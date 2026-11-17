#!/usr/bin/env zsh
# GWT_KEYS: jj\n
# vim 風格的 j/k 移動
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "jjEnter 切換到第 3 筆" "$(fixture_path "$GWT_FIXTURE/shop" 3)" "$PWD"

t_report
