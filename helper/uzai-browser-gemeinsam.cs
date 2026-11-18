// Uzai-Browser: gemeinsame Teile beider Wirte (docs/SECURITY.md „Uzai-Browser“, docs/BROWSER_PLAN.md).
//
// Der Helfer übersetzt diese Datei zusammen mit uzai-browser-kern.cs (Chromium über CEF, der Browser-Kern) bzw.
// uzai-browser-wirt.cs (Microsofts WebView2, nur noch als ausdrücklich gewählter Notnagel) – C# 5, .NET Framework 4,
// Add-Type; tests/browser_cs.ps1 und tests/browser_kern_cs.ps1 prüfen beides unter Linux.
//
// Hier steht alles, was nicht vom Kern abhängt: der strenge JSON-Leser, die Adress- und Download-Regeln (gleich wie
// src/core/browser_adresse.gd), das Schema der Leitung in beiden Richtungen (gleich wie src/core/browser_protokoll.gd),
// Ein- und Ausgabe über die anonyme Leitung (Standardein-/-ausgabe, Zeilen mit Längengrenze), das randlose Fenster,
// das nie aktiv wird, und der Werbe-/Tracker-Blocker (UzbFilter, Regeln als Daten aus assets/browser/filter).

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

// --- JSON: streng, mit Tiefen- und Längengrenze -------------------------------------------------

public static class UzbJson {
    public const int TIEFE = 8;
    public static readonly object NICHTS = new object();

    sealed class Kaputt : Exception { }

    // null = kaputt. JSON null wird zu NICHTS.
    public static object Lesen(string s) {
        if (s == null) return null;
        int i = 0;
        try {
            object v = Wert(s, ref i, 0);
            Leer(s, ref i);
            return i == s.Length ? v : null;
        } catch (Kaputt) {
            return null;
        }
    }

