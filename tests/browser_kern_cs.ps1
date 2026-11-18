# Prüft den Browser-Kern (helper/uzai-browser-kern.cs mit helper/uzai-browser-gemeinsam.cs, docs/BROWSER_PLAN.md,
# docs/SECURITY.md „Uzai-Browser“) unter Linux mit PowerShell 7: Die Quellen müssen als C# 5 ohne Warnungen als
# Bibliothek übersetzbar sein (ohne CEF – libcef.dll wird erst zur Laufzeit geladen); jede Größe und jeder
# Versatz der CEF-Strukturen in UzcV muss mit tests/fixtures/cef_api_15101.json übereinstimmen (erzeugt aus den
# CEF-Kopfdateien, tools/cef_api_tabelle.py); der Blocker (UzbFilter) entscheidet wie Uzai
# (tests/fixtures/browser_filter.json); Installer-Eingaben, Startargumente, der Fortschritt per WM_COPYDATA, die
# Konfiguration vom Start-Stummel; feste Sicherheits-Einstellungen im Quelltext; der Start-Stummel
# (assets/browser/cef/uzai-browser-start.dll) hat die eingetragene Prüfsumme, nur den Export RunWinMain und nur
# die Importe kernel32/mscoree.
# Nur am Windows-PC: CEF selbst, Sandbox (chrome://sandbox), Signaturprüfung, Bootstrap, Installer.
#   pwsh -NoProfile -File tests/browser_kern_cs.ps1 helper/uzai-browser-kern.cs →  „Ergebnis: alles ok“
$kern = $args[0]
$root = Split-Path -Parent (Split-Path -Parent (Resolve-Path $kern))
$gemeinsam = Join-Path $root 'helper/uzai-browser-gemeinsam.cs'
$src = (Get-Content -Raw $gemeinsam) + "`n" + (Get-Content -Raw $kern)
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

$ref = Join-Path $PSHOME 'ref'
$refs = @('mscorlib.dll', 'System.Collections.dll', 'System.Runtime.dll', 'System.Text.RegularExpressions.dll', 'System.Security.Cryptography.dll',
    'System.Security.Cryptography.X509Certificates.dll', 'System.Threading.dll', 'System.Threading.Thread.dll', 'System.Console.dll',
    'System.Runtime.InteropServices.dll', 'System.Linq.dll', 'System.Collections.NonGeneric.dll', 'System.Runtime.Extensions.dll', 'netstandard.dll',
    'System.Threading.Timer.dll', 'System.IO.FileSystem.dll', 'System.Text.Encoding.Extensions.dll', 'System.IO.Compression.dll',
    'System.Security.Cryptography.Algorithms.dll', 'System.Security.Cryptography.Primitives.dll' | ForEach-Object { Join-Path $ref $_ } | Where-Object { Test-Path $_ })
try {
    Add-Type -Path @($gemeinsam, (Resolve-Path $kern).Path) -ReferencedAssemblies $refs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "übersetzt (C# 5, Warnungen als Fehler, ohne CEF-Bibliothek)"
} catch {
    Check $false ("übersetzt: " + $_.Exception.Message)
    "Ergebnis: $fails Fehler"
    exit 1
}

# --- Strukturen: jeder Versatz wie in der Tabelle aus den CEF-Kopfdateien --------------------------------------
$tab = Get-Content -Raw (Join-Path $root 'tests/fixtures/cef_api_15101.json') | ConvertFrom-Json
Check ([UzcV]::API -eq [int]$tab.api -and [UzcV]::API_HASH -eq [string]$tab.hash_windows) "API-Fassung und Windows-Hash wie in der Tabelle"
$felder = [UzcV].GetFields() | Where-Object { $_.IsLiteral -and $_.FieldType -eq [int] -and $_.Name -notin @('API', 'BASIS', 'MAIN_ARGS_GROESSE', 'STRING_GROESSE', 'VERSION_INFO_MIT_INSTALLER') }
$geprueft = 0
$falsch = @()
$klassen = @{}
foreach ($p in $tab.klassen.PSObject.Properties) { $klassen[$p.Name] = $p.Value }
$strukturen = @{}
foreach ($p in $tab.strukturen.PSObject.Properties) { $strukturen[$p.Name] = $p.Value }
foreach ($f in $felder) {
    $name = $f.Name
    $wert = [int]$f.GetRawConstantValue()
    $soll = $null
    foreach ($k in $klassen.Keys) {
        $prefix = $k.Substring(4, $k.Length - 6).ToUpperInvariant() + '_'
        if (-not $name.StartsWith($prefix)) { continue }
        $rest = $name.Substring($prefix.Length)
        if ($rest -eq 'GROESSE') { $soll = [int]$klassen[$k].size; break }
        $m = $rest.ToLowerInvariant()
        $v = $klassen[$k].versatz.PSObject.Properties[$m]
        if ($null -ne $v) { $soll = [int]$v.Value; break }
    }
    if ($null -eq $soll) {
        foreach ($s in $strukturen.Keys) {
            $prefix = $s.Substring(4, $s.Length - 6).ToUpperInvariant() + '_'
            if (-not $name.StartsWith($prefix)) { continue }
            $rest = $name.Substring($prefix.Length)
            if ($rest -eq 'GROESSE') { $soll = [int]$strukturen[$s].size; break }
            $v = $strukturen[$s].felder.PSObject.Properties[$rest.ToLowerInvariant()]
            if ($null -ne $v) { $soll = [int]$v.Value; break }
        }
    }
    if ($null -eq $soll) { $falsch += "$name (nicht in der Tabelle)"; continue }
    $geprueft++
    if ($soll -ne $wert) { $falsch += "$name = $wert, Tabelle $soll" }
}
Check ($geprueft -gt 150 -and $falsch.Count -eq 0) ("Versatz und Größen: $geprueft geprüft " + ($falsch -join '; '))
# Jeder Funktionszeiger, den die Handler setzen, muss in seiner Struktur liegen – das prüft UzcApi.Neu beim Bauen.
Check ($src.Contains('if (v < UzcV.BASIS || v + 8 > groesse) throw new ArgumentException("Versatz");')) "Neu(): Versatz außerhalb der Struktur wirft"

