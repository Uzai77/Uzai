extends Node
## Erster Start (Punkte 52, 53): Konten der Einrichtung nur per QR, die kurze Tour danach (wann
## sie kommt, Weiter/Abbrechen, die Hinweise) und die Startseite gleich voll – Reihenfolge ohne
## Spielzeit nach dem, was der Launcher bzw. die Datei sagt, und kein verlorenes Einlesen.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_erststart.tscn → „Ergebnis: alles ok“

const E := preload("res://src/core/einrichtung.gd")
const Lib := preload("res://src/library/library.gd")
const Glyph := preload("res://src/ui/components/glyph.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const RomScanner := preload("res://src/library/rom_scanner.gd")
const PcScanner := preload("res://src/library/pc_scanner.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Konten in der Einrichtung: alle zur Wahl, ohne IDs")
	var list := [
		{ "title": "Steam", "way": "qr" },
		{ "title": "Discord", "way": "app", "needs_id": true },
		{ "title": "Spotify", "way": "qr" },
		{ "title": "Alt", "way": "" },
		{ "title": "Nuvio", "way": "qr" },
	]
	var shown: Array = E.setup_accounts(list).map(func(a: Dictionary) -> String: return str(a.title))
	check(shown == ["Steam", "Discord", "Spotify", "Nuvio"], "QR- und App-Konten zur Wahl: %s" % str(shown))
	check(E.app_accounts(list) == ["Discord"], "nur mit eigener App: ehrlich benannt")
	check(E.setup_accounts([]).is_empty() and E.app_accounts([{}]).is_empty() and E.setup_accounts([{ "way": "qr" }]).is_empty(), "leere Liste, Eintrag ohne Angaben")
	var w = load("res://src/ui/layers/setup_wizard.gd").new()
	var real: Array = w.call("_accounts")
	var real_shown: Array = E.setup_accounts(real).map(func(a: Dictionary) -> String: return str(a.title))
	check(real.all(func(a: Dictionary) -> bool:
		var st: Array = (a.status as Callable).call()
		return st.size() == 3 and str(st[0]) != ""), "jede Zeile hat einen Stand")
	w.free()
	# Plex und Stremio immer; Jellyfin und Emby nur, wenn schon einer verbunden ist – sonst unter Filme-Quellen.
	# Steam und Discord (Freunde, Chat) zuerst – es gibt keinen eigenen Freunde-Schritt mehr.
	check(real_shown == ["Steam", "Discord", "Epic Games", "Spotify", "YouTube", "Twitch", "Nuvio", "Plex", "Stremio", "RetroAchievements"],
			"alle Konten in der Einrichtung, Steam und Discord zuerst, Nuvio vor Medienservern: %s" % str(real_shown))
	check(real.all(func(a: Dictionary) -> bool: return str(a.get("way", "")) in ["qr", "app"]), "jedes Konto sagt, wie es verbunden wird")
	check(E.app_accounts(real).is_empty(), "mit Uzais Discord-App braucht kein Konto eine eigene ID")
	var wsrc := Quelle.lesen("res://src/ui/layers/setup_wizard_konten.gd")
	var konten_src := wsrc.substr(wsrc.find("func _konten()"), wsrc.find("# --- 6 Extras") - wsrc.find("func _konten()"))
	check(not konten_src.contains("open_keyboard(\"Discord-Client-Secret") and not konten_src.contains("spotify_client_id\", \"\")) != \"\"")
			and not konten_src.contains("client_secret"), "kein Feld für Secrets im Hauptweg")

	print("Tour: wann sie kommt")
	check(E.tour_due({}), "nach der ersten Einrichtung: ja")
	check(not E.tour_due({ "tour": true }), "schon gesehen: nein")
	check(not E.tour_due({ "restart": true }), "Einrichtung aus den Einstellungen neu gestartet: nein")
	check(not E.tour_due({}, true), "Vorführung: nein")

	print("Tour: Weiter und Abbrechen")
	var n: int = E.TOUR.size()
	check(n >= 3 and n <= 4, "drei bis vier Hinweise (%d)" % n)
	check(E.tour_next(0, n, "a") == 1 and E.tour_next(n - 2, n, "a") == n - 1, "A: zum nächsten")
	check(E.tour_next(n - 1, n, "a") == -1, "A am letzten: fertig")
	check(E.tour_next(0, n, "b") == -1 and E.tour_next(2, n, "b") == -1, "B: sofort zu Ende")
	check(E.tour_next(1, n, "x") == 1 and E.tour_next(9, n, "x") == n - 1, "andere Tasten: bleibt")
	check(E.tour_next(0, 0, "a") == -1, "ohne Hinweise: gleich fertig")
	var ok_items := true
	for h in E.TOUR:
		var key := str(h.get("key", ""))
		var has_sign := (key != "" and Glyph.KEYS.has(key)) or (key == "" and Icons.P.has(str(h.get("icon", ""))))
		if not has_sign or str(h.get("title", "")) == "" or str(h.get("text", "")).length() < 12 or str(h.get("text", "")).length() > 48:
			ok_items = false
			print("    ", h)
	check(ok_items, "jeder Hinweis: Taste oder Zeichen, Titel und eine knappe Zeile")
	check(E.TOUR.map(func(h: Dictionary) -> String: return str(h.get("key", h.get("icon", "")))) == ["guide", "search", "y", "settings"],
			"Guide, Suche, Optionen, Einstellungen")
	var named := false
	for h in E.TOUR:
		for word in [" Y ", " RS", " R3", "Taste A", " A öffnet", "Dreieck"]:
			if (" " + str(h.text) + " ").contains(word):
				named = true
	check(not named, "Texte nennen keine Tasten (das Symbol passt sich dem Controller an)")
	var ort := false
	for h in E.TOUR:
		for word in ["oben", "unten", "rechts", "links", "hier", "→", "Tour"]:
			if str(h.text).to_lower().contains(word.to_lower()):
				ort = true
	check(not ort, "Texte ohne Ortsangabe und ohne Anleitung")

	print("Startseite: Reihenfolge ohne Spielzeit")
	var day := 86400
	var t0 := 1_760_000_000
	var games := [
		{ "id": "alt", "added": t0, "install_time": t0 - 400 * day },
		{ "id": "frisch", "added": t0 + 30, "install_time": t0 - 2 * day },
		{ "id": "mitte", "added": t0 + 10, "install_time": t0 - 40 * day },
		{ "id": "ohne", "added": t0 + 5 },
		{ "id": "spaeter", "added": t0 + 3 * day, "install_time": t0 - 900 * day },
	]
	games.sort_custom(Lib.newer)
	var ids: Array = games.map(func(g: Dictionary) -> String: return str(g.id))
	check(ids == ["spaeter", "frisch", "mitte", "alt", "ohne"], "später gefunden zuerst, am selben Tag zuletzt installiert: %s" % str(ids))
	var same := [{ "id": "a", "added": t0 }, { "id": "b", "added": t0 + 60 }]
	same.sort_custom(Lib.newer)
	check(str(same[0].id) == "b", "ohne Zeit vom Launcher: wie bisher, neuer gefunden zuerst")
	check(Lib.INT_FIELDS.has("install_time"), "Zeit vom Launcher bleibt nach dem Laden eine ganze Zahl")

	print("Startseite: Zeiten aus Launcher und Dateien")
	var root := Config.path("erststart-test")
	DirAccess.make_dir_recursive_absolute(root.path_join("steam/steamapps/common/Celeste"))
	_write(root.path_join("steam/steamapps/appmanifest_504230.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"504230\"\n\t\"name\"\t\t\"Celeste\"\n\t\"installdir\"\t\t\"Celeste\"\n\t\"LastUpdated\"\t\t\"1700000000\"\n\t\"LastPlayed\"\t\t\"0\"\n}\n")
	var st := SteamScanner.scan(root.path_join("steam"))
	check(st.size() == 1 and int(st[0].get("install_time", 0)) == 1700000000, "Steam: LastUpdated aus dem appmanifest")
	DirAccess.make_dir_recursive_absolute(root.path_join("roms"))
	_write(root.path_join("roms/Tetris.gb"), "x")
	var sys := { "id": "gb", "extensions": ["gb"] }
	var rs := RomScanner.scan(sys, root.path_join("roms"))
	check(rs.size() == 1 and int(rs[0].get("install_time", 0)) > 0, "Spieleordner: Zeit der Datei")
	check(int(PcScanner.entry(root.path_join("roms/Tetris.gb")).get("install_time", 0)) > 0, "PC-Spiel: Zeit der Datei bzw. Verknüpfung")

	print("Einlesen geht nicht verloren")
	var was: bool = Library.scanning
	Library.scanning = true
	Library.set("_scan_again", "")
	Library.scan()
	check(str(Library.get("_scan_again")) == "ja", "neuer Ordner während des Einlesens: gleich danach noch einmal")
	Library.scan(true)
	Library.scan()
	check(str(Library.get("_scan_again")) == "online", "mit Konto-Abgleich verlangt: bleibt dabei")
	Library.set("_scan_again", "")
	Library.scanning = was

	print("Eingebaut")
	var wiz := Quelle.lesen("res://src/ui/layers/setup_wizard.gd")
	check(wiz.contains("E.setup_accounts(_accounts())") and wiz.contains("Tour.offer(main, tour)"), "Einrichtung: Konten zur Wahl, danach die Tour")
	var set_src := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	check(set_src.contains("\"Kurze Tour\"") and set_src.contains("tour.gd\").open_for(main)"), "Einstellungen → System → Kurze Tour")
	var lib_src := Quelle.lesen("res://src/library/library.gd")
	var scan_src := lib_src.substr(lib_src.find("func _einlesen("))
	var at_emit := scan_src.find("changed.emit()")
	check(at_emit > 0 and at_emit < scan_src.find("await _index_discs()"), "Spiele erscheinen vor dem Lesen der Disc-Nummern")

	# A setup that was never completed must not be silently skipped after an update.
	print("Einrichtung nach einem Update")
	var ich := { "first_run": false }
	check(E.start_mode({}, ich) == "anbieten", "benutzt Uzai, nie abgeschlossen: angeboten")
	check(E.start_mode({ "step": "spiele", "done": false }, ich) == "weiter", "abgebrochen oder abgestürzt bei „Spiele“: geht dort weiter")
	check(E.start_mode({ "done": true }, ich) == "", "fertig oder mit „Abbrechen“ geschlossen: nie wieder")
	check(not E.tour_due({ "restart": true }), "angeboten (wie aus den Einstellungen): danach keine Tour")
	var main_src := Quelle.lesen("res://src/main.gd")
	var boot := main_src.substr(main_src.find("func _after_boot()"), main_src.find("# --- Aufbau ---") - main_src.find("func _after_boot()"))
	check(boot.contains("SetupWizard.open_for(self, setup == \"anbieten\")"), "angeboten: mit „Abbrechen“ (B im ersten Schritt schließt für immer)")
	check(boot.contains("if setup != \"anbieten\":\n\t\tWhatsNew.offer(self, fresh)"), "über der angebotenen Einrichtung keine Karte „Was ist neu“")
	check(wiz.contains("Config.set_value(\"einrichtung.done\", true)") and wiz.contains("Abgebrochen im ersten Schritt"),
			"„Abbrechen“ merkt sich das (bewusst übersprungen) und steht im Protokoll")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
