# =============================================================================
# gwt.psm1 — Git Worktree 互動式切換工具（PowerShell 7 / pwsh 版）
# =============================================================================
#
# 這是 gwt.zsh 的 PowerShell 移植版，行為、按鍵、設定項、結束碼都與 zsh 版對齊。
#
# 一定要是「載入到目前工作階段的模組」，不能是獨立的 .ps1：獨立腳本跑在子處理序，
# 它的 Set-Location 影響不到呼叫它的終端機。模組函式則跑在目前的工作階段裡，
# Set-Location 會真的改變你的位置（也保留 `cd -` 的歷史）。
#
# 用法：
#   Import-Module ./gwt.psm1     # 或由 install.ps1 寫進 $PROFILE
#   gwt                          # 列出所有 worktree 並選擇
#   gwt feature                  # 用關鍵字篩選
#
# 模組只匯出 gwt 這一個命令；其餘函式與狀態都留在模組作用域，不會污染使用者
# 的命名空間（相當於 zsh 版的 _gwt_ 前綴與 emulate -L zsh）。
#
# 需要 PowerShell 7.0 以上與 Git。Windows PowerShell 5.1 不支援。
# =============================================================================
#Requires -Version 7.0

Set-StrictMode -Version 3.0

$script:GwtVersion = '0.2.0'

# -----------------------------------------------------------------------------
# 測試用的掛鉤（正常使用時全部是 $null，走真正的主控台）
#
# ReadKey      scriptblock，回傳 [ConsoleKeyInfo]；回傳 $null 代表輸入結束（EOF）
# KeyAvailable scriptblock，回傳 [bool]；未設定時由 ReadKey 掛鉤無法判斷，視為 $false
# Write        scriptblock，接收一整個畫面的文字；測試用它收集輸出
# Interactive  $null = 照實檢查；$true = 假裝是互動式終端機；$false = 假裝不是
# -----------------------------------------------------------------------------
$script:Hooks = @{ ReadKey = $null; KeyAvailable = $null; Write = $null; Interactive = $null }

# -----------------------------------------------------------------------------
# 狀態（變數一律放在模組作用域）
# 索引維持與 zsh 版相同的「1 起算」，方便逐行對照；取陣列元素時才減 1。
# -----------------------------------------------------------------------------
$script:M = @{}
$script:HelpText = ''
$script:Paths = [System.Collections.Generic.List[string]]::new()
$script:Branches = [System.Collections.Generic.List[string]]::new()
$script:Heads = [System.Collections.Generic.List[string]]::new()
# 完整候選清單（已套用命令列關鍵字），互動搜尋時從這裡重新篩選
$script:AllPaths = [System.Collections.Generic.List[string]]::new()
$script:AllBranches = [System.Collections.Generic.List[string]]::new()
$script:AllHeads = [System.Collections.Generic.List[string]]::new()
$script:Count = 0
$script:Selected = 0
$script:Drawn = 0
$script:Width = 80
$script:Height = 24
$script:Visible = 0
$script:Top = 1
$script:Scrolled = $false
$script:Search = $false
$script:Query = ''
$script:Current = ''
$script:PendingKey = $null
$script:Style = @{ Reset = ''; Bar = ''; Branch = ''; Mark = ''; Dim = '' }
$script:Buf = [System.Text.StringBuilder]::new()
$script:CSI = [string][char]27 + '['
$script:AsciiOnly = [regex]::new('^[\x00-\x7F]*$')
# 寬度為 2 的「基本多文種平面」（BMP）字元：Unicode 的 East Asian Width 是 W（Wide）或 F（Fullwidth）。
# 不只是 CJK：⚡ ⌚ ⌛ ✅ ❌ ⭐ ⭕ 這類 emoji 符號也在基本多文種平面，卻不在 CJK 範圍裡，一樣佔 2 欄。
# 只有 CJK 範圍的表（0.2.1 以前的 zsh 版是這樣）會把它們當成 1 欄，一列就比算出來的寬，折行之後重繪與收尾
# 的列數對不上。基本多文種平面以外的字元（代理對，例如 🔥 與 CJK 擴充區）由 Get-GwtWidth 另外處理，一律 2 欄。
# 測試用另一份獨立的實作與逐字寫死的 Unicode 標準答案對照（tests/pwsh/lib/WidthOracle.ps1）。
# gwt.zsh 的 _GWT_WIDE 是從這張表機械轉換來的，兩邊逐字相同：改這裡就要一起改那裡。
$script:WideBmp = [regex]::new(
  '[ᄀ-ᅟ⌚⌛〈〉⏩-⏬⏰⏳◽◾☔☕♈-♓♿⚓' +
  '⚡⚪⚫⚽⚾⛄⛅⛎⛔⛪⛲⛳⛵⛺⛽✅✊✋✨' +
  '❌❎❓-❕❗➕-➗➰➿⬛⬜⭐⭕⺀-〾ぁ-꓏' +
  'ꥠ-꥿가-힣豈-﫿︐-︙︰-﹯＀-｠￠-￦]')
$script:AnsiSgr = [regex]::new("\x1b\[[0-9;]*m")

# -----------------------------------------------------------------------------
# 使用者設定：全部是環境變數（$env:GWT_LANG = 'en'）
# 空字串視為沒設定，與 zsh 版的 ${VAR:-default} 一致
# -----------------------------------------------------------------------------
function Get-GwtEnv {
  param([string]$Name, [string]$Default)
  $v = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrEmpty($v)) { return $Default }
  return $v
}

function Get-GwtInt {
  param([string]$Name, [int]$Default)
  $n = 0
  if ([int]::TryParse((Get-GwtEnv $Name ''), [ref]$n)) { return $n }
  return $Default
}

