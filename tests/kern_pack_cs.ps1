# Prüft den Entpacker des Browser-Kerns im Helfer (UzKernPack in helper/uzai-helper.ps1, docs/BROWSER_PLAN.md 2.2) unter
# Linux mit PowerShell 7: übersetzt mit C# 5 ohne Warnungen; liest Probe-Archive aus Python (tests/kern_pack_archive.py)
# im Aufbau der echten Verteilungen: aus der signierten (.tar.xz: pax, GNU, ustar; CRC32, CRC64, SHA-256, ohne Prüfsumme;
# Stufe 0/6/9; mehrere Blöcke, zwei Ströme) bitgenau nur chrome_elf.dll aus dem Hauptordner, aus der minimal (.tar.bz2
# aus Python und bzip2, Stufe 1–9, mehrere Blöcke und Ströme; auch .tar.xz) nur Release/bootstrap.exe – unter festem
# Namen. Lehnt kaputte, abgeschnittene, falsche CRC (Block, Strom), zu große/kleine Dateien, Nicht-Programme, fehlende
# Dateien, BCJ-Filter und „..“ mit kurzem Grund ab; ganze bzip2-Ströme bitgenau. kern-auslegen nutzt ihn statt
# Windows-tar, nimmt nur Archive derselben Fassung aus festen Ordnern und meldet Schritt und Grund ohne Benutzerpfad.
#   pwsh -NoProfile -File tests/kern_pack_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$helper = $args[0]
$root = Split-Path -Parent (Split-Path -Parent (Resolve-Path $helper))
$src = (Get-Content -Raw $helper) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

