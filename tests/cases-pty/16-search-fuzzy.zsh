#!/usr/bin/env zsh
# GWT_KEYS: /flogin\n
# GWT_EXPECT: 搜尋：
# 按 / 進入搜尋，fuzzy 比對分支名稱：flogin → feature/login
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

cd "$GWT_FIXTURE/shop" || exit 1
gwt
rc=$?

assert_rc "回傳 0" 0 "$rc"
assert_eq "模糊搜尋選到 feature/login" "$(fixture_path_matching "$GWT_FIXTURE/shop" shop-feature-login)" "$PWD"

t_report
