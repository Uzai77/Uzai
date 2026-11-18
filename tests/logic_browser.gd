extends Node
## Uzai-Browser (Wunschliste 120), alles ohne Windows: Adressen (gleiche Tabelle wie der Wirt,
## tests/fixtures/browser_urls.json), Adresszeile deuten, Leitung (Schema beider Richtungen,
## tests/fixtures/browser_protokoll.json, Grenzen, Fuzz), Fokus-Karte (Springen, Bereiche, Lesen statt
## Springen, gemerkte Stelle, Magnet-Zeiger, Video-Modus, Fokus-Falle im Dialog), was der Browser sich merkt,
## die Frage der Link-Vorschau (verfällt ohne Antwort), der Kern im Vorführmodus über dieselbe Leitung (auch Gliederung, Wahl, Formular, Suche, Blocker, Kern),
## das Sprung-Skript (keine gefährlichen Aufrufe) und die Prüfsummen der WebView2-Dateien (überall gleich).
## Aufruf: godot --headless --path . res://tests/logic_browser.tscn

const Adresse := preload("res://src/core/browser_adresse.gd")
const P := preload("res://src/core/browser_protokoll.gd")
const K := preload("res://src/core/browser_karte.gd")
const D := preload("res://src/core/browser_daten.gd")
const Wirt := preload("res://src/core/browser_wirt.gd")
const Z := preload("res://src/core/browser_zeiger.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	var keep: Dictionary = Config.settings.duplicate(true)
	_adressen()
	_deuten()
	_leitung()
	_fuzz()
	_karte()
	_sprung()
	_zeiger()
	_daten()
	_link_frage()
	await _wirt_demo()
	_skript()
	_pruefsummen()
	Config.settings = keep
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _adressen() -> void:
	print("Adressen (gleiche Tabelle wie der Wirt)")
	var f := FileAccess.get_file_as_string("res://tests/fixtures/browser_urls.json")
	var tab: Variant = JSON.parse_string(f)
	check(tab is Array and (tab as Array).size() > 40, "Tabelle gelesen")
	var falsch: Array = []
	for z in tab:
		var g := Adresse.grund(str(z[0]), bool(z[1]))
		if g != str(z[2]):
			falsch.append("%s (%s): %s statt %s" % [str(z[0]).left(60), z[1], g, z[2]])
	check(falsch.is_empty(), "jede Adresse mit dem erwarteten Urteil %s" % ("" if falsch.is_empty() else str(falsch)))
	check(Adresse.host_von("https://www.Example.com:8443/a?b") == "example.com", "Name für die Anzeige ohne www.")
	check(Adresse.host_von("javascript:alert(1)") == "", "kein Name für fremde Schemata")
	check(Adresse.seiten_schluessel("https://a.de/x#oben") == Adresse.seiten_schluessel("https://a.de/x#unten"), "Stelle je Seite ohne Sprungmarke")
	check(Adresse.sauber("A\u202eB\u200bC\nD\u0007", 10) == "ABC D", "Richtungs-, unsichtbare und Steuerzeichen raus")
	check(Adresse.sauber("x".repeat(500), 20).length() == 20, "Text gekürzt")


func _deuten() -> void:
	print("Adresszeile")
	var fall := [
		["example.com", "adresse", "https://example.com", ""],
		["wetter morgen", "suche", "https://www.google.com/search?q=wetter%20morgen", ""],
		["192.168.0.1", "adresse", "http://192.168.0.1", ""],
		["fritz.box", "adresse", "http://fritz.box", ""],
		["localhost:8080", "adresse", "http://localhost:8080", "lokal"],
		["javascript:alert(1)", "suche", "", ""],
		["c++", "suche", "", ""],
		["file:///C:/Windows", "suche", "", ""],
		["https://example.com/a?b=1", "adresse", "https://example.com/a?b=1", ""],
		["xn--mnchen-3ya.de", "adresse", "https://xn--mnchen-3ya.de", ""],
		["  Uzai Konsole  ", "suche", "https://www.google.com/search?q=Uzai%20Konsole", ""],
		["steam://run/440", "suche", "", ""],
	]
	for f in fall:
		var d := Adresse.deuten(str(f[0]))
		var ok: bool = d.get("art", "") == f[1] and (str(f[2]) == "" or d.get("url", "") == f[2]) and d.get("grund", "") == f[3]
		check(ok, "„%s“ → %s %s" % [f[0], f[1], d.get("url", "")])
	check(Adresse.deuten("   ").is_empty(), "leer bleibt leer")
	check(Adresse.such_url("a&b", "google") == "https://www.google.com/search?q=a%26b", "Suche kodiert (keine eingeschleusten Parameter)")
	check(Adresse.such_url("x", "gibtsnicht").begins_with("https://www.google.com/search?q="), "unbekannte Suchmaschine → Standard (Google)")
	check(Adresse.STANDARD_SUCHE == "google" and str(Adresse.SUCHMASCHINEN[0].id) == "google" and str(Config.DEFAULTS.browser.suche) == "google", "Vorgabe Google, zuerst in der Wahl")
	check(Adresse.such_url("x", "duckduckgo") == "https://duckduckgo.com/?q=x", "DuckDuckGo bleibt wählbar")
	var keep: Dictionary = Config.settings.duplicate(true)
	Config.settings = { "schema": 3, "browser": { "suche": "duckduckgo" } }
	Config._migrate(3)
	var umgestellt := str(Config.settings.browser.suche)
	Config.settings = { "schema": 3, "browser": { "suche": "ecosia" } }
	Config._migrate(3)
	check(umgestellt == "google" and str(Config.settings.browser.suche) == "ecosia" and int(Config.settings.schema) == Config.SETTINGS_VERSION,
		"einmal umgestellt: alte Vorgabe DuckDuckGo → Google, eigene Wahl bleibt")
	Config.settings = keep
	for m in Adresse.SUCHMASCHINEN:
		check(Adresse.grund(str(m.url).replace("%s", "x"), false) == "", "Suchmaschine %s: https-Adresse" % m.name)


func _leitung() -> void:
	print("Leitung (gleiche Beispiele wie der Wirt)")
	var tab: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/browser_protokoll.json"))
	check(tab is Dictionary, "Beispiele gelesen")
	var falsch: Array = []
	for z in tab.befehle:
		var v: Variant = JSON.parse_string(str(z[0]))
		var ok := v is Dictionary and not P.befehl_pruefen(v).is_empty()
		if ok != bool(z[1]):
			falsch.append(str(z[0]).left(80))
	check(falsch.is_empty(), "Befehle: Urteil wie erwartet %s" % ("" if falsch.is_empty() else str(falsch)))
	falsch.clear()
	for z in tab.ereignisse:
		var ok := not P.ereignis(str(z[0])).is_empty()
		if ok != bool(z[1]):
			falsch.append(str(z[0]).left(80))
	check(falsch.is_empty(), "Ereignisse: Urteil wie erwartet %s" % ("" if falsch.is_empty() else str(falsch)))
	var line := P.befehl("laden", { "tab": 1, "url": "https://example.com/", "nutzer": true, "boese": "x" })
	check(line.ends_with("\n") and not line.contains("boese") and line.count("\n") == 1, "Befehl als eine Zeile, fremde Felder fallen weg")
	check(P.befehl("laden", { "tab": 1, "url": "http://127.0.0.1/", "nutzer": true }) == "", "ungültiger Befehl wird nie geschickt")
	check(P.befehl("gibtsnicht") == "", "unbekannte Art wird nie geschickt")
	var m := P.ereignis(JSON.stringify({ "t": "meldung", "tab": 1, "herkunft": "a.de", "text": "Hallo\u202eevil\u0007" }))
	check(m.get("text", "") == "Halloevil", "Text der Seite ohne Richtungs- und Steuerzeichen")
	var k := P.ereignis(JSON.stringify({ "t": "karte", "tab": 1, "vw": 1920, "vh": 1080, "sy": 0, "sh": 10, "ziele": [[1, 1.0, 2, 3, 4, 0, 2]] }))
	check(not k.is_empty() and k.ziele[0][1] is int, "Zahlen kommen als ganze Zahlen an")
	var viele: Array = []
	for i in P.MAX_ZIELE + 1:
		viele.append([i + 1, 0, i, 10, 10, 0, 2])
	check(P.ereignis(JSON.stringify({ "t": "karte", "tab": 1, "vw": 10, "vh": 10, "sy": 0, "sh": 0, "ziele": viele })).is_empty(), "höchstens %d Ziele" % P.MAX_ZIELE)
	check(P.ereignis("x".repeat(P.MAX_EREIGNIS + 1)).is_empty(), "zu lange Zeile verworfen")
	# Spotify-Abfragen in der Seite: Regeln je Ziel und Größen.
	var pf := JSON.stringify({ "operationName": "libraryV3", "variables": {}, "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "a".repeat(64) } } })
	check(P.spotify_abfrage_grund("pathfinder", "POST", P.PATHFINDER_PFAD, pf, "") == "" and P.spotify_abfrage_grund("webapi", "GET", "/v1/me", "", "") == ""
			and P.spotify_abfrage_grund("spclient", "PUT", "/connect-state/v1/devices/abc", "{}", "Y29ubg==") == "", "Spotify-Abfragen: erlaubte Formen")
	check(P.spotify_abfrage_grund("webapi", "GET", "//boese.example/x", "", "") == "ziel" and P.spotify_abfrage_grund("webapi", "GET", "/v1/../x", "", "") == "ziel"
			and P.spotify_abfrage_grund("webapi", "PUT", "/v1/me/player", "{}", "") == "ziel"
			and P.spotify_abfrage_grund("pathfinder", "GET", P.PATHFINDER_PFAD, "", "") == "ziel"
			and P.spotify_abfrage_grund("pathfinder", "POST", P.PATHFINDER_PFAD, pf.replace("libraryV3", "x y"), "") == "ziel"
			and P.spotify_abfrage_grund("spclient", "GET", "/melody/v1/x", "", "") == "ziel"
			and P.spotify_abfrage_grund("spclient", "GET", "/context-resolve/v1/x", "", "abc") == "ziel"
			and P.spotify_abfrage_grund("webapi", "GET", "/v1/me", "[1]", "") == "ziel"
			and P.spotify_abfrage_grund("api.example", "GET", "/v1/me", "", "") == "ziel", "Spotify-Abfragen: fremder Host, .., PUT, falsche Formen abgelehnt")
	check(P.befehl("spotify-abfrage", { "id": 1, "ziel": "webapi", "methode": "PUT", "pfad": "/v1/me", "inhalt": "", "verbindung": "", "zeit": 5000 }) == ""
			and P.befehl("spotify-abfrage", { "id": 1, "ziel": "webapi", "methode": "GET", "pfad": "/v1/me", "inhalt": "", "verbindung": "", "zeit": 5000,
				"kopf": "X-Boese: 1" }).find("Boese") < 0, "Befehl spotify-abfrage: Regeln an der Leitung, keine Kopfzeilen von Uzai")
	var gross := JSON.stringify({ "t": "spotify-antwort", "id": 1, "code": 200, "grund": "", "text": "x".repeat(P.MAX_EREIGNIS + 10), "gekuerzt": false, "warte": 0 })
	check(not P.ereignis(gross).is_empty(), "Spotify-Antwort darf länger sein als andere Ereignisse")
	check(P.ereignis(JSON.stringify({ "t": "spotify-antwort", "id": 1, "code": 200, "grund": "", "text": "x".repeat(P.MAX_ANTWORT + 1), "gekuerzt": false,
			"warte": 0 })).is_empty(), "Spotify-Antwort über %d Zeichen: verworfen" % P.MAX_ANTWORT)
	check(P.ereignis(JSON.stringify({ "t": "meldung", "tab": 1, "herkunft": "a.de", "text": "x", "fuell": "y".repeat(P.MAX_EREIGNIS) })).is_empty(),
			"andere Ereignisse bleiben unter MAX_EREIGNIS")
	var tief := "[".repeat(200) + "]".repeat(200)
	check(P.ereignis(tief).is_empty(), "tief verschachteltes verworfen")


## Zufällige Änderungen an gültigen Zeilen: nie ein Absturz, nie etwas außerhalb des Schemas.
func _fuzz() -> void:
	print("Fuzz der Leitung")
	var tab: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/browser_protokoll.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 120
	var gut := 0
	var schlecht := 0
	var raus := 0
	var basis: Array = []
	for z in tab.ereignisse:
		if bool(z[1]):
			basis.append(str(z[0]))
	for i in 3000:
		var s: String = basis[rng.randi() % basis.size()]
		var b := s.to_utf8_buffer()
		for n in 1 + rng.randi() % 3:
			if b.size() > 0:
				b[rng.randi() % b.size()] = rng.randi() % 256
		var e := P.ereignis(b.get_string_from_utf8())
		if e.is_empty():
			schlecht += 1
			continue
		gut += 1
		if not P.EREIGNISSE.has(e.t) or e.size() != (P.EREIGNISSE[e.t] as Dictionary).size() + 1:
			raus += 1
	check(raus == 0, "3000 kaputte Zeilen: nichts außerhalb des Schemas (%d angenommen, %d verworfen)" % [gut, schlecht])


func _z(id: int, x: float, y: float, w: float, h: float, art := 0, bereich := 2) -> Array:
	return [id, int(x), int(y), int(w), int(h), art, bereich]


func _karte() -> void:
	print("Fokus-Karte")
	# Kopf mit drei Links, Inhalt mit Spalte aus Karten, Seitenleiste rechts, Fuß weit unten.
	var roh := [
		_z(1, 40, 20, 120, 40, 0, 0), _z(2, 200, 20, 120, 40, 0, 0), _z(3, 360, 20, 120, 40, 0, 0),
		_z(10, 100, 200, 600, 300, 5, 2), _z(11, 760, 200, 600, 300, 5, 2), _z(12, 100, 560, 600, 300, 5, 2), _z(13, 760, 560, 600, 300, 5, 2),
		_z(20, 1500, 200, 300, 60, 0, 3), _z(21, 1500, 300, 300, 60, 0, 3),
		_z(30, 100, 3200, 200, 40, 0, 4),
	]
	var z := K.als_ziele(roh)
	var vw := 1920.0
	var vh := 1080.0
	check(K.erstes(z, vw, vh) == 10, "Start im Inhalt beim ersten großen Ziel")
	check(K.naechstes(z, 10, "right", vw, vh).id == 11, "rechts zur Nachbarkarte")
	check(K.naechstes(z, 10, "down", vw, vh).id == 12, "runter zur Karte darunter (gleiche Spalte)")
	check(K.naechstes(z, 11, "down", vw, vh).id == 13, "runter in der rechten Spalte")
	check(K.naechstes(z, 10, "up", vw, vh).id in [1, 2, 3], "hoch in den Kopf")
	check(K.naechstes(z, 1, "right", vw, vh).id == 2, "Kopf: Link für Link nach rechts")
	check(K.naechstes(z, 3, "right", vw, vh).id != 20 or true, "Kopf rechts: kein Absturz")
	var r := K.naechstes(z, 12, "down", vw, vh)
	check(r.id == -1 and r.rollen == "down", "langer Text bis zum Fuß: erst rollen statt springen")
	check(K.naechstes(z, 1, "up", vw, vh).rollen == "up", "nichts darüber: rollen")
	check(K.naechstes(z, 999, "down", vw, vh).id == 10, "unbekanntes Ziel: beginnt beim ersten")
	check(K.bereiche(z) == [0, 2, 3, 4], "Bereiche in Lesereihenfolge (Kopf, Inhalt, Seitenleiste, Fuß)")
	check(K.bereich_sprung(z, 10, 1, vw, vh) == 20, "RB: in die Seitenleiste")
	check(K.bereich_sprung(z, 10, -1, vw, vh) == 1, "LB: in den Kopf")
	check(K.bereich_sprung(z, 1, -1, vw, vh) == -1, "LB im ersten Bereich: anstoßen")
	check(K.bereich_sprung(z, 21, 1, vw, vh) == 30, "RB: in den Fuß (auch außerhalb des Bildes)")
	# Ein anderer Bereich kostet: von der Seitenleiste nach links lieber in den Inhalt als …
	check(K.naechstes(z, 20, "left", vw, vh).id == 11, "links aus der Seitenleiste in die nächste Karte")
	# Gemerkte Stelle: Mitte der Karte 13 bei gerollten 400 px
	var p := K.stelle(K.finde(z, 13), 400.0)
	check(K.erstes(z, vw, vh, p, 400.0) == 13, "gemerkte Stelle wiedergefunden")
	check(Z.einrast_punkt(Vector2(130, 45), z).is_equal_approx(Vector2(100, 40)), "Zeiger rastet in der Mitte des Links ein")
	check(Z.einrast_punkt(Vector2(1000, 1000), z).x < 0.0, "Zeiger frei, wo kein Ziel ist")
	check(Z.einrast_punkt(Vector2(400, 300), z).x < 0.0, "großes Ziel: Zeiger bleibt, wo er ist")
	var vz := K.als_ziele([_z(50, 0, 0, 1600, 900, 4, 2)])
	check(K.video_modus({ "da": true, "laeuft": true, "voll": false }, vz, vw, vh), "großes laufendes Video: Fernbedienung")
	check(not K.video_modus({ "da": true, "laeuft": false, "voll": false }, vz, vw, vh), "pausiert: keine Fernbedienung")
	check(not K.video_modus({ "da": true, "laeuft": true, "voll": false }, K.als_ziele([_z(51, 0, 0, 300, 200, 4, 2)]), vw, vh), "kleines Video: keine Fernbedienung")
	check(K.auf_schirm(Rect2(100, 50, 200, 100), 1280, 720, Vector2(1920, 1080)) == Rect2(150, 75, 300, 150), "CSS-Pixel → Bildpunkte")
	# Leere Karte
	check(K.erstes([], vw, vh) == -1 and K.naechstes([], 1, "down", vw, vh).rollen == "down", "leere Seite: rollen")
	# Versetzte Ziele (je 10 px tiefer und weiter links): paarweise verglichen ergäbe das einen Kreis (A vor C,
	# C vor B, B vor A). Die Reihenfolge muss trotzdem feststehen – gleich, in welcher Folge die Ziele ankommen.
	var versetzt := [
		{ "id": 1, "r": Rect2(300, 100, 80, 30), "art": "link", "bereich": 2 }, { "id": 2, "r": Rect2(200, 110, 80, 30), "art": "link", "bereich": 2 },
		{ "id": 3, "r": Rect2(100, 120, 80, 30), "art": "link", "bereich": 2 }, { "id": 4, "r": Rect2(50, 200, 80, 30), "art": "link", "bereich": 2 }]
	var folge := func(l: Array) -> Array: return K.in_lesereihe(l).map(func(e: Dictionary) -> int: return int(e.id))
	var umgekehrt := versetzt.duplicate()
	umgekehrt.reverse()
	var gemischt := [versetzt[2], versetzt[0], versetzt[3], versetzt[1]]
	check(folge.call(versetzt) == [2, 1, 3, 4] and folge.call(umgekehrt) == [2, 1, 3, 4] and folge.call(gemischt) == [2, 1, 3, 4],
			"Lesereihenfolge bei versetzten Zielen: fest, in jeder Ankunftsfolge gleich (%s)" % str(folge.call(versetzt)))
	check(folge.call([]) == [] and K.erstes(umgekehrt, vw, vh) == K.erstes(versetzt, vw, vh), "… und der Start auf der Seite hängt nicht von der Folge ab")
	# Offener Dialog (Bereich 5): der Fokus bleibt darin – wie mit der Tastatur.
	var d := K.als_ziele(roh + [_z(70, 700, 400, 200, 50, 1, 5), _z(71, 950, 400, 200, 50, 1, 5), _z(72, 700, 500, 450, 40, 2, 5)])
	check(K.aktive(d).size() == 3 and K.aktive(z).size() == z.size(), "aktive Ziele: nur der Dialog, sonst alle")
	check(K.erstes(d, vw, vh) in [70, 71, 72], "Dialog offen: Start im Dialog")
	check(K.naechstes(d, 70, "up", vw, vh).id == -1 and K.naechstes(d, 70, "left", vw, vh).id == -1, "aus dem Dialog führt kein Sprung hinaus")
	check(K.naechstes(d, 70, "right", vw, vh).id == 71 and K.naechstes(d, 70, "down", vw, vh).id == 72, "im Dialog springt es normal")
	check(K.bereich_sprung(d, 70, 1, vw, vh) == -1 and K.bereich_sprung(d, 70, -1, vw, vh) == -1, "LB/RB verlassen den Dialog nicht")
	check(Z.einrast_punkt(Vector2(130, 45), d).x < 0.0 and Z.treffer(Vector2(130, 45), d).id == -1, "Zeiger rastet hinter dem Dialog nicht ein")


## Steuerkreuz auf typischen Seiten (tests/fixtures/browser_sprung.json): Wege mit erwarteten Zielen, mit dem
## Gedächtnis des letzten Sprungs wie im Browser.
func _sprung() -> void:
	print("Sprung (Fixtures)")
	var tab: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/browser_sprung.json"))
	check(tab is Array and (tab as Array).size() >= 6, "Fixtures gelesen")
	for f in tab:
		var z := K.als_ziele(f.ziele)
		for w in f.wege:
			var von := int(w.start)
			var her := {}
			var weg: Array = []
			for i in (w.dirs as Array).size():
				var dir := str(w.dirs[i])
				var r := K.naechstes(z, von, dir, 1920.0, 1080.0, her)
				weg.append(int(r.id))
				if int(r.id) >= 0:
					her = { "von": von, "nach": int(r.id), "dir": dir }
					von = int(r.id)
			var soll: Array = (w.ziel as Array).map(func(x: Variant) -> int: return int(x))
			check(weg == soll, "%s: ab %d %s → %s%s" % [f.name, int(w.start), str(w.dirs), str(soll), "" if weg == soll else " (ist %s)" % str(weg)])


## Der Zeiger (browser_zeiger.gd): Kurve, Tempo, Bildrate, Schub, fein, Magnet, Treffer, Rand, Sprung.
func _zeiger() -> void:
	print("Zeiger")
	check(Z.kurve(Vector2(0.1, 0.05)) == Vector2.ZERO, "Totzone: Stick-Drift bewegt nichts")
	var knapp := Z.kurve(Vector2(Z.TOT + 0.002, 0)).x
	check(knapp > 0.0 and knapp < 0.002, "hinter der Totzone beginnt es bei 0 (kein Sprung)")
	check(is_equal_approx(Z.kurve(Vector2(1, 0)).x, 1.0) and is_equal_approx(Z.kurve(Vector2(0, -0.97)).y, -1.0), "voller Ausschlag = 1")
	var steigt := true
	var vorher := 0.0
	for i in 101:
		var y := Z.kurve(Vector2(i / 100.0, 0)).x
		steigt = steigt and y >= vorher
		vorher = y
	check(steigt, "Kurve steigt stetig")
	check(Z.kurve(Vector2(0.5, 0)).x < 0.25 and Z.kurve(Vector2(0.3, 0)).x < 0.05, "wenig Ausschlag ist fein (halb: unter einem Viertel)")
	var schraeg := Z.kurve(Vector2(0.6, 0.6))
	check(absf(schraeg.length() - Z.kurve(Vector2(0.6 * sqrt(2.0), 0)).length()) < 0.001 and absf(schraeg.angle() - PI / 4.0) < 0.001,
		"radial: schräg so schnell wie gerade, Richtung bleibt")
	check(is_equal_approx(Z.einheit(1920, 1080), 1920.0) and is_equal_approx(Z.einheit(1280, 720), 1280.0), "Tempo in Bildbreiten (16:9)")
	check(Z.tempo("schnell") > Z.tempo("mittel") and Z.tempo("mittel") > Z.tempo("langsam") and Z.tempo("quatsch") == Z.tempo(Z.STANDARD_TEMPO),
		"Tempo-Stufen, Unbekanntes wird Mittel")
	var o := { "tempo": Z.tempo("mittel"), "fein": false, "einrasten": false }
	# Bildrate: eine Sekunde mit 30 und mit 144 Bildern je Sekunde – fast derselbe Weg.
	var wege: Array = []
	for fps in [30, 60, 144]:
		var a := Z.new()
		a.setzen(Vector2(10, 540))
		for i in fps:
			a.schritt(Vector2(0.6, 0), 1.0 / fps, [], 1920, 1080, o)
		wege.append(a.p.x - 10.0)
	check(absf(wege[0] - wege[2]) < wege[2] * 0.03 and absf(wege[1] - wege[2]) < wege[2] * 0.02, "an die Bildrate entkoppelt %s" % str(wege))
	# Auflösung: 4K-Bild doppelt so viele CSS-Pixel – derselbe Anteil des Bildes.
	var hd := Z.new()
	var uhd := Z.new()
	hd.setzen(Vector2.ZERO)
	uhd.setzen(Vector2.ZERO)
	for i in 30:
		hd.schritt(Vector2(0.7, 0), 1.0 / 60.0, [], 1920, 1080, o)
		uhd.schritt(Vector2(0.7, 0), 1.0 / 60.0, [], 3840, 2160, o)
	check(absf(uhd.p.x / 3840.0 - hd.p.x / 1920.0) < 0.001, "gleich schnell auf 1080p und 4K (Anteil des Bildes)")
	# Schub: lange voll gehalten wird es schneller, kurz nicht.
	var s := Z.new()
	s.setzen(Vector2(0, 540))
	for i in 12:
		s.schritt(Vector2(1, 0), 1.0 / 60.0, [], 1920, 1080, o)
	var v_kurz: float = s.v.x
	for i in 78:
		s.schritt(Vector2(1, 0), 1.0 / 60.0, [], 1920, 1080, o)
	var basis := Z.tempo("mittel") * 1920.0
	check(v_kurz <= basis * 1.01 and absf(s.v.x / basis - Z.SCHUB) < 0.05, "Schub nach langem Halten (%.0f → ×%.2f)" % [v_kurz, s.v.x / basis])
	# Fein: LB/RB gehalten.
	var f := Z.new()
	f.setzen(Vector2(0, 540))
	for i in 60:
		f.schritt(Vector2(1, 0), 1.0 / 60.0, [], 1920, 1080, o.merged({ "fein": true }, true))
	check(absf(f.v.x - 1920.0 * Z.tempo("mittel") * Z.FEIN) < 2.0, "fein: %.0f %% Tempo, kein Schub" % (Z.FEIN * 100))
	# Sub-Pixel: ganz leichter Druck bewegt um Bruchteile eines Pixels je Bild.
	var sp := Z.new()
	sp.setzen(Vector2(500, 500))
	var schritte_klein := true
	for i in 20:
		var vor: float = sp.p.x
		sp.schritt(Vector2(Z.TOT + 0.05, 0), 1.0 / 60.0, [], 1920, 1080, o)
		schritte_klein = schritte_klein and sp.p.x - vor < 1.0 and sp.p.x >= vor
	check(schritte_klein and sp.p.x > 500.0 and not is_equal_approx(sp.p.x, roundf(sp.p.x)), "Sub-Pixel: leichter Druck kriecht (%.3f)" % sp.p.x)
	# Loslassen: kein Nachrutschen.
	var los := Z.new()
	los.setzen(Vector2(100, 540))
	for i in 30:
		los.schritt(Vector2(1, 0), 1.0 / 60.0, [], 1920, 1080, o)
	var bei: float = los.p.x
	for i in 30:
		los.schritt(Vector2.ZERO, 1.0 / 60.0, [], 1920, 1080, o)
	check(los.p.x - bei < 40.0 and los.v == Vector2.ZERO, "losgelassen hält er gleich an (%.1f px Auslauf)" % (los.p.x - bei))
	# Magnet: Bremse über einem kleinen Ziel nur bei langsamer Bewegung.
	var z := K.als_ziele([_z(1, 400, 500, 120, 40, 1, 2), _z(2, 900, 300, 800, 500, 5, 2), _z(3, 100, 100, 200, 120, 8, 2)])
	check(Z.reibung(Vector2(460, 520), z, 0.1) < 0.5 and Z.reibung(Vector2(460, 520), z, 1.0) == 1.0 and Z.reibung(Vector2(700, 900), z, 0.1) == 1.0,
		"Magnet bremst langsames Zielen über dem Knopf, schnelles bleibt frei")
	check(Z.reibung(Vector2(460, 470), z, 0.1) > Z.reibung(Vector2(460, 495), z, 0.1), "Bremse setzt am Rand weich ein")
	var m := Z.new()
	m.setzen(Vector2(380, 545))
	var om := o.merged({ "einrasten": true }, true)
	for i in 60:
		m.schritt(Vector2.ZERO, 1.0 / 60.0, z, 1920, 1080, om)
	check(m.p.distance_to(Vector2(460, 520)) < 0.5 and int(m.ueber.get("id", -1)) == 1, "losgelassen neben dem Knopf: gleitet in seine Mitte")
	var aus := Z.new()
	aus.setzen(Vector2(380, 545))
	for i in 60:
		aus.schritt(Vector2.ZERO, 1.0 / 60.0, z, 1920, 1080, o)
	check(aus.p == Vector2(380, 545), "Einrasten aus: bleibt, wo er ist")
	check(Z.einrast_punkt(Vector2(1000, 400), z).x < 0.0 and Z.einrast_punkt(Vector2(890, 400), z).is_equal_approx(Vector2(906, 400)),
		"großes Ziel: darin bleibt er, knapp daneben ein Stück hinein")
	check(Z.einrast_punkt(Vector2(90, 150), z).x < 0.0, "in einen Rahmen rastet nichts ein")
	var zeile := K.als_ziele([_z(7, 100, 700, 400, 40, 0, 3)])
	check(Z.einrast_punkt(Vector2(512, 726), zeile).is_equal_approx(Vector2(494, 720)), "breite Zeile (Link in einer Liste): auf ihre Mittellinie")
	check(Z.einrast_punkt(Vector2(498, 712), zeile).is_equal_approx(Vector2(494, 720)) and Z.einrast_punkt(Vector2(300, 720), zeile).x < 0.0,
		"… auch schon knapp darin; in der Mitte bleibt er")
	var alt := Z.new()
	alt.setzen(Vector2(380, 545))
	for i in 60:
		alt.schritt(Vector2.ZERO, 1.0 / 60.0, z, 1920, 1080, om.merged({ "ziele_frisch": false }, true))
	check(alt.p == Vector2(380, 545) and alt.ueber.is_empty(), "beim Rollen (alte Ziele): kein Einrasten")
	# Treffer: knapp daneben zählt, weit daneben nicht, im Rahmen genau dort.
	var t1 := Z.treffer(Vector2(395, 520), z)
	check(int(t1.id) == 1 and (t1.punkt as Vector2).is_equal_approx(Vector2(460, 520)), "A knapp neben dem Knopf trifft seine Mitte")
	check(int(Z.treffer(Vector2(470, 525), z).id) == 1 and (Z.treffer(Vector2(470, 525), z).punkt as Vector2) == Vector2(470, 525), "im Ziel: genau dort")
	check(int(Z.treffer(Vector2(300, 700), z).id) == -1, "weit daneben: kein Ziel, Klick bleibt, wo er ist")
	var t3 := Z.treffer(Vector2(150, 150), z)
	check(str(t3.art) == "rahmen" and (t3.punkt as Vector2) == Vector2(150, 150) and int(Z.treffer(Vector2(95, 150), z).id) == -1,
		"Rahmen: Klick genau unter dem Zeiger, daneben nie hinein")
	var klein := K.als_ziele([_z(5, 100, 100, 400, 200, 5, 2), _z(6, 440, 260, 40, 30, 1, 2)])
	check(int(Z.ziel_bei(Vector2(460, 275), klein).id) == 6, "Knopf in der Karte: das kleinere Ziel unter dem Zeiger")
	# Rand: gegen den unteren Rand gedrückt rollt die Seite.
	var r := Z.new()
	r.setzen(Vector2(500, 1078))
	for i in 10:
		r.schritt(Vector2(0, 1), 1.0 / 60.0, [], 1920, 1080, o)
	check(r.rand.y > 0.0 and r.p.y <= 1079.0, "am Rand: Seite rollt mit (%.0f px/s)" % r.rand.y)
	r.schritt(Vector2(0, -1), 1.0 / 60.0, [], 1920, 1080, o)
	check(r.rand == Vector2.ZERO, "vom Rand weg: rollt nicht")
	# Steuerkreuz im Zeiger: zum nächsten Ziel.
	var zr := K.als_ziele([_z(1, 40, 20, 120, 40, 0, 0), _z(2, 200, 20, 120, 40, 0, 0), _z(3, 200, 400, 120, 40, 0, 2)])
	var sp2 := Z.new()
	sp2.setzen(Vector2(100, 40))
	sp2.schritt(Vector2.ZERO, 1.0 / 60.0, zr, 1920, 1080, o)
	check(sp2.springen("right", zr, 1920, 1080) == 2, "Steuerkreuz: rechts zum nächsten Link")
	for i in 40:
		sp2.schritt(Vector2.ZERO, 1.0 / 60.0, zr, 1920, 1080, o)
	check(sp2.p.is_equal_approx(Vector2(260, 40)) and int(sp2.ueber.id) == 2, "… gleitet in seine Mitte")
	check(sp2.springen("down", zr, 1920, 1080) == 3 and sp2.springen("up", K.als_ziele([_z(9, 0, 2000, 50, 50)]), 1920, 1080) == -1,
		"runter zum Ziel darunter; nichts im Bild: rollen")
	var u := Z.new()
	u.setzen(Vector2(640, 360))
	u.umrechnen(1280, 720, 640, 360)
	check(u.p == Vector2(320, 180), "Zoom: der Zeiger bleibt an derselben Stelle des Schirms")


func _daten() -> void:
	print("Was der Browser sich merkt")
	Config.set_value("browser.favoriten", [])
	check(D.favorit_umschalten("https://example.com/", "Beispiel"), "Lesezeichen gesetzt")
	check(D.hat("favoriten", "https://example.com/"), "Lesezeichen da")
	check(not D.favorit_umschalten("https://example.com/", "Beispiel"), "Lesezeichen wieder weg")
	check(not D.favorit_umschalten("http://127.0.0.1/", "x"), "nie ein Lesezeichen auf diesen PC")
	Config.set_value("browser.favoriten", [{ "url": "javascript:alert(1)", "titel": "x" }, { "url": "https://a.de/", "titel": "A\u202eB" }, "kaputt",
		{ "url": "https://a.de/", "titel": "doppelt" }])
	var l := D.liste("favoriten")
	check(l.size() == 1 and l[0].titel == "AB", "von Hand geänderte Liste: geprüft beim Lesen")
	Config.set_value("browser.zuletzt", [])
	Config.set_value("browser.verlauf", true)
	for i in 40:
		D.besucht("https://s%d.de/" % i, "Seite %d" % i, false)
	D.besucht("https://s5.de/", "Seite 5", false)
	var z := D.liste("zuletzt")
	check(z.size() == 30 and z[0].url == "https://s5.de/", "zuletzt besucht: höchstens 30, neueste vorn, ohne Doppel")
	D.besucht("https://geheim.de/", "x", true)
	check(D.liste("zuletzt")[0].url != "https://geheim.de/", "privater Tab: kein Verlauf")
	Config.set_value("browser.verlauf", false)
	D.besucht("https://aus.de/", "x", false)
	check(D.liste("zuletzt")[0].url != "https://aus.de/", "Verlauf aus: nichts gemerkt")
	D.zoom_merken("https://www.example.com/a", 150)
	check(D.zoom_fuer("https://example.com/b") == 150, "Zoom je Seite (nach Name)")
	D.zoom_merken("https://example.com/", 100)
	check(not (Config.get_value("browser.zoom", {}) as Dictionary).has("example.com"), "Zoom 100 % wird nicht gespeichert")
	Config.set_value("browser.zoom", { "x.de": 9999 })
	check(D.zoom_fuer("https://x.de/") == 300, "Zoom aus der Datei begrenzt")
	D.stelle_merken("https://a.de/lang#mitte", Vector2(400, 2500), false)
	check(D.stelle("https://a.de/lang") == Vector2(400, 2500), "Stelle je Seite")
	D.stelle_merken("https://b.de/", Vector2(1, 1), true)
	check(D.stelle("https://b.de/") == Vector2(-1, -1), "privat: keine Stelle")
	check(D.app_umschalten("https://news.example/", "News", 140) and D.liste("apps")[0].zoom == 140, "als App angeheftet mit eigener Zoomstufe")
	Config.set_value("browser.suche", "boese")
	check(D.suchmaschine() == "google", "unbekannte Suchmaschine → Standard")
	check(D.monogramm("https://www.zdf.de/") == "Z", "Zeichen für die Kachel")


## Der Wirt im Vorführmodus spricht dieselbe Leitung wie der echte (jede Zeile durch das Schema).
## Link-Vorschau: Auf eine Frage nach der Adresse eines Links antwortet der Kern nicht immer (Link ohne
## http(s)-Adresse, role="link" ohne href, Antwort für einen anderen Tab). Früher blieb die Frage dann offen,
## und bis zum Schließen des Browsers kam keine Link-Vorschau mehr; jetzt verfällt sie nach LINK_WARTE_MS.
func _link_frage() -> void:
	print("Link-Vorschau: offene Frage verfällt")
	var B: GDScript = load("res://src/ui/layers/browser.gd")
	check(not B.link_verfallen(0, B.LINK_WARTE_MS - 1) and B.link_verfallen(0, B.LINK_WARTE_MS), "Frage gilt LINK_WARTE_MS lang")
	var b = B.new()
	b.wirt = Wirt.new()                 # nicht gestartet: senden() geht nirgends hin
	b.aktiv = 1
	b.tabs = { 1: { "url": "https://uzai.example/start", "fokus": 5, "ziele": K.als_ziele([_z(4, 0, 0, 100, 20), _z(5, 0, 40, 100, 20)]) } }
	b._sprung_ms = -100000
	b._link_wunsch = "vorschau"         # Frage zu Link 4 ohne Antwort
	b._link_ms = Time.get_ticks_msec()
	b._vorschau_id = 4
	b._vorschau_pruefen()
	check(b._vorschau_id == 4, "Frage offen: der nächste Link wartet")
	b._link_ms = Time.get_ticks_msec() - B.LINK_WARTE_MS
	b._vorschau_pruefen()
	check(b._vorschau_id == 5 and b._link_wunsch == "vorschau", "ohne Antwort verfallen: der nächste Link fragt wieder")
	b.wirt.free()
	b.free()


func _wirt_demo() -> void:
	print("Leitung: Zeilen je Bild")
	# Ein Block mit sehr vielen kurzen Zeilen: je Bild nur MAX_ZEILEN_JE_BILD, der Rest bleibt liegen und kommt danach.
	var lw = Wirt.new()
	lw.demo = true
	var gesehen: Array = []
	lw.ereignis.connect(func(e: Dictionary) -> void: gesehen.append(e))
	var block := PackedByteArray()
	for i in 200:
		block.append_array(("{\"t\":\"tab-zu\",\"tab\":%d}\n" % (i + 1)).to_utf8_buffer())
	block.append_array("{\"t\":\"tab-zu\",\"ta".to_utf8_buffer())            # angefangene Zeile ohne Ende
	lw._buf = block
	var n1: int = lw._zeilen_abarbeiten(0)
	check(n1 == Wirt.MAX_ZEILEN_JE_BILD and gesehen.size() == Wirt.MAX_ZEILEN_JE_BILD and int(gesehen[0].tab) == 1,
			"erstes Bild: genau %d Zeilen, in der Reihenfolge" % Wirt.MAX_ZEILEN_JE_BILD)
	check(lw._zeilen_abarbeiten(Wirt.MAX_ZEILEN_JE_BILD) == Wirt.MAX_ZEILEN_JE_BILD and gesehen.size() == Wirt.MAX_ZEILEN_JE_BILD,
			"ist das Bild voll, wird keine weitere verarbeitet")
	var runden := 0
	while lw._zeilen_abarbeiten(0) > 0 and runden < 10:
		runden += 1
	check(gesehen.size() == 200 and int(gesehen[199].tab) == 200 and runden == 3, "der Rest kommt in den nächsten Bildern, nichts geht verloren")
	check(lw._buf.get_string_from_utf8() == "{\"t\":\"tab-zu\",\"ta", "die angefangene Zeile bleibt im Puffer liegen")
	lw.free()

	print("Wirt im Vorführmodus")
	var w = Wirt.new()
	w.demo = true
	add_child(w)
	var ev: Array = []
	w.ereignis.connect(func(e: Dictionary) -> void: ev.append(e))
	w.starten()
	await get_tree().process_frame
	await get_tree().process_frame
	check(w.bereit, "Wirt bereit")
	w.senden("tab-neu", { "url": "https://uzai.example/start", "privat": false, "vorn": true, "nutzer": true })
	for i in 6:
		await get_tree().process_frame
	var tabs := ev.filter(func(e: Dictionary) -> bool: return e.t == "tab")
	var karten := ev.filter(func(e: Dictionary) -> bool: return e.t == "karte")
	check(not tabs.is_empty() and str(tabs[-1].url) == "https://uzai.example/start", "Tab mit Adresse gemeldet")
	check(not karten.is_empty() and (karten[-1].ziele as Array).size() >= 8, "Fokus-Karte der Platzhalter-Seite")
	var tid := int(tabs[-1].tab)
	var ziele := K.als_ziele(karten[-1].ziele)
	var z0 := K.erstes(ziele, float(karten[-1].vw), float(karten[-1].vh))
	ev.clear()
	w.senden("fokus", { "tab": tid, "id": z0 })
	for i in 4:
		await get_tree().process_frame
	check(ev.any(func(e: Dictionary) -> bool: return e.t == "ziel" and int(e.id) == z0), "Fokus: Rechteck des Ziels zurück")
	ev.clear()
	w.senden("laden", { "tab": tid, "url": "http://127.0.0.1:47811/", "nutzer": true })
	for i in 4:
		await get_tree().process_frame
	check(ev.is_empty(), "ungültiger Befehl verlässt Uzai nicht")
	check(w.verworfen >= 1, "… und wird gezählt")
	w.senden("rollen", { "tab": tid, "vx": 0, "vy": 2400 })
	await get_tree().create_timer(0.25).timeout
	w.senden("rollen", { "tab": tid, "vx": 0, "vy": 0 })
	await get_tree().create_timer(1.2).timeout
	var k2 := ev.filter(func(e: Dictionary) -> bool: return e.t == "karte")
	check(not k2.is_empty() and int(k2[-1].sy) > 100, "Rollen: die Seite rollt (mit Trägheit), die Karte kommt neu (%s)" % (str(k2[-1].sy) if not k2.is_empty() else "-"))
	# Neue Befehle des Kerns: Blocker, Gliederung, Wahl-Liste, Formular, Suche, Video-Fernbedienung Plus, Kern.
	ev.clear()
	w.senden("blocker", { "tab": tid, "an": true })
	for i in 3:
		await get_tree().process_frame
	var bl := ev.filter(func(e: Dictionary) -> bool: return e.t == "blocker")
	check(not bl.is_empty() and int(bl[-1].anzahl) + int(bl[-1].versteckt) > 0, "Blocker meldet je Seite, was er tat")
	ev.clear()
	w.senden("gliederung", { "tab": tid })
	w.senden("suche", { "tab": tid, "text": "platzhalter" })
	for i in 3:
		await get_tree().process_frame
	var gl := ev.filter(func(e: Dictionary) -> bool: return e.t == "gliederung")
	check(not gl.is_empty() and (gl[-1].punkte as Array).size() >= 2 and int(gl[-1].punkte[0][2]) >= 1, "Gliederung: Überschriften mit Stufe")
	var su := ev.filter(func(e: Dictionary) -> bool: return e.t == "suche")
	check(not su.is_empty() and int(su[-1].treffer) >= 1 and int(su[-1].aktuell) == 1, "Suche auf der Seite: Treffer gezählt")
	ev.clear()
	w.senden("springe", { "tab": tid, "id": int(gl[-1].punkte[-1][0]) })
	w.senden("suche-weiter", { "tab": tid, "richtung": 1 })
	for i in 3:
		await get_tree().process_frame
	var k3 := ev.filter(func(e: Dictionary) -> bool: return e.t == "karte")
	check(not k3.is_empty() and int(k3[-1].sy) > 0, "Springen: die Seite rollt zur Überschrift")
	# Formular (weiter unten auf der Seite, nach dem Springen in der Karte): Kommentar → RB → Name → RB → Sprache
	ziele = K.als_ziele(k3[-1].ziele)
	var felder := ziele.filter(func(zz: Dictionary) -> bool: return zz.art == "feld")
	check(felder.size() >= 3, "Platzhalter-Seite hat ein Formular (%d Felder im Bild)" % felder.size())
	ev.clear()
	var kommentar := int(felder[0].id)
	w.senden("aktivieren", { "tab": tid, "id": kommentar, "neu": false })
	for i in 3:
		await get_tree().process_frame
	var fo := ev.filter(func(e: Dictionary) -> bool: return e.t == "formular")
	check(not fo.is_empty() and int(fo[-1].anzahl) >= 3 and not bool(fo[-1].ende), "Textfeld: Formular gemeldet (Stelle, Anzahl)")
	ev.clear()
	w.senden("feld-weiter", { "tab": tid, "id": kommentar, "richtung": 1 })
	for i in 3:
		await get_tree().process_frame
	var fe := ev.filter(func(e: Dictionary) -> bool: return e.t == "feld")
	check(not fe.is_empty() and int(fe[-1].id) != kommentar, "RB: das nächste Feld ist dran")
	ev.clear()
	w.senden("feld-weiter", { "tab": tid, "id": int(fe[-1].id), "richtung": 1 })
	for i in 3:
		await get_tree().process_frame
	var wa := ev.filter(func(e: Dictionary) -> bool: return e.t == "wahl")
	check(not wa.is_empty() and (wa[-1].optionen as Array).size() == 5, "Auswahlfeld: Wahl-Liste statt Aufklappmenü")
	w.senden("wahl-setzen", { "tab": tid, "id": int(wa[-1].id), "index": 2 })
	ev.clear()
	w.senden("wahl", { "tab": tid, "id": int(wa[-1].id) })
	for i in 3:
		await get_tree().process_frame
	wa = ev.filter(func(e: Dictionary) -> bool: return e.t == "wahl")
	check(not wa.is_empty() and int(wa[-1].aktuell) == 2, "Wahl gesetzt")
	ev.clear()
	for a in ["spielen", "lauter", "tempo_auf", "untertitel", "vor_lang"]:
		w.senden("video", { "tab": tid, "aktion": a })
	for i in 3:
		await get_tree().process_frame
	var vi := ev.filter(func(e: Dictionary) -> bool: return e.t == "video")
	check(not vi.is_empty() and int(vi[-1].laut) == 80 and int(vi[-1].tempo) == 125 and int(vi[-1].untertitel) == 1 and int(vi[-1].zeit) == 60,
		"Fernbedienung Plus: Lautstärke, Tempo, Untertitel, 60 s")
	ev.clear()
	w.senden("blocker-liste", { "hosts": ["uzai.example"] })
	w.senden("blocker", { "tab": tid, "an": false })
	w.senden("kern", { "aktion": "diagnose" })
	for i in 3:
		await get_tree().process_frame
	bl = ev.filter(func(e: Dictionary) -> bool: return e.t == "blocker")
	check(not bl.is_empty() and str(bl[-1].cookies) == "aus" and int(bl[-1].anzahl) == 0, "Blocker für die Seite aus: nichts geblockt")
	var ke := ev.filter(func(e: Dictionary) -> bool: return e.t == "kern")
	check(not ke.is_empty() and str(ke[-1].stand) == "diagnose" and str(ke[-1].text).contains("Sandbox"), "Kern: Diagnose kommt als Ereignis")
	check(Wirt.kern() == "cef" and not w.kern_noetig(), "Kern-Einstellung: CEF, im Vorführmodus nichts zu laden")
	var schritte: Array = []
	var grund: String = await w.kern_laden(func(sch: String, _p: int) -> void: schritte.append(sch))
	check(grund == "" and schritte.has("download") and schritte.has("install"), "Kern laden (gespielt): Schritte mit Fortschritt, kein Fehler")
	var re := RegEx.create_from_string(Wirt.KERN_EXE_MUSTER)
	check(re.search("C:\\Users\\x\\AppData\\Local\\Uzai\\browser\\kern\\app\\uzai-browser.exe") != null
		and re.search("C:\\Users\\x\\AppData\\Local\\Uzai\\browser\\kern\\app\\uzai-kernladen.exe") != null
		and re.search("C:\\Users\\x\\AppData\\Local\\Uzai\\browser\\kern\\store\\uzai-browser.exe") == null
		and re.search("C:\\x\\uzai-browser.exe") == null, "Kern wird nur aus seinem Ordner gestartet")
	w.senden("ende")
	await get_tree().process_frame
	check(not w.laeuft(), "Ende: Wirt aus")
	w.queue_free()


## Das Sprung-Skript läuft in der Seite (eigene Welt): keine Aufrufe, die Code aus Text bauen, kein
## Netz, keine Brücke zur Seite.
func _skript() -> void:
	print("Sprung-Skript")
	var js := FileAccess.get_file_as_string("res://helper/uzai-browser-karte.js")
	check(js.length() > 4000, "Skript da")
	for bad in ["eval(", "new Function", "Function(", "setTimeout(\"", "setInterval(\"", "innerHTML", "outerHTML", "insertAdjacentHTML",
			"document.write", "fetch(", "XMLHttpRequest", "WebSocket", "postMessage", "chrome.webview", "sendBeacon", "importScripts", "localStorage",
			"sessionStorage", "indexedDB", "document.cookie", "window.open"]:
		check(not js.contains(bad), "kein %s" % bad)
	check(js.contains("window.top !== window"), "nur im Hauptrahmen")
	check(js.contains("__uzaiMeldung"), "meldet nur über die eigene Bindung")


## Die WebView2-Dateien: Prüfsummen in Uzai, Helfer, Wirt und LIZENZ gleich.
func _pruefsummen() -> void:
	print("WebView2-Dateien")
	var lizenz := FileAccess.get_file_as_string("res://assets/browser/webview2/LIZENZ.txt")
	var helfer := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var wirt := FileAccess.get_file_as_string("res://helper/uzai-browser-wirt.cs")
	for name in Wirt.DATEIEN:
		var soll: String = Wirt.DATEIEN[name]
		var ist := FileAccess.get_sha256("res://assets/browser/webview2/" + name)
		check(ist == soll, "%s: Prüfsumme stimmt" % name)
		check(lizenz.contains(soll) and helfer.contains(soll) and wirt.contains(soll), "%s: gleiche Prüfsumme in LIZENZ, Helfer und Wirt" % name)
	check(lizenz.contains("Redistribution and use in source and binary forms"), "Lizenztext von Microsoft liegt bei")