# --- Start-Stummel ----------------------------------------------------------------------------------------------
$stummel = Join-Path $root 'assets/browser/cef/uzai-browser-start.dll'
$gd = Get-Content -Raw (Join-Path $root 'src/core/browser_kern.gd')
$helfer = Get-Content -Raw (Join-Path $root 'helper/uzai-helper.ps1')
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $stummel).Hash.ToLowerInvariant()
Check ($gd.Contains($sha) -and $helfer.Contains($sha)) "Stummel: Prüfsumme $sha in Uzai und Helfer"
$bytes = [IO.File]::ReadAllBytes($stummel)
Check ($bytes.Length -lt 65536 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) "Stummel: kleine PE-Datei"
$ascii = [Text.Encoding]::ASCII.GetString($bytes)
Check ($ascii.Contains('RunWinMain') -and $ascii.Contains('kernel32.dll') -and $ascii.Contains('mscoree.dll') -and $ascii.Contains('CLRCreateInstance')) "Stummel: Export RunWinMain, Importe kernel32 und mscoree"
foreach ($nie in @('msvcrt', 'ucrtbase', 'vcruntime', 'libcef.dll', 'ws2_32', 'wininet', 'urlmon', 'shell32', 'advapi32')) {
    Check (-not $ascii.ToLowerInvariant().Contains($nie)) "Stummel ohne $nie"
}
$quelle = Get-Content -Raw (Join-Path $root 'helper/uzai-browser-start.c')
Check ($quelle.Contains('#define UZAI_CEF_API 15101') -and $quelle.Contains([string]$tab.hash_windows)) "Stummel-Quelle: API-Fassung und Hash wie die Tabelle"
Check ($quelle.Contains('if (hat_schalter(GetCommandLineW(), L"type")) return unterprozess(instance, sandbox_info);')) "Stummel: Unterprozesse ohne .NET-Laufzeit"
Check (-not $quelle.Contains('CLRCreateInstance(&CLSID_CLRMetaHost') -or $quelle.IndexOf('static int unterprozess') -lt $quelle.IndexOf('CLRCreateInstance(&CLSID_CLRMetaHost')) "Stummel: Laufzeit nur im Browserprozess"

