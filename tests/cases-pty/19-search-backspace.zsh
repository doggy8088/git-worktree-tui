#!/usr/bin/env zsh
# GWT_KEYS: /floginn\x7f\n
# Backspace 刪掉多打的一個字元
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "Backspace 後仍命中 feature/login" "$(fixture_path_matching "$GWT_FIXTURE/shop" shop-feature-login)" "$PWD"

t_report
