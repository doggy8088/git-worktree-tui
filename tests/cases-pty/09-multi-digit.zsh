#!/usr/bin/env zsh
# GWT_KEYS: 12
# 12 筆時按 1 再按 2，應跳到第 12 筆（多位數編號）
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/twelve" || exit 1
total=$(fixture_count "$GWT_FIXTURE/twelve")
if (( total != 12 )); then
  print -r -- "  FAIL  測試資料應有 12 筆，實得 $total"
  exit 1
fi

gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "按 12 切到第 12 筆" "$(fixture_path "$GWT_FIXTURE/twelve" 12)" "$PWD"

t_report
