# Probe für das Live-Bild im Fernseher des Zimmers (UzTvFang und Befehl „tv-fang“ in
# helper/uzai-helper.ps1): C# 5 übersetzbar (Warnungen als Fehler), Wahl der Mip-Stufe, BGRA → RGBA,
# Kopf und Seqlock der Zwischendatei (wie src/room/spielbild.gd sie liest), nur Zahlen als Argumente,
# keine Tasten, kein Fokus, kein PrintWindow. Windows Graphics Capture selbst läuft hier nicht.
# Dazu, was gegen schwarze Bilder ohne Grafikkarte prüfbar ist: mittlere Farbe (Kopf, Feld 28), HDR
# (16-Bit-Gleitkomma → SDR), Texte für launch.log, Größe des Spiegels, Befehl „uzai-vorrang“.
#   pwsh -NoProfile -File tests/tvfang_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}
function U32([byte[]]$b, [int]$o) { return [BitConverter]::ToUInt32($b, $o) }
function UHex([string]$s) { return [Convert]::ToUInt32($s, 16) }   # 0x80000000 wäre in PowerShell negativ

$m = [regex]::Match($src, "(?s)\`$script:TvFangSrc = @'\n(.*?)\n'@")
$code = $m.Groups[1].Value
Check ($code.Length -gt 2000) ("UzTvFang-Block gefunden (" + $code.Length + " Zeichen)")
try {
    Add-Type -TypeDefinition $code -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "UzTvFang übersetzt (C# 5, Warnungen als Fehler)"
} catch { Check $false ("UzTvFang: " + $_.Exception.Message) }

"Mip-Stufe (GPU rechnet klein, höchstens ein Drittel über dem Ziel)"
Check ([UzTvFang]::Stufe(1920, 1080, 960, 540) -eq 1) "1920×1080 → 960×540"
Check ([UzTvFang]::Stufe(2560, 1440, 960, 540) -eq 1) "2560×1440 → 1280×720"
Check ([UzTvFang]::Stufe(3840, 2160, 960, 540) -eq 2) "3840×2160 → 960×540"
Check ([UzTvFang]::Stufe(7680, 4320, 960, 540) -eq 3) "7680×4320 → 960×540"
Check ([UzTvFang]::Stufe(1280, 720, 960, 540) -eq 0) "1280×720 bleibt (passt)"
Check ([UzTvFang]::Stufe(640, 480, 960, 540) -eq 0) "kleines Fenster bleibt"
$l = [UzTvFang]::Stufe(5120, 1440, 960, 540)
Check ($l -eq 2 -and [UzTvFang]::Seite(5120, $l) -eq 1280 -and [UzTvFang]::Seite(1440, $l) -eq 360) "Ultrabreit 5120×1440 → 1280×360"
Check ([UzTvFang]::Stufe(1920, 1080, 640, 360) -eq 2) "Leicht: 1920×1080 → 480×270"
Check ([UzTvFang]::Stufe(0, 1080, 960, 540) -eq -1 -and [UzTvFang]::Stufe(1920, -5, 960, 540) -eq -1) "leere Größe: nichts"
$riesig = [UzTvFang]::Stufe(1920, 1080, 999999, 999999)
Check ([UzTvFang]::Seite(1920, $riesig) -le 1280 -and [UzTvFang]::Seite(1920, $riesig) * [UzTvFang]::Seite(1080, $riesig) -le 1280 * 720) "zu großes Ziel wird begrenzt"
Check ([UzTvFang]::Seite(1, 5) -eq 1) "Seite nie 0"

"Pixel"
$px = [byte[]]@(10, 20, 30, 0, 1, 2, 3, 4)
[UzTvFang]::Tausche($px, 8)
Check ((-join $px) -eq (-join @(30, 20, 10, 255, 3, 2, 1, 255))) "BGRA → RGBA, Alpha voll"
[UzTvFang]::Tausche($null, 8)
$kurz = [byte[]]@(1, 2, 3, 4, 5)
[UzTvFang]::Tausche($kurz, 99)
Check ((-join $kurz) -eq (-join @(3, 2, 1, 255, 5))) "kurzer Puffer: nie darüber hinaus"

