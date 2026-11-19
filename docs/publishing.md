# 發佈到 PowerShell Gallery

這份文件給維護者：怎麼發佈、第一次要做哪些一次性設定、出事時怎麼辦。
發佈由 [`.github/workflows/publish-psgallery.yml`](../.github/workflows/publish-psgallery.yml) 自動完成：
**發佈一個 GitHub release，就會測試、打包、等你核准、發佈。**

## 為什麼用 API key，不是 Trusted publishing

NuGet.org、PyPI、crates.io 都支援 Trusted publishing（OIDC）：workflow 向 GitHub 要一個短效的身分 token，
換成臨時憑證，專案裡完全不必存祕密。**PowerShell Gallery 目前不支援。** 唯一的請求是
[PowerShell/PowerShellGallery#353](https://github.com/PowerShell/PowerShellGallery/issues/353)
（2026-09-04 提出，沒有任何回應，也沒有時程）。

所以只能用 Gallery 的 API key。key 是長效的祕密，整個流程的設計就是把「它能被拿到的機會」降到最小：

| 攻擊面                                   | 怎麼擋                                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------------------------- |
| 有人從 pull request／fork 讀 key         | workflow 不會被 pull request 觸發；key 在「環境」裡，不是一般的 repository secret           |
| 有人從別的分支或 tag 讀 key              | 環境只放行 `v*` 的 tag（見下方設定）                                                         |
| 有人（或被入侵的帳號）直接觸發發佈       | 環境要求核准，核准人是你；沒有核准，發佈 job 不會開始，key 也不會交給任何程式                |
| 測試程式碼讀 key                         | 測試與打包在另一個 job，那個 job 完全看不到祕密；key 只在發佈 job 的一個步驟的環境變數裡      |
| key 外洩之後的損害                       | key 只能推送名為 `gwt` 的套件、只有最小權限、會過期（見下方）                                |
| 供應鏈：action 的標籤被改成惡意版本      | 所有 action 釘在 40 碼的 commit SHA                                                          |
| 外部輸入（tag 名稱）造成腳本注入         | 只經由環境變數傳入，不展開進腳本；tag 格式在打包腳本裡嚴格檢查（`vX.Y.Z`）                   |
| workflow 的 token 被濫用                 | 頂層 `permissions: {}`；發佈 job 沒有任何 token 權限                                         |

這些性質都有測試（`tests/pwsh/cases/19-gallery-package.ps1`）：把 workflow 改壞（例如把祕密放進 `run`、
拿掉 SHA 釘選）會在合併之前就失敗。

**等 Gallery 支援 OIDC 時**：訂閱 [#353](https://github.com/PowerShell/PowerShellGallery/issues/353)；
屆時只需要換掉 workflow 裡「發佈」那一步取得憑證的方式，其餘（核准、環境、打包檢查）都不用動，
然後刪掉 Gallery 上的 API key 與 GitHub 的祕密。

## 一次性設定（只有你能做，因為需要你的帳號）

### 1. 在 PowerShell Gallery 建立 API key

登入 <https://www.powershellgallery.com> → 右上角帳號 → **API Keys** → 展開 **Create**。
欄位與選項的字樣是 2026-11-19 實際建立時畫面上看到的：

- **Key Name**：例如 `gwt-github-actions-versions`
- **Expires In**：選你記得住要換的最短期限。選項是 1／90／180／270／365 天（預設 365），
  **建立之後不能改**，也沒有「永不過期」（[Microsoft 的說明](https://learn.microsoft.com/en-us/powershell/gallery/how-to/managing-profile/creating-apikeys)）。
  建議 180 天或更短，並且**自己在行事曆設提醒**，不要只靠 Gallery 寄的到期通知信。
- **Select Scopes**：**Push** 保持勾選，下面兩個選項選 **Push only new package versions**；
  **不要**勾 **Unlist package**。
- **Select Packages**：**Glob Pattern** 填 `gwt`（完整名稱，不要用 `*`）；下方清單裡 `gwt` 的勾選框會跟著被勾起來。

按 **Create** 之後，**只有這一次**能在 **Manage** 區塊用該 key 的 **Copy** 複製（之後重新整理頁面就沒有 Copy 了，
只能 Regenerate）。複製後直接存成 GitHub 的祕密（下一節），不要貼進任何聊天或文件。

**目前使用中的 key**：`gwt-github-actions-versions`，2026-11-19 建立，180 天（Gallery 顯示 *in 6 months*），
*Push only new package versions*，套件 `gwt`。

> **只有在套件還不存在時**（第一次發佈、或改名成新的套件），才需要另一個選項
> *Push new packages and package versions*：「只推送新版本」的 key 不能建立新套件，發佈會得到 403。
> v0.2.0 就是先用這種 key（`gwt-github-actions`）發佈，成功後換成上面那把較窄的 key，並刪掉第一把。
> 這樣即使現在的 key 外洩，也沒有建立新套件的權限。

### 2. 在 GitHub 建立環境 `psgallery`

Settings → Environments → **New environment** → 名稱 `psgallery`：

- **Required reviewers**：加你自己。獨自維護時**不要**勾「Prevent self-review」，否則沒有人能核准。
- **Deployment branches and tags**：選 **Selected branches and tags**，只加一條規則：type 選 **Tag**、名稱 `v*`。
  （不要加任何分支規則。）
- **管理員不能略過保護規則**（API 的 `can_admins_bypass: false`）：否則 repo 管理員可以不經核准直接發佈。
- **Environment secrets**：新增 `PSGALLERY_API_KEY`，值是上一步的 key。

用命令列做（2026-11-19 實際就是用這組命令建立的）：

```sh
uid=$(gh api users/doggy8088 --jq .id)
gh api -X PUT repos/doggy8088/git-worktree-tui/environments/psgallery --input - <<EOF
{"can_admins_bypass":false,
 "reviewers":[{"type":"User","id":$uid}],
 "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
gh api -X POST repos/doggy8088/git-worktree-tui/environments/psgallery/deployment-branch-policies \
  -f name='v*' -f type=tag
gh secret set PSGALLERY_API_KEY --env psgallery --repo doggy8088/git-worktree-tui   # 會提示你貼上 key
```

設定完確認 GitHub 實際存下的值：

```sh
gh api repos/doggy8088/git-worktree-tui/environments/psgallery \
  --jq '{can_admins_bypass, deployment_branch_policy, rules: [.protection_rules[] | {type, prevent_self_review, reviewers: [(.reviewers // [])[] | .reviewer.login]}]}'
gh api repos/doggy8088/git-worktree-tui/environments/psgallery/deployment-branch-policies --jq '[.branch_policies[] | {name, type}]'
gh secret list --env psgallery --repo doggy8088/git-worktree-tui
```

> **用管線餵 key 給 `gh secret set` 時，先確認值不是空的。** `gh secret set` 從 stdin 收到空的輸入也會成功、
> 建立一個空的祕密，不會報錯（2026-11-19 實際踩到：讀剪貼簿的命令失敗，輸出是空的）。
> `gh secret list` 只看得到名稱與更新時間，看不到值，所以事後也發現不了；要到發佈時，「發佈」步驟一開始的檢查
> 才會以「PSGALLERY_API_KEY 是空的」失敗（這時還沒送出任何東西）。

### 3. 名稱

套件名稱 `gwt` 已在 2026-11-19 隨 v0.2.0 註冊，擁有者是 Gallery 帳號 `willh`。

## 發佈一個版本

1. **三個地方的版本改成同一個數字**（例如 `0.3.0`）：`gwt.zsh` 的 `GWT_VERSION`、`gwt.psm1` 的
   `$script:GwtVersion`、`gwt.psd1` 的 `ModuleVersion`。再把 `CHANGELOG.md` 的「未發布」改成這個版本與日期。
   打包腳本與測試都會檢查三者一致，不一致不能打包。
2. 開 PR、合併。
3. **試跑**（不會發佈）：GitHub 的 Actions 分頁 → *Publish to PowerShell Gallery* → *Run workflow*。
   手動執行只會跑測試與打包，永遠不會發佈。也可以在本機：
   `pwsh tools/Build-PSGalleryPackage.ps1 -OutputDir ./out -Tag v0.3.0`。
4. **發佈 release**（tag 必須是 `v` 加版本號，且不是 pre-release）：
   ```sh
   gh release create v0.3.0 --title 'v0.3.0' --notes-file <(sed -n '/^## \[0.3.0\]/,/^## \[/p' CHANGELOG.md | sed '$d')
   ```
5. workflow 開始：先測試與打包，然後**停在發佈步驟等你核准**（GitHub 會通知你）。核准後送出，再等 Gallery 驗證
   （通常幾分鐘），最後從 Gallery 裝一份下來確認 `gwt --version` 正確。
6. 到 <https://www.powershellgallery.com/packages/gwt> 看一眼。

## 出事時

- **發佈之後發現有問題**：版本**不能刪除、不能覆蓋**，只能在 Gallery 的套件管理頁面把它**下架**（unlist，新的
  `Install-PSResource` 不會再選它，但已經裝的不受影響）。修好之後發佈更高的版本。所以才會在發佈前做這麼多檢查。
- **403**：key 的 scope 或 glob 不對（例如第一次發佈用了「只推送新版本」的 key，套件還不存在）、或 key 過期。
- **「已經在 PowerShell Gallery 上了」**：那個版本號已經用過。提高版本號。
- **key 外洩或不確定有沒有外洩**：立刻到 Gallery 的 API Keys 頁面**刪除**那把 key，建立新的、更新 GitHub 的祕密，
  然後檢查套件的版本歷史有沒有不認得的版本。
- **key 快過期**：Gallery 會寄到期通知，但不要只靠它——建立 key 時就在行事曆設好提醒。換法：照第 1 節建立新 key
  （**Push only new package versions**、套件 `gwt`；不要選 *Push new packages and package versions*）→ 更新祕密
  → 刪掉舊的。過期的 key 不能再用，發佈 job 會在「發佈」那一步失敗，不會發佈出任何東西。
- **workflow 顯示失敗，但不確定有沒有發佈出去**：看失敗的是哪一步。「發佈」之後的「確認已上架」失敗時，
  版本其實已經送出了；到 <https://www.powershellgallery.com/packages/gwt> 確認，**不要**為了讓它變綠而重跑
  （重跑會被「版本已存在」的檢查擋下）。v0.2.0 就是這樣：「確認已上架」有 bug（`Save-PSResource` 的目錄沒先建立），
  發佈本身成功，那次 run 會一直是紅的；bug 已在之後的 commit 修正。

## 與 `install.ps1` 的關係

兩種安裝方式不要同時用：

- `Install-PSResource gwt` 把模組裝進 PowerShell 的模組資料夾，第一次打 `gwt` 時自動載入，不需要改 profile；
  更新用 `Update-PSResource gwt`。
- `install.ps1`（一行安裝）把 `gwt.psm1` 放到 `~\.gwt`，並在 profile 加一行 `Import-Module`。

兩種都裝，profile 那一行會先載入 `~\.gwt` 的那一份，Gallery 的那一份被蓋住，看起來「更新了卻沒變」。
換方式之前先移除舊的（`install.ps1 -Uninstall` 或 `Uninstall-PSResource gwt`）。
