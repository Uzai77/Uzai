# Probe für Spiel-Profile: UzDisplay (C# 5, Warnungen als Fehler) übersetzen, die Prüfung der
# Argumente der neuen Helfer-Befehle und die Antworten ohne Windows ansehen.
# Aufruf: pwsh tests/spielprofil_cs.ps1 helper/uzai-helper.ps1
$src = Get-Content -Raw $args[0]
$fails = 0
function ok($c, $what) { if ($c) { "  ok   $what" } else { $script:fails++; "  FAIL $what" } }
$m = [regex]::Match($src, "(?s)\`$script:DisplaySrc = @'\r?\n(.*?)\r?\n'@")
$code = $m.Groups[1].Value
"UzDisplay-Block: " + $code.Length + " Zeichen"
try { Add-Type -TypeDefinition $code -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; ok $true "UzDisplay übersetzt (C# 5, Warnungen als Fehler)" } catch { ok $false ("UzDisplay: " + $_.Exception.Message) }
Invoke-Expression ([regex]::Match($src, '(?s)\n(function Get-Num\(.*?\r?\n\})\r?\n').Groups[1].Value)
Invoke-Expression ([regex]::Match($src, '\n(function Test-DisplayDevice\([^\n]*\})\r?\n').Groups[1].Value)
ok ($null -ne (Get-Command Get-Num -ErrorAction SilentlyContinue) -and $null -ne (Get-Command Test-DisplayDevice -ErrorAction SilentlyContinue)) "Prüffunktionen aus dem Helfer geladen"
ok (Test-DisplayDevice '\\.\DISPLAY1') "Gerät \\.\DISPLAY1"
ok (Test-DisplayDevice '\\.\DISPLAY12') "Gerät \\.\DISPLAY12"
ok (-not (Test-DisplayDevice "\\.\DISPLAY1`n")) "Zeilenumbruch hinten abgelehnt"
ok (-not (Test-DisplayDevice '\\.\DISPLAY1; calc')) "Befehl im Gerätenamen abgelehnt"
ok (-not (Test-DisplayDevice 'C:\Windows')) "Pfad abgelehnt"
ok (-not (Test-DisplayDevice '')) "leer abgelehnt"
ok ([UzDisplay]::ValidDevice('\\.\DISPLAY3') -and -not [UzDisplay]::ValidDevice("\\.\DISPLAY3`n") -and -not [UzDisplay]::ValidDevice($null)) "C#: dieselbe Prüfung"
ok ((Get-Num '1920; rm x' 16384) -eq -1 -and (Get-Num 99999 16384) -eq 16384) "Zahlen nur als Zahlen, begrenzt"
$set = [UzDisplay]::SetMode("bad", 1920, 1080, 60, $true) | ConvertFrom-Json
ok ($set.ok -eq $false -and $set.error -eq 'device') "SetMode: falsches Gerät → nichts"
$hdr = [UzDisplay]::SetHdr('\\.\DISPLAY1', 5) | ConvertFrom-Json
ok ($hdr.ok -eq $false -and $hdr.error -eq 'args') "SetHdr: nur 0 oder 1"
$rs = [UzDisplay]::Reset('nope') | ConvertFrom-Json
ok ($rs.ok -eq $false) "Reset: falsches Gerät → nichts"
$audio = [regex]::Match($src, "notmatch '(\^\\\{\[0-9\.\][^']*)'").Groups[1].Value
ok ($audio -ne '') "audio-set prüft die Gerätekennung"
ok ('{0.0.0.00000000}.{a1b2c3d4-0000-1111-2222-333344445555}' -match $audio) "echte Kennung passt"
ok (-not ('{0.0.0.00000000}.{a1b2c3d4-0000-1111-2222-333344445555}" & calc' -match $audio)) "angehängter Befehl passt nicht"
""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
