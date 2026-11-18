extends RefCounted
## Uzai-Browser: die Leitung zwischen Uzai und dem Browser-Wirt (helper/uzai-browser-wirt.cs).
## Eine JSON-Zeile je Nachricht über die Standardein- und -ausgabe des Wirts – eine anonyme Leitung,
## die nur Uzai und der Wirt kennen (kein Name, den ein anderes Programm öffnen oder vorher belegen
## könnte, kein Anschluss, kein Server). Jede Nachricht hat ein festes Schema: Art „t“ aus einer
## Erlaubnisliste, jedes Feld mit Typ und Bereich, Texte mit Längengrenze; Unbekanntes wird verworfen.
## Der Wirt prüft Befehle mit demselben Schema (UzbSchema.Befehl), Uzai prüft jedes Ereignis des
## Wirts – auch das, was das Sprung-Skript aus der Seite meldet, ist fremd und wird hier noch einmal
## geprüft (zweite Mauer). Beispiele beider Seiten: tests/fixtures/browser_protokoll.json.

const Adresse := preload("res://src/core/browser_adresse.gd")
const Fremd := preload("res://src/core/fremd.gd")

const MAX_BEFEHL := 16384          ## Uzai → Wirt: höchstens so viele Bytes je Zeile
const MAX_EREIGNIS := 786432       ## Wirt → Uzai (Lesemodus ist das größte)
const MAX_ZIELE := 800
const MAX_ABSAETZE := 200
const MAX_TABS := 12
const ZOOM_MIN := 25
const ZOOM_MAX := 300

## Arten der Ziele auf der Fokus-Karte (Zahl auf der Leitung) und Bereiche der Seite.
const ARTEN := ["link", "knopf", "feld", "wahl", "video", "bild", "reiter", "sonst", "rahmen"]
const BEREICHE := ["kopf", "navigation", "inhalt", "seite", "fuss", "dialog", "sonst"]
const TASTEN := ["enter", "tab", "umschalt_tab", "escape", "backspace", "links", "rechts", "hoch", "runter",
	"seite_hoch", "seite_runter", "pos1", "ende", "leer"]
const VIDEO := ["umschalten", "pause", "spielen", "vor", "zurueck", "vollbild", "vor_lang", "zurueck_lang", "lauter", "leiser", "stumm",
	"tempo_auf", "tempo_ab", "untertitel"]
const FELDER := ["text", "suche", "email", "zahl", "passwort", "url", "tel", "bereich"]
const FRAGEN := ["kamera", "mikrofon", "standort", "bestaetigen"]
const SPERREN := ["protokoll", "laenge", "zeichen", "anmeldung", "name", "lokal", "heimnetz", "popup", "app",
	"zertifikat", "anmeldedialog", "download", "nur_spotify"]
const FEHLER := ["webview2", "pruefung", "start", "absturz", "tabs", "kern", "kern_api", "kern_signatur", "kern_pfad", "kern_sandbox", "kern_installer"]
const DOWNLOAD := ["laeuft", "fertig", "gesperrt", "fehler"]
const COOKIES := ["", "abgelehnt", "versteckt", "aus"]
const KERN_STAND := ["laedt", "fertig", "fehler", "stand", "update", "diagnose", "info"]
const KERN_AKTION := ["diagnose", "update", "gesund"]
const MAX_PUNKTE := 60
const MAX_OPTIONEN := 400

