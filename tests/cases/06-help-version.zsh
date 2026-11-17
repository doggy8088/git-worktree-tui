#!/usr/bin/env zsh
# --help 與 --version
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

out=$(gwt --help)
rc=$?
assert_rc "--help 回傳 0" 0 "$rc"
assert_contains "說明含用法" "用法：gwt" "$out"
assert_contains "說明含 --list" "--list" "$out"
assert_contains "說明列出環境變數" "GWT_CLEAR_ON_EXIT" "$out"

out=$(gwt -h)
assert_rc "-h 回傳 0" 0 "$?"

out=$(gwt --version)
assert_rc "--version 回傳 0" 0 "$?"
assert_eq "輸出與 GWT_VERSION 一致" "gwt $GWT_VERSION" "$out"

# 版本號格式必須是 x.y.z，避免改版時不小心打成別的形式
[[ $out == 'gwt '<->.<->.<-> ]]
assert_rc "版本號格式為 x.y.z" 0 "$?"

out=$(gwt -V)
assert_eq "-V 與 --version 一致" "gwt $GWT_VERSION" "$out"

# 英文介面
GWT_LANG=en
out=$(gwt --help)
assert_contains "英文介面可切換" "Usage: gwt" "$out"

t_report
