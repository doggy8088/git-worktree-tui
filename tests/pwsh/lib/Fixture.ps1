# -----------------------------------------------------------------------------
# 讀取測試 fixture 內容的小工具（對應 tests/lib/fixture.zsh）
#
# 測試不要硬寫「第 3 筆是 shop-feature-login」這種假設，因為 worktree 的排序
# 由 Git 決定。這裡一律從 git worktree list --porcelain 取得順序，讓測試只
# 驗證「選了第 N 筆就會 cd 到第 N 筆」這件真正想驗的事。
#
# git 在 Windows 輸出正斜線；gwt 與 Get-Location 用原生分隔符，這裡統一轉過去。
# -----------------------------------------------------------------------------

function ConvertTo-NativeTestPath {
  param([string]$Path)
  if ($IsWindows) { return $Path.Replace('/', '\') }
  return $Path
}

# 所有 worktree 路徑（依 git 的順序）
function Get-FixturePaths {
  param([string]$Repo)
  $text = & git -C $Repo worktree list --porcelain
  $paths = foreach ($line in $text) {
    if ($line.StartsWith('worktree ')) { ConvertTo-NativeTestPath $line.Substring(9) }
  }
  return @($paths)
}

# Get-FixturePath <儲存庫路徑> <第幾筆，從 1 開始>
function Get-FixturePath {
  param([string]$Repo, [int]$Index)
  return (Get-FixturePaths $Repo)[$Index - 1]
}

function Get-FixtureCount {
  param([string]$Repo)
  return (Get-FixturePaths $Repo).Count
}

# 依路徑片段找出 worktree 的完整路徑（找不到就回傳空字串）
function Find-FixturePath {
  param([string]$Repo, [string]$Fragment)
  $hit = Get-FixturePaths $Repo | Where-Object { $_.Contains($Fragment) } | Select-Object -First 1
  if ($null -eq $hit) { return '' }
  return $hit
}

# 目前的位置（字串）
function Get-Here {
  return (Get-Location).Path
}

# 切到 fixture 裡的某個儲存庫
function Enter-Fixture {
  param([string]$Name)
  Set-Location -LiteralPath (Join-Path $env:GWT_FIXTURE $Name)
}
