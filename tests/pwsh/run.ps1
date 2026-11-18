# -----------------------------------------------------------------------------
# PowerShell 版測試總入口（對應 tests/run.sh）。需要 pwsh 7 與 git，沒有其他依賴。
#
#   pwsh tests/pwsh/run.ps1                 全部（語法檢查 + 單元 + 按鍵驅動）
#   pwsh tests/pwsh/run.ps1 -Filter search  只跑檔名含 search 的測試（可以給多個：-Filter a,b）
#   pwsh tests/pwsh/run.ps1 -Keep           保留暫存目錄，方便失敗時進去追
#   pwsh tests/pwsh/run.ps1 -SkipConsole    略過需要真主控台（ConPTY）的測試
#
# 測試分三類：
#   cases/          單元測試：直接呼叫模組內部函式，或用 gwt --list 這類不需要終端機的路徑
#   cases-keys/     按鍵驅動：用 gwt.psm1 的測試掛鉤餵按鍵、收畫面，再重播成最終畫面檢查
#   cases-console/  真主控台：在 Windows 的 ConPTY 裡跑真正的 pwsh，送真的按鍵
#                   （只有 Windows 有；其他平台自動略過）
#
# 每個測試檔都在獨立的 `pwsh -NoProfile` 處理序裡執行：不受使用者 $PROFILE 影響
# （你的 profile 很可能已經載入了 gwt），測試之間也不會互相污染狀態。
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
  [string[]]$Filter = @(),
  [switch]$Keep,
  [switch]$SkipConsole
)

$ErrorActionPreference = 'Stop'
# pwsh -File 不會把 "-Filter a,b" 解析成陣列，而是一整個字串，所以自己用逗號切開
$Filter = @($Filter | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$pwshExe = (Get-Process -Id $PID).Path

# 子處理序的輸出是 UTF-8，這裡也要用 UTF-8 解碼，中文標籤才不會變亂碼
$savedEncoding = [Console]::OutputEncoding
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("gwt-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null

$script:pass = 0
$script:fail = 0
$script:failed = [System.Collections.Generic.List[string]]::new()

function Write-Line { param([string]$Text) [Console]::Out.WriteLine($Text) }

try {
  # ---- 乾淨的環境：使用者自己的 GWT_* 設定、NO_COLOR 不能影響測試結果 ----------
  Get-ChildItem Env: | Where-Object { $_.Name -like 'GWT_*' -or $_.Name -eq 'NO_COLOR' } |
    ForEach-Object { Remove-Item -LiteralPath "Env:\$($_.Name)" }
  $env:GWT_ROOT = $root
  $env:GWT_FIXTURE = $work
  $env:GWT_LANG = 'zh'
  $env:GIT_CONFIG_NOSYSTEM = '1'
  $env:GIT_CONFIG_GLOBAL = Join-Path $work 'gitconfig'
  $env:GIT_TERMINAL_PROMPT = '0'

  # ---- 語法檢查（等同 zsh -n）------------------------------------------------
  Write-Line "語法檢查"
  $lintOk = $true
  $files = @(Get-ChildItem -LiteralPath $root -Recurse -Include *.ps1, *.psm1 -File |
      Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|site)[\\/]' })
  foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
      $lintOk = $false
      Write-Line "  失敗  $($f.Name)"
      foreach ($e in $errors) { Write-Line "        $($e.Extent.StartLineNumber): $($e.Message)" }
    }
  }
  if ($lintOk) { Write-Line "  通過  $($files.Count) 個 .ps1 / .psm1 檔案都能解析"; $script:pass++ }
  else { $script:fail++; $script:failed.Add('語法檢查') }

  # ---- 測試資料 ---------------------------------------------------------------
  Write-Line "`n建立測試資料 ..."
  $buildLog = Join-Path $work 'build.log'
  $out = & $pwshExe -NoProfile -File (Join-Path $PSScriptRoot 'fixtures\Build-Fixtures.ps1') -Root $work 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Line "建立測試資料失敗："
    $out | ForEach-Object { Write-Line "    $_" }
    exit 1
  }

  function Invoke-Case {
    param([System.IO.FileInfo]$File)
    $log = Join-Path $work "log-$($File.Name).txt"
    $output = & $pwshExe -NoProfile -NonInteractive -File $File.FullName 2>&1
    $rc = $LASTEXITCODE
    $output | ForEach-Object { "$_" } | Set-Content -LiteralPath $log -Encoding utf8
    if ($rc -eq 0) {
      Write-Line "  通過  $($File.Name)"
      $script:pass++
    }
    else {
      Write-Line "  失敗  $($File.Name)（結束碼 $rc）"
      $script:fail++
      $script:failed.Add($File.Name)
      Get-Content -LiteralPath $log | ForEach-Object { Write-Line "        $_" }
    }
  }

  function Invoke-Group {
    param([string]$Title, [string]$Dir)
    # -Filter 可以給多個：檔名符合任何一個就跑；沒給就全跑
    $cases = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $Dir) -Filter *.ps1 -File -ErrorAction SilentlyContinue |
        Where-Object { $n = $_.Name; (@($Filter).Count -eq 0) -or (@(@($Filter) | Where-Object { $n -like "*$_*" }).Count -gt 0) } |
        Sort-Object Name)
    if ($cases.Count -eq 0) { return }
    Write-Line "`n$Title"
    foreach ($c in $cases) { Invoke-Case $c }
  }

  Invoke-Group '單元測試（不需要終端機）' 'cases'
  Invoke-Group '按鍵驅動測試（測試掛鉤餵按鍵、重播畫面）' 'cases-keys'

  if (-not $SkipConsole) {
    if ($IsWindows) {
      Invoke-Group '真主控台測試（ConPTY 裡的真正 pwsh）' 'cases-console'
    }
    else {
      Write-Line "`n真主控台測試：略過（只支援 Windows 的 ConPTY）"
    }
  }

  Write-Line "`n========================================"
  Write-Line "通過 $($script:pass)，失敗 $($script:fail)"
  if ($script:fail -gt 0) {
    Write-Line "`n失敗的測試："
    $script:failed | ForEach-Object { Write-Line "  - $_" }
  }
}
finally {
  try { [Console]::OutputEncoding = $savedEncoding } catch { }
  if ($Keep) { Write-Line "`n（保留測試目錄：$work）" }
  else { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:fail -gt 0) { exit 1 }
exit 0
