extends "res://tests/probe_base.gd"
## Probe für den Rahmen: Kopfleiste, Reiter, Unterreiter, Hinweisleiste, Übergänge, Ebenen.
## Mit --uzai-film zusätzlich Bildfolgen der Übergänge in Zeitlupe (Engine.time_scale), damit
## man die Bewegung trotz langsamer Software-Grafik Bild für Bild beurteilen kann.

var _film := false


func run() -> void:
	_film = "--uzai-film" in OS.get_cmdline_user_args()
	# Wie am Fernseher: Controller-Symbole statt Tastatur.
	Config.set_value("controller.glyphs", "xbox")
	if "--uzai-variants" in OS.get_cmdline_user_args():
		await _variants()
		Config.set_value("controller.glyphs", "auto")
		Config.set_value("theme.preset", "uzai")
		Config.set_value("theme.tabs", "auto")
		Config.save_settings()
		return
	main.goto("games")
	await shot("01_home_pad", 1.4)
	# Cursor auf den Reitern oben
	Nav.focus(main._tab_items["games"], true)
	await shot("02_tabs_focus", 0.6)
	if _film:
		await film("f1_tab_right", 10, func() -> void: Nav._fire("right"))
	else:
		await press("right")
	await shot("03_tab_shop", 0.9)
	await press("right")
	await shot("04_tab_erfolge", 0.9)
	# RT von der Seite aus: Bereichswechsel mit Inhalt
	await press("down")
	await wait(0.4)
	if _film:
		await film("f3_section_rt", 12, func() -> void: Nav._fire("rt"))
	else:
		await press("rt")
	await shot("05_freunde", 0.9)
	await press("rt")
	await shot("06_musik", 0.9)
	main.goto("shop")
	await wait(1.6)
	await press("up")
	await shot("07_shop_chips_focus", 0.6)
	if _film:
		await film("f4_chip_right", 10, func() -> void: Nav._fire("right"))
	else:
		await press("right")
	await shot("08_shop_chip2", 1.0)
	await press("down")
	await wait(0.6)
	if _film:
		await film("f4b_rb_sub", 10, func() -> void: Nav._fire("rb"))
	main.goto("settings")
	await shot("09_settings", 1.0)
	await press("down", 2)
	await shot("10_settings_row", 0.6)
	if _film:
		await _trace_hold("down", 12)
		await wait(0.6)
		await film("f7_hold_up", 24, func() -> void: _hold("up", 8), 0.5, 0.08)
	# Seitenleiste und Dialog
	if _film:
		await film("f5_sheet_open", 10, func() -> void: main.open_notifications())
	else:
		main.open_notifications()
	await shot("11_sheet", 0.8)
	await press("b")
	await wait(0.5)
	var dlg := func() -> void: main.open_dialog("Ordner löschen?", "Die Spiele bleiben in der Bibliothek, nur der Ordner verschwindet.",
			[["Löschen", func() -> void: pass], ["Abbrechen", func() -> void: pass]])
	if _film:
		await film("f6_dialog_open", 10, dlg)
	else:
		dlg.call()
	await shot("12_dialog", 0.8)
	await press("b")
	await wait(0.4)
	main.goto("friends")
	await shot("13_friends", 1.0)
	await press("down")
	await shot("14_friends_row2", 0.5)
	main.goto("achievements")
	await shot("17_erfolge", 1.0)
	main.goto("music")
	await shot("18_musik", 1.0)
	main.goto("games")
	await wait(1.0)
	await press("right", 2)
	await shot("15_home_right", 1.0)
	# Leere Seitenleiste: Hinweise unten nur für die Ebene, A/X/Y wirken nicht dahinter.
	main.open_notifications()
	await shot("19_empty_sheet_hints", 0.8)
	await press("b")
	# Hintergrund lebt: dasselbe Bild 4 s später
	await shot("16_home_later", 4.0)
	# Seitenleiste mit Inhalt, Guide, Tastatur
	await press("y")
	await shot("21_options_sheet", 0.9)
	await press("down", 9)
	await shot("21b_options_scrolled", 0.9)
	await press("b")
	await wait(0.4)
	main.toggle_guide()
	await shot("22_guide", 1.4)
	main.toggle_guide()
	await wait(0.8)
	main.open_keyboard("Spiel suchen", "Zelda", func(_t: String) -> void: pass)
	await shot("23_keyboard", 1.0)
	await press("b")
	await wait(0.5)
	Config.set_value("controller.glyphs", "keys")
	await shot("20_home_keys", 0.8)
	Config.set_value("controller.glyphs", "auto")
	Config.save_settings()


