# Uzai – Anleitung (Deutsch)

> Die Startseite des Projekts steht englisch in der [README](../README.md). Hier die ausführliche deutsche
> Anleitung und die Liste „Getestet“ je Version.

Eine Konsolenoberfläche für Windows-PCs. Uzai startet im Vollbild, wird nur mit dem Controller
bedient und bringt Steam-, Epic-, EA- und Emulatorspiele in eine gemeinsame Bibliothek – mit Erfolgen,
Freunden, Musik, YouTube ohne Werbung, Bildfiltern und Lossless Scaling, ohne dass man
zwischendurch in Windows herumklicken muss.

Gebaut mit Godot 4.5. Kein ES-DE, kein Pegasus, keine fremden Frontends.

---

## Herunterladen

- **Fertige Version:** unter *Releases* die neueste `Uzai-windows.zip` laden.
- **Neuester Stand:** unter *Actions → Windows-Build →* letzter grüner Lauf → *Artifacts →
  Uzai-windows*.

Zip entpacken, `Uzai.exe` starten. `Uzai.exe` und `Uzai.pck` müssen im selben Ordner liegen.

**Portabler Modus:** Legt man neben `Uzai.exe` einen leeren Ordner `uzai-daten` an, speichert Uzai
alles dort (Einstellungen, Bibliothek, Bilder). Sonst landet alles unter `%APPDATA%\Uzai`.

---

## Bedienung

| Taste | Was passiert |
|---|---|
| **A** | auswählen, Spiel starten |
| **B** | zurück |
| **X / Y** | Zusatzaktionen, stehen immer unten in der Leiste |
| **LB / RB** | Konsole bzw. Unterbereich wechseln (PS2 → PS1 → GameCube …) |
| **LT / RT** | Hauptbereich wechseln (Spiele, Shop, Profil, die Apps, Einstellungen); im Guide nur im Reiter *Spiel* die Lautstärke des Spiels, im Reiter *Musik* die der Musik und im Reiter *Bild in Bild* die des kleinen Videos |
| **Start** | Optionen zum markierten Spiel |
| **Select** (View) | Freunde als Seitenleiste (Steam und Discord); noch einmal Select oder B schließt. Steht gerade ein Pop-up da, öffnet Select zuerst das |
| **Guide** (Xbox-/PS-Taste) | Schnellmenü, auch mitten im Spiel |
| **View + Start** | Schnellmenü, falls die Guide-Taste von Windows oder Steam belegt ist |
| **Rechter Stick drücken** (R3) | Suche über alles: eigene Spiele, Einstellungen, Freunde – nach kurzer Tipp-Pause auch Shop, Musik, Streams und Filme (abschaltbar mit Y). Tastatur: F, Maus: die Lupe oben rechts |

### Aufbau
Oben stehen **Spiele · Shop · Profil** als Wörter, daneben hinter einem feinen Trenner
die Apps als Symbole – **Musik · Videos · Filme · Streams · Zimmer** und deine eigenen Apps (Netflix,
Programme …) mit ihrem echten App-Symbol –, dann **+** (App hinzufügen) und ganz rechts das Zahnrad
(Einstellungen). Unter dem Cursor zeigt ein Symbol seinen Namen; gewählt steht es gefüllt da.
Links/rechts und LT/RT laufen durch alle Reiter. A betritt die App (eigene Apps starten gleich,
das Zimmer geht gleich auf); A lange (oder X): verschieben, ausblenden, Ausgeblendetes zurückholen,
eigene Apps entfernen. Passen nicht alle Symbole in die Breite, sammelt der Ordner *Meine Apps* die
eigenen. Sichtbarkeit unter Einstellungen → Aussehen → Leiste oben. Die **Freunde** gleiten mit
Select von rechts herein (Liste von Steam und Discord, LB/RB wechselt den Dienst; A: Chat, Profil,
Beitreten). Das Bild oben rechts öffnet mit der Maus ebenfalls das
Profil. Reicht oben der Platz nicht, treten Level, Akku der Controller und zuletzt der Songtitel
zurück – die Reiter bleiben ganz.

### Die Startseite
Oben links das gewählte Spiel groß und ruhig, ohne Knöpfe: System, Spielzeit, zuletzt gespielt,
Schriftzug oder Titel, eine Zeile mit Genre und Studio (Steam) bzw. dem System, darunter Erfolge,
Bildfilter, Ordner und Freunde, die es gerade spielen. A auf einem Cover öffnet die Spielseite,
Y die Optionen, X macht es zum Favoriten. Oben rechts **Für dich**: Vorschläge aus echten Daten – ein Freund spielt gerade ein
Spiel, das du auch hast; Leute im Sprachkanal; fast alle Erfolge geschafft; ein Favorit, der lange
liegt; Neues in der Bibliothek; weiterspielen. Darunter die Quellen nur mit Namen (Zuletzt,
Favoriten, PS2, GameCube, Steam, PC, Ordner, Alle – LB/RB) und unten das Regal: Das gewählte Cover
steht links an der Kante, bündig mit dem Text, und hebt sich nur leicht ab (kein Hineinzoomen). Mit
dem Steuerkreuz nach oben kommen die Quellen, dann *Für dich*, dann die Bereiche. **A lange auf einer
Quelle**: *Verschieben* (links/rechts, A fertig – Uzai merkt sich die Reihenfolge), *Ausblenden*,
*Ausgeblendete Quellen* und *Ausgeblendete Spiele* zum Zurückholen (dort Y → *Ausblenden* aus oder
mehrere auswählen → *Wieder zeigen*). Kurz A zeigt wie bisher alle Spiele der Quelle.

### Die Spielseite
A auf einem Cover öffnet erst die Seite des Spiels: großes Bild mit Schriftzug, Spielzeit,
**Spielen**, Optionen, Favorit und Erfolge. Darunter Bilder aus dem Spiel (bei Steam aus dem
Store; A zeigt sie groß, LB/RB blättert), Erfolge, Freunde, die es gerade spielen, Angaben aus
dem Store, deine Spielzeit und weitere Spiele desselben Systems.

Emulator-Spiele bekommen ihre Bilder ohne Schlüssel aus dem Netz: große Spielszenen und eine
kurze Beschreibung aus Wikipedia (englische Seite für die Bilder, deutsche für den Text, mit
Quellenangabe), Spielszene und Titelbild von RetroAchievements (wenn verbunden) und aus der
Libretro-Sammlung. Gibt es kein großes Hintergrundbild, liegt eine Spielszene weich hinter der
Seite, und die Startseite nimmt sie als Hintergrund. Alles wird zwischengespeichert. Wer lieber direkt startet:
Einstellungen → System → *Spielseite vor dem Start* aus.

Emulator-Spiele, die über Uzai mit Schnellfortsetzen beendet wurden, zeigen **Fortsetzen (vor 2 Std.)**
mit einem Bild vom Moment des Beendens und **Neu starten** daneben (siehe *Ruhemodus und
Schnellfortsetzen*).

Nicht installierte Steam- und Epic-Spiele: *Installieren* startet den Download **über Uzai** – kein
Fenster von Steam oder Epic kommt nach vorn, keine Maus. Die Seite bleibt offen und zeigt Balken,
Größe, Tempo und Restzeit; A darauf pausiert, setzt fort oder bricht ab (Steam). Fertig wird daraus
*Spielen*, dazu eine Mitteilung mit *Spielen*. Details unter *Spiele → Installieren über Uzai*.

### Musik
Vorn steht **Für dich**. Angemeldet **wie die Spotify-App** (inoffiziell, nur auf ausdrücklichen Wunsch – siehe unten)
zeigt Uzai deine echten Mixe von Spotify – *Mix der Woche*, *Release Radar*, *Daily Mix 1–6*, *In
Dauerschleife*, *Zeitkapsel* und was Spotify sonst für dich macht – mit allen Titeln: A öffnet die
Liste wie eine Playlist, Y spielt ab, A auf einem Titel spielt ab dort. Diese Mixe holt Uzai von
derselben Startseite, die die Spotify-App selbst lädt (die interne Schnittstelle der Spotify-Apps),
damit sie auch dann kommen, wenn Spotify die alte öffentliche Web-Schnittstelle für solche
Anmeldungen bremst. Mit einer eigenen Spotify-App findet Uzai diese Mixe nur über die Suche und
spielt sie direkt ab; ihre Titellisten gibt Spotify seit Ende 2024 nicht mehr an eigene Apps
heraus. Daneben baut Uzai eigene Mixe aus deinen Hördaten:
*Deine Top-Titel* (diesen Monat), *Neu von deinen Künstlern* (ein eigenes Release Radar: neue
Alben und Singles der letzten sechs Wochen), *Lange nicht gehört* und *Zuletzt gehört*. Dazu
kommen deine Alben und Playlists. *Läuft gerade* zeigt großes Bild, Fortschritt, Steuerung mit
Lautstärke und das Gerät, daneben *Als Nächstes*.

Alles bleibt in Uzai. Läuft Spotify nirgends, startet Uzai die Spotify-App unsichtbar im
Hintergrund und holt die Wiedergabe dorthin. Einen Song schickst du an Freunde über den
Steam-Chat oder per QR-Code aufs Handy. Den Spotify-Jam gibt es nur in der Spotify-App, deshalb
fehlt er.

### Shop
Der Steam-Shop läuft in Uzai: Entdecken (mit Rampenlicht), Angebote, Topseller, Neu, Bald,
Genres (jede Kachel mit drei Spielen, die dort gerade oben stehen), Wunschliste und Suche. Die Seite eines Spiels ist aufgebaut wie die Spielseite: großes Bild mit Titel,
Bewertung, Preis, *Kaufen*, Wunschliste und Trailer. Darunter folgen Trailer (im eigenen
Player), Bilder, Beschreibung, Editionen, Erweiterungen, Bewertungen, Neuigkeiten und
Systemanforderungen.

Die Preise kommen aus dem deutschen Steam-Shop. Nennt eine Liste keinen Preis (die Genres und
damit auch *Weil du … spielst* schicken nur 0), fragt Uzai ihn gebündelt nach. *Kostenlos* steht
nur bei Spielen, die Steam als kostenlos führt; ist kein Preis bekannt, steht keiner da.

Die Bilder holt Uzai unter ihren echten Namen aus dem Steam-Store (neue Spiele haben dafür Ordner
mit Prüfsumme), gebündelt und eine Woche zwischengespeichert. Gibt es zu einem Spiel nur ein
Bild im Querformat, steht es ganz und unverzerrt auf der Karte, dahinter dasselbe Bild weich.

Die Wunschliste änderst du direkt in Uzai; X nimmt ein Spiel aus der Liste. *Kaufen* fragt in
Uzai mit Edition und Preis nach und legt das Spiel mit der Steam-Anmeldung in den Warenkorb
deines Kontos. Nur zum Bezahlen öffnet sich der Warenkorb im Steam-Client, denn Steam hat keine
Schnittstelle zum Kaufen.

### Filme
Aufgebaut wie Nuvio TV. **Start:** oben groß der Titel, auf dem du stehst (Schriftzug oder Name,
Genre, Laufzeit, Jahr, Bewertung, Beschreibung), das Bild oben rechts läuft in den Raum aus.
Darunter *Weiterschauen* (mit Restzeit und Balken, auch *Als Nächstes*) und die Kataloge der
Addons; bleibst du auf einem Plakat stehen, wird es breit und zeigt das Hintergrundbild. Y auf
einem Plakat: *Alle ansehen* (Raster mit Genre-Filter, lädt beim Blättern nach), X: Bibliothek,
Y auf *Weiterschauen*: Details, von vorn, entfernen. Unterbereiche (LB/RB): Start, Bibliothek und
Suche (Bildschirmtastatur oder Handy). Ganze Kataloge zeigt *Alle ansehen* an jeder Reihe. Addons
und Plugins verwaltest du über den Knopf *Addons und Plugins* oben in der Bibliothek (LB/RB
wechselt zwischen beiden) oder unter Einstellungen → Filme.

Die **Detailseite** zeigt Abspielen bzw. *S2 F3 fortsetzen*, Bibliothek, Gesehen und Trailer,
bei Serien die Staffeln als Reiter und die Folgen mit Vorschaubild (X: gesehen), darunter
Besetzung, ähnliche Titel und Angaben. A auf Abspielen oder einer Folge öffnet die
**Quellenwahl**: Filter je Addon, der Stand jeder Quelle (lädt, fertig, Fehler) und die Liste mit
Qualität, HDR, Größe und „Sofort bereit“; Y filtert nach Qualität. Bei angefangenen Titeln fragt
Uzai *Fortsetzen* oder *Von vorn*. Am Ende einer Folge startet die nächste nach einem Countdown
(B hält an). Den Reiter schaltest du unter Einstellungen → Filme aus.

### Der Guide (Schnellmenü)
Liegt über dem laufenden Spiel. Oben das Spiel mit Spielzeit, die laufende Musik, Freunde online,
Akku der Controller (ein Symbol je Controller) und die Uhr; darunter die Reiter **Spiel**, **Discord**, **Musik**,
**Freunde**, **System** (LB/RB, die helle Auswahl gleitet mit). X pausiert überall die Musik.
Außerhalb eines Spiels tritt die Startseite zurück und der Guide liegt auf den Farbverläufen.

- **Spiel:** oben das Spiel mit Cover, Spielzeit und Erfolgsbalken, *Zurück ins Spiel* und *Spiel
  beenden* (rote Pille, fragt nach). Darunter höchstens vier große Kacheln – meist Bildschirmfoto,
  Clip speichern, Übertragen (im Sprachkanal) und Bildrate ×2; eine laufende Aufnahme und ein nach
  einer Einladung offenes Steam-Overlay rücken nach vorn – und **Mehr**. *Mehr* ist eine
  Seitenleiste mit Gruppen: Aufnehmen und teilen (Aufnahme, Aufnahmen), Spielstand
  (Speichern/Laden im Emulator), Bild und Leistung (Bildrate ×2, Bildfilter), Mehrspieler (wer
  mitspielt, Freund einladen, alle aus dem Call zu Remote Play, Steam-Overlay), Sprachkanal (Mikro,
  Ton), Nebenbei (Bild in Bild), System (Controller, Ausschalten). Unten drei Karten: *Aufnahmen*
  mit Vorschau der neuesten (A öffnet die Galerie), *Erfolge* (zuletzt freigeschaltet, A die
  Liste) und *Mehrspieler* (A öffnet *Mehr* bei Mehrspieler). Ohne Spiel: das zuletzt gespielte
  Spiel mit kurzen Angaben, weitere Spiele zum direkten Starten, rechts daneben die neueste
  Aufnahme und unten die Woche. Beim Video:
  Fortschritt und *Als Nächstes*. **LT/RT** ändern hier nur die Lautstärke des Spiels (wie im
  Lautstärkemixer von Windows, samt Starter, Emulator und anderen Prozessen des Spiels) bzw. beim
  Video die des Videos; unter der Karte steht der Pegel. Läuft kein Spiel oder hat es keinen Ton,
  sagt Uzai das und ändert nichts.
- **Musik:** großes Cover mit Schein in seiner Farbe, Titel, Künstler, Album, Gerät, Fortschritt
  mit Zeiten; Zufall, zurück, Pause/weiter, weiter, *Gefällt mir*. Darunter *Als Nächstes*
  (öffnet die Warteschlange über dem Guide), *Playlists* (als Liste über dem Guide),
  *Abspielen auf …* und *Song schicken* (über den Steam-Chat in Uzai). **LT/RT** ändern hier nur
  die Musik: die Lautstärke des Spotify-Players bzw. der Musik-App, die Windows meldet (etwa
  Chrome oder Apple Music).
- **Freunde:** Steam, Discord-Server und Sprachkanal in einer Liste, jede Person nur einmal.
  Zuerst kommt, wer spielt (dein Spiel und offene Lobbys vorn), dann wer beitreten kann, dann
  wer online ist. Ungelesene Steam-Nachrichten zeigt ein Goldpunkt am Reiter. A öffnet ein Menü
  an der Person (siehe unten).
- **Discord – der Sprachkanal, in dem du bist:**
  - Die Leute stehen mittig über die Karte verteilt (bis fünf, sonst zum Durchblättern). Je Person eine Kachel: Profilbild, grüner pulsierender Ring, solange sie spricht, rotes
    Zeichen bei Mikro aus, LIVE beim Übertragen, darunter was sie gerade tut und ihre Lautstärke.
    Oben rechts steht, wer gerade spricht.
  - **A** auf einer Person öffnet ihr Menü: *Lautstärke* (links/rechts in
    Zehnerschritten bis 200 %, A setzt auf 100 %), *Für mich stumm*, bei Steam-Freunden *Nachricht*.
    **X** schaltet sie direkt für dich stumm bzw. wieder hörbar.
  - Bei dir selbst: Mikro, Ton, Übertragen. Oben Kanalname und „Server · N Personen“, unten genau
    eine Leiste: *Übertragen* (nur wenn ein Spiel oder Video läuft), *Streams ansehen*, *Kanal
    wechseln*, *Mikro*, *Ton*, *Verlassen*. *Kanal wechseln* zeigt die anderen Kanäle (die mit
    Leuten zuerst) und *Anderer Server …*.
  - Das läuft über die offizielle lokale Schnittstelle der Discord-App (RPC). Einrichten siehe
    *Konten*. Ohne Einrichtung zeigt der Reiter die Sprachkanäle aus dem Server-Widget.
  - *Spiel übertragen* – das laufende Spiel als „Go Live“ in den Sprachkanal oder Anruf, in dem
    du gerade bist. Discord hat dafür keine Schnittstelle (weder RPC noch Social SDK); Uzai drückt
    im Spiel die Taste, die du in Discord für „Toggle Screen Share“ einträgst (Discord-App unter
    Windows → Einstellungen → Tastenbelegung → Tastenbelegung hinzufügen). Uzai drückt
    standardmäßig **Strg+Umschalt+F9**, änderbar unter *Einstellungen → Im Spiel* (auch deutsch,
    z. B. `STRG+UMSCHALT+F9`). Nochmal drücken beendet die Übertragung.
    Damit es klappt: (1) Discord-App läuft (nicht im Browser), (2) du bist in einem Sprachkanal
    oder Anruf, (3) Discord erkennt das Spiel – Emulatoren oft nicht: dann einmal in Discord unter
    *Einstellungen → Registrierte Spiele → Hinzufügen* den Emulator wählen, während das Spiel läuft,
    (4) Spiel und Uzai laufen beide ohne oder beide mit Administratorrechten.
  - *In Discord übertragen* (runder Discord-Knopf neben *Übertragen*) – der Weg, der immer geht:
    Die Discord-App kommt mit deinem Sprachkanal nach vorn, die Controller-Maus ist an (linker
    Stick, A klickt), und Uzai drückt „<Spiel> streamen“ bzw. „Bildschirm teilen“ und „Live gehen“
    selbst (über die Bedienhilfe von Windows, UI Automation); was es nicht findet, klickst du.
    Läuft die Übertragung, geht es von selbst zurück ins Spiel, sonst mit der Guide-Taste (Spiel
    bzw. Video wieder vorn, Maus aus). *Einstellungen → Im Spiel → Übertragen über*: *Automatisch*
    (Taste; scheitert sie erkennbar, gleich weiter in der Discord-App), *Nur Taste*, *Discord-App*.
    Uzai drückt die Taste erst, wenn der Guide zu und das Spiel vorn ist, wie eine echte Tastatur
    (linke Strg/Umschalt/Alt, mit Scan-Nummer, 150 ms gehalten). Was es erkennt (Tippfehler in der
    Taste, Discord läuft nicht, kein Sprachkanal, Adminrechte), sagt eine Mitteilung; jeder Versuch
    steht in `logs\discord.log`. *Einstellungen → Im Spiel → Übertragung prüfen* drückt die Taste
    einmal bei Uzai und zeigt, wie sie ankommt. Ob Discord dann wirklich überträgt, meldet Discord
    nicht.
  - *Video übertragen* – läuft gerade ein Video (YouTube oder Filme), überträgt derselbe Knopf das
    Video. Einmalig in Discord unter *Registrierte Spiele → Hinzufügen* den Eintrag „Uzai Video“
    wählen (das Fenster des Videoplayers); Uzai weist beim ersten Mal darauf hin. Den Knopf gibt es
    auch als Kachel im Video-Reiter des Guides und im Menü an dir selbst.
  - Nicht in einem Kanal: oben deine Server als Pillen (so viele, wie in die Karte passen, lange
    Namen gekürzt, der Rest unter *Alle Server*), darunter die Sprachkanäle mit den Leuten darin.
  - *Streams ansehen* – die eine bewusste Ausnahme von „Uzai holt nie ein anderes Programm nach
    vorn“: Einem Stream zusehen geht nur in der Discord-App (Discord bietet keine Schnittstelle,
    um ihn in Uzai zu zeigen). Uzai schließt den Guide und öffnet deinen Sprachkanal bzw. Anruf
    in der Discord-App (`discord://-/channels/…`), dort wählst du den Stream. Die **Guide-Taste**
    bringt dich zurück: Uzai kommt wieder nach vorn, ohne dass der Guide aufgeht; im Spiel öffnet
    sie wie immer den Guide über dem Spiel (das Spiel läuft weiter).
  - Discord-Nachrichten und -Anrufe gehen weiterhin nur in der Discord-App selbst.
  - *Maus mit dem Controller* (Reiter System) – linker Stick bewegt die Maus, rechter Stick scrollt, A klickt,
    X ist Rechtsklick, B ist Zurück. Die Guide-Taste beendet es. Praktisch für alles ohne
    Controller-Steuerung.
- **System:** links die Mitteilungen, rechts Ton ausgeben (Fernseher ↔ Headset), *Lautstärke*,
  *Mikro*, Maus mit dem Controller, Einstellungen, Ausschalten. In den Reitern Discord, Freunde und
  System tun LT/RT nichts.
  - *Lautstärke* öffnet den Mixer: oben die Gesamtlautstärke, das Mikrofon, darunter nur die
    Programme, die gerade Ton ausgeben – das Spiel (samt Starter und Emulator, auch wenn es kurz
    still ist), Uzai, Musik, Discord, Video, Browser und der Rest. Links/rechts ändern in
    Fünferschritten, A schaltet stumm; lauter hebt Stumm zuerst auf. Uzai stellt dabei nur Pegel
    und Stumm der Audiositzungen ein, wie der Lautstärkemixer von Windows.
  - *Mikro* schaltet mit einem Druck das Mikrofon von Windows (Standard- und
    Kommunikationsgerät) und, wenn verbunden, dein Discord-Mikro stumm bzw. wieder an. Solange es
    aus ist, steht oben in der Kopfleiste und im Guide **Mikro aus**.
  Darunter **Controller** wie im Xbox-Guide: ein Controller mit Name, Spieler (Xbox: der Anschluss,
  wie der Leuchtring), Verbindung (Kabel, Funk, Bluetooth) und Akku (Voll/Mittel/Schwach/Fast leer,
  PlayStation in Prozent, „lädt“); mehrere in einer Zeile mit je einem Akku, A zeigt alle. A auf
  einem Controller öffnet die Seitenleiste: *Kurz vibrieren lassen* (welcher ist
  welcher?), *Controller testen* und bei kabellosen Xbox-Controllern *Controller ausschalten* – über
  `XInputPowerOffController` (Ordinal 103 von `xinput1_4.dll`), eine nicht dokumentierte, aber seit
  Windows 8 vorhandene Funktion; klappt über den Xbox-Funkadapter bzw. den 360-Empfänger, über
  Bluetooth meist nicht (dann sagt Uzai, dass man die Xbox-Taste 6 s hält).

**Freunde** (Reiter *Freunde* im Guide oder der Bereich *Freunde*) – Steam und Discord zusammen.
A auf einem Freund zeigt, was gerade geht:
  - *Spiel beitreten* – nur wenn sein Spiel eine offene Lobby oder einen Server meldet (wie im
    Steam-Menü),
  - *Zum Spiel einladen* – wenn du selbst ein Steam-Spiel spielst. Uzai lädt direkt ein, ohne
    Steam-Overlay oder Steam-Fenster: Es nutzt die Steamworks-Bibliothek des laufenden Spiels
    (`steam_api64.dll`) und schickt dieselbe Einladung, die auch das Overlay schicken würde. Bietet
    das Spiel keine an, aber du bist in einer offenen Lobby, geht ein Beitreten-Link in den Chat,
  - *Nachricht schreiben* und *Schnellnachrichten* („Bin gleich da!“, „GG!“ …) an Steam-Freunde,
  - *Link aus der Zwischenablage schicken* (z. B. ein Spotify-Jam-Link),
  - *Profil* (in Uzai: Level, befreundet seit, zuletzt gespielt, gemeinsame Spiele),
    *Erfolge vergleichen*, bei Discord *Sprachkanal beitreten*.

**Dein Profil und Status** – oben rechts im Reiter *Freunde* (wie bei Steam und Discord, wo du
selbst über der Freundesliste stehst): dein Bild mit Statuspunkt, Name und je ein Punkt für Steam
und Discord, im Spiel „Spielt …“. Vom ersten Freund nach oben, A öffnet *Dein Status*:
  - *Steam*: Online, Abwesend, Unsichtbar, Offline. Läuft Steam am PC (angemeldet), ändert Uzai
    den Status über Steam selbst mit dem offiziellen Link `steam://friends/status/…` – still, ohne
    Fenster, Uzai bleibt vorn (öffnet Steam doch ein Fenster, schließt Uzai es wieder). Uzai meldet
    dann nie selbst einen Status (das ließ am PC alle Freunde offline erscheinen). Nur wenn Steam
    am PC aus ist, setzt Uzai den Status über seine eigene Steam-Anmeldung (QR-Code unter
    Einstellungen → Konten). „Nicht stören“ gibt es bei Steam hier nicht: Steam hat dafür keinen
    Link, und es stellt dort nur Mitteilungen stumm.
  - *Discord*: Online, Abwesend, Bitte nicht stören, Unsichtbar – über die Discord-Verbindung für
    Nachrichten (Discord Social SDK). Ohne sie steht dort, wo man sie einrichtet; die
    Sprachkanal-Verbindung kann den Status nicht ändern.
  - Außerhalb eines Spiels: *Mein Profil ansehen* (Profil-Reiter), *Konten* (Einstellungen →
    Konten) und *Aufnahmen*, sobald es die Galerie gibt.

Der Bereich *Freunde* zeigt links die Liste und rechts eine große Karte mit dem Spiel der Person,
*Beitreten*, *Chat* und *Profil* (X Chat, Y Profil). Der Chat läuft ganz in Uzai, mit ganzem
Verlauf, Tipp-Anzeige und Schnellantworten. Links zu YouTube, Spotify, dem Steam-Shop und zum
Beitreten öffnen in Uzai; alles andere geht als QR-Code aufs Handy.

Bildschirmfotos landen in *Bilder\Uzai*, Clips in *Videos\Uzai*. *Clip speichern* nimmt Uzai
selbst auf (siehe *Aufnahmen* unten); wer lieber die Xbox Game Bar oder NVIDIA nimmt, stellt das
unter Einstellungen → Aufnahmen um.

So funktionieren Nachrichten: **Steam-Nachrichten** verschickt Uzai selbst – über eine eigene
Verbindung zu Steams Chat-Servern, so wie die Steam-App (Steam bietet das Senden über normale
Web-Anfragen nicht an). Dafür meldet man sich einmal per QR-Code an; Uzai erscheint dabei als
Gerät „Uzai“, die Steam-App am PC bleibt angemeldet, kein Steam-Fenster geht auf. Ist Uzai noch
nicht angemeldet, kommt zuerst der QR-Code, danach geht die Nachricht raus. Eine Anmeldung aus
0.7.4 oder älter darf nur lesen: Beim ersten Senden kommt einmal der QR-Code, danach geht es.
**Discord** hat für private Nachrichten und Anrufe keine Schnittstelle; Uzai bietet sie deshalb
nicht an, statt die Discord-App nach vorn zu holen.

**Steams Guide-Taste:** Damit die Guide-Taste nicht zusätzlich Steam Big Picture öffnet, schaltet Uzai
Steams Guide-Taste beim ersten Start ab. Vorher sagt ein Fenster, was passiert („Verstanden“ oder „Steam
behalten“); läuft Steam, startet es dafür kurz neu. Das gilt auch, wenn Uzai nicht läuft. Zurück unter
Einstellungen › Controller › Steam auf der Guide-Taste.

Die Guide-Taste funktioniert auch, während ein Spiel im Vordergrund läuft: Uzai bleibt im
Hintergrund und ein kleiner Wächter liest die Xbox-Controller direkt aus (auch View + Start).
PlayStation-Controller gehen im Spiel nur, wenn Steam Input oder DS4Windows sie als
Xbox-Controller ausgibt.

