#!/usr/bin/env zsh
# GWT_KEYS: q
# GWT_EXPECT: \e[J
# GWT_EXPECT: \e[?25h
# 按 q 取消：目錄不變、選單被擦掉、游標復原
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
before=$PWD
gwt
rc=$?

assert_rc "取消回傳 1" 1 "$rc"
assert_eq "目錄維持不變" "$before" "$PWD"

t_report
