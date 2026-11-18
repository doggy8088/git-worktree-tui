# 移動與確認：方向鍵、vim 風格的 j/k、到頭尾循環、Enter
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$shop = Join-Path $env:GWT_FIXTURE 'shop'
$total = Get-FixtureCount $shop

function Go {
  param([string]$Keys)
  Enter-Fixture 'shop'
  Invoke-Gwt -Keys $Keys
}

$r = Go '<down><down><enter>'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '↓↓Enter 切換到第 3 筆' (Get-FixturePath $shop 3) (Get-Here)
Assert-Contains '離開時游標一定要復原' "$ESC[?25h" $r.Raw
Assert-Contains '選單期間游標是隱藏的' "$ESC[?25l" $r.Raw
Assert-Contains '離開時擦掉選單' "$ESC[J" $r.Raw

$r = Go '<up><enter>'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '在第 1 筆按上移，循環到最後一筆' (Get-FixturePath $shop $total) (Get-Here)

$r = Go ('<down>' * $total + '<enter>')
Assert-Eq '往下走一圈回到第 1 筆' (Get-FixturePath $shop 1) (Get-Here)

$r = Go 'jj<enter>'
Assert-Eq 'jjEnter 切換到第 3 筆' (Get-FixturePath $shop 3) (Get-Here)

$r = Go 'jjk<enter>'
Assert-Eq 'jjk 回到第 2 筆' (Get-FixturePath $shop 2) (Get-Here)

$r = Go 'J<enter>'
Assert-Eq '大寫 J 也能往下' (Get-FixturePath $shop 2) (Get-Here)

$r = Go 'K<enter>'
Assert-Eq '大寫 K 在第 1 筆循環到最後' (Get-FixturePath $shop $total) (Get-Here)

$r = Go '<enter>'
Assert-Rc '一開始直接 Enter 回傳 0' 0 $r.Rc
Assert-Eq '一開始直接 Enter 選第 1 筆' (Get-FixturePath $shop 1) (Get-Here)

# 沒有意義的按鍵一律忽略，不會中斷選單
$r = Go 'x<c-u><c-w><bksp><enter>'
Assert-Rc '無意義的按鍵被忽略後仍可確認' 0 $r.Rc
Assert-Eq '無意義的按鍵不改變選取' (Get-FixturePath $shop 1) (Get-Here)
Assert-Rc '按鍵全部被吃掉' 0 $r.Left

# 選取的那一列在畫面上有光棒
$env:GWT_CLEAR_ON_EXIT = '0'
$r = Go '<down><down>'
$screen = Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100
Assert-Screen '游標停在第 3 筆' '^SELECTED=3$' $screen
Assert-Screen '5 列都畫出來' '^ITEM_ROWS=5$' $screen
Assert-Screen '表頭仍在' '^請選擇 Worktree' $screen
Assert-Screen '目前位置有標註' '\[main\].*\(目前位置\)' $screen

Complete-Tests
