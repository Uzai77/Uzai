# Prüft die Helfer-Befehle für eigene Apps (helper/uzai-helper.ps1, src/core/apps_extern.gd,
# docs/SECURITY.md „Apps“): der C#-Teil UzAppAct übersetzt mit C# 5 ohne Warnungen; Test-Aumid,
# Test-ProgPath, Test-ExtAppIdent (gehört ein Fenster zur App?) und die Sperrliste lehnen ab, was sie sollen; die Befehle app-start, app-logo,
# app-media, prog-check, app-window, app-vollbild, app-pad und app-text scheitern mit falschen Angaben an einer Prüfung, bevor
# Windows etwas davon sieht (unter Linux auch mit richtigen: es gibt kein installiertes Paket, also
# keine Aktivierung). Läuft unter Linux (pwsh 7).
#   pwsh -NoProfile -File tests/apps_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$helper = $args[0]
$src = (Get-Content -Raw $helper) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

"C#-Teil"
$cs = [regex]::Match($src, "\`$script:AppActSrc = @'\n(?s)(.*?)\n'@").Groups[1].Value
Check ($cs.Length -gt 2000) "UzAppAct gefunden"
try {
    Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "übersetzt (C# 5, ohne Warnungen)"
} catch { Check $false ("UzAppAct: " + $_.Exception.Message) }
Check ($cs.Contains('ActivateApplication(aumid, null, 0, out pid)')) "Aktivierung ohne Parameter"
Check ($cs.Contains('45BA127D-10A8-46EA-8AB7-56EA9078943C') -and $cs.Contains('2e941141-7f97-4756-ba1d-9decde894a3d')) "offizieller ApplicationActivationManager"
Check (-not $cs.Contains('ShellExecute') -and -not $cs.Contains('Process.Start')) "kein Start über die Shell im C#-Teil"
Check (-not $cs.Contains('SystemParametersInfo') -and -not $cs.Contains('Shell_TrayWnd') -and -not $cs.Contains('SendInput') -and -not $cs.Contains('keybd_event')) "Vollbild: nur das App-Fenster (keine Systemeinstellung, keine Taskleiste, keine Tasten)"
Check ($cs.Contains('if (!IsWindow(h) || PidOf(h) != v.Pid) return false;')) "Zurück nur am selben Fenster desselben Prozesses"

"Rand oben frei (UzAppRand)"
Check ([UzAppRand]::RandPx(1080) -eq 11 -and [UzAppRand]::RandPx(2160) -eq 22 -and [UzAppRand]::RandPx(600) -eq 8 -and [UzAppRand]::RandPx(9000) -eq 40 -and [UzAppRand]::RandPx(0) -eq 0) "Rand: 1/100 der Höhe, 8 bis 40 Pixel"
Check ([UzAppRand]::Schritt($true, $true, $true, $false) -eq 1 -and [UzAppRand]::Schritt($true, $true, $false, $true) -eq 1) "Grenze nur mit der App vorn im Vollbild (Zeiger dort oder Grenze schon da)"
Check ([UzAppRand]::Schritt($true, $true, $false, $false) -eq 0) "Zeiger auf einem anderen Bildschirm: nicht einfangen"
Check ([UzAppRand]::Schritt($false, $true, $true, $true) -eq -1 -and [UzAppRand]::Schritt($true, $false, $true, $true) -eq -1) "anderes Fenster vorn bzw. kein Vollbild: freigeben"
Check ([UzAppRand]::Schritt($false, $false, $false, $false) -eq 0) "fremde Grenze (Spiel) nie anfassen"
Check ($cs.Contains('if (GetClipCursor(out jetzt) && Gleich(jetzt, gesetzt)) ClipCursorFrei(IntPtr.Zero);')) "freigegeben wird nur die eigene Grenze"
$fs = [regex]::Match($src, "\`$script:AppFeldSrc = @'\n(?s)(.*?)\n'@").Groups[1].Value
Check ($fs.Contains('AutomationElement.FocusedElement') -and -not $fs.Contains('.Current.Name') -and -not $fs.Contains('GetCurrentValue') -and -not $fs.Contains('.Value') -and -not $fs.Contains('SendInput')) "Textfeld: nur Art, Zustand und Prozess des Fokus – nie sein Inhalt, keine Tasten"
Check ($fs.Contains('if (p != a && p != b) return 0;') -and $fs.Contains('GetForegroundWindow() != h')) "Textfeld: nur im App-Fenster vorn, nur ihr Prozess"
# UI Automation gibt es unter Linux nicht: mit Platzhaltern übersetzen (nur Form und Sprache).
$stub = @'
namespace System.Windows.Automation {
  public class ControlType { public int Id; }
  public class UzInfo { public int ProcessId; public ControlType ControlType; public bool IsEnabled; public bool IsPassword; }
  public class AutomationPattern {}
  public class UzWert { public bool IsReadOnly; }
  public class ValuePattern { public static AutomationPattern Pattern; public UzWert Current; }
  public class AutomationElement { public static AutomationElement FocusedElement; public UzInfo Current; public bool TryGetCurrentPattern(AutomationPattern p, out object o) { o = null; return false; } }
}
'@
try {
    Add-Type -TypeDefinition ($fs + "`n" + $stub) -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check ([UzAppFeld]::FeldJetzt() -eq 0) "UzAppFeld übersetzt (C# 5, ohne Warnungen); aus: kein Textfeld"
} catch { Check $false ("UzAppFeld: " + $_.Exception.Message) }