# --- Konfiguration vom Stummel, Startargumente -------------------------------------------------------------------
$s0 = [UzcStart]::Lesen('instance=0000000000400000;sandbox=00000000deadbeef;version=0000000000000000;show=000000000000000a')
Check ($null -ne $s0 -and $s0.Instance.ToInt64() -eq 4194304 -and $s0.Sandbox.ToInt64() -eq 3735928559 -and $s0.CmdShow -eq 10) "Zeiger vom Stummel gelesen"
Check ($null -eq [UzcStart]::Lesen('instance=1;sandbox=2')) "kaputte Form: abgelehnt"
Check ($null -eq [UzcStart]::Lesen('instance=0000000000400000;sandbox=00000000deadbeef;version=0000000000000000;show=000000000000000a;x=0000000000000001')) "fremdes Feld: abgelehnt"
$m = ''; $p = ''; $l = ''
Check ([UzcEinstieg]::Argumente(@('--uzai-kern', '--profil=standard', '--sprache=de-DE'), [ref]$m, [ref]$p, [ref]$l) -and $m -eq 'kern' -and $p -eq 'standard') "Startargumente Kern"
Check ([UzcEinstieg]::Argumente(@('--uzai-install'), [ref]$m, [ref]$p, [ref]$l) -and $m -eq 'install') "Startargumente Laden"
Check (-not [UzcEinstieg]::Argumente(@('--uzai-kern', '--profil=../x', '--sprache=de-DE'), [ref]$m, [ref]$p, [ref]$l)) "Profil mit ../: abgelehnt"
Check (-not [UzcEinstieg]::Argumente(@('--uzai-kern', '--profil=a', '--sprache=de-DE', '--remote-debugging-port=9222'), [ref]$m, [ref]$p, [ref]$l)) "zusätzliches Argument: abgelehnt"
Check (-not [UzcEinstieg]::Argumente(@('--uzai-install', '--no-sandbox'), [ref]$m, [ref]$p, [ref]$l)) "Laden mit Zusatz: abgelehnt"
$sw = $false
Check ([UzcEinstieg]::Argumente(@('--uzai-kern', '--profil=a', '--sprache=de-DE', '--grafik=software'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and $m -eq 'kern' -and $sw) "Software-Grafik als einziger Zusatz"
Check ([UzcEinstieg]::Argumente(@('--uzai-kern', '--profil=a', '--sprache=de-DE'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and -not $sw) "ohne Zusatz: Hardware"
Check (-not [UzcEinstieg]::Argumente(@('--uzai-kern', '--profil=a', '--sprache=de-DE', '--grafik=x'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and
    -not [UzcEinstieg]::Argumente(@('--uzai-kern', '--profil=a', '--sprache=de-DE', '--grafik=software', '--no-sandbox'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and
    -not [UzcEinstieg]::Argumente(@('--grafik=software', '--uzai-kern', '--profil=a', '--sprache=de-DE'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw)) "andere Grafik, weitere Zusätze, andere Stelle: abgelehnt"
$gs = [regex]::Match($src, 'GRAFIK_SOFTWARE = \{([^}]*)\}').Groups[1].Value
Check ($gs.Trim() -eq '"disable-gpu", "disable-gpu-compositing"') "Software-Grafik nur mit disable-gpu/disable-gpu-compositing (Sandbox bleibt)"
Check ($src.Contains('"disable-gpu-sandbox", "disable-software-rasterizer" }) {') -and $src.Contains('Kern("info", "schalter"')) "GPU-Sandbox und Software-Rückfall nie abschaltbar; Schalter ins Protokoll"

# --- Installer-Eingaben -----------------------------------------------------------------------------------------
Check ([UzcInstaller]::AppIdOk('A3B9C4D5-E6F7-4A8B-9C0D-E1F2A3B4C5D6')) "App-Kennung"
Check (-not [UzcInstaller]::AppIdOk('A3B9C4D5-E6F7-4A8B-9C0D-E1F2A3B4C5D6"') -and -not [UzcInstaller]::AppIdOk('')) "App-Kennung kaputt"
Check ([UzcInstaller]::FassungOk('154.3.2') -and [UzcInstaller]::FassungOk('154.3') -and [UzcInstaller]::FassungOk('')) "Fassungen"
Check (-not [UzcInstaller]::FassungOk('154') -and -not [UzcInstaller]::FassungOk('1.2.3.4') -and -not [UzcInstaller]::FassungOk('x')) "kaputte Fassungen"
Check ([UzcInstaller]::AbiOk('1671cc913eeb4ecf') -and -not [UzcInstaller]::AbiOk('1671CC913EEB4ECF') -and -not [UzcInstaller]::AbiOk('..')) "ABI-Hash"
Check (-not [UzcInstaller]::OrdnerOk('C:\Windows\Temp') -and -not [UzcInstaller]::OrdnerOk('') -and -not [UzcInstaller]::OrdnerOk('C:\x\..\y')) "Store-Ordner nur unter Uzais Kern-Ordner"
# WM_COPYDATA des Installers: CEFI + JSON → Schritt und Prozent; alles andere wird verworfen.
$json = [Text.Encoding]::UTF8.GetBytes('{"step_name":"downloading","step":4,"total_steps":9,"bytes_done":25,"bytes_total":100,"message":"x"}') + [byte]0
$daten = [Runtime.InteropServices.Marshal]::AllocHGlobal($json.Length)
[Runtime.InteropServices.Marshal]::Copy($json, 0, $daten, $json.Length)
$cds = [Runtime.InteropServices.Marshal]::AllocHGlobal(24)
[Runtime.InteropServices.Marshal]::WriteInt64($cds, 0, 0x43454649)
[Runtime.InteropServices.Marshal]::WriteInt32($cds, 8, $json.Length)
[Runtime.InteropServices.Marshal]::WriteIntPtr($cds, 16, $daten)
$f = [UzcInstaller]::Fortschritt($cds)
Check ($null -ne $f -and $f['schritt'] -eq 'downloading' -and $f['prozent'] -eq 25) "Fortschritt gelesen (downloading 25 %)"
[Runtime.InteropServices.Marshal]::WriteInt64($cds, 0, 0x43454652)
Check ($null -eq [UzcInstaller]::Fortschritt($cds)) "andere Kennung: verworfen"
[Runtime.InteropServices.Marshal]::FreeHGlobal($cds); [Runtime.InteropServices.Marshal]::FreeHGlobal($daten)

# --- Blocker: gleiche Tabelle wie Uzai --------------------------------------------------------------------------
$ft = Get-Content -Raw (Join-Path $root 'tests/fixtures/browser_filter.json') | ConvertFrom-Json
$filter = [UzbFilter]::new()
$n = 0
foreach ($z in $ft.regeln) { if ($filter.Zeile([char]$z.Substring(0, 1), $z.Substring(2))) { $n++ } }
Check ($n -eq $ft.regeln.Count) "alle $n Regeln der Tabelle angenommen"
$falsch = @()
foreach ($z in $ft.faelle) {
    $g = $filter.Gesperrt([string]$z[0], [int]$z[1], [string]$z[2])
    if ($g -ne [bool]$z[3]) { $falsch += ("{0} ({1} auf {2}): {3}" -f $z[0], $z[1], $z[2], $g) }
}
Check ($falsch.Count -eq 0) ("Blocker: gleiches Urteil wie Uzai " + ($falsch -join ' | '))
$k = $filter.Kosmetik('news.example')
Check ($k.Count -eq [int]$ft.kosmetik_news -and $filter.Kosmetik('other.example').Count -eq [int]$ft.kosmetik_other) "Kosmetik je Seite (news $($k.Count), other $($filter.Kosmetik('other.example').Count))"
foreach ($bad in @('div{color:red}', 'a;b', 'x url(a)', '/* */', 'div:has(a)')) { Check (-not [UzbFilter]::SelektorOk($bad)) "Selektor abgelehnt: $bad" }
Check (-not $filter.Zeile('p', 'x')) "zu kurzes Muster abgelehnt"
Check (-not $filter.Gesperrt('https://ads.example/x.js', 0, 'news.example')) "Hauptdokument nie gesperrt"
Check ([UzbFilter]::Site('a.b.co.uk') -eq 'b.co.uk' -and [UzbFilter]::Site('x.example.com') -eq 'example.com') "Site aus dem Namen"

# --- Feste Sicherheits-Einstellungen im Quelltext ------------------------------------------------------------------
foreach ($muss in @('SETTINGS_NO_SANDBOX, 0)', 'SETTINGS_REMOTE_DEBUGGING_PORT, 0)', 'SETTINGS_COMMAND_LINE_ARGS_DISABLED, 1)', 'LOGSEVERITY_DISABLE',
        'if (start.Sandbox == IntPtr.Zero) { Grund(aus, "K10 ohne Sandbox vom Bootstrap"); aus.Fehler("kern_sandbox")', 'UzbSignatur.Von(start.LibcefPfad, UzcV.CEF_ZERTIFIKAT)', 'if (hash != UzcV.API_HASH)',
        '"no-sandbox", "remote-debugging-port", "remote-debugging-pipe", "remote-allow-origins", "load-extension"', 'Fehler("kern_sandbox"); Beenden();',
        'RUNTIME_STYLE_ALLOY', 'int ChromeBefehl(IntPtr self, IntPtr browser, int befehl, int disposition) { return 1; }', 'return 1;   // nie ein eigenes Fenster',
        'UzcApi.Fn<UzcD.SelfD>(callback, UzcV.FILE_DIALOG_CALLBACK_CANCEL)(callback);', 'return 0;   // kein „trotzdem fortfahren“', 'Gesperrt(t.Id, "anmeldedialog");',
        '(gewuenscht & ~(MEDIA_AUDIO | MEDIA_VIDEO)) != 0', 'gewuenscht != PERM_GEOLOCATION) { weiter(callback, PERMISSION_DENY)', 'UzbRegeln.DownloadOk(name)',
        'UzbRegeln.ZielGesperrt(u, HeimErlaubt(t, u) || HeimSeite(t))', '"executionContextName"', '"worldName"', 'Marshal.WriteInt32(erlauben, 0);',
        'UzcApi.HandlesSchliessen();', 'if (UzcApi.Erhoeht())', '"disable-component-update", "disable-background-networking"', '"credentials_enable_service", false',
        'int FokusSetzen(IntPtr self, IntPtr browser, int quelle) { return 1; }', 'KEYBOARD_HANDLER_ON_PRE_KEY_EVENT')) {
    Check ($src.Contains($muss)) "Quelltext: $muss"
}
foreach ($nie in @('Process.Start', 'UseShellExecute', 'execute_java_script', 'ExecuteJavaScript', 'remote-debugging-port=', 'show_dev_tools', 'SetForegroundWindow',
        'SendInput', 'keybd_event', 'cef_register_extension', 'AddHostObject', 'no_sandbox = 1', 'eval(')) {
    Check (-not $src.Contains($nie)) "Quelltext ohne $nie"
}
$kernSrc = Get-Content -Raw $kern
Check (([regex]::Matches($kernSrc, 'PERMISSION_ACCEPT')).Count -eq 2 -and $kernSrc.Contains('weiter(callback, ja ? PERMISSION_ACCEPT : PERMISSION_DENY)')) "Erlauben nur nach deiner Antwort"
Check ((([regex]::Matches($kernSrc, 'cef_browser_host_create_browser_sync\(')).Count -eq 2)) "Browser entstehen nur an einer Stelle (immer als Kindfenster, Alloy-Stil)"

# --- Spotify-Sitzung (--uzai-spotify, src/core/spotify_web.gd) ---------------------------------------------------
Check ([UzcEinstieg]::Argumente(@('--uzai-spotify', '--profil=standard', '--sprache=de-DE'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and $m -eq 'spotify' -and -not $sw) "Startargumente Spotify-Sitzung"
Check ([UzcEinstieg]::Argumente(@('--uzai-spotify', '--profil=a', '--sprache=en-US', '--grafik=software'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and $m -eq 'spotify' -and $sw) "Spotify-Sitzung mit Software-Grafik"
Check (-not [UzcEinstieg]::Argumente(@('--uzai-spotify', '--profil=../x', '--sprache=de-DE'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and
    -not [UzcEinstieg]::Argumente(@('--uzai-spotify', '--profil=a', '--sprache=de-DE', '--no-sandbox'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw) -and
    -not [UzcEinstieg]::Argumente(@('--uzai-spotify'), [ref]$m, [ref]$p, [ref]$l, [ref]$sw)) "Spotify-Sitzung: dieselben strengen Formen"
foreach ($u in @('https://accounts.spotify.com/de/login?continue=x', 'https://open.spotify.com/', 'https://challenge.spotify.com/c', 'https://accounts.google.com/o', 'https://appleid.apple.com/auth')) {
    Check ([UzcSpotify]::Erlaubt($u)) "Spotify-Sitzung darf: $u"
}
foreach ($u in @('http://open.spotify.com/', 'https://spotify.com.boese.de/', 'https://boese-spotify.com/', 'https://example.com/', 'javascript:alert(1)', 'https://127.0.0.1/', 'https://www.google.com/')) {
    Check (-not [UzcSpotify]::Erlaubt($u)) "Spotify-Sitzung sperrt: $u"
}
Check ([UzcSpotify]::TraegtSchluessel('https://api-partner.spotify.com/pathfinder/v2/query') -and [UzcSpotify]::TraegtSchluessel('https://gew4-spclient.spotify.com/x') -and
    [UzcSpotify]::TraegtSchluessel('https://spclient.wg.spotify.com/x') -and -not [UzcSpotify]::TraegtSchluessel('https://open.spotify.com/api/token') -and
    -not [UzcSpotify]::TraegtSchluessel('http://api-partner.spotify.com/x') -and -not [UzcSpotify]::TraegtSchluessel('https://api-partner.spotify.com.boese.de/')) "Schlüssel nur aus Anfragen an pathfinder, spclient, Web-API (https)"
Check ([UzcSpotify]::Gesperrt('https://gew4-spclient.spotify.com/connect-state/v1/devices/hobs_abc') -and [UzcSpotify]::Gesperrt('https://spclient.wg.spotify.com/track-playback/v1/devices') -and
    -not [UzcSpotify]::Gesperrt('https://spclient.wg.spotify.com/melody/v1/x') -and -not [UzcSpotify]::Gesperrt('https://api-partner.spotify.com/pathfinder/v2/query')) "die Seite wird nie ein Connect-Gerät"
$tok = 'BQD' + ('aB3-_x9' * 20)
Check ([UzcSpotify]::Bearer("Bearer $tok") -eq $tok -and [UzcSpotify]::Bearer($tok) -eq '' -and [UzcSpotify]::Bearer('Bearer kurz') -eq '' -and
    [UzcSpotify]::Bearer("Bearer $tok`r`nX: y") -eq '' -and [UzcSpotify]::Bearer('Bearer ' + ('a' * 2049)) -eq '' -and [UzcSpotify]::Bearer($null) -eq '') "Bearer: nur Base64(url), 20–2048 Zeichen"
Check ([UzcSpotify]::Fassung('1.2.73.157.gd7f98bd8') -eq '1.2.73.157.gd7f98bd8' -and [UzcSpotify]::Fassung('1.2;x') -eq '' -and [UzcSpotify]::Fassung('x1.2') -eq '') "Fassung des Webplayers geprüft"
$ev = [UzbSchema]::Ereignis([UzbJson]::Lesen('{"t":"spotify","token":"' + $tok + '","client":"","version":"1.2.3","mehr":1}'))
Check ($null -ne $ev -and -not $ev.ContainsKey('mehr') -and $null -eq [UzbSchema]::Ereignis([UzbJson]::Lesen('{"t":"spotify","token":"a b","client":"","version":""}'))) "Ereignis spotify: festes Schema"
Check ($null -eq [UzbSchema]::Skript([UzbJson]::Lesen('{"t":"spotify","token":"' + $tok + '","client":"","version":""}'))) "das Sprung-Skript der Seite kann keinen Schlüssel melden"
foreach ($muss in @('Path.Combine(wurzel, spotify ? "spotify-daten" : "kern-daten")', 'sp ? null : filter', 'if (spotify) return;   // Diagnose, Update',
        'if (UzcSpotify.Gesperrt(u) && !SpotifyErwartet(u)) return RV_CANCEL;', 'BROWSER_HOST_SET_AUDIO_MUTED)(t.Host, 1)', 'g == "" && spotify && haupt && !UzcSpotify.Erlaubt(u)',
        't.Intern || spotify || UzbRegeln.UrlGrund(u, HeimErlaubt(t, u)) != "") return 0;', 'if (intern || !UzcSpotify.Erlaubt(url)) { Gesperrt(0, "nur_spotify"); return; }')) {
    Check ($src.Contains($muss)) "Spotify-Sitzung im Quelltext: $muss"
}
# Jedes Uzai-Profil hat seinen eigenen Browser-Ordner: Wurzel und Profil sind derselbe Ordner (Chrome-Stil nimmt als
# Profil nur die Wurzel oder ein direktes Kind – sonst landete alles gemeinsam in daten\Default).
Check ($src.Contains('SETTINGS_ROOT_CACHE_PATH, profilOrdner, puffer)') -and -not $src.Contains('SETTINGS_ROOT_CACHE_PATH, daten, puffer)')) "Browser-Daten je Profil getrennt (Wurzel = Ordner des Profils)"
$weg = [regex]::Match($kernSrc, '(?s)static void AltesGemeinsamesWeg\(string daten\) \{.*?\n    \}').Value
Check ($weg.Contains('Path.Combine(daten, "Default")') -and $weg.Contains('Path.Combine(daten, "Local State")') -and ([regex]::Matches($weg, 'Delete\(').Count -eq 2)) "alter gemeinsamer Stand: nur Default und Local State werden gelöscht"
$beob = [regex]::Match($kernSrc, '(?s)void SpotifyBeobachten\(IntPtr anfrage, string u\) \{.*?\n    \}').Value
Check ($beob.Contains('aus.Senden(d);') -and -not $beob.Contains('Kern(') -and -not $beob.Contains('Grund(')) "Schlüssel geht nur über die Leitung, nie ins Protokoll"

# --- Spotify-Abfragen in der Seite (spotify-abfrage → spotify-antwort) ------------------------------------------
$pf = '{"operationName":"libraryV3","variables":{"limit":50,"order":null},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"' + ('a' * 64) + '"}}}'
Check ([UzcSpotify]::AbfrageGrund('pathfinder', 'POST', '/pathfinder/v2/query', $pf, '') -eq '') "pathfinder: POST mit operationName und Hash"
Check ([UzcSpotify]::AbfrageGrund('pathfinder', 'GET', '/pathfinder/v2/query', '', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('pathfinder', 'POST', '/pathfinder/v1/query', $pf, '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('pathfinder', 'POST', '/pathfinder/v2/query', $pf.Replace('libraryV3', 'x;y'), '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('pathfinder', 'POST', '/pathfinder/v2/query', $pf.Replace('a' * 64, 'zz'), '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('pathfinder', 'POST', '/pathfinder/v2/query', '[1]', '') -eq 'ziel') "pathfinder: sonst nichts (GET, anderer Pfad, fremder Name, kein Hash, kein Objekt)"
Check ([UzcSpotify]::AbfrageGrund('spclient', 'PUT', '/connect-state/v1/devices/hobs_abc', '{"a":1}', 'Y29ubmVjdA==') -eq '' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'POST', '/connect-state/v1/player/command/from/a/to/b', '{"command":{}}', '') -eq '' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'GET', '/context-resolve/v1/spotify:playlist:abc', '', '') -eq '' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'GET', '/recently-played/v3/user/x/recently-played?format=json&filter=default,collection', '', '') -eq '') "spclient: Spotify Connect, Titel einer Liste, Zuletzt gehört"
Check ([UzcSpotify]::AbfrageGrund('spclient', 'PUT', '/connect-state/v1/player/command/from/a/to/b', '{}', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'POST', '/context-resolve/v1/x', '{}', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'GET', '/melody/v1/x', '', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'GET', '/context-resolve/v1/../x', '', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'GET', '/context-resolve/v1/x', '', 'a b') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'GET', '/context-resolve/v1/x', '', 'abc') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('spclient', 'GET', '/context-resolve/v1/x', '{"a":1}', '') -eq 'ziel') "spclient: kein PUT/POST außer Connect, keine anderen Dienste, kein .., Kennung nur für Connect, GET ohne Inhalt"
Check ([UzcSpotify]::AbfrageGrund('webapi', 'GET', '/v1/me', '', '') -eq '' -and [UzcSpotify]::AbfrageGrund('webapi', 'PUT', '/v1/me/player/play', '{}', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('webapi', 'GET', '/me', '', '') -eq 'ziel' -and [UzcSpotify]::AbfrageGrund('webapi', 'GET', '/v1/me#x', '', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('webapi', 'GET', '//evil.example/v1/', '', '') -eq 'ziel' -and [UzcSpotify]::AbfrageGrund('webapi', 'DELETE', '/v1/me', '', '') -eq 'ziel' -and
    [UzcSpotify]::AbfrageGrund('andere', 'GET', '/v1/me', '', '') -eq 'ziel') "Web-API: nur GET/POST unter /v1/, kein fremder Host über den Pfad"
Check ([UzcSpotify]::Adresse('pathfinder', '/x', '') -eq 'https://api-partner.spotify.com/pathfinder/v2/query' -and
    [UzcSpotify]::Adresse('spclient', '/context-resolve/v1/x', 'gew4-spclient.spotify.com') -eq 'https://gew4-spclient.spotify.com/context-resolve/v1/x' -and
    [UzcSpotify]::Adresse('spclient', '/context-resolve/v1/x', 'boese.example') -eq 'https://spclient.wg.spotify.com/context-resolve/v1/x' -and
    [UzcSpotify]::Adresse('webapi', '/v1/me', '') -eq 'https://api.spotify.com/v1/me') "feste Hosts je Ziel (spclient der Seite nur nach Muster)"
$k = [UzcSpotify]::Kopf('pathfinder', $tok, 'ctok', '1.2.3', $true, '')
Check ($k['authorization'] -eq "Bearer $tok" -and $k['client-token'] -eq 'ctok' -and $k['app-platform'] -eq 'WebPlayer' -and $k['spotify-app-version'] -eq '1.2.3' -and $k['content-type'] -like 'application/json*') "Kopfzeilen wie die der Seite (pathfinder)"
$k2 = [UzcSpotify]::Kopf('webapi', $tok, 'ctok', '1.2.3', $false, '')
Check (-not $k2.ContainsKey('client-token') -and -not $k2.ContainsKey('app-platform') -and -not $k2.ContainsKey('content-type')) "Web-API: nur der Schlüssel"
Check ([UzcSpotify]::FUNKTION.Contains('AbortController') -and [UzcSpotify]::FUNKTION.Contains("redirect: 'error'") -and [UzcSpotify]::FUNKTION.Contains('x.slice(0, a.n)') -and
    -not [UzcSpotify]::FUNKTION.Contains('eval') -and -not [UzcSpotify]::FUNKTION.Contains('Function(')) "fetch in der Seite: Zeitlimit, keine Umleitung, Größengrenze, kein eval"
$b = [UzbSchema]::Befehl([UzbJson]::Lesen('{"t":"spotify-abfrage","id":7,"ziel":"webapi","methode":"POST","pfad":"/v1/x","inhalt":"{\"a\": 1}","verbindung":"","zeit":20000}'))
Check ($null -ne $b -and $b['inhalt'] -eq '{"a":1}') "Befehl spotify-abfrage: Inhalt neu geschrieben"
Check ($null -eq [UzbSchema]::Befehl([UzbJson]::Lesen('{"t":"spotify-abfrage","id":7,"ziel":"webapi","methode":"PUT","pfad":"/v1/x","inhalt":"","verbindung":"","zeit":20000}'))) "Befehl spotify-abfrage: Regeln je Ziel schon an der Leitung"
Check ($null -eq [UzbSchema]::Befehl([UzbJson]::Lesen('{"t":"spotify-abfrage","id":7,"ziel":"pathfinder","methode":"POST","pfad":"/pathfinder/v2/query","inhalt":"[1]","verbindung":"","zeit":20000}')) -and
    $null -eq [UzbSchema]::Befehl([UzbJson]::Lesen('{"t":"spotify-abfrage","id":7,"ziel":"x","methode":"POST","pfad":"/p","inhalt":"","verbindung":"","zeit":20000}')) -and
    $null -eq [UzbSchema]::Befehl([UzbJson]::Lesen('{"t":"spotify-abfrage","id":7,"ziel":"webapi","methode":"GET","pfad":"/v1/me x","inhalt":"","verbindung":"","zeit":20000}')) -and
    $null -eq [UzbSchema]::Befehl([UzbJson]::Lesen('{"t":"spotify-abfrage","id":7,"ziel":"webapi","methode":"GET","pfad":"/v1/me","inhalt":"","verbindung":"","zeit":99}'))) "Befehl spotify-abfrage: Schema (Inhalt, Ziel, Pfad, Zeit)"
$ant = [UzbSchema]::Ereignis([UzbJson]::Lesen('{"t":"spotify-antwort","id":7,"code":403,"grund":"","text":"{\"error\":1}","gekuerzt":false,"warte":0}'))
Check ($null -ne $ant -and $ant['text'] -eq '{"error":1}' -and $null -eq [UzbSchema]::Ereignis([UzbJson]::Lesen('{"t":"spotify-antwort","id":7,"code":1000,"grund":"","text":"","gekuerzt":false,"warte":0}')) -and
    $null -eq [UzbSchema]::Ereignis([UzbJson]::Lesen('{"t":"spotify-antwort","id":7,"code":200,"grund":"anders","text":"","gekuerzt":false,"warte":0}'))) "Ereignis spotify-antwort: festes Schema"
$gross = New-Object System.Collections.Generic.Dictionary[string`,object]
$gross['t'] = 'spotify-antwort'; $gross['id'] = 1; $gross['code'] = 200; $gross['grund'] = ''; $gross['gekuerzt'] = $false; $gross['warte'] = 0
$gross['text'] = 'x' * ([UzbSchema]::MAX_ANTWORT + 1)
Check ($null -eq [UzbSchema]::Ereignis($gross)) "Antwort über der Größengrenze: verworfen"
$gross['text'] = 'x' * 1000000
$ms = New-Object System.IO.MemoryStream
Check (([UzbAusgabe]::new($ms)).Senden($gross) -and $ms.Length -gt [UzbSchema]::MAX_EREIGNIS) "große Antwort (1 MB) passt durch die Leitung (eigene Grenze)"
$abf = [regex]::Match($kernSrc, '(?s)void SpotifyAbfrage\(Dictionary<string, object> b\) \{.*?\n    \}').Value
Check ($abf.Contains('UzcSpotify.AbfrageGrund(') -and $abf.Contains('UzcSpotify.Kopf(') -and $abf.Contains('"awaitPromise"') -and $abf.Contains('MAX_OFFEN') -and
    -not $abf.Contains('Kern(') -and $abf.Contains('zeit + 5000')) "Abfrage: geprüft, Kopfzeilen vom Kern, höchstens MAX_OFFEN, Sicherung, nichts ins Protokoll"
$antw = [regex]::Match($kernSrc, '(?s)void SpotifyAntwort\(int id.*?\n    \}').Value
Check ($antw.Contains('aus.Senden(d)') -and -not $antw.Contains('Kern(')) "Antwort nur über die Leitung"

# --- Helfer -----------------------------------------------------------------------------------------------------
Check ($helfer.Contains("'kern-auslegen' { return (Kern-Auslegen") -and $helfer.Contains("'kern-bauen' { return (Kern-Bauen") -and $helfer.Contains("'kern-ressource' { return (Kern-Ressource")) "Helfer kennt kern-auslegen, kern-bauen, kern-ressource"
$fn = [regex]::Match($helfer, '(?s)function Kern-Auslegen\(\$a\) \{.*?\n\}').Value
Check ($fn.Contains('[UzElev]::IsElevated($PID)') -and $fn.Contains('Kern-Entpacken ') -and $helfer.Contains('[UzKernPack]::Auslegen($voll, $tmp, $art)') -and $fn.Contains('Kern-SignaturEntfernen')) "kern-auslegen: nie als Admin, eigener Entpacker (je Archiv eine Datei, tests/kern_pack_cs.ps1), nimmt Signaturen von Kopien"
Check (-not $fn.Contains('Invoke-Expression') -and -not $fn.Contains('Start-Process')) "kern-auslegen: startet nichts"
$fn2 = [regex]::Match($helfer, '(?s)function Kern-Bauen \{.*?\n\}').Value
Check ($fn2.Contains('/target:library') -and $fn2.Contains('uzai-browser-gemeinsam.cs') -and $fn2.Contains('uzai-browser-kern.cs') -and -not $fn2.Contains('Invoke-Expression')) "kern-bauen: übersetzt beide Quellen als Bibliothek"

""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
