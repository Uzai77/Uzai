# Prüft das Koppeln von Controllern im Helfer (helper/uzai-helper.ps1, src/core/koppeln.gd, src/ui/layers/pad_pair.gd) unter
# Linux mit PowerShell 7 – ohne Windows, mit nachgebauten Meldungen der Gerätesuche: UzBtSuche übersetzt mit C# 5 ohne
# Warnungen; was der DeviceWatcher meldet (Hinzugekommen, Geändert, Weg) wird gesammelt, nur Controller kommen heraus
# (Klasse, LE-Erscheinungsbild, ohne Klasse nach dem Namen), Namen gesäubert und gekürzt, höchstens 256 Geräte; gekoppelt
# und verbunden kommen mit. Die Suche ist aktiv (IssueInquiry, klassisch und LE), Bt-Pair lehnt falsche Kennungen und ein
# falsches „neu“ ab, bevor Windows etwas sieht, und entkoppelt nur bei neu = 1. Nur am Windows-PC: Windows selbst.
#   pwsh -NoProfile -File tests/koppeln_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$helper = $args[0]
$src = (Get-Content -Raw $helper) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

"C#-Teil"
$cs = [regex]::Match($src, "\`$script:BtSucheSrc = @'\n(?s)(.*?)\n'@").Groups[1].Value
Check ($cs.Length -gt 2000) "UzBtSuche gefunden"
$fake = @'
using System;
using System.Collections.Generic;
public class UzFakePairing { public bool IsPaired; public bool CanPair; public bool IsPairedP { get { return IsPaired; } } }
public class UzFakePaar { public bool IsPaired { get; set; } public bool CanPair { get; set; } }
public class UzFakeInfo {
    public string Id { get; set; }
    public string Name { get; set; }
    public IReadOnlyDictionary<string, object> Properties { get; set; }
    public UzFakePaar Pairing { get; set; }
}
public class UzFakeUpdate { public string Id { get; set; } public IReadOnlyDictionary<string, object> Properties { get; set; } }
'@
try {
    Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Add-Type -TypeDefinition $fake -ErrorAction Stop
    Check $true "übersetzt (C# 5, ohne Warnungen)"
} catch { Check $false ("UzBtSuche: " + $_.Exception.Message); "Ergebnis: $fails Fehler"; exit 1 }
Check (-not $cs.Contains('DllImport') -and -not $cs.Contains('Process') -and -not $cs.Contains('Registry') -and -not $cs.Contains('PairAsync')) "C#: nur lesen – keine Windows-Aufrufe, kein Koppeln"

