#!/usr/bin/env zsh
# GWT_KEYS: q
# GWT_EXPECT: \e[?25h
# GWT_EXPECT_NOT: \e[J
# GWT_CLEAR_ON_EXIT=0 時選單要留在畫面上（原文的預設行為）
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

GWT_CLEAR_ON_EXIT=0

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "取消回傳 1" 1 "$rc"

t_report
