#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 建立測試用的 Git 儲存庫
#
# 用法：build.sh <空目錄>
#
# 會產生底下幾個 fixture，讓測試可以覆蓋各種邊界：
#   shop/       主 worktree + 4 個 worktree（含路徑有空白、含 detached HEAD）
#   twelve/     主 worktree + 11 個 worktree（驗證多位數編號）
#   many/       40 個 worktree（驗證選單視窗化，清單比終端機高）
#   longname/   分支與目錄名都很長（驗證每一列都不會折行）
#   plain/      只有一個 worktree 的儲存庫
#   outside/    不是 Git 儲存庫的目錄
#
# 為了讓 commit hash 與測試結果可重現，這裡固定作者與日期，並使用獨立的
# git config，不去動使用者原本的全域設定。
# -----------------------------------------------------------------------------
set -euo pipefail

root=${1:?用法: build.sh <空目錄>}
mkdir -p "$root"

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$root/gitconfig"
export GIT_AUTHOR_NAME='gwt test'
export GIT_AUTHOR_EMAIL='gwt@example.com'
export GIT_COMMITTER_NAME='gwt test'
export GIT_COMMITTER_EMAIL='gwt@example.com'
export GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000'
export GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000'

git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath /dev/null

# ---- shop：5 個 worktree，含路徑空白與 detached HEAD ------------------------
git init -q "$root/shop"
git -C "$root/shop" commit -q --allow-empty -m 'init'
git -C "$root/shop" worktree add -q "$root/shop-feature-login" -b feature/login
git -C "$root/shop" worktree add -q "$root/shop-feature search api" -b feature/search-api
git -C "$root/shop" worktree add -q "$root/shop-fix-cart-bug" -b fix/cart-bug
git -C "$root/shop" worktree add -q --detach "$root/shop-hotfix"

# ---- twelve：12 個 worktree -------------------------------------------------
git init -q "$root/twelve"
git -C "$root/twelve" commit -q --allow-empty -m 'init'
for i in $(seq -w 1 11); do
  git -C "$root/twelve" worktree add -q "$root/twelve-w$i" -b "w$i"
done

# ---- many：40 個 worktree ---------------------------------------------------
git init -q "$root/many"
git -C "$root/many" commit -q --allow-empty -m 'init'
for i in $(seq -w 1 39); do
  git -C "$root/many" worktree add -q "$root/many-w$i" -b "m$i"
done

# ---- longname：超長分支名與超長目錄名 ---------------------------------------
git init -q "$root/longname"
git -C "$root/longname" commit -q --allow-empty -m 'init'
git -C "$root/longname" worktree add -q \
  "$root/longname-a-very-long-worktree-directory-name-used-for-testing" \
  -b "feature/this-is-a-deliberately-long-branch-name"

# ---- plain：只有一個 worktree ----------------------------------------------
git init -q "$root/plain"
git -C "$root/plain" commit -q --allow-empty -m 'init'

# ---- outside：不是 Git 儲存庫 ----------------------------------------------
mkdir -p "$root/outside"
