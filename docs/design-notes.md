# 設計筆記

這份文件記錄 `gwt.zsh` 裡每個「看起來有點囉唆」的決定的理由，以及判斷的依據。
多數結論都是實際跑過才確認的，指令都附在下面，可以自己重現。

## 1. 為什麼一定得是 shell 函式

這不是風格問題，而是 shell 的執行模型決定的：

| 形式              | 執行位置   | 能改變目前終端機的工作目錄 | 適合用途                     |
| ----------------- | ---------- | -------------------------- | ---------------------------- |
| 獨立腳本 `gwt.sh` | 子處理序   | 不行，`cd` 只影響子處理序  | 不需要改變 shell 狀態的工具  |
| `source gwt.sh`   | 目前 shell | 可以，但每次都要 `source`  | 臨時載入設定                 |
| shell 函式        | 目前 shell | 可以                       | 需要 `cd`、改環境變數的工具  |
| alias             | 目前 shell | 可以，但寫不了流程判斷     | 縮短固定指令                 |

子處理序結束後，父 shell 的工作目錄不會跟著變。所以「切換 worktree」這個需求從一開始就只能寫成函式，代價是它必須被 `source` 進目前的 shell（`install.sh` 就是在處理這件事）。

`gwt.plugin.zsh` 只是給 plugin manager 的進入點，內容是 `source "${0:A:h}/gwt.zsh"`；用 `${0:A:h}` 是為了讓 symlink 與任意安裝路徑都能正確解析。

## 2. 解析 `git worktree list --porcelain`，不是給人看的格式

預設輸出是對齊過的人類格式，欄位用空白分隔，路徑只要含空白就切不準。`--porcelain` 改成每行一個 `key value`，worktree 之間用空行分隔：

```
worktree /path/to/shop
HEAD 89ae97a1b2c3d4e5f6a7b8
branch refs/heads/main

worktree /path/to/shop-hotfix
HEAD fedcba9876543210fedc
detached
```

實作上用 `case` 逐行比對前綴，遇到空行才把累積到的那一組收進陣列：

```zsh
while IFS= read -r line || [[ -n $line ]]; do
  case $line in
    'worktree '*) wt_path=${line#worktree } ;;
    'HEAD '*)     head=${line#HEAD } ;;
    'branch '*)   branch=${line#branch refs/heads/} ;;
    'detached')   branch=${_GWT_M[detached]} ;;
    '')
      [[ -n $wt_path ]] && _gwt_collect_one "$keyword" "$wt_path" "$branch" "$head"
      wt_path=''; head=''; branch=''
      ;;
  esac
done
```

`IFS= read -r` 的 `-r` 不能省，否則路徑裡的反斜線會被吃掉。`|| [[ -n $line ]]` 是處理最後一行沒有換行的情況。

呼叫端會補一個換行，確保最後一組一定會以空行結尾：

```zsh
_gwt_collect "$keyword" < <(git worktree list --porcelain 2>/dev/null; printf '\n')
```

用 process substitution 而不用 `git ... | _gwt_collect`，是因為管線的每一段都跑在子 shell，`_GWT_PATHS` 的賦值會消失在子 shell 裡。這是 shell 腳本常見的陷阱，改寫時很容易漏掉。

## 3. 變數千萬不要叫 `path`

在 zsh 裡，小寫的 `path` 陣列與大寫的 `PATH` 環境變數是**同一個東西的兩種表示**。在函式裡宣告 `local path=""`，等於把函式內的 `PATH` 清空：

```sh
zsh -f -c 'f(){ local path=""; ls /tmp >/dev/null; }; f'
# f: command not found: ls
```

這個坑在 bash 不存在（bash 的 `path` 只是普通變數），所以從 bash 改寫過來特別容易中。本專案一律使用 `wt_path`，並有測試 `tests/cases/07-path-safety.zsh` 把關：

- 執行後 `PATH` 與執行前完全相同
- `command -v ls` 仍能解析
- 原始碼（略過註解）不含 `local path=`

## 4. 用跳脫序列原地重繪

選單不是每按一次鍵就重印一份，而是把游標移回選單第一列，原地重畫：

