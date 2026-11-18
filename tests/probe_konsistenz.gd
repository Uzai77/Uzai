extends "res://tests/probe_base.gd"
## Probe „Konsistenz“ (Roadmap 62): ein Rundgang über alle Bildschirme – Bereiche mit allen
## Unterseiten, Spielseite, Guide-Reiter, Einstellungen, Dialoge, Mitteilungen, Einrichtung,
## Doktor, Profile, Zimmer, Filme-Quellen. Bei jedem Bild prüft sie:
## - Text, der über den Bildschirmrand ragt oder abgeschnitten („…“) wird (nur Oberflächen-
##   texte, keine Namen und Titel der Nutzer),
## - in einer anderen Sprache: Texte, die deutsch geblieben sind,
## - bei jeder Ebene: führt B wieder heraus?
## Umgebung: UZAI_K_SCALE (1.0), UZAI_K_STICH=1 (nur Stichprobe),
## UZAI_K_BILDER=a,b,… (nur diese Bilder speichern – geprüft wird trotzdem alles).
## Sprache über den Datenordner (settings.json mit system.language).

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")

var funde := 0
var _seen := {}
var _german: RegEx
var stich := false


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var sc := OS.get_environment("UZAI_K_SCALE")
	if sc != "" and float(sc) != 1.0:
		Config.set_value("theme.ui_scale", float(sc))
		await wait(1.5)
	stich = OS.get_environment("UZAI_K_STICH") == "1"
	print("Konsistenz: Größe %s, Sprache %s" % [str(UzTheme.ui_scale()), TranslationServer.get_locale()])

	var ab := OS.get_environment("UZAI_K_AB")
	# Bereiche mit allen Unterseiten.
	for sid in ([] if ab != "" else main.order):
		if not main.sections.has(sid):
			continue
		var s = main.sections[sid]
		var subs: Array = s.subtabs()
		if subs.is_empty() or stich:
			main.goto(sid)
			await shot("b_%s" % sid, 1.4)
			continue
		for t in subs:
			main.goto(sid, str(t.id))
			await shot("b_%s_%s" % [sid, str(t.id)], 1.2)
			if sid == "settings":
				# Nur blättern: links/rechts würde Werte umstellen (Sprache, Tastensymbole).
				await press("down", 7, 0.1)
				await shot("b_%s_%s_unten" % [sid, str(t.id)], 0.5)
	main.goto("games")
	await wait(1.0)

	# Spielseite
	main.open_game(Library.get_game("steam:1245620"))
	await shot("e_spielseite", 2.2)
	await press("down")
	await shot("e_spielseite_unten", 0.6)
	await zurueck("Spielseite")

	# Guide mit allen Reitern
	main.toggle_guide()
	await shot("g_guide_0", 1.0)
	for i in 6:
		await press("rb")
		await shot("g_guide_%d" % (i + 1), 0.7)
	main.toggle_guide()
	await wait(0.6)

	# Dialoge und Mitteilungen
	main.open_dialog("Spiel startet nicht", "Der Emulator für PlayStation 2 fehlt. Unter Einstellungen → Emulatoren lässt er sich suchen.", [
		["Emulator suchen", func() -> void: pass, "primary"], ["Abbrechen", func() -> void: pass]], "warning", "warn")
	await shot("d_dialog_fehler", 0.7)
	await zurueck("Dialog")
	main.ask_quit_uzai()
	await shot("d_dialog_beenden", 0.7)
	await zurueck("Beenden-Dialog")
	main.open_power()
	await shot("d_ausschalten", 0.7)
	await zurueck("Ausschalten")
	Toasts.show_toast("Bildschirmfoto ging nicht", "Der Windows-Helfer antwortet nicht. Gleich noch einmal versuchen.", "warning")
	Toasts.show_toast("Aufnahme gespeichert", "Unter Aufnahmen zu finden.", "camera")
	await shot("d_toasts", 1.0)
	main.open_notifications()
	await shot("d_mitteilungen", 0.7)
	await zurueck("Mitteilungen")
	main.open_search("")
	await shot("d_suche", 0.8)
	await zurueck("Suche")
	main.open_keyboard("Spiel suchen", "Zelda", func(_t: String) -> void: pass)
	await shot("d_tastatur", 0.6)
	await zurueck("Tastatur")
	main.open_choice("Sprache", [["de", "Deutsch"], ["en", "English"]], "de", func(_v) -> void: pass)
	await shot("d_auswahl", 0.6)
	await zurueck("Auswahlliste")
	if stich:
		await _ende()
		return

	# Doktor, Profile
	main.open_doktor()
	await shot("e_doktor", 1.2)
	await zurueck("Doktor")
	main.open_profiles("switch")
	await shot("e_profile", 1.0)
	await zurueck("Profile")
	main.open_profiles("manage")
	await shot("e_profile_verwalten", 1.0)
	await zurueck("Profile verwalten")

	# Filme-Quellen
	main.goto("movies", "start")
	await wait(1.0)
	main.open_movie_sources(false)
	await shot("f_quellen", 1.2)
	await zurueck("Filme-Quellen")

	# Einrichtung (B im ersten Schritt bricht ab, wenn aus den Einstellungen geöffnet)
	Wizard.open_for(main, true)
	await shot("w_einrichtung_1", 2.4)
	await press("a")
	await shot("w_einrichtung_2", 1.4)
	await zurueck("Einrichtung Schritt 2", false)
	await zurueck("Einrichtung")

	# Zimmer mit seinen Menüs
	main.goto("games")
	await wait(0.8)
	main.open_room(true)
	await wait(3.0)
	await shot("z_zimmer", 0.8)
	await press("menu")
	await shot("z_zimmer_menue", 0.9)
	await zurueck("Zimmer-Menü")
	await press("lt")
	await shot("z_zimmer_rad", 0.8)
	await press("b")
	await wait(0.6)
	await zurueck("Zimmer")
	await _ende()


