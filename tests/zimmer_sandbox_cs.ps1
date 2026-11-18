# Prüft die Sandbox fürs Zimmer-Netz aus helper/uzai-helper.ps1 (Punkt 131, docs/ZIMMER_SICHERHEIT.md
# Abschnitt 6, docs/PLAN_ZIMMER_ONLINE.md Phase 2): Die Quelle muss als C# 5 ohne Warnungen
# übersetzbar sein; Rahmen lesen/schreiben (auch mit Zufall und Kaputtem); die Echo-Schleife;
# Prüfmauer 1 (UzNetzSchema) Regel für Regel und mit Fuzz; dieselben Pakete wie
# tests/logic_zimmer_netz.gd mit demselben Urteil; die Sitzungs-Schleife (Drossel, Rauswurf,
# Ausgehendes nur nach Schema, Unerwartetes beendet sie); Auftrag und Auswertung des Selbsttests;
# feste Werte (nur internetClient, Handle-Liste, Job-Objekt, Befehlszeilen) und der Helfer-Zweig
# „-ZimmerNetz“. Läuft unter Linux (pwsh 7); AppContainer und Prozessstart selbst gehen nur am
# Windows-PC (Uzai: Zimmer-Menü → Online → „Abschottung prüfen“).
#   pwsh -NoProfile -File tests/zimmer_sandbox_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = Get-Content -Raw $args[0]
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}
$cs = [regex]::Match($src, "\`$script:ZimmerNetzSrc = @'\r?\n(?s)(.*?)\r?\n'@").Groups[1].Value
Check ($cs.Length -gt 10000) "Quelle des Zimmer-Netzes gefunden"

# Nur für diese Probe: dieselben Pakete wie tests/logic_zimmer_netz.gd (_vektor_urteile), in C#.
$vektorCs = @'
public static class UzNetzVektoren {
    public static readonly string[] BASIS = {
        "5502010078563412",
        "55020240010000c20150fb2c01",
        "55020302",
        "55020408",
        "5502050101010101",
        "550207",
        "5502060c0a00c2946600e8e0d100e8e0d100e8e0d100e8e0d100008c0a640200000101" + "00ffff010000000000" + "05030201" + "00ff031122330000",
    };
    static readonly int[] GRENZEN = { 0, 1, 2, 3, 299, 300, 301, 1050, 1051, 1571, 1572, 3142, 3143, 1799, 1800, 6500, 6501, 65535 - 3142, 65535 - 3141,
        65535 - 1570, 65535 - 1571, 32768, 65535 };
    static uint xs;

    static uint N() { xs ^= xs << 13; xs ^= xs >> 17; xs ^= xs << 5; return xs; }

    public static byte[] Hex(string s) {
        var b = new byte[s.Length / 2];
        for (int i = 0; i < b.Length; i++) b[i] = System.Convert.ToByte(s.Substring(2 * i, 2), 16);
        return b;
    }

    public static string Urteile(uint saat, int anzahl) {
        xs = saat;
        var basis = new byte[BASIS.Length][];
        for (int i = 0; i < BASIS.Length; i++) basis[i] = Hex(BASIS[i]);
        uint h = 2166136261;
        int an = 0;
        byte[] grenz = { 0, 1, 0x7F, 0x80, 0xFE, 0xFF };
        for (int i = 0; i < anzahl; i++) {
            byte[] b;
            switch (N() % 8) {
                case 0: {
                    int n = (int)(N() % 40);
                    b = new byte[n];
                    for (int k = 0; k < n; k++) b[k] = (byte)(N() & 0xFF);
                    break;
                }
                case 1: {
                    int n = 3 + (int)(N() % 40);
                    b = new byte[n];
                    b[0] = UzNetzSchema.MAGIC; b[1] = UzNetzSchema.VERSION; b[2] = (byte)(N() % 9);
                    for (int k = 3; k < n; k++) b[k] = (byte)(N() & 0xFF);
                    break;
                }
                case 2: {
                    b = (byte[])basis[N() % (uint)basis.Length].Clone();
                    uint m = 1 + N() % 3;
                    for (uint k = 0; k < m; k++) { int at = (int)(N() % (uint)b.Length); b[at] ^= (byte)(1 << (int)(N() % 8)); }
                    break;
                }
                case 3: {
                    byte[] q = basis[N() % (uint)basis.Length];
                    int n = (int)(N() % (uint)q.Length);
                    b = new byte[n];
                    System.Array.Copy(q, b, n);
                    break;
                }
                case 4: {
                    byte[] q = basis[N() % (uint)basis.Length];
                    b = new byte[q.Length + 1];
                    System.Array.Copy(q, b, q.Length);
                    b[q.Length] = (byte)(N() & 0xFF);
                    break;
                }
                case 5: {
                    b = (byte[])basis[N() % (uint)basis.Length].Clone();
                    int at = (int)(N() % (uint)b.Length);
                    b[at] = grenz[N() % 6];
                    break;
                }
                case 6: {
                    b = (byte[])basis[N() % (uint)basis.Length].Clone();
                    if (b.Length < 5) b = (byte[])basis[1].Clone();
                    int at = 3 + (int)(N() % (uint)(b.Length - 3));
                    b[at] = (byte)(N() % 40);
                    break;
                }
                default: {
                    b = (byte[])basis[N() % (uint)basis.Length].Clone();
                    if (b.Length < 5) b = (byte[])basis[1].Clone();
                    int at = 3 + (int)(N() % (uint)(b.Length - 4));
                    int g = GRENZEN[N() % (uint)GRENZEN.Length];
                    b[at] = (byte)(g & 0xFF);
                    b[at + 1] = (byte)(g >> 8);
                    break;
                }
            }
            bool vg = (N() & 1) == 1;
            bool ok = UzNetzSchema.Pruefen(b, vg);
            if (ok) an++;
            h = (h ^ (uint)(ok ? 0x31 : 0x30)) * 16777619;
        }
        return "0x" + h.ToString("x8") + "/" + an;
    }
}
'@
try { Add-Type -TypeDefinition ($cs + "`n" + $vektorCs) -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; Check $true "übersetzt (C# 5, Warnungen als Fehler)" }
catch { Check $false ("übersetzt: " + $_.Exception.Message); "Ergebnis: $fails Fehler"; exit 1 }

