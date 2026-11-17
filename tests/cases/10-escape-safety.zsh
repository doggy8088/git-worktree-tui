#!/usr/bin/env zsh
# 迴歸測試：分支名稱與路徑裡的 % 與反斜線不能被當成格式字串解讀
# 原文用 %b 印出後方的分支資訊，遇到 a\nb 這種分支會被轉成真的換行。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

_gwt_load_msgs
_gwt_reset_state

_GWT_PATHS=('/repos/100%s-discount')
_GWT_BRANCHES=('a\nb\tc')
_GWT_HEADS=('1234567')
_GWT_COUNT=1
_GWT_CURRENT=''
_GWT_WIDTH=120
_GWT_SELECTED=1
_GWT_S_RESET=''
_GWT_S_BAR=''
_GWT_S_BRANCH=''
_GWT_S_MARK=''

_gwt_format_row 1
row=$REPLY

assert_contains "反斜線 n 維持字面" 'a\nb\tc' "$row"
assert_not_contains "沒有被轉成真正的換行" $'\n' "$row"
assert_contains "路徑中的百分比符號原樣保留" '/repos/100%s-discount' "$row"

# 透過 _gwt_draw 走一次 printf，確認 % 不會被當成格式指示符
out=$(_gwt_draw)
assert_contains "printf 不會把 %s 吃掉" '[a\nb\tc]' "$out"
assert_not_contains "輸出中沒有格式錯誤訊息" 'not found' "$out"

t_report
