# Dein Zimmer online – Bedrohungsanalyse und Sicherheitsplan

Gilt für Punkt 131 („Dein Zimmer“, Stufe 4 und Gäste ohne Uzai) und ist laut ROADMAP Pflicht **vor**
dem Bau. Wunsch des Nutzers, wörtlich: „EXTREM sicher gegen RCE-Angriffe und Bots, kein Zugriff auf
meinen Rechner – SEHR WICHTIG“. Darum steht hier zuerst, was ein Angreifer versuchen kann und wie
jeder einzelne Weg zu ist – und erst dann, was gebaut wird.

**Stand 10.11.2026: eingeschaltet für Uzai zu Uzai (`Online.BEREIT = true`), Standard aus.** Die
Gesamtprüfung vor dem Einschalten steht in Abschnitt 10, dort auch, was offen bleibt. Die Tabelle
darunter zeigt das Fundament:

| Teil | Datei | Stand |
|---|---|---|
| Bedrohungsanalyse | dieses Dokument | fertig, vor jedem weiteren Schritt fortschreiben |
| Nachrichten-Protokoll Fassung 2 (binär, feste Längen, Prüfmauer 2) | `src/room/netz_protokoll.gd` | fertig (Phase 1), Fuzz-Tests und Abgleich mit der Sandbox in `tests/logic_zimmer_netz.gd` |
| Einladung (Schlüssel hinter „#“, je Einladung genau ein Freund) | `src/room/einladung.gd`, `src/room/online.gd` | fertig, ohne Versand |
| Gastgeber-Logik (Anklopfen nur für Eingeladene, Annahme, Rauswerfen, Sperren, Grenzen) | `src/room/online.gd` | fertig, nur mit Beispiel-Gästen |
| Bedienung „Online“ (Zimmer-Menü und Einstellungen → System) | `src/room/online_ui.gd` | fertig, zeigt klar „aus“; Anklopfen, Gästeliste, Sperrliste und „Zimmer offline“ mit Beispiel-Gästen |
| Sandbox-Prozess (AppContainer, nur `internetClient`) mit schmaler Leitung und Prüfmauer 1 | Helfer `-ZimmerNetz` und `zimmer-netz-probe` (`UzNetzSchema`, `UzaiZimmerNetz.Netz`), Leitung `src/room/zimmer_netz.gd` | fertig (Phase 2) mit Test-Gegenstelle statt Netz; unter Linux geprüft (`tests/zimmer_sandbox_cs.ps1`, Pipe-Lauf in `tests/logic_zimmer_netz.gd`), AppContainer selbst **nur am Windows-PC prüfbar** |
| Treffpunkt (Nostr-Relays, AES-256-GCM mit dem Link-Schlüssel, Sitzung per ECDH P-256, strenger JSON-Leser, Wiederholungsschutz, Drossel, SDP-Prüfer) | Helfer: `UzKrypto`, `UzJson`, `UzNostr`, `UzSdp`, `UzTreff`, `UzRelays`; Uzai: `src/room/treffpunkt.gd` | gebaut (Phase 3), mit BIP-340-Signatur (libsecp256k1, `UzSecp`), geprüft mit `tests/zimmer_treff_cs.ps1`, `tests/netzlibs_cs.ps1`, `tests/logic_treffpunkt.gd` und zwei Instanzen gegen ein Test-Relay (`tests/net_zimmer_treff.gd`) |
| WebRTC-Datenkanal | Helfer: `UzRtc`, `UzDirekt` (libdatachannel über P/Invoke); `src/room/verbindungstest.gd` | gebaut (Phase 4), unter Linux mit zwei Instanzen über 127.0.0.1 geprüft (echter Kanal, beide Prüfmauern, böse Gegenstelle); ICE aus dem AppContainer **nur am Windows-PC prüfbar** |
| Freundestest (echte Einladung als Code, Gast, Figuren im Zimmer, Protokoll) | `src/room/freundestest.gd`, `einladung.gd` (Code), `einladung_ui.gd`, `besucher.gd` | gebaut, nur im Testbetrieb; unter Linux mit zwei Instanzen geprüft (`net_zimmer_treff`, `logic_freundestest`); zwei PCs **nur am Windows-PC prüfbar** |
| Netz-Bibliotheken | `assets/net/`, `tools/bau_netzlibs.sh`, `UzNetzLib` | selbst gebaut aus gepinnten Quellen (Abschnitt 5), nur in der Sandbox geladen |

Online geht das Zimmer nur, wenn alle vier Bedingungen aus Abschnitt 10 gelten; sonst bleibt es offline, egal
was eingestellt ist. Der **Testbetrieb** (Einstellung „Testbetrieb“, Standard aus) bleibt für die Fehlersuche:
Er schaltet den „Verbindungstest“ frei –
zwei Sandboxen auf diesem PC, nur ohne Adminrechte und nur, wenn „Abschottung prüfen“ gerade alles
bestanden hat (Container, beide Prüfmauern, beide Bibliotheken). Beim Verbindungstest kann niemand von außen
anklopfen: Der Link entsteht und bleibt im Test. Der **Freundestest** (gleiche Bedingungen) erzeugt dagegen eine
echte Einladung als kurzen Code, den der Nutzer selbst verschickt – sie gilt einmal und kurz, herein kommt nur,
wen er annimmt, und der Gast ändert nichts am Zimmer (siehe W3).

---

## 1. Was geschützt wird

1. **Der PC des Gastgebers** – Dateien, Programme, Einstellungen, Konten, Kamera/Mikrofon, das
   Heimnetz (Router, NAS, andere Geräte). Höchstes Gut.
2. **Der PC jedes Gastes** – gleiches Ziel, umgekehrte Richtung (ein böser Gastgeber).
3. **Privatsphäre** – IP-Adresse, wer mit wem wann im Zimmer war, Figur, Zimmer-Inhalt
   (Spieletitel), Kamerabild (Extra i).
4. **Der Herausgeber** – betreibt nichts, speichert nichts, verarbeitet keine personenbezogenen
   Daten (R6); keine Infrastruktur, die angegriffen, beschlagnahmt oder missbraucht werden kann.
5. **Die Stimmung im Zimmer** – kein Spam, keine Bots, kein Belästigen, Gastgeber hat das letzte Wort.

## 2. Angreifer

| Nr. | Angreifer | Hat | Will |
|---|---|---|---|
| A1 | **Bot / Scanner im Internet** | nichts außer Rechenzeit, liest öffentliche Relays mit | offene Ports finden, Spam, bekannte Lücken ausnutzen |
| A2 | **Relay-Betreiber** (Nostr) | alles, was über sein Relay läuft, und die IP-Adressen der Verbindungen | mitlesen, Metadaten sammeln, Nachrichten fälschen/zurückhalten/wiederholen |
| A3 | **Netz dazwischen** (WLAN im Café, Provider) | sieht und verändert Pakete | mitlesen, Mann in der Mitte |
| A4 | **Jemand mit einem abgefangenen Link** (weitergeleiteter Screenshot, Chatverlauf) | den Einladungsschlüssel | ins Zimmer kommen |
| A5 | **Angenommener, aber böser Gast** (oder ein gekapertes Uzai/Browser eines Freundes) | direkte, verschlüsselte Verbindung, kennt das Protokoll, schickt beliebige Bytes | Code beim Gastgeber ausführen, Uzai abstürzen lassen, IP herausfinden, belästigen |
| A6 | **Böser Gastgeber** | dasselbe in die andere Richtung, schickt Zimmer-Schnappschüsse und Stream | Code beim Gast ausführen, Gäste aushorchen |
| A7 | **Lücke in einer Fremdbibliothek** (WebRTC/libdatachannel, OpenSSL/mbedTLS, Godot selbst) | eine unbekannte Speicherlücke, die A5/A6 auslösen können | aus dem Zimmer heraus auf den PC |
| A8 | **Gefälschte Uzai-/Web-Version** | eine nachgebaute Seite oder ein manipuliertes Update | Schlüssel abgreifen, Schadcode verteilen |

## 3. Angriffswege und Schutz je Weg

**Übersicht (Bedrohungsmodell):**

| Weg | Angreifer | Schutz | Geprüft durch | Stand |
|---|---|---|---|---|
| W1 Uzai von außen erreichen | A1 | keine offenen Ports, kein UPnP; Sandbox ohne `internetClientServer` | `tests/zimmer_sandbox_cs.ps1` (Fähigkeiten) | gebaut (Sandbox), ICE am PC offen |
| W2 Treffpunkt fluten/fälschen | A1, A2 | AES-256-GCM mit Einladungs-Schlüssel, Wiederholungsschutz, Zeitfenster, Drossel je Relay und Postfach, strenger JSON-Leser | `zimmer_treff_cs.ps1`, `net_zimmer_treff` | gebaut (ohne Nostr-Signatur) |
| W3 Einladung abgefangen | A4 | je Einladung genau ein Freund, kurz gültig, einmal nutzbar, Annahme nötig | `logic_zimmer_netz` (Gastgeber) | Logik gebaut |
| W4 Mann in der Mitte | A2, A3 | DTLS-Fingerabdruck im SDP, versiegelt mit dem Sitzungsschlüssel (ECDH, an Link-Schlüssel gebunden) | `zimmer_treff_cs.ps1` | Treffpunkt gebaut, DTLS mit Phase 4 |
| W5 IP-Adresse | A1, A4, A5 | IP erst nach Annahme und nur im Sitzungsschlüssel versiegelt, Heimnetz-Adressen und `raddr` raus, ehrlicher Hinweis | `zimmer_treff_cs.ps1`, `net_zimmer_treff` | Treffpunkt gebaut, ICE mit Phase 4 |
| W6 Code ausführen über Nachrichten | A5, A6 | Protokoll Fassung 2: nur Zahlen, feste Längen, Wertebereiche, kein Text, keine Namen; zwei Prüfmauern; Drossel | `logic_zimmer_netz` (Fuzz, Grenzen, gleiches Urteil wie die Sandbox), `zimmer_sandbox_cs.ps1` | gebaut (Phase 1) |
| W7 Lücke in WebRTC/mbedTLS/Godot | A7 | AppContainer (nur `internetClient`), Job-Objekt, keine Dateien, keine Kindprozesse, schmale Leitung, Prüfmauer 2 in Uzai; Bibliotheken nur in der Sandbox, schmal gebaut (kein Medien-, WebSocket-, Server-Code, Mbed TLS nur DTLS 1.2 AEAD) | `zimmer_sandbox_cs.ps1`, `netzlibs_cs.ps1`, Pipe-Lauf, „Abschottung prüfen“ am PC | gebaut, am PC zu prüfen |
| W14 Lieferkette, DLL-Laden | A7, A8 | Quellen am festen Commit mit SHA-256 je Datei, selbst gebaut und bit-gleich nachbaubar; Prüfsumme in Uzai, Helfer und Sandbox; voller Pfad, Datei beim Laden gesperrt, Abhängigkeiten nur aus System32; kein DllImport mit Suchpfad | `netzlibs_cs.ps1`, `bau_netzlibs.sh --pruefen` | gebaut |
| W15 Fremder Code schreibt auf die Leitung | A7 | Sandbox nimmt eine eigene Kopie der Standardausgabe; die der C-Laufzeit wird geschlossen (Windows) bzw. auf /dev/null gelegt, bevor eine Bibliothek lädt; Protokoll-Ausgabe der Bibliotheken ausgebaut | `netzlibs_cs.ps1` | gebaut |
| W8 Adminrechte | A5, A7 | Probe und Sitzung verweigern den Start mit Adminrechten | `zimmer_sandbox_cs.ps1` | gebaut |
| W9 Absturz/Speicher | A5, A6 | Längen vor dem Lesen, höchstens 3632 Byte je Nachricht, 8 KiB je Rahmen, Drossel je Gast, 256 MB Job-Grenze | Fuzz in beiden Tests | gebaut |
| W10 Eingaben fälschen | A5 | Gäste senden nur Position, Blick, Emote, Schnellsatz | `logic_zimmer_netz` | gebaut (Protokoll) |
| W11 böser Gastgeber | A6 | derselbe Leser in die andere Richtung; Zimmer nur aus Katalog-Nummern | `logic_zimmer_netz` (Rolle Gast) | gebaut |
| W12 gefälschte Version | A8 | signierte Updates, statische Web-Seite mit CSP/SRI | – | später |
| W13 Belästigung, Spam | A4, A5 | kein freier Chat, keine selbst gewählten Namen, Sperren, Drossel, Rauswurf | `logic_zimmer_netz` | gebaut (Logik) |

### W1 – Uzai von außen erreichen (A1)
- **Weg:** offene Ports, UPnP-Weiterleitung, ein Dienst, der auf Anfragen wartet.
- **Schutz:** Uzai öffnet **nie** einen Port nach außen und nutzt **kein UPnP/NAT-PMP**. Es gibt nur
  ausgehende Verbindungen (zu Relays) und eine WebRTC-Verbindung, die erst nach Annahme entsteht
  und bei der beide Seiten selbst nach außen „lochen“ (ICE). Ein Scanner findet nichts, woran er
  klopfen kann. Im Sandbox-Prozess fehlt zusätzlich die Fähigkeit „internetClientServer“ – er darf
  gar nicht lauschen (siehe W11, offen: ob ICE ohne diese Fähigkeit reicht).

### W2 – Über den Treffpunkt (Nostr-Relays) einschleusen (A1, A2)
- **Weg:** Bots lesen öffentliche Relays mit, schicken massenhaft Ereignisse an die Zimmer-Kennung,
  fälschen oder wiederholen alte Nachrichten.
- **Schutz:**
  - Jede Nachricht über den Treffpunkt ist mit dem **Schlüssel aus dem Link** authentifiziert
    verschlüsselt (AEAD, Abschnitt 5). Was sich damit nicht öffnen lässt, wird **ungelesen**
    verworfen – der Inhalt kommt nie bis zum Protokoll-Leser, geschweige denn zu Uzai.
  - Die Zimmer-Kennung im Relay-Filter ist **zufällig** (128 Bit, eigene Zufallszahl, nicht aus dem
    Schlüssel abgeleitet) und verrät nichts. Ohne Link kennt ein Bot sie nicht; mit ihr allein kann
    er trotzdem nichts Gültiges schicken.
  - **Wiederholungsschutz:** jede Nachricht trägt Zeitstempel und Zufallszahl im verschlüsselten
    Teil; zu alt (über 2 Minuten) oder schon gesehen → verworfen.
  - **Mengen:** höchstens `Online.ANKLOPFEN_JE_MINUTE` Anklopfer je Minute, höchstens
    `Online.MAX_WARTEND` gleichzeitig wartend, alles darüber wird ohne Antwort verworfen.
  - Relays werden nur als „Briefkasten“ genutzt: **flüchtige Ereignisse** (Nostr-Arten 20000–29999),
    die Relays nicht speichern; jede Einladung nutzt einen **Wegwerf-Nostr-Schlüssel** – kein Konto,
    keine Identität, keine Verbindung zwischen zwei Abenden.
  - Mehrere Relays als Rückfall; ein Relay, das Unsinn liefert, schadet nicht (wird verworfen).
    Ein Relay, das flutet, bremst nur sich selbst (Drossel je Relay: 200/s, Vorrat 400; je Postfach
    5/s, Vorrat 30) – zur Not auch echte Nachrichten über dieses Relay; die anderen tragen weiter.
    Seit 17.11.2026 zählen Wiederholungsschutz und Postfach-Drossel erst **nach** dem Entschlüsseln: Das
    Postfach ist öffentlich sichtbar und signieren kann jeder – ein Dritter ohne Einladung konnte vorher mit
    eigenen Ereignissen den Wiederholungsschutz füllen und jeden Besuchsaufbau scheitern lassen.
    Mehr als 16 KiB, Binär-Rahmen oder kaputtes UTF-8 trennen die Verbindung (danach neu, mit Pause).

### W3 – Einladung abgefangen (A4)
- **Weg:** Eine Einladung landet bei Fremden.
- **Schutz:** Anklopfen kann **nur, wer eingeladen wurde**: Jede Einladung geht an genau einen
  Freund (Steam-Chat oder Discord-Direktnachricht) und trägt beim Gastgeber dessen Namen aus Uzais
  eigener Freundesliste – der Gast schickt keinen Namen. Die Einladung allein lässt **niemanden
  herein**: Der Gastgeber sieht, wen er eingeladen hat, und entscheidet (Annahme, Ablehnen,
  Sperren). Einladungen laufen ab (Standard 60 Minuten, wählbar 15 min bis 24 h), sind **immer nur
  einmal nutzbar** (kein Schalter) und lassen sich jederzeit **zurückziehen**. Die frühere Wahl „Wer darf
  anklopfen“ (offener Link oder nur Freunde) gibt es nicht mehr.
- **Freundestest-Code** (`einladung.gd` `neu_code`/`code_lesen`): `UZAI-` + 35 Zeichen Crockford-Base32. Inhalt
  144 Bit Zufall und die Ablauf-Minute; Kennung und Schlüssel per HKDF-SHA256 (RFC 5869, HMAC aus mbedTLS) –
  wer die Ablaufzeit ändert, landet in einem fremden, leeren Postfach. Der Gast liest den Ablauf nur, um ehrlich
  „abgelaufen“ zu sagen; gültig ist, was der Gastgeber in seiner Liste hat. Gelesen wird höchstens 120 Zeichen,
  nur Leerraum, Bindestriche, Präfix und das Alphabet – kein Link, kein Text drumherum. Prüfzeichen (gewichtete
  Summe mod 1021 + 5 Bit SHA-256) finden jeden Tippfehler in einem Zeichen und jeden Nachbar-Dreher
  (`tests/logic_freundestest.gd`: alle 1116, dazu 28 000 Fuzz-Eingaben). Den Namen wählt der Gastgeber beim
  Einladen; der Gast sieht „Gastgeber“. Im Protokoll `logs/zimmer_online.log` stehen nie Code, Schlüssel,
  Kennung, Name oder Adresse (beide Tests prüfen das).
- Der Schlüssel steht **nur hinter „#“** (Fragment). Browser schicken das Fragment nie an einen
  Server; die statische Web-Seite liest es nur im Browser. Uzai zeigt den Link nie in Logs.

### W4 – Mitlesen und Mann in der Mitte (A2, A3)
- **Weg:** Verbindungsdaten (SDP, ICE-Kandidaten) unterwegs austauschen, eigenen DTLS-Schlüssel
  unterschieben.
- **Schutz:** SDP und ICE gehen **nur verschlüsselt und signiert** über den Treffpunkt. WebRTC ist
  immer DTLS-verschlüsselt; der **DTLS-Fingerabdruck** steht im verschlüsselten SDP und wird beim
  Verbindungsaufbau geprüft – wer den Link-Schlüssel nicht hat, kann keinen eigenen Fingerabdruck
  unterschieben. Zusätzlich geht das SDP nur mit dem **Sitzungsschlüssel** (ECDH P-256 aus dem
  Wegwerf-Schlüssel im Anklopfen und dem des Gastgebers, an den Link-Schlüssel gebunden) – den hat nur
  der angenommene Gast; der Gastgeber nimmt genau diesen Schlüssel an.

### W5 – IP-Adresse herausfinden (A1, A4, A5)
- **Weg:** Bei einer direkten Verbindung sieht die Gegenseite die IP-Adresse.
- **Schutz:** Die eigene IP geht **erst raus, wenn der Gastgeber angenommen hat** (vorher nur
  verschlüsselte Nachrichten über Relays – die sehen die IP wie jede Webseite, aber nicht den
  Inhalt). Uzai **sagt das ehrlich** vor dem ersten Einschalten und im Online-Bereich
  („Hinweis zur IP-Adresse“). Lokale Adressen (192.168.x.x usw.) werden aus den ICE-Kandidaten
  entfernt, außer der Gast ist im selben Netz und der Gastgeber erlaubt das. **Keine IP-Adressen in
  Logs**. Kein eigener Vermittlungsserver (TURN); wer eine verdeckte IP will, kann später einen
  eigenen TURN eintragen (Fortgeschrittene).
- Erst nach der Annahme fragt die Sandbox zwei feste öffentliche STUN-Server (Google, Cloudflare) nach der
  eigenen öffentlichen Adresse – die sehen die IP wie jede Webseite, nichts sonst. Die Standard-Adresse in
  `c=`/`m=` des SDP setzt der Prüfer immer auf 0.0.0.0 bzw. Port 9 (libdatachannel trüge dort sonst den
  ersten Kandidaten ein, auch einen aus dem Heimnetz).

### W6 – Code beim Gastgeber ausführen über Nachrichten (A5) – **RCE, höchste Priorität**
- **Weg:** präparierte Nachrichten, die einen Parser, eine Godot-Ressource, ein Skript, eine
  Bild-/Modelldatei, einen Text oder einen Link auslösen.
- **Schutz (alle gleichzeitig):**
  1. **Nichts von außen wird ausgeführt oder als Godot-Ressource geladen.** Nie `str_to_var`,
     `bytes_to_var`/`bytes_to_var_with_objects`, `Expression`, `ResourceLoader`, `load()`,
     `JSON.to_native` oder `Marshalls.base64_to_variant` auf fremden Daten. Im Zimmer-Netz gibt es
     auch kein JSON mehr (der Test sucht im Quelltext danach).
  2. **Protokoll Fassung 2, komplett binär** (`netz_protokoll.gd`): Kopf `U`, Fassung 2, Art; jede
     Art hat **eine feste Länge** und feste Stellen: `hallo` 8 Byte (Gerät, Schema-Stempel), `pos`
     13 (x, y, z in cm, Blick und Neigung in Milliradiant – begrenzte Ganzzahlen), `emote` 4 (Nummer
     aus den 7 Emotes der Figur), `satz` 4 (Nummer aus 12 festen Schnellsätzen), `figur` 30 (je Feld
     die Nummer der Option), `zimmer` 32 + 12 je Möbel (nur vom Gastgeber, höchstens 300 Möbel),
     `tschuess` 3. Was nicht genau passt – Länge, Fassung, Art, ein Wert außerhalb, ein gesetztes
     Reserve-Bit –, wird **abgelehnt**, nicht zurechtgebogen.
  3. **Kein freier Text, keine Namen:** Den Chat gibt es nicht mehr, Schnellsätze sind Nummern (den
     Text liefert Uzai selbst, übersetzt), Gäste schicken keinen Namen (angezeigt wird der Name,
     unter dem du den Freund eingeladen hast), der Name des Haustiers bleibt zu Hause.
  4. **Schema-Stempel:** `hallo` trägt einen SHA-256-Stempel über alle Listen, die Nummern bedeuten
     (Emotes, Sätze, Figur, Katalog, Wände, Böden, Licht). Passt er nicht, versteht man sich nicht –
     statt dass Nummern bei verschiedenen Fassungen Falsches bedeuten.
  5. **Zwei Prüfmauern:** Prüfmauer 1 in der Sandbox (`UzNetzSchema`, C#) und Prüfmauer 2 in Uzai
     (`struktur_ok` + Bedeutung) prüfen nach denselben Regeln; Uzai prüft zusätzlich, was nur Uzai
     wissen kann (Varianten und Stufen je Möbel, Stempel, Zimmer-Prüfer `pruefe_raum`). Lässt die
     Sandbox etwas durch, das schon Prüfmauer 1 hätte abweisen müssen, schließt Uzai die Leitung.
  6. **Grenzen vor dem Lesen:** höchstens 3632 Byte je Nachricht, 8 KiB je Rahmen, 64 KiB je Lesen.
  7. **Keine Dateien, Bilder, Modelle, Links oder Skripte von Gästen.** Zimmer bestehen nur aus
     **Katalog-Nummern** (eigene Möbel bleiben zu Hause), Figuren nur aus Nummern der Optionen.
  8. **Raten-Grenzen** je Gast und Art (Token-Eimer `Drossel`, in beiden Mauern gleich); wer sie
     dauernd reißt oder Unsinn schickt, wird von selbst hinausgeworfen.
  9. **Fuzz-Tests** (`tests/logic_zimmer_netz.gd`, deterministische Saat): 4000 × Rauschen, 5000 ×
     kaputt gemachte gültige Nachrichten, 3000 × zufällig gültige Pakete; nichts darf abstürzen oder
     einen Wert außerhalb der Grenzen liefern. Dazu 6000 Pakete aus demselben Zufallsgenerator in
     GDScript und C#: Beide Mauern müssen über jedes dasselbe Urteil fällen (gleicher Fingerabdruck).

### W7 – Lücke in WebRTC/OpenSSL/Godot (A7) – **Sandbox**
- **Weg:** Ein Speicherfehler in einer Bibliothek, die Netzwerkdaten zuerst anfasst (DTLS, SCTP,
  ICE, Video-Dekoder).
- **Schutz:** Alles, was rohe Daten aus dem Netz anfasst, läuft **in einem eigenen Prozess in
  einem Windows-AppContainer** (Abschnitt 6): keine Dateien außer einem eigenen leeren Ordner,
  keine Programme starten (Job-Objekt mit höchstens einem Prozess, Kindprozesse verboten), kein
  Zugriff auf Uzai, Heimnetz oder localhost, nur ausgehendes Internet. Zu Uzai führt nur eine
  **schmale Leitung**: Uzais Pipe zum Helfer wird direkt die Standardeingabe und -ausgabe des
  Sandbox-Prozesses (der Helfer schreibt darauf nichts), mit festen Rahmen (4 Byte Länge, Art,
  höchstens 8 KiB). Jede Art gilt nur in ihrer Richtung; ein falscher Rahmen beendet die Sandbox
  (Code 3) bzw. schließt die Leitung in Uzai. Über die Leitung gehen nur Nachrichten, die
  Prüfmauer 1 durchgelassen hat, und Uzai prüft sie **noch einmal** (Prüfmauer 2). Auch
  Ausgehendes prüft die Sandbox: Den PC verlassen nur Schema-Nachrichten.
  Selbst eine fremde Lücke im Sandbox-Prozess sitzt dann fest.
- Native Bibliotheken nur in fester, geprüfter Version mit Prüfsumme (libsecp256k1, libdatachannel samt
  libjuice, usrsctp, Mbed TLS; Abschnitt 5), Sicherheits-Updates schnell und signiert (Punkte 66, 67, 74).
- Der Datenkanal ist schmal: genau ein ausgehandelter Kanal (Strom 0), Kanäle, die die Gegenstelle selbst
  öffnet, schließt die Sandbox sofort; nur Binärnachrichten bis 4096 Byte (größere kürzt die Bibliothek,
  Text zählt als Verstoß); höchstens 32 Nachrichten je Takt und Platz, 256 KiB SCTP-Puffer, 64 KiB
  Sendestau; Rückrufe aus nativen Fäden setzen nur Zahlen (fest gehaltene Delegaten, auch nach dem Ende).

### W8 – Uzai mit Adminrechten (A5, A7)
- **Schutz:** Uzai fordert **nie** Adminrechte an. Läuft Uzai trotzdem erhöht (z. B. von Hand
  „Als Administrator ausführen“), lässt sich das Zimmer **nicht** online schalten – ehrlicher
  Hinweis statt Verbindung. Der Sandbox-Prozess erbt ohnehin nur ein AppContainer-Token.

### W9 – Abstürzen lassen / Speicher füllen (A5, A6)
- **Schutz:** Größen- und Mengengrenzen vor dem Lesen, feste Höchstzahl an Gästen
  (`Online.max_gaeste`, Standard 4, höchstens `MAX_GAESTE_GRENZE` = 8), Drossel je Gast; Speichergrenze für den
  Sandbox-Prozess (Job-Objekt). Stürzt der Sandbox-Prozess ab, ist das Zimmer offline – Uzai läuft
  weiter.

### W10 – Eingaben fälschen, „Mitspielen“ missbrauchen (A5)
- **Schutz:** Gäste können nur **ihre Figur bewegen, Emotes zeigen und feste Schnellsätze sagen**
  – Möbel umstellen kommt erst mit einer eigenen Nachrichtenart; bis dahin ist der Schalter
  dafür ausgeblendet. Mitspiel-Eingaben (später) sind ein festes Format (Tasten/Sticks), gelten nur,
  solange der Gastgeber „Mitspielen“ erlaubt, gehen nur ins Spiel (RetroArch an localhost bzw.
  Windows-Gamepad-Einspeisung) und **nie** als Tastatur/Maus; kein virtueller Treiber, keine globale
  Tastatur-Simulation. Die Guide-Taste eines Gastes erreicht nie Windows.

### W11 – Böser Gastgeber gegen Gäste (A6)
- **Schutz:** derselbe Leser in die andere Richtung. Im Freundestest zeigt der Gast das Zimmer des Gastgebers nur
  als Kopie (geprüft mit `pruefe_raum`): Bauen, Anpassen und Einräumen sind gesperrt, gespeichert wird nichts,
  sein eigenes Zimmer bleibt unberührt und kommt nach dem Besuch zurück. Gäste nehmen vom Gastgeber nur `zimmer`
  (Katalog-Nummern), Figuren, Positionen, Emotes und Schnellsätze; den Stream (später) als Video über WebRTC – im
  Browser dekodiert der Browser, in Uzai der Sandbox-Prozess.

### W12 – Gefälschte Web-Version / Updates (A8)
- **Schutz:** Web-Version nur statisch über HTTPS mit strenger Content-Security-Policy, ohne fremde
  Skripte, Dateien mit Prüfsummen (Subresource Integrity); `uzai://`-Links streng geprüft
  (`einladung.gd`); Updates signiert (Punkte 66, 67).

### W13 – Belästigung, Spam (A4, A5)
- **Schutz:** Kein freier Chat und keine selbst gewählten Namen – nichts, womit man beleidigen,
  werben oder täuschen könnte. Nur Eingeladene klopfen an, Annahme nötig, Rauswerfen und **Sperren**
  mit einem Druck, Sperrliste für den laufenden Besuch (nur im Speicher, über den Fingerabdruck des
  Wegwerf-Schlüssels, der sich je Besuch ändert – nicht dauerhaft),
  Drossel für Emotes und Schnellsätze.
  Kein öffentliches Zimmer-Verzeichnis. Jugendschutz/DSA → Anwalts-Prüfung (R9).

## 4. Entscheidungen

1. **Treffpunkt:** öffentliche **Nostr-Relays**, mehrere als Rückfall, kein eigener Server
   (entschieden in Punkt 131). Nur flüchtige, verschlüsselte Ereignisse, Wegwerf-Schlüssel.
2. **Verbindung:** **WebRTC, Ende-zu-Ende verschlüsselt** (DTLS-SRTP/SCTP), Fingerabdruck über den
   verschlüsselten Treffpunkt geprüft. Godots offizielles webrtc-native (MIT), fest auf geprüfte
   Version mit Prüfsumme – **nur im Sandbox-Prozess** geladen.
3. **Schlüssel nur hinter „#“** im Link: `uzai://zimmer#z1.<Kennung 128 Bit>.<Schlüssel 256 Bit>`
   bzw. dieselbe Form auf der statischen Web-Seite. Beides base64url, feste Länge, sonst nichts.
4. **Anklopfen** mit Nachweis des Link-Schlüssels (die Nachricht lässt sich nur damit erzeugen),
   gedrosselt je Minute; **Annahme durch den Gastgeber** – vorher keine direkte Verbindung, keine IP.
5. **Keine offenen Ports, kein UPnP**, kein Vermittlungsserver des Herausgebers.
6. **Nie Admin.** Online nur, wenn Uzai ohne erhöhte Rechte läuft.
7. **AppContainer-Sandbox** für alles, was rohe Netzdaten anfasst; nur die Fähigkeit
   `internetClient`; eigener leerer Ordner; Job-Objekt (ein Prozess, Speichergrenze, keine
   Kindprozesse, keine Zwischenablage, kein Desktop-Zugriff); schmale Pipe zu Uzai.
8. **Online ist aus, bis man es einschaltet**; „Zimmer offline“ mit einem Druck; beim Beenden von
   Uzai endet alles (Job-Objekt schließt den Sandbox-Prozess mit).

## 5. Kryptografie-Plan

**Grundsatz: keine Eigenbau-Kryptografie.** Weder eigene Verfahren noch eigene Zusammensetzungen
aus Bausteinen, wo es eine fertige, geprüfte Funktion gibt.

### Was Godot 4.5 mitbringt (geprüft)

| Klasse | Kann | Taugt für das Zimmer? |
|---|---|---|
| `Crypto.generate_random_bytes` | Zufall aus mbedTLS CTR_DRBG, vom Betriebssystem gesät | **ja** – Einladungs-Kennung und -Schlüssel (`einladung.gd`) |
| `Crypto.constant_time_compare` | Vergleich ohne Zeit-Leck | **ja** – Schlüssel vergleichen |
| `Crypto.hmac_digest`, `HMACContext` | HMAC-SHA1/SHA256 | nur als Baustein; kein AEAD |
| `HashingContext` | MD5, SHA-1, SHA-256 | Prüfsummen von Dateien, nicht für Schlüssel |
| `AESContext` | **nur AES-ECB und AES-CBC**, ohne Authentifizierung | **nein** – kein GCM, kein Poly1305; CBC ohne MAC ist angreifbar (Padding-Orakel). Eine eigene „Encrypt-then-MAC“-Zusammensetzung wäre genau die Eigenbau-Krypto, die wir ausschließen |
| `Crypto.sign/verify`, `CryptoKey` | RSA (PKCS#1 v1.5), Schlüssel erzeugen nur RSA | **nein** – kein Ed25519, kein X25519, kein secp256k1 |
| `StreamPeerTLS`, `DTLSServer` | TLS/DTLS über mbedTLS | nur für eigene TLS-Verbindungen; nicht für Nachrichten über Relays |

**Ergebnis:** Godot allein reicht **nicht** für authentifizierte Verschlüsselung der
Treffpunkt-Nachrichten und nicht für Nostr-Signaturen. Godot übernimmt nur Zufall und Vergleich
(erneut geprüft mit Godot 4.5.1: `AESContext` kennt nur ECB/CBC, `Crypto` erzeugt nur RSA,
`WebRTCPeerConnection` braucht eine Erweiterung – im Projekt liegt keine).

### Was gebaut ist (Phase 3, ohne neue Abhängigkeit)

Die Sandbox ist ein .NET-Programm; dort gibt es geprüfte Verfahren aus dem Betriebssystem:

| Baustein | Woher | Wofür |
|---|---|---|
| AES-256-GCM | Windows CNG (`bcrypt.dll`); unter Linux nur für Tests .NET `AesGcm` (OpenSSL) | jede Nachricht über die Relays (Nonce 12 Byte Zufall, Tag 16 Byte); Zusatzdaten „UZ1“ + Typ + Postfach (+ Fingerabdruck) binden jede Kiste an Richtung und Sitzung |
| ECDH P-256 + SHA-256 | .NET `ECDiffieHellman` (CNG bzw. OpenSSL), `DeriveKeyFromHash` | Sitzungsschlüssel = SHA-256(„UZ1-sitzung“ ‖ ECDH ‖ Kennung ‖ Link-Schlüssel ‖ beide öffentlichen Schlüssel); Wegwerf-Schlüssel je Besuch |
| Zufall, SHA-256 | `RandomNumberGenerator`, `SHA256` | Nonces, Wegwerf-Namen, Nostr-Kennung |

Ein **Selbsttest** prüft beim Start (und in „Abschottung prüfen“ im Container): AES-256-GCM gegen
Testfall 16 der GCM-Spezifikation, ein verändertes Bit scheitert, ECDH beider Seiten gleich, ein
Punkt außerhalb der Kurve abgelehnt. Scheitert er, bleibt der Treffpunkt aus („Verschlüsselung fehlt“).
Kein CBC, kein ECB, kein HMAC-Eigenbau (der Test sucht im Quelltext danach).

Ablauf: Gast klopft mit seinem öffentlichen Wegwerf-Schlüssel an (versiegelt mit S, Zeit, Zufall);
der Gastgeber öffnet, prüft Zeitfenster (2 Minuten) und Wiederholung und meldet Uzai nur „klopft“
(Kennung + 8-Byte-Fingerabdruck). Erst nach Uzais Annahme antwortet er mit seinem Wegwerf-Schlüssel
(versiegelt mit S, mit Prüfwert des Gast-Schlüssels); ab dann gehen Angebot und Antwort (SDP) nur
mit dem Sitzungsschlüssel, mit Zählern gegen Wiederholung. Wer S aus einem abgefangenen Link hat,
aber nicht angenommen wird, kann keine Sitzung öffnen und sieht keine Adresse. Nach der Annahme ist
das Postfach zu (einmalig); abgelaufene oder zurückgezogene Einladungen schließen ihr Postfach.
Grenze: Wer S hat, könnte sich gegenüber dem Gast als Gastgeber ausgeben – darum geht jede Einladung
an genau einen Freund und gilt nur kurz.

### Was nötig ist (Vorschlag, **nicht eingebaut**)

| Bibliothek | Lizenz | Wofür | Warum diese |
|---|---|---|---|
| ~~libsodium~~ – **nicht mehr nötig** (AES-GCM und ECDH aus CNG, siehe oben) | ISC | `crypto_aead_xchacha20poly1305_ietf` (Treffpunkt-Nachrichten, 192-Bit-Nonce ohne Zähler-Risiko), `crypto_kdf` (Teilschlüssel je Zweck aus dem Link-Schlüssel), `crypto_sign` Ed25519 (Sitzungsschlüssel, signiertes SDP), `randombytes_buf` | weit verbreitet, geprüft (Audit 2017 im Auftrag von Private Internet Access), kleine, missbrauchssichere Schnittstelle |
| **libsecp256k1** v0.7.1 – **eingebaut** (`UzSecp`) | MIT | **BIP-340-Schnorr-Signatur** der Nostr-Ereignisse (sonst nehmen Relays sie nicht an), Prüfung fremder Signaturen | die Referenz-Umsetzung, stark geprüft; nur für die Hülle mit Wegwerf-Schlüssel, Sicherheit hängt **nicht** daran; Selbsttest gegen BIP-340-Vektoren |
| **libdatachannel** v0.24.6 – **eingebaut** (`UzRtc`), statt webrtc-native | MPL-2.0 (+ libjuice MPL-2.0, usrsctp BSD-3, Mbed TLS Apache-2.0) | WebRTC-Datenkanal | passt zur C#-Sandbox (Weg b, P/Invoke); dieselbe Bibliothek steckt in webrtc-native 1.2.2 |

Einbindung: **im Sandbox-Prozess**, nicht in Uzai. Zwei Wege, beide am PC zu prüfen:
- (a) Der Sandbox-Prozess ist ein zweiter, kopfloser Uzai-Start (`Uzai.exe --headless
  --zimmer-netz`) mit webrtc-native und einer kleinen GDExtension für libsodium/libsecp256k1;
  braucht Lese-/Ausführrechte des AppContainers auf den Programmordner (der Helfer setzt dafür
  einen einzelnen Lese-Eintrag für die Container-Kennung, nur auf Uzais eigene Dateien).
- (b) Ein eigenes kleines Programm (der Prototyp in Abschnitt 6 ist dessen Gerüst) mit libsodium
  über P/Invoke; WebRTC dann über libdatachannel direkt. Weniger Godot, mehr eigener Code.

Empfehlung: **(a)** – derselbe geprüfte Protokoll-Leser (`netz_protokoll.gd`) läuft dann auf beiden
Seiten der Pipe, und es gibt keinen zweiten Parser in einer anderen Sprache.

### Schlüssel und Ablauf (geplant)

- **Link:** Kennung `K` (16 Byte Zufall) und Schlüssel `S` (32 Byte Zufall = 256 Bit, Mindestmaß
  laut Punkt 131: 128 Bit). Erzeugt mit `Crypto.generate_random_bytes`.
- Aus `S` per `crypto_kdf` getrennte Teilschlüssel: Anklopfen, Antwort des Gastgebers, SDP/ICE.
- **Anklopfen:** Gast erzeugt einen Sitzungsschlüssel (Ed25519), schickt verschlüsselt
  `{öffentlicher Sitzungsschlüssel, Zeit, Zufallszahl}` (kein Name: den kennt der Gastgeber aus
  seiner Einladung). Nur wer `S` kennt, kann das.
- **Annahme:** Gastgeber antwortet verschlüsselt mit seinem öffentlichen Sitzungsschlüssel; dann
  tauschen beide signiertes SDP (inkl. DTLS-Fingerabdruck) und ICE. Erst jetzt fließt die IP.
- **Einmal-Links:** Gastgeber merkt sich den ersten angenommenen Sitzungsschlüssel und lehnt danach
  jedes weitere Anklopfen mit diesem Link ab; Ablaufzeit prüft **der Gastgeber** (der Link selbst
  trägt keine Zeit, die man fälschen könnte).
- **Zurückziehen:** neuer `S`, alte Links sind wertlos.

## 6. Sandbox-Prozess

Ein eigenes kleines Programm `uzai-zimmer-netz-2.exe` (C# 5, .NET Framework 4), gebaut vom Helfer
nach `%LOCALAPPDATA%\Uzai\zimmer-netz\`, gestartet im AppContainer `Uzai.ZimmerNetz`
(`CreateAppContainerProfile`, sonst `DeriveAppContainerSidFromAppContainerName`; ohne Adminrechte).
Die Container-Kennung darf **nur** diese eine Datei lesen und ausführen. Start mit `STARTUPINFOEX`:
`PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES` (Container + nur `internetClient`, S-1-15-3-1),
`PROC_THREAD_ATTRIBUTE_HANDLE_LIST` (nur die Leitungs-Enden werden vererbt),
`PROC_THREAD_ATTRIBUTE_CHILD_PROCESS_POLICY` (keine Kindprozesse); angehalten gestartet, in ein
**Job-Objekt** gelegt (ein Prozess, 256 MB, beendet mit dem Helfer, keine Zwischenablage, kein
Desktop, keine Systemeinstellungen), dann fortgesetzt. Umgebung nur `SystemRoot`, `windir`,
`TEMP`/`TMP` (eigener Ordner). Befehlszeilen nur in festen Formen.

**Zwei Wege hinein:**

1. **Probe** (Helfer-Befehl `zimmer-netz-probe`, keine Argumente, Zeitgrenze 12 s; Uzai: Zimmer-Menü
   → Online → „Abschottung prüfen“): `--echo`, zwei eigene Pipes. Drei Pings (leer, 1 Byte, 8 KiB
   Zufall) müssen genau zurückkommen; **Selbsttest im Container:** in den eigenen Ordner schreiben
   (muss gehen), Uzais Helfer-Datei lesen, das Benutzerprofil auflisten, in den Benutzer-Temp-Ordner
   schreiben, ein Programm starten (alles muss scheitern).
2. **Sitzung** (Helfer mit `-ZimmerNetz gastgeber|gast`, von Uzai mit `OS.execute_with_pipe`
   gestartet, `src/room/zimmer_netz.gd`): Der Helfer prüft die Rolle, verweigert Adminrechte, baut
   das Programm und startet es mit `--netz <rolle> --test`; **Uzais Pipe wird direkt dessen
   Standardeingabe und -ausgabe**, der Helfer selbst liest und schreibt darauf nichts und wartet
   nur. Endet Uzai, endet die Leitung und die Sandbox; endet der Helfer, schließt das Job-Objekt sie.

**Rahmen auf der Leitung** (4 Byte Länge, 1 Byte Art, Nutzlast bis 8 KiB):

| Art | Richtung | Nutzlast |
|---|---|---|
| 1 PING / 2 PONG | Uzai → Sandbox / zurück | beliebig (Echo) |
| 3 SELBSTTEST / 4 ERGEBNIS | nur Probe | Auftrag / Antwort |
| 5 ENDE | Uzai → Sandbox | leer |
| 6 SENDEN | Uzai → Sandbox | Platz + Nachricht an die Gegenstelle (geprüft, sonst gezählt und verworfen) |
| 7 EMPFANGEN | Sandbox → Uzai | Platz + Nachricht, die Prüfmauer 1 durchgelassen hat |
| 8 TEST_REIN / 9 TEST_RAUS | nur `--test` | Bytes der Test-Gegenstelle / was ins Netz ginge |
| 10 RAUS | Sandbox → Uzai | Platz + Grund (Gast reißt die Grenzen) |
| 11 ZAEHLER | beide | leer / angenommen, verworfen, gedrosselt, hinaus verworfen, TEST_REIN-Rahmen angekommen (je u32; vor Sandbox-Fassung 5 ohne den letzten) |
| 12 SCHLIESSEN | Uzai → Sandbox | Platz (Drossel und Rauswurf zurück; mit Treffpunkt: Sitzung beenden, Gast bekommt „zu“) |
| 13 TREFF | Uzai → Sandbox | u16 Port: 0 = feste Relays (nur mit echter Signatur), sonst nur mit `--test` 127.0.0.1:Port; nur einmal |
| 14 EINLADUNG / 15 ZURUECK | Uzai → Sandbox (Gastgeber) | Kennung 16 + Schlüssel 32 / Kennung 16 |
| 16 BESUCH | Uzai → Sandbox (Gast) | Kennung 16 + Schlüssel 32 |
| 17 KLOPFT | Sandbox → Uzai (Gastgeber) | Kennung 16 + Fingerabdruck 8 |
| 18 ENTSCHEID | Uzai → Sandbox (Gastgeber) | Fingerabdruck 8 + Platz 0–7 (0xFF = still abweisen) |
| 19 STAND | Sandbox → Uzai | Zustand (Relays, angenommen, keine Antwort, Verschlüsselung fehlt, Signatur fehlt, verbunden, zu, gescheitert, Datenkanal fehlt), zwei Bytes |
| 20 TREFF_ZAEHLER | beide | leer / gesehen, Unsinn, Krypto, Wiederholt, Gedrosselt, Relay-Fehler (je u32) |
| 21 QUITTUNG | Sandbox → Uzai | u32: so viele Bytes hat die Sandbox insgesamt gelesen (mod 2^32); nie mehr als Uzai schrieb, nie rückwärts |

**Fenster statt Verlust.** Godot öffnet die Pipe ohne Warten; unter Windows ist sie dann `PIPE_NOWAIT` mit
4 KiB Puffer (`CreatePipe` mit Größe 0). Passt ein Schreibvorgang nicht ganz hinein, schreibt Windows nichts –
oder nur den Teil, den ein wartendes Lesen gerade nimmt –, und `store_buffer` meldet nur `false` (0.16.33: der
5000-Byte-Rahmen der Test-Gegenstelle fehlte). Darum legt Uzai nie mehr als 3 KiB unquittiert in die Pipe; die
Sandbox quittiert vor jedem Lesen, sobald 512 Byte offen sind (`UzQuittEin`). Jeder Schreibvorgang passt so ganz
hinein, der Rest wartet in Uzai (höchstens 256 KiB, sonst geht die Leitung zu). Scheitert trotzdem einer, ist
unklar, wie viel ankam: Uzai schließt die Leitung, statt weiterzuschreiben (`tests/logic_zimmer_leitung.gd` mit
einer Pipe-Attrappe).

Gastgeber: Plätze 0–7 (ein Gast je Platz); Gast: nur Platz 0 (der Gastgeber). Alles andere, jede Art
in der falschen Richtung und jeder kaputte Rahmen → Code 3.

**Testbetrieb und Echtbetrieb.** Mit `--test` kommen die Bytes der Gegenstelle über die Leitung
(`TEST_REIN`) oder – mit den Bibliotheken – über einen echten Datenkanal zu 127.0.0.1; der Treffpunkt
spricht nur mit einem Test-Relay auf 127.0.0.1. Ohne `--test` (Helfer-Rolle `gastgeber-echt`/`gast-echt`,
nur aus dem Verbindungstest) gibt es keine Test-Gegenstelle, nur die festen Relays und den WebRTC-Datenkanal
mit festen STUN-Servern; fehlt eine Bibliothek, meldet die Sandbox „Signatur fehlt“ bzw. „Datenkanal fehlt“. Die **Test-Gegenstelle** (`zimmer_netz.gd → pruefen`) schickt gute und
böse Pakete, eine Flut (Drossel), Dauer-Unsinn (Rauswurf), Ausgehendes mit und ohne Schema und
prüft beide Mauern. Unter Linux läuft dieselbe Prüfung gegen die echte C#-Schleife über eine echte
Pipe (PowerShell 7, `tests/zimmer_netz_stdio.ps1`, ohne AppContainer).

**Nur am Windows-PC prüfbar (Phase 0):**
- Startet das .NET-Framework-Programm im AppContainer sauber (CLR liest Systemordner/Registry – die
  sind für „ALL APPLICATION PACKAGES“ lesbar)? Falls nicht: Weg (a) mit Uzai selbst.
- Erbt die Sandbox Uzais Pipe (Standardeingabe/-ausgabe des Helfers über `DuplicateHandle` und die
  Handle-Liste), und schreibt Windows PowerShell vorher nichts darauf? „Abschottung prüfen“ zeigt
  das als „Prüfmauer in der Abschottung: ja“.
- Reicht `internetClient` für ICE/UDP-Lochen, oder braucht WebRTC `internetClientServer`? Letzteres
  hieße nur „darf Antworten auf eigene Pakete empfangen“ – Router-Ports bleiben zu; vorher messen
  (erst mit Phase 4, wenn Netzwerk-Code im Kindprozess steckt).
- Windows-Firewall: AppContainer-Regeln greifen von selbst; keine Firewall-Abfrage erwartet.

## 7. Was ausdrücklich NICHT geht

- **Kein** eigener Server, kein Relay, kein TURN des Herausgebers; keine Telemetrie, keine Logs mit IP.
- **Keine** offenen Ports, **kein** UPnP/NAT-PMP, kein Lauschen auf eingehende Verbindungen.
- **Kein** öffentliches Zimmer-Verzeichnis, keine Suche nach Zimmern, kein „jeder darf rein“.
- **Keine** Dateien, Bilder, Modelle, Links, Skripte, Themes oder Shader von Gästen; keine eigenen
  3D-Modelle in geteilten Zimmern.
- **Nie** `str_to_var`, `bytes_to_var(_with_objects)`, `Expression`, `ResourceLoader`, `load()`,
  `JSON.to_native` auf Netzdaten; kein freier Chat, keine selbst gewählten Namen.
- **Nie** Adminrechte; kein virtueller Controller-Treiber; keine globale Tastatur-/Maus-Simulation;
  Gäste-Pads nie als Tastatur/Maus.
- **Kein** Weiterstreamen von Netflix & Co. oder Spotify an Gäste (R2, Punkt 131).
- **Kein** Desktop im Stream, keine Mitteilungen im Stream (WDA_EXCLUDEFROMCAPTURE, Extra k).
- **Keine** Eigenbau-Kryptografie, keine Zusammensetzungen aus AES-CBC und HMAC.
- **Keine** Verbindung, bevor der Gastgeber angenommen hat; keine IP vorher.

## 8. Was für einen echten Online-Start noch fehlt

1. ~~libsecp256k1 und eine WebRTC-Bibliothek~~ eingebaut (libdatachannel über P/Invoke, nur im
   Sandbox-Prozess). libsodium ist nicht mehr nötig.
2. Sandbox am Windows-PC prüfen („Abschottung prüfen“: Probe und Sitzung mit beiden Prüfmauern),
   offene Fragen aus Abschnitt 6 klären, dann echten Netzwerk-Teil hineinlegen.
3. ~~Nostr-Anbindung~~ gebaut (Art 20777, vier feste Relays, Wiederholungsschutz, BIP-340). Am PC
   („Verbindungstest“): Nehmen die Relays die Art an, geht WebSocket aus dem Container?
4. ~~WebRTC-Aufbau~~ gebaut. Am PC: Reicht `internetClient` für ICE (Verbindungstest, dann mit einem Freund)?
5. Gestaltung der Möbel im Detail (zweite Farbe, Materialien, Muster, Lampen, Regale) als feste
   Nummern ins Zimmer-Paket aufnehmen; bis dahin sehen Gäste dafür das Standardaussehen.
6. Einladung über Steam-Chat und Discord-Direktnachricht verschicken (je Einladung ein Freund).
7. Web-Version (statisch, CSP, SRI) und `uzai://`-Registrierung über das App-Paket (MSIX).
8. Externe Sicherheitsprüfung, SECURITY.md, Anwalts-Prüfung (Jugendschutz/DSA, R9).
9. ~~`Online.BEREIT` auf `true`~~ – seit 10.11.2026 gesetzt, auf Wunsch des Projektinhabers und nach der
   Gesamtprüfung in Abschnitt 10, **vor** den Punkten 2 bis 4 (PC) und 8 (externe Prüfung). Online bleibt aus,
   bis der Nutzer es einschaltet und die Abschottung auf seinem PC besteht.

## 10. Gesamtprüfung vor dem Einschalten (Phase 6)

Stand 10.11.2026. Zimmer online ist nur von Uzai zu Uzai eingeschaltet; der Gast im Browser ruht.

### Wann das Zimmer überhaupt online geht

Alle vier Bedingungen zugleich (`Online.darf_online`), sonst bleibt es offline:

1. Die Einstellung „Zimmer online“ ist an. Standard ist aus.
2. Uzai läuft ohne Adminrechte.
3. „Abschottung prüfen“ hat **in dieser Sitzung auf diesem PC** alles bestanden: AppContainer, beide Prüfmauern,
   beide Netz-Bibliotheken mit Prüfsumme und Selbsttest. Uzai prüft beim Einschalten und vor dem ersten Besuch
   selbst. Das Ergebnis wird je Uzai-Fassung gemerkt, aber nur für die Anzeige: Geprüft wird in jeder Sitzung
   neu, weil sich Adminrechte und Umgebung ändern können. Besteht die Prüfung nicht, schaltet Uzai wieder aus
   und sagt, warum.
4. Der Hinweis kam und wurde bestätigt: Wen du hereinlässt, sieht deine IP-Adresse.

Letzte Schranke: `freundestest.gd _starten` startet die Abschottung im Echtbetrieb nur, wenn `darf()` gilt –
egal, welcher Code es aufruft. Ausschalten wirft sofort alle raus und macht alle Einladungen ungültig.

### Durchgegangene Angriffe

| Angriff | Was der Angreifer hat | Was passiert | Geprüft durch |
|---|---|---|---|
| **Böser Gast**: schickt nach der Annahme beliebige Bytes, zu viel, zu schnell, außerhalb der Reihenfolge | eine direkte, verschlüsselte Verbindung | Prüfmauer 1 (Abschottung) und Prüfmauer 2 (Uzai) lassen nur Nachrichten mit fester Länge und Wertebereich durch; wer die Grenzen reißt, fliegt raus („raus“). Vor dem „hallo“ zählt nichts. Gäste senden nur Zahlen: Lage, Blick, Emote, Schnellsatz, Figur aus festen Listen. | `logic_zimmer_netz` (Fuzz, Grenzen, Drossel, echte Prüfmauer 1 über die Leitung), `net_zimmer_treff` („Böser Gast, böses Relay“), `logic_freundestest` |
| **Fremder ohne Einladung** klopft an, auch tausendfach | nichts außer dem Treffpunkt | Ohne den Schlüssel einer gültigen Einladung wird jedes Anklopfen still verworfen. | `logic_zimmer_netz` „Böser Gast und Flut“: 3000 Anklopfer, niemand wartet |
| **Abgefangene Einladung**, Flut mit immer neuen Kennungen | den Code | Höchstens 6 Anklopfer je Minute und 8 Wartende; herein kommt nur, wen der Gastgeber annimmt; eine Einladung gilt für genau einen Gast, danach ist sie verbraucht. | ebenda: 3000 Anklopfer mit richtigem Schlüssel |
| **Müll** als Kennung, Schlüssel oder Code (leer, zu lang, Pfadzeichen, 64 KiB) | – | Abgewiesen, bevor irgendetwas gemerkt wird. | ebenda; `logic_freundestest` (Code-Fuzz) |
| **Böses Relay**: liest mit, fälscht, hält zurück, wiederholt | alles, was über das Relay läuft | Sieht nur versiegelte Daten (AES-256-GCM mit dem Schlüssel der Einladung), Wiederholungsschutz und Zeitfenster, Drossel je Relay und Postfach, strenger JSON-Leser in der Abschottung. Zurückhalten heißt nur: Der Besuch kommt nicht zustande. | `zimmer_treff_cs.ps1`, `net_zimmer_treff` |
| **Gefälschte Einladung im Chat** (ausgedachter oder veränderter Code) | ein Freundeskonto oder dessen Text | Uzai liest nur die ersten 400 Zeichen, nur von Freunden aus der eigenen Liste und nur, wenn Zimmer online an ist. Der Code muss als Ganzes dastehen und Prüfzeichen und Ablauf bestehen. Der Text wird nie ausgeführt, geöffnet oder als Adresse behandelt. Uzai bietet nur „Zimmer betreten“ an – betreten wird nie von selbst, und vor dem Anklopfen kommt der Hinweis zur IP-Adresse. Ein Code, der nur zufällig die Prüfzeichen trifft, führt zu einem Anklopfen ohne Gegenstelle („Keine Antwort“). | `logic_freundestest` „Einladung im Chat“ (3000 zufällige Nachrichten, ein Zeichen falsch, abgeschnitten, in einem Wort versteckt, riesige Nachricht) |
| **Wiederholte Einladung im Chat** | eine alte, echte Nachricht | Derselbe Code wird nur einmal angeboten (Fingerabdruck, nie der Code selbst); abgelaufen wird nicht angeboten; beim Gastgeber ist er nach einem Gast verbraucht. | ebenda |
| **Flut im Chat** | ein oder mehrere Freundeskonten | Höchstens ein Angebot je Freund in 60 s und sechs in zehn Minuten; der Rest bleibt eine gewöhnliche Chat-Nachricht. | ebenda |
| **Gekapertes Freundeskonto lädt ein** | ein echtes Konto, eine echte Einladung | Du wärst Gast bei einem bösen Gastgeber: Es gilt W11 – derselbe strenge Leser in deine Richtung, das Zimmer nur aus Katalog-Nummern, nichts wird bei dir gespeichert. Er sieht deine IP-Adresse (der Hinweis sagt das vorher). | `logic_zimmer_netz` (Rolle Gast) |

### Was offen bleibt (ehrlich)

- **Am Windows-PC ist nichts davon gelaufen.** Der AppContainer, ICE mit nur `internetClient` und die Relays
  aus dem Container sind dort zu prüfen. Weil
  Bedingung 3 auf jedem PC selbst prüft, bleibt Zimmer online dort aus, wo die Abschottung nicht besteht.
- **Keine externe Sicherheitsprüfung.** Diese Durchsicht ist eine eigene, keine fremde. Eine unbekannte Lücke
  in libdatachannel, Mbed TLS oder usrsctp (W7) kann sie nicht ausschließen; dagegen steht nur die Abschottung.
- **Deine IP-Adresse** sieht jeder, den du hereinlässt. Das ist so gewollt und steht im Hinweis.
- Jugendschutz und DSA (R9), SECURITY.md und die Web-Version (Abschnitt 8, Punkte 7 und 8) sind nicht erledigt.

## 9. Spielbild im Fernseher (Stufe 2) und Zimmer teilen (Stufe 3)

Beides läuft ohne Netz. Es gilt dieselbe Haltung wie oben: fremde Daten sind feindlich, eigene Daten
verlassen den PC nur, wenn du es ausdrücklich auslöst.

**Spielbild (`src/room/spielbild.gd`, Helfer-Befehl `window-frame`)**

- Derselbe Weg wie das Fenster-Bild für Installationsdialoge (`PrintWindow`, nur lesen): Kein Fenster
  wird umgestellt, nichts kommt nach vorn. Argumente sind nur Zahlen (Fenster-Kennung > 0, Breite
  64 … 1280, JPEG-Qualität 30 … 90), fest begrenzt im Helfer.
- Das Bild bleibt im Speicher: Der Helfer antwortet mit einem kleinen JPEG als Base64, auf die Platte
  kommt nichts. Uzai prüft Länge, JPEG-Kopf und Größe vor dem Dekodieren und behält nur das letzte
  Bild (für den Übergang ins Vollbild) – es verschwindet mit dem Zimmer.
- `PrintWindow` läuft im Helfer in einem eigenen Faden mit Zeitgrenze (1,5 s): Ein hängendes oder
  angehaltenes Spiel hält den Helfer nie auf. Angehaltene Emulatoren fragt Uzai höchstens einmal.
- Sparsam: nur bei offenem Zimmer, nur wenn der Fernseher im Bild ist, im Takt der Grafikstufe
  (Leicht: alle 2 s, 320 Pixel breit). Liegt das Spiel vorn, zeichnet das Zimmer nichts und nimmt nichts auf.
- Gespeichert wird ein Spielbild nur über einen ausdrücklichen Schnappschuss im Fotomodus. Die
  Vorschau beim Teilen zeigt nie das Spielbild (und keine Spiele, Pokale oder Platten).
- Uzai holt das Spiel nur nach vorn, wenn du es auslöst (A am Fernseher, Guide › Zum Spiel).

**Zimmer teilen (`src/room/zimmer_teilen.gd`)**

| Weg | Schutz |
|---|---|
| Inhalt | Nur ein Raum, eigene Möbel, die darin stehen, Figur und Haustier-Aussehen. Nie: Spiele, eigene Reihenfolge, Auswahl nach Ordnern/Listen/Tags/Sammlungen, Namen (Zimmer, Stimmungen, Haustier), Meilensteine, eigene Farben, Hüllen je System. Test: `tests/logic_zteilen.gd` sucht persönliche Werte im Auszug. |
| Datei (.uzaizimmer) | Der strenge ZIP-Leser (`paket.gd` `verzeichnis`): nur genau `zimmer.json` (≤ 256 KB) und `vorschau.jpg` (≤ 768 KB), keine Ordner, keine Verknüpfungen, keine Verschlüsselung, nur Speichern/Deflate, Bomben-Grenze, Prüfsummen (auch ungepackt), Datei ≤ 2 MB. |
| Code (UZZ1:) | Länge ≤ 4400, nur Base64-Zeichen, dann derselbe Weg wie eine Datei. |
| zimmer.json | Derselbe Prüfer wie für die eigene zimmer.json (Fassung 2): nur Kennungen aus dem Katalog, Farben `#rrggbb`, Zahlen in festen Bereichen, höchstens 300 Möbel, 24 eigene Möbel mit je 48 Teilen; fremde Namen werden ersetzt. |
| Vorschaubild | Wird nur im Kopf geprüft (Format, ≤ 1920 Pixel) und nie dekodiert. Die Vorschau beim Einführen rechnet Uzai selbst aus den geprüften Daten. |
| Eigene Möbel | Bekommen neue Kennungen (keine Kollision mit deinen), gleiche werden wiederverwendet; der Raum geht danach noch einmal durch den Prüfer. Möbel, die bei dir noch nicht freigespielt sind, bleiben weg. |
| Übernehmen | Nur nach Rückfrage („Dein Zimmer ersetzen“ mit Rückgängig, „Als Vorlage speichern“); Figur und Haustier nur, wenn du es einschaltest. |
| Schreiben | Atomar (`.neu`, wieder eingelesen und verglichen, dann umbenannt), nur in Dokumente\Uzai\Zimmer bzw. Bilder\Uzai, nie über Verknüpfungen, Dateinamen nach fester Regel. |
| Netz | Keins: kein Upload, kein Server, keine Telemetrie. Die Web-Version zum Ansehen ohne Uzai braucht eine Homepage (R8) und ist **nicht gebaut**. |

Fuzz-Tests: 300 Pakete mit zufällig veränderten Bytes, 300 Zimmer mit vergifteten Feldern und
200 zufällige Codes (`tests/logic_zteilen.gd`).
