# Prüft den Helfer als Ganzes (helper/uzai-helper.ps1), damit eine Änderung an irgendeiner Stelle nicht erst am
# Windows-PC auffällt:
# 1. PowerShell-Syntax der ganzen Datei.
# 2. Jeder eingebettete C#-Block wird übersetzt – als C# 5: Windows PowerShell 5 (damit läuft der Helfer) kann
#    nichts Neueres. Vier Blöcke brauchen Bibliotheken, die es nur unter Windows gibt (UI Automation,
#    System.Drawing); von ihnen wird hier nur die Syntax geprüft und grob nach neueren Sprachmitteln gesucht.
# 3. Der Helfer startet im Einmal-Modus und lehnt einen unbekannten Befehl ordentlich ab – sein Code auf
#    oberster Ebene läuft also durch.
# Was die einzelnen Teile tun, prüfen ihre eigenen Proben (pip_cs, raumton_cs, zimmer_treff_cs …). Läuft unter
# Linux (pwsh 7); unter Windows läuft nichts davon – dort zeigt erst der echte Start, ob alles stimmt.
#   pwsh -NoProfile -File tests/helfer_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$pfad = (Resolve-Path $args[0]).Path
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}
function Kurz($fehler) {
    $z = @(([string]$fehler) -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 2)
    if ($z.Count -eq 0) { $z = @(([string]$fehler) -split "`n" | Select-Object -First 1) }
    $t = ($z -join ' | ').Trim()
    if ($t.Length -gt 300) { $t = $t.Substring(0, 300) }
    return $t
}

"PowerShell"
$errs = $null; $tok = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($pfad, [ref]$tok, [ref]$errs)
$wo = ''
if ($errs.Count -gt 0) { $wo = ': Zeile ' + $errs[0].Extent.StartLineNumber + ', ' + $errs[0].Message }
Check ($errs.Count -eq 0) ("Syntax der ganzen Datei (" + $tok.Count + " Zeichenfolgen)" + $wo)

"C#-Blöcke"
# Greift die Einschränkung auf C# 5 überhaupt? Ein Satz aus C# 6 muss scheitern, sonst prüfte diese Probe nichts.
$abgelehnt = $false
try {
    Add-Type -TypeDefinition 'public static class UzSprachProbe { public static string X(int a) { return $"{a}"; } }' -CompilerOptions @('-langversion:5') -ErrorAction Stop
} catch { $abgelehnt = $true }
Check $abgelehnt "die Übersetzung lehnt C# 6 ab"

# Die Blöcke: Zuweisungen „$script:…Src = @'…'@“ und Texte direkt hinter Add-Type.
$L = [System.Management.Automation.Language.StringConstantExpressionAst]
$E = [System.Management.Automation.Language.ExpandableStringExpressionAst]
$bloecke = @()
foreach ($z in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -match '^\$script:\w+Src$' }, $true)) {
    $s = $z.Right.Find({ param($n) $n -is $L -or $n -is $E }, $true)
    if ($null -ne $s) { $bloecke += , @($z.Left.Extent.Text.Substring(8), $s) }
}
foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Type' }, $true)) {
    foreach ($el in $c.CommandElements) {
        if (($el -is $L -or $el -is $E) -and $el.Extent.Text.StartsWith('@')) { $bloecke += , @('Block hinter Add-Type', $el) }
    }
}
Check ($bloecke.Count -ge 29) ("Blöcke gefunden: " + $bloecke.Count)

