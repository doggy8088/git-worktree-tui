# -----------------------------------------------------------------------------
# 極簡測試斷言
#
# 每個測試檔開頭 source 這個檔案，中間呼叫 assert_*，最後呼叫 t_report。
# t_report 的回傳值就是這個測試檔的結果：全部通過回傳 0，有失敗回傳 1。
# 故意不引入 bats 之類的框架，讓專案只依賴 zsh 與 git。
# -----------------------------------------------------------------------------

typeset -gi _T_PASS=0 _T_FAIL=0

_t_pass() {
  (( _T_PASS++ ))
  printf '  ok    %s\n' "$1"
}

_t_fail() {
  (( _T_FAIL++ ))
  printf '  FAIL  %s\n' "$1"
}

# assert_eq <說明> <期望值> <實際值>
assert_eq() {
  local label=$1 want=$2 got=$3
  if [[ "$want" == "$got" ]]; then
    _t_pass "$label"
  else
    _t_fail "$label"
    printf '        期望: %s\n        實得: %s\n' "$want" "$got"
  fi
}

# assert_ne <說明> <不該等於的值> <實際值>
assert_ne() {
  local label=$1 want=$2 got=$3
  if [[ "$want" != "$got" ]]; then
    _t_pass "$label"
  else
    _t_fail "$label"
    printf '        不該等於: %s\n' "$want"
  fi
}

# assert_contains <說明> <要找的字串> <內容>
assert_contains() {
  local label=$1 needle=$2 hay=$3
  if [[ "$hay" == *"$needle"* ]]; then
    _t_pass "$label"
  else
    _t_fail "$label"
    printf '        找不到: %s\n        內容: %s\n' "$needle" "$hay"
  fi
}

# assert_not_contains <說明> <不該出現的字串> <內容>
assert_not_contains() {
  local label=$1 needle=$2 hay=$3
  if [[ "$hay" != *"$needle"* ]]; then
    _t_pass "$label"
  else
    _t_fail "$label"
    printf '        不該出現: %s\n' "$needle"
  fi
}

# assert_rc <說明> <期望結束碼> <實際結束碼>
assert_rc() {
  local label=$1 want=$2 got=$3
  if (( want == got )); then
    _t_pass "$label"
  else
    _t_fail "$label"
    printf '        期望結束碼: %d，實得: %d\n' "$want" "$got"
  fi
}

t_report() {
  printf '  小計：%d 通過，%d 失敗\n' "$_T_PASS" "$_T_FAIL"
  (( _T_FAIL == 0 ))
}