| 序列               | 作用               | 用途                               |
| ------------------ | ------------------ | ---------------------------------- |
| `\e[?25l` / `\e[?25h` | 隱藏／顯示游標  | 選單期間隱藏游標，避免閃爍         |
| `\e[%dA`           | 游標往上移 N 行    | 按鍵後回到第一列重畫               |
| `\r\e[2K`          | 回到行首並清除整行 | 每列重畫前先清乾淨，避免殘留舊文字 |
| `\e[J`             | 清除游標以下       | 離開時把整個選單擦掉               |
| `\e[1;30;46m`      | 粗體、黑字、青底   | 選取光棒                           |

重繪的關鍵是「每列只佔一行」。長路徑折行會讓「往上移 N 行」算錯，畫面就會錯位——這也是本專案加上欄寬截斷的原因（見第 8 節）。

## 5. 分開「單獨的 Esc」與「方向鍵」

方向鍵送進終端機的其實是一串字元：`↑` 是 `Esc [ A`，`↓` 是 `Esc [ B`；某些終端機在 application cursor mode 下送 `Esc O A` / `Esc O B`。

所以讀到 `Esc` 之後，要再等一小段時間看後面有沒有跟著字元：

```zsh
rest=''
read -r -k 2 -s -t "${GWT_ESC_TIMEOUT:-0.05}" rest
case $rest in
  '[A'|'OA') _gwt_shift -1 ;;
  '[B'|'OB') _gwt_shift 1 ;;
  '')        _gwt_finish; return 1 ;;   # 只按了 Esc
  *)         ;;                         # 其他序列：忽略
esac
```

`-t 0.05` 是等 50 毫秒。等不到就是單獨的 Esc，視為取消；等到兩個字元就是方向鍵。這個值做成 `GWT_ESC_TIMEOUT`，因為某些遠端連線或慢速終端機可能讓後續字元晚到。

## 6. 隱藏游標，就要配 `trap`

選單期間游標是隱藏的。如果使用者按 `Ctrl+C` 而沒有清理，游標會一直消失，整個終端機看起來像壞掉。所以進入選單前先設 trap：

```zsh
printf '\e[?25l'
trap '_GWT_INTERRUPTED=1; _gwt_finish; return 130' INT TERM
```

而 `_gwt_finish` 是所有離開路徑唯一的出口：

```zsh
_gwt_finish() {
  trap - INT TERM
  if (( ${GWT_CLEAR_ON_EXIT:-1} )); then
    printf '\e[%dA\e[J' "$_GWT_DRAWN"
  fi
  printf '\e[?25h'
}
```

Enter、數字鍵、`q`、`Esc`、`Ctrl+C`、讀不到輸入（EOF）這六條路都會呼叫它，順序是「先移除 trap、再擦畫面、最後還原游標」。`tests/cases-pty/08-ctrl-c.zsh` 會檢查原始輸出裡真的出現過 `\e[?25h`。

## 7. `trap` 裡的 `return` 回傳值不可信

原始版本用 `trap '...; return 130' INT TERM` 期望 `gwt` 最後回傳 130。實測 zsh 5.9 在 PTY 下按 `Ctrl+C`，`gwt` 的結束碼會變成 `0`（有時是 `1`），不是 `130`。

用 `zsh -fx` 追蹤看得很清楚：trap 內的 `_gwt_finish` 有跑、`return 130` 也有執行，但回到呼叫端時 `$?` 不是 130。

因此本專案改成「trap 只負責標記，結束碼由 `gwt` 自己決定」：

```zsh
# trap 內
_GWT_INTERRUPTED=1; _gwt_finish; return 130

# gwt 內
_gwt_pick
local rc=$?
(( _GWT_INTERRUPTED )) && return 130
(( rc != 0 )) && return $rc
```

另外也處理了「Ctrl+C 被當成位元組送進來」的情況（有些終端機設定會關掉 `ISIG`，訊號就不會產生，`\x03` 會直接變成輸入）：

```zsh
$'\x03')
  _GWT_INTERRUPTED=1
  _gwt_finish
  return 130
  ;;
```

## 8. 欄寬計算：跳脫序列不算、全形字算兩欄

路徑長度用「字元數」算是不準的：`\e[36m` 這種跳脫序列不佔畫面，而 CJK 全形字佔兩欄。`(目前位置)` 是 6 個字元，但實際佔 10 欄。

