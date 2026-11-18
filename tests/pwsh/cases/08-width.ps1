# 寬度計算與中間截斷
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

function Width { param([string]$s) Invoke-InGwt { param($x) Get-GwtWidth $x } @($s) }
function Clip { param([string]$s, [int]$n) Invoke-InGwt { param($x, $b) Get-GwtClipped $x $b } @($s, $n) }
function Strip { param([string]$s) Invoke-InGwt { param($x) Remove-GwtAnsi $x } @($s) }

$e = [string][char]27

Assert-Rc 'ASCII 寬度' 3 (Width 'abc')
Assert-Rc 'CJK 全形字算兩欄' 10 (Width '(目前位置)')
Assert-Rc '英文標註寬度' 9 (Width '(current)')
Assert-Rc '空字串寬度為 0' 0 (Width '')
Assert-Rc 'emoji（代理對）算兩欄' 4 (Width "a😀b")
Assert-Rc '全形標點算兩欄' 2 (Width '，')

Assert-Eq '去色後只剩文字' '[main]' (Strip "$e[36m[main]$e[0m")
Assert-Rc '上色字串的寬度不含跳脫序列' 10 (Width (Strip "$e[1;30;46m > [1] /a $e[0m"))

$r = Clip '/a/very/long/path/to/shop-feature-login' 20
Assert-True '截斷後不超過指定欄寬' ((Width $r) -le 20)
Assert-Contains '截斷處有省略號' '…' $r
Assert-Contains '保留結尾較有用的部分' 'login' $r

Assert-Eq '夠短時原樣保留' '/short' (Clip '/short' 20)

$r = Clip '/tmp/x' 3
Assert-True '預算極小時也不超過欄寬' ((Width $r) -le 3)
Assert-Eq '預算小於 3 時只剩省略號' '…' (Clip '/tmp/xyz' 2)

# 中文路徑：寬度以欄計，不是以字元數計；截斷後不能超過預算，也不能把全形字切成半個
$cjk = 'C:\專案\購物車\shop-修正結帳錯誤'
foreach ($budget in 10, 14, 19, 25) {
  $r = Clip $cjk $budget
  Assert-True "中文路徑截斷到 $budget 欄不超過預算" ((Width $r) -le $budget)
}
$r = Clip $cjk 19
Assert-Contains '中文路徑保留尾段' '結帳錯誤' $r

# --- 逐字對照 Unicode 的標準答案（tests/pwsh/lib/WidthOracle.ps1，不是任何程式算出來的）---------------
# 基本多文種平面裡寬度為 2 的符號（⚡ ⌚ ✅ ⭐ ...）不在 CJK 範圍內：只有 CJK 範圍的表會把它們當成 1 欄，
# 選單的一列就比算出來的寬，折行之後重繪與收尾的列數對不上。
. "$env:GWT_ROOT\tests\pwsh\lib\WidthOracle.ps1"
foreach ($entry in $script:WidthOracle) {
  $ch = [char]::ConvertFromUtf32($entry.Cp)
  Assert-Rc "Get-GwtWidth：$($entry.Name) 應為 $($entry.W) 欄" $entry.W (Width $ch)
}
Assert-Rc '夾在 ASCII 中間：a⚡b 為 4 欄' 4 (Width "a$([char]0x26A1)b")
Assert-Rc '連續的寬符號：⚡ 三個為 6 欄' 6 (Width ([string][char]0x26A1 * 3))
Assert-Rc '寬符號與 CJK 混用：中⚡文⌚ 為 8 欄' 8 (Width "中$([char]0x26A1)文$([char]0x231A)")
Assert-Rc '上色字串裡的寬符號：去掉跳脫序列後才算寬度' 2 (Width (Strip "$e[36m$([char]0x26A1)$e[0m"))

# 含寬符號的長字串，截斷後不能超過預算（每個 ⚡ 佔 2 欄，用字元數算會超過一倍）
$bolts = 'feature/' + ([string][char]0x26A1 * 30)
foreach ($budget in 8, 20, 33, 50, 76) {
  $r = Clip $bolts $budget
  Assert-True "含 30 個 ⚡ 的分支名截斷到 $budget 欄不超過預算（實際 $(Width $r) 欄）" ((Width $r) -le $budget)
}
$r = Clip $bolts 20
Assert-Contains '截斷處有省略號' '…' $r

# emoji 不能被從代理對中間切開
$emoji = 'proj-😀😀😀😀😀😀😀😀-end'
$r = Clip $emoji 12
Assert-True 'emoji 截斷後不超過預算' ((Width $r) -le 12)
Assert-True 'emoji 截斷後沒有落單的代理字元' ($r -notmatch '[\uD800-\uDBFF](?![\uDC00-\uDFFF])' -and $r -notmatch '(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]')

Complete-Tests