    static void Leer(string s, ref int i) {
        while (i < s.Length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++;
    }

    static object Wert(string s, ref int i, int tiefe) {
        if (tiefe > TIEFE) throw new Kaputt();
        Leer(s, ref i);
        if (i >= s.Length) throw new Kaputt();
        char c = s[i];
        if (c == '{') {
            i++;
            var d = new Dictionary<string, object>();
            Leer(s, ref i);
            if (i < s.Length && s[i] == '}') { i++; return d; }
            while (true) {
                Leer(s, ref i);
                if (i >= s.Length || s[i] != '"') throw new Kaputt();
                string k = Text(s, ref i);
                Leer(s, ref i);
                if (i >= s.Length || s[i] != ':') throw new Kaputt();
                i++;
                object v = Wert(s, ref i, tiefe + 1);
                if (d.ContainsKey(k)) throw new Kaputt();
                d[k] = v;
                Leer(s, ref i);
                if (i >= s.Length) throw new Kaputt();
                if (s[i] == ',') { i++; continue; }
                if (s[i] == '}') { i++; return d; }
                throw new Kaputt();
            }
        }
        if (c == '[') {
            i++;
            var l = new List<object>();
            Leer(s, ref i);
            if (i < s.Length && s[i] == ']') { i++; return l; }
            while (true) {
                l.Add(Wert(s, ref i, tiefe + 1));
                Leer(s, ref i);
                if (i >= s.Length) throw new Kaputt();
                if (s[i] == ',') { i++; continue; }
                if (s[i] == ']') { i++; return l; }
                throw new Kaputt();
            }
        }
        if (c == '"') return Text(s, ref i);
        if (Wort(s, i, "true")) { i += 4; return true; }
        if (Wort(s, i, "false")) { i += 5; return false; }
        if (Wort(s, i, "null")) { i += 4; return NICHTS; }
        return Zahl(s, ref i);
    }

    static bool Wort(string s, int i, string w) {
        return i + w.Length <= s.Length && string.CompareOrdinal(s, i, w, 0, w.Length) == 0;
    }

    static object Zahl(string s, ref int i) {
        int a = i;
        if (i < s.Length && s[i] == '-') i++;
        int ziffern = 0;
        while (i < s.Length && s[i] >= '0' && s[i] <= '9') { i++; ziffern++; }
        if (ziffern == 0) throw new Kaputt();
        if (i < s.Length && s[i] == '.') {
            i++;
            int n = 0;
            while (i < s.Length && s[i] >= '0' && s[i] <= '9') { i++; n++; }
            if (n == 0) throw new Kaputt();
        }
        if (i < s.Length && (s[i] == 'e' || s[i] == 'E')) {
            i++;
            if (i < s.Length && (s[i] == '+' || s[i] == '-')) i++;
            int n = 0;
            while (i < s.Length && s[i] >= '0' && s[i] <= '9') { i++; n++; }
            if (n == 0) throw new Kaputt();
        }
        if (i - a > 40) throw new Kaputt();
        double d;
        if (!double.TryParse(s.Substring(a, i - a), NumberStyles.Float, CultureInfo.InvariantCulture, out d)) throw new Kaputt();
        if (double.IsNaN(d) || double.IsInfinity(d)) throw new Kaputt();
        return d;
    }

    static string Text(string s, ref int i) {
        i++;
        var sb = new StringBuilder();
        while (true) {
            if (i >= s.Length) throw new Kaputt();
            char c = s[i++];
            if (c == '"') return sb.ToString();
            if (c < 0x20) throw new Kaputt();
            if (c != '\\') { sb.Append(c); continue; }
            if (i >= s.Length) throw new Kaputt();
            char e = s[i++];
            switch (e) {
                case '"': sb.Append('"'); break;
                case '\\': sb.Append('\\'); break;
                case '/': sb.Append('/'); break;
                case 'b': sb.Append('\b'); break;
                case 'f': sb.Append('\f'); break;
                case 'n': sb.Append('\n'); break;
                case 'r': sb.Append('\r'); break;
                case 't': sb.Append('\t'); break;
                case 'u': {
                    if (i + 4 > s.Length) throw new Kaputt();
                    int v;
                    if (!int.TryParse(s.Substring(i, 4), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out v)) throw new Kaputt();
                    sb.Append((char)v);
                    i += 4;
                    break;
                }
                default: throw new Kaputt();
            }
        }
    }

    public static string Schreiben(object v) {
        var sb = new StringBuilder();
        Schreib(sb, v, 0);
        return sb.ToString();
    }

    static void Schreib(StringBuilder sb, object v, int tiefe) {
        if (tiefe > TIEFE + 2) throw new InvalidOperationException("zu tief");
        if (v == null || v == NICHTS) { sb.Append("null"); return; }
        if (v is bool) { sb.Append((bool)v ? "true" : "false"); return; }
        if (v is int) { sb.Append(((int)v).ToString(CultureInfo.InvariantCulture)); return; }
        if (v is long) { sb.Append(((long)v).ToString(CultureInfo.InvariantCulture)); return; }
        if (v is double) {
            double d = (double)v;
            if (double.IsNaN(d) || double.IsInfinity(d)) d = 0;
            sb.Append(d.ToString("R", CultureInfo.InvariantCulture));
            return;
        }
        var s = v as string;
        if (s != null) { Zitat(sb, s); return; }
        var d2 = v as Dictionary<string, object>;
        if (d2 != null) {
            sb.Append('{');
            bool erst = true;
            foreach (var kv in d2) {
                if (!erst) sb.Append(',');
                erst = false;
                Zitat(sb, kv.Key);
                sb.Append(':');
                Schreib(sb, kv.Value, tiefe + 1);
            }
            sb.Append('}');
            return;
        }
        var l = v as List<object>;
        if (l != null) {
            sb.Append('[');
            for (int i = 0; i < l.Count; i++) {
                if (i > 0) sb.Append(',');
                Schreib(sb, l[i], tiefe + 1);
            }
            sb.Append(']');
            return;
        }
        throw new InvalidOperationException("Typ");
    }

    public static void Zitat(StringBuilder sb, string s) {
        sb.Append('"');
        foreach (char c in s) {
            switch (c) {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20 || c == 0x7F || c == 0x2028 || c == 0x2029 || (c >= 0xD800 && c <= 0xDFFF))
                        sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }
}
// --- Regeln: Adressen, Texte, Downloads (gleich wie src/core/browser_adresse.gd) -------------------

public static class UzbRegeln {
    public const int MAX_URL = 4096;

    // Warum diese Adresse nicht geöffnet wird ("" = in Ordnung).
    public static string UrlGrund(string u, bool vomNutzer) {
        if (u == null) return "zeichen";
        if (u.Length > MAX_URL || u.Length == 0) return "laenge";
        foreach (char c in u) if (c <= 32 || c == 127 || c > 126) return "zeichen";
        string low = u.ToLowerInvariant();
        string rest;
        if (low.StartsWith("https://", StringComparison.Ordinal)) rest = u.Substring(8);
        else if (low.StartsWith("http://", StringComparison.Ordinal)) rest = u.Substring(7);
        else return "protokoll";
        string aut = rest.Substring(0, AutoritaetEnde(rest));
        if (aut.IndexOf('@') >= 0) return "anmeldung";
        if (aut.IndexOf('\\') >= 0) return "zeichen";
        string host, port;
        if (!HostPort(aut, out host, out port)) return "name";
        if (IstLokal(host)) return "lokal";
        if (IstHeimnetz(host) && !vomNutzer) return "heimnetz";
        return "";
    }

    static int AutoritaetEnde(string rest) {
        int ende = rest.Length;
        foreach (char z in new[] { '/', '?', '#' }) {
            int k = rest.IndexOf(z);
            if (k >= 0 && k < ende) ende = k;
        }
        return ende;
    }

    // Name der Seite (klein, ohne Anschluss) oder "".
    public static string Host(string u) {
        if (u == null) return "";
        string low = u.ToLowerInvariant();
        string rest = low.StartsWith("https://", StringComparison.Ordinal) ? u.Substring(8) : (low.StartsWith("http://", StringComparison.Ordinal) ? u.Substring(7) : null);
        if (rest == null) return "";
        string host, port;
        return HostPort(rest.Substring(0, AutoritaetEnde(rest)), out host, out port) ? host : "";
    }

    // Unteranfrage (jedes Schema, auch ws:): Ziel auf diesem PC immer, im Heimnetz ohne Erlaubnis gesperrt.
    // Ein Name, der sich nicht lesen lässt, gilt als gesperrt.
    public static bool ZielGesperrt(string u, bool heimOk) {
        if (u == null) return true;
        int k = u.IndexOf("://", StringComparison.Ordinal);
        if (k < 0) return false;
        string rest = u.Substring(k + 3);
        string aut = rest.Substring(0, AutoritaetEnde(rest));
        int at = aut.LastIndexOf('@');
        if (at >= 0) aut = aut.Substring(at + 1);
        string host, port;
        if (!HostPort(aut, out host, out port)) return true;
        return IstLokal(host) || (IstHeimnetz(host) && !heimOk);
    }

    public static bool HostPort(string a, out string host, out string port) {
        host = "";
        port = "";
        if (a.StartsWith("[", StringComparison.Ordinal)) {
            int zu = a.IndexOf(']');
            if (zu < 0) return false;
            host = a.Substring(0, zu + 1).ToLowerInvariant();
            string hinten = a.Substring(zu + 1);
            if (hinten != "") {
                if (!hinten.StartsWith(":", StringComparison.Ordinal)) return false;
                port = hinten.Substring(1);
            }
            if (!V6Ok(host.Substring(1, host.Length - 2))) return false;
        } else {
            int k = a.IndexOf(':');
            if (k >= 0) { host = a.Substring(0, k).ToLowerInvariant(); port = a.Substring(k + 1); } else host = a.ToLowerInvariant();
            if (!NameOk(host)) return false;
        }
        if (port != "") {
            if (port.Length > 5) return false;
            foreach (char c in port) if (c < '0' || c > '9') return false;
            int p = int.Parse(port, CultureInfo.InvariantCulture);
            if (p < 1 || p > 65535) return false;
        }
        return true;
    }

    static bool NameOk(string h) {
        if (h.Length == 0 || h.Length > 253) return false;
        string t = h.Length > 1 && h.EndsWith(".", StringComparison.Ordinal) ? h.Substring(0, h.Length - 1) : h;
        foreach (string teil in t.Split('.')) {
            if (teil.Length == 0 || teil.Length > 63 || teil.StartsWith("-", StringComparison.Ordinal) || teil.EndsWith("-", StringComparison.Ordinal)) return false;
            foreach (char c in teil) if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
        }
        return true;
    }

    static bool V6Ok(string s) {
        if (s.Length < 2 || s.Length > 45) return false;
        foreach (char c in s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || c == ':' || c == '.')) return false;
        return s.IndexOf(':') >= 0 && V6Gruppen(s) != null;
    }

    // Die acht Gruppen einer IPv6-Adresse (ohne Klammern, klein geschrieben), null wenn sie so nicht gilt. Jede
    // Schreibweise derselben Adresse ergibt dieselben Gruppen; geprüft wird danach an den Zahlen, nie am Text
    // (am Text ließ sich „dieser PC“ umschreiben: 0:0::ffff:7f00:1 ist 127.0.0.1). Wie v6_gruppen in Uzai.
    public static int[] V6Gruppen(string s) {
        if (s.IndexOf('.') >= 0) {
            int k = s.LastIndexOf(':');
            if (k < 0) return null;
            string hinten = s.Substring(k + 1);
            if (hinten.EndsWith(".", StringComparison.Ordinal)) return null;
            int[] v4 = Ipv4(hinten);
            if (v4 == null) return null;
            s = s.Substring(0, k + 1) + (v4[0] * 256 + v4[1]).ToString("x", CultureInfo.InvariantCulture) + ":"
                + (v4[2] * 256 + v4[3]).ToString("x", CultureInfo.InvariantCulture);
        }
        int dd = s.IndexOf("::", StringComparison.Ordinal);
        if (dd >= 0 && s.IndexOf("::", dd + 1, StringComparison.Ordinal) >= 0) return null;
        int[] links, rechts;
        if (dd >= 0) {
            links = V6Teil(s.Substring(0, dd));
            rechts = V6Teil(s.Substring(dd + 2));
            // „::“ steht für mindestens eine Gruppe aus Nullen.
            if (links == null || rechts == null || links.Length + rechts.Length > 7) return null;
        } else {
            links = V6Teil(s);
            rechts = new int[0];
            if (links == null || links.Length != 8) return null;
        }
        var g = new int[8];
        for (int i = 0; i < links.Length; i++) g[i] = links[i];
        for (int i = 0; i < rechts.Length; i++) g[8 - rechts.Length + i] = rechts[i];
        return g;
    }

    // Gruppen eines Stücks ohne „::“ („1:2:3“), null wenn eine Gruppe nicht gilt.
    static int[] V6Teil(string t) {
        if (t.Length == 0) return new int[0];
        string[] p = t.Split(':');
        var o = new int[p.Length];
        for (int i = 0; i < p.Length; i++) {
            if (p[i].Length < 1 || p[i].Length > 4) return null;
            int v = 0;
            foreach (char c in p[i]) {
                int d = c >= '0' && c <= '9' ? c - '0' : (c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1);
                if (d < 0) return null;
                v = v * 16 + d;
            }
            o[i] = v;
        }
        return o;
    }

    static string OhnePunkt(string h) {
        return h.EndsWith(".", StringComparison.Ordinal) ? h.Substring(0, h.Length - 1) : h;
    }

    static bool NurZiffern(string s) {
        if (s.Length == 0) return false;
        foreach (char c in s) if (c < '0' || c > '9') return false;
        return true;
    }

    // IPv4 in üblicher Schreibweise, sonst null. Eine führende Null gilt nicht: Browser lesen „012“ als oktal (10) –
    // 012.0.0.1 ist dort das Heimnetz, als Dezimalzahl gelesen sähe es öffentlich aus.
    public static int[] Ipv4(string h) {
        string[] teile = OhnePunkt(h).Split('.');
        if (teile.Length != 4) return null;
        var o = new int[4];
        for (int i = 0; i < 4; i++) {
            if (teile[i].Length == 0 || teile[i].Length > 3 || !NurZiffern(teile[i])) return null;
            if (teile[i].Length > 1 && teile[i][0] == '0') return null;
            o[i] = int.Parse(teile[i], CultureInfo.InvariantCulture);
            if (o[i] > 255) return null;
        }
        return o;
    }

    static bool ZahlName(string h) {
        string t = OhnePunkt(h);
        string letzter = t.Substring(t.LastIndexOf('.') + 1);
        if (letzter.Length == 0) return false;
        if (NurZiffern(letzter)) return Ipv4(t) == null;
        if (!letzter.StartsWith("0x", StringComparison.Ordinal) || letzter.Length <= 2) return false;
        for (int i = 2; i < letzter.Length; i++) {
            char c = letzter[i];
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
        }
        return true;
    }

    public static bool IstLokal(string h) {
        string t = OhnePunkt(h);
        if (t == "localhost" || t.EndsWith(".localhost", StringComparison.Ordinal)) return true;
        if (ZahlName(t)) return true;
        int[] v4 = Ipv4(t);
        if (v4 != null) return v4[0] == 127 || v4[0] == 0;
        if (t.StartsWith("[", StringComparison.Ordinal)) {
            if (t.Length < 2) return true;
            string v6 = t.Substring(1, t.Length - 2);
            int[] g = V6Gruppen(v6);
            // Nicht lesbar, oder IPv4 in Punkten darin: vorsichtshalber dieser PC.
            if (g == null || v6.IndexOf('.') >= 0) return true;
            // Über einen NAT64-Übergang (64:ff9b::/96) erreichbare IPv4-Adressen: ebenso.
            if (g[0] == 0x64 && g[1] == 0xff9b) return true;
            // ::, ::1 und jede IPv4 in IPv6, in welcher Schreibweise auch immer: die ersten 80 Bit null, dann 0 oder ffff.
            return g[0] == 0 && g[1] == 0 && g[2] == 0 && g[3] == 0 && g[4] == 0 && (g[5] == 0 || g[5] == 0xffff);
        }
        return false;
    }

    public static bool IstHeimnetz(string h) {
        string t = OhnePunkt(h);
        int[] v4 = Ipv4(t);
        if (v4 != null) {
            int a = v4[0], b = v4[1];
            return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254) || (a == 100 && b >= 64 && b <= 127);
        }
        if (t.StartsWith("[", StringComparison.Ordinal)) {
            int[] g = t.Length < 2 ? null : V6Gruppen(t.Substring(1, t.Length - 2));
            if (g == null) return false;
            // fc00::/7 (privat), fe80::/10 (Verbindung), fec0::/10 (alte Standort-Adressen) – an der ersten Gruppe.
            return (g[0] & 0xfe00) == 0xfc00 || (g[0] & 0xffc0) == 0xfe80 || (g[0] & 0xffc0) == 0xfec0;
        }
        return t.IndexOf('.') < 0 || t.EndsWith(".local", StringComparison.Ordinal) || t.EndsWith(".lan", StringComparison.Ordinal)
            || t.EndsWith(".home.arpa", StringComparison.Ordinal) || t.EndsWith(".fritz.box", StringComparison.Ordinal) || t == "fritz.box";
    }