`_gwt_swidth` 逐字元累加，遇到全形範圍就加兩欄：

```zsh
if [[ $c == [$'\u1100'-$'\u115f'] || $c == [$'\u2e80'-$'\ua4cf'] ||
      $c == [$'\uac00'-$'\ud7a3'] || $c == [$'\uf900'-$'\ufaff'] ||
      $c == [$'\uFE30'-$'\uFE4F'] || $c == [$'\uff00'-$'\uff60'] ||
      $c == [$'\uffe0'-$'\uffe6'] ]]; then
  (( w += 2 ))
else
  (( w += 1 ))
fi
```

`_gwt_strip_ansi` 先把 `\e[...m` 拿掉，再量剩下的文字。組字串時刻意用固定格式：

```
[編號] 路徑  [分支] (commit) (目前位置)
```

可用給路徑的欄寬 = 終端機寬 − 前綴 − 後方資訊，算出來才決定要不要截斷：

```zsh
_gwt_clip_middle "$wt_path" "$avail"   # 保留頭 1/3、尾 2/3，中間放省略號
```

保留比較多的尾段，是因為工作目錄的結尾（`shop-feature-login`）比前面的共同路徑有用。

小細節：`_GWT_WIDTH` 會再減 1，避免內容剛好佔滿最後一欄時觸發終端機自動換行，那樣也會讓重繪行數算錯。

## 9. 不用 `%b` 印分支名稱

原始版本把顏色碼存在陣列裡，再用 `printf '... %b\n'` 印出。`%b` 會解讀反斜線跳脫序列，所以分支名稱只要包含 `\n`、`\t` 之類的內容，就會被轉成控制字元（分支名稱是可以包含反斜線的）。

本專案改成「事先組好真正的跳脫字串，再用 `%s` 印」：

```zsh
_GWT_S_BRANCH=$'\e[36m'
suffix=" ${_GWT_S_BRANCH}[${branch}]${_GWT_S_RESET} (${head})"
printf '%s\n' "$REPLY"
```

`tests/cases/10-escape-safety.zsh` 用 `a\nb\tc` 這種分支名稱與含 `%s` 的路徑驗證輸出維持字面。

## 10. 超過 9 筆時的多位數編號

原文的限制是「數字鍵只支援 1 到 9」，但提示文字卻印出「按 1-12 直接跳轉」，按 `1` 會立刻跳到第 1 筆，永遠選不到 10 以後。

這裡的作法是：只有在 `_GWT_COUNT > 9` 時才多等一個數字：

```zsh
while (( ${#digits} < maxlen )); do
  if ! read -r -k 1 -s -t "${GWT_DIGIT_TIMEOUT:-0.4}" more; then
    break
  fi
  if [[ $more == [0-9] ]]; then
    digits="${digits}${more}"
    (( 10#$digits * 10 > _GWT_COUNT )) && break   # 再加一位就爆了，不用等
  else
    [[ -n $more ]] && _GWT_PENDING_KEY=$more       # 交回主迴圈處理
    break
  fi
done
```

三個細節：

1. 9 筆以內完全沒有等待，跟原本一樣即時。
2. 若已輸入的數字再加一位就會超過總數（例如 12 筆時輸入 `9`），立刻結束等待，不必白等 0.4 秒。
3. 等待期間如果按下的是 `j`、`k`、`q`、Enter 之類的按鍵，會放進 `_GWT_PENDING_KEY` 交回主迴圈，不會被吃掉。

## 11. 狀態集中在 `_GWT_*`，邏輯拆成小函式

原文是一支大函式，`_gwt_draw` 直接定義在裡面並依賴外層的區域變數。這樣寫能動，但沒辦法單獨測試「porcelain 解析對不對」或「某一列長什麼樣」。

拆開之後，每個函式只做一件事，狀態放在 `_GWT_` 開頭的變數：

