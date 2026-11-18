# 相容性防線：gwt.psm1 與 install.ps1 宣稱支援 PowerShell 7.0（.NET Core 3.1），不能用到更新的 API 或語法。
#
# 這不是在 7.0 上實際執行——CI 跑的是 windows-latest 上的新版 pwsh，7.0 上有沒有問題只有在真的 7.0
# 上才看得到。這裡只是擋掉「已經知道」會在 7.0 壞掉的東西，避免同樣的錯再犯一次：
# 曾經用 SHA256.HashData 與 Convert.ToHexString（.NET 5 才有），在 7.0 上安裝與移除都會直接丟例外，
# 而開發環境是 7.7，完全看不出來（code review 才發現）。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

# 規則 = 正規表示式 + 為什麼不行。只掃程式碼，不掃註解（註解裡可以解釋「為什麼不用」）。
$rules = @(
  @{ Pattern = 'HashData\s*\(';             Why = 'SHA256.HashData 等靜態雜湊方法是 .NET 5 才有；改用 SHA256.Create().ComputeHash()' }
  @{ Pattern = '\bToHexString\s*\(';        Why = 'Convert.ToHexString 是 .NET 5 才有；改用 BitConverter.ToString() 再去掉 -' }
  @{ Pattern = '\bFromHexString\s*\(';      Why = 'Convert.FromHexString 是 .NET 5 才有' }
  @{ Pattern = '\?\.\w|\?\[';               Why = '空值條件運算子 ?. 與 ?[] 是 PowerShell 7.1 才有' }
  @{ Pattern = '\$PSStyle\b';               Why = '$PSStyle 是 PowerShell 7.2 才有' }
  @{ Pattern = 'PSNativeCommand\w+';        Why = '$PSNativeCommand* 偏好變數是 PowerShell 7.2／7.3 才有' }
  @{ Pattern = '\[System\.Text\.Rune\]|\bEnumerateRunes\b'; Why = 'Rune 的 PowerShell 用法在 7.0 上不穩，字元請自己以代理對處理' }
)

foreach ($file in 'gwt.psm1', 'install.ps1') {
  $lines = Get-Content -LiteralPath (Join-Path $env:GWT_ROOT $file)
  $code = for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].TrimStart().StartsWith('#')) { continue }
    [pscustomobject]@{ No = $i + 1; Text = $lines[$i] }
  }
  foreach ($rule in $rules) {
    $hits = @($code | Where-Object { $_.Text -match $rule.Pattern })
    if ($hits.Count -eq 0) {
      Add-TestPass "$file 沒有用到：$($rule.Why)"
    }
    else {
      Add-TestFail "$file 用到了：$($rule.Why)"
      foreach ($h in $hits) { Write-TestLine "        第 $($h.No) 行: $($h.Text.Trim())" }
    }
  }
}

# 模組宣告的最低版本與文件一致
$psm1 = Get-Content -LiteralPath (Join-Path $env:GWT_ROOT 'gwt.psm1') -Raw
Assert-True 'gwt.psm1 宣告 #Requires -Version 7.0' ($psm1 -match '(?m)^#Requires -Version 7\.0\s*$')

Complete-Tests
