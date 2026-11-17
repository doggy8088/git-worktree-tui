#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 安裝 gwt 到 ~/.zsh/gwt.zsh，並在 ~/.zshrc 加入一行 source
#
# 用法：
#   bash install.sh              安裝（可重複執行，不會重複加行）
#   bash install.sh --uninstall  移除
#
# 環境變數：
#   GWT_INSTALL_DIR  安裝目錄（預設 ~/.zsh）
#   ZDOTDIR          zshrc 所在目錄（預設 ~）
#
# 只會動到 .zshrc 裡由本腳本產生的那一段（有明確的起訖註解），
# 其餘內容原封不動。
# -----------------------------------------------------------------------------
set -euo pipefail

src_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target_dir="${GWT_INSTALL_DIR:-$HOME/.zsh}"
target="$target_dir/gwt.zsh"
zshrc_dir="${ZDOTDIR:-$HOME}"
zshrc="$zshrc_dir/.zshrc"

begin_mark='# >>> gwt (git-worktree-tui) >>>'
end_mark='# <<< gwt (git-worktree-tui) <<<'

usage() {
  sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
}

remove_block() {
  [[ -f $zshrc ]] || return 0
  grep -qF "$begin_mark" "$zshrc" || return 0
  local tmp
  tmp=$(mktemp)
  awk -v b="$begin_mark" -v e="$end_mark" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$zshrc" >"$tmp"
  mv "$tmp" "$zshrc"
}

do_install() {
  mkdir -p "$target_dir"
  cp "$src_dir/gwt.zsh" "$target"
  printf '已複製函式庫到 %s\n' "$target"

  if grep -qF "$begin_mark" "$zshrc" 2>/dev/null; then
    printf '偵測到 %s 已經有 gwt 設定，更新內容\n' "$zshrc"
    remove_block
  fi

  mkdir -p "$zshrc_dir"
  {
    printf '%s\n' "$begin_mark"
    printf 'source %s\n' "$target"
    printf '%s\n' "$end_mark"
  } >>"$zshrc"

  printf '已在 %s 加入 source，重新開啟終端機或執行 source %s 後生效\n' "$zshrc" "$zshrc"
  printf '\n試試看：gwt --help\n'
}

do_uninstall() {
  remove_block
  printf '已從 %s 移除 gwt 設定\n' "$zshrc"
  if [[ -f $target ]]; then
    rm -f "$target"
    printf '已刪除 %s\n' "$target"
  fi
}

case "${1:-}" in
  '' | --install) do_install ;;
  --uninstall) do_uninstall ;;
  -h | --help) usage ;;
  *) printf '未知的參數：%s\n\n' "$1" >&2; usage >&2; exit 2 ;;
esac
