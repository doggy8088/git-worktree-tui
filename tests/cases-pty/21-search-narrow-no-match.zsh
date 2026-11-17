#!/usr/bin/env zsh
# GWT_KEYS: /zzz\n\x15\n
# GWT_ROWS: 12
# GWT_COLS: 30
# GWT_SCREEN_EXPECT: ^AFTER=
# GWT_SCREEN_EXPECT_NOT: 請選擇 Worktree
# GWT_SCREEN_EXPECT_NOT: 沒有符合
# 窄視窗加上「沒有符合」提示時，收尾仍要把整個區塊擦乾淨
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?
print -r -- "AFTER=$PWD"

assert_rc "回傳 0" 0 "$rc"
assert_eq "清空後選第 1 筆" "$(fixture_path "$GWT_FIXTURE/shop" 1)" "$PWD"

t_report
