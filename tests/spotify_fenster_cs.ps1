# Prüft das Lesen des Spotify-Fensters über die Bedienhilfe von Windows (UzSpotRegeln, UzSpot.UzSpotUi
# und die Befehle „spotify-fenster“, „spotify-fenster-spielen“ in helper/uzai-helper.ps1): alle
# Teile als C# 5 übersetzbar (UI Automation unter Linux über einen kleinen Nachbau mit Beispielbaum
# und einer virtuellen Liste, die wie Spotifys Bibliothek nur die sichtbaren Zeilen zeigt), Texte
# geprüft und gekürzt, nur Abspiel-Knöpfe und Zeilen mit Spotify-Adresse in den Abschnitten
# Bibliothek, „Zuletzt gespielt“ und Suche, vollständiges Durchblättern über das Bildlauf-Muster
# (alte Stelle danach wieder), Grenzen für Knoten, Tiefe und Einträge, Aufrufen nur mit gleichem
# Namen und Prozess, Fenster nur von der Spotify-App (Pfad), keine Tasten, Klicks, Fokuswechsel
# oder Debug-Ports; Bereitlegen zum Lesen nur, wenn Uzai vorn liegt, Zurücklegen immer. Läuft unter Linux (pwsh 7).
#   pwsh -NoProfile -File tests/spotify_fenster_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

"Quelltext"
$regeln = [regex]::Match($src, "(?s)\n\`$script:SpotRegelnSrc = @'\n(.*?)\n'@").Groups[1].Value
$ui = [regex]::Match($src, "(?s)\n\`$script:SpotUiSrc = @'\n(.*?)\n'@").Groups[1].Value
Check ($regeln.Length -gt 2000 -and $ui.Length -gt 2000) "Regeln und Lesen gefunden"
$cmdRead = [regex]::Match($src, "(?s)\n        'spotify-fenster' \{(.*?)\n        'spotify-fenster-spielen' \{").Groups[1].Value
$cmdPlay = [regex]::Match($src, "(?s)\n        'spotify-fenster-spielen' \{(.*?)\n        'spotify-start' \{").Groups[1].Value
$find = [regex]::Match($src, "(?s)\n(function Find-SpotifyWindow \{.*?\n\})\n").Groups[1].Value
Check ($cmdRead.Length -gt 200 -and $cmdPlay.Length -gt 200 -and $find.Length -gt 100) "Befehle und Fenstersuche gefunden"
$all = $regeln + $ui + $cmdRead + $cmdPlay + $find
foreach ($bad in @('SendInput', 'keybd_event', 'mouse_event', 'SetForegroundWindow', 'SetCursorPos', 'remote-debugging', 'LoadLibrary', 'ReadProcessMemory', 'WriteProcessMemory', 'UzInput]::Key', 'UzInput]::Mouse', 'Focus(', 'Local\Spotify', 'prefs')) {
    Check (-not $all.Contains($bad)) "nichts mit $bad"
}
Check ($find.Contains("Test-AppWindow ([long]`$best) @('spotify')") -and $find.Contains("IsIconic(`$best)")) "Fenster nur der Spotify-App, minimiert wird gemeldet"
Check ($cmdRead.Contains('Find-SpotifyWindow') -and $cmdRead.Contains("Get-Zahl `$a.budget_ms 500 ([UzSpotRegeln]::BudgetHard)") -and $cmdRead.Contains('Get-Zahl $a.pause_ms 20 1000')) "Lesen: Fenster geprüft, Zeit begrenzt"
Check ($cmdRead.Contains('$voll -and $fgPid -eq [int]$f.pid) { $voll = $false') -and $cmdRead.Contains('$fgPid -eq $upid) { $legen = $true }')) "Blättern nie, wenn Spotify vorn ist; Bereitlegen nur, wenn Uzai vorn ist"
Check ($cmdRead.Contains("} finally {`n                if (`$legen) { [void][UzSpot.UzSpotFenster]::Zurueck(`$h) }") -and $cmdRead.Contains('$rest = [UzSpot.UzSpotFenster]::Zurueck($h)')) "Zurücklegen immer (auch Reste eines abgebrochenen Lesens)"
$fen = [regex]::Match($ui, "(?s)public static class UzSpotFenster \{(.*)").Groups[1].Value
Check ($fen.Contains('SW_SHOWNOACTIVATE') -and $fen.Contains('SWP_NOACTIVATE') -and $fen.Contains('EX_TRANSPARENT') -and $fen.Contains('SetLayeredWindowAttributes(h, 0, 1, 2)')) "Fenster zum Lesen: ohne Aktivierung, klickdurchlässig, fast durchsichtig"
Check (-not $fen.Contains('SW_SHOWNORMAL') -and -not $fen.Contains('SW_RESTORE') -and -not $fen.Contains('BringWindowToTop') -and -not $fen.Contains('SetActiveWindow') -and -not $fen.Contains('SetFocus')) "nie aktivieren oder nach vorn holen"
Check ($cmdPlay.Contains('ShowWindow($fg1, 6)') -and $cmdPlay.Contains('zurueck')) "Spielen: springt Spotify nach vorn, wird es minimiert (ohne Alt-Notlösung)"
Check ($cmdPlay.Contains("Test-AppWindow ([long]`$w.hwnd) @('spotify')") -and $cmdPlay.Contains('[int]$chk.pid -ne [int]$w.pid') -and $cmdPlay.Contains('[UzSpotRegeln]::NameMax')) "Spielen: Fenster und Prozess erneut geprüft, Name begrenzt"

