#!/usr/bin/env zsh
# GWT_KEYS: /flogin\n
# GWT_ROWS: 20
# GWT_COLS: 100
# GWT_SCREEN_EXPECT: ^ITEM_ROWS=1$
# GWT_SCREEN_EXPECT: ^INDEXES=1$
# GWT_SCREEN_EXPECT: ^DUPLICATES=-$
# 搜尋讓清單從 5 筆縮到 1 筆時，舊的列一定要被擦掉；
# 只畫新的列會讓畫面看起來像「清單沒有跟著搜尋變化」。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

# 保留選單，才能檢查最後的畫面
GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

print -r -- GWT-SCREEN-CUT

assert_rc "回傳 0" 0 "$rc"
assert_eq "搜尋後仍切換到 feature/login" \
  "$(fixture_path_matching "$GWT_FIXTURE/shop" shop-feature-login)" "$PWD"

t_report
