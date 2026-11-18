# Prüft die beiden Netz-Bibliotheken der Zimmer-Sandbox (docs/ZIMMER_SICHERHEIT.md W7, Abschnitt 5; tools/bau_netzlibs.sh):
#  1. Die Windows-DLLs in assets/net/: Prüfsumme gleich den Werten in der Sandbox (UzNetzLib), in Uzai (zimmer_netz.gd
#     NETZLIBS) und im Bauskript-Nachweis; Härtung aus dem PE-Kopf (DYNAMICBASE, HIGHENTROPYVA, NX, x64, ohne
#     Zeitstempel); nur Windows-Systembibliotheken als Importe; Exporte genau die erwarteten (libdatachannel nur die
#     benutzte C-Schnittstelle, libsecp256k1 ohne ecdh/recovery/musig/ellswift).
#  2. Die Lade-Regeln im Quelltext: voller Pfad, Prüfsumme vor dem Laden, LOAD_LIBRARY_SEARCH_SYSTEM32, kein DllImport
#     auf die Bibliotheken (kein Suchpfad), Standardausgabe geschützt.
#  3. Mit der Linux-Fassung derselben Quellen (build/netzlibs-linux, nur für Tests): alle BIP-340-Testvektoren
#     (tests/bip340_vektoren.txt), falsche Signaturen, Fuzz der P/Invoke-Schicht, echte Nostr-Ereignisse; ein echter
#     WebRTC-Datenkanal über 127.0.0.1 mit Grenzen (Größe, Text, Flut, fremde Kanäle) und eine böse Gegenstelle.
# Ohne Linux-Fassung (tools/bau_netzlibs.sh --linux) wird Teil 3 übersprungen.
#   pwsh -NoProfile -File tests/netzlibs_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$ErrorActionPreference = 'Stop'
$src = Get-Content -Raw $args[0]
$root = Split-Path -Parent (Split-Path -Parent (Resolve-Path $args[0]))
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}
$cs = [regex]::Match($src, "\`$script:ZimmerNetzSrc = @'\r?\n(?s)(.*?)\r?\n'@").Groups[1].Value
try { Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; Check $true "Sandbox übersetzt (C# 5, Warnungen als Fehler)" }
catch { Check $false ("übersetzt: " + $_.Exception.Message); "Ergebnis: $fails Fehler"; exit 1 }

"Windows-DLLs (assets/net)"
$gd = Get-Content -Raw (Join-Path $root 'src/room/zimmer_netz.gd')
$dlls = @(@('uzai-secp256k1.dll', [UzNetzLib]::SECP_SHA256), @('uzai-datachannel.dll', [UzNetzLib]::RTC_SHA256))
foreach ($d in $dlls) {
    $p = Join-Path $root ('assets/net/' + $d[0])
    $ist = if (Test-Path $p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() } else { '' }
    Check ($ist -eq $d[1] -and $gd.Contains('"' + $d[0] + '": "' + $d[1] + '"')) "$($d[0]): Prüfsumme gleich in Datei, Sandbox und Uzai ($($ist.Substring(0, [Math]::Min(12, $ist.Length))))"
}

