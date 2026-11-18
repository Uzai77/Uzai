# Nur für Tests unter Linux (tests/logic_zimmer_netz.gd): die Sitzungs-Schleife der Zimmer-Sandbox
# (UzaiZimmerNetz.Netz aus helper/uzai-helper.ps1) direkt an Standardeingabe und -ausgabe – wie im
# AppContainer, nur ohne ihn. So prüft Uzai seine Seite der Leitung (Prüfmauer 2) gegen die echte
# Prüfmauer 1 über eine echte Pipe. Kein Netz außer 127.0.0.1, keine Dateien.
#   pwsh -NoProfile -NonInteractive -File tests/zimmer_netz_stdio.ps1 <helper/uzai-helper.ps1> gastgeber|gast
$ErrorActionPreference = 'Stop'
if ($args.Count -ne 2 -or @('gastgeber', 'gast') -cnotcontains $args[1]) { exit 2 }
$src = Get-Content -Raw -LiteralPath $args[0]
$cs = [regex]::Match($src, "\`$script:ZimmerNetzSrc = @'\r?\n(?s)(.*?)\r?\n'@").Groups[1].Value
Add-Type -TypeDefinition $cs
$ein = [Console]::OpenStandardInput()
# Wie im Kindprozess: eigene Kopie der Ausgabe, fd 1/2 auf /dev/null (was eine Netz-Bibliothek schreibt, trifft nie
# die Leitung). Mit UZAI_NETZLIB_TEST lädt die Sandbox die Linux-Fassung der Bibliotheken (echter Datenkanal).
$aus = [UzNetzLib]::AusgabeSchuetzen()
if ($null -eq $aus) { $aus = [Console]::OpenStandardOutput() }
exit ([UzaiZimmerNetz]::Netz($ein, $aus, $args[1] -eq 'gastgeber', $true))
