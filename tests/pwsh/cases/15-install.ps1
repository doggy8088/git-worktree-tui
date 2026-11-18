# install.ps1：安裝、重複安裝、移除；profile 要在各種編碼、換行與空內容下逐位元組還原。
# 全部在暫存目錄裡做（-Dir、-ProfilePath 都明確指定），絕不碰真正的 $PROFILE 與 ~\.gwt。
# 不比對中文訊息：子行程的主控台輸出編碼不是測試能控制的，只看結束碼與檔案內容。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$installer = Join-Path $env:GWT_ROOT 'install.ps1'
$module = Join-Path $env:GWT_ROOT 'gwt.psm1'
$pwshExe = (Get-Process -Id $PID).Path
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('gwt-inst-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null

# 真正的 profile 與預設安裝目錄：測試前後都不能變
function Get-RealState {
  $p = $PROFILE.CurrentUserAllHosts
  $d = Join-Path $HOME '.gwt'
  $ph = if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p).Hash } else { '(none)' }
  $dh = if (Test-Path -LiteralPath $d) { (Get-ChildItem -LiteralPath $d -Recurse -Force | ForEach-Object { $_.FullName + $_.Length }) -join '|' } else { '(none)' }
  return "$ph / $dh"
}
$realBefore = Get-RealState

function Invoke-Installer {
  param([string[]]$InstallerArgs, [string]$Pwsh = $pwshExe, [hashtable]$Env = @{})
  $saved = @{}
  foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
  try {
    $out = & $Pwsh -NoProfile -NonInteractive -File $installer @InstallerArgs 2>&1
    $rc = $LASTEXITCODE
  }
  finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
  return [pscustomobject]@{ Rc = $rc; Output = (@($out | ForEach-Object { "$_" }) -join "`n") }
}

