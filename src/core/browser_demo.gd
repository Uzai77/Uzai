extends RefCounted
## Uzai-Browser im Vorführmodus (ohne Windows, mit --demo): spielt den Browser-Wirt mit einer
## Platzhalter-Seite – Kopf mit Navigation und Suchfeld, Aufmacher, Kacheln, Artikel mit Video,
## Seitenleiste, Formular, Fuß. Antwortet auf dieselben Befehle wie der echte Wirt und schickt jede
## Meldung als JSON-Zeile durch dasselbe Schema (browser_wirt.gd _zeile). Keine echte Webseite, kein Netz.
## seite() liefert die Blöcke zum Zeichnen (browser_seite_demo.gd). Dazu spielt er den Blocker (Zahlen je
## Seite), die Gliederung, Wahl-Listen, das Formular, die Suche auf der Seite und die Antworten des Kerns.
## Spotify-Sitzung: accounts.spotify.com ist eine schlichte Platzhalter-Anmeldung (Felder, „Anmelden“ führt zum
## Webplayer); auf open.spotify.com meldet er einen Beispiel-Schlüssel (Ereignis „spotify“) wie der echte Kern und
## beantwortet Abfragen in der Seite („spotify-abfrage“ → „spotify-antwort“) mit Beispieldaten – Tests setzen
## spotify_antwort (Callable), um Antworten, Verzögerung, Schweigen und Größe nachzubauen.

const P := preload("res://src/core/browser_protokoll.gd")

const BASIS := Vector2(1280, 720)       ## CSS-Bild bei 100 %
const TITEL := ["Neue Konsole im Test", "Die besten Koop-Spiele", "Retro-Abend: zehn Klassiker", "So klingt der Herbst",
	"Was Controller besser macht", "Bildschirm richtig einstellen", "Ein Jahr mit dem Handheld", "Leise PCs fürs Wohnzimmer"]
const NAV := ["Neu", "Spiele", "Technik", "Kultur", "Sport"]
const BELIEBT := ["Wetter am Wochenende", "Rezept: Kürbissuppe", "Liga: alle Tore", "Sternenhimmel im November", "Bahn: neue Strecken",
	"Podcast der Woche"]
const FUSS := ["Impressum", "Datenschutz", "Kontakt", "Hilfe", "Nach oben"]

const WAHL := ["Deutsch", "English", "Français", "Español", "Italiano"]
const SPOTIFY_DEMO_TOKEN := "VorfuehrungSchluessel0123456789"

var _melden: Callable
var _tabs := {}
var _gen := 0
var _naechster_tab := 1
var _aktiv := 0
var _blocker_aus: Array = []
var kern_befehle: Array = []       ## was an den Kern ging (für Tests)
## Tests: (ziel, methode, pfad, inhalt) -> { code, text, nach_s, still } (still: keine Antwort, wie ein hängender Renderer).
static var spotify_antwort := Callable()
static var spotify_abfragen: Array = []   ## Abfragen, die in der Seite ankamen (ohne Inhalt; für Tests)
var _spaeter: Array = []           ## [rest_s, zeile] – verzögerte Antworten


func verbinden(cb: Callable) -> void:
	_melden = cb
	_senden({ "t": "bereit", "version": "demo" })


func _senden(d: Dictionary) -> void:
	if _melden.is_valid():
		_melden.call(JSON.stringify(d))


