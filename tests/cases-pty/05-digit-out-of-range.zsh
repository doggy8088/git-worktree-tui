#!/usr/bin/env zsh
# GWT_KEYS: 9q
# 只有 5 筆時按 9 應被忽略，選單繼續等待輸入；接著按 q 取消
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
before=$PWD
gwt
rc=$?

assert_rc "取消回傳 1" 1 "$rc"
assert_eq "超出範圍的數字鍵不會切換" "$before" "$PWD"

t_report