# Nachbau von System.Windows.Automation (nur was UzSpotUi braucht) mit einem Baum zum Durchgehen.
$stub = @'
namespace System.Windows.Automation {
    using System;
    using System.Collections.Generic;
    public class AutomationPattern { }
    public class ControlType {
        public string N;
        ControlType(string n) { N = n; }
        public static readonly ControlType Button = new ControlType("Button"), ListItem = new ControlType("ListItem"), DataItem = new ControlType("DataItem"),
            TreeItem = new ControlType("TreeItem"), Group = new ControlType("Group"), Custom = new ControlType("Custom"), Text = new ControlType("Text"),
            Hyperlink = new ControlType("Hyperlink"), Pane = new ControlType("Pane"), List = new ControlType("List"), DataGrid = new ControlType("DataGrid"),
            Table = new ControlType("Table"), Tree = new ControlType("Tree");
    }
    public class AutomationProperty { }
    public class AutomationElement {
        public string Nm = "";
        public string Aid = "";
        public string Val = "";
        public ControlType Ty;
        public List<AutomationElement> All;    // virtuelle Liste: alle Zeilen, gezeigt werden Show ab Pos
        public double Pos;
        public int Show = 12;
        public int Scrolls;
        public static readonly AutomationProperty IsScrollPatternAvailableProperty = new AutomationProperty();
        public object GetCurrentPropertyValue(AutomationProperty p) { return All != null; }
        public List<AutomationElement> View() {
            if (All == null) return Kids;
            int n = All.Count - Show;
            int s = n <= 0 ? 0 : (int)Math.Round(Pos / 100.0 * n);
            return All.GetRange(s, Math.Min(Show, All.Count - s));
        }
        public int Pid = 4711;
        public bool CanInvoke = true;
        public int Invoked;
        public AutomationElement Up;
        public List<AutomationElement> Kids = new List<AutomationElement>();
        public static AutomationElement Root;
        public static AutomationElement FromHandle(IntPtr h) { return Root; }
        public struct AutomationElementInformation {
            internal AutomationElement E;
            public string Name { get { return E.Nm; } }
            public ControlType ControlType { get { return E.Ty; } }
            public int ProcessId { get { return E.Pid; } }
            public string AutomationId { get { return E.Aid; } }
        }
        public AutomationElementInformation Current { get { var i = new AutomationElementInformation(); i.E = this; return i; } }
        public bool TryGetCurrentPattern(AutomationPattern p, out object o) {
            o = null;
            if (p == InvokePattern.Pattern) { if (CanInvoke) o = new InvokePattern(this); }
            else if (p == ScrollPattern.Pattern) { if (All != null) o = new ScrollPattern(this); }
            else if (p == ValuePattern.Pattern) { if (Val != "") o = new ValuePattern(this); }
            return o != null;
        }
        public AutomationElement Add(string n, ControlType t) { var c = new AutomationElement(); c.Nm = n; c.Ty = t; c.Up = this; c.Pid = Pid; Kids.Add(c); return c; }
        public AutomationElement Virt(string n, ControlType t) { var c = new AutomationElement(); c.Nm = n; c.Ty = t; c.Up = this; c.Pid = Pid; if (All == null) All = new List<AutomationElement>(); All.Add(c); return c; }
    }
    public class InvokePattern {
        public static readonly AutomationPattern Pattern = new AutomationPattern();
        AutomationElement e;
        public InvokePattern(AutomationElement x) { e = x; }
        public void Invoke() { e.Invoked++; }
    }
    public class ScrollPattern {
        public static readonly AutomationPattern Pattern = new AutomationPattern();
        public const double NoScroll = -1;
        AutomationElement e;
        public ScrollPattern(AutomationElement x) { e = x; }
        public struct ScrollPatternInformation {
            internal AutomationElement E;
            public bool VerticallyScrollable { get { return E.All.Count > E.Show; } }
            public double VerticalScrollPercent { get { return E.Pos; } }
            public double VerticalViewSize { get { return 100.0 * E.Show / E.All.Count; } }
        }
        public ScrollPatternInformation Current { get { var i = new ScrollPatternInformation(); i.E = e; return i; } }
        public void SetScrollPercent(double h, double v) { if (v >= 0) { e.Pos = v > 100 ? 100 : v; e.Scrolls++; } }
    }
    public class ValuePattern {
        public static readonly AutomationPattern Pattern = new AutomationPattern();
        AutomationElement e;
        public ValuePattern(AutomationElement x) { e = x; }
        public struct ValuePatternInformation { internal AutomationElement E; public string Value { get { return E.Val; } } }
        public ValuePatternInformation Current { get { var i = new ValuePatternInformation(); i.E = e; return i; } }
    }
    public class TreeWalker {
        public static readonly TreeWalker ControlViewWalker = new TreeWalker();
        public AutomationElement GetFirstChild(AutomationElement e) { var k = e.View(); return k.Count > 0 ? k[0] : null; }
        public AutomationElement GetNextSibling(AutomationElement e) {
            if (e.Up == null) return null;
            var k = e.Up.View();
            int i = k.IndexOf(e);
            return i >= 0 && i + 1 < k.Count ? k[i + 1] : null;
        }
    }
}
'@
try {
    Add-Type -TypeDefinition ($regeln + "`n" + $ui + "`n" + $stub) -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "Regeln und Lesen übersetzt (C# 5, ohne Warnungen, gegen den Nachbau)"
} catch {
    Check $false ("Übersetzen: " + $_.Exception.Message)
    try { Add-Type -TypeDefinition $regeln -CompilerOptions @('-langversion:5') -ErrorAction Stop } catch {}
}
Check ($null -ne ('UzSpotRegeln' -as [type]) -and $null -ne ('UzSpot.UzSpotUi' -as [type])) "Klassen da"