    // Text aus der Seite für Uzai: ohne Steuer-, Richtungs- und unsichtbare Zeichen, Leerraum zusammengefasst.
    public static string Sauber(string s, int max) {
        if (s == null) return "";
        if (s.Length > max * 4) s = s.Substring(0, max * 4);
        var sb = new StringBuilder();
        bool leer = false;
        for (int i = 0; i < s.Length; i++) {
            char c = s[i];
            if (char.IsHighSurrogate(c)) {
                if (i + 1 < s.Length && char.IsLowSurrogate(s[i + 1])) { sb.Append(c).Append(s[i + 1]); i++; leer = false; }
                continue;
            }
            if (char.IsLowSurrogate(c)) continue;
            if (c < 32 || c == 127 || (c >= 0x80 && c < 0xA0) || (c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E)
                || (c >= 0x2066 && c <= 0x2069) || c == 0xFEFF || c == 0x2028 || c == 0x2029 || (c >= 0xFFF9 && c <= 0xFFFB)) {
                if ((c == 9 || c == 10 || c == 13) && !leer) { sb.Append(' '); leer = true; }
                continue;
            }
            if (c == ' ') {
                if (leer) continue;
                leer = true;
            } else leer = false;
            sb.Append(c);
        }
        string t = sb.ToString().Trim(' ');
        if (t.Length > max) {
            int n = max;
            if (char.IsHighSurrogate(t[n - 1])) n--;
            t = t.Substring(0, n);
        }
        return t;
    }

    // Downloads nur in diesen Dateiarten (nie Programme, Skripte, Verknüpfungen, Installationspakete).
    static readonly string[] ERLAUBT = { "pdf", "txt", "csv", "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "mp3", "m4a", "aac", "flac",
        "ogg", "opus", "wav", "mp4", "m4v", "webm", "mkv", "mov", "srt", "vtt", "epub", "zip", "7z" };
    static readonly string[] RESERVIERT = { "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
        "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9" };

    public static bool DownloadOk(string name) {
        if (string.IsNullOrEmpty(name)) return false;
        int p = name.LastIndexOf('.');
        if (p <= 0 || p == name.Length - 1) return false;
        return Array.IndexOf(ERLAUBT, name.Substring(p + 1).ToLowerInvariant()) >= 0;
    }

    // Dateiname aus dem Vorschlag der Seite: nur der Name, ohne verbotene Zeichen, ohne Punkt/Leerzeichen
    // am Ende, keine reservierten Namen, höchstens 120 Zeichen.
    public static string Dateiname(string vorschlag) {
        string s = vorschlag ?? "";
        int k = Math.Max(s.LastIndexOf('\\'), s.LastIndexOf('/'));
        if (k >= 0) s = s.Substring(k + 1);
        var sb = new StringBuilder();
        foreach (char c in Sauber(s, 1000)) {
            if (c < 32 || "<>:\"/\\|?*".IndexOf(c) >= 0) continue;
            sb.Append(c);
        }
        string t = sb.ToString().TrimEnd('.', ' ').TrimStart(' ');
        if (t.Length > 120) {
            int p = t.LastIndexOf('.');
            string ext = p > 0 && t.Length - p <= 8 ? t.Substring(p) : "";
            t = t.Substring(0, 120 - ext.Length) + ext;
        }
        string stamm = t.IndexOf('.') >= 0 ? t.Substring(0, t.IndexOf('.')) : t;
        if (Array.IndexOf(RESERVIERT, stamm.ToLowerInvariant()) >= 0) t = "_" + t;
        return t.Length == 0 ? "download" : t;
    }
}
// --- Schema der Leitung (gleich wie src/core/browser_protokoll.gd) --------------------------------

public static class UzbSchema {
    public static readonly string[] ARTEN = { "link", "knopf", "feld", "wahl", "video", "bild", "reiter", "sonst", "rahmen" };
    public static readonly string[] BEREICHE = { "kopf", "navigation", "inhalt", "seite", "fuss", "dialog", "sonst" };
    public static readonly string[] TASTEN = { "enter", "tab", "umschalt_tab", "escape", "backspace", "links", "rechts", "hoch", "runter",
        "seite_hoch", "seite_runter", "pos1", "ende", "leer" };
    public static readonly string[] VIDEO = { "umschalten", "pause", "spielen", "vor", "zurueck", "vollbild", "vor_lang", "zurueck_lang", "lauter",
        "leiser", "stumm", "tempo_auf", "tempo_ab", "untertitel" };
    public static readonly string[] FELDER = { "text", "suche", "email", "zahl", "passwort", "url", "tel", "bereich" };
    public static readonly string[] FRAGEN = { "kamera", "mikrofon", "standort", "bestaetigen" };
    public static readonly string[] SPERREN = { "protokoll", "laenge", "zeichen", "anmeldung", "name", "lokal", "heimnetz", "popup", "app",
        "zertifikat", "anmeldedialog", "download", "nur_spotify" };
    public static readonly string[] FEHLER = { "webview2", "pruefung", "start", "absturz", "tabs", "kern", "kern_api", "kern_signatur", "kern_pfad",
        "kern_sandbox", "kern_installer" };
    public static readonly string[] DOWNLOAD = { "laeuft", "fertig", "gesperrt", "fehler" };
    public static readonly string[] COOKIES = { "", "abgelehnt", "versteckt", "aus" };
    public static readonly string[] KERN_STAND = { "laedt", "fertig", "fehler", "stand", "update", "diagnose", "info" };
    public static readonly string[] KERN_AKTION = { "diagnose", "update", "gesund" };
    public const int MAX_PUNKTE = 60;
    public const int MAX_OPTIONEN = 400;
    public const int MAX_ZIELE = 800;
    public const int MAX_ABSAETZE = 200;
    public const int MAX_BEFEHL = 16384;
    public const int MAX_EREIGNIS = 786432;
    // Spotify-Sitzung: Abfragen in der Seite (UzcSpotify im Kern, src/core/browser_protokoll.gd spotify_abfrage_grund).
    public static readonly string[] SPOTIFY_ZIELE = { "pathfinder", "spclient", "webapi" };
    public static readonly string[] SPOTIFY_METHODEN = { "GET", "POST", "PUT" };
    public static readonly string[] SPOTIFY_GRUENDE = { "", "zeit", "netz", "gross", "ziel", "welt", "schluessel", "voll" };
    public const int MAX_PFAD = 2048;
    public const int MAX_INHALT = 12000;
    public const int MAX_ANTWORT = 2097152;   // Text einer Spotify-Antwort (Zeichen)
    public const int MAX_ZEILE = 6291456;     // nur „spotify-antwort“ darf länger sein als MAX_EREIGNIS (Bytes)

    const string TAB = "int:1:1000000";
    const string ID = "int:1:1000000000";

    // Uzai → Wirt. Je Feld „name=regel“, Regeln: int:min:max, bool, text:max, wahl:<liste>, url.
    public static readonly Dictionary<string, string[]> BEFEHLE = new Dictionary<string, string[]> {
        { "fenster", new[] { "x=int:-32768:32768", "y=int:-32768:32768", "w=int:100:16384", "h=int:100:16384" } },
        { "zeigen", new[] { "an=bool" } },
        { "tab-neu", new[] { "url=url", "privat=bool", "vorn=bool", "nutzer=bool" } },
        { "tab-zu", new[] { "tab=" + TAB } },
        { "tab-wahl", new[] { "tab=" + TAB } },
        { "laden", new[] { "tab=" + TAB, "url=url", "nutzer=bool" } },
        { "zurueck", new[] { "tab=" + TAB } },
        { "vor", new[] { "tab=" + TAB } },
        { "neu", new[] { "tab=" + TAB } },
        { "stopp", new[] { "tab=" + TAB } },
        { "zoom", new[] { "tab=" + TAB, "prozent=int:25:300" } },
        { "rollen", new[] { "tab=" + TAB, "vx=int:-30000:30000", "vy=int:-30000:30000" } },
        { "karte", new[] { "tab=" + TAB } },
        { "fokus", new[] { "tab=" + TAB, "id=" + ID } },
        { "aktivieren", new[] { "tab=" + TAB, "id=" + ID, "neu=bool" } },
        { "link", new[] { "tab=" + TAB, "id=" + ID } },
        { "feld", new[] { "tab=" + TAB, "id=" + ID } },
        { "text", new[] { "tab=" + TAB, "id=" + ID, "text=text:2000" } },
        { "taste", new[] { "tab=" + TAB, "taste=wahl:tasten" } },
        { "klick", new[] { "tab=" + TAB, "x=int:0:100000", "y=int:0:100000" } },
        { "zeiger", new[] { "tab=" + TAB, "x=int:0:100000", "y=int:0:100000" } },
        { "rad", new[] { "tab=" + TAB, "x=int:0:100000", "y=int:0:100000", "dy=int:-5000:5000" } },
        { "video", new[] { "tab=" + TAB, "aktion=wahl:video" } },
        { "vorschau", new[] { "tab=" + TAB } },
        { "lesen", new[] { "tab=" + TAB } },
        { "antwort", new[] { "frage=" + ID, "ja=bool" } },
        { "gliederung", new[] { "tab=" + TAB } },
        { "springe", new[] { "tab=" + TAB, "id=" + ID } },
        { "wahl", new[] { "tab=" + TAB, "id=" + ID } },
        { "wahl-setzen", new[] { "tab=" + TAB, "id=" + ID, "index=int:0:399" } },
        { "feld-weiter", new[] { "tab=" + TAB, "id=" + ID, "richtung=int:-1:1" } },
        { "suche", new[] { "tab=" + TAB, "text=text:200" } },
        { "suche-weiter", new[] { "tab=" + TAB, "richtung=int:-1:1" } },
        { "blocker", new[] { "tab=" + TAB, "an=bool" } },
        { "blocker-liste", new[] { "hosts=optionen" } },
        { "kern", new[] { "aktion=wahl:kern_aktion" } },
        { "spotify-abfrage", new[] { "id=" + ID, "ziel=wahl:spotify_ziele", "methode=wahl:spotify_methoden", "pfad=pfad:2048", "inhalt=json:12000",
            "verbindung=schluessel:512", "zeit=int:1000:30000" } },
        { "ende", new string[0] },
    };

