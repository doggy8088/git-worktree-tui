#!/usr/bin/env zsh
# GWT_KEYS: /zzz\n\x15\n
# 沒有符合項目時 Enter 不應切換；Ctrl+U 清空後才能選取
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "清空搜尋後選第 1 筆" "$(fixture_path "$GWT_FIXTURE/shop" 1)" "$PWD"

t_report
