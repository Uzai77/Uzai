extends "res://tests/probe_base.gd"
## Eigene Spiele hinzufügen: Kachel am Ende von „Alle“, die Ebene, ein durchsuchter Ordner mit
## Haken, „Ändern“, und die Spieloptionen eines PC-Spiels (Programmdatei, Arbeitsordner).

func run() -> void:
	var root := OS.get_user_data_dir().path_join("probe_spiele")
	for rel in ["Hades/Hades.exe", "Hollow_Knight [GOG]/hollow_knight.exe", "Hollow_Knight [GOG]/unins000.exe",
			"Celeste v1.4.0.0/Celeste.exe", "Disco Elysium (GOG)/disco.exe", "_CommonRedist/vcredist_x64.exe"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(rel).get_base_dir())
		var f := FileAccess.open(root.path_join(rel), FileAccess.WRITE)
		f.store_string("x")
		f.close()
	main.sections["games"]._last_by_sub.clear()
	main.goto("games", "alle")
	await wait(1.2)
	var shelf = main.sections["games"]._shelf
	var last: Control = shelf.items()[shelf.items().size() - 1]
	Nav.focus(last, true)
	await shot("01_kachel", 0.8)
	var l = main.open_add_game()
	await wait(0.8)
	await shot("02_ebene", 0.3)
	l._scan(root)
	await wait(1.2)
	await shot("03_liste", 0.3)
	await press("down")
	await press("a")
	await wait(0.4)
	await shot("04_abgehakt", 0.3)
	l._add_selected()
	await wait(1.0)
	await shot("05_hinzugefuegt", 0.3)
	var g := Library.add_manual("Hades", root.path_join("Hades/Hades.exe"))
	main.open_game_options(g)
	await wait(0.8)
	await press("down", 9)
	await shot("06_optionen", 0.4)
	print("EIGENE: ", Library.by_system("pc").size(), " PC-Spiele")
