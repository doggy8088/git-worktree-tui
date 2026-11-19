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

登入 <https://www.powershellgallery.com> → 右上角帳號 → **API Keys** → **Create**：

- **Key Name**：`gwt-github-actions`
- **Expires in**：選你記得住要換的最短期限。Gallery 的選項是 1／90／180／270／365 天（預設 365），
  **建立之後不能改**，也沒有「永不過期」（[Microsoft 的說明](https://learn.microsoft.com/en-us/powershell/gallery/how-to/managing-profile/creating-apikeys)）。
  建議 180 天或更短，並且**自己在行事曆設提醒**，不要只靠 Gallery 寄的到期通知信。
- **Select Scopes**：第一次發佈，套件還不存在，所以要選「可以推送**新套件**」的那一項。
- **Select Packages → Glob Pattern**：填 `gwt`（完整名稱，不要用 `*`）。第一次發佈時套件還不存在，
  沒辦法用勾選的，一定要用 glob；glob 只比對名稱，所以填完整名稱就只能推送這一個套件。

> 權限選項的字樣以你在畫面上看到的為準：Microsoft 的說明寫的是 *Push new packages* ／ *Push new or update
> packages* ／ *Unlist packages*，Gallery 畫面上的文字可能不一樣（我寫這份文件時沒有登入看過實際畫面）。
> 判斷標準是語意：**不要**選 *Unlist*；第一把要能建立新套件，第二把只能推送既有套件的新版本。

**第一次發佈成功之後**，回來建立第二把 key：權限改成只能推送既有套件的新版本、在 *Select Packages*
勾選已存在的 `gwt`，把 GitHub 的祕密換成這一把，再到 Gallery 刪掉第一把。
這樣之後外洩的 key 連「建立新套件」的權限都沒有。

key 只會顯示一次，不要貼進任何聊天或文件。

### 2. 在 GitHub 建立環境 `psgallery`

Settings → Environments → **New environment** → 名稱 `psgallery`：

- **Required reviewers**：加你自己。獨自維護時**不要**勾「Prevent self-review」，否則沒有人能核准。
- **Deployment branches and tags**：選 **Selected branches and tags**，只加一條規則：type 選 **Tag**、名稱 `v*`。
  （不要加任何分支規則。）
- **Environment secrets**：新增 `PSGALLERY_API_KEY`，值是上一步的 key。

用命令列做的話（會提示你輸入 key，不會留在 shell 歷史裡）：

```sh
uid=$(gh api users/doggy8088 --jq .id)
gh api -X PUT repos/doggy8088/git-worktree-tui/environments/psgallery --input - <<EOF
{"reviewers":[{"type":"User","id":$uid}],
 "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
gh api -X POST repos/doggy8088/git-worktree-tui/environments/psgallery/deployment-branch-policies \
  -f name='v*' -f type=tag
gh secret set PSGALLERY_API_KEY --env psgallery --repo doggy8088/git-worktree-tui
```

（這段命令我沒有實際執行過——建立環境與祕密需要你的授權；以網頁介面為準，命令只是省事。
設定完用 `gh api repos/doggy8088/git-worktree-tui/environments/psgallery` 確認 reviewers 與
`deployment_branch_policy` 都在。）

### 3. 名稱

套件名稱 `gwt` 在 2026-11-19 檢查時還沒有人用。**第一次發佈就會註冊這個名稱**；在那之前任何人都可以先註冊，
所以第一次發佈不要拖太久。

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
- **key 快過期**：Gallery 會寄到期通知，但不要只靠它——建立 key 時就在行事曆設好提醒。換法：建立新 key
  （參數同上）→ 更新祕密 → 刪掉舊的。過期的 key 不能再用，發佈 job 會在「發佈」那一步失敗，不會發佈出任何東西。

## 與 `install.ps1` 的關係

兩種安裝方式不要同時用：

- `Install-PSResource gwt` 把模組裝進 PowerShell 的模組資料夾，第一次打 `gwt` 時自動載入，不需要改 profile；
  更新用 `Update-PSResource gwt`。
- `install.ps1`（一行安裝）把 `gwt.psm1` 放到 `~\.gwt`，並在 profile 加一行 `Import-Module`。

兩種都裝，profile 那一行會先載入 `~\.gwt` 的那一份，Gallery 的那一份被蓋住，看起來「更新了卻沒變」。
換方式之前先移除舊的（`install.ps1 -Uninstall` 或 `Uninstall-PSResource gwt`）。
