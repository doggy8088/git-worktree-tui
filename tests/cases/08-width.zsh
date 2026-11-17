#!/usr/bin/env zsh
# 寬度計算與中間截斷
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

_gwt_swidth 'abc'
assert_rc "ASCII 寬度" 3 "$_GWT_SW"

_gwt_swidth '(目前位置)'
assert_rc "CJK 全形字算兩欄" 10 "$_GWT_SW"

_gwt_swidth '(current)'
assert_rc "英文標註寬度" 9 "$_GWT_SW"

_gwt_strip_ansi $'\e[36m[main]\e[0m'
assert_eq "去色後只剩文字" '[main]' "$REPLY"

_gwt_width_of $'\e[1;30;46m > [1] /a \e[0m'
assert_rc "上色字串的寬度不含跳脫序列" 10 "$_GWT_SW"

_gwt_clip_middle '/a/very/long/path/to/shop-feature-login' 20
_gwt_swidth "$REPLY"
assert_rc "截斷後不超過指定欄寬" 1 "$(( _GWT_SW <= 20 ))"
assert_contains "截斷處有省略號" '…' "$REPLY"
assert_contains "保留結尾較有用的部分" 'login' "$REPLY"

_gwt_clip_middle '/short' 20
assert_eq "夠短時原樣保留" '/short' "$REPLY"

_gwt_clip_middle '/tmp/x' 3
_gwt_swidth "$REPLY"
assert_rc "預算極小時也不超過欄寬" 1 "$(( _GWT_SW <= 3 ))"

t_report
