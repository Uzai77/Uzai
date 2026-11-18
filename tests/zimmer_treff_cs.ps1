# Prüft den Treffpunkt der Zimmer-Sandbox (Punkt 131, docs/PLAN_ZIMMER_ONLINE.md Phase 3,
# docs/ZIMMER_SICHERHEIT.md W2/W4/W5): Verschlüsselung aus dem Betriebssystem (AES-256-GCM gegen den
# Testfall der Spezifikation, jedes veränderte Bit scheitert, ECDH P-256), der strenge JSON-Leser
# der Relay-Antworten (Regeln und Fuzz), Nostr-Ereignisse (Kennung nachgerechnet, jedes Feld
# geprüft), der SDP-Prüfer (Heimnetz-Adressen raus, Fuzz, Ergebnis bleibt gleich), die
# Zustandsmaschine mit Gastgeber, Gast und einem bösen Gast über ein nachgebautes Relay im
# Speicher (Anklopfen, Annahme, Sitzung, Wiederholung, falscher Schlüssel, Flut, Zurückziehen,
# Rauswurf) und die Leitung (Treffpunkt nur einmal, Test-Relay nur mit „--test“, ohne echte
# Signatur keine Verbindung). Läuft unter Linux (pwsh 7); CNG und AppContainer nur am Windows-PC
# (Uzai: Zimmer-Menü → Online → „Abschottung prüfen“ zeigt „Verschlüsselung in der Abschottung“).
#   pwsh -NoProfile -File tests/zimmer_treff_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = Get-Content -Raw $args[0]
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}
$cs = [regex]::Match($src, "\`$script:ZimmerNetzSrc = @'\r?\n(?s)(.*?)\r?\n'@").Groups[1].Value
Check ($cs.Contains('class UzTreff') -and $cs.Contains('class UzKrypto')) "Treffpunkt in der Quelle der Sandbox"

# Nur für diese Probe: ein Relay im Speicher (verteilt an alle außer den Absender, merkt sich
# alles) und die Abläufe in C#.
$probeCs = @'
public static class UzTreffProbe {
    public sealed class Seite {
        public UzTreff T;
        public List<byte[]> Rahmen = new List<byte[]>();
        public List<string> Raus = new List<string>();
        public byte[] Letzter(byte art) {
            for (int i = Rahmen.Count - 1; i >= 0; i--) if (Rahmen[i][0] == art) return UzKrypto.Teil(Rahmen[i], 1, Rahmen[i].Length - 1);
            return null;
        }
        public int Anzahl(byte art) { int n = 0; foreach (var r in Rahmen) if (r[0] == art) n++; return n; }
        public bool Stand(byte code) { foreach (var r in Rahmen) if (r[0] == UzNetzRahmen.STAND && r[1] == code) return true; return false; }
    }
    public static long Jetzt = 1700000000;
    public static double Uhr = 0;
    public static List<string> Alle = new List<string>();

    public static Seite Neu(bool gastgeber) {
        var s = new Seite();
        s.T = new UzTreff(gastgeber, true, delegate { return Jetzt; }, delegate { return Uhr; },
            delegate (byte art, byte[] n) { s.Rahmen.Add(UzKrypto.Kette(new byte[] { art }, n)); },
            delegate (int r, string t) { s.Raus.Add(t); });
        s.T.Start(4000);
        s.T.RelayDa(0, true);
        return s;
    }

    // Was eine Seite ans Relay schickte, geht als Ereignis an die anderen (wie ein Relay es tut).
    public static int Verteilen(Seite von, params Seite[] an) {
        int n = 0;
        foreach (string t in von.Raus.ToArray()) {
            var a = UzJson.Lesen(t) as List<object>;
            if (a == null || (string)a[0] != "EVENT") continue;
            string ev = "[\"EVENT\",\"uz\"," + t.Substring(9);
            Alle.Add(ev);
            foreach (var s in an) { s.T.VomRelay(0, ev); n++; }
        }
        von.Raus.Clear();
        return n;
    }

    public static string Hex(byte[] b) { return UzNostr.Hex(b); }
}
'@
try { Add-Type -TypeDefinition ($cs + "`n" + $probeCs.Replace('List<', 'System.Collections.Generic.List<')) -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; Check $true "übersetzt (C# 5, Warnungen als Fehler)" }
catch { Check $false ("übersetzt: " + $_.Exception.Message); "Ergebnis: $fails Fehler"; exit 1 }

