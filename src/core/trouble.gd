extends RefCounted
## Hilfe bei Problemen (Punkte 15, 113, 116): ob ein Spiel hängt, ob es abgestürzt ist, und was
## dann je nach Quelle hilft. Hier wird nur entschieden – die Fakten (Fenster antwortet nicht,
## Rückgabewert, Absturzbericht von Windows) holt der Launcher über den Helfer. Dazu die zehn
## häufigsten Probleme für „Erste Hilfe“ (Einstellungen → System).

const Lang := preload("res://src/core/lang.gd")

## So lange muss das Spielfenster ohne Unterbrechung hängen (Windows meldet es selbst erst nach
## 5 s), bevor Uzai „antwortet nicht“ sagt: Lade- und Shader-Pausen dauern oft ein paar Sekunden.
const HUNG_MS := 10000
## Kürzer gelaufen, ohne Fenster und mit Fehlercode: „nicht richtig gestartet“.
const START_FAIL_S := 15
## Rückgabewerte, bei denen Windows das Programm gar nicht erst laden konnte: DLL fehlt
## (0xC0000135), DLL ließ sich nicht starten (0xC0000142), 32/64 Bit gemischt (0xC000007B).
const LOAD_CODES := [0xC0000135, 0xC0000142, 0xC000007B]
## Emulatoren, die BIOS oder Firmware der eigenen Konsole brauchen (Uzai liefert so etwas nie mit).
const BIOS := { "ps1": "das BIOS", "ps2": "das BIOS", "ps3": "die Firmware", "saturn": "das BIOS",
	"xbox": "das BIOS", "switch": "die Firmware und die Schlüssel" }


# --- Hängt das Spiel? ------------------------------------------------------------------------

## Seit wann (ms) das Fenster ohne Unterbrechung hängt; 0 = antwortet.
static func hung_since(since: int, hung_now: bool, now: int) -> int:
	if not hung_now:
		return 0
	return since if since > 0 else maxi(now, 1)


static func is_hung(since: int, now: int) -> bool:
	return since > 0 and now - since >= HUNG_MS


# --- Abgestürzt? -----------------------------------------------------------------------------

## Rückgabewert eines beendeten Programms: "absturz" (Windows-Ausnahme wie 0xC0000005), "laden"
## (Windows konnte es nicht laden) oder "" (normal beendet oder von außen geschlossen).
static func code_kind(code: int) -> String:
	if code in LOAD_CODES:
		return "laden"
	# 0xC000013A: Konsolenfenster geschlossen (Strg+C); 0xFFFFFFFF: hart beendet (Uzai, Task-Manager).
	if code == 0xC000013A or code == 0xFFFFFFFF:
		return ""
	if (code & 0xC0000000) == 0xC0000000 or code == 0x80000003:
		return "absturz"
	return ""


## Nach dem Spielende: {} (nichts Auffälliges) oder { kind: "absturz"|"start", why, code, module }.
## f: quit (über Uzai beendet), kind (Quelle beim Start), secs, window (Spielfenster war da),
## code (Rückgabewert, -1 = unbekannt), wer ({ found, code, module } aus dem Anwendungsprotokoll),
## steam_seen (Steam meldete das Spiel als laufend). Nur Verlässliches zählt: Wer selbst beendet,
## bekommt nie eine Absturzmeldung, und eine kurze Laufzeit allein ist noch kein Fehler (Starter,
## die das Spiel weiterreichen, enden auch schnell – aber mit 0).
static func verdict(f: Dictionary) -> Dictionary:
	if bool(f.get("quit", false)):
		return {}
	var code := int(f.get("code", -1))
	var ck := code_kind(code) if code >= 0 else ""
	if ck == "laden":
		return { "kind": "start", "why": "laden", "code": hex(code), "module": "" }
	var wer: Dictionary = f.get("wer", {}) if f.get("wer") is Dictionary else {}
	if bool(wer.get("found", false)):
		return { "kind": "absturz", "why": "windows", "code": wer_code(str(wer.get("code", ""))), "module": str(wer.get("module", "")) }
	if ck == "absturz":
		return { "kind": "absturz", "why": "code", "code": hex(code), "module": "" }
	var secs := int(f.get("secs", 0))
	var window := bool(f.get("window", false))
	if code > 0 and secs < START_FAIL_S and not window:
		return { "kind": "start", "why": "code", "code": str(code), "secs": secs, "module": "" }
	if str(f.get("kind", "")) == "steam" and not bool(f.get("steam_seen", false)) and not window:
		return { "kind": "start", "why": "steam", "code": "", "module": "" }
	return {}


