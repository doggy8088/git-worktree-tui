# =============================================================================
# gwt installer (PowerShell 7 / pwsh)
#
# One-line install:
#   irm https://gwt.gh.miniasp.com/install.ps1 | iex
#
# Pin a version (iex cannot take parameters, so wrap the script in a scriptblock):
#   & ([scriptblock]::Create((irm https://gwt.gh.miniasp.com/install.ps1))) -Version v0.2.0
#
# From a clone of the repository (uses the local gwt.psm1, no network):
#   pwsh -File install.ps1
#
# Uninstall:
#   & ([scriptblock]::Create((irm https://gwt.gh.miniasp.com/install.ps1))) -Uninstall
#
# Parameters:
#   -Version      release tag to install, e.g. v0.2.0 (default: the latest release;
#                 if it has no PowerShell version yet, falls back to main)
#   -Dir          install directory (default ~\.gwt)
#   -ProfilePath  profile that gets the import block (default
#                 $PROFILE.CurrentUserAllHosts, which VS Code's terminal also loads)
#   -Uninstall    remove gwt
#   -Help         show usage
#
# Environment variables (iex cannot take parameters; a parameter wins over these):
#   GWT_VERSION      same as -Version
#   GWT_INSTALL_DIR  same as -Dir
#   GWT_PROFILE      same as -ProfilePath
#
# Test-only (regular users never need these):
#   GWT_RAW_BASE     replaces https://raw.githubusercontent.com/doggy8088/git-worktree-tui
#   GWT_CDN_BASE     replaces https://cdn.jsdelivr.net/gh/doggy8088/git-worktree-tui
#   GWT_LATEST_URL   replaces https://github.com/doggy8088/git-worktree-tui/releases/latest
#
# Why this file is ASCII-only (the Chinese messages are \uXXXX escapes decoded by T):
#   * It is read through `irm | iex`. GitHub Pages sends no charset for .ps1, and a
#     BOM would arrive as U+FEFF and break iex, so it cannot be a BOM'd UTF-8 file.
#   * Windows PowerShell 5.1 reads a BOM-less file in the ANSI code page. On CJK
#     systems (cp950 etc.) a Chinese comment or string can swallow the newline or the
#     closing quote and the whole file fails to parse, which would hide the "please
#     use PowerShell 7" message below. ASCII survives every code page.
# Each message has its English meaning in the comment above it.
#
# Never `exit` at the top level: under iex that closes the user's terminal.
# =============================================================================
[CmdletBinding()]
param(
  [string]$Version,
  [string]$Dir,
  [string]$ProfilePath,
  [switch]$Uninstall,
  [switch]$Help
)

# Windows PowerShell 5.1 reaches this point too; refuse with a message it can read.
# English first, then the Chinese text decoded from escapes (so it is correct however
# the file was decoded): "Please run this in PowerShell 7 (pwsh); Windows PowerShell
# 5.1 is not supported."
if ($PSVersionTable.PSEdition -ne 'Core') {
  Write-Host 'gwt installer: please run this in PowerShell 7 (pwsh), not Windows PowerShell 5.1.' -ForegroundColor Red
  Write-Host ([regex]::Unescape('\u8acb\u5728 PowerShell 7 (pwsh) \u57f7\u884c\uff0c\u4e0d\u652f\u63f4 Windows PowerShell 5.1\u3002')) -ForegroundColor Red
  Write-Host '  https://aka.ms/powershell'
  $global:LASTEXITCODE = 1
  if ($PSCommandPath) { exit 1 }
  return
}