$rng = New-Object Random 131
function Zufall([int]$n) { $b = New-Object byte[] $n; $rng.NextBytes($b); return , $b }

"Verschlüsselung (Betriebssystem bzw. .NET, nichts Eigenes)"
Check ([UzKrypto]::Selbsttest()) "Selbsttest: AES-256-GCM gleich dem Testfall 16 der Spezifikation, Bit-Fehler scheitert, ECDH gleich"
$k = Zufall 32; $aad = Zufall 20; $klar = Zufall 300
$kiste = [UzKrypto]::Zu($k, $aad, $klar)
Check ($kiste.Length -eq 12 + 300 + 16 -and [UzKrypto]::Gleich([UzKrypto]::Auf($k, $aad, $kiste), $klar)) "versiegeln und öffnen: Nonce | Geheimtext | Tag"
$alle = $true
foreach ($i in 0, 5, 11, 12, 100, 311, 312, 327) { $c = [byte[]]$kiste.Clone(); $c[$i] = $c[$i] -bxor 0x40; $alle = $alle -and $null -eq [UzKrypto]::Auf($k, $aad, $c) }
Check $alle "ein verändertes Bit (Nonce, Geheimtext, Tag): nicht zu öffnen"
$k2 = [byte[]]$k.Clone(); $k2[31] = $k2[31] -bxor 1
Check ($null -eq [UzKrypto]::Auf($k2, $aad, $kiste) -and $null -eq [UzKrypto]::Auf($k, (Zufall 20), $kiste) -and $null -eq [UzKrypto]::Auf($k, $aad, [UzKrypto]::Teil($kiste, 0, 28))) "falscher Schlüssel, andere Zusatzdaten, abgeschnitten: nicht zu öffnen"
Check (-not [UzKrypto]::Gleich([UzKrypto]::Zu($k, $aad, $klar), [UzKrypto]::Zu($k, $aad, $klar))) "jedes Versiegeln mit frischer Nonce"
$x = New-Object UzKrypto+Dh; $y = New-Object UzKrypto+Dh
$px = $x.Oeffentlich(); $py = $y.Oeffentlich()
Check ($px.Length -eq 65 -and $px[0] -eq 4 -and [UzKrypto]::PunktOk($px)) "öffentlicher Schlüssel: 0x04 | X | Y auf P-256"
$s1 = $x.Teilen($py, [byte[]](1), [byte[]](2)); $s2 = $y.Teilen($px, [byte[]](1), [byte[]](2))
Check ($s1.Length -eq 32 -and [UzKrypto]::Gleich($s1, $s2) -and -not [UzKrypto]::Gleich($s1, $y.Teilen($px, [byte[]](1), [byte[]](3)))) "ECDH: beide Seiten gleich, anderer Zusatz → anderer Schlüssel"
$schlecht = [byte[]]$py.Clone(); $schlecht[40] = $schlecht[40] -bxor 1
$null65 = New-Object byte[] 65; $null65[0] = 4
Check ($null -eq $x.Teilen($schlecht, [byte[]](1), [byte[]](2)) -and $null -eq $x.Teilen($null65, [byte[]](1), [byte[]](2)) -and -not [UzKrypto]::PunktOk($schlecht) -and
    $null -eq $x.Teilen([UzKrypto]::Teil($py, 0, 33), [byte[]](1), [byte[]](2))) "Punkt außerhalb der Kurve, Null, verkürzt: abgelehnt"
Check ($cs -match 'AesGcm' -and $cs -match 'BCryptEncrypt' -and -not ($cs -match 'AesManaged|RijndaelManaged|CipherMode\.CBC|CipherMode\.ECB|HMACSHA')) "nur AES-GCM (CNG bzw. .NET), kein CBC/ECB, kein HMAC-Eigenbau"

"JSON der Relays (streng)"
$gut = @('["EOSE","uz"]', '[1,-2,true,false,null,"a\"b\\u00e4"]', '{"a":[{"b":[]}]}', '  ["x" , 0 ]  ')
$schlecht = @('', '[', '[1,]', '[1 2]', '{"a":1,"a":2}', '[1.5]', '[1e3]', '[01]', '["a', '["\x01"]', '[tru]', '[1] x', '[[[[[[1]]]]]]', ('[' + ('1,' * 60) + '1]'),
    '{"a":}', '["\u12"]', '["\q"]', 'nul', '[1234567890123456]', ('["' + ('a' * 9000) + '"]'), ('[' + (' ' * 17000) + ']'))
