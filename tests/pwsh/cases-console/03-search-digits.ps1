# 真主控台：模糊搜尋（打字、Backspace、Ctrl+U、Ctrl+W、搜尋中的 Esc、方向鍵）與多位數編號。
# Esc 與後面的按鍵之間一定要隔一小段時間：VT 輸入裡「ESC 緊接著另一個字元」是 Alt+字元，
# ConPTY 會把它們併成一個按鍵；真人按 Esc 再按 Enter 之間一定隔得夠久。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"
. "$env:GWT_ROOT\tests\pwsh\lib\ConPty.ps1"

$k = $script:Keys
$shop = Join-Path $env:GWT_FIXTURE 'shop'
$twelve = Join-Path $env:GWT_FIXTURE 'twelve'
$nap = @{ Sleep = 350 }

# 每一輪用哪個 fixture：以環境變數傳給子行程
$plan = @('shop', 'shop', 'shop', 'shop', 'shop', 'shop', 'shop', 'twelve', 'twelve', 'twelve', 'twelve')
$env:GWT_TEST_PLAN = $plan -join ','

$scenario = {
  Import-Module (Join-Path $env:GWT_ROOT 'gwt.psm1')
  $plan = $env:GWT_TEST_PLAN -split ','
  for ($n = 1; $n -le $plan.Count; $n++) {
    Set-Location -LiteralPath (Join-Path $env:GWT_FIXTURE $plan[$n - 1])
    "RUN-$n"
    gwt
    "RESULT-$n rc=$LASTEXITCODE ok=$? pwd=$((Get-Location).Path)"
  }
}

$steps = @()
$steps += New-RunSteps 1 @('/flogin', $k.Enter)                                  # 子序列比對
$steps += New-RunSteps 2 @('/floginn', $k.Bksp, $k.Enter)                        # Backspace（0x7f）
$steps += New-RunSteps 3 @('/zzz', $nap, $k.Esc, $nap, $k.Enter)                 # 搜尋中 Esc 只清除搜尋
$steps += New-RunSteps 4 @('/zzz', $k.Enter, $k.CtrlU, $k.Enter)                 # 沒結果時 Enter 無效；Ctrl+U 清空
$steps += New-RunSteps 5 @('/lgnzz', $k.CtrlW, $k.Enter)                         # Ctrl+W 刪掉唯一的詞
$steps += New-RunSteps 6 @('/q', $nap, $k.Esc, $nap, $k.Esc)                     # 搜尋中的 q 是字元；兩次 Esc 才取消
$steps += New-RunSteps 7 @('/f', $k.Down, $k.Enter)                              # 搜尋結果裡用方向鍵
$steps += New-RunSteps 8 @('1', '2')                                             # 12 筆：1 再 2 = 第 12 筆
$steps += New-RunSteps 9 @('1', '0')                                             # 0 當第二位數
$steps += New-RunSteps 10 @('9')                                                 # 9 不可能再接第二位數，立刻生效
$steps += New-RunSteps 11 @('1')                                                 # 單一個 1：等 timeout 後生效

$r = Invoke-InConsole -Script $scenario -Steps $steps -Rows 50 -Cols 200 -TimeoutSec 90
Assert-True '沒有逾時、沒有等不到的步驟' ((-not $r.TimedOut) -and ($null -eq $r.WaitFailed))
if ($r.WaitFailed) { Write-TestLine "        等不到：$($r.WaitFailed)" }

function Check {
  param([int]$N, [string]$Label, [int]$Rc, [string]$Pwd)
  $x = Get-RunResult $r.Screen $N
  if ($null -eq $x) { Assert-True "$Label：有結果" $false; return }
  Assert-Rc "$Label：結束碼" $Rc $x.Rc
  Assert-Eq "$Label：位置" $Pwd $x.Pwd
}

Check 1 '/flogin Enter' 0 (Find-FixturePath $shop 'shop-feature-login')
Check 2 '/floginn Backspace Enter' 0 (Find-FixturePath $shop 'shop-feature-login')
Check 3 '/zzz Esc Enter（Esc 清除搜尋，Enter 選第 1 筆）' 0 (Get-FixturePath $shop 1)
Check 4 '/zzz Enter Ctrl+U Enter' 0 (Get-FixturePath $shop 1)
Check 5 '/lgnzz Ctrl+W Enter' 0 (Get-FixturePath $shop 1)
Check 6 '/q Esc Esc（搜尋中的 q 不取消）' 1 $shop
Check 7 '/f Down Enter' 0 (Find-FixturePath $shop 'shop-fix-cart-bug')
Check 8 '12' 0 (Get-FixturePath $twelve 12)
Check 9 '10' 0 (Get-FixturePath $twelve 10)
Check 10 '9' 0 (Get-FixturePath $twelve 9)
Check 11 '單一個 1（等 timeout）' 0 (Get-FixturePath $twelve 1)

Complete-Tests
