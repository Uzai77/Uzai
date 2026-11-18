extends "res://tests/probe_base.gd"
## Probe für Uzais eigenen Epic-Installer und den reparierten Launcher-Rückfall: der eine Hinweis
## beim ersten Mal, die Download-Liste mit einem Epic-Spiel ohne Launcher und seine Knöpfe,
## Spieloptionen eines von Uzai installierten Spiels, ein Gratis-Spiel, das dir gehört
## („Installieren“), das Fenster des Launchers in Uzai mit „Ohne Launcher installieren“ und die
## Einstellungen.

const Flow := preload("res://src/ui/install_flow.gd")
const P := preload("res://src/core/install_parse.gd")
const FreeGame := preload("res://src/ui/layers/free_game.gd")
const WindowRemote := preload("res://src/ui/layers/window_remote.gd")


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	Config.set_value("accounts.epic_refresh", "probe")
	Config.set_value("accounts.epic_name", "Spieler")
	Config.set_value("library.epic_uzai_dir", "D:/Spiele/Epic")
	Installs.main = main
	var ctl := Library.get_game("epic:DemoControl")
	ctl["epic"] = { "namespace": "ns-control", "item": "item-control", "app": "DemoControl" }
	var hog := Library.get_game("epic:DemoHogwarts")
	hog["epic_uzai"] = true
	hog["install_dir"] = "D:/Spiele/Epic/Hogwarts Legacy"
	hog["path"] = "D:/Spiele/Epic/Hogwarts Legacy/Phoenix/Binaries/Win64/HogwartsLegacy.exe"
	await wait(1.5)
	# 1. Der eine Satz beim ersten Mal.
	Flow.ask_uzai(main, Library.get_game("epic:DemoDeathStranding"), true)
	await shot("01_hinweis_erstes_mal", 1.0)
	await _close_all()
	# 2. Downloads: ein Epic-Spiel lädt mit Uzais Installer.
	var id := "epic:DemoDeathStranding"
	var e: Dictionary = Installs._new_entry(Library.get_game(id))
	var total := 71.3 * 1073741824.0
	e.merge({ "how": "uzai", "can_pause": true, "phase": "downloading", "frac": 0.42, "got": total * 0.42, "total": total, "speed": 48.0 * 1048576.0,
		"text": P.line("Wird geladen", 0.42, total * 0.42, total, 48.0 * 1048576.0) }, true)
	Installs.items[id] = e
	Flow.open_downloads(main)
	await shot("02_downloads_ohne_launcher", 2.0)
	Flow.actions(main, id)
	await shot("03_knoepfe_pausieren_abbrechen", 0.8)
	await _close_all()
	Installs.items.erase(id)
	# 3. Spieloptionen eines von Uzai installierten Spiels.
	main.open_game_options(Library.get_game("epic:DemoHogwarts"))
	await wait(0.8)
	await press("down", 6)
	await shot("04_spieloptionen_pruefen_deinstallieren", 0.8)
	await _close_all()
	# 4. Gratis-Spiel, das dir gehört: gleich „Installieren“.
	var f = FreeGame.new()
	f.item = { "store": "epic", "name": "Control", "ns": "ns-control", "slug": "control", "url": "https://store.epicgames.com/de/p/control",
		"desc": "Ein übernatürliches Abenteuer im Ältesten Haus.", "upcoming": false }
	f.main = main
	main.open_layer(f)
	await shot("05_gratis_gehoert_dir_installieren", 1.2)
	await _close_all()
	# 5. Das Fenster des Launchers in Uzai, mit dem Weg ohne Launcher.
	var l = WindowRemote.new()
	l.hwnd = 0
	l.heading = "Epic Games Launcher"
	l.alt_text = "Ohne Launcher installieren"
	main.open_layer(l)
	await shot("06_launcher_fenster_in_uzai", 1.2)
	await _close_all()
	# 6. Einstellungen → Spiele → Installieren und Downloads.
	main.goto("settings", "spiele")
	await wait(1.0)
	var sv = main.sections["settings"]
	sv.open_more("Installieren und Downloads")
	await wait(0.6)
	await press("down", 2)
	await shot("07_einstellungen_epic", 0.8)
	await _close_all()


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().process_frame
	await wait(0.3)