function Get-GwtSeconds {
  param([string]$Name, [double]$Default)
  $n = 0.0
  $ok = [double]::TryParse((Get-GwtEnv $Name ''), [System.Globalization.NumberStyles]::Float,
    [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)
  if ($ok -and $n -ge 0) { return $n }
  return $Default
}

function Test-GwtFlag {
  param([string]$Name, [int]$Default)
  return ((Get-GwtInt $Name $Default) -ne 0)
}

# -----------------------------------------------------------------------------
# 介面文字（格式字串只用 {0} 這類位置參數；使用者的資料一律當作「參數」，
# 絕不拿分支名稱或路徑當格式字串，否則含 {0} 的分支名稱會被誤解讀）
# -----------------------------------------------------------------------------
function Initialize-GwtMessages {
  $m = @{}
  if ((Get-GwtEnv 'GWT_LANG' 'zh').ToLowerInvariant() -eq 'en') {
    $m.not_repo = 'gwt: not inside a Git repository.'
    $m.no_git = 'gwt: git was not found in PATH.'
    $m.no_match = 'gwt: no worktree matched "{0}".'
    $m.no_worktrees = 'gwt: this repository has no other worktree.'
    $m.not_tty = 'gwt: an interactive terminal is required.'
    $m.no_vt = 'gwt: this terminal does not support ANSI escape sequences.'
    $m.bad_opt = 'gwt: unknown option: {0}'
    $m.mark = '(current)'
    $m.detached = 'detached'
    $m.header = 'Select a worktree (↑/↓ move, Enter confirm, / search, 1-{0} jump, q/Esc cancel):'
    $m.search = 'Search: {0}▏  {1} match(es) (↑/↓ move, Enter confirm, Esc clear):'
    $m.search_none = 'No worktree matches this search.'
    $m.range = 'showing {0}-{1} of {2}'
    $script:HelpText = @'
Usage: gwt [options] [keyword]

Switch between all worktrees of the current Git repository by changing the
working directory of the shell you are in.

Options:
  -l, --list     only print matching worktree paths, one per line
  -h, --help     show this help
  -V, --version  show version

Keys:
  ↑/↓, k/j       move up and down (wraps around)
  1-9            jump to that number and switch immediately
  /              fuzzy search branch names and the last path component
  Enter          switch to the highlighted worktree
  q, Esc         cancel

While searching, ↑/↓ still move, Enter still confirms, and Esc clears the
search instead of cancelling the menu. Backspace edits the query, Ctrl+U
clears it, and Ctrl+W deletes the last word.

Keyword: matched against "path + branch". When exactly one worktree matches,
         gwt switches to it directly without showing the menu.

Environment (set with $env:NAME = 'value'):
  GWT_LANG                     UI language (zh / en, default zh)
  GWT_CLEAR_ON_EXIT            erase the menu after leaving (1/0, default 1)
  GWT_FILTER_CASE_INSENSITIVE  case-insensitive keyword match (1/0, default 1)
  GWT_DIGIT_TIMEOUT            seconds to wait for a second digit (default 0.4)
  GWT_NO_COLOR                 disable colors (1/0, default 0)
  GWT_WIDTH                    menu width in columns (0 = auto)
  GWT_HEIGHT                   menu height in rows (0 = auto; a shorter
                               list is shown in a scrolling window)

Exit status: $LASTEXITCODE is 0 on success, 1 on cancel or error, 2 on an
unknown option, 130 on Ctrl+C. `$?` is false for every non-zero status, so
`gwt && next-command` stops after a cancel.
'@
  }
  else {
    $m.not_repo = 'gwt: 目前目錄不在 Git 儲存庫中。'
    $m.no_git = 'gwt: 找不到 git，請先安裝並確認它在 PATH 裡。'
    $m.no_match = 'gwt: 找不到符合「{0}」的 worktree。'
    $m.no_worktrees = 'gwt: 這個儲存庫沒有其他 worktree。'
    $m.not_tty = 'gwt: 需要在互動式終端機中執行。'
    $m.no_vt = 'gwt: 這個終端機不支援 ANSI 跳脫序列。'
    $m.bad_opt = 'gwt: 未知的選項：{0}'
    $m.mark = '(目前位置)'
    $m.detached = 'detached'
    $m.header = '請選擇 Worktree (↑/↓ 移動, Enter 確認, / 搜尋, 按 1-{0} 直接跳轉, q/Esc 取消)：'
    $m.search = '搜尋：{0}▏  {1} 筆符合 (↑/↓ 移動, Enter 確認, Esc 清除搜尋)：'
    $m.search_none = '沒有符合搜尋條件的 worktree。'
    $m.range = '顯示 {0}-{1}，共 {2} 筆'
    $script:HelpText = @'
用法：gwt [選項] [關鍵字]

在目前 Git 儲存庫的所有 worktree 之間互動式切換，
直接改變目前這個 shell 的工作目錄。

選項：
  -l, --list     僅列出符合的 worktree 路徑（每行一筆）
  -h, --help     顯示本說明
  -V, --version  顯示版本

按鍵：
  ↑/↓, k/j       上下移動（到頭尾會循環）
  1-9            直接跳到該編號並切換，不需要按 Enter
  /              模糊搜尋分支名稱與目錄名稱（只比對路徑的最後一層）
  Enter          切換到反白的 worktree
  q, Esc         取消

搜尋模式中 ↑/↓ 仍可移動、Enter 仍可確認，Esc 改為清除搜尋（不會直接取消
選單）。Backspace 刪除一個字元，Ctrl+U 清空，Ctrl+W 刪除最後一個詞。

關鍵字：比對「路徑 + 分支名稱」整串文字。
        只有一筆符合時，不顯示選單，直接切換過去。

環境變數（用 $env:名稱 = '值' 設定）：
  GWT_LANG                    介面語言（zh / en，預設 zh）
  GWT_CLEAR_ON_EXIT           選完後擦掉選單（1/0，預設 1）
  GWT_FILTER_CASE_INSENSITIVE 關鍵字不分大小寫（1/0，預設 1）
  GWT_DIGIT_TIMEOUT           多位數編號的等待秒數（預設 0.4）
  GWT_NO_COLOR                關閉顏色（1/0，預設 0）
  GWT_WIDTH                   選單寬度（0 = 自動偵測）
  GWT_HEIGHT                  選單可用高度（0 = 自動偵測，
                              清單較高時只顯示一個會捲動的視窗）

結束狀態：$LASTEXITCODE 成功為 0、取消或錯誤為 1、未知選項為 2、Ctrl+C 為 130。
非 0 時 `$?` 一律為 false，所以 `gwt && 下一個指令` 在取消之後不會繼續。
'@
  }
  $script:M = $m
}

function Reset-GwtState {
  $script:Paths.Clear()
  $script:Branches.Clear()
  $script:Heads.Clear()
  $script:AllPaths.Clear()
  $script:AllBranches.Clear()
  $script:AllHeads.Clear()
  $script:Count = 0
  $script:Selected = 0
  $script:Drawn = 0
  $script:Height = 24
  $script:Visible = 0
  $script:Top = 1
  $script:Scrolled = $false
  $script:Search = $false
  $script:Query = ''
  $script:Current = ''
  $script:PendingKey = $null
  [void]$script:Buf.Clear()
}

# -----------------------------------------------------------------------------
# 輸出：整個畫面先組成一個字串再一次寫出，避免逐列輸出造成閃爍。
# 這裡刻意用 $Host.UI.Write 而不是 [Console]::Out：後者會依主控台的輸出
# 字碼頁編碼（例如繁中 Windows 的 950），ASCII 以外的字元（▏ … ↑↓）會變成 ?；
# 前者直接寫 UTF-16，不受字碼頁影響。
# -----------------------------------------------------------------------------
function Add-GwtText {
  param([string]$Text)
  [void]$script:Buf.Append($Text)
}

function Send-GwtFrame {
  if ($script:Buf.Length -eq 0) { return }
  $text = $script:Buf.ToString()
  [void]$script:Buf.Clear()
  if ($null -ne $script:Hooks.Write) {
    & $script:Hooks.Write $text
  }
  else {
    $Host.UI.Write($text)
  }
}

# -----------------------------------------------------------------------------
# 寬度計算：ANSI 跳脫序列不佔欄寬，CJK 全形字佔兩欄
# -----------------------------------------------------------------------------
function Remove-GwtAnsi {
  param([string]$Text)
  return $script:AnsiSgr.Replace($Text, '')
}

# 字串在終端機上的欄寬。純 ASCII 走快速路徑（每次按鍵都要重算，PowerShell 的
# 逐字元迴圈很慢，不能每列都跑）。
#
# 每個 UTF-16 單位算 1 欄：基本多文種平面以外的字元（代理對，例如 🔥 與 CJK 擴充區）是兩個單位，所以自然
# 是 2 欄；再為「基本多文種平面裡寬度為 2 的字元」（CJK、全形、⚡ ⌚ ✅ 這類 emoji 符號）各加 1 欄。
# 用一個正規表示式一次掃完，不逐字元跑迴圈。
function Get-GwtWidth {
  param([string]$Text)
  if ($script:AsciiOnly.IsMatch($Text)) { return $Text.Length }
  return $Text.Length + $script:WideBmp.Matches($Text).Count
}

# 把過長的字串從中截斷成 budget 欄寬：保留頭 1/3、尾 2/3，中間放省略號。
# 工作目錄的結尾（shop-feature-login）比前面的共同路徑有用，所以留比較多尾段。
function Get-GwtClipped {
  param([string]$Text, [int]$Budget)
  if ((Get-GwtWidth $Text) -le $Budget) { return $Text }
  if ($Budget -lt 3) { return '…' }

  $keep = $Budget - 1
  $tailw = [int][math]::Floor($keep * 2 / 3)
  $headw = $keep - $tailw

  if ($script:AsciiOnly.IsMatch($Text)) {
    return $Text.Substring(0, $headw) + '…' + $Text.Substring($Text.Length - $tailw)
  }

  # 以「字」為單位（代理對算一個字），避免把 emoji 從中間切開
  $units = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $Text.Length; $i++) {
    if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1 -lt $Text.Length) -and [char]::IsLowSurrogate($Text[$i + 1])) {
      $units.Add($Text.Substring($i, 2))
      $i++
    }
    else {
      $units.Add([string]$Text[$i])
    }
  }

  $head = ''
  $left = $headw
  foreach ($u in $units) {
    $w = Get-GwtWidth $u
    if ($w -gt $left) { break }
    $head += $u
    $left -= $w
  }
  $tail = ''
  $left = $tailw
  for ($j = $units.Count - 1; $j -ge 0; $j--) {
    $w = Get-GwtWidth $units[$j]
    if ($w -gt $left) { break }
    $tail = $units[$j] + $tail
    $left -= $w
  }
  return $head + '…' + $tail
}