| 函式                             | 職責                                   |
| -------------------------------- | -------------------------------------- |
| `_gwt_collect` / `_gwt_collect_one` | 解析 porcelain、套用關鍵字篩選      |
| `_gwt_format_row` / `_gwt_draw` / `_gwt_header` | 組出單列文字、表頭、重繪整個選單 |
| `_gwt_fuzzy_term` / `_gwt_fuzzy_match` / `_gwt_refilter` | 模糊比對與排序          |
| `_gwt_pick` / `_gwt_pick_number` / `_gwt_shift` / `_gwt_read_escape` | 讀鍵、移動、數字跳轉、Esc 序列解析 |
| `_gwt_clip_middle` / `_gwt_swidth` / `_gwt_strip_ansi` | 欄寬計算與截斷 |
| `_gwt_finish`                    | 收尾（移除 trap、擦畫面、還原游標）    |
| `gwt`                            | 參數解析、檢查環境、最後 `cd`          |

唯一進入使用者命名空間的只有 `gwt` 這一個名字。`_gwt_collect` 直接從 stdin 讀 porcelain，測試因此可以餵一段固定的文字進去，不需要真的建立儲存庫。

## 12. 取消回傳 1，不是 0

原文的 `q`／`Esc` 分支回傳 `0`。本專案改成 `1`：

- 「取消」不是成功，`gwt && deploy` 這種寫法不該在使用者按 `q` 之後繼續跑
- 與 `Ctrl+C`（130）、找不到（1）、未知選項（2）一起看，語意一致

這是刻意的行為變更，`tests/cases-pty/06-cancel-q.zsh` 與 `07-cancel-esc.zsh` 都把它固定下來。

## 13. 用 `emulate -L zsh` 開場

使用者的 `~/.zshrc` 可能開了 `ksh_arrays`（陣列從 0 起算）、`nounset`、`shwordsplit` 之類的選項，這些都會讓原本的程式碼行為改變或直接報錯。

`emulate -L zsh` 在函式內把選項重設成 zsh 預設值，離開函式後自動還原使用者的設定，是寫 zsh 函式時最省事的自我保護。另外 `setopt local_options no_nomatch` 避免沒對到東西的 glob 直接讓函式報錯中斷。

## 14. 測試為什麼一定要 PTY

`gwt` 會檢查 stdin/stdout 是否為終端機，因為選單需要游標控制；而 zsh 的 `read -k` 在管線上會直接失敗：

```sh
printf '12' | zsh -f -c 'read -r -k1 a; print $a'
# read: not interactive and can't open terminal
```

所以互動測試用 `tests/lib/ptydrive.py` 開一個真正的 pseudo-terminal。這支小工具做兩件關鍵的事：

1. 用 `pty.fork()` 讓子行程的 stdin/stdout/stderr 都接上 PTY
2. **等輸出靜止 0.3 秒才送按鍵**。如果只是「啟動後等 0.3 秒」，在慢一點的機器上按鍵可能比選單更早抵達，就會被終端機的行緩衝吃掉，測試變成隨機失敗。

它同時把子行程的結束碼原樣傳回來，所以測試檔只要照平常寫 `zsh -f 測試檔`，用結束碼表示結果即可。

## 15. 清單比畫面高時：視窗化，而不是一路往上捲

原本的重繪是「往上移 `count` 行，再把所有項目重畫一次」。這在清單放得進畫面時
完全正確，但只要 `表頭 + 項目數` 超過終端機高度就會壞掉，而且壞得很難懂。

### 症狀

- 按下 ↓，光棒好像消失了，畫面只看到清單的尾巴
- 表頭不見了
- 偶爾會看到某一列重複出現

### 根因

`\e[<n>A`（游標往上移 n 行）在畫面頂端會被**夾住**：真實終端機不可能把游標移到
第 0 列以上。所以當程式以為自己回到選單第一列、實際上還停在下面時，重畫就會
從錯的位置開始，接著寫入超過畫面高度又不斷上捲，整段區塊就越飄越遠。

實測（60 筆 / 40 列，按 3 次 ↓）：每次重繪都送出 `\e[60A`，但終端機只能上移 39 行，
最後畫面只剩 `23-60`，表頭消失，光棒（第 4 筆）根本不在畫面上。

### 第二個根因：假設「一筆一列」

重繪的行數計算建立在「每個項目剛好佔一個實體行」這個假設上。只要有一行比終端機
還寬，終端機就會自動折行，實體行數變多，往上移 n 行就會少移，於是上面那一列
沒有被覆蓋、下面又多畫一次——這就是「第一列重複出現」。

