# Prüft das Einspielen eines Updates im Helfer (helper/uzai-helper.ps1 -Update) in einem Temp-Ordner:
# 1. gutes Update: alte Dateien weg, neue da, Ergebnis ok, Quellordner weg, keine .alt- oder .neu-Reste;
# 2. Datei fehlt mittendrin: alles wie vorher (Rückweg), Ergebnis mit Grund;
# 3. fremder Dateiname im Auftrag: nichts angefasst;
# 4. Prüfsumme passt nicht (halb entpackt, Platte voll): nichts angefasst, keine .neu-Reste.
# Startet nichts außer dem Helfer selbst (neu_starten ist aus). Unter Windows mit Windows PowerShell 5 wie im Betrieb:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests/update_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$helfer = (Resolve-Path $args[0]).Path
$fails = 0
function Check($cond, $what) { if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" } }
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $ps)) { $ps = 'pwsh' }

function Lauf($root, $dateien, $quelleInhalt, $falsch = '') {
    $dir = Join-Path $root 'uzai'
    $quelle = Join-Path $root 'neu'
    New-Item -ItemType Directory -Force $dir, $quelle | Out-Null
    'ALT-EXE' | Set-Content (Join-Path $dir 'Uzai.exe') -NoNewline
    'ALT-PCK' | Set-Content (Join-Path $dir 'Uzai.pck') -NoNewline
    foreach ($k in $quelleInhalt.Keys) { $quelleInhalt[$k] | Set-Content (Join-Path $quelle $k) -NoNewline }
    $ergebnis = Join-Path $root 'ergebnis.json'
    $sha = @{}
    foreach ($d in $dateien) {
        $p = Join-Path $quelle $d
        $sha[$d] = if (Test-Path $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() } else { '0' * 64 }
    }
    if ($falsch -ne '') { $sha[$falsch] = 'f' * 64 }
    $job = @{ pid = 0; dir = $dir; ordner = $quelle; dateien = $dateien; sha256 = $sha; fassung = '9.9.9'; neu_starten = $false; ergebnis = $ergebnis }
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($job | ConvertTo-Json -Compress)))
    & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helfer -Update $b64 | Out-Null
    $e = $null
    if (Test-Path $ergebnis) { $e = Get-Content $ergebnis -Raw | ConvertFrom-Json }
    return @{ dir = $dir; quelle = $quelle; e = $e }
}

$basis = Join-Path ([IO.Path]::GetTempPath()) ('uzai_probe_update_' + $PID)

"Gutes Update"
$r = Lauf (Join-Path $basis 'gut') @('Uzai.exe', 'Uzai.pck') @{ 'Uzai.exe' = 'NEU-EXE'; 'Uzai.pck' = 'NEU-PCK' }
Check ($r.e -and $r.e.ok) "Ergebnis ok"
Check ((Get-Content (Join-Path $r.dir 'Uzai.exe') -Raw) -eq 'NEU-EXE' -and (Get-Content (Join-Path $r.dir 'Uzai.pck') -Raw) -eq 'NEU-PCK') "neue Dateien drin"
Check (-not (Test-Path (Join-Path $r.dir 'Uzai.exe.alt')) -and -not (Test-Path (Join-Path $r.dir 'Uzai.pck.neu')) -and -not (Test-Path $r.quelle)) "keine .alt- oder .neu-Reste, Quellordner weg"

"Datei fehlt mittendrin"
$r = Lauf (Join-Path $basis 'halb') @('Uzai.exe', 'Uzai.pck') @{ 'Uzai.exe' = 'NEU-EXE' }
Check ($r.e -and -not $r.e.ok -and [string]$r.e.grund -ne '') "Ergebnis mit Grund"
Check ((Get-Content (Join-Path $r.dir 'Uzai.exe') -Raw) -eq 'ALT-EXE' -and (Get-Content (Join-Path $r.dir 'Uzai.pck') -Raw) -eq 'ALT-PCK') "alles wie vorher"
Check (-not (Test-Path (Join-Path $r.dir 'Uzai.exe.alt'))) "keine .alt-Reste"

"Fremder Dateiname"
$r = Lauf (Join-Path $basis 'fremd') @('Uzai.exe', 'Uzai.pck', 'version.dll') @{ 'Uzai.exe' = 'NEU-EXE'; 'Uzai.pck' = 'NEU-PCK'; 'version.dll' = 'X' }
Check ($r.e -and -not $r.e.ok) "abgelehnt"
Check ((Get-Content (Join-Path $r.dir 'Uzai.exe') -Raw) -eq 'ALT-EXE' -and -not (Test-Path (Join-Path $r.dir 'version.dll'))) "nichts angefasst"

"Prüfsumme passt nicht"
$r = Lauf (Join-Path $basis 'pruef') @('Uzai.exe', 'Uzai.pck') @{ 'Uzai.exe' = 'NEU-EXE'; 'Uzai.pck' = 'NEU-PCK' } 'Uzai.pck'
Check ($r.e -and -not $r.e.ok -and [string]$r.e.grund -like '*fsumme passt nicht*') "abgelehnt mit Grund"
Check ((Get-Content (Join-Path $r.dir 'Uzai.exe') -Raw) -eq 'ALT-EXE' -and (Get-Content (Join-Path $r.dir 'Uzai.pck') -Raw) -eq 'ALT-PCK') "alles wie vorher"
Check (-not (Test-Path (Join-Path $r.dir 'Uzai.exe.neu')) -and -not (Test-Path (Join-Path $r.dir 'Uzai.pck.neu'))) "keine .neu-Reste"

Remove-Item -Recurse -Force $basis -ErrorAction SilentlyContinue
""
"Ergebnis: " + $(if ($fails -eq 0) { 'alles ok' } else { "$fails Fehler" })
exit $fails
