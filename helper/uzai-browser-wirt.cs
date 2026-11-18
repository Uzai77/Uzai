// Uzai-Browser: der Wirt für Microsofts WebView2 – seit 0.17 nur noch der ausdrücklich gewählte Notnagel
// (Einstellung browser.kern = webview2, „Microsoft-Kern“); der eigene Kern ist Chromium über CEF
// (helper/uzai-browser-kern.cs, docs/BROWSER_PLAN.md). Gemeinsame Teile (JSON, Regeln, Schema, Leitung, Fenster,
// Blocker) stehen in helper/uzai-browser-gemeinsam.cs; der Helfer übersetzt beide Dateien zusammen.
//
// Ein eigenes kleines Programm (Add-Type, C# 5, .NET Framework 4; tests/browser_cs.ps1 prüft es unter Linux). Es hält
// WebView2 – Chromium, von Windows/Edge aktuell gehalten, mit der Chromium-Sandbox – in einem randlosen Fenster, das
// nie aktiv wird und keinen Taskleisten-Eintrag hat. Uzai liegt durchsichtig darüber, liest den Controller und
// zeichnet alles, was man sieht; der Wirt zeigt nur die Seite.
//
// Sicherheit (alles fest im Code, keine Einstellung von außen): nur http/https; dieser PC nie, das Heimnetz nur, wenn du
// die Adresse selbst eingibst (auch für Unteranfragen der Seite); andere Protokolle (steam:, ms-settings:, file: …)
// gesperrt; Pop-ups nur nach einem Druck, dann als Tab; Downloads nur in Dateiarten aus einer Erlaubnisliste, nie
// geöffnet; Kamera, Mikrofon, Standort nur nach Rückfrage in Uzai, alles andere abgelehnt; Bildschirm teilen,
// Anmeldedialoge, Zertifikatsfehler gesperrt; DevTools, Kontextmenüs, Host-Objekte, Web-Nachrichten, Erweiterungen,
// Passwort- und Formular-Speicher aus; Tracking-Schutz „Streng“, SmartScreen an; Anmeldung mit dem Windows-Konto aus;
// Absturzberichte nicht an Microsoft; WEBVIEW2_*-Umgebungsvariablen werden geleert; nie mit Adminrechten. Eigenes
// Profil je Uzai-Profil unter %LOCALAPPDATA%\Uzai\browser\profil, privater Tab ohne Spuren.
//
// Vor dem ersten Zugriff auf WebView2 prüft der Wirt die beiden DLLs neben sich: SHA-256 wie unten und gültige
// Signatur von Microsoft Corporation (WinVerifyTrust). Der Lader kommt nur aus diesem Ordner.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;

// --- Prüfung der WebView2-Dateien vor dem ersten Zugriff ------------------------------------------

public static class UzbPruefung {
    public const string CORE = "Microsoft.Web.WebView2.Core.dll";
    public const string LOADER = "WebView2Loader.dll";
    // NuGet Microsoft.Web.WebView2 1.0.4258.31 (assets/browser/webview2/LIZENZ.txt).
    public const string CORE_SHA256 = "d60e6e94245078cb56e44ebd5f360dc04bf18e460136be93bfc4cfca43b98505";
    public const string LOADER_SHA256 = "3426dcc55fdfb8b5e7ac623cf33b4ccf283fbf68a0c5a65bddfdb4d749a8abee";
    public const string SKRIPT = "uzai-browser-karte.js";

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WINTRUST_FILE_INFO { public uint cbStruct; public string pcwszFilePath; public IntPtr hFile; public IntPtr pgKnownSubject; }

    [StructLayout(LayoutKind.Sequential)]
    struct WINTRUST_DATA {
        public uint cbStruct; public IntPtr pPolicyCallbackData; public IntPtr pSIPClientData; public uint dwUIChoice; public uint fdwRevocationChecks;
        public uint dwUnionChoice; public IntPtr pFile; public uint dwStateAction; public IntPtr hWVTStateData; public IntPtr pwszURLReference;
        public uint dwProvFlags; public uint dwUIContext; public IntPtr pSignatureSettings;
    }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode)]
    static extern int WinVerifyTrust(IntPtr hwnd, [MarshalAs(UnmanagedType.LPStruct)] Guid action, ref WINTRUST_DATA data);

    static readonly Guid GENERIC_VERIFY_V2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

    public static string Sha256(string datei) {
        using (var s = File.OpenRead(datei))
        using (var h = SHA256.Create()) {
            var sb = new StringBuilder();
            foreach (byte b in h.ComputeHash(s)) sb.Append(b.ToString("x2", CultureInfo.InvariantCulture));
            return sb.ToString();
        }
    }

    // Signatur gültig (ohne Online-Sperrprüfung, damit es auch offline geht) und von Microsoft Corporation.
    public static bool VonMicrosoft(string datei) {
        var fi = new WINTRUST_FILE_INFO();
        fi.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
        fi.pcwszFilePath = datei;
        IntPtr pfi = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
        try {
            Marshal.StructureToPtr(fi, pfi, false);
            var wd = new WINTRUST_DATA();
            wd.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
            wd.dwUIChoice = 2;           // WTD_UI_NONE
            wd.fdwRevocationChecks = 0;  // WTD_REVOKE_NONE
            wd.dwUnionChoice = 1;        // WTD_CHOICE_FILE
            wd.pFile = pfi;
            wd.dwStateAction = 0;
            wd.dwProvFlags = 0x10;       // WTD_CACHE_ONLY_URL_RETRIEVAL
            if (WinVerifyTrust(IntPtr.Zero, GENERIC_VERIFY_V2, ref wd) != 0) return false;
        } finally {
            Marshal.DestroyStructure(pfi, typeof(WINTRUST_FILE_INFO));
            Marshal.FreeHGlobal(pfi);
        }
        try {
            var cert = new X509Certificate2(X509Certificate.CreateFromSignedFile(datei));
            return cert.Subject.IndexOf("O=Microsoft Corporation", StringComparison.Ordinal) >= 0;
        } catch (Exception) {
            return false;
        }
    }

    public static bool Dateien(string ordner) {
        try {
            string core = Path.Combine(ordner, CORE), loader = Path.Combine(ordner, LOADER), js = Path.Combine(ordner, SKRIPT);
            if (!File.Exists(core) || !File.Exists(loader) || !File.Exists(js)) return false;
            if (Sha256(core) != CORE_SHA256 || Sha256(loader) != LOADER_SHA256) return false;
            if (new FileInfo(js).Length > 262144) return false;
            return VonMicrosoft(core) && VonMicrosoft(loader);
        } catch (Exception) {
            return false;
        }
    }
}
// --- Start: Argumente, Handles, Rechte, DPI -------------------------------------------------------

