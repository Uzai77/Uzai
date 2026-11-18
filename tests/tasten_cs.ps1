# Prüft die Eingaben an Fenster im Helfer (helper/uzai-helper.ps1, docs/SECURITY.md „Eingaben an
# Fenster“): die Erlaubnisliste der Tastenkürzel samt böser Kombinationen (Tabelle
# tests/fixtures/tasten_kombis.json, dieselbe prüft tests/logic_tasten.gd für Uzai), Mindestabstand
# und Höchstzahl je Minute, die Pfadprüfung für Discord/Steam/Epic, die geschützten Fenster und die
# Regel für Esc der Controller-Maus (UzGuard, C# 5) – und dass die Befehle ohne Ziel, mit falschem
# Kürzel, fremdem Fenster oder ohne Knopfdruck nichts drücken (require_focus gilt immer). Läuft
# unter Linux (pwsh 7): Alles hier scheitert an einer Prüfung, bevor Windows berührt wird.
#   pwsh -NoProfile -File tests/tasten_cs.ps1 helper/uzai-helper.ps1 tests/fixtures/tasten_kombis.json  → „Ergebnis: alles ok“
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

"Helfer-Quelltext"
$errs = $null; $tok = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$tok, [ref]$errs)
Check ($errs.Count -eq 0) "ohne Parse-Fehler"
$main = [regex]::Match($src, 'Add-Type -TypeDefinition @"(?s)\n(.*?)\n"@').Groups[1].Value
try {
    Add-Type -TypeDefinition $main -CompilerOptions @('-langversion:5') -ErrorAction Stop
    Check $true "Haupt-C# übersetzt mit C# 5"
} catch { Check $false ("Haupt-C#: " + $_.Exception.Message) }
$fn = [regex]::Match($src, '(?s)\n(function Get-Hwnd\(.*?\n\})\n').Groups[1].Value + "`n" +
    [regex]::Match($src, '(?s)\n(function Get-Zahl\(.*?\n\})\n').Groups[1].Value + "`n" +
    [regex]::Match($src, '(?s)\n(function Parse-Keys\(.*?\n\})\n').Groups[1].Value + "`n" +
    [regex]::Match($src, '(?s)\n(function Test-KeyCombo\(.*?)\nfunction Get-SteamDir').Groups[1].Value + "`n" +
    [regex]::Match($src, '(?s)\n(function Get-AppPadCode\(.*?\n\})\n').Groups[1].Value
Check ($fn.Contains('function Test-KeyRate') -and $fn.Contains('function Test-AppPath')) "Prüfungen gefunden"
Invoke-Expression $fn

"Erlaubnisliste"
$cases = (Get-Content -Raw -Encoding UTF8 $args[1] | ConvertFrom-Json).faelle
Check ($cases.Count -ge 50) "Tabelle mit $($cases.Count) Kürzeln"
$want = @{ ok = ''; nein = 'nicht erlaubt'; unbekannt = 'unbekannt' }
$bad = @()
foreach ($c in $cases) {
    $i = 1
    foreach ($mode in 'global', 'fenster', 'dialog', 'app') {
        $got = Test-KeyCombo ([string]$c[0]) $mode
        if ($got -ne $want[[string]$c[$i]]) { $bad += ('„' + ([string]$c[0] -replace "`n", '\n') + '“ ' + $mode + ' → ' + $(if ($got -eq '') { 'ok' } else { $got })) }
        $i++
    }
}
Check ($bad.Count -eq 0) ("alle Kürzel wie erwartet" + $(if ($bad.Count -gt 0) { ': ' + ($bad -join '; ') } else { '' }))
Check ((Test-KeyCombo 'CTRL+SHIFT+F9' 'irgendwas') -eq 'nicht erlaubt') "unbekannte Art: nicht erlaubt"

