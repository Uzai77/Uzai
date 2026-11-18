extends Node
## Automatischer Rundgang für Bildschirmfotos (nur mit --uzai-test=<ordner>).
## Drückt Tasten wie ein Controller und speichert Bilder aller Bereiche.

var out := ""
var main: Node
var errors := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-test="):
			out = a.substr(12)
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String, wait := 0.5) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Bild: ", name)
	_lint_clip(get_tree().root, name)
	if not TranslationServer.get_locale().begins_with("de"):
		_lint_lang(get_tree().root, name)


## Schatten auf zuschneidenden Knoten zeigen im Kompatibilitäts-Renderer alte Bildreste
## (DESIGN.md › Höhenstufen). Jeder Fund wird einmal gemeldet.
var _clip_seen := {}


func _lint_clip(n: Node, where: String) -> void:
	if n is Control and (n as Control).clip_children != CanvasItem.CLIP_CHILDREN_DISABLED and (n as Control).visible:
		for key in ["panel", "normal", "focus"]:
			var sb: StyleBox = (n as Control).get_theme_stylebox(key) if (n as Control).has_theme_stylebox(key) else null
			if sb is StyleBoxFlat and ((sb as StyleBoxFlat).shadow_size > 0 or (sb as StyleBoxFlat).get_expand_margin(SIDE_LEFT) > 0.0):
				var p := str(n.get_path())
				if not _clip_seen.has(p):
					_clip_seen[p] = true
					errors += 1
					print("Clip-Schatten (", where, "): ", p)
	for c in n.get_children():
		_lint_clip(c, where)


## In einer anderen Sprache: sichtbare Texte, die nach der Übersetzung noch deutsch aussehen.
var _lang_seen := {}
var lang_left := 0
var _german: RegEx


func _lint_lang(n: Node, where: String) -> void:
	if _german == null:
		_german = RegEx.create_from_string("[äöüßÄÖÜ]|\\b(und|oder|der|die|das|nicht|mit|für|ist|eine?|noch|wird|von|auf|im|den|dem|zum|zur|gerade|hier|alle|keine?|Spiele|Einstellungen|Zuletzt|Neu|Weiter|Zurück)\\b")
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	var text := ""
	if n is Label:
		text = (n as Label).text
	elif n is Button:
		text = (n as Button).text
	if text.strip_edges() != "" and n.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED:
		var shown := n.tr(text)
		if _german.search(shown) != null and not _lang_seen.has(shown):
			_lang_seen[shown] = true
			lang_left += 1
			print("Deutsch geblieben (", where, "): ", shown.replace("\n", " ⏎ ").left(160))
	for c in n.get_children():
		_lint_lang(c, where)


func press(cmd: String, times := 1, gap := 0.12) -> void:
	for i in times:
		Nav._fire(cmd)
		await get_tree().create_timer(gap).timeout


