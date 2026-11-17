#!/usr/bin/env zsh
# GWT_KEYS: /shopfix\n
# 搜尋只比對目錄的最後一層：shopfix → shop-fix-cart-bug
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "目錄名稱模糊搜尋" "$(fixture_path_matching "$GWT_FIXTURE/shop" shop-fix-cart-bug)" "$PWD"

t_report
