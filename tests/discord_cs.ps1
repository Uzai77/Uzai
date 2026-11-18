# Prüft den C#-Teil für das Discord Social SDK (UzDsdk) aus helper/uzai-helper.ps1: als C# 5
# übersetzbar (Windows PowerShell 5 baut mit dem alten Compiler), ohne Warnungen; die neuen
# Angaben zur Aktivität (Art, App, Startzeit) stehen nur in try-Blöcken (ältere SDK-Fassungen);
# der Befehl „presence“ nimmt für status_display_type nur 0, 1 oder 2. Läuft auch unter Linux
# (pwsh 7); das SDK selbst prüft tests/net_discord_dm.gd mit der nachgebauten Bibliothek.
#   pwsh -NoProfile -File tests/discord_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = Get-Content -Raw $args[0]
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}
$dsdk = [regex]::Match($src, "\`$script:DsdkSrc = @`"\r?\n(?s)(.*?)\r?\n`"@").Groups[1].Value
Check ($dsdk.Length -gt 5000) "SDK-Quelltext gefunden"
Check (-not $dsdk.Contains('$')) "kein `$ im doppelt gequoteten Block (PowerShell würde es ersetzen)"
try {
    Add-Type -TypeDefinition $dsdk -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "UzDsdk übersetzt (C# 5, ohne Warnungen)"
} catch { Check $false ("UzDsdk: " + $_.Exception.Message) }
Check ($null -ne ('UzDsdk' -as [type])) "Klasse UzDsdk da"

# Die neuen SDK-Aufrufe stehen alle in einem try (EntryPointNotFound bei älteren Fassungen).
$uj = [regex]::Match($dsdk, '(?s)static string UserJson\(ref IntPtr user\) \{(.*?)\r?\n    \}').Groups[1].Value
Check ($uj.Length -gt 200) "UserJson gefunden"
$tries = [regex]::Matches($uj, '(?s)try \{(.*?)\} catch \(Exception\) \{ \}') | ForEach-Object { $_.Groups[1].Value }
$inTry = ($tries -join "`n")
foreach ($fn in @('Discord_Activity_Type', 'Discord_Activity_ApplicationId', 'Discord_Activity_Timestamps', 'Discord_ActivityTimestamps_Start', 'Discord_ActivityTimestamps_Drop')) {
    Check ($inTry.Contains($fn + '(')) "$fn nur im try-Block"
}
Check ($uj.Contains('if (atype < 0 || atype > 6) atype = 0;')) "Art der Aktivität begrenzt"
Check ($uj.Contains('Discord_ActivityTimestamps_Drop(ref ts)')) "Zeitangaben werden wieder freigegeben"
# Signaturen wie in cdiscord.h: Rückgabe bool als I1, Ausgabe über out.
Check ($dsdk -match 'MarshalAs\(UnmanagedType\.I1\)\] static extern bool Discord_Activity_Timestamps\(ref IntPtr self, out IntPtr ret\)') "Timestamps: bool, out-Handle"
Check ($dsdk -match 'MarshalAs\(UnmanagedType\.I1\)\] static extern bool Discord_Activity_ApplicationId\(ref IntPtr self, out ulong ret\)') "ApplicationId: bool, out uint64"
Check ($dsdk -match 'static extern ulong Discord_ActivityTimestamps_Start\(ref IntPtr self\)') "Start: uint64"

# presence: status_display_type nur als Zahl 0..2 (Get-Num aus dem Helfer).
Invoke-Expression ([regex]::Match($src, '(?s)\n(function Get-Num\(.*?\r?\n\})\r?\n').Groups[1].Value)
$pres = [regex]::Match($src, "(?s)\n        'presence' \{(.*?)\n        \}").Groups[1].Value
Check ($pres.Contains('$disp = Get-Num $a.display 9') -and $pres.Contains('if ($disp -ge 0 -and $disp -le 2) { $act.status_display_type = $disp }')) "presence prüft display"
function Disp($v) { $d = Get-Num $v 9; if ($d -ge 0 -and $d -le 2) { return $d } return $null }
Check ((Disp 2) -eq 2 -and (Disp '0') -eq 0) "2 und 0 werden übernommen"
Check ($null -eq (Disp 5) -and $null -eq (Disp -1) -and $null -eq (Disp '2; calc') -and $null -eq (Disp $null) -and $null -eq (Disp 'abc')) "5, -1, Befehl, nichts, Text: weggelassen"
# Bibliothek: nur mit gültiger Signatur von Discord Inc., gegen Tausch gesperrt, Abhängigkeiten eng.
$st = [regex]::Match($dsdk, '(?s)public static string Start\(string dllPath, ulong appId\) \{(.*?)running = true;').Groups[1].Value
Check (-not $dsdk.Contains('LoadLibraryW(')) "kein LoadLibraryW mehr (nur LoadLibraryExW mit Suchbeschränkung)"
Check ($st.IndexOf('SignedByDiscord(dllPath)') -gt 0 -and $st.IndexOf('SignedByDiscord(dllPath)') -lt $st.IndexOf('LoadLibraryExW(')) "Signatur wird vor dem Laden geprüft"
Check ($st.Contains('FileShare.Read)') -and $st.Contains('0x00000100 | 0x00000800')) "Datei gesperrt, Suche nur eigener Ordner und System32"
Check ($dsdk.Contains('const string Signer = "Discord Inc.";') -and $dsdk.Contains('00AAC56B-CD44-11d0-8CC2-00C04FC295EE')) "WinVerifyTrust und Aussteller Discord Inc."
Check ([UzDsdk]::SignedByDiscord('/tmp/evil.dll') -eq 'name') "fremder Dateiname abgelehnt"
""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
