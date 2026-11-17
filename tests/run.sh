#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 測試總入口：make test 呼叫的就是這支
#
# 測試分兩類：
#   tests/cases/      不需要終端機的單元測試，直接用 zsh -f 執行
#   tests/cases-pty/  需要按鍵的互動測試，用 tests/lib/ptydrive.py 開 PTY 執行
#
# 互動測試的按鍵寫在測試檔第一行的註解裡，例如：
#   # GWT_KEYS: \e[B\e[B\n
# 另外可以用 # GWT_EXPECT: 與 # GWT_EXPECT_NOT: 檢查原始輸出（支援 \e 跳脫），
# 用來驗證游標有沒有被還原、選單有沒有被擦掉這類「畫面」行為。
#
# 選單排版要用「重播後的畫面」才驗得準，可以用：
#   # GWT_ROWS: 12                     PTY 高度（預設 40）
#   # GWT_COLS: 48                     PTY 寬度（預設 100）
#   # GWT_SCREEN_EXPECT: ^SELECTED=16$  對重播畫面（含結構摘要）比對延伸正規表示式
#   # GWT_SCREEN_EXPECT_NOT: 請選擇     畫面上不該出現的字串
# 畫面重播由 tests/lib/screen.py 負責。若測試在選單之後會印出斷言結果，
# 那些輸出會把選單往上推，所以要在 gwt 之後印一行 GWT-SCREEN-CUT，
# 重播時就會停在那一行之前，看到完整的選單。
#
# 環境變數：
#   GWT_KEEP=1  保留暫存目錄，方便失敗時進去追
# -----------------------------------------------------------------------------
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export GWT_ROOT="$ROOT"
export GWT_LANG="${GWT_LANG:-zh}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gwt-test.XXXXXXXX") || {
  printf '無法建立暫存目錄\n' >&2
  exit 1
}
cleanup() {
  if [[ -n ${GWT_KEEP:-} ]]; then
    printf '\n（保留測試目錄：%s）\n' "$WORK"
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT
export GWT_FIXTURE="$WORK"

printf '建立測試資料 ...\n'
if ! bash "$ROOT/tests/fixtures/build.sh" "$WORK" >"$WORK/build.log" 2>&1; then
  printf '建立測試資料失敗：\n' >&2
  sed 's/^/    /' "$WORK/build.log" >&2
  exit 1
fi

HAVE_PYTHON=0
if command -v python3 >/dev/null 2>&1; then
  HAVE_PYTHON=1
fi

pass=0
fail=0
skip=0
failed=()

show_log() {
  sed 's/^/        /' "$1"
}

# 從 PTY 的原始輸出裡挑出斷言結果，方便失敗時除錯
show_pty_log() {
  LC_ALL=C sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$1" |
    tr -d '\r' |
    grep -a -E 'ok |FAIL|小計' |
    sed 's/^/        /'
}

run_plain() {
  local file=$1 name out
  name=$(basename "$file")
  out="$WORK/log-$name.txt"
  if zsh -f "$file" >"$out" 2>&1; then
    printf '  通過  %s\n' "$name"
    pass=$(( pass + 1 ))
  else
    printf '  失敗  %s\n' "$name"
    fail=$(( fail + 1 ))
    failed+=("$name")
    show_log "$out"
  fi
}

run_pty() {
  local file=$1 name keys out raw rc ok pat literal rows cols screen
  name=$(basename "$file")
  out="$WORK/log-pty-$name.txt"
  raw="$WORK/raw-pty-$name.bin"
  keys=$(sed -n 's/^# *GWT_KEYS: *//p' "$file" | head -1)
  rows=$(sed -n 's/^# *GWT_ROWS: *//p' "$file" | head -1)
  cols=$(sed -n 's/^# *GWT_COLS: *//p' "$file" | head -1)
  [[ -z $rows ]] && rows=40
  [[ -z $cols ]] && cols=100

  if [[ -z $keys ]]; then
    printf '  失敗  %s（缺少 # GWT_KEYS:）\n' "$name"
    fail=$(( fail + 1 ))
    failed+=("$name")
    return
  fi

  rc=0
  python3 "$ROOT/tests/lib/ptydrive.py" --keys "$keys" --out "$raw" \
    --rows "$rows" --cols "$cols" \
    -- zsh -f "$file" >"$out" 2>&1 || rc=$?

  ok=1
  (( rc != 0 )) && ok=0

  while IFS= read -r pat; do
    [[ -z $pat ]] && continue
    literal=$(printf '%b' "$pat")
    if ! grep -a -q -F -- "$literal" "$raw" 2>/dev/null; then
      ok=0
      printf '        缺少預期輸出: %s\n' "$pat" >>"$out"
    fi
  done < <(sed -n 's/^# *GWT_EXPECT: *//p' "$file")

  while IFS= read -r pat; do
    [[ -z $pat ]] && continue
    literal=$(printf '%b' "$pat")
    if grep -a -q -F -- "$literal" "$raw" 2>/dev/null; then
      ok=0
      printf '        不該出現的輸出: %s\n' "$pat" >>"$out"
    fi
  done < <(sed -n 's/^# *GWT_EXPECT_NOT: *//p' "$file")

  # 畫面層級的檢查：把 PTY 輸出重播成最終畫面再比對
  if sed -n 's/^# *GWT_SCREEN_EXPECT: *//p' "$file" | grep -q .; then
    screen=$(python3 "$ROOT/tests/lib/screen.py" --rows "$rows" --cols "$cols" \
      --until GWT-SCREEN-CUT --raw "$raw" 2>&1)
    while IFS= read -r pat; do
      [[ -z $pat ]] && continue
      if ! printf '%s\n' "$screen" | grep -E -q -- "$pat"; then
        ok=0
        printf '        畫面缺少: %s\n' "$pat" >>"$out"
      fi
    done < <(sed -n 's/^# *GWT_SCREEN_EXPECT: *//p' "$file")
  fi

  if sed -n 's/^# *GWT_SCREEN_EXPECT_NOT: *//p' "$file" | grep -q .; then
    [[ -z ${screen:-} ]] && screen=$(python3 "$ROOT/tests/lib/screen.py" \
      --rows "$rows" --cols "$cols" --until GWT-SCREEN-CUT --raw "$raw" 2>&1)
    while IFS= read -r pat; do
      [[ -z $pat ]] && continue
      if printf '%s\n' "$screen" | grep -E -q -- "$pat"; then
        ok=0
        printf '        畫面不該出現: %s\n' "$pat" >>"$out"
      fi
    done < <(sed -n 's/^# *GWT_SCREEN_EXPECT_NOT: *//p' "$file")
  fi

  if (( ok )); then
    printf '  通過  %s\n' "$name"
    pass=$(( pass + 1 ))
  else
    printf '  失敗  %s（結束碼 %d）\n' "$name" "$rc"
    fail=$(( fail + 1 ))
    failed+=("$name")
    [[ -s $out ]] && show_log "$out"
    [[ -s $raw ]] && show_pty_log "$raw"
    [[ -n ${screen:-} ]] && printf '%s\n' "$screen" | tail -6 | sed 's/^/        /'
  fi
}

printf '\n單元測試（不需要終端機）\n'
for file in "$ROOT"/tests/cases/*.zsh; do
  [[ -e $file ]] || continue
  run_plain "$file"
done

printf '\n互動測試（PTY）\n'
if (( HAVE_PYTHON )); then
  for file in "$ROOT"/tests/cases-pty/*.zsh; do
    [[ -e $file ]] || continue
    run_pty "$file"
  done
else
  printf '  略過 找不到 python3，互動測試需要它才能開 PTY\n'
  skip=$(( skip + 1 ))
fi

printf '\n========================================\n'
printf '通過 %d，失敗 %d' "$pass" "$fail"
(( skip )) && printf '，略過 %d 類' "$skip"
printf '\n'

if (( fail )); then
  printf '\n失敗的測試：\n'
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi
exit 0