"Mittlere Farbe und schwarz"
$bunt = [byte[]]@(10, 20, 30, 255, 10, 20, 30, 255, 10, 20, 30, 255, 10, 20, 30, 255)
Check ([UzTvFang]::Mittel($bunt, 2, 2) -eq (UHex '800A141E')) "Mittel: Farbe mit Gültig-Bit"
Check ([UzTvFang]::Mittel($bunt, 4, 4) -eq 0 -and [UzTvFang]::Mittel($null, 2, 2) -eq 0) "zu kleiner Puffer: keine Farbe (nie darüber hinaus)"
$halb = New-Object byte[] (960 * 540 * 4)
for ($y = 0; $y -lt 540; $y++) { for ($x = 120; $x -lt 840; $x++) { $o = ($y * 960 + $x) * 4; $halb[$o] = 100; $halb[$o + 1] = 100; $halb[$o + 2] = 100 } }
$mh = [UzTvFang]::Mittel($halb, 960, 540)
Check ((($mh -shr 8) -band 255) -ge 70 -and (($mh -shr 8) -band 255) -le 80) ("4:3 mit schwarzen Rändern: Mittel über das ganze Bild (" + (($mh -shr 8) -band 255) + " statt 75)")
Check ([UzTvFang]::Schwarz((UHex '80000000')) -and [UzTvFang]::Schwarz((UHex '80020202')) -and -not [UzTvFang]::Schwarz((UHex '80202020')) -and -not [UzTvFang]::Schwarz(0)) "schwarz wie in Uzai (unbekannt zählt nicht)"
Check ([UzTvFang]::Hex((UHex '80102030')) -eq '#102030' -and [UzTvFang]::Hex(0) -eq 'unbekannt') "Farbe als Text"

"HDR: 16-Bit-Gleitkomma → SDR"
Check ([UzTvFang]::Halb(0x3C00) -eq 1.0 -and [UzTvFang]::Halb(0xC000) -eq -2.0 -and [UzTvFang]::Halb(0) -eq 0.0) "Halb: 1, -2, 0"
Check ([single]::IsPositiveInfinity([UzTvFang]::Halb(0x7C00)) -and [single]::IsNaN([UzTvFang]::Halb(0x7E00)) -and [Math]::Abs([UzTvFang]::Halb(1) - 5.96e-8) -lt 1e-9) "Halb: unendlich, NaN, kleinste Zahl"
Check ([Math]::Abs([UzTvFang]::Halb(0x3555) - 0.33325) -lt 0.0001) "Halb: 0x3555 ≈ 1/3"
Check ([UzTvFang]::Srgb(0) -eq 0 -and [UzTvFang]::Srgb(1) -eq 255 -and [UzTvFang]::Srgb(0.5) -eq 188 -and [UzTvFang]::Srgb([single]::NaN) -eq 0 -and [UzTvFang]::Srgb(-1) -eq 0) "sRGB: 0, 1, Mitte, NaN, negativ"
$w = [UzTvFang]::Weiss($true, 240)
Check ($w -eq 3.0 -and [UzTvFang]::Weiss($true, 0) -eq 2.5 -and [UzTvFang]::Weiss($false, 240) -eq 1.0) "SDR-Weiß: 240 nits = 3,0; unbekannt 2,5; ohne HDR 1,0"
Check ([UzTvFang]::Abbilden(1.5, 3.0) -eq 0.5 -and [UzTvFang]::Abbilden(-1, 3.0) -eq 0 -and [UzTvFang]::Abbilden([single]::NaN, 3.0) -eq 0) "unter dem Knie unverändert, negativ/NaN → 0"
$a1 = [UzTvFang]::Abbilden(3.0, 3.0); $a2 = [UzTvFang]::Abbilden(30.0, 3.0); $a3 = [UzTvFang]::Abbilden([single]::PositiveInfinity, 3.0)
Check ($a1 -gt 0.95 -and $a1 -lt 0.97 -and $a2 -gt $a1 -and $a2 -le 1.0 -and $a3 -eq 1.0) "SDR-Weiß ≈ 0,96, helle Lichter laufen weich gegen 1"
$stetig = $true; $vor = -1.0
for ($v = 0.0; $v -lt 40.0; $v += 0.05) { $r = [UzTvFang]::Abbilden($v, 3.0); if ($r -lt $vor) { $stetig = $false }; $vor = $r }
Check $stetig "Abbildung steigt überall (keine Stufe, kein Knick nach unten)"
$fp = [byte[]]@(0x00, 0x3C, 0x00, 0x38, 0x00, 0x00, 0x00, 0x3C)
$ziel = New-Object byte[] 8
[UzTvFang]::HalbZuRgba($fp, 2, $ziel, 1.0)
Check ($ziel[0] -ge 250 -and $ziel[1] -eq 188 -and $ziel[2] -eq 0 -and $ziel[3] -eq 255 -and $ziel[4] -eq 0) "ein Pixel (1; 0,5; 0) → (≈251, 188, 0, 255); zweiter fehlt: unberührt"
[UzTvFang]::HalbZuRgba($null, 5, $ziel, 1.0)
[UzTvFang]::HalbZuRgba($fp, 99, (New-Object byte[] 3), 1.0)
Check $true "zu kurze Puffer: nie darüber hinaus"

