#!/usr/bin/env zsh
# GWT_KEYS: \e[B\n
# GWT_ROWS: 12
# GWT_COLS: 25
# GWT_SCREEN_EXPECT: ^WRAPS=0$
# GWT_SCREEN_EXPECT: ^DUPLICATES=-$
# GWT_SCREEN_EXPECT: ^ITEM_ROWS=5$
# GWT_SCREEN_EXPECT: ^SELECTED=2$
# GWT_SCREEN_EXPECT: ^ > \[2\] /
# GWT_SCREEN_EXPECT_NOT: \([0-9a-f]{7}\)
# 25 欄的終端機：完整的一列（編號 + 路徑 + [分支] + (commit)）至少要 26 欄，放不下。
# 不能硬塞而折行（折行會讓重繪的列數算錯，畫面留下殘影），要依序省略 commit、分支。
# 也不能為了塞下 [分支] (commit) 把路徑擠到只剩一個「…」：路徑至少要看得到開頭的 /（最少 4 欄），
# 放不下時 commit 要被省略，所以畫面上不該出現「(七碼 commit)」。
# fixture 只有 ASCII，畫面重播器的欄寬才準（它不認得全形字）。
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
