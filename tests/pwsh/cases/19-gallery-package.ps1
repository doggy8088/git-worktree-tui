# PowerShell Gallery 的發佈流程：打包腳本、套件本身、以及發佈用的 GitHub Actions workflow。
#
# 為什麼要測得這麼細：Gallery 上的版本發佈之後不能刪除也不能覆蓋，而發佈用的 API key 是長效的祕密。
# 打包前能檢查的都要在發佈之前擋下來；workflow 的安全性質（key 只在哪裡出現、什麼會觸發發佈）
# 一旦被改壞，要在合併之前就看得到，不能等到出事。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$root = $env:GWT_ROOT
$build = Join-Path $root 'tools\Build-PSGalleryPackage.ps1'
$pwshExe = (Get-Process -Id $PID).Path
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('gwt-gallery-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null

$version = Invoke-InGwt { $script:GwtVersion }
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'gwt.psd1')
$zshVersion = [regex]::Match((Get-Content -LiteralPath (Join-Path $root 'gwt.zsh') -Raw), "GWT_VERSION='([^']+)'").Groups[1].Value

# --- 三個版本號一致（發佈前必須；打包腳本也會擋，這裡先確認專案現在就是一致的）--------------------------
Assert-Eq '清單（gwt.psd1）與模組（gwt.psm1）的版本一致' $version ([string]$manifest.ModuleVersion)
Assert-Eq 'zsh 版（gwt.zsh）與模組的版本一致' $version $zshVersion
Assert-True '版本是 x.y.z' ($version -match '^\d+\.\d+\.\d+$')

function Invoke-Build {
  param([string]$OutDir, [string]$Tag = '', [string]$FromRoot = '')
  $a = @('-NoProfile', '-NonInteractive', '-File', $build, '-OutputDir', $OutDir)
  if ($Tag) { $a += @('-Tag', $Tag) }
  if ($FromRoot) { $a += @('-Root', $FromRoot) }
  $out = & $pwshExe @a 2>&1
  return [pscustomobject]@{ Rc = $LASTEXITCODE; Output = (@($out | ForEach-Object { "$_" }) -join "`n") }
}

# --- 正常打包：版本等於 tag ----------------------------------------------------------------------------
$out1 = Join-Path $work 'ok'
$r = Invoke-Build $out1 "v$version"
Assert-Rc '打包（tag 與版本一致）成功' 0 $r.Rc
$pkg = Join-Path $out1 'gwt'
Assert-True '產生 gwt 資料夾（資料夾名稱必須等於模組名稱）' (Test-Path -LiteralPath $pkg -PathType Container)
$names = @(Get-ChildItem -LiteralPath $pkg -Recurse -File | ForEach-Object Name)
Assert-Rc '套件剛好三個檔案' 3 $names.Count
foreach ($n in 'gwt.psd1', 'gwt.psm1', 'LICENSE') { Assert-True "套件含 $n" ($names -ccontains $n) }
Assert-True '套件裡的模組與專案的 gwt.psm1 逐位元組相同' ((Get-FileHash -LiteralPath (Join-Path $pkg 'gwt.psm1')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'gwt.psm1')).Hash)
Assert-True '套件裡的清單與專案的 gwt.psd1 逐位元組相同' ((Get-FileHash -LiteralPath (Join-Path $pkg 'gwt.psd1')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'gwt.psd1')).Hash)
Assert-Eq '沒有 tag 時也能打包（本機試跑）' 0 (Invoke-Build (Join-Path $work 'notag')).Rc

# --- 套件本身：放進 PSModulePath 之後，打 gwt 就會自動載入（Install-PSResource 之後的使用情境）---------------
$loaded = & $pwshExe -NoProfile -NonInteractive -Command "`$env:PSModulePath = '$out1' + [System.IO.Path]::PathSeparator + `$env:PSModulePath; 'BEFORE=' + [bool](Get-Module gwt); 'TYPE=' + (Get-Command gwt).CommandType; 'VER=' + (gwt --version); 'EXPORTS=' + ((Get-Module gwt).ExportedCommands.Keys -join ',')" 2>&1
$loaded = (@($loaded | ForEach-Object { "$_" }) -join "`n")
Assert-Contains '還沒 Import-Module 就能找到 gwt（自動載入靠 FunctionsToExport）' 'BEFORE=False' $loaded
Assert-Contains 'gwt 是函式' 'TYPE=Function' $loaded
Assert-Contains '自動載入的 gwt 回報正確的版本' "VER=gwt $version" $loaded
Assert-Contains '只匯出 gwt 一個命令' 'EXPORTS=gwt' $loaded