"Spiegel und Texte"
$sw = 0; $sh = 0
[UzTvFang]::SpiegelGroesse(1920, 1080, 960, 540, [ref]$sw, [ref]$sh); $s1 = "$sw x $sh"
[UzTvFang]::SpiegelGroesse(640, 480, 960, 540, [ref]$sw, [ref]$sh); $s2 = "$sw x $sh"
[UzTvFang]::SpiegelGroesse(5120, 1440, 960, 540, [ref]$sw, [ref]$sh); $s3 = "$sw x $sh"
[UzTvFang]::SpiegelGroesse(0, 0, 99999, 1, [ref]$sw, [ref]$sh); $s4 = "$sw x $sh"
Check ($s1 -eq '960 x 540' -and $s2 -eq '720 x 540' -and $s3 -eq '960 x 270' -and $s4 -eq '1280 x 36') ("Spiegel im Seitenverhältnis, begrenzt: $s1, $s2, $s3, $s4")
Check ([UzTvFang]::Deckt(0, 0, 1920, 1081, 0, 0, 1920, 1080) -and -not [UzTvFang]::Deckt(0, 0, 1280, 720, 0, 0, 1920, 1080)) "deckt den Bildschirm?"
$z = [UzTvFang]::ZustandText($true, $true, $true, 0, 1920, 1080, 1920, 1080, $true, 0x11, 3, 'Qt6120QWindowIcon', (UHex '96000000'))
Check ($z.Contains('minimiert') -and $z.Contains('WDA_EXCLUDEFROMCAPTURE') -and $z.Contains('exklusives Vollbild') -and $z.Contains('deckt den Bildschirm')) $z
$z = [UzTvFang]::ZustandText($true, $false, $true, 2, 1920, 1080, 3840, 2160, $false, 0, 5, '', 0)
Check ($z.Contains('nicht minimiert') -and $z.Contains('cloaked 2') -and $z.Contains('kein exklusives Vollbild')) $z
Check ([UzTvFang]::ZustandText($false, $false, $false, 0, 0, 0, 0, 0, $false, 0, 0, '', 0).Contains('gibt es nicht')) "Fenster weg"
$i = [UzTvFang]::InfoText('NVIDIA GeForce RTX 5080', $true, '\\.\DISPLAY1', $true, 12, 10, $true, $true, 240, $true, $false)
Check ($i.Contains('RTX 5080') -and $i.Contains('HDR an') -and $i.Contains('HDR10') -and $i.Contains('SDR-Weiß 240 nits') -and $i.Contains('R16G16B16A16')) $i
$i = [UzTvFang]::InfoText('', $false, '', $false, 0, 0, $false, $false, 0, $false, $true)
Check ($i.Contains('Standard') -and $i.Contains('HDR aus') -and $i.Contains('B8G8R8A8') -and $i.Contains('Spiegel')) $i
$b = [UzTvFang]::BildText(87, 1920, 1088, 1920, 1080, 1, 960, 540, (UHex '80000000'))
Check ($b.Contains('B8G8R8A8') -and $b.Contains('1920×1088') -and $b.Contains('960×540') -and $b.Contains('#000000 (schwarz)')) $b