# All logic lives in this scriptblock: under iex the top level is the user's own
# session, and functions or variables left outside it would stay in their environment.
& {
  # Every failure must reach the catch at the bottom. With the default 'Continue', a
  # non-terminating error from Move-Item or Remove-Item (a locked file, a denied ACL)
  # would be printed and the script would carry on: rewrite the profile and report
  # success although the module was never replaced or removed. This is a local
  # variable of this scriptblock; the caller's preference is not touched.
  $ErrorActionPreference = 'Stop'

  $repo = 'doggy8088/git-worktree-tui'
  $beginMark = '# >>> gwt (git-worktree-tui) >>>'
  $endMark = '# <<< gwt (git-worktree-tui) <<<'
  $utf8 = [System.Text.UTF8Encoding]::new($false)

  # T decodes the \uXXXX escapes used by the messages below. It only touches \uXXXX,
  # so other backslashes (paths, regexes) are left alone.
  function T([string]$Text) {
    return [regex]::Replace($Text, '\\u([0-9a-fA-F]{4})', [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        [string][char][Convert]::ToInt32($m.Groups[1].Value, 16)
      })
  }
  # M fills a message template: only the template is decoded by T; the values (paths,
  # error text) are inserted afterwards, so a path that happens to contain a backslash-u sequence is left alone.
  function M([string]$Template) {
    return (T $Template) -f $args
  }
  function Say([string]$Text) { Write-Host $Text }
  function Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }

  function Show-Usage {
    # "gwt installer (PowerShell 7)", the three commands, then the parameter and
    # environment variable lists.
    Say (T @'
gwt \u5b89\u88dd\u8173\u672c\uff08PowerShell 7\uff09

  irm https://gwt.gh.miniasp.com/install.ps1 | iex
  & ([scriptblock]::Create((irm https://gwt.gh.miniasp.com/install.ps1))) -Version v0.2.0
  & ([scriptblock]::Create((irm https://gwt.gh.miniasp.com/install.ps1))) -Uninstall

\u53c3\u6578\uff1a
  -Version      \u8981\u5b89\u88dd\u7684 release \u6a19\u7c64\uff08\u9810\u8a2d\uff1a\u6700\u65b0 release\uff0c\u6c92\u6709 PowerShell \u7248\u5c31\u6539\u88dd main\uff09
  -Dir          \u5b89\u88dd\u76ee\u9304\uff08\u9810\u8a2d ~\.gwt\uff09
  -ProfilePath  \u8981\u5beb\u5165\u8f09\u5165\u8a2d\u5b9a\u7684 profile\uff08\u9810\u8a2d $PROFILE.CurrentUserAllHosts\uff09
  -Uninstall    \u79fb\u9664
  -Help         \u986f\u793a\u8aaa\u660e

\u74b0\u5883\u8b8a\u6578\uff08\u53c3\u6578\u512a\u5148\uff09\uff1aGWT_VERSION\u3001GWT_INSTALL_DIR\u3001GWT_PROFILE
'@)
  }

  # Resolve ~ and relative paths without requiring the path to exist.
  function Resolve-UserPath([string]$Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  }

  # ---- profile I/O: keep the file's encoding, BOM and newlines ------------------
  # The encoding is detected from the bytes, so apart from the block we add or remove
  # the file round-trips byte for byte.
  function Read-ProfileText([string]$Path) {
    $info = @{ Exists = $false; Text = ''; Encoding = $utf8; Preamble = [byte[]]@() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $info }
    $info.Exists = $true
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $n = $bytes.Length
    if ($n -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
      $info.Preamble = [byte[]]$bytes[0..2]
      $info.Text = $utf8.GetString($bytes, 3, $n - 3)
    }
    # UTF-32 first: the UTF-32LE BOM (FF FE 00 00) starts with the UTF-16LE BOM (FF FE),
    # so checking UTF-16 first would take a UTF-32 file for UTF-16 and append a block
    # in the wrong encoding, leaving a file that neither decoder can read.
    elseif ($n -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
      $info.Encoding = [System.Text.UTF32Encoding]::new($false, $false)
      $info.Preamble = [byte[]]$bytes[0..3]
      $info.Text = $info.Encoding.GetString($bytes, 4, $n - 4)
    }
    elseif ($n -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
      $info.Encoding = [System.Text.UTF32Encoding]::new($true, $false)
      $info.Preamble = [byte[]]$bytes[0..3]
      $info.Text = $info.Encoding.GetString($bytes, 4, $n - 4)
    }
    elseif ($n -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
      $info.Encoding = [System.Text.Encoding]::Unicode
      $info.Preamble = [byte[]]$bytes[0..1]
      $info.Text = $info.Encoding.GetString($bytes, 2, $n - 2)
    }
    elseif ($n -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
      $info.Encoding = [System.Text.Encoding]::BigEndianUnicode
      $info.Preamble = [byte[]]$bytes[0..1]
      $info.Text = $info.Encoding.GetString($bytes, 2, $n - 2)
    }
    else {
      try {
        $info.Text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
      }
      catch {
        # Not valid UTF-8 (e.g. an old ANSI file): map bytes 1:1 through Latin-1 so
        # nothing is corrupted on the way back out.
        $info.Encoding = [System.Text.Encoding]::GetEncoding(28591)
        $info.Text = $info.Encoding.GetString($bytes)
      }
    }
    return $info
  }

  function Write-ProfileText([string]$Path, $Info, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
      [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $body = $Info.Encoding.GetBytes($Text)
    [System.IO.File]::WriteAllBytes($Path, [byte[]]($Info.Preamble + $body))
  }

  $blockRegex = [regex]::new(
    '(?ms)^[ \t]*' + [regex]::Escape($beginMark) + '[ \t]*\r?\n.*?^[ \t]*' +
    [regex]::Escape($endMark) + '[ \t]*(?:\r?\n|\z)')

  # Remove the block we added. Install puts exactly ONE newline between the existing
  # content and the block (when there is any content), whether or not that content
  # ended with a newline: "A" becomes "A<nl><block>", "A<nl>" becomes "A<nl><nl><block>".
  # When the block is at the end of the file that one newline goes with it, which
  # returns both cases to the original bytes. The rule needs no saved state because the
  # two outputs differ, and it is exact for any original: empty, whitespace only, with
  # or without a final newline.
  function Remove-GwtBlock([string]$Text) {
    while ($true) {
      $m = $blockRegex.Match($Text)
      if (-not $m.Success) { return $Text }
      $before = $Text.Substring(0, $m.Index)
      $after = $Text.Substring($m.Index + $m.Length)
      if ($after.Length -eq 0 -and $before -match '\r?\n\z') {
        $before = $before -replace '\r?\n\z', ''
      }
      $Text = $before + $after
    }
  }

  # Lines outside our block that also load gwt (they would load it twice). We only
  # point them out, never touch them.
  function Get-ForeignLines([string]$Text) {
    $found = @()
    $inBlock = $false
    $no = 0
    foreach ($line in ($Text -split '\r?\n')) {
      $no++
      $t = $line.Trim()
      if ($t -eq $beginMark) { $inBlock = $true; continue }
      if ($t -eq $endMark) { $inBlock = $false; continue }
      if ($inBlock -or $t.StartsWith('#')) { continue }
      if ($line -match 'gwt\.psm1') { $found += ('{0}: {1}' -f $no, $line) }
    }
    return $found
  }

  # ---- download ------------------------------------------------------------------
  # Returns ok / notfound / error. -SkipHttpErrorCheck is not used: with -OutFile the
  # HTML body of a 404 would be written to the file.
  function Get-RemoteFile([string]$Url, [string]$Dest) {
    $status = 'error'
    for ($try = 1; $try -le 2; $try++) {
      try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop | Out-Null
        return 'ok'
      }
      catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        if ([int]$_.Exception.Response.StatusCode -eq 404) { return 'notfound' }
        $status = 'error'
      }
      catch {
        $status = 'error'
      }
    }
    return $status
  }

  # raw.githubusercontent.com first; jsDelivr only when raw cannot be reached (same as
  # install.sh). A 404 is final: the file is simply not at that ref.
  function Get-ModuleFile([string]$Ref, [string]$Dest) {
    $rawBase = if ($env:GWT_RAW_BASE) { $env:GWT_RAW_BASE.TrimEnd('/') } else { "https://raw.githubusercontent.com/$repo" }
    $cdnBase = if ($env:GWT_CDN_BASE) { $env:GWT_CDN_BASE.TrimEnd('/') } else { "https://cdn.jsdelivr.net/gh/$repo" }
    $result = Get-RemoteFile "$rawBase/$Ref/gwt.psm1" $Dest
    if ($result -eq 'error') {
      # "raw.githubusercontent.com is unreachable, using jsDelivr"
      Warn (T 'raw.githubusercontent.com \u53d6\u4e0d\u5230\uff0c\u6539\u7528 jsDelivr')
      $result = Get-RemoteFile "$cdnBase@$Ref/gwt.psm1" $Dest
    }
    return $result
  }

  # Tag of the latest release, or '' when there is none or it cannot be read.
  function Get-LatestTag {
    $url = if ($env:GWT_LATEST_URL) { $env:GWT_LATEST_URL } else { "https://github.com/$repo/releases/latest" }
    try {
      Invoke-WebRequest -Uri $url -MaximumRedirection 0 -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop | Out-Null
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
      # A redirect that is not followed is reported as an error; the target is in the
      # Location header. (-SkipHttpErrorCheck with -MaximumRedirection 0 throws an
      # InvalidOperationException instead, so it cannot be used here.)
      $loc = [string]$_.Exception.Response.Headers.Location
      if ($loc -match '/tag/([^/?#]+)$') { return $Matches[1] }
    }
    catch { }
    return ''
  }

  function Test-ModuleFile([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path, $utf8)
    # "The download does not look like gwt.psm1; aborted" / "...is incomplete; aborted"
    if ($text -notmatch 'GwtVersion') { throw (T '\u4e0b\u8f09\u5230\u7684\u5167\u5bb9\u4e0d\u50cf gwt.psm1\uff0c\u5df2\u4e2d\u6b62') }
    if ($text -notmatch 'Export-ModuleMember') { throw (T '\u4e0b\u8f09\u5230\u7684\u5167\u5bb9\u4e0d\u5b8c\u6574\uff0c\u5df2\u4e2d\u6b62') }
  }

  function Get-InstalledVersion([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path, $utf8)
    if ($text -match '\$script:GwtVersion = ''([^'']*)''') { return $Matches[1] }
    return '?'
  }

  # ---- parameters and paths --------------------------------------------------------
  if ($Help) { Show-Usage; return }

  # Any failure is caught here: print the message and set the exit code. exit is only
  # called when run as a file; under iex it would close the user's terminal.
  try {
    $versionArg = if ($Version) { $Version } elseif ($env:GWT_VERSION) { $env:GWT_VERSION } else { '' }
    $dirArg = if ($Dir) { $Dir } elseif ($env:GWT_INSTALL_DIR) { $env:GWT_INSTALL_DIR } else { Join-Path $HOME '.gwt' }
    $profileArg = if ($ProfilePath) { $ProfilePath } elseif ($env:GWT_PROFILE) { $env:GWT_PROFILE } else { $PROFILE.CurrentUserAllHosts }

    $installDir = Resolve-UserPath $dirArg
    $profileFile = Resolve-UserPath $profileArg
    $target = Join-Path $installDir 'gwt.psm1'

    # The import line in the profile. Under the home directory it is written with
    # $HOME (works after moving to another machine or account); otherwise as an
    # absolute path in single quotes (which expand neither $ nor backticks).
    function Get-ImportLine {
      $homeDir = $HOME.TrimEnd('\', '/')
      $sep = [System.IO.Path]::DirectorySeparatorChar
      if ($target.StartsWith($homeDir + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rest = $target.Substring($homeDir.Length)
        if ($rest -notmatch '[`$"'']') { return 'Import-Module "$HOME' + $rest + '"' }
      }
      return "Import-Module '" + $target.Replace("'", "''") + "'"
    }

    # Written next to the module when install had to CREATE the profile. It is how
    # uninstall tells "a file we made" (delete it again) from "an empty or
    # whitespace-only file the user already had" (restore it exactly).
    $createdMarker = Join-Path $installDir '.profile-created'

    # ---- uninstall -------------------------------------------------------------------
    if ($Uninstall) {
      $removed = $false
      $createdByUs = Test-Path -LiteralPath $createdMarker -PathType Leaf
      if (Test-Path -LiteralPath $profileFile -PathType Leaf) {
        $info = Read-ProfileText $profileFile
        $clean = Remove-GwtBlock $info.Text
        if ($clean -ne $info.Text) {
          if ($createdByUs -and $clean.Length -eq 0) {
            # We created this file and nothing but our block was ever in it: remove
            # it, back to the state before install.
            Remove-Item -LiteralPath $profileFile -Force
          }
          else {
            Write-ProfileText $profileFile $info $clean
          }
          $removed = $true
        }
      }
      # "Removed the gwt block from <profile>" / "<profile> has no gwt block"
      if ($removed) { Say (M '\u5df2\u5f9e {0} \u79fb\u9664 gwt \u8a2d\u5b9a' $profileFile) } else { Say (M '{0} \u88e1\u6c92\u6709 gwt \u8a2d\u5b9a' $profileFile) }
      if (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
        Say (M '\u5df2\u522a\u9664 {0}' $target)   # "Deleted <file>"
      }
      if ($createdByUs) { Remove-Item -LiteralPath $createdMarker -Force }
      if ((Test-Path -LiteralPath $installDir -PathType Container) -and -not (Get-ChildItem -LiteralPath $installDir -Force)) {
        Remove-Item -LiteralPath $installDir -Force
      }
      # Unload gwt from this session as well, if it was loaded.
      Get-Module gwt | Remove-Module -Force -ErrorAction SilentlyContinue
      return
    }

    # ---- install ---------------------------------------------------------------------
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('gwt-' + [guid]::NewGuid().ToString('N') + '.psm1')
    try {
      # Inside a clone, use the local file and stay offline. iex and scriptblocks have
      # no script path ($PSScriptRoot is empty), so they download.
      $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'gwt.psm1' } else { '' }
      if ($local -and (Test-Path -LiteralPath $local -PathType Leaf)) {
        Say (M '\u4f7f\u7528\u672c\u5730\u6a94\u6848\uff1a{0}' $local)   # "Using the local file: <path>"
        Copy-Item -LiteralPath $local -Destination $tmp -Force
      }
      else {
        $refs = @()
        $explicit = [bool]$versionArg
        if ($explicit) {
          $refs = @($versionArg)
        }
        else {
          $latest = Get-LatestTag
          if ($latest) { $refs += $latest }
          $refs += 'main'
        }

        $done = $false
        for ($i = 0; $i -lt $refs.Count -and -not $done; $i++) {
          $ref = $refs[$i]
          Say (M '\u4e0b\u8f09 gwt\uff08{0}\uff09\u2026' $ref)   # "Downloading gwt (<ref>)..."
          $result = Get-ModuleFile $ref $tmp
          if ($result -eq 'ok') {
            $done = $true
          }
          elseif ($result -eq 'notfound') {
            if ($explicit) {
              # "<ref> has no gwt.psm1: the PowerShell version was added after v0.1.0 and
              # this release does not include it. Use a newer version, or omit -Version
              # to install the latest from main."
              throw (M '\u627e\u4e0d\u5230 {0} \u7684 gwt.psm1\uff1aPowerShell \u7248\u662f v0.1.0 \u4e4b\u5f8c\u624d\u52a0\u5165\u7684\uff0c\u9019\u500b\u7248\u672c\u6c92\u6709\u3002\u8acb\u6539\u7528\u66f4\u65b0\u7684\u7248\u672c\uff0c\u6216\u7701\u7565 -Version \u5b89\u88dd main \u5206\u652f\u7684\u6700\u65b0\u7248\u3002' $ref)
            }
            if ($ref -ne 'main') {
              # "The latest release (<ref>) has no PowerShell version yet; installing main."
              Warn (M '\u6700\u65b0 release\uff08{0}\uff09\u9084\u4e0d\u542b PowerShell \u7248\uff0c\u6539\u5b89\u88dd main \u5206\u652f\u7684\u6700\u65b0\u7248\u3002' $ref)
            }
          }
          else {
            # "Downloading <ref> failed; check the network connection and try again."
            throw (M '\u4e0b\u8f09 {0} \u5931\u6557\uff0c\u8acb\u78ba\u8a8d\u7db2\u8def\u9023\u7dda\u5f8c\u518d\u8a66\u4e00\u6b21\u3002' $ref)
          }
        }
        # "No gwt.psm1 found to install."
        if (-not $done) { throw (T '\u627e\u4e0d\u5230\u53ef\u4ee5\u5b89\u88dd\u7684 gwt.psm1\u3002') }
      }

      Test-ModuleFile $tmp
      [void](New-Item -ItemType Directory -Path $installDir -Force)
      Move-Item -LiteralPath $tmp -Destination $target -Force
    }
    finally {
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }

    # ---- write the profile -----------------------------------------------------------
    $info = Read-ProfileText $profileFile
    $text = Remove-GwtBlock $info.Text
    $foreign = @(Get-ForeignLines $info.Text)

    $nl = if ($text -match '\r\n') { "`r`n" } elseif ($text -match '\n') { "`n" } else { [Environment]::NewLine }
    # Exactly one newline between the existing content and the block (see
    # Remove-GwtBlock, which removes exactly that one). Content that ends with a newline
    # gets a blank line before the block; content that does not gets the block on the
    # next line. Never add a second newline to "terminate" the last line: then "A" and
    # "A<nl>" would look the same after install and uninstall could not tell them apart.
    if ($text.Length -gt 0) { $text += $nl }
    $text += $beginMark + $nl + (Get-ImportLine) + $nl + $endMark + $nl
    Write-ProfileText $profileFile $info $text
    if (-not $info.Exists) {
      # We created the profile: remember it, so uninstall deletes it again
      [void](New-Item -ItemType File -Path $createdMarker -Force)
    }

    # "Installed to <file> (version <v>)" / "Added the import block to <profile>"
    Say (M '\u5df2\u5b89\u88dd\u5230 {0}\uff08\u7248\u672c {1}\uff09' $target (Get-InstalledVersion $target))
    Say (M '\u5df2\u5728 {0} \u52a0\u5165\u8f09\u5165\u8a2d\u5b9a' $profileFile)

    if ($foreign.Count -gt 0) {
      Warn ''
      # "Note: the profile has other lines that load gwt; they cause a double load, you
      # should delete them:"
      Warn (T '\u6ce8\u610f\uff1aprofile \u88e1\u9084\u6709\u5176\u4ed6\u8f09\u5165 gwt \u7684\u8a2d\u5b9a\uff0c\u6703\u9020\u6210\u91cd\u8907\u8f09\u5165\uff0c\u5efa\u8b70\u522a\u6389\uff1a')
      foreach ($f in $foreign) { Warn "  $f" }
    }

    # Advisory only: if the policy cannot even be read, skip the warning.
    $policy = ''
    try { $policy = [string](Get-ExecutionPolicy) } catch { }
    if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
      Warn ''
      # "Note: the execution policy is <p>, so the profile will not load in new terminals.
      # To allow it (affects only your account):"
      Warn (M '\u6ce8\u610f\uff1a\u76ee\u524d\u7684\u57f7\u884c\u539f\u5247\u662f {0}\uff0c\u958b\u65b0\u7d42\u7aef\u6a5f\u6642 profile \u4e0d\u6703\u88ab\u8f09\u5165\u3002' $policy)
      Warn (T '\u8981\u5141\u8a31\u7684\u8a71\uff08\u53ea\u5f71\u97ff\u4f60\u81ea\u5df1\u7684\u5e33\u865f\uff09\uff1a')
      Warn '  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'
    }

    # Under iex or a scriptblock this shell is the one the user is typing in, so load
    # gwt into it and no restart is needed. Under pwsh -File we are a child process and
    # loading would do nothing, so only tell the user how.
    $loaded = $false
    if (-not $PSCommandPath) {
      try {
        Import-Module -Name $target -Global -Force -DisableNameChecking -ErrorAction Stop
        $loaded = $true
      }
      catch {
        # "Loading into the current session failed: <reason>"
        Warn (M '\u8f09\u5165\u5230\u76ee\u524d\u7684\u5de5\u4f5c\u968e\u6bb5\u5931\u6557\uff1a{0}' $_.Exception.Message)
      }
    }

    Say ''
    if ($loaded) {
      Say (T '\u5df2\u8f09\u5165\u5230\u76ee\u524d\u7684\u8996\u7a97\uff0c\u73fe\u5728\u5c31\u53ef\u4ee5\u7528\uff1a')   # "Loaded into this window, you can use it now:"
    }
    else {
      # "Reopen the terminal, or run Import-Module "<file>" in this window, then use:"
      Say (M '\u91cd\u65b0\u958b\u555f\u7d42\u7aef\u6a5f\uff0c\u6216\u5728\u76ee\u524d\u8996\u7a97\u57f7\u884c Import-Module "{0}" \u5f8c\u5c31\u53ef\u4ee5\u7528\uff1a' $target)
    }
    Say (T '  gwt              # \u4e92\u52d5\u5f0f\u9078\u55ae')   # interactive menu
    Say (T '  gwt --list       # \u53ea\u5370\u8def\u5f91')     # print paths only
    Say (T '  gwt --help       # \u5168\u90e8\u9078\u9805')     # all options
  }
  catch {
    # "Error: <message>"
    Write-Host (M '\u932f\u8aa4\uff1a{0}' $_.Exception.Message) -ForegroundColor Red
    $global:LASTEXITCODE = 1
    if ($PSCommandPath) { exit 1 }
  }
}