# PE lesen (nur was wir brauchen): Kopf, Abschnitte, Import- und Exportverzeichnis.
function PeLesen([string]$pfad) {
    $b = [IO.File]::ReadAllBytes($pfad)
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    $r = @{ ok = ([Text.Encoding]::ASCII.GetString($b, $pe, 4) -eq "PE`0`0") }
    $r.maschine = [BitConverter]::ToUInt16($b, $pe + 4)
    $n = [BitConverter]::ToUInt16($b, $pe + 6)
    $r.zeit = [BitConverter]::ToUInt32($b, $pe + 8)
    $opt = $pe + 24
    $r.magic = [BitConverter]::ToUInt16($b, $opt)
    $r.dllchar = [BitConverter]::ToUInt16($b, $opt + 70)
    $r.basis = [BitConverter]::ToUInt64($b, $opt + 24)
    $dd = $opt + 112
    $abschn = $opt + [BitConverter]::ToUInt16($b, $pe + 20)
    $teile = @()
    for ($i = 0; $i -lt $n; $i++) { $o = $abschn + 40 * $i; $teile += , @([BitConverter]::ToUInt32($b, $o + 12), [BitConverter]::ToUInt32($b, $o + 8), [BitConverter]::ToUInt32($b, $o + 20)) }
    $rva = { param($v) foreach ($t in $teile) { if ($v -ge $t[0] -and $v -lt $t[0] + [Math]::Max($t[1], 1)) { return [int]($v - $t[0] + $t[2]) } }; return -1 }
    $txt = { param($o) $e = $o; while ($b[$e] -ne 0) { $e++ }; [Text.Encoding]::ASCII.GetString($b, $o, $e - $o) }
    $r.exporte = @()
    $ex = [BitConverter]::ToUInt32($b, $dd)
    if ($ex -ne 0) {
        $eo = & $rva $ex
        $anz = [BitConverter]::ToUInt32($b, $eo + 24); $namen = & $rva ([BitConverter]::ToUInt32($b, $eo + 32))
        for ($i = 0; $i -lt $anz; $i++) { $r.exporte += & $txt (& $rva ([BitConverter]::ToUInt32($b, $namen + 4 * $i))) }
    }
    $r.importe = @()
    $im = [BitConverter]::ToUInt32($b, $dd + 8)
    if ($im -ne 0) {
        $io = & $rva $im
        while ([BitConverter]::ToUInt32($b, $io + 12) -ne 0) { $r.importe += & $txt (& $rva ([BitConverter]::ToUInt32($b, $io + 12))); $io += 20 }
    }
    return $r
}
$system = @('KERNEL32.dll', 'msvcrt.dll', 'WS2_32.dll', 'IPHLPAPI.DLL', 'bcrypt.dll')
$rtcExporte = @((Get-Content (Join-Path $root 'tools/netzlibs/datachannel.def')) | Where-Object { $_ -match '^\s+rtc' } | ForEach-Object { $_.Trim() }) | Sort-Object
foreach ($d in $dlls) {
    $p = Join-Path $root ('assets/net/' + $d[0])
    if (-not (Test-Path $p)) { Check $false "$($d[0]) fehlt"; continue }
    $pe = PeLesen $p
    Check ($pe.ok -and $pe.maschine -eq 0x8664 -and $pe.magic -eq 0x20B) "$($d[0]): PE32+ für x64"
    Check (($pe.dllchar -band 0x0160) -eq 0x0160 -and $pe.basis -gt 0xFFFFFFFF) "$($d[0]): DYNAMICBASE, HIGHENTROPYVA, NX_COMPAT, Basis über 4 GB (0x$('{0:X4}' -f $pe.dllchar))"
    Check ($pe.zeit -eq 0) "$($d[0]): ohne Zeitstempel (reproduzierbar)"
    $fremd = @($pe.importe | Where-Object { $system -notcontains $_ })
    Check ($fremd.Count -eq 0 -and $pe.importe.Count -ge 2) "$($d[0]): nur Windows-Systembibliotheken ($($pe.importe -join ', '))"
    if ($d[0] -eq 'uzai-datachannel.dll') {
        Check ((@($pe.exporte | Sort-Object) -join ',') -eq ($rtcExporte -join ',')) "libdatachannel: genau die $($rtcExporte.Count) benutzten C-Funktionen exportiert (keine C++-Klassen, kein WebSocket, keine Medien)"
    } else {
        $schlecht = @($pe.exporte | Where-Object { $_ -notmatch '^secp256k1_' -or $_ -match 'ecdh|recover|musig|ellswift' })
        Check ($schlecht.Count -eq 0 -and $pe.exporte -contains 'secp256k1_schnorrsig_sign32' -and $pe.exporte -contains 'secp256k1_schnorrsig_verify') "libsecp256k1: nur secp256k1_*, mit schnorrsig, ohne ecdh/recovery/musig/ellswift"
    }
}
$exp = Get-Content -Raw (Join-Path $root 'export_presets.cfg')
Check ($exp -match 'include_filter="[^"]*assets/net/\*\.dll') "Export nimmt assets/net/*.dll mit"