public static class UzbStart {
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr t, int cls, out int info, int len, out int ret);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    static readonly Regex PROFIL = new Regex("^[a-z0-9_-]{1,40}\\z", RegexOptions.CultureInvariant);

    // Nur genau diese drei Argumente: --uzai-wirt, --profil=<kennung>, --sprache=de-DE|en-US.
    public static bool Argumente(string[] args, out string profil, out string sprache) {
        profil = "";
        sprache = "";
        if (args == null || args.Length != 3 || args[0] != "--uzai-wirt") return false;
        if (!args[1].StartsWith("--profil=", StringComparison.Ordinal) || !args[2].StartsWith("--sprache=", StringComparison.Ordinal)) return false;
        profil = args[1].Substring(9);
        sprache = args[2].Substring(10);
        return PROFIL.IsMatch(profil) && (sprache == "de-DE" || sprache == "en-US");
    }

    // Standardein- und -ausgabe nicht vererben: Kein Prozess, den WebView2 startet, bekommt die Leitung.
    public static void HandlesSchliessen() {
        foreach (int n in new[] { -10, -11, -12 }) {
            IntPtr h = GetStdHandle(n);
            if (h != IntPtr.Zero && h != new IntPtr(-1)) SetHandleInformation(h, 1, 0);
        }
    }

    public static bool Erhoeht() {
        IntPtr t;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0008, out t)) return true;
        try {
            int erh, len;
            if (!GetTokenInformation(t, 20, out erh, 4, out len)) return true;
            return erh != 0;
        } finally {
            CloseHandle(t);
        }
    }

    public static void DpiBewusst() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (EntryPointNotFoundException) { }
        SetProcessDPIAware();
    }

    // Keine fremden Startargumente, kein anderer Browser-Ordner, kein Debugger über Umgebungsvariablen.
    public static void UmgebungLeeren() {
        var namen = new List<string>();
        foreach (System.Collections.DictionaryEntry e in Environment.GetEnvironmentVariables()) {
            string k = Convert.ToString(e.Key, CultureInfo.InvariantCulture) ?? "";
            if (k.StartsWith("WEBVIEW2_", StringComparison.OrdinalIgnoreCase) || k.StartsWith("COREWEBVIEW2_", StringComparison.OrdinalIgnoreCase)) namen.Add(k);
        }
        foreach (string k in namen) Environment.SetEnvironmentVariable(k, null);
        // Kein weißer Blitz vor dem ersten Bild: Graphit wie Uzai (ARGB).
        Environment.SetEnvironmentVariable("WEBVIEW2_DEFAULT_BACKGROUND_COLOR", "FF0B0B0D");
    }
}
// --- Der Wirt selbst (WebView2) -----------------------------------------------------------------

public sealed class UzbTab {
    public int Id;
    public CoreWebView2Controller C;
    public CoreWebView2 W;
    public int Kontext;            // Ausführungskontext der Welt „uzai“ im aktuellen Dokument (aus „hallo“)
    public bool Privat;
    public int Zoom = 100;
    public bool Laedt;
    public string HeimHost = "";   // Heimnetz-Name, den du selbst eingegeben hast (nur dorthin darf die Seite)
    public bool Zu;
}

public sealed class UzbWirt {
    public const string VERSION = "1";
    public const int MAX_TABS = 12;
    const string WELT = "uzai";
    const string BINDUNG = "__uzaiMeldung";
    const string FUNKTION = "function (a) { var u = globalThis.__uzai; if (u) u.befehl(a); }";

    readonly UzbFenster f;
    readonly UzbAusgabe aus;
    readonly string basis, profil, sprache, skript;
    readonly Dictionary<int, UzbTab> tabs = new Dictionary<int, UzbTab>();
    readonly Dictionary<int, Action<bool>> fragen = new Dictionary<int, Action<bool>>();
    CoreWebView2Environment env;
    int aktiv, naechsterTab = 1, naechsteFrage = 1;
    bool sichtbar, ende;
    string downloads = "", vorschau = "";