"Regeln"
Check ([UzSpotRegeln]::Clean("Mix`u{0001} der`u{202E} Woche`u{200B}", 120) -eq 'Mix der Woche') "Steuer- und Richtungszeichen weg"
Check ([UzSpotRegeln]::Clean(('x' * 5000), 120).Length -eq 120 -and [UzSpotRegeln]::Clean($null, 10) -eq '') "gekürzt, leer bleibt leer"
Check ([UzSpotRegeln]::Clean("a`n`n  b", 50) -eq 'a b') "Leerraum zusammengezogen"
Check ([UzSpotRegeln]::Section('Deine Bibliothek') -eq 'lib' -and [UzSpotRegeln]::Section('Your Library') -eq 'lib') "Bibliothek erkannt"
Check ([UzSpotRegeln]::Section('Zuletzt gespielt') -eq 'recent' -and [UzSpotRegeln]::Section('Recently played') -eq 'recent') "Zuletzt gespielt erkannt"
Check ([UzSpotRegeln]::Section('Top-Ergebnis') -eq 'search' -and [UzSpotRegeln]::Section('Mix der Woche') -eq '') "Suche erkannt, sonst nichts"
Check ([UzSpotRegeln]::PlayTarget('Dein Mix der Woche abspielen') -eq 'Dein Mix der Woche' -and [UzSpotRegeln]::PlayTarget('Play Discover Weekly') -eq 'Discover Weekly') "Abspiel-Knopf: Name dahinter"
Check ([UzSpotRegeln]::PlayTarget('Abspielen') -eq '' -and [UzSpotRegeln]::PlayTarget('Play') -eq '' -and [UzSpotRegeln]::PlayTarget('Pause Discover Weekly') -eq '') "Wiedergabeleiste und Pause: nein"
Check ([UzSpotRegeln]::PlayTarget(('Play ' + ('y' * 900))).Length -le [UzSpotRegeln]::NameMax) "langer Name gekürzt"
Check ([UzSpotRegeln]::Kind('Lieblingssongs Playlist • 512 Titel') -eq 'playlist' -and [UzSpotRegeln]::Kind('Final Fantasy X Album • Nobuo Uematsu') -eq 'album' -and [UzSpotRegeln]::Kind('Koji Kondo Künstler') -eq 'artist') "Art aus der Zeile"
Check ([UzSpotRegeln]::Sub('Final Fantasy X Album • Nobuo Uematsu', 'Final Fantasy X') -eq 'Album • Nobuo Uematsu') "Unterzeile ohne den Namen"
Check ([UzSpotRegeln]::Clamp(99999, 200, 20000) -eq 20000 -and [UzSpotRegeln]::Clamp(-5, 500, 8000) -eq 500) "Grenzen"
$PLU = 'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'
Check ([UzSpotRegeln]::UriAusId('listrow-title-' + $PLU) -eq $PLU -and [UzSpotRegeln]::UriAusId('card-title-spotify:album:6dVIqQ8qmQ5GBnJ9shOYGE-3') -eq 'spotify:album:6dVIqQ8qmQ5GBnJ9shOYGE') "Adresse aus der Kennung"
Check ([UzSpotRegeln]::UriAusId('listrow-title-spotify:user:robin.k:collection') -eq 'spotify:user:robin.k:collection') "Lieblingssongs"
Check ([UzSpotRegeln]::UriAusId('x-spotify:playlist:37i9dQZF1DXcBWIGoYBM5Mx') -eq '' -and [UzSpotRegeln]::UriAusId('spotify:track:4uLU6hMCjMI75M1A2tKUQC') -eq '' -and [UzSpotRegeln]::UriAusId('spotify:user:a b:collection') -eq '') "zu lang, Titel, Leerzeichen: nein"
Check ([UzSpotRegeln]::UriAusId(('a' * 400) + $PLU) -eq '' -and [UzSpotRegeln]::UriAusId($null) -eq '') "zu lange Kennung: nein"
Check ([UzSpotRegeln]::UriAusLink('https://xpui.app.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M') -eq $PLU -and [UzSpotRegeln]::UriAusLink('https://open.spotify.com/artist/0OdUWJ0sBjDrqHygGUXeCF?si=1') -eq 'spotify:artist:0OdUWJ0sBjDrqHygGUXeCF') "Adresse aus einem Link"
Check ([UzSpotRegeln]::UriAusLink('http://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M') -eq '' -and [UzSpotRegeln]::UriAusLink('https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC') -eq '' -and [UzSpotRegeln]::UriAusLink('https://a/b/playlist/37i9dQZF1DXcBWIGoYBM5M') -eq '') "ohne https, Titel, tiefer Pfad: nein"
Check ([UzSpotRegeln]::UriKind($PLU) -eq 'playlist' -and [UzSpotRegeln]::UriKind('spotify:user:x:collection') -eq 'playlist' -and [UzSpotRegeln]::UriKind('spotify:artist:0OdUWJ0sBjDrqHygGUXeCF') -eq 'artist') "Art aus der Adresse"
Check (([UzSpotRegeln]::ItemJson(1, 'lib', 'a', '', 'playlist', 'spotify:evil:"x') | ConvertFrom-Json).uri -eq '' -and ([UzSpotRegeln]::ItemJson(1, 'lib', 'a', '', 'playlist', $PLU) | ConvertFrom-Json).uri -eq $PLU) "nur geprüfte Adressen im JSON"
Check ([UzSpotRegeln]::Weiter(0, 10) -eq 8 -and [UzSpotRegeln]::Weiter(95, 10) -eq 100 -and [UzSpotRegeln]::Weiter(0, 0.5) -eq 2 -and [UzSpotRegeln]::Weiter([double]::NaN, [double]::NaN) -eq 10) "Blättern: knapp eine Seite, nie über 100"
$sr = [UzSpotRegeln]::Streifen(0, 0, 1920, 1080, 800, 0, 0)
Check ($sr[0] -eq 1918 -and $sr[1] -eq 0 -and $sr[2] -eq 2918 -and $sr[3] -eq 1080) "Lesestreifen: 2 Punkte am rechten Rand, Bildschirmhöhe, mindestens 1000 breit"
$sr2 = [UzSpotRegeln]::Streifen(-1920, 0, 0, 1080, 3000, 0, 40)
Check ($sr2[0] -eq -2 -and $sr2[1] -eq -40 -and ($sr2[2] - $sr2[0]) -eq 1920 -and [UzSpotRegeln]::Streifen(0, 0, 100, 100, 800, 0, 0).Length -eq 0) "Bildschirm links, Arbeitsbereich verschoben, zu kleiner Bildschirm: nichts"