"Lade-Regeln (Quelltext)"
$lib = [regex]::Match($cs, '(?s)public static class UzNetzLib \{.*?\n\}').Value
Check ($lib.Contains('LoadLibraryExW(pfad, IntPtr.Zero, LOAD_LIBRARY_SEARCH_SYSTEM32)') -and $lib.Contains('LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x800')) "voller Pfad, Abhängigkeiten nur aus System32"
Check ($lib.IndexOf('UzKrypto.Sha256(alles)) == soll') -gt 0 -and $lib.IndexOf('UzKrypto.Sha256(alles)) == soll') -lt $lib.IndexOf('LoadLibraryExW(pfad') -and $lib.Contains('FileShare.Read')) "erst Prüfsumme (Datei gegen Schreiben gesperrt), dann laden"
Check (-not ($cs -match 'DllImport\("uzai|DllImport\("libuzai|LoadLibrary\(|LoadLibraryW\(') -and ([regex]::Matches($cs, 'LoadLibraryExW\(')).Count -eq 2) "kein DllImport auf die Bibliotheken, kein LoadLibrary mit Suchpfad"
Check ($lib.Contains('if (Windows && !Geschuetzt) z = LADEN;') -and $cs.Contains('Stream geschuetzt = UzNetzLib.AusgabeSchuetzen();')) "unter Windows erst laden, wenn die Leitung geschützt ist"
Check ($lib.Contains('Environment.GetEnvironmentVariable("UZAI_NETZLIB_TEST")') -and $lib.IndexOf('if (Windows) {') -lt $lib.IndexOf('UZAI_NETZLIB_TEST')) "Test-Ordner nur außerhalb von Windows"
Check ($src.Contains('ZimmerNetz-Bibliotheken $dir') -and $src -match "Get-FileHash -LiteralPath \`$quelle -Algorithm SHA256\)\.Hash\.ToLowerInvariant\(\) -ne \`$paar\[1\]") "Helfer legt die Bibliotheken nur mit richtiger Prüfsumme neben die Sandbox"
Check ($cs.Contains('foreach (string lib in new[] { UzNetzLib.SECP, UzNetzLib.RTC })') -and $cs.Contains('Erlauben(pfad, sid)')) "der Container darf genau diese Dateien lesen/ausführen"
Check ($cs.Contains('k.IceTcp') -eq $false -and $cs.Contains('k.MaxNachricht = MAX_NACHRICHT;') -and -not ($cs -cmatch '"turns?:')) "WebRTC: kein ICE-TCP, kein TURN, Nachrichten höchstens 4096 Byte"
Check (@([UzRtc]::STUN | Where-Object { $_ -notmatch '^stun:[a-z0-9.-]+:[0-9]{2,5}$' }).Count -eq 0 -and [UzRtc]::STUN.Count -eq 2) "STUN nur fest eingetragen ($([UzRtc]::STUN -join ', '))"