"Wie oft"
Check (Test-KeyRate 'global') "erster Druck frei"
Check (-not (Test-KeyRate 'global')) "gleich danach nicht (Mindestabstand)"
$script:KeyLog['global'].Clear()
$t = $script:KeyClock.ElapsedMilliseconds
for ($k = 0; $k -lt 12; $k++) { $script:KeyLog['global'].Add($t - 50000 + $k) }
Check (-not (Test-KeyRate 'global')) "nach 12 Drücken in einer Minute nicht mehr"
$script:KeyLog['global'].Clear()
for ($k = 0; $k -lt 12; $k++) { $script:KeyLog['global'].Add($t - 61000) }
Check (Test-KeyRate 'global') "ältere als eine Minute zählen nicht"
Check (-not (Test-KeyRate 'irgendwas')) "unbekannte Art: nie"

"Programm-Pfade"
$la = 'C:\Users\Uz\AppData\Local'
$sd = 'c:/program files (x86)/steam'
Check (Test-AppPath 'discord' 'Discord' 'C:\Users\Uz\AppData\Local\Discord\app-1.0.9188\Discord.exe' $la '') "Discord-App"
Check (Test-AppPath 'discord' 'DiscordPTB' 'C:\Users\Uz\AppData\Local\DiscordPTB\app-1.0.1130\DiscordPTB.exe' $la '') "Discord PTB"
Check (-not (Test-AppPath 'discord' 'Discord' 'C:\Temp\Discord.exe' $la '')) "Discord.exe anderswo: nein"
Check (-not (Test-AppPath 'discord' 'Discord' 'C:\Users\Uz\AppData\Local\Discord\app-1.0\Evil.exe' $la '')) "anderes Programm im Discord-Ordner: nein"
Check (-not (Test-AppPath 'discord' 'Discord' 'C:\Users\Uz\AppData\Local\Discord\app-1.0\..\..\Temp\Discord.exe' $la '')) "Pfad mit ..: nein"
Check (-not (Test-AppPath 'discord' 'Discordx' 'C:\Users\Uz\AppData\Local\Discordx\app-1.0\Discordx.exe' $la '')) "falscher Name: nein"
Check (-not (Test-AppPath 'discord' 'Discord' 'C:\Users\Uz\AppData\Local\Discord\app-1.0\Discord.exe' '' '')) "ohne LOCALAPPDATA: nein"
Check (-not (Test-AppPath 'discord' 'Discord' 'C:\Users\Uz\AppData\Local\Discord\app-1.0\Discord.exe.bak' $la '')) "Endung muss stimmen"
Check (Test-AppPath 'steam' 'steamwebhelper' 'C:\Program Files (x86)\Steam\bin\cef\cef.win7x64\steamwebhelper.exe' '' $sd) "Steam (Webhelper)"
Check (Test-AppPath 'steam' 'steam' 'C:\Program Files (x86)\Steam\steam.exe' '' $sd) "Steam"
Check (-not (Test-AppPath 'steam' 'steam' 'C:\Program Files (x86)\SteamBoese\steam.exe' '' $sd)) "Ordner, der nur so anfängt: nein"
Check (-not (Test-AppPath 'steam' 'steam' 'C:\Program Files (x86)\Steam\steam.exe' '' '')) "ohne Steam-Ordner: nein"
Check (Test-AppPath 'epic' 'EpicGamesLauncher' 'C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe' '' '') "Epic Games Launcher"
Check (Test-AppPath 'epic' 'EpicWebHelper' 'D:\Spiele\Epic Games\Launcher\Engine\Binaries\Win64\EpicWebHelper.exe' '' '') "Epic-Webhelfer"
Check (-not (Test-AppPath 'epic' 'EpicGamesLauncher' 'C:\Temp\EpicGamesLauncher.exe' '' '')) "Epic anderswo: nein"
Check (-not (Test-AppPath 'steam' 'Discord' 'C:\Users\Uz\AppData\Local\Discord\app-1.0\Discord.exe' $la $sd)) "Discord zählt nicht als Steam"
Check (-not (Test-AppPath 'notepad' 'notepad' 'C:\Windows\notepad.exe' $la $sd)) "andere Apps nie"

