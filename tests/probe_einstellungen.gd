extends "res://tests/probe_base.gd"
## Probe für den Bereich Einstellungen: alle Unterseiten, Dialoge, Tastatur, Farbwahl,
## Dateiauswahl, Auswahlliste, Willkommen, Startfehler, Startbild und Mitteilungen.
## Mit --uzai-only=<teil,teil> lassen sich einzelne Teile fotografieren (boot, settings, layers, toasts, previews).

const BootC := preload("res://src/ui/boot.gd")
const WelcomeC := preload("res://src/ui/layers/welcome.gd")

var only := ""


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-only="):
			only = a.substr(12)
	Config.set_value("theme.preset", "theme")
	Config.set_value("theme.corners", "rund")
	Config.set_value("theme.background", "game")
	if _want("boot"):
		await _boot()
	if _want("settings"):
		await _settings()
	if _want("layers"):
		await _layers()
	if _want("toasts"):
		await _toasts()
	if _want("previews"):
		await _previews()
	if _want("fremd"):
		await _fremd()


## Fenster anderer Bereiche, die meine Bausteine benutzen (Einstellungszeile, Dialog).
func _fremd() -> void:
	main.goto("games")
	await wait(1.0)
	var g: Dictionary = Library.get_game(Library.recent(1)[0].id)
	main.open_game_options(g)
	await shot("f01_spieloptionen", 0.9)
	await _close_all()


func _want(part: String) -> bool:
	return only == "" or only.split(",").has(part)


func focus_key(k: String) -> void:
	for c in Nav.focusables(main.sections["settings"]):
		if str(c.get_meta("uz_key", "")) == k:
			Nav.focus(c, true)
			return
	print("Nicht gefunden: ", k)


# --- Vorschauen rechts und andere Farbschemata ----------------------------------------------

func _previews() -> void:
	main.goto("settings", "aussehen")
	await wait(0.8)
	for spec in [["Startanimation", "p01_start"], ["Ecken", "p02_ecken"], ["Cover-Form", "p03_coverform"], ["Schrift", "p04_schrift"],
			["Akzentfarbe", "p05_akzent"]]:
		focus_key("set:aussehen:" + str(spec[0]))
		await shot(str(spec[1]), 0.9)
	main.goto("settings", "bibliothek")
	await wait(0.6)
	Config.set_rom_dir("ps2", "/usr/share/games/PlayStation 2/Sammlung/Japan-Importe")
	main.sections["settings"].build()
	await wait(0.3)
	focus_key("set:bibliothek:PlayStation 2")
	await shot("p06_pfad", 0.7)
	Config.set_rom_dir("ps2", "")
	main.goto("settings", "info")
	await wait(0.6)
	main.sections["settings"]._data_sheet()
	await shot("p07_datenordner", 0.9)
	await _close_all()
	main.open_dialog("Emulator löschen?", "„PCSX2 (eigen)“ verschwindet aus Uzai. Systeme, die ihn nutzen, brauchen danach einen anderen Emulator.", [
		["Löschen", func() -> void: pass, "danger"],
		["Behalten", func() -> void: pass],
	])
	await shot("p08_loeschen", 0.7)
	await press("left")
	await shot("p09_loeschen_rot", 0.4)
	await _close_all()
	for th in ["papier", "ps2", "bernstein"]:
		Config.set_value("theme.preset", th)
		await wait(1.2)
		main.goto("settings", "aussehen")
		await shot("p10_schema_%s" % th, 1.0)
	Config.set_value("theme.preset", "theme")
	await wait(1.0)
	# Große Oberfläche: rechts muss Platz für die Erklärung bleiben.
	Config.set_value("theme.ui_scale", 1.3)
	await wait(1.2)
	main.goto("settings", "aussehen")
	await shot("p11_gross", 1.0)
	Config.set_value("theme.ui_scale", 1.0)
	await wait(1.0)


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().process_frame
	await wait(0.25)


# --- Startbild -----------------------------------------------------------------------

