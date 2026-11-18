# Read-GwtPorcelain 解析 porcelain：多筆、路徑含空白、detached HEAD、CRLF、附註行
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

# 直接用固定的 porcelain 文字測試，不依賴實際儲存庫
$porcelain = @'
worktree /repos/shop
HEAD 89ae97a1b2c3d4e5f6a7b8
branch refs/heads/main

worktree /repos/shop feature api
HEAD 0123456789abcdef0123
branch refs/heads/feature/search-api
locked reason

worktree /repos/shop-hotfix
HEAD fedcba9876543210fedc
detached

worktree /repos/bare.git
bare

'@

function Read-Text {
  param([string]$Text)
  Invoke-InGwt {
    param($t)
    Initialize-GwtMessages
    Reset-GwtState
    Read-GwtPorcelain -Text $t -Keyword ''
    [pscustomobject]@{ Count = $script:Count; Paths = @($script:Paths); Branches = @($script:Branches); Heads = @($script:Heads) }
  } @($Text)
}

$r = Read-Text $porcelain
Assert-Rc 'bare 沒有 HEAD 與分支但仍是一筆，共解析出 4 筆' 4 $r.Count
Assert-Eq '第 1 筆路徑' (ConvertTo-NativeTestPath '/repos/shop') $r.Paths[0]
Assert-Eq '第 2 筆路徑含空白不被切開' (ConvertTo-NativeTestPath '/repos/shop feature api') $r.Paths[1]
Assert-Eq '第 3 筆路徑' (ConvertTo-NativeTestPath '/repos/shop-hotfix') $r.Paths[2]
Assert-Eq '分支去掉 refs/heads/ 前綴' 'feature/search-api' $r.Branches[1]
Assert-Eq 'detached HEAD 標成 detached' 'detached' $r.Branches[2]
Assert-Eq 'commit 只保留前 7 碼' '89ae97a' $r.Heads[0]
Assert-Eq 'locked 附註行不影響分支' 'feature/search-api' $r.Branches[1]

# 最後一組沒有結尾空行也要收進來
$r = Read-Text "worktree /repos/only`nHEAD 1234567890abcdef`nbranch refs/heads/main"
Assert-Rc '結尾沒有空行也能解析' 1 $r.Count

# Windows 上的 git 可能輸出 CRLF，路徑不能帶著 \r
$r = Read-Text "worktree /repos/crlf`r`nHEAD 1234567890abcdef`r`nbranch refs/heads/main`r`n`r`n"
Assert-Rc 'CRLF 也能解析' 1 $r.Count
Assert-Eq 'CRLF 路徑沒有殘留 \r' (ConvertTo-NativeTestPath '/repos/crlf') $r.Paths[0]
Assert-Eq 'CRLF 分支沒有殘留 \r' 'main' $r.Branches[0]

# 路徑與分支裡的特殊字元：反斜線、大括號、百分比
$r = Read-Text "worktree /repos/{0}-100%s`nHEAD 1234567890abcdef`nbranch refs/heads/a\nb{1}`n`n"
Assert-Eq '路徑含 {0} 與 % 原樣保留' (ConvertTo-NativeTestPath '/repos/{0}-100%s') $r.Paths[0]
Assert-Eq '分支含反斜線與 {1} 原樣保留' 'a\nb{1}' $r.Branches[0]

# Windows 上 git 輸出正斜線，gwt 轉成原生分隔符（其他平台維持原樣）
$r = Read-Text "worktree C:/Users/me/repo`nHEAD 1234567890abcdef`nbranch refs/heads/main`n`n"
if ($IsWindows) {
  Assert-Eq 'Windows 路徑轉成反斜線' 'C:\Users\me\repo' $r.Paths[0]
}
else {
  Assert-Eq '非 Windows 路徑維持原樣' 'C:/Users/me/repo' $r.Paths[0]
}

Complete-Tests