實測（2 筆、40 欄、分支名很長）：

```
INDEXES=1-2,1-2      ← 每一筆都出現兩次
DUPLICATES=1-2
```

同一種偏移也會讓收尾的擦除少擦一行，選完之後畫面上留下表頭的第一行。實測
（48 欄終端機）：

```
請選擇 Worktree (↑/↓ 移動, Enter 確認, 按 1-12 直接跳轉, q/E
AFTER=/path/to/twelve-w01        ← 上一行是殘影
```

### 解法

**一、把畫面高度納入計算（視窗化）**

維持一個不變量：

```
表頭(1) + 可視列 + 提示列(0 或 1) + 游標那一列(1) ≤ 終端機高度
```

所以清單放得下時就全部畫；放不下時只畫 `高度 - 3` 列，並多畫一列範圍提示
（`顯示 8-16，共 40 筆`）。`_gwt_top` 會跟著選取項目移動，確保光棒永遠在視窗內：

```zsh
if (( _GWT_SELECTED < _GWT_TOP )); then
  _GWT_TOP=$_GWT_SELECTED
elif (( _GWT_SELECTED > _GWT_TOP + _GWT_VISIBLE - 1 )); then
  _GWT_TOP=$(( _GWT_SELECTED - _GWT_VISIBLE + 1 ))
fi
```

往上移的距離也從「項目總數」改成「這次實際畫了幾列」（`_GWT_DRAWN`），
兩者相等時行為跟原本一樣。

**二、保證每一列都是實體一行**

- 表頭：用 `_gwt_clip_middle` 裁到終端機寬度，窄視窗時不會折行。
- 項目列：先把「後方資訊」的預算算出來（`[分支] (commit) (目前位置)`），
  不夠就裁分支名稱，剩下的才給路徑，並保留至少 12 欄給路徑。這樣
  `前綴 + 路徑 + 間隔 + 後方資訊` 一定 ≤ 寬度。
- 寬度本身留一欄餘裕（`w - 1`），避免內容剛好佔滿最後一欄時觸發自動換行。

**三、量尺寸用 `stty size`**

`COLUMNS`／`LINES` 是環境變數，可能過期（例如在 tmux 換過 pane 大小），
`tput` 也可能被這兩個變數影響。`stty size` 直接問終端機，一次拿到高度與寬度。
仍然保留 `GWT_WIDTH`／`GWT_HEIGHT` 覆寫，方便測試與特殊需求。

### 怎麼驗

錯誤只會出現在「最終畫面」上，不會出現在 stdout 的文字裡，所以測試要重播
ANSI 序列。`tests/lib/screen.py` 只支援 gwt 會用到的那幾種序列（游標上下移動、
清除行、清除畫面、SGR），把 PTY 輸出重播成畫面後再列出結構摘要：

```
ITEM_ROWS=9
INDEXES=8-16
DUPLICATES=-
SELECTED=16
```

測試檔用 `# GWT_ROWS:` / `# GWT_COLS:` 指定終端機大小，再用
`# GWT_SCREEN_EXPECT:` 對摘要或畫面內容比對。這三個迴歸測試在修正前
都會失敗（`INDEXES=30-40`、`DUPLICATES=1-2`、殘影），修正後才通過。

## 16. 選單內的模糊搜尋

目標是「挑選時按 `/` 就開始打字」，不必先離開選單、重新執行 `gwt 關鍵字`。
比對範圍刻意縮小到兩處：

- 分支名稱
- 路徑的最後一層目錄（`${path:t}`）

### 為什麼不比對完整路徑

命令列關鍵字是「路徑 + 分支」的**子字串**比對，因為那時使用者是在刻意縮小
候選清單。互動搜尋若沿用完整路徑，`/Users/will/projects/` 這類共同前綴會讓
幾乎每一筆都符合，查詢反而失去意義。只留目錄名稱也符合挑選時的直覺：
大家記得的是 `shop-feature-login`，不是前面那一長串。

### 子序列比對與排序

`_gwt_fuzzy_term` 用子序列比對：查詢的每個字元依序出現在候選字串中就命中，
所以 `flogin` 找得到 `feature/login`。分數規則是：

