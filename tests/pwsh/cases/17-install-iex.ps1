# 一行安裝的真正流程：irm https://.../install.ps1 | iex（沒有 $PSScriptRoot、要下載 gwt.psm1），
# 以及給 iex 帶不了參數時用的 & ([scriptblock]::Create((irm ...))) -Version ...。
#
# 用本機的 HttpListener 當伺服器，install.ps1 以 application/octet-stream 且沒有 charset 提供
# （預期 GitHub Pages 對 .ps1 就是這樣；實際送什麼要發佈後才驗得到）。下載網址用
# GWT_RAW_BASE／GWT_CDN_BASE／GWT_LATEST_URL（install.ps1 標明「只給測試用」的覆寫）指向本機，
# 安裝目錄與 profile 一律指到暫存目錄，絕不碰真正的 $PROFILE 與 ~\.gwt。
. "$env:GWT_ROOT\tests\pwsh\lib\Init.ps1"

$installer = Join-Path $env:GWT_ROOT 'install.ps1'
$module = Join-Path $env:GWT_ROOT 'gwt.psm1'
$pwshExe = (Get-Process -Id $PID).Path
$moduleBytes = [System.IO.File]::ReadAllBytes($module)
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('gwt-iex-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null

# 找一個空的埠
$probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
$base = "http://127.0.0.1:$port"

$routes = @{
  '/install.ps1'                  = @{ Bytes = [System.IO.File]::ReadAllBytes($installer); Type = 'application/octet-stream' }
  '/raw/main/gwt.psm1'            = @{ Bytes = $moduleBytes; Type = 'text/plain; charset=utf-8' }
  '/raw/v9.9.9/gwt.psm1'          = @{ Bytes = $moduleBytes; Type = 'text/plain; charset=utf-8' }
  '/raw/junk/gwt.psm1'            = @{ Bytes = [System.Text.Encoding]::UTF8.GetBytes('<html><body>not a module</body></html>'); Type = 'text/html' }
  '/cdn@main/gwt.psm1'            = @{ Bytes = $moduleBytes; Type = 'text/plain; charset=utf-8' }
  '/latest-without-module'        = @{ Status = 302; Location = "$base/releases/tag/v0.0.1" }
  '/latest-with-module'           = @{ Status = 302; Location = "$base/releases/tag/v9.9.9" }
}
$requests = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("$base/")
$listener.Start()
$server = [powershell]::Create()
[void]$server.AddScript({
    param($listener, $routes, $requests)
    while ($listener.IsListening) {
      try { $ctx = $listener.GetContext() } catch { break }
      $path = $ctx.Request.Url.AbsolutePath
      $requests.Enqueue($path)
      $res = $ctx.Response
      try {
        if ($routes.ContainsKey($path)) {
          $r = $routes[$path]
          if ($r.Status -eq 302) { $res.StatusCode = 302; $res.RedirectLocation = $r.Location; $res.ContentLength64 = 0 }
          else { $res.StatusCode = 200; $res.ContentType = $r.Type; $res.ContentLength64 = $r.Bytes.Length; $res.OutputStream.Write($r.Bytes, 0, $r.Bytes.Length) }
        }
        else {
          $b = [System.Text.Encoding]::UTF8.GetBytes('<html>not found</html>')
          $res.StatusCode = 404; $res.ContentType = 'text/html'; $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b, 0, $b.Length)
        }
      }
      finally { $res.Close() }
    }
  }).AddArgument($listener).AddArgument($routes).AddArgument($requests)
$serverHandle = $server.BeginInvoke()

function Reset-Requests { $x = $null; while ($requests.TryDequeue([ref]$x)) { } }

# 子行程裡跑一段命令；環境變數只給這一個子行程。Command 結尾自己帶 exit $LASTEXITCODE。
function Invoke-Child {
  param([string]$Command, [hashtable]$Env)
  $saved = @{}
  foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
  try {
    $out = & $pwshExe -NoProfile -NonInteractive -Command $Command 2>&1
    return [pscustomobject]@{ Rc = $LASTEXITCODE; Output = (@($out | ForEach-Object { "$_" }) -join "`n") }
  }
  finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}