func befehl(v: Variant) -> void:
	if not (v is Dictionary):
		return
	var m: Dictionary = v
	match str(m.get("t", "")):
		"tab-neu":
			_neuer_tab(str(m.url), bool(m.privat), bool(m.vorn))
		"tab-zu":
			_tabs.erase(int(m.tab))
			if _aktiv == int(m.tab):
				_aktiv = 0
			_senden({ "t": "tab-zu", "tab": int(m.tab) })
		"tab-wahl":
			if _tabs.has(int(m.tab)):
				_aktiv = int(m.tab)
				_status(_aktiv)
				_karte(int(m.tab))
		"laden":
			_laden(int(m.tab), str(m.url), true)
		"zurueck":
			_zurueck(int(m.tab))
		"neu":
			_laden(int(m.tab), str(_tab(int(m.tab)).get("url", "")), false)
		"zoom":
			var t := _tab(int(m.tab))
			if not t.is_empty():
				t.zoom = int(m.prozent)
				_aufbauen(t)
				_status(int(m.tab))
				_karte(int(m.tab))
		"rollen":
			var t2 := _tab(int(m.tab))
			if not t2.is_empty():
				# Stick los: die Seite läuft mit der letzten Geschwindigkeit aus (Trägheit).
				if int(m.vx) == 0 and int(m.vy) == 0:
					t2.halten = false
				else:
					t2.v = Vector2(float(m.vx), float(m.vy))
					t2.halten = true
		"fokus":
			_fokus(int(m.tab), int(m.id))
		"karte":
			_karte(int(m.tab))
		"aktivieren":
			_aktivieren(int(m.tab), int(m.id), bool(m.neu))
		"klick":
			var t3 := _tab(int(m.tab))
			if not t3.is_empty():
				var p := Vector2(float(m.x), float(m.y) + float(t3.sy))
				for b in t3.bloecke:
					if int(b.art) >= 0 and (b.r as Rect2).has_point(p):
						_aktivieren(int(m.tab), int(b.id), false)
						break
		"link":
			var b2 := _block(int(m.tab), int(m.id))
			if not b2.is_empty() and str(b2.get("ziel", "")) != "":
				_senden({ "t": "link", "tab": int(m.tab), "id": int(m.id), "url": str(b2.ziel) })
		"feld":
			var b3 := _block(int(m.tab), int(m.id))
			if not b3.is_empty() and int(b3.art) == P.ARTEN.find("feld"):
				_senden({ "t": "feld", "tab": int(m.tab), "id": int(m.id), "typ": str(b3.get("typ", "text")),
					"wert": str((_tab(int(m.tab)).felder as Dictionary).get(int(m.id), "")) })
		"text":
			var t4 := _tab(int(m.tab))
			if not t4.is_empty():
				t4.felder[int(m.id)] = str(m.text)
		"video":
			var t5 := _tab(int(m.tab))
			if not t5.is_empty():
				match str(m.aktion):
					"umschalten":
						t5.video = not bool(t5.video)
					"pause":
						t5.video = false
					"spielen":
						t5.video = true
					"vor":
						t5.zeit = mini(int(t5.zeit) + 10, 600)
					"zurueck":
						t5.zeit = maxi(int(t5.zeit) - 10, 0)
					"vor_lang":
						t5.zeit = mini(int(t5.zeit) + 60, 600)
					"zurueck_lang":
						t5.zeit = maxi(int(t5.zeit) - 60, 0)
					"lauter":
						t5.laut = mini(int(t5.laut) + 10, 100)
						t5.stumm = false
					"leiser":
						t5.laut = maxi(int(t5.laut) - 10, 0)
					"stumm":
						t5.stumm = not bool(t5.stumm)
					"tempo_auf":
						t5.tempo = mini(int(t5.tempo) + 25, 200)
					"tempo_ab":
						t5.tempo = maxi(int(t5.tempo) - 25, 50)
					"untertitel":
						t5.untertitel = 1 if int(t5.untertitel) != 1 else 0
				_video(int(m.tab))
		"lesen":
			var t6 := _tab(int(m.tab))
			if not t6.is_empty():
				var abs: Array = []
				for i in 6:
					abs.append("Absatz %d: Platzhalter-Text der Vorführung. Der Lesemodus zeigt nur den Text der Seite, groß und im Theme von Uzai, ohne Werbung und ohne Kopf der Seite." % (i + 1))
				_senden({ "t": "lesen", "tab": int(m.tab), "titel": str(t6.titel), "absaetze": abs })
		"gliederung":
			_gliederung(int(m.tab))
		"springe":
			var t7 := _tab(int(m.tab))
			var b7 := _block(int(m.tab), int(m.id))
			if not t7.is_empty() and not b7.is_empty():
				t7.sy = clampf((b7.r as Rect2).position.y - 24.0, 0.0, maxf(0.0, float(t7.hoehe) - ansicht(t7).y))
				_karte(int(m.tab))
		"wahl":
			var b8 := _block(int(m.tab), int(m.id))
			if not b8.is_empty() and str(b8.get("typ", "")) == "wahl":
				_senden({ "t": "wahl", "tab": int(m.tab), "id": int(m.id), "optionen": WAHL,
					"aktuell": int((_tab(int(m.tab)).felder as Dictionary).get(int(m.id), 0)) })
		"wahl-setzen":
			var t9 := _tab(int(m.tab))
			if not t9.is_empty():
				t9.felder[int(m.id)] = int(m.index)
		"feld-weiter":
			_feld_weiter(int(m.tab), int(m.id), int(m.richtung))
		"suche":
			var t10 := _tab(int(m.tab))
			if not t10.is_empty():
				t10.suche = str(m.text)
				t10.treffer = 0
				if str(m.text) != "":
					for b in t10.bloecke:
						if str(b.get("text", "")).to_lower().contains(str(m.text).to_lower()):
							t10.treffer = int(t10.treffer) + 1
				t10.aktuell = 1 if int(t10.treffer) > 0 else 0
				_senden({ "t": "suche", "tab": int(m.tab), "treffer": int(t10.treffer), "aktuell": int(t10.aktuell) })
		"suche-weiter":
			var t11 := _tab(int(m.tab))
			if not t11.is_empty() and int(t11.get("treffer", 0)) > 0:
				t11.aktuell = posmod(int(t11.get("aktuell", 1)) - 1 + int(m.richtung), int(t11.treffer)) + 1
				_senden({ "t": "suche", "tab": int(m.tab), "treffer": int(t11.treffer), "aktuell": int(t11.aktuell) })
		"blocker":
			var t12 := _tab(int(m.tab))
			if not t12.is_empty():
				t12.blocker = bool(m.an)
				_blocker(int(m.tab))
		"blocker-liste":
			_blocker_aus = (m.hosts as Array).duplicate()
		"kern":
			_kern(str(m.aktion))
		"spotify-abfrage": _spotify_abfrage(m)