func _run() -> void:
	main = get_tree().current_scene
	Config.set_value("theme.preset", "uzai")
	Config.set_value("theme.corners", "rund")
	Config.set_value("theme.cover_shape", "hoch")
	await shot("01_boot", 1.2)
	await get_tree().create_timer(3.8).timeout
	await shot("02_home", 0.6)
	# Disc eingelegt (Demo: Ico, SCES-50760): vorn im Regal mit Plakette, Enter spielt das Abbild.
	Discs.set_disc("SCES-50760", "ps2", "E:\\")
	await shot("02b_disc", 1.2)
	Discs.set_disc("")
	main.sections["games"]._last_by_sub.clear()
	main.goto("games", "zuletzt")
	await get_tree().create_timer(0.8).timeout
	await press("right", 2)
	await shot("03_games_right", 0.6)
	await press("rb")
	await shot("04_ps2", 0.8)
	await press("y")
	await shot("05_options", 0.6)
	await press("b")
	await press("down")
	await shot("06_buttons", 0.4)
	await press("up")
	await press("rb", 4)
	await shot("07_switch", 0.6)
	await press("rb")
	await shot("08_steam", 2.0)
	main.goto("videos")
	await shot("40_videos", 1.2)
	await press("down")
	await shot("41_videos_neu", 0.8)
	await press("right", 2)
	await press("y")
	await shot("42_video_options", 0.6)
	await press("b")
	await press("rb")
	await shot("43_videos_neu", 0.8)
	await press("rb")
	await shot("43b_videos_abos", 0.8)
	await press("rb")
	var vv = main.sections["videos"]
	vv._run_search("retro")
	await shot("44_videos_suche", 1.0)
	main.open_channel("UCpixelbude0000000000b0", "Pixelbude")
	await shot("45_kanal", 1.0)
	await press("b")
	main.open_video(YouTube.feed, 3)
	await shot("46_player", 2.6)
	await press("right", 3, 0.1)
	await shot("47_player_seek", 0.3)
	await press("y")
	await shot("48_player_optionen", 0.6)
	await press("b")
	await press("a")
	await shot("49_player_pause", 0.5)
	main.toggle_guide()
	await shot("50_guide_video", 0.9)
	await press("lb")
	await shot("50b_guide_video_reiter", 0.7)
	main.toggle_guide()
	await get_tree().create_timer(0.6).timeout
	await press("b")
	await get_tree().create_timer(0.6).timeout
	main.open_yt_login()
	await shot("51_login_einrichten", 0.8)
	var login = Nav.top_layer()
	login._info = { "url": "https://www.google.com/device", "user_code": "KXRT-PWQB", "device_code": "x", "interval": 999, "expires": 1800 }
	login._until = Time.get_unix_time_from_system() + 1800
	login._state = "code"
	login._refill()
	await shot("52_login_qr", 0.8)
	login._state = "x"
	await press("b")
	# Streams (Twitch): Startseite, Reihen, Kategorien, Kanalseite, Anmeldung.
	main.goto("streams", "start")
	await shot("55_streams", 1.4)
	await press("down")
	await shot("55a_streams_reihe", 0.8)
	main.goto("streams", "kategorien")
	await shot("55b_streams_kategorien", 0.9)
	main.open_stream_channel("pixelbude", "Pixelbude")
	await shot("55c_streams_kanal", 1.0)
	await press("b")
	await get_tree().create_timer(0.4).timeout
	main.open_twitch_login()
	await shot("55d_streams_anmeldung", 0.8)
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().create_timer(0.3).timeout
	# Filme (wie Nuvio): Startseite, breite Karte, Detailseite, Quellen.
	main.goto("movies", "start")
	await shot("57_filme", 1.6)
	await press("down")
	await shot("57a_filme_karte", 1.0)
	await press("a")
	await shot("57b_filme_detail", 1.4)
	await press("a")
	await shot("57d_filme_quellen", 2.0)
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().create_timer(0.3).timeout
	main.goto("achievements")
	await shot("10_achievements", 0.6)
	await press("rt")
	await shot("11_friends", 0.6)
	await press("rt")
	await shot("12_music", 0.6)
	main.goto("shop")
	await shot("13_shop", 4.0)
	await press("a")
	await shot("14_shop_detail", 2.5)
	await press("b")
	main.goto("settings")
	await shot("15_settings", 0.6)
	# Einstellungen: links die Kategorien, rechts geht es hinein, LB/RB blättert weiter.
	await press("right")
	await press("down", 3)
	await shot("16_settings_down", 0.4)
	await press("rb")
	await shot("17_settings_spiele", 0.6)
	await press("rb")
	await shot("18_settings_emulation", 0.6)
	await press("a")
	await shot("19_system_ps2", 0.7)
	await press("b")
	await press("rb", 2)
	await shot("53_settings_medien", 0.6)
	await press("down", 9)
	await shot("54_settings_medien_unten", 0.5)
	main.sections["settings"].open_more("Addons und Plugins")
	await shot("57c_settings_filme", 0.7)
	await press("b")
	await press("rb", 2)
	await shot("55_settings_imspiel", 0.6)
	main.sections["settings"].open_more("Bildrate ×2")
	await shot("55b_settings_lossless", 0.7)
	await press("b")
	await press("rb")
	await shot("20_controller", 0.6)
	await press("guide")
	await shot("21_guide", 0.8)
	await press("lb")
	await shot("21b_guide_start", 0.7)
	await press("b")
	main.open_keyboard("Spiel suchen", "Zelda", func(_t: String) -> void: pass)
	await shot("22_keyboard", 0.6)
	await press("b")
	main.open_color_picker("Akzentfarbe", UzTheme.col("accent"), func(_c: Color) -> void: pass)
	await shot("23_color", 0.6)
	await press("b")
	main.open_file_browser("Ordner wählen", true, func(_p: String) -> void: pass, [], "/")
	await shot("24_files", 0.6)
	# B geht eine Ordnerebene hoch (hier zu den Laufwerken), erst dort schließt B.
	await press("b")
	await shot("24b_files_hoch", 0.5)
	await press("b")
	main.goto("games", "zuletzt")
	await get_tree().create_timer(0.5).timeout
	await press("a")
	await shot("25_launch_error", 1.0)
	await press("b")
	main.open_game_achievements(Library.get_game("steam:1245620"))
	await shot("26_achievements_game", 0.8)
	await press("b")
	# Guide so zeigen, als liefe ein Spiel
	Launcher.in_game = true
	Launcher.current = Library.get_game(Library.recent(1)[0].id)
	main.toggle_guide()
	await shot("27_guide_ingame", 0.9)
	await press("lb")
	await shot("56_guide_spiel", 0.6)
	await press("down", 2)
	await press("right")
	await shot("56b_guide_lossless", 0.4)
	main.toggle_guide()
	Launcher.in_game = false
	Launcher.current = {}
	await get_tree().create_timer(0.3).timeout
	main.open_library("ps2", "PlayStation 2")
	await shot("28_library", 0.8)
	await press("b")
	# --- 0.3: Ordner, Bilder, Guide, Freunde, Emulatoren, Statistik ---
	main.goto("games", "ps2")
	await shot("60_ps2_ordner", 1.0)
	main.open_library("ordner:auto:ps2:RPG", "RPG")
	await shot("61_ordner_offen", 0.8)
	await press("b")
	main.open_folder_picker("f_demo2")
	await shot("62_ordner_waehlen", 0.8)
	await press("a")
	await shot("62b_ordner_haken", 0.4)
	await press("b")
	var okami := Library.get_game(Library.by_system("ps2")[1].id)
	main.open_game_folders(okami)
	await shot("63_spiel_ordner", 0.6)
	await press("b")
	main.open_art_picker(okami)
	await shot("64_steamgriddb", 0.8)
	await press("b")
	await get_tree().create_timer(0.3).timeout
	main.goto("games", "zuletzt")
	await get_tree().create_timer(0.4).timeout
	main.toggle_guide()
	await shot("65_guide", 1.0)
	await press("a")
	await shot("65b_guide_person", 0.7)
	await press("b")
	await press("rb")
	await shot("65c_guide_musik", 0.6)
	await press("rb", 2)
	await shot("65d_guide_system", 0.6)
	main.toggle_guide()
	await get_tree().create_timer(0.6).timeout
	Launcher.in_game = true
	Launcher.current = Library.get_game("steam:1245620")
	main.toggle_guide("spiel")
	await shot("66_guide_im_spiel", 1.0)
	main.open_friend(Social.steam_friends[0], "steam")
	await shot("67_freund", 0.7)
	await press("b")
	main.open_music_actions()
	await shot("68_musik_menue", 0.7)
	await press("b")
	main.open_notifications()
	await shot("69_mitteilungen", 0.6)
	await press("b")
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(main._guide):
		main._guide.close()
	await get_tree().create_timer(0.3).timeout
	Launcher.in_game = false
	Launcher.current = {}
	await get_tree().create_timer(0.6).timeout
	main.open_friend(Social.discord["1"].members[1], "discord", "1")
	await shot("67b_discord_freund", 0.6)
	await press("b")
	main.goto("settings", "emulatoren")
	await shot("70_emulatoren", 0.8)
	main.sections["settings"]._emu_sheet("eden")
	await shot("70b_eden", 0.7)
	await press("b")
	main.sections["settings"]._new_emulator()
	await shot("71_neuer_emulator", 0.6)
	await press("b")
	main.goto("settings", "systeme")
	await shot("74_systeme", 0.6)
	main.sections["settings"].open_more("Systeme ein- und ausschalten")
	await shot("74b_systeme_schalten", 0.7)
	await press("b")
	main.goto("achievements", "statistik")
	await shot("72_statistik", 0.9)
	await press("down")
	await shot("72b_statistik_cover", 0.7)
	await press("down")
	await shot("72c_statistik_verlauf", 0.7)
	main.goto("achievements", "uebersicht")
	await shot("72e_erfolge", 0.9)
	# Die Demo liefert selbst Erfolge; hier die Liste von RetroAchievements.
	main.goto("achievements", "retro")
	await shot("72f_erfolge_daten", 0.9)
	main.goto("friends")
	await shot("75_freunde", 0.9)
	main.open_keyboard("SteamGridDB-Schlüssel", "", func(_t: String) -> void: pass, true, "https://www.steamgriddb.com/profile/preferences/api")
	await get_tree().create_timer(0.4).timeout
	Nav.top_layer()._phone()
	await shot("73_tastatur_handy", 0.8)
	await press("b")
	main.goto("games", "zuletzt")
	await get_tree().create_timer(0.6).timeout
	Config.set_value("theme.preset", "bernstein")
	await shot("29_theme_bernstein", 1.0)
	Config.set_value("theme.cover_shape", "quer")
	Config.set_value("theme.preset", "graphit")
	await shot("30_theme_quer", 1.2)
	Config.set_value("theme.cover_shape", "hoch")
	Config.set_value("theme.preset", "ps2")
	Config.set_value("theme.corners", "eckig")
	await shot("31_theme_tiefsee", 1.0)
	Config.set_value("theme.preset", "uzai")
	Config.set_value("theme.corners", "rund")
	print("Rundgang fertig, Clip-Schatten: ", errors, (", Deutsch geblieben: %d" % lang_left) if not TranslationServer.get_locale().begins_with("de") else "")
	get_tree().quit()
