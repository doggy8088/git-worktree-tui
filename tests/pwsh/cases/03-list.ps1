# gwt --list：只印路徑，每行一筆，含空白路徑也要完整；結果走成功串流，可以接管線
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

Enter-Fixture 'shop'

$out = @(gwt --list)
Assert-Rc '--list 回傳 0' 0 $global:LASTEXITCODE
Assert-Rc '列出 5 筆' 5 $out.Count
Assert-True '每一筆都是字串（不是物件）' (@($out | Where-Object { $_ -isnot [string] }).Count -eq 0)
Assert-True '含空白路徑完整輸出' ($out -contains (Find-FixturePath (Join-Path $env:GWT_FIXTURE 'shop') 'shop-feature search api'))
Assert-Eq '第一筆是主 worktree' (Get-FixturePath (Join-Path $env:GWT_FIXTURE 'shop') 1) $out[0]

# -l 與 PowerShell 風格的 -List 等價
Assert-Rc '-l 同樣列出 5 筆' 5 @(gwt -l).Count
Assert-Rc '-List 同樣列出 5 筆' 5 @(gwt -List).Count

# 搭配其他命令時可以直接過濾
$n = @(gwt --list | Where-Object { $_ -like '*feature*' }).Count
Assert-Rc '管線過濾得到 2 筆 feature' 2 $n

# 與關鍵字併用
Assert-Rc '--list 加關鍵字' 1 @(gwt --list cart).Count

# 沒有其他 worktree 時仍應印出自己那一筆
Enter-Fixture 'plain'
Assert-Rc '單一 worktree 列出 1 筆' 1 @(gwt --list).Count

Complete-Tests
