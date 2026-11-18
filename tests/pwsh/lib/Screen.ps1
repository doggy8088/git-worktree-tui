# -----------------------------------------------------------------------------
# 把 gwt 輸出的 ANSI 序列重播成「最後的畫面」（對應 tests/lib/screen.py）
#
# 為什麼需要它：選單是靠跳脫序列就地重繪的，錯誤不會顯示在文字內容裡，只會表現
# 在終端機的最終畫面上。要驗證「有沒有重複的列」「游標往上移幾行」這類問題，
# 只能把序列重播一遍。
#
# 只支援 gwt 會用到的序列，刻意不寫成完整的終端機模擬器：
#   \r         游標回到行首
#   \n         換行並回到行首（真實終端機的 ONLCR / Windows 的自動歸位）
#   ESC[nA/B   往上／往下 n 行（到頂為止，與真實終端機一致）
#   ESC[2K/K   清除整列／清除游標到行尾
#   ESC[J      清除游標到畫面結尾
#   ESC[..m    SGR，忽略；ESC[?25l/h 顯示／隱藏游標，忽略
#
# 與 screen.py 的差別：全形字（CJK、emoji）佔兩個儲存格，而且放不下時會整個換到
# 下一行，跟真實終端機一樣。中文路徑的折行錯誤只有這樣才抓得到。
# -----------------------------------------------------------------------------

# 寬度為 2 的基本多文種平面（BMP）範圍：Unicode 的 East Asian Width 是 W（Wide）或 F（Fullwidth）。
# 這是「真實終端機認定的寬度」，不是從 gwt 抄來的：gwt.psm1 的 Get-GwtWidth 是另一份獨立的實作，
# 兩邊各自對照 cases/08-width.ps1 與 cases/18-screen-replay.ps1 裡「逐字寫死的 Unicode 預期值」，
# 不能讓它們共用同一個盲點（只有 CJK 範圍的表，會把 ⚡ ⌚ ✅ 這類寬度為 2 的符號當成 1 欄）。
# 代理對（基本多文種平面以外的 emoji 等）一律算 2。
$script:WideRanges = @(
  @(0x1100, 0x115F), @(0x231A, 0x231B), @(0x2329, 0x232A), @(0x23E9, 0x23EC), @(0x23F0, 0x23F0), @(0x23F3, 0x23F3),
  @(0x25FD, 0x25FE), @(0x2614, 0x2615), @(0x2648, 0x2653), @(0x267F, 0x267F), @(0x2693, 0x2693), @(0x26A1, 0x26A1),
  @(0x26AA, 0x26AB), @(0x26BD, 0x26BE), @(0x26C4, 0x26C5), @(0x26CE, 0x26CE), @(0x26D4, 0x26D4), @(0x26EA, 0x26EA),
  @(0x26F2, 0x26F3), @(0x26F5, 0x26F5), @(0x26FA, 0x26FA), @(0x26FD, 0x26FD), @(0x2705, 0x2705), @(0x270A, 0x270B),
  @(0x2728, 0x2728), @(0x274C, 0x274C), @(0x274E, 0x274E), @(0x2753, 0x2755), @(0x2757, 0x2757), @(0x2795, 0x2797),
  @(0x27B0, 0x27B0), @(0x27BF, 0x27BF), @(0x2B1B, 0x2B1C), @(0x2B50, 0x2B50), @(0x2B55, 0x2B55),
  @(0x2E80, 0x303E), @(0x3041, 0xA4CF), @(0xA960, 0xA97F), @(0xAC00, 0xD7A3), @(0xF900, 0xFAFF),
  @(0xFE10, 0xFE19), @(0xFE30, 0xFE6F), @(0xFF00, 0xFF60), @(0xFFE0, 0xFFE6)
)

function Get-CellWidth {
  param([string]$Unit)
  if ($Unit.Length -ge 2) { return 2 }   # 代理對（emoji 等）
  $code = [int]$Unit[0]
  foreach ($range in $script:WideRanges) {
    if ($code -ge $range[0] -and $code -le $range[1]) { return 2 }
  }
  return 1
}

