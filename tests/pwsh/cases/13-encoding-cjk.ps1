# 中文路徑與分支：git 輸出 UTF-8，PowerShell 預設卻用主控台字碼頁解碼原生命令輸出
# （繁中 Windows 是 950、英文 Windows 是 437）。gwt 自己以 UTF-8 解碼，不受字碼頁影響。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$cjk = Join-Path $env:GWT_FIXTURE 'cjk'
$expected = @(Get-FixturePaths $cjk)
$expectedFix = Find-FixturePath $cjk '修正結帳錯誤'
Assert-Rc '測試資料有 3 筆' 3 $expected.Count
Assert-True '測試資料確實含中文路徑' (@($expected | Where-Object { $_ -match '[一-鿿]' }).Count -eq 2)

# 故意把主控台輸出編碼換成一個「不是 UTF-8」的字碼頁，再執行 gwt；
# 如果 gwt 靠預設解碼，中文會變成亂碼。沒有主控台（CI）就設不了，那只驗結果正確。
# 期望值與斷言都在換回編碼之後才做，免得測試自己的輸出與 git 輔助函式也被影響。
$saved = [Console]::OutputEncoding
$switched = $false
try {
  [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(1252)
  $switched = $true
}
catch { }

Enter-Fixture 'cjk'
$out = @(gwt --list)
$byKeyword = @(gwt --list 購物車)
$byBranch = @(gwt --list 登入)
gwt 修正
$landed = Get-Here
$encodingAfter = [Console]::OutputEncoding.CodePage

if ($switched) { [Console]::OutputEncoding = $saved }

Assert-Rc '列出 3 筆' 3 $out.Count
for ($i = 0; $i -lt $expected.Count; $i++) {
  Assert-Eq "第 $($i + 1) 筆路徑與 git 一致（含中文）" $expected[$i] $out[$i]
}
Assert-Rc '用中文關鍵字篩選' 1 $byKeyword.Count
Assert-Rc '用中文分支名稱的關鍵字篩選' 1 $byBranch.Count
Assert-Eq '用中文關鍵字單筆符合直接切換' $expectedFix $landed
if ($switched) {
  Assert-Rc '執行後主控台輸出編碼沒有被改動' 1252 $encodingAfter
}

# 選單：中文路徑與分支的列，每一列都不能超過畫面寬度（寬度以欄計，全形字佔兩欄）
Enter-Fixture 'cjk'
$env:GWT_CLEAR_ON_EXIT = '0'
foreach ($cols in 80, 40, 30) {
  $r = Invoke-Gwt -Keys '<down>' -Rows 12 -Cols $cols
  $screen = Get-ScreenReplay -Text $r.Raw -Rows 12 -Cols $cols
  Assert-Screen "中文清單在 $cols 欄下仍是 3 列、沒有折行" '^ITEM_ROWS=3$' $screen
  Assert-Screen "中文清單在 $cols 欄下沒有重複的列" '^DUPLICATES=-$' $screen
  Assert-Screen "中文清單在 $cols 欄下沒有任何一列折行（全形字以兩欄計）" '^WRAPS=0$' $screen
  Assert-Screen "中文清單在 $cols 欄下游標停在第 2 筆" '^SELECTED=2$' $screen
}

Complete-Tests