    // Wirt → Uzai.
    public static readonly Dictionary<string, string[]> EREIGNISSE = new Dictionary<string, string[]> {
        { "bereit", new[] { "version=text:96" } },
        { "fehler", new[] { "code=wahl:fehler" } },
        { "tab", new[] { "tab=" + TAB, "url=seite", "titel=text:300", "laedt=bool", "zurueck=bool", "vor=bool", "zoom=int:25:300", "privat=bool", "aktiv=bool" } },
        { "tab-zu", new[] { "tab=" + TAB } },
        { "karte", new[] { "tab=" + TAB, "vw=int:1:20000", "vh=int:1:20000", "sy=int:0:10000000", "sh=int:0:10000000", "ziele=ziele" } },
        { "ziel", new[] { "tab=" + TAB, "id=" + ID, "x=int:-100000:100000", "y=int:-100000:100000", "w=int:1:20000", "h=int:1:20000" } },
        { "feld", new[] { "tab=" + TAB, "id=" + ID, "typ=wahl:felder", "wert=text:2000" } },
        { "link", new[] { "tab=" + TAB, "id=" + ID, "url=url_fremd" } },
        { "video", new[] { "tab=" + TAB, "da=bool", "laeuft=bool", "zeit=int:0:1000000", "dauer=int:0:1000000", "voll=bool", "laut=int:0:100", "stumm=bool",
            "tempo=int:25:400", "untertitel=int:-1:1" } },
        { "frage", new[] { "frage=" + ID, "art=wahl:fragen", "herkunft=text:253", "text=text:300" } },
        { "meldung", new[] { "tab=" + TAB, "herkunft=text:253", "text=text:300" } },
        { "download", new[] { "name=text:120", "stand=wahl:download" } },
        { "gesperrt", new[] { "tab=int:0:1000000", "grund=wahl:sperren" } },
        { "vorschau", new[] { "tab=" + TAB, "datei=datei" } },
        { "lesen", new[] { "tab=" + TAB, "titel=text:300", "absaetze=absaetze" } },
        { "vollbild", new[] { "tab=" + TAB, "an=bool" } },
        { "absturz", new[] { "tab=" + TAB } },
        { "gliederung", new[] { "tab=" + TAB, "punkte=punkte" } },
        { "wahl", new[] { "tab=" + TAB, "id=" + ID, "optionen=optionen", "aktuell=int:-1:399" } },
        { "formular", new[] { "tab=" + TAB, "id=" + ID, "index=int:0:999", "anzahl=int:0:999", "ende=bool" } },
        { "suche", new[] { "tab=" + TAB, "treffer=int:0:100000", "aktuell=int:0:100000" } },
        { "blocker", new[] { "tab=" + TAB, "anzahl=int:0:1000000", "versteckt=int:0:1000000", "cookies=wahl:cookies" } },
        { "kern", new[] { "stand=wahl:kern_stand", "schritt=text:32", "prozent=int:0:100", "fassung=text:64", "text=text:3000" } },
        // Spotify-Sitzung: Schlüssel aus den Anfragen der Seite (nur der Kern meldet das, nie das Sprung-Skript).
        { "spotify", new[] { "token=schluessel:2048", "client=schluessel:2048", "version=schluessel:40" } },
        // Antwort auf „spotify-abfrage“: code 0 = keine Antwort (grund sagt warum); text roh, Uzai liest ihn nur als JSON.
        { "spotify-antwort", new[] { "id=" + ID, "code=int:0:999", "grund=wahl:spotify_gruende", "text=roh:2097152", "gekuerzt=bool", "warte=int:0:86400" } },
    };

    // Was das Sprung-Skript melden darf (ohne „tab“, den setzt der Wirt); klick und oeffnen bleiben im Wirt.
    public static readonly Dictionary<string, string[]> VOM_SKRIPT = new Dictionary<string, string[]> {
        { "hallo", new string[0] },
        { "karte", new[] { "vw=int:1:20000", "vh=int:1:20000", "sy=int:0:10000000", "sh=int:0:10000000", "ziele=ziele" } },
        { "ziel", new[] { "id=" + ID, "x=int:-100000:100000", "y=int:-100000:100000", "w=int:1:20000", "h=int:1:20000" } },
        { "feld", new[] { "id=" + ID, "typ=wahl:felder", "wert=text:2000" } },
        { "link", new[] { "id=" + ID, "url=url_fremd" } },
        { "video", new[] { "da=bool", "laeuft=bool", "zeit=int:0:1000000", "dauer=int:0:1000000", "voll=bool", "laut=int:0:100", "stumm=bool", "tempo=int:25:400",
            "untertitel=int:-1:1" } },
        { "lesen", new[] { "titel=text:300", "absaetze=absaetze" } },
        { "klick", new[] { "x=int:0:100000", "y=int:0:100000" } },
        { "zeiger", new[] { "x=int:0:100000", "y=int:0:100000" } },
        { "oeffnen", new[] { "url=url_fremd" } },
        { "gliederung", new[] { "punkte=punkte" } },
        { "wahl", new[] { "id=" + ID, "optionen=optionen", "aktuell=int:-1:399" } },
        { "formular", new[] { "id=" + ID, "index=int:0:999", "anzahl=int:0:999", "ende=bool" } },
        { "suche", new[] { "treffer=int:0:100000", "aktuell=int:0:100000" } },
        { "blocker", new[] { "versteckt=int:0:1000000", "cookies=wahl:cookies" } },
    };

    static readonly Regex DATEI = new Regex("^tab-[0-9]{1,7}\\.jpg\\z", RegexOptions.CultureInvariant);

    public static readonly string[] SPCLIENT_PFADE = { "/connect-state/v1/", "/context-resolve/v1/", "/recently-played/v3/" };
    public static readonly string[] PUT_PFADE = { "/connect-state/v1/devices/", "/connect-state/v1/connect/volume/" };
    public const string PATHFINDER_PFAD = "/pathfinder/v2/query";
    static readonly Regex OPERATION = new Regex("^[A-Za-z][A-Za-z0-9_]{0,63}\\z",
        RegexOptions.CultureInvariant);
    static readonly Regex HASH = new Regex("^[0-9a-f]{64}\\z",
        RegexOptions.CultureInvariant);

    static bool BeginntMit(string p, string[] liste) {
        foreach (string v in liste) if (p.StartsWith(v, StringComparison.Ordinal)) return true;
        return false;
    }

    // Spotify-Abfrage: "" = darf in der Seite laufen, sonst "ziel" (wie spotify_abfrage_grund in browser_protokoll.gd).
    public static string SpotifyAbfrageGrund(string ziel, string methode, string pfad, string inhalt, string verbindung) {
        if (Array.IndexOf(SPOTIFY_ZIELE, ziel) < 0 || Array.IndexOf(SPOTIFY_METHODEN, methode) < 0) return "ziel";
        if (!PfadOk(pfad, MAX_PFAD) || inhalt == null || inhalt.Length > MAX_INHALT) return "ziel";
        if (!SchluesselOkLeer(verbindung, 512)) return "ziel";
        Dictionary<string, object> body = null;
        if (inhalt.Length > 0) {
            body = UzbJson.Lesen(inhalt) as Dictionary<string, object>;
            if (body == null) return "ziel";
        }
        if (methode == "GET" && body != null) return "ziel";
        bool connect = pfad.StartsWith("/connect-state/v1/", StringComparison.Ordinal);
        if (verbindung.Length > 0 && !(ziel == "spclient" && connect)) return "ziel";
        if (ziel == "pathfinder") {
            if (methode != "POST" || pfad != PATHFINDER_PFAD || body == null) return "ziel";
            object op, ext, vars;
            if (!body.TryGetValue("operationName", out op) || !(op is string) || !OPERATION.IsMatch((string)op)) return "ziel";
            if (!body.TryGetValue("variables", out vars) || !(vars is Dictionary<string, object>)) return "ziel";
            var e = body.TryGetValue("extensions", out ext) ? ext as Dictionary<string, object> : null;
            object pq, h;
            var pqd = e != null && e.TryGetValue("persistedQuery", out pq) ? pq as Dictionary<string, object> : null;
            if (pqd == null || !pqd.TryGetValue("sha256Hash", out h) || !(h is string) || !HASH.IsMatch((string)h)) return "ziel";
            return "";
        }
        if (ziel == "spclient") {
            if (!BeginntMit(pfad, SPCLIENT_PFADE)) return "ziel";
            if (methode == "PUT" && !BeginntMit(pfad, PUT_PFADE)) return "ziel";
            if (methode == "POST" && !connect) return "ziel";
            return "";
        }
        if (methode == "PUT" || !pfad.StartsWith("/v1/", StringComparison.Ordinal)) return "ziel";
        return "";
    }