function New-Sandbox {
  $dir = Join-Path $work ([guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Path $dir | Out-Null
  return [pscustomobject]@{ Root = $dir; Profile = (Join-Path $dir 'profile.ps1'); Dir = (Join-Path $dir 'dotgwt') }
}

function Get-B64 { param([string]$Path) [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) }
function Get-Text { param([string]$Path) $t = Get-Content -LiteralPath $Path -Raw; if ($null -eq $t) { '' } else { $t } }

$utf8 = [System.Text.UTF8Encoding]::new($false)
$bom8 = [byte[]](0xEF, 0xBB, 0xBF)
$bom16 = [byte[]](0xFF, 0xFE)
$bom32 = [byte[]](0xFF, 0xFE, 0x00, 0x00)

# --- 安裝後再移除，profile 要和原本完全一樣 ---------------------------------------
$cases = [ordered]@{
  'LF、有結尾換行'              = $utf8.GetBytes("# my profile`nSet-Alias ll Get-ChildItem`n")
  'CRLF、有結尾換行'            = $utf8.GetBytes("# my profile`r`nSet-Alias ll Get-ChildItem`r`n")
  '沒有結尾換行'                = $utf8.GetBytes('Write-Host hello')
  'CRLF、沒有結尾換行'          = $utf8.GetBytes("`$a = 1`r`nWrite-Host hello")
  '結尾有多個空行'              = $utf8.GetBytes("Write-Host hello`n`n`n")
  '空檔案（0 位元組）'          = [byte[]]@()
  '只有空白與換行'              = $utf8.GetBytes("  `n`n")
  '只有一個換行'                = $utf8.GetBytes("`n")
  '只有 UTF-8 BOM'              = $bom8
  'UTF-8 BOM + CRLF 內容'       = [byte[]]($bom8 + $utf8.GetBytes("# bom profile`r`nWrite-Host hi`r`n"))
  'UTF-16LE（有 BOM）'          = [byte[]]($bom16 + [System.Text.Encoding]::Unicode.GetBytes("# utf16 profile`r`nWrite-Host hi`r`n"))
  'UTF-16BE（有 BOM）'          = [byte[]](([byte[]](0xFE, 0xFF)) + [System.Text.Encoding]::BigEndianUnicode.GetBytes("# utf16be profile`nWrite-Host hi`n"))
  'UTF-32LE（有 BOM）'          = [byte[]]($bom32 + [System.Text.UTF32Encoding]::new($false, $false).GetBytes("# utf32 profile`nWrite-Host hi`n"))
  'UTF-32BE（有 BOM）'          = [byte[]](([byte[]](0x00, 0x00, 0xFE, 0xFF)) + [System.Text.UTF32Encoding]::new($true, $false).GetBytes("# utf32be profile`nWrite-Host hi`n"))
  '非 UTF-8 的舊式 ANSI（Big5）' = [byte[]](0x23, 0x20, 0xA4, 0xA4, 0xA4, 0xE5, 0x0D, 0x0A, 0x57, 0x72, 0x69, 0x74, 0x65, 0x0D, 0x0A)
  '含中文與特殊字元'            = $utf8.GetBytes("# 我的 profile`nfunction ll { Get-ChildItem `$args }`nSet-Alias 'it''s' ll`n")
}

foreach ($name in $cases.Keys) {
  $original = $cases[$name]
  $sb = New-Sandbox
  [System.IO.File]::WriteAllBytes($sb.Profile, $original)
  $originalB64 = [Convert]::ToBase64String($original)

  $i = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile)
  Assert-Rc "[$name] 安裝回傳 0" 0 $i.Rc
  $afterInstall = Get-B64 $sb.Profile
  $blocks = ([regex]::Matches((Get-Text $sb.Profile), '>>> gwt \(git-worktree-tui\) >>>')).Count
  Assert-Rc "[$name] 安裝後有一個 block" 1 $blocks
  Assert-True "[$name] 安裝後原本的位元組都還在（block 只是附加在後面）" ($afterInstall.Length -gt $originalB64.Length)
  Assert-Eq "[$name] 模組檔與專案的 gwt.psm1 一致" (Get-FileHash -LiteralPath $module).Hash (Get-FileHash -LiteralPath (Join-Path $sb.Dir 'gwt.psm1')).Hash

  $u = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile, '-Uninstall')
  Assert-Rc "[$name] 移除回傳 0" 0 $u.Rc
  Assert-True "[$name] 移除後 profile 還在（原本就存在的檔案不能被刪）" (Test-Path -LiteralPath $sb.Profile)
  if (Test-Path -LiteralPath $sb.Profile) {
    Assert-Eq "[$name] 移除後 profile 與原本逐位元組相同" $originalB64 (Get-B64 $sb.Profile)
  }
  Assert-True "[$name] 移除後安裝目錄也清掉了" (-not (Test-Path -LiteralPath $sb.Dir))
}

# --- 重複安裝不會重複加行，結果與第一次完全相同 ----------------------------------------
foreach ($name in 'LF、有結尾換行', 'CRLF、沒有結尾換行') {
  $sb = New-Sandbox
  [System.IO.File]::WriteAllBytes($sb.Profile, $cases[$name])
  [void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile))
  $first = Get-B64 $sb.Profile
  $again = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile)
  Assert-Rc "[$name] 重複安裝回傳 0" 0 $again.Rc
  Assert-Eq "[$name] 重複安裝後 profile 與第一次逐位元組相同" $first (Get-B64 $sb.Profile)
  [void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile, '-Uninstall'))
  Assert-Eq "[$name] 裝兩次再移除，仍然還原成原本的樣子" ([Convert]::ToBase64String($cases[$name])) (Get-B64 $sb.Profile)
}

