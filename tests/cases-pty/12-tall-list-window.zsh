#!/usr/bin/env zsh
# GWT_KEYS: \e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[Bq
# GWT_ROWS: 12
# GWT_COLS: 80
# GWT_SCREEN_EXPECT: ^請選擇 Worktree
# GWT_SCREEN_EXPECT: ^ > \[16\]
# GWT_SCREEN_EXPECT: ^ITEM_ROWS=9$
# GWT_SCREEN_EXPECT: ^INDEXES=8-16$
# GWT_SCREEN_EXPECT: ^DUPLICATES=-$
# GWT_SCREEN_EXPECT: ^SELECTED=16$
# 40 筆的清單放進 12 列的終端機：視窗要跟著選取項目捲動，
# 而且不能出現重複的列（這是清單比畫面高時會壞掉的地方）。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

# 要檢查「選單最後長什麼樣」，所以保留選單不擦掉
GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/many" || exit 1
before=$PWD
gwt
rc=$?

# 讓畫面重播停在這裡，才看得到選單最後的樣子
print -r -- GWT-SCREEN-CUT

assert_rc "取消回傳 1" 1 "$rc"
assert_eq "取消後目錄不變" "$before" "$PWD"

t_report