    public UzbWirt(UzbFenster f, UzbAusgabe aus, string basis, string profil, string sprache, string skript) {
        this.f = f;
        this.aus = aus;
        this.basis = basis;
        this.profil = profil;
        this.sprache = sprache;
        this.skript = skript;
        f.Groesse = delegate (int w, int h) {
            foreach (var t in tabs.Values) if (t.C != null) t.C.Bounds = new System.Drawing.Rectangle(0, 0, w, h);
        };
        f.Schliessen = Beenden;
    }

    static Dictionary<string, object> E(string art) {
        var d = new Dictionary<string, object>();
        d["t"] = art;
        return d;
    }

    void Gesperrt(int tab, string grund) {
        var d = E("gesperrt");
        d["tab"] = tab;
        d["grund"] = grund;
        aus.Senden(d);
    }

    public async void Starten() {
        try {
            string lokal = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string wurzel = Path.Combine(lokal, "Uzai", "browser");
            string daten = Path.Combine(wurzel, "profil", profil);
            vorschau = Path.Combine(wurzel, "vorschau");
            downloads = Path.Combine(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"), "Uzai Browser");
            Directory.CreateDirectory(daten);
            Directory.CreateDirectory(vorschau);
            CoreWebView2Environment.SetLoaderDllFolderPath(basis);
            string v = null;
            try { v = CoreWebView2Environment.GetAvailableBrowserVersionString(); } catch (Exception) { v = null; }
            if (string.IsNullOrEmpty(v)) { aus.Fehler("webview2"); Beenden(); return; }
            var o = new CoreWebView2EnvironmentOptions();
            o.AdditionalBrowserArguments = "";
            o.Language = sprache;
            o.AllowSingleSignOnUsingOSPrimaryAccount = false;
            o.ExclusiveUserDataFolderAccess = true;
            o.IsCustomCrashReportingEnabled = true;
            o.EnableTrackingPrevention = true;
            o.AreBrowserExtensionsEnabled = false;
            o.ScrollBarStyle = CoreWebView2ScrollbarStyle.FluentOverlay;
            env = await CoreWebView2Environment.CreateAsync(null, daten, o);
            var b = E("bereit");
            b["version"] = VERSION;
            aus.Senden(b);
        } catch (Exception) {
            aus.Fehler("start");
            Beenden();
        }
    }

    public void Beenden() {
        if (ende) return;
        ende = true;
        foreach (var t in new List<UzbTab>(tabs.Values)) {
            try { if (t.C != null) t.C.Close(); } catch (Exception) { }
        }
        tabs.Clear();
        f.Ende();
    }

    UzbTab Tab(Dictionary<string, object> b) {
        UzbTab t;
        return tabs.TryGetValue((int)b["tab"], out t) && t.W != null && !t.Zu ? t : null;
    }

    // Ein Befehl von Uzai (schon geprüft), auf dem Faden des Fensters.
    public void Befehl(Dictionary<string, object> b) {
        if (ende) return;
        string art = (string)b["t"];
        if (art == "ende") { Beenden(); return; }
        if (env == null) return;
        if (art == "fenster") { f.Lage((int)b["x"], (int)b["y"], (int)b["w"], (int)b["h"]); return; }
        if (art == "zeigen") { Zeigen((bool)b["an"]); return; }
        if (art == "tab-neu") { TabNeu((string)b["url"], (bool)b["privat"], (bool)b["vorn"], (bool)b["nutzer"]); return; }
        if (art == "antwort") {
            Action<bool> a;
            if (fragen.TryGetValue((int)b["frage"], out a)) { fragen.Remove((int)b["frage"]); a((bool)b["ja"]); }
            return;
        }
        // Befehle ohne Tab (Kern-Pflege, Blocker-Liste, Spotify-Abfragen) gehören dem CEF-Kern: hier still übergangen.
        if (!b.ContainsKey("tab")) return;
        UzbTab t = Tab(b);
        if (t == null) return;
        switch (art) {
            case "tab-zu": TabZu(t); break;
            case "tab-wahl": Waehlen(t); break;
            case "laden": Laden(t, (string)b["url"], (bool)b["nutzer"]); break;
            case "zurueck": if (t.W.CanGoBack) t.W.GoBack(); break;
            case "vor": if (t.W.CanGoForward) t.W.GoForward(); break;
            case "neu": t.W.Reload(); break;
            case "stopp": t.W.Stop(); break;
            case "zoom":
                t.Zoom = (int)b["prozent"];
                t.C.ZoomFactor = t.Zoom / 100.0;
                Skript(t, Arg("zoom"));
                Status(t);
                break;
            case "rollen": { var a = Arg("rollen"); a["vx"] = b["vx"]; a["vy"] = b["vy"]; Skript(t, a); break; }
            case "karte": Skript(t, Arg("karte")); break;
            case "fokus": { var a = Arg("fokus"); a["id"] = b["id"]; Skript(t, a); break; }
            case "aktivieren": { var a = Arg("aktivieren"); a["id"] = b["id"]; a["neu"] = b["neu"]; Skript(t, a); break; }
            case "link": { var a = Arg("link"); a["id"] = b["id"]; Skript(t, a); break; }
            case "feld": { var a = Arg("feld"); a["id"] = b["id"]; Skript(t, a); break; }
            case "text": Tippen(t, (string)b["text"]); break;
            case "taste": Taste(t, (string)b["taste"]); break;
            case "klick": Klick(t, (int)b["x"], (int)b["y"]); break;
            case "zeiger": Maus(t, "mouseMoved", (int)b["x"], (int)b["y"], 0); break;
            case "rad": Maus(t, "mouseWheel", (int)b["x"], (int)b["y"], (int)b["dy"]); break;
            case "video": { var a = Arg("video"); a["aktion"] = b["aktion"]; Skript(t, a); break; }
            case "lesen": Skript(t, Arg("lesen")); break;
            case "vorschau": Vorschau(t); break;
        }
    }

    static Dictionary<string, object> Arg(string art) {
        var d = new Dictionary<string, object>();
        d["t"] = art;
        return d;
    }

    void Zeigen(bool an) {
        sichtbar = an;
        f.Zeigen(an);
        UzbTab t;
        if (tabs.TryGetValue(aktiv, out t) && t.C != null) t.C.IsVisible = an;
    }

    async void TabNeu(string url, bool privat, bool vorn, bool nutzer) {
        if (tabs.Count >= MAX_TABS) { aus.Fehler("tabs"); return; }
        var t = new UzbTab();
        t.Id = naechsterTab++;
        t.Privat = privat;
        tabs[t.Id] = t;
        try {
            var o = env.CreateCoreWebView2ControllerOptions();
            o.ProfileName = privat ? "privat" : "uzai";
            o.IsInPrivateModeEnabled = privat;
            o.ScriptLocale = sprache;
            var c = await env.CreateCoreWebView2ControllerAsync(f.Hwnd, o);
            if (t.Zu || ende) { c.Close(); return; }
            t.C = c;
            t.W = c.CoreWebView2;
            c.Bounds = new System.Drawing.Rectangle(0, 0, f.Breite, f.Hoehe);
            c.IsVisible = false;
            Einrichten(t);
            await Welt(t);
            if (t.Zu || ende) return;
            if (vorn || aktiv == 0) Waehlen(t);
            Laden(t, url, nutzer);
            Status(t);
        } catch (Exception) {
            tabs.Remove(t.Id);
            aus.Fehler("start");
        }
    }

    void TabZu(UzbTab t) {
        t.Zu = true;
        tabs.Remove(t.Id);
        if (aktiv == t.Id) aktiv = 0;
        try { t.C.Close(); } catch (Exception) { }
        try { File.Delete(Path.Combine(vorschau, "tab-" + t.Id.ToString(CultureInfo.InvariantCulture) + ".jpg")); } catch (Exception) { }
        var d = E("tab-zu");
        d["tab"] = t.Id;
        aus.Senden(d);
    }

    void Waehlen(UzbTab t) {
        UzbTab alt;
        if (aktiv != t.Id && tabs.TryGetValue(aktiv, out alt) && alt.C != null) {
            alt.C.IsVisible = false;
            try { alt.W.MemoryUsageTargetLevel = CoreWebView2MemoryUsageTargetLevel.Low; } catch (Exception) { }
        }
        aktiv = t.Id;
        try { t.W.MemoryUsageTargetLevel = CoreWebView2MemoryUsageTargetLevel.Normal; } catch (Exception) { }
        t.C.IsVisible = sichtbar;
        Skript(t, Arg("karte"));
        Status(t);
    }

    void Laden(UzbTab t, string url, bool nutzer) {
        if (nutzer) {
            string h = UzbRegeln.Host(url);
            t.HeimHost = UzbRegeln.IstHeimnetz(h) && !UzbRegeln.IstLokal(h) ? h : "";
        }
        string g = UzbRegeln.UrlGrund(url, HeimErlaubt(t, url));
        if (g != "") { Gesperrt(t.Id, g); return; }
        t.W.Navigate(url);
    }

    static bool HeimErlaubt(UzbTab t, string url) {
        return t.HeimHost != "" && UzbRegeln.Host(url) == t.HeimHost;
    }

    // Steht die Seite selbst im Heimnetz (du hast sie eingegeben)? Dann darf sie Teile aus dem Heimnetz laden.
    static bool HeimSeite(UzbTab t) {
        return t.HeimHost != "" && UzbRegeln.Host(t.W.Source) == t.HeimHost;
    }

    void Einrichten(UzbTab t) {
        var s = t.W.Settings;
        s.AreDevToolsEnabled = false;
        s.AreDefaultContextMenusEnabled = false;
        s.AreDefaultScriptDialogsEnabled = false;
        s.AreHostObjectsAllowed = false;
        s.IsWebMessageEnabled = false;
        s.IsStatusBarEnabled = false;
        s.IsZoomControlEnabled = false;
        s.IsBuiltInErrorPageEnabled = true;
        s.AreBrowserAcceleratorKeysEnabled = false;
        s.IsPasswordAutosaveEnabled = false;
        s.IsGeneralAutofillEnabled = false;
        s.IsSwipeNavigationEnabled = false;
        s.IsReputationCheckingRequired = true;
        s.IsNonClientRegionSupportEnabled = false;
        var p = t.W.Profile;
        p.PreferredTrackingPreventionLevel = CoreWebView2TrackingPreventionLevel.Strict;
        p.PreferredColorScheme = CoreWebView2PreferredColorScheme.Dark;
        p.IsPasswordAutosaveEnabled = false;
        p.IsGeneralAutofillEnabled = false;
        try { Directory.CreateDirectory(downloads); p.DefaultDownloadFolderPath = downloads; } catch (Exception) { }

        t.W.NavigationStarting += delegate (object o, CoreWebView2NavigationStartingEventArgs a) {
            string u = a.Uri ?? "";
            if (u == "about:blank") return;
            string g = UzbRegeln.UrlGrund(u, HeimErlaubt(t, u));
            if (g != "") { a.Cancel = true; Gesperrt(t.Id, g); return; }
            t.Laedt = true;
            Status(t);
        };
        t.W.FrameNavigationStarting += delegate (object o, CoreWebView2NavigationStartingEventArgs a) {
            string u = a.Uri ?? "";
            string low = u.ToLowerInvariant();
            if (low.StartsWith("about:", StringComparison.Ordinal) || low.StartsWith("data:", StringComparison.Ordinal) || low.StartsWith("blob:", StringComparison.Ordinal)) return;
            string g = UzbRegeln.UrlGrund(u, HeimErlaubt(t, u));
            if (g == "heimnetz" && HeimSeite(t)) g = "";
            if (g != "") a.Cancel = true;
        };
        t.W.NavigationCompleted += delegate (object o, CoreWebView2NavigationCompletedEventArgs a) { t.Laedt = false; Status(t); };
        t.W.SourceChanged += delegate (object o, CoreWebView2SourceChangedEventArgs a) { Status(t); };
        t.W.HistoryChanged += delegate (object o, object a) { Status(t); };
        t.W.DocumentTitleChanged += delegate (object o, object a) { Status(t); };
        t.W.NewWindowRequested += delegate (object o, CoreWebView2NewWindowRequestedEventArgs a) {
            a.Handled = true;
            if (!a.IsUserInitiated) { Gesperrt(t.Id, "popup"); return; }
            string u = a.Uri ?? "";
            string g = UzbRegeln.UrlGrund(u, HeimErlaubt(t, u));
            if (g != "") { Gesperrt(t.Id, g); return; }
            TabNeu(u, t.Privat, true, false);
        };
        t.W.WindowCloseRequested += delegate (object o, object a) { if (!t.Zu) TabZu(t); };
        t.W.LaunchingExternalUriScheme += delegate (object o, CoreWebView2LaunchingExternalUriSchemeEventArgs a) { a.Cancel = true; Gesperrt(t.Id, "app"); };
        t.W.DownloadStarting += delegate (object o, CoreWebView2DownloadStartingEventArgs a) { Download(t, a); };
        t.W.SaveAsUIShowing += delegate (object o, CoreWebView2SaveAsUIShowingEventArgs a) { a.Cancel = true; };
        t.W.SaveFileSecurityCheckStarting += delegate (object o, CoreWebView2SaveFileSecurityCheckStartingEventArgs a) {
            if (!UzbRegeln.DownloadOk("x." + (a.FileExtension ?? "").TrimStart('.'))) a.CancelSave = true;
        };
        t.W.PermissionRequested += delegate (object o, CoreWebView2PermissionRequestedEventArgs a) { Erlaubnis(t, a); };
        t.W.ScriptDialogOpening += delegate (object o, CoreWebView2ScriptDialogOpeningEventArgs a) { Dialog(t, a); };
        t.W.BasicAuthenticationRequested += delegate (object o, CoreWebView2BasicAuthenticationRequestedEventArgs a) { a.Cancel = true; Gesperrt(t.Id, "anmeldedialog"); };
        t.W.ClientCertificateRequested += delegate (object o, CoreWebView2ClientCertificateRequestedEventArgs a) { a.Cancel = true; a.Handled = true; };
        t.W.ServerCertificateErrorDetected += delegate (object o, CoreWebView2ServerCertificateErrorDetectedEventArgs a) {
            a.Action = CoreWebView2ServerCertificateErrorAction.Cancel;
            Gesperrt(t.Id, "zertifikat");
        };
        t.W.ScreenCaptureStarting += delegate (object o, CoreWebView2ScreenCaptureStartingEventArgs a) { a.Cancel = true; a.Handled = true; };
        t.W.NotificationReceived += delegate (object o, CoreWebView2NotificationReceivedEventArgs a) { a.Handled = true; };
        t.W.ContainsFullScreenElementChanged += delegate (object o, object a) {
            var d = E("vollbild");
            d["tab"] = t.Id;
            d["an"] = t.W.ContainsFullScreenElement;
            aus.Senden(d);
        };
        t.W.ProcessFailed += delegate (object o, CoreWebView2ProcessFailedEventArgs a) {
            if (a.ProcessFailedKind == CoreWebView2ProcessFailedKind.BrowserProcessExited) { aus.Fehler("absturz"); Beenden(); return; }
            if (a.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessExited || a.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessUnresponsive) {
                var d = E("absturz");
                d["tab"] = t.Id;
                aus.Senden(d);
            }
        };
        // Unteranfragen an diesen PC nie, ins Heimnetz nur von einer Seite im Heimnetz (DNS-Namen prüft Chromium
        // selbst nicht vorab – siehe docs/SECURITY.md, Bekannte Grenzen).
        foreach (string muster in new[] { "*://localhost*", "*://*.localhost*", "*://127.*", "*://0.*", "*://[*", "*://10.*", "*://192.168.*",
                "*://172.*", "*://169.254.*", "*://100.*", "*://2130706433*", "*://0x*" })
            t.W.AddWebResourceRequestedFilter(muster, CoreWebView2WebResourceContext.All);
        t.W.WebResourceRequested += delegate (object o, CoreWebView2WebResourceRequestedEventArgs a) {
            string u = a.Request.Uri ?? "";
            if (UzbRegeln.ZielGesperrt(u, HeimErlaubt(t, u) || HeimSeite(t))) a.Response = env.CreateWebResourceResponse(null, 403, "Forbidden", "");
        };
    }

    // Uzais Welt in der Seite: Bindung nur in dieser Welt, Skript nur dort, Fokus wie mit einem Fenster vorn.
    async Task Welt(UzbTab t) {
        await t.W.CallDevToolsProtocolMethodAsync("Runtime.enable", "{}");
        var bind = new Dictionary<string, object>();
        bind["name"] = BINDUNG;
        bind["executionContextName"] = WELT;
        await t.W.CallDevToolsProtocolMethodAsync("Runtime.addBinding", UzbJson.Schreiben(bind));
        t.W.GetDevToolsProtocolEventReceiver("Runtime.bindingCalled").DevToolsProtocolEventReceived +=
            delegate (object o, CoreWebView2DevToolsProtocolEventReceivedEventArgs a) { Meldung(t, a.ParameterObjectAsJson); };
        var fokus = new Dictionary<string, object>();
        fokus["enabled"] = true;
        await t.W.CallDevToolsProtocolMethodAsync("Emulation.setFocusEmulationEnabled", UzbJson.Schreiben(fokus));
        var sk = new Dictionary<string, object>();
        sk["source"] = skript;
        sk["worldName"] = WELT;
        sk["runImmediately"] = true;
        await t.W.CallDevToolsProtocolMethodAsync("Page.addScriptToEvaluateOnNewDocument", UzbJson.Schreiben(sk));
    }

    // Meldung des Sprung-Skripts: fremde Daten.
    void Meldung(UzbTab t, string json) {
        if (t.Zu || json == null || json.Length > UzbSchema.MAX_EREIGNIS + 4096) return;
        var p = UzbJson.Lesen(json) as Dictionary<string, object>;
        if (p == null) return;
        object name, payload, ctx;
        if (!p.TryGetValue("name", out name) || !(name is string) || (string)name != BINDUNG) return;
        if (!p.TryGetValue("payload", out payload) || !(payload is string) || ((string)payload).Length > UzbSchema.MAX_EREIGNIS) return;
        int kontext = 0;
        if (p.TryGetValue("executionContextId", out ctx) && ctx is double) kontext = (int)(double)ctx;
        var m = UzbSchema.Skript(UzbJson.Lesen((string)payload));
        if (m == null) return;
        string art = (string)m["t"];
        if (art == "hallo") { t.Kontext = kontext; return; }
        if (kontext != t.Kontext) return;
        if (art == "klick") { if (t.Id == aktiv) Klick(t, (int)m["x"], (int)m["y"]); return; }
        if (art == "zeiger") { if (t.Id == aktiv) Maus(t, "mouseMoved", (int)m["x"], (int)m["y"], 0); return; }
        if (art == "oeffnen") {
            string u = (string)m["url"];
            string g = UzbRegeln.UrlGrund(u, HeimErlaubt(t, u));
            if (g != "") Gesperrt(t.Id, g); else TabNeu(u, t.Privat, false, false);
            return;
        }
        m["tab"] = t.Id;
        aus.Senden(m);
    }

    async void Skript(UzbTab t, Dictionary<string, object> arg) {
        if (t.Kontext == 0 || t.Zu) return;
        var p = new Dictionary<string, object>();
        p["functionDeclaration"] = FUNKTION;
        p["executionContextId"] = t.Kontext;
        var wert = new Dictionary<string, object>();
        wert["value"] = arg;
        p["arguments"] = new List<object> { wert };
        p["returnByValue"] = true;
        p["userGesture"] = true;
        p["silent"] = true;
        try { await t.W.CallDevToolsProtocolMethodAsync("Runtime.callFunctionOn", UzbJson.Schreiben(p)); } catch (Exception) { /* Dokument gerade weg */ }
    }

    async void Cdp(UzbTab t, string methode, Dictionary<string, object> p) {
        if (t.Zu) return;
        try { await t.W.CallDevToolsProtocolMethodAsync(methode, UzbJson.Schreiben(p)); } catch (Exception) { }
    }

    // CSS-Pixel der Seite (Rechtecke des Sprung-Skripts) → Punkte des Fensters: mit dem Zoom des Tabs.
    static double Punkt(UzbTab t, int css) { return Math.Round(css * t.Zoom / 100.0, 1); }

    // Ein echter Mausklick nur in diese Seite (keine Eingabe an Windows, kein anderes Fenster).
    void Klick(UzbTab t, int x, int y) {
        foreach (string typ in new[] { "mouseMoved", "mousePressed", "mouseReleased" }) {
            var p = new Dictionary<string, object>();
            p["type"] = typ;
            p["x"] = Punkt(t, x);
            p["y"] = Punkt(t, y);
            if (typ != "mouseMoved") { p["button"] = "left"; p["buttons"] = typ == "mousePressed" ? 1 : 0; p["clickCount"] = 1; }
            Cdp(t, "Input.dispatchMouseEvent", p);
        }
    }

    void Maus(UzbTab t, string typ, int x, int y, int dy) {
        var p = new Dictionary<string, object>();
        p["type"] = typ;
        p["x"] = Punkt(t, x);
        p["y"] = Punkt(t, y);
        if (typ == "mouseWheel") { p["deltaX"] = 0; p["deltaY"] = dy; }
        Cdp(t, "Input.dispatchMouseEvent", p);
    }

    void Tippen(UzbTab t, string text) {
        var p = new Dictionary<string, object>();
        p["text"] = text;
        Cdp(t, "Input.insertText", p);
    }

    void Taste(UzbTab t, string taste) {
        string key = "", code = "", text = "";
        int vk = 0, mod = 0;
        switch (taste) {
            case "enter": key = "Enter"; code = "Enter"; vk = 13; text = "\r"; break;
            case "tab": key = "Tab"; code = "Tab"; vk = 9; break;
            case "umschalt_tab": key = "Tab"; code = "Tab"; vk = 9; mod = 8; break;
            case "escape": key = "Escape"; code = "Escape"; vk = 27; break;
            case "backspace": key = "Backspace"; code = "Backspace"; vk = 8; break;
            case "links": key = "ArrowLeft"; code = "ArrowLeft"; vk = 37; break;
            case "rechts": key = "ArrowRight"; code = "ArrowRight"; vk = 39; break;
            case "hoch": key = "ArrowUp"; code = "ArrowUp"; vk = 38; break;
            case "runter": key = "ArrowDown"; code = "ArrowDown"; vk = 40; break;
            case "seite_hoch": key = "PageUp"; code = "PageUp"; vk = 33; break;
            case "seite_runter": key = "PageDown"; code = "PageDown"; vk = 34; break;
            case "pos1": key = "Home"; code = "Home"; vk = 36; break;
            case "ende": key = "End"; code = "End"; vk = 35; break;
            case "leer": key = " "; code = "Space"; vk = 32; text = " "; break;
            default: return;
        }
        foreach (string typ in new[] { "keyDown", "keyUp" }) {
            var p = new Dictionary<string, object>();
            p["type"] = typ == "keyDown" && text != "" ? "keyDown" : (typ == "keyDown" ? "rawKeyDown" : "keyUp");
            p["key"] = key;
            p["code"] = code;
            p["windowsVirtualKeyCode"] = vk;
            p["modifiers"] = mod;
            if (typ == "keyDown" && text != "") p["text"] = text;
            Cdp(t, "Input.dispatchKeyEvent", p);
        }
    }

    async void Vorschau(UzbTab t) {
        if (t.Zu) return;
        string name = "tab-" + t.Id.ToString(CultureInfo.InvariantCulture) + ".jpg";
        string ziel = Path.Combine(vorschau, name), neu = ziel + ".neu";
        try {
            using (var fs = new FileStream(neu, FileMode.Create, FileAccess.Write)) {
                await t.W.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Jpeg, fs);
            }
            if (File.Exists(ziel)) File.Delete(ziel);
            File.Move(neu, ziel);
            var d = E("vorschau");
            d["tab"] = t.Id;
            d["datei"] = name;
            aus.Senden(d);
        } catch (Exception) {
            try { File.Delete(neu); } catch (Exception) { }
        }
    }