static func hex(code: int) -> String:
	return "0x%08X" % code


## „c0000005“ aus dem Anwendungsprotokoll → „0xC0000005“.
static func wer_code(s: String) -> String:
	s = s.strip_edges().to_lower().trim_prefix("0x")
	return "" if s == "" else "0x" + s.to_upper()


static func headline(title: String, v: Dictionary) -> String:
	return ("%s ist abgestürzt" if str(v.get("kind", "")) == "absturz" else "%s ist nicht richtig gestartet") % title


## Was Uzai gesehen hat, in einem Satz.
static func what_happened(v: Dictionary) -> String:
	match str(v.get("why", "")):
		"laden":
			return "Windows konnte das Programm nicht laden (Fehler %s): Eine Datei, die es braucht, fehlt oder passt nicht." % str(v.code)
		"steam":
			return "Steam hat das Spiel nicht gestartet."
		"windows":
			if str(v.get("module", "")) != "":
				return "Windows hat einen Absturz aufgezeichnet: Fehler %s in %s." % [str(v.code), str(v.module)]
			return "Windows hat einen Absturz aufgezeichnet (Fehler %s)." % str(v.code)
	if str(v.get("kind", "")) == "start":
		return "Es hat sich nach %s mit Fehlercode %s beendet, bevor ein Fenster kam." % [Lang.count(int(v.get("secs", 0)), "Sekunde", "Sekunden"), str(v.code)]
	return "Es hat sich mit dem Fehlercode %s beendet." % str(v.code)


## Konkrete Tipps je Quelle und höchstens ein Knopf: [Text, id] mit id „validate“ (Steam prüft die
## Spieldateien), „emulator“ (Emulator in den Einstellungen) oder „options“ (Spieloptionen).
## Neben „Neu starten“ und „Schließen“ ist auf der Karte für mehr kein Platz – und nicht nötig.
static func tips(game: Dictionary, v: Dictionary) -> Dictionary:
	var lines := PackedStringArray()
	var action: Array = []
	var why := str(v.get("why", ""))
	match str(game.get("source", "rom")):
		"steam":
			if why == "steam":
				lines.append("Oft wartet Steam auf ein Update, eine Anmeldung oder eine Bestätigung in seinem Fenster.")
			lines.append("Steam prüft die Spieldateien und ersetzt beschädigte.")
			action = ["Dateien prüfen", "validate"]
		"epic":
			lines.append("Im Epic Games Launcher unter Bibliothek beim Spiel „…“ → Verwalten → Überprüfen.")
		"ea":
			lines.append("In der EA app beim Spiel „…“ → Reparieren.")
		"gog":
			lines.append("In GOG Galaxy beim Spiel „Verwalten“ → „Installation verwalten“ → „Überprüfen / Reparieren“.")
		"ubisoft":
			lines.append("In Ubisoft Connect beim Spiel „Eigenschaften“ → „Dateien überprüfen“.")
		"battlenet":
			lines.append("In Battle.net beim Spiel das Zahnrad neben „Spielen“ → „Scannen und reparieren“.")
		"xboxpc":
			lines.append("In der Xbox-App beim Spiel „…“ → „Verwalten“ → „Dateien“ → „Überprüfen und reparieren“.")
		"amazon", "itch", "riot":
			lines.append("Im Launcher des Spiels lässt es sich überprüfen oder neu installieren.")
		"rom":
			var sys := str(game.get("system", ""))
			if why == "laden":
				lines.append("Dem Emulator fehlt eine Datei, meist eine Laufzeitbibliothek von Microsoft. Was er braucht, steht auf seiner Seite.")
			elif BIOS.has(sys):
				lines.append("Der Emulator braucht %s deiner eigenen Konsole. Nicht enthalten." % BIOS[sys])
			lines.append("In den Einstellungen des Emulators einen anderen Grafik-Renderer versuchen (Vulkan, OpenGL oder Direct3D).")
			lines.append("Stürzt nur dieses Spiel ab, ist die Spieldatei vielleicht unvollständig oder beschädigt.")
			action = ["Emulator-Einstellungen", "emulator"]
		_:
			var exe := str(game.get("target", game.get("path", "")))
			if str(game.get("url", "")) != "" or exe.get_extension().to_lower() == "lnk":
				lines.append("Das Spiel startet über seinen Launcher (GOG Galaxy, Battle.net, Xbox-App …): Dort lässt es sich überprüfen oder reparieren.")
			else:
				if why == "laden":
					lines.append("Viele Spiele bringen Laufzeitpakete mit (Ordner wie „_CommonRedist“ oder „Redist“ im Spielordner): diese einmal installieren.")
				lines.append("In den Spieloptionen Programmdatei, Arbeitsordner und Startparameter prüfen – manche Spiele starten nur aus ihrem eigenen Ordner.")
				action = ["Spieloptionen", "options"]
	return { "lines": lines, "actions": [action] if not action.is_empty() else [] }


