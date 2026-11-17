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
assert_contains "版本號可讀" "gwt 1.0.0" "$out"

out=$(gwt -V)
assert_eq "-V 與 --version 一致" "gwt 1.0.0" "$out"

# 英文介面
GWT_LANG=en
out=$(gwt --help)
assert_contains "英文介面可切換" "Usage: gwt" "$out"

t_report