# 傳回一整段文字：畫面 + 結構摘要（格式與 screen.py 相同），測試用 Assert-Screen 比對。
function Get-ScreenReplay {
  param([string]$Text, [int]$Rows = 24, [int]$Cols = 80)

  # 每個儲存格存一個字串；全形字的第二格存 $null（輸出時略過）
  $grid = New-Object 'object[]' ($Rows)
  for ($r = 0; $r -lt $Rows; $r++) { $grid[$r] = New-Object 'object[]' ($Cols); for ($c = 0; $c -lt $Cols; $c++) { $grid[$r][$c] = ' ' } }
  # Wraps：因為「寫滿一列還繼續寫」而自動換行的次數（不含明確的 \n）。gwt 保證每一列都留在寬度之內，
  # 所以選單本身的輸出一次自動換行都不該有。這比「數有幾列含 [n]」直接：一列折成兩行時，
  # 接續的那一行（例如 "7)"）不含 [n]，ITEM_ROWS 與 DUPLICATES 都看不出來——只有後面碰巧又重繪
  # 一次、列數對不上時才會間接露出來。
  $state = @{ Row = 0; Col = 0; Wraps = 0 }

  $blank = {
    param($r)
    for ($c = 0; $c -lt $Cols; $c++) { $grid[$r][$c] = ' ' }
  }
  # 全形字佔兩個儲存格：左半存字，右半存 $null。蓋掉或清掉其中一半時，另一半不能留著——真實終端機會把
  # 整個全形字清成空白。留著的話，剩下的那一半會讓整列的欄位錯開（右半 $null 輸出時被略過，後面的字就左移）。
  #   $orphanLeft  r c：從第 c 欄開始要被改寫；如果第 c 欄是某個全形字的右半，它的左半（c-1）清成空白
  #   $orphanRight r c：到第 c 欄為止都被改寫了；如果第 c+1 欄是右半，它的左半（c）已經不在，清成空白
  $orphanLeft = { param($r, $c) if ($c -gt 0 -and $c -lt $Cols -and $null -eq $grid[$r][$c]) { $grid[$r][$c - 1] = ' ' } }
  $orphanRight = { param($r, $c) if ($c -ge 0 -and $c + 1 -lt $Cols -and $null -eq $grid[$r][$c + 1]) { $grid[$r][$c + 1] = ' ' } }
  $newline = {
    $state.Row++
    $state.Col = 0
    if ($state.Row -ge $Rows) {
      for ($r = 1; $r -lt $Rows; $r++) { $grid[$r - 1] = $grid[$r] }
      $grid[$Rows - 1] = New-Object 'object[]' ($Cols)
      for ($c = 0; $c -lt $Cols; $c++) { $grid[$Rows - 1][$c] = ' ' }
      $state.Row = $Rows - 1
    }
  }

  $csi = [regex]::new("\x1b\[([0-9;?]*)([A-Za-z])")
  $n = $Text.Length
  $i = 0
  while ($i -lt $n) {
    $ch = $Text[$i]
    if ($ch -ceq [char]27) {
      $m = $csi.Match($Text, $i)
      if (-not $m.Success -or $m.Index -ne $i) {
        # 不是 CSI：跳過其他常見的跳脫序列（ConPTY 會送 OSC 視窗標題、字元集切換等）
        $nextCh = if ($i + 1 -lt $n) { $Text[$i + 1] } else { [char]0 }
        if ($nextCh -ceq ']') {
          $j = $i + 2
          while ($j -lt $n -and $Text[$j] -ne [char]7 -and -not ($Text[$j] -eq [char]27 -and $j + 1 -lt $n -and $Text[$j + 1] -eq '\')) { $j++ }
          if ($j -lt $n -and $Text[$j] -eq [char]27) { $j++ }
          $i = $j + 1
        }
        elseif ($nextCh -ceq '(' -or $nextCh -ceq ')') { $i += 3 }
        else { $i += 2 }
        continue
      }
      $params = $m.Groups[1].Value
      $final = $m.Groups[2].Value
      $i = $m.Index + $m.Length
      $first = if ($params -match '^(\d+)') { [int]$Matches[1] } else { -1 }
      switch -CaseSensitive ($final) {
        'A' { $k = if ($first -gt 0) { $first } else { 1 }; $state.Row = [math]::Max(0, $state.Row - $k) }
        'B' { $k = if ($first -gt 0) { $first } else { 1 }; $state.Row = [math]::Min($Rows - 1, $state.Row + $k) }
        'C' { $k = if ($first -gt 0) { $first } else { 1 }; $state.Col = [math]::Min($Cols - 1, $state.Col + $k) }
        'D' { $k = if ($first -gt 0) { $first } else { 1 }; $state.Col = [math]::Max(0, $state.Col - $k) }
        'G' { $k = if ($first -gt 0) { $first } else { 1 }; $state.Col = [math]::Min($Cols - 1, $k - 1) }
        'd' { $k = if ($first -gt 0) { $first } else { 1 }; $state.Row = [math]::Min($Rows - 1, $k - 1) }
        { $_ -ceq 'H' -or $_ -ceq 'f' } {
          # 絕對定位 ESC[row;colH（從 1 起算）。ConPTY 一律用它來移動游標。
          $parts = $params.Split(';')
          $rr = if ($parts.Count -ge 1 -and $parts[0] -match '^\d+$' -and [int]$parts[0] -gt 0) { [int]$parts[0] } else { 1 }
          $cc = if ($parts.Count -ge 2 -and $parts[1] -match '^\d+$' -and [int]$parts[1] -gt 0) { [int]$parts[1] } else { 1 }
          $state.Row = [math]::Min($Rows - 1, $rr - 1)
          $state.Col = [math]::Min($Cols - 1, $cc - 1)
        }
        'K' {
          # ESC[2K 清掉整列，但「不移動游標」（EL 的定義）。gwt 自己的畫面每次都先送 \r 再送
          # ESC[2K，所以游標怎樣都在行首；ConPTY 的輸出則會在游標已經移到某一欄之後才送 ESC[2K，
          # 這時把游標歸零會讓後面的文字畫到錯的位置。
          if ($first -eq 2) { & $blank $state.Row }
          elseif ($first -eq 1) {
            for ($c = 0; $c -le $state.Col; $c++) { $grid[$state.Row][$c] = ' ' }
            & $orphanRight $state.Row $state.Col
          }
          else {
            & $orphanLeft $state.Row $state.Col
            for ($c = $state.Col; $c -lt $Cols; $c++) { $grid[$state.Row][$c] = ' ' }
          }
        }
        'X' {
          $k = if ($first -gt 0) { $first } else { 1 }
          $end = [math]::Min($Cols, $state.Col + $k) - 1
          & $orphanLeft $state.Row $state.Col
          for ($c = $state.Col; $c -le $end; $c++) { $grid[$state.Row][$c] = ' ' }
          & $orphanRight $state.Row $end
        }
        'J' {
          if ($first -eq 2 -or $first -eq 3) {
            for ($r = 0; $r -lt $Rows; $r++) { & $blank $r }
          }
          elseif ($first -eq 1) {
            for ($r = 0; $r -lt $state.Row; $r++) { & $blank $r }
            for ($c = 0; $c -le $state.Col; $c++) { $grid[$state.Row][$c] = ' ' }
            & $orphanRight $state.Row $state.Col
          }
          else {
            & $orphanLeft $state.Row $state.Col
            for ($c = $state.Col; $c -lt $Cols; $c++) { $grid[$state.Row][$c] = ' ' }
            for ($r = $state.Row + 1; $r -lt $Rows; $r++) { & $blank $r }
          }
        }
      }
      continue
    }
    if ($ch -ceq "`r") { $state.Col = 0; $i++; continue }
    if ($ch -ceq "`n") { & $newline; $i++; continue }
    if ($ch -lt ' ') { $i++; continue }

    $unit = [string]$ch
    if ([char]::IsHighSurrogate($ch) -and ($i + 1 -lt $n) -and [char]::IsLowSurrogate($Text[$i + 1])) {
      $unit = $Text.Substring($i, 2)
      $i++
    }
    $i++
    $w = Get-CellWidth $unit
    # 延遲換行：寫到最後一欄之後，要等下一個字元才真的換行；放不下的全形字整個換行
    if ($state.Col + $w -gt $Cols) { $state.Wraps++; & $newline }
    # 寫在別的全形字的某一半上面：那個全形字的另一半要一起清掉（見 $orphanLeft／$orphanRight）
    & $orphanLeft $state.Row $state.Col
    & $orphanRight $state.Row ($state.Col + $w - 1)
    $grid[$state.Row][$state.Col] = $unit
    if ($w -eq 2) { $grid[$state.Row][$state.Col + 1] = $null }
    $state.Col += $w
  }

  $lines = for ($r = 0; $r -lt $Rows; $r++) {
    $sb = [System.Text.StringBuilder]::new()
    foreach ($cell in $grid[$r]) { if ($null -ne $cell) { [void]$sb.Append($cell) } }
    $sb.ToString().TrimEnd()
  }

  $itemRows = 0
  $indexes = [System.Collections.Generic.List[int]]::new()
  $selected = '-'
  foreach ($line in $lines) {
    $m = [regex]::Match($line, '\[(\d+)\]')
    if (-not $m.Success) { continue }
    $itemRows++
    $indexes.Add([int]$m.Groups[1].Value)
    if ($line.TrimStart().StartsWith('>')) { $selected = $m.Groups[1].Value }
  }
  $seen = [System.Collections.Generic.HashSet[int]]::new()
  $dups = [System.Collections.Generic.SortedSet[int]]::new()
  foreach ($x in $indexes) { if (-not $seen.Add($x)) { [void]$dups.Add($x) } }

  $compress = {
    param($nums)
    if ($nums.Count -eq 0) { return '-' }
    $parts = [System.Collections.Generic.List[string]]::new()
    $start = $nums[0]; $prev = $nums[0]
    for ($k = 1; $k -lt $nums.Count; $k++) {
      if ($nums[$k] -eq $prev + 1) { $prev = $nums[$k]; continue }
      $parts.Add($(if ($start -eq $prev) { "$start" } else { "$start-$prev" }))
      $start = $nums[$k]; $prev = $nums[$k]
    }
    $parts.Add($(if ($start -eq $prev) { "$start" } else { "$start-$prev" }))
    return ($parts -join ',')
  }

  $out = [System.Collections.Generic.List[string]]::new()
  $out.Add('--- 畫面 ---')
  foreach ($line in $lines) { $out.Add($line) }
  $out.Add('--- 結構摘要 ---')
  $out.Add("ITEM_ROWS=$itemRows")
  $out.Add("INDEXES=$(& $compress @($indexes))")
  $out.Add("DUPLICATES=$(if ($dups.Count -eq 0) { '-' } else { & $compress @($dups) })")
  $out.Add("SELECTED=$selected")
  $out.Add("WRAPS=$($state.Wraps)")
  return ($out -join "`n")
}
