#!/usr/bin/env zsh
# 只有一筆符合時，不顯示選單直接切換（原文行為）
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
expected=$(fixture_path_matching "$GWT_FIXTURE/shop" 'fix-cart-bug')
assert_ne "測試資料裡找得到 cart-bug" "" "$expected"

gwt cart
rc=$?
assert_rc "單筆符合回傳 0" 0 "$rc"
assert_eq "直接切換到該 worktree" "$expected" "$PWD"

# 從子目錄執行也要能切換（git rev-parse --show-toplevel 會往上找）
mkdir -p "$GWT_FIXTURE/shop/src/sub"
cd "$GWT_FIXTURE/shop/src/sub" || exit 1
gwt hotfix
assert_eq "從子目錄也能切換" "$(fixture_path_matching "$GWT_FIXTURE/shop" 'hotfix')" "$PWD"

t_report