"Geschützte Fenster und Controller-Maus"
Check ([UzGuard]::SensitiveName('consent') -and [UzGuard]::SensitiveName('Consent.exe') -and [UzGuard]::SensitiveName('CredentialUIBroker') -and
    [UzGuard]::SensitiveName('LogonUI') -and [UzGuard]::SensitiveName('LockApp') -and [UzGuard]::SensitiveName('SecHealthUI') -and
    [UzGuard]::SensitiveName('Microsoft.AAD.BrokerPlugin') -and [UzGuard]::SensitiveName('KeePassXC')) "UAC, Anmeldung, Sperre, Windows-Sicherheit, Konten, Passwortmanager"
Check (-not [UzGuard]::SensitiveName('notepad') -and -not [UzGuard]::SensitiveName('') -and -not [UzGuard]::SensitiveName('consentx')) "andere nicht"
Check ([UzGuard]::SensitiveClass('Credential Dialog Xaml Host') -and -not [UzGuard]::SensitiveClass('Chrome_WidgetWin_1')) "Fensterklasse des Anmeldedialogs"
Check ([UzGuard]::MouseKeyRule(1200, 'Discord', 'Chrome_WidgetWin_1', 1200, 0)) "Esc: Zeiger liegt auf dem Fenster vorn"
Check ([UzGuard]::MouseKeyRule(1200, 'steam', '', 900, 1200)) "Esc: zuletzt angeklickt"
Check (-not [UzGuard]::MouseKeyRule(1200, 'notepad', '', 900, 800)) "Esc: Fenster vorn, das du nicht bedienst: nein"
Check (-not [UzGuard]::MouseKeyRule(1200, 'consent', '', 1200, 1200) -and -not [UzGuard]::MouseKeyRule(1200, 'CredentialUIBroker', '', 1200, 1200)) "Esc: nie an UAC oder Anmeldedialog"
Check (-not [UzGuard]::MouseKeyRule(1200, 'x', 'Credential Dialog Xaml Host', 1200, 1200)) "Esc: nie an die Klasse des Anmeldedialogs"
Check (-not [UzGuard]::MouseKeyRule(4, 'System', '', 4, 4) -and -not [UzGuard]::MouseKeyRule(0, '', '', 0, 0)) "Esc: kein Fenster vorn (sicherer Desktop) oder System: nein"

"Quelltext"
$keys = [regex]::Match($src, "(?s)\n        'keys' \{(.*?)\n        'live-keys' \{").Groups[1].Value
Check ($keys.Contains("Test-KeyCombo ([string]`$a.keys) `$mode") -and $keys.Contains("Test-KeyRate `$mode")) "keys: Erlaubnisliste und Grenze"
Check (-not ($keys -match '\$a\.require_focus') -and $keys.Contains("if (-not `$focused -or `$fg0 -ne `$h)")) "keys: nur, wenn das Ziel vorn ist – require_focus lässt sich nicht abschalten"
Check ($keys.Contains("[UzGuard]::Problem(`$h)") -and $keys.Contains("[UzGuard]::Problem(`$fg0)")) "keys: nie geschützte Fenster (Ziel und Vordergrund)"
Check ($keys.IndexOf('Find-Target') -lt $keys.IndexOf('[UzWin]::Focus') -and $keys.IndexOf("[UzGuard]::Problem(`$h)") -lt $keys.IndexOf('[UzWin]::Focus')) "keys: geschütztes Ziel wird gar nicht erst nach vorn geholt"
$lk = [regex]::Match($src, "(?s)\n        'live-keys' \{(.*?)\n        'discord-front' \{").Groups[1].Value
Check ($lk.Contains("Test-KeyCombo ([string]`$a.keys) 'global'") -and $lk.Contains("Test-KeyRate 'global'")) "live-keys: enges Format und Grenze"
Check ($src.Contains('string block = PressBlock(now, target, fg0, uzaiPid);')) "live-keys: drückt nur ins Ziel, in Uzai oder ins schon vorn liegende Fenster"
$wk = [regex]::Match($src, "(?s)\n        'window-keys' \{(.*?)\n        'window-focus' \{").Groups[1].Value
Check ($wk.Contains("Test-KeyCombo ([string]`$a.keys) 'dialog'") -and $wk.Contains("Test-AppWindow `$hw @('steam', 'epic')")) "window-keys: nur Bedientasten, nur Steam und Epic"
$md = [regex]::Match($src, "(?s)\n        'media' \{(.*?)\n        'media-info'").Groups[1].Value
Check ($md.Contains("if (-not (`$a.user -is [bool] -and `$a.user)) { return @{ sent = `$false; reason = 'kein Ziel' } }") -and
    $md.IndexOf("`$a.user -is [bool]") -lt $md.IndexOf('[UzWin]::Key(')) "media: globale Medientaste nur nach eigenem Knopfdruck"
