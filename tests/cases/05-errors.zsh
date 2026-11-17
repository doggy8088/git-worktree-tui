#!/usr/bin/env zsh
# 錯誤情境：找不到符合、不在 Git 儲存庫、未知選項
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1

out=$(gwt nomatch 2>&1)
rc=$?
assert_rc "找不到符合回傳 1" 1 "$rc"
assert_contains "訊息含關鍵字" "nomatch" "$out"
assert_contains "訊息說明找不到" "找不到符合" "$out"

before=$PWD
gwt nomatch >/dev/null 2>&1
assert_eq "找不到時目錄不變" "$before" "$PWD"

cd "$GWT_FIXTURE/outside" || exit 1
out=$(gwt 2>&1)
rc=$?
assert_rc "非 Git 目錄回傳 1" 1 "$rc"
assert_contains "訊息說明不在儲存庫" "不在 Git 儲存庫中" "$out"

cd "$GWT_FIXTURE/shop" || exit 1
out=$(gwt --bogus 2>&1)
rc=$?
assert_rc "未知選項回傳 2" 2 "$rc"
assert_contains "訊息含選項名稱" "--bogus" "$out"

# 非互動環境（管線）且有兩個以上 worktree 時，應明確拒絕而不是卡住
out=$(print '' | gwt 2>&1)
rc=$?
assert_rc "非 tty 回傳 1" 1 "$rc"
assert_contains "訊息說明需要終端機" "互動式終端機" "$out"

t_report
