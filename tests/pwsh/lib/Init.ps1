# 每個測試檔開頭 dot-source 這一支：載入斷言、fixture 工具、畫面重播、按鍵驅動，
# 並把 gwt 模組載進來（-Force：確保測的是工作目錄裡這一份，不是之前載入過的舊版）。
$lib = $PSScriptRoot
. (Join-Path $lib 'Assert.ps1')
. (Join-Path $lib 'Fixture.ps1')
. (Join-Path $lib 'Screen.ps1')
. (Join-Path $lib 'Driver.ps1')
Import-Module (Join-Path $env:GWT_ROOT 'gwt.psm1') -Force

# 測試裡常用的跳脫字元
$ESC = [string][char]27
