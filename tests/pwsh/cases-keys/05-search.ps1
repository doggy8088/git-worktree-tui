# 選單內的模糊搜尋：按 / 進入，直接打字，Esc 清除、Backspace、Ctrl+U、Ctrl+W
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$shop = Join-Path $env:GWT_FIXTURE 'shop'

function Go {
  param([string]$Keys, [int]$Rows = 20, [int]$Cols = 100)
  Enter-Fixture 'shop'
  Invoke-Gwt -Keys $Keys -Rows $Rows -Cols $Cols
}

# 按 / 進入搜尋，fuzzy 比對分支名稱：flogin → feature/login
$r = Go '/flogin<enter>'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '模糊搜尋選到 feature/login' (Find-FixturePath $shop 'shop-feature-login') (Get-Here)
Assert-Contains '搜尋模式的表頭' '搜尋：' $r.Raw

# 搜尋只比對目錄的最後一層：shopfix → shop-fix-cart-bug
$r = Go '/shopfix<enter>'
Assert-Eq '目錄名稱模糊搜尋' (Find-FixturePath $shop 'shop-fix-cart-bug') (Get-Here)

# 搜尋中的 Esc 只清除搜尋，不會取消選單；緊接的 Enter 不可被吃掉
$r = Go '/zzz<esc><enter>'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq 'Esc 清除搜尋後 Enter 選第 1 筆' (Get-FixturePath $shop 1) (Get-Here)

# Backspace 刪掉多打的一個字元（Windows 的 Backspace 與 Unix 的 DEL 都要支援）
$r = Go '/floginn<bksp><enter>'
Assert-Eq 'Backspace 後仍命中 feature/login' (Find-FixturePath $shop 'shop-feature-login') (Get-Here)
$r = Go '/floginn<del><enter>'
Assert-Eq 'DEL（0x7f）也能刪字' (Find-FixturePath $shop 'shop-feature-login') (Get-Here)

# 沒有符合項目時 Enter 不應切換；Ctrl+U 清空後才能選取
$r = Go '/zzz<enter><c-u><enter>'
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '清空搜尋後選第 1 筆' (Get-FixturePath $shop 1) (Get-Here)

# Ctrl+W 刪除最後一個詞：'fea log' → 'fea'（2 筆），再補 'ture' 不變
$env:GWT_CLEAR_ON_EXIT = '0'
$r = Go '/fea log<c-w>'
$screen = Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100
Assert-Screen 'Ctrl+W 之後剩下 fea 的結果' '^ITEM_ROWS=2$' $screen
Assert-Screen '表頭顯示剩下的查詢' '搜尋：fea▏' $screen

# 搜尋模式裡 q、j、k、數字都只是查詢字元，不會取消或移動
$r = Go '/q<esc><esc>'
Assert-Rc '搜尋中的 q 不取消；第二次 Esc 才取消' 1 $r.Rc
Assert-Rc '兩次 Esc 都被讀到（q 沒有提早取消）' 0 $r.Left

$r = Go '/1<enter>'
Assert-Rc '搜尋中的數字是查詢字元，沒有結果時 Enter 不動作（最後 EOF 取消）' 1 $r.Rc
Assert-Eq '位置不變' (Get-FixturePath $shop 1) (Get-Here)

# 搜尋後仍可用方向鍵改變選取，Enter 要切到第 2 筆結果
$r = Go '/f<down><enter>'
$screen = Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '方向鍵移到第 2 筆並切換' (Find-FixturePath $shop 'shop-fix-cart-bug') (Get-Here)
Assert-Screen '搜尋結果 4 筆' '^ITEM_ROWS=4$' $screen
Assert-Screen '光棒在第 2 筆結果' '^SELECTED=2$' $screen

# 搜尋讓清單從 5 筆縮到 1 筆時，舊的列一定要被擦掉
$r = Go '/flogin<enter>'
$screen = Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100
Assert-Screen '縮到 1 列' '^ITEM_ROWS=1$' $screen
Assert-Screen '剩下的是編號 1' '^INDEXES=1$' $screen
Assert-Screen '沒有重複的列' '^DUPLICATES=-$' $screen

# 搜尋模式的結果排序：連續命中者在前；同分維持 Git 的順序
$r = Go '/cart'
$screen = Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100
Assert-Screen 'cart 只命中 fix/cart-bug' '^ITEM_ROWS=1$' $screen

# 窄視窗加上「沒有符合」提示時，收尾仍要把整個區塊擦乾淨
Remove-Item Env:\GWT_CLEAR_ON_EXIT
$r = Go '/zzz<enter><c-u><enter>' -Rows 12 -Cols 30
$r.Cap.Append("AFTER=$(Get-Here)`n") | Out-Null
$screen = Get-ScreenReplay -Text $r.Cap.ToString() -Rows 12 -Cols 30
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '清空後選第 1 筆' (Get-FixturePath $shop 1) (Get-Here)
Assert-Screen '收尾後有輸出後續的文字' '^AFTER=' $screen
Assert-NotScreen '窄視窗收尾後沒有表頭殘影' '請選擇 Worktree' $screen
Assert-NotScreen '收尾後沒有「沒有符合」殘影' '沒有符合' $screen
Assert-NotScreen '收尾後沒有搜尋表頭殘影' '搜尋：' $screen

# 沒有結果時的畫面：提示取代清單
$env:GWT_CLEAR_ON_EXIT = '0'
$r = Go '/zzz'
$screen = Get-ScreenReplay -Text $r.Raw -Rows 20 -Cols 100
Assert-Screen '沒有結果時顯示提示' '沒有符合搜尋條件的 worktree' $screen
Assert-Screen '沒有結果時沒有項目列' '^ITEM_ROWS=0$' $screen

# 在搜尋結果很長的清單裡（40 筆）也能運作，而且視窗化仍然正確
Enter-Fixture 'many'
$many = Join-Path $env:GWT_FIXTURE 'many'
$r = Invoke-Gwt -Keys '/m3<down><down>' -Rows 12 -Cols 80
$screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols 80
Assert-Screen '命中筆數超過畫面時仍只畫 9 列' '^ITEM_ROWS=9$' $screen
Assert-Screen '下方標示搜尋結果的範圍' '顯示 \d+-\d+，共 \d+ 筆' $screen
Assert-Screen '搜尋後視窗化沒有重複的列' '^DUPLICATES=-$' $screen
Assert-Screen '方向鍵移動後選取第 3 筆結果' '^SELECTED=3$' $screen

Complete-Tests
