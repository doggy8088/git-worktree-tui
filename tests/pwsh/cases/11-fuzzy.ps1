# 模糊搜尋：子序列比對、只比對分支與最後一層目錄、多詞 AND、分數排序
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

# 刻意讓某一筆的路徑中段含有 marker，驗證不會拿完整路徑去比對
function Search {
  param([string]$Query)
  Invoke-InGwt {
    param($q)
    Initialize-GwtMessages
    Reset-GwtState
    $script:AllPaths.AddRange([string[]]@(
        '/repos/shop'
        '/repos/shop-feature-login'
        '/repos/shop-feature search api'
        '/repos/shop-fix-cart-bug'
        '/repos/shop-hotfix'
        '/repos/parent-only-marker/inner'
        '/repos/other'))
    $script:AllBranches.AddRange([string[]]@('main', 'feature/login', 'feature/search-api', 'fix/cart-bug', 'detached', 'trunk', 'feature/alpha'))
    $script:AllHeads.AddRange([string[]]@('1111111', '2222222', '3333333', '4444444', '5555555', '6666666', '7777777'))
    $script:Query = $q
    Update-GwtFilter
    [pscustomobject]@{ Count = $script:Count; Paths = @($script:Paths) }
  } @($Query)
}

$r = Search 'flogin'
Assert-Rc '子序列可以跨過字元命中分支' 1 $r.Count
Assert-Eq '命中的是 feature/login' '/repos/shop-feature-login' $r.Paths[0]

$r = Search 'shopfix'
Assert-Rc '目錄名稱也納入比對' 2 $r.Count
Assert-Eq '連續命中排在跳字命中前面' '/repos/shop-fix-cart-bug' $r.Paths[0]

Assert-Eq '目錄名稱可跨過連字號比對' '/repos/shop-fix-cart-bug' (Search 'cartbug').Paths[0]
Assert-Rc '不比對路徑中段' 0 (Search 'marker').Count
Assert-Rc '只比對最後一層目錄' 1 (Search 'inner').Count
Assert-Eq '可以只靠分支名稱命中' '/repos/other' (Search 'alpha').Paths[0]

$r = Search 'fea login'
Assert-Rc '多個詞以 AND 串接' 1 $r.Count
Assert-Eq '兩個詞分別命中分支與目錄' '/repos/shop-feature-login' $r.Paths[0]
Assert-Rc '多餘空白不影響比對' 1 (Search 'fea   login').Count
Assert-Rc '預設不分大小寫' 1 (Search 'FLOGIN').Count

# 空白查詢要恢復完整清單，而且維持 Git 的原始順序
$r = Search ''
Assert-Rc '空查詢顯示全部' 7 $r.Count
Assert-Eq '空查詢維持原始順序' '/repos/shop' $r.Paths[0]
Assert-Rc '全是空白的查詢也顯示全部' 7 (Search '   ').Count

# 同分時維持 Git 的順序：'feature' 命中三筆分支（login、search-api、alpha）
$r = Search 'feature'
Assert-True '同類命中的順序穩定（login 在 search 之前）' ($r.Paths.IndexOf('/repos/shop-feature-login') -lt $r.Paths.IndexOf('/repos/shop-feature search api'))

# 連續命中的分數應該高於跳字命中
$score = { param($q) Invoke-InGwt { param($x) Get-GwtFuzzyScore 'feature/login' 'shop-feature-login' $x } @($q) }
Assert-True '連續命中分數較高' ((& $score 'login') -gt (& $score 'lgn'))
Assert-True '沒有命中時回傳 $null（而不是 0 分）' ($null -eq (& $score 'zzz'))

# PowerShell 的 -eq 比對字元時不分大小寫；關掉不分大小寫就必須真的區分
$env:GWT_FILTER_CASE_INSENSITIVE = '0'
Assert-Rc '關閉不分大小寫後找不到' 0 (Search 'FLOGIN').Count
Assert-Rc '關閉不分大小寫後小寫仍可以' 1 (Search 'flogin').Count
$caseCheck = Invoke-InGwt { Get-GwtFuzzyTermScore 'Feature/Login' 'flogin' }
Assert-True '區分大小寫：Feature/Login 不能被 flogin 命中' ($null -eq $caseCheck)
$caseCheck = Invoke-InGwt { Get-GwtFuzzyTermScore 'Feature/Login' 'FL' }
Assert-True '區分大小寫：Feature/Login 可以被 FL 命中' ($null -ne $caseCheck)

# 中文分支名稱也能子序列比對
$env:GWT_FILTER_CASE_INSENSITIVE = '1'
$cjk = Invoke-InGwt { Get-GwtFuzzyScore '功能/登入' 'cjk-購物車' '功入' }
Assert-True '中文分支可以子序列比對' ($null -ne $cjk)

Complete-Tests
