#!/usr/bin/env zsh
# GWT_KEYS: \x1b
# GWT_EXPECT: \e[?25h
# 單獨按 Esc 應視為取消，而不是誤判成方向鍵
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
before=$PWD
gwt
rc=$?

assert_rc "取消回傳 1" 1 "$rc"
assert_eq "目錄維持不變" "$before" "$PWD"

t_report