# --- profile 原本不存在：安裝時建立，移除時刪掉；但使用者後來加的內容要保留 --------------
$sb = New-Sandbox
$i = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile)
Assert-Rc '[原本沒有 profile] 安裝回傳 0' 0 $i.Rc
Assert-True '[原本沒有 profile] 安裝時建立了 profile' (Test-Path -LiteralPath $sb.Profile)
$u = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile, '-Uninstall')
Assert-Rc '[原本沒有 profile] 移除回傳 0' 0 $u.Rc
Assert-True '[原本沒有 profile] 移除後 profile 也刪掉（回到安裝前）' (-not (Test-Path -LiteralPath $sb.Profile))
Assert-True '[原本沒有 profile] 移除後安裝目錄也清掉了' (-not (Test-Path -LiteralPath $sb.Dir))

$sb = New-Sandbox
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile))
[System.IO.File]::AppendAllText($sb.Profile, "Write-Host later`n", $utf8)   # 使用者之後自己加的
$u = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile, '-Uninstall')
Assert-True '[安裝時建立的 profile] 使用者後來加了內容，移除後 profile 要保留' (Test-Path -LiteralPath $sb.Profile)
if (Test-Path -LiteralPath $sb.Profile) {
  Assert-Eq '[安裝時建立的 profile] 保留的只剩使用者自己的內容' "Write-Host later`n" (Get-Text $sb.Profile)
}

# --- 「這個 profile 是安裝腳本建立的」要記在每個 profile 自己身上，不是記在安裝目錄 -----------
# 同一個 -Dir 配不同的 -ProfilePath：A 原本不存在（我們建立的），B 原本就是空檔案（使用者的）。
# 移除 B 時不能拿 A 的建立紀錄當授權，把使用者本來就有的 B 刪掉。
$sb = New-Sandbox
$profileA = Join-Path $sb.Root 'profile-a.ps1'
$profileB = Join-Path $sb.Root 'profile-b.ps1'
[System.IO.File]::WriteAllBytes($profileB, [byte[]]@())
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileA))
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileB))
Assert-True '[兩個 profile] A 是安裝時建立的' (Test-Path -LiteralPath $profileA)
$u = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileB, '-Uninstall')
Assert-Rc '[兩個 profile] 移除 B 回傳 0' 0 $u.Rc
Assert-True '[兩個 profile] 移除 B 之後，原本就有的空檔案 B 還在（不能拿 A 的建立紀錄刪掉它）' (Test-Path -LiteralPath $profileB)
if (Test-Path -LiteralPath $profileB) {
  Assert-Rc '[兩個 profile] B 還原成原本的 0 位元組' 0 ([System.IO.File]::ReadAllBytes($profileB)).Length
}
$u = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileA, '-Uninstall')
Assert-Rc '[兩個 profile] 接著移除 A 回傳 0' 0 $u.Rc
Assert-True '[兩個 profile] 安裝時建立的 A 仍然會被刪掉' (-not (Test-Path -LiteralPath $profileA))
Assert-True '[兩個 profile] 兩個都移除後安裝目錄清乾淨' (-not (Test-Path -LiteralPath $sb.Dir))

# 相反的順序：先裝原本就有的 B，再裝不存在的 A，然後先移除 A
$sb = New-Sandbox
$profileA = Join-Path $sb.Root 'profile-a.ps1'
$profileB = Join-Path $sb.Root 'profile-b.ps1'
[System.IO.File]::WriteAllBytes($profileB, $utf8.GetBytes("  `n"))
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileB))
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileA))
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileA, '-Uninstall'))
Assert-True '[兩個 profile、相反順序] A 被刪掉' (-not (Test-Path -LiteralPath $profileA))
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $profileB, '-Uninstall'))
Assert-True '[兩個 profile、相反順序] 原本只有空白的 B 還在' (Test-Path -LiteralPath $profileB)
if (Test-Path -LiteralPath $profileB) {
  Assert-Eq '[兩個 profile、相反順序] B 逐位元組還原' ([Convert]::ToBase64String($utf8.GetBytes("  `n"))) (Get-B64 $profileB)
}

