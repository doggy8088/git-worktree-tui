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

typeset -g GWT_VERSION='0.2.1'

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
: ${GWT_HEIGHT:=0}                      # 選單可用高度，0 = 自動偵測

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
      _GWT_M[header]='Select a worktree (↑/↓ move, Enter confirm, / search, 1-%d jump, q/Esc cancel):'
      _GWT_M[search]='Search: %s▏  %d match(es) (↑/↓ move, Enter confirm, Esc clear):'
      _GWT_M[search_none]='No worktree matches this search.'
      _GWT_M[range]='showing %d-%d of %d'
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
  /              fuzzy search branch names and the last path component
  Enter          switch to the highlighted worktree
  q, Esc         cancel

While searching, ↑/↓ still move, Enter still confirms, and Esc clears the
search instead of cancelling the menu. Backspace edits the query, Ctrl+U
clears it, and Ctrl+W deletes the last word.

Keyword: matched against "path + branch". When exactly one worktree matches,
         gwt switches to it directly without showing the menu.

Environment:
  GWT_LANG                     UI language (zh / en, default zh)
  GWT_CLEAR_ON_EXIT            erase the menu after leaving (1/0, default 1)
  GWT_FILTER_CASE_INSENSITIVE  case-insensitive keyword match (1/0, default 1)
  GWT_DIGIT_TIMEOUT            seconds to wait for a second digit (default 0.4)
  GWT_NO_COLOR                 disable colors (1/0, default 0)
  GWT_WIDTH                    menu width in columns (0 = auto)
  GWT_HEIGHT                   menu height in rows (0 = auto; a shorter
                               list is shown in a scrolling window)'
      ;;
    *)
      _GWT_M[not_repo]='gwt: 目前目錄不在 Git 儲存庫中。'
      _GWT_M[no_match]='gwt: 找不到符合「%s」的 worktree。'
      _GWT_M[no_worktrees]='gwt: 這個儲存庫沒有其他 worktree。'
      _GWT_M[not_tty]='gwt: 需要在互動式終端機中執行。'
      _GWT_M[bad_opt]='gwt: 未知的選項：%s'
      _GWT_M[mark]='(目前位置)'
      _GWT_M[detached]='detached'
      _GWT_M[header]='請選擇 Worktree (↑/↓ 移動, Enter 確認, / 搜尋, 按 1-%d 直接跳轉, q/Esc 取消)：'
      _GWT_M[search]='搜尋：%s▏  %d 筆符合 (↑/↓ 移動, Enter 確認, Esc 清除搜尋)：'
      _GWT_M[search_none]='沒有符合搜尋條件的 worktree。'
      _GWT_M[range]='顯示 %d-%d，共 %d 筆'
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
  /              模糊搜尋分支名稱與目錄名稱（只比對路徑的最後一層）
  Enter          切換到反白的 worktree
  q, Esc         取消

搜尋模式中 ↑/↓ 仍可移動、Enter 仍可確認，Esc 改為清除搜尋（不會直接取消
選單）。Backspace 刪除一個字元，Ctrl+U 清空，Ctrl+W 刪除最後一個詞。

關鍵字：比對「路徑 + 分支名稱」整串文字。
        只有一筆符合時，不顯示選單，直接切換過去。

環境變數：
  GWT_LANG                    介面語言（zh / en，預設 zh）
  GWT_CLEAR_ON_EXIT           選完後擦掉選單（1/0，預設 1）
  GWT_FILTER_CASE_INSENSITIVE 關鍵字不分大小寫（1/0，預設 1）
  GWT_DIGIT_TIMEOUT           多位數編號的等待秒數（預設 0.4）
  GWT_ESC_TIMEOUT             判斷單獨 Esc 的等待秒數（預設 0.05）
  GWT_NO_COLOR                關閉顏色（1/0，預設 0）
  GWT_WIDTH                   選單寬度（0 = 自動偵測）
  GWT_HEIGHT                  選單可用高度（0 = 自動偵測，
                              清單較高時只顯示一個會捲動的視窗）'
      ;;
  esac
}