Im Video:

| Taste | Was passiert |
|---|---|
| **A** | Pause / weiter |
| **← / →** | 10 Sekunden zurück / vor (gedrückt halten: schneller); kurz nach einem übersprungenen Abschnitt führt ← an seinen Anfang zurück |
| **LT / RT** | 1 Minute zurück / vor |
| **↑ / ↓** | Lautstärke |
| **LB / RB** | voriges / nächstes Video |
| **X** | Untertitel an/aus |
| **Y** | Qualität, Untertitel, Geschwindigkeit, Nur Ton, Merken, Kanal abonnieren |
| **B** | Video beenden (Uzai merkt sich die Stelle) |
| **Start/≡** | Bild in Bild; bei *Nur Ton*: im Hintergrund weiterhören |

Bei **Shorts** (Reiter *Shorts* unter Videos) blättern **↑ / ↓** zum vorigen bzw. nächsten Short,
**LT / RT** stellen die Lautstärke; am Ende kommt gleich der nächste.

Tastatur geht auch: Pfeiltasten, Enter, Esc, Q/E, Bild↑/Bild↓, G für das Schnellmenü.

Auf der Bildschirmtastatur (Chat, Suche im Shop, bei Filmen und Videos, Namen, Schlüssel):

| Taste | Was passiert |
|---|---|
| **A** | Taste tippen – an der Stelle der Schreibmarke |
| **LB / RB** | Schreibmarke einen Buchstaben nach links / rechts (gedrückt halten: weiter) |
| **X** | Buchstaben vor der Schreibmarke löschen |
| **Y** | Leerzeichen |
| **LT / RT** | Großbuchstaben / Sonderzeichen |
| **Start** | Fertig (übernehmen) |
| **B** | Abbrechen |
| **Steuerkreuz** | Am Rand geht es auf der anderen Seite weiter: links aus der Reihe kommt rechts wieder herein (und umgekehrt), hoch aus der Zahlenreihe führt in die untere Leiste, runter aus der Leiste in die Zahlenreihe |

Mit einer echten Tastatur tippst du direkt; Pos1/Ende springen an den Anfang/das Ende, Entf
löscht hinter der Schreibmarke.

---

## Einrichten

Beim ersten Start führt Uzai durch eine kurze **Einrichtung** (wie bei einer Konsole), danach
geht alles unter **Einstellungen**.

### Einrichtung beim ersten Start
Nach der Startanimation kommen ganzseitige Karten nacheinander; oben zeigen Punkte, wo man steht.
**A** geht weiter, **Y** („Später“) überspringt einen Schritt, **B** geht zurück (im ersten Schritt:
ganz überspringen). Sprache ist Deutsch.
1. **Willkommen** – das Licht geht an, das Zeichen erscheint groß; Sprache, „Starten“ oder
   „Überspringen“. Der Controller wird dabei still erkannt (Koppeln und Test aller Tasten:
   *Einstellungen → Controller*).
2. **Spiele** – der Zähler läuft hoch, die eigenen Cover fliegen herein, je Quelle (Steam, Epic, EA …)
   ein Schild mit Anzahl. Uzai sucht an den üblichen Stellen nach Emulatoren (`C:\Emulatoren`,
   Programme, Steam …) und Spieleordnern (`<Laufwerk>\ROMs\ps2`, `Emulation\roms\…` wie bei
   EmuDeck/RetroBat) und zeigt die Funde – „Weiter“ übernimmt die gewählten und liest ein. Dazu:
   eigenen Ordner wählen.
3. **Die Guide-Taste** – eine kleine Szene zeigt, was der Guide kann; die echte Taste öffnet ihn zum
   Ausprobieren. Guide-Taste halten und Wecken gleich daneben.
4. **Konten** – Steam und Discord oben, dann Epic, Spotify, YouTube, Twitch, Nuvio, RetroAchievements
   und SteamGridDB: je eine Zeile, per QR-Code oder Freigabe in der App; der Zustand ändert sich live.
   Alles freiwillig („Später“).
5. **Bereit** – „Alles bereit“ mit einer Zeile Bilanz; „Los“ lässt die Startseite sich aufbauen.
   Freiwillig über „Mehr einrichten“: Aussehen, Dein Zimmer und Extras (Bildrate ×2, Guide-Taste
   weckt Uzai, Mit Windows starten …).

Der Stand wird bei jedem Schritt gespeichert: Nach einem Neustart geht es dort weiter. Wer Uzai schon
benutzt (Einstellungen, Konten oder Spieleordner vorhanden), bekommt die Einrichtung nie von selbst.
Noch einmal: *Einstellungen → System → Einrichtung erneut starten*.

### Spiele
- **Bibliothek → Spieleordner:** pro System einen Ordner wählen, z. B. `D:\Spiele\PS2`. In der
  Ordnerauswahl geht B eine Ebene hoch (bei den Laufwerken schließt B), Y bricht ab.
  Unterordner werden mit durchsucht. Mehrteilige Spiele (`Disc 1`, `Disc 2`, `.m3u`) werden zu
  einem Eintrag zusammengefasst.
- **Steam, Epic und EA app** werden automatisch gefunden, jede Quelle mit eigenem Reiter auf der
  Startseite (*Steam*, *Epic*, *EA*), mit Spielzeit, „Für dich“, Ordnern, Suche im Raster und in
  der Spielzeit-Statistik. Ein- und ausschalten unter *Einstellungen → Spiele → Quellen*. Mit
  Steam-Schlüssel (siehe *Konten*) zeigt Uzai auf Wunsch auch nicht installierte Steam-Spiele.
- **Epic Games:** Uzai liest nur die Dateien, die der Epic Games Launcher selbst ablegt –
  `C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests\*.item` (Name, Ordner, Programmdatei,
  Katalog-IDs) und `C:\ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat`.
  Zusatzinhalte, die Unreal Engine und halbe Installationen bleiben draußen. Gestartet wird über
  den Launcher-Link `com.epicgames.launcher://apps/<Namespace>%3A<Item>%3A<App>?action=launch&silent=true`
  (Anmeldung, Kopierschutz und Updates wie gewohnt); das Spielende erkennt Uzai am Prozess im
  Spielordner.
- **Gekaufte, nicht installierte Epic-Spiele** stehen hinten im Reiter *Epic* und im Raster,
  gedämpft und mit Download-Zeichen (nie in „Zuletzt“, „Für dich“ oder der Spielzeit; starten lassen
  sie sich nicht). Quelle ist allein die Katalogdatei, die der Epic Games Launcher für die eigene
  Bibliothek auf dem PC ablegt: `C:\ProgramData\Epic\EpicGamesLauncher\Data\Catalog\catcache.bin`
  (ältere Launcher: `%LOCALAPPDATA%\EpicGamesLauncher\Saved\Data\Catalog\catcache.bin`; Base64
  eines JSON-Arrays mit `namespace`, `id`, `title`, `categories`, `mainGameItem`,
  `releaseInfo[].appId`, `keyImages`). Dafür fragt Uzai keine Epic-Server und braucht keine
  Anmeldung (alle gekauften Spiele gibt es mit dem Epic-Konto, siehe nächster Punkt). Ausgelassen werden
  Zusatzinhalte, Add-ons, Engine/Werkzeuge und Spiele ohne Windows-Version; schon installierte
  (gleicher App-Name oder Katalog-ID) erscheinen nur einmal und bekommen dabei das Cover aus dem
  Katalog (`DieselGameBoxTall`, Hintergrund `DieselGameBox`, Logo `DieselGameBoxLogo`, geladen von
  Epics Bildserver – ganz ohne SteamGridDB). *Installieren* läuft über Uzai (siehe nächster Punkt
  *Installieren über Uzai*): Uzai öffnet den offiziellen Launcher-Link
  `com.epicgames.launcher://apps/<Namespace>%3A<Item>%3A<App>?action=install` und bestätigt den
  Dialog des Launchers im Hintergrund. Solange eine Installation aussteht (höchstens 6 Stunden), schaut Uzai alle 5 s
  nach Änderungen im Manifest-Ordner (nur Dateizeiten) und beim Zurückkommen nach; lädt der
  Launcher gerade (`Manifests\Pending`), steht das auf der Spielseite. Fertig installiert wird aus
  „Installieren“ „Spielen“. Fehlt die Katalogdatei, zeigt Uzai nur die installierten Spiele und
  sagt es unter *Einstellungen → Spiele* (einmal die Bibliothek im Launcher öffnen hilft). Schalter:
  *Einstellungen → Spiele → Nicht installierte Epic-Spiele anzeigen* (Standard an).
- **Raster *Alle anzeigen* – ordnen und filtern:** Y öffnet *Ordnen und filtern*: Sortierung,
  Abschnitte (nach Plattform, Genre, Spielreihe, Jahrzehnt oder Erscheinungsjahr, jeweils mit
  Überschrift und Anzahl) und Filter (System oder Laden, installiert, gespielt, Favoriten, Genre,
  Erscheinungsjahrzehnt, Spielzeit, Erfolge), beliebig kombiniert; links/rechts wechselt den Wert,
  das Raster folgt gleich dahinter. Was eingestellt ist, lässt sich als *Ansicht* mit Namen
  speichern; LB/RB wechseln im Raster zwischen *Alle Spiele* und den Ansichten. Genre und Jahr
  kommen aus dem Steam-Shop – beim Ansehen eines Spiels oder auf Wunsch für alle Steam-Spiele auf
  einmal (*Genre und Jahr von Steam holen*, eine Abfrage etwa alle 1,6 s, pausiert im Spiel). Was
  keine Angabe hat (Emulator-, Epic-, EA-Spiele), steht unter *Unbekannt* statt geraten. Spielreihen
  erkennt Uzai vorsichtig am Titel (gleicher Name vor Untertitel oder Nummer, mindestens zwei
  verschiedene Spiele); alles andere steht unter *Einzelne Spiele*. Erfolge zählen nur, soweit Uzai
  sie schon kennt (Erfolge-Bereich, Spielseite).
- **Installieren über Uzai (Steam und Epic):** Ziel ist: *Installieren* drücken, und der Download
  läuft, ohne dass du ein anderes Fenster bedienst. Wie Uzai das macht, je nach Laden:
  - **Steam, direkt (mit Steam-Anmeldung in Uzai, *Konten → Steam*):** Uzai nutzt Steams eigenen
    Fern-Download – denselben Weg, über den die Steam-App am Handy ein Spiel auf dem PC installiert
    (Dienst `IClientCommService/InstallClientApp`, mit dem Zugang aus der Anmeldung über die Web-API,
    ohne Zugang kurz über Steams Chat-Server, weil du es selbst anstößt). Uzai wählt die Steam-Sitzung
    dieses PCs (gleicher Rechnername – nie einen anderen PC), startet Steam bei Bedarf still
    (`-silent`, ohne Fenster) und wartet, bis es angemeldet ist. Steam lädt dann ohne Dialog in seinen
    **Standardordner**. Pausieren/Fortsetzen (`SetClientAppUpdateState`) und Abbrechen
    (`UninstallClientApp`, entfernt das schon Geladene) gehen aus Uzai.
  - **Steam ohne Anmeldung (oder wenn Steam den Fern-Download ablehnt):** `steam://install/<appid>`;
    Uzai bleibt dabei „immer oben“ (wie beim Spielstart) und drückt im Dialog „Installieren“ über die
    Bedienhilfe-Schnittstelle von Windows (UI Automation, wie bei „In Discord übertragen“), notfalls
    einmal Enter. **Lizenzvereinbarungen bestätigt Uzai nie selbst:** Dann – und wenn die Knöpfe nicht
    eindeutig sind – erscheinen sie in Uzai als Auswahl mit dem Controller. Findet Uzai gar keine Knöpfe,
    zeigt es das Fenster **in Uzai** (Live-Bild) und bedient es mit dem Controller: Steuerkreuz ↑/↓ =
    nächstes Feld (Tab), ←/→ = Pfeiltasten, A = Enter, X = Leertaste, Y = Esc, B = zurück zu Uzai. Das
    Fenster selbst bleibt hinter Uzai und wird danach minimiert.
  - **Steam in einen anderen Bibliotheksordner** (*Einstellungen → Spiele → Installieren und Downloads →
    Speicherort neuer Steam-Spiele*, Liste der Steam-Bibliotheken mit freiem Platz): Den Fern-Download
    gibt es nur für den Standardordner. Für einen anderen Ordner legt Uzai dort Steams
    `appmanifest_<appid>.acf` an („Aktualisierung nötig“, StateFlags 1026) – **nur wenn Steam zu ist**,
    denn Steam liest neue Manifeste nur beim Start. Läuft Steam, fragt Uzai: *Steam kurz neu starten*
    (Steams eigenes `steam://exit`, dann still wieder an; nie während eines Spiels) oder *In den
    Standardordner*. Uzai legt nur eine neue Datei an, nie wird eine vorhandene geändert; gibt es den
    Spielordner schon, nimmt Uzai lieber Steams Weg.
  - **Epic:** Der Launcher hat keine Schnittstelle zum Installieren (einen eigenen Downloader wie
    Legendary baut Uzai bewusst nicht). Uzai öffnet den Installationslink, bleibt oben und drückt den
    **eindeutigen** „Installieren“-Knopf (UI Automation); stehen mehrere da (Bibliothek dahinter) oder
    keiner, wählst du in Uzai bzw. bedienst das Fenster wie oben in Uzai. Gespeichert wird im
    Standardordner des Launchers (angezeigt in den Einstellungen, aus `GameUserSettings.ini`). Der
    Launcher muss angemeldet sein. Pausieren und Abbrechen gehen bei Epic nur im Launcher.
  - **Fortschritt:** Steam: `appmanifest_<appid>.acf` (Zustand, Bytes; Tempo aus dem Verlauf), mit
    Web-Zugang zusätzlich `GetClientAppList` (Tempo, Restzeit von Steam selbst). Epic:
    `Manifests\Pending\*.item`, das Protokoll `%LOCALAPPDATA%\EpicGamesLauncher\Saved\Logs\EpicGamesLauncher.log`
    (Epic dokumentiert das Format nicht – Uzai nimmt nur Zeilen mit Prozent bzw. „x GB von y GB“), sonst
    die Größe des Spielordners im Verhältnis zur erwarteten Größe („ca. …“), sonst „Epic lädt …“.
    Zu sehen auf der Spielseite, auf dem Cover (Balken und Prozent) und unter **Downloads** (Guide →
    *Schnell einstellen*, solange etwas lädt, und *Einstellungen → Spiele → Installieren und
    Downloads*). Laufende Downloads überstehen einen Neustart von Uzai; Steam-Downloads, die anders
    angestoßen wurden, erscheinen ebenfalls. Fertig: Mitteilung mit *Spielen*.
  - *Dialoge selbst bestätigen* (Standard an) schaltet das Bestätigen ab – dann zeigen Steam bzw. Epic
    ihren Dialog wie früher. Protokoll: `logs/installs.log`. Kostenlose Spiele aus dem *Shop* installiert
    weiter Steam selbst (`steam://install`), weil sie vorher noch nicht im Konto sind.
  - **Download-Zentrale** (*Downloads*): Lädt gerade, Uzais **Warteschlange**, anstehende
    **Steam-Updates** und Fertiges. Lädt schon etwas, fragt „Installieren“: *Danach laden* (Uzai gibt
    Steam bzw. Epic das nächste Spiel erst, wenn das vorige fertig ist – die Reihenfolge stellst du in
    Uzai um), *Gleich mitladen* oder – mit *Nachts laden* – *Heute Nacht laden*. Updates liest Uzai aus
    den appmanifests (`StateFlags`, `BytesToDownload`, nur lesen) und stößt sie mit der Steam-Anmeldung
    an (`SetClientAppUpdateState`, wie die Steam-App am Handy).
  - **Nachts laden** (*Einstellungen → Spiele → Installieren und Downloads*, Standard aus): im
    Zeitfenster (Standard 1 bis 6 Uhr), nur wenn der PC ohnehin an ist und Uzai im Ruhemodus wartet,
    eins nach dem anderen; auf Wunsch mit allen anstehenden Steam-Updates – nie für das laufende Spiel.
    Uzai weckt den PC nie und ändert keine Energieeinstellung. Unbeaufsichtigt öffnet Uzai keinen
    Dialog: Was einen braucht (Epic, Steam ohne Anmeldung, eine Lizenzfrage), wartet, bis du da bist.
    Vor jedem Start prüft Uzai den Platz; was im Ruhemodus fertig wird, meldet eine stille Mitteilung
    beim Aufwachen. Die **Bandbreite** setzt nur Steam (*Einstellungen → Downloads*); Uzai liest
    `DownloadThrottleKbps` aus `config.vdf` nur aus.
- **Alle gekauften Epic-Spiele mit dem Epic-Konto (inoffiziell, auf Wunsch):** *Einstellungen →
  Konten → Epic Games → Mit Epic anmelden*. **Anmeldung wie Heroic/Legendary – nicht offiziell von
  Epic unterstützt.** Uzai meldet sich so an wie diese freien Launcher (und Playnite): über Epics
  eigene Anmeldeseite mit der öffentlichen Client-ID des Epic Games Launchers. Ablauf am Fernseher:
  QR-Code mit dem Handy scannen → Uzais Handy-Seite → *Bei Epic anmelden* öffnet
  `https://www.epicgames.com/id/login?redirectUrl=…/id/api/redirect?clientId=…&responseType=code`;
  nach der Anmeldung zeigt Epic eine Textseite (JSON) mit `authorizationCode`. Die ganze Seite oder
  nur den Code (32 Zeichen) kopieren, auf der Handy-Seite einfügen, *An Uzai senden*. Ohne WLAN-Handy:
  *Code eintippen* (Bildschirmtastatur, auch *Einfügen* nach *Im Browser am PC*). Das Passwort
  sieht Uzai nie. Uzai tauscht den Code beim Anmeldedienst gegen eine Anmeldung, speichert davon
  nur die Erneuerungs-Anmeldung (`accounts.epic_refresh`, wie bei Spotify) samt Name und Konto-ID,
  erneuert selbst und schreibt nichts davon ins Protokoll. Die Liste kommt aus Epics
  Bibliotheksdienst (alle Seiten über `nextCursor`), Titel und Bilder aus dem Katalog (gebündelt je
  Namespace, nur neue Einträge); gefiltert wie bei der Katalogdatei (keine DLC, Engine/Unreal-Inhalte,
  Plugins, Programme, Mac-only), ohne Doppelte mit installierten und Katalogdatei-Spielen (App-Name,
  Katalog-ID). Nicht installierte zeigen wie oben *Installieren* über den Launcher. Zwischenspeicher
  `epic_konto.json` im Datenordner; neu geholt beim Einlesen höchstens alle 6 Stunden, sofort mit
  *Jetzt neu einlesen* oder *Spiele jetzt abgleichen*. Ändert oder sperrt Epic etwas, zeigt Uzai
  still weiter installierte, Katalogdatei- und die zuletzt geholten Spiele; abgelaufene Anmeldung
  (nach einigen Wochen ohne Nutzung) steht in den Einstellungen. *Von Epic abmelden* beendet die
  Sitzung bei Epic und löscht Anmeldung und Liste.
- **EA app (früher Origin):** Uzai liest nur, ohne etwas zu ändern: die Spielordner aus der Registry
  (`HKLM\SOFTWARE\(WOW6432Node\)EA Games`, `Electronic Arts`, `Origin Games` → „Install Dir“,
  dazu Deinstallations-Einträge von Electronic Arts), die üblichen Ordner `Program Files\EA Games`
  und `Origin Games` und die Origin-Manifeste `C:\ProgramData\Origin\LocalContent\*\*.mfst`. Ein
  Ordner zählt, wenn darin `__Installer\installerdata.xml` liegt (Titel, Inhalts-IDs,
  Programmdatei). Gestartet wird über die EA app: `origin2://game/launch?offerIds=<IDs>`, ist nur
  `link2ea` angemeldet `link2ea://launchgame/<ID>?platform=pcwin`, ohne beides die Programmdatei
  selbst. Über Steam oder Epic gekaufte EA-Spiele stehen nur dort (kein doppelter Eintrag). Den
  verschlüsselten Installationsstand der EA app (`C:\ProgramData\EA Desktop\…`) liest Uzai nicht.
  **Nicht installierte EA-Spiele gibt es nicht:** Die EA app legt keine lesbare Liste der gekauften
  Spiele auf den PC (nur verschlüsselte Daten), und die Liste gibt es sonst nur über EAs
  inoffizielle Web-Schnittstelle mit dem Anmelde-Token der App – beides nutzt Uzai bewusst nicht.
- **Bilder für Epic- und EA-Spiele** kommen bei Epic zuerst aus dem Katalog des Launchers (siehe oben), sonst von SteamGridDB (Suche nach dem Titel, Schlüssel unter
  *Spiele → Erweitert*) oder aus dem Medienordner (`<Medien>\epic\…`, `<Medien>\ea\…`, wie bei den
  Systemen). Im Steam-Status steht beim Spielen „Spielt Nicht-Steam-Spiel: <Titel>“ wie bei
  Emulator-Spielen.
- **Unterordner werden zu Ordnern:** liegt etwas in `D:\Spiele\PS2\RPG\…`, gibt es im Reiter
  PS2 eine Ordner-Kachel „RPG“ (ab zwei Spielen; pro System abschaltbar).
- **Eigene Ordner** pro System oder für alle Systeme: im Spiel *Optionen → Ordner* oder unter
  *Bibliothek → Neuer Ordner*. Ordner erscheinen als Kacheln vorne im Reiter des Systems,
  Ordner für alle Systeme bekommen einen eigenen Reiter. *Spiele auswählen* zeigt alle Spiele
  mit Haken – A hakt an oder ab.
- **PC-Spiele-Ordner:** einen Ordner mit Verknüpfungen (`.lnk`), Internet-Verknüpfungen (`.url`
  von GOG Galaxy, Battle.net, Xbox-App) und Programmen (`.exe`) wählen – alles darin erscheint
  unter *PC*, mit Spielzeit. Einzelne Spiele gehen auch über *PC-Spiel hinzufügen*.
- **Verknüpfungen:** *Optionen → Verknüpfung auf dem Desktop / Ins Startmenü*. Die Verknüpfung
  startet das Spiel direkt über Uzai (mit Spielzeit, Bildfilter und Guide). Läuft Uzai schon,
  übernimmt das laufende Uzai, ohne dass ein zweites Fenster aufblitzt (neue Verknüpfungen starten
  dafür ohne Fenster; ältere bitte einmal neu anlegen). Hängt ein altes Uzai, fragt das neue, ob es
  das alte beenden soll.
- **Spielstart wie an der Konsole:** Vom Druck auf *Spielen* an bleibt Uzais Startbildschirm ganz
  vorn – über Starter- und Emulatorfenstern, über der Taskleiste und ohne Mauszeiger –, bis das
  Spielfenster vorn liegt und den Bildschirm füllt (höchstens 8 s nach dem ersten Fenster, bei
  Startern wie Steam- oder Spiel-Launchern 4 s, bei Spielen im Fenstermodus sobald das Fenster
  still steht). Dann blendet Uzai auf Schwarz und geht aus dem Weg; spielst du mit Controller,
  wandert der Mauszeiger an den rechten Bildschirmrand. Wartet unterwegs ein Fenster auf dich
  (Steam „Shader werden verarbeitet“, Fehlermeldung des Emulators, Windows-Abfrage), gibt Uzai
  nach drei Sekunden den Platz ganz oben ab, damit du es siehst. Dauerhaft ändert sich nichts:
  keine Taskleisten- oder Mauseinstellung, keine Registry; nach dem Spiel ist alles wie vorher.
- **Spielstart-Karte** (Einstellungen → Im Spiel → Spielstart, an): Wie bei Switch und PS5 füllt
  beim Start das Bild des Spiels den Schirm (in 0,14 s eingeblendet), in der Mitte sein Logo mit
  weichem Hof (sonst der Titel, groß gesetzt), unten eine feine schimmernde Leiste und klein, was
  passiert: „Wird gestartet …“, System bzw. Laden, „Steam überprüft Dateien …“, „Steam lädt ein
  Update · 42 %“ (dann als Balken; gelesen aus Steams appmanifest). Das Bild driftet sehr langsam
  (Ken Burns, nur ein Shaderwert), Farbgebung und Vignette kommen aus den Farben des Bilds. Ist das
  Spiel vorn, blendet die Karte in 0,3 s auf Schwarz und Uzai gibt ab; nach dem Spiel kommt sie
  kurz mit „Zurück in Uzai“ und blendet über der Startseite aus. Nie pixelig: Bilder werden in
  Bildschirmpunkten geladen (4K doppelt), höchstens 12 % hochgezogen, Logo und Hülle Punkt auf
  Punkt (nie über ihre eigene Größe). Reicht der Hero nicht für den ganzen Schirm, steht er scharf
  in der Mitte und läuft weich in sich aus; reicht er auch dafür nicht (oder es gibt nur die
  Hülle, z. B. bei Emulator-Spielen), kommt die Hülle scharf in die Mitte vor einen
  weichgezeichneten Grund. Ohne Bilder: ruhiges Licht in der Farbe des Systems und der Titel.
  `logs\launch.log` zeigt, wann welches Fenster vorn lag.
- **PS1/PS2-Disc einlegen:** Liegt eine PlayStation- oder PS2-Disc im Laufwerk, steht sie ganz vorn
  auf der Startseite. Ist das Spiel schon als Abbild in der Bibliothek, öffnet A wie bei jedem Spiel
  die Spielseite, und „Spielen“ startet das Abbild (schneller und leiser als das Laufwerk). Ohne
  Abbild spielt A die Disc direkt vom Laufwerk, mit DuckStation (PS1) oder PCSX2 (PS2); Uzai kopiert
  dabei nichts und legt nichts an. Erkannt wird über die Seriennummer der Disc
  (z. B. `SLES-50330`). Am einfachsten steht sie im Dateinamen (`SLES-50330 Spielname.cue`), sonst
  liest Uzai sie beim Einlesen aus `.iso`, `.bin`/`.cue` und `.img`. `.chd`, `.cso` und `.pbp`
  werden über den Dateinamen erkannt: mit Nummer darin oder mit dem Redump-Namen
  (`Ico (Europe) (En,Fr,De,Es,It).chd`). Dafür lädt Uzai einmal die Redump-Listen aus der
  libretro-database (je System rund 4 MB, danach aus dem Cache, alle 90 Tage frisch). Steckt eine
  Disc aus einer anderen Region im Laufwerk (Disc aus Europa, Abbild aus den USA), findet Uzai das
  Abbild über den Titel. Im Spieltitel erscheint die Nummer nicht.
  Gibt es kein passendes Abbild, steht die Disc mit Namen und Cover vorn. Kann der eingerichtete
  Emulator nicht direkt vom Laufwerk spielen, öffnet A **Abbild zuordnen** (Uzai merkt sich die Wahl).
  In den Optionen eines PS1/PS2-Spiels lässt sich die eingelegte Disc ebenfalls zuordnen oder eine
  Zuordnung lösen.

### Emulatoren
Unter **Emulatoren** bei jedem Emulator den Pfad zur `.exe` setzen. Es gibt Vorlagen für 34
Emulatoren, darunter PCSX2, DuckStation, Dolphin, mGBA, SkyEmu, VBA-M, NanoBoyAdvance,
**Eden, Citron, Sudachi, yuzu-Ableger, Ryubing**, Azahar, Lime3DS, Citra, Cemu, RPCS3,
PPSSPP, melonDS, DeSmuME, Flycast, Redream, xemu, Cxbx-Reloaded, Xenia, RetroArch, BizHawk,
ares, Mesen, Mednafen, Snes9x, Project64 und simple64. Alle Vorlagen starten das Spiel direkt im
Vollbild, ohne die Spieleliste des Emulators.

- **Eigenen Emulator hinzufügen:** leer oder als Kopie einer Vorlage, dann Programmdatei,
  Systeme, Startparameter und Tastenkürzel einstellen. *Standard für …* macht ihn zum Emulator
  eines Systems; pro Spiel geht auch ein anderer (Spiel-Optionen).
- Platzhalter in den Startparametern: `{rom}` Spieldatei, `{rom_dir}` ihr Ordner, `{rom_name}`
  Name ohne Endung, `{title}` Spieltitel, `{core}` RetroArch-Kern, `{emudir}` Ordner des Emulators.

### Bildfilter (ShaderGlass)
Unter **Bildfilter** den Pfad zu `ShaderGlass.exe` setzen. Uzai legt den Filter beim Spielstart
automatisch über das Emulatorfenster.

