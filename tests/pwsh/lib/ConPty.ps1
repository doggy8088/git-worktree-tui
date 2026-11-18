# -----------------------------------------------------------------------------
# 在 Windows 的偽主控台（ConPTY）裡跑真正的 pwsh，送真正的按鍵
#
# 按鍵驅動測試（Driver.ps1）用測試掛鉤取代了 [Console]::ReadKey 與輸出，跑得快、
# 不會因為時間差而不穩，但它沒走過真正的主控台：ReadKey、VT 序列、Esc 與方向鍵的
# 翻譯、TreatControlCAsInput、$Host.UI.Write 都沒被驗證到。這裡補上那一塊。
#
# 做法：CreatePseudoConsole 建一個偽主控台，把 pwsh 掛在上面，從輸入管線寫入 VT 位元組
# （ESC[B 是方向鍵下、\r 是 Enter、\x1b 是 Esc、\x03 是 Ctrl+C），ConPTY 會把它們
# 翻成主控台輸入事件，pwsh 看到的就跟使用者在 Windows Terminal 裡按鍵一模一樣。
# 輸出則是 ConPTY 重新渲染後的 VT 串流，交給 Screen.ps1 重播成使用者實際看到的畫面。
#
# 只有 Windows 10 1809 以上才有 CreatePseudoConsole。
# -----------------------------------------------------------------------------