# --- 安裝路徑含中文，而 profile 是舊式單位元組編碼（Big5）-----------------------------------
# 為了不弄壞原本的位元組，這種 profile 是以 Latin-1 逐位元組讀寫的；新加的 import 那一行如果
# 直接寫中文路徑，會被編成 ?，安裝宣告成功，之後每個終端機都載入不了。這一行要用純 ASCII 表示。
function Get-ImportedPath {
  # profile 裡那一行 Import-Module 的引數，當成 PowerShell 運算式求值之後得到的路徑。
  # 不能只看「載入成功」：被寫成 ?? 的路徑會被 PowerShell 當成萬用字元，剛好只有一個目錄
  # 符合時照樣載得進去，看起來沒問題，其實那一行早就壞了。要求值結果與預期的路徑一字不差。
  param([string]$ProfilePath)
  $text = Get-Content -LiteralPath $ProfilePath -Raw
  $m = [regex]::Match($text, '(?m)^Import-Module (.+?)\s*$')
  if (-not $m.Success) { return $null }
  return [string](& ([scriptblock]::Create($m.Groups[1].Value)))
}
function Test-ProfileImports {
  param([string]$ProfilePath, [string]$ExpectedModulePath)
  if ((Get-ImportedPath $ProfilePath) -ne $ExpectedModulePath) { return $false }
  # 再實際載入一次。這些 fixture profile 自己會印東西（Write-Host hi）甚至報錯（Big5 那份有一行
  # 單獨的 Write），所以只認「MODPATH=」那一行，不拿整段輸出來比。
  $out = & $pwshExe -NoProfile -NonInteractive -Command ". '$ProfilePath'; 'MODPATH=' + (Get-Module gwt).Path" 2>&1
  $m = [regex]::Match((@($out) | ForEach-Object { "$_" }) -join "`n", '(?m)^MODPATH=(.*?)\s*$')
  return ($m.Success -and $m.Groups[1].Value -eq $ExpectedModulePath)
}
foreach ($name in '非 UTF-8 的舊式 ANSI（Big5）', 'LF、有結尾換行', 'UTF-16LE（有 BOM）') {
  $sb = New-Sandbox
  $cjkDir = Join-Path $sb.Root '工具\gwt 模組'
  [System.IO.File]::WriteAllBytes($sb.Profile, $cases[$name])
  $i = Invoke-Installer @('-Dir', $cjkDir, '-ProfilePath', $sb.Profile)
  Assert-Rc "[中文安裝路徑、$name] 安裝回傳 0" 0 $i.Rc
  Assert-True "[中文安裝路徑、$name] profile 載入後真的從中文路徑載入了模組" (Test-ProfileImports $sb.Profile (Join-Path $cjkDir 'gwt.psm1'))
  [void](Invoke-Installer @('-Dir', $cjkDir, '-ProfilePath', $sb.Profile, '-Uninstall'))
  Assert-Eq "[中文安裝路徑、$name] 移除後 profile 逐位元組還原" ([Convert]::ToBase64String($cases[$name])) (Get-B64 $sb.Profile)
}
# 路徑裡有 $、反引號、雙引號與單引號：用 ASCII 表示時也不能被展開或截斷（雙引號在 Windows 路徑裡不合法，不測）
$sb = New-Sandbox
$oddDir = Join-Path $sb.Root "工具 `$HOME's"
[System.IO.File]::WriteAllBytes($sb.Profile, $cases['非 UTF-8 的舊式 ANSI（Big5）'])
[void](Invoke-Installer @('-Dir', $oddDir, '-ProfilePath', $sb.Profile))
Assert-True '[中文與 $、單引號的路徑、Big5] profile 載入後從正確的路徑載入' (Test-ProfileImports $sb.Profile (Join-Path $oddDir 'gwt.psm1'))