- **PS2 / GameCube:** „Röhre 480p“ – crt-guest-advanced-hd mit deinen Werten
  (Internal Resolution 4.5, Interlacing 500, Pixel Size ×1).
- **PS1:** „Röhre RGB“ mit Pixel Size ×9.
- Eigene `.sgp`-Profile aus ShaderGlass gehen auch: im Filter als Datei hinterlegen, dann nimmt
  Uzai genau diese Datei.

### Konten
**Nötig ist nichts.** Steam-, Epic- und PC-Spiele findet Uzai von selbst, und welche Musik gerade
läuft, zeigt es über die Mediensitzung von Windows an (jede Musik-App, mit Cover). Für Freunde,
Profile, Erfolge, Wunschliste, Warenkorb und Chat reicht eine Anmeldung: **Mit Steam anmelden**
(QR-Code mit der Steam-App scannen). Alles in der Tabelle unten ist freiwillig.

| Konto | Wofür | Wo man den Schlüssel bekommt |
|---|---|---|
| RetroAchievements | Erfolge für Emulatorspiele | retroachievements.org → Einstellungen → *Web API Key* |
| Epic Games (inoffiziell) | Alle gekauften Epic-Spiele, auch nicht installierte | Einstellungen → Konten → *Epic Games* → *Mit Epic anmelden*: QR-Code scannen, auf Epics Seite anmelden, angezeigten Code an Uzai senden. Anmeldung wie Heroic/Legendary – nicht offiziell von Epic unterstützt (siehe *Spiele*). |
| Twitch (inoffiziell, freiwillig) | Streams: deine gefolgten Kanäle, die gerade live sind | Einstellungen → Konten → *Twitch* → *Mit Twitch anmelden*: QR-Code scannen, Code auf twitch.tv/activate bestätigen. Wie die Twitch-App am Fernseher; offiziell mit eigener Client-ID von dev.twitch.tv |
| Steam (empfohlen) | Freunde, Profile, Erfolge, Spielzeit, Wunschliste, Warenkorb, Chat mit ganzem Verlauf | Einstellungen → Konten → *Mit Steam anmelden*: QR-Code mit der Steam-App (Steam Guard) scannen und bestätigen. Kein Passwort, kein Schlüssel; Uzai erneuert den Zugang selbst. Wer lieber einen Web-API-Schlüssel nimmt (steamcommunity.com/dev/apikey), kann ihn weiterhin eintragen. |
| Spotify wie die Spotify-App (**inoffiziell**, nur auf ausdrücklichen Wunsch) | Wie unten, dazu deine echten Mixe (Mix der Woche, Release Radar, Daily Mixes …) und fremde Playlists mit allen Titeln, Suche mit 20 Treffern | Einstellungen → Konten → Spotify → *Wie die Spotify-App anmelden*: Vor dem ersten Mal erklärt Uzai, dass dieser Weg inoffiziell ist, und fragt nach (*Trotzdem so anmelden*). Dann QR-Code scannen oder spotify.com/pair öffnen, Code eingeben, bestätigen – keine eigene Client-ID, am PC öffnet sich nichts (geht der Code nicht: *Im Browser am PC*). Uzai meldet sich dabei wie librespot/ncspot mit der öffentlichen Kennung der Spotify-Desktop-App an und liest deine Mixe über dieselben internen Wege wie die Spotify-App selbst (api-partner/„Startseite“, mit einem Client-Token wie die echten Clients). Spotify bremst seit Ende 2025 die **alte** öffentliche Web-Schnittstelle (api.spotify.com) für diese Kennung dauerhaft; Mixe, Playlists, Lieblingssongs, Suche, Top-Titel, Zuletzt gehört, Alben und Künstlerseiten gehen deshalb über die internen Wege, die den Schlüssel weiter annehmen. Abspielen (Playlist, Mix, Titel), Pause, Weiter, Zurück, Spulen, Zufall, Wiederholen, Lautstärke und die Warteschlange steuert Uzai über **Spotify Connect** an der Spotify-App auf diesem PC – sie bleibt dabei im Hintergrund. Ist Spotify nirgends offen, startet Uzai es minimiert ohne Fokus bzw. bittet ruhig, es einmal zu öffnen; geht Spotify Connect gar nicht, schalten Abspielen/Pause/Weiter über die Medientasten von Windows. Das ist **nicht offiziell von Spotify unterstützt, verstößt gegen Spotifys Nutzungsbedingungen** und kann jederzeit aufhören zu gehen. Dann fällt Uzai von selbst auf die eigene Spotify-App zurück (falls eingerichtet) oder bittet ruhig um eine neue Anmeldung – ohne Anfrage-Flut: bremst Spotify (429), wartet Uzai die angegebene Zeit ab. Welcher Weg die Mixe gefunden hat, steht in `logs\spotify.log`. Gespeichert wird nur die Erneuerungs-Anmeldung (`accounts.spotify_app_refresh`); deine eigene Spotify-App (unten) löscht Uzai nie von selbst – nur du über *Eigene App trennen*. Nur „Alle Titel“ eines Künstlers fragt noch die Web-API (bzw. die eigene Spotify-App). |
| Spotify mit eigener App (offiziell, empfohlen; für *Für dich*, Playlists und Steuerung; *Verbindung prüfen* zeigt, was Spotify ablehnt) | Musik: Für dich, läuft gerade, Als Nächstes, Playlists und Alben mit allen Titeln, Lieblingssongs, Zuletzt gehört, Suche | developer.spotify.com → App anlegen. Seit 2026 braucht dein Konto dafür **Premium**, und eine App im Entwicklungsmodus erlaubt höchstens fünf eingetragene Nutzer. Redirect-URI `http://127.0.0.1:8888/callback` eintragen, dich unter *User Management* hinzufügen und die Client-ID in Uzai eintragen. Die Freigabe öffnet einmal den Browser; danach holt sich Uzai selbst wieder nach vorn. Wer schon mit 0.6 oder älter verbunden war: einmal *Neu anmelden*, sonst fehlen Top-Titel und Künstler für *Für dich*. |
| Discord (Server) | Server-Tabs mit Freunden online, „Spielt gerade“ | Server-Einstellungen → *Widget* aktivieren, Server-ID eintragen |
| Discord (Status) | „Spielt <Titel>“ mit Cover, Laden oder System („PlayStation 2 · Uzai“) und Spielzeit – auch bei Emulator-, Epic-, EA- und PC-Spielen; je Spiel ausblendbar (Spieloptionen → *Im Discord-Status zeigen*). Das Cover lädt Discord über seine öffentliche Adresse (Steam, Epic, SteamGridDB, Libretro); eigene Bilder verlassen den PC nie. Einen Beitreten-Knopf gibt es nicht: Knöpfe im Status öffnen nur Webadressen, und Discords „Beitreten“ erreicht nur Freunde mit derselben Discord-App | discord.com/developers → eigene App anlegen, *Application ID* in Uzai eintragen (dieselbe App wie für den Sprachkanal) |
| Discord (Sprachkanal im Guide) | Wer im Kanal ist und spricht, stummschalten, Lautstärke, Mikro, Ton, Kanal wechseln | discord.com/developers → eigene App anlegen (dieselbe wie für den Status): *Application ID* und unter OAuth2 das *Client Secret* in Uzai eintragen (32 Zeichen – **nicht** den Bot-Token, einen Bot braucht Uzai nicht), unter OAuth2 → Redirects `http://localhost` hinzufügen. Dann *Mit Discord verbinden* und in der Discord-App einmal auf „Autorisieren“ klicken. Die App muss dir gehören – Discord lässt die Sprachsteuerung nur für den Besitzer der App (und eingetragene Tester) zu; darum geht sie mit Uzais eingebauter Discord-App nur beim Projektinhaber und seinen Testern, und Uzai sagt das, wenn die Freigabe scheitert. Klappt es nicht, steht unter Einstellungen → Konten, was Discord geantwortet hat; Einzelheiten in `logs\discord.log` im Datenordner. |
| SteamGridDB | Cover, Hintergründe, Logos, Symbole – automatisch und zum Aussuchen | steamgriddb.com → Einstellungen → *API* |

**Lange Schlüssel nicht mit dem Controller tippen:** Auf der Bildschirmtastatur gibt es
**Handy** – QR-Code scannen, auf dem Handy einfügen, senden, fertig (Handy und PC im selben
WLAN; beim ersten Mal fragt die Windows-Firewall). Die Handy-Seite hat bei Schlüsseln gleich
einen Link „Schlüssel holen“. **Einfügen** nimmt die Zwischenablage des PCs.

Ohne Spotify-Konto steuert Uzai die Musik über die Medientasten von Windows (geht mit jedem Player).

### Mitteilungen (Nachrichten als Pop-up)
Neue Direktnachrichten erscheinen sofort oben rechts, mit Name, Profilbild und Text – auch
während ein Spiel läuft. Einstellen unter **System → Mitteilungen** (Steam-Nachrichten,
Discord-Benachrichtigungen, Pop-ups im Spiel, Ton).

- **Steam:** Mit *Mit Steam anmelden* (QR-Code, Steam-App) hält Uzai die Verbindung zu Steam
  offen und bekommt Nachrichten und „schreibt gerade“ in Echtzeit. Steam liefert Nachrichten
  nur an Sitzungen mit Status; Uzai meldet dafür genau den Status, den du in Steam schon hast
  (online, abwesend …), ohne Vorrang – für Freunde ändert sich nichts. Bist du offline oder
  unsichtbar, setzt Uzai keinen Status und schaut alle 15 Sekunden nach. Ohne diese Anmeldung
  ebenso. Keine Pop-ups für eigene Nachrichten oder den Chat, der gerade offen ist.
- **Discord:** Direktnachrichten und Erwähnungen aus der Discord-App, über dieselbe Verbindung
  wie der Sprachkanal (siehe *Konten*). Wer schon verbunden war, verbindet einmal neu
  (Einstellungen zeigen *Neu verbinden*). Lässt Discord das Recht für deine App nicht zu, geht
  der Sprachkanal trotzdem weiter.
- **Öffnen:** In Uzai öffnet **View** (⧉, Tastatur V) das Pop-up: bei Steam den Chat, bei
  Discord die Mitteilungen. Im Spiel öffnet die **Guide-Taste** kurz nach dem Pop-up den Guide
  gleich beim Chat.
- **Nicht stören** (Schnellmenü-Kachel, Guide → System → Mehr; bei Filmen von selbst, abschaltbar):
  Nachrichten, Discord, Freundschaftsanfragen und Angebote kommen still in die Mitteilungen (Punkt an
  der Glocke); Anrufe und Erfolge kommen weiter. In der Liste entfernt **Y** alle (mit Rückgängig).
- **Melden, wenn online:** im Menü eines Steam-Freunds (A); kommt er online oder startet ein Spiel,
  kommt eine leise Mitteilung, die in den Chat führt.
- **Im Spiel** erscheint das Pop-up in einem eigenen kleinen Fenster, das nie den Fokus nimmt
  (das Spiel läuft und reagiert weiter, Uzai bleibt im Hintergrund) und nicht in Aufnahmen
  auftaucht. Spiele im **exklusiven Vollbild** lassen kein Fenster darüber zu – dort im Spiel
  *Randloses Fenster* (Borderless) wählen.

### Erfolgs-Pop-ups und Uzai-Punkte
Schaltest du im Spiel einen Erfolg frei, erscheint unten in der Mitte Uzais eigenes Pop-up: ein
runder Knopf mit Pokal springt auf, ein Lichtring läuft aus, der Kreis öffnet sich zur
Glas-Pille mit „Erfolg freigeschaltet“, dem Namen und den **Uzai-Punkten**, die hochzählen; das
Bild des Erfolgs blendet in den Kreis, dazu ein eigener heller Glockenklang. Mehrere kommen
nacheinander (je mehr warten, desto kürzer). Einstellen unter **Einstellungen → Mitteilungen →
Erfolge** (an/aus, unten oder oben, Ton, Seltene hervorheben, RetroAchievements); dort zeigen
*Test-Pop-up zeigen*, *Seltenes Test-Pop-up* und *Retro-Test-Pop-up*, wie es aussieht und klingt.

- **Steam:** sofort. Steam schreibt bei jeder Freischaltung seinen Zwischenspeicher
  `Steam\appcache\stats\UserGameStats_<Konto>_<App-ID>.bin` neu; Uzai schaut alle 1,5 s nur auf
  dessen Änderungszeit und liest dann die Erfolge daraus (ohne Netz, ohne API-Schlüssel). Mit
  Steam-Konto in Uzai zusätzlich alle 30 s über die Web-API (Rückfall), dazu deutsche Namen,
  Bilder und Seltenheit. Steam zeigt bei Steam-Spielen außerdem sein eigenes Pop-up unten rechts –
  das lässt sich nur in Steam abschalten (Steam → Einstellungen → Benachrichtigungen).
- **RetroAchievements** (Emulator-Spiele, Konto unter *Konten*): alle 12 s, als eigene Retro-Art
  (Bernstein, Pixel-Pokal, RA-Punkte, Hardcore).
- **Uzai-Punkte** nach Seltenheit wie ein Gamerscore: ab 50 % der Spieler 10, ab 20 % 20, ab
  10 % 30, ab 5 % 50, ab 1 % 75, darunter 100 (unbekannt 20, RetroAchievements aus den
  RA-Punkten). Seltene Erfolge (unter 10 %) bekommen Gold und einen Schimmer und zeigen den
  Anteil („Seltener Erfolg · 3,2 % der Spieler“), unter 1 % Platin.
- **Profil:** „Zuletzt freigeschaltet“ mit der Summe und dem Spiel mit den meisten Punkten; die
  Erfolge eines Spiels zeigen „x von y Uzai-Punkten“. Gespeichert in `unlocks.json` im
  Datenordner. Alte Erfolge geben nie ein Pop-up, keiner kommt doppelt.

### Profil-Level und Abzeichen
Aus den Uzai-Punkten aller Plattformen wird ein **Uzai-Level** (1 bis ohne Ende):
- **Punkte:** jeder Erfolg nach Seltenheit (wie oben, 10–100), jede Spielstunde 2 Punkte, jede
  Abzeichen-Stufe 25/50/100/250 (Bronze/Silber/Gold/Platin). Auch was vor Uzai freigeschaltet
  wurde, zählt: Spiele, deren Erfolgsliste Uzai kennt (Spielseiten, seltenste Erfolge, Uzais
  Pop-ups), genau nach Seltenheit, alle übrigen freigeschalteten Erfolge (Steam-Zählung über die
  Bibliothek, RetroAchievements) mit 20 Punkten – so ist das Level schon am ersten Tag nicht null.
- **Level:** Level 2 braucht 200 Punkte, jeder weitere Schritt rund 10 % mehr, ab Level 36
  gleichbleibend 6.000. Steht rechts im Profil-Banner (Ring, Balken, „Noch 120 Punkte bis
  Level 13“, das Steam-Level als Chip daneben), als „Lv 20“ oben neben dem Profilbild (Maus darüber:
  Punkte bis zum nächsten), auf deiner Karte im Guide (*Freunde*) und in *Dein Status*.
- **Abzeichen** (31, je vier Stufen, eigene Medaillen, scharf auf 4K): Spielzeit
  je Plattform (PS1, PS2, GameCube, Wii, N64, 8/16 Bit, Switch, Handhelds, Steam, PC: 10/50/100/500
  Std., insgesamt 50–5.000), Erfolge (erster/10/100/1.000, seltene unter 10 %, unter 1 %, Erfolge
  in vielen Spielen), Komplett (Spiele zu 100 %, durchgespielt), Vielfalt (Plattformen, gespielte
  Spiele, Konsolen im Emulator), Gemeinsam (Spiele mit Freunden – ein Steam-Freund spielt dasselbe
  oder Remote Play –, Remote-Play-Sitzungen, Bildschirmfotos und Clips), Treue (Tage in Folge,
  Spieltage, längste Sitzung, Nachteule, Uzai-Level) und Retro (RetroAchievements, Hardcore,
  gemeistert). Plattformen ohne Spiele und Retro ohne RA-Konto bleiben ausgeblendet, bis du sie
  hast. Genres fehlen: Uzai kennt die Genres deiner Spiele nicht.
- **Echte Konsolen-Logos (Startseite und Spielzeit-Abzeichen):** Die Quellen-Zeile der Startseite
  (PS1–PS5, PSP, Vita, GameCube, Wii, Wii U, Switch, N64, SNES, NES, Game Boy, GBA, DS, 3DS, Mega
  Drive, Saturn, Dreamcast, Xbox, Steam, Epic, GOG, EA, Ubisoft, Battle.net, itch.io, Amazon, Riot)
  zeigt das Logo einfarbig in der Farbe der Schrift und in einheitlicher Höhe; ohne Logo den Namen.
  In der Medaille steht das echte Logo der
  Plattform (PlayStation, PS2, GameCube, Wii, N64, Switch, Steam, Windows; 8/16 Bit und Handhelds
  zeigen das System, das du dort am meisten spielst – z. B. Mega Drive, PSP oder Game Boy Advance –,
  sonst SNES bzw. Game Boy Advance), einfarbig im Metall der Stufe eingeprägt, gesperrt grau.
  **Die Logos sind nicht Teil des Repositorys und nicht des Builds:** Uzai lädt sie zur Laufzeit für
  den privaten Gebrauch von Wikimedia Commons (PNG-Render 960 Punkte breit; passt kein bekannter
  Dateiname, einmal eine Suche nach „<Name> logo“ auf Commons) und legt sie im Datenordner unter
  `cache/logos` ab (`index.json` merkt sich Quelle und Fehlschläge). Abschalten: Einstellungen →
  Spiele → Mehr → Bilder → *Echte Konsolen-Logos (aus dem Netz, privat)* (Standard: an). Ohne Netz oder wenn nichts
  gefunden wird, bleibt der Kurzname („PS2“) bzw. das Zeichen. Eigene Logos gewinnen immer:
  `<Medienordner>\logos\<name>.png|svg|webp|jpg` mit dem Namen der Gruppe (`ps1`, `ps2`, `gc`,
  `wii`, `n64`, `16bit`, `switch`, `handheld`, `steam`, `pc`) oder des Systems (`megadrive`,
  `psp`, `nds`, `epic`, `windows` …) – auch, wenn das Laden aus ist.
- **Im Profil** die Reihe *Abzeichen* (zuletzt verdiente, dann die, die am nächsten dran sind,
  mit Fortschritt wie „37/50 Stunden“) und *Alle Abzeichen*: Kopf mit Level und woher die Punkte
  kommen, darunter das Raster nach Kategorien (LB/RB springt), rechts das gewählte Abzeichen mit
  allen vier Stufen, Datum und was noch fehlt.
- **Pop-ups** in der Glas-Pille der Erfolge, mit Medaille bzw. Level-Ring; zum Level eine kurze
  Fanfare. Nicht aufdringlich: Beim ersten Start gibt es für schon verdiente Abzeichen nur einmal
  „Du hast 14 Abzeichen freigeschaltet“; was beim Start nachgeladen wird oder seit dem letzten Mal
  dazukam, kommt als eine Zusammenfassung; im Spiel warten sie bis danach; mehr als zwei auf einmal
  werden zusammengefasst. Alles steht auch in den Mitteilungen. Gespeichert in `badges.json`
  (Stufen mit Datum, Höchststände – nichts geht verloren, wenn Daten fehlen).

### Videos (YouTube ohne Werbung)
Beim ersten Öffnen von **Videos** auf *Jetzt einrichten* drücken. Uzai lädt drei freie Programme
in seinen Datenordner (zusammen etwa 150 MB):

- **yt-dlp** holt die Videos. Uzai hält es alle drei Tage selbst aktuell.
- **Deno** hilft yt-dlp, damit alle Qualitätsstufen funktionieren.
- **mpv** spielt ab. Uzai legt seine eigene Leiste darüber, man sieht nichts von mpv.

Geladen wird nur über https und nur mit der Prüfsumme des Herausgebers (yt-dlp: `SHA2-256SUMS`,
Deno: `.sha256sum`, mpv: die SHA-256, die GitHub zum Paket nennt). Passt sie nicht oder fehlt sie,
installiert Uzai nichts und sagt es.

Weil dabei nie die YouTube-Seite geladen wird, gibt es keine Werbung. Gesponserte Abschnitte
überspringt Uzai mit **SponsorBlock** (Standard: nur Sponsoren; weitere Kategorien unter
Einstellungen → Medien → *Abschnitte überspringen*). Uzai fragt dabei nur mit den ersten vier
Zeichen eines SHA-256-Prüfwerts der Video-ID, merkt sich die Antwort einige Stunden, prüft sie
streng (nur Zahlen in sinnvollen Grenzen) und meldet selbst nie etwas. Nach dem Sprung steht kurz
*„Sponsoren übersprungen · links: zurück“* da. Die Daten stehen unter CC BY-NC-SA 4.0.

**Nur Ton im Hintergrund:** Bei *Nur Ton* legt **Start/≡** (oder *Optionen → Im Hintergrund
weiterhören*) das Video in den Hintergrund: Der Player geht zu, der Ton läuft wie Musik weiter,
oben in der Kopfleiste steht, was läuft. Gesteuert wird im Guide, Reiter **Video-Ton** (Pause,
±10 s, voriges/nächstes, Lautstärke mit LT/RT, *Mit Bild* zurück in den Player). Am Ende geht es
mit dem nächsten Video der Liste weiter; ein Spielstart beendet den Ton. Direkt so starten geht
über Y auf einem Video → *Im Hintergrund hören*.

**Shorts:** Der Reiter *Shorts* zeigt die Hochkant-Videos deiner Abos als hohe Karten, neueste
zuerst. Sie kommen über denselben öffentlichen RSS-Weg wie die neuen Videos (die Shorts-Liste
jedes Kanals) und werden erst geholt, wenn du den Reiter öffnest. In den übrigen Reihen bleiben
sie mit *Shorts ausblenden* draußen; den Reiter selbst schaltet *Reiter „Shorts“* ab.

Ohne Anmeldung kannst du Kanäle direkt in Uzai abonnieren (Y auf einem Video → *Kanal
abonnieren*). Mit **Google-Anmeldung per QR-Code** übernimmt Uzai deine Abos, Playlists,
„Mag ich“ und zeigt, was gerade angesagt ist. Dafür braucht es einmalig einen eigenen,
kostenlosen Google-Zugang; die Anmelde-Ebene in Uzai erklärt die Schritte:

1. console.cloud.google.com → neues Projekt „Uzai“
2. *APIs und Dienste → Bibliothek* → „YouTube Data API v3“ aktivieren
3. *OAuth-Zustimmungsbildschirm*: extern, App-Name, eigene E-Mail. Danach **App
   veröffentlichen**, sonst läuft die Anmeldung nach 7 Tagen ab. Google zeigt beim Anmelden
   „nicht überprüfte App“ – das ist bei eigenen Zugängen normal (*Erweitert → Weiter*).
4. *Anmeldedaten → OAuth-Client-ID* → Typ **Fernseher und Geräte mit begrenzter Eingabe**
5. JSON-Datei laden und in Uzai auswählen (oder Client-ID und Schlüssel eintippen)

Uzai fragt nur Leserechte an (Abos, Playlists, „Mag ich“) und postet nie etwas.

**Für dich** ist die Startseite wie bei YouTube. Echte YouTube-Empfehlungen holt yt-dlp mit der
Anmeldung aus deinem Browser (Einstellungen → Videos → *Empfehlungen von YouTube*: am besten
Firefox, oder eine `cookies.txt`). Ohne das mischt Uzai selbst: Neues der Kanäle, die du am
meisten schaust (auch ohne Abo), Neues aus den Abos und Angesagtes; Gesehenes fällt raus.

**Startseite wie auf dem Fernseher (inoffiziell, auf Wunsch).** Die offizielle Schnittstelle
(YouTube Data API v3) gibt die persönliche Startseite nicht heraus – darum kämen ohne Browser-Cookies
nur Abos und Uzais Mischung. Unter Einstellungen → Konten → YouTube gibt es deshalb zusätzlich die
*Anmeldung wie YouTube auf dem Fernseher (SmartTube-Weg) – nicht offiziell von Google unterstützt*:
QR-Code scannen oder `youtube.com/activate` (bzw. `google.com/device`) öffnen und den angezeigten
Code eingeben – ohne eigenen Google-Zugang. Uzai meldet sich dabei wie die YouTube-App auf
Fernsehern an (Geräte-Anmeldung mit der öffentlichen Kennung der TV-App, die Uzai wie SmartTube aus
`youtube.com/tv` liest) und holt dann über YouTubes interne Schnittstelle (InnerTube, Client
`TVHTML5`):

- **Videos → Startseite**: die echten Reihen von YouTube („Für dich“, Themenreihen wie *Gaming*,
  *Musik* …) mit Titel, Kanal, Vorschaubild, Länge, Aufrufen, Alter und LIVE-Abzeichen; beim
  Blättern nach unten kommen weitere Reihen nach. Darunter wie bisher *Weiterschauen*, *Neu von
  deinen Abos*, *Angesagt* und die Merkliste; die Abos bleiben unter *Neu* und *Abos*.
- **Empfohlen im Player**: läuft das letzte Video einer Reihe, hängt Uzai YouTubes Vorschläge
  dahinter – Abspann und *Automatisch weiter* zeigen dann, was YouTube als Nächstes empfiehlt.
- **Gesehenes an YouTube melden** (Schalter, Standard aus): gestartete Videos landen auch in
  deinem YouTube-Verlauf.

Gespeichert wird nur die Erneuerungs-Anmeldung (in den Konten-Einstellungen), nie ein Passwort;
nichts davon steht im Protokoll. *Abmelden* widerruft die Anmeldung bei Google und löscht die
Startseite. Weil Google diesen Weg nicht offiziell anbietet, kann er jederzeit brechen: Ist YouTube
nicht erreichbar oder antwortet anders als erwartet, zeigt Uzai still deine Abos und die eigene
Mischung (mit einem kleinen Hinweis über der ersten Reihe); die offizielle Google-Anmeldung oben
bleibt davon unberührt und funktioniert weiter.

**Anzeige:** Das Video liegt vorn (mpv), und mpv zeichnet Uzais Leiste selbst: Kanal, Titel,
*Als Nächstes*, Fortschritt mit SponsorBlock-Abschnitten, Tasten, Uhr und Endkarte, in Uzais Schrift.
Das klappt auf jedem PC, denn kein Fenster muss durchsichtig sein. Öffnest du Optionen, pausiert
das Video, und Uzai kommt kurz davor; danach läuft es weiter. Der Guide hält das Video nicht an –
angehalten wird nur mit *Pause* (im Player A, im Guide im Reiter *Video*). Die Leiste in mpv
spricht die Sprache der Oberfläche. Die alte Art (Uzai
als durchsichtiges Fenster über mpv) gibt es noch unter Einstellungen → Videos → *Anzeige* →
*Uzai darüber*. Auf manchen PCs bleibt das Bild damit aber schwarz.

### Bild in Bild (Video beim Spielen)
Im Player **Start/≡** (Tastatur M) oder *Optionen → Bild in Bild*: Das Video – YouTube, Filme und
Streams, alles, was über mpv läuft – schrumpft weich in eine Ecke (Standard unten rechts, 28 % der
Bildschirmbreite, 16:9) und läuft weiter. Dahinter steht Uzai wieder dort, wo du vor dem Video
warst; startest du jetzt ein Spiel, liegt das kleine Bild über dem Spiel. Es nimmt dem Spiel nie
den Fokus, steht nicht in Taskleiste und Alt+Tab, hat unter Windows 11 runde Ecken und lässt sich
mit der Maus ziehen.

Gesteuert wird über den **Guide**: Solange Bild in Bild läuft, öffnet die Guide-Taste ihn gleich im
Reiter **Bild in Bild** (erster Reiter, wie *Video* beim Vollbild). Vorn steht *Vollbild* (schon
gewählt, ein Druck auf A holt das Video zurück in den Player; nur ohne laufendes Spiel, dort steht
*Pause* vorn), dann *Pause* und *Schließen*. Darunter ±10 s, *Verschieben* (der Guide tritt zurück,
linker Stick oder Steuerkreuz schiebt das Bild weich über den Bildschirm, LT/RT ändern die Größe,
A lässt es dort – nah am Rand rastet es ein –, B setzt es zurück), *Größe* (Klein/Mittel/Groß),
*Deckkraft* (100/85/70 %), die vier Ecken und die Lautstärke mit **LT/RT**. Freunde, Chat und der
Rest des Guides liegen einen Reiter weiter (RB). Verkleinern ändert den Ton nicht: Bild in Bild ist
so laut wie im Vollbild; eine eigene Stufe gibt es unter Einstellungen → Videos → *Mehr zu Videos*
→ *Eigene Lautstärke für Bild in Bild* (anfangs aus). Lage, Größe und Deckkraft merkt sich Uzai.
Im Reiter *Spiel* startet *Bild in Bild* ein Video aus *Weiterschauen* gleich klein in der Ecke,
ohne das Spiel zu verlassen. Wählst du in Uzai ein anderes Video oder einen anderen Stream, ersetzt
er das kleine Bild und startet wie sonst groß im Player.

