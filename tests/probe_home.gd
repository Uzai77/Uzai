extends "res://tests/probe_base.gd"
## Probe für die Startseite, die Spielseite, die Bibliothek, die Spiel-Optionen und die
## SteamGridDB-Bildwahl (vorher/nachher). Mit UZAI_DEMO_ART bekommt die Spielseite echte Bilder.
## UZAI_PROBE=start,seite,bib,opt,sgdb wählt Teile aus (ohne: alles).


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	Config.set_value("theme.corners", "rund")
	Config.set_value("theme.cover_shape", "hoch")
	# Das Farbschema baut die Oberfläche neu auf; erst danach Ebenen öffnen.
	await wait(1.0)
	var art := OS.get_environment("UZAI_DEMO_ART")
	var parts := OS.get_environment("UZAI_PROBE")
	_demo_page_data(art)
	if parts == "" or parts.contains("start"):
		await _start_page()
	if parts == "" or parts.contains("bib"):
		await _library()
	if parts == "" or parts.contains("opt"):
		await _options()
	if parts == "" or parts.contains("sgdb"):
		await _sgdb()
	if parts == "" or parts.contains("seite"):
		await _game_page()
	if parts.contains("quer"):
		await _shapes()


## Andere Cover-Formen und eckige Ecken: Regal, Ordner und „Alle anzeigen“ müssen mitgehen.
func _shapes() -> void:
	Config.set_value("theme.cover_shape", "quer")
	await wait(1.2)
	main.goto("games", "ps2")
	await shot("30_quer_ordner", 1.2)
	await press("right", 4, 0.15)
	await shot("31_quer_weiter", 0.9)
	Config.set_value("theme.cover_shape", "quadrat")
	Config.set_value("theme.corners", "eckig")
	await wait(1.2)
	main.goto("games", "zuletzt")
	await shot("32_quadrat_eckig", 1.2)
	main.open_folder_picker("f_demo2")
	await wait(0.8)
	await press("a")
	await shot("33_auswahl", 0.6)
	await press("b")
	Config.set_value("theme.cover_shape", "hoch")
	Config.set_value("theme.corners", "rund")
	await wait(1.0)


func _start_page() -> void:
	main.goto("games", "zuletzt")
	await shot("01_home", 1.4)
	# Spielwechsel: einmal mitten in der Bewegung, einmal danach.
	await press("right", 1, 0.02)
	await shot("02_home_wechsel", 0.06)
	await shot("03_home_rechts", 0.9)
	await press("right", 4, 0.16)
	await shot("04_home_weiter", 0.9)
	await press("left", 5, 0.12)
	await wait(0.6)
	# Nach oben: Quellen; „Für dich“ liegt hinter der Start-Taste (Seitenleiste von rechts)
	await press("up")
	await shot("05_quellen", 0.6)
	await press("down")
	await press("menu")
	await shot("06_fuer_dich", 0.7)
	await press("down")
	await shot("07_fuer_dich_zeile", 0.6)
	await press("b")
	await wait(0.4)
	# Wenige Spiele (Favoriten) und Ordner (PS2), am Ende „Alle anzeigen“
	main.goto("games", "favoriten")
	await shot("08_favoriten", 1.0)
	main.goto("games", "ps2")
	await shot("09_ps2_ordner", 1.0)
	await press("right", 13, 0.1)
	await shot("10_alle_anzeigen", 0.9)
	main.goto("games", "steam")
	await shot("11_steam", 1.2)


func _library() -> void:
	main.open_library("alle", "Alle Spiele")
	await shot("12_bibliothek", 1.0)
	await press("down", 2)
	await shot("13_bibliothek_unten", 0.7)
	await press("b")
	await wait(0.5)
	main.open_library("ordner:auto:ps2:RPG", "RPG")
	await shot("14_ordner_offen", 0.9)
	await press("b")
	await wait(0.5)


func _options() -> void:
	main.goto("games", "zuletzt")
	await wait(0.6)
	main.open_game_options(Library.get_game("ps2:74a8e64542ec02"))
	await shot("15_optionen_ps2", 0.8)
	await press("down", 9, 0.1)
	await shot("16_optionen_unten", 0.7)
	await press("b")
	await wait(0.4)
	main.open_game_options(Library.get_game("steam:1245620"))
	await shot("17_optionen_steam", 0.8)
	await press("b")
	await wait(0.4)


func _sgdb() -> void:
	main.open_art_picker(Library.get_game("ps2:30fa359a43774f"))
	await shot("18_steamgriddb", 1.0)
	await press("b")
	await wait(0.5)
	# Mit Heimnetz (feste Adresse): QR-Code für die Eingabe am Handy
	var l = load("res://src/ui/layers/art_picker.gd").new()
	l.game = Library.get_game("ps2:30fa359a43774f")
	l.phone_ip = "192.168.1.20"
	main.open_layer(l)
	await shot("19_steamgriddb_handy", 1.0)
	await press("b")
	await wait(0.5)


