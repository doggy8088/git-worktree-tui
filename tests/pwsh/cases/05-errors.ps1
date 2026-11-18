# 錯誤情境：找不到符合、不在 Git 儲存庫、未知選項、非互動環境
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

function Get-Messages {
  param($Result)
  (@($Result.Output | ForEach-Object { $_.ToString() })) -join "`n"
}

Enter-Fixture 'shop'
$r = Invoke-Gwt -GwtArgs 'nomatch'
Assert-Rc '找不到符合回傳 1' 1 $r.Rc
Assert-Contains '訊息含關鍵字' 'nomatch' (Get-Messages $r)
Assert-Contains '訊息說明找不到' '找不到符合' (Get-Messages $r)
Assert-True '訊息走錯誤串流（可以用 2>&1 或 -ErrorVariable 接）' (@($r.Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count -eq 1)

$before = Get-Here
Invoke-Gwt -GwtArgs 'nomatch' | Out-Null
Assert-Eq '找不到時目錄不變' $before (Get-Here)

Enter-Fixture 'outside'
$r = Invoke-Gwt
Assert-Rc '非 Git 目錄回傳 1' 1 $r.Rc
Assert-Contains '訊息說明不在儲存庫' '不在 Git 儲存庫中' (Get-Messages $r)

Enter-Fixture 'shop'
$r = Invoke-Gwt -GwtArgs '--bogus'
Assert-Rc '未知選項回傳 2' 2 $r.Rc
Assert-Contains '訊息含選項名稱' '--bogus' (Get-Messages $r)
Assert-Contains '訊息附上說明' '用法：gwt' (Get-Messages $r)

$r = Invoke-Gwt -GwtArgs '-x'
Assert-Rc '未知的短選項也回傳 2' 2 $r.Rc

# 非互動環境且有兩個以上 worktree 時，應明確拒絕而不是卡住
$r = Invoke-Gwt -NotTty
Assert-Rc '非 tty 回傳 1' 1 $r.Rc
Assert-Contains '訊息說明需要終端機' '互動式終端機' (Get-Messages $r)
Assert-Eq '非 tty 時不輸出任何畫面' '' $r.Raw

# 英文介面
$env:GWT_LANG = 'en'
$r = Invoke-Gwt -GwtArgs 'nomatch'
Assert-Contains '英文訊息' 'no worktree matched "nomatch"' (Get-Messages $r)
$r = Invoke-Gwt -NotTty
Assert-Contains '英文的需要終端機訊息' 'interactive terminal is required' (Get-Messages $r)

# 目錄在 git worktree list 裡，但實際上被刪掉了（沒有 git worktree prune）
$env:GWT_LANG = 'zh'
$gone = Join-Path $env:GWT_FIXTURE 'shop-hotfix'
$stash = "$gone.moved"
Enter-Fixture 'shop'
Move-Item -LiteralPath $gone -Destination $stash
try {
  $here = Get-Here
  $r = Invoke-Gwt -GwtArgs 'hotfix'
  Assert-Rc '目錄不存在時回傳 1' 1 $r.Rc
  Assert-Eq '目錄不存在時位置不變' $here (Get-Here)
  Assert-True '目錄不存在時有錯誤訊息' (@($r.Output).Count -ge 1)
}
finally {
  Move-Item -LiteralPath $stash -Destination $gone
}

Complete-Tests
