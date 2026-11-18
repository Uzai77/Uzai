# Sicherheit in Uzai

Uzai ist eine Oberfläche für den eigenen Windows-PC. Es spricht mit vielen fremden Diensten (Steam,
Discord, Spotify, YouTube, Twitch, Medienserver, Addons, Plugins), liest Dateien anderer Launcher und
nimmt Zimmer und Zimmer-Codes von anderen Menschen an. Dieses Dokument beschreibt, wovor Uzai
schützt, wo die Grenzen liegen und wie man Lücken meldet. Die Bedrohungsanalyse für das Zimmer im
Netz steht ausführlich in `docs/ZIMMER_SICHERHEIT.md`.

## Leitlinien

- **Keine eigenen Server, keine offenen Ports nach außen, kein UPnP, keine Telemetrie.** Uzai sendet
  nichts über dich an den Herausgeber. Personenbezogene Daten verarbeitet der Herausgeber nicht.
- **Fremde Daten werden nie ausgeführt.** Nie `str_to_var`, `bytes_to_var(_with_objects)`,
  `Expression`, `JSON.to_native`, `ResourceLoader`/`load()` auf Daten von außen. Fremde Daten sind
  JSON mit festem Schema, Bilder, Schriften und Klänge über die Rohdaten-Lader – mit Größengrenzen.
- **Programme nur mit Argument-Liste, nie über eine Shell** (Ausnahme: `.bat`/`.cmd`, die nur so
  laufen; ihre Argumente stammen aus deinen eigenen Einstellungen). Argumente aus fremden Quellen
  laufen durch `Helper.win_args` (Windows-Anführungszeichen) und beginnen nie mit `-`.
- **Nie Administratorrechte.** Uzai fordert sie nicht an; ein Spiel, das sie verlangt, startet erst
  nach deiner Rückfrage, und dann fragt Windows selbst.
- **Kein virtueller Controller-Treiber, keine globalen Tastendrücke für Gäste, kein Credential
  Provider.**
- **Löschen nur in Uzais eigenen Ordnern, nie über Verknüpfungen.**

## Bedrohungsmodell

| Angreifer | Kann | Uzai schützt |
|---|---|---|
| Fremde im Internet, Bots | nichts direkt – es gibt keinen offenen Port | Uzai lauscht nur auf 127.0.0.1 bzw. kurz im Heimnetz (siehe unten) |
| Ein Dienst oder Server, der Unsinn liefert (gehackt, bösartig, Mann in der Mitte bei http) | beliebige Antworten | Schema-Prüfung, Größen-, Tiefen- und Mengengrenzen, nur https für Downloads |
| Wer dir schreibt (Steam-, Discord-Chat, Freundesstatus) | Texte, Links, Lobby-/Server-Angaben | Links werden nie im Browser geöffnet (QR fürs Handy); Steam-Links nur in fester Form |
| Autor eines Addons, Plugins, Zimmers | Daten oder (bei Plugins) JavaScript | Plugins nur in Deno mit engen Rechten; Zimmer sind reine Daten |
| Jemand im selben WLAN | Pakete sehen, Anfragen an den PC schicken | Handy-Seite nur mit 128-Bit-Code, kurzer Laufzeit, nur Heimnetz-Absender |
| Gast im Zimmer (Zimmer online, Standard aus) | beliebige Bytes über die Verbindung | nur Eingeladene; Protokoll nur aus Zahlen mit festen Längen und Bereichen, kein Text, keine Namen; zwei Prüfmauern (Sandbox und Uzai), Drossel, Rauswurf |
| Bot oder Relay-Betreiber am Treffpunkt (Nostr) | beliebige Ereignisse an eine Zimmer-Kennung | ohne Link-Schlüssel nicht zu öffnen (AES-256-GCM), ungelesen verworfen; nur in der Sandbox; keine IP vor der Annahme; Drossel; nichts davon erreicht Uzai |
| Lücke in einer Netz-Bibliothek (WebRTC, TLS) | Speicherfehler im Prozess, der Netzdaten liest | dieser Prozess läuft im AppContainer (nur `internetClient`, keine Dateien, keine Kindprozesse, Job-Objekt), nur eine schmale Leitung zu Uzai |
| Eine Webseite im Uzai-Browser | beliebiges HTML/JavaScript, Links, Pop-ups, Downloads, Fragen nach Kamera/Mikrofon | Chromium-Sandbox von WebView2 (eigener Prozess), Uzais Skript in einer eigenen Welt, keine Brücke zur Seite, nur http/https, nie dieser PC, Heimnetz nur selbst eingegeben, Downloads nur aus einer Erlaubnisliste und nie geöffnet (siehe „Uzai-Browser“) |
| Ein anderes Programm unter deinem Windows-Konto | alles, was du darfst | **nicht** – siehe „Was Uzai nicht schützt“ |

### Was Uzai nicht schützt

- **Schadsoftware unter deinem eigenen Windows-Konto.** Sie kann Uzais Datenordner lesen und ändern,
  den Helfer austauschen oder Uzai mit eigenen Argumenten starten. Dagegen hilft nur Windows selbst.
- **Die Profil-PIN ist keine Sicherheitsgrenze.** Sie hält Kinder und Mitbewohner aus fremden
  Profilen fern (gesalzener PBKDF2-Hash, Sperre nach Fehlversuchen). Wer an die Dateien kommt, kann
  vier bis acht Ziffern durchprobieren oder die Datei ändern.
- **Zugangsdaten** liegen verschlüsselt (Windows DPAPI, an dein Konto gebunden). Das schützt vor
  dem Kopieren der Dateien auf einen anderen PC, nicht vor Programmen unter deinem Konto.
- **Sicherungen** enthalten Spielpfade, Startparameter und Anmeldungen. Lege nie eine fremde
  Sicherung in `backups` – Uzai würde ihre Spiele so starten, wie sie dort stehen.
- **Spiele, Emulatoren und Launcher** startet Uzai so, wie du oder der Launcher sie eingerichtet
  habt. Was diese Programme tun, liegt außerhalb von Uzai.

## Eingänge und ihre Prüfungen

### Netz-Antworten der Dienste

| Eingang | Prüfung |
|---|---|
| Alle HTTP-Antworten (`Net.request`) | Größengrenze (Bilder 32 MB, Daten 64 MB bzw. enger je Dienst), Zeitgrenze, JSON nur über Godots Parser ohne Objekte |
| Bilder aus fremden Quellen (SteamGridDB, Addons, Wikipedia, Medienserver, Avatare) | nur https (Medienserver: nur der verbundene Ursprung), Kopf muss ein Bild sein; vor dem Dekodieren Größe aus dem Kopf: höchstens 8192 Pixel je Seite und 37,7 Mio. Pixel; Pfade statt Adressen nie als Windows-Freigabe (`\\server\…`) |
| Steam (Web-API, CM über wss) | feste Server von Steam, TLS geprüft, eigener Protobuf-Leser mit Längenprüfung |
| Spotify, YouTube, Twitch, Epic, Nuvio | feste https-Adressen, Schema-Prüfung je Antwort |
| Liedtexte (LRCLIB, `lyrics.gd`; abschaltbar, `music.lrclib`) | nur https an `lrclib.net/api/get` bzw. `/api/search`, ohne Weiterleitungen, eigener User-Agent (Name und Fassung), gesendet nur Titel, Künstler, Album, Länge (ohne Steuerzeichen, je höchstens 200 Zeichen); Antwort höchstens 768 KB, Typen und Längen je Feld geprüft (Text höchstens 64 K Zeichen, höchstens 20 Treffer), LRC-Zeitmarken nur im festen Format (Sekunden < 60, bis 3 h, höchstens 1200 Zeilen à 300 Zeichen), Steuer- und Richtungszeichen entfernt; Zwischenspeicher `cache/lyrics.json` nur mit SHA-256-Schlüsseln, beim Lesen wie eine fremde Antwort geprüft, höchstens 300 Titel bzw. 3 MB |
| Plex, Jellyfin, Emby, Stremio-Konto | Adressen streng geprüft (`medienquellen_basis.gd`), http nur im Heimnetz nach Bestätigung, ohne Weiterleitungen, Pfade nur auf demselben Server, Größengrenzen |
| Jellyfin/Emby-Suche im Heimnetz | nur auf Wunsch, ein UDP-Rundruf, 2,5 s Antworten sammeln, nur von privaten Absendern, Antwort muss zur Absenderadresse passen |
| Addons (Stremio-Protokoll) | nur JSON; Stream-Adressen nur http(s) und für mpv maskiert (`Video.safe_url`, `arg_text`), Kopfzeilen nur mit sauberem Namen; P2P/Torrent spielt Uzai nicht ab |
| Downloads von Werkzeugen (yt-dlp, mpv, FFmpeg, Deno) | nur https, Prüfsumme (SHA-256) vor dem Ablegen |
| Epic-Spiele ohne Launcher (`epic_install.gd`, `epic_manifest.gd`; inoffiziell wie Heroic/Legendary, nur nach ausdrücklicher Wahl) | Anmeldung nur in der Kopfzeile an Epics Dienst, nie an Download-Server, nie im Protokoll oder in einer Kommandozeile (beim Spielstart nur der Einmal-Code, siehe unten); Manifest-Adressen nur https zu Epics Download-Servern (feste Hosts bzw. `*.epicgames.com`, `*.epicgamescdn.com`, ohne Anmeldedaten, Anschluss, `..`), keine Weiterleitungen; SHA-1 des Manifests laut Epic Pflicht, dazu die im Kopf; eigener Leser mit Größen-, Mengen- und Längengrenzen vor jedem Anlegen; Pfade nur relativ, ohne `..`, Laufwerk, Datenstrom, Gerätenamen, Verknüpfungen, Doppelte (auch Groß/klein) und Datei-als-Ordner; jeder Chunk geprüft (Kopf, GUID, Größe, SHA-1), jede Datei geprüft (SHA-1), erst danach an ihren Platz; verschlüsselte Manifeste/Chunks abgelehnt (kein Umgehen von Kopierschutz); geschrieben nur im eigenen Spielordner unter dem gewählten Ordner (nicht in Windows-/Programmordnern), nie durch Verknüpfungen; gelöscht nur, was laut Manifest dazugehört; ausgeführt wird nichts (keine Voraussetzungs-Installer) |
| Emulatoren und RetroArch-Kerne (Retro ohne Einrichtung, `retro_auto.gd`, `retro_laden.gd`) | nur nach Zustimmung; nur feste Hosts (api.github.com, github.com mit Weiterleitung nur zu GitHubs Dateiservern, buildbot.libretro.com, dl.dolphin-emu.org, dolphin-emu.org) und feste Repositorys; Release-Daten von GitHub mit Größengrenze, Paketname nach festem Muster, Adresse genau nach GitHub-Schema, Größe in Grenzen, SHA-256 von GitHub Pflicht; RetroArch und Dolphin nur in der fest hinterlegten Fassung mit fester SHA-256; Weiterleitungen löst Uzai selbst auf und prüft jede; Download mit Größengrenze, abbrechbar. Entpacken nur in einen eigenen Zwischenordner unter `emulatoren`: ZIP über einen eigenen Leser (keine Verknüpfungen, kein Zip-Slip, keine Laufwerke/Datenströme/Gerätenamen, keine Überlappungen, Grenzen für Zahl, Größe, Packrate), 7z über Windows-tar erst nach Prüfung der Liste (`tar -tvf`), danach noch einmal nachgesehen. Ausgeführt wird dabei nichts – den Emulator startet erst ein Spiel. Nie BIOS, Firmware, Schlüssel oder Spiele, Switch nie automatisch |

