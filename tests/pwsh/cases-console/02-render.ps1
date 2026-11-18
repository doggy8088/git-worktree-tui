# 真主控台的排版：主控台高度由 [Console]::WindowHeight 查（不是 GWT_HEIGHT）、
# 視窗化、窄視窗、中文與省略號的欄寬。ConPTY 會用 conhost 自己的字元寬度表重新渲染，
# 如果 gwt 算的欄寬與主控台認定的不一致（例如省略號 … 或全形字被當成 2 欄），
# 一列就會折成兩行，重播後會看到重複的列。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"
. "$env:GWT_ROOT\tests\pwsh\lib\ConPty.ps1"

$k = $script:Keys

# 取消之後把選單留在畫面上，才能檢查最後的畫面
$env:GWT_CLEAR_ON_EXIT = '0'
# 這個測試的重點是「靠真的主控台量尺寸」，不要讓環境變數蓋過去
Remove-Item Env:\GWT_HEIGHT, Env:\GWT_WIDTH -ErrorAction SilentlyContinue

function Run-Menu {
  param([string]$Fixture, [string[]]$Keys, [int]$Rows, [int]$Cols)
  $env:GWT_TEST_FIXTURE_NAME = $Fixture
  $scenario = {
    Import-Module (Join-Path $env:GWT_ROOT 'gwt.psm1')
    Set-Location -LiteralPath (Join-Path $env:GWT_FIXTURE $env:GWT_TEST_FIXTURE_NAME)
    "RUN-1"
    # 主控台自己回報的游標列：選單畫完之後游標比畫之前往下移了幾列。這是「實際佔了幾個實體行」，
    # 由真的 conhost 決定，不經過任何字元寬度表——選單有一列被折成兩行，這個差就會多 1。
    $top0 = [Console]::CursorTop
    gwt
    $top1 = [Console]::CursorTop
    "RESULT-1 rc=$LASTEXITCODE ok=$? pwd=$((Get-Location).Path)"
    "TOPS=$top0,$top1"
  }
  $steps = New-RunSteps 1 $Keys
  Invoke-InConsole -Script $scenario -Steps $steps -Rows $Rows -Cols $Cols
}

# 選單實際佔用的主控台行數（取消後選單留在畫面上，游標停在最後一列的下一行）。取不到回傳 -1。
function Get-PhysicalLines {
  param($Run)
  $m = [regex]::Match($Run.Screen, '(?m)^TOPS=(\d+),(\d+)\s*$')
  if (-not $m.Success) { return -1 }
  return [int]$m.Groups[2].Value - [int]$m.Groups[1].Value
}

# --- shop：5 筆，寬度夠，主控台 30 列
$r = Run-Menu 'shop' @('jj', 'q') 30 160
Assert-True '沒有逾時' ((-not $r.TimedOut) -and ($null -eq $r.WaitFailed))
Assert-Screen '表頭在畫面上' '^請選擇 Worktree.*q/Esc 取消\)：' $r.Screen
Assert-Screen '5 列都畫出來' '^ITEM_ROWS=5$' $r.Screen
Assert-Screen '游標停在第 3 筆（jj）' '^SELECTED=3$' $r.Screen
Assert-Screen '沒有重複的列' '^DUPLICATES=-$' $r.Screen
Assert-Screen '目前位置有標註（全形字之後仍在同一列）' '\[main\].*\(目前位置\)' $r.Screen
$lastHide = $r.Output.LastIndexOf("$ESC[?25l", [System.StringComparison]::Ordinal)
$lastShow = $r.Output.LastIndexOf("$ESC[?25h", [System.StringComparison]::Ordinal)
Assert-True '選單期間隱藏了游標' ($lastHide -ge 0)
Assert-True '離開後游標是顯示的（最後一次 ?25h 在最後一次 ?25l 之後）' ($lastShow -gt $lastHide)

# --- many：40 筆放進 12 列的主控台：視窗化要靠 [Console]::WindowHeight
$down15 = $k.Down * 15
$r = Run-Menu 'many' @($down15, 'q') 12 100
Assert-True '沒有逾時' ((-not $r.TimedOut) -and ($null -eq $r.WaitFailed))
# 選單之後場景程式還會印一行 RESULT-1，在 12 列的畫面裡那一行會把表頭擠出去（這是正常的
# 捲動，不是 gwt 的問題）。所以只重播到 gwt 結束為止，看選單最後的樣子——
# 對應 zsh 測試裡的 GWT-SCREEN-CUT。
$cut = $r.Output.IndexOf('RESULT-1', [System.StringComparison]::Ordinal)
Assert-True '輸出裡找得到 RESULT-1 的位置（才切得出選單最後的畫面）' ($cut -gt 0)
$menu = Get-ScreenReplay -Text $r.Output.Substring(0, $cut) -Rows 12 -Cols 100
Assert-Screen '40 筆在 12 列的主控台裡：表頭沒有被捲出畫面' '^請選擇 Worktree' $menu
Assert-Screen '可視列是 高度 - 3 = 9（真的量到了主控台高度）' '^ITEM_ROWS=9$' $menu
Assert-Screen '視窗跟著捲到 8-16' '^INDEXES=8-16$' $menu
Assert-Screen '光棒在第 16 筆' '^SELECTED=16$' $menu
Assert-Screen '沒有重複的列' '^DUPLICATES=-$' $menu
Assert-Screen '下方標示目前範圍' '顯示 8-16，共 40 筆' $menu

