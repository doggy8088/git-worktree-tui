#!/usr/bin/env zsh
# GWT_KEYS: /zzz\e\n
# 搜尋中的 Esc 只清除搜尋，不會取消選單；緊接的 Enter 不可被吃掉
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "Esc 清除搜尋後 Enter 選第 1 筆" "$(fixture_path "$GWT_FIXTURE/shop" 1)" "$PWD"

t_report
