# =============================================================================
# gwt.zsh — Git Worktree 互動式切換工具
# =============================================================================
#
# 這是一份「被 source 的函式庫」，不是可直接執行的腳本，原因是：
# 獨立腳本會跑在子處理序裡，它執行 cd 只會改變子處理序自己的工作目錄，
# 不會影響呼叫它的終端機。只有載入到目前 shell 的函式才能真的切換目錄。
#
# 用法：
#   source gwt.zsh      # 或交給 zsh plugin manager 載入 gwt.plugin.zsh
#   gwt                 # 列出所有 worktree 並選擇
#   gwt feature         # 用關鍵字篩選
#
# 本檔的所有函式都以 _gwt_ 為前綴，狀態則放在 _GWT_ 開頭的變數裡，
# 唯一會進入使用者命名空間的只有 gwt 這一個函式。
#
# 注意：變數一律不使用 path 這個名字。在 zsh 裡小寫 path 陣列與大寫 PATH
# 環境變數是連動的，函式內宣告 local path="" 會把 PATH 清空，之後連 ls
# 都找不到指令。詳見 docs/design-notes.md。
# =============================================================================

typeset -g GWT_VERSION='0.1.0'

# -----------------------------------------------------------------------------
# 使用者設定（可在 source 之前 export，或 source 之後再改）
# -----------------------------------------------------------------------------
: ${GWT_LANG:='zh'}                     # 介面語言：zh / en
: ${GWT_CLEAR_ON_EXIT:=1}               # 選完後是否擦掉選單
: ${GWT_FILTER_CASE_INSENSITIVE:=1}     # 關鍵字比對是否不分大小寫
: ${GWT_DIGIT_TIMEOUT:=0.4}             # 多位數編號的等待秒數
: ${GWT_ESC_TIMEOUT:=0.05}              # 判斷單獨 Esc 與方向鍵的等待秒數
: ${GWT_NO_COLOR:=0}                    # 1 = 關閉所有顏色
: ${GWT_WIDTH:=0}                       # 選單寬度，0 = 自動偵測

# -----------------------------------------------------------------------------
# 介面文字
# -----------------------------------------------------------------------------
typeset -gA _GWT_M

_gwt_load_msgs() {
  _GWT_M=()
  case ${GWT_LANG:l} in
    en)
      _GWT_M[not_repo]='gwt: not inside a Git repository.'
      _GWT_M[no_match]='gwt: no worktree matched "%s".'
      _GWT_M[no_worktrees]='gwt: this repository has no other worktree.'
      _GWT_M[not_tty]='gwt: an interactive terminal is required.'
      _GWT_M[bad_opt]='gwt: unknown option: %s'
      _GWT_M[mark]='(current)'
      _GWT_M[detached]='detached'
      _GWT_M[header]='Select a worktree (↑/↓ move, Enter confirm, 1-%d jump, q/Esc cancel):'
      _GWT_HELP='Usage: gwt [options] [keyword]

Switch between all worktrees of the current Git repository by changing the
working directory of the shell you are in.

Options:
  -l, --list     only print matching worktree paths, one per line
  -h, --help     show this help
  -V, --version  show version

Keys:
  ↑/↓, k/j       move up and down (wraps around)
  1-9            jump to that number and switch immediately
  Enter          switch to the highlighted worktree
  q, Esc         cancel

Keyword: matched against "path + branch". When exactly one worktree matches,
         gwt switches to it directly without showing the menu.

Environment:
  GWT_LANG                     UI language (zh / en, default zh)
  GWT_CLEAR_ON_EXIT            erase the menu after leaving (1/0, default 1)
  GWT_FILTER_CASE_INSENSITIVE  case-insensitive keyword match (1/0, default 1)
  GWT_DIGIT_TIMEOUT            seconds to wait for a second digit (default 0.4)
  GWT_NO_COLOR                 disable colors (1/0, default 0)
  GWT_WIDTH                    menu width in columns (0 = auto)'
      ;;
    *)
      _GWT_M[not_repo]='gwt: 目前目錄不在 Git 儲存庫中。'
      _GWT_M[no_match]='gwt: 找不到符合「%s」的 worktree。'
      _GWT_M[no_worktrees]='gwt: 這個儲存庫沒有其他 worktree。'
      _GWT_M[not_tty]='gwt: 需要在互動式終端機中執行。'
      _GWT_M[bad_opt]='gwt: 未知的選項：%s'
      _GWT_M[mark]='(目前位置)'
      _GWT_M[detached]='detached'
      _GWT_M[header]='請選擇 Worktree (↑/↓ 移動, Enter 確認, 按 1-%d 直接跳轉, q/Esc 取消)：'
      _GWT_HELP='用法：gwt [選項] [關鍵字]

