# Prüft den Helfer-Befehl „emu-hints“ (helper/uzai-helper.ps1, src/core/emu_suche.gd): liest nur
# (Registry-Einträge, Prozesse, Versionsangaben), startet nichts, kürzt Texte, begrenzt Listen und
# liefert unter Linux (ohne Registry) leere bzw. gültige Listen.
#   pwsh -NoProfile -File tests/emusuche_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$helper = $args[0]
$src = (Get-Content -Raw $helper) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

"Befehl"
Check ($src.Contains("'emu-hints' { return (Get-EmuHints) }")) "emu-hints angemeldet, ohne Eingaben"
$fn = ''
foreach ($n in @('Get-EmuHintText', 'Get-EmuHintProduct', 'Get-EmuHints')) {
    $fn += [regex]::Match($src, "(?s)\n(function $n\(?.*?\n\})\n").Groups[1].Value + "`n"
}
Check ($fn.Length -gt 1500) "Funktionen gefunden"
foreach ($bad in @('Start-Process', 'Invoke-Item', 'Invoke-Expression', '& $', 'Set-ItemProperty', 'New-Item', 'Remove-Item', 'Process]::Start')) {
    Check (-not $fn.Contains($bad)) "nichts gestartet oder geschrieben ($bad)"
}
Invoke-Expression $fn

"Texte"
Check ((Get-EmuHintText "Ret`u{0007}ro`nArch") -eq 'Ret ro Arch') "Steuerzeichen weg"
Check ((Get-EmuHintText ('x' * 900)).Length -eq 400 -and (Get-EmuHintText ('x' * 900) 200).Length -eq 200) "gekürzt"
Check ((Get-EmuHintText $null) -eq '') "leer bleibt leer"
Check ((Get-EmuHintProduct '\\server\share\retroarch.exe') -eq '') "Netzpfad: keine Versionsangaben gelesen"
Check ((Get-EmuHintProduct 'retroarch.exe') -eq '' -and (Get-EmuHintProduct 'C:\x\readme.txt,0') -eq '') "nur ganze Pfade zu .exe"

"Ergebnis des Befehls"
$r = Get-EmuHints
Check ($r.ContainsKey('uninstall') -and $r.ContainsKey('procs')) "uninstall und procs"
Check (@($r.procs).Count -le 300 -and @($r.uninstall).Count -le 3000) "Listen begrenzt"
$okp = @($r.procs | Where-Object { $_.path -is [string] -and $_.path.Length -le 400 })
Check ($okp.Count -eq @($r.procs).Count) "Prozesse: Pfade als kurze Texte ($($okp.Count))"
$json = $r | ConvertTo-Json -Depth 5 -Compress
Check ($json.Length -gt 10) "als JSON zu senden"
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