# --- 清單欄位的內容（Gallery 顯示與搜尋用）-----------------------------------------------------------------
Assert-True '有作者' (-not [string]::IsNullOrWhiteSpace($manifest.Author))
Assert-Contains '作者與 LICENSE 的著作權人一致' 'Will' $manifest.Author
Assert-True '描述夠長，足以說明這個模組在做什麼' ($manifest.Description.Length -ge 100)
Assert-Eq '只支援 PowerShell 7（Core）' 'Core' ($manifest.CompatiblePSEditions -join ',')
Assert-Eq '最低 PowerShell 7.0' '7.0' $manifest.PowerShellVersion
Assert-Eq 'FunctionsToExport 明確只有 gwt（不是 *）' 'gwt' ($manifest.FunctionsToExport -join ',')
Assert-True 'GUID 有效且不是空的' ([guid]::Parse($manifest.GUID) -ne [guid]::Empty)
Assert-True 'Tags 夠 Gallery 搜尋用' (@($manifest.PrivateData.PSData.Tags).Count -ge 5)
Assert-True '授權與專案網址都是 https' (($manifest.PrivateData.PSData.LicenseUri -like 'https://*') -and ($manifest.PrivateData.PSData.ProjectUri -like 'https://*'))

# --- 該被擋下來的：改壞專案根目錄的一份副本，打包腳本必須拒絕，而且不留下半成品 ----------------------------
function New-RootCopy {
  $d = Join-Path $work ('root-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Path $d | Out-Null
  foreach ($f in 'gwt.psd1', 'gwt.psm1', 'gwt.zsh', 'LICENSE') { Copy-Item -LiteralPath (Join-Path $root $f) -Destination $d }
  return $d
}
function Edit-File {
  param([string]$Dir, [string]$Name, [string]$Old, [string]$New)
  $p = Join-Path $Dir $Name
  $t = [System.IO.File]::ReadAllText($p)
  if (-not $t.Contains($Old)) { throw "測試設定有誤：$Name 裡找不到要取代的文字：$Old" }
  [System.IO.File]::WriteAllText($p, $t.Replace($Old, $New), [System.Text.UTF8Encoding]::new($false))
}
function Expect-Refusal {
  param([string]$Label, [scriptblock]$Mutate, [string]$ExpectInMessage, [string]$Tag = '')
  $d = New-RootCopy
  & $Mutate $d
  $o = Join-Path $work ('out-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  $res = Invoke-Build $o $Tag $d
  Assert-True "$Label：被拒絕（結束碼不是 0）" ($res.Rc -ne 0)
  Assert-Contains "$Label：訊息說明原因" $ExpectInMessage $res.Output
  Assert-True "$Label：沒有留下半成品" (-not (Test-Path -LiteralPath (Join-Path $o 'gwt')))
}

Expect-Refusal '清單版本與模組不一致' { param($d) Edit-File $d 'gwt.psd1' "ModuleVersion         = '$version'" "ModuleVersion         = '9.9.9'" } '版本不一致'
Expect-Refusal '模組版本與清單不一致' { param($d) Edit-File $d 'gwt.psm1' "`$script:GwtVersion = '$version'" "`$script:GwtVersion = '9.9.9'" } '版本不一致'
Expect-Refusal 'zsh 版版本與清單不一致' { param($d) Edit-File $d 'gwt.zsh' "GWT_VERSION='$version'" "GWT_VERSION='9.9.9'" } '版本不一致'
Expect-Refusal 'tag 與版本不一致' { param($d) } '不一致' -Tag 'v9.9.9'
Expect-Refusal 'tag 少了 v' { param($d) } 'vX.Y.Z' -Tag $version
Expect-Refusal 'tag 是預先發行版本' { param($d) } 'vX.Y.Z' -Tag "v$version-rc1"
Expect-Refusal 'tag 只有兩段' { param($d) } 'vX.Y.Z' -Tag 'v0.2'
Expect-Refusal '清單的版本帶預先發行後綴' { param($d) Edit-File $d 'gwt.psd1' "ModuleVersion         = '$version'" "ModuleVersion         = '$version-rc1'" } 'x.y.z'
Expect-Refusal '缺少描述' { param($d) Edit-File $d 'gwt.psd1' 'Description           = ' 'Descriptio_n          = ' } 'Description'
Expect-Refusal '匯出 *' { param($d) Edit-File $d 'gwt.psd1' "FunctionsToExport     = @('gwt')" "FunctionsToExport     = @('*')" } 'FunctionsToExport'
Expect-Refusal '多匯出一個函式' { param($d) Edit-File $d 'gwt.psd1' "FunctionsToExport     = @('gwt')" "FunctionsToExport     = @('gwt', 'Get-GwtWidth')" } 'FunctionsToExport'
Expect-Refusal '宣稱支援 Windows PowerShell' { param($d) Edit-File $d 'gwt.psd1' "CompatiblePSEditions  = @('Core')" "CompatiblePSEditions  = @('Core', 'Desktop')" } 'CompatiblePSEditions'
Expect-Refusal '最低版本低於 7.0' { param($d) Edit-File $d 'gwt.psd1' "PowerShellVersion     = '7.0'" "PowerShellVersion     = '5.1'" } 'PowerShellVersion'
Expect-Refusal 'GUID 無效' { param($d) Edit-File $d 'gwt.psd1' "GUID                  = '$($manifest.GUID)'" "GUID                  = '00000000-0000-0000-0000-000000000000'" } 'GUID'
Expect-Refusal '授權網址不是 https' { param($d) Edit-File $d 'gwt.psd1' 'LicenseUri               = ''https://' 'LicenseUri               = ''http://' } 'LicenseUri'
Expect-Refusal 'Tags 太少' { param($d) Edit-File $d 'gwt.psd1' "Tags                     = @('git', 'worktree', 'navigation', 'tui', 'cli', 'pwsh', 'PSEdition_Core')" "Tags                     = @('git')" } 'Tags'
Expect-Refusal '缺少授權檔' { param($d) Remove-Item -LiteralPath (Join-Path $d 'LICENSE') } 'LICENSE'

# --- 發佈用的 workflow：安全性質（當成文字檢查；PowerShell 7.0 沒有內建的 YAML 解析）---------------------------
$wfPath = Join-Path $root '.github\workflows\publish-psgallery.yml'
Assert-True 'workflow 檔案存在' (Test-Path -LiteralPath $wfPath)
$wf = @(Get-Content -LiteralPath $wfPath)

function Get-JobRange {
  param([string[]]$Lines, [string]$Job)
  $start = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match "^  ${Job}:\s*$") { $start = $i; break }
  }
  if ($start -lt 0) { return $null }
  $end = $Lines.Count
  for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^  [A-Za-z0-9_-]+:\s*$') { $end = $i; break }
  }
  return @{ Start = $start; End = $end }
}
$verifyRange = Get-JobRange $wf 'verify'
$publishRange = Get-JobRange $wf 'publish'
Assert-True 'workflow 有 verify 與 publish 兩個 job' (($null -ne $verifyRange) -and ($null -ne $publishRange))

