# 畫面重播器（tests/pwsh/lib/Screen.ps1）本身的測試。
#
# 所有排版斷言（有沒有折行、有沒有重複的列、殘影）都建立在它「重播得跟真實終端機一樣」之上；
# 它如果有誤，要嘛讓真的錯誤被放過，要嘛讓沒有錯的東西失敗。所以重播器的語意要有自己的測試，
# 不能只靠「用它的測試都通過」來證明它是對的。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

# 重播後的畫面（只取畫面本身那幾列，不含結構摘要）
function Get-Rows {
  param([string]$Text, [int]$Rows = 4, [int]$Cols = 20)
  $all = (Get-ScreenReplay -Text $Text -Rows $Rows -Cols $Cols) -split "`n"
  return @($all[1..$Rows])
}
$e = [string][char]27

# --- 清除 ------------------------------------------------------------------------------------
# ESC[2K 清掉整列但不移動游標（EL 的定義）：後面的文字接在原本的欄位
$r = Get-Rows "abc${e}[2KX"
Assert-Eq 'ESC[2K 之後游標留在原本的欄（abc 三個字之後寫 X 落在第 4 欄）' '   X' $r[0]
$r = Get-Rows "abc`r${e}[2KX"
Assert-Eq '先 \r 再 ESC[2K（gwt 的畫法）：X 在行首' 'X' $r[0]

# ESC[K／ESC[0K 清到行尾，ESC[1K 清到游標（含游標那一格）
$r = Get-Rows "abcdef`r${e}[3C${e}[KX"
Assert-Eq 'ESC[K 清游標到行尾，X 寫在第 4 欄' 'abcX' $r[0]
$r = Get-Rows "abcdef`r${e}[2C${e}[1KX"
Assert-Eq 'ESC[1K 清行首到游標（含游標那一格）' '  Xdef' $r[0]

# ESC[J 清游標到畫面結尾（含游標之後的列）
$r = Get-Rows "one`ntwo`nthree${e}[2A${e}[J"
Assert-Eq 'ESC[J 保留游標之前的內容' 'one' $r[0]
Assert-Eq 'ESC[J 清掉下一列' '' $r[1]
Assert-Eq 'ESC[J 清掉再下一列' '' $r[2]
$r = Get-Rows "aaa`nbbb`nccc${e}[2J"
Assert-Eq 'ESC[2J 清掉整個畫面' '' (($r | Where-Object { $_ -ne '' }) -join '')

# --- 游標移動 ---------------------------------------------------------------------------------
$r = Get-Rows "${e}[3;5HX"
Assert-Eq 'ESC[3;5H 絕對定位（第 3 列第 5 欄，從 1 起算）' '    X' $r[2]
Assert-Eq '定位之前的列是空的' '' $r[0]
$r = Get-Rows "a`nb`nc${e}[2Ax"
Assert-Eq 'ESC[2A 往上兩列（寫在第 1 列；c 之後游標在第 2 欄，所以 x 接在 a 後面）' 'ax' $r[0]
$r = Get-Rows "ab${e}[5Cx"
Assert-Eq 'ESC[5C 往右五欄' 'ab     x' $r[0]
$r = Get-Rows "abcdef${e}[3Gx"
Assert-Eq 'ESC[3G 移到第 3 欄' 'abxdef' $r[0]
$r = Get-Rows "abc`n${e}[10A${e}[1Bx"
Assert-Eq '往上超過頂端會被夾住（不是負數）' 'abc' $r[0]
Assert-Eq '被夾住之後再往下一列寫字' 'x' $r[1]