    public static Dictionary<string, object> Befehl(object roh) {
        var b = Pruefe(roh, BEFEHLE, true);
        if (b != null && (string)b["t"] == "spotify-abfrage"
            && SpotifyAbfrageGrund((string)b["ziel"], (string)b["methode"], (string)b["pfad"], (string)b["inhalt"], (string)b["verbindung"]) != "") return null;
        return b;
    }
    public static Dictionary<string, object> Ereignis(object roh) { return Pruefe(roh, EREIGNISSE, false); }
    public static Dictionary<string, object> Skript(object roh) { return Pruefe(roh, VOM_SKRIPT, false); }

    public static Dictionary<string, object> Pruefe(object roh, Dictionary<string, string[]> schema, bool befehlSeite) {
        var m = roh as Dictionary<string, object>;
        if (m == null) return null;
        object art;
        if (!m.TryGetValue("t", out art) || !(art is string) || !schema.ContainsKey((string)art)) return null;
        var o = new Dictionary<string, object>();
        o["t"] = art;
        foreach (string regel in schema[(string)art]) {
            int eq = regel.IndexOf('=');
            string name = regel.Substring(0, eq);
            object v;
            if (!m.TryGetValue(name, out v)) return null;
            object w = Wert(v, regel.Substring(eq + 1), befehlSeite, m);
            if (w == null) return null;
            o[name] = w;
        }
        return o;
    }

    static string[] Liste(string n) {
        switch (n) {
            case "tasten": return TASTEN;
            case "video": return VIDEO;
            case "felder": return FELDER;
            case "fragen": return FRAGEN;
            case "sperren": return SPERREN;
            case "fehler": return FEHLER;
            case "download": return DOWNLOAD;
            case "cookies": return COOKIES;
            case "kern_stand": return KERN_STAND;
            case "kern_aktion": return KERN_AKTION;
            case "spotify_ziele": return SPOTIFY_ZIELE;
            case "spotify_methoden": return SPOTIFY_METHODEN;
            case "spotify_gruende": return SPOTIFY_GRUENDE;
        }
        return new string[0];
    }

    static bool Ganz(object v, long lo, long hi, out int o) {
        o = 0;
        if (!(v is double)) {
            if (v is int) v = (double)(int)v;
            else if (v is long) v = (double)(long)v;
            else return false;
        }
        double d = (double)v;
        if (double.IsNaN(d) || double.IsInfinity(d) || d != Math.Floor(d) || d < lo || d > hi) return false;
        o = (int)d;
        return true;
    }

    static object Wert(object v, string regel, bool befehlSeite, Dictionary<string, object> m) {
        string[] r = regel.Split(':');
        switch (r[0]) {
            case "int": {
                int o;
                return Ganz(v, long.Parse(r[1], CultureInfo.InvariantCulture), long.Parse(r[2], CultureInfo.InvariantCulture), out o) ? (object)o : null;
            }
            case "bool":
                return v is bool ? v : null;
            case "text": {
                var s = v as string;
                int max = int.Parse(r[1], CultureInfo.InvariantCulture);
                return s != null && s.Length <= max ? UzbRegeln.Sauber(s, max) : null;
            }
            case "wahl": {
                var s = v as string;
                return s != null && Array.IndexOf(Liste(r[1]), s) >= 0 ? s : null;
            }
            case "url": {
                var s = v as string;
                object n;
                bool nutzer = befehlSeite && m.TryGetValue("nutzer", out n) && n is bool && (bool)n;
                return s != null && UzbRegeln.UrlGrund(s, nutzer) == "" ? s : null;
            }
            case "url_fremd": {
                var s = v as string;
                return s != null && UzbRegeln.UrlGrund(s, true) == "" ? s : null;
            }
            case "seite": {
                var s = v as string;
                return s != null && s.Length <= UzbRegeln.MAX_URL && (s == "about:blank" || UzbRegeln.UrlGrund(s, true) == "") ? s : null;
            }
            case "datei": {
                var s = v as string;
                return s != null && DATEI.IsMatch(s) ? s : null;
            }
            case "schluessel": {
                // Base64 bzw. Base64url, leer erlaubt: nur A–Z a–z 0–9 - _ . + / =
                var s = v as string;
                int max = int.Parse(r[1], CultureInfo.InvariantCulture);
                return s != null && (s.Length == 0 || SchluesselOk(s, max)) ? s : null;
            }
            case "pfad": {
                var s = v as string;
                return s != null && PfadOk(s, int.Parse(r[1], CultureInfo.InvariantCulture)) ? s : null;
            }
            case "json": {
                // Inhalt einer Abfrage: leer oder ein JSON-Objekt; weiter geht er neu geschrieben (nichts Fremdes durch).
                var s = v as string;
                if (s == null || s.Length > int.Parse(r[1], CultureInfo.InvariantCulture)) return null;
                if (s.Length == 0) return s;
                var o = UzbJson.Lesen(s) as Dictionary<string, object>;
                return o == null ? null : UzbJson.Schreiben(o);
            }
            case "roh": {
                var s = v as string;
                return s != null && s.Length <= int.Parse(r[1], CultureInfo.InvariantCulture) ? s : null;
            }
            case "ziele":
                return Ziele(v);
            case "punkte":
                return Punkte(v);
            case "optionen": {
                var l = v as List<object>;
                if (l == null || l.Count > MAX_OPTIONEN) return null;
                var o = new List<object>();
                foreach (object a in l) {
                    var s = a as string;
                    if (s == null || s.Length > 120) return null;
                    o.Add(UzbRegeln.Sauber(s, 120));
                }
                return o;
            }
            case "absaetze": {
                var l = v as List<object>;
                if (l == null || l.Count > MAX_ABSAETZE) return null;
                var o = new List<object>();
                foreach (object a in l) {
                    var s = a as string;
                    if (s == null || s.Length > 3000) return null;
                    string t = UzbRegeln.Sauber(s, 3000);
                    if (t != "") o.Add(t);
                }
                return o;
            }
        }
        return null;
    }

    // Pfad einer Spotify-Abfrage: „/“ vorn, nur A–Z a–z 0–9 und - . _ ~ % / ? & = , : +, kein „..“ und kein „//“.
    public static bool PfadOk(string p, int max) {
        if (p == null || p.Length < 2 || p.Length > max || p[0] != '/' || p.Contains("..") || p.Contains("//")) return false;
        foreach (char c in p) {
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) continue;
            if ("-._~%/?&=,:+".IndexOf(c) >= 0) continue;
            return false;
        }
        return true;
    }

    public static bool SchluesselOkLeer(string s, int max) { return s != null && (s.Length == 0 || SchluesselOk(s, max)); }

    static bool SchluesselOk(string s, int max) {
        if (s.Length > max) return false;
        foreach (char c in s) {
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) continue;
            if (c == '-' || c == '_' || c == '.' || c == '+' || c == '/' || c == '=') continue;
            return false;
        }
        return true;
    }

    static readonly long[,] GRENZEN = { { 1, 1000000000 }, { -100000, 100000 }, { -100000, 100000 }, { 1, 20000 }, { 1, 20000 }, { 0, 8 }, { 0, 6 } };

    // Gliederung: höchstens MAX_PUNKTE, je [id, y (Seiten-Koordinate), stufe 1–6, text ≤ 80].
    static object Punkte(object v) {
        var l = v as List<object>;
        if (l == null || l.Count > MAX_PUNKTE) return null;
        var o = new List<object>();
        foreach (object z in l) {
            var e = z as List<object>;
            if (e == null || e.Count != 4) return null;
            int id, y, stufe;
            if (!Ganz(e[0], 1, 1000000000, out id) || !Ganz(e[1], 0, 10000000, out y) || !Ganz(e[2], 0, 6, out stufe)) return null;
            var s = e[3] as string;
            if (s == null || s.Length > 80) return null;
            o.Add(new List<object> { id, y, stufe, UzbRegeln.Sauber(s, 80) });
        }
        return o;
    }

    static object Ziele(object v) {
        var l = v as List<object>;
        if (l == null || l.Count > MAX_ZIELE) return null;
        var o = new List<object>();
        foreach (object z in l) {
            var e = z as List<object>;
            if (e == null || e.Count != 7) return null;
            var zeile = new List<object>();
            for (int i = 0; i < 7; i++) {
                int n;
                if (!Ganz(e[i], GRENZEN[i, 0], GRENZEN[i, 1], out n)) return null;
                zeile.Add(n);
            }
            o.Add(zeile);
        }
        return o;
    }
}
// --- Ausgabe an Uzai: eine geprüfte JSON-Zeile je Ereignis ---------------------------------------

public sealed class UzbAusgabe {
    readonly Stream aus;
    readonly object sperre = new object();
    public int Verworfen;

    public UzbAusgabe(Stream s) { aus = s; }

    readonly HashSet<string> verworfeneArten = new HashSet<string>(StringComparer.Ordinal);

    public bool Senden(Dictionary<string, object> e) {
        var ok = UzbSchema.Ereignis(e);
        if (ok == null) { Verworfen++; Melden(e); return false; }
        string line = UzbJson.Schreiben(ok);
        byte[] b = new UTF8Encoding(false).GetBytes(line + "\n");
        if (b.Length > ((string)ok["t"] == "spotify-antwort" ? UzbSchema.MAX_ZEILE : UzbSchema.MAX_EREIGNIS)) { Verworfen++; return false; }
        lock (sperre) {
            try { aus.Write(b, 0, b.Length); aus.Flush(); return true; } catch (IOException) { return false; }
        }
    }

