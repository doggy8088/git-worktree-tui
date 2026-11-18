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

function Get-CellWidth {
  param([string]$Unit)
  if ($Unit.Length -ge 2) { return 2 }   # 代理對（emoji 等）
  $code = [int]$Unit[0]
  if (($code -ge 0x1100 -and $code -le 0x115F) -or ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
    ($code -ge 0xAC00 -and $code -le 0xD7A3) -or ($code -ge 0xF900 -and $code -le 0xFAFF) -or
    ($code -ge 0xFE30 -and $code -le 0xFE4F) -or ($code -ge 0xFF00 -and $code -le 0xFF60) -or
    ($code -ge 0xFFE0 -and $code -le 0xFFE6)) { return 2 }
  return 1
}

# 傳回一整段文字：畫面 + 結構摘要（格式與 screen.py 相同），測試用 Assert-Screen 比對。
function Get-ScreenReplay {
  param([string]$Text, [int]$Rows = 24, [int]$Cols = 80)

  # 每個儲存格存一個字串；全形字的第二格存 $null（輸出時略過）
  $grid = New-Object 'object[]' ($Rows)
  for ($r = 0; $r -lt $Rows; $r++) { $grid[$r] = New-Object 'object[]' ($Cols); for ($c = 0; $c -lt $Cols; $c++) { $grid[$r][$c] = ' ' } }
  $state = @{ Row = 0; Col = 0 }

  $blank = {
    param($r)
    for ($c = 0; $c -lt $Cols; $c++) { $grid[$r][$c] = ' ' }
  }
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
          elseif ($first -eq 1) { for ($c = 0; $c -le $state.Col; $c++) { $grid[$state.Row][$c] = ' ' } }
          else { for ($c = $state.Col; $c -lt $Cols; $c++) { $grid[$state.Row][$c] = ' ' } }
        }
        'X' {
          $k = if ($first -gt 0) { $first } else { 1 }
          for ($c = $state.Col; $c -lt [math]::Min($Cols, $state.Col + $k); $c++) { $grid[$state.Row][$c] = ' ' }
        }
        'J' {
          if ($first -eq 2 -or $first -eq 3) {
            for ($r = 0; $r -lt $Rows; $r++) { & $blank $r }
          }
          elseif ($first -eq 1) {
            for ($r = 0; $r -lt $state.Row; $r++) { & $blank $r }
            for ($c = 0; $c -le $state.Col; $c++) { $grid[$state.Row][$c] = ' ' }
          }
          else {
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
    if ($state.Col + $w -gt $Cols) { & $newline }
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
  return ($out -join "`n")
}
