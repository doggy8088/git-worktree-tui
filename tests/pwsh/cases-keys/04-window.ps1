# 清單比畫面高、畫面很窄時的排版：視窗化、不折行、不留殘影
# 錯誤只會出現在「最終畫面」上，所以一律把輸出重播成畫面再檢查。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$many = Join-Path $env:GWT_FIXTURE 'many'
$twelve = Join-Path $env:GWT_FIXTURE 'twelve'
$longname = Join-Path $env:GWT_FIXTURE 'longname'
Assert-Rc '測試資料 many 應有 40 筆' 40 (Get-FixtureCount $many)

# 40 筆的清單放進 12 列的終端機：視窗要跟著選取項目捲動，而且不能出現重複的列
$env:GWT_CLEAR_ON_EXIT = '0'
Enter-Fixture 'many'
$before = Get-Here
$r = Invoke-Gwt -Keys ('<down>' * 15 + 'q') -Rows 12 -Cols 80
$screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols 80
Assert-Rc '取消回傳 1' 1 $r.Rc
Assert-Eq '取消後目錄不變' $before (Get-Here)
Assert-Screen '表頭沒有被捲出畫面' '^請選擇 Worktree' $screen
Assert-Screen '光棒在第 16 筆' '^ > \[16\]' $screen
Assert-Screen '可視列是 高度 - 3 = 9 列' '^ITEM_ROWS=9$' $screen
Assert-Screen '視窗跟著捲到 8-16' '^INDEXES=8-16$' $screen
Assert-Screen '沒有重複的列' '^DUPLICATES=-$' $screen
Assert-Screen '選取的是 16' '^SELECTED=16$' $screen
Assert-Screen '下方標示目前範圍' '顯示 8-16，共 40 筆' $screen

# 一路往下走再繞回頭：每一步都不能破壞不變量
$r = Invoke-Gwt -Keys ('<down>' * 41) -Rows 12 -Cols 80
$screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols 80
Assert-Screen '繞過一整圈後回到第 2 筆' '^SELECTED=2$' $screen
Assert-Screen '繞圈後沒有重複的列' '^DUPLICATES=-$' $screen
Assert-Screen '繞圈後仍是 9 列' '^ITEM_ROWS=9$' $screen

$r = Invoke-Gwt -Keys '<up>' -Rows 12 -Cols 80
$screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols 80
Assert-Screen '在第 1 筆往上，視窗跳到尾端' '^INDEXES=32-40$' $screen
Assert-Screen '往上循環後選取 40' '^SELECTED=40$' $screen

# 直接按數字鍵跳到第 40 筆：視窗要跟著跳到尾端，而且真的 cd 到第 40 筆
Enter-Fixture 'many'
$r = Invoke-Gwt -Keys '40' -Rows 12 -Cols 80
$screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols 80
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '跳到第 40 筆' (Get-FixturePath $many 40) (Get-Here)
Assert-Screen '光棒在第 40 筆' '^ > \[40\]' $screen
Assert-Screen '視窗在 32-40' '^INDEXES=32-40$' $screen
Assert-Screen '跳轉後沒有重複的列' '^DUPLICATES=-$' $screen

# 高度很小（6 列）也不能壞
Enter-Fixture 'many'
$r = Invoke-Gwt -Keys ('<down>' * 10 + 'q') -Rows 6 -Cols 80
$screen = Get-ScreenReplay -Text $r.Raw -Rows 6 -Cols 80
Assert-Screen '6 列的終端機只畫 3 列' '^ITEM_ROWS=3$' $screen
Assert-Screen '6 列時沒有重複的列' '^DUPLICATES=-$' $screen
Assert-Screen '6 列時光棒在第 11 筆' '^SELECTED=11$' $screen

# 窄視窗時表頭會被裁成一行；選完之後整塊都要擦乾淨，不能留下表頭的第一行殘影
Remove-Item Env:\GWT_CLEAR_ON_EXIT
Enter-Fixture 'twelve'
$r = Invoke-Gwt -Keys '<down><enter>' -Rows 24 -Cols 48
$r.Cap.Append("AFTER=$(Get-Here)`n") | Out-Null
$screen = Get-ScreenReplay -Text $r.Cap.ToString() -Rows 24 -Cols 48
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '切換到第 2 筆' (Get-FixturePath $twelve 2) (Get-Here)
Assert-Screen '收尾後有輸出後續的文字' '^AFTER=' $screen
Assert-NotScreen '窄視窗收尾後沒有表頭殘影' '請選擇 Worktree' $screen
Assert-NotScreen '收尾後沒有任何項目列殘留' '\[\d+\]' $screen

