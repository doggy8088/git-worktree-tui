# 取消與中斷：q、Esc、Ctrl+C、輸入結束、保留選單、例外時仍要還原游標
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

function Cancel-With {
  param([string]$Keys)
  Enter-Fixture 'shop'
  $script:before = Get-Here
  Invoke-Gwt -Keys $Keys
}

$r = Cancel-With 'q'
Assert-Rc '按 q 取消回傳 1' 1 $r.Rc
Assert-Eq '目錄維持不變' $before (Get-Here)
Assert-Contains '選單被擦掉' "$ESC[J" $r.Raw
Assert-Contains '游標復原' "$ESC[?25h" $r.Raw

$r = Cancel-With 'Q'
Assert-Rc '大寫 Q 也取消' 1 $r.Rc

$r = Cancel-With '<esc>'
Assert-Rc '單獨按 Esc 視為取消（不是方向鍵）' 1 $r.Rc
Assert-Eq '目錄維持不變' $before (Get-Here)
Assert-Contains '游標復原' "$ESC[?25h" $r.Raw

# Esc 之後馬上按 Enter：Esc 先取消，Enter 不會被吃進任何序列
$r = Cancel-With '<esc><enter>'
Assert-Rc 'Esc 取消後不再處理後面的按鍵' 1 $r.Rc
Assert-Rc '後面的 Enter 沒被讀走' 1 $r.Left

# Ctrl+C 中斷：回傳 130、目錄不變、游標一定要還回來（原文最在意的點）
$r = Cancel-With '<c-c>'
Assert-Rc 'Ctrl+C 回傳 130' 130 $r.Rc
Assert-Eq '目錄維持不變' $before (Get-Here)
Assert-Contains '游標復原' "$ESC[?25h" $r.Raw
Assert-Contains '選單被擦掉' "$ESC[J" $r.Raw

# 搜尋模式中的 Ctrl+C 也一樣是 130
$r = Cancel-With '/abc<c-c>'
Assert-Rc '搜尋中 Ctrl+C 回傳 130' 130 $r.Rc

# 讀不到輸入（EOF）：當作取消，並且還原游標
$r = Cancel-With ''
Assert-Rc '輸入結束回傳 1' 1 $r.Rc
Assert-Contains 'EOF 時游標復原' "$ESC[?25h" $r.Raw

# GWT_CLEAR_ON_EXIT=0 時選單要留在畫面上（原文的預設行為）
$env:GWT_CLEAR_ON_EXIT = '0'
$r = Cancel-With 'q'
Assert-Rc '取消回傳 1' 1 $r.Rc
Assert-Contains '游標仍然復原' "$ESC[?25h" $r.Raw
Assert-NotContains '不擦掉選單' "$ESC[J" $r.Raw
Assert-Screen '選單留在畫面上' '^請選擇 Worktree' (Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100)
Remove-Item Env:\GWT_CLEAR_ON_EXIT

# 按鍵來源丟出例外：不論怎麼離開，游標都要回來
Enter-Fixture 'shop'
$cap = [System.Text.StringBuilder]::new()
Invoke-InGwt {
  param($buf)
  $script:Hooks.Interactive = $true
  $script:Hooks.ReadKey = { throw 'boom' }
  $script:Hooks.KeyAvailable = { $false }
  $script:Hooks.Write = { param($t) [void]$buf.Append($t) }.GetNewClosure()
} @($cap)
$env:GWT_HEIGHT = '20'; $env:GWT_WIDTH = '80'
$threw = $false
try { gwt 2>&1 | Out-Null } catch { $threw = $true }
Invoke-InGwt { $script:Hooks.Interactive = $null; $script:Hooks.ReadKey = $null; $script:Hooks.KeyAvailable = $null; $script:Hooks.Write = $null }
Assert-Contains '例外時游標也會復原' "$ESC[?25h" $cap.ToString()
Assert-Eq '例外時目錄不變' $before (Get-Here)

Complete-Tests