## Abfrage in der „Seite“: dieselben Regeln wie der echte Kern (an der Leitung schon geprüft), Antwort mit Kennung.
func _spotify_abfrage(m: Dictionary) -> void:
	var id := int(m.id)
	spotify_abfragen.append({ "ziel": str(m.ziel), "methode": str(m.methode), "pfad": str(m.pfad) })
	var seite := false
	for t in _tabs.values():
		seite = seite or _host(str((t as Dictionary).url)) == "open.spotify.com"
	if not seite:
		_senden({ "t": "spotify-antwort", "id": id, "code": 0, "grund": "welt", "text": "", "gekuerzt": false, "warte": 0 })
		return
	var a: Dictionary = { "code": 404, "text": "{\"error\":{\"status\":404,\"message\":\"Vorführung\"}}" }
	if spotify_antwort.is_valid():
		var v: Variant = spotify_antwort.call(str(m.ziel), str(m.methode), str(m.pfad), str(m.inhalt))
		a = v if v is Dictionary else a
	elif str(m.ziel) == "pathfinder" and str(m.inhalt).contains("\"profileAttributes\""):
		a = { "code": 200, "text": JSON.stringify({ "data": { "me": { "profile": { "username": "vorfuehrung", "name": "Vorführung" } } } }) }
	if bool(a.get("still", false)):
		return
	var text := str(a.get("text", ""))
	var gekuerzt := text.length() > P.MAX_ANTWORT
	var zeile := JSON.stringify({ "t": "spotify-antwort", "id": id, "code": int(a.get("code", 0)), "grund": str(a.get("grund", "")),
		"text": text.left(P.MAX_ANTWORT), "gekuerzt": gekuerzt, "warte": int(a.get("warte", 0)) })
	if float(a.get("nach_s", 0.0)) > 0.0:
		_spaeter.append([float(a.nach_s), zeile])
	elif _melden.is_valid():
		_melden.call(zeile)