# Nur unter Windows übersetzbar (UI Automation aus WPF, System.Drawing).
$nurWindows = @('UiaSrc', 'SpotUiSrc', 'SnapSrc', 'AppFeldSrc')
$parse = [Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::new([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp5)
# Sprachmittel ab C# 6, an denen der alte Übersetzer scheitert: $"…", ?. und ?[, nameof(…), „out var“, „is not“.
$neuer = '\$"|\?\.[A-Za-z_(]|\?\[|\bnameof\s*\(|\bout\s+var\s|\bis\s+not\s'
foreach ($b in $bloecke) {
    $name = $b[0]
    $text = [string]$b[1].Value
    if ($b[1] -is $E) { $text = $ExecutionContext.InvokeCommand.ExpandString($text) }
    $zeile = $b[1].Extent.StartLineNumber
    if ($nurWindows -contains $name) {
        $d = @([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText($text, $parse).GetDiagnostics() | Where-Object { [string]$_.Severity -eq 'Error' })
        $was = ''
        if ($d.Count -gt 0) { $was = ': ' + (Kurz ([string]$d[0])) }
        Check ($d.Count -eq 0) ("$name (Zeile $zeile): Syntax in Ordnung – übersetzt wird er nur unter Windows" + $was)
        # Kommentare und Texte in Anführungszeichen zählen nicht.
        $kahl = [regex]::Replace($text, '//[^\n]*|"(\\.|[^"\\\n])*"', '""')
        $m = [regex]::Match($kahl, $neuer)
        Check (-not $m.Success) ("$name – keine Sprachmittel nach C# 5 (grobe Suche)" + $(if ($m.Success) { ': ' + $m.Value } else { '' }))
        continue
    }
    try {
        Add-Type -TypeDefinition $text -CompilerOptions @('-langversion:5') -IgnoreWarnings -ErrorAction Stop
        Check $true "$name (Zeile $zeile) übersetzt"
    } catch { Check $false ("$name (Zeile $zeile): " + (Kurz $_.Exception.Message)) }
}

"Kleine Funktionen"
# Test-DateiMuster (Remote Play: verlangt das Programm Adminrechte?): liest in Stücken – der Treffer muss an jeder
# Stelle gefunden werden, auch über eine Stückgrenze hinweg.
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-DateiMuster' }, $true)
Check ($null -ne $fn) "Test-DateiMuster gefunden"
if ($null -ne $fn) {
    . ([scriptblock]::Create($fn.Extent.Text))
    $muster = 'level\s*=\s*[''"](requireAdministrator|highestAvailable)[''"]'
    $treffer = [Text.Encoding]::ASCII.GetBytes('level="requireAdministrator"')
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("uzai-muster-" + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    try {
        $datei = Join-Path $dir 'probe.bin'
        $alle = $true
        foreach ($vor in 0..200) {
            $b = New-Object byte[] ($vor + $treffer.Length + 90)
            for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = 65 }
            [Array]::Copy($treffer, 0, $b, $vor, $treffer.Length)
            [IO.File]::WriteAllBytes($datei, $b)
            if (-not (Test-DateiMuster $datei $muster 64MB 64 48)) { $alle = $false; break }
        }
        Check $alle "Treffer an jeder Stelle gefunden (Stücke zu 64 Bytes, 48 Bytes Überlappung)"
        $b = New-Object byte[] 5000
        for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = 65 }
        [IO.File]::WriteAllBytes($datei, $b)
        Check (-not (Test-DateiMuster $datei $muster 64MB 64 48)) "ohne Treffer: nein"
        [Array]::Copy($treffer, 0, $b, 100, $treffer.Length)
        [IO.File]::WriteAllBytes($datei, $b)
        Check (Test-DateiMuster $datei $muster 64MB) "mit den Vorgaben (1 MB je Stück): gefunden"
        Check (-not (Test-DateiMuster $datei $muster 1000 64 48)) "Treffer vor den letzten 1000 Bytes: zählt nicht"
        [IO.File]::WriteAllBytes($datei, (New-Object byte[] 0))
        Check (-not (Test-DateiMuster $datei $muster 64MB)) "leere Datei: nein"
        $geworfen = $false
        try { [void](Test-DateiMuster (Join-Path $dir 'gibt-es-nicht.bin') $muster 64MB) } catch { $geworfen = $true }
        Check $geworfen "fehlende Datei: Fehler (der Aufrufer fängt ihn)"
    } finally { [IO.Directory]::Delete($dir, $true) }
}

# FxSound: Die Befehlszeile baut der Helfer selbst (FxSounds Zerleger kennt kein Maskieren). Kein Name darf eine
# weitere Option einschleusen; --run_minimized steht immer dabei (sonst käme FxSounds Fenster nach vorn).
foreach ($name in @('Get-Zahl', 'Fx-Wert', 'Fx-Neu', 'Fx-Zeile')) {
    $f = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }.GetNewClosure(), $true)
    Check ($null -ne $f) "$name gefunden"
    if ($null -ne $f) { . ([scriptblock]::Create($f.Extent.Text)) }
}
$fx = 'C:\Program Files\FxSound LLC\FxSound\FxSound.exe'
Check ((Fx-Zeile $fx @{ output = 'LG TV (NVIDIA High Definition Audio)' }) -eq ('"' + $fx + '" --output="LG TV (NVIDIA High Definition Audio)" --run_minimized')) "FxSound: Ausgabegerät als ein Wert in Anführungszeichen, still"
Check ((Fx-Zeile $fx @{ power = 1; preset = 'Bass Boost' }) -eq ('"' + $fx + '" --power=1 --preset="Bass Boost" --run_minimized')) "FxSound: an und Klangprofil in einem Aufruf"
Check ((Fx-Zeile $fx @{ power = 0 }) -eq ('"' + $fx + '" --power=0 --run_minimized')) "FxSound: aus"
Check ($null -eq (Fx-Zeile $fx @{ output = 'TV" --power=0 --preset="x' })) "FxSound: ein Anführungszeichen im Namen wird abgelehnt (keine eingeschleuste Option)"
Check ($null -eq (Fx-Zeile $fx @{ preset = ("a" + [char]10 + "b") }) -and $null -eq (Fx-Zeile $fx @{ preset = '' }) -and $null -eq (Fx-Zeile $fx @{ output = ('x' * 201) })) "FxSound: Steuerzeichen, leer, zu lang: abgelehnt"
Check ($null -eq (Fx-Zeile $fx @{ power = 2 }) -and $null -eq (Fx-Zeile $fx @{ power = $true }) -and $null -eq (Fx-Zeile $fx @{ power = '1 --output=x' })) "FxSound: an/aus nur als 0 oder 1"
Check ($null -eq (Fx-Zeile $fx @{}) -and $null -eq (Fx-Zeile $fx @{ op = 'set'; anderes = 'x' })) "FxSound: nichts zu setzen: kein Aufruf"
Check ($null -eq (Fx-Zeile $fx @{ preset = ('p' * 65) }) -and $null -ne (Fx-Zeile $fx @{ preset = ('p' * 64) })) "FxSound: Klangprofil höchstens 64 Zeichen"
Check ((Fx-Neu '1.2.11.0') -and (Fx-Neu '1.2.15.0') -and (Fx-Neu '1.3.0') -and (Fx-Neu '2.0.0.0') -and -not (Fx-Neu '1.2.10.0') -and -not (Fx-Neu '1.1.22.0') -and -not (Fx-Neu '') -and -not (Fx-Neu 'x.y.z')) "FxSound: Befehle erst ab 1.2.11"
Check ((Fx-Wert 'Kopfhörer (Xbox Wireless Headset)') -and -not (Fx-Wert ('a' + [char]9 + 'b')) -and -not (Fx-Wert ('a' + [char]127))) "FxSound: Umlaute und Klammern gehen, Tabulator und DEL nicht"

