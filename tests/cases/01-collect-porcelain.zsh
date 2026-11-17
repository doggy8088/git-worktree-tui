#!/usr/bin/env zsh
# _gwt_collect 解析 porcelain：多筆、路徑含空白、detached HEAD
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

_gwt_load_msgs
_gwt_reset_state

# 直接用固定的 porcelain 文字測試，不依賴實際儲存庫
_gwt_collect '' <<'PORCELAIN'
worktree /repos/shop
HEAD 89ae97a1b2c3d4e5f6a7b8
branch refs/heads/main

worktree /repos/shop feature api
HEAD 0123456789abcdef0123
branch refs/heads/feature/search-api

worktree /repos/shop-hotfix
HEAD fedcba9876543210fedc
detached

PORCELAIN

assert_rc "解析出 3 筆" 3 "$_GWT_COUNT"
assert_eq "第 1 筆路徑" "/repos/shop" "${_GWT_PATHS[1]}"
assert_eq "第 2 筆路徑含空白不被切開" "/repos/shop feature api" "${_GWT_PATHS[2]}"
assert_eq "第 3 筆路徑" "/repos/shop-hotfix" "${_GWT_PATHS[3]}"
assert_eq "分支去掉 refs/heads/ 前綴" "feature/search-api" "${_GWT_BRANCHES[2]}"
assert_eq "detached HEAD 標成 detached" "detached" "${_GWT_BRANCHES[3]}"
assert_eq "commit 只保留前 7 碼" "89ae97a" "${_GWT_HEADS[1]}"

t_report