## Spotify-Sitzung: Abfragen, die der Kern IN der angemeldeten Seite ausführt (fetch im Seitenkontext, mit den
## Kopfzeilen der Seite – spotify_web.gd abfrage(), UzcSpotify im Kern). Uzai nennt nur Ziel-Art, Methode, Pfad und
## Inhalt; Host und Kopfzeilen setzt der Kern selbst. Antwort: HTTP-Code und Text (höchstens MAX_ANTWORT Zeichen).
const SPOTIFY_ZIELE := ["pathfinder", "spclient", "webapi"]
const SPOTIFY_METHODEN := ["GET", "POST", "PUT"]
const SPOTIFY_GRUENDE := ["", "zeit", "netz", "gross", "ziel", "welt", "schluessel", "voll"]
## spclient: nur diese Dienste (Spotify Connect, Titel einer Liste, Zuletzt gehört).
const SPOTIFY_SPCLIENT := ["/connect-state/v1/", "/context-resolve/v1/", "/recently-played/v3/"]
## PUT nur für Spotify Connect: Uzais verstecktes Gerät (Zustand lesen) und die Lautstärke.
const SPOTIFY_PUT := ["/connect-state/v1/devices/", "/connect-state/v1/connect/volume/"]
const PATHFINDER_PFAD := "/pathfinder/v2/query"
const MAX_PFAD := 2048
const MAX_INHALT := 12000
const MAX_VERBINDUNG := 512         ## Verbindungs-Kennung von Spotify Connect (Base64)
const MAX_ANTWORT := 2097152       ## Text einer Spotify-Antwort (Zeichen)
const MAX_ZEILE := 6291456         ## nur „spotify-antwort“ darf länger sein als MAX_EREIGNIS (Bytes)

static var _RX_VORSCHAU := RegEx.create_from_string("^tab-[0-9]{1,7}\\.jpg\\z")
static var _RX_ABFRAGE := RegEx.create_from_string("^[A-Za-z][A-Za-z0-9_]{0,63}\\z")
static var _RX_SHA256 := RegEx.create_from_string("^[0-9a-f]{64}\\z")

const TAB := ["int", 1, 1000000]
const ID := ["int", 1, 1000000000]
const KOORD := ["int", -100000, 100000]
const TEXT_KURZ := ["text", 300]

## Uzai → Wirt.
const BEFEHLE := {
	"fenster": { "x": ["int", -32768, 32768], "y": ["int", -32768, 32768], "w": ["int", 100, 16384], "h": ["int", 100, 16384] },
	"zeigen": { "an": ["bool"] },
	"tab-neu": { "url": ["url"], "privat": ["bool"], "vorn": ["bool"], "nutzer": ["bool"] },
	"tab-zu": { "tab": TAB },
	"tab-wahl": { "tab": TAB },
	"laden": { "tab": TAB, "url": ["url"], "nutzer": ["bool"] },
	"zurueck": { "tab": TAB },
	"vor": { "tab": TAB },
	"neu": { "tab": TAB },
	"stopp": { "tab": TAB },
	"zoom": { "tab": TAB, "prozent": ["int", ZOOM_MIN, ZOOM_MAX] },
	"rollen": { "tab": TAB, "vx": ["int", -30000, 30000], "vy": ["int", -30000, 30000] },
	"karte": { "tab": TAB },
	"fokus": { "tab": TAB, "id": ID },
	"aktivieren": { "tab": TAB, "id": ID, "neu": ["bool"] },
	"link": { "tab": TAB, "id": ID },
	"feld": { "tab": TAB, "id": ID },
	"text": { "tab": TAB, "id": ID, "text": ["text", 2000] },
	"taste": { "tab": TAB, "taste": ["wahl", TASTEN] },
	"klick": { "tab": TAB, "x": ["int", 0, 100000], "y": ["int", 0, 100000] },
	"zeiger": { "tab": TAB, "x": ["int", 0, 100000], "y": ["int", 0, 100000] },
	"rad": { "tab": TAB, "x": ["int", 0, 100000], "y": ["int", 0, 100000], "dy": ["int", -5000, 5000] },
	"video": { "tab": TAB, "aktion": ["wahl", VIDEO] },
	"vorschau": { "tab": TAB },
	"lesen": { "tab": TAB },
	"antwort": { "frage": ID, "ja": ["bool"] },
	"gliederung": { "tab": TAB },
	"springe": { "tab": TAB, "id": ID },
	"wahl": { "tab": TAB, "id": ID },
	"wahl-setzen": { "tab": TAB, "id": ID, "index": ["int", 0, 399] },
	"feld-weiter": { "tab": TAB, "id": ID, "richtung": ["int", -1, 1] },
	"suche": { "tab": TAB, "text": ["text", 200] },
	"suche-weiter": { "tab": TAB, "richtung": ["int", -1, 1] },
	"blocker": { "tab": TAB, "an": ["bool"] },
	"blocker-liste": { "hosts": ["optionen"] },
	"kern": { "aktion": ["wahl", KERN_AKTION] },
	## Spotify-Sitzung: eine Abfrage in der Seite (Regeln je Ziel: spotify_abfrage_grund).
	"spotify-abfrage": { "id": ID, "ziel": ["wahl", SPOTIFY_ZIELE], "methode": ["wahl", SPOTIFY_METHODEN], "pfad": ["pfad", MAX_PFAD],
		"inhalt": ["json", MAX_INHALT], "verbindung": ["schluessel", MAX_VERBINDUNG], "zeit": ["int", 1000, 30000] },
	"ende": {},
}

