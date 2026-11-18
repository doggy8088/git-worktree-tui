# 模組不污染使用者的工作階段（相當於 zsh 版的 path/PATH 迴歸測試與 emulate -L zsh）
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

# 只匯出 gwt 一個命令；內部函式與狀態都不能漏到外面
$mod = Get-Module gwt
Assert-Eq '只匯出 gwt 一個函式' 'gwt' ((@($mod.ExportedFunctions.Keys) | Sort-Object) -join ',')
Assert-Rc '沒有匯出變數' 0 @($mod.ExportedVariables.Keys).Count
Assert-Rc '沒有匯出別名' 0 @($mod.ExportedAliases.Keys).Count
Assert-True '內部函式不在使用者的命令清單裡' ($null -eq (Get-Command Read-GwtPorcelain -ErrorAction SilentlyContinue))
Assert-True '內部狀態不在全域變數裡' (@(Get-Variable -Scope Global | Where-Object { $_.Name -like '*Gwt*' -or $_.Name -like 'GWT*' }).Count -eq 0)

Enter-Fixture 'shop'

$pathBefore = $env:PATH
$epBefore = $ErrorActionPreference
$encBefore = [Console]::OutputEncoding.CodePage
$cwdBefore = [Environment]::CurrentDirectory
$policyBefore = $global:PSNativeCommandUseErrorActionPreference
$errBefore = $global:Error.Count

# 使用者把錯誤偏好設成 Stop、又開了原生命令錯誤即例外（很多腳本都這樣設）。
# 在非 repo 目錄 git rev-parse 會失敗，那是預期中的結果：
#   - 不能讓「原生命令結束碼非 0」這個例外漏出來（gwt 不是用 & git 呼叫，所以不會）
#   - 取消（沒有任何錯誤訊息的失敗）在 Stop 下也不能丟例外
#   - 帶訊息的失敗在 Stop 下會依 PowerShell 的慣例變成終止錯誤，訊息要是 gwt 自己的
$ErrorActionPreference = 'Stop'
$global:PSNativeCommandUseErrorActionPreference = $true
Enter-Fixture 'outside'
$message = ''
try { $null = gwt } catch { $message = $_.Exception.Message }
Assert-Contains 'Stop 偏好下失敗的例外是 gwt 的訊息，不是 git 的結束碼錯誤' '不在 Git 儲存庫中' $message
Assert-NotContains '不是原生命令的結束碼例外' 'non-zero exit code' $message
$silent = $true
try { gwt -ErrorAction SilentlyContinue } catch { $silent = $false }
Assert-True '明確指定 -ErrorAction SilentlyContinue 時不丟例外' $silent
Assert-Rc '而且結束碼仍是 1' 1 $global:LASTEXITCODE

Enter-Fixture 'shop'
$cancelThrew = $false
$queue = ConvertTo-KeyQueue 'q'
Invoke-InGwt {
  param($q)
  $script:Hooks.Interactive = $true
  $script:Hooks.ReadKey = { if ($q.Count -gt 0) { $q.Dequeue() } else { $null } }.GetNewClosure()
  $script:Hooks.KeyAvailable = { $q.Count -gt 0 }.GetNewClosure()
  $script:Hooks.Write = { param($t) }
} @(, $queue)
$env:GWT_HEIGHT = '20'; $env:GWT_WIDTH = '80'
try { gwt } catch { $cancelThrew = $true }
Invoke-InGwt { $script:Hooks.Interactive = $null; $script:Hooks.ReadKey = $null; $script:Hooks.KeyAvailable = $null; $script:Hooks.Write = $null }
Assert-True '取消在 Stop 偏好下不丟例外（取消不是錯誤，沒有訊息）' (-not $cancelThrew)
Assert-Rc '取消的結束碼仍是 1' 1 $global:LASTEXITCODE

$global:PSNativeCommandUseErrorActionPreference = $policyBefore
$ErrorActionPreference = $epBefore
Enter-Fixture 'shop'

$null = gwt --list
$null = gwt nomatch 2>&1
Assert-Eq '執行後 PATH 沒有被動到' $pathBefore $env:PATH
Assert-Eq '執行後 ErrorActionPreference 沒有被動到' "$epBefore" "$ErrorActionPreference"
Assert-Rc '沒有改動主控台輸出編碼' $encBefore ([Console]::OutputEncoding.CodePage)
Assert-Eq '沒有改動 .NET 的目前目錄' $cwdBefore ([Environment]::CurrentDirectory)
Assert-True '仍找得到 git' ($null -ne (Get-Command git -ErrorAction SilentlyContinue))

# 失敗用的錯誤紀錄會被清掉，不會一直累積在 $Error（只有帶訊息的錯誤才會留下）
$count = $global:Error.Count
Invoke-Gwt -Keys '<esc>' | Out-Null
Invoke-Gwt -Keys 'q' | Out-Null
Invoke-Gwt -Keys '<c-c>' | Out-Null
Assert-Rc '取消與中斷不在 $Error 留下紀錄' $count $global:Error.Count

# gwt 對原始碼的衛生要求：不用 -like 比對使用者資料（萬用字元），不用 -f 套用使用者資料當格式字串
$src = (Get-Content -LiteralPath (Join-Path $env:GWT_ROOT 'gwt.psm1') -Raw)
$code = ($src -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
Assert-NotContains '原始碼沒有 -like' ' -like ' $code
Assert-NotContains '原始碼沒有 Invoke-Expression' 'Invoke-Expression' $code

Complete-Tests