func _ende() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.3)
	print("Konsistenz fertig: %d Funde" % funde)


## B drücken und prüfen, dass die oberste Ebene geht (bzw. einen Schritt zurück geht: dann
## gilt jede Änderung der obersten Ebene oder ihres Fokus).
func zurueck(was: String, ganz := true) -> void:
	var vor = Nav.top_layer()
	var fokus = Nav.focused()
	await press("b")
	await wait(0.7)
	var nach = Nav.top_layer()
	if vor != null and nach == vor and (ganz or Nav.focused() == fokus):
		funde += 1
		print("B-Falle: ", was, " (", vor.get_script().resource_path.get_file() if vor.get_script() else vor.name, ")")


func shot(name: String, w := 0.6) -> void:
	var only := OS.get_environment("UZAI_K_BILDER")
	if only == "" or name in only.split(","):
		await super.shot(name, w)
	else:
		await wait(w)
		await RenderingServer.frame_post_draw
	_lint(get_tree().root, name)


func _lint(n: Node, where: String) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if (n is Label or n is Button) and n.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED:
		var c := n as Control
		var text: String = c.get("text")
		if text.strip_edges() != "" and c.size.x > 4 and c.modulate.a > 0.05:
			var shown := c.tr(text)
			var vr := get_viewport().get_visible_rect()
			var r := c.get_global_rect()
			var font: Font = c.get_theme_font("font")
			var fs: int = c.get_theme_font_size("font_size")
			if r.end.x > vr.end.x + 2 or r.position.x < -2:
				_fund("Rand", where, shown, c)
			elif n is Label and not (n as Label).autowrap_mode and (n as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
				var wdt := font.get_string_size(shown.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if wdt > c.size.x + 1.5:
					_fund("abgeschnitten", where, shown, c)
			elif n is Button and (n as Button).clip_text:
				var wdt2 := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if wdt2 > c.size.x + 1.5:
					_fund("abgeschnitten", where, shown, c)
			if not TranslationServer.get_locale().begins_with("de"):
				if _german == null:
					_german = RegEx.create_from_string("[äöüßÄÖÜ]|\\b(und|oder|der|die|das|nicht|mit|für|ist|eine?|noch|wird|von|auf|im|den|dem|zum|zur|gerade|hier|alle|keine?|Spiele|Einstellungen|Zuletzt|Neu|Weiter|Zurück)\\b")
				if _german.search(shown) != null:
					_fund("deutsch", where, shown, c)
	for ch in n.get_children():
		_lint(ch, where)


func _fund(art: String, where: String, text: String, c: Control) -> void:
	var key := art + "|" + text
	if _seen.has(key):
		return
	_seen[key] = true
	funde += 1
	print(
			"Fund %s (%s): %s  [%s, %d px breit]" % [art, where, text.replace("\n", " ⏎ ").left(120), c.get_script().resource_path.get_file() if c.get_script()
			else c.get_parent().get_script().resource_path.get_file() if c.get_parent() and c.get_parent().get_script() else c.get_class(), int(c.size.x)])
