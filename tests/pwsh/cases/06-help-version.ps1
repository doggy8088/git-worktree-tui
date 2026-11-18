# --help 與 --version。-V 要真的綁到 -Version 開關，而不是被 PowerShell 當成 -Verbose。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$version = Invoke-InGwt { $script:GwtVersion }

$out = (gwt --help) -join "`n"
Assert-Rc '--help 回傳 0' 0 $global:LASTEXITCODE
Assert-Contains '說明含用法' '用法：gwt' $out
Assert-Contains '說明含 --list' '--list' $out
Assert-Contains '說明列出環境變數' 'GWT_CLEAR_ON_EXIT' $out
Assert-Contains '說明解釋結束狀態' '$LASTEXITCODE' $out

$null = gwt -h
Assert-Rc '-h 回傳 0' 0 $global:LASTEXITCODE
$null = gwt -Help
Assert-Rc '-Help 回傳 0' 0 $global:LASTEXITCODE

$out = (gwt --version) -join "`n"
Assert-Rc '--version 回傳 0' 0 $global:LASTEXITCODE
Assert-Eq '輸出與 GwtVersion 一致' "gwt $version" $out
Assert-True '版本號格式為 x.y.z' ($out -match '^gwt \d+\.\d+\.\d+$')

# 直接打 -V（不經過陣列展開），確認是綁到我們宣告的開關
Assert-Eq '-V 與 --version 一致' "gwt $version" ((gwt -V) -join "`n")
Assert-Eq '-v 不分大小寫' "gwt $version" ((gwt -v) -join "`n")
Assert-Eq '-Version 也可以' "gwt $version" ((gwt -Version) -join "`n")

# -Verbose 仍然是 PowerShell 的共同參數，不會被我們吃掉，也不會讓 gwt 誤判成選項
$out = (gwt -Verbose --version 4>&1) -join "`n"
Assert-Contains '-Verbose 不影響其他選項' "gwt $version" $out

# 說明與版本都是成功串流上的字串，不是錯誤
$errs = $null
$null = gwt --help -ErrorVariable errs
Assert-Rc '--help 沒有錯誤紀錄' 0 @($errs).Count

# 英文介面
$env:GWT_LANG = 'en'
$out = (gwt --help) -join "`n"
Assert-Contains '英文介面可切換' 'Usage: gwt' $out
Assert-Contains '英文說明列出結束狀態' 'Exit status' $out

Complete-Tests
