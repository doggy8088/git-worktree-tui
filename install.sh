#!/usr/bin/env bash
# =============================================================================
# gwt 安裝腳本
#
# 一行安裝：
#   curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash
#
# 指定版本：
#   curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash -s -- --version v0.1.0
#
# 在 cloned 的專案裡也可以直接跑（會用本地檔案，不連網）：
#   bash install.sh
#
# 移除：
#   curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash -s -- --uninstall
#
# 環境變數：
#   GWT_INSTALL_DIR  安裝目錄（預設 ~/.zsh）
#   ZDOTDIR          .zshrc 所在目錄（預設 ~）
# =============================================================================
set -euo pipefail

repo='doggy8088/git-worktree-tui'
version=''
install_dir="${GWT_INSTALL_DIR:-$HOME/.zsh}"
zshrc_dir="${ZDOTDIR:-$HOME}"
zshrc="$zshrc_dir/.zshrc"
target=''
mode='install'

begin_mark='# >>> gwt (git-worktree-tui) >>>'
end_mark='# <<< gwt (git-worktree-tui) <<<'

usage() {
  local self="${BASH_SOURCE[0]:-}"
  if [[ -n $self && -f $self ]]; then
    # 只印檔頭的註解區塊，遇到第一行程式碼就停
    awk 'NR == 1 { next }
         /^#/ { sub(/^# ?/, ""); print; next }
         { exit }' "$self" | awk '!/^=+$/'
    return
  fi
  cat <<'TEXT'
gwt 安裝腳本

  curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash
  ... | bash -s -- --version v0.1.0
  ... | bash -s -- --uninstall

環境變數：
  GWT_INSTALL_DIR  安裝目錄（預設 ~/.zsh）
  ZDOTDIR          .zshrc 所在目錄（預設 ~）
TEXT
}

say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() { printf '錯誤：%s\n' "$*" >&2; exit 1; }

parse_args() {
  while (($#)); do
    case "$1" in
      --version | -v)
        [[ $# -ge 2 ]] || die "$1 需要一個版本，例如 --version v0.1.0"
        version=$2
        shift 2
        ;;
      --version=*)
        version=${1#*=}
        shift
        ;;
      --dir)
        [[ $# -ge 2 ]] || die "--dir 需要一個路徑"
        install_dir=$2
        shift 2
        ;;
      --uninstall)
        mode='uninstall'
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "未知的參數：$1（用 --help 看用法）"
        ;;
    esac
  done
  target="$install_dir/gwt.zsh"
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

# 找出「不是本腳本管理」但也在載入 gwt 的行，提醒使用者避免重複定義
find_foreign_lines() {
  [[ -f $zshrc ]] || return 0
  awk -v b="$begin_mark" -v e="$end_mark" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip && /gwt\.zsh|gwt\.plugin\.zsh/ { print NR": "$0 }
  ' "$zshrc"
}

resolve_version() {
  if [[ -n $version ]]; then
    return 0
  fi
  local location=''
  location=$(curl -fsSI -o /dev/null -w '%{redirect_url}' \
    "https://github.com/$repo/releases/latest" 2>/dev/null || true)
  case "$location" in
    */tag/*) version=${location##*/} ;;
    *) version='main' ;;
  esac
}

download() {
  local ref=$1 dest=$2
  local raw="https://raw.githubusercontent.com/$repo/$ref/gwt.zsh"
  local cdn="https://cdn.jsdelivr.net/gh/$repo@$ref/gwt.zsh"

  if curl -fsSL --retry 2 --connect-timeout 10 "$raw" -o "$dest" 2>/dev/null; then
    return 0
  fi
  warn "raw.githubusercontent.com 取不到，改用 jsDelivr"
  curl -fsSL --retry 2 --connect-timeout 10 "$cdn" -o "$dest"
}

verify() {
  local file=$1
  grep -q 'GWT_VERSION' "$file" || die "下載到的內容不像 gwt.zsh，已中止"
  grep -q '_gwt_collect' "$file" || die "下載到的內容不完整，已中止"
}

installed_version() {
  sed -n "s/.*GWT_VERSION='\([^']*\)'.*/\1/p" "$1" | head -1
}

ensure_block() {
  mkdir -p "$zshrc_dir"
  if grep -qF "$begin_mark" "$zshrc" 2>/dev/null; then
    remove_block
  fi
  local source_path=$target
  case "$target" in
    "$HOME"/*) source_path='$HOME'"${target#"$HOME"}" ;;
  esac
  {
    printf '%s\n' "$begin_mark"
    printf 'source "%s"\n' "$source_path"
    printf '%s\n' "$end_mark"
  } >>"$zshrc"
}

do_install() {
  command -v curl >/dev/null 2>&1 || die "需要 curl，請先安裝"

  local tmp
  tmp=$(mktemp)

  # 在 cloned 的專案裡執行時，直接用本地檔案，不連網
  local self="${BASH_SOURCE[0]:-}"
  local src_dir=''
  if [[ -n $self && -f $self ]]; then
    src_dir=$(cd "$(dirname "$self")" && pwd)
  fi

  if [[ -n $src_dir && -f "$src_dir/gwt.zsh" ]]; then
    say "使用本地檔案：$src_dir/gwt.zsh"
    cp "$src_dir/gwt.zsh" "$tmp"
  else
    resolve_version
    say "下載 gwt（$version）…"
    download "$version" "$tmp"
  fi

  verify "$tmp"
  mkdir -p "$install_dir"
  mv "$tmp" "$target"
  chmod 0644 "$target"

  ensure_block

  say "已安裝到 $target（版本 $(installed_version "$target")）"
  say "已在 $zshrc 加入載入設定"

  local foreign=''
  foreign=$(find_foreign_lines)
  if [[ -n $foreign ]]; then
    warn ''
    warn '注意：.zshrc 裡還有其他載入 gwt 的設定，會造成重複定義，建議刪掉：'
    while IFS= read -r line; do warn "  $line"; done <<<"$foreign"
  fi

  say ''
  say "重新開啟終端機，或執行 source \"$zshrc\" 後就可以用："
  say '  gwt              # 互動式選單'
  say '  gwt --list       # 只印路徑'
  say '  gwt --help       # 全部選項'
}

do_uninstall() {
  remove_block
  say "已從 $zshrc 移除 gwt 設定"
  if [[ -f $target ]]; then
    rm -f "$target"
    say "已刪除 $target"
  fi
  rmdir "$install_dir" 2>/dev/null || true
}

parse_args "$@"
case "$mode" in
  install) do_install ;;
  uninstall) do_uninstall ;;
esac
