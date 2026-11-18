# 關鍵字篩選：比對「路徑 + 分支」、不分大小寫、萬用字元與大括號只當普通文字
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$porcelain = @'
worktree /repos/shop
HEAD 1111111aaaa
branch refs/heads/main

worktree /repos/shop hotfix
HEAD 2222222bbbb
branch refs/heads/hotfix

worktree /repos/shop-feature
HEAD 3333333cccc
branch refs/heads/feature/login

worktree /repos/shop-fix-cart-bug
HEAD 4444444dddd
branch refs/heads/fix/cart-bug

'@

function Collect-With {
  param([string]$Keyword)
  Invoke-InGwt {
    param($t, $k)
    Initialize-GwtMessages
    Reset-GwtState
    Read-GwtPorcelain -Text $t -Keyword $k
    [pscustomobject]@{ Count = $script:Count; Paths = @($script:Paths) }
  } @($porcelain, $Keyword)
}

Assert-Rc '關鍵字命中分支名稱' 1 (Collect-With 'feature').Count
Assert-Rc '預設不分大小寫' 1 (Collect-With 'FEATURE').Count

$r = Collect-With 'hotfix'
Assert-Rc '路徑命中（shop hotfix）' 1 $r.Count
Assert-Eq '命中含空白路徑' (ConvertTo-NativeTestPath '/repos/shop hotfix') $r.Paths[0]

Assert-Rc '可以比對含斜線的分支' 1 (Collect-With 'feature/login').Count

# 這裡刻意用同一個短關鍵字，驗證「路徑也算在比對範圍內」這個原文提到的行為
Assert-Rc 'fix 同時命中路徑與分支' 2 (Collect-With 'fix').Count
Assert-Rc '沒有符合時為 0 筆' 0 (Collect-With 'nomatch').Count

# 關鍵字含萬用字元時只能當普通文字，不能變成萬用字元（用 -like 比對就會踩到）
Assert-Rc '星號不當萬用字元' 0 (Collect-With '*').Count
Assert-Rc '問號不當萬用字元' 0 (Collect-With '?').Count
Assert-Rc '中括號不當字元集' 0 (Collect-With '[a-z]').Count
Assert-Rc '大括號不當格式字串' 0 (Collect-With '{0}').Count

# 關掉不分大小寫後，大寫關鍵字就應該找不到
$env:GWT_FILTER_CASE_INSENSITIVE = '0'
Assert-Rc '關閉不分大小寫後找不到' 0 (Collect-With 'FEATURE').Count
Assert-Rc '關閉不分大小寫後小寫仍可以' 1 (Collect-With 'feature').Count

Complete-Tests
