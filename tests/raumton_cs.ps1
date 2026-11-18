# Probe für den Spielton aus dem Fernseher des Zimmers (UzAudio.RaumTon und Befehl „raum-ton“ in
# helper/uzai-helper.ps1, src/room/raumton.gd): der Audio-Teil übersetzt mit C# 5 (Warnungen als Fehler),
# Kanal-Faktoren je Lautsprecher-Anordnung, Grenzen, „aus“ ohne Zustand, nur Zahlen als Argumente, nie die
# Gesamtlautstärke, Zurückstellen am Ende des Helfers. Core Audio selbst läuft hier nicht.
#   pwsh -NoProfile -File tests/raumton_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

$m = [regex]::Match($src, "(?s)\`$script:AudioSrc = @`"\n(.*?)\n`"@")
$code = $m.Groups[1].Value
Check ($code.Length -gt 5000) ("UzAudio-Block gefunden (" + $code.Length + " Zeichen)")
Check (-not $code.Contains('$') -and -not $code.Contains('`')) "keine Zeichen, die PowerShell im Block ersetzen würde"
try {
    Add-Type -TypeDefinition $code -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "UzAudio übersetzt (C# 5, Warnungen als Fehler)"
} catch { Check $false ("UzAudio: " + $_.Exception.Message) }

"Kanäle"
function F($n, $l, $r) { return (([UzAudio]::Faktoren($n, $l, $r) | ForEach-Object { [Math]::Round($_, 2) }) -join ' ') }
Check ((F 2 0.4 1.0) -eq '0.4 1') "Stereo: links, rechts"
Check ((F 1 0.4 1.0) -eq '0.7') "Mono: der Schnitt"
Check ((F 3 0.4 1.0) -eq '0.4 1 0.7') "2.1: Bass mittig"
Check ((F 4 0.4 1.0) -eq '0.4 1 0.4 1') "Quadro: vorn und hinten je Seite"
Check ((F 5 0.4 1.0) -eq '0.4 1 0.7 0.4 1') "5.0: Mitte, dann hinten links/rechts"
Check ((F 6 0.4 1.0) -eq '0.4 1 0.7 0.7 0.4 1') "5.1: Mitte und Bass mittig"
Check ((F 8 0.4 1.0) -eq '0.4 1 0.7 0.7 0.4 1 0.4 1') "7.1: hinten und seitlich je Seite"
Check (([UzAudio]::Faktoren(20, 1, 1)).Count -eq 8 -and ([UzAudio]::Faktoren(-3, 1, 1)).Count -eq 0) "höchstens acht Kanäle, nie negativ"
Check ((F 2 -5 7) -eq '0 1') "Faktoren begrenzt auf 0..1"
Check ([UzAudio]::Klemme([float]::NaN) -eq 0 -and [UzAudio]::Klemme(2) -eq 1 -and [UzAudio]::Klemme(-1) -eq 0) "Klemme: NaN, zu groß, negativ"
Check ([UzAudio]::LeaseMs -le 5000 -and [UzAudio]::LeaseMs -ge 2000) ("ohne Lebenszeichen nach " + [UzAudio]::LeaseMs + " ms zurück")
$aus = [UzAudio]::RaumTonAus() | ConvertFrom-Json
Check ($aus.found -eq $false -and $aus.zurueck -eq 0 -and $aus.weg -eq 0) "aus ohne Zustand: nichts zu tun, nichts weg"

"Befehl"
$i = $src.IndexOf("        'raum-ton' {")
Check ($i -gt 0) "fester Befehl raum-ton"
$ende = $src.IndexOf("`n        }`n", $i)
$block = $src.Substring($i, $ende - $i)
Check ($block.Contains('Get-Num $a.l 1000') -and $block.Contains('Get-Num $a.r 1000') -and $block.Contains('Get-Num $_ 1000')) "links, rechts und alte Werte nur als begrenzte Zahlen"
Check (-not ($block -match 'Invoke-|Start-|iex|MasterSet|Volume\(|SetMasterVolumeLevel')) "führt nichts aus, nie die Gesamtlautstärke"
Check ($block.Contains('-gt 8')) "höchstens acht alte Werte"
$fn = [regex]::Match($code, "(?s)public static string RaumTon\(.*?\n    }\n").Value
Check ($fn.Length -gt 200 -and -not $fn.Contains('Endpoint(') -and -not $fn.Contains('MasterVolumeLevel')) "RaumTon fasst nur Sitzungen des Spiels an, nie das Wiedergabegerät"
Check ($fn.Contains('RtSitzungen(') -and $code.Contains('GameTree(Snapshot(), pidsCsv, dir, hwnd, skipCsv)')) "nur das Spiel samt Kindprozessen (Uzai ausgenommen)"
$schleife = $src.Substring($src.LastIndexOf("while (`$true) {"))
Check ($schleife.Contains('[UzAudio]::RaumTonAus()') -and $schleife.IndexOf('RaumTonAus') -lt $schleife.IndexOf('Crash-Restart')) "Uzai zu: der Helfer stellt den Ton zurück"

# Argumente prüfen, ohne Core Audio: der Befehlsblock als Skriptblock mit dem echten Get-Num.
$gn = [regex]::Match($src, "(?s)function Get-Num\(.*?\n}\n").Value
. ([scriptblock]::Create($gn))
function Use-Audio { }
$body = $block.Substring($block.IndexOf('{') + 1)
$sb = [scriptblock]::Create("param(`$a)`n" + $body)
foreach ($fall in @(@{ was = 'links fehlt'; a = @{ r = 500 } }, @{ was = 'links Text'; a = @{ l = '1; calc'; r = 500 } },
        @{ was = 'werte leer'; a = @{ werte = @() } }, @{ was = 'werte zu viele'; a = @{ werte = @(1, 2, 3, 4, 5, 6, 7, 8, 9) } },
        @{ was = 'werte Text'; a = @{ werte = @(1000, 'x') } })) {
    $r = & $sb ([pscustomobject]$fall.a)
    Check ($r.json -eq '{"found":false,"error":"args"}') ("raum-ton " + $fall.was + " → args")
}
$r = & $sb ([pscustomobject]@{ l = 5000; r = 300; pids = @(1234) })
$j = $r.json | ConvertFrom-Json
Check ($null -ne $j -and $j.found -eq $false) "zu großer Wert wird begrenzt (hier ohne Core Audio: nichts gefunden)"

""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