## Wirt → Uzai.
const EREIGNISSE := {
	"bereit": { "version": ["text", 96] },
	"fehler": { "code": ["wahl", FEHLER] },
	"tab": { "tab": TAB, "url": ["seite"], "titel": TEXT_KURZ, "laedt": ["bool"], "zurueck": ["bool"], "vor": ["bool"],
		"zoom": ["int", ZOOM_MIN, ZOOM_MAX], "privat": ["bool"], "aktiv": ["bool"] },
	"tab-zu": { "tab": TAB },
	"karte": { "tab": TAB, "vw": ["int", 1, 20000], "vh": ["int", 1, 20000], "sy": ["int", 0, 10000000], "sh": ["int", 0, 10000000],
		"ziele": ["ziele"] },
	"ziel": { "tab": TAB, "id": ID, "x": KOORD, "y": KOORD, "w": ["int", 1, 20000], "h": ["int", 1, 20000] },
	"feld": { "tab": TAB, "id": ID, "typ": ["wahl", FELDER], "wert": ["text", 2000] },
	"link": { "tab": TAB, "id": ID, "url": ["url_fremd"] },
	"video": { "tab": TAB, "da": ["bool"], "laeuft": ["bool"], "zeit": ["int", 0, 1000000], "dauer": ["int", 0, 1000000], "voll": ["bool"],
		"laut": ["int", 0, 100], "stumm": ["bool"], "tempo": ["int", 25, 400], "untertitel": ["int", -1, 1] },
	"frage": { "frage": ID, "art": ["wahl", FRAGEN], "herkunft": ["text", 253], "text": TEXT_KURZ },
	"meldung": { "tab": TAB, "herkunft": ["text", 253], "text": TEXT_KURZ },
	"download": { "name": ["text", 120], "stand": ["wahl", DOWNLOAD] },
	"gesperrt": { "tab": ["int", 0, 1000000], "grund": ["wahl", SPERREN] },
	"vorschau": { "tab": TAB, "datei": ["datei"] },
	"lesen": { "tab": TAB, "titel": TEXT_KURZ, "absaetze": ["absaetze"] },
	"vollbild": { "tab": TAB, "an": ["bool"] },
	"absturz": { "tab": TAB },
	"gliederung": { "tab": TAB, "punkte": ["punkte"] },
	"wahl": { "tab": TAB, "id": ID, "optionen": ["optionen"], "aktuell": ["int", -1, 399] },
	"formular": { "tab": TAB, "id": ID, "index": ["int", 0, 999], "anzahl": ["int", 0, 999], "ende": ["bool"] },
	"suche": { "tab": TAB, "treffer": ["int", 0, 100000], "aktuell": ["int", 0, 100000] },
	"blocker": { "tab": TAB, "anzahl": ["int", 0, 1000000], "versteckt": ["int", 0, 1000000], "cookies": ["wahl", COOKIES] },
	"kern": { "stand": ["wahl", KERN_STAND], "schritt": ["text", 32], "prozent": ["int", 0, 100], "fassung": ["text", 64], "text": ["text", 3000] },
	## Spotify-Sitzung (spotify_web.gd): Schlüssel aus den eigenen Anfragen der Seite – nur Zeichen von Base64(url).
	"spotify": { "token": ["schluessel", 2048], "client": ["schluessel", 2048], "version": ["schluessel", 40] },
	## Antwort auf „spotify-abfrage“: code 0 = keine Antwort (grund sagt warum); text roh (nur als JSON gelesen).
	"spotify-antwort": { "id": ID, "code": ["int", 0, 999], "grund": ["wahl", SPOTIFY_GRUENDE], "text": ["roh", MAX_ANTWORT],
		"gekuerzt": ["bool"], "warte": ["int", 0, 86400] },
}