$db = [regex]::Match($src, "(?s)\n        'discord-buttons' \{(.*?)\n        # --- Installieren").Groups[1].Value
Check ($db.Contains("Test-AppWindow `$hw @(`$app)") -and $db.Contains("Test-AppWindow ([long]`$w.hwnd)") -and $db.Contains('[UzUia]::ElementPid(')) "UIA: nur Discord (bzw. Steam), Fenster und Knopf vor dem Drücken erneut geprüft"
Check ($src.Contains('UzGuard.MouseKeyOk()) { UzWin.Key(0x1B, true)')) "Controller-Maus: Esc nur über UzGuard"

"Controller in einer eigenen App (UzPad.AppStep)"
$okc = @(0x7A, 0x1B, 0x25, 0x26, 0x27, 0x28, 0x0D, 0x20, 0x08, 0x09, (0x10000 -bor 0x09), 0)
Check (@($okc | Where-Object { -not [UzPad]::AppKeyOk($_) }).Count -eq 0) "erlaubt: F11, Esc, Pfeile, Enter, Leertaste, Backspace, Tab, Umschalt+Tab, nichts"
$badc = @(0x5B, 0x12, 0x11, 0x73, 0x2E, 0x41, 0x7B, 0x2C, (0x10000 -bor 0x7A), (0x10000 -bor 0x0D), (0x20000 -bor 0x09), -1, 0x1FFFF)
Check (@($badc | Where-Object { [UzPad]::AppKeyOk($_) }).Count -eq 0) "nie: Windows-Taste, Alt, Strg, F4, Entf, Buchstaben, Druck, Umschalt außer mit Tab, fremde Bits"
Check (-not [UzPad]::AppStart([IntPtr]::Zero, 1234, [int[]]@(0x0D, 0x1B, 0x20, 0x7A, 0x10009, 0x09))) "ohne Fenster: nichts an"
Check (-not [UzPad]::AppStart([IntPtr]12345, 1234, [int[]]@(0x5B, 0, 0, 0, 0, 0)) -and -not [UzPad]::AppOn) "Windows-Taste in der Belegung: nichts an"
Check (-not [UzPad]::AppStart([IntPtr]12345, 1234, [int[]]@(0x0D, 0x1B)) -and -not [UzPad]::AppStart([IntPtr]12345, 4, [int[]]@(0, 0, 0, 0, 0, 0))) "falsche Länge, Systemprozess: nichts an"
Check ((Get-AppPadCode 'F11') -eq 0x7A -and (Get-AppPadCode 'SHIFT+TAB') -eq (0x10000 -bor 0x09) -and (Get-AppPadCode '') -eq 0 -and (Get-AppPadCode 'BACKSPACE') -eq 0x08) "Belegung → Codes (F11, Umschalt+Tab, leer, Backspace)"
Check ($null -eq (Get-AppPadCode 'WIN+R') -and $null -eq (Get-AppPadCode 'ALT+F4') -and $null -eq (Get-AppPadCode 'S') -and $null -eq (Get-AppPadCode 5) -and $null -eq (Get-AppPadCode 'SHIFT+F11')) "Belegung außerhalb der Liste: abgelehnt"
Check ([UzPad]::AppTargetRule(500, 500, 1200, 1200)) "Tasten, wenn genau das App-Fenster vorn ist"
Check (-not [UzPad]::AppTargetRule(501, 500, 1200, 1200) -and -not [UzPad]::AppTargetRule(500, 500, 1300, 1200)) "nicht: anderes Fenster vorn, anderer Prozess (Fensternummer neu vergeben)"
Check (-not [UzPad]::AppTargetRule(0, 0, 0, 0) -and -not [UzPad]::AppTargetRule(500, 500, 4, 4)) "nicht: kein Fenster vorn (sicherer Desktop), System"
$step = [regex]::Match($src, '(?s)static void AppStep\(XState s, int i\) \{(.*?)\n    static void Loop').Groups[1].Value
Check ($step.Contains('bool vorn = AppVorn(h, pid);') -and $step.Contains('|| !vorn) continue;') -and $step.Contains('if (vorn) AppKey(d)')) "Tasten nur, wenn das App-Fenster vorn ist"
Check ($step.Contains('if (!vorn ||') -and $step.Contains('x = Math.Max(r.Left, Math.Min(r.Right - 1, x));')) "Zeiger und Klick nur im App-Fenster"
Check ($src.Contains('else if (appOn && !Mouse && !down) AppStep(s, i);')) "Guide und View + Start bleiben bei Uzai, die Controller-Maus hat Vorrang"
$ap = [regex]::Match($src, "(?s)\n        'app-pad' \{(.*?)\n        'ping' \{").Groups[1].Value
Check ($ap.Contains('Test-ExtAppWindow $a') -and $ap.IndexOf('Test-ExtAppWindow') -lt $ap.IndexOf('AppStart')) "app-pad: erst das Fenster prüfen (Kennung bzw. Pfad, nie geschützt)"
Check ($src.Contains("if (`$t -isnot [string] -or (Test-KeyCombo `$t 'app') -ne '') { return `$null }")) "app-pad: jede Taste aus der Liste für Apps"
$av = [regex]::Match($src, "(?s)\n        'app-vollbild' \{(.*?)\n        'app-text' \{").Groups[1].Value
Check ($av.Contains("Test-KeyCombo `$taste 'app'") -and $av.Contains('[UzWin]::GetForegroundWindow() -eq $h') -and $av.Contains("Test-KeyRate 'fenster'")) "app-vollbild: F11 nur aus der Liste, nur an das Fenster vorn, mit Grenze"
Check ($av.IndexOf('Test-ExtAppWindow') -lt $av.IndexOf('[UzAppRand]::Start(')) "app-vollbild: Rand oben erst nach der Prüfung des Fensters"