"Kopf und Seqlock"
$k = [UzTvFang]::KopfBytes(6, 960, 540)
Check ($k.Length -eq 32 -and [Text.Encoding]::ASCII.GetString($k, 0, 4) -eq 'UZTV') "Kopf 32 Byte, Kennung „UZTV“"
Check ((U32 $k 4) -eq 1 -and (U32 $k 8) -eq 6 -and (U32 $k 12) -eq 960 -and (U32 $k 16) -eq 540 -and (U32 $k 20) -eq 3840 -and (U32 $k 24) -eq (960 * 540 * 4)) "Version, Nummer, Breite, Höhe, Zeile, Länge"
Check ((U32 $k 28) -eq 0 -and (U32 ([UzTvFang]::KopfBytes(6, 960, 540, (UHex '80102030'))) 28) -eq (UHex '80102030')) "Feld 28: mittlere Farbe (ohne: 0)"
$k2 = [UzTvFang]::KopfBytes(2, 5000, 5000)
Check ((U32 $k2 12) -eq 0 -and (U32 $k2 16) -eq 0 -and (U32 $k2 24) -eq 0) "zu groß: Kopf ohne Bild"
Check ([UzTvFang]::Dateigroesse() -eq 32 + 1280 * 720 * 4) "feste Dateigröße"
$ms = New-Object IO.MemoryStream
$bild = New-Object byte[] (4 * 3 * 4)
for ($i = 0; $i -lt $bild.Length; $i++) { $bild[$i] = [byte]($i + 1) }
$s = [UzTvFang]::Schreibe($ms, 0, 4, 3, $bild)
$a = $ms.ToArray()
Check ($s -eq 2 -and (U32 $a 8) -eq 2) "erstes Bild: Nummer 2 (gerade = fertig)"
Check ($a.Length -eq 32 + 48 -and $a[32] -eq 1 -and $a[79] -eq 48) "Pixel gleich hinter dem Kopf"
$s2 = [UzTvFang]::Schreibe($ms, $s, 4, 3, $bild)
Check ($s2 -eq 4 -and (U32 $ms.ToArray() 8) -eq 4) "nächstes Bild: Nummer 4"
$s2 = [UzTvFang]::Schreibe($ms, $s2, 4, 3, $bild, (UHex '80ABCDEF'))
Check ($s2 -eq 6 -and (U32 $ms.ToArray() 28) -eq (UHex '80ABCDEF')) "Bild mit Farbe: steht im Kopf"
$vor = $ms.ToArray()
Check ([UzTvFang]::Schreibe($ms, $s2, 4, 3, (New-Object byte[] 10)) -eq $s2 -and (-join $ms.ToArray()) -eq (-join $vor)) "zu kurzer Puffer: nichts geschrieben"
Check ([UzTvFang]::Schreibe($ms, $s2, 2000, 3, $bild) -eq $s2 -and [UzTvFang]::Schreibe($null, 8, 4, 3, $bild) -eq 8) "zu breit / ohne Datei: nichts"
# Mitten im Schreiben: ungerade Nummer im Kopf (ein Strom, der nach den Pixeln abbricht).
$fest = New-Object byte[] 40
$ws = New-Object IO.MemoryStream (, $fest)
try { [void][UzTvFang]::Schreibe($ws, 0, 4, 3, $bild) } catch { }
Check ((U32 $fest 8) -eq 1) "bricht das Schreiben ab, bleibt die Nummer ungerade (Uzai nimmt das Bild nicht)"

