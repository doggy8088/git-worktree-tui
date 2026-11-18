# 只有一筆符合時，不顯示選單直接切換（原文行為）；cd - 仍然可用
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$shop = Join-Path $env:GWT_FIXTURE 'shop'
Enter-Fixture 'shop'
$expected = Find-FixturePath $shop 'fix-cart-bug'
Assert-Ne '測試資料裡找得到 cart-bug' '' $expected

gwt cart
Assert-Rc '單筆符合回傳 0' 0 $global:LASTEXITCODE
Assert-Eq '直接切換到該 worktree' $expected (Get-Here)

# Set-Location 在模組函式裡仍然記進位置歷史，所以 cd - 能回去
Set-Location -LiteralPath $shop
gwt cart
Set-Location -
Assert-Eq 'cd - 回到切換之前的目錄' $shop (Get-Here)

# 從子目錄執行也要能切換（git rev-parse --show-toplevel 會往上找）
$sub = Join-Path $shop 'src\sub'
New-Item -ItemType Directory -Force -Path $sub | Out-Null
Set-Location -LiteralPath $sub
gwt hotfix
Assert-Eq '從子目錄也能切換' (Find-FixturePath $shop 'hotfix') (Get-Here)

# 呼叫端的 PowerShell 位置與 .NET 的目前目錄是兩回事；gwt 一定要以前者為準
Set-Location -LiteralPath $shop
[Environment]::CurrentDirectory = $env:GWT_FIXTURE
gwt cart
Assert-Eq '.NET 目前目錄不同時，仍以 PowerShell 位置為準' $expected (Get-Here)

Complete-Tests
