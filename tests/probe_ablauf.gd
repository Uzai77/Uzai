extends "res://tests/probe_base.gd"
## Abläufe wirklich bedienen (nicht nur ansehen): Suche tippen und öffnen, Spiel hinzufügen,
## Musikordner wählen und abspielen, Chat, Kauf im Shop, Einstellungen ändern, Raster ordnen.
## Bilder an den Stellen, an denen etwas schiefgehen kann; Skriptfehler stehen im Protokoll.
## Teile: --uzai-teil=suche|spiel|musik|chat|shop|einst|raster|medien (ohne: alle).

var teil := ""
var basis := ""


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-teil="):
			teil = a.substr(12)
	basis = OS.get_environment("UZAI_DATA").path_join("probe_ablauf")
	DirAccess.make_dir_recursive_absolute(basis)
	Nav.device = "pad"
	Nav.pad_name = "Xbox Wireless Controller"
	Nav.device_changed.emit("pad")
	await wait(2.0)
	for t in ["suche", "spiel", "musik", "chat", "shop", "einst", "raster", "medien"]:
		if teil == "" or teil == t:
			print("=== Teil: ", t)
			await call("_" + t)
			await _zu()


func _zu() -> void:
	var n := 0
	while Nav.top_layer() and n < 8:
		Nav.top_layer().close()
		n += 1
		await wait(0.4)


func _tippen(s: String) -> void:
	var k := Nav.top_layer()
	if k and k.has_method("_type"):
		for ch in s:
			k.call("_type", ch)
			await wait(0.12)


func _suche() -> void:
	main.goto("games", "zuletzt")
	await wait(1.0)
	main.open_search("")
	await wait(1.5)
	await _tippen("eld")
	await shot("a01_suche_tippen", 1.5)
	await press("menu")
	await shot("a02_suche_treffer", 1.5)
	await press("a")
	await shot("a03_suche_geoeffnet", 2.0)
	await _zu()
	main.open_search("")
	await wait(1.5)
	await _tippen("xyzq")
	await press("menu")
	await shot("a04_suche_nichts", 1.5)


func _spiel() -> void:
	var dir := basis.path_join("Spiele")
	for n in ["Hollow Knight", "Celeste", "Stardew Valley"]:
		DirAccess.make_dir_recursive_absolute(dir.path_join(n))
		var f := FileAccess.open(dir.path_join(n).path_join(n.replace(" ", "") + ".exe"), FileAccess.WRITE)
		f.store_string("MZ")
		f.close()
	DirAccess.make_dir_recursive_absolute(dir.path_join("Leer"))
	main.open_add_game()
	await wait(1.2)
	Nav.top_layer().call("_scan", dir)
	await shot("b01_hinzufuegen_funde", 2.5)
	await press("down")
	await press("a")
	await shot("b02_hinzufuegen_abgehakt", 0.8)
	await press("y")
	await shot("b03_hinzufuegen_y", 1.2)
	await _zu()
	main.open_add_game()
	await wait(1.0)
	Nav.top_layer().call("_scan", dir.path_join("Leer"))
	await shot("b04_hinzufuegen_leer", 2.0)


func _wav(pfad: String, sek: float) -> void:
	var f := FileAccess.open(pfad, FileAccess.WRITE)
	var n := int(8000 * sek)
	f.store_string("RIFF")
	f.store_32(36 + n)
	f.store_string("WAVEfmt ")
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(8000)
	f.store_32(8000)
	f.store_16(1)
	f.store_16(8)
	f.store_string("data")
	f.store_32(n)
	var b := PackedByteArray()
	b.resize(n)
	b.fill(128)
	f.store_buffer(b)
	f.close()


func _musik() -> void:
	var dir := basis.path_join("Musik")
	for al in [["Nachtfahrt", ["01 Auffahrt", "02 Tunnel", "03 Rastplatz"]], ["Sommer 98", ["01 Freibad", "02 Kassette"]]]:
		DirAccess.make_dir_recursive_absolute(dir.path_join("Die Probe").path_join(str(al[0])))
		for t in al[1]:
			_wav(dir.path_join("Die Probe").path_join(str(al[0])).path_join(str(t) + ".wav"), 20.0)
	main.goto("music", "alben")
	await wait(1.5)
	Config.set_value("music.local_dir", dir)
	await shot("c01_musik_nach_ordner", 4.0)
	await press("a")
	await shot("c02_musik_album", 2.0)
	await press("a")
	await shot("c03_musik_spielt", 2.5)
	await _zu()
	main.goto("music", "jetzt")
	await shot("c04_musik_laeuft", 2.0)
	main.goto("music", "titel")
	await shot("c05_musik_titel", 2.0)
	main.goto("music", "interpreten")
	await shot("c06_musik_interpreten", 2.0)
	main.toggle_guide()
	await wait(1.0)
	await press("rb", 3)
	await shot("c07_guide_musik", 1.5)
	await _zu()
	main.goto("games", "zuletzt")
	await shot("c08_start_mit_musik", 1.5)
	Music.play_pause()