# 高度與寬度一起量。直接問主控台視窗（不是 BufferHeight：緩衝區可以遠大於視窗）。
function Initialize-GwtSize {
  $h = Get-GwtInt 'GWT_HEIGHT' 0
  $w = Get-GwtInt 'GWT_WIDTH' 0
  if ($h -le 0 -or $w -le 0) {
    $wh = 0
    $ww = 0
    try {
      $wh = [Console]::WindowHeight
      $ww = [Console]::WindowWidth
    }
    catch {
      $wh = 0
      $ww = 0
    }
    if ($h -le 0) {
      $h = $wh
      if ($h -le 0) { $h = Get-GwtInt 'LINES' 0 }
      if ($h -le 0) { $h = 24 }
    }
    if ($w -le 0) {
      $w = $ww
      if ($w -le 0) { $w = Get-GwtInt 'COLUMNS' 0 }
      if ($w -le 0) { $w = 80 }
    }
  }
  if ($h -lt 6) { $h = 6 }
  # 多留一欄，避免最後一欄剛好觸發終端機自動換行
  # 下限 16（17 欄的終端機）：再窄，連 前綴 + 最短的路徑 都放不下，只能折行（zsh 版 0.2.1 起相同）
  $w = $w - 1
  if ($w -lt 16) { $w = 16 }
  $script:Height = $h
  $script:Width = $w
}

# 決定這次要畫哪幾列。重點：表頭 + 可視列 + 提示列 + 游標那一列，
# 加起來不能超過終端機高度，否則終端機會上捲，而「游標往上 N 行」
# 在畫面頂端會被夾住，重繪就整個錯位。
function Update-GwtLayout {
  if ($script:Count + 2 -le $script:Height) {
    $script:Visible = $script:Count
    $script:Scrolled = $false
  }
  else {
    $avail = $script:Height - 3     # 表頭 1 + 提示列 1 + 游標那一列 1
    if ($avail -lt 1) { $avail = 1 }
    $script:Visible = $avail
    $script:Scrolled = $true
  }

  # 讓選取項目永遠留在可視範圍內
  if ($script:Selected -lt $script:Top) {
    $script:Top = $script:Selected
  }
  elseif ($script:Selected -gt $script:Top + $script:Visible - 1) {
    $script:Top = $script:Selected - $script:Visible + 1
  }
  if ($script:Top -lt 1) { $script:Top = 1 }
  $maxTop = $script:Count - $script:Visible + 1
  if ($maxTop -lt 1) { $maxTop = 1 }
  if ($script:Top -gt $maxTop) { $script:Top = $maxTop }
}

function Initialize-GwtStyle {
  $use = $true
  if (Test-GwtFlag 'GWT_NO_COLOR' 0) { $use = $false }
  if (-not [string]::IsNullOrEmpty($env:NO_COLOR)) { $use = $false }
  if ($use -and $null -eq $script:Hooks.Interactive -and [Console]::IsOutputRedirected) { $use = $false }
  $e = $script:CSI
  if ($use) {
    $script:Style = @{
      Reset  = "${e}0m"
      Bar    = "${e}1;30;46m"     # 粗體 + 黑字 + 青色底：選取光棒
      Branch = "${e}36m"          # 青色：分支名稱
      Mark   = "${e}33m"          # 黃色：目前位置
      Dim    = "${e}2m"           # 暗色：顯示範圍提示
    }
  }
  else {
    $script:Style = @{ Reset = ''; Bar = ''; Branch = ''; Mark = ''; Dim = '' }
  }
}

# -----------------------------------------------------------------------------
# 呼叫 git
# 用 System.Diagnostics.Process 而不是 & git，原因有三：
#   1. 輸出以 UTF-8 解碼。git 輸出 UTF-8，但 PowerShell 預設用主控台字碼頁解碼
#      原生命令的輸出（繁中 Windows 是 950），路徑或分支名稱含中文就會變成亂碼。
#      改 [Console]::OutputEncoding 會動到全域狀態，這裡不碰。
#   2. 不會動到 $?、$Error，也不受使用者的 $ErrorActionPreference 或
#      $PSNativeCommandUseErrorActionPreference 影響（在非 repo 目錄 rev-parse
#      會失敗，那是預期中的結果，不該變成例外）。
#   3. stdout 與 stderr 分開收，stderr 不會漏到畫面上。
# 注意 WorkingDirectory：Set-Location 不會改 [Environment]::CurrentDirectory，
# 必須明確帶 PowerShell 目前的檔案系統位置，否則 git 會在錯的目錄執行。
# -----------------------------------------------------------------------------
function Invoke-GwtGit {
  param([string[]]$GitArguments)
  $result = [pscustomobject]@{ ExitCode = 127; Output = '' }
  $cmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $cmd) { return $result }

  $utf8 = [System.Text.UTF8Encoding]::new($false)
  $psi = [System.Diagnostics.ProcessStartInfo]::new($cmd.Source)
  foreach ($a in $GitArguments) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $psi.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath

  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi
  try {
    [void]$proc.Start()
    $proc.StandardInput.Close()
    # 兩個串流都用非同步讀，避免其中一個塞滿緩衝區造成死結
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    [void]$errTask.Result
    $result.Output = $outTask.Result
    $result.ExitCode = $proc.ExitCode
  }
  catch {
    $result.ExitCode = 127
  }
  finally {
    $proc.Dispose()
  }
  return $result
}