"Textfeld in der App: Uzais Tastatur (app-text, UzPad.AppType)"
Check ([UzPad]::AppTextOk('Stranger Things') -and [UzPad]::AppTextOk('Grüße – ½ ü') -and [UzPad]::AppTextOk(('a' * 500)) -and [UzPad]::AppTextOk("x`u{1F600}")) "Text: Buchstaben, Umlaute, Zeichen, Emoji (Ersatzpaar), bis 500"
$badt = @('', ('a' * 501), "a`nb", "a`tb", "a`rb", "`u{0007}", "a`u{007F}", "a`u{0085}", "a`u{202E}txt", "a`u{200B}", "a`u{2066}", "`u{FEFF}a", [string][char]0xD83D, ('a' + [char]0xDE00))
Check (@($badt | Where-Object { [UzPad]::AppTextOk($_) }).Count -eq 0) "Text: kein Zeilenumbruch, Tab, Steuer-, Richtungs- oder unsichtbares Zeichen, kein halbes Ersatzpaar, nicht leer, nicht zu lang"
Check (-not [UzPad]::AppTextOk($null)) "Text: nichts ist kein Text"
Check ([UzPad]::AppFeldEditierbar(50004, $true, $false, $true) -and [UzPad]::AppFeldEditierbar(50004, $false, $false, $true)) "Textfeld: Edit"
Check ([UzPad]::AppFeldEditierbar(50030, $true, $false, $true) -and -not [UzPad]::AppFeldEditierbar(50030, $false, $false, $true)) "Textfeld: Dokument nur mit beschreibbarem Wert (contenteditable)"
Check (-not [UzPad]::AppFeldEditierbar(50004, $true, $true, $true) -and -not [UzPad]::AppFeldEditierbar(50004, $true, $false, $false) -and -not [UzPad]::AppFeldEditierbar(50000, $true, $false, $true)) "kein Textfeld: nur lesbar, gesperrt, Knopf"
Check ([UzPad]::AppFeldMeldung(0, 1, 300) -eq 2 -and [UzPad]::AppFeldMeldung(0, 2, 900) -eq 2) "Textfeld gleich nach A bzw. Klick: Tastatur geht auf"
Check ([UzPad]::AppFeldMeldung(0, 1, 5000) -eq 1 -and [UzPad]::AppFeldMeldung(0, 1, -5) -eq 1) "Textfeld ohne eigenen Druck (Seite setzt den Fokus): nur „Y Tastatur“"
Check ([UzPad]::AppFeldMeldung(1, 1, 100) -eq 0 -and [UzPad]::AppFeldMeldung(1, 0, 100) -eq 0 -and [UzPad]::AppFeldMeldung(0, 0, 100) -eq 0) "kein neues Textfeld: nichts"
Check ($step.Contains('if (k == 3 && feld > 0) { AppMelden("app-tastatur", i); continue; }')) "Y im Textfeld öffnet die Tastatur statt der Taste"
$ty = [regex]::Match($src, '(?s)public static int AppType\(IntPtr h, int pid, string text\) \{(.*?)\n    \}').Groups[1].Value
Check ($ty.Contains('if (!AppTextOk(text)') -and $ty.Contains('if (!AppVorn(h, pid) || UzGuard.Problem(h) != "") break;') -and $ty.Contains('dwFlags = 0x0004u') -and -not $ty.Contains('wVk = (ushort)')) "Tippen: nur geprüfter Text, nur als Zeichen (keine Tasten), vor jedem Zeichen: Fenster vorn, nie geschützt"
$at = [regex]::Match($src, "(?s)\n        'app-text' \{(.*?)\n        'app-pad' \{").Groups[1].Value
Check ($at.IndexOf('Test-ExtAppWindow') -lt $at.IndexOf('AppType($h') -and $at.Contains('[UzPad]::AppTextOk(') -and $at.Contains("Test-KeyRate 'fenster'") -and $at.Contains("[UzGuard]::Problem(`$h) -ne ''") -and $at.IndexOf('Pruefen(') -lt $at.IndexOf('AppType($h')) "app-text: Fenster, Text, Grenze, vorn, nie geschützt, Textfeld – erst dann tippen"