    void Download(UzbTab t, CoreWebView2DownloadStartingEventArgs a) {
        a.Handled = true;
        string name = UzbRegeln.Dateiname(Path.GetFileName(a.ResultFilePath ?? ""));
        var d = E("download");
        d["name"] = UzbRegeln.Sauber(name, 120);
        if (!UzbRegeln.DownloadOk(name) || UzbRegeln.UrlGrund(a.DownloadOperation.Uri ?? "", HeimErlaubt(t, a.DownloadOperation.Uri ?? "")) != "") {
            a.Cancel = true;
            d["stand"] = "gesperrt";
            aus.Senden(d);
            return;
        }
        try {
            Directory.CreateDirectory(downloads);
            string ziel = Path.Combine(downloads, name);
            int n = 2;
            string stamm = Path.GetFileNameWithoutExtension(name), ext = Path.GetExtension(name);
            while (File.Exists(ziel) && n < 1000) ziel = Path.Combine(downloads, stamm + " (" + (n++).ToString(CultureInfo.InvariantCulture) + ")" + ext);
            a.ResultFilePath = ziel;
        } catch (Exception) {
            a.Cancel = true;
            d["stand"] = "fehler";
            aus.Senden(d);
            return;
        }
        d["stand"] = "laeuft";
        aus.Senden(d);
        var op = a.DownloadOperation;
        op.StateChanged += delegate (object o, object x) {
            if (op.State == CoreWebView2DownloadState.InProgress) return;
            var e = E("download");
            e["name"] = UzbRegeln.Sauber(name, 120);
            e["stand"] = op.State == CoreWebView2DownloadState.Completed ? "fertig" : "fehler";
            aus.Senden(e);
        };
    }