"Beispielbaum"
$AE = [System.Windows.Automation.AutomationElement]
$CT = [System.Windows.Automation.ControlType]
$root = New-Object System.Windows.Automation.AutomationElement
$root.Nm = 'Spotify Premium'; $root.Ty = $CT::Pane
$side = $root.Add('Deine Bibliothek', $CT::Group)
$l1 = $side.Add('Lieblingssongs Playlist • 512 Titel', $CT::ListItem); $b1 = $l1.Add('Lieblingssongs abspielen', $CT::Button)
$t1 = $l1.Add('Lieblingssongs', $CT::Text); $t1.Aid = 'listrow-title-spotify:user:robin:collection'
$u1 = $l1.Add('Playlist • 512 Titel', $CT::Text); $u1.Aid = 'listrow-subtitle-spotify:user:robin:collection'
$l4 = $side.Add('Koji Kondo Künstler', $CT::ListItem); $t4 = $l4.Add('Koji Kondo', $CT::Text); $t4.Aid = 'listrow-title-spotify:artist:0OdUWJ0sBjDrqHygGUXeCF'
$l2 = $side.Add('Final Fantasy X Album • Nobuo Uematsu', $CT::ListItem); [void]$l2.Add('Final Fantasy X abspielen', $CT::Button)
[void]$side.Add("Ohne Knopf`u{0007} Playlist", $CT::ListItem)
$main = $root.Add('', $CT::Group)
$sec = $main.Add('', $CT::Group)
$hd = $sec.Add('', $CT::Group); [void]$hd.Add('Zuletzt gespielt', $CT::Hyperlink)
$cards = $sec.Add('', $CT::Group)
$c1 = $cards.Add('Dein Mix der Woche', $CT::Group); [void]$c1.Add('Dein Mix der Woche abspielen', $CT::Button)
$k1 = $c1.Add('Dein Mix der Woche', $CT::Hyperlink); $k1.Val = 'https://xpui.app.spotify.com/playlist/37i9dQZEVXcBWIGoYBM5Mq'
$c2 = $cards.Add('Zwei Links', $CT::Group); [void]$c2.Add('Zwei Links abspielen', $CT::Button)
$k2 = $c2.Add('a', $CT::Hyperlink); $k2.Val = 'https://xpui.app.spotify.com/album/6dVIqQ8qmQ5GBnJ9shOYGE'
$k3 = $c2.Add('b', $CT::Hyperlink); $k3.Val = 'https://xpui.app.spotify.com/album/1dVIqQ8qmQ5GBnJ9shOYGE'
$sec2 = $main.Add('Für dich gemacht', $CT::Group); [void]$sec2.Add('Release Radar abspielen', $CT::Button)
$bar = $root.Add('Wiedergabe', $CT::Group); [void]$bar.Add('Abspielen', $CT::Button); [void]$bar.Add('Play Fremdes', $CT::Button)
$AE::Root = $root
$r = [UzSpot.UzSpotUi]::Read(1, 3000, 6000, 48, $false, 30) | ConvertFrom-Json
Check ($r.done -and -not $r.cut -and $r.error -eq '') "gelesen, fertig, ohne Fehler"
$names = @($r.items | ForEach-Object { $_.name })
Check ($names.Count -eq 5 -and ($names -contains 'Lieblingssongs') -and ($names -contains 'Final Fantasy X') -and ($names -contains 'Dein Mix der Woche') -and ($names -contains 'Koji Kondo') -and ($names -contains 'Zwei Links')) "Bibliothek und Zuletzt gespielt: fünf Einträge"
Check (-not ($names -contains 'Release Radar') -and -not ($names -contains 'Fremdes')) "andere Abschnitte und Wiedergabeleiste: nichts"
Check ($r.secs.lib -eq 3 -and $r.secs.recent -eq 2 -and $r.nobutton -eq 2) "Abschnitte gezählt, Zeilen ohne Knopf gezählt"
$lk = @($r.items | Where-Object { $_.name -eq 'Lieblingssongs' })[0]
Check ($lk.kind -eq 'playlist' -and $lk.sec -eq 'lib' -and $lk.sub -eq 'Playlist • 512 Titel' -and $lk.uri -eq 'spotify:user:robin:collection') "Art, Unterzeile und Adresse"
$kk = @($r.items | Where-Object { $_.name -eq 'Koji Kondo' })[0]
Check ($kk.kind -eq 'artist' -and $kk.uri -eq 'spotify:artist:0OdUWJ0sBjDrqHygGUXeCF') "Zeile ohne Knopf, aber mit Adresse: Künstler"
$mx = @($r.items | Where-Object { $_.name -eq 'Dein Mix der Woche' })[0]
$zl = @($r.items | Where-Object { $_.name -eq 'Zwei Links' })[0]
Check ($mx.uri -eq 'spotify:playlist:37i9dQZEVXcBWIGoYBM5Mq' -and $zl.uri -eq '' -and @($r.items | Where-Object { $_.name -eq 'Final Fantasy X' })[0].uri -eq '') "Adresse aus dem Link der Karte; zwei verschiedene oder keine: leer"
Check ($r.uris -eq 3) "Adressen gezählt"

