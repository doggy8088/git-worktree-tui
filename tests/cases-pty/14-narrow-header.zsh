#!/usr/bin/env zsh
# GWT_KEYS: \e[B\n
# GWT_ROWS: 24
# GWT_COLS: 48
# GWT_SCREEN_EXPECT: ^AFTER=
# GWT_SCREEN_EXPECT_NOT: 請選擇 Worktree
# 窄視窗時表頭會被裁成一行；選完之後整塊都要擦乾淨，
# 不能在畫面上留下表頭的第一行（之前會留一條殘影）。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/twelve" || exit 1
gwt
gwt_rc=$?
print -r -- "AFTER=$PWD"

assert_rc "回傳 0" 0 "$gwt_rc"
assert_eq "切換到第 2 筆" "$(fixture_path "$GWT_FIXTURE/twelve" 2)" "$PWD"

t_report