# --- 換行與捲動 -------------------------------------------------------------------------------
$r = Get-Rows "ab`ncd"
Assert-Eq '\n 等於換行加歸位（真實終端機的 ONLCR）：第一列' 'ab' $r[0]
Assert-Eq '\n 等於換行加歸位：第二列從行首開始' 'cd' $r[1]
$r = Get-Rows "a`nb`nc" -Rows 2
Assert-Eq '超過畫面高度時整頁上捲：第一列是 b' 'b' $r[0]
Assert-Eq '超過畫面高度時整頁上捲：第二列是 c' 'c' $r[1]
$r = Get-Rows "abcde" -Cols 5
$r2 = Get-Rows "abcdef" -Cols 5
Assert-Eq '剛好寫滿一列不會立刻換行（延遲換行）' 'abcde' $r[0]
Assert-Eq '寫滿之後再寫一個字才換到下一列' 'f' $r2[1]

# --- 全形字與代理對佔兩個儲存格 --------------------------------------------------------------------
$r = Get-Rows "ab中文" -Cols 5
Assert-Eq '全形字放不下時整個換到下一列（不會切成半個）：第一列' 'ab中' $r[0]
Assert-Eq '全形字放不下時整個換到下一列：第二列' '文' $r[1]
$r = Get-Rows "中文字" -Cols 6
Assert-Eq '3 個全形字剛好 6 欄，不換行' '中文字' $r[0]
$r = Get-Rows "a😀b" -Cols 4
Assert-Eq 'emoji（代理對）佔兩欄：a😀b 剛好 4 欄' 'a😀b' $r[0]
$r = Get-Rows "ab😀c" -Cols 4
Assert-Eq 'ab😀 剛好 4 欄放得下，只有後面的 c 換行：第一列' 'ab😀' $r[0]
Assert-Eq 'ab😀 剛好 4 欄放得下，只有後面的 c 換行：第二列' 'c' $r[1]
$r = Get-Rows "abc😀d" -Cols 4
Assert-Eq 'emoji 只剩一欄放不下時整個換行（不會切成半個）：第一列' 'abc' $r[0]
Assert-Eq 'emoji 整個換到下一列：下一列' '😀d' $r[1]

# --- 蓋在全形字的一半上面（Copilot：蓋寫全形字會留下舊的儲存格）------------------------------------
# 全形字佔兩格（左半存字、右半存 $null）。蓋掉其中一半，另一半必須跟著清成空白，跟真實終端機一樣；
# 否則殘留的半個會讓整列欄位錯開，後面的斷言（折行、殘影）就不可靠。
$r = Get-Rows "a中b`r${e}[2CX" -Cols 10
Assert-Eq '蓋在全形字的右半上：整個全形字清成空白，新的字寫在原位' 'a Xb' $r[0]
$r = Get-Rows "a中b`r${e}[1CX" -Cols 10
Assert-Eq '蓋在全形字的左半上：右半跟著清成空白' 'aX b' $r[0]
$r = Get-Rows "中文`r${e}[1C字" -Cols 10
Assert-Eq '全形字蓋在兩個全形字的交界上：兩邊各剩的半個都清掉' ' 字' $r[0]
$r = Get-Rows "a中b`r${e}[2C${e}[K" -Cols 10
Assert-Eq 'ESC[K 從全形字的右半開始清：整個全形字清掉' 'a' $r[0]
$r = Get-Rows "a中b`r${e}[1C${e}[1K" -Cols 10
Assert-Eq 'ESC[1K 清到全形字的左半為止：右半也清掉' '   b' $r[0]
$r = Get-Rows "a中b`r${e}[2C${e}[1X" -Cols 10
Assert-Eq 'ESC[1X 清掉全形字的右半：左半也清掉，後面的字不動' 'a  b' $r[0]
$r = Get-Rows "a中b`r${e}[2C${e}[J" -Cols 10
Assert-Eq 'ESC[J 從全形字的右半開始清：整個全形字清掉' 'a' $r[0]
# 整列都被蓋掉（gwt 的畫法：\r、ESC[2K、重寫）不受影響
$r = Get-Rows "中文字`r${e}[2Kabc" -Cols 10
Assert-Eq '整列清掉再重寫：沒有殘留' 'abc' $r[0]

