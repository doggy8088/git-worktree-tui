#!/usr/bin/env zsh
# GWT_KEYS: 9
# 12 筆時按 9：再加一位數就是 90 以上，一定超過 12，不可能是兩位數，必須立刻跳轉，
# 不能白等 GWT_DIGIT_TIMEOUT。（舊版是讀到第二位數「之後」才判斷，第一位數一律要等滿。）
# 等待時間刻意設成 5 秒、門檻 3 秒：耗時包含 ptydrive 等畫面靜止的 0.3 秒與 git 指令，
# 慢的 CI 機器也不會誤判；而有等的話一定超過 5 秒。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"
zmodload zsh/datetime

GWT_DIGIT_TIMEOUT=5
cd "$GWT_FIXTURE/twelve" || exit 1
start=$EPOCHREALTIME
gwt
rc=$?
elapsed=$(( EPOCHREALTIME - start ))

assert_rc "回傳 0" 0 "$rc"
assert_eq "跳到第 9 筆" "$(fixture_path "$GWT_FIXTURE/twelve" 9)" "$PWD"
assert_rc "沒有等第二位數（耗時 ${elapsed} 秒，應遠小於 GWT_DIGIT_TIMEOUT 的 5 秒）" 1 "$(( elapsed < 3 ))"

t_report