# --- Teil 3: mit der Linux-Fassung ---------------------------------------------------------------------------------------
$d = Join-Path $root 'build/netzlibs-linux'
$so1 = Join-Path $d 'libuzai-secp256k1.so'; $so2 = Join-Path $d 'libuzai-datachannel.so'
if (-not ((Test-Path $so1) -and (Test-Path $so2))) {
    "  (Linux-Fassung fehlt – tools/bau_netzlibs.sh --linux; Teil 3 übersprungen)"
    if ($fails -gt 0) { "Ergebnis: $fails Fehler"; exit 1 }
    "Ergebnis: alles ok"; exit 0
}
"Falsche Prüfsumme"
$env:UZAI_NETZLIB_TEST = "$d|" + ('0' * 64) + "|" + ('0' * 64)
Check ([UzNetzLib].GetMethod('Laden').Invoke($null, @('uzai-secp256k1.dll')) -eq [IntPtr]::Zero -and [UzNetzLib]::Zustand('uzai-secp256k1.dll') -eq 3 -and -not [UzSecp]::Bereit()) "Prüfsumme falsch: nicht geladen (Zustand 3), keine Signatur"
Check ($null -eq [UzNostr]::EchterSignierer()) "ohne Bibliothek kein echter Signierer"
# Für den Rest frisch (Zustände sind je Prozess): eine zweite Laufzeit-Instanz gibt es nicht – darum hier neu laden.
$env:UZAI_NETZLIB_TEST = "$d|" + (Get-FileHash $so1).Hash.ToLower() + "|" + (Get-FileHash $so2).Hash.ToLower()
[UzNetzLib].GetField('zustand', [Reflection.BindingFlags]'NonPublic,Static').GetValue($null).Clear()
[UzSecp].GetField('bereit', [Reflection.BindingFlags]'NonPublic,Static').SetValue($null, -1)

"libsecp256k1 (BIP-340)"
Check ([UzSecp]::Bereit() -and [UzNetzLib]::Zustand('uzai-secp256k1.dll') -eq 1) "geladen, Prüfsumme und Selbsttest in Ordnung"
$secpT = [UzSecp]
$priv = [Reflection.BindingFlags]'NonPublic,Static'
$mPaar = $secpT.GetMethod('Paar', $priv); $mPub = $secpT.GetMethod('Oeffentlich', $priv); $mSig = $secpT.GetMethod('Signatur', $priv)
function HexB([string]$s) { if ($s -eq '') { return , (New-Object byte[] 0) }; return , [UzKrypto]::Hex($s) }
$vek = @(Get-Content (Join-Path $root 'tests/bip340_vektoren.txt') | Where-Object { $_ -match '^[0-9]+,' })
$alle = $true; $n = 0
foreach ($z in $vek) {
    $f = $z.Split(',')
    $sk = $f[1]; $pk = HexB $f[2]; $aux = $f[3]; $msg = HexB $f[4]; $sig = HexB $f[5]; $soll = $f[6] -eq 'TRUE'
    if ($sk -ne '') {
        $kp = $mPaar.Invoke($null, @(, (HexB $sk)))
        $pub = $mPub.Invoke($null, @(, $kp))
        $alle = $alle -and [UzKrypto]::Gleich($pub, $pk)
        $auxB = [byte[]](HexB $aux)
        if ($msg.Length -eq 32) { $alle = $alle -and [UzKrypto]::Gleich($mSig.Invoke($null, [object[]]@($kp, $msg, $auxB)), $sig) }
    }
    # Unsere Schnittstelle prüft nur 32-Byte-Nachrichten (Nostr-Kennungen); andere Längen müssen abgelehnt werden.
    $ist = [UzSecp]::Pruefen($sig, $msg, $pk)
    $alle = $alle -and ($ist -eq ($soll -and $msg.Length -eq 32))
    $n++
}
Check ($alle -and $n -eq 19) "alle $n Vektoren aus BIP-340: Schlüssel, Signatur und Prüfergebnis wie vorgegeben"
$rng = New-Object Random 340
function Zufall([int]$k) { $b = New-Object byte[] $k; $rng.NextBytes($b); return , $b }
$k = New-Object UzSecp+Schluessel
$ok = $true; $falsch = 0
for ($i = 0; $i -lt 200; $i++) {
    $m = Zufall 32; $s = $k.Signieren($m)
    $ok = $ok -and $s.Length -eq 64 -and [UzSecp]::Pruefen($s, $m, $k.Pub)
    $s2 = [byte[]]$s.Clone(); $s2[$rng.Next(0, 64)] = $s2[$rng.Next(0, 64)] -bxor (1 -shl $rng.Next(0, 8))
    $m2 = [byte[]]$m.Clone(); $m2[$rng.Next(0, 32)] = $m2[$rng.Next(0, 32)] -bxor 0x80
    if ([UzSecp]::Pruefen($s2, $m, $k.Pub) -and -not [UzKrypto]::Gleich($s2, $s)) { $falsch++ }
    if ([UzSecp]::Pruefen($s, $m2, $k.Pub) -and -not [UzKrypto]::Gleich($m2, $m)) { $falsch++ }
}
Check ($ok -and $falsch -eq 0) "200 eigene Signaturen gültig; jedes veränderte Bit in Signatur oder Nachricht scheitert"
$k2 = New-Object UzSecp+Schluessel
Check (-not [UzKrypto]::Gleich($k.Pub, $k2.Pub) -and -not [UzSecp]::Pruefen($k.Signieren((Zufall 32)), (Zufall 32), $k2.Pub)) "Wegwerf-Schlüssel je Aufruf neu; fremder Schlüssel prüft nicht"
$k2.Dispose()
Check ($null -eq $k2.Signieren((Zufall 32))) "nach Dispose keine Signatur mehr (Schlüssel gelöscht)"
$f = 0
foreach ($l in @(0, 1, 31, 33, 63, 65, 128)) {
    try { if ([UzSecp]::Pruefen((Zufall $l), (Zufall 32), $k.Pub) -or [UzSecp]::Pruefen((Zufall 64), (Zufall $l), $k.Pub) -or [UzSecp]::Pruefen((Zufall 64), (Zufall 32), (Zufall $l))) { $f++ } } catch { $f++ }
}
Check ($f -eq 0 -and -not [UzSecp]::Pruefen($null, $null, $null) -and $null -eq $mSig.Invoke($null, [object[]]@([byte[]](Zufall 95), [byte[]](Zufall 32), [byte[]](Zufall 32)))) "falsche Längen und null: abgelehnt, bevor die Bibliothek sie sieht"
$f = 0
for ($i = 0; $i -lt 5000; $i++) {
    try { if ([UzSecp]::Pruefen((Zufall 64), (Zufall 32), (Zufall 32))) { $f++ } } catch { $f++ }
}
Check ($f -eq 0) "Fuzz: 5000 zufällige Signaturen/Schlüssel – keine gilt, kein Absturz"

