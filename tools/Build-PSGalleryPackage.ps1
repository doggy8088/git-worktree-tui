# -----------------------------------------------------------------------------
# 把 gwt 打包成可以發佈到 PowerShell Gallery 的資料夾，並在打包之前把「發佈之後就改不了」的事情檢查完。
#
# 為什麼要有這支：PowerShell Gallery 上的版本發佈之後不能刪除、不能覆蓋，只能「下架」（unlist）。
# 版本號寫錯、清單欄位缺漏、少了授權檔，都要等發佈之後才發現就太遲了。所以所有能事先檢查的都在這裡檢查，
# 而且 CI 的發佈流程與本機試跑用的是同一支（tests/pwsh/cases/19-gallery-package.ps1 也測它）。
#
# 用法：
#   pwsh tools/Build-PSGalleryPackage.ps1 -OutputDir ./out                  # 本機試打包
#   pwsh tools/Build-PSGalleryPackage.ps1 -OutputDir ./out -Tag v0.2.0      # 發佈流程：版本必須等於 tag
#
# 成功時在 <OutputDir>/gwt/ 產生 gwt.psd1、gwt.psm1、LICENSE，並把資料夾路徑輸出到成功串流；
# 任何檢查不過都會丟例外（結束碼非 0），而且不會留下半成品。
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$OutputDir,
  # Git tag，例如 v0.2.0。給了就要求版本號等於它（發佈流程一定會給）
  [string]$Tag,
  # 專案根目錄；測試用它指到一份被改動過的副本，預設是這支腳本的上一層
  [string]$Root = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$Root = (Resolve-Path -LiteralPath $Root).ProviderPath
$manifestPath = Join-Path $Root 'gwt.psd1'
$modulePath = Join-Path $Root 'gwt.psm1'
$zshPath = Join-Path $Root 'gwt.zsh'
$licensePath = Join-Path $Root 'LICENSE'

foreach ($p in $manifestPath, $modulePath, $zshPath, $licensePath) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "找不到必要的檔案：$p" }
}

# ---- 版本：三個地方一致，發佈時還要等於 tag ------------------------------------------------
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$psm1 = [System.IO.File]::ReadAllText($modulePath)
$zsh = [System.IO.File]::ReadAllText($zshPath)

$m = [regex]::Match($psm1, '\$script:GwtVersion = ''([^'']+)''')
if (-not $m.Success) { throw "gwt.psm1 裡找不到 `$script:GwtVersion" }
$psm1Version = $m.Groups[1].Value
$m = [regex]::Match($zsh, 'GWT_VERSION=''([^'']+)''')
if (-not $m.Success) { throw "gwt.zsh 裡找不到 GWT_VERSION" }
$zshVersion = $m.Groups[1].Value
$manifestVersion = [string]$manifest.ModuleVersion

if ($manifestVersion -notmatch '^\d+\.\d+\.\d+$') {
  throw "ModuleVersion 必須是 x.y.z（不含預先發行後綴），實得：$manifestVersion"
}
if ($manifestVersion -ne $psm1Version -or $manifestVersion -ne $zshVersion) {
  throw "版本不一致：gwt.psd1 是 $manifestVersion、gwt.psm1 是 $psm1Version、gwt.zsh 是 $zshVersion。三個地方必須相同。"
}
if ($Tag) {
  $t = [regex]::Match($Tag, '^v(\d+\.\d+\.\d+)$')
  if (-not $t.Success) { throw "tag 的格式必須是 vX.Y.Z，實得：$Tag" }
  if ($t.Groups[1].Value -ne $manifestVersion) {
    throw "tag $Tag 與程式裡的版本 $manifestVersion 不一致。先把三個地方的版本改成 $($t.Groups[1].Value) 再發佈。"
  }
}

