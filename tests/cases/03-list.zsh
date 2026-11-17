#!/usr/bin/env zsh
# gwt --list：只印路徑，每行一筆，含空白路徑也要完整
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1

out=$(gwt --list)
rc=$?
assert_rc "--list 回傳 0" 0 "$rc"
assert_rc "列出 5 筆" 5 "$(print -r -- "$out" | grep -c '^' | tr -d ' ')"
assert_contains "含空白路徑完整輸出" "shop-feature search api" "$out"
assert_eq "第一筆是主 worktree" "$(fixture_path "$GWT_FIXTURE/shop" 1)" \
  "$(print -r -- "$out" | head -1)"

# 搭配其他工具時，--list 應該可以被 grep 直接吃掉
n=$(gwt --list | grep -c 'feature')
assert_rc "grep 得到 2 筆 feature" 2 "$n"

# 沒有其他 worktree 時仍應印出自己那一筆
cd "$GWT_FIXTURE/plain" || exit 1
out=$(gwt --list)
assert_rc "單一 worktree 列出 1 筆" 1 "$(print -r -- "$out" | grep -c '^')"

t_report