function Rahmen([byte]$art, [byte[]]$nutz) {
    $ms = New-Object IO.MemoryStream
    [void][UzNetzRahmen]::Schreiben($ms, $art, $nutz)
    return , $ms.ToArray()
}
function Lies([byte[]]$b) {
    $ms = New-Object IO.MemoryStream (, $b)
    $art = [byte]0
    $r = [UzNetzRahmen]::Lesen($ms, [ref]$art)
    return @{ nutz = $r; art = $art }
}
function Alle([byte[]]$b) {
    $ms = New-Object IO.MemoryStream (, $b)
    $out = @()
    while ($true) {
        $art = [byte]0
        $r = [UzNetzRahmen]::Lesen($ms, [ref]$art)
        if ($null -eq $r) { break }
        $out += , @{ art = $art; nutz = $r }
    }
    return , $out
}
function Hex([string]$h) { return , [UzNetzVektoren]::Hex($h) }
function Mit([byte[]]$b, [int]$at, [int]$v) { $c = [byte[]]$b.Clone(); $c[$at] = [byte]$v; return , $c }

"Rahmen"
$r = Rahmen 1 ([byte[]](1, 2, 3))
Check ($r.Length -eq 8 -and $r[0] -eq 4 -and $r[4] -eq 1) "Ping mit 3 Byte: 4 Byte Länge, Art, Nutzlast"
$l = Lies $r
Check ($l.art -eq 1 -and $l.nutz.Length -eq 3 -and $l.nutz[2] -eq 3) "Rahmen kommt genau zurück"
$gross = New-Object byte[] 8192
Check ((Lies (Rahmen 1 $gross)).nutz.Length -eq 8192) "8 KiB Nutzlast gehen"
$ms = New-Object IO.MemoryStream
Check (-not [UzNetzRahmen]::Schreiben($ms, 1, (New-Object byte[] 8193))) "mehr als 8 KiB werden gar nicht geschrieben"
Check (-not [UzNetzRahmen]::Schreiben($ms, 22, (New-Object byte[] 1)) -and -not [UzNetzRahmen]::Schreiben($ms, 0, (New-Object byte[] 1))) "unbekannte Art wird nicht geschrieben"
Check ($null -eq (Lies ([byte[]](2, 0x20, 0, 0, 1))).nutz) "Länge über 8 KiB: verworfen, ohne zu lesen"
Check ($null -eq (Lies ([byte[]](0, 0, 0, 0))).nutz) "Länge 0: verworfen"
Check ($null -eq (Lies ([byte[]](2, 0, 0, 0, 22, 1))).nutz) "unbekannte Art: verworfen"
Check ($null -eq (Lies ([byte[]](5, 0, 0, 0, 1, 1))).nutz) "abgeschnitten: verworfen"
Check ($null -eq (Lies ([byte[]](0xFF, 0xFF, 0xFF, 0xFF, 1))).nutz) "riesige Länge (4 GiB): verworfen"