# UzSteamStill (Steams Mitteilungs-Fenster, solange Uzai läuft): Nur genau der bekannte Titel zählt; für die
# Diagnose merkt sich der Helfer nur Titel, die ähnlich heißen – nie Chats oder Namen.
Check ([UzSteamStill]::IstMitteilung('notificationtoasts_18_desktop')) "Mitteilungs-Fenster von Steam am Titel erkannt"
Check (-not [UzSteamStill]::IstMitteilung('notificationtoasts__desktop') -and -not [UzSteamStill]::IstMitteilung('notificationtoasts_1a_desktop')) "nur Ziffern in der Mitte"
Check (-not [UzSteamStill]::IstMitteilung('Steam') -and -not [UzSteamStill]::IstMitteilung('') -and -not [UzSteamStill]::IstMitteilung($null)) "andere Fenster von Steam: nein"
Check (-not [UzSteamStill]::IstMitteilung('xnotificationtoasts_18_desktop') -and -not [UzSteamStill]::IstMitteilung('notificationtoasts_18_desktop ')) "nichts davor, nichts dahinter"
Check (-not [UzSteamStill]::IstMitteilung('notificationtoasts_' + ('1' * 40) + '_desktop')) "überlange Titel: nein"
Check ([UzSteamStill]::Aehnelt('NotificationToasts_18_bpm') -and -not [UzSteamStill]::Aehnelt('Mila – Chat')) "ähnliche Titel für die Diagnose, Chats nie"
Check (-not [UzSteamStill]::Aktiv() -and [UzSteamStill]::Aus() -eq 0) "ohne Einschalten läuft nichts, Abschalten ändert nichts"

"Startlauf"
# Als .NET-Werkzeug installiert läuft pwsh als „dotnet pwsh.dll“: Dann gehört die DLL vor die Argumente.
$exe = (Get-Process -Id $PID).Path
$vor = @()
if ([IO.Path]::GetFileNameWithoutExtension($exe) -eq 'dotnet') { $vor = @([Environment]::GetCommandLineArgs()[0]) }
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"id":7,"cmd":"gibt-es-nicht","args":{}}'))
$out = & $exe @vor -NoProfile -NonInteractive -File $pfad -Once $b64 2>$null
$r = $null
foreach ($l in @($out)) { try { $x = $l | ConvertFrom-Json; if ($null -ne $x.ok) { $r = $x } } catch {} }
Check ($null -ne $r -and $r.id -eq 7 -and -not $r.ok -and ([string]$r.error).StartsWith('Unbekannter Befehl')) "der Helfer startet (Einmal-Modus) und lehnt einen unbekannten Befehl ab"

if ($fails -gt 0) { "Ergebnis: $fails Fehler"; exit 1 }
"Ergebnis: alles ok"