$a = $true; foreach ($t in $gut) { $a = $a -and $null -ne [UzJson]::Lesen($t) }
Check $a "gültige Antworten gelesen"
$b = $true; foreach ($t in $schlecht) { $b = $b -and $null -eq [UzJson]::Lesen($t) }
Check $b "kaputt, doppelte Schlüssel, Kommazahlen, zu tief, zu viele, zu lang: abgelehnt"
$v = [UzJson]::Lesen('[1,-2,true,false,null,"a\"bä"]')
Check ($v[0] -is [long] -and $v[1] -eq -2 -and $v[2] -eq $true -and [object]::ReferenceEquals($v[4], [UzJson]::Null) -and $v[5] -eq "a`"bä") "Werte: Ganzzahl, Wahrheitswert, null, Text mit Maskierung"
$zeichen = '[]{}",:0123456789-truefalsn\ u'.ToCharArray()
$absturz = 0
for ($i = 0; $i -lt 4000; $i++) {
    $n = $rng.Next(0, 60); $sb = New-Object Text.StringBuilder
    for ($j = 0; $j -lt $n; $j++) { [void]$sb.Append($zeichen[$rng.Next(0, $zeichen.Length)]) }
    try { [void][UzJson]::Lesen($sb.ToString()) } catch { $absturz++ }
}
Check ($absturz -eq 0) "Fuzz: 4000 zufällige JSON-Schnipsel ohne Absturz"

"Nostr-Ereignisse"
$sig = New-Object UzNostr+TestSignierer
$z = [UzNostr]::Hex((Zufall 16)); $inhalt = [Convert]::ToBase64String((Zufall 90))
$id = $null
$text = [UzNostr]::Ereignis($sig, 1700000000, $z, $inhalt, [ref]$id)
$ev = '["EVENT","uz",' + $text.Substring(9)
$still = $false
$e = [UzNostr]::Lesen($ev, 'uz', [ref]$still)
Check ($null -ne $e -and $e.Id -eq $id -and $e.Z -eq $z -and $e.Inhalt -eq $inhalt -and $e.Zeit -eq 1700000000 -and $id.Length -eq 64) "Ereignis: gebaut, gelesen, Kennung nachgerechnet"
Check ($null -eq [UzNostr]::Ereignis($null, 1, $z, $inhalt, [ref]$id)) "ohne Signierer kein Ereignis"
Check ($null -eq [UzNostr]::EchterSignierer()) "ohne geladene libsecp256k1 kein echter Signierer (mit ihr: tests/netzlibs_cs.ps1)"
$abw = @(
    $ev.Replace('"kind":20777', '"kind":1'), $ev.Replace('"uz"', '"xx"'), $ev.Replace($inhalt, $inhalt.Substring(4) + 'AAAA'), $ev.Replace('"tags":[["z"', '"tags":[["p"'),
    $ev.Replace(',"sig"', ',"x":1,"sig"'), $ev.Replace('"created_at":1700000000', '"created_at":1700000001'), $ev.Replace('"created_at":1700000000', '"created_at":"1700000000"'),
    $ev.Replace($z, $z.ToUpper()), $ev.Replace('[["z","' + $z + '"]]', '[["z","' + $z + '"],["z","' + $z + '"]]'), ($ev.Substring(0, $ev.Length - 1) + ',1]'), $ev.Replace($inhalt, '<script>')
)
$c = $true; foreach ($t in $abw) { $s = $false; $c = $c -and $null -eq [UzNostr]::Lesen($t, 'uz', [ref]$s) }
Check $c "falsche Art, fremdes Abo, veränderter Inhalt/Zeit, fremdes Merkmal, Zusatzfeld, Großbuchstaben, zweites Merkmal: verworfen"
$s = $false
Check ($null -eq [UzNostr]::Lesen('["NOTICE","hallo"]', 'uz', [ref]$s) -and $s -and $null -eq [UzNostr]::Lesen('["WAS","x"]', 'uz', [ref]$s) -and -not $s) "NOTICE/OK/EOSE still, Unbekanntes ist Unsinn"
Check ([UzNostr]::RELAYS.Count -ge 3 -and @([UzNostr]::RELAYS | Where-Object { $_ -notmatch '^wss://[a-z0-9.-]+$' }).Count -eq 0) "feste Relays, nur wss://"
$f = 0
for ($i = 0; $i -lt 3000; $i++) {
    $t = $ev.ToCharArray(); for ($j = 0; $j -lt 1 + $rng.Next(0, 4); $j++) { $t[$rng.Next(0, $t.Length)] = [char]$rng.Next(32, 127) }
    # Die Signatur prüfen die Relays (nicht der Treffpunkt): eine Änderung nur darin zählt nicht.
    $ohneSig = { param($x) $x -replace '"sig":"[^"]*"', '' }
    try { $s = $false; $r = [UzNostr]::Lesen((-join $t), 'uz', [ref]$s); if ($null -ne $r -and (& $ohneSig (-join $t)) -ne (& $ohneSig $ev)) { $f++ } } catch { $f++ }
}
Check ($f -eq 0) "Fuzz: 3000 veränderte Ereignisse – keins geht durch (außer in der Signatur, die prüfen die Relays), keins stürzt ab"

"Verbindungsangebot (SDP)"
$angebot = [UzSdp]::TestAngebot($false)
$p = [UzSdp]::Pruefen($angebot, $false)
Check ($null -ne $p -and $p -match 'a=candidate:2 1 udp 1686052607 203\.0\.113\.7 50001 typ srflx raddr 0\.0\.0\.0 rport 0' -and -not ($p -match '192\.168')) "Heimnetz-Kandidat und raddr raus, öffentlicher bleibt"
Check (([UzSdp]::Pruefen($angebot, $true)) -match '192\.168\.1\.20 50000 typ host') "mit Erlaubnis bleibt der Heimnetz-Kandidat"
Check ([UzSdp]::Pruefen($p, $false) -eq $p) "geprüftes Angebot bleibt beim zweiten Prüfen gleich"
$boese = @(
    $angebot.Replace('m=application 9 UDP/DTLS/SCTP webrtc-datachannel', 'm=audio 9 UDP/TLS/RTP/SAVPF 111'),
    $angebot.Replace("a=setup:actpass`r`n", "a=setup:actpass`r`na=fingerprint:sha-256 " + ('AB:' * 31) + "AB`r`n"),
    $angebot.Replace('a=fingerprint:sha-256 ', 'a=fingerprint:sha-1 '), $angebot.Replace('v=0', 'v=1'), $angebot.Replace("a=mid:0`r`n", "a=mid:0`r`nb=AS:30`r`n"),
    $angebot.Replace("a=mid:0", "a=mid:0`u{0}"), $angebot.Replace('a=setup:actpass', 'a=setup:holdconn'), ($angebot + ('a=candidate:1 1 UDP 1 203.0.113.9 1 typ host' + "`r`n") * 20),
    $angebot.Replace('203.0.113.7 50001', '203.0.113.7 70001'), ($angebot * 3)
)
$d = $true; foreach ($t in $boese) { $d = $d -and $null -eq [UzSdp]::Pruefen($t, $false) }
Check $d "Audio/Video, zwei Fingerabdrücke, SHA-1, fremde Zeilen, Steuerzeichen, zu viele Kandidaten, zu groß: abgelehnt"
# Eine Sitzungsnummer mit 20 Ziffern passt nicht in 64 Bit: abgelehnt wie jeder andere Unsinn, nicht mit einer Ausnahme.
$gross = $null; $wurf = $false
try { $gross = [UzSdp]::Pruefen($angebot.Replace('o=- 4611731400430051336 ', 'o=- 99999999999999999999 '), $false) } catch { $wurf = $true }
Check (-not $wurf -and $null -eq $gross) "Sitzungsnummer über 64 Bit: abgelehnt, ohne Ausnahme"
$weg = @('1 1 UDP 1 abc.local 5000 typ host', '1 1 TCP 1 203.0.113.9 9 typ host tcptype active', '1 1 UDP 1 203.0.113.9 5000 typ relay raddr 1.2.3.4 rport 1',
    '1 1 UDP 1 10.0.0.1 5000 typ host', '1 1 UDP 1 100.64.1.1 5000 typ srflx', '1 1 UDP 1 fe80::1 5000 typ host', '1 1 UDP 1 fd00::5 5000 typ host', '1 1 UDP 1 ::ffff:10.0.0.1 5000 typ host',
    '1 1 UDP 1 127.0.0.1 5000 typ host', '1 1 UDP 1 169.254.3.3 5000 typ host')
$w = $true
foreach ($kand in $weg) {
    $r = [UzSdp]::Pruefen($angebot.Replace("a=end-of-candidates", "a=candidate:$kand`r`na=end-of-candidates"), $false)
    $w = $w -and $null -ne $r -and ([regex]::Matches($r, 'a=candidate:')).Count -eq 1
}
Check $w "Namen (mDNS), TCP, Relais, 10/8, Provider-NAT, fe80::, fd00::, eingebettetes IPv4, 127/8, 169.254: weggelassen"
Check ($null -eq [UzSdp]::Adresse('0x7f.1.1.1') -and $null -eq [UzSdp]::Adresse('127.1') -and $null -eq [UzSdp]::Adresse('01.2.3.4') -and $null -eq [UzSdp]::Adresse('fe80::1%eth0') -and
    $null -ne [UzSdp]::Adresse('2001:db8::1')) "Adressen nur in Normalform (keine Kurz- oder Sonderformen, keine Zonen)"
$f = 0; $zeilen = $angebot -split "`r`n"
for ($i = 0; $i -lt 3000; $i++) {
    $t = [Collections.Generic.List[string]]::new([string[]]$zeilen)
    switch ($rng.Next(0, 3)) {
        0 { $t.RemoveAt($rng.Next(0, $t.Count)) }
        1 { $t.Insert($rng.Next(1, $t.Count), $zeilen[$rng.Next(0, $zeilen.Count)]) }
        2 { $q = $rng.Next(0, $t.Count); $ch = $t[$q].ToCharArray(); if ($ch.Length -gt 0) { $ch[$rng.Next(0, $ch.Length)] = [char]$rng.Next(32, 127) }; $t[$q] = -join $ch }
    }
    try { $r = [UzSdp]::Pruefen(($t -join "`r`n"), $false); if ($null -ne $r -and ([UzSdp]::Pruefen($r, $false) -ne $r -or $r -match '192\.168|raddr 192')) { $f++ } } catch { $f++ }
}
Check ($f -eq 0) "Fuzz: 3000 veränderte Angebote – kein Absturz, Ergebnis immer wieder gleich, nie eine Heimnetz-Adresse"

"Treffpunkt: Gastgeber, Gast, böser Gast (Relay im Speicher)"
$wirt = [UzTreffProbe]::Neu($true)
$gast = [UzTreffProbe]::Neu($false)
$boes = [UzTreffProbe]::Neu($false)
$kennung = Zufall 16; $schluessel = Zufall 32
$wirt.T.Befehl([UzNetzRahmen]::EINLADUNG, [UzKrypto]::Kette($kennung, $schluessel))
Check ($wirt.Raus.Count -eq 1 -and $wirt.Raus[-1] -match '"#z":\["' + [UzNostr]::Hex($kennung) + '"\]') "Gastgeber abonniert das Postfach (zufällige Kennung)"
$wirt.Raus.Clear()
$gast.T.Befehl([UzNetzRahmen]::BESUCH, [UzKrypto]::Kette($kennung, $schluessel))
$klopfText = @($gast.Raus | Where-Object { $_.StartsWith('["EVENT"') })[0]
Check ($null -ne $klopfText -and -not $klopfText.Contains([UzNostr]::Hex($schluessel)) -and -not $klopfText.Contains([Convert]::ToBase64String($schluessel))) "Gast klopft an; der Schlüssel steht nie im Ereignis"
[void][UzTreffProbe]::Verteilen($gast, $wirt, $boes)
$kl = $wirt.Letzter([UzNetzRahmen]::KLOPFT)
Check ($null -ne $kl -and $kl.Length -eq 24 -and [UzKrypto]::Gleich([UzKrypto]::Teil($kl, 0, 16), $kennung)) "Gastgeber meldet Uzai: klopft (Kennung + Fingerabdruck), sonst nichts"
Check ($wirt.Raus.Count -eq 0) "vor der Annahme antwortet der Gastgeber nicht (keine IP, kein Schlüssel)"
# Wiederholung: dasselbe Ereignis noch einmal (anderes Relay) und ein erneutes Klopfen desselben Gastes.
$vorher = $wirt.T.Zaehler[[UzTreff]::Z_WIEDERHOLT]
$wirt.T.VomRelay(0, [UzTreffProbe]::Alle[0])
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 1 -and $wirt.T.Zaehler[[UzTreff]::Z_WIEDERHOLT] -eq $vorher + 1) "wiederholtes Ereignis: verworfen, kein zweites „klopft“"
[UzTreffProbe]::Jetzt += 16; $gast.T.Takt(); [void][UzTreffProbe]::Verteilen($gast, $wirt)
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 1) "Gast klopft nach 15 s erneut: derselbe Gast, kein zweites „klopft“"
# Böser Gast ohne Schlüssel: eigenes Postfach-Ereignis mit falschem Schlüssel an dieselbe Kennung.
$boes.T.Befehl([UzNetzRahmen]::BESUCH, [UzKrypto]::Kette($kennung, (Zufall 32)))
$k0 = $wirt.T.Zaehler[[UzTreff]::Z_KRYPTO]
[void][UzTreffProbe]::Verteilen($boes, $wirt)
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 1 -and $wirt.T.Zaehler[[UzTreff]::Z_KRYPTO] -eq $k0 + 1) "falscher Schlüssel: nicht zu öffnen, ungelesen verworfen"
# Annahme → Sitzung → Verbindungsangebote.
$wirt.T.Befehl([UzNetzRahmen]::ENTSCHEID, [UzKrypto]::Kette([UzKrypto]::Teil($kl, 16, 8), [byte[]](2)))
[void][UzTreffProbe]::Verteilen($wirt, $gast, $boes)
Check ($gast.Stand([UzTreff]::ST_ANGENOMMEN) -and -not $boes.Stand([UzTreff]::ST_ANGENOMMEN)) "Annahme: nur der Gast mit dem passenden Schlüssel erkennt sie"
[void][UzTreffProbe]::Verteilen($gast, $wirt, $boes)
[void][UzTreffProbe]::Verteilen($wirt, $gast, $boes)
$wv = $wirt.Letzter([UzNetzRahmen]::STAND)
Check ($wirt.Stand([UzTreff]::ST_VERBUNDEN) -and $wv[0] -eq [UzTreff]::ST_VERBUNDEN -and $wv[1] -eq 2 -and $gast.Stand([UzTreff]::ST_VERBUNDEN)) "Angebot und Antwort über den Sitzungsschlüssel: beide verbunden (Platz 2)"
Check (-not $boes.Stand([UzTreff]::ST_VERBUNDEN)) "der böse Gast kann die Sitzung nicht öffnen"
$ohneIp = $true; foreach ($t in [UzTreffProbe]::Alle) { $ohneIp = $ohneIp -and -not $t.Contains('203.0.113') -and -not $t.Contains('192.168') }
Check $ohneIp "Adressen gehen nur versiegelt über das Relay"
# Zweites Anklopfen mit dem abgefangenen Link (richtiger Schlüssel, anderer Gast): Gastgeber meldet
# es (Uzai weist ab, weil die Einladung benutzt ist), die laufende Sitzung bleibt unberührt.
$dieb = [UzTreffProbe]::Neu($false)
$dieb.T.Befehl([UzNetzRahmen]::BESUCH, [UzKrypto]::Kette($kennung, $schluessel))
[void][UzTreffProbe]::Verteilen($dieb, $wirt)
$kl2 = $wirt.Letzter([UzNetzRahmen]::KLOPFT)
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 2 -and -not [UzKrypto]::Gleich($kl2, $kl)) "abgefangener Link: eigener Fingerabdruck, Uzai entscheidet"
$wirt.T.Befehl([UzNetzRahmen]::ENTSCHEID, [UzKrypto]::Kette([UzKrypto]::Teil($kl2, 16, 8), [byte[]](0xFF)))
[void][UzTreffProbe]::Verteilen($wirt, $dieb)
[UzTreffProbe]::Jetzt += 16; $dieb.T.Takt(); [void][UzTreffProbe]::Verteilen($dieb, $wirt)
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 2 -and -not $dieb.Stand([UzTreff]::ST_ANGENOMMEN)) "abgewiesen: still, auch erneutes Klopfen bleibt still"
# Flut eines Dritten ohne Einladung: 400 Ereignisse in einer Sekunde (Unsinn und echte Form, eigener Schlüssel, aber
# ohne den Schlüssel der Einladung). Wiederholungsschutz und Postfach-Drossel zählen erst nach dem Entschlüsseln: Die
# Flut erreicht Uzai nicht und verdrängt nichts – ein echtes Klopfen danach kommt durch.
$w0 = $wirt.T.Zaehler[[UzTreff]::Z_WIEDERHOLT]
for ($i = 0; $i -lt 200; $i++) {
    $wirt.T.VomRelay(0, '["EVENT","uz",{"id":"' + ('0' * 64) + '"}]')
    $t = [UzNostr]::Ereignis($sig, [UzTreffProbe]::Jetzt, [UzNostr]::Hex($kennung), [Convert]::ToBase64String((Zufall 120)), [ref]$id)
    $wirt.T.VomRelay(0, '["EVENT","uz",' + $t.Substring(9))
}
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 2 -and $wirt.T.Zaehler[[UzTreff]::Z_WIEDERHOLT] -eq $w0) "Flut: nichts erreicht Uzai, nichts im Wiederholungsschutz"
[UzTreffProbe]::Jetzt += 3; [UzTreffProbe]::Uhr += 3
$nach = [UzTreffProbe]::Neu($false)
$nach.T.Befehl([UzNetzRahmen]::BESUCH, [UzKrypto]::Kette($kennung, $schluessel))
[void][UzTreffProbe]::Verteilen($nach, $wirt)
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 3) "nach der Flut: ein echtes Klopfen kommt durch"
# Je Relay bleibt eine Grenze: 1000 weitere Ereignisse in derselben Sekunde werden gebremst.
$g0 = $wirt.T.Zaehler[[UzTreff]::Z_GEDROSSELT]
for ($i = 0; $i -lt 1000; $i++) { $wirt.T.VomRelay(0, '["EVENT","uz",{"id":"' + ('0' * 64) + '"}]') }
Check ($wirt.T.Zaehler[[UzTreff]::Z_GEDROSSELT] -gt $g0 + 400 -and $wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 3) "Flut je Relay: gebremst"
# Zu alt: ein echtes Klopfen, das erst nach 3 Minuten ankommt.
$spaet = [UzTreffProbe]::Neu($false)
$spaet.T.Befehl([UzNetzRahmen]::BESUCH, [UzKrypto]::Kette($kennung, $schluessel))
[UzTreffProbe]::Jetzt += 180; [UzTreffProbe]::Uhr += 60
[void][UzTreffProbe]::Verteilen($spaet, $wirt)
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 3) "zu alte Nachricht (über 2 Minuten): verworfen"
# Fremdes Postfach und Zurückziehen.
$wirt.T.Befehl([UzNetzRahmen]::ZURUECK, $kennung)
$neu = [UzTreffProbe]::Neu($false)
$neu.T.Befehl([UzNetzRahmen]::BESUCH, [UzKrypto]::Kette($kennung, $schluessel))
[void][UzTreffProbe]::Verteilen($neu, $wirt)
Check ($wirt.Anzahl([UzNetzRahmen]::KLOPFT) -eq 3) "zurückgezogene Einladung: Postfach zu, Klopfen bleibt ungelesen"
# Rauswurf: Uzai schließt Platz 2 → der Gast erfährt es über die Sitzung.
$wirt.T.Befehl([UzNetzRahmen]::SCHLIESSEN, [byte[]](2))
[void][UzTreffProbe]::Verteilen($wirt, $gast)
Check ($gast.Stand([UzTreff]::ST_ZU)) "Rauswerfen: der Gast bekommt „zu“"
# Gast: keine Antwort nach 8 Versuchen.
$einsam = [UzTreffProbe]::Neu($false)
$einsam.T.Befehl([UzNetzRahmen]::BESUCH, [UzKrypto]::Kette((Zufall 16), (Zufall 32)))
for ($i = 0; $i -lt 9; $i++) { [UzTreffProbe]::Jetzt += 16; $einsam.T.Takt() }
Check ($einsam.Stand([UzTreff]::ST_KEINE_ANTWORT) -and @($einsam.Raus | Where-Object { $_.StartsWith('["EVENT"') }).Count -eq 8) "Gast: höchstens 8-mal klopfen, dann „keine Antwort“"
$wirt.T.Befehl([UzNetzRahmen]::TREFF_ZAEHLER, (New-Object byte[] 0))
Check ($wirt.Letzter([UzNetzRahmen]::TREFF_ZAEHLER).Length -eq 24) "Zähler: sechs Werte"
# Böser Gast schickt die Fuzz-Ladung direkt an den Gastgeber: Ereignisse mit zufälligem Inhalt.
$wirt2 = [UzTreffProbe]::Neu($true)
$wirt2.T.Befehl([UzNetzRahmen]::EINLADUNG, [UzKrypto]::Kette($kennung, $schluessel))
$f = 0
for ($i = 0; $i -lt 1500; $i++) {
    [UzTreffProbe]::Uhr += 1
    $roh = Zufall (2 + $rng.Next(0, 400))
    if ($rng.Next(0, 2) -eq 0) { $roh[0] = 1; $roh[1] = [byte]$rng.Next(1, 5) }
    $t = [UzNostr]::Ereignis($sig, [UzTreffProbe]::Jetzt, [UzNostr]::Hex($kennung), [Convert]::ToBase64String($roh), [ref]$id)
    try { $wirt2.T.VomRelay(0, '["EVENT","uz",' + $t.Substring(9)) } catch { $f++ }
}
Check ($f -eq 0 -and $wirt2.Anzahl([UzNetzRahmen]::KLOPFT) -eq 0) "Fuzz: 1500 Ereignisse mit zufälligem Inhalt – kein Absturz, nichts erreicht Uzai"
Check ([UzTreff]::BefehlOk([UzNetzRahmen]::BESUCH, (New-Object byte[] 48), $true) -eq $false -and [UzTreff]::BefehlOk([UzNetzRahmen]::EINLADUNG, (New-Object byte[] 48), $false) -eq $false -and
    [UzTreff]::BefehlOk([UzNetzRahmen]::ENTSCHEID, (New-Object byte[] 9), $true) -and -not [UzTreff]::BefehlOk([UzNetzRahmen]::ENTSCHEID, [byte[]](0, 0, 0, 0, 0, 0, 0, 0, 8), $true)) "Befehle nur in Form und Rolle"