## Varianten der Kopfleiste: Reiter als Symbole, helles Farbschema, PlayStation-Symbole.
func _variants() -> void:
	main.goto("games")
	await wait(1.2)
	Config.set_value("theme.tabs", "symbole")
	await wait(1.2)
	await shot("v1_symbole", 0.5)
	Nav.focus(main._tab_items["games"], true)
	await press("right", 2)
	await shot("v2_symbole_focus", 1.0)
	Config.set_value("theme.tabs", "auto")
	await wait(1.0)
	Config.set_value("theme.preset", "papier")
	await wait(1.2)
	main.goto("settings")
	await wait(1.0)
	await press("down", 2)
	await shot("v3_papier_settings", 0.8)
	Nav.focus(main._tab_items["settings"], true)
	await shot("v4_papier_tabs", 0.8)
	Config.set_value("theme.preset", "uzai")
	await wait(1.2)
	Config.set_value("controller.glyphs", "ps")
	main.goto("friends")
	await shot("v5_ps_glyphs", 1.2)
	Config.set_value("controller.glyphs", "nintendo")
	await shot("v6_nintendo_glyphs", 0.6)


## Scrollweg beim Halten aufzeichnen (jedes Bild: Zeit, Lage) – zeigt, ob die Liste gleichmäßig
## gleitet oder bei jedem Schritt neu anfährt.
func _trace_hold(cmd: String, steps: int) -> void:
	var sc: ScrollContainer = null
	var n: Node = Nav.focused()
	while n:
		if n is ScrollContainer:
			sc = n
			break
		n = n.get_parent()
	if sc == null:
		print("Spur: keine Liste")
		return
	_hold(cmd, steps)
	var t0 := Time.get_ticks_msec()
	var line := PackedStringArray()
	var last := float(sc.scroll_vertical)
	while Time.get_ticks_msec() - t0 < 2600:
		await get_tree().process_frame
		var v := float(sc.scroll_vertical)
		line.append("%d:%d" % [Time.get_ticks_msec() - t0, int(v - last)])
		last = v
	print("Spur ", cmd, " (ms:Schritt px): ", " ".join(line))


## Halten simulieren: Schritt, dann nach Wiederholungsabstand weitere (Spielzeit).
func _hold(cmd: String, steps: int) -> void:
	for i in steps:
		Nav._fire(cmd)
		await get_tree().create_timer(Nav.repeat_ms(i) / 1000.0).timeout


## Bildfolge eines Übergangs in Zeitlupe (¼): Bilder holen, danach speichern.
func film(name: String, frames: int, action: Callable, slow := 0.25, every := 0.075) -> void:
	var imgs: Array[Image] = []
	var stamps: Array[int] = []
	await RenderingServer.frame_post_draw
	imgs.append(get_viewport().get_texture().get_image())
	stamps.append(0)
	Engine.time_scale = slow
	var t0 := Time.get_ticks_msec()
	action.call()
	for i in frames:
		await get_tree().create_timer(every, true, false, true).timeout
		await RenderingServer.frame_post_draw
		imgs.append(get_viewport().get_texture().get_image())
		stamps.append(int((Time.get_ticks_msec() - t0) * slow))
	Engine.time_scale = 1.0
	for i in imgs.size():
		var img := imgs[i]
		img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img.save_png(out.path_join("%s_%02d_%03dms.png" % [name, i, stamps[i]]))
	print("Film: ", name)