$codeLines = @($wf | Where-Object { $_.TrimStart() -notmatch '^#' })
Assert-True '預設沒有任何 token 權限（頂層 permissions: {}）' (@($wf | Where-Object { $_ -match '^permissions:\s*\{\}\s*$' }).Count -eq 1)
Assert-True '只由發佈 release 觸發發佈（有 release: published）' (($wf -join "`n") -match '(?ms)^on:\s*\n\s+release:\s*\n\s+types:\s*\[published\]')
Assert-True '手動執行（workflow_dispatch）存在，但只會走 verify（發佈 job 的 if 限定 release 事件）' ((($wf -join "`n") -match '(?m)^\s+workflow_dispatch:') -and (($wf[$publishRange.Start..$publishRange.End] -join "`n") -match "if:\s*github\.event_name == 'release'"))
Assert-True '不會被 pull request 觸發（沒有 pull_request／pull_request_target）' (-not (($codeLines -join "`n") -match 'pull_request'))
Assert-True '預先發行的 release 不發佈' (($wf[$publishRange.Start..$publishRange.End] -join "`n") -match '!github\.event\.release\.prerelease')

# 每個 uses: 都釘在 40 碼的 commit SHA
$uses = @($codeLines | Where-Object { $_ -match '^\s*-?\s*uses:' })
Assert-True '有用到 action（這項檢查才有意義）' ($uses.Count -ge 3)
foreach ($u in $uses) {
  Assert-True "action 釘在 commit SHA，不是會被改動的標籤：$($u.Trim())" ($u -match 'uses:\s*[\w./-]+@[0-9a-f]{40}\b')
}