"Nostr mit echter Signatur"
$sig = [UzNostr]::EchterSignierer()
$z = [UzNostr]::Hex((Zufall 16)); $inhalt = [Convert]::ToBase64String((Zufall 90)); $id = $null
$text = [UzNostr]::Ereignis($sig, 1700000000, $z, $inhalt, [ref]$id)
$ev = '["EVENT","uz",' + $text.Substring(9)
$still = $false
$e = [UzNostr]::Lesen($ev, 'uz', [ref]$still)
Check ($null -ne $sig -and $sig -is [UzNostr+EchtSignierer] -and $null -ne $e -and [UzNostr]::SignaturOk($e)) "Ereignis mit BIP-340-Signatur gebaut, gelesen, Signatur gültig"
$sigHex = [regex]::Match($ev, '"sig":"([0-9a-f]{128})"').Groups[1].Value
$anders = $ev.Replace($sigHex, $sigHex.Substring(0, 127) + $(if ($sigHex[127] -eq '0') { '1' } else { '0' }))
$e2 = [UzNostr]::Lesen($anders, 'uz', [ref]$still)
$fremd = [UzNostr]::Ereignis((New-Object UzNostr+TestSignierer), 1700000000, $z, $inhalt, [ref]$id)
$e3 = [UzNostr]::Lesen('["EVENT","uz",' + $fremd.Substring(9), 'uz', [ref]$still)
Check ($null -ne $e2 -and -not [UzNostr]::SignaturOk($e2) -and $null -ne $e3 -and -not [UzNostr]::SignaturOk($e3)) "veränderte Signatur und Null-Signatur: gelesen, aber ungültig"
# Treffpunkt mit Signaturprüfung: ein Ereignis mit falscher Signatur kommt nie bis zur Entschlüsselung.
$rahmen = New-Object 'System.Collections.Generic.List[byte[]]'
$wirt = New-Object UzTreff $true, $true, ([Func[long]] { 1700000000 }), ([Func[double]] { 1.0 }), ([Action[byte, byte[]]] { param($a, $n) $rahmen.Add([UzKrypto]::Kette([byte[]]@($a), $n)) }), ([Action[int, string]] { param($r, $t) })
[void]$wirt.Start(4000); $wirt.RelayDa(0, $true)
$kennung = Zufall 16
$wirt.Befehl([UzNetzRahmen]::EINLADUNG, [UzKrypto]::Kette($kennung, (Zufall 32)))
$k0 = $wirt.Zaehler[[UzTreff]::Z_KRYPTO]
$t = [UzNostr]::Ereignis((New-Object UzNostr+TestSignierer), 1700000000, [UzNostr]::Hex($kennung), [Convert]::ToBase64String((Zufall 120)), [ref]$id)
$wirt.VomRelay(0, '["EVENT","uz",' + $t.Substring(9))
Check ($wirt.Zaehler[[UzTreff]::Z_KRYPTO] -eq $k0 + 1 -and $wirt.Zaehler[[UzTreff]::Z_WIEDERHOLT] -eq 0) "Treffpunkt: Ereignis ohne gültige Signatur verworfen (gezählt), nicht einmal im Wiederholungsschutz"