# --- Erste Hilfe -----------------------------------------------------------------------------

## Die zehn häufigsten Probleme. Knöpfe öffnen nur, was es in Uzai schon gibt:
## „pad_help“ (Controller-Problemlöser), „pad_test“ (Controller-Test), „audio“ (Ton ausgeben über), „scan“ (Bibliothek neu einlesen),
## „tools“ (Video-Programme laden), „safe“ (Neustart im Sicheren Modus) und Stellen in den
## Einstellungen: „seite:<Kategorie>“, „seite:<Kategorie>/<Unterseite>“, „seite:<Kategorie>#<Zeile>“.
const FIRST_AID := [
	{ "title": "Controller reagiert nicht", "icon": "controller", "desc": "Problemlöser, neu verbinden, Steam Input.",
		"steps": [
			"Controller neu einschalten oder neu koppeln (Einstellungen → Controller).",
			"Der Problemlöser prüft Tasten, Sticks, Trigger und Vibration.",
			"Nur in einem Spiel: Steam Input in Steam prüfen.",
			"Ohne Guide-Taste öffnet View + Start den Guide."],
		"actions": [["Problemlöser öffnen", "pad_help"], ["Einstellungen", "seite:controller"]] },
	{ "title": "Spiel startet nicht", "icon": "play", "desc": "Emulator, Programmdatei, Adminrechte.",
		"steps": [
			"Emulator-Spiele: Unter Einstellungen → Emulation braucht das System einen Emulator mit Programmdatei.",
			"Eigene PC-Spiele: In den Spieloptionen Programmdatei, Arbeitsordner und Startparameter prüfen.",
			"Steam-Spiele: nach einem Fehlstart „Dateien prüfen“.",
			"Administratorrechte bestätigt man mit Maus oder Tastatur."],
		"actions": [["Emulation öffnen", "seite:emulation"]] },
	{ "title": "Bild bleibt schwarz", "icon": "monitor", "desc": "Spiel nach vorn holen, Bildfilter, HDR, Vollbild.",
		"steps": [
			"Im Guide „Zurück ins Spiel“ wählen.",
			"Mit Bildfilter: Windows-HDR ausschalten oder Filter aus.",
			"Spiele im exklusiven Vollbild: im Spiel „Randloses Fenster“ wählen.",
			"Mit Lossless Scaling: im Guide ausschalten."],
		"actions": [["Bildfilter-Einstellungen", "seite:emulation#Bildfilter verwenden"]] },
	{ "title": "Kein Ton", "icon": "speaker", "desc": "Richtiges Ausgabegerät wählen.",
		"steps": [
			"Ton geht oft an ein anderes Gerät.",
			"Gerät unter „Ton ausgeben über“ wählen.",
			"Fehlen nur die Menüklänge: Einstellungen → Klang."],
		"actions": [["Ton ausgeben über", "audio"]] },
	{ "title": "Steam-Anmeldung klappt nicht", "icon": "steam", "desc": "QR-Code mit der Steam-App, Steam selbst.",
		"steps": [
			"Code mit der Steam-App scannen und bestätigen.",
			"Abgelaufenen Code neu anzeigen lassen.",
			"Zum Spielen muss Steam am PC angemeldet sein."],
		"actions": [["Steam-Konto", "seite:konten/Steam"]] },
	{ "title": "Discord verbindet nicht", "icon": "discord", "desc": "Discord-App, Freigabe.",
		"steps": [
			"Die Discord-App muss am PC laufen und angemeldet sein.",
			"Keine eigene App-ID nötig.",
			"„Mit Discord verbinden“ zeigt, welcher Schritt hängt."],
		"actions": [["Discord-Verbindung", "seite:konten/Discord"]] },
	{ "title": "Musik fehlt", "icon": "music", "desc": "Musik-Einstellung, Spotify-Anmeldung.",
		"steps": [
			"Musikquelle unter Klang darf nicht „Aus“ sein.",
			"Playlists und Mixe mit Spotify-Anmeldung. Wird sie blockiert: eigene Spotify-App.",
			"Läuft gar nichts, zuerst in der Musik-App selbst etwas abspielen."],
		"actions": [["Spotify-Konto", "seite:konten/Spotify"], ["Musikquelle", "seite:klang#Musikquelle"]] },
	{ "title": "Videos laden nicht", "icon": "video", "desc": "Video-Programme laden, Anzeige umstellen.",
		"steps": [
			"Videos brauchen yt-dlp, Deno und mpv. „Fehlendes laden“ holt sie.",
			"Bricht ein Video ab, später erneut versuchen.",
			"Bleibt das Bild schwarz: unter Medien → Mehr zu Videos die Anzeige auf „Video vorn“ stellen."],
		"actions": [["Fehlendes laden", "tools"], ["Mehr zu Videos", "seite:medien/Mehr zu Videos"]] },
	{ "title": "Spiel fehlt in der Bibliothek", "icon": "search", "desc": "Neu einlesen, Ausgeblendetes, Ordner.",
		"steps": [
			"„Jetzt neu einlesen“ durchsucht alle Ordner, Steam, Epic und die EA app.",
			"Ausgeblendete Spiele: Einstellungen → Spiele → Mehr.",
			"Emulator-Spiele: beim System Spieleordner und Dateiendungen prüfen (Einstellungen → Emulation).",
			"Eigene PC-Spiele: Einstellungen → Spiele → PC-Spiele → „PC-Spiel hinzufügen“."],
		"actions": [["Neu einlesen", "scan"], ["Einstellungen", "seite:spiele/Mehr#Ausgeblendete Spiele"]] },
	{ "title": "Uzai ist langsam", "icon": "speed", "desc": "Leistung messen, leichter Modus, Sicherer Modus.",
		"steps": [
			"„Leistung“ zeigt Speicher und Rechenzeit.",
			"Schwacher PC: leichter Modus (Einstellungen → Aussehen → Mehr).",
			"Sicherer Modus startet nur das Nötigste."],
		"actions": [["Leistung", "seite:system/Leistung"], ["Sicherer Modus", "safe"]] },
]