"Aufrufen"
Check ([UzSpot.UzSpotUi]::Invoke([int]$lk.i, 'Lieblingssongs', 4711, 2000) -eq 'ok' -and $b1.Invoked -eq 1) "richtiger Name und Prozess: aufgerufen"
Check ([UzSpot.UzSpotUi]::Invoke([int]$lk.i, 'Anderes', 4711, 2000) -eq 'anders' -and $b1.Invoked -eq 1) "anderer Name: nein"
Check ([UzSpot.UzSpotUi]::Invoke([int]$lk.i, 'Lieblingssongs', 999, 2000) -eq 'fremd' -and $b1.Invoked -eq 1) "anderer Prozess: nein"
Check ([UzSpot.UzSpotUi]::Invoke(500, 'Lieblingssongs', 4711, 2000) -eq 'weg' -and [UzSpot.UzSpotUi]::Invoke(-1, 'x', 4711, 2000) -eq 'weg') "unbekannte Nummer: weg"
$b1.Nm = 'Etwas anderes abspielen'
Check ([UzSpot.UzSpotUi]::Invoke([int]$lk.i, 'Lieblingssongs', 4711, 2000) -eq 'anders' -and $b1.Invoked -eq 1) "Knopf inzwischen umbenannt: nein"
$b1.Nm = 'Lieblingssongs abspielen'; $b1.CanInvoke = $false
Check ([UzSpot.UzSpotUi]::Invoke([int]$lk.i, 'Lieblingssongs', 4711, 2000) -eq 'kein Aufruf') "ohne Invoke-Muster: nichts"

