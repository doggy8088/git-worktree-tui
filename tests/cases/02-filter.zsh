#!/usr/bin/env zsh
# 關鍵字篩選：比對「路徑 + 分支」、不分大小寫、glob 字元只當普通文字
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

_gwt_load_msgs
_PORCELAIN='
worktree /repos/shop
HEAD 1111111aaaa
branch refs/heads/main

worktree /repos/shop hotfix
HEAD 2222222bbbb
branch refs/heads/hotfix

worktree /repos/shop-feature
HEAD 3333333cccc
branch refs/heads/feature/login

worktree /repos/shop-fix-cart-bug
HEAD 4444444dddd
branch refs/heads/fix/cart-bug

'

collect_with() {
  _gwt_reset_state
  _gwt_collect "$1" <<< "$_PORCELAIN"
}

collect_with 'feature'
assert_rc "關鍵字命中分支名稱" 1 "$_GWT_COUNT"

collect_with 'FEATURE'
assert_rc "預設不分大小寫" 1 "$_GWT_COUNT"

collect_with 'hotfix'
assert_rc "路徑命中（shop hotfix）" 1 "$_GWT_COUNT"
assert_eq "命中含空白路徑" "/repos/shop hotfix" "${_GWT_PATHS[1]}"

collect_with 'feature/login'
assert_rc "可以比對含斜線的分支" 1 "$_GWT_COUNT"

# 這裡刻意用同一個短關鍵字，驗證「路徑也算在比對範圍內」這個原文提到的行為
collect_with 'fix'
assert_rc "fix 同時命中路徑與分支" 2 "$_GWT_COUNT"

collect_with 'nomatch'
assert_rc "沒有符合時為 0 筆" 0 "$_GWT_COUNT"

# 關鍵字含 glob 字元時只能當普通文字，不能變成萬用字元
collect_with '*'
assert_rc "星號不當萬用字元" 0 "$_GWT_COUNT"

collect_with '?'
assert_rc "問號不當萬用字元" 0 "$_GWT_COUNT"

# 關掉不分大小寫後，大寫關鍵字就應該找不到
GWT_FILTER_CASE_INSENSITIVE=0
collect_with 'FEATURE'
assert_rc "關閉不分大小寫後找不到" 0 "$_GWT_COUNT"

t_report
