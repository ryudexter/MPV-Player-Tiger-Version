// mpv-open.exe - the Windows half of MPV Player: Tiger Version.
//
// install.ps1 compiles this with the C# compiler that comes with Windows
// (.NET Framework 4's csc.exe, so C# 5: no $"", no ?.), into the mpv config
// folder. It is what Explorer opens videos with, and it does the few things
// the Lua scripts cannot do from inside mpv on Windows:
//
//   mpv-open.exe [files or folders]   play them in the ONE running mpv
//   mpv-open.exe --reveal <path>      File Explorer, with the file selected (i)
//   mpv-open.exe --trash <path>       the Recycle Bin (Ctrl+Delete)
//   mpv-open.exe --power              prints ac / battery / unknown (y's ladder)
//
// The single-instance logic is the Mac launcher's (the Python `mpv-open` in
// the config folder), translated; read that file for the why of each step.
// What is different here:
//   * mpv's IPC is a named pipe, \\.\pipe\mpv-single, not a Unix socket.
//   * Explorer starts one copy of this per selected file rather than handing
//     one copy all of them, as Finder does. They queue on a mutex, and only
//     the first open of a burst switches what is playing - the rest just add
//     their file - or the player would hop through every file selected.
//   * Bringing mpv forward is SetForegroundWindow, which Windows allows here
//     because Explorer started this process in answer to a click.
//
// It is built as a windowed app (/target:winexe), so no console flashes up;
// --power still prints, because mpv hands it a pipe for stdout.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