    // Ein Ereignis passte nicht ins Schema (0.16.36: „bereit“ mit zu langer Fassung – Uzai wartete vergeblich):
    // je Art einmal als kern-Ereignis „info“ melden, nur die Art, nie der Inhalt.
    void Melden(Dictionary<string, object> e) {
        object t;
        string art = e != null && e.TryGetValue("t", out t) && t is string ? (string)t : "?";
        if (art == "kern" || art.Length > 20) return;
        lock (verworfeneArten) {
            if (verworfeneArten.Count >= 20 || !verworfeneArten.Add(art)) return;
        }
        var d = new Dictionary<string, object>();
        d["t"] = "kern";
        d["stand"] = "info";
        d["schritt"] = "verworfen";
        d["prozent"] = 0;
        d["fassung"] = "";
        d["text"] = "Ereignis verworfen (Schema): " + art;
        Senden(d);
    }

    public void Fehler(string code) {
        var d = new Dictionary<string, object>();
        d["t"] = "fehler";
        d["code"] = code;
        Senden(d);
    }
}
// --- Eingabe von Uzai: Zeilen mit Längengrenze, in eigenem Faden ---------------------------------

public sealed class UzbEingabe {
    public static void Lesen(Stream ein, Action<Dictionary<string, object>> befehl, Action ende) {
        var t = new Thread(delegate () {
            var utf8 = new UTF8Encoding(false, true);
            var zeile = new MemoryStream();
            var buf = new byte[8192];
            bool zuLang = false;
            int kaputt = 0;
            try {
                while (true) {
                    int n = ein.Read(buf, 0, buf.Length);
                    if (n <= 0) break;
                    for (int i = 0; i < n; i++) {
                        byte c = buf[i];
                        if (c != 10) {
                            if (!zuLang && zeile.Length < UzbSchema.MAX_BEFEHL) zeile.WriteByte(c);
                            else { zuLang = true; zeile.SetLength(0); }
                            continue;
                        }
                        if (!zuLang && zeile.Length > 0) {
                            Dictionary<string, object> b = null;
                            try { b = UzbSchema.Befehl(UzbJson.Lesen(utf8.GetString(zeile.ToArray()))); } catch (DecoderFallbackException) { b = null; }
                            if (b != null) befehl(b); else kaputt++;
                        } else if (zuLang) kaputt++;
                        zuLang = false;
                        zeile.SetLength(0);
                        // Wer die Leitung mit Unsinn flutet, ist nicht Uzai: aufhören.
                        if (kaputt > 200) { ende(); return; }
                    }
                }
            } catch (IOException) { }
            ende();
        });
        t.IsBackground = true;
        t.Start();
    }
}
// --- Fenster (Win32, ohne WinForms): randlos, nie aktiv, ohne Taskleiste ---------------------------

public sealed class UzbFenster {
    delegate IntPtr WndProcD(IntPtr h, uint m, IntPtr w, IntPtr l);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASSEX {
        public uint cbSize; public uint style; public WndProcD lpfnWndProc; public int cbClsExtra; public int cbWndExtra; public IntPtr hInstance;
        public IntPtr hIcon; public IntPtr hCursor; public IntPtr hbrBackground; public string lpszMenuName; public string lpszClassName; public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassExW(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateWindowExW(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr p);
    [DllImport("user32.dll")] static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern int GetMessageW(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessageW(ref MSG m);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern void PostQuitMessage(int code);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string n);
    [DllImport("gdi32.dll")] static extern IntPtr CreateSolidBrush(uint rgb);

    const uint WM_DESTROY = 0x0002, WM_SIZE = 0x0005, WM_CLOSE = 0x0010, WM_MOUSEACTIVATE = 0x0021, WM_COPYDATA = 0x004A, WM_APP_ARBEIT = 0x8001;
    const uint WS_POPUP = 0x80000000, WS_CLIPCHILDREN = 0x02000000, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x00000080;
    const uint SWP_NOACTIVATE = 0x0010, SWP_NOZORDER = 0x0004;

    static WndProcD proc;          // muss leben, solange das Fenster lebt
    readonly Queue<Action> arbeit = new Queue<Action>();
    int faden;
    public IntPtr Hwnd;
    public int Breite, Hoehe;
    public Action<int, int> Groesse;
    public Action Schliessen;
    // WM_COPYDATA (Fortschritt des CEF-Installers): bekommt (wParam, lParam), gibt den Rückgabewert.
    public Func<IntPtr, IntPtr, IntPtr> CopyData;

    public bool AufUiFaden { get { return Thread.CurrentThread.ManagedThreadId == faden; } }

    public bool Erstellen(int x, int y, int w, int h) {
        faden = Thread.CurrentThread.ManagedThreadId;
        proc = Proc;
        var wc = new WNDCLASSEX();
        wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
        wc.lpfnWndProc = proc;
        wc.hInstance = GetModuleHandleW(null);
        wc.hbrBackground = CreateSolidBrush(0x000D0B0B);
        wc.lpszClassName = "UzaiBrowserWirt";
        if (RegisterClassExW(ref wc) == 0) return false;
        Breite = w;
        Hoehe = h;
        Hwnd = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, wc.lpszClassName, "Uzai Browser", WS_POPUP | WS_CLIPCHILDREN, x, y, w, h,
            IntPtr.Zero, IntPtr.Zero, wc.hInstance, IntPtr.Zero);
        return Hwnd != IntPtr.Zero;
    }

    public void Post(Action a) {
        lock (arbeit) arbeit.Enqueue(a);
        PostMessageW(Hwnd, WM_APP_ARBEIT, IntPtr.Zero, IntPtr.Zero);
    }

    public void Zeigen(bool an) { ShowWindow(Hwnd, an ? 4 : 0); }   // SW_SHOWNOACTIVATE bzw. SW_HIDE

    public void Lage(int x, int y, int w, int h) { SetWindowPos(Hwnd, IntPtr.Zero, x, y, w, h, SWP_NOACTIVATE | SWP_NOZORDER); }

    public void Schleife() {
        MSG m;
        while (GetMessageW(out m, IntPtr.Zero, 0, 0) > 0) {
            TranslateMessage(ref m);
            DispatchMessageW(ref m);
        }
    }

    public void Ende() { DestroyWindow(Hwnd); }

    IntPtr Proc(IntPtr h, uint msg, IntPtr w, IntPtr l) {
        if (msg == WM_APP_ARBEIT) {
            while (true) {
                Action a;
                lock (arbeit) {
                    if (arbeit.Count == 0) break;
                    a = arbeit.Dequeue();
                }
                try { a(); } catch (Exception) { /* ein Fehler einer Seite beendet nicht den Wirt */ }
            }
            return IntPtr.Zero;
        }
        if (msg == WM_SIZE) {
            long v = l.ToInt64();
            Breite = (int)(v & 0xFFFF);
            Hoehe = (int)((v >> 16) & 0xFFFF);
            if (Groesse != null) Groesse(Breite, Hoehe);
            return IntPtr.Zero;
        }
        if (msg == WM_COPYDATA && CopyData != null) {
            try { return CopyData(w, l); } catch (Exception) { return IntPtr.Zero; }
        }
        if (msg == WM_MOUSEACTIVATE) return new IntPtr(3);   // MA_NOACTIVATE: ein Klick holt den Wirt nie nach vorn
        if (msg == WM_CLOSE) { if (Schliessen != null) Schliessen(); return IntPtr.Zero; }
        if (msg == WM_DESTROY) { PostQuitMessage(0); return IntPtr.Zero; }
        return DefWindowProcW(h, msg, w, l);
    }
}
// Fortsetzungen nach await laufen auf dem Faden des Fensters (WebView2 verlangt das).
public sealed class UzbKontext : SynchronizationContext {
    readonly UzbFenster f;
    public UzbKontext(UzbFenster f) { this.f = f; }
    public override void Post(SendOrPostCallback d, object state) { f.Post(delegate () { d(state); }); }
    public override void Send(SendOrPostCallback d, object state) {
        if (f.AufUiFaden) { d(state); return; }
        using (var fertig = new ManualResetEvent(false)) {
            f.Post(delegate () { try { d(state); } finally { fertig.Set(); } });
            fertig.WaitOne();
        }
    }
    public override SynchronizationContext CreateCopy() { return this; }
}

// --- Signaturen (Authenticode) – für den Kern: libcef.dll muss vom CEF-Zertifikat signiert sein -------

public static class UzbSignatur {
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

    // Signatur gültig (ohne Online-Sperrprüfung, damit es auch offline geht)?
    public static bool Gueltig(string datei) {
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
            wd.dwProvFlags = 0x10;       // WTD_CACHE_ONLY_URL_RETRIEVAL
            return WinVerifyTrust(IntPtr.Zero, GENERIC_VERIFY_V2, ref wd) == 0;
        } finally {
            Marshal.DestroyStructure(pfi, typeof(WINTRUST_FILE_INFO));
            Marshal.FreeHGlobal(pfi);
        }
    }

    // SHA-1-Fingerabdruck des Signaturzertifikats (40 Zeichen, Großbuchstaben) oder "".
    public static string Fingerabdruck(string datei) {
        try {
            var cert = new System.Security.Cryptography.X509Certificates.X509Certificate2(
                System.Security.Cryptography.X509Certificates.X509Certificate.CreateFromSignedFile(datei));
            return (cert.Thumbprint ?? "").ToUpperInvariant();
        } catch (Exception) {
            return "";
        }
    }

    // Gültig signiert und genau von diesem Zertifikat?
    public static bool Von(string datei, string fingerabdruck) {
        return Gueltig(datei) && Fingerabdruck(datei) == fingerabdruck;
    }
}