### Epic-Anmeldung beim Spielstart (Einmal-Code)

Spiele, die Uzai selbst installiert hat, bekommen beim Start wie bei Legendary/Heroic einen
Exchange-Code (`-AUTH_LOGIN=unused -AUTH_PASSWORD=<Code> -AUTH_TYPE=exchangecode`, dazu `-epicapp`,
`-epicenv=Prod`, `-EpicPortal`, Name, Konto-ID, Sprache, Sandbox), damit Spiele mit Epic-Online-
Anmeldung angemeldet starten (`epic_account.gd` `exchange_code`, `epic_install.gd` `start_argv`).

- Nur mit verbundenem Epic-Konto, nur für Spiele von Uzais eigenem Installer, abschaltbar
  (Konten → Epic Games → Mehr). Ob ein Spiel die Anmeldung braucht, steht weder im Manifest noch im
  Katalog verlässlich – darum wie Legendary immer; Spiele ohne Epic-Anmeldung übergehen die Parameter.
- Für jeden Start frisch geholt (`GET /account/api/oauth/exchange` nur per https an
  `account-public-service-prod03.ol.epicgames.com`, ohne Weiterleitungen, höchstens 4 KB), erst nach
  der Admin-Rückfrage; nie gespeichert, nie im Protokoll (nur der HTTP-Code), nicht in Fehlermeldungen
  des Helfers (`Helper.redact` als letzte Sicherung). Lehnt Epic den Zugang ab, erneuert Uzai ihn einmal
  über den vorhandenen Weg; klappt das nicht, startet das Spiel ohne Code mit einer stillen Mitteilung.
  Zugangsdaten bleiben wie bisher DPAPI-verschlüsselt im Tresor.
- Der Code muss genau 16–64 Zeichen aus `0–9a–f` sein (Zeichen für Zeichen geprüft, kein `$`, das einen
  Zeilenumbruch durchließe), sonst gibt es gar keine `-AUTH_*`-Parameter.
- Startparameter gehen als **Liste** an den Helfer (`argv`); er quotet jeden Eintrag einzeln wie
  `CommandLineToArgvW` ihn zurückliest, nimmt höchstens 64 ohne Steuerzeichen und lehnt die Liste für
  alles außer `.exe` ab – nie über `cmd` oder PowerShell. Ohne Helfer (Godots eigener Prozessstart, der
  die Befehlszeile bei Fehlern protokolliert) und für Remote Play (Auftrag als Datei) gibt es keinen Code.

### Chats und Status von Freunden

- Links in Nachrichten öffnet Uzai **nicht** im Browser. YouTube, Spotify und Steam-Shop-Links
  öffnet Uzai selbst über feste Kennungen, alles andere als QR-Code fürs Handy.
- **Beitreten-Links** (`steam://joinlobby`, `steam://connect`) gelten nur in fester Form: Lobby aus
  Ziffern bzw. Host und Anschluss, sonst nichts (`Sicher.steam_join_ok`). Das gilt auch für Lobby
  und Server aus dem Status eines Freundes.
- **Link-Vorschau** (Titel und Beschreibung einer Seite): nur zu Adressen im Internet, nie zu diesem
  PC oder ins Heimnetz – auch nicht über einen Namen, der dorthin zeigt, oder eine Weiterleitung
  (Uzai folgt Weiterleitungen selbst und prüft jedes Ziel). Höchstens 1,5 MB, nur HTML.
- Texte werden nie als BBCode oder Rich Text angezeigt.

### Lokale Dateien anderer Launcher

Steam, Epic, EA, GOG, Ubisoft, Battle.net, Xbox, Amazon, itch und Riot schreiben ihre Dateien unter
deinem Konto. Uzai liest sie nur, prüft Kennungen streng (`store_util.gd`, je Scanner ein Muster)
und baut Start-Links nur aus geprüften bzw. kodierten Kennungen.

Steam-Erfolge und dein Steam-Status ohne Web-API (`src/core/steam_erfolge.gd`, `steam_am_pc.gd`):
Uzai liest nur – `appcache/stats/UserGameStatsSchema_<App>.bin` (höchstens 4 MB) und
`UserGameStats_<Konto>_<App>.bin` (512 KB) mit dem eigenen strengen Leser für binäre KeyValues
(Tiefe begrenzt, kaputt → leer), `userdata/<Konto>/config/localconfig.vdf` (32 MB, nur zwei Schlüssel
gesucht, nicht zerlegt; JSON über `JSON.parse_string`, Status nur 0–7) und `config/loginusers.vdf`
(1 MB). Bildnamen aus dem Schema nur als schlichter Dateiname auf Steams Bildserver. Uzai meldet
dabei nichts an Steam; die Antworten des Chat-Servers (ClientGetUserStats) laufen durch denselben Leser.

### Zimmer-Pakete

Pakete (`.uzaizimmer`) und Codes (`UZZ1:`) laufen durch einen eigenen ZIP-Leser
(`src/core/paket.gd`, `src/core/zip_pruefung.gd`): keine Ordner, keine Verknüpfungen, keine
Verschlüsselung, nur Speichern/Deflate, Grenzen für Dateizahl, Größe und Packrate (Bomben),
Prüfsummen; erlaubt sind genau zwei feste Dateinamen. Das Vorschaubild wird nur im Kopf geprüft.
Theme-Pakete (`.uzaitheme`, Codes `UZT1:`) nimmt Uzai seit dem 12.11.2026 nicht mehr an – das
Theme-System ist entfernt.

### Zimmer-Netz

`Online.BEREIT` ist `true`, Zimmer online aber standardmäßig aus (`room.online`); von selbst verbindet sich nichts.
Die Sandbox startet nur, wenn du Zimmer online einschaltest, den Hinweis zur IP-Adresse bestätigst, „Abschottung
prüfen“ ohne Adminrechte bestanden hat **und** du „Freund einladen“ (Gastgeber) bzw. „Zimmer betreten“ und
„Anklopfen“ (Gast) drückst. Gebaut und geprüft ist das Fundament
(Bedrohungsmodell in `docs/ZIMMER_SICHERHEIT.md`):

