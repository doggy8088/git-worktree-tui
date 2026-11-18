# 迴歸測試：分支名稱與路徑裡的特殊字元不能被當成格式字串解讀。
# zsh 版的 %b 問題，在 PowerShell 的對應就是 -f 的 {0}：分支名稱可以含大括號。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

function Draw {
  param([string[]]$Paths, [string[]]$Branches)
  Invoke-InGwt {
    param($p, $b)
    Initialize-GwtMessages
    Reset-GwtState
    $script:Paths.AddRange([string[]]$p)
    $script:Branches.AddRange([string[]]$b)
    $script:Heads.AddRange([string[]]@('1234567') * $p.Count)
    $script:Count = $p.Count
    $script:Current = ''
    $script:Width = 120
    $script:Height = 24
    $script:Selected = 1
    $script:Style = @{ Reset = ''; Bar = ''; Branch = ''; Mark = ''; Dim = '' }
    Add-GwtList
    $script:Buf.ToString()
  } @($Paths, $Branches)
}

$text = Draw @('/repos/100%s-discount') @('a\nb\tc')
Assert-Contains '反斜線 n 維持字面' 'a\nb\tc' $text
Assert-NotContains '沒有被轉成真正的換行' "`nb" $text
Assert-Contains '路徑中的百分比符號原樣保留' '/repos/100%s-discount' $text

$text = Draw @('/repos/{0}-x') @('{0}{1}{2}')
Assert-Contains '分支裡的 {0}{1}{2} 原樣保留' '[{0}{1}{2}]' $text
Assert-Contains '路徑裡的 {0} 原樣保留' '/repos/{0}-x' $text

# 表頭裡的搜尋字串也是使用者資料：{0} 不能被當成位置參數
$header = Invoke-InGwt {
  Initialize-GwtMessages
  Reset-GwtState
  $script:Search = $true
  $script:Query = '{0}{1}'
  $script:Count = 3
  $script:Width = 120
  Add-GwtHeader
  $script:Buf.ToString()
}
Assert-Contains '搜尋字串含 {0}{1} 時原樣顯示' '搜尋：{0}{1}▏' $header
Assert-Contains '符合筆數照常顯示' '3 筆符合' $header

# 沒有被當成跳脫序列：路徑裡的 ESC 字元不會讓 gwt 重設游標位置之類的
$text = Draw @('/repos/plain') @('main')
Assert-NotContains '一般輸出不含多餘的 CSI' ([string][char]27 + '[?') $text

Complete-Tests
