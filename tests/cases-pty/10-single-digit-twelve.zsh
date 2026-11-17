#!/usr/bin/env zsh
# GWT_KEYS: 3
# 12 筆時只按一個 3：等 timeout 後應跳到第 3 筆，而不是卡住
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/twelve" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "單一數字在多位數清單中仍可用" "$(fixture_path "$GWT_FIXTURE/twelve" 3)" "$PWD"

t_report