## Befehl als Zeile (mit Zeilenende) – "" wenn er nicht ins Schema passt (wird dann nie geschickt).
static func befehl(art: String, daten: Dictionary = {}) -> String:
	var d := daten.duplicate()
	d["t"] = art
	var ok := befehl_pruefen(d)
	if ok.is_empty():
		return ""
	var line := JSON.stringify(ok)
	return "" if line.to_utf8_buffer().size() > MAX_BEFEHL else line + "\n"


## Ein Befehl gegen das Schema und die Regeln je Art (wie UzbSchema.Befehl im Wirt): {} wenn er nicht passt.
static func befehl_pruefen(m: Dictionary) -> Dictionary:
	var ok := pruefe(m, BEFEHLE, true)
	if not ok.is_empty() and ok.t == "spotify-abfrage" and spotify_abfrage_grund(ok.ziel, ok.methode, ok.pfad, ok.inhalt, ok.verbindung) != "":
		return {}
	return ok


## Eine Zeile des Wirts → geprüftes Ereignis ({} wenn kaputt, unbekannt oder außerhalb der Grenzen).
static func ereignis(line: String) -> Dictionary:
	if line.is_empty() or line.length() > MAX_ZEILE:
		return {}
	var v: Variant = Fremd.json_roh(line)
	if not (v is Dictionary):
		return {}
	# Länger als MAX_EREIGNIS darf nur eine Spotify-Antwort sein (ihr Text hat seine eigene Grenze).
	if line.length() > MAX_EREIGNIS and (v as Dictionary).get("t") != "spotify-antwort":
		return {}
	return pruefe(v, EREIGNISSE, false)


## Prüft eine Nachricht gegen das Schema: genau die Felder der Art (zusätzliche fallen weg, fehlende
## machen sie ungültig), jedes im Typ und Bereich. Ergebnis mit sauberen Werten (Zahlen als int).
static func pruefe(m: Dictionary, schema: Dictionary, befehl_seite: bool) -> Dictionary:
	var art: Variant = m.get("t", null)
	if not (art is String) or not schema.has(art):
		return {}
	var felder: Dictionary = schema[art]
	var out := { "t": art }
	for k in felder:
		if not m.has(k):
			return {}
		var w: Variant = wert(m[k], felder[k], befehl_seite, m)
		if w == null:
			return {}
		out[k] = w
	return out


