extends "res://tests/probe_base.gd"
## Probe „Hilfe bei Problemen“: Erste Hilfe unter Einstellungen → System (Liste, Schritte, Knöpfe
## und ob jede Stelle in den Einstellungen wirklich existiert), die Karte nach einem Absturz je
## Quelle und der Guide über einem Spiel, das nicht antwortet.

const Trouble := preload("res://src/core/trouble.gd")


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.4)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	await _targets()
	await _first_aid()
	await _crash_cards()
	await _hung_guide()


## Jede „seite:“-Stelle der Erste-Hilfe-Knöpfe muss es in den Einstellungen geben.
func _targets() -> void:
	var idx: Array = main.sections["settings"].search_index()
	var bad := 0
	for p in Trouble.FIRST_AID:
		for a in p.actions:
			var id := str(a[1])
			if not id.begins_with("seite:"):
				continue
			var t := id.trim_prefix("seite:")
			var cat := t.get_slice("/", 0).get_slice("#", 0)
			var more := t.get_slice("/", 1) if t.contains("/") else ""
			var row := t.get_slice("#", 1) if t.contains("#") else ""
			var found := idx.any(func(e: Dictionary) -> bool:
				return str(e.cat) == cat and (more == "" or str(e.more) == more) and (row == "" or (str(e.more) == "" and str(e.key) == "set:%s:%s" % [cat, row])))
			print("Ziel %s: %s" % [id, "da" if found else "FEHLT"])
			if not found:
				bad += 1
	print("Ziele fehlen: %d" % bad)


func _first_aid() -> void:
	main.goto("settings", "system")
	await wait(0.8)
	var sv = main.sections["settings"]
	sv._enter_content()
	await wait(0.3)
	for c in Nav.focusables(sv._list):
		if str(c.get_meta("uz_key", "")).ends_with("Erste Hilfe"):
			Nav.focus(c, true)
	await shot("h01_system_erste_hilfe", 0.6)
	await press("a")
	await shot("h02_liste", 0.9)
	await press("a")
	await shot("h03_controller", 0.7)
	await press("b")
	await wait(0.4)
	await press("down", 8)
	await press("a")
	await shot("h04_bibliothek", 0.7)
	await press("b")
	await wait(0.4)
	await press("down")
	await press("a")
	await shot("h05_langsam", 0.7)
	# Knopf „Leistung“ (erster Knopf): Hilfe zu, Unterseite Leistung offen.
	await press("a")
	await shot("h06_ziel_leistung", 1.0)
	await _close_all()
	# Musik: zweiter Knopf führt in eine andere Kategorie (Medien).
	sv._show_cat("system")
	await wait(0.3)
	sv.open_more("Erste Hilfe")
	await wait(0.6)
	await press("down", 6)
	await press("a")
	await wait(0.6)
	await press("right")
	await press("a")
	await shot("h07_ziel_medien", 1.0)
	print("Kategorie nach dem Knopf: %s" % sv.sub)
	await _close_all()


func _crash_cards() -> void:
	main.goto("games")
	await wait(0.6)
	var steam: Array = Library.games.filter(func(g): return str(g.get("source", "")) == "steam")
	var roms: Array = Library.games.filter(func(g): return str(g.get("source", "")) == "rom" and str(g.get("system", "")) == "ps2")
	if not steam.is_empty():
		main._on_game_crashed(steam[0], Trouble.verdict({ "kind": "steam", "secs": 900, "window": true, "steam_seen": true,
			"wer": { "found": true, "code": "c0000005", "module": "d3d11.dll" } }))
		await shot("h10_absturz_steam", 1.4)
		await _close_all()
	if not roms.is_empty():
		main._on_game_crashed(roms[0], Trouble.verdict({ "kind": "rom", "secs": 4, "window": false, "code": 0xC0000005 }))
		await shot("h11_absturz_ps2", 1.4)
		await _close_all()
	main._on_game_crashed({ "id": "probe:pc", "title": "Mein Spiel", "source": "pc", "path": "C:/Spiele/Mein Spiel/spiel.exe" },
		Trouble.verdict({ "kind": "pc", "secs": 1, "window": false, "code": 0xC0000135 }))
	await shot("h12_fehlstart_pc", 1.4)
	await _close_all()


func _hung_guide() -> void:
	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	Launcher.in_game = true
	Launcher.current = g
	Launcher.hung = true
	main.toggle_guide("spiel")
	await shot("h20_guide_haengt", 1.2)
	await press("a")
	await shot("h21_frage_sofort", 0.7)
	print("Auswahl im Dialog: %s" % str(Nav.focused().get("text") if Nav.focused() else ""))
	await press("b")
	await _close_all()
	Launcher.hung = false
	Launcher.in_game = false
	Launcher.current = {}