# 祕密：整份檔案只出現一次，在 publish job，而且是環境變數的值（不是 run 的內容、不在 verify）
$secretLines = @(for ($i = 0; $i -lt $wf.Count; $i++) { if ($wf[$i] -match 'secrets\.' -and $wf[$i].TrimStart() -notmatch '^#') { [pscustomobject]@{ No = $i; Text = $wf[$i] } } })
Assert-Rc '祕密整份 workflow 只被引用一次' 1 $secretLines.Count
if ($secretLines.Count -eq 1) {
  $s = $secretLines[0]
  Assert-True '祕密在 publish job 裡（verify 看不到）' (($s.No -gt $publishRange.Start) -and ($s.No -lt $publishRange.End))
  Assert-True '祕密只當環境變數的值（NAME: ${{ secrets.NAME }}），不在 run 的內容裡' ($s.Text -match '^\s+PSGALLERY_API_KEY:\s*\$\{\{\s*secrets\.PSGALLERY_API_KEY\s*\}\}\s*$')
}
Assert-True '祕密只出現在一個步驟的 env（發佈那一步），「確認已上架」那一步拿不到' (@($secretLines).Count -eq 1)
Assert-True 'publish job 使用受保護的環境 psgallery（要求核准、只放行 v* 的 tag）' (($wf[$publishRange.Start..$publishRange.End] -join "`n") -match '(?m)^\s+environment:\s*psgallery\s*$')
Assert-True 'publish job 沒有 token 權限（permissions: {}）' (($wf[$publishRange.Start..$publishRange.End] -join "`n") -match '(?m)^\s+permissions:\s*\{\}\s*$')
Assert-True 'verify job 只有唯讀的 contents 權限' (($wf[$verifyRange.Start..$verifyRange.End] -join "`n") -match '(?ms)^\s+permissions:\s*\n\s+contents:\s*read\s*\n')
Assert-True '不留下 git 憑證（checkout 設 persist-credentials: false）' (($wf -join "`n") -match 'persist-credentials:\s*false')

# 腳本注入：外部輸入（${{ github.event… }}、${{ inputs… }}）只能放在 env 的值或 if 條件，不能展開進 run 的內容
$inRun = $false; $runIndent = 0; $leaks = @()
foreach ($line in $wf) {
  if ($line.TrimStart().StartsWith('#')) { continue }
  $indent = $line.Length - $line.TrimStart().Length
  if ($inRun -and $line.Trim() -ne '' -and $indent -le $runIndent) { $inRun = $false }
  if ($inRun -and $line -match '\$\{\{') { $leaks += $line.Trim() }
  if ($line -match '^(\s*)(-\s+)?run:\s*\|') { $inRun = $true; $runIndent = $line.IndexOf('run:') }
}
Assert-Rc 'run 的內容裡沒有任何 ${{ }} 展開（外部輸入只經由環境變數傳入）' 0 $leaks.Count
foreach ($l in $leaks) { Write-TestLine "        展開在 run 裡：$l" }

# --- 文件指到的東西都存在 ----------------------------------------------------------------------------------
Assert-True '維護文件 docs/publishing.md 存在' (Test-Path -LiteralPath (Join-Path $root 'docs\publishing.md'))

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Complete-Tests