func _chat() -> void:
	main.goto("games", "zuletzt")
	await wait(1.0)
	await press("view")
	await wait(1.5)
	await press("down")
	await press("a")
	await shot("d01_freund_aktionen", 1.5)
	await press("a")
	await shot("d02_nach_erster_aktion", 2.0)
	await _zu()
	main.open_notifications()
	await wait(1.2)
	await press("a")
	await shot("d03_mitteilung_geoeffnet", 2.0)
	await _zu()
	main.open_power()
	await shot("d04_ausschalten", 1.2)
	await press("down")
	await press("a")
	await shot("d05_ausschalten_zweite", 2.0)
	await press("a")
	await wait(1.0)


func _shop() -> void:
	main.goto("shop", "entdecken")
	await wait(2.0)
	await press("a")
	await wait(2.5)
	await press("a")
	await shot("e01_shop_kaufen", 1.5)
	await _zu()
	main.goto("shop", "wunschliste")
	await shot("e02_wunschliste", 2.0)
	await press("y")
	await shot("e03_wunschliste_y", 1.2)
	await _zu()
	main.goto("achievements", "backlog")
	await wait(1.5)
	await press("a")
	await shot("e04_backlog_a", 1.5)


func _einst() -> void:
	main.goto("settings", "controller")
	await wait(1.0)
	await press("right")
	await press("down")
	await press("a")
	await shot("f01_ab_getauscht", 1.0)
	await press("a")
	main.goto("settings", "aussehen")
	await wait(1.0)
	await press("right")
	await press("down", 5)
	await press("a")
	await press("right", 4)
	await shot("f02_groesse_stellen", 1.0)
	await press("a")
	await shot("f03_groesse_120", 2.0)
	Config.set_value("theme.scale", 1.0)
	await wait(1.5)
	main.goto("settings", "suche")
	await wait(1.0)
	main.goto("settings", "aussehen")
	await press("up", 3)
	await press("a")
	await wait(1.2)
	await _tippen("laut")
	await shot("f04_einst_suche", 1.5)
	await press("menu")
	await shot("f05_einst_suche_treffer", 1.2)


func _raster() -> void:
	main.open_library("alle", "Alle")
	await wait(2.0)
	await press("y")
	await press("down")
	await press("a")
	await shot("g01_raster_geordnet", 1.5)
	await press("x")
	await wait(1.0)
	await _tippen("sh")
	await shot("g02_raster_suche", 1.5)
	await _zu()
	main.goto("games", "zuletzt")
	await wait(1.0)
	await press("y")
	await shot("g03_start_optionen", 1.2)
	await press("down", 2)
	await press("a")
	await shot("g04_start_option_gewaehlt", 1.5)
	await _zu()
	main.goto("games", "zuletzt")
	await press("x")
	await shot("g05_start_favorit", 1.0)
	await press("x")
	await press("rb", 2)
	await shot("g06_start_reiter", 1.5)


func _medien() -> void:
	main.goto("videos", "fuerdich")
	await wait(2.0)
	await press("a")
	await shot("h01_video_a", 3.0)
	await press("b")
	await wait(1.0)
	await _zu()
	main.goto("movies", "start")
	await wait(2.0)
	await press("down")
	await press("a")
	await wait(2.0)
	await press("a")
	await shot("h02_film_a", 3.0)
	await press("b")
	await wait(1.0)
	await _zu()
	main.goto("streams", "start")
	await wait(2.0)
	await press("a")
	await shot("h03_stream_a", 3.0)
	await press("b")
	await wait(1.0)
	await _zu()
	main.goto("browser", "")
	await wait(1.5)
	await press("a")
	await shot("h04_browser_a", 2.0)