"Befehle (nichts erreicht Windows)"
$jobs = @(
    @{ cmd = 'keys'; args = @{ keys = 'WIN+R'; pid = 4711 }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'keys'; args = @{ keys = 'ALT+F4'; pid = 4711 }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'keys'; args = @{ keys = 'CTRL+ALT+DEL'; global = $true }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'keys'; args = @{ keys = 'WIN+ALT+G'; global = $true; pids = @(4711) }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'keys'; args = @{ keys = 'S'; global = $true; pids = @(4711) }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'keys'; args = @{ keys = 'WIN+ALT+G'; global = 'false' }; key = 'reason'; want = 'nicht vorn' },
    @{ cmd = 'keys'; args = @{ keys = 'CTRL+SHIFT+F9'; global = $true }; key = 'reason'; want = 'nicht vorn' },
    @{ cmd = 'keys'; args = @{ keys = 'F5'; require_focus = $false }; key = 'reason'; want = 'nicht vorn' },
    @{ cmd = 'keys'; args = @{ keys = 'F5'; hwnd = '1;calc'; pid = 'x'; pids = @('2 -Force') }; key = 'reason'; want = 'nicht vorn' },
    @{ cmd = 'keys'; args = @{ keys = 'STRGG+S' }; key = 'reason'; want = 'unbekannt' },
    @{ cmd = 'live-keys'; args = @{ keys = 'WIN+R' }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'live-keys'; args = @{ keys = 'CTRL+ALT+DEL' }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'live-keys'; args = @{ keys = 'ALT+F4' }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'window-keys'; args = @{ hwnd = 123; keys = 'ALT+F4' }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'window-keys'; args = @{ hwnd = 123; keys = 'CTRL+V' }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'window-keys'; args = @{ hwnd = 0; keys = 'TAB' }; key = 'reason'; want = 'nicht erlaubt' },
    @{ cmd = 'window-focus'; args = @{ hwnd = 0 }; key = 'focused'; want = 'False' },
    @{ cmd = 'discord-buttons'; args = @{ hwnd = 0 }; key = 'error'; want = 'nicht erlaubt' },
    @{ cmd = 'discord-buttons'; args = @{ hwnd = 'abc'; app = 'notepad' }; key = 'error'; want = 'nicht erlaubt' },
    @{ cmd = 'discord-invoke'; args = @{ i = 0 }; key = 'result'; want = 'nicht erlaubt' },
    @{ cmd = 'media'; args = @{ action = 'playpause' }; key = 'reason'; want = 'kein Ziel' },
    @{ cmd = 'media'; args = @{ action = 'next'; user = 'true' }; key = 'reason'; want = 'kein Ziel' },
    @{ cmd = 'media'; args = @{ action = 'calc' }; key = 'reason'; want = 'unbekannt' },
    @{ cmd = 'app-pad'; args = @{ an = $true; hwnd = 0; kind = 'store'; aumid = '4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App'; tasten = @{ a = 'ENTER' } }; key = 'why'; want = 'kein Fenster' },
    @{ cmd = 'app-pad'; args = @{ an = $true; hwnd = 77; kind = 'store'; aumid = 'x;calc' }; key = 'why'; want = 'Ungültige App-Kennung.' },
    @{ cmd = 'app-pad'; args = @{ an = $true; hwnd = 77; kind = 'prog'; path = 'C:\Windows\System32\cmd.exe' }; key = 'why'; want = 'Kein gültiger Pfad.' },
    @{ cmd = 'app-pad'; args = @{ an = $true; hwnd = 77; kind = 'shell' }; key = 'why'; want = 'Unbekannte Art.' },
    @{ cmd = 'app-pad'; args = @{ an = 'true'; hwnd = 77 }; key = 'an'; want = 'False' },
    @{ cmd = 'app-vollbild'; args = @{ an = $true; hwnd = '1;calc'; kind = 'prog'; path = 'C:\Kodi\kodi.exe'; taste = 'WIN+R' }; key = 'why'; want = 'kein Fenster' },
    @{ cmd = 'app-vollbild'; args = @{ an = $true; hwnd = 77; kind = 'store'; aumid = 'N*_mcm4njqhnhss8!App' }; key = 'why'; want = 'Ungültige App-Kennung.' }
)
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = (Get-Process -Id $PID).Path
# pwsh als .NET-Werkzeug läuft als „dotnet pwsh.dll“: dann die DLL zuerst.
if ([IO.Path]::GetFileNameWithoutExtension($psi.FileName) -eq 'dotnet') { $psi.ArgumentList.Add([Environment]::GetCommandLineArgs()[0]) }
foreach ($x in @('-NoProfile', '-NonInteractive', '-File', (Resolve-Path $args[0]).Path)) { $psi.ArgumentList.Add($x) }
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
$errTask = $p.StandardError.ReadToEndAsync()
$n = 1
foreach ($j in $jobs) { $p.StandardInput.WriteLine((@{ id = $n; cmd = $j.cmd; args = $j.args } | ConvertTo-Json -Compress -Depth 5)); $n++ }
$p.StandardInput.Close()
$out = $p.StandardOutput.ReadToEnd()
[void]$p.WaitForExit(120000)
$replies = @{}
foreach ($line in ($out -split "`n")) {
    $l = $line.Trim()
    if (-not $l.StartsWith('{')) { continue }
    try { $r = $l | ConvertFrom-Json } catch { continue }
    $replies[[int]$r.id] = $r
}
$n = 1
foreach ($j in $jobs) {
    $r = $replies[$n]
    $got = ''
    if ($null -eq $r) { $got = '(keine Antwort)' }
    elseif (-not $r.ok) { $got = 'Fehler: ' + $r.error }
    else { $got = [string]$r.result.($j.key) }
    $sent = $null -ne $r -and $r.ok -and $r.result.sent -eq $true
    Check ($got -eq $j.want -and -not $sent) ("{0} {1} → {2}" -f $j.cmd, (($j.args | ConvertTo-Json -Compress) -replace '^(.{70}).*$', '$1…'), $got)
    $n++
}
""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