"Quelltext"
foreach ($bad in @('SetForegroundWindow', 'keybd_event', 'SendInput', 'AttachThreadInput', 'Process.Start', 'OpenProcess', 'PrintWindow', 'BitBlt', 'D3DCompile')) {
    Check (-not $code.Contains($bad)) "UzTvFang ohne $bad"
}
Check ($code.Contains('CreateFreeThreaded') -or $code.Contains('IID_PoolStatics2')) "frei laufender Bildpool (kein Fenster-Thread nötig)"
Check ($code.Contains('(s2, 7)(s2, 0)')) "Mauszeiger aus, gelber Rahmen aus, wo Windows es erlaubt"
Check ($code.Contains('0x100') -and $code.Contains('File.Delete(zDatei)')) "Zwischendatei temporär markiert und beim Stoppen gelöscht"
Check ($code.Contains('PULS_MS = 15000') -and $code.Contains('"kein Lebenszeichen"') -and $code.Contains('"Fenster zu"')) "endet ohne Lebenszeichen und mit dem Fenster"
Check ($code.Contains('GenerateMips') -or $code.Contains('(ctx, 54)')) "kleinrechnen auf der Grafikkarte (Mipmaps)"
Check ($code.Contains('KarteFuer(MonitorFromWindow(spiel') -and $code.Contains('D3D11CreateDevice(karte, karte != IntPtr.Zero ? 0 : 1')) "Gerät auf der Grafikkarte des Bildschirms (sonst Standard)"
Check ($code.Contains('(o6, 27)') -and $code.Contains('FarbeVonWindows(gdi') -and $code.Contains('int fmt = hdr ? FMT_FP16 : FMT_BGRA')) "HDR erkannt (IDXGIOutput6, Anzeige-Einstellungen) → 16-Bit-Pool"
Check ($code.Contains('SCHWARZ_N') -and $code.Contains('(pool, 6)(pool, rtDev, neu')) "nur schwarz: einmal das andere Format"
Check ($code.Contains('DwmRegisterThumbnail(w, spiel') -and $code.Contains('0x08000000u | 0x00000020u') -and -not $code.Contains('0x00040000')) "Spiegel: nie aktivierbar, mausdurchlässig, kein Taskleisten-Eintrag"
Check ($code.Contains('DestroyWindow(spWnd)') -and $code.Contains('DwmUnregisterThumbnail(spThumb)')) "Spiegel verschwindet mit der Aufnahme"
Check ($code.Contains('GetWindowDisplayAffinity') -and $code.Contains('SHQueryUserNotificationState') -and $code.Contains('DwmGetWindowAttribute(h, 14')) "Zustand: Aufnahmeschutz, exklusives Vollbild, von Windows versteckt"
$cmd = [regex]::Match($src, "(?s)\n        'tv-fang' \{\n(.*?)\n        \}\n").Groups[1].Value
Check ($cmd -ne '' -and ([regex]::Matches($src, "\n        'tv-fang' \{")).Count -eq 1) "Befehl „tv-fang“ genau einmal"
Check ($cmd.Contains('Get-Hwnd $a.spiel') -and $cmd.Contains('Get-Zahl $a.max_w 64 1280') -and $cmd.Contains('Get-Zahl $a.fps 1 60')) "Argumente nur als Zahlen, fest begrenzt"
Check ($cmd.Contains('-eq $PID') -and $cmd.Contains("grund = 'daten'")) "nie das eigene Fenster, falsche Daten → nichts"
Check (-not $cmd.Contains('Focus') -and -not $cmd.Contains('keys')) "kein Fokuswechsel, keine Tasten"
Check ($cmd.Contains('$a.spiegel -is [bool]') -and $cmd.Contains('Get-Hwnd $a.hwnd') -and $cmd.Contains('zustand = [UzTvFang]::Zustand($spiel)')) "Spiegel nur als echtes true, Uzais Fenster als Zahl; Messwerte in der Antwort"
$vr = [regex]::Match($src, "(?s)\n        'uzai-vorrang' \{\n(.*?)\n        \}\n").Groups[1].Value
Check ($vr -ne '' -and ([regex]::Matches($src, "\n        'uzai-vorrang' \{")).Count -eq 1) "Befehl „uzai-vorrang“ genau einmal"
Check ($vr.Contains('Get-UzaiPid') -and $vr.Contains('PidOf([IntPtr]$h) -ne $p') -and $vr.Contains('BelowNormal') -and -not $vr.Contains('High') -and -not $vr.Contains('AboveNormal') -and -not $vr.Contains('RealTime')) "nur Uzais eigener Prozess, nur zurücknehmen, nie höher"
Check ($vr.Contains('$cpu = -not ($a.cpu -is [bool] -and -not $a.cpu)') -and $vr.Contains('if ($leise -and $cpu)')) "Prozessor nur auf Wunsch (cpu = false: bleibt normal, ohne Angabe wie bisher)"
$df = [regex]::Match($src, "(?s)\nfunction Get-TvFangDatei \{\n(.*?)\n\}\n").Groups[1].Value
Check ($df.Contains('GetTempPath') -and $df.Contains("'^uzai-tvbild-\d{1,10}\.bin$'")) "Zwischendatei nur im Temp-Ordner, aufgeräumt wird nur das eigene Muster"