# 40 欄的窄視窗加上超長分支名與超長目錄名：每一列都必須裁到一行以內
$env:GWT_CLEAR_ON_EXIT = '0'
Enter-Fixture 'longname'
$r = Invoke-Gwt -Keys '<down><enter>' -Rows 12 -Cols 40
$screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols 40
Assert-Rc '回傳 0' 0 $r.Rc
Assert-Eq '切換到長名字的 worktree' (Get-FixturePath $longname 2) (Get-Here)
Assert-Screen '2 筆各佔一列（沒有折行）' '^ITEM_ROWS=2$' $screen
Assert-Screen '沒有重複的列' '^DUPLICATES=-$' $screen
Assert-Screen '光棒在第 2 筆' '^ > \[2\]' $screen

# 每一列的欄寬都不超過畫面：重播時若有折行，列數就會變多。
foreach ($cols in 30, 48, 60, 120) {
  Enter-Fixture 'longname'
  $r = Invoke-Gwt -Keys '<down>' -Rows 12 -Cols $cols
  $screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols $cols
  Assert-Screen "$cols 欄下 2 筆各佔一列" '^ITEM_ROWS=2$' $screen
  Assert-Screen "$cols 欄下沒有重複" '^DUPLICATES=-$' $screen
  Assert-Screen "$cols 欄下沒有任何一列折行" '^WRAPS=0$' $screen
}

# 很窄的終端機：一列放不下完整資訊時，要先省略 commit、再省略分支、最後只留路徑。
# 完整的一列至少要 前綴 7 + 路徑 4 + 間隔 2 + […] (7 碼 hash) 13 = 26 欄；
# 在這之下如果硬塞，一列會折成兩行，重繪與收尾算的列數就會錯，畫面留下殘影。
foreach ($fx in 'longname', 'shop', 'cjk') {
  $count = Get-FixtureCount (Join-Path $env:GWT_FIXTURE $fx)
  foreach ($cols in 17, 20, 24, 25, 26, 27, 30) {
    Enter-Fixture $fx
    $r = Invoke-Gwt -Keys '<down>' -Rows 14 -Cols $cols
    $screen = Get-ScreenReplay -Text $r.Raw -Rows 14 -Cols $cols
    Assert-Screen "$fx $cols 欄：每筆各佔一列（$count 筆）" "^ITEM_ROWS=$count$" $screen
    Assert-Screen "$fx $cols 欄：沒有重複的列" '^DUPLICATES=-$' $screen
    Assert-Screen "$fx $cols 欄：光棒在第 2 筆" '^SELECTED=2$' $screen
    Assert-Screen "$fx $cols 欄：沒有任何一列折行（WRAPS=0）" '^WRAPS=0$' $screen

    # 只畫第一個畫面、沒有任何按鍵（所以沒有重繪）。ITEM_ROWS 數的是含 [n] 的列，折行時接續的那一行
    # （例如 "7)"）不含 [n]，所以一列折成兩行照樣算一列；而沒有重繪就不會因為列數對不上而露出重複。
    # 這個情境只有直接數自動換行（WRAPS）才抓得到。
    $first = Invoke-Gwt -Keys '' -Rows 14 -Cols $cols
    $screen0 = Get-ScreenReplay -Text $first.Raw -Rows 14 -Cols $cols
    Assert-Screen "$fx $cols 欄：只畫第一個畫面時 $count 筆各佔一列" "^ITEM_ROWS=$count$" $screen0
    Assert-Screen "$fx $cols 欄：只畫第一個畫面時沒有任何一列折行（WRAPS=0）" '^WRAPS=0$' $screen0
  }
}

# 收尾也一樣：窄到要省略資訊時，選完後整塊都要擦乾淨
Remove-Item Env:\GWT_CLEAR_ON_EXIT
Enter-Fixture 'shop'
$r = Invoke-Gwt -Keys '<down><enter>' -Rows 14 -Cols 25
$r.Cap.Append("AFTER=$(Get-Here)`n") | Out-Null
$screen = Get-ScreenReplay -Text $r.Cap.ToString() -Rows 14 -Cols 25
Assert-Screen '25 欄選完後有輸出後續的文字' '^AFTER=' $screen
Assert-NotScreen '25 欄選完後沒有表頭殘影' '請選擇' $screen
Assert-NotScreen '25 欄選完後沒有項目列殘留' '\[\d+\]' $screen

Complete-Tests
