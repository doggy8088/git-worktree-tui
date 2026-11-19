#!/usr/bin/env zsh
# GWT_KEYS: 1\x03
# GWT_EXPECT: \e[?25h
# 12 筆時按 1（還可能是 10～12，所以要等第二位數），等待中按 Ctrl+C：是中斷，回傳 130、不切換。
#
# 一般情況下 Ctrl+C 會變成 SIGINT，由 trap 處理，不經過這段程式。這裡先用 stty -isig 關掉
# 終端機的訊號轉換，讓 Ctrl+C 以 \x03 位元組送進來（主迴圈本來就有處理這種情況）。
# 舊版等第二位數時把 \x03 放進「待處理按鍵」，但數字有效就直接切換並回傳 0，沒人看那個按鍵。
source "$GWT_ROOT/tests/lib/assert.zsh"
source "$GWT_ROOT/tests/lib/fixture.zsh"
source "$GWT_ROOT/gwt.zsh"

GWT_DIGIT_TIMEOUT=5
# 從第 5 筆的目錄開始，第 1 筆（主要的工作目錄）才會與現在位置不同，切換了就看得出來
start=$(fixture_path "$GWT_FIXTURE/twelve" 5)
cd "$start" || exit 1

saved=$(stty -g)
stty -isig
gwt
rc=$?
stty "$saved"

assert_rc "中斷回傳 130" 130 "$rc"
assert_eq "目錄維持不變" "$start" "$PWD"

t_report
