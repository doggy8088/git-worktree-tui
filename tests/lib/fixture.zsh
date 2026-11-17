# -----------------------------------------------------------------------------
# 讀取測試 fixture 內容的小工具
#
# 測試不要硬寫「第 3 筆是 shop-feature-login」這種假設，因為 worktree 的排序
# 由 Git 決定。這裡一律從 git worktree list --porcelain 取得順序，讓測試只
# 驗證「選了第 N 筆就會 cd 到第 N 筆」這件真正想驗的事。
# -----------------------------------------------------------------------------

# fixture_path <儲存庫路徑> <第幾筆，從 1 開始>
fixture_path() {
  local repo=$1 idx=$2
  local -a paths
  paths=("${(@f)$(git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p')}")
  print -r -- "${paths[idx]}"
}

# fixture_count <儲存庫路徑>
fixture_count() {
  local repo=$1
  local -a paths
  paths=("${(@f)$(git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p')}")
  print -r -- "${#paths}"
}

# 依路徑片段找出 worktree 的完整路徑（找不到就回傳空字串）
fixture_path_matching() {
  local repo=$1 fragment=$2
  git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p' | grep -F -- "$fragment" | head -1
}
