#!/usr/bin/env zsh
# GWT_KEYS: \x03
# GWT_EXPECT: \e[?25h
# Ctrl+C 中斷：回傳 130、目錄不變、游標一定要還回來（原文最在意的點）
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
before=$PWD
gwt
rc=$?

assert_rc "中斷回傳 130" 130 "$rc"
assert_eq "目錄維持不變" "$before" "$PWD"

# 中斷後 shell 仍可正常執行後續指令（游標與 trap 都已復原）
out=$(print -r -- alive)
assert_eq "中斷後 shell 仍正常" 'alive' "$out"

t_report