# --- 寬度對照 Unicode 的標準答案（與 gwt 的 Get-GwtWidth 是兩份各自的實作，各自對照同一份清單）-------------
. "$env:GWT_ROOT\tests\pwsh\lib\WidthOracle.ps1"
foreach ($entry in $script:WidthOracle) {
  $ch = [char]::ConvertFromUtf32($entry.Cp)
  Assert-Rc "重播器的 Get-CellWidth：$($entry.Name) 應為 $($entry.W) 欄" $entry.W (Get-CellWidth $ch)
}
# 寬符號放不下時整個換行，跟 CJK 一樣（⚡ 是基本多文種平面的字元，不是代理對）
$bolt = [string][char]0x26A1
$r = Get-Rows "ab${bolt}c" -Cols 4
Assert-Eq '⚡ 剛好 4 欄放得下：第一列' "ab${bolt}" $r[0]
Assert-Eq '⚡ 剛好 4 欄放得下：後面的 c 換行' 'c' $r[1]
$r = Get-Rows "abc${bolt}d" -Cols 4
Assert-Eq '⚡ 只剩一欄放不下：整個換到下一列（第一列）' 'abc' $r[0]
Assert-Eq '⚡ 只剩一欄放不下：整個換到下一列' "${bolt}d" $r[1]

# --- 該忽略的序列 -----------------------------------------------------------------------------
$r = Get-Rows "${e}[1;30;46mab${e}[0m"
Assert-Eq 'SGR（顏色）不佔欄位' 'ab' $r[0]
$r = Get-Rows "${e}[?25lab${e}[?25h"
Assert-Eq '顯示／隱藏游標不佔欄位' 'ab' $r[0]
$r = Get-Rows "${e}]0;視窗標題$([char]7)x"
Assert-Eq 'OSC 視窗標題（以 BEL 結尾）整段略過' 'x' $r[0]
$r = Get-Rows "${e}]0;title${e}\x"
Assert-Eq 'OSC 視窗標題（以 ST 結尾）整段略過' 'x' $r[0]
$r = Get-Rows "${e}(Bx"
Assert-Eq '字元集切換 ESC(B 略過' 'x' $r[0]

# --- 自動換行的計數（WRAPS）-------------------------------------------------------------------
# 只數「寫滿一列還繼續寫」造成的自動換行，明確的 \n 不算
function Get-Wraps { param([string]$Text, [int]$Rows = 6, [int]$Cols = 5) ([regex]::Match((Get-ScreenReplay -Text $Text -Rows $Rows -Cols $Cols), '(?m)^WRAPS=(\d+)$')).Groups[1].Value }
Assert-Eq '剛好寫滿一列、沒有再寫：沒有自動換行' '0' (Get-Wraps 'abcde')
Assert-Eq '寫滿之後再寫一個字：一次自動換行' '1' (Get-Wraps 'abcdef')
Assert-Eq '寫滿之後接明確的 \n：不算自動換行' '0' (Get-Wraps "abcde`nfgh")
Assert-Eq '全形字放不下而換行：算一次' '1' (Get-Wraps 'ab中文')
Assert-Eq '一個字串寫了十二個字在 5 欄：折成三列、兩次自動換行' '2' (Get-Wraps 'abcdefghijkl')
Assert-Eq 'gwt 的畫法（每列都先 \r、清列、寫、\n）不寬於欄寬：沒有自動換行' '0' (Get-Wraps "`r${e}[2Kabcd`n`r${e}[2Kefgh`n")

# --- 結構摘要（ITEM_ROWS／INDEXES／DUPLICATES／SELECTED）--------------------------------------------
$summary = Get-ScreenReplay -Text " > [1] aaa`n   [2] bbb`n   [2] dup`n   [4] ddd`n" -Rows 6 -Cols 40
Assert-Screen '摘要：列數' '^ITEM_ROWS=4$' $summary
Assert-Screen '摘要：編號壓成區間（1,2,2,4 → 1-2,2,4）' '^INDEXES=1-2,2,4$' $summary
Assert-Screen '摘要：重複的編號' '^DUPLICATES=2$' $summary
Assert-Screen '摘要：光棒所在的編號' '^SELECTED=1$' $summary

Complete-Tests
