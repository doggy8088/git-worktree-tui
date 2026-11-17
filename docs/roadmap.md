# 後續開發方向

這裡記錄還沒做、但值得做的事，順序大致代表優先度。歡迎直接開 issue 討論或認領。

## 近期（不改架構就能做）

### 1. `gwt -` 回到上一個 worktree

像 `cd -` 一樣。作法是每次成功切換時把前一個路徑寫進 shell 變數（`_GWT_PREV`），`gwt -` 直接跳回去。

要注意的是「前一個」的定義：從 A 切到 B 之後 `gwt -` 應該回 A；但如果使用者自己用 `cd` 離開，記錄就會過期。可以用 `$OLDPWD` 當輔助判斷。

### 2. zsh completion

```sh
gwt fea<TAB>   # 補出符合的 worktree 路徑
```

用 `_arguments` 寫一個 `_gwt`，把 `git worktree list --porcelain` 的結果轉成候選。需要另外一個檔案（例如 `_gwt`），並在 `install.sh` 裡處理 `fpath`。

### 3. 標示失效與鎖定的 worktree

`git worktree list --porcelain` 會輸出 `locked`、`prunable` 這類附註行。目前是直接忽略，之後可以在選單上標成灰色，或選到時提醒「這個目錄已經不存在，建議執行 `git worktree prune`」。

### 4. 顯示 dirty 狀態

在分支後面加一個 `*` 表示有未提交的變更。代價是每個 worktree 都要跑一次 `git status --porcelain`，worktree 一多就會慢；比較好的做法是只在 `GWT_SHOW_DIRTY=1` 時才做，或改成非同步（zsh 的 `zle -F` 可以做到，但複雜度會上升不少）。

### 5. 排序選項

目前順序完全照 Git 的輸出（依路徑排序）。可以加 `GWT_SORT=path|recent|branch`，用 `zstat` 讀目錄的 mtime 做「最近用過」排序。

## 中期（需要設計討論）

### 6. 整合 fzf

```sh
gwt --fzf    # 把清單交給 fzf，支援模糊比對
```

好處是搜尋能力立刻升級；壞處是多一個外部依賴，而且 fzf 的 `--height` 行為會影響畫面。比較合理的作法是把 fzf 當成「有裝就用」的選項，預設仍然是內建選單。

### 7. 建立與刪除 worktree

```sh
gwt add feature/login    # git worktree add ../repo-feature-login -b feature/login
gwt rm feature/login     # 先確認沒有未提交變更，再 git worktree remove
```

刪除涉及資料遺失風險，必須先檢查 `git status`，而且在有未提交變更時要明確要求 `--force`。這塊要有「絕不默默丟掉使用者工作」的設計原則。

### 8. 在 tmux 視窗之間跳轉

選到某個 worktree 時，開一個新視窗並 `cd` 過去，而不是改變目前視窗的目錄。適合把 worktree 當成「每個分支一個環境」的人。

### 9. 多選

一次選多個 worktree 開成多個 tmux 視窗或 pane。需要重做按鍵設計（例如空白鍵標記、Enter 確認），目前單選的模型會衝突。

## 長期（可能整個重寫）

### 10. 獨立執行檔（Go / Rust）

最大的動機是「跨 shell」與「跨平台」。但要解決一個根本問題：**獨立執行檔沒辦法改變呼叫端的工作目錄**。

可行的做法是讓執行檔只負責「選」，把結果印到 stdout，再由 shell 包裝函式接手 `cd`：

```sh
gwt() {
  local dir
  dir=$(command gwt --pick) || return $?
  [[ -n $dir ]] && builtin cd -- "$dir"
}
```

這樣就能兩邊都要：用 Go/Rust 寫 TUI（畫面、按鍵、模糊搜尋都好做很多），shell 端只留三行。`--list` 其實已經是這個模式的雛形。

### 11. bash 版本

要改的地方：`read -k 1` → `read -n 1`、陣列索引從 0 起算、`printf '\e[%dA'` 的換行行為要重測。與其維護兩份，不如先做第 10 項。

### 12. Windows

PowerShell 版本的等價物是 `Set-Location`，但 ANSI 序列、終端機模式、按鍵讀取都要重寫。目前沒有計畫。

## 明確不做

- **寫成獨立腳本卻期待它能 `cd`**：這在 shell 模型上不可能，只能靠 `source` 或包裝函式。
- **自動執行 `git worktree prune`**：會刪掉使用者可能還想救的目錄，這種破壞性操作不該藏在選單工具裡。
- **為了美觀引入 TUI 框架**：目前的 ANSI 重繪已經足夠，多一層依賴只會讓安裝變麻煩。