"Prüfungen"
$names = @('Test-Aumid', 'Test-AppBlockedName', 'Test-ProgPath', 'Test-AppMediaId', 'Get-AppCleanText', 'Test-ExtAppIdent')
$fn = ''
foreach ($n in $names) { $fn += [regex]::Match($src, "(?s)\n(function $n\(.*?\n\})\n").Groups[1].Value + "`n" }
$fn += [regex]::Match($src, "(?s)\n(\`$script:AppGesperrt = @\(.*?\))\n").Groups[1].Value + "`n"
Invoke-Expression $fn
Check ($script:AppGesperrt.Count -ge 20) "Sperrliste mit $($script:AppGesperrt.Count) Namen"
foreach ($ok in @('4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App', 'Disney.37853FC22B2CE_6rarf9sa4v8jt!App', 'AmazonVideo.PrimeVideo_pwbj9vvecjh7j!App')) {
    Check (Test-Aumid $ok) "AUMID gültig: $ok"
}
$bad = @('', 'Netflix', '4DF9E0F8.Netflix_mcm4njqhnhss8!', '4DF9E0F8.Netflix_MCM4NJQHNHSS8!App', "4DF9E0F8.Netflix_mcm4njqhnhss8!App`n",
    '4DF9E0F8.Netflix_mcm4njqhnhss8!App; calc', '4DF9E0F8.Netflix_mcm4njqhnhss8!App&calc', '4DF9E0F8.Netflix_mcm4njqhnhss8!1App',
    'N*_mcm4njqhnhss8!App', 'N?x_mcm4njqhnhss8!App', '[ab]_mcm4njqhnhss8!App', ('4DF9E0F8.Netflix_mcm4njqhnhss8!' + ('A' * 65)),
    'shell:AppsFolder\4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App')