# -----------------------------------------------------------------------------
# 狀態
# -----------------------------------------------------------------------------
typeset -ga _GWT_PATHS _GWT_BRANCHES _GWT_HEADS
# 完整候選清單（已套用命令列關鍵字），互動搜尋時從這裡重新篩選
typeset -ga _GWT_ALL_PATHS _GWT_ALL_BRANCHES _GWT_ALL_HEADS
typeset -gi _GWT_COUNT=0 _GWT_SELECTED=0 _GWT_DRAWN=0 _GWT_WIDTH=80 _GWT_SW=0
typeset -gi _GWT_HEIGHT=24 _GWT_VISIBLE=0 _GWT_TOP=1 _GWT_SCROLLED=0
typeset -gi _GWT_SEARCH=0
typeset -g  _GWT_CURRENT='' _GWT_PENDING_KEY='' _GWT_QUERY='' _GWT_ESC_KIND=''
typeset -gi _GWT_INTERRUPTED=0
typeset -g  _GWT_S_RESET='' _GWT_S_BAR='' _GWT_S_BRANCH='' _GWT_S_MARK='' _GWT_S_DIM=''

_gwt_reset_state() {
  _GWT_PATHS=()
  _GWT_BRANCHES=()
  _GWT_HEADS=()
  _GWT_ALL_PATHS=()
  _GWT_ALL_BRANCHES=()
  _GWT_ALL_HEADS=()
  _GWT_COUNT=0
  _GWT_SELECTED=0
  _GWT_DRAWN=0
  _GWT_HEIGHT=24
  _GWT_VISIBLE=0
  _GWT_TOP=1
  _GWT_SCROLLED=0
  _GWT_SEARCH=0
  _GWT_CURRENT=''
  _GWT_PENDING_KEY=''
  _GWT_QUERY=''
  _GWT_ESC_KIND=''
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

# 寬度為 2 的「基本多文種平面」字元：Unicode 的 East Asian Width 是 W（Wide）或 F（Fullwidth）。
# 不只 CJK：⚡ ⌚ ✅ ⭐ 這類 emoji 符號也在基本多文種平面、也佔 2 欄；只有 CJK 範圍的表會把它們當成
# 1 欄，一列就比算出來的寬而折行，重繪與收尾的列數對不上。
# 這張表與 gwt.psm1 的 $script:WideBmp 逐字相同（由它機械轉換而來，改一邊就要改另一邊）。
# 注意 U+303F 夾在 CJK 範圍中間卻是窄的，所以那一段是 U+2E80–U+303E 與 U+3041–U+A4CF 兩段。
typeset -g _GWT_WIDE=$'[\u1100-\u115f\u231a\u231b\u2329\u232a\u23e9-\u23ec\u23f0\u23f3\u25fd\u25fe\u2614\u2615\u2648-\u2653\u267f\u2693\u26a1\u26aa\u26ab\u26bd\u26be\u26c4\u26c5\u26ce\u26d4\u26ea\u26f2\u26f3\u26f5\u26fa\u26fd\u2705\u270a\u270b\u2728\u274c\u274e\u2753-\u2755\u2757\u2795-\u2797\u27b0\u27bf\u2b1b\u2b1c\u2b50\u2b55\u2e80-\u303e\u3041-\ua4cf\ua960-\ua97f\uac00-\ud7a3\uf900-\ufaff\ufe10-\ufe19\ufe30-\ufe6f\uff00-\uff60\uffe0-\uffe6]'
# 基本多文種平面以外（🔥 等 emoji、CJK 擴充區）一律算 2 欄，與 PowerShell 版相同。
typeset -g _GWT_ASTRAL=$'[\U00010000-\U0010ffff]'

# 計算字串在終端機上的欄寬，結果放在 _GWT_SW。
# 測試對照逐字寫死的 Unicode 標準答案（tests/pwsh/lib/WidthOracle.ps1，與 PowerShell 版共用）。
_gwt_swidth() {
  local s=$1 c
  # 全是 ASCII（最常見）就不必逐字比對
  if [[ $s != *[^$'\x01'-$'\x7f']* ]]; then
    _GWT_SW=${#s}
    return 0
  fi
  local -i i n=${#1} w=0
  for (( i = 1; i <= n; i++ )); do
    c=${s[i]}
    if [[ $c == ${~_GWT_WIDE} || $c == ${~_GWT_ASTRAL} ]]; then
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

# 高度與寬度一起量。這裡用 stty size 而不是 COLUMNS/LINES，因為環境變數
# 可能過期（例如在 tmux 裡換了 pane 大小），而 stty size 直接問終端機。
_gwt_init_size() {
  local -i h=${GWT_HEIGHT:-0} w=${GWT_WIDTH:-0}
  local -a parts=()
  if (( h <= 0 || w <= 0 )) && [[ -t 1 ]]; then
    parts=(${=$(stty size 2>/dev/null)})
  fi
  if (( h <= 0 )); then
    [[ ${parts[1]:-} == <-> ]] && h=$parts[1]
    (( h <= 0 )) && h=${LINES:-0}
    (( h <= 0 )) && h=24
  fi
  if (( w <= 0 )); then
    [[ ${parts[2]:-} == <-> ]] && w=$parts[2]
    (( w <= 0 )) && w=${COLUMNS:-0}
    (( w <= 0 )) && w=80
  fi
  (( h < 6 )) && h=6
  # 多留一欄，避免最後一欄剛好觸發終端機自動換行。
  # 下限 16（17 欄的終端機），與 PowerShell 版相同：再窄，連「編號 + 最短的路徑」都放不下，只能折行。
  # 放不下完整的後方資訊時由 _gwt_format_row 依序省略 commit、分支，所以 17～25 欄也不會折行。
  w=$(( w - 1 ))
  (( w < 16 )) && w=16
  _GWT_HEIGHT=$h
  _GWT_WIDTH=$w
}

# 決定這次要畫哪幾列。重點：表頭 + 可視列 + 提示列 + 游標那一列，
# 加起來不能超過終端機高度，否則終端機會上捲，而「游標往上 N 行」
# 在畫面頂端會被夾住，重繪就整個錯位。
_gwt_layout() {
  local -i avail max_top
  if (( _GWT_COUNT + 2 <= _GWT_HEIGHT )); then
    _GWT_VISIBLE=$_GWT_COUNT
    _GWT_SCROLLED=0
  else
    avail=$(( _GWT_HEIGHT - 3 ))     # 表頭 1 + 提示列 1 + 游標那一列 1
    (( avail < 1 )) && avail=1
    _GWT_VISIBLE=$avail
    _GWT_SCROLLED=1
  fi

  # 讓選取項目永遠留在可視範圍內
  if (( _GWT_SELECTED < _GWT_TOP )); then
    _GWT_TOP=$_GWT_SELECTED
  elif (( _GWT_SELECTED > _GWT_TOP + _GWT_VISIBLE - 1 )); then
    _GWT_TOP=$(( _GWT_SELECTED - _GWT_VISIBLE + 1 ))
  fi
  (( _GWT_TOP < 1 )) && _GWT_TOP=1
  max_top=$(( _GWT_COUNT - _GWT_VISIBLE + 1 ))
  (( max_top < 1 )) && max_top=1
  (( _GWT_TOP > max_top )) && _GWT_TOP=$max_top
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
    _GWT_S_DIM=$'\e[2m'            # 暗色：顯示範圍提示
  else
    _GWT_S_RESET=''
    _GWT_S_BAR=''
    _GWT_S_BRANCH=''
    _GWT_S_MARK=''
    _GWT_S_DIM=''
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
# 模糊搜尋
# -----------------------------------------------------------------------------
# 互動搜尋只比對「分支名稱」與「路徑的最後一層目錄」，不比對完整路徑，
# 避免 /Users/... 這種共同前綴讓每一筆都符合。
#
# 比對方式是子序列（subsequence）：查詢字元依序出現在候選字串裡就算符合，
# 所以 "flogin" 可以找到 feature/login。分數用來排序，規則大致是：
#   - 連續命中的加成最高（越長越好）
#   - 命中在字首或分隔符（/ - _ . 空白）之後額外加分
#   - 跳過太多字元要扣分，候選字串越長也會被小幅扣分

# 單一詞彙比對。符合時 REPLY 放分數並回傳 0，不符合回傳 1。
_gwt_fuzzy_term() {
  local hay=$1 term=$2
  if (( ${GWT_FILTER_CASE_INSENSITIVE:-1} )); then
    hay=${(L)hay}
    term=${(L)term}
  fi

  local -i hl=${#hay} tl=${#term}
  REPLY=0
  (( tl == 0 )) && return 0

  local -i hi=1 ti=1 score=0 last=0 run=0 skipped=0
  local ch prev
  while (( ti <= tl )); do
    ch=${term[ti]}
    while (( hi <= hl )) && [[ ${hay[hi]} != "$ch" ]]; do
      (( hi++ ))
    done
    if (( hi > hl )); then
      REPLY=0
      return 1
    fi

    (( score += 10 ))
    if (( last > 0 )); then
      if (( hi == last + 1 )); then
        (( run++ ))
        (( score += 6 + run * 2 ))
      else
        (( run = 0 ))
        (( skipped = hi - last - 1 ))
        # 中間跳過的字元越多越不像，但最多只扣 4 分，避免長名稱永遠排最後
        (( score -= skipped > 4 ? 4 : skipped ))
      fi
    fi

    if (( hi == 1 )); then
      (( score += 14 ))
    else
      prev=${hay[hi-1]}
      case $prev in
        '/'|'-'|'_'|'.'|' ') (( score += 10 )) ;;
      esac
    fi

    last=$hi
    (( hi++ ))
    (( ti++ ))
  done

  # 候選字串越長，同樣的命中越不精確
  (( score -= hl / 5 ))
  REPLY=$score
  return 0
}

# 整串查詢比對：以空白切成多個詞，每個詞都必須命中分支或目錄名稱（AND）。
# 符合時 REPLY 放總分並回傳 0。
_gwt_fuzzy_match() {
  local branch=$1 base=$2 query=$3
  local -a terms=()
  local t
  for t in "${(@s: :)query}"; do
    [[ -n $t ]] && terms+=("$t")
  done
  if (( ${#terms} == 0 )); then
    REPLY=0
    return 0
  fi

  local -i total=0 sb=0 sa=0 rb=0 ra=0
  local term
  for term in "${terms[@]}"; do
    _gwt_fuzzy_term "$branch" "$term"
    rb=$?
    sb=$REPLY
    _gwt_fuzzy_term "$base" "$term"
    ra=$?
    sa=$REPLY

    if (( rb != 0 && ra != 0 )); then
      REPLY=0
      return 1
    fi
    if (( rb == 0 && ( ra != 0 || sb >= sa ) )); then
      (( total += sb ))
    else
      (( total += sa ))
    fi
  done

  REPLY=$total
  return 0
}

# 記住命令列關鍵字篩選後的完整清單，互動搜尋才不會愈搜愈少。
_gwt_snapshot() {
  _GWT_ALL_PATHS=("${(@)_GWT_PATHS}")
  _GWT_ALL_BRANCHES=("${(@)_GWT_BRANCHES}")
  _GWT_ALL_HEADS=("${(@)_GWT_HEADS}")
}

# 依 _GWT_QUERY 重新產生目前顯示的清單，並依分數排序（同分維持 Git 的順序）。
_gwt_refilter() {
  local -i i n=${#_GWT_ALL_PATHS} score
  local base key
  local -a ranked=()

  _GWT_PATHS=()
  _GWT_BRANCHES=()
  _GWT_HEADS=()
  _GWT_COUNT=0

  if [[ -z ${_GWT_QUERY// /} ]]; then
    _GWT_PATHS=("${(@)_GWT_ALL_PATHS}")
    _GWT_BRANCHES=("${(@)_GWT_ALL_BRANCHES}")
    _GWT_HEADS=("${(@)_GWT_ALL_HEADS}")
    _GWT_COUNT=$n
    return 0
  fi

  for (( i = 1; i <= n; i++ )); do
    base=${_GWT_ALL_PATHS[i]:t}
    _gwt_fuzzy_match "${_GWT_ALL_BRANCHES[i]}" "$base" "$_GWT_QUERY" || continue
    score=$REPLY
    (( score < 0 )) && score=0
    # 固定寬度排序鍵：分數遞減、原始順序遞增（(O) 是字串遞減排序）
    printf -v key '%06d:%06d:%d' $(( score + 1 )) $(( 1000000 - i )) "$i"
    ranked+=("$key")
  done

  for key in "${(@O)ranked}"; do
    i=${key##*:}
    _GWT_PATHS+=("${_GWT_ALL_PATHS[i]}")
    _GWT_BRANCHES+=("${_GWT_ALL_BRANCHES[i]}")
    _GWT_HEADS+=("${_GWT_ALL_HEADS[i]}")
    (( _GWT_COUNT++ ))
  done
}

# 查詢改變後重設游標：永遠從最佳的那一筆開始。
_gwt_search_apply() {
  _gwt_refilter
  if (( _GWT_COUNT > 0 )); then
    _GWT_SELECTED=1
  else
    _GWT_SELECTED=0
  fi
  _GWT_TOP=1
}

# 離開搜尋模式，恢復完整清單（ESC 在搜尋模式裡做這件事，不是取消選單）。
_gwt_search_exit() {
  _GWT_SEARCH=0
  _GWT_QUERY=''
  _gwt_refilter
  if (( _GWT_COUNT > 0 )); then
    _GWT_SELECTED=1
  else
    _GWT_SELECTED=0
  fi
  _GWT_TOP=1
}

# -----------------------------------------------------------------------------
# 畫面
# -----------------------------------------------------------------------------
# 產生第 i 列的文字，結果放在 REPLY。
# 光棒只反白到路徑為止，分支與狀態維持原色，方便一眼辨識。
# 每一列都必須控制在一個實體行內，否則折行會讓「往上移 N 行」算錯。
# 預算分配：前綴 → 間隔 2 欄 → 後方資訊 → 剩下的全部給路徑（至少 12 欄）。
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

  local -i gap=2
  local -i tail_budget=$(( _GWT_WIDTH - ${#prefix} - gap - 12 ))
  (( tail_budget < 8 )) && tail_budget=8

  # 目前位置標註：空間不夠就省略，優先保留路徑與分支
  local mark=''
  if [[ -n $_GWT_CURRENT && ${wt_path:A} == ${_GWT_CURRENT:A} ]]; then
    _gwt_swidth "${_GWT_M[mark]}"
    if (( _GWT_SW + 1 <= tail_budget - 12 )); then
      mark=${_GWT_M[mark]}
      (( tail_budget -= _GWT_SW + 1 ))
    fi
  fi

  # [branch] (commit) 的固定成本是 12 欄：'[' ']' 空白 '(' 7 碼 ')'
  local -i branch_budget=$(( tail_budget - 12 ))
  (( branch_budget < 1 )) && branch_budget=1
  _gwt_clip_middle "$branch" "$branch_budget"
  local branch_shown=$REPLY

  local suffix="${_GWT_S_BRANCH}[${branch_shown}]${_GWT_S_RESET} (${head})"
  [[ -n $mark ]] && suffix+=" ${_GWT_S_MARK}${mark}${_GWT_S_RESET}"

  _gwt_width_of "$suffix"
  local -i avail=$(( _GWT_WIDTH - ${#prefix} - gap - _GWT_SW ))

  # 完整的後方資訊放不下（路徑連最短的 4 欄都分不到）時，不能硬把路徑夾到 4 欄：
  # 一列會折成兩行，重繪與收尾算的列數就錯，畫面留下殘影。依序省略：先拿掉 commit
  # 只留 [分支]，再放不下就連分支都拿掉，整列只剩編號與路徑。（與 PowerShell 版相同）
  local -i min_path=4 room
  if (( avail < min_path )); then
    room=$(( _GWT_WIDTH - ${#prefix} - gap - min_path - 2 ))   # 扣掉 [ ] 兩欄
    if (( room >= 1 )); then
      _gwt_clip_middle "$branch" "$room"
      suffix="${_GWT_S_BRANCH}[${REPLY}]${_GWT_S_RESET}"
      _gwt_width_of "$suffix"
      avail=$(( _GWT_WIDTH - ${#prefix} - gap - _GWT_SW ))
    else
      suffix=''
      avail=$(( _GWT_WIDTH - ${#prefix} ))
    fi
  fi
  (( avail < 1 )) && avail=1
  _gwt_clip_middle "$wt_path" "$avail"
  local shown=$REPLY

  if (( sel )); then
    # 光棒只反白到路徑為止，後方分支與狀態維持原色
    if [[ -z $suffix ]]; then
      REPLY="${_GWT_S_BAR}${prefix}${shown}${_GWT_S_RESET}"
    else
      REPLY="${_GWT_S_BAR}${prefix}${shown} ${_GWT_S_RESET} ${suffix}"
    fi
  elif [[ -z $suffix ]]; then
    REPLY="${prefix}${shown}"
  else
    REPLY="${prefix}${shown}  ${suffix}"
  fi
}

_gwt_header() {
  local text=''
  if (( _GWT_SEARCH )); then
    printf -v text "${_GWT_M[search]}" "$_GWT_QUERY" "$_GWT_COUNT"
  else
    printf -v text "${_GWT_M[header]}" "$_GWT_COUNT"
  fi
  _gwt_clip_middle "$text" "$_GWT_WIDTH"
}

# 表頭只佔一列，而且每次重畫都要先清掉整列，避免搜尋字串變短時留下殘影。
_gwt_draw_header() {
  _gwt_header
  printf '\r\e[2K%s\n' "$REPLY"
}

_gwt_draw() {
  _gwt_layout

  if (( _GWT_COUNT == 0 )); then
    _gwt_clip_middle "${_GWT_M[search_none]}" "$_GWT_WIDTH"
    printf '\r\e[2K%s%s%s\n' "$_GWT_S_DIM" "$REPLY" "$_GWT_S_RESET"
    _GWT_DRAWN=1
    return 0
  fi

  local -i i last=$(( _GWT_TOP + _GWT_VISIBLE - 1 ))
  (( last > _GWT_COUNT )) && last=$_GWT_COUNT

  for (( i = _GWT_TOP; i <= last; i++ )); do
    printf '\r\e[2K'
    _gwt_format_row "$i"
    printf '%s\n' "$REPLY"
  done
  _GWT_DRAWN=$(( last - _GWT_TOP + 1 ))

  if (( _GWT_SCROLLED )); then
    local text=''
    printf -v text "${_GWT_M[range]}" "$_GWT_TOP" "$last" "$_GWT_COUNT"
    _gwt_clip_middle "$text" "$(( _GWT_WIDTH - 3 ))"
    printf '\r\e[2K%s   %s%s\n' "$_GWT_S_DIM" "$REPLY" "$_GWT_S_RESET"
    (( _GWT_DRAWN++ ))
  fi
}

# 回到表頭那一列，重畫表頭與清單。表頭會隨搜尋字串改變，所以不能只畫清單。
# 這裡一定要先 \e[J 清到畫面結尾：搜尋讓清單變短時，舊的列還在游標下方，
# 只畫新的列會留下殘影，看起來就像清單沒有跟著篩選。
_gwt_repaint() {
  _gwt_layout
  printf '\e[%dA\e[J' "$(( _GWT_DRAWN + 1 ))"
  _gwt_draw_header
  _gwt_draw
}

# 收尾：移除 trap、視需要擦掉選單、把游標還給使用者。
# 不論是 Enter、數字鍵、q/Esc、Ctrl+C 或讀不到輸入，都必須經過這裡。
_gwt_finish() {
  trap - INT TERM
  if (( ${GWT_CLEAR_ON_EXIT:-1} )) && (( _GWT_DRAWN > 0 )); then
    printf '\e[%dA\e[J' "$(( _GWT_DRAWN + 1 ))"
  fi
  printf '\e[?25h'
}

_gwt_shift() {
  local -i d=$1
  (( _GWT_COUNT == 0 )) && return 0
  _GWT_SELECTED=$(( _GWT_SELECTED + d ))
  if (( _GWT_SELECTED > _GWT_COUNT )); then
    _GWT_SELECTED=1
  elif (( _GWT_SELECTED < 1 )); then
    _GWT_SELECTED=$_GWT_COUNT
  fi
}

# 數字鍵：worktree 超過 9 個時，再等一小段時間看是否還有第二位數字。
# 例如清單有 12 筆時，按 1 再按 2 會跳到第 12 筆；只按 1 則等 timeout 後跳第 1 筆。
#
# 只把解析出的編號放在 REPLY，不動 _GWT_SELECTED：編號超出範圍（5 筆時按 9、12 筆時按 13）
# 會被呼叫端忽略，這時目前的選取必須維持原樣，否則光棒會消失、Enter 會選到不存在的那一筆。
#
# 「再加一位就超過總數就不必等」這條，在等待「之前」就要判斷：12 筆時按 9，90 > 12，
# 第二位數不可能有效，立刻跳轉，不能白等 GWT_DIGIT_TIMEOUT。
#
# 等待期間收到的不是數字的按鍵，放進 _GWT_PENDING_KEY 交給呼叫端：
#   - Ctrl+C（終端機關掉 ISIG 時以 \x03 位元組進來）是中斷，呼叫端要直接中止，不能讓剛才的數字生效
#   - 編號超出範圍時，主迴圈接著照一般按鍵處理它
#   - 編號有效時選單隨即關閉，其他按鍵就沒有後續了（跟剛按完數字就立刻跳轉的短清單一致）
# 這三點與 PowerShell 版（Invoke-GwtPickNumber）相同。
_gwt_pick_number() {
  local digits=$1 more=''
  local -i maxlen=${#_GWT_COUNT}
  while (( ${#digits} < maxlen )); do
    (( 10#$digits * 10 > _GWT_COUNT )) && break
    if ! read -r -k 1 -s -t "${GWT_DIGIT_TIMEOUT:-0.4}" more; then
      break
    fi
    if [[ $more == [0-9] ]]; then
      digits="${digits}${more}"
    else
      [[ -n $more ]] && _GWT_PENDING_KEY=$more
      break
    fi
  done
  REPLY=$(( 10#$digits ))
}

# 讀取 Esc 之後的序列，結果分類放在 _GWT_ESC_KIND：
#   up / down / escape（單獨一個 Esc） / other（無法辨識的序列）
# 這裡刻意逐字元讀，而不是 read -k 2：使用者按 Esc 之後若馬上按 Enter，
# read -k 2 會把 Enter 一起吃掉。現在會把它放回 _GWT_PENDING_KEY。
_gwt_read_escape() {
  local one='' two=''
  _GWT_ESC_KIND='other'
  if ! read -r -k 1 -s -t "${GWT_ESC_TIMEOUT:-0.05}" one; then
    _GWT_ESC_KIND='escape'
    return 0
  fi
  case $one in
    '['|'O')
      if read -r -k 1 -s -t "${GWT_ESC_TIMEOUT:-0.05}" two; then
        case $two in
          A) _GWT_ESC_KIND='up' ;;
          B) _GWT_ESC_KIND='down' ;;
          *) _GWT_ESC_KIND='other' ;;
        esac
      fi
      ;;
    *)
      _GWT_PENDING_KEY=$one
      _GWT_ESC_KIND='escape'
      ;;
  esac
}

# 互動式選單。成功選定時回傳 0，取消或中斷時回傳非 0。
_gwt_pick() {
  local key=''
  local -i picked=0
  _GWT_SELECTED=1
  _GWT_PENDING_KEY=''
  _gwt_init_size
  _gwt_init_style

  # 選單顯示期間隱藏游標；trap 保證中斷時游標與終端狀態都會復原。
  # 這裡除了清理，還要把 _GWT_INTERRUPTED 標起來：zsh 在 trap 裡執行 return
  # 時，回傳值不見得會傳到呼叫端（實測可能變成 0 或 1），所以 gwt 最後一律
  # 以這個旗標決定要不要回傳 130，不依賴 trap 的 return 值。
  printf '\e[?25l'
  trap '_GWT_INTERRUPTED=1; _gwt_finish; return 130' INT TERM

  _gwt_draw_header
  _gwt_draw

  while true; do
    if [[ -n $_GWT_PENDING_KEY ]]; then
      key=$_GWT_PENDING_KEY
      _GWT_PENDING_KEY=''
    elif ! read -r -k 1 -s key; then
      _gwt_finish
      return 1
    fi

    if (( _GWT_SEARCH )); then
      # 搜尋模式：可列印字元都算查詢內容，所以 q、j、k、數字都不再有特殊意義。
      case $key in
        $'\e')
          _gwt_read_escape
          case $_GWT_ESC_KIND in
            up)     _gwt_shift -1 ;;
            down)   _gwt_shift 1 ;;
            escape) _gwt_search_exit ;;   # 搜尋中的 Esc 只清掉搜尋
          esac
          ;;
        $'\x03')                             # Ctrl+C
          _GWT_INTERRUPTED=1
          _gwt_finish
          return 130
          ;;
        $'\n'|$'\r')
          if (( _GWT_COUNT > 0 )); then
            _gwt_finish
            return 0
          fi
          ;;
        $'\x7f'|$'\x08')                     # Backspace / Delete
          if [[ -n $_GWT_QUERY ]]; then
            _GWT_QUERY=${_GWT_QUERY%?}
            _gwt_search_apply
          fi
          ;;
        $'\x15')                             # Ctrl+U：清空查詢
          if [[ -n $_GWT_QUERY ]]; then
            _GWT_QUERY=''
            _gwt_search_apply
          fi
          ;;
        $'\x17')                             # Ctrl+W：刪除最後一個詞
          if [[ -n $_GWT_QUERY ]]; then
            local q=${_GWT_QUERY% }
            if [[ $q == *' '* ]]; then
              _GWT_QUERY=${q% *}
            else
              _GWT_QUERY=''
            fi
            _gwt_search_apply
          fi
          ;;
        [$'\x01'-$'\x1f'])
          ;;                                 # 其他控制鍵：忽略
        *)
          _GWT_QUERY+=$key
          _gwt_search_apply
          ;;
      esac
    else
      case $key in
        /)                                   # 進入模糊搜尋
          _GWT_SEARCH=1
          _GWT_QUERY=''
          _gwt_search_apply
          ;;
        $'\e')
          _gwt_read_escape
          case $_GWT_ESC_KIND in
            up)     _gwt_shift -1 ;;
            down)   _gwt_shift 1 ;;
            escape) _gwt_finish; return 1 ;;   # 單獨一個 Esc = 取消
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
          picked=$REPLY
          # 等第二位數的時候按了 Ctrl+C：是中斷。不論數字有沒有效都以中斷為準
          if [[ $_GWT_PENDING_KEY == $'\x03' ]]; then
            _GWT_PENDING_KEY=''
            _GWT_INTERRUPTED=1
            _gwt_finish
            return 130
          fi
          if (( picked >= 1 && picked <= _GWT_COUNT )); then
            _GWT_SELECTED=$picked
            # 先重畫一次，讓使用者看到最後落在哪一筆
            printf '\e[%dA' "$_GWT_DRAWN"
            _gwt_draw
            _gwt_finish
            return 0
          fi
          # 超出範圍：忽略，目前的選取維持原樣
          ;;
        q|Q)
          _gwt_finish
          return 1
          ;;
      esac
    fi

    # 回到這一塊的第一列重畫（表頭也可能因為搜尋字串而改變）
    _gwt_repaint
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
  # 互動搜尋從完整清單重新篩選；命令列關鍵字已經是第一層篩選。
  _gwt_snapshot

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