# ---- 清單欄位：Gallery 要求的與我們自己要求的 ------------------------------------------------
$problems = [System.Collections.Generic.List[string]]::new()
foreach ($key in 'RootModule', 'GUID', 'Author', 'Copyright', 'Description') {
  if (-not $manifest.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$manifest[$key])) { $problems.Add("缺少 $key") }
}
if ($manifest.ContainsKey('RootModule') -and $manifest.RootModule -ne 'gwt.psm1') { $problems.Add("RootModule 必須是 gwt.psm1，實得 $($manifest.RootModule)") }
if (-not $manifest.ContainsKey('PowerShellVersion') -or [version]$manifest.PowerShellVersion -lt [version]'7.0') { $problems.Add('PowerShellVersion 必須是 7.0 或更新') }
if (-not $manifest.ContainsKey('CompatiblePSEditions') -or (@($manifest.CompatiblePSEditions) -join ',') -ne 'Core') { $problems.Add("CompatiblePSEditions 必須剛好是 'Core'（不支援 Windows PowerShell 5.1）") }
if ((@($manifest.FunctionsToExport) -join ',') -ne 'gwt') { $problems.Add("FunctionsToExport 必須剛好是 'gwt'（不要用 '*'，也不要多匯出內部函式）") }
foreach ($key in 'CmdletsToExport', 'VariablesToExport', 'AliasesToExport') {
  if (-not $manifest.ContainsKey($key) -or @($manifest[$key]).Count -ne 0) { $problems.Add("$key 必須明確寫成空陣列 @()") }
}
$psd = if ($manifest.ContainsKey('PrivateData')) { $manifest.PrivateData.PSData } else { $null }
if ($null -eq $psd) {
  $problems.Add('缺少 PrivateData.PSData')
}
else {
  foreach ($key in 'LicenseUri', 'ProjectUri', 'ReleaseNotes') {
    if (-not $psd.ContainsKey($key) -or $psd[$key] -notmatch '^https://') { $problems.Add("PrivateData.PSData.$key 必須是 https 網址") }
  }
  if (-not $psd.ContainsKey('Tags') -or @($psd.Tags).Count -lt 3) { $problems.Add('PrivateData.PSData.Tags 至少要有 3 個，Gallery 靠它搜尋') }
}
if ($manifest.ContainsKey('GUID')) {
  $g = [guid]::Empty
  if (-not [guid]::TryParse([string]$manifest.GUID, [ref]$g) -or $g -eq [guid]::Empty) { $problems.Add('GUID 不是有效的 GUID') }
}
if ($problems.Count -gt 0) { throw ("gwt.psd1 不合格：`n  - " + ($problems -join "`n  - ")) }

# ---- 打包：先在暫存位置做完，檢查通過才換到目的地，失敗不留下半成品 ---------------------------------
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('gwt-pkg-' + [guid]::NewGuid().ToString('N'))
$stagedModule = Join-Path $staging 'gwt'
try {
  New-Item -ItemType Directory -Path $stagedModule -Force | Out-Null
  Copy-Item -LiteralPath $manifestPath, $modulePath, $licensePath -Destination $stagedModule

  # 用 Gallery 與 Import-Module 實際會讀的那份（暫存裡的副本）驗證，不是專案裡的
  $warnings = @()
  $tested = Test-ModuleManifest -Path (Join-Path $stagedModule 'gwt.psd1') -WarningVariable warnings -ErrorAction Stop
  if (@($warnings).Count -gt 0) { throw ("Test-ModuleManifest 有警告：`n  - " + (@($warnings) -join "`n  - ")) }
  if ((@($tested.ExportedFunctions.Keys) -join ',') -ne 'gwt') { throw "模組實際匯出的函式不是只有 gwt：$(@($tested.ExportedFunctions.Keys) -join ',')" }

  # 比對「集合」，不要比對排序後的字串：Sort-Object 依文化特性排序，大小寫與符號的順序不是固定的
  $files = @(Get-ChildItem -LiteralPath $stagedModule -Recurse -File | ForEach-Object { $_.Name })
  $diff = @(Compare-Object -ReferenceObject @('LICENSE', 'gwt.psd1', 'gwt.psm1') -DifferenceObject $files -CaseSensitive)
  if ($diff.Count -gt 0) { throw "套件內容不是預期的三個檔案（LICENSE、gwt.psd1、gwt.psm1）：$($files -join ', ')" }

  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
  $dest = Join-Path (Resolve-Path -LiteralPath $OutputDir).ProviderPath 'gwt'
  if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
  Move-Item -LiteralPath $stagedModule -Destination $dest
  Write-Verbose "已打包 gwt $manifestVersion 到 $dest"
  Get-Item -LiteralPath $dest | Select-Object -ExpandProperty FullName
}
finally {
  if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
}
