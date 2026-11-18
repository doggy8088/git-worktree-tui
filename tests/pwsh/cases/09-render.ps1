# 選單列內容：光棒只在選取列、目前位置用黃色標註、分支用青色
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

function Draw {
  param([int]$Selected)
  Invoke-InGwt {
    param($sel)
    Initialize-GwtMessages
    Reset-GwtState
    $script:Paths.AddRange([string[]]@('/repos/shop', '/repos/shop-feature'))
    $script:Branches.AddRange([string[]]@('main', 'feature/login'))
    $script:Heads.AddRange([string[]]@('89ae97a', '89ae97a'))
    $script:Count = 2
    $script:Current = '/repos/shop'
    $script:Width = 80
    $script:Height = 24
    $script:Selected = $sel
    # 非 tty 環境下 Initialize-GwtStyle 會關閉顏色，這裡直接指定，才能驗證上色位置
    $c = [string][char]27 + '['
    $script:Style = @{ Reset = "${c}0m"; Bar = "${c}1;30;46m"; Branch = "${c}36m"; Mark = "${c}33m"; Dim = "${c}2m" }
    Add-GwtList
    $script:Buf.ToString()
  } @($Selected)
}

$e = [string][char]27
$bar = "$e[1;30;46m"

$text = Draw 1
$lines = @($text -split "`n" | Where-Object { $_ -ne '' })
Assert-Rc '畫出兩列' 2 $lines.Count
Assert-Contains '選取列有光棒' $bar $lines[0]
Assert-NotContains '未選取列沒有光棒' $bar $lines[1]
Assert-Contains '目前位置用黃色標註' "$e[33m" $lines[0]
Assert-Contains '分支名稱用青色' "$e[36m[main]" $lines[0]
Assert-Contains '未選取列也有分支名稱' "$e[36m[feature/login]" $lines[1]
Assert-Contains '顯示 commit 前 7 碼' '(89ae97a)' $lines[0]
Assert-Contains '每列先清掉整列' "`r$e[2K" $lines[0]

# 光棒只反白到路徑為止：重設碼要出現在分支之前
$headPart = $lines[0].Substring(0, $lines[0].IndexOf("$e[0m"))
Assert-Contains '光棒範圍含路徑' '/repos/shop' $headPart
Assert-NotContains '光棒範圍不含分支' 'feature' $headPart

# 切換選取後，光棒應該換到第二列
$lines = @((Draw 2) -split "`n" | Where-Object { $_ -ne '' })
Assert-NotContains '換選取後第一列沒有光棒' $bar $lines[0]
Assert-Contains '換選取後第二列有光棒' $bar $lines[1]

# 目前位置的比對：Windows 不分大小寫、容許結尾分隔符
$mark = Invoke-InGwt { Initialize-GwtMessages; Test-GwtSamePath 'C:\Repo\Shop\' 'c:\repo\shop' }
if ($IsWindows) { Assert-True 'Windows 路徑比對不分大小寫且忽略結尾分隔符' $mark }
else { Assert-True '非 Windows 路徑比對區分大小寫' (-not $mark) }

Complete-Tests