- 每個命中字元 +10
- 連續命中額外加分，而且連得越長加得越多
- 字首，或 `/ - _ . 空白` 之後的命中再加 10
- 跳過的字元扣分（最多扣 4，避免長名稱一面倒）
- 候選字串越長扣一點分，短的、精準的排前面

查詢含空白時切成多個詞，每個詞都必須命中分支或目錄名稱（AND）。分數排序用
固定寬度的排序鍵搭配 zsh 的 `${(@O)array}`：分數遞減、原始索引遞增，所以同分
時仍維持 Git 的順序。這裡不能用 `(@Oa)`——`a` 是「依陣列索引」排序，會把整份
清單反過來。

互動搜尋以命令列關鍵字篩選後的清單為母體（`_GWT_ALL_*`）。`_gwt_refilter`
只重建顯示用的 `_GWT_PATHS`，所以刪除字元或清空查詢時能完整還原，不會愈搜
愈少。

### 按鍵與畫面

搜尋模式是獨立的輸入狀態，`q`、`j`、`k`、數字都只是一般字元。`Esc` 在搜尋模式
裡只清除查詢並回到完整清單，要取消選單得先離開搜尋。`Backspace` 刪一字、
`Ctrl+U` 清空、`Ctrl+W` 刪最後一個詞；`↑`／`↓` 與 `Enter` 行為不變。

表頭會因查詢而改變，所以每次重繪都要連表頭一起畫（`_gwt_repaint` 會往上移
`_GWT_DRAWN + 1` 行）。表頭先用 `\r\e[2K` 清整列，查詢變短時才不會留下殘影。
移動到表頭後還要 `\e[J` 清到畫面結尾：搜尋會讓清單變短，上一輪比較長的列還
留在游標下方，只畫新的列會讓人以為清單沒有跟著篩選。沒有符合項目時清單區
改畫一行提示，`_GWT_DRAWN` 仍然要算 1，收尾的擦除才不會少擦。

### 網站的示範選單

首頁 `#how` 的互動選單是 `site/assets/app.js` 模擬的，現在也支援 `/`。
`fuzzyTerm`／`fuzzyMatch` 刻意與 `_gwt_fuzzy_term` 用同一套規則（子序列、
連續命中、分隔符加成、長度懲罰），查詢以空白切成多詞 AND，排序同分時維持
原順序；差別只在 JavaScript 沒有 zsh 的 `${(@O)}`，改用穩定的 `sort`。

按鍵也對齊：`↑`／`↓` 移動、`Enter` 切換、`Backspace` 刪字、`Ctrl+U` 清空、
`Ctrl+W` 刪最後一詞；`q`、`j`、`k`、數字在搜尋模式都只是查詢字元。`Esc` 先
清除搜尋，第二次才回到示範的第一個階段。沒有結果時清單區顯示一行提示，
`Enter` 不會動作。

這份邏輯是 `make test` 之外的另一份實作（需要瀏覽器），改動時兩邊要一起看；
目前用 Chrome 在 1280px 與 390px 實際操作過搜尋、排序、方向鍵、Esc、Backspace、
Ctrl+U、多詞與無結果狀態。

### Esc 解析順序

原本用 `read -k 2` 判斷 `\e[A`／`\e[B`，但使用者按 `Esc` 後若馬上按 `Enter`，
`Enter` 會被當成序列的第二個字元吃掉，導致「清除搜尋後按 Enter 沒反應」。
`_gwt_read_escape` 改成逐字元讀：先讀一個字元，是 `[` 或 `O` 才再讀方向鍵；
其他字元放進 `_GWT_PENDING_KEY` 交回主迴圈。`tests/cases-pty/18-search-esc-clears`
把這個情境固定下來。

## 附錄：文章中刻意保留的行為

以下行為與原文完全一致，不是忘記改：

- 光棒只反白到路徑，後面的分支與 commit 維持原色
- 目前位置用黃色標註
- 迴圈式的上下移動（到頭尾會繞回另一端）
- 關鍵字比對範圍是「路徑 + 分支」整串，短關鍵字可能命中多筆
- 單筆符合時不顯示選單，直接切換
- 選單提示會依實際數量印出「按 1-N 直接跳轉」
