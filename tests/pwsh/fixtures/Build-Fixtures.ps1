# -----------------------------------------------------------------------------
# 建立測試用的 Git 儲存庫（對應 tests/fixtures/build.sh，改用 PowerShell 寫，
# 這樣 Windows 上不需要 bash）
#
# 用法：Build-Fixtures.ps1 -Root <空目錄>
#
#   shop/       主 worktree + 4 個 worktree（含路徑有空白、含 detached HEAD）
#   twelve/     主 worktree + 11 個 worktree（驗證多位數編號）
#   many/       40 個 worktree（驗證選單視窗化，清單比終端機高）
#   longname/   分支與目錄名都很長（驗證每一列都不會折行）
#   cjk/        目錄與分支名稱都是中文（驗證 UTF-8 解碼與全形字寬度）
#   special/    目錄名稱含 [ ] $ ' & ; ( )（驗證不會被當成萬用字元或變數）
#   plain/      只有一個 worktree 的儲存庫
#   outside/    不是 Git 儲存庫的目錄
#
# 為了讓 commit hash 與結果可重現，這裡固定作者與日期，並使用獨立的 git config，
# 不去動使用者原本的全域設定。呼叫端（run.ps1）也要把同樣的環境變數帶給測試。
# -----------------------------------------------------------------------------
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# git 輸出是 UTF-8；先讓主控台解碼對齊，錯誤訊息才讀得懂
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

New-Item -ItemType Directory -Force -Path $Root | Out-Null
$Root = (Resolve-Path -LiteralPath $Root).ProviderPath

$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_CONFIG_GLOBAL = Join-Path $Root 'gitconfig'
$env:GIT_AUTHOR_NAME = 'gwt test'
$env:GIT_AUTHOR_EMAIL = 'gwt@example.com'
$env:GIT_COMMITTER_NAME = 'gwt test'
$env:GIT_COMMITTER_EMAIL = 'gwt@example.com'
$env:GIT_AUTHOR_DATE = '2026-01-01T00:00:00 +0000'
$env:GIT_COMMITTER_DATE = '2026-01-01T00:00:00 +0000'

git config --file $env:GIT_CONFIG_GLOBAL init.defaultBranch main
git config --file $env:GIT_CONFIG_GLOBAL advice.detachedHead false

function New-Repo {
  param([string]$Name)
  $dir = Join-Path $Root $Name
  git init -q $dir
  git -C $dir commit -q --allow-empty -m 'init'
  return $dir
}

function Add-Worktree {
  param([string]$Repo, [string]$Path, [string]$Branch)
  if ($Branch) {
    git -C $Repo worktree add -q $Path -b $Branch
  }
  else {
    git -C $Repo worktree add -q --detach $Path
  }
}

# ---- shop：5 個 worktree，含路徑空白與 detached HEAD ------------------------
$shop = New-Repo 'shop'
Add-Worktree $shop (Join-Path $Root 'shop-feature-login') 'feature/login'
Add-Worktree $shop (Join-Path $Root 'shop-feature search api') 'feature/search-api'
Add-Worktree $shop (Join-Path $Root 'shop-fix-cart-bug') 'fix/cart-bug'
Add-Worktree $shop (Join-Path $Root 'shop-hotfix') ''

# ---- twelve：12 個 worktree -------------------------------------------------
$twelve = New-Repo 'twelve'
1..11 | ForEach-Object {
  $n = '{0:D2}' -f $_
  Add-Worktree $twelve (Join-Path $Root "twelve-w$n") "w$n"
}

# ---- many：40 個 worktree ---------------------------------------------------
$many = New-Repo 'many'
1..39 | ForEach-Object {
  $n = '{0:D2}' -f $_
  Add-Worktree $many (Join-Path $Root "many-w$n") "m$n"
}

# ---- longname：超長分支名與超長目錄名 ---------------------------------------
$long = New-Repo 'longname'
Add-Worktree $long (Join-Path $Root 'longname-a-very-long-worktree-directory-name-used-for-testing') 'feature/this-is-a-deliberately-long-branch-name'

# ---- cjk：中文目錄與中文分支 ------------------------------------------------
$cjk = New-Repo 'cjk'
Add-Worktree $cjk (Join-Path $Root 'cjk-購物車') '功能/登入'
Add-Worktree $cjk (Join-Path $Root 'cjk-修正結帳錯誤') '修正/結帳'

# ---- special：目錄名稱含 PowerShell 的特殊字元 ----------------------------
# [ ] 會被當成萬用字元，$ 會被當成變數，' 會破壞單引號字串，& ; ( ) 是命令分隔與群組。
# 分支名稱不能含 [，所以分支用一般名稱。
$special = New-Repo 'special'
Add-Worktree $special (Join-Path $Root 'special-[1]') 'sp1'
Add-Worktree $special (Join-Path $Root 'special-$HOME') 'sp2'
Add-Worktree $special (Join-Path $Root "special-it's") 'sp3'
Add-Worktree $special (Join-Path $Root 'special-a&b;(c)') 'sp4'

# ---- plain：只有一個 worktree ----------------------------------------------
[void](New-Repo 'plain')

# ---- outside：不是 Git 儲存庫 ----------------------------------------------
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'outside') | Out-Null
