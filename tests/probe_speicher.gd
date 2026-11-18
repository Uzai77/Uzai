extends "res://tests/probe_base.gd"
## Probe für den Speicherplatz (Punkte 10 und 106): Zeile und Unterseite „Speicher“ unter
## Einstellungen → System, Optionen eines Spiels (Deinstallieren, Verschieben), Aufräumen mit
## Rückfrage, Platz auf Spiel- und Shopseite und die Warnungen „knapp“ und „voll“ vor dem Installieren.

const StorageFlow := preload("res://src/ui/storage_flow.gd")
const G := 1073741824


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	# Etwas zum Aufräumen im (eigenen) Datenordner der Probe.
	for i in 40:
		_write(Config.path("cache/img/web/bild_%d.jpg" % i), 180000)
	_write(Config.path("logs/steam.log"), 90000)
	main.goto("settings", "system")
	await wait(1.0)
	var sv = main.sections["settings"]
	for c in Nav.focusables(sv):
		if str(c.get_meta("uz_key", "")) == "more:system:Speicher":
			Nav.focus(c, true)
	await shot("01_system_zeile", 0.8)
	sv.open_more("Speicher")
	await shot("02_speicher_oben", 0.25)
	await shot("03_speicher_balken", 1.2)
	await press("down", 3)
	await shot("04_spiele", 0.6)
	await press("down", 12)
	await shot("05_aufraeumen", 1.2)
	var games := StorageFlow.games_stand()
	StorageFlow.game_options(main, games[0], Callable())
	await shot("06_spiel_optionen", 0.8)
	await _close_dialogs()
	StorageFlow.uninstall(main, games[0], Callable())
	await shot("07_deinstallieren", 0.8)
	await _close_dialogs()
	StorageFlow.move(main, games[0])
	await shot("08_verschieben", 0.8)
	await _close_dialogs()
	var epic: Array = games.filter(func(e: Dictionary) -> bool: return str(e.store) == "epic")
	if not epic.is_empty():
		StorageFlow.uninstall(main, epic[0], Callable())
		await shot("09_epic_deinstallieren", 0.8)
		await _close_dialogs()
	StorageFlow.ask_clean(main, "bilder", Callable())
	await shot("10_aufraeumen_frage", 0.8)
	await _close_dialogs()
	var files: Array = StorageFlow._clean_files.get("bilder", [])
	await StorageFlow._clean("bilder", files, Callable())
	await shot("11_aufgeraeumt", 0.6)
	await _close_all()
	# Spielseite eines nicht installierten Spiels: Platz auf dem Ziel-Laufwerk in der kleinen Zeile.
	for g in Library.games:
		if str(g.get("source", "")) == "epic" and not Library.is_installed(g):
			main.open_game(g)
			break
	await shot("12_spielseite", 1.6)
	await _close_all()
	# Warnungen vor dem Installieren (Demo: D: hat 41 GB frei).
	var eg := Library.get_game("steam:1245620")
	if eg.is_empty():
		eg = { "title": "Elden Ring", "source": "steam", "appid": 1245620 }
	StorageFlow.ask_space(main, eg, 60 * G, 41 * G, "D:", Callable())
	await shot("13_passt_nicht", 0.8)
	await _close_dialogs()
	StorageFlow.ask_space(main, eg, 35 * G, 41 * G, "D:", Callable())
	await shot("14_knapp", 0.8)
	await _close_all()
	# Shopseite: Speicherplatz mit freiem Platz.
	main.goto("shop")
	await wait(1.0)
	var shop = main.sections["shop"]
	shop.open_item({ "appid": 1145350, "name": "Hades", "store": "steam" })
	await wait(1.5)
	await press("down", 9, 0.25)
	await shot("15_shop_speicher", 1.0)


func _write(path: String, n: int) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_bytes(n))
	f.close()


func _bytes(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	return b


## Nur Dialoge über der Speicher-Seite schließen.
func _close_dialogs() -> void:
	while Nav.top_layer() and Nav.top_layer().get_script() != null and str(Nav.top_layer().get_script().resource_path).ends_with("dialog.gd"):
		Nav.top_layer().close()
		await get_tree().process_frame
	await wait(0.3)


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().process_frame
	await wait(0.25)
