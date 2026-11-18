extends "res://tests/probe_base.gd"
## Probe „Akzent“: dieselben Bildschirme (Startseite, Einstellungen mit Schaltern, Guide,
## Spielseite) im Graphit-Theme mit einem anderen Akzent. UZAI_AKZENT=#rrggbb setzt nur in
## dieser Probe die Einstellung „Akzentfarbe“; leer = der Akzent des Themes (Gold). Die Bilder
## tragen UZAI_AKZENT_NAME als Vorsilbe, damit mehrere Läufe in einen Ordner passen.

var _p := ""


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var acc := OS.get_environment("UZAI_AKZENT")
	_p = OS.get_environment("UZAI_AKZENT_NAME")
	if _p == "":
		_p = "gold"
	if acc != "" and acc.is_valid_html_color():
		Config.set_value("theme.accent", acc)
	await wait(1.4)

	main.goto("games", "zuletzt")
	await shot("%s_1_start" % _p, 1.6)

	var sv = main.sections["settings"]
	for cid in ["aussehen", "system"]:
		main.goto("settings", cid)
		await wait(1.0)
		var first := Nav.default_in(sv._list)
		if first:
			Nav.focus(first, true)
		await press("down", 2, 0.2)
		await shot("%s_2_einst_%s" % [_p, cid], 0.8)

	main.goto("games", "zuletzt")
	await wait(0.8)
	main.toggle_guide()
	await wait(1.4)
	await shot("%s_3_guide" % _p, 0.5)
	await _close_all()

	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	main.open_game(g)
	await shot("%s_4_spielseite" % _p, 2.2)
	await press("down")
	await shot("%s_5_spielseite_erfolge" % _p, 1.0)
	await _close_all()


func _close_all() -> void:
	var n := 0
	while Nav.top_layer() and n < 8:
		Nav.top_layer().close()
		await wait(0.35)
		n += 1
	await wait(0.3)