$cs = [regex]::Match($src, "\`$script:KernPackSrc = @'\n(?s)(.*?)\n'@").Groups[1].Value
Check ($cs.Length -gt 10000) "UzKernPack gefunden"
try {
    Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "übersetzt (C# 5, ohne Warnungen)"
} catch { Check $false ("UzKernPack: " + $_.Exception.Message); "Ergebnis: $fails Fehler"; exit 1 }
foreach ($nie in @('DllImport', 'Process', 'unsafe', 'Marshal', 'Registry', 'WebClient', 'Http')) { Check (-not $cs.Contains($nie)) "Entpacker ohne $nie" }
Check ($cs.Contains('FileMode.CreateNew') -and $cs.Contains('Path.Combine(ziel, Namen[gesucht])') -and $cs.Contains('"bootstrap.exe", "chrome_elf.dll"')) "schreibt nur feste Namen, nie einen Pfad aus dem Archiv"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('uzai-kernpack-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp | Out-Null
$arch = Join-Path $tmp 'archive'
New-Item -ItemType Directory $arch | Out-Null
try {
    $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source
    if (-not $py) { Check $false "python3 fehlt" } else {
        $n = & $py -I (Join-Path $root 'tests/kern_pack_archive.py') $arch
        $f = Get-Content -Raw (Join-Path $arch 'faelle.json') | ConvertFrom-Json
        Check ([int]$n -ge 30) "$n Probe-Archive gebaut"
        foreach ($p in $f.faelle.PSObject.Properties) {
            $z = Join-Path $tmp ('aus_' + $p.Name)
            New-Item -ItemType Directory $z | Out-Null
            $uhr = [Diagnostics.Stopwatch]::StartNew()
            $r = [UzKernPack]::Auslegen((Join-Path $arch $p.Value.datei), $z, $p.Value.art)
            $ms = $uhr.ElapsedMilliseconds
            $dateien = @(Get-ChildItem -LiteralPath $z | ForEach-Object { $_.Name })
            $e = [string]$p.Value.erwartet
            if ($e -eq '') {
                $soll = $(if ($p.Value.art -eq 'minimal') { 'bootstrap.exe' } else { 'chrome_elf.dll' })
                $sha = $(if ($p.Value.art -eq 'minimal') { $f.bootstrap } else { $f.elf })
                $ok = $r -eq '' -and ($dateien -join ',') -eq $soll -and (Get-FileHash -Algorithm SHA256 (Join-Path $z $soll)).Hash.ToLower() -eq $sha
                Check $ok ("{0}: nur {1}, bitgenau ({2} Einträge, {3} ms) {4}" -f $p.Name, $soll, [UzKernPack]::Eintraege, $ms, $r)
            } elseif ($e -eq '*') {
                Check ($r -ne '' -and $r.Length -lt 120 -and $dateien.Count -eq 0) ("{0}: abgelehnt ({1})" -f $p.Name, $r)
            } else {
                Check (($r -eq $e -or ($e.EndsWith(':') -and $r.StartsWith($e))) -and $dateien.Count -eq 0) ("{0}: {1}" -f $p.Name, $r)
            }
        }
        Check ([UzKernPack]::Auslegen((Join-Path $arch 'gibtsnicht.tar.xz'), $tmp, 'signiert') -ne '') "fehlende Datei: Grund statt Absturz"
        Check ([UzKernPack]::Auslegen((Join-Path $arch 's_pax_crc64.tar.xz'), $tmp, 'alles') -eq 'Art unbekannt') "nur die zwei Arten"
        "ganze bzip2-Ströme"
        foreach ($p in $f.voll.PSObject.Properties) {
            $r = ''
            try {
                $fs = [IO.File]::OpenRead((Join-Path $arch ($p.Name + '.bz2')))
                try {
                    $x = New-Object UzBz2Leser($fs)
                    $r = (([Security.Cryptography.SHA256]::Create().ComputeHash($x)) | ForEach-Object { $_.ToString('x2') }) -join ''
                } finally { $fs.Dispose() }
            } catch { $r = $_.Exception.InnerException.Message; if (-not $r) { $r = $_.Exception.Message } }
            Check ($r -eq $p.Value) ("{0}: {1}" -f $p.Name, $(if ($r.Length -eq 64) { 'bitgenau' } else { $r }))
        }
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Check ([UzKernPack]::NameOk('cef_binary_1/Release/bootstrap.exe') -and -not [UzKernPack]::NameOk('../Release/bootstrap.exe') -and -not [UzKernPack]::NameOk('/Release/bootstrap.exe') -and
    -not [UzKernPack]::NameOk('a\Release\bootstrap.exe') -and -not [UzKernPack]::NameOk('C:Release/bootstrap.exe')) "Namen der gesuchten Einträge: nur relativ und schlicht"
Check ([UzKernPack]::Gesucht('cef_binary_1_minimal/Release/bootstrap.exe') -eq 0 -and [UzKernPack]::Gesucht('cef_binary_1_minimal/bin/bootstrap.exe') -eq -1 -and
    [UzKernPack]::Gesucht('cef_binary_1_minimal/Debug/bootstrap.exe') -eq -1 -and [UzKernPack]::Gesucht('cef_binary_1/Release/bootstrap.exe.sig') -eq -1 -and
    [UzKernPack]::Gesucht('cef_binary_1/Release/bootstrapc.exe') -eq -1 -and [UzKernPack]::Gesucht('x/Release/bootstrap.exe') -eq 0 -and
    [UzKernPack]::Gesucht('a/b/Release/bootstrap.exe') -eq -1 -and [UzKernPack]::Gesucht('Release/bootstrap.exe') -eq -1) "Bootstrap nur aus <Hauptordner>/Release/, nie aus Debug/"
Check ([UzKernPack]::Gesucht('cef_binary_1_signed/chrome_elf.dll') -eq 1 -and [UzKernPack]::Gesucht('cef_binary_1_signed/Release/chrome_elf.dll') -eq -1 -and
    [UzKernPack]::Gesucht('chrome_elf.dll') -eq -1 -and [UzKernPack]::Gesucht('irgendwas/chrome_elf.dll') -eq 1 -and
    [UzKernPack]::Gesucht('a/Debug/chrome_elf.dll') -eq -1) "chrome_elf.dll nur aus dem Hauptordner der signierten Verteilung (Name egal)"

"kern-auslegen"
$fn = [regex]::Match($src, '(?s)\nfunction Kern-Auslegen\(\$a\) \{.*?\n\}\n').Value
$ke = [regex]::Match($src, '(?s)\nfunction Kern-Entpacken\(.*?\n\}\n').Value
Check ($fn.Contains('[UzElev]::IsElevated($PID)') -and $fn.Contains('Kern-Entpacken ') -and $ke.Contains('[UzKernPack]::Auslegen($voll, $tmp, $art)') -and $fn.Contains('Kern-SignaturEntfernen')) "nie als Admin, eigener Entpacker, Signatur nur aus Kopien"
Check (-not $fn.Contains('tar.exe') -and -not $fn.Contains("'-tf'") -and -not $fn.Contains('Start-Process') -and -not $fn.Contains('Invoke-Expression') -and -not $src.Contains("System32\tar.exe")) "kein Windows-tar, startet nichts"
Check ($fn.Contains('schritt = $schritt') -and $fn.Contains('Kern-Text') -and $fn.Contains('} catch {') -and $fn.Contains('} finally {')) "jeder Fehler mit Schritt und Grund (ohne Benutzerpfad), Zwischenordner wird immer entfernt"
$kp = [regex]::Match($src, '(?s)\nfunction Kern-ArchivPfad\(.*?\n\}\n').Value
Check ($fn.Contains("_windows64)_signed\.tar\.xz`$'") -and $fn.Contains("_windows64)_minimal\.tar\.(bz2|xz)`$'") -and $fn.Contains("(Join-Path `$wurzel 'spiegel')") -and
    $fn.Contains("(Join-Path `$wurzel 'boot')") -and $kp.Contains('GetDirectoryName($voll) -ne $ordner') -and $kp.Contains("Contains('..')")) "nur das signierte Archiv direkt im Spiegel, das minimal direkt in kern\boot"
Check ($fn.Contains("'andere Fassung'") -and $fn.Contains("Kern-Entpacken `$voll `$tmp 'signiert'") -and $fn.Contains("Kern-Entpacken `$bvoll `$tmp 'minimal'") -and $fn.Contains("`$schritt = 'bootstrap'")) "beide Archive derselben Fassung; chrome_elf.dll aus der signierten, Bootstrap aus der minimal (eigener Schritt)"
# Unter Linux trennt / die Ordner: für die Probe die Rollen von / und \ tauschen (sonst unverändert).
Invoke-Expression ($kp.Replace("Contains('/')", "Contains('\')").Replace("`$ordner + '\'", "`$ordner + '/'"))
$env:LOCALAPPDATA = Join-Path $tmp 'la'
$sp = Join-Path $env:LOCALAPPDATA 'spiegel'
$mu = '^(cef_binary_[0-9.]+\+g[0-9a-f]{7}\+chromium-[0-9.]+_windows64)_signed\.tar\.xz$'
$gut = 'cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows64_signed.tar.xz'
Check ((Kern-ArchivPfad (Join-Path $sp $gut) $sp $mu) -ne '' -and (Kern-ArchivPfad (Join-Path $sp ('x/' + $gut)) $sp $mu) -eq '' -and
    (Kern-ArchivPfad (Join-Path $sp ('../' + $gut)) $sp $mu) -eq '' -and (Kern-ArchivPfad (Join-Path $sp ($gut + '.exe')) $sp $mu) -eq '' -and
    (Kern-ArchivPfad (Join-Path $env:LOCALAPPDATA $gut) $sp $mu) -eq '') "Archivpfad: nur direkt im Ordner, nur nach Muster (unter Linux mit / geprüft)"
$kt = [regex]::Match($src, '(?s)\n(function Kern-Text\(.*?\n\})\n').Groups[1].Value
Invoke-Expression $kt
$env:LOCALAPPDATA = '/home/Jérémi Müller/AppData/Local'
Check ((Kern-Text 'Zugriff auf /home/Jérémi Müller/AppData/Local/Uzai/x') -eq 'Zugriff auf %LOCALAPPDATA%/Uzai/x' -and (Kern-Text ("a`nb" + ('x' * 400))).Length -le 240) "Grund ohne Benutzerpfad, ohne Zeilenumbruch, gekürzt"

""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
