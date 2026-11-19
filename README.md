# git-worktree-tui

[![CI](https://github.com/doggy8088/git-worktree-tui/actions/workflows/ci.yml/badge.svg)](https://github.com/doggy8088/git-worktree-tui/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

網站：<https://gwt.gh.miniasp.com>（示範選單可以直接用鍵盤操作，按 `/` 也能模糊搜尋）

Git Worktree 互動式切換工具，有 zsh 版與 PowerShell 7（`pwsh`）版：一個指令列出所有 worktree，用方向鍵、`j`／`k` 或數字鍵選好，按下 Enter 就直接 `cd`（PowerShell 裡是 `Set-Location`）過去。

```
請選擇 Worktree (↑/↓ 移動, Enter 確認, 按 1-5 直接跳轉, q/Esc 取消)：
 > [1] …/shop              [main] (89ae97a) (目前位置)
   [2] …/shop-feature-login       [feature/login] (89ae97a)
   [3] …/shop-feature-search-api  [feature/search-api] (89ae97a)
   [4] …/shop-fix-cart-bug        [fix/cart-bug] (89ae97a)
   [5] …/shop-hotfix              [detached] (89ae97a)
```

Worktree 很多、超過終端機高度時，選單只會顯示一段視窗，並在下方標示目前範圍（`顯示 8-16，共 40 筆`），選取項目會帶動視窗捲動。

被選中的那一列會用青色光棒反白，而且只反白到路徑為止，後方的分支名稱與 commit 雜湊維持原色；目前所在的 worktree 用黃色標註「目前位置」。

Worktree 一多，真正花時間的從來不是 Git 指令，而是「`git worktree list` → 找到路徑 → 複製 → 貼到 `cd` 後面」這串動作。這個工具把這件事收斂成一次按鍵。

> 專案源自 Will 保哥的部落格文章：[用 zsh 寫一個 TUI 小工具 gwt：在命令列快速切換 Git Worktree 資料夾](https://blog.miniasp.com/post/2026/10/31/gwt-zsh-tui-switch-git-worktree)。文章的原始版本是一段貼進 `~/.zshrc` 的函式，這裡把它整理成有測試、有文件、可以持續改的專案，並修掉幾個實測後才發現的問題（詳見[與原文的差異](#與原文的差異)）。

## 需求

任選一種 shell：

- zsh 5.8 以上（macOS 內建的 zsh、Homebrew 安裝的 zsh 都可以）
- PowerShell 7.0 以上（`pwsh`，在 Windows 上開發與驗證；Windows 內建的 Windows PowerShell 5.1 不支援，到 <https://aka.ms/powershell> 安裝 PowerShell 7）。實測只在 PowerShell 7.7 上做過：7.0 以 code review 與一個擋掉「.NET 5 以後才有的 API」的測試把關（7.0 跑在 .NET Core 3.1 上），沒有在 7.0 上實際執行過

另外都需要：

- Git 2.7 以上（`git worktree` 從 2.5 開始提供，`list --porcelain` 從 2.7 開始）

刻意只依賴 shell 與 git，沒有 fzf、沒有額外的套件管理器。

## 安裝

用 zsh（macOS、Linux）看 [zsh](#zsh)；用 PowerShell 7 的 Windows 使用者直接跳到 [PowerShell 7](#powershell-7)。

### zsh

#### 方式一：一行安裝（推薦）

```sh
curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash
```

要固定版本（例如發過 release 之後）：

```sh
curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash -s -- --version v0.1.0
```

腳本會把 `gwt.zsh` 放到 `~/.zsh/gwt.zsh`，並在 `~/.zshrc` 加入載入設定。移除時：

```sh
curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash -s -- --uninstall
```

在 clone 下來的專案裡也可以直接 `bash install.sh`（會用本地檔案，不連網）。

腳本會把 `gwt.zsh` 複製到 `~/.zsh/gwt.zsh`，並在 `~/.zshrc` 加入：

```sh
# >>> gwt (git-worktree-tui) >>>
source ~/.zsh/gwt.zsh
# <<< gwt (git-worktree-tui) <<<
```

只有這一段是腳本產生的，其餘內容原封不動；重複執行不會重複加行。移除時執行 `bash install.sh --uninstall`，或 `make install` / `make uninstall`。

#### 方式二：手動

把 `gwt.zsh` 放到你喜歡的位置，在 `~/.zshrc` 加一行：

```sh
source ~/path/to/gwt.zsh
```

再開一個新的終端機，或執行 `source ~/.zshrc`。

#### 方式三：zsh plugin manager

`gwt.plugin.zsh` 是給 oh-my-zsh 自訂 plugin、antigen、zinit、sheldon、zplug 這類工具用的進入點，它只負責 `source` 同目錄的 `gwt.zsh`。

以 oh-my-zsh 為例：

```sh
git clone https://github.com/doggy8088/git-worktree-tui.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/gwt
```

然後在 `~/.zshrc` 的 `plugins=(...)` 加入 `gwt`。

### PowerShell 7

給 Windows 上的 PowerShell 7（`pwsh`）。要用 PowerShell 7，不是 Windows 內建的藍色 Windows PowerShell 5.1；在 5.1 裡執行安裝腳本只會得到一行請你改用 `pwsh` 的訊息，不會安裝任何東西。

#### 方式一：一行安裝（推薦）

```powershell
irm https://gwt.gh.miniasp.com/install.ps1 | iex
```

裝完會直接載入到目前的視窗，馬上就能打 `gwt`；之後開的每個 PowerShell 7 視窗（包含 VS Code 的終端機）也都會載入。

要固定版本，`iex` 沒辦法帶參數，所以把腳本包成 scriptblock，或先設環境變數：

```powershell
& ([scriptblock]::Create((irm https://gwt.gh.miniasp.com/install.ps1))) -Version vX.Y.Z

# 或
$env:GWT_VERSION = 'vX.Y.Z'; irm https://gwt.gh.miniasp.com/install.ps1 | iex
```

`vX.Y.Z` 換成想固定的 release 標籤。PowerShell 版從 v0.2.0 起才有，所以 v0.1.0 沒有它，`-Version v0.1.0` 會明確失敗；沒指定版本時，腳本會安裝最新 release 的 `gwt.psm1`，如果最新的 release 還不含 PowerShell 版（例如 v0.2.0 發佈之前），會明說並改安裝 `main` 分支的最新版。

移除：

```powershell
& ([scriptblock]::Create((irm https://gwt.gh.miniasp.com/install.ps1))) -Uninstall
```

如果 `gwt.gh.miniasp.com` 連不上，同一支腳本也放在 GitHub：

```powershell
irm https://raw.githubusercontent.com/doggy8088/git-worktree-tui/main/install.ps1 | iex
```

在 clone 下來的專案裡也可以直接跑（會用本地的 `gwt.psm1`，不連網）：

```powershell
pwsh -File install.ps1              # 安裝
pwsh -File install.ps1 -Uninstall   # 移除
```

腳本會把 `gwt.psm1` 放到 `~\.gwt\gwt.psm1`，並在 `$PROFILE.CurrentUserAllHosts`（`profile.ps1`，所有 PowerShell 主機共用，所以 VS Code 的終端機也會載入）加入：

```powershell
# >>> gwt (git-worktree-tui) >>>
Import-Module "$HOME\.gwt\gwt.psm1"
# <<< gwt (git-worktree-tui) <<<
```

只有這一段是腳本產生的，其餘內容原封不動（編碼、BOM、換行都保持原樣）；重複執行不會重複加行，移除時會把這一段拿掉，並刪掉 `gwt.psm1`，profile 與安裝前逐位元組相同（原本就有的 profile，即使是空的、只有空白、沒有結尾換行或是 UTF-16／UTF-32 編碼，都會原樣還原；原本不存在而由腳本建立的 profile，移除時一併刪除）。任何一步失敗（例如模組檔被鎖住無法覆蓋或刪除）都會明確報錯並回傳 1，不會報告成功。profile 裡若還有別行也在載入 `gwt.psm1`，腳本會提醒你，但不會動它。腳本不會改 PowerShell 的執行原則；如果目前是 `Restricted` 或 `AllSigned`，它會警告開新視窗時 profile 不會被載入，並告訴你怎麼改（只影響你自己的帳號）：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

參數（用 `iex` 時沒有參數可用，改設右邊的環境變數；參數優先）：

| 參數           | 環境變數          | 說明                                                         |
| -------------- | ----------------- | ------------------------------------------------------------ |
| `-Version`     | `GWT_VERSION`     | 要安裝的 release 標籤                                        |
| `-Dir`         | `GWT_INSTALL_DIR` | 安裝目錄，預設 `~\.gwt`                                      |
| `-ProfilePath` | `GWT_PROFILE`     | 要寫入載入設定的 profile，預設 `$PROFILE.CurrentUserAllHosts` |
| `-Uninstall`   |                   | 移除                                                         |
| `-Help`        |                   | 顯示說明                                                     |

#### 方式二：PowerShell Gallery

gwt 也發佈在 [PowerShell Gallery](https://www.powershellgallery.com/packages/gwt)（從 v0.2.0 起）：

```powershell
Install-PSResource gwt                  # PowerShell 7.4 以上（內建 PSResourceGet）
Install-Module gwt -Scope CurrentUser   # PowerShell 7.0～7.3
```

第一次從 PSGallery 安裝時，可能會問你是否信任這個來源，回答 `Y` 即可。只裝在你自己的帳號底下，不需要系統管理員權限。

裝完不必改 profile：第一次打 `gwt` 時 PowerShell 會自動載入模組，連執行安裝的那個視窗也一樣。

更新與移除：

```powershell
Update-PSResource gwt       # PowerShell 7.0～7.3：Update-Module gwt
Uninstall-PSResource gwt    # PowerShell 7.0～7.3：Uninstall-Module gwt
```

**不要和方式一同時使用。** 方式一會在 profile 加一行 `Import-Module`，開新視窗時先載入 `~\.gwt` 的那一份，Gallery 裝的那一份就不會被用到，看起來會像「更新了卻沒變」。要換方式，先移除原本的：方式一用上面的 `-Uninstall`，方式二用 `Uninstall-PSResource gwt`。

#### 方式三：手動

把 `gwt.psm1` 放到你喜歡的位置，在 `$PROFILE.CurrentUserAllHosts` 加一行：

```powershell
Import-Module C:\path\to\gwt.psm1
```

再開一個新的終端機，或直接在目前的視窗執行同一行。

## 用法

在任何一個 Git 儲存庫（或它的任何 worktree、子目錄）裡執行：

```sh
gwt
```

| 按鍵            | 行為                                     |
| --------------- | ---------------------------------------- |
| `↑` / `↓`       | 上下移動，到頭尾會循環                   |
| `k` / `j`       | 跟 Vim 一樣的上下移動                    |
| `/`             | 進入模糊搜尋（分支名稱 + 最後一層目錄）  |
| `1` 到 `9`      | 直接跳到該編號並切換，不需要再按 Enter   |
| `Enter`         | 切換到目前反白的 worktree                |
| `q` / `Esc`     | 取消，維持原本的工作目錄                 |
| `Ctrl+C`        | 中斷，並把隱藏的游標恢復回來             |

### 模糊搜尋

選單開著時按 `/` 就進入搜尋模式，直接打字即可，不需要先按 Enter。查詢會用
**子序列（subsequence）** 比對，字元依序出現就算命中，所以 `flogin` 可以找到
`feature/login`：

```
請選擇 Worktree (↑/↓ 移動, Enter 確認, / 搜尋, 按 1-5 直接跳轉, q/Esc 取消)：
搜尋：flogin▏  1 筆符合 (↑/↓ 移動, Enter 確認, Esc 清除搜尋)：
 > [1] …/shop-feature-login  [feature/login] (89ae97a)
```

比對範圍只有兩個地方：

- 分支名稱，例如 `feature/login`
- 目錄路徑的**最後一層**，例如 `…/shop-feature-login` 只比 `shop-feature-login`

刻意不比對完整路徑，否則 `/Users/will/projects/` 這種共同前綴會讓每一筆都符合。
查詢含空白時會切成多個詞，每個詞都要命中（AND），所以 `fea login` 也找得到。
結果依相關度排序：連續命中、字首或 `/-_.` 分隔符之後的命中會排在前面；同分時
維持 Git 原本的順序。

搜尋模式中的按鍵：

| 按鍵        | 行為                                       |
| ----------- | ------------------------------------------ |
| 直接打字    | 累加查詢字串，清單即時更新                 |
| `Backspace` | 刪除一個字元                               |
| `Ctrl+U`    | 清空查詢                                   |
| `Ctrl+W`    | 刪除最後一個詞                             |
| `↑` / `↓`   | 在搜尋結果中移動                           |
| `Enter`     | 切換到反白的 worktree                     |
| `Esc`       | 清除搜尋、回到完整清單（不是取消整個選單） |

因為 `q`、`j`、`k`、數字在搜尋模式裡都只是查詢字元，要取消請先按 `Esc` 離開
搜尋模式，再按 `q` 或 `Esc`。

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

全部都是環境變數。zsh 可以 `export` 在 `~/.zshrc`，或 source 之後再改；PowerShell 用 `$env:名稱 = '值'` 設定（要永久生效就寫進 `$PROFILE`）。預設值如下：

| 變數                            | 預設  | 說明                                                     |
| ------------------------------- | ----- | -------------------------------------------------------- |
| `GWT_LANG`                      | `zh`  | 介面語言，可設 `en`                                      |
| `GWT_CLEAR_ON_EXIT`             | `1`   | 離開時擦掉選單；設 `0` 會留在畫面上（原文行為）           |
| `GWT_FILTER_CASE_INSENSITIVE`   | `1`   | 關鍵字不分大小寫；設 `0` 則區分                           |
| `GWT_DIGIT_TIMEOUT`             | `0.4` | 多位數編號的等待秒數，worktree 超過 9 個時才會用到         |
| `GWT_ESC_TIMEOUT`               | `0.05`| 判斷「單獨一個 Esc」與方向鍵的等待秒數                     |
| `GWT_NO_COLOR`                  | `0`   | 設 `1` 關閉顏色；設定 `NO_COLOR` 環境變數也有同樣效果      |
| `GWT_WIDTH`                     | `0`   | 選單欄寬，`0` 表示自動偵測終端機寬度                       |
| `GWT_HEIGHT`                    | `0`   | 選單可用高度，`0` 表示自動偵測；清單較高時只顯示可視視窗   |

範例：

```sh
GWT_LANG=en
GWT_CLEAR_ON_EXIT=0
GWT_FILTER_CASE_INSENSITIVE=0
```

PowerShell：

```powershell
$env:GWT_LANG = 'en'
$env:GWT_CLEAR_ON_EXIT = '0'
$env:GWT_FILTER_CASE_INSENSITIVE = '0'
```

`GWT_ESC_TIMEOUT` 在 PowerShell 版用不到：zsh 要等一小段時間才分得出「單獨一個 Esc」和方向鍵送來的 `Esc [ A`，而 PowerShell 的 `[Console]::ReadKey` 直接回報「這是方向鍵」或「這是 Esc」，不需要等。設了也不會有作用。

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

**PowerShell** 的函式沒有「結束碼」，「失敗」看的是 `$?`，所以兩邊都給：同一組數字放在 `$LASTEXITCODE`，而且只要不是 `0`，`$?` 就一定是 `$false`。這樣 `gwt && 下一個指令` 在你按 `q`／`Esc`、`Ctrl+C` 之後不會繼續跑，跟 zsh 版一致：

```powershell
gwt && Write-Host '已切換'      # 取消的話不會印
gwt; $LASTEXITCODE              # 取消 = 1，Ctrl+C = 130
```

取消與 `Ctrl+C` 不會印出任何訊息，也不會在 `$Error` 留下紀錄；找不到符合、不在儲存庫、未知選項這類失敗，則會把訊息寫進錯誤串流（可以用 `2>$null` 隱藏）。每次執行結束時 `$LASTEXITCODE` 一定會被設成上表的值，不會殘留 `git` 的結果碼。

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
| 搜尋                 | 沒有                          | 選單內按 `/` 可模糊搜尋分支與目錄名稱                |
| bare repo            | 不支援                      | 可以執行（沒有工作目錄，所以不會標「目前位置」）      |
| shell 選項衝突       | 使用者開了 `ksh_arrays` 等會壞 | 進入時 `emulate -L zsh`，不受使用者選項影響          |

## 已知限制

- **只支援 zsh 與 PowerShell 7**：zsh 版用到 `read -k`（讀單一按鍵）與從 1 開始的陣列索引，要在 bash 用需要改寫成 `read -n 1` 與 0 起算索引；PowerShell 版需要 PowerShell 7（`pwsh`），Windows PowerShell 5.1 不支援。fish 同樣沒有。
- **PowerShell 版有幾個短選項會被 PowerShell 先吃掉**：`-d`、`-e`、`-i`、`-o`、`-p`、`-w` 這類短選項會被 PowerShell 當成共同參數（`-Debug`、`-ErrorAction`、`-InformationAction`、`-OutVariable`、`-PipelineVariable`、`-WarningAction`…）的縮寫，`gwt` 根本收不到。gwt 本身沒有這些選項，所以不影響使用；只是打錯成這幾個字母時，看到的會是 PowerShell 的錯誤訊息，結束碼也不是 `2`。`-l`、`-h`、`-V` 與長選項（`--list`、`--help`、`--version`）不受影響。
- **清單比畫面高時只看得到一段**：選單會顯示一個符合終端機高度的視窗，並標示目前範圍；要一次看到全部就得用 `gwt --list` 或把終端機拉高。
- **選單開著時改變視窗大小不會重排**：寬高都在啟動時量一次，選單顯示期間調整視窗大小不會重新排版（下次執行才會生效）。
- **多位數編號有等待感**：超過 9 筆時，按單一數字要等 `GWT_DIGIT_TIMEOUT` 才知道你是不是要按第二位數。只有後面「還可能接第二位數」時才等：12 筆時按 `9`（`90` 已經超過總數）或 `3` 會立刻跳轉，只有 `1` 要等。
- **寬度為 2 的 emoji 符號在不同終端機畫得不一樣**：`⚡ ⌚ ✅ ⭐` 這類符號（Unicode 的 East Asian Width 是 W）在 Windows Terminal 佔 2 欄，在舊的 conhost 可能只佔 1 欄。gwt 一律當成 2 欄，所以在舊 conhost 上只是一列短一點，不會折行；反過來就會折行，所以才這樣算。零寬字元（組合記號、零寬連接符、`U+FE0F` 變體選擇符，例如 `❤️`、家庭與旗幟 emoji 序列）沒有處理，路徑與分支名稱含這些的話欄寬可能少算（見 [docs/design-notes.md](docs/design-notes.md) 17.12）。
- **PowerShell 版只在 Windows 10 的 PowerShell 7.7 上驗證過**：測試與實際操作都在這個環境做，沒有在 7.0～7.6 的其他版本上實際跑過；macOS／Linux 的 `pwsh` 理論上能跑（不依賴任何 Windows 專屬 API，除了測試用的 ConPTY），但沒有驗證，也沒有 CI。Windows Terminal、舊的 conhost 視窗與 VS Code 終端機的實際按鍵手感也沒有逐一驗證，見 [docs/design-notes.md](docs/design-notes.md) 第 17.11 節的檢查清單。
- **終端機窄於 17 欄時選單仍會折行**：窄到放不下完整一列時，會依序省略 commit、分支，只留編號與路徑，所以 17 欄以上都能正常重繪；再窄就連編號加最短的路徑都放不下了。
- **互動搜尋只比對分支與目錄名稱**：`/` 搜尋不看完整路徑，避免共同前綴干擾；命令列關鍵字（`gwt fix`）則仍然比對「路徑 + 分支」整串。
- **搜尋不支援正規表示式**：只有子序列比對與多詞 AND。需要更複雜的查詢可以考慮接 `fzf`。
- **不會自動清理失效的 worktree**：目錄被砍掉但沒 `git worktree prune` 的話，清單裡還是會出現。

## 開發

```sh
make help      # 列出所有指令
make test      # 執行全部測試（單元 + PTY 互動）
make test-pwsh # 執行 PowerShell 版測試（需要 pwsh 7）
make lint      # zsh -n 語法檢查 + python 編譯檢查
make demo      # 建一個含 5 個 worktree 的示範儲存庫
make site      # 在本機預覽網站（http://localhost:8765）
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
# 通過 40，失敗 0
```

想看某個測試在幹嘛，例如 Ctrl+C 的處理：

```sh
GWT_ROOT=$PWD GWT_FIXTURE=/tmp/fx bash tests/fixtures/build.sh /tmp/fx
python3 tests/lib/ptydrive.py --keys '\x03' --out /tmp/out.bin -- zsh -f tests/cases-pty/08-ctrl-c.zsh
```

### PowerShell 版的測試

只需要 `pwsh` 7 與 git，不需要 bash、python 或 Pester（Windows 內建的 Pester 3.4 與現在的語法不相容，而且這個專案的原則是不加依賴）：

```powershell
pwsh tests/pwsh/run.ps1                  # 全部：語法檢查 + 單元 + 按鍵驅動 + 真主控台
pwsh tests/pwsh/run.ps1 -Filter search   # 只跑檔名含 search 的測試
pwsh tests/pwsh/run.ps1 -SkipConsole     # 略過需要 ConPTY 的測試
pwsh tests/pwsh/run.ps1 -Keep            # 保留暫存目錄，方便失敗時進去追
```

測試分三類，每個檔案都在獨立的 `pwsh -NoProfile` 處理序裡執行（所以你 `$PROFILE` 裡已經載入的 gwt 不會干擾）：

| 目錄                     | 做什麼                                                                                               |
| ------------------------ | ---------------------------------------------------------------------------------------------------- |
| `tests/pwsh/cases/`         | 單元測試：直接呼叫模組內部函式（解析、篩選、模糊搜尋、欄寬、排版），以及 `--list`、錯誤、結束狀態、中文與特殊字元路徑、`install.ps1` 在各種 profile 編碼與內容下的安裝／移除還原 |
| `tests/pwsh/cases-keys/`    | 按鍵驅動：用 `gwt.psm1` 的測試掛鉤餵按鍵、收畫面，重播成最終畫面後檢查（視窗化、折行、殘影、搜尋）   |
| `tests/pwsh/cases-console/` | 真主控台：在 Windows 的 ConPTY 偽主控台裡跑真正的 `pwsh`，送真正的按鍵（方向鍵、`Esc`、`Ctrl+C`…）  |

Windows 沒有 `pty`，而且 `[Console]::ReadKey` 在輸入被導向時會直接丟例外，所以不能照搬 zsh 版的 PTY 作法：按鍵驅動測試跑得快也不會因為時間差而不穩，但沒走過真正的主控台；真主控台測試用 `tests/pwsh/lib/ConPty.ps1`（一小段 C#，用 `Add-Type` 編譯）補上那一塊。ConPTY 只有 Windows 有，其他平台會自動略過那一類。

### 專案結構

```
git-worktree-tui/
├── gwt.zsh                  # zsh 版函式本體（唯一需要載入的檔案）
├── gwt.plugin.zsh           # plugin manager 進入點
├── gwt.psm1                 # PowerShell 7 版（模組，只匯出 gwt）
├── install.sh               # zsh 版安裝／移除腳本
├── install.ps1              # PowerShell 版安裝／移除腳本
├── Makefile                 # help / test / test-pwsh / lint / install / demo / clean
├── docs/
│   ├── design-notes.md      # 每個設計決定的理由
│   └── roadmap.md           # 後續想做的事
├── scripts/
│   └── demo.sh              # 建立示範儲存庫
├── site/                    # 官方網站（GitHub Pages，部署到 gwt.gh.miniasp.com）
├── tools/
│   └── social-card.html     # 社群分享卡的來源，以 1200×630 截圖產生 site/assets/og.png
└── tests/
    ├── run.sh               # zsh 版測試入口
    ├── cases/               # 單元測試（不需要終端機）
    ├── cases-pty/           # 互動測試（需要 PTY）
    ├── fixtures/build.sh    # 測試資料產生器
    ├── lib/                 # 斷言、fixture 工具、PTY 驅動程式
    └── pwsh/                # PowerShell 版測試
        ├── run.ps1          # 入口（語法檢查 + 三類測試）
        ├── cases/           # 單元測試
        ├── cases-keys/      # 測試掛鉤餵按鍵 + 畫面重播
        ├── cases-console/   # ConPTY 真主控台
        ├── fixtures/        # 測試資料產生器（PowerShell 寫的，不需要 bash）
        └── lib/             # 斷言、按鍵驅動、畫面重播、ConPTY 驅動
```

## 授權

[MIT](LICENSE)，著作權人 Will 保哥 (Will Huang)。
