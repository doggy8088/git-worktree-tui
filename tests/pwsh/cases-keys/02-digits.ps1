# 數字鍵：直接跳轉、超出範圍、多位數、只按一位數的等待、等待時收到其他按鍵
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$shop = Join-Path $env:GWT_FIXTURE 'shop'
$twelve = Join-Path $env:GWT_FIXTURE 'twelve'
Assert-Rc '測試資料 twelve 應有 12 筆' 12 (Get-FixtureCount $twelve)

Enter-Fixture 'shop'
$r = Invoke-Gwt -Keys '4'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '按 4 直接切到第 4 筆（不需要 Enter）' (Get-FixturePath $shop 4) (Get-Here)

# 只有 5 筆時按 9 應被忽略，選單繼續等待輸入；接著按 q 取消
Enter-Fixture 'shop'
$before = Get-Here
$r = Invoke-Gwt -Keys '9q'
Assert-Rc '取消回傳 1' 1 $r.Rc
Assert-Eq '超出範圍的數字鍵不會切換' $before (Get-Here)
Assert-Rc 'q 有被讀到（9 被忽略後選單仍在）' 0 $r.Left

# 0 不是有效的第一位數
Enter-Fixture 'shop'
$r = Invoke-Gwt -Keys '0<down><enter>'
Assert-Eq '0 被忽略，後面的按鍵照常運作' (Get-FixturePath $shop 2) (Get-Here)

# 12 筆時按 1 再按 2，跳到第 12 筆（多位數編號）
$env:GWT_DIGIT_TIMEOUT = '0.2'
Enter-Fixture 'twelve'
$r = Invoke-Gwt -Keys '12'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '按 12 切到第 12 筆' (Get-FixturePath $twelve 12) (Get-Here)

Enter-Fixture 'twelve'
$r = Invoke-Gwt -Keys '10'
Assert-Eq '0 可以當第二位數：10 切到第 10 筆' (Get-FixturePath $twelve 10) (Get-Here)

# 再加一位就爆了（9 → 90 > 12），不必等 timeout
Enter-Fixture 'twelve'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$env:GWT_DIGIT_TIMEOUT = '3'
$r = Invoke-Gwt -Keys '9'
$sw.Stop()
Assert-Eq '9 直接切到第 9 筆' (Get-FixturePath $twelve 9) (Get-Here)
Assert-True '不必等待第二位數（遠小於 3 秒的 timeout）' ($sw.Elapsed.TotalSeconds -lt 2)

# 12 筆時 3 也不可能再接第二位數（30 > 12），同樣不必等
Enter-Fixture 'twelve'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Gwt -Keys '3'
$sw.Stop()
Assert-Eq '3 直接切到第 3 筆' (Get-FixturePath $twelve 3) (Get-Here)
Assert-True '3 不必等待（遠小於 3 秒的 timeout）' ($sw.Elapsed.TotalSeconds -lt 2)

# 12 筆時只按一個 1（後面可能接 0、1、2）：等 timeout 後跳到第 1 筆，而不是卡住
$env:GWT_DIGIT_TIMEOUT = '0.3'
Set-Location -LiteralPath (Join-Path $env:GWT_FIXTURE 'twelve-w05')
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Gwt -Keys '1'
$sw.Stop()
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '單一的 1 在多位數清單中仍可用' (Get-FixturePath $twelve 1) (Get-Here)
Assert-True '有等第二位數（至少 timeout 的一半）' ($sw.Elapsed.TotalSeconds -ge 0.15)
Assert-True '但不會卡住（遠小於 5 秒）' ($sw.Elapsed.TotalSeconds -lt 5)

# 等待第二位數時收到的是別的按鍵：不會被吃掉（這裡是 j）
Enter-Fixture 'twelve'
$r = Invoke-Gwt -Keys '1j<enter>'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '1 之後的 j 不是數字，1 立刻生效' (Get-FixturePath $twelve 1) (Get-Here)

# 超出範圍的兩位數（13 > 12）：忽略，選單繼續
Enter-Fixture 'twelve'
$before = Get-Here
$r = Invoke-Gwt -Keys '13q'
Assert-Rc '超出範圍的兩位數被忽略，q 取消' 1 $r.Rc
Assert-Eq '位置不變' $before (Get-Here)

# 被忽略的數字不能弄掉目前的選取：5 筆時按 9，光棒要還在原處，Enter 仍然能確認
Enter-Fixture 'shop'
$r = Invoke-Gwt -Keys '9<enter>'
Assert-Rc '超出範圍的 9 之後 Enter 仍可確認（回傳 0）' 0 $r.Rc
Assert-Eq 'Enter 選的是原本反白的第 1 筆' (Get-FixturePath $shop 1) (Get-Here)

Enter-Fixture 'shop'
$r = Invoke-Gwt -Keys '9<down><enter>'
Assert-Eq '超出範圍的 9 之後 ↓ 從第 1 筆移到第 2 筆' (Get-FixturePath $shop 2) (Get-Here)

Enter-Fixture 'shop'
$r = Invoke-Gwt -Keys '9<up><enter>'
Assert-Eq '超出範圍的 9 之後 ↑ 從第 1 筆循環到最後一筆' (Get-FixturePath $shop (Get-FixtureCount $shop)) (Get-Here)

Enter-Fixture 'shop'
$env:GWT_CLEAR_ON_EXIT = '0'
$r = Invoke-Gwt -Keys '9' -Rows 20 -Cols 100
Remove-Item Env:\GWT_CLEAR_ON_EXIT
Assert-Screen '超出範圍的 9 之後光棒仍在第 1 筆（沒有消失）' '^SELECTED=1$' (Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100)

Set-Location -LiteralPath (Join-Path $env:GWT_FIXTURE 'twelve-w05')
$r = Invoke-Gwt -Keys '13<enter>'
Assert-Rc '12 筆時 13 被忽略，Enter 仍可確認' 0 $r.Rc
Assert-Eq '13 被忽略後 Enter 選原本反白的第 1 筆' (Get-FixturePath $twelve 1) (Get-Here)

# 等待第二位數的時候按 Ctrl+C：是中斷，不能反而讓第 1 筆生效、切換目錄、回報成功
Set-Location -LiteralPath (Join-Path $env:GWT_FIXTURE 'twelve-w05')
$here = Get-Here
$r = Invoke-Gwt -Keys '1<c-c>'
Assert-Rc '等第二位數時按 Ctrl+C 回傳 130' 130 $r.Rc
Assert-Eq 'Ctrl+C 之後沒有切換目錄' $here (Get-Here)
Assert-Contains 'Ctrl+C 之後游標有還原' "$ESC[?25h" $r.Raw

Complete-Tests