// --- Werbe- und Tracker-Blocker: Regeln als Daten (assets/browser/filter, tools/filter_bauen.py) ----------
//
// Dateiformat (Text oder gz, eine Regel je Zeile, erstes Zeichen = Art; gleich in src/core/browser_filter.gd):
//   d <domäne>                      Anfragen an diese Domäne und ihre Unterdomänen sperren
//   t <domäne>                      … nur, wenn die Seite eine andere Domäne ist (dritte Partei)
//   p <muster>|<flags>|<seiten>     Adressmuster (||Anker, ^ Trenner, * beliebig, | Anfang/Ende); flags: 3 nur dritte
//                                   Partei, 1 nur erste, Typbuchstaben s i c x f m o F p O (Skript, Bild, Stil, XHR,
//                                   Rahmen, Medien, Objekt, Schrift, Ping, Sonstiges), ~ davor: alle außer diesen;
//                                   seiten: nur auf diesen Seiten (Komma, ~ nimmt aus)
//   a <muster>|<flags>|<seiten>     Ausnahme: so eine Anfrage wird nie gesperrt
//   h <selektor>                    überall verstecken (Kosmetik)
//   s <seiten>|<selektor>           nur auf diesen Seiten verstecken
//   e <seiten>|<selektor>           dort nicht verstecken
// Regeln können nur sperren und verstecken – nie Code. Hauptdokumente werden nie gesperrt.

public sealed class UzbFilter {
    public const int MAX_ZEILEN = 400000;
    public const int MAX_ZEILE = 600;
    public const long MAX_BYTES = 16 * 1024 * 1024;
    public const int MAX_SELEKTOREN = 24000;

    sealed class Muster {
        public string Text;            // ohne Anker, klein geschrieben
        public string Lit = "";        // längstes Stück ohne * und ^: muss wörtlich in der Adresse stehen (Vorprüfung)
        public int LitPos = -1;
        public bool LitFrei;           // kein Stern vor dem Stück: der Anfang des Musters steht damit fest
        public bool HostAnker, Anfang, Ende;
        public bool NurDritte, NurErste;
        public string Typen = "";      // Buchstaben; leer = alle
        public bool TypenNegiert;
        public string[] Seiten = new string[0];
        public string[] SeitenNicht = new string[0];
    }

    readonly HashSet<string> domaenen = new HashSet<string>(StringComparer.Ordinal);
    readonly HashSet<string> dritte = new HashSet<string>(StringComparer.Ordinal);
    readonly Dictionary<string, List<Muster>> index = new Dictionary<string, List<Muster>>(StringComparer.Ordinal);
    readonly List<Muster> rest = new List<Muster>();
    readonly Dictionary<string, List<Muster>> ausIndex = new Dictionary<string, List<Muster>>(StringComparer.Ordinal);
    readonly List<Muster> ausRest = new List<Muster>();
    readonly List<string> verstecken = new List<string>();
    readonly Dictionary<string, List<string>> versteckenSeiten = new Dictionary<string, List<string>>(StringComparer.Ordinal);
    readonly Dictionary<string, HashSet<string>> versteckenAusnahmen = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
    public int Regeln;

    // Ressourcenart von CEF (cef_resource_type_t) als Typbuchstabe.
    public static char Typ(int art) {
        switch (art) {
            case 1: return 'f';
            case 2: return 'c';
            case 3: return 's';
            case 4: return 'i';
            case 5: return 'F';
            case 7: return 'o';
            case 8: return 'm';
            case 13: return 'x';
            case 14: return 'p';
        }
        return 'O';
    }

    public static UzbFilter Laden(string pfad) {
        var f = new UzbFilter();
        var info = new FileInfo(pfad);
        if (!info.Exists || info.Length > MAX_BYTES) return f;
        using (var roh = File.OpenRead(pfad)) {
            Stream s = roh;
            int b0 = roh.ReadByte(), b1 = roh.ReadByte();
            roh.Position = 0;
            if (b0 == 0x1f && b1 == 0x8b) s = new GZipStream(roh, CompressionMode.Decompress);
            using (var r = new StreamReader(s, new UTF8Encoding(false, false))) {
                string zeile;
                long gelesen = 0;
                while ((zeile = r.ReadLine()) != null) {
                    gelesen += zeile.Length + 1;
                    if (gelesen > MAX_BYTES || f.Regeln > MAX_ZEILEN) break;
                    if (zeile.Length < 3 || zeile.Length > MAX_ZEILE || zeile[1] != ' ') continue;
                    if (f.Zeile(zeile[0], zeile.Substring(2))) f.Regeln++;
                }
            }
        }
        return f;
    }

    // Eine Zeile aus Text (für Tests) – gleiche Prüfung wie beim Laden.
    public bool Zeile(char art, string rest) {
        switch (art) {
            case 'd': return DomaeneOk(rest) && domaenen.Add(rest);
            case 't': return DomaeneOk(rest) && dritte.Add(rest);
            case 'p': case 'a': {
                var m = MusterLesen(rest);
                if (m == null) return false;
                Eintragen(m, art == 'a' ? ausIndex : index, art == 'a' ? ausRest : this.rest);
                return true;
            }
            case 'h':
                if (!SelektorOk(rest) || verstecken.Count >= MAX_SELEKTOREN) return false;
                verstecken.Add(rest);
                return true;
            case 's': case 'e': {
                int k = rest.IndexOf('|');
                if (k <= 0 || k == rest.Length - 1) return false;
                string sel = rest.Substring(k + 1);
                if (!SelektorOk(sel)) return false;
                foreach (string d in rest.Substring(0, k).Split(',')) {
                    string dd = d.Trim();
                    if (!DomaeneOk(dd)) continue;
                    if (art == 's') {
                        List<string> l;
                        if (!versteckenSeiten.TryGetValue(dd, out l)) versteckenSeiten[dd] = l = new List<string>();
                        if (l.Count < 2000) l.Add(sel);
                    } else {
                        HashSet<string> h;
                        if (!versteckenAusnahmen.TryGetValue(dd, out h)) versteckenAusnahmen[dd] = h = new HashSet<string>(StringComparer.Ordinal);
                        h.Add(sel);
                    }
                }
                return true;
            }
        }
        return false;
    }

    static bool DomaeneOk(string d) {
        if (d.Length < 3 || d.Length > 253 || d.IndexOf('.') < 0) return false;
        foreach (char c in d) if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_')) return false;
        return true;
    }

    // Selektoren sind nur CSS: keine geschweiften Klammern, kein Semikolon, kein Kommentar, keine Adressen.
    public static bool SelektorOk(string s) {
        if (s.Length < 2 || s.Length > 300) return false;
        foreach (char c in s) if (c == '{' || c == '}' || c == ';' || c < 32 || c == '\\' || c == '/') return false;
        return s.IndexOf("url(", StringComparison.OrdinalIgnoreCase) < 0 && s.IndexOf("expression", StringComparison.OrdinalIgnoreCase) < 0
            && s.IndexOf(":has(", StringComparison.Ordinal) < 0 && s.IndexOf("-abp-", StringComparison.Ordinal) < 0;
    }

    static Muster MusterLesen(string rest) {
        string[] teile = rest.Split('|');
        // Das Muster selbst darf „|“ als Anker enthalten – darum von hinten zerlegen: … |flags|seiten.
        string seiten = "", flags = "", text = rest;
        if (teile.Length >= 3) {
            seiten = teile[teile.Length - 1];
            flags = teile[teile.Length - 2];
            text = rest.Substring(0, rest.Length - seiten.Length - flags.Length - 2);
        } else if (teile.Length == 2) {
            flags = teile[1];
            text = teile[0];
        }
        if (text.Length < 2 || text.Length > 300) return null;
        var m = new Muster();
        if (text.StartsWith("||", StringComparison.Ordinal)) { m.HostAnker = true; text = text.Substring(2); }
        else if (text.StartsWith("|", StringComparison.Ordinal)) { m.Anfang = true; text = text.Substring(1); }
        if (text.EndsWith("|", StringComparison.Ordinal)) { m.Ende = true; text = text.Substring(0, text.Length - 1); }
        text = text.ToLowerInvariant();
        foreach (char c in text) if (c <= 32 || c > 126) return null;
        if (text.Length == 0 || text.Trim('*').Length < 2) return null;
        m.Text = text;
        m.Lit = Literal(text);
        m.LitPos = m.Lit.Length > 0 ? text.IndexOf(m.Lit, StringComparison.Ordinal) : -1;
        int stern = text.IndexOf('*');
        m.LitFrei = m.Lit.Length > 0 && (stern < 0 || stern > m.LitPos);
        foreach (char c in flags) {
            if (c == '3') m.NurDritte = true;
            else if (c == '1') m.NurErste = true;
            else if (c == '~') m.TypenNegiert = true;
            else if ("sicxfmoFpO".IndexOf(c) >= 0) m.Typen += c;
            else return null;
        }
        if (seiten != "") {
            var ja = new List<string>();
            var nein = new List<string>();
            foreach (string d in seiten.Split(',')) {
                if (d.StartsWith("~", StringComparison.Ordinal)) { if (DomaeneOk(d.Substring(1))) nein.Add(d.Substring(1)); }
                else if (DomaeneOk(d)) ja.Add(d);
            }
            m.Seiten = ja.ToArray();
            m.SeitenNicht = nein.ToArray();
        }
        return m;
    }

    void Eintragen(Muster m, Dictionary<string, List<Muster>> idx, List<Muster> sonst) {
        string token = BestesToken(m.Text);
        if (token == null) { if (sonst.Count < 5000) sonst.Add(m); return; }
        List<Muster> l;
        if (!idx.TryGetValue(token, out l)) idx[token] = l = new List<Muster>();
        l.Add(m);
    }