# Der Befehl selbst: falsche Argumente scheitern an der Prüfung, bevor Windows etwas sieht.
Invoke-Expression ([regex]::Match($src, '(?s)\n(function Get-Hwnd\(\$v\) \{.*?\n\})\n').Groups[1].Value)
Invoke-Expression ([regex]::Match($src, '(?s)\n(function Get-Zahl\(.*?\n\})\n').Groups[1].Value)
function Use-TvFang { }
$sb = [scriptblock]::Create("param(`$a)`n" + $cmd)
foreach ($fall in @(
        @{ a = @{ an = $true; spiel = '1; calc'; max_w = 960; max_h = 540; fps = 30 }; was = 'Befehl als Fenster' },
        @{ a = @{ an = $true; spiel = 88; max_w = 99999; max_h = 540; fps = 30 }; was = 'zu breit' },
        @{ a = @{ an = $true; spiel = 88; max_w = 960; max_h = 540; fps = 0 }; was = '0 Bilder/s' },
        @{ a = @{ an = $true; spiel = 88; max_w = 960; max_h = 540; fps = '30;x' }; was = 'Text als Zahl' })) {
    $r = & $sb ([pscustomobject]$fall.a)
    Check ($r.an -eq $false -and $r.grund -eq 'daten') ("tv-fang " + $fall.was + " → daten")
}
$sbv = [scriptblock]::Create("param(`$a)`n" + $vr)
foreach ($fall in @(@{ pid = 'x'; hwnd = 5 }, @{ pid = 77; hwnd = 0 }, @{ pid = $PID; hwnd = 5 }, @{ pid = '1; calc'; hwnd = 5 })) {
    $r = & $sbv ([pscustomobject]@{ leise = $true; pid = $fall.pid; hwnd = $fall.hwnd })
    Check ($r.ok -eq $false -and $r.grund -eq 'daten') ("uzai-vorrang pid " + $fall.pid + ", Fenster " + $fall.hwnd + " → daten")
}
$r = & $sb ([pscustomobject]@{ an = 'true'; spiel = 88; max_w = 960; max_h = 540; fps = 30 })
Check ($r.an -eq $false -and -not $r.ContainsKey('grund')) "an nur als echtes true (sonst aus)"
""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