"libdatachannel (WebRTC-Datenkanal über 127.0.0.1)"
Check ([UzRtc]::Bereit() -and [UzNetzLib]::Zustand('uzai-datachannel.dll') -eq 1) "geladen, Prüfsumme und Selbsttest (Angebot mit DTLS-Fingerabdruck) in Ordnung"
function Warte([scriptblock]$bis, [int]$ms = 15000) { $t0 = [Diagnostics.Stopwatch]::StartNew(); while ($t0.ElapsedMilliseconds -lt $ms) { if (& $bis) { return $true }; Start-Sleep -Milliseconds 20 }; return $false }
$a = New-Object UzDirekt 1, $true; $b = New-Object UzDirekt 2, $true
Check ($a.Neu(0, $true) -and -not $a.Neu(0, $true) -and -not $a.Neu(1, $true) -and -not $a.Neu(-1, $true)) "je Platz eine Verbindung, Plätze geprüft"
$o = $null; [void](Warte { ($script:o = $a.Lokal(0)) -ne $null })
$po = [UzSdp]::Pruefen($o, $true)
Check ($null -ne $po -and $po -match 'a=fingerprint:sha-256 ' -and $po -match 'm=application 9 ' -and $po -match 'c=IN IP4 0\.0\.0\.0' -and -not ($po -match 'a=candidate:.* tcp ')) "Angebot: Fingerabdruck, c= und Port neutral, nur UDP"
Check ($null -eq [UzSdp]::Pruefen($o, $false) -or -not ([UzSdp]::Pruefen($o, $false) -match '127\.0\.0\.1 ')) "ohne Erlaubnis: kein 127.0.0.1-Kandidat im Angebot"
Check ($null -eq $a.Lokal(0)) "das eigene Angebot nur einmal"
Check (-not $b.Fern(1, $po, $false) -and $b.Neu(1, $false) -and $b.Fern(1, $po, $true) -and -not $b.Fern(1, $po, $true)) "Antwortseite: erst Angebot, dann Kanal; nur einmal"
$an = $null; [void](Warte { ($script:an = $b.Lokal(1)) -ne $null })
$pa = [UzSdp]::Pruefen($an, $true)
Check ($null -ne $pa -and $pa -match 'a=setup:(active|passive)') "Antwort: geprüft, DTLS-Rolle fest"
Check ($a.Fern(0, $pa, $false)) "Antwort beim Anbieter gesetzt"
Check (Warte { $a.Zustand(0) -eq 1 -and $b.Zustand(1) -eq 1 }) "ICE, DTLS (Mbed TLS) und SCTP: Kanal auf beiden Seiten offen"
$an1 = New-Object 'System.Collections.Generic.List[object]'
$pumpe = [Action[int, byte[]]] { param($p, $m) $an1.Add(@($p, $m)) }
Check ($a.Senden(0, [byte[]](0x55, 2, 3, 4))) "Nachricht gesendet"
[void](Warte { $b.Pumpen($pumpe); $an1.Count -gt 0 })
Check ($an1.Count -eq 1 -and $an1[0][0] -eq 1 -and [BitConverter]::ToString($an1[0][1]) -eq '55-02-03-04') "kommt genau so auf Platz 1 an"
Check (-not $a.Senden(0, (New-Object byte[] 0)) -and -not $a.Senden(0, (New-Object byte[] 4097)) -and $a.Senden(0, (New-Object byte[] 4096)) -and -not $a.Senden(0, $null) -and -not $a.Senden(5, [byte[]](1))) "Senden: leer, über 4096 Byte, null, fremder Platz abgelehnt; 4096 geht"
# Die böse Gegenstelle spricht die Bibliothek direkt an (ohne unsere Grenzen): Text, Übergröße, Flut, eigene Kanäle.
$feld = { param($n) [UzRtc].GetField($n, [Reflection.BindingFlags]'NonPublic,Static').GetValue($null) }
$roh = & $feld 'senden'
$dcA = $a.GetType().GetField('dc', [Reflection.BindingFlags]'NonPublic,Instance').GetValue($a)[0]
$text0 = [Text.Encoding]::ASCII.GetBytes("hallo`0")
[void]$roh.Invoke($dcA, $text0, -1)
$gross = $roh.Invoke($dcA, (New-Object byte[] 70000), 70000)
$an1.Clear()
[void](Warte { $b.Pumpen($pumpe); $an1.Count -ge 2 } 4000)
$ersteLeer = $an1.Count -ge 2 -and $an1[1][1].Length -eq 0
Check ($ersteLeer -and $an1[0][1].Length -eq 4096) "Textnachricht kommt als leeres Feld an (zählt als Verstoß in Prüfmauer 1)"
Check ($gross -ne 0 -or @($an1 | Where-Object { $_[1].Length -gt 4096 }).Count -eq 0) "Übergröße (70000 Byte): schon beim Absender abgelehnt oder auf 4096 gekürzt"
$an1.Clear()
for ($i = 0; $i -lt 300; $i++) { [void]$roh.Invoke($dcA, [byte[]](0x55, 2, 7, [byte]($i % 256)), 4) }
$runden = 0; $max = 0
[void](Warte { $vor = $an1.Count; $b.Pumpen($pumpe); $script:runden++; $script:max = [Math]::Max($script:max, $an1.Count - $vor); $an1.Count -ge 300 } 10000)
Check ($an1.Count -eq 300 -and $max -le [UzDirekt]::JE_TAKT) "Flut: 300 Nachrichten, je Takt höchstens $([UzDirekt]::JE_TAKT) abgeholt (größter Schub $max)"
$kanal = & $feld 'kanal'
$init = New-Object UzRtc+KanalInit
$pcA = $a.GetType().GetField('pc', [Reflection.BindingFlags]'NonPublic,Instance').GetValue($a)[0]
$fremdDc = $kanal.Invoke($pcA, 'boese', [ref]$init)
$geloescht = Warte { $b.Pumpen($pumpe); [UzRtc]::Geschlossen($fremdDc) } 8000
Check ($fremdDc -gt 0 -and $geloescht -and $b.Zustand(1) -eq 1 -and $a.Zustand(0) -eq 1) "eigener Kanal der Gegenstelle: gemeldet und sofort geschlossen, der ausgehandelte bleibt offen"
$f = 0
for ($i = 0; $i -lt 2000; $i++) {
    try {
        $l = $rng.Next(1, 4097); $m = Zufall $l
        if (-not $a.Senden(0, $m)) { Start-Sleep -Milliseconds 5 }
        if ($i % 50 -eq 0) { $b.Pumpen($pumpe) }
        [void][UzRtc]::Holen($rng.Next(-5, 100000), (New-Object byte[] 8192)); [void][UzRtc]::Holen(1, (New-Object byte[] 100))
        [void][UzRtc]::Offen($rng.Next(-5, 100000)); [void][UzRtc]::Senden($rng.Next(-5, 100000), $m)
    } catch { $f++ }
}
Check ($f -eq 0) "Fuzz der P/Invoke-Schicht: 2000 Runden mit zufälligen Längen, Kennungen und Puffergrößen – kein Absturz"
$a.Weg(0); $a.Weg(0)
Check ($a.Zustand(0) -eq -1 -and (Warte { $b.Pumpen($pumpe); $b.Zustand(1) -eq 2 } 20000)) "Verbindung weg (zweimal geht): die Gegenseite merkt es (gescheitert/zu)"
$b.Stop(); $a.Stop()
Check ($true) "Aufräumen ohne Absturz (Rückrufe bleiben gehalten)"