"Leitung"
function Rahmen([int]$art, [byte[]]$nutz) { $n = $nutz.Length + 1; return , ([byte[]](@(($n -band 0xFF), (($n -shr 8) -band 0xFF), 0, 0, $art) + $nutz)) }
function Lauf([byte[]]$ein, [bool]$test, [bool]$gastgeber = $true) {
    $i = New-Object IO.MemoryStream (, $ein); $o = New-Object IO.MemoryStream
    $code = [UzaiZimmerNetz]::Netz($i, $o, $gastgeber, $test, [Func[double]] { 1.0 })
    return @{ code = $code; aus = $o.ToArray() }
}
Check ((Lauf ([byte[]]((Rahmen 13 ([byte[]](0xA0, 0x0F))) + (Rahmen 5 @()))) $false).code -eq 3) "Test-Relay ohne „--test“: Sandbox beendet sich"
Check ((Lauf ([byte[]]((Rahmen 14 (New-Object byte[] 48)) + (Rahmen 5 @()))) $true).code -eq 3) "Einladung vor dem Start des Treffpunkts: Sandbox beendet sich"
Check ((Lauf ([byte[]]((Rahmen 13 ([byte[]](0, 0))) + (Rahmen 13 ([byte[]](0, 0))))) $true).code -eq 3) "Treffpunkt nur einmal"
Check ((Lauf ([byte[]]((Rahmen 13 ([byte[]](0, 0))) + (Rahmen 16 (New-Object byte[] 48)))) $true $true).code -eq 3) "Besuch beim Gastgeber: Sandbox beendet sich"
$st = (Lauf ([byte[]]((Rahmen 13 ([byte[]](0, 0))) + (Rahmen 1 @()))) $true).aus
$hat = $false
for ($p = 0; $p + 5 -le $st.Length; ) { $n = $st[$p] + 256 * $st[$p + 1]; if ($st[$p + 4] -eq 19 -and $n -eq 4 -and $st[$p + 5] -eq [UzTreff]::ST_SIGNATUR_FEHLT) { $hat = $true }; $p += 4 + $n }
Check $hat "feste Relays ohne echten Signierer: „Signatur fehlt“, keine Verbindung"

if ($fails -gt 0) { "Ergebnis: $fails Fehler"; exit 1 }
"Ergebnis: alles ok"