if (-not ('GwtConPty' -as [type])) {
  Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class GwtConPty : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    struct COORD { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, IntPtr lpPipeAttributes, int nSize);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern int CreatePseudoConsole(COORD size, IntPtr hInput, IntPtr hOutput, uint dwFlags, out IntPtr phPC);
    [DllImport("kernel32.dll")]
    static extern void ClosePseudoConsole(IntPtr hPC);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateProcThreadAttribute(IntPtr lpAttributeList, uint dwFlags, IntPtr Attribute, IntPtr lpValue, IntPtr cbSize, IntPtr lpPreviousValue, IntPtr lpReturnSize);
    [DllImport("kernel32.dll")]
    static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes,
        bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    static readonly IntPtr PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = (IntPtr)0x00020016;

    IntPtr hPC, inWrite, outRead, hProcess, hThread, attrList;
    FileStream input;
    Thread reader;
    readonly MemoryStream captured = new MemoryStream();
    readonly object gate = new object();
    bool disposed;

    public static GwtConPty Start(string commandLine, string workingDirectory, int cols, int rows)
    {
        var pty = new GwtConPty();
        pty.Launch(commandLine, workingDirectory, cols, rows);
        return pty;
    }

    void Launch(string commandLine, string cwd, int cols, int rows)
    {
        IntPtr inRead, outWrite;
        if (!CreatePipe(out inRead, out inWrite, IntPtr.Zero, 0)) throw new InvalidOperationException("CreatePipe(in) failed: " + Marshal.GetLastWin32Error());
        if (!CreatePipe(out outRead, out outWrite, IntPtr.Zero, 0)) throw new InvalidOperationException("CreatePipe(out) failed: " + Marshal.GetLastWin32Error());

        var size = new COORD { X = (short)cols, Y = (short)rows };
        int hr = CreatePseudoConsole(size, inRead, outWrite, 0, out hPC);
        if (hr != 0) throw new InvalidOperationException("CreatePseudoConsole failed: 0x" + hr.ToString("x"));
        // ConPTY 已經複製了這兩端，我們自己的那份可以關掉
        CloseHandle(inRead);
        CloseHandle(outWrite);

        var listSize = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref listSize);
        attrList = Marshal.AllocHGlobal(listSize);
        if (!InitializeProcThreadAttributeList(attrList, 1, 0, ref listSize)) throw new InvalidOperationException("InitializeProcThreadAttributeList failed");
        if (!UpdateProcThreadAttribute(attrList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, hPC, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero))
            throw new InvalidOperationException("UpdateProcThreadAttribute failed: " + Marshal.GetLastWin32Error());

        var si = new STARTUPINFOEX();
        si.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
        si.lpAttributeList = attrList;
        // 一定要帶 STARTF_USESTDHANDLES 並把三個標準代碼留空：否則當呼叫端自己的 stdin/stdout
        // 被導向（CI、這類工具的工作階段），子行程會繼承那些管線而不是偽主控台，
        // 看起來就像「不是互動式終端機」。node-pty 也是這樣做。
        si.StartupInfo.dwFlags = 0x00000100;
        PROCESS_INFORMATION pi;
        if (!CreateProcessW(null, commandLine, IntPtr.Zero, IntPtr.Zero, false, EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                IntPtr.Zero, cwd, ref si, out pi))
            throw new InvalidOperationException("CreateProcess failed: " + Marshal.GetLastWin32Error());
        hProcess = pi.hProcess;
        hThread = pi.hThread;

        input = new FileStream(new SafeFileHandle(inWrite, false), FileAccess.Write, 1, false);
        reader = new Thread(ReadLoop) { IsBackground = true };
        reader.Start();
    }

    void ReadLoop()
    {
        var stream = new FileStream(new SafeFileHandle(outRead, false), FileAccess.Read, 4096, false);
        var buf = new byte[4096];
        try
        {
            while (true)
            {
                int n = stream.Read(buf, 0, buf.Length);
                if (n <= 0) break;
                lock (gate) captured.Write(buf, 0, n);
            }
        }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
    }

    /// <summary>送出文字（UTF-8）。VT 序列就是按鍵：ESC[B 下、\r Enter、\x1b Esc、\x03 Ctrl+C。</summary>
    public void Send(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        input.Write(bytes, 0, bytes.Length);
        input.Flush();
    }

    /// <summary>目前為止收到的全部輸出（UTF-8 解碼）。</summary>
    public string Output()
    {
        lock (gate) return Encoding.UTF8.GetString(captured.ToArray());
    }

    public bool WaitForText(string needle, int timeoutMs)
    {
        var deadline = Environment.TickCount + timeoutMs;
        while (Environment.TickCount < deadline)
        {
            if (Output().Contains(needle)) return true;
            if (HasExited()) return Output().Contains(needle);
            Thread.Sleep(25);
        }
        return false;
    }

    public bool HasExited() { return WaitForSingleObject(hProcess, 0) == 0; }

    public bool WaitForExit(int timeoutMs, out int exitCode)
    {
        exitCode = -1;
        if (WaitForSingleObject(hProcess, (uint)timeoutMs) != 0) return false;
        uint code;
        GetExitCodeProcess(hProcess, out code);
        exitCode = unchecked((int)code);
        return true;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        try { if (hProcess != IntPtr.Zero && !HasExited()) TerminateProcess(hProcess, 1); } catch { }
        if (hPC != IntPtr.Zero) ClosePseudoConsole(hPC);   // 讀取執行緒還在排空輸出，不會卡住
        if (reader != null) reader.Join(3000);
        try { if (input != null) input.Dispose(); } catch { }
        if (inWrite != IntPtr.Zero) CloseHandle(inWrite);
        if (outRead != IntPtr.Zero) CloseHandle(outRead);
        if (hThread != IntPtr.Zero) CloseHandle(hThread);
        if (hProcess != IntPtr.Zero) CloseHandle(hProcess);
        if (attrList != IntPtr.Zero) { DeleteProcThreadAttributeList(attrList); Marshal.FreeHGlobal(attrList); }
    }
}
'@
}

