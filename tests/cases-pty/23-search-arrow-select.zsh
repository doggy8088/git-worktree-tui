#!/usr/bin/env zsh
# GWT_KEYS: /f\e[B\n
# GWT_ROWS: 20
# GWT_COLS: 100
# GWT_SCREEN_EXPECT: ^ITEM_ROWS=4$
# GWT_SCREEN_EXPECT: ^SELECTED=2$
# 搜尋後仍可用方向鍵改變選取，Enter 要切到第 2 筆結果
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

# 保留選單，才能檢查光棒停在哪一列
GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

print -r -- GWT-SCREEN-CUT

assert_rc "回傳 0" 0 "$rc"
assert_eq "方向鍵移到第 2 筆並切換" \
  "$(fixture_path_matching "$GWT_FIXTURE/shop" shop-fix-cart-bug)" "$PWD"

t_report