| Teil | Grenzen |
|---|---|
| Protokoll Fassung 2 (`src/room/netz_protokoll.gd`) | binär, feste Länge je Art, Werte nur in festen Bereichen (Position in cm, Blick in Milliradiant), Emotes und Schnellsätze nur als Nummer aus festen Listen; kein freier Chat, keine Namen, keine Dateien; Unbekanntes wird abgelehnt; höchstens 3632 Byte; Drossel je Gast und Art |
| Sandbox (Helfer `-ZimmerNetz`, `zimmer-netz-probe`) | AppContainer nur mit `internetClient` (kein Lauschen, kein Heimnetz), Job-Objekt (ein Prozess, 256 MB, endet mit dem Helfer, keine UI-Rechte), keine Kindprozesse, nur der eigene leere Ordner; nie mit Adminrechten; Netz nur ausgehend per WebSocket an feste Relays (eine einzige Stelle im Code) |
| Treffpunkt in der Sandbox (`UzTreff`, `UzRelays`) | Nostr-Relays nur als Briefkasten: flüchtige Ereignisse, Postfach = zufällige Kennung, Inhalt mit AES-256-GCM versiegelt (Schlüssel nur im Link hinter „#“), Sitzung per ECDH P-256 erst nach der Annahme; Kryptografie nur aus Windows CNG bzw. .NET mit Selbsttest; JSON der Relays mit eigenem strengen Leser (16 KiB, Tiefe 4, nur Ganzzahlen, doppelte Schlüssel abgelehnt), Kennung nachgerechnet, Wiederholungs- und Zeitprüfung (2 Minuten), Drossel je Relay und je Postfach, zu große oder binäre Nachrichten trennen das Relay; SDP-Prüfer: nur Datenkanal, ein SHA-256-Fingerabdruck, ICE nur UDP mit IP, Heimnetz-Adressen und `raddr` raus, `c=`/`m=`-Adresse neutral. BIP-340-Signatur mit Wegwerf-Schlüssel je Postfach (libsecp256k1), fremde Signaturen geprüft (falsch → ungelesen verworfen); echte Relays nur im Echtbetrieb (`--netz <rolle>` ohne `--test`) |
| Netz-Bibliotheken (`assets/net/`, `tools/bau_netzlibs.sh`, `UzNetzLib`, `UzSecp`, `UzRtc`, `UzDirekt`) | libsecp256k1 v0.7.1 und libdatachannel v0.24.6 (libjuice, usrsctp, Mbed TLS 3.6.7) aus gepinnten Commits selbst gebaut (504 Quelldateien mit SHA-256, bit-gleich nachbaubar), gehärtet (ASLR/HIGHENTROPYVA/NX, Stack-Schutz, Fortify), nur Windows-Systemimporte; **nur in der Sandbox** geladen: voller Pfad neben dem Programm, Prüfsumme dreimal (Uzai, Helfer, Sandbox; Datei beim Laden gegen Schreiben gesperrt), `LOAD_LIBRARY_SEARCH_SYSTEM32`, erst nach geschützter Standardausgabe; Selbsttest (BIP-340-Vektoren, Angebot mit DTLS-Fingerabdruck). WebRTC: nur ein ausgehandelter Datenkanal, nur Binär bis 4096 Byte, ICE nur UDP, STUN fest (Google, Cloudflare), kein TURN, kein UDP-Mux, kein Server in libjuice, kein UPnP; fremde Kanäle sofort zu; Rückrufe setzen nur Zahlen, Nachrichten holt der eigene Faden ab (höchstens 32 je Takt und Platz) |
| Leitung (`src/room/zimmer_netz.gd`, `src/room/treffpunkt.gd`) | Rahmen mit 4 Byte Länge, höchstens 8 KiB, jede Art nur in einer Richtung und Rolle; Prüfmauer 1 in der Sandbox, Prüfmauer 2 in Uzai; über die Leitung gehen vom Treffpunkt nur Kennung, Fingerabdruck (8 Byte) und Zustände – nie Adressen oder Relay-Texte; bringt die Sandbox etwas Ungültiges, schließt Uzai die Leitung |

Tests: `tests/logic_zimmer_netz.gd` (Fuzz, Grenzen, gleiches Urteil beider Mauern über 6000
Pakete, Lauf gegen die echte Sandbox-Schleife über eine Pipe), `tests/zimmer_sandbox_cs.ps1`,
`tests/zimmer_treff_cs.ps1` (Krypto gegen Testvektor, JSON/Nostr/SDP mit Fuzz, Gastgeber/Gast/böser
Gast im Speicher), `tests/logic_treffpunkt.gd` (neue Rahmen, Gastgeber-Logik), `tests/net_zimmer_treff.gd`
(zwei kopflose Instanzen, Test-Relay auf 127.0.0.1, böser Gast und böses Relay).
`tests/netzlibs_cs.ps1` (Prüfsummen, PE-Härtung, Exporte/Importe, Lade-Regeln; mit der Linux-Fassung: alle
BIP-340-Vektoren, Fuzz der P/Invoke-Schicht, echter Datenkanal über 127.0.0.1 mit böser Gegenstelle).
Nur am Windows-PC prüfbar: AppContainer-Start, Vererbung der Leitung, AES-GCM über CNG im Container
(„Abschottung prüfen“ → „Verschlüsselung in der Abschottung“, „Signatur“, „Datenkanal“), WebSocket zu den
Relays im Container, ICE mit nur `internetClient` („Verbindungstest“ im Testbetrieb).

### Plugins (Nuvio-Scraper)

Plugins sind fremder JavaScript-Code und laufen in **Deno** mit: `--allow-net` ohne Heimnetz
(`--deny-net` mit allen privaten IPv4-Bereichen, `localhost`, `[::1]`, `[::]` und den Adressen dieses
PCs), Lesen nur des Runners und der Skripte, kein Schreiben, keine Programme, keine Umgebung, kein
Nachladen, Speichergrenze, Zeitgrenze. Deno prüft auch die aufgelöste Adresse eines Namens. Die
Skripte lädt Uzai nur vom Server des Repositorys selbst oder per https aus dem Internet, nie aus dem
Heimnetz, auch nicht über Weiterleitungen.

Untertitel aus Addons und Plugins gehen nur über http(s) an mpv (`Video.sichere_untertitel`); eine Datei auf dem
PC oder eine Netzwerkfreigabe (Windows schickte dabei die Anmeldung an den fremden Rechner) fällt weg.

### Weiterleitungen

Folgt Uzai einer Weiterleitung zu einem anderen Ursprung (anderer Host, anderer Anschluss, anderes Schema), gehen
nur die harmlosen Kopfzeilen mit (User-Agent, Accept, Accept-Language, Range) – nie ein Schlüssel, nie ein
Formular. Anfragen, die etwas senden (POST, PUT …), und der Schritt von https zurück zu http enden an der
Weiterleitung (`src/core/abruf.gd`, geprüft in `tests/net_abruf.gd`).

### Test-Umleitungen

Für Proben mit nachgebauten Servern lassen sich die Adressen der Dienste, der Helfer, die JavaScript-Laufzeit der
Plugins und http zu diesem PC über Umgebungsvariablen (`UZAI_…`) umstellen. Das gilt nur in Entwickler-Fassungen
(Editor, Tests, Debug-Export): Im ausgelieferten Programm liest `Config.probe_env` sie nicht. Vorher hätte eine
gesetzte Variable Anmeldungen an eine fremde Adresse geschickt oder Plugins ohne Deno-Absicherung laufen lassen.

### Lokale Server

| Server | Grenzen |
|---|---|
| Steuer-Anschluss (TCP 47811) | nur 127.0.0.1; jeder Auftrag braucht den Sitzungsschlüssel (128 Bit) aus dem Datenordner, verglichen in fester Zeit; Zeile höchstens 4 KB; nur `launch <Kennung>` und `show` |
| Handy-Seite (TCP 47812) | nur, solange eine Eingabe oder ein Teilen offen ist; lauscht nur an der Heimnetz-Adresse; nimmt nur Absender aus dem Heimnetz; Zufallscode je Eingabe (128 Bit, Ablauf 10 bzw. 30 min); höchstens 64 KB (nur ein Bild an eine offene Bild-Eingabe des Mosaiks: 15 MB, 60 s) und 8 Anfragen gleichzeitig; `Host` muss eine IP sein (gegen DNS-Rebinding); strenge Kopfzeilen (CSP ohne Skripte, kein Referer, nicht einbettbar) |
| Rücksprung der Spotify-Anmeldung im Browser | nur 127.0.0.1, nur während der Anmeldung (höchstens 3 min), PKCE und Zufallswert (`state`), Kopf höchstens 8 KB |

### Helfer (`helper/uzai-helper.ps1`)

PowerShell mit eingebettetem C#, läuft mit deinen Rechten. Er nimmt Befehle nur über seine
Standardeingabe von Uzai, nur feste Befehle mit geprüften Argumenten (Zahlen, feste Werte, Pfade),
mit Zeitgrenzen. Kein `Invoke-Expression`. Programme startet er mit `UseShellExecute` nur dort, wo
Windows nach Adminrechten fragen soll.

**Vorhang** (`UzEbenen`, `src/core/vorhang.gd`): ein eigenes Fenster des Helfers, das nie aktiv wird,
keinen Taskleisten-Eintrag hat und Mausklicks durchlässt. Er deckt Spielstart und Spielende ab (mit
Zeitgrenze, wartende Fenster bleiben frei). Die Befehle nehmen nur Zahlen (Fensterkennungen, Farbe,
Zeitgrenzen bis 180 s). Keine Tastendrücke, kein Fokuswechsel.
Wann der Vordergrund wechselt oder ein Fenster des Spiels zugeht, meldet Windows über
`SetWinEventHook` nur außerhalb des fremden Prozesses (`WINEVENT_OUTOFCONTEXT`, nichts wird in ein Spiel
geladen). Der feine Zeitgeber (`timeBeginPeriod(1)`) gilt nur, solange der Vorhang steht, und nur für
diesen Prozess.

**Fernsehbild beim Herumlaufen** (`UzTvFang`, Befehl `tv-fang`, `src/room/spielbild.gd`): Läufst du im
Zimmer, liefert Windows die Bilder des Spielfensters über Windows Graphics Capture (nur lesen, ohne
Mauszeiger, gelber Rahmen aus, wo Windows es erlaubt). Die Grafikkarte rechnet sie klein (höchstens
1280 × 720); sie liegen in einer Zwischendatei im eigenen Temp-Ordner (`uzai-tvbild-<Helfer>.bin`,
temporär markiert, beim Stoppen gelöscht, Reste nur dieses Musters räumt der nächste Helfer weg). Uzai
liest dort nur einen festen Kopf (Kennung, Größen in festen Grenzen, Folgenummer vor und nach dem Bild)
und die Pixel – nichts wird gedeutet, gespeichert oder verschickt (auch nicht an Gäste im Zimmer). Der
Befehl nimmt nur Zahlen; ohne Lebenszeichen von Uzai (15 s) oder wenn das Fenster zugeht, endet die
Aufnahme von selbst. Rückfall nur, wenn das nicht geht: `window-frame` (PrintWindow) in langsamem Takt.

**Spielton aus dem Fernseher** (Befehl `raum-ton`, `src/room/raumton.gd`): Läufst du im Zimmer, während
das Spiel im Fernseher weiterläuft, setzt der Helfer nur die Kanal-Lautstärken (`IChannelAudioVolume`,
sonst die Lautstärke der Sitzung) der Audiositzungen des Spiels samt Kindprozessen – nie die
Gesamtlautstärke, nie andere Programme, Uzai selbst ausgenommen. Der Befehl nimmt nur Zahlen (links und
rechts 0..1000, Prozessnummern, Fensterkennung; der Spielordner wird nur verglichen). Die Werte von vorher
merkt sich der Helfer und stellt sie zurück: auf Wunsch, nach 5 s ohne Lebenszeichen von Uzai und wenn
Uzai den Helfer schließt; für einen Absturz von beiden steht der Vermerk in den Einstellungen und gilt
beim nächsten Start desselben Spiels. Den Fokus gibt Uzai dem Spiel nur im Vollbild
(`src/room/fernsehspiel.gd`); keine Tastendrücke, kein virtueller Controller.

**Beenden** (`prozessbaum`, `baum-beenden`, `src/core/launcher.gd`): Erst bittet Uzai das Spiel wie mit
Alt+F4, sich zu schließen; danach beendet der Helfer nur den Prozess, den Uzai selbst gestartet hat, und
dessen Kinder (Toolhelp-Liste; ein Kind zählt nur, wenn es nach seinem Elternteil gestartet ist) bzw. bei
Steam, Epic & Co. die Prozesse im Spielordner. Geschützte Programme (Windows, Steam, Discord, Uzai,
PowerShell) und alles darunter bleiben draußen, Prozesse werden nur zum Nachsehen geöffnet, beendet wird
mit deinen Rechten – lehnt Windows ab (Adminrechte), sagt Uzai das, statt mehr Rechte zu verlangen.
Die Befehle nehmen nur eine Prozessnummer.

**Windows-Einstellungen mit dem Controller** (Einstellungen → System → Windows, `src/core/win_einst.gd`,
`src/core/bild_ton.gd`): WLAN, Bluetooth, Energie, Tonausgabe, Auflösung und HDR nur über offizielle
Schnittstellen (Windows.Devices.WiFi/Radios/Enumeration, `WlanGetProfileList` nur lesend, Anzeige- und
Audio-Schnittstellen, `powercfg` mit fester Argumentliste und Werten aus einer festen Liste), nur auf
Knopfdruck und nie als Administrator. SSIDs und Gerätenamen sind fremde Daten: Der Helfer vergleicht
sie nur mit der Liste von Windows, sie stehen nie in einer Kommandozeile; auf dem Bildschirm ohne
Steuer- und Richtungszeichen. Ein WLAN-Passwort geht über die Standardeingabe als `PasswordCredential`
an Windows – Uzai speichert und protokolliert es nicht, die Handy-Eingabe ist dafür gesperrt. Eine neue
Auflösung gilt erst vorübergehend und geht ohne „Behalten“ nach 15 Sekunden zurück (auch nach einem
Absturz beim nächsten Start).

### Emulatoren im Hintergrund

Vor jedem Emulator-Start stellt Uzai (`src/core/emu_hintergrund.gd`) dort, wo der Emulator eine
Einstellung hat, „bei Fokusverlust weiterlaufen“ und „Controller nur mit Fokus“ ein – nur diese
Schlüssel in der Einstellungsdatei des Emulators (bekannter Name, in seinem Ordner, höchstens 2 MB).
Die alten Werte stehen in Uzais Einstellungen und kommen nach dem Spiel (bzw. nach einem Absturz beim
nächsten Start) zurück, aber nur, wenn sie noch so aussehen, wie Uzai sie geschrieben hat. Aus:
`system.emu_hintergrund` = false.

### Controller in den Emulatoren

Vor jedem Emulator-Start ergänzt Uzai (`src/core/spieler_emus.gd`) eine fehlende Controller-Belegung –
nur in der Einstellungsdatei des Emulators (bekannter Name, in seinem Ordner, höchstens 2 MB), nur die
Abschnitte der Spieler, und nur, wo keine Belegung auf einen angeschlossenen Controller zeigt. Neu
angelegt wird nur Dolphins GCPadNew.ini bzw. WiimoteNew.ini, und nur neben Dolphin.ini. Vor dem ersten
Schreiben liegt das Original in Uzais Ablage („Originale zurückholen“). Kein Treiber, kein virtueller
Controller. Aus: Einstellungen › Spieler & Controller › „Fehlende Belegung automatisch“.

### Emulator-Suche

Die Einrichtung und der Doktor suchen Emulatoren auch außerhalb von „Programme“ (`src/core/emu_suche.gd`,
Helfer-Befehl `emu-hints`). Alles nur lesen, nichts wird gestartet: Ordner mit fester Tiefe (höchstens
vier Ebenen) und Grenze (8000 Ordner, 12 Sekunden), Systemordner bleiben außen vor; Verknüpfungen
(`.lnk`) werden als fremde Daten gelesen (Größe, jede Länge und jeder Versatz geprüft, nur lokale
Pfade ohne `..`, nie eine Freigabe). `emu-hints` nimmt keine Eingaben, liest die Deinstallations-Einträge
der Registry und die Programmpfade laufender Prozesse samt Versionsangaben (nur lokale `.exe`), kürzt
Texte und begrenzt die Listen. Geprüft von `tests/logic_emu_suche.gd` und `tests/emusuche_cs.ps1`.

### Apps (Store-Apps und Programme)

Unter „Apps“ stehen neben den eingebauten Apps Store-Apps (Netflix, Disney+, Prime Video …) und
Programme, die du selbst wählst (Plex HTPC, Kodi, Moonlight, Steam Link) – `src/core/apps_extern.gd`,
Helfer-Befehle `store-apps`, `app-logo`, `app-start`, `prog-check`, `app-window`, `app-media`,
`app-vollbild`, `app-pad`. Geprüft von `tests/logic_apps.gd`, `tests/logic_app_steuerung.gd` (Uzai),
`tests/apps_cs.ps1` und `tests/tasten_cs.ps1` (Helfer, PowerShell 7).

| Was | Prüfung |
| --- | --- |
| App-Kennung (AUMID) | nur `<Paketname>_<Herausgeber>!<App>` nach dem Schema des App-Manifests (Paketname `A–Z a–z 0–9 . -`, 3–50 Zeichen, Herausgeber 13 Zeichen `a–z 0–9`, App-Kennung mit Buchstaben vorn, höchstens 64) – damit auch keine Platzhalter für `Get-AppxPackage`; in Uzai und im Helfer gleich |
| Store-App starten | nur, wenn genau dieses Paket für dein Konto installiert ist und die App in seinem Manifest steht; Start über `IApplicationActivationManager.ActivateApplication` ohne Parameter – nie `shell:AppsFolder`, nie eine Shell |
| Programm | nur eine `.exe` auf einem Laufwerk (keine Freigabe `\\server`, kein `\\?\`, kein `..`, keine Sonderzeichen, kein Punkt oder Leerzeichen am Ende eines Teils), höchstens 260 Zeichen |
| Gesperrt | Shells, Skript-Hosts und Werkzeuge, die Text als Befehl ausführen: cmd, PowerShell, pwsh, wscript, cscript, mshta, rundll32, regsvr32, WSL/bash, Windows Terminal, msiexec, msbuild, certutil, explorer, Interpreter (Python, Node, Java …) – auch umbenannt: der Helfer prüft den Originalnamen in den Versionsangaben der Datei. `.bat`, `.cmd`, `.ps1`, `.vbs`, `.js`, `.lnk` und alles außer `.exe` nimmt Uzai nicht an |
| Programm starten | `UseShellExecute` aus, Parameter als Liste (höchstens 16, je höchstens 260 Zeichen, ohne Steuerzeichen), jeder einzeln gequotet; verlangt es Adminrechte, startet es nicht (Uzai fragt nie nach mehr Rechten) |
| Rückfrage | ein Programm beim ersten Start; jede eigene App nach dem Wiederherstellen einer Sicherung. Die Bestätigung ist ein Fingerabdruck (Art, Kennung bzw. Pfad und Parameter) in `cache/apps_ok.json` – nie in einer Sicherung; geänderte Parameter fragen wieder |
| Gespeichert | im Profil (`apps.extern`), höchstens 40; jeder Eintrag wird beim Lesen neu geprüft (Kennung passt zum Inhalt), Unbekanntes fällt weg. Nicht im sicheren Modus und nicht im Kinderprofil |
| Liste der Store-Apps, Logo | nur lesen: Pakete deines Kontos, ihr `AppxManifest.xml` als XML ohne DTD und ohne Auflöser (höchstens 4 MB), Namen ohne Steuerzeichen; das Logo nur aus dem Paketordner, PNG bis 512 KB, von Uzai geprüft dekodiert und neu gespeichert |
| Was in der App läuft | nur die Windows-Mediensitzung genau dieser App (Titel, Interpret, Bild) – Uzai liest nichts aus den Diensten selbst und schickt nichts weiter |
| Laufende App | wie ein Spiel: Uzai behält die Guide-Taste und liegt als Kulisse hinter der App (statt Desktop und Taskleiste); Schließen bittet erst das Fenster und beendet dann nur den Prozessbaum, den Uzai gestartet hat. Die Maus mit dem Controller ist aus, bis du sie im Guide einschaltest, und geht mit der App aus. Kein Discord- oder Steam-Status, keine Spielzeit |
| Welches Fenster ist die App? (`Test-ExtAppWindow`) | nur eine Fensternummer, nie ein geschütztes Fenster (`UzGuard`) oder der Helfer selbst. Store-App: die App-Kennung am Fenster, an seinem Prozess oder – im Rahmen (`ApplicationFrameWindow`) – an seinem Inhalt ist genau ihre (nur lesen: `SHGetPropertyStoreForWindow`, `GetApplicationUserModelId`). Programm: der Prozess ist genau diese `.exe` oder eine `.exe` in ihrem Ordner (nie eine Shell; liegt sie direkt auf dem Laufwerk, nur sie selbst). Sonst passiert nichts |
| Vollbild (`app-vollbild`) | erst das eigene Vollbild der App (F11, nur aus der Liste für Apps, nur wenn genau dieses Fenster vorn ist, Grenze wie „an ein Fenster“); deckt sie den Bildschirm dann nicht, nimmt der Helfer **nur diesem Fenster** Titelleiste und Rahmen und legt es über den Bildschirm (Store-Apps im Rahmen: um ihre Titelleiste nach oben, eine Region schneidet genau den Bildschirm aus). Keine Systemeinstellung, die Taskleiste wird nicht angefasst (Windows legt sie hinter ein Vollbild-Fenster vorn). Zurück zu Uzai und Schließen stellen Stil und Lage wieder her, ohne das Fenster zu aktivieren – nur am selben Fenster desselben Prozesses |
| Controller in der App (`app-pad`) | siehe „Eingaben an Fenster“: nur Tasten aus der Liste für Apps, nur an das geprüfte Fenster, wenn es vorn ist; je App abschaltbar (Guide), aus bei Apps, die selbst Controller können (Kodi, Plex HTPC, Moonlight, Steam Link) |

### Uzai-Browser

Ein Browser, der für Controller gebaut ist. Die Seite stellt **Uzais eigener Chromium über CEF** dar (Chromium
Embedded Framework, BSD; offizielle, signierte Verteilung von `cef-builds.spotifycdn.com`, Chromium-Sandbox: jede
Seite in eigenen, eingeschränkten Prozessen). Der frühere WebView2-Wirt bleibt nur als ausdrückliche Einstellung
„Kern wählen › WebView2“ (nie stiller Rückfall). Alles, was man sieht, zeichnet Uzai. Geprüft von `tests/logic_browser.gd`, `tests/logic_browser_kern.gd`, `tests/logic_browser_filter.gd`
(Uzai) und `tests/browser_kern_cs.ps1`, `tests/browser_cs.ps1` (Kern und Wirt, PowerShell 7).

| Teil | Schutz |
| --- | --- |
| Sandbox (Pflicht) | Der Kern läuft nur im offiziellen `bootstrap.exe` von CEF (als `uzai-browser.exe` kopiert; nur so hat Chromium unter Windows seine Sandbox, ohne Uzai gegen die MSVC-Laufzeit zu linken). Der Bootstrap lädt daneben `uzai-browser.dll` – Uzais Start-Stummel (`helper/uzai-browser-start.c`, freistehendes C, 6,6 KB, reproduzierbar mit clang/lld gebaut, SHA-256 in `browser_kern.gd`, Helfer und Test): in Unterprozessen (Renderer, GPU, Netz) ruft er nur `cef_execute_process` **ohne .NET**; nur im Browserprozess lädt er die .NET-Laufzeit und `uzai-browser-kern.dll`. Der Kern prüft den Sandbox-Zeiger des Bootstraps, startet mit `no_sandbox = 0`, bricht jeden Kindprozess mit `--no-sandbox` ab und beendet sich mit `kern_sandbox`, wenn etwas fehlt – **lieber keine Seite als eine ohne Schutz**. Menü › Browser-Kern › Sandbox prüfen zeigt die Diagnose des laufenden Kerns |
| Kern laden (erstes Öffnen) | von selbst beim ersten Öffnen des Bereichs Browser (Nutzerwunsch: „automatisch mit drin“; Fortschritt auf der Startbühne, X bzw. „Abbrechen“ hält an), vorab nur mit Zustimmung (Einrichtung › Extras, `browser.kern_vorab`); Uzai lädt `stable.txt`, `<m>_windows64.json`, `revoked.json`, die signierte Verteilung (`…_windows64_signed.tar.xz`, höchstens 500 MB), die minimal-Verteilung derselben Fassung (`…_windows64_minimal.tar.bz2` oder `.tar.xz`, höchstens 400 MB, nur für den Bootstrap – die signierte hat keinen) und ihre `.sha256` nur per https vom festen Host, ohne Weiterleitungen, mit Größengrenzen; jeder Eintrag der Listen wird Feld für Feld geprüft (Fassung, Dateiname nach Muster, SHA-1, Größe, Typ, ABI-Hash; beide Archive mit gleichem Namen bis `_windows64`; die minimal-Verteilung steht nur im Gesamt-Index `index.json` – höchstens 64 MB, nur der Zweig `windows64` –, sonst gilt die `.sha1`-Beilage desselben Hosts), zurückgerufene Fassungen fallen weg; SHA-1 und, wo angegeben, Größe (Index) und SHA-256 (Beilage) jeder Datei müssen stimmen, sonst wird sie gelöscht. Der Helfer liest die Archive mit eigenem Entpacker (UzKernPack: xz/LZMA2, bzip2 und tar in verwaltetem C#, jeder Zugriff geprüft, Prüfsummen von Blöcken, Index und Fuß bzw. CRC je Block und Strom, auch der Block, in dem die gesuchte Datei endet; nicht Windows-`tar`, das xz nicht überall kann und Pfade mit Umlauten verliert) und holt genau eine Datei je Archiv (`cef_binary_…_signed/chrome_elf.dll`, `cef_binary_…_minimal/Release/bootstrap.exe`; 4 KB bis 16 MB, muss mit `MZ` beginnen) unter festem Namen in einen leeren Zwischenordner – kein Pfad aus dem Archiv wird Dateiname; er nimmt den Kopien die Signatur (sonst passt sie nicht zur unsignierten DLL) und legt Stummel, Skripte, Cookie-Regeln und Filterliste (SHA-256) daneben; dann prüft **CEFs eigener Installer** (`RunInstaller` im Bootstrap, aus dem Spiegel-Ordner, `vmin` = `vmax` = die geladene Fassung; im Spiegel liegt dazu roh vom Host das Manifest, das er mit ABI-Hash liest, `<abi_hash>_windows64.json` – vorher wie im Installer geprüft und nur, wenn es unseren Bau genau so führt) Katalog und Zertifikat der Verteilung (Fingerabdruck `3906F72B…7E5B`) und entpackt sie nach `%LOCALAPPDATA%\Uzai\browser\kern\store`. Nie Adminrechte (Helfer und Kern prüfen es) |
| Updates und Rückfall | höchstens einmal am Tag `kern update` (Installer sieht nach, lädt verifiziert im Hintergrund; neue Fassung gilt ab dem nächsten Start, Uzai sagt es); nach der ersten geladenen Seite meldet Uzai `gesund` (`launch_success`) – eine Fassung, die dreimal nicht sauber startete, fällt auf die bewährte zurück; die API ist festgenagelt (`CEF_API_VERSION` 15101, Hash geprüft, Struktur-Versätze gegen `tests/fixtures/cef_api_15101.json` getestet); passt eine Fassung nicht mehr (`kern_api`), bleibt die alte, und `vmax` schließt die neue aus |
| Browser-Kern (`helper/uzai-browser-kern.cs`) | vom Helfer einmal je Fassung übersetzt (`kern-bauen`, nie als Administrator), von Uzai mit fester Argumentliste gestartet (`--uzai-kern`, Profil-Kennung nach Muster, Sprache aus zwei Werten – sonst endet er); `remote_debugging_port = 0`, `command_line_args_disabled`, Komponenten-Updates, Erweiterungen, Chrome-Leisten, Synchronisation, Anmeldung aus (Alloy-Stil: nur Seiteninhalt); Fenster wird nie aktiv (`WS_EX_NOACTIVATE`, kein Taskleisten-Eintrag); kein eigener Anschluss, keine Named Pipe |
| Leitung Uzai ↔ Kern | anonyme Leitung über Standardein- und -ausgabe; JSON-Zeilen mit festem Schema in beiden Richtungen (`browser_protokoll.gd` = `UzbSchema`, Befehle höchstens 16 KiB, Ereignisse 768 KiB, strenger JSON-Leser, Listen mit Höchstzahlen: 60 Gliederungspunkte, 400 Optionen), Unbekanntes verworfen; der Kern schickt nur, was ins Schema passt. Der Installer-Lauf (`uzai-kernladen.exe --uzai-install`) bekommt genau eine Konfigurationszeile und meldet nur `kern`-Ereignisse |
| Uzais Skripte in der Seite (`uzai-browser-karte.js`, `uzai-browser-filter.js`) | über das DevTools-Protokoll **ohne Anschluss** in einer eigenen, isolierten Welt (`Page.addScriptToEvaluateOnNewDocument` mit `worldName`, Bindung nur in dieser Welt, nur Hauptrahmen); Befehle als Werte (`Runtime.callFunctionOn`), nie als Text, der Code wird; kein `eval`, kein Netz, kein Speicher, keine Cookies; melden Rechtecke, Überschriften, Optionen, Formular-Stand, Treffer-Zahlen, Blocker-Zähler, Video-Stand, Link-Ziel, Lesetext – Uzai prüft alles noch einmal |
| Blocker (`UzbFilter` = `browser_filter.gd`, `assets/browser/filter`) | Netz-Sperren prozessintern im Kern (`on_before_resource_load`, nie das Hauptdokument), Kosmetik als `<style>` in der isolierten Welt, Cookie-Banner: nur ein Ablehnen-/Nur-notwendige-Knopf nach Dienst-Regel oder Wortliste, nie „akzeptieren“, nie in fremden Rahmen; Listen (EasyList, EasyPrivacy, EasyList Cookie, CC BY-SA 3.0, `LIZENZ.txt`) sind reine Daten in eigener Grammatik (kein Regex, kein Skript), SHA-256 an drei Stellen gleich, kaputt = nicht geladen, kein Nachladen im Betrieb; Ausnahmen je Seite nur über das Menü. Ehrlich: kein SmartScreen/Safe Browsing – Phishing-Warnungen wie in Edge gibt es nicht |
| Brücken zur Seite | keine: keine Host-Objekte, keine Web-Nachrichten, keine Erweiterungen, DevTools-Fenster aus, eigene Kontextmenüs aus, Tastenkürzel des Browsers aus |
| Adressen | nur http und https, höchstens 4096 Zeichen, keine Anmeldedaten; **dieser PC nie** (localhost, 127/8, 0.0.0.0, ::1 und IPv4 in IPv6 in jeder Schreibweise – geprüft an den Zahlen der Adresse, nicht am Text –, Zahl-Namen und IPv4 mit führender Null, die Browser oktal lesen); das **Heimnetz** nur, wenn du die Adresse selbst eingibst, und dann nur dieser eine Name; Links, Weiterleitungen, Rahmen, Pop-ups und Unteranfragen genauso (gleiches Urteil in Uzai und Kern, `tests/fixtures/browser_urls.json`) |
| Andere Protokolle, Pop-ups, Downloads, Rechte, Dialoge, Zertifikate | wie bisher: Programm-Links gesperrt; Pop-ups nur nach einem Druck als Tab ohne `opener`; Downloads nur Daten-Dateiarten aus der Erlaubnisliste, nur in `Downloads\Uzai Browser`, nie geöffnet; Kamera/Mikrofon/Standort nur nach Rückfrage in Uzai (Ablehnen vorn, nach 60 s nein), alles andere abgelehnt; HTTP-Anmeldung, Client-Zertifikate, Eingabe-Dialoge gesperrt; Zertifikatsfehler: die Seite lädt nicht |
| Privatsphäre | eigenes Profil je Uzai-Profil unter `%LOCALAPPDATA%\Uzai\browser\kern-daten\profil\<profil>`; privater Tab ohne Spuren; keine Anmeldung, kein Passwort-Speicher, keine Absturzberichte, keine Telemetrie (Komponenten-Updates und Feldversuche aus); Verlauf löschbar; Vorschaubilder nur in Uzais Ordner |
| Eingaben und Anzeige | Klicks, Zeiger, Tasten und Text gehen über das DevTools-Protokoll nur in diese eine Seite; Text höchstens 2000 Zeichen ohne Steuer- und Richtungszeichen; Vorlesen nur mit der Stimme des Systems und nur Text des Lesemodus; alles, was Uzai zeigt, ist gesäuberter Klartext (nie BBCode); die Fokus-Falle hält den Cursor in einem offenen Dialog der Seite |
| Nur am Windows-PC prüfbar (hier ohne CEF-Binärdateien) | dass der Bootstrap die unsignierte Stummel-DLL annimmt und die Signaturen der Kopien sauber entfernt sind; `chrome://sandbox` bzw. die Diagnose zeigt „Sandboxed: Yes“; Leistung des eigenen Entpackers mit dem echten Archiv; der Installer-Lauf mit Katalog; Leistung mit Filterliste |

### Eingaben an Fenster

Alles, was der Helfer an Tasten, Klicks oder „Aufrufen“ erzeugt, mit Ziel und Schutz. Geprüft von
`tests/tasten_cs.ps1` (Helfer, PowerShell 7) und `tests/logic_tasten.gd` (Uzai), beide mit derselben
Tabelle böser und erlaubter Kürzel (`tests/fixtures/tasten_kombis.json`).

**Geschützte Fenster** (`UzGuard`): Anmelde-, Passwort- und Sicherheitsfenster bekommen nie eine Taste
von Uzai – UAC-Abfrage (`consent`), Windows-Anmeldedialog (`CredentialUIBroker`, Klasse „Credential
Dialog Xaml Host“), Anmelde- und Sperrbildschirm (`LogonUI`, `LockApp`, `winlogon`), Windows-Sicherheit
und SmartScreen, Konto-Anmeldung (`Microsoft.AAD.BrokerPlugin`, `UserAccountBroker`, `WWAHost`), Windows
Hello, Anmeldeinformationsverwaltung, KeePass/KeePassXC, 1Password, Bitwarden, Systemprozesse. Der
sichere Desktop (UAC, Strg+Alt+Entf) ist für Programme ohnehin unerreichbar; solange er offen ist,
meldet Windows kein Vordergrundfenster, und das gilt als „nein“. Fenster mit Adminrechten verwirft
Windows ohnehin (UIPI) – Uzai fragt nie nach mehr Rechten.

**Kürzel** (`Test-KeyCombo`): höchstens 40 Zeichen (nur Buchstaben, Ziffern, `+`, Leerzeichen),
höchstens 4 Tasten, keine doppelt, genau eine Nicht-Umschalttaste. Immer abgelehnt: Alt+F4, Alt+Tab,
Alt+Esc, Alt+Leertaste, Strg+Esc, Strg+Umschalt+Esc, Strg+Alt+Entf/Ende. *Tastenbelegungen* (Discord,
Lossless Scaling – wirken systemweit): nur Strg/Alt/Umschalt + eine Taste aus A–Z, 0–9, F1–F24,
Buchstaben und Ziffern nur mit Strg oder Alt, nie die Windows-Taste; Uzai prüft das vorher selbst
(`Helper.global_keys_ok`), auch für das Kürzel aus der Einstellungsdatei von Lossless Scaling. *An ein
Fenster vorn*: Windows-Taste nur für die Aufnahme-Kürzel der Game Bar (Win+G, Win+Druck,
Win+Alt+G/R/Druck) – nie Win+R, Win+X, Win+L. *Dialog bedienen*: nur Tab, Umschalt+Tab, Pfeile,
Enter, Leertaste, Esc. *Controller in einer eigenen App*: nur F11, Esc, Pfeile, Enter, Leertaste,
Backspace, Tab und Umschalt+Tab (Spalte „app“ der Tabelle; der Controller-Wächter prüft jeden Code
noch einmal, `UzPad.AppKeyOk`). Grenze je Helfer-Prozess (`Test-KeyRate`): Tastenbelegungen höchstens alle
0,4 s und 12 je Minute, an ein Fenster 0,12 s/60, Dialog 0,04 s/240, Medientaste 0,2 s/40.

| Befehl | Ziel | Schutz |
| --- | --- | --- |
| `app-pad` (Controller in einer eigenen App) | Steuerkreuz/linker Stick → Pfeile, A/B/X/Y/LB/RB → Tasten des App-Profils (`src/core/app_steuerung.gd`) – nur, solange genau das geprüfte App-Fenster vorn ist (Fensternummer **und** Prozess, `UzPad.AppTargetRule`); rechter Stick bewegt den Zeiger nur innerhalb dieses Fensters, RT klickt nur dort | Fenster vorher geprüft (`Test-ExtAppWindow`, nie geschützt); nur Tasten aus der Liste für Apps; höchstens alle 35 ms und 1200 je Minute; Guide und View + Start bleiben bei Uzai, die Maus mit dem Controller hat Vorrang; ist das Fenster weg, endet es von selbst; geht mit der App aus |
| `app-vollbild` mit `taste` | F11 an die App (ihr eigenes Vollbild) | wie `app-pad` geprüft; nur wenn genau dieses Fenster vorn ist, Grenze „an ein Fenster“ |
| `app-vollbild` (Rand oben, `UzAppRand`) | Mauszeiger bleibt knapp unter dem oberen Bildschirmrand (`ClipCursor`, 1/100 der Höhe, 8–40 Pixel), damit Windows bzw. der Browser im Vollbild keine Titelleiste und kein „X“ einblendet | nur, solange genau das geprüfte App-Fenster vorn liegt und seinen Bildschirm deckt und der Zeiger schon auf diesem Bildschirm ist; liegt etwas anderes vorn (Uzai, Guide, ein Dialog) oder ist das Fenster weg, sofort frei – und nur die eigene Grenze (die eines Spiels wird nie angefasst); keine Tasten, keine Systemeinstellung |
| `app-pad` (Textfeld, `UzAppFeld`) | liest über UI Automation nur Art, Zustand und Prozess des fokussierten Elements (Textfeld ja/nein, Passwortfeld) – nie seinen Inhalt; Y öffnet dann Uzais Bildschirmtastatur statt der Taste des Profils | nur, solange genau das App-Fenster vorn liegt, nur Elemente ihres Prozesses (bzw. des Inhalts im Rahmen); alle 350 ms in eigenem Faden; geht mit `app-pad` aus |
| `app-text` (Text aus Uzais Tastatur) | Zeichen (`KEYEVENTF_UNICODE`, keine Tasten mit Umschalt/Strg/Alt) in das Textfeld der App | Fenster wie `app-pad` geprüft; Text 1–500 Zeichen ohne Steuer-, Richtungs- und unsichtbare Zeichen (`UzPad.AppTextOk`, in Uzai `AppSteuerung.text_ok`); Grenze „an ein Fenster“; wartet höchstens 2,5 s, bis genau dieses Fenster vorn ist; nur wenn dort ein Textfeld den Fokus hat; vor jedem Zeichen erneut: Fenster vorn, nie geschützt – sonst Abbruch |
| `mouse` (Maus mit dem Controller) | Bewegen, Scrollen, Klicken (A/X): überall – dafür ist sie da (`SendInput`) | nur, solange Uzai sie einschaltet; die Guide-Taste bleibt bei Uzai. **B = Esc** nur an das Vordergrundfenster, auf dem der Zeiger liegt oder das du zuletzt per Controller angeklickt hast, und nie an ein geschütztes Fenster |
| `keys` | Fenster aus `hwnd`/`pid`/`pids`: Emulator (Speichern/Laden), Spiel (Clip-Kürzel, Steam-Overlay), Discord und Steam-Chat (Strg+V, Enter) | Kürzel „an ein Fenster“; nur Zahlen als Ziel; geschütztes Ziel wird nicht einmal nach vorn geholt; gedrückt wird nur, wenn das Ziel danach wirklich vorn ist – `require_focus` gilt immer, ohne Ziel passiert nichts |
| `keys` mit `global` | Lossless Scaling (skaliert das Spiel vorn) | wie `keys`, dazu das enge Format für Tastenbelegungen |
| `live-keys` | Discord „Toggle Screen Share“ (Discord hört systemweit mit) | enges Format, Grenze; gedrückt wird nur, wenn vorn das Spiel/mpv, Uzai oder das schon beim Befehl vorn liegende Fenster ist – nie ein inzwischen aufgetauchtes oder geschütztes |
| `window-keys`, `window-focus` | Installationsdialog von Steam oder Epic in Uzai bedienen | Fenster muss nach Prozessname **und** Programmpfad zu Steam (Steam-Ordner aus der Registry des eigenen Kontos) oder Epic (`…\Epic Games\Launcher\…`) gehören; nur die Dialog-Tasten; nur, wenn es vorn ist |
| `media` | Mediensitzung der Musik-App (gezielt, Windows-Medienschnittstelle) | die globale Medientaste (wirkt auf alles, was Ton hat) nur, wenn keine Sitzung direkt steuerbar ist **und** du gerade selbst gedrückt hast (`user`); nie beim Anhalten durch Ruhemodus oder Spiel-Profil; nur feste Aktionen |
| `discord-buttons`, `discord-invoke` (UI Automation „Aufrufen“) | „Bildschirm teilen“/„Live gehen“ in der Discord-App; mit `app: steam` Knöpfe in Steams Installationsdialog | Fenster nach Prozessname und Pfad (`%LOCALAPPDATA%\Discord…\app-…\Discord….exe` bzw. Steam-Ordner); gedrückt wird nur ein Knopf aus der zuletzt gelesenen Liste, nachdem Fenster und Prozess des Knopfs nochmals geprüft sind |
| `spotify-fenster`, `spotify-fenster-spielen` (UI Automation lesen, blättern bzw. „Aufrufen“) | Grundmodus von Spotify: Namen und Spotify-Adressen (Kennung der Zeile bzw. Link, nur `spotify:(playlist\|album\|artist\|show):<22>` und `spotify:user:<name>:collection`) aus „Deine Bibliothek“, „Zuletzt gespielt“ und Suchergebnissen des Spotify-Fensters; die Bibliothek ganz über das Bildlauf-Muster (ScrollPattern, alte Stelle danach wieder); einen Abspiel-Knopf daraus drücken – abgespielt wird sonst über Spotify Connect mit der Adresse | Fenster nach Prozessname und Pfad (`%APPDATA%\Spotify\Spotify.exe` oder Store-Paket `SpotifyAB.SpotifyMusic_…__zpdnekdrzrea0`); höchstens 20000 Knoten, Tiefe 48, 600 Einträge, 20 s; Texte gekürzt und ohne Steuerzeichen. Zum Blättern nur, wenn Uzai vorn liegt (nie, wenn Spotify vorn ist): das Fenster für die Dauer des Lesens fast durchsichtig (Deckkraft 1/255), klickdurchlässig, ohne Aktivierung an den rechten Bildschirmrand (2 Punkte sichtbar) und danach zurück (minimiert bzw. an seinen Platz, Stil wie vorher; eine Markierung am Fenster räumt auch ein abgebrochenes Lesen auf). Gedrückt wird nur ein Knopf aus der letzten Liste mit gleichem Namen und Prozess; springt Spotify dabei nach vorn, minimiert der Helfer es sofort (Windows gibt den Vordergrund an Uzai zurück). Keine Tasten, Klicks, Fokuswechsel, Debug-Ports, DLLs, kein Lesen von Spotifys Speicher, Cache oder Anmeldung |
| `discord-front` | Discord-App nach vorn (Senden, Übertragen) | nur die echte Discord-App (Name und Pfad) |
| Fokuswechsel (`focus`, in `keys`/`live-keys`) | kurzes Alt (`keybd_event`) – die bekannte Notlösung, damit Windows den Fokuswechsel erlaubt | nie, solange ein geschütztes Fenster vorn ist |
| `close-window` | `WM_CLOSE` an das Spielfenster (wie Alt+F4, aber als Bitte) | nur Zahlen, nie der Helfer selbst |
| `monitor` (an) | eine Mausbewegung um 1 Pixel hin und zurück | weckt nur den Bildschirm |
| `cursor-park` | Mauszeiger an den Bildschirmrand (`SetCursorPos`) | kein Klick |
| Wächter nach dem Schließen | Uzai nach vorn (Alt-Notlösung) | nur Uzai |

`UzInput.ClickAt` steht noch im Quelltext, wird aber von keinem Befehl benutzt.

### Kommandozeile

`--profil=` nur mit gültiger Kennung, `--launch=` nur mit einer Kennung aus der Bibliothek.
Test-Schalter (`--uzai-script=` und Proben) laden im fertigen Uzai nur Skripte aus `res://tests/`,
die der Export weglässt – nie eine Datei von der Platte.

### Zwischenablage, Dateiauswahl, Handy-Eingabe

Codes aus der Zwischenablage werden in der Länge begrenzt und laufen durch denselben Prüfer wie
Dateien. Was vom Handy kommt, ist Text mit Längengrenze; Schlüssel und Adressen prüft die Stelle,
die sie verwendet.
Bilder vom Handy (Mosaik, `src/ui/layers/mosaik_handy.gd`): nur mit Einmal-Code, nur PNG, JPEG
oder WebP nach dem echten Dateikopf (Name, Typ und Pfad vom Handy zählen nie), höchstens 15 MB und
8192 Punkte je Seite; Uzai dekodiert mit `Image.load_*_from_buffer` und speichert das Bild neu
kodiert unter eigenem Namen im Medienordner – die Originaldatei wird nie gespeichert oder ausgeführt.
Die Bildersuche öffnet das Handy selbst (nur ein Link); Uzai fragt keine Suchmaschine ab.

## Bekannte Grenzen

- **Deno und IPv6:** Deno nimmt in `--deny-net` keine IPv6-Bereiche. Gesperrt sind `[::1]`, `[::]`,
  IPv4 in IPv6 und alle Adressen dieses PCs (damit auch das Lauschen an ihnen). Andere Geräte im
  Heimnetz über IPv6-ULA (`fd…`) bleiben für ein bösartiges Plugin erreichbar, wenn dein Heimnetz
  IPv6 nutzt. Abhilfe wäre Deno im AppContainer ohne „privateNetworkClientServer“ (wie der
  Zimmer-Prototyp) – nur am Windows-PC prüfbar, noch nicht gebaut.
- **Plugins untereinander:** Alle Plugins eines Abrufs laufen in einem Deno-Prozess und können die
  Einstellungen der anderen Plugins (den Auftrag) lesen. Trage in Plugin-Einstellungen keine
  Schlüssel ein, die ein anderes Plugin nicht sehen soll.
- **Handy-Seite ohne Verschlüsselung:** Die Seite im Heimnetz läuft über http. Wer im selben WLAN
  mitliest, sieht, was du vom Handy schickst (etwa einen Schlüssel). In fremden WLANs (Hotel, Café)
  die Handy-Eingabe nicht nutzen.
- **Prüfsummen der Werkzeuge** kommen vom selben Anbieter (GitHub-Release) wie die Datei. Sie
  schützen vor kaputten und unterwegs veränderten Downloads, nicht vor einem gekaperten Release.
- **Emulatoren ohne veröffentlichte Prüfsumme:** RetroArch (Buildbot) und Dolphin veröffentlichen keine
  SHA-256. Uzai bietet sie nur in der Fassung an, deren SHA-256 fest im Code steht (`RA.KATALOG`). Die
  Werte stammen aus den Scoop-Manifesten der Fassung und sind vor jeder Uzai-Veröffentlichung gegen die
  offizielle Datei zu prüfen. Neuere Fassungen zeigt Uzai nur an, bis ihre Prüfsumme in Uzai steht.
- **RetroArch-Kerne:** Der Buildbot baut sie täglich neu und nennt je Kern nur eine CRC32
  (`.index-extended`). Sie schützt vor kaputten Downloads, nicht vor einem gefälschten Server – dagegen
  hilft nur https zum festen Host. Uzai lädt nur Kerne mit freier Lizenz aus einer festen Liste und legt
  sie nur in sein eigenes RetroArch.
- **Emulator-Pakete von GitHub:** Wie bei den Werkzeugen kommt die Prüfsumme vom selben Release wie die
  Datei; sie schützt nicht vor einem gekaperten Projekt.
- **Remote-Play-Starter:** Der Auftrag liegt im Ordner des Spender-Spiels. Steam-Bibliotheken sind
  oft für alle Windows-Konten beschreibbar; ein anderes Konto am selben PC könnte dort einen Auftrag
  ablegen – oder ebenso gut die Spieldatei selbst ersetzen. Auf PCs mit mehreren Konten, denen du
  nicht traust, Remote Play über Uzai nicht einrichten.
- **Geteilte Plex-Server:** Die Adressen eines geteilten Servers nennt sein Besitzer. Uzai fragt
  dort nur nach der Kennung des Servers (`/identity`) und nutzt ihn nur, wenn sie passt.
- **mpv-Steuerung:** mpv nimmt Befehle über eine benannte Pipe an, die nur dein Konto beschreiben
  darf (Windows-Standard). Programme unter deinem Konto können mpv darüber steuern.
- **WLAN-Passwort im Arbeitsspeicher:** Bis die Speicherbereinigung von Godot bzw. PowerShell es
  freigibt, liegt das Passwort kurz im Speicher von Uzai und des Helfers. Programme unter deinem Konto
  könnten es dort lesen – wie bei jedem Programm, in das man ein Passwort tippt.
- **Epic-Einmal-Code in der Befehlszeile:** Wie bei Legendary steht der Code in der Befehlszeile des
  Spiels; Programme unter deinem Konto können sie lesen. Der Code gilt nur wenige Minuten und nur
  einmal (das Spiel löst ihn beim Start ein). Wer das nicht will: Konten → Epic Games → Mehr.
- **Uzai-Browser und DNS:** Die Sperren für diesen PC und das Heimnetz prüfen die Adresse, nicht, wohin
  ein Name aufgelöst wird. Ein Name im Internet, der auf `127.0.0.1` oder ins Heimnetz zeigt (DNS-Rebinding),
  bleibt ein Restrisiko; dagegen hilft der Schutz für private Netze von Chromium selbst. Uzais Anschlüsse auf
  127.0.0.1 verlangen ohnehin einen Schlüssel.
- **WebView2 und Diagnosedaten:** Uzai sendet nichts. Die WebView2-Laufzeit von Microsoft schickt
  Diagnosedaten nach der Windows-Einstellung „Diagnose und Feedback“; Absturzberichte aus dem Browser hat Uzai
  abgeschaltet. Sicherheits-Updates der Engine kommen über Windows/Edge – Uzai kann sie nicht verzögern.
- **Uzai-Browser und Seiten:** Eine Seite kann ihren DOM-Baum so bauen, dass Uzais Sprung-Skript sich
  verirrt (falsche Ziele, Ziele unter einem Overlay). Das betrifft nur das Springen, nie die Sicherheit: Klicks
  gehen nur in diese Seite. Rahmen anderer Seiten (eingebettete Videos, Karten) sind nur mit dem
  Magnet-Zeiger erreichbar. Pop-ups ohne Verbindung zur öffnenden Seite brechen manche Anmeldungen über
  ein zweites Fenster.
- **Link-Vorschau und DNS:** Uzai prüft die Namensauflösung vor dem Abruf; Godot merkt sich das
  Ergebnis. Ein Name, der zwischen Prüfung und Abruf umgestellt wird, bleibt ein Restrisiko.

## Lücken melden

Bitte melde Sicherheitslücken **nicht** als öffentliches Issue, sondern vertraulich über **GitHub
Security Advisories** des Repositorys (Reiter „Security“ → „Report a vulnerability“) oder über den
Meldeweg auf der Homepage von Uzai, sobald es sie gibt. Hilfreich sind: Uzai-Version, Windows-Version,
Schritte zum Nachstellen, was ein Angreifer dafür braucht und was er erreicht. Bitte keine Angriffe
auf fremde Konten, Server oder Geräte, um eine Lücke zu zeigen.

## Ergebnis der Sicherheitsprüfung (23.10.2026)

Prüfung des gesamten Codes nach Art eines Pentests (Punkte 78/80): Angriffsfläche kartiert (alle
Netz-Antworten, Launcher-Dateien, Themes und Zimmer, Handy-Seite und Steuer-Anschluss, Plugins,
Helfer-Befehle, Kommandozeile, Zwischenablage, Profile, Sicherungen; alle Prozessstarts, Datei-
Schreib- und Löschstellen), je Fläche gezielt angegriffen, mit echtem Deno 2.9 gegen die Plugin-
Sperren. Regressionstests: `tests/logic_pentest.gd`, dazu `tests/net_handy.gd` und
`tests/logic_plugin_rechte.gd`.

| Schwere | Fund | Behebung |
|---|---|---|
| hoch | Steam-Links aus Chats und aus dem Status eines Freundes gingen mit beliebigem Anhang an Steam (`steam://connect/<host>/<…>` – Anhänge landen als Startparameter im Spiel) | nur feste Form (`Sicher.steam_join_ok`) in Chat, Freundesstatus, Spielstart |
| hoch | Bildadressen aus fremden Daten (Addon-Poster, Plugin-Logos) wurden als lokaler Pfad geprüft, auch `\\server\freigabe\…` – Windows hätte dabei die Anmeldung (NTLM-Hash) an fremde Rechner geschickt | Freigabe-Pfade nie öffnen (`Sicher.local_path_ok` in `Media`) |
| mittel | Plugin-Repository: Skript-Adressen aus dem fremden Manifest (auch Weiterleitungen) durften ins Heimnetz zeigen; Uzai legte die Antwort in den Plugin-Ordner, den jedes Plugin lesen und ins Internet schicken kann (Umgehung der Deno-Sperre) | nur gleicher Server wie das Repository oder https ins Internet, Weiterleitungen einzeln geprüft |
| mittel | Link-Vorschau im Chat rief beliebige Adressen ab, auch Router und `127.0.0.1`, und folgte Weiterleitungen | nur Internet-Adressen, Namen aufgelöst und geprüft, Weiterleitungen einzeln geprüft |
| mittel | Bild-Bomben: ein kleines PNG mit riesiger Größe belegte entpackt bis 1 GB je Bild | Größe aus dem Kopf vor dem Dekodieren, Grenze 8192 Pixel je Seite |
| mittel | `--uzai-script=<Datei>` lud im fertigen Uzai jede GDScript-Datei von der Platte | im Export nur `res://tests/` |
| mittel (offen) | Deno sperrt keine IPv6-Bereiche (Heimnetz über ULA erreichbar, Lauschen an eigener IPv6) | eigene Adressen des PCs gesperrt; Rest siehe „Bekannte Grenzen“ |
| niedrig | Daten-Antworten ohne Größengrenze | 64 MB je Antwort |
| niedrig | Steuer-Anschluss: Schlüsselvergleich nicht in fester Zeit, Zeile unbegrenzt | fester Zeitvergleich, 4 KB |
| niedrig | Rücksprung der Spotify-Anmeldung las Anfragen unbegrenzt | höchstens 8 KB |
| niedrig | Handy-Seite nahm jeden `Host` an (DNS-Rebinding; der Zufallscode schützte schon) | nur IP-Adressen als `Host` |
| niedrig | Steam-ID im Aufnahmen-Teilen ungeprüft in einem `steam://`-Link | nur Ziffern |

Ohne Befund geprüft: Deserialisierung (keine gefährlichen Aufrufe im Code), ZIP-Leser für Themes und
Zimmer (Zip-Slip, Bomben, Verknüpfungen), Sicherungen (nur erlaubte Pfade), Profil-Löschen (keine
Verknüpfungen), Argument-Maskierung für mpv/yt-dlp/FFmpeg, Helfer ohne `Invoke-Expression`,
lauschende Anschlüsse nur in `remote.gd`, Tresor (DPAPI), Absturzbericht (Namen, Pfade, Schlüssel
werden entfernt), Plex/Jellyfin/Emby/Stremio-Anbindung und die UDP-Suche.

**Nur am Windows-PC prüfbar:** NTLM-Verhalten von Godots Dateizugriff auf Freigaben (die Sperre
greift unabhängig davon), Steam-Verhalten bei präparierten `steam://`-Links, Deno mit IPv6 im
echten Heimnetz, Windows-Firewall-Abfragen beim Öffnen der Handy-Seite und der UDP-Suche.

## Zweite Sicherheitsprüfung (17.11.2026, vor der Veröffentlichung)

Drei unabhängige Prüfer (je ein Bereich: Netz und fremde Server; Helfer und Programmstarts; Browser, Downloads,
Anmeldungen und Protokolle), jeder Fund danach im Code gegengeprüft. Dazu eine Suche nach eingetragenen Schlüsseln in
allen Git-Dateien: keine eigenen Geheimnisse im Code (der Nuvio-Schlüssel ist Nuvios öffentlicher „publishable key“,
alles andere sind Testwerte und Zeichenvorräte). Regressionstests in `tests/logic_pentest.gd`.

**Fremde Client-Kennungen (Stand Release-Review):** Im Code stehen öffentlich bekannte Kennungen fremder Apps, die
Uzai für deren Anmeldeweg braucht – der Google-Client der YouTube-TV-App samt „Secret“ (`src/core/youtube_tv.gd`),
der Client des Epic-Launchers (`src/library/epic_online.gd`) und die Web-Client-Kennungen von Twitch
(`src/core/twitch_parse.gd`). Sie gehören den jeweiligen Firmen, sind in deren eigenen Apps für jeden auslesbar und
schützen nichts (Geräte- bzw. PKCE-Ablauf, das Konto schützt erst die Anmeldung des Nutzers). GitHubs Geheimnis-Suche
kann trotzdem anschlagen; die Nutzung verstößt womöglich gegen die Bedingungen der Dienste (README „Legal“).

| Schwere | Fund | Behebung |
|---|---|---|
| hoch | `\??\UNC\server\…` (und `\??\GLOBALROOT\Device\Mup\…`) kam an `Sicher.local_path_ok` vorbei – ein Addon-Poster hätte Windows die Anmeldung (NTLM) an einen fremden Rechner schicken lassen | `?` und `*` nie in einem lokalen Pfad; Bildfelder von Addons nur `http(s)://` (`MoviesDaten.bild`) |
| mittel | Discord-RPC: Uzai verband sich mit der ersten Leitung `discord-ipc-N`, ohne zu prüfen, wer sie angelegt hat, und schickte die Discord-Anmeldung dorthin (Leitungsnamen gelten für den ganzen PC) | Server-Prozess muss in derselben Sitzung laufen und die Discord-App sein (`UzRpc.IstDiscord`, Pfad wie bei Fenstern); nur `discord-ipc-[0-9]` |
| mittel | Ton-Leitungen der Aufnahme (Mikrofon, Systemton): Windows-Vorgabe gab „Jeder“ und „Anonym“ Lesezugriff, Verbindungen übers Netz erlaubt, Name vorhersagbar | DACL nur für dieses Konto, Kennzeichnung „mittel“, `FILE_FLAG_FIRST_PIPE_INSTANCE`, `PIPE_REJECT_REMOTE_CLIENTS`, Zufallsname; der Ton geht nur an das selbst gestartete FFmpeg (`GetNamedPipeClientProcessId`) |
| mittel | Browser: Jeder Befehl an das Seiten-Skript trug `userGesture` – auch der Filter gleich nach dem Laden. Jede Seite hätte so ohne Tastendruck Pop-ups (vorn) öffnen und in die Zwischenablage schreiben dürfen | `userGesture` nur bei Befehlen nach einem Tastendruck (aktivieren, Link, Feld, Video, Auswahl) |
| mittel | Browser-Kern: `chrome_elf.dll` (und der Bootstrap) liefen, bevor eine Signatur geprüft wurde | `chrome_elf.dll` muss gültig vom CEF-Zertifikat signiert sein; ein signierter Bootstrap ebenso (der Bootstrap der minimal-Verteilung ist unsigniert, Stand CEF 156 – für ihn bleibt die Prüfsumme vom CEF-Server) |
| mittel | mpvs Protokoll enthielt die Befehlszeile mit `X-Plex-Token`/`X-Emby-Token`, und `logs/player.log` die ganze Stream-Adresse einer Fehlerzeile (Addon-Schlüssel im Pfad) | `PlayerLog.sauber` (Adressen nur bis zum Host, Schlüssel, Tokens, IPs raus); mpvs Protokoll wird nach dem Ende gelöscht |
| niedrig | Medienserver-Schlüssel hing an jeder Bildadresse desselben Servers, auch an einer, die ein Addon nennt (`/:/scrobble`, Bibliothek neu einlesen) | Schlüssel nur an Uzais eigene Bildpfade (`Net.media_bildpfad`: Plex `/photo/:/transcode`, Jellyfin/Emby `…/Items/<id>/Images/…`) |
| niedrig | Browser: Die selbst eingegebene Heimnetz-Adresse blieb nach Verlassen der Seite freigegeben – die nächste Seite hätte den Router ansprechen können | Freigabe endet, sobald der Tab zu einem anderen Host navigiert |
| niedrig | mpv-Steuerkanal mit festem Namen (`uzai-mpv`): vorher belegt, hätte ein anderes Konto die Stream-Adressen mitgelesen | Zufallsname je Start |
| niedrig | Handy-Seite: Ein Gerät im WLAN konnte ohne Code mit 64 KB aus `\r` den Hauptfaden auslasten | Kopfende nur im neuen Teil suchen, Kopf höchstens 8 KB (431) |

**Zimmer online (eigener Prüfer, Frage: Können Fremde über die Verbindung zwischen Uzai-Nutzern Code ausführen?):**
Kein Weg gefunden. Standard aus, nichts lauscht, kein `uzai://`-Link; die Sandbox startet erst nach mehreren
eigenen Drücken. Ein Fremder erreicht nur die Sandbox (AppContainer, nur `internetClient`): verwalteter C#-Leser,
libsecp256k1, AES-GCM ohne Schlüssel scheitert; Uzai.exe bekommt nur feste Rahmen aus Ganzzahlen, nie Bilder,
Schriften, Variants oder Pfade der Gegenseite. Der Einladungscode trägt 144 Bit Zufall. Theoretisch bliebe nur eine
Kette aus zwei unbekannten Lücken (in der Sandbox **und** ein AppContainer-Ausbruch).

| Schwere | Fund | Behebung |
|---|---|---|
| mittel | Discord-Meldung (Erwähnung in einem gemeinsamen Server, keine Freundschaft nötig): Das angehängte Bild wurde ohne Klick mit den Original-Bytes des Absenders im Hauptprozess dekodiert (libpng/libjpeg/libwebp, Godots BMP-Lader) | Vorschau nur über Discords Bild-Proxy, neu kodiert als PNG (`Notify.proxy_bild`); BMP aus dem Netz wird nie gespeichert |
| niedrig | Treffpunkt: Ein Dritter ohne Einladung konnte mit selbst signierten Ereignissen an die öffentlich sichtbare Postfach-Kennung Wiederholungsschutz und Drossel füllen – jeder Besuchsaufbau scheiterte | Wiederholungsschutz und Postfach-Drossel erst nach dem Entschlüsseln; Drossel je Relay 200/s |
| niedrig | Doku: `Online.BEREIT` stand als `false`, die Sperrliste als „dauerhaft“ | berichtigt (SECURITY.md, ZIMMER_SICHERHEIT.md W2/W13) |

## Updates

Uzai aktualisiert sich selbst über die Releases auf GitHub (`src/core/updater.gd`, Einstellungen › System › Updates:
Automatisch, Nur melden, Aus). Ein Updater ist selbst ein Angriffsweg – wer ein Update fälschen kann, führt Code auf
jedem PC aus. Darum:

- **Signatur statt Vertrauen in GitHub:** Jedes Release trägt neben `Uzai-X.Y.Z-windows.zip` eine `.sig` (JSON) mit
  einer RSA-Signatur über Format, Fassung, Dateiname und SHA-256 des Pakets. Uzai prüft sie mit dem öffentlichen
  Schlüssel, der im Programm steckt (`Updater.SCHLUESSEL`). Wer das GitHub-Konto oder den Download-Server übernimmt,
  kann ohne den privaten Schlüssel kein Update unterschieben. Der private Schlüssel liegt nur beim Herausgeber, nie im
  Repository (`tools/release_signieren.gd` legt ihn nur außerhalb des Projekts an). Ohne eingetragenen Schlüssel meldet
  Uzai ein Update nur.
- **Erst Signatur, dann Paket:** Uzai lädt das Paket nur nach gültiger Signatur, und nur mit genau der signierten
  Prüfsumme (`Net.download_verified`). Nur Adressen unter `https://github.com/<Repository>/releases/download/`.
- **Nur bekannte Dateien:** Aus dem Paket kommen nur `Uzai.exe`, `Uzai.pck` und `discord_partner_sdk.dll`, ohne
  Ordner; alles andere lehnt das Paket ab. Eine ältere Signatur passt nie zu einer neueren Fassung.
- **Einspielen beim Beenden:** Der Helfer (`-Update`) wartet, bis Uzai weg ist, tauscht die Dateien mit Sicherung
  (`.alt`) und holt bei einem Fehler alles zurück. Läuft gerade wieder ein Uzai aus demselben Ordner, wartet er auf das
  nächste Schließen. Keine Adminrechte; liegt Uzai in einem Ordner ohne Schreibrecht, meldet es das Update nur.
- Proben: `tests/logic_updater.gd` (Fassungen, fremde Adressen, Signatur mit Probe-Schlüssel, fremde und manipulierte
  Signaturen, Pfad-Tricks und fremde Dateien im Paket), `tests/update_cs.ps1` (Einspielen und Rückweg im Helfer).

**Offen (bewusst nicht in dieser Runde):**
- *Service Worker im Browser-Kern:* Anfragen eines Service Workers haben in CEF keinen Browser und laufen nicht über
  Uzais Anfrage-Prüfung; die Heimnetz-Sperre greift dort nur, soweit Chromium selbst (Private Network Access) sie
  durchsetzt. Lösung: ein `CefRequestContextHandler` mit derselben Prüfung oder Service Worker abschalten.
- *Steuer-Anschluss belegt:* Ein anderes Windows-Konto kann `127.0.0.1:47811` vor Uzai belegen; Uzai hält es für eine
  laufende Uzai und beendet sich. Lösung: Frage-Antwort mit dem Schlüssel aus der PID-Datei (HMAC über eine Nonce).
- *Handy-Seite:* höchstens 8 Verbindungen gesamt, keine Grenze je Absender (ein Gerät kann die Plätze belegen).
- *Alter WebView2-Wirt (nur auf Wunsch):* Heimnetz nur nach IP-Literalen, Namen wie `fritz.box` nicht.