## Ein Feld nach seiner Regel; null = ungültig.
static func wert(v: Variant, regel: Array, befehl_seite: bool, m: Dictionary) -> Variant:
	match str(regel[0]):
		"int":
			if not (v is int or v is float):
				return null
			var f := float(v)
			if is_nan(f) or is_inf(f) or f != floorf(f) or f < float(regel[1]) or f > float(regel[2]):
				return null
			return int(f)
		"bool":
			return v if v is bool else null
		"text":
			if not (v is String) or (v as String).length() > int(regel[1]):
				return null
			return Adresse.sauber(v, int(regel[1]))
		"wahl":
			return v if v is String and (regel[1] as Array).has(v) else null
		"url":
			if not (v is String):
				return null
			return v if Adresse.grund(v, befehl_seite and m.get("nutzer", false) == true) == "" else null
		"url_fremd":
			# Ein Link auf der Seite: darf auch ins Heimnetz zeigen (der Wirt sperrt ihn beim Öffnen).
			if not (v is String):
				return null
			var g := Adresse.grund(v, true)
			return v if g == "" else null
		"seite":
			if not (v is String) or (v as String).length() > Adresse.MAX_URL:
				return null
			return v if v == "about:blank" or Adresse.grund(v, true) == "" else null
		"datei":
			if not (v is String):
				return null
			return v if _RX_VORSCHAU.search(v) != null else null
		"schluessel":
			if not (v is String) or (v as String).length() > int(regel[1]):
				return null
			return v if schluessel_ok(v) else null
		"pfad":
			return v if v is String and pfad_ok(v, int(regel[1])) else null
		"json":
			# Inhalt einer Abfrage: leer oder ein JSON-Objekt (nur gelesen, nie ausgeführt).
			if not (v is String) or (v as String).length() > int(regel[1]):
				return null
			return v if v == "" or Fremd.json_roh(v) is Dictionary else null
		"roh":
			# Antworttext: nur Typ und Länge – Uzai liest ihn ausschließlich als JSON (Net.parse_json).
			return v if v is String and (v as String).length() <= int(regel[1]) else null
		"ziele":
			return ziele(v)
		"punkte":
			return punkte(v)
		"optionen":
			if not (v is Array) or (v as Array).size() > MAX_OPTIONEN:
				return null
			var opt: Array = []
			for a in v:
				if not (a is String) or (a as String).length() > 120:
					return null
				opt.append(Adresse.sauber(a, 120))
			return opt
		"absaetze":
			if not (v is Array) or (v as Array).size() > MAX_ABSAETZE:
				return null
			var out: Array = []
			for a in v:
				if not (a is String) or (a as String).length() > 3000:
					return null
				var s := Adresse.sauber(a, 3000)
				if s != "":
					out.append(s)
			return out
	return null


## Nur A–Z a–z 0–9 - _ . + / = (Base64 bzw. Base64url); leer ist erlaubt.
static func schluessel_ok(s: String) -> bool:
	for c in s:
		var u := c.unicode_at(0)
		if not ((u >= 65 and u <= 90) or (u >= 97 and u <= 122) or (u >= 48 and u <= 57) or c in ["-", "_", ".", "+", "/", "="]):
			return false
	return true


## Pfad einer Spotify-Abfrage: beginnt mit „/“, nur A–Z a–z 0–9 und - . _ ~ % / ? & = , : +, kein „..“, „//“.
static func pfad_ok(p: String, max_len := MAX_PFAD) -> bool:
	if p.length() < 2 or p.length() > max_len or not p.begins_with("/") or p.contains("..") or p.contains("//"):
		return false
	for c in p:
		var u := c.unicode_at(0)
		if not ((u >= 65 and u <= 90) or (u >= 97 and u <= 122) or (u >= 48 and u <= 57) or c in ["-", ".", "_", "~", "%", "/", "?", "&", "=", ",", ":", "+"]):
			return false
	return true


