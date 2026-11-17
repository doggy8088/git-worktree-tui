# git-worktree-tui

[![CI](https://github.com/doggy8088/git-worktree-tui/actions/workflows/ci.yml/badge.svg)](https://github.com/doggy8088/git-worktree-tui/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

用 zsh 寫的 Git Worktree 互動式切換工具：一個指令列出所有 worktree，用方向鍵、`j`／`k` 或數字鍵選好，按下 Enter 就直接 `cd` 過去。

```
請選擇 Worktree (↑/↓ 移動, Enter 確認, 按 1-5 直接跳轉, q/Esc 取消)：
 > [1] …/shop              [main] (89ae97a) (目前位置)
   [2] …/shop-feature-login       [feature/login] (89ae97a)
   [3] …/shop-feature-search-api  [feature/search-api] (89ae97a)
   [4] …/shop-fix-cart-bug        [fix/cart-bug] (89ae97a)
   [5] …/shop-hotfix              [detached] (89ae97a)
```

被選中的那一列會用青色光棒反白，而且只反白到路徑為止，後方的分支名稱與 commit 雜湊維持原色；目前所在的 worktree 用黃色標註「目前位置」。

Worktree 一多，真正花時間的從來不是 Git 指令，而是「`git worktree list` → 找到路徑 → 複製 → 貼到 `cd` 後面」這串動作。這個工具把這件事收斂成一次按鍵。

> 專案源自 Will 保哥的部落格文章：[用 zsh 寫一個 TUI 小工具 gwt：在命令列快速切換 Git Worktree 資料夾](https://blog.miniasp.com/post/2026/10/31/gwt-zsh-tui-switch-git-worktree)。文章的原始版本是一段貼進 `~/.zshrc` 的函式，這裡把它整理成有測試、有文件、可以持續改的專案，並修掉幾個實測後才發現的問題（詳見[與原文的差異](#與原文的差異)）。

## 需求

- zsh 5.8 以上（macOS 內建的 zsh、Homebrew 安裝的 zsh 都可以）
- Git 2.7 以上（`git worktree` 從 2.5 開始提供，`list --porcelain` 從 2.7 開始）

刻意只依賴 zsh 與 git，沒有 fzf、沒有額外的套件管理器。

## 安裝

### 方式一：安裝腳本（推薦）

```sh
git clone https://github.com/doggy8088/git-worktree-tui.git
cd git-worktree-tui
bash install.sh
```

腳本會把 `gwt.zsh` 複製到 `~/.zsh/gwt.zsh`，並在 `~/.zshrc` 加入：

```sh
# >>> gwt (git-worktree-tui) >>>
source ~/.zsh/gwt.zsh
# <<< gwt (git-worktree-tui) <<<
```

只有這一段是腳本產生的，其餘內容原封不動；重複執行不會重複加行。移除時執行 `bash install.sh --uninstall`，或 `make install` / `make uninstall`。

### 方式二：手動

把 `gwt.zsh` 放到你喜歡的位置，在 `~/.zshrc` 加一行：

```sh
source ~/path/to/gwt.zsh
```

再開一個新的終端機，或執行 `source ~/.zshrc`。

### 方式三：zsh plugin manager

`gwt.plugin.zsh` 是給 oh-my-zsh 自訂 plugin、antigen、zinit、sheldon、zplug 這類工具用的進入點，它只負責 `source` 同目錄的 `gwt.zsh`。

以 oh-my-zsh 為例：

```sh
git clone https://github.com/doggy8088/git-worktree-tui.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/gwt
```

然後在 `~/.zshrc` 的 `plugins=(...)` 加入 `gwt`。

## 用法

在任何一個 Git 儲存庫（或它的任何 worktree、子目錄）裡執行：

```sh
gwt
```

| 按鍵            | 行為                                     |
| --------------- | ---------------------------------------- |
| `↑` / `↓`       | 上下移動，到頭尾會循環                   |
| `k` / `j`       | 跟 Vim 一樣的上下移動                    |
| `1` 到 `9`      | 直接跳到該編號並切換，不需要再按 Enter   |
| `Enter`         | 切換到目前反白的 worktree                |
| `q` / `Esc`     | 取消，維持原本的工作目錄                 |
| `Ctrl+C`        | 中斷，並把隱藏的游標恢復回來             |

### 關鍵字篩選

關鍵字會比對「路徑 + 分支名稱」整串文字，只要包含就算符合：

```sh
gwt feature        # 只列出路徑或分支含 feature 的 worktree
gwt cart           # 只剩一筆符合時，不顯示選單，直接 cd 過去
gwt fix login      # 多個關鍵字會以空白串接後一起比對
```

預設不分大小寫，可以用 `GWT_FILTER_CASE_INSENSITIVE=0` 改成區分大小寫。

需要留意的是，關鍵字比對範圍包含路徑，所以 `gwt fix` 這種短關鍵字也可能命中 `shop-hotfix`；這不是 bug，只是關鍵字太短時要有心理準備。

### 只列出路徑

```sh
gwt --list         # 每行一筆完整路徑，方便接給其他工具
gwt --list feature | head -1
```

### 其他選項

| 選項            | 說明                       |
| --------------- | -------------------------- |
| `-l`, `--list`  | 只列出符合的 worktree 路徑 |
| `-h`, `--help`  | 顯示說明                   |
| `-V`, `--version` | 顯示版本                 |

## 設定

全部都是環境變數，可以 `export` 在 `~/.zshrc`，或 source 之後再改。預設值如下：

| 變數                            | 預設  | 說明                                                     |
| ------------------------------- | ----- | -------------------------------------------------------- |
| `GWT_LANG`                      | `zh`  | 介面語言，可設 `en`                                      |
| `GWT_CLEAR_ON_EXIT`             | `1`   | 離開時擦掉選單；設 `0` 會留在畫面上（原文行為）           |
| `GWT_FILTER_CASE_INSENSITIVE`   | `1`   | 關鍵字不分大小寫；設 `0` 則區分                           |
| `GWT_DIGIT_TIMEOUT`             | `0.4` | 多位數編號的等待秒數，worktree 超過 9 個時才會用到         |
| `GWT_ESC_TIMEOUT`               | `0.05`| 判斷「單獨一個 Esc」與方向鍵的等待秒數                     |
| `GWT_NO_COLOR`                  | `0`   | 設 `1` 關閉顏色；設定 `NO_COLOR` 環境變數也有同樣效果      |
| `GWT_WIDTH`                     | `0`   | 選單欄寬，`0` 表示自動偵測終端機寬度                       |

範例：

```sh
GWT_LANG=en
GWT_CLEAR_ON_EXIT=0
GWT_FILTER_CASE_INSENSITIVE=0
```

## 結束碼

| 情況                       | 結束碼 |
| -------------------------- | ------ |
| 選定並切換成功             | `0`    |
| 只有一筆符合，直接切換     | `0`    |
| 按 `q`／`Esc` 取消         | `1`    |
| 找不到符合的 worktree      | `1`    |
| 不在 Git 儲存庫            | `1`    |
| 需要互動式終端機時卻沒有   | `1`    |
| `Ctrl+C` 中斷              | `130`  |
| 未知的選項                 | `2`    |

## 與原文的差異

原始版本的設計與行為都保留，以下幾點是整理成專案時改掉的，理由都寫在 [docs/design-notes.md](docs/design-notes.md)：

| 項目                 | 原文                        | 本專案                                              |
| -------------------- | --------------------------- | --------------------------------------------------- |
| 取消的結束碼         | `0`                         | `1`（取消不是成功，`gwt && ...` 不該繼續）           |
| 數字鍵               | 只支援 `1`–`9`              | 超過 9 筆時支援多位數（按 `1` `2` 跳到第 12 筆）      |
| 離開後的畫面         | 選單留在捲動緩衝區          | 預設擦掉，`GWT_CLEAR_ON_EXIT=0` 可保留                |
| 長路徑               | 直接折行，重繪會錯位        | 依終端機欄寬從中間截斷（CJK 全形字算兩欄）            |
| 大小寫               | 區分大小寫                  | 預設不分，可關閉                                     |
| 分支含 `%` 或反斜線  | 用 `%b` 印出，可能被解讀    | 改用 `%s` + 事先組好的跳脫字串，原樣輸出              |
| 介面語言             | 只有中文                    | `GWT_LANG=en` 可切換                                 |
| 顏色                 | 固定開啟                    | 支援 `NO_COLOR`／`GWT_NO_COLOR`                      |
| 其他指令             | 只有互動選單                | 另有 `--list`、`--help`、`--version`                 |
| bare repo            | 不支援                      | 可以執行（沒有工作目錄，所以不會標「目前位置」）      |
| shell 選項衝突       | 使用者開了 `ksh_arrays` 等會壞 | 進入時 `emulate -L zsh`，不受使用者選項影響          |

## 已知限制

- **只能在 zsh 使用**：用到 `read -k`（讀單一按鍵）與從 1 開始的陣列索引。要在 bash 用需要改寫成 `read -n 1` 與 0 起算索引。
- **選單高於終端機時會錯位**：重繪靠「游標往上移 N 行」計算，如果 worktree 數量超過終端機可見行數，畫面會不準。這種情況建議搭配關鍵字篩選。
- **視窗縮放不會重算寬度**：欄寬在啟動時偵測一次，選單開著的時候改變視窗大小不會重新排版。
- **多位數編號有等待感**：超過 9 筆時，按單一數字要等 `GWT_DIGIT_TIMEOUT` 才知道你是不是要按第二位數。
- **篩選是子字串比對**：沒有模糊比對，也不吃正規表示式。需要更強的搜尋可以考慮接 `fzf`。
- **不會自動清理失效的 worktree**：目錄被砍掉但沒 `git worktree prune` 的話，清單裡還是會出現。

## 開發

```sh
make help      # 列出所有指令
make test      # 執行全部測試（單元 + PTY 互動）
make lint      # zsh -n 語法檢查 + python 編譯檢查
make demo      # 建一個含 5 個 worktree 的示範儲存庫
make install   # 安裝到 ~/.zsh/gwt.zsh
make clean     # 清除暫存產物
```

測試需要 zsh、git 與 `python3`（互動測試要開 PTY）。沒有 python3 時，互動測試會自動略過並在結尾提示。

```sh
make test
# 建立測試資料 ...
#
# 單元測試（不需要終端機）
#   通過  01-collect-porcelain.zsh
#   ...
# 互動測試（PTY）
#   通過  01-arrow-down-enter.zsh
#   ...
# ========================================
# 通過 21，失敗 0
```

想看某個測試在幹嘛，例如 Ctrl+C 的處理：

```sh
GWT_ROOT=$PWD GWT_FIXTURE=/tmp/fx bash tests/fixtures/build.sh /tmp/fx
python3 tests/lib/ptydrive.py --keys '\x03' --out /tmp/out.bin -- zsh -f tests/cases-pty/08-ctrl-c.zsh
```

### 專案結構

```
git-worktree-tui/
├── gwt.zsh                  # 函式本體（唯一需要載入的檔案）
├── gwt.plugin.zsh           # plugin manager 進入點
├── install.sh               # 安裝／移除腳本
├── Makefile                 # help / test / lint / install / demo / clean
├── docs/
│   ├── design-notes.md      # 每個設計決定的理由
│   └── roadmap.md           # 後續想做的事
├── scripts/
│   └── demo.sh              # 建立示範儲存庫
└── tests/
    ├── run.sh               # 測試入口
    ├── cases/               # 單元測試（不需要終端機）
    ├── cases-pty/           # 互動測試（需要 PTY）
    ├── fixtures/build.sh    # 測試資料產生器
    └── lib/                 # 斷言、fixture 工具、PTY 驅動程式
```

## 授權

[MIT](LICENSE)，著作權人 Will 保哥 (Will Huang)。