Bild in Bild liegt nur über Uzai und dem Spiel, das du aus Uzai gestartet hast. Holst du ein anderes
Programm oder den Desktop nach vorn (Alt+Tab), versteckt es sich und kommt zurück, sobald Uzai oder
das Spiel wieder vorn ist. Solange der Guide offen ist, liegt das Bild unter ihm (über dem Spiel scheint es gedimmt durch).
Ein beendetes Spiel lässt das Bild stehen; im Ruhemodus ist es versteckt und angehalten,
Ausschalten schließt es. Mit mehreren Bildschirmen zieht es auf den des Spiels. Clips und
Bildschirmfotos zeigen den Bildschirm, wie du ihn siehst, also samt Bild in Bild. Ein Spiel im
**exklusiven Vollbild** kann kein Fenster überdecken; erkennt Uzai das, rät es ruhig: *Spiel im
Vollbild-Fenster (randlos) starten, damit Bild in Bild sichtbar ist.*

### Streams (Twitch)
Der Bereich **Streams** zeigt Twitch wie die Videos: oben groß der Stream, auf dem du stehst
(Kategorie, Zuschauer, seit wann live), darunter *Live – Gefolgt*, *Weiterschauen* (angefangene
Übertragungen), *Beliebt auf Deutsch*, *Kategorien* und *Beliebt weltweit*. Dazu die Seiten
*Gefolgt*, *Kategorien* (Spielhüllen im Raster) und *Suche* (Kanäle, Live-Streams, Kategorien).
A auf einem Kanal öffnet seine Seite mit *Jetzt live*, den letzten Übertragungen und Clips.
Abgespielt wird wie YouTube über **mpv und yt-dlp** – kein Browser, Uzai bleibt vorn, Lautstärke
mit ↑/↓, Qualität unter Y → *Qualität*, LB/RB schalten zum vorigen/nächsten Stream der Reihe.
Live-Streams lassen sich nicht spulen (die Leiste zeigt *LIVE*). Ohne Einrichtung von Videos
(yt-dlp, mpv) geht es nicht – *Videos → Jetzt einrichten* reicht für beides.

**Ohne Anmeldung** gehen beliebte Streams, Kategorien, Suche und Kanalseiten. Für deine gefolgten
Kanäle: *Mit Twitch anmelden* (Streams → Gefolgt oder Einstellungen → Konten → Twitch) – QR-Code
mit dem Handy scannen oder twitch.tv/activate öffnen, Code prüfen, *Aktivieren* tippen.

> **Inoffiziell:** Uzai meldet sich dabei wie die Twitch-App am Fernseher an (deren öffentliche
> Kennung, wie Xtra und Twitch-Channel-Points-Miner) und liest über Twitchs interne Schnittstelle
> (GQL, wie yt-dlp und streamlink). Das verstößt vermutlich gegen Twitchs Regeln für Entwickler;
> Twitch kann es jederzeit abstellen. Gespeichert wird nur die Anmeldung, nie dein Passwort.
> **Offiziell** geht es mit einer eigenen Client-ID: auf dev.twitch.tv/console eine App anlegen
> (Client-Typ *Öffentlich*, Redirect `http://localhost`), unter Einstellungen → Konten → Twitch →
> *Eigene Client-ID* eintragen und neu anmelden – dann kommt *Gefolgt* über Twitchs offizielle
> Schnittstelle (Helix).

Was geklappt hat und was nicht (welche Kennung, welcher Weg, Ablauf der Anmeldung), steht ohne
Anmeldedaten in `logs/twitch.log` im Datenordner.

### Filme (Addons wie Stremio/Nuvio)
Uzai ist hier nur der Client, ähnlich wie Stremio oder Nuvio TV: Kataloge, Details, Streams und
Untertitel kommen aus **Addons**, die du selbst einträgst. Vorinstalliert ist nur **Cinemeta**
(Kataloge und Details, ohne Schlüssel). Uzai bringt keine Quellen mit und schlägt keine vor. Was du einträgst, entscheidest und
verantwortest du selbst: Nutze nur Angebote, die du rechtmäßig nutzen darfst.

- **Addon eintragen:** Einstellungen → Filme → *Addon hinzufügen* und die Adresse des Addons
  (endet auf `manifest.json`, `stremio://…` geht auch) eingeben – am bequemsten über die
  **Handy**-Eingabe (QR-Code) oder *Einfügen*. Muss ein Addon erst eingerichtet werden, öffnest du
  seine Seite `…/configure`, richtest es dort ein und trägst die fertige Adresse ein. Die Reihenfolge
  zählt: weiter oben = Kataloge zuerst, Details zuerst von dort.
- **Kein P2P:** Streams per Torrent (infoHash) blendet Uzai aus (Einstellungen → Filme → *Kein
  P2P*, an). Abgespielt werden nur direkte Adressen über **mpv** – dasselbe mpv wie bei Videos,
  also zuerst unter Videos *Jetzt einrichten*. Kopfzeilen der Addons und deren Untertitel
  reicht Uzai an mpv weiter.
- **Plugins** (JavaScript-Erweiterungen im Nuvio-Format): ein Plugin-Verzeichnis über seine
  Adresse eintragen, einzelne Plugins an- und ausschalten. Auch hier ist nichts voreingestellt. Sie laufen auf deinem PC mit **Deno** (kommt
  beim Einrichten von Videos mit). CloudStream-Plugins sind Android-Programme und laufen unter
  Windows nicht. Meldungen der Plugins stehen in `logs/plugins.log` im Datenordner.
- **Optional:** ein eigener TMDB-Schlüssel (themoviedb.org, kostenlos) bringt deutsche Titel und
  Beschreibungen. Bibliothek, Fortschritt, „gesehen“ und *Weiterschauen* mit *Als Nächstes*
  bleiben lokal (`movies.json`); ab 90 % gilt etwas als gesehen.


#### Nuvio-Konto
Einstellungen → Filme → *Mit Nuvio anmelden*: QR-Code mit dem Handy scannen (öffnet nuvio.tv/link,
wie bei der Nuvio-TV-App) oder E-Mail und Passwort. Danach übernimmt Uzai aus deinem Konto:

- **Profile** (mehrere: unter Einstellungen → Filme wechselbar; Profile, die die Addons/Plugins von
  Profil 1 teilen, bekommen diese),
- **Addons** und **Plugin-Verzeichnisse** genau wie im Konto (CloudStream-Verzeichnisse laufen
  unter Windows nicht und fallen weg),
- **Bibliothek**, **Weiterschauen** (die neuesten 200 Einträge) und **Gesehen**,
- das **Layout der Startseite** aus Nuvio TV: Reihenfolge der Kataloge, ausgeblendete Kataloge,
  eigene Titel, **Sammlungen** (je Ordner eine Reihe an ihrem Platz), die Kataloge fürs große
  Titelbild, Titelbild und Weiterschauen an/aus.

Abgleich beim Start, beim Öffnen von „Filme“ und alle 10 Minuten. Addons, Plugins und Bibliothek
sind wie im Konto; bei Fortschritt und „Gesehen“ gewinnt das Neuere. Was du in Uzai tust
(abspielen, gesehen, merken, Addons ändern), geht sofort zurück ins Konto, sonst später
(Warteschlange übersteht Neustarts). Beim ersten Anmelden lädt Uzai, was es schon hatte, ins Konto.
Grundlage ist Nuvios öffentliche API (api.nuvio.tv) mit dem öffentlichen Schlüssel aus Nuvios
Dokumentation; Uzai speichert nur die Zugangstokens, nie das Passwort. Uzai bleibt im Stil von
Uzai: Nuvios Gestaltung (Classic/Grid/Modern, Farben) übernimmt es nicht, wohl aber die Ordnung.
### Bildfilter und Guide
Solange der Guide offen ist, versteckt Uzai das ShaderGlass-Fenster (es liegt sonst ganz oben und
verdeckt den Guide) und zeigt es danach wieder. Stürzt ShaderGlass ab, läuft das Spiel ohne
Filter weiter; im Guide lässt er sich wieder einschalten. Wird das Bild mit Filter blau oder
flackert der Bildschirm: Windows-HDR ausschalten (ShaderGlass kann kein HDR) und den Emulator
im Fenster oder randlos laufen lassen, nicht im exklusiven Vollbild.

### Aufnahmen (Clips, Aufnahmen, Bildschirmfotos)

Uzai nimmt selbst auf, wie *Aufnahme* bei PS5 und Xbox – ohne Game Bar und ohne ShadowPlay:

- **Clip speichern:** Im Spiel läuft still ein Puffer der letzten 15/30/60/120 Sekunden (Standard
  30 s). Guide → *Clip speichern*, **Guide halten + X** oder die **Share-Taste** (Xbox Series,
  Switch Pro) machen daraus sofort ein MP4 – nichts wird neu kodiert, der Clip ist in einer
  Sekunde fertig. Er endet in dem Augenblick, in dem du die Guide-Taste gedrückt hast; der Guide
  selbst ist nicht darin. Eine Mitteilung mit Vorschaubild erscheint über dem Spiel; *Ansehen*
  (View, im Spiel aus den Mitteilungen im Guide) öffnet den Clip, nach dem Spiel erinnert eine
  Mitteilung an die neuen Clips.
- **Aufnahme starten/beenden:** längere Aufnahme im Guide, höchstens 10 Minuten.
- **Bildschirmfoto** (Y im Guide): mit FFmpeg über die Desktop-Duplizierung, damit auch
  Vollbild-Spiele nicht schwarz werden; ohne FFmpeg wie bisher.
- Auf der **Spielseite** stehen die *Aufnahmen aus diesem Spiel* (neue Clips tragen die Spiel-ID,
  ältere zählen über den Titel).
- **Galerie *Aufnahmen*** (Guide → System, im Spiel Guide → Spiel → Aufnahmen, Einstellungen →
  Aufnahmen, Profil): alle Clips und Bildschirmfotos nach Spielen mit Vorschaubild. A spielt ab
  (Uzais Videoplayer, mpv), X teilt, Y Optionen: *Bearbeiten*, *Umbenennen*, *In den Papierkorb*.
- **Clip bearbeiten** (Y → *Bearbeiten*): Zeitleiste mit Bildstreifen, links/rechts verschiebt den
  gewählten Griff (halten wird schneller), LT/RT um eine Zehntelsekunde, A wechselt zwischen Anfang,
  Ende und – mit *Zeitlupe* 0,5× oder 0,25× – deren Bereich. *Text oben/unten* (Bildschirmtastatur
  oder Handy, eine Zeile, Uzais Schrift), *Ton* aus. X zeigt eine kleine Vorschau des Ergebnisses
  in Uzai (Theora, aus FFmpeg). *Speichern* legt eine neue Datei „… (bearbeitet)“ bzw. nur
  geschnitten „… (gekürzt)“ neben dem Original an – das bleibt immer; mit Fortschritt und
  *Abbrechen*, läuft weiter, wenn der Editor zugeht, nie neben einem Spiel (startet eins, bricht
  es ab). Der eigene Text kommt nie in die Befehlszeile von FFmpeg, sondern als Datei aus Uzais
  Datenordner (drawtext `textfile`, ohne %-Ersetzungen); bearbeitet werden nur Clips direkt im
  Clip-Ordner. Danach *Teilen* aus der Mitteilung über die vorhandenen Wege (Handy, Discord, Steam).