func _tab(id: int) -> Dictionary:
	return _tabs.get(id, {})


func _block(tab: int, id: int) -> Dictionary:
	for b in _tab(tab).get("bloecke", []):
		if int(b.id) == id:
			return b
	return {}


func _neuer_tab(url: String, privat: bool, vorn := true) -> void:
	if _tabs.size() >= P.MAX_TABS:
		_senden({ "t": "fehler", "code": "tabs" })
		return
	var id := _naechster_tab
	_naechster_tab += 1
	_tabs[id] = { "id": id, "url": "", "titel": "", "verlauf": [], "sy": 0.0, "zoom": 100, "v": Vector2.ZERO, "halten": false,
		"privat": privat, "felder": {}, "video": false, "zeit": 0, "bloecke": [], "hoehe": 0.0, "takt": 0, "blocker": true, "suche": "",
		"treffer": 0, "aktuell": 0, "laut": 70, "stumm": false, "tempo": 100, "untertitel": -1 }
	if vorn or _aktiv == 0:
		_aktiv = id
	_laden(id, url, true)


func _laden(tab: int, url: String, neu: bool) -> void:
	var t := _tab(tab)
	if t.is_empty():
		return
	if neu and str(t.url) != "":
		(t.verlauf as Array).append(t.url)
	t.url = url
	t.sy = 0.0
	t.video = false
	t.zeit = 0
	var n := absi(url.hash())
	t.titel = "%s – Platzhalter" % TITEL[n % TITEL.size()]
	if _host(url) == "accounts.spotify.com":
		t.titel = "Anmelden – Spotify"
	elif _host(url) == "open.spotify.com":
		t.titel = "Spotify – Webplayer"
	t.suche = ""
	t.treffer = 0
	_aufbauen(t)
	_status(tab)
	_karte(tab)
	_blocker(tab)
	if _host(url) == "open.spotify.com":
		_senden({ "t": "spotify", "token": SPOTIFY_DEMO_TOKEN, "client": "", "version": "1.2.0" })


static func _host(url: String) -> String:
	return url.get_slice("://", 1).get_slice("/", 0).to_lower() if url.contains("://") else ""


func _zurueck(tab: int) -> void:
	var t := _tab(tab)
	if t.is_empty() or (t.verlauf as Array).is_empty():
		return
	var url: String = (t.verlauf as Array).pop_back()
	_laden(tab, url, false)


func _status(tab: int) -> void:
	var t := _tab(tab)
	_senden({ "t": "tab", "tab": tab, "url": str(t.url), "titel": str(t.titel), "laedt": false, "zurueck": not (t.verlauf as Array).is_empty(),
		"vor": false, "zoom": int(t.zoom), "privat": bool(t.privat), "aktiv": tab == _aktiv })


func ansicht(t: Dictionary) -> Vector2:
	return (BASIS * 100.0 / float(t.zoom)).round()


