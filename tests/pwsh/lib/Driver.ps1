# -----------------------------------------------------------------------------
# 不需要終端機的按鍵驅動（對應 tests/lib/ptydrive.py）
#
# zsh 版用 pty.fork 開一個真的 PTY；Windows 沒有 pty，而且 [Console]::ReadKey 在輸入被
# 導向時會直接丟例外。所以這裡改用 gwt.psm1 的測試掛鉤：
#   - ReadKey：從事先排好的佇列取按鍵
#   - Write：把畫面文字收進一個緩衝區，之後交給 Screen.ps1 重播
# 其餘邏輯（版面、搜尋、數字鍵、Esc、結束碼、Set-Location）都是真的在跑。
# 真正的主控台輸入（ReadKey、VT 序列、Ctrl+C）由 tests/pwsh/cases-console 另外驗證。
#
# 按鍵字串的寫法：一般字元照寫，特殊鍵用角括號：
#   <up> <down> <enter> <esc> <bksp> <del> <c-c> <c-u> <c-w> <lt>（字面的 <）
# 例如  '/flogin<enter>'、'<down><down><enter>'、'12'。
# -----------------------------------------------------------------------------

function ConvertTo-KeyInfo {
  param([string]$Token)
  $none = [System.ConsoleKey]0
  switch ($Token) {
    '<up>' { return [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::UpArrow, $false, $false, $false) }
    '<down>' { return [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::DownArrow, $false, $false, $false) }
    '<enter>' { return [System.ConsoleKeyInfo]::new([char]13, [System.ConsoleKey]::Enter, $false, $false, $false) }
    '<esc>' { return [System.ConsoleKeyInfo]::new([char]27, [System.ConsoleKey]::Escape, $false, $false, $false) }
    '<bksp>' { return [System.ConsoleKeyInfo]::new([char]8, [System.ConsoleKey]::Backspace, $false, $false, $false) }
    '<del>' { return [System.ConsoleKeyInfo]::new([char]127, $none, $false, $false, $false) }
    '<c-c>' { return [System.ConsoleKeyInfo]::new([char]3, [System.ConsoleKey]::C, $false, $false, $true) }
    '<c-u>' { return [System.ConsoleKeyInfo]::new([char]21, [System.ConsoleKey]::U, $false, $false, $true) }
    '<c-w>' { return [System.ConsoleKeyInfo]::new([char]23, [System.ConsoleKey]::W, $false, $false, $true) }
    '<lt>' { return [System.ConsoleKeyInfo]::new('<', $none, $false, $false, $false) }
  }
  $c = [char]$Token[0]
  $key = $none
  if ($c -ge 'a' -and $c -le 'z') { $key = [System.ConsoleKey]([int][char]::ToUpperInvariant($c)) }
  elseif ($c -ge 'A' -and $c -le 'Z') { $key = [System.ConsoleKey]([int]$c) }
  elseif ($c -ge '0' -and $c -le '9') { $key = [System.ConsoleKey]([int]$c) }
  return [System.ConsoleKeyInfo]::new($c, $key, $false, $false, $false)
}

function ConvertTo-KeyQueue {
  param([string]$Spec)
  $queue = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
  $i = 0
  while ($i -lt $Spec.Length) {
    $m = [regex]::Match($Spec.Substring($i), '^<[a-z-]+>')
    if ($m.Success) {
      $queue.Enqueue((ConvertTo-KeyInfo $m.Value))
      $i += $m.Length
    }
    else {
      $queue.Enqueue((ConvertTo-KeyInfo ([string]$Spec[$i])))
      $i++
    }
  }
  return , $queue
}

# 在 gwt 模組的作用域裡執行一段程式碼（存取私有函式與狀態）
function Invoke-InGwt {
  param([scriptblock]$Script, [object[]]$Arguments = @())
  & (Get-Module gwt) $Script @Arguments
}

# 用排好的按鍵跑一次 gwt。傳回：
#   Rc      $LASTEXITCODE
#   Raw     gwt 寫出的全部畫面文字（可以再補上測試自己的輸出，一起交給 Get-ScreenReplay）
#   Output  成功串流與錯誤串流的內容（錯誤是 ErrorRecord）
#   Left    佇列裡沒被吃掉的按鍵數
function Invoke-Gwt {
  param(
    [string]$Keys = '',
    [int]$Rows = 40,
    [int]$Cols = 100,
    [string[]]$GwtArgs = @(),
    [switch]$NotTty
  )
  $queue = ConvertTo-KeyQueue $Keys
  $cap = [System.Text.StringBuilder]::new()
  $savedH = $env:GWT_HEIGHT
  $savedW = $env:GWT_WIDTH
  $env:GWT_HEIGHT = "$Rows"
  $env:GWT_WIDTH = "$Cols"

  $interactive = -not $NotTty
  Invoke-InGwt {
    param($q, $buf, $interactive)
    $script:Hooks.Interactive = $interactive
    $script:Hooks.ReadKey = { if ($q.Count -gt 0) { $q.Dequeue() } else { $null } }.GetNewClosure()
    $script:Hooks.KeyAvailable = { $q.Count -gt 0 }.GetNewClosure()
    $script:Hooks.Write = { param($t) [void]$buf.Append($t) }.GetNewClosure()
  } @($queue, $cap, $interactive)

  try {
    $out = @(gwt @GwtArgs 2>&1)
    $rc = $global:LASTEXITCODE
  }
  finally {
    Invoke-InGwt {
      $script:Hooks.Interactive = $null
      $script:Hooks.ReadKey = $null
      $script:Hooks.KeyAvailable = $null
      $script:Hooks.Write = $null
    }
    $env:GWT_HEIGHT = $savedH
    $env:GWT_WIDTH = $savedW
  }
  return [pscustomobject]@{ Rc = $rc; Raw = $cap.ToString(); Output = $out; Left = $queue.Count; Cap = $cap }
}
