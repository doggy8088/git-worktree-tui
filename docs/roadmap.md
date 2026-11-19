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

### 5a. zsh 版：把 PowerShell 版 code review 找到的問題補回來

PowerShell 版開發與 code review 時，發現 `gwt.zsh` 的程式碼有下面四個同樣的結構。PowerShell 版都已修正並有
重現的測試（[design-notes 第 17.6、17.9 節](design-notes.md)）。**下面是對照 `gwt.zsh` 讀程式碼得到的結論，沒有
實際在 zsh 上重現**（寫 PowerShell 版時沒有 zsh 可跑），動手前先用 PTY 測試確認：

1. **多位數編號的第一位數不必等待。** [design-notes 第 10 節](design-notes.md) 寫「若已輸入的數字再加一位就會超過
   總數，立刻結束等待」，但 `_gwt_pick_number` 是讀到第二位數「之後」才判斷，所以第一位數一律要等滿
   `GWT_DIGIT_TIMEOUT`：12 筆時按 `9` 明明不可能再接第二位數，仍然白等 0.4 秒。在 `while` 迴圈開頭加一行
   `(( 10#$digits * 10 > _GWT_COUNT )) && break` 即可。
2. **被忽略的數字會弄掉目前的選取。** `_gwt_pick_number` 無條件 `_GWT_SELECTED=$(( 10#$digits ))`；5 筆時按 `9`
   被主迴圈忽略，但 `_GWT_SELECTED` 已經是 9：光棒消失、Enter 回傳失敗。應該先確認在範圍內才指定。
3. **等第二位數時收到的 `Ctrl+C` 位元組會被丟掉。** 一般情況下 `Ctrl+C` 是 SIGINT，由 `INT` trap 處理，不受影響；
   但終端機關掉 `ISIG`、`Ctrl+C` 以 `$'\x03'` 進來時（主迴圈另外處理過這種情況），`_gwt_pick_number` 會把它放進
   `_GWT_PENDING_KEY`，之後數字有效就直接 `return 0`，沒人看那個按鍵。`_gwt_pick_number` 回來後要先檢查它。
4. **很窄的終端機會折行。** 一列至少要 26 欄，而寬度下限是 24（`(( w < 24 )) && w=24`）；放不下時要依序省略
   commit、分支，不能硬把路徑夾到 4 欄。
5. **欄寬表缺了「基本多文種平面裡寬度為 2 的 emoji 符號」。** `_gwt_swidth` 只有 CJK 與全形的範圍，`⚡ ⌚ ✅ ⭐`
   （U+26A1、U+231A、U+2705、U+2B50 等，East Asian Width 是 W）被當成 1 欄；分支或路徑含這些符號時，在把它們
   畫成 2 欄的終端機上一列會比算出來的寬而折行。PowerShell 版已補上完整的範圍（[design-notes 17.12](design-notes.md)），
   `site/assets/app.js` 的示範選單如果也算欄寬，同樣要看。zsh 的 `[$'⺀'-$'꓏']` 這種字元範圍比對要補的範圍
   不少，建議照 `tests/pwsh/lib/WidthOracle.ps1` 的逐字清單先寫測試。

每一項都要補測試：1 用「按 `9` 的耗時」，2 用 PTY 送 `9\n`，3 要先把 PTY 的 `ISIG` 關掉再送 `1\x03`，
4 用 25 欄的 PTY 重播畫面檢查沒有重複的列。

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

**PowerShell 7（`pwsh`）版已完成**：`gwt.psm1` 與 `install.ps1`，設計與踩過的坑見
[design-notes 第 17 節](design-notes.md)。還沒做的：

- **Windows PowerShell 5.1**：內建的藍色那個。主控台預設不吃 VT 序列、預設編碼是 ANSI、沒有三元運算子與 `&&`，
  不是改幾行的事；目前明確不支援（安裝腳本在 5.1 裡會請使用者改用 `pwsh`）。
- **發佈到 PowerShell Gallery**：流程已建好（`gwt.psd1`、`tools/Build-PSGalleryPackage.ps1`、
  `.github/workflows/publish-psgallery.yml`，見 [publishing.md](publishing.md)），第一次發佈需要維護者先在
  Gallery 建立 API key、在 GitHub 建立 `psgallery` 環境。PowerShell Gallery **不支援 Trusted publishing（OIDC）**，
  所以用 API key；追蹤 [PowerShell/PowerShellGallery#353](https://github.com/PowerShell/PowerShellGallery/issues/353)，
  支援之後換掉 workflow 裡取得憑證的那一步，並刪掉 key 與 GitHub 的祕密。
- **macOS／Linux 的 `pwsh`**：程式本身沒有 Windows 專屬 API，理論上能跑，但沒驗證也沒有 CI。
  要支援的話先把 `tests/pwsh/run.ps1` 掛上 ubuntu／macos 的 CI 看哪些測試會紅。
- **`cmd.exe`、fish**：沒有計畫。Git Bash 底下的 zsh／bash 見第 11 項。

## 明確不做

- **寫成獨立腳本卻期待它能 `cd`**：這在 shell 模型上不可能，只能靠 `source` 或包裝函式。
- **自動執行 `git worktree prune`**：會刪掉使用者可能還想救的目錄，這種破壞性操作不該藏在選單工具裡。
- **為了美觀引入 TUI 框架**：目前的 ANSI 重繪已經足夠，多一層依賴只會讓安裝變麻煩。