    // Kamera, Mikrofon, Standort: Uzai fragt (60 s, sonst nein). Alles andere: nein.
    void Erlaubnis(UzbTab t, CoreWebView2PermissionRequestedEventArgs a) {
        a.SavesInProfile = false;
        string art = a.PermissionKind == CoreWebView2PermissionKind.Camera ? "kamera" : (a.PermissionKind == CoreWebView2PermissionKind.Microphone ? "mikrofon"
            : (a.PermissionKind == CoreWebView2PermissionKind.Geolocation ? "standort" : ""));
        // Automatisch abspielen entscheidet WebView2 selbst (nichts Gefährliches), alles andere ohne Rückfrage: nein.
        if (a.PermissionKind == CoreWebView2PermissionKind.Autoplay) return;
        if (art == "") { a.State = CoreWebView2PermissionState.Deny; return; }
        var aufschub = a.GetDeferral();
        Fragen(art, UzbRegeln.Host(a.Uri ?? ""), "", delegate (bool ja) {
            try { a.State = ja ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny; } finally { aufschub.Complete(); }
        });
    }

    void Dialog(UzbTab t, CoreWebView2ScriptDialogOpeningEventArgs a) {
        string herkunft = UzbRegeln.Host(a.Uri ?? "");
        string text = UzbRegeln.Sauber(a.Message ?? "", 300);
        switch (a.Kind) {
            case CoreWebView2ScriptDialogKind.Alert: {
                var d = E("meldung");
                d["tab"] = t.Id;
                d["herkunft"] = herkunft;
                d["text"] = text;
                aus.Senden(d);
                a.Accept();
                break;
            }
            case CoreWebView2ScriptDialogKind.Confirm: {
                var aufschub = a.GetDeferral();
                Fragen("bestaetigen", herkunft, text, delegate (bool ja) { try { if (ja) a.Accept(); } finally { aufschub.Complete(); } });
                break;
            }
            case CoreWebView2ScriptDialogKind.Beforeunload:
                a.Accept();
                break;
            default:
                break;   // Eingabe-Dialoge der Seite: abgelehnt (Texte tippt man in Uzais Tastatur)
        }
    }