"Leitung geschützt"
$kind = Join-Path ([IO.Path]::GetTempPath()) ("uzai-netzlib-" + [Guid]::NewGuid().ToString('N') + '.ps1')
$kindSrc = @'
$src = Get-Content -Raw -LiteralPath '@HELFER@'
$cs = [regex]::Match($src, "\`$script:ZimmerNetzSrc = @'\r?\n(?s)(.*?)\r?\n'@").Groups[1].Value
Add-Type -TypeDefinition $cs
Add-Type -TypeDefinition 'public static class Puts { [System.Runtime.InteropServices.DllImport("libc.so.6")] public static extern int puts(string s); [System.Runtime.InteropServices.DllImport("libc.so.6")] public static extern int fflush(System.IntPtr f); }'
$aus = [UzNetzLib]::AusgabeSchuetzen()
[void][Puts]::puts('FREMD'); [void][Puts]::fflush([IntPtr]::Zero)
[void][UzNetzRahmen]::Schreiben($aus, 1, [byte[]](7, 7))
'@
$kindSrc.Replace('@HELFER@', (Resolve-Path $args[0]).Path) | Set-Content -LiteralPath $kind -Encoding UTF8
$p = New-Object Diagnostics.ProcessStartInfo ((Get-Process -Id $PID).Path)
# pwsh als .NET-Werkzeug läuft als „dotnet pwsh.dll“: dann die DLL zuerst.
if ([IO.Path]::GetFileNameWithoutExtension($p.FileName) -eq 'dotnet') { $p.ArgumentList.Add([Environment]::GetCommandLineArgs()[0]) }
foreach ($x in @('-NoProfile', '-NonInteractive', '-File', $kind)) { $p.ArgumentList.Add($x) }
$p.RedirectStandardOutput = $true; $p.UseShellExecute = $false
$pr = [Diagnostics.Process]::Start($p)
$ms = New-Object IO.MemoryStream; $pr.StandardOutput.BaseStream.CopyTo($ms); $pr.WaitForExit()
Remove-Item -LiteralPath $kind -Force
Check ([BitConverter]::ToString($ms.ToArray()) -eq '03-00-00-00-01-07-07' -and [UzNetzLib]::Geschuetzt -eq $false) "nach dem Schutz: printf aus nativem Code landet im Nichts, auf der Leitung nur der Rahmen (verwalteten Konsolen-Code hat die Sandbox nicht)"

if ($fails -gt 0) { "Ergebnis: $fails Fehler"; exit 1 }
"Ergebnis: alles ok"