在目前 Git 儲存庫的所有 worktree 之間互動式切換，
直接改變目前這個 shell 的工作目錄。

選項：
  -l, --list     僅列出符合的 worktree 路徑（每行一筆）
  -h, --help     顯示本說明
  -V, --version  顯示版本

按鍵：
  ↑/↓, k/j       上下移動（到頭尾會循環）
  1-9            直接跳到該編號並切換，不需要按 Enter
  Enter          切換到反白的 worktree
  q, Esc         取消

關鍵字：比對「路徑 + 分支名稱」整串文字。
        只有一筆符合時，不顯示選單，直接切換過去。

環境變數：
  GWT_LANG                    介面語言（zh / en，預設 zh）
  GWT_CLEAR_ON_EXIT           選完後擦掉選單（1/0，預設 1）
  GWT_FILTER_CASE_INSENSITIVE 關鍵字不分大小寫（1/0，預設 1）
  GWT_DIGIT_TIMEOUT           多位數編號的等待秒數（預設 0.4）
  GWT_ESC_TIMEOUT             判斷單獨 Esc 的等待秒數（預設 0.05）
  GWT_NO_COLOR                關閉顏色（1/0，預設 0）
  GWT_WIDTH                   選單寬度（0 = 自動偵測）'
      ;;
  esac
}

# -----------------------------------------------------------------------------
# 狀態
# -----------------------------------------------------------------------------
typeset -ga _GWT_PATHS _GWT_BRANCHES _GWT_HEADS
typeset -gi _GWT_COUNT=0 _GWT_SELECTED=0 _GWT_DRAWN=0 _GWT_WIDTH=80 _GWT_SW=0
typeset -g  _GWT_CURRENT='' _GWT_PENDING_KEY=''
typeset -gi _GWT_INTERRUPTED=0
typeset -g  _GWT_S_RESET='' _GWT_S_BAR='' _GWT_S_BRANCH='' _GWT_S_MARK=''

_gwt_reset_state() {
  _GWT_PATHS=()
  _GWT_BRANCHES=()
  _GWT_HEADS=()
  _GWT_COUNT=0
  _GWT_SELECTED=0
  _GWT_DRAWN=0
  _GWT_CURRENT=''
  _GWT_PENDING_KEY=''
  _GWT_INTERRUPTED=0
}

