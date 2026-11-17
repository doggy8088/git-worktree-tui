#!/usr/bin/env zsh
# GWT_KEYS: \e[A\n
# 在第 1 筆按上移，應循環到最後一筆
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
total=$(fixture_count "$GWT_FIXTURE/shop")
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "上移循環到最後一筆" "$(fixture_path "$GWT_FIXTURE/shop" "$total")" "$PWD"

t_report
