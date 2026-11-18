extends "res://tests/probe_base.gd"
## Probe Spielstände, Neu-Einlesen und Disc vom Laufwerk: Spielseite mit „Weiter, wo du warst“ und
## „Spielstände“, die Liste mit Bildern, Entfernen, Guide im Emulatorspiel (Sichern/Laden, Beenden),
## Spielseite ohne gemerkte Stelle, Einstellungen → Emulation mit „Spiele neu einlesen“, Disc ohne
## Abbild auf der Startseite. Gibt „FX ok/FAIL …“ aus.

const QR := preload("res://src/core/quick_resume.gd")
const GamePage := preload("res://src/ui/layers/game_page.gd")
const Spielstaende := preload("res://src/ui/layers/spielstaende.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("FX %s %s" % ["ok  " if cond else "FAIL", what])


## Ein Bild „vom Moment“: Verlauf mit hellem Fleck (selbst gemalt).
func _paint(path: String, a: Color, b: Color, seed_v: int) -> void:
	var img := Image.create(480, 270, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var sun := Vector2(rng.randf_range(80, 400), rng.randf_range(50, 200))
	for y in 270:
		for x in 480:
			var c := a.lerp(b, float(y) / 270.0)
			c = c.lerp(Color(1, 0.95, 0.8), clampf(1.0 - Vector2(x, y).distance_to(sun) / 60.0, 0.0, 1.0) * 0.8)
			img.set_pixel(x, y, c)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_jpg(path)


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.5)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var g: Dictionary = Library.by_system("ps2")[0]
	var gid := str(g.id)
	var now := int(Time.get_unix_time_from_system())
	var cols := [[Color("#c9b48a"), Color("#3d4a5c")], [Color("#9fc3d6"), Color("#24313a")], [Color("#f2c46d"), Color("#3b1f2b")],
		[Color("#7fd3e8"), Color("#0e2a3d")], [Color("#8d9091"), Color("#202324")]]
	var ages := [[7200, "auto"], [86400 + 3000, "auto"], [3 * 86400, "auto"], [20 * 60, "own"], [2 * 86400, "own"]]
	DirAccess.make_dir_recursive_absolute(Config.path(QR.DIR))
	for i in ages.size():
		var base := Config.path(QR.DIR).path_join("probe_%d" % i)
		var f := base + ".p2s"
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_string("stand")
		fa.close()
		_paint(base + ".jpg", cols[i][0], cols[i][1], i + 5)
		QR.add(gid, { "emulator": "pcsx2", "at": now - int(ages[i][0]), "file": f, "shot": base + ".jpg",
			"slot_file": "C:/PCSX2/sstates/SCUS-1.01.p2s", "title": str(g.title) }, str(ages[i][1]))
	_ck(QR.states(g).size() == 5 and not QR.record(g).is_empty(), "fünf Stände, „Weiter, wo du warst“ da")

	# 1. Spielseite mit gemerkter Stelle.
	main.open_game(g)
	await shot("01_spielseite", 1.6)
	# 2. Alle Spielstände.
	GamePage.open_states(main, g, Callable())
	await shot("02_spielstaende", 1.0)
	await press("down")
	await shot("03_spielstaende_auswahl", 0.4)
	Nav._fire("y")
	await shot("04_entfernen_frage", 0.7)
	await press("b")
	await wait(0.4)
	await _close_all()

	# 3. Im Spiel: Guide mit Sichern/Laden, Laden-Liste, Beenden.
	Launcher.in_game = true
	Launcher.current = g
	Launcher._kind = "rom"
	main.toggle_guide("spiel")
	await shot("05_guide_spiel", 1.2)
	var guide: Node = main._guide
	Spielstaende.open_for(main, g, "laden", func(_r: Dictionary) -> void: pass)
	await shot("06_guide_laden", 1.0)
	Nav.top_layer().close()
	await wait(0.4)
	if guide and is_instance_valid(guide):
		guide._ask_quit()
		await shot("07_beenden", 0.8)
	await _close_all()
	Launcher.in_game = false
	Launcher.current = {}
	await wait(0.6)

	# 4. Anders weitergespielt: „Spielen“ vorn, die Stände bleiben unter „Spielstände“.
	QR.mark_stale(gid)
	_ck(QR.record(g).is_empty() and QR.states(g).size() == 5, "ohne gemerkte Stelle: Stände bleiben")
	main.open_game(g)
	await shot("08_spielseite_ohne_stelle", 1.4)
	await _close_all()

	# 5. Einstellungen → Spiele: „Spiele neu einlesen“.
	main.goto("settings", "spiele")
	await wait(1.2)
	var sv = main.sections["settings"]
	var found := false
	for c in Nav.focusables(sv):
		if str(c.get_meta("uz_key", "")) == "emu:rescan":
			Nav.focus(c, true)
			found = true
			break
	_ck(found, "Zeile „Spiele neu einlesen“ da")
	await shot("09_emulation_neu_einlesen", 0.8)
	Toasts.show_toast("Neu eingelesen", Library.scan_text({ "games": 58, "gone": 3 }), "refresh", { "ms": 5000 })
	await shot("10_meldung", 0.9)

	# 6. Disc ohne Abbild im Laufwerk: A spielt direkt.
	var exe := Config.path("probe_emu/duckstation.exe")
	DirAccess.make_dir_recursive_absolute(exe.get_base_dir())
	var fe := FileAccess.open(exe, FileAccess.WRITE)
	fe.store_string("x")
	fe.close()
	Config.set_emulator("duckstation", "exe", exe)
	Library.set_disc_db("ps1", { "serials": { "SCES-02105": "Crash Bandicoot 3 - Warped (Europe)" }, "files": {} })
	main.goto("games", "zuletzt")
	await wait(1.0)
	Discs.set_disc("SCES-02105", "ps1", "E:\\")
	await shot("11_disc_meldung", 1.2)
	_ck(Discs.can_play(), "Disc ohne Abbild: direkt spielbar")
	await shot("12_disc_startseite", 2.0)
	print("FX fertig, Fehler: %d" % fails)
