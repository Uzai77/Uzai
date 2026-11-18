# Prüft den Browser-Wirt (helper/uzai-browser-wirt.cs, Wunschliste 120, docs/SECURITY.md „Uzai-Browser“)
# unter Linux mit PowerShell 7: Die Quelle muss als C# 5 ohne Warnungen gegen die echte
# Microsoft.Web.WebView2.Core.dll übersetzbar sein; Adressen-Regeln mit derselben Tabelle wie Uzai
# (tests/fixtures/browser_urls.json); Schema beider Richtungen mit denselben Beispielen
# (tests/fixtures/browser_protokoll.json); JSON-Leser (Tiefe, Doppel, Steuerzeichen, Schreiben);
# Unteranfragen (auch ws:); Downloads (Erlaubnisliste, Dateinamen); Startargumente; Zeilen der Leitung
# (Länge, Kaputtes, Flut); Ausgabe nur nach Schema; feste Sicherheits-Einstellungen im Quelltext;
# Prüfsummen der WebView2-Dateien überall gleich; der Helfer-Befehl „browser-bauen“.
# Nur am Windows-PC: WebView2 selbst, Fenster, Signaturprüfung (WinVerifyTrust), Übersetzen mit
# Windows PowerShell 5.
#   pwsh -NoProfile -File tests/browser_cs.ps1 helper/uzai-browser-wirt.cs →  „Ergebnis: alles ok“
$wirt = $args[0]
$root = Split-Path -Parent (Split-Path -Parent (Resolve-Path $wirt))
# Der Helfer übersetzt den Wirt zusammen mit den gemeinsamen Teilen (helper/uzai-browser-gemeinsam.cs) – hier genauso
# (zwei Quelldateien, eine Übersetzung). Die Quelltext-Prüfungen unten sehen beide Dateien.
$gemeinsam = Join-Path $root 'helper/uzai-browser-gemeinsam.cs'
$src = (Get-Content -Raw $gemeinsam) + "`n" + (Get-Content -Raw $wirt)
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

$core = Join-Path $root 'assets/browser/webview2/Microsoft.Web.WebView2.Core.dll'
$ref = Join-Path $PSHOME 'ref'
$refs = @($core) + @('mscorlib.dll', 'System.Collections.dll', 'System.Runtime.dll', 'System.Drawing.dll', 'System.Drawing.Primitives.dll',
    'System.Text.RegularExpressions.dll', 'System.Security.Cryptography.dll', 'System.Security.Cryptography.X509Certificates.dll',
    'System.Threading.dll', 'System.Threading.Thread.dll', 'System.Console.dll', 'System.Runtime.InteropServices.dll', 'System.Linq.dll',
    'System.Collections.NonGeneric.dll', 'System.Runtime.Extensions.dll', 'netstandard.dll', 'System.Threading.Timer.dll',
    'System.IO.FileSystem.dll', 'System.Text.Encoding.Extensions.dll', 'System.IO.Compression.dll', 'System.Security.Cryptography.Algorithms.dll',
    'System.Security.Cryptography.Primitives.dll' | ForEach-Object { Join-Path $ref $_ } | Where-Object { Test-Path $_ })
# Nur für diese Probe: die Leitung in einem Faden lesen lassen und sammeln, was ankommt.
$testCs = @'
public static class UzbProbeLeitung {
    public static string Lauf(byte[] daten) {
        var q = new System.Collections.Generic.List<string>();
        var fertig = new System.Threading.ManualResetEvent(false);
        UzbEingabe.Lesen(new System.IO.MemoryStream(daten), delegate (System.Collections.Generic.Dictionary<string, object> b) {
            lock (q) q.Add((string)b["t"]);
        }, delegate () { fertig.Set(); });
        bool ok = fertig.WaitOne(5000);
        lock (q) return string.Join(",", q.ToArray()) + (ok ? "|ende" : "|offen");
    }
}
'@
$probeDatei = Join-Path ([IO.Path]::GetTempPath()) ("uzai-browser-probe-" + $PID + ".cs")
[IO.File]::WriteAllText($probeDatei, $testCs, (New-Object Text.UTF8Encoding $false))
try {
    Add-Type -Path @($gemeinsam, (Resolve-Path $wirt).Path, $probeDatei) -ReferencedAssemblies $refs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "übersetzt gegen die echte WebView2-DLL (C# 5, Warnungen als Fehler)"
} catch {
    Check $false ("übersetzt: " + $_.Exception.Message)
    Remove-Item -LiteralPath $probeDatei -ErrorAction SilentlyContinue
    "Ergebnis: $fails Fehler"
    exit 1
}
Remove-Item -LiteralPath $probeDatei -ErrorAction SilentlyContinue