[assembly: AssemblyTitle("mpv (Tiger Version)")]
[assembly: AssemblyProduct("MPV Player: Tiger Version")]
[assembly: AssemblyDescription("Opens videos in one long-lived mpv")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class MpvOpen
{
    const string PipeName = "mpv-single";
    const string Pipe = @"\\.\pipe\" + PipeName;
    // install.ps1 writes the mpv.exe it found here before compiling.
    const string InstalledMpv = @"@@MPV_EXE@@";
    // Two opens closer together than this are one selection in Explorer.
    const int BurstMs = 1000;

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            if (args.Length >= 1 && args[0] == "--power") return Power();
            if (args.Length == 2 && args[0] == "--trash") return Trash(args[1]);
            if (args.Length == 2 && args[0] == "--reveal") return Reveal(args[1]);
            return Open(args);
        }
        catch (Exception e)
        {
            try { Console.Error.WriteLine(e.Message); } catch { }
            return 1;
        }
    }

    // ---- open: the single-instance launcher --------------------------------

    static int Open(string[] files)
    {
        using (var lockm = new Mutex(false, @"Local\mpv-tiger-open"))
        {
            try { lockm.WaitOne(30000); }
            catch (AbandonedMutexException) { }   // a copy that crashed: ours now
            try
            {
                Ipc ipc = Ipc.TryConnect(500);
                if (ipc == null)
                {
                    Launch(files);
                    ipc = Ipc.TryConnect(10000);
                    if (ipc != null) using (ipc) Stamp(ipc);
                    return ipc != null ? 0 : 1;
                }
                using (ipc)
                {
                    if (files.Length > 0) Push(ipc, files);
                    ipc.Cmd("set_property", "window-minimized", false);
                    object pid = ipc.Cmd("get_property", "pid");
                    Stamp(ipc);
                    if (pid != null) BringForward(Convert.ToInt32(pid));
                }
                return 0;
            }
            finally
            {
                try { lockm.ReleaseMutex(); } catch { }
            }
        }
    }

    // When the last open happened, in the player itself, so the next copy of
    // this (a separate process) can tell it is part of the same selection.
    static void Stamp(Ipc ipc)
    {
        ipc.Cmd("set_property", "user-data/tiger/last-open", (double)Environment.TickCount);
    }

    static bool InBurst(Ipc ipc)
    {
        object last = ipc.Cmd("get_property", "user-data/tiger/last-open");
        if (last == null) return false;
        long ago = (long)Environment.TickCount - (long)Convert.ToDouble(last);
        return ago >= 0 && ago < BurstMs;
    }

    static string Norm(string p)
    {
        try { return Path.GetFullPath(p).TrimEnd('\\'); } catch { return p; }
    }

    static void Push(Ipc ipc, string[] files)
    {
        bool burst = InBurst(ipc);
        var known = new List<string>();
        int? cur = null;
        object[] pl = ipc.Cmd("get_property", "playlist") as object[] ?? new object[0];
        for (int i = 0; i < pl.Length; i++)
        {
            var e = pl[i] as Dictionary<string, object>;
            if (e == null) { known.Add(""); continue; }
            object fn;
            known.Add(e.TryGetValue("filename", out fn) ? Norm(Convert.ToString(fn)) : "");
            object c;
            if (e.TryGetValue("current", out c) && c is bool && (bool)c) cur = i;
        }
        var cmp = StringComparer.OrdinalIgnoreCase;     // NTFS ignores case
        Func<string, int> indexOf = delegate(string p)
        {
            for (int i = 0; i < known.Count; i++) if (cmp.Equals(known[i], p)) return i;
            return -1;
        };

        // the first file decides what is switched to
        string first = Norm(files[0]);
        int target = indexOf(first);
        if (target < 0)
        {
            target = known.Count;
            ipc.Cmd("loadfile", files[0], "append");
            known.Add(first);
        }
        for (int i = 1; i < files.Length; i++)
        {
            if (indexOf(Norm(files[i])) < 0)
            {
                ipc.Cmd("loadfile", files[i], "append");
                known.Add(Norm(files[i]));
            }
        }
        if (burst) return;                    // another file of this selection plays

        // Re-opening the playing file must not reload it from 0.
        if (cur == null || target != cur.Value)
        {
            if (cur != null) ipc.Cmd("write-watch-later-config");
            ipc.Cmd("playlist-play-index", target);
        }
        // Opening a file means "play this", at 1x - see the Mac launcher.
        ipc.Cmd("set_property", "pause", false);
        ipc.Cmd("set_property", "speed", 1.0);
    }

    static string FindMpv()
    {
        if (InstalledMpv.Length > 0 && !InstalledMpv.StartsWith("@@") && File.Exists(InstalledMpv))
            return InstalledMpv;
        string local = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                    @"Programs\mpv\mpv.exe");
        if (File.Exists(local)) return local;
        foreach (string dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
        {
            try
            {
                string p = Path.Combine(dir.Trim('"'), "mpv.exe");
                if (File.Exists(p)) return p;
            }
            catch (ArgumentException) { }
        }
        return "mpv.exe";
    }

    static void Launch(string[] files)
    {
        var args = new List<string> { "--force-window=immediate", "--input-ipc-server=" + Pipe };
        // For testing only (the CI sets --vo=null --ao=null), as in the Mac launcher.
        string extra = Environment.GetEnvironmentVariable("MPV_TIGER_FLAGS");
        if (!string.IsNullOrEmpty(extra))
            args.AddRange(extra.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries));
        if (files.Length == 0) args.Add("--idle=once");
        args.Add("--");                       // everything after this is a file
        args.AddRange(files);

        var sb = new StringBuilder();
        foreach (string a in args) { if (sb.Length > 0) sb.Append(' '); sb.Append(Quote(a)); }
        var psi = new ProcessStartInfo(FindMpv(), sb.ToString());
        psi.UseShellExecute = false;
        psi.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        Process.Start(psi);
    }

    // One argument, quoted the way CommandLineToArgvW reads it back.
    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return a;
        var sb = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in a)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') sb.Append('\\', slashes * 2 + 1);
            else sb.Append('\\', slashes);
            slashes = 0;
            sb.Append(c);
        }
        sb.Append('\\', slashes * 2);
        return sb.Append('"').ToString();
    }

    // ---- bringing the player forward ---------------------------------------

    delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetClassName(IntPtr hwnd, StringBuilder name, int max);

    static void BringForward(int pid)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            uint p;
            GetWindowThreadProcessId(h, out p);
            if (p != (uint)pid || !IsWindowVisible(h)) return true;
            var cls = new StringBuilder(64);
            GetClassName(h, cls, cls.Capacity);
            if (cls.ToString() != "mpv") return true;
            found = h;
            return false;
        }, IntPtr.Zero);
        AllowSetForegroundWindow(pid);
        if (found == IntPtr.Zero) return;
        if (IsIconic(found)) ShowWindow(found, 9 /* SW_RESTORE */);
        SetForegroundWindow(found);
    }

    // ---- --power -------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    struct SYSTEM_POWER_STATUS
    {
        public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
        public int BatteryLifeTime, BatteryFullLifeTime;
    }
    [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS s);

    static int Power()
    {
        SYSTEM_POWER_STATUS s;
        string answer = "unknown";
        if (GetSystemPowerStatus(out s))
            answer = s.ACLineStatus == 0 ? "battery" : s.ACLineStatus == 1 ? "ac" : "unknown";
        Console.Out.WriteLine(answer);
        Console.Out.Flush();
        return 0;
    }

    // ---- --trash ---------------------------------------------------------------
    //
    // SHFileOperation with FOF_ALLOWUNDO is the Recycle Bin. FOF_WANTNUKEWARNING
    // is the important flag: without it, a file that cannot be recycled (a
    // network share, a drive with no bin, a file bigger than the bin) is
    // deleted outright and silently. With it Windows asks first, and a "No"
    // comes back here as aborted - exit 2, which trash-file.lua reports as kept.

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom, pTo;
        public ushort fFlags;
        public int fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }
    // 32-bit Windows packs the same struct to 1 byte
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 1)]
    struct SHFILEOPSTRUCT32
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom, pTo;
        public ushort fFlags;
        public int fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHFileOperation")]
    static extern int SHFileOperation32(ref SHFILEOPSTRUCT32 op);

    const uint FO_DELETE = 3;
    const ushort FOF_SILENT = 0x4, FOF_NOCONFIRMATION = 0x10, FOF_ALLOWUNDO = 0x40,
                 FOF_WANTNUKEWARNING = 0x4000;

    static int Trash(string path)
    {
        path = Path.GetFullPath(path);
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            Console.Error.WriteLine("no such file: " + path);
            return 1;
        }
        ushort flags = (ushort)(FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_WANTNUKEWARNING | FOF_SILENT);
        int rc, aborted;
        if (IntPtr.Size == 8)
        {
            var op = new SHFILEOPSTRUCT { wFunc = FO_DELETE, pFrom = path + "\0\0", fFlags = flags };
            rc = SHFileOperation(ref op);
            aborted = op.fAnyOperationsAborted;
        }
        else
        {
            var op = new SHFILEOPSTRUCT32 { wFunc = FO_DELETE, pFrom = path + "\0\0", fFlags = flags };
            rc = SHFileOperation32(ref op);
            aborted = op.fAnyOperationsAborted;
        }
        if (aborted != 0) { Console.Error.WriteLine("cancelled"); return 2; }
        if (rc != 0) { Console.Error.WriteLine("SHFileOperation failed: 0x" + rc.ToString("x")); return 1; }
        if (File.Exists(path)) { Console.Error.WriteLine("still there: " + path); return 1; }
        return 0;
    }

    // ---- --reveal ----------------------------------------------------------------
    //
    // SHOpenFolderAndSelectItems is what Explorer's own "Open file location"
    // uses: it reuses a window already showing that folder, and selects the file.

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern IntPtr ILCreateFromPathW(string path);
    [DllImport("shell32.dll")] static extern void ILFree(IntPtr pidl);
    [DllImport("shell32.dll")]
    static extern int SHOpenFolderAndSelectItems(IntPtr pidlFolder, uint cidl, IntPtr apidl, uint flags);

    static int Reveal(string path)
    {
        IntPtr pidl = ILCreateFromPathW(Path.GetFullPath(path));
        if (pidl == IntPtr.Zero) { Console.Error.WriteLine("no such file: " + path); return 1; }
        try
        {
            AllowSetForegroundWindow(-1);     // ASFW_ANY: let Explorer come to the front
            int hr = SHOpenFolderAndSelectItems(pidl, 0, IntPtr.Zero, 0);
            if (hr != 0) { Console.Error.WriteLine("SHOpenFolderAndSelectItems: 0x" + hr.ToString("x")); return 1; }
            return 0;
        }
        finally { ILFree(pidl); }
    }
}