"Grenzen"
$deep = New-Object System.Windows.Automation.AutomationElement; $deep.Ty = $CT::Pane
$cur = $deep.Add('Deine Bibliothek', $CT::Group)
for ($k = 0; $k -lt 200; $k++) { $cur = $cur.Add('', $CT::Group) }
[void]$cur.Add('Ganz tief abspielen', $CT::Button)
$AE::Root = $deep
$r2 = [UzSpot.UzSpotUi]::Read(1, 3000, 6000, 48, $false, 30) | ConvertFrom-Json
Check ($r2.done -and @($r2.items).Count -eq 0 -and $r2.nodes -le 60) "Tiefe begrenzt (48)"
$wide = New-Object System.Windows.Automation.AutomationElement; $wide.Ty = $CT::Pane
$lib = $wide.Add('Deine Bibliothek', $CT::Group)
for ($k = 0; $k -lt 700; $k++) { $it = $lib.Add("Liste $k Playlist", $CT::ListItem); [void]$it.Add("Liste $k abspielen", $CT::Button) }
$AE::Root = $wide
$r3 = [UzSpot.UzSpotUi]::Read(1, 3000, 6000, 48, $false, 30) | ConvertFrom-Json
Check (@($r3.items).Count -eq [UzSpotRegeln]::MaxItems -and $r3.cut) "höchstens 600 Einträge"
$r4 = [UzSpot.UzSpotUi]::Read(1, 3000, 200, 48, $false, 30) | ConvertFrom-Json
Check ($r4.nodes -le 201 -and $r4.cut) "Knoten begrenzt"
$odd = New-Object System.Windows.Automation.AutomationElement; $odd.Ty = $CT::Pane
$ol = $odd.Add('Deine Bibliothek', $CT::Group)
$oi = $ol.Add("Böse`u{202E}Liste`" Playlist", $CT::ListItem); [void]$oi.Add("Böse`u{202E}Liste`" abspielen", $CT::Button)
[void]$ol.Add('', $CT::ListItem).Add((('z' * 300) + ' abspielen'), $CT::Button)
$AE::Root = $odd
$r5 = [UzSpot.UzSpotUi]::Read(1, 3000, 6000, 48, $false, 30) | ConvertFrom-Json
Check (@($r5.items).Count -eq 2 -and @($r5.items)[0].name -eq 'Böse Liste"' -and @($r5.items)[1].name.Length -le 120) "Texte geprüft, JSON bleibt gültig"