    void Fragen(string art, string herkunft, string text, Action<bool> antwort) {
        int id = naechsteFrage++;
        Timer uhr = null;
        bool fertig = false;
        Action<bool> einmal = delegate (bool ja) {
            if (fertig) return;
            fertig = true;
            fragen.Remove(id);
            if (uhr != null) uhr.Dispose();
            antwort(ja);
        };
        fragen[id] = einmal;
        var d = E("frage");
        d["frage"] = id;
        d["art"] = art;
        d["herkunft"] = UzbRegeln.Sauber(herkunft, 253);
        d["text"] = text;
        if (!aus.Senden(d)) { einmal(false); return; }
        uhr = new Timer(delegate (object s) { f.Post(delegate () { einmal(false); }); }, null, 60000, Timeout.Infinite);
    }

    void Status(UzbTab t) {
        if (t.Zu || t.W == null) return;
        var d = E("tab");
        d["tab"] = t.Id;
        string src = t.W.Source ?? "";
        d["url"] = src == "about:blank" || UzbRegeln.UrlGrund(src, true) == "" ? src : "about:blank";
        d["titel"] = UzbRegeln.Sauber(t.W.DocumentTitle ?? "", 300);
        d["laedt"] = t.Laedt;
        d["zurueck"] = t.W.CanGoBack;
        d["vor"] = t.W.CanGoForward;
        d["zoom"] = t.Zoom;
        d["privat"] = t.Privat;
        d["aktiv"] = t.Id == aktiv;
        aus.Senden(d);
    }
}