"Kindprozess: Echo-Schleife"
function Schleife([byte[]]$ein) {
    $i = New-Object IO.MemoryStream (, $ein)
    $o = New-Object IO.MemoryStream
    $code = [UzaiZimmerNetz]::Schleife($i, $o)
    return @{ code = $code; aus = $o.ToArray() }
}
$zufall = New-Object byte[] 8000
(New-Object Random 131).NextBytes($zufall)
$ein = New-Object Collections.Generic.List[byte]
$ein.AddRange([byte[]](Rahmen 1 ([byte[]]@())))
$ein.AddRange([byte[]](Rahmen 1 $zufall))
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("uzai-zn-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$auftrag = [UzZimmerNetz]::Auftrag($tmp, (Join-Path $tmp 'fehlt.txt'), $tmp, (Join-Path $tmp 'w.txt'))
$ein.AddRange([byte[]](Rahmen 3 ([Text.Encoding]::UTF8.GetBytes($auftrag))))
$ein.AddRange([byte[]](Rahmen 5 ([byte[]]@())))
$s = Schleife $ein.ToArray()
Check ($s.code -eq 0) "Ende → Code 0"
$aus = Alle $s.aus
Check ($aus[0].art -eq 2 -and $aus[0].nutz.Length -eq 0) "leerer Ping → leerer Pong"
Check ($aus[1].art -eq 2 -and [UzZimmerNetz]::Gleich($aus[1].nutz, $zufall)) "8000 Byte Zufall kommen genau zurück"
$antwort = [Text.Encoding]::UTF8.GetString($aus[2].nutz)
Check ($aus[2].art -eq 4 -and $antwort -match '(?m)^ordner=1$' -and $antwort -match '(?m)^lesen=0$') "Selbsttest antwortet (hier ohne Container: eigener Ordner ja, fehlende Datei nein)"
Check (@($antwort.Trim() -split "`n").Count -eq 8 -and $antwort -match '(?m)^krypto=1$' -and $antwort -match '(?m)^secp=2$' -and $antwort -match '(?m)^rtc=2$') "Selbsttest: genau acht Proben (Verschlüsselung; ohne Netz-Bibliotheken: „fehlt“)"
Remove-Item -Recurse -Force $tmp
Check ((Schleife (Rahmen 2 ([byte[]](1)))).code -eq 3) "Pong von der anderen Seite: Leitung zu (Code 3)"
Check ((Schleife (Rahmen 4 ([byte[]](1)))).code -eq 3) "Ergebnis von der anderen Seite: Leitung zu"
Check ((Schleife (Rahmen 8 ([byte[]](1)))).code -eq 3) "Sitzungs-Rahmen im Echo-Modus: Leitung zu"
Check ((Schleife ([byte[]]@())).code -eq 3) "Leitung ohne Ende: Code 3"
Check ([UzaiZimmerNetz]::Main(@()) -eq 2 -and [UzaiZimmerNetz]::Main(@('--netz')) -eq 2 -and [UzaiZimmerNetz]::Main(@('--echo', 'x')) -eq 2 -and
    [UzaiZimmerNetz]::Main(@('--netz', 'gastgeber', '--echt')) -eq 2 -and [UzaiZimmerNetz]::Main(@('--netz', 'admin', '--test')) -eq 2 -and
    [UzaiZimmerNetz]::Main(@('--netz', 'Gast', '--test')) -eq 2 -and [UzaiZimmerNetz]::Main(@('--netz', 'gast', '--live')) -eq 2 -and
    [UzaiZimmerNetz]::Main(@('--netz', 'gast', '--test', 'x')) -eq 2) 'nur „--echo“, „--netz gastgeber|gast --test“ und „--netz gastgeber|gast“ starten etwas'

"Prüfmauer 1 (UzNetzSchema)"
$pos = Hex '55020240010000c20150fb2c01'
Check ([UzNetzSchema]::Pruefen($pos, $false)) "gültige Position"
function U16([byte[]]$b, [int]$at, [int]$v) { $c = [byte[]]$b.Clone(); $c[$at] = [byte]($v -band 0xFF); $c[$at + 1] = [byte](($v -shr 8) -band 0xFF); return , $c }
Check ([UzNetzSchema]::Pruefen((U16 $pos 3 1050), $false) -and -not [UzNetzSchema]::Pruefen((U16 $pos 3 1051), $false)) "x: 1050 ja, 1051 nein"
Check ([UzNetzSchema]::Pruefen((U16 $pos 5 300), $false) -and -not [UzNetzSchema]::Pruefen((U16 $pos 5 301), $false)) "y: 300 ja, 301 nein"
Check ([UzNetzSchema]::Pruefen((U16 $pos 9 (65536 - 3142)), $false) -and -not [UzNetzSchema]::Pruefen((U16 $pos 9 (65536 - 3143)), $false) -and -not [UzNetzSchema]::Pruefen((U16 $pos 9 32768), $false)) "Blick: ±3142, nicht −32768"
Check (-not [UzNetzSchema]::Pruefen((U16 $pos 11 1572), $false)) "Neigung über 1571: nein"
Check (-not [UzNetzSchema]::Pruefen((Mit $pos 0 0x7B), $false) -and -not [UzNetzSchema]::Pruefen((Mit $pos 1 1), $false) -and -not [UzNetzSchema]::Pruefen((Mit $pos 2 8), $false)) "falscher Kopf, alte Fassung, unbekannte Art"
Check (-not [UzNetzSchema]::Pruefen($pos[0..11], $false) -and -not [UzNetzSchema]::Pruefen([byte[]]($pos + 0), $false) -and -not [UzNetzSchema]::Pruefen($null, $false) -and -not [UzNetzSchema]::Pruefen([byte[]]@(), $false)) "zu kurz, zu lang, null, leer"
Check ([UzNetzSchema]::Pruefen((Hex '55020306'), $false) -and -not [UzNetzSchema]::Pruefen((Hex '55020307'), $false)) "Emote 0–6"
Check ([UzNetzSchema]::Pruefen((Hex '5502040b'), $false) -and -not [UzNetzSchema]::Pruefen((Hex '5502040c'), $false)) "Schnellsatz 0–11"
$fig = Hex ('550205' + ('00' * 5))
$fgut = $true
for ($i = 0; $i -lt 5; $i++) {
    $n = [UzNetzSchema]::FIGUR_ANZAHL[$i]
    $fgut = $fgut -and [UzNetzSchema]::Pruefen((Mit $fig (3 + $i) ($n - 1)), $false) -and -not [UzNetzSchema]::Pruefen((Mit $fig (3 + $i) $n), $false)
}
Check $fgut "Figur: jedes Feld genau bis zur letzten Option"
$z = Hex ([UzNetzVektoren]::BASIS[6])
Check ([UzNetzSchema]::Pruefen($z, $true) -and -not [UzNetzSchema]::Pruefen($z, $false)) "Zimmer nur vom Gastgeber"
$zf = @((Mit $z 3 7), (Mit $z 3 21), (Mit $z 5 9), (Mit $z 9 8), (Mit $z 25 5), (Mit $z 26 5), (U16 $z 27 1799), (U16 $z 27 6501), (Mit $z 29 201),
    (U16 $z 30 3), (U16 $z 30 1), (Mit $z 32 ([UzNetzSchema]::KATALOG)), (Mit $z 33 12), (Mit $z 34 10), (Mit $z 35 4), (Mit $z 36 16), (Mit $z 37 8), (Mit $z 38 4),
    (Mit $z 39 1), (Mit $z 42 1), (Mit $z 43 1))
$zab = 0
foreach ($b in $zf) { if (-not [UzNetzSchema]::Pruefen($b, $true)) { $zab++ } }
Check ($zab -eq $zf.Count) "Zimmer: Größe, Boden, Wand, Zeit, Wetter, Kelvin, Helligkeit, Anzahl, Katalog, Feld, Drehung, Variante, Stufe, Merkmale, Farbe ohne Merkmal, Reserve ($zab/$($zf.Count))"
$voll = New-Object byte[] ([UzNetzSchema]::MAX_NACHRICHT)
[Array]::Copy($z, $voll, 32)
$voll[30] = 0x2C; $voll[31] = 1
for ($i = 0; $i -lt 300; $i++) { $o = 32 + 12 * $i; $voll[$o + 4] = 0xFF; $voll[$o + 5] = 0xFF }
Check ([UzNetzSchema]::Pruefen($voll, $true) -and -not [UzNetzSchema]::Pruefen([byte[]]($voll + (New-Object byte[] 12)), $true)) "300 Möbel ja (3632 Byte), 301 nein"
Check ([UzNetzSchema]::MAX_NACHRICHT -eq 3632 -and [UzNetzSchema]::MAX_NACHRICHT + 1 -lt [UzNetzRahmen]::MAX) "größte Nachricht 3632 Byte, passt in einen Rahmen"
$json = [Text.Encoding]::UTF8.GetBytes('{"v":1,"a":"chat","d":{"text":"hi"}}')
Check (-not [UzNetzSchema]::Pruefen($json, $true)) "alte JSON-Nachricht (Chat): abgelehnt"
$alle = 0
foreach ($h in [UzNetzVektoren]::BASIS) { if ([UzNetzSchema]::Pruefen((Hex $h), $true)) { $alle++ } }
Check ($alle -eq 7) "alle sieben Grundformen gültig"
$u = [UzNetzVektoren]::Urteile(0x13112026, 6000)
$soll = [regex]::Match((Get-Content -Raw (Join-Path (Split-Path -Parent $args[0]) '../tests/logic_zimmer_netz.gd')), 'VEKTOR_SOLL := "([^"]+)"').Groups[1].Value
Check ($u -eq $soll) "6000 Pakete: dasselbe Urteil wie Uzai (Fingerabdruck $u, Uzai $soll)"

"Fuzz"
$rnd = New-Object Random 75
$schlecht = 0
for ($n = 0; $n -lt 3000; $n++) {
    $b = New-Object byte[] ($rnd.Next(0, 300))
    $rnd.NextBytes($b)
    if ($b.Length -gt 4 -and $rnd.Next(2) -eq 0) { $b[1] = 0; $b[2] = 0; $b[3] = 0; $b[0] = [byte]$rnd.Next(1, 40); $b[4] = [byte]$rnd.Next(0, 13) }
    try { $c = (Schleife $b).code; if ($c -ne 0 -and $c -ne 3) { $schlecht++ } } catch { $schlecht++ }
}
Check ($schlecht -eq 0) "3000 × Zufallsbytes: die Echo-Schleife endet immer sauber (0 oder 3), ohne Ausnahme"
$schlecht = 0
for ($n = 0; $n -lt 4000; $n++) {
    $b = New-Object byte[] ($rnd.Next(0, 4000))
    $rnd.NextBytes($b)
    if ($b.Length -ge 3 -and $rnd.Next(3) -gt 0) { $b[0] = 0x55; $b[1] = 2; $b[2] = [byte]$rnd.Next(0, 9) }
    try { [void][UzNetzSchema]::Pruefen($b, ($rnd.Next(2) -eq 0)) } catch { $schlecht++ }
}
Check ($schlecht -eq 0) "4000 × Zufallspakete bis 4000 Byte: Prüfmauer 1 urteilt ohne Ausnahme"

"Sitzung (Prüfmauer 1 mit Test-Gegenstelle)"
$script:uhrWert = 0.0
function Sitzung([byte[]]$ein, [bool]$gastgeber) {
    $i = New-Object IO.MemoryStream (, $ein)
    $o = New-Object IO.MemoryStream
    $code = [UzaiZimmerNetz]::Netz($i, $o, $gastgeber, $true, [Func[double]] { 10.0 })
    return @{ code = $code; aus = (Alle $o.ToArray()) }
}
function Platz([byte]$art, [byte]$platz, [byte[]]$m) { return , (Rahmen $art ([byte[]](@($platz) + $m))) }
$ein = New-Object Collections.Generic.List[byte]
$gut = @($pos, (Hex '55020302'), (Hex '5502040b'), (Hex '550207'), (Hex '5502010078563412'))
foreach ($g in $gut) { $ein.AddRange([byte[]](Platz 8 1 $g)) }
$boese = @($z, $json, $pos[0..11], (Mit $pos 1 1), (Hex '55020307'), [byte[]]@())
foreach ($b in $boese) { $ein.AddRange([byte[]](Platz 8 1 $b)) }
for ($i = 0; $i -lt 60; $i++) { $ein.AddRange([byte[]](Platz 8 2 $pos)) }
for ($i = 0; $i -lt 40; $i++) { $ein.AddRange([byte[]](Platz 8 3 ([byte[]](0x55, 2, 2, $i)))) }
$ein.AddRange([byte[]](Platz 6 1 $z))
$ein.AddRange([byte[]](Platz 6 1 $json))
$ein.AddRange([byte[]](Rahmen 11 ([byte[]]@())))
$ein.AddRange([byte[]](Rahmen 12 ([byte[]](3))))
$ein.AddRange([byte[]](Platz 8 3 $pos))
$ein.AddRange([byte[]](Rahmen 5 ([byte[]]@())))
$s = Sitzung $ein.ToArray() $true
Check ($s.code -eq 0) "Sitzung endet mit Code 0"
$empf1 = @($s.aus | Where-Object { $_.art -eq 7 -and $_.nutz[0] -eq 1 })
$empf2 = @($s.aus | Where-Object { $_.art -eq 7 -and $_.nutz[0] -eq 2 })
$empf3 = @($s.aus | Where-Object { $_.art -eq 7 -and $_.nutz[0] -eq 3 })
$raus = @($s.aus | Where-Object { $_.art -eq 10 })
$tr = @($s.aus | Where-Object { $_.art -eq 9 })
$zl = @($s.aus | Where-Object { $_.art -eq 11 })
Check ($empf1.Count -eq 5) "Platz 1: genau die fünf gültigen Nachrichten kommen durch (Zimmer vom Gast, JSON, kaputt, alt, unbekannt, leer nicht)"
Check ([UzZimmerNetz]::Gleich($empf1[0].nutz, [byte[]](@(1) + $pos))) "durchgelassen wird Platz + unveränderte Nachricht"
Check ($empf2.Count -eq 40) "Flut auf Platz 2: Drossel lässt 40 durch"
Check ($raus.Count -eq 1 -and $raus[0].nutz[0] -eq 3 -and $raus[0].nutz[1] -eq 1) "Dauer-Unsinn auf Platz 3: RAUS gemeldet, genau einmal"
Check ($empf3.Count -eq 1) "nach SCHLIESSEN ist Platz 3 wieder offen"
Check ($tr.Count -eq 1 -and [UzZimmerNetz]::Gleich($tr[0].nutz, [byte[]](@(1) + $z))) "hinaus geht nur, was ins Schema passt (Zimmer ja, JSON nein)"
$zb = $zl[0].nutz
Check ($zl.Count -eq 1 -and $zb.Length -eq 20 -and [BitConverter]::ToUInt32($zb, 0) -eq 45 -and [BitConverter]::ToUInt32($zb, 4) -eq 46 -and [BitConverter]::ToUInt32($zb, 8) -eq 20 -and [BitConverter]::ToUInt32($zb, 12) -eq 1) "Zähler: 45 angenommen, 46 verworfen, 20 gedrosselt, 1 hinaus verworfen"
Check ([BitConverter]::ToUInt32($zb, 16) -eq 111) "Zähler: 111 TEST_REIN-Rahmen bis dahin angekommen (Leitung ohne Verlust)"
# Quittungen: steigend, je mindestens 512 Byte weiter, nie mehr als gelesen; am Ende fehlt weniger als 512 + ein Rahmen.
$qt = @($s.aus | Where-Object { $_.art -eq 21 } | ForEach-Object { [BitConverter]::ToUInt32($_.nutz, 0) })
$qok = $qt.Count -ge [int]($ein.Count / 9000) -and $qt.Count -gt 0 -and @($s.aus | Where-Object { $_.art -eq 21 -and $_.nutz.Length -ne 4 }).Count -eq 0
for ($k = 0; $k -lt $qt.Count; $k++) { if ($qt[$k] -gt $ein.Count -or ($k -gt 0 -and $qt[$k] - $qt[$k - 1] -lt 512) -or ($k -eq 0 -and $qt[0] -lt 512)) { $qok = $false } }
Check ($qok -and $ein.Count - $qt[-1] -lt 512 + 8197) "Quittungen: $($qt.Count) für $($ein.Count) Byte, steigend, je ≥ 512, nie mehr als gelesen"
Check ((Sitzung ([byte[]](Rahmen 21 ([byte[]](0, 0, 0, 0)))) $true).code -eq 3) "QUITTUNG von Uzai → Code 3 (gilt nur Sandbox → Uzai)"
$sg = Sitzung ([byte[]]((Platz 8 0 $z) + (Platz 8 0 $pos) + (Rahmen 5 ([byte[]]@())))) $false
Check ($sg.code -eq 0 -and @($sg.aus | Where-Object { $_.art -eq 7 }).Count -eq 2) "Gast: das Zimmer des Gastgebers kommt durch"
Check ((Sitzung ([byte[]](Platz 8 1 $pos)) $false).code -eq 3) "Gast: Platz 1 gibt es nicht → Code 3"
Check ((Sitzung ([byte[]](Platz 6 1 $z)) $false).code -eq 3) "Gast: SENDEN an Platz 1 → Code 3"
Check ((Sitzung ([byte[]](Platz 8 8 $pos)) $true).code -eq 3) "Gastgeber: Platz 8 gibt es nicht → Code 3"
Check ((Sitzung ([byte[]](Platz 7 1 $pos)) $true).code -eq 3 -and (Sitzung ([byte[]](Platz 9 1 $pos)) $true).code -eq 3 -and (Sitzung ([byte[]](Rahmen 10 ([byte[]](1, 1)))) $true).code -eq 3) "Rahmen der Gegenrichtung (EMPFANGEN, TEST_RAUS, RAUS) → Code 3"
Check ((Sitzung ([byte[]](Rahmen 3 ([byte[]](1)))) $true).code -eq 3 -and (Sitzung ([byte[]](Rahmen 11 ([byte[]](1)))) $true).code -eq 3 -and (Sitzung ([byte[]](Rahmen 12 ([byte[]]@()))) $true).code -eq 3) "Selbsttest in der Sitzung, Zähler mit Inhalt, SCHLIESSEN ohne Platz → Code 3"
$io = New-Object IO.MemoryStream (, [byte[]](Platz 8 1 $pos))
$oo = New-Object IO.MemoryStream
Check ([UzaiZimmerNetz]::Netz($io, $oo, $true, $false, [Func[double]] { 1.0 }) -eq 3) "ohne „--test“ gibt es TEST_REIN nicht"
$schlecht = 0
for ($n = 0; $n -lt 1500; $n++) {
    $b = New-Object byte[] ($rnd.Next(0, 600))
    $rnd.NextBytes($b)
    if ($b.Length -gt 6 -and $rnd.Next(3) -gt 0) { $len = $b.Length - 4; $b[0] = [byte]($len -band 0xFF); $b[1] = [byte]($len -shr 8); $b[2] = 0; $b[3] = 0; $b[4] = [byte]$rnd.Next(1, 13); $b[5] = [byte]$rnd.Next(0, 9) }
    try { $c = (Sitzung $b ($rnd.Next(2) -eq 0)).code; if ($c -ne 0 -and $c -ne 3) { $schlecht++ } } catch { $schlecht++ }
}
Check ($schlecht -eq 0) "1500 × Zufallsrahmen an die Sitzung: endet immer sauber (0 oder 3), ohne Ausnahme"

"Auftrag und Auswertung"
$kv = [UzaiZimmerNetz]::Auftrag("ordner=/tmp/a`nlesen=relativ/x`nfremd=/x`nliste=/tmp/b`nliste=/tmp/c`nschreiben=\\\\server\\x`nprogramm=/bin/sh`n")
Check ($kv.Count -eq 2 -and $kv['ordner'] -eq '/tmp/a' -and $kv['liste'] -eq '/tmp/b') "nur bekannte Schlüssel, absolute Pfade, kein Netzpfad, keiner doppelt, kein Programm"
Check (-not [UzaiZimmerNetz]::PfadOk('') -and -not [UzaiZimmerNetz]::PfadOk(('/x' * 200)) -and -not [UzaiZimmerNetz]::PfadOk("/a`0b")) "leere, zu lange und Pfade mit Null-Zeichen abgelehnt"
$e = New-Object 'UzZimmerNetz+Ergebnis'
[UzZimmerNetz]::Auswerten("ordner=1`nlesen=0`nliste=0`nschreiben=0`nprogramm=0`n", $e)
$e.Container = $true; $e.Echo = $true; $e.Sauber = $true
Check ($e.Ok()) "alle Mauern stehen → ok"
$j = $e.Json() | ConvertFrom-Json
Check ($j.ok -and $j.container -and $j.echo -and $j.eigener_ordner -and $j.uzai_daten_gesperrt -and $j.profil_gesperrt -and $j.temp_gesperrt -and $j.programme_gesperrt) "Antwort an Uzai: alle Felder"
$e2 = New-Object 'UzZimmerNetz+Ergebnis'
[UzZimmerNetz]::Auswerten("ordner=1`nlesen=1`nliste=0`nschreiben=0`nprogramm=0`n", $e2)
$e2.Container = $true; $e2.Echo = $true; $e2.Sauber = $true
Check (-not $e2.Ok()) "Uzais Datei lesbar → nicht ok"
$e3 = New-Object 'UzZimmerNetz+Ergebnis'
[UzZimmerNetz]::Auswerten("ordner=1`nlesen=0`n", $e3)
Check (-not $e3.ProgrammGesperrt -and -not $e3.SchreibenGesperrt) "fehlende Antwort zählt nie als gesperrt"
$e3.Fehler = 'start 5"},"ok":true,{"x":"'
Check (($e3.Json() | ConvertFrom-Json).fehler -eq 'start 5ok:truex:') "Fehlertext kann das JSON nicht aufbrechen"
$u = [UzZimmerNetz]::Umgebung('C:\Windows', 'C:\Users\x\AppData\Local\Packages\uzai.zimmernetz\AC')
$uz = @($u.TrimEnd([char]0) -split "`0")
$uw = @($uz | ForEach-Object { $_.Substring($_.IndexOf('=') + 1) })
Check ($u.EndsWith("`0`0") -and $uz.Count -eq 7 -and -not $u.Contains('PATH=') -and
    @($uw | Where-Object { $_ -ne 'C:\Windows' -and $_ -ne 'C:\Users\x\AppData\Local\Packages\uzai.zimmernetz\AC' }).Count -eq 0) "Kindprozess: nur feste Variablen, Werte nur Windows-Ordner oder der eigene Container-Ordner"
$namen = @($uz | ForEach-Object { $_.Substring(0, $_.IndexOf('=')) })
Check ((($namen | ForEach-Object { $_.ToUpperInvariant() }) -join ',') -eq ((@($namen | ForEach-Object { $_.ToUpperInvariant() }) | Sort-Object -CaseSensitive) -join ',') -and
    $namen -contains 'LOCALAPPDATA' -and $namen -contains 'USERPROFILE') "Block nach Namen sortiert, Profil-Variablen für den AppContainer-Start da"

"Feste Werte"
Check ([UzZimmerNetz]::InternetClient -eq 'S-1-15-3-1') "einzige Fähigkeit: internetClient (S-1-15-3-1)"
Check (-not $cs.Contains('S-1-15-3-2') -and -not $cs.Contains('S-1-15-3-3') -and -not $cs.Contains('internetClientServer')) "kein internetClientServer, kein privateNetworkClientServer (kein Lauschen, kein Heimnetz)"
Check ($cs.Contains('sc.CapabilityCount = 1;')) "genau eine Fähigkeit im Container"
Check ([UzZimmerNetz]::ATTR_SECURITY_CAPABILITIES -eq 0x20009 -and [UzZimmerNetz]::ATTR_HANDLE_LIST -eq 0x20002 -and [UzZimmerNetz]::ATTR_CHILD_PROCESS_POLICY -eq 0x2000E) "Attribute: SECURITY_CAPABILITIES, HANDLE_LIST, CHILD_PROCESS_POLICY"
Check ([UzZimmerNetz]::Container -match '^[A-Za-z0-9.]{1,64}$') "Container-Name gültig (Buchstaben, Ziffern, Punkt)"
Check ($cs.Contains('CREATE_SUSPENDED | DETACHED_PROCESS |') -and -not $cs.Contains('CREATE_NO_WINDOW')) "Kindprozess ohne Konsole (kein conhost im Job mit nur einem Prozess)"
Check ($cs.Contains('0x2000 | 0x8 | 0x100 | 0x400') -and $cs.Contains('ActiveProcessLimit = 1') -and $cs.Contains('0xFF') -and [UzZimmerNetz]::SPEICHER -eq 268435456) "Job-Objekt: ein Prozess, 256 MB, endet mit dem Helfer, alle UI-Sperren"
Check ([UzZimmerNetz]::Befehl('C:\a\z.exe', 'echo') -eq '"C:\a\z.exe" --echo' -and [UzZimmerNetz]::Befehl('C:\a\z.exe', 'gast') -eq '"C:\a\z.exe" --netz gast --test' -and
    [UzZimmerNetz]::Befehl('C:\a\z.exe', 'gastgeber-echt') -eq '"C:\a\z.exe" --netz gastgeber' -and $null -eq [UzZimmerNetz]::Befehl('C:\a\z.exe', 'echt') -and
    $null -eq [UzZimmerNetz]::Befehl('C:\a\z.exe', 'gast --live') -and $null -eq [UzZimmerNetz]::Befehl('C:\a\z.exe', 'Gastgeber') -and $null -eq [UzZimmerNetz]::Befehl('C:\a\z.exe', '')) "Befehlszeile nur in festen Formen"
Check ([UzZimmerNetz]::Sitzung('C:\x.exe', 'admin') -eq 2 -and [UzZimmerNetz]::Sitzung('C:\x.exe', '') -eq 2) "Sitzung mit unbekannter Rolle: gar nicht erst (Code 2)"
Check (-not ($cs -match 'cmd\.exe|powershell|ShellExecute = true|(?<!Web)Socket\b|TcpListener|HttpListener|HttpWebRequest|WebClient|TcpClient|UdpClient|Console\.Write\(|Console\.Out')) "kein Shell-Aufruf, kein Lauschen, Netz nur ausgehend per WebSocket, nichts schreibt neben die Leitung"
Check (([regex]::Matches($cs, 'new System\.Net\.WebSockets\.ClientWebSocket\(\)')).Count -eq 1 -and ([regex]::Matches($cs, 'ConnectAsync\(')).Count -eq 1) "genau eine Stelle verbindet sich (Treffpunkt, UzRelays)"
Check ($src.Contains("'zimmer-netz-probe' { return (ZimmerNetz-Probe) }")) "Helfer-Befehl ohne Argumente von außen"
Check ($src -match "IsElevated\(\`$PID\)\) \{ return @\{ ok = \`$false; fehler = 'admin' \}") "Probe mit Adminrechten: gar nicht erst"
$zweig = [regex]::Match($src, "(?s)if \(\`$ZimmerNetz -ne ''\) \{(.*?)\n\}").Groups[1].Value
Check ($zweig.Contains("@('gastgeber', 'gast', 'gastgeber-echt', 'gast-echt')") -and $zweig.Contains('IsElevated($PID)) { exit 4 }') -and $zweig.Contains('[UzZimmerNetz]::Sitzung($exe, $ZimmerNetz)')) "-ZimmerNetz: nur vier feste Rollen, nie mit Adminrechten, dann die Sitzung"
Check (-not ($zweig -match 'Write-Reply|Write-Output|Write-Host|\[Console\]::Out|\[Console\]::In')) "-ZimmerNetz schreibt und liest nichts auf der Leitung"
Check ($src.IndexOf("if (`$ZimmerNetz -ne '')") -lt $src.IndexOf('Write-Reply 0 $true @{ ready = $true')) "-ZimmerNetz kommt vor der Bereit-Meldung des Helfers"
""
if ($fails -eq 0) { "Ergebnis: alles ok" } else { "Ergebnis: $fails Fehler"; exit 1 }