$leak = @($bad | Where-Object { Test-Aumid $_ })
Check ($leak.Count -eq 0) ("$($bad.Count) falsche AUMIDs abgelehnt (auch Platzhalter für Get-AppxPackage)" + $(if ($leak.Count) { ': ' + ($leak -join ' | ') } else { '' }))
foreach ($ok in @('C:\Program Files\Kodi\kodi.exe', 'D:/Spiele/Moonlight/Moonlight.exe', 'C:\Program Files\Plex\Plex HTPC\Plex HTPC.exe')) {
    Check ((Test-ProgPath $ok) -eq '') "Programm in Ordnung: $ok"
}
$sh = 'Shells und Skript-Programme startet Uzai nicht.'
foreach ($b in @('C:\Windows\System32\cmd.exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\PowerShell.exe', 'C:\pwsh\pwsh.exe',
        'C:\Windows\System32\wscript.exe', 'C:\Windows\System32\cscript.exe', 'C:\Windows\System32\mshta.exe', 'C:\Windows\System32\rundll32.exe',
        'C:\Windows\System32\regsvr32.exe', 'C:\Python312\python3.12.exe', 'C:\Windows\explorer.exe')) {
    Check ((Test-ProgPath $b) -eq $sh) ("gesperrt: " + $b.Substring($b.LastIndexOf('\') + 1))
}
foreach ($b in @('C:\x\a.bat', 'C:\x\a.cmd', 'C:\x\a.ps1', 'C:\x\a.vbs', 'C:\x\a.js', 'C:\x\a.lnk', 'C:\x\a.hta', 'C:\x\a.exe.lnk')) {
    Check ((Test-ProgPath $b) -eq 'Nur Programme (.exe) – keine Skripte oder Verknüpfungen.') ("nur .exe: " + $b.Substring(5))
}
$weird = @('', 'kodi.exe', '\\server\share\kodi.exe', '\\?\C:\kodi.exe', 'C:kodi.exe', 'C:\..\kodi.exe', 'C:\a\..\Windows\System32\cmd.exe',
    'C:\a\kodi.exe:x.exe', 'C:\a\ko"di.exe', 'C:\a\ko|di.exe', 'C:\a\kodi.exe.', "C:\a\ko`ndi.exe", ('C:\' + ('a\' * 140) + 'kodi.exe'))
$leak = @($weird | Where-Object { (Test-ProgPath $_) -eq '' })
Check ($leak.Count -eq 0) ("$($weird.Count) seltsame Pfade abgelehnt" + $(if ($leak.Count) { ': ' + ($leak -join ' | ') } else { '' }))
Check ((Test-AppBlockedName 'Cmd.Exe') -and (Test-AppBlockedName 'POWERSHELL') -and -not (Test-AppBlockedName 'kodi.exe')) "Originalname einer umbenannten Shell (Cmd.Exe aus den Versionsangaben) zählt"
Check ((Test-AppMediaId 'kodi.exe') -and (Test-AppMediaId '4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App') -and -not (Test-AppMediaId "kodi.exe`n") -and -not (Test-AppMediaId 'a;b.exe')) "Kennung der Mediensitzung geprüft"
Check ((Get-AppCleanText "Net`u{0007}flix`n") -eq 'Netflix' -and (Get-AppCleanText ('x' * 300)).Length -eq 120) "Namen ohne Steuerzeichen, begrenzt"

"Gehört das Fenster zur App? (Test-ExtAppIdent)"
$nf = '4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App'
Check (Test-ExtAppIdent 'store' $nf @{ win = $nf }) "Store-App: Kennung am Fenster (Web-App im Browser-Prozess)"
Check (Test-ExtAppIdent 'store' $nf @{ proc = $nf.ToLower() }) "Store-App: Kennung des Prozesses"
Check (Test-ExtAppIdent 'store' $nf @{ child = $nf }) "Store-App: Inhalt im Rahmen (ApplicationFrameWindow)"
Check (-not (Test-ExtAppIdent 'store' $nf @{ win = 'Disney.37853FC22B2CE_6rarf9sa4v8jt!App'; proc = 'MSEdge'; child = '' })) "Store-App: andere Kennung nein"
Check (-not (Test-ExtAppIdent 'store' $nf @{})) "Store-App: ohne Kennung nein (etwa ein beliebiges Browserfenster)"
Check (-not (Test-ExtAppIdent 'store' 'N*_mcm4njqhnhss8!App' @{ win = 'N*_mcm4njqhnhss8!App' })) "Store-App: ungültige Kennung nein"
$kodi = 'C:\Program Files\Kodi\kodi.exe'
Check (Test-ExtAppIdent 'prog' $kodi @{ img = 'c:\program files\kodi\KODI.exe' }) "Programm: genau diese Datei"
Check (Test-ExtAppIdent 'prog' 'C:\Program Files\Plex\Plex HTPC\Plex HTPC.exe' @{ img = 'C:\Program Files\Plex\Plex HTPC\bin\Plex.exe' }) "Programm: Starter, Fenster aus dem eigenen Ordner"
Check (-not (Test-ExtAppIdent 'prog' $kodi @{ img = 'C:\Program Files\Kodi\..\Evil\x.exe' })) "Programm: Pfad mit .. nein"
Check (-not (Test-ExtAppIdent 'prog' $kodi @{ img = 'C:\Program Files\KodiBoese\kodi.exe' })) "Programm: Ordner, der nur so anfängt, nein"
Check (-not (Test-ExtAppIdent 'prog' $kodi @{ img = 'C:\Program Files\Kodi\cmd.exe' })) "Programm: Shell im Ordner nein"
Check (-not (Test-ExtAppIdent 'prog' 'C:\kodi.exe' @{ img = 'C:\other.exe' }) -and (Test-ExtAppIdent 'prog' 'C:\kodi.exe' @{ img = 'C:\kodi.exe' })) "Programm direkt auf dem Laufwerk: nur es selbst"
Check (-not (Test-ExtAppIdent 'prog' 'C:\Windows\System32\cmd.exe' @{ img = 'C:\Windows\System32\cmd.exe' })) "gesperrtes Programm nie"
Check (-not (Test-ExtAppIdent 'prog' $kodi @{ img = '' }) -and -not (Test-ExtAppIdent 'shell' $kodi @{ img = $kodi })) "ohne Programmpfad, unbekannte Art: nein"

"Befehle (ohne Windows: nichts wird aktiviert oder gestartet)"
# Als .NET-Werkzeug installiert („dotnet tool install PowerShell“) läuft pwsh als „dotnet pwsh.dll“: Dann gehört die
# DLL vor die Argumente – sonst startete der zweite Prozess nur „dotnet“, und jeder Befehl hier schlüge fehl.
$pwshExe = (Get-Process -Id $PID).Path
$pwshVor = @()
if ([IO.Path]::GetFileNameWithoutExtension($pwshExe) -eq 'dotnet') { $pwshVor = @([Environment]::GetCommandLineArgs()[0]) }
function Once($cmd, $a) {
    $j = @{ id = 1; cmd = $cmd; args = $a } | ConvertTo-Json -Compress -Depth 5
    $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($j))
    $out = & $pwshExe @pwshVor -NoProfile -NonInteractive -File $helper -Once $b 2>$null
    foreach ($l in @($out)) { try { $r = $l | ConvertFrom-Json; if ($null -ne $r.ok) { return $r } } catch {} }
    return $null
}
$r = Once 'app-start' @{ kind = 'store'; aumid = '4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App; calc' }
Check ($r -and -not $r.ok -and $r.error -eq 'Ungültige App-Kennung.') "app-start: falsche AUMID abgelehnt"
$r = Once 'app-start' @{ kind = 'store'; aumid = '4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App' }
Check ($r -and -not $r.ok -and $r.error -eq 'Diese App ist für dieses Windows-Konto nicht installiert.') "app-start: nicht installiert → keine Aktivierung"
$r = Once 'app-start' @{ kind = 'prog'; path = 'C:\Windows\System32\cmd.exe'; args = @('/c', 'calc') }
Check ($r -and -not $r.ok -and $r.error -eq $sh) "app-start: cmd.exe gesperrt"
$r = Once 'app-start' @{ kind = 'prog'; path = 'C:\x\start.bat' }
Check ($r -and -not $r.ok -and $r.error -like 'Nur Programme*') "app-start: .bat gesperrt"
$r = Once 'app-start' @{ kind = 'prog'; path = 'C:\Kodi\kodi.exe'; args = @(1..17 | ForEach-Object { 'a' }) }
Check ($r -and -not $r.ok -and $r.error -eq 'Zu viele Startparameter.') "app-start: zu viele Parameter"
$r = Once 'app-start' @{ kind = 'prog'; path = 'C:\Kodi\kodi.exe'; args = @(5) }
Check ($r -and -not $r.ok -and $r.error -eq 'Ungültiger Startparameter.') "app-start: Parameter, der kein Text ist"
$r = Once 'app-start' @{ kind = 'prog'; path = 'C:\Kodi\kodi.exe' }
Check ($r -and -not $r.ok -and $r.error -eq 'Das Programm wurde nicht gefunden.') "app-start: Programm fehlt"
$r = Once 'app-start' @{ kind = 'shell'; path = 'calc' }
Check ($r -and -not $r.ok -and $r.error -eq 'Unbekannte Art.') "app-start: unbekannte Art"
$r = Once 'prog-check' @{ path = '\\server\share\kodi.exe' }
Check ($r -and $r.ok -and -not $r.result.ok -and $r.result.why -eq 'Nur Programme auf einem Laufwerk dieses PCs.') "prog-check: Freigabe abgelehnt"
$r = Once 'app-logo' @{ aumid = '..\..\x' }
Check ($r -and -not $r.ok -and $r.error -eq 'Ungültige App-Kennung.') "app-logo: falsche AUMID abgelehnt"
$r = Once 'app-logo' @{ aumid = '4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App' }
Check ($r -and $r.ok -and -not $r.result.found) "app-logo: ohne Paket kein Logo"
$r = Once 'app-media' @{ id = 'x; calc' }
Check ($r -and -not $r.ok -and $r.error -eq 'Ungültige Kennung.') "app-media: falsche Kennung abgelehnt"
$r = Once 'app-window' @{ pid = 'abc' }
Check ($r -and $r.ok -and [long]$r.result.hwnd -eq 0) "app-window: keine Zahl → kein Fenster"
$r = Once 'app-window' @{ pid = 'abc'; aumid = 'x;calc' }
Check ($r -and $r.ok -and [long]$r.result.hwnd -eq 0) "app-window: falsche Kennung → kein Fenster"
$r = Once 'app-vollbild' @{ an = $true; hwnd = 0; kind = 'store'; aumid = $nf; taste = 'F11' }
Check ($r -and $r.ok -and -not $r.result.done -and $r.result.why -eq 'kein Fenster') "app-vollbild: ohne Fenster nichts"
$r = Once 'app-vollbild' @{ an = $false; hwnd = 5; kind = 'prog'; path = 'C:\x\a.bat' }
Check ($r -and $r.ok -and -not $r.result.done -and $r.result.why -eq 'Kein gültiger Pfad.') "app-vollbild: falsches Programm nichts"
$r = Once 'app-pad' @{ an = $false }
Check ($r -and $r.ok -and -not $r.result.an) "app-pad: aus geht immer"
$r = Once 'app-text' @{ hwnd = 0; kind = 'store'; aumid = $nf; text = 'hallo' }
Check ($r -and $r.ok -and -not $r.result.done -and $r.result.why -eq 'kein Fenster') "app-text: ohne Fenster nichts"
$r = Once 'app-text' @{ hwnd = 5; kind = 'prog'; path = 'C:\Windows\System32\cmd.exe'; text = 'dir' }
Check ($r -and $r.ok -and -not $r.result.done -and $r.result.why -eq 'Kein gültiger Pfad.') "app-text: Shell nie"
$r = Once 'store-apps' @{}
Check ($r -and $r.ok -and @($r.result.apps).Count -eq 0) "store-apps: ohne Windows leer"
""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
