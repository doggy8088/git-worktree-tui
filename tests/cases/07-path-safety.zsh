#!/usr/bin/env zsh
# 迴歸測試：zsh 的 path 陣列與 PATH 連動，函式內絕不能出現 local path=
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

before_path=$PATH
cd "$GWT_FIXTURE/shop" || exit 1

gwt nomatch >/dev/null 2>&1
assert_eq "執行後 PATH 沒有被動到" "$before_path" "$PATH"

resolved=$(command -v ls)
assert_ne "仍找得到 ls" "" "$resolved"

# 直接掃原始碼（略過註解行），確保沒有人把變數取名為 path
src=$(grep -v '^[[:space:]]*#' "$GWT_ROOT/gwt.zsh")
assert_not_contains "原始碼沒有 local path=" 'local path=' "$src"
assert_not_contains "原始碼沒有 path= 這個宣告" 'path=""' "$src"

t_report