# --- Adressen: gleiche Tabelle wie Uzai ------------------------------------------------------------
$urls = Get-Content -Raw (Join-Path $root 'tests/fixtures/browser_urls.json') | ConvertFrom-Json -NoEnumerate
$falsch = @()
foreach ($z in $urls) {
    $g = [UzbRegeln]::UrlGrund([string]$z[0], [bool]$z[1])
    if ($g -ne [string]$z[2]) { $falsch += ("{0} ({1}): {2} statt {3}" -f ([string]$z[0]).Substring(0, [Math]::Min(60, ([string]$z[0]).Length)), $z[1], $g, $z[2]) }
}
Check ($urls.Count -gt 40 -and $falsch.Count -eq 0) ("Adressen: gleiches Urteil wie Uzai " + ($falsch -join '; '))
Check ([UzbRegeln]::Host('https://WWW.Example.com:8443/a') -eq 'www.example.com') "Name einer Adresse"

# --- Schema: gleiche Beispiele wie Uzai ---------------------------------------------------------
$pro = Get-Content -Raw (Join-Path $root 'tests/fixtures/browser_protokoll.json') | ConvertFrom-Json
$falsch = @()
foreach ($z in $pro.befehle) {
    $ok = $null -ne [UzbSchema]::Befehl([UzbJson]::Lesen([string]$z[0]))
    if ($ok -ne [bool]$z[1]) { $falsch += ([string]$z[0]).Substring(0, [Math]::Min(80, ([string]$z[0]).Length)) }
}
Check ($falsch.Count -eq 0) ("Befehle: gleiches Urteil wie Uzai " + ($falsch -join ' | '))
$falsch = @()
foreach ($z in $pro.ereignisse) {
    $ok = $null -ne [UzbSchema]::Ereignis([UzbJson]::Lesen([string]$z[0]))
    if ($ok -ne [bool]$z[1]) { $falsch += ([string]$z[0]).Substring(0, [Math]::Min(80, ([string]$z[0]).Length)) }
}
Check ($falsch.Count -eq 0) ("Ereignisse: gleiches Urteil wie Uzai " + ($falsch -join ' | '))
$b = [UzbSchema]::Befehl([UzbJson]::Lesen('{"t":"laden","tab":1,"url":"https://a.de/","nutzer":true,"boese":"x"}'))
Check ($null -ne $b -and -not $b.ContainsKey('boese') -and $b['tab'] -is [int]) "fremde Felder fallen weg, Zahlen als int"
$s = [UzbSchema]::Skript([UzbJson]::Lesen('{"t":"karte","vw":1280,"vh":720,"sy":0,"sh":900,"ziele":[[1,2,3,4,5,0,2]]}'))
Check ($null -ne $s -and -not $s.ContainsKey('tab')) "Meldung des Sprung-Skripts: Karte ohne Tab"
Check ($null -eq [UzbSchema]::Skript([UzbJson]::Lesen('{"t":"tab","tab":1}'))) "Sprung-Skript darf keinen Tab-Stand melden"
Check ($null -eq [UzbSchema]::Skript([UzbJson]::Lesen('{"t":"oeffnen","url":"http://127.0.0.1/"}'))) "Sprung-Skript: nie ein Tab auf diesen PC"
Check ($null -ne [UzbSchema]::Skript([UzbJson]::Lesen('{"t":"klick","x":10,"y":20}'))) "Klickpunkt des Sprung-Skripts"
Check ($null -eq [UzbSchema]::Skript([UzbJson]::Lesen('{"t":"klick","x":-10,"y":20}'))) "Klickpunkt außerhalb verworfen"

