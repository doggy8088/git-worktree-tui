#!/usr/bin/env zsh
# GWT_KEYS: 4
# 數字鍵直接跳轉，不需要再按 Enter
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "按 4 直接切到第 4 筆" "$(fixture_path "$GWT_FIXTURE/shop" 4)" "$PWD"

t_report