func _boot() -> void:
	# Nicht unter main hängen: ein Neuaufbau (Farbschema) räumt dort alles ab.
	await wait(0.5)
	for mode in ["voll", "kurz"]:
		var b: Control = BootC.new().setup(mode)
		get_tree().root.add_child(b)
		b.set_process(false)
		var times: Array = [0.25, 0.55, 0.85, 1.1, 1.5, 2.0, 2.6, 3.3] if mode == "voll" else [0.5, 1.0, 1.5, 2.0]
		for t in times:
			b.set("_t", t)
			b.queue_redraw()
			await shot("boot_%s_%02d" % [mode, int(t * 10)], 0.12)
		b.queue_free()
		await wait(0.2)
	var r: Control = BootC.new().setup("roehre")
	get_tree().root.add_child(r)
	r.set_process(false)
	for t2 in [0.4, 0.8, 1.4, 2.2]:
		r.set("_t", t2)
		r.queue_redraw()
		await shot("boot_roehre_%02d" % int(t2 * 10), 0.12)
	r.queue_free()
	await wait(0.2)
	# Helles Farbschema: Zeichen und Schrift müssen auch dort klar stehen.
	Config.set_value("theme.preset", "papier")
	await wait(1.0)
	var lb: Control = BootC.new().setup("voll")
	get_tree().root.add_child(lb)
	lb.set_process(false)
	lb.set("_t", 2.2)
	lb.queue_redraw()
	await shot("boot_papier_22", 0.15)
	lb.queue_free()
	main.open_layer(WelcomeC.new())
	await shot("boot_papier_willkommen", 1.0)
	await _close_all()
	Config.set_value("theme.preset", "theme")
	await wait(1.0)


# --- Einstellungen ---------------------------------------------------------------------

func _settings() -> void:
	main.goto("settings", "aussehen")
	await shot("s01_aussehen", 0.9)
	await press("down", 12)
	await shot("s04_aussehen_unten", 0.6)
	await press("down", 12)
	await shot("s05_aussehen_ende", 0.6)
	# Bewegung ohne Neuaufbau: Controller-Seite (Wechselwert, Schalter, Schieber).
	main.goto("settings", "controller")
	await wait(0.8)
	await press("right")
	await shot("m01_wechsel_mitte", 0.07)
	await shot("m02_wechsel_fertig", 0.4)
	await press("left")
	await press("down")
	await press("a")
	await shot("m03_schalter_mitte", 0.09)
	await shot("m04_schalter_an", 0.4)
	await press("a")
	await press("down", 3)
	await shot("m05_schieber", 0.4)
	await press("right")
	await shot("m06_schieber_mitte", 0.08)
	await shot("m07_schieber_fertig", 0.4)
	await press("left")
	await wait(0.3)
	for sub in ["bibliothek", "systeme", "emulatoren", "bildfilter", "konten", "videos", "controller", "system", "info"]:
		main.goto("settings", sub)
		await shot("s10_%s" % sub, 0.9)
	main.goto("settings", "bibliothek")
	await wait(0.5)
	await press("down", 14)
	await shot("s11_bibliothek_unten", 0.6)
	await press("down", 14)
	await shot("s12_bibliothek_ende", 0.6)
	main.goto("settings", "konten")
	await wait(0.5)
	await press("down", 12)
	await shot("s13_konten_unten", 0.6)
	main.goto("settings", "system")
	await wait(0.5)
	await press("down", 20)
	await shot("s14_system_ende", 0.6)
	main.goto("settings", "info")
	await wait(0.5)
	await press("down")
	await shot("s15_info_datenordner", 0.5)
	main.goto("settings", "systeme")
	await wait(0.6)
	await press("y")
	await shot("s20_system_blatt", 0.8)
	await _close_all()
	main.goto("settings", "bildfilter")
	await wait(0.5)
	main.sections["settings"]._filter_sheet("crt480")
	await shot("s21_filter_blatt", 0.8)
	await _close_all()


# --- Ebenen ---------------------------------------------------------------------------