# 在偽主控台裡執行一段 PowerShell，依序送出按鍵步驟，最後回傳畫面與結束碼。
#
# Script  要在子 pwsh 裡跑的程式碼（用 -EncodedCommand 傳，不必煩惱引號）。它看不到
#         呼叫端的變數，只能讀環境變數（GWT_ROOT、GWT_FIXTURE 都有繼承下來）。
# Steps   依序執行的步驟，每個是 hashtable：
#           @{ Wait = '文字' }   等到輸出裡出現這段文字（最多 20 秒）
#           @{ Wait = '文字'; After = '標記' }  只比對最後一個「標記」之後的輸出
#           @{ Send = "..." }    送出按鍵（VT 位元組）
#           @{ Sleep = 200 }     等一下（毫秒）；只在要驗證「按了之後沒反應」時才用
# 回傳   Screen（重播後的畫面）、Output（原始 VT）、ExitCode、TimedOut、WaitFailed
function Invoke-InConsole {
  param(
    [Parameter(Mandatory)][scriptblock]$Script,
    [object[]]$Steps = @(),
    [int]$Rows = 30,
    [int]$Cols = 120,
    [int]$TimeoutSec = 60,
    [string]$WorkingDirectory = (Get-Location).ProviderPath
  )
  $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script.ToString()))
  $pwshExe = (Get-Process -Id $PID).Path
  $cmd = "`"$pwshExe`" -NoProfile -NoLogo -EncodedCommand $encoded"

  $pty = [GwtConPty]::Start($cmd, $WorkingDirectory, $Cols, $Rows)
  $waitFailed = $null
  $code = -1
  $exited = $false
  try {
    foreach ($step in $Steps) {
      if ($step.ContainsKey('Wait')) {
        # After：只看這個標記「之後」的輸出。同一個子行程連跑好幾次 gwt 時，
        # 前一輪留在輸出裡的選單文字不能拿來滿足下一輪的等待。
        $needle = [string]$step.Wait
        $found = $false
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        while ([DateTime]::UtcNow -lt $deadline) {
          $so = $pty.Output()
          $from = 0
          if ($step.ContainsKey('After')) {
            $from = $so.LastIndexOf([string]$step.After, [System.StringComparison]::Ordinal)
            if ($from -lt 0) { Start-Sleep -Milliseconds 25; continue }
          }
          if ($so.IndexOf($needle, $from, [System.StringComparison]::Ordinal) -ge 0) { $found = $true; break }
          if ($pty.HasExited()) { break }
          Start-Sleep -Milliseconds 25
        }
        if (-not $found) { $waitFailed = $needle; break }
      }
      elseif ($step.ContainsKey('Send')) { $pty.Send([string]$step.Send) }
      elseif ($step.ContainsKey('Sleep')) { Start-Sleep -Milliseconds ([int]$step.Sleep) }
    }
    $exited = $pty.WaitForExit($TimeoutSec * 1000, [ref]$code)
    # 子行程結束後 ConPTY 還要把最後的畫面刷出來
    Start-Sleep -Milliseconds 500
    $out = $pty.Output()
  }
  finally {
    $pty.Dispose()
  }
  return [pscustomobject]@{
    Output     = $out
    Screen     = (Get-ScreenReplay -Text $out -Rows $Rows -Cols $Cols)
    ExitCode   = $code
    TimedOut   = (-not $exited)
    WaitFailed = $waitFailed
  }
}

# 同一個子行程連跑多次 gwt 的標準流程（省掉每次啟動 pwsh 的 2 秒）：
# 場景程式每一輪先印 RUN-n、跑 gwt、再印 RESULT-n；這裡產生對應的步驟——
# 等選單畫出來（只看 RUN-n 之後的輸出）、依序送出按鍵、等 RESULT-n 出現。
# Keys 的元素是字串（直接送出）或 @{ Sleep = 毫秒 }。
function New-RunSteps {
  param([int]$N, [object[]]$Keys, [string]$Header = '請選擇')
  $steps = @(@{ Wait = $Header; After = "RUN-$N" })
  foreach ($k in $Keys) {
    if ($k -is [hashtable]) { $steps += $k } else { $steps += @{ Send = [string]$k } }
  }
  $steps += @{ Wait = "RESULT-$N"; After = "RUN-$N" }
  return $steps
}

# 從重播後的畫面取出某一輪的結果（場景程式印的 RESULT-n rc=.. ok=.. pwd=..）
function Get-RunResult {
  param([string]$Screen, [int]$N)
  $m = [regex]::Match($Screen, "(?m)^RESULT-$N rc=(-?\d+) ok=(\w+) pwd=(.*?)\s*$")
  if (-not $m.Success) { return $null }
  return [pscustomobject]@{ Rc = [int]$m.Groups[1].Value; Ok = ($m.Groups[2].Value -eq 'True'); Pwd = $m.Groups[3].Value }
}

# VT 按鍵
$script:Keys = @{
  Up    = "$([char]27)[A"
  Down  = "$([char]27)[B"
  Enter = "`r"
  Esc   = "$([char]27)"
  Bksp  = [string][char]127
  CtrlC = [string][char]3
  CtrlU = [string][char]21
  CtrlW = [string][char]23
}