## Die Platzhalter-Seite für die Breite des Bildes (CSS-Pixel): Blöcke mit Rechteck in Seiten-
## Koordinaten, Art (-1: kein Ziel), Bereich und Text.
func _aufbauen(t: Dictionary) -> void:
	_gen += 1
	var v := ansicht(t)
	var x0 := maxf(32.0, (v.x - 1200.0) * 0.5)
	var cw := minf(1200.0, v.x - 64.0)
	var b: Array = []
	var nr := [0]
	var add := func(r: Rect2, art: String, bereich: String, text: String, extra: Dictionary) -> void:
		var e := { "r": r, "art": P.ARTEN.find(art) if art != "" else -1, "bereich": P.BEREICHE.find(bereich), "text": text, "id": 0 }
		if art != "":
			nr[0] += 1
			e.id = _gen * 1000 + nr[0]
		e.merge(extra)
		b.append(e)
	var slug := func(s: String) -> String: return "https://uzai.example/" + s.to_lower().replace(" ", "-").replace(":", "").replace("ü", "ue").replace("ä", "ae")
	if _host(str(t.url)) in ["accounts.spotify.com", "open.spotify.com"]:
		_spotify_seite(t, v, add)
		t.bloecke = b
		return
	add.call(Rect2(0, 0, v.x, 72), "", "kopf", "", { "art_bild": "leiste" })
	add.call(Rect2(x0, 16, 150, 40), "link", "kopf", "Platzhalter", { "ziel": "https://uzai.example/start", "art_bild": "logo" })
	var x := x0 + 182.0
	for n in NAV:
		var w: float = 22.0 + str(n).length() * 11.0
		add.call(Rect2(x, 16, w, 40), "link", "navigation", n, { "ziel": slug.call(n) })
		x += w + 10.0
	add.call(Rect2(x0 + cw - 404, 16, 270, 40), "feld", "kopf", "Suchen", { "typ": "suche" })
	add.call(Rect2(x0 + cw - 120, 16, 120, 40), "knopf", "kopf", "Anmelden", { "ziel": "https://uzai.example/anmelden" })
	var n0 := absi(str(t.url).hash())
	var hw := floorf(cw * 0.62)
	add.call(Rect2(x0, 104, hw, 360), "bild", "inhalt", TITEL[n0 % TITEL.size()], { "ziel": slug.call(TITEL[n0 % TITEL.size()]), "farbe": float(n0 % 100) / 100.0 })
	for i in 3:
		var tt: String = TITEL[(n0 + i + 1) % TITEL.size()]
		add.call(Rect2(x0 + hw + 24, 104 + i * 124, cw - hw - 24, 108), "link", "inhalt", tt, { "ziel": slug.call(tt) })
	add.call(Rect2(x0, 500, 400, 36), "", "inhalt", "Neu für dich", { "art_bild": "ueberschrift" })
	var kw := floorf((cw - 48.0) / 3.0)
	for i in 6:
		var tt2: String = TITEL[(n0 + i + 4) % TITEL.size()]
		var r := Rect2(x0 + (i % 3) * (kw + 24.0), 556 + floorf(i / 3.0) * 284.0, kw, 260)
		add.call(r, "bild", "inhalt", tt2, { "ziel": slug.call(tt2 + " " + str(i)), "farbe": float((n0 + i * 17) % 100) / 100.0 })
	var ay := 1150.0
	var aw := floorf(cw * 0.66)
	add.call(Rect2(x0, ay, aw, 48), "", "inhalt", TITEL[(n0 + 2) % TITEL.size()], { "art_bild": "titel" })
	add.call(Rect2(x0, ay + 70, aw, 150), "", "inhalt", "", { "art_bild": "text", "zeilen": 5 })
	add.call(Rect2(x0 + 120, ay + 70 + 30 * 2, 170, 28), "link", "inhalt", "mehr dazu", { "ziel": "https://uzai.example/mehr" })
	add.call(Rect2(x0, ay + 250, aw, floorf(aw * 9.0 / 16.0)), "video", "inhalt", "Video", {})
	var vy := ay + 250 + floorf(aw * 9.0 / 16.0) + 30
	add.call(Rect2(x0, vy, aw, 240), "", "inhalt", "", { "art_bild": "text", "zeilen": 8 })
	add.call(Rect2(x0, vy + 270, aw * 0.7, 48), "feld", "inhalt", "Dein Kommentar", { "typ": "text" })
	add.call(Rect2(x0 + aw * 0.7 + 16, vy + 270, 140, 48), "knopf", "inhalt", "Senden", { "ziel": "https://uzai.example/danke" })
	add.call(Rect2(x0, vy + 334, aw * 0.42, 48), "feld", "inhalt", "Name", { "typ": "text" })
	add.call(Rect2(x0 + aw * 0.42 + 16, vy + 334, aw * 0.28, 48), "feld", "inhalt", "Sprache", { "typ": "wahl" })
	add.call(Rect2(x0, vy + 420, aw, 1200), "", "inhalt", "", { "art_bild": "text", "zeilen": 40 })
	var sx := x0 + aw + 40
	var sw := cw - aw - 40
	add.call(Rect2(sx, ay, sw, 36), "", "seite", "Beliebt", { "art_bild": "ueberschrift" })
	for i in BELIEBT.size():
		# Links zu einer anderen Seite (für die Link-Vorschau: ihr Name steht dann unter dem Rahmen).
		add.call(Rect2(sx, ay + 56 + i * 56, sw, 44), "link", "seite", BELIEBT[i], { "ziel": str(slug.call(BELIEBT[i])).replace("uzai.example", "beliebt.example") })
	var fy := vy + 1620
	add.call(Rect2(0, fy, v.x, 160), "", "fuss", "", { "art_bild": "fuss" })
	var fx := x0
	for n2 in FUSS:
		var w2: float = 24.0 + str(n2).length() * 10.0
		add.call(Rect2(fx, fy + 56, w2, 40), "link", "fuss", n2, { "ziel": slug.call(n2) })
		fx += w2 + 24.0
	t.bloecke = b
	t.hoehe = fy + 160


