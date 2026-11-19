#!/usr/bin/env zsh
# GWT_KEYS: \e[B9\n
# GWT_SCREEN_EXPECT: ^SELECTED=2$
# GWT_SCREEN_EXPECT: ^DUPLICATES=-$
# 5 筆時先往下移到第 2 筆，再按 9（超出範圍，應被忽略），最後按 Enter：
# 被忽略的數字不能動到目前的選取——光棒要還在第 2 筆，Enter 要切到第 2 筆。
# （舊版不論有沒有效都先把選取改成 9：光棒消失，Enter 選到不存在的第 9 筆。）
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

# 要檢查「按 9 之後光棒還在不在」，所以保留選單不擦掉
GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

print -r -- GWT-SCREEN-CUT

assert_rc "回傳 0" 0 "$rc"
assert_eq "Enter 切到原本選取的第 2 筆" "$(fixture_path "$GWT_FIXTURE/shop" 2)" "$PWD"

t_report
