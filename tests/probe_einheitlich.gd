extends "res://tests/probe_base.gd"
## Probe „Einheitlich“: dieselben Ebenen vorher und nachher in Graphit, Deutsch, 1920 × 1080 –
## Einstellungen (Hauptseite, „Mehr …“, Unterseite), Auswahl, Dialoge, Spiel-Optionen und
## -Einstellungen, Backlog, Sammel-Aktionen, Freunde-Aktionen, Ausschalten, Mitteilungen, Profile,
## Doktor, Einrichtung, Tastatur, Medien (Musik, Videos, Filme, Shop) und das Zimmer.
## Teil über UZAI_E_TEIL: „menues“, „medien“, „zimmer“, „seiten“ (leer: alle). Läuft auf altem und neuem
## Stand gleich (fehlende Funktionen werden übersprungen).

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const BacklogFlow := preload("res://src/ui/backlog_flow.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	await wait(1.0)
	var teil := OS.get_environment("UZAI_E_TEIL")
	if teil == "" or teil == "menues":
		await _menues()
	if teil == "" or teil == "medien":
		await _medien()
	if teil == "" or teil == "zimmer":
		await _zimmer()
	if teil == "" or teil == "seiten":
		await _seiten()


func _menues() -> void:
	# --- Einstellungen ---------------------------------------------------------------------------
	var sv = main.sections["settings"]
	main.goto("settings", "aussehen")
	await wait(1.2)
	var first := Nav.default_in(sv._list)
	if first:
		Nav.focus(first, true)
	await shot("set_aussehen", 0.7)
	main.goto("settings", "system")
	await wait(1.0)
	first = Nav.default_in(sv._list)
	if first:
		Nav.focus(first, true)
	await press("down", 2)
	await shot("set_system", 0.6)
	if sv._mores.has("Mehr"):
		sv.open_more("Mehr")
		await wait(1.2)
		await shot("set_mehr", 0.4)
		await _close_all()
	main.goto("settings", "spiele")
	await wait(1.0)
	if sv.has_method("_system_sheet"):
		sv._system_sheet("ps2")
		await wait(1.2)
		await shot("set_unterseite", 0.4)
		await _close_all()
	# --- Auswahl und Dialoge ---------------------------------------------------------------------
	main.goto("games", "zuletzt")
	await wait(0.8)
	main.open_choice("Sprache", [["de", "Deutsch"], ["en", "English", "Englisch"], ["fr", "Français"]], "de", func(_v) -> void: pass)
	await shot("auswahl", 0.7)
	await _close_all()
	main.ask_quit_uzai()
	await shot("dialog", 0.7)
	await _close_all()
	main.open_dialog("Aus Uzai entfernen?", "„Celeste“ verschwindet aus der Bibliothek. Das Spiel selbst bleibt auf dem PC.", [
		["Entfernen", func() -> void: pass, "danger"], ["Behalten", func() -> void: pass]], "trash")
	await shot("dialog_loeschen", 0.7)
	await _close_all()
	# --- Spiel-Menüs -----------------------------------------------------------------------------
	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	main.open_game_options(g)
	await wait(1.2)
	await shot("spieloptionen", 0.4)
	var go = Nav.top_layer()
	if go and go.has_method("_open_advanced"):
		go._open_advanced()
		await wait(1.2)
		await shot("spieleinstellungen", 0.4)
	await _close_all()
	BacklogFlow.open_sheet(main, g)
	await wait(1.2)
	await shot("backlog", 0.4)
	await _close_all()
	main.open_library("zuletzt", "Zuletzt")
	await wait(1.6)
	var lg = Nav.top_layer()
	if lg and lg.has_method("_set_select"):
		lg.call("_set_select", true)
		await wait(4.2)
		lg.call("_pick_all")
		await wait(0.3)
		lg.call("_open_bulk")
		await wait(1.2)
		await shot("sammel", 0.4)
	await _close_all()
	# --- Freunde, Ausschalten, Mitteilungen, Profile ---------------------------------------------
	if not Social.steam_friends.is_empty():
		main.open_friend(Social.steam_friends[0])
		await wait(1.2)
		await shot("freund", 0.4)
		await _close_all()
	main.open_power()
	await shot("ausschalten", 1.0)
	await _close_all()
	main.open_notifications()
	await shot("mitteilungen", 1.0)
	await _close_all()
	main.open_profiles("switch")
	await shot("profile", 1.2)
	await _close_all()
	main.open_doktor()
	await shot("doktor", 1.4)
	await _close_all()
	main.open_keyboard("Spiel suchen", "Zelda", func(_t: String) -> void: pass)
	await shot("tastatur", 0.8)
	await _close_all()
	Wizard.open_for(main, true)
	await shot("einrichtung_1", 2.4)
	await press("a")
	await shot("einrichtung_2", 1.4)
	await _close_all()


func _medien() -> void:
	# --- Guide (darf sich nicht ändern) ------------------------------------------------------------
	main.goto("games", "zuletzt")
	await wait(0.8)
	main.toggle_guide()
	await shot("guide_start", 1.6)
	await _close_all()
	main.toggle_guide("system")
	await shot("guide_system", 1.4)
	await _close_all()
	main.toggle_guide("musik")
	await shot("guide_musik", 1.4)
	await _close_all()
	# --- Musik -----------------------------------------------------------------------------------
	main.goto("music", "jetzt")
	await shot("musik_jetzt", 1.6)
	main.open_music_actions()
	await shot("musik_menue", 1.0)
	await _close_all()
	# --- Videos ------------------------------------------------------------------------------------
	main.goto("videos", "fuerdich")
	await wait(1.4)
	await press("down")
	await press("y")
	await shot("video_optionen", 0.9)
	await _close_all()
	# --- Filme -------------------------------------------------------------------------------------
	main.goto("movies", "start")
	await wait(1.2)
	var rows: Array = await Movies.call("home_rows")
	if not rows.is_empty() and not (rows[0].items as Array).is_empty():
		main.open_movie((rows[0].items as Array)[0])
		await shot("film_detail", 1.6)
		await _close_all()
	# --- Shop --------------------------------------------------------------------------------------
	main.goto("shop", "entdecken")
	await wait(2.0)
	var view = main.sections["shop"]
	if view.has_method("open_item"):
		view.open_item(Store.known_item(753640))
		await shot("shop_spiel", 2.4)
		await _close_all()


func _zimmer() -> void:
	main.goto("games")
	await wait(0.8)
	main.open_room(true)
	await wait(3.0)
	await shot("zimmer_laufen", 1.4)
	await press("menu")
	await shot("zimmer_menue", 1.0)
	await press("b")
	await wait(0.6)
	await press("y")
	await shot("zimmer_einrichten", 1.2)
	await press("rt")
	await shot("zimmer_katalog", 1.8)
	await press("b")
	await wait(0.5)
	await press("b")
	await wait(0.6)


## Seiten mit vielen Knöpfen (nicht im Auftrag einzeln genannt, aber derselbe Knopf überall).
func _seiten() -> void:
	main.goto("games", "zuletzt")
	await wait(0.8)
	main.open_game(Library.get_game("steam:1245620"), true)
	await shot("spielseite", 2.2)
	await _close_all()
	main.goto("friends")
	await shot("freunde_bereich", 1.8)
	main.open_room(true)
	await wait(3.0)
	await press("menu")
	await wait(0.6)
	await press("down", 5)
	await shot("zimmer_menue_unten", 0.8)
	await _close_all()


func _close_all() -> void:
	var n := 0
	while Nav.top_layer() and n < 8:
		Nav.top_layer().close()
		await wait(0.35)
		n += 1
	await wait(0.3)
