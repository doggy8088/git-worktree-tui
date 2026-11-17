#!/usr/bin/env zsh
# GWT_KEYS: 40
# GWT_ROWS: 12
# GWT_COLS: 80
# GWT_SCREEN_EXPECT: ^ > \[40\]
# GWT_SCREEN_EXPECT: ^INDEXES=32-40$
# GWT_SCREEN_EXPECT: ^SELECTED=40$
# GWT_SCREEN_EXPECT: ^DUPLICATES=-$
# 40 筆的清單、12 列的終端機，直接按數字鍵跳到第 40 筆：
# 視窗要跟著跳到尾端，而且真的 cd 到第 40 筆。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

# 要檢查「選單最後長什麼樣」，所以保留選單不擦掉
GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/many" || exit 1
gwt
rc=$?

# 讓畫面重播停在這裡，才看得到選單最後的樣子
print -r -- GWT-SCREEN-CUT

assert_rc "回傳 0" 0 "$rc"
assert_eq "跳到第 40 筆" "$(fixture_path "$GWT_FIXTURE/many" 40)" "$PWD"

t_report
