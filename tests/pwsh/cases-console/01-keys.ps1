# 真主控台：在 ConPTY 裡的真正 pwsh 送真正的按鍵（方向鍵、j/k、數字、q、單獨的 Esc、Ctrl+C）。
# 這些路徑在按鍵驅動測試裡是用掛鉤餵的；這裡驗證 [Console]::ReadKey 與主控台輸入翻譯。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"
. "$env:GWT_ROOT\tests\pwsh\lib\ConPty.ps1"

$shop = Join-Path $env:GWT_FIXTURE 'shop'

# 每一輪：回到 shop、印 RUN-n、跑 gwt、印結果。最後再印 Ctrl+C 模式有沒有被還原。
$scenario = {
  Import-Module (Join-Path $env:GWT_ROOT 'gwt.psm1')
  $shop = Join-Path $env:GWT_FIXTURE 'shop'
  foreach ($n in 1..7) {
    Set-Location -LiteralPath $shop
    "RUN-$n"
    gwt
    "RESULT-$n rc=$LASTEXITCODE ok=$? pwd=$((Get-Location).Path)"
  }
  "TREAT-C-AS-INPUT=$([Console]::TreatControlCAsInput)"
}

$k = $script:Keys
$steps = @()
$steps += New-RunSteps 1 @(($k.Down * 2), $k.Enter)                       # ↓↓ Enter
$steps += New-RunSteps 2 @($k.Up, $k.Enter)                                # ↑ 循環到最後
$steps += New-RunSteps 3 @('jj', $k.Enter)                                 # vim 鍵
$steps += New-RunSteps 4 @('4')                                            # 數字鍵直接跳
$steps += New-RunSteps 5 @('q')                                            # 取消
$steps += New-RunSteps 6 @($k.Esc)                                         # 單獨的 Esc（不是方向鍵）
$steps += New-RunSteps 7 @($k.CtrlC)                                       # Ctrl+C

$r = Invoke-InConsole -Script $scenario -Steps $steps -Rows 50 -Cols 200

Assert-True '沒有逾時、沒有等不到的步驟' ((-not $r.TimedOut) -and ($null -eq $r.WaitFailed))
if ($r.WaitFailed) { Write-TestLine "        等不到：$($r.WaitFailed)" }

$total = Get-FixtureCount $shop

$x = Get-RunResult $r.Screen 1
Assert-True '↓↓Enter 有結果' ($null -ne $x)
if ($x) {
  Assert-Rc '↓↓Enter 回傳 0' 0 $x.Rc
  Assert-True '↓↓Enter 的 $? 是 true' $x.Ok
  Assert-Eq '↓↓Enter 切換到第 3 筆（真的方向鍵）' (Get-FixturePath $shop 3) $x.Pwd
}

$x = Get-RunResult $r.Screen 2
if ($x) {
  Assert-Rc '↑Enter 回傳 0' 0 $x.Rc
  Assert-Eq '↑ 循環到最後一筆' (Get-FixturePath $shop $total) $x.Pwd
}
else { Assert-True '↑Enter 有結果' $false }

$x = Get-RunResult $r.Screen 3
if ($x) {
  Assert-Rc 'jjEnter 回傳 0' 0 $x.Rc
  Assert-Eq 'jjEnter 切換到第 3 筆' (Get-FixturePath $shop 3) $x.Pwd
}
else { Assert-True 'jjEnter 有結果' $false }

$x = Get-RunResult $r.Screen 4
if ($x) {
  Assert-Rc '數字 4 回傳 0' 0 $x.Rc
  Assert-Eq '數字 4 直接切到第 4 筆（不需 Enter）' (Get-FixturePath $shop 4) $x.Pwd
}
else { Assert-True '數字 4 有結果' $false }

$x = Get-RunResult $r.Screen 5
if ($x) {
  Assert-Rc 'q 取消回傳 1' 1 $x.Rc
  Assert-True 'q 取消的 $? 是 false（gwt && next 會停）' (-not $x.Ok)
  Assert-Eq 'q 取消後位置不變' $shop $x.Pwd
}
else { Assert-True 'q 有結果' $false }

$x = Get-RunResult $r.Screen 6
if ($x) {
  Assert-Rc '單獨的 Esc 取消回傳 1' 1 $x.Rc
  Assert-Eq 'Esc 取消後位置不變' $shop $x.Pwd
}
else { Assert-True 'Esc 有結果' $false }

$x = Get-RunResult $r.Screen 7
if ($x) {
  Assert-Rc 'Ctrl+C 回傳 130（行程沒有被中斷，腳本繼續跑）' 130 $x.Rc
  Assert-True 'Ctrl+C 的 $? 是 false' (-not $x.Ok)
  Assert-Eq 'Ctrl+C 後位置不變' $shop $x.Pwd
}
else { Assert-True 'Ctrl+C 有結果（腳本沒有被 Ctrl+C 殺掉）' $false }

Assert-Screen 'Ctrl+C 模式在 gwt 結束後被還原' '^TREAT-C-AS-INPUT=False$' $r.Screen
Assert-NotScreen '選單離開後整塊被擦掉（沒有殘留的項目列）' '\[\d+\]' $r.Screen
Assert-NotScreen '選單離開後沒有表頭殘影' '請選擇' $r.Screen

Complete-Tests