// --- Programm -----------------------------------------------------------------------------------

public static class UzbProgramm {
    [STAThread]
    public static int Main(string[] args) {
        try { return Lauf(args); } catch (Exception) { return 3; }
    }

    static int Lauf(string[] args) {
        string profil, sprache;
        if (!UzbStart.Argumente(args, out profil, out sprache)) return 2;
        UzbStart.HandlesSchliessen();
        var aus = new UzbAusgabe(Console.OpenStandardOutput());
        if (UzbStart.Erhoeht()) { aus.Fehler("start"); return 4; }
        string basis = AppDomain.CurrentDomain.BaseDirectory;
        if (!UzbPruefung.Dateien(basis)) { aus.Fehler("pruefung"); return 5; }
        string skript = File.ReadAllText(Path.Combine(basis, UzbPruefung.SKRIPT), new UTF8Encoding(false, true));
        UzbStart.UmgebungLeeren();
        UzbStart.DpiBewusst();
        return UzbLauf.Start(basis, profil, sprache, skript, aus);
    }
}

// Erst hier wird WebView2 geladen (nach der Prüfung oben).
public static class UzbLauf {
    [MethodImpl(MethodImplOptions.NoInlining)]
    public static int Start(string basis, string profil, string sprache, string skript, UzbAusgabe aus) {
        var f = new UzbFenster();
        if (!f.Erstellen(0, 0, 1280, 720)) { aus.Fehler("start"); return 6; }
        SynchronizationContext.SetSynchronizationContext(new UzbKontext(f));
        var w = new UzbWirt(f, aus, basis, profil, sprache, skript);
        UzbEingabe.Lesen(Console.OpenStandardInput(), delegate (Dictionary<string, object> b) { f.Post(delegate () { w.Befehl(b); }); },
            delegate () { f.Post(w.Beenden); });
        f.Post(w.Starten);
        f.Schleife();
        return 0;
    }
}
