# -----------------------------------------------------------------------------
# 極簡測試斷言（PowerShell 版，對應 tests/lib/assert.zsh）
#
# 每個測試檔開頭 dot-source 這個檔案，中間呼叫 Assert-*，最後呼叫 Complete-Tests。
# Complete-Tests 會直接結束這個處理序：全部通過結束碼 0，有失敗為 1。
# 故意不用 Pester：Windows 內建的是 Pester 3.4，語法與 Pester 5 不相容，
# 而且這個專案的原則是不加依賴。
# -----------------------------------------------------------------------------

# 測試標籤與輸出含中文；讓子處理序用 UTF-8 輸出，父處理序才不會用字碼頁（繁中 950、
# CI 上的 437）解錯。沒有主控台（CI 重導向）時設定會失敗，那就算了。
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

$script:TPass = 0
$script:TFail = 0

function Write-TestLine {
  param([string]$Text)
  [Console]::Out.WriteLine($Text)
}

function Add-TestPass {
  param([string]$Label)
  $script:TPass++
  Write-TestLine "  ok    $Label"
}

function Add-TestFail {
  param([string]$Label)
  $script:TFail++
  Write-TestLine "  FAIL  $Label"
}

# Assert-Eq <說明> <期望值> <實際值>
function Assert-Eq {
  param([string]$Label, $Want, $Got)
  if ("$Want" -ceq "$Got") {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
    Write-TestLine "        期望: $Want"
    Write-TestLine "        實得: $Got"
  }
}

function Assert-Ne {
  param([string]$Label, $Unwanted, $Got)
  if ("$Unwanted" -cne "$Got") {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
    Write-TestLine "        不該等於: $Unwanted"
  }
}

# 判斷式本身已經算好（$true / $false），用在「小於等於」之類的比較
function Assert-True {
  param([string]$Label, $Condition)
  if ($Condition) {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
  }
}

function Assert-Contains {
  param([string]$Label, [string]$Needle, [string]$Hay)
  if ($Hay.Contains($Needle, [System.StringComparison]::Ordinal)) {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
    Write-TestLine "        找不到: $Needle"
    Write-TestLine "        內容: $Hay"
  }
}

function Assert-NotContains {
  param([string]$Label, [string]$Needle, [string]$Hay)
  if (-not $Hay.Contains($Needle, [System.StringComparison]::Ordinal)) {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
    Write-TestLine "        不該出現: $Needle"
  }
}

# Assert-Rc <說明> <期望結束碼> <實際結束碼>
function Assert-Rc {
  param([string]$Label, [int]$Want, [int]$Got)
  if ($Want -eq $Got) {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
    Write-TestLine "        期望結束碼: $Want，實得: $Got"
  }
}

# 對重播後的畫面做正規表示式比對（多行模式，^ 與 $ 以行為單位）
function Assert-Screen {
  param([string]$Label, [string]$Pattern, [string]$Screen)
  if ([regex]::IsMatch($Screen, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
    Write-TestLine "        畫面缺少: $Pattern"
    Write-TestLine (($Screen -split "`n" | Select-Object -Last 14 | ForEach-Object { "        | $_" }) -join "`n")
  }
}

function Assert-NotScreen {
  param([string]$Label, [string]$Pattern, [string]$Screen)
  if (-not [regex]::IsMatch($Screen, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
    Add-TestPass $Label
  }
  else {
    Add-TestFail $Label
    Write-TestLine "        畫面不該出現: $Pattern"
    Write-TestLine (($Screen -split "`n" | Select-Object -Last 14 | ForEach-Object { "        | $_" }) -join "`n")
  }
}

function Complete-Tests {
  Write-TestLine "  小計：$($script:TPass) 通過，$($script:TFail) 失敗"
  if ($script:TFail -gt 0) { exit 1 }
  exit 0
}