- **Teilen:** *An Handy senden* zeigt einen QR-Code zu Uzais kleiner Seite im Heimnetz (wie bei der
  Eingabe per Handy, 30 Minuten gültig): Das Handy zeigt die Aufnahme, lädt sie herunter, und von
  dort geht sie über „Teilen“ an Discord, WhatsApp, Steam … – wie mit der PlayStation-App. *In
  Discord senden*: *Freund* (Discord-Nachrichten unter Konten verbunden) oder *Server-Kanal*
  (Server und Textkanäle aus der Discord-Verbindung für Sprachkanäle, zuletzt benutzte zuerst, der
  letzte Kanal als schnelle Wahl „Zuletzt: #clips in …“); Uzai legt die Datei in die
  Zwischenablage, öffnet die Direktnachricht bzw. den Kanal in der Discord-App, fügt ein und sendet; Clips
  über der Discord-Grenze (ohne Nitro 10 MB) verkleinert Uzai vorher. Discord kommt dafür kurz
  nach vorn, die Guide-Taste bringt dich zurück. *In Steam-Chat senden* (nur Bildschirmfotos;
  Videos nimmt der Steam-Chat nicht an): Steam öffnet den Chat, Uzai fügt ein, „Hochladen“ mit der
  Controller-Maus. Discords und Steams Schnittstellen können keine Dateien schicken – darum dieser
  Weg über die eigenen Apps. Uzai lädt nichts zu fremden Diensten hoch.

So nimmt Uzai auf: Beim ersten Mal lädt Uzai **FFmpeg** (freie Software, GPL; Build von BtbN über
GitHub, auf ffmpeg.org verlinkt; etwa 190 MB) in seinen Datenordner (`tools\ffmpeg`) und prüft es
gegen die Prüfsummenliste des Builds. FFmpeg greift das Bild über die Desktop-Duplizierung von
Windows ab (`ddagrab`; *Nur das Spielfenster*: Windows.Graphics.Capture), kodiert es auf der
Grafikkarte (NVIDIA NVENC, AMD AMF, Intel Quick Sync, sonst x264) und schreibt 2-Sekunden-Stücke
in einen Ordner, der sich im Kreis überschreibt (`capture\puffer` im Datenordner, je nach Länge
und Qualität 50–300 MB). Den Ton nimmt der Windows-Helfer über WASAPI-Loopback ab (FFmpeg kann das
unter Windows nicht) und gibt ihn über eine benannte Leitung weiter; Bild und Ton laufen auf
derselben Uhr. Was nicht geht (Kodierer, Quelle), probiert Uzai der Reihe nach durch und merkt
sich, was lief (der schnelle Weg über die Grafikkarte bleibt dabei immer zuerst dran). Die Bildrate
ist fest (60 bzw. 30, `-fps_mode cfr`): Liefert die Quelle zu wenig Bilder (Grafikkarte vom Spiel
ausgelastet), füllt FFmpeg auf und zählt mit; FFmpeg bekommt dafür Vorrang (Prozessor „über
normal“, Grafikkarte „hoch“, keine Energiedrosselung). In `logs\helper.log` steht beim Start der
Weg (Quelle, Kodierer, Grafikkarte/Arbeitsspeicher, Vorrang), jede Minute „Quelle liefert x von 60
Bildern/s“ und zu jedem Clip die gemessene Bildrate der Datei. Der Puffer läuft nur, solange ein Spiel vorn ist: Er ruht, wenn Uzai länger als
eine Minute vorn ist, im Akkubetrieb (einstellbar), bei unter 2 GB freiem Platz und wenn das
Spiel endet. FFmpeg läuft als Kind des Helfers in einem Job-Objekt: Endet Uzai (auch bei einem
Absturz), beendet Windows FFmpeg mit; der Puffer-Ordner wird beim Start und Beenden geleert.

Einstellungen → **Aufnahmen**: *Aufnahme über* (Uzai (eigen) / Windows Game Bar / NVIDIA – die
beiden letzten drücken wie früher deren Tastenkürzel), FFmpeg einrichten, Zustand, Clip-Puffer,
Cliplänge, Qualität (720p/1080p/volle Auflösung), Bildrate (30/60), Bild (ganzer Bildschirm /
nur Spielfenster), Ton des Spiels, Mikrofon (Standard aus), Guide halten + X, Ordner (Standard
*Videos\Uzai*), Speicherplatz für Clips (Standard 25 GB; voll = keine neuen Clips, Uzai löscht
nie selbst), Akkubetrieb, Videos, Grenze für Discord.

### Lossless Scaling
Lossless Scaling (Steam, kostenpflichtig) verdoppelt oder vervierfacht die Bildrate jedes Spiels.
Uzai findet es in der Steam-Bibliothek. Im Guide gibt es dann während des Spiels die Karte
**Bildrate ×2**: Uzai startet Lossless Scaling falls nötig (minimiert, ohne Fokus), wartet, bis
der Guide zu ist, holt das Spiel nach vorn und drückt das Tastenkürzel nur, wenn das Spiel
wirklich vorn liegt (Lossless Scaling skaliert das Vordergrundfenster). Standard **Strg + Alt +
S**, muss mit „Scale“ in Lossless Scaling übereinstimmen. Danach sieht Uzai nach, ob Lossless
Scaling sein Bild zeigt (ein Fenster immer oben über dem ganzen Bildschirm), und meldet, wenn
nicht. Welcher Modus (×2, ×3, Hochskalieren) läuft, stellst du in Lossless Scaling ein; an dessen
Einstellungen ändert Uzai nichts.

Unter Einstellungen → Im Spiel → Bildrate ×2 lässt es sich automatisch beim Spielstart
einschalten (nie / bei PC-Spielen / bei Emulator-Spielen / bei allen), pro Spiel unter *Optionen*
auch einzeln (*Immer* / *Nie*); von Hand geht es in jedem Spiel über den Guide. Automatisch heißt:
sobald das Spiel vorn im Bild ist plus die eingestellte Wartezeit; ist dann der Guide offen,
wartet Uzai, bis er zu ist.
Das Spiel bzw. der Emulator muss im Fenster- oder **randlosen** Vollbild laufen (bei DuckStation,
PCSX2 & Co. unter Grafik/Anzeige „Randloses Vollbild“ statt exklusiv). Ist ein ShaderGlass-Bildfilter
aktiv, schaltet Uzai ihn dabei aus (einstellbar), weil beide Programme dasselbe Bild abgreifen.
`logs\lossless.log` zeigt jeden Schritt: welches Fenster vorn lag, ob es Adminrechte hatte, wie
viele Tastenereignisse Windows angenommen hat und welche Fenster Lossless Scaling vorher und
nachher hatte.

### Remote Play Together für jedes Spiel
Steam-Freunde können per Remote Play Together bei jedem Spiel mitspielen, das Uzai startet –
auch bei Emulator-Spielen (z. B. FIFA Street 2 in PCSX2). Steam erlaubt das nur bei Steam-Spielen,
die es können; Uzai leiht sich deshalb ein **Spender-Spiel** aus deiner Steam-Bibliothek, am
besten das kostenlose **RetroArch**.

Einrichten: Einstellungen → System → Remote Play Together → *Spender-Spiel* wählen. Uzai erkennt
die Programmdatei (aus Steams Startoptionen, sonst am Namen; im Zweifel fragt es), benennt sie in
`*.uzai-original.exe` um und legt an ihre Stelle einen kleinen Starter, den Uzai auf deinem PC mit
dem eingebauten .NET Framework baut. *Rückgängig machen* legt das Original zurück.

Starten: in den Optionen eines Spiels *Mit Remote Play Together starten*, oder in den Einstellungen
*Emulator-Spiele immer Remote-Play-bereit starten*. Uzai lässt Steam den Spender starten, der
Starter startet das Spiel; Pause, Guide, Bildfilter und Lossless Scaling funktionieren wie sonst.
Einladen: im Guide einen Steam-Freund wählen → *Zu Remote Play einladen* (auch in Steam-Spielen,
die Remote Play Together selbst können). Dein Freund nimmt die Einladung in Steam an. Klappt das
direkte Einladen nicht, geht es im Steam-Overlay (Umschalt+Tab) – Uzai holt dafür nichts nach vorn.

Alle im Discord-Call auf einmal: Läuft ein Spiel mit Remote Play Together und du bist in einem
Discord-Sprachkanal oder -Anruf (auch Gruppenanruf), steht im Guide unter *Discord* der Knopf
*Alle im Call zu Remote Play einladen* (im Gruppenanruf *Ganze Gruppe …*). Discord verrät nicht,
wer jemand bei Steam ist – deshalb ordnest du jede Person einmal ihrem Steam-Freund zu: Uzai zeigt
alle im Call mit Bild und schlägt den passenden Steam-Freund vor (Name und öffentlicher Klarname;
Groß/klein, Akzente, Trennzeichen, Tippfehler und Teilnamen wie „pixelpaul“ ↔ „Paul Berger“ zählen).
Eindeutige Vorschläge sind gleich gewählt, sonst A: drei Vorschläge, *Andere wählen …* (alle
Steam-Freunde) oder *Nicht einladen*; X lässt jemanden diesmal aus. Uzai merkt sich die Wahl
(Einstellungen → Konten → Discord → *Zuordnungen Discord ↔ Steam*: ändern oder entfernen). Ein
Druck lädt dann alle nacheinander ein (ein Helfer-Prozess, kurze Pause dazwischen); dich selbst und
wer schon in der Sitzung ist, lädt Uzai nicht ein. Danach steht bei jeder Person, wie es lief, und
eine Mitteilung fasst zusammen („3 eingeladen: Paul, Mira, Kai · 1 ohne Steam-Zuordnung“). Steam
empfiehlt höchstens vier Spieler (du und drei Gäste) – mehr geht, Uzai weist darauf hin. Einladen
geht nur an Steam-Freunde: Steams Gast-Link für Leute ohne Freundschaft gibt Steam an andere
Programme nicht heraus.

Spieler 2: Vor einem Remote-Play-Start belegt Uzai Spieler 2 im Emulator mit dem nächsten
Controller – das ist der deines Freundes – und stellt nach dem Spiel genau das zurück, was es
geändert hat (auch nach einem Absturz von Uzai beim nächsten Start). Hast du Spieler 2 selbst
belegt, bleibt das unangetastet; belegst du während des Spiels um, bleibt deine Belegung.

| Emulator | Was Uzai für Spieler 2 tut |
|---|---|
| PCSX2 | `PCSX2.ini` → `[Pad2]` wie Pad 1, Gerät +1 (`SDL-0` → `SDL-1`), Typ DualShock 2 |
| DuckStation | `settings.ini` → `[Pad2]` wie Pad 1, Gerät +1, Typ wie Pad 1 (z. B. AnalogController) |
| Dolphin (GameCube) | `GCPadNew.ini` → `[GCPad2]` auf den nächsten XInput-Controller, `Dolphin.ini` → Anschluss 2 = Standard-Controller |
| Dolphin (Wii) | `WiimoteNew.ini` → zweite emulierte Wiimote wie Wiimote 1 (mit Nunchuk usw.), Gerät +1 |
| Eden, Citron, Sudachi, yuzu | `qt-config.ini` → `player_1_*` wie Spieler 1 mit `port:1`, eingesteckt; Handheld → Pro Controller |
| RetroArch u. a. | nichts nötig, Spieler 2 nimmt den nächsten Controller von selbst |
| mGBA (GBA/GB) | nichts: ein Spieler am Gerät, dein Freund schaut zu (Linkkabel-Mehrspieler kann mGBA nicht per Befehl öffnen) |

Tragbare Installationen (`portable.txt`/`portable.ini` bzw. `user`-Ordner neben dem Programm)
werden erkannt, sonst Dokumente bzw. AppData. Liegt Spieler 1 nur auf der Tastatur, bekommt
Spieler 2 den ersten Controller mit Standardbelegung (bei Eden/Dolphin-Wii kommt ein Hinweis).

Erkennung: Der Starter zählt die Controller so, wie Steam sie dem Spiel zeigt, und schreibt sie
in seine Rückmeldung; zusammen mit dem Helfer meldet Uzai „Spieler 2 ist verbunden“ bzw. „Spieler 2
ist weg“. Kommt 90 s nach einer Einladung aus Uzai kein zweiter Controller, gibt es einen Hinweis
(Controller-Symbol im Steam-Overlay einschalten).

Adminrechte: Verlangt ein Spiel oder Emulator Adminrechte (im Manifest der Programmdatei oder per
Kompatibilität „Als Administrator ausführen“) und Steam läuft ohne, kann Steam es weder starten
noch Eingaben hineingeben. Uzai prüft das vor dem Start und sagt, was zu tun ist; meldet Windows
beim Start trotzdem Fehler 740, kommt dieselbe Erklärung.

PC-Spiele ohne Steam: Spiele aus PC-Ordnern und eigene Verknüpfungen (z. B. GOG oder itch ohne
Kopierschutz) gehen wie Emulator-Spiele, auf Wunsch immer (*PC-Spiele immer Remote-Play-bereit
starten*). Epic-Spiele gibt es pro Spiel unter Optionen; Uzai startet dann die Programmdatei direkt,
das klappt nur bei Spielen, die ohne Epic Launcher laufen. Local-Multiplayer braucht das Spiel
selbst: Dein Freund ist für das Spiel einfach Controller 2.

Grenzen: Deine Freunde sehen „spielt RetroArch“ (bzw. den Namen des Spenders). Ein Steam-Update
oder „Dateien auf Fehler prüfen“ kann den Starter durch das Original ersetzen; Uzai merkt das beim
nächsten Start und legt ihn still neu an. Startest du den Spender selbst in Steam, startet das
Original. Die Controller deiner Freunde kommen über Steam Input an; manche Emulatoren müssen
dafür auf XInput bzw. „Steam Input“-Controller eingestellt sein. Getestet ist der Ablauf nur
ohne Steam (Logik, Dateien, Übersetzen des Starters); ob Steam die Einladung annimmt, lässt sich
nur unter Windows mit echtem Steam prüfen.

---

## Anpassen

Fast alles lässt sich einstellen, ohne Dateien anzufassen:

- **Aussehen:** zehn Farbschemata (Graphit Gold als Standard: ruhiges Grau, helle Auswahl,
  Gold für Kleinigkeiten; dazu Etikett – das gelbe Aussehen von 0.4 –, Glut, Mitternacht, Tiefsee,
  Graphit, Bernstein, Phosphor, Kirsche, Papier), eigene Akzentfarbe, Ecken, Coverform und -größe,
  Schrift (IBM Plex Sans, Hanken Grotesk, Atkinson Hyperlegible oder eigene `.ttf`), Schrift für
  Titel und Bedienung (IBM Plex Sans Condensed, Hanken Grotesk, Saira oder wie der Rest), Stärke der Farbverläufe, Größe der ganzen Oberfläche, Hintergrund (Spielbild, Nebel, Farbe,
  eigenes Bild), *Raum in Spielfarbe* (der Hintergrund färbt sich dunkel in der kräftigsten Farbe
  des gewählten Covers), Startanimation, Menüklänge.
  *Leichter Modus* (Aus / Automatisch / An) für schwache PCs: Cover schneiden ihr Bild schlicht
  zu statt über einen eigenen Puffer, Schatten und Glimmen werden kürzer, die Lichter stehen
  still, der Weichzeichner nimmt weniger Proben, Animationen laufen etwas kürzer, Bilder liegen
  in 1080p-Größe und mit halbem Budget im Speicher, nur die Nachbarbereiche werden vorgebaut und
  das Menü zeichnet höchstens 60 Bilder/s (nach 20 s ohne Eingabe 30). Automatisch schlägt ihn
  einmal ruhig vor, wenn Uzai Software-Grafik sieht oder das Menü messbar ruckelt – nie still.
  Einstellungen → System → Leistung misst nach dem Umschalten neu (vorher/nachher).
- **Bereiche:** Reihenfolge ändern und ausblenden (z. B. Shop oder Videos weg).
- **Pro Spiel** (Start → Optionen): Titel, Bilder (SteamGridDB oder Datei), anderer Emulator,
  anderer Filter, eigene Startparameter, Ordner, Lossless Scaling, Verknüpfung, verstecken.
- **Pro System:** Name, Kürzel, Farbe, Emulator, Filter, Dateiendungen, an/aus.
- **Controller:** A/B tauschen (Nintendo-Stil), Tastensymbole (Xbox, PlayStation, Nintendo),
  Totzone, Wartezeit und Tempo beim Gedrückthalten (Stick und Steuerkreuz; der Stick zählt nur
  in seiner Hauptrichtung, LT/RT schalten genau einen Bereich pro Druck).
  *Controller testen* zeigt live Tasten, Steuerkreuz, Sticks (mit der Totzone als Ring) und
  Trigger; Start halten testet die Vibration (erst links/tief, dann rechts/hell), B halten geht
  zurück. Darunter jeder verbundene Controller mit Spieler, Verbindung und Akku.
  *Vibration bei Bestätigungen* (Standard an): ein kurzer, leiser Impuls (höchstens 150 ms), wenn
  ein Clip gespeichert wird, ein Erfolg freigeschaltet ist oder eine Nachricht kommt – auch im
  Spiel (dort über den Helfer, nur Xbox-/XInput-Controller); sonst vibriert im Spiel nie etwas von
  Uzai. *Auch wenn Freunde online kommen* (Standard aus, nur außerhalb von Spielen).
  **Akku:** oben in der Statuszeile und im Guide ein kleines Akkusymbol je Controller. Fällt ein
  Akku auf „schwach“ und später auf „fast leer“, kommt je Stufe einmal „Controller-Akku schwach“
  (im Spiel als Pop-up über dem Spiel); nach dem Laden darf es wieder melden. Xbox-Controller
  liest der Controller-Wächter des Helfers (`XInputGetBatteryInformation`, je Controller höchstens
  einmal pro Minute), DualSense/DualShock 4 ein eigener Faden über HID (`hid.dll`, keine
  Zusatzprogramme; ein DualSense über Bluetooth meldet den Stand erst, wenn ein Spiel oder Steam
  ihn in den vollen Modus geschaltet hat). Andere Controller: nur Name und Spieler.
  Für Entwickler: `Pads.pulse("achievement"|"clip"|"message"|"friend_online")`, `Pads.pads`,
  `Pads.changed`; der Test als Ebene `src/ui/layers/pad_test.gd` (`device`, `back_text`).
- **Eigene Klänge:** WAV- oder OGG-Dateien in `sounds\` im Datenordner (`move`, `select`, `back`,
  `tab`, `guide`, `notify`, `launch`, `boot`, `achievement`, `shutter`, `power_off`). Die
  mitgelieferten Klänge sind vorab gerendert (`tools/synth.py`, der Ausschaltklang mit
  `tools/synth_power.py`).
- **Startanimation:** Konsole (Schwarz, der Punkt leuchtet auf, dann steht das U – auf dem Schlag
  des Startklangs –, darunter die Wortmarke), kurz, Röhrenfernseher oder aus.
- **Ausschalt-Animation** (Einstellungen → System, Standard: an): Beim Schließen und Ausschalten –
  *Uzai schließen*, *Uzai ganz beenden*, Alt+F4 oder Schließen in der Taskleiste, *Neu starten* und
  *Herunterfahren* – tritt die Oberfläche zurück (kleiner, weich unscharf, dunkel), das Uzai-Zeichen
  erscheint kurz, fällt zu einer Lichtlinie zusammen, die sich zu einem Punkt zusammenzieht und
  verglimmt; dazu ein leiser, absteigender Ausschaltklang. Gut 1,4 s, nie länger als 1,6 s; ein
  zweiter Druck auf A oder B kürzt ab. Ist Uzai minimiert, im Spiel geparkt oder durchsichtig über
  einem Spiel/Video, beendet es sofort; ein zweites Alt+F4 ebenfalls. Bei Neustart/Herunterfahren
  bleibt das Bild danach schwarz (macht Windows nicht weiter, blendet Uzai nach 8 s wieder auf).

### Alle Bilder von SteamGridDB
Einstellungen → Bibliothek → *Alle Bilder von SteamGridDB holen* lädt für jedes Spiel Cover,
Hintergrund, Schriftzug und Symbol – wahlweise nur fehlende oder alles neu. Selbst gewählte Bilder
bleiben. Braucht den kostenlosen SteamGridDB-Schlüssel.

### Cover für Emulator-Spiele
Ohne Schlüssel lädt Uzai Cover, Spielszenen und Titelbilder aus der freien Libretro-Sammlung
(dieselbe wie RetroArch; fällt der Libretro-Server aus, über den GitHub-Spiegel). Die Datei muss
nicht wie in der Sammlung heißen: Uzai lädt einmal pro System das Verzeichnis und sucht unscharf
(`shadow_of_the_colossus [PAL].iso` findet `Shadow of the Colossus (Europe, Australia)`, „and“
und „&“ sind gleich, „, The“ wird erkannt, Demos und Betas fallen weg, die deutsche bzw.
europäische Fassung kommt zuerst). Mit SteamGridDB-Schlüssel kommen zuerst Bilder von dort.
Ausschalten: Einstellungen → Bibliothek (auch die Wikipedia-Abfrage).

### Bilder aus SteamGridDB
Im Spiel *Optionen → Bilder aus SteamGridDB*: alle Cover, Hintergründe, Logos und Symbole des
Spiels als Raster. LB/RB wechselt die Art, A übernimmt, X sucht das Spiel unter anderem Namen,
Y entfernt das eigene Bild wieder. Logos ersetzen auf der Startseite den Titel.

### Eigene Bilder ohne Menü
Bilder in den Medienordner legen (Standard: `media\` im Datenordner), Dateiname wie die ROM oder
der Spieltitel, `.png`, `.jpg` oder `.webp`:

```
media\
  ps2\
    Shadow of the Colossus (Europe).png      ← Cover
    hero\Shadow of the Colossus (Europe).jpg ← Hintergrund
    logo\Shadow of the Colossus (Europe).png ← Schriftzug
  gba\
    Pokemon Smaragd.png
```

Reihenfolge, in der Uzai Bilder sucht: eigenes Bild aus dem Menü → Medienordner → eigene
Steam-Artworks (`userdata\…\config\grid`, auch von Steam ROM Manager) → Steam-Cache (alte und
neue Ordnerstruktur) → Steam-Store (kennt auch die neuen Bildadressen) → SteamGridDB →
gezeichnetes Ersatzcover.

### Profil, Erfolge und Spielzeit
- **Profil** (Hauptbereich): dein Steam-Profil mit Profilhintergrund, großem Avatar, Status,
  „Seit … bei Steam“, Info-Text und Level-Ring; *Steam in Zahlen* (Spiele, Spielzeit, perfekte
  Spiele, Erfolge), zuletzt gespielt, perfekte Spiele, seltenste Erfolge und RetroAchievements
  (Punkte, Rang, gemeistert, durchgespielt). Perfekte Spiele zählt Uzai über die ganze Bibliothek
  (nicht nur die letzten zwei Wochen) und merkt sich den Stand.
- RetroAchievements für Emulatorspiele und Steam-Erfolge stehen beim Spiel, im Guide und unter
  *Profil → Erfolge*. Die Übersicht ist ein Trophäenschrank: oben ein Ring über alle Erfolge, darunter
  zuletzt freigeschaltete mit Seltenheit bzw. Punkten, *Fast geschafft* und *Komplett* als
  Spielkacheln. Die Erfolge eines Spiels füllen eine ganze Seite (links Cover, Ring und Stand je
  Seltenheit, rechts die Liste mit Filtern über LB/RB). Geheime Steam-Erfolge deckt A auf.
- **Vergleichen:** in den Erfolgen eines Steam-Spiels **Y** oder bei einem Freund *Erfolge
  vergleichen* – Uzai zeigt pro Erfolg, wer ihn hat (geht, wenn das Steam-Profil des Freundes
  öffentlich ist).
- **Spielzeit** unter *Profil → Spielzeit*, erzählt über die Spiele statt über Zahlenkacheln:
  oben das Spiel der Woche mit Cover und den letzten sieben Tagen als Säulen, darunter die
  Aufteilung nach System, die meistgespielten Spiele als Cover-Reihe und ein Verlauf als
  Zeitleiste (Heute, Gestern, Montag …) mit jeder Sitzung. *Dein Rückblick* zeigt die Gesamtzeit
  mit Anteilen je System, die längste Runde, den Lieblingstag, die Tageszeit und die längste
  Serie. A öffnet die Spielseite. Uzai misst jede Sitzung, Steam-Spielzeit kommt mit der
  Steam-Anmeldung dazu.

---

## Windows als Konsole einrichten

1. **Autostart:** Einstellungen → System → *Mit Windows starten*.
2. **Automatisch anmelden:** `netplwiz` ausführen, Haken bei „Benutzer müssen Benutzernamen und
   Kennwort eingeben“ entfernen. (Bei Microsoft-Konten vorher unter *Konten → Anmeldeoptionen*
   „Nur Windows Hello-Anmeldung zulassen“ ausschalten.)
3. **Guide-Taste freigeben:** Windows-Einstellungen → Spielen → Game Bar → „Game Bar mit dieser
   Taste auf einem Controller öffnen“ ausschalten. In Steam → Einstellungen → Controller die
   Guide-Taste-Verknüpfung abschalten. Sonst einfach **View + Start** nutzen.
4. Emulatoren am besten so einstellen, dass sie beim Beenden nicht nachfragen.

### Nach dem Schließen im Hintergrund bereit

Wie bei einer Konsole: Schließt du Uzai über Ausschalten → *Uzai schließen*, holt die
**Guide-Taste** (oder View + Start) es zurück – im Vollbild, mit der Startanimation wie sonst.
Einstellungen → System → *Nach dem Schließen im Hintergrund bereit* (Standard: an). Alt+F4 und
Schließen in der Taskleiste beenden Uzai dagegen ganz, ohne Wächter (wie *Uzai ganz beenden*).

- Uzai selbst beendet sich dabei ganz. Es bleibt nur ein winziger Wächter (ein verstecktes
  PowerShell mit `uzai-helper.ps1 -Watch`), der die Controller abfragt: kaum Rechenzeit, wenige MB
  Arbeitsspeicher, niedrige Priorität.
- Er endet beim Abmelden, Neustarten und Herunterfahren und sobald Uzai wieder läuft. Es gibt
  keinen Autostart, keinen Registry-Eintrag und keine geplante Aufgabe.
- **Uzai ganz beenden** (Ausschalten-Menü oder im Schließen-Dialog) startet keinen Wächter.
- Liegt vorn ein Vollbild-Programm (ein Spiel außerhalb von Uzai, Steam Big Picture), gehört ein
  kurzer Druck diesem: die Guide-Taste dann **0,8 s halten**.
- Öffnet die Guide-Taste auch die Xbox Game Bar oder Steam, kommt beides: siehe Punkt 3 oben.
- Controller aus? Ein Druck auf Guide schaltet ihn erst ein; nach dem Verbinden nochmal drücken
  (oder Guide beim Einschalten gedrückt halten).

### Updates

Uzai sucht höchstens einmal am Tag (gut eine Minute nach dem Start) auf GitHub nach einer neuen Fassung.
Einstellungen → System → *Updates*: **Automatisch** (lädt im Hintergrund, spielt beim Schließen ein), **Nur melden**
oder **Aus**; darunter *Nach Updates suchen* bzw., wenn eins bereitliegt, *Update einspielen* (Uzai startet dafür neu).

- Jedes Release trägt neben dem Paket eine Signatur. Uzai lädt das Paket nur, wenn die Signatur zum Schlüssel in
  Uzai passt, und nur mit genau der signierten Prüfsumme; aus dem Paket kommen nur `Uzai.exe`, `Uzai.pck` und
  `discord_partner_sdk.dll`. Ohne Schlüssel in Uzai (`Updater.SCHLUESSEL` leer) meldet es ein Update nur.
- Eingespielt wird beim Schließen: Ein kurzer Helfer wartet, bis Uzai weg ist, tauscht die Dateien mit Sicherung und
  holt bei einem Fehler die alten zurück. Liegt Uzai in einem Ordner ohne Schreibrecht (etwa unter „Programme“),
  meldet es das Update nur.
- Protokoll: `logs/update.log` (nur Fassungen und Gründe).

Herausgeben (nur der Herausgeber, mit dem privaten Schlüssel außerhalb des Projekts):

```
godot --headless --path . --script res://tools/release_signieren.gd -- --signieren <privat.pem> Uzai-X.Y.Z-windows.zip
```

Dann ins GitHub-Release mit Tag `vX.Y.Z`: `Uzai-X.Y.Z-windows.zip` und `Uzai-X.Y.Z-windows.zip.sig`.

### Ruhemodus und Schnellfortsetzen

Wie Ruhemodus und Quick Resume bei Xbox und PlayStation. Einstellungen → System →
*Ruhemodus & Fortsetzen*.

**Ruhemodus:** Guide-Taste **etwa 1 s halten** (kurz drücken öffnet wie immer den Guide) oder
Guide → System → Ausschalten → *Ruhemodus*. Der Bildschirm geht aus (nur für den Augenblick über
`SC_MONITORPOWER`, an den Energieoptionen von Windows ändert sich nichts), das Spiel hält an, sein
Ton geht aus, Uzai zeigt still „Ruhemodus“ (der Text wandert langsam, OLED-Schutz). **Jede Taste**
am Controller – auch ein eben eingeschalteter Controller – weckt: Bildschirm an, Spiel läuft weiter
und ist wieder vorn, „Willkommen zurück“. Eine Mausbewegung schaltet nur den Bildschirm ein.

- **Emulatoren** hält Uzai an wie beim Guide (Prozess anhalten) – das geht immer.
- **PC-Spiele** (Steam, Epic, EA, eigene): *PC-Spiele im Ruhemodus anhalten* = *Nur ohne
  Anti-Cheat* (Standard) oder *Aus*. Uzai sucht im Spielordner nach Easy Anti-Cheat, BattlEye,
  Riot Vanguard, EA Anti-Cheat, XIGNCODE3, GameGuard, PunkBuster, ACE, EQU8, FACEIT und allem mit
  „anticheat“ im Namen; Steam-Spiele, die laut Store nur online gehen (MMO, Mehrspieler ohne
  Einzelspieler), zählen auch dazu. Solche Spiele laufen weiter, nur Bild und Ton gehen aus – ein
  angehaltener Prozess kann dort als Manipulation gelten, Online-Spiele verlieren die Verbindung.
  Die Ruhe-Anzeige sagt, was mit dem Spiel ist.
- Läuft kein Spiel, geht nur der Bildschirm aus (Musik und Video halten an).

**Ruhebildschirm** (wie beim Apple TV): Bleibt Uzai im Menü eine Weile unbedient (*Ruhebildschirm*:
Aus, 2, 5, **10** (Standard), 20 oder 30 Minuten), ziehen die großen Bilder deiner Spiele in einer
langsamen Kamerafahrt vorbei und blenden weich ineinander – unten links das Spiel mit Plattform und
Spielzeit, oben rechts Uhrzeit und Datum, unten rechts die laufende Musik. Favoriten und zuletzt
Gespieltes kommen zuerst. Nur Bilder, die schon auf dem PC liegen (eigene Bilder, Medienordner,
Steam-Cache, Uzais Zwischenspeicher) – für den Ruhebildschirm lädt Uzai nichts; ohne ein einziges
Bild steht nur die Uhr da und wandert. Auf Wunsch auch eigene Bildschirmfotos (jedes dritte Bild).
Nie im Spiel, bei einem Video oder Film im Bild, im Ruhemodus, beim Tippen oder wenn Uzai nicht vorn
ist. **Jede Eingabe** (Taste, Klick, echte Mausbewegung, Stick, Guide-Taste) beendet ihn, ohne
dahinter etwas auszulösen; Medientasten bleiben bei der Musik. Die Bilder sind leicht gedämpft,
Uhr und Schrift rücken mit jedem Bild ein Stück weiter (OLED-Schutz). Er läuft mit 30 Bildern pro
Sekunde, mit *Nur überblenden* (oder „Animationen reduzieren“, oder wenn das Menü auf dem PC oft
ruckelt) ohne Kamerafahrt mit 12. *Danach Ruhemodus*: nach 30 Minuten bis 2 Stunden auf Wunsch in
den Ruhemodus. *Vorschau* zeigt ihn sofort.

**Schlaf-Timer** (Schnellmenü-Kachel, Ausschalten-Menü, im Video Y → *Wiedergabe*): in 15, 30, 60
oder 90 Minuten bzw. *nach dieser Folge* (dann startet keine nächste) halten Video und Musik an und
Uzai geht in den Ruhemodus; beim Aufwachen läuft nichts von selbst weiter. Eine Minute vorher kommt
eine leise Mitteilung. **Nur hören** (Kachel bzw. Ausschalten-Menü, mit Musik, ohne Spiel): das Bild
wird dunkel, die Musik läuft weiter, jede Taste weckt. Auf Wunsch schaltet der Ruhemodus kabellose
Xbox-Controller aus (*Controller ausschalten*; die Xbox-Taste schaltet ein und weckt).
**Nachts leiser** (Einstellungen → Klang → Ausgabe): im gewählten Zeitfenster hält Uzai die
Lautstärke von Windows höchstens auf 20–50 % – es senkt nur, nie lauter.

**PC schlafen legen** (Ausschalten-Menü, mit Rückfrage): echter Energiesparmodus
(`SetSuspendState`), das Spiel bleibt offen. Nach dem Aufwachen merkt Uzai den Zeitsprung und holt
das Spiel wieder nach vorn. Mit dem **Controller aufwecken** geht nur, wenn er per USB oder
Xbox-Funkadapter verbunden ist und Windows ihn wecken lässt (Geräte-Manager → Gerät →
Energieverwaltung → „Gerät kann den Computer aus dem Ruhezustand aktivieren“); über Bluetooth
meist nicht. Online-Spiele verlieren dabei meist die Verbindung.

**Schnellfortsetzen für Emulatoren:** *Guide → Spiel beenden* sichert vorher einen Spielstand
(„Beenden“ steht dann vorn, *Ohne Fortsetzen beenden* daneben). Uzai drückt das Speichern-Kürzel des
Emulators, macht ein kleines Vorschaubild, sucht die eben geschriebene Datei, legt eine Kopie im
Datenordner ab (`quickresume/`) und stellt den Speicherplatz des Emulators wieder her, wie er war
(gesicherte Datei zurück, neu angelegte wieder weg). Beim nächsten Mal zeigt die Spielseite
**Fortsetzen (vor 2 Std.)** mit dem Bild und **Neu starten** daneben; der Guide zeigt das Spiel
unter *Zuletzt pausiert*, die Startseite „pausiert vor 2 Std.“. Endet das Spiel anders (im Emulator
beendet, Absturz) nach mehr als zwei Minuten, verwirft Uzai den Stand – er wäre älter als der
Fortschritt.

| Emulator | Speichern (ab Werk) | Laden beim Start |
|---|---|---|
| DuckStation | F2 | `-statefile <datei>` |
| PCSX2 | F1 | `-statefile <datei>` |
| PPSSPP | F2 | `--state=<datei>` |
| Dolphin | Umschalt+F1 | `-s <datei>` |
| RetroArch | F2 | `-e <platz>` – Uzai legt seinen Stand als `<spiel>.state<N>.entry` neben den Platz, den das Kürzel benutzt hat; RetroArch zeigt diese Datei nicht als Platz an |

Andere Emulatoren (mGBA, Ryubing, Cemu, xemu, Xenia, RPCS3 …) laden beim Start keinen Spielstand
über die Kommandozeile oder speichern nicht über ein Kürzel – dort bleibt es bei *Spielen*.
Uzai sucht die Spielstände in den üblichen Ordnern (neben der .exe für portable Installationen,
Dokumente, AppData); wer im Emulator einen eigenen Ordner für Spielstände eingestellt hat, bekommt
die Meldung „Ohne Fortsetzen beendet“. Kürzel geändert? Unter Einstellungen → Emulatoren eintragen.

---

## Stand

Getestet (Linux, Godot 4.5.1, ohne Windows):
- 0.16.91 (am Windows-PC: check 0 Fehler, lint 0, tot_code 0, logic_updater alles ok, logic_pentest alles ok,
  update_cs.ps1 alles ok mit Windows PowerShell 5 (Einspielen, Rückweg, fremde Datei), zimmer_treff_cs alles ok
  (mit den neuen Flut-Prüfungen; unter PowerShell 7 nur mit stummgeschalteten „veraltet“-Warnungen von .NET);
  ein echtes Update über GitHub ist noch nicht durchgelaufen – dafür fehlen Schlüssel und Release):
  - Rückmeldung: „Alt+F4 soll das Programm komplett schließen“ – Alt+F4 und die Taskleiste starteten den Wächter für
    die Guide-Taste. Jetzt beenden sie ganz (Helper sperrt den Wächter beim Schließen-Signal); im Hintergrund bereit
    bleibt Uzai nur über Ausschalten → „Uzai schließen“.
  - Wunsch: Updater über GitHub. Neu: src/core/updater.gd und update_pruefung.gd (Signatur RSA/SHA-256 über
    Fassung, Datei und Prüfsumme; nur erlaubte Dateien; Einspielen beim Beenden über den Helfer mit -Update),
    tools/release_signieren.gd, Einstellungen → System → Updates. docs/SECURITY.md „Updates“.
  - Frage „Kann RCE passieren über die Verbindung zwischen Uzai-Nutzern?“: eigene Prüfung von Zimmer online – kein
    Weg für Fremde gefunden (docs/SECURITY.md). Behoben: Bild in Discord-Meldungen nur über Discords Proxy neu
    kodiert (vorher Original-Bytes eines Fremden im Hauptprozess), BMP aus dem Netz nie; Treffpunkt zählt
    Wiederholungsschutz und Drossel erst nach dem Entschlüsseln (ein Dritter konnte Besuche verhindern).
  - Rückmeldung: „SP Football Life 2027: Das Spiel startet über ein kleines Programm, Uzai denkt dann, das Spiel sei
    zu – nicht bedienbar („Ein anderes Fenster ist vorn“), im Guide steht nichts“: Die Verknüpfung zeigt auf
    „FL 2027 start.exe“, das FL_2027.exe startet und sich beendet; Uzai sah nur den Starter. Endet der gestartete
    Prozess in den ersten 5 Minuten und läuft im Spielordner etwas anderes, gilt ab da der Ordner (wie bei Epic und
    GOG): Das Spiel läuft, solange dort etwas läuft; Fenster, Guide und „Spiel beenden“ folgen dem (launcher.gd
    _nachfolger; nie in Sammelordnern wie „Programme“). Am Spiel selbst noch nicht gesehen.
  - Proben am Windows-PC nur mit eigenem Datenordner (Umgebungsvariable UZAI_DATA): Ohne ihn laufen sie im echten
    Datenordner – bei wechselnder Fassung legte Config jedes Mal eine Update-Sicherung an und verdrängte ältere
    (höchstens 5 bleiben). logic_beenden besteht im frischen Ordner; zwei seiner Prüfungen hängen unter Windows am
    Zeitpunkt, zu dem der Helfer bereit ist (auch auf 0.16.90).
  - Nach 0.16.90 im Code: discord.log ohne Discord-Kennungen.
- 0.16.90 (am Windows-PC headless: check 0 Fehler, lint 0, tot_code 0, zustaende 0, logic_pentest alles ok mit den
  neuen Prüfungen; helfer_cs übersetzt alle geänderten C#-Blöcke als C# 5 – der eine Fehler in TvFangSrc steht genauso
  auf 0.16.89; der Browser-Kern übersetzt mit Windows PowerShell 5 wie im Helfer; nichts davon am laufenden Uzai
  gesehen – Aufnahme mit Ton, Discord-Sprachkanal, Browser und Filme bitte einmal am PC):
  - Zweite Sicherheitsprüfung vor der Veröffentlichung (docs/SECURITY.md „Zweite Sicherheitsprüfung“): drei Prüfer,
    jeder Fund im Code gegengeprüft. Behoben: NT-Pfade wie `\??\UNC\…` in Addon-Bildern (NTLM), Discord-RPC ohne
    Prüfung, wer die Leitung angelegt hat, offene Ton-Leitungen der Aufnahme, `userGesture` bei jedem Browser-Befehl,
    `chrome_elf.dll` ohne Signaturprüfung, Schlüssel in mpvs und Uzais Spieler-Protokoll, Medienserver-Schlüssel an
    fremden Bildadressen, Heimnetz-Freigabe im Browser nach dem Verlassen der Seite, fester mpv-Leitungsname,
    Rechenlast auf der Handy-Seite. Offen und dort beschrieben: Service Worker im Browser-Kern, belegter
    Steuer-Anschluss.
  - Suche nach eingetragenen Schlüsseln in allen Git-Dateien: nichts Geheimes im Code.
  - GitHub-Seite: Startbild als Fernseher mit Fuß und lila Schein, die Funktionsbilder mit runden Ecken und Schatten
    (WebP, zusammen 2 MB); beim Zimmer der Besuch anderer Uzai-Nutzer und Remote Play Together.
- 0.16.89:
  - Rückmeldung vom PC: Im Guide stand auf Englisch „Streams ansehen“ deutsch. Die Zeile war als „Namen“ markiert (der Zusatz nennt, wer streamt), damit wurde auch der Titel nicht übersetzt; jetzt übersetzt die Zeile ihren Titel selbst, ebenso „Server“ (guide_discord.gd). Alle Reiter des Guide auf Englisch abgelaufen (Vorführdaten, ohne Sprachkanal): keine deutschen Reste. Die README im Wurzelordner ist jetzt die englische Startseite für GitHub; die deutsche Anleitung steht in docs/README.de.md.
- 0.16.88:
  - Rückmeldung vom PC: Die Nutzer sollen mitbekommen, dass Uzai Steams Guide-Taste von selbst abschaltet. Vor dem Abschalten beim Start ein Fenster mit Erklärung – „Verstanden“ schaltet ab, „Steam behalten“ lässt es, weggedrückt fragt Uzai beim nächsten Start wieder (steam_guide.gd beim_start, entscheidung, frage_text; main._steam_guide_fragen; logic_steam_guide). Die Mitteilung danach, die Zeile in der Einrichtung und die in den Einstellungen sagen, dass es auch ohne Uzai gilt und wo man es zurückstellt. Unter Windows lief nichts davon.
- 0.16.87:
  - Rückmeldung vom PC: „die Menüs sind nicht flüssig, Hz-mäßig“. An 4K bewegt sich die Oberfläche jetzt auf ganzen Bildpunkten statt auf dem Raster von 1080p, ohne Bild, in dem eine Bewegung steht, auch bei 120 Hz (src/core/raster.gd, liste.gd feder_px, u.gd px_schluss, cover_row.gd, feder_lage.gd); Listen rollen feiner als ganze Punkte (nav.gd _lage_setzen); geprüft in logic_kreuzen und im Bild an 4K. Die Startseite baut ihr Regal in Scheiben (games.gd, U.nach_und_nach: Betreten 20–27 statt 33–40 ms Rechenzeit hier). leistung.log schreibt eine Zeile „Bildtakt“ mit Bildern je Sekunde, Rate des Bildschirms, Treiber und Bildschirmen. Unter Windows lief nichts davon.
- 0.16.86:
  - Rückmeldungen vom PC (eingegangen nach 0.16.63, auf dem Stand von 0.16.85 zusammengeführt). Profil: Die Unterseiten bleiben stehen und bauen in Scheiben (achievements_view.gd switch_sub, nachbau; Tastendruck gemessen 20–76 ms, danach 4–27 ms, beim Zurückkommen meist 4–6 ms). Guide: Der gewählte Reiter ist mit dem Steuerkreuz erreichbar (guide.gd _TabPill). Wunschliste: baut neu, sobald sie da ist, und liest nach der Steam-Anmeldung noch einmal (Store.wishlist_noetig, logic_shop_neuaufbau). Bildschirmtastatur: Tasten für .com, www., https:// im Browser (keyboard.gd kuerzel, logic_einstellungen). Shop- und Spielseite: Diskussionen, Guides, Artworks und mehr öffnen in Uzais Browser (Store.steam_seiten, logic_shop). Steam-Suche: Kategorien als Filter, mit oder ohne Suchwort (Store.search mit tags, parse_suche_gefiltert; Form der Antwort gegen Steam nachgesehen, logic_shop) – der ganze Weg lief nur im Vorführmodus, unter Windows lief nichts davon.
- 0.16.85 (headless: check 0 Fehler, lint 0, tot_code 0, zustaende 0; logic_youtube_tv mit den neuen Prüfungen grün,
  seine zwei Fehler „nicht angemeldet“ wie auf 0.16.84; am PC 15.11.: Livestreams stehen in der Suche in „Gerade
  live“):
  - „Livestreams, die ich gesucht habe, gab es nicht bei YouTube – zum Beispiel gestern das Worlds-Finale“: Die Suche
    (yt-dlp ytsearch40) bekommt Livestreams nur, wenn YouTube sie unter die ersten 40 stellt – das tut es fast nie
    (am 15.11. bei „league of legends“ und „fifa“ keiner von 40, obwohl Hunderte liefen; bei „news“ 4). Jetzt fragt
    Uzai gleichzeitig mit dem Filter „Live“ (Adresse results?…&sp=EgJAAQ%253D%253D, wie YouTube selbst) und zeigt
    eine Reihe davon als „Gerade live“ über den Ergebnissen; was dort steht, fehlt unter den Ergebnissen. Dauer: die
    längere der beiden Suchen. Diese Antwort hat keinen Kanalnamen: Kennung aus channel_url, als Name das @-Kürzel aus
    uploader_url (from_ytdlp, gesäubert, Kennung nur aus erlaubten Zeichen).
- 0.16.84 (headless: check 0 Fehler, lint 0, tot_code 0, zustaende 0; logic_youtube_tv mit den neuen Prüfungen grün,
  seine zwei Fehler „nicht angemeldet“ kommen vom angemeldeten Profil auf dem PC und stehen genauso auf 0.16.83;
  am PC 15.11.: Guide über einem laufenden Video zeigt das Bild dahinter; Livestreams dort noch nicht gesehen):
  - „Starte ich Videos, Streams oder Filme und drücke Guide, ist das Video dahinter ausgeblendet“: Mit „Video vorn“
    (Standard seit 0.7.1) lag Uzai für den Guide als undurchsichtiges Fenster über mpv – eine leere Fläche über dem
    Bild. Solange ein Menü über dem Video liegt, ist Uzai jetzt durchsichtig (main_fenster.gd menue_durchsichtig, wie
    see_through ohne „immer oben“): erst durchsichtig, solange mpv noch oben liegt, nach zwei fertigen Bildern nach
    vorn; beim Schließen erst mpv wieder nach oben, nach 0,5 s Uzai dahinter wieder undurchsichtig. mpvs eigene Leiste
    (uzai_osd.lua, Nachricht „covered“) zeichnet dabei nichts – sonst stünden Titel und Balken hinter dem Guide.
  - „Bei YouTube fehlen Livestreams“: Sie waren im Abo-Feed (aus der Fernseher-Anmeldung), haben aber kein Alter
    (published 0) und standen nach dem Sortieren ganz hinten (beim Nutzer Platz 101–103 von 104; die Reihe zeigt 20).
    feed_mischen stellt Livestreams nach vorn, der Live-Stand aus dem Abo-Feed gewinnt gegen RSS; „Für dich“ bzw.
    „Startseite“ hat die Reihe „Gerade live“, der Reiter „Neu“ eine Gruppe ganz oben. Der Abo-Feed kommt jetzt auch
    beim Öffnen von Videos (höchstens alle 20 Minuten), alte Einträge daraus gehen dabei (beendete Streams).
- 0.16.83 (headless: check 0 Fehler, lint 0, tot_code 0; logic_regal nicht gelaufen – es fasst Dateien im Datenordner an):
  - „Die Grid-Optionen bei Konsolen komplett raus, nur das Regal“: Regal.ist_regal gilt für jede Konsole (alte Wahl
    library.ansicht/konsolen_ansicht zählt nicht mehr – beim Nutzer stand PS2 auf „Eigenes Raster“). Im Regal unter Y
    fallen „Eigenes Raster“ und „Als Liste“ weg, in den Einstellungen „Konsolen öffnen als“. Ordner bleiben ihr Mosaik.
- 0.16.82 (headless: check 0 Fehler, lint 0, logic_chat_medien grün; keine echten Chats angesehen):
  - „Alte Bilder erscheinen nur, wenn jemand eine neue Nachricht schreibt, davor ‚Nachricht ohne Text‘“: Die Bilder kamen
    an (discord.log: GET_CHANNEL beim Öffnen, mit messages), aber die Chat-Ansicht zeichnete nur neu, wenn sich Zahl
    oder letzte Nachricht änderten. verlauf_sig zählt jetzt auch die Nachrichten mit Bildern; ist ein Bild geladen und
    man stand unten, bleibt man unten (bild_geladen).
- 0.16.81 (headless: check 0 Fehler, lint 0, logic_chat_medien und logic_pentest grün; keine echten Chats angesehen):
  - „Im Pop-up steht nur der Dateiname“: Das Pop-up kam aus Discords eigener Benachrichtigung (NOTIFICATION_CREATE),
    deren body bei Bildern der Dateiname ist. Notify.discord_popup liest jetzt die Anhänge der mitgelieferten Nachricht
    (DiscordChat.medien_aus): „Bild“ statt Dateiname, das Bild klein als Vorschau.
  - „Alte Bilder laden erst, wenn ein neues kommt“: Uzai fragte die Discord-App nur, wenn das SDK einen Anhang meldete –
    bei älteren Nachrichten meldet es keinen. Jetzt holt history() die Bilder des Gesprächs einmal je Sitzung immer
    (und versucht es weiter, bis die Discord-App bereit ist).
- 0.16.80 (headless: check 0 Fehler, lint 0, logic_chat_medien (Schreibfeld neu), logic_pentest, logic_schweben grün;
  keine echten Chats angesehen):
  - „Screenshots laden, aber A will sie aufs Handy schicken, und darunter steht der Dateiname“: Ein Bild steht allein in
    der Blase (in seinem Format), A bzw. Klick öffnet es groß (capture_view.gd nimmt jetzt auch Adressen); kein
    „Aufs Handy“ bei Bildern.
  - „Im Pop-up soll das Bild klein zu sehen sein, nicht ‚Datei‘“: DiscordChat holt bei einer neuen Nachricht mit Anhang
    kurz die Adresse (_bild_von, höchstens gut 3 s), Toasts zeigt sie als kleine Vorschau; ohne Namen heißt ein
    Anhang „Anhang“, nicht „Datei“.
  - „Die Nachrichtenvorschläge komplett raus“: Schnellantworten und der Song-Knopf über dem Schreibfeld sind weg.
  - „Mit der Maus unten im Chat klicken und direkt schreiben, das Feld nur mit dem Controller“: _Composer tippt mit
    Maus/Tastatur in einem Eingabefeld im Schreibfeld selbst (Enter schickt, Esc hört auf); Controller/Touch wie bisher.
- 0.16.79 (headless: check 0 Fehler, lint 0, logic_chat_medien grün, logic_mitteilungen wie vorher 1 Fehler; nicht mit
  der echten Discord-App bestätigt):
  - „Nach ‚Bilder anzeigen‘ kommt kein Fenster in der Discord-App“: Auf einer angemeldeten Verbindung lehnt Discord
    AUTHORIZE mit „Already authenticated“ ab (discord.log). Uzai deutete das als abgelehnte Rechte und stufte bis
    „Uzais App nicht freigeschaltet“ zurück. Jetzt: Verbindung zur Discord-App kurz schließen, neu öffnen, AUTHORIZE
    vor AUTHENTICATE (Voice.msg_scope_anfragen, _msg_flow). Abgelehnt, liegen gelassen oder Zugang nicht ausgestellt:
    mit dem alten Zugang anmelden. „Already authenticated“ stuft nie mehr zurück.
- 0.16.78 (headless: check 0 Fehler, lint 0, logic_chat_medien und logic_pentest grün; keine echten Chats angesehen):
  - „Das mit den Discord-Bildern ist kacke, kriegen wir das anders hin?“: Über die Discord-App (lokale Schnittstelle,
    Recht messages.read) liefert GET_CHANNEL die Nachrichten mit Anhängen samt Adresse. Im Chat einmal „Bilder
    anzeigen“ → Discord fragt „Autorisieren“; ab dem nächsten Start holt Uzai für die offene Unterhaltung die Anhänge
    (Voice.nachrichten_holen, DiscordChat.medien_aus) und zeigt Bilder in der Blase. Nur Adressen von
    cdn.discordapp.com/media.discordapp.net, nur https; GIFs als Discords PNG-Vorschau. Lehnt Discord das Recht ab,
    fragt Uzai ohne es neu (nie scheitert daran die übrige Freigabe) und bleibt bei der Karte.
- 0.16.77 (headless: check 0 Fehler, lint 0; logic_chat_medien (neu), logic_pentest, logic_leicht, logic_schweben,
  logic_guidepanel, logic_steam_mit_pc grün; logic_freunde, logic_mitteilungen, logic_videos scheitern hier wie schon
  auf 0.16.76 (englisches Profil). Helfer: Discord-C#-Block mit Windows PowerShell 5 übersetzt. Keine echten Chats
  oder Anrufe angesehen, nichts im Fenster angesehen):
  - „Beim Discord-Anruf steht ‚… über die Discord-App‘ – kein Text, und Ablehnen fehlt“: Zeile weg; Annehmen,
    Ignorieren, Ablehnen (Voice.decline_call: Uzai klingelt für diesen Anruf nicht mehr – beim Anrufer klingelt es
    weiter, die lokale Discord-Schnittstelle kennt kein Ablehnen).
  - „Ecken abgerundet, aber man sieht klein die rechteckige Kante“: kernlicht.gdshader traf in den Ecken den Schatten;
    jetzt nur innerhalb der Rundung (Uniform „rund“ aus der StyleBox).
  - „X A B ganz bisschen off center“: Glyph._text zentriert nach dem sichtbaren Zeichen (TextServer), nicht nach
    Zeilenhöhe – vorher bis zu ½ Punkt daneben, in 4K ein Bildpunkt.
  - „Im Discord- oder Steam-Chat sieht man keinen Link, kein Bild, kein Video“: Steam: [img]/[url]/src-Adressen bleiben
    (SteamChat.clean). Bilder bekannter Dienste (ChatLink.BILD_HOSTS, nur https) stehen als Bild in der Blase, Videos
    als Karte. Discord: Das SDK gibt Anhänge nur als Art, Titel, Anzahl heraus (keine Adresse) – Karte „Bild ·
    urlaub.jpg“; der Helfer liest dafür MessageHandle_AdditionalContent.
- 0.16.76 (headless: check 0 Fehler, lint 0; logic_steam_mit_pc (neu), logic_iidb, logic_schweben, logic_guidepanel
  grün. logic_steam_status nicht gelaufen – es löscht das echte steam.log im Datenordner. Nicht im Fenster und nicht
  bei Steam-Freunden nachgesehen):
  - „Play und Continue playing nicht zentriert“: Die ungleichen Ränder gehörten zur Taste auf der Scheibe (bis 0.16.74);
    jetzt 16/16.
  - „Jedes Spiel soll in Steam aktiv stehen, auch Emulator oder fremde – das ging immer“: Seit 17.10. meldete Uzai bei
    angemeldetem Steam am PC keinen Status, und ohne Status zeigt Steam die Spielmeldung nicht (steam.log: „Spielt: …“,
    aber nie „Freunde sehen dich: …, spielt“). Jetzt meldet Uzai für die Spieldauer den Status, den Steam am PC schon hat
    (SteamCM.status_mit_pc), nie offline/unsichtbar, danach nichts; die Sitzung meldet sich sauber ab.
  - „Den Soundbit bei iiDB-Spielen auswählen, unter Artwork“: Bildwahl iiDB hat den Reiter „Klang“ (art_picker_iidb.gd);
    A wählt und spielt an, gemerkt als eigen (Iidb.gemerkt) – Uzai ersetzt ihn nicht mehr von selbst.
- 0.16.75 (headless: check 0 Fehler, lint 0, logic_schweben und logic_guidepanel grün; logic_guide wie gehabt am
  englischen Profil; im Fenster nicht angesehen):
  - „Beenden hat keine Umrandung, da sieht man die Auswahl – Weiterspielen hat eine weiße, mach es so wie Beenden, und
    das von eben weg“: Die Hauptaktion im Guide (_Action) ist keine helle Platte mehr, kein Ring, keine Taste auf
    dunkler Scheibe – sie sieht aus wie Beenden, nur fett; unter der Maus der Cursor halb.
  - „In der Spielseite dasselbe, da sieht man mit der Maus gar nichts“: Ruhige Knöpfe (U.ruhig) hatten unter der Maus
    dieselbe Fläche wie in Ruhe. Jetzt U.knopf_schweben: eine Spur heller und ein Schein im Akzent (schweben.gd).
- 0.16.74 (headless: check 0 Fehler, lint 0, logic_guidepanel und logic_schweben grün; logic_guide, logic_guidestart,
  logic_guidetasten scheitern hier wie schon auf 0.16.73 am englischen Profil; im Fenster nicht angesehen):
  - „Im Guide ist Weiterspielen weiß, aber die Auswahl sieht man nicht“: Die helle Hauptaktion (guide_spiel.gd _Action)
    tritt ungewählt etwas zurück; gewählt trägt sie einen Ring mit Schein im Akzent, unter der Maus halb.
- 0.16.73 (headless: check 0 Fehler, lint 0; logic_schweben, logic_eigene_spiele, logic_cursor, logic_ausblenden grün.
  logic_filme_ui, logic_medien, logic_bedienung, logic_startseite, logic_einstellungen scheitern hier – genauso schon auf
  0.16.72, denn das Profil auf diesem PC steht auf Englisch, die Tests erwarten deutsche Texte. Schein nicht im Fenster angesehen):
  - „Eigene Apps sollen unter Steam zu finden sein, ganz vorne mit dem Hinzufüge-Datum“: Library.by_tab("steam") nimmt
    die selbst hinzugefügten (Library.eigen) dazu; „Zuletzt“-Sortierung zählt bei ihnen max(gespielt, hinzugefügt).
  - „Die Spieleseite neu hinzugefügter Apps ist leer“: game_page._load_about sucht PC-, Epic-, EA- und eigene Spiele
    bei Steam nach dem Namen (Media.steam_match_id) und zeigt deren Angaben.
  - „Erst steht da DESKTOP“: GameFinder.name_for_pick nimmt den Namen der Verknüpfung; Desktop & Co. gelten als
    nichtssagende Ordner.
  - „ScreenScraper fehlt“: Öffentliche Pakete bringen den Zugang nicht mit. Er wird jetzt auch aus
    %APPDATA%\Uzai\screenscraper_dev.json gelesen (eigener PC, nie im Paket).
  - „Auswahl in der Bildwahl nur mit Q/E“: Reiter (Cover, Hintergrund …) und LB/RB sind anklickbar.
  - „Glow mit Maus zu schwach, oben gar keiner“: UzTheme.draw_tile_hover (kräftiger als der Auswahl-Schein), Reiter
    oben über tab_strip.strip_hover, alle anderen Kacheln über schweben.gd.
  - „Zweimal oben auf Zimmer/Browser öffnet es“: Klicks auf Reiter oben öffnen nie, nur A oder die Kachel im Bereich.
- 0.16.72 (headless geprüft, den Schein nicht im Fenster angesehen):
  - „Die Spiele brauchen einen Hover-Effekt … Streams, Filme mit Glow“: Kacheln leuchten unter der Maus mit dem Schein der Auswahl, leiser (UzTheme.HOVER_GLOW; cover_card, video_card – auch Streams –, movie_card: zeiger_schweben; schweben.gd meldet an und aus, auch beim Griff zum Controller und wenn die Maus das Fenster verlässt).
  - „Er öffnet direkt den Browser und das Zimmer, wenn man oben aufs Symbol klickt“: Godot gibt den Fokus schon beim Drücken, Nav.klicks „erst wählen“ griff darum nie. Reiter der Kopfleiste (uz_klick_waehlt_nur) fängt zeiger.gd ab: erster Klick zeigt, zweiter öffnet (logic_schweben).
- 0.16.71 (headless geprüft):
  - „Der Scroll ist ein wenig zu schnell“: Reihen per Schritt gehen mit dem Rad höchstens alle 160 ms einen Schritt, was dazwischen kommt, verfällt (zeiger.gd _schritte_rad; logic_schweben „schnell gedreht“).
  - „Einen Weg, ein Non-Steam-Game hinzuzufügen“: Den Dialog „Spiel hinzufügen“ (Programm oder Ordner, Punkt 117) gab es nur als Kachel am Ende von PC und Alle. Jetzt steht „Hinzufügen“ als Aktions-Chip hinter den Quellen (games.gd chip_aktionen, main._build_chips – reagiert nur auf A/Klick). Solche Spiele (Quelle pc) haben dieselben Optionen wie die anderen.
- 0.16.70 (headless geprüft):
  - Rückmeldung: „Videos, Filme und Streams soll man runterscrollen können, oder Klick halten um nach rechts“. Das Rad fand dort nichts Senkrechtes (die Reihen gleiten per Schritt) und rollte die Reihe unter dem Zeiger seitwärts. Jetzt geht es Reihe für Reihe – auch über der Bühne (medien_bereich.gd zeiger_schritt/zeiger_achse; zeiger.gd: liegt unter dem Zeiger nichts Rollbares, gilt die Auswahl). Ziehen mit gedrückter Maustaste rollt die Reihe seitwärts, ohne etwas zu öffnen (logic_schweben).
- 0.16.69 (headless geprüft):
  - Rückmeldung zu 0.16.68 („mit der Maus auf einem Tab, und er switcht direkt“, „der Rahmen bleibt kurz, fühlt sich verzögert an“): Klick-Modus. Darüberfahren wählt nirgends mehr, kein Rahmen; über Wählbarem ist der Zeiger eine Hand. Jeder Klick wählt sein Ziel und löst im selben Klick aus (zeiger.gd _vorher_fokus, schweben.gd; logic_schweben). Die Markierung `uz_kein_schweben` und `controller.mouse_hover` entfallen.
  - Unscharfes Bild am selben Abend: Windows lief auf 2560×1440 statt 3840×2160 (von außen umgestellt, nicht von Uzai) – kein Fehler in Uzai.
- 0.16.68 (am Windows-PC: 0.16.67 mit Maus und Tastatur durchgeklickt, die Änderungen headless geprüft – nicht mehr live geklickt):
  - Maus: Darüberfahren wählt erst nach kurzem Verweilen; vorher schalteten Kategorien beim Drüberstreifen um, und die Maus traf danach Zeilen der eben abgebauten Seite – die Auswahl saß unsichtbar fest (src/core/schweben.gd, Nav.hover_waehlen; logic_schweben). Ausgewertet wird nach Godots eigener Verarbeitung (vorher ein Ereignis zu spät). In Reihen, die mit der Auswahl gleiten, zeigt ein Rahmen, was ein Klick öffnet; über Wählbarem ist der Zeiger eine Hand.
  - Texteingabe mit echter Tastatur oder Maus ohne Tastenfeld, Pfeile schieben die Schreibmarke, Controller oder Finger klappen es auf (keyboard.gd _set_kompakt; logic_einstellungen).
- 0.16.67 (Tester-Paket, am Windows-PC gebaut und durchsucht):
  - Vor der Veröffentlichung: keine echten Namen mehr in Tests und Kommentaren (Beispielname „Robin“), das Bauskript nimmt den ScreenScraper-Zugang nur noch mit `UZAI_PRIVAT=1` mit. Das Paket enthält nachweislich keinen der echten Zugänge des Projektinhabers (Discord, Steam, YouTube, Nuvio, ScreenScraper), keinen Namen, keine E-Mail, keine Benutzerpfade, keinen PC-Namen und keine Heimnetz-Adresse.
- 0.16.66 (am Windows-PC gebaut, Bilder der Ebene und der Handy-Seite angesehen; mit einer fremden Discord-App nicht durchgespielt):
  - „Volle Discord-Steuerung“: Uzais Discord-App bekommt den Sprachkanal nur für freigeschaltete Konten, neue Freischaltungen vergibt Discord nicht mehr. Jeder legt darum mit dem Handy seine eigene App an (src/ui/layers/discord_eigen.gd): am Fernseher QR-Code und drei Zeilen, die Anleitung auf dem Handy samt der zwei Redirect-Adressen zum Kopieren (Remote.phone_form_begin mit steps, Feld mit Ziffern-Muster ohne Skript; logic_launcher_ra). Die App-ID übernimmt Voice.eigene_app_setzen (prüft 17–20 Ziffern, vergisst den alten Zugang) und verbindet gleich. Die Discord-Bibliothek im Paket gilt für jede App. Einstiege: Einstellungen → Konten → Discord, das Verbinden-Fenster und der Guide, wenn Uzais App abgelehnt wurde (Voice.tester_fehlt, Text Voice.TESTER_TEXT statt „eingetragene Tester“; test_logic).
- 0.16.65 (am Windows-PC geprüft):
  - Rückmeldung „Zufällig spielt zehnmal dasselbe Lied“: Lieblingssongs liefen als lose Liste, am PC also über Weg d – nur das Album des ersten Titels; bei einer Single mit „Liste wiederholen“ immer derselbe. Jetzt als Spotifys Kontext `spotify:user:<id>:collection` ab einem Titel (gemischt: ein zufälliger) (spotify_intern.gd liked_context, music_listen.gd liked_uri, track_page.gd; logic_musik). Die App am PC meldet dafür als Kontext eine eigene Playlist-Adresse – Uzai prüft darum am Titel. Am PC: läuft nach 0,4 s, zehn verschiedene Titel in der Warteschlange.
  - Abgelaufene Anmeldung: Nach einer 401 gab die Spotify-Seite denselben Schlüssel noch einmal heraus, die zweite 401 hielt Uzai für eine Ablehnung und merkte den Grundmodus zwölf Stunden (Bibliothek und Lieblingssongs leer). Jetzt verwirft Uzai den Schlüssel bei der Seite (schluessel_verwerfen), merkt eine 401 nicht über einen Neustart, und ein gemerkter Grundmodus prüft nach „Konto ja“ mit einer einzelnen Anfrage neu (music_spotify.gd).
- 0.16.64 (erstmals am Windows-PC selbst geprüft, Godot 4.5.1 für Windows):
  - Browser-Kern: Der Installer verwarf die CEF-Fassung nach zwei unbestätigten Starts („Installed version was removed before launch“), weil Uzai „gesund“ nur einmal je Einrichtung meldete und die Spotify-Sitzung nie. Jetzt meldet jeder gelungene Start, auch die Spotify-Sitzung (browser_wirt.gd _gesund, uzai-browser-kern.cs KernBefehl); am PC danach `confirmed:true`.
  - Fokus nach dem Start: Das unsichtbare Fenster der Spotify-Sitzung nahm Uzai rund 3 s nach dem Start den Vordergrund – die Ursache von „man muss kurz Guide drücken“. Der Kern gibt ihn jetzt zurück (UzcVorn); am PC nach 0,2 s wieder Uzai vorn.
  - Spotify am PC: lose Titellisten und ein Titel als eigener Kontext laden nichts (Wege a–c), Playlist und Album ab Titel laufen. Neuer Weg d: der Titel in seinem Album (spotify_intern.gd play_album, music_spotify.gd _album_von; logic_musik). Am PC: erst nach a–c, dann gemerkt und sofort (0,4 s).
- 0.16.63:
  - Rückmeldungen vom PC zu 0.16.62. Englisch: Abzeichen- und Level-Pop-ups, Steam-Erfolge aus Steams eigenen Dateien, der Filtername unter dem Spiel und Zahlen mit Tausendertrenner sind jetzt englisch (badge_popup.gd, unlocks.gd _lang, games.gd, buehne.gd, lang.gd; gemessen mit einer Probe auf Englisch, logic_englisch). Start: Eine Wache holt Uzai bis zum ersten Tastendruck nach vorn und schreibt mit, wer vorn lag (src/core/startwache.gd, main._start_vorn, logic_startwache) – die Ursache am PC ist nicht bewiesen, unter Windows lief nichts davon. Discord: Scheitert die Freigabe mit Uzais eigener App, nennt Uzai den Grund (nur eingetragene Tester) und den Weg (eigene App-ID).
- 0.16.62:
  - Rückmeldung vom PC zu 0.16.61 (Protokoll: dreimal „play → HTTP 200“, die Spotify-App wird aktiv und lädt nichts). Der Abspielbefehl hat jetzt die vollständige Form (spotify_intern.gd commands_for). Uzai sieht nach dem Befehl nach, ob das Gewünschte läuft, nimmt sonst den nächsten Weg und meldet am Ende klar, dass nichts gestartet ist (music_spotify.gd _connect_play; logic_musik, net_musik gegen den Nachbau mit den Schaltern streng, nurziel, nurtitel, haengt, stumm). Gegen Spotify selbst lief hier nichts.
- 0.16.61:
  - Spotify (aus dem Protokoll vom PC): Befehle gehen an die Spotify-App auf diesem PC, nicht an das zuletzt benutzte Gerät (system.spotify_ort, spotify_intern.gd pick_target, logic_musik); der Dealer versucht es nach einer Ablehnung sofort mit einem frischen Schlüssel (music_spotify.gd _dealer_ensure). Tonausgabe: festes Gerät, auf das Uzai zurückstellt, sobald es wieder da ist – über FxSound, wenn es den Ton führt, sonst über Windows (src/core/tonwahl.gd, logic_fxsound). FxSound aus Uzai: an/aus, Klangprofil, Starten über dessen eigene Kommandozeile (src/core/fxsound.gd, Helfer-Befehl fxsound; Befehlszeile geprüft in tests/helfer_cs.ps1). FxSound selbst lief hier nie.
- 0.16.60:
  - Rückmeldungen vom PC zu 0.16.59. Die Guide-Taste öffnet beim Drücken statt beim Loslassen; gehalten weicht der Guide dem Schnellmenü (guide_hold.gd druck, main_guide.gd _guide_press_done, logic_guidetasten). Die Seite hinter dem Guide steht ab dem Druck still: ein Abbild, nicht mehr nachgeführt, nach dem Schließen noch 0,35 s (main_fenster.gd seite_anhalten, seite_auftauen; Bild für Bild gemessen: außer der Abdunklung ändert sich nichts).
- 0.16.59:
  - Rückmeldungen vom PC zu 0.16.58. Guide: hoch und runter laufen am Rand um (nav.gd uz_umlauf, logic_umlauf), kein „Übertragen“ im Discord-Reiter, kein Knopf „Optionen“ am Spiel, die Uhr bleibt im Kopf auch mit „Mikro aus“ und langem Namen. Discord: Kanal-Listen nach dem Verlassen frisch (voice.gd _set_channel, test_logic), ein Mikro für alle Anzeigen und Schalter (Mixer.mic_aus, toggle_mic), X = Stumm in jeder Zeile. Steams Mitteilungs-Fenster unsichtbar, solange Uzai läuft (steam_still.gd, UzSteamStill im Helfer: übersetzt, Titelerkennung geprüft – unter Windows nie gelaufen).
- 0.16.58:
  - Guide: Die Chat-Spalte steht ganz rechts am Schirm statt direkt neben der Leiste (guide.gd pin_rect, logic_freunde).
- 0.16.57:
  - Rückmeldungen vom PC zu 0.16.56. Guide über dem Menü: die Seite dahinter als stehendes Bild (main_fenster.gd seite_anhalten, punktgenau gleich, gemessen halbe Zeit je Bild), kein Zurückrücken der Oberfläche mehr. Medien: Bühne 350 statt 400, die nächste Reihe angeschnitten (medien_reihen.gd anriss_sichtbar, logic_medien), keine Reihe „Weiterschauen“ bei YouTube. Erfolgs-Pop-up mit Beschreibung; Steams Guide-Taste von selbst aus (steam_guide.gd beim_start). Hauptknopf im Akzent getönt statt gefüllt (u.gd knopf_farben). Musik baut bei gleichen Daten nicht neu. Zimmer immer über die Tür und am Anfang (main.open_room).
- 0.16.56:
  - Meldungen vom PC zu 0.16.55. Start: Uzai sieht in den ersten Sekunden nach, ob sein Fenster vorn ist, und holt sich sonst nach vorn (main._start_vorn, logs/start.log). Bildschirm: wählbar (Einstellungen › Aussehen), Neustart mit eigener DPI-Behandlung bei mehreren Bildschirmen (src/core/bildschirm.gd, remote._scharf_neu_starten), Größe der Oberfläche je Bildschirm (logic_bildschirmwahl). Mit zwei Bildschirmen ließ sich hier nichts ausprobieren.
- 0.16.55:
  - Durchsicht des ganzen Quellcodes: Netz auf eigenem Faden (kein Stehenbleiben bei stummem Server), fremde Daten gehärtet, Regal/Raster/lange Listen in Scheiben (große Bibliothek), englische Lücken, toter Code 0 (tools/tot_code.py).
  - Fenster und Fokus, Spielstart, Mini-Video, Overlay im Spiel als Versuch (je Spiel, nie mit Anti-Cheat), iiDB als Quelle für Bilder und Spielklang, Zimmer online eingeschaltet (docs/ZIMMER_SICHERHEIT.md).
  - Entscheidungen vom 12.11.: Theme-System, große Freunde-Karte und räumliches Zeichen entfernt; Land für Preise folgt der Sprache (logic_sprache, logic_shop); Aufrufe mit festem Typ (761 → 438 über den Namen). Kompilierprüfung 0 Fehler, Lint 0 Fehler, gezielte Logik-Tests und Bildproben; keine ganze Testreihe.
- 0.16.54:
  - Freundestest 0.16.53: Mini-Video nur über Uzai und Spiel (Lage „fremd“), Guide öffnet beim Mini-Video die Videosteuerung zuerst und pausiert nicht mehr, gleich laut, Streamwechsel ersetzt das kleine Video, Video-Leiste übersetzt (logic_bild_in_bild); Profil-Unterbereiche ohne Sprung (geteilte Zimmer-Welt, U.takt_halten), Seitenleisten automatisch geprüft (logic_leisten_rand), Einstellungen: Steuerkreuz bewegt, A ändert (logic_einstellungen_steuerkreuz); Steam-Nachrichten neben Steam am PC (Zustand steam.nachrichten, logic_mitteilungen), Einrichtung wird einmal angeboten, wenn sie nie abgeschlossen wurde (logic_einrichtung, logic_erststart).
- 0.16.53:
  - Zustandsautomaten: 54 Automaten mit Tabelle oder Meldung (src/core/zustand.gd, tools/zustaende.py im Lint), Verstöße als Testfehler, Stand aller Automaten im Fehlerbericht. Behoben: Emulator-Suche der Einrichtung, Link-Vorschau, Fernsehbild-Rückfall je Spiel, Nuvio-QR, Jellyfin-Passwort, „Nochmal versuchen“ bei Stremio/Plex, Discord „Verbindet …“. Meldungen ohne rohe Codes (Filmkataloge nennen den Grund in Worten, logic_konsistenz grün), probe_umbau auf dem Y-Menü des Regals.
- 0.16.52:
  - Freundestest: Player richtet sich selbst ein (7-Zip unter Windows 10, player.log), Katalog-Gründe in filme.log, Steam-Pop-ups auch bei offen gelassenem Chat, neue Nachrichten oben im Guide, Chat angeheftet neben dem Guide, Spielsymbol in Verknüpfungen, Einrichtung übersteht Umbau beim ersten Start, Guide über exklusivem Vollbild (Spiel kurz minimiert), Alt-Tab ohne Einfrieren, ruhigere Untermenüs, Rückfrage mit Halten vor PC aus/neu.
- 0.16.51:
  - Englisch lückenlos (Messung probe_englisch, logic_englisch, tools/i18n_luecken.py); Einrichtung: Konten mittig in zwei Spalten, ruhige leere Zustände (Emulatoren, Spiele).
- 0.16.50:
  - Einrichtung: Konten nach Bereichen (Steam/Discord groß), Emulator-Stand ehrlich (Bereit/Kann geladen werden/Von Hand), kein Überspringen, einheitliche Knöpfe, Cover landen ohne Schweben in der Startseite (logic_einrichtung, logic_startseite).
- 0.16.49:
  - Zimmer-Vorlagen nur noch hell: Kino-Ecke und Neon-Höhle entfernt (vorlagen.gd).
- 0.16.48:
  - Zimmerlicht wie vor 0.16.39 (Lampenstärke voll, Abprall, TV-Licht 0,9; neue TV-Marke bleibt).
  - Spotify: Playlists ohne Anzahl aus libraryV3 → Anzahl über /me/playlists nachgeladen, unbekannt statt „0 Titel“; „Dieser PC“ immer in der Geräteauswahl (startet die Spotify-App).
- 0.16.47:
  - Spotify: alle Abrufe im Seitenmodus per fetch() in der angemeldeten Webplayer-Seite (spotify-abfrage/-antwort, feste Hosts, Kern nach 2 min Leerlauf zu), Diagnose in spotify.log.
- 0.16.46:
  - Spotify-Anmeldung: nach der Anmeldung (Webplayer) wird die Seite sofort verdeckt, Uzai-Zustand davor, nach 15 s ohne Schlüssel trotzdem zu (browser.gd _spotify_seite, Protokoll in browser_kern.log).
- 0.16.45:
  - Spotify: „Mit Spotify anmelden“ über die echte Anmeldeseite im Uzai-Browser, Schlüssel aus dem unsichtbaren Webplayer (Kopfzeilen, kein TOTP-Nachbau), Grundmodus als Rückfall, spotify:-Adressen ohne Premium; QR-Weg entfernt (logic_musik, logic_browser_kern).
- 0.16.44:
  - Zimmerlicht wieder wie 0.16.42 (Änderung aus 0.16.43 rückgängig, Nutzerwunsch).
- 0.16.43:
  - Zimmerlicht: Grundlicht abends/nachts, Ausgleich dunkler Hüllen (bis 16×, gedeckelt), Kontrast in der Farbkurve ohne Abschneiden, Tischlampe 3,4 m (logic_zgrafik Mindest-Grundhelle je Vorlage).
  - ScreenScraper für alle Spiele (PC Windows 138/Dos 135, Namenssuche, Jahr als Entscheider), Bildwahl und „Spiele scrapen“ für alle (logic_screenscraper).
  - Musik: leerer Ordner zeigt Bühne mit Ordner/Spotify/Neu einlesen. Texte im Systemton, Anmeldungen ohne Warnhinweise, Tour ohne Ortsangaben.
- 0.16.42:
  - Zimmer online Freundestest (nur Testbetrieb, ohne Admin, nach bestandener Abschottung): Einladungscode UZAI-7×5 mit Prüfzeichen + QR, Anklopfen/Annehmen/Sperren, Besucherfigur mit Emotes/Schnellsätzen, Gast sieht Zimmer nur als Kopie (einladung.gd, freundestest.gd, logic_freundestest, net_zimmer_treff).
- 0.16.41:
  - Browser-Zeiger: Totzone 0,14, Kurve x^2,6, Tempo in Bildbreiten/s (Menü), Schub, LB/RB fein, Magnet mit Einrasten, Steuerkreuz-Sprung mit Rücksprung, weiches Rollen mit Seitenende (browser_zeiger.gd, logic_browser).
- 0.16.40:
  - Quellenliste: Dateiname, Sprachen (Flaggen/Wörter/Kürzel), Ton, Herkunft, Container, Original-Beschreibung; Sprachfilter X, „Sprache zuerst“ (movies_quelle.gd, logic_filme_quellen).
- 0.16.39:
  - Zimmerlicht: Lampen 0,55/Reichweite 0,75, Schirmlampen als Kegel, mehr Abprall, Lichterketten vor der Wand, Fernsehlicht 0,55; Fernseher/Schnappschuss mit neuer Marke.
- 0.16.38:
  - Browser: Pad ohne Fensterfokus während einer Seite, ein Kern je Sitzung (Warten/Beenden), Ende ohne „absturz“, iframes als Ziel „rahmen“ (Zeiger), Leitung gesamt im Protokoll.
- 0.16.37:
  - Browser: „bereit“ wurde wegen 32-Zeichen-Grenze der Fassung verworfen (jetzt 96); Verworfenes wird gemeldet; Z1 nur ohne jede Zeile; Google Standardsuche.
- 0.16.36:
  - Browser: Start-Stummel verglich „\\libcef.dll“ um ein Zeichen versetzt (jeder Unterprozess Code 205 → GPU FATAL); Stummel erneuern am PC; Grafik-Rückfall auf Software.
- 0.16.35:
  - Zimmer-Leitung: Ausgangs-Warteschlange mit 3-KiB-Fenster und QUITTUNG (Windows-Pipe ohne Warten verlor Rahmen), Sandbox-Fassung 5, ZAEHLER mit Rein.
- 0.16.34:
  - Browser-Kern: Gründe mit Codes (K…, S…, H…, P…, Z1, Exitcodes) im Protokoll und im Hinweis; debug.log/stderr-Auszug.
- 0.16.33:
  - Browser-Kern: <abi>_windows64.json in den Spiegel (Installer liest es bei gesetztem ABI-Hash), vmax = vmin.
  - Prüfmauer-Test: Flut in einem Stück; Zähler im Fehlertext.
- 0.16.32:
  - Sandbox: DETACHED_PROCESS statt CREATE_NO_WINDOW (conhost zählte im Job mit ActiveProcessLimit 1 → 0xC0000142).
- 0.16.31:
  - Sandbox: Container darf den eigenen Programmordner lesen (nicht vererbt); ohne Echo meldet die Probe den Code des Kindprozesses.
- 0.16.30:
  - Sandbox-Start: Umgebung mit APPDATA/LOCALAPPDATA/USERPROFILE auf den eigenen Container-Ordner, sortiert (CreateProcess 203 am PC).
- 0.16.29:
  - UzKernPack: Hauptordner beliebig (signierte heißt nicht cef_binary_…), Hauptordner im Protokoll.
  - Abschottung prüfen: Ergebnis aus Helper.run().result statt der Hülle; Grund bei Fehlschlag.
- 0.16.28:
  - Einrichtung: Intro-Marke ohne Kachel, 3D-Retro-Zimmer mit PSX-Figuren, Schauen & Hören mit echten Medien, Einpassen bei jeder Fenstergröße, gestaffelter Aufbau der Startseite; Zimmer-Tür geht beim Bereichswechsel sofort.
- 0.16.27:
  - Beenden: zweiter Druck/hängendes Fenster sofort hart, Wächter 25 s, Vorhang „schliessen“ nur mit Loch um Spielfenster, Guide-Wahl bei „läuft noch“.
  - Spiele scrapen: Quelle wählbar, „Alles ersetzen“ ersetzt (eigene Dateinamen je Adresse, Neuaufbau), Mitteilung je Quelle, logs/scrape.log; ScreenScraper-Bildwahl je Spiel.
- 0.16.26:
  - Browser-Kern: minimal-Verteilung aus index.json (Meilenstein-Liste führt nur signierte Bauten), Rückfall .sha1.
  - Intro-Licht auf entstufter Lage; Profilbilder in der Freundes-Auswahl; Einrichtung endet auch aus den Einstellungen auf der Startseite.
- 0.16.25:
  - boot.gd: Typ der Wortmarken-Breite (0.16.24 ließ sich nicht übersetzen).
- 0.16.24:
  - Zimmer online: libsecp256k1 (Signatur) und libdatachannel (Datenkanal) nur in der Sandbox, gepinnt und bit-gleich gebaut; BEREIT aus, Testbetrieb.
  - Spiele scrapen: Einrichtung von selbst, Bibliothek und Für dich immer sichtbar.
- 0.16.23:
  - Intro: kleine flache Wortmarke UZAI unter dem U am Ende; ScreenScraper-Programmzugang im Paket (nicht im Repo).
- 0.16.22:
  - Hüllen: Scan unverändert unter Folie, Kunststoff/Scharnier/CD-Hülle/Karton je System, Band nur ohne Scan.
  - Browser-Kern: bootstrap.exe aus der minimal-Verteilung derselben Fassung (eigener bzip2-Leser, CRC je Block).
- 0.16.21:
  - Zimmer online Phase 3: verschlüsselter Treffpunkt in der Sandbox (AES-GCM aus CNG, ECDH), nur Test-Relay; BEREIT aus.
  - logic_konsolenstart wartet aufs Logo nach der Uhr statt nach 60 Bildern.
- 0.16.20:
  - Intro nur mit dem U (größer, mittig), ohne Wortmarke, Gruß, Status und Kachel.
- 0.16.19:
  - UzKernPack findet bootstrap.exe/chrome_elf.dll an jeder Stelle (Release/ bevorzugt, Debug/ nie); Archiv-Übersicht im Protokoll.
- 0.16.18:
  - Export nimmt alle Browser-Dateien mit (helper/*.cs, *.js, assets/browser/cef, filter); Kern wartet auf den Helfer;
    Zimmer-Tür ohne Kopf von innen.
- 0.16.17:
  - Zimmer: verdeckte Möbel und Bilder wählbar, Kissen ohne Schnitt, Garderobe direkt im Zimmer (figur/garderobe.gd),
    Backen ohne schwarze Wände, Ankunft hinter der Tür, 24 neue eigene Möbel (src/room/moebel_mehr.gd).
  - Browser-Kern lädt beim ersten Öffnen von selbst (browser_kern_lauf.gd, eigener Entpacker UzKernPack im Helfer);
    Controller koppeln mit aktiver Bluetooth-Suche, „Neu koppeln“, bis zu 4 (koppeln.gd, pad_pair.gd).
- 0.16.16:
  - Start-Intro hängerfest (Uhr startet nach ruhigen Bildern), Shader-Systemstarts wieder Standard (3D wählbar),
    Hüllen je System nach echten Maßen, Profil-Freunde parallel mit Zwischenspeicher (beim Abmelden gelöscht).
  - „+“ oben entfällt (App hinzufügen in Einstellungen), Reiter „Eigene Musik“ mit Ordnerwahl, ScreenScraper-Konto.
- 0.16.15:
  - Uzai Browser mit eigenem Chromium-Kern (CEF, Sandbox Pflicht; src/core/browser_kern.gd):
    Laden beim ersten Öffnen mit Prüfsummen, Updates mit Rückfall, Blocker (EasyList, CC BY-SA 3.0), Startbühne.
    CEF selbst nur unter Windows prüfbar (hier keine Binärdateien).
- 0.16.14:
  - Zeichen: flaches U-Symbol als Vektor (src/ui/components/uzai_logo.gd), ruhiger 2D-Start mit eigenem Akkord,
    Kopfzeile im Textton; Einrichtung mit echten Inhalten bzw. eigenen Bildern, Emulator-Liste mit Logos (Laufzeit).
  - Spiele scrapen (src/ui/layers/spiele_scrapen.gd) mit ScreenScraper (src/core/screenscraper.gd, Programmzugang nur
    im Paket) und SteamGridDB; eigene Screenshots im eigenen Abschnitt; Cover im Guide-Start zuverlässiger.
  - Zimmer: Tür als ganze Fläche mit Fahrt ins Zimmer, Fernseher als randloses Vollbild (Guide fährt zurück), volle
    Bildrate neben dem Spiel; Regal mit Hüllen wie im Hauptmenü. Musik: Spotify und eigene Musik zugleich.
  - Medien-Reihen: angeschnittene Reihe unten blendet aus.
- 0.16.13:
  - Marke „U-Band“ (src/ui/marke_3d.gd, vorgerendert mit tools/marke_rendern.gd), in der Kopfzeile nur das U; Start
    als 3D-Szene mit Studio, Funken und eigenem Klang (tools/synth_start.py); Standard-Akzent #A47BFF; System-Starts
    für PS2, GameCube, PlayStation, N64 und Switch als 3D-Szenen (src/ui/components/system_buehne.gd).
  - Zimmer: Jackenständer statt Spiegel (keine zweite Ansicht mehr), Guide 2× steht auf (src/core/guide_doppel.gd),
    Fensterbank ohne Z-Fighting; Umbauen beim Laufen (src/room/zimmer_umbau.gd), Wände ziehen, Hüllen von Hand,
    Regal mit mehreren Systemen.
  - Beenden: beide Tresor-Fäden werden abgewartet (gelegentlich Signal 11 beim Beenden).
- 0.16.12:
  - Zimmer neben dem Spiel: Kappe = kleinster ganzer Teiler der Bildschirmrate ≥ 60 (Leistung.spiel_kappe), in jeder
    Stufe; schlanker Weg (FSR 1, FXAA, ohne SSAO/SSR/SSIL/Glühen/Nebel, Spiegel als Standbild); Ruckler je Bild gemessen.
  - Keine Pipeline-Übersetzungen beim Zeichnen: Schattenqualität im Zimmer fest (nur bei echtem Wechsel gesetzt), MSAA-
    und 32-Bit-Schatten-Varianten vorab angelegt (probe_zimmerbild --pipelines: 764 → 0).
  - Bauen: Möbel erst wählen, dann am Cursor platzieren (zimmer_einrichten.gd); Feld darunter klar grün/rot.
- 0.16.11:
  - Marke „Schale und Kern“ (src/ui/components/uzai_logo.gd, icon.svg, uzai.ico), Start im Licht des Kerns; Material
    „Kernlicht“ (src/ui/kernlicht.gdshader) für Guide, Schnellmenü, Leisten und Dialoge; System-Intros mit Kamera,
    Staub, Höhepunkt und Flug in die Karte; Spielbild mit leichtem Grading.
  - Einrichtung: Vorstellung (Emulatoren, Guide, Zimmer, Schauen & Hören) mit Lichtring in die Startseite; Konten
    nach Bereichen zugeklappt; „Alles eingerichtet“ statt „Keine Emulatoren“; Steams Guide-Taste aus
    (src/core/steam_guide.gd, nur Controller_CheckGuideButton in localconfig.vdf, Sicherung, Steam geschlossen).
  - Zimmer: Bau-Menü mit Bereichen, großen Kacheln und Probe im Zimmer, Regal-Tafel mit echten Hüllen; Fenster ohne
    Flackern, draußen rundum; Schild unter dem Fernseher; neben dem Spiel Bildschirmrate, PCSX2 und yuzu & Co.
    halten bei Fokusverlust; Tür als Eingang.
  - Emulatoren: Spieler 2–4 automatisch (PS1/PS2 über Multitap an Anschluss 1, Eden & Co. mit der Belegung des
    gleichen Modells).
  - Komfort: Schlaf-Timer, Nicht stören, Nachts leiser, Melden wenn online, Mitteilungen leeren,
    Controller im Ruhemodus aus, Nur hören.
  - Uzai-Browser: eigener Wirt mit WebView2 (helper/uzai-browser-wirt.cs), Fokus-Karte,
    Tabs, Zoom, Lesemodus, Fernbedienung; nur am Windows-PC wirklich prüfbar.
- 0.16.10:
  - Zimmer: Licht der Hülle vorberechnet (src/room/lichtbacken.gd, neu bei jeder Änderung), ohne SDFGI/SSIL/SSR/FSR 2
    je Bild, Schatten nur bei Bewegung; Ziel ist die Bildrate des Bildschirms; kein Glimmen und kein Schild auf
    Möbeln mit Bildschirm (A steht im Tastenhinweis).
  - Figuren aus „Characters PSX“ (assets/figur/psx, src/room/figur/figur_psx.gd): 19 Menschen zur Wahl (drei
    über Meilensteine), gleiche Knochen und Posen; Kopfteile, Brillen, Kopfhörer und Schal bleiben; die
    selbst gebaute Figur ist entfernt. Figur-Nachricht im Netz 13 Byte (Sandbox-Schema angepasst).
- 0.16.9:
  - Zimmer-Leistung (src/room/leistung.gd): 60 Bilder/s in Bewegung, ~30 in Ruhe, dynamische Auflösung, FSR 2.2
    statt MSAA auf Hoch/Ultra, Reflexionssonde nicht mehr je Fernseher-Flackern, Automatisch lernt je Grafikkarte.
- 0.16.8:
  - Zimmer: Mipmaps für alle Karten, Rauschen fest statt je Bild, Schatten ohne Schraffur, feste Belichtung je
    Tageszeit, 3D in echter Auflösung; Fernseher farbtreu ohne Glimmen. Fernseher steuerbar nur im Fokus,
    Spielton aus dem Fernseher (raum-ton), leere Regale zum Selbstfüllen. Schnellmenü anpassbar
    (system.quick_tiles). Handpan: Bestätigen kurz. Ruhebildschirm nur scharfe Bilder, Fahrt ohne Wackeln.
    Freunde: Spielname fremder Steam-Spiele aus dem Shop, Discord nur als Zeichen.
- 0.16.7:
  - Handpan: Reiter (tab) nur noch in einer Fassung (F4), kein Wechsel zwischen tiefem und hellem Ton beim Blättern.
- 0.16.6:
  - Klangsatz Handpan (Standard, tools/synth_klang5.py) für alle Menüklänge und die Einrichtung; Samt wird
    einmalig zu Handpan (theme.rev 14), alle alten Sätze bleiben wählbar; Sfx nimmt freie oder verstummte Spieler zuerst.
- 0.16.5:
  - Klangsätze Samt (Standard), Kiesel, Pad, Haptik; PS2/PS1-Hüllen originalgetreu (Band vorn, PAL-Rücken),
    Einrichtung mit fünf Schritten und großem Intro ohne Banding; Zimmer-Fernseher (HDR, randloses PCSX2,
    Spiegel-Rückfall) und sparsame Grafik beim Aufstehen.
- 0.16.4:
  - Neue Einrichtung im 3D-Raum (Einschalten, Hüllen ziehen ein, Deine Konsole, Guide über eigenem Spiel, Punkt
    landet auf dem i), Klangbett und Einrichtungsklänge in E; Hüllen mit Systemrahmen und passendem Coverformat.
- 0.16.3:
  - Konsolen als 3D-Regal mit Spielehüllen (Mosaik weiter wählbar),
    Spieler 1 im Emulator = benutzter Controller (PCSX2 über XInput, richtige Einstellungsdatei), Klangsatz
    „Perle“, Videos in SDR mit fester Bildrate, Profil mit Steam unter der Vitrine, Bild in Bild im Schnellmenü.
- 0.16.2:
  - Controller-Belegung für Emulatoren automatisch (2–4 Spieler), Einrichtung mit Guide, Freunden und
    Überblick, lokale Musik als Standard ohne Spotify, Retro-Bühne, „Für dich“ neu, Ausschalten klarer.
- 0.16.1:
  - Steam-Erfolge aus dem Steam-Ordner bzw. Chat-Server, Status aus Steam am PC; Medien laden schneller;
    Mosaik mit Einführung und „A halten“.
- 0.16.0:
  - Jetzt läuft groß mit Liedtext (LRCLIB), Apps mit Controller-Tastatur, ohne Titelleiste und mit Leitfaden,
    Spiel live im Zimmer-Fernseher, YouTube ohne Ruckler und mit Abos, Hinweistexte im Konsolen-Ton.
- 0.15.1:
  - Spotify-Grundmodus mit ganzer Bibliothek aus der PC-App, Steam-Status neben Steam am PC, Mosaik in Glas,
    Ruhemodus mit Diashow, Guide mit Glocke, Zimmer scharf, Nuvio in den Filme-Quellen.
- 0.15.0:
  - Einrichtung als Konsolen-Moment: fünf Schritte, mit A durchklickbar, Spielesuche mit fliegenden Covern,
    Ende löst sich in die Startseite auf.
  - Nicht eingerichtete Bereiche zeigen eine ruhige Bühne mit Vorschau und richten mit einem Druck ein.
- 0.14.0:
  - Zimmer realistisch (Forward+ mit GI, PBR-Materialien, MakeHuman-Figur, 21 neue Möbel), Bewegung und
    Kamera wie Source; Grafik „Kompatibel“ als Rückweg unter Einstellungen › System.
  - Premium-Durchgang (Lichtkante statt Kontur, neue Knöpfe, weniger Text), neue Leiste oben, Freunde auf Select.
  - Shop, Erfolge, Guide, Einstellungen, Spielseite und Profil, Medien-Apps neu; Mosaik je Konsole und Ordner.
  - Ein- und Ausschalten neu, Startanimationen je Konsole scharf bis 4K, Spotify-Grundmodus ohne eigene App.
- 0.13.0:
  - Weicher, Konsolen-Gefühl, gefüllter Cursor; Start mit Licht und Einrichtung als Vorstellung; Themes vorerst aus.
  - Konten ohne eigene IDs (Discord mit eingebauter App, Spotify gebremst mit Grundmodus, Steam neben Steam am
    PC, SteamGridDB für den ganzen PC); Discord Social SDK im Windows-Paket, nur mit Discords Signatur geladen.
  - Zimmer: Modus-Leiste, Aktionen am Möbel, Ego-Kamera und Bewegung, Guide beim TV-Spiel, Plattenspieler mit
    laufender Musik, nachempfundene Konsolen im Lowboard.
  - Spieler & Controller für Emulatoren, Store-Apps im Vollbild mit Controller, Startanimation je Konsole,
    Klangsatz „Filz & Glas“; echte Konsolen-Logos zur Laufzeit, Retro-Katalog entfernt, Medienserver aus dem Weg.
- 0.12.0:
  - Gefühl: ein Bewegungs-Takt, gleitender Cursor, Kreuzen statt Loch, Seiten mit Fläche vor Schrift, keine
    Geister-Titel, Mitteilungen weichen aus, Guide- und Start-Signatur; Klangregeln und drei neue Klangsätze.
  - Apps: Store-Apps und eigene Programme; Zimmer online Phase 1–2 (Protokoll v2, Sandbox), weiterhin aus.
  - Lavendel als Akzent; Testrunner, Regeln und Pläne im Projekt (`tools/run_tests.sh`).
- 0.11.0:
  - Neue Marke: IBM Plex, U-Zeichen mit Punkt, eckig und matt, ein Cursor; alle Menüs, Blätter, Dialoge
    und das Zimmer in derselben Listen-Sprache; Guide als Seitenleiste.
  - Leiste Spiele · Shop · Freunde · Profil · Apps · Einstellungen; Apps wie Spiele, Quellen und Apps per
    langem A ordnen, ausblenden, zurückholen; Zimmer direkt im Raum einrichten.
  - Spielstart/-ende ohne Desktop, Beenden über den Prozessbaum, Epic-Anmeldung per Einmal-Code,
    Discord-Freunde wie Steam, Eingaben an Fenster gehärtet; Museum und „Heute legal spielen“ entfernt.
- 0.10.0:
  - Themes: geprüfte Theme-Pakete, eigene Oberflächen-Sprache, sieben eingebaute Themes mit eigener
    Startseite, Guide, Dialogen und Pop-ups; Theme-Editor, Startseite zum Selberbauen, Teilen per Datei/QR.
  - Dein Zimmer: alles anpassbar, Möbel-Baukasten, Stimmungen, Lichtkonzept mit drei Grafikstufen,
    Figur und Haustier, Fernseher zeigt das laufende Spiel, Zimmer teilen, Fotomodus; Online-Fundament (aus).
  - Mehrere Profile mit PIN und Kinderprofil; Einrichtung in fünf Schritten, Controller koppeln, Uzai-Doktor.
  - Weitere Launcher (GOG, Ubisoft, Battle.net, Xbox, Amazon, itch.io, Riot); Filme aus Plex, Jellyfin,
    Emby und Stremio-Konto.
  - Sicherheitsprüfung wie ein Pentest, Funde behoben, `docs/SECURITY.md`.
- 0.9.0:
  - Erster Start mit QR-Konten und kurzer Tour, Startseite sofort voll; Englisch als zweite Sprache.
  - Bibliothek: globale Suche, Filter, Abschnitte und Ansichten, eigene Felder (Tags, Kategorie,
    Freigabe, Region, Links nur als QR) und Mehrfachbearbeitung; Spielseite mit „Fast geschafft“,
    Neuigkeiten, Erweiterungen, Bewertungen und Verlauf der Runden; Zusammenfassung nach dem Spielen.
  - Guide: Schnellmenü per langem Druck, eigene Kacheln, Guide passend zur Lage, Lautstärke-Mixer,
    Mikro mit einem Druck stumm, Lösungshilfe als Bild in Bild.
  - Hilfe: hängendes Spiel sofort beenden (nie Windows, Launcher oder Uzai, nie mit Adminrechten),
    Absturz erkennen mit Tipps, Erste Hilfe, Controller-Problemlöser.
  - Speicher vor dem Installieren und Seite „Speicher“ (Aufräumen nur von Uzais eigenen Daten);
    Rückgängig nach Änderungen; Ruhebildschirm; leichter Modus für schwache PCs.
  - YouTube-Shorts, Ton im Hintergrund, SponsorBlock nur mit Hash-Präfix; Discord-Status mit Cover;
    Freundschaftsanfragen; „Was ist neu“ nach einem Update.
  - Am echten Windows-PC noch zu prüfen: alles, was der Helfer neu kann (Mixer, Mikro, Guide-Taste
    halten, hängende Spiele, Laufwerke), Steam-Deinstallieren, Anfragen annehmen, mpv mit Shorts.
- 0.8.3:
  - Phase 0 der Roadmap (Fehler und Rechtliches):
    - Guide → Profil → Aufnahmen bzw. Abzeichen: B führt zurück ins Profil statt aus dem Guide.
    - Controller-Akku: Bluetooth-Xbox-Controller meldeten über XInput „Kabel“ (Uzai zeigte nur
      „lädt“). Den Stand liest Uzai jetzt zusätzlich über Windows.Gaming.Input (Prozent, lädt).
    - Filme-Player: Tonspur und Untertitel-Spur wählbar (Y → Wiedergabe), die gewählte Sprache
      gilt beim nächsten Film zuerst.
    - Steam-Freunde standen kurz nach dem Schreiben alle auf „offline“: Ihren Status übernimmt Uzai
      nur noch aus einer Sitzung mit eigenem Status, und der offene Chat hält neben Steam am PC
      keine zweite Sitzung mehr dauerhaft offen (er sieht dann alle 20 s statt alle 4 s nach).
    - Rechtliches: kein Beispiel-Addon mehr im README, Plugins neutral beschrieben, Konsolen-Logos
      auf den Abzeichen nur noch auf Wunsch (Standard: aus), der inoffizielle Spotify-Weg erst nach
      Hinweis und ausdrücklicher Wahl.
    - Getestet: Logik- und Netz-Tests mit nachgebauten Servern, Proben mit Bildschirmfotos. Nicht
      getestet: echte Controller, echtes mpv, echtes Steam unter Windows.
  - Spielstart: Uzais Startbildschirm bleibt vorn (über Taskleiste, Emulator- und Starterfenstern,
    ohne Mauszeiger), bis das Spiel vorn im Vollbild ist; Dialoge unterwegs bleiben sichtbar.
    Vorher ging Uzai schon beim ersten neuen Fenster aus dem Weg (oft das Fenster vor dem
    Vollbild), und die Taskleiste kam über Uzai, sobald das Spiel den Fokus hatte.
  - Discord *Übertragen*: Die Taste kommt wie von einer echten Tastatur (linke Strg/Umschalt/Alt
    statt der allgemeinen Tasten, SendInput mit Scan-Nummer, 150 ms gehalten statt 60 ms), erst
    wenn das Spiel vorn ist; beim Video an mpv, wenn mpv vorn liegt. Unbekannte Tastennamen fielen
    früher still weg (aus `STRG+UMSCHALT+F9` wurde F9) – jetzt verstanden bzw. gemeldet. Mitteilung
    bei fehlender Discord-App, ohne Sprachkanal, bei Adminrechten; *Übertragung prüfen*;
    Protokoll in `discord.log`.
  - Guide-Taste im Film/Video (mpv vorn): Der Guide lag unsichtbar hinter dem Video (mpv gibt
    „immer oben“ ab und landet dabei über Uzai), man sah nur die Pause. Jetzt liegt Uzai, solange
    ein Menü über dem Video offen ist, ganz oben.
  - Lossless Scaling: Kürzel nur, wenn das Spiel wirklich vorn liegt (sonst Meldung), nach dem
    Guide; Prüfung, ob das Bild von Lossless Scaling erscheint; „Bei Emulator-Spielen“
    automatisch; genaues Protokoll.
  - Nicht unter Windows getestet; geprüft: Logik in `tests/logic_guide.tscn`/`tests/test_logic.tscn`,
    Helfer übersetzt und gestartet mit PowerShell 7.
  - Nuvio schnell: Nach dem ersten Abgleich holt Uzai nur noch Änderungen (Nuvios Änderungs-Cursor
    für Bibliothek, Fortschritt, Verlauf), Anfragen laufen gleichzeitig auf eigenen Netz-Plätzen
    (Bilder und Kataloge werden nicht ausgebremst), Addon-Manifeste gleichzeitig, kein Abgleich
    während Spiel oder Film, Zustand in eigener Datei `nuvio.json` statt in den Einstellungen, in
    Nuvio ausgeblendete Kataloge werden gar nicht erst geladen, Startseite baut nur bei echten
    Änderungen neu. „Weiterschauen“ für große Bibliotheken rund 6× schneller und zwischengespeichert
    (`tests/perf_nuvio.tscn`: 511 → 85 ms bei 400 Serien × 200 Folgen, danach 0 ms). Protokoll:
    `logs/nuvio.log`.
  - Guide → Freunde: Steam und Discord werden nicht mehr nach gleichem Namen zusammengelegt.
  - Eingehende Discord-Anrufe: Karte mittig über dem Guide mit „Annehmen“/„Ignorieren“; im Spiel
    ein Pop-up, die Guide-Taste öffnet die Karte. Erkannt über die lokale Discord-Schnittstelle
    (Sprachstatus der Direktnachricht, nachgeprüft mit GET_CHANNEL); Annehmen tritt dem Anruf bei.
    Getestet mit nachgebauten Discord-Nachrichten, nicht mit echtem Discord.
- 0.8.2:
  - Filme: Anmeldung mit dem Nuvio-Konto (QR-Code wie Nuvio TV oder E-Mail/Passwort), Abgleich von
    Profilen, Addons, Plugins, Bibliothek, Weiterschauen, Gesehen und dem Startseiten-Layout
    (Reihenfolge, ausgeblendet, eigene Titel, Sammlungen, Titelbild) in beide Richtungen.
    Getestet gegen eine nachgebaute Nuvio-API (`tests/fake_nuvio.py`, `tests/net_nuvio.tscn`, 42
    Prüfungen); gegen das echte api.nuvio.tv nicht (hier gesperrt).
  - Discord: „Already authenticated“ trennt die Verbindung nicht mehr (Guide-Reiter Discord bleibt);
    Direktnachrichten als Pop-up auch im Spiel, Guide-Taste danach öffnet den Chat (auch außerhalb
    des Spiels); Discord-Freunde anrufen über das Menü (die Discord-App tritt dem Anruf der
    Direktnachricht bei, Uzai bleibt vorn); Discord-Profil in Uzai (Status, Spiel mit Rich Presence,
    Sprachkanal, gemeinsame Server, Nachricht, Anrufen).
  - Guide → Freunde nach Quelle getrennt (Steam, Discord) mit Spiel und „im Spiel/online“ je Gruppe.
  - Steam-Mitteilungen: Uzai holt den eigenen Status jetzt selbst (ohne Web-API-Schlüssel), damit
    Steam Nachrichten sofort schickt; `logs/steam.log` schreibt mit, warum ein Pop-up kam oder nicht.
- 0.8.1:
  - Remote Play Together ausgebaut: Spieler 2 wird für die Sitzung automatisch eingerichtet
    (PCSX2, DuckStation, Dolphin GC/Wii, Eden/Citron/Sudachi/yuzu) und danach zurückgestellt,
    „Spieler 2 ist verbunden“ als Mitteilung, Hinweis wenn nach der Einladung keiner kommt,
    Prüfung auf Adminrechte vor dem Start, PC-Spiele auf Wunsch immer, Epic-Spiele ohne
    Kopierschutz pro Spiel. Starter Version 2 (meldet Controller und Fehler 740); Uzai tauscht
    den alten Starter beim nächsten Start still aus.
  - Getestet: INI-Bearbeitung und Rücksicherung mit nachgebauten Dateien der Emulatoren
    (`tests/logic_remoteplay.tscn`), Starter übersetzt als C# 5 (`tests/remoteplay_cs.ps1`).
    Nicht getestet: echtes Steam, echte Emulatoren, Windows.
- 0.8.0:
  - Neuer Reiter **Filme** (abschaltbar) wie Nuvio TV: Stremio-Addons per Manifest-URL
    (selbst eingetragen), Cinemeta dabei, kein P2P, Plugins im Nuvio-Format über Deno, Weiterschauen,
    Bibliothek, Staffeln/Folgen, Quellenwahl mit Qualität/HDR/Größe/„sofort bereit“, Abspielen
    in mpv mit Untertiteln, nächste Folge automatisch. Getestet gegen nachgebaute Addons.
  - Discord-Direktnachrichten in Uzai über das offizielle Discord Social SDK (Freundesliste,
    Chat, Ungelesene). Braucht einmal den SDK-Download neben Uzai.exe (siehe Konten).
  - Mitteilungen als Pop-up: Steam-Nachrichten in Echtzeit (Status wie in Steam, nie
    „unsichtbar“), Discord-Benachrichtigungen, auch über laufenden Spielen (eigenes Fenster ohne
    Fokus; nicht bei exklusivem Vollbild). View öffnet das letzte Pop-up.
  - Remote Play Together für jedes Spiel (auch Emulatoren) über ein Spender-Spiel wie RetroArch,
    Einladen im Guide an Steam-Freunden.
  - Shop: echte Hüllen-Bilder von Steam (auch neue Spiele), Querbilder nie mehr verzerrt.
  - Startseite: Systemwechsel ohne Flackern, das Steuerkreuz bleibt auf der Systemleiste.
- 0.7.6:
  - Spotify *Abspielen auf …*: Uzai wartet jetzt, bis Spotify das Gerät wirklich übernommen hat,
    und sagt sonst warum nicht (Premium nötig, Gerät nicht erreichbar, von Spotify gesperrt).
    Schlafende Lautsprecher werden einmal geweckt. Vorher hieß es immer „gewechselt“.
  - Steam-Chat: Die Anmeldung am Chat-Server läuft unter der eigenen Steam-ID (wie bei
    steam-user/SteamKit), nicht unter der allgemeinen. Antwortet Steams Chat-Server beim
    QR-Code nicht, steht das jetzt da (dieser QR-Code erlaubt dann nur Lesen).
- 0.7.5:
  - Nie mehr raus aus Uzai: Kein Knopf holt Steam oder Discord nach vorn. Steam-Nachrichten
    gehen über eine eigene Verbindung zu Steams Chat-Servern (wie die Steam-App: WebSocket,
    QR-Anmeldung als Steam-App). Eine ältere Anmeldung darf nur lesen; beim ersten Senden kommt
    einmal der QR-Code. Discord-Nachricht, -Anruf und „Stream ansehen“ sind raus (ohne die
    Discord-App nicht machbar).
  - Discord im Guide: die Server-Leiste passt immer in die Karte (Namen gekürzt, Rest unter
    *Alle Server*), nichts rutscht mehr aus der Mitte.
  - Weichgezeichnete Hintergründe ohne Blöcke und Streifen, auch bei kleinen Bildern und auf
    4K: das Bild wird erst sauber verkleinert, dann fein weichgezeichnet (und schneller).
  - Steam-Profil ohne „Song schicken“.
- 0.7.4:
  - Steam-Chat: Steam bietet das Senden über HTTP nicht an (404). Uzai sendet dann über das
    Steam-Programm (`steam://friends/message/…`): Chat öffnen, tippen, absenden, Uzai sofort
    wieder vorn. Lesen bleibt direkt in Uzai.
  - Shop im Hochformat wie Spielhüllen (Steams 600 × 900, auf 4K die 2×-Fassung), mehr Spiele
    nebeneinander. Genres: drei Spiele nebeneinander direkt in der Kachel, ohne Karten.
  - Freunde: eigener Reiter „Discord“ über die Discord-App – Server, Sprachkanäle mit den
    Leuten, beitreten. Nicht verbunden: der Grund und „Mit Discord verbinden“. Lehnt Discord
    die Serverliste ab, steht das da (statt still leer).
  - SteamGridDB: Bilder bekommen mehr Zeit (große Hintergründe brachen bei vielen
    gleichzeitigen Downloads ab), Fehler stehen in `logs\sgdb.log` und in der Auswahl.
- 0.7.3:
  - Steam-Chat: Senden mit dem Zugang des Steam-Webchats (steamcommunity.com) statt mit dem
    Anmelde-Zugang (der gab beim Senden 403). Der Zugang wird erneuert, ohne abzumelden: nach
    einem Neustart muss man sich nicht mehr neu anmelden.
  - Kein blauer Windows-Rahmen mehr bei Spiel- und Videostart: Uzai bleibt immer randlos.
  - Maus: Zeigen setzt die Auswahl (leise, ohne Scrollen). SteamGridDB-Auswahl mit sichtbarem
    Ring.
  - 4K: Bilder werden passend zur Bildschirmauflösung geladen und mit Mipmaps gezeichnet.
  - Menüklänge leiser und weicher.
  - Shop: Genres ohne Farbe, das erste Spiel füllt den Kasten, zwei weitere als Karten, gewählt
    fährt das Bild langsam heran. Alle Shop-Karten im schärferen Kapselformat (616 × 353).
  - Schneller: Daten und Bilder haben getrennte Netzspuren, gleiche Bilder werden nur einmal
    geladen.
  - Discord: Server und Sprachkanäle im Guide wählen und beitreten. Status „Hört …“ mit Knopf
    zum Mithören auf Spotify. Freundesmenü: Profil, Nachricht, Einladen, Anrufen (nur
    Discord), Spiel beitreten. „Song schicken“ nicht mehr im Steam-Chat und -Profil.
  - Songtexte (LRCLIB) in „Läuft gerade“, zuschaltbar, laufen mit.
  - Guide: Stimmung aus dem Spiel hinter der Karte (weiches Spielbild, wandernder Lichtschein),
    zuletzt gespielte Spiele mit Bild.
  - Lossless Scaling: `logs\lossless.log` zeigt, welches Fenster das Kürzel bekam.
- 0.7.2:
  - Spotify zeigte überall nur „Abgelehnt, Fehler 403“: Spotify schickt manche Ablehnungen als
    reinen Text statt JSON (etwa „the user may not be registered“), Uzai hat diesen Text
    verworfen. Jetzt wird er gelesen und erkannt. Lehnt Spotify sogar das eigene Konto ohne
    Grund ab, sagt *Verbindung prüfen*, was im Dashboard zu prüfen ist (User Management mit
    derselben E-Mail, Premium des Besitzers, „Web API“ angehakt).
  - Steam-Chat: „Steam hat die Nachricht nicht angenommen“. Der Zugang steht beim Senden jetzt
    in der Adresse wie in Steams eigenem Webchat. Bei Ablehnung holt Uzai einmal einen frischen
    Zugang und versucht es nochmal. Steams Ergebnis (`x-eresult`) wird gelesen und als Grund
    angezeigt, alles steht in `logs\steam.log`.
  - Spielseite: Zurück nach oben (Spielen, Optionen) blättert die Seite wieder ganz hoch, das
    große Bild ist wie beim Öffnen voll zu sehen.
  - Mögliche Ursache für Abstürze nach mehreren Spielseiten beseitigt: Jede Seite übersetzte
    ihren Weichzeichner neu und rechnete das große Bild in voller Breite mit Mipmaps; der
    Bilderspeicher war nur nach Anzahl begrenzt. Jetzt ein gemeinsamer Shader, kleineres
    Weichbild und höchstens rund 360 MB Bilder im Speicher.
  - Videos starten ohne Fensterrahmen direkt im Vollbild auf dem Bildschirm, auf dem Uzai liegt.
  - Lossless Scaling bei Emulatoren: Das Kürzel ging an das erste Fenster des Programms, bei
    PCSX2 das Hauptfenster statt das Spielbild. Jetzt geht es an das Fenster, das vorn liegt,
    sonst an das größte. Im Emulator muss Vollbild „randlos“ sein (exklusives Vollbild kann
    Lossless Scaling nicht abgreifen).
- 0.7.1: Fehler aus dem Alltag am PC behoben:
  - *Pause/Abspielen* öffnete den Guide: Der Helfer drückte Medientasten ohne
    Extended-Kennzeichen, deshalb kam Pause/Play als Taste G an. Uzai ignoriert Medientasten
    jetzt bei der Bedienung.
  - Spotify: Jede Ablehnung hieß „Neu anmelden“. Jetzt nennt Uzai den echten Grund: Konto nicht
    unter *User Management*, App ohne Premium, Anmeldung nach sechs Monaten abgelaufen oder
    fehlende Freigabe. Ein „Neu anmelden“ im Kreis gibt es nicht mehr. Kam Playlists nichts an,
    zeigt die Seite den Grund statt endloser Platzhalter. „Läuft gerade“ nimmt notfalls, was
    Windows abspielt.
  - Discord: Der Code-Tausch beginnt mit `http://localhost` (ein Code gilt nur einmal). Eine
    abgelehnte Anmeldung lief bisher endlos im Kreis. Die Freigabe zeigt jetzt jeden Schritt.
  - Videos liegen vorn (siehe oben) statt hinter einem durchsichtigen Fenster.
  - Keine hellen Haarlinien mehr an Knöpfen, Pillen und Karten, auch keine hellen Ringe um
    Abspielknöpfe, Tastensymbole und Farbfelder.
  - Genres im Shop zeigen je drei Spiele.
- 0.7: neun unabhängige Prüfer, je einer für Startseite und Spielseite, Shop, Erfolge, Freunde,
  Musik, Videos, Guide, Einstellungen und den Rahmen (Kopfleiste, Bewegung, Designsystem). Jeder
  hat seine Fenster ehrlich benotet und die größten Mängel selbst behoben; danach wurde alles
  zusammengeführt und gemeinsam geprüft. Dabei aufgefallen: Schatten auf zuschneidenden Flächen
  ließen im Kompatibilitäts-Renderer kurz alte Bildreste durchscheinen. Das ist behoben, und der
  Rundgang meldet so etwas künftig.
- 0.6.3: fünf getrennte Prüfungen (Design, Bewegung, Klang, Guide, Fehlersuche) über alle
  Bildschirme; eingebaut u. a.: neue Klänge in einer Tonart mit Vorrang und Begrenzer,
  Bewegungen ohne Stapeln und Springen (Rand-Anschlag wanderte), Seitenleisten gleiten statt
  sich zu dehnen, weicher Abschluss hinter den Tastenhinweisen, Guide schließt Unterfenster mit,
  „Spiel beenden“ fragt nach, Bildfilter-Umschalten blockiert den Guide nicht mehr, Fehler beim
  schnellen Öffnen/Schließen über dem Spiel behoben, Bilder-Cache nimmt nur echte Bilder an
- 471 Logiktests in zehn Gruppen grün (161 allgemeine, dazu eine Gruppe je Bereich), dazu ein
  Netztest gegen eine nachgebaute Spotify-Schnittstelle mit den Regeln von 2026 (40 Prüfungen:
  neue Adressen, höchstens zehn Suchtreffer, Bibliothek über URIs, gesperrte Titellisten, kein
  aktives Gerät, fehlende Freigaben, Konto nicht in der App (als reiner Text), Ablehnung ohne
  Grund, abgelaufene Anmeldung). Unter den allgemeinen Tests: die unscharfe Libretro-Namenssuche (mit 11 000 echten
  PS2-Namen gegengeprüft, drei Treffer auch auf dem Server nachgesehen), Wikipedia-Seiten- und
  Bildauswahl, RetroAchievements-Bilder, Stick-Richtung und Wiederholtempo, Steam-IDs nach dem Laden
  (Cover-Fehler aus 0.5.1), Libretro-Cover, „Für dich“-Mischung, Spotify-Titel und Playlists,
  Steam-Chat (Verlauf, Emoticons, Anmeldung), Shop (Listen, Sortieren, Bewertungen, Spieleseite),
  Fehlererkennung bei Discord (Bot-Token statt Secret, Weiterleitungsadresse), alle Menüklänge, Farbverläufe aus der Spielfarbe, der Discord-Sprachkanal (Anmeldung, Kanal, Sprechen, Lautstärke,
  stummschalten, Mikro, Ton, Kanal wechseln und verlassen, andere Kanäle, Ablehnung), Ordner aus Unterordnern, PC-Spiele-Ordner, Steam-Bilder (neuer
  Cache, eigene Artworks, Store-Adressen), Platzhalter und eigene Emulatoren, Beitreten,
  Zeitangaben der Spielzeit-Seite
- Handy-Eingabe Ende zu Ende über HTTP (auch Umlaute und Sonderzeichen), nur ein Uzai
  gleichzeitig (eine Verknüpfung übergibt an das laufende Uzai)
- alle Skripte laden fehlerfrei, Logiktests grün (VDF, Steam-Bibliotheken, ROM-Suche,
  Disc-Zusammenfassung, Startparameter, ShaderGlass-Profil, Titelvergleich für Erfolge,
  YouTube-Feeds, yt-dlp-Antworten, YouTube-Startseite wie auf dem Fernseher (eigene
  Beispielantworten, Geräte-Anmeldung, Erneuern; Netz-Probe gegen ein nachgebautes YouTube),
  SponsorBlock, Zeit- und Aufrufanzeige, QR-Code,
  Lossless-Automatik)
- der QR-Code wird von einem unabhängigen Leser (OpenCV) korrekt erkannt
- der Windows-Helfer: Syntax, C#-Teil (auch die direkte Steam-Einladung und die Discord-Leitung,
  mit den Sprachregeln von C# 5 wie unter Windows PowerShell) und der mpv-Steuerkanal (gegen einen
  nachgebauten mpv) mit PowerShell 7 geprüft