# --- 省略號與欄寬：窄視窗讓路徑與分支都被截斷（… 在 CJK 字碼頁的主控台可能被當成 2 欄）
foreach ($cols in 25, 50, 60, 80) {
  $r = Run-Menu 'shop' @($k.Down, 'q') 30 $cols
  Assert-True "$cols 欄：沒有逾時" ((-not $r.TimedOut) -and ($null -eq $r.WaitFailed))
  Assert-Screen "$cols 欄：5 筆各佔一列（省略號沒有造成折行）" '^ITEM_ROWS=5$' $r.Screen
  Assert-Screen "$cols 欄：沒有重複的列" '^DUPLICATES=-$' $r.Screen
  Assert-Screen "$cols 欄：游標在第 2 筆" '^SELECTED=2$' $r.Screen
  Assert-Screen "$cols 欄：確實出現了省略號（測試有效）" '…' $r.Screen
  Assert-Rc "$cols 欄：選單實際佔 1 + 5 = 6 個主控台行（主控台自己回報的游標列）" 6 (Get-PhysicalLines $r)
  # 直接數自動換行。只重播到 gwt 結束為止：之後場景程式自己印的 RESULT-1 那一行（含很長的路徑）
  # 在窄視窗裡本來就會換行，那不是選單的問題。
  $cut = $r.Output.IndexOf('RESULT-1', [System.StringComparison]::Ordinal)
  $menuOnly = Get-ScreenReplay -Text $r.Output.Substring(0, $cut) -Rows 30 -Cols $cols
  Assert-Screen "$cols 欄：選單本身沒有任何一列被主控台折行（WRAPS=0）" '^WRAPS=0$' $menuOnly
}

# --- cjk：中文目錄與中文分支
foreach ($cols in 40, 60, 100) {
  $r = Run-Menu 'cjk' @($k.Down, 'q') 20 $cols
  Assert-True "cjk $cols 欄：沒有逾時" ((-not $r.TimedOut) -and ($null -eq $r.WaitFailed))
  Assert-Screen "cjk $cols 欄：3 筆各佔一列" '^ITEM_ROWS=3$' $r.Screen
  Assert-Screen "cjk $cols 欄：沒有重複的列" '^DUPLICATES=-$' $r.Screen
  Assert-Screen "cjk $cols 欄：游標在第 2 筆" '^SELECTED=2$' $r.Screen
  Assert-Rc "cjk $cols 欄：選單實際佔 1 + 3 = 4 個主控台行（主控台自己回報的游標列）" 4 (Get-PhysicalLines $r)
  $cut = $r.Output.IndexOf('RESULT-1', [System.StringComparison]::Ordinal)
  $menuOnly = Get-ScreenReplay -Text $r.Output.Substring(0, $cut) -Rows 20 -Cols $cols
  Assert-Screen "cjk $cols 欄：選單本身沒有任何一列被主控台折行（WRAPS=0）" '^WRAPS=0$' $menuOnly
}
# --- emoji：寬度為 2 的符號（⚡ ⌚ ✅ ⭐）與代理對 emoji（🔥）。
# 這裡不能用「把 conhost 的輸出重播成畫面」來判斷有沒有折行：重播器得自己決定 ⚡ 佔幾欄，而不同的主控台
# 對這些符號的看法不一樣——Unicode 與 Windows Terminal 是 2 欄，這台 Windows 10 的 conhost（較舊的
# Unicode 表）是 1 欄；重播器認定的寬度和 conhost 排版時用的寬度對不上，就會誤判折行（實測：畫面
# 看起來完全正常，WRAPS 卻是 2）。改問主控台自己：選單畫完之後游標往下移了幾列。有任何一列被折成兩行，
# 這個數字就會多 1，與任何寬度表無關。
# gwt 一律當成 2 欄是安全的方向：在把它們畫成 1 欄的主控台上，一列只是短一點；反過來假設 1 欄，
# 在畫成 2 欄的主控台（Windows Terminal）上就會折行。
foreach ($cols in 40, 60, 80, 100) {
  $r = Run-Menu 'emoji' @($k.Down, 'q') 20 $cols
  Assert-True "emoji $cols 欄：沒有逾時" ((-not $r.TimedOut) -and ($null -eq $r.WaitFailed))
  Assert-Rc "emoji $cols 欄：4 筆實際佔 1 + 4 = 5 個主控台行（沒有任何一列被 conhost 折行）" 5 (Get-PhysicalLines $r)
}

$r = Run-Menu 'cjk' @($k.Down, 'q') 20 100
Assert-Screen '中文分支名稱與路徑正確顯示' '功能/登入|修正/結帳' $r.Screen
Assert-Screen '中文目錄名稱正確顯示' 'cjk-購物車|cjk-修正結帳錯誤|…' $r.Screen

Complete-Tests