# 同一個路徑嗎？兩邊都來自 git，已經是同一種寫法；Windows 的檔名不分大小寫。
function Test-GwtSamePath {
  param([string]$A, [string]$B)
  $a1 = $A.TrimEnd('\', '/')
  $b1 = $B.TrimEnd('\', '/')
  if ($IsWindows) {
    return [string]::Equals($a1, $b1, [System.StringComparison]::OrdinalIgnoreCase)
  }
  return [string]::Equals($a1, $b1, [System.StringComparison]::Ordinal)
}

# git 在 Windows 輸出正斜線（C:/Users/...）。PowerShell 的提示字元與 Get-Location
# 都是反斜線，選單與 --list 也跟著用原生分隔符，看起來才一致。
function ConvertTo-GwtNativePath {
  param([string]$Path)
  if ($IsWindows) { return $Path.Replace('/', '\') }
  return $Path
}

# -----------------------------------------------------------------------------
# 解析 git worktree list --porcelain
# -----------------------------------------------------------------------------
# 每個 worktree 是一組以空行分隔的資料：
#   worktree /path/to/shop
#   HEAD 89ae97a...
#   branch refs/heads/main        （detached HEAD 時改為一行 detached）
# 逐行比對前綴，遇到空行才把這一組收進清單，所以路徑含空白也不會被切開。
function Read-GwtPorcelain {
  param([string]$Text, [string]$Keyword)
  $wtPath = ''
  $head = ''
  $branch = ''
  # 補一個空行，確保最後一組資料一定會被收進清單
  $lines = @($Text -split "\r?\n") + ''
  foreach ($line in $lines) {
    if ($line.StartsWith('worktree ', [System.StringComparison]::Ordinal)) {
      $wtPath = $line.Substring(9)
    }
    elseif ($line.StartsWith('HEAD ', [System.StringComparison]::Ordinal)) {
      $head = $line.Substring(5)
    }
    elseif ($line.StartsWith('branch ', [System.StringComparison]::Ordinal)) {
      $branch = $line.Substring(7)
      if ($branch.StartsWith('refs/heads/', [System.StringComparison]::Ordinal)) {
        $branch = $branch.Substring(11)
      }
    }
    elseif ($line -ceq 'detached') {
      $branch = $script:M.detached
    }
    elseif ($line -eq '') {
      # locked / prunable / bare 這類附註行不影響選單，直接略過
      if ($wtPath -ne '') {
        Add-GwtWorktree -Keyword $Keyword -WtPath $wtPath -Branch $branch -Head $head
      }
      $wtPath = ''
      $head = ''
      $branch = ''
    }
  }
  $script:Count = $script:Paths.Count
}

function Add-GwtWorktree {
  param([string]$Keyword, [string]$WtPath, [string]$Branch, [string]$Head)
  $display = ConvertTo-GwtNativePath $WtPath
  if ($Keyword -ne '') {
    # IndexOf 是純文字比對，* ? [ 等字元不會被當成萬用字元
    $cmp = if (Test-GwtFlag 'GWT_FILTER_CASE_INSENSITIVE' 1) {
      [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
      [System.StringComparison]::Ordinal
    }
    if ("$display $Branch".IndexOf($Keyword, $cmp) -lt 0) { return }
  }
  $script:Paths.Add($display)
  $script:Branches.Add($Branch)
  $script:Heads.Add($Head.Substring(0, [math]::Min(7, $Head.Length)))
}

# -----------------------------------------------------------------------------
# 模糊搜尋
# -----------------------------------------------------------------------------
# 與 gwt.zsh 的 _gwt_fuzzy_*、site/assets/app.js 的 fuzzyTerm/fuzzyMatch 是同一套
# 規則的第三份實作，三邊必須一起改（見 docs/design-notes.md 第 16 節）。
#
# 互動搜尋只比對「分支名稱」與「路徑的最後一層目錄」，不比對完整路徑，
# 避免 C:\Users\... 這種共同前綴讓每一筆都符合。
#
# 比對方式是子序列（subsequence）：查詢字元依序出現在候選字串裡就算符合，
# 所以 "flogin" 可以找到 feature/login。分數用來排序，規則大致是：
#   - 連續命中的加成最高（越長越好）
#   - 命中在字首或分隔符（/ - _ . 空白）之後額外加分
#   - 跳過太多字元要扣分，候選字串越長也會被小幅扣分
#
# 注意：PowerShell 的 -eq 比對字元時不分大小寫，所以這裡一律用 -ceq；
# 是否分大小寫由事先轉小寫與否決定。

# 單一詞彙比對。符合時回傳分數（可能為負），不符合回傳 $null。
function Get-GwtFuzzyTermScore {
  param([string]$Hay, [string]$Term)
  if (Test-GwtFlag 'GWT_FILTER_CASE_INSENSITIVE' 1) {
    $Hay = $Hay.ToLowerInvariant()
    $Term = $Term.ToLowerInvariant()
  }
  $hl = $Hay.Length
  $tl = $Term.Length
  if ($tl -eq 0) { return 0 }

  $hi = 0
  $score = 0
  $last = -1
  $run = 0
  for ($ti = 0; $ti -lt $tl; $ti++) {
    $ch = $Term[$ti]
    while ($hi -lt $hl -and $Hay[$hi] -cne $ch) { $hi++ }
    if ($hi -ge $hl) { return $null }

    $score += 10
    if ($last -ge 0) {
      if ($hi -eq $last + 1) {
        $run++
        $score += 6 + $run * 2
      }
      else {
        $run = 0
        $skipped = $hi - $last - 1
        # 中間跳過的字元越多越不像，但最多只扣 4 分，避免長名稱永遠排最後
        $score -= [math]::Min($skipped, 4)
      }
    }

    if ($hi -eq 0) {
      $score += 14
    }
    else {
      $prev = $Hay[$hi - 1]
      if ($prev -ceq '/' -or $prev -ceq '-' -or $prev -ceq '_' -or $prev -ceq '.' -or $prev -ceq ' ') {
        $score += 10
      }
    }
    $last = $hi
    $hi++
  }

  # 候選字串越長，同樣的命中越不精確
  $score -= [int][math]::Floor($hl / 5)
  return $score
}

# 整串查詢比對：以空白切成多個詞，每個詞都必須命中分支或目錄名稱（AND）。
# 符合時回傳總分，不符合回傳 $null。
function Get-GwtFuzzyScore {
  param([string]$Branch, [string]$Base, [string]$Query)
  $terms = @($Query -split ' ' | Where-Object { $_ -ne '' })
  if ($terms.Count -eq 0) { return 0 }

  $total = 0
  foreach ($term in $terms) {
    $sb = Get-GwtFuzzyTermScore $Branch $term
    $sa = Get-GwtFuzzyTermScore $Base $term
    if ($null -eq $sb -and $null -eq $sa) { return $null }
    if ($null -ne $sb -and ($null -eq $sa -or $sb -ge $sa)) {
      $total += $sb
    }
    else {
      $total += $sa
    }
  }
  return $total
}

# 記住命令列關鍵字篩選後的完整清單，互動搜尋才不會愈搜愈少。
function Save-GwtSnapshot {
  $script:AllPaths = [System.Collections.Generic.List[string]]::new($script:Paths)
  $script:AllBranches = [System.Collections.Generic.List[string]]::new($script:Branches)
  $script:AllHeads = [System.Collections.Generic.List[string]]::new($script:Heads)
}

# 依 Query 重新產生目前顯示的清單，並依分數排序（同分維持 Git 的順序）。
function Update-GwtFilter {
  $n = $script:AllPaths.Count
  $script:Paths = [System.Collections.Generic.List[string]]::new()
  $script:Branches = [System.Collections.Generic.List[string]]::new()
  $script:Heads = [System.Collections.Generic.List[string]]::new()
  $script:Count = 0

  if ([string]::IsNullOrWhiteSpace($script:Query.Replace(' ', ''))) {
    $script:Paths.AddRange($script:AllPaths)
    $script:Branches.AddRange($script:AllBranches)
    $script:Heads.AddRange($script:AllHeads)
    $script:Count = $n
    return
  }

  $ranked = [System.Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $n; $i++) {
    $base = [System.IO.Path]::GetFileName($script:AllPaths[$i].TrimEnd('\', '/'))
    $score = Get-GwtFuzzyScore $script:AllBranches[$i] $base $script:Query
    if ($null -eq $score) { continue }
    if ($score -lt 0) { $score = 0 }
    $ranked.Add([pscustomobject]@{ Score = $score; Index = $i })
  }

  # 分數遞減；同分時維持 Git 原本的順序（索引遞增）
  $ordered = $ranked | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Index'; Descending = $false }
  foreach ($r in $ordered) {
    $script:Paths.Add($script:AllPaths[$r.Index])
    $script:Branches.Add($script:AllBranches[$r.Index])
    $script:Heads.Add($script:AllHeads[$r.Index])
    $script:Count++
  }
}

# 查詢改變後重設游標：永遠從最佳的那一筆開始。
function Invoke-GwtSearchApply {
  Update-GwtFilter
  $script:Selected = if ($script:Count -gt 0) { 1 } else { 0 }
  $script:Top = 1
}

# 離開搜尋模式，恢復完整清單（Esc 在搜尋模式裡做這件事，不是取消選單）。
function Exit-GwtSearch {
  $script:Search = $false
  $script:Query = ''
  Update-GwtFilter
  $script:Selected = if ($script:Count -gt 0) { 1 } else { 0 }
  $script:Top = 1
}

# -----------------------------------------------------------------------------
# 畫面
# -----------------------------------------------------------------------------
# 產生第 i 列的文字。
# 光棒只反白到路徑為止，分支與狀態維持原色，方便一眼辨識。
# 每一列都必須控制在一個實體行內，否則折行會讓「往上移 N 行」算錯。
# 預算分配：前綴 → 間隔 2 欄 → 後方資訊 → 剩下的全部給路徑（至少 12 欄）。
function Format-GwtRow {
  param([int]$Index)
  $isSelected = ($Index -eq $script:Selected)
  $wtPath = $script:Paths[$Index - 1]
  $branch = $script:Branches[$Index - 1]
  $head = $script:Heads[$Index - 1]
  $st = $script:Style

  $prefix = if ($isSelected) { " > [$Index] " } else { "   [$Index] " }

  $gap = 2
  $tailBudget = $script:Width - $prefix.Length - $gap - 12
  if ($tailBudget -lt 8) { $tailBudget = 8 }

  # 目前位置標註：空間不夠就省略，優先保留路徑與分支
  $mark = ''
  if ($script:Current -ne '' -and (Test-GwtSamePath $wtPath $script:Current)) {
    $markWidth = Get-GwtWidth $script:M.mark
    if ($markWidth + 1 -le $tailBudget - 12) {
      $mark = $script:M.mark
      $tailBudget -= $markWidth + 1
    }
  }

  # [branch] (commit) 的固定成本是 12 欄：'[' ']' 空白 '(' 7 碼 ')'
  $branchBudget = $tailBudget - 12
  if ($branchBudget -lt 1) { $branchBudget = 1 }
  $branchShown = Get-GwtClipped $branch $branchBudget

  $suffix = $st.Branch + '[' + $branchShown + ']' + $st.Reset + ' (' + $head + ')'
  if ($mark -ne '') { $suffix += ' ' + $st.Mark + $mark + $st.Reset }

  $avail = $script:Width - $prefix.Length - $gap - (Get-GwtWidth (Remove-GwtAnsi $suffix))

  # 完整的後方資訊放不下（路徑連最短的 4 欄都分不到）時，不能硬塞：一列折成兩行，
  # 重繪與收尾算的列數就會錯，畫面留下殘影。依序省略：先拿掉 commit 只留 [分支]，
  # 再放不下就連分支都拿掉，整列只剩編號與路徑。
  $minPath = 4
  if ($avail -lt $minPath) {
    $room = $script:Width - $prefix.Length - $gap - $minPath - 2     # 扣掉 [ ] 兩欄
    if ($room -ge 1) {
      $suffix = $st.Branch + '[' + (Get-GwtClipped $branch $room) + ']' + $st.Reset
      $avail = $script:Width - $prefix.Length - $gap - (Get-GwtWidth (Remove-GwtAnsi $suffix))
    }
    else {
      $suffix = ''
      $avail = $script:Width - $prefix.Length
    }
  }
  if ($avail -lt 1) { $avail = 1 }
  $shown = Get-GwtClipped $wtPath $avail

  if ($isSelected) {
    # 光棒只反白到路徑為止，後方分支與狀態維持原色
    if ($suffix -eq '') { return $st.Bar + $prefix + $shown + $st.Reset }
    return $st.Bar + $prefix + $shown + ' ' + $st.Reset + ' ' + $suffix
  }
  if ($suffix -eq '') { return $prefix + $shown }
  return $prefix + $shown + '  ' + $suffix
}

# 表頭只佔一列，而且每次重畫都要先清掉整列，避免搜尋字串變短時留下殘影。
function Add-GwtHeader {
  if ($script:Search) {
    $text = $script:M.search -f $script:Query, $script:Count
  }
  else {
    $text = $script:M.header -f $script:Count
  }
  $text = Get-GwtClipped $text $script:Width
  Add-GwtText "`r$($script:CSI)2K$text`n"
}

function Add-GwtList {
  Update-GwtLayout
  $st = $script:Style
  $csi = $script:CSI

  if ($script:Count -eq 0) {
    $text = Get-GwtClipped $script:M.search_none $script:Width
    Add-GwtText "`r${csi}2K$($st.Dim)$text$($st.Reset)`n"
    $script:Drawn = 1
    return
  }

  $last = $script:Top + $script:Visible - 1
  if ($last -gt $script:Count) { $last = $script:Count }

  for ($i = $script:Top; $i -le $last; $i++) {
    Add-GwtText "`r${csi}2K"
    Add-GwtText (Format-GwtRow $i)
    Add-GwtText "`n"
  }
  $script:Drawn = $last - $script:Top + 1

  if ($script:Scrolled) {
    $text = $script:M.range -f $script:Top, $last, $script:Count
    $text = Get-GwtClipped $text ($script:Width - 3)
    Add-GwtText "`r${csi}2K$($st.Dim)   $text$($st.Reset)`n"
    $script:Drawn++
  }
}

# 回到表頭那一列，重畫表頭與清單。表頭會隨搜尋字串改變，所以不能只畫清單。
# 一定要先 ESC[J 清到畫面結尾：搜尋讓清單變短時，舊的列還在游標下方，
# 只畫新的列會留下殘影，看起來就像清單沒有跟著篩選。
function Invoke-GwtRepaint {
  Update-GwtLayout
  Add-GwtText "$($script:CSI)$($script:Drawn + 1)A$($script:CSI)J"
  Add-GwtHeader
  Add-GwtList
  Send-GwtFrame
}

# 收尾：視需要擦掉選單、把游標還給使用者。
# 不論是 Enter、數字鍵、q/Esc、Ctrl+C 或讀不到輸入，都必須經過這裡。
function Complete-GwtMenu {
  if ((Test-GwtFlag 'GWT_CLEAR_ON_EXIT' 1) -and $script:Drawn -gt 0) {
    Add-GwtText "$($script:CSI)$($script:Drawn + 1)A$($script:CSI)J"
  }
  Add-GwtText "$($script:CSI)?25h"
  Send-GwtFrame
}

function Move-GwtSelection {
  param([int]$Delta)
  if ($script:Count -eq 0) { return }
  $script:Selected += $Delta
  if ($script:Selected -gt $script:Count) {
    $script:Selected = 1
  }
  elseif ($script:Selected -lt 1) {
    $script:Selected = $script:Count
  }
}

# -----------------------------------------------------------------------------
# 按鍵
# -----------------------------------------------------------------------------
# 把 [ConsoleKeyInfo] 整理成 @{ Name; Char }。Name 是：
#   Up Down Enter Escape Backspace CtrlC CtrlU CtrlW Control（其他控制鍵） Char（可列印字元）
# [Console]::ReadKey 直接給方向鍵與 Esc，不必像 zsh 那樣解析 ESC [ A 序列，
# 也就不需要 GWT_ESC_TIMEOUT。
function ConvertTo-GwtKey {
  param([System.ConsoleKeyInfo]$Info)
  $c = $Info.KeyChar
  $ctrl = (($Info.Modifiers -band [System.ConsoleModifiers]::Control) -ne 0)
  $name = 'Char'
  switch ($Info.Key) {
    'UpArrow' { $name = 'Up' }
    'DownArrow' { $name = 'Down' }
    'Escape' { $name = 'Escape' }
    'Enter' { $name = 'Enter' }
    'Backspace' { $name = 'Backspace' }
    default {
      if ($c -ceq [char]3 -or ($ctrl -and $Info.Key -eq 'C')) { $name = 'CtrlC' }
      elseif ($c -ceq [char]21 -or ($ctrl -and $Info.Key -eq 'U')) { $name = 'CtrlU' }
      elseif ($c -ceq [char]23 -or ($ctrl -and $Info.Key -eq 'W')) { $name = 'CtrlW' }
      elseif ($c -ceq "`r" -or $c -ceq "`n") { $name = 'Enter' }
      elseif ($c -ceq [char]127 -or $c -ceq [char]8) { $name = 'Backspace' }
      elseif ([char]::IsControl($c) -or $c -ceq [char]0) { $name = 'Control' }
    }
  }
  return @{ Name = $name; Char = [string]$c }
}

# 讀一個按鍵；輸入結束時回傳 $null。
function Read-GwtKey {
  if ($null -ne $script:Hooks.ReadKey) {
    $info = & $script:Hooks.ReadKey
  }
  else {
    $info = [Console]::ReadKey($true)
  }
  if ($null -eq $info) { return $null }
  return ConvertTo-GwtKey $info
}

function Test-GwtKeyAvailable {
  if ($null -ne $script:Hooks.KeyAvailable) { return [bool](& $script:Hooks.KeyAvailable) }
  if ($null -ne $script:Hooks.ReadKey) { return $false }
  return [Console]::KeyAvailable
}

# 最多等 Seconds 秒，看有沒有按鍵進來。
function Wait-GwtKey {
  param([double]$Seconds)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while (-not (Test-GwtKeyAvailable)) {
    if ($sw.Elapsed.TotalSeconds -ge $Seconds) { return $false }
    Start-Sleep -Milliseconds 5
  }
  return $true
}

# 數字鍵：worktree 超過 9 個時，再等一小段時間看是否還有第二位數字。
# 例如清單有 12 筆時，按 1 再按 2 會跳到第 12 筆；只按 1 則等 timeout 後跳第 1 筆。
#
# 只「回傳」解析出的編號，不動 $script:Selected：編號超出範圍（5 筆時按 9、12 筆時按 13）
# 會被呼叫端忽略，這時目前的選取必須維持原樣，否則光棒會消失、Enter 會回傳失敗。
#
# 等待期間收到的不是數字的按鍵，放進 $script:PendingKey 交給呼叫端：
#   - Ctrl+C 是中斷，呼叫端要直接中止，不能反而讓剛才的數字生效
#   - 編號超出範圍時，主迴圈接著照一般按鍵處理它
#   - 編號有效時選單隨即關閉，其他按鍵就沒有後續了（跟剛按完數字就立刻跳轉的短清單一致）
#
# 「再加一位就超過總數就不必等」這條，在等待「之前」就要判斷：12 筆時按 9，
# 90 > 12，第二位數不可能有效，立刻跳轉。（design-notes 第 10 節寫的就是這個行為；
# zsh 版原本是讀到第二位數之後才判斷，第一位數一律要等滿 timeout，0.2.1 起與這裡相同。）
function Invoke-GwtPickNumber {
  param([string]$First)
  $digits = $First
  $maxLen = "$($script:Count)".Length
  while ($digits.Length -lt $maxLen) {
    if ([int]$digits * 10 -gt $script:Count) { break }
    if (-not (Wait-GwtKey (Get-GwtSeconds 'GWT_DIGIT_TIMEOUT' 0.4))) { break }
    $more = Read-GwtKey
    if ($null -eq $more) { break }
    if ($more.Name -eq 'Char' -and $more.Char -match '^[0-9]$') {
      $digits += $more.Char
    }
    else {
      $script:PendingKey = $more
      break
    }
  }
  return [int]$digits
}

# 處理一個按鍵。回傳 -1 表示繼續讀鍵，否則是要結束選單的結果碼（0 選定，1 取消，130 中斷）。
function Invoke-GwtKey {
  param($Key)

  if ($script:Search) {
    # 搜尋模式：可列印字元都算查詢內容，所以 q、j、k、數字都不再有特殊意義。
    switch ($Key.Name) {
      'Escape' { Exit-GwtSearch }                  # 搜尋中的 Esc 只清掉搜尋
      'Up' { Move-GwtSelection -1 }
      'Down' { Move-GwtSelection 1 }
      'CtrlC' { return 130 }
      'Enter' { if ($script:Count -gt 0) { return 0 } }
      'Backspace' {
        if ($script:Query -ne '') {
          $len = $script:Query.Length
          $cut = 1
          if ($len -ge 2 -and [char]::IsLowSurrogate($script:Query[$len - 1]) -and [char]::IsHighSurrogate($script:Query[$len - 2])) { $cut = 2 }
          $script:Query = $script:Query.Substring(0, $len - $cut)
          Invoke-GwtSearchApply
        }
      }
      'CtrlU' {
        if ($script:Query -ne '') {
          $script:Query = ''
          Invoke-GwtSearchApply
        }
      }
      'CtrlW' {                                    # 刪除最後一個詞
        if ($script:Query -ne '') {
          $q = if ($script:Query.EndsWith(' ')) { $script:Query.Substring(0, $script:Query.Length - 1) } else { $script:Query }
          $at = $q.LastIndexOf(' ')
          $script:Query = if ($at -ge 0) { $q.Substring(0, $at) } else { '' }
          Invoke-GwtSearchApply
        }
      }
      'Char' {
        $script:Query += $Key.Char
        Invoke-GwtSearchApply
      }
      default { }                                  # 其他控制鍵：忽略
    }
    return -1
  }

  switch ($Key.Name) {
    'Up' { Move-GwtSelection -1 }
    'Down' { Move-GwtSelection 1 }
    'Escape' { return 1 }                          # 單獨一個 Esc = 取消
    'CtrlC' { return 130 }
    'Enter' { return 0 }
    'Char' {
      $ch = $Key.Char
      if ($ch -ceq '/') {                          # 進入模糊搜尋
        $script:Search = $true
        $script:Query = ''
        Invoke-GwtSearchApply
      }
      elseif ($ch -ceq 'k' -or $ch -ceq 'K') { Move-GwtSelection -1 }
      elseif ($ch -ceq 'j' -or $ch -ceq 'J') { Move-GwtSelection 1 }
      elseif ($ch -ceq 'q' -or $ch -ceq 'Q') { return 1 }
      elseif ($ch -match '^[1-9]$') {
        $picked = Invoke-GwtPickNumber $ch
        # 等第二位數的時候按了 Ctrl+C：是中斷。不論數字有沒有效都以中斷為準
        if ($null -ne $script:PendingKey -and $script:PendingKey.Name -eq 'CtrlC') {
          $script:PendingKey = $null
          return 130
        }
        if ($picked -ge 1 -and $picked -le $script:Count) {
          $script:Selected = $picked
          # 先重畫一次，讓使用者看到最後落在哪一筆
          Add-GwtText "$($script:CSI)$($script:Drawn)A"
          Add-GwtList
          Send-GwtFrame
          return 0
        }
        # 超出範圍：忽略，目前的選取維持原樣
      }
    }
    default { }
  }
  return -1
}

# 互動式選單。成功選定時回傳 0，取消回傳 1，Ctrl+C 回傳 130。
function Invoke-GwtPick {
  $script:Selected = 1
  $script:PendingKey = $null
  Initialize-GwtSize
  Initialize-GwtStyle

  # Ctrl+C 當成一般按鍵讀進來（而不是讓 PowerShell 中斷管線），這樣才能確定
  # 清理與結束碼都由我們自己決定；離開時一定要還原。
  $ctrlCSaved = $null
  if ($null -eq $script:Hooks.ReadKey) {
    try {
      $ctrlCSaved = [Console]::TreatControlCAsInput
      [Console]::TreatControlCAsInput = $true
    }
    catch {
      $ctrlCSaved = $null
    }
  }

  $finished = $false
  try {
    # 選單顯示期間隱藏游標；finally 保證不論怎麼離開，游標都會回來
    Add-GwtText "$($script:CSI)?25l"
    Add-GwtHeader
    Add-GwtList
    Send-GwtFrame

    while ($true) {
      if ($null -ne $script:PendingKey) {
        $key = $script:PendingKey
        $script:PendingKey = $null
      }
      else {
        $key = Read-GwtKey
        if ($null -eq $key) {                      # 讀不到輸入（EOF）
          $finished = $true
          Complete-GwtMenu
          return 1
        }
      }

      $rc = Invoke-GwtKey $key
      if ($rc -ge 0) {
        $finished = $true
        Complete-GwtMenu
        return $rc
      }
      # 回到這一塊的第一列重畫（表頭也可能因為搜尋字串而改變）
      Invoke-GwtRepaint
    }
  }
  finally {
    if (-not $finished) {
      # 例外或被強制中止：至少把游標與主控台狀態還原
      Add-GwtText "$($script:CSI)?25h"
      Send-GwtFrame
    }
    if ($null -ne $ctrlCSaved) {
      try { [Console]::TreatControlCAsInput = $ctrlCSaved } catch { }
    }
  }
}

# -----------------------------------------------------------------------------
# 結束狀態
# -----------------------------------------------------------------------------
# 與 zsh 版一樣：成功 0、取消或錯誤 1、未知選項 2、Ctrl+C 130。
# PowerShell 的「失敗」是 $?，`gwt && next` 看的是它，不是 $LASTEXITCODE。
# 讓 $? 變成 false 又不印出錯誤訊息的做法，是在進階函式裡用 $PSCmdlet.WriteError
# 並把錯誤偏好設成 SilentlyContinue；呼叫端的 $? 會是 false，畫面上什麼都沒有。
# （換成 Write-Error -ErrorAction SilentlyContinue 或單純設 $LASTEXITCODE 都不行，
#   $? 仍然是 true，`gwt && next` 會在取消之後繼續跑。）
# $LASTEXITCODE 也一定要設：git 的呼叫會把它改掉，不設就會漏出 git 的結果碼。
function Set-GwtResult {
  param($Cmdlet, [int]$Code)
  $global:LASTEXITCODE = $Code
  if ($Code -eq 0) { return }
  $ErrorActionPreference = 'SilentlyContinue'
  $record = [System.Management.Automation.ErrorRecord]::new(
    [System.Exception]::new("gwt exited with status $Code"),
    'GwtExit',
    [System.Management.Automation.ErrorCategory]::OperationStopped,
    $null)
  $Cmdlet.WriteError($record)
  # 這筆紀錄只是用來讓 $? 變 false，不該留在 $Error 裡干擾使用者除錯
  $errors = $global:Error
  if ($errors.Count -gt 0 -and $errors[0].FullyQualifiedErrorId.StartsWith('GwtExit', [System.StringComparison]::Ordinal)) {
    $errors.RemoveAt(0)
  }
}

# 帶著訊息的失敗：寫進 PowerShell 的錯誤串流（可以用 2>&1、-ErrorVariable 接，
# 也不受主控台字碼頁影響），同時讓 $? 變 false、設好 $LASTEXITCODE。
# 訊息開頭的「gwt: 」要拿掉：PowerShell 顯示錯誤時會自己加上命令名稱。
function Stop-Gwt {
  param($Cmdlet, [int]$Code, [string]$Message)
  $global:LASTEXITCODE = $Code
  $text = $Message -replace '^gwt:\s*', ''
  $record = [System.Management.Automation.ErrorRecord]::new(
    [System.Exception]::new($text),
    'GwtError',
    [System.Management.Automation.ErrorCategory]::InvalidOperation,
    $null)
  $Cmdlet.WriteError($record)
}

# 是否能做互動式選單：輸入輸出都不能被導向，而且終端機要吃得下 ANSI 序列。
# 回傳 $null 代表可以，否則回傳要顯示的訊息。
function Test-GwtTerminal {
  if ($null -ne $script:Hooks.Interactive) {
    if ($script:Hooks.Interactive) { return $null }
    return $script:M.not_tty
  }
  if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $script:M.not_tty }
  if (-not $Host.UI.SupportsVirtualTerminal) { return $script:M.no_vt }
  return $null
}

# -----------------------------------------------------------------------------
# 主函式
# -----------------------------------------------------------------------------
# 為什麼是進階函式（CmdletBinding）：只有進階函式才有 $PSCmdlet，才能在取消時
# 讓 `gwt && next` 停下來。代價是 PowerShell 會自己吃掉 -Verbose、-Debug 這類共同
# 參數，而 -V（--version）剛好是 -Verbose 的縮寫，所以明確宣告 -V 別名。
# 其他選項（-l、-h、--list…）都不是宣告過的參數，會落進 $Arguments 由下面自己解析。
# 已知限制：-d、-e、-i、-o、-p、-w 這些短選項會被 PowerShell 當成共同參數的縮寫，
# 沒機會到這裡；gwt 目前也沒有這些選項。
function gwt {
  [CmdletBinding(PositionalBinding = $false)]
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments,

    [Alias('V')]
    [switch]$Version
  )

  Initialize-GwtMessages
  Reset-GwtState

  $mode = 'pick'
  $keywords = [System.Collections.Generic.List[string]]::new()
  $rest = @($Arguments)

  if ($Version) {
    "gwt $script:GwtVersion"
    Set-GwtResult $PSCmdlet 0
    return
  }

  for ($i = 0; $i -lt $rest.Count; $i++) {
    $arg = [string]$rest[$i]
    if ($arg -ceq '--') {
      for ($j = $i + 1; $j -lt $rest.Count; $j++) { $keywords.Add([string]$rest[$j]) }
      break
    }
    elseif ($arg -in '-h', '--help', '-Help') {
      $script:HelpText
      Set-GwtResult $PSCmdlet 0
      return
    }
    elseif ($arg -in '-V', '--version', '-Version') {
      "gwt $script:GwtVersion"
      Set-GwtResult $PSCmdlet 0
      return
    }
    elseif ($arg -in '-l', '--list', '-List') {
      $mode = 'list'
    }
    elseif ($arg.Length -gt 1 -and $arg.StartsWith('-', [System.StringComparison]::Ordinal)) {
      Stop-Gwt $PSCmdlet 2 (($script:M.bad_opt -f $arg) + "`n" + $script:HelpText)
      return
    }
    else {
      $keywords.Add($arg)
    }
  }
  $keyword = $keywords -join ' '

  if ($null -eq (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    Stop-Gwt $PSCmdlet 1 $script:M.no_git
    return
  }

  if ((Invoke-GwtGit @('rev-parse', '--git-dir')).ExitCode -ne 0) {
    Stop-Gwt $PSCmdlet 1 $script:M.not_repo
    return
  }

  # 目前所在的 worktree；bare repo 沒有工作目錄，此時為空字串
  $top = Invoke-GwtGit @('rev-parse', '--show-toplevel')
  if ($top.ExitCode -eq 0) {
    $script:Current = ConvertTo-GwtNativePath $top.Output.Trim()
  }

  $listing = Invoke-GwtGit @('worktree', 'list', '--porcelain')
  if ($listing.ExitCode -eq 0) {
    Read-GwtPorcelain -Text $listing.Output -Keyword $keyword
  }
  # 互動搜尋從完整清單重新篩選；命令列關鍵字已經是第一層篩選。
  Save-GwtSnapshot

  if ($script:Count -eq 0) {
    if ($keyword -ne '') {
      Stop-Gwt $PSCmdlet 1 ($script:M.no_match -f $keyword)
    }
    else {
      Stop-Gwt $PSCmdlet 1 $script:M.no_worktrees
    }
    return
  }

  if ($mode -eq 'list') {
    foreach ($p in $script:Paths) { $p }
    Set-GwtResult $PSCmdlet 0
    return
  }

  # 只有一筆符合時不顯示選單，直接切換
  if ($script:Count -eq 1) {
    Switch-GwtLocation $PSCmdlet $script:Paths[0]
    return
  }

  $problem = Test-GwtTerminal
  if ($null -ne $problem) {
    Stop-Gwt $PSCmdlet 1 $problem
    return
  }

  $rc = Invoke-GwtPick
  if ($rc -ne 0) {
    Set-GwtResult $PSCmdlet $rc
    return
  }
  if ($script:Selected -lt 1 -or $script:Selected -gt $script:Count) {
    Set-GwtResult $PSCmdlet 1
    return
  }

  Switch-GwtLocation $PSCmdlet $script:Paths[$script:Selected - 1]
}

# 在「全域」工作階段裡切換目錄，失敗時丟例外。
#
# 為什麼不直接 Set-Location：模組函式裡的 Set-Location 確實會改變呼叫者的位置
# （位置是整個 runspace 共用的），但 `cd -`（Set-Location -）用的歷史是記在
# 「各自的 SessionState」裡的，模組有自己的一份。結果是 gwt 切過去之後 `cd -`
# 不會回到切換之前的目錄，而是跳到一個更早、毫不相干的位置——比不支援更糟。
# zsh 版用的是 builtin cd，所以 `cd -` 一直是可用的，這裡要對齊。
#
# 實測（pwsh 7.7）：在模組裡用 Set-Location、$ExecutionContext.SessionState.Path、
# 用 [scriptblock]::Create 建的區塊、用 Function:\global: 建的函式、
# [powershell]::Create('CurrentRunspace') 開的巢狀管線，歷史全都記在錯的地方；
# 只有拿到引擎的最上層 SessionState 再呼叫 Path.SetLocation 才會記對。
# 沒有公開的 API 可以拿到它，所以這裡用反射。
#
# 反射是這個檔案唯一碰到 PowerShell 內部的地方，而且有後路：內部結構改了、
# 或在受限語言模式（反射被擋）下，會自動退回一般的 Set-Location——目錄照樣會
# 切過去，只是 `cd -` 又回到上面描述的行為。tests/pwsh/cases/04-single-match.ps1
# 會驗證 `cd -`，PowerShell 改版造成失效時 CI 會先知道。
function Set-GwtLocation {
  param([string]$Target)
  $session = $null
  try {
    $flags = [System.Reflection.BindingFlags]'NonPublic,Instance'
    $ctx = $ExecutionContext.GetType().GetField('_context', $flags).GetValue($ExecutionContext)
    $top = $ctx.GetType().GetProperty('TopLevelSessionState', $flags).GetValue($ctx)
    $session = $top.GetType().GetProperty('PublicSessionState', $flags).GetValue($top)
  }
  catch {
    $session = $null
  }
  if ($null -ne $session) {
    # SetLocation 的參數會做萬用字元展開（Set-Location -LiteralPath 才不會），
    # 路徑含 [ ] * ? 時要先跳脫，否則 C:\proj[1] 這種目錄會切不進去
    [void]$session.Path.SetLocation([System.Management.Automation.WildcardPattern]::Escape($Target))
    return
  }
  Set-Location -LiteralPath $Target -ErrorAction Stop
}

# 真正切換目錄。
function Switch-GwtLocation {
  param($Cmdlet, [string]$Target)
  try {
    Set-GwtLocation $Target
  }
  catch {
    # 目錄不存在（例如被刪掉卻沒有 git worktree prune）：照實顯示 PowerShell 的錯誤
    $global:LASTEXITCODE = 1
    $Cmdlet.WriteError($_)
    return
  }
  Set-GwtResult $Cmdlet 0
}

Export-ModuleMember -Function gwt