- kompletter Rundgang durch alle Bereiche, Menüs und den Videoplayer (simuliert) mit 75
  Bildschirmfotos, ohne Skriptfehler
- Windows-Export baut und lädt

**Noch nicht auf echtem Windows getestet:** Emulatorstart, ShaderGlass-Überlagerung,
Schnellmenü über einem laufenden Spiel, Guide-Wächter im Spiel, Pausieren des Spiels,
Lossless Scaling, YouTube-Wiedergabe über mpv (durchsichtiges Fenster darüber),
automatisches Einrichten von yt-dlp/Deno/mpv, Google-Anmeldung, Discord-Status,
Spotify-Anmeldung, Spotify *Für dich* mit echtem Konto, Spotify im Hintergrund starten, die
Gründe, mit denen das echte Spotify ablehnt (nachgebaut nach Dokumentation), Uzais Leiste im echten
mpv (das Skript lief mit nachgebautem mpv, gezeichnet mit derselben Bibliothek libass),
Medientasten über den Helfer,
Medientasten, Steam-Chat über die Steam-Schnittstelle, Steam-Profil, Wunschliste und Warenkorb
über die Steam-Schnittstelle, Installationsfortschritt, direkte Steam-Einladung,
Installieren über Uzai mit echtem Steam und Epic (Fern-Download über `IClientCommService` mit einem
echten Konto – getestet gegen eine nachgebaute Web-API –, UI Automation in Steams und Epics
Dialogen, Live-Bild per PrintWindow, Tasten an das Fenster, das Format des Epic-Protokolls, das
appmanifest für einen anderen Bibliotheksordner nach Steam-Neustart),
Senden über Steams Chat-Server mit einem echten Konto (getestet gegen einen nachgebauten Server),
Discord-Kanal betreten aus *Für dich*, den Freunden und dem Guide,
Discord-Sprachkanal mit der echten Discord-App,
Discord-Übertragung per Tastenbelegung,
Maus mit dem Controller,
Bildschirmfoto, Clip, Audioausgabe umschalten, Controller-Akku, Verknüpfungen,
Autostart, Ausschalten/Neustart.