func _layers() -> void:
	main.goto("settings", "system")
	await wait(0.6)
	# Startfehler
	var g: Dictionary = Library.get_game(Library.recent(1)[0].id)
	main._on_game_failed(g, "Für PlayStation 2 ist noch kein Emulator eingerichtet. Unter Einstellungen → Emulatoren den Pfad zu PCSX2 eintragen.")
	await shot("l01_startfehler", 0.12)
	await shot("l01b_startfehler", 0.6)
	await press("right")
	await shot("l01c_startfehler_zweiter", 0.4)
	await _close_all()
	main.open_dialog("Bilder von SteamGridDB", "Für 42 Spiele. Das dauert ein paar Minuten, Uzai bleibt dabei bedienbar.", [
		["Nur fehlende ergänzen", func() -> void: pass],
		["Alles ersetzen", func() -> void: pass],
		["Abbrechen", func() -> void: pass],
	])
	await shot("l02_dialog_drei", 0.6)
	await _close_all()
	main.open_dialog("Emulator löschen?", "„PCSX2 (eigen)“ verschwindet aus Uzai. Systeme, die ihn nutzen, brauchen danach einen anderen Emulator.", [
		["Löschen", func() -> void: pass],
		["Abbrechen", func() -> void: pass],
	])
	await shot("l03_dialog_loeschen", 0.6)
	await _close_all()
	# Willkommen
	main.open_layer(WelcomeC.new())
	await shot("l04_willkommen", 0.15)
	await shot("l04b_willkommen", 0.8)
	await press("down")
	await shot("l04c_willkommen_zwei", 0.4)
	await _close_all()
	# Auswahlliste
	main.open_choice("Welcher Bereich soll nach vorne?",
			[["games", "Spiele"], ["shop", "Shop"], ["achievements", "Erfolge"], ["friends", "Freunde"], ["music", "Musik"], ["videos", "Videos"]], "music",
			func(_v: Variant) -> void: pass)
	await shot("l05_auswahl", 0.7)
	await _close_all()
	main.sections["settings"]._new_emulator()
	await shot("l06_neuer_emulator", 0.7)
	await _close_all()
	# Tastatur
	main.open_keyboard("Name des Ordners", "Klassiker", func(_t: String) -> void: pass)
	await shot("l10_tastatur", 0.15)
	await shot("l10b_tastatur", 0.6)
	await press("down", 3)
	await press("right", 4)
	await shot("l11_tastatur_unten", 0.4)
	await press("lt")
	await shot("l12_tastatur_gross", 0.4)
	await press("rt")
	await shot("l13_tastatur_zeichen", 0.4)
	await _close_all()
	main.open_keyboard("Web-API-Schlüssel", "a1b2c3d4e5", func(_t: String) -> void: pass, true, "https://retroachievements.org/settings")
	await wait(0.4)
	var kb: Control = Nav.top_layer()
	if kb and kb.has_method("_phone"):
		if _phone_arity(kb) > 0:
			kb.call("_phone", "192.168.178.24")
		else:
			kb.call("_phone")
	await shot("l14_tastatur_handy", 0.8)
	await _close_all()
	# Farbwahl
	main.open_color_picker("Akzentfarbe", UzTheme.col("accent"), func(_c: Color) -> void: pass)
	await shot("l20_farbe", 0.7)
	await press("down")
	await shot("l21_farbe_regler", 0.4)
	await press("right", 3)
	await shot("l22_farbe_gedreht", 0.4)
	await _close_all()
	# Dateiauswahl
	main.open_file_browser("Ordner für PlayStation 2", true, func(_p: String) -> void: pass, [], "/usr")
	await shot("l30_ordner", 0.8)
	await press("down", 2)
	await shot("l31_ordner_runter", 0.4)
	await _close_all()
	main.open_file_browser("Programmdatei wählen", false, func(_p: String) -> void: pass, ["svg", "cfg", "godot", "md"], ProjectSettings.globalize_path("res://"))
	await shot("l32_datei", 0.8)
	await _close_all()
	main.open_file_browser("Ordner wählen", true, func(_p: String) -> void: pass, [], "")
	await shot("l33_laufwerke", 0.8)
	await _close_all()


func _phone_arity(n: Object) -> int:
	for m in n.get_method_list():
		if str(m.name) == "_phone":
			return (m.args as Array).size()
	return 0


# --- Mitteilungen ------------------------------------------------------------------------

func _toasts() -> void:
	main.goto("games")
	await wait(1.0)
	Toasts.show_toast("Controller verbunden", "Xbox Wireless Controller", "controller")
	await shot("t01_toast_einflug", 0.1)
	await shot("t02_toast_da", 0.5)
	Toasts.show_toast("Bildschirmfoto gespeichert", "Okami_2026-10-15_10-41.png", "camera", { "sound": "shutter" })
	await shot("t03_zwei_einflug", 0.12)
	Toasts.show_toast("Spiel nicht gefunden", "Die Verknüpfung zeigt auf ein Spiel, das nicht mehr in der Bibliothek ist.", "warning")
	await shot("t04_drei", 0.6)
	await wait(4.0)
	await shot("t05_ausflug", 0.1)
	await wait(1.5)
	Toasts.show_toast("Mira ist online", "spielt ELDEN RING", "friends", { "color": "ok" })
	await shot("t06_freund", 0.6)
