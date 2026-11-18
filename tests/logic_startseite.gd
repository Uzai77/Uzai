extends Node
## Startseite in der Marke (games.gd): Sortierung neben den Quellen, ein Schild je Cover nur in
## gemischten Quellen, Spielzeit unter dem gewählten Cover, die leise Zeile unter dem Titel,
## die Knöpfe im Kopf, „Für dich“ im matten Theme und als Seitenleiste auf Start, der Aufbau nach
## der Einrichtung (startseite_aufbau.gd).
## Aufruf: godot --headless --path . res://tests/logic_startseite.tscn

const Games := preload("res://src/ui/sections/games.gd")
const ForYouCard := preload("res://src/ui/components/for_you_card.gd")
const FuerDichLeiste := preload("res://src/ui/layers/fuer_dich_leiste.gd")
const Aufbau := preload("res://src/ui/sections/startseite_aufbau.gd")
const CoverRow := preload("res://src/ui/components/cover_row.gd")
const U := preload("res://src/ui/u.gd")
const BG := preload("res://src/ui/components/background.gd")
const RetroBuehne := preload("res://src/ui/components/retro_buehne.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var keep_sort: Variant = Config.get_value("library.sort", "recent")
	var gs = Games.new()
	add_child(gs)

	print("Quellenleiste: rechts leise die Sortierung")
	gs.sub = "zuletzt"
	check(gs._count_text(24) == "Sortierung · Zuletzt gespielt", "Zuletzt: immer nach dem letzten Spielen (%s)" % gs._count_text(24))
	gs.sub = "ps2"
	Config.set_value("library.sort", "title")
	check(gs._count_text(3) == "3 Spiele · Sortierung · A bis Z", "andere Quellen: Anzahl und die Sortierung der Bibliothek (%s)" % gs._count_text(3))
	Config.set_value("library.sort", "playtime")
	check(gs._count_text(1).ends_with("Meiste Spielzeit"), "folgt der Einstellung")
	Config.set_value("library.sort", keep_sort)
	check(not gs._count_text(5).contains("›"), "kein „›“: die Zeile ist nicht wählbar")

	print("Ein Schild je Cover, nur in gemischten Quellen")
	for s in ["favoriten", "alle", "ordner:x"]:
		gs.sub = s
		check(gs._mixed_source(), "%s: Plattform-Schild" % s)
	for s2 in ["zuletzt", "ps2", "steam", "pc"]:
		gs.sub = s2
		check(not gs._mixed_source(), "%s: kein Schild (der Reiter sagt es)" % s2)

	print("Startseite ohne Spielzeit")
	# Playtime and "zuletzt" are shown on the game page, not on the home page.
	check(not gs.has_method("_caption"), "keine Spielzeit-Zeile unter dem Cover")
	var src := (load("res://src/ui/sections/games.gd") as GDScript).source_code
	check(not src.contains("U.playtime(pt)") and not src.contains("_last_text("), "keine Spielzeit und kein „zuletzt“ im Kopf")

	print("Zeile unter dem Titel")
	check(Games._stat("Bild", "CRT · 480 Zeilen") == "Bild: CRT, 480 Zeilen", "„ · “ im Wert wird zum Komma")
	var rom := { "id": "ps2:t", "title": "Ico", "source": "rom", "system": "ps2" }
	var parts: Array = gs._info_parts(rom)
	check(not parts.is_empty() and str(parts[0]) == str(Config.system("ps2").get("name", "")), "Emulator-Spiel: zuerst der volle Systemname (%s)" % str(parts))
	var emu := str(Config.emulator(str(Config.system("ps2").get("emulator", ""))).get("name", ""))
	check(emu == "" or parts.has(emu), "dann der Emulator (%s)" % emu)
	gs._hero_w = 980.0
	var holder: Control = gs._build_hero()
	gs.add_child(holder)
	var long_parts := ["PlayStation 2", "PCSX2", "Bild: CRT, 480 Zeilen", "Erfolge: 12 / 40", "Ordner: Eine sehr lange Sammlung von Lieblingsspielen"]
	gs._set_info(long_parts)
	var t: String = gs._tag.text
	check(t.begins_with("PlayStation 2 · PCSX2") and not t.contains("Lieblingsspielen"), "zu lang: hintere Angaben fallen ganz weg (%s)" % t)
	check(not gs._tag.clip_text, "kein Abbruch mitten im Wort")
	gs._set_info(["Kurz"])
	check(gs._tag.text == "Kurz" and not gs._faces.visible, "ohne Freunde keine Gesichter")
	gs._set_info(["Action"], [{ "name": "Mira", "avatar": "" }, { "name": "Jonas", "avatar": "" }])
	check(gs._faces.visible and gs._faces.get_child_count() == 2, "Freunde: Gesichter und „spielen gerade“ hinter der Zeile, ohne Namen im Text")
	check(not gs._tag.text.contains("Mira"), "Namen nicht im (übersetzten) Text")

	print("Kopf ohne Knöpfe")
	check(gs.get("_act_a") == null and not (gs.get_script() as GDScript).source_code.contains("_HeroKey"),
			"keine Knöpfe „Öffnen“/„Optionen“ im Kopf (was A und Y tun, steht in der Tastenzeile)")

	print("„Für dich“ im matten Theme")
	var fy = ForYouCard.new().setup({ "kind": "neu", "title": "Test", "sub": "x", "why": "Neu", "act": func() -> void: pass }, true, Vector2(540, 160))
	add_child(fy)
	check(fy.get("_matt") == UzTheme.matt(), "matt nach dem Theme")
	if UzTheme.matt():
		check(not fy.has_meta("uz_shiny"), "matt: kein Lichtstreif")
		check(fy.get("_r") == UzTheme.r_panel(), "matt und streng: Kartenradius (%d)" % int(fy.get("_r")))
		fy.focus_entered.emit()
		await get_tree().create_timer(0.4).timeout
		check(float(fy.get("_lift")) < 0.0, "matt: gewählt hebt sich die Karte (Tiefe statt Rahmen)")
	fy.queue_free()

	print("„Für dich“ als Seitenleiste auf Start")
	check(gs.get("_foryou") == null, "nicht mehr auf der Startseite (Kopf ohne Block rechts)")
	check(gs.has_method("menu_taste"), "Start auf der Startseite: eigene Menü-Taste (main.gd)")
	var hs: Array = gs.extra_hints(null)
	check(Library.visible_games().is_empty() or (hs.size() == 1 and str(hs[0][0]) == "menu" and str(hs[0][1]) == "Für dich"),
			"Tastenzeile: Start heißt „Für dich“ (%s)" % str(hs))
	var main_src := (load("res://src/main.gd") as GDScript).source_code
	var mz := main_src.find("\t\t\"menu\":")
	check(mz > 0 and main_src.find("menu_taste()", mz) < main_src.find("open_game_options(", mz),
			"Menü-Taste des Bereichs vor den Spiel-Optionen (Start ist nicht mehr dasselbe wie Y)")
	var getan: Array = []
	var plan := { "big": { "key": "weiter", "kind": "weiter", "title": "Ico", "why": "Weiterspielen", "hint": "Spielen",
			"act": func() -> void: getan.append("a"), "y_act": func() -> void: getan.append("y") },
		"small": [{ "key": "neu", "kind": "neu", "title": "Neu", "why": "Neu", "sub": "Gestern hinzugefügt", "act": func() -> void: getan.append("n") },
			{ "key": "woche", "kind": "woche", "title": "Woche", "why": "Deine Woche", "act": func() -> void: pass }] }
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var ld = FuerDichLeiste.new()
	ld.plan = plan
	ld.extra = { "freunde": [{ "key": "fr:1", "title": "Mira", "extra": "Celeste", "person": { "name": "Mira" }, "hint": "Mitspielen",
		"act": func() -> void: getan.append("f") }] }
	ld.open(host)
	await get_tree().create_timer(0.3).timeout
	var karten: Array = Nav.focusables(ld.content).filter(func(c: Control) -> bool: return c is ForYouCard)
	var zeilen: Array = Nav.focusables(ld.content).filter(func(c: Control) -> bool: return c is GuideRow)
	check(karten.size() == 1 and karten[0].get("big") == true, "oben groß der „Weiter“-Moment (%d Karten)" % karten.size())
	check(zeilen.size() == 3, "darunter Zeilen der Listen-Sprache statt Karten (%d)" % zeilen.size())
	var texte := _texte(ld.content)
	check(texte.has("Freunde spielen") and texte.has("Deine Woche"), "Abschnitte nur mit Inhalt, mit Etikett (%s)" % str(texte.slice(0, 8)))
	check(texte.find("Freunde spielen") < texte.find("Neu in deiner Bibliothek") and texte.find("Neu in deiner Bibliothek") < texte.find("Deine Woche")
			and not texte.has("Fast geschafft"), "feste Reihenfolge, leere Abschnitte fehlen")
	check(zeilen.size() == 3 and zeilen[0].global_position.y > karten[0].global_position.y + 100.0, "Zeilen unter der Karte")
	check(ld.panel.anchor_left == 1.0, "kommt von rechts (sheet.gd)")
	check(Nav.top_layer() == ld and Nav.focused() == karten[0], "die große Karte ist gewählt")
	check(karten.size() == 1 and karten[0].has_meta("uz_on_y"), "Y bei Spielen: zur Spielseite")
	if karten.size() == 1:
		karten[0].activate()
	check(getan == ["a"], "A führt die Handlung aus (%s)" % str(getan))
	check(ld.get("_closing") == true and Nav.top_layer() != ld, "… und schließt die Leiste")
	await get_tree().create_timer(0.3).timeout
	var ldz = FuerDichLeiste.new()
	ldz.plan = plan
	ldz.extra = {}
	ldz.open(host)
	await get_tree().create_timer(0.3).timeout
	var zz: Array = Nav.focusables(ldz.content).filter(func(c: Control) -> bool: return c is GuideRow)
	check(zz.size() == 2 and str(zz[0].get_meta("uz_hint_a", "")) != "", "Zeile mit Hinweis für A")
	if zz.size() == 2:
		zz[0].activate()
	check(getan == ["a", "n"] and ldz.get("_closing") == true, "A auf einer Zeile führt aus und schließt (%s)" % str(getan))
	var ld2 = FuerDichLeiste.new()
	ld2.plan = {}
	ld2.extra = {}
	ld2.open(host)
	await get_tree().create_timer(0.3).timeout
	check(ld2.content.get_child_count() >= 1, "ohne Karten eine leise Zeile statt einer leeren Leiste")
	check(ld2.nav_command("menu") and ld2.get("_closing") == true, "Start schließt die Leiste")
	var ld3 = FuerDichLeiste.new()
	ld3.plan = plan
	ld3.extra = {}
	ld3.open(host)
	await get_tree().create_timer(0.3).timeout
	check(ld3.nav_command("b") and ld3.get("_closing") == true, "B schließt die Leiste")
	await get_tree().create_timer(0.4).timeout
	host.queue_free()

	await _aufbau()

	print("Hintergrund: weiche Fassung")
	check(not Media.has_soft("", 22), "ohne Datei keine weiche Fassung")

	print("Retro-Bühne auf der Startseite")
	var vs := Vector2(1920, 1080)
	var rb: Rect2 = BG.retro_box(vs, BG.stage_rect())
	check(is_equal_approx(rb.end.x, 1824.0), "rechts bündig mit dem Seitenrand (%s)" % [rb])
	check(rb.position.y >= 110.0 and rb.end.y <= 530.0, "unter der Kopfleiste, über den Quellen (%s)" % [rb])
	check(rb.position.x >= BG.stage_rect().position.x * vs.x and rb.size.x <= rb.size.y * 4.0 / 3.0 + 0.5, "im Spielbild, höchstens 4 : 3")
	var gba: Rect2 = RetroBuehne.schirm_rect(Vector2i(240, 160), rb, 1.0)
	check(gba.size == Vector2(480, 320) and is_equal_approx(gba.end.x, rb.end.x), "Game Boy Advance zweifach, rechts bündig (%s)" % [gba])
	check(absf(gba.get_center().y - rb.get_center().y) <= 1.0, "senkrecht mittig")
	check(BG.retro_box(vs, Rect2(0.5, 0.0, 0.5, 0.6)).end.x <= 1824.0, "anderes Theme: folgt dessen Fläche")
	var bg_src := (load("res://src/ui/components/background.gd") as GDScript).source_code
	check(bg_src.contains("elif MediaS.hero_tauglich(MediaS.orig_groesse(sh)):") and bg_src.contains("_show_retro(game, key, sh)"),
			"große breite Szene als Hero, sonst Retro-Bühne (kein Strecken)")
	var gs_src := (load("res://src/ui/sections/games.gd") as GDScript).source_code
	check(gs_src.contains("show_game(g, soft_bg(), true)"), "nur die Startseite zeigt den Bildschirm")

	gs.queue_free()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Eingaben, die nach dem Aufbau bei der Steuerung ankommen (liegt im Baum vor ihm, hört also danach).
class _Lauscher extends Node:
	var tasten: Array = []

	func _input(e: InputEvent) -> void:
		if e is InputEventKey and e.is_pressed():
			tasten.append((e as InputEventKey).keycode)


## Startseite zum Ausprobieren: was main.gd und games.gd dem Aufbau geben (Leiste, Kopf, Regal …).
func _buehne_bauen(lauscher: Node) -> Dictionary:
	var gd := GDScript.new()
	gd.source_code = "extends Control\nvar background\nvar top_bar\nvar brand_mark\nvar tabs_box\nvar kopf_status\nvar hint_hud\nvar shell\n"
	gd.reload()
	var bgs := GDScript.new()
	bgs.source_code = "extends Control\nvar raum := -1.0\nvar bild := -1.0\nfunc aufbau(r: float, b: float) -> void:\n\traum = r\n\tbild = b\n"
	bgs.reload()
	var karte := GDScript.new()
	karte.source_code = "extends Control\nvar game := {}\nvar spiegel := 1.0\n"
	karte.reload()
	add_child(lauscher)
	var m: Control = gd.new()
	m.size = Vector2(1920, 1080)
	add_child(m)
	m.background = bgs.new()
	m.add_child(m.background)
	m.shell = VBoxContainer.new()
	m.shell.size = Vector2(1920, 1080)
	m.add_child(m.shell)
	m.top_bar = MarginContainer.new()
	m.shell.add_child(m.top_bar)
	var row := HBoxContainer.new()
	m.top_bar.add_child(row)
	for n in ["brand_mark", "tabs_box", "kopf_status"]:
		var c := Control.new()
		c.custom_minimum_size = Vector2(120, 30)
		row.add_child(c)
		m.set(n, c)
	var sec := VBoxContainer.new()
	sec.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.shell.add_child(sec)
	var titel := Label.new()
	titel.text = "Ico"
	sec.add_child(titel)
	var regal = CoverRow.new().setup("covers:test", 34, true, 40, 96, 46)
	regal.custom_minimum_size.x = 1920
	sec.add_child(regal)
	for id in ["a", "b", "c"]:
		var k: Control = karte.new()
		k.game = { "id": id }
		k.custom_minimum_size = Vector2(200, 280)
		k.size = Vector2(200, 280)
		regal.add(k)
	m.hint_hud = Control.new()
	m.add_child(m.hint_hud)
	return { "main": m, "titel": titel, "regal": regal, "sec": sec }


func _aufbau() -> void:
	print("Aufbau nach der Einrichtung")
	var keep_ruhig: Variant = Config.get_value("theme.reduce_motion", false)
	var keep_leicht: bool = Aufbau.Leicht.active
	Config.set_value("theme.reduce_motion", false)
	Aufbau.Leicht.active = false
	var lauscher := _Lauscher.new()
	var b := _buehne_bauen(lauscher)
	await get_tree().process_frame
	await get_tree().process_frame
	var m: Control = b.main
	var regal: Control = b.regal
	var karten: Array = regal.items()
	var ruhe_marke: Vector2 = m.brand_mark.position
	var a: Node = Aufbau.new()
	m.add_child(a)
	a.set_process(false)
	var signale: Array = []
	a.bereit.connect(func() -> void: signale.append("bereit"))
	a.fertig.connect(func() -> void: signale.append("fertig"))
	a.start(m, b.sec, { "kopf": [b.titel], "regal": regal }, ["b"])
	check(not a.kurz, "normal: der ganze Aufbau")
	check(m.top_bar.modulate.a == 0.0 and b.titel.modulate.a == 0.0 and m.hint_hud.modulate.a == 0.0 and m.background.raum == 0.0,
			"„Los“: Leiste, Titel, Tastenzeile und Licht stehen noch nicht da")
	check(is_equal_approx(m.brand_mark.position.y, ruhe_marke.y - U.W_ORT), "die Marke steht W_ORT über ihrem Platz (%s)" % str(m.brand_mark.position))
	check(float(karten[0].get_meta("uz_ein", 1.0)) == 0.0 and karten[0].modulate.a == 0.0 and karten[1].modulate.a == 0.0, "die Cover sind noch nicht da")
	var ab_b: float = a.flug_ab("b")
	check(ab_b > 0.0 and ab_b < Aufbau.AB_LEISTE, "das Cover aus der Einrichtung fliegt gleich nach „Los“ los – es wartet nicht im Raum (%.2f s)" % ab_b)
	check(a.flug_ab("a") == 0.0, "nur Cover aus der Einrichtung fliegen")
	a.seek(Aufbau.AB_BILD)
	check(m.background.raum > 0.3 and m.background.bild == 0.0, "zuerst Licht und Raum, das Spielbild danach")
	a.seek(Aufbau.AB_COVER)
	check(m.top_bar.modulate.a == 1.0 and m.brand_mark.position == ruhe_marke, "die Leiste steht, bevor die Cover kommen")
	check(b.titel.modulate.a == 1.0 and karten[0].modulate.a == 0.0, "Kopf vor den Covern")
	a.seek(Aufbau.AB_SPIEGEL)
	check(karten[0].modulate.a == 1.0 and karten[0].spiegel == 0.0, "das erste Cover steht, seine Spiegelung kommt zuletzt")
	a.seek(Aufbau.AB_SPIEGEL + 0.12)
	check(karten[2].modulate.a == 1.0 and not karten[2].has_meta("uz_ein"), "die übrigen Cover stehen gestaffelt an ihrem Platz")
	check(karten[1].modulate.a == 0.0, "das Cover aus der Einrichtung wartet auf seine Landung (kein doppeltes Bild)")
	a.gelandet("b")
	check(karten[1].modulate.a == 0.0, "gelandet: das echte Cover kommt erst (das der Einrichtung kreuzt aus)")
	a.seek(Aufbau.AB_SPIEGEL + 0.12 + U.T_ORT)
	check(karten[1].modulate.a == 1.0 and not karten[1].has_meta("uz_ein"), "… und steht nach T_ORT an seinem Platz")
	check(m.hint_hud.modulate.a == 0.0 and signale.is_empty(), "Tastenzeile und Fokus erst am Ende")
	a.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_F24
	ev.pressed = true
	get_viewport().push_input(ev)
	check(signale == ["bereit", "fertig"], "eine Eingabe beendet den Aufbau sofort (%s)" % str(signale))
	check(m.hint_hud.modulate.a == 1.0 and karten[0].spiegel == 1.0 and m.background.bild == 1.0, "… und alles steht")
	check(lauscher.tasten.has(KEY_F24), "die Eingabe wird nicht verschluckt (geht weiter an die Steuerung)")
	m.queue_free()
	lauscher.queue_free()
	await get_tree().process_frame

	print("Aufbau: Animationen reduzieren")
	Config.set_value("theme.reduce_motion", true)
	var b2 := _buehne_bauen(_Lauscher.new())
	await get_tree().process_frame
	await get_tree().process_frame
	var m2: Control = b2.main
	var ruhe2: Vector2 = m2.brand_mark.position
	var a2: Node = Aufbau.new()
	m2.add_child(a2)
	a2.set_process(false)
	a2.start(m2, b2.sec, { "kopf": [b2.titel], "regal": b2.regal }, ["b"])
	check(a2.kurz and m2.brand_mark.position == ruhe2, "reduziert: kein Weg, nur Einblenden")
	check(a2.flug_ab("b") == 0.0, "reduziert: nichts fliegt")
	a2.seek(U.T_RAUM)
	var k2: Array = b2.regal.items()
	check(m2.top_bar.modulate.a == 1.0 and m2.hint_hud.modulate.a == 1.0 and k2[1].modulate.a == 1.0, "nach T_RAUM steht alles")
	a2.ende()
	m2.queue_free()
	Config.set_value("theme.reduce_motion", keep_ruhig)
	Aufbau.Leicht.active = keep_leicht
	await get_tree().process_frame


## Alle Texte unter n (Etiketten der Abschnitte, Titel der Zeilen), in Reihenfolge.
func _texte(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append(str((c as Label).text))
		out.append_array(_texte(c))
	return out