# --- 安裝目錄含萬用字元（[ ]）：profile 的 import 不能被 PowerShell 當成樣式展開 ------------------------
# Import-Module 會先把路徑當萬用字元展開：gwt[12] 這個目錄名稱會被解讀成「gwt1 或 gwt2」，旁邊剛好有
# gwt1\gwt.psm1 時，profile 默默載入隔壁那一個——安裝宣告成功，之後每個終端機跑的卻是別的模組。
# 不能看 (Get-Module gwt).Path（對跳脫過的萬用字元目錄它會顯示錯的路徑），要看「實際跑起來的是誰」：
# 真的 gwt 回報版本，誘餌模組只會印 DECOY。（Windows 的檔名不能含 * 與 ?，所以只有 [ ] 是實際會遇到的。）
function Get-RunningGwt {
  param([string]$ProfilePath)
  $out = & $pwshExe -NoProfile -NonInteractive -Command ". '$ProfilePath'; 'WHO=' + (gwt --version)" 2>&1
  $m = [regex]::Match((@($out | ForEach-Object { "$_" }) -join "`n"), '(?m)^WHO=(.*?)\s*$')
  if ($m.Success) { return $m.Groups[1].Value }
  return '(import failed)'
}
$realVersion = Invoke-InGwt { $script:GwtVersion }
$wildCases = @(
  @{ Dir = 'gwt[12]'; Decoy = 'gwt1' }
  @{ Dir = 'a[1]\gwt'; Decoy = 'a1\gwt' }
  @{ Dir = 'x[a-c]y'; Decoy = 'xby' }
)
foreach ($wc in $wildCases) {
  foreach ($kind in 'UTF-8', 'Big5（import 要純 ASCII）') {
    $sb = New-Sandbox
    $decoy = Join-Path $sb.Root $wc.Decoy
    New-Item -ItemType Directory -Path $decoy -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $decoy 'gwt.psm1'), "function gwt { 'DECOY' }`nExport-ModuleMember -Function gwt`n", $utf8)
    $wild = Join-Path $sb.Root $wc.Dir
    $original = if ($kind -like 'Big5*') { $cases['非 UTF-8 的舊式 ANSI（Big5）'] } else { $cases['LF、有結尾換行'] }
    [System.IO.File]::WriteAllBytes($sb.Profile, $original)
    $tag = "[萬用字元目錄 $($wc.Dir)、$kind]"

    $i = Invoke-Installer @('-Dir', $wild, '-ProfilePath', $sb.Profile)
    Assert-Rc "$tag 安裝回傳 0" 0 $i.Rc
    Assert-True "$tag 模組真的裝進那個目錄" (Test-Path -LiteralPath (Join-Path $wild 'gwt.psm1'))
    Assert-Eq "$tag profile 載入後跑起來的是剛裝的 gwt，不是隔壁的誘餌" "gwt $realVersion" (Get-RunningGwt $sb.Profile)

    $u = Invoke-Installer @('-Dir', $wild, '-ProfilePath', $sb.Profile, '-Uninstall')
    Assert-Rc "$tag 移除回傳 0" 0 $u.Rc
    Assert-True "$tag 移除只清掉自己的目錄" (-not (Test-Path -LiteralPath $wild))
    Assert-True "$tag 移除沒有誤刪隔壁的誘餌目錄" (Test-Path -LiteralPath (Join-Path $decoy 'gwt.psm1'))
    Assert-Eq "$tag 移除後 profile 逐位元組還原" ([Convert]::ToBase64String($original)) (Get-B64 $sb.Profile)
  }
}

# --- 沒有裝過就移除：什麼都不動 ---------------------------------------------------------
$sb = New-Sandbox
[System.IO.File]::WriteAllBytes($sb.Profile, $cases['沒有結尾換行'])
$u = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile, '-Uninstall')
Assert-Rc '[沒裝過] 移除回傳 0' 0 $u.Rc
Assert-Eq '[沒裝過] profile 一個位元組都沒動' ([Convert]::ToBase64String($cases['沒有結尾換行'])) (Get-B64 $sb.Profile)