function Info($id, $name, $props, $paired = $false) {
    $d = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    foreach ($k in $props.Keys) { $d[$k] = $props[$k] }
    $i = New-Object UzFakeInfo
    $i.Id = $id; $i.Name = $name; $i.Properties = $d
    $p = New-Object UzFakePaar; $p.IsPaired = $paired; $p.CanPair = -not $paired; $i.Pairing = $p
    return $i
}
function Upd($id, $props) {
    $d = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    foreach ($k in $props.Keys) { $d[$k] = $props[$k] }
    $u = New-Object UzFakeUpdate; $u.Id = $id; $u.Properties = $d
    return $u
}
$A = 'Bluetooth#Bluetooth00:1a:7d:da:71:13-'
$maj = 'System.Devices.Aep.Bluetooth.Cod.Major'; $min = 'System.Devices.Aep.Bluetooth.Cod.Minor'; $look = 'System.Devices.Aep.Bluetooth.Le.Appearance'
$sig = 'System.Devices.Aep.SignalStrength'; $ver = 'System.Devices.Aep.IsConnected'
[UzBtSuche]::Leeren()
[UzBtSuche]::Neu($null, (Info ($A + '58:10:31:7a:0c:42') 'DualSense Wireless Controller' @{ $maj = [byte]5; $min = [byte]2; $sig = -61 }))
[UzBtSuche]::Neu($null, (Info ('BluetoothLE#BluetoothLE00:1a:7d:da:71:13-c8:3f:26:4b:9e:01') 'Xbox Wireless Controller' @{ $look = [uint16]964; $sig = -50 }))
[UzBtSuche]::Neu($null, (Info ($A + '00:1b:66:aa:10:02') 'Kopfhörer' @{ $maj = [byte]4; $min = [byte]6 }))
[UzBtSuche]::Neu($null, (Info ($A + '98:b6:e9:20:5d:17') "Pro`u{202E} Controller`n" @{}))
[UzBtSuche]::Neu($null, (Info ($A + 'aa:bb:cc:dd:ee:01') 'Gamepad Tastatur' @{}))
[UzBtSuche]::Neu($null, (Info ($A + 'e8:47:3a:01:9c:5d') 'Wireless Controller' @{ $maj = [byte]5; $min = [byte]2; $ver = $false } $true))
[UzBtSuche]::Neu($null, (Info ($A + 'aa:bb:cc:dd:ee:02') '' @{}))
$st = @([UzBtSuche]::Stand(16))
$namen = @($st | ForEach-Object { [string]$_['name'] } | Sort-Object)
Check ($st.Count -eq 4) ("vier Controller unter sieben Geräten: " + ($namen -join ', '))
Check (-not ($namen -contains 'Kopfhörer') -and -not ($namen -contains 'Gamepad Tastatur')) "Kopfhörer (Klasse) und Tastatur (Name) fallen heraus"
$pro = $st | Where-Object { [string]$_['id'] -eq ($A + '98:b6:e9:20:5d:17') }
Check ($null -ne $pro -and [string]$pro['name'] -eq 'Pro Controller') "ohne Klasse nach dem Namen; Richtungs- und Steuerzeichen entfernt"
$alt = $st | Where-Object { [string]$_['id'] -eq ($A + 'e8:47:3a:01:9c:5d') }
Check ($null -ne $alt -and [bool]$alt['paired'] -and -not [bool]$alt['connected']) "gekoppelt, aber nicht verbunden: kommt mit"
# Geändert: Kopfhörer bleibt Kopfhörer; das Gerät ohne Namen bekommt Klasse Gamepad und Namen.
[UzBtSuche]::Neu2($null, (Upd ($A + 'aa:bb:cc:dd:ee:02') @{ $maj = [byte]5; $min = [byte]1; 'System.ItemNameDisplay' = 'Arcade Stick'; $sig = -70 }))
[UzBtSuche]::Neu2($null, (Upd ($A + 'ff:ff:ff:ff:ff:ff') @{ $maj = [byte]5; $min = [byte]2 }))
$st = @([UzBtSuche]::Stand(16))
Check ($st.Count -eq 5 -and @($st | Where-Object { [string]$_['name'] -eq 'Arcade Stick' -and [int]$_['signal'] -eq -70 }).Count -eq 1) "Geändert: Klasse und Name kommen nach (Joystick)"
Check (@($st | Where-Object { [string]$_['id'] -like '*ff:ff:ff:ff:ff:ff' }).Count -eq 0) "Geändert für Unbekanntes: nichts angelegt"
[UzBtSuche]::Weg($null, (Upd ($A + '58:10:31:7a:0c:42') @{}))
[UzBtSuche]::Weg($null, (Upd ($A + 'e8:47:3a:01:9c:5d') @{}))
$st = @([UzBtSuche]::Stand(16))
Check (@($st | Where-Object { [string]$_['name'] -eq 'DualSense Wireless Controller' }).Count -eq 0 -and @($st | Where-Object { [bool]$_['paired'] }).Count -eq 1) "Weg: ungekoppelt fällt heraus, gekoppelt bleibt (als nicht verbunden)"
[UzBtSuche]::Neu($null, (Info ($A + '11:22:33:44:55:66') ('Controller ' + ('x' * 300)) @{ $maj = [byte]5; $min = [byte]2; $sig = 'stark' }))
$lang = @([UzBtSuche]::Stand(16)) | Where-Object { [string]$_['id'] -like '*11:22:33:44:55:66' }
Check ($null -ne $lang -and ([string]$lang['name']).Length -le 80 -and [int]$lang['signal'] -eq -100) "langer Name gekürzt, Signal als Text verworfen"
[UzBtSuche]::Neu($null, (Info ('x' * 200) 'Controller' @{ $maj = [byte]5; $min = [byte]2 }))
Check (-not (@([UzBtSuche]::Stand(64)) | Where-Object { ([string]$_['id']).Length -gt 120 })) "überlange Kennung: nicht angenommen"
[UzBtSuche]::Leeren()
for ($i = 0; $i -lt 300; $i++) { [UzBtSuche]::Neu($null, (Info ($A + ('00:00:00:00:{0:x2}:{1:x2}' -f ($i -shr 8), ($i -band 255))) "Pad $i" @{ $maj = [byte]5; $min = [byte]2 })) }
Check ([UzBtSuche]::Anzahl() -eq 256 -and @([UzBtSuche]::Stand(16)).Count -eq 16) "höchstens 256 Geräte gesammelt, 16 gemeldet"
[UzBtSuche]::Neu($null, $null); [UzBtSuche]::Neu($null, 'kaputt'); [UzBtSuche]::Neu2($null, 42); [UzBtSuche]::Weg($null, $null)
Check $true "kaputte Meldungen: kein Absturz"
foreach ($n in @('DualSense Wireless Controller', 'Xbox Wireless Controller', 'Pro Controller', 'Joy-Con (L)', '8BitDo Pro 2', 'USB Gamepad')) { Check ([UzBtSuche]::NameIstPad($n)) "Name als Controller: $n" }
foreach ($n in @('Bluetooth Keyboard', 'Galaxy Buds', 'Kopfhörer', 'TV Remote Control', '', 'Lautsprecher')) { Check (-not [UzBtSuche]::NameIstPad($n)) "kein Controller: '$n'" }

