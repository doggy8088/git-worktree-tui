#!/usr/bin/env zsh
# 模糊搜尋：子序列比對、只比對分支與最後一層目錄、多詞 AND、分數排序
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/gwt.zsh"

_gwt_load_msgs

# 刻意讓某一筆的路徑中段含有 marker，驗證不會拿完整路徑去比對
_gwt_all() {
  _GWT_ALL_PATHS=(
    '/repos/shop'
    '/repos/shop-feature-login'
    '/repos/shop-feature search api'
    '/repos/shop-fix-cart-bug'
    '/repos/shop-hotfix'
    '/repos/parent-only-marker/inner'
    '/repos/other'
  )
  _GWT_ALL_BRANCHES=(
    'main'
    'feature/login'
    'feature/search-api'
    'fix/cart-bug'
    'detached'
    'trunk'
    'feature/alpha'
  )
  _GWT_ALL_HEADS=(1111111 2222222 3333333 4444444 5555555 6666666 7777777)
}

search() {
  _GWT_QUERY=$1
  _gwt_refilter
}

_gwt_all
search 'flogin'
assert_rc "子序列可以跨過字元命中分支" 1 "$_GWT_COUNT"
assert_eq "命中的是 feature/login" '/repos/shop-feature-login' "${_GWT_PATHS[1]}"

_gwt_all
search 'shopfix'
assert_rc "目錄名稱也納入比對" 2 "$_GWT_COUNT"
assert_eq "連續命中排在跳字命中前面" '/repos/shop-fix-cart-bug' "${_GWT_PATHS[1]}"

_gwt_all
search 'cartbug'
assert_eq "目錄名稱可跨過連字號比對" '/repos/shop-fix-cart-bug' "${_GWT_PATHS[1]}"

_gwt_all
search 'marker'
assert_rc "不比對路徑中段" 0 "$_GWT_COUNT"

_gwt_all
search 'inner'
assert_rc "只比對最後一層目錄" 1 "$_GWT_COUNT"

_gwt_all
search 'alpha'
assert_eq "可以只靠分支名稱命中" '/repos/other' "${_GWT_PATHS[1]}"

_gwt_all
search 'fea login'
assert_rc "多個詞以 AND 串接" 1 "$_GWT_COUNT"
assert_eq "兩個詞分別命中分支與目錄" '/repos/shop-feature-login' "${_GWT_PATHS[1]}"

_gwt_all
search 'fea   login'
assert_rc "多餘空白不影響比對" 1 "$_GWT_COUNT"

_gwt_all
search 'FLOGIN'
assert_rc "預設不分大小寫" 1 "$_GWT_COUNT"

GWT_FILTER_CASE_INSENSITIVE=0
_gwt_all
search 'FLOGIN'
assert_rc "關閉不分大小寫後找不到" 0 "$_GWT_COUNT"
GWT_FILTER_CASE_INSENSITIVE=1

# 空白查詢要恢復完整清單，而且維持 Git 的原始順序
_gwt_all
search ''
assert_rc "空查詢顯示全部" 7 "$_GWT_COUNT"
assert_eq "空查詢維持原始順序" '/repos/shop' "${_GWT_PATHS[1]}"

# 連續命中的分數應該高於跳字命中
_gwt_fuzzy_match 'feature/login' 'shop-feature-login' 'login'
contiguous=$REPLY
_gwt_fuzzy_match 'feature/login' 'shop-feature-login' 'lgn'
gapped=$REPLY
(( contiguous > gapped ))
assert_rc "連續命中分數較高" 0 $?

t_report