# --- 環境變數版（iex 沒辦法帶參數，用這個）---------------------------------------------
$sb = New-Sandbox
$i = Invoke-Installer @() -Env @{ GWT_INSTALL_DIR = $sb.Dir; GWT_PROFILE = $sb.Profile }
Assert-Rc '[環境變數] 安裝回傳 0' 0 $i.Rc
Assert-True '[環境變數] 模組裝到 GWT_INSTALL_DIR' (Test-Path -LiteralPath (Join-Path $sb.Dir 'gwt.psm1'))
Assert-Rc '[環境變數] block 寫進 GWT_PROFILE' 1 ([regex]::Matches((Get-Text $sb.Profile), '>>> gwt')).Count

# --- 安裝出來的 profile 真的載得起來，gwt 能用 -------------------------------------------
$sb = New-Sandbox
[void](Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile))
$loaded = & $pwshExe -NoProfile -NonInteractive -Command ". '$($sb.Profile)'; (Get-Command gwt).CommandType; gwt --version" 2>&1
Assert-Eq '[載入] profile 載入後 gwt 是函式，--version 有輸出' "Function`ngwt $(Invoke-InGwt { $script:GwtVersion })" ((@($loaded) | ForEach-Object { "$_" }) -join "`n")

# --- 模組檔被鎖住、無法覆蓋時：不能一路走到「安裝成功」（只有 Windows 有強制檔案鎖）-----------
if ($IsWindows) {
  $sb = New-Sandbox
  [System.IO.File]::WriteAllBytes($sb.Profile, $utf8.GetBytes("# keep`n"))
  $first = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile)
  Assert-Rc '[鎖住] 第一次安裝回傳 0' 0 $first.Rc
  $profileBefore = Get-B64 $sb.Profile
  $version = Invoke-InGwt { $script:GwtVersion }
  $target = Join-Path $sb.Dir 'gwt.psm1'
  $lock = [System.IO.File]::Open($target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
  try {
    $again = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile)
  }
  finally { $lock.Dispose() }
  Assert-Rc '[鎖住] 模組無法覆蓋時結束碼是 1' 1 $again.Rc
  Assert-NotContains '[鎖住] 失敗時沒有宣告安裝成功（沒有印出版本號）' $version $again.Output
  Assert-Eq '[鎖住] 失敗時 profile 沒被改動' $profileBefore (Get-B64 $sb.Profile)

  # 移除時刪不掉模組也一樣：不能報告「已刪除」還回傳 0
  $lock = [System.IO.File]::Open($target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
  try {
    $un = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile, '-Uninstall')
  }
  finally { $lock.Dispose() }
  Assert-Rc '[鎖住] 模組刪不掉時，移除的結束碼是 1' 1 $un.Rc
}

# --- Windows PowerShell 5.1：明確拒絕，什麼都不裝 ---------------------------------------
if ($IsWindows -and (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
  $sb = New-Sandbox
  $i = Invoke-Installer @('-Dir', $sb.Dir, '-ProfilePath', $sb.Profile) -Pwsh (Get-Command powershell.exe).Source
  Assert-Rc '[5.1] 回傳 1' 1 $i.Rc
  Assert-True '[5.1] 沒有建立安裝目錄' (-not (Test-Path -LiteralPath $sb.Dir))
  Assert-True '[5.1] 沒有建立 profile' (-not (Test-Path -LiteralPath $sb.Profile))
}

# --- 腳本本身：只含 ASCII、沒有 BOM（iex 與 5.1 的需要）-----------------------------------
$bytes = [System.IO.File]::ReadAllBytes($installer)
Assert-Rc 'install.ps1 只含 ASCII' 0 @($bytes | Where-Object { $_ -gt 127 }).Count
Assert-True 'install.ps1 沒有 BOM' (-not ($bytes[0] -eq 0xEF -or $bytes[0] -eq 0xFF -or $bytes[0] -eq 0xFE))

# --- 全程沒有碰到真正的 profile 與 ~\.gwt -----------------------------------------------
Assert-Eq '真正的 profile 與 ~\.gwt 完全沒被動到' $realBefore (Get-RealState)

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Complete-Tests
