#!/usr/bin/env zsh
# GWT_KEYS: \e[B\n
# GWT_ROWS: 12
# GWT_COLS: 20
# GWT_SCREEN_EXPECT: ^WRAPS=0$
# GWT_SCREEN_EXPECT: ^DUPLICATES=-$
# GWT_SCREEN_EXPECT: ^ITEM_ROWS=5$
# GWT_SCREEN_EXPECT: ^SELECTED=2$
# GWT_SCREEN_EXPECT: ^ > \[2\] /
# GWT_SCREEN_EXPECT_NOT: \([0-9a-f]{7}\)
# 20 欄的終端機：比舊版的寬度下限（24）還窄。下限改成 16（與 PowerShell 版相同），
# 加上依序省略 commit、分支之後，連這麼窄也不折行。fixture 只有 ASCII（見 27）。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

print -r -- GWT-SCREEN-CUT

assert_rc "回傳 0" 0 "$rc"
assert_eq "切換到第 2 筆" "$(fixture_path "$GWT_FIXTURE/shop" 2)" "$PWD"

t_report
