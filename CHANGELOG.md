# 版本記錄

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本號參考 [Semantic Versioning](https://semver.org/zh-TW/)。

## [未發布]

## [0.2.1] - 2026-11-19

zsh 版補上 PowerShell 版 code review 找到的五個問題（[roadmap 原本的 5a](https://github.com/doggy8088/git-worktree-tui/blob/v0.2.0/docs/roadmap.md)），
兩個版本的行為從此一致。每一項都有新的測試，而且都先在未修正的程式上確認會失敗。PowerShell 版的程式沒有改，只改了版本號與註解。

### 修正

- **zsh 版：多位數編號的第一位數不必等。** 12 筆時按 `9`（再加一位就是 90 以上，一定超過總數）原本要白等
  `GWT_DIGIT_TIMEOUT`，現在立刻跳轉；只有 `1` 這種還可能接第二位數的才等。
- **zsh 版：被忽略的數字不再弄掉目前的選取。** 5 筆時按 `9` 會被忽略，但原本已經把選取改成 9：光棒消失、
  Enter 選到不存在的第 9 筆。現在光棒留在原處，Enter 照常選原本那筆。
- **zsh 版：等第二位數時按 `Ctrl+C` 是中斷。** 終端機關掉訊號轉換（`stty -isig`）、`Ctrl+C` 以位元組送進來時，
  原本剛才的數字照樣生效、切換目錄、回傳成功；現在回傳 130、不切換。一般情況下 `Ctrl+C` 是訊號，本來就沒問題。
- **zsh 版：很窄的終端機不再折行。** 一列放不下時依序省略 commit、分支，只留編號與路徑；寬度下限從 24 降到 16。
  原本 25 欄以下每一列都會折成兩行，重繪後畫面留下殘影。現在 17 欄以上都正常（與 PowerShell 版相同）。
- **zsh 版：欄寬表補齊。** `⚡ ⌚ ✅ ⭐` 這類寬度為 2 的 emoji 符號、`🔥` 等基本多文種平面以外的字元原本算 1 欄，
  分支或路徑含這些時一列會比算出來的寬而折行；`U+303F` 原本反而多算成 2 欄。現在與 PowerShell 版用同一張表
  （由 `gwt.psm1` 的表機械轉換而來）。
- 發佈流程的「確認已上架」步驟：`Save-PSResource` 之前先建立目錄。v0.2.0 發佈時這一步失敗，
  workflow 因此顯示失敗，但發佈本身成功（`gwt 0.2.0` 已在 Gallery 上，另外手動驗證過下載與執行）。

### 新增

- README 加上從 PowerShell Gallery 安裝的方式：`Install-PSResource gwt`（PowerShell 7.4 以上；7.0～7.3 用
  `Install-Module`）、更新與移除，以及「不要和一行安裝同時使用」的提醒。手動安裝改為方式三。
  官網「之後怎麼更新？」也補上 Gallery 的更新方式。
- 測試：zsh 版新增 1 個單元測試與 5 個 PTY 互動測試，總數 40。欄寬測試直接讀 PowerShell 版的
  `tests/pwsh/lib/WidthOracle.ps1`（逐字寫死的 Unicode 標準答案），兩個版本對同一份答案。
  畫面重播器（`tests/lib/screen.py`）新增 `WRAPS`（折行次數）：窄終端機的問題只看「有沒有重複的列」抓不到。

### 變更

- 新增 `.gitattributes`：所有文字檔在每個平台都以 LF 取出。v0.2.0 在 Windows runner 上打包，
  PowerShell Gallery 上的三個檔案因此是 CRLF（內容與 tag 相同，位元組不同）；之後發佈的位元組會與 tag 相同。
- `docs/publishing.md` 依第一次實際發佈更新：Gallery 畫面上實際的欄位與選項字樣、目前使用的 key
  （只能推送新版本）、環境設定補上 `can_admins_bypass: false`、`gh secret set` 收到空輸入也會成功的陷阱、
  workflow 失敗但版本已送出時怎麼判斷。並修正一個會誤導的說明：換 key 時原本寫「參數同上」，照做會建立
  能推送新套件、權限過寬的 key。
- README 與 design-notes 拿掉「zsh 版不一樣」的說明（多位數編號的等待、窄終端機的下限、欄寬表），
  roadmap 移除已完成的 5a，並更新第 12 項 PowerShell Gallery 的狀態。

## [0.2.0] - 2026-11-19

第一個包含 PowerShell 7 版的 release；版本號三個地方（`gwt.zsh`、`gwt.psm1`、新的 `gwt.psd1`）同步改為 0.2.0。

### 新增

- **發佈到 PowerShell Gallery 的流程**：新增模組清單 `gwt.psd1`、打包腳本 `tools/Build-PSGalleryPackage.ps1`
  （發佈之前就把「發佈之後改不了」的事檢查完：三處版本一致、版本等於 tag、清單欄位、套件內容）、
  以及發佈用的 GitHub Actions workflow（`.github/workflows/publish-psgallery.yml`）。發佈 GitHub release
  就會測試、打包、等維護者核准、發佈、再從 Gallery 裝一份確認。PowerShell Gallery 目前不支援 Trusted
  publishing（OIDC，[#353](https://github.com/PowerShell/PowerShellGallery/issues/353)），所以用 API key，
  並且把風險降到最小：key 放在需要核准、只放行 `v*` tag 的 GitHub 環境裡，測試與打包看不到它，
  action 釘在 commit SHA，沒有 token 權限，外部輸入不展開進腳本。維護與一次性設定見
  [docs/publishing.md](docs/publishing.md)。
- **PowerShell 7（`pwsh`）版**：`gwt.psm1`，只匯出 `gwt` 一個命令。行為、按鍵、設定項與 zsh 版對齊：
  方向鍵／`j`／`k`／數字鍵／`/` 模糊搜尋、`Esc` 與 `Ctrl+C`、`--list`／`--help`／`--version`、視窗化、
  欄寬截斷、`GWT_LANG` 等環境變數。取消與錯誤的結束狀態同時放在 `$LASTEXITCODE`（0／1／2／130）與 `$?`
  （非 0 時為 false），所以 `gwt && 下一個指令` 在取消之後不會繼續跑，取消時也不印任何訊息。
  切換後 `cd -` 仍回到切換之前的目錄。路徑與分支含中文、空白、`[ ] $ ' &` 都能正確切換。
  細節與每個決定的理由見 [design-notes 第 17 節](docs/design-notes.md)。
- **`install.ps1` 與 PowerShell 一行安裝**：`irm https://gwt.gh.miniasp.com/install.ps1 | iex`。把
  `gwt.psm1` 放到 `~\.gwt\`，並在 `$PROFILE.CurrentUserAllHosts`（VS Code 的終端機也會載入）加入可移除的
  區塊；重複執行不會重複加行，移除時 profile 逐位元組還原。支援 `-Version`、`-Dir`、`-ProfilePath`、
  `-Uninstall`，以及給 `iex` 用的 `GWT_VERSION`／`GWT_INSTALL_DIR`／`GWT_PROFILE`。沒指定版本而最新的
  release 還沒有 PowerShell 版時，會明說並改裝 `main`。不會改執行原則，只會在 profile 載不進來時警告。
- README 與官方網站加上 PowerShell 的安裝指令（各有自己的複製按鈕）、環境變數與結束狀態的 PowerShell 寫法。
- 測試：新增 `tests/pwsh/`（27 個測試檔：19 個單元——含 PowerShell Gallery 打包與發佈 workflow 的安全性質檢查、
  `install.ps1` 對 16 種 profile 內容的安裝／移除逐位元組還原、
  以本機伺服器走完整的 `irm | iex` 流程、擋掉「PowerShell 7.0 上會壞的 API」的相容性防線、畫面重播器本身的語意測試；
  5 個以測試掛鉤餵按鍵並重播畫面、3 個在 ConPTY 真主控台裡送真按鍵），只需要 `pwsh` 7 與 git，不需要 bash、python 或 Pester。`make test-pwsh` 或
  `pwsh tests/pwsh/run.ps1`。CI 新增 `windows-latest` 工作。
- 選單內按 `/` 進入模糊搜尋：以子序列比對分支名稱與路徑的最後一層目錄，
  `flogin` 可以找到 `feature/login`。查詢含空白時切成多個詞，每個詞都要命中（AND）。
- 搜尋結果依相關度排序（連續命中、字首與分隔符後命中優先），同分時維持 Git 的順序。
- 搜尋模式支援 `Backspace`、`Ctrl+U`（清空）、`Ctrl+W`（刪除最後一個詞）；
  沒有符合項目時顯示提示，按 `Enter` 不會誤切換。
- 測試：新增 1 個模糊搜尋單元測試與 8 個 PTY 互動測試，總數 34 個。
- 首頁的可互動示範選單也支援 `/` 模糊搜尋：即時篩選、方向鍵選取、
  `Backspace`／`Ctrl+U`／`Ctrl+W`、`Esc` 清除與無結果提示；桌機與手機寬度都驗證過。

### 變更

- 表頭改為每次重繪時一起更新，才能即時顯示搜尋字串與符合筆數。
- 選單按鍵說明加入 `/` 搜尋；`--help` 同步補充搜尋模式的按鍵。

### 修正

- 按 `Esc` 後緊接 `Enter` 時，`Enter` 會被當成跳脫序列的一部分吃掉。改為逐字元
  解析 Esc 序列，非方向鍵的字元會放回主迴圈處理。
- 首頁示範選單完成後選單沒有真的消失：`.term-body .menu` 的 `display: block`
  蓋過 `hidden` 屬性，`cd` 結果因此擠在整份清單下面，看起來像壞掉。補上
  `.term-body .menu[hidden] { display: none; }`。
- 首頁示範選單的三個死路：初始畫面直接按 `Enter` 沒反應、切換完成後鍵盤失效、
  沒先點選單時 `/` 無效。現在 `Enter` 會先選第一筆，結果列可以用 `Esc`／`Enter`
  回到選單，點終端機任意位置都能聚焦，示範區在畫面上時可直接按 `/` 搜尋。

## [0.1.0] - 2026-11-17

第一個 release。把部落格文章裡的 `gwt` 函式整理成可維護、有測試、可安裝的專案。

版號從 0.1.0 起算，介面與行為在 1.0.0 之前仍可能調整。

### 新增

- `gwt.zsh`：互動式 worktree 切換器，方向鍵／`j`／`k` 移動、數字鍵直接跳轉、`Enter` 切換、`q`／`Esc` 取消、`Ctrl+C` 中斷。
- 關鍵字篩選，比對「路徑 + 分支名稱」，只剩一筆符合時直接切換。
- `--list`：只印出符合的 worktree 路徑，方便接給其他工具。
- `--help`、`--version`。
- 設定項：`GWT_LANG`、`GWT_CLEAR_ON_EXIT`、`GWT_FILTER_CASE_INSENSITIVE`、`GWT_DIGIT_TIMEOUT`、`GWT_ESC_TIMEOUT`、`GWT_NO_COLOR`、`GWT_WIDTH`、`GWT_HEIGHT`。
- `GWT_LANG=en` 英文介面。
- `gwt.plugin.zsh`：oh-my-zsh、antigen、zinit、sheldon、zplug 等 plugin manager 的進入點。
- **一行安裝**：`curl -fsSL https://gwt.gh.miniasp.com/install.sh | bash`。腳本會抓最新 release、放進 `~/.zsh/gwt.zsh`，並在 `~/.zshrc` 加入可移除的區塊；支援 `--version`、`--dir`、`--uninstall`，重複執行不會重複加行。
- 官方網站 <https://gwt.gh.miniasp.com>：可互動的選單示範、按鍵與設定說明，以 GitHub Pages 部署。
- `Makefile`：`help`、`test`、`lint`、`install`、`uninstall`、`site`、`demo`、`clean`。
- 測試框架：25 個測試（10 個單元 + 15 個在真 PTY 送按鍵的互動測試），含 fixture 產生器與 PTY 驅動程式。
- 文件：`README.md`、`docs/design-notes.md`（每個設計決定的理由）、`docs/roadmap.md`、`CHANGELOG.md`。

### 變更

- 取消（`q`／`Esc`）的結束碼從 `0` 改為 `1`，讓「取消」不會被當成成功。
- 選單離開後預設擦掉，不再留在捲動緩衝區；`GWT_CLEAR_ON_EXIT=0` 可保留原文行為。
- 關鍵字比對預設不分大小寫；`GWT_FILTER_CASE_INSENSITIVE=0` 可改回區分大小寫。
- worktree 超過 9 個時，數字鍵支援多位數（按 `1` `2` 跳到第 12 筆）。
- 過長路徑依終端機欄寬從中間截斷（保留較有用的尾段）。
- 進入函式時執行 `emulate -L zsh`，不受使用者既有的 shell 選項影響。
- Repo 偵測改用 `git rev-parse --git-dir`，bare repo 也能執行。
- 分支與路徑改用 `%s` 輸出，不再使用 `%b`。

### 修正

- **worktree 數量超過終端機高度時選單錯位**：原本每次都重畫整個清單，但 `\e[NA` 在畫面頂端會被夾住，導致表頭消失、只剩清單尾端、光棒跑出畫面。改成視窗化：只畫放得下的列數，選取項目帶著視窗捲動，下方標示目前範圍。
- **每一列沒有保證只佔一個實體行**：長分支名或窄視窗讓終端機自動換行時，「往上移 N 行」會算錯，出現整列重複與選完後的殘影。現在表頭會裁到一行，項目列也會先裁分支名稱、再裁路徑。
- **`Ctrl+C` 的結束碼**：zsh 在 trap 內執行 `return 130` 時回傳值不保證是 130，改用 `_GWT_INTERRUPTED` 旗標，確保一律回傳 130。
- **分支名稱含 `%` 或反斜線**：原本用 `%b` 會被當成格式字串解讀，改為原樣輸出。
- **數字鍵跳轉後沒有重繪**：`GWT_CLEAR_ON_EXIT=0` 時會看到跳轉前的舊畫面。
- **`_GWT_COUNT` 沒有在 `_gwt_collect` 更新**，單獨呼叫時計數永遠是 0。
- **`Makefile` 的 `ZSH` 變數與 oh-my-zsh 的 `$ZSH` 衝突**，導致 `make lint` 失敗，改名為 `ZSHBIN`。
- **網站 hero 的中文標題斷行**：固定 `<br>` 配 vw 字級，卡片變窄時會把「互動式切換指令」切成「…指／令」。改用容器查詢（cqw）定字級，每行不可斷。

### 已知限制

- 只支援 zsh（用到 `read -k` 與 1 起算的陣列索引）。
- 選單開著時改變視窗大小不會重排，下次執行才生效。
- 清單比畫面高時只顯示一段視窗。
- 篩選是子字串比對，沒有模糊搜尋。
- 不會自動 `git worktree prune`。

[0.2.0]: https://github.com/doggy8088/git-worktree-tui/releases/tag/v0.2.0
[0.1.0]: https://github.com/doggy8088/git-worktree-tui/releases/tag/v0.1.0
