# Prüft die C#-Teile für Remote Play Together aus helper/uzai-helper.ps1: Starter und Einladung
# müssen als C# 5 übersetzbar sein (Windows PowerShell 5 baut mit dem alten Compiler), ohne
# Warnungen, und die reinen Funktionen müssen stimmen. Läuft auch unter Linux (pwsh 7);
# Starten und Einladen selbst geht nur unter Windows mit Steam.
#   pwsh -NoProfile -File tests/remoteplay_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = Get-Content -Raw $args[0]
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}
$starter = [regex]::Match($src, "\`$script:StarterSrc = @'\r?\n(?s)(.*?)\r?\n'@").Groups[1].Value
$rp = [regex]::Match($src, "\`$script:RemotePlaySrc = @'\r?\n(?s)(.*?)\r?\n'@").Groups[1].Value
Check ($starter.Length -gt 1000) "Starter-Quelltext gefunden"
Check ($rp.Length -gt 1000) "Einladungs-Quelltext gefunden"
$opts = @('-langversion:5', '-warnaserror')
# Starter als Datei bauen (wie auf dem PC, dort als WindowsApplication), dann laden.
$tmpDll = Join-Path ([IO.Path]::GetTempPath()) ("uzai-starter-probe-" + [Guid]::NewGuid().ToString('N') + ".dll")
try {
    Add-Type -TypeDefinition $starter -CompilerOptions $opts -OutputAssembly $tmpDll -OutputType Library -ErrorAction Stop
    Check $true "Starter übersetzt (C# 5, ohne Warnungen)"
    $bytes = [IO.File]::ReadAllBytes($tmpDll)
    Check ([Text.Encoding]::ASCII.GetString($bytes).Contains('UzaiStarter') -and $bytes.Length -lt 4MB) "übersetzte Datei trägt die Kennung UzaiStarter (Uzai erkennt alte Starter daran)"
    Add-Type -Path $tmpDll
} catch { Check $false ("Starter übersetzt: " + $_.Exception.Message) }
finally { if (Test-Path $tmpDll) { Remove-Item $tmpDll -Force } }
try { Add-Type -TypeDefinition $rp -CompilerOptions $opts -ErrorAction Stop; Check $true "Einladung übersetzt (C# 5, ohne Warnungen)" }
catch { Check $false ("Einladung übersetzt: " + $_.Exception.Message) }
if ($fails -gt 0) { "Ergebnis: $fails Fehler"; exit 1 }

