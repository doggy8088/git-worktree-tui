#
# gwt 的模組清單（manifest），給 PowerShell Gallery 與 Import-Module 用。
#
# 版本號有三個地方必須一致：gwt.zsh 的 GWT_VERSION、gwt.psm1 的 $script:GwtVersion、這裡的 ModuleVersion，
# 發佈時還要等於 Git tag（v0.2.0 → 0.2.0）。tools/Build-PSGalleryPackage.ps1 與
# tests/pwsh/cases/19-gallery-package.ps1 都會檢查，不一致就不能打包。
#
# GUID 是這個模組在 PowerShell Gallery 上的身分，產生之後永遠不要改。
#
@{
  RootModule            = 'gwt.psm1'
  ModuleVersion         = '0.2.1'
  GUID                  = '262ddb7e-0c4d-499b-b21b-0f3754c8cdbd'
  Author                = 'Will 保哥 (Will Huang)'
  Copyright             = '(c) 2026 Will 保哥 (Will Huang). MIT License.'
  Description           = 'Interactive Git worktree switcher for PowerShell 7. Run gwt to list every worktree of the current repository, pick one with the arrow keys, j/k, a number or a fuzzy search (press /), and press Enter to Set-Location there. Keeps "cd -" working, and a cancel sets $? to false so "gwt && next-command" stops. Works with non-ASCII paths and wide (CJK, emoji) characters. Requires PowerShell 7.0 or later and Git.'

  # 只支援 PowerShell 7（Core）；Windows PowerShell 5.1 不支援
  PowerShellVersion     = '7.0'
  CompatiblePSEditions  = @('Core')

  # 明確列出，不要用 '*'：Gallery 與自動載入（打 gwt 就會載入模組）都靠這份清單
  FunctionsToExport     = @('gwt')
  CmdletsToExport       = @()
  VariablesToExport     = @()
  AliasesToExport       = @()

  PrivateData           = @{
    PSData = @{
      Tags                     = @('git', 'worktree', 'navigation', 'tui', 'cli', 'pwsh', 'PSEdition_Core')
      LicenseUri               = 'https://github.com/doggy8088/git-worktree-tui/blob/main/LICENSE'
      ProjectUri               = 'https://github.com/doggy8088/git-worktree-tui'
      ReleaseNotes             = 'https://github.com/doggy8088/git-worktree-tui/blob/main/CHANGELOG.md'
      RequireLicenseAcceptance = $false
    }
  }
}
