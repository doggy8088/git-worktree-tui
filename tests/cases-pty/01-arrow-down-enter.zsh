#!/usr/bin/env zsh
# GWT_KEYS: \e[B\e[B\n
# GWT_EXPECT: \e[?25h
# 方向鍵下移兩次再按 Enter，應切到第 3 筆
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "↓↓Enter 切換到第 3 筆" "$(fixture_path "$GWT_FIXTURE/shop" 3)" "$PWD"

t_report
