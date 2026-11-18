# 目錄名稱含 PowerShell 的特殊字元：[ ]（萬用字元）、$（變數）、'（引號）、& ; ( )
# 這些路徑只要在某個地方被「當成程式碼或樣式」處理，就會切不過去或切到別的地方。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$special = Join-Path $env:GWT_FIXTURE 'special'
$paths = @(Get-FixturePaths $special)
Assert-Rc '測試資料有 5 筆' 5 $paths.Count

$names = @{
  bracket = 'special-[1]'
  dollar  = 'special-$HOME'
  quote   = "special-it's"
  amp     = 'special-a&b;(c)'
}
foreach ($k in $names.Keys) {
  Assert-True "測試資料存在：$($names[$k])" (Test-Path -LiteralPath (Join-Path $env:GWT_FIXTURE $names[$k]))
}

# --list：原樣輸出，一字不差
Enter-Fixture 'special'
$listed = @(gwt --list)
Assert-Rc '--list 列出 5 筆' 5 $listed.Count
foreach ($p in $paths) {
  Assert-True "--list 含 $(Split-Path -Leaf $p)" ($listed -contains $p)
}

# 單筆符合直接切換：用路徑片段當關鍵字（關鍵字本身也含特殊字元）
foreach ($k in $names.Keys) {
  Enter-Fixture 'special'
  $want = Find-FixturePath $special $names[$k]
  gwt $names[$k]
  Assert-Rc "關鍵字 $($names[$k]) 回傳 0" 0 $global:LASTEXITCODE
  Assert-Eq "關鍵字 $($names[$k]) 切到正確的目錄" $want (Get-Here)
}

# 關鍵字含 [ ]：只能當普通文字，不是字元集（[1] 不能命中 special-1 這種東西）
Enter-Fixture 'special'
Assert-Rc '關鍵字 [1] 只命中含 [1] 的那一筆' 1 @(gwt --list '[1]').Count
Assert-Rc '關鍵字 $HOME 只命中字面的 $HOME' 1 @(gwt --list '$HOME').Count

# 從選單選到這些目錄（Enter 與數字鍵兩條路）
for ($i = 1; $i -le $paths.Count; $i++) {
  Enter-Fixture 'special'
  $r = Invoke-Gwt -Keys "$i"
  Assert-Rc "數字鍵 $i 回傳 0" 0 $r.Rc
  Assert-Eq "數字鍵 $i 切到第 $i 筆" $paths[$i - 1] (Get-Here)
}

# cd - 要能回到切換之前的目錄（gwt 在全域工作階段裡切換，歷史才會記對）
$shop = Join-Path $env:GWT_FIXTURE 'shop'
Set-Location -LiteralPath (Join-Path $env:GWT_FIXTURE 'outside')
Set-Location -LiteralPath $shop
gwt cart
Set-Location -
Assert-Eq 'gwt 之後 cd - 回到切換之前的目錄' $shop (Get-Here)
gwt hotfix
Set-Location -
Assert-Eq '再切一次，cd - 仍然正確' $shop (Get-Here)

Complete-Tests
