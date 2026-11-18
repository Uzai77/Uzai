# Uzai-Helfer für Windows.
# Uzai startet dieses Skript einmal im Hintergrund und schickt ihm Befehle als JSON-Zeilen
# (Fenster in den Vordergrund holen, Emulator pausieren, Tasten senden, Medientasten,
# Discord-Status, mpv steuern, Autostart, Ausschalten). Jede Antwort ist wieder eine JSON-Zeile.
# Zusätzlich beobachtet ein Hintergrund-Thread die Xbox-Controller: Die Guide-Taste (oder
# View + Start) meldet er als {"id":-1,"event":"guide"}, auch wenn gerade ein Spiel im
# Vordergrund ist.
#
# Mit -Once '<json>' führt es einen einzelnen, länger dauernden Befehl aus
# (zum Beispiel: auf das Spielfenster warten und ShaderGlass darüberlegen) und beendet sich.
#
# Mit -Watch '<json>' ist es der kleine Wächter nach dem Schließen (Einstellung „Nach dem
# Schließen im Hintergrund bereit“): siehe unten, gleich nach den Kodierungen.
#
# Mit -Update '<json>' spielt es ein geprüftes Update ein, sobald Uzai beendet ist (gleich nach den Kodierungen).
#
# Mit -ZimmerNetz gastgeber|gast startet es den abgeschotteten Netzwerk-Teil fürs Zimmer im Testbetrieb
# (AppContainer; „gastgeber-echt“/„gast-echt“: echte Relays und WebRTC, nur über Uzais Testschalter) und gibt ihm
# seine Standardeingabe und -ausgabe als schmale Leitung zu Uzai;
# es selbst schreibt darauf nichts (siehe „Zimmer-Netz“ weiter unten).
#
# Stürzt Uzai ab, endet seine Leitung zu diesem Helfer. Hat Uzai vorher „crash-watch“ geschickt,
# startet der Helfer es dann neu (Crash-Restart, ganz unten).

param([string]$Once = '', [string]$Watch = '', [string]$ZimmerNetz = '', [string]$Update = '')

$ErrorActionPreference = 'Stop'
try { [Console]::InputEncoding = New-Object Text.UTF8Encoding $false } catch {}
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}

# --- Update einspielen (-Update) ----------------------------------------------------------------
# Uzai (src/core/updater.gd) hat ein Update geladen, die Signatur mit seinem eingebauten Schlüssel geprüft und nur
# Uzai.exe, Uzai.pck und discord_partner_sdk.dll in einen eigenen Ordner entpackt. Beim Beenden startet es dieses Skript
# mit -Update '<base64 JSON>': pid, dir (Uzais Ordner), ordner (die neuen Dateien), dateien, sha256 (je Datei),
# fassung, neu_starten, ergebnis (Datei für das Ergebnis). Ablauf: warten, bis Uzai weg ist (höchstens 2 min); läuft
# ein anderes Uzai aus demselben Ordner (Neustart), nichts tun (verschoben) – dann beim nächsten Schließen. Sonst:
# jede neue Datei gegen ihre Prüfsumme prüfen, als <ziel>.neu neben die alte kopieren (gleiches Laufwerk) und die Kopie
# noch einmal prüfen; erst dann je Datei in einem Schritt tauschen ([IO.File]::Replace, die alte bleibt als .alt).
# Wird das Skript mittendrin beendet (PC aus, Abmelden), ist jede Datei ganz alt oder ganz neu, nie halb oder weg, und
# das noch bereite Update kommt beim nächsten Schließen erneut. Geht etwas schief, kommen alle alten zurück. Nur
# Dateien aus der festen Liste, nie Ordner.
if ($Update -ne '') {
    $u = $null
    $ergebnis = @{ ok = $false; fassung = ''; grund = ''; verschoben = $false }
    $kopien = New-Object Collections.Generic.List[string]
    try {
        $u = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Update)) | ConvertFrom-Json
        $ergebnis.fassung = [string]$u.fassung
        $dir = [IO.Path]::GetFullPath([string]$u.dir)
        $quelle = [IO.Path]::GetFullPath([string]$u.ordner)
        $erlaubt = @('Uzai.exe', 'Uzai.pck', 'discord_partner_sdk.dll')
        $dateien = @($u.dateien | ForEach-Object { [string]$_ })
        foreach ($d in $dateien) { if ($erlaubt -cnotcontains $d) { throw "nicht erlaubt: $d" } }
        if ($dateien -cnotcontains 'Uzai.exe' -or $dateien -cnotcontains 'Uzai.pck') { throw 'unvollständig' }
        $soll = @{}
        foreach ($d in $dateien) {
            $p = if ($u.sha256) { $u.sha256.PSObject.Properties[$d] } else { $null }
            $s = if ($p) { ([string]$p.Value).ToLowerInvariant() } else { '' }
            if ($s -notmatch '^[0-9a-f]{64}$') { throw "Prüfsumme fehlt: $d" }
            $soll[$d] = $s
        }
        $altPid = [int]$u.pid
        $bis = (Get-Date).AddSeconds(120)
        while ($altPid -gt 0 -and (Get-Process -Id $altPid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $bis) { Start-Sleep -Milliseconds 250 }
        if ($altPid -gt 0 -and (Get-Process -Id $altPid -ErrorAction SilentlyContinue)) { throw 'Uzai läuft noch' }
        $exe = Join-Path $dir 'Uzai.exe'
        $wieder = @(Get-Process -Name 'Uzai' -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -ieq $exe) } catch { $false } })
        if ($wieder.Count -gt 0) { $ergebnis.verschoben = $true; throw 'Uzai läuft wieder' }
        # Erst alles prüfen und neben die alten legen – solange ist an Uzai noch nichts verändert.
        foreach ($d in $dateien) {
            $neu = Join-Path $quelle $d
            $ziel = Join-Path $dir $d
            if (-not (Test-Path -LiteralPath $neu -PathType Leaf)) { throw "fehlt: $d" }
            if ((Get-FileHash -LiteralPath $neu -Algorithm SHA256).Hash.ToLowerInvariant() -ne $soll[$d]) { throw "Prüfsumme passt nicht: $d" }
            $kopien.Add($ziel + '.neu')
            Copy-Item -LiteralPath $neu -Destination ($ziel + '.neu') -Force
            if ((Get-FileHash -LiteralPath ($ziel + '.neu') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $soll[$d]) { throw "Kopie unvollständig: $d" }
        }
        $getauscht = New-Object Collections.Generic.List[string]
        try {
            foreach ($d in $dateien) {
                $ziel = Join-Path $dir $d
                if (Test-Path -LiteralPath ($ziel + '.alt')) { Remove-Item -LiteralPath ($ziel + '.alt') -Force }
                $getauscht.Add($d)
                if (Test-Path -LiteralPath $ziel -PathType Leaf) { [IO.File]::Replace($ziel + '.neu', $ziel, $ziel + '.alt', $true) }
                else { [IO.File]::Move($ziel + '.neu', $ziel) }
            }
        } catch {
            foreach ($d in $getauscht) {
                $ziel = Join-Path $dir $d
                try {
                    if (Test-Path -LiteralPath ($ziel + '.alt')) {
                        if (Test-Path -LiteralPath $ziel) { Remove-Item -LiteralPath $ziel -Force }
                        Move-Item -LiteralPath ($ziel + '.alt') -Destination $ziel -Force
                    }
                } catch {}
            }
            throw
        }
        foreach ($d in $dateien) { Remove-Item -LiteralPath ((Join-Path $dir $d) + '.alt') -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $quelle -Recurse -Force -ErrorAction SilentlyContinue
        $ergebnis.ok = $true
    } catch {
        $ergebnis.grund = [string]$_.Exception.Message
    } finally {
        foreach ($k in $kopien) { Remove-Item -LiteralPath $k -Force -ErrorAction SilentlyContinue }
    }
    try { if ($u -and $u.ergebnis) { [IO.File]::WriteAllText([string]$u.ergebnis, ($ergebnis | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false)) } } catch {}
    if ($ergebnis.ok -and $u.neu_starten) { try { Start-Process -FilePath (Join-Path $dir 'Uzai.exe') -WorkingDirectory $dir } catch {} }
    exit 0
}

# --- Wächter nach dem Schließen (-Watch) ------------------------------------------------------
# Uzai startet ihn beim Schließen und beendet sich dann ganz. Er übersetzt nur diesen kleinen
# C#-Teil (nicht den großen unten), wartet, bis Uzai wirklich weg ist, und fragt dann die
# Controller ab: verbundene alle 50 ms, freie Anschlüsse alle 1–2 s (XInput auf leeren
# Anschlüssen ist teuer). Guide-Taste (oder View + Start) → Uzai.exe neu starten (mit Startanimation
# wie sonst), Uzai nach vorn holen, Wächter beendet sich. Liegt vorn ein Vollbild-Programm (ein
# Spiel außerhalb von Uzai, Steam Big Picture), gehört ein kurzer Druck diesem: Dann nur nach
# 0,8 s Halten. Er beendet sich auch, sobald Uzai auf anderem Weg startet (Uzai schreibt beim Start
# uzai.pid neu), und mit der Windows-Sitzung (Abmelden, Neustart, Herunterfahren) wie jedes
# Programm. Kein Autostart, keine Registry, keine Systemeinstellung. Nur ein Wächter gleichzeitig
# (benannter Mutex in der eigenen Sitzung). Niedrige Priorität, Arbeitsspeicher nach dem Start
# freigegeben (SetProcessWorkingSetSize), vor dem Start von Uzai wieder normale Priorität (sonst
# erbte Uzai „niedriger als normal“).
if ($Watch -ne '') {
    $w = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Watch)) | ConvertFrom-Json
    $mutex = New-Object Threading.Mutex($false, 'Local\UzaiGuideWake')
    $own = $false
    # Ein älterer Wächter beendet sich gleich (Uzai lief ja wieder): kurz auf ihn warten.
    # Ausnahme hier heißt: der alte Wächter wurde hart beendet (AbandonedMutex) – dann gehört er uns.
    try { $own = $mutex.WaitOne(5000) } catch { $own = $true }
    if (-not $own) { $mutex.Dispose(); exit 0 }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class UzWake {
    // Reserved: XInputGetStateEx schreibt (anders als XInputGetState) vier Bytes mehr
    // (XINPUT_STATE_EX) – ohne das Feld landeten sie hinter der Struktur.
    [StructLayout(LayoutKind.Sequential)]
    public struct XState { public uint Packet; public ushort Buttons; public byte LT; public byte RT; public short LX; public short LY; public short RX; public short RY; public uint Reserved; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    // Ordinal 100 ist XInputGetStateEx, die einzige Variante, die auch die Guide-Taste liefert.
    [DllImport("xinput1_4.dll", EntryPoint = "#100")] static extern int GetStateEx(int index, out XState s);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool SetProcessWorkingSetSize(IntPtr p, IntPtr min, IntPtr max);
    [DllImport("kernel32.dll")] static extern bool SetPriorityClass(IntPtr p, uint cls);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    public const int HOLD_MS = 800;

    static DateTime Mtime(string path) {
        try { return File.Exists(path) ? File.GetLastWriteTimeUtc(path) : DateTime.MinValue; } catch { return DateTime.MinValue; }
    }

    static void Trim() {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        SetProcessWorkingSetSize(GetCurrentProcess(), new IntPtr(-1), new IntPtr(-1));
    }

    // Vorn ein Fenster, das seinen ganzen Bildschirm bedeckt (Spiel, Big Picture, Film im Vollbild)?
    // Der Desktop selbst zählt nicht.
    public static bool FullscreenInFront() {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero || !IsWindowVisible(h) || IsIconic(h)) return false;
        var sb = new StringBuilder(64);
        GetClassName(h, sb, 64);
        string c = sb.ToString();
        if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return false;
        RECT r;
        if (!GetWindowRect(h, out r)) return false;
        var mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref mi)) return false;
        RECT m = mi.rcMonitor;
        if (m.Right - m.Left <= 0) return false;
        return r.Left <= m.Left + 2 && r.Top <= m.Top + 2 && r.Right >= m.Right - 2 && r.Bottom >= m.Bottom - 2;
    }

    // Wartet, bis Uzai (parent) zu ist und die Guide-Taste kommt. "wake", "stop" (Uzai lief
    // wieder an oder schloss nicht) oder "error" (kein XInput).
    public static string Run(int parent, bool combo, string pidFile) {
        DateTime baseline = Mtime(pidFile);
        SetPriorityClass(GetCurrentProcess(), 0x4000);   // BELOW_NORMAL_PRIORITY_CLASS
        if (parent > 0) {
            try {
                var p = Process.GetProcessById(parent);
                if (!p.WaitForExit(20000)) return "stop";
            } catch (ArgumentException) {
            } catch (InvalidOperationException) {
            }
        }
        Trim();
        bool[] conn = new bool[4];
        bool[] was = new bool[4];
        bool[] hold = new bool[4];
        long[] downAt = new long[4];
        bool first = true;
        var sw = Stopwatch.StartNew();
        long nextScan = 0, nextFile = 0, trimAt = 30000;
        while (true) {
            long now = sw.ElapsedMilliseconds;
            if (now >= nextFile) {
                nextFile = now + 1000;
                if (Mtime(pidFile) > baseline) return "stop";
            }
            if (trimAt > 0 && now >= trimAt) { trimAt = 0; Trim(); }
            bool scan = now >= nextScan;
            if (scan) nextScan = now + 2000;
            bool any = false;
            for (int i = 0; i < 4; i++) {
                if (!conn[i] && !scan) continue;
                XState s;
                int r;
                try { r = GetStateEx(i, out s); } catch { return "error"; }
                if (r != 0) { conn[i] = false; was[i] = false; hold[i] = false; continue; }
                conn[i] = true;
                any = true;
                bool down = (s.Buttons & 0x0400) != 0 || (combo && (s.Buttons & 0x0030) == 0x0030);
                // Schon gedrückt, als der Wächter anfing (z. B. noch vom Schließen): zählt nicht.
                if (first) { was[i] = down; continue; }
                if (down && !was[i]) {
                    downAt[i] = now;
                    if (!FullscreenInFront()) { SetPriorityClass(GetCurrentProcess(), 0x20); return "wake"; }
                    hold[i] = true;
                }
                if (down && hold[i] && now - downAt[i] >= HOLD_MS) { SetPriorityClass(GetCurrentProcess(), 0x20); return "wake"; }
                if (!down) hold[i] = false;
                was[i] = down;
            }
            first = false;
            if (!any) nextScan = 0;
            Thread.Sleep(any ? 50 : 1000);
        }
    }

    // Ein Argument für die Windows-Befehlszeile (wie CommandLineToArgvW es zurückliest).
    public static string Quote(string a) {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return a;
        var sb = new StringBuilder("\"");
        int bs = 0;
        foreach (char c in a) {
            if (c == '\\') { bs++; continue; }
            if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); bs = 0; continue; }
            sb.Append('\\', bs);
            bs = 0;
            sb.Append(c);
        }
        sb.Append('\\', bs * 2);
        sb.Append('"');
        return sb.ToString();
    }

    public static int Launch(string exe, string dir, string[] args) {
        var parts = new System.Collections.Generic.List<string>();
        if (args != null) foreach (string a in args) if (!String.IsNullOrEmpty(a)) parts.Add(Quote(a));
        var si = new ProcessStartInfo(exe, String.Join(" ", parts.ToArray()));
        si.UseShellExecute = false;
        if (!String.IsNullOrEmpty(dir)) si.WorkingDirectory = dir;
        var p = Process.Start(si);
        return p == null ? 0 : p.Id;
    }

    static void Focus(IntPtr h) {
        if (IsIconic(h)) ShowWindow(h, 9);
        int dummy;
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), out dummy);
        uint me = GetCurrentThreadId();
        if (fg != 0 && fg != me) AttachThreadInput(me, fg, true);
        SetForegroundWindow(h);
        BringWindowToTop(h);
        if (fg != 0 && fg != me) AttachThreadInput(me, fg, false);
        if (GetForegroundWindow() != h) {
            // Notlösung wie im Helfer: kurzes Alt erlaubt Windows den Fokuswechsel.
            keybd_event(0x12, 0, 0, UIntPtr.Zero);
            SetForegroundWindow(h);
            keybd_event(0x12, 0, 2, UIntPtr.Zero);
        }
    }

    // Das neu gestartete Uzai nach vorn holen (nur Uzai, höchstens viermal, bis es vorn bleibt).
    public static bool FocusWhenReady(int pid, int ms) {
        Process p;
        try { p = Process.GetProcessById(pid); } catch { return false; }
        var sw = Stopwatch.StartNew();
        int tries = 0, held = 0;
        while (sw.ElapsedMilliseconds < ms && tries < 4) {
            Thread.Sleep(200);
            try { if (p.HasExited) return false; p.Refresh(); } catch { return false; }
            IntPtr h = p.MainWindowHandle;
            if (h == IntPtr.Zero || !IsWindowVisible(h)) continue;
            if (GetForegroundWindow() == h) { if (++held >= 5) return true; continue; }
            held = 0;
            tries++;
            Focus(h);
        }
        return false;
    }
}
'@
        $res = [UzWake]::Run([int]$w.parent, [bool]$w.combo, [string]$w.pid_file)
        if ($res -eq 'wake') {
            $wpid = [UzWake]::Launch([string]$w.exe, [string]$w.dir, [string[]]@($w.args | Where-Object { $null -ne $_ }))
            try { $mutex.ReleaseMutex() } catch {}
            $own = $false
            if ($wpid -gt 0) { [void][UzWake]::FocusWhenReady($wpid, 15000) }
        }
    } catch {
    } finally {
        if ($own) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
    exit 0
}

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UzWin {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr h);
    [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr h);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
    [DllImport("powrprof.dll")] public static extern bool SetSuspendState(bool hibernate, bool force, bool wake);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);

    // Minimieren und Wiederherstellen ohne Windows-Animation (DWMWA_TRANSITIONS_FORCEDISABLED):
    // sonst „zoomt“ beim Guide über dem Spiel ein altes Bild von Uzai aus der Taskleiste.
    public static bool NoTransitions(IntPtr h) {
        int on = 1;
        try { return DwmSetWindowAttribute(h, 3, ref on, 4) == 0; } catch { return false; }
    }

    public static List<IntPtr> WindowsOf(int pid) {
        var list = new List<IntPtr>();
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            int p;
            GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h) && GetWindowTextLength(h) > 0) list.Add(h);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // Das eigentliche Spielfenster: Emulatoren wie PCSX2 haben ein Hauptfenster und ein eigenes
    // Bildfenster. Liegt eines der Fenster schon vorn, ist es das; sonst das größte.
    public static IntPtr Best(int[] pids) {
        IntPtr fg = GetForegroundWindow();
        int fpid;
        GetWindowThreadProcessId(fg, out fpid);
        IntPtr best = IntPtr.Zero;
        long area = -1;
        foreach (int pid in pids) {
            if (pid == fpid && fg != IntPtr.Zero && IsWindowVisible(fg)) return fg;
            foreach (IntPtr h in WindowsOf(pid)) {
                RECT r;
                if (!GetWindowRect(h, out r)) continue;
                long a = (long)(r.Right - r.Left) * (long)(r.Bottom - r.Top);
                if (a > area) { area = a; best = h; }
            }
        }
        return best;
    }

    public static string Title(IntPtr h) {
        var sb = new StringBuilder(512);
        GetWindowText(h, sb, 512);
        return sb.ToString();
    }

    // Große, sichtbare Fenster anderer Programme, je Eintrag „hwnd|pid|breite|höhe|titel“.
    // Beim Spielstart: Uzai geht erst aus dem Weg, wenn ein neues Fenster (Spiel oder dessen
    // Starter) wirklich da ist. Werkzeugfenster (Overlays, Pop-ups) zählen nicht.
    public static List<string> BigWindows(int minW, int minH, int[] skipPids) {
        var list = new List<string>();
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            int p;
            GetWindowThreadProcessId(h, out p);
            foreach (int sp in skipPids) { if (sp == p) return true; }
            long ex = GetWindowLongPtr(h, -20).ToInt64();
            if ((ex & 0x00000080L) != 0) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int w = r.Right - r.Left;
            int hh = r.Bottom - r.Top;
            if (w < minW || hh < minH) return true;
            list.Add(h.ToInt64() + "|" + p + "|" + w + "|" + hh + "|" + Title(h));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // Antwortet das Fenster binnen ms auf eine leere Nachricht (WM_NULL, SMTO_ABORTIFHUNG)?
    public static bool Antwortet(IntPtr h, uint ms) {
        if (h == IntPtr.Zero) return false;
        IntPtr r;
        return SendMessageTimeout(h, 0, IntPtr.Zero, IntPtr.Zero, 0x0002, ms, out r) != IntPtr.Zero;
    }

    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO p);

    // Millisekunden seit der letzten Maus- oder Tastatureingabe am PC (Controller zählen bei Windows nicht mit),
    // -1 unbekannt. Damit unterscheidet Uzai nach dem Start „ein Programm hat sich davorgesetzt“ von „der Nutzer
    // hat selbst gewechselt“ (src/core/startwache.gd).
    public static int IdleMs() {
        try {
            LASTINPUTINFO li = new LASTINPUTINFO();
            li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!GetLastInputInfo(ref li)) return -1;
            uint d = unchecked((uint)Environment.TickCount - li.dwTime);
            return d > 0x7FFFFFFFu ? -1 : (int)d;
        } catch { return -1; }
    }

    // SHQueryUserNotificationState: 3 = exklusives Direct3D-Vollbild vorn, 2 = Vollbild-Programm.
    public static int Quns() {
        int q = 0;
        try { if (SHQueryUserNotificationState(out q) != 0) q = 0; } catch { q = 0; }
        return q;
    }

    // Fenster minimieren, ohne auf seinen Faden zu warten (Guide über exklusivem Vollbild: so gibt
    // das Spiel den Bildschirm frei, wie bei Alt+Tab; Focus holt es danach zurück).
    public static bool MinimizeAsync(IntPtr h) {
        return h != IntPtr.Zero && IsWindow(h) && ShowWindowAsync(h, 6);
    }

    public static bool Focus(IntPtr h) {
        // Asynchron: Ein Spiel, das gerade lädt oder den Bildschirmmodus wechselt, antwortet erst
        // Sekunden später – ShowWindow und BringWindowToTop warteten darauf, und mit ihnen der ganze
        // schnelle Helfer (window-state, Vorhang, Raumton: „nach 2.0 s ohne Antwort“).
        if (IsIconic(h)) ShowWindowAsync(h, 9);
        int dummy;
        IntPtr fgw = GetForegroundWindow();
        uint fg = GetWindowThreadProcessId(fgw, out dummy);
        uint me = GetCurrentThreadId();
        // Hängt das Fenster vorn oder antwortet es nicht sofort, nie an seinen Faden koppeln: Der
        // Wechsel wartete sonst auf ihn, und der Helfer (Vorhang, Beenden) hinge mit. Windows lässt
        // den Wechsel weg von einem hängenden Fenster ohnehin zu.
        bool koppeln = fg != 0 && fg != me && !IsHungAppWindow(fgw) && Antwortet(fgw, 150);
        if (koppeln) AttachThreadInput(me, fg, true);
        SetForegroundWindow(h);
        // HWND_TOP; SWP_NOSIZE | SWP_NOMOVE | SWP_ASYNCWINDOWPOS (statt BringWindowToTop, das wartet)
        SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x0001u | 0x0002u | 0x4000u);
        if (koppeln) AttachThreadInput(me, fg, false);
        if (GetForegroundWindow() != h && UzGuard.Problem(GetForegroundWindow()) != "geschützt") {
            // Notlösung: kurzes Alt erlaubt Windows den Fokuswechsel (nie, solange ein Anmelde- oder
            // Sicherheitsfenster vorn ist – dort bleibt es dann einfach, wie es ist).
            keybd_event(0x12, 0, 0, UIntPtr.Zero);
            SetForegroundWindow(h);
            keybd_event(0x12, 0, 2, UIntPtr.Zero);
        }
        return GetForegroundWindow() == h;
    }

    // Pop-up-Fenster über dem Spiel (Uzai-Mitteilungen). Godot legt es schon mit
    // WS_EX_NOACTIVATE | WS_EX_TOPMOST an und zeigt es mit SW_SHOWNA. Der Helfer stellt das
    // sicher, nimmt es zusätzlich aus Alt+Tab (WS_EX_TOOLWINDOW) und legt es nochmal ganz nach
    // oben (Spiele, die selbst „immer oben“ sind) – ohne Aktivieren, nie SetForegroundWindow.
    // Die Maus geht über Godot durch (WM_NCHITTEST); WS_EX_LAYERED setzt der Helfer nicht
    // (Godot zeichnet Durchsichtiges über DWM, ein Layered-Fenster ohne Deckkraft wäre unsichtbar).
    public static bool NoActivate(IntPtr h) {
        if (h == IntPtr.Zero) return false;
        long ex = GetWindowLongPtr(h, -20).ToInt64();
        long want = (ex | 0x08000000L | 0x00000080L | 0x00000008L) & ~0x00040000L;
        if (want != ex) SetWindowLongPtr(h, -20, new IntPtr(want));
        // HWND_TOPMOST; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOOWNERZORDER
        return SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001u | 0x0002u | 0x0010u | 0x0020u | 0x0200u);
    }

    public static void Key(byte vk, bool down) {
        uint flags = down ? 0u : 2u;
        // Erweiterte Tasten brauchen das Extended-Kennzeichen. Ohne meldet Windows nur die
        // Scan-Nummer einer normalen Taste: Pause/Play käme als „G“ an (in Uzai der Guide),
        // Zurück als „Q“, leiser als „C“.
        if (IsExtended(vk)) flags |= 1u;
        keybd_event(vk, (byte)MapVirtualKey(vk, 0), flags, UIntPtr.Zero);
    }

    public static bool IsExtended(byte vk) {
        return (vk >= 0x21 && vk <= 0x28) || vk == 0x2C || vk == 0x2D || vk == 0x2E
            || vk == 0x5B || vk == 0x5C || vk == 0x5D || vk == 0x6F || vk == 0x90
            || vk == 0xA3 || vk == 0xA5 || (vk >= 0xA6 && vk <= 0xB7);
    }

    // Fenster eines Prozesses verstecken und später wieder zeigen (ShaderGlass, solange der
    // Guide offen ist: sein Fenster liegt sonst ganz oben und verdeckt Uzai).
    static List<IntPtr> hidden = new List<IntPtr>();
    public static int HideAll(int pid) {
        var l = WindowsOf(pid);
        foreach (var h in l) { ShowWindow(h, 0); hidden.Add(h); }
        return l.Count;
    }
    public static int ShowHidden() {
        int n = hidden.Count;
        foreach (var h in hidden) ShowWindow(h, 8);
        hidden.Clear();
        return n;
    }

    // Gestartete Spiele: Solange der Helfer einen Griff auf den Prozess hält, bleibt sein
    // Rückgabewert lesbar, auch wenn er längst beendet ist (Absturz erkennen, „exit-code“). Nur
    // Nachsehen (PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE), kein Steuern.
    static Dictionary<int, IntPtr> started = new Dictionary<int, IntPtr>();
    public static void Watch(int pid) {
        if (pid <= 0 || started.ContainsKey(pid)) return;
        IntPtr h = OpenProcess(0x1000 | 0x00100000, false, pid);
        if (h != IntPtr.Zero) started[pid] = h;
    }

    // -1: unbekannt (nicht hier gestartet), -2: läuft noch, sonst der Rückgabewert.
    public static long ExitCode(int pid) {
        IntPtr h;
        if (!started.TryGetValue(pid, out h)) return -1;
        if (WaitForSingleObject(h, 0) != 0) return -2;
        uint code;
        bool ok = GetExitCodeProcess(h, out code);
        CloseHandle(h);
        started.Remove(pid);
        return ok ? (long)code : -1;
    }

    public static bool Suspend(int pid, bool suspend) {
        IntPtr h = OpenProcess(0x0800, false, pid);
        if (h == IntPtr.Zero) return false;
        int r = suspend ? NtSuspendProcess(h) : NtResumeProcess(h);
        CloseHandle(h);
        return r == 0;
    }

    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);

    public static int PidOf(IntPtr h) {
        int p = 0;
        if (h != IntPtr.Zero) GetWindowThreadProcessId(h, out p);
        return p;
    }

    public static string ClassOf(IntPtr h) {
        var sb = new StringBuilder(256);
        if (h != IntPtr.Zero) GetClassName(h, sb, 256);
        return sb.ToString();
    }

    public static bool IsTopmost(IntPtr h) {
        return h != IntPtr.Zero && (GetWindowLongPtr(h, -20).ToInt64() & 0x00000008L) != 0;
    }

    // Bildschirm, auf dem das Fenster liegt (MONITOR_DEFAULTTONEAREST).
    public static RECT MonitorOf(IntPtr h) {
        var mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        GetMonitorInfo(MonitorFromWindow(h, 2), ref mi);
        return mi.rcMonitor;
    }

    // Bedeckt das Fenster seinen ganzen Bildschirm (Vollbild, randlos oder exklusiv)? Zwei Pixel
    // Spielraum: Manche Spiele liegen einen Pixel daneben, Uzai selbst ist einen Pixel größer.
    public static bool CoversMonitor(IntPtr h) {
        RECT r;
        if (h == IntPtr.Zero || !IsWindowVisible(h) || IsIconic(h) || !GetWindowRect(h, out r)) return false;
        RECT m = MonitorOf(h);
        if (m.Right - m.Left <= 0) return false;
        return r.Left <= m.Left + 2 && r.Top <= m.Top + 2 && r.Right >= m.Right - 2 && r.Bottom >= m.Bottom - 2;
    }

    // Fenster eines Prozesses mit allem, was beim Nachsehen hilft, je Eintrag
    // „hwnd|breite|höhe|immer oben|deckt den Bildschirm|durchklickbar|klasse|titel“. Auch Fenster
    // ohne Titel (Lossless Scaling zeichnet sein Bild in ein solches Fenster über dem Spiel).
    public static List<string> Describe(int pid) {
        var list = new List<string>();
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            int p;
            GetWindowThreadProcessId(h, out p);
            if (p != pid || !IsWindowVisible(h)) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            long ex = GetWindowLongPtr(h, -20).ToInt64();
            list.Add(h.ToInt64() + "|" + (r.Right - r.Left) + "|" + (r.Bottom - r.Top) + "|" + (((ex & 0x8L) != 0) ? 1 : 0)
                + "|" + (CoversMonitor(h) ? 1 : 0) + "|" + (((ex & 0x20L) != 0) ? 1 : 0) + "|" + ClassOf(h) + "|" + Title(h));
            return true;
        }, IntPtr.Zero);
        return list;
    }
}

// Startbildschirm vorn halten: Während ein Spiel startet, legt ein eigener Faden Uzais Fenster
// alle 50 ms wieder ganz nach oben (HWND_TOPMOST, ohne Aktivieren), sobald etwas anderes darüber
// liegt. Sonst sah man beim Start Starter- und Emulatorfenster, die Taskleiste (Windows holt sie
// nach vorn, sobald das Vordergrundfenster kein Vollbild ist) und den Mauszeiger. Nichts davon
// bleibt: Der Faden hört auf, wenn Uzai „cover“ beendet, das Fenster weg ist oder die Zeit um ist.
public static class UzCover {
    static readonly object gate = new object();
    static IntPtr target = IntPtr.Zero;
    static int ownPid = 0;
    static DateTime until = DateTime.MinValue;
    static System.Threading.Thread worker;
    public static int Raised = 0;

    public static void Start(IntPtr h, int maxMs) {
        lock (gate) {
            target = h;
            ownPid = UzWin.PidOf(h);
            until = DateTime.UtcNow.AddMilliseconds(maxMs);
            Raised = 0;
            if (worker == null) {
                worker = new System.Threading.Thread(Loop);
                worker.IsBackground = true;
                worker.Start();
            }
        }
    }

    public static void Stop() { lock (gate) { target = IntPtr.Zero; } }

    // Beenden. Unter der Sperre: Danach legt der Faden das Fenster sicher nicht mehr nach oben.
    // Vorher konnte ein Anheben genau zwischen Godots „nicht mehr immer oben“ und dem Stopp landen –
    // dann blieb Uzai dauerhaft über allem (über mpv, über dem Desktop). keepTop: Uzai bleibt selbst
    // „immer oben“ (durchsichtig über dem Spiel); sonst gibt der Helfer den Platz hier frei.
    // behindFront: zusätzlich gleich hinter das Vordergrundfenster (ein Dialog, der wartet – „nicht
    // mehr oben“ allein legt Uzai über alle normalen Fenster, also auch über diesen Dialog).
    public static void Stop(IntPtr h, bool keepTop, bool behindFront) {
        lock (gate) {
            target = IntPtr.Zero;
            if (keepTop || h == IntPtr.Zero || !UzWin.IsWindow(h)) return;
            // HWND_NOTOPMOST; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER |
            // SWP_ASYNCWINDOWPOS (nicht auf Uzai warten: Dieser Faden liest auch Uzais Befehle)
            UzWin.SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 0x0001u | 0x0002u | 0x0010u | 0x0200u | 0x4000u);
            if (!behindFront) return;
            IntPtr fg = UzWin.GetForegroundWindow();
            if (fg != IntPtr.Zero && fg != h && UzWin.PidOf(fg) != UzWin.PidOf(h))
                UzWin.SetWindowPos(h, fg, 0, 0, 0, 0, 0x0001u | 0x0002u | 0x0010u | 0x0200u | 0x4000u);
        }
    }

    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);

    // Von DWM versteckt (Startmenü, Suche, angehaltene Store-Apps): IsWindowVisible sagt trotzdem ja.
    static bool Cloaked(IntPtr w) {
        int c = 0;
        try { return DwmGetWindowAttribute(w, 14, out c, 4) == 0 && c != 0; } catch { return false; }
    }

    public static bool Active() { lock (gate) { return target != IntPtr.Zero; } }

    // Liegt ein sichtbares, nicht durchklickbares Fenster eines anderen Programms über Uzai?
    // (Durchklickbare Overlays wie die von Grafiktreibern zählen nicht, sonst ginge das Gerangel
    // um den obersten Platz den ganzen Start über.)
    static bool Covered(IntPtr h) {
        UzWin.RECT me;
        if (!UzWin.GetWindowRect(h, out me)) return false;
        IntPtr w = UzWin.GetTopWindow(IntPtr.Zero);
        int guard = 0;
        while (w != IntPtr.Zero && w != h && guard++ < 2000) {
            if (UzWin.IsWindowVisible(w) && !UzWin.IsIconic(w) && UzWin.PidOf(w) != ownPid && !Cloaked(w)) {
                long ex = UzWin.GetWindowLongPtr(w, -20).ToInt64();
                UzWin.RECT r;
                if ((ex & 0x20L) == 0 && UzWin.GetWindowRect(w, out r)
                    && r.Right > me.Left && r.Left < me.Right && r.Bottom > me.Top && r.Top < me.Bottom
                    && r.Right - r.Left > 1 && r.Bottom - r.Top > 1) return true;
            }
            w = UzWin.GetWindow(w, 2);
        }
        return false;
    }

    static void Loop() {
        while (true) {
            IntPtr h;
            // Prüfen und Anheben unter der Sperre (siehe Stop).
            lock (gate) {
                h = target;
                if (h != IntPtr.Zero) {
                    try {
                        if (!UzWin.IsWindow(h) || DateTime.UtcNow > until) {
                            target = IntPtr.Zero;
                        } else if (UzWin.IsWindowVisible(h) && !UzWin.IsIconic(h) && (!UzWin.IsTopmost(h) || Covered(h))) {
                            // HWND_TOPMOST; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER |
                            // SWP_ASYNCWINDOWPOS (Uzais Fenster arbeitet die Aufträge der Reihe nach ab;
                            // so hält kein Warten auf Uzai die Sperre fest)
                            UzWin.SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001u | 0x0002u | 0x0010u | 0x0200u | 0x4000u);
                            Raised++;
                        }
                    } catch { }
                }
            }
            System.Threading.Thread.Sleep(h != IntPtr.Zero ? 50 : 500);
        }
    }
}

// Mauszeiger aus dem Bild: an den rechten Rand des Bildschirms, auf halber Höhe (dort ist von
// der Pfeilspitze nur ein Pixel zu sehen, und anders als in den Ecken liegt dort nichts, das auf
// den Zeiger reagiert – unten rechts wäre „Desktop anzeigen“). Ändert keine Einstellung.
public static class UzCursor {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);

    public static string Park(IntPtr h) {
        POINT old;
        GetCursorPos(out old);
        UzWin.RECT m = UzWin.MonitorOf(h);
        if (m.Right - m.Left <= 0) return old.X + "|" + old.Y + "|" + old.X + "|" + old.Y;
        int x = m.Right - 1;
        int y = m.Top + (m.Bottom - m.Top) / 2;
        SetCursorPos(x, y);
        return old.X + "|" + old.Y + "|" + x + "|" + y;
    }
}

// Steams Mitteilungen (die Pop-ups am Bildschirmrand: Erfolge, Freunde, Downloads) bleiben unsichtbar, solange
// Uzai läuft – Uzai zeigt sie selbst. Steam hat dafür keine Einstellung, die sich von außen und nur für diese
// Zeit schalten ließe. Die Pop-ups sind eigene Fenster von steamwebhelper.exe mit dem Titel
// „notificationtoasts_<Zahl>_desktop“; Steam benutzt dasselbe Fenster immer wieder. Ein Faden sieht alle
// 100 ms nach und gibt jedem dieser Fenster einen leeren Fensterbereich (SetWindowRgn): Es bleibt, wie und wo
// Steam es will, zeigt aber nichts und fängt keine Klicks. Beim Abschalten und wenn Uzai endet, bekommt jedes
// Fenster seinen Bereich von vorher zurück – danach zeigt Steam seine Mitteilungen wieder selbst. Kein
// Eingriff in Steams Dateien oder Einstellungen, nichts im Steam-Prozess. Pop-ups, die Steams Overlay im
// Spiel selbst zeichnet, sind keine Fenster: die erreicht das nicht. Unter Windows noch nicht erprobt.
public static class UzSteamStill {
    [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("user32.dll")] static extern int GetWindowRgn(IntPtr h, IntPtr rgn);
    [DllImport("gdi32.dll")] static extern IntPtr CreateRectRgn(int l, int t, int r, int b);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);

    static readonly object gate = new object();
    static bool on = false;
    static System.Threading.Thread worker;
    // Fenster -> sein Bereich von vorher (eine Kopie; IntPtr.Zero: es hatte keinen).
    static Dictionary<IntPtr, IntPtr> vorher = new Dictionary<IntPtr, IntPtr>();
    static Dictionary<int, bool> pids = new Dictionary<int, bool>();
    static DateTime pidsAt = DateTime.MinValue;
    // Für die Diagnose: verschiedene Fenster; wie oft der leere Bereich gesetzt wurde (öfter als Fenster: Steam
    // setzt ihn zurück); der letzte Titel; Titel von Steam, die ähnlich heißen, aber nicht passen.
    public static int Gesehen = 0;
    public static int Gesetzt = 0;
    public static string Zuletzt = "";
    static List<string> aehnlich = new List<string>();

    // Titel eines Mitteilungs-Fensters: „notificationtoasts_“, Ziffern, „_desktop“ – nichts sonst.
    public static bool IstMitteilung(string title) {
        const string a = "notificationtoasts_", b = "_desktop";
        if (title == null || title.Length <= a.Length + b.Length || title.Length > 48) return false;
        if (!title.StartsWith(a, StringComparison.Ordinal) || !title.EndsWith(b, StringComparison.Ordinal)) return false;
        for (int i = a.Length; i < title.Length - b.Length; i++)
            if (title[i] < '0' || title[i] > '9') return false;
        return true;
    }

    // Heißt ähnlich (für die Diagnose, falls Steam die Fenster einmal anders nennt)? Nur solche Titel werden
    // gemerkt – nie die von Chats oder Freunden.
    public static bool Aehnelt(string title) {
        if (title == null || title.Length == 0 || title.Length > 48) return false;
        string t = title.ToLowerInvariant();
        return t.Contains("toast") || t.Contains("notification");
    }

    public static string Aehnliche() { lock (gate) { return string.Join("|", aehnlich.ToArray()); } }

    public static void An() {
        lock (gate) {
            on = true;
            if (worker == null) {
                worker = new System.Threading.Thread(Loop);
                worker.IsBackground = true;
                worker.Start();
            }
        }
    }

    // Abschalten: Jedes Fenster bekommt seinen Bereich zurück (nach Erfolg gehört er dem System).
    public static int Aus() {
        lock (gate) {
            on = false;
            int n = 0;
            foreach (var kv in vorher) {
                try {
                    if (UzWin.IsWindow(kv.Key) && SetWindowRgn(kv.Key, kv.Value, true) != 0) n++;
                    else if (kv.Value != IntPtr.Zero) DeleteObject(kv.Value);
                } catch { }
            }
            vorher.Clear();
            return n;
        }
    }

    public static bool Aktiv() { lock (gate) { return on; } }

    static void Loop() {
        while (true) {
            System.Threading.Thread.Sleep(100);
            try { lock (gate) { if (on) Runde(); } } catch { }
        }
    }

    static void Runde() {
        if ((DateTime.UtcNow - pidsAt).TotalMilliseconds > 2000) {
            pidsAt = DateTime.UtcNow;
            pids.Clear();
            foreach (var p in System.Diagnostics.Process.GetProcessesByName("steamwebhelper")) {
                try { pids[p.Id] = true; } catch { } finally { p.Dispose(); }
            }
            // Fenster, die es nicht mehr gibt, vergessen.
            var weg = new List<IntPtr>();
            foreach (var kv in vorher) if (!UzWin.IsWindow(kv.Key)) weg.Add(kv.Key);
            foreach (var h in weg) { if (vorher[h] != IntPtr.Zero) DeleteObject(vorher[h]); vorher.Remove(h); }
        }
        if (pids.Count == 0) return;
        UzWin.EnumWindows(delegate (IntPtr h, IntPtr l) {
            int pid;
            UzWin.GetWindowThreadProcessId(h, out pid);
            if (!pids.ContainsKey(pid)) return true;
            var sb = new StringBuilder(64);
            UzWin.GetWindowText(h, sb, 64);
            string t = sb.ToString();
            if (IstMitteilung(t)) Leeren(h, t);
            else if (Aehnelt(t) && aehnlich.Count < 6 && !aehnlich.Contains(t)) aehnlich.Add(t);
            return true;
        }, IntPtr.Zero);
    }

    static void Leeren(IntPtr h, string title) {
        IntPtr jetzt = CreateRectRgn(0, 0, 0, 0);
        int art = GetWindowRgn(h, jetzt);      // 0: kein Bereich, 1: leer, 2 oder 3: einer
        if (art == 1) { DeleteObject(jetzt); return; }
        // Was jetzt gilt, ist der Bereich „von vorher“ (Steam hat ihn gesetzt, oder es gab keinen).
        IntPtr alt;
        if (vorher.TryGetValue(h, out alt)) { if (alt != IntPtr.Zero) DeleteObject(alt); }
        else Gesehen++;
        if (art == 2 || art == 3) vorher[h] = jetzt;
        else { DeleteObject(jetzt); vorher[h] = IntPtr.Zero; }
        IntPtr leer = CreateRectRgn(0, 0, 0, 0);
        if (SetWindowRgn(h, leer, true) != 0) { Gesetzt++; Zuletzt = title; }
        else DeleteObject(leer);
    }
}

public static class UzPad {
    // Reserved: XInputGetStateEx schreibt (anders als XInputGetState) vier Bytes mehr
    // (XINPUT_STATE_EX) – ohne das Feld landeten sie hinter der Struktur.
    [StructLayout(LayoutKind.Sequential)]
    public struct XState { public uint Packet; public ushort Buttons; public byte LT; public byte RT; public short LX; public short LY; public short RX; public short RY; public uint Reserved; }
    // Ordinal 100 ist XInputGetStateEx, die einzige Variante, die auch die Guide-Taste liefert.
    [DllImport("xinput1_4.dll", EntryPoint = "#100")] static extern int GetStateEx(int index, out XState s);
    public static volatile bool Combo = true;
    // Maus mit dem Controller: linker Stick bewegt, rechter Stick scrollt, A klickt links,
    // X klickt rechts, B ist Escape (nur fürs bediente Fenster, siehe UzGuard). Die Guide-Taste bleibt bei Uzai.
    public static volatile bool Mouse = false;
    // Controller-Status (UzPads, eigener C#-Teil, siehe Use-Pads): bekommt bei jedem Durchgang,
    // welche Anschlüsse verbunden sind, und liest Akku und Verbindung höchstens einmal pro Minute.
    public static volatile Action<int> OnPoll;
    // Ruhemodus (rest.gd): Wake = jede neue Taste, ein Trigger oder ein eben eingeschalteter
    // Controller meldet "pad-wake". HoldMs: Guide so lange gehalten meldet einmal "guide-hold"
    // (0 = aus), Loslassen "guide-up". Alles nur Meldungen; was passiert, entscheidet Uzai.
    public static volatile bool Wake = false;
    public static volatile int HoldMs = 1000;
    static int[] downAt = new int[4];
    static bool[] isDown = new bool[4];
    static bool[] holdSent = new bool[4];
    static bool[] seen = new bool[4];
    static byte[] prevLT = new byte[4], prevRT = new byte[4];
    static int lastWake;
    static void Emit(string ev, int i) {
        Console.Out.WriteLine("{\"id\":-1,\"event\":\"" + ev + "\",\"pad\":" + i + "}");
        Console.Out.Flush();
    }
    static double ax, ay, wheel;
    static ushort[] prev = new ushort[4];
    static System.Threading.Thread worker;
    static readonly object gate = new object();

    public static void Start(bool combo) {
        Combo = combo;
        lock (gate) {
            if (worker != null) return;
            worker = new System.Threading.Thread(Loop);
            worker.IsBackground = true;
            worker.Start();
        }
    }

    static void MouseStep(XState s, int i) {
        double lx = s.LX / 32768.0, ly = s.LY / 32768.0;
        double mag = Math.Sqrt(lx * lx + ly * ly);
        if (mag > 0.22) {
            double k = Math.Min(1.0, (mag - 0.22) / 0.78);
            double speed = k * k * 34.0 + k * 4.0;
            ax += lx / mag * speed;
            ay -= ly / mag * speed;
        }
        int dx = (int)ax, dy = (int)ay;
        ax -= dx; ay -= dy;
        if (dx != 0 || dy != 0) UzInput.MouseMove(dx, dy);
        double ry = s.RY / 32768.0;
        if (Math.Abs(ry) > 0.3) {
            wheel += ry * 14.0;
            int w = (int)wheel;
            if (w != 0) { UzInput.Wheel(w); wheel -= w; }
        }
        ushort b = s.Buttons, p = prev[i];
        // Bewegen und Klicken wirken überall (dafür ist die Controller-Maus da); ein Klick merkt sich,
        // welches Programm du gerade bedienst.
        if ((b & 0x1000) != 0 && (p & 0x1000) == 0) { UzGuard.NoteClick(); UzInput.MouseButton(0x0002); }
        if ((b & 0x1000) == 0 && (p & 0x1000) != 0) UzInput.MouseButton(0x0004);
        if ((b & 0x4000) != 0 && (p & 0x4000) == 0) { UzGuard.NoteClick(); UzInput.MouseButton(0x0008); }
        if ((b & 0x4000) == 0 && (p & 0x4000) != 0) UzInput.MouseButton(0x0010);
        // B ist Esc – aber nur für das Vordergrundfenster, das du gerade mit der Controller-Maus
        // bedienst (Zeiger darauf oder zuletzt angeklickt), nie für Anmelde- oder Sicherheitsfenster.
        if ((b & 0x2000) != 0 && (p & 0x2000) == 0 && UzGuard.MouseKeyOk()) { UzWin.Key(0x1B, true); UzWin.Key(0x1B, false); }
    }

    // --- Controller in einer eigenen App (src/core/app_steuerung.gd, Befehl „app-pad“) ------------
    // Steuerkreuz und linker Stick → Pfeiltasten (gehalten: nach 380 ms alle 110 ms), A/B/X/Y/LB/RB →
    // die Tasten des Profils, rechter Stick → Mauszeiger nur innerhalb des App-Fensters, RT klickt.
    // Gedrückt wird nur, solange genau dieses Fenster vorn ist (Fensternummer und Prozess, vorher vom
    // Helfer geprüft: Test-ExtAppWindow) und es kein geschütztes ist (UzGuard). Guide und View + Start
    // bleiben bei Uzai, die Maus mit dem Controller hat Vorrang. Ist das Fenster weg, endet es von selbst.
    static volatile bool appOn;
    static IntPtr appHwnd = IntPtr.Zero;
    static int appPid;
    static int[] appKeys = new int[6];          // A, B, X, Y, LB, RB: Taste (| 0x10000 = mit Umschalt), 0 = nichts
    static readonly ushort[] appMasks = { 0x1000, 0x2000, 0x4000, 0x8000, 0x0100, 0x0200 };
    static int[] appDir = new int[4];
    static int[] appNext = new int[4];
    static byte[] appPrevRT = new byte[4];
    static bool[] appClick = new bool[4];
    static double appAx, appAy;
    static int appLastKey, appMinute, appCount;
    [DllImport("user32.dll")] static extern bool GetCursorPos(out UzCursor.POINT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);

    public static bool AppOn { get { return appOn; } }

    // Erlaubt in einer App: F11, Esc, Pfeile, Enter, Leertaste, Backspace, Tab; Umschalt nur mit Tab
    // (dieselbe Liste wie Test-KeyCombo „app“). 0 = Knopf ohne Taste.
    public static bool AppKeyOk(int code) {
        if (code == 0) return true;
        if ((code & ~0x1FFFF) != 0) return false;
        int vk = code & 0xFFFF;
        if ((code & 0x10000) != 0) return vk == 0x09;
        return vk == 0x7A || vk == 0x1B || (vk >= 0x25 && vk <= 0x28) || vk == 0x0D || vk == 0x20 || vk == 0x08 || vk == 0x09;
    }

    public static bool AppStart(IntPtr h, int pid, int[] keys) {
        if (h == IntPtr.Zero || pid <= 4 || keys == null || keys.Length != 6) return false;
        foreach (int k in keys) if (!AppKeyOk(k)) return false;
        if (!UzWin.IsWindow(h) || UzWin.PidOf(h) != pid || UzGuard.Problem(h) != "") return false;
        lock (gate) {
            appHwnd = h; appPid = pid; appKeys = (int[])keys.Clone();
            for (int i = 0; i < 4; i++) { appDir[i] = 0; appClick[i] = false; appPrevRT[i] = 255; }
            appOn = true;
        }
        return true;
    }

    public static void AppStop() {
        appOn = false;
        appFeldPrev = 0;
        for (int i = 0; i < 4; i++) {
            if (appClick[i]) { appClick[i] = false; UzInput.MouseButton(0x0004); }
            appDir[i] = 0;
        }
    }

    // Die Regel ohne Windows-Aufrufe (prüfbar): Vorn liegt genau das geprüfte Fenster desselben Prozesses.
    public static bool AppTargetRule(long fg, long target, int fgPid, int targetPid) {
        return target != 0 && fg == target && targetPid > 4 && fgPid == targetPid;
    }

    static bool AppVorn(IntPtr h, int pid) {
        IntPtr fg = UzWin.GetForegroundWindow();
        return AppTargetRule(fg.ToInt64(), h.ToInt64(), UzWin.PidOf(fg), pid) && UzWin.IsWindow(h);
    }

    // --- Textfeld in der App: Uzais Tastatur (Befehle „app-pad“ und „app-text“) ------------------
    // Hat in der App vorn ein Textfeld den Fokus (UzAppFeld liest das über UI Automation, nur lesen),
    // öffnet Y statt seiner Taste Uzais Bildschirmtastatur („app-tastatur“). Kam der Fokus gleich nach
    // A bzw. einem Klick mit RT, geht sie von selbst auf, sonst meldet Uzai nur „Y Tastatur“
    // („app-textfeld“). Getippt wird danach nur an genau dieses Fenster (AppType).
    public static volatile Func<int> AppFeld;   // 0 = kein Textfeld, 1 = Textfeld, 2 = Passwortfeld (UzAppFeld)
    public static volatile int AppTopRand;      // Rand oben in Pixeln, den der Zeiger meidet (UzAppRand)
    static int appFeldPrev, appAktiv, appEventAt;
    public const int AppTextMax = 500;

    // Ist das fokussierte Element ein Textfeld? UI-Automation-Steuerelementart (Edit 50004, Document
    // 50030 nur mit Wert-Muster, Combobox 50003 nur mit beschreibbarem Wert), bedienbar, nicht nur lesbar.
    public static bool AppFeldEditierbar(int controlType, bool hasValue, bool readOnly, bool enabled) {
        if (!enabled || readOnly) return false;
        if (controlType == 50004) return true;
        if (controlType == 50030 || controlType == 50003) return hasValue;
        return false;
    }

    // Was der Wechsel des Fokus meldet: 2 = Tastatur öffnen (Textfeld neu, A oder Klick eben gedrückt),
    // 1 = nur „Y Tastatur“ zeigen, 0 = nichts.
    public static int AppFeldMeldung(int vorher, int jetzt, int msSeitAktiv) {
        if (jetzt <= 0 || vorher > 0) return 0;
        return (msSeitAktiv >= 0 && msSeitAktiv < 1500) ? 2 : 1;
    }

    // Text aus Uzais Tastatur: 1–500 Zeichen, keine Steuerzeichen (auch keine Zeilenumbrüche, kein
    // Tab), keine Richtungs- und unsichtbaren Formatzeichen, nur vollständige Ersatzpaare.
    public static bool AppTextOk(string s) {
        if (s == null || s.Length < 1 || s.Length > AppTextMax) return false;
        for (int i = 0; i < s.Length; i++) {
            char c = s[i];
            if (c < 0x20 || (c >= 0x7F && c <= 0x9F)) return false;
            if ((c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069) || c == 0xFEFF) return false;
            if (char.IsHighSurrogate(c)) { if (i + 1 >= s.Length || !char.IsLowSurrogate(s[i + 1])) return false; i++; continue; }
            if (char.IsLowSurrogate(c)) return false;
        }
        return true;
    }

    [DllImport("user32.dll")] static extern uint SendInput(uint n, UzInput.INPUT[] inputs, int size);

    // Text als Zeichen (KEYEVENTF_UNICODE, keine Tasten mit Umschalt, Strg oder Alt) an das App-Fenster –
    // vor jedem Zeichen geprüft, dass genau dieses Fenster vorn ist und kein geschütztes. Rückgabe: wie
    // viele Zeichen ankamen (bricht ab, sobald etwas anderes vorn liegt).
    public static int AppType(IntPtr h, int pid, string text) {
        if (!AppTextOk(text) || h == IntPtr.Zero || pid <= 4) return 0;
        int n = 0;
        int size = Marshal.SizeOf(typeof(UzInput.INPUT));
        for (int i = 0; i < text.Length; i++) {
            if (!AppVorn(h, pid) || UzGuard.Problem(h) != "") break;
            int len = char.IsHighSurrogate(text[i]) ? 2 : 1;
            var batch = new UzInput.INPUT[len * 2];
            for (int j = 0; j < len; j++) {
                ushort ch = (ushort)text[i + j];
                batch[j * 2].type = 1;
                batch[j * 2].u.ki = new UzInput.KEYBDINPUT { wVk = 0, wScan = ch, dwFlags = 0x0004u };
                batch[j * 2 + 1].type = 1;
                batch[j * 2 + 1].u.ki = new UzInput.KEYBDINPUT { wVk = 0, wScan = ch, dwFlags = 0x0004u | 0x0002u };
            }
            if (SendInput((uint)batch.Length, batch, size) == 0) break;
            n++;
            i += len - 1;
            System.Threading.Thread.Sleep(4);
        }
        return n;
    }

    static void AppMelden(string ev, int i) {
        int now = Environment.TickCount;
        if (unchecked(now - appEventAt) < 600) return;
        appEventAt = now;
        Emit(ev, i);
    }

    // Höchstens alle 35 ms und 1200 je Minute (gegen eine Schleife, die nicht aufhört).
    static void AppKey(int code) {
        int now = Environment.TickCount;
        if (code == 0 || !AppKeyOk(code) || unchecked(now - appLastKey) < 35) return;
        if (unchecked(now - appMinute) >= 60000) { appMinute = now; appCount = 0; }
        if (appCount >= 1200) return;
        appCount++;
        appLastKey = now;
        ushort vk = (ushort)(code & 0xFFFF);
        bool shift = (code & 0x10000) != 0;
        if (shift) UzInput.Key(0x10, true);
        UzInput.Key(vk, true);
        UzInput.Key(vk, false);
        if (shift) UzInput.Key(0x10, false);
    }

    static void AppStep(XState s, int i) {
        IntPtr h; int pid; int[] keys;
        lock (gate) { h = appHwnd; pid = appPid; keys = appKeys; }
        if (!UzWin.IsWindow(h)) { AppStop(); return; }
        bool vorn = AppVorn(h, pid);
        ushort b = s.Buttons, p = prev[i];
        int now0 = Environment.TickCount;
        int feld = 0;
        var ff = AppFeld;
        if (vorn && ff != null) { try { feld = ff(); } catch { feld = 0; } }
        for (int k = 0; k < 6; k++) {
            if ((b & appMasks[k]) == 0 || (p & appMasks[k]) != 0 || !vorn) continue;
            // Y im Textfeld: Uzais Tastatur statt der Taste des Profils.
            if (k == 3 && feld > 0) { AppMelden("app-tastatur", i); continue; }
            if (k == 0) appAktiv = now0;
            AppKey(keys[k]);
        }
        int meld = AppFeldMeldung(appFeldPrev, feld, unchecked(now0 - appAktiv));
        appFeldPrev = feld;
        if (meld == 2) AppMelden("app-tastatur", i);
        else if (meld == 1) AppMelden("app-textfeld", i);
        // Richtung: Steuerkreuz, sonst linker Stick (die stärkere Achse).
        int d = 0;
        if ((b & 0x0001) != 0) d = 0x26; else if ((b & 0x0002) != 0) d = 0x28;
        else if ((b & 0x0004) != 0) d = 0x25; else if ((b & 0x0008) != 0) d = 0x27;
        else {
            double lx = s.LX / 32768.0, ly = s.LY / 32768.0;
            if (Math.Max(Math.Abs(lx), Math.Abs(ly)) > 0.6) d = Math.Abs(lx) > Math.Abs(ly) ? (lx > 0 ? 0x27 : 0x25) : (ly > 0 ? 0x26 : 0x28);
        }
        int now = Environment.TickCount;
        if (d != appDir[i]) {
            appDir[i] = d;
            if (d != 0) { if (vorn) AppKey(d); appNext[i] = now + 380; }
        } else if (d != 0 && unchecked(now - appNext[i]) >= 0) {
            if (vorn) AppKey(d);
            appNext[i] = now + 110;
        }
        // Rechter Stick: Zeiger nur innerhalb des Fensters (liegt er außerhalb, springt er in die Mitte).
        UzWin.RECT r;
        if (!vorn || !UzWin.GetWindowRect(h, out r) || r.Right - r.Left < 8 || r.Bottom - r.Top < 8) {
            if (appClick[i]) { appClick[i] = false; UzInput.MouseButton(0x0004); }
            appPrevRT[i] = s.RT;
            return;
        }
        double rx = s.RX / 32768.0, ry = s.RY / 32768.0;
        double mag = Math.Sqrt(rx * rx + ry * ry);
        if (mag > 0.22) {
            double k = Math.Min(1.0, (mag - 0.22) / 0.78);
            double speed = k * k * 30.0 + k * 3.0;
            appAx += rx / mag * speed;
            appAy -= ry / mag * speed;
            int dx = (int)appAx, dy = (int)appAy;
            appAx -= dx; appAy -= dy;
            UzCursor.POINT c;
            if (GetCursorPos(out c)) {
                bool inside = c.X >= r.Left && c.X < r.Right && c.Y >= r.Top && c.Y < r.Bottom;
                int x = inside ? c.X + dx : (r.Left + r.Right) / 2;
                int y = inside ? c.Y + dy : (r.Top + r.Bottom) / 2;
                x = Math.Max(r.Left, Math.Min(r.Right - 1, x));
                // Oben bleibt ein schmaler Rand frei (UzAppRand): dort blendet Windows bzw. der Browser
                // im Vollbild sonst Titelleiste und „X“ ein.
                y = Math.Max(r.Top + Math.Max(0, Math.Min(AppTopRand, 200)), Math.Min(r.Bottom - 1, y));
                if (x != c.X || y != c.Y) SetCursorPos(x, y);
            }
        }
        // RT: Linksklick, nur mit dem Zeiger im Fenster.
        if (s.RT > 120 && appPrevRT[i] <= 120 && !appClick[i]) {
            UzCursor.POINT c;
            if (GetCursorPos(out c) && c.X >= r.Left && c.X < r.Right && c.Y >= r.Top && c.Y < r.Bottom) {
                appClick[i] = true;
                appAktiv = Environment.TickCount;
                UzInput.MouseButton(0x0002);
            }
        } else if (s.RT < 60 && appClick[i]) {
            appClick[i] = false;
            UzInput.MouseButton(0x0004);
        }
        appPrevRT[i] = s.RT;
    }

    static void Loop() {
        bool[] was = new bool[4];
        while (true) {
            bool any = false;
            int mask = 0;
            for (int i = 0; i < 4; i++) {
                XState s;
                int r;
                try { r = GetStateEx(i, out s); } catch { return; }
                if (r != 0) { was[i] = false; seen[i] = false; isDown[i] = false; continue; }
                any = true;
                mask |= 1 << i;
                bool guide = (s.Buttons & 0x0400) != 0;
                bool combo = Combo && (s.Buttons & 0x0030) == 0x0030;
                bool down = guide || combo;
                if (down && !was[i]) {
                    Console.Out.WriteLine("{\"id\":-1,\"event\":\"guide\",\"pad\":" + i + "}");
                    Console.Out.Flush();
                }
                // Losgelassen: Uzai unterscheidet damit kurz (Guide) und gehalten (Schnellmenü).
                if (!down && was[i]) Emit("guide-up", i);
                // Guide (oder View + Start) gehalten: einmal je Druck "guide-hold".
                if (down) {
                    if (!isDown[i]) { isDown[i] = true; holdSent[i] = false; downAt[i] = Environment.TickCount; }
                    else if (!holdSent[i] && HoldMs > 0 && unchecked(Environment.TickCount - downAt[i]) >= HoldMs) {
                        holdSent[i] = true;
                        Emit("guide-hold", i);
                    }
                } else { isDown[i] = false; holdSent[i] = false; }
                if (Wake) {
                    bool fresh = (s.Buttons & ~prev[i] & 0xFFFF) != 0
                        || (s.LT > 120 && prevLT[i] <= 120) || (s.RT > 120 && prevRT[i] <= 120)
                        || !seen[i];
                    if (fresh && unchecked(Environment.TickCount - lastWake) > 400) {
                        lastWake = Environment.TickCount;
                        Emit("pad-wake", i);
                    }
                }
                seen[i] = true;
                prevLT[i] = s.LT; prevRT[i] = s.RT;
                was[i] = down;
                // Guide halten + X: Clip speichern (Uzais eigene Aufnahme), ohne Guide-Menü.
                if (guide && !Mouse && (s.Buttons & 0x4000) != 0 && (prev[i] & 0x4000) == 0) {
                    Console.Out.WriteLine("{\"id\":-1,\"event\":\"clip\",\"pad\":" + i + "}");
                    Console.Out.Flush();
                }
                if (Mouse && !down) MouseStep(s, i);
                else if (appOn && !Mouse && !down) AppStep(s, i);
                prev[i] = s.Buttons;
            }
            var poll = OnPoll;
            if (poll != null) { try { poll(mask); } catch { } }
            System.Threading.Thread.Sleep(any ? ((Mouse || appOn) ? 12 : 30) : 1500);
        }
    }
}

public static class UzInput {
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public MOUSEINPUT mi; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion u; }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

    // Eine Taste über SendInput, mit Scan-Nummer und Extended-Kennzeichen wie eine echte
    // Tastatur. Rückgabe: wie viele Eingaben Windows angenommen hat (0: abgewiesen).
    public static uint Key(ushort vk, bool down) {
        var k = new INPUT(); k.type = 1;
        uint flags = down ? 0u : 2u;
        if (UzWin.IsExtended((byte)vk)) flags |= 1u;
        k.u.ki = new KEYBDINPUT { wVk = vk, wScan = (ushort)UzWin.MapVirtualKey(vk, 0), dwFlags = flags };
        return SendInput(1, new INPUT[] { k }, Marshal.SizeOf(typeof(INPUT)));
    }

    static void SendMouse(MOUSEINPUT mi) {
        var inp = new INPUT(); inp.type = 0; inp.u.mi = mi;
        SendInput(1, new INPUT[] { inp }, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void MouseMove(int dx, int dy) { SendMouse(new MOUSEINPUT { dx = dx, dy = dy, dwFlags = 0x0001 }); }
    public static void MouseButton(uint flags) { SendMouse(new MOUSEINPUT { dwFlags = flags }); }
    public static void Wheel(int clicks) { SendMouse(new MOUSEINPUT { mouseData = (uint)(clicks * 40), dwFlags = 0x0800 }); }
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(40);
        MouseButton(0x0002);
        System.Threading.Thread.Sleep(30);
        MouseButton(0x0004);
    }

    // Electron/Chromium baut seinen Bedienhilfe-Baum erst, wenn jemand danach fragt:
    // die Inhaltsfenster einmal über MSAA und UIA ansprechen.
    delegate bool ChildProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, ChildProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    public static int WakeAccessibility(IntPtr top) {
        int n = 0;
        EnumChildWindows(top, (h, l) => {
            var sb = new StringBuilder(128);
            GetClassName(h, sb, 128);
            if (sb.ToString().StartsWith("Chrome_RenderWidgetHostHWND")) {
                IntPtr r;
                foreach (int obj in new int[] { 1, -4, -25 })
                    SendMessageTimeout(h, 0x003D, IntPtr.Zero, new IntPtr(obj), 0x0002, 500, out r);
                n++;
            }
            return true;
        }, IntPtr.Zero);
        return n;
    }

    public static string ForegroundProcess() {
        int pid;
        UzWin.GetWindowThreadProcessId(UzWin.GetForegroundWindow(), out pid);
        try { return System.Diagnostics.Process.GetProcessById(pid).ProcessName.ToLowerInvariant(); } catch { return ""; }
    }

    // Sichtbares Fenster eines Prozesses (nach Namen), zum Beispiel Discord.
    public static IntPtr WindowOfProcess(string name) {
        foreach (var p in System.Diagnostics.Process.GetProcessesByName(name)) {
            var w = UzWin.WindowsOf(p.Id);
            if (w.Count > 0) return w[0];
        }
        return IntPtr.Zero;
    }
}

// Schutz für alles, was Tasten erzeugt (siehe docs/SECURITY.md „Eingaben an Fenster“): Anmelde-,
// Passwort- und Windows-Sicherheitsfenster bekommen von Uzai nie eine Taste – auch kein Esc der
// Controller-Maus. Der sichere Desktop (UAC, Strg+Alt+Entf) ist für Programme ohnehin unerreichbar;
// solange er offen ist, meldet Windows gar kein Vordergrundfenster, und das gilt hier als „nein“.
public static class UzGuard {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);

    // Prozesse (ohne .exe, klein): UAC-Abfrage, Windows-Anmeldedialog, Anmelde- und Sperrbildschirm,
    // Windows-Sicherheit/SmartScreen, Konto-Anmeldung (Microsoft/Arbeitskonto), Windows Hello,
    // Anmeldeinformationsverwaltung und verbreitete Passwortmanager.
    static readonly string[] Names = { "consent", "credentialuibroker", "logonui", "lockapp", "winlogon", "sechealthui",
        "securityhealthhost", "securityhealthsystray", "smartscreen", "useraccountcontrolsettings", "credwiz",
        "microsoft.aad.brokerplugin", "useraccountbroker", "wwahost", "bioenrollmenthost", "keepass", "keepassxc",
        "1password", "bitwarden" };
    // Fensterklassen derselben Dialoge, falls sie in einem anderen Prozess stecken.
    static readonly string[] Classes = { "Credential Dialog Xaml Host", "Secure UAP Dummy Window Class For Interim Dialog", "PasswordDialog" };

    public static bool SensitiveName(string name) {
        if (string.IsNullOrEmpty(name)) return false;
        string n = name.ToLowerInvariant();
        if (n.EndsWith(".exe")) n = n.Substring(0, n.Length - 4);
        foreach (string s in Names) if (n == s) return true;
        return false;
    }

    public static bool SensitiveClass(string cls) {
        if (string.IsNullOrEmpty(cls)) return false;
        foreach (string s in Classes) if (cls.IndexOf(s, StringComparison.OrdinalIgnoreCase) >= 0) return true;
        return false;
    }

    static string NameOf(int pid) {
        if (pid <= 0) return "";
        try { return System.Diagnostics.Process.GetProcessById(pid).ProcessName; } catch { return ""; }
    }

    // "" = darf Tasten bekommen; sonst warum nicht ("kein Fenster", "geschützt").
    public static string Problem(IntPtr h) {
        if (h == IntPtr.Zero || !UzWin.IsWindow(h)) return "kein Fenster";
        int pid = UzWin.PidOf(h);
        if (pid <= 4) return "geschützt";
        if (SensitiveName(NameOf(pid)) || SensitiveClass(UzWin.ClassOf(h))) return "geschützt";
        return "";
    }

    // Maus mit dem Controller: Prozess des Fensters, das zuletzt per Controller angeklickt wurde.
    static volatile int clickPid;

    public static int PidUnderCursor() {
        POINT p;
        if (!GetCursorPos(out p)) return 0;
        return UzWin.PidOf(WindowFromPoint(p));
    }

    public static void NoteClick() {
        try { clickPid = PidUnderCursor(); } catch { clickPid = 0; }
    }

    // Die Regel ohne Windows-Aufrufe (prüfbar): Das Vordergrundfenster ist das, was du gerade mit der
    // Controller-Maus bedienst – der Zeiger liegt darauf, oder du hast es zuletzt angeklickt – und
    // kein geschütztes Fenster.
    public static bool MouseKeyRule(int fgPid, string fgName, string fgClass, int cursorPid, int lastClickPid) {
        if (fgPid <= 4 || SensitiveName(fgName) || SensitiveClass(fgClass)) return false;
        return fgPid == cursorPid || fgPid == lastClickPid;
    }

    // Esc (B) der Controller-Maus: nur an das Fenster, das du gerade bedienst.
    public static bool MouseKeyOk() {
        try {
            IntPtr fg = UzWin.GetForegroundWindow();
            if (fg == IntPtr.Zero || !UzWin.IsWindow(fg)) return false;
            int pid = UzWin.PidOf(fg);
            return MouseKeyRule(pid, NameOf(pid), UzWin.ClassOf(fg), PidUnderCursor(), clickPid);
        } catch { return false; }
    }
}

public static class UzPadInfo {
    [StructLayout(LayoutKind.Sequential)] public struct XState { public uint Packet; public ushort Buttons; public byte LT; public byte RT; public short LX; public short LY; public short RX; public short RY; }
    [DllImport("xinput1_4.dll")] static extern int XInputGetState(int index, out XState s);

    public static int Count() {
        int n = 0;
        for (int i = 0; i < 4; i++) { XState st; if (XInputGetState(i, out st) == 0) n++; }
        return n;
    }
}

// Optische Laufwerke im Hintergrund beobachten: Ist eine Disc eingelegt, wie heißt sie, und was
// steht in ihrer SYSTEM.CNF (PS1/PS2)? Ein eigener Faden fragt alle 2,5 s; der Befehl liefert nur
// den letzten Stand und wartet so nie auf ein anlaufendes Laufwerk. Fehlermeldungen von Windows
// („Kein Datenträger“) sind für diesen Faden abgeschaltet.
public static class UzDisc {
    [DllImport("kernel32.dll")] static extern bool SetThreadErrorMode(uint mode, out uint old);
    static readonly object Gate = new object();
    static string last = "[]";
    static System.Threading.Thread worker;
    static readonly Dictionary<string, string> cnfCache = new Dictionary<string, string>();

    public static string State() {
        lock (Gate) {
            if (worker == null) {
                worker = new System.Threading.Thread(Loop);
                worker.IsBackground = true;
                worker.Start();
            }
            return last;
        }
    }

    static void Loop() {
        try { uint old; SetThreadErrorMode(0x0001 | 0x8000, out old); } catch { }
        while (true) {
            string s;
            try { s = Poll(); } catch { s = "[]"; }
            lock (Gate) { last = s; }
            System.Threading.Thread.Sleep(2500);
        }
    }

    static string Poll() {
        var sb = new StringBuilder("[");
        foreach (var d in System.IO.DriveInfo.GetDrives()) {
            if (d.DriveType != System.IO.DriveType.CDRom) continue;
            bool ready = false;
            string label = "";
            string cnf = "";
            try { ready = d.IsReady; } catch { }
            if (ready) {
                long total = 0;
                try { label = d.VolumeLabel; total = d.TotalSize; } catch { }
                string key = d.Name + "|" + label + "|" + total;
                if (!cnfCache.TryGetValue(key, out cnf)) {
                    cnf = ReadCnf(d.Name);
                    if (cnf == null) cnf = "";
                    else {
                        if (cnfCache.Count > 32) cnfCache.Clear();
                        cnfCache[key] = cnf;
                    }
                }
            }
            if (sb.Length > 1) sb.Append(",");
            sb.Append("{\"drive\":\"" + Esc(d.Name) + "\",\"ready\":" + (ready ? "true" : "false")
                + ",\"label\":\"" + Esc(label) + "\",\"cnf\":\"" + Esc(cnf) + "\"}");
        }
        return sb.Append("]").ToString();
    }

    // Inhalt von SYSTEM.CNF ("" wenn es keine gibt), null wenn das Lesen fehlschlug (gleich nochmal).
    static string ReadCnf(string root) {
        try {
            string p = System.IO.Path.Combine(root, "SYSTEM.CNF");
            if (!System.IO.File.Exists(p)) return "";
            using (var f = new System.IO.FileStream(p, System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.Read)) {
                var buf = new byte[4096];
                int n = f.Read(buf, 0, buf.Length);
                return Encoding.ASCII.GetString(buf, 0, Math.Max(0, n));
            }
        } catch { return null; }
    }

    static string Esc(string s) {
        if (s == null) return "";
        var sb = new StringBuilder();
        foreach (char c in s) {
            if (c == '\\') sb.Append("\\\\");
            else if (c == '"') sb.Append("\\\"");
            else if (c == '\n') sb.Append("\\n");
            else if (c < ' ') sb.Append(' ');
            else sb.Append(c);
        }
        return sb.ToString();
    }
}

// Läuft ein Prozess mit Adminrechten? Kein Zugriff auf seine Rechte heißt: er läuft höher als wir.
public static class UzElev {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr token, int cls, out int info, int len, out int ret);

    public static bool IsElevated(int pid) {
        IntPtr p = OpenProcess(0x1000, false, pid);
        if (p == IntPtr.Zero) return true;
        try {
            IntPtr t;
            if (!OpenProcessToken(p, 0x0008, out t)) return true;
            try { int e; int r; return GetTokenInformation(t, 20, out e, 4, out r) && e != 0; }
            finally { CloseHandle(t); }
        } finally { CloseHandle(p); }
    }

    // Wie IsElevated, aber ehrlich: 1 = Adminrechte, 0 = keine, -1 = unbekannt (der Prozess lässt
    // sich gar nicht öffnen, etwa durch einen Spielschutz) – das zählt nicht als „Admin“.
    public static int Level(int pid) {
        IntPtr p = OpenProcess(0x1000, false, pid);
        if (p == IntPtr.Zero) return -1;
        try {
            IntPtr t;
            if (!OpenProcessToken(p, 0x0008, out t)) return 1;
            try { int e; int r; if (!GetTokenInformation(t, 20, out e, 4, out r)) return -1; return e != 0 ? 1 : 0; }
            finally { CloseHandle(t); }
        } finally { CloseHandle(p); }
    }
}

// Lossless Scaling finden: nach Prozessnamen (geht ohne Rechte, auch wenn es als Administrator
// läuft – Get-Process liefert dann keinen Pfad) und nach Ordner (Pfad über
// QueryFullProcessImageName mit geringen Rechten). Pfade werden vor dem Vergleich vereinheitlicht
// (/ und \, doppelte Trenner, Groß/Klein): Uzai schickte „C:\\Program Files (x86)\…“, das passte
// zu keinem Prozesspfad – Lossless Scaling galt dann immer als „läuft nicht“.
public static class UzLs {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, int flags, StringBuilder name, ref int size);

    public static string ImagePath(int pid) {
        IntPtr h = OpenProcess(0x1000, false, pid);
        if (h == IntPtr.Zero) return "";
        try {
            var sb = new StringBuilder(1024);
            int n = sb.Capacity;
            return QueryFullProcessImageNameW(h, 0, sb, ref n) ? sb.ToString(0, n) : "";
        } finally { CloseHandle(h); }
    }

    public static string Norm(string p) {
        if (string.IsNullOrEmpty(p)) return "";
        string s = p.Replace('/', '\\');
        bool unc = s.StartsWith("\\\\");
        var sb = new StringBuilder(s.Length);
        char prev = '\0';
        foreach (char c in s) {
            if (c == '\\' && prev == '\\') continue;
            sb.Append(c);
            prev = c;
        }
        string r = sb.ToString().TrimEnd('\\');
        if (unc) r = "\\" + r;
        return r.ToLowerInvariant();
    }

    // Je Treffer „pid|name|stufe|wie|pfad“ (stufe wie UzElev.Level; wie: name oder ordner).
    public static List<string> Find(string[] names, string dir) {
        var list = new List<string>();
        string nd = Norm(dir);
        bool useDir = nd.Length > 3;
        if (useDir) nd += "\\";
        foreach (var p in System.Diagnostics.Process.GetProcesses()) {
            try {
                string n = p.ProcessName;
                bool byName = false;
                foreach (var w in names) if (string.Equals(n, w, StringComparison.OrdinalIgnoreCase)) byName = true;
                string path = "";
                bool byDir = false;
                if (byName || useDir) {
                    try { path = ImagePath(p.Id); } catch { }
                    byDir = useDir && path.Length > 0 && Norm(path).StartsWith(nd, StringComparison.Ordinal);
                }
                if (!byName && !byDir) continue;
                int lv = -1;
                try { lv = UzElev.Level(p.Id); } catch { }
                list.Add(p.Id + "|" + n + "|" + lv + "|" + (byName ? "name" : "ordner") + "|" + path);
            } catch { } finally { p.Dispose(); }
        }
        return list;
    }
}

// Discord-Übertragung per Tastenbelegung („Toggle Screen Share“). Alles mit fester Zeitgrenze:
// Der eigentliche Druck läuft in einem eigenen Faden, Fokuswechsel in noch einem. Hängt dabei ein
// Windows-Aufruf (Fokuswechsel auf ein beschäftigtes Fenster, langsame Tastatur-Hooks anderer
// Programme), antwortet der Helfer trotzdem nach höchstens budgetMs mit dem, was bis dahin
// geschah (steps) – früher blieb der ganze Befehl hängen und blockierte den Helfer-Weg.
// Discords Tastenbelegungen gelten global (Discord hört über einen systemweiten Tastatur-Hook mit):
// Das Spiel muss dafür nicht vorn liegen. Nur wenn Uzai selbst noch vorn liegt, holt der Helfer
// kurz das Spiel nach vorn (Discord überträgt das Spiel, das es erkennt).
public static class UzLive {
    class Job {
        public readonly object Gate = new object();
        public readonly StringBuilder Steps = new StringBuilder();
        public readonly System.Diagnostics.Stopwatch Clock = System.Diagnostics.Stopwatch.StartNew();
        public string Stage = "start";
        public bool Done;
        public int Accepted;
        public int Fallback;
        public int Expected;
        public bool Focused;
        public bool FocusTried;
        public string Blocked = "";
        public string Error = "";
        public void Step(string s) {
            lock (Gate) {
                if (Steps.Length > 0) Steps.Append("; ");
                Steps.Append(Clock.ElapsedMilliseconds).Append(" ms ").Append(s);
                Stage = s;
            }
        }
    }

    public static string Esc(string s) {
        if (s == null) return "";
        var sb = new StringBuilder(s.Length + 8);
        foreach (char c in s) {
            if (c == '"' || c == '\\') { sb.Append('\\').Append(c); }
            else if (c < 0x20) { sb.Append("\\u").Append(((int)c).ToString("x4")); }
            else sb.Append(c);
        }
        return sb.ToString();
    }

    static string ProcName(int pid) {
        if (pid <= 0) return "";
        try { return System.Diagnostics.Process.GetProcessById(pid).ProcessName; } catch { return ""; }
    }

    // Laufende Discord-Apps als JSON-Liste: name, count, elevated (true/false/null = unbekannt).
    public static string DiscordJson() {
        var sb = new StringBuilder("[");
        foreach (string n in new string[] { "Discord", "DiscordPTB", "DiscordCanary", "DiscordDevelopment" }) {
            System.Diagnostics.Process[] ps;
            try { ps = System.Diagnostics.Process.GetProcessesByName(n); } catch { continue; }
            if (ps.Length == 0) continue;
            int lvl = -1;
            try { lvl = UzElev.Level(ps[0].Id); } catch { }
            if (sb.Length > 1) sb.Append(",");
            sb.Append("{\"name\":\"").Append(n).Append("\",\"count\":").Append(ps.Length)
              .Append(",\"elevated\":").Append(lvl == 1 ? "true" : (lvl == 0 ? "false" : "null")).Append("}");
        }
        return sb.Append("]").ToString();
    }

    static string Lvl(int l) { return l == 1 ? "true" : (l == 0 ? "false" : "null"); }

    // Ein Tastenereignis: erst SendInput (wie eine echte Tastatur, mit Scan-Nummer), weist Windows
    // es ab, dasselbe über keybd_event.
    static void One(Job j, ushort vk, bool down) {
        uint a = 0;
        try { a = UzInput.Key(vk, down); } catch (Exception e) { lock (j.Gate) { j.Error = e.Message; } }
        if (a > 0) { lock (j.Gate) { j.Accepted++; } return; }
        try { UzWin.Key((byte)vk, down); lock (j.Gate) { j.Fallback++; } } catch (Exception e) { lock (j.Gate) { j.Error = e.Message; } }
    }

    // "" = drücken; sonst "nicht vorn" oder "geschützt".
    static string PressBlock(IntPtr now, IntPtr target, IntPtr fg0, int uzaiPid) {
        string p = UzGuard.Problem(now);
        if (p == "geschützt") return p;
        if (p != "") return "nicht vorn";
        if (now == target || now == fg0) return "";
        if (uzaiPid > 0 && UzWin.PidOf(now) == uzaiPid) return "";
        return "nicht vorn";
    }

    public static string Press(int[] codes, long hwnd, int[] pids, int uzaiPid, int holdMs, int focusMs, int budgetMs) {
        var j = new Job();
        j.Expected = 2 * codes.Length;
        if (holdMs <= 0) holdMs = 150;
        IntPtr fg0 = IntPtr.Zero;
        int fgPid0 = 0;
        IntPtr target = IntPtr.Zero;
        try {
            fg0 = UzWin.GetForegroundWindow();
            fgPid0 = UzWin.PidOf(fg0);
        } catch { }
        var worker = new System.Threading.Thread(delegate () {
            // Ziel und Fokus sind nur Beiwerk: Scheitern sie, wird trotzdem gedrückt – aber nur in ein
            // erwartetes Fenster (PressBlock).
            try {
                IntPtr h = new IntPtr(hwnd);
                if (hwnd != 0 && UzWin.IsWindow(h) && UzWin.IsWindowVisible(h)) target = h;
                else if (pids != null && pids.Length > 0) target = UzWin.Best(pids);
                j.Step("Ziel " + (target == IntPtr.Zero ? "keins" : "gefunden"));
            } catch (Exception e) { j.Step("Ziel: " + e.Message); }
            try {
                // Uzai liegt noch vorn (oder gar nichts): das Spiel kurz nach vorn holen, begrenzt.
                bool uzaiFront = uzaiPid > 0 && fgPid0 == uzaiPid;
                if (focusMs > 0 && target != IntPtr.Zero && target != fg0 && (uzaiFront || fg0 == IntPtr.Zero)) {
                    j.FocusTried = true;
                    IntPtr t = target;
                    bool ok = false;
                    var ft = new System.Threading.Thread(delegate () { try { ok = UzWin.Focus(t); } catch { } });
                    ft.IsBackground = true;
                    ft.Start();
                    if (ft.Join(focusMs)) { j.Focused = ok; j.Step(ok ? "Spiel vorn" : "Spiel nicht vorn"); }
                    else j.Step("Fokuswechsel hängt, drücke trotzdem");
                    System.Threading.Thread.Sleep(120);
                }
            } catch (Exception e) { j.Step("Fokus: " + e.Message); }
            try {
                // Nur ins erwartete Fenster: das Ziel, Uzai selbst oder das, was schon vorn lag, als der
                // Befehl kam (das Spiel) – nie in ein Fenster, das inzwischen von selbst nach vorn kam,
                // nie in ein Anmelde- oder Sicherheitsfenster.
                IntPtr now = IntPtr.Zero;
                try { now = UzWin.GetForegroundWindow(); } catch { }
                string block = PressBlock(now, target, fg0, uzaiPid);
                if (block != "") {
                    lock (j.Gate) { j.Blocked = block; j.Done = true; }
                    j.Step("nichts gedrückt: " + block);
                    return;
                }
                j.Step("drücke");
                foreach (int c in codes) { One(j, (ushort)c, true); System.Threading.Thread.Sleep(35); }
                System.Threading.Thread.Sleep(holdMs);
                for (int i = codes.Length - 1; i >= 0; i--) { One(j, (ushort)codes[i], false); System.Threading.Thread.Sleep(25); }
                j.Step("gedrückt");
            } catch (Exception e) {
                lock (j.Gate) { j.Error = e.Message; }
                j.Step("Fehler");
            }
            lock (j.Gate) { j.Done = true; }
        });
        worker.IsBackground = true;
        worker.Start();
        bool finished = worker.Join(budgetMs);
        if (!finished) j.Step("Zeitgrenze " + budgetMs + " ms erreicht");
        // Ab hier nur noch Auskunft (schnell, ohne Fenster-Nachrichten), nie vor dem Druck.
        int fgLvl = -1, selfLvl = -1;
        string fgName = "", fgTitle = "", after = "", targetTitle = "";
        int targetPid = 0;
        try { selfLvl = UzElev.Level(System.Diagnostics.Process.GetCurrentProcess().Id); } catch { }
        try { if (fgPid0 > 0) fgLvl = UzElev.Level(fgPid0); } catch { }
        try { fgName = ProcName(fgPid0); fgTitle = UzWin.Title(fg0); } catch { }
        try { after = UzWin.Title(UzWin.GetForegroundWindow()); } catch { }
        try { if (target != IntPtr.Zero) { targetTitle = UzWin.Title(target); targetPid = UzWin.PidOf(target); } } catch { }
        string discord = "[]";
        try { discord = DiscordJson(); } catch { }
        var sb = new StringBuilder("{");
        lock (j.Gate) {
            sb.Append("\"done\":").Append(j.Done ? "true" : "false");
            sb.Append(",\"sent\":").Append(j.Accepted + j.Fallback > 0 ? "true" : "false");
            sb.Append(",\"accepted\":").Append(j.Accepted + j.Fallback);
            sb.Append(",\"sendinput\":").Append(j.Accepted);
            sb.Append(",\"fallback\":").Append(j.Fallback);
            sb.Append(",\"expected\":").Append(j.Expected);
            sb.Append(",\"stage\":\"").Append(Esc(j.Stage)).Append("\"");
            sb.Append(",\"steps\":\"").Append(Esc(j.Steps.ToString())).Append("\"");
            sb.Append(",\"error\":\"").Append(Esc(j.Error)).Append("\"");
            sb.Append(",\"focus_tried\":").Append(j.FocusTried ? "true" : "false");
            sb.Append(",\"focused\":").Append(j.Focused ? "true" : "false");
            if (j.Blocked != "") sb.Append(",\"reason\":\"").Append(Esc(j.Blocked)).Append("\"");
        }
        sb.Append(",\"window\":\"").Append(Esc(targetTitle)).Append("\",\"target_pid\":").Append(targetPid);
        sb.Append(",\"foreground\":\"").Append(Esc(fgTitle)).Append("\",\"foreground_pid\":").Append(fgPid0);
        sb.Append(",\"foreground_name\":\"").Append(Esc(fgName)).Append("\"");
        sb.Append(",\"foreground_uzai\":").Append(uzaiPid > 0 && fgPid0 == uzaiPid ? "true" : "false");
        sb.Append(",\"foreground_elevated\":").Append(fgLvl == 1 ? "true" : "false");
        sb.Append(",\"foreground_elev\":").Append(Lvl(fgLvl));
        sb.Append(",\"self_elevated\":").Append(selfLvl == 1 ? "true" : "false");
        sb.Append(",\"foreground_after\":\"").Append(Esc(after)).Append("\"");
        sb.Append(",\"discord\":").Append(discord);
        sb.Append(",\"ms\":").Append(j.Clock.ElapsedMilliseconds);
        return sb.Append("}").ToString();
    }

    // Das Hauptfenster der Discord-App (sichtbar, mit Titel, das größte). 0: keins (etwa nur im
    // Infobereich). Rückgabe „hwnd|pid|name“.
    public static string DiscordWindow() {
        IntPtr best = IntPtr.Zero;
        long area = -1;
        int bestPid = 0;
        string bestName = "";
        foreach (string n in new string[] { "Discord", "DiscordPTB", "DiscordCanary", "DiscordDevelopment" }) {
            System.Diagnostics.Process[] ps;
            try { ps = System.Diagnostics.Process.GetProcessesByName(n); } catch { continue; }
            foreach (var p in ps) {
                foreach (IntPtr h in UzWin.WindowsOf(p.Id)) {
                    UzWin.RECT r;
                    if (!UzWin.GetWindowRect(h, out r)) continue;
                    long a = (long)(r.Right - r.Left) * (long)(r.Bottom - r.Top);
                    if (a > area) { area = a; best = h; bestPid = p.Id; bestName = n; }
                }
            }
        }
        return best.ToInt64() + "|" + bestPid + "|" + bestName;
    }

    // Fenster nach vorn, mit Zeitgrenze (Focus in eigenem Faden). 1 = vorn, 0 = nicht, -1 = hängt.
    public static int FocusBounded(long hwnd, int ms) {
        IntPtr h = new IntPtr(hwnd);
        if (hwnd == 0 || !UzWin.IsWindow(h)) return 0;
        bool ok = false;
        var t = new System.Threading.Thread(delegate () { try { ok = UzWin.Focus(h); } catch { } });
        t.IsBackground = true;
        t.Start();
        if (!t.Join(ms)) return -1;
        return ok ? 1 : 0;
    }
}

// Konsolenprogramme und Batchdateien ohne schwarzes Konsolenfenster starten. CreateProcess direkt
// (ohne vererbte Griffe), damit das Spiel nicht die Leitung zwischen Helfer und Uzai offen hält.
public static class UzStart {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute; public int dwFlags;
        public short wShowWindow; public short cbReserved2; public IntPtr lpReserved2;
        public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcInfo { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref StartupInfo si, out ProcInfo pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);

    // Subsystem aus dem PE-Kopf: 2 = Fensterprogramm, 3 = Konsolenprogramm, 0 = unbekannt.
    public static int Subsystem(string path) {
        try {
            using (var f = new System.IO.FileStream(path, System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.ReadWrite)) {
                var r = new System.IO.BinaryReader(f);
                if (r.ReadUInt16() != 0x5A4D) return 0;
                f.Seek(0x3C, System.IO.SeekOrigin.Begin);
                int pe = r.ReadInt32();
                if (pe <= 0 || pe + 0x60 > f.Length) return 0;
                f.Seek(pe, System.IO.SeekOrigin.Begin);
                if (r.ReadUInt32() != 0x00004550) return 0;
                f.Seek(pe + 0x5C, System.IO.SeekOrigin.Begin);
                return r.ReadUInt16();
            }
        } catch { return 0; }
    }

    // Prozessnummer, oder der negative Windows-Fehler (-740: braucht Adminrechte).
    public static int Hidden(string app, string cmdLine, string dir) {
        var si = new StartupInfo();
        si.cb = Marshal.SizeOf(typeof(StartupInfo));
        ProcInfo pi;
        var cmd = new StringBuilder(cmdLine, cmdLine.Length + 2);
        if (!CreateProcessW(app, cmd, IntPtr.Zero, IntPtr.Zero, false, 0x08000000, IntPtr.Zero, string.IsNullOrEmpty(dir) ? null : dir, ref si, out pi))
            return -Marshal.GetLastWin32Error();
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return pi.dwProcessId;
    }

    // Kurzer Befehl an ein laufendes Programm: eine zweite Instanz, die ihre Befehlszeile an die erste weitergibt
    // und endet (FxSound). Ohne Fenster nach vorn und ohne Sanduhr am Mauszeiger (STARTF_FORCEOFFFEEDBACK).
    // Wartet höchstens waitMs. Rückgabe: Endcode (0 …), -1 = läuft noch, sonst -(100000 + Windows-Fehler).
    public static int Still(string app, string cmdLine, string dir, int waitMs) {
        var si = new StartupInfo();
        si.cb = Marshal.SizeOf(typeof(StartupInfo));
        si.dwFlags = 0x1 | 0x80;
        si.wShowWindow = 7;
        ProcInfo pi;
        var cmd = new StringBuilder(cmdLine, cmdLine.Length + 2);
        if (!CreateProcessW(app, cmd, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, string.IsNullOrEmpty(dir) ? null : dir, ref si, out pi))
            return -(100000 + Marshal.GetLastWin32Error());
        CloseHandle(pi.hThread);
        try {
            if (WaitForSingleObject(pi.hProcess, (uint)Math.Max(0, waitMs)) != 0) return -1;
            uint code;
            return GetExitCodeProcess(pi.hProcess, out code) ? (int)(code & 0x7FFFFFFF) : 0;
        } finally { CloseHandle(pi.hProcess); }
    }

    // Fensterprogramm minimiert starten, ohne dass es den Fokus bekommt (SW_SHOWMINNOACTIVE).
    // Start-Process -WindowStyle Minimized aktiviert das Fenster – Spotify sprang so über Uzai.
    public static int MinNoActive(string app, string cmdLine, string dir) {
        var si = new StartupInfo();
        si.cb = Marshal.SizeOf(typeof(StartupInfo));
        si.dwFlags = 1;
        si.wShowWindow = 7;
        ProcInfo pi;
        var cmd = new StringBuilder(cmdLine, cmdLine.Length + 2);
        if (!CreateProcessW(app, cmd, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, string.IsNullOrEmpty(dir) ? null : dir, ref si, out pi))
            return -Marshal.GetLastWin32Error();
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return pi.dwProcessId;
    }
}

"@

# Controller-Status (Akku, Verbindung, Vibration, Ausschalten; siehe UzPads): erst beim ersten
# Gebrauch übersetzt, damit ein Problem dort den restlichen Helfer nie mitreißt. Use-Pads hängt
# UzPads.Tick an den laufenden Controller-Wächter (UzPad.OnPoll) – kein zweiter Abfrage-Faden.
$script:PadsSrc = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

// Controller-Status (siehe src/core/pads.gd). Xbox-/XInput-Controller: Akku und Verbindung, vom
// Controller-Wächter (UzPad) über UzPad.OnPoll mitgefragt – je Controller höchstens einmal pro Minute
// (und sofort, wenn einer dazukommt). PlayStation (DualSense, DualShock 4): ein eigener Faden liest
// einmal pro Minute einen Eingabebericht über HID (hid.dll, liegt jedem Windows bei) und gibt nur die
// Bytes weiter, in denen der Akkustand stehen kann – ausgewertet wird in Uzai (Pads.sony_battery).
// Dazu kurze, leise Vibration (XInputSetState) und „Controller ausschalten“ (XInputPowerOffController,
// Ordinal 103 von xinput1_4.dll: nicht dokumentiert, aber seit Windows 8 vorhanden; nur kabellose).
public static class UzPads {
    [StructLayout(LayoutKind.Sequential)] public struct Battery { public byte Type; public byte Level; }
    [StructLayout(LayoutKind.Sequential)] public struct Vibration { public ushort Left; public ushort Right; }
    [StructLayout(LayoutKind.Sequential)] public struct Caps {
        public byte Type; public byte SubType; public ushort Flags;
        public ushort Buttons; public byte LT; public byte RT; public short LX; public short LY; public short RX; public short RY;
        public ushort VibLeft; public ushort VibRight;
    }
    // XINPUT_CAPABILITIES_EX (wie in SDL): dahinter Hersteller- und Produktnummer.
    [StructLayout(LayoutKind.Sequential)] public struct CapsEx { public Caps C; public ushort Vid; public ushort Pid; public ushort Version; public ushort Unk1; public uint Unk2; }
    [StructLayout(LayoutKind.Sequential)] public struct XState { public uint Packet; public ushort Buttons; public byte LT; public byte RT; public short LX; public short LY; public short RX; public short RY; }

    [DllImport("xinput1_4.dll")] static extern int XInputGetState(int index, out XState s);
    [DllImport("xinput1_4.dll")] static extern int XInputGetBatteryInformation(int index, byte devType, out Battery info);
    [DllImport("xinput1_4.dll")] static extern int XInputGetCapabilities(int index, int flags, out Caps caps);
    [DllImport("xinput1_4.dll", EntryPoint = "#108")] static extern int XInputGetCapabilitiesEx(int one, int index, int flags, out CapsEx caps);
    [DllImport("xinput1_4.dll")] static extern int XInputSetState(int index, ref Vibration v);
    [DllImport("xinput1_4.dll", EntryPoint = "#103")] static extern int XInputPowerOffController(int index);

    const long BATTERY_MS = 60000;
    static readonly System.Diagnostics.Stopwatch Clock = System.Diagnostics.Stopwatch.StartNew();
    static readonly object Gate = new object();
    static readonly string[] slot = new string[] { "", "", "", "" };
    static readonly long[] readAt = new long[4];
    static long lastTick = -100000;
    static long lastKick = -100000;
    static volatile bool kick;
    static bool capsExMissing;

    // Vom Controller-Wächter bei jedem Durchgang (alle 30 ms, ohne Controller alle 1,5 s): mask =
    // welche Anschlüsse gerade verbunden sind. Liest nur, wenn ein Controller neu ist, eine Minute
    // um ist oder Uzai frisch fragt (kick). Ändert sich etwas, kommt {"event":"pad-status"}.
    public static void Tick(int mask) {
        long now = Clock.ElapsedMilliseconds;
        bool again = kick;
        kick = false;
        bool changed = false;
        for (int i = 0; i < 4; i++) {
            bool on = (mask & (1 << i)) != 0;
            string cur;
            lock (Gate) { cur = slot[i]; }
            if (!on) {
                if (cur != "") { lock (Gate) { slot[i] = ""; } changed = true; }
                continue;
            }
            if (cur != "" && !again && now - readAt[i] < BATTERY_MS) continue;
            string s = Read(i);
            readAt[i] = now;
            if (s != cur) { lock (Gate) { slot[i] = s; } changed = true; }
        }
        lastTick = now;
        if (changed) Emit();
    }

    static void Emit() {
        try {
            Console.Out.WriteLine("{\"id\":-1,\"event\":\"pad-status\"}");
            Console.Out.Flush();
        } catch { }
    }

    static string Read(int i) {
        int bt = 255, bl = 0, sub = 0, flags = 0, vid = 0, pid = 0;
        try { Battery b; if (XInputGetBatteryInformation(i, 0, out b) == 0) { bt = b.Type; bl = b.Level; } } catch { }
        try { Caps c; if (XInputGetCapabilities(i, 0, out c) == 0) { sub = c.SubType; flags = c.Flags; } } catch { }
        if (!capsExMissing) {
            try { CapsEx e; if (XInputGetCapabilitiesEx(1, i, 0, out e) == 0) { vid = e.Vid; pid = e.Pid; } }
            catch (EntryPointNotFoundException) { capsExMissing = true; }
            catch { }
        }
        return "{\"pad\":" + i + ",\"btype\":" + bt + ",\"blevel\":" + bl + ",\"sub\":" + sub + ",\"flags\":" + flags + ",\"vid\":" + vid + ",\"pid\":" + pid + "}";
    }

    static bool Connected(int i) {
        try { XState s; return XInputGetState(i, out s) == 0; } catch { return false; }
    }

    // Stand für Uzai: {"xinput":[…],"sony":[…],"watch":true}. rescan: gleich neu lesen (höchstens
    // alle 3 s), etwa wenn ein Controller dazukam. Läuft der Wächter nicht (anderer Helfer-Weg),
    // liest der Befehl selbst.
    public static string Status(bool rescan) {
        long now = Clock.ElapsedMilliseconds;
        EnsureHid();
        if (rescan && now - lastKick > 3000) {
            lastKick = now;
            kick = true;
            hidWake.Set();
        }
        bool watching = now - lastTick < 3000;
        if (!watching) {
            int mask = 0;
            for (int i = 0; i < 4; i++) if (Connected(i)) mask |= 1 << i;
            Tick(mask);
        }
        var sb = new StringBuilder("{\"xinput\":[");
        bool first = true;
        lock (Gate) {
            for (int i = 0; i < 4; i++) {
                if (slot[i] == "") continue;
                if (!first) sb.Append(",");
                sb.Append(slot[i]);
                first = false;
            }
        }
        string sony;
        lock (HidGate) { sony = hidLast; }
        sb.Append("],\"sony\":").Append(sony).Append(",\"watch\":").Append(watching ? "true" : "false").Append("}");
        return sb.ToString();
    }

    // Kurzer Impuls: low = linker (tiefer) Motor, high = rechter (heller), 0..65535; pad -1 = alle.
    // Kehrt sofort zurück; der Impuls läuft im Thread-Pool und endet immer mit Stillstand.
    public static int Pulse(int pad, int low, int high, int ms) {
        if (ms < 10) ms = 10;
        if (ms > 400) ms = 400;
        ushort l = (ushort)Math.Max(0, Math.Min(65535, low));
        ushort h = (ushort)Math.Max(0, Math.Min(65535, high));
        var targets = new List<int>();
        for (int i = 0; i < 4; i++) {
            if (pad >= 0 && i != pad) continue;
            if (Connected(i)) targets.Add(i);
        }
        if (targets.Count == 0) return 0;
        int dur = ms;
        ThreadPool.QueueUserWorkItem(delegate (object o) {
            try {
                foreach (int i in targets) { var v = new Vibration(); v.Left = l; v.Right = h; XInputSetState(i, ref v); }
                Thread.Sleep(dur);
            } catch { }
            try {
                foreach (int i in targets) { var z = new Vibration(); XInputSetState(i, ref z); }
            } catch { }
        });
        return targets.Count;
    }

    // 0 = ausgeschaltet; 1167 = nicht verbunden; -2 = Windows kennt die Funktion nicht.
    public static int PowerOff(int pad) {
        if (pad < 0 || pad > 3) return -1;
        int r;
        try { r = XInputPowerOffController(pad); }
        catch (EntryPointNotFoundException) { return -2; }
        catch { return -3; }
        kick = true;
        return r;
    }

    // --- PlayStation über HID ---------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential)] struct DevIface { public int Size; public Guid Cls; public int Flags; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)] struct HidAttr { public int Size; public ushort Vid; public ushort Pid; public ushort Ver; }
    [StructLayout(LayoutKind.Sequential, Size = 64)] struct HidCaps { public ushort Usage; public ushort UsagePage; public ushort InputLen; public ushort OutputLen; public ushort FeatureLen; }
    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref HidAttr a);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data, out HidCaps caps);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr enumerator, IntPtr parent, int flags);
    [DllImport("setupapi.dll")] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr devInfo, ref Guid g, int idx, ref DevIface di);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref DevIface di, IntPtr detail, int size, out int req, IntPtr devInfo);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll")] static extern bool CancelIoEx(SafeFileHandle h, IntPtr ov);

    static readonly object HidGate = new object();
    static string hidLast = "[]";
    static Thread hidWorker;
    static readonly AutoResetEvent hidWake = new AutoResetEvent(false);
    static readonly int[] Offsets = new int[] { 30, 32, 53, 54 };

    static void EnsureHid() {
        lock (HidGate) {
            if (hidWorker != null) return;
            hidWorker = new Thread(HidLoop);
            hidWorker.IsBackground = true;
            hidWorker.Priority = ThreadPriority.BelowNormal;
            hidWorker.Start();
        }
    }

    static void HidLoop() {
        while (true) {
            string s;
            try { s = ScanSony(); } catch { s = "[]"; }
            bool changed;
            lock (HidGate) { changed = s != hidLast; hidLast = s; }
            if (changed) Emit();
            hidWake.WaitOne(60000);
            // Nach einem Anstoß kurz warten: Windows meldet einen neuen Controller in Etappen an.
            Thread.Sleep(1500);
        }
    }

    static string ScanSony() {
        Guid g;
        HidD_GetHidGuid(out g);
        IntPtr set = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
        if (set == IntPtr.Zero || set == new IntPtr(-1)) return "[]";
        var sb = new StringBuilder("[");
        try {
            for (int idx = 0; idx < 256; idx++) {
                var di = new DevIface();
                di.Size = Marshal.SizeOf(typeof(DevIface));
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, idx, ref di)) break;
                string path = DetailPath(set, ref di);
                if (path == null || path.ToLowerInvariant().IndexOf("054c") < 0) continue;
                string e = null;
                try { e = ReadSony(path); } catch { }
                if (e == null) continue;
                if (sb.Length > 1) sb.Append(",");
                sb.Append(e);
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
        return sb.Append("]").ToString();
    }

    static string DetailPath(IntPtr set, ref DevIface di) {
        int req;
        SetupDiGetDeviceInterfaceDetail(set, ref di, IntPtr.Zero, 0, out req, IntPtr.Zero);
        if (req <= 0 || req > 4096) return null;
        IntPtr buf = Marshal.AllocHGlobal(req);
        try {
            Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
            if (!SetupDiGetDeviceInterfaceDetail(set, ref di, buf, req, out req, IntPtr.Zero)) return null;
            return Marshal.PtrToStringUni(new IntPtr(buf.ToInt64() + 4));
        } finally { Marshal.FreeHGlobal(buf); }
    }

    static bool IsSonyPad(int pid) {
        return pid == 0x05C4 || pid == 0x09CC || pid == 0x0BA0 || pid == 0x0CE6 || pid == 0x0DF2;
    }

    // Ein Eintrag: Produkt, Bluetooth (am Gerätepfad: HID-über-Bluetooth-Dienst 0x1124), Berichtsnummer
    // und -länge des ersten vollständigen Berichts und die Bytes an den möglichen Akku-Stellen.
    static string ReadSony(string path) {
        string low = path.ToLowerInvariant();
        bool bt = low.IndexOf("00001124-0000-1000-8000-00805f9b34fb") >= 0;
        SafeFileHandle h = CreateFile(path, 0x80000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
        bool canRead = !h.IsInvalid;
        if (!canRead) {
            h.Dispose();
            // Exklusiv geöffnet (z. B. DS4Windows mit HidHide): wenigstens erkennen, ohne Akku.
            h = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (h.IsInvalid) { h.Dispose(); return null; }
        }
        try {
            var a = new HidAttr();
            a.Size = Marshal.SizeOf(typeof(HidAttr));
            if (!HidD_GetAttributes(h, ref a) || a.Vid != 0x054C || !IsSonyPad(a.Pid)) return null;
            int len = 0;
            IntPtr pre;
            if (HidD_GetPreparsedData(h, out pre)) {
                try {
                    HidCaps caps;
                    if (HidP_GetCaps(pre, out caps) == 0x00110000) {
                        if (caps.UsagePage != 1 || (caps.Usage != 4 && caps.Usage != 5)) return null;
                        len = caps.InputLen;
                    }
                } finally { HidD_FreePreparsedData(pre); }
            }
            int rid = -1, n = 0;
            var st = new int[] { -1, -1, -1, -1 };
            if (canRead && len > 0 && len <= 4096) {
                var buf = new byte[len];
                var fs = new FileStream(h, FileAccess.Read, len, true);
                try {
                    for (int k = 0; k < 4; k++) {
                        int got = ReadOnce(fs, h, buf, len, 300);
                        if (got <= 0) break;
                        rid = buf[0];
                        n = got;
                        if ((rid == 0x01 && got >= 64) || rid == 0x11 || rid == 0x31) break;
                    }
                } finally { try { fs.Dispose(); } catch { } }
                for (int j = 0; j < Offsets.Length; j++) if (Offsets[j] < n) st[j] = buf[Offsets[j]];
            }
            return "{\"vid\":" + a.Vid + ",\"pid\":" + a.Pid + ",\"bt\":" + (bt ? "true" : "false") + ",\"read\":" + (canRead ? "true" : "false") +
                ",\"rid\":" + rid + ",\"n\":" + n + ",\"st\":[" + st[0] + "," + st[1] + "," + st[2] + "," + st[3] + "]}";
        } finally { if (!h.IsClosed) h.Dispose(); }
    }

    static int ReadOnce(FileStream fs, SafeFileHandle h, byte[] buf, int len, int ms) {
        IAsyncResult ar = fs.BeginRead(buf, 0, len, null, null);
        if (!ar.AsyncWaitHandle.WaitOne(ms)) {
            try { CancelIoEx(h, IntPtr.Zero); } catch { }
            try { fs.EndRead(ar); } catch { }
            return -1;
        }
        try { return fs.EndRead(ar); } catch { return -1; }
    }
}
'@
$script:PadsReady = $false
# Zweite Akku-Quelle (siehe Pads.apply_wgi): Windows.Gaming.Input kennt den Stand auch dort, wo
# XInput „Kabel“ meldet (Xbox-Controller über Bluetooth). Nur lesen; ohne WinRT (PowerShell 7,
# altes Windows) leer. Je Controller: Hersteller, Produkt, Prozent (-1 unbekannt), BatteryStatus.
function Get-WgiBatteries {
    try {
        if (-not $script:WgiReady) {
            $null = [Windows.Gaming.Input.RawGameController, Windows.Gaming.Input, ContentType = WindowsRuntime]
            $script:WgiReady = $true
        }
        $out = @()
        foreach ($c in [Windows.Gaming.Input.RawGameController]::RawGameControllers) {
            $r = $null
            try { $r = $c.TryGetBatteryReport() } catch { }
            if ($null -eq $r) { continue }
            $pct = -1
            $full = $r.FullChargeCapacityInMilliwattHours
            $rem = $r.RemainingCapacityInMilliwattHours
            if ($null -ne $full -and $null -ne $rem -and [int]$full -gt 0) {
                $pct = [int][math]::Max(0, [math]::Min(100, [math]::Round(100.0 * [int]$rem / [int]$full)))
            }
            $out += @{ vid = [int]$c.HardwareVendorId; pid = [int]$c.HardwareProductId; pct = $pct; st = [int]$r.Status }
        }
        return $out
    } catch { return @() }
}

function Use-Pads {
    if ($script:PadsReady) { return }
    Add-Type -TypeDefinition $script:PadsSrc
    [UzPad]::OnPoll = [Delegate]::CreateDelegate([Action[int]], [UzPads].GetMethod('Tick'))
    $script:PadsReady = $true
}

# Audiogeräte (COM) werden erst beim ersten Gebrauch übersetzt, damit ein Problem dort den
# restlichen Helfer nie mitreißt.
$script:AudioSrc = @"
using System;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class UzAudio {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom { }
    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClient { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        int GetCount(out int count);
        int Item(int index, out IMMDevice device);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        int OpenPropertyStore(int access, out IPropertyStore store);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }
    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        int GetCount(out int count);
        int GetAt(int prop, out PropertyKey key);
        int GetValue(ref PropertyKey key, out PropVariant value);
        int SetValue(ref PropertyKey key, ref PropVariant value);
        int Commit();
    }
    [StructLayout(LayoutKind.Sequential)] struct PropertyKey { public Guid fmtid; public int pid; }
    [StructLayout(LayoutKind.Explicit)] struct PropVariant { [FieldOffset(0)] public short vt; [FieldOffset(8)] public IntPtr pwszVal; [FieldOffset(16)] public IntPtr pad; }
    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig {
        int GetMixFormat(string a, IntPtr b);
        int GetDeviceFormat(string a, bool b, IntPtr c);
        int ResetDeviceFormat(string a);
        int SetDeviceFormat(string a, IntPtr b, IntPtr c);
        int GetProcessingPeriod(string a, bool b, IntPtr c, IntPtr d);
        int SetProcessingPeriod(string a, IntPtr b);
        int GetShareMode(string a, IntPtr b);
        int SetShareMode(string a, IntPtr b);
        int GetPropertyValue(string a, bool b, IntPtr c, IntPtr d);
        int SetPropertyValue(string a, bool b, IntPtr c, IntPtr d);
        int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string deviceId, int role);
        int SetEndpointVisibility(string a, bool b);
    }

    // Wiedergabegeräte als JSON: [{ id, name, default, ff }]. ff: Bauform laut Windows
    // (PKEY_AudioEndpoint_FormFactor: 1 Lautsprecher, 3 Kopfhörer, 5 Headset, 9 Bildschirm über
    // HDMI/DisplayPort …; -1 unbekannt) – für das Zeichen in „Bild & Ton“.
    public static string List() {
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        string defId = "";
        IMMDevice def;
        if (en.GetDefaultAudioEndpoint(0, 1, out def) == 0) def.GetId(out defId);
        IMMDeviceCollection col;
        en.EnumAudioEndpoints(0, 1, out col);
        int n; col.GetCount(out n);
        var key = new PropertyKey { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };
        var ffKey = new PropertyKey { fmtid = new Guid("1da5d803-d492-4edd-8c23-e0c0ffee7f0e"), pid = 0 };
        var sb = new StringBuilder("[");
        for (int i = 0; i < n; i++) {
            IMMDevice d; col.Item(i, out d);
            string id; d.GetId(out id);
            IPropertyStore ps; d.OpenPropertyStore(0, out ps);
            PropVariant v; ps.GetValue(ref key, out v);
            string name = v.pwszVal != IntPtr.Zero ? Marshal.PtrToStringUni(v.pwszVal) : id;
            // VT_UI4 (19): die Zahl steht im selben Feld wie sonst der Zeiger.
            PropVariant f;
            int ff = ps.GetValue(ref ffKey, out f) == 0 && f.vt == 19 ? (int)(f.pwszVal.ToInt64() & 0xFFFF) : -1;
            if (i > 0) sb.Append(",");
            sb.Append("{\"id\":\"" + Esc(id) + "\",\"name\":\"" + Esc(name) + "\",\"default\":" + (id == defId ? "true" : "false") + ",\"ff\":" + ff + "}");
        }
        return sb.Append("]").ToString();
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out int count);
        int SetMasterVolumeLevel(float levelDB, ref Guid ctx);
        int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
        int GetMasterVolumeLevel(out float levelDB);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(uint ch, float levelDB, ref Guid ctx);
        int SetChannelVolumeLevelScalar(uint ch, float level, ref Guid ctx);
        int GetChannelVolumeLevel(uint ch, out float levelDB);
        int GetChannelVolumeLevelScalar(uint ch, out float level);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
        int GetVolumeStepInfo(out uint step, out uint count);
        int VolumeStepUp(ref Guid ctx);
        int VolumeStepDown(ref Guid ctx);
        int QueryHardwareSupport(out uint mask);
        int GetVolumeRange(out float min, out float max, out float inc);
    }

    // Lautstärke des Standard-Wiedergabegeräts um delta Prozentpunkte ändern (0 = nur lesen), direkt
    // über Core Audio statt über die Lautstärketasten: Windows blendet dann keine eigene Anzeige über
    // Uzai und das Spiel. Lauter hebt Stumm auf. Rückgabe als JSON: { level 0..100, mute }.
    public static string Volume(int delta) {
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        IMMDevice dev;
        if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0) return "";
        var iid = typeof(IAudioEndpointVolume).GUID;
        object o;
        if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0 || o == null) return "";
        var vol = (IAudioEndpointVolume)o;
        float cur;
        vol.GetMasterVolumeLevelScalar(out cur);
        var ctx = Guid.Empty;
        if (delta != 0) {
            float nv = Math.Max(0f, Math.Min(1f, cur + delta / 100f));
            vol.SetMasterVolumeLevelScalar(nv, ref ctx);
            if (delta > 0) vol.SetMute(false, ref ctx);
            cur = nv;
        }
        bool mute;
        vol.GetMute(out mute);
        return "{\"level\":" + ((int)Math.Round(cur * 100f)) + ",\"mute\":" + (mute ? "true" : "false") + "}";
    }

    // --- Lautstärke einzelner Programme (wie im Lautstärkemixer von Windows) -------------------
    // Reihenfolge der Methoden = vtable von audiopolicy.h; alle mit PreserveSig (HRESULT zurück,
    // keine Ausnahme, kein verstecktes Rückgabe-Argument).
    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 {
        [PreserveSig] int GetAudioSessionControl(IntPtr groupingParam, uint flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr groupingParam, uint flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
        [PreserveSig] int RegisterSessionNotification(IntPtr notify);
        [PreserveSig] int UnregisterSessionNotification(IntPtr notify);
        [PreserveSig] int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr notify);
        [PreserveSig] int UnregisterDuckNotification(IntPtr notify);
    }
    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, [MarshalAs(UnmanagedType.IUnknown)] out object session);
    }
    // IAudioSessionControl2 erbt von IAudioSessionControl: dessen Methoden zuerst.
    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2 {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, IntPtr ctx);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, IntPtr ctx);
        [PreserveSig] int GetGroupingParam(out Guid group);
        [PreserveSig] int SetGroupingParam(IntPtr group, IntPtr ctx);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr notify);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr notify);
        [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetProcessId(out uint pid);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }
    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume {
        [PreserveSig] int SetMasterVolume(float level, ref Guid ctx);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ProcEntry {
        public uint dwSize; public uint cntUsage; public uint th32ProcessID; public IntPtr th32DefaultHeapID;
        public uint th32ModuleID; public uint cntThreads; public uint th32ParentProcessID; public int pcPriClassBase;
        public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "Process32FirstW")] static extern bool ProcFirst(IntPtr snap, ref ProcEntry e);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "Process32NextW")] static extern bool ProcNext(IntPtr snap, ref ProcEntry e);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr h, out long created, out long exited, out long kernel, out long user);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, int flags, StringBuilder name, ref int size);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);

    class Proc { public uint Pid; public uint Parent; public string Name = ""; public long Created = -1; public string Path = null; public bool Timed; }

    // Startzeit und Programmpfad eines Prozesses (ohne Rechte: -1 bzw. leer).
    static void Fill(Proc p, bool wantPath) {
        p.Timed = true;
        IntPtr h = OpenProcess(0x1000, false, p.Pid);
        if (h == IntPtr.Zero) { p.Path = ""; return; }
        try {
            long c, e, k, u;
            if (GetProcessTimes(h, out c, out e, out k, out u)) p.Created = c;
            if (wantPath) {
                var sb = new StringBuilder(1024);
                int n = sb.Capacity;
                p.Path = QueryFullProcessImageNameW(h, 0, sb, ref n) ? sb.ToString(0, n) : "";
            }
        } finally { CloseHandle(h); }
    }

    static Dictionary<uint, Proc> Snapshot() {
        var all = new Dictionary<uint, Proc>();
        IntPtr snap = CreateToolhelp32Snapshot(2, 0);
        if (snap == IntPtr.Zero || snap == new IntPtr(-1)) return all;
        try {
            var e = new ProcEntry();
            e.dwSize = (uint)Marshal.SizeOf(typeof(ProcEntry));
            bool ok = ProcFirst(snap, ref e);
            while (ok) {
                var name = (e.szExeFile ?? "").ToLowerInvariant();
                if (name.EndsWith(".exe")) name = name.Substring(0, name.Length - 4);
                all[e.th32ProcessID] = new Proc { Pid = e.th32ProcessID, Parent = e.th32ParentProcessID, Name = name };
                ok = ProcNext(snap, ref e);
            }
        } finally { CloseHandle(snap); }
        return all;
    }

    // Ordner, die zu viel träfen (Laufwerk, Programme, Windows): nie nach Ordner suchen.
    static bool BroadDir(string d) {
        if (d.Length < 4) return true;
        var broad = new Environment.SpecialFolder[] { Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86,
            Environment.SpecialFolder.Windows, Environment.SpecialFolder.System, Environment.SpecialFolder.UserProfile, Environment.SpecialFolder.Desktop };
        foreach (var f in broad) {
            string p = "";
            try { p = Environment.GetFolderPath(f); } catch { }
            if (p != "" && string.Equals(p.TrimEnd('\\'), d, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }

    static uint[] ParsePids(string csv) {
        var l = new List<uint>();
        foreach (var s in (csv ?? "").Split(',')) { uint v; if (uint.TryParse(s.Trim(), out v) && v > 4) l.Add(v); }
        return l.ToArray();
    }

    // Prozesse des Spiels: die angegebenen, das Fenster, alles aus dem Spielordner und alle ihre
    // Kindprozesse (Starter -> Spiel, Emulator -> Kern). Ein Kind muss nach dem Elternteil
    // gestartet sein (sonst wäre die Elternnummer schon neu vergeben).
    static Dictionary<uint, bool> GameTree(Dictionary<uint, Proc> all, string pidsCsv, string dir, long hwnd, string skipCsv) {
        var set = new Dictionary<uint, bool>();
        var queue = new List<uint>();
        foreach (var p in ParsePids(pidsCsv)) queue.Add(p);
        if (hwnd != 0) { uint wp; GetWindowThreadProcessId(new IntPtr(hwnd), out wp); if (wp > 4) queue.Add(wp); }
        string d = (dir ?? "").Replace('/', '\\').Trim().TrimEnd('\\');
        if (d != "" && !BroadDir(d)) {
            string pre = d + "\\";
            foreach (var p in all.Values) {
                if (p.Pid <= 4) continue;
                if (p.Path == null) Fill(p, true);
                if (p.Path != "" && p.Path.StartsWith(pre, StringComparison.OrdinalIgnoreCase)) queue.Add(p.Pid);
            }
        }
        var kids = new Dictionary<uint, List<uint>>();
        foreach (var p in all.Values) {
            if (p.Pid == p.Parent) continue;
            List<uint> l;
            if (!kids.TryGetValue(p.Parent, out l)) { l = new List<uint>(); kids[p.Parent] = l; }
            l.Add(p.Pid);
        }
        for (int i = 0; i < queue.Count && set.Count < 256; i++) {
            uint id = queue[i];
            if (set.ContainsKey(id)) continue;
            set[id] = true;
            List<uint> l;
            if (!kids.TryGetValue(id, out l)) continue;
            Proc parent;
            all.TryGetValue(id, out parent);
            foreach (var k in l) {
                if (set.ContainsKey(k)) continue;
                Proc child;
                if (parent != null && all.TryGetValue(k, out child)) {
                    if (!parent.Timed) Fill(parent, false);
                    if (!child.Timed) Fill(child, false);
                    if (parent.Created > 0 && child.Created > 0 && child.Created < parent.Created) continue;
                }
                queue.Add(k);
            }
        }
        foreach (var s in ParsePids(skipCsv)) set.Remove(s);
        return set;
    }

    // Lautstärke der Audiositzungen bestimmter Programme um delta Prozentpunkte ändern (0 = nur
    // lesen) – nie die Gesamtlautstärke. pids/dir/hwnd: das Spiel samt Kindprozessen; keys: Musik-
    // App nach Programmname bzw. Paketname (Store-Apps). Läuft in eigenem Faden mit Zeitgrenze,
    // damit der Helfer nie hängen bleibt. JSON: { found, level 0..100, mute, sessions, procs }.
    public static string AppVolume(string pidsCsv, string dir, long hwnd, string keysCsv, string skipCsv, int delta) {
        string res = null;
        var t = new Thread(() => {
            try { res = AppVolumeCore(pidsCsv, dir, hwnd, keysCsv, skipCsv, delta); }
            catch (Exception e) { res = "{\"found\":false,\"error\":\"" + Esc(e.Message) + "\"}"; }
        });
        t.IsBackground = true;
        try { t.SetApartmentState(ApartmentState.MTA); } catch { }   // Core Audio frei vom Fenster-Faden
        t.Start();
        if (!t.Join(2000)) return "{\"found\":false,\"timeout\":true}";
        return res ?? "{\"found\":false}";
    }

    // Ruhemodus: Ton eines Spiels (samt Kindprozessen) stumm bzw. wieder an, Pegel bleibt.
    public static string AppMute(string pidsCsv, string dir, long hwnd, string skipCsv, bool on) {
        string res = null;
        var t = new Thread(() => {
            try { res = AppVolumeCore(pidsCsv, dir, hwnd, "", skipCsv, 0, on ? 1 : 0); }
            catch (Exception e) { res = "{\"found\":false,\"error\":\"" + Esc(e.Message) + "\"}"; }
        });
        t.IsBackground = true;
        try { t.SetApartmentState(ApartmentState.MTA); } catch { }
        t.Start();
        if (!t.Join(2000)) return "{\"found\":false,\"timeout\":true}";
        return res ?? "{\"found\":false}";
    }

    static string AppVolumeCore(string pidsCsv, string dir, long hwnd, string keysCsv, string skipCsv, int delta, int setMute = -1) {
        var all = Snapshot();
        var keys = new List<string>();
        foreach (var k in (keysCsv ?? "").Split(',')) { var s = k.Trim().ToLowerInvariant(); if (s.Length >= 3) keys.Add(s); }
        bool byPid = (pidsCsv ?? "").Trim() != "" || (dir ?? "").Trim() != "" || hwnd != 0;
        var set = byPid ? GameTree(all, pidsCsv, dir, hwnd, skipCsv) : new Dictionary<uint, bool>();
        var skip = new Dictionary<uint, bool>();
        foreach (var s in ParsePids(skipCsv)) skip[s] = true;
        if (set.Count == 0 && keys.Count == 0) return "{\"found\":false,\"procs\":0}";

        var vols = new List<ISimpleAudioVolume>();
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        IMMDeviceCollection col;
        en.EnumAudioEndpoints(0, 1, out col);
        int n; col.GetCount(out n);
        for (int i = 0; i < n && i < 16; i++) {
            try {
                IMMDevice dev; col.Item(i, out dev);
                var iid = typeof(IAudioSessionManager2).GUID;
                object o;
                dev.Activate(ref iid, 23, IntPtr.Zero, out o);
                var mgr = o as IAudioSessionManager2;
                if (mgr == null) continue;
                IAudioSessionEnumerator sessions;
                if (mgr.GetSessionEnumerator(out sessions) != 0 || sessions == null) continue;
                int sc;
                if (sessions.GetCount(out sc) != 0) continue;
                for (int j = 0; j < sc && j < 256; j++) {
                    try {
                        object so;
                        if (sessions.GetSession(j, out so) != 0 || so == null) continue;
                        var ctl = so as IAudioSessionControl2;
                        var vol = so as ISimpleAudioVolume;
                        if (ctl == null || vol == null) continue;
                        int state;
                        if (ctl.GetState(out state) == 0 && state == 2) continue;      // abgelaufen
                        if (ctl.IsSystemSoundsSession() == 0) continue;                 // Systemklänge
                        uint pid;
                        if (ctl.GetProcessId(out pid) != 0) pid = 0;
                        if (pid == 0 || skip.ContainsKey(pid)) continue;
                        bool hit = set.ContainsKey(pid);
                        if (!hit && keys.Count > 0) {
                            Proc p;
                            string name = all.TryGetValue(pid, out p) ? p.Name : "";
                            string sid = "";
                            try { string s; if (ctl.GetSessionIdentifier(out s) == 0 && s != null) sid = s.ToLowerInvariant(); } catch { }
                            foreach (var k in keys) {
                                if (name == k || sid.Contains("\\" + k)) { hit = true; break; }
                            }
                        }
                        if (hit) vols.Add(vol);
                    } catch { }
                }
            } catch { }
        }
        if (vols.Count == 0) return "{\"found\":false,\"procs\":" + set.Count + "}";
        float cur = -1f;
        foreach (var v in vols) { float l; if (v.GetMasterVolume(out l) == 0 && l > cur) cur = l; }
        if (cur < 0f) cur = 1f;
        var ctx = Guid.Empty;
        if (delta != 0) {
            cur = Math.Max(0f, Math.Min(1f, cur + delta / 100f));
            foreach (var v in vols) {
                v.SetMasterVolume(cur, ref ctx);
                if (delta > 0) v.SetMute(false, ref ctx);
            }
        }
        if (setMute >= 0) {
            foreach (var v in vols) v.SetMute(setMute == 1, ref ctx);
        }
        bool mute = true;
        foreach (var v in vols) { bool m; if (v.GetMute(out m) != 0 || !m) { mute = false; break; } }
        return "{\"found\":true,\"level\":" + ((int)Math.Round(cur * 100f)) + ",\"mute\":" + (mute ? "true" : "false")
            + ",\"sessions\":" + vols.Count + ",\"procs\":" + set.Count + "}";
    }

    // --- Lautstärkemixer (src/core/mixer.gd) ------------------------------------------------
    // Eingaben sind nur Zahlen: Prozessnummern (über 4), Pegel 0..100 und Stumm 0/1, je -1 für
    // „lassen“; der Spielordner wird wie bei AppVolume nur verglichen. Jeder Aufruf läuft in
    // eigenem Faden mit Zeitgrenze, damit der Helfer nie hängen bleibt.

    static string Timed(Func<string> f) {
        string res = null;
        var t = new Thread(() => {
            try { res = f(); }
            catch (Exception e) { res = "{\"found\":false,\"error\":\"" + Txt(e.Message, 200) + "\"}"; }
        });
        t.IsBackground = true;
        try { t.SetApartmentState(ApartmentState.MTA); } catch { }
        t.Start();
        if (!t.Join(2500)) return "{\"found\":false,\"timeout\":true}";
        return res ?? "{\"found\":false}";
    }

    class Sess { public uint Pid; public int State; public ISimpleAudioVolume Vol; public object So; public string Id; }

    // Audiositzungen aller Wiedergabegeräte, ohne abgelaufene und ohne die Systemklänge.
    static List<Sess> Sessions() {
        var list = new List<Sess>();
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        IMMDeviceCollection col = null;
        en.EnumAudioEndpoints(0, 1, out col);
        if (col == null) return list;
        int n; col.GetCount(out n);
        for (int i = 0; i < n && i < 16; i++) {
            try {
                IMMDevice dev; col.Item(i, out dev);
                var iid = typeof(IAudioSessionManager2).GUID;
                object o;
                dev.Activate(ref iid, 23, IntPtr.Zero, out o);
                var mgr = o as IAudioSessionManager2;
                if (mgr == null) continue;
                IAudioSessionEnumerator sessions;
                if (mgr.GetSessionEnumerator(out sessions) != 0 || sessions == null) continue;
                int sc;
                if (sessions.GetCount(out sc) != 0) continue;
                for (int j = 0; j < sc && j < 256 && list.Count < 512; j++) {
                    try {
                        object so;
                        if (sessions.GetSession(j, out so) != 0 || so == null) continue;
                        var ctl = so as IAudioSessionControl2;
                        var vol = so as ISimpleAudioVolume;
                        if (ctl == null || vol == null) continue;
                        int state;
                        if (ctl.GetState(out state) != 0 || state == 2) continue;      // abgelaufen
                        if (ctl.IsSystemSoundsSession() == 0) continue;                 // Systemklänge
                        uint pid;
                        if (ctl.GetProcessId(out pid) != 0 || pid <= 4) continue;
                        string sid = null;
                        try { if (ctl.GetSessionInstanceIdentifier(out sid) != 0) sid = null; } catch { sid = null; }
                        list.Add(new Sess { Pid = pid, State = state, Vol = vol, So = so, Id = sid ?? ("pid:" + pid + ":" + i + ":" + j) });
                    } catch { }
                }
            } catch { }
        }
        return list;
    }

    // Lautstärke-Regler eines Standardgeräts (flow 0 Wiedergabe, 1 Aufnahme); null ohne Gerät.
    static IAudioEndpointVolume Endpoint(int flow, int role, out string id, out string name) {
        id = "";
        name = "";
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        IMMDevice dev = null;
        try { en.GetDefaultAudioEndpoint(flow, role, out dev); } catch { return null; }   // kein Gerät
        if (dev == null) return null;
        string i; dev.GetId(out i);
        id = i ?? "";
        try {
            var key = new PropertyKey { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };
            IPropertyStore ps; dev.OpenPropertyStore(0, out ps);
            PropVariant v; ps.GetValue(ref key, out v);
            if (v.pwszVal != IntPtr.Zero) name = Marshal.PtrToStringUni(v.pwszVal) ?? "";
        } catch { }
        var iid = typeof(IAudioEndpointVolume).GUID;
        object o;
        dev.Activate(ref iid, 23, IntPtr.Zero, out o);
        return o as IAudioEndpointVolume;
    }

    // Gesamtlautstärke und alle Programme, die gerade Ton ausgeben (Sitzung aktiv) – die des
    // Spiels (pids/dir/hwnd samt Kindprozessen) auch, wenn es gerade still ist. Je Prozess eine
    // Zeile: { master: { level, mute }, apps: [{ pid, name, desc, level, mute, game, active }] }.
    public static string Mixer(string pidsCsv, string dir, long hwnd, string skipCsv) {
        return Timed(() => MixerCore(pidsCsv, dir, hwnd, skipCsv));
    }

    static string MixerCore(string pidsCsv, string dir, long hwnd, string skipCsv) {
        var all = Snapshot();
        bool byGame = (pidsCsv ?? "").Trim() != "" || (dir ?? "").Trim() != "" || hwnd != 0;
        var game = byGame ? GameTree(all, pidsCsv, dir, hwnd, skipCsv) : new Dictionary<uint, bool>();
        var order = new List<uint>();
        var level = new Dictionary<uint, float>();
        var muted = new Dictionary<uint, bool>();
        var active = new Dictionary<uint, bool>();
        foreach (var s in Sessions()) {
            bool isGame = game.ContainsKey(s.Pid);
            if (s.State != 1 && !isGame) continue;                              // still und nicht das Spiel
            float l; bool m;
            if (s.Vol.GetMasterVolume(out l) != 0) l = 1f;
            if (s.Vol.GetMute(out m) != 0) m = false;
            if (!level.ContainsKey(s.Pid)) { order.Add(s.Pid); level[s.Pid] = l; muted[s.Pid] = m; active[s.Pid] = false; }
            else { level[s.Pid] = Math.Max(level[s.Pid], l); muted[s.Pid] = muted[s.Pid] && m; }
            if (s.State == 1) active[s.Pid] = true;
        }
        var sb = new StringBuilder("{\"found\":true,\"master\":");
        string id, nm;
        var mv = Endpoint(0, 1, out id, out nm);
        if (mv != null) {
            float cur; mv.GetMasterVolumeLevelScalar(out cur);
            bool m; mv.GetMute(out m);
            sb.Append("{\"level\":" + Lvl(cur) + ",\"mute\":" + B(m) + ",\"device\":\"" + Txt(nm, 80) + "\"}");
        } else sb.Append("null");
        sb.Append(",\"apps\":[");
        int k = 0;
        foreach (var pid in order) {
            if (k >= 48) break;
            Proc p;
            all.TryGetValue(pid, out p);
            string desc = "";
            if (p != null) {
                if (p.Path == null) Fill(p, true);
                if (p.Path != "") {
                    try { desc = System.Diagnostics.FileVersionInfo.GetVersionInfo(p.Path).FileDescription ?? ""; } catch { }
                }
            }
            if (k > 0) sb.Append(",");
            sb.Append("{\"pid\":" + pid + ",\"name\":\"" + Txt(p != null ? p.Name : "", 64) + "\",\"desc\":\"" + Txt(desc, 64)
                + "\",\"level\":" + Lvl(level[pid]) + ",\"mute\":" + B(muted[pid]) + ",\"game\":" + B(game.ContainsKey(pid))
                + ",\"active\":" + B(active[pid]) + "}");
            k++;
        }
        return sb.Append("]}").ToString();
    }

    // Pegel und/oder Stumm aller Sitzungen dieser Prozesse (höchstens 64). { found, level, mute }
    public static string MixerSet(string pidsCsv, int level, int mute) {
        return Timed(() => {
            var want = new Dictionary<uint, bool>();
            foreach (var p in ParsePids(pidsCsv)) { if (want.Count < 64) want[p] = true; }
            if (want.Count == 0) return "{\"found\":false}";
            var ctx = Guid.Empty;
            int n = 0;
            float cur = -1f;
            bool allMute = true;
            foreach (var s in Sessions()) {
                if (!want.ContainsKey(s.Pid)) continue;
                if (level >= 0) s.Vol.SetMasterVolume(Math.Min(100, level) / 100f, ref ctx);
                if (mute >= 0) s.Vol.SetMute(mute == 1, ref ctx);
                float l; if (s.Vol.GetMasterVolume(out l) == 0 && l > cur) cur = l;
                bool m; if (s.Vol.GetMute(out m) != 0 || !m) allMute = false;
                n++;
            }
            if (n == 0) return "{\"found\":false}";
            return "{\"found\":true,\"level\":" + Lvl(Math.Max(0f, cur)) + ",\"mute\":" + B(allMute) + ",\"sessions\":" + n + "}";
        });
    }

    // --- Ton aus dem Fernseher des Zimmers (src/room/raumton.gd) ---------------------------------
    // Nur die Kanal-Lautstärken (IChannelAudioVolume) der Audiositzungen des Spiels samt
    // Kindprozessen; gibt eine Sitzung sie nicht her, ihre Lautstärke (ISimpleAudioVolume). Nie die
    // Gesamtlautstärke, nie andere Programme, Eingaben nur Zahlen 0..1000. Was vorher eingestellt
    // war, merkt sich der Helfer je Sitzung (nur Zahlen, keine COM-Zeiger über Aufrufe hinweg) und
    // stellt es zurück: auf „aus“, nach LeaseMs ohne Auftrag (Uzai hängt oder ist abgestürzt) und
    // wenn Uzai den Helfer schließt (Ende der Befehlsschleife).
    [ComImport, Guid("1C158861-B533-4B30-B1CF-E853E51C59B8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IChannelAudioVolume {
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetChannelVolume(uint index, float level, ref Guid ctx);
        [PreserveSig] int GetChannelVolume(uint index, out float level);
        [PreserveSig] int SetAllVolumes(uint count, [MarshalAs(UnmanagedType.LPArray)] float[] levels, ref Guid ctx);
        [PreserveSig] int GetAllVolumes(uint count, [MarshalAs(UnmanagedType.LPArray)] float[] levels);
    }

    public const long LeaseMs = 5000;
    const long SucheMs = 2000;
    public const int MaxKanaele = 8;
    static readonly object RtLock = new object();
    static readonly System.Diagnostics.Stopwatch RtUhr = System.Diagnostics.Stopwatch.StartNew();
    static Dictionary<string, float[]> RtAlt = new Dictionary<string, float[]>();     // Sitzung -> Kanäle vorher
    static Dictionary<string, float> RtAltM = new Dictionary<string, float>();         // Sitzung -> Lautstärke vorher
    static Dictionary<uint, bool> RtMenge = new Dictionary<uint, bool>();
    static string RtSchluessel = "";
    static long RtGesucht = -100000;
    static long RtKontakt;
    static int RtWeg;
    static Timer RtWache;

    public static float Klemme(float v) {
        if (float.IsNaN(v) || v < 0f) return 0f;
        return v > 1f ? 1f : v;
    }

    // Faktor je Kanal aus links/rechts, Reihenfolge wie bei WAVEFORMATEXTENSIBLE: vorn links, vorn
    // rechts, Mitte, Bass, hinten links/rechts, seitlich links/rechts. Mono, Mitte und Bass: der Schnitt.
    public static float[] Faktoren(int n, float l, float r) {
        n = Math.Max(0, Math.Min(MaxKanaele, n));
        l = Klemme(l);
        r = Klemme(r);
        float m = (l + r) * 0.5f;
        var f = new float[n];
        for (int i = 0; i < n; i++) {
            if (n == 1) f[i] = m;
            else if (n == 3 && i == 2) f[i] = m;
            else if (n == 5 && i == 2) f[i] = m;
            else if (n == 5) f[i] = (i == 0 || i == 3) ? l : r;
            else if (n >= 6 && (i == 2 || i == 3)) f[i] = m;
            else f[i] = (i % 2 == 0) ? l : r;
        }
        return f;
    }

    static string Zahlen(float[] v) {
        var sb = new StringBuilder();
        for (int i = 0; i < v.Length; i++) {
            if (i > 0) sb.Append(",");
            sb.Append((int)Math.Round(Klemme(v[i]) * 1000f));
        }
        return sb.ToString();
    }

    // Die Sitzungen des Spiels (Prozessmenge höchstens alle SucheMs neu, das kostet am meisten).
    static List<Sess> RtSitzungen(string pidsCsv, string dir, long hwnd, string skipCsv) {
        string key = (pidsCsv ?? "") + "|" + (dir ?? "") + "|" + hwnd + "|" + (skipCsv ?? "");
        long jetzt = RtUhr.ElapsedMilliseconds;
        if (key != RtSchluessel || jetzt - RtGesucht > SucheMs) {
            RtMenge = GameTree(Snapshot(), pidsCsv, dir, hwnd, skipCsv);
            RtSchluessel = key;
            RtGesucht = jetzt;
        }
        var list = new List<Sess>();
        foreach (var s in Sessions()) { if (RtMenge.ContainsKey(s.Pid) && list.Count < 64) list.Add(s); }
        return list;
    }

    // Kanäle einer Sitzung lesen (1..MaxKanaele), sonst null.
    static float[] Lesen(IChannelAudioVolume k) {
        uint n;
        if (k == null || k.GetChannelCount(out n) != 0 || n < 1 || n > MaxKanaele) return null;
        var v = new float[n];
        for (uint i = 0; i < n; i++) { float x; if (k.GetChannelVolume(i, out x) != 0) return null; v[i] = Klemme(x); }
        return v;
    }

    public static string RaumTon(string pidsCsv, string dir, long hwnd, string skipCsv, int l, int r) {
        return Timed(() => {
            lock (RtLock) {
                RtKontakt = RtUhr.ElapsedMilliseconds;
                Wache();
                float fl = Klemme(Math.Max(0, Math.Min(1000, l)) / 1000f), fr = Klemme(Math.Max(0, Math.Min(1000, r)) / 1000f);
                var ctx = Guid.Empty;
                var da = new Dictionary<string, bool>();
                int n = 0;
                bool kanal = false;
                string alt = "";
                foreach (var s in RtSitzungen(pidsCsv, dir, hwnd, skipCsv)) {
                    try {
                        da[s.Id] = true;
                        var k = s.So as IChannelAudioVolume;
                        float[] vorher;
                        if (!RtAlt.TryGetValue(s.Id, out vorher) && !RtAltM.ContainsKey(s.Id)) {
                            vorher = Lesen(k);
                            if (vorher != null) RtAlt[s.Id] = vorher;
                            else { float m; if (s.Vol.GetMasterVolume(out m) == 0) RtAltM[s.Id] = Klemme(m); }
                        }
                        if (vorher != null && k != null) {
                            var f = Faktoren(vorher.Length, fl, fr);
                            for (int i = 0; i < vorher.Length; i++) k.SetChannelVolume((uint)i, Klemme(vorher[i] * f[i]), ref ctx);
                            kanal = true;
                            if (alt == "") alt = Zahlen(vorher);
                            n++;
                        } else if (RtAltM.ContainsKey(s.Id)) {
                            s.Vol.SetMasterVolume(Klemme(RtAltM[s.Id] * (fl + fr) * 0.5f), ref ctx);
                            n++;
                        }
                    } catch { }
                }
                // Sitzungen, die es nicht mehr gibt (Programm oder Ton zu): nicht mehr zurückstellbar.
                foreach (var id in new List<string>(RtAlt.Keys)) { if (!da.ContainsKey(id)) { RtAlt.Remove(id); RtWeg++; } }
                foreach (var id in new List<string>(RtAltM.Keys)) { if (!da.ContainsKey(id)) { RtAltM.Remove(id); RtWeg++; } }
                return "{\"found\":" + B(n > 0) + ",\"kanal\":" + B(kanal) + ",\"sessions\":" + n
                    + (alt != "" ? ",\"alt\":[" + alt + "]" : "") + "}";
            }
        });
    }

    // Alles zurück, was RaumTon verändert hat. { found, zurueck, weg }: weg = nicht mehr zurückstellbar.
    public static string RaumTonAus() {
        return Timed(() => { lock (RtLock) { return RtZurueck(); } });
    }

    static string RtZurueck() {
        int n = 0, weg = RtWeg;
        var ctx = Guid.Empty;
        var fertig = new Dictionary<string, bool>();
        if (RtAlt.Count > 0 || RtAltM.Count > 0) {
            foreach (var s in Sessions()) {
                if (fertig.ContainsKey(s.Id)) continue;
                try {
                    float[] vorher;
                    if (RtAlt.TryGetValue(s.Id, out vorher)) {
                        var k = s.So as IChannelAudioVolume;
                        bool ok = k != null;
                        for (int i = 0; ok && i < vorher.Length; i++) ok = k.SetChannelVolume((uint)i, vorher[i], ref ctx) == 0;
                        if (ok) { fertig[s.Id] = true; n++; }
                    } else if (RtAltM.ContainsKey(s.Id)) {
                        if (s.Vol.SetMasterVolume(RtAltM[s.Id], ref ctx) == 0) { fertig[s.Id] = true; n++; }
                    }
                } catch { }
            }
            foreach (var id in RtAlt.Keys) { if (!fertig.ContainsKey(id)) weg++; }
            foreach (var id in RtAltM.Keys) { if (!fertig.ContainsKey(id)) weg++; }
        }
        RtAlt.Clear();
        RtAltM.Clear();
        RtSchluessel = "";
        RtWeg = 0;
        return "{\"found\":" + B(n > 0) + ",\"zurueck\":" + n + ",\"weg\":" + weg + "}";
    }

    // Nach einem Absturz von Uzai und Helfer: gemerkte alte Kanal-Werte (0..1000) wieder setzen –
    // nur bei Sitzungen des Spiels mit genau so vielen Kanälen.
    public static string RaumTonWerte(string pidsCsv, string dir, long hwnd, string skipCsv, int[] werte) {
        return Timed(() => {
            lock (RtLock) {
                if (werte == null || werte.Length < 1 || werte.Length > MaxKanaele) return "{\"found\":false,\"error\":\"args\"}";
                var ctx = Guid.Empty;
                int n = 0;
                RtSchluessel = "";
                foreach (var s in RtSitzungen(pidsCsv, dir, hwnd, skipCsv)) {
                    try {
                        var k = s.So as IChannelAudioVolume;
                        uint c;
                        if (k == null || k.GetChannelCount(out c) != 0 || c != werte.Length) continue;
                        for (int i = 0; i < werte.Length; i++) k.SetChannelVolume((uint)i, Klemme(Math.Max(0, Math.Min(1000, werte[i])) / 1000f), ref ctx);
                        n++;
                    } catch { }
                }
                return "{\"found\":" + B(n > 0) + ",\"sessions\":" + n + "}";
            }
        });
    }

    // Wache: Sagt Uzai LeaseMs lang nichts mehr, stellt der Helfer von selbst zurück.
    static void Wache() {
        if (RtWache != null) return;
        RtWache = new Timer(_ => {
            bool faellig;
            lock (RtLock) { faellig = (RtAlt.Count > 0 || RtAltM.Count > 0) && RtUhr.ElapsedMilliseconds - RtKontakt > LeaseMs; }
            if (faellig) Timed(() => { lock (RtLock) { return (RtUhr.ElapsedMilliseconds - RtKontakt > LeaseMs) ? RtZurueck() : ""; } });
        }, null, 1000, 1000);
    }

    // Gesamtlautstärke setzen (Pegel 0..100 und/oder Stumm). { found, level, mute }
    public static string MasterSet(int level, int mute) {
        return Timed(() => {
            string id, nm;
            var vol = Endpoint(0, 1, out id, out nm);
            if (vol == null) return "{\"found\":false}";
            var ctx = Guid.Empty;
            if (level >= 0) vol.SetMasterVolumeLevelScalar(Math.Min(100, level) / 100f, ref ctx);
            if (mute >= 0) vol.SetMute(mute == 1, ref ctx);
            float cur; vol.GetMasterVolumeLevelScalar(out cur);
            bool m; vol.GetMute(out m);
            return "{\"found\":true,\"level\":" + Lvl(cur) + ",\"mute\":" + B(m) + "}";
        });
    }

    // Mikrofon von Windows stumm bzw. an (mute -1: nur lesen) – das Standard- und das
    // Kommunikationsgerät (Discord und Telefonie nehmen oft das zweite). Wie der Knopf in den
    // Windows-Einstellungen, nur Benutzerrechte. { found, mute (beide stumm), name }
    public static string Mic(int mute) {
        return Timed(() => {
            var seen = new List<string>();
            string name = "";
            bool any = false, allMute = true;
            var ctx = Guid.Empty;
            foreach (int role in new int[] { 0, 2 }) {
                string id, nm;
                var vol = Endpoint(1, role, out id, out nm);
                if (vol == null || seen.Contains(id)) continue;
                seen.Add(id);
                if (name == "") name = nm;
                if (mute >= 0) vol.SetMute(mute == 1, ref ctx);
                bool m; vol.GetMute(out m);
                if (!m) allMute = false;
                any = true;
            }
            if (!any) return "{\"found\":false}";
            return "{\"found\":true,\"mute\":" + B(allMute) + ",\"name\":\"" + Txt(name, 80) + "\"}";
        });
    }

    static string Lvl(float v) { return ((int)Math.Round(Math.Max(0f, Math.Min(1f, v)) * 100f)).ToString(); }
    static string B(bool b) { return b ? "true" : "false"; }

    // Text für JSON: ohne Steuerzeichen, gekürzt.
    static string Txt(string s, int max) {
        var sb = new StringBuilder();
        foreach (char c in (s ?? "")) {
            if (sb.Length >= max) break;
            if (c < ' ') sb.Append(' ');
            else if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else sb.Append(c);
        }
        return sb.ToString();
    }

    public static void SetDefault(string id) {
        var pc = (IPolicyConfig)new PolicyConfigClient();
        for (int role = 0; role < 3; role++) pc.SetDefaultEndpoint(id, role);
    }

    static string Esc(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }
}
"@
# Ganze Zahl von 0 bis max aus einem Befehl; fehlt sie oder ist sie keine: -1 („lassen“).
function Get-Num($v, [int]$max) {
    $n = 0
    if ($null -eq $v -or -not [int]::TryParse([string]$v, [ref]$n)) { return -1 }
    return [Math]::Max(-1, [Math]::Min($max, $n))
}
$script:AudioReady = $false
function Use-Audio {
    if (-not $script:AudioReady) { Add-Type -TypeDefinition $script:AudioSrc; $script:AudioReady = $true }
}

# Bildschirm, auf dem Uzai liegt (src/core/display_fit.gd): Name, Anschluss und HDR aus der
# Bildschirmkonfiguration von Windows (QueryDisplayConfig), nur lesen. Erst beim ersten Gebrauch
# übersetzt, damit ein Problem dort den restlichen Helfer nie mitreißt.
$script:DisplaySrc = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class UzDisplay {
    [StructLayout(LayoutKind.Sequential)] struct Luid { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] struct Rational { public uint Num; public uint Den; }
    [StructLayout(LayoutKind.Sequential)] struct PathSource { public Luid Adapter; public uint Id; public uint ModeIdx; public uint Status; }
    [StructLayout(LayoutKind.Sequential)] struct PathTarget {
        public Luid Adapter; public uint Id; public uint ModeIdx; public uint Tech; public uint Rotation; public uint Scaling;
        public Rational Refresh; public uint ScanLine; public int Available; public uint Status;
    }
    [StructLayout(LayoutKind.Sequential)] struct PathInfo { public PathSource Source; public PathTarget Target; public uint Flags; }
    [StructLayout(LayoutKind.Sequential, Size = 64)] struct ModeInfo { public uint Type; public uint Id; public Luid Adapter; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public uint Type; public uint Size; public Luid Adapter; public uint Id; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct SourceName {
        public Header H; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Gdi;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct TargetName {
        public Header H; public uint Flags; public uint Tech; public ushort Maker; public ushort Product; public uint Connector;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string Friendly;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Path;
    }
    [StructLayout(LayoutKind.Sequential)] struct AdvancedColor { public Header H; public uint Value; public uint Encoding; public uint Bits; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct MonitorInfoEx {
        public int Size; public Rect Monitor; public Rect Work; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] PathInfo[] pathArr, ref uint modes, [Out] ModeInfo[] modeArr, IntPtr topology);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SourceName p);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TargetName p);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref AdvancedColor p);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr mon, ref MonitorInfoEx info);

    const uint QDC_ONLY_ACTIVE_PATHS = 2;

    // Größen der Windows-Strukturen; stimmt eine nicht, liest Uzai gar nichts statt Unsinn.
    public static string Layout() {
        return Marshal.SizeOf(typeof(PathInfo)) + "," + Marshal.SizeOf(typeof(ModeInfo)) + "," + Marshal.SizeOf(typeof(SourceName)) + ","
            + Marshal.SizeOf(typeof(TargetName)) + "," + Marshal.SizeOf(typeof(AdvancedColor)) + "," + Marshal.SizeOf(typeof(MonitorInfoEx));
    }

    static string Tech(uint t) {
        if (t == 5) return "hdmi";
        if (t == 10) return "dp";
        if (t == 0x80000000u || t == 6 || t == 11 || t == 13) return "intern";
        if (t == 15) return "drahtlos";
        return "anders";
    }

    static string Esc(string s) {
        var b = new StringBuilder();
        foreach (char c in s ?? "") {
            if (c == '"' || c == '\\') b.Append('\\').Append(c);
            else if (c < ' ') b.Append(' ');
            else b.Append(c);
        }
        return b.ToString();
    }

    // Der Bildschirm unter diesem Fenster als JSON; {} wenn Windows nichts liefert.
    public static string Report(long hwnd) {
        if (Layout() != "72,64,84,420,32,104") return "{\"error\":\"layout\"}";
        var info = new MonitorInfoEx();
        info.Size = Marshal.SizeOf(typeof(MonitorInfoEx));
        IntPtr mon = MonitorFromWindow(new IntPtr(hwnd), 2);
        if (mon == IntPtr.Zero || !GetMonitorInfo(mon, ref info)) return "{}";
        uint np, nm;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out np, out nm) != 0) return "{}";
        var paths = new PathInfo[np];
        var modes = new ModeInfo[nm];
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero) != 0) return "{}";
        for (int i = 0; i < np; i++) {
            var src = new SourceName();
            src.H.Type = 1; src.H.Size = (uint)Marshal.SizeOf(typeof(SourceName));
            src.H.Adapter = paths[i].Source.Adapter; src.H.Id = paths[i].Source.Id;
            if (DisplayConfigGetDeviceInfo(ref src) != 0 || !string.Equals(src.Gdi, info.Device, StringComparison.OrdinalIgnoreCase)) continue;
            var tgt = new TargetName();
            tgt.H.Type = 2; tgt.H.Size = (uint)Marshal.SizeOf(typeof(TargetName));
            tgt.H.Adapter = paths[i].Target.Adapter; tgt.H.Id = paths[i].Target.Id;
            bool named = DisplayConfigGetDeviceInfo(ref tgt) == 0;
            var col = new AdvancedColor();
            col.H.Type = 9; col.H.Size = (uint)Marshal.SizeOf(typeof(AdvancedColor));
            col.H.Adapter = paths[i].Target.Adapter; col.H.Id = paths[i].Target.Id;
            string hdr = "";
            if (DisplayConfigGetDeviceInfo(ref col) == 0)
                hdr = (col.Value & 2) != 0 ? "an" : ((col.Value & 1) != 0 ? "moeglich" : "nein");
            var r = paths[i].Target.Refresh;
            double hz = r.Den > 0 ? (double)r.Num / r.Den : 0;
            return "{\"name\":\"" + Esc(named ? tgt.Friendly : "") + "\",\"tech\":\"" + Tech(named ? tgt.Tech : paths[i].Target.Tech)
                + "\",\"path\":\"" + Esc(named ? tgt.Path : "") + "\",\"hdr\":\"" + hdr + "\",\"hz\":"
                + hz.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture) + "}";
        }
        return "{}";
    }

    // --- Spiel-Profile (src/core/profile_run.gd) -------------------------------------------
    // Auflösung und Bildwiederholrate nur vorübergehend: ChangeDisplaySettingsEx mit CDS_FULLSCREEN
    // schreibt nichts in die Registrierung; zurück geht es mit dem dokumentierten Aufruf ohne Modus
    // (lpDevMode NULL, dwFlags 0), der den gespeicherten Modus von Windows wieder setzt. Nur ein
    // Modus, den Windows für diesen Bildschirm selbst aufzählt, und vorher mit CDS_TEST geprüft.
    // HDR über DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE (dokumentiert, ohne Adminrechte) – das bleibt
    // in Windows stehen, darum stellt Uzai es nach dem Spiel bzw. beim nächsten Start zurück.
    // „Bild & Ton“ (src/core/bild_ton.gd): erst vorübergehend wie oben, nach „Behalten“ derselbe
    // Modus mit CDS_UPDATEREGISTRY | CDS_NORESET – nur in die Anzeige-Einstellungen des Benutzers
    // geschrieben, ohne den Bildschirm noch einmal umzuschalten.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct DevMode {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        public ushort SpecVersion; public ushort DriverVersion; public ushort Size; public ushort DriverExtra;
        public uint Fields;
        public int PositionX; public int PositionY; public uint Orientation; public uint FixedOutput;
        public short Color; public short Duplex; public short YResolution; public short TTOption; public short Collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FormName;
        public ushort LogPixels; public uint BitsPerPel; public uint PelsWidth; public uint PelsHeight;
        public uint DisplayFlags; public uint DisplayFrequency;
        public uint IcmMethod; public uint IcmIntent; public uint MediaType; public uint DitherType;
        public uint Reserved1; public uint Reserved2; public uint PanningWidth; public uint PanningHeight;
    }
    [StructLayout(LayoutKind.Sequential)] struct SetAdvancedColor { public Header H; public uint Value; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DevMode dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DevMode dm, IntPtr hwnd, uint flags, IntPtr param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, IntPtr dm, IntPtr hwnd, uint flags, IntPtr param);
    [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(ref SetAdvancedColor p);

    const uint DM_MODE = 0x40000 | 0x80000 | 0x100000 | 0x400000;   // Farbtiefe, Breite, Höhe, Hz
    const uint CDS_UPDATEREGISTRY = 1;
    const uint CDS_TEST = 2;
    const uint CDS_FULLSCREEN = 4;
    const uint CDS_NORESET = 0x10000000;
    const int MAX_MODES = 400;

    // Nur „\\.\DISPLAY1“ … „\\.\DISPLAY99“.
    public static bool ValidDevice(string dev) {
        return System.Text.RegularExpressions.Regex.IsMatch(dev ?? "", @"^\\\\\.\\DISPLAY[0-9]{1,2}\z");
    }

    static DevMode NewMode() {
        var dm = new DevMode();
        dm.Size = (ushort)Marshal.SizeOf(typeof(DevMode));
        return dm;
    }

    static string DeviceOf(long hwnd) {
        var info = new MonitorInfoEx();
        info.Size = Marshal.SizeOf(typeof(MonitorInfoEx));
        IntPtr mon = MonitorFromWindow(new IntPtr(hwnd), 2);
        if (mon == IntPtr.Zero || !GetMonitorInfo(mon, ref info)) return "";
        return ValidDevice(info.Device) ? info.Device : "";
    }

    // Ziel (Adapter, Nummer) des aktiven Pfads, dessen Quelle dieses Gerät ist.
    static bool FindTarget(string dev, out Luid adapter, out uint id) {
        adapter = new Luid(); id = 0;
        uint np, nm;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out np, out nm) != 0) return false;
        var paths = new PathInfo[np];
        var modes = new ModeInfo[nm];
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero) != 0) return false;
        for (int i = 0; i < np; i++) {
            var src = new SourceName();
            src.H.Type = 1; src.H.Size = (uint)Marshal.SizeOf(typeof(SourceName));
            src.H.Adapter = paths[i].Source.Adapter; src.H.Id = paths[i].Source.Id;
            if (DisplayConfigGetDeviceInfo(ref src) != 0 || !string.Equals(src.Gdi, dev, StringComparison.OrdinalIgnoreCase)) continue;
            adapter = paths[i].Target.Adapter; id = paths[i].Target.Id;
            return true;
        }
        return false;
    }

    // "an", "moeglich" (kann HDR, ist aus), "nein" oder "" (unbekannt).
    static string HdrOf(string dev) {
        Luid ad; uint id;
        if (!FindTarget(dev, out ad, out id)) return "";
        var col = new AdvancedColor();
        col.H.Type = 9; col.H.Size = (uint)Marshal.SizeOf(typeof(AdvancedColor));
        col.H.Adapter = ad; col.H.Id = id;
        if (DisplayConfigGetDeviceInfo(ref col) != 0) return "";
        return (col.Value & 2) != 0 ? "an" : ((col.Value & 1) != 0 ? "moeglich" : "nein");
    }

    static bool LayoutOk() {
        return Layout() == "72,64,84,420,32,104" && Marshal.SizeOf(typeof(DevMode)) == 220 && Marshal.SizeOf(typeof(SetAdvancedColor)) == 24;
    }

    // Bildschirm unter dem Fenster: Gerät, jetziger Modus, HDR und die Modi, die Windows anbietet.
    public static string Modes(long hwnd) {
        if (!LayoutOk()) return "{\"error\":\"layout\"}";
        string dev = DeviceOf(hwnd);
        if (dev == "") return "{}";
        var cur = NewMode();
        if (!EnumDisplaySettings(dev, -1, ref cur)) return "{}";
        var seen = new System.Collections.Generic.Dictionary<string, bool>();
        var sb = new StringBuilder();
        for (int i = 0; i < 5000 && seen.Count < MAX_MODES; i++) {
            var dm = NewMode();
            if (!EnumDisplaySettings(dev, i, ref dm)) break;
            if (dm.BitsPerPel < 24 || dm.PelsWidth < 640 || dm.PelsHeight < 480 || dm.DisplayFrequency < 24) continue;
            string k = dm.PelsWidth + "x" + dm.PelsHeight + "@" + dm.DisplayFrequency;
            if (seen.ContainsKey(k)) continue;
            seen[k] = true;
            if (sb.Length > 0) sb.Append(",");
            sb.Append("{\"w\":" + dm.PelsWidth + ",\"h\":" + dm.PelsHeight + ",\"hz\":" + dm.DisplayFrequency + "}");
        }
        return "{\"device\":\"" + Esc(dev) + "\",\"w\":" + cur.PelsWidth + ",\"h\":" + cur.PelsHeight + ",\"hz\":" + cur.DisplayFrequency
            + ",\"hdr\":\"" + HdrOf(dev) + "\",\"modes\":[" + sb.ToString() + "]}";
    }

    public static string SetMode(string dev, int w, int h, int hz, bool keep) {
        if (!ValidDevice(dev)) return "{\"ok\":false,\"error\":\"device\"}";
        if (!LayoutOk()) return "{\"ok\":false,\"error\":\"layout\"}";
        var pick = NewMode();
        bool found = false;
        for (int i = 0; i < 5000; i++) {
            var dm = NewMode();
            if (!EnumDisplaySettings(dev, i, ref dm)) break;
            if (dm.PelsWidth == w && dm.PelsHeight == h && dm.DisplayFrequency == hz && dm.BitsPerPel >= 24 && (!found || dm.BitsPerPel > pick.BitsPerPel)) {
                pick = dm;
                found = true;
            }
        }
        if (!found) return "{\"ok\":false,\"error\":\"mode\"}";
        pick.Fields = DM_MODE;
        int t = ChangeDisplaySettingsEx(dev, ref pick, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
        if (t != 0) return "{\"ok\":false,\"error\":\"test\",\"code\":" + t + "}";
        int r = ChangeDisplaySettingsEx(dev, ref pick, IntPtr.Zero, keep ? CDS_UPDATEREGISTRY | CDS_NORESET : CDS_FULLSCREEN, IntPtr.Zero);
        return "{\"ok\":" + (r == 0 ? "true" : "false") + ",\"code\":" + r + "}";
    }

    // Zurück auf den Modus, den Windows gespeichert hat (nach CDS_FULLSCREEN der dokumentierte Weg).
    public static string Reset(string dev) {
        if (!ValidDevice(dev)) return "{\"ok\":false,\"error\":\"device\"}";
        int r = ChangeDisplaySettingsEx(dev, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        return "{\"ok\":" + (r == 0 ? "true" : "false") + ",\"code\":" + r + "}";
    }

    // HDR an (1) oder aus (0); danach den echten Stand lesen.
    public static string SetHdr(string dev, int on) {
        if (!ValidDevice(dev) || on < 0 || on > 1) return "{\"ok\":false,\"error\":\"args\"}";
        if (!LayoutOk()) return "{\"ok\":false,\"error\":\"layout\"}";
        string before = HdrOf(dev);
        if (before == "" || before == "nein") return "{\"ok\":false,\"error\":\"nein\",\"before\":\"" + before + "\"}";
        if ((before == "an") == (on == 1)) return "{\"ok\":true,\"before\":\"" + before + "\",\"after\":\"" + before + "\"}";
        Luid ad; uint id;
        if (!FindTarget(dev, out ad, out id)) return "{\"ok\":false,\"error\":\"pfad\"}";
        var set = new SetAdvancedColor();
        set.H.Type = 10; set.H.Size = (uint)Marshal.SizeOf(typeof(SetAdvancedColor));
        set.H.Adapter = ad; set.H.Id = id;
        set.Value = (uint)on;
        int r = DisplayConfigSetDeviceInfo(ref set);
        string after = HdrOf(dev);
        return "{\"ok\":" + (r == 0 && (after == "an") == (on == 1) ? "true" : "false") + ",\"code\":" + r
            + ",\"before\":\"" + before + "\",\"after\":\"" + after + "\"}";
    }
}
'@
$script:DisplayReady = $false
function Test-DisplayDevice([string]$dev) { return $dev -match '^\\\\\.\\DISPLAY[0-9]{1,2}\z' }
function Use-Display {
    if (-not $script:DisplayReady) { Add-Type -TypeDefinition $script:DisplaySrc; $script:DisplayReady = $true }
}

# Bildgröße in cm aus den EDID-Daten (WMI), passend zum Gerätepfad aus UzDisplay. Fernseher
# melden oft nur das Seitenverhältnis (16 × 9 cm) oder 0 – das sortiert display_fit.gd aus.
function Get-DisplayInfo([long]$hwnd) {
    Use-Display
    $d = [UzDisplay]::Report($hwnd) | ConvertFrom-Json
    $out = @{ ok = $true; name = [string]$d.name; tech = [string]$d.tech; hdr = [string]$d.hdr; hz = [double]$d.hz; w_cm = 0; h_cm = 0 }
    if ($d.error) { $out.ok = $false; $out.error = [string]$d.error; return $out }
    $parts = ([string]$d.path).Split('#')
    if ($parts.Count -ge 3) {
        $key = 'DISPLAY\' + $parts[1] + '\' + $parts[2]
        try {
            foreach ($m in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop)) {
                if (([string]$m.InstanceName).StartsWith($key, [StringComparison]::OrdinalIgnoreCase)) {
                    $out.w_cm = [int]$m.MaxHorizontalImageSize
                    $out.h_cm = [int]$m.MaxVerticalImageSize
                }
            }
        } catch {}
    }
    return $out
}

# Leistung im Guide (src/core/perf_live.gd): Last von Prozessor und Grafikkarte, Arbeits- und
# Grafikspeicher, Temperatur (nur NVIDIA, über nvml.dll des Treibers) und das Energieprofil. Alles
# mit Benutzerrechten über offizielle Schnittstellen: Leistungsindikatoren von Windows (PDH), DXGI,
# NVML, die Energie-Schnittstelle von Windows (dieselbe wie powercfg). Nichts im Spiel, kein Treiber.
# Gemessen wird in einem eigenen Faden und nur, solange Uzai nachfragt (Haltedauer); die Abfrage
# selbst gibt nur die letzte Messung zurück und kostet darum nichts. Erst beim ersten Gebrauch
# übersetzt, damit ein Problem dort den restlichen Helfer nie mitreißt.
$script:PerfSrc = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Globalization;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UzPerf {
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhOpenQuery(string source, IntPtr user, out IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhAddEnglishCounter(IntPtr query, string path, IntPtr user, out IntPtr counter);
    [DllImport("pdh.dll")] static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern uint PdhGetFormattedCounterArray(IntPtr counter, uint format, ref uint size, out uint count, IntPtr items);
    [DllImport("pdh.dll")] static extern uint PdhCloseQuery(IntPtr query);
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MemStatus m);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)] static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object factory);
    [DllImport("powrprof.dll")] static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
    [DllImport("powrprof.dll")] static extern uint PowerEnumerate(IntPtr root, IntPtr scheme, IntPtr sub, uint access, uint index, byte[] buf, ref uint size);
    [DllImport("powrprof.dll")] static extern uint PowerReadFriendlyName(IntPtr root, ref Guid scheme, IntPtr sub, IntPtr setting, byte[] buf, ref uint size);
    [DllImport("powrprof.dll")] static extern uint PowerSettingAccessCheck(uint access, IntPtr guid);
    [DllImport("powrprof.dll")] static extern uint PowerSetActiveScheme(IntPtr root, ref Guid scheme);
    [DllImport("powrprof.dll")] static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, out uint value);
    [DllImport("powrprof.dll")] static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, out uint value);
    [DllImport("powrprof.dll")] static extern bool GetPwrCapabilities(byte[] caps);
    [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out PowerStatus st);
    [StructLayout(LayoutKind.Sequential)] struct PowerStatus { public byte AcLine; public byte BatteryFlag; public byte Percent; public byte Saver; public int LifeTime; public int FullLifeTime; }

    [StructLayout(LayoutKind.Sequential)]
    class MemStatus {
        public uint Length = 64; public uint Load; public ulong Total; public ulong Avail; public ulong TotalPage;
        public ulong AvailPage; public ulong TotalVirtual; public ulong AvailVirtual; public ulong AvailExt;
    }

    // DXGI: nur die Plätze in der Tabelle bis GetDesc1/EnumAdapters1; die übrigen ruft niemand.
    [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFactory1 {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        void EnumAdapters(); void MakeWindowAssociation(); void GetWindowAssociation(); void CreateSwapChain(); void CreateSoftwareAdapter();
        [PreserveSig] int EnumAdapters1(uint index, out IAdapter1 adapter);
    }
    [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAdapter1 {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        void EnumOutputs(); void GetDesc(); void CheckInterfaceSupport();
        [PreserveSig] int GetDesc1(out AdapterDesc desc);
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct AdapterDesc {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Name;
        public uint Vendor; public uint Device; public uint SubSys; public uint Revision;
        public UIntPtr Dedicated; public UIntPtr DedicatedSystem; public UIntPtr Shared;
        public uint LuidLow; public int LuidHigh; public uint Flags;
    }
    class Adapter { public string Luid; public string Name; public double Vram; public uint Vendor; }

    // NVML (NVIDIA): nur Anzahl, Name, Temperatur.
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvVoid();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvCount(out uint n);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvHandle(uint i, out IntPtr dev);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvTemp(IntPtr dev, int sensor, out uint t);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvName(IntPtr dev, [Out] byte[] name, uint len);
    class Nv { public NvVoid Shutdown; public NvTemp Temp; public List<IntPtr> Devs = new List<IntPtr>(); public List<string> Names = new List<string>(); }

    const uint FMT = 0x00000200 | 0x00008000;     // PDH_FMT_DOUBLE | PDH_FMT_NOCAP100
    const uint MORE_DATA = 0x800007D2;
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    static readonly object Gate = new object();
    static Thread worker;
    static DateTime until = DateTime.MinValue;
    static int every = 1000;
    static int[] game = new int[0];
    static string last = "{\"warming\":true}";
    static DateTime failed = DateTime.MinValue;   // nach einem Fehler erst 10 s später neu versuchen

    // Letzte Messung zurückgeben und den Faden (wieder) laufen lassen: höchstens bis hold ms nach
    // dieser Abfrage, alle every ms. pids: Prozesse des Spiels („1234,5678“, nur Zahlen).
    public static string Snap(string pids, int everyMs, int holdMs) {
        var list = new List<int>();
        foreach (string s in (pids ?? "").Split(',')) {
            int n;
            if (int.TryParse(s.Trim(), NumberStyles.None, Inv, out n) && n > 4 && list.Count < 16) list.Add(n);
        }
        lock (Gate) {
            every = Math.Max(500, Math.Min(5000, everyMs));
            until = DateTime.UtcNow.AddMilliseconds(Math.Max(1000, Math.Min(20000, holdMs)));
            game = list.ToArray();
            if (worker == null && DateTime.UtcNow > failed.AddSeconds(10)) {
                last = "{\"warming\":true}";
                worker = new Thread(Run);
                worker.IsBackground = true;
                worker.Priority = ThreadPriority.BelowNormal;
                worker.Start();
            }
            return last;
        }
    }

    static void Run() {
        IntPtr q = IntPtr.Zero, cEng = IntPtr.Zero, cMem = IntPtr.Zero, cProc = IntPtr.Zero;
        Nv nv = null;
        try {
            if (PdhOpenQuery(null, IntPtr.Zero, out q) != 0) q = IntPtr.Zero;
            if (q != IntPtr.Zero) {
                if (PdhAddEnglishCounter(q, "\\GPU Engine(*)\\Utilization Percentage", IntPtr.Zero, out cEng) != 0) cEng = IntPtr.Zero;
                if (PdhAddEnglishCounter(q, "\\GPU Adapter Memory(*)\\Dedicated Usage", IntPtr.Zero, out cMem) != 0) cMem = IntPtr.Zero;
                if (PdhAddEnglishCounter(q, "\\GPU Process Memory(*)\\Dedicated Usage", IntPtr.Zero, out cProc) != 0) cProc = IntPtr.Zero;
                PdhCollectQueryData(q);
            }
            List<Adapter> adapters = Adapters();
            nv = NvOpen(adapters);
            long i0, k0, u0;
            GetSystemTimes(out i0, out k0, out u0);
            var cpu0 = new Dictionary<int, double>();
            DateTime t0 = DateTime.UtcNow;
            int first;
            lock (Gate) first = Math.Min(every, 500);
            Thread.Sleep(first);
            while (true) {
                int ms;
                int[] pids;
                lock (Gate) {
                    if (DateTime.UtcNow > until) { worker = null; return; }
                    ms = every;
                    pids = game;
                }
                var sb = new StringBuilder("{\"ok\":true");
                long i1, k1, u1;
                GetSystemTimes(out i1, out k1, out u1);
                double busy = (k1 - k0) + (u1 - u0);
                Put(sb, "cpu", busy > 0 ? (busy - (i1 - i0)) / busy * 100.0 : -1);
                i0 = i1; k0 = k1; u0 = u1;
                Put(sb, "cores", Environment.ProcessorCount);
                var m = new MemStatus();
                if (GlobalMemoryStatusEx(m)) { Put(sb, "ram_total", m.Total); Put(sb, "ram_used", m.Total - m.Avail); }
                // Das Spiel: Rechenzeit seit der letzten Messung über alle Kerne, Arbeitsspeicher.
                DateTime t1 = DateTime.UtcNow;
                double wall = (t1 - t0).TotalMilliseconds * Environment.ProcessorCount;
                t0 = t1;
                double gcpu = 0, gram = 0;
                bool cpuOk = pids.Length > 0, ramOk = false;
                var cpu1 = new Dictionary<int, double>();
                foreach (int pid in pids) {
                    Process p = null;
                    try { p = Process.GetProcessById(pid); } catch { cpuOk = false; continue; }
                    try { gram += p.WorkingSet64; ramOk = true; } catch { }
                    try {
                        double c = p.TotalProcessorTime.TotalMilliseconds;
                        cpu1[pid] = c;
                        double c0;
                        if (cpu0.TryGetValue(pid, out c0)) gcpu += c - c0; else cpuOk = false;
                    } catch { cpuOk = false; }
                    p.Dispose();
                }
                cpu0 = cpu1;
                Put(sb, "game_cpu", cpuOk && wall > 0 ? gcpu / wall * 100.0 : -1);
                Put(sb, "game_ram", ramOk ? gram : -1);
                if (q != IntPtr.Zero) PdhCollectQueryData(q);
                Gpu(sb, Read(cEng), Read(cMem), Read(cProc), adapters, pids, nv, cEng != IntPtr.Zero);
                sb.Append('}');
                lock (Gate) last = sb.ToString();
                Thread.Sleep(ms);
            }
        } catch (Exception e) {
            lock (Gate) { last = "{\"error\":\"" + Esc(e.Message) + "\"}"; worker = null; failed = DateTime.UtcNow; }
        } finally {
            if (q != IntPtr.Zero) PdhCloseQuery(q);
            if (nv != null) { try { nv.Shutdown(); } catch { } }
        }
    }

    // Grafikkarte: je Einheit (3D, Kopieren, Video …) die Summe aller Prozesse, die Karte so voll
    // wie ihre vollste Einheit (wie der Task-Manager). Gezeigt wird die Karte, auf der das Spiel
    // rechnet, sonst die meistbeschäftigte.
    static void Gpu(StringBuilder sb, Dictionary<string, double> eng, Dictionary<string, double> mem, Dictionary<string, double> proc,
            List<Adapter> adapters, int[] pids, Nv nv, bool counters) {
        var gameSet = new HashSet<int>(pids);
        var engAll = new Dictionary<string, double>();
        var engGame = new Dictionary<string, double>();
        foreach (var kv in eng) {
            // pid_1234_luid_0x00000000_0x0000C7A1_phys_0_eng_0_engtype_3D
            string[] t = kv.Key.Split('_');
            if (t.Length < 9 || t[0] != "pid" || t[2] != "luid") continue;
            string key = "luid_" + t[3] + "_" + t[4] + "|" + t[6] + "|" + t[8];
            Add(engAll, key, kv.Value);
            int pid;
            if (int.TryParse(t[1], NumberStyles.None, Inv, out pid) && gameSet.Contains(pid)) Add(engGame, key, kv.Value);
        }
        var use = Max(engAll);
        var useGame = Max(engGame);
        var vram = new Dictionary<string, double>();
        foreach (var kv in mem) {
            string[] t = kv.Key.Split('_');
            if (t.Length >= 3 && t[0] == "luid") Add(vram, "luid_" + t[1] + "_" + t[2], kv.Value);
        }
        var vramGame = new Dictionary<string, double>();
        foreach (var kv in proc) {
            string[] t = kv.Key.Split('_');
            int pid;
            if (t.Length >= 5 && t[0] == "pid" && t[2] == "luid" && int.TryParse(t[1], NumberStyles.None, Inv, out pid) && gameSet.Contains(pid))
                Add(vramGame, "luid_" + t[3] + "_" + t[4], kv.Value);
        }
        Put(sb, "gpu_counters", counters);
        string pick = null;
        double best = -1;
        foreach (var kv in useGame) if (kv.Value > best && Known(adapters, kv.Key)) { best = kv.Value; pick = kv.Key; }
        if (pick == null) {
            foreach (var kv in use) {
                double v = kv.Value * 1e12 + Get(vram, kv.Key);
                if (v > best && Known(adapters, kv.Key)) { best = v; pick = kv.Key; }
            }
        }
        if (pick == null) foreach (var a in adapters) if (a.Vram > best) { best = a.Vram; pick = a.Luid; }
        if (pick == null) return;
        Adapter ad = null;
        foreach (var a in adapters) if (string.Equals(a.Luid, pick, StringComparison.OrdinalIgnoreCase)) ad = a;
        if (counters) Put(sb, "gpu", Math.Min(100.0, Get(use, pick)));
        if (useGame.ContainsKey(pick)) Put(sb, "game_gpu", Math.Min(100.0, useGame[pick]));
        if (vram.ContainsKey(pick)) Put(sb, "vram_used", vram[pick]);
        if (vramGame.ContainsKey(pick)) Put(sb, "game_vram", vramGame[pick]);
        if (ad == null) return;
        sb.Append(",\"gpu_name\":\"").Append(Esc(ad.Name)).Append('"');
        Put(sb, "vendor", ad.Vendor);
        if (ad.Vram > 0) Put(sb, "vram_total", ad.Vram);
        if (nv != null && ad.Vendor == 0x10DE) {
            int idx = nv.Names.FindIndex(n => string.Equals(n, ad.Name.Trim(), StringComparison.OrdinalIgnoreCase));
            if (idx < 0 && nv.Devs.Count == 1) idx = 0;
            uint temp;
            if (idx >= 0 && nv.Temp(nv.Devs[idx], 0, out temp) == 0) Put(sb, "gpu_temp", temp);
        }
    }

    static bool Known(List<Adapter> adapters, string luid) {
        if (adapters.Count == 0) return true;
        foreach (var a in adapters) if (string.Equals(a.Luid, luid, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    static Dictionary<string, double> Max(Dictionary<string, double> engines) {
        var outp = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in engines) {
            string luid = kv.Key.Substring(0, kv.Key.IndexOf('|'));
            double old;
            if (!outp.TryGetValue(luid, out old) || kv.Value > old) outp[luid] = kv.Value;
        }
        return outp;
    }

    static void Add(Dictionary<string, double> d, string k, double v) { double o; d[k] = d.TryGetValue(k, out o) ? o + v : v; }
    static double Get(Dictionary<string, double> d, string k) { double o; return d.TryGetValue(k, out o) ? o : 0; }

    // Alle Instanzen eines Indikators mit Platzhalter: Name → Wert (gleiche Namen addiert).
    static Dictionary<string, double> Read(IntPtr counter) {
        var outp = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        if (counter == IntPtr.Zero) return outp;
        uint size = 0, count;
        if (PdhGetFormattedCounterArray(counter, FMT, ref size, out count, IntPtr.Zero) != MORE_DATA || size == 0 || size > 64 * 1024 * 1024) return outp;
        IntPtr buf = Marshal.AllocHGlobal((int)size);
        try {
            if (PdhGetFormattedCounterArray(counter, FMT, ref size, out count, buf) != 0) return outp;
            // PDH_FMT_COUNTERVALUE_ITEM_W: Name (Zeiger), Status bei 8, Wert (double) bei 16, 24 Bytes je Eintrag.
            for (int i = 0; i < count; i++) {
                IntPtr it = new IntPtr(buf.ToInt64() + i * 24L);
                int st = Marshal.ReadInt32(it, 8);
                if (st != 0 && st != 1) continue;
                string name = Marshal.PtrToStringUni(Marshal.ReadIntPtr(it, 0));
                double v = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(it, 16));
                if (name == null || double.IsNaN(v) || double.IsInfinity(v) || v < 0) continue;
                Add(outp, name, v);
            }
        } finally { Marshal.FreeHGlobal(buf); }
        return outp;
    }

    // Grafikkarten aus DXGI (ohne die Software-Karte): LUID wie in den Indikatoren, Name, Speicher.
    static List<Adapter> Adapters() {
        var list = new List<Adapter>();
        object fo = null;
        try {
            Guid iid = typeof(IFactory1).GUID;
            if (CreateDXGIFactory1(ref iid, out fo) != 0 || fo == null) return list;
            var f = (IFactory1)fo;
            for (uint i = 0; i < 16; i++) {
                IAdapter1 a;
                if (f.EnumAdapters1(i, out a) != 0 || a == null) break;
                AdapterDesc d;
                if (a.GetDesc1(out d) == 0 && (d.Flags & 2) == 0) {
                    var x = new Adapter();
                    x.Luid = string.Format(Inv, "luid_0x{0:X8}_0x{1:X8}", (uint)d.LuidHigh, d.LuidLow);
                    x.Name = d.Name ?? "";
                    x.Vram = (double)d.Dedicated.ToUInt64();
                    x.Vendor = d.Vendor;
                    list.Add(x);
                }
                Marshal.ReleaseComObject(a);
            }
        } catch { } finally { if (fo != null) { try { Marshal.ReleaseComObject(fo); } catch { } } }
        return list;
    }

    // nvml.dll nur von ihren festen Orten (Treiber in System32, sonst NVSMI), nur mit NVIDIA-Karte.
    static Nv NvOpen(List<Adapter> adapters) {
        if (!adapters.Exists(a => a.Vendor == 0x10DE)) return null;
        var paths = new List<string>();
        paths.Add(Path.Combine(Environment.SystemDirectory, "nvml.dll"));
        string pf = Environment.GetEnvironmentVariable("ProgramW6432");
        if (string.IsNullOrEmpty(pf)) pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (!string.IsNullOrEmpty(pf)) paths.Add(Path.Combine(pf, "NVIDIA Corporation\\NVSMI\\nvml.dll"));
        foreach (string p in paths) {
            if (!Path.IsPathRooted(p) || !File.Exists(p)) continue;
            // Abhängigkeiten nur aus dem Ordner der DLL und System32.
            IntPtr h = LoadLibraryEx(p, IntPtr.Zero, 0x00000100 | 0x00000800);
            if (h == IntPtr.Zero) continue;
            try {
                var init = Fn<NvVoid>(h, "nvmlInit_v2");
                var count = Fn<NvCount>(h, "nvmlDeviceGetCount_v2");
                var handle = Fn<NvHandle>(h, "nvmlDeviceGetHandleByIndex_v2");
                var name = Fn<NvName>(h, "nvmlDeviceGetName");
                var nv = new Nv();
                nv.Temp = Fn<NvTemp>(h, "nvmlDeviceGetTemperature");
                nv.Shutdown = Fn<NvVoid>(h, "nvmlShutdown");
                if (init == null || count == null || handle == null || name == null || nv.Temp == null || nv.Shutdown == null) continue;
                if (init() != 0) continue;
                uint n;
                if (count(out n) != 0) { nv.Shutdown(); continue; }
                for (uint i = 0; i < Math.Min(n, 8u); i++) {
                    IntPtr dev;
                    if (handle(i, out dev) != 0) continue;
                    var b = new byte[96];
                    string nm = name(dev, b, (uint)b.Length) == 0 ? Encoding.UTF8.GetString(b).TrimEnd('\0').Trim() : "";
                    nv.Devs.Add(dev);
                    nv.Names.Add(nm);
                }
                return nv;
            } catch { }
        }
        return null;
    }

    static T Fn<T>(IntPtr h, string name) where T : class {
        IntPtr p = GetProcAddress(h, name);
        return p == IntPtr.Zero ? null : Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }

    // --- Energieprofil ---

    // Profile von Windows und das aktive; can_set: Windows erlaubt diesem Benutzer das Umschalten.
    public static string Plans() {
        try {
            var sb = new StringBuilder("{\"ok\":true");
            IntPtr p;
            string active = "";
            if (PowerGetActiveScheme(IntPtr.Zero, out p) == 0 && p != IntPtr.Zero) {
                active = ((Guid)Marshal.PtrToStructure(p, typeof(Guid))).ToString("D");
                LocalFree(p);
            }
            sb.Append(",\"active\":\"").Append(active).Append('"');
            Put(sb, "can_set", PowerSettingAccessCheck(19, IntPtr.Zero) == 0);   // ACCESS_ACTIVE_SCHEME
            sb.Append(",\"plans\":[");
            var list = List();
            for (int i = 0; i < list.Count; i++) {
                if (i > 0) sb.Append(',');
                sb.Append("{\"id\":\"").Append(list[i].ToString("D")).Append("\",\"name\":\"").Append(Esc(Name(list[i]))).Append("\"}");
            }
            return sb.Append("]}").ToString();
        } catch (Exception e) { return "{\"ok\":false,\"error\":\"" + Esc(e.Message) + "\"}"; }
    }

    // Nur ein Profil, das Windows selbst aufzählt.
    public static string SetPlan(string id) {
        try {
            Guid g;
            if (!Guid.TryParse(id ?? "", out g) || !List().Contains(g)) return "{\"ok\":false,\"why\":\"id\"}";
            if (PowerSettingAccessCheck(19, IntPtr.Zero) != 0) return "{\"ok\":false,\"why\":\"denied\"}";
            uint r = PowerSetActiveScheme(IntPtr.Zero, ref g);
            if (r == 5) return "{\"ok\":false,\"why\":\"denied\"}";
            return r == 0 ? "{\"ok\":true}" : "{\"ok\":false,\"why\":\"" + r.ToString(Inv) + "\"}";
        } catch (Exception e) { return "{\"ok\":false,\"error\":\"" + Esc(e.Message) + "\"}"; }
    }

    // Energie (Einstellungen → System → Windows, src/core/win_einst.gd): Bildschirm aus, Schlafen
    // und Ruhezustand nach … im aktiven Profil, in Sekunden (0 = nie), am Netz (ac) und im
    // Akkubetrieb (dc), nur lesen. Umgestellt wird über powercfg mit festen Werten (power-time-set).
    static readonly Guid VideoSub = new Guid("7516b95f-f776-4464-8c53-06167f40cc99");
    static readonly Guid VideoIdle = new Guid("3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e");
    static readonly Guid SleepSub = new Guid("238c9fa8-0aad-41ed-83f4-97be242c8f20");
    static readonly Guid StandbyIdle = new Guid("29f6c1db-86da-48c5-9fdb-f2b67b1f44da");
    static readonly Guid HibernateIdle = new Guid("9d7815a6-7ee4-497e-8888-515a05f02364");

    static long Read(Guid scheme, Guid sub, Guid setting, bool ac) {
        uint v;
        uint r = ac ? PowerReadACValueIndex(IntPtr.Zero, ref scheme, ref sub, ref setting, out v) : PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref sub, ref setting, out v);
        return r == 0 ? (long)v : -1;
    }

    public static string Times() {
        try {
            IntPtr p;
            if (PowerGetActiveScheme(IntPtr.Zero, out p) != 0 || p == IntPtr.Zero) return "{\"ok\":false,\"why\":\"plan\"}";
            var g = (Guid)Marshal.PtrToStructure(p, typeof(Guid));
            LocalFree(p);
            var sb = new StringBuilder("{\"ok\":true");
            foreach (bool ac in new[] { true, false }) {
                sb.Append(ac ? ",\"ac\":{" : ",\"dc\":{");
                sb.Append("\"monitor\":").Append(Read(g, VideoSub, VideoIdle, ac).ToString(Inv));
                sb.Append(",\"sleep\":").Append(Read(g, SleepSub, StandbyIdle, ac).ToString(Inv));
                sb.Append(",\"hibernate\":").Append(Read(g, SleepSub, HibernateIdle, ac).ToString(Inv)).Append('}');
            }
            PowerStatus st;
            Put(sb, "battery", GetSystemPowerStatus(out st) && st.BatteryFlag != 128 && st.BatteryFlag != 255);
            var caps = new byte[256];
            // SYSTEM_POWER_CAPABILITIES: Byte 6 SystemS4 (Ruhezustand möglich), Byte 8 HiberFilePresent.
            Put(sb, "hibernate_ok", GetPwrCapabilities(caps) && caps[6] != 0 && caps[8] != 0);
            Put(sb, "can_set", PowerSettingAccessCheck(19, IntPtr.Zero) == 0);
            return sb.Append('}').ToString();
        } catch (Exception e) { return "{\"ok\":false,\"error\":\"" + Esc(e.Message) + "\"}"; }
    }

    // Akku des PCs (Kopfleiste und Schnellmenü auf Handhelds und Laptops, src/core/handheld.gd),
    // nur lesen. BatteryFlag 128 = kein Akku, 255 = unbekannt; Bit 8 = lädt.
    public static string Akku() {
        try {
            PowerStatus st;
            if (!GetSystemPowerStatus(out st)) return "{\"ok\":false}";
            var sb = new StringBuilder("{\"ok\":true");
            Put(sb, "akku", st.BatteryFlag != 128 && st.BatteryFlag != 255);
            Put(sb, "prozent", st.Percent == 255 ? -1.0 : (double)st.Percent);
            Put(sb, "netz", st.AcLine == 1);
            Put(sb, "laedt", st.BatteryFlag != 255 && (st.BatteryFlag & 8) != 0);
            Put(sb, "sparen", st.Saver == 1);
            Put(sb, "minuten", st.LifeTime < 0 ? -1.0 : (double)(st.LifeTime / 60));
            return sb.Append('}').ToString();
        } catch (Exception e) { return "{\"ok\":false,\"error\":\"" + Esc(e.Message) + "\"}"; }
    }

    static List<Guid> List() {
        var list = new List<Guid>();
        for (uint i = 0; i < 32; i++) {
            var b = new byte[16];
            uint sz = 16;
            if (PowerEnumerate(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 16, i, b, ref sz) != 0) break;   // ACCESS_SCHEME
            list.Add(new Guid(b));
        }
        return list;
    }

    static string Name(Guid g) {
        var b = new byte[512];
        uint sz = (uint)b.Length;
        if (PowerReadFriendlyName(IntPtr.Zero, ref g, IntPtr.Zero, IntPtr.Zero, b, ref sz) != 0 || sz < 2) return "";
        return Encoding.Unicode.GetString(b, 0, (int)Math.Min(sz, (uint)b.Length)).TrimEnd('\0');
    }

    // --- JSON ---

    static void Put(StringBuilder sb, string k, double v) {
        sb.Append(",\"").Append(k).Append("\":");
        sb.Append(double.IsNaN(v) || double.IsInfinity(v) ? "-1" : v.ToString("0.##", Inv));
    }
    static void Put(StringBuilder sb, string k, bool v) { sb.Append(",\"").Append(k).Append("\":").Append(v ? "true" : "false"); }

    static string Esc(string s) {
        var sb = new StringBuilder();
        foreach (char c in s ?? "") {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c < 0x20) sb.Append(' ');
            else sb.Append(c);
        }
        return sb.ToString();
    }
}
'@
$script:PerfReady = $false
function Use-Perf {
    if (-not $script:PerfReady) { Add-Type -TypeDefinition $script:PerfSrc; $script:PerfReady = $true }
}

# Discord-Knöpfe über UI Automation (siehe UzUia) – erst beim ersten Gebrauch übersetzt, damit ein
# Problem dort den restlichen Helfer nie mitreißt. Die Bibliotheken gehören zu .NET Framework
# (WPF) und liegen jedem Windows bei; referenziert über ihren echten Ort.
$script:UiaSrc = @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Windows.Automation;

// Knöpfe der Discord-App über die Bedienhilfe-Schnittstelle von Windows (UI Automation) – die
// offizielle Schnittstelle, über die auch Bildschirmleser bedienen. Nur lesen und „Aufrufen“
// (wie ein Klick), nichts wird umgestellt. Alles mit Zeitgrenze in eigenem Faden: Chromium baut
// seinen Baum erst auf, wenn jemand fragt, und große Bäume brauchen etwas.
public static class UzUia {
    static readonly object Gate = new object();
    static List<AutomationElement> cache = new List<AutomationElement>();

    static string Esc(string s) {
        if (s == null) return "";
        var sb = new StringBuilder(s.Length + 8);
        foreach (char c in s) {
            if (c == '"' || c == '\\') { sb.Append('\\').Append(c); }
            else if (c < 0x20) { sb.Append(' '); }
            else sb.Append(c);
        }
        return sb.ToString();
    }

    // Alle Knöpfe im Fenster: JSON {"done":..,"buttons":[{"i":0,"name":"..","enabled":true,"offscreen":false}],"error":".."}
    public static string Buttons(long hwnd, int budgetMs) {
        var found = new List<AutomationElement>();
        var rows = new List<string>();
        string err = "";
        bool done = false;
        var t = new System.Threading.Thread(delegate () {
            try {
                var root = AutomationElement.FromHandle(new IntPtr(hwnd));
                var all = root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button));
                int n = 0;
                foreach (AutomationElement e in all) {
                    if (n >= 400) break;
                    string name = "";
                    bool en = true, off = false;
                    try { name = e.Current.Name; en = e.Current.IsEnabled; off = e.Current.IsOffscreen; } catch { continue; }
                    if (string.IsNullOrEmpty(name)) continue;
                    lock (Gate) {
                        rows.Add("{\"i\":" + found.Count + ",\"name\":\"" + Esc(name) + "\",\"enabled\":" + (en ? "true" : "false") + ",\"offscreen\":" + (off ? "true" : "false") + "}");
                        found.Add(e);
                    }
                    n++;
                }
            } catch (Exception ex) { lock (Gate) { err = ex.Message; } }
            lock (Gate) { done = true; }
        });
        t.IsBackground = true;
        t.Start();
        t.Join(budgetMs);
        lock (Gate) {
            cache = new List<AutomationElement>(found);
            return "{\"done\":" + (done ? "true" : "false") + ",\"buttons\":[" + string.Join(",", rows.ToArray()) + "],\"error\":\"" + Esc(err) + "\"}";
        }
    }

    // Zu welchem Prozess gehört Knopf Nummer i (der Helfer prüft ihn vor dem Aufrufen)? 0 = weg/hängt.
    public static int ElementPid(int i, int budgetMs) {
        AutomationElement e = null;
        lock (Gate) { if (i >= 0 && i < cache.Count) e = cache[i]; }
        if (e == null) return 0;
        int pid = 0;
        var t = new System.Threading.Thread(delegate () {
            int r = 0;
            try { r = e.Current.ProcessId; } catch { r = 0; }
            lock (Gate) { pid = r; }
        });
        t.IsBackground = true;
        t.Start();
        t.Join(budgetMs);
        lock (Gate) { return pid; }
    }

    // Knopf Nummer i aus der letzten Liste aufrufen. "ok", "kein Aufruf", "weg", "hängt" oder der Fehler.
    public static string Invoke(int i, int budgetMs) {
        AutomationElement e = null;
        lock (Gate) { if (i >= 0 && i < cache.Count) e = cache[i]; }
        if (e == null) return "weg";
        string res = "hängt";
        var t = new System.Threading.Thread(delegate () {
            string r;
            try {
                object p;
                if (e.TryGetCurrentPattern(InvokePattern.Pattern, out p)) { ((InvokePattern)p).Invoke(); r = "ok"; }
                else r = "kein Aufruf";
            } catch (Exception ex) { r = ex.Message; }
            lock (Gate) { res = r; }
        });
        t.IsBackground = true;
        t.Start();
        t.Join(budgetMs);
        lock (Gate) { return res; }
    }
}

'@

function Use-Uia {
    if ($script:UiaReady) { return }
    Add-Type -AssemblyName WindowsBase, UIAutomationTypes, UIAutomationClient
    $refs = @([System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location, [System.Windows.Rect].Assembly.Location)
    Add-Type -TypeDefinition $script:UiaSrc -ReferencedAssemblies $refs
    $script:UiaReady = $true
}

# Spotify am PC über die Bedienhilfe von Windows (UI Automation), wie ein Bildschirmleser: Uzai liest,
# was das Spotify-Fenster zeigt (linke Bibliothek, „Zuletzt gespielt“ auf der Startseite, sichtbare
# Suchergebnisse – Namen und, wo Spotify sie als Kennung der Zeile nennt, die Spotify-Adresse
# „spotify:playlist:…“), und „ruft“ genau einen Abspiel-Knopf dieses Fensters „auf“ (Invoke-Muster).
# Die Bibliothek ist eine virtuelle Liste (nur die sichtbaren Zeilen stehen im Baum): Zum vollständigen
# Lesen blättert der Helfer sie über das Bildlauf-Muster (ScrollPattern) durch – ohne Fokus, ohne
# Tasten, ohne Mausrad – und stellt die Stelle danach wieder her. Chromium zeichnet ein verdecktes
# oder minimiertes Fenster nicht neu; dafür legt der Helfer das Fenster kurz fast durchsichtig und
# klickdurchlässig an den rechten Bildschirmrand (nur 2 Punkte im Bild, nie aktiviert) und danach
# wieder zurück (UzSpotFenster). Keine Tastendrücke, keine Mausklicks, keine globalen Eingaben; kein
# Debug-Port, keine DLL, kein Zugriff auf Spotifys Speicher, Cache oder Anmeldung. Drei Teile: die
# Regeln (UzSpotRegeln, ohne UI Automation, unter Linux prüfbar), das Lesen (UzSpot.UzSpotUi) und das
# Fenster zum Lesen (UzSpot.UzSpotFenster).
$script:SpotRegelnSrc = @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Text.RegularExpressions;

public static class UzSpotRegeln {
    public const int MaxItems = 600;
    public const int NameMax = 120;
    public const int MaxNodesHard = 30000;
    public const int MaxDepthHard = 64;
    public const int BudgetHard = 20000;

    public static int Clamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

    // Text aus dem fremden Fenster: ohne Steuer- und Richtungszeichen, Leerraum zusammengezogen, gekürzt.
    public static string Clean(string s, int max) {
        if (string.IsNullOrEmpty(s)) return "";
        if (s.Length > max * 4) s = s.Substring(0, max * 4);
        var sb = new StringBuilder(s.Length);
        bool sp = false;
        foreach (char c in s) {
            bool bad = c < 0x20 || c == 0x7F || (c >= 0x80 && c < 0xA0) || (c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069) || c == 0xFEFF;
            if (bad || char.IsWhiteSpace(c)) { if (!sp && sb.Length > 0) { sb.Append(' '); sp = true; } continue; }
            sb.Append(c);
            sp = false;
        }
        string o = sb.ToString().Trim();
        if (o.Length > max) o = o.Substring(0, max).Trim();
        return o;
    }

    // Abschnitt nach seinem Namen (aria-label bzw. Überschrift): "lib", "recent", "search" oder "".
    public static string Section(string name) {
        string n = Clean(name, 60).ToLowerInvariant();
        if (n == "") return "";
        foreach (string x in new string[] { "your library", "deine bibliothek", "bibliothek", "library", "votre bibliothèque", "tu biblioteca" }) if (n == x) return "lib";
        foreach (string x in new string[] { "recently played", "zuletzt gespielt", "zuletzt gehört", "jump back in", "récemment écoutés", "escuchado recientemente" }) if (n == x) return "recent";
        foreach (string x in new string[] { "top result", "top-ergebnis", "search results", "suchergebnisse" }) if (n == x) return "search";
        return "";
    }

    static readonly Regex[] Play = new Regex[] {
        new Regex(@"^Play (.+)$"), new Regex(@"^(.+) abspielen$"), new Regex(@"^Lire (.+)$"), new Regex(@"^Reproducir (.+)$"),
        new Regex(@"^Riproduci (.+)$"), new Regex(@"^(.+) afspelen$"), new Regex(@"^Tocar (.+)$"), new Regex(@"^Odtwórz (.+)$")
    };

    // Name dessen, was ein Abspiel-Knopf spielt („Play Discover Weekly“, „Dein Mix der Woche abspielen“),
    // sonst "". Der große Knopf „Abspielen“ der Wiedergabeleiste hat keinen Namen dahinter.
    public static string PlayTarget(string name) {
        string n = Clean(name, 600);
        if (n.Length < 2) return "";
        foreach (Regex r in Play) {
            Match m = r.Match(n);
            if (m.Success) {
                string x = Clean(m.Groups[1].Value, NameMax);
                return x.Length >= 1 ? x : "";
            }
        }
        return "";
    }

    // Art aus der Zeile daneben („Playlist • Robin“, „Album • Koji Kondo“, „Künstler“).
    public static string Kind(string row) {
        string r = Clean(row, 200).ToLowerInvariant();
        if (r.Contains("playlist")) return "playlist";
        if (r.Contains("album") || r.Contains("single") || r.Contains(" ep")) return "album";
        if (r.Contains("künstler") || r.Contains("artist") || r.Contains("interpret")) return "artist";
        if (r.Contains("podcast") || r.Contains("folge") || r.Contains("episode")) return "show";
        return "";
    }

    // Was in der Zeile außer dem Namen steht (Unterzeile der Kachel), ohne den Namen selbst.
    public static string Sub(string row, string name) {
        string r = Clean(row, 200);
        if (r == "" || r == name) return "";
        int at = r.IndexOf(name, StringComparison.Ordinal);
        if (at >= 0) r = (r.Substring(0, at) + " " + r.Substring(at + name.Length)).Trim();
        r = r.Trim(new char[] { ' ', '•', '·', ',', '-' });
        return Clean(r, 80);
    }

    // Spotify-Adressen: nur diese Muster, sonst "". Die Kennung (HTML-id) einer Zeile der Bibliothek
    // heißt etwa „listrow-title-spotify:playlist:37i9dQZF1DXcBWIGoYBM5M“; Lieblingssongs sind
    // „spotify:user:<name>:collection“. Ein Link (Wert des Value-Musters) zeigt auf „…/playlist/<id>“.
    static readonly Regex UriRe = new Regex(@"spotify:(playlist|album|artist|show):[A-Za-z0-9]{22}(?![A-Za-z0-9])");
    static readonly Regex CollRe = new Regex(@"spotify:user:[A-Za-z0-9._-]{1,64}:collection(?![A-Za-z0-9._:-])");
    static readonly Regex LinkRe = new Regex(@"^https://[a-z0-9.-]{1,64}/(playlist|album|artist|show)/([A-Za-z0-9]{22})(?:[/?#]|$)");

    public static string UriAusId(string id) {
        if (string.IsNullOrEmpty(id) || id.Length > 300) return "";
        Match m = UriRe.Match(id);
        if (m.Success) return m.Value;
        m = CollRe.Match(id);
        return m.Success ? m.Value : "";
    }

    public static string UriAusLink(string url) {
        if (string.IsNullOrEmpty(url) || url.Length > 300) return "";
        Match m = LinkRe.Match(url);
        return m.Success ? "spotify:" + m.Groups[1].Value + ":" + m.Groups[2].Value : "";
    }

    // Art aus der Adresse ("playlist", "album", "artist", "show"); Lieblingssongs gelten als Playlist.
    public static string UriKind(string uri) {
        if (string.IsNullOrEmpty(uri)) return "";
        if (uri.EndsWith(":collection", StringComparison.Ordinal)) return "playlist";
        string[] p = uri.Split(':');
        return p.Length == 3 ? p[1] : "";
    }

    public static bool TitelId(string id) { return id != null && id.StartsWith("listrow-title-", StringComparison.Ordinal); }
    public static bool UnterId(string id) { return id != null && id.StartsWith("listrow-subtitle-", StringComparison.Ordinal); }

    // Nächste Stelle beim Blättern (Prozent): knapp eine Seite weiter (Überlappung, damit keine Zeile
    // fehlt), mindestens 2 Prozentpunkte, höchstens 100.
    public static double Weiter(double cur, double view) {
        if (double.IsNaN(cur) || cur < 0) cur = 0;
        double step = (double.IsNaN(view) || view <= 0 || view > 100) ? 10 : view * 0.8;
        if (step < 2) step = 2;
        double n = cur + step;
        return n > 100 ? 100 : n;
    }

    // Wohin das Fenster zum Lesen kommt: an den rechten Rand des Bildschirms, auf dem Uzai liegt (mon*),
    // nur 2 Punkte im Bild; so hoch wie der Bildschirm (viele Zeilen je Schritt), mindestens 1000 breit
    // (sonst klappt Spotify die Bibliothek zu). In Workspace-Koordinaten (SetWindowPlacement): ox/oy ist
    // die linke obere Ecke des Arbeitsbereichs des Hauptbildschirms. { links, oben, rechts, unten }.
    public static int[] Streifen(int monL, int monT, int monR, int monB, int w, int ox, int oy) {
        int mw = monR - monL, mh = monB - monT;
        if (mw < 200 || mh < 200) return new int[0];
        if (w < 1000) w = 1000;
        if (w > mw) w = mw;
        int x = monR - 2, y = monT;
        return new int[] { x - ox, y - oy, x - ox + w, y - oy + mh };
    }

    static string Esc(string s) {
        var sb = new StringBuilder(s.Length + 8);
        foreach (char c in s) {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c < 0x20) sb.Append(' ');
            else sb.Append(c);
        }
        return sb.ToString();
    }

    // Ein gefundener Eintrag als JSON (nur geprüfte Texte; uri nur im Muster oben, sonst leer).
    public static string ItemJson(int i, string sec, string name, string sub, string kind, string uri) {
        string u = (UriAusId(uri) == uri) ? uri : "";
        return "{\"i\":" + i + ",\"sec\":\"" + Esc(sec) + "\",\"name\":\"" + Esc(Clean(name, NameMax)) + "\",\"sub\":\"" + Esc(Clean(sub, 80)) + "\",\"kind\":\"" + Esc(kind)
            + "\",\"uri\":\"" + Esc(u) + "\"}";
    }

    public static string Quote(string s) { return "\"" + Esc(s ?? "") + "\""; }
}
'@

$script:SpotUiSrc = @'
namespace UzSpot {
    using System;
    using System.Text;
    using System.Threading;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    using System.Windows.Automation;

    public static class UzSpotUi {
        static readonly object Gate = new object();
        static List<AutomationElement> cache = new List<AutomationElement>();
        static List<string> names = new List<string>();

        class Item {
            public string Sec, Name, Row;
            public int[] Rows;
            public AutomationElement El;
        }

        class St {
            public Stopwatch W;
            public int Budget, MaxNodes, MaxDepth, Nodes, NoButton, RowSerial, Steps, Pause;
            public bool Cut, Voll, Suche, Ende, Halt, Blatt;
            public List<Item> Items = new List<Item>();
            public HashSet<string> Seen = new HashSet<string>();
            public Dictionary<int, string> RowUri = new Dictionary<int, string>();
            public HashSet<int> RowMulti = new HashSet<int>();
            public Dictionary<string, string[]> Titel = new Dictionary<string, string[]>();
            public List<string> TitelOrder = new List<string>();
            public Dictionary<string, string> Unter = new Dictionary<string, string>();
            public List<AutomationElement> Scroller = new List<AutomationElement>();
            public List<int> ScrollHits = new List<int>();
            public bool Stop() {
                if (Halt || Nodes >= MaxNodes || Items.Count >= UzSpotRegeln.MaxItems || TitelOrder.Count >= UzSpotRegeln.MaxItems || W.ElapsedMilliseconds > Budget) { Cut = true; return true; }
                return false;
            }
        }

        static bool IsRow(ControlType t) {
            return t == ControlType.ListItem || t == ControlType.DataItem || t == ControlType.TreeItem || t == ControlType.Group || t == ControlType.Custom;
        }

        static bool MayScroll(ControlType t) {
            return t == ControlType.Group || t == ControlType.Pane || t == ControlType.Custom || t == ControlType.List || t == ControlType.DataGrid || t == ControlType.Table || t == ControlType.Tree;
        }

        // Adresse eines Links (Value-Muster), sonst "".
        static string LinkUri(AutomationElement e) {
            try {
                object p;
                if (e.TryGetCurrentPattern(ValuePattern.Pattern, out p)) return UzSpotRegeln.UriAusLink(((ValuePattern)p).Current.Value);
            } catch { }
            return "";
        }

        // Adresse für alle Zeilen, in denen dieser Knoten liegt; zwei verschiedene in derselben Zeile:
        // die Zeile ist ein Sammelbehälter und bekommt keine.
        static void NoteUri(List<int> rows, string uri, St st) {
            foreach (int r in rows) {
                string had;
                if (st.RowUri.TryGetValue(r, out had)) { if (had != uri) st.RowMulti.Add(r); }
                else st.RowUri[r] = uri;
            }
        }

        // Bildlauf-fähig und senkrecht verschiebbar? Dann die Nummer in st.Scroller, sonst -1.
        static int Scrollbar(AutomationElement e, St st) {
            try {
                object v = e.GetCurrentPropertyValue(AutomationElement.IsScrollPatternAvailableProperty);
                if (!(v is bool) || !(bool)v) return -1;
                object p;
                if (!e.TryGetCurrentPattern(ScrollPattern.Pattern, out p)) return -1;
                if (!((ScrollPattern)p).Current.VerticallyScrollable) return -1;
            } catch { return -1; }
            st.Scroller.Add(e);
            st.ScrollHits.Add(0);
            return st.Scroller.Count - 1;
        }

        // Kinder von el durchgehen (Tiefe begrenzt). sec: Abschnitt von außen; row: Text der nächsten
        // Zeile darüber; rows: Nummern der Zeilen darüber (für die Adresse); scr: nächster Behälter mit
        // Bildlauf darüber. Gibt einen Abschnittsnamen zurück, den dieser Teilbaum als Überschrift trägt
        // (dann gilt er für die folgenden Geschwister), sonst "".
        static string Walk(TreeWalker tw, AutomationElement el, int depth, string sec, string row, List<int> rows, int scr, St st) {
            if (depth >= st.MaxDepth) return "";
            string cur = sec;
            string head = "";
            AutomationElement ch = null;
            try { ch = tw.GetFirstChild(el); } catch { ch = null; }
            while (ch != null && !st.Stop()) {
                st.Nodes++;
                string name = "";
                ControlType type = null;
                try { name = ch.Current.Name; type = ch.Current.ControlType; } catch { name = ""; type = null; }
                string label = UzSpotRegeln.Section(name);
                string mine = cur;
                if (label != "") {
                    if (type != null && IsRow(type)) mine = label; else { cur = label; mine = label; if (head == "") head = label; }
                }
                bool isRow = type != null && IsRow(type) && !string.IsNullOrEmpty(name);
                string nrow = isRow ? name : row;
                bool pushed = false;
                if (isRow && label == "") { st.RowSerial++; rows.Add(st.RowSerial); pushed = true; }
                int myScr = scr;
                if (mine != "") {
                    string aid = "";
                    try { aid = ch.Current.AutomationId; } catch { aid = ""; }
                    string uri = UzSpotRegeln.UriAusId(aid);
                    if (uri == "" && type == ControlType.Hyperlink) uri = LinkUri(ch);
                    if (uri != "") {
                        NoteUri(rows, uri, st);
                        string key = mine + "|" + uri;
                        if (UzSpotRegeln.TitelId(aid) && !st.Titel.ContainsKey(key)) {
                            string t = UzSpotRegeln.Clean(name, UzSpotRegeln.NameMax);
                            if (t != "") {
                                st.Titel[key] = new string[] { mine, t, uri };
                                st.TitelOrder.Add(key);
                                if (mine == "lib" && scr >= 0) st.ScrollHits[scr]++;
                            }
                        } else if (UzSpotRegeln.UnterId(aid) && !st.Unter.ContainsKey(uri)) {
                            st.Unter[uri] = UzSpotRegeln.Clean(name, 80);
                        }
                    }
                    if (st.Suche && mine == "lib" && type != null && MayScroll(type)) {
                        int k = Scrollbar(ch, st);
                        if (k >= 0) myScr = k;
                    }
                }
                if (type == ControlType.Button) {
                    string x = UzSpotRegeln.PlayTarget(name);
                    if (x != "" && mine != "") {
                        string key = mine + "|" + x;
                        if (!st.Seen.Contains(key)) {
                            st.Seen.Add(key);
                            var it = new Item();
                            it.Sec = mine;
                            it.Name = x;
                            it.Row = nrow;
                            it.Rows = rows.ToArray();
                            it.El = ch;
                            st.Items.Add(it);
                            if (mine == "lib" && myScr >= 0) st.ScrollHits[myScr]++;
                        }
                    }
                }
                int before = st.Items.Count;
                string got = Walk(tw, ch, depth + 1, mine, nrow, rows, myScr, st);
                // Zeilen der Bibliothek ohne Abspiel-Knopf (fürs Protokoll: zeigt Spotify sie anders?)
                if (!st.Blatt && mine == "lib" && type != null && (type == ControlType.ListItem || type == ControlType.TreeItem) && !string.IsNullOrEmpty(name) && st.Items.Count == before) st.NoButton++;
                if (got != "" && st.Items.Count == before && label == "") { cur = got; if (head == "") head = got; }
                if (pushed) rows.RemoveAt(rows.Count - 1);
                AutomationElement nx = null;
                try { nx = tw.GetNextSibling(ch); } catch { nx = null; }
                ch = nx;
            }
            return head;
        }

        static bool Gehe(ScrollPattern sp, double pos) {
            try { sp.SetScrollPercent(ScrollPattern.NoScroll, pos); return true; } catch { return false; }
        }

        // Die Bibliothek ganz durchblättern: der Behälter mit Bildlauf, in dem die meisten Einträge der
        // Bibliothek liegen, Seite für Seite; nach jedem Schritt nur ihn neu lesen. Danach die alte Stelle.
        static void Blaettern(TreeWalker tw, St st) {
            int best = -1, hits = 0;
            for (int k = 0; k < st.Scroller.Count; k++) if (st.ScrollHits[k] > hits) { hits = st.ScrollHits[k]; best = k; }
            if (best < 0) return;
            AutomationElement el = st.Scroller[best];
            ScrollPattern sp;
            double orig, view;
            try {
                object p;
                if (!el.TryGetCurrentPattern(ScrollPattern.Pattern, out p)) return;
                sp = (ScrollPattern)p;
                orig = sp.Current.VerticalScrollPercent;
                view = sp.Current.VerticalViewSize;
            } catch { return; }
            st.Blatt = true;
            st.Suche = false;
            double pos = 0;
            if (orig > 0.5) {
                if (!Gehe(sp, 0)) return;
                Thread.Sleep(st.Pause);
                Walk(tw, el, 0, "lib", "", new List<int>(), -1, st);
            }
            int idle = 0;
            while (!st.Stop() && st.Steps < 150) {
                pos = UzSpotRegeln.Weiter(pos, view);
                if (!Gehe(sp, pos)) break;
                st.Steps++;
                Thread.Sleep(st.Pause);
                int n0 = st.Items.Count + st.TitelOrder.Count;
                Walk(tw, el, 0, "lib", "", new List<int>(), -1, st);
                idle = (st.Items.Count + st.TitelOrder.Count == n0) ? idle + 1 : 0;
                double now = pos;
                try { now = sp.Current.VerticalScrollPercent; view = sp.Current.VerticalViewSize; } catch { }
                if (pos >= 100 || now >= 99.5) { st.Ende = true; break; }
                if (idle >= 4) break;
                if (now > pos) pos = now;
            }
            Gehe(sp, orig < 0 ? 0 : orig);
        }

        static string ResolveUri(int[] rows, St st) {
            for (int j = rows.Length - 1; j >= 0; j--) {
                if (st.RowMulti.Contains(rows[j])) return "";
                string u;
                if (st.RowUri.TryGetValue(rows[j], out u)) return u;
            }
            return "";
        }

        // Liest das Fenster: JSON {"done":..,"cut":..,"nodes":..,"items":[..],"secs":{..},"nobutton":..,
        // "steps":..,"ende":..,"uris":..,"error":".."}. voll: die Bibliothek ganz durchblättern.
        public static string Read(long hwnd, int budgetMs, int maxNodes, int maxDepth, bool voll, int pauseMs) {
            var st = new St();
            st.Budget = UzSpotRegeln.Clamp(budgetMs, 500, UzSpotRegeln.BudgetHard);
            st.MaxNodes = UzSpotRegeln.Clamp(maxNodes, 200, UzSpotRegeln.MaxNodesHard);
            st.MaxDepth = UzSpotRegeln.Clamp(maxDepth, 8, UzSpotRegeln.MaxDepthHard);
            st.Pause = UzSpotRegeln.Clamp(pauseMs, 20, 1000);
            st.Voll = voll;
            st.Suche = voll;
            string err = "";
            bool done = false;
            st.W = Stopwatch.StartNew();
            var t = new Thread(delegate () {
                try {
                    var root = AutomationElement.FromHandle(new IntPtr(hwnd));
                    Walk(TreeWalker.ControlViewWalker, root, 0, "", "", new List<int>(), -1, st);
                    if (st.Voll) Blaettern(TreeWalker.ControlViewWalker, st);
                } catch (Exception ex) { lock (Gate) { err = ex.GetType().Name; } }
                lock (Gate) { done = true; }
            });
            t.IsBackground = true;
            t.Start();
            if (!t.Join(st.Budget + 2000)) { st.Halt = true; t.Join(1500); }
            lock (Gate) {
                var rows = new List<string>();
                var els = new List<AutomationElement>();
                var nms = new List<string>();
                var secs = new Dictionary<string, int>();
                var had = new HashSet<string>();
                int uris = 0;
                try {
                    var items = new List<Item>(st.Items);
                    foreach (Item it in items) {
                        if (els.Count >= UzSpotRegeln.MaxItems) { st.Cut = true; break; }
                        string uri = ResolveUri(it.Rows, st);
                        if (uri != "" && had.Contains(it.Sec + "|" + uri)) uri = "";
                        if (uri != "") { had.Add(it.Sec + "|" + uri); uris++; }
                        string sub = UzSpotRegeln.Sub(it.Row, it.Name);
                        string u2;
                        if (uri != "" && st.Unter.TryGetValue(uri, out u2) && u2 != "") sub = u2;
                        string kind = uri != "" ? UzSpotRegeln.UriKind(uri) : UzSpotRegeln.Kind(it.Row);
                        rows.Add(UzSpotRegeln.ItemJson(els.Count, it.Sec, it.Name, sub, kind, uri));
                        els.Add(it.El);
                        nms.Add(it.Name);
                        int n0;
                        secs.TryGetValue(it.Sec, out n0);
                        secs[it.Sec] = n0 + 1;
                    }
                    // Zeilen mit Adresse, aber ohne Abspiel-Knopf (Spotify zeigt ihn nur beim Darüberfahren):
                    // abspielbar über Spotify Connect, nicht über das Fenster.
                    foreach (string key in new List<string>(st.TitelOrder)) {
                        if (els.Count >= UzSpotRegeln.MaxItems) { st.Cut = true; break; }
                        string[] tt = st.Titel[key];
                        if (had.Contains(key) || st.Seen.Contains(tt[0] + "|" + tt[1])) continue;
                        had.Add(key);
                        uris++;
                        string sub = "";
                        st.Unter.TryGetValue(tt[2], out sub);
                        rows.Add(UzSpotRegeln.ItemJson(els.Count, tt[0], tt[1], sub ?? "", UzSpotRegeln.UriKind(tt[2]), tt[2]));
                        els.Add(null);
                        nms.Add(tt[1]);
                        int n0;
                        secs.TryGetValue(tt[0], out n0);
                        secs[tt[0]] = n0 + 1;
                    }
                } catch (Exception ex) { if (err == "") err = ex.GetType().Name; }
                cache = els;
                names = nms;
                var sl = new List<string>();
                foreach (KeyValuePair<string, int> kv in secs) sl.Add(UzSpotRegeln.Quote(kv.Key) + ":" + kv.Value);
                return "{\"done\":" + (done ? "true" : "false") + ",\"cut\":" + (st.Cut ? "true" : "false") + ",\"nodes\":" + st.Nodes + ",\"nobutton\":" + st.NoButton
                    + ",\"steps\":" + st.Steps + ",\"ende\":" + (st.Ende ? "true" : "false") + ",\"uris\":" + uris + ",\"scroller\":" + st.Scroller.Count
                    + ",\"items\":[" + string.Join(",", rows.ToArray()) + "],\"secs\":{" + string.Join(",", sl.ToArray()) + "},\"error\":" + UzSpotRegeln.Quote(err) + "}";
            }
        }

        // Eintrag i aus der letzten Liste abspielen – nur, wenn der Knopf noch denselben Namen trägt
        // und zum erwarteten Prozess gehört. "ok", "weg", "anders", "fremd", "kein Aufruf", "hängt".
        public static string Invoke(int i, string want, int pid, int budgetMs) {
            AutomationElement e = null;
            string nm = "";
            lock (Gate) { if (i >= 0 && i < cache.Count) { e = cache[i]; nm = names[i]; } }
            if (e == null) return "weg";
            if (nm != UzSpotRegeln.Clean(want, UzSpotRegeln.NameMax)) return "anders";
            string res = "hängt";
            var t = new Thread(delegate () {
                string r;
                try {
                    if (e.Current.ProcessId != pid) r = "fremd";
                    else if (UzSpotRegeln.PlayTarget(e.Current.Name) != nm) r = "anders";
                    else {
                        object p;
                        if (e.TryGetCurrentPattern(InvokePattern.Pattern, out p)) { ((InvokePattern)p).Invoke(); r = "ok"; }
                        else r = "kein Aufruf";
                    }
                } catch (Exception ex) { r = ex.GetType().Name; }
                lock (Gate) { res = r; }
            });
            t.IsBackground = true;
            t.Start();
            t.Join(UzSpotRegeln.Clamp(budgetMs, 500, 5000));
            lock (Gate) { return res; }
        }
    }

    // Das Spotify-Fenster zum Lesen bereitlegen und wieder zurück. Chromium zeichnet ein minimiertes oder
    // ganz verdecktes Fenster nicht neu – dann rückt die virtuelle Liste beim Blättern nicht nach. Darum
    // für die Dauer des Lesens: fast durchsichtig (Deckkraft 1/255) und klickdurchlässig, ohne Aktivierung
    // wiederhergestellt, an den rechten Rand des Bildschirms von Uzai (2 Punkte im Bild) und über Uzai in
    // der Reihenfolge. Danach: wieder minimiert (war es maximiert, kommt es später maximiert zurück) bzw.
    // an die alte Stelle hinter Uzai, Stil und Deckkraft wie vorher. Eine Markierung am Fenster (SetProp)
    // sorgt dafür, dass auch ein abgebrochenes Lesen beim nächsten Mal aufgeräumt wird. Nie aktiviert,
    // nie in den Vordergrund geholt, keine Eingaben.
    public static class UzSpotFenster {
        [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)] public struct RC { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] public struct WP { public int length, flags, showCmd; public PT ptMin, ptMax; public RC rc; }
        [StructLayout(LayoutKind.Sequential)] public struct MI { public int cbSize; public RC rcMonitor, rcWork; public int dwFlags; }

        [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h, ref WP wp);
        [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr h, ref WP wp);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
        [DllImport("user32.dll")] static extern bool GetLayeredWindowAttributes(IntPtr h, out uint key, out byte alpha, out uint flags);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
        [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr mon, ref MI mi);
        [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint p, ref RC r, uint ini);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool SetProp(IntPtr h, string name, IntPtr v);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetProp(IntPtr h, string name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr RemoveProp(IntPtr h, string name);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);

        const int GWL_EXSTYLE = -20;
        const int EX_TOPMOST = 0x8, EX_TRANSPARENT = 0x20, EX_LAYERED = 0x80000;
        const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOACTIVATE = 0x10, SWP_NOOWNERZORDER = 0x200;
        const int SW_SHOWMINIMIZED = 2, SW_SHOWMAXIMIZED = 3, SW_SHOWNOACTIVATE = 4, SW_MINIMIZE = 6, SW_SHOWMINNOACTIVE = 7;
        const string Mark = "UzaiSpotLesen", MarkEx = "UzaiSpotStil";

        static IntPtr cur = IntPtr.Zero;
        static WP orig;
        static int origEx;
        static bool hadLayer;
        static uint oKey, oFlags;
        static byte oAlpha;

        // Bereitlegen. fg: das Fenster von Uzai (für Bildschirm und Reihenfolge). "" = bereit, sonst der Grund.
        public static string Bereit(IntPtr h, IntPtr fg) {
            Zurueck(h);
            if (h == IntPtr.Zero || !IsWindow(h)) return "kein Fenster";
            var wp = new WP();
            wp.length = Marshal.SizeOf(typeof(WP));
            if (!GetWindowPlacement(h, ref wp)) return "keine Lage";
            var mi = new MI();
            mi.cbSize = Marshal.SizeOf(typeof(MI));
            if (!GetMonitorInfo(MonitorFromWindow(fg != IntPtr.Zero ? fg : h, 2), ref mi)) return "kein Bildschirm";
            var work = new RC();
            SystemParametersInfo(0x30, 0, ref work, 0);
            int[] r = UzSpotRegeln.Streifen(mi.rcMonitor.Left, mi.rcMonitor.Top, mi.rcMonitor.Right, mi.rcMonitor.Bottom, wp.rc.Right - wp.rc.Left, work.Left, work.Top);
            if (r.Length != 4) return "kein Bildschirm";
            orig = wp;
            origEx = GetWindowLong(h, GWL_EXSTYLE);
            hadLayer = (origEx & EX_LAYERED) != 0;
            if (hadLayer && !GetLayeredWindowAttributes(h, out oKey, out oAlpha, out oFlags)) { oKey = 0; oAlpha = 255; oFlags = 2; }
            cur = h;
            SetProp(h, MarkEx, new IntPtr(origEx));
            SetProp(h, Mark, new IntPtr(1));
            SetWindowLong(h, GWL_EXSTYLE, origEx | EX_LAYERED | EX_TRANSPARENT);
            SetLayeredWindowAttributes(h, 0, 1, 2);
            var nw = wp;
            nw.flags = 0;
            nw.showCmd = SW_SHOWNOACTIVATE;
            nw.rc.Left = r[0]; nw.rc.Top = r[1]; nw.rc.Right = r[2]; nw.rc.Bottom = r[3];
            SetWindowPlacement(h, ref nw);
            bool top = fg != IntPtr.Zero && (GetWindowLong(fg, GWL_EXSTYLE) & EX_TOPMOST) != 0;
            SetWindowPos(h, new IntPtr(top ? -1 : 0), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
            return "";
        }

        // Zurücklegen, falls das Fenster die Markierung trägt (auch nach einem abgebrochenen Lesen).
        // "" = nichts zu tun, "zurück" = zurückgelegt.
        public static string Zurueck(IntPtr h) {
            if (h == IntPtr.Zero || !IsWindow(h)) { if (h == cur) cur = IntPtr.Zero; return ""; }
            if (GetProp(h, Mark) == IntPtr.Zero) return "";
            bool known = h == cur;
            SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
            var wp = new WP();
            wp.length = Marshal.SizeOf(typeof(WP));
            bool minimize = true;
            if (known) {
                wp = orig;
                bool wasMax = orig.showCmd == SW_SHOWMAXIMIZED;
                minimize = wasMax || orig.showCmd == SW_SHOWMINIMIZED || orig.showCmd == SW_SHOWMINNOACTIVE || orig.showCmd == SW_MINIMIZE;
                if (wasMax) wp.flags |= 2;
            } else {
                GetWindowPlacement(h, ref wp);
            }
            wp.showCmd = minimize ? SW_SHOWMINNOACTIVE : SW_SHOWNOACTIVATE;
            SetWindowPlacement(h, ref wp);
            if (!minimize) SetWindowPos(h, new IntPtr(1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
            // Erst nach dem Minimieren wieder deckend (sonst wäre es einen Augenblick zu sehen).
            Thread.Sleep(250);
            int ex = known ? origEx : GetProp(h, MarkEx).ToInt32();
            SetWindowLong(h, GWL_EXSTYLE, ex);
            if ((ex & EX_LAYERED) != 0) {
                if (known && hadLayer) SetLayeredWindowAttributes(h, oKey, oAlpha, oFlags);
                else SetLayeredWindowAttributes(h, 0, 255, 2);
            }
            RemoveProp(h, Mark);
            RemoveProp(h, MarkEx);
            if (known) cur = IntPtr.Zero;
            return "zurück";
        }
    }
}
'@

function Use-SpotUi {
    if ($script:SpotUiReady) { return }
    Add-Type -AssemblyName WindowsBase, UIAutomationTypes, UIAutomationClient
    $refs = @([System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location, [System.Windows.Rect].Assembly.Location)
    Add-Type -TypeDefinition ($script:SpotRegelnSrc + "`n" + $script:SpotUiSrc) -ReferencedAssemblies $refs
    $script:SpotUiReady = $true
}

# Das Hauptfenster der Spotify-App (sichtbar, mit Titel, das größte) – nur, wenn Prozessname und
# Pfad zur Spotify-App gehören (Test-AppWindow 'spotify'). Auch minimiert (min = $true): Gelesen wird
# trotzdem, beim vollständigen Lesen kurz unsichtbar bereitgelegt (UzSpotFenster).
# @{ ok; hwnd; pid; min } bzw. @{ ok = $false; why }.
function Find-SpotifyWindow {
    $pids = @(Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })
    if ($pids.Count -eq 0) { return @{ ok = $false; why = 'läuft nicht' } }
    $best = [UzWin]::Best([int[]]$pids)
    if ($best -eq [IntPtr]::Zero) { return @{ ok = $false; why = 'kein Fenster' } }
    $chk = Test-AppWindow ([long]$best) @('spotify')
    if (-not $chk.ok) { return @{ ok = $false; why = [string]$chk.why } }
    return @{ ok = $true; hwnd = [long]$best; pid = [int]$chk.pid; min = [bool][UzWin]::IsIconic($best) }
}

# Bild eines fremden Fensters (Installationsdialog von Steam/Epic), damit Uzai es zeigen kann,
# während das Fenster hinter Uzai bleibt. Nur lesen (PrintWindow), nichts wird umgestellt. Erst
# beim ersten Gebrauch übersetzt (wie UzUia), damit ein Problem hier den Helfer nie mitreißt.
$script:SnapSrc = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class UzSnap {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);

    // PW_RENDERFULLCONTENT (2): auch Chromium- und DirectX-Inhalte. Auf höchstens maxW Pixel
    // Breite verkleinert. "ok" oder der Grund.
    public static string Capture(long hwnd, string path, int maxW) {
        IntPtr h = new IntPtr(hwnd);
        if (!IsWindow(h)) return "kein Fenster";
        RECT r;
        if (!GetWindowRect(h, out r)) return "keine Größe";
        int w = r.Right - r.Left, ht = r.Bottom - r.Top;
        if (w < 2 || ht < 2 || w > 16384 || ht > 16384) return "Größe " + w + "x" + ht;
        try {
            using (Bitmap bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb)) {
                bool ok;
                using (Graphics g = Graphics.FromImage(bmp)) {
                    IntPtr dc = g.GetHdc();
                    try { ok = PrintWindow(h, dc, 2); } finally { g.ReleaseHdc(dc); }
                }
                if (!ok) return "PrintWindow";
                if (maxW > 0 && w > maxW) {
                    int nh = Math.Max(1, (int)((long)ht * maxW / w));
                    using (Bitmap small = new Bitmap(bmp, new Size(maxW, nh))) { small.Save(path, ImageFormat.Png); }
                } else {
                    bmp.Save(path, ImageFormat.Png);
                }
            }
        } catch (Exception ex) { return ex.Message; }
        return "ok";
    }

    // Fernseher im Zimmer (src/room/spielbild.gd): ein Bild des Spielfensters nur im Speicher –
    // JPEG, höchstens maxW breit, als Base64; nie auf der Platte. PrintWindow läuft in einem
    // eigenen Faden mit Zeitgrenze, damit ein hängendes oder angehaltenes Spiel den Helfer nie
    // aufhält. "ok|<base64>" oder der Grund.
    public static string Frame(long hwnd, int maxW, int quality, int timeoutMs) {
        IntPtr h = new IntPtr(hwnd);
        if (hwnd == 0 || !IsWindow(h)) return "kein Fenster";
        RECT r;
        if (!GetWindowRect(h, out r)) return "keine Größe";
        int w = r.Right - r.Left, ht = r.Bottom - r.Top;
        if (w < 2 || ht < 2 || w > 16384 || ht > 16384) return "Größe " + w + "x" + ht;
        string[] box = new string[] { "Zeitgrenze" };
        Thread t = new Thread(delegate() { box[0] = FrameNow(h, w, ht, maxW, quality); });
        t.IsBackground = true;
        t.Start();
        if (!t.Join(timeoutMs)) return "Zeitgrenze";
        return box[0];
    }

    static string FrameNow(IntPtr h, int w, int ht, int maxW, int quality) {
        try {
            using (Bitmap bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb)) {
                bool ok;
                using (Graphics g = Graphics.FromImage(bmp)) {
                    IntPtr dc = g.GetHdc();
                    try { ok = PrintWindow(h, dc, 2); } finally { g.ReleaseHdc(dc); }
                }
                if (!ok) return "PrintWindow";
                int nw = Math.Min(w, maxW);
                int nh = Math.Max(1, (int)((long)ht * nw / w));
                ImageCodecInfo jpg = null;
                foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders()) {
                    if (c.FormatID == ImageFormat.Jpeg.Guid) { jpg = c; }
                }
                if (jpg == null) return "kein JPEG";
                using (Bitmap small = new Bitmap(nw, nh, PixelFormat.Format24bppRgb)) {
                    using (Graphics gs = Graphics.FromImage(small)) {
                        gs.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
                        gs.DrawImage(bmp, 0, 0, nw, nh);
                    }
                    using (MemoryStream ms = new MemoryStream())
                    using (EncoderParameters ep = new EncoderParameters(1)) {
                        ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, (long)quality);
                        small.Save(ms, jpg, ep);
                        return "ok|" + Convert.ToBase64String(ms.ToArray());
                    }
                }
            }
        } catch (Exception ex) { return ex.Message; }
    }
}
'@

function Use-Snap {
    if ($script:SnapReady) { return }
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition $script:SnapSrc -ReferencedAssemblies System.Drawing
    $script:SnapReady = $true
}

# Bild in Bild (src/core/pip.gd): mpvs Fenster klein in einer Ecke über Spiel und Uzai. Es nimmt nie
# den Fokus (WS_EX_NOACTIVATE), steht nicht in Taskleiste und Alt+Tab (WS_EX_TOOLWINDOW statt
# WS_EX_APPWINDOW), hat unter Windows 11 runde Ecken und einen feinen dunklen Rand. Bewegt wird es
# nur mit SetWindowPos ohne Aktivieren; Größe und Lage gleiten in einem eigenen Faden (etwa 80 Bilder
# pro Sekunde, weich auslaufend), damit Uzai nicht für jedes Bild einen Befehl schicken muss.
# Rechnet mit echten Pixeln je Bildschirm (Per-Monitor-DPI), auch auf dem Bildschirm des Spiels.
# Erst beim ersten Gebrauch übersetzt (wie UzSnap).
$script:PipSrc = @'
using System;
using System.Threading;
using System.Runtime.InteropServices;

public static class UzPip {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetTopWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr m, int type, out uint x, out uint y);
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);

    const long EX_NOACTIVATE = 0x08000000L, EX_TOOLWINDOW = 0x80L, EX_APPWINDOW = 0x40000L, EX_LAYERED = 0x80000L, EX_TRANSPARENT = 0x20L;
    // SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS
    const uint Z_ONLY = 0x0001u | 0x0002u | 0x0010u | 0x0200u | 0x4000u;
    // SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER (beim Gleiten zusätzlich ASYNC)
    const uint MOVE_ONLY = 0x0004u | 0x0010u | 0x0200u;

    static readonly object gate = new object();
    static readonly AutoResetEvent wake = new AutoResetEvent(false);
    static Thread worker;
    static IntPtr animH = IntPtr.Zero;
    static int x0, y0, w0, h0, x1, y1, w1, h1, animMs;
    static DateTime animStart;

    // Per-Monitor-DPI nur für diesen Aufruf (Windows 10 1607+; sonst bleibt es, wie es ist).
    static IntPtr Aware() {
        try { return SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch { return IntPtr.Zero; }
    }

    static void Unaware(IntPtr old) {
        if (old == IntPtr.Zero) return;
        try { SetThreadDpiAwarenessContext(old); } catch { }
    }

    public static bool Alive(long hwnd) { return hwnd != 0 && IsWindow(new IntPtr(hwnd)); }

    // Fenster von mpv: das größte mit Titel, sichtbare zuerst (versteckt im Ruhemodus zählt auch).
    public static long Find(int pid) {
        IntPtr best = IntPtr.Zero;
        long area = -1;
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            int p;
            GetWindowThreadProcessId(h, out p);
            if (p != pid || GetWindowTextLength(h) == 0) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            long a = (long)(r.Right - r.Left) * (long)(r.Bottom - r.Top) + 1;
            if (IsWindowVisible(h)) a += 1L << 40;
            if (a > area) { area = a; best = h; }
            return true;
        }, IntPtr.Zero);
        return best.ToInt64();
    }

    // „Bildschirm x|y|b|h|Arbeitsbereich x|y|b|h|dpi|Fenster x|y|b|h|Benachrichtigungsstatus|vorn“ –
    // Bildschirm des Bezugsfensters (Spiel), sonst des Fensters selbst.
    public static string Info(long hwnd, long refHwnd) {
        IntPtr old = Aware();
        try {
            IntPtr h = new IntPtr(hwnd);
            IntPtr r = (refHwnd != 0 && IsWindow(new IntPtr(refHwnd))) ? new IntPtr(refHwnd) : h;
            IntPtr mon = MonitorFromWindow(r, 2);
            MONITORINFO mi = new MONITORINFO();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            GetMonitorInfo(mon, ref mi);
            uint dx = 96, dy = 96;
            try { if (GetDpiForMonitor(mon, 0, out dx, out dy) != 0) dx = 96; } catch { dx = 96; }
            RECT w = new RECT();
            if (hwnd != 0 && IsWindow(h)) GetWindowRect(h, out w);
            int q = 0;
            try { SHQueryUserNotificationState(out q); } catch { q = 0; }
            bool fg = hwnd != 0 && GetForegroundWindow() == h;
            RECT m = mi.rcMonitor, k = mi.rcWork;
            return string.Join("|", new string[] {
                m.Left.ToString(), m.Top.ToString(), (m.Right - m.Left).ToString(), (m.Bottom - m.Top).ToString(),
                k.Left.ToString(), k.Top.ToString(), (k.Right - k.Left).ToString(), (k.Bottom - k.Top).ToString(),
                dx.ToString(), w.Left.ToString(), w.Top.ToString(), (w.Right - w.Left).ToString(), (w.Bottom - w.Top).ToString(),
                q.ToString(), fg ? "1" : "0" });
        } finally { Unaware(old); }
    }

    // Art des Fensters: pip = true ohne Fokus, ohne Taskleiste, runde Ecken; false wie vorher.
    // Versteckt umgestellt, sonst behält die Taskleiste den Eintrag.
    public static bool Style(long hwnd, bool pip) {
        IntPtr h = new IntPtr(hwnd);
        if (!IsWindow(h)) return false;
        long ex = GetWindowLongPtr(h, -20).ToInt64();
        long want = pip ? ((ex | EX_NOACTIVATE | EX_TOOLWINDOW) & ~EX_APPWINDOW) : (ex & ~(EX_NOACTIVATE | EX_TOOLWINDOW));
        if (want != ex) {
            bool vis = IsWindowVisible(h);
            if (vis) ShowWindow(h, 0);
            SetWindowLongPtr(h, -20, new IntPtr(want));
            if (vis) ShowWindow(h, 4);
        }
        // DWMWA_WINDOW_CORNER_PREFERENCE: 2 rund, 0 wie Windows will; DWMWA_BORDER_COLOR: dunkles
        // Grau bzw. Standard (0xFFFFFFFF). Vor Windows 11 lehnt DWM beides still ab.
        int corner = pip ? 2 : 0;
        int border = pip ? 0x00302E2C : -1;
        try { DwmSetWindowAttribute(h, 33, ref corner, 4); } catch { }
        try { DwmSetWindowAttribute(h, 34, ref border, 4); } catch { }
        return true;
    }

    // Deckkraft 30…100 % (unter 100 % als Layered-Fenster).
    public static bool Alpha(long hwnd, int pct) {
        IntPtr h = new IntPtr(hwnd);
        if (!IsWindow(h)) return false;
        long ex = GetWindowLongPtr(h, -20).ToInt64();
        if (pct >= 100) {
            if ((ex & EX_LAYERED) != 0) SetWindowLongPtr(h, -20, new IntPtr(ex & ~EX_LAYERED));
            return true;
        }
        if ((ex & EX_LAYERED) == 0) SetWindowLongPtr(h, -20, new IntPtr(ex | EX_LAYERED));
        int a = Math.Max(77, Math.Min(255, pct * 255 / 100));
        return SetLayeredWindowAttributes(h, 0, (byte)a, 2);
    }

    // Nach x/y/b/h, in ms Millisekunden weich (0: sofort). Eine neue Bewegung beginnt dort, wo das
    // Fenster gerade steht – Verschieben mit dem Stick gleitet so ohne Sprünge.
    public static bool Move(long hwnd, int x, int y, int w, int hgt, int ms) {
        IntPtr h = new IntPtr(hwnd);
        if (!IsWindow(h) || w < 16 || hgt < 9) return false;
        IntPtr old = Aware();
        try {
            if (ms <= 0) {
                lock (gate) { animH = IntPtr.Zero; }
                return SetWindowPos(h, IntPtr.Zero, x, y, w, hgt, MOVE_ONLY);
            }
            RECT r;
            if (!GetWindowRect(h, out r)) return false;
            lock (gate) {
                animH = h;
                x0 = r.Left; y0 = r.Top; w0 = r.Right - r.Left; h0 = r.Bottom - r.Top;
                x1 = x; y1 = y; w1 = w; h1 = hgt;
                animMs = ms;
                animStart = DateTime.UtcNow;
                if (worker == null) {
                    worker = new Thread(Loop);
                    worker.IsBackground = true;
                    worker.Start();
                }
            }
            wake.Set();
            return true;
        } finally { Unaware(old); }
    }

    static void Loop() {
        Aware();
        while (true) {
            IntPtr h;
            int x = 0, y = 0, w = 0, hh = 0;
            lock (gate) {
                h = animH;
                if (h != IntPtr.Zero) {
                    double k = (DateTime.UtcNow - animStart).TotalMilliseconds / Math.Max(1, animMs);
                    if (k >= 1.0) { k = 1.0; animH = IntPtr.Zero; }
                    double e = 1.0 - Math.Pow(1.0 - k, 3.0);
                    x = x0 + (int)Math.Round((x1 - x0) * e);
                    y = y0 + (int)Math.Round((y1 - y0) * e);
                    w = w0 + (int)Math.Round((w1 - w0) * e);
                    hh = h0 + (int)Math.Round((h1 - h0) * e);
                }
            }
            if (h == IntPtr.Zero) { wake.WaitOne(1000); continue; }
            try { if (IsWindow(h)) SetWindowPos(h, IntPtr.Zero, x, y, w, hh, MOVE_ONLY | 0x4000u); } catch { }
            Thread.Sleep(12);
        }
    }

    // Ganz nach oben (HWND_TOPMOST, ohne Aktivieren). covered: nur wenn ein fremdes Fenster darüber liegt.
    public static bool Raise(long hwnd, int ownPid, bool covered) {
        IntPtr h = new IntPtr(hwnd);
        if (!IsWindow(h) || !IsWindowVisible(h)) return false;
        if (covered && !Covered(h, ownPid)) return false;
        return SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, Z_ONLY);
    }

    // Direkt unter ein anderes Fenster (Uzai mit dem Guide). Liegt es unter einem normalen Fenster,
    // ist es danach nicht mehr „immer oben“ – Raise holt das zurück.
    public static bool Behind(long hwnd, long after) {
        IntPtr h = new IntPtr(hwnd), a = new IntPtr(after);
        if (!IsWindow(h) || !IsWindow(a)) return false;
        return SetWindowPos(h, a, 0, 0, 0, 0, Z_ONLY);
    }

    // Zeigen (ohne Aktivieren) oder verstecken (Ruhemodus).
    public static bool Show(long hwnd, bool on) {
        IntPtr h = new IntPtr(hwnd);
        if (!IsWindow(h)) return false;
        ShowWindow(h, on ? 4 : 0);
        return true;
    }

    public static bool IsForeground(long hwnd) { return hwnd != 0 && GetForegroundWindow() == new IntPtr(hwnd); }

    // Wer liegt vorn? „Vordergrundfenster|dessen Prozess|Prozess des Spielfensters“ (0: keins). Uzai
    // entscheidet damit, ob das Bild oben bleibt (Uzai, Video, Spiel) oder sich versteckt (anderes
    // Programm, Desktop). Nur Nachsehen, nichts wird umgestellt.
    public static string Front(long gameHwnd) {
        IntPtr fg = GetForegroundWindow();
        int fp = 0, gp = 0;
        if (fg != IntPtr.Zero) GetWindowThreadProcessId(fg, out fp);
        IntPtr g = new IntPtr(gameHwnd);
        if (gameHwnd != 0 && IsWindow(g)) GetWindowThreadProcessId(g, out gp);
        return fg.ToInt64().ToString() + "|" + fp.ToString() + "|" + gp.ToString();
    }

    static bool Cloaked(IntPtr w) {
        int c = 0;
        try { return DwmGetWindowAttribute(w, 14, out c, 4) == 0 && c != 0; } catch { return false; }
    }

    // Liegt ein sichtbares Fenster eines anderen Programms (nicht Uzai, nicht durchklickbar) darüber?
    static bool Covered(IntPtr h, int ownPid) {
        RECT me;
        if (!GetWindowRect(h, out me)) return false;
        int self;
        GetWindowThreadProcessId(h, out self);
        IntPtr w = GetTopWindow(IntPtr.Zero);
        int guard = 0;
        while (w != IntPtr.Zero && w != h && guard++ < 2000) {
            int p;
            GetWindowThreadProcessId(w, out p);
            if (p != ownPid && p != self && IsWindowVisible(w) && !IsIconic(w) && !Cloaked(w)) {
                long ex = GetWindowLongPtr(w, -20).ToInt64();
                RECT r;
                if ((ex & EX_TRANSPARENT) == 0 && GetWindowRect(w, out r)
                    && r.Right > me.Left && r.Left < me.Right && r.Bottom > me.Top && r.Top < me.Bottom
                    && r.Right - r.Left > 1 && r.Bottom - r.Top > 1) return true;
            }
            w = GetWindow(w, 2);
        }
        return false;
    }
}
'@

function Use-Pip {
    if ($script:PipReady) { return }
    Add-Type -TypeDefinition $script:PipSrc
    $script:PipReady = $true
}

# Vorhang (src/core/vorhang.gd): ein eigenes, randloses Fenster des Helfers, oberste Ebene, ohne
# Taskleisten-Eintrag (WS_EX_TOOLWINDOW), nie aktivierbar (WS_EX_NOACTIVATE) und für Maus und Uzais
# Vorn-Halten durchlässig (WS_EX_TRANSPARENT). Ein eigener Faden besitzt es; Uzais Aufträge und
# Meldungen von Windows (Vordergrund gewechselt, Fenster des Spiels zu) wecken ihn sofort, sonst schaut
# er alle 15 ms nach (solange der Vorhang steht: alle 2 ms).
# - Vorhang: deckt beim Spielstart und Spielende Desktop und Taskleiste ab (schwarz bzw. in Uzais
#   Grundfarbe), bis das Spiel bzw. Uzai wirklich vorn ist. „an“ antwortet erst, wenn er gemalt ist
#   und Windows ihn dargestellt hat (DwmFlush) – erst dann stellt Uzai sein Fenster um. Legt Windows
#   die Taskleiste wieder darüber (nach jedem Wechsel des Vordergrunds), legt er sich sofort zurück
#   nach oben; beim Spielende über jedes Fenster, bis Uzai gezeichnet hat. Ein fremdes Vordergrund-
#   fenster, das nicht den ganzen Bildschirm deckt (Dialog, Starter, Fehlermeldung), bleibt ausgespart
#   (Fenster-Region mit Loch), sobald es kurz vorn bleibt – Uzai verdeckt nie, was auf dich wartet;
#   ein Ladefenster, das gleich wieder geht, bleibt verdeckt (beim Spielende ohne Loch: dann kommt
#   gleich Uzai). Deckt das Vordergrundfenster den Bildschirm (Spiel im Vollbild, auch auf einem
#   anderen Bildschirm) und ist es weder von Windows versteckt noch hängt es, ist der Vorhang
#   überflüssig und geht. Immer mit Zeitgrenze.
# - Wache: Solange ein Spiel läuft, merkt der Faden sofort, wenn sein Fenster verschwindet (Spiel
#   zu), und zieht den Vorhang zu, bevor der Desktop zu sehen ist; Uzai erfährt es als Ereignis
#   {"event":"vorhang"}. Nur Nachsehen (IsWindow, IsWindowVisible, Meldungen von Windows über
#   SetWinEventHook außerhalb des Spiels), nichts wird umgestellt.
# Alles nur mit Zahlen. Erst beim ersten Gebrauch übersetzt.
$script:EbenenSrc = @'
using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;

public static class UzEbenen {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public POINT pt; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASSEX { public uint cbSize; public uint style; public IntPtr lpfnWndProc; public int cbClsExtra; public int cbWndExtra; public IntPtr hInstance; public IntPtr hIcon; public IntPtr hCursor; public IntPtr hbrBackground; public string lpszMenuName; public string lpszClassName; public IntPtr hIconSm; }
    delegate IntPtr WndProcFn(IntPtr h, uint m, IntPtr w, IntPtr l);
    delegate void WinEventFn(IntPtr hook, uint ev, IntPtr h, int idObject, int idChild, uint thread, uint time);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassEx(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool PeekMessage(out MSG m, IntPtr h, uint min, uint max, uint remove);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("user32.dll")] static extern uint MsgWaitForMultipleObjects(uint n, IntPtr[] handles, bool all, uint ms, uint mask);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool UpdateWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
    [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventFn fn, uint pid, uint tid, uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("gdi32.dll")] static extern IntPtr CreateSolidBrush(uint color);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
    [DllImport("gdi32.dll")] static extern IntPtr CreateRectRgn(int l, int t, int r, int b);
    [DllImport("gdi32.dll")] static extern int CombineRgn(IntPtr dst, IntPtr a, IntPtr b, int mode);
    [DllImport("user32.dll")] static extern int FillRect(IntPtr dc, ref RECT r, IntPtr brush);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr BeginPaint(IntPtr h, byte[] ps);
    [DllImport("user32.dll")] static extern bool EndPaint(IntPtr h, byte[] ps);
    [DllImport("user32.dll")] static extern bool InvalidateRect(IntPtr h, IntPtr r, bool erase);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint ms);
    [DllImport("dwmapi.dll")] static extern int DwmFlush();
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);

    // WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT (+ WS_EX_LAYERED beim
    // Vorhang, für das Ausblenden); WS_POPUP.
    const uint EX_BASIS = 0x00000008u | 0x00000080u | 0x08000000u | 0x00000020u;
    const uint EX_LAYERED = 0x00080000u;
    const uint WS_POPUP = 0x80000000u;
    // SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW
    const uint SWP_ZEIGEN = 0x0010u | 0x0200u | 0x0040u;
    // SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
    const uint SWP_NUR_Z = 0x0001u | 0x0002u | 0x0010u | 0x0200u;
    static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

    /// Deckt das Vordergrundfenster den Bildschirm so lange, ist der Vorhang fertig.
    public const int VOLL_MS = 400;
    /// Feste Obergrenzen (der Helfer nimmt nie mehr an).
    public const int MAX_MS = 180000;
    public const int MAX_WEICH_MS = 1000;
    public const int MAX_LOCH_MS = 5000;
    /// Höchstens so oft legt sich der Vorhang wieder ganz nach oben (ms).
    public const int HOCH_MS = 10;

    static readonly object gate = new object();
    static readonly AutoResetEvent wecker = new AutoResetEvent(false);
    static Thread worker;
    static WndProcFn proc;               // bleibt am Leben, solange der Faden lebt
    static WinEventFn evProc;            // ebenso
    static IntPtr vWnd = IntPtr.Zero;
    static IntPtr vPinsel = IntPtr.Zero;

    // Vorhang (unter gate)
    static bool vAn;
    static long vBis;
    static uint vFarbe;
    static bool vLochUzai;
    static bool vLochAn = true;
    static int vLochMs;
    static int vEinMs;                    // einblenden (nur „beenden“; sonst sofort ganz da)
    static bool vImmer;                   // bleibt, auch wenn das Spiel noch den Bildschirm deckt (Beenden: Uzai beendet es gleich)
    static int[] vLochPids;               // Loch nur um Fenster dieser Prozesse (leer: um jedes)
    static IntPtr vBezug = IntPtr.Zero;
    static int vWeichMs = 200;
    static long vVollSeit;
    static int vAuftrag;                  // jeder Auftrag „an“ zählt hoch …
    static int vErledigt;                 // … und so weit steht der Vorhang auf dem Bildschirm (oder ist nicht nötig)
    static bool vErledigtSichtbar;
    public static int Ausgeloest;
    // Wache (unter gate)
    static bool wAn;
    static IntPtr wSpiel = IntPtr.Zero;
    static int wMs;
    static uint wFarbe;
    static bool melden;
    static bool kaputt;                   // der Faden lief nicht (keine Fenster)
    // nur im Faden
    static bool vSichtbar;
    static int vAlpha;
    static long vAusSeit;
    static int vAusVon;
    static long vEinSeit;
    static bool vAusblenden;
    static RECT vLoch, vMon;
    static IntPtr vLochKand = IntPtr.Zero;
    static long vLochSeit;
    static long vHochAt;
    static uint vPinselFarbe = 0xFFFFFFFFu;
    static bool feinTakt;
    static IntPtr hookVorn = IntPtr.Zero, hookSpiel = IntPtr.Zero;
    static int hookPid;
    static volatile bool angestossen;

    static long Jetzt() { return DateTime.UtcNow.Ticks / 10000L; }

    // --- Reine Regeln (ohne Windows, prüfbar: tests/logic_vorhang.gd) ----------------------------

    /// Deckt r den Bildschirm mon (bis auf 2 Pixel)?
    public static bool Deckt(RECT r, RECT mon) {
        return mon.Right - mon.Left > 0 && r.Left <= mon.Left + 2 && r.Top <= mon.Top + 2 && r.Right >= mon.Right - 2 && r.Bottom >= mon.Bottom - 2;
    }

    /// Was der Vorhang zeigen soll, je nach Vordergrundfenster: 0 = nichts (es deckt den Bildschirm),
    /// 1 = alles decken, 2 = alles außer diesem Fenster (Loch; nur mit loch).
    /// mon: Uzais Bildschirm, fgMon: der Bildschirm des Vordergrundfensters. bereit: Es ist nicht
    /// von Windows versteckt und antwortet – ein Fenster, das zwar den Bildschirm deckt, aber noch
    /// nichts zeigt (versteckt, hängt beim Laden), beendet den Vorhang nicht.
    public static int Art(RECT mon, RECT fgMon, bool fgOk, bool bereit, RECT fg, bool loch) {
        if (!fgOk || fg.Right - fg.Left < 2 || fg.Bottom - fg.Top < 2) return 1;
        if (Deckt(fg, mon)) return bereit ? 0 : 1;
        // Das Spiel im Vollbild auf einem anderen Bildschirm: Uzais Bildschirm muss nicht schwarz bleiben.
        bool andererBildschirm = fgMon.Left != mon.Left || fgMon.Top != mon.Top || fgMon.Right != mon.Right || fgMon.Bottom != mon.Bottom;
        if (andererBildschirm && bereit && Deckt(fg, fgMon)) return 0;
        if (!loch || fg.Right <= mon.Left || fg.Left >= mon.Right || fg.Bottom <= mon.Top || fg.Top >= mon.Bottom) return 1;
        return 2;
    }

    /// Ein Schritt: 0 = fertig (ausblenden), 1 = decken, 2 = mit Loch, 3 = gerade unsichtbar (das
    /// Vordergrundfenster deckt den Bildschirm; nach VOLL_MS ist der Vorhang fertig).
    public static int Weiter(long jetzt, long bis, int art, ref long vollSeit) {
        if (jetzt >= bis) return 0;
        if (art == 0) {
            if (vollSeit == 0) vollSeit = jetzt;
            return jetzt - vollSeit >= VOLL_MS ? 0 : 3;
        }
        vollSeit = 0;
        return art;
    }

    /// Beim Beenden: Ein Loch bekommt nur ein Fenster des Spiels (seine Rückfrage), nie ein fremdes
    /// (Browser, Explorer, das nach dem Spielfenster vorn liegt); deckt das Spiel noch alles, bleibt der
    /// Vorhang trotzdem (immer – gleich beendet Uzai es hart).
    public static int Beim(int art, bool immer, int[] lochPids, int fgPid) {
        if (art == 0 && immer) return 1;
        if (art == 2 && lochPids != null && lochPids.Length > 0 && Array.IndexOf(lochPids, fgPid) < 0) return 1;
        return art;
    }

    /// Loch erst, wenn dasselbe Fenster lochMs lang vorn liegt: Ein Lade- oder Startfenster, das nur
    /// kurz aufgeht (Emulator, Launcher), bleibt so verdeckt; ein Dialog, der auf dich wartet, nicht.
    /// seit: ab wann dasselbe Fenster das Loch bekäme.
    public static int MitLochfrist(int art, long jetzt, long seit, int lochMs) {
        if (art != 2) return art;
        return jetzt - seit < lochMs ? 1 : 2;
    }

    /// Muss der Vorhang wieder ganz nach oben? alles (Spielende): über jedes Fenster; sonst nur über
    /// die Taskleiste – die legt Windows nach jedem Wechsel des Vordergrunds wieder über alles.
    public static bool ObenStoert(bool alles, string cls) {
        return alles || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd";
    }

    public static int Grenze(int ms) { return Math.Max(200, Math.Min(MAX_MS, ms)); }

    /// 0xRRGGBB (wie Uzai) → COLORREF 0x00BBGGRR.
    public static uint Farbe(int rgb) {
        int c = Math.Max(0, Math.Min(0xFFFFFF, rgb));
        return (uint)(((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF));
    }

    // --- Aufträge von Uzai ---------------------------------------------------------------------

    /// Vorhang zu. Gibt die Nummer des Auftrags zurück (für Stand).
    public static int VorhangAn(long bezug, int farbe, int ms, bool loch, bool lochUzai, int lochMs, int einMs) {
        return VorhangAn(bezug, farbe, ms, loch, lochUzai, lochMs, einMs, false, null);
    }

    /// immer: auch über einem Vollbild-Fenster (Beenden). lochPids: Loch nur um deren Fenster.
    public static int VorhangAn(long bezug, int farbe, int ms, bool loch, bool lochUzai, int lochMs, int einMs, bool immer, int[] lochPids) {
        int n;
        lock (gate) {
            vImmer = immer;
            vLochPids = lochPids != null && lochPids.Length > 0 ? (int[])lochPids.Clone() : null;
            vEinMs = Math.Max(0, Math.Min(MAX_WEICH_MS, einMs));
            vAn = true;
            vBezug = new IntPtr(bezug);
            vFarbe = Farbe(farbe);
            vBis = Jetzt() + Grenze(ms);
            vLochAn = loch;
            vLochUzai = lochUzai;
            vLochMs = Math.Max(0, Math.Min(MAX_LOCH_MS, lochMs));
            vVollSeit = 0;
            vAuftrag++;
            n = vAuftrag;
        }
        Faden();
        wecker.Set();
        return n;
    }

    /// Wartet, bis der Faden den Auftrag n umgesetzt hat: 1 = der Vorhang steht auf dem Bildschirm
    /// (gezeichnet, und Windows hat ihn dargestellt), 0 = nicht nötig (das Spiel deckt schon alles),
    /// -1 = keine Antwort in ms (oder der Faden läuft nicht).
    public static int Stand(int n, int ms) {
        long bis = Jetzt() + Math.Max(0, Math.Min(2000, ms));
        lock (gate) {
            while (vErledigt < n && !kaputt) {
                long rest = bis - Jetzt();
                if (rest <= 0) return -1;
                Monitor.Wait(gate, (int)rest);
            }
            if (kaputt) return -1;
            return vErledigtSichtbar ? 1 : 0;
        }
    }

    public static void VorhangAus(int weichMs) {
        lock (gate) {
            vAn = false;
            vWeichMs = Math.Max(0, Math.Min(MAX_WEICH_MS, weichMs));
        }
        // Auch zum Vorbereiten: Der Faden legt seine Fenster schon an, nicht erst beim ersten Spiel.
        Faden();
        wecker.Set();
    }

    public static bool VorhangAktiv() { lock (gate) { return vAn; } }

    /// Wache an (nur auf ein Fenster, das es gerade gibt – sonst ginge sie sofort los) oder aus.
    public static bool Wache(bool an, long bezug, long spiel, int farbe, int ms) {
        IntPtr s = new IntPtr(spiel);
        bool geht = an && spiel != 0 && IsWindow(s) && IsWindowVisible(s);
        lock (gate) {
            wAn = geht;
            wSpiel = geht ? s : IntPtr.Zero;
            if (bezug != 0) vBezug = new IntPtr(bezug);
            wFarbe = Farbe(farbe);
            wMs = Grenze(ms);
        }
        if (geht) Faden();
        wecker.Set();
        return geht;
    }

    public static bool WacheAktiv() { lock (gate) { return wAn; } }

    // --- Der Faden -----------------------------------------------------------------------------

    static void Faden() {
        lock (gate) {
            if (worker != null) return;
            worker = new Thread(Lauf);
            worker.IsBackground = true;
            worker.Start();
        }
    }

    static IntPtr Proc(IntPtr h, uint m, IntPtr w, IntPtr l) {
        if (m == 0x0021) return new IntPtr(3);            // WM_MOUSEACTIVATE → MA_NOACTIVATE
        if (m == 0x0084) return new IntPtr(-1);           // WM_NCHITTEST → HTTRANSPARENT
        if (m == 0x0014) return new IntPtr(1);            // WM_ERASEBKGND: malt WM_PAINT
        if (m == 0x000F) {                                 // WM_PAINT: ganz in der Farbe
            byte[] ps = new byte[128];
            IntPtr dc = BeginPaint(h, ps);
            RECT r;
            GetClientRect(h, out r);
            IntPtr b = h == vWnd && vPinsel != IntPtr.Zero ? vPinsel : CreateSolidBrush(0);
            FillRect(dc, ref r, b);
            if (b != vPinsel) DeleteObject(b);
            EndPaint(h, ps);
            return IntPtr.Zero;
        }
        return DefWindowProc(h, m, w, l);
    }

    // Windows meldet: ein anderes Fenster ist vorn (danach legt es die Taskleiste wieder nach oben),
    // oder ein Fenster des Spiels ging zu bzw. weg. Nur anstoßen – der Faden sieht gleich selbst nach.
    static void Ereignis(IntPtr hook, uint ev, IntPtr h, int idObject, int idChild, uint thread, uint time) {
        if (ev == 3u || ((ev == 0x8001u || ev == 0x8003u) && idObject == 0)) angestossen = true;
    }

    static IntPtr Neu(string cls, uint ex) {
        IntPtr inst = GetModuleHandle(null);
        WNDCLASSEX wc = new WNDCLASSEX();
        wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
        wc.lpfnWndProc = Marshal.GetFunctionPointerForDelegate(proc);
        wc.hInstance = inst;
        wc.lpszClassName = cls;
        RegisterClassEx(ref wc);
        IntPtr h = CreateWindowEx(ex, cls, "", WS_POPUP, 0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, inst, IntPtr.Zero);
        if (h == IntPtr.Zero) return h;
        int an = 1;
        try { DwmSetWindowAttribute(h, 3, ref an, 4); } catch { }      // DWMWA_TRANSITIONS_FORCEDISABLED
        int eckig = 1;
        try { DwmSetWindowAttribute(h, 33, ref eckig, 4); } catch { }  // DWMWA_WINDOW_CORNER_PREFERENCE: keine runden Ecken
        return h;
    }

    // Geht hier etwas schief, endet nur dieser Faden (nie der Helfer); Uzai sieht „geht nicht“.
    static void Lauf() {
        try { LaufInnen(); } catch { lock (gate) { kaputt = true; Monitor.PulseAll(gate); } }
        if (feinTakt) { try { timeEndPeriod(1); } catch { } feinTakt = false; }
    }

    static void LaufInnen() {
        try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch { }
        proc = new WndProcFn(Proc);
        evProc = new WinEventFn(Ereignis);
        vWnd = Neu("UzaiVorhang", EX_BASIS | EX_LAYERED);
        if (vWnd == IntPtr.Zero) throw new InvalidOperationException("Fenster");
        // EVENT_SYSTEM_FOREGROUND; WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS (nur Nachricht, nichts im fremden Prozess)
        try { hookVorn = SetWinEventHook(3, 3, IntPtr.Zero, evProc, 0, 0, 2); } catch { hookVorn = IntPtr.Zero; }
        IntPtr[] warte = new IntPtr[] { wecker.SafeWaitHandle.DangerousGetHandle() };
        MSG msg;
        while (true) {
            angestossen = false;
            while (PeekMessage(out msg, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref msg); DispatchMessage(ref msg); }
            int zeigen = 0;
            bool still;
            try { still = Schritt(out zeigen); } catch { still = false; }
            if (zeigen > 0) {
                // Erst gemalt und von Windows dargestellt, dann erfährt Uzai „steht“ – vorher darf Uzai
                // sein Fenster nicht umstellen (sonst sähe man für ein Bild den Desktop).
                try { UpdateWindow(vWnd); DwmFlush(); } catch { }
                lock (gate) {
                    if (vErledigt < zeigen) { vErledigt = zeigen; vErledigtSichtbar = vSichtbar; }
                    Monitor.PulseAll(gate);
                }
            }
            if (melden) {
                melden = false;
                try { Console.Out.WriteLine("{\"id\":-1,\"event\":\"vorhang\"}"); } catch { }
            }
            // Feiner Takt (1 ms) nur, solange der Vorhang steht: So sieht der Faden die Taskleiste,
            // bevor Windows sie darstellt. Danach wieder wie vorher.
            bool fein = vSichtbar;
            if (fein != feinTakt) {
                try { if (fein) timeBeginPeriod(1); else timeEndPeriod(1); } catch { }
                feinTakt = fein;
            }
            if (angestossen) continue;
            uint ms = still ? 250u : (vSichtbar ? 2u : 15u);
            MsgWaitForMultipleObjects(1, warte, false, ms, 0x04FFu);        // QS_ALLINPUT
        }
    }

    static int PidOf(IntPtr h) {
        int p = 0;
        if (h != IntPtr.Zero) GetWindowThreadProcessId(h, out p);
        return p;
    }

    static RECT Bildschirm(IntPtr h) {
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        GetMonitorInfo(MonitorFromWindow(h, h == IntPtr.Zero ? 1u : 2u), ref mi);
        return mi.rcMonitor;
    }

    static string Klasse(IntPtr h) {
        StringBuilder sb = new StringBuilder(64);
        GetClassName(h, sb, 64);
        return sb.ToString();
    }

    static bool Shell(IntPtr h) {
        string c = Klasse(h);
        return c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd" || c == "Progman" || c == "WorkerW";
    }

    // Von DWM versteckt (noch nicht gezeigt, Startmenü, angehaltene Store-Apps): IsWindowVisible sagt trotzdem ja.
    static bool Versteckt(IntPtr h) {
        int c = 0;
        try { return DwmGetWindowAttribute(h, 14, out c, 4) == 0 && c != 0; } catch { return false; }
    }

    // Liegt über dem Vorhang etwas, das ihn stört (siehe ObenStoert)? Nur die Fenster darüber – über
    // einem obersten Fenster liegen höchstens andere oberste.
    static bool Ueberdeckt(bool alles, RECT mon) {
        IntPtr w = GetWindow(vWnd, 3);                        // GW_HWNDPREV
        int guard = 0;
        while (w != IntPtr.Zero && guard++ < 64) {
            if (IsWindowVisible(w) && !IsIconic(w) && !Versteckt(w)) {
                RECT r;
                if (GetWindowRect(w, out r) && r.Right > mon.Left && r.Left < mon.Right && r.Bottom > mon.Top && r.Top < mon.Bottom
                    && ObenStoert(alles, Klasse(w))) return true;
            }
            w = GetWindow(w, 3);
        }
        return false;
    }

    // Wache: Windows meldet sofort, wenn ein Fenster des Spiels zugeht oder verschwindet
    // (EVENT_OBJECT_DESTROY … EVENT_OBJECT_HIDE, nur dieser Prozess) – schneller als nachzusehen.
    static void SpielHaken(int pid) {
        if (pid == hookPid) return;
        if (hookSpiel != IntPtr.Zero) { try { UnhookWinEvent(hookSpiel); } catch { } }
        hookSpiel = IntPtr.Zero;
        hookPid = pid;
        if (pid > 0) { try { hookSpiel = SetWinEventHook(0x8001, 0x8003, IntPtr.Zero, evProc, (uint)pid, 0, 0); } catch { hookSpiel = IntPtr.Zero; } }
    }

    // Ein Schritt. still: nichts zu tun (der Faden darf länger schlafen). zeigen: dieser Auftrag ist
    // jetzt sichtbar oder unnötig – nach dem Darstellen melden.
    static bool Schritt(out int zeigen) {
        zeigen = 0;
        long jetzt = Jetzt();
        bool an, lochUzai, lochAn;
        IntPtr bezug;
        long bis;
        uint farbe;
        int weich;
        lock (gate) {
            // Wache: Spielfenster weg (Spiel zu) → sofort decken, bevor der Desktop zu sehen ist.
            if (wAn && !vAn && (wSpiel == IntPtr.Zero || !IsWindow(wSpiel) || !IsWindowVisible(wSpiel))) {
                wAn = false;
                vAn = true;
                vBis = jetzt + wMs;
                vFarbe = wFarbe;
                vLochAn = false;
                vLochUzai = false;
                vImmer = false;
                vLochPids = null;
                vVollSeit = 0;
                Ausgeloest++;
                melden = true;
            }
            SpielHaken(wAn ? PidOf(wSpiel) : 0);
            an = vAn; lochUzai = vLochUzai; lochAn = vLochAn; bezug = vBezug; bis = vBis; farbe = vFarbe; weich = vWeichMs;
            int art = 0;
            if (an) {
                RECT mon = Bildschirm(IsWindow(bezug) ? bezug : (IsWindow(wSpiel) ? wSpiel : IntPtr.Zero));
                IntPtr fg = GetForegroundWindow();
                RECT fr = new RECT();
                bool fgOk = fg != IntPtr.Zero && fg != vWnd && IsWindowVisible(fg) && !IsIconic(fg) && !Versteckt(fg)
                    && GetWindowRect(fg, out fr) && !Shell(fg) && (lochUzai || PidOf(fg) != PidOf(bezug));
                bool bereit = fgOk && !IsHungAppWindow(fg);
                int roh = Beim(Art(mon, fgOk ? Bildschirm(fg) : mon, fgOk, bereit, fr, lochAn), vImmer, vLochPids, fgOk ? PidOf(fg) : 0);
                if (roh != 2) vLochKand = IntPtr.Zero;
                else if (fg != vLochKand) { vLochKand = fg; vLochSeit = jetzt; }
                roh = MitLochfrist(roh, jetzt, vLochSeit, vLochMs);
                art = Weiter(jetzt, bis, roh, ref vVollSeit);
                if (art == 0) vAn = false;
                VorhangZeigen(art, mon, fr, farbe, weich, jetzt, vEinMs);
                if ((art == 1 || art == 2) && vSichtbar && jetzt - vHochAt >= HOCH_MS && Ueberdeckt(!lochAn, mon)) {
                    vHochAt = jetzt;
                    SetWindowPos(vWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NUR_Z);
                }
            } else {
                vLochKand = IntPtr.Zero;
                VorhangZeigen(0, vMon, vLoch, farbe, weich, jetzt, 0);
            }
            if (vErledigt < vAuftrag) {
                if (an && (art == 1 || art == 2) && vSichtbar) {
                    zeigen = vAuftrag;
                } else if (!an || art == 0 || art == 3) {
                    vErledigt = vAuftrag;
                    vErledigtSichtbar = false;
                    Monitor.PulseAll(gate);
                }
            }
            return !an && !wAn && !vSichtbar;
        }
    }

    /// Deckkraft beim Einblenden: von 0 auf 255 in einMs (0: sofort ganz).
    public static int EinAlpha(long seit, long jetzt, int einMs) {
        if (einMs <= 0 || jetzt - seit >= einMs) return 255;
        return (int)Math.Max(0, Math.Min(255, 255L * (jetzt - seit) / einMs));
    }

    static void VorhangZeigen(int art, RECT mon, RECT loch, uint farbe, int weich, long jetzt, int einMs) {
        if (vWnd == IntPtr.Zero) return;
        if (art == 0) {
            // Fertig oder von Uzai beendet: weich ausblenden.
            if (!vSichtbar) return;
            if (!vAusblenden) { vAusblenden = true; vAusSeit = jetzt; vAusVon = vAlpha; }
            int a = weich <= 0 ? 0 : (int)(vAusVon * (1.0 - Math.Min(1.0, (jetzt - vAusSeit) / (double)weich)));
            if (a <= 0) {
                ShowWindow(vWnd, 0);
                vSichtbar = false;
                vAusblenden = false;
                vAlpha = 0;
                return;
            }
            if (a != vAlpha) { vAlpha = a; SetLayeredWindowAttributes(vWnd, 0, (byte)a, 2); }
            return;
        }
        if (art == 3) {
            // Das Vordergrundfenster deckt den Bildschirm: nicht darüberliegen (auch nicht unsichtbar –
            // ein Fenster darüber nähme einem Spiel im Vollbild den direkten Weg zum Bildschirm).
            if (vSichtbar) { ShowWindow(vWnd, 0); vSichtbar = false; }
            vAusblenden = false;
            return;
        }
        vAusblenden = false;
        if (farbe != vPinselFarbe) {
            IntPtr alt = vPinsel;
            vPinsel = CreateSolidBrush(farbe);
            vPinselFarbe = farbe;
            if (alt != IntPtr.Zero) DeleteObject(alt);
            InvalidateRect(vWnd, IntPtr.Zero, true);
        }
        int w = mon.Right - mon.Left, h = mon.Bottom - mon.Top;
        RECT neu = art == 2 ? loch : new RECT();
        bool umriss = !vSichtbar || neu.Left != vLoch.Left || neu.Top != vLoch.Top || neu.Right != vLoch.Right || neu.Bottom != vLoch.Bottom
            || mon.Left != vMon.Left || mon.Top != vMon.Top || mon.Right != vMon.Right || mon.Bottom != vMon.Bottom;
        if (umriss) {
            if (art == 2) {
                IntPtr ganz = CreateRectRgn(0, 0, w, h);
                IntPtr frei = CreateRectRgn(loch.Left - mon.Left, loch.Top - mon.Top, loch.Right - mon.Left, loch.Bottom - mon.Top);
                CombineRgn(ganz, ganz, frei, 4);                 // RGN_DIFF
                DeleteObject(frei);
                SetWindowRgn(vWnd, ganz, true);                  // gehört danach Windows
            } else {
                SetWindowRgn(vWnd, IntPtr.Zero, true);
            }
            vLoch = neu;
            vMon = mon;
        }
        if (!vSichtbar) vEinSeit = jetzt;
        int soll = vSichtbar && vAlpha >= 255 ? 255 : EinAlpha(vEinSeit, jetzt, einMs);
        if (soll != vAlpha) { vAlpha = soll; SetLayeredWindowAttributes(vWnd, 0, (byte)soll, 2); }
        if (!vSichtbar || umriss) {
            SetWindowPos(vWnd, HWND_TOPMOST, mon.Left, mon.Top, w, h, SWP_ZEIGEN);
            vSichtbar = true;
            vHochAt = jetzt;
        }
    }
}
'@

function Use-Ebenen {
    if ($script:EbenenReady) { return }
    Add-Type -TypeDefinition $script:EbenenSrc
    $script:EbenenReady = $true
}

# --- Fernseher im Zimmer: Live-Bild über Windows Graphics Capture (UzTvFang) ---------------------
# Aufgestanden im Zimmer zeigt der Fernseher das laufende Spiel weiter. Früher holte Uzai dafür
# PrintWindow-Bilder (JPEG, Base64) – das zwingt Windows, das Spiel für jedes Bild zu synchronisieren,
# und bremste es. Jetzt liefert Windows die Bilder des Spielfensters selbst (Windows Graphics Capture,
# frei laufender Bildpool, nur lesen). Die Grafikkarte rechnet sie klein (Mipmaps, kein eigener
# Shader), eine Staging-Textur holt die kleinen Pixel, und ein fester Kopf plus Bild liegt in einer
# Zwischendatei im eigenen Temp-Ordner (temporär markiert, Windows hält sie im Arbeitsspeicher; beim
# Stoppen gelöscht). Uzai liest sie mit Prüfung (Kennung, Größen, Folgenummer vorn und nach dem Bild).
# Kein Ton, kein Mauszeiger, nichts wird gespeichert oder nach vorn geholt. Nur Zahlen als Argumente.
# Ohne Lebenszeichen von Uzai (15 s) oder wenn das Fenster zugeht, endet die Aufnahme von selbst.
#
# Gegen schwarze Bilder (launch.log 0.16.4: „Windows Graphics Capture liefert nur schwarze Bilder“):
# - Grafikkarte: Das Gerät entsteht auf der Karte, an der der Bildschirm des Spiels hängt (sonst kopiert
#   Windows zwischen zwei Karten – auf Rechnern mit Prozessorgrafik daneben oft schwarz).
# - HDR: Ist der Bildschirm im HDR-Modus (DXGI-Farbraum ST.2084 oder „HDR verwenden“ in den Anzeige-
#   Einstellungen), nimmt der Pool 16-Bit-Gleitkomma (scRGB) statt 8-Bit-BGRA auf; der Helfer rechnet
#   es selbst auf SDR um (SDR-Weiß aus Windows, Lichter laufen weich aus). Kommen trotzdem nur schwarze
#   Bilder, wechselt er einmal das Format.
# - Spiegel (Rückfall, nur auf Uzais Wunsch): Windows zeichnet das Spielfenster per DWM-Vorschau (wie
#   Alt+Tab) in ein eigenes, unsichtbares Helferfenster gleich unter
#   Uzai; aufgenommen wird dann dieses. Kein Fokus, keine Eingaben, kein Taskleisten-Eintrag.
# - Messwerte für launch.log: Grafikkarte, HDR, Format und Größe des ersten Bilds, seine mittlere
#   Farbe (auch im Kopf jedes Bilds, Feld 28), Zustand des Spielfensters (minimiert, von Windows
#   versteckt, Bildschirm deckend, Aufnahmeschutz) und ob Windows exklusives Vollbild meldet.
$script:TvFangSrc = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class UzTvFang {
    // Kopf der Zwischendatei (32 Byte, little endian): "UZTV", Version, Folgenummer (ungerade = wird
    // gerade geschrieben), Breite, Höhe, Zeilenlänge (Breite * 4), Länge der Pixel, mittlere Farbe
    // (FARBE_GUELTIG | R << 16 | G << 8 | B, 0 = unbekannt). Danach RGBA.
    public const int KOPF = 32;
    public const int MAX_SEITE = 1280;
    public const int MAX_PX = 1280 * 720;
    public const uint MAGIC = 0x56545A55;
    public const uint VERSION = 1;
    public const int PULS_MS = 15000;
    // Formate des Bildpools (DirectXPixelFormat = DXGI_FORMAT): 8-Bit-BGRA, 16-Bit-Gleitkomma (scRGB).
    public const int FMT_BGRA = 87;
    public const int FMT_FP16 = 10;
    public const uint FARBE_GUELTIG = 0x80000000u;
    // So viele schwarze Bilder nacheinander (und mindestens so lange), dann einmal das andere Format.
    public const int SCHWARZ_N = 8;
    public const int SCHWARZ_MS = 700;
    // DXGI-Farbraum eines HDR-Bildschirms (RGB, voll, ST.2084, BT.2020).
    public const int FARBRAUM_HDR10 = 12;

    // --- Ohne Windows prüfbar ---------------------------------------------------------------

    // Mip-Stufe, deren Größe zum Ziel passt (höchstens ein Drittel größer, nie über MAX_SEITE/MAX_PX).
    public static int Stufe(int w, int h, int maxW, int maxH) {
        if (w <= 0 || h <= 0) return -1;
        maxW = Math.Max(16, Math.Min(MAX_SEITE, maxW));
        maxH = Math.Max(16, Math.Min(MAX_SEITE, maxH));
        int l = 0;
        while (l < 14) {
            long lw = Math.Max(1, w >> l), lh = Math.Max(1, h >> l);
            if (lw * 3 <= (long)maxW * 4 && lh * 3 <= (long)maxH * 4 && lw <= MAX_SEITE && lh <= MAX_SEITE && lw * lh <= MAX_PX) return l;
            l++;
        }
        return -1;
    }

    public static int Seite(int n, int stufe) { return Math.Max(1, n >> stufe); }

    // BGRA (Windows) → RGBA (Godot), Alpha immer voll (Fensterinhalte haben oft Alpha 0).
    public static void Tausche(byte[] px, int n) {
        if (px == null) return;
        n = Math.Min(n, px.Length);
        for (int i = 0; i + 3 < n; i += 4) {
            byte b = px[i];
            px[i] = px[i + 2];
            px[i + 2] = b;
            px[i + 3] = 255;
        }
    }

    // Mittlere Farbe eines RGBA-Bilds aus einem Raster von höchstens 32 × 18 Punkten (Mitte jedes
    // Felds; billig auch bei 60 Bildern je Sekunde). Mit FARBE_GUELTIG; ohne Bild 0.
    public static uint Mittel(byte[] rgba, int w, int h) {
        if (rgba == null || w <= 0 || h <= 0 || (long)w * h * 4 > rgba.Length) return 0;
        int nx = Math.Min(32, w), ny = Math.Min(18, h);
        long r = 0, g = 0, b = 0;
        for (int j = 0; j < ny; j++) {
            int y = (int)(((long)j * 2 + 1) * h / (ny * 2));
            for (int i = 0; i < nx; i++) {
                int x = (int)(((long)i * 2 + 1) * w / (nx * 2));
                int o = (y * w + x) * 4;
                r += rgba[o]; g += rgba[o + 1]; b += rgba[o + 2];
            }
        }
        long n = (long)nx * ny;
        return FARBE_GUELTIG | ((uint)(r / n) << 16) | ((uint)(g / n) << 8) | (uint)(b / n);
    }

    // Fast schwarz, wie Uzai es zählt (Helligkeit nach Rec. 709 unter 0,012)?
    public static bool Schwarz(uint farbe) {
        if ((farbe & FARBE_GUELTIG) == 0) return false;
        double l = (0.2126 * ((farbe >> 16) & 255) + 0.7152 * ((farbe >> 8) & 255) + 0.0722 * (farbe & 255)) / 255.0;
        return l < 0.012;
    }

    public static string Hex(uint farbe) {
        if ((farbe & FARBE_GUELTIG) == 0) return "unbekannt";
        return "#" + (farbe & 0xFFFFFF).ToString("X6");
    }

    // 16-Bit-Gleitkomma (IEEE 754 half) → float.
    public static float Halb(ushort h) {
        int s = (h >> 15) & 1, e = (h >> 10) & 31, m = h & 1023;
        float v;
        if (e == 0) v = m / 16777216f;
        else if (e == 31) v = m == 0 ? float.PositiveInfinity : float.NaN;
        else v = (1f + m / 1024f) * (float)Math.Pow(2.0, e - 15);
        return s == 1 ? -v : v;
    }

    // Linear (0..1) → sRGB (0..255).
    public static byte Srgb(float lin) {
        if (!(lin > 0f)) return 0;
        if (lin >= 1f) return 255;
        double c = lin <= 0.0031308 ? lin * 12.92 : 1.055 * Math.Pow(lin, 1.0 / 2.4) - 0.055;
        return (byte)Math.Max(0, Math.Min(255, (int)(c * 255.0 + 0.5)));
    }

    // scRGB (1,0 = 80 nits) → 0..1 für SDR: SDR-Weiß (weiss, z. B. 2,5 bei 200 nits) wird fast 1,0;
    // bis KNIE bleibt alles, wie es ist, Lichter darüber laufen stetig und weich gegen 1,0 aus.
    public const float KNIE = 0.9f;
    public static float Abbilden(float v, float weiss) {
        if (!(v > 0f)) return 0f;
        float x = v / (weiss > 0.1f ? weiss : 1f);
        if (x <= KNIE) return x;
        if (float.IsInfinity(x)) return 1f;
        return KNIE + (1f - KNIE) * (1f - (float)Math.Exp(-(x - KNIE) / (1f - KNIE)));
    }

    static float[] halbTafel;
    static byte[] srgbTafel;

    static void Tafeln() {
        if (srgbTafel != null) return;
        float[] h = new float[65536];
        for (int i = 0; i < 65536; i++) h[i] = Halb((ushort)i);
        byte[] s = new byte[4096];
        for (int i = 0; i < 4096; i++) s[i] = Srgb(i / 4095f);
        halbTafel = h;
        srgbTafel = s;
    }

    static byte Kanal(int h, float weiss) {
        float l = Abbilden(halbTafel[h & 0xFFFF], weiss);
        return srgbTafel[Math.Max(0, Math.Min(4095, (int)(l * 4095f + 0.5f)))];
    }

    // n Pixel R16G16B16A16-Gleitkomma (scRGB) → RGBA (sRGB, 8 Bit, Alpha voll). Nie über ein Ende hinaus.
    public static void HalbZuRgba(byte[] src, int n, byte[] dst, float weiss) {
        if (src == null || dst == null) return;
        n = Math.Min(n, Math.Min(src.Length / 8, dst.Length / 4));
        Tafeln();
        for (int i = 0; i < n; i++) {
            int o = i * 8, d = i * 4;
            dst[d] = Kanal(src[o] | (src[o + 1] << 8), weiss);
            dst[d + 1] = Kanal(src[o + 2] | (src[o + 3] << 8), weiss);
            dst[d + 2] = Kanal(src[o + 4] | (src[o + 5] << 8), weiss);
            dst[d + 3] = 255;
        }
    }

    public static string FormatName(int f) {
        switch (f) {
            case FMT_BGRA: return "B8G8R8A8";
            case FMT_FP16: return "R16G16B16A16-Gleitkomma (scRGB)";
            case 28: return "R8G8B8A8";
            case 24: return "R10G10B10A2";
            case 0: return "–";
        }
        return "Format " + f;
    }

    // SDR-Weiß in scRGB: bei HDR aus Windows (nits / 80; unbekannt: 200 nits), sonst 1,0.
    public static float Weiss(bool hdr, int weissNits) {
        if (!hdr) return 1f;
        return weissNits >= 80 && weissNits <= 10000 ? weissNits / 80f : 2.5f;
    }

    // Größe des Spiegels: Seitenverhältnis der Quelle, eingepasst in maxW × maxH, mindestens 64 × 36.
    public static void SpiegelGroesse(int qw, int qh, int maxW, int maxH, out int w, out int h) {
        maxW = Math.Max(64, Math.Min(MAX_SEITE, maxW));
        maxH = Math.Max(36, Math.Min(MAX_SEITE, maxH));
        if (qw <= 0 || qh <= 0) { w = maxW; h = maxH; return; }
        w = maxW;
        h = (int)Math.Round((double)maxW * qh / qw);
        if (h > maxH) { h = maxH; w = (int)Math.Round((double)maxH * qw / qh); }
        w = Math.Max(64, Math.Min(maxW, w));
        h = Math.Max(36, Math.Min(maxH, h));
    }

    // Deckt das Rechteck (l, t, r, b) den Bildschirm (bis auf 2 Pixel)?
    public static bool Deckt(int l, int t, int r, int b, int ml, int mt, int mr, int mb) {
        return mr - ml > 0 && l <= ml + 2 && t <= mt + 2 && r >= mr - 2 && b >= mb - 2;
    }

    // Zustand des Spielfensters als Text für launch.log.
    public static string ZustandText(bool gibts, bool ikon, bool sichtbar, int versteckt, int w, int h, int mw, int mh, bool deckt,
            uint schutz, int quns, string klasse, uint stil) {
        if (!gibts) return "Fenster gibt es nicht (mehr)";
        var sb = new StringBuilder();
        sb.Append("Fenster ").Append(w).Append('×').Append(h);
        sb.Append(deckt ? " (deckt den Bildschirm " : " (Bildschirm ").Append(mw).Append('×').Append(mh).Append(')');
        sb.Append(ikon ? ", minimiert" : ", nicht minimiert");
        if (!sichtbar) sb.Append(", unsichtbar");
        if (versteckt != 0) sb.Append(", von Windows versteckt (cloaked ").Append(versteckt).Append(')');
        if (schutz == 0x11) sb.Append(", von der Aufnahme ausgenommen (WDA_EXCLUDEFROMCAPTURE)");
        else if (schutz != 0) sb.Append(", Aufnahmeschutz (Display-Affinity ").Append(schutz).Append(')');
        sb.Append(", Stil 0x").Append(stil.ToString("X8"));
        if (!string.IsNullOrEmpty(klasse)) sb.Append(", Klasse ").Append(klasse.Length > 40 ? klasse.Substring(0, 40) : klasse);
        switch (quns) {
            case 3: sb.Append("; Windows meldet exklusives Vollbild (D3D)"); break;
            case 2: sb.Append("; Windows meldet ein Vollbild-Programm vorn"); break;
            case 4: sb.Append("; Präsentationsmodus"); break;
            case 7: sb.Append("; App im Vollbild vorn"); break;
            case 1: sb.Append("; Bildschirm gesperrt"); break;
            default: sb.Append("; kein exklusives Vollbild"); break;
        }
        return sb.ToString();
    }

    // Grafikkarte und HDR als Text für launch.log.
    public static string InfoText(string karte, bool desSpiels, string gdi, bool hatOd, int farbraum, int bits, bool winOk, bool winHdr,
            int weissNits, bool hdr, bool spiegel) {
        var sb = new StringBuilder();
        sb.Append("Grafikkarte ").Append(string.IsNullOrEmpty(karte) ? "Standard" : karte);
        sb.Append(desSpiels ? " (am Bildschirm des Spiels" + (string.IsNullOrEmpty(gdi) ? "" : " " + gdi) + ")" : " (Standard – Bildschirm des Spiels nicht gefunden)");
        sb.Append(" · HDR ").Append(hdr ? "an" : "aus");
        var teile = new System.Collections.Generic.List<string>();
        if (hatOd) teile.Add("DXGI-Farbraum " + farbraum + (farbraum == FARBRAUM_HDR10 ? " = HDR10" : farbraum == 0 ? " = SDR" : "") + ", " + bits + " Bit");
        if (winOk) teile.Add("Windows: HDR " + (winHdr ? "an" : "aus") + (weissNits > 0 ? ", SDR-Weiß " + weissNits + " nits" : ""));
        if (teile.Count > 0) sb.Append(" (").Append(string.Join("; ", teile.ToArray())).Append(')');
        sb.Append(" · Pool ").Append(FormatName(hdr ? FMT_FP16 : FMT_BGRA));
        if (spiegel) sb.Append(" · über den Spiegel (DWM-Vorschau in einem Helferfenster)");
        return sb.ToString();
    }

    // Erstes Bild als Text für launch.log.
    public static string BildText(int fmt, int tw, int th, int cw, int ch, int stufe, int lw, int lh, uint farbe) {
        return "Format " + FormatName(fmt) + ", Fläche " + tw + "×" + th + ", Fensterinhalt " + cw + "×" + ch + ", Mip-Stufe " + stufe + " → " + lw + "×" + lh
            + ", mittlere Farbe " + Hex(farbe) + (Schwarz(farbe) ? " (schwarz)" : "");
    }

    static void Put(byte[] b, int o, uint v) {
        b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); b[o + 2] = (byte)(v >> 16); b[o + 3] = (byte)(v >> 24);
    }

    public static byte[] KopfBytes(uint seq, int w, int h) { return KopfBytes(seq, w, h, 0); }

    public static byte[] KopfBytes(uint seq, int w, int h, uint farbe) {
        byte[] k = new byte[KOPF];
        if (w < 0 || h < 0 || w > MAX_SEITE || h > MAX_SEITE || (long)w * h > MAX_PX) { w = 0; h = 0; farbe = 0; }
        Put(k, 0, MAGIC);
        Put(k, 4, VERSION);
        Put(k, 8, seq);
        Put(k, 12, (uint)w);
        Put(k, 16, (uint)h);
        Put(k, 20, (uint)(w * 4));
        Put(k, 24, (uint)(w * 4 * h));
        Put(k, 28, farbe);
        return k;
    }

    public static long Dateigroesse() { return KOPF + (long)MAX_PX * 4; }

    public static uint Schreibe(Stream fs, uint seq, int w, int h, byte[] rgba) { return Schreibe(fs, seq, w, h, rgba, 0); }

    // Ein Bild schreiben (Seqlock): Kopf mit ungerader Nummer, Pixel, Kopf mit der nächsten geraden.
    // Uzai nimmt ein Bild nur, wenn die Nummer vor und nach dem Lesen gleich und gerade ist.
    // Rückgabe: die neue (gerade) Nummer; bei falschen Größen bleibt alles, wie es war.
    public static uint Schreibe(Stream fs, uint seq, int w, int h, byte[] rgba, uint farbe) {
        if (fs == null || rgba == null || w <= 0 || h <= 0 || w > MAX_SEITE || h > MAX_SEITE || (long)w * h > MAX_PX || rgba.Length < w * h * 4) return seq;
        uint s = (seq | 1u);
        if (s == seq) s += 2;
        fs.Position = 0;
        fs.Write(KopfBytes(s, w, h, farbe), 0, KOPF);
        fs.Write(rgba, 0, w * h * 4);
        fs.Position = 0;
        fs.Write(KopfBytes(s + 1, w, h, farbe), 0, KOPF);
        fs.Flush();
        return s + 1;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);

    // Zwischendatei: temporär markiert (Windows schreibt sie möglichst nie auf die Platte), feste Größe.
    public static FileStream Oeffne(string pfad) {
        // GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | WRITE | DELETE, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY
        SafeFileHandle h = CreateFileW(pfad, 0xC0000000, 0x7, IntPtr.Zero, 2, 0x100, IntPtr.Zero);
        if (h.IsInvalid) throw new IOException("Zwischendatei: " + Marshal.GetLastWin32Error());
        FileStream fs = new FileStream(h, FileAccess.ReadWrite, 1);
        fs.SetLength(Dateigroesse());
        fs.Position = 0;
        fs.Write(KopfBytes(0, 0, 0), 0, KOPF);
        fs.Flush();
        return fs;
    }

    // --- Windows Graphics Capture über die rohen COM-Schnittstellen (C# 5, ohne .winmd) -------

    [DllImport("combase.dll")] static extern int RoInitialize(int t);
    [DllImport("combase.dll")] static extern void RoUninitialize();
    [DllImport("combase.dll", CharSet = CharSet.Unicode)] static extern int WindowsCreateString(string s, int n, out IntPtr h);
    [DllImport("combase.dll")] static extern int WindowsDeleteString(IntPtr h);
    [DllImport("combase.dll")] static extern int RoGetActivationFactory(IntPtr cls, ref Guid iid, out IntPtr f);
    [DllImport("d3d11.dll")] static extern int D3D11CreateDevice(IntPtr adapter, int type, IntPtr sw, uint flags, IntPtr levels, uint n, uint sdk, out IntPtr dev, out int level, out IntPtr ctx);
    [DllImport("d3d11.dll")] static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgi, out IntPtr insp);
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid iid, out IntPtr f);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern int GetWindowLongW(IntPtr h, int i);
    [DllImport("user32.dll")] static extern bool GetWindowDisplayAffinity(IntPtr h, out uint a);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfoW(IntPtr m, ref MONINFO mi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int n);
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int s);
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint np, out uint nm);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint np, [Out] byte[] paths, ref uint nm, [Out] byte[] modes, IntPtr topo);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo([In, Out] byte[] packet);
    // Spiegel: eigenes Fenster, in das Windows das Spiel zeichnet (DWM-Vorschau).
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassExW(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool PeekMessageW(out MSG m, IntPtr h, uint min, uint max, uint remove);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessageW(ref MSG m);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr mod, string name);
    [DllImport("dwmapi.dll")] static extern int DwmRegisterThumbnail(IntPtr dest, IntPtr src, out IntPtr thumb);
    [DllImport("dwmapi.dll")] static extern int DwmUnregisterThumbnail(IntPtr thumb);
    [DllImport("dwmapi.dll")] static extern int DwmUpdateThumbnailProperties(IntPtr thumb, ref THUMB props);
    [DllImport("dwmapi.dll")] static extern int DwmQueryThumbnailSourceSize(IntPtr thumb, out SIZE size);
    [DllImport("gdi32.dll")] static extern int D3DKMTSetProcessSchedulingPriorityClass(IntPtr process, int priority);

    static Guid IID_ItemInterop = new Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    static Guid IID_Item = new Guid("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    static Guid IID_PoolStatics2 = new Guid("589B103F-6BBC-5DF5-A991-02E28B3B66D5");
    static Guid IID_SessionStatics = new Guid("2224A540-5974-49AA-B232-0882536F4CB5");
    static Guid IID_Session2 = new Guid("2C39AE40-7D2E-5044-804E-8B6799D4CF9E");
    static Guid IID_Session3 = new Guid("F2CDD966-22AE-5EA1-9596-3A289344C3BE");
    static Guid IID_Closable = new Guid("30D5A829-7FA4-4026-83BB-D75BAE4EA99E");
    static Guid IID_DxgiAccess = new Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");
    static Guid IID_Tex2D = new Guid("6F15AAF2-D208-4E89-9AB4-489535D34F9C");
    static Guid IID_DxgiDevice = new Guid("54EC77FA-1377-44E6-8C32-88FD5F44C84C");
    static Guid IID_RtDevice = new Guid("A37624AB-8D5F-4650-9D3E-9EAE3D9BC670");
    static Guid IID_Factory1 = new Guid("770AAE78-F26F-4DBA-A829-253C83D1B387");
    static Guid IID_Output6 = new Guid("068346E8-AAEC-4B84-ADD7-137F513F77A1");

    [StructLayout(LayoutKind.Sequential)]
    public struct TexDesc { public uint W, H, Mips, Array, Format, SampleCount, SampleQuality, Usage, Bind, Cpu, Misc; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Box { public uint L, T, F, R, B, Bk; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Mapped { public IntPtr Data; public uint Row, Depth; }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MONINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct AdDesc { [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Name; public uint Vendor, Device, SubSys, Rev; public UIntPtr Ded, DedSys, Shared; public uint LuidLo; public int LuidHi; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct OutDesc { [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Name; public RECT Desktop; public int Attached, Rotation; public IntPtr Monitor; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct OutDesc1 {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Name; public RECT Desktop; public int Attached, Rotation; public IntPtr Monitor;
        public uint Bits; public int ColorSpace; public float Rx, Ry, Gx, Gy, Bx, By, Wx, Wy, MinLum, MaxLum, MaxFull;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WNDCLASSEX { public uint cbSize, style; public IntPtr lpfnWndProc; public int cbClsExtra, cbWndExtra; public IntPtr hInstance, hIcon, hCursor, hbrBackground; public string lpszMenuName, lpszClassName; public IntPtr hIconSm; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }
    [StructLayout(LayoutKind.Sequential)]
    public struct THUMB { public uint dwFlags; public RECT rcDestination, rcSource; public byte opacity; public int fVisible, fSourceClientAreaOnly; }
    [StructLayout(LayoutKind.Sequential)]
    public struct SIZE { public int cx, cy; }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnV(IntPtr s);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnOutP(IntPtr s, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnOutB(IntPtr s, out byte b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnOutL(IntPtr s, out long v);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnB(IntPtr s, byte b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnHwnd(IntPtr s, IntPtr h, ref Guid g, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnGuidP(IntPtr s, ref Guid g, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnPool(IntPtr s, IntPtr dev, int fmt, int n, long size, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnRecreate(IntPtr s, IntPtr dev, int fmt, int n, long size);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnPP(IntPtr s, IntPtr a, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnTex(IntPtr s, ref TexDesc d, IntPtr init, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnSrv(IntPtr s, IntPtr res, IntPtr desc, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnDesc(IntPtr s, out TexDesc d);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnCopyBox(IntPtr s, IntPtr dst, uint dsub, uint x, uint y, uint z, IntPtr src, uint ssub, ref Box b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnCopy(IntPtr s, IntPtr dst, uint dsub, uint x, uint y, uint z, IntPtr src, uint ssub, IntPtr b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnMips(IntPtr s, IntPtr srv);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnMap(IntPtr s, IntPtr res, uint sub, int typ, uint flags, out Mapped m);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void FnUnmap(IntPtr s, IntPtr res, uint sub);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnEnum(IntPtr s, uint i, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnAdDesc(IntPtr s, out AdDesc d);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnOutDesc(IntPtr s, out OutDesc d);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int FnOutDesc1(IntPtr s, out OutDesc1 d);

    static T Vt<T>(IntPtr p, int i) where T : class {
        IntPtr vt = Marshal.ReadIntPtr(p);
        return Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vt, i * IntPtr.Size), typeof(T)) as T;
    }

    static void Los(ref IntPtr p) { if (p != IntPtr.Zero) { Marshal.Release(p); p = IntPtr.Zero; } }

    // WinRT-Objekt schließen (IClosable.Close), dann loslassen.
    static void Zu(ref IntPtr p) {
        if (p == IntPtr.Zero) return;
        IntPtr c;
        Guid g = IID_Closable;
        if (Marshal.QueryInterface(p, ref g, out c) >= 0) {
            try { Vt<FnV>(c, 6)(c); } catch { }
            Marshal.Release(c);
        }
        Los(ref p);
    }

    static IntPtr Fabrik(string klasse, Guid iid) {
        IntPtr hs, f;
        if (WindowsCreateString(klasse, klasse.Length, out hs) < 0) return IntPtr.Zero;
        try {
            if (RoGetActivationFactory(hs, ref iid, out f) < 0) return IntPtr.Zero;
            return f;
        } finally { WindowsDeleteString(hs); }
    }

    static void Pruefe(int hr, string was) { if (hr < 0) throw new Exception(was + " " + hr.ToString("X8")); }

    static long Groesse(int w, int h) { return (long)(uint)w | ((long)h << 32); }

    // --- Zustand ----------------------------------------------------------------------------

    static readonly object sperre = new object();
    static Thread faden;
    static volatile bool halt;
    static volatile int stand;          // 0 startet, 3 Aufnahme läuft, 1 Bilder kommen, 2 beendet, -1 Fehler
    static volatile string grund = "";
    static volatile bool randAus;
    static volatile int bilder, bw, bh, format, schwarzFolge;
    static volatile string info = "", erstes = "", wechsel = "";
    static volatile bool spiegelAktiv;
    static long arbeitTicks;            // Zeit für Kopieren, Lesen, Umrechnen, Schreiben (Stopwatch-Ticks)
    static int puls;
    static long zHwnd, zBezug;
    static bool zSpiegel;
    static int zW, zH, zFps;
    static string zDatei = "";

    public static int Stand() { return stand; }
    public static string Grund() { return grund; }
    public static bool RandAus() { return randAus; }
    public static int Bilder() { return bilder; }
    public static int Breite() { return bw; }
    public static int Hoehe() { return bh; }
    public static int Format() { return format; }
    public static string Info() { return info; }
    public static string Erstes() { return erstes; }
    public static string Wechsel() { return wechsel; }
    public static int SchwarzFolge() { return schwarzFolge; }
    public static bool Spiegel() { return spiegelAktiv; }
    // Mittlere Arbeit des Helfers je Bild in ms (Kopieren auf die CPU, Umrechnen, Schreiben).
    public static double Ms() {
        int n = bilder;
        return n <= 0 ? 0.0 : Interlocked.Read(ref arbeitTicks) * 1000.0 / Stopwatch.Frequency / n;
    }
    public static bool Laeuft() { lock (sperre) { return faden != null && faden.IsAlive; } }

    // Unterstützt Windows das hier (ab Windows 10 1903)?
    public static bool Unterstuetzt() {
        IntPtr f = IntPtr.Zero;
        try {
            f = Fabrik("Windows.Graphics.Capture.GraphicsCaptureSession", IID_SessionStatics);
            if (f == IntPtr.Zero) return false;
            byte b;
            return Vt<FnOutB>(f, 6)(f, out b) >= 0 && b != 0;
        } catch { return false; }
        finally { Los(ref f); }
    }

    // Zustand eines Fensters für launch.log (nur lesen).
    public static string Zustand(long hwnd) {
        try {
            IntPtr h = new IntPtr(hwnd);
            if (hwnd == 0 || !IsWindow(h)) return ZustandText(false, false, false, 0, 0, 0, 0, 0, false, 0, 0, "", 0);
            RECT r;
            if (!GetWindowRect(h, out r)) r = new RECT();
            MONINFO mi = new MONINFO();
            mi.cbSize = Marshal.SizeOf(typeof(MONINFO));
            IntPtr mon = MonitorFromWindow(h, 2);
            if (mon == IntPtr.Zero || !GetMonitorInfoW(mon, ref mi)) mi = new MONINFO();
            int cloak;
            if (DwmGetWindowAttribute(h, 14, out cloak, 4) != 0) cloak = 0;
            uint aff;
            if (!GetWindowDisplayAffinity(h, out aff)) aff = 0;
            int q = 0;
            try { if (SHQueryUserNotificationState(out q) != 0) q = 0; } catch { q = 0; }
            var cls = new StringBuilder(128);
            GetClassNameW(h, cls, 128);
            RECT m = mi.rcMonitor;
            return ZustandText(true, IsIconic(h), IsWindowVisible(h), cloak, r.Right - r.Left, r.Bottom - r.Top, m.Right - m.Left, m.Bottom - m.Top,
                Deckt(r.Left, r.Top, r.Right, r.Bottom, m.Left, m.Top, m.Right, m.Bottom), aff, q, cls.ToString(), (uint)GetWindowLongW(h, -16));
        } catch (Exception e) { return "Zustand nicht lesbar: " + e.Message; }
    }

    // Uzai nimmt sich auf der Grafikkarte selbst zurück, solange es neben einem Spiel zeichnet
    // (1 = unter normal, 2 = normal). Nur für den übergebenen eigenen Prozess (Prüfung im Befehl).
    public static bool GpuStufe(IntPtr prozess, bool leise) {
        try { return D3DKMTSetProcessSchedulingPriorityClass(prozess, leise ? 1 : 2) == 0; } catch { return false; }
    }

    // Starten bzw. – gleiche Werte, läuft schon – nur das Lebenszeichen auffrischen.
    public static void Start(long hwnd, int maxW, int maxH, int fps, string datei) { Start(hwnd, maxW, maxH, fps, datei, 0, false); }

    public static void Start(long hwnd, int maxW, int maxH, int fps, string datei, long bezug, bool spiegel) {
        lock (sperre) {
            puls = Environment.TickCount;
            if (faden != null && faden.IsAlive && zHwnd == hwnd && zW == maxW && zH == maxH && zFps == fps && zDatei == datei
                && zSpiegel == spiegel && (!spiegel || zBezug == bezug)) return;
            StopIntern();
            zHwnd = hwnd; zW = maxW; zH = maxH; zFps = Math.Max(1, Math.Min(60, fps)); zDatei = datei; zBezug = bezug; zSpiegel = spiegel;
            halt = false; stand = 0; grund = ""; bilder = 0; bw = 0; bh = 0; randAus = false; format = 0; schwarzFolge = 0;
            info = ""; erstes = ""; wechsel = ""; spiegelAktiv = false;
            Interlocked.Exchange(ref arbeitTicks, 0);
            faden = new Thread(Lauf);
            faden.IsBackground = true;
            faden.Priority = ThreadPriority.BelowNormal;
            faden.Start();
        }
    }

    public static void Stop() { lock (sperre) { StopIntern(); } }

    static void StopIntern() {
        halt = true;
        if (faden != null) { faden.Join(2000); faden = null; }
    }

    static void Fehler(string g) { grund = g.Length > 160 ? g.Substring(0, 160) : g; stand = -1; }

    // Grafikkarte, an der der Bildschirm hmon hängt (oder IntPtr.Zero), samt Angaben zum Bildschirm.
    static IntPtr KarteFuer(IntPtr hmon, out string name, out OutDesc1 aus, out bool hatAus, out string gdi) {
        name = ""; aus = new OutDesc1(); hatAus = false; gdi = "";
        IntPtr fab = IntPtr.Zero, treffer = IntPtr.Zero;
        Guid g = IID_Factory1;
        if (hmon == IntPtr.Zero || CreateDXGIFactory1(ref g, out fab) < 0 || fab == IntPtr.Zero) return IntPtr.Zero;
        try {
            for (uint a = 0; a < 16 && treffer == IntPtr.Zero; a++) {
                IntPtr ad;
                if (Vt<FnEnum>(fab, 12)(fab, a, out ad) < 0 || ad == IntPtr.Zero) break;
                for (uint o = 0; o < 16 && treffer == IntPtr.Zero; o++) {
                    IntPtr op;
                    if (Vt<FnEnum>(ad, 7)(ad, o, out op) < 0 || op == IntPtr.Zero) break;
                    try {
                        OutDesc od;
                        if (Vt<FnOutDesc>(op, 7)(op, out od) >= 0 && od.Monitor == hmon) {
                            treffer = ad;
                            gdi = od.Name ?? "";
                            IntPtr o6;
                            Guid g6 = IID_Output6;
                            if (Marshal.QueryInterface(op, ref g6, out o6) >= 0) {
                                try { hatAus = Vt<FnOutDesc1>(o6, 27)(o6, out aus) >= 0; } finally { Marshal.Release(o6); }
                            }
                        }
                    } finally { Marshal.Release(op); }
                }
                if (treffer == IntPtr.Zero) Marshal.Release(ad);
            }
            if (treffer != IntPtr.Zero) {
                AdDesc d;
                if (Vt<FnAdDesc>(treffer, 8)(treffer, out d) >= 0) name = (d.Name ?? "").Trim();
            }
            return treffer;
        } catch {
            if (treffer != IntPtr.Zero) Marshal.Release(treffer);
            return IntPtr.Zero;
        } finally { Marshal.Release(fab); }
    }

    // HDR laut den Anzeige-Einstellungen von Windows für den Bildschirm gdi („\\.\DISPLAY1“):
    // an/aus und SDR-Weiß in nits (0 = unbekannt). false: nicht gefunden.
    static bool FarbeVonWindows(string gdi, out bool an, out int weissNits) {
        an = false; weissNits = 0;
        uint np, nm;
        if (GetDisplayConfigBufferSizes(2, out np, out nm) != 0 || np == 0 || np > 64 || nm > 256) return false;
        byte[] p = new byte[72 * np], m = new byte[64 * Math.Max(1u, nm)];
        if (QueryDisplayConfig(2, ref np, p, ref nm, m, IntPtr.Zero) != 0) return false;
        for (int i = 0; i < (int)np; i++) {
            int o = i * 72;
            byte[] q = new byte[84];
            Put(q, 0, 1); Put(q, 4, 84);
            Array.Copy(p, o, q, 8, 12);
            if (DisplayConfigGetDeviceInfo(q) != 0) continue;
            string n = Encoding.Unicode.GetString(q, 20, 64);
            int z = n.IndexOf('\0');
            if (z >= 0) n = n.Substring(0, z);
            if (!string.Equals(n, gdi, StringComparison.OrdinalIgnoreCase)) continue;
            byte[] c = new byte[32];
            Put(c, 0, 9); Put(c, 4, 32);
            Array.Copy(p, o + 20, c, 8, 12);
            if (DisplayConfigGetDeviceInfo(c) == 0) an = (BitConverter.ToUInt32(c, 20) & 2u) != 0;
            byte[] wl = new byte[24];
            Put(wl, 0, 11); Put(wl, 4, 24);
            Array.Copy(p, o + 20, wl, 8, 12);
            if (DisplayConfigGetDeviceInfo(wl) == 0) weissNits = (int)(BitConverter.ToUInt32(wl, 20) * 80L / 1000L);
            return true;
        }
        return false;
    }

    // --- Spiegel ----------------------------------------------------------------------------

    static bool klasseDa;
    const string SPIEGEL_KLASSE = "UzaiFernsehSpiegel";

    // Unsichtbarer Besitzer (kein Taskleisten-Eintrag) und das Spiegelfenster gleich unter Uzai
    // (bezug): ohne Fokus, ohne Eingaben, nur die DWM-Vorschau des Spiels darin.
    static IntPtr SpiegelAn(IntPtr spiel, IntPtr bezug, int maxW, int maxH, out IntPtr thumb, out IntPtr besitzer, out SIZE quelle) {
        thumb = IntPtr.Zero; besitzer = IntPtr.Zero; quelle = new SIZE();
        IntPtr inst = GetModuleHandleW(null);
        if (!klasseDa) {
            WNDCLASSEX wc = new WNDCLASSEX();
            wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
            wc.lpfnWndProc = GetProcAddress(GetModuleHandleW("user32.dll"), "DefWindowProcW");
            wc.hInstance = inst;
            wc.lpszClassName = SPIEGEL_KLASSE;
            if (wc.lpfnWndProc == IntPtr.Zero || RegisterClassExW(ref wc) == 0) { grund = "Spiegel: Fensterklasse"; return IntPtr.Zero; }
            klasseDa = true;
        }
        // WS_POPUP; Spiegel: WS_EX_NOACTIVATE | WS_EX_TRANSPARENT (keine Maus), besessen (kein Taskleisten-Eintrag).
        besitzer = CreateWindowExW(0x08000000u, SPIEGEL_KLASSE, "", 0x80000000u, 0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, inst, IntPtr.Zero);
        if (besitzer == IntPtr.Zero) { grund = "Spiegel: Besitzerfenster"; return IntPtr.Zero; }
        IntPtr w = CreateWindowExW(0x08000000u | 0x00000020u, SPIEGEL_KLASSE, "Uzai Fernseher", 0x80000000u, 0, 0, 64, 36, besitzer, IntPtr.Zero, inst, IntPtr.Zero);
        if (w == IntPtr.Zero) { grund = "Spiegel: Fenster"; return IntPtr.Zero; }
        IntPtr th;
        if (DwmRegisterThumbnail(w, spiel, out th) != 0 || th == IntPtr.Zero) { DestroyWindow(w); grund = "Spiegel: DWM-Vorschau"; return IntPtr.Zero; }
        thumb = th;
        SpiegelSetzen(w, th, bezug, maxW, maxH, ref quelle, true);
        return w;
    }

    // Größe nach der Quelle, Platz gleich unter Uzai auf dessen Bildschirm (dort deckt Uzai ihn ganz).
    static void SpiegelSetzen(IntPtr w, IntPtr th, IntPtr bezug, int maxW, int maxH, ref SIZE quelle, bool immer) {
        SIZE q;
        if (DwmQueryThumbnailSourceSize(th, out q) != 0) q = new SIZE();
        bool neu = immer || q.cx != quelle.cx || q.cy != quelle.cy;
        // SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOOWNERZORDER (+ SWP_NOSIZE | SWP_NOMOVE, wenn nur die Ebene)
        if (neu) {
            quelle = q;
            int sw, sh;
            SpiegelGroesse(q.cx, q.cy, maxW, maxH, out sw, out sh);
            THUMB p = new THUMB();
            p.dwFlags = 0x1u | 0x4u | 0x8u | 0x10u;
            p.rcDestination.Right = sw;
            p.rcDestination.Bottom = sh;
            p.opacity = 255;
            p.fVisible = 1;
            p.fSourceClientAreaOnly = 1;
            DwmUpdateThumbnailProperties(th, ref p);
            MONINFO mi = new MONINFO();
            mi.cbSize = Marshal.SizeOf(typeof(MONINFO));
            IntPtr mon = MonitorFromWindow(bezug, 2);
            if (mon == IntPtr.Zero || !GetMonitorInfoW(mon, ref mi)) mi = new MONINFO();
            SetWindowPos(w, IsWindow(bezug) ? bezug : new IntPtr(1), mi.rcMonitor.Left, mi.rcMonitor.Top, sw, sh, 0x0010u | 0x0040u | 0x0200u);
        } else if (IsWindow(bezug) && GetWindow(bezug, 2) != w) {
            SetWindowPos(w, bezug, 0, 0, 0, 0, 0x0001u | 0x0002u | 0x0010u | 0x0200u);
        }
    }

    static void Nachrichten() {
        MSG m;
        int n = 0;
        while (n++ < 64 && PeekMessageW(out m, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref m); DispatchMessageW(ref m); }
    }

    // --- Aufnahme ---------------------------------------------------------------------------

    static void Lauf() {
        IntPtr dev = IntPtr.Zero, ctx = IntPtr.Zero, dxgi = IntPtr.Zero, rtDev = IntPtr.Zero, item = IntPtr.Zero, karte = IntPtr.Zero;
        IntPtr pool = IntPtr.Zero, sess = IntPtr.Zero, mip = IntPtr.Zero, srv = IntPtr.Zero, stage = IntPtr.Zero, f = IntPtr.Zero;
        IntPtr spWnd = IntPtr.Zero, spThumb = IntPtr.Zero, spBesitzer = IntPtr.Zero;
        FileStream fs = null;
        int ro = RoInitialize(1);
        try {
            if (!Unterstuetzt()) { Fehler("nicht unterstützt"); return; }
            IntPtr spiel = new IntPtr(zHwnd), bezug = new IntPtr(zBezug);
            // Bildschirm des Spiels: Grafikkarte daran, HDR an oder aus.
            string kname = "", gdi = "";
            OutDesc1 od = new OutDesc1();
            bool hatOd = false, winOk = false, winHdr = false;
            int weissNits = 0;
            try { karte = KarteFuer(MonitorFromWindow(spiel, 2), out kname, out od, out hatOd, out gdi); } catch { karte = IntPtr.Zero; }
            try { if (gdi != "") winOk = FarbeVonWindows(gdi, out winHdr, out weissNits); } catch { winOk = false; }
            bool hdr = (hatOd && od.ColorSpace == FARBRAUM_HDR10) || (winOk && winHdr);
            float weiss = Weiss(hdr, weissNits);
            int fmt = hdr ? FMT_FP16 : FMT_BGRA;
            info = InfoText(kname, karte != IntPtr.Zero, gdi, hatOd, od.ColorSpace, (int)od.Bits, winOk, winHdr, weissNits, hdr, zSpiegel);
            int fl;
            // Mit eigener Karte: D3D_DRIVER_TYPE_UNKNOWN (0), sonst Hardware (1) auf der Standardkarte.
            Pruefe(D3D11CreateDevice(karte, karte != IntPtr.Zero ? 0 : 1, IntPtr.Zero, 0x20, IntPtr.Zero, 0, 7, out dev, out fl, out ctx), "D3D11");
            Guid g = IID_DxgiDevice;
            Pruefe(Marshal.QueryInterface(dev, ref g, out dxgi), "DXGI");
            IntPtr insp;
            Pruefe(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out insp), "WinRT-Gerät");
            g = IID_RtDevice;
            int hrq = Marshal.QueryInterface(insp, ref g, out rtDev);
            Marshal.Release(insp);
            Pruefe(hrq, "IDirect3DDevice");
            // Rückfall Spiegel: Windows zeichnet das Spiel in ein eigenes Fenster, aufgenommen wird dieses.
            IntPtr quelleWnd = spiel;
            SIZE spQuelle = new SIZE();
            if (zSpiegel) {
                spWnd = SpiegelAn(spiel, bezug, zW, zH, out spThumb, out spBesitzer, out spQuelle);
                if (spWnd == IntPtr.Zero) { Fehler(grund == "" ? "Spiegel" : grund); return; }
                quelleWnd = spWnd;
                spiegelAktiv = true;
                Nachrichten();
            }
            f = Fabrik("Windows.Graphics.Capture.GraphicsCaptureItem", IID_ItemInterop);
            if (f == IntPtr.Zero) { Fehler("keine Fabrik"); return; }
            g = IID_Item;
            Pruefe(Vt<FnHwnd>(f, 3)(f, quelleWnd, ref g, out item), zSpiegel ? "Spiegelfenster" : "Fenster");
            Los(ref f);
            long gr;
            Pruefe(Vt<FnOutL>(item, 7)(item, out gr), "Größe");
            int pw = Math.Max(1, (int)(gr & 0xFFFFFFFF)), ph = Math.Max(1, (int)(gr >> 32));
            f = Fabrik("Windows.Graphics.Capture.Direct3D11CaptureFramePool", IID_PoolStatics2);
            if (f == IntPtr.Zero) { Fehler("kein Bildpool"); return; }
            // CreateFreeThreaded: 87 = B8G8R8A8UIntNormalized, 10 = R16G16B16A16Float (HDR); zwei Puffer
            Pruefe(Vt<FnPool>(f, 6)(f, rtDev, fmt, 2, Groesse(pw, ph), out pool), "Bildpool");
            Los(ref f);
            format = fmt;
            Pruefe(Vt<FnPP>(pool, 10)(pool, item, out sess), "Sitzung");
            IntPtr s2;
            g = IID_Session2;
            if (Marshal.QueryInterface(sess, ref g, out s2) >= 0) { Vt<FnB>(s2, 7)(s2, 0); Marshal.Release(s2); }
            g = IID_Session3;
            if (Marshal.QueryInterface(sess, ref g, out s2) >= 0) { randAus = Vt<FnB>(s2, 7)(s2, 0) >= 0; Marshal.Release(s2); }
            Pruefe(Vt<FnV>(sess, 6)(sess), "Start");
            fs = Oeffne(zDatei);
            stand = 3;
            byte[] px = new byte[MAX_PX * 4];
            byte[] px16 = null;
            uint seq = 0;
            int takt = Math.Max(10, 1000 / zFps);
            int mw = 0, mh = 0, ml = 0, mf = 0, sw = 0, sh = 0, sf = 0;
            int schwarzSeit = 0, hell = 0, spAt = 0;
            bool gewechselt = false;
            Stopwatch uhr = new Stopwatch();
            while (!halt) {
                int t0 = Environment.TickCount;
                if (unchecked(t0 - puls) > PULS_MS) { grund = "kein Lebenszeichen"; break; }
                if (!IsWindow(spiel)) { grund = "Fenster zu"; break; }
                if (spWnd != IntPtr.Zero) {
                    Nachrichten();
                    if (unchecked(t0 - spAt) >= 300) { spAt = t0; SpiegelSetzen(spWnd, spThumb, bezug, zW, zH, ref spQuelle, false); }
                }
                // Nur das neueste Bild (ältere gleich zurück an den Pool).
                IntPtr fr = IntPtr.Zero, n;
                while (Vt<FnOutP>(pool, 7)(pool, out n) >= 0 && n != IntPtr.Zero) { Zu(ref fr); fr = n; }
                if (fr != IntPtr.Zero) {
                    IntPtr surf = IntPtr.Zero, acc = IntPtr.Zero, tex = IntPtr.Zero;
                    uhr.Restart();
                    try {
                        long cs;
                        Pruefe(Vt<FnOutL>(fr, 8)(fr, out cs), "Inhalt");
                        int cw = Math.Max(1, (int)(cs & 0xFFFFFFFF)), ch = Math.Max(1, (int)(cs >> 32));
                        Pruefe(Vt<FnOutP>(fr, 6)(fr, out surf), "Fläche");
                        g = IID_DxgiAccess;
                        Pruefe(Marshal.QueryInterface(surf, ref g, out acc), "Zugriff");
                        g = IID_Tex2D;
                        Pruefe(Vt<FnGuidP>(acc, 3)(acc, ref g, out tex), "Textur");
                        TexDesc td;
                        Vt<FnDesc>(tex, 10)(tex, out td);
                        int tf = (int)td.Format;
                        int bpp = tf == FMT_FP16 ? 8 : 4;
                        int w = Math.Min(cw, (int)td.W), h = Math.Min(ch, (int)td.H);
                        int l = (tf == FMT_FP16 || tf == FMT_BGRA) ? Stufe(w, h, zW, zH) : -1;
                        if (l >= 0) {
                            int lw = Seite(w, l), lh = Seite(h, l);
                            if (l > 0 && (mw != w || mh != h || ml != l || mf != tf)) {
                                Los(ref srv); Los(ref mip);
                                TexDesc d = new TexDesc { W = (uint)w, H = (uint)h, Mips = (uint)(l + 1), Array = 1, Format = (uint)tf, SampleCount = 1, Usage = 0, Bind = 0x28, Misc = 1 };
                                Pruefe(Vt<FnTex>(dev, 5)(dev, ref d, IntPtr.Zero, out mip), "Mip-Textur");
                                Pruefe(Vt<FnSrv>(dev, 7)(dev, mip, IntPtr.Zero, out srv), "Mip-Sicht");
                                mw = w; mh = h; ml = l; mf = tf;
                            }
                            if (sw != lw || sh != lh || sf != tf) {
                                Los(ref stage);
                                TexDesc d = new TexDesc { W = (uint)lw, H = (uint)lh, Mips = 1, Array = 1, Format = (uint)tf, SampleCount = 1, Usage = 3, Cpu = 0x20000 };
                                Pruefe(Vt<FnTex>(dev, 5)(dev, ref d, IntPtr.Zero, out stage), "Staging");
                                sw = lw; sh = lh; sf = tf;
                            }
                            Box b = new Box { L = 0, T = 0, F = 0, R = (uint)w, B = (uint)h, Bk = 1 };
                            if (l == 0) {
                                Vt<FnCopyBox>(ctx, 46)(ctx, stage, 0, 0, 0, 0, tex, 0, ref b);
                            } else {
                                Vt<FnCopyBox>(ctx, 46)(ctx, mip, 0, 0, 0, 0, tex, 0, ref b);
                                Vt<FnMips>(ctx, 54)(ctx, srv);
                                Vt<FnCopy>(ctx, 46)(ctx, stage, 0, 0, 0, 0, mip, (uint)l, IntPtr.Zero);
                            }
                            byte[] ziel = px;
                            if (bpp == 8) {
                                if (px16 == null) px16 = new byte[MAX_PX * 8];
                                ziel = px16;
                            }
                            Mapped m;
                            Pruefe(Vt<FnMap>(ctx, 14)(ctx, stage, 0, 1, 0, out m), "Map");
                            try {
                                for (int y = 0; y < lh; y++) Marshal.Copy(new IntPtr(m.Data.ToInt64() + (long)y * m.Row), ziel, y * lw * bpp, lw * bpp);
                            } finally { Vt<FnUnmap>(ctx, 15)(ctx, stage, 0); }
                            if (bpp == 8) HalbZuRgba(px16, lw * lh, px, weiss);
                            else Tausche(px, lw * lh * 4);
                            uint farbe = Mittel(px, lw, lh);
                            seq = Schreibe(fs, seq, lw, lh, px, farbe);
                            if (bilder == 0) erstes = BildText(tf, (int)td.W, (int)td.H, cw, ch, l, lw, lh, farbe);
                            bilder++; bw = lw; bh = lh; stand = 1;
                            // Nur schwarze Bilder (HDR, Treiber)? Einmal das andere Format versuchen.
                            if (Schwarz(farbe)) {
                                if (schwarzFolge == 0) schwarzSeit = t0;
                                schwarzFolge++;
                            } else { schwarzFolge = 0; hell++; }
                            if (!gewechselt && hell == 0 && schwarzFolge >= SCHWARZ_N && unchecked(t0 - schwarzSeit) >= SCHWARZ_MS) {
                                gewechselt = true;
                                int neu = fmt == FMT_FP16 ? FMT_BGRA : FMT_FP16;
                                if (Vt<FnRecreate>(pool, 6)(pool, rtDev, neu, 2, Groesse(pw, ph)) >= 0) {
                                    wechsel = "nach " + schwarzFolge + " schwarzen Bildern von " + FormatName(fmt) + " auf " + FormatName(neu) + " gewechselt";
                                    fmt = neu; format = neu; schwarzFolge = 0;
                                    if (neu == FMT_FP16 && !hdr) weiss = 1f;
                                } else wechsel = "Wechsel auf " + FormatName(neu) + " ging nicht";
                            }
                        }
                        // Fenster hat jetzt eine andere Größe: Pool neu (gilt ab dem nächsten Bild).
                        if (cw != pw || ch != ph) {
                            pw = cw; ph = ch;
                            Vt<FnRecreate>(pool, 6)(pool, rtDev, fmt, 2, Groesse(pw, ph));
                        }
                    } finally {
                        Los(ref tex); Los(ref acc); Los(ref surf); Zu(ref fr);
                        Interlocked.Add(ref arbeitTicks, uhr.ElapsedTicks);
                    }
                }
                int rest = takt - unchecked(Environment.TickCount - t0);
                if (rest > 0) Thread.Sleep(rest);
            }
            if (stand != -1) stand = 2;
        } catch (Exception e) {
            Fehler(e.Message);
        } finally {
            Zu(ref sess); Zu(ref pool); Los(ref f); Los(ref item);
            Los(ref stage); Los(ref srv); Los(ref mip); Los(ref rtDev); Los(ref dxgi); Los(ref ctx); Los(ref dev); Los(ref karte);
            if (spThumb != IntPtr.Zero) { try { DwmUnregisterThumbnail(spThumb); } catch { } }
            if (spWnd != IntPtr.Zero) { try { DestroyWindow(spWnd); } catch { } }
            if (spBesitzer != IntPtr.Zero) { try { DestroyWindow(spBesitzer); } catch { } }
            spiegelAktiv = false;
            if (fs != null) {
                try { fs.Position = 0; fs.Write(KopfBytes(0, 0, 0), 0, KOPF); fs.Flush(); } catch { }
                try { fs.Dispose(); } catch { }
                try { File.Delete(zDatei); } catch { }
            }
            if (ro >= 0) RoUninitialize();
        }
    }
}
'@

function Use-TvFang {
    if ($script:TvFangReady) { return }
    Add-Type -TypeDefinition $script:TvFangSrc
    $script:TvFangReady = $true
}

# Zwischendatei des Fernsehbilds: nur im eigenen Temp-Ordner, Name mit der Nummer dieses Helfers.
# Reste früherer Helfer (Absturz) räumt der erste Start auf – nur Dateien genau dieses Musters.
function Get-TvFangDatei {
    $tmp = [IO.Path]::GetTempPath()
    $eigen = "uzai-tvbild-$PID.bin"
    if (-not $script:TvFangAufgeraeumt) {
        $script:TvFangAufgeraeumt = $true
        try {
            Get-ChildItem -LiteralPath $tmp -Filter 'uzai-tvbild-*.bin' -File -ErrorAction Stop |
                Where-Object { $_.Name -match '^uzai-tvbild-\d{1,10}\.bin$' -and $_.Name -ne $eigen } |
                ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch {} }
        } catch {}
    }
    return [IO.Path]::Combine($tmp, $eigen)
}

# Uzais Prozessnummer: der Prozess, der diesen Helfer gestartet hat (einmal gefragt, 0 = unbekannt).
function Get-UzaiPid {
    if ($null -eq $script:UzaiPid) {
        $script:UzaiPid = 0
        try { $script:UzaiPid = [int](Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop).ParentProcessId } catch {}
    }
    return $script:UzaiPid
}

# Fensterkennung als Zahl (sonst 0).
function Get-Hwnd($v) {
    $n = [long]0
    if ($null -eq $v -or $v -is [bool] -or -not [long]::TryParse([string]$v, [ref]$n) -or $n -le 0) { return [long]0 }
    return $n
}

# Ganze Zahl zwischen min und max (sonst $null).
function Get-Zahl($v, [int]$min, [int]$max) {
    $n = 0
    if ($null -eq $v -or $v -is [bool] -or -not [int]::TryParse([string]$v, [ref]$n) -or $n -lt $min -or $n -gt $max) { return $null }
    return $n
}

## FxSound (github.com/fxsound2/fxsound-app) von Uzai aus bedienen (src/core/fxsound.gd, src/core/tonwahl.gd).
## Nur über FxSounds eigene, dokumentierte Kommandozeile: Ein Aufruf von FxSound.exe mit Optionen gibt sie an das
## laufende FxSound weiter und endet. Uzai fasst weder Treiber noch Dateien von FxSound an.
##
## Die Befehlszeile baut dieser Helfer selbst (nicht über eine Argumentliste): FxSound zerlegt sie mit einem eigenen
## Zerleger, der kein Maskieren kennt – ein Anführungszeichen schaltet immer nur „in Anführungszeichen“ um. Die
## übliche Maskierung (\") käme dort als Rückstrich an und risse den Namen am ersten Leerzeichen ab. Darum: jeder
## Wert genau einmal in Anführungszeichen, und Werte mit Anführungs- oder Steuerzeichen werden abgelehnt (Fx-Wert) –
## so kann kein Name eine weitere Option einschleusen. Eine Shell ist nirgends beteiligt.

## Darf dieser Name in die Befehlszeile? Nicht leer, höchstens 200 Zeichen, kein Anführungszeichen, keine Steuerzeichen.
function Fx-Wert([string]$s) {
    if ($s.Length -lt 1 -or $s.Length -gt 200) { return $false }
    foreach ($c in $s.ToCharArray()) {
        $n = [int]$c
        if ($n -lt 32 -or $n -eq 127 -or $n -eq 34) { return $false }
    }
    return $true
}

## Kann diese Fassung Befehle annehmen und ihren Stand melden (ab 1.2.11)?
function Fx-Neu([string]$v) {
    $m = [regex]::Match($v, '^\s*(\d{1,5})\.(\d{1,5})\.(\d{1,5})')
    if (-not $m.Success) { return $false }
    $n = [long]$m.Groups[1].Value * 100000000 + [long]$m.Groups[2].Value * 10000 + [long]$m.Groups[3].Value
    return ($n -ge 100020011)
}

## Die Befehlszeile für „set“: power (0/1), preset, output – immer mit --run_minimized (sonst holt FxSound bei
## jedem Aufruf sein Fenster nach vorn). $null, wenn etwas nicht stimmt oder nichts zu setzen ist.
function Fx-Zeile([string]$exe, $a) {
    if ($exe.Contains('"')) { return $null }
    $teile = @('"' + $exe + '"')
    if ($null -ne $a.power) {
        $p = Get-Zahl $a.power 0 1
        if ($null -eq $p) { return $null }
        $teile += ('--power=' + $p)
    }
    foreach ($k in @('preset', 'output')) {
        if ($null -ne $a.$k) {
            $w = [string]$a.$k
            if (-not (Fx-Wert $w)) { return $null }
            if ($k -eq 'preset' -and $w.Length -gt 64) { return $null }
            $teile += ('--' + $k + '="' + $w + '"')
        }
    }
    if ($teile.Count -lt 2) { return $null }
    $teile += '--run_minimized'
    return ($teile -join ' ')
}

## Wo FxSound.exe liegt: der laufende Prozess, sonst der Standardordner, sonst der Eintrag „FxSound“ unter
## „Programme deinstallieren“ (so sucht auch FxSounds eigenes Werkzeug). '' wenn es nicht installiert ist.
function Fx-Exe {
    if ($script:FxExe -and (Test-Path -LiteralPath $script:FxExe)) { return $script:FxExe }
    $script:FxExe = ''
    foreach ($p in @(Get-Process -Name 'FxSound' -ErrorAction SilentlyContinue)) {
        $pfad = ''
        try { $pfad = [UzLs]::ImagePath($p.Id) } catch {}
        if ($pfad -and (Test-Path -LiteralPath $pfad)) { $script:FxExe = $pfad; return $pfad }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) {
            $c = Join-Path $base 'FxSound LLC\FxSound\FxSound.exe'
            if (Test-Path -LiteralPath $c) { $script:FxExe = $c; return $c }
        }
    }
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $v = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                if ([string]$v.DisplayName -eq 'FxSound' -and $v.InstallLocation) {
                    $c = Join-Path ([string]$v.InstallLocation) 'FxSound.exe'
                    if (Test-Path -LiteralPath $c) { $script:FxExe = $c; return $c }
                }
            } catch {}
        }
    }
    return ''
}

## op: info (installiert? läuft? Fassung), start (still starten), status (Stand lesen), set (umstellen, dann Stand).
## Antwort: da, laeuft, version, alt (läuft, aber zu alt), json (Text der Statusdatei von FxSound).
## Ein Befehl geht nur an ein FxSound, das läuft – sonst würde der Aufruf es starten.
function Fx-Call($a) {
    $op = [string]$a.op
    if ($op -notin @('info', 'start', 'status', 'set')) { throw 'Unbekannter Befehl für FxSound' }
    $exe = Fx-Exe
    $laeuft = @(Get-Process -Name 'FxSound' -ErrorAction SilentlyContinue).Count -gt 0
    $ver = ''
    if ($exe) { try { $ver = [string][Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion } catch {} }
    $out = @{ da = [bool]$exe; laeuft = $laeuft; version = $ver }
    if ($op -eq 'info' -or -not $exe) { return $out }
    $dir = Split-Path -Parent $exe
    if ($op -eq 'start') {
        if (-not $laeuft) { $out.pid = [UzStart]::MinNoActive($exe, ('"' + $exe + '" --run_minimized'), $dir) }
        return $out
    }
    if (-not $laeuft) { return $out }
    if (-not (Fx-Neu $ver)) { $out.alt = $true; return $out }
    if ($op -eq 'set') {
        $zeile = Fx-Zeile $exe $a
        if ($null -eq $zeile) { throw 'Ungültiger Wert für FxSound' }
        $out.code = [UzStart]::Still($exe, $zeile, $dir, 5000)
        Start-Sleep -Milliseconds 300
    }
    # Stand lesen: --status schreibt %APPDATA%\FxSound\status.json. Es gibt kein Zeichen, wann das fertig ist –
    # darum warten, bis die Datei jünger ist als vor dem Aufruf (höchstens 2,5 s).
    $datei = Join-Path $env:APPDATA 'FxSound\status.json'
    $vorher = [DateTime]::MinValue
    if (Test-Path -LiteralPath $datei) { $vorher = (Get-Item -LiteralPath $datei).LastWriteTimeUtc }
    [void][UzStart]::Still($exe, ('"' + $exe + '" --status'), $dir, 5000)
    $bis = (Get-Date).AddMilliseconds(2500)
    while ((Get-Date) -lt $bis) {
        if ((Test-Path -LiteralPath $datei) -and (Get-Item -LiteralPath $datei).LastWriteTimeUtc -gt $vorher) {
            Start-Sleep -Milliseconds 60
            try {
                $info = Get-Item -LiteralPath $datei
                if ($info.Length -gt 0 -and $info.Length -le 524288) { $out.json = [IO.File]::ReadAllText($datei, [Text.Encoding]::UTF8) }
            } catch {}
            break
        }
        Start-Sleep -Milliseconds 100
    }
    return $out
}

## Bild in Bild: ein Befehl je op (find, info, front, place, style, alpha, raise, behind, show). Das Fenster kommt
## aus hwnd (zuletzt bekannt) oder wird über die Prozess-ID von mpv gesucht.
function Pip-Call($a) {
    Use-Pip
    $h = [long]0
    if ($a.hwnd) { $h = [long]$a.hwnd }
    if (-not [UzPip]::Alive($h)) { $h = [long]0 }
    if ($h -eq 0 -and $a.pid) { $h = [UzPip]::Find([int]$a.pid) }
    switch ([string]$a.op) {
        'find' { return @{ hwnd = $h } }
        'info' {
            $ref = [long]0
            if ($a.ref) { $ref = [long]$a.ref }
            $f = @(([UzPip]::Info($h, $ref)).Split('|') | ForEach-Object { [int]$_ })
            return @{ hwnd = $h; mon = @($f[0..3]); work = @($f[4..7]); dpi = $f[8]; rect = @($f[9..12]); quns = $f[13]; fg = ($f[14] -eq 1) }
        }
        'place' {
            if ($h -eq 0) { return @{ ok = $false; hwnd = 0 } }
            if ($null -ne $a.style) { [void][UzPip]::Style($h, [bool]$a.style) }
            if ($null -ne $a.alpha) { [void][UzPip]::Alpha($h, [int]$a.alpha) }
            $ok = [UzPip]::Move($h, [int]$a.x, [int]$a.y, [int]$a.w, [int]$a.h, [int]$a.ms)
            if ($a.top) { [void][UzPip]::Raise($h, 0, $false) }
            return @{ ok = $ok; hwnd = $h; fg = [UzPip]::IsForeground($h) }
        }
        'style' {
            $ok = [UzPip]::Style($h, [bool]$a.style)
            if ($null -ne $a.alpha) { [void][UzPip]::Alpha($h, [int]$a.alpha) }
            return @{ ok = $ok; hwnd = $h; fg = [UzPip]::IsForeground($h) }
        }
        'front' {
            $g = [long]0
            if ($a.game) { $g = [long]$a.game }
            $f = @(([UzPip]::Front($g)).Split('|') | ForEach-Object { [long]$_ })
            return @{ hwnd = $h; fg_hwnd = $f[0]; fg_pid = $f[1]; game_pid = $f[2] }
        }
        'alpha' { return @{ ok = [UzPip]::Alpha($h, [int]$a.alpha); hwnd = $h } }
        'raise' { return @{ ok = [UzPip]::Raise($h, [int]$a.own, [bool]$a.covered); hwnd = $h } }
        'behind' { return @{ ok = [UzPip]::Behind($h, [long]$a.after); hwnd = $h } }
        'show' { return @{ ok = [UzPip]::Show($h, [bool]$a.on); hwnd = $h } }
        default { throw "Unbekannt: pip $($a.op)" }
    }
}

# Discord-Sprachkanal (offizielle lokale RPC-Schnittstelle der Discord-App): eine eigene
# Verbindung zur Pipe discord-ipc-N, die nur Rahmen weiterreicht. Alles, was Discord schickt,
# geht als {"id":-1,"event":"discord","msg":{...}} an Uzai; Uzai schickt fertige Befehle.
# Die Pipe wird überlappend geöffnet, damit Lesen (Hintergrund) und Schreiben sich nie blockieren.
$script:RpcSrc = @"
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

public static class UzRpc {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetNamedPipeServerProcessId(SafeHandle h, out uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetNamedPipeServerSessionId(SafeHandle h, out uint session);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ProcessIdToSessionId(uint pid, out uint session);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool QueryFullProcessImageNameW(IntPtr h, int flags, StringBuilder name, ref int size);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();

    // Steht hinter der Leitung wirklich die Discord-App? Pipe-Namen gelten für den ganzen PC: Ein anderes Konto oder
    // ein anderes Programm könnte discord-ipc-0 vor Discord anlegen und bekäme sonst Uzais Discord-Anmeldung
    // (AUTHENTICATE). Verlangt: Server-Prozess in derselben Windows-Sitzung und mit dem Pfad der Discord-App
    // (%LOCALAPPDATA%\<Name>\app-<Fassung>\<Name>.exe, wie Test-AppPath für Fenster).
    public static bool IstDiscord(SafeHandle h) {
        uint pid, sitzung, meine;
        if (h == null || h.IsInvalid || !GetNamedPipeServerProcessId(h, out pid) || pid == 0) return false;
        if (!GetNamedPipeServerSessionId(h, out sitzung) || !ProcessIdToSessionId(GetCurrentProcessId(), out meine) || sitzung != meine) return false;
        return DiscordPfad(BildPfad(pid), Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
    }

    public static bool DiscordPfad(string pfad, string local) {
        if (string.IsNullOrEmpty(pfad) || string.IsNullOrEmpty(local)) return false;
        string p = pfad.Replace('/', '\\');
        if (p.Contains("\\.\\") || p.Contains("\\..\\")) return false;
        var m = Regex.Match(p, "^" + Regex.Escape(local.Replace('/', '\\').TrimEnd('\\')) +
            @"\\(Discord|DiscordPTB|DiscordCanary|DiscordDevelopment)\\app-[0-9.]{1,32}\\(Discord|DiscordPTB|DiscordCanary|DiscordDevelopment)\.exe\z",
            RegexOptions.IgnoreCase);
        return m.Success && string.Equals(m.Groups[1].Value, m.Groups[2].Value, StringComparison.OrdinalIgnoreCase);
    }

    static string BildPfad(uint pid) {
        IntPtr p = OpenProcess(0x1000, false, pid);   // PROCESS_QUERY_LIMITED_INFORMATION
        if (p == IntPtr.Zero) return "";
        try {
            var sb = new StringBuilder(1024);
            int n = sb.Capacity;
            return QueryFullProcessImageNameW(p, 0, sb, ref n) ? sb.ToString(0, n) : "";
        } finally { CloseHandle(p); }
    }
    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint OPEN_EXISTING = 3;
    const uint FILE_FLAG_OVERLAPPED = 0x40000000;

    static FileStream pipe;
    static readonly object wlock = new object();
    static Thread reader;
    static int generation = 0;

    public static bool Connected { get { return pipe != null; } }

    // Verbindet und schickt den Handshake. Rückgabe: "" oder Fehlertext.
    public static string Open(string clientId) {
        Close();
        for (int i = 0; i < 10; i++) {
            SafeFileHandle h = CreateFile("\\\\.\\pipe\\discord-ipc-" + i, GENERIC_READ | GENERIC_WRITE, 0, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero);
            if (h.IsInvalid) { continue; }
            if (!IstDiscord(h)) { h.Dispose(); continue; }
            try { pipe = new FileStream(h, FileAccess.ReadWrite, 1, true); }
            catch (Exception) { h.Dispose(); continue; }
            break;
        }
        if (pipe == null) { return "Discord läuft nicht"; }
        int gen = Interlocked.Increment(ref generation);
        FileStream mine = pipe;
        reader = new Thread(delegate() { Loop(mine, gen); });
        reader.IsBackground = true;
        reader.Start();
        if (!Send(0, "{\"v\":1,\"client_id\":\"" + clientId.Replace("\"", "") + "\"}")) { return "Discord nimmt nichts an"; }
        return "";
    }

    public static bool Send(int op, string json) {
        FileStream p = pipe;
        if (p == null) { return false; }
        byte[] body = Encoding.UTF8.GetBytes(json);
        byte[] frame = new byte[8 + body.Length];
        BitConverter.GetBytes(op).CopyTo(frame, 0);
        BitConverter.GetBytes(body.Length).CopyTo(frame, 4);
        body.CopyTo(frame, 8);
        try {
            lock (wlock) { p.Write(frame, 0, frame.Length); p.Flush(); }
            return true;
        } catch (Exception) {
            Drop(p);
            return false;
        }
    }

    public static void Close() {
        FileStream p = pipe;
        pipe = null;
        if (p != null) { try { p.Dispose(); } catch (Exception) {} }
    }

    static void Drop(FileStream p) {
        if (pipe == p) {
            pipe = null;
            try { p.Dispose(); } catch (Exception) {}
            Emit("{\"id\":-1,\"event\":\"discord-closed\"}");
        }
    }

    static bool ReadAll(FileStream p, byte[] buf, int len) {
        int got = 0;
        while (got < len) {
            int n = p.Read(buf, got, len - got);
            if (n <= 0) { return false; }
            got += n;
        }
        return true;
    }

    static void Loop(FileStream p, int gen) {
        byte[] head = new byte[8];
        try {
            while (gen == generation) {
                if (!ReadAll(p, head, 8)) { break; }
                int op = BitConverter.ToInt32(head, 0);
                int len = BitConverter.ToInt32(head, 4);
                if (len < 0 || len > 4 * 1024 * 1024) { break; }
                byte[] body = new byte[len];
                if (!ReadAll(p, body, len)) { break; }
                string json = Encoding.UTF8.GetString(body);
                if (op == 3) { Send(4, json); continue; }
                if (op == 2) {
                    // Discord beendet die Verbindung (z. B. falsche App-ID): Grund mitschicken.
                    if (json.Length > 0 && json[0] == '{') {
                        Emit("{\"id\":-1,\"event\":\"discord\",\"msg\":{\"cmd\":\"CLOSE\",\"evt\":\"ERROR\",\"data\":" + json + "}}");
                    }
                    break;
                }
                if (json.Length > 0 && json[0] == '{') {
                    Emit("{\"id\":-1,\"event\":\"discord\",\"msg\":" + json + "}");
                }
            }
        } catch (Exception) {}
        Drop(p);
    }

    static void Emit(string line) {
        lock (Console.Out) {
            Console.Out.WriteLine(line);
            Console.Out.Flush();
        }
    }
}
"@
$script:RpcReady = $false

# Was gerade spielt, über die Mediensitzung von Windows (dieselbe Anzeige wie beim
# Lautstärke-Regler von Windows): Titel, Interpret, Album, Cover, Position – von jeder
# Musik-App (Spotify, Browser, Apple Music …), ohne Konto und ohne Schlüssel.
$script:WinRtReady = $false
$script:MediaMgr = $null
$script:MediaKey = ''
$script:MediaArt = ''
$script:MediaArtTries = 0
# Albumbilder liegen als Datei in %TEMP%: nur die letzten zwölf behalten (früher sammelten sich
# bei viel Musik Tausende), Reste älterer Sitzungen räumt der erste Aufruf weg.
$script:MediaArtFiles = New-Object System.Collections.Generic.List[string]
$script:MediaArtSwept = $false
function Use-WinRt {
    if ($script:WinRtReady) { return }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $script:AsTaskOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $script:WinRtReady = $true
}
function Await-Op($op, [Type]$t) {
    $task = $script:AsTaskOp.MakeGenericMethod($t).Invoke($null, @($op))
    if (-not $task.Wait(3000)) { throw 'Zeitüberschreitung' }
    return $task.Result
}
# Nur Musik-Apps (Uzai, Musik-Bereich): Die Listen kommen von Uzai (music.gd: MUSIC_APPS,
# MUSIC_IF_AUDIO, NOT_MUSIC). Browser, Videos, Discord, Spiele und Systemklänge zählen nicht.
# Art der Sitzung (MediaPlaybackType): 1 Musik, 2 Video, 3 Bild, 0 unbekannt. Reine Musik-Apps
# zählen immer (auch ein Video-Podcast in Spotify ist Spotify), Player für Musik und Video
# (Medienwiedergabe, VLC) nur bei Musik.
function Get-PlaybackType($s) {
    try { $t = $s.GetPlaybackInfo().PlaybackType; if ($null -ne $t) { return [int]$t } } catch { }
    return 0
}
function Test-MusicApp([string]$app, [int]$ptype, $a) {
    $x = $app.Trim().ToLowerInvariant()
    if ($x -eq '') { return $false }
    foreach ($k in @($a.deny)) { if ([string]$k -ne '' -and $x.Contains([string]$k)) { return $false } }
    foreach ($k in @($a.allow)) { if ([string]$k -ne '' -and $x.Contains([string]$k)) { return $true } }
    foreach ($k in @($a.audio)) { if ([string]$k -ne '' -and $x.Contains([string]$k)) { return ($ptype -eq 1) } }
    return $false
}
function Use-MediaMgr {
    Use-WinRt
    if ($null -eq $script:MediaMgr) {
        $script:MediaMgr = Await-Op ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
    }
}
# Sitzung der Musik-App: die mit der Kennung $a.app (wenn sie noch da ist), sonst eine, die gerade
# spielt, vor der aktuellen von Windows, sonst die erste (wie Music.pick_session). Ohne Listen
# ($a.allow fehlt, älteres Uzai): die aktuelle Sitzung wie früher.
function Find-MusicSession($a) {
    Use-MediaMgr
    $cur = $script:MediaMgr.GetCurrentSession()
    if ($null -eq $a -or $null -eq $a.allow) { return $cur }
    $curId = ''
    if ($null -ne $cur) { $curId = [string]$cur.SourceAppUserModelId }
    $want = [string]$a.app
    $best = $null; $bestScore = -1
    foreach ($s in $script:MediaMgr.GetSessions()) {
        $id = [string]$s.SourceAppUserModelId
        if (-not (Test-MusicApp $id (Get-PlaybackType $s) $a)) { continue }
        if ($want -ne '' -and $id -eq $want) { return $s }
        $score = 0
        try { if ([string]$s.GetPlaybackInfo().PlaybackStatus -eq 'Playing') { $score += 2 } } catch { }
        if ($curId -ne '' -and $id -eq $curId) { $score += 1 }
        if ($score -gt $bestScore) { $best = $s; $bestScore = $score }
    }
    return $best
}
function Get-MediaInfo($a) {
    $s = Find-MusicSession $a
    if ($null -eq $s) { return @{ active = $false } }
    $p = Await-Op ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    $pb = $s.GetPlaybackInfo()
    $tl = $s.GetTimelineProperties()
    $key = "$($p.Title)|$($p.Artist)|$($p.AlbumTitle)"
    # Spotify meldet Windows bei einem neuen Titel erst Titel und Interpret, das Cover kurz danach:
    # Fehlt es noch, beim nächsten Abfragen erneut lesen (höchstens achtmal je Titel). Früher blieb
    # der Titel dann ganz ohne Cover.
    $retry = ($key -eq $script:MediaKey -and $script:MediaArt -eq '' -and $script:MediaArtTries -lt 8)
    if ($key -ne $script:MediaKey -or $retry) {
        if ($key -ne $script:MediaKey) { $script:MediaArtTries = 0 }
        $script:MediaArtTries++
        $script:MediaKey = $key
        $script:MediaArt = ''
        if ($p.Thumbnail) {
            try {
                $st = Await-Op ($p.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                $net = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($st)
                $file = Join-Path $env:TEMP ('uzai-cover-' + [Math]::Abs($key.GetHashCode()) + '.png')
                # Erst vollständig in eine Nebendatei, dann umbenennen: Uzai liest nie ein halbes Bild.
                # Nur ein echtes Bild (PNG, JPG, BMP, WebP am Kopf) gilt; ein leerer Strom (Spotify meldet
                # das Cover manchmal, bevor es da ist) zählt als „noch kein Cover“ und wird erneut gelesen.
                $part = $file + '.teil'
                $fs = [IO.File]::Create($part)
                try { $net.CopyTo($fs) } finally { $fs.Close(); $net.Close() }
                $head = New-Object byte[] 12
                $hs = [IO.File]::OpenRead($part)
                try { $got = $hs.Read($head, 0, 12) } finally { $hs.Close() }
                $isImg = $got -ge 12 -and (($head[0] -eq 0x89 -and $head[1] -eq 0x50) -or ($head[0] -eq 0xFF -and $head[1] -eq 0xD8) -or
                    ($head[0] -eq 0x42 -and $head[1] -eq 0x4D) -or ($head[0] -eq 0x52 -and $head[1] -eq 0x49 -and $head[8] -eq 0x57 -and $head[9] -eq 0x45))
                if (-not $isImg) {
                    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
                    throw 'kein Bild'
                }
                Move-Item -LiteralPath $part -Destination $file -Force
                $script:MediaArt = $file
                if (-not $script:MediaArtSwept) {
                    $script:MediaArtSwept = $true
                    $old = (Get-Date).AddDays(-2)
                    Get-ChildItem -Path $env:TEMP -Filter 'uzai-cover-*.png' -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt $old } | Remove-Item -Force -ErrorAction SilentlyContinue
                }
                if (-not $script:MediaArtFiles.Contains($file)) { $script:MediaArtFiles.Add($file) }
                while ($script:MediaArtFiles.Count -gt 12) {
                    Remove-Item -LiteralPath $script:MediaArtFiles[0] -Force -ErrorAction SilentlyContinue
                    $script:MediaArtFiles.RemoveAt(0)
                }
            } catch { $script:MediaArt = '' }
        }
    }
    return @{
        active = $true; title = [string]$p.Title; artist = [string]$p.Artist; album = [string]$p.AlbumTitle
        app = [string]$s.SourceAppUserModelId; playing = ([string]$pb.PlaybackStatus -eq 'Playing')
        position = [int64]$tl.Position.TotalMilliseconds; duration = [int64]$tl.EndTime.TotalMilliseconds
        art = [string]$script:MediaArt; type = (Get-PlaybackType $s)
    }
}
function Use-Rpc {
    if (-not $script:RpcReady) { Add-Type -TypeDefinition $script:RpcSrc; $script:RpcReady = $true }
}

# Discord-Direktnachrichten über das offizielle Discord Social SDK (discord_partner_sdk.dll, liegt im
# Windows-Paket neben Uzai.exe; geladen nur mit gültiger Signatur von Discord Inc.). Ein eigener Faden im SDK-Teil
# ruft Discord_RunCallbacks auf; neue Nachrichten usw. gehen als {"id":-1,"event":"dsdk",...} an Uzai.
$script:DsdkSrc = @"
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;

// Discord Social SDK (discord_partner_sdk.dll, offizielle C-Schnittstelle cdiscord.h). Ein eigener
// Arbeitsfaden besitzt den Client: Er führt die Aufträge aus und ruft Discord_RunCallbacks auf,
// damit alle Rückrufe auf demselben Faden ankommen. Ereignisse (neue Nachricht, Zustand,
// Freundesliste) gehen als {"id":-1,"event":"dsdk","msg":{...}} an Uzai.
public static class UzDsdk {
    const string Lib = "discord_partner_sdk";

    [StructLayout(LayoutKind.Sequential)]
    public struct DStr { public IntPtr ptr; public UIntPtr size; }
    [StructLayout(LayoutKind.Sequential)]
    public struct DSpan { public IntPtr ptr; public UIntPtr size; }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void FreeFn(IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void StatusCb(int status, int error, int detail, IntPtr ud);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void ResultCb(IntPtr result, IntPtr ud);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void SendCb(IntPtr result, ulong messageId, IntPtr ud);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void MessagesCb(IntPtr result, DSpan messages, IntPtr ud);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void IdCb(ulong id, IntPtr ud);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void RelCb(ulong id, [MarshalAs(UnmanagedType.I1)] bool discordSide, IntPtr ud);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void LogCb(DStr message, int severity, IntPtr ud);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void AuthCb(IntPtr result, DStr code, DStr redirectUri, IntPtr ud);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Free(IntPtr p);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_RunCallbacks();
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_Init(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetApplicationId(ref IntPtr self, ulong id);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_Client_GetVersionMajor();
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_Client_GetVersionMinor();
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_Client_GetVersionPatch();
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_GetDefaultCommunicationScopes(out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetStatusChangedCallback(ref IntPtr self, StatusCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetMessageCreatedCallback(ref IntPtr self, IdCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetRelationshipCreatedCallback(ref IntPtr self, RelCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetRelationshipDeletedCallback(ref IntPtr self, RelCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetUserUpdatedCallback(ref IntPtr self, IdCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_AddLogCallback(ref IntPtr self, LogCb cb, FreeFn f, IntPtr ud, int minSeverity);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_UpdateToken(ref IntPtr self, int tokenType, DStr token, ResultCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_Connect(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_Disconnect(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetShowingChat(ref IntPtr self, [MarshalAs(UnmanagedType.I1)] bool on);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SetOnlineStatus(ref IntPtr self, int status, ResultCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_GetRelationships(ref IntPtr self, out DSpan ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_AcceptDiscordFriendRequest(ref IntPtr self, ulong userId, ResultCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_RejectDiscordFriendRequest(ref IntPtr self, ulong userId, ResultCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_Client_GetCurrentUserV2(ref IntPtr self, out IntPtr user);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_Client_GetUser(ref IntPtr self, ulong id, out IntPtr user);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_SendUserMessage(ref IntPtr self, ulong recipient, DStr content, SendCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_GetUserMessagesWithLimit(ref IntPtr self, ulong recipient, int limit, MessagesCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_Client_GetMessageHandle(ref IntPtr self, ulong id, out IntPtr msg);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_Authorize(ref IntPtr self, ref IntPtr args, AuthCb cb, FreeFn f, IntPtr ud);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Client_CreateAuthorizationCodeVerifier(ref IntPtr self, out IntPtr verifier);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationCodeVerifier_Verifier(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationCodeVerifier_Challenge(ref IntPtr self, out IntPtr challenge);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationCodeVerifier_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationCodeChallenge_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationArgs_Init(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationArgs_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationArgs_SetClientId(ref IntPtr self, ulong id);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationArgs_SetScopes(ref IntPtr self, DStr scopes);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AuthorizationArgs_SetCodeChallenge(ref IntPtr self, ref IntPtr challenge);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_ClientResult_Drop(IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_ClientResult_Successful(IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_ClientResult_Error(IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_ClientResult_Status(IntPtr self);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_RelationshipHandle_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_RelationshipHandle_DiscordRelationshipType(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_RelationshipHandle_Id(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_RelationshipHandle_User(ref IntPtr self, out IntPtr user);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_UserHandle_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_UserHandle_Id(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_UserHandle_DisplayName(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_UserHandle_Username(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_UserHandle_AvatarUrl(ref IntPtr self, int animated, int stat, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_UserHandle_Status(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_UserHandle_GameActivity(ref IntPtr self, out IntPtr activity);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Activity_Name(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_Activity_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_Activity_Details(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_Activity_State(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_Activity_Type(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_Activity_ApplicationId(ref IntPtr self, out ulong ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_Activity_Timestamps(ref IntPtr self, out IntPtr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_ActivityTimestamps_Start(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_ActivityTimestamps_Drop(ref IntPtr self);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_MessageHandle_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_MessageHandle_Id(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_MessageHandle_AuthorId(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_MessageHandle_RecipientId(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_MessageHandle_ChannelId(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern ulong Discord_MessageHandle_SentTimestamp(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_MessageHandle_Content(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_MessageHandle_Lobby(ref IntPtr self, out IntPtr lobby);
    // Anhang einer Nachricht (Bild, Video, Sticker …): das SDK nennt Art, Titel und Anzahl – keine Adresse.
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_MessageHandle_AdditionalContent(ref IntPtr self, out IntPtr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern int Discord_AdditionalContent_Type(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] static extern bool Discord_AdditionalContent_Title(ref IntPtr self, out DStr ret);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern byte Discord_AdditionalContent_Count(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_AdditionalContent_Drop(ref IntPtr self);
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)] static extern void Discord_LobbyHandle_Drop(ref IntPtr self);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);

    // Nur eine von Discord Inc. gültig signierte Bibliothek wird geladen: WinVerifyTrust (ohne Netz,
    // ohne Fenster) und der Name im Zertifikat. Fremder Code im Datenordner läuft so nicht im Helfer.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WtFile { public uint cbStruct; public string path; public IntPtr hFile; public IntPtr known; }
    [StructLayout(LayoutKind.Sequential)]
    struct WtData {
        public uint cbStruct; public IntPtr policy; public IntPtr sip; public uint ui; public uint revoke;
        public uint union; public IntPtr file; public uint state; public IntPtr stateData; public IntPtr url;
        public uint prov; public uint uiContext; public IntPtr sigSettings;
    }
    [DllImport("wintrust.dll", CharSet = CharSet.Unicode)] static extern int WinVerifyTrust(IntPtr hwnd, ref Guid action, ref WtData data);
    static readonly Guid VerifyV2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
    const string Signer = "Discord Inc.";

    // "" = echt (Dateiname stimmt, Signatur gültig, ausgestellt für Discord Inc.), sonst der Grund.
    public static string SignedByDiscord(string path) {
        if (!String.Equals(Path.GetFileName(path), "discord_partner_sdk.dll", StringComparison.OrdinalIgnoreCase)) { return "name"; }
        WtFile fi = new WtFile();
        fi.cbStruct = (uint)Marshal.SizeOf(typeof(WtFile));
        fi.path = path;
        IntPtr pf = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WtFile)));
        try {
            Marshal.StructureToPtr(fi, pf, false);
            WtData d = new WtData();
            d.cbStruct = (uint)Marshal.SizeOf(typeof(WtData));
            d.ui = 2;               // WTD_UI_NONE
            d.revoke = 0;           // WTD_REVOKE_NONE
            d.union = 1;            // WTD_CHOICE_FILE
            d.file = pf;
            d.state = 1;            // WTD_STATEACTION_VERIFY
            d.prov = 0x1000 | 0x10; // nur Zwischenspeicher, keine Sperrlisten aus dem Netz
            Guid act = VerifyV2;
            int rc = WinVerifyTrust(IntPtr.Zero, ref act, ref d);
            d.state = 2;            // WTD_STATEACTION_CLOSE
            WinVerifyTrust(IntPtr.Zero, ref act, ref d);
            if (rc != 0) { return "signatur " + rc.ToString("X8"); }
        } finally {
            Marshal.DestroyStructure(pf, typeof(WtFile));
            Marshal.FreeHGlobal(pf);
        }
        try {
            X509Certificate2 c = new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
            if (c.GetNameInfo(X509NameType.SimpleName, false) != Signer || !c.Subject.Contains("O=" + Signer)) { return "aussteller"; }
        } catch (Exception) { return "zertifikat"; }
        return "";
    }

    // Rückrufe bleiben am Leben, solange der Helfer läuft (sonst räumt .NET sie weg).
    static readonly FreeFn NoFree = delegate(IntPtr p) { };
    static readonly StatusCb OnStatus = StatusChanged;
    static readonly IdCb OnMessage = MessageCreated;
    static readonly RelCb OnRelCreated = delegate(ulong id, bool d, IntPtr ud) { Emit("{\"type\":\"friends\"}"); };
    static readonly RelCb OnRelDeleted = delegate(ulong id, bool d, IntPtr ud) { Emit("{\"type\":\"friends\"}"); };
    static readonly IdCb OnUserUpdated = delegate(ulong id, IntPtr ud) { Emit("{\"type\":\"user\",\"id\":\"" + id + "\"}"); };
    static readonly LogCb OnLog = delegate(DStr m, int sev, IntPtr ud) { Emit("{\"type\":\"log\",\"level\":" + sev + ",\"text\":" + Q(Read(m, true)) + "}"); };
    static readonly Dictionary<long, object> keep = new Dictionary<long, object>();
    static long nextKey = 1;

    static IntPtr client = IntPtr.Zero;
    static Thread worker;
    static readonly Queue<Action> jobs = new Queue<Action>();
    static volatile bool running;
    public static int Status = 0;
    public static string LastError = "";

    // --- Start ------------------------------------------------------------------------------

    // Lädt die DLL (voller Pfad) und startet den Client. Rückgabe: JSON { ok, version, scopes } oder Fehler.
    public static string Start(string dllPath, ulong appId) {
        if (running) { return Do(delegate() { return Info(); }, 5000); }
        if (dllPath != "" && Environment.OSVersion.Platform == PlatformID.Win32NT) {
            // Die Datei bleibt beim Prüfen und Laden gegen Schreiben gesperrt (kein Tausch dazwischen).
            FileStream sperre = null;
            try {
                try {
                    dllPath = Path.GetFullPath(dllPath);
                    sperre = new FileStream(dllPath, FileMode.Open, FileAccess.Read, FileShare.Read);
                } catch (Exception) {
                    return "{\"ok\":false,\"error\":" + Q("Die Discord-Bibliothek ließ sich nicht öffnen.") + "}";
                }
                string why = SignedByDiscord(dllPath);
                if (why != "") {
                    return "{\"ok\":false,\"unsigned\":true,\"error\":" + Q("Die Discord-Bibliothek ist nicht von Discord signiert und wird nicht geladen (" + why + ").") + "}";
                }
                // Abhängigkeiten nur aus ihrem eigenen Ordner und System32.
                if (LoadLibraryExW(dllPath, IntPtr.Zero, 0x00000100 | 0x00000800) == IntPtr.Zero) {
                    return "{\"ok\":false,\"error\":" + Q("Die Discord-Bibliothek ließ sich nicht laden (Fehler " + Marshal.GetLastWin32Error() + ").") + "}";
                }
            } finally {
                if (sperre != null) { sperre.Dispose(); }
            }
        }
        running = true;
        worker = new Thread(Loop);
        worker.IsBackground = true;
        worker.Start();
        return Do(delegate() {
            Discord_Client_Init(ref client);
            Discord_Client_SetApplicationId(ref client, appId);
            Discord_Client_SetStatusChangedCallback(ref client, OnStatus, NoFree, IntPtr.Zero);
            Discord_Client_SetMessageCreatedCallback(ref client, OnMessage, NoFree, IntPtr.Zero);
            Discord_Client_SetRelationshipCreatedCallback(ref client, OnRelCreated, NoFree, IntPtr.Zero);
            Discord_Client_SetRelationshipDeletedCallback(ref client, OnRelDeleted, NoFree, IntPtr.Zero);
            Discord_Client_SetUserUpdatedCallback(ref client, OnUserUpdated, NoFree, IntPtr.Zero);
            Discord_Client_AddLogCallback(ref client, OnLog, NoFree, IntPtr.Zero, 3);
            return Info();
        }, 10000);
    }

    static string Info() {
        DStr s;
        Discord_Client_GetDefaultCommunicationScopes(out s);
        return "{\"ok\":true,\"version\":\"" + Discord_Client_GetVersionMajor() + "." + Discord_Client_GetVersionMinor() + "." + Discord_Client_GetVersionPatch() + "\",\"scopes\":" + Q(Read(s, true)) + ",\"status\":" + Status + "}";
    }

    public static void Stop() {
        if (!running) { return; }
        try {
            Do(delegate() {
                Discord_Client_Disconnect(ref client);
                Discord_Client_Drop(ref client);
                client = IntPtr.Zero;
                return "";
            }, 3000);
        } catch (Exception) {}
        running = false;
    }

    // Zugang (OAuth2, Bearer) setzen und verbinden. Wartet, bis Discord den Zugang angenommen hat.
    public static string Token(string token) {
        return Await(delegate(Action<string> done) {
            DStr t = Str(token);
            Discord_Client_UpdateToken(ref client, 1, t, Keep(new ResultCb(delegate(IntPtr res, IntPtr ud) {
                string r = ResultJson(res, "");
                if (r.StartsWith("{\"ok\":true")) { Discord_Client_Connect(ref client); }
                done(r);
            })), NoFree, IntPtr.Zero);
            Free(t);
        }, 10000);
    }

    // Eigener Status (discordpp::StatusType: 0 Online, 3 Abwesend, 4 Bitte nicht stören, 5 Unsichtbar).
    // Ältere SDK-Fassungen kennen die Funktion nicht: dann "unsupported" statt zehn Sekunden Warten.
    public static string SetStatus(int status) {
        return Await(delegate(Action<string> done) {
            try {
                Discord_Client_SetOnlineStatus(ref client, status, Keep(new ResultCb(delegate(IntPtr res, IntPtr ud) {
                    done(ResultJson(res, ""));
                })), NoFree, IntPtr.Zero);
            } catch (EntryPointNotFoundException) {
                done("{\"ok\":false,\"error\":\"unsupported\"}");
            }
        }, 10000);
    }

    public static string ShowingChat(bool on) {
        return Do(delegate() { Discord_Client_SetShowingChat(ref client, on); return "{\"ok\":true}"; }, 3000);
    }

    // --- Freunde ------------------------------------------------------------------------------

    // Freunde (Beziehung 1) und offene Freundschaftsanfragen: 3 = an dich, 4 = von dir gesendet.
    public static string Friends() {
        return Do(delegate() {
            DSpan span;
            Discord_Client_GetRelationships(ref client, out span);
            List<string>[] lists = { new List<string>(), new List<string>(), new List<string>() };
            int n = (int)span.size.ToUInt64();
            int size = IntPtr.Size;
            for (int i = 0; i < n; i++) {
                IntPtr rel = Marshal.ReadIntPtr(span.ptr, i * size);
                int type = Discord_RelationshipHandle_DiscordRelationshipType(ref rel);
                int k = type == 1 ? 0 : (type == 3 ? 1 : (type == 4 ? 2 : -1));
                IntPtr user;
                if (k >= 0 && Discord_RelationshipHandle_User(ref rel, out user)) {
                    lists[k].Add(UserJson(ref user));
                    Discord_UserHandle_Drop(ref user);
                }
                Discord_RelationshipHandle_Drop(ref rel);
            }
            if (span.ptr != IntPtr.Zero) { Discord_Free(span.ptr); }
            return "{\"ok\":true,\"friends\":[" + string.Join(",", lists[0]) + "],\"incoming\":[" + string.Join(",", lists[1]) +
                "],\"outgoing\":[" + string.Join(",", lists[2]) + "]}";
        }, 5000);
    }

    // Freundschaftsanfrage an dich annehmen oder ablehnen – nur auf Knopfdruck in Uzai. Ältere
    // SDK-Fassungen kennen das nicht: dann "unsupported".
    public static string AnswerRequest(ulong id, bool accept) {
        if (id == 0) { return "{\"ok\":false,\"error\":\"keine Nutzer-ID\"}"; }
        return Await(delegate(Action<string> done) {
            try {
                ResultCb cb = Keep(new ResultCb(delegate(IntPtr res, IntPtr ud) { done(ResultJson(res, "")); }));
                if (accept) { Discord_Client_AcceptDiscordFriendRequest(ref client, id, cb, NoFree, IntPtr.Zero); }
                else { Discord_Client_RejectDiscordFriendRequest(ref client, id, cb, NoFree, IntPtr.Zero); }
            } catch (EntryPointNotFoundException) {
                done("{\"ok\":false,\"error\":\"unsupported\"}");
            }
        }, 10000);
    }

    public static string Me() {
        return Do(delegate() {
            IntPtr user;
            if (!Discord_Client_GetCurrentUserV2(ref client, out user)) { return "{\"ok\":false,\"error\":\"nicht verbunden\"}"; }
            string j = UserJson(ref user);
            Discord_UserHandle_Drop(ref user);
            return "{\"ok\":true,\"me\":" + j + "}";
        }, 3000);
    }

    static readonly string[] StatusNames = { "online", "offline", "blocked", "away", "busy", "offline", "online", "offline" };

    static string UserJson(ref IntPtr user) {
        DStr s;
        Discord_UserHandle_DisplayName(ref user, out s);
        string name = Read(s, true);
        Discord_UserHandle_Username(ref user, out s);
        string uname = Read(s, true);
        Discord_UserHandle_AvatarUrl(ref user, 2, 2, out s);
        string avatar = Read(s, true);
        int st = Discord_UserHandle_Status(ref user);
        string game = "", details = "", astate = "";
        int atype = 0;
        ulong app = 0, start = 0;
        IntPtr act;
        if (Discord_UserHandle_GameActivity(ref user, out act)) {
            Discord_Activity_Name(ref act, out s);
            game = Read(s, true);
            // Rich Presence (z. B. „Ranked · Map“) – ältere SDK-Fassungen kennen es nicht.
            try {
                if (Discord_Activity_Details(ref act, out s)) details = Read(s, true);
                if (Discord_Activity_State(ref act, out s)) astate = Read(s, true);
            } catch (Exception) { }
            // Art (0 spielt, 2 hört), App und seit wann (Millisekunden) – ebenso nur, wo es sie gibt.
            try {
                atype = Discord_Activity_Type(ref act);
                ulong id;
                if (Discord_Activity_ApplicationId(ref act, out id)) app = id;
                IntPtr ts;
                if (Discord_Activity_Timestamps(ref act, out ts)) {
                    start = Discord_ActivityTimestamps_Start(ref ts);
                    Discord_ActivityTimestamps_Drop(ref ts);
                }
            } catch (Exception) { }
            Discord_Activity_Drop(ref act);
        }
        if (atype < 0 || atype > 6) atype = 0;
        return "{\"id\":\"" + Discord_UserHandle_Id(ref user) + "\",\"name\":" + Q(name) + ",\"username\":" + Q(uname) +
            ",\"avatar\":" + Q(avatar) + ",\"state\":\"" + (st >= 0 && st < StatusNames.Length ? StatusNames[st] : "offline") +
            "\",\"st\":" + st + ",\"streaming\":" + (st == 6 ? "true" : "false") + ",\"game\":" + Q(game) + ",\"details\":" + Q(details) + ",\"activity_state\":" + Q(astate) +
            ",\"type\":" + atype + ",\"app\":\"" + app + "\",\"start\":" + start + "}";
    }

    // --- Nachrichten ----------------------------------------------------------------------------

    public static string Send(ulong to, string text) {
        return Await(delegate(Action<string> done) {
            DStr t = Str(text);
            Discord_Client_SendUserMessage(ref client, to, t, Keep(new SendCb(delegate(IntPtr res, ulong id, IntPtr ud) {
                done(ResultJson(res, ",\"message_id\":\"" + id + "\""));
            })), NoFree, IntPtr.Zero);
            Free(t);
        }, 10000);
    }

    public static string History(ulong with, int limit) {
        return Await(delegate(Action<string> done) {
            Discord_Client_GetUserMessagesWithLimit(ref client, with, limit, Keep(new MessagesCb(delegate(IntPtr res, DSpan msgs, IntPtr ud) {
                StringBuilder sb = new StringBuilder(",\"messages\":[");
                int n = (int)msgs.size.ToUInt64();
                for (int i = 0; i < n; i++) {
                    IntPtr m = Marshal.ReadIntPtr(msgs.ptr, i * IntPtr.Size);
                    if (i > 0) { sb.Append(','); }
                    sb.Append(MessageJson(ref m));
                    Discord_MessageHandle_Drop(ref m);
                }
                if (msgs.ptr != IntPtr.Zero) { Discord_Free(msgs.ptr); }
                sb.Append(']');
                done(ResultJson(res, sb.ToString()));
            })), NoFree, IntPtr.Zero);
        }, 10000);
    }

    static string MessageJson(ref IntPtr m) {
        DStr s;
        Discord_MessageHandle_Content(ref m, out s);
        // Anhang: Art (1 Anhang, 2 Umfrage, 3 Sprachnachricht, 4 Thread, 5 Einbettung, 6 Sticker), Titel, Anzahl.
        string extra = "";
        try {
            IntPtr ac;
            if (Discord_MessageHandle_AdditionalContent(ref m, out ac)) {
                int typ = Discord_AdditionalContent_Type(ref ac);
                DStr t;
                string titel = Discord_AdditionalContent_Title(ref ac, out t) ? Read(t, true) : "";
                int anzahl = Discord_AdditionalContent_Count(ref ac);
                Discord_AdditionalContent_Drop(ref ac);
                if (titel.Length > 200) { titel = titel.Substring(0, 200); }
                extra = ",\"anhang\":{\"art\":" + typ + ",\"titel\":" + Q(titel) + ",\"anzahl\":" + anzahl + "}";
            }
        } catch (Exception) { extra = ""; }
        return "{\"id\":\"" + Discord_MessageHandle_Id(ref m) + "\",\"author\":\"" + Discord_MessageHandle_AuthorId(ref m) +
            "\",\"recipient\":\"" + Discord_MessageHandle_RecipientId(ref m) + "\",\"channel\":\"" + Discord_MessageHandle_ChannelId(ref m) +
            "\",\"sent\":" + Discord_MessageHandle_SentTimestamp(ref m) + ",\"text\":" + Q(Read(s, true)) + extra + "}";
    }

    static void MessageCreated(ulong id, IntPtr ud) {
        IntPtr m;
        if (!Discord_Client_GetMessageHandle(ref client, id, out m)) { return; }
        // Nur Direktnachrichten (Lobby-Nachrichten nutzt Uzai nicht).
        IntPtr lobby;
        bool inLobby = Discord_MessageHandle_Lobby(ref m, out lobby);
        if (inLobby) { Discord_LobbyHandle_Drop(ref lobby); }
        else { Emit("{\"type\":\"message\",\"message\":" + MessageJson(ref m) + "}"); }
        Discord_MessageHandle_Drop(ref m);
    }

    static void StatusChanged(int status, int error, int detail, IntPtr ud) {
        Status = status;
        Emit("{\"type\":\"status\",\"status\":" + status + ",\"error\":" + error + ",\"detail\":" + detail + "}");
    }

    // --- Anmeldung über das SDK (Rückfall, wenn die Freigabe über die Discord-App nicht geht) ------

    // Öffnet Discords Freigabe (Overlay oder Browser). Kehrt sofort zurück; das Ergebnis kommt
    // als Ereignis {"type":"authorized", ok, error, code, redirect, verifier}.
    public static string Authorize(ulong appId, string scopes) {
        if (!running || client == IntPtr.Zero) { return "{\"ok\":false,\"error\":\"nicht gestartet\"}"; }
        return Do(delegate() {
            IntPtr verifier, challenge, args = IntPtr.Zero;
            Discord_Client_CreateAuthorizationCodeVerifier(ref client, out verifier);
            DStr v;
            Discord_AuthorizationCodeVerifier_Verifier(ref verifier, out v);
            string ver = Read(v, true);
            Discord_AuthorizationCodeVerifier_Challenge(ref verifier, out challenge);
            Discord_AuthorizationArgs_Init(ref args);
            Discord_AuthorizationArgs_SetClientId(ref args, appId);
            DStr sc = Str(scopes);
            Discord_AuthorizationArgs_SetScopes(ref args, sc);
            Free(sc);
            Discord_AuthorizationArgs_SetCodeChallenge(ref args, ref challenge);
            Discord_Client_Authorize(ref client, ref args, Keep(new AuthCb(delegate(IntPtr res, DStr code, DStr redirect, IntPtr ud) {
                string extra = ",\"code\":" + Q(Read(code, true)) + ",\"redirect\":" + Q(Read(redirect, true)) + ",\"verifier\":" + Q(ver);
                string r = ResultJson(res, extra);
                Emit("{\"type\":\"authorized\",\"result\":" + r + "}");
            })), NoFree, IntPtr.Zero);
            Discord_AuthorizationArgs_Drop(ref args);
            Discord_AuthorizationCodeChallenge_Drop(ref challenge);
            Discord_AuthorizationCodeVerifier_Drop(ref verifier);
            return "{\"ok\":true}";
        }, 5000);
    }

    // --- Faden und Hilfen ---------------------------------------------------------------------

    static void Loop() {
        while (running) {
            Action job = null;
            lock (jobs) { if (jobs.Count > 0) { job = jobs.Dequeue(); } }
            if (job != null) { job(); continue; }
            try { if (client != IntPtr.Zero) { Discord_RunCallbacks(); } } catch (Exception) {}
            Thread.Sleep(15);
        }
    }

    static string Do(Func<string> f, int ms) {
        string result = null;
        Exception err = null;
        ManualResetEvent ev = new ManualResetEvent(false);
        lock (jobs) {
            jobs.Enqueue(delegate() {
                try { result = f(); } catch (Exception e) { err = e; }
                ev.Set();
            });
        }
        if (!ev.WaitOne(ms)) { return "{\"ok\":false,\"error\":\"Discord antwortet nicht\"}"; }
        if (err != null) { return "{\"ok\":false,\"error\":" + Q(err.Message) + "}"; }
        return result;
    }

    // Startet etwas auf dem Faden, dessen Ergebnis später in einem Rückruf kommt.
    static string Await(Action<Action<string>> start, int ms) {
        if (!running || client == IntPtr.Zero) { return "{\"ok\":false,\"error\":\"nicht gestartet\"}"; }
        string result = null;
        ManualResetEvent ev = new ManualResetEvent(false);
        Action<string> done = delegate(string r) { result = r; ev.Set(); };
        string started = Do(delegate() { start(done); return "{\"ok\":true}"; }, 5000);
        if (!started.StartsWith("{\"ok\":true")) { return started; }
        if (!ev.WaitOne(ms)) { return "{\"ok\":false,\"error\":\"Discord hat nicht geantwortet\"}"; }
        return result;
    }

    // Rückruf-Objekt bis zum Ende festhalten (das SDK ruft es später auf).
    static T Keep<T>(T d) {
        lock (keep) { keep[nextKey++] = d; }
        return d;
    }

    static string ResultJson(IntPtr res, string extra) {
        bool ok = Discord_ClientResult_Successful(res);
        string err = "";
        int status = 0;
        if (!ok) {
            DStr s;
            Discord_ClientResult_Error(res, out s);
            err = Read(s, true);
            status = Discord_ClientResult_Status(res);
        }
        Discord_ClientResult_Drop(res);
        return "{\"ok\":" + (ok ? "true" : "false") + ",\"error\":" + Q(err) + ",\"status\":" + status + extra + "}";
    }

    // Text für einen Aufruf (das SDK kopiert ihn sofort, wie discordpp.h: danach wieder frei).
    static DStr Str(string s) {
        byte[] b = Encoding.UTF8.GetBytes(s ?? "");
        IntPtr p = Marshal.AllocHGlobal(b.Length + 1);
        Marshal.Copy(b, 0, p, b.Length);
        Marshal.WriteByte(p, b.Length, 0);
        DStr d;
        d.ptr = p;
        d.size = new UIntPtr((ulong)b.Length);
        return d;
    }

    static void Free(DStr d) { if (d.ptr != IntPtr.Zero) { Marshal.FreeHGlobal(d.ptr); } }

    static string Read(DStr s, bool free) {
        int n = (int)s.size.ToUInt64();
        string r = "";
        if (s.ptr != IntPtr.Zero && n > 0) {
            byte[] b = new byte[n];
            Marshal.Copy(s.ptr, b, 0, n);
            r = Encoding.UTF8.GetString(b);
        }
        if (free && s.ptr != IntPtr.Zero) { Discord_Free(s.ptr); }
        return r;
    }

    public static string Q(string s) {
        StringBuilder sb = new StringBuilder("\"");
        foreach (char c in s ?? "") {
            switch (c) {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) { sb.Append("\\u" + ((int)c).ToString("x4")); } else { sb.Append(c); }
                    break;
            }
        }
        return sb.Append('"').ToString();
    }

    static void Emit(string msg) {
        lock (Console.Out) {
            Console.Out.WriteLine("{\"id\":-1,\"event\":\"dsdk\",\"msg\":" + msg + "}");
            Console.Out.Flush();
        }
    }
}
"@
$script:DsdkReady = $false
function Use-Dsdk {
    if (-not $script:DsdkReady) { Add-Type -TypeDefinition $script:DsdkSrc; $script:DsdkReady = $true }
}

# Uzais eigene Aufnahme (Clips, Aufnahmen): Ton über WASAPI-Loopback in benannte Leitungen, FFmpeg als
# Kindprozess im Job-Objekt. Erst beim ersten Gebrauch übersetzt (wie Discord und Audio).
$script:CapSrc = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Globalization;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

// Uzais eigene Aufnahme, Teil im Helfer: Ton über WASAPI (Loopback = was Windows ausgibt, auf
// Wunsch das Mikrofon) in benannte Leitungen für FFmpeg, FFmpeg selbst als Kindprozess in einem
// Job-Objekt (stirbt der Helfer – Uzai beendet, abgestürzt –, beendet Windows FFmpeg mit). Nur
// ein FFmpeg zur Zeit. Die Befehlszeile baut Uzai (capture_logic.gd); hier werden nur die
// Platzhalter {T0}, {SYS_RATE}, {MIC_RATE}, {HWND}, {HMON} eingesetzt.
//
// Zeitbasis: T0 (Unix-Sekunden) ist der Augenblick, ab dem der Ton zählt. Jede Probe n eines
// Tonstroms gehört zu T0 + n/Rate: Pakete werden nach ihrer QPC-Zeit eingeordnet, Lücken (Loopback
// liefert bei Stille gar nichts) mit Stille gefüllt, Überlappungen verworfen.
public static class UzCap {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }

    [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioClient {
        [PreserveSig] int Initialize(int share, uint flags, long buffer, long period, IntPtr fmt, IntPtr session);
        [PreserveSig] int GetBufferSize(out uint frames);
        [PreserveSig] int GetStreamLatency(out long lat);
        [PreserveSig] int GetCurrentPadding(out uint pad);
        [PreserveSig] int IsFormatSupported(int share, IntPtr fmt, out IntPtr closest);
        [PreserveSig] int GetMixFormat(out IntPtr fmt);
        [PreserveSig] int GetDevicePeriod(out long def, out long min);
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
        [PreserveSig] int Reset();
        [PreserveSig] int SetEventHandle(IntPtr h);
        [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }

    [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioCaptureClient {
        [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devPos, out ulong qpcPos);
        [PreserveSig] int ReleaseBuffer(uint frames);
        [PreserveSig] int GetNextPacketSize(out uint frames);
    }

    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr p);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateNamedPipeW(string name, uint openMode, uint pipeMode, uint maxInst, uint outBuf, uint inBuf, uint timeout, IntPtr sa);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ConnectNamedPipe(IntPtr h, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetNamedPipeClientProcessId(IntPtr h, out uint pid);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint rev, out IntPtr sd, IntPtr size);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
    [StructLayout(LayoutKind.Sequential)] struct PIPE_SA { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateNamedPipeW")]
    static extern IntPtr CreateNamedPipeSa(string name, uint openMode, uint pipeMode, uint maxInst, uint outBuf, uint inBuf, uint timeout, ref PIPE_SA sa);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObjectW(IntPtr sa, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint len);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS s);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("gdi32.dll")] static extern int D3DKMTSetProcessSchedulingPriorityClass(IntPtr process, int priority);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetProcessInformation(IntPtr process, int infoClass, ref POWER_THROTTLING info, uint size);

    [StructLayout(LayoutKind.Sequential)]
    struct POWER_THROTTLING { public uint Version; public uint ControlMask; public uint StateMask; }

    [StructLayout(LayoutKind.Sequential)]
    struct SYSTEM_POWER_STATUS { public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte SystemStatusFlag; public int BatteryLifeTime; public int BatteryFullLifeTime; }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
    }

    static readonly IntPtr INVALID = new IntPtr(-1);

    // Ein Tonstrom: Aufnahme-Faden (WASAPI) und Schreib-Faden (Leitung zu FFmpeg).
    class Source {
        public string Pipe = "";
        public bool Loopback;
        public int Rate, Channels, Bits, Block;
        public bool IsFloat;
        public volatile bool Stop;
        public volatile bool Ready;
        public string Error = "";
        public long Written;          // Proben auf der Zeitachse (mit Stille)
        public long Silence, Dropped, Skipped;
        public double T0Hns;          // T0 als QPC in 100 ns
        public volatile bool T0Set;
        public IntPtr PipeHandle = INVALID;
        public volatile int ExpectPid;    // nur dieser Prozess (das gestartete FFmpeg) darf die Leitung lesen
        public Thread Cap, Writer;
        public readonly ManualResetEvent Inited = new ManualResetEvent(false);
        readonly object qlock = new object();
        readonly Queue<byte[]> queue = new Queue<byte[]>();
        long queued;
        readonly AutoResetEvent signal = new AutoResetEvent(false);

        public void Push(byte[] b) {
            lock (qlock) {
                queue.Enqueue(b);
                queued += b.Length;
                // Liest FFmpeg nicht (hängt, startet noch): höchstens ~10 s halten.
                long cap = (long)Math.Max(1, Rate) * 8 * 10;
                while (queued > cap && queue.Count > 1) { var o = queue.Dequeue(); queued -= o.Length; Dropped += o.Length / 8; }
            }
            signal.Set();
        }

        public byte[] Take(int waitMs) {
            signal.WaitOne(waitMs);
            lock (qlock) {
                if (queue.Count == 0) return null;
                var ms = new MemoryStream((int)Math.Min(queued, 1 << 22));
                while (queue.Count > 0) { var b = queue.Dequeue(); ms.Write(b, 0, b.Length); }
                queued = 0;
                return ms.ToArray();
            }
        }

        public void Wake() { signal.Set(); }
    }

    static readonly object gate = new object();
    static Process proc;
    static IntPtr job = IntPtr.Zero;
    static Source sys, mic;
    static double t0Unix;
    static DateTime started;
    static readonly List<string> errTail = new List<string>();
    static string lastError = "";

    static void AddErr(string line) {
        lock (errTail) {
            errTail.Add(line);
            if (errTail.Count > 12) errTail.RemoveAt(0);
        }
    }

    static string Esc(string s) {
        if (s == null) return "";
        var sb = new StringBuilder(s.Length + 8);
        foreach (char c in s) {
            if (c == '"' || c == '\\') sb.Append('\\').Append(c);
            else if (c < 0x20) sb.Append(' ');
            else sb.Append(c);
        }
        return sb.ToString();
    }

    // Ein Argument so in die Befehlszeile, wie CommandLineToArgvW es wieder zerlegt.
    public static string Quote(string a) {
        if (a == null) a = "";
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return a;
        var sb = new StringBuilder("\"");
        int bs = 0;
        foreach (char c in a) {
            if (c == '\\') { bs++; continue; }
            if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); bs = 0; continue; }
            if (bs > 0) { sb.Append('\\', bs); bs = 0; }
            sb.Append(c);
        }
        sb.Append('\\', bs * 2);
        sb.Append('"');
        return sb.ToString();
    }

    static double NowUnix() {
        return (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
    }

    static double QpcHns() {
        return (double)Stopwatch.GetTimestamp() * 10000000.0 / (double)Stopwatch.Frequency;
    }

    // --- Ton -----------------------------------------------------------------------------

    static void CaptureLoop(object o) {
        var s = (Source)o;
        IAudioClient client = null;
        IntPtr fmt = IntPtr.Zero;
        try {
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo();
            IMMDevice dev;
            // Loopback: Ausgabe (eRender = 0), sonst Aufnahme (eCapture = 1); Rolle eConsole = 0.
            int hr = en.GetDefaultAudioEndpoint(s.Loopback ? 0 : 1, 0, out dev);
            if (hr != 0 || dev == null) throw new Exception(s.Loopback ? "Kein Ausgabegerät" : "Kein Mikrofon");
            var iid = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
            object co;
            hr = dev.Activate(ref iid, 23, IntPtr.Zero, out co);
            client = co as IAudioClient;
            if (hr != 0 || client == null) throw new Exception("Audiogerät lässt sich nicht öffnen (" + hr.ToString("X") + ")");
            hr = client.GetMixFormat(out fmt);
            if (hr != 0 || fmt == IntPtr.Zero) throw new Exception("Tonformat unbekannt");
            int tag = Marshal.ReadInt16(fmt, 0) & 0xFFFF;
            s.Channels = Marshal.ReadInt16(fmt, 2);
            s.Rate = Marshal.ReadInt32(fmt, 4);
            s.Block = Marshal.ReadInt16(fmt, 12);
            s.Bits = Marshal.ReadInt16(fmt, 14);
            int sub = tag;
            if (tag == 0xFFFE) sub = Marshal.ReadInt16(fmt, 24) & 0xFFFF;   // SubFormat (GUID, erste zwei Bytes)
            s.IsFloat = sub == 3;
            if (!(s.IsFloat && s.Bits == 32) && !(sub == 1 && (s.Bits == 16 || s.Bits == 24 || s.Bits == 32)))
                throw new Exception("Tonformat nicht unterstützt (" + sub + "/" + s.Bits + " Bit)");
            if (s.Channels < 1 || s.Block < s.Channels) throw new Exception("Tonformat ungültig");
            // Gemeinsamer Modus, 200 ms Puffer; Loopback = AUDCLNT_STREAMFLAGS_LOOPBACK.
            hr = client.Initialize(0, s.Loopback ? 0x00020000u : 0u, 2000000, 0, fmt, IntPtr.Zero);
            if (hr != 0) throw new Exception("Audio-Initialisierung ging nicht (" + hr.ToString("X") + ")");
            var ciid = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
            object cco;
            hr = client.GetService(ref ciid, out cco);
            var cap = cco as IAudioCaptureClient;
            if (hr != 0 || cap == null) throw new Exception("Audio-Aufnahme nicht verfügbar");
            hr = client.Start();
            if (hr != 0) throw new Exception("Audio-Start ging nicht (" + hr.ToString("X") + ")");
            s.Ready = true;
            s.Inited.Set();
            while (!s.T0Set && !s.Stop) Thread.Sleep(2);
            long tol = s.Rate / 50;            // 20 ms
            long lag = s.Rate * 60 / 1000;     // so weit hinkt die Stille der Uhr hinterher
            while (!s.Stop) {
                bool got = false;
                uint n;
                while (!s.Stop && cap.GetNextPacketSize(out n) == 0 && n > 0) {
                    IntPtr data; uint frames, flags; ulong dpos, qpc;
                    if (cap.GetBuffer(out data, out frames, out flags, out dpos, out qpc) != 0) break;
                    got = true;
                    long target = (long)(((double)qpc - s.T0Hns) * s.Rate / 10000000.0);
                    if ((flags & 0x4) != 0) target = s.Written;   // TIMESTAMP_ERROR
                    if (target > s.Written + tol) PushSilence(s, target - s.Written);
                    long skip = 0;
                    if (target < s.Written - tol) skip = Math.Min(frames, s.Written - target);
                    long keep = frames - skip;
                    if (keep > 0) {
                        if ((flags & 0x2) != 0) PushSilence(s, keep);   // SILENT
                        else { s.Push(ToStereo(s, data, (int)skip, (int)keep)); s.Written += keep; }
                    }
                    s.Skipped += skip;
                    cap.ReleaseBuffer(frames);
                }
                if (!got) {
                    long now = (long)((QpcHns() - s.T0Hns) * s.Rate / 10000000.0) - lag;
                    if (now > s.Written) PushSilence(s, now - s.Written);
                }
                Thread.Sleep(5);
            }
            client.Stop();
        } catch (Exception e) {
            s.Error = e.Message;
            s.Inited.Set();
        } finally {
            if (fmt != IntPtr.Zero) CoTaskMemFree(fmt);
        }
    }

    static void PushSilence(Source s, long frames) {
        while (frames > 0) {
            int n = (int)Math.Min(frames, s.Rate);
            s.Push(new byte[n * 8]);
            s.Written += n;
            s.Silence += n;
            frames -= n;
        }
    }

    // Beliebiges Mischformat → 32-Bit-Float, Stereo (FFmpeg bekommt immer f32le, 2 Kanäle).
    static byte[] ToStereo(Source s, IntPtr data, int skip, int frames) {
        int ch = s.Channels;
        int bps = s.Bits / 8;
        var raw = new byte[frames * s.Block];
        Marshal.Copy(new IntPtr(data.ToInt64() + (long)skip * s.Block), raw, 0, raw.Length);
        var outF = new float[frames * 2];
        float gain = ch > 2 ? 0.6f : 1.0f;
        for (int f = 0; f < frames; f++) {
            int b = f * s.Block;
            float c0 = Sample(s, raw, b, bps);
            float c1 = ch > 1 ? Sample(s, raw, b + bps, bps) : c0;
            float l = c0, r = c1;
            if (ch > 2) {
                float c = Sample(s, raw, b + 2 * bps, bps) * 0.707f;
                l += c; r += c;
                if (ch >= 6) { l += 0.5f * Sample(s, raw, b + 4 * bps, bps); r += 0.5f * Sample(s, raw, b + 5 * bps, bps); }
                if (ch >= 8) { l += 0.5f * Sample(s, raw, b + 6 * bps, bps); r += 0.5f * Sample(s, raw, b + 7 * bps, bps); }
                l *= gain; r *= gain;
            }
            outF[f * 2] = l;
            outF[f * 2 + 1] = r;
        }
        var bytes = new byte[outF.Length * 4];
        Buffer.BlockCopy(outF, 0, bytes, 0, bytes.Length);
        return bytes;
    }

    static float Sample(Source s, byte[] raw, int at, int bps) {
        if (s.IsFloat) return BitConverter.ToSingle(raw, at);
        if (bps == 2) return BitConverter.ToInt16(raw, at) / 32768f;
        if (bps == 3) return ((raw[at] << 8 | raw[at + 1] << 16 | raw[at + 2] << 24) >> 8) / 8388608f;
        return BitConverter.ToInt32(raw, at) / 2147483648f;
    }

    static void WriterLoop(object o) {
        var s = (Source)o;
        FileStream fs = null;
        try {
            // Wartet, bis FFmpeg die Leitung öffnet (Stop() öffnet sie notfalls selbst, um das zu lösen).
            if (!ConnectNamedPipe(s.PipeHandle, IntPtr.Zero) && Marshal.GetLastWin32Error() != 535) throw new Exception("Leitung zu FFmpeg ging nicht");
            if (s.Stop) return;
            // Nur das FFmpeg, das Start() gerade gestartet hat, bekommt den Ton (Mikrofon!) – kein anderer Prozess, der
            // sich schneller verbunden hat. Start() trägt die Kennung gleich nach dem Start ein.
            uint client;
            if (!GetNamedPipeClientProcessId(s.PipeHandle, out client)) throw new Exception("Leitung: Gegenstelle unbekannt");
            for (int i = 0; i < 40 && s.ExpectPid == 0 && !s.Stop; i++) Thread.Sleep(50);
            if (s.Stop) return;
            if (s.ExpectPid == 0 || client != (uint)s.ExpectPid) throw new Exception("Leitung: fremde Gegenstelle");
            fs = new FileStream(new SafeFileHandle(s.PipeHandle, true), FileAccess.Write, 1 << 16, false);
            s.PipeHandle = INVALID;
            while (!s.Stop) {
                var b = s.Take(100);
                if (b != null && b.Length > 0) fs.Write(b, 0, b.Length);
            }
        } catch (Exception e) {
            if (!s.Stop && s.Error == "") s.Error = "Leitung: " + e.Message;
        } finally {
            try { if (fs != null) fs.Dispose(); } catch { }
        }
    }

    // Leitung nur für dieses Konto: DACL allein mit der eigenen SID (geschützt, nichts geerbt), Kennzeichnung „mittel“
    // ohne Lesen und Schreiben von unten (Prozesse mit niedriger Integrität, etwa Browser-Sandboxen, bleiben draußen),
    // FILE_FLAG_FIRST_PIPE_INSTANCE und PIPE_REJECT_REMOTE_CLIENTS. Darf das Konto keine Kennzeichnung setzen, ohne sie.
    static IntPtr PipeAnlegen(string name) {
        string sid = System.Security.Principal.WindowsIdentity.GetCurrent().User.Value;
        foreach (string sddl in new string[] { "D:P(A;;GA;;;" + sid + ")S:(ML;;NWNR;;;ME)", "D:P(A;;GA;;;" + sid + ")" }) {
            IntPtr sd;
            if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out sd, IntPtr.Zero)) continue;
            try {
                var sa = new PIPE_SA();
                sa.nLength = Marshal.SizeOf(typeof(PIPE_SA));
                sa.lpSecurityDescriptor = sd;
                IntPtr h = CreateNamedPipeSa(name, 0x00000002 | 0x00080000, 0x00000008, 1, 1 << 20, 0, 0, ref sa);
                if (h != INVALID) return h;
                int e = Marshal.GetLastWin32Error();
                if (e != 5 && e != 1314) return INVALID;
            } finally { LocalFree(sd); }
        }
        return INVALID;
    }

    static Source OpenSource(bool loopback, string pipe) {
        var s = new Source();
        s.Loopback = loopback;
        s.Pipe = pipe;
        // Ausgehende Byte-Leitung, eine Instanz, 1 MB Puffer. Nur dieses Windows-Konto (ohne Vorgabe hätten „Jeder“ und
        // „Anonym“ Lesezugriff), nur mittlere Integrität und darüber, nie über das Netz, und nur, wenn es den Namen
        // noch nicht gibt (sonst hätte ihn jemand vorher belegt).
        s.PipeHandle = PipeAnlegen(@"\\.\pipe\" + pipe);
        if (s.PipeHandle == INVALID) throw new Exception("Leitung " + pipe + " ließ sich nicht anlegen (" + Marshal.GetLastWin32Error() + ")");
        s.Cap = new Thread(CaptureLoop);
        s.Cap.IsBackground = true;
        s.Cap.Start(s);
        return s;
    }

    static void CloseSource(Source s) {
        if (s == null) return;
        s.Stop = true;
        s.Wake();
        if (s.Writer != null && s.Writer.IsAlive && !s.Writer.Join(300)) {
            // Hängt noch in ConnectNamedPipe (FFmpeg hat die Leitung nie geöffnet): selbst verbinden.
            IntPtr h = CreateFileW(@"\\.\pipe\" + s.Pipe, 0x80000000, 0, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (h != INVALID) CloseHandle(h);
            s.Writer.Join(1000);
        }
        if (s.Cap != null) s.Cap.Join(1000);
        if (s.PipeHandle != INVALID) { CloseHandle(s.PipeHandle); s.PipeHandle = INVALID; }
    }

    // --- FFmpeg --------------------------------------------------------------------------

    static void EnsureJob() {
        if (job != IntPtr.Zero) return;
        job = CreateJobObjectW(IntPtr.Zero, null);
        if (job == IntPtr.Zero) return;
        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = 0x2000;   // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        SetInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)));
    }

    static bool Running() { return proc != null && !proc.HasExited; }

    // Vorrang für FFmpeg, wie OBS ihn sich selbst gibt: Läuft das Spiel mit voller Grafikkarte,
    // kommt die Aufnahme sonst nicht mehr dran, und der Clip hat zu wenig Bilder. Prozessor „über
    // normal“, Grafikkarte „hoch“ (ohne Adminrechte oft abgelehnt, dann „über normal“), und Windows
    // drosselt den fensterlosen Prozess nicht (Energiesparen, grobe Zeitgeber). Text fürs Protokoll.
    static string Boost(Process p) {
        var parts = new List<string>();
        try { p.PriorityClass = ProcessPriorityClass.AboveNormal; parts.Add("CPU über normal"); }
        catch (Exception e) { parts.Add("CPU normal (" + e.Message + ")"); }
        try {
            int st = D3DKMTSetProcessSchedulingPriorityClass(p.Handle, 4);
            if (st == 0) parts.Add("GPU hoch");
            else {
                int st2 = D3DKMTSetProcessSchedulingPriorityClass(p.Handle, 3);
                parts.Add(st2 == 0 ? "GPU über normal" : "GPU normal (0x" + st2.ToString("X8") + ")");
            }
        } catch (Exception) { parts.Add("GPU normal"); }
        try {
            var t = new POWER_THROTTLING();
            t.Version = 1;
            t.ControlMask = 0x1 | 0x4;   // EXECUTION_SPEED, IGNORE_TIMER_RESOLUTION
            t.StateMask = 0;             // beides aus: volle Leistung, feine Zeitgeber
            parts.Add(SetProcessInformation(p.Handle, 4, ref t, (uint)Marshal.SizeOf(typeof(POWER_THROTTLING))) ? "ohne Drosselung" : "Drosselung unverändert");
        } catch (Exception) { }
        return string.Join(", ", parts);
    }

    // args: fertige Befehlszeile mit Platzhaltern; sysPipe/micPipe "" = ohne. skipPid: Uzai selbst
    // (dessen Fenster ist nie das Spielfenster). Antwort als JSON.
    public static string Start(string exe, string[] args, string sysPipe, string micPipe, string dir, int skipPid) {
        lock (gate) {
            StopInner();
            lock (errTail) errTail.Clear();
            lastError = "";
            try {
                if (!File.Exists(exe)) return "{\"ok\":false,\"error\":\"FFmpeg fehlt\"}";
                IntPtr fg = GetForegroundWindow();
                int fpid;
                GetWindowThreadProcessId(fg, out fpid);
                if (fpid == skipPid) fg = IntPtr.Zero;
                IntPtr mon = MonitorFromWindow(fg != IntPtr.Zero ? fg : GetForegroundWindow(), 2);
                bool needHwnd = false;
                foreach (var a in args) if (a.Contains("{HWND}")) needHwnd = true;
                if (needHwnd && fg == IntPtr.Zero) return "{\"ok\":false,\"error\":\"Kein Spielfenster vorn\"}";
                if (sysPipe != "") sys = OpenSource(true, sysPipe);
                if (micPipe != "") mic = OpenSource(false, micPipe);
                foreach (var s in new Source[] { sys, mic }) {
                    if (s == null) continue;
                    if (!s.Inited.WaitOne(4000)) s.Error = "Audiogerät antwortet nicht";
                }
                string audioErr = "";
                if (sys != null && !sys.Ready) { audioErr = "Ton: " + sys.Error; CloseSource(sys); sys = null; }
                if (mic != null && !mic.Ready) { audioErr += (audioErr != "" ? " · " : "") + "Mikrofon: " + mic.Error; CloseSource(mic); mic = null; }
                if ((sysPipe != "" && sys == null) || (micPipe != "" && mic == null)) {
                    // Ohne den Ton passt die Befehlszeile nicht mehr: Uzai baut sie dann ohne neu.
                    StopInner();
                    return "{\"ok\":false,\"audio_failed\":true,\"error\":\"" + Esc(audioErr) + "\"}";
                }
                double qpc = QpcHns();
                t0Unix = NowUnix();
                foreach (var s in new Source[] { sys, mic }) {
                    if (s == null) continue;
                    s.T0Hns = qpc;
                    s.T0Set = true;
                    s.Writer = new Thread(WriterLoop);
                    s.Writer.IsBackground = true;
                    s.Writer.Start(s);
                }
                var line = new StringBuilder();
                string t0s = t0Unix.ToString("F6", CultureInfo.InvariantCulture);
                foreach (var a0 in args) {
                    string a = a0.Replace("{T0}", t0s)
                        .Replace("{SYS_RATE}", sys != null ? sys.Rate.ToString(CultureInfo.InvariantCulture) : "48000")
                        .Replace("{MIC_RATE}", mic != null ? mic.Rate.ToString(CultureInfo.InvariantCulture) : "48000")
                        .Replace("{HWND}", fg.ToInt64().ToString(CultureInfo.InvariantCulture))
                        .Replace("{HMON}", mon.ToInt64().ToString(CultureInfo.InvariantCulture));
                    if (line.Length > 0) line.Append(' ');
                    line.Append(Quote(a));
                }
                var psi = new ProcessStartInfo(exe, line.ToString());
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardInput = true;
                psi.RedirectStandardError = true;
                psi.RedirectStandardOutput = true;
                psi.WorkingDirectory = dir;
                var p = new Process();
                p.StartInfo = psi;
                p.ErrorDataReceived += (o, e) => { if (e.Data != null && e.Data.Trim() != "") AddErr(e.Data.Trim()); };
                p.OutputDataReceived += (o, e) => { };
                if (!p.Start()) { StopInner(); return "{\"ok\":false,\"error\":\"FFmpeg startet nicht\"}"; }
                proc = p;
                foreach (var s in new Source[] { sys, mic }) if (s != null) s.ExpectPid = p.Id;
                started = DateTime.UtcNow;
                try { p.BeginErrorReadLine(); p.BeginOutputReadLine(); } catch { }
                EnsureJob();
                if (job != IntPtr.Zero) AssignProcessToJobObject(job, p.Handle);
                string prio = Boost(p);
                return "{\"ok\":true,\"pid\":" + p.Id + ",\"prio\":\"" + Esc(prio) + "\",\"t0\":\"" + t0s + "\",\"sys_rate\":" + (sys != null ? sys.Rate : 0)
                    + ",\"mic_rate\":" + (mic != null ? mic.Rate : 0) + ",\"hwnd\":" + fg.ToInt64() + ",\"audio_error\":\"" + Esc(audioErr) + "\"}";
            } catch (Exception e) {
                StopInner();
                lastError = e.Message;
                return "{\"ok\":false,\"error\":\"" + Esc(e.Message) + "\"}";
            }
        }
    }

    static void StopInner() {
        var p = proc;
        proc = null;
        if (p != null) {
            try {
                if (!p.HasExited) {
                    // „q“: FFmpeg schließt das laufende Stück sauber ab.
                    try { p.StandardInput.Write("q"); p.StandardInput.Flush(); } catch { }
                    if (!p.WaitForExit(4000)) { try { p.Kill(); } catch { } p.WaitForExit(2000); }
                }
            } catch { }
            try { p.Dispose(); } catch { }
        }
        CloseSource(sys); sys = null;
        CloseSource(mic); mic = null;
    }

    public static string Stop() {
        lock (gate) { StopInner(); }
        return "{\"ok\":true}";
    }

    // Läuft FFmpeg noch, letzte Meldungen, Ton-Zähler und Stromversorgung (Akku).
    public static string Status() {
        var sb = new StringBuilder("{");
        lock (gate) {
            bool run = Running();
            sb.Append("\"running\":").Append(run ? "true" : "false");
            if (proc != null) {
                sb.Append(",\"pid\":").Append(proc.Id);
                sb.Append(",\"uptime\":").Append(((int)(DateTime.UtcNow - started).TotalSeconds).ToString(CultureInfo.InvariantCulture));
                if (!run) { try { sb.Append(",\"code\":").Append(proc.ExitCode); } catch { } }
            }
            sb.Append(",\"t0\":\"").Append(t0Unix.ToString("F6", CultureInfo.InvariantCulture)).Append('"');
            foreach (var pair in new KeyValuePair<string, Source>[] { new KeyValuePair<string, Source>("sys", sys), new KeyValuePair<string, Source>("mic", mic) }) {
                var s = pair.Value;
                if (s == null) continue;
                sb.Append(",\"").Append(pair.Key).Append("\":{\"rate\":").Append(s.Rate).Append(",\"ch\":").Append(s.Channels)
                    .Append(",\"written\":").Append(s.Written).Append(",\"silence\":").Append(s.Silence)
                    .Append(",\"dropped\":").Append(s.Dropped).Append(",\"error\":\"").Append(Esc(s.Error)).Append("\"}");
            }
        }
        lock (errTail) sb.Append(",\"err\":\"").Append(Esc(string.Join(" | ", errTail.ToArray()))).Append('"');
        sb.Append(",\"last_error\":\"").Append(Esc(lastError)).Append('"');
        SYSTEM_POWER_STATUS ps;
        if (GetSystemPowerStatus(out ps)) {
            // ACLineStatus 0 = Akku; BatteryFlag 128 = kein Akku.
            sb.Append(",\"on_battery\":").Append(ps.ACLineStatus == 0 && ps.BatteryFlag != 128 ? "true" : "false");
            sb.Append(",\"battery\":").Append(ps.BatteryLifePercent == 255 ? -1 : (int)ps.BatteryLifePercent);
        }
        sb.Append('}');
        return sb.ToString();
    }
}
'@
$script:CapReady = $false
function Use-Capture {
    if (-not $script:CapReady) { Add-Type -TypeDefinition $script:CapSrc; $script:CapReady = $true }
}

try { [void][UzInput]::SetProcessDPIAware() } catch {}
$script:discord = $null
$script:mpv = $null
$script:mpvName = ''
$script:mpvReader = $null
$script:mpvWriter = $null

function Mpv-Reset {
    if ($script:mpv) { try { $script:mpv.Dispose() } catch {} }
    $script:mpv = $null
}

# Schickt fertige JSON-Zeilen an mpv und sammelt die Antworten mit passender request_id.
function Mpv-Call([string]$pipe, $cmds) {
    if (-not $script:mpv -or -not $script:mpv.IsConnected -or $script:mpvName -ne $pipe) {
        Mpv-Reset
        $p = New-Object IO.Pipes.NamedPipeClientStream('.', $pipe, [IO.Pipes.PipeDirection]::InOut)
        $p.Connect(800)
        $enc = New-Object Text.UTF8Encoding $false
        $script:mpvReader = New-Object IO.StreamReader($p, $enc)
        $script:mpvWriter = New-Object IO.StreamWriter($p, $enc)
        $script:mpvWriter.AutoFlush = $true
        $script:mpvWriter.NewLine = "`n"
        $script:mpv = $p
        $script:mpvName = $pipe
    }
    $ids = @()
    foreach ($c in $cmds) {
        $line = [string]$c
        $script:mpvWriter.WriteLine($line)
        $ids += [string](($line | ConvertFrom-Json).request_id)
    }
    $got = @{}
    while ($got.Count -lt $ids.Count) {
        $task = $script:mpvReader.ReadLineAsync()
        if (-not $task.Wait(1500)) { Mpv-Reset; throw 'mpv antwortet nicht' }
        $line = $task.Result
        if ($null -eq $line) { Mpv-Reset; throw 'mpv beendet' }
        if ($line -notmatch '"request_id"') { continue }
        $k = [string](($line | ConvertFrom-Json).request_id)
        if ($ids -contains $k) { $got[$k] = $line }
    }
    $out = New-Object Collections.Generic.List[string]
    foreach ($k in $ids) { $out.Add([string]$got[$k]) }
    return @{ results = $out.ToArray() }
}

function Find-Window([int]$procId) {
    return [UzWin]::Best([int[]]@($procId))
}

# Spielfenster aus einer oder mehreren Prozess-IDs (Spiele mit Launcher haben mehrere): das vorn
# liegende, sonst das größte – nicht einfach das erste (bei PCSX2 wäre das das Hauptfenster).
function Find-Target($a) {
    $hw = Get-Hwnd $a.hwnd
    if ($hw -ne 0) {
        $h = [IntPtr]$hw
        if ([UzWin]::IsWindowVisible($h)) { return $h }
    }
    $ids = @()
    foreach ($p in @($a.pids) + @($a.pid)) {
        $n = Get-Zahl $p 1 2147483647
        if ($null -ne $n) { $ids += $n }
    }
    if ($ids.Count -eq 0) { return [IntPtr]::Zero }
    return [UzWin]::Best([int[]]$ids)
}

# Tastenkombination wie „CTRL+SHIFT+F9“ in virtuelle Tasten zerlegen. Auch deutsche Namen
# (STRG, UMSCHALT); was unbekannt ist, steht in unknown – früher fiel es still weg, und aus
# „STRG+UMSCHALT+F9“ wurde nur F9.
# global: für Tastenbelegungen anderer Programme (Discord, Lossless Scaling). Dann die linken
# Umschalt-, Strg- und Alt-Tasten statt der allgemeinen – genau das meldet eine echte Tastatur,
# und so speichert Discord seine Tastenbelegung.
function Parse-Keys([string]$combo, [bool]$global) {
    $vk = @{ 'SHIFT' = 0x10; 'CTRL' = 0x11; 'ALT' = 0x12; 'WIN' = 0x5B; 'ESC' = 0x1B; 'ENTER' = 0x0D; 'SPACE' = 0x20; 'TAB' = 0x09; 'PRTSC' = 0x2C; 'DRUCK' = 0x2C
        'STRG' = 0x11; 'CONTROL' = 0x11; 'CTL' = 0x11; 'UMSCHALT' = 0x10; 'UMSCH' = 0x10; 'WINDOWS' = 0x5B; 'EINGABE' = 0x0D; 'LEER' = 0x20; 'LEERTASTE' = 0x20
        'LSHIFT' = 0xA0; 'RSHIFT' = 0xA1; 'LCTRL' = 0xA2; 'RCTRL' = 0xA3; 'LALT' = 0xA4; 'RALT' = 0xA5; 'ALTGR' = 0xA5
        'INS' = 0x2D; 'EINFG' = 0x2D; 'DEL' = 0x2E; 'ENTF' = 0x2E; 'HOME' = 0x24; 'POS1' = 0x24; 'END' = 0x23; 'ENDE' = 0x23
        'PGUP' = 0x21; 'BILDAUF' = 0x21; 'PGDN' = 0x22; 'BILDAB' = 0x22; 'UP' = 0x26; 'DOWN' = 0x28; 'LEFT' = 0x25; 'RIGHT' = 0x27
        'PAUSE' = 0x13; 'SCROLL' = 0x91; 'ROLLEN' = 0x91; 'BACKSPACE' = 0x08 }
    for ($i = 1; $i -le 24; $i++) { $vk["F$i"] = 0x6F + $i }
    for ($i = 0; $i -le 9; $i++) { $vk["NUM$i"] = 0x60 + $i }
    $codes = @()
    $unknown = @()
    foreach ($p in $combo.ToUpper().Split('+')) {
        $p = $p.Trim()
        if ($p -eq '') { continue }
        if ($vk.ContainsKey($p)) { $c = [int]$vk[$p] }
        elseif ($p.Length -eq 1 -and $p -match '^[A-Z0-9]$') { $c = [int][char]$p }
        else { $unknown += $p; continue }
        if ($global) {
            if ($c -eq 0x10) { $c = 0xA0 } elseif ($c -eq 0x11) { $c = 0xA2 } elseif ($c -eq 0x12) { $c = 0xA4 }
        }
        $codes += $c
    }
    return @{ codes = $codes; unknown = $unknown }
}

# --- Eingaben an Fenster (docs/SECURITY.md „Eingaben an Fenster“) -----------------------------------
# Jede Tastenkombination wird hier geprüft, bevor sie gedrückt wird. Rückgabe: '' (erlaubt),
# 'unbekannt' (Tastenname unbekannt) oder 'nicht erlaubt'. Arten:
#   global  – Tastenbelegung von Discord oder Lossless Scaling (wirkt systemweit): nur Strg, Alt,
#             Umschalt und genau eine Taste aus A–Z, 0–9, F1–F24; Buchstaben und Ziffern nur mit Strg
#             oder Alt (sonst tippte es ins Spiel). Nie die Windows-Taste.
#   fenster – an ein Fenster, das vorher sicher vorn ist (Emulator-Kürzel, Clip, Steam-Overlay,
#             Strg+V in Discord/Steam): Tasten wie in Parse-Keys, die Windows-Taste nur für die
#             Aufnahme-Kürzel der Game Bar (Win+G, Win+Druck, Win+Alt+G/R/Druck).
#   dialog  – ein Fenster in Uzai bedienen (window-keys): nur Tab, Umschalt+Tab, Pfeile, Enter,
#             Leertaste, Esc.
#   app     – Controller in einer eigenen App (app-pad, app-vollbild): nur F11, Esc, Pfeile, Enter,
#             Leertaste, Backspace, Tab und Umschalt+Tab.
# Immer abgelehnt: Alt+F4, Alt+Tab, Alt+Esc, Alt+Leertaste, Strg+Esc, Strg+Umschalt+Esc,
# Strg+Alt+Entf/Ende, mehr als 4 Tasten, eine Taste doppelt, mehr als eine Nicht-Umschalttaste,
# mehr als 40 Zeichen oder andere Zeichen als Buchstaben, Ziffern, + und Leerzeichen.
function Test-KeyCombo([string]$combo, [string]$mode) {
    if ($combo.Length -eq 0 -or $combo.Length -gt 40 -or $combo -cnotmatch '^[A-Za-z0-9+ ]+\z') { return 'nicht erlaubt' }
    $parsed = Parse-Keys $combo ($mode -eq 'global')
    if (@($parsed.unknown).Count -gt 0) { return 'unbekannt' }
    $codes = @($parsed.codes)
    if ($codes.Count -eq 0 -or $codes.Count -gt 4) { return 'nicht erlaubt' }
    $ctrl = $false; $alt = $false; $shift = $false; $win = $false
    $main = @()
    $seen = @{}
    foreach ($c in $codes) {
        $c = [int]$c
        if ($c -eq 0x10 -or $c -eq 0xA0 -or $c -eq 0xA1) { $k = 'shift'; $shift = $true }
        elseif ($c -eq 0x11 -or $c -eq 0xA2 -or $c -eq 0xA3) { $k = 'ctrl'; $ctrl = $true }
        elseif ($c -eq 0x12 -or $c -eq 0xA4 -or $c -eq 0xA5) { $k = 'alt'; $alt = $true }
        elseif ($c -eq 0x5B -or $c -eq 0x5C) { $k = 'win'; $win = $true }
        else { $k = 'k' + $c; $main += $c }
        if ($seen.ContainsKey($k)) { return 'nicht erlaubt' }
        $seen[$k] = $true
    }
    if ($main.Count -ne 1) { return 'nicht erlaubt' }
    $m = [int]$main[0]
    # Fenster schließen oder wechseln, Startmenü, Task-Manager, Sicherheitsbildschirm.
    if ($alt -and (@(0x73, 0x09, 0x1B, 0x20) -contains $m)) { return 'nicht erlaubt' }
    if ($ctrl -and $m -eq 0x1B) { return 'nicht erlaubt' }
    if ($ctrl -and $alt -and ($m -eq 0x2E -or $m -eq 0x23)) { return 'nicht erlaubt' }
    $letter = ($m -ge 0x41 -and $m -le 0x5A) -or ($m -ge 0x30 -and $m -le 0x39)
    $fkey = ($m -ge 0x70 -and $m -le 0x87)
    if ($mode -eq 'global') {
        if ($win) { return 'nicht erlaubt' }
        if ($fkey -or ($letter -and ($ctrl -or $alt))) { return '' }
        return 'nicht erlaubt'
    }
    if ($mode -eq 'dialog') {
        if ($ctrl -or $alt -or $win -or ($shift -and $m -ne 0x09)) { return 'nicht erlaubt' }
        if (@(0x09, 0x25, 0x26, 0x27, 0x28, 0x0D, 0x20, 0x1B) -contains $m) { return '' }
        return 'nicht erlaubt'
    }
    if ($mode -eq 'app') {
        if ($ctrl -or $alt -or $win -or ($shift -and $m -ne 0x09)) { return 'nicht erlaubt' }
        if (@(0x7A, 0x1B, 0x25, 0x26, 0x27, 0x28, 0x0D, 0x20, 0x08, 0x09) -contains $m) { return '' }
        return 'nicht erlaubt'
    }
    if ($mode -ne 'fenster') { return 'nicht erlaubt' }
    if ($win) {
        if ($ctrl -or $shift) { return 'nicht erlaubt' }
        if (-not $alt -and ($m -eq 0x47 -or $m -eq 0x2C)) { return '' }
        if ($alt -and (@(0x47, 0x52, 0x2C) -contains $m)) { return '' }
        return 'nicht erlaubt'
    }
    return ''
}

# Wie oft gedrückt werden darf, je Art – gegen eine Schleife, die nicht mehr aufhört: Mindestabstand
# in ms und höchstens so viele je Minute (je Helfer-Prozess). Gezählt wird beim Freigeben.
$script:KeyClock = [Diagnostics.Stopwatch]::StartNew()
$script:KeyLog = @{}
$script:KeyLimit = @{ global = @(400, 12); fenster = @(120, 60); dialog = @(40, 240); media = @(200, 40) }
function Test-KeyRate([string]$kind) {
    $lim = $script:KeyLimit[$kind]
    if ($null -eq $lim) { return $false }
    $now = $script:KeyClock.ElapsedMilliseconds
    $list = $script:KeyLog[$kind]
    if ($null -eq $list) { $list = New-Object Collections.Generic.List[long]; $script:KeyLog[$kind] = $list }
    while ($list.Count -gt 0 -and $now - $list[0] -ge 60000) { $list.RemoveAt(0) }
    if ($list.Count -gt 0 -and $now - $list[$list.Count - 1] -lt $lim[0]) { return $false }
    if ($list.Count -ge $lim[1]) { return $false }
    $list.Add($now)
    return $true
}

# Gehört ein Programm wirklich zu dieser App? Prozessname UND Programmpfad – ein umbenanntes Programm
# anderswo zählt nicht. discord: %LOCALAPPDATA%\Discord…\app-<Fassung>\Discord….exe (so installiert
# sich die Discord-App); steam: im Steam-Ordner aus der Registry des eigenen Kontos; epic:
# …\Epic Games\Launcher\Portal|Engine\Binaries\Win64|Win32\….exe.
function Test-AppPath([string]$app, [string]$name, [string]$path, [string]$local, [string]$steam) {
    if ($name -eq '' -or $path -eq '') { return $false }
    $p = $path -replace '/', '\'
    if ($p -match '\\\.\.?\\') { return $false }
    if ($app -eq 'discord') {
        if (@('Discord', 'DiscordPTB', 'DiscordCanary', 'DiscordDevelopment') -notcontains $name -or $local -eq '') { return $false }
        $l = ($local -replace '/', '\').TrimEnd('\')
        return ($p -match ('^' + [regex]::Escape($l) + '\\' + $name + '\\app-[0-9.]{1,32}\\' + $name + '\.exe\z'))
    }
    if ($app -eq 'steam') {
        if (@('steam', 'steamwebhelper') -notcontains $name -or $steam -eq '') { return $false }
        $d = ($steam -replace '/', '\').TrimEnd('\') + '\'
        return ($p.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) -and $p -match ('\\' + $name + '\.exe\z'))
    }
    if ($app -eq 'spotify') {
        # Spotify-App: %APPDATA%\Spotify\Spotify.exe ($local ist hier APPDATA) oder die Store-App.
        if ($name -ne 'Spotify') { return $false }
        if ($local -ne '') {
            $l = ($local -replace '/', '\').TrimEnd('\')
            if ($p -match ('^' + [regex]::Escape($l) + '\\Spotify\\Spotify\.exe\z')) { return $true }
        }
        return ($p -match '^[A-Za-z]:\\Program Files\\WindowsApps\\SpotifyAB\.SpotifyMusic_[0-9.]{1,32}_(?:x64|x86|arm64|neutral)__zpdnekdrzrea0\\Spotify\.exe\z')
    }
    if ($app -eq 'epic') {
        if (@('EpicGamesLauncher', 'EpicWebHelper') -notcontains $name) { return $false }
        return ($p -match ('^[A-Za-z]:\\(?:[^\\]+\\)*Epic Games\\Launcher\\(?:Portal|Engine)\\Binaries\\Win(?:64|32)\\' + $name + '\.exe\z'))
    }
    return $false
}

function Get-SteamDir {
    $v = ''
    try { $v = [string](Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch {}
    return $v
}

# Fenster einer der erlaubten Apps? @{ ok; app; pid; name } – sonst ok = $false und why
# ("kein Fenster", "geschützt", "falsches Programm").
function Test-AppWindow([long]$hwnd, [string[]]$apps) {
    if ($hwnd -le 0) { return @{ ok = $false; why = 'kein Fenster' } }
    $h = [IntPtr]$hwnd
    if (-not [UzWin]::IsWindow($h)) { return @{ ok = $false; why = 'kein Fenster' } }
    if ([UzGuard]::Problem($h) -ne '') { return @{ ok = $false; why = 'geschützt' } }
    $wpid = [UzWin]::PidOf($h)
    $name = ''
    try { $name = [string](Get-Process -Id $wpid -ErrorAction Stop).ProcessName } catch {}
    $path = ''
    try { $path = [UzLs]::ImagePath($wpid) } catch {}
    $steam = ''
    if ($apps -contains 'steam') { $steam = Get-SteamDir }
    foreach ($app in $apps) {
        $base = [string]$env:LOCALAPPDATA
        if ($app -eq 'spotify') { $base = [string]$env:APPDATA }
        if (Test-AppPath $app $name $path $base $steam) { return @{ ok = $true; app = $app; pid = $wpid; name = $name } }
    }
    return @{ ok = $false; why = 'falsches Programm'; name = $name }
}

# Laufende Discord-Apps (auch PTB, Canary) und ob sie mit Adminrechten laufen – für die
# Fehlersuche bei „Übertragen“.
function Discord-Processes {
    $out = @()
    foreach ($n in 'Discord', 'DiscordPTB', 'DiscordCanary', 'DiscordDevelopment') {
        $ps = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        if ($ps.Count -eq 0) { continue }
        $e = $null
        try { $e = [UzElev]::IsElevated($ps[0].Id) } catch {}
        $out += @{ name = $n; count = $ps.Count; elevated = $e }
    }
    return $out
}

# Drückt die Kombination der Reihe nach (erst die Umschalttasten), hält sie hold ms und lässt in
# umgekehrter Reihenfolge los. Programme, die ihre Tastenbelegung nur alle paar Millisekunden
# abfragen, verpassten früher den kurzen Druck (60 ms); für global sind es 150 ms.
# Rückgabe: wie viele Tastenereignisse Windows angenommen hat (soll: zweimal die Tastenzahl).
function Send-Keys([string]$combo, [bool]$global = $false, [int]$hold = 0) {
    $codes = @((Parse-Keys $combo $global).codes)
    if ($hold -le 0) { $hold = if ($global) { 150 } else { 60 } }
    # Höchstens 2 s halten: Solange wartet der Helfer hier und nimmt keinen anderen Befehl an.
    if ($hold -gt 2000) { $hold = 2000 }
    $n = 0
    foreach ($c in $codes) { $n += [UzInput]::Key([uint16]$c, $true); Start-Sleep -Milliseconds 30 }
    Start-Sleep -Milliseconds $hold
    [array]::Reverse($codes)
    foreach ($c in $codes) { $n += [UzInput]::Key([uint16]$c, $false); Start-Sleep -Milliseconds 20 }
    return $n
}

function Discord-Send([int]$op, $obj) {
    $json = $obj | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $hdr = New-Object byte[] 8
    [BitConverter]::GetBytes($op).CopyTo($hdr, 0)
    [BitConverter]::GetBytes([int]$bytes.Length).CopyTo($hdr, 4)
    $script:discord.Write($hdr, 0, 8)
    $script:discord.Write($bytes, 0, $bytes.Length)
    $script:discord.Flush()
}

function Discord-Drop {
    try { if ($script:discord) { $script:discord.Dispose() } } catch {}
    $script:discord = $null
}

# Liest genau $len Bytes, mit Zeitlimit. Früher ohne: antwortete die Discord-App nicht, hing der
# ganze Helfer für immer; brach die Leitung mitten in einer Nachricht ab (Read = 0), lief eine
# Endlosschleife mit voller CPU.
function Discord-ReadExact([byte[]]$buf, [int]$len, [int]$ms) {
    $read = 0
    while ($read -lt $len) {
        $task = $script:discord.ReadAsync($buf, $read, $len - $read)
        if (-not $task.Wait($ms)) { Discord-Drop; throw 'Discord antwortet nicht' }
        $n = $task.Result
        if ($n -le 0) { Discord-Drop; throw 'Discord-Verbindung getrennt' }
        $read += $n
    }
}

function Discord-Read([int]$ms = 4000) {
    $hdr = New-Object byte[] 8
    Discord-ReadExact $hdr 8 $ms
    $len = [BitConverter]::ToInt32($hdr, 4)
    if ($len -lt 0 -or $len -gt 16MB) { Discord-Drop; throw 'Discord: ungültige Antwort' }
    $buf = New-Object byte[] $len
    if ($len -gt 0) { Discord-ReadExact $buf $len $ms }
    return [Text.Encoding]::UTF8.GetString($buf)
}

function Discord-Connect([string]$clientId) {
    if ($script:discord -and $script:discord.IsConnected) { return }
    $script:discord = $null
    # Nur Leitungen probieren, die es gibt: ohne laufendes Discord kostete jeder Versuch
    # 10 × 300 ms, in denen der Helfer nichts anderes tat.
    $names = @()
    # Nur discord-ipc-0 … 9 (wie Discord sie anlegt) und nur, wenn die Discord-App dahinter steht ([UzRpc]::IstDiscord):
    # Ein fremdes Programm mit einem passenden Namen bekäme sonst Spiel und Status.
    try { $names = @([IO.Directory]::GetFiles('\\.\pipe\') | ForEach-Object { [IO.Path]::GetFileName($_) } | Where-Object { $_ -match '^discord-ipc-[0-9]\z' } | Sort-Object) } catch { $names = @(0..9 | ForEach-Object { "discord-ipc-$_" }) }
    Use-Rpc
    foreach ($name in $names) {
        try {
            $p = New-Object IO.Pipes.NamedPipeClientStream('.', $name, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
            $p.Connect(300)
            if (-not [UzRpc]::IstDiscord($p.SafePipeHandle)) { $p.Dispose(); continue }
            $script:discord = $p
            break
        } catch {}
    }
    if (-not $script:discord) { throw 'Discord läuft nicht.' }
    Discord-Send 0 @{ v = 1; client_id = $clientId }
    $null = Discord-Read
}

# Bildschirmfoto des Hauptbildschirms nach Bilder\Uzai (eigene Funktion, damit System.Drawing
# erst beim Gebrauch geladen wird).
function Take-Screenshot([string]$title) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    # Auch wenn Aufnehmen oder Speichern scheitert (gesperrter Bildschirm, volle Platte): Bild und Zeichenfläche
    # freigeben – ein Bild in Bildschirmgröße bliebe sonst im Speicher, bis .NET irgendwann aufräumt.
    try {
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $dir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Uzai'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $name = ($title -replace '[\\/:*?"<>|]', '').Trim()
        if ($name -eq '') { $name = 'Uzai' }
        $file = Join-Path $dir ($name + ' ' + (Get-Date -Format 'yyyy-MM-dd HH-mm-ss') + '.png')
        $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $g.Dispose(); $bmp.Dispose() }
    return @{ file = $file }
}

# Schnellfortsetzen (quick_resume.gd): kleines Vorschaubild des Spiels als JPEG in Uzais
# Datenordner (nicht in „Bilder“), $w Pixel breit.
function Take-Thumb([string]$file, [int]$w) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    if ($w -lt 64) { $w = 480 }
    if ($w -gt 1920) { $w = 1920 }
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $small = $null
    $g2 = $null
    # Wie bei Take-Screenshot: auch im Fehlerfall alles freigeben.
    try {
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $h = [Math]::Max(1, [int][Math]::Round($w * $b.Height / [double]$b.Width))
        $small = New-Object System.Drawing.Bitmap $w, $h
        $g2 = [System.Drawing.Graphics]::FromImage($small)
        $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g2.DrawImage($bmp, 0, 0, $w, $h)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
        $small.Save($file, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    } finally {
        if ($null -ne $g2) { $g2.Dispose() }
        if ($null -ne $small) { $small.Dispose() }
        $g.Dispose(); $bmp.Dispose()
    }
    return @{ file = $file; w = $w; h = $h }
}

# Ruhemodus (rest.gd): Bildschirm aus und wieder an – nur für den Augenblick, keine Einstellung
# von Windows wird geändert. PostMessage statt SendMessage: ein Broadcast mit SendMessage wartet
# auf jedes Fenster, ein hängendes Programm hielte den Helfer fest.
$script:ScreenSrc = @"
using System;
using System.Runtime.InteropServices;

public static class UzScreen {
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
    const uint WM_SYSCOMMAND = 0x0112;
    const int SC_MONITORPOWER = 0xF170;
    static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);

    public static bool Off() {
        return PostMessage(HWND_BROADCAST, WM_SYSCOMMAND, new IntPtr(SC_MONITORPOWER), new IntPtr(2));
    }

    // -1 (an) beachten neuere Windows-Versionen oft nicht; eine winzige Mausbewegung hin und
    // zurück weckt den Bildschirm sicher, ES_DISPLAY_REQUIRED setzt den Bildschirm-Zeitgeber zurück.
    public static bool On() {
        bool ok = PostMessage(HWND_BROADCAST, WM_SYSCOMMAND, new IntPtr(SC_MONITORPOWER), new IntPtr(-1));
        mouse_event(0x0001, 0, 1, 0, UIntPtr.Zero);
        mouse_event(0x0001, 0, -1, 0, UIntPtr.Zero);
        SetThreadExecutionState(0x00000002);
        return ok;
    }
}
"@
$script:ScreenReady = $false
function Use-Screen {
    if (-not $script:ScreenReady) { Add-Type -TypeDefinition $script:ScreenSrc; $script:ScreenReady = $true }
}

# Steam-Einladung ohne Overlay: Uzai lädt die Steamworks-Bibliothek, die jedes Steam-Spiel
# mitbringt, meldet sich mit der App-ID des laufenden Spiels bei Steam an und schickt die
# Einladung genau so, wie es das Overlay tun würde (Rich-Presence „connect“ oder Lobby).
# Läuft nur im Einmal-Modus (eigener Prozess), damit der Hauptfelfer nie an ein Spiel gebunden ist.
$script:InviteSrc = @"
using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;

public static class UzSteamInvite {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)] static extern IntPtr GetProcAddress(IntPtr h, string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool SetDllDirectoryW(string path);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] delegate bool InitFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitFlatFn(IntPtr err);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void VoidFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr PtrFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int HUserFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr FindIfaceFn(int user, [MarshalAs(UnmanagedType.LPStr)] string version);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong SteamIdFn(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr RichPresenceFn(IntPtr self, ulong id, [MarshalAs(UnmanagedType.LPStr)] string key);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] delegate bool InviteGameFn(IntPtr self, ulong id, [MarshalAs(UnmanagedType.LPStr)] string connect);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] delegate bool GamePlayedFn(IntPtr self, ulong id, IntPtr info);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] delegate bool InviteLobbyFn(IntPtr self, ulong lobby, ulong invitee);

    static IntPtr lib;

    static T Fn<T>(string name) where T : class {
        IntPtr p = GetProcAddress(lib, name);
        if (p == IntPtr.Zero) return null;
        return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }

    static IntPtr Iface(string[] accessors, string[] versions) {
        foreach (var a in accessors) {
            var f = Fn<PtrFn>(a);
            if (f != null) { var p = f(); if (p != IntPtr.Zero) return p; }
        }
        var hu = Fn<HUserFn>("SteamAPI_GetHSteamUser");
        var find = Fn<FindIfaceFn>("SteamInternal_FindOrCreateUserInterface");
        if (hu != null && find != null) {
            int user = hu();
            foreach (var v in versions) { var p = find(user, v); if (p != IntPtr.Zero) return p; }
        }
        return IntPtr.Zero;
    }

    static string Json(bool ok, string method, string reason) {
        return "{\"ok\":" + (ok ? "true" : "false") + ",\"method\":\"" + method + "\",\"reason\":\"" + reason.Replace("\\", "/").Replace("\"", "'") + "\"}";
    }

    public static string Invite(string dll, ulong friend) {
        try { return InviteInner(dll, friend); }
        catch (Exception e) { return Json(false, "", "Fehler: " + e.Message); }
    }

    static string InviteInner(string dll, ulong friend) {
        if (string.IsNullOrEmpty(dll) || !System.IO.File.Exists(dll)) return Json(false, "", "Steamworks-Bibliothek des Spiels nicht gefunden");
        SetDllDirectoryW(System.IO.Path.GetDirectoryName(dll));
        lib = LoadLibraryW(dll);
        if (lib == IntPtr.Zero) return Json(false, "", "Steamworks-Bibliothek ließ sich nicht laden");
        bool started = false;
        var initFlat = Fn<InitFlatFn>("SteamAPI_InitFlat");
        if (initFlat != null) {
            IntPtr err = Marshal.AllocHGlobal(1024);
            started = initFlat(err) == 0;
            Marshal.FreeHGlobal(err);
        } else {
            var init = Fn<InitFn>("SteamAPI_Init");
            if (init != null) started = init();
        }
        if (!started) return Json(false, "", "Steam ist nicht erreichbar (läuft Steam?)");
        var run = Fn<VoidFn>("SteamAPI_RunCallbacks");
        var shutdown = Fn<VoidFn>("SteamAPI_Shutdown");
        try {
            IntPtr friends = Iface(new[] { "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v016", "SteamAPI_SteamFriends_v015", "SteamFriends" },
                new[] { "SteamFriends017", "SteamFriends016", "SteamFriends015" });
            IntPtr user = Iface(new[] { "SteamAPI_SteamUser_v023", "SteamAPI_SteamUser_v022", "SteamAPI_SteamUser_v021", "SteamAPI_SteamUser_v020", "SteamUser" },
                new[] { "SteamUser023", "SteamUser022", "SteamUser021", "SteamUser020", "SteamUser019" });
            IntPtr mm = Iface(new[] { "SteamAPI_SteamMatchmaking_v009", "SteamMatchmaking" }, new[] { "SteamMatchMaking009" });
            var getId = Fn<SteamIdFn>("SteamAPI_ISteamUser_GetSteamID");
            var rp = Fn<RichPresenceFn>("SteamAPI_ISteamFriends_GetFriendRichPresence");
            var inviteGame = Fn<InviteGameFn>("SteamAPI_ISteamFriends_InviteUserToGame");
            var played = Fn<GamePlayedFn>("SteamAPI_ISteamFriends_GetFriendGamePlayed");
            var inviteLobby = Fn<InviteLobbyFn>("SteamAPI_ISteamMatchmaking_InviteUserToLobby");
            if (friends == IntPtr.Zero || user == IntPtr.Zero || getId == null || inviteGame == null)
                return Json(false, "", "Diese Steamworks-Version kennt Uzai nicht");
            // Steam braucht einen Moment, bis der Stand des Spiels (Lobby, Rich Presence) da ist.
            for (int i = 0; i < 12; i++) { if (run != null) run(); Thread.Sleep(100); }
            ulong me = getId(user);
            string connect = "";
            if (rp != null) {
                IntPtr c = rp(friends, me, "connect");
                if (c != IntPtr.Zero) connect = Marshal.PtrToStringAnsi(c) ?? "";
            }
            if (connect != "") {
                bool ok = inviteGame(friends, friend, connect);
                for (int i = 0; i < 5; i++) { if (run != null) run(); Thread.Sleep(100); }
                return Json(ok, "connect", ok ? "" : "Steam hat die Einladung abgelehnt");
            }
            ulong lobby = 0;
            if (played != null) {
                IntPtr info = Marshal.AllocHGlobal(32);
                for (int i = 0; i < 32; i++) Marshal.WriteByte(info, i, 0);
                if (played(friends, me, info)) lobby = (ulong)Marshal.ReadInt64(info, 16);
                Marshal.FreeHGlobal(info);
            }
            if (lobby != 0) {
                bool ok = (inviteLobby != null && mm != IntPtr.Zero) && inviteLobby(mm, lobby, friend);
                if (!ok) ok = inviteGame(friends, friend, "+connect_lobby " + lobby);
                for (int i = 0; i < 5; i++) { if (run != null) run(); Thread.Sleep(100); }
                return Json(ok, "lobby", ok ? "" : "Steam hat die Einladung abgelehnt") .Replace("\"reason\"", "\"lobby\":\"" + lobby + "\",\"reason\"");
            }
            return Json(false, "none", "Das Spiel bietet gerade keine Einladung an");
        } finally {
            if (shutdown != null) shutdown();
        }
    }
}
"@

## Einen Knopf in Discord drücken (per Windows-Bedienhilfe), zum Beispiel "Stream ansehen".
## patterns: reguläre Ausdrücke für den Namen des Knopfs (Discord auf Deutsch oder Englisch).

function Steam-Invite($a) {
    Add-Type -TypeDefinition $script:InviteSrc
    [Environment]::SetEnvironmentVariable('SteamAppId', [string]$a.appid, 'Process')
    [Environment]::SetEnvironmentVariable('SteamGameId', [string]$a.appid, 'Process')
    $json = [UzSteamInvite]::Invite([string]$a.dll, [UInt64]::Parse([string]$a.friend))
    return ($json | ConvertFrom-Json)
}

# --- Remote Play Together für jedes Spiel ------------------------------------------------------
# Steam erlaubt Remote Play Together nur in Steam-Spielen, die es können. Uzai leiht sich dafür
# ein „Spender“-Spiel (z. B. das kostenlose RetroArch): Dessen Programmdatei wird (mit Sicherung)
# durch einen kleinen Starter ersetzt. Steam startet den Spender, der Starter startet das Spiel,
# das Uzai in eine Auftragsdatei geschrieben hat, und Steam hält alles für den Spender.
# Der Starter wird auf dem PC des Nutzers mit Add-Type gebaut (.NET Framework 4, C# 5).
$script:StarterSrc = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UzaiStarter {
    public const string Version = "3";
    public const string JobFile = "uzai-remoteplay-auftrag.txt";
    public const string StatusFile = "uzai-remoteplay-status.txt";
    public const string LogFile = "uzai-remoteplay.log";
    public const string Suffix = ".uzai-original.exe";
    public const int MaxAge = 300;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObjectW(IntPtr attr, string name);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll")] static extern bool QueryInformationJobObject(IntPtr job, int cls, IntPtr info, uint len, IntPtr ret);

    [StructLayout(LayoutKind.Sequential)] public struct BasicLimit {
        public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] public struct IoCounters { public ulong R, W, O, RB, WB, OB; }
    [StructLayout(LayoutKind.Sequential)] public struct ExtLimit {
        public BasicLimit Basic; public IoCounters Io; public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
    }

    static string dir = "";
    static StringBuilder log = new StringBuilder();
    static int pads = -1;

    // Controller, wie Steam sie dem Spiel zeigt (der Starter läuft in Steams Spielumgebung; der
    // Controller eines Remote-Play-Gasts kommt hier als weiterer Controller an).
    [StructLayout(LayoutKind.Sequential)] public struct XState { public uint Packet; public ushort Buttons; public byte LT; public byte RT; public short LX; public short LY; public short RX; public short RY; }
    [DllImport("xinput1_4.dll")] static extern int XInputGetState(int index, out XState s);

    public static int CountPads() {
        try {
            int n = 0;
            for (int i = 0; i < 4; i++) { XState st; if (XInputGetState(i, out st) == 0) n++; }
            return n;
        } catch (Exception) { return -1; }
    }

    // Konsolenprogramm (PE-Subsystem 3) oder Batchdatei? Die starten ohne schwarzes Fenster.
    public static bool Quiet(string path) {
        string ext = Path.GetExtension(path).ToLowerInvariant();
        if (ext == ".bat" || ext == ".cmd") return true;
        try {
            using (var f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                var r = new BinaryReader(f);
                if (r.ReadUInt16() != 0x5A4D) return false;
                f.Seek(0x3C, SeekOrigin.Begin);
                int pe = r.ReadInt32();
                if (pe <= 0 || pe + 0x60 > f.Length) return false;
                f.Seek(pe, SeekOrigin.Begin);
                if (r.ReadUInt32() != 0x00004550) return false;
                f.Seek(pe + 0x5C, SeekOrigin.Begin);
                return r.ReadUInt16() == 3;
            }
        } catch (Exception) { return false; }
    }

    // Windows-Fehler 740: Das Programm verlangt Adminrechte, der Starter (von Steam) hat keine.
    public static string StartError(int code, string msg) {
        return code == 740 ? "admin:" + msg : msg;
    }

    // Auftrags- und Statusdatei: Zeilen „schlüssel=wert“, „env=NAME=WERT“ darf mehrfach vorkommen.
    public static Dictionary<string, string> ParseKv(string text, List<string> env) {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (text == null) return d;
        if (text.Length > 0 && text[0] == '﻿') text = text.Substring(1);
        foreach (var raw in text.Split('\n')) {
            var line = raw.TrimEnd('\r');
            if (line.Length == 0 || line[0] == '#') continue;
            int i = line.IndexOf('=');
            if (i <= 0) continue;
            string k = line.Substring(0, i).Trim();
            string v = line.Substring(i + 1);
            if (k == "env") { if (env != null) env.Add(v); }
            else d[k] = v;
        }
        return d;
    }

    public static string Get(Dictionary<string, string> d, string k) {
        string v;
        return d.TryGetValue(k, out v) ? v : "";
    }

    // Ein Auftrag gilt nur kurz: Startet jemand den Spender später selbst in Steam, kommt das Original.
    public static bool IsFresh(string zeit, long now) {
        long t;
        if (!long.TryParse(zeit, out t)) return false;
        return now - t <= MaxAge && t - now <= 60;
    }

    public static string OriginalPath(string self) {
        return Path.Combine(Path.GetDirectoryName(self), Path.GetFileNameWithoutExtension(self) + Suffix);
    }

    // Was Steam beim Start nach dem Programmnamen mitgibt (für das Original durchreichen).
    public static string ArgsAfterExe(string cmd) {
        if (string.IsNullOrEmpty(cmd)) return "";
        cmd = cmd.TrimStart();
        int i;
        if (cmd.StartsWith("\"")) {
            i = cmd.IndexOf('"', 1);
            if (i < 0) return "";
            i++;
        } else {
            i = cmd.IndexOf(' ');
            if (i < 0) return "";
        }
        return cmd.Substring(i).Trim();
    }

    static long Now() {
        return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
    }

    static void Log(string s) {
        log.AppendLine(DateTime.Now.ToString("HH:mm:ss") + " " + s);
        try { File.WriteAllText(Path.Combine(dir, LogFile), log.ToString(), new UTF8Encoding(false)); } catch (Exception) { }
    }

    static void Status(string id, int pid, string state, string err) {
        string text = "id=" + id + "\r\npid=" + pid + "\r\nzustand=" + state + "\r\nfehler=" + (err ?? "").Replace("\r", " ").Replace("\n", " ") + "\r\npads=" + pads + "\r\nzeit=" + Now() + "\r\n";
        try { File.WriteAllText(Path.Combine(dir, StatusFile), text, new UTF8Encoding(false)); } catch (Exception) { }
    }

    // Alle Prozesse im Job (das Spiel und was es selbst startet). null: Abfrage geht nicht.
    static List<int> JobPids(IntPtr job) {
        int n = 256;
        int size = 8 + n * IntPtr.Size;
        IntPtr buf = Marshal.AllocHGlobal(size);
        try {
            for (int i = 0; i < 8; i++) Marshal.WriteByte(buf, i, 0);
            if (!QueryInformationJobObject(job, 3, buf, (uint)size, IntPtr.Zero)) return null;
            var list = new List<int>();
            int cnt = Marshal.ReadInt32(buf, 4);
            for (int i = 0; i < cnt && i < n; i++) list.Add((int)Marshal.ReadIntPtr(buf, 8 + i * IntPtr.Size).ToInt64());
            return list;
        } finally { Marshal.FreeHGlobal(buf); }
    }

    public static int Main(string[] argv) {
        string self = "";
        try { self = System.Reflection.Assembly.GetEntryAssembly().Location; } catch (Exception) { }
        if (string.IsNullOrEmpty(self)) self = Process.GetCurrentProcess().MainModule.FileName;
        dir = Path.GetDirectoryName(self);
        string jobPath = Path.Combine(dir, JobFile);
        string id = "", exe = "", args = "", wd = "";
        var env = new List<string>();
        if (File.Exists(jobPath)) {
            string text = "";
            try { text = File.ReadAllText(jobPath, Encoding.UTF8); File.Delete(jobPath); }
            catch (Exception e) { Log("Auftrag nicht lesbar: " + e.Message); }
            var kv = ParseKv(text, env);
            if (IsFresh(Get(kv, "zeit"), Now())) {
                id = Get(kv, "id"); exe = Get(kv, "exe"); args = Get(kv, "args"); wd = Get(kv, "dir");
                Log("Auftrag " + id + ": " + exe + " " + args);
            } else {
                env.Clear();
                Log("Auftrag zu alt, starte das Original");
            }
        }
        if (exe == "") {
            exe = OriginalPath(self);
            args = ArgsAfterExe(Environment.CommandLine);
            wd = dir;
            Log("Kein Auftrag, starte das Original: " + exe + " " + args);
        }
        if (wd == "" || !Directory.Exists(wd)) wd = Path.GetDirectoryName(exe);
        if (!File.Exists(exe)) {
            Log("Nicht gefunden: " + exe);
            Status(id, 0, "fehler", "Programm nicht gefunden: " + exe);
            return 2;
        }
        var psi = new ProcessStartInfo(exe, args);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = Quiet(exe);
        psi.WorkingDirectory = wd;
        foreach (var e in env) {
            int i = e.IndexOf('=');
            if (i > 0) psi.EnvironmentVariables[e.Substring(0, i)] = e.Substring(i + 1);
        }
        Process p;
        try { p = Process.Start(psi); }
        catch (System.ComponentModel.Win32Exception wx) {
            Log("Start ging nicht (" + wx.NativeErrorCode + "): " + wx.Message);
            Status(id, 0, "fehler", StartError(wx.NativeErrorCode, wx.Message));
            return 3;
        }
        catch (Exception ex) {
            Log("Start ging nicht: " + ex.Message);
            Status(id, 0, "fehler", ex.Message);
            return 3;
        }
        // Job: Uzai und Steam sehen das Spiel samt allem, was es selbst startet. Beendet Steam den
        // Starter, endet auch das Spiel.
        IntPtr job = CreateJobObjectW(IntPtr.Zero, null);
        bool inJob = false;
        if (job != IntPtr.Zero) {
            var lim = new ExtLimit();
            lim.Basic.LimitFlags = 0x2000;
            int len = Marshal.SizeOf(typeof(ExtLimit));
            IntPtr buf = Marshal.AllocHGlobal(len);
            Marshal.StructureToPtr(lim, buf, false);
            SetInformationJobObject(job, 9, buf, (uint)len);
            Marshal.FreeHGlobal(buf);
            inJob = AssignProcessToJobObject(job, p.Handle);
        }
        int cur = p.Id;
        pads = CountPads();
        Status(id, cur, "laeuft", "");
        Log("Läuft: Prozess " + cur + (inJob ? " (Job)" : "") + ", Controller: " + pads);
        int tick = 0;
        while (true) {
            if (inJob) {
                var pids = JobPids(job);
                if (pids == null) inJob = false;
                else if (pids.Count == 0) break;
                else if (!pids.Contains(cur)) {
                    cur = pids[0];
                    Status(id, cur, "laeuft", "");
                    Log("Weiter mit Prozess " + cur);
                }
            }
            if (!inJob && p.HasExited) break;
            if (++tick % 3 == 0) {
                int n = CountPads();
                if (n != pads) {
                    Log("Controller: " + pads + " → " + n);
                    pads = n;
                    Status(id, cur, "laeuft", "");
                }
            }
            Thread.Sleep(500);
        }
        Status(id, 0, "beendet", "");
        Log("Beendet");
        return 0;
    }
}
'@

# Einladung zu Remote Play Together über die offizielle Steamworks-Schnittstelle
# ISteamRemotePlay::BSendRemotePlayTogetherInvite, aus einem eigenen Prozess mit der App-ID des
# laufenden Spiels (bzw. des Spenders). Die Steamworks-Bibliothek kann alt sein: Plan() wählt aus
# den vorhandenen Einsprungpunkten, was geht (flache Schnittstelle v004 … v001, sonst die
# Schnittstelle direkt bei Steam anfordern und über die Methodentabelle aufrufen).
$script:RemotePlaySrc = @'
using System;
using System.Threading;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UzRemotePlay {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)] static extern IntPtr GetProcAddress(IntPtr h, string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool SetDllDirectoryW(string path);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] delegate bool InitFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitFlatFn(IntPtr err);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void VoidFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr PtrFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int HUserFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr FindIfaceFn(int user, [MarshalAs(UnmanagedType.LPStr)] string version);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] delegate bool SendFlatFn(IntPtr self, ulong friend);
    [UnmanagedFunctionPointer(CallingConvention.ThisCall)] [return: MarshalAs(UnmanagedType.I1)] delegate bool SendVirtFn(IntPtr self, ulong friend);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint CountFlatFn(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint SessionIdFlatFn(IntPtr self, int index);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong SessionSteamFlatFn(IntPtr self, uint session);

    public const string FlatSend = "SteamAPI_ISteamRemotePlay_BSendRemotePlayTogetherInvite";
    // Wer schon in der Sitzung ist (nur über die flache Schnittstelle: GetSessionSteamID gibt
    // eine CSteamID zurück, über die Methodentabelle wäre das je nach Compiler anders verpackt).
    public const string FlatCount = "SteamAPI_ISteamRemotePlay_GetSessionCount";
    public const string FlatSessionId = "SteamAPI_ISteamRemotePlay_GetSessionID";
    public const string FlatSessionSteam = "SteamAPI_ISteamRemotePlay_GetSessionSteamID";
    public const string Find = "SteamInternal_FindOrCreateUserInterface";
    public const string HUser = "SteamAPI_GetHSteamUser";
    public const string VersionPrefix = "STEAMREMOTEPLAY_INTERFACE_VERSION";
    // Interface-Versionen, neueste zuerst, und der Platz von BSendRemotePlayTogetherInvite in der
    // Methodentabelle (aus den Steamworks-Headern: 001 ab SDK 1.47, 002 ab 1.58, 003 ab 1.62, 004 ab 1.64).
    public static readonly string[] Versions = { "004", "003", "002", "001" };
    public static readonly int[] Slots = { 12, 7, 7, 6 };

    public static string[] Known() {
        var k = new List<string>();
        k.Add(FlatSend); k.Add(Find); k.Add(HUser); k.Add(FlatCount); k.Add(FlatSessionId); k.Add(FlatSessionSteam);
        foreach (var v in Versions) k.Add("SteamAPI_SteamRemotePlay_v" + v);
        return k.ToArray();
    }

    // Reihenfolge der Versuche aus den Einsprungpunkten, die die Bibliothek hat:
    // „flat:<Zugriff>“ (passt sicher zur Bibliothek) vor „vtable:<Version>:<Platz>“.
    public static string[] Plan(string[] exports) {
        var has = new List<string>(exports ?? new string[0]);
        var plan = new List<string>();
        if (has.Contains(FlatSend)) {
            foreach (var v in Versions) {
                if (has.Contains("SteamAPI_SteamRemotePlay_v" + v)) plan.Add("flat:SteamAPI_SteamRemotePlay_v" + v);
            }
        }
        if (has.Contains(Find) && has.Contains(HUser)) {
            for (int i = 0; i < Versions.Length; i++) plan.Add("vtable:" + VersionPrefix + Versions[i] + ":" + Slots[i]);
        }
        return plan.ToArray();
    }

    static IntPtr lib;

    static T Fn<T>(string name) where T : class {
        IntPtr p = GetProcAddress(lib, name);
        if (p == IntPtr.Zero) return null;
        return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }

    static string Json(bool ok, string method, string reason) {
        return "{\"ok\":" + (ok ? "true" : "false") + ",\"method\":\"" + method + "\",\"reason\":\"" + reason.Replace("\\", "/").Replace("\"", "'") + "\"}";
    }

    static void Pump(VoidFn run, int times) {
        for (int i = 0; i < times; i++) { if (run != null) run(); Thread.Sleep(100); }
    }

    // Mehrere Freunde (Liste mit Komma, z. B. alle aus dem Discord-Call): Steam-IDs prüfen,
    // doppelte nur einmal. Rein, für die Tests.
    public static ulong[] ParseFriends(string csv) {
        var outList = new List<ulong>();
        foreach (var part in (csv ?? "").Split(',', ';', ' ')) {
            ulong id;
            if (part.Length >= 16 && ulong.TryParse(part.Trim(), out id) && id > 0 && !outList.Contains(id)) outList.Add(id);
        }
        return outList.ToArray();
    }

    // Wen noch einladen: alle, die nicht schon in der Remote-Play-Sitzung sind. Rein.
    public static ulong[] Pending(ulong[] friends, ulong[] joined) {
        var j = new List<ulong>(joined ?? new ulong[0]);
        var outList = new List<ulong>();
        foreach (var f in friends ?? new ulong[0]) { if (!j.Contains(f)) outList.Add(f); }
        return outList.ToArray();
    }

    // Antwort für mehrere: { ok, method, reason, joined: [..], results: [{ friend, ok, skipped, reason }] }. Rein.
    public static string ManyJson(bool ok, string method, string reason, ulong[] joined, ulong[] friends, bool[] sent, string[] skipped) {
        var sb = new System.Text.StringBuilder();
        sb.Append("{\"ok\":").Append(ok ? "true" : "false");
        sb.Append(",\"method\":\"").Append(method).Append("\",\"reason\":\"").Append(reason.Replace("\\", "/").Replace("\"", "'")).Append("\"");
        sb.Append(",\"joined\":[");
        for (int i = 0; joined != null && i < joined.Length; i++) { if (i > 0) sb.Append(","); sb.Append("\"").Append(joined[i]).Append("\""); }
        sb.Append("],\"results\":[");
        for (int i = 0; friends != null && i < friends.Length; i++) {
            if (i > 0) sb.Append(",");
            bool s = sent != null && i < sent.Length && sent[i];
            string sk = skipped != null && i < skipped.Length && skipped[i] != null ? skipped[i] : "";
            sb.Append("{\"friend\":\"").Append(friends[i]).Append("\",\"ok\":").Append(s ? "true" : "false");
            sb.Append(",\"skipped\":\"").Append(sk).Append("\",\"reason\":\"").Append(s || sk != "" ? "" : "Steam hat die Einladung nicht angenommen").Append("\"}");
        }
        sb.Append("]}");
        return sb.ToString();
    }

    public static string Invite(string dll, ulong friend) {
        try { return InviteInner(dll, new ulong[] { friend }, false); }
        catch (Exception e) { return Json(false, "", "Fehler: " + e.Message); }
    }

    // Alle auf einmal in einem Prozess (Steam nur einmal anmelden), nacheinander mit kurzer Pause;
    // wer schon in der Sitzung ist, wird übersprungen.
    public static string InviteMany(string dll, string csv) {
        var friends = ParseFriends(csv);
        if (friends.Length == 0) return ManyJson(false, "", "Keine Steam-IDs", new ulong[0], friends, null, null);
        try { return InviteInner(dll, friends, true); }
        catch (Exception e) { return ManyJson(false, "", "Fehler: " + e.Message, new ulong[0], friends, null, null); }
    }

    static ulong[] Joined(IntPtr rp) {
        var outList = new List<ulong>();
        var count = Fn<CountFlatFn>(FlatCount);
        var sid = Fn<SessionIdFlatFn>(FlatSessionId);
        var steam = Fn<SessionSteamFlatFn>(FlatSessionSteam);
        if (rp == IntPtr.Zero || count == null || sid == null || steam == null) return outList.ToArray();
        uint n = count(rp);
        for (int i = 0; i < n && i < 32; i++) {
            ulong who = steam(rp, sid(rp, i));
            if (who != 0 && !outList.Contains(who)) outList.Add(who);
        }
        return outList.ToArray();
    }

    static string Fail(bool many, ulong[] friends, string method, string reason) {
        return many ? ManyJson(false, method, reason, new ulong[0], friends, null, null) : Json(false, method, reason);
    }

    static string InviteInner(string dll, ulong[] friends, bool many) {
        if (string.IsNullOrEmpty(dll) || !System.IO.File.Exists(dll)) return Fail(many, friends, "", "Keine Steamworks-Bibliothek gefunden");
        SetDllDirectoryW(System.IO.Path.GetDirectoryName(dll));
        lib = LoadLibraryW(dll);
        if (lib == IntPtr.Zero) return Fail(many, friends, "", "Steamworks-Bibliothek ließ sich nicht laden");
        var exports = new List<string>();
        foreach (var k in Known()) { if (GetProcAddress(lib, k) != IntPtr.Zero) exports.Add(k); }
        var plan = Plan(exports.ToArray());
        if (plan.Length == 0) return Fail(many, friends, "none", "Diese Steamworks-Version kennt Remote Play Together nicht");
        bool started = false;
        var initFlat = Fn<InitFlatFn>("SteamAPI_InitFlat");
        if (initFlat != null) {
            IntPtr err = Marshal.AllocHGlobal(1024);
            started = initFlat(err) == 0;
            Marshal.FreeHGlobal(err);
        } else {
            var init = Fn<InitFn>("SteamAPI_Init");
            if (init != null) started = init();
        }
        if (!started) return Fail(many, friends, "", "Steam ist nicht erreichbar (läuft Steam?)");
        var run = Fn<VoidFn>("SteamAPI_RunCallbacks");
        var shutdown = Fn<VoidFn>("SteamAPI_Shutdown");
        try {
            Pump(run, 8);
            foreach (var step in plan) {
                IntPtr rp = IntPtr.Zero;
                bool ok;
                if (step.StartsWith("flat:")) {
                    var acc = Fn<PtrFn>(step.Substring(5));
                    var send = Fn<SendFlatFn>(FlatSend);
                    if (acc == null || send == null) continue;
                    rp = acc();
                    if (rp == IntPtr.Zero) continue;
                    if (many) {
                        var joined = Joined(rp);
                        var sent = new bool[friends.Length];
                        var skipped = new string[friends.Length];
                        bool any = false;
                        for (int i = 0; i < friends.Length; i++) {
                            if (Array.IndexOf(joined, friends[i]) >= 0) { skipped[i] = "joined"; continue; }
                            if (any) Pump(run, 6);
                            sent[i] = send(rp, friends[i]);
                            any = true;
                        }
                        Pump(run, 10);
                        return ManyJson(Array.IndexOf(sent, true) >= 0 || Pending(friends, joined).Length == 0, step, "", joined, friends, sent, skipped);
                    }
                    ok = send(rp, friends[0]);
                } else {
                    var parts = step.Split(':');
                    var hu = Fn<HUserFn>(HUser);
                    var find = Fn<FindIfaceFn>(Find);
                    if (parts.Length != 3 || hu == null || find == null) continue;
                    rp = find(hu(), parts[1]);
                    if (rp == IntPtr.Zero) continue;
                    IntPtr vt = Marshal.ReadIntPtr(rp);
                    IntPtr fp = Marshal.ReadIntPtr(vt, int.Parse(parts[2]) * IntPtr.Size);
                    var send = (SendVirtFn)Marshal.GetDelegateForFunctionPointer(fp, typeof(SendVirtFn));
                    if (many) {
                        var sent = new bool[friends.Length];
                        for (int i = 0; i < friends.Length; i++) {
                            if (i > 0) Pump(run, 6);
                            sent[i] = send(rp, friends[i]);
                        }
                        Pump(run, 10);
                        return ManyJson(Array.IndexOf(sent, true) >= 0, step, "", new ulong[0], friends, sent, null);
                    }
                    ok = send(rp, friends[0]);
                }
                // Steam die Einladung verschicken lassen, bevor sich der Helfer abmeldet.
                Pump(run, 10);
                return Json(ok, step, ok ? "" : "Steam hat die Einladung nicht angenommen");
            }
            return Fail(many, friends, "none", "Steam bietet Remote Play Together gerade nicht an");
        } finally {
            if (shutdown != null) shutdown();
        }
    }
}
'@

## Remote Play Together: Einladung über die Steamworks-Bibliothek (Einmal-Modus, eigener Prozess).
function RemotePlay-Invite($a) {
    Add-Type -TypeDefinition $script:RemotePlaySrc
    [Environment]::SetEnvironmentVariable('SteamAppId', [string]$a.appid, 'Process')
    [Environment]::SetEnvironmentVariable('SteamGameId', [string]$a.appid, 'Process')
    if ([string]$a.friends -ne '') {
        # Mehrere auf einmal (Discord-Call): ein Prozess, nacheinander, wer schon dabei ist, nicht.
        $json = [UzRemotePlay]::InviteMany([string]$a.dll, [string]$a.friends)
    } else {
        $json = [UzRemotePlay]::Invite([string]$a.dll, [UInt64]::Parse([string]$a.friend))
    }
    return ($json | ConvertFrom-Json)
}

## Steht das Muster in den letzten $max Bytes der Datei? Gelesen wird in Stücken, jedes mit dem Ende des vorigen
## davor (ein Treffer über die Grenze geht so nicht verloren, solange er kürzer als $ueber ist). Alles auf einmal
## zu lesen hieß bei einer großen Programmdatei kurz rund 200 MB Arbeitsspeicher (64 MB Bytes, dazu der Text).
function Test-DateiMuster([string]$pfad, [string]$muster, [long]$max, [int]$stueck = 1MB, [int]$ueber = 256) {
    $fs = [IO.File]::OpenRead($pfad)
    try {
        [void]$fs.Seek([Math]::Max([long]0, $fs.Length - $max), 'Begin')
        $buf = New-Object byte[] ($stueck + $ueber)
        $halt = 0
        while ($true) {
            $n = $fs.Read($buf, $halt, $stueck)
            if ($n -le 0) { return $false }
            $voll = $halt + $n
            if ([Text.Encoding]::ASCII.GetString($buf, 0, $voll) -match $muster) { return $true }
            $halt = [Math]::Min($ueber, $voll)
            [Array]::Copy($buf, $voll - $halt, $buf, 0, $halt)
        }
    } finally { $fs.Close() }
}

## Remote Play Together: Verlangt das Programm Adminrechte (Manifest oder Kompatibilität), und hat
## Steam welche? Ohne passende Rechte kann der Starter (von Steam gestartet) es nicht starten.
function RemotePlay-Check($a) {
    $exe = [string]$a.exe
    $manifest = $false
    try { $manifest = Test-DateiMuster $exe 'level\s*=\s*[''"](requireAdministrator|highestAvailable)[''"]' 64MB } catch {}
    $compat = $false
    foreach ($root in 'HKCU:', 'HKLM:') {
        try {
            $v = (Get-ItemProperty ($root + '\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers') -ErrorAction Stop).$exe
            if ($v -and ([string]$v) -match 'RUNASADMIN') { $compat = $true }
        } catch {}
    }
    $steamElev = $false
    $p = Get-Process steam -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) {
        # Kommt Uzai nicht an Steams Rechte heran, läuft Steam höher als Uzai – also als Administrator.
        try { $steamElev = [UzElev]::IsElevated($p.Id) } catch {}
    }
    return @{ manifest_admin = $manifest; compat_admin = $compat; steam_elevated = $steamElev; self_elevated = [UzElev]::IsElevated($PID) }
}

## Remote Play Together: den Starter als Programmdatei bauen (Windows PowerShell 5, .NET Framework 4).
function RemotePlay-Build($a) {
    $out = [string]$a.out
    $dir = Split-Path -Parent $out
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmp = $out + '.neu.exe'
    # -LiteralPath: Ein Datenordner mit eckigen Klammern im Namen gälte sonst als Suchmuster („nicht gebaut“).
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    Add-Type -TypeDefinition $script:StarterSrc -OutputAssembly $tmp -OutputType WindowsApplication -IgnoreWarnings
    if (-not (Test-Path -LiteralPath $tmp)) { return @{ ok = $false; reason = 'Der Starter wurde nicht gebaut' } }
    Move-Item -Force -LiteralPath $tmp -Destination $out
    return @{ ok = $true; path = $out }
}

## Spiel beenden („kill“). Nur mit den Rechten des Benutzers: Ein Spiel mit Adminrechten lässt
## Windows so nicht beenden – das meldet „denied“, Uzai fragt nie nach mehr Rechten. Nie Windows
## selbst, Steam, Discord, Uzai oder diesen Helfer, auch wenn eine falsche Nummer ankäme.
$script:KillNever = @('system', 'idle', 'registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass',
    'lsaiso', 'svchost', 'dwm', 'explorer', 'fontdrvhost', 'sihost', 'taskhostw', 'ctfmon', 'conhost', 'audiodg',
    'spoolsv', 'runtimebroker', 'searchhost', 'startmenuexperiencehost', 'shellexperiencehost', 'textinputhost',
    'applicationframehost', 'securityhealthservice', 'msmpeng', 'steam', 'steamwebhelper', 'steamservice',
    'gameoverlayui', 'epicgameslauncher', 'eadesktop', 'eabackgroundservice', 'discord', 'uzai', 'powershell', 'pwsh')

# Prozessbaum des Spiels (src/core/launcher.gd, „Beenden“): der Prozess, den Uzai gestartet hat, und
# alles, was er selbst gestartet hat (Starter → Spiel, cmd → Emulator). Nur lesen (Toolhelp-Liste,
# Startzeit); Beenden geht danach einzeln über Stop-GameProcess (nie Windows, Steam, Discord, Uzai).
# Ein Kind zählt nur, wenn es nicht vor seinem Elternteil gestartet ist – sonst gehört die Nummer
# längst einem anderen Prozess. Geschützte Programme (KillNever) und alles darunter bleiben draußen.
$script:BaumSrc = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UzBaum {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PE32 {
        public uint dwSize; public uint cntUsage; public uint th32ProcessID; public IntPtr th32DefaultHeapID; public uint th32ModuleID;
        public uint cntThreads; public uint th32ParentProcessID; public int pcPriClassBase; public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snap, ref PE32 e);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32NextW(IntPtr snap, ref PE32 e);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr h, out long created, out long exited, out long kernel, out long user);

    public const int MAX = 64;

    /// Reine Regel (prüfbar: tests/logic_beenden.gd): wurzel zuerst, dann die Nachkommen (Breite zuerst).
    /// start 0 = unbekannt (zählt). nie[i]: geschützt – weder dabei noch weiter darunter gesucht.
    /// Die Wurzel steht nur drin, wenn es sie noch gibt (lebt[i] für ihre Nummer).
    public static int[] Nachkommen(int wurzel, int[] pids, int[] eltern, long[] start, bool[] nie, int max) {
        List<int> aus = new List<int>();
        Dictionary<int, long> startVon = new Dictionary<int, long>();
        bool wurzelDa = false, wurzelNie = false;
        for (int i = 0; i < pids.Length; i++) {
            startVon[pids[i]] = start[i];
            if (pids[i] == wurzel) { wurzelDa = true; wurzelNie = nie[i]; }
        }
        if (wurzelNie) return new int[0];
        List<int> suchen = new List<int>();
        suchen.Add(wurzel);
        if (wurzelDa) aus.Add(wurzel);
        int k = 0;
        while (k < suchen.Count && aus.Count < max) {
            int p = suchen[k++];
            long ps;
            if (!startVon.TryGetValue(p, out ps)) ps = 0;
            for (int i = 0; i < pids.Length && aus.Count < max; i++) {
                if (eltern[i] != p || pids[i] == p || pids[i] <= 4 || suchen.Contains(pids[i])) continue;
                if (ps > 0 && start[i] > 0 && start[i] < ps) continue;
                if (nie[i]) continue;
                suchen.Add(pids[i]);
                aus.Add(pids[i]);
            }
        }
        return aus.ToArray();
    }

    /// Lebende Prozesse des Baums unter wurzel (ohne ich, ohne geschützte Namen).
    public static int[] Baum(int wurzel, int ich, string[] geschuetzt) {
        List<int> pids = new List<int>();
        List<int> eltern = new List<int>();
        List<long> start = new List<long>();
        List<bool> nie = new List<bool>();
        Dictionary<string, bool> schutz = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        foreach (string g in geschuetzt) schutz[g] = true;
        IntPtr snap = CreateToolhelp32Snapshot(0x2u, 0);           // TH32CS_SNAPPROCESS
        if (snap == IntPtr.Zero || snap == new IntPtr(-1)) return new int[0];
        try {
            PE32 e = new PE32();
            e.dwSize = (uint)Marshal.SizeOf(typeof(PE32));
            bool ok = Process32FirstW(snap, ref e);
            int guard = 0;
            while (ok && guard++ < 20000) {
                int id = (int)e.th32ProcessID;
                string name = e.szExeFile ?? "";
                if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name.Substring(0, name.Length - 4);
                pids.Add(id);
                eltern.Add((int)e.th32ParentProcessID);
                start.Add(Startzeit(id));
                nie.Add(id <= 4 || id == ich || schutz.ContainsKey(name));
                ok = Process32NextW(snap, ref e);
            }
        } finally { CloseHandle(snap); }
        return Nachkommen(wurzel, pids.ToArray(), eltern.ToArray(), start.ToArray(), nie.ToArray(), MAX);
    }

    static long Startzeit(int pid) {
        if (pid <= 4) return 0;
        IntPtr h = OpenProcess(0x1000u, false, pid);                 // PROCESS_QUERY_LIMITED_INFORMATION
        if (h == IntPtr.Zero) return 0;
        try {
            long c, x, k, u;
            return GetProcessTimes(h, out c, out x, out k, out u) ? c : 0;
        } finally { CloseHandle(h); }
    }
}
'@

function Use-Baum {
    if ($script:BaumReady) { return }
    Add-Type -TypeDefinition $script:BaumSrc
    $script:BaumReady = $true
}

# Lebende Prozesse des Spielbaums (Nummern), ohne den Helfer selbst und ohne Geschütztes.
function Get-SpielBaum([int]$root) {
    Use-Baum
    return @([UzBaum]::Baum($root, $PID, [string[]]$script:KillNever))
}

function Stop-GameProcess([int]$id) {
    if ($id -le 4 -or $id -eq $PID) { return @{ ok = $false; reason = 'geschützt' } }
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if (-not $p) { return @{ ok = $true; gone = $true } }
    if ($script:KillNever -contains $p.ProcessName.ToLowerInvariant()) { return @{ ok = $false; reason = 'geschützt' } }
    try { $p.Kill() } catch {
        if (-not (Get-Process -Id $id -ErrorAction SilentlyContinue)) { return @{ ok = $true; gone = $true } }
        return @{ ok = $false; denied = $true }
    }
    return @{ ok = $true }
}

## Hat Windows einen Absturz des Spiels aufgezeichnet? Ereignis 1000 („Application Error“) im
## Anwendungsprotokoll seit dem Spielstart, passend zum Prozess, zur Programmdatei oder zum
## Spielordner. Das Protokoll darf jeder Benutzer lesen; Uzai schreibt nichts hinein.
function Find-CrashEvent($a) {
    $none = @{ found = $false }
    $since = [DateTimeOffset]::FromUnixTimeSeconds([long]$a.since).LocalDateTime
    $dir = ([string]$a.dir) -replace '(?<!^)[\\/]+', '\'
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since } -MaxEvents 20 -ErrorAction Stop)
    } catch { return $none }
    foreach ($e in $ev) {
        $p = @($e.Properties | ForEach-Object { [string]$_.Value })
        if (Test-CrashMatch $p ([int]$a.pid) ([string]$a.exe) $dir) {
            return @{ found = $true; app = $p[0]; module = $p[3]; code = $p[6] }
        }
    }
    return $none
}

# Felder des Ereignisses: 0 Programm, 3 Modul, 6 Ausnahme-Code, 8 Prozess (hex), 10 Programmpfad.
function Test-CrashMatch($p, [int]$id, [string]$exe, [string]$dir) {
    if ($p.Count -lt 11) { return $false }
    if ($id -gt 0) {
        try { if ([Convert]::ToInt64(($p[8] -replace '^0x', ''), 16) -eq $id) { return $true } } catch {}
    }
    $path = [string]$p[10]
    if ($exe -ne '' -and $path -ieq $exe) { return $true }
    if ($dir -ne '' -and $path.StartsWith($dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

# --- Zimmer-Netz: abgeschotteter Prozess (Punkt 131, docs/ZIMMER_SICHERHEIT.md Abschnitt 6) -------
# Die Sandbox für alles, was später rohe Netzdaten anfasst (docs/PLAN_ZIMMER_ONLINE.md Phase 2): ein
# eigenes kleines Programm in einem Windows-AppContainer mit NUR der Fähigkeit „internetClient“
# (kein Lauschen, kein Heimnetz, kein localhost), ohne Dateizugriff außer seinem eigenen leeren
# Container-Ordner, in einem Job-Objekt (ein Prozess, Speichergrenze, keine Kindprozesse, keine
# Zwischenablage, kein Desktop). Zu Uzai führt nur eine schmale Leitung mit festen Rahmen
# (Längenpräfix). Darin prüft Prüfmauer 1 (UzNetzSchema) jede Nachricht der Gegenstelle nach
# denselben Regeln wie Uzai (src/room/netz_protokoll.gd, Prüfmauer 2), mit eigener Drossel je Gast.
# Noch kein Netzwerk-Code: Statt einer echten Gegenstelle kommen deren Bytes zum Testen über die
# Leitung („--test“, Rahmen TEST_REIN/TEST_RAUS). Keine Adminrechte nötig.
# Dieselbe Quelle wird zweimal übersetzt: im Helfer (UzZimmerNetz startet und prüft) und als
# Programmdatei (UzaiZimmerNetz.Main ist der Kindprozess). Übersetzbar als C# 5 (tests/zimmer_sandbox_cs.ps1).
$script:ZimmerNetzSrc = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

// Feste Rahmen auf der Leitung: 4 Byte Länge (little endian; Art + Nutzlast), 1 Byte Art, Nutzlast
// bis 8 KiB. Alles andere ist ein Fehler und beendet die Leitung. Dieselben Nummern in
// src/room/zimmer_netz.gd (der Test vergleicht).
public static class UzNetzRahmen {
    public const int MAX = 8192;
    public const byte PING = 1, PONG = 2, SELBSTTEST = 3, ERGEBNIS = 4, ENDE = 5, SENDEN = 6, EMPFANGEN = 7, TEST_REIN = 8, TEST_RAUS = 9, RAUS = 10, ZAEHLER = 11, SCHLIESSEN = 12;
    // Treffpunkt (Phase 3): Start, Einladung, Zurückziehen, Besuch, „klopft“, Entscheidung, Stand, Zähler.
    public const byte TREFF = 13, EINLADUNG = 14, ZURUECK = 15, BESUCH = 16, KLOPFT = 17, ENTSCHEID = 18, STAND = 19, TREFF_ZAEHLER = 20;
    // Nur Sandbox → Uzai: so viele Bytes hat die Sandbox von der Leitung gelesen (u32, insgesamt; UzQuittEin).
    public const byte QUITTUNG = 21;

    public static bool ArtBekannt(byte a) { return a >= PING && a <= QUITTUNG; }

    // Nutzlast eines ganzen Rahmens, null bei Ende der Leitung, Länge 0, zu groß oder unbekannter Art.
    public static byte[] Lesen(Stream s, out byte art) {
        art = 0;
        byte[] kopf = Genau(s, 4);
        if (kopf == null) return null;
        long n = (long)kopf[0] | ((long)kopf[1] << 8) | ((long)kopf[2] << 16) | ((long)kopf[3] << 24);
        if (n < 1 || n > MAX + 1) return null;
        byte[] rest = Genau(s, (int)n);
        if (rest == null || !ArtBekannt(rest[0])) return null;
        art = rest[0];
        byte[] nutz = new byte[n - 1];
        Buffer.BlockCopy(rest, 1, nutz, 0, nutz.Length);
        return nutz;
    }

    static byte[] Genau(Stream s, int n) {
        byte[] b = new byte[n];
        int got = 0;
        while (got < n) {
            int r = s.Read(b, got, n - got);
            if (r <= 0) return null;
            got += r;
        }
        return b;
    }

    public static bool Schreiben(Stream s, byte art, byte[] nutz) {
        if (!ArtBekannt(art) || nutz == null || nutz.Length > MAX) return false;
        int n = nutz.Length + 1;
        byte[] b = new byte[4 + n];
        b[0] = (byte)n; b[1] = (byte)(n >> 8); b[2] = (byte)(n >> 16); b[3] = (byte)(n >> 24);
        b[4] = art;
        Buffer.BlockCopy(nutz, 0, b, 5, nutz.Length);
        lock (s) {      // der Treffpunkt schreibt aus seinem eigenen Faden
            s.Write(b, 0, b.Length);
            s.Flush();
        }
        return true;
    }
}

// Die Leitung von Uzai, mitgezählt und quittiert. Uzai öffnet seine Pipe ohne Warten (Windows: PIPE_NOWAIT,
// 4 KiB Puffer); passte ein Schreibvorgang nicht ganz hinein, ginge er still verloren oder nur halb hinein.
// Darum legt Uzai nie mehr als sein Fenster (FENSTER in zimmer_netz.gd, 3 KiB) unquittiert in die Pipe, und die
// Sandbox quittiert vor jedem Lesen, sobald AB Bytes offen sind. Offen bleiben beim Warten so höchstens AB - 1
// Bytes – Uzai kann also immer weiterschreiben (kein Stillstand), und jeder Schreibvorgang passt ganz hinein.
public sealed class UzQuittEin : Stream {
    public const int AB = 512;
    readonly Stream ein, aus;
    uint gelesen, quittiert;

    public UzQuittEin(Stream ein, Stream aus) { this.ein = ein; this.aus = aus; }

    public override int Read(byte[] b, int o, int n) {
        uint offen = unchecked(gelesen - quittiert);
        if (offen >= AB) {
            UzNetzRahmen.Schreiben(aus, UzNetzRahmen.QUITTUNG, new byte[] { (byte)gelesen, (byte)(gelesen >> 8), (byte)(gelesen >> 16), (byte)(gelesen >> 24) });
            quittiert = gelesen;
        }
        int r = ein.Read(b, o, n);
        if (r > 0) gelesen = unchecked(gelesen + (uint)r);
        return r;
    }

    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long o, SeekOrigin w) { throw new NotSupportedException(); }
    public override void SetLength(long n) { throw new NotSupportedException(); }
    public override void Write(byte[] b, int o, int n) { throw new NotSupportedException(); }
}

// Prüfmauer 1: das Zimmer-Protokoll Fassung 2, Regel für Regel wie struktur_ok in
// src/room/netz_protokoll.gd (Länge, Fassung, Art, jedes Feld im Bereich; unbekannt = abgelehnt).
// Die Zahlen der Listen (Emotes, Sätze, Figur, Katalog …) vergleicht tests/logic_zimmer_netz.gd mit
// Uzai; beide Tests prüfen dieselben Tausenden Pakete und müssen dasselbe Urteil fällen.
public static class UzNetzSchema {
    public const byte MAGIC = 0x55, VERSION = 2;
    public const int HALLO = 1, POS = 2, EMOTE = 3, SATZ = 4, FIGUR = 5, ZIMMER = 6, TSCHUESS = 7, ARTEN = 8;
    public const int GERAETE = 2, EMOTES = 7, SAETZE = 12, KATALOG = 76, WANDMATERIAL = 8, BODENARTEN = 9, ZEITEN = 5, WETTER = 5;
    public const int X_MAX = 1050, Y_MAX = 300, YAW_MAX = 3142, PITCH_MAX = 1571, K_MIN = 1800, K_MAX = 6500, H_MAX = 200;
    public const int MIN_FELDER = 8, MAX_FELDER = 20, MAX_MOEBEL = 300, MAX_VARIANTEN = 16, MAX_STUFEN = 8, KEINE = 0xFF;
    public const int ZIMMER_KOPF = 32, MOEBEL_BYTES = 12, MAX_NACHRICHT = ZIMMER_KOPF + MAX_MOEBEL * MOEBEL_BYTES;
    public static readonly int[] LAENGE = { 0, 8, 13, 4, 4, 8, -1, 3 };
    public static readonly byte[] FIGUR_ANZAHL = { 22, 5, 11, 6, 3 };
    // Drossel je Gast und Art: Nachrichten je Sekunde und Vorrat (wie RATEN in netz_protokoll.gd).
    public static readonly double[] RATE = { 0, 0.1, 30, 2, 0.5, 0.2, 0.5, 1 };
    public static readonly double[] VORRAT = { 0, 2, 40, 4, 4, 3, 2, 1 };
    public const double BYTES_JE_SEKUNDE = 16384, BYTES_VORRAT = 32768, VERSTOESSE_RAUS = 25;

    static int U16(byte[] b, int o) { return b[o] | (b[o + 1] << 8); }
    static int S16(byte[] b, int o) { return (short)(b[o] | (b[o + 1] << 8)); }

    // vonGastgeber: kommt die Nachricht vom Gastgeber (nur der darf ein Zimmer schicken)?
    public static bool Pruefen(byte[] b, bool vonGastgeber) {
        if (b == null || b.Length < 3 || b.Length > MAX_NACHRICHT || b[0] != MAGIC || b[1] != VERSION) return false;
        int art = b[2];
        if (art < 1 || art >= ARTEN) return false;
        if (art == ZIMMER) return vonGastgeber && Zimmer(b);
        if (b.Length != LAENGE[art]) return false;
        switch (art) {
            case HALLO: return b[3] < GERAETE;
            case POS: return U16(b, 3) <= X_MAX && U16(b, 5) <= Y_MAX && U16(b, 7) <= X_MAX && Math.Abs(S16(b, 9)) <= YAW_MAX && Math.Abs(S16(b, 11)) <= PITCH_MAX;
            case EMOTE: return b[3] < EMOTES;
            case SATZ: return b[3] < SAETZE;
            case FIGUR:
                for (int i = 0; i < FIGUR_ANZAHL.Length; i++) if (b[3 + i] >= FIGUR_ANZAHL[i]) return false;
                return true;
        }
        return true;
    }

    static bool Zimmer(byte[] b) {
        int n = b.Length;
        if (n < ZIMMER_KOPF) return false;
        int w = b[3], t = b[4];
        if (w < MIN_FELDER || w > MAX_FELDER || t < MIN_FELDER || t > MAX_FELDER) return false;
        if (b[5] >= BODENARTEN) return false;
        for (int k = 0; k < 4; k++) if (b[9 + 4 * k] >= WANDMATERIAL) return false;
        if (b[25] >= ZEITEN || b[26] >= WETTER) return false;
        int kel = U16(b, 27);
        if (kel < K_MIN || kel > K_MAX || b[29] > H_MAX) return false;
        int anzahl = U16(b, 30);
        if (anzahl > MAX_MOEBEL || n != ZIMMER_KOPF + anzahl * MOEBEL_BYTES) return false;
        for (int i = 0; i < anzahl; i++) {
            int o = ZIMMER_KOPF + i * MOEBEL_BYTES;
            if (b[o] >= KATALOG || b[o + 1] >= w || b[o + 2] >= t || b[o + 3] > 3) return false;
            if (b[o + 4] != KEINE && b[o + 4] >= MAX_VARIANTEN) return false;
            if (b[o + 5] != KEINE && b[o + 5] >= MAX_STUFEN) return false;
            int fl = b[o + 6];
            if ((fl & ~3) != 0) return false;
            if ((fl & 2) == 0 && (b[o + 7] != 0 || b[o + 8] != 0 || b[o + 9] != 0)) return false;
            if (b[o + 10] != 0 || b[o + 11] != 0) return false;
        }
        return true;
    }

    // Token-Eimer je Gast, wie Drossel in netz_protokoll.gd. jetzt in Sekunden.
    public class Drossel {
        readonly double[] eimer = new double[ARTEN];
        double bytes = BYTES_VORRAT, verstoesse = 0, zuletzt = -1;

        public Drossel() { for (int i = 1; i < ARTEN; i++) eimer[i] = VORRAT[i]; }

        void Nachfuellen(double jetzt) {
            if (zuletzt < 0) zuletzt = jetzt;
            double dt = Math.Min(60.0, Math.Max(0.0, jetzt - zuletzt));
            zuletzt = Math.Max(zuletzt, jetzt);
            for (int i = 1; i < ARTEN; i++) eimer[i] = Math.Min(VORRAT[i], eimer[i] + dt * RATE[i]);
            bytes = Math.Min(BYTES_VORRAT, bytes + dt * BYTES_JE_SEKUNDE);
            verstoesse = Math.Max(0.0, verstoesse - dt);
        }

        public bool Erlaubt(int art, int groesse, double jetzt) {
            Nachfuellen(jetzt);
            if (art < 1 || art >= ARTEN || eimer[art] < 1.0 || bytes < groesse) { Verstoss(); return false; }
            eimer[art] -= 1.0;
            bytes -= groesse;
            return true;
        }

        public void Verstoss() { verstoesse += 1.0; }
        public bool Rauswerfen() { return verstoesse >= VERSTOESSE_RAUS; }
    }
}

// Der Kindprozess. „--echo“: Ping → Pong, Selbsttest → Ergebnis, Ende → Code 0. „--netz <rolle>
// --test“: die Sitzung mit Prüfmauer 1 (siehe Netz). Kaputte, zu große oder unerwartete Rahmen →
// Code 3. Andere Aufrufe → Code 2.
public static class UzaiZimmerNetz {
    public static readonly string[] Proben = { "ordner", "lesen", "liste", "schreiben", "programm", "krypto", "secp", "rtc" };
    public const int SLOTS = 8;

    // „--netz <rolle> --test“: Testbetrieb (Test-Gegenstelle über die Leitung, Test-Relay auf 127.0.0.1).
    // „--netz <rolle>“: echt (nur die festen Relays, nur mit beiden Bibliotheken; Uzai startet das nur mit dem
    // Testschalter, ohne Adminrechte und nach bestandener Probe).
    public static int Main(string[] args) {
        if (args == null) return 2;
        bool echo = args.Length == 1 && args[0] == "--echo";
        bool rolle = args.Length >= 2 && args[0] == "--netz" && (args[1] == "gastgeber" || args[1] == "gast");
        bool test = rolle && args.Length == 3 && args[2] == "--test";
        bool netz = rolle && (args.Length == 2 || test);
        if (!echo && !netz) return 2;
        // Erst die Leitung schützen (fremder Code darf nie auf die Standardausgabe schreiben), dann erst Bibliotheken.
        Stream geschuetzt = UzNetzLib.AusgabeSchuetzen();
        using (Stream ein = Console.OpenStandardInput())
        using (Stream aus = geschuetzt ?? Console.OpenStandardOutput()) {
            return echo ? Schleife(ein, aus) : Netz(ein, aus, args[1] == "gastgeber", test);
        }
    }

    public static int Schleife(Stream ein, Stream aus) {
        while (true) {
            byte art;
            byte[] nutz = UzNetzRahmen.Lesen(ein, out art);
            if (nutz == null) return 3;
            if (art == UzNetzRahmen.PING) UzNetzRahmen.Schreiben(aus, UzNetzRahmen.PONG, nutz);
            else if (art == UzNetzRahmen.SELBSTTEST) UzNetzRahmen.Schreiben(aus, UzNetzRahmen.ERGEBNIS, Encoding.UTF8.GetBytes(Selbsttest(Encoding.UTF8.GetString(nutz))));
            else if (art == UzNetzRahmen.ENDE) { UzRtc.Aufraeumen(); return 0; }   // Fäden des Selbsttests sauber anhalten
            else return 3;
        }
    }

    // Zähler der Sitzung (Antwort auf ZAEHLER: fünf u32, little endian). Rein (seit Fassung 5): so viele
    // TEST_REIN-Rahmen kamen an – „Abschottung prüfen“ trennt damit „Rahmen verloren“ von „Prüfmauer falsch“.
    public class Stand {
        public uint Angenommen, Verworfen, Gedrosselt, AusVerworfen, Rein;

        public byte[] Bytes() {
            var b = new byte[20];
            uint[] w = { Angenommen, Verworfen, Gedrosselt, AusVerworfen, Rein };
            for (int i = 0; i < 5; i++) for (int k = 0; k < 4; k++) b[i * 4 + k] = (byte)(w[i] >> (8 * k));
            return b;
        }
    }

    public static int Netz(Stream ein, Stream aus, bool gastgeber, bool test) {
        var uhr = Stopwatch.StartNew();
        return Netz(ein, aus, gastgeber, test, delegate { return uhr.Elapsed.TotalSeconds; });
    }

    // Die Sitzung. Von Uzai kommen nur: PING, ZAEHLER (leer), SENDEN (Platz + Nachricht an die
    // Gegenstelle), SCHLIESSEN (Platz), ENDE – und mit „--test“ TEST_REIN (Platz + Bytes, als kämen
    // sie aus dem Netz). Zu Uzai gehen nur PONG, ZAEHLER, EMPFANGEN (Platz + geprüfte Nachricht),
    // RAUS (Platz, Grund) und mit „--test“ TEST_RAUS (was ins Netz ginge). Gastgeber: Plätze 0..7
    // (je Gast einer); Gast: nur Platz 0 (der Gastgeber). Alles andere → Code 3. Was sie gelesen hat,
    // quittiert sie (QUITTUNG, UzQuittEin).
    public static int Netz(Stream ein, Stream aus, bool gastgeber, bool test, Func<double> uhr) {
        ein = new UzQuittEin(ein, aus);
        int plaetze = gastgeber ? SLOTS : 1;
        var drossel = new UzNetzSchema.Drossel[plaetze];
        var raus = new bool[plaetze];
        for (int i = 0; i < plaetze; i++) drossel[i] = new UzNetzSchema.Drossel();
        var st = new Stand();
        UzTreffBetrieb treff = null;
        // Prüfmauer 1 läuft für die Leitung (Test-Gegenstelle) und für den Datenkanal (Treffpunkt-Faden) unter
        // derselben Sperre: Drossel, Rauswurf und Zähler sind geteilt.
        var sperre = new object();
        Action<int, byte[]> kanalEin = delegate (int platz, byte[] m) {
            if (platz < 0 || platz >= plaetze || m == null) return;
            lock (sperre) Eingang(platz, m, gastgeber, drossel, raus, st, aus, uhr());
        };
        try {
            while (true) {
                byte art;
                byte[] nutz = UzNetzRahmen.Lesen(ein, out art);
                if (nutz == null) return 3;
                int r;
                lock (sperre) r = Schritt(art, nutz, gastgeber, test, uhr, aus, plaetze, drossel, raus, st, ref treff, kanalEin);
                if (r >= 0) return r;
            }
        } finally { if (treff != null) treff.Stop(); }
    }

    // Ein Rahmen von Uzai; -1 = weiter, sonst der Rückgabewert der Sitzung.
    static int Schritt(byte art, byte[] nutz, bool gastgeber, bool test, Func<double> uhr, Stream aus, int plaetze, UzNetzSchema.Drossel[] drossel, bool[] raus, Stand st,
            ref UzTreffBetrieb treff, Action<int, byte[]> kanalEin) {
        {
            switch (art) {
                case UzNetzRahmen.PING:
                    UzNetzRahmen.Schreiben(aus, UzNetzRahmen.PONG, nutz);
                    break;
                case UzNetzRahmen.ENDE:
                    return 0;
                case UzNetzRahmen.ZAEHLER:
                    if (nutz.Length != 0) return 3;
                    UzNetzRahmen.Schreiben(aus, UzNetzRahmen.ZAEHLER, st.Bytes());
                    break;
                case UzNetzRahmen.SCHLIESSEN:
                    if (nutz.Length != 1 || nutz[0] >= plaetze) return 3;
                    drossel[nutz[0]] = new UzNetzSchema.Drossel();
                    raus[nutz[0]] = false;
                    if (treff != null) treff.Befehl(art, nutz);
                    break;
                case UzNetzRahmen.TREFF: {
                    // Treffpunkt einmal starten: 0 = feste Relays, sonst nur mit „--test“ 127.0.0.1:Port.
                    if (treff != null || !UzTreff.BefehlOk(art, nutz, gastgeber)) return 3;
                    int port = nutz[0] | (nutz[1] << 8);
                    if (port != 0 && !test) return 3;
                    treff = new UzTreffBetrieb(gastgeber, test, aus, kanalEin);
                    treff.Start(port);
                    break;
                }
                case UzNetzRahmen.EINLADUNG:
                case UzNetzRahmen.ZURUECK:
                case UzNetzRahmen.BESUCH:
                case UzNetzRahmen.ENTSCHEID:
                case UzNetzRahmen.TREFF_ZAEHLER:
                    if (treff == null || !UzTreff.BefehlOk(art, nutz, gastgeber)) return 3;
                    treff.Befehl(art, nutz);
                    break;
                case UzNetzRahmen.SENDEN:
                    // Auch Ausgehendes nur nach Schema: Was den PC verlässt, sind nur diese Nachrichten.
                    if (nutz.Length < 1 || nutz[0] >= plaetze) return 3;
                    if (!UzNetzSchema.Pruefen(Teil(nutz), gastgeber)) { st.AusVerworfen++; break; }
                    // Über den Datenkanal, wenn er auf diesem Platz offen ist; sonst im Testbetrieb an die Test-Gegenstelle.
                    if (treff != null && treff.Direkt != null && treff.Direkt.Offen(nutz[0])) { if (!treff.Direkt.Senden(nutz[0], Teil(nutz))) st.AusVerworfen++; }
                    else if (test) UzNetzRahmen.Schreiben(aus, UzNetzRahmen.TEST_RAUS, nutz);
                    break;
                case UzNetzRahmen.TEST_REIN:
                    if (!test || nutz.Length < 1 || nutz[0] >= plaetze) return 3;
                    st.Rein++;
                    Eingang(nutz[0], Teil(nutz), gastgeber, drossel, raus, st, aus, uhr());
                    break;
                default:
                    return 3;
            }
        }
        return -1;
    }

    static byte[] Teil(byte[] nutz) {
        var m = new byte[nutz.Length - 1];
        Buffer.BlockCopy(nutz, 1, m, 0, m.Length);
        return m;
    }

    // Prüfmauer 1 für alles, was von der Gegenstelle kommt: Schema, dann Drossel. Wer zu oft
    // Unsinn schickt oder die Grenzen reißt, wird gemeldet (RAUS) und danach nicht mehr gehört.
    static void Eingang(int platz, byte[] m, bool gastgeber, UzNetzSchema.Drossel[] d, bool[] raus, Stand st, Stream aus, double jetzt) {
        if (raus[platz]) { st.Verworfen++; return; }
        bool ok = UzNetzSchema.Pruefen(m, !gastgeber);
        if (!ok) { st.Verworfen++; d[platz].Verstoss(); }
        else if (!d[platz].Erlaubt(m[2], m.Length, jetzt)) { st.Gedrosselt++; ok = false; }
        if (ok) {
            st.Angenommen++;
            var f = new byte[m.Length + 1];
            f[0] = (byte)platz;
            Buffer.BlockCopy(m, 0, f, 1, m.Length);
            UzNetzRahmen.Schreiben(aus, UzNetzRahmen.EMPFANGEN, f);
        } else if (d[platz].Rauswerfen()) {
            raus[platz] = true;
            UzNetzRahmen.Schreiben(aus, UzNetzRahmen.RAUS, new byte[] { (byte)platz, 1 });
        }
    }

    // Auftrag: Zeilen „schlüssel=absoluter Pfad“ nur für ordner, lesen, liste, schreiben.
    public static Dictionary<string, string> Auftrag(string text) {
        var kv = new Dictionary<string, string>();
        foreach (string zeile in (text ?? "").Split('\n')) {
            int i = zeile.IndexOf('=');
            if (i <= 0) continue;
            string k = zeile.Substring(0, i);
            string v = zeile.Substring(i + 1);
            if (k == "programm" || k == "krypto" || k == "secp" || k == "rtc" || Array.IndexOf(Proben, k) < 0 || kv.ContainsKey(k) || !PfadOk(v)) continue;
            kv[k] = v;
        }
        return kv;
    }

    public static bool PfadOk(string p) {
        if (string.IsNullOrEmpty(p) || p.Length > 260 || p.IndexOf('\0') >= 0 || p.IndexOfAny(Path.GetInvalidPathChars()) >= 0) return false;
        return Path.IsPathRooted(p) && !p.StartsWith("\\\\");
    }

    // Jede Probe: „1“ wenn es ging, „0“ wenn Windows es verweigert hat. Im Container soll nur
    // „ordner“ gehen (eigener Ordner); lesen, liste, schreiben und programm müssen scheitern.
    public static string Selbsttest(string auftrag) {
        var kv = Auftrag(auftrag);
        var sb = new StringBuilder();
        sb.Append("ordner=").Append(Probe(delegate {
            string f = Path.Combine(Wert(kv, "ordner"), "probe.txt");
            File.WriteAllText(f, "uzai");
            if (File.ReadAllText(f) != "uzai") throw new IOException();
            File.Delete(f);
        })).Append('\n');
        sb.Append("lesen=").Append(Probe(delegate { File.ReadAllBytes(Wert(kv, "lesen")); })).Append('\n');
        sb.Append("liste=").Append(Probe(delegate { Directory.GetFileSystemEntries(Wert(kv, "liste")); })).Append('\n');
        sb.Append("schreiben=").Append(Probe(delegate {
            string f = Wert(kv, "schreiben");
            File.WriteAllText(f, "uzai");
            File.Delete(f);
        })).Append('\n');
        // Sich selbst noch einmal starten (ohne Shell): Job-Objekt und Kindprozess-Sperre verbieten es.
        sb.Append("programm=").Append(Probe(delegate {
            var si = new ProcessStartInfo(System.Reflection.Assembly.GetEntryAssembly().Location, "--nichts");
            si.UseShellExecute = false;
            si.CreateNoWindow = true;
            using (Process p = Process.Start(si)) { p.WaitForExit(2000); }
        })).Append('\n');
        // Verschlüsselung für den Treffpunkt auch im Container (AES-GCM aus CNG, ECDH P-256).
        sb.Append("krypto=").Append(UzKrypto.Selbsttest() ? "1" : "0").Append('\n');
        // Die beiden Netz-Bibliotheken: geladen (voller Pfad, Prüfsumme) und Selbsttest (BIP-340-Vektoren bzw. ein
        // Angebot mit DTLS-Fingerabdruck). Zahl = UzNetzLib-Zustand (1 bereit).
        sb.Append("secp=").Append(UzSecp.Bereit() ? UzNetzLib.BEREIT : UzNetzLib.Zustand(UzNetzLib.SECP)).Append('\n');
        sb.Append("rtc=").Append(UzRtc.Bereit() ? UzNetzLib.BEREIT : UzNetzLib.Zustand(UzNetzLib.RTC)).Append('\n');
        return sb.ToString();
    }

    static string Wert(Dictionary<string, string> kv, string k) {
        string v;
        if (!kv.TryGetValue(k, out v)) throw new ArgumentException(k);
        return v;
    }

    static string Probe(Action a) {
        try { a(); return "1"; } catch { return "0"; }
    }
}

// --- Netz-Bibliotheken (nur hier in der Sandbox; docs/ZIMMER_SICHERHEIT.md W7, Abschnitt 5) ------------------
// libsecp256k1 (BIP-340-Schnorr für die Nostr-Hülle) und libdatachannel (WebRTC-Datenkanal), gebaut von
// tools/bau_netzlibs.sh aus fest gepinnten Quellen. Geladen wird nur über den vollen Pfad neben dem Programm der
// Sandbox, erst nach der Prüfsumme (Datei dabei gegen Schreiben gesperrt), Abhängigkeiten nur aus System32 (kein
// Suchpfad, kein Hijacking). Uzai selbst lädt keine der beiden. Unter Linux gibt es das nur für die Tests (Ordner und
// Prüfsummen aus UZAI_NETZLIB_TEST, nie unter Windows).
public static class UzNetzLib {
    public const string SECP = "uzai-secp256k1.dll", RTC = "uzai-datachannel.dll";
    // Dieselben Werte in src/room/zimmer_netz.gd (NETZLIBS) und im Helfer; tests/netzlibs_cs.ps1 vergleicht mit assets/net/.
    public const string SECP_SHA256 = "24a4e9d05fbbf7158888ae1a69ee255b32fa855ce6c09c62a452b2c33ac7f072";
    public const string RTC_SHA256 = "7ee7217ad3848a65611838dda0bba4fdbe355635a8a3da5137992945d3206a8b";
    public const int MAX_DATEI = 16 * 1024 * 1024;
    // Zustand je Bibliothek (für „Abschottung prüfen“): 0 nicht versucht, 1 bereit, 2 fehlt, 3 Prüfsumme falsch,
    // 4 Laden gescheitert, 5 Selbsttest gescheitert.
    public const int NICHT = 0, BEREIT = 1, FEHLT = 2, PRUEFSUMME = 3, LADEN = 4, SELBSTTEST = 5;
    const uint LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x800;
    static readonly object Tor = new object();
    static readonly Dictionary<string, IntPtr> offen = new Dictionary<string, IntPtr>();
    static readonly Dictionary<string, int> zustand = new Dictionary<string, int>();

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryExW(string datei, IntPtr h, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)] static extern IntPtr GetProcAddress(IntPtr h, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetStdHandle(int n, IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool DuplicateHandle(IntPtr sp, IntPtr h, IntPtr tp, out IntPtr th, uint access, bool inherit, uint options);
    [DllImport("msvcrt.dll", EntryPoint = "_close")] static extern int CrtClose(int fd);
    [DllImport("libc.so.6", EntryPoint = "dlopen")] static extern IntPtr DlOpen(string datei, int flags);
    [DllImport("libc.so.6", EntryPoint = "dlsym")] static extern IntPtr DlSym(IntPtr h, string name);
    [DllImport("libc.so.6", EntryPoint = "dup")] static extern int Dup(int fd);
    [DllImport("libc.so.6", EntryPoint = "dup2")] static extern int Dup2(int fd, int neu);
    [DllImport("libc.so.6", EntryPoint = "open")] static extern int Open(string pfad, int flags);

    public static bool Windows { get { return Environment.OSVersion.Platform == PlatformID.Win32NT; } }
    // Erst wenn die Standardausgabe geschützt ist, lädt die Sandbox unter Windows eine Bibliothek.
    public static volatile bool Geschuetzt;

    // Ordner und Sollwerte. Windows: neben dem Programm der Sandbox, feste Prüfsummen. Sonst nur für Tests.
    static bool Ort(string name, out string pfad, out string soll) {
        pfad = null; soll = null;
        if (Windows) {
            string exe = System.Reflection.Assembly.GetEntryAssembly() != null ? System.Reflection.Assembly.GetEntryAssembly().Location : null;
            if (string.IsNullOrEmpty(exe)) return false;
            pfad = Path.Combine(Path.GetDirectoryName(exe), name);
            soll = name == SECP ? SECP_SHA256 : RTC_SHA256;
            return true;
        }
        // Test unter Linux: „<ordner>|<sha secp>|<sha rtc>“; die Dateien heißen libuzai-*.so.
        string t = Environment.GetEnvironmentVariable("UZAI_NETZLIB_TEST");
        if (string.IsNullOrEmpty(t)) return false;
        string[] f = t.Split('|');
        if (f.Length != 3 || !Path.IsPathRooted(f[0])) return false;
        pfad = Path.Combine(f[0], name == SECP ? "libuzai-secp256k1.so" : "libuzai-datachannel.so");
        soll = name == SECP ? f[1] : f[2];
        return soll.Length == 64;
    }

    public static int Zustand(string name) {
        lock (Tor) { int z; return zustand.TryGetValue(name, out z) ? z : NICHT; }
    }

    public static void Setzen(string name, int z) { lock (Tor) zustand[name] = z; }

    // Die Bibliothek laden (einmal je Prozess). IntPtr.Zero, wenn sie fehlt, die Prüfsumme nicht stimmt oder das
    // Laden scheitert; der Grund steht danach in Zustand(name).
    public static IntPtr Laden(string name) {
        lock (Tor) {
            IntPtr h;
            if (offen.TryGetValue(name, out h)) return h;
            int z;
            if (zustand.TryGetValue(name, out z) && z != NICHT) return IntPtr.Zero;
            h = IntPtr.Zero;
            z = FEHLT;
            string pfad, soll;
            try {
                if (Windows && !Geschuetzt) z = LADEN;
                else if (Ort(name, out pfad, out soll) && File.Exists(pfad)) {
                    // Gegen Schreiben gesperrt, solange geprüft und geladen wird (keine Änderung dazwischen).
                    using (var fs = new FileStream(pfad, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                        z = PRUEFSUMME;
                        if (fs.Length > 0 && fs.Length <= MAX_DATEI) {
                            byte[] alles = new byte[fs.Length];
                            int n = 0;
                            while (n < alles.Length) { int r = fs.Read(alles, n, alles.Length - n); if (r <= 0) break; n += r; }
                            if (n == alles.Length && UzNostr.Hex(UzKrypto.Sha256(alles)) == soll) {
                                z = LADEN;
                                h = Windows ? LoadLibraryExW(pfad, IntPtr.Zero, LOAD_LIBRARY_SEARCH_SYSTEM32) : DlOpen(pfad, 2);
                                if (h != IntPtr.Zero) z = BEREIT;
                            }
                        }
                    }
                }
            } catch { h = IntPtr.Zero; if (z == BEREIT) z = LADEN; }
            zustand[name] = z;
            if (h != IntPtr.Zero) offen[name] = h;
            return h;
        }
    }

    // Eine Funktion der Bibliothek als Delegat (null, wenn es sie nicht gibt).
    public static Delegate Fn(IntPtr h, string name, Type t) {
        if (h == IntPtr.Zero) return null;
        IntPtr p = Windows ? GetProcAddress(h, name) : DlSym(h, name);
        return p == IntPtr.Zero ? null : Marshal.GetDelegateForFunctionPointer(p, t);
    }

    // Die Leitung zu Uzai vor fremdem Code schützen: Was eine Bibliothek auf die Standardausgabe oder -fehler schreibt
    // (printf, std::cout), ginge sonst mitten in die Rahmen. Darum bekommt die Sandbox eine eigene Kopie des Handles und
    // die Standardausgabe der C-Laufzeit wird geschlossen (Windows) bzw. auf /dev/null gelegt. null = so lassen.
    public static Stream AusgabeSchuetzen() {
        try {
            if (Windows) {
                IntPtr ich = GetCurrentProcess(), h2, h1 = GetStdHandle(-11), he = GetStdHandle(-12);
                if (!DuplicateHandle(ich, h1, ich, out h2, 0, false, 2)) return null;
                var s = new FileStream(new SafeFileHandle(h2, true), FileAccess.Write, 1);
                SetStdHandle(-11, IntPtr.Zero);
                SetStdHandle(-12, IntPtr.Zero);
                // _close schließt auch das alte Handle; die Sandbox bekommt kein eigenes für Fehler (Probe und Sitzung).
                try { CrtClose(1); if (he != IntPtr.Zero && he != h1 && he != (IntPtr)(-1)) CrtClose(2); } catch { return s; }
                Geschuetzt = true;
                return s;
            }
            int fd = Dup(1);
            if (fd < 0) return null;
            int leer = Open("/dev/null", 1);
            if (leer >= 0 && Dup2(leer, 1) == 1 && Dup2(leer, 2) == 2) Geschuetzt = true;
            return new FileStream(new SafeFileHandle((IntPtr)fd, true), FileAccess.Write, 1);
        } catch { return null; }
    }
}

// BIP-340-Schnorr über libsecp256k1 (nur schnorrsig + extrakeys). Alle Puffer haben feste Größen, die hier geprüft werden
// (Schlüsselpaar 96, x-only-Schlüssel 64 intern, 32 außen, Signatur 64, Nachricht 32). Selbsttest gegen die Testvektoren
// aus BIP-340 (bitcoin/bips, bip-0340/test-vectors.csv) beim ersten Gebrauch; scheitert er, gibt es keine Signatur.
public static class UzSecp {
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr FErzeugen(uint flags);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FMischen(IntPtr ctx, byte[] saat32);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FPaar(IntPtr ctx, [In, Out] byte[] paar96, byte[] geheim32);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FXonly(IntPtr ctx, [In, Out] byte[] pub64, IntPtr paritaet, byte[] paar96);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSchreiben(IntPtr ctx, [In, Out] byte[] aus32, byte[] pub64);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FLesen(IntPtr ctx, [In, Out] byte[] pub64, byte[] ein32);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSignieren(IntPtr ctx, [In, Out] byte[] sig64, byte[] nachricht32, byte[] paar96, byte[] zufall32);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FPruefen(IntPtr ctx, byte[] sig64, byte[] nachricht, UIntPtr laenge, byte[] pub64);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FGeheimOk(IntPtr ctx, byte[] geheim32);

    static readonly object Tor = new object();
    static int bereit = -1;
    static IntPtr ctx;
    static FPaar paar; static FXonly xonly; static FSchreiben schreiben; static FLesen lesen; static FSignieren signieren; static FPruefen pruefen; static FGeheimOk geheimOk;

    // Ausgewählte Vektoren aus BIP-340: geheim, öffentlich, Zufall, Nachricht, Signatur (signieren und prüfen) …
    static readonly string[][] SIGNIEREN = {
        new string[] { "0000000000000000000000000000000000000000000000000000000000000003", "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9",
            "0000000000000000000000000000000000000000000000000000000000000000", "0000000000000000000000000000000000000000000000000000000000000000",
            "E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0" },
        new string[] { "B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            "0000000000000000000000000000000000000000000000000000000000000001", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            "6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE33418906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A" },
        new string[] { "C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9", "DD308AFEC5777E13121FA72B9CC1B7CC0139715309B086C960E18FD969774EB8",
            "C87AA53824B4D7AE2EB035A2B5BBBCCC080E76CDC6D1692C4B0B62D798E6D906", "7E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C",
            "5831AAEED7B44BB74E5EAB94BA9D4294C49BCF2A60728D8B4C200F50DD313C1BAB745879A5AD954A72C45A91C3A51D3C7ADEA98D82F8481E0E1E03674A6F3FB7" },
        new string[] { "0B432B2677937381AEF05BB02A66ECD012773062CF3FA2549E44F58ED2401710", "25D1DFF95105F5253C4022F628A996AD3A0D95FBF21D468A1B33F8C160D8F517",
            "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
            "7EB0509757E246F19449885651611CB965ECC1A187DD51B64FDA1EDC9637D5EC97582B9CB13DB3933705B32BA982AF5AF25FD78881EBB32771FC5922EFC66EA3" },
    };
    // … und Signaturen, die scheitern müssen (Vektoren 5, 6, 12, 14: Schlüssel nicht auf der Kurve, ungerades R,
    // r ≥ p, Schlüssel ≥ p): öffentlich, Nachricht, Signatur.
    static readonly string[][] FALSCH = {
        new string[] { "EEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B" },
        new string[] { "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            "FFF97BD5755EEEA420453A14355235D382F6472F8568A18B2F057A14602975563CC27944640AC607CD107AE10923D9EF7A73C643E166BE5EBEAFA34B1AC553E2" },
        new string[] { "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B" },
        new string[] { "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC30", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B" },
    };

    // Geladen, Prüfsumme in Ordnung und Selbsttest bestanden?
    public static bool Bereit() {
        lock (Tor) {
            if (bereit >= 0) return bereit == 1;
            bereit = 0;
            IntPtr h = UzNetzLib.Laden(UzNetzLib.SECP);
            if (h == IntPtr.Zero) return false;
            bool ok = false;
            try {
                var erzeugen = (FErzeugen)UzNetzLib.Fn(h, "secp256k1_context_create", typeof(FErzeugen));
                var mischen = (FMischen)UzNetzLib.Fn(h, "secp256k1_context_randomize", typeof(FMischen));
                paar = (FPaar)UzNetzLib.Fn(h, "secp256k1_keypair_create", typeof(FPaar));
                xonly = (FXonly)UzNetzLib.Fn(h, "secp256k1_keypair_xonly_pub", typeof(FXonly));
                schreiben = (FSchreiben)UzNetzLib.Fn(h, "secp256k1_xonly_pubkey_serialize", typeof(FSchreiben));
                lesen = (FLesen)UzNetzLib.Fn(h, "secp256k1_xonly_pubkey_parse", typeof(FLesen));
                signieren = (FSignieren)UzNetzLib.Fn(h, "secp256k1_schnorrsig_sign32", typeof(FSignieren));
                pruefen = (FPruefen)UzNetzLib.Fn(h, "secp256k1_schnorrsig_verify", typeof(FPruefen));
                geheimOk = (FGeheimOk)UzNetzLib.Fn(h, "secp256k1_ec_seckey_verify", typeof(FGeheimOk));
                if (erzeugen != null && mischen != null && paar != null && xonly != null && schreiben != null && lesen != null && signieren != null && pruefen != null && geheimOk != null) {
                    ctx = erzeugen(1);   // SECP256K1_CONTEXT_NONE
                    ok = ctx != IntPtr.Zero && mischen(ctx, UzKrypto.Zufall(32)) == 1 && Vektoren();
                }
            } catch { ok = false; }
            bereit = ok ? 1 : 0;
            if (!ok) UzNetzLib.Setzen(UzNetzLib.SECP, UzNetzLib.SELBSTTEST);
            return ok;
        }
    }

    static bool Vektoren() {
        foreach (string[] v in SIGNIEREN) {
            byte[] kp = Paar(UzKrypto.Hex(v[0]));
            if (kp == null || !UzKrypto.Gleich(Oeffentlich(kp), UzKrypto.Hex(v[1]))) return false;
            byte[] sig = Signatur(kp, UzKrypto.Hex(v[3]), UzKrypto.Hex(v[2]));
            if (sig == null || !UzKrypto.Gleich(sig, UzKrypto.Hex(v[4]))) return false;
            if (!Pruefen(sig, UzKrypto.Hex(v[3]), UzKrypto.Hex(v[1]))) return false;
            sig[63] ^= 1;
            if (Pruefen(sig, UzKrypto.Hex(v[3]), UzKrypto.Hex(v[1]))) return false;
        }
        foreach (string[] v in FALSCH) if (Pruefen(UzKrypto.Hex(v[2]), UzKrypto.Hex(v[1]), UzKrypto.Hex(v[0]))) return false;
        return true;
    }

    // Schlüsselpaar (96 Byte, intern) aus einem geheimen Schlüssel; null, wenn er nicht taugt.
    static byte[] Paar(byte[] geheim) {
        if (geheim == null || geheim.Length != 32 || ctx == IntPtr.Zero) return null;
        var kp = new byte[96];
        lock (Tor) { if (geheimOk(ctx, geheim) != 1 || paar(ctx, kp, geheim) != 1) return null; }
        return kp;
    }

    static byte[] Oeffentlich(byte[] kp) {
        var pub = new byte[64];
        var aus = new byte[32];
        lock (Tor) { if (kp == null || kp.Length != 96 || xonly(ctx, pub, IntPtr.Zero, kp) != 1 || schreiben(ctx, aus, pub) != 1) return null; }
        return aus;
    }

    static byte[] Signatur(byte[] kp, byte[] nachricht, byte[] zufall) {
        if (kp == null || kp.Length != 96 || nachricht == null || nachricht.Length != 32 || zufall == null || zufall.Length != 32) return null;
        var sig = new byte[64];
        lock (Tor) { if (signieren(ctx, sig, nachricht, kp, zufall) != 1) return null; }
        return sig;
    }

    // Prüft eine Signatur (64) über eine Nachricht (32, bei Nostr die Ereignis-Kennung) mit einem x-only-Schlüssel (32).
    public static bool Pruefen(byte[] sig, byte[] nachricht, byte[] pub) {
        if (sig == null || sig.Length != 64 || nachricht == null || nachricht.Length != 32 || pub == null || pub.Length != 32 || ctx == IntPtr.Zero) return false;
        var p = new byte[64];
        lock (Tor) {
            if (lesen(ctx, p, pub) != 1) return false;
            return pruefen(ctx, sig, nachricht, (UIntPtr)32, p) == 1;
        }
    }

    // Ein Wegwerf-Schlüssel (Windows: CSPRNG über RandomNumberGenerator). Verlässt nie die Sandbox, lebt nur so lange
    // wie die Einladung bzw. der Besuch.
    public sealed class Schluessel : IDisposable {
        byte[] kp;
        public readonly byte[] Pub;

        public Schluessel() {
            for (int i = 0; i < 8 && kp == null; i++) {
                byte[] g = UzKrypto.Zufall(32);
                kp = Paar(g);
                Array.Clear(g, 0, g.Length);
            }
            if (kp == null) throw new InvalidOperationException();
            Pub = Oeffentlich(kp);
            if (Pub == null) throw new InvalidOperationException();
        }

        // Signatur über 32 Byte; jede wird vor dem Verschicken selbst noch einmal geprüft (Fehler im Rechenwerk).
        public byte[] Signieren(byte[] nachricht) {
            if (kp == null) return null;
            byte[] s = Signatur(kp, nachricht, UzKrypto.Zufall(32));
            return s != null && Pruefen(s, nachricht, Pub) ? s : null;
        }

        public void Dispose() { if (kp != null) { Array.Clear(kp, 0, kp.Length); kp = null; } }
    }
}

// Der WebRTC-Datenkanal über die C-Schnittstelle von libdatachannel (rtc.h, v0.24.6). Nur ein ausgehandelter Kanal je
// Verbindung (Strom 0, „uz“, zuverlässig, geordnet), nur Binärnachrichten bis 4096 Byte (größere kürzt libdatachannel
// auf diese Grenze, Prüfmauer 1 verwirft sie). ICE nur UDP, kein TURN, STUN nur fest eingetragen, kein UDP-Mux, kein
// eigener Port (ephemer). Rückrufe aus nativen Fäden setzen nur Zahlen in Tabellen; Nachrichten holt der Treffpunkt-Faden
// selbst ab (rtcReceiveMessage) – kein verwalteter Code wartet in einem fremden Faden.
public static class UzRtc {
    public const int MAX_NACHRICHT = 4096, PUFFER = 8192;
    public const int ZU = 5, GESCHEITERT = 4, VERBUNDEN = 2;
    public static readonly string[] STUN = { "stun:stun.l.google.com:19302", "stun:stun.cloudflare.com:3478" };

    [StructLayout(LayoutKind.Explicit, Size = 56)]
    public struct Konfig {
        [FieldOffset(0)] public IntPtr IceServer;
        [FieldOffset(8)] public int IceServerAnzahl;
        [FieldOffset(16)] public IntPtr Proxy;
        [FieldOffset(24)] public IntPtr Bindung;
        [FieldOffset(32)] public int Zertifikat;          // 1 = ECDSA
        [FieldOffset(36)] public int Richtlinie;          // 0 = alle (kein TURN eingetragen)
        [FieldOffset(40)] public byte IceTcp, UdpMux, OhneAutoAushandlung, MedienZwingen;
        [FieldOffset(44)] public ushort PortVon;
        [FieldOffset(46)] public ushort PortBis;
        [FieldOffset(48)] public int Mtu;
        [FieldOffset(52)] public int MaxNachricht;
    }

    [StructLayout(LayoutKind.Explicit, Size = 32)]
    public struct KanalInit {
        [FieldOffset(0)] public byte Ungeordnet;
        [FieldOffset(1)] public byte Unzuverlaessig;
        [FieldOffset(4)] public uint MaxLebenszeit;
        [FieldOffset(8)] public uint MaxWiederholungen;
        [FieldOffset(16)] public IntPtr Protokoll;
        [FieldOffset(24)] public byte Ausgehandelt;
        [FieldOffset(25)] public byte FesterStrom;
        [FieldOffset(26)] public ushort Strom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Sctp {
        public int Empfang, Senden, MaxStuecke, StartFenster, MaxSchub, Stau, VerzSack, MinRto, MaxRto, StartRto, MaxWdh, Herzschlag;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void ZustandRueckruf(int pc, int zustand, IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void KanalRueckruf(int pc, int dc, IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void FLeer();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void FLogger(int stufe, IntPtr rueckruf);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FZahl(uint n);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSctp(ref Sctp s);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FNeu(ref Konfig k);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FId(int id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)] delegate bool FIst(int id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FRueckruf(int id, IntPtr rueckruf);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Ansi)] delegate int FText(int id, string a);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Ansi)] delegate int FFern(int id, string sdp, string art);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FHolen(int id, [In, Out] byte[] puffer, int groesse);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Ansi)] delegate int FKanal(int pc, string label, ref KanalInit init);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSenden(int id, byte[] daten, int groesse);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FEmpfangen(int id, [In, Out] byte[] puffer, ref int groesse);

    static readonly object Tor = new object();
    static int bereit = -1;
    static FLeer cleanup;
    static FNeu neuPc;
    static FId schliessenPc, loeschenPc, loeschenKanal, schliessen, loeschen, verfuegbar, gepuffert;
    static FIst istOffen, istZu;
    static FRueckruf rZustand, rSammeln, rKanal;
    static FText lokalSetzen;
    static FFern fernSetzen;
    static FHolen lokalHolen;
    static FKanal kanal;
    static FSenden senden;
    static FEmpfangen empfangen;

    // Die Rückrufe leben so lange wie der Prozess (statisch, dazu fest gehalten): Auch ein später Rückruf aus einem
    // nativen Faden nach dem Schließen trifft nie auf eingesammelten Code. Sie schreiben nur in diese Tabellen, und nur
    // für Verbindungen, die hier eingetragen sind; Ausnahmen bleiben drinnen.
    public static readonly System.Collections.Concurrent.ConcurrentDictionary<int, int> Zustaende = new System.Collections.Concurrent.ConcurrentDictionary<int, int>();
    public static readonly System.Collections.Concurrent.ConcurrentDictionary<int, int> Gesammelt = new System.Collections.Concurrent.ConcurrentDictionary<int, int>();
    public static readonly System.Collections.Concurrent.ConcurrentQueue<int> FremdeKanaele = new System.Collections.Concurrent.ConcurrentQueue<int>();
    static readonly ZustandRueckruf aufZustand = AufZustand, aufSammeln = AufSammeln;
    static readonly KanalRueckruf aufKanal = AufKanal;
    static readonly GCHandle[] halten = { GCHandle.Alloc(aufZustand), GCHandle.Alloc(aufSammeln), GCHandle.Alloc(aufKanal) };
    static IntPtr pZustand, pSammeln, pKanal;

    static void AufZustand(int pc, int z, IntPtr p) {
        try { int alt; if (Zustaende.TryGetValue(pc, out alt)) Zustaende.TryUpdate(pc, z, alt); } catch { }
    }
    static void AufSammeln(int pc, int z, IntPtr p) {
        try { int alt; if (Gesammelt.TryGetValue(pc, out alt)) Gesammelt.TryUpdate(pc, z, alt); } catch { }
    }
    // Ein Kanal, den die Gegenstelle selbst öffnet: wird nicht benutzt, der Treffpunkt-Faden schließt ihn.
    static void AufKanal(int pc, int dc, IntPtr p) {
        try { if (FremdeKanaele.Count < 256) FremdeKanaele.Enqueue(dc); } catch { }
    }

    public static bool Bereit() {
        lock (Tor) {
            if (bereit >= 0) return bereit == 1;
            bereit = 0;
            IntPtr h = UzNetzLib.Laden(UzNetzLib.RTC);
            if (h == IntPtr.Zero) return false;
            bool ok = false;
            try {
                var logger = (FLogger)UzNetzLib.Fn(h, "rtcInitLogger", typeof(FLogger));
                var faeden = (FZahl)UzNetzLib.Fn(h, "rtcSetThreadPoolSize", typeof(FZahl));
                var sctp = (FSctp)UzNetzLib.Fn(h, "rtcSetSctpSettings", typeof(FSctp));
                cleanup = (FLeer)UzNetzLib.Fn(h, "rtcCleanup", typeof(FLeer));
                neuPc = (FNeu)UzNetzLib.Fn(h, "rtcCreatePeerConnection", typeof(FNeu));
                schliessenPc = (FId)UzNetzLib.Fn(h, "rtcClosePeerConnection", typeof(FId));
                loeschenPc = (FId)UzNetzLib.Fn(h, "rtcDeletePeerConnection", typeof(FId));
                loeschenKanal = (FId)UzNetzLib.Fn(h, "rtcDeleteDataChannel", typeof(FId));
                schliessen = (FId)UzNetzLib.Fn(h, "rtcClose", typeof(FId));
                loeschen = (FId)UzNetzLib.Fn(h, "rtcDelete", typeof(FId));
                verfuegbar = (FId)UzNetzLib.Fn(h, "rtcGetAvailableAmount", typeof(FId));
                gepuffert = (FId)UzNetzLib.Fn(h, "rtcGetBufferedAmount", typeof(FId));
                istOffen = (FIst)UzNetzLib.Fn(h, "rtcIsOpen", typeof(FIst));
                istZu = (FIst)UzNetzLib.Fn(h, "rtcIsClosed", typeof(FIst));
                rZustand = (FRueckruf)UzNetzLib.Fn(h, "rtcSetStateChangeCallback", typeof(FRueckruf));
                rSammeln = (FRueckruf)UzNetzLib.Fn(h, "rtcSetGatheringStateChangeCallback", typeof(FRueckruf));
                rKanal = (FRueckruf)UzNetzLib.Fn(h, "rtcSetDataChannelCallback", typeof(FRueckruf));
                lokalSetzen = (FText)UzNetzLib.Fn(h, "rtcSetLocalDescription", typeof(FText));
                fernSetzen = (FFern)UzNetzLib.Fn(h, "rtcSetRemoteDescription", typeof(FFern));
                lokalHolen = (FHolen)UzNetzLib.Fn(h, "rtcGetLocalDescription", typeof(FHolen));
                kanal = (FKanal)UzNetzLib.Fn(h, "rtcCreateDataChannelEx", typeof(FKanal));
                senden = (FSenden)UzNetzLib.Fn(h, "rtcSendMessage", typeof(FSenden));
                empfangen = (FEmpfangen)UzNetzLib.Fn(h, "rtcReceiveMessage", typeof(FEmpfangen));
                object[] alle = { logger, faeden, sctp, cleanup, neuPc, schliessenPc, loeschenPc, loeschenKanal, schliessen, loeschen, verfuegbar, gepuffert, istOffen, istZu,
                    rZustand, rSammeln, rKanal, lokalSetzen, fernSetzen, lokalHolen, kanal, senden, empfangen };
                ok = true;
                foreach (object f in alle) ok = ok && f != null;
                if (ok) {
                    pZustand = Marshal.GetFunctionPointerForDelegate(aufZustand);
                    pSammeln = Marshal.GetFunctionPointerForDelegate(aufSammeln);
                    pKanal = Marshal.GetFunctionPointerForDelegate(aufKanal);
                    logger(0, IntPtr.Zero);                 // RTC_LOG_NONE (die Ausgabe ist ohnehin ausgebaut)
                    faeden(2);
                    var s = new Sctp();
                    s.Empfang = 256 * 1024;                 // höchstens so viel puffert eine Verbindung
                    s.Senden = 256 * 1024;
                    sctp(ref s);
                    ok = Selbsttest();
                }
            } catch { ok = false; }
            bereit = ok ? 1 : 0;
            if (!ok) UzNetzLib.Setzen(UzNetzLib.RTC, UzNetzLib.SELBSTTEST);
            return ok;
        }
    }

    // Selbsttest ohne Netz: Verbindung und Kanal anlegen, das eigene Angebot muss ein DTLS-Fingerabdruck (SHA-256,
    // Zertifikat aus Mbed TLS) tragen und durch den SDP-Prüfer gehen. Danach alles wieder weg.
    static bool Selbsttest() {
        int pc = Neu(new string[0], "127.0.0.1");
        if (pc <= 0) return false;
        try {
            if (Kanal(pc) <= 0) return false;
            var uhr = Stopwatch.StartNew();
            while (uhr.ElapsedMilliseconds < 5000) {
                string sdp = Lokal(pc);
                if (sdp != null && sdp.Contains("a=fingerprint:sha-256 ")) return UzSdp.Pruefen(sdp, true) != null;
                Thread.Sleep(20);
            }
            return false;
        } finally { Weg(pc, 0); }
    }

    // Neue Verbindung; stun = feste STUN-Adressen (leer im Test), bindung = null (alle) oder „127.0.0.1“ (Test).
    public static int Neu(string[] stun, string bindung) {
        var zeiger = new List<IntPtr>();
        IntPtr liste = IntPtr.Zero, bind = IntPtr.Zero;
        try {
            liste = Marshal.AllocHGlobal(IntPtr.Size * Math.Max(1, stun.Length));
            for (int i = 0; i < stun.Length; i++) {
                IntPtr s = Marshal.StringToHGlobalAnsi(stun[i]);
                zeiger.Add(s);
                Marshal.WriteIntPtr(liste, i * IntPtr.Size, s);
            }
            if (bindung != null) bind = Marshal.StringToHGlobalAnsi(bindung);
            var k = new Konfig();
            k.IceServer = stun.Length > 0 ? liste : IntPtr.Zero;
            k.IceServerAnzahl = stun.Length;
            k.Bindung = bind;
            k.Zertifikat = 1;
            k.MaxNachricht = MAX_NACHRICHT;
            int pc;
            lock (Tor) pc = neuPc(ref k);   // libdatachannel kopiert die Texte
            if (pc <= 0) return -1;
            Zustaende[pc] = 0;
            Gesammelt[pc] = 0;
            rZustand(pc, pZustand);
            rSammeln(pc, pSammeln);
            rKanal(pc, pKanal);
            return pc;
        } catch { return -1; }
        finally {
            foreach (IntPtr s in zeiger) Marshal.FreeHGlobal(s);
            if (liste != IntPtr.Zero) Marshal.FreeHGlobal(liste);
            if (bind != IntPtr.Zero) Marshal.FreeHGlobal(bind);
        }
    }

    // Der eine ausgehandelte Kanal (beide Seiten legen ihn selbst an, Strom 0). Auf der anbietenden Seite stößt er
    // auch das Angebot an.
    public static int Kanal(int pc) {
        var init = new KanalInit();
        init.Ausgehandelt = 1;
        init.FesterStrom = 1;
        init.Strom = 0;
        try { return kanal(pc, "uz", ref init); } catch { return -1; }
    }

    public static bool Fern(int pc, string sdp, bool angebot) {
        try { return fernSetzen(pc, sdp, angebot ? "offer" : "answer") == 0; } catch { return false; }
    }

    // Das eigene Angebot bzw. die Antwort (ASCII, höchstens PUFFER-1 Byte), sonst null.
    public static string Lokal(int pc) {
        var b = new byte[PUFFER];
        int n;
        try { n = lokalHolen(pc, b, b.Length); } catch { return null; }
        if (n <= 1 || n > b.Length) return null;
        int ende = Array.IndexOf(b, (byte)0);
        if (ende < 0 || ende >= n) return null;
        for (int i = 0; i < ende; i++) if (b[i] > 0x7E || (b[i] < 0x20 && b[i] != '\r' && b[i] != '\n')) return null;
        return Encoding.ASCII.GetString(b, 0, ende);
    }

    public static int Zustand(int pc) { int z; return Zustaende.TryGetValue(pc, out z) ? z : ZU; }
    public static int Sammeln(int pc) { int z; return Gesammelt.TryGetValue(pc, out z) ? z : 0; }

    public static bool Offen(int dc) { try { return dc > 0 && istOffen(dc); } catch { return false; } }
    public static bool Geschlossen(int dc) { try { return dc <= 0 || istZu(dc); } catch { return true; } }

    // Senden nur ganz oder gar nicht: 1..MAX_NACHRICHT Byte, und nur, solange nicht mehr als 64 KiB warten.
    public static bool Senden(int dc, byte[] m) {
        if (dc <= 0 || m == null || m.Length < 1 || m.Length > MAX_NACHRICHT) return false;
        try {
            if (!istOffen(dc) || gepuffert(dc) > 65536) return false;
            return senden(dc, m, m.Length) == 0;
        } catch { return false; }
    }

    // Eine Nachricht abholen: null = keine da; leeres Feld = etwas, das nicht sein darf (Text, zu groß) – zählt als
    // Verstoß. Puffergrenzen: der Puffer ist doppelt so groß wie die erlaubte Länge; die gemeldete Länge wird geprüft.
    public static byte[] Holen(int dc, byte[] puffer) {
        if (dc <= 0 || puffer == null || puffer.Length != PUFFER) return null;
        int n = puffer.Length;
        int r;
        try { r = empfangen(dc, puffer, ref n); } catch { return null; }
        if (r == -3) return null;                       // RTC_ERR_NOT_AVAIL
        if (r == -4) {                                  // RTC_ERR_TOO_SMALL: kann nach der Grenze nicht sein – Kanal zu
            try { schliessen(dc); } catch { }
            return new byte[0];
        }
        if (r != 0) return null;
        if (n < 0) return new byte[0];                  // Textnachricht: gibt es im Protokoll nicht
        if (n == 0 || n > MAX_NACHRICHT || n > puffer.Length) return new byte[0];
        var m = new byte[n];
        Buffer.BlockCopy(puffer, 0, m, 0, n);
        return m;
    }

    // Kanal und Verbindung weg (auch, wenn nur eins davon lebt).
    public static void Weg(int pc, int dc) {
        try {
            if (dc > 0) loeschenKanal(dc);
            if (pc > 0) { schliessenPc(pc); loeschenPc(pc); }
        } catch { }
        int x;
        if (pc > 0) { Zustaende.TryRemove(pc, out x); Gesammelt.TryRemove(pc, out x); }
    }

    // Einen Kanal löschen, den die Gegenstelle geöffnet hat (nie einer von uns).
    public static void FremdWeg(int dc) { try { if (dc > 0) loeschen(dc); } catch { } }

    // Am Ende: alle Fäden der Bibliothek anhalten (mit Zeitgrenze, damit die Sandbox nie hängen bleibt).
    public static void Aufraeumen() {
        if (bereit != 1) return;
        var t = new Thread(delegate () { try { cleanup(); } catch { } });
        t.IsBackground = true;
        t.Start();
        t.Join(3000);
    }
}

// Die Direktverbindungen eines Treffpunkts: je Platz eine WebRTC-Verbindung mit genau einem Kanal. Gebraucht vom
// Treffpunkt-Faden (Neu, Fern, Lokal, Zustand, Weg, Pumpen) und vom Leitungs-Faden (Senden) – geteilt sind nur die
// Kanal-Nummern (volatile Lesezugriffe; ein veralteter Wert trifft höchstens einen gelöschten Kanal, das meldet die
// Bibliothek als Fehler).
public interface IUzDirekt {
    bool Neu(int platz, bool anbieter);
    bool Fern(int platz, string sdp, bool angebot);
    string Lokal(int platz);
    int Zustand(int platz);
    void Weg(int platz);
}

public sealed class UzDirekt : IUzDirekt {
    public const int SAMMELN_MS = 8000, AUFBAU_MS = 45000, JE_TAKT = 32;
    readonly bool test;
    readonly int[] pc, dc;
    readonly long[] seit;
    readonly bool[] gesendet, warOffen;
    readonly Stopwatch uhr = Stopwatch.StartNew();
    readonly byte[] puffer = new byte[UzRtc.PUFFER];

    public UzDirekt(int plaetze, bool test) {
        this.test = test;
        pc = new int[plaetze]; dc = new int[plaetze]; seit = new long[plaetze]; gesendet = new bool[plaetze]; warOffen = new bool[plaetze];
    }

    bool Platz(int p) { return p >= 0 && p < pc.Length; }

    // Anbieter: Verbindung und Kanal sofort (das stößt das Angebot an). Sonst erst die Verbindung; der Kanal entsteht
    // in Fern() nach dem fremden Angebot (sonst schriebe die Bibliothek ein eigenes Angebot statt der Antwort).
    public bool Neu(int platz, bool anbieter) {
        if (!Platz(platz) || pc[platz] > 0) return false;
        int p = UzRtc.Neu(test ? new string[0] : UzRtc.STUN, test ? "127.0.0.1" : null);
        if (p <= 0) return false;
        int d = 0;
        if (anbieter) {
            d = UzRtc.Kanal(p);
            if (d <= 0) { UzRtc.Weg(p, 0); return false; }
        }
        pc[platz] = p;
        Thread.VolatileWrite(ref dc[platz], d);
        seit[platz] = uhr.ElapsedMilliseconds;
        gesendet[platz] = false;
        warOffen[platz] = false;
        return true;
    }

    public bool Fern(int platz, string sdp, bool angebot) {
        if (!Platz(platz) || pc[platz] <= 0 || sdp == null || (angebot && dc[platz] > 0) || (!angebot && dc[platz] <= 0)) return false;
        if (!UzRtc.Fern(pc[platz], sdp, angebot)) return false;
        if (!angebot) return true;
        int d = UzRtc.Kanal(pc[platz]);
        if (d <= 0) return false;
        Thread.VolatileWrite(ref dc[platz], d);
        return true;
    }

    // Das eigene Angebot bzw. die Antwort, einmal, sobald alle Kandidaten gesammelt sind (spätestens nach 8 s).
    public string Lokal(int platz) {
        if (!Platz(platz) || pc[platz] <= 0 || gesendet[platz]) return null;
        bool fertig = UzRtc.Sammeln(pc[platz]) == 2 || uhr.ElapsedMilliseconds - seit[platz] > SAMMELN_MS;
        if (!fertig) return null;
        string s = UzRtc.Lokal(pc[platz]);
        if (s != null) gesendet[platz] = true;
        return s;
    }

    // -1 nichts, 0 im Aufbau, 1 offen, 2 gescheitert oder zu.
    public int Zustand(int platz) {
        if (!Platz(platz) || pc[platz] <= 0) return -1;
        int z = UzRtc.Zustand(pc[platz]);
        if (UzRtc.Offen(dc[platz])) { warOffen[platz] = true; return 1; }
        if (z == UzRtc.GESCHEITERT || z == UzRtc.ZU || (warOffen[platz] && UzRtc.Geschlossen(dc[platz]))) return 2;
        if (!warOffen[platz] && uhr.ElapsedMilliseconds - seit[platz] > AUFBAU_MS) return 2;
        return 0;
    }

    public void Weg(int platz) {
        if (!Platz(platz) || pc[platz] <= 0) return;
        int d = dc[platz];
        Thread.VolatileWrite(ref dc[platz], 0);
        UzRtc.Weg(pc[platz], d);
        pc[platz] = 0;
    }

    // Aus dem Leitungs-Faden: eine geprüfte Nachricht an die Gegenstelle auf diesem Platz.
    public bool Senden(int platz, byte[] m) {
        if (!Platz(platz)) return false;
        int d = Thread.VolatileRead(ref dc[platz]);
        return d > 0 && UzRtc.Senden(d, m);
    }

    public bool Offen(int platz) { return Platz(platz) && UzRtc.Offen(Thread.VolatileRead(ref dc[platz])); }

    // Aus dem Treffpunkt-Faden: fremde Kanäle schließen, Nachrichten abholen (höchstens JE_TAKT je Platz) und an
    // Prüfmauer 1 geben.
    public void Pumpen(Action<int, byte[]> ein) {
        int f;
        while (UzRtc.FremdeKanaele.TryDequeue(out f)) {
            bool unser = false;
            foreach (int d in dc) unser = unser || d == f;
            if (!unser) UzRtc.FremdWeg(f);
        }
        for (int p = 0; p < pc.Length; p++) {
            if (dc[p] <= 0) continue;
            for (int i = 0; i < JE_TAKT; i++) {
                byte[] m = UzRtc.Holen(dc[p], puffer);
                if (m == null) break;
                ein(p, m);
            }
        }
    }

    public bool Aktiv() { foreach (int p in pc) if (p > 0) return true; return false; }

    public void Stop() {
        for (int p = 0; p < pc.Length; p++) Weg(p);
        UzRtc.Aufraeumen();
    }
}

// --- Treffpunkt (Phase 3): öffentliche Nostr-Relays als Briefkasten, Ende-zu-Ende verschlüsselt ------
// Läuft nur hier in der Sandbox (docs/ZIMMER_SICHERHEIT.md W2, W4, W5, Abschnitt 5). Keine eigene
// Kryptografie: AES-256-GCM aus dem Betriebssystem (Windows: CNG, bcrypt.dll; sonst .NET AesGcm),
// ECDH P-256 mit SHA-256 (ECDiffieHellman), SHA-256, Zufall aus RandomNumberGenerator. Was fehlt:
// BIP-340-Schnorr-Signaturen der Nostr-Hülle (libsecp256k1) – ohne sie nimmt kein echtes Relay ein
// Ereignis an. Darum verbindet sich die Sandbox nie mit einem echten Relay, sondern meldet
// „Signatur fehlt“; nur mit „--test“ spricht sie mit einem Test-Relay auf 127.0.0.1.
public static class UzKrypto {
    public const int SCHLUESSEL = 32, NONCE = 12, TAG = 16, PUB = 65;
    static readonly object Tor = new object();
    static int bereit = -1;
    static Type gcmTyp;

    public static byte[] Zufall(int n) {
        var b = new byte[n];
        using (var r = System.Security.Cryptography.RandomNumberGenerator.Create()) r.GetBytes(b);
        return b;
    }

    public static byte[] Sha256(byte[] b) {
        using (var h = System.Security.Cryptography.SHA256.Create()) return h.ComputeHash(b);
    }

    // Vergleich ohne Zeit-Leck.
    public static bool Gleich(byte[] a, byte[] b) {
        if (a == null || b == null || a.Length != b.Length) return false;
        int d = 0;
        for (int i = 0; i < a.Length; i++) d |= a[i] ^ b[i];
        return d == 0;
    }

    public static byte[] Teil(byte[] b, int o, int n) {
        if (b == null || o < 0 || n < 0 || o + n > b.Length) return null;
        var t = new byte[n];
        Buffer.BlockCopy(b, o, t, 0, n);
        return t;
    }

    public static byte[] Kette(params byte[][] teile) {
        int n = 0;
        foreach (var t in teile) n += t.Length;
        var o = new byte[n];
        int p = 0;
        foreach (var t in teile) { Buffer.BlockCopy(t, 0, o, p, t.Length); p += t.Length; }
        return o;
    }

    // Versiegeln: Nonce (12 Byte Zufall) | Geheimtext | Tag (16). null bei Fehler.
    public static byte[] Zu(byte[] k, byte[] aad, byte[] klar) {
        if (k == null || k.Length != SCHLUESSEL || klar == null || klar.Length == 0) return null;
        byte[] nonce = Zufall(NONCE), ct = new byte[klar.Length], tag = new byte[TAG];
        if (!Gcm(true, k, nonce, klar, ct, tag, aad)) return null;
        return Kette(nonce, ct, tag);
    }

    // Öffnen: null, wenn Schlüssel, Zusatzdaten oder auch nur ein Bit nicht stimmen.
    public static byte[] Auf(byte[] k, byte[] aad, byte[] kiste) {
        if (k == null || k.Length != SCHLUESSEL || kiste == null || kiste.Length < NONCE + TAG + 1) return null;
        int n = kiste.Length - NONCE - TAG;
        byte[] klar = new byte[n];
        return Gcm(false, k, Teil(kiste, 0, NONCE), Teil(kiste, NONCE, n), klar, Teil(kiste, NONCE + n, TAG), aad) ? klar : null;
    }

    // Ein Durchgang AES-256-GCM. ver: input Klartext → output Geheimtext, tag wird gesetzt; sonst
    // input Geheimtext → output Klartext, tag wird geprüft (falsch → false, output leer).
    public static bool Gcm(bool ver, byte[] k, byte[] nonce, byte[] input, byte[] output, byte[] tag, byte[] aad) {
        try {
            bool ok = Environment.OSVersion.Platform == PlatformID.Win32NT ? UzCng.Gcm(ver, k, nonce, input, output, tag, aad ?? new byte[0])
                : NetGcm(ver, k, nonce, input, output, tag, aad ?? new byte[0]);
            if (!ok) Array.Clear(output, 0, output.Length);
            return ok;
        } catch { Array.Clear(output, 0, output.Length); return false; }
    }

    // Außerhalb von Windows (nur die Tests unter Linux): .NET AesGcm (OpenSSL), über Reflexion,
    // weil .NET Framework 4 die Klasse nicht kennt.
    static bool NetGcm(bool ver, byte[] k, byte[] nonce, byte[] input, byte[] output, byte[] tag, byte[] aad) {
        if (gcmTyp == null) gcmTyp = Type.GetType("System.Security.Cryptography.AesGcm, System.Security.Cryptography");
        if (gcmTyp == null) return false;
        object g;
        try { g = Activator.CreateInstance(gcmTyp, new object[] { k, TAG }); }
        catch (MissingMethodException) { g = Activator.CreateInstance(gcmTyp, new object[] { k }); }
        try {
            var t = typeof(byte[]);
            var m = gcmTyp.GetMethod(ver ? "Encrypt" : "Decrypt", new Type[] { t, t, t, t, t });
            if (m == null) return false;
            m.Invoke(g, ver ? new object[] { nonce, input, output, tag, aad } : new object[] { nonce, input, tag, output, aad });
            return true;
        } catch (System.Reflection.TargetInvocationException) { return false; }
        finally { var d = g as IDisposable; if (d != null) d.Dispose(); }
    }

    // Wegwerf-Schlüssel für einen Schlüsseltausch (ECDH P-256). Nur die öffentliche Hälfte verlässt ihn.
    public sealed class Dh : IDisposable {
        readonly System.Security.Cryptography.ECDiffieHellman k =
            System.Security.Cryptography.ECDiffieHellman.Create(System.Security.Cryptography.ECCurve.NamedCurves.nistP256);

        // 0x04 | X (32) | Y (32)
        public byte[] Oeffentlich() {
            var p = k.ExportParameters(false);
            if (p.Q.X == null || p.Q.Y == null || p.Q.X.Length != 32 || p.Q.Y.Length != 32) return null;
            return Kette(new byte[] { 4 }, p.Q.X, p.Q.Y);
        }

        // Gemeinsamer Schlüssel: SHA-256(vorne | ECDH-Geheimnis | hinten). null, wenn der fremde Punkt
        // nicht taugt (falsche Form, nicht auf der Kurve – das prüft die Bibliothek beim Einlesen).
        public byte[] Teilen(byte[] fremd, byte[] vorne, byte[] hinten) {
            if (fremd == null || fremd.Length != PUB || fremd[0] != 4) return null;
            try {
                var p = new System.Security.Cryptography.ECParameters();
                p.Curve = System.Security.Cryptography.ECCurve.NamedCurves.nistP256;
                var q = new System.Security.Cryptography.ECPoint();
                q.X = Teil(fremd, 1, 32);
                q.Y = Teil(fremd, 33, 32);
                p.Q = q;
                p.Validate();
                using (var f = System.Security.Cryptography.ECDiffieHellman.Create(p)) {
                    byte[] s = k.DeriveKeyFromHash(f.PublicKey, System.Security.Cryptography.HashAlgorithmName.SHA256, vorne, hinten);
                    return s != null && s.Length == SCHLUESSEL ? s : null;
                }
            } catch { return null; }
        }

        public void Dispose() { k.Dispose(); }
    }

    // Liegt der Punkt (0x04 | X | Y) auf P-256? Das prüft die Bibliothek beim Einlesen.
    public static bool PunktOk(byte[] pub) {
        if (pub == null || pub.Length != PUB || pub[0] != 4) return false;
        try {
            var p = new System.Security.Cryptography.ECParameters();
            p.Curve = System.Security.Cryptography.ECCurve.NamedCurves.nistP256;
            var q = new System.Security.Cryptography.ECPoint();
            q.X = Teil(pub, 1, 32);
            q.Y = Teil(pub, 33, 32);
            p.Q = q;
            p.Validate();
            using (var f = System.Security.Cryptography.ECDiffieHellman.Create(p)) return f.KeySize == 256;
        } catch { return false; }
    }

    public static byte[] Hex(string s) {
        var b = new byte[s.Length / 2];
        for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(s.Substring(2 * i, 2), 16);
        return b;
    }

    // Selbsttest (einmal je Prozess): AES-256-GCM gegen Testfall 16 der GCM-Spezifikation (McGrew/
    // Viega), ein verändertes Bit muss scheitern, Hin und Zurück, ECDH beider Seiten gleich, ein
    // Punkt außerhalb der Kurve abgelehnt. Scheitert etwas, bleibt der Treffpunkt aus.
    public static bool Selbsttest() {
        lock (Tor) {
            if (bereit >= 0) return bereit == 1;
            bool ok = false;
            try {
                byte[] k = Hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308");
                byte[] iv = Hex("cafebabefacedbaddecaf888");
                byte[] p = Hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39");
                byte[] a = Hex("feedfacedeadbeeffeedfacedeadbeefabaddad2");
                byte[] c = Hex("522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662");
                byte[] t = Hex("76fc6ece0f4e1768cddf8853bb2d551b");
                byte[] ct = new byte[p.Length], tag = new byte[TAG], zurueck = new byte[p.Length];
                ok = Gcm(true, k, iv, p, ct, tag, a) && Gleich(ct, c) && Gleich(tag, t) && Gcm(false, k, iv, c, zurueck, t, a) && Gleich(zurueck, p);
                t[0] ^= 1;
                ok = ok && !Gcm(false, k, iv, c, zurueck, t, a);
                byte[] kiste = Zu(k, a, p);
                ok = ok && kiste != null && Gleich(Auf(k, a, kiste), p) && Auf(k, new byte[] { 1 }, kiste) == null;
                using (Dh x = new Dh(), y = new Dh()) {
                    byte[] v = { 1 }, h = { 2 };
                    byte[] s1 = x.Teilen(y.Oeffentlich(), v, h), s2 = y.Teilen(x.Oeffentlich(), v, h);
                    byte[] falsch = y.Oeffentlich();
                    falsch[64] ^= 1;
                    ok = ok && s1 != null && Gleich(s1, s2) && x.Teilen(falsch, v, h) == null;
                }
            } catch { ok = false; }
            bereit = ok ? 1 : 0;
            return ok;
        }
    }
}

// AES-GCM über Windows CNG (bcrypt.dll) – der Weg unter .NET Framework 4 (so baut der Helfer die Sandbox).
public static class UzCng {
    [StructLayout(LayoutKind.Sequential)]
    public struct AUTH_INFO {
        public int cbSize, dwInfoVersion;
        public IntPtr pbNonce; public int cbNonce;
        public IntPtr pbAuthData; public int cbAuthData;
        public IntPtr pbTag; public int cbTag;
        public IntPtr pbMacContext; public int cbMacContext;
        public int cbAAD; public long cbData; public int dwFlags;
    }
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)] static extern int BCryptOpenAlgorithmProvider(out IntPtr alg, string id, string impl, int flags);
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)] static extern int BCryptSetProperty(IntPtr h, string name, byte[] wert, int n, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptGenerateSymmetricKey(IntPtr alg, out IntPtr key, IntPtr obj, int nObj, byte[] geheim, int n, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptEncrypt(IntPtr key, byte[] ein, int nEin, ref AUTH_INFO info, byte[] iv, int nIv, byte[] aus, int nAus, out int n, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptDecrypt(IntPtr key, byte[] ein, int nEin, ref AUTH_INFO info, byte[] iv, int nIv, byte[] aus, int nAus, out int n, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptDestroyKey(IntPtr key);
    [DllImport("bcrypt.dll")] static extern int BCryptCloseAlgorithmProvider(IntPtr alg, int flags);

    public static bool Gcm(bool ver, byte[] k, byte[] nonce, byte[] input, byte[] output, byte[] tag, byte[] aad) {
        IntPtr alg = IntPtr.Zero, key = IntPtr.Zero;
        GCHandle hn = GCHandle.Alloc(nonce, GCHandleType.Pinned), ht = GCHandle.Alloc(tag, GCHandleType.Pinned), ha = GCHandle.Alloc(aad, GCHandleType.Pinned);
        try {
            if (BCryptOpenAlgorithmProvider(out alg, "AES", null, 0) != 0) return false;
            byte[] modus = Encoding.Unicode.GetBytes("ChainingModeGCM\0");
            if (BCryptSetProperty(alg, "ChainingMode", modus, modus.Length, 0) != 0) return false;
            if (BCryptGenerateSymmetricKey(alg, out key, IntPtr.Zero, 0, k, k.Length, 0) != 0) return false;
            var info = new AUTH_INFO();
            info.cbSize = Marshal.SizeOf(typeof(AUTH_INFO));
            info.dwInfoVersion = 1;
            info.pbNonce = hn.AddrOfPinnedObject();
            info.cbNonce = nonce.Length;
            info.pbAuthData = aad.Length > 0 ? ha.AddrOfPinnedObject() : IntPtr.Zero;
            info.cbAuthData = aad.Length;
            info.pbTag = ht.AddrOfPinnedObject();
            info.cbTag = tag.Length;
            int n;
            int r = ver ? BCryptEncrypt(key, input, input.Length, ref info, null, 0, output, output.Length, out n, 0)
                : BCryptDecrypt(key, input, input.Length, ref info, null, 0, output, output.Length, out n, 0);
            return r == 0 && n == output.Length;
        } finally {
            if (key != IntPtr.Zero) BCryptDestroyKey(key);
            if (alg != IntPtr.Zero) BCryptCloseAlgorithmProvider(alg, 0);
            hn.Free(); ht.Free(); ha.Free();
        }
    }
}

// Ein strenger, kleiner JSON-Leser nur für Antworten der Relays: begrenzte Länge, Tiefe und Anzahl,
// nur Ganzzahlen, doppelte Schlüssel abgelehnt. Ergebnis: List<object>, Dictionary<string, object>,
// string, long, bool, UzJson.Null – oder null, wenn irgendetwas nicht passt. Erzeugt nie Objekte
// anderer Art und führt nichts aus.
public static class UzJson {
    public const int MAX_TEXT = 16384, MAX_TIEFE = 4, MAX_KNOTEN = 48, MAX_STR = 8192;
    public static readonly object Null = new object();

    sealed class Leser { public string S; public int I, Knoten; }

    public static object Lesen(string s) {
        if (s == null || s.Length == 0 || s.Length > MAX_TEXT) return null;
        var l = new Leser();
        l.S = s;
        try {
            object v = Wert(l, 0);
            Leer(l);
            return l.I == s.Length ? v : null;
        } catch (FormatException) { return null; }
    }

    static void Fehler() { throw new FormatException(); }

    static void Leer(Leser l) {
        while (l.I < l.S.Length && (l.S[l.I] == ' ' || l.S[l.I] == '\t' || l.S[l.I] == '\n' || l.S[l.I] == '\r')) l.I++;
    }

    static bool Ist(Leser l, char c) {
        if (l.I < l.S.Length && l.S[l.I] == c) { l.I++; return true; }
        return false;
    }

    static bool Wort(Leser l, string w) {
        if (l.I + w.Length > l.S.Length || string.CompareOrdinal(l.S, l.I, w, 0, w.Length) != 0) return false;
        l.I += w.Length;
        return true;
    }

    static object Wert(Leser l, int tiefe) {
        if (tiefe > MAX_TIEFE || ++l.Knoten > MAX_KNOTEN) Fehler();
        Leer(l);
        if (l.I >= l.S.Length) Fehler();
        char c = l.S[l.I];
        if (c == '[') {
            l.I++;
            var a = new List<object>();
            Leer(l);
            if (Ist(l, ']')) return a;
            while (true) {
                a.Add(Wert(l, tiefe + 1));
                Leer(l);
                if (Ist(l, ']')) return a;
                if (!Ist(l, ',')) Fehler();
            }
        }
        if (c == '{') {
            l.I++;
            var o = new Dictionary<string, object>();
            Leer(l);
            if (Ist(l, '}')) return o;
            while (true) {
                Leer(l);
                if (l.I >= l.S.Length || l.S[l.I] != '"') Fehler();
                string k = Text(l);
                Leer(l);
                if (!Ist(l, ':') || o.ContainsKey(k)) Fehler();
                if (++l.Knoten > MAX_KNOTEN) Fehler();
                o[k] = Wert(l, tiefe + 1);
                Leer(l);
                if (Ist(l, '}')) return o;
                if (!Ist(l, ',')) Fehler();
            }
        }
        if (c == '"') return Text(l);
        if (Wort(l, "true")) return true;
        if (Wort(l, "false")) return false;
        if (Wort(l, "null")) return Null;
        if (c == '-' || (c >= '0' && c <= '9')) return Zahl(l);
        Fehler();
        return null;
    }

    // Nur Ganzzahlen bis 15 Stellen, ohne führende Nullen, ohne Komma und Exponent.
    static object Zahl(Leser l) {
        bool minus = Ist(l, '-');
        int start = l.I;
        while (l.I < l.S.Length && l.S[l.I] >= '0' && l.S[l.I] <= '9') l.I++;
        int n = l.I - start;
        if (n == 0 || n > 15 || (n > 1 && l.S[start] == '0')) Fehler();
        if (l.I < l.S.Length && (l.S[l.I] == '.' || l.S[l.I] == 'e' || l.S[l.I] == 'E')) Fehler();
        long v = 0;
        for (int i = start; i < l.I; i++) v = v * 10 + (l.S[i] - '0');
        return minus ? -v : v;
    }

    static string Text(Leser l) {
        l.I++;
        var sb = new StringBuilder();
        while (true) {
            if (l.I >= l.S.Length) Fehler();
            char c = l.S[l.I++];
            if (c == '"') return sb.ToString();
            if (c < 0x20) Fehler();
            if (c == '\\') {
                if (l.I >= l.S.Length) Fehler();
                char e = l.S[l.I++];
                switch (e) {
                    case '"': case '\\': case '/': c = e; break;
                    case 'b': c = '\b'; break;
                    case 'f': c = '\f'; break;
                    case 'n': c = '\n'; break;
                    case 'r': c = '\r'; break;
                    case 't': c = '\t'; break;
                    case 'u': {
                        if (l.I + 4 > l.S.Length) Fehler();
                        int v = 0;
                        for (int i = 0; i < 4; i++) {
                            char h = l.S[l.I++];
                            int d = h >= '0' && h <= '9' ? h - '0' : h >= 'a' && h <= 'f' ? h - 'a' + 10 : h >= 'A' && h <= 'F' ? h - 'A' + 10 : -1;
                            if (d < 0) Fehler();
                            v = v * 16 + d;
                        }
                        c = (char)v;
                        break;
                    }
                    default: Fehler(); break;
                }
            }
            sb.Append(c);
            if (sb.Length > MAX_STR) Fehler();
        }
    }
}

// Nostr (NIP-01) nur so weit, wie der Treffpunkt es braucht: ein flüchtiges Ereignis (Art 20777,
// Relays speichern es nicht) mit genau einem Merkmal „z“ (Postfach = zufällige Zimmer-Kennung) und
// dem versiegelten Inhalt als Base64. Alles Gelesene wird Feld für Feld geprüft und die Kennung
// nachgerechnet; mit libsecp256k1 prüft der Treffpunkt zusätzlich die BIP-340-Signatur (fremde,
// ungültige Ereignisse fliegen raus). Die Sicherheit selbst hängt nicht daran, sondern an AES-GCM.
public static class UzNostr {
    public const int ART = 20777, MAX_INHALT = 4096, FENSTER = 120;
    // Feste Relays (mehrere als Rückfall). Uzai wählt nie eine Adresse; die Liste steht nur hier.
    public static readonly string[] RELAYS = { "wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net", "wss://relay.snort.social" };
    const string HEX = "0123456789abcdef";
    const string B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    // Wer Nostr-Ereignisse signiert (BIP-340 Schnorr über secp256k1).
    public abstract class Signierer {
        public abstract string Pub { get; }
        public abstract string Sig(string id);
    }

    // Echt: ein Wegwerf-Schlüssel (je Einladung bzw. Besuch neu, aus dem Zufall des Betriebssystems), signiert mit
    // libsecp256k1. Gibt es nur, wenn die Bibliothek geladen ist und ihren Selbsttest bestanden hat.
    public sealed class EchtSignierer : Signierer {
        readonly UzSecp.Schluessel k = new UzSecp.Schluessel();
        readonly string pub;
        public EchtSignierer() { pub = Hex(k.Pub); }
        public override string Pub { get { return pub; } }
        public override string Sig(string id) {
            byte[] m = HexLesen(id, 32);
            byte[] s = m != null ? k.Signieren(m) : null;
            return s != null ? Hex(s) : null;
        }
    }

    // Nur fürs Test-Relay auf 127.0.0.1: zufälliger Wegwerf-Name, Signatur aus Nullen. Echte
    // Relays würden das ablehnen.
    public sealed class TestSignierer : Signierer {
        readonly string pub = Hex(UzKrypto.Zufall(32));
        public override string Pub { get { return pub; } }
        public override string Sig(string id) { return new string('0', 128); }
    }

    public static Signierer EchterSignierer() {
        if (!UzSecp.Bereit()) return null;
        try { return new EchtSignierer(); } catch { return null; }
    }

    // Die Signatur eines gelesenen Ereignisses (Kennung schon nachgerechnet).
    public static bool SignaturOk(Ein e) {
        return e != null && UzSecp.Pruefen(HexLesen(e.Sig, 64), HexLesen(e.Id, 32), HexLesen(e.Pub, 32));
    }

    public static string Hex(byte[] b) {
        var sb = new StringBuilder(b.Length * 2);
        foreach (byte x in b) sb.Append(HEX[x >> 4]).Append(HEX[x & 15]);
        return sb.ToString();
    }

    // Genau n Bytes als kleine Hex-Zeichen, sonst null.
    public static byte[] HexLesen(string s, int n) {
        if (s == null || s.Length != 2 * n) return null;
        var b = new byte[n];
        for (int i = 0; i < n; i++) {
            int h = HEX.IndexOf(s[2 * i]), l = HEX.IndexOf(s[2 * i + 1]);
            if (h < 0 || l < 0) return null;
            b[i] = (byte)(h * 16 + l);
        }
        return b;
    }

    public static byte[] B64Lesen(string s) {
        if (s == null || s.Length == 0 || s.Length > MAX_INHALT || s.Length % 4 != 0) return null;
        for (int i = 0; i < s.Length; i++) if (B64.IndexOf(s[i]) < 0 && !(s[i] == '=' && i >= s.Length - 2)) return null;
        if (s[s.Length - 2] == '=' && s[s.Length - 1] != '=') return null;
        try {
            byte[] b = Convert.FromBase64String(s);
            return Convert.ToBase64String(b) == s ? b : null;
        } catch (FormatException) { return null; }
    }

    static string Zahl(long v) { return v.ToString(System.Globalization.CultureInfo.InvariantCulture); }

    // NIP-01: Kennung = SHA-256 über [0,pubkey,created_at,kind,tags,content]. Alle Felder bestehen nur
    // aus Hex- bzw. Base64-Zeichen, darum gibt es nichts zu maskieren und die Form ist eindeutig.
    public static string Id(string pub, long zeit, string z, string inhalt) {
        string s = "[0,\"" + pub + "\"," + Zahl(zeit) + "," + Zahl(ART) + ",[[\"z\",\"" + z + "\"]],\"" + inhalt + "\"]";
        return Hex(UzKrypto.Sha256(Encoding.UTF8.GetBytes(s)));
    }

    // Ein Ereignis zum Verschicken (["EVENT", {…}]); null, wenn ein Feld nicht passt.
    public static string Ereignis(Signierer sig, long zeit, string z, string inhalt, out string id) {
        id = null;
        if (sig == null || HexLesen(sig.Pub, 32) == null || HexLesen(z, 16) == null || B64Lesen(inhalt) == null) return null;
        id = Id(sig.Pub, zeit, z, inhalt);
        string s = sig.Sig(id);
        if (s == null || s.Length != 128 || HexLesen(s, 64) == null) return null;
        return "[\"EVENT\",{\"id\":\"" + id + "\",\"pubkey\":\"" + sig.Pub + "\",\"created_at\":" + Zahl(zeit) + ",\"kind\":" + Zahl(ART) +
            ",\"tags\":[[\"z\",\"" + z + "\"]],\"content\":\"" + inhalt + "\",\"sig\":\"" + s + "\"}]";
    }

    // Abo auf die eigenen Postfächer (höchstens 16 Kennungen).
    public static string Abo(string abo, IList<string> z, long seit) {
        var sb = new StringBuilder("[\"REQ\",\"" + abo + "\",{\"kinds\":[" + Zahl(ART) + "],\"#z\":[");
        for (int i = 0; i < z.Count && i < 16; i++) sb.Append(i > 0 ? "," : "").Append('"').Append(z[i]).Append('"');
        return sb.Append("],\"since\":").Append(Zahl(seit)).Append("}]").ToString();
    }

    public sealed class Ein { public string Id, Pub, Z, Inhalt, Sig; public long Zeit; }

    // Antwort eines Relays → das Ereignis, wenn es genau die erwartete Form hat; sonst null.
    // still: eine bekannte Nachricht ohne Ereignis (OK, EOSE, NOTICE, CLOSED, AUTH) – kein Unsinn.
    public static Ein Lesen(string text, string abo, out bool still) {
        still = false;
        var a = UzJson.Lesen(text) as List<object>;
        if (a == null || a.Count < 2 || a.Count > 4) return null;
        string was = a[0] as string;
        if (was == "OK" || was == "EOSE" || was == "NOTICE" || was == "CLOSED" || was == "AUTH") { still = true; return null; }
        if (was != "EVENT" || a.Count != 3 || (a[1] as string) != abo) return null;
        var o = a[2] as Dictionary<string, object>;
        if (o == null || o.Count != 7) return null;
        var e = new Ein();
        e.Id = Feld(o, "id");
        e.Pub = Feld(o, "pubkey");
        e.Inhalt = Feld(o, "content");
        string sig = Feld(o, "sig");
        e.Sig = sig;
        object zeit, art, tags;
        if (!o.TryGetValue("created_at", out zeit) || !(zeit is long) || !o.TryGetValue("kind", out art) || !(art is long) || (long)art != ART) return null;
        e.Zeit = (long)zeit;
        if (e.Zeit < 0 || e.Zeit > 0xFFFFFFFFFFL || HexLesen(e.Id, 32) == null || HexLesen(e.Pub, 32) == null || HexLesen(sig, 64) == null) return null;
        if (!o.TryGetValue("tags", out tags) || !(tags is List<object>) || ((List<object>)tags).Count != 1) return null;
        var t = ((List<object>)tags)[0] as List<object>;
        if (t == null || t.Count != 2 || (t[0] as string) != "z" || HexLesen(t[1] as string, 16) == null) return null;
        e.Z = (string)t[1];
        if (B64Lesen(e.Inhalt) == null || Id(e.Pub, e.Zeit, e.Z, e.Inhalt) != e.Id) return null;
        return e;
    }

    static string Feld(Dictionary<string, object> o, string k) {
        object v;
        return o.TryGetValue(k, out v) ? v as string : null;
    }
}

// Verbindungsangebot (SDP) prüfen, bevor es versiegelt hinausgeht oder nach dem Öffnen weitergeht
// (Phase 4 gibt es dem WebRTC-Teil). Nur ein Datenkanal, genau ein DTLS-Fingerabdruck (SHA-256),
// bekannte Zeilen; ICE-Kandidaten nur UDP mit IP-Adresse (keine Namen), lokale Adressen fliegen
// raus (außer erlaubt), „raddr“ wird zu 0.0.0.0. Die Standard-Adresse in „c=“ und der Port in „m=“ (libdatachannel
// trägt dort den ersten Kandidaten ein, auch ein Heimnetz) werden immer zu 0.0.0.0 bzw. 9. Was nicht passt: null.
public static class UzSdp {
    public const int MAX = 3000, MAX_ZEILEN = 40, MAX_ZEILE = 256, MAX_KANDIDATEN = 16;
    static readonly string[] FEST = { "s=-", "t=0 0", "a=end-of-candidates", "a=extmap-allow-mixed", "a=msid-semantic: WMS", "a=msid-semantic:WMS *", "a=sendrecv" };
    static readonly string[] ANFANG = { "o=- ", "o=rtc ", "c=IN IP4 ", "c=IN IP6 ", "a=group:BUNDLE ", "a=ice-ufrag:", "a=ice-pwd:", "a=ice-options:", "a=fingerprint:sha-256 ",
        "a=setup:", "a=mid:", "a=sctp-port:", "a=max-message-size:", "a=candidate:", "m=application " };

    static bool Zeichen(string s, string erlaubt, int min, int max) {
        if (s == null || s.Length < min || s.Length > max) return false;
        foreach (char c in s) if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || erlaubt.IndexOf(c) >= 0)) return false;
        return true;
    }

    static bool Ziffern(string s, int max, long hoechstens) {
        if (s == null || s.Length == 0 || s.Length > max) return false;
        foreach (char c in s) if (c < '0' || c > '9') return false;
        // 20 Ziffern können über long hinausgehen: abgelehnt, statt mit einer Ausnahme aus der Prüfung zu fallen.
        long v;
        return long.TryParse(s, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out v) && v <= hoechstens;
    }

    public static string Pruefen(string sdp, bool lokal) {
        if (sdp == null || sdp.Length == 0 || sdp.Length > MAX) return null;
        foreach (char c in sdp) if ((c < 0x20 || c > 0x7E) && c != '\r' && c != '\n') return null;
        string[] zeilen = sdp.Replace("\r\n", "\n").Split('\n');
        int n = zeilen.Length;
        if (n > 0 && zeilen[n - 1] == "") n--;
        if (n < 2 || n > MAX_ZEILEN || zeilen[0] != "v=0") return null;
        var aus = new List<string>();
        aus.Add("v=0");
        int m = 0, fp = 0, ufrag = 0, pwd = 0, setup = 0, kand = 0;
        for (int i = 1; i < n; i++) {
            string z = zeilen[i];
            if (z.Length == 0 || z.Length > MAX_ZEILE) return null;
            if (Array.IndexOf(FEST, z) >= 0) { aus.Add(z); continue; }
            string anf = null;
            foreach (string a in ANFANG) if (z.StartsWith(a, StringComparison.Ordinal)) { anf = a; break; }
            if (anf == null) return null;
            string w = z.Substring(anf.Length);
            switch (anf) {
                case "o=- ":
                case "o=rtc ": {
                    string[] t = w.Split(' ');
                    if (t.Length != 5 || !Ziffern(t[0], 20, long.MaxValue) || !Ziffern(t[1], 10, uint.MaxValue) || t[2] != "IN" || (t[3] != "IP4" && t[3] != "IP6")) return null;
                    aus.Add("o=- " + t[0] + " " + t[1] + " IN " + t[3] + " " + (t[3] == "IP4" ? "127.0.0.1" : "::1"));
                    continue;
                }
                case "c=IN IP4 ": if (w != "0.0.0.0" && (Adresse(w) == null || Adresse(w).Length != 4)) return null; aus.Add("c=IN IP4 0.0.0.0"); continue;
                case "c=IN IP6 ": if (w != "::" && (Adresse(w) == null || Adresse(w).Length != 16)) return null; aus.Add("c=IN IP6 ::"); continue;
                case "a=group:BUNDLE ": case "a=mid:": if (!Zeichen(w, " ", 1, 16)) return null; break;
                case "a=ice-ufrag:": if (!Zeichen(w, "+/", 4, 256)) return null; ufrag++; break;
                case "a=ice-pwd:": if (!Zeichen(w, "+/", 22, 256)) return null; pwd++; break;
                case "a=ice-options:": if (w != "trickle" && w != "ice2" && w != "trickle ice2" && w != "ice2 trickle" && w != "ice2,trickle") return null; break;
                case "a=fingerprint:sha-256 ": {
                    string f = w.ToUpperInvariant();
                    if (f.Length != 95) return null;
                    for (int k = 0; k < 95; k++) {
                        bool trenner = k % 3 == 2;
                        if (trenner ? f[k] != ':' : "0123456789ABCDEF".IndexOf(f[k]) < 0) return null;
                    }
                    fp++;
                    aus.Add("a=fingerprint:sha-256 " + f);
                    continue;
                }
                case "a=setup:": if (w != "actpass" && w != "active" && w != "passive") return null; setup++; break;
                case "a=sctp-port:": if (!Ziffern(w, 5, 65535)) return null; break;
                case "a=max-message-size:": if (!Ziffern(w, 9, 268435456)) return null; break;
                case "m=application ": {
                    string[] t = w.Split(' ');
                    if (t.Length != 3 || !Ziffern(t[0], 5, 65535) || t[1] != "UDP/DTLS/SCTP" || t[2] != "webrtc-datachannel") return null;
                    m++;
                    aus.Add("m=application 9 UDP/DTLS/SCTP webrtc-datachannel");
                    continue;
                }
                case "a=candidate:": {
                    string k = Kandidat(w, lokal);
                    if (k == null) return null;
                    if (k == "") continue;
                    if (++kand > MAX_KANDIDATEN) return null;
                    aus.Add("a=candidate:" + k);
                    continue;
                }
            }
            aus.Add(z);
        }
        if (m != 1 || fp != 1 || ufrag != 1 || pwd != 1 || setup != 1) return null;
        return string.Join("\r\n", aus.ToArray()) + "\r\n";
    }

    // Ein Kandidat neu geschrieben, "" = wird weggelassen (TCP, Relais, Name, lokale Adresse), null = Unsinn.
    static string Kandidat(string w, bool lokal) {
        string[] t = w.Split(' ');
        if (t.Length < 8 || t.Length > 18 || !Zeichen(t[0], "+/", 1, 32) || (t[1] != "1" && t[1] != "2") || !Ziffern(t[3], 10, uint.MaxValue) || !Ziffern(t[5], 5, 65535) || t[6] != "typ") return null;
        string transport = t[2].ToLowerInvariant(), typ = t[7];
        if (transport != "udp" && transport != "tcp") return null;
        if (typ != "host" && typ != "srflx" && typ != "prflx" && typ != "relay") return null;
        byte[] ip = Adresse(t[4]);
        if (transport != "udp" || typ == "relay" || ip == null || t[5] == "0") return "";
        if (!lokal && Lokal(ip)) return "";
        string r = t[0] + " " + t[1] + " udp " + t[3] + " " + t[4] + " " + t[5] + " typ " + typ;
        return typ == "host" ? r : r + " raddr 0.0.0.0 rport 0";
    }

    // Nur eine IP-Adresse in Normalform: IPv4 als vier Zahlen ohne führende Nullen, IPv6 nur Hex und
    // Doppelpunkte (keine Namen wie *.local, keine Zonen). Sonst null.
    public static byte[] Adresse(string s) {
        if (s == null || s.Length < 2 || s.Length > 39) return null;
        if (s.IndexOf(':') < 0) {
            string[] t = s.Split('.');
            if (t.Length != 4) return null;
            var b = new byte[4];
            for (int i = 0; i < 4; i++) {
                if (!Ziffern(t[i], 3, 255) || (t[i].Length > 1 && t[i][0] == '0')) return null;
                b[i] = (byte)int.Parse(t[i], System.Globalization.CultureInfo.InvariantCulture);
            }
            return b;
        }
        foreach (char c in s) if ("0123456789abcdefABCDEF:".IndexOf(c) < 0) return null;
        System.Net.IPAddress a;
        if (!System.Net.IPAddress.TryParse(s, out a) || a.AddressFamily != System.Net.Sockets.AddressFamily.InterNetworkV6) return null;
        return a.GetAddressBytes();
    }

    // Heimnetz, eigenes Gerät, Provider-NAT, Verbindungs-lokal, Mehrfach-/Sonderadressen.
    public static bool Lokal(byte[] ip) {
        if (ip.Length == 4) {
            int a = ip[0], b = ip[1];
            return a == 0 || a == 10 || a == 127 || a >= 224 || (a == 100 && b >= 64 && b < 128) || (a == 169 && b == 254) || (a == 172 && b >= 16 && b < 32) ||
                (a == 192 && b == 168) || (a == 192 && b == 0 && ip[2] == 0) || (a == 198 && (b == 18 || b == 19));
        }
        bool null10 = true;
        for (int i = 0; i < 10; i++) null10 = null10 && ip[i] == 0;
        if (null10) return true;   // ::, ::1, ::ffff:… (eingebettetes IPv4)
        return (ip[0] & 0xFE) == 0xFC || (ip[0] == 0xFE && (ip[1] & 0xC0) == 0x80) || ip[0] == 0xFF;
    }

    // Ein Test-Angebot für den Testbetrieb ohne WebRTC: ein Heimnetz-Kandidat (muss rausfliegen) und
    // einer mit öffentlicher Adresse aus dem Dokumentationsbereich 203.0.113.0/24.
    public static string TestAngebot(bool gastgeber) {
        var fp = new StringBuilder();
        byte[] z = UzKrypto.Zufall(48);
        for (int i = 0; i < 32; i++) fp.Append(i > 0 ? ":" : "").Append(z[i].ToString("X2"));
        string ufrag = UzNostr.Hex(UzKrypto.Teil(z, 32, 4)), pwd = UzNostr.Hex(UzKrypto.Teil(z, 36, 12));
        return "v=0\r\no=- 4611731400430051336 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n" +
            "c=IN IP4 0.0.0.0\r\na=ice-ufrag:" + ufrag + "\r\na=ice-pwd:" + pwd + "\r\na=fingerprint:sha-256 " + fp + "\r\na=setup:" + (gastgeber ? "active" : "actpass") +
            "\r\na=mid:0\r\na=sctp-port:5000\r\na=max-message-size:262144\r\na=candidate:1 1 UDP 2122317823 192.168.1.20 50000 typ host\r\n" +
            "a=candidate:2 1 UDP 1686052607 203.0.113.7 50001 typ srflx raddr 192.168.1.20 rport 50000\r\na=end-of-candidates\r\n";
    }
}

// Token-Eimer (Menge je Sekunde, Vorrat). jetzt in Sekunden.
public sealed class UzEimer {
    readonly double rate, vorrat;
    double stand, zuletzt = -1;

    public UzEimer(double rate, double vorrat) { this.rate = rate; this.vorrat = vorrat; stand = vorrat; }

    public bool Nehmen(double jetzt) {
        if (zuletzt < 0) zuletzt = jetzt;
        stand = Math.Min(vorrat, stand + Math.Min(60.0, Math.Max(0.0, jetzt - zuletzt)) * rate);
        zuletzt = Math.Max(zuletzt, jetzt);
        if (stand < 1.0) return false;
        stand -= 1.0;
        return true;
    }
}

// Der Treffpunkt als reine Zustandsmaschine (ohne Netz, ohne Faden – testbar):
//   Gast:      klopft mit seinem Wegwerf-Schlüssel (ECDH) an, versiegelt mit dem Link-Schlüssel S.
//   Gastgeber: öffnet, prüft Zeit und Wiederholung, meldet Uzai „klopft“ (Kennung + Fingerabdruck),
//              antwortet erst nach Uzais Annahme mit seinem Wegwerf-Schlüssel (versiegelt mit S).
//   Beide:     Sitzungsschlüssel = SHA-256("UZ1-sitzung" | ECDH | Kennung | S | Gast | Gastgeber);
//              ab dann nur noch damit: Verbindungsangebote (SDP, geprüft) mit Zählern.
// Wer S nicht kennt, bekommt nichts geöffnet; wer S aus einem abgefangenen Link hat, aber nicht
// angenommen wird, sieht keine Sitzung (und keine IP-Adresse).
// Kiste: Fassung 1 | Typ | [8 Byte Gast-Fingerabdruck bei Typ 3/4] | Nonce | Geheimtext | Tag;
// Zusatzdaten (AAD): „UZ1“ | Typ | Kennung | [Fingerabdruck]. So passt keine Kiste in ein anderes
// Postfach, eine andere Richtung oder eine andere Sitzung.
public sealed class UzTreff {
    public const int MAX_FAECHER = 16, MAX_WARTEND = 8, MAX_JE_FACH = 4, KLOPFEN_ALLE = 15, KLOPFEN_MAX = 8, MAX_SIGNALE = 32, MAX_GESEHEN = 4096;
    public const byte T_KLOPFEN = 1, T_ANNAHME = 2, T_SIGNAL_GAST = 3, T_SIGNAL_WIRT = 4;
    public const byte S_ANGEBOT = 1, S_ANTWORT = 2, S_ENDE = 3;
    public const byte ST_RELAYS = 1, ST_ANGENOMMEN = 2, ST_KEINE_ANTWORT = 3, ST_KRYPTO_FEHLT = 4, ST_SIGNATUR_FEHLT = 5, ST_VERBUNDEN = 6, ST_ZU = 7;
    // Direktverbindung kam nicht zustande (ICE/DTLS gescheitert, Zeit um) bzw. WebRTC-Bibliothek fehlt.
    public const byte ST_GESCHEITERT = 8, ST_DIREKT_FEHLT = 9;
    public const int Z_GESEHEN = 0, Z_UNSINN = 1, Z_KRYPTO = 2, Z_WIEDERHOLT = 3, Z_GEDROSSELT = 4, Z_RELAY = 5;
    public const string ABO = "uz";
    static readonly byte[] KDF = Encoding.ASCII.GetBytes("UZ1-sitzung");
    static readonly byte[] AAD = Encoding.ASCII.GetBytes("UZ1");

    // Zu: zurückgezogen oder benutzt – niemand kann mehr anklopfen, laufende Sitzungen gehen weiter.
    sealed class Fach { public byte[] K, S; public string Z; public bool Zu; public UzNostr.Signierer Wegwerf; public UzEimer Eimer = new UzEimer(5, 30); }
    sealed class Besuch {
        public Fach F; public byte[] Pub, G8; public UzKrypto.Dh Dh; public byte[] K; public int Platz = -1;
        public uint SeqEin, SeqAus; public bool Verbunden, SdpDa; public int Signale, Versuche, Warte; public long Seit, Naechstes;
    }

    public readonly bool Gastgeber, Test;
    public readonly uint[] Zaehler = new uint[6];
    public bool An;
    readonly Func<long> unix;
    readonly Func<double> uhr;
    readonly Action<byte, byte[]> zuUzai;
    readonly Action<int, string> zuRelay;
    UzNostr.Signierer echt;
    bool sigPruefen;
    // WebRTC (libdatachannel); null = ohne (nur im Testbetrieb: dann ein Test-Angebot statt echter Verbindung).
    public IUzDirekt Direkt;
    bool[] relayDa = new bool[0];
    UzEimer[] relayEimer = new UzEimer[0];
    readonly Dictionary<string, Fach> faecher = new Dictionary<string, Fach>();
    readonly Dictionary<string, Besuch> besuche = new Dictionary<string, Besuch>();
    readonly HashSet<string> abgewiesen = new HashSet<string>();
    readonly Dictionary<string, long> gesehen = new Dictionary<string, long>();
    readonly HashSet<string> eigene = new HashSet<string>();
    Besuch ich;

    public UzTreff(bool gastgeber, bool test, Func<long> unix, Func<double> uhr, Action<byte, byte[]> zuUzai, Action<int, string> zuRelay) {
        Gastgeber = gastgeber; Test = test; this.unix = unix; this.uhr = uhr; this.zuUzai = zuUzai; this.zuRelay = zuRelay;
    }

    // Start: Adressen der Relays (leer = keine Verbindung; der Grund ging als STAND an Uzai).
    // port 0 = die festen Relays (braucht echte Signaturen), sonst nur mit „--test“ 127.0.0.1:port.
    public string[] Start(int port) {
        if (!UzKrypto.Selbsttest()) { Stand(ST_KRYPTO_FEHLT, 0, 0); return new string[0]; }
        // Mit libsecp256k1 signiert jedes Postfach mit eigenem Wegwerf-Schlüssel, und fremde Signaturen werden geprüft.
        sigPruefen = UzSecp.Bereit();
        string[] urls;
        if (port == 0) {
            echt = UzNostr.EchterSignierer();
            if (echt == null) { Stand(ST_SIGNATUR_FEHLT, 0, 0); return new string[0]; }
            if (Direkt == null) { Stand(ST_DIREKT_FEHLT, 0, 0); return new string[0]; }
            urls = UzNostr.RELAYS;
        } else {
            if (!Test) return new string[0];
            urls = new string[] { "ws://127.0.0.1:" + port.ToString(System.Globalization.CultureInfo.InvariantCulture) + "/" };
        }
        relayDa = new bool[urls.Length];
        relayEimer = new UzEimer[urls.Length];
        // Je Relay großzügig: gezählt werden hier auch fremde Ereignisse (vor jeder Prüfung). Eine Signaturprüfung kostet
        // Mikrosekunden – bei 20 je Sekunde hätte ein Dritter mit wenig Aufwand auch die echten Nachrichten verdrängt.
        for (int i = 0; i < urls.Length; i++) relayEimer[i] = new UzEimer(200, 400);
        An = true;
        Stand(ST_RELAYS, 0, (byte)urls.Length);
        return urls;
    }

    // Je Postfach ein eigener Wegwerf-Schlüssel; ohne Bibliothek (nur Testbetrieb) ein Test-Name ohne echte Signatur.
    UzNostr.Signierer NeuerSignierer() {
        if (sigPruefen) { UzNostr.Signierer e = UzNostr.EchterSignierer(); if (e != null) return e; }
        return Test ? new UzNostr.TestSignierer() : null;
    }

    void Stand(byte code, byte a, byte b) { zuUzai(UzNetzRahmen.STAND, new byte[] { code, a, b }); }

    static string H(byte[] b) { return UzNostr.Hex(b); }

    // Passt ein Befehl von Uzai in Form und Rolle? (Sonst beendet die Sandbox die Leitung.)
    public static bool BefehlOk(byte art, byte[] n, bool gastgeber) {
        switch (art) {
            case UzNetzRahmen.TREFF: return n.Length == 2;
            case UzNetzRahmen.EINLADUNG: return gastgeber && n.Length == 48;
            case UzNetzRahmen.ZURUECK: return gastgeber && n.Length == 16;
            case UzNetzRahmen.BESUCH: return !gastgeber && n.Length == 48;
            case UzNetzRahmen.ENTSCHEID: return gastgeber && n.Length == 9 && (n[8] < UzaiZimmerNetz.SLOTS || n[8] == 0xFF);
            case UzNetzRahmen.TREFF_ZAEHLER: return n.Length == 0;
            case UzNetzRahmen.SCHLIESSEN: return n.Length == 1;
        }
        return false;
    }

    public void Befehl(byte art, byte[] n) {
        if (!An && art != UzNetzRahmen.TREFF_ZAEHLER) return;
        switch (art) {
            case UzNetzRahmen.EINLADUNG: {
                var f = new Fach();
                f.K = UzKrypto.Teil(n, 0, 16); f.S = UzKrypto.Teil(n, 16, 32); f.Z = H(f.K); f.Wegwerf = NeuerSignierer();
                if (faecher.ContainsKey(f.Z) || faecher.Count >= MAX_FAECHER) return;
                faecher[f.Z] = f;
                Abo(-1);
                break;
            }
            case UzNetzRahmen.ZURUECK: {
                Fach f;
                if (!faecher.TryGetValue(H(n), out f)) return;
                f.Zu = true;
                foreach (var k in new List<string>(besuche.Keys)) if (besuche[k].F == f && besuche[k].Platz < 0) Weg(k);
                Aufraeumen(f);
                break;
            }
            case UzNetzRahmen.BESUCH: {
                if (ich != null) return;
                var f = new Fach();
                f.K = UzKrypto.Teil(n, 0, 16); f.S = UzKrypto.Teil(n, 16, 32); f.Z = H(f.K); f.Wegwerf = NeuerSignierer();
                faecher.Clear();
                faecher[f.Z] = f;
                ich = new Besuch();
                ich.F = f; ich.Dh = new UzKrypto.Dh(); ich.Pub = ich.Dh.Oeffentlich(); ich.G8 = UzKrypto.Teil(UzKrypto.Sha256(ich.Pub), 0, 8);
                ich.Naechstes = unix();
                Abo(-1);
                Takt();
                break;
            }
            case UzNetzRahmen.ENTSCHEID: {
                string g = H(UzKrypto.Teil(n, 0, 8));
                Besuch b;
                if (!besuche.TryGetValue(g, out b) || b.K != null) return;
                if (n[8] == 0xFF) { abgewiesen.Add(g); Weg(g); return; }
                foreach (var x in besuche.Values) if (x.Platz == n[8]) return;
                b.Dh = new UzKrypto.Dh();
                byte[] eigen = b.Dh.Oeffentlich();
                b.K = b.Dh.Teilen(b.Pub, KDF, UzKrypto.Kette(b.F.K, b.F.S, b.Pub, eigen));
                if (b.K == null) { Weg(g); return; }
                b.Platz = n[8];
                b.Seit = unix();
                byte[] klar = UzKrypto.Kette(eigen, UzKrypto.Teil(UzKrypto.Sha256(b.Pub), 0, 16), Zeit(unix()));
                Senden(b.F, T_ANNAHME, null, b.F.S, klar);
                break;
            }
            case UzNetzRahmen.SCHLIESSEN: {
                foreach (var k in new List<string>(besuche.Keys)) {
                    var b = besuche[k];
                    if (b.Platz != n[0]) continue;
                    Signal(b, T_SIGNAL_WIRT, S_ENDE, new byte[0]);
                    Weg(k);
                }
                break;
            }
            case UzNetzRahmen.TREFF_ZAEHLER: {
                var o = new byte[24];
                for (int i = 0; i < 6; i++) for (int k = 0; k < 4; k++) o[i * 4 + k] = (byte)(Zaehler[i] >> (8 * k));
                zuUzai(UzNetzRahmen.TREFF_ZAEHLER, o);
                break;
            }
        }
    }

    void Weg(string g) {
        Besuch b;
        if (!besuche.TryGetValue(g, out b)) return;
        if (b.Dh != null) b.Dh.Dispose();
        if (b.Platz >= 0 && Direkt != null) Direkt.Weg(b.Platz);
        besuche.Remove(g);
        Aufraeumen(b.F);
    }

    // Ein zugemachtes Postfach ohne laufende Sitzung verschwindet ganz (auch aus dem Abo).
    void Aufraeumen(Fach f) {
        if (!f.Zu || !faecher.ContainsKey(f.Z)) return;
        foreach (var x in besuche.Values) if (x.F == f) return;
        faecher.Remove(f.Z);
        if (faecher.Count > 0) Abo(-1);
        else zuRelay(-1, "[\"CLOSE\",\"" + ABO + "\"]");
    }

    static byte[] Zeit(long t) {
        var b = new byte[8];
        for (int i = 0; i < 8; i++) b[i] = (byte)(t >> (8 * i));
        return b;
    }

    static long ZeitLesen(byte[] b, int o) {
        long t = 0;
        for (int i = 7; i >= 0; i--) t = (t << 8) | b[o + i];
        return t;
    }

    bool Frisch(long t) { long d = unix() - t; return d <= UzNostr.FENSTER && d >= -UzNostr.FENSTER; }

    void Abo(int relay) {
        if (faecher.Count == 0) return;
        zuRelay(relay, UzNostr.Abo(ABO, new List<string>(faecher.Keys), unix() - UzNostr.FENSTER));
    }

    public void RelayDa(int r, bool da) {
        if (r < 0 || r >= relayDa.Length || relayDa[r] == da) return;
        relayDa[r] = da;
        if (da) Abo(r);
        else Zaehler[Z_RELAY]++;
        int n = 0;
        foreach (bool x in relayDa) if (x) n++;
        Stand(ST_RELAYS, (byte)n, (byte)relayDa.Length);
        if (da) Takt();
    }

    bool IrgendeinRelay() { foreach (bool x in relayDa) if (x) return true; return false; }

    void Senden(Fach f, byte typ, byte[] g8, byte[] schluessel, byte[] klar) {
        byte[] aad = UzKrypto.Kette(AAD, new byte[] { typ }, f.K, g8 ?? new byte[0]);
        byte[] zu = UzKrypto.Zu(schluessel, aad, klar);
        if (zu == null) return;
        string inhalt = Convert.ToBase64String(UzKrypto.Kette(new byte[] { 1, typ }, g8 ?? new byte[0], zu));
        string id;
        string text = UzNostr.Ereignis(f.Wegwerf, unix(), f.Z, inhalt, out id);
        if (text == null) return;
        if (eigene.Count > MAX_GESEHEN) eigene.Clear();
        eigene.Add(id);
        zuRelay(-1, text);
    }

    void Signal(Besuch b, byte typ, byte art, byte[] daten) {
        if (b.K == null) return;
        b.SeqAus++;
        var kopf = new byte[15];
        for (int i = 0; i < 4; i++) kopf[i] = (byte)(b.SeqAus >> (8 * i));
        Buffer.BlockCopy(Zeit(unix()), 0, kopf, 4, 8);
        kopf[12] = art;
        kopf[13] = (byte)daten.Length; kopf[14] = (byte)(daten.Length >> 8);
        Senden(b.F, typ, b.G8, b.K, UzKrypto.Kette(kopf, daten));
    }

    // Uhr: Gast klopft alle 15 s erneut (höchstens 8-mal), alte Einträge verfallen.
    public void Takt() {
        long jetzt = unix();
        if (gesehen.Count > MAX_GESEHEN / 2) {
            foreach (var k in new List<string>(gesehen.Keys)) if (jetzt - gesehen[k] > 2 * UzNostr.FENSTER) gesehen.Remove(k);
        }
        foreach (var k in new List<string>(besuche.Keys)) if (besuche[k].K == null && jetzt - besuche[k].Seit > 10 * 60) Weg(k);
        if (!Gastgeber && ich != null && ich.K == null && IrgendeinRelay() && jetzt >= ich.Naechstes) {
            if (ich.Versuche >= KLOPFEN_MAX) { Stand(ST_KEINE_ANTWORT, 0, 0); IchWeg(); return; }
            ich.Versuche++;
            ich.Naechstes = jetzt + KLOPFEN_ALLE;
            Senden(ich.F, T_KLOPFEN, null, ich.F.S, UzKrypto.Kette(ich.Pub, Zeit(jetzt), UzKrypto.Zufall(16)));
        }
        if (Direkt == null) return;
        if (!Gastgeber && ich != null && ich.K != null) Pflegen(ich, 0);
        if (Gastgeber) foreach (var k in new List<string>(besuche.Keys)) { Besuch b; if (besuche.TryGetValue(k, out b) && b.K != null && b.Platz >= 0) Pflegen(b, b.Platz); }
    }

    // Direktverbindung einer Sitzung: eigenes Angebot bzw. Antwort (geprüft, versiegelt) verschicken, sobald die
    // Kandidaten gesammelt sind; „verbunden“ erst, wenn der Kanal offen ist; gescheitert → Sitzung zu.
    void Pflegen(Besuch b, int platz) {
        if (b.Warte == 1) {
            string l = Direkt.Lokal(platz);
            if (l != null) {
                string p = UzSdp.Pruefen(l, Test);
                if (p == null) { Scheitern(b); return; }
                Signal(b, Gastgeber ? T_SIGNAL_WIRT : T_SIGNAL_GAST, Gastgeber ? S_ANTWORT : S_ANGEBOT, Encoding.ASCII.GetBytes(p));
                b.Warte = 2;
            }
        }
        int z = Direkt.Zustand(platz);
        if (z == 1 && !b.Verbunden) { b.Verbunden = true; Stand(ST_VERBUNDEN, (byte)platz, 0); }
        else if (z == 2) Scheitern(b);
    }

    void Scheitern(Besuch b) {
        bool war = b.Verbunden;
        Signal(b, Gastgeber ? T_SIGNAL_WIRT : T_SIGNAL_GAST, S_ENDE, new byte[0]);
        if (Gastgeber) { Stand(war ? ST_ZU : ST_GESCHEITERT, (byte)b.Platz, 0); Weg(H(b.G8)); }
        else { Stand(war ? ST_ZU : ST_GESCHEITERT, 0, 0); IchWeg(); }
    }

    void IchWeg() {
        if (ich != null && ich.Dh != null) ich.Dh.Dispose();
        ich = null;
        if (Direkt != null) Direkt.Weg(0);
    }

    bool Neu(string schluessel) {
        if (gesehen.ContainsKey(schluessel)) { Zaehler[Z_WIEDERHOLT]++; return false; }
        if (gesehen.Count >= MAX_GESEHEN) { Zaehler[Z_GEDROSSELT]++; return false; }
        gesehen[schluessel] = unix();
        return true;
    }

    // Eine Nachricht eines Relays. Alles, was nicht genau passt, wird gezählt und vergessen.
    public void VomRelay(int r, string text) {
        if (!An || r < 0 || r >= relayEimer.Length) return;
        if (!relayEimer[r].Nehmen(uhr())) { Zaehler[Z_GEDROSSELT]++; return; }
        bool still;
        UzNostr.Ein e = UzNostr.Lesen(text, ABO, out still);
        if (e == null) { if (!still) Zaehler[Z_UNSINN]++; return; }
        if (eigene.Contains(e.Id)) return;
        Zaehler[Z_GESEHEN]++;
        Fach f;
        if (!faecher.TryGetValue(e.Z, out f) || e.Zeit < unix() - 2 * UzNostr.FENSTER || e.Zeit > unix() + UzNostr.FENSTER) { Zaehler[Z_UNSINN]++; return; }
        // BIP-340: ein Ereignis mit falscher Signatur ist gefälscht (kommt nie bis zur Entschlüsselung).
        if (sigPruefen && !UzNostr.SignaturOk(e)) { Zaehler[Z_KRYPTO]++; return; }
        // Wiederholungsschutz und Drossel des Postfachs zählen erst NACH dem Entschlüsseln (unten): Das Postfach ist
        // öffentlich sichtbar, signieren kann jeder mit eigenem Schlüssel – zählten fremde Ereignisse mit, füllte ein
        // Dritter ohne Einladung „gesehen“ und den Eimer und brachte jeden Besuchsaufbau zum Scheitern.
        if (gesehen.ContainsKey("e" + e.Id)) { Zaehler[Z_WIEDERHOLT]++; return; }
        byte[] b = UzNostr.B64Lesen(e.Inhalt);
        if (b == null || b.Length < 2 || b[0] != 1) { Zaehler[Z_UNSINN]++; return; }
        byte typ = b[1];
        bool erwartet = Gastgeber ? (typ == T_KLOPFEN || typ == T_SIGNAL_GAST) : (typ == T_ANNAHME || typ == T_SIGNAL_WIRT);
        if (!erwartet) { Zaehler[Z_UNSINN]++; return; }
        bool signal = typ == T_SIGNAL_GAST || typ == T_SIGNAL_WIRT;
        byte[] g8 = signal ? UzKrypto.Teil(b, 2, 8) : new byte[0];
        if (g8 == null) { Zaehler[Z_UNSINN]++; return; }
        byte[] kiste = UzKrypto.Teil(b, 2 + g8.Length, b.Length - 2 - g8.Length);
        byte[] aad = UzKrypto.Kette(AAD, new byte[] { typ }, f.K, g8);
        Besuch sitzung = null;
        if (signal) {
            if (Gastgeber) besuche.TryGetValue(H(g8), out sitzung);
            else if (ich != null && UzKrypto.Gleich(ich.G8, g8)) sitzung = ich;
            if (sitzung == null || sitzung.K == null || sitzung.F != f) { Zaehler[Z_UNSINN]++; return; }
        }
        byte[] klar = UzKrypto.Auf(signal ? sitzung.K : f.S, aad, kiste);
        if (klar == null) { Zaehler[Z_KRYPTO]++; return; }
        if (!Neu("e" + e.Id)) return;
        if (!f.Eimer.Nehmen(uhr())) { Zaehler[Z_GEDROSSELT]++; return; }
        switch (typ) {
            case T_KLOPFEN: Klopfen(f, klar); break;
            case T_ANNAHME: Annahme(f, klar); break;
            default: SignalEin(sitzung, klar); break;
        }
    }

    void Klopfen(Fach f, byte[] klar) {
        if (klar.Length != UzKrypto.PUB + 24 || klar[0] != 4 || !Frisch(ZeitLesen(klar, UzKrypto.PUB))) { Zaehler[Z_UNSINN]++; return; }
        if (!Neu("k" + H(UzKrypto.Teil(klar, UzKrypto.PUB + 8, 16)))) return;
        byte[] pub = UzKrypto.Teil(klar, 0, UzKrypto.PUB);
        if (!UzKrypto.PunktOk(pub)) { Zaehler[Z_KRYPTO]++; return; }
        byte[] g8 = UzKrypto.Teil(UzKrypto.Sha256(pub), 0, 8);
        string g = H(g8);
        if (f.Zu || besuche.ContainsKey(g) || abgewiesen.Contains(g)) return;   // Postfach zu, oder derselbe Gast klopft erneut
        int wartend = 0, imFach = 0;
        foreach (var x in besuche.Values) {
            if (x.K == null) wartend++;
            if (x.F == f) imFach++;
        }
        if (wartend >= MAX_WARTEND || imFach >= MAX_JE_FACH) { Zaehler[Z_GEDROSSELT]++; return; }
        var b = new Besuch();
        b.F = f; b.Pub = pub; b.G8 = g8; b.Seit = unix();
        besuche[g] = b;
        zuUzai(UzNetzRahmen.KLOPFT, UzKrypto.Kette(f.K, g8));
    }

    void Annahme(Fach f, byte[] klar) {
        if (ich == null || ich.K != null || ich.F != f) return;
        if (klar.Length != UzKrypto.PUB + 24 || klar[0] != 4 || !Frisch(ZeitLesen(klar, UzKrypto.PUB + 16))) { Zaehler[Z_UNSINN]++; return; }
        if (!UzKrypto.Gleich(UzKrypto.Teil(klar, UzKrypto.PUB, 16), UzKrypto.Teil(UzKrypto.Sha256(ich.Pub), 0, 16))) { Zaehler[Z_UNSINN]++; return; }
        byte[] wirt = UzKrypto.Teil(klar, 0, UzKrypto.PUB);
        byte[] k = ich.Dh.Teilen(wirt, KDF, UzKrypto.Kette(f.K, f.S, ich.Pub, wirt));
        if (k == null) { Zaehler[Z_KRYPTO]++; return; }
        ich.K = k;
        ich.Platz = 0;
        Stand(ST_ANGENOMMEN, 0, 0);
        // Erst jetzt entsteht die Direktverbindung (und mit dem Angebot die eigene Adresse); Angebot im Takt.
        if (Direkt != null) {
            if (Direkt.Neu(0, true)) ich.Warte = 1;
            else Scheitern(ich);
            return;
        }
        // Ohne WebRTC-Bibliothek (nur „--test“) ein Test-Angebot.
        string sdp = UzSdp.Pruefen(UzSdp.TestAngebot(false), false);
        if (sdp != null) Signal(ich, T_SIGNAL_GAST, S_ANGEBOT, Encoding.ASCII.GetBytes(sdp));
    }

    void SignalEin(Besuch b, byte[] klar) {
        if (klar.Length < 15) { Zaehler[Z_UNSINN]++; return; }
        uint seq = (uint)(klar[0] | (klar[1] << 8) | (klar[2] << 16) | (klar[3] << 24));
        int n = klar[13] | (klar[14] << 8);
        byte art = klar[12];
        if (seq <= b.SeqEin || n != klar.Length - 15 || n > UzSdp.MAX || !Frisch(ZeitLesen(klar, 4)) || ++b.Signale > MAX_SIGNALE) { Zaehler[Z_WIEDERHOLT]++; return; }
        b.SeqEin = seq;
        if (art == S_ENDE && n == 0) {
            if (Gastgeber) { Stand(ST_ZU, (byte)b.Platz, 0); Weg(H(b.G8)); }
            else { Stand(ST_ZU, 0, 0); IchWeg(); }
            return;
        }
        // Genau ein Angebot und eine Antwort je Sitzung, beide durch den SDP-Prüfer (Heimnetz-Adressen nur im Test).
        bool passt = Gastgeber ? art == S_ANGEBOT && !b.SdpDa : art == S_ANTWORT && !b.SdpDa;
        string sdp = passt ? UzSdp.Pruefen(Encoding.ASCII.GetString(klar, 15, n), Test && Direkt != null) : null;
        if (sdp == null) { Zaehler[Z_UNSINN]++; return; }
        b.SdpDa = true;
        if (Direkt != null) {
            bool ok = Gastgeber ? Direkt.Neu(b.Platz, false) && Direkt.Fern(b.Platz, sdp, true) : Direkt.Fern(0, sdp, false);
            if (!ok) { Scheitern(b); return; }
            if (Gastgeber) b.Warte = 1;
            return;
        }
        b.Verbunden = true;
        if (Gastgeber) {
            string antwort = UzSdp.Pruefen(UzSdp.TestAngebot(true), false);
            if (antwort != null) Signal(b, T_SIGNAL_WIRT, S_ANTWORT, Encoding.ASCII.GetBytes(antwort));
        }
        Stand(ST_VERBUNDEN, (byte)b.Platz, 0);
    }
}

// Die Verbindungen zu den Relays (je eine eigene WebSocket-Verbindung mit Faden). Nur ausgehend;
// eine Nachricht über 16 KiB, ein Binär-Rahmen oder kaputtes UTF-8 beendet die Verbindung; danach
// mit wachsender Pause neu. Gesendet wird nur, was der Treffpunkt gebaut hat.
public sealed class UzRelays {
    readonly string[] urls;
    readonly System.Net.WebSockets.ClientWebSocket[] ws;
    readonly object[] tore;
    readonly Action<int, string> text;
    readonly Action<int, bool> da;
    volatile bool aus;

    public UzRelays(string[] urls, Action<int, string> text, Action<int, bool> da) {
        this.urls = urls; this.text = text; this.da = da;
        ws = new System.Net.WebSockets.ClientWebSocket[urls.Length];
        tore = new object[urls.Length];
        for (int i = 0; i < urls.Length; i++) tore[i] = new object();
    }

    public void Start() {
        for (int i = 0; i < urls.Length; i++) {
            int r = i;
            var t = new Thread(delegate () { Schleife(r); });
            t.IsBackground = true;
            t.Start();
        }
    }

    void Schleife(int i) {
        int pause = 2000;
        var utf8 = new UTF8Encoding(false, true);
        while (!aus) {
            var w = new System.Net.WebSockets.ClientWebSocket();
            bool war = false;
            try {
                var u = new Uri(urls[i]);
                if (u.Scheme == "ws") w.Options.Proxy = null;   // nur das Test-Relay auf 127.0.0.1
                w.Options.KeepAliveInterval = TimeSpan.FromSeconds(30);
                if (!w.ConnectAsync(u, CancellationToken.None).Wait(10000)) throw new TimeoutException();
                lock (tore[i]) ws[i] = w;
                war = true;
                da(i, true);
                pause = 2000;
                var puffer = new byte[UzJson.MAX_TEXT];
                while (!aus && w.State == System.Net.WebSockets.WebSocketState.Open) {
                    int n = 0;
                    System.Net.WebSockets.WebSocketReceiveResult r;
                    do {
                        if (n >= puffer.Length) throw new InvalidDataException();
                        r = w.ReceiveAsync(new ArraySegment<byte>(puffer, n, puffer.Length - n), CancellationToken.None).Result;
                        if (r.MessageType != System.Net.WebSockets.WebSocketMessageType.Text) throw new InvalidDataException();
                        n += r.Count;
                    } while (!r.EndOfMessage);
                    text(i, utf8.GetString(puffer, 0, n));
                }
            } catch { }
            lock (tore[i]) ws[i] = null;
            try { w.Abort(); w.Dispose(); } catch { }
            if (war) da(i, false);
            for (int k = 0; k < pause / 100 && !aus; k++) Thread.Sleep(100);
            pause = Math.Min(pause * 2, 60000);
        }
    }

    // An ein Relay (r) oder an alle (-1).
    public void Senden(int r, string s) {
        byte[] b = Encoding.UTF8.GetBytes(s);
        for (int i = 0; i < urls.Length; i++) {
            if (r >= 0 && i != r) continue;
            lock (tore[i]) {
                var w = ws[i];
                if (w == null || w.State != System.Net.WebSockets.WebSocketState.Open) continue;
                try { w.SendAsync(new ArraySegment<byte>(b), System.Net.WebSockets.WebSocketMessageType.Text, true, CancellationToken.None).Wait(5000); } catch { }
            }
        }
    }

    public void Stop() {
        aus = true;
        for (int i = 0; i < urls.Length; i++) {
            lock (tore[i]) { if (ws[i] != null) try { ws[i].Abort(); } catch { } }
        }
    }
}

// Treffpunkt im Betrieb: ein Faden, eine Warteschlange (begrenzt). Befehle von Uzai, Nachrichten
// der Relays und der Takt laufen nacheinander durch die Zustandsmaschine – kein geteilter Zustand.
public sealed class UzTreffBetrieb {
    readonly System.Collections.Concurrent.BlockingCollection<object[]> q = new System.Collections.Concurrent.BlockingCollection<object[]>(2048);
    readonly UzTreff treff;
    readonly bool gastgeber, test;
    readonly Action<int, byte[]> kanalEin;
    UzRelays netz;
    Thread faden;
    volatile bool aus;
    // Die Direktverbindungen (null ohne WebRTC-Bibliothek); Senden darf der Leitungs-Faden.
    public UzDirekt Direkt;

    public UzTreffBetrieb(bool gastgeber, bool test, Stream ausStrom, Action<int, byte[]> kanalEin) {
        this.gastgeber = gastgeber; this.test = test; this.kanalEin = kanalEin;
        var uhr = Stopwatch.StartNew();
        treff = new UzTreff(gastgeber, test, delegate { return DateTimeOffset.UtcNow.ToUnixTimeSeconds(); }, delegate { return uhr.Elapsed.TotalSeconds; },
            delegate (byte art, byte[] nutz) { UzNetzRahmen.Schreiben(ausStrom, art, nutz); },
            delegate (int r, string s) { if (netz != null) netz.Senden(r, s); });
    }

    // Der Start selbst (Selbsttest, Stand an Uzai) läuft sofort; Relays und Takt dann im eigenen Faden.
    public void Start(int port) {
        if (UzRtc.Bereit()) Direkt = new UzDirekt(gastgeber ? UzaiZimmerNetz.SLOTS : 1, test);
        treff.Direkt = Direkt;
        string[] urls = treff.Start(port);
        if (urls.Length > 0) netz = new UzRelays(urls, delegate (int r, string s) { q.TryAdd(new object[] { 1, r, s }); }, delegate (int r, bool d) { q.TryAdd(new object[] { 2, r, d }); });
        faden = new Thread(Schleife);
        faden.IsBackground = true;
        faden.Start();
    }

    void Schleife() {
        if (netz != null) netz.Start();
        while (!aus) {
            object[] e;
            // Ein Fehler bei einer einzelnen Nachricht beendet nicht den Treffpunkt (gezählt als Unsinn).
            try {
                // Mit offener Direktverbindung kurz takten (Nachrichten abholen), sonst gemächlich.
                if (q.TryTake(out e, Direkt != null && Direkt.Aktiv() ? 10 : 250)) {
                    switch ((int)e[0]) {
                        case 0: treff.Befehl((byte)e[1], (byte[])e[2]); break;
                        case 1: treff.VomRelay((int)e[1], (string)e[2]); break;
                        case 2: treff.RelayDa((int)e[1], (bool)e[2]); break;
                    }
                }
                treff.Takt();
                if (Direkt != null) Direkt.Pumpen(kanalEin);
            } catch (Exception) { treff.Zaehler[UzTreff.Z_UNSINN]++; }
        }
        if (netz != null) netz.Stop();
        if (Direkt != null) Direkt.Stop();
    }

    public void Befehl(byte art, byte[] nutz) { q.TryAdd(new object[] { 0, art, nutz }, 1000); }

    // Ende: Relays zu, Direktverbindungen zu (im eigenen Faden, mit Zeitgrenze).
    public void Stop() {
        aus = true;
        if (netz != null) netz.Stop();
        if (faden != null) faden.Join(5000);
    }
}

// Der Helfer-Teil: AppContainer anlegen, Programm darin starten, Echo und Selbsttest prüfen
// (Probe) bzw. eine Sitzung mit Uzais Leitung führen (Sitzung).
public static class UzZimmerNetz {
    public const string Version = "5";
    public const string Container = "Uzai.ZimmerNetz";
    public const string InternetClient = "S-1-15-3-1";      // einzige Fähigkeit: ausgehend ins Internet
    public const int ATTR_HANDLE_LIST = 0x20002;
    public const int ATTR_SECURITY_CAPABILITIES = 0x20009;
    public const int ATTR_CHILD_PROCESS_POLICY = 0x2000E;
    public const ulong SPEICHER = 256UL * 1024 * 1024;
    // „-echt“: ohne Testbetrieb (feste Relays, WebRTC); Uzai startet das nur mit dem Testschalter.
    public static readonly string[] Rollen = { "gastgeber", "gast", "gastgeber-echt", "gast-echt" };
    const int HR_ALREADY_EXISTS = unchecked((int)0x800700B7);
    // DETACHED_PROCESS statt „ohne Fenster“ (0x08000000): ohne Konsole. Sonst startet Windows für das Konsolenprogramm einen
    // Konsolen-Wirt (conhost) – der zählte im Job (höchstens ein Prozess) mit, und der Start brach mit 0xC0000142 ab
    // (Nutzer-PC 0.16.31). Die Leitung läuft ohnehin über die übergebenen Handles (STARTF_USESTDHANDLES).
    const uint EXTENDED_STARTUPINFO_PRESENT = 0x80000, CREATE_SUSPENDED = 0x4, DETACHED_PROCESS = 0x8, CREATE_UNICODE_ENVIRONMENT = 0x400;
    const uint SE_GROUP_ENABLED = 0x4;
    const uint GENERIC_READ = 0x80000000, GENERIC_EXECUTE = 0x20000000;
    const uint DUPLICATE_SAME_ACCESS = 2;

    [StructLayout(LayoutKind.Sequential)] public struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)] public struct SECURITY_CAPABILITIES { public IntPtr AppContainerSid; public IntPtr Capabilities; public uint CapabilityCount, Reserved; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)] public struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }
    [StructLayout(LayoutKind.Sequential)] public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [StructLayout(LayoutKind.Sequential)] public struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] public struct IO_COUNTERS { public ulong R, W, O, RB, WB, OB; }
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION Basic; public IO_COUNTERS Io;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    [StructLayout(LayoutKind.Sequential)] public struct TRUSTEE { public IntPtr pMultipleTrustee; public int MultipleTrusteeOperation, TrusteeForm, TrusteeType; public IntPtr ptstrName; }
    [StructLayout(LayoutKind.Sequential)] public struct EXPLICIT_ACCESS { public uint grfAccessPermissions; public int grfAccessMode; public uint grfInheritance; public TRUSTEE Trustee; }

    [DllImport("userenv.dll", CharSet = CharSet.Unicode)] static extern int CreateAppContainerProfile(string name, string display, string desc, IntPtr caps, uint count, out IntPtr sid);
    [DllImport("userenv.dll", CharSet = CharSet.Unicode)] static extern int DeriveAppContainerSidFromAppContainerName(string name, out IntPtr sid);
    [DllImport("userenv.dll", CharSet = CharSet.Unicode)] static extern int GetAppContainerFolderPath(string sid, out IntPtr path);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool ConvertSidToStringSidW(IntPtr sid, out IntPtr str);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool ConvertStringSidToSidW(string str, out IntPtr sid);
    [DllImport("advapi32.dll")] static extern IntPtr FreeSid(IntPtr sid);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern uint GetNamedSecurityInfoW(string name, int type, uint info, IntPtr owner, IntPtr group, out IntPtr dacl, IntPtr sacl, out IntPtr sd);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern uint SetEntriesInAclW(uint count, ref EXPLICIT_ACCESS ea, IntPtr old, out IntPtr neu);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern uint SetNamedSecurityInfoW(string name, int type, uint info, IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CreatePipe(out IntPtr r, out IntPtr w, ref SECURITY_ATTRIBUTES sa, int size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attr, IntPtr val, IntPtr size, IntPtr prev, IntPtr ret);
    [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref STARTUPINFOEX si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateJobObjectW(IntPtr sa, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool DuplicateHandle(IntPtr sp, IntPtr h, IntPtr tp, out IntPtr th, uint access, bool inherit, uint options);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr p);

    // Ergebnis einer Probe (ein Feld je Schritt; JSON für Uzai).
    public class Ergebnis {
        public bool Container, Echo, Ordner, LesenGesperrt, ListeGesperrt, SchreibenGesperrt, ProgrammGesperrt, Kindsperre, Sauber, Krypto;
        public int Secp, Rtc;      // UzNetzLib-Zustand in der Abschottung (1 = geladen, Prüfsumme und Selbsttest in Ordnung)
        public string Fehler = "";
        public long Ms;

        public bool Ok() {
            return Container && Echo && Ordner && LesenGesperrt && ListeGesperrt && SchreibenGesperrt && ProgrammGesperrt && Sauber && Fehler == "";
        }

        public string Json() {
            var sb = new StringBuilder("{");
            sb.Append("\"ok\":").Append(B(Ok()));
            sb.Append(",\"container\":").Append(B(Container));
            sb.Append(",\"echo\":").Append(B(Echo));
            sb.Append(",\"eigener_ordner\":").Append(B(Ordner));
            sb.Append(",\"uzai_daten_gesperrt\":").Append(B(LesenGesperrt));
            sb.Append(",\"profil_gesperrt\":").Append(B(ListeGesperrt));
            sb.Append(",\"temp_gesperrt\":").Append(B(SchreibenGesperrt));
            sb.Append(",\"programme_gesperrt\":").Append(B(ProgrammGesperrt));
            sb.Append(",\"kindsperre\":").Append(B(Kindsperre));
            sb.Append(",\"sauber_beendet\":").Append(B(Sauber));
            sb.Append(",\"krypto\":").Append(B(Krypto));
            sb.Append(",\"secp\":").Append(Secp);
            sb.Append(",\"rtc\":").Append(Rtc);
            sb.Append(",\"ms\":").Append(Ms);
            sb.Append(",\"fehler\":\"").Append(Bereinigt(Fehler)).Append("\"}");
            return sb.ToString();
        }

        static string B(bool b) { return b ? "true" : "false"; }
    }

    // Fehlertexte sind feste Wörter mit Zahlen; zur Sicherheit nur diese Zeichen.
    public static string Bereinigt(string s) {
        var sb = new StringBuilder();
        foreach (char c in s ?? "") if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == ' ' || c == ':') sb.Append(c);
        return sb.ToString();
    }

    // Antwort des Selbsttests („schlüssel=0/1“ je Zeile) in das Ergebnis übernehmen.
    public static void Auswerten(string antwort, Ergebnis e) {
        var kv = new Dictionary<string, string>();
        foreach (string z in (antwort ?? "").Split('\n')) {
            int i = z.IndexOf('=');
            if (i > 0 && Array.IndexOf(UzaiZimmerNetz.Proben, z.Substring(0, i)) >= 0) kv[z.Substring(0, i)] = z.Substring(i + 1);
        }
        e.Ordner = Ist(kv, "ordner", "1");
        e.LesenGesperrt = Ist(kv, "lesen", "0");
        e.ListeGesperrt = Ist(kv, "liste", "0");
        e.SchreibenGesperrt = Ist(kv, "schreiben", "0");
        e.ProgrammGesperrt = Ist(kv, "programm", "0");
        e.Krypto = Ist(kv, "krypto", "1");
        e.Secp = Zahl(kv, "secp");
        e.Rtc = Zahl(kv, "rtc");
    }

    static int Zahl(Dictionary<string, string> kv, string k) {
        string v;
        return kv.TryGetValue(k, out v) && v.Length == 1 && v[0] >= '0' && v[0] <= '5' ? v[0] - '0' : 0;
    }

    static bool Ist(Dictionary<string, string> kv, string k, string soll) {
        string v;
        return kv.TryGetValue(k, out v) && v == soll;
    }

    // Auftrag für den Selbsttest: eigener Ordner und drei Orte, an die der Container nicht darf.
    public static string Auftrag(string ordner, string lesen, string liste, string schreiben) {
        return "ordner=" + ordner + "\nlesen=" + lesen + "\nliste=" + liste + "\nschreiben=" + schreiben + "\n";
    }

    // Kleine, feste Umgebung für den Kindprozess (nichts vom Benutzer, keine Pfade außer dem eigenen). Windows
    // passt beim Start im AppContainer die Profil-Variablen an den Container an und bricht ohne sie mit 203
    // (ERROR_ENVVAR_NOT_FOUND) ab (Nutzer-PC 0.16.29) – darum stehen sie da, alle auf den eigenen leeren Ordner.
    // Nach Namen sortiert (ohne Groß/Klein), wie Windows es für den Block verlangt.
    public static string Umgebung(string systemRoot, string ordner) {
        return "APPDATA=" + ordner + "\0LOCALAPPDATA=" + ordner + "\0SystemRoot=" + systemRoot + "\0TEMP=" + ordner + "\0TMP=" + ordner +
            "\0USERPROFILE=" + ordner + "\0windir=" + systemRoot + "\0\0";
    }

    // Befehlszeile des Kindprozesses: nur diese festen Formen (kein Text von außen).
    public static string Befehl(string exe, string modus) {
        if (modus == "echo") return "\"" + exe + "\" --echo";
        if (modus == "gastgeber" || modus == "gast") return "\"" + exe + "\" --netz " + modus + " --test";
        if (modus == "gastgeber-echt" || modus == "gast-echt") return "\"" + exe + "\" --netz " + modus.Substring(0, modus.Length - 5);
        return null;
    }

    // Ein gestarteter Kindprozess: Prozess, Job-Objekt, eigener Container-Ordner.
    public class Kind {
        public PROCESS_INFORMATION Pi;
        public IntPtr Job;
        public bool Container, Kindsperre;
        public string Ordner = "";

        public void Schliessen() {
            if (Job != IntPtr.Zero) { TerminateJobObject(Job, 1); CloseHandle(Job); Job = IntPtr.Zero; }
            if (Pi.hProcess != IntPtr.Zero) { CloseHandle(Pi.hProcess); Pi.hProcess = IntPtr.Zero; }
            if (Pi.hThread != IntPtr.Zero) { CloseHandle(Pi.hThread); Pi.hThread = IntPtr.Zero; }
        }
    }

    // Startet exe im AppContainer (nur internetClient) in einem Job-Objekt; der Kindprozess erbt
    // genau die übergebenen Handles (Standardeingabe, -ausgabe, -fehler; null = keins). Ordner wird
    // vor dem Start bestimmt (für den Selbsttest). "" bei Erfolg, sonst ein fester Fehlertext.
    public static string Starten(string exe, string modus, IntPtr kindIn, IntPtr kindAus, IntPtr kindFehler, Kind k) {
        string befehl = Befehl(exe, modus);
        if (befehl == null) return "modus";
        IntPtr sid = IntPtr.Zero, cap = IntPtr.Zero, liste = IntPtr.Zero, scPtr = IntPtr.Zero, saPtr = IntPtr.Zero, hl = IntPtr.Zero, pol = IntPtr.Zero, env = IntPtr.Zero;
        try {
            int hr = CreateAppContainerProfile(Container, "Uzai Zimmer-Netz", "Abgeschotteter Netzwerk-Teil von Uzai", IntPtr.Zero, 0, out sid);
            if (hr == HR_ALREADY_EXISTS) hr = DeriveAppContainerSidFromAppContainerName(Container, out sid);
            if (hr != 0 || sid == IntPtr.Zero) return "container " + hr.ToString("x");
            IntPtr s;
            if (!ConvertSidToStringSidW(sid, out s)) return "sid " + Marshal.GetLastWin32Error();
            string sidText = Marshal.PtrToStringUni(s);
            LocalFree(s);
            IntPtr fp;
            if (GetAppContainerFolderPath(sidText, out fp) != 0) return "ordner";
            k.Ordner = Marshal.PtrToStringUni(fp);
            CoTaskMemFree(fp);
            uint acl = Erlauben(exe, sid);
            if (acl != 0) return "rechte " + acl;
            // Den eigenen Programmordner lesen (nur er, nicht vererbt): sonst startet die .NET-Laufzeit im Container
            // nicht (sie sieht sich den Ordner des Programms an). Darin liegen nur das Programm und die Netz-Bibliotheken.
            acl = Erlauben(Path.GetDirectoryName(exe), sid);
            if (acl != 0) return "rechte ordner " + acl;
            // Die beiden Netz-Bibliotheken neben dem Programm (vom Helfer geprüft hingelegt): ebenso nur lesen/ausführen.
            foreach (string lib in new[] { UzNetzLib.SECP, UzNetzLib.RTC }) {
                string pfad = Path.Combine(Path.GetDirectoryName(exe), lib);
                if (File.Exists(pfad) && Erlauben(pfad, sid) != 0) return "rechte " + lib;
            }
            if (!ConvertStringSidToSidW(InternetClient, out cap)) return "faehigkeit";
            k.Container = true;

            IntPtr groesse = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 3, 0, ref groesse);
            liste = Marshal.AllocHGlobal(groesse);
            if (!InitializeProcThreadAttributeList(liste, 3, 0, ref groesse)) { Marshal.FreeHGlobal(liste); liste = IntPtr.Zero; return "attribute " + Marshal.GetLastWin32Error(); }
            var saa = new SID_AND_ATTRIBUTES();
            saa.Sid = cap;
            saa.Attributes = SE_GROUP_ENABLED;
            saPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SID_AND_ATTRIBUTES)));
            Marshal.StructureToPtr(saa, saPtr, false);
            var sc = new SECURITY_CAPABILITIES();
            sc.AppContainerSid = sid;
            sc.Capabilities = saPtr;
            sc.CapabilityCount = 1;
            scPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SECURITY_CAPABILITIES)));
            Marshal.StructureToPtr(sc, scPtr, false);
            if (!UpdateProcThreadAttribute(liste, 0, (IntPtr)ATTR_SECURITY_CAPABILITIES, scPtr, (IntPtr)Marshal.SizeOf(typeof(SECURITY_CAPABILITIES)), IntPtr.Zero, IntPtr.Zero)) return "faehigkeiten " + Marshal.GetLastWin32Error();
            // Nur die Leitungs-Enden erbt der Kindprozess – kein anderes offenes Handle des Helfers.
            var erben = new List<IntPtr>();
            foreach (IntPtr h in new[] { kindIn, kindAus, kindFehler }) if (h != IntPtr.Zero && !erben.Contains(h)) erben.Add(h);
            hl = Marshal.AllocHGlobal(IntPtr.Size * erben.Count);
            for (int i = 0; i < erben.Count; i++) Marshal.WriteIntPtr(hl, i * IntPtr.Size, erben[i]);
            if (!UpdateProcThreadAttribute(liste, 0, (IntPtr)ATTR_HANDLE_LIST, hl, (IntPtr)(IntPtr.Size * erben.Count), IntPtr.Zero, IntPtr.Zero)) return "handles " + Marshal.GetLastWin32Error();
            // Keine Kindprozesse (ab Windows 10 1709; sonst bleibt das Job-Objekt als Grenze).
            pol = Marshal.AllocHGlobal(4);
            Marshal.WriteInt32(pol, 1);
            k.Kindsperre = UpdateProcThreadAttribute(liste, 0, (IntPtr)ATTR_CHILD_PROCESS_POLICY, pol, (IntPtr)4, IntPtr.Zero, IntPtr.Zero);

            var si = new STARTUPINFOEX();
            si.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
            si.StartupInfo.dwFlags = 0x100;   // STARTF_USESTDHANDLES
            si.StartupInfo.hStdInput = kindIn;
            si.StartupInfo.hStdOutput = kindAus;
            si.StartupInfo.hStdError = kindFehler;
            si.lpAttributeList = liste;
            env = Marshal.StringToHGlobalUni(Umgebung(Environment.GetEnvironmentVariable("SystemRoot") ?? "C:\\Windows", k.Ordner));
            var cmd = new StringBuilder(befehl);
            if (!CreateProcessW(exe, cmd, IntPtr.Zero, IntPtr.Zero, true, EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | DETACHED_PROCESS | CREATE_UNICODE_ENVIRONMENT, env, k.Ordner, ref si, out k.Pi))
                return "start " + Marshal.GetLastWin32Error();
            k.Job = Job();
            if (k.Job == IntPtr.Zero || !AssignProcessToJobObject(k.Job, k.Pi.hProcess)) {
                TerminateProcess(k.Pi.hProcess, 1);
                return "job " + Marshal.GetLastWin32Error();
            }
            ResumeThread(k.Pi.hThread);
            return "";
        } finally {
            if (liste != IntPtr.Zero) { DeleteProcThreadAttributeList(liste); Marshal.FreeHGlobal(liste); }
            foreach (IntPtr m in new[] { scPtr, saPtr, hl, pol, env }) if (m != IntPtr.Zero) Marshal.FreeHGlobal(m);
            if (cap != IntPtr.Zero) LocalFree(cap);
            if (sid != IntPtr.Zero) FreeSid(sid);
        }
    }

    public static string Probe(string exe, string lesen, string liste, string schreiben, int timeoutMs) {
        var e = new Ergebnis();
        var uhr = Stopwatch.StartNew();
        IntPtr inR = IntPtr.Zero, inW = IntPtr.Zero, outR = IntPtr.Zero, outW = IntPtr.Zero;
        var k = new Kind();
        try {
            var sa = new SECURITY_ATTRIBUTES();
            sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
            sa.bInheritHandle = 1;
            if (!CreatePipe(out inR, out inW, ref sa, 0) || !CreatePipe(out outR, out outW, ref sa, 0)) { e.Fehler = "pipe " + Marshal.GetLastWin32Error(); return e.Json(); }
            // Die eigenen Enden bleiben beim Helfer.
            SetHandleInformation(inW, 1, 0);
            SetHandleInformation(outR, 1, 0);
            string f = Starten(exe, "echo", inR, outW, IntPtr.Zero, k);
            e.Container = k.Container;
            e.Kindsperre = k.Kindsperre;
            if (f != "") { e.Fehler = f; return e.Json(); }
            CloseHandle(inR); inR = IntPtr.Zero;
            CloseHandle(outW); outW = IntPtr.Zero;

            var zu = new FileStream(new SafeFileHandle(inW, true), FileAccess.Write, 4096);
            var von = new FileStream(new SafeFileHandle(outR, true), FileAccess.Read, 4096);
            inW = IntPtr.Zero; outR = IntPtr.Zero;
            string auftrag = Auftrag(k.Ordner, lesen, liste, schreiben);
            var t = new Thread(delegate() {
                try { Gespraech(zu, von, auftrag, e); } catch (Exception gx) { e.Echo = false; e.Fehler = "echo " + gx.GetType().Name.ToLowerInvariant(); }
            });
            t.IsBackground = true;
            t.Start();
            if (!t.Join(timeoutMs)) {
                TerminateJobObject(k.Job, 1);
                t.Join(2000);
                e.Fehler = "zeit";
            }
            uint code = 0;
            bool zuEnde = WaitForSingleObject(k.Pi.hProcess, 3000) == 0 && GetExitCodeProcess(k.Pi.hProcess, out code);
            e.Sauber = zuEnde && code == 0;
            // Kam kein Echo, sagt der Code des Kindprozesses meist, warum (etwa 0xC0000135: Datei fehlt,
            // 0xC0000022: kein Zugriff, 0xE0434352: Ausnahme in .NET).
            if (!e.Echo && zuEnde && code != 0) e.Fehler = (e.Fehler == "" ? "" : e.Fehler + ", ") + "kind 0x" + code.ToString("x8");
            try { zu.Dispose(); } catch { }
            try { von.Dispose(); } catch { }
        } catch (Exception ex) {
            e.Fehler = "ausnahme " + ex.GetType().Name.ToLowerInvariant();
        } finally {
            k.Schliessen();
            foreach (IntPtr h in new[] { inR, inW, outR, outW }) if (h != IntPtr.Zero) CloseHandle(h);
            e.Ms = uhr.ElapsedMilliseconds;
        }
        return e.Json();
    }

    // Eine Sitzung (Helfer mit -ZimmerNetz <rolle>): Der Kindprozess bekommt Uzais Leitung – die
    // Standardeingabe und -ausgabe dieses Helfers – direkt; der Helfer liest und schreibt darauf
    // nichts, er hält nur das Job-Objekt und wartet. Endet Uzai, endet die Leitung und damit der
    // Kindprozess (Code 3); endet der Helfer, schließt das Job-Objekt den Kindprozess.
    // Rückgabe: Code des Kindprozesses; 2 unbekannte Rolle, 6 Start gescheitert.
    public static int Sitzung(string exe, string rolle) {
        if (Array.IndexOf(Rollen, rolle) < 0) return 2;
        IntPtr ich = GetCurrentProcess();
        IntPtr hin = IntPtr.Zero, haus = IntPtr.Zero;
        var k = new Kind();
        try {
            if (!DuplicateHandle(ich, GetStdHandle(-10), ich, out hin, 0, true, DUPLICATE_SAME_ACCESS)) return 6;
            if (!DuplicateHandle(ich, GetStdHandle(-11), ich, out haus, 0, true, DUPLICATE_SAME_ACCESS)) return 6;
            string f = Starten(exe, rolle, hin, haus, IntPtr.Zero, k);
            if (f != "") { Console.Error.WriteLine("zimmer-netz: " + Bereinigt(f)); return 6; }
            CloseHandle(hin); hin = IntPtr.Zero;
            CloseHandle(haus); haus = IntPtr.Zero;
            WaitForSingleObject(k.Pi.hProcess, 0xFFFFFFFF);
            uint code;
            return GetExitCodeProcess(k.Pi.hProcess, out code) ? (int)code : 6;
        } finally {
            k.Schliessen();
            if (hin != IntPtr.Zero) CloseHandle(hin);
            if (haus != IntPtr.Zero) CloseHandle(haus);
        }
    }

    // Drei Pings (leer, ein Byte, 8 KiB Zufall) müssen genau zurückkommen, dann der Selbsttest, dann Ende.
    public static void Gespraech(Stream zu, Stream von, string auftrag, Ergebnis e) {
        var zufall = new byte[UzNetzRahmen.MAX];
        using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create()) rng.GetBytes(zufall);
        bool echo = true;
        foreach (byte[] p in new[] { new byte[0], new byte[] { 0x55 }, zufall }) {
            UzNetzRahmen.Schreiben(zu, UzNetzRahmen.PING, p);
            byte art;
            byte[] r = UzNetzRahmen.Lesen(von, out art);
            echo = echo && r != null && art == UzNetzRahmen.PONG && Gleich(r, p);
        }
        e.Echo = echo;
        UzNetzRahmen.Schreiben(zu, UzNetzRahmen.SELBSTTEST, Encoding.UTF8.GetBytes(auftrag));
        byte art2;
        byte[] antwort = UzNetzRahmen.Lesen(von, out art2);
        if (antwort != null && art2 == UzNetzRahmen.ERGEBNIS) Auswerten(Encoding.UTF8.GetString(antwort), e);
        UzNetzRahmen.Schreiben(zu, UzNetzRahmen.ENDE, new byte[0]);
    }

    public static bool Gleich(byte[] a, byte[] b) {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }

    // Job-Objekt: genau ein Prozess, 256 MB, endet mit dem Helfer, unbehandelte Fehler beenden ihn;
    // keine Zwischenablage, keine fremden Fenster-Handles, kein Desktop-Wechsel, keine Systemeinstellungen.
    static IntPtr Job() {
        IntPtr job = CreateJobObjectW(IntPtr.Zero, null);
        if (job == IntPtr.Zero) return job;
        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.Basic.LimitFlags = 0x2000 | 0x8 | 0x100 | 0x400;   // KILL_ON_JOB_CLOSE, ACTIVE_PROCESS, PROCESS_MEMORY, DIE_ON_UNHANDLED_EXCEPTION
        info.Basic.ActiveProcessLimit = 1;
        info.ProcessMemoryLimit = (UIntPtr)SPEICHER;
        int n = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr p = Marshal.AllocHGlobal(n);
        try {
            Marshal.StructureToPtr(info, p, false);
            if (!SetInformationJobObject(job, 9, p, (uint)n)) { CloseHandle(job); return IntPtr.Zero; }
            Marshal.WriteInt32(p, 0xFF);   // JOB_OBJECT_UILIMIT_*: alle
            if (!SetInformationJobObject(job, 4, p, 4)) { CloseHandle(job); return IntPtr.Zero; }
        } finally { Marshal.FreeHGlobal(p); }
        return job;
    }

    // Der Container darf genau diese eine Datei lesen und ausführen – sonst nichts von Uzai.
    static uint Erlauben(string datei, IntPtr sid) {
        IntPtr dacl, sd, neu;
        uint r = GetNamedSecurityInfoW(datei, 1, 4, IntPtr.Zero, IntPtr.Zero, out dacl, IntPtr.Zero, out sd);
        if (r != 0) return r;
        try {
            var ea = new EXPLICIT_ACCESS();
            ea.grfAccessPermissions = GENERIC_READ | GENERIC_EXECUTE;
            ea.grfAccessMode = 1;          // GRANT_ACCESS
            ea.grfInheritance = 0;
            ea.Trustee.TrusteeForm = 0;    // TRUSTEE_IS_SID
            ea.Trustee.TrusteeType = 5;    // TRUSTEE_IS_WELL_KNOWN_GROUP
            ea.Trustee.ptstrName = sid;
            r = SetEntriesInAclW(1, ref ea, dacl, out neu);
            if (r != 0) return r;
            try { return SetNamedSecurityInfoW(datei, 1, 4, IntPtr.Zero, IntPtr.Zero, neu, IntPtr.Zero); }
            finally { LocalFree(neu); }
        } finally { LocalFree(sd); }
    }
}
'@

$script:ZimmerNetzReady = $false
## Zimmer-Netz: das kleine Programm einmal bauen (je Fassung eine Datei). Pfad oder ''.
function ZimmerNetz-Bauen {
    # ECDH (System.Core) und WebSocket (System): Windows PowerShell 5 braucht System.Core zusätzlich.
    $refs = @{}
    if ($PSVersionTable.PSEdition -ne 'Core') { $refs.ReferencedAssemblies = @('System.Core') }
    if (-not $script:ZimmerNetzReady) { Add-Type -TypeDefinition $script:ZimmerNetzSrc @refs; $script:ZimmerNetzReady = $true }
    $dir = Join-Path $env:LOCALAPPDATA 'Uzai\zimmer-netz'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir ('uzai-zimmer-netz-' + [UzZimmerNetz]::Version + '.exe')
    if (-not (Test-Path -LiteralPath $exe)) {
        $tmp = Join-Path $dir ('uzai-zimmer-netz-' + [UzZimmerNetz]::Version + '.neu.exe')
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        Add-Type -TypeDefinition $script:ZimmerNetzSrc @refs -OutputAssembly $tmp -OutputType ConsoleApplication -IgnoreWarnings
        if (-not (Test-Path -LiteralPath $tmp)) { return '' }
        Move-Item -Force -LiteralPath $tmp -Destination $exe
    }
    ZimmerNetz-Bibliotheken $dir
    return $exe
}

## Zimmer-Netz: die beiden Netz-Bibliotheken (libsecp256k1, libdatachannel; tools/bau_netzlibs.sh) neben das Programm
## der Sandbox legen – nur mit der fest eingetragenen Prüfsumme (dieselbe prüft die Sandbox vor dem Laden noch einmal).
## Uzai legt sie geprüft nach „net“ neben diesen Helfer (src/room/zimmer_netz.gd netzlibs_auslegen). Fehlt eine oder
## stimmt sie nicht, bleibt sie weg (die Sandbox meldet das in „Abschottung prüfen“); geladen wird hier nichts.
function ZimmerNetz-Bibliotheken([string]$dir) {
    foreach ($paar in @(@([UzNetzLib]::SECP, [UzNetzLib]::SECP_SHA256), @([UzNetzLib]::RTC, [UzNetzLib]::RTC_SHA256))) {
        $quelle = Join-Path (Join-Path $PSScriptRoot 'net') $paar[0]
        $ziel = Join-Path $dir $paar[0]
        try {
            if ((Test-Path -LiteralPath $ziel -PathType Leaf) -and (Get-FileHash -LiteralPath $ziel -Algorithm SHA256).Hash.ToLowerInvariant() -eq $paar[1]) { continue }
            if (Test-Path -LiteralPath $ziel) { Remove-Item -LiteralPath $ziel -Force }
            if (-not (Test-Path -LiteralPath $quelle -PathType Leaf) -or (Get-Item -LiteralPath $quelle).Length -gt [UzNetzLib]::MAX_DATEI) { continue }
            if ((Get-FileHash -LiteralPath $quelle -Algorithm SHA256).Hash.ToLowerInvariant() -ne $paar[1]) { continue }
            $neu = $ziel + '.neu'
            Copy-Item -LiteralPath $quelle -Destination $neu -Force
            if ((Get-FileHash -LiteralPath $neu -Algorithm SHA256).Hash.ToLowerInvariant() -eq $paar[1]) { Move-Item -Force -LiteralPath $neu -Destination $ziel }
            else { Remove-Item -LiteralPath $neu -Force }
        } catch {}
    }
}

## Zimmer-Netz: Sandbox-Prozess im AppContainer starten, Echo und Mauern prüfen. Keine Argumente
## von außen – Pfade setzt der Helfer selbst. Mit Adminrechten gar nicht (Abschnitt 4.6).
function ZimmerNetz-Probe {
    if ([UzElev]::IsElevated($PID)) { return @{ ok = $false; fehler = 'admin' } }
    $exe = ZimmerNetz-Bauen
    if ($exe -eq '') { return @{ ok = $false; fehler = 'bau' } }
    $probe = Join-Path $env:TEMP 'uzai-zimmer-netz-probe.txt'
    return ([UzZimmerNetz]::Probe($exe, [string]$PSCommandPath, [string]$env:USERPROFILE, $probe, 12000) | ConvertFrom-Json)
}

# --- Uzai-Browser (Wunschliste 120, docs/SECURITY.md „Uzai-Browser“) --------------------------------
# browser-bauen: den Browser-Wirt einmal je Fassung als eigenes kleines Programm übersetzen und den Pfad
# melden – Uzai startet ihn dann selbst (src/core/browser_wirt.gd). Uzai legt die Quelle des Wirts
# (uzai-browser-wirt.cs), das Sprung-Skript (uzai-browser-karte.js) und die beiden WebView2-Dateien aus dem
# NuGet-Paket Microsoft.Web.WebView2 1.0.4258.31 in den Ordner „browser“ neben diesen Helfer. Geprüft wird
# hier: SHA-256 jeder DLL gegen die feste Liste und gültige Signatur von Microsoft Corporation; ohne das
# wird nichts gebaut. Ziel: %LOCALAPPDATA%\Uzai\browser\bin-<Fassung> (Fassung = SHA-256 über alle vier
# Dateien), dort liegen dann das Programm, die beiden DLLs und das Skript; der Wirt prüft sie beim Start ein
# drittes Mal. Alte Fassungen (nur Ordner genau dieses Musters, nie Verknüpfungen) räumt der Helfer weg.
# Keine Argumente, nie mit Adminrechten.
$script:BrowserDateien = @{
    'Microsoft.Web.WebView2.Core.dll' = 'd60e6e94245078cb56e44ebd5f360dc04bf18e460136be93bfc4cfca43b98505'
    'WebView2Loader.dll' = '3426dcc55fdfb8b5e7ac623cf33b4ccf283fbf68a0c5a65bddfdb4d749a8abee'
}
$script:BrowserQuellen = @('uzai-browser-wirt.cs', 'uzai-browser-karte.js')

function Browser-Signiert([string]$pfad) {
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $pfad
        if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate) { return $false }
        return ([string]$sig.SignerCertificate.Subject).Contains('O=Microsoft Corporation')
    } catch { return $false }
}

function Browser-Hash([string]$pfad) {
    return (Get-FileHash -LiteralPath $pfad -Algorithm SHA256).Hash.ToLowerInvariant()
}

## Stimmen die DLLs in diesem Ordner (Prüfsumme, Signatur)?
function Browser-DateienOk([string]$ordner) {
    foreach ($n in @($script:BrowserDateien.Keys)) {
        $p = Join-Path $ordner $n
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $false }
        if ((Browser-Hash $p) -ne $script:BrowserDateien[$n]) { return $false }
        if (-not (Browser-Signiert $p)) { return $false }
    }
    return $true
}

function Browser-Bauen {
    if ([UzElev]::IsElevated($PID)) { return @{ ok = $false; fehler = 'start' } }
    $quelle = Join-Path $PSScriptRoot 'browser'
    if (-not (Browser-DateienOk $quelle)) { return @{ ok = $false; fehler = 'pruefung' } }
    $teile = @()
    foreach ($n in @(@($script:BrowserDateien.Keys | Sort-Object) + $script:BrowserQuellen)) {
        $p = Join-Path $quelle $n
        if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p).Length -gt 4194304) { return @{ ok = $false; fehler = 'pruefung' } }
        $teile += (Browser-Hash $p)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    $fassung = (($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($teile -join ':')) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)
    $wurzel = Join-Path $env:LOCALAPPDATA 'Uzai\browser'
    $bin = Join-Path $wurzel ('bin-' + $fassung)
    $exe = Join-Path $bin 'uzai-browser.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        foreach ($n in @(@($script:BrowserDateien.Keys) + @('uzai-browser-karte.js'))) {
            Copy-Item -LiteralPath (Join-Path $quelle $n) -Destination (Join-Path $bin $n) -Force
        }
        $tmp = Join-Path $bin 'uzai-browser.neu.exe'
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $cp = New-Object System.CodeDom.Compiler.CompilerParameters
        foreach ($r in @('System.dll', 'System.Core.dll', 'System.Drawing.dll', (Join-Path $bin 'Microsoft.Web.WebView2.Core.dll'))) { [void]$cp.ReferencedAssemblies.Add($r) }
        $cp.GenerateExecutable = $true
        $cp.GenerateInMemory = $false
        $cp.OutputAssembly = $tmp
        $cp.CompilerOptions = '/target:winexe /platform:x64 /optimize+'
        $src = [IO.File]::ReadAllText((Join-Path $quelle 'uzai-browser-wirt.cs'), [Text.Encoding]::UTF8)
        # Add-Type will das fertige Programm danach in diese Sitzung laden – das schlägt fehl (WebView2 liegt nur
        # neben dem Programm) und ist egal: Es zählt nur, dass die Datei gebaut ist.
        try { Add-Type -TypeDefinition $src -CompilerParameters $cp -ErrorAction Stop } catch {}
        if (-not (Test-Path -LiteralPath $tmp -PathType Leaf)) { return @{ ok = $false; fehler = 'start' } }
        Move-Item -Force -LiteralPath $tmp -Destination $exe
    }
    if (-not (Browser-DateienOk $bin)) {
        Remove-Item -LiteralPath $bin -Recurse -Force -ErrorAction SilentlyContinue
        return @{ ok = $false; fehler = 'pruefung' }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $wurzel -Directory -ErrorAction SilentlyContinue)) {
        if ($d.Name -notmatch '^bin-[0-9a-f]{12}$' -or $d.Name -eq ('bin-' + $fassung)) { continue }
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    return @{ ok = $true; exe = $exe; version = $fassung }
}

# --- Browser-Kern (Chromium über CEF; docs/BROWSER_PLAN.md 2.1/2.2, docs/SECURITY.md „Uzai-Browser“) ----------
# Drei Schritte, alle ohne Adminrechte, alle nur unter %LOCALAPPDATA%\Uzai\browser\kern:
#   kern-auslegen   Uzai hat die signierte CEF-Verteilung (cef_binary_…_signed.tar.xz) nach kern\spiegel und die
#                   minimal-Verteilung derselben Fassung (cef_binary_…_minimal.tar.bz2 oder .tar.xz) nach kern\boot
#                   geladen und geprüft. Der Helfer liest beide mit eigenem Entpacker (UzKernPack: xz/LZMA2, bzip2 und
#                   tar in verwaltetem Code, nicht Windows-tar – das kann xz nicht überall und verliert Umlaute im Pfad):
#                   aus der signierten NUR chrome_elf.dll (liegt dort oben, ohne Release/; die signierte Verteilung hat
#                   keinen Bootstrap), aus der minimal NUR Release/bootstrap.exe – unter festen Namen in einen
#                   Zwischenordner – und legt sie als uzai-browser.exe, uzai-kernladen.exe (beides Kopien des Bootstraps)
#                   und chrome_elf.dll nach kern\app. Die übrige Laufzeit bringt der offizielle Installer aus der signierten.
#                   Ist eine Kopie signiert, nimmt er die Signatur-Tabelle aus der KOPIE (Code unverändert): Der
#                   Bootstrap verlangt, dass EXE, chrome_elf.dll und unsere unsignierte Client-DLL zusammenpassen.
#                   Dazu der Start-Stummel (assets/browser/cef/uzai-browser-start.dll, Prüfsumme unten) zweimal als
#                   uzai-browser.dll und uzai-kernladen.dll, die Skripte und die Filterliste (Prüfsumme unten).
#   kern-bauen      übersetzt helper/uzai-browser-gemeinsam.cs + uzai-browser-kern.cs einmal je Fassung als DLL
#                   (kern\app\uzai-browser-kern.dll). Gestartet wird dabei nichts.
#   kern-ressource  schreibt die Konfiguration des CEF-Installers (CEF_INSTALLER_CONFIG, JSON) als Ressource in die
#                   Kopie uzai-browser.dll – appid, vmin, vmax, abi_hash, install_path (kern\store), launch_health. Die
#                   Kopie uzai-kernladen.dll bleibt ohne Ressource: Damit läuft der erste Download über unsere eigene
#                   Fortschrittsanzeige (RunInstaller aus dem Kern) statt still beim Start.
$script:KernStummelSha = '3e8257dff57644731000628ffa75b586c6c95740ccfda83ca78c2ba53cc28ac5'
# Zertifikat der CEF-Verteilung (wie CEF_ZERTIFIKAT in uzai-browser-kern.cs): chrome_elf.dll aus der signierten
# Verteilung muss gültig damit signiert sein, bevor irgendetwas daraus läuft. Der Bootstrap der minimal-Verteilung ist
# unsigniert (Stand CEF 156) – trägt er einmal eine Signatur, muss es dieselbe sein.
$script:CefZertifikat = '3906F72B1D5FA45A6334A8590495FAEB93347E5B'
$script:KernFilterSha = '32275b8fce9d1b36ba8493b3cb160694d438c90ce4275ace4c3d87f2e02329f6'

function Kern-Wurzel { return (Join-Path $env:LOCALAPPDATA 'Uzai\browser\kern') }

## Authenticode-Tabelle aus einer Kopie entfernen: Security-Verzeichnis (Eintrag 4) nullen, Datei dahinter abschneiden.
## Nur PE32+ und nur, wenn die Tabelle ganz am Ende liegt; sonst $false (Datei bleibt, wie sie ist).
function Kern-SignaturEntfernen([string]$pfad) {
    $b = [IO.File]::ReadAllBytes($pfad)
    if ($b.Length -lt 0x200 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return $false }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ($pe -le 0 -or $pe + 0x100 -gt $b.Length -or $b[$pe] -ne 0x50 -or $b[$pe + 1] -ne 0x45) { return $false }
    if ([BitConverter]::ToUInt16($b, $pe + 24) -ne 0x20B) { return $false }
    $secOff = $pe + 24 + 112 + 4 * 8
    $rva = [BitConverter]::ToUInt32($b, $secOff)
    $size = [BitConverter]::ToUInt32($b, $secOff + 4)
    if ($rva -eq 0 -or $size -eq 0) { return $true }
    if ([long]$rva + [long]$size -ne $b.Length) { return $false }
    [Array]::Clear($b, $secOff, 8)
    $neu = New-Object byte[] $rva
    [Array]::Copy($b, $neu, $rva)
    [IO.File]::WriteAllBytes($pfad, $neu)
    return $true
}

# Entpacker für die Verteilung (UzKernPack, tests/kern_pack_cs.ps1): eigener, verwalteter Code statt Windows-tar.
$script:KernPackSrc = @'
using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Text.RegularExpressions;

// Kleiner, geprüfter Entpacker für die CEF-Verteilungen (.tar.xz, .tar.bz2), unabhängig vom tar.exe von Windows (das
// xz je nach Windows-Fassung nicht kann und Pfade mit Umlauten über die ANSI-Codepage verliert). Nur verwalteter Code
// (jeder Zugriff ist geprüft), liest nur vorwärts, schreibt nur den einen gesuchten Eintrag unter festem Namen in einen
// leeren Ordner – kein Pfad aus dem Archiv wird je zum Dateinamen. xz: Stream-Kopf, Blöcke mit genau einem Filter
// (LZMA2), Prüfsumme CRC32/CRC64/SHA-256/keine, Index und Fuß werden geprüft; bzip2: CRC je Block und Strom;
// tar: ustar, pax und GNU-Langnamen.
public sealed class UzXzFehler : Exception {
    public UzXzFehler(string m) : base(m) { }
}

public static class UzCrc {
    static uint[] t32;
    static ulong[] t64;

    static void Init() {
        if (t32 != null) return;
        var a = new uint[256];
        var b = new ulong[256];
        for (uint i = 0; i < 256; i++) {
            uint c = i;
            ulong d = i;
            for (int k = 0; k < 8; k++) {
                c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                d = (d & 1) != 0 ? 0xC96C5795D7870F42UL ^ (d >> 1) : d >> 1;
            }
            a[i] = c;
            b[i] = d;
        }
        t64 = b;
        t32 = a;
    }

    public static uint Crc32(byte[] b, int o, int n, uint crc) {
        Init();
        crc = ~crc;
        for (int i = o; i < o + n; i++) crc = t32[(crc ^ b[i]) & 0xFF] ^ (crc >> 8);
        return ~crc;
    }

    public static ulong Crc64(byte[] b, int o, int n, ulong crc) {
        Init();
        crc = ~crc;
        for (int i = o; i < o + n; i++) crc = t64[(crc ^ b[i]) & 0xFF] ^ (crc >> 8);
        return ~crc;
    }
}

// Liest einen xz-Strom (auch mehrere hintereinander) als Strom der entpackten Bytes.
public sealed class UzXzLeser : Stream {
    public const uint MAX_WOERTERBUCH = 256u << 20;
    public const long MAX_AUSGABE = 16L << 30;

    readonly Stream ein;
    int pruefArt = -1;
    int pruefLaenge;
    byte[] flags = new byte[2];
    bool imBlock;
    bool ende;
    bool halt;
    int bloecke;
    long blockGepackt;
    long blockEntpackt;
    long blockSollGepackt = -1;
    long blockSollEntpackt = -1;
    uint crc32;
    ulong crc64;
    SHA256 sha;
    public long Ausgabe;

    // LZMA2
    byte[] fenster;
    int fpos;
    long seitReset;
    uint woerterbuch;
    bool brauchtReset = true;
    bool brauchtProps = true;
    int lc, lp, pb;
    ushort[] lit;
    readonly ushort[] isMatch = new ushort[192], isRep = new ushort[12], isRepG0 = new ushort[12], isRepG1 = new ushort[12], isRepG2 = new ushort[12],
        isRep0Long = new ushort[192], posSlot = new ushort[256], posDec = new ushort[115], align = new ushort[16];
    readonly ushort[] lenC = new ushort[2], lenLow = new ushort[128], lenMid = new ushort[128], lenHigh = new ushort[256];
    readonly ushort[] repC = new ushort[2], repLow = new ushort[128], repMid = new ushort[128], repHigh = new ushort[256];
    int zustand;
    uint rep0, rep1, rep2, rep3;
    // Bereichsdecoder über einem Abschnitt
    readonly byte[] gepackt = new byte[65536];
    int ip, iende;
    uint bereich, code;
    // noch nicht abgeholte Ausgabe im Fenster
    int ausStart, ausRest;

    public UzXzLeser(Stream s) {
        ein = s;
        StreamKopf(true);
    }

    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position { get { return Ausgabe; } set { throw new NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long o, SeekOrigin w) { throw new NotSupportedException(); }
    public override void SetLength(long v) { throw new NotSupportedException(); }
    public override void Write(byte[] b, int o, int n) { throw new NotSupportedException(); }

    static UzXzFehler F(string m) { return new UzXzFehler("xz: " + m); }

    int Byte() {
        int b = ein.ReadByte();
        if (b < 0) throw F("Archiv endet zu früh");
        if (imBlock) blockGepackt++;
        return b;
    }

    void Voll(byte[] b, int o, int n) {
        while (n > 0) {
            int k = ein.Read(b, o, n);
            if (k <= 0) throw F("Archiv endet zu früh");
            if (imBlock) blockGepackt += k;
            o += k;
            n -= k;
        }
    }

    static uint Le32(byte[] b, int o) {
        return (uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24));
    }

    // Stream-Kopf: Magie, Flags, CRC32. erster = false: nach dem Fuß – Füllnullen oder Ende sind erlaubt.
    bool StreamKopf(bool erster) {
        var k = new byte[12];
        if (!erster) {
            while (true) {
                int n = 0;
                while (n < 4) {
                    int r = ein.Read(k, n, 4 - n);
                    if (r <= 0) break;
                    n += r;
                }
                if (n == 0) return false;
                if (n < 4) throw F("Füllbytes kaputt");
                if (k[0] == 0 && k[1] == 0 && k[2] == 0 && k[3] == 0) continue;
                break;
            }
            Voll(k, 4, 8);
        } else {
            Voll(k, 0, 12);
        }
        if (k[0] != 0xFD || k[1] != 0x37 || k[2] != 0x7A || k[3] != 0x58 || k[4] != 0x5A || k[5] != 0) throw F("kein xz-Archiv");
        if (k[6] != 0 || (k[7] & 0xF0) != 0 || UzCrc.Crc32(k, 6, 2, 0) != Le32(k, 8)) throw F("Kopf kaputt");
        pruefArt = k[7];
        if (pruefArt == 0) pruefLaenge = 0;
        else if (pruefArt == 1) pruefLaenge = 4;
        else if (pruefArt == 4) pruefLaenge = 8;
        else if (pruefArt == 10) pruefLaenge = 32;
        else throw F("Prüfsummen-Art " + pruefArt + " unbekannt");
        flags[0] = k[6];
        flags[1] = k[7];
        bloecke = 0;
        return true;
    }

    static long Zahl(byte[] b, ref int o, int ende) {
        long v = 0;
        for (int i = 0; i < 9; i++) {
            if (o >= ende) throw F("Zahl kaputt");
            int x = b[o++];
            v |= (long)(x & 0x7F) << (7 * i);
            if ((x & 0x80) == 0) {
                if (i > 0 && x == 0) throw F("Zahl kaputt");
                return v;
            }
        }
        throw F("Zahl zu lang");
    }

    long ZahlStrom(ref uint crc, ref long laenge) {
        long v = 0;
        var e = new byte[1];
        for (int i = 0; i < 9; i++) {
            int x = Byte();
            e[0] = (byte)x;
            crc = UzCrc.Crc32(e, 0, 1, crc);
            laenge++;
            v |= (long)(x & 0x7F) << (7 * i);
            if ((x & 0x80) == 0) return v;
        }
        throw F("Zahl zu lang");
    }

    // Nächster Block; false am Ende aller Ströme.
    bool BlockKopf() {
        while (true) {
            int g = Byte();
            if (g == 0) {
                Index();
                if (!StreamKopf(false)) return false;
                continue;
            }
            int n = (g + 1) * 4;
            var k = new byte[n];
            k[0] = (byte)g;
            Voll(k, 1, n - 1);
            if (UzCrc.Crc32(k, 0, n - 4, 0) != Le32(k, n - 4)) throw F("Blockkopf kaputt");
            int f = k[1];
            if ((f & 0x3C) != 0) throw F("Blockkopf unbekannt");
            int o = 2;
            blockSollGepackt = (f & 0x40) != 0 ? Zahl(k, ref o, n - 4) : -1;
            blockSollEntpackt = (f & 0x80) != 0 ? Zahl(k, ref o, n - 4) : -1;
            int filter = (f & 3) + 1;
            for (int i = 0; i < filter; i++) {
                long id = Zahl(k, ref o, n - 4);
                long pl = Zahl(k, ref o, n - 4);
                if (filter != 1 || id != 0x21) throw F("Filter 0x" + id.ToString("x") + " wird nicht unterstützt (nur LZMA2)");
                if (pl != 1 || o >= n - 4) throw F("Filter kaputt");
                int d = k[o++];
                if (d > 40) throw F("Wörterbuch kaputt");
                uint w = d == 40 ? 0xFFFFFFFFu : (uint)((2 | (d & 1)) << (d / 2 + 11));
                if (w > MAX_WOERTERBUCH) throw F("Wörterbuch zu groß");
                woerterbuch = w;
            }
            while (o < n - 4) if (k[o++] != 0) throw F("Blockkopf kaputt");
            int fg = (int)Math.Max(woerterbuch, 1u << 21);
            if (fenster == null || fenster.Length < fg) fenster = new byte[fg];
            blockGepackt = 0;
            blockEntpackt = 0;
            crc32 = 0;
            crc64 = 0;
            if (pruefArt == 10) sha = SHA256.Create();
            brauchtReset = true;
            brauchtProps = true;
            imBlock = true;
            bloecke++;
            return true;
        }
    }

    void BlockEnde() {
        imBlock = false;
        if ((blockSollGepackt >= 0 && blockSollGepackt != blockGepackt) || (blockSollEntpackt >= 0 && blockSollEntpackt != blockEntpackt)) throw F("Blockgröße stimmt nicht");
        long pad = (4 - (blockGepackt & 3)) & 3;
        for (long i = 0; i < pad; i++) if (Byte() != 0) throw F("Block kaputt");
        var p = new byte[32];
        Voll(p, 0, pruefLaenge);
        bool gut = true;
        if (pruefArt == 1) gut = Le32(p, 0) == crc32;
        else if (pruefArt == 4) gut = ((ulong)Le32(p, 0) | ((ulong)Le32(p, 4) << 32)) == crc64;
        else if (pruefArt == 10) {
            sha.TransformFinalBlock(new byte[0], 0, 0);
            byte[] h = sha.Hash;
            for (int i = 0; i < 32; i++) if (h[i] != p[i]) gut = false;
            sha.Dispose();
            sha = null;
        }
        if (!gut) throw F("Prüfsumme eines Blocks stimmt nicht");
    }

    // Index und Fuß eines Stroms: Anzahl der Blöcke, Füllbytes, CRC32, Fuß mit denselben Flags.
    void Index() {
        var e = new byte[] { 0 };
        uint crc = UzCrc.Crc32(e, 0, 1, 0);
        long laenge = 1;
        long n = ZahlStrom(ref crc, ref laenge);
        if (n != bloecke) throw F("Index passt nicht");
        for (long i = 0; i < n * 2; i++) ZahlStrom(ref crc, ref laenge);
        while ((laenge & 3) != 0) {
            if (Byte() != 0) throw F("Index kaputt");
            crc = UzCrc.Crc32(e, 0, 1, crc);
            laenge++;
        }
        var c = new byte[4];
        Voll(c, 0, 4);
        if (Le32(c, 0) != crc) throw F("Index kaputt");
        var fuss = new byte[12];
        Voll(fuss, 0, 12);
        if (fuss[10] != 0x59 || fuss[11] != 0x5A || fuss[8] != flags[0] || fuss[9] != flags[1] || UzCrc.Crc32(fuss, 4, 6, 0) != Le32(fuss, 0)) throw F("Fuß kaputt");
    }

    void RcInit() {
        if (iende - ip < 5 || gepackt[ip] != 0) throw F("Daten kaputt");
        ip++;
        code = 0;
        bereich = 0xFFFFFFFFu;
        for (int i = 0; i < 4; i++) code = (code << 8) | gepackt[ip++];
        if (code == bereich) throw F("Daten kaputt");
    }

    int Bit(ushort[] p, int i) {
        uint v = p[i];
        uint grenze = (bereich >> 11) * v;
        int bit;
        if (code < grenze) {
            v += (2048 - v) >> 5;
            bereich = grenze;
            bit = 0;
        } else {
            v -= v >> 5;
            code -= grenze;
            bereich -= grenze;
            bit = 1;
        }
        p[i] = (ushort)v;
        if (bereich < 0x1000000u) {
            if (ip >= iende) throw F("Daten kaputt");
            bereich <<= 8;
            code = (code << 8) | gepackt[ip++];
        }
        return bit;
    }

    int Baum(ushort[] p, int o, int bits) {
        int m = 1;
        for (int i = 0; i < bits; i++) m = (m << 1) + Bit(p, o + m);
        return m - (1 << bits);
    }

    int Rueckwaerts(ushort[] p, int o, int bits) {
        int m = 1, s = 0;
        for (int i = 0; i < bits; i++) {
            int b = Bit(p, o + m);
            m = (m << 1) + b;
            s |= b << i;
        }
        return s;
    }

    uint Direkt(int bits) {
        uint r = 0;
        do {
            bereich >>= 1;
            code -= bereich;
            uint t = 0u - (code >> 31);
            code += bereich & t;
            if (code == bereich) throw F("Daten kaputt");
            if (bereich < 0x1000000u) {
                if (ip >= iende) throw F("Daten kaputt");
                bereich <<= 8;
                code = (code << 8) | gepackt[ip++];
            }
            r = (r << 1) + (t + 1);
        } while (--bits > 0);
        return r;
    }

    int Laenge(ushort[] c, ushort[] low, ushort[] mid, ushort[] high, int ps) {
        if (Bit(c, 0) == 0) return Baum(low, ps << 3, 3);
        if (Bit(c, 1) == 0) return 8 + Baum(mid, ps << 3, 3);
        return 16 + Baum(high, 0, 8);
    }

    static void Init(ushort[] p) {
        for (int i = 0; i < p.Length; i++) p[i] = 1024;
    }

    void Props(int d) {
        if (d > 224) throw F("LZMA-Eigenschaften kaputt");
        lc = d % 9;
        d /= 9;
        lp = d % 5;
        pb = d / 5;
        if (lc + lp > 4) throw F("LZMA-Eigenschaften kaputt");
        int n = 0x300 << (lc + lp);
        if (lit == null || lit.Length != n) lit = new ushort[n];
    }

    void Zuruecksetzen() {
        foreach (var p in new ushort[][] { lit, isMatch, isRep, isRepG0, isRepG1, isRepG2, isRep0Long, posSlot, posDec, align, lenC, lenLow, lenMid, lenHigh, repC, repLow, repMid, repHigh })
            Init(p);
        zustand = 0;
        rep0 = rep1 = rep2 = rep3 = 0;
    }

    int Hol(uint d) {
        int i = fpos - (int)d;
        if (i < 0) i += fenster.Length;
        return fenster[i];
    }

    void Setz(int b) {
        fenster[fpos++] = (byte)b;
        if (fpos == fenster.Length) fpos = 0;
        seitReset++;
    }

    void Lzma(int n) {
        int fertig = 0;
        int pbMaske = (1 << pb) - 1, lpMaske = (1 << lp) - 1;
        while (fertig < n) {
            int ps = (int)(seitReset & pbMaske);
            if (Bit(isMatch, (zustand << 4) + ps) == 0) {
                int vor = seitReset > 0 ? Hol(1) : 0;
                int o = 0x300 * (int)((((int)seitReset & lpMaske) << lc) + (vor >> (8 - lc)));
                int s = 1;
                if (zustand >= 7) {
                    if ((long)rep0 >= seitReset) throw F("Daten kaputt");
                    int mb = Hol(rep0 + 1);
                    do {
                        int mbit = (mb >> 7) & 1;
                        mb <<= 1;
                        int b = Bit(lit, o + ((1 + mbit) << 8) + s);
                        s = (s << 1) | b;
                        if (mbit != b) break;
                    } while (s < 0x100);
                }
                while (s < 0x100) s = (s << 1) | Bit(lit, o + s);
                Setz(s - 0x100);
                zustand = zustand < 4 ? 0 : (zustand < 10 ? zustand - 3 : zustand - 6);
                fertig++;
                continue;
            }
            int len;
            if (Bit(isRep, zustand) != 0) {
                if (seitReset == 0) throw F("Daten kaputt");
                if (Bit(isRepG0, zustand) == 0) {
                    if (Bit(isRep0Long, (zustand << 4) + ps) == 0) {
                        if ((long)rep0 >= seitReset) throw F("Daten kaputt");
                        zustand = zustand < 7 ? 9 : 11;
                        Setz(Hol(rep0 + 1));
                        fertig++;
                        continue;
                    }
                } else {
                    uint d;
                    if (Bit(isRepG1, zustand) == 0) d = rep1;
                    else {
                        if (Bit(isRepG2, zustand) == 0) d = rep2;
                        else {
                            d = rep3;
                            rep3 = rep2;
                        }
                        rep2 = rep1;
                    }
                    rep1 = rep0;
                    rep0 = d;
                }
                len = Laenge(repC, repLow, repMid, repHigh, ps);
                zustand = zustand < 7 ? 8 : 11;
            } else {
                rep3 = rep2;
                rep2 = rep1;
                rep1 = rep0;
                len = Laenge(lenC, lenLow, lenMid, lenHigh, ps);
                zustand = zustand < 7 ? 7 : 10;
                int ls = len < 3 ? len : 3;
                int slot = Baum(posSlot, ls << 6, 6);
                if (slot < 4) rep0 = (uint)slot;
                else {
                    int nd = (slot >> 1) - 1;
                    uint d = (uint)((2 | (slot & 1)) << nd);
                    if (slot < 14) d += (uint)Rueckwaerts(posDec, (int)d - slot, nd);
                    else {
                        d += Direkt(nd - 4) << 4;
                        d += (uint)Rueckwaerts(align, 0, 4);
                    }
                    rep0 = d;
                }
                if (rep0 == 0xFFFFFFFFu) throw F("Endmarke in LZMA2");
            }
            len += 2;
            if (rep0 >= woerterbuch || (long)rep0 >= seitReset) throw F("Abstand außerhalb des Wörterbuchs");
            if (len > n - fertig) throw F("Daten kaputt");
            uint dist = rep0 + 1;
            for (int i = 0; i < len; i++) Setz(Hol(dist));
            fertig += len;
        }
    }

    // Einen LZMA2-Abschnitt entpacken; false am Ende des Blocks.
    bool Abschnitt() {
        int c = Byte();
        if (c == 0) return false;
        if (c >= 0xE0 || c == 1) {
            brauchtProps = true;
            brauchtReset = false;
            fpos = 0;
            seitReset = 0;
        } else if (brauchtReset) throw F("Daten kaputt");
        int start = fpos;
        int n;
        if (c >= 0x80) {
            n = ((c & 0x1F) << 16) + (Byte() << 8) + Byte() + 1;
            int k = (Byte() << 8) + Byte() + 1;
            if (c >= 0xC0) {
                Props(Byte());
                brauchtProps = false;
            } else if (brauchtProps) throw F("Daten kaputt");
            if (c >= 0xA0) Zuruecksetzen();
            Voll(gepackt, 0, k);
            ip = 0;
            iende = k;
            RcInit();
            Lzma(n);
            if (ip != iende || code != 0) throw F("Abschnitt kaputt");
        } else {
            if (c > 2) throw F("Daten kaputt");
            n = (Byte() << 8) + Byte() + 1;
            int rest = n;
            while (rest > 0) {
                int stueck = Math.Min(rest, fenster.Length - fpos);
                Voll(fenster, fpos, stueck);
                fpos += stueck;
                if (fpos == fenster.Length) fpos = 0;
                rest -= stueck;
            }
            seitReset += n;
        }
        // Prüfsumme über die neuen Bytes (im Ring)
        int a = start, r = n;
        while (r > 0) {
            int stueck = Math.Min(r, fenster.Length - a);
            if (pruefArt == 1) crc32 = UzCrc.Crc32(fenster, a, stueck, crc32);
            else if (pruefArt == 4) crc64 = UzCrc.Crc64(fenster, a, stueck, crc64);
            else if (pruefArt == 10) sha.TransformBlock(fenster, a, stueck, null, 0);
            a = (a + stueck) % fenster.Length;
            r -= stueck;
        }
        blockEntpackt += n;
        Ausgabe += n;
        if (Ausgabe > MAX_AUSGABE) throw F("Archiv zu groß");
        ausStart = start;
        ausRest = n;
        return true;
    }

    // Liest den laufenden Block zu Ende (und prüft seine Prüfsumme) – nach der gesuchten Datei, ohne den Rest zu lesen.
    public void BlockAbschliessen() {
        var p = new byte[1 << 16];
        halt = true;
        try {
            while (imBlock && Read(p, 0, p.Length) > 0) { }
        } finally {
            halt = false;
        }
    }

    public override int Read(byte[] b, int o, int n) {
        while (ausRest == 0) {
            if (ende) return 0;
            if (!imBlock) {
                if (halt) return 0;
                if (!BlockKopf()) {
                    ende = true;
                    return 0;
                }
            }
            if (!Abschnitt()) {
                BlockEnde();
                if (halt) return 0;
            }
        }
        int k = Math.Min(n, Math.Min(ausRest, fenster.Length - ausStart));
        Buffer.BlockCopy(fenster, ausStart, b, o, k);
        ausStart = (ausStart + k) % fenster.Length;
        ausRest -= k;
        return k;
    }
}

// Liest einen bzip2-Strom (auch mehrere hintereinander) als Strom der entpackten Bytes: Huffman-Tabellen, MTF,
// Burrows-Wheeler rückwärts, Lauflängen – jede Länge, jeder Index geprüft; CRC je Block und des ganzen Stroms.
// „Zufällige“ Blöcke (veraltet, kein heutiger Packer schreibt sie) werden abgelehnt.
public sealed class UzBz2Leser : Stream {
    public const long MAX_AUSGABE = 16L << 30;
    const int MAX_SELEKTOREN = 18002, MAX_CODE = 20;

    static uint[] tab;
    readonly Stream ein;
    readonly byte[] puffer = new byte[1 << 16];
    int pp, pe;
    ulong bits;
    int nbits;
    int maxBlock;
    uint[] tt;
    readonly byte[] selektor = new byte[MAX_SELEKTOREN];
    readonly byte[][] laenge = new byte[6][];
    readonly int[][] limit = new int[6][], basis = new int[6][], perm = new int[6][];
    readonly int[] minLaenge = new int[6];
    readonly byte[] zuByte = new byte[256];
    readonly byte[] mtf = new byte[256];
    readonly int[] anzahl = new int[256];
    readonly int[] cftab = new int[257];
    // Huffman-Gruppe beim Lesen der Symbole
    int gruppe, gRest, gmin, gAnzahl, gSel, gAlpha;
    int[] gl, gb, gp;
    // Zustand des laufenden Blocks
    int nblock, tPos, rest;
    int letzter = -1, gleich, wiederhol;
    uint blockCrc, sollCrc, stromCrc;
    bool imBlock, ende, halt;
    public long Ausgabe;

    public UzBz2Leser(Stream s) {
        ein = s;
        for (int i = 0; i < 6; i++) {
            laenge[i] = new byte[258];
            limit[i] = new int[24];
            basis[i] = new int[24];
            perm[i] = new int[258];
        }
        if (tab == null) {
            var t = new uint[256];
            for (uint i = 0; i < 256; i++) {
                uint c = i << 24;
                for (int k = 0; k < 8; k++) c = (c & 0x80000000u) != 0 ? (c << 1) ^ 0x04C11DB7u : c << 1;
                t[i] = c;
            }
            tab = t;
        }
        if (!Kopf()) throw F("kein bzip2-Archiv");
    }

    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position { get { return Ausgabe; } set { throw new NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long o, SeekOrigin w) { throw new NotSupportedException(); }
    public override void SetLength(long v) { throw new NotSupportedException(); }
    public override void Write(byte[] b, int o, int n) { throw new NotSupportedException(); }

    static UzXzFehler F(string m) { return new UzXzFehler("bzip2: " + m); }

    int Byte() {
        if (pp == pe) {
            pe = ein.Read(puffer, 0, puffer.Length);
            pp = 0;
            if (pe <= 0) {
                pe = 0;
                return -1;
            }
        }
        return puffer[pp++];
    }

    // n = 1..24 Bits, das höchste zuerst.
    uint Bits(int n) {
        while (nbits < n) {
            int b = Byte();
            if (b < 0) throw F("Archiv endet zu früh");
            bits = (bits << 8) | (uint)b;
            nbits += 8;
        }
        nbits -= n;
        return (uint)(bits >> nbits) & ((1u << n) - 1);
    }

    int Bit() {
        if (nbits == 0) {
            int b = Byte();
            if (b < 0) throw F("Archiv endet zu früh");
            bits = (bits << 8) | (uint)b;
            nbits = 8;
        }
        nbits--;
        return (int)(bits >> nbits) & 1;
    }

    uint Bits32() {
        uint h = Bits(16);
        return (h << 16) | Bits(16);
    }

    // Strom-Kopf „BZh1“ … „BZh9“ (Blockgröße 100 000 … 900 000).
    bool Kopf() {
        if (Bits(8) != 0x42 || Bits(8) != 0x5A || Bits(8) != 0x68) return false;
        int stufe = (int)Bits(8) - 0x30;
        if (stufe < 1 || stufe > 9) return false;
        maxBlock = stufe * 100000;
        if (tt == null || tt.Length < maxBlock) tt = new uint[maxBlock];
        stromCrc = 0;
        return true;
    }

    // Nach dem Ende eines Stroms: Schluss oder ein weiterer Strom (cat, pbzip2); alles andere ist kaputt.
    bool Weiter() {
        nbits -= nbits % 8;
        if (nbits == 0) {
            int b = Byte();
            if (b < 0) return false;
            bits = (bits << 8) | (uint)b;
            nbits = 8;
        }
        if (!Kopf()) throw F("Daten nach dem Ende");
        return true;
    }

    void Tabelle(int g, int alpha) {
        byte[] l = laenge[g];
        int[] li = limit[g], ba = basis[g], pe2 = perm[g];
        int min = 32, max = 0;
        for (int i = 0; i < alpha; i++) {
            if (l[i] > max) max = l[i];
            if (l[i] < min) min = l[i];
        }
        int p = 0;
        for (int i = min; i <= max; i++)
            for (int j = 0; j < alpha; j++)
                if (l[j] == i) pe2[p++] = j;
        Array.Clear(ba, 0, ba.Length);
        Array.Clear(li, 0, li.Length);
        for (int i = 0; i < alpha; i++) ba[l[i] + 1]++;
        for (int i = 1; i < ba.Length; i++) ba[i] += ba[i - 1];
        int vec = 0;
        for (int i = min; i <= max; i++) {
            vec += ba[i + 1] - ba[i];
            li[i] = vec - 1;
            vec <<= 1;
        }
        for (int i = min + 1; i <= max; i++) ba[i] = ((li[i - 1] + 1) << 1) - ba[i];
        minLaenge[g] = min;
    }

    // Nächstes Huffman-Symbol; alle 50 Symbole die Tabelle des nächsten Selektors.
    int Symbol() {
        if (gRest == 0) {
            if (++gruppe >= gSel) throw F("Tabellen kaputt");
            int s = selektor[gruppe];
            if (s >= gAnzahl) throw F("Tabellen kaputt");
            gl = limit[s];
            gb = basis[s];
            gp = perm[s];
            gmin = minLaenge[s];
            gRest = 50;
        }
        gRest--;
        int zn = gmin;
        int zvec = (int)Bits(zn);
        while (true) {
            if (zn > MAX_CODE) throw F("Code kaputt");
            if (zvec <= gl[zn]) break;
            zn++;
            zvec = (zvec << 1) | Bit();
        }
        int idx = zvec - gb[zn];
        if (idx < 0 || idx >= gAlpha) throw F("Code kaputt");
        return gp[idx];
    }

    // Liest den nächsten Block bis zur Rücktransformation; false am Ende aller Ströme.
    bool Block() {
        while (true) {
            uint m1 = Bits(24), m2 = Bits(24);
            if (m1 == 0x314159 && m2 == 0x265359) break;
            if (m1 != 0x177245 || m2 != 0x385090) throw F("Block kaputt");
            if (Bits32() != stromCrc) throw F("Prüfsumme des Stroms falsch");
            if (!Weiter()) return false;
        }
        sollCrc = Bits32();
        if (Bit() != 0) throw F("zufällige Blöcke werden nicht unterstützt");
        int ursprung = (int)Bits(24);
        int nZeichen = 0;
        uint benutzt = Bits(16);
        for (int i = 0; i < 16; i++) {
            if ((benutzt & (0x8000u >> i)) == 0) continue;
            uint u = Bits(16);
            for (int j = 0; j < 16; j++)
                if ((u & (0x8000u >> j)) != 0) zuByte[nZeichen++] = (byte)(i * 16 + j);
        }
        if (nZeichen == 0) throw F("Block ohne Zeichen");
        int alpha = nZeichen + 2;
        int nGruppen = (int)Bits(3);
        int nSel = (int)Bits(15);
        if (nGruppen < 2 || nGruppen > 6 || nSel < 1) throw F("Tabellen kaputt");
        var mtfG = new byte[] { 0, 1, 2, 3, 4, 5 };
        for (int i = 0; i < nSel; i++) {
            int j = 0;
            while (Bit() == 1)
                if (++j >= nGruppen) throw F("Tabellen kaputt");
            if (i >= MAX_SELEKTOREN) continue;              // überzählige Selektoren gelten nie (wie bzip2 1.0.8)
            byte v = mtfG[j];
            for (; j > 0; j--) mtfG[j] = mtfG[j - 1];
            mtfG[0] = v;
            selektor[i] = v;
        }
        if (nSel > MAX_SELEKTOREN) nSel = MAX_SELEKTOREN;
        for (int g = 0; g < nGruppen; g++) {
            int cur = (int)Bits(5);
            for (int i = 0; i < alpha; i++) {
                while (true) {
                    if (cur < 1 || cur > MAX_CODE) throw F("Tabellen kaputt");
                    if (Bit() == 0) break;
                    cur += Bit() == 0 ? 1 : -1;
                }
                laenge[g][i] = (byte)cur;
            }
            Tabelle(g, alpha);
        }
        // Symbole: MTF-Indizes mit Läufen (RUNA, RUNB), Ende mit EOB.
        for (int i = 0; i < 256; i++) {
            mtf[i] = (byte)i;
            anzahl[i] = 0;
        }
        int eob = nZeichen + 1;
        gruppe = -1;
        gRest = 0;
        gAnzahl = nGruppen;
        gSel = nSel;
        gAlpha = alpha;
        int n = 0;
        int sym = Symbol();
        while (sym != eob) {
            if (sym <= 1) {
                int lauf = 0, stelle = 1;
                do {
                    if (stelle >= (2 << 20)) throw F("Lauf zu lang");
                    lauf += (sym + 1) * stelle;
                    stelle <<= 1;
                    sym = Symbol();
                } while (sym <= 1);
                if (lauf > maxBlock - n) throw F("Block zu groß");
                byte b0 = zuByte[mtf[0]];
                anzahl[b0] += lauf;
                for (; lauf > 0; lauf--) tt[n++] = b0;
                continue;
            }
            if (n >= maxBlock) throw F("Block zu groß");
            int nn = sym - 1;
            byte v = mtf[nn];
            Array.Copy(mtf, 0, mtf, 1, nn);
            mtf[0] = v;
            byte b1 = zuByte[v];
            anzahl[b1]++;
            tt[n++] = b1;
            sym = Symbol();
        }
        if (ursprung >= n) throw F("Block kaputt");
        // Burrows-Wheeler rückwärts: tt[i] = Byte | (Nachfolger << 8).
        cftab[0] = 0;
        for (int i = 1; i <= 256; i++) cftab[i] = cftab[i - 1] + anzahl[i - 1];
        for (int i = 0; i < n; i++) {
            int c = (int)(tt[i] & 0xFF);
            tt[cftab[c]] |= (uint)i << 8;
            cftab[c]++;
        }
        nblock = n;
        tPos = (int)(tt[ursprung] >> 8);
        rest = n;
        blockCrc = 0xFFFFFFFFu;
        letzter = -1;
        gleich = 0;
        wiederhol = 0;
        return true;
    }

    // Liest den laufenden Block zu Ende (und prüft seine CRC) – nach der gesuchten Datei, ohne den Rest zu lesen.
    public void BlockAbschliessen() {
        var p = new byte[1 << 16];
        halt = true;
        try {
            while (imBlock && Read(p, 0, p.Length) > 0) { }
        } finally {
            halt = false;
        }
    }

    public override int Read(byte[] b, int o, int n) {
        if (b == null || o < 0 || n < 0 || o > b.Length - n) throw new ArgumentException();
        int got = 0;
        while (got < n && !ende) {
            if (wiederhol > 0) {
                int k = Math.Min(wiederhol, n - got);
                byte c = (byte)letzter;
                for (int i = 0; i < k; i++) {
                    b[o + got++] = c;
                    blockCrc = (blockCrc << 8) ^ tab[(blockCrc >> 24) ^ c];
                }
                wiederhol -= k;
                continue;
            }
            if (!imBlock) {
                if (halt) break;
                if (!Block()) {
                    ende = true;
                    break;
                }
                imBlock = true;
                continue;
            }
            if (rest == 0) {
                blockCrc = ~blockCrc;
                if (blockCrc != sollCrc) throw F("Prüfsumme des Blocks falsch");
                stromCrc = ((stromCrc << 1) | (stromCrc >> 31)) ^ blockCrc;
                imBlock = false;
                if (halt) break;
                continue;
            }
            if (tPos >= nblock) throw F("Block kaputt");
            uint e = tt[tPos];
            int ch = (int)(e & 0xFF);
            tPos = (int)(e >> 8);
            rest--;
            if (gleich == 4) {
                wiederhol = ch;
                gleich = 0;
                continue;
            }
            if (ch == letzter) gleich++;
            else {
                letzter = ch;
                gleich = 1;
            }
            b[o + got++] = (byte)ch;
            blockCrc = (blockCrc << 8) ^ tab[(blockCrc >> 24) ^ (uint)ch];
        }
        Ausgabe += got;
        if (Ausgabe > MAX_AUSGABE) throw F("Archiv zu groß");
        return got;
    }
}

// Sucht im tar-Strom eine Datei des Kerns und schreibt sie unter festem Namen in einen leeren Ordner.
public static class UzKernPack {
    public const int MAX_EINTRAEGE = 200000;
    public const long MAX_DATEI = 16L << 20;
    static readonly Regex Sauber = new Regex("^[A-Za-z0-9._+ /-]{1,300}\\z");
    // Wo sie liegen (echte Verteilungen, 156.0): Bootstrap in der minimal-Verteilung unter Release/, chrome_elf.dll
    // in der signierten gleich im Hauptordner (die signierte hat weder Release/ noch einen Bootstrap). Der Name des
    // Hauptordners ist nicht festgelegt (die signierte heißt nicht „cef_binary_…“, Nutzerprotokoll 0.16.27) – genau
    // eine Ebene darunter, nie aus Debug/.
    static readonly Regex[] Muster = { new Regex("^[^/]+/Release/bootstrap\\.exe\\z"), new Regex("^[^/]+/chrome_elf\\.dll\\z") };
    public static string Haupt = "";
    // Welche Datei aus welcher Verteilung: "minimal" → bootstrap.exe, "signiert" → chrome_elf.dll.
    public static readonly string[] Arten = { "minimal", "signiert" };
    static readonly Regex ExeDll = new Regex("(?i)\\.(exe|dll)\\z");
    // Für das Protokoll, falls etwas fehlt: welche Programme und Ordner im Archiv liegen (nur saubere Namen).
    public static readonly List<string> Gesehen = new List<string>();
    public static readonly HashSet<string> Ordner = new HashSet<string>();
    public static readonly string[] Namen = { "bootstrap.exe", "chrome_elf.dll" };
    public const int MIN_DATEI = 4096;
    public static int Eintraege;
    public static long Gelesen;

    // Ein Eintrag, den wir übernehmen würden: relativ, ohne „..“, ohne Laufwerk, Rückstrich oder Doppelpunkt.
    public static bool NameOk(string n) {
        if (n == null || n.StartsWith("/") || n.Contains("..") || n.Contains("\\") || n.Contains(":")) return false;
        return Sauber.IsMatch(n);
    }

    // Welcher der Einträge (0 Bootstrap, 1 chrome_elf.dll) – oder -1. Nur an der festen Stelle, nie aus Debug/.
    public static int Gesucht(string n) {
        for (int i = 0; i < Muster.Length; i++) if (Muster[i].IsMatch(n)) return i;
        return -1;
    }

    static string Text(byte[] h, int o, int n) {
        int e = o;
        while (e < o + n && h[e] != 0) e++;
        return Encoding.UTF8.GetString(h, o, e - o);
    }

    static long Oktal(byte[] h, int o, int n) {
        if ((h[o] & 0x80) != 0) {
            if ((h[o] & 0x40) != 0) throw new UzXzFehler("tar: Größe kaputt");
            long v = h[o] & 0x3F;
            for (int i = o + 1; i < o + n; i++) {
                if (v > (long.MaxValue >> 9)) throw new UzXzFehler("tar: Größe kaputt");
                v = (v << 8) | h[i];
            }
            return v;
        }
        long r = 0;
        int k = o;
        while (k < o + n && (h[k] == 0x20 || h[k] == 0)) k++;
        for (; k < o + n; k++) {
            int c = h[k];
            if (c == 0 || c == 0x20) break;
            if (c < 0x30 || c > 0x37 || r > (long.MaxValue >> 4)) throw new UzXzFehler("tar: Zahl kaputt");
            r = r * 8 + (c - 0x30);
        }
        return r;
    }

    static bool Lesen(Stream s, byte[] b, int n) {
        int o = 0;
        while (o < n) {
            int k = s.Read(b, o, n - o);
            if (k <= 0) {
                if (o == 0) return false;
                throw new UzXzFehler("tar: Archiv endet zu früh");
            }
            o += k;
        }
        Gelesen += n;
        return true;
    }

    static byte[] Daten(Stream s, long n, long max) {
        if (n < 0 || n > max) throw new UzXzFehler("tar: Kopfdaten zu groß");
        var b = new byte[(n + 511) & ~511L];
        if (b.Length > 0 && !Lesen(s, b, b.Length)) throw new UzXzFehler("tar: Archiv endet zu früh");
        var r = new byte[n];
        Buffer.BlockCopy(b, 0, r, 0, (int)n);
        return r;
    }

    static void Ueberspringen(Stream s, long n, byte[] puffer) {
        long rest = (n + 511) & ~511L;
        while (rest > 0) {
            int k = (int)Math.Min(rest, puffer.Length);
            if (!Lesen(s, puffer, k)) throw new UzXzFehler("tar: Archiv endet zu früh");
            rest -= k;
        }
    }

    // pax-Kopf („<länge> schlüssel=wert\n“ …): path und size; alles andere zählt nicht.
    static void Pax(byte[] d, ref string pfad, ref long groesse) {
        int o = 0;
        while (o < d.Length) {
            int sp = Array.IndexOf(d, (byte)0x20, o);
            if (sp < 0 || sp - o > 20) throw new UzXzFehler("tar: pax kaputt");
            int len;
            if (!int.TryParse(Encoding.ASCII.GetString(d, o, sp - o), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out len)
                    || len <= sp - o + 1 || o + len > d.Length || d[o + len - 1] != 0x0A) throw new UzXzFehler("tar: pax kaputt");
            string rec = Encoding.UTF8.GetString(d, sp + 1, o + len - sp - 2);
            int eq = rec.IndexOf('=');
            if (eq > 0) {
                string k = rec.Substring(0, eq), v = rec.Substring(eq + 1);
                long g;
                if (k == "path") pfad = v;
                else if (k == "size") {
                    if (!long.TryParse(v, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out g)) throw new UzXzFehler("tar: pax kaputt");
                    groesse = g;
                }
            }
            o += len;
        }
    }

    // Liest den tar-Strom, bis die gesuchte Datei (welche: 0, 1) da ist. "" oder der Grund (kurz, ohne Pfade).
    public static string Suchen(Stream s, string ziel, int gesucht) {
        Eintraege = 0;
        Gelesen = 0;
        var h = new byte[512];
        var puffer = new byte[1 << 16];
        Gesehen.Clear();
        Ordner.Clear();
        Haupt = "";
        string paxPfad = null, gnuName = null;
        long paxGroesse = -1;
        int nullen = 0;
        while (true) {
            if (!Lesen(s, h, 512)) break;
            bool leer = true;
            for (int i = 0; i < 512; i++) if (h[i] != 0) { leer = false; break; }
            if (leer) {
                if (++nullen >= 2) break;
                continue;
            }
            nullen = 0;
            long summe = 0;
            for (int i = 0; i < 512; i++) summe += (i >= 148 && i < 156) ? 0x20 : h[i];
            if (Oktal(h, 148, 8) != summe) return "tar: Kopf kaputt";
            if (++Eintraege > MAX_EINTRAEGE) return "tar: zu viele Einträge";
            char typ = (char)h[156];
            long groesse = Oktal(h, 124, 12);
            if (typ == 'x') {
                Pax(Daten(s, groesse, 1 << 20), ref paxPfad, ref paxGroesse);
                continue;
            }
            if (typ == 'g') {
                Ueberspringen(s, groesse, puffer);
                continue;
            }
            if (typ == 'L') {
                gnuName = Text(Daten(s, groesse, 65536), 0, (int)groesse);
                continue;
            }
            if (typ == 'K') {
                Ueberspringen(s, groesse, puffer);
                continue;
            }
            string name = paxPfad ?? gnuName;
            if (name == null) {
                name = Text(h, 0, 100);
                if (Text(h, 257, 5) == "ustar") {
                    string vor = Text(h, 345, 155);
                    if (vor != "") name = vor + "/" + name;
                }
            }
            if (paxGroesse >= 0) groesse = paxGroesse;
            paxPfad = null;
            gnuName = null;
            paxGroesse = -1;
            if (groesse < 0) return "tar: Größe kaputt";
            while (name.StartsWith("./")) name = name.Substring(2);
            if (Sauber.IsMatch(name)) {
                // Ohne den langen Hauptordner (cef_binary_…/): Ordner der zweiten Ebene und Programme.
                int sl = name.IndexOf('/');
                string kurz = sl >= 0 ? name.Substring(sl + 1) : name;
                if (Haupt == "" && sl > 0) Haupt = name.Substring(0, Math.Min(sl, 80));
                int sl2 = kurz.IndexOf('/');
                if (Ordner.Count < 40 && sl2 > 0) Ordner.Add(kurz.Substring(0, sl2));
                if (Gesehen.Count < 60 && ExeDll.IsMatch(name)) Gesehen.Add(kurz);
            }
            bool treffer = (typ == '0' || typ == '\0' || typ == '7') && Gesucht(name) == gesucht;
            if (!treffer) {
                Ueberspringen(s, groesse, puffer);
                continue;
            }
            if (!NameOk(name)) return "tar: Name kaputt";
            if (groesse > MAX_DATEI) return "tar: " + Namen[gesucht] + " zu groß";
            if (groesse < MIN_DATEI) return "tar: " + Namen[gesucht] + " zu klein";
            string pfad = Path.Combine(ziel, Namen[gesucht]);
            bool mz = false;
            var f = new FileStream(pfad, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            try {
                using (f) {
                    long rest = groesse;
                    while (rest > 0) {
                        int k = (int)Math.Min(rest, puffer.Length);
                        if (!Lesen(s, puffer, k)) throw new UzXzFehler("tar: Archiv endet zu früh");
                        if (rest == groesse) mz = puffer[0] == 0x4D && puffer[1] == 0x5A;
                        f.Write(puffer, 0, k);
                        rest -= k;
                    }
                }
                long pad = ((groesse + 511) & ~511L) - groesse;
                if (pad > 0 && !Lesen(s, puffer, (int)pad)) throw new UzXzFehler("tar: Archiv endet zu früh");
                // Den Block, in dem die Datei endet, zu Ende lesen: so ist auch seine Prüfsumme (CRC) geprüft.
                var bz = s as UzBz2Leser;
                if (bz != null) bz.BlockAbschliessen();
                var xz = s as UzXzLeser;
                if (xz != null) xz.BlockAbschliessen();
            } catch {
                // Was nicht ganz und geprüft ist, bleibt nicht liegen.
                try { File.Delete(pfad); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                throw;
            }
            if (!mz) {
                File.Delete(pfad);
                return "tar: " + Namen[gesucht] + " ist kein Programm";
            }
            return "";
        }
        return Namen[gesucht] + " fehlt im Archiv; Hauptordner: " + Haupt + "; Ordner: " + string.Join(", ", Ordner) + "; Programme: " + string.Join(", ", Gesehen);
    }

    // archiv: .tar.xz oder .tar.bz2 (nach Endung); ziel: ein leerer Ordner; art: "minimal" (Bootstrap) oder
    // "signiert" (chrome_elf.dll). "" oder der Grund (kurz, ohne Pfade).
    public static string Auslegen(string archiv, string ziel, string art) {
        int gesucht = Array.IndexOf(Arten, art);
        if (gesucht < 0) return "Art unbekannt";
        bool xz = archiv.EndsWith(".tar.xz", StringComparison.Ordinal);
        if (!xz && !archiv.EndsWith(".tar.bz2", StringComparison.Ordinal)) return "Format unbekannt";
        Eintraege = 0;
        Gelesen = 0;
        try {
            using (var f = new FileStream(archiv, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16))
            using (var b = new BufferedStream(f, 1 << 16))
            using (Stream x = xz ? (Stream)new UzXzLeser(b) : new UzBz2Leser(b)) {
                return Suchen(x, ziel, gesucht);
            }
        } catch (UzXzFehler e) {
            return e.Message;
        } catch (UnauthorizedAccessException) {
            return "Zugriff verweigert";
        } catch (IOException e) {
            return "Lesen/Schreiben: " + e.GetType().Name;
        } catch (OutOfMemoryException) {
            return "zu wenig Speicher";
        } catch (IndexOutOfRangeException) {
            return (xz ? "xz" : "bzip2") + ": Daten kaputt";
        }
    }
}
'@

## Text für Uzai und das Protokoll: ohne Benutzerpfad, ohne Steuerzeichen, kurz.
function Kern-Text([string]$t) {
    if ($null -eq $t) { return '' }
    $la = [string]$env:LOCALAPPDATA
    if ($la -ne '') { $t = $t.Replace($la, '%LOCALAPPDATA%') }
    $up = [string]$env:USERPROFILE
    if ($up -ne '') { $t = $t.Replace($up, '%USERPROFILE%') }
    $t = $t -replace '[\x00-\x1f\x7f]', ' '
    if ($t.Length -gt 240) { $t = $t.Substring(0, 240) }
    return $t
}

## Kopieren mit kurzem Warten, falls ein alter Kern die Datei noch hält. "" oder der Grund.
function Kern-Kopieren([string]$von, [string]$nach) {
    for ($i = 0; $i -lt 10; $i++) {
        try { [IO.File]::Copy($von, $nach, $true); return '' }
        catch [UnauthorizedAccessException] { return 'Zugriff verweigert: ' + [IO.Path]::GetFileName($nach) }
        catch [IO.IOException] { Start-Sleep -Milliseconds 600 }
    }
    return 'in Benutzung: ' + [IO.Path]::GetFileName($nach)
}

## Ein Archiv direkt in kern\<ordner> mit Namen nach Muster → voller Pfad, sonst ''.
function Kern-ArchivPfad([string]$pfad, [string]$ordner, [string]$muster) {
    if ($pfad.Length -gt 400 -or $pfad.Contains('..') -or $pfad.Contains('/')) { return '' }
    $voll = [IO.Path]::GetFullPath($pfad)
    if (-not $voll.StartsWith($ordner + '\', [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetDirectoryName($voll) -ne $ordner -or
        [IO.Path]::GetFileName($voll) -notmatch $muster) { return '' }
    return $voll
}

## Eine Datei mit UzKernPack holen (art: signiert → chrome_elf.dll, minimal → bootstrap.exe).
## @{ grund; info; liste } – grund '' bei Erfolg; liste: Ordner und Programme im Archiv, wenn die Datei fehlt.
function Kern-Entpacken([string]$voll, [string]$tmp, [string]$art) {
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    $grund = [UzKernPack]::Auslegen($voll, $tmp, $art)
    $info = '{0}: {1} Einträge, {2} MB in {3} s' -f $art, [UzKernPack]::Eintraege, [int]([UzKernPack]::Gelesen / 1MB), [int]$uhr.Elapsed.TotalSeconds
    $liste = ''
    $p = $grund.IndexOf('; ')
    if ($p -gt 0) {
        $liste = ($grund.Substring($p + 2) -replace '[\x00-\x1f\x7f]', ' ')
        if ($liste.Length -gt 1800) { $liste = $liste.Substring(0, 1800) }
        $grund = $grund.Substring(0, $p)
    }
    return @{ grund = $grund; info = $info; liste = $liste }
}

function Kern-Auslegen($a) {
    if ([UzElev]::IsElevated($PID)) { return @{ ok = $false; fehler = 'start'; schritt = 'admin'; text = 'mit Adminrechten gestartet' } }
    $schritt = 'archiv'
    $tmp = $null
    try {
        $wurzel = [IO.Path]::GetFullPath((Kern-Wurzel))
        $app = Join-Path $wurzel 'app'
        # Laufzeit (chrome_elf.dll) aus der signierten Verteilung im Spiegel, Bootstrap aus der minimal derselben Fassung.
        $voll = Kern-ArchivPfad ([string]$a.archiv) (Join-Path $wurzel 'spiegel') '^(cef_binary_[0-9.]+\+g[0-9a-f]{7}\+chromium-[0-9.]+_windows64)_signed\.tar\.xz$'
        $bvoll = Kern-ArchivPfad ([string]$a.boot) (Join-Path $wurzel 'boot') '^(cef_binary_[0-9.]+\+g[0-9a-f]{7}\+chromium-[0-9.]+_windows64)_minimal\.tar\.(bz2|xz)$'
        if ($voll -eq '' -or $bvoll -eq '') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'Pfad' } }
        if (([IO.Path]::GetFileName($voll) -replace '_signed\.tar\.xz$', '') -ne ([IO.Path]::GetFileName($bvoll) -replace '_minimal\.tar\.(bz2|xz)$', '')) {
            return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'andere Fassung' }
        }
        foreach ($p in @($voll, $bvoll)) {
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'Archiv fehlt' } }
        }
        $schritt = 'entpacken'
        if (-not ('UzKernPack' -as [type])) { Add-Type -TypeDefinition $script:KernPackSrc }
        $tmp = Join-Path $wurzel ('tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][IO.Directory]::CreateDirectory($tmp)
        $e = Kern-Entpacken $voll $tmp 'signiert'
        $info = $e.info
        if ($e.grund -ne '') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = (Kern-Text $e.grund); info = $info; liste = $e.liste } }
        $schritt = 'bootstrap'
        $e = Kern-Entpacken $bvoll $tmp 'minimal'
        $info += '; ' + $e.info
        if ($e.grund -ne '') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = (Kern-Text $e.grund); info = $info; liste = $e.liste } }
        # Vor dem Kopieren (danach laufen beide als uzai-kernladen.exe): chrome_elf.dll nur gültig vom CEF-Zertifikat,
        # der Bootstrap nur unsigniert oder ebenso. Die Kopien sind danach unsigniert (Signatur-Tabelle entfernt).
        $schritt = 'signatur'
        $elf = Get-AuthenticodeSignature -LiteralPath (Join-Path $tmp 'chrome_elf.dll')
        if ($elf.Status -ne 'Valid' -or -not $elf.SignerCertificate -or $elf.SignerCertificate.Thumbprint -ne $script:CefZertifikat) {
            return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'chrome_elf.dll nicht von CEF signiert'; info = $info }
        }
        $sig = Get-AuthenticodeSignature -LiteralPath (Join-Path $tmp 'bootstrap.exe')
        $bootSig = [string]$sig.Status
        if ($sig.SignerCertificate) { $bootSig += ' ' + $sig.SignerCertificate.Thumbprint.Substring(0, 8) }
        if ($sig.Status -ne 'NotSigned' -and ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Thumbprint -ne $script:CefZertifikat)) {
            return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'bootstrap.exe fremd signiert'; info = $info }
        }
        $schritt = 'kopieren'
        [void][IO.Directory]::CreateDirectory($app)
        $entsigniert = @()
        foreach ($paar in @(@('bootstrap.exe', 'uzai-browser.exe'), @('bootstrap.exe', 'uzai-kernladen.exe'), @('chrome_elf.dll', 'chrome_elf.dll'))) {
            $von = Join-Path $tmp $paar[0]
            $nach = Join-Path $app $paar[1]
            if (-not (Test-Path -LiteralPath $von -PathType Leaf)) { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = $paar[0] + ' fehlt' } }
            $g = Kern-Kopieren $von $nach
            if ($g -ne '') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = $g } }
            $schritt = 'signatur'
            if ((Get-AuthenticodeSignature -LiteralPath $nach).Status -ne 'NotSigned') {
                if (-not (Kern-SignaturEntfernen $nach)) { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'Signatur ' + $paar[1] } }
                $entsigniert += $paar[1]
            }
            if ((Get-AuthenticodeSignature -LiteralPath $nach).Status -ne 'NotSigned') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'Signatur ' + $paar[1] } }
            $schritt = 'kopieren'
        }
        $schritt = 'beilagen'
        $quelle = Join-Path $PSScriptRoot 'browser'
        $stummel = Join-Path $quelle 'uzai-browser-start.dll'
        if (-not (Test-Path -LiteralPath $stummel -PathType Leaf) -or (Browser-Hash $stummel) -ne $script:KernStummelSha) { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'Stummel' } }
        foreach ($n in @('uzai-browser.dll', 'uzai-kernladen.dll')) {
            $g = Kern-Kopieren $stummel (Join-Path $app $n)
            if ($g -ne '') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = $g } }
        }
        $filter = Join-Path $quelle 'filter.gz'
        if (-not (Test-Path -LiteralPath $filter -PathType Leaf) -or (Browser-Hash $filter) -ne $script:KernFilterSha) { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = 'Filter' } }
        $g = Kern-Kopieren $filter (Join-Path $app 'filter.gz')
        if ($g -ne '') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = $g } }
        foreach ($n in @('uzai-browser-karte.js', 'uzai-browser-filter.js', 'cookies.json')) {
            $p = Join-Path $quelle $n
            if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p).Length -gt 262144) { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = $n } }
            $g = Kern-Kopieren $p (Join-Path $app $n)
            if ($g -ne '') { return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = $g } }
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $wurzel 'store'))
        return @{ ok = $true; app = $app; entsigniert = $entsigniert; info = $info; boot_signatur = $bootSig }
    } catch {
        return @{ ok = $false; fehler = 'pruefung'; schritt = $schritt; text = (Kern-Text ($_.Exception.GetType().Name + ': ' + $_.Exception.Message)) }
    } finally {
        if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Kern-Bauen {
    if ([UzElev]::IsElevated($PID)) { return @{ ok = $false; fehler = 'start' } }
    $quelle = Join-Path $PSScriptRoot 'browser'
    $app = Join-Path (Kern-Wurzel) 'app'
    $dateien = @((Join-Path $quelle 'uzai-browser-gemeinsam.cs'), (Join-Path $quelle 'uzai-browser-kern.cs'))
    $teile = @()
    foreach ($p in $dateien) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p).Length -gt 4194304) { return @{ ok = $false; fehler = 'pruefung' } }
        $teile += (Browser-Hash $p)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    $fassung = (($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($teile -join ':')) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)
    New-Item -ItemType Directory -Force -Path $app | Out-Null
    $dll = Join-Path $app 'uzai-browser-kern.dll'
    $marke = Join-Path $app 'uzai-browser-kern.fassung'
    if ((Test-Path -LiteralPath $dll -PathType Leaf) -and (Test-Path -LiteralPath $marke -PathType Leaf) -and ((Get-Content -LiteralPath $marke -Raw).Trim() -eq $fassung)) {
        return @{ ok = $true; dll = $dll; fassung = $fassung }
    }
    $tmp = Join-Path $app 'uzai-browser-kern.neu.dll'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $cp = New-Object System.CodeDom.Compiler.CompilerParameters
    foreach ($r in @('System.dll', 'System.Core.dll')) { [void]$cp.ReferencedAssemblies.Add($r) }
    $cp.GenerateExecutable = $false
    $cp.GenerateInMemory = $false
    $cp.OutputAssembly = $tmp
    $cp.CompilerOptions = '/target:library /platform:x64 /optimize+'
    # Add-Type will die Bibliothek danach in diese Sitzung laden – egal, es zählt nur, dass die Datei gebaut ist.
    try { Add-Type -Path $dateien -CompilerParameters $cp -ErrorAction Stop } catch {}
    if (-not (Test-Path -LiteralPath $tmp -PathType Leaf)) { return @{ ok = $false; fehler = 'start' } }
    Move-Item -Force -LiteralPath $tmp -Destination $dll
    Set-Content -LiteralPath $marke -Value $fassung -NoNewline
    return @{ ok = $true; dll = $dll; fassung = $fassung }
}

## Die Konfiguration des CEF-Installers als Ressource in die Kopie uzai-browser.dll – Werte eng geprüft.
function Kern-Ressource($a) {
    if ([UzElev]::IsElevated($PID)) { return @{ ok = $false; fehler = 'start' } }
    $appid = [string]$a.appid
    $vmin = [string]$a.vmin
    $vmax = [string]$a.vmax
    $abi = [string]$a.abi
    if ($appid -notmatch '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') { return @{ ok = $false; fehler = 'pruefung'; text = 'appid' } }
    if ($vmin -notmatch '^[0-9]{2,4}(\.[0-9]{1,4}){1,2}$' -or ($vmax -ne '' -and $vmax -notmatch '^[0-9]{2,4}(\.[0-9]{1,4}){1,2}$')) { return @{ ok = $false; fehler = 'pruefung'; text = 'fassung' } }
    if ($abi -ne '' -and $abi -notmatch '^[0-9a-f]{16}$') { return @{ ok = $false; fehler = 'pruefung'; text = 'abi' } }
    $app = Join-Path (Kern-Wurzel) 'app'
    $dll = Join-Path $app 'uzai-browser.dll'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { return @{ ok = $false; fehler = 'pruefung'; text = 'dll' } }
    $json = @{ appid = $appid; vmin = $vmin; vmax = $vmax; abi_hash = $abi; install_path = (Join-Path (Kern-Wurzel) 'store'); launch_health = 'explicit';
        cdn_urls = @('https://cef-builds.spotifycdn.com/') } | ConvertTo-Json -Compress
    if (-not ('UzKernRes' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UzKernRes {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr BeginUpdateResourceW(string file, bool deleteExisting);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool UpdateResourceW(IntPtr h, IntPtr type, string name, ushort lang, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool EndUpdateResourceW(IntPtr h, bool discard);
    public static bool Schreiben(string datei, string name, byte[] daten) {
        IntPtr h = BeginUpdateResourceW(datei, false);
        if (h == IntPtr.Zero) return false;
        bool ok = UpdateResourceW(h, new IntPtr(10), name, 0, daten, (uint)daten.Length);
        return EndUpdateResourceW(h, !ok) && ok;
    }
}
'@
    }
    $ok = [UzKernRes]::Schreiben($dll, 'CEF_INSTALLER_CONFIG', [Text.Encoding]::UTF8.GetBytes($json))
    return @{ ok = $ok; fehler = $(if ($ok) { '' } else { 'start' }) }
}

# --- Windows-Einstellungen mit dem Controller (Roadmap 4/16) ------------------------------------
# Einstellungen → System → Windows und der Uzai-Doktor (src/core/win_einst.gd). Nur offizielle
# Schnittstellen mit den Rechten des Benutzers – läuft der Helfer als Administrator, lehnt er ab –,
# und jeder Befehl nur, weil jemand in Uzai einen Knopf gedrückt hat:
#   wlan-state       WLAN-Funk, Internet laut Windows, verbundenes Netz und die Netze der letzten
#                    Suche (scan = 1: neu suchen) über Windows.Devices.WiFi; gespeicherte Profile über
#                    die WLAN-Schnittstelle von Windows (WlanGetProfileList), nur lesen.
#   wlan-connect     mit einem Netz aus der Suche verbinden. SSID und BSSID sind nur Daten: Sie werden
#                    mit der Liste von Windows verglichen und landen nie in einer Kommandozeile. Ein
#                    Passwort (nur WPA/WPA2/WPA3-Personal: 8–63 druckbare Zeichen oder 64 Hex) geht als
#                    PasswordCredential direkt an Windows – der Helfer speichert und protokolliert es nie.
#                    Die Verbindung läuft im Hintergrund weiter, wlan-poll holt das Ergebnis.
#   wlan-disconnect  trennen.
#   radio-set        WLAN- oder Bluetooth-Funk an/aus (Windows.Devices.Radios).
#   bt-paired        gekoppelte Bluetooth-Geräte: Name, verbunden, Geräteklasse; nur lesen.
#   bt-unpair        ein gekoppeltes Gerät entfernen (DeviceInformationPairing.UnpairAsync). Kennung nach
#                    festem Muster, und Windows muss das Gerät noch einmal als gekoppelt melden.
#   power-times      Bildschirm aus, Schlafen, Ruhezustand nach … (UzPerf.Times, nur lesen).
#   power-time-set   dasselbe setzen: powercfg mit fester Argumentliste, Werte nur aus einer festen Liste.
# Ein Verbinden oder Trennen einzelner Bluetooth-Geräte gibt es für Programme nicht offiziell; das
# erklärt Uzai, statt es nachzubauen. Sperren und Abmelden gibt es hier bewusst nicht.
$script:WlanReady = $false
$script:WlanAdapter = $null
$script:WlanJob = $null
$script:WlanJobMaxS = 45
$script:BtPairedProps = @('System.Devices.Aep.IsConnected', 'System.Devices.Aep.Bluetooth.Cod.Major',
    'System.Devices.Aep.Bluetooth.Cod.Minor', 'System.Devices.Aep.Bluetooth.Le.Appearance')
# powercfg-Schalter je Einstellung und Stromquelle – nur diese Wörter gehen als Argument hinaus.
$script:PowerSwitch = @{
    'monitor|ac' = 'monitor-timeout-ac'; 'monitor|dc' = 'monitor-timeout-dc'
    'sleep|ac' = 'standby-timeout-ac'; 'sleep|dc' = 'standby-timeout-dc'
    'hibernate|ac' = 'hibernate-timeout-ac'; 'hibernate|dc' = 'hibernate-timeout-dc'
}
# Minuten wie in den Windows-Einstellungen (0 = nie); dieselbe Liste steht in win_einst.gd.
$script:PowerMinutes = @(0, 1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 120, 180, 240, 300)

# Gespeicherte WLAN-Profile (Namen, meist die SSID), höchstens 64; nur lesen. Größen der Einträge
# wie in wlanapi.h: WLAN_INTERFACE_INFO 532 Bytes, WLAN_PROFILE_INFO 516 Bytes, je Liste 8 Bytes Kopf.
$script:WlanSrc = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class UzWlan {
    [DllImport("wlanapi.dll")] static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr handle);
    [DllImport("wlanapi.dll")] static extern uint WlanCloseHandle(IntPtr handle, IntPtr reserved);
    [DllImport("wlanapi.dll")] static extern uint WlanEnumInterfaces(IntPtr handle, IntPtr reserved, out IntPtr list);
    [DllImport("wlanapi.dll")] static extern uint WlanGetProfileList(IntPtr handle, ref Guid iface, IntPtr reserved, out IntPtr list);
    [DllImport("wlanapi.dll")] static extern void WlanFreeMemory(IntPtr p);

    const int IFACE = 532;
    const int PROFILE = 516;
    const int MAX = 64;

    public static string[] Profiles() {
        var names = new List<string>();
        IntPtr h;
        uint neg;
        if (WlanOpenHandle(2, IntPtr.Zero, out neg, out h) != 0) return names.ToArray();
        try {
            IntPtr ifaces;
            if (WlanEnumInterfaces(h, IntPtr.Zero, out ifaces) != 0) return names.ToArray();
            try {
                int n = Math.Min(8, Marshal.ReadInt32(ifaces));
                for (int i = 0; i < n; i++) {
                    var g = (Guid)Marshal.PtrToStructure(new IntPtr(ifaces.ToInt64() + 8 + (long)i * IFACE), typeof(Guid));
                    IntPtr list;
                    if (WlanGetProfileList(h, ref g, IntPtr.Zero, out list) != 0) continue;
                    try {
                        int m = Marshal.ReadInt32(list);
                        for (int j = 0; j < m && names.Count < MAX; j++) {
                            string s = Marshal.PtrToStringUni(new IntPtr(list.ToInt64() + 8 + (long)j * PROFILE), 256);
                            int z = s.IndexOf('\0');
                            if (z >= 0) s = s.Substring(0, z);
                            if (s.Length > 0 && !names.Contains(s)) names.Add(s);
                        }
                    } finally { WlanFreeMemory(list); }
                }
            } finally { WlanFreeMemory(ifaces); }
        } finally { WlanCloseHandle(h, IntPtr.Zero); }
        return names.ToArray();
    }
}
'@

function Use-Wlan {
    if ($script:WlanReady) { return }
    Use-WinRt
    $null = [Windows.Devices.WiFi.WiFiAdapter, Windows.Devices.WiFi, ContentType = WindowsRuntime]
    $null = [Windows.Security.Credentials.PasswordCredential, Windows.Security.Credentials, ContentType = WindowsRuntime]
    $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
    $null = [Windows.Devices.Radios.Radio, Windows.Devices.Radios, ContentType = WindowsRuntime]
    $script:AsTaskAct = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
    Add-Type -TypeDefinition $script:WlanSrc
    $script:WlanReady = $true
}

# SSID: Text mit 1–32 Bytes (UTF-8), ohne Steuerzeichen. Nie Teil einer Kommandozeile – nur verglichen.
function Test-Ssid($s) {
    if ($null -eq $s -or -not ($s -is [string])) { return $false }
    if ($s.Length -lt 1 -or [Text.Encoding]::UTF8.GetByteCount($s) -gt 32) { return $false }
    foreach ($ch in $s.ToCharArray()) { if ([int]$ch -lt 32 -or [int]$ch -eq 127) { return $false } }
    return $true
}

function Test-Bssid($b) {
    return ($b -is [string]) -and [regex]::IsMatch($b, '\A([0-9a-f]{2}:){5}[0-9a-f]{2}\z')
}

# WPA-Passwort: 8–63 druckbare ASCII-Zeichen oder genau 64 Hex-Ziffern.
function Test-WlanKey($k) {
    if ($null -eq $k -or -not ($k -is [string])) { return $false }
    if ($k.Length -eq 64) { return [regex]::IsMatch($k, '\A[0-9A-Fa-f]{64}\z') }
    if ($k.Length -lt 8 -or $k.Length -gt 63) { return $false }
    foreach ($ch in $k.ToCharArray()) { if ([int]$ch -lt 32 -or [int]$ch -gt 126) { return $false } }
    return $true
}

# Art eines Netzes aus NetworkAuthenticationType und NetworkEncryptionType: offen (auch OWE), psk
# (Passwort), firma (802.1X – einrichten in Windows), wep (zu unsicher) oder anders.
function Get-WlanKind([int]$auth, [int]$enc) {
    if ($auth -eq 0 -or $auth -eq 2) {
        if ($enc -ge 2 -and $enc -le 4) { return 'wep' }
        return 'offen'
    }
    if ($auth -eq 12) { return 'offen' }
    if ($auth -eq 3) { return 'wep' }
    if ($auth -eq 5 -or $auth -eq 8 -or $auth -eq 11) { return 'psk' }
    if ($auth -eq 4 -or $auth -eq 7 -or $auth -eq 10 -or $auth -eq 13) { return 'firma' }
    return 'anders'
}

# WiFiConnectionStatus → Uzais Schlüssel (src/core/win_einst.gd).
function Get-WlanResult([int]$st) {
    switch ($st) {
        1 { return 'verbunden' }
        2 { return 'abgelehnt' }
        3 { return 'passwort' }
        4 { return 'weg' }
        5 { return 'zeit' }
        6 { return 'anders' }
    }
    return 'fehler'
}

function Get-RadioList([string]$kind) {
    $want = [Windows.Devices.Radios.RadioKind]::Bluetooth
    if ($kind -ceq 'wlan') { $want = [Windows.Devices.Radios.RadioKind]::WiFi }
    $list = Await-OpMs ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]]) 5000
    return @($list | Where-Object { $_.Kind -eq $want })
}

# „an“, „aus“ oder „kein“ (kein Funk dieser Art).
function Get-RadioState([string]$kind) {
    $r = @(Get-RadioList $kind)
    if ($r.Count -eq 0) { return 'kein' }
    if (@($r | Where-Object { $_.State -eq [Windows.Devices.Radios.RadioState]::On }).Count -gt 0) { return 'an' }
    return 'aus'
}

function Get-WlanAdapter([bool]$fresh) {
    if ($null -ne $script:WlanAdapter -and -not $fresh) { return $script:WlanAdapter }
    $list = Await-OpMs ([Windows.Devices.WiFi.WiFiAdapter]::FindAllAdaptersAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.WiFi.WiFiAdapter]]) 5000
    $script:WlanAdapter = $null
    foreach ($x in $list) { $script:WlanAdapter = $x; break }
    return $script:WlanAdapter
}

# Darf Uzai WLANs suchen? Ab Windows 11 24H2 hängt das an „Standort“ für Desktop-Apps.
function Get-WlanAccess {
    $st = Await-OpMs ([Windows.Devices.WiFi.WiFiAdapter]::RequestAccessAsync()) ([Windows.Devices.WiFi.WiFiAccessStatus]) 5000
    switch ([int]$st) {
        1 { return 'ok' }
        2 { return 'nutzer' }
        3 { return 'system' }
    }
    return 'unbekannt'
}

function Get-WlanConnected($ad) {
    try {
        $p = Await-OpMs ($ad.NetworkAdapter.GetConnectedProfileAsync()) ([Windows.Networking.Connectivity.ConnectionProfile]) 4000
        if ($null -ne $p -and $p.IsWlanConnectionProfile) { return [string]$p.WlanConnectionProfileDetails.GetConnectedSsid() }
    } catch { }
    return ''
}

# Internet laut Windows: „ok“, „lokal“ (nur Heimnetz oder eingeschränkt) oder „keins“.
function Get-InternetState {
    try {
        $p = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
        if ($null -eq $p) { return 'keins' }
        $lvl = [int]$p.GetNetworkConnectivityLevel()
        if ($lvl -eq 3) { return 'ok' }
        if ($lvl -eq 0) { return 'keins' }
        return 'lokal'
    } catch { }
    return ''
}

function Find-WlanNetwork($ad, [string]$ssid, [string]$bssid) {
    foreach ($n in $ad.NetworkReport.AvailableNetworks) {
        if (([string]$n.Bssid).ToLowerInvariant() -ceq $bssid -and [string]$n.Ssid -ceq $ssid) { return $n }
    }
    return $null
}

function Wlan-Scan($ad) {
    $t = $script:AsTaskAct.Invoke($null, @($ad.ScanAsync()))
    [void]$t.Wait(6000)
}

function Wlan-State($a) {
    if (Test-BtAdmin) { return @{ code = 'admin' } }
    try { Use-Wlan } catch { return @{ code = 'kein' } }
    $scan = (Get-Num $a.scan 1) -eq 1
    $radio = 'kein'
    try { $radio = Get-RadioState 'wlan' } catch { }
    $out = @{ code = 'ok'; radio = $radio; internet = (Get-InternetState); connected = ''; access = ''; networks = @(); busy = ($null -ne $script:WlanJob) }
    $ad = $null
    try { $ad = Get-WlanAdapter $scan } catch { }
    if ($null -eq $ad) { $out.code = 'kein'; return $out }
    $out.connected = Get-WlanConnected $ad
    if ($radio -eq 'aus') { $out.code = 'aus'; return $out }
    if ($scan) {
        $acc = 'unbekannt'
        try { $acc = Get-WlanAccess } catch { }
        $out.access = $acc
        if ($acc -ne 'ok') { $out.code = 'zugriff'; return $out }
        try { Wlan-Scan $ad } catch { }
    }
    $known = @()
    try { $known = @([UzWlan]::Profiles()) } catch { }
    $nets = @()
    try {
        foreach ($n in $ad.NetworkReport.AvailableNetworks) {
            if ($nets.Count -ge 60) { break }
            $ssid = [string]$n.Ssid
            $bssid = ([string]$n.Bssid).ToLowerInvariant()
            if (-not (Test-Ssid $ssid) -or -not (Test-Bssid $bssid)) { continue }
            $sec = $n.SecuritySettings
            $nets += @{ ssid = $ssid; bssid = $bssid; bars = [int]$n.SignalBars; known = ($known -ccontains $ssid)
                kind = (Get-WlanKind ([int]$sec.NetworkAuthenticationType) ([int]$sec.NetworkEncryptionType))
                ghz = [int][Math]::Round([double]$n.ChannelCenterFrequencyInKilohertz / 1000000.0) }
        }
    } catch { }
    $out.networks = $nets
    return $out
}

function Wlan-Connect($a) {
    # Erst die Daten (nur Text gegen feste Regeln), dann erst Windows.
    $ssid = $a.ssid
    $bssid = $a.bssid
    if (-not (Test-Ssid $ssid) -or -not (Test-Bssid $bssid)) { return @{ code = 'daten' } }
    $key = $a.password
    if ($null -ne $key) { $a.password = $null }
    $hasKey = $null -ne $key
    if ($hasKey -and -not (Test-WlanKey $key)) { return @{ code = 'passwort' } }
    if (Test-BtAdmin) { return @{ code = 'admin' } }
    if ($null -ne $script:WlanJob) { return @{ code = 'laeuft' } }
    try { Use-Wlan } catch { return @{ code = 'kein' } }
    $ad = $null
    try { $ad = Get-WlanAdapter $false } catch { }
    if ($null -eq $ad) { return @{ code = 'kein' } }
    $net = Find-WlanNetwork $ad $ssid $bssid
    if ($null -eq $net) {
        try { Wlan-Scan $ad } catch { }
        $net = Find-WlanNetwork $ad $ssid $bssid
    }
    if ($null -eq $net) { return @{ code = 'weg' } }
    $sec = $net.SecuritySettings
    $kind = Get-WlanKind ([int]$sec.NetworkAuthenticationType) ([int]$sec.NetworkEncryptionType)
    if ($kind -cne 'offen' -and $kind -cne 'psk') { return @{ code = $kind } }
    if ($kind -ceq 'offen' -and $hasKey) { return @{ code = 'daten' } }
    $known = $false
    try { $known = @([UzWlan]::Profiles()) -ccontains $ssid } catch { }
    if ($kind -ceq 'psk' -and -not $hasKey -and -not $known) { return @{ code = 'passwort' } }
    $how = [Windows.Devices.WiFi.WiFiReconnectionKind]::Automatic
    if ((Get-Num $a.auto 1) -eq 0) { $how = [Windows.Devices.WiFi.WiFiReconnectionKind]::Manual }
    if ($hasKey) {
        $cred = New-Object Windows.Security.Credentials.PasswordCredential
        $cred.Password = [string]$key
        $op = $ad.ConnectAsync($net, $how, $cred)
        $cred = $null
    } else {
        $op = $ad.ConnectAsync($net, $how)
    }
    $key = $null
    $task = $script:AsTaskOp.MakeGenericMethod([Windows.Devices.WiFi.WiFiConnectionResult]).Invoke($null, @($op))
    $script:WlanJob = @{ task = $task; t0 = [DateTime]::UtcNow }
    return @{ code = 'gestartet' }
}

function Wlan-Poll {
    $j = $script:WlanJob
    if ($null -eq $j) { return @{ code = 'nichts' } }
    if (-not $j.task.IsCompleted) {
        if (([DateTime]::UtcNow - $j.t0).TotalSeconds -lt $script:WlanJobMaxS) { return @{ code = 'laeuft' } }
        $script:WlanJob = $null
        return @{ code = 'zeit' }
    }
    $script:WlanJob = $null
    if ($j.task.IsFaulted -or $j.task.IsCanceled) { return @{ code = 'fehler' } }
    return @{ code = (Get-WlanResult ([int]$j.task.Result.ConnectionStatus)) }
}

function Wlan-Disconnect {
    if (Test-BtAdmin) { return @{ code = 'admin' } }
    try { Use-Wlan } catch { return @{ code = 'kein' } }
    $ad = $null
    try { $ad = Get-WlanAdapter $false } catch { }
    if ($null -eq $ad) { return @{ code = 'kein' } }
    $ad.Disconnect()
    return @{ code = 'getrennt' }
}

function Radio-Set($a) {
    $kind = $a.kind
    $on = Get-Num $a.on 1
    if (-not ($kind -is [string]) -or ($kind -cne 'wlan' -and $kind -cne 'bt') -or $on -lt 0) { return @{ code = 'daten' } }
    if (Test-BtAdmin) { return @{ code = 'admin' } }
    try { Use-Wlan } catch { return @{ code = 'kein' } }
    $acc = Await-OpMs ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus]) 5000
    if ([int]$acc -ne 1) { return @{ code = 'zugriff' } }
    $radios = @(Get-RadioList $kind)
    if ($radios.Count -eq 0) { return @{ code = 'kein' } }
    $want = [Windows.Devices.Radios.RadioState]::Off
    if ($on -eq 1) { $want = [Windows.Devices.Radios.RadioState]::On }
    $res = 1
    foreach ($r in $radios) {
        $res = [int](Await-OpMs ($r.SetStateAsync($want)) ([Windows.Devices.Radios.RadioAccessStatus]) 8000)
        if ($res -ne 1) { break }
    }
    $code = 'ok'
    if ($res -ne 1) { $code = 'zugriff' }
    return @{ code = $code; state = (Get-RadioState $kind) }
}

function Bt-Paired {
    if (Test-BtAdmin) { return @{ code = 'admin'; devices = @() } }
    try { Use-Bt } catch { return @{ code = 'kein'; devices = @() } }
    $radio = 'kein'
    try { $radio = Get-BtRadio } catch { }
    if ($radio -eq 'kein') { return @{ code = 'kein'; devices = @() } }
    $kind = [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint
    $out = @()
    foreach ($sel in @([Windows.Devices.Bluetooth.BluetoothDevice]::GetDeviceSelectorFromPairingState($true),
            [Windows.Devices.Bluetooth.BluetoothLEDevice]::GetDeviceSelectorFromPairingState($true))) {
        $found = $null
        try { $found = Await-OpMs ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($sel, [string[]]$script:BtPairedProps, $kind)) ([Windows.Devices.Enumeration.DeviceInformationCollection]) 6000 } catch { }
        if ($null -eq $found) { continue }
        foreach ($d in $found) {
            if ($out.Count -ge 32) { break }
            $id = [string]$d.Id
            if (-not (Test-BtId $id)) { continue }
            $con = $false
            try { $con = [bool]$d.Properties['System.Devices.Aep.IsConnected'] } catch { }
            $out += @{ id = $id; name = ([string]$d.Name); connected = $con; major = (Get-BtProp $d 'System.Devices.Aep.Bluetooth.Cod.Major')
                minor = (Get-BtProp $d 'System.Devices.Aep.Bluetooth.Cod.Minor'); appearance = (Get-BtProp $d 'System.Devices.Aep.Bluetooth.Le.Appearance') }
        }
    }
    return @{ code = $radio; devices = $out }
}

function Bt-Unpair($a) {
    $id = $a.id
    if (-not (Test-BtId $id)) { return @{ code = 'kennung' } }
    if (Test-BtAdmin) { return @{ code = 'admin' } }
    try { Use-Bt } catch { return @{ code = 'kein' } }
    $dev = $null
    try {
        $dev = Await-OpMs ([Windows.Devices.Enumeration.DeviceInformation]::CreateFromIdAsync([string]$id, [string[]]$script:BtPairedProps,
            [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint)) ([Windows.Devices.Enumeration.DeviceInformation]) 8000
    } catch { $dev = $null }
    if ($null -eq $dev) { return @{ code = 'fehlt' } }
    if (-not $dev.Pairing.IsPaired) { return @{ code = 'schon' } }
    $res = Await-OpMs ($dev.Pairing.UnpairAsync()) ([Windows.Devices.Enumeration.DeviceUnpairingResult]) 15000
    switch ([int]$res.Status) {
        0 { return @{ code = 'entfernt' } }
        1 { return @{ code = 'schon' } }
        3 { return @{ code = 'abgelehnt' } }
    }
    return @{ code = 'fehler' }
}

# Gerätename aus dem BIOS (Handhelds erkennen, src/core/handheld.gd): nur lesen, feste Werte,
# jeder Text gekürzt. Nichts davon verlässt den PC.
function Get-GeraetInfo {
    try { $p = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction Stop } catch { return @{ ok = $false } }
    $o = @{ ok = $true }
    foreach ($k in @(@('maker', 'SystemManufacturer'), @('product', 'SystemProductName'), @('family', 'SystemFamily'), @('version', 'SystemVersion'))) {
        $v = [string]$p.($k[1])
        if ($v.Length -gt 64) { $v = $v.Substring(0, 64) }
        $o[$k[0]] = $v
    }
    return $o
}

function Power-TimeSet($a) {
    $what = $a.what
    $src = $a.src
    $min = Get-Num $a.min 300
    if (-not ($what -is [string]) -or -not ($src -is [string])) { return @{ code = 'daten' } }
    $switch = $script:PowerSwitch[($what + '|' + $src)]
    if ($null -eq $switch -or -not ($script:PowerMinutes -contains $min)) { return @{ code = 'daten' } }
    if (Test-BtAdmin) { return @{ code = 'admin' } }
    $exe = ''
    if ($env:SystemRoot) { $exe = Join-Path $env:SystemRoot 'System32\powercfg.exe' }
    if ($exe -eq '' -or -not (Test-Path -LiteralPath $exe)) { return @{ code = 'kein' } }
    $null = & $exe '/change' $switch ([string]$min) 2>&1
    if ($LASTEXITCODE -ne 0) { return @{ code = 'abgelehnt' } }
    return @{ code = 'ok' }
}

# --- Controller koppeln (Punkt 133) -------------------------------------------------------------
# Nur über die offizielle Windows-Schnittstelle (Windows.Devices.Enumeration, Windows.Devices.Bluetooth,
# Windows.Devices.Radios): keine Treiber, keine Registry, keine Systemeinstellung. Bluetooth selbst
# schaltet Uzai nie ein oder aus – ist es aus, sagt der Helfer das nur. Beides läuft als eigener
# Prozess (-Once, src/ui/layers/pad_pair.gd), nie mit Adminrechten.
#   bt-scan: sucht aktiv (DeviceWatcher mit Bluetooth-Abfrage „IssueInquiry“, klassisch und LE) und meldet nur
#            Controller: Bluetooth-Peripherie mit Joystick/Gamepad, LE-Erscheinungsbild Joystick/Gamepad, und – nur wenn
#            Windows die Klasse nicht kennt – ein Name wie „Controller“/„Gamepad“. Auch schon gekoppelte (gekoppelt,
#            verbunden), damit Uzai „gekoppelt, aber nicht verbunden“ zeigen kann – die Windows-Einstellungen zeigen
#            solche Geräte und manche Controller gar nicht (Bluetooth-Geräteerkennung „Standard“).
#   bt-pair: koppelt genau ein Gerät. Die Kennung kommt von Uzai und muss genau dem Windows-Format
#            entsprechen (Test-BtId); dann liest der Helfer das Gerät selbst noch einmal und koppelt nur,
#            wenn es wirklich ein ungekoppeltes Gamepad ist. Nur „Bestätigen“ ohne PIN: Will ein Gerät
#            eine PIN, lehnt der Helfer ab, statt ein Windows-Fenster zu öffnen. neu = 1 (nur auf ausdrücklichen
#            Wunsch, „Neu koppeln“): eine alte Kopplung desselben Controllers erst entfernen, dann koppeln.
#            Klappt es nicht auf Anhieb (Zeit, nicht bereit), einmal nachfassen.
$script:BtIdRe = '\ABluetooth(LE)?#Bluetooth(LE)?([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}-([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\z'
$script:BtProps = @('System.Devices.Aep.Bluetooth.Cod.Major', 'System.Devices.Aep.Bluetooth.Cod.Minor',
    'System.Devices.Aep.Bluetooth.Le.Appearance', 'System.Devices.Aep.SignalStrength')
$script:BtSucheProps = @('System.Devices.Aep.Bluetooth.Cod.Major', 'System.Devices.Aep.Bluetooth.Cod.Minor',
    'System.Devices.Aep.Bluetooth.Le.Appearance', 'System.Devices.Aep.SignalStrength', 'System.Devices.Aep.IsPaired', 'System.Devices.Aep.IsConnected',
    'System.Devices.Aep.IsPresent', 'System.Devices.Aep.CanPair', 'System.ItemNameDisplay')
# AQS: klassisches Bluetooth mit aktiver Abfrage (sonst nur, was Windows ohnehin im Speicher hat) und Bluetooth LE.
$script:BtAqs = @(
    @('System.Devices.Aep.ProtocolId:="{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}" AND System.Devices.Aep.Bluetooth.IssueInquiry:=System.StructuredQueryType.Boolean#True',
        'System.Devices.Aep.ProtocolId:="{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}"'),
    @('System.Devices.Aep.ProtocolId:="{bb7bb05e-5972-42b5-94fc-76eaa7084d49}"'))
$script:BtSucheReady = $false
$script:BtReady = $false
# Nimmt die Kopplungsanfrage von Windows an – nur „Bestätigen“ (DevicePairingKinds.ConfirmOnly = 1).
# Ohne Verweis auf WinRT übersetzt: Windows ruft OnRequest über einen Delegaten mit den echten
# Typen auf (die Parameter hier sind object), gelesen wird per Reflection. Läuft in einem Faden von
# Windows, nicht in PowerShell.
$script:BtSrc = @'
using System;
using System.Reflection;
public static class UzBtPair {
    public static volatile int LastKind = 0;
    public static void OnRequest(object sender, object args) {
        try {
            Type t = args.GetType();
            PropertyInfo p = t.GetProperty("PairingKind");
            int kind = p == null ? 0 : Convert.ToInt32(p.GetValue(args, null));
            LastKind = kind;
            if (kind != 1) return;
            MethodInfo m = t.GetMethod("Accept", Type.EmptyTypes);
            if (m != null) m.Invoke(args, null);
        } catch (Exception) { }
    }
}
'@
$script:BtSucheSrc = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;

// Sammelt, was die Gerätesuche von Windows (DeviceWatcher, Windows.Devices.Enumeration) meldet: Hinzugekommen,
// Geändert, Weg. Ohne Verweis auf WinRT übersetzt: Windows ruft die Methoden über Delegaten mit den echten Typen
// auf (die Parameter hier sind object), gelesen wird per Reflection. Läuft in Fäden von Windows, nicht in PowerShell –
// darum alles unter einer Sperre und ohne PowerShell-Code. Nur lesen: Name, Kennung und feste Eigenschaften.
public static class UzBtSuche {
    public const int MAX_GERAETE = 256;
    public const int MAX_NAME = 80;
    static readonly object sperre = new object();
    static readonly Dictionary<string, Hashtable> geraete = new Dictionary<string, Hashtable>();
    public static volatile int Fertig = 0;
    public static volatile int Meldungen = 0;

    // Eigenschaft → Feld (Zahl oder Ja/Nein).
    static readonly string[,] FELDER = {
        { "System.Devices.Aep.Bluetooth.Cod.Major", "major" }, { "System.Devices.Aep.Bluetooth.Cod.Minor", "minor" },
        { "System.Devices.Aep.Bluetooth.Le.Appearance", "appearance" }, { "System.Devices.Aep.SignalStrength", "signal" },
        { "System.Devices.Aep.IsPaired", "paired" }, { "System.Devices.Aep.IsConnected", "connected" }, { "System.Devices.Aep.IsPresent", "present" },
        { "System.Devices.Aep.CanPair", "canpair" },
    };

    public static void Leeren() {
        lock (sperre) { geraete.Clear(); }
        Fertig = 0;
        Meldungen = 0;
    }

    static object Wert(object o, string name) {
        if (o == null) return null;
        try {
            PropertyInfo p = o.GetType().GetProperty(name);
            return p == null ? null : p.GetValue(o, null);
        } catch (Exception) { return null; }
    }

    static string Sauber(object v, int max) {
        string s = v as string;
        if (s == null) return "";
        var b = new System.Text.StringBuilder();
        foreach (char c in s) {
            if (c < 0x20 || c == 0x7F || (c >= 0x80 && c < 0xA0) || (c >= 0x200E && c <= 0x200F) || (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069)) continue;
            b.Append(c);
            if (b.Length >= max) break;
        }
        return b.ToString().Trim();
    }

    static object Zahl(object v) {
        if (v == null) return null;
        if (v is bool) return (bool)v;
        try { return Convert.ToInt32(v, System.Globalization.CultureInfo.InvariantCulture); } catch (Exception) { return null; }
    }

    // Eigenschaften (IReadOnlyDictionary<string, object> bzw. IMapView) in das Gerät übernehmen.
    static void Uebernehmen(Hashtable g, object props) {
        var d = props as IReadOnlyDictionary<string, object>;
        var alt = props as IDictionary;
        for (int i = 0; i < FELDER.GetLength(0); i++) {
            object v = null;
            bool da = false;
            if (d != null) da = d.TryGetValue(FELDER[i, 0], out v);
            else if (alt != null && alt.Contains(FELDER[i, 0])) { v = alt[FELDER[i, 0]]; da = true; }
            if (!da || v == null) continue;
            object z = Zahl(v);
            if (z == null) continue;
            string f = FELDER[i, 1];
            if (f == "paired" || f == "connected" || f == "present" || f == "canpair") g[f] = (z is bool) ? (bool)z : ((int)z != 0);
            else g[f] = z is bool ? ((bool)z ? 1 : 0) : (int)z;
        }
        object name = null;
        if (d != null) d.TryGetValue("System.ItemNameDisplay", out name);
        string n = Sauber(name, MAX_NAME);
        if (n != "") g["name"] = n;
    }

    static Hashtable Neues(string id) {
        var g = new Hashtable();
        g["id"] = id;
        g["name"] = "";
        g["major"] = 0;
        g["minor"] = 0;
        g["appearance"] = 0;
        g["signal"] = -100;
        g["paired"] = false;
        g["connected"] = false;
        g["present"] = true;
        g["canpair"] = false;
        return g;
    }

    // DeviceWatcher.Added: DeviceInformation (Id, Name, Properties, Pairing).
    public static void Neu(object sender, object info) {
        try {
            string id = Wert(info, "Id") as string;
            if (id == null || id.Length > 120) return;
            lock (sperre) {
                Hashtable g;
                if (!geraete.TryGetValue(id, out g)) {
                    if (geraete.Count >= MAX_GERAETE) return;
                    g = Neues(id);
                    geraete[id] = g;
                }
                string n = Sauber(Wert(info, "Name"), MAX_NAME);
                if (n != "") g["name"] = n;
                Uebernehmen(g, Wert(info, "Properties"));
                object pairing = Wert(info, "Pairing");
                object p = Zahl(Wert(pairing, "IsPaired"));
                if (p is bool) g["paired"] = (bool)p;
                object cp = Zahl(Wert(pairing, "CanPair"));
                if (cp is bool) g["canpair"] = (bool)cp;
            }
            Meldungen++;
        } catch (Exception) { }
    }

    // DeviceWatcher.Updated: DeviceInformationUpdate (Id, Properties) – nur, was schon bekannt ist.
    public static void Neu2(object sender, object update) {
        try {
            string id = Wert(update, "Id") as string;
            if (id == null) return;
            lock (sperre) {
                Hashtable g;
                if (!geraete.TryGetValue(id, out g)) return;
                Uebernehmen(g, Wert(update, "Properties"));
            }
            Meldungen++;
        } catch (Exception) { }
    }

    // DeviceWatcher.Removed: nicht mehr in Reichweite.
    public static void Weg(object sender, object update) {
        try {
            string id = Wert(update, "Id") as string;
            if (id == null) return;
            lock (sperre) {
                Hashtable g;
                if (geraete.TryGetValue(id, out g)) g["present"] = false;
            }
        } catch (Exception) { }
    }

    public static void Ende(object sender, object args) {
        Fertig++;
    }

    // Name eines Controllers, falls Windows die Klasse (noch) nicht kennt – nur beschreibend, nur als Rückfall.
    public static bool NameIstPad(string n) {
        if (string.IsNullOrEmpty(n)) return false;
        string s = n.ToLowerInvariant();
        foreach (string nie in new[] { "keyboard", "tastatur", "mouse", "maus", "headset", "kopfhörer", "speaker", "lautsprecher", "buds", "watch", "tv", "remote control" })
            if (s.Contains(nie)) return false;
        foreach (string ja in new[] { "controller", "gamepad", "joy-con", "dualsense", "dualshock", "8bitdo", "joystick" })
            if (s.Contains(ja)) return true;
        return false;
    }

    public static bool IstPad(Hashtable g) {
        int major = (int)g["major"], minor = (int)g["minor"], look = (int)g["appearance"];
        if (major == 5 && ((minor & 0x0F) == 1 || (minor & 0x0F) == 2)) return true;
        if (look == 0x03C3 || look == 0x03C4) return true;
        // Klasse unbekannt (Windows liest sie bei manchen Controllern erst nach dem Koppeln): nach dem Namen.
        return major == 0 && look == 0 && NameIstPad(g["name"] as string);
    }

    // Die Controller unter allem Gefundenen (Kopien, höchstens max).
    public static Hashtable[] Stand(int max) {
        var out_ = new List<Hashtable>();
        lock (sperre) {
            foreach (var g in geraete.Values) {
                if (out_.Count >= max) break;
                if (!IstPad(g)) continue;
                if (!(bool)g["present"] && !(bool)g["paired"]) continue;
                out_.Add((Hashtable)g.Clone());
            }
        }
        return out_.ToArray();
    }

    public static int Anzahl() {
        lock (sperre) { return geraete.Count; }
    }
}
'@

function Test-BtId($id) {
    if ($null -eq $id -or -not ($id -is [string])) { return $false }
    if ($id.Length -lt 1 -or $id.Length -gt 80) { return $false }
    return [regex]::IsMatch($id, $script:BtIdRe)
}

# Läuft der Helfer mit Adminrechten? Lässt es sich nicht feststellen, gilt das wie „ja“ (ablehnen).
function Test-BtAdmin {
    try { return [UzElev]::IsElevated($PID) } catch { return $true }
}

function Test-BtGamepad([int]$major, [int]$minor, [int]$appearance) {
    if ($major -eq 5 -and ((($minor -band 0x0F) -eq 1) -or (($minor -band 0x0F) -eq 2))) { return $true }
    return ($appearance -eq 0x03C3 -or $appearance -eq 0x03C4)
}

# Rückfall, wenn Windows die Klasse nicht kennt: der Name sagt „Controller“ o. Ä. (wie UzBtSuche.NameIstPad).
function Test-BtPadName([string]$name) {
    if ($null -eq $name -or $name.Length -gt 120) { return $false }
    $s = $name.ToLowerInvariant()
    foreach ($nie in @('keyboard', 'tastatur', 'mouse', 'maus', 'headset', 'kopfhörer', 'speaker', 'lautsprecher', 'buds', 'watch', 'tv', 'remote control')) { if ($s.Contains($nie)) { return $false } }
    foreach ($ja in @('controller', 'gamepad', 'joy-con', 'dualsense', 'dualshock', '8bitdo', 'joystick')) { if ($s.Contains($ja)) { return $true } }
    return $false
}

function Get-BtProp($d, [string]$name) {
    try { $v = $d.Properties[$name]; if ($null -ne $v) { return [int]$v } } catch { }
    return 0
}

function Use-Bt {
    if ($script:BtReady) { return }
    Use-WinRt
    $null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
    $null = [Windows.Devices.Enumeration.DeviceInformationCustomPairing, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
    $null = [Windows.Devices.Bluetooth.BluetoothDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
    $null = [Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
    $null = [Windows.Devices.Radios.Radio, Windows.Devices.Radios, ContentType = WindowsRuntime]
    Add-Type -TypeDefinition $script:BtSrc
    $script:BtReady = $true
}

function Use-BtSuche {
    if ($script:BtSucheReady) { return }
    $null = [Windows.Devices.Enumeration.DeviceWatcher, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
    $null = [Windows.Devices.Enumeration.DeviceInformationUpdate, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
    Add-Type -TypeDefinition $script:BtSucheSrc
    $script:BtSucheReady = $true
}

function Await-OpMs($op, [Type]$t, [int]$ms) {
    $task = $script:AsTaskOp.MakeGenericMethod($t).Invoke($null, @($op))
    if (-not $task.Wait($ms)) { throw 'Zeitüberschreitung' }
    return $task.Result
}

# „an“, „aus“ oder „kein“ (kein Bluetooth-Funk). Nur lesen.
function Get-BtRadio {
    $list = Await-OpMs ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]]) 5000
    $bt = @($list | Where-Object { $_.Kind -eq [Windows.Devices.Radios.RadioKind]::Bluetooth })
    if ($bt.Count -eq 0) { return 'kein' }
    if (@($bt | Where-Object { $_.State -eq [Windows.Devices.Radios.RadioState]::On }).Count -gt 0) { return 'an' }
    return 'aus'
}

function Bt-Scan($a) {
    if (Test-BtAdmin) { return @{ code = 'admin'; devices = @() } }
    try { Use-Bt; Use-BtSuche } catch { return @{ code = 'kein'; devices = @() } }
    try { $radio = Get-BtRadio } catch { $radio = 'kein' }
    if ($radio -ne 'an') { return @{ code = $radio; devices = @() } }
    $secs = Get-Num $a.secs 30
    if ($secs -lt 4) { $secs = 12 }
    $props = [string[]]$script:BtSucheProps
    $kind = [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint
    $tInfo = [Windows.Foundation.TypedEventHandler[Windows.Devices.Enumeration.DeviceWatcher, Windows.Devices.Enumeration.DeviceInformation]]
    $tUpd = [Windows.Foundation.TypedEventHandler[Windows.Devices.Enumeration.DeviceWatcher, Windows.Devices.Enumeration.DeviceInformationUpdate]]
    $tObj = [Windows.Foundation.TypedEventHandler[Windows.Devices.Enumeration.DeviceWatcher, Object]]
    $hNeu = [Delegate]::CreateDelegate($tInfo, [UzBtSuche].GetMethod('Neu'))
    $hNeu2 = [Delegate]::CreateDelegate($tUpd, [UzBtSuche].GetMethod('Neu2'))
    $hWeg = [Delegate]::CreateDelegate($tUpd, [UzBtSuche].GetMethod('Weg'))
    $hEnde = [Delegate]::CreateDelegate($tObj, [UzBtSuche].GetMethod('Ende'))
    [UzBtSuche]::Leeren()
    $watcher = @()
    foreach ($wahl in $script:BtAqs) {
        $w = $null
        foreach ($aqs in $wahl) {
            try { $w = [Windows.Devices.Enumeration.DeviceInformation]::CreateWatcher($aqs, $props, $kind); break } catch { $w = $null }
        }
        if ($null -eq $w) { continue }
        $w.add_Added($hNeu); $w.add_Updated($hNeu2); $w.add_Removed($hWeg); $w.add_EnumerationCompleted($hEnde)
        try { $w.Start(); $watcher += $w } catch { }
    }
    if ($watcher.Count -eq 0) { return @{ code = 'fehler'; devices = @() } }
    $until = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 250 }
    foreach ($w in $watcher) {
        try { $w.Stop() } catch { }
        try { $w.remove_Added($hNeu); $w.remove_Updated($hNeu2); $w.remove_Removed($hWeg); $w.remove_EnumerationCompleted($hEnde) } catch { }
    }
    $out = @()
    foreach ($g in [UzBtSuche]::Stand(16)) {
        if (-not (Test-BtId ([string]$g['id']))) { continue }
        $out += @{ id = [string]$g['id']; name = [string]$g['name']; major = [int]$g['major']; minor = [int]$g['minor']; appearance = [int]$g['appearance']
            signal = [int]$g['signal']; paired = [bool]$g['paired']; connected = [bool]$g['connected'] }
    }
    return @{ code = 'an'; devices = $out; gesehen = [UzBtSuche]::Anzahl() }
}

# DevicePairingResultStatus → Uzais Schlüssel (src/core/koppeln.gd).
function Get-BtPairCode([int]$st) {
    switch ($st) {
        0 { return 'gekoppelt' }
        3 { return 'schon' }
        1 { return 'bereit' }
        2 { return 'bereit' }
        7 { return 'zeit' }
        15 { return 'laeuft' }
        { $_ -in 4, 8, 9, 11, 12, 14, 17, 18 } { return 'abgelehnt' }
    }
    return 'fehler'
}

function Bt-Get([string]$id) {
    try {
        return Await-OpMs ([Windows.Devices.Enumeration.DeviceInformation]::CreateFromIdAsync($id, [string[]]$script:BtProps,
            [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint)) ([Windows.Devices.Enumeration.DeviceInformation]) 8000
    } catch { return $null }
}

function Bt-Pair($a) {
    # Erst die Kennung (nur Text gegen ein festes Muster) und „neu“ (nur 0 oder 1), dann alles andere.
    $id = $a.id
    if (-not (Test-BtId $id)) { return @{ code = 'kennung' } }
    $neu = 0
    if ($null -ne $a.neu) { $neu = Get-Num $a.neu 9 }
    if ($neu -ne 0 -and $neu -ne 1) { return @{ code = 'kennung' } }
    if (Test-BtAdmin) { return @{ code = 'admin' } }
    try { Use-Bt } catch { return @{ code = 'kein' } }
    try { $radio = Get-BtRadio } catch { $radio = 'kein' }
    if ($radio -ne 'an') { return @{ code = $radio } }
    $dev = Bt-Get ([string]$id)
    if ($null -eq $dev) { return @{ code = 'fehlt' } }
    $major = Get-BtProp $dev 'System.Devices.Aep.Bluetooth.Cod.Major'
    $minor = Get-BtProp $dev 'System.Devices.Aep.Bluetooth.Cod.Minor'
    $look = Get-BtProp $dev 'System.Devices.Aep.Bluetooth.Le.Appearance'
    if (-not (Test-BtGamepad $major $minor $look) -and -not ($major -eq 0 -and $look -eq 0 -and (Test-BtPadName ([string]$dev.Name)))) { return @{ code = 'klasse' } }
    if ($dev.Pairing.IsPaired) {
        if ($neu -ne 1) { return @{ code = 'schon'; name = [string]$dev.Name } }
        # Neu koppeln (ausdrücklich gewünscht): die alte Kopplung genau dieses Controllers entfernen, dann neu koppeln.
        $un = $null
        try { $un = Await-OpMs ($dev.Pairing.UnpairAsync()) ([Windows.Devices.Enumeration.DeviceUnpairingResult]) 15000 } catch { $un = $null }
        if ($null -eq $un -or ([int]$un.Status -ne 0 -and [int]$un.Status -ne 1)) { return @{ code = 'abgelehnt'; name = [string]$dev.Name } }
        Start-Sleep -Milliseconds 1500
        $dev = Bt-Get ([string]$id)
        if ($null -eq $dev -or -not $dev.Pairing.CanPair) { return @{ code = 'entkoppelt' } }
    }
    if (-not $dev.Pairing.CanPair) { return @{ code = 'bereit' } }
    $h = [Delegate]::CreateDelegate([Windows.Foundation.TypedEventHandler[Windows.Devices.Enumeration.DeviceInformationCustomPairing, Windows.Devices.Enumeration.DevicePairingRequestedEventArgs]], [UzBtPair].GetMethod('OnRequest'))
    $code = 'fehler'
    for ($versuch = 0; $versuch -lt 2; $versuch++) {
        $custom = $dev.Pairing.Custom
        [UzBtPair]::LastKind = 0
        $custom.add_PairingRequested($h)
        $res = $null
        try {
            $res = Await-OpMs ($custom.PairAsync([Windows.Devices.Enumeration.DevicePairingKinds]::ConfirmOnly)) ([Windows.Devices.Enumeration.DevicePairingResult]) 30000
        } catch {
            $res = $null
        } finally {
            try { $custom.remove_PairingRequested($h) } catch { }
        }
        $code = if ($null -eq $res) { 'zeit' } else { Get-BtPairCode ([int]$res.Status) }
        if ($code -ne 'gekoppelt' -and $code -ne 'schon' -and [UzBtPair]::LastKind -gt 1) { return @{ code = 'pin'; name = [string]$dev.Name } }
        # Einmal nachfassen, wenn der Controller nur zu langsam war (manche brauchen nach dem Aufwachen einen zweiten Anlauf).
        if ($versuch -gt 0 -or ($code -ne 'zeit' -and $code -ne 'bereit' -and $code -ne 'fehler')) { break }
        Start-Sleep -Milliseconds 1200
        $dev = Bt-Get ([string]$id)
        if ($null -eq $dev -or -not $dev.Pairing.CanPair) { break }
    }
    return @{ code = $code; name = [string]$dev.Name; neu = $neu }
}

# Feste Startparameter (Liste aus Uzai, z. B. Epics Einmal-Code) zur Befehlszeile: höchstens 64,
# je höchstens 1024 Zeichen, keine Steuerzeichen, nur für eine .exe. Gequotet wie CommandLineToArgvW
# es zurückliest (wie Quote-Arg unten). Fehler nennen nie einen Wert.
# --- Apps: Store-Apps und Programme (src/core/apps_extern.gd, docs/SECURITY.md „Apps“) ----------
# Store-Apps startet der Helfer nur über ihre App-Kennung (AppUserModelID) mit dem offiziellen Weg
# von Windows (IApplicationActivationManager) – und nur, wenn genau diese App für dieses Konto
# installiert ist. Programme nur als .exe mit Argumentliste, ohne Shell (UseShellExecute aus);
# Shells und Skript-Programme sind gesperrt, auch umbenannt (Originalname in der Datei). Jede Angabe
# wird hier noch einmal geprüft, bevor Windows etwas davon sieht (tests/apps_cs.ps1). Gelesen wird
# nur: die App-Pakete dieses Kontos, ihr Manifest (XML ohne DTD, ohne Auflöser) und ihr Logo.
$script:AppActSrc = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class UzAppAct {
    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IApplicationActivationManager {
        [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, [MarshalAs(UnmanagedType.LPWStr)] string arguments, int options, out uint processId);
        [PreserveSig] int ActivateForFile([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, IntPtr itemArray, [MarshalAs(UnmanagedType.LPWStr)] string verb, out uint processId);
        [PreserveSig] int ActivateForProtocol([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, IntPtr itemArray, out uint processId);
    }
    [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    class ApplicationActivationManager { }

    delegate bool EnumProc(IntPtr h, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)] static extern int SHLoadIndirectString(string src, StringBuilder outBuf, int cch, IntPtr reserved);

    // Startet die App ohne Parameter (oder holt die laufende nach vorn). > 0: ihr Prozess, sonst
    // der Fehler von Windows (HRESULT, negativ).
    public static long Activate(string aumid) {
        IApplicationActivationManager m = (IApplicationActivationManager)new ApplicationActivationManager();
        uint pid;
        int hr;
        try { hr = m.ActivateApplication(aumid, null, 0, out pid); }
        finally { Marshal.ReleaseComObject(m); }
        if (hr < 0) return hr;
        return pid;
    }

    static string Cls(IntPtr h) {
        StringBuilder sb = new StringBuilder(256);
        GetClassName(h, sb, sb.Capacity);
        return sb.ToString();
    }

    // Fenster der App: bei Store-Apps der Rahmen (ApplicationFrameWindow), dessen Inhalt zum Prozess
    // gehört; sonst das größte sichtbare Hauptfenster des Prozesses. 0: keins.
    public static long WindowOf(int pid) { return WindowOf(pid, ""); }

    // Dazu (aumid nicht leer): ein Fenster, das genau diese App-Kennung trägt – Web-Apps aus dem Store
    // laufen in einem Prozess des Browsers, nicht in dem, den Windows beim Start meldet.
    public static long WindowOf(int pid, string aumid) {
        if (pid <= 0 && string.IsNullOrEmpty(aumid)) return 0;
        IntPtr best = IntPtr.Zero;
        long area = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true;
            int p;
            GetWindowThreadProcessId(h, out p);
            bool mine = pid > 0 && p == pid;
            if (!mine && pid > 0 && Cls(h) == "ApplicationFrameWindow") {
                EnumChildWindows(h, delegate(IntPtr c, IntPtr l2) {
                    int cp;
                    GetWindowThreadProcessId(c, out cp);
                    if (cp == pid) { mine = true; return false; }
                    return true;
                }, IntPtr.Zero);
            }
            if (!mine && !string.IsNullOrEmpty(aumid)) mine = string.Equals(WindowAumid(h), aumid, StringComparison.OrdinalIgnoreCase);
            if (!mine) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            long a = (long)(r.Right - r.Left) * (long)(r.Bottom - r.Top);
            if (a > area) { area = a; best = h; }
            return true;
        }, IntPtr.Zero);
        return best.ToInt64();
    }

    // --- Wer ist dieses Fenster? (Test-ExtAppWindow) -------------------------------------------
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern int GetApplicationUserModelId(IntPtr process, ref uint len, StringBuilder id);
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        [PreserveSig] int GetCount(out uint n);
        [PreserveSig] int GetAt(uint i, out PROPERTYKEY key);
        [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT v);
    }
    [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PROPERTYKEY { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Sequential)] struct PROPVARIANT { public ushort vt; public ushort r1; public ushort r2; public ushort r3; public IntPtr p; public IntPtr p2; }
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr h, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT v);

    static string Kurz(string s) {
        if (s == null) return "";
        return s.Length > 300 ? s.Substring(0, 300) : s;
    }

    public static int PidOf(IntPtr h) {
        int p = 0;
        if (h != IntPtr.Zero) GetWindowThreadProcessId(h, out p);
        return p;
    }

    // App-Kennung, die das Fenster selbst trägt (System.AppUserModel.ID; Web-Apps aus dem Store setzen
    // sie so). "" = keine. Nur lesen.
    public static string WindowAumid(IntPtr h) {
        if (h == IntPtr.Zero || !IsWindow(h)) return "";
        Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropertyStore st = null;
        try {
            if (SHGetPropertyStoreForWindow(h, ref iid, out st) != 0 || st == null) return "";
            PROPERTYKEY k = new PROPERTYKEY();
            k.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
            k.pid = 5;
            PROPVARIANT v;
            if (st.GetValue(ref k, out v) != 0) return "";
            try { return (v.vt == 31 && v.p != IntPtr.Zero) ? Kurz(Marshal.PtrToStringUni(v.p)) : ""; }
            finally { PropVariantClear(ref v); }
        } catch { return ""; }
        finally { if (st != null) Marshal.ReleaseComObject(st); }
    }

    // App-Kennung des Prozesses (nur Prozesse aus einem Paket haben eine). "" = keine.
    public static string ProcessAumid(int pid) {
        if (pid <= 4) return "";
        IntPtr p = OpenProcess(0x1000, false, pid);
        if (p == IntPtr.Zero) return "";
        try {
            uint n = 512;
            StringBuilder sb = new StringBuilder(512);
            return GetApplicationUserModelId(p, ref n, sb) == 0 ? Kurz(sb.ToString()) : "";
        } catch { return ""; }
        finally { CloseHandle(p); }
    }

    // Store-App im Rahmen (ApplicationFrameWindow gehört ApplicationFrameHost): Prozess ihres Inhalts.
    // 0 = kein solcher Rahmen.
    public static int FrameContentPid(IntPtr h) {
        if (h == IntPtr.Zero || Cls(h) != "ApplicationFrameWindow") return 0;
        int own = PidOf(h);
        int found = 0;
        EnumChildWindows(h, delegate(IntPtr c, IntPtr l) {
            int cp = PidOf(c);
            if (cp > 4 && cp != own) { found = cp; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    // --- Randlos auf den ganzen Bildschirm (app-vollbild) -----------------------------------------
    // Nur das Fenster der App ändert sich (Stil, Lage); Windows-Einstellungen, Taskleiste und andere
    // Fenster bleiben, wie sie sind. Zurueck stellt Stil und Lage wieder her, wie sie vorher waren.
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("gdi32.dll")] static extern IntPtr CreateRectRgn(int l, int t, int r, int b);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);

    class Vorher { public long Style; public long Ex; public RECT Rect; public int Pid; public bool Rgn; }
    static readonly System.Collections.Generic.Dictionary<long, Vorher> vorher = new System.Collections.Generic.Dictionary<long, Vorher>();
    static readonly object vgate = new object();

    static RECT Monitor(IntPtr h) {
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        GetMonitorInfo(MonitorFromWindow(h, 2), ref mi);
        return mi.rcMonitor;
    }

    // Deckt das Fenster seinen Bildschirm (eigenes Vollbild der App oder randlos)? Zwei Pixel Spielraum.
    public static bool Covers(IntPtr h) {
        RECT r;
        if (h == IntPtr.Zero || !IsWindow(h) || !IsWindowVisible(h) || IsIconic(h) || !GetWindowRect(h, out r)) return false;
        RECT m = Monitor(h);
        if (m.Right - m.Left <= 0) return false;
        return r.Left <= m.Left + 2 && r.Top <= m.Top + 2 && r.Right >= m.Right - 2 && r.Bottom >= m.Bottom - 2;
    }

    // Titelleiste und Rahmen weg (WS_CAPTION, WS_THICKFRAME, WS_SYSMENU, Min/Max; Kanten im erweiterten
    // Stil), dann über den ganzen Bildschirm. Store-Apps im Rahmen zeichnen ihre Titelleiste selbst in
    // den Rahmen: dann liegt der Rahmen um ihre Höhe nach oben verschoben, und eine Region schneidet
    // genau den Bildschirm aus (auf einem Bildschirm darüber ist nichts davon zu sehen).
    public static bool Randlos(IntPtr h) {
        if (h == IntPtr.Zero || !IsWindow(h)) return false;
        RECT m = Monitor(h);
        int w = m.Right - m.Left, hh = m.Bottom - m.Top;
        if (w <= 0 || hh <= 0) return false;
        long key = h.ToInt64();
        Vorher v;
        lock (vgate) {
            if (!vorher.TryGetValue(key, out v)) {
                if (vorher.Count >= 16) {
                    // Erst vergessen, was es nicht mehr gibt (geschlossene Fenster); nur wenn dann noch alles belegt
                    // ist, alles – früher verlor das 17. Fenster sofort den Stand aller anderen.
                    var weg = new System.Collections.Generic.List<long>();
                    foreach (var kv in vorher) if (!IsWindow(new IntPtr(kv.Key))) weg.Add(kv.Key);
                    foreach (long k in weg) vorher.Remove(k);
                    if (vorher.Count >= 16) vorher.Clear();
                }
                v = new Vorher();
                v.Style = GetWindowLongPtr(h, -16).ToInt64();
                v.Ex = GetWindowLongPtr(h, -20).ToInt64();
                GetWindowRect(h, out v.Rect);
                v.Pid = PidOf(h);
                vorher[key] = v;
            }
        }
        if (IsZoomed(h) || IsIconic(h)) ShowWindow(h, 9);
        long st = v.Style & ~(0x00C00000L | 0x00040000L | 0x00080000L | 0x00020000L | 0x00010000L);
        long ex = v.Ex & ~(0x00000001L | 0x00000100L | 0x00000200L | 0x00020000L);
        SetWindowLongPtr(h, -16, new IntPtr(st));
        SetWindowLongPtr(h, -20, new IntPtr(ex));
        // HWND_TOP; SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER
        SetWindowPos(h, IntPtr.Zero, m.Left, m.Top, w, hh, 0x0010u | 0x0020u | 0x0040u | 0x0200u);
        if (Cls(h) == "ApplicationFrameWindow") {
            System.Threading.Thread.Sleep(150);
            int top = 0;
            EnumChildWindows(h, delegate(IntPtr c, IntPtr l) {
                if (Cls(c) != "Windows.UI.Core.CoreWindow") return true;
                RECT cr;
                if (GetWindowRect(c, out cr)) top = cr.Top - m.Top;
                return false;
            }, IntPtr.Zero);
            if (top > 0 && top < 120) {
                SetWindowPos(h, IntPtr.Zero, m.Left, m.Top - top, w, hh + top, 0x0010u | 0x0200u);
                IntPtr rg = CreateRectRgn(0, top, w, top + hh);
                if (SetWindowRgn(h, rg, true) != 0) v.Rgn = true;
                else DeleteObject(rg);
            }
        }
        return Covers(h);
    }

    // Wie vorher (nur, was Randlos gemerkt hat, und nur am selben Prozess). Ohne Aktivieren: Uzai bleibt vorn.
    public static bool Zurueck(IntPtr h) {
        long key = h.ToInt64();
        Vorher v;
        lock (vgate) {
            if (!vorher.TryGetValue(key, out v)) return false;
            vorher.Remove(key);
        }
        if (!IsWindow(h) || PidOf(h) != v.Pid) return false;
        if (v.Rgn) SetWindowRgn(h, IntPtr.Zero, true);
        SetWindowLongPtr(h, -16, new IntPtr(v.Style));
        SetWindowLongPtr(h, -20, new IntPtr(v.Ex));
        // SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOOWNERZORDER
        return SetWindowPos(h, IntPtr.Zero, v.Rect.Left, v.Rect.Top, v.Rect.Right - v.Rect.Left, v.Rect.Bottom - v.Rect.Top, 0x0004u | 0x0010u | 0x0020u | 0x0200u);
    }

    // Text aus den Ressourcen eines Pakets („@{Paket?ms-resource://…}“), "" wenn es ihn nicht gibt.
    public static string Resource(string src) {
        StringBuilder sb = new StringBuilder(512);
        int hr = SHLoadIndirectString(src, sb, sb.Capacity, IntPtr.Zero);
        return hr == 0 ? sb.ToString() : "";
    }
}

// Rand oben frei (app-vollbild): Store-Apps im Vollbild und Browser-Apps nach F11 blenden ihre
// Titelleiste bzw. ein „X“ ein, sobald die Maus an den oberen Bildschirmrand kommt. Solange genau das
// geprüfte App-Fenster vorn liegt und seinen Bildschirm deckt, hält der Helfer den Mauszeiger auf
// diesem Bildschirm und einen schmalen Streifen unter dem oberen Rand (ClipCursor). Liegt etwas anderes
// vorn (Uzai, Guide, ein Dialog) oder ist das Fenster weg, gibt er den Zeiger sofort frei – nur, wenn
// die Grenze noch seine ist; die eines Spiels oder Programms fasst er nie an.
public static class UzAppRand {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll", EntryPoint = "ClipCursor")] static extern bool ClipCursorFrei(IntPtr r);
    [DllImport("user32.dll")] static extern bool GetClipCursor(out RECT r);

    static readonly object gate = new object();
    static IntPtr ziel = IntPtr.Zero;
    static int zielPid;
    static volatile bool an;
    static bool unser;
    static RECT gesetzt;
    static System.Threading.Thread faden;

    // So viele Pixel bleiben oben frei: genug für die Auslöser von Windows und Chromium (wenige Punkte,
    // auch bei 200 % Skalierung), kaum sichtbar.
    public static int RandPx(int bildHoehe) {
        if (bildHoehe <= 0) return 0;
        return Math.Max(8, Math.Min(40, (bildHoehe + 50) / 100));
    }

    // 1 = Grenze setzen (bzw. halten), -1 = freigeben, 0 = nichts tun. Gesetzt wird nur, wenn die App vorn
    // liegt und den Bildschirm deckt und der Zeiger schon auf diesem Bildschirm ist (oder die Grenze
    // schon steht); freigegeben nur, was der Helfer selbst gesetzt hat.
    public static int Schritt(bool vorn, bool deckt, bool zeigerDort, bool unsereGrenze) {
        if (vorn && deckt && (zeigerDort || unsereGrenze)) return 1;
        return unsereGrenze ? -1 : 0;
    }

    public static void Start(IntPtr h, int pid) {
        if (h == IntPtr.Zero || pid <= 4) return;
        lock (gate) {
            ziel = h; zielPid = pid; an = true;
            if (faden != null && faden.IsAlive) return;
            faden = new System.Threading.Thread(Lauf);
            faden.IsBackground = true;
            faden.Start();
        }
    }

    public static void Stop() {
        an = false;
        lock (gate) { Frei(); ziel = IntPtr.Zero; }
    }

    public static bool Aktiv { get { return an; } }

    // Rand für den Bildschirm, auf dem das Fenster liegt (auch für den Zeiger mit dem rechten Stick).
    public static int RandFuer(IntPtr h) {
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (h == IntPtr.Zero || !GetMonitorInfo(MonitorFromWindow(h, 2), ref mi)) return 0;
        return RandPx(mi.rcMonitor.Bottom - mi.rcMonitor.Top);
    }

    static bool Gleich(RECT a, RECT b) { return a.Left == b.Left && a.Top == b.Top && a.Right == b.Right && a.Bottom == b.Bottom; }

    // Nur freigeben, wenn die Grenze noch die eigene ist (sonst gehört sie inzwischen jemand anderem).
    static void Frei() {
        if (!unser) return;
        unser = false;
        RECT jetzt;
        if (GetClipCursor(out jetzt) && Gleich(jetzt, gesetzt)) ClipCursorFrei(IntPtr.Zero);
    }

    static void Lauf() {
        while (true) {
            System.Threading.Thread.Sleep(30);
            lock (gate) {
                if (!an) { Frei(); faden = null; return; }
                IntPtr h = ziel;
                int p;
                bool lebt = h != IntPtr.Zero && IsWindow(h);
                GetWindowThreadProcessId(h, out p);
                if (!lebt || p != zielPid) { Frei(); an = false; faden = null; return; }
                bool vorn = GetForegroundWindow() == h && IsWindowVisible(h) && !IsIconic(h);
                MONITORINFO mi = new MONITORINFO();
                mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
                RECT m = new RECT(), w;
                bool deckt = false;
                if (vorn && GetMonitorInfo(MonitorFromWindow(h, 2), ref mi) && GetWindowRect(h, out w)) {
                    m = mi.rcMonitor;
                    deckt = m.Right > m.Left && w.Left <= m.Left + 2 && w.Top <= m.Top + 2 && w.Right >= m.Right - 2 && w.Bottom >= m.Bottom - 2;
                }
                POINT c;
                bool dort = deckt && GetCursorPos(out c) && c.X >= m.Left && c.X < m.Right && c.Y >= m.Top && c.Y < m.Bottom;
                int s = Schritt(vorn, deckt, dort, unser);
                if (s == -1) Frei();
                if (s != 1) continue;
                RECT g = m;
                g.Top = m.Top + RandPx(m.Bottom - m.Top);
                RECT jetzt;
                if (unser && GetClipCursor(out jetzt) && Gleich(jetzt, g)) continue;
                if (ClipCursor(ref g)) { unser = true; gesetzt = g; }
            }
        }
    }
}
'@
function Use-AppAct {
    if (-not $script:AppActReady) { Add-Type -TypeDefinition $script:AppActSrc; $script:AppActReady = $true }
}

# Textfeld in einer eigenen App (app-pad, app-text): Hat in der App vorn ein Textfeld den Fokus? Gelesen
# über UI Automation (wie ein Bildschirmleser), nur Art, Zustand und Prozess des fokussierten Elements –
# nie sein Inhalt. Fragt nur, solange genau das App-Fenster vorn liegt (alle 350 ms, in eigenem Faden);
# ob es ein Textfeld ist, entscheidet UzPad.AppFeldEditierbar (eine Regel für beide, Delegat Regel).
# Erst beim ersten Gebrauch übersetzt (wie UzUia), damit ein Problem dort den Helfer nie mitreißt.
$script:AppFeldSrc = @'
using System;
using System.Windows.Automation;
using System.Runtime.InteropServices;

public static class UzAppFeld {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    public static volatile Func<int, bool, bool, bool, bool> Regel;
    static readonly object gate = new object();
    static IntPtr ziel = IntPtr.Zero;
    static int pidA, pidB;
    static volatile bool an;
    static volatile int feld;
    static System.Threading.Thread faden;

    public static int FeldJetzt() { return an ? feld : 0; }

    public static void Start(IntPtr h, int pid, int inhaltPid) {
        if (h == IntPtr.Zero || pid <= 4) return;
        lock (gate) {
            ziel = h; pidA = pid; pidB = inhaltPid > 4 ? inhaltPid : pid; feld = 0; an = true;
            if (faden != null) return;
            faden = new System.Threading.Thread(Lauf);
            faden.IsBackground = true;
            faden.Start();
        }
    }

    public static void Stop() { lock (gate) { an = false; feld = 0; } }

    // Fokussiertes Element jetzt (0/1/2), höchstens budgetMs; nur wenn das Fenster vorn liegt.
    public static int Pruefen(int budgetMs) {
        int r = 0;
        var t = new System.Threading.Thread(delegate () { r = Lesen(); });
        t.IsBackground = true;
        t.Start();
        if (!t.Join(Math.Max(50, Math.Min(budgetMs, 3000)))) return 0;
        return r;
    }

    static int Lesen() {
        IntPtr h; int a, b;
        lock (gate) { h = ziel; a = pidA; b = pidB; }
        if (h == IntPtr.Zero || !IsWindow(h) || GetForegroundWindow() != h) return 0;
        var regel = Regel;
        if (regel == null) return 0;
        try {
            AutomationElement e = AutomationElement.FocusedElement;
            if (e == null) return 0;
            int p = e.Current.ProcessId;
            if (p != a && p != b) return 0;
            object vp;
            bool hasValue = e.TryGetCurrentPattern(ValuePattern.Pattern, out vp);
            bool ro = hasValue && ((ValuePattern)vp).Current.IsReadOnly;
            if (!regel(e.Current.ControlType.Id, hasValue, ro, e.Current.IsEnabled)) return 0;
            return e.Current.IsPassword ? 2 : 1;
        } catch { return 0; }
    }

    static void Lauf() {
        while (true) {
            lock (gate) { if (!an) { faden = null; return; } }
            feld = Lesen();
            System.Threading.Thread.Sleep(350);
        }
    }
}
'@
function Use-AppFeld {
    if ($script:AppFeldReady) { return }
    Add-Type -AssemblyName WindowsBase, UIAutomationTypes, UIAutomationClient
    $refs = @([System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location, [System.Windows.Rect].Assembly.Location)
    Add-Type -TypeDefinition $script:AppFeldSrc -ReferencedAssemblies $refs
    [UzAppFeld]::Regel = [Delegate]::CreateDelegate([Func[int, bool, bool, bool, bool]], [UzPad].GetMethod('AppFeldEditierbar'))
    [UzPad]::AppFeld = [Delegate]::CreateDelegate([Func[int]], [UzAppFeld].GetMethod('FeldJetzt'))
    $script:AppFeldReady = $true
}
# Wie AppsExtern.GESPERRT (src/core/apps_extern.gd) – beide Listen prüft tests/apps_cs.ps1.
$script:AppGesperrt = @('cmd', 'powershell', 'powershell_ise', 'pwsh', 'wscript', 'cscript', 'mshta', 'rundll32', 'regsvr32',
    'wsl', 'wslhost', 'bash', 'wt', 'windowsterminal', 'conhost', 'openconsole', 'msiexec', 'msbuild', 'installutil',
    'regasm', 'regsvcs', 'cmstp', 'certutil', 'bitsadmin', 'schtasks', 'forfiles', 'hh', 'wmic', 'msxsl', 'scriptrunner',
    'explorer', 'control', 'mmc', 'reg', 'regedit', 'runas', 'sc', 'at', 'pcalua', 'presentationhost', 'dotnet', 'node', 'python',
    'pythonw', 'py', 'pyw', 'perl', 'ruby', 'java', 'javaw', 'php', 'wish', 'tclsh', 'lua', 'deno', 'bun')
function Test-Aumid([string]$s) {
    if ($null -eq $s -or $s.Length -lt 18 -or $s.Length -gt 180) { return $false }
    if ($s -cnotmatch '^[A-Za-z0-9.\-]{3,50}_[a-z0-9]{13}![A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)*\z') { return $false }
    return ($s.Substring($s.IndexOf('!') + 1).Length -le 64)
}
function Test-AppBlockedName([string]$n) {
    $s = ([string]$n).Trim().ToLowerInvariant()
    if ($s.EndsWith('.exe')) { $s = $s.Substring(0, $s.Length - 4) }
    $bare = $s -replace '[0-9._\-]+\z', ''
    return (($script:AppGesperrt -contains $s) -or ($script:AppGesperrt -contains $bare))
}
# Nur eine .exe auf einem Laufwerk (keine Freigabe, kein \\?\), ohne „..“ und Sonderzeichen, keine
# Shell. '' = in Ordnung, sonst der Grund (wie AppsExtern.path_problem).
function Test-ProgPath([string]$p) {
    $s = ([string]$p).Trim() -replace '/', '\'
    if ($s.Length -eq 0 -or $s.Length -gt 260) { return 'Kein gültiger Pfad.' }
    if ($s -notmatch '^[A-Za-z]:\\[^\\]') { return 'Nur Programme auf einem Laufwerk dieses PCs.' }
    if ($s -match '[\x00-\x1f\x7f"<>|*?]' -or $s.Substring(2).Contains(':')) { return 'Kein gültiger Pfad.' }
    foreach ($part in $s.Split('\')) { if ($part -eq '' -or $part.EndsWith(' ') -or $part.EndsWith('.')) { return 'Kein gültiger Pfad.' } }
    $file = $s.Substring($s.LastIndexOf('\') + 1)
    if (-not $file.ToLowerInvariant().EndsWith('.exe')) { return 'Nur Programme (.exe) – keine Skripte oder Verknüpfungen.' }
    if (Test-AppBlockedName $file) { return 'Shells und Skript-Programme startet Uzai nicht.' }
    return ''
}
# Wie Test-ProgPath, dazu: die Datei gibt es, und ihr Originalname (Versionsangaben) ist keine Shell –
# eine umbenannte cmd.exe bleibt gesperrt.
function Test-Program([string]$p) {
    $why = Test-ProgPath $p
    if ($why) { return $why }
    $s = ([string]$p).Trim() -replace '/', '\'
    if (-not (Test-Path -LiteralPath $s -PathType Leaf)) { return 'Das Programm wurde nicht gefunden.' }
    try {
        $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($s)
        foreach ($n in @([string]$vi.OriginalFilename, [string]$vi.InternalName)) {
            if ($n -and (Test-AppBlockedName ($n.Trim() -replace '\.mui\z', ''))) { return 'Shells und Skript-Programme startet Uzai nicht.' }
        }
    } catch {}
    return ''
}
# Gehört das Fenster genau dieser eigenen App? (Regel ohne Windows-Aufrufe, prüfbar.) Store-App: die
# App-Kennung des Fensters, seines Prozesses oder – im Rahmen (ApplicationFrameWindow) – seines Inhalts
# ist genau ihre. Programm: der Prozess ist genau dieses Programm oder eine .exe in seinem Ordner (Starter
# wie Plex HTPC), nie eine Shell; liegt das Programm direkt auf dem Laufwerk, nur es selbst.
# $f: @{ win; proc; child; img }.
function Test-ExtAppIdent([string]$kind, [string]$want, $f) {
    if ($kind -eq 'store') {
        if (-not (Test-Aumid $want)) { return $false }
        foreach ($x in @([string]$f.win, [string]$f.proc, [string]$f.child)) {
            if ($x -and [string]::Equals($x, $want, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    if ($kind -ne 'prog' -or (Test-ProgPath $want) -ne '') { return $false }
    $img = ([string]$f.img) -replace '/', '\'
    if (-not $img -or $img -match '[\x00-\x1f]' -or $img.Contains('\..\') -or $img.Contains('\.\')) { return $false }
    $exe = ([string]$want).Trim() -replace '/', '\'
    if ([string]::Equals($img, $exe, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $dir = $exe.Substring(0, $exe.LastIndexOf('\') + 1)
    if ($dir.Length -le 3) { return $false }
    $file = $img.Substring($img.LastIndexOf('\') + 1)
    return ($img.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) -and $file.ToLowerInvariant().EndsWith('.exe') -and -not (Test-AppBlockedName $file))
}
# Fenster einer eigenen App (docs/SECURITY.md „Apps“): nur Zahlen als Fenster, nie ein geschütztes
# (UzGuard) oder der Helfer selbst, dann Test-ExtAppIdent. @{ ok; pid } bzw. @{ ok = $false; why }.
function Test-ExtAppWindow($a) {
    $kind = [string]$a.kind
    $want = ''
    if ($kind -eq 'store') { $want = [string]$a.aumid; if (-not (Test-Aumid $want)) { return @{ ok = $false; why = 'Ungültige App-Kennung.' } } }
    elseif ($kind -eq 'prog') { $want = [string]$a.path; if ((Test-ProgPath $want) -ne '') { return @{ ok = $false; why = 'Kein gültiger Pfad.' } } }
    else { return @{ ok = $false; why = 'Unbekannte Art.' } }
    $hw = Get-Hwnd $a.hwnd
    if ($hw -le 0) { return @{ ok = $false; why = 'kein Fenster' } }
    $h = [IntPtr]$hw
    if (-not [UzWin]::IsWindow($h)) { return @{ ok = $false; why = 'kein Fenster' } }
    if ([UzGuard]::Problem($h) -ne '') { return @{ ok = $false; why = 'geschützt' } }
    $wpid = [UzWin]::PidOf($h)
    if ($wpid -le 4 -or $wpid -eq $PID) { return @{ ok = $false; why = 'fremd' } }
    Use-AppAct
    $f = @{ win = ''; proc = ''; child = ''; img = '' }
    if ($kind -eq 'store') {
        $f.win = [UzAppAct]::WindowAumid($h)
        $f.proc = [UzAppAct]::ProcessAumid($wpid)
        $cp = [UzAppAct]::FrameContentPid($h)
        if ($cp -gt 0) { $f.child = [UzAppAct]::ProcessAumid($cp) }
    } else { $f.img = [UzLs]::ImagePath($wpid) }
    if (-not (Test-ExtAppIdent $kind $want $f)) { return @{ ok = $false; why = 'fremd' } }
    return @{ ok = $true; pid = $wpid }
}
# Taste für einen Knopf in einer App (Test-KeyCombo „app“) als Code für UzPad: Taste, mit Umschalt
# | 0x10000; '' = 0 (Knopf tut nichts); $null = nicht erlaubt.
function Get-AppPadCode($t) {
    if ($null -eq $t -or ($t -is [string] -and $t -eq '')) { return 0 }
    if ($t -isnot [string] -or (Test-KeyCombo $t 'app') -ne '') { return $null }
    $code = 0
    foreach ($c in @((Parse-Keys $t $false).codes)) { if ([int]$c -eq 0x10) { $code = $code -bor 0x10000 } else { $code = $code -bor [int]$c } }
    return $code
}
function Test-AppMediaId([string]$s) {
    if (Test-Aumid $s) { return $true }
    return ($s -match '^[A-Za-z0-9 ._()+\-]{1,80}\.[Ee][Xx][Ee]\z')
}
# Name aus fremder Quelle: ohne Steuerzeichen, höchstens 120 Zeichen.
function Get-AppCleanText([string]$s) {
    $t = (([string]$s) -replace '[\x00-\x1f\x7f]', '').Trim()
    if ($t.Length -gt 120) { $t = $t.Substring(0, 120) }
    return $t
}
# App-Manifest eines Pakets lesen: nur Daten (keine DTD, kein Auflöser, Größe begrenzt).
function Read-AppManifest([string]$dir) {
    if (-not $dir) { return $null }
    $file = Join-Path $dir 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    if ((Get-Item -LiteralPath $file).Length -gt 4MB) { return $null }
    $set = New-Object Xml.XmlReaderSettings
    $set.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $set.XmlResolver = $null
    $set.MaxCharactersInDocument = 8MB
    $r = [Xml.XmlReader]::Create($file, $set)
    try {
        $doc = New-Object Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.Load($r)
        return $doc
    } finally { $r.Close() }
}
function Get-AppNodes($doc) {
    return @($doc.SelectNodes("/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application']"))
}
# Anzeigename aus dem Manifest („ms-resource:…“ über die Ressourcen des Pakets).
function Get-AppText($p, [string]$s) {
    if (-not $s) { return '' }
    if (-not $s.StartsWith('ms-resource:', [StringComparison]::OrdinalIgnoreCase)) { return (Get-AppCleanText $s) }
    Use-AppAct
    $key = $s.Substring(12)
    $pn = [string]$p.Name
    $full = [string]$p.PackageFullName
    $tries = @()
    if ($key.StartsWith('//')) { $tries += ('ms-resource:' + $key) }
    elseif ($key.StartsWith('/')) { $tries += ('ms-resource://' + $pn + $key) }
    else { $tries += ('ms-resource://' + $pn + '/resources/' + $key); $tries += ('ms-resource://' + $pn + '/' + $key) }
    foreach ($t in $tries) {
        $v = [UzAppAct]::Resource('@{' + $full + '?' + $t + '}')
        if ($v) { return (Get-AppCleanText $v) }
    }
    return ''
}
# Paket und Eintrag zu einer geprüften AUMID – nur, wenn genau diese App für dieses Konto
# installiert ist ($null sonst, auch ohne Get-AppxPackage, etwa unter Linux).
function Find-StorePackage([string]$aumid) {
    if (-not (Test-Aumid $aumid)) { return $null }
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) { return $null }
    $i = $aumid.IndexOf('!')
    $fam = $aumid.Substring(0, $i)
    $name = $fam.Substring(0, $fam.LastIndexOf('_'))
    $appId = $aumid.Substring($i + 1)
    $p = $null
    try { $p = @(Get-AppxPackage -Name $name -ErrorAction Stop | Where-Object { [string]$_.PackageFamilyName -ceq $fam }) | Select-Object -First 1 } catch {}
    if ($null -eq $p -or $p.IsFramework) { return $null }
    $m = Read-AppManifest ([string]$p.InstallLocation)
    if ($null -eq $m) { return $null }
    foreach ($ap in (Get-AppNodes $m)) {
        if ([string]$ap.GetAttribute('Id') -ceq $appId) { return @{ pkg = $p; app = $ap } }
    }
    return $null
}
# Hinweise für die Emulator-Suche (src/core/emu_suche.gd): Deinstallations-Einträge (HKLM, HKCU,
# WOW6432Node – nur lesen) mit Name, Ordner und Symbol-Datei und die Programmdateien laufender
# Prozesse, beide mit Produktname aus den Versionsangaben. Nichts wird gestartet oder geöffnet
# außer zum Lesen der Versionsangaben; keine Eingaben. Texte gekürzt, Listen begrenzt.
function Get-EmuHintText($v, [int]$max = 400) {
    $t = [string]$v
    if (-not $t) { return '' }
    $t = ($t -replace '[\x00-\x1f\x7f]', ' ').Trim()
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max) }
    return $t
}
function Get-EmuHintProduct([string]$path) {
    $p = ($path.Trim().Trim('"') -split ',')[0].Trim().Trim('"')
    if (-not $p.ToLower().EndsWith('.exe') -or -not [IO.Path]::IsPathRooted($p) -or $p.StartsWith('\\')) { return '' }
    try {
        if (-not [IO.File]::Exists($p)) { return '' }
        $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($p)
        return (Get-EmuHintText ([string]$vi.ProductName + ' ' + [string]$vi.FileDescription) 200)
    } catch { return '' }
}
function Get-EmuHints {
    $un = New-Object Collections.ArrayList
    foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($k in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue | Select-Object -First 3000)) {
            if ($un.Count -ge 3000) { break }
            $p = $null
            try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
            $name = Get-EmuHintText $p.DisplayName 200
            $dir = Get-EmuHintText $p.InstallLocation
            $icon = Get-EmuHintText $p.DisplayIcon
            if (-not $name -or (-not $dir -and -not $icon)) { continue }
            [void]$un.Add(@{ name = $name; dir = $dir; icon = $icon; product = (Get-EmuHintProduct $icon) })
        }
    }
    $procs = New-Object Collections.ArrayList
    $seen = @{}
    foreach ($pr in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($procs.Count -ge 300) { break }
        $path = ''
        try { $path = [string]$pr.Path } catch {}
        if (-not $path -or $seen.ContainsKey($path.ToLower())) { continue }
        $seen[$path.ToLower()] = $true
        $vi = $null
        try { $vi = $pr.MainModule.FileVersionInfo } catch {}
        $prod = ''
        $desc = ''
        if ($null -ne $vi) { $prod = Get-EmuHintText $vi.ProductName 200; $desc = Get-EmuHintText $vi.FileDescription 200 }
        [void]$procs.Add(@{ path = (Get-EmuHintText $path); product = $prod; desc = $desc })
    }
    return @{ uninstall = @($un); procs = @($procs) }
}
# Installierte Store-Apps dieses Kontos (ohne System-Apps, Frameworks und Apps ohne Eintrag im
# Startmenü): [{ aumid, name }]. Keine Eingaben.
function Get-StoreApps {
    $out = New-Object Collections.ArrayList
    $pk = @()
    try { $pk = @(Get-AppxPackage -PackageTypeFilter Main -ErrorAction Stop) } catch {}
    foreach ($p in $pk) {
        if ($out.Count -ge 400) { break }
        try {
            if ($p.IsFramework -or [string]$p.SignatureKind -eq 'System') { continue }
            $m = Read-AppManifest ([string]$p.InstallLocation)
            if ($null -eq $m) { continue }
            $fam = [string]$p.PackageFamilyName
            foreach ($ap in (Get-AppNodes $m)) {
                $aumid = $fam + '!' + [string]$ap.GetAttribute('Id')
                if (-not (Test-Aumid $aumid)) { continue }
                $ve = $ap.SelectSingleNode("*[local-name()='VisualElements']")
                if ($null -eq $ve -or [string]$ve.GetAttribute('AppListEntry') -eq 'none') { continue }
                $name = Get-AppText $p ([string]$ve.GetAttribute('DisplayName'))
                if (-not $name) {
                    $pd = $m.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Properties']/*[local-name()='DisplayName']")
                    if ($null -ne $pd) { $name = Get-AppText $p ([string]$pd.InnerText) }
                }
                [void]$out.Add(@{ aumid = $aumid; name = $name })
            }
        } catch {}
    }
    return @{ apps = @($out) }
}
# Logo einer Store-App (Square150x150, sonst 44x44) als PNG, nur aus ihrem Paketordner, höchstens
# 512 KB. Uzai dekodiert und speichert es neu (AppsExtern.save_logo).
function Get-AppLogo([string]$aumid) {
    if (-not (Test-Aumid $aumid)) { throw 'Ungültige App-Kennung.' }
    $f = Find-StorePackage $aumid
    if ($null -eq $f) { return @{ found = $false } }
    $loc = ([string]$f.pkg.InstallLocation).TrimEnd('\')
    $ve = $f.app.SelectSingleNode("*[local-name()='VisualElements']")
    if ($null -eq $ve) { return @{ found = $false } }
    $bg = [string]$ve.GetAttribute('BackgroundColor')
    if ($bg -notmatch '^#[0-9A-Fa-f]{6}\z') { $bg = '' }
    foreach ($attr in @('Square150x150Logo', 'Square44x44Logo')) {
        $rel = [string]$ve.GetAttribute($attr)
        if (-not $rel -or $rel.Length -gt 200 -or $rel -notmatch '^[A-Za-z0-9_\-. \\/]+\.png\z' -or $rel.Contains('..')) { continue }
        $full = [IO.Path]::GetFullPath((Join-Path $loc ($rel -replace '/', '\')))
        if (-not $full.StartsWith($loc + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $dir = Split-Path -Parent $full
        $stem = [IO.Path]::GetFileNameWithoutExtension($full)
        $cands = @($full)
        foreach ($q in @('scale-200', 'scale-150', 'scale-125', 'scale-100', 'scale-400', 'targetsize-256', 'targetsize-96', 'targetsize-48')) {
            $cands += (Join-Path $dir ($stem + '.' + $q + '.png'))
        }
        foreach ($c in $cands) {
            if (-not (Test-Path -LiteralPath $c -PathType Leaf)) { continue }
            $len = (Get-Item -LiteralPath $c).Length
            if ($len -le 0 -or $len -gt 524288) { continue }
            return @{ found = $true; png = [Convert]::ToBase64String([IO.File]::ReadAllBytes($c)); bg = $bg }
        }
    }
    return @{ found = $false }
}
# Windows-Mediensitzung genau dieser App (offizielle Schnittstelle, nur Titel, Interpret, Bild).
function Get-AppMedia([string]$id) {
    if (-not (Test-AppMediaId $id)) { throw 'Ungültige Kennung.' }
    Use-MediaMgr
    $s = $null
    foreach ($x in $script:MediaMgr.GetSessions()) {
        if ([string]::Equals([string]$x.SourceAppUserModelId, $id, [StringComparison]::OrdinalIgnoreCase)) { $s = $x; break }
    }
    if ($null -eq $s) { return @{ active = $false } }
    $p = Await-Op ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    $pb = $s.GetPlaybackInfo()
    $art = ''
    if ($p.Thumbnail) {
        try {
            # uzai-cover-*: räumt Get-MediaInfo nach zwei Tagen mit weg.
            $file = Join-Path $env:TEMP ('uzai-cover-app-' + [Math]::Abs(($id + '|' + [string]$p.Title).GetHashCode()) + '.png')
            if (-not (Test-Path -LiteralPath $file)) {
                $st = Await-Op ($p.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                $net = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($st)
                # Wie Get-MediaInfo: erst ganz in eine Nebendatei, dann umbenennen. Ein leerer Strom (die App meldet das
                # Bild manchmal, bevor es da ist) oder ein Abbruch bliebe sonst als kaputtes Bild liegen – und weil die
                # Datei dann „da“ ist, käme für diesen Titel nie wieder eins.
                $part = $file + '.teil'
                $fs = [IO.File]::Create($part)
                try { $net.CopyTo($fs) } finally { $fs.Close(); $net.Close() }
                if ((Get-Item -LiteralPath $part).Length -lt 12) {
                    try { [IO.File]::Delete($part) } catch {}
                    throw 'kein Bild'
                }
                Move-Item -LiteralPath $part -Destination $file -Force
            }
            $art = $file
        } catch { $art = '' }
    }
    return @{ active = $true; title = (Get-AppCleanText $p.Title); artist = (Get-AppCleanText $p.Artist); playing = ([string]$pb.PlaybackStatus -eq 'Playing'); art = $art }
}
# Programm starten: geprüft, ohne Shell, Parameter als Liste (Join-StartArgv quotet jeden einzeln).
function Start-AppProgram([string]$path, $list) {
    $argv = @()
    if ($null -ne $list) { $argv = @($list) }
    if ($argv.Count -gt 16) { throw 'Zu viele Startparameter.' }
    foreach ($x in $argv) { if ($x -isnot [string] -or $x.Length -gt 260) { throw 'Ungültiger Startparameter.' } }
    $why = Test-Program $path
    if ($why) { throw $why }
    $exe = ([string]$path).Trim() -replace '/', '\'
    $wd = $exe.Substring(0, $exe.LastIndexOf('\'))
    if ($wd.EndsWith(':')) { $wd += '\' }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = Join-StartArgv $argv '.exe'
    $psi.WorkingDirectory = $wd
    $psi.UseShellExecute = $false
    $pr = [Diagnostics.Process]::Start($psi)
    return @{ pid = $pr.Id }
}
# Store-App starten: nur eine geprüfte, für dieses Konto installierte AUMID, ohne Parameter.
function Start-StoreApp([string]$aumid) {
    if (-not (Test-Aumid $aumid)) { throw 'Ungültige App-Kennung.' }
    if ($null -eq (Find-StorePackage $aumid)) { throw 'Diese App ist für dieses Windows-Konto nicht installiert.' }
    Use-AppAct
    $r = [UzAppAct]::Activate($aumid)
    if ($r -le 0) { throw 'Windows hat die App nicht gestartet.' }
    return @{ pid = [int]$r }
}

function Join-StartArgv($list, [string]$ext) {
    if ($null -eq $list) { return '' }
    $items = @($list)
    if ($items.Count -eq 0) { return '' }
    if ($ext -ne '.exe') { throw 'Startparameter-Liste nur für .exe' }
    if ($items.Count -gt 64) { throw 'Zu viele Startparameter' }
    $out = New-Object Collections.Generic.List[string]
    foreach ($x in $items) {
        if ($x -isnot [string]) { throw 'Ungültiger Startparameter' }
        if ($x.Length -eq 0 -or $x.Length -gt 1024 -or $x -match '[\x00-\x1f\x7f]') { throw 'Ungültiger Startparameter' }
        if ($x.IndexOfAny([char[]]@(' ', "`t", '"')) -lt 0) { $out.Add($x); continue }
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $x.ToCharArray()) {
            if ($ch -eq [char]92) { $bs++; continue }
            if ($ch -eq [char]34) { [void]$sb.Append([char]92, [int]($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
            if ($bs -gt 0) { [void]$sb.Append([char]92, [int]$bs) }
            $bs = 0
            [void]$sb.Append($ch)
        }
        if ($bs -gt 0) { [void]$sb.Append([char]92, [int]($bs * 2)) }
        [void]$sb.Append('"')
        $out.Add($sb.ToString())
    }
    return ($out -join ' ')
}

function Invoke-Command-Json($req) {
    $a = $req.args
    switch ($req.cmd) {
        'bt-scan' { return (Bt-Scan $a) }
        'bt-pair' { return (Bt-Pair $a) }
        # Apps (Store-Apps und Programme, src/core/apps_extern.gd): alles geprüft, siehe oben.
        'store-apps' { return (Get-StoreApps) }
        'emu-hints' { return (Get-EmuHints) }
        'app-logo' { return (Get-AppLogo ([string]$a.aumid)) }
        'app-media' { return (Get-AppMedia ([string]$a.id)) }
        'app-start' {
            $kind = [string]$a.kind
            if ($kind -eq 'store') { return (Start-StoreApp ([string]$a.aumid)) }
            if ($kind -eq 'prog') { return (Start-AppProgram ([string]$a.path) $a.args) }
            throw 'Unbekannte Art.'
        }
        'prog-check' {
            $why = Test-Program ([string]$a.path)
            $name = ''
            if (-not $why) {
                try {
                    $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo((([string]$a.path).Trim() -replace '/', ''))
                    $name = Get-AppCleanText $(if ($vi.ProductName) { $vi.ProductName } else { $vi.FileDescription })
                } catch {}
            }
            return @{ ok = (-not $why); why = $why; name = $name }
        }
        'app-window' {
            $wp = Get-Zahl $a.pid 5 2147483647
            $au = ''
            if ($a.aumid -is [string] -and (Test-Aumid $a.aumid)) { $au = [string]$a.aumid }
            if (($null -eq $wp -and $au -eq '') -or $wp -eq $PID) { return @{ hwnd = 0 } }
            if ($null -eq $wp) { $wp = 0 }
            Use-AppAct
            return @{ hwnd = [UzAppAct]::WindowOf([int]$wp, $au) }
        }
        'app-vollbild' {
            # Eigene App randlos auf den ganzen Bildschirm bzw. zurück, wie sie war (UzAppAct.Randlos/
            # Zurueck). taste: das eigene Vollbild der App (F11) – nur aus der Liste für Apps, nur wenn
            # genau dieses Fenster vorn ist; Uzai fragt danach noch einmal (dann randlos, falls nötig).
            $t = Test-ExtAppWindow $a
            if (-not $t.ok) { return @{ done = $false; why = $t.why } }
            $h = [IntPtr](Get-Hwnd $a.hwnd)
            if (-not ($a.an -is [bool] -and $a.an)) {
                [UzAppRand]::Stop()
                return @{ done = [UzAppAct]::Zurueck($h) }
            }
            # Rand oben frei, solange genau dieses Fenster vorn liegt (UzAppRand): keine Titelleiste, kein „X“.
            [UzAppRand]::Start($h, [int]$t.pid)
            if ([UzAppAct]::Covers($h)) { return @{ done = $true; art = 'schon'; voll = $true } }
            $taste = [string]$a.taste
            if ($taste -ne '') {
                if ((Test-KeyCombo $taste 'app') -ne '') { return @{ done = $false; why = 'nicht erlaubt' } }
                if ([UzWin]::GetForegroundWindow() -eq $h -and [UzGuard]::Problem($h) -eq '' -and (Test-KeyRate 'fenster')) {
                    $n = Send-Keys $taste
                    return @{ done = ($n -gt 0); art = 'taste'; voll = $false }
                }
            }
            $voll = [UzAppAct]::Randlos($h)
            return @{ done = $true; art = 'randlos'; voll = $voll }
        }
        'app-text' {
            # Text aus Uzais Tastatur in das Textfeld der App vorn (UzPad.AppType): Fenster geprüft wie bei
            # app-pad, Text eng geprüft, höchstens 2,5 s warten, bis genau dieses Fenster vorn ist, dann nur,
            # wenn dort ein Textfeld den Fokus hat (UzAppFeld) – nie ein geschütztes Fenster.
            $t = Test-ExtAppWindow $a
            if (-not $t.ok) { return @{ done = $false; why = $t.why } }
            if (-not ($a.text -is [string]) -or -not [UzPad]::AppTextOk([string]$a.text)) { return @{ done = $false; why = 'ungültiger Text' } }
            if (-not (Test-KeyRate 'fenster')) { return @{ done = $false; why = 'zu schnell' } }
            $h = [IntPtr](Get-Hwnd $a.hwnd)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ([UzWin]::GetForegroundWindow() -ne $h -and $sw.ElapsedMilliseconds -lt 2500) { Start-Sleep -Milliseconds 50 }
            if ([UzWin]::GetForegroundWindow() -ne $h -or [UzGuard]::Problem($h) -ne '') { return @{ done = $false; why = 'nicht vorn' } }
            try { Use-AppFeld } catch { return @{ done = $false; why = 'keine Bedienhilfe' } }
            Use-AppAct
            [UzAppFeld]::Start($h, [int]$t.pid, [UzAppAct]::FrameContentPid($h))
            if ([UzAppFeld]::Pruefen(1200) -le 0) { return @{ done = $false; why = 'kein Textfeld' } }
            $n = [UzPad]::AppType($h, [int]$t.pid, [string]$a.text)
            return @{ done = ($n -gt 0); n = $n }
        }
        'app-pad' {
            # Controller als Tasten nur für dieses App-Fenster (UzPad.AppStep). Aus: sofort.
            if (-not ($a.an -is [bool] -and $a.an)) { [UzPad]::AppStop(); if ($script:AppFeldReady) { [UzAppFeld]::Stop() }; return @{ an = $false } }
            $t = Test-ExtAppWindow $a
            if (-not $t.ok) { [UzPad]::AppStop(); return @{ an = $false; why = $t.why } }
            $codes = New-Object int[] 6
            $i = 0
            foreach ($k in @('a', 'b', 'x', 'y', 'lb', 'rb')) {
                $c = Get-AppPadCode $(if ($null -ne $a.tasten) { $a.tasten.$k } else { $null })
                if ($null -eq $c) { [UzPad]::AppStop(); return @{ an = $false; why = 'nicht erlaubt' } }
                $codes[$i] = [int]$c
                $i++
            }
            # Der Wächter läuft schon (pad-watch beim Start des Helfers, derselbe Weg).
            $h = [IntPtr](Get-Hwnd $a.hwnd)
            $on = [UzPad]::AppStart($h, [int]$t.pid, $codes)
            # Textfeld im Blick (Y öffnet dann Uzais Tastatur); geht das nicht, bleibt alles andere.
            # Der Zeiger mit dem rechten Stick meidet denselben Rand oben wie die Maus (UzAppRand).
            if ($on) { try { Use-AppAct; [UzPad]::AppTopRand = [UzAppRand]::RandFuer($h) } catch {} }
            if ($on) { try { Use-AppFeld; [UzAppFeld]::Start($h, [int]$t.pid, [UzAppAct]::FrameContentPid($h)) } catch {} }
            return @{ an = $on }
        }
        'ping' { return @{ pong = $true; pid = $PID } }
        'windows' {
            $list = @()
            foreach ($h in [UzWin]::WindowsOf([int]$a.pid)) { $list += @{ hwnd = $h.ToInt64(); title = [UzWin]::Title($h) } }
            return @{ windows = $list }
        }
        'toast-window' { return @{ ok = [UzWin]::NoActivate([IntPtr][long]$a.hwnd) } }
        'focus' {
            $h = Find-Target $a
            if ($h -eq [IntPtr]::Zero) { return @{ focused = $false } }
            # Mit Zeitgrenze im eigenen Faden: Hängt der Wechsel doch, wartet nichts dahinter.
            $fo = [UzLive]::FocusBounded($h.ToInt64(), 1200)
            return @{ focused = ($fo -eq 1); haengt = ($fo -eq -1) }
        }
        'spiel-minimieren' {
            # Guide über exklusivem Vollbild: nur das bekannte Fenster des Spiels, nie Uzai selbst.
            $h = [IntPtr](Get-Hwnd $a.hwnd)
            if ($h -eq [IntPtr]::Zero) { return @{ ok = $false } }
            $p = [UzWin]::PidOf($h)
            $want = @(@($a.pids) | ForEach-Object { Get-Zahl $_ 1 2147483647 } | Where-Object { $null -ne $_ })
            if ($p -eq $PID -or $p -eq [int](Get-Zahl $a.own 1 2147483647) -or ($want.Count -gt 0 -and -not ($want -contains $p))) { return @{ ok = $false } }
            return @{ ok = [UzWin]::MinimizeAsync($h) }
        }
        'no-anim' { return @{ ok = [UzWin]::NoTransitions([IntPtr]([long]$a.hwnd)) } }
        'gamebar' {
            # Öffnet die Guide-Taste zusätzlich die Xbox Game Bar? Nur auf ausdrücklichen Wunsch
            # (Knopf in Uzai) wird die Einstellung des eigenen Windows-Kontos umgeschaltet – dieselbe
            # wie unter Einstellungen → Spielen → Game Bar „mit dieser Taste öffnen“.
            $key = 'HKCU:\Software\Microsoft\GameBar'
            if ($null -ne $a.set) {
                if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
                Set-ItemProperty -Path $key -Name 'UseNexusForGameBarEnabled' -Value ([int][bool]$a.set) -Type DWord
            }
            $on = $true
            try { $on = [int](Get-ItemProperty -Path $key -Name 'UseNexusForGameBarEnabled' -ErrorAction Stop).UseNexusForGameBarEnabled -ne 0 } catch {}
            return @{ enabled = $on }
        }
        'windows-snapshot' {
            $skip = [int[]]@($a.skip | ForEach-Object { [int]$_ })
            $ids = @([UzWin]::BigWindows(200, 120, $skip) | ForEach-Object { [long]($_.Split('|')[0]) })
            return @{ hwnds = $ids }
        }
        'window-alive' {
            $h = [IntPtr]([long]$a.hwnd)
            return @{ alive = ([UzWin]::IsWindow($h) -and [UzWin]::IsWindowVisible($h)) }
        }
        'window-hung' {
            # Antwortet das Fenster nicht mehr? Windows sagt das nach 5 s ohne Nachrichten (wie „Keine Rückmeldung“).
            $h = [IntPtr]([long]$a.hwnd)
            $ok = [UzWin]::IsWindow($h)
            return @{ alive = $ok; hung = ($ok -and [UzWin]::IsHungAppWindow($h)); pid = [UzWin]::PidOf($h) }
        }
        'exit-code' { return @{ code = [UzWin]::ExitCode([int]$a.pid) } }
        'crash-event' { return (Find-CrashEvent $a) }
        'close-window' {
            # Wie Alt+F4: das Fenster bittet das Programm, sich zu beenden (Spiel kann noch speichern).
            # Ohne bekanntes Fenster: das Hauptfenster des gestarteten Prozesses (nur eine Zahl).
            $h = [IntPtr](Get-Hwnd $a.hwnd)
            if ($h -eq [IntPtr]::Zero) {
                $wp = Get-Zahl $a.pid 5 2147483647
                if ($null -ne $wp -and $wp -ne $PID) { $h = [UzWin]::Best([int[]]@($wp)) }
            }
            if ($h -eq [IntPtr]::Zero) { return @{ sent = $false; pid = 0 } }
            $p = 0
            [void][UzWin]::GetWindowThreadProcessId($h, [ref]$p)
            if ($p -eq $PID) { return @{ sent = $false; pid = 0 } }
            $sent = [UzWin]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero)
            return @{ sent = $sent; pid = $p; hwnd = $h.ToInt64() }
        }
        'new-window' {
            # Neues großes Fenster seit dem Schnappschuss; eines der Spielprozesse hat Vorrang.
            $skip = [int[]]@($a.skip | ForEach-Object { [int]$_ })
            $known = @{}
            foreach ($k in @($a.known)) { $known[[long]$k] = $true }
            $want = @{}
            foreach ($p in @($a.pids)) { $want[[int]$p] = $true }
            $minW = if ($a.min_w) { [int]$a.min_w } else { 640 }
            $minH = if ($a.min_h) { [int]$a.min_h } else { 360 }
            $pick = $null
            foreach ($row in [UzWin]::BigWindows($minW, $minH, $skip)) {
                $f = $row.Split('|', 5)
                if ($known.ContainsKey([long]$f[0])) { continue }
                $cand = @{ found = $true; hwnd = [long]$f[0]; pid = [int]$f[1]; w = [int]$f[2]; h = [int]$f[3]; title = $f[4]; game = $want.ContainsKey([int]$f[1]) }
                if ($cand.game) { $pick = $cand; break }
                if ($null -eq $pick) { $pick = $cand }
            }
            if ($null -eq $pick) { return @{ found = $false } }
            return $pick
        }
        'keys' {
            # Tasten an ein Zielfenster (hwnd, pid oder pids) – nur, wenn es sicher vorn ist: Ohne
            # Ziel, bei einem Anmelde- oder Sicherheitsfenster oder wenn Windows es nicht nach vorn
            # lässt, wird nichts gedrückt (früher nur mit require_focus; ohne traf es, was gerade vorn
            # lag). require_focus wird noch angenommen, gilt aber immer.
            # global: Tastenbelegung eines anderen Programms (Discord, Lossless Scaling) – nur im engen
            # Format aus Test-KeyCombo; Lossless Scaling skaliert das Vordergrundfenster, deshalb
            # auch hier erst das Spiel nach vorn. Die Antwort sagt genau, was passiert ist (fürs Protokoll).
            $global = ($a.global -is [bool] -and $a.global)
            $mode = 'fenster'
            if ($global) { $mode = 'global' }
            $why = Test-KeyCombo ([string]$a.keys) $mode
            if ($why -eq 'unbekannt') {
                return @{ sent = $false; reason = 'unbekannt'; unknown = @((Parse-Keys ([string]$a.keys) $global).unknown); keys = [string]$a.keys }
            }
            if ($why -ne '') { return @{ sent = $false; reason = $why; keys = [string]$a.keys } }
            $codes = @((Parse-Keys ([string]$a.keys) $global).codes)
            $h = Find-Target $a
            if ($h -eq [IntPtr]::Zero) { return @{ sent = $false; reason = 'nicht vorn'; window = ''; keys = [string]$a.keys } }
            $title = [UzWin]::Title($h)
            $tpid = [UzWin]::PidOf($h)
            if ([UzGuard]::Problem($h) -ne '') {
                return @{ sent = $false; reason = 'geschützt'; window = $title; target_pid = $tpid; keys = [string]$a.keys }
            }
            $focused = [UzWin]::Focus($h)
            if (-not $focused) {
                Start-Sleep -Milliseconds 200
                $focused = [UzWin]::Focus($h)
            }
            Start-Sleep -Milliseconds 250
            $fg0 = [UzWin]::GetForegroundWindow()
            $fgPid = [UzWin]::PidOf($fg0)
            $selfElev = $false
            try { $selfElev = [UzElev]::IsElevated($PID) } catch {}
            # Läuft das Vordergrundprogramm mit Adminrechten und der Helfer nicht, verwirft Windows
            # die Tasten still (UIPI) – SendInput meldet trotzdem Erfolg.
            $fgElev = $false
            if ($fgPid -gt 0 -and $fgPid -ne $PID) { try { $fgElev = [UzElev]::IsElevated($fgPid) } catch {} }
            $res = @{ sent = $false; window = $title; target_pid = $tpid; focused = $focused; foreground = [UzWin]::Title($fg0); foreground_pid = $fgPid
                foreground_class = [UzWin]::ClassOf($fg0); self_elevated = $selfElev; foreground_elevated = $fgElev; keys = [string]$a.keys; codes = $codes; global = $global }
            if (-not $focused -or $fg0 -ne $h) {
                $res.reason = 'nicht vorn'
                return $res
            }
            if ([UzGuard]::Problem($fg0) -ne '') {
                $res.reason = 'geschützt'
                return $res
            }
            if (-not (Test-KeyRate $mode)) {
                $res.reason = 'zu oft'
                return $res
            }
            $res.accepted = Send-Keys ([string]$a.keys) $global ([int]$a.hold_ms)
            $res.expected = 2 * $codes.Count
            $res.sent = $true
            Start-Sleep -Milliseconds 300
            # Nur noch Auskunft: Ein Fehler hier darf den schon erfolgten Tastendruck nicht zum
            # Fehlschlag machen.
            try { $res.foreground_after = [UzWin]::Title([UzWin]::GetForegroundWindow()) } catch {}
            try {
                $first = 0
                if ($a.pids) { $first = [int]@($a.pids)[0] } elseif ($a.pid) { $first = [int]$a.pid }
                $res.windows = @([UzWin]::WindowsOf($first) | ForEach-Object { [UzWin]::Title($_) })
            } catch {}
            if ($a.diag) { try { $res.discord = @(Discord-Processes) } catch {} }
            return $res
        }
        'live-keys' {
            # Discord „Toggle Screen Share“: Druck zuerst, mit fester Zeitgrenze (UzLive.Press),
            # Auskunft danach. Die Schritte mit Zeiten gehen zusätzlich in den Fehlerkanal, den Uzai
            # nach logs/helper.log schreibt – auch wenn Uzai die Antwort nicht mehr abwartet.
            # Nur das enge Format für Tastenbelegungen (Test-KeyCombo „global“), höchstens alle 0,4 s;
            # UzLive.Press drückt nur ins Ziel, in Uzai oder ins schon vorn liegende Fenster.
            try { [Console]::Error.WriteLine('live-keys: angekommen') } catch {}
            $parsed = Parse-Keys ([string]$a.keys) $true
            $codes = @($parsed.codes)
            $why = Test-KeyCombo ([string]$a.keys) 'global'
            if ($why -eq 'unbekannt') {
                return @{ sent = $false; reason = 'unbekannt'; unknown = @($parsed.unknown); keys = [string]$a.keys }
            }
            if ($why -ne '') { return @{ sent = $false; reason = $why; keys = [string]$a.keys } }
            if (-not (Test-KeyRate 'global')) { return @{ sent = $false; reason = 'zu oft'; keys = [string]$a.keys } }
            $ids = @()
            foreach ($p in @($a.pids)) { if ($p) { $ids += [int]$p } }
            $hw = [long]0
            if ($a.hwnd) { $hw = [long]$a.hwnd }
            $uz = 0
            if ($a.uzai_pid) { $uz = [int]$a.uzai_pid }
            $hold = 150
            if ($a.hold_ms) { $hold = [int]$a.hold_ms }
            $fms = 700
            if ($null -ne $a.focus_ms) { $fms = [int]$a.focus_ms }
            $json = [UzLive]::Press([int[]]$codes, $hw, [int[]]$ids, $uz, $hold, $fms, 2500)
            $res = $json | ConvertFrom-Json
            try { [Console]::Error.WriteLine('live-keys: ' + $res.steps + ' (angenommen ' + $res.accepted + '/' + $res.expected + ', davon Ersatzweg ' + $res.fallback + ', ' + $res.ms + ' ms)') } catch {}
            $res | Add-Member -NotePropertyName keys -NotePropertyValue ([string]$a.keys) -Force
            return $res
        }
        'discord-front' {
            # Die Discord-App nach vorn (die eine erlaubte Ausnahme: zum Übertragen und Zuschauen).
            # Wartet bis wait_ms auf ein sichtbares Fenster (nach discord:// erscheint es erst).
            $wait = 3000
            if ($a.wait_ms) { $wait = [int]$a.wait_ms }
            $deadline = (Get-Date).AddMilliseconds($wait)
            $f = @('0', '0', '')
            while ($true) {
                $f = ([UzLive]::DiscordWindow()).Split('|')
                if ([long]$f[0] -ne 0 -or (Get-Date) -gt $deadline) { break }
                Start-Sleep -Milliseconds 250
            }
            $dc = @()
            try { $dc = @(Discord-Processes) } catch {}
            if ([long]$f[0] -eq 0) { return @{ found = $false; discord = $dc } }
            # Nur die echte Discord-App (Prozessname und Pfad): Strg+V und Enter gehen danach an dieses Fenster.
            $chk = Test-AppWindow ([long]$f[0]) @('discord')
            if (-not $chk.ok) { return @{ found = $false; reason = $chk.why; discord = $dc } }
            $fo = [UzLive]::FocusBounded([long]$f[0], 1500)
            return @{ found = $true; hwnd = [long]$f[0]; pid = [int]$f[1]; name = $f[2]; focused = ($fo -eq 1); hung = ($fo -eq -1); discord = $dc }
        }
        'discord-buttons' {
            # Knöpfe in einem Fenster der Discord-App (Name, an/aus) für „In Discord übertragen“, mit
            # app = 'steam' in Steams Installationsdialog (installs.gd); Uzai wählt. Nur, wenn das
            # Fenster nach Prozessname und Pfad wirklich zu dieser App gehört – „discord-invoke“ drückt
            # nur Knöpfe aus dieser Liste und prüft das Fenster dann noch einmal.
            $app = 'discord'
            if ([string]$a.app -eq 'steam') { $app = 'steam' }
            $hw = Get-Hwnd $a.hwnd
            $script:UiaWin = $null
            $chk = Test-AppWindow $hw @($app)
            if (-not $chk.ok) { return @{ done = $true; buttons = @(); error = 'nicht erlaubt'; reason = $chk.why } }
            Use-Uia
            $h = [IntPtr]$hw
            $woke = 0
            try { $woke = [UzInput]::WakeAccessibility($h) } catch {}
            if (-not $script:UiaWoke) { $script:UiaWoke = $true; Start-Sleep -Milliseconds 500 }
            $budget = 5000
            $bm = Get-Zahl $a.budget_ms 500 15000
            if ($null -ne $bm) { $budget = $bm }
            $res = ([UzUia]::Buttons($hw, $budget)) | ConvertFrom-Json
            $res | Add-Member -NotePropertyName woke -NotePropertyValue $woke -Force
            $script:UiaWin = @{ hwnd = $hw; app = $app; pid = [int]$chk.pid }
            return $res
        }
        'discord-invoke' {
            # Knopf Nummer i aus der letzten Liste – nur, wenn das Fenster noch dieselbe erlaubte App ist
            # und der Knopf zu einem Programm derselben App gehört (Prozessname und Pfad).
            $w = $script:UiaWin
            if ($null -eq $w -or -not $script:UiaReady) { return @{ result = 'nicht erlaubt' } }
            $i = Get-Zahl $a.i 0 399
            if ($null -eq $i) { return @{ result = 'weg' } }
            $chk = Test-AppWindow ([long]$w.hwnd) @([string]$w.app)
            if (-not $chk.ok -or [int]$chk.pid -ne [int]$w.pid) { $script:UiaWin = $null; return @{ result = 'nicht erlaubt' } }
            $epid = [UzUia]::ElementPid($i, 1500)
            if ($epid -le 0) { return @{ result = 'weg' } }
            if ($epid -ne [int]$w.pid) {
                $en = ''; $ep = ''
                try { $en = [string](Get-Process -Id $epid -ErrorAction Stop).ProcessName } catch {}
                try { $ep = [UzLs]::ImagePath($epid) } catch {}
                $sd = ''
                if ($w.app -eq 'steam') { $sd = Get-SteamDir }
                if (-not (Test-AppPath ([string]$w.app) $en $ep ([string]$env:LOCALAPPDATA) $sd)) { return @{ result = 'nicht erlaubt' } }
            }
            return @{ result = [UzUia]::Invoke($i, 3000) }
        }
        # --- Installieren über Uzai (Installs): Dialoge von Steam/Epic im Hintergrund bedienen ---
        'proc-windows' {
            # Sichtbare Fenster bestimmter Programme (steamwebhelper, EpicGamesLauncher …): hwnd,
            # Titel, Klasse, Größe, minimiert, vorn. minimize: diese Fenster ohne Fokus minimieren
            # (7 = SW_SHOWMINNOACTIVE), außer denen in keep. Nichts wird geschlossen.
            $names = @($a.names | ForEach-Object { [string]$_ })
            $keep = @{}
            foreach ($k in @($a.keep)) { if ($k) { $keep[[long]$k] = $true } }
            $fg = [UzWin]::GetForegroundWindow()
            $list = @()
            foreach ($p in @(Get-Process -Name $names -ErrorAction SilentlyContinue)) {
                foreach ($h in [UzWin]::WindowsOf($p.Id)) {
                    $r = New-Object UzWin+RECT
                    $w = 0; $hh = 0
                    if ([UzWin]::GetWindowRect($h, [ref]$r)) { $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top }
                    $min = [UzWin]::IsIconic($h)
                    if ($a.minimize -and -not $min -and -not $keep.ContainsKey($h.ToInt64())) { [void][UzWin]::ShowWindow($h, 7); $min = $true }
                    $list += @{ hwnd = $h.ToInt64(); title = [UzWin]::Title($h); cls = [UzWin]::ClassOf($h); pid = $p.Id; name = $p.ProcessName; w = $w; h = $hh; min = $min; fg = ($h -eq $fg) }
                }
            }
            return @{ windows = $list }
        }
        'window-keys' {
            # Tasten an ein Fenster, das hinter Uzai liegt (Uzai ist dabei „immer oben“): kurz
            # dieses Fenster wählen, drücken, sofort zurück zu Uzai (back_pid). stay: das Fenster
            # behält die Tastatur (Epic Games Launcher, siehe window_remote.gd) – nur wählen, wenn es
            # sie verloren hat, und nicht zurückspringen.
            # Nur Fenster von Steam und Epic (Prozessname und Pfad), nur die Bedientasten aus
            # Test-KeyCombo „dialog“ (Tab, Pfeile, Enter, Leertaste, Esc).
            $why = Test-KeyCombo ([string]$a.keys) 'dialog'
            if ($why -ne '') { return @{ sent = $false; reason = $why } }
            $hw = Get-Hwnd $a.hwnd
            $chk = Test-AppWindow $hw @('steam', 'epic')
            if (-not $chk.ok) { return @{ sent = $false; reason = 'nicht erlaubt'; why = $chk.why } }
            $h = [IntPtr]$hw
            if (-not [UzWin]::IsWindowVisible($h)) { return @{ sent = $false; reason = 'kein Fenster' } }
            $stay = ($a.stay -eq $true)
            $focused = $true
            if (-not $stay -or [UzWin]::GetForegroundWindow() -ne $h) {
                $focused = [UzWin]::Focus($h)
                Start-Sleep -Milliseconds 90
            }
            $n = 0
            if ([UzWin]::GetForegroundWindow() -eq $h -and (Test-KeyRate 'dialog')) { $n = Send-Keys ([string]$a.keys) }
            Start-Sleep -Milliseconds 60
            if ($stay) { return @{ sent = ($n -gt 0); focused = $focused; n = $n } }
            if ($a.back_pid) {
                $u = Find-Target @{ pid = [int]$a.back_pid }
                if ($u -ne [IntPtr]::Zero) { [void][UzWin]::Focus($u) }
            }
            return @{ sent = ($n -gt 0); focused = $focused; n = $n }
        }
        'window-focus' {
            # Ein Fenster bekommt die Tastatur (Epic Games Launcher in Uzai bedienen); Uzai bleibt
            # sichtbar oben. Nur eine Fensternummer von Steam oder Epic, nichts wird gestartet oder umgestellt.
            $hw = Get-Hwnd $a.hwnd
            $chk = Test-AppWindow $hw @('steam', 'epic')
            if (-not $chk.ok) { return @{ focused = $false; reason = 'nicht erlaubt'; why = $chk.why } }
            $h = [IntPtr]$hw
            if (-not [UzWin]::IsWindowVisible($h)) { return @{ focused = $false; reason = 'kein Fenster' } }
            return @{ focused = [UzWin]::Focus($h) }
        }
        'pip' { return (Pip-Call $a) }
        'window-snap' {
            Use-Snap
            return @{ result = [UzSnap]::Capture([long]$a.hwnd, [string]$a.path, [int]$a.max_w) }
        }
        'window-frame' {
            # Fernseher im Zimmer: Bild des Spielfensters nur im Speicher (nie auf der Platte).
            # Nur Zahlen, fest begrenzt; nichts wird umgestellt oder nach vorn geholt.
            $hw = [long]$a.hwnd
            if ($hw -le 0) { return @{ result = 'kein Fenster' } }
            Use-Snap
            $mw = [Math]::Max(64, [Math]::Min(1280, [int]$a.max_w))
            $q = [Math]::Max(30, [Math]::Min(90, [int]$a.q))
            $r = [UzSnap]::Frame($hw, $mw, $q, 1500)
            if ($r.StartsWith('ok|')) { return @{ result = 'ok'; jpg = $r.Substring(3) } }
            return @{ result = $r }
        }
        'discord-diag' {
            $selfElev = $false
            try { $selfElev = [UzElev]::IsElevated($PID) } catch {}
            $game = @()
            foreach ($p in @($a.pids)) {
                if (-not $p) { continue }
                $e = $null
                try { $e = [UzElev]::IsElevated([int]$p) } catch {}
                $name = ''
                try { $name = (Get-Process -Id ([int]$p) -ErrorAction Stop).ProcessName } catch {}
                $game += @{ pid = [int]$p; name = $name; elevated = $e }
            }
            return @{ discord = @(Discord-Processes); self_elevated = $selfElev; game = $game }
        }
        'cover' {
            # Startbildschirm vorn halten (siehe UzCover). max_s: Sicherheitsgrenze.
            if ($a.on) {
                $max = if ($a.max_s) { [int]$a.max_s } else { 150 }
                [UzCover]::Start([IntPtr]([long]$a.hwnd), $max * 1000)
            } else { [UzCover]::Stop([IntPtr]([long]$a.hwnd), [bool]$a.top, [bool]$a.behind_front) }
            return @{ active = [UzCover]::Active(); raised = [UzCover]::Raised }
        }
        'vorhang' {
            # Vorhang zwischen Uzai und dem Spiel (siehe UzEbenen): nur Zahlen, fest begrenzt.
            Use-Ebenen
            if ($a.an -is [bool] -and $a.an) {
                $bezug = Get-Hwnd $a.hwnd
                $ms = Get-Zahl $a.max_ms 200 180000
                $farbe = Get-Zahl $a.farbe 0 16777215
                if ($bezug -eq 0 -or $null -eq $ms -or $null -eq $farbe) { return @{ an = $false; grund = 'daten' } }
                $lochMs = Get-Zahl $a.loch_ms 0 5000
                if ($null -eq $lochMs) { $lochMs = 0 }
                $einMs = Get-Zahl $a.ein_ms 0 1000
                if ($null -eq $einMs) { $einMs = 0 }
                # Beim Beenden: Loch nur um Fenster des Spiels (Prozessnummern, höchstens 64).
                $lochPids = [int[]]@(@($a.loch_pids) | Select-Object -First 64 | ForEach-Object { Get-Zahl $_ 5 2147483647 } | Where-Object { $null -ne $_ })
                $n = [UzEbenen]::VorhangAn($bezug, $farbe, $ms, ($a.loch -is [bool] -and $a.loch), ($a.loch_uzai -is [bool] -and $a.loch_uzai), $lochMs, $einMs,
                    ($a.immer -is [bool] -and $a.immer), $lochPids)
                # Erst antworten, wenn er wirklich auf dem Bildschirm steht (höchstens 0,8 s).
                $stand = [UzEbenen]::Stand($n, 800)
                return @{ an = [UzEbenen]::VorhangAktiv(); sichtbar = ($stand -eq 1); noetig = ($stand -ne 0); ausgeloest = [UzEbenen]::Ausgeloest }
            } else {
                $weich = Get-Zahl $a.weich_ms 0 1000
                if ($null -eq $weich) { $weich = 200 }
                [UzEbenen]::VorhangAus($weich)
            }
            return @{ an = [UzEbenen]::VorhangAktiv(); ausgeloest = [UzEbenen]::Ausgeloest }
        }
        'vorhang-wache' {
            # Solange das Spiel läuft: verschwindet sein Fenster, zieht der Helfer den Vorhang sofort zu.
            Use-Ebenen
            $spiel = Get-Hwnd $a.spiel
            if ($a.an -is [bool] -and $a.an -and $spiel -ne 0) {
                $ms = Get-Zahl $a.max_ms 200 180000
                $farbe = Get-Zahl $a.farbe 0 16777215
                if ($null -eq $ms -or $null -eq $farbe) { return @{ an = $false; grund = 'daten' } }
                [void][UzEbenen]::Wache($true, (Get-Hwnd $a.hwnd), $spiel, $farbe, $ms)
            } else { [void][UzEbenen]::Wache($false, 0, 0, 0, 200) }
            return @{ an = [UzEbenen]::WacheAktiv() }
        }
        'tv-fang' {
            # Fernseher im Zimmer, aufgestanden: Windows liefert die Bilder des Spielfensters (siehe
            # UzTvFang). Nur Zahlen; nichts kommt nach vorn. an: true startet bzw. hält am Leben.
            Use-TvFang
            if (-not ($a.an -is [bool] -and $a.an)) { [UzTvFang]::Stop(); return @{ an = $false } }
            $spiel = Get-Hwnd $a.spiel
            $mw = Get-Zahl $a.max_w 64 1280
            $mh = Get-Zahl $a.max_h 36 1280
            $fps = Get-Zahl $a.fps 1 60
            if ($spiel -eq 0 -or $null -eq $mw -or $null -eq $mh -or $null -eq $fps) { [UzTvFang]::Stop(); return @{ an = $false; grund = 'daten' } }
            if ([UzWin]::PidOf([IntPtr]$spiel) -eq $PID) { [UzTvFang]::Stop(); return @{ an = $false; grund = 'daten' } }
            # Mit Bildfilter (ShaderGlass): dessen Bild, wie im Vollbild.
            $q = Get-Zahl $a.quelle 5 2147483647
            if ($null -ne $q -and $q -ne $PID) {
                $hq = [UzWin]::Best([int[]]@($q))
                if ($hq -ne [IntPtr]::Zero -and [UzWin]::IsWindowVisible($hq) -and [UzWin]::PidOf($hq) -eq $q) { $spiel = $hq.ToInt64() }
            }
            # Rückfall Spiegel (spielbild.gd, nur auf Uzais Wunsch): Windows zeichnet das Spiel in ein
            # eigenes Helferfenster gleich unter Uzais Fenster (hwnd), aufgenommen wird dieses.
            $bezug = [long]0
            $spiegel = ($a.spiegel -is [bool] -and $a.spiegel)
            if ($spiegel) {
                $bezug = Get-Hwnd $a.hwnd
                if ($bezug -eq 0 -or $bezug -eq $spiel -or [UzWin]::PidOf([IntPtr]$bezug) -eq [UzWin]::PidOf([IntPtr]$spiel)) {
                    [UzTvFang]::Stop(); return @{ an = $false; grund = 'daten' }
                }
            }
            $datei = Get-TvFangDatei
            [UzTvFang]::Start($spiel, $mw, $mh, $fps, $datei, $bezug, $spiegel)
            $t0 = [DateTime]::UtcNow
            while ([UzTvFang]::Stand() -eq 0 -and ([DateTime]::UtcNow - $t0).TotalMilliseconds -lt 1500) { Start-Sleep -Milliseconds 15 }
            $st = [UzTvFang]::Stand()
            # Messwerte für launch.log: Grafikkarte/HDR, erstes Bild, Zustand des Spielfensters, Formatwechsel.
            return @{ an = ($st -eq 1 -or $st -eq 3); stand = $st; grund = [UzTvFang]::Grund(); datei = $datei; rand_aus = [UzTvFang]::RandAus();
                bilder = [UzTvFang]::Bilder(); w = [UzTvFang]::Breite(); h = [UzTvFang]::Hoehe(); info = [UzTvFang]::Info();
                erstes = [UzTvFang]::Erstes(); zustand = [UzTvFang]::Zustand($spiel); wechsel = [UzTvFang]::Wechsel();
                schwarz = [UzTvFang]::SchwarzFolge(); format = [UzTvFang]::Format(); ms = [Math]::Round([UzTvFang]::Ms(), 2); spiegel = [UzTvFang]::Spiegel() }
        }
        'uzai-vorrang' {
            # Uzai nimmt sich selbst zurück, solange es neben einem laufenden Spiel zeichnet (Zimmer,
            # aufgestanden): Grafikkarte und (cpu, Standard ja) Prozessor „unter normal“, das Spiel kommt
            # zuerst; danach wieder wie vorher. cpu = $false lässt den Prozessor normal (und stellt eine
            # frühere Zurücknahme zurück). Nur Uzais eigener Prozess (der diesen Helfer gestartet hat und
            # dem das Fenster gehört) – nie ein anderer, nie höher als vorher. Nur Zahlen und Ja/Nein.
            $p = Get-Zahl $a.pid 1 2147483647
            $h = Get-Hwnd $a.hwnd
            if ($null -eq $p -or $h -eq 0 -or $p -eq $PID -or [UzWin]::PidOf([IntPtr]$h) -ne $p -or $p -ne (Get-UzaiPid)) { return @{ ok = $false; grund = 'daten' } }
            $leise = ($a.leise -is [bool] -and $a.leise)
            $cpu = -not ($a.cpu -is [bool] -and -not $a.cpu)
            try {
                $proc = [Diagnostics.Process]::GetProcessById($p)
                if ($leise -and $cpu) {
                    if ($null -eq $script:UzaiPrioVorher) { $script:UzaiPrioVorher = $proc.PriorityClass }
                    if ($proc.PriorityClass -ne [Diagnostics.ProcessPriorityClass]::Idle) { $proc.PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal }
                } elseif ($null -ne $script:UzaiPrioVorher) {
                    $proc.PriorityClass = $script:UzaiPrioVorher
                    $script:UzaiPrioVorher = $null
                } elseif ($proc.PriorityClass -eq [Diagnostics.ProcessPriorityClass]::BelowNormal) {
                    # Ein früherer Helfer hatte zurückgenommen (und ist inzwischen neu gestartet).
                    $proc.PriorityClass = [Diagnostics.ProcessPriorityClass]::Normal
                }
                Use-TvFang
                $gpu = [UzTvFang]::GpuStufe($proc.Handle, $leise)
                return @{ ok = $true; cpu = [string]$proc.PriorityClass; gpu = $gpu }
            } catch { return @{ ok = $false; grund = $_.Exception.Message } }
        }
        'cursor-park' {
            $h = if ($a.hwnd) { [IntPtr]([long]$a.hwnd) } else { [UzWin]::GetForegroundWindow() }
            $f = ([UzCursor]::Park($h)).Split('|')
            return @{ from_x = [int]$f[0]; from_y = [int]$f[1]; x = [int]$f[2]; y = [int]$f[3] }
        }
        'window-state' {
            # Wie steht das Spiel gerade? Vordergrundfenster (gehört es zum Spiel, deckt es den
            # Bildschirm?) und das gefundene Spielfenster. Für den Übergang vom Startbildschirm.
            $want = @{}
            foreach ($p in @($a.pids)) { if ($p) { $want[[int]$p] = $true } }
            $fg = [UzWin]::GetForegroundWindow()
            $fgPid = [UzWin]::PidOf($fg)
            $t = [IntPtr]::Zero
            if ($a.hwnd) { $t = [IntPtr]([long]$a.hwnd) }
            $r = New-Object UzWin+RECT
            $w = 0; $hh = 0
            if ($fg -ne [IntPtr]::Zero -and [UzWin]::GetWindowRect($fg, [ref]$r)) { $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top }
            $cls = [UzWin]::ClassOf($fg)
            return @{
                fg_hwnd = $fg.ToInt64(); fg_pid = $fgPid; fg_title = [UzWin]::Title($fg); fg_class = $cls; fg_w = $w; fg_h = $hh
                fg_full = [UzWin]::CoversMonitor($fg); fg_topmost = [UzWin]::IsTopmost($fg)
                fg_game = ($want.ContainsKey($fgPid) -or ($t -ne [IntPtr]::Zero -and $fg -eq $t))
                fg_shell = ($cls -in @('Shell_TrayWnd', 'Shell_SecondaryTrayWnd', 'Progman', 'WorkerW', 'Windows.UI.Core.CoreWindow'))
                target_alive = ($t -ne [IntPtr]::Zero -and [UzWin]::IsWindow($t) -and [UzWin]::IsWindowVisible($t))
                target_full = [UzWin]::CoversMonitor($t)
                target_iconic = ($t -ne [IntPtr]::Zero -and [UzWin]::IsIconic($t))
                quns = [UzWin]::Quns()
                idle_ms = [UzWin]::IdleMs()
            }
        }
        'media' {
            # Mit Musik-Liste (Uzai): gezielt an die Sitzung der Musik-App, nicht als Taste an
            # Windows (die schaltete, was zuletzt Ton hatte – etwa YouTube im Browser). Läuft nur
            # anderes, passiert nichts.
            # Die Medientaste an Windows (wirkt auf alles) nur als Notlösung: keine Sitzung ist direkt
            # steuerbar UND du hast die Aktion gerade selbst ausgelöst (user = true – Uzai setzt es nur
            # beim Druck auf Wiedergabe, Weiter, Zurück; nie beim Anhalten durch Ruhemodus oder
            # Spiel-Profil). Sonst gäbe Uzai von sich aus einem beliebigen Programm einen Befehl.
            $act = [string]$a.action
            $map = @{ 'next' = 0xB0; 'prev' = 0xB1; 'stop' = 0xB2; 'playpause' = 0xB3; 'mute' = 0xAD; 'voldown' = 0xAE; 'volup' = 0xAF }
            if (-not $map.ContainsKey($act)) { return @{ sent = $false; reason = 'unbekannt' } }
            if ($null -ne $a.allow -and @('next', 'prev', 'playpause') -contains $act) {
                $other = $false
                $s = $null
                try {
                    $s = Find-MusicSession $a
                    if ($null -ne $s) {
                        if ($act -eq 'next') { $op = $s.TrySkipNextAsync() }
                        elseif ($act -eq 'prev') { $op = $s.TrySkipPreviousAsync() }
                        else { $op = $s.TryTogglePlayPauseAsync() }
                        $ok = Await-Op $op ([bool])
                        return @{ sent = [bool]$ok; app = [string]$s.SourceAppUserModelId }
                    }
                    $other = ($null -ne $script:MediaMgr.GetCurrentSession())
                } catch { $other = $false }
                # Sitzung gefunden, aber Windows antwortete nicht: keine Taste hinterher (sonst
                # schaltete sie womöglich doppelt oder etwas anderes).
                if ($null -ne $s) { return @{ sent = $false; app = [string]$s.SourceAppUserModelId } }
                if ($other) { return @{ sent = $false; other = $true } }
            }
            if (-not ($a.user -is [bool] -and $a.user)) { return @{ sent = $false; reason = 'kein Ziel' } }
            if (-not (Test-KeyRate 'media')) { return @{ sent = $false; reason = 'zu oft' } }
            $code = [byte]$map[$act]
            [UzWin]::Key($code, $true); [UzWin]::Key($code, $false)
            return @{ sent = $true; global = $true }
        }
        'media-info' { return (Get-MediaInfo $a) }
        'suspend' {
            # Wie beim Beenden (Stop-GameProcess): nie Windows selbst, Steam, Discord, Uzai oder diesen Helfer
            # anhalten, auch wenn eine falsche Nummer ankäme – ein angehaltener Explorer friert Taskleiste und
            # Desktop ein, ein angehaltenes Uzai könnte sich nie wieder selbst fortsetzen.
            $sp = Get-Zahl $a.pid 5 2147483647
            if ($null -eq $sp -or $sp -eq $PID) { return @{ ok = $false; reason = 'geschützt' } }
            $spr = Get-Process -Id $sp -ErrorAction SilentlyContinue
            if (-not $spr) { return @{ ok = $false; reason = 'weg' } }
            if ($script:KillNever -contains $spr.ProcessName.ToLowerInvariant()) { return @{ ok = $false; reason = 'geschützt' } }
            # Merken, was dieser Helfer angehalten hat: Endet Uzai (auch durch einen Absturz), läuft es am Ende weiter.
            $ok = [UzWin]::Suspend([int]$a.pid, $true)
            if ($ok) { $script:Angehalten[[int]$a.pid] = $true }
            return @{ ok = $ok }
        }
        'resume' {
            $script:Angehalten.Remove([int]$a.pid)
            return @{ ok = [UzWin]::Suspend([int]$a.pid, $false) }
        }
        'kill' { return (Stop-GameProcess ([int]$a.pid)) }
        'prozessbaum' {
            # Läuft das Spiel noch (auch in einem Kind des gestarteten Prozesses)? Nur Zahlen, nur lesen.
            $root = Get-Zahl $a.pid 5 2147483647
            if ($null -eq $root) { return @{ pids = @(); grund = 'daten' } }
            return @{ pids = @(Get-SpielBaum $root) }
        }
        'baum-beenden' {
            # „Beenden“, nachdem das Spiel höflich gebeten wurde: den gestarteten Prozess und seine Kinder
            # beenden – nur diesen Baum, nichts Geschütztes, nie mit mehr Rechten.
            $root = Get-Zahl $a.pid 5 2147483647
            if ($null -eq $root -or $root -eq $PID) { return @{ ok = $false; grund = 'daten' } }
            $ids = @(Get-SpielBaum $root)
            $n = 0; $denied = $false
            foreach ($id in $ids) {
                $r = Stop-GameProcess ([int]$id)
                if ($r.ok) { $n++ } elseif ($r.denied) { $denied = $true }
            }
            $rest = @()
            for ($i = 0; $i -lt 10; $i++) {
                $rest = @($ids | Where-Object { Get-Process -Id ([int]$_) -ErrorAction SilentlyContinue })
                if ($rest.Count -eq 0) { break }
                Start-Sleep -Milliseconds 50
            }
            return @{ ok = ($ids.Count -eq 0 -or $n -gt 0); n = $n; denied = $denied; rest = $rest.Count; pids = $ids.Count }
        }
        'alive' { return @{ alive = ($null -ne (Get-Process -Id ([int]$a.pid) -ErrorAction SilentlyContinue)) } }
        'usage' {
            # Leistung (src/core/perf.gd): Arbeitsspeicher und Rechenzeit von Uzai und seinen Helfern.
            $procs = @()
            foreach ($p in @($a.pids)) {
                $pr = Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue
                if ($pr) { $procs += @{ pid = $pr.Id; mem = [long]$pr.WorkingSet64; cpu = [long]$pr.TotalProcessorTime.TotalMilliseconds } }
            }
            return @{ procs = $procs; cores = [Environment]::ProcessorCount }
        }
        'hide-windows' { return @{ n = [UzWin]::HideAll([int]$a.pid) } }
        'perf-live' {
            # Leistung im Guide (src/core/perf_live.gd), nur lesen: Prozesse des Spiels (Zahlen),
            # Abstand und Haltedauer in ms. Antwortet sofort mit der letzten Messung.
            Use-Perf
            $ids = @(@($a.pids) | ForEach-Object { Get-Num $_ 2147483647 } | Where-Object { $_ -gt 4 } | Select-Object -First 16)
            return @{ json = [UzPerf]::Snap(($ids -join ','), (Get-Num $a.every 5000), (Get-Num $a.hold 20000)) }
        }
        'power-plans' { Use-Perf; return @{ json = [UzPerf]::Plans() } }
        'pc-akku' { Use-Perf; try { return @{ json = [UzPerf]::Akku() } } catch { return @{ json = '{"ok":false}' } } }
        'geraet-info' { return (Get-GeraetInfo) }
        'power-plan-set' {
            # Nur ein Energieprofil, das Windows selbst aufzählt (GUID); Uzai stellt es nach dem Spiel zurück.
            $id = [string]$a.id
            if ($id -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return @{ json = '{"ok":false,"why":"id"}' } }
            Use-Perf
            return @{ json = [UzPerf]::SetPlan($id) }
        }
        # Windows-Einstellungen mit dem Controller (src/core/win_einst.gd), Prüfung in den Funktionen.
        'power-times' { Use-Perf; return @{ json = [UzPerf]::Times() } }
        'power-time-set' { return (Power-TimeSet $a) }
        'wlan-state' { return (Wlan-State $a) }
        'wlan-connect' { return (Wlan-Connect $a) }
        'wlan-poll' { return (Wlan-Poll) }
        'wlan-disconnect' { return (Wlan-Disconnect) }
        'radio-set' { return (Radio-Set $a) }
        'bt-paired' { return (Bt-Paired) }
        'bt-unpair' { return (Bt-Unpair $a) }
        'crash-watch' { $script:crashWatch = $a; return @{ ok = $true } }
        'show-hidden' { return @{ n = [UzWin]::ShowHidden() } }
        'start' {
            $exe = [string]$a.exe
            $wd = if ($a.dir) { [string]$a.dir } else { Split-Path -Parent $exe }
            $ext = [IO.Path]::GetExtension($exe).ToLowerInvariant()
            # Batchdateien und Konsolenprogramme (z. B. MAME) brächten über die Shell ein schwarzes
            # Konsolenfenster mit, das das ganze Spiel über offen steht. Sie starten ohne Fenster.
            $bat = ($ext -eq '.bat' -or $ext -eq '.cmd')
            # argv: feste Parameter als Liste (Epic-Spiele von Uzai, mit Einmal-Code). Jeder Eintrag
            # wird einzeln gequotet, wie CommandLineToArgvW ihn zurückliest – nur für eine .exe, nie
            # über cmd. Die Werte kommen nie in eine Meldung (der Code darf in kein Protokoll).
            $argLine = Join-StartArgv $a.argv $ext
            if ([string]$a.args) { $argLine = (@($argLine, [string]$a.args) | Where-Object { $_ -ne '' }) -join ' ' }
            if ($bat -or ($ext -eq '.exe' -and [UzStart]::Subsystem($exe) -eq 3)) {
                $inner = '"' + $exe + '"'
                if ($argLine) { $inner += ' ' + $argLine }
                if ($bat) {
                    $app = if ($env:ComSpec) { $env:ComSpec } else { Join-Path $env:SystemRoot 'System32\cmd.exe' }
                    $line = '"' + $app + '" /d /c "' + $inner + '"'
                } else { $app = $exe; $line = $inner }
                $id = [UzStart]::Hidden($app, $line, $wd)
                if ($id -gt 0) {
                    if ($a.watch) { [UzWin]::Watch($id) }
                    return @{ pid = $id; hidden = $true }
                }
                # Etwa Adminrechte nötig (740): wie bisher über die Shell, Windows fragt dann nach.
            }
            # Hilfsprogramme neben dem Spiel (Lossless Scaling): minimiert und ohne Fokus starten,
            # damit ihr Fenster nicht über das laufende Spiel springt.
            if ($a.quiet -and $ext -eq '.exe') {
                $line = '"' + $exe + '"'
                if ($argLine) { $line += ' ' + $argLine }
                $id = [UzStart]::MinNoActive($exe, $line, $wd)
                if ($id -gt 0) { return @{ pid = $id; quiet = $true } }
            }
            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName = $exe
            $psi.Arguments = $argLine
            $psi.WorkingDirectory = $wd
            $psi.UseShellExecute = $true
            $p = [Diagnostics.Process]::Start($psi)
            if ($a.watch) { [UzWin]::Watch($p.Id) }
            return @{ pid = $p.Id }
        }
        'fxsound' { return (Fx-Call $a) }
        'steam-still' {
            # Steams Mitteilungs-Fenster unsichtbar, solange Uzai läuft (siehe UzSteamStill). an: ein/aus;
            # ohne „an“ nur der Stand. Am Ende des Helfers (Uzai zu oder abgestürzt) wird abgeschaltet.
            $zurueck = 0
            if ($a.an -eq $true) { [UzSteamStill]::An() }
            elseif ($a.an -eq $false) { $zurueck = [UzSteamStill]::Aus() }
            return @{ aktiv = [UzSteamStill]::Aktiv(); gesehen = [UzSteamStill]::Gesehen; gesetzt = [UzSteamStill]::Gesetzt
                zuletzt = [UzSteamStill]::Zuletzt; aehnlich = [UzSteamStill]::Aehnliche(); zurueck = $zurueck }
        }
        'steam-running' {
            $v = 0
            try { $v = [int](Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).RunningAppID } catch {}
            return @{ appid = $v }
        }
        'steam-path' {
            $v = ''
            try { $v = [string](Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch {}
            return @{ path = $v }
        }
        # EA app / Origin: Spielordner aus der Registry, nur lesen. Spiele schreiben „Install Dir“
        # unter EA Games bzw. Electronic Arts, Origin unter Origin Games; dazu die Deinstallations-
        # Einträge von Electronic Arts. Ob ein Ordner wirklich ein EA-Spiel ist, prüft Uzai selbst
        # (__Installer\installerdata.xml). Außerdem: welche Start-Links (origin2, link2ea) angemeldet sind.
        'ea-games' {
            $out = @()
            foreach ($r in @('HKLM:\SOFTWARE\WOW6432Node\EA Games', 'HKLM:\SOFTWARE\EA Games', 'HKLM:\SOFTWARE\WOW6432Node\Electronic Arts',
                    'HKLM:\SOFTWARE\Electronic Arts', 'HKLM:\SOFTWARE\WOW6432Node\Origin Games', 'HKLM:\SOFTWARE\Origin Games')) {
                foreach ($k in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
                    $p = $null
                    try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
                    $dir = [string]$p.'Install Dir'
                    if (-not $dir) { $dir = [string]$p.InstallDir }
                    if (-not $dir) { continue }
                    $nm = [string]$p.DisplayName
                    if (-not $nm) { $nm = [string]$k.PSChildName }
                    $out += @{ dir = $dir; name = $nm; key = [string]$k.PSChildName }
                }
            }
            foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
                foreach ($k in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
                    $p = $null
                    try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
                    if ([string]$p.Publisher -notmatch 'Electronic Arts' -or -not [string]$p.InstallLocation) { continue }
                    $out += @{ dir = [string]$p.InstallLocation; name = [string]$p.DisplayName; key = [string]$k.PSChildName }
                }
            }
            $o2 = Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\origin2\shell\open\command'
            $l2 = Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\link2ea\shell\open\command'
            return @{ games = @($out); origin2 = [bool]$o2; link2ea = [bool]$l2 }
        }
        # Weitere Launcher (Punkt 6): feste Registry-Schlüssel, nur lesen, keine Eingaben. GOG
        # (GOG.com\Games, Galaxy-Ordner), Ubisoft Connect (Launcher\Installs), Deinstallations-
        # Einträge nur von Ubisoft, Blizzard/Battle.net und Amazon Games, und welche Start-Links
        # angemeldet sind. Ob ein Eintrag wirklich ein Spiel ist, prüft Uzai selbst.
        'store-games' {
            $cut = { param($v) $s = [string]$v; if ($s.Length -gt 1024) { $s = $s.Substring(0, 1024) }; $s }
            $gog = @()
            foreach ($r in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games')) {
                foreach ($k in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue | Select-Object -First 1000)) {
                    $p = $null
                    try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
                    $gog += @{ key = (& $cut $k.PSChildName); id = (& $cut $p.gameID); name = (& $cut $p.gameName); path = (& $cut $p.path)
                        exe = (& $cut $p.exe); depends = (& $cut $p.dependsOn) }
                }
            }
            $galaxy = ''
            foreach ($r in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\GalaxyClient\paths', 'HKLM:\SOFTWARE\GOG.com\GalaxyClient\paths')) {
                try { $galaxy = & $cut (Get-ItemProperty -LiteralPath $r -ErrorAction Stop).client } catch {}
                if ($galaxy) { break }
            }
            $ubi = @()
            foreach ($r in @('HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs', 'HKLM:\SOFTWARE\Ubisoft\Launcher\Installs')) {
                foreach ($k in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue | Select-Object -First 1000)) {
                    $p = $null
                    try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
                    $ubi += @{ id = (& $cut $k.PSChildName); dir = (& $cut $p.InstallDir) }
                }
            }
            $un = @()
            $bnet = ''
            foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
                foreach ($k in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue | Select-Object -First 3000)) {
                    $p = $null
                    try { $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop } catch { continue }
                    $key = [string]$k.PSChildName
                    $pub = [string]$p.Publisher
                    $cmd = [string]$p.UninstallString
                    if ($key -eq 'Battle.net' -and -not $bnet) { $bnet = & $cut $p.InstallLocation }
                    if ($key -like 'Uplay Install *' -or $pub -like 'Blizzard*' -or $cmd -like '*Amazon Game Remover.exe*') {
                        $un += @{ key = (& $cut $key); name = (& $cut $p.DisplayName); dir = (& $cut $p.InstallLocation); publisher = (& $cut $pub); cmd = (& $cut $cmd) }
                    }
                }
            }
            $protos = @{}
            foreach ($n in @('uplay', 'amazon-games', 'goggalaxy', 'battlenet', 'itchio', 'riotclient')) {
                $protos[$n] = [bool](Test-Path -LiteralPath ('Registry::HKEY_CLASSES_ROOT\' + $n + '\shell\open\command'))
            }
            return @{ gog = @($gog); galaxy = $galaxy; ubisoft = @($ubi); uninstall = @($un); bnet_dir = $bnet; protos = $protos }
        }
        # Xbox-App / PC Game Pass: App-Pakete dieses Windows-Kontos (ohne Adminrechte, nur lesen).
        # Ein Spiel ist nur ein Paket mit MicrosoftGame.config im Ordner; normale Apps bleiben draußen.
        # Keine Eingaben. Läuft als eigener Prozess (Helper.run_once), weil Get-AppxPackage dauern kann.
        'xbox-games' {
            $out = @()
            $pk = @()
            try { $pk = @(Get-AppxPackage -PackageTypeFilter Main -ErrorAction Stop) } catch {}
            $app = [bool]($pk | Where-Object { $_.Name -eq 'Microsoft.GamingApp' } | Select-Object -First 1)
            foreach ($p in $pk) {
                if ($out.Count -ge 400) { break }
                try {
                    if ($p.IsFramework -or [string]$p.SignatureKind -eq 'System') { continue }
                    $loc = [string]$p.InstallLocation
                    if (-not $loc -or -not (Test-Path -LiteralPath (Join-Path $loc 'MicrosoftGame.config') -PathType Leaf)) { continue }
                    $ids = @()
                    $title = ''
                    try {
                        $m = Get-AppxPackageManifest -Package $p.PackageFullName -ErrorAction Stop
                        foreach ($ap in @($m.Package.Applications.Application)) { if ($ap.Id -and $ids.Count -lt 16) { $ids += [string]$ap.Id } }
                        $title = [string]$m.Package.Properties.DisplayName
                    } catch {}
                    $out += @{ family = [string]$p.PackageFamilyName; name = [string]$p.Name; dir = $loc; apps = @($ids); title = $title }
                } catch {}
            }
            return @{ games = @($out); app = $app }
        }
        # Läuft der Steam-Client, und ist jemand angemeldet? (ActiveProcess bleibt nach einem Absturz
        # stehen, darum zählt nur ein lebender Prozess.)
        'steam-state' {
            $sp = 0; $user = 0
            try {
                $ap = Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess' -ErrorAction Stop
                $sp = [int64]$ap.pid; $user = [int64]$ap.ActiveUser
            } catch {}
            $alive = $false
            if ($sp -gt 0) { $alive = [bool](Get-Process -Id $sp -ErrorAction SilentlyContinue) }
            if (-not $alive) { $user = 0 }
            return @{ running = $alive; user = $user }
        }
        # Laufwerke mit Größe und freiem Platz, nur lesen (Einstellungen → System → Speicher). Nur
        # feste und Wechsel-Laufwerke, die bereit sind – Netz- und CD-Laufwerke können lange hängen.
        'drives' {
            $out = @()
            foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
                try {
                    if ($d.DriveType -ne [System.IO.DriveType]::Fixed -and $d.DriveType -ne [System.IO.DriveType]::Removable) { continue }
                    if (-not $d.IsReady) { continue }
                    $out += @{ name = [string]$d.Name; label = [string]$d.VolumeLabel; total = [int64]$d.TotalSize; free = [int64]$d.AvailableFreeSpace }
                } catch {}
            }
            return @{ drives = @($out) }
        }
        # Steam still starten: -silent (kein Bibliotheksfenster), minimiert und ohne Fokus.
        'steam-silent' {
            $exe = ''
            try { $exe = [string](Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamExe } catch {}
            if (-not $exe) {
                try { $exe = Join-Path ([string](Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath) 'steam.exe' } catch {}
            }
            $exe = $exe -replace '/', '\'
            if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return @{ started = $false } }
            $id = [UzStart]::MinNoActive($exe, ('"' + $exe + '" -silent'), (Split-Path -Parent $exe))
            return @{ started = ($id -gt 0); pid = $id }
        }
        'find-process' {
            # Doppelte/gemischte Trenner (C:\/Program Files…) zusammenfassen, sonst passt kein Prozesspfad.
            $dir = ([string]$a.dir) -replace '(?<!^)[\\/]+', '\'
            # Nur Pfade IN diesem Ordner: „C:\Spiel“ darf nicht „C:\Spiel 2“ treffen.
            $dir = $dir.TrimEnd('\') + '\'
            $ids = @()
            foreach ($p in Get-Process) {
                try { if ($p.Path -and $p.Path.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase)) { $ids += $p.Id } } catch {}
            }
            return @{ pids = $ids }
        }
        'lossless' {
            # Lossless Scaling: läuft es (nach Name und Ordner, siehe UzLs.Find), mit welchen
            # Rechten, welche Fenster sind sichtbar (keine = nur im Infobereich). Ob sein Bild über
            # dem Spiel liegt, entscheidet Uzai aus den Fenstern (Lossless.overlay_in).
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $names = @('LosslessScaling')
            if ($a.names) { $names = @($a.names | ForEach-Object { [string]$_ }) }
            $procs = @()
            $list = @()
            foreach ($row in [UzLs]::Find([string[]]$names, [string]$a.dir)) {
                $f = $row.Split('|', 5)
                $procs += @{ pid = [int]$f[0]; name = $f[1]; level = [int]$f[2]; by = $f[3]; path = $f[4] }
                $rows = @()
                try { $rows = @([UzWin]::Describe([int]$f[0])) } catch {}
                foreach ($w in $rows) {
                    $g = $w.Split('|', 8)
                    $list += @{ pid = [int]$f[0]; hwnd = [long]$g[0]; w = [int]$g[1]; h = [int]$g[2]; topmost = ($g[3] -eq '1'); full = ($g[4] -eq '1'); clickthrough = ($g[5] -eq '1'); class = $g[6]; title = $g[7] }
                }
            }
            $self = -1
            try { $self = [UzElev]::Level($PID) } catch {}
            return @{ procs = $procs; windows = $list; self_level = $self; ms = [int]$sw.ElapsedMilliseconds }
        }
        'lossless-start' {
            # Nie über die Shell: Verlangt Lossless Scaling Adminrechte (Fehler 740), käme sonst die
            # UAC-Abfrage, die sich mit dem Controller nicht bedienen lässt. Minimiert, ohne Fokus.
            $exe = [string]$a.exe
            if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return @{ started = $false; missing = $true } }
            $id = [UzStart]::MinNoActive($exe, ('"' + $exe + '"'), (Split-Path -Parent $exe))
            if ($id -gt 0) { return @{ started = $true; pid = $id; how = 'direkt' } }
            if ($id -eq -740) { return @{ started = $false; elevation = $true; code = 740 } }
            # Nur eine Steam-Nummer: Der Wert geht in eine Adresse, die Windows öffnet.
            if ([string]$a.steam -match '^[0-9]{1,12}\z') {
                try { Start-Process ('steam://rungameid/' + [string]$a.steam); return @{ started = $true; how = 'steam'; code = -$id } } catch {}
            }
            return @{ started = $false; code = -$id }
        }
        'presence' {
            Discord-Connect ([string]$a.client_id)
            $act = @{ details = [string]$a.details; state = [string]$a.state; timestamps = @{ start = [int64]$a.start } }
            if ($a.end) { $act.timestamps.end = [int64]$a.end }
            # 2 = „Hört …“ (Musik) statt „Spielt …“
            if ($a.type) { $act.type = [int]$a.type }
            # Was in der Mitgliederliste steht: 0 App-Name („Spielt Uzai“), 1 state, 2 details
            # („Spielt Ratchet & Clank“). Nur genau diese drei Zahlen.
            $disp = Get-Num $a.display 9
            if ($disp -ge 0 -and $disp -le 2) { $act.status_display_type = $disp }
            if ($a.image) { $act.assets = @{ large_image = [string]$a.image; large_text = [string]$a.large_text } }
            if (-not $a.large_text -and $act.assets) { $act.assets.large_text = [string]$a.details }
            # Kleines Uzai-Bild: nur das eine Bild aus Uzais eigener Discord-App (Erlaubnisliste).
            if ([string]$a.small -ceq 'uzai') {
                if (-not $act.assets) { $act.assets = @{} }
                $act.assets.small_image = 'uzai'; $act.assets.small_text = 'Uzai'
            }
            if ($a.buttons) { $act.buttons = @($a.buttons | ForEach-Object { @{ label = [string]$_.label; url = [string]$_.url } }) }
            Discord-Send 1 @{ cmd = 'SET_ACTIVITY'; args = @{ pid = $PID; activity = $act }; nonce = [guid]::NewGuid().ToString() }
            $null = Discord-Read
            return @{ ok = $true }
        }
        'presence-clear' {
            if ($script:discord -and $script:discord.IsConnected) {
                Discord-Send 1 @{ cmd = 'SET_ACTIVITY'; args = @{ pid = $PID }; nonce = [guid]::NewGuid().ToString() }
                $null = Discord-Read
            }
            return @{ ok = $true }
        }
        'autostart' {
            $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Uzai.lnk'
            if ($a.enable) {
                $sh = New-Object -ComObject WScript.Shell
                $s = $sh.CreateShortcut($lnk)
                $s.TargetPath = [string]$a.exe
                $s.WorkingDirectory = Split-Path -Parent ([string]$a.exe)
                $s.Save()
            } elseif (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
            return @{ ok = $true }
        }
        'power' {
            # shutdown.exe mit vollem Pfad (wie powercfg): Nur mit dem Namen nähme PowerShell das erste gleichnamige
            # Programm im Suchpfad.
            $sd = 'shutdown.exe'
            if ($env:SystemRoot) { $sd = Join-Path $env:SystemRoot 'System32\shutdown.exe' }
            switch ([string]$a.action) {
                'shutdown' { & $sd /s /t 0 }
                'restart' { & $sd /r /t 0 }
                'sleep' { [void][UzWin]::SetSuspendState($false, $false, $false) }
            }
            return @{ ok = $true }
        }
        'screenshot' { return (Take-Screenshot ([string]$a.title)) }
        'cap-start' {
            Use-Capture
            $r = [UzCap]::Start([string]$a.ffmpeg, [string[]]@($a.args), [string]$a.sys_pipe, [string]$a.mic_pipe, [string]$a.dir, [int]$a.skip_pid)
            return ($r | ConvertFrom-Json)
        }
        'cap-stop' {
            if ($script:CapReady) { [void][UzCap]::Stop() }
            return @{ ok = $true }
        }
        'cap-status' {
            Use-Capture
            return ([UzCap]::Status() | ConvertFrom-Json)
        }
        'clip-files' {
            # Datei in die Zwischenablage (wie im Explorer „Kopieren“, CF_HDROP): In Discord oder im
            # Steam-Chat fügt Strg+V sie als Anhang ein.
            $f = [string]$a.file
            if (-not (Test-Path -LiteralPath $f)) { return @{ ok = $false; reason = 'Datei fehlt' } }
            try { Set-Clipboard -LiteralPath $f }
            catch {
                Add-Type -AssemblyName System.Windows.Forms
                $c = New-Object System.Collections.Specialized.StringCollection
                [void]$c.Add($f)
                [System.Windows.Forms.Clipboard]::SetFileDropList($c)
            }
            return @{ ok = $true; foreground = [UzInput]::ForegroundProcess() }
        }
        'fg-proc' { return @{ name = [UzInput]::ForegroundProcess(); hwnd = [UzWin]::GetForegroundWindow().ToInt64() } }
        'audio-list' { Use-Audio; return @{ devices = @([UzAudio]::List() | ConvertFrom-Json) } }
        'audio-set' {
            # Nur eine Gerätekennung, wie audio-list sie liefert („{0.0.0.00000000}.{GUID}“).
            if ([string]$a.id -notmatch '^\{[0-9.]{1,40}\}\.\{[0-9a-fA-F-]{36}\}\z') { throw 'Ungültiges Audiogerät' }
            Use-Audio; [UzAudio]::SetDefault([string]$a.id); return @{ ok = $true }
        }
        'volume' { Use-Audio; return @{ json = [UzAudio]::Volume([int]$a.delta) } }
        'app-volume' {
            # Nur die Audiositzungen eines Programms (Spiel samt Kindprozessen, Video, Musik-App),
            # nie die Gesamtlautstärke. Zeitgrenze im C#-Teil (2 s).
            Use-Audio
            $hw = [int64]0
            if ($a.hwnd) { $hw = [int64]$a.hwnd }
            $js = [UzAudio]::AppVolume((@($a.pids) -join ','), [string]$a.dir, $hw, (@($a.keys) -join ','), (@($a.skip) -join ','), [int]$a.delta)
            return @{ json = $js }
        }
        # Lautstärkemixer und Mikrofon (src/core/mixer.gd). Nur Zahlen: Prozessnummern, Pegel 0..100,
        # Stumm 0/1 (fehlt oder ungültig: -1 = lassen); der Spielordner wird nur verglichen.
        'mixer' {
            Use-Audio
            $hw = [int64]0
            if ($a.hwnd) { $hw = [int64]$a.hwnd }
            return @{ json = [UzAudio]::Mixer((@($a.pids) -join ','), [string]$a.dir, $hw, (@($a.skip) -join ',')) }
        }
        'mixer-set' { Use-Audio; return @{ json = [UzAudio]::MixerSet((@($a.pids) -join ','), (Get-Num $a.level 100), (Get-Num $a.mute 1)) } }
        'master-set' { Use-Audio; return @{ json = [UzAudio]::MasterSet((Get-Num $a.level 100), (Get-Num $a.mute 1)) } }
        'mic' { Use-Audio; return @{ json = [UzAudio]::Mic((Get-Num $a.mute 1)) } }
        # Ton aus dem Fernseher des Zimmers (src/room/raumton.gd): nur die Kanal-Lautstärken der
        # Audiositzungen des Spiels samt Kindprozessen, links/rechts als Zahlen 0..1000; „aus“ stellt
        # zurück, was vorher war; „werte“ (1..8 Zahlen 0..1000) setzt nach einem Absturz gemerkte alte
        # Werte. Nie die Gesamtlautstärke, nie andere Programme.
        'raum-ton' {
            Use-Audio
            if ($a.aus) { return @{ json = [UzAudio]::RaumTonAus() } }
            $hw = [int64]0
            if ($a.hwnd) { $hw = [int64]$a.hwnd }
            if ($null -ne $a.werte) {
                $w = @(@($a.werte) | ForEach-Object { Get-Num $_ 1000 })
                if ($w.Count -lt 1 -or $w.Count -gt 8 -or ($w -contains -1)) { return @{ json = '{"found":false,"error":"args"}' } }
                return @{ json = [UzAudio]::RaumTonWerte((@($a.pids) -join ','), [string]$a.dir, $hw, (@($a.skip) -join ','), [int[]]$w) }
            }
            $l = Get-Num $a.l 1000
            $r = Get-Num $a.r 1000
            if ($l -lt 0 -or $r -lt 0) { return @{ json = '{"found":false,"error":"args"}' } }
            return @{ json = [UzAudio]::RaumTon((@($a.pids) -join ','), [string]$a.dir, $hw, (@($a.skip) -join ','), $l, $r) }
        }
        'display-info' { return (Get-DisplayInfo ([long]$a.hwnd)) }
        # Spiel-Profile: nur feste Befehle, Gerät nur „\\.\DISPLAYn“, sonst nur Zahlen.
        'display-modes' { Use-Display; return @{ json = [UzDisplay]::Modes([long]$a.hwnd) } }
        'display-set' {
            # keep = 1 („Behalten“ in Bild & Ton): denselben Modus in Windows merken; sonst vorübergehend.
            $dev = [string]$a.device
            $w = Get-Num $a.w 16384; $h = Get-Num $a.h 16384; $hz = Get-Num $a.hz 1000
            if (-not (Test-DisplayDevice $dev) -or $w -lt 640 -or $h -lt 480 -or $hz -lt 24) { return @{ json = '{"ok":false,"error":"args"}' } }
            Use-Display; return @{ json = [UzDisplay]::SetMode($dev, $w, $h, $hz, ((Get-Num $a.keep 1) -eq 1)) }
        }
        'display-reset' {
            $dev = [string]$a.device
            if (-not (Test-DisplayDevice $dev)) { return @{ json = '{"ok":false,"error":"args"}' } }
            Use-Display; return @{ json = [UzDisplay]::Reset($dev) }
        }
        'display-hdr' {
            $dev = [string]$a.device
            $on = Get-Num $a.on 1
            if (-not (Test-DisplayDevice $dev) -or $on -lt 0) { return @{ json = '{"ok":false,"error":"args"}' } }
            Use-Display; return @{ json = [UzDisplay]::SetHdr($dev, $on) }
        }
        'pad-count' { return @{ n = [UzPadInfo]::Count() } }
        # Controller-Status (src/core/pads.gd): Stand als JSON, kurzer Impuls, Ausschalten.
        'pad-status' { Use-Pads; return @{ json = [UzPads]::Status([bool]$a.rescan); wgi = @(Get-WgiBatteries) } }
        'pad-pulse' { Use-Pads; return @{ n = [UzPads]::Pulse([int]$a.pad, [int]$a.low, [int]$a.high, [int]$a.ms) } }
        'pad-off' { Use-Pads; return @{ code = [UzPads]::PowerOff([int]$a.pad) } }
        'discs' { return @{ json = [UzDisc]::State() } }
        'rp-check' { return (RemotePlay-Check $a) }
        'mpv' { return (Mpv-Call ([string]$a.pipe) @($a.cmds)) }
        'steam-invite' { return (Steam-Invite $a) }
        'remoteplay-invite' { return (RemotePlay-Invite $a) }
        'remoteplay-build' { return (RemotePlay-Build $a) }
        'zimmer-netz-probe' { return (ZimmerNetz-Probe) }
        'browser-bauen' { return (Browser-Bauen) }
        'kern-auslegen' { return (Kern-Auslegen $a) }
        'kern-bauen' { return (Kern-Bauen) }
        'kern-ressource' { return (Kern-Ressource $a) }
        'shortcut' {
            $name = ([string]$a.name) -replace '[\\/:*?"<>|]', ''
            if ([string]$a.where -eq 'startmenu') {
                $dir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Uzai'
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            } else { $dir = [Environment]::GetFolderPath('Desktop') }
            $path = Join-Path $dir ($name + '.lnk')
            $sh = New-Object -ComObject WScript.Shell
            $l = $sh.CreateShortcut($path)
            $l.TargetPath = [string]$a.target
            $l.Arguments = [string]$a.args
            $l.WorkingDirectory = Split-Path -Parent ([string]$a.target)
            # Symbol: nur eine vorhandene .exe/.ico mit lokalem, vollem Pfad (kein Netzwerkpfad, keine
            # Steuerzeichen); sonst behält die Verknüpfung das Symbol des Ziels (Uzai).
            $ic = if ($a.icon) { [string]$a.icon } else { '' }
            $ext = if ($ic) { [IO.Path]::GetExtension($ic).ToLowerInvariant() } else { '' }
            if ($ic.Length -gt 0 -and $ic.Length -lt 1024 -and $ic -notmatch '[\x00-\x1f]' -and [IO.Path]::IsPathRooted($ic) -and -not $ic.StartsWith('\\') `
                    -and ($ext -eq '.exe' -or $ext -eq '.ico') -and (Test-Path -LiteralPath $ic -PathType Leaf)) {
                $l.IconLocation = $ic + ',0'
            }
            $l.Save()
            return @{ path = $path }
        }
        'lnk' {
            $sh = New-Object -ComObject WScript.Shell
            $l = $sh.CreateShortcut([string]$a.path)
            return @{ target = [string]$l.TargetPath; args = [string]$l.Arguments; dir = [string]$l.WorkingDirectory }
        }
        'pad-watch' { [UzPad]::Start([bool]$a.combo); return @{ ok = $true } }
        # Ruhemodus (rest.gd): Wecken mit jeder Taste an/aus, Haltezeit der Guide-Taste (0 = aus).
        'pad-wake' {
            # Der Wächter läuft schon (pad-watch beim Start des Helfers); Start() hier setzte Combo neu.
            if ($null -ne $a.hold_ms) { [UzPad]::HoldMs = [int]$a.hold_ms }
            if ($null -ne $a.on) { [UzPad]::Wake = [bool]$a.on }
            return @{ ok = $true; on = [UzPad]::Wake; hold_ms = [UzPad]::HoldMs }
        }
        'monitor' {
            Use-Screen
            if ($a.on) { return @{ ok = [UzScreen]::On() } }
            return @{ ok = [UzScreen]::Off() }
        }
        'app-mute' {
            Use-Audio
            $hw = [int64]0
            if ($a.hwnd) { $hw = [int64]$a.hwnd }
            $js = [UzAudio]::AppMute((@($a.pids) -join ','), [string]$a.dir, $hw, (@($a.skip) -join ','), [bool]$a.on)
            # Merken, was Uzai stumm geschaltet hat (Ruhemodus): Endet Uzai dabei, kommt der Ton am Ende zurück.
            # Windows merkt sich „stumm“ je Programm – das Spiel bliebe sonst auch nach einem Neustart ohne Ton.
            if ([bool]$a.on) { $script:Stumm = @{ pids = (@($a.pids) -join ','); dir = [string]$a.dir; hwnd = $hw; skip = (@($a.skip) -join ',') } }
            else { $script:Stumm = $null }
            return @{ json = $js }
        }
        'thumb' { return (Take-Thumb ([string]$a.file) ([int]$a.w)) }
        'mouse' {
            [UzPad]::Start([bool]$a.combo)
            [UzPad]::Mouse = [bool]$a.on
            return @{ ok = $true; on = [UzPad]::Mouse }
        }
        'dsdk-start' { Use-Dsdk; return ([UzDsdk]::Start([string]$a.dll, [uint64][string]$a.app_id) | ConvertFrom-Json) }
        'dsdk-token' { Use-Dsdk; return ([UzDsdk]::Token([string]$a.token) | ConvertFrom-Json) }
        'dsdk-me' { Use-Dsdk; return ([UzDsdk]::Me() | ConvertFrom-Json) }
        'dsdk-friends' { Use-Dsdk; return ([UzDsdk]::Friends() | ConvertFrom-Json) }
        'dsdk-accept' { Use-Dsdk; return ([UzDsdk]::AnswerRequest([uint64][string]$a.id, $true) | ConvertFrom-Json) }
        'dsdk-reject' { Use-Dsdk; return ([UzDsdk]::AnswerRequest([uint64][string]$a.id, $false) | ConvertFrom-Json) }
        'dsdk-send' { Use-Dsdk; return ([UzDsdk]::Send([uint64][string]$a.to, [string]$a.text) | ConvertFrom-Json) }
        'dsdk-history' { Use-Dsdk; return ([UzDsdk]::History([uint64][string]$a.with, [int]$a.limit) | ConvertFrom-Json) }
        'dsdk-showing' { Use-Dsdk; return ([UzDsdk]::ShowingChat([bool]$a.on) | ConvertFrom-Json) }
        'dsdk-status' { Use-Dsdk; return ([UzDsdk]::SetStatus([int]$a.status) | ConvertFrom-Json) }
        'dsdk-authorize' { Use-Dsdk; return ([UzDsdk]::Authorize([uint64][string]$a.app_id, [string]$a.scopes) | ConvertFrom-Json) }
        'dsdk-stop' { if ($script:DsdkReady) { [UzDsdk]::Stop() }; return @{ ok = $true } }
        'rpc-open' {
            Use-Rpc
            $err = [UzRpc]::Open([string]$a.client_id)
            if ($err -ne '') { return @{ ok = $false; reason = $err } }
            return @{ ok = $true }
        }
        'rpc-send' {
            Use-Rpc
            return @{ ok = [UzRpc]::Send(1, [string]$a.json) }
        }
        'rpc-close' {
            if ($script:RpcReady) { [UzRpc]::Close() }
            return @{ ok = $true }
        }
        'shaderglass' {
            # Auf das Spielfenster warten, ShaderGlass-Profil mit dem Fenstertitel schreiben, starten.
            $procId = [int]$a.pid
            $deadline = (Get-Date).AddSeconds([double]$a.timeout)
            $ignore = [string]$a.ignore
            $title = ''
            while ((Get-Date) -lt $deadline) {
                if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { return @{ ok = $false; reason = 'beendet' } }
                foreach ($h in [UzWin]::WindowsOf($procId)) {
                    $t = [UzWin]::Title($h)
                    if ($t -and ($ignore -eq '' -or $t -notmatch $ignore)) { $title = $t; break }
                }
                if ($title) { break }
                Start-Sleep -Milliseconds 300
            }
            if (-not $title) { return @{ ok = $false; reason = 'kein Fenster' } }
            Start-Sleep -Milliseconds 1500
            $lines = @(([string]$a.profile) -split "`n" | Where-Object { $_ -notmatch '^(CaptureWindow|CaptureDesktop|CaptureDevice|CaptureFormat) ' -and $_.Trim() -ne '' })
            $lines += 'CaptureWindow "' + $title.Replace('\', '\\').Replace('"', '\"') + '"'
            $tmp = Join-Path $env:TEMP 'uzai-shaderglass.sgp'
            [IO.File]::WriteAllLines($tmp, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
            # Im eigenen Ordner starten (wie ein Doppelklick): Der Arbeitsordner des Helfers hängt davon
            # ab, wie Uzai gestartet wurde (Autostart, Wächter, Neustart) – ShaderGlass soll das nicht merken.
            $sgDir = Split-Path -Parent ([string]$a.exe)
            $sg = Start-Process -FilePath ([string]$a.exe) -ArgumentList @('-f', "`"$tmp`"") -WorkingDirectory $sgDir -PassThru
            Start-Sleep -Milliseconds 1500
            $h = Find-Window $procId
            if ($h -ne [IntPtr]::Zero) { [void][UzWin]::Focus($h) }
            return @{ ok = $true; sg_pid = $sg.Id; title = $title }
        }
        'spotify-fenster' {
            # Was das Fenster der Spotify-App zeigt (Bibliothek, „Zuletzt gespielt“, Suchergebnisse),
            # über die Bedienhilfe von Windows – Namen und Spotify-Adressen, nur dieses Fenster
            # (Prozessname und Pfad geprüft), mit Grenzen für Knoten, Tiefe und Zeit. Weg oder fremd:
            # leer mit Grund. voll: die Bibliothek ganz durchblättern. Liegt Uzai vorn (uzai_pid), wird
            # das Fenster dafür kurz unsichtbar bereitgelegt (UzSpotFenster) und danach zurückgelegt; ist
            # Spotify selbst vorn (jemand benutzt es), wird nicht geblättert.
            $script:SpotWin = $null
            $f = Find-SpotifyWindow
            if (-not $f.ok) { return @{ ok = $false; why = [string]$f.why; items = @() } }
            Use-SpotUi
            $h = [IntPtr][long]$f.hwnd
            $rest = [UzSpot.UzSpotFenster]::Zurueck($h)
            $voll = ($a.voll -eq $true)
            $upid = Get-Zahl $a.uzai_pid 1 2147483647
            $fg = [UzWin]::GetForegroundWindow()
            $fgPid = [UzWin]::PidOf($fg)
            $legen = $false
            $lage = if ($f.min) { 'minimiert' } else { 'offen' }
            if ($voll -and $fgPid -eq [int]$f.pid) { $voll = $false; $lage = 'Spotify vorn' }
            elseif ($voll -and $null -ne $upid -and $fgPid -eq $upid) { $legen = $true }
            $woke = 0
            $budget = if ($voll) { 12000 } else { 4000 }
            $bm = Get-Zahl $a.budget_ms 500 ([UzSpotRegeln]::BudgetHard)
            if ($null -ne $bm) { $budget = $bm }
            $pause = 250
            $pm = Get-Zahl $a.pause_ms 20 1000
            if ($null -ne $pm) { $pause = $pm }
            $t0 = Get-Date
            $res = $null
            try {
                if ($legen) {
                    $why = [UzSpot.UzSpotFenster]::Bereit($h, $fg)
                    if ($why -eq '') { $lage = 'Lesestreifen'; Start-Sleep -Milliseconds 700 } else { $lage = 'nicht bereit: ' + $why }
                }
                try { $woke = [UzInput]::WakeAccessibility($h) } catch {}
                if (-not $script:SpotWoke) { $script:SpotWoke = $true; Start-Sleep -Milliseconds 500 }
                $nodes = if ($voll) { 20000 } else { 6000 }
                $res = ([UzSpot.UzSpotUi]::Read([long]$f.hwnd, $budget, $nodes, 48, [bool]$voll, $pause)) | ConvertFrom-Json
            } finally {
                if ($legen) { [void][UzSpot.UzSpotFenster]::Zurueck($h) }
            }
            $res | Add-Member -NotePropertyName ok -NotePropertyValue $true -Force
            $res | Add-Member -NotePropertyName woke -NotePropertyValue $woke -Force
            $res | Add-Member -NotePropertyName lage -NotePropertyValue $lage -Force
            $res | Add-Member -NotePropertyName aufgeraeumt -NotePropertyValue ($rest -ne '') -Force
            $res | Add-Member -NotePropertyName ms -NotePropertyValue ([int]((Get-Date) - $t0).TotalMilliseconds) -Force
            $script:SpotWin = @{ hwnd = [long]$f.hwnd; pid = [int]$f.pid }
            return $res
        }
        'spotify-fenster-spielen' {
            # Einen Abspiel-Knopf aus der letzten Liste „aufrufen“ (Invoke-Muster, wie ein Bildschirmleser):
            # nur im selben, noch geprüften Fenster, nur wenn der Knopf denselben Namen trägt. Kein
            # Fokuswechsel von Uzai aus. Springt Spotify doch nach vorn („vorn“), wird es sofort minimiert:
            # Windows gibt den Vordergrund dann von selbst an das Fenster dahinter (Uzai) zurück – ohne
            # Alt-Notlösung, ohne Flackern („zurueck“).
            $w = $script:SpotWin
            if ($null -eq $w -or -not $script:SpotUiReady) { return @{ result = 'nicht erlaubt' } }
            $i = Get-Zahl $a.i 0 ([UzSpotRegeln]::MaxItems - 1)
            if ($null -eq $i) { return @{ result = 'weg' } }
            $name = [string]$a.name
            if ($name.Length -lt 1 -or $name.Length -gt [UzSpotRegeln]::NameMax) { return @{ result = 'weg' } }
            $chk = Test-AppWindow ([long]$w.hwnd) @('spotify')
            if (-not $chk.ok -or [int]$chk.pid -ne [int]$w.pid) { $script:SpotWin = $null; return @{ result = 'nicht erlaubt' } }
            $fg0 = [UzWin]::GetForegroundWindow()
            $r = [UzSpot.UzSpotUi]::Invoke($i, $name, [int]$w.pid, 3000)
            Start-Sleep -Milliseconds 300
            $fg1 = [UzWin]::GetForegroundWindow()
            $vorn = ($fg1 -ne $fg0 -and [UzWin]::PidOf($fg1) -eq [int]$w.pid)
            $zurueck = $false
            if ($vorn) {
                [void][UzWin]::ShowWindow($fg1, 6)
                Start-Sleep -Milliseconds 150
                $zurueck = ([UzWin]::GetForegroundWindow() -eq $fg0)
            }
            return @{ result = $r; vorn = $vorn; zurueck = $zurueck }
        }
        'spotify-start' {
            # Spotify im Hintergrund starten (minimiert, mit hide unsichtbar), damit Uzai die
            # Wiedergabe über die Web-API auf diesen PC holen kann – ohne dass Spotify nach vorn
            # springt. Läuft Spotify schon, bleibt sein Fenster, wie es ist.
            $wait = 10.0
            if ($a.wait) { $wait = [double]$a.wait }
            $running = @(Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue)
            if ($running.Count -gt 0) { return @{ ok = $true; how = 'laeuft'; windows = 0 } }
            $how = ''
            $exe = ''
            if ($env:APPDATA) { $exe = Join-Path $env:APPDATA 'Spotify\Spotify.exe' }
            if ($exe -ne '' -and (Test-Path -LiteralPath $exe)) {
                $sp = [UzStart]::MinNoActive($exe, ('"' + $exe + '" --minimized'), (Split-Path -Parent $exe))
                if ($sp -le 0) { Start-Process -FilePath $exe -ArgumentList '--minimized' -WindowStyle Minimized }
                $how = 'exe'
            } else {
                # Store-Version: über die App-Kennung starten (ohne Parameter, Fenster folgt unten).
                $pkg = $null
                try { $pkg = Get-AppxPackage -Name 'SpotifyAB.SpotifyMusic' -ErrorAction Stop | Select-Object -First 1 } catch { $pkg = $null }
                if ($null -eq $pkg) { return @{ ok = $false; reason = 'nicht installiert' } }
                Start-Process ('shell:AppsFolder\' + $pkg.PackageFamilyName + '!Spotify')
                $how = 'store'
            }
            # Fenster minimieren (7: ohne Fokus) bzw. verstecken (0), sobald es auftaucht. Kurz
            # weiter beobachten: Spotify zeigt manchmal erst ein zweites Fenster.
            $deadline = (Get-Date).AddSeconds($wait)
            $n = 0
            $seen = @{}
            while ((Get-Date) -lt $deadline) {
                foreach ($p in @(Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue)) {
                    foreach ($h in [UzWin]::WindowsOf($p.Id)) {
                        $k = $h.ToInt64()
                        if ($seen.ContainsKey($k)) { continue }
                        $seen[$k] = $true
                        # Hat sich Spotify nach vorn gedrängt: minimieren (6) – Windows gibt den Vordergrund
                        # dann von selbst an das Fenster dahinter zurück; sonst nur ohne Aktivierung (7).
                        $vorn = ([UzWin]::GetForegroundWindow() -eq $h)
                        if ($a.hide) { [void][UzWin]::ShowWindow($h, 0) } elseif ($vorn) { [void][UzWin]::ShowWindow($h, 6) } else { [void][UzWin]::ShowWindow($h, 7) }
                        # Nur wenn danach noch ein Spotify-Fenster vorn liegt, Uzai zurückholen (die
                        # Alt-Notlösung flackert – nie, wenn Uzai ohnehin vorn ist).
                        if ($a.uzai_pid) {
                            $u = Find-Target @{ pid = [int]$a.uzai_pid }
                            $fgp = [UzWin]::PidOf([UzWin]::GetForegroundWindow())
                            $spot = @(Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })
                            if ($u -ne [IntPtr]::Zero -and $spot -contains $fgp) { [void][UzWin]::Focus($u) }
                        }
                        $n++
                        $later = (Get-Date).AddSeconds(2.5)
                        if ($later -lt $deadline) { $deadline = $later }
                    }
                }
                Start-Sleep -Milliseconds 250
            }
            return @{ ok = $true; how = $how; windows = $n }
        }
        default { throw "Unbekannter Befehl: $($req.cmd)" }
    }
}

function Write-Reply($id, $ok, $result, $err) {
    $out = @{ id = $id; ok = $ok; result = $result; error = $err } | ConvertTo-Json -Depth 8 -Compress
    [Console]::Out.WriteLine($out)
    [Console]::Out.Flush()
}

# Zimmer-Netz-Sitzung: Standardeingabe und -ausgabe gehören ab hier dem Kindprozess im
# AppContainer – nichts in diesem Zweig schreibt darauf (Fehler nur auf den Fehlerkanal).
if ($ZimmerNetz -ne '') {
    $code = 6
    try {
        if ([Array]::IndexOf([string[]]@('gastgeber', 'gast', 'gastgeber-echt', 'gast-echt'), $ZimmerNetz) -lt 0) { exit 2 }
        if ([UzElev]::IsElevated($PID)) { exit 4 }
        $exe = ZimmerNetz-Bauen
        if ($exe -ne '') { $code = [UzZimmerNetz]::Sitzung($exe, $ZimmerNetz) }
    } catch { [Console]::Error.WriteLine('zimmer-netz: ' + $_.Exception.GetType().Name) }
    exit $code
}

if ($Once -ne '') {
    $req = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Once)) | ConvertFrom-Json
    try { Write-Reply $req.id $true (Invoke-Command-Json $req) $null }
    catch { Write-Reply $req.id $false $null $_.Exception.Message }
    exit 0
}

# Uzai ist weg (Leitung zu). Nach einem Absturz – laeuft.json liegt noch da, mit Uzais Kennung –
# Uzai neu starten, dort weiter, wo es war (src/core/crash_guard.gd). Nur nach einem gelungenen
# Start und höchstens zweimal hintereinander (sonst stürzte es im Kreis). Lief ein Spiel, holt der
# Helfer Uzai nicht nach vorn: Er wird zum Wächter für die Guide-Taste (-Watch). Beim Herunterfahren
# („aus“) nichts.
$script:crashWatch = $null
# Prozesse, die dieser Helfer für Uzai angehalten hat (Guide offen, Ruhemodus): Prozess-ID -> $true.
$script:Angehalten = @{}
# Das Programm, das dieser Helfer für Uzai stumm geschaltet hat (Ruhemodus), mit den Angaben von „app-mute“.
$script:Stumm = $null
# Wo FxSound.exe liegt (Fx-Exe sucht einmal und merkt es sich).
$script:FxExe = ''

# Wie CommandLineToArgvW es zurückliest (wie UzWake.Quote im Wächter oben).
function Quote-Arg([string]$a) {
    if ($a.Length -gt 0 -and $a.IndexOfAny([char[]]@(' ', "`t", '"')) -lt 0) { return $a }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $a.ToCharArray()) {
        if ($ch -eq [char]92) { $bs++; continue }
        if ($ch -eq [char]34) { [void]$sb.Append([char]92, [int]($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
        if ($bs -gt 0) { [void]$sb.Append([char]92, [int]$bs) }
        $bs = 0
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append([char]92, [int]($bs * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Eigenständig starten: ohne die Leitungen dieses Helfers (die gehörten dem abgestürzten Uzai).
# Unter Windows über die Shell; unter Linux (nur Tests mit PowerShell 7) über sh mit /dev/null.
function Start-Quoted([string]$exe, [string]$dir, $list, [bool]$hidden = $false) {
    $si = New-Object Diagnostics.ProcessStartInfo
    $argv = @($list | Where-Object { [string]$_ -ne '' } | ForEach-Object { [string]$_ })
    if ([Environment]::OSVersion.Platform -eq 'Win32NT') {
        $si.FileName = $exe
        $si.UseShellExecute = $true
        if ($hidden) { $si.WindowStyle = 'Hidden' }
    } else {
        $si.FileName = '/bin/sh'
        $argv = @('-c', 'exec "$0" "$@" </dev/null >/dev/null 2>&1', $exe) + $argv
        $si.UseShellExecute = $false
    }
    $si.Arguments = (@($argv | ForEach-Object { Quote-Arg $_ }) -join ' ')
    if ($dir -ne '') { $si.WorkingDirectory = $dir }
    [void][Diagnostics.Process]::Start($si)
}

function Crash-Restart($c) {
    try { $p = Get-Process -Id ([int]$c.pid) -ErrorAction Stop; [void]$p.WaitForExit(5000) } catch {}
    if (Get-Process -Id ([int]$c.pid) -ErrorAction SilentlyContinue) { return }
    if (-not (Test-Path -LiteralPath ([string]$c.marker))) { return }
    try { $m = Get-Content -LiteralPath ([string]$c.marker) -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return }
    if ([int]$m.pid -ne [int]$c.pid -or -not $m.stable -or [int]$m.auto -ge 2) { return }
    $where = [string]$m.where
    if ($where -eq 'aus') { return }
    if ($where -eq 'spiel') {
        if ([string]$c.watch -ne '') {
            Start-Quoted ([string]$c.ps) '' @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ([string]$c.script), '-Watch', ([string]$c.watch)) $true
        }
        return
    }
    Start-Quoted ([string]$c.exe) ([string]$c.dir) @($c.args)
}

Write-Reply 0 $true @{ ready = $true; pid = $PID } $null
while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    if ($line.Trim() -eq '') { continue }
    $req = $null
    try {
        $req = $line | ConvertFrom-Json
        Write-Reply $req.id $true (Invoke-Command-Json $req) $null
    } catch {
        $rid = 0
        if ($req) { $rid = $req.id }
        Write-Reply $rid $false $null $_.Exception.Message
    }
}
# Uzai ist zu (oder abgestürzt): Was Uzai angehalten hat, läuft weiter. Sonst bliebe das Spiel für immer eingefroren,
# und niemand könnte es fortsetzen (ein schon fortgesetzter Prozess läuft dabei einfach weiter).
foreach ($p in @($script:Angehalten.Keys)) { try { [void][UzWin]::Suspend([int]$p, $false) } catch {} }
if ($script:Stumm) { try { [void][UzAudio]::AppMute($script:Stumm.pids, $script:Stumm.dir, [int64]$script:Stumm.hwnd, $script:Stumm.skip, $false) } catch {} }
# Kam der Spielton gerade aus dem Fernseher, die alten Werte zurück.
if ($script:AudioReady) { try { [void][UzAudio]::RaumTonAus() } catch {} }
# Steams Mitteilungs-Fenster zeigen wieder selbst (UzSteamStill).
try { [void][UzSteamStill]::Aus() } catch {}
if ($script:crashWatch) { try { Crash-Restart $script:crashWatch } catch {} }