"Virtuelle Liste (Bibliothek ganz durchblättern)"
$vr = New-Object System.Windows.Automation.AutomationElement; $vr.Ty = $CT::Pane
$vs = $vr.Add('Deine Bibliothek', $CT::Group)
$vl = $vs.Add('', $CT::Group)
for ($k = 0; $k -lt 300; $k++) {
    $id = 'spotify:playlist:P' + $k.ToString('D21')
    $row = $vl.Virt("Liste $k Playlist • Du", $CT::ListItem)
    $tt = $row.Add("Liste $k", $CT::Text); $tt.Aid = 'listrow-title-' + $id
    if ($k % 3 -eq 0) { [void]$row.Add("Liste $k abspielen", $CT::Button) }
}
$vl.Pos = 30
$AE::Root = $vr
$rv0 = [UzSpot.UzSpotUi]::Read(1, 8000, 20000, 48, $false, 20) | ConvertFrom-Json
Check (@($rv0.items).Count -eq 12 -and $vl.Scrolls -eq 0) "ohne voll: nur die sichtbaren Zeilen, kein Blättern"
$rv = [UzSpot.UzSpotUi]::Read(1, 15000, 30000, 48, $true, 20) | ConvertFrom-Json
$vn = @($rv.items | ForEach-Object { $_.name })
Check ($vn.Count -eq 300 -and $rv.ende -and -not $rv.cut -and $rv.uris -eq 300) ("voll: alle 300 Zeilen mit Adresse ({0}, {1} Schritte)" -f $vn.Count, $rv.steps)
Check (($vn | Select-Object -Unique).Count -eq 300 -and $rv.secs.lib -eq 300 -and @($rv.items | Where-Object { $_.kind -ne 'playlist' }).Count -eq 0) "keine doppelt, alle Bibliothek/Playlist"
Check ($vl.Pos -eq 30 -and $vl.Scrolls -gt 10) "danach wieder an der alten Stelle"
$l7 = @($rv.items | Where-Object { $_.name -eq 'Liste 7' })[0]
Check ($l7.uri -eq ('spotify:playlist:P' + (7).ToString('D21')) -and [UzSpot.UzSpotUi]::Invoke([int]$l7.i, 'Liste 7', 4711, 1000) -eq 'weg') "Zeile ohne Knopf: Adresse ja, Aufrufen nein"
$rc = [UzSpot.UzSpotUi]::Read(1, 15000, 400, 48, $true, 20) | ConvertFrom-Json
Check ($rc.cut -and -not $rc.ende -and $vl.Pos -eq 30) "Knotengrenze beim Blättern: abgebrochen, Stelle trotzdem zurück"