## Platzhalter der Spotify-Anmeldung bzw. des Webplayers (keine Nachbildung der echten Seite).
func _spotify_seite(t: Dictionary, v: Vector2, add: Callable) -> void:
	var cw := 460.0
	var x0 := floorf((v.x - cw) * 0.5)
	if _host(str(t.url)) == "open.spotify.com":
		add.call(Rect2(x0, 200, cw, 48), "", "inhalt", "Webplayer (Vorführung)", { "art_bild": "titel" })
		t.hoehe = v.y
		return
	add.call(Rect2(x0, 90, cw, 48), "", "inhalt", "Anmeldeseite (Vorführung)", { "art_bild": "titel" })
	add.call(Rect2(x0, 170, cw, 52), "knopf", "inhalt", "Mit Google fortfahren", { "ziel": "https://open.spotify.com/" })
	add.call(Rect2(x0, 236, cw, 52), "knopf", "inhalt", "Mit Apple fortfahren", { "ziel": "https://open.spotify.com/" })
	add.call(Rect2(x0, 330, cw, 52), "feld", "inhalt", "E-Mail-Adresse oder Benutzername", { "typ": "email" })
	add.call(Rect2(x0, 398, cw, 52), "feld", "inhalt", "Passwort", { "typ": "passwort" })
	add.call(Rect2(x0, 476, cw, 56), "knopf", "inhalt", "Anmelden", { "ziel": "https://open.spotify.com/" })
	add.call(Rect2(x0, 556, cw, 40), "link", "inhalt", "Ohne Passwort anmelden", { "ziel": "https://accounts.spotify.com/de/login" })
	t.hoehe = v.y


