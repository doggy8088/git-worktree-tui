# 結束狀態：$LASTEXITCODE 與 $?。
# `gwt && next` 看的是 $?；取消（q／Esc）必須讓它是 false，而且不能印出任何錯誤。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

# 直接在這個 script 裡呼叫（不經過函式包裝），$? 才是使用者實際會看到的那個。
# 掛鉤的設定與還原集中在這裡，每個情境一次。
function Use-Keys {
  param([string]$Keys)
  $queue = ConvertTo-KeyQueue $Keys
  Invoke-InGwt {
    param($q)
    $script:Hooks.Interactive = $true
    $script:Hooks.ReadKey = { if ($q.Count -gt 0) { $q.Dequeue() } else { $null } }.GetNewClosure()
    $script:Hooks.KeyAvailable = { $q.Count -gt 0 }.GetNewClosure()
    $script:Hooks.Write = { param($t) }
  } @(, $queue)   # 逗號：避免佇列被展開成一個一個按鍵
}
function Reset-Keys {
  Invoke-InGwt { $script:Hooks.Interactive = $null; $script:Hooks.ReadKey = $null; $script:Hooks.KeyAvailable = $null; $script:Hooks.Write = $null }
}

$env:GWT_HEIGHT = '30'
$env:GWT_WIDTH = '100'
Enter-Fixture 'shop'
$start = Get-Here
$errBefore = $global:Error.Count

# --- 取消：$? 為 false、結束碼 1、位置不變、完全沒有輸出（stderr 也沒有）
Use-Keys 'q'
$noise = @(gwt 2>&1)
$rc = $global:LASTEXITCODE
Reset-Keys
Assert-Rc '取消的 $LASTEXITCODE 是 1' 1 $rc
Assert-Rc '取消時成功串流與錯誤串流都沒有任何輸出' 0 $noise.Count

Use-Keys 'q'
$ran = 'no'
gwt && ($ran = 'ran') | Out-Null
Reset-Keys
Assert-Eq 'gwt && next：取消之後 next 不會執行' 'no' $ran

Use-Keys '<esc>'
$ran = 'no'
gwt && ($ran = 'ran') | Out-Null
Reset-Keys
Assert-Eq 'gwt && next：Esc 取消之後 next 不會執行' 'no' $ran

Use-Keys 'q'
$ran = 'no'
gwt || ($ran = 'or-ran') | Out-Null
Reset-Keys
Assert-Eq 'gwt || fallback：取消之後會執行' 'or-ran' $ran

# --- Ctrl+C：130
Use-Keys '<c-c>'
$ran = 'no'
gwt && ($ran = 'ran') | Out-Null
$rc = $global:LASTEXITCODE
Reset-Keys
Assert-Rc 'Ctrl+C 的結束碼是 130' 130 $rc
Assert-Eq 'gwt && next：Ctrl+C 之後 next 不會執行' 'no' $ran

# --- 選定：$? 為 true、結束碼 0，而且 git 呼叫留下的 $LASTEXITCODE 不會漏出來
Use-Keys '<down><enter>'
$ran = 'no'
gwt && ($ran = 'ran') | Out-Null
$rc = $global:LASTEXITCODE
Reset-Keys
Assert-Eq 'gwt && next：選定之後 next 會執行' 'ran' $ran
Assert-Rc '選定的結束碼是 0' 0 $rc

# --- 刻意先讓 $LASTEXITCODE 帶著別的值（例如前一個 git 失敗），確認成功時會被歸零
Set-Location -LiteralPath $start
$global:LASTEXITCODE = 77
gwt --list | Out-Null
Assert-Rc '成功時 $LASTEXITCODE 會被歸零，不留舊值' 0 $global:LASTEXITCODE
$global:LASTEXITCODE = 77
gwt --version | Out-Null
Assert-Rc '--version 也會歸零' 0 $global:LASTEXITCODE

# --- 各種失敗都是 $? = false
$ran = 'no'; gwt nomatch-xyz 2>$null && ($ran = 'ran') | Out-Null
Assert-Eq '找不到符合：next 不會執行' 'no' $ran
Assert-Rc '找不到符合的結束碼是 1' 1 $global:LASTEXITCODE

$ran = 'no'; gwt --bogus 2>$null && ($ran = 'ran') | Out-Null
Assert-Eq '未知選項：next 不會執行' 'no' $ran
Assert-Rc '未知選項的結束碼是 2' 2 $global:LASTEXITCODE

# --- 帶訊息的失敗仍然留在 $Error，方便使用者除錯；取消則沒有
Assert-True '有訊息的失敗會留下 $Error 紀錄' ($global:Error.Count -gt $errBefore)

Complete-Tests