"Pfad der Spotify-App"
Invoke-Expression ([regex]::Match($src, '(?s)\n(function Test-AppPath\(.*?\n\})\n').Groups[1].Value)
$ad = 'C:\Users\Uz\AppData\Roaming'
Check (Test-AppPath 'spotify' 'Spotify' 'C:\Users\Uz\AppData\Roaming\Spotify\Spotify.exe' $ad '') "Spotify aus APPDATA"
Check (Test-AppPath 'spotify' 'Spotify' 'C:\Program Files\WindowsApps\SpotifyAB.SpotifyMusic_1.2.63.394.0_x64__zpdnekdrzrea0\Spotify.exe' $ad '') "Spotify aus dem Store"
Check (-not (Test-AppPath 'spotify' 'Spotify' 'C:\Temp\Spotify\Spotify.exe' $ad '')) "Spotify.exe anderswo: nein"
Check (-not (Test-AppPath 'spotify' 'Spotify' 'C:\Users\Uz\AppData\Roaming\Spotify\..\..\Temp\Spotify.exe' $ad '')) "Pfad mit ..: nein"
Check (-not (Test-AppPath 'spotify' 'Spotify' 'C:\Program Files\WindowsApps\Evil.SpotifyMusic_1.0_x64__zpdnekdrzrea0\Spotify.exe' $ad '')) "fremdes Store-Paket: nein"
Check (-not (Test-AppPath 'spotify' 'notepad' 'C:\Users\Uz\AppData\Roaming\Spotify\Spotify.exe' $ad '')) "falscher Prozessname: nein"
Check (-not (Test-AppPath 'spotify' 'Spotify' 'C:\Users\Uz\AppData\Roaming\Spotify\SpotifyLauncher.exe' $ad '')) "anderes Programm im Ordner: nein"

"Befehle (ohne Spotify: still leer)"
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
$jobs = @(
    @{ cmd = 'spotify-fenster-spielen'; args = @{ i = 0; name = 'Lieblingssongs' }; key = 'result'; want = 'nicht erlaubt' },
    @{ cmd = 'spotify-fenster'; args = @{ budget_ms = 'viel' }; key = 'ok'; want = 'False' },
    @{ cmd = 'spotify-fenster-spielen'; args = @{ i = '0; calc'; name = 'x' }; key = 'result'; want = 'nicht erlaubt' }
)
$n = 1
foreach ($j in $jobs) { $p.StandardInput.WriteLine((@{ id = $n; cmd = $j.cmd; args = $j.args } | ConvertTo-Json -Compress -Depth 5)); $n++ }
$p.StandardInput.Close()
$out = $p.StandardOutput.ReadToEnd()
[void]$p.WaitForExit(120000)
$replies = @{}
foreach ($line in ($out -split "`n")) {
    $l = $line.Trim()
    if (-not $l.StartsWith('{')) { continue }
    try { $rr = $l | ConvertFrom-Json } catch { continue }
    $replies[[int]$rr.id] = $rr
}
$n = 1
foreach ($j in $jobs) {
    $rr = $replies[$n]
    $got = ''
    if ($null -eq $rr) { $got = '(keine Antwort)' } elseif (-not $rr.ok) { $got = 'Fehler: ' + $rr.error } else { $got = [string]$rr.result.($j.key) }
    Check ($got -eq $j.want) ("{0} → {1}" -f $j.cmd, $got)
    $n++
}
$why = if ($replies[2] -and $replies[2].ok) { [string]$replies[2].result.why } else { '' }
Check ($why -in @('läuft nicht', 'kein Fenster', 'minimiert')) "ohne Spotify-Fenster: Grund statt Fehler ($why)"
""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