**Was es nicht gibt (keine Schnittstelle dafür):** Einladungen in Spiele, die selbst keine anbieten
(dann gibt es auch im Steam-Overlay keinen Knopf dafür), deine persönliche Discord-Freundesliste
(nur Server über das Widget), ob jemand anderes im Sprachkanal gerade überträgt (die
Schnittstelle meldet das nicht), einem Discord-Stream in Uzai zusehen (*Streams ansehen* holt
dafür die Discord-App nach vorn),
Spotify-Jam starten (nur in der Spotify-App; den Link kann Uzai verschicken), Bezahlen im Shop
(Steam hat keine Kauf-Schnittstelle; Uzai legt das Spiel in den Warenkorb, bezahlt wird im
Steam-Client), die Titellisten von Mix der Woche, Release Radar und Daily Mix (Spotify gibt sie
seit Ende 2024 nicht an eigene Apps heraus; abspielen geht), private Discord-Nachrichten und
-Anrufe (Uzai holt die Discord-App dafür nicht nach vorn). Diese Teile laufen über
`helper/uzai-helper.ps1` und Windows-Programme.
Wenn etwas hakt: In `%APPDATA%\Uzai\logs\` stehen `godot.log` (allgemein), `spotify.log` (was
Spotify abgelehnt hat und warum), `steam.log` (warum Steam eine Chat-Nachricht nicht angenommen
hat), `lossless.log` (welches Fenster das Lossless-Kürzel bekam), `launch.log` (Spielstart: wann
welches Fenster vorn lag) und `discord.log` (jeder Schritt der Discord-Verbindung, ohne Zugangsdaten, und jeder Versuch von *Übertragen*). Unter Einstellungen → Konten prüft *Verbindung prüfen* Spotify Schritt für Schritt;
*Mit Discord verbinden* zeigt die Schritte der Freigabe und bleibt am Schritt stehen, der hakt.

---

## Entwicklung

- Godot **4.5.1** (Compatibility-Renderer), alles in GDScript, Oberfläche komplett im Code gebaut.
- Start im Editor mit Demodaten: Startargumente `--demo --windowed --no-boot`.
- Tests:
  ```
  godot --headless --path . res://tests/check.tscn       # alle Skripte laden
  godot --headless --path . res://tests/test_logic.tscn  # Logiktests
  godot --headless --path . res://tests/logic_musik.tscn # je Bereich: logic_home, logic_shop, …
  ```
  Netztest Musik: `python3 tests/fake_spotify.py 18765` starten, dann `tests/net_musik.tscn` mit
  `UZAI_SPOTIFY_API=http://127.0.0.1:18765/v1` und `UZAI_SPOTIFY_ACCOUNTS=http://127.0.0.1:18765`.
  Netztest Epic-Konto: `python3 tests/fake_epic.py 18794` starten, dann `tests/net_epic.tscn` mit
  `UZAI_EPIC_API=http://127.0.0.1:18794` (Code tauschen, Erneuern, Seiten, Katalog, Störung,
  abgelaufen, Abmelden); ohne Netz `tests/logic_epic_konto.tscn`.
  Netztest Steam-Chat: `tests/net_steam_cm.tscn` (bringt einen nachgebauten Steam-Chat-Server mit;
  QR-Anmeldung als Steam-App, Anmelden, Senden, Trennung, Ablehnung).
  Remote Play Together: `tests/logic_remoteplay.tscn` (Logik, Dateien im Spender) und
  `pwsh -File tests/remoteplay_cs.ps1 helper/uzai-helper.ps1` (Starter und Einladung als C# 5,
  auch mehrere auf einmal); „Alle im Discord-Call einladen“ (Namensvergleich, Zuordnungen, wen
  einladen) steht ebenfalls in `tests/logic_remoteplay.tscn`.
  Netztest Shop-Bilder: `tests/net_shop.tscn` (startet `tests/fake_steam_store.py` selbst; eigener
  Server über `UZAI_STEAM_API` und `UZAI_STEAM_CDN`).
  Leiste in mpv ohne mpv ansehen: `tools/osd_preview.py` (Lua mit nachgebautem mpv, Bild mit
  libass). Schrift dafür: `tools/make_uzai_sans.py` (feste Schnitte aus Hanken Grotesk).
  Rundgang mit Bildern: `-- --demo --uzai-test=<ordner>`; eigene Proben: `--uzai-script=<datei>`
  (siehe `tests/probe_example.gd`). `UZAI_DATA=<ordner>` legt einen eigenen Datenordner fest.