func _karte(tab: int) -> void:
	var t := _tab(tab)
	if t.is_empty():
		return
	var v := ansicht(t)
	var sy := float(t.sy)
	var ziele: Array = []
	for b in t.bloecke:
		if int(b.art) < 0:
			continue
		var r: Rect2 = b.r
		if r.end.y < sy - v.y or r.position.y > sy + v.y * 2.0:
			continue
		ziele.append([int(b.id), roundi(r.position.x), roundi(r.position.y - sy), maxi(1, roundi(r.size.x)), maxi(1, roundi(r.size.y)), int(b.art),
			int(b.bereich)])
	_senden({ "t": "karte", "tab": tab, "vw": int(v.x), "vh": int(v.y), "sy": roundi(sy), "sh": roundi(float(t.hoehe)), "ziele": ziele })


func _fokus(tab: int, id: int) -> void:
	var t := _tab(tab)
	var b := _block(tab, id)
	if b.is_empty():
		return
	var v := ansicht(t)
	var r: Rect2 = b.r
	var sy := float(t.sy)
	if r.position.y < sy + 80.0 or r.end.y > sy + v.y - 40.0:
		t.sy = clampf(r.get_center().y - v.y * 0.45, 0.0, maxf(0.0, float(t.hoehe) - v.y))
		_karte(tab)
	_senden({ "t": "ziel", "tab": tab, "id": id, "x": roundi(r.position.x), "y": roundi(r.position.y - float(t.sy)), "w": roundi(r.size.x),
		"h": roundi(r.size.y) })


func _aktivieren(tab: int, id: int, neu: bool) -> void:
	var b := _block(tab, id)
	if b.is_empty():
		return
	var art: String = P.ARTEN[int(b.art)]
	if art == "feld":
		if str(b.get("typ", "")) == "wahl":
			befehl({ "t": "wahl", "tab": tab, "id": id })
			return
		befehl({ "t": "feld", "tab": tab, "id": id })
		_formular(tab, id)
		return
	if art == "video":
		befehl({ "t": "video", "tab": tab, "aktion": "umschalten" })
		return
	var ziel := str(b.get("ziel", ""))
	if ziel == "":
		return
	if neu:
		_neuer_tab(ziel, bool(_tab(tab).privat), false)
	else:
		_laden(tab, ziel, true)


func _video(tab: int) -> void:
	var t := _tab(tab)
	_senden({ "t": "video", "tab": tab, "da": true, "laeuft": bool(t.video), "zeit": int(t.zeit), "dauer": 600, "voll": false,
		"laut": int(t.laut), "stumm": bool(t.stumm), "tempo": int(t.tempo), "untertitel": int(t.untertitel) })


## Die Felder der Seite in Lesereihenfolge (das Formular: Kommentar, Name, Sprache).
func _felder(tab: int) -> Array:
	var out: Array = []
	for b in _tab(tab).get("bloecke", []):
		if int(b.art) == P.ARTEN.find("feld"):
			out.append(b)
	return out


func _formular(tab: int, id: int) -> void:
	var f := _felder(tab)
	var i := -1
	for k in f.size():
		if int(f[k].id) == id:
			i = k
	if i < 0:
		return
	_senden({ "t": "formular", "tab": tab, "id": id, "index": i, "anzahl": f.size(), "ende": i == f.size() - 1 })


func _feld_weiter(tab: int, id: int, richtung: int) -> void:
	var f := _felder(tab)
	for k in f.size():
		if int(f[k].id) == id:
			var j := k + richtung
			if j >= 0 and j < f.size():
				_fokus(tab, int(f[j].id))
				_senden({ "t": "ziel", "tab": tab, "id": int(f[j].id), "x": roundi((f[j].r as Rect2).position.x),
					"y": roundi((f[j].r as Rect2).position.y - float(_tab(tab).sy)), "w": roundi((f[j].r as Rect2).size.x), "h": roundi((f[j].r as Rect2).size.y) })
				_aktivieren(tab, int(f[j].id), false)
			return


