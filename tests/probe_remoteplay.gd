extends "res://tests/probe_base.gd"
## Probe für Remote Play Together: Abschnitt in Einstellungen → System (vor und nach dem
## Einrichten), Auswahl des Spenders, Spieloptionen eines Emulator-Spiels und das Menü an einem
## Steam-Freund im Guide und im Bereich Freunde, während ein PS2-Spiel über den Spender läuft.
## Die Dateien des Spenders sind nachgebaut (im Datenordner), Steam läuft hier nicht.

const RP := preload("res://src/core/remote_play.gd")


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().process_frame
	await wait(0.35)


func focus_key(k: String) -> void:
	for c in Nav.focusables(main.sections["settings"]):
		if str(c.get_meta("uz_key", "")) == k:
			Nav.focus(c, true)
			return
	print("Nicht gefunden: ", k)


func _fake_donor() -> void:
	var dir := Config.path("probe-steam/RetroArch")
	DirAccess.make_dir_recursive_absolute(dir)
	var starter := RP.starter_path()
	DirAccess.make_dir_recursive_absolute(starter.get_base_dir())
	for p in [starter, dir.path_join("retroarch.exe")]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("MZ UzaiStarter Probe")
		f.close()
	var o := FileAccess.open(dir.path_join("retroarch.uzai-original.exe"), FileAccess.WRITE)
	o.store_string("ORIGINAL")
	o.close()
	Config.set_value("remoteplay.donor_appid", RP.RETROARCH_APPID)
	Config.set_value("remoteplay.donor_exe", dir.path_join("retroarch.exe"))
	Config.set_value("remoteplay.donor_title", "RetroArch")
	Config.set_value("remoteplay.donor_id", "steam:1118310")


func run() -> void:
	Config.set_value("remoteplay.donor_exe", "")
	Config.set_value("remoteplay.donor_appid", 0)
	# Einstellungen, noch nicht eingerichtet
	main.goto("settings", "system")
	await wait(1.0)
	focus_key("set:system:Spender-Spiel")
	await shot("r01_einstellungen_leer", 0.8)
	# Auswahl des Spenders (RetroArch steht oben, wenn es installiert ist)
	Library.games.append({ "id": "steam:1118310", "title": "RetroArch", "system": "steam", "source": "steam", "appid": 1118310,
		"installed": true, "install_dir": Config.path("probe-steam/RetroArch") })
	Library._reindex()
	RP.choose_donor(main, Callable())
	await shot("r02_spender_waehlen", 0.8)
	await _close_all()
	# Eingerichtet
	_fake_donor()
	main.sections["settings"].build()
	await wait(0.6)
	focus_key("set:system:Spender-Spiel")
	await shot("r03_einstellungen_bereit", 0.8)
	focus_key("set:system:Emulator-Spiele immer Remote-Play-bereit starten")
	await shot("r04_einstellungen_emulatoren", 0.6)
	focus_key("set:system:Freunde einladen")
	await shot("r05_einstellungen_einladen", 0.6)
	focus_key("set:system:Spieler 2 automatisch einrichten")
	await shot("r05b_spieler2", 0.6)
	focus_key("set:system:Wenn Spieler 2 nicht reagiert")
	await shot("r05c_tipps", 0.6)
	# Spieloptionen eines PS2-Spiels
	main.goto("games")
	await wait(0.8)
	var ps2: Dictionary = Library.by_system("ps2")[0]
	main.open_game_options(ps2)
	await wait(0.6)
	await press("down")
	await shot("r06_spieloptionen", 0.6)
	await _close_all()
	# Im Spiel über den Spender: Guide → Freunde → Freund
	Launcher.in_game = true
	Launcher.current = ps2
	Launcher.remote_play = true
	main.toggle_guide("freunde")
	await wait(1.0)
	await shot("r07_guide_freunde", 0.2)
	await press("a")
	await shot("r08_freund_menue", 0.8)
	await press("b")
	await _close_all()
	# Bereich Freunde: Menü an einem Freund
	var fa = load("res://src/ui/layers/friend_actions.gd").new()
	fa.friend = Social.steam_friends[2]
	fa.kind = "steam"
	main.open_layer(fa)
	await shot("r09_freund_aktionen", 0.9)
	await _close_all()
	# Ergebnis-Mitteilungen
	Toasts.show_toast("Zu Remote Play eingeladen: Lea",
			"Die Einladung zu Shadow of the Colossus ist unterwegs. Dein Freund nimmt sie in Steam an und spielt dann mit dem eigenen Controller mit.", "check",
			{ "ms": 7000 })
	await shot("r10_toast_ok", 0.9)
	Toasts.show_toast("Einladen ging nicht", RP.overlay_hint("Steam hat die Einladung nicht angenommen."), "warning", { "ms": 9000 })
	await shot("r11_toast_rueckfall", 0.9)
	Toasts.show_toast("Spieler 2 ist verbunden", "Lea spielt jetzt mit.", "controller", { "sound": "select", "ms": 5000 })
	await shot("r12_toast_spieler2", 0.9)
	Launcher.in_game = false
	Launcher.remote_play = false
	Launcher.current = {}