function New-Sandbox {
  $dir = Join-Path $work ([guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Path $dir | Out-Null
  return [pscustomobject]@{ Root = $dir; Profile = (Join-Path $dir 'profile.ps1'); Dir = (Join-Path $dir 'dotgwt') }
}
# jsDelivr 的網址是 <CDN 基底>@<標籤>/gwt.psm1，基底要以路徑結尾（真的是 .../gh/<owner>/<repo>）；
# 只給 http://127.0.0.1:埠 的話 @ 會變成「使用者資訊」，主機名稱就變成標籤了。
function Get-Env { param($Sb, [string]$Latest) @{ GWT_RAW_BASE = "$base/raw"; GWT_CDN_BASE = "$base/cdn"; GWT_LATEST_URL = "$base/$Latest"; GWT_INSTALL_DIR = $Sb.Dir; GWT_PROFILE = $Sb.Profile } }

try {
  # --- irm | iex：最新 release 還沒有 PowerShell 版 → 明說並改裝 main -----------------------
  $sb = New-Sandbox; Reset-Requests
  $r = Invoke-Child "irm '$base/install.ps1' | iex; 'CMD=' + (Get-Command gwt -ErrorAction SilentlyContinue).CommandType; 'VER=' + (gwt --version); exit `$LASTEXITCODE" (Get-Env $sb 'latest-without-module')
  $asked = @($requests.ToArray())
  Assert-Rc '[iex、最新 release 沒有 PowerShell 版] 結束碼 0' 0 $r.Rc
  Assert-True '[iex、最新 release 沒有 PowerShell 版] 模組裝到 GWT_INSTALL_DIR' (Test-Path -LiteralPath (Join-Path $sb.Dir 'gwt.psm1'))
  Assert-Eq '[iex、最新 release 沒有 PowerShell 版] 裝進去的就是 main 上的模組' (Get-FileHash -LiteralPath $module).Hash (Get-FileHash -LiteralPath (Join-Path $sb.Dir 'gwt.psm1')).Hash
  Assert-True '[iex、最新 release 沒有 PowerShell 版] 先試了最新 release 的標籤，找不到才改抓 main' (($asked -contains '/raw/v0.0.1/gwt.psm1') -and ($asked -contains '/raw/main/gwt.psm1'))
  Assert-Rc '[iex、最新 release 沒有 PowerShell 版] block 寫進 GWT_PROFILE' 1 ([regex]::Matches((Get-Content -LiteralPath $sb.Profile -Raw), '>>> gwt')).Count
  Assert-Contains '[iex、最新 release 沒有 PowerShell 版] 裝完立刻載入到目前的工作階段（不必重開）' 'CMD=Function' $r.Output
  Assert-Contains '[iex、最新 release 沒有 PowerShell 版] 載入的 gwt 能跑' 'VER=gwt ' $r.Output
  Assert-NotContains '[iex] 沒有把 install.ps1 的內部函式留在使用者的工作階段' 'Resolve-UserPath' $r.Output

  # --- irm | iex：最新 release 有 PowerShell 版 → 用那個 release，不去抓 main -------------------
  $sb = New-Sandbox; Reset-Requests
  $r = Invoke-Child "irm '$base/install.ps1' | iex; exit `$LASTEXITCODE" (Get-Env $sb 'latest-with-module')
  $asked = @($requests.ToArray())
  Assert-Rc '[iex、最新 release 有 PowerShell 版] 結束碼 0' 0 $r.Rc
  Assert-True '[iex、最新 release 有 PowerShell 版] 抓的是該 release 的檔案' ($asked -contains '/raw/v9.9.9/gwt.psm1')
  Assert-True '[iex、最新 release 有 PowerShell 版] 沒有多抓 main' (-not ($asked -contains '/raw/main/gwt.psm1'))

  # --- 再跑一次 = 更新：不重複加行 -----------------------------------------------------------
  $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($sb.Profile))
  $r = Invoke-Child "irm '$base/install.ps1' | iex; exit `$LASTEXITCODE" (Get-Env $sb 'latest-with-module')
  Assert-Rc '[iex 再跑一次] 結束碼 0' 0 $r.Rc
  Assert-Eq '[iex 再跑一次] profile 逐位元組不變（沒有重複加行）' $before ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($sb.Profile)))

  # --- GWT_VERSION（iex 沒辦法帶參數的版本指定）-----------------------------------------------
  $sb = New-Sandbox; Reset-Requests
  $env2 = Get-Env $sb 'latest-without-module'; $env2['GWT_VERSION'] = 'v9.9.9'
  $r = Invoke-Child "irm '$base/install.ps1' | iex; exit `$LASTEXITCODE" $env2
  Assert-Rc '[iex、GWT_VERSION] 結束碼 0' 0 $r.Rc
  Assert-True '[iex、GWT_VERSION] 抓的是指定的版本，沒有去查最新 release' ((@($requests.ToArray()) -contains '/raw/v9.9.9/gwt.psm1') -and -not (@($requests.ToArray()) -contains '/latest-without-module'))

  # --- scriptblock 形式帶參數：指定的版本沒有 PowerShell 版 → 明確失敗，什麼都不裝 -----------------
  $sb = New-Sandbox; Reset-Requests
  $r = Invoke-Child "& ([scriptblock]::Create((irm '$base/install.ps1'))) -Version v0.0.1 -Dir '$($sb.Dir)' -ProfilePath '$($sb.Profile)'; exit `$LASTEXITCODE" (Get-Env $sb 'latest-with-module')
  Assert-Rc '[scriptblock -Version、該版本沒有模組] 結束碼 1' 1 $r.Rc
  Assert-True '[scriptblock -Version、該版本沒有模組] 沒有裝任何東西' (-not (Test-Path -LiteralPath (Join-Path $sb.Dir 'gwt.psm1')))
  Assert-True '[scriptblock -Version、該版本沒有模組] 沒有建立 profile' (-not (Test-Path -LiteralPath $sb.Profile))
  Assert-True '[scriptblock -Version、該版本沒有模組] 指定版本就不退而求其次抓 main' (-not (@($requests.ToArray()) -contains '/raw/main/gwt.psm1'))

  # --- 抓到的不是 gwt.psm1（例如被導向一個 HTML 頁面）→ 拒絕，不安裝 ----------------------------
  $sb = New-Sandbox
  $r = Invoke-Child "irm '$base/install.ps1' | iex; exit `$LASTEXITCODE" ((Get-Env $sb 'latest-with-module') + @{ GWT_VERSION = 'junk' })
  Assert-Rc '[下載到的不是模組] 結束碼 1' 1 $r.Rc
  Assert-True '[下載到的不是模組] 沒有裝任何東西' (-not (Test-Path -LiteralPath (Join-Path $sb.Dir 'gwt.psm1')))

  # --- raw.githubusercontent.com 連不上 → 改用 jsDelivr -----------------------------------------
  $sb = New-Sandbox; Reset-Requests
  $deadPort = ([System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0) | ForEach-Object { $_.Start(); $p = $_.LocalEndpoint.Port; $_.Stop(); $p })
  $env3 = Get-Env $sb 'latest-without-module'; $env3['GWT_RAW_BASE'] = "http://127.0.0.1:$deadPort/raw"; $env3['GWT_VERSION'] = 'main'
  $r = Invoke-Child "irm '$base/install.ps1' | iex; exit `$LASTEXITCODE" $env3
  Assert-Rc '[raw 連不上] 結束碼 0' 0 $r.Rc
  Assert-True '[raw 連不上] 改從 CDN 抓到了模組' ((Test-Path -LiteralPath (Join-Path $sb.Dir 'gwt.psm1')) -and (@($requests.ToArray()) -contains '/cdn@main/gwt.psm1'))

  # --- 移除（scriptblock 形式）-----------------------------------------------------------------
  $sb = New-Sandbox
  [void](Invoke-Child "irm '$base/install.ps1' | iex; exit `$LASTEXITCODE" (Get-Env $sb 'latest-with-module'))
  $r = Invoke-Child "& ([scriptblock]::Create((irm '$base/install.ps1'))) -Uninstall; exit `$LASTEXITCODE" (Get-Env $sb 'latest-with-module')
  Assert-Rc '[scriptblock -Uninstall] 結束碼 0' 0 $r.Rc
  Assert-True '[scriptblock -Uninstall] 模組與安裝目錄都清掉了' (-not (Test-Path -LiteralPath $sb.Dir))
  Assert-True '[scriptblock -Uninstall] 安裝時建立的 profile 也一併刪掉' (-not (Test-Path -LiteralPath $sb.Profile))
}
finally {
  $listener.Stop(); $listener.Close()
  try { $server.Stop() } catch { }
  $server.Dispose()
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-Tests