## Gliederung: die Überschriften der Platzhalter-Seite (Stufe 1 Titel, 2 Abschnitte), Ziel ist der Block.
func _gliederung(tab: int) -> void:
	var t := _tab(tab)
	if t.is_empty():
		return
	var punkte: Array = []
	for b in t.bloecke:
		var art := str(b.get("art_bild", ""))
		if art in ["titel", "ueberschrift"] and int(b.id) == 0:
			_gen += 1
			b.id = _gen * 1000 + 900
		if art == "titel":
			punkte.append([int(b.id), roundi((b.r as Rect2).position.y), 1, str(b.text)])
		elif art == "ueberschrift":
			punkte.append([int(b.id), roundi((b.r as Rect2).position.y), 2, str(b.text)])
	_senden({ "t": "gliederung", "tab": tab, "punkte": punkte })


## Blocker: Zahlen je Seite (aus dem Namen der Adresse, damit sie je Seite gleich bleiben), aus für Seiten auf der Liste.
func _blocker(tab: int) -> void:
	var t := _tab(tab)
	if t.is_empty():
		return
	var host := str(t.url).trim_prefix("https://").get_slice("/", 0)
	var an := bool(t.blocker) and not _blocker_aus.has(host)
	var n := absi(str(t.url).hash())
	_senden({ "t": "blocker", "tab": tab, "anzahl": (3 + n % 14) if an else 0, "versteckt": (2 + n % 9) if an else 0,
		"cookies": ("abgelehnt" if n % 3 != 0 else "") if an else "aus" })


## Der Kern antwortet: Stand, Diagnose (Sandbox ja), Update (nichts Neues) – nur gespielt.
func _kern(aktion: String) -> void:
	kern_befehle.append(aktion)
	match aktion:
		"diagnose":
			_senden({ "t": "kern", "stand": "diagnose", "schritt": "sandbox", "prozent": 100, "fassung": "demo",
				"text": "Vorführung: Sandbox an, kein Debug-Anschluss, API 15101." })
		"update":
			_senden({ "t": "kern", "stand": "stand", "schritt": "update", "prozent": 100, "fassung": "demo", "text": "" })
		"gesund":
			pass


## Rollen mit Trägheit wie im echten Sprung-Skript: Geschwindigkeit vom Stick, danach läuft sie aus. Die
## Karte kommt beim Rollen jedes dritte Bild neu und einmal, wenn die Seite steht.
func schritt(dt: float) -> void:
	for i in range(_spaeter.size() - 1, -1, -1):
		_spaeter[i][0] = float(_spaeter[i][0]) - dt
		if float(_spaeter[i][0]) <= 0.0:
			var z: String = _spaeter[i][1]
			_spaeter.remove_at(i)
			if _melden.is_valid():
				_melden.call(z)
	for id in _tabs:
		var t: Dictionary = _tabs[id]
		var v: Vector2 = t.v
		if v == Vector2.ZERO:
			continue
		if not bool(t.halten):
			v *= exp(-dt * 7.0)
		var unten := maxf(0.0, float(t.hoehe) - ansicht(t).y)
		var neu := clampf(float(t.sy) + v.y * dt, 0.0, unten)
		var am_rand := (neu <= 0.0 and v.y < 0.0) or (neu >= unten and v.y > 0.0)
		t.sy = neu
		t.takt = int(t.takt) + 1
		var steht := v.length() < 4.0 or (am_rand and not bool(t.halten))
		t.v = Vector2.ZERO if steht else v
		if steht or (int(t.takt) % 3 == 0 and absf(neu - float(t.get("gemeldet", -1.0))) >= 1.0):
			t.gemeldet = neu
			_karte(id)


## Zum Zeichnen: Blöcke, Rollstand, Zoom, Felder (nur Vorführung).
func seite(tab: int) -> Dictionary:
	var t := _tab(tab)
	if t.is_empty():
		return {}
	return { "url": t.url, "titel": t.titel, "sy": t.sy, "ansicht": ansicht(t), "hoehe": t.hoehe, "bloecke": t.bloecke, "felder": t.felder,
		"video": t.video }