func _game_page() -> void:
	# Steam, mit Bildern (zwei laden nicht), Erfolgen, Freunden, Angaben
	main.open_game(Library.get_game("steam:1245620"))
	await shot("20_seite_oben", 2.2)
	await press("down")
	await shot("21_seite_bilder", 1.0)
	await press("down")
	await shot("22_seite_erfolge", 1.0)
	await press("down")
	await shot("23_seite_freunde", 1.0)
	await press("down")
	await shot("24_seite_mehr", 1.0)
	await press("b")
	await wait(0.6)
	# Nicht installiertes Steam-Spiel ohne Bilder
	var hk := Library.get_game("steam:367520")
	hk["installed"] = false
	main.open_game(hk)
	await shot("25_seite_installieren", 1.6)
	await press("b")
	await wait(0.5)
	# Dasselbe, während Steam lädt (Steams Datei appmanifest nachgestellt)
	var root := Config.path("probe_steam")
	DirAccess.make_dir_recursive_absolute(root.path_join("steamapps"))
	var f := FileAccess.open(root.path_join("steamapps/appmanifest_367520.acf"), FileAccess.WRITE)
	f.store_string('"AppState"\n{\n\t"appid"\t"367520"\n\t"name"\t"Hollow Knight"\n\t"StateFlags"\t"1026"\n\t"installdir"\t"Hollow Knight"\n\t"BytesToDownload"\t"9663676416"\n\t"BytesDownloaded"\t"3758096384"\n}\n')
	f.close()
	var keep_root: String = Library._steam_root
	Library._steam_root = root
	main.open_game(hk)
	await shot("25b_seite_laedt", 1.6)
	await press("b")
	await wait(0.5)
	Library._steam_root = keep_root
	hk["installed"] = true
	# Emulator-Spiel mit echtem Cover (wenn vorhanden)
	main.open_game(Library.get_game("ps2:74a8e64542ec02"))
	await shot("26_seite_emulator", 2.0)
	await press("down", 3)
	await shot("27_seite_emulator_unten", 1.0)
	await press("b")
	await wait(0.5)


## Beispielinhalte für die Spielseite (der Rundgang läuft ohne Internet).
func _demo_page_data(src: String) -> void:
	var g := Library.get_game("steam:1245620")
	var shots: Array = []
	if src != "":
		g["images"] = { "hero": src.path_join("hero.jpg"), "logo": src.path_join("logo.png") }
		Media.forget(g)
		for f in ["rom/snap.png", "rom/title.png", "hero.jpg", "rom/ico_snap.png"]:
			if FileAccess.file_exists(src.path_join(f)):
				shots.append(src.path_join(f))
	for i in 2:
		shots.append("https://demo.uzai/kaputt%d.jpg" % i)
	Store._details[1245620] = {
		"about": "Erhebe dich, Befleckter, und lass dich von der Gnade leiten, um die Macht des Eldenrings zu nutzen und ein Eldenfürst im Zwischenland zu werden. Eine weite Welt voller Gefahren, offen erkundbar, mit gewaltigen Dungeons und Gegnern, die dich alles abverlangen.",
		"genres": PackedStringArray(["Action", "Rollenspiel"]), "developer": "FromSoftware", "release": "25. Feb. 2022",
		"my_lang": true, "metacritic": 94, "screens": shots,
	}
	var list: Array = []
	var names := ["Eldenfürst", "Zeitalter der Sterne", "Herr der rasenden Flamme", "Schild-Großmeister", "Leyndell erreicht", "Malenia besiegt",
			"Rennala besiegt", "Radahn besiegt", "Godrick besiegt", "Morgott besiegt", "Mohg besiegt", "Rykard besiegt"]
	for i in names.size():
		list.append(
				{ "id": str(i), "title": names[i], "desc": "Beispielerfolg %d" % (i + 1), "icon": "", "icon_locked": "", "unlocked": i < 8, "rarity": 10.0 + i * 5 })
	Achievements._games["steam:1245620"] = { "source": "steam", "total": 42, "unlocked": 29, "list": list }
	if src != "" and DirAccess.dir_exists_absolute(src.path_join("rom")):
		var rg := Library.get_game("ps2:74a8e64542ec02")
		var h := str(rg.id).md5_text().substr(0, 16)
		for kind in ["snap", "title", "cover"]:
			var dest := Config.path("cache/img/libretro/%s_%s.png" % [h, kind])
			DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
			DirAccess.copy_absolute(src.path_join("rom/%s.png" % kind), dest)
		Config.write_json(Config.path("cache/wiki/%s.json" % str(rg.id).md5_text()), {
			"t": int(Time.get_unix_time_from_system()), "page": "Shadow of the Colossus", "page_de": "Shadow of the Colossus", "shots": [],
			"about": "(Beispieltext für die Probe) Ein junger Krieger reitet in ein verbotenes Land, um sechzehn riesige Kolosse zu bezwingen. Jeder Koloss ist ein eigenes Rätsel: erklettern, Schwachstelle finden, festhalten.",
		})
		Media.forget(rg)