## Darf diese Abfrage in der Seite laufen? "" = ja, sonst "ziel". Dieselben Regeln prüft der Kern (UzcSpotify.AbfrageGrund):
## pathfinder nur POST auf PATHFINDER_PFAD mit operationName und sha256-Hash; spclient nur SPOTIFY_SPCLIENT (PUT nur
## SPOTIFY_PUT, POST nur Spotify Connect); Web-API nur GET/POST unter /v1/. Verbindungs-Kennung nur für Spotify Connect.
static func spotify_abfrage_grund(ziel: String, methode: String, pfad: String, inhalt: String, verbindung: String) -> String:
	if not ziel in SPOTIFY_ZIELE or not methode in SPOTIFY_METHODEN or not pfad_ok(pfad) or inhalt.length() > MAX_INHALT:
		return "ziel"
	if verbindung.length() > MAX_VERBINDUNG or not schluessel_ok(verbindung):
		return "ziel"
	var body: Variant = null
	if inhalt != "":
		body = Fremd.json_roh(inhalt)
		if not (body is Dictionary):
			return "ziel"
	if methode == "GET" and inhalt != "":
		return "ziel"
	var connect := pfad.begins_with("/connect-state/v1/")
	if verbindung != "" and not (ziel == "spclient" and connect):
		return "ziel"
	match ziel:
		"pathfinder":
			if methode != "POST" or pfad != PATHFINDER_PFAD or not (body is Dictionary):
				return "ziel"
			var op: Variant = (body as Dictionary).get("operationName")
			var ext: Variant = (body as Dictionary).get("extensions")
			var pq: Variant = (ext as Dictionary).get("persistedQuery") if ext is Dictionary else null
			var h64: Variant = (pq as Dictionary).get("sha256Hash") if pq is Dictionary else null
			if not (op is String) or _RX_ABFRAGE.search(op) == null:
				return "ziel"
			if not (h64 is String) or _RX_SHA256.search(h64) == null:
				return "ziel"
			if not ((body as Dictionary).get("variables") is Dictionary):
				return "ziel"
		"spclient":
			if not SPOTIFY_SPCLIENT.any(func(v: String) -> bool: return pfad.begins_with(v)):
				return "ziel"
			if methode == "PUT" and not SPOTIFY_PUT.any(func(v: String) -> bool: return pfad.begins_with(v)):
				return "ziel"
			if methode == "POST" and not connect:
				return "ziel"
		"webapi":
			if methode == "PUT" or not pfad.begins_with("/v1/"):
				return "ziel"
	return ""


## Gliederung einer Seite: höchstens MAX_PUNKTE, je [id, y (Seiten-Koordinate), stufe 0–6, text ≤ 80].
static func punkte(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() > MAX_PUNKTE:
		return null
	var out: Array = []
	for z in v:
		if not (z is Array) or (z as Array).size() != 4:
			return null
		var zahlen: Array = []
		var grenzen := [[1, 1000000000], [0, 10000000], [0, 6]]
		for i in 3:
			var e: Variant = z[i]
			if not (e is int or e is float):
				return null
			var f := float(e)
			if is_nan(f) or f != floorf(f) or f < float(grenzen[i][0]) or f > float(grenzen[i][1]):
				return null
			zahlen.append(int(f))
		if not (z[3] is String) or (z[3] as String).length() > 80:
			return null
		zahlen.append(Adresse.sauber(z[3], 80))
		out.append(zahlen)
	return out


## Ziele der Fokus-Karte: höchstens MAX_ZIELE, je [id, x, y, w, h, art, bereich] als ganze Zahlen in
## festen Bereichen. Ein kaputtes Ziel macht die ganze Karte ungültig (der Wirt prüft dasselbe).
static func ziele(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() > MAX_ZIELE:
		return null
	var out: Array = []
	var grenzen := [[1, 1000000000], [-100000, 100000], [-100000, 100000], [1, 20000], [1, 20000], [0, ARTEN.size() - 1],
		[0, BEREICHE.size() - 1]]
	for z in v:
		if not (z is Array) or (z as Array).size() != 7:
			return null
		var zeile: Array = []
		for i in 7:
			var e: Variant = z[i]
			if not (e is int or e is float):
				return null
			var f := float(e)
			if is_nan(f) or f != floorf(f) or f < float(grenzen[i][0]) or f > float(grenzen[i][1]):
				return null
			zeile.append(int(f))
		out.append(zeile)
	return out