    // Längster Lauf aus a–z0–9 (mindestens 4 Zeichen), der in jeder passenden Adresse vorkommen muss.
    static string BestesToken(string text) {
        string best = null;
        int i = 0;
        while (i < text.Length) {
            int j = i;
            while (j < text.Length && ((text[j] >= 'a' && text[j] <= 'z') || (text[j] >= '0' && text[j] <= '9'))) j++;
            // Nur ein Lauf, der im Muster beidseitig begrenzt ist (nicht am Anfang/Ende, nicht neben *): sonst könnte
            // die Adresse einen längeren Lauf haben („/adserver“ trifft auch „/adservers/“).
            if (j - i >= 4 && (best == null || j - i > best.Length) && i > 0 && j < text.Length && text[i - 1] != '*' && text[j] != '*')
                best = text.Substring(i, j - i);
            i = j + 1;
        }
        return best;
    }

    // --- Entscheidung ---------------------------------------------------------------------------------

    public static string HostVon(string url) {
        if (url == null) return "";
        int k = url.IndexOf("://", StringComparison.Ordinal);
        if (k < 0) return "";
        int a = k + 3;
        int e = a;
        while (e < url.Length && url[e] != '/' && url[e] != '?' && url[e] != '#') e++;
        string aut = url.Substring(a, e - a);
        int at = aut.LastIndexOf('@');
        if (at >= 0) aut = aut.Substring(at + 1);
        if (aut.StartsWith("[", StringComparison.Ordinal)) { int z = aut.IndexOf(']'); return z > 0 ? aut.Substring(0, z + 1).ToLowerInvariant() : ""; }
        int p = aut.IndexOf(':');
        if (p >= 0) aut = aut.Substring(0, p);
        return aut.ToLowerInvariant().TrimEnd('.');
    }

    static readonly string[] ZWEISTUFIG = { "co.uk", "org.uk", "gov.uk", "ac.uk", "me.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp", "ne.jp",
        "or.jp", "com.br", "com.mx", "com.ar", "co.za", "com.tr", "co.in", "co.kr", "com.cn", "com.tw", "com.hk", "com.sg", "co.il", "com.pl" };

    // Registrierbare Domäne (grob): letzte zwei Teile, bei bekannten Endungen drei.
    public static string Site(string host) {
        string[] t = host.Split('.');
        if (t.Length <= 2) return host;
        string zwei = t[t.Length - 2] + "." + t[t.Length - 1];
        return Array.IndexOf(ZWEISTUFIG, zwei) >= 0 ? t[t.Length - 3] + "." + zwei : zwei;
    }

    static bool InListe(string host, HashSet<string> liste) {
        string h = host;
        while (true) {
            if (liste.Contains(h)) return true;
            int p = h.IndexOf('.');
            if (p < 0) return false;
            h = h.Substring(p + 1);
        }
    }

    static bool SeiteTrifft(string seite, string[] liste) {
        foreach (string d in liste) if (seite == d || seite.EndsWith("." + d, StringComparison.Ordinal)) return true;
        return false;
    }

    // Soll diese Anfrage gesperrt werden? art = cef_resource_type_t, seite = Name der Seite (erste Partei).
    public bool Gesperrt(string url, int art, string seite) {
        if (art == 0 || art == 19 || url == null || url.Length > 8192) return false;   // nie das Hauptdokument
        string host = HostVon(url);
        if (host == "") return false;
        string low = url.ToLowerInvariant();
        string seiteLow = (seite ?? "").ToLowerInvariant();
        bool dritte = seiteLow == "" || Site(host) != Site(seiteLow);
        char typ = Typ(art);
        if (Trifft(low, host, dritte, typ, seiteLow, ausIndex, ausRest)) return false;
        if (InListe(host, domaenen)) return true;
        if (dritte && InListe(host, this.dritte)) return true;
        return Trifft(low, host, dritte, typ, seiteLow, index, rest);
    }

    bool Trifft(string low, string host, bool dritte, char typ, string seite, Dictionary<string, List<Muster>> idx, List<Muster> sonst) {
        foreach (Muster m in sonst) if (Passt(m, low, host, dritte, typ, seite)) return true;
        int i = 0;
        var gesehen = new HashSet<string>(StringComparer.Ordinal);
        while (i < low.Length) {
            int j = i;
            while (j < low.Length && ((low[j] >= 'a' && low[j] <= 'z') || (low[j] >= '0' && low[j] <= '9'))) j++;
            if (j - i >= 4) {
                string tok = low.Substring(i, j - i);
                List<Muster> l;
                if (gesehen.Add(tok) && idx.TryGetValue(tok, out l)) {
                    foreach (Muster m in l) if (Passt(m, low, host, dritte, typ, seite)) return true;
                }
            }
            i = j + 1;
        }
        return false;
    }

    static bool Passt(Muster m, string low, string host, bool dritte, char typ, string seite) {
        if (m.NurDritte && !dritte) return false;
        if (m.NurErste && dritte) return false;
        if (m.Typen.Length > 0) {
            bool drin = m.Typen.IndexOf(typ) >= 0;
            if (m.TypenNegiert ? drin : !drin) return false;
        }
        if (m.Seiten.Length > 0 && !SeiteTrifft(seite, m.Seiten)) return false;
        if (m.SeitenNicht.Length > 0 && SeiteTrifft(seite, m.SeitenNicht)) return false;
        if (m.Lit.Length > 0 && low.IndexOf(m.Lit, StringComparison.Ordinal) < 0) return false;
        if (m.HostAnker) {
            int k = low.IndexOf("://", StringComparison.Ordinal);
            if (k < 0) return false;
            int a = k + 3;
            int hostEnde = a;
            while (hostEnde < low.Length && low[hostEnde] != '/' && low[hostEnde] != '?' && low[hostEnde] != '#') hostEnde++;
            // Beginn am Anfang des Namens oder nach einem Punkt darin.
            for (int p = a; p <= hostEnde; p++) {
                if (p != a && low[p - 1] != '.') continue;
                if (p > a && p >= hostEnde) break;
                if (Glob(m.Text, 0, low, p, m.Ende)) return true;
            }
            return false;
        }
        if (m.Anfang) return Glob(m.Text, 0, low, 0, m.Ende);
        if (m.Lit.Length == 0) {
            for (int p = 0; p <= low.Length - 1; p++) {
                if (m.Text[0] != '*' && m.Text[0] != '^' && low[p] != m.Text[0]) continue;
                if (Glob(m.Text, 0, low, p, m.Ende)) return true;
            }
            return false;
        }
        int s = 0;
        while (true) {
            int k = low.IndexOf(m.Lit, s, StringComparison.Ordinal);
            if (k < 0) return false;
            int start = k - m.LitPos;
            if (m.LitFrei) {
                if (start >= 0 && Glob(m.Text, 0, low, start, m.Ende)) return true;
            } else {
                // Stern vor dem Stück: jeder Anfang bis dorthin kommt infrage (der Stern findet spätere Stellen selbst).
                for (int p = 0; p <= Math.Max(start, 0); p++) if (Glob(m.Text, 0, low, p, m.Ende)) return true;
                return false;
            }
            s = k + 1;
        }
    }

    // Das längste Stück eines Musters ohne * und ^ (mindestens 2 Zeichen), "" wenn keins.
    static string Literal(string text) {
        string best = "";
        int i = 0;
        while (i < text.Length) {
            int j = i;
            while (j < text.Length && text[j] != '*' && text[j] != '^') j++;
            if (j - i >= 2 && j - i > best.Length) best = text.Substring(i, j - i);
            i = j + 1;
        }
        return best;
    }

    static bool Trenner(char c) {
        return !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == '%');
    }

    // Muster mit * (beliebig) und ^ (Trenner oder Ende) gegen den Text ab Stelle t; ende: muss am Ende aufhören.
    static bool Glob(string muster, int mi, string text, int ti, bool ende) {
        int sternM = -1, sternT = -1;
        while (true) {
            if (mi == muster.Length) {
                if (!ende || ti == text.Length) return true;
            } else {
                char c = muster[mi];
                if (c == '*') { sternM = mi++; sternT = ti; continue; }
                if (ti < text.Length && (c == text[ti] || (c == '^' && Trenner(text[ti])))) { mi++; ti++; continue; }
                if (c == '^' && ti == text.Length) { mi++; continue; }
            }
            if (sternM < 0) return false;
            if (sternT >= text.Length) return false;
            mi = sternM + 1;
            ti = ++sternT;
        }
    }

    // Selektoren, die auf dieser Seite versteckt werden (allgemeine ohne die Ausnahmen der Seite, dazu die eigenen).
    public List<string> Kosmetik(string seite) {
        var aus = new List<string>();
        string s = (seite ?? "").ToLowerInvariant();
        var ausnahmen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var kv in versteckenAusnahmen) if (s == kv.Key || s.EndsWith("." + kv.Key, StringComparison.Ordinal)) ausnahmen.UnionWith(kv.Value);
        foreach (string sel in verstecken) if (!ausnahmen.Contains(sel)) aus.Add(sel);
        foreach (var kv in versteckenSeiten) {
            if (s == kv.Key || s.EndsWith("." + kv.Key, StringComparison.Ordinal)) foreach (string sel in kv.Value) if (!ausnahmen.Contains(sel)) aus.Add(sel);
        }
        if (aus.Count > MAX_SELEKTOREN) aus.RemoveRange(MAX_SELEKTOREN, aus.Count - MAX_SELEKTOREN);
        return aus;
    }
}