# -----------------------------------------------------------------------------
# 寬度計算：ANSI 跳脫序列不佔欄寬，CJK 全形字佔兩欄
# -----------------------------------------------------------------------------
# 去掉 \e[...m 形式的 SGR 序列，結果放在 REPLY。分支名稱可能含有反斜線或
# 百分比符號，這裡只做字串比對，不會把內容當成 printf 格式或 %b 解讀。
_gwt_strip_ansi() {
  local s=$1
  local out=''
  while [[ $s == *$'\e['* ]]; do
    out+=${s%%$'\e['*}
    s=${s#*$'\e['}
    s=${s#*m}
  done
  REPLY="$out$s"
}

# 計算字串在終端機上的欄寬，結果放在 _GWT_SW。
_gwt_swidth() {
  local s=$1 c
  local -i i n=${#1} w=0
  for (( i = 1; i <= n; i++ )); do
    c=${s[i]}
    if [[ $c == [$'\u1100'-$'\u115f'] || $c == [$'\u2e80'-$'\ua4cf'] ||
          $c == [$'\uac00'-$'\ud7a3'] || $c == [$'\uf900'-$'\ufaff'] ||
          $c == [$'\uFE30'-$'\uFE4F'] || $c == [$'\uff00'-$'\uff60'] ||
          $c == [$'\uffe0'-$'\uffe6'] ]]; then
      (( w += 2 ))
    else
      (( w += 1 ))
    fi
  done
  _GWT_SW=$w
}

# 計算「已上色字串」的欄寬，結果放在 _GWT_SW。
_gwt_width_of() {
  _gwt_strip_ansi "$1"
  _gwt_swidth "$REPLY"
}

# 把過長的字串從中截斷成 budget 欄寬，結果放在 REPLY。
_gwt_clip_middle() {
  local s=$1
  local -i budget=$2 n=${#1} i w keep tailw headw
  _gwt_swidth "$s"
  if (( _GWT_SW <= budget )); then
    REPLY=$s
    return 0
  fi
  if (( budget < 3 )); then
    REPLY='…'
    return 0
  fi
  keep=$(( budget - 1 ))
  tailw=$(( keep * 2 / 3 ))
  headw=$(( keep - tailw ))
  local head='' tail=''
  for (( i = 1; i <= n; i++ )); do
    _gwt_swidth "${s[i]}"
    w=$_GWT_SW
    (( w > headw )) && break
    head+=${s[i]}
    (( headw -= w ))
  done
  for (( i = n; i >= 1; i-- )); do
    _gwt_swidth "${s[i]}"
    w=$_GWT_SW
    (( w > tailw )) && break
    tail=${s[i]}$tail
    (( tailw -= w ))
  done
  REPLY="${head}…${tail}"
}

_gwt_init_width() {
  local -i w=${GWT_WIDTH:-0}
  if (( w <= 0 )); then
    if [[ -t 1 ]]; then
      w=${COLUMNS:-0}
      if (( w <= 0 )); then
        w=$(tput cols 2>/dev/null)
        [[ $w == <-> ]] || w=0
      fi
    fi
    (( w <= 0 )) && w=80
  fi
  # 多留一欄，避免最後一欄剛好觸發終端機自動換行
  w=$(( w - 1 ))
  (( w < 24 )) && w=24
  _GWT_WIDTH=$w
}

_gwt_init_style() {
  local -i use=1
  (( ${GWT_NO_COLOR:-0} )) && use=0
  [[ -n ${NO_COLOR-} ]] && use=0
  (( use )) && [[ ! -t 1 ]] && use=0
  if (( use )); then
    _GWT_S_RESET=$'\e[0m'
    _GWT_S_BAR=$'\e[1;30;46m'      # 粗體 + 黑字 + 青色底：選取光棒
    _GWT_S_BRANCH=$'\e[36m'        # 青色：分支名稱
    _GWT_S_MARK=$'\e[33m'          # 黃色：目前位置
  else
    _GWT_S_RESET=''
    _GWT_S_BAR=''
    _GWT_S_BRANCH=''
    _GWT_S_MARK=''
  fi
}

# -----------------------------------------------------------------------------
# 解析 git worktree list --porcelain
# -----------------------------------------------------------------------------
# 每個 worktree 是一組以空行分隔的資料：
#   worktree /path/to/shop
#   HEAD 89ae97a...
#   branch refs/heads/main        （detached HEAD 時改為一行 detached）
# 用 case 逐行比對前綴，遇到空行才把這一組收進陣列，所以路徑含空白也不會被切開。
_gwt_collect() {
  local keyword=$1 line='' wt_path='' head='' branch=''
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      'worktree '*) wt_path=${line#worktree } ;;
      'HEAD '*)     head=${line#HEAD } ;;
      'branch '*)   branch=${line#branch refs/heads/} ;;
      'detached')   branch=${_GWT_M[detached]} ;;
      'locked'*|'prunable'*|'bare')  ;;   # 附註行，目前不影響選單
      '')
        if [[ -n $wt_path ]]; then
          _gwt_collect_one "$keyword" "$wt_path" "$branch" "$head"
        fi
        wt_path=''; head=''; branch=''
        ;;
    esac
  done
  _GWT_COUNT=${#_GWT_PATHS}
}

_gwt_collect_one() {
  local keyword=$1 wt_path=$2 branch=$3 head=$4
  if [[ -n $keyword ]]; then
    local hay="$wt_path $branch"
    if (( ${GWT_FILTER_CASE_INSENSITIVE:-1} )); then
      hay=${(L)hay}
      # 關鍵字放在雙引號裡，因此 * ? [ 等字元都只當普通文字比對
      [[ $hay == *"${(L)keyword}"* ]] || return 0
    else
      [[ $hay == *"$keyword"* ]] || return 0
    fi
  fi
  _GWT_PATHS+=("$wt_path")
  _GWT_BRANCHES+=("$branch")
  _GWT_HEADS+=("${head[1,7]}")
}

# -----------------------------------------------------------------------------
# 畫面
# -----------------------------------------------------------------------------
# 產生第 i 列的文字，結果放在 REPLY。
# 光棒只反白到路徑為止，分支與狀態維持原色，方便一眼辨識。
_gwt_format_row() {
  local -i i=$1 sel=0
  (( i == _GWT_SELECTED )) && sel=1

  local wt_path=${_GWT_PATHS[i]}
  local branch=${_GWT_BRANCHES[i]}
  local head=${_GWT_HEADS[i]}
  local prefix

  if (( sel )); then
    prefix=" > [$i] "
  else
    prefix="   [$i] "
  fi

  local suffix=" ${_GWT_S_BRANCH}[${branch}]${_GWT_S_RESET} (${head})"
  if [[ -n $_GWT_CURRENT && ${wt_path:A} == ${_GWT_CURRENT:A} ]]; then
    suffix+=" ${_GWT_S_MARK}${_GWT_M[mark]}${_GWT_S_RESET}"
  fi

  # 可用於路徑的欄寬 = 總寬 - 編號前綴 - 後方分支資訊
  local -i avail=$(( _GWT_WIDTH - ${#prefix} - 2 ))
  _gwt_width_of "$suffix"
  avail=$(( avail - _GWT_SW ))
  (( avail < 12 )) && avail=12

  _gwt_clip_middle "$wt_path" "$avail"
  local shown=$REPLY

  if (( sel )); then
    REPLY="${_GWT_S_BAR}${prefix}${shown} ${_GWT_S_RESET}${suffix}"
  else
    REPLY="${prefix}${shown}  ${suffix}"
  fi
}

_gwt_draw() {
  local -i i
  for (( i = 1; i <= _GWT_COUNT; i++ )); do
    printf '\r\e[2K'
    _gwt_format_row "$i"
    printf '%s\n' "$REPLY"
  done
  _GWT_DRAWN=$(( _GWT_COUNT + 1 ))
}

# 收尾：移除 trap、視需要擦掉選單、把游標還給使用者。
# 不論是 Enter、數字鍵、q/Esc、Ctrl+C 或讀不到輸入，都必須經過這裡。
_gwt_finish() {
  trap - INT TERM
  if (( ${GWT_CLEAR_ON_EXIT:-1} )); then
    printf '\e[%dA\e[J' "$_GWT_DRAWN"
  fi
  printf '\e[?25h'
}

_gwt_shift() {
  local -i d=$1
  _GWT_SELECTED=$(( _GWT_SELECTED + d ))
  if (( _GWT_SELECTED > _GWT_COUNT )); then
    _GWT_SELECTED=1
  elif (( _GWT_SELECTED < 1 )); then
    _GWT_SELECTED=$_GWT_COUNT
  fi
}

# 數字鍵：worktree 超過 9 個時，再等一小段時間看是否還有第二位數字。
# 例如清單有 12 筆時，按 1 再按 2 會跳到第 12 筆；只按 1 則等 timeout 後跳第 1 筆。
# 若等待期間收到的是其他按鍵（例如 j），就交回主迴圈處理，不會被吃掉。
_gwt_pick_number() {
  local digits=$1 more=''
  local -i maxlen=${#_GWT_COUNT}
  if (( _GWT_COUNT > 9 )); then
    while (( ${#digits} < maxlen )); do
      if ! read -r -k 1 -s -t "${GWT_DIGIT_TIMEOUT:-0.4}" more; then
        break
      fi
      if [[ $more == [0-9] ]]; then
        digits="${digits}${more}"
        (( 10#$digits * 10 > _GWT_COUNT )) && break
      else
        [[ -n $more ]] && _GWT_PENDING_KEY=$more
        break
      fi
    done
  fi
  _GWT_SELECTED=$(( 10#$digits ))
}

# 互動式選單。成功選定時回傳 0，取消或中斷時回傳非 0。
_gwt_pick() {
  local key='' rest=''
  _GWT_SELECTED=1
  _GWT_PENDING_KEY=''
  _gwt_init_width
  _gwt_init_style

  # 選單顯示期間隱藏游標；trap 保證中斷時游標與終端狀態都會復原。
  # 這裡除了清理，還要把 _GWT_INTERRUPTED 標起來：zsh 在 trap 裡執行 return
  # 時，回傳值不見得會傳到呼叫端（實測可能變成 0 或 1），所以 gwt 最後一律
  # 以這個旗標決定要不要回傳 130，不依賴 trap 的 return 值。
  printf '\e[?25l'
  trap '_GWT_INTERRUPTED=1; _gwt_finish; return 130' INT TERM

  printf "${_GWT_M[header]}\n" "$_GWT_COUNT"
  _gwt_draw

  while true; do
    if [[ -n $_GWT_PENDING_KEY ]]; then
      key=$_GWT_PENDING_KEY
      _GWT_PENDING_KEY=''
    elif ! read -r -k 1 -s key; then
      _gwt_finish
      return 1
    fi

    case $key in
      $'\e')
        rest=''
        read -r -k 2 -s -t "${GWT_ESC_TIMEOUT:-0.05}" rest
        case $rest in
          '[A'|'OA') _gwt_shift -1 ;;
          '[B'|'OB') _gwt_shift 1 ;;
          '')        _gwt_finish; return 1 ;;   # 單獨一個 Esc = 取消
          *)         ;;                         # 其他跳脫序列：忽略
        esac
        ;;
      $'\x03')                                 # Ctrl+C（未轉成 SIGINT 時）
        _GWT_INTERRUPTED=1
        _gwt_finish
        return 130
        ;;
      k|K) _gwt_shift -1 ;;
      j|J) _gwt_shift 1 ;;
      $'\n'|$'\r')
        _gwt_finish
        return 0
        ;;
      [1-9])
        _gwt_pick_number "$key"
        if (( _GWT_SELECTED >= 1 && _GWT_SELECTED <= _GWT_COUNT )); then
          _gwt_finish
          return 0
        fi
        ;;
      q|Q)
        _gwt_finish
        return 1
        ;;
    esac

    # 回到選單第一列重畫
    printf '\e[%dA' "$_GWT_COUNT"
    _gwt_draw
  done
}

# -----------------------------------------------------------------------------
# 主函式
# -----------------------------------------------------------------------------
gwt() {
  emulate -L zsh
  setopt local_options no_nomatch

  _gwt_load_msgs
  _gwt_reset_state

  local mode=pick arg=''
  local keyword=''
  local -a keywords=()

  while (( $# )); do
    arg=$1
    case $arg in
      -h|--help)    printf '%s\n' "$_GWT_HELP"; return 0 ;;
      -V|--version) printf 'gwt %s\n' "$GWT_VERSION"; return 0 ;;
      -l|--list)    mode=list; shift ;;
      --)           shift; keywords+=("$@"); break ;;
      -?*)
        printf "${_GWT_M[bad_opt]}\n" "$arg" >&2
        printf '%s\n' "$_GWT_HELP" >&2
        return 2
        ;;
      *)            keywords+=("$arg"); shift ;;
    esac
  done

  (( ${#keywords} )) && keyword="${(j: :)keywords}"

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s\n' "${_GWT_M[not_repo]}" >&2
    return 1
  fi

  # 目前所在的 worktree；bare repo 沒有工作目錄，此時為空字串
  _GWT_CURRENT=$(git rev-parse --show-toplevel 2>/dev/null)

  # 用 process substitution 讀 porcelain，最後補一個換行，
  # 確保最後一組資料一定以空行結尾而被收進陣列。
  _gwt_collect "$keyword" < <(git worktree list --porcelain 2>/dev/null; printf '\n')

  if (( _GWT_COUNT == 0 )); then
    if [[ -n $keyword ]]; then
      printf "${_GWT_M[no_match]}\n" "$keyword" >&2
    else
      printf '%s\n' "${_GWT_M[no_worktrees]}" >&2
    fi
    return 1
  fi

  if [[ $mode == list ]]; then
    local p
    for p in "${_GWT_PATHS[@]}"; do
      printf '%s\n' "$p"
    done
    return 0
  fi

  # 只有一筆符合時不顯示選單，直接切換
  if (( _GWT_COUNT == 1 )); then
    builtin cd -- "${_GWT_PATHS[1]}" || return 1
    return 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    printf '%s\n' "${_GWT_M[not_tty]}" >&2
    return 1
  fi

  _gwt_pick
  local rc=$?
  # Ctrl+C：無論 trap 的 return 值是什麼，一律以 130（被中斷）回報
  (( _GWT_INTERRUPTED )) && return 130
  (( rc != 0 )) && return $rc

  if (( _GWT_SELECTED < 1 || _GWT_SELECTED > _GWT_COUNT )); then
    return 1
  fi

  builtin cd -- "${_GWT_PATHS[_GWT_SELECTED]}" || return 1
  return 0
}
