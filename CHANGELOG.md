# 版本記錄

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本號參考 [Semantic Versioning](https://semver.org/lang/zh-TW/)。

## [1.0.0] - 2026-11-17

第一個公開版本：把部落格文章裡的 `gwt` 函式整理成可維護、有測試的專案。

### 新增

- `gwt.zsh`：互動式 worktree 切換器，方向鍵／`j`／`k` 移動、數字鍵直接跳轉、`Enter` 切換、`q`／`Esc` 取消、`Ctrl+C` 中斷。
- 關鍵字篩選，比對「路徑 + 分支名稱」，只剩一筆符合時直接切換。
- `--list`：只印出符合的 worktree 路徑，方便接給其他工具。
- `--help`、`--version`。
- 設定項：`GWT_LANG`、`GWT_CLEAR_ON_EXIT`、`GWT_FILTER_CASE_INSENSITIVE`、`GWT_DIGIT_TIMEOUT`、`GWT_ESC_TIMEOUT`、`GWT_NO_COLOR`、`GWT_WIDTH`。
- `GWT_LANG=en` 英文介面。
- `gwt.plugin.zsh`：oh-my-zsh、antigen、zinit、sheldon、zplug 等 plugin manager 的進入點。
- `install.sh`：安裝到 `~/.zsh/gwt.zsh` 並在 `~/.zshrc` 加入 source，支援 `--uninstall`，可重複執行。
- `Makefile`：`help`、`test`、`lint`、`install`、`uninstall`、`demo`、`clean`。
- `scripts/demo.sh`：建立含 5 個 worktree 的示範儲存庫。
- 測試框架：21 個測試（10 個單元 + 11 個 PTY 互動），含 fixture 產生器與 PTY 按鍵驅動程式。
- 文件：`README.md`、`docs/design-notes.md`（每個設計決定的理由）、`docs/roadmap.md`。

### 變更

- 取消（`q`／`Esc`）的結束碼從 `0` 改為 `1`，讓「取消」不會被當成成功。
- 選單離開後預設擦掉，不再留在捲動緩衝區；`GWT_CLEAR_ON_EXIT=0` 可保留原文行為。
- 關鍵字比對預設不分大小寫；`GWT_FILTER_CASE_INSENSITIVE=0` 可改回區分大小寫。
- worktree 超過 9 個時，數字鍵支援多位數（按 `1` `2` 跳到第 12 筆）。
- 過長路徑依終端機欄寬從中間截斷（保留較有用的尾段），避免折行造成重繪錯位。
- 進入函式時執行 `emulate -L zsh`，不受使用者既有的 shell 選項影響。
- Repo 偵測改用 `git rev-parse --git-dir`，bare repo 也能執行。
- 分支與路徑改用 `%s` 輸出，不再使用 `%b`。

### 修正

- `Ctrl+C` 的結束碼：zsh 在 trap 內執行 `return 130` 時回傳值不保證是 130（實測會變成 0 或 1），改用 `_GWT_INTERRUPTED` 旗標判斷，確保一律回傳 130。
- 分支名稱含 `%` 或反斜線時，原本用 `%b` 會被當成格式字串或跳脫序列解讀；改為原樣輸出。
- `_GWT_COUNT` 原本只在 `gwt` 內設定，單獨呼叫 `_gwt_collect` 時不會更新。
- `Makefile` 的 `ZSH` 變數與 oh-my-zsh 的 `$ZSH`（安裝目錄）衝突，導致 `make lint` 失敗；改名為 `ZSHBIN`。

[1.0.0]: https://github.com/doggy8088/git-worktree-tui/releases/tag/v1.0.0