// mpv's JSON IPC over the named pipe: one request, read until its reply.
sealed class Ipc : IDisposable
{
    readonly NamedPipeClientStream pipe;
    readonly StreamReader reader;
    readonly StreamWriter writer;
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    int rid;

    Ipc(NamedPipeClientStream p)
    {
        pipe = p;
        var utf8 = new UTF8Encoding(false);
        reader = new StreamReader(p, utf8);
        writer = new StreamWriter(p, utf8);
        writer.AutoFlush = true;
        writer.NewLine = "\n";
    }

    public static Ipc TryConnect(int timeoutMs)
    {
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (true)
        {
            var p = new NamedPipeClientStream(".", "mpv-single", PipeDirection.InOut);
            try
            {
                p.Connect(Math.Max(1, Math.Min(500, (int)(deadline - DateTime.UtcNow).TotalMilliseconds)));
                return new Ipc(p);
            }
            catch (Exception e)
            {
                p.Dispose();
                if (!(e is TimeoutException || e is IOException)) throw;
                if (DateTime.UtcNow >= deadline) return null;
                Thread.Sleep(100);
            }
        }
    }

    public object Cmd(params object[] command)
    {
        int id = ++rid;
        var req = new Dictionary<string, object> { { "command", command }, { "request_id", id } };
        writer.WriteLine(json.Serialize(req));
        while (true)
        {
            string line = reader.ReadLine();
            if (line == null) return null;
            Dictionary<string, object> m;
            try { m = json.DeserializeObject(line) as Dictionary<string, object>; }
            catch (ArgumentException) { continue; }
            object got;
            if (m == null || !m.TryGetValue("request_id", out got) || Convert.ToInt32(got) != id)
                continue;                     // an event, or someone else's reply
            object data;
            return m.TryGetValue("data", out data) ? data : null;
        }
    }

    public void Dispose()
    {
        try { pipe.Dispose(); } catch { }
    }
}