"Starter"
$main = [UzaiStarter].GetMethod('Main')
Check ($main -ne $null -and $main.IsStatic) "hat Main als Einstieg"
$env = New-Object 'System.Collections.Generic.List[string]'
$kv = [UzaiStarter]::ParseKv("# Kopf`r`nid=ab12`r`nzeit=1700000000`r`nexe=D:\Emus\PCSX2\pcsx2-qt.exe`r`nargs=-fullscreen -- `"D:\ROMs\FIFA Street 2.iso`"`r`nenv=PCSX2_X=1=2`r`nenv=FOO=bar`r`nkaputt`r`n", $env)
Check ([UzaiStarter]::Get($kv, 'exe') -eq 'D:\Emus\PCSX2\pcsx2-qt.exe') "Auftrag: exe"
Check ([UzaiStarter]::Get($kv, 'args') -eq '-fullscreen -- "D:\ROMs\FIFA Street 2.iso"') "Auftrag: Parameter mit Anführungszeichen und Gleichheitszeichen bleiben"
Check ($env.Count -eq 2 -and $env[0] -eq 'PCSX2_X=1=2') "Auftrag: Umgebungsvariablen (mehrfach)"
Check ([UzaiStarter]::Get($kv, 'fehlt') -eq '') "Auftrag: fehlender Schlüssel ist leer"
$bom = [UzaiStarter]::ParseKv([string][char]0xFEFF + "id=x`n", $null)
Check ([UzaiStarter]::Get($bom, 'id') -eq 'x') "Auftrag: BOM am Anfang stört nicht"
Check ([UzaiStarter]::IsFresh('1000', 1100)) "frischer Auftrag"
Check (-not [UzaiStarter]::IsFresh('1000', 1000 + 301)) "alter Auftrag startet das Original"
Check (-not [UzaiStarter]::IsFresh('', 1000)) "Auftrag ohne Zeit gilt nicht"
Check (-not [UzaiStarter]::IsFresh('2000', 1000)) "Auftrag aus der Zukunft gilt nicht"
$orig = [UzaiStarter]::OriginalPath([IO.Path]::Combine('steam', 'RetroArch', 'retroarch.exe'))
Check ($orig -eq [IO.Path]::Combine('steam', 'RetroArch', 'retroarch.uzai-original.exe')) "Sicherung heißt *.uzai-original.exe"
Check ([UzaiStarter]::ArgsAfterExe('"C:\Steam\RetroArch\retroarch.exe" -L core.dll "rom 1.iso"') -eq '-L core.dll "rom 1.iso"') "Steam-Parameter nach Programm in Anführungszeichen"
Check ([UzaiStarter]::ArgsAfterExe('C:\x\retroarch.exe --menu') -eq '--menu') "Steam-Parameter ohne Anführungszeichen"
Check ([UzaiStarter]::ArgsAfterExe('"C:\x\retroarch.exe"') -eq '') "ohne Parameter"
Check ([UzaiStarter]::Version -eq '3') "Starter-Version 3 (meldet Controller und Adminfehler, Konsolenprogramme ohne Fenster)"
$tmpExe = [IO.Path]::GetTempFileName()
$pe = New-Object byte[] 0x200
$pe[0] = 0x4D; $pe[1] = 0x5A; $pe[0x3C] = 0x80; $pe[0x80] = 0x50; $pe[0x81] = 0x45; $pe[0x80 + 0x5C] = 3
[IO.File]::WriteAllBytes($tmpExe, $pe)
$q3 = [UzaiStarter]::Quiet($tmpExe)
$pe[0x80 + 0x5C] = 2; [IO.File]::WriteAllBytes($tmpExe, $pe)
$q2 = [UzaiStarter]::Quiet($tmpExe)
Remove-Item $tmpExe -Force
Check ($q3 -and -not $q2) "Konsolenprogramm (PE-Subsystem 3) startet ohne Fenster, Fensterprogramm normal"
Check ([UzaiStarter]::Quiet('C:\Spiele\start.BAT') -and [UzaiStarter]::Quiet('x.cmd') -and -not [UzaiStarter]::Quiet('/fehlt/spiel.exe')) "Batchdateien ohne Fenster, fehlende Datei normal"
Check ([UzaiStarter]::StartError(740, 'x') -eq 'admin:x') "Fehler 740 (Adminrechte nötig) wird als admin: gemeldet"
Check ([UzaiStarter]::StartError(2, 'x') -eq 'x') "andere Startfehler bleiben, wie sie sind"
Check ($starter.Contains('"\r\npads=" + pads')) "Status enthält die Zahl der Controller"

"Einladung: Wahl der Schnittstelle"
$known = [UzRemotePlay]::Known()
$plan = [UzRemotePlay]::Plan($known)
Check ($plan[0] -eq 'flat:SteamAPI_SteamRemotePlay_v004') "neue Bibliothek: flache Schnittstelle v004 zuerst"
Check ($plan.Count -eq 8 -and $plan[4] -eq 'vtable:STEAMREMOTEPLAY_INTERFACE_VERSION004:12') "danach Methodentabelle, neueste Version zuerst"
$p158 = [UzRemotePlay]::Plan(@('SteamAPI_ISteamRemotePlay_BSendRemotePlayTogetherInvite', 'SteamAPI_SteamRemotePlay_v002', 'SteamInternal_FindOrCreateUserInterface', 'SteamAPI_GetHSteamUser'))
Check ($p158[0] -eq 'flat:SteamAPI_SteamRemotePlay_v002' -and $p158.Count -eq 5) "SDK 1.58: v002 flach, dann Methodentabelle"
$p147 = [UzRemotePlay]::Plan(@('SteamAPI_ISteamRemotePlay_BSendRemotePlayTogetherInvite', 'SteamInternal_FindOrCreateUserInterface', 'SteamAPI_GetHSteamUser'))
Check ($p147.Count -eq 4 -and $p147[0].StartsWith('vtable:') -and $p147[3] -eq 'vtable:STEAMREMOTEPLAY_INTERFACE_VERSION001:6') "SDK 1.47 (alte flache Schnittstelle ohne Zugriff): nur Methodentabelle, 001 an Platz 6"
$pOld = [UzRemotePlay]::Plan(@('SteamAPI_Init', 'SteamFriends'))
Check ($pOld.Count -eq 0) "uralte Bibliothek: kein Versuch (ehrlicher Hinweis)"
$pNoSend = [UzRemotePlay]::Plan(@('SteamAPI_SteamRemotePlay_v001', 'SteamAPI_GetHSteamUser'))
Check ($pNoSend.Count -eq 0) "Zugriff ohne Senden-Funktion und ohne Anforderung: kein Versuch"
Check (([UzRemotePlay]::Slots -join ',') -eq '12,7,7,6') "Plätze in der Methodentabelle laut Steamworks-Headern"

"Einladung: mehrere auf einmal (Discord-Call)"
$fr = [UzRemotePlay]::ParseFriends('76561190000000001, 76561190000000002,kaputt,76561190000000001,12')
Check ($fr.Count -eq 2 -and $fr[1] -eq [UInt64]76561190000000002) "Steam-IDs aus der Liste, doppelte und kaputte fallen weg"
Check ([UzRemotePlay]::ParseFriends('').Count -eq 0) "leere Liste"
$pend = [UzRemotePlay]::Pending($fr, [UInt64[]]@(76561190000000001))
Check ($pend.Count -eq 1 -and $pend[0] -eq [UInt64]76561190000000002) "wer schon in der Sitzung ist, wird nicht eingeladen"
$mj = [UzRemotePlay]::ManyJson($true, 'flat:x', '', [UInt64[]]@(76561190000000001), $fr, [bool[]]@($false, $true), [string[]]@('joined', $null)) | ConvertFrom-Json
Check ($mj.ok -and $mj.joined[0] -eq '76561190000000001' -and $mj.results.Count -eq 2) "Antwort: Sitzung und je Freund ein Ergebnis"
Check ($mj.results[0].skipped -eq 'joined' -and -not $mj.results[0].ok -and $mj.results[0].reason -eq '') "schon dabei: übersprungen, kein Fehler"
Check ($mj.results[1].ok -and $mj.results[1].friend -eq '76561190000000002') "eingeladen"
$bad = [UzRemotePlay]::ManyJson($false, '', 'Steam "weg"', [UInt64[]]@(), $fr, $null, $null) | ConvertFrom-Json
Check (-not $bad.ok -and $bad.reason -eq "Steam 'weg'" -and $bad.results[0].reason -ne '') "Fehler: Grund lesbar, jeder Freund nicht eingeladen"
Check (([UzRemotePlay]::Known() -join ',').Contains('SteamAPI_ISteamRemotePlay_GetSessionSteamID')) "fragt die Sitzung über die flache Schnittstelle ab"
Check ($src.Contains("[UzRemotePlay]::InviteMany([string]`$a.dll, [string]`$a.friends)")) "Helfer: friends geht an InviteMany"
""
if ($fails -eq 0) { "Ergebnis: alles ok" } else { "Ergebnis: $fails Fehler"; exit 1 }
