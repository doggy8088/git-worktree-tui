#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 建立一個示範用的多 worktree 儲存庫，方便實際玩一次 gwt
#
# 用法：
#   bash scripts/demo.sh             建在 $TMPDIR/gwt-demo
#   bash scripts/demo.sh <路徑>      建在指定路徑（該路徑必須不存在）
# -----------------------------------------------------------------------------
set -euo pipefail

target=${1:-}
if [[ -z $target ]]; then
  target=$(mktemp -d "${TMPDIR:-/tmp}/gwt-demo.XXXXXX")/shop
  mkdir -p "$target"
elif [[ -e $target ]]; then
  printf '路徑已存在，請換一個：%s\n' "$target" >&2
  exit 1
fi

root=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$root.gitconfig"
export GIT_AUTHOR_NAME='gwt demo'
export GIT_AUTHOR_EMAIL='demo@example.com'
export GIT_COMMITTER_NAME='gwt demo'
export GIT_COMMITTER_EMAIL='demo@example.com'

git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

git init -q "$root"
printf 'demo\n' >"$root/README.md"
git -C "$root" add README.md
git -C "$root" commit -q -m 'init'

git -C "$root" worktree add -q "$root-feature-login" -b feature/login
git -C "$root" worktree add -q "$root-feature-search-api" -b feature/search-api
git -C "$root" worktree add -q "$root-fix-cart-bug" -b fix/cart-bug
git -C "$root" worktree add -q --detach "$root-hotfix"

printf '\n示範儲存庫建好了：%s\n\n' "$root"
git -C "$root" worktree list
printf '\n試試看：\n'
printf '  cd %s\n' "$root"
printf '  gwt              # 互動式選單\n'
printf '  gwt feature      # 關鍵字篩選\n'
printf '  gwt --list       # 只印路徑\n'