- Export: `godot --headless --path . --export-release "Windows" build/Uzai.exe`
- Jeder Push auf `main` baut über GitHub Actions eine Windows-Version. Ein Tag wie `v0.1.0` legt
  zusätzlich ein Release an.

```
src/core/       Einstellungen, Aussehen, Netzwerk, Bilder, Spielstart, Erfolge, Freunde, Musik, Shop,
                YouTube, Videoplayer, Lossless Scaling, QR-Code, Navigation
src/library/    Steam-, Epic-, EA-, ROM- und PC-Ordner-Suche, Ordner
src/ui/         Bausteine, Bereiche, Menüs (layers), Startanimation
data/           Startwerte für Systeme, Emulatoren, Bildfilter
helper/         Windows-Helfer (Fenster, Tasten, Text, Pausieren, ShaderGlass, Discord, mpv,
                Bildschirmfoto, Audiogeräte, Controller-Akku, Verknüpfungen)
assets/sounds/  vorab gerenderte Klänge (Quelle: tools/synth.py)
tests/          Prüfungen, Rundgang, Demodaten
```

Schriften: Hanken Grotesk, Atkinson Hyperlegible Next/Mono und Saira (alle SIL Open Font
License, siehe `assets/fonts/OFL-HankenGrotesk.txt`, `assets/fonts/OFL.txt` und
`assets/fonts/OFL-Saira.txt`). Die Leiste in mpv nutzt Uzai Sans, feste Schnitte aus Hanken
Grotesk unter eigenem Namen (ebenfalls OFL, `assets/mpv/fonts/OFL.txt`). Die Grundwerte des Aussehens
(„Graphit“) stehen in `src/core/aussehen.gd`.
Das Repository enthält keine Logos oder Grafiken von Sony, Microsoft, Nintendo, Sega, Valve oder
Google. Die Konsolen-Logos (Startseite, Abzeichen) lädt Uzai zur Laufzeit (abschaltbar) für den privaten Gebrauch von Wikimedia Commons (Marken der jeweiligen Inhaber); sie
werden nur im Datenordner zwischengespeichert.
yt-dlp (Unlicense), mpv (GPL/LGPL) und Deno (MIT) werden als eigene Programme geladen und
gestartet, nicht in Uzai eingebaut. YouTube ohne Werbung verstößt gegen die Nutzungsbedingungen
von YouTube; Werbeblocker sind in Deutschland aber zulässig (BGH, 2018).