"Helfer-Befehle"
$fn = ''
foreach ($n in @('Test-BtId', 'Test-BtPadName', 'Get-Num')) { $fn += [regex]::Match($src, "(?s)\n(function $n\(.*?\n\})\n").Groups[1].Value + "`n" }
$fn += [regex]::Match($src, "(?s)\n(function Bt-Pair\(\`$a\) \{.*?\n\})\n").Groups[1].Value + "`n"
$script:BtIdRe = [regex]::Match($src, "(?m)^\`$script:BtIdRe = '([^']*)'").Groups[1].Value
Invoke-Expression $fn
function Test-BtAdmin { return $true }
$good = 'Bluetooth#Bluetooth00:1a:7d:da:71:13-e4:17:d8:2a:00:9b'
Check ((Bt-Pair @{ id = $good; neu = 'x' }).code -eq 'kennung' -and (Bt-Pair @{ id = $good; neu = 2 }).code -eq 'kennung' -and (Bt-Pair @{ id = $good; neu = -1 }).code -eq 'kennung') "neu: nur 0 oder 1"
Check ((Bt-Pair @{ id = ($good + ';x'); neu = 1 }).code -eq 'kennung' -and (Bt-Pair @{ id = @('x') }).code -eq 'kennung') "falsche Kennung: abgelehnt"
Check ((Bt-Pair @{ id = $good; neu = 1 }).code -eq 'admin' -and (Bt-Pair @{ id = $good }).code -eq 'admin') "mit Adminrechten: nichts"
$gleich = $true
foreach ($n in @('DualSense Wireless Controller', 'Bluetooth Keyboard', 'Joy-Con (R)', 'Galaxy Buds', '')) { if ((Test-BtPadName $n) -ne [UzBtSuche]::NameIstPad($n)) { $gleich = $false } }
Check $gleich "Test-BtPadName urteilt wie UzBtSuche.NameIstPad"
$gd = Get-Content -Raw (Join-Path (Split-Path -Parent (Split-Path -Parent (Resolve-Path $helper))) 'src/core/koppeln.gd')
$ja = [regex]::Match($cs, 'new\[\] \{ "controller"[^}]*\}').Value -replace 'new\[\] \{ ', '[' -replace ' \}', ']'
$nie = [regex]::Match($cs, 'new\[\] \{ "keyboard"[^}]*\}').Value -replace 'new\[\] \{ ', '[' -replace ' \}', ']'
Check ($ja.Length -gt 10 -and $gd.Contains('const NAME_JA := ' + $ja) -and $gd.Contains('const NAME_NIE := ' + $nie)) "dieselben Namenswörter in Uzai und im Helfer"
$scan = [regex]::Match($src, "(?s)\nfunction Bt-Scan\(\`$a\) \{.*?\n\}\n").Value
Check ($src.Contains('System.Devices.Aep.Bluetooth.IssueInquiry:=System.StructuredQueryType.Boolean#True') -and $src.Contains('{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}') -and $src.Contains('{bb7bb05e-5972-42b5-94fc-76eaa7084d49}')) "aktive Suche: klassisch mit Abfrage und LE"
Check ($scan.Contains('CreateWatcher(') -and $scan.Contains('$w.Stop()') -and $scan.Contains('remove_Added') -and $scan.Contains('if (Test-BtAdmin)')) "Suche: Beobachter gestartet, wieder gestoppt, nie als Admin"
foreach ($nie2 in @('PairAsync', 'Unpair', 'SetStateAsync', 'Start-Process', 'Invoke-Expression', 'Registry', 'HKLM:', 'HKCU:')) { Check (-not $scan.Contains($nie2)) "Suche ohne $nie2" }
$paar = [regex]::Match($src, "(?s)\nfunction Bt-Pair\(\`$a\) \{.*?\n\}\n").Value
Check ($paar.Contains('PairAsync([Windows.Devices.Enumeration.DevicePairingKinds]::ConfirmOnly)') -and -not $paar.Contains('ProvidePin') -and -not $paar.Contains('DisplayPin')) "Koppeln nur mit Bestätigen (ConfirmOnly)"
Check ($paar.IndexOf('UnpairAsync') -gt $paar.IndexOf("if (`$neu -ne 1) { return @{ code = 'schon'")) "Entkoppeln nur bei neu = 1"

""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