# --- JSON ---------------------------------------------------------------------------------------
Check ($null -eq [UzbJson]::Lesen(('[' * 12) + (']' * 12))) "zu tief verschachtelt: verworfen"
Check ($null -ne [UzbJson]::Lesen(('[' * 8) + (']' * 8))) "Tiefe 8 geht"
Check ($null -eq [UzbJson]::Lesen('{"a":1,"a":2}')) "doppelte Schlüssel: verworfen"
Check ($null -eq [UzbJson]::Lesen("{`"a`":`"x`ny`"}")) "Steuerzeichen im Text: verworfen"
Check ($null -eq [UzbJson]::Lesen('{"a":1} x')) "Rest hinter dem Wert: verworfen"
Check ($null -eq [UzbJson]::Lesen('{"a":01x}')) "kaputte Zahl: verworfen"
Check ($null -eq [UzbJson]::Lesen('{"a":1e999}')) "unendliche Zahl: verworfen"
Check ([UzbJson]::Lesen('null') -eq [UzbJson]::NICHTS) "null ist kein Fehler"
$d = [Collections.Generic.Dictionary[string, object]]::new()
$d['t'] = "a`"b\c`u{2028}`u{1}"
$j = [UzbJson]::Schreiben($d)
Check ($j -eq '{"t":"a\"b\\c\u2028\u0001"}') "Schreiben maskiert Anführungszeichen, Rückstrich, U+2028, Steuerzeichen"
$back = [UzbJson]::Lesen($j)
Check ($back['t'] -eq $d['t']) "Hin und zurück gleich"
Check ([UzbRegeln]::Sauber("A`u{202e}B`u{200b}C`nD`u{7}", 10) -eq 'ABC D') "Text: Richtungs-, unsichtbare und Steuerzeichen raus"
Check ([UzbRegeln]::Sauber(('x' * 500), 20).Length -eq 20) "Text gekürzt"
Check ([UzbRegeln]::Sauber(('a' * 19) + [char]::ConvertFromUtf32(0x1F600), 20).Length -eq 19) "kein halbes Zeichen am Ende"

# --- Unteranfragen ------------------------------------------------------------------------------
Check ([UzbRegeln]::ZielGesperrt('ws://127.0.0.1:47811/x', $true)) "WebSocket auf diesen PC: gesperrt"
Check ([UzbRegeln]::ZielGesperrt('http://user@localhost/', $true)) "mit Anmeldung auf diesen PC: gesperrt"
Check (-not [UzbRegeln]::ZielGesperrt('wss://example.com/', $false)) "WebSocket ins Internet: frei"
Check ([UzbRegeln]::ZielGesperrt('http://192.168.1.1/api', $false)) "Heimnetz von einer Seite im Internet: gesperrt"
Check (-not [UzbRegeln]::ZielGesperrt('http://192.168.1.1/api', $true)) "Heimnetz von einer Seite im Heimnetz: frei"
Check ([UzbRegeln]::ZielGesperrt('http://[::1]:8080/', $true)) "IPv6 auf diesen PC: gesperrt"
Check ([UzbRegeln]::ZielGesperrt('http://exa%mple/', $false)) "unlesbarer Name: gesperrt"

# --- Downloads ----------------------------------------------------------------------------------
foreach ($n in @('rechnung.pdf', 'Foto.JPG', 'film.mkv', 'paket.zip')) { Check ([UzbRegeln]::DownloadOk($n)) "Download erlaubt: $n" }
foreach ($n in @('setup.exe', 'x.pdf.exe', 'x.msi', 'x.msix', 'x.bat', 'x.cmd', 'x.ps1', 'x.vbs', 'x.js', 'x.lnk', 'x.scr', 'x.hta', 'x.jar', 'x.reg',
        'x.appinstaller', 'x.url', 'x.iso', 'x', '.pdf', 'x.')) { Check (-not [UzbRegeln]::DownloadOk($n)) "Download gesperrt: $n" }
Check ([UzbRegeln]::Dateiname('..\..\Windows\evil.pdf') -eq 'evil.pdf') "Dateiname ohne Pfad"
Check ([UzbRegeln]::Dateiname('a:b.pdf') -eq 'ab.pdf') "kein Doppelpunkt (kein Datenstrom)"
Check ([UzbRegeln]::Dateiname('x.pdf. . ') -eq 'x.pdf') "kein Punkt oder Leerzeichen am Ende"
Check ([UzbRegeln]::Dateiname('con.pdf') -eq '_con.pdf') "reservierter Name"
Check ([UzbRegeln]::Dateiname("rech`u{202e}fdp.exe") -eq 'rechfdp.exe' -and -not [UzbRegeln]::DownloadOk([UzbRegeln]::Dateiname("rech`u{202e}fdp.exe"))) "Richtungszeichen-Trick: gesperrt"
Check ([UzbRegeln]::Dateiname(('a' * 300) + '.pdf').Length -le 120 -and [UzbRegeln]::Dateiname(('a' * 300) + '.pdf').EndsWith('.pdf')) "langer Name gekürzt, Endung bleibt"
Check ([UzbRegeln]::Dateiname('') -eq 'download') "leerer Name"

# --- Startargumente -----------------------------------------------------------------------------
$p = ''; $l = ''
Check ([UzbStart]::Argumente(@('--uzai-wirt', '--profil=standard', '--sprache=de-DE'), [ref]$p, [ref]$l) -and $p -eq 'standard') "Startargumente"
Check (-not [UzbStart]::Argumente(@('--uzai-wirt', '--profil=../x', '--sprache=de-DE'), [ref]$p, [ref]$l)) "Profil mit ../: abgelehnt"
Check (-not [UzbStart]::Argumente(@('--uzai-wirt', '--profil=a', '--sprache=de-DE', '--remote-debugging-port=9222'), [ref]$p, [ref]$l)) "zusätzliches Argument: abgelehnt"
Check (-not [UzbStart]::Argumente(@('--uzai-wirt', '--profil=a', '--sprache=fr-FR'), [ref]$p, [ref]$l)) "andere Sprache: abgelehnt"
Check (-not [UzbStart]::Argumente(@(), [ref]$p, [ref]$l)) "ohne Argumente: abgelehnt"

# --- Leitung: Zeilen von Uzai -------------------------------------------------------------------
$zeilen = '{"t":"zeigen","an":true}' + "`n" + 'kaputt' + "`n" + ('{"t":"text","tab":1,"id":1,"text":"' + ('x' * 20000) + '"}') + "`n" +
    '{"t":"laden","tab":1,"url":"file:///C:/","nutzer":true}' + "`n" + '{"t":"ende"}' + "`n"
$r = [UzbProbeLeitung]::Lauf([Text.Encoding]::UTF8.GetBytes($zeilen))
Check ($r -eq 'zeigen,ende|ende') "Leitung: nur gültige Befehle kommen durch (zu lang, kaputt, file: verworfen) [$r]"
$r = [UzbProbeLeitung]::Lauf([Text.Encoding]::UTF8.GetBytes(("x`n" * 300) + '{"t":"ende"}' + "`n"))
Check ($r -eq '|ende') "Flut aus Unsinn: Leitung zu, nichts kommt durch [$r]"
$r = [UzbProbeLeitung]::Lauf([byte[]](@(0x7b, 0x22, 0x74, 0x22, 0x3a, 0x22, 0xff, 0xfe, 0x22, 0x7d, 0x0a) + [Text.Encoding]::UTF8.GetBytes('{"t":"ende"}' + "`n")))
Check ($r -eq 'ende|ende') "kaputtes UTF-8: verworfen [$r]"

# --- Ausgabe nur nach Schema --------------------------------------------------------------------
$ms = [IO.MemoryStream]::new()
$aus = [UzbAusgabe]::new($ms)
$e = [Collections.Generic.Dictionary[string, object]]::new(); $e['t'] = 'gesperrt'; $e['tab'] = 1; $e['grund'] = 'lokal'
$e2 = [Collections.Generic.Dictionary[string, object]]::new(); $e2['t'] = 'gesperrt'; $e2['tab'] = 1; $e2['grund'] = 'alles'
$e3 = [Collections.Generic.Dictionary[string, object]]::new(); $e3['t'] = 'eval'
$r1 = $aus.Senden($e); $r2 = $aus.Senden($e2); $r3 = $aus.Senden($e3)
$text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
$r4 = $aus.Senden($e2)
$text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
$soll = '{"t":"gesperrt","tab":1,"grund":"lokal"}' + "`n" + '{"t":"kern","stand":"info","schritt":"verworfen","prozent":0,"fassung":"","text":"Ereignis verworfen (Schema): gesperrt"}' + "`n" +
    '{"t":"kern","stand":"info","schritt":"verworfen","prozent":0,"fassung":"","text":"Ereignis verworfen (Schema): eval"}' + "`n"
Check ($r1 -and -not $r2 -and -not $r3 -and -not $r4 -and $text -eq $soll -and $aus.Verworfen -eq 3) "Ausgabe: nur, was ins Schema passt; Verworfenes je Art einmal gemeldet (nur die Art)"

# --- Feste Sicherheits-Einstellungen im Quelltext --------------------------------------------------
foreach ($muss in @('AreDevToolsEnabled = false', 'AreHostObjectsAllowed = false', 'IsWebMessageEnabled = false', 'AreDefaultContextMenusEnabled = false',
        'IsPasswordAutosaveEnabled = false', 'IsGeneralAutofillEnabled = false', 'IsReputationCheckingRequired = true',
        'PreferredTrackingPreventionLevel = CoreWebView2TrackingPreventionLevel.Strict', 'AllowSingleSignOnUsingOSPrimaryAccount = false',
        'AreBrowserExtensionsEnabled = false', 'IsCustomCrashReportingEnabled = true', 'EnableTrackingPrevention = true',
        'LaunchingExternalUriScheme += delegate', 'ScreenCaptureStarting += delegate', 'ServerCertificateErrorAction.Cancel',
        'BasicAuthenticationRequested += delegate', 'SaveAsUIShowing += delegate', 'SaveFileSecurityCheckStarting += delegate',
        'IsInPrivateModeEnabled = privat', '"worldName"', '"executionContextName"', 'SetLoaderDllFolderPath(basis)', 'UmgebungLeeren()',
        'HandlesSchliessen()', 'UzbStart.Erhoeht()', 'UzbPruefung.Dateien(basis)', 'MethodImplOptions.NoInlining', 'WS_EX_NOACTIVATE',
        'a.SavesInProfile = false', 'if (!a.IsUserInitiated) { Gesperrt(t.Id, "popup")')) {
    Check ($src.Contains($muss)) "Quelltext: $muss"
}
foreach ($nie in @('AddHostObjectToScript', 'ExecuteScriptAsync', 'PostWebMessage', 'Process.Start', 'UseShellExecute', 'remote-debugging',
        'OpenDevToolsWindow', 'SetForegroundWindow', 'SendInput', 'keybd_event', 'AlwaysAllow', 'CoreWebView2PermissionState.Allow;')) {
    Check (-not $src.Contains($nie)) "Quelltext ohne $nie"
}
Check (([regex]::Matches($src, 'CoreWebView2PermissionState\.Allow')).Count -eq 1) "Erlauben nur an einer Stelle (nach deiner Antwort)"

# --- Prüfsummen und Helfer ------------------------------------------------------------------------
$lizenz = Get-Content -Raw (Join-Path $root 'assets/browser/webview2/LIZENZ.txt')
$helfer = Get-Content -Raw (Join-Path $root 'helper/uzai-helper.ps1')
$gd = Get-Content -Raw (Join-Path $root 'src/core/browser_wirt.gd')
foreach ($n in @(@('Microsoft.Web.WebView2.Core.dll', [UzbPruefung]::CORE_SHA256), @('WebView2Loader.dll', [UzbPruefung]::LOADER_SHA256))) {
    $ist = (Get-FileHash -Algorithm SHA256 (Join-Path $root ('assets/browser/webview2/' + $n[0]))).Hash.ToLowerInvariant()
    Check ($ist -eq $n[1]) ("{0}: Prüfsumme der Datei" -f $n[0])
    Check ($lizenz.Contains($n[1]) -and $helfer.Contains($n[1]) -and $gd.Contains($n[1])) ("{0}: gleiche Prüfsumme in LIZENZ, Helfer und Uzai" -f $n[0])
}
Check ($helfer.Contains("'browser-bauen' { return (Browser-Bauen) }")) "Helfer kennt browser-bauen"
$fn = [regex]::Match($helfer, '(?s)function Browser-Bauen \{.*?\n\}').Value
Check ($fn.Contains('[UzElev]::IsElevated($PID)') -and $fn.Contains('Browser-DateienOk $quelle') -and $fn.Contains('Browser-DateienOk $bin')) "browser-bauen: nie als Admin, prüft vor und nach dem Bauen"
Check ($fn.Contains("/platform:x64") -and -not $fn.Contains('Invoke-Expression') -and -not $fn.Contains('Start-Process')) "browser-bauen: übersetzt nur, startet nichts"
Check ($helfer.Contains("ReparsePoint") -and $helfer.Contains("'^bin-[0-9a-f]{12}$'")) "browser-bauen: räumt nur eigene Ordner, nie Verknüpfungen"

""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
