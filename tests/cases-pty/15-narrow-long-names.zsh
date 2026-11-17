#!/usr/bin/env zsh
# GWT_KEYS: \e[B\n
# GWT_ROWS: 12
# GWT_COLS: 40
# GWT_SCREEN_EXPECT: ^ITEM_ROWS=2$
# GWT_SCREEN_EXPECT: ^DUPLICATES=-$
# GWT_SCREEN_EXPECT: ^ > \[2\]
# 40 欄的窄視窗加上超長分支名與超長目錄名：
# 每一列都必須裁到一行以內，否則折行會讓重繪錯位。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

# 要檢查「選單最後長什麼樣」，所以保留選單不擦掉
GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/longname" || exit 1
gwt
rc=$?

# 讓畫面重播停在這裡，才看得到選單最後的樣子
print -r -- GWT-SCREEN-CUT

assert_rc "回傳 0" 0 "$rc"
assert_eq "切換到長名字的 worktree" "$(fixture_path "$GWT_FIXTURE/longname" 2)" "$PWD"

t_report
