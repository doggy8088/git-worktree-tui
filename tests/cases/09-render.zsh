#!/usr/bin/env zsh
# 選單列內容：光棒只在選取列、目前位置用黃色標註、分支用青色
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

_gwt_load_msgs
_gwt_reset_state

_GWT_PATHS=('/repos/shop' '/repos/shop-feature')
_GWT_BRANCHES=('main' 'feature/login')
_GWT_HEADS=('89ae97a' '89ae97a')
_GWT_COUNT=2
_GWT_CURRENT='/repos/shop'
_GWT_WIDTH=80
_GWT_SELECTED=1

# 非 tty 環境下 _gwt_init_style 會關閉顏色，這裡直接指定，才能驗證上色位置
_GWT_S_RESET=$'\e[0m'
_GWT_S_BAR=$'\e[1;30;46m'
_GWT_S_BRANCH=$'\e[36m'
_GWT_S_MARK=$'\e[33m'

out=$(_gwt_draw)
lines=("${(@f)out}")

assert_rc "畫出兩列" 2 "${#lines}"
assert_contains "選取列有光棒" $'\e[1;30;46m' "${lines[1]}"
assert_not_contains "未選取列沒有光棒" $'\e[1;30;46m' "${lines[2]}"
assert_contains "目前位置用黃色標註" $'\e[33m' "${lines[1]}"
assert_contains "分支名稱用青色" $'\e[36m[main]' "${lines[1]}"
assert_contains "未選取列也有分支名稱" $'\e[36m[feature/login]' "${lines[2]}"
assert_contains "顯示 commit 前 7 碼" '(89ae97a)' "${lines[1]}"

# 光棒只反白到路徑為止：重設碼要出現在分支之前
row=${lines[1]}
head_part=${row%%$'\e[0m'*}
assert_contains "光棒範圍含路徑" '/repos/shop' "$head_part"
assert_not_contains "光棒範圍不含分支" 'feature' "$head_part"

# 切換選取後，光棒應該換到第二列
_GWT_SELECTED=2
out=$(_gwt_draw)
lines=("${(@f)out}")
assert_not_contains "換選取後第一列沒有光棒" $'\e[1;30;46m' "${lines[1]}"
assert_contains "換選取後第二列有光棒" $'\e[1;30;46m' "${lines[2]}"

t_report
