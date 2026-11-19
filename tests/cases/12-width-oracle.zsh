#!/usr/bin/env zsh
# 字元欄寬對照 Unicode 的標準答案。
#
# 答案不在這裡另抄一份：直接讀 PowerShell 版測試用的 tests/pwsh/lib/WidthOracle.ps1
# （逐字寫死的碼點與欄寬，來源是 Unicode 的 East Asian Width），兩個版本對同一份答案。
#
# 舊版的表只有 CJK 與全形的範圍，⚡ ⌚ ✅ ⭐ 這類「基本多文種平面裡寬度為 2 的 emoji 符號」被當成 1 欄；
# 分支或路徑含這些符號時，一列比算出來的寬而折行，重繪就錯位。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

oracle="$GWT_ROOT/tests/pwsh/lib/WidthOracle.ps1"
typeset -i total=0 wrong=0 cp want
typeset line hex ch
while IFS= read -r line; do
  [[ $line =~ 'Cp = 0x([0-9A-Fa-f]+); W = ([12]);' ]] || continue
  hex=$match[1]
  want=$match[2]
  cp=$(( 16#$hex ))
  ch=${(#)cp}
  _gwt_swidth "$ch"
  (( total++ ))
  if (( _GWT_SW != want )); then
    (( wrong++ ))
    printf '        U+%s：期望 %d 欄，實得 %d 欄（%s）\n' "$hex" "$want" "$_GWT_SW" "${${line#*Name = \'}%\'*}"
  fi
done < "$oracle"

# 清單讀不到（路徑錯、格式改了）時，下面的「全部相符」會空洞地成立，所以先確認真的讀到了
assert_rc "讀到標準答案清單（至少 50 個字元）" 1 "$(( total >= 50 ))"
assert_rc "每個字元的欄寬都與 Unicode 標準答案相符（共 ${total} 個）" 0 "$wrong"

# 混在字串裡也一樣：分支名稱含 emoji 符號時整串的寬度
_gwt_swidth 'fix⚡bug'
assert_rc "含 ⚡ 的分支名稱：6 個 ASCII + 2" 8 "$_GWT_SW"
_gwt_swidth $'feat-\U0001F525'
assert_rc "基本多文種平面以外的 emoji（🔥）算 2 欄" 7 "$_GWT_SW"

# 截斷：預算以欄計，寬字不能被算成 1 欄而超出
_gwt_clip_middle '⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡' 9
_gwt_swidth "$REPLY"
assert_rc "全是寬 emoji 的字串截斷後不超過 9 欄（實得 ${_GWT_SW}）" 1 "$(( _GWT_SW <= 9 ))"

t_report
