# 字元寬度的「標準答案」：逐字寫死，不是任何程式算出來的。
#
# 來源是 Unicode 的 East Asian Width（EastAsianWidth.txt）：W（Wide）與 F（Fullwidth）佔 2 欄，
# 其餘（Na、N、H、A）佔 1 欄；基本多文種平面以外的 emoji 與 CJK 擴充區（代理對）也是 2 欄。
#
# 為什麼要獨立的標準答案：gwt.psm1 的 Get-GwtWidth 與測試重播器的 Get-CellWidth 是兩份各自的實作。
# 如果測試只拿其中一份去驗另一份，或兩份共用同一個只有 CJK 範圍的表，就會有同一個盲點——例如把 ⚡ ⌚ ✅
# 這類「基本多文種平面裡寬度為 2 的符號」當成 1 欄，選單的一列就會比算出來的寬，折行之後重繪錯位。
# 這份清單固定寫著每個字元該是幾欄，兩個實作都要對得上。
#
# Cp 是碼點，W 是預期欄寬，Name 是說明。
$script:WidthOracle = @(
  # --- 寬度 2：基本多文種平面裡的 emoji 與符號（只有 CJK 範圍的表會漏掉這一整類）---
  @{ Cp = 0x231A; W = 2; Name = 'U+231A WATCH' }
  @{ Cp = 0x231B; W = 2; Name = 'U+231B HOURGLASS' }
  @{ Cp = 0x23E9; W = 2; Name = 'U+23E9 FAST-FORWARD' }
  @{ Cp = 0x23F0; W = 2; Name = 'U+23F0 ALARM CLOCK' }
  @{ Cp = 0x23F3; W = 2; Name = 'U+23F3 HOURGLASS WITH FLOWING SAND' }
  @{ Cp = 0x25FD; W = 2; Name = 'U+25FD WHITE MEDIUM SMALL SQUARE' }
  @{ Cp = 0x2614; W = 2; Name = 'U+2614 UMBRELLA WITH RAIN DROPS' }
  @{ Cp = 0x2615; W = 2; Name = 'U+2615 HOT BEVERAGE' }
  @{ Cp = 0x2648; W = 2; Name = 'U+2648 ARIES' }
  @{ Cp = 0x267F; W = 2; Name = 'U+267F WHEELCHAIR SYMBOL' }
  @{ Cp = 0x2693; W = 2; Name = 'U+2693 ANCHOR' }
  @{ Cp = 0x26A1; W = 2; Name = 'U+26A1 HIGH VOLTAGE SIGN' }
  @{ Cp = 0x26AA; W = 2; Name = 'U+26AA MEDIUM WHITE CIRCLE' }
  @{ Cp = 0x26BD; W = 2; Name = 'U+26BD SOCCER BALL' }
  @{ Cp = 0x26C4; W = 2; Name = 'U+26C4 SNOWMAN WITHOUT SNOW' }
  @{ Cp = 0x26D4; W = 2; Name = 'U+26D4 NO ENTRY' }
  @{ Cp = 0x26EA; W = 2; Name = 'U+26EA CHURCH' }
  @{ Cp = 0x26F2; W = 2; Name = 'U+26F2 FOUNTAIN' }
  @{ Cp = 0x26FD; W = 2; Name = 'U+26FD FUEL PUMP' }
  @{ Cp = 0x2705; W = 2; Name = 'U+2705 WHITE HEAVY CHECK MARK' }
  @{ Cp = 0x270A; W = 2; Name = 'U+270A RAISED FIST' }
  @{ Cp = 0x2728; W = 2; Name = 'U+2728 SPARKLES' }
  @{ Cp = 0x274C; W = 2; Name = 'U+274C CROSS MARK' }
  @{ Cp = 0x274E; W = 2; Name = 'U+274E NEGATIVE SQUARED CROSS MARK' }
  @{ Cp = 0x2753; W = 2; Name = 'U+2753 BLACK QUESTION MARK ORNAMENT' }
  @{ Cp = 0x2757; W = 2; Name = 'U+2757 HEAVY EXCLAMATION MARK SYMBOL' }
  @{ Cp = 0x2795; W = 2; Name = 'U+2795 HEAVY PLUS SIGN' }
  @{ Cp = 0x27B0; W = 2; Name = 'U+27B0 CURLY LOOP' }
  @{ Cp = 0x27BF; W = 2; Name = 'U+27BF DOUBLE CURLY LOOP' }
  @{ Cp = 0x2B1B; W = 2; Name = 'U+2B1B BLACK LARGE SQUARE' }
  @{ Cp = 0x2B50; W = 2; Name = 'U+2B50 WHITE MEDIUM STAR' }
  @{ Cp = 0x2B55; W = 2; Name = 'U+2B55 HEAVY LARGE CIRCLE' }
  @{ Cp = 0x2329; W = 2; Name = 'U+2329 LEFT-POINTING ANGLE BRACKET' }
  # --- 寬度 2：CJK、韓文、全形 ---
  @{ Cp = 0x1100; W = 2; Name = 'U+1100 HANGUL CHOSEONG KIYEOK' }
  @{ Cp = 0x3000; W = 2; Name = 'U+3000 IDEOGRAPHIC SPACE' }
  @{ Cp = 0x3042; W = 2; Name = 'U+3042 HIRAGANA A' }
  @{ Cp = 0x30A2; W = 2; Name = 'U+30A2 KATAKANA A' }
  @{ Cp = 0x4E2D; W = 2; Name = 'U+4E2D CJK 中' }
  @{ Cp = 0xD55C; W = 2; Name = 'U+D55C HANGUL 한' }
  @{ Cp = 0xFF01; W = 2; Name = 'U+FF01 FULLWIDTH EXCLAMATION MARK' }
  @{ Cp = 0xFF21; W = 2; Name = 'U+FF21 FULLWIDTH LATIN A' }
  @{ Cp = 0xFFE1; W = 2; Name = 'U+FFE1 FULLWIDTH POUND SIGN' }
  # --- 寬度 2：基本多文種平面以外（代理對）---
  @{ Cp = 0x1F525; W = 2; Name = 'U+1F525 FIRE' }
  @{ Cp = 0x1F600; W = 2; Name = 'U+1F600 GRINNING FACE' }
  @{ Cp = 0x20000; W = 2; Name = 'U+20000 CJK EXTENSION B' }
  # --- 寬度 1 ---
  @{ Cp = 0x61; W = 1; Name = 'U+0061 LATIN a' }
  @{ Cp = 0x31; W = 1; Name = 'U+0031 DIGIT ONE' }
  @{ Cp = 0xE9; W = 1; Name = 'U+00E9 é' }
  @{ Cp = 0x2026; W = 1; Name = 'U+2026 HORIZONTAL ELLIPSIS（gwt 用它當省略號）' }
  @{ Cp = 0x2191; W = 1; Name = 'U+2191 UPWARDS ARROW（選單提示用）' }
  @{ Cp = 0x258F; W = 1; Name = 'U+258F LEFT ONE EIGHTH BLOCK（搜尋游標用）' }
  @{ Cp = 0x2500; W = 1; Name = 'U+2500 BOX DRAWINGS LIGHT HORIZONTAL' }
  @{ Cp = 0xFF71; W = 1; Name = 'U+FF71 HALFWIDTH KATAKANA A' }
  @{ Cp = 0x2600; W = 1; Name = 'U+2600 BLACK SUN WITH RAYS（預設是文字呈現，不是 emoji 呈現）' }
  @{ Cp = 0x26A0; W = 1; Name = 'U+26A0 WARNING SIGN' }
  @{ Cp = 0x2713; W = 1; Name = 'U+2713 CHECK MARK' }
  @{ Cp = 0x2714; W = 1; Name = 'U+2714 HEAVY CHECK MARK' }
  @{ Cp = 0x2764; W = 1; Name = 'U+2764 HEAVY BLACK HEART' }
  @{ Cp = 0x303F; W = 1; Name = 'U+303F IDEOGRAPHIC HALF FILL SPACE（夾在 CJK 範圍中間，卻是窄的）' }
)
