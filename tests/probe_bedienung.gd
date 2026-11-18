extends "res://tests/probe_base.gd"
## Probe „Bedienung“ (Punkt 64): Tastatur-Symbole (Startseite, Einstellungen, Guide), Touch mit Zurück-Knopf
## (Spielseite, Optionen nach langem Tippen, Bildschirmtastatur), Steam Deck auf 1280 × 800 und
## ROG Ally auf 1920 × 1080 bei 7″ (Gerät und Bildschirm nachgestellt, Oberfläche 150 %), mit
## Akku oben, Schnellmenü samt „Leistung“ und Handheld-Tastensymbolen. Alle Eingaben als
## Godot-Ereignisse.

const Handheld := preload("res://src/core/handheld.gd")
const DisplayFit := preload("res://src/core/display_fit.gd")
const GuideQuick := preload("res://src/ui/components/guide_quick.gd")
const Guide := preload("res://src/ui/layers/guide.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "auto")
	main.goto("games", "zuletzt")
	await wait(1.5)
	# Tastatur: Pfeile und Enter, die Hinweise zeigen Tastatur-Symbole.
	_taste(KEY_DOWN)
	await shot("01_tastatur_startseite", 1.0)
	main.goto("settings", "controller")
	await wait(0.8)
	_taste(KEY_DOWN)
	await press("down", 3, 0.2)
	await shot("02_tastatur_einstellungen_controller", 0.8)
	main.goto("games", "zuletzt")
	await wait(0.6)
	main.toggle_guide()
	await shot("03_tastatur_guide", 1.4)
	_taste(KEY_ESCAPE)
	await wait(0.6)
	# Touch: Spielseite mit Zurück-Knopf oben links.
	main.goto("games", "zuletzt")
	await wait(1.0)
	var g := Library.get_game("ps2:sotc")
	if g.is_empty() and not Library.visible_games().is_empty():
		g = Library.visible_games()[0]
	_tippen(Vector2(1700, 980))
	main.open_game_note(g)
	await shot("04_touch_spielseite", 1.6)
	_tippen(Vector2(UzTheme.GUTTER - 46, 56))
	await wait(0.8)
	# Langes Tippen auf ein Cover: Optionen (Seitenleiste), Zurück-Knopf bleibt erreichbar.
	var cover := _cover(1)
	if cover:
		_finger(0, true, cover.get_global_rect().get_center())
		await wait(0.7)
		_finger(0, false, cover.get_global_rect().get_center())
		await shot("05_touch_optionen_lang_getippt", 1.0)
		_tippen(Vector2(UzTheme.GUTTER - 46, 56))
		await wait(0.6)
	main.open_keyboard("Suchen", "Zel", func(_t: String) -> void: pass)
	await wait(0.6)
	_tippen(_key_pos("d"))
	await shot("06_touch_bildschirmtastatur", 0.8)
	_tippen(Vector2(UzTheme.GUTTER - 46, 56))
	await wait(0.6)

	# Steam Deck: 1280 × 800, 7,4″ eingebaut, Name „Jupiter“ von Valve.
	await _geraet(Vector2i(1280, 800), { "maker": "Valve", "product": "Jupiter", "tech": "intern", "w_cm": 16, "h_cm": 10 })
	Nav.pad_name = "Steam Virtual Gamepad"
	Nav.pad_vid = 0x28DE
	_pad()
	main.goto("games", "zuletzt")
	await shot("07_deck_startseite_1280x800", 1.6)
	await GuideQuick.plaene_laden()
	main.toggle_guide(Guide.QUICK)
	await shot("08_deck_schnellmenue_leistung", 1.2)
	Nav._fire("b")
	await wait(0.6)
	main.toggle_guide()
	await shot("09_deck_guide", 1.4)
	Nav._fire("b")
	await wait(0.6)
	main.goto("settings", "controller")
	await wait(0.8)
	await press("down", 4, 0.25)
	await shot("10_deck_einstellungen_controller", 0.8)
	# Mit dem Finger auf dem Deck (Tastensymbole wie am eingebauten Controller).
	Config.set_value("controller.glyphs", "deck")
	main.goto("games", "zuletzt")
	await wait(1.0)
	_tippen(Vector2(1200, 760))
	main.open_game_note(g)
	await shot("11_deck_touch_spielseite", 1.6)
	_tippen(Vector2(UzTheme.GUTTER - 46, 56))
	await wait(0.6)
	main.open_keyboard("WLAN-Kennwort", "", func(_t: String) -> void: pass, true)
	await shot("12_deck_touch_tastatur", 1.0)
	_tippen(Vector2(UzTheme.GUTTER - 46, 56))
	await wait(0.6)
	Config.set_value("controller.glyphs", "auto")

	# ROG Ally: 1920 × 1080 auf 7″.
	await _geraet(Vector2i(1920, 1080), { "maker": "ASUSTeK COMPUTER INC.", "product": "ROG Ally RC71L_RC71L", "tech": "intern", "w_cm": 15, "h_cm": 9 })
	Nav.pad_name = "XInput Gamepad"
	Nav.pad_vid = -1
	_pad()
	main.goto("games", "zuletzt")
	await shot("13_ally_startseite_1080p_7zoll", 1.6)
	main.open_game_note(g)
	await shot("14_ally_spielseite", 1.6)
	Nav._fire("b")
	await wait(0.6)
	main.toggle_guide(Guide.QUICK)
	await shot("15_ally_schnellmenue", 1.2)
	Nav._fire("b")
	await wait(0.6)

	# Zurück an den Schreibtisch.
	Handheld.aktiv = {}
	Config.set_value("display.seen", {})
	Config.set_value("theme.ui_scale", 1.0)
	await wait(UzTheme.LAYOUT_DELAY + 1.2)


# --- Gerät nachstellen ------------------------------------------------------------------------

func _geraet(px: Vector2i, seen: Dictionary) -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED
	w.borderless = true
	w.position = Vector2i.ZERO
	w.size = px
	await wait(0.4)
	DisplayFit.mark_handheld(seen, "")
	Config.set_value("display.seen", seen)
	DisplayFit.apply(seen, false)
	print(
			"Gerät: %s, Oberfläche %d %%, logisch %s" % [str(Handheld.aktiv.get("name", "")), roundi(UzTheme.ui_scale() * 100.0),
			str(get_viewport().get_visible_rect().size)])
	await wait(UzTheme.LAYOUT_DELAY + 1.4)
	main._rebuild()
	await wait(1.2)


func _pad() -> void:
	Nav.set_device("keys")
	Nav.set_device("pad")


# --- Eingaben ---------------------------------------------------------------------------------

func _taste(kc: Key) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = kc
		k.physical_keycode = kc
		k.pressed = down
		get_viewport().push_input(k, true)


func _finger(idx: int, down: bool, pos: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.pressed = down
	t.position = pos
	get_viewport().push_input(t, true)


func _tippen(pos: Vector2) -> void:
	_finger(0, true, pos)
	_finger(0, false, pos)


func _wischen(from: Vector2, by: Vector2) -> void:
	_finger(0, true, from)
	var p := from
	for i in 8:
		await get_tree().create_timer(0.016).timeout
		p += by / 8.0
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = p
		d.relative = by / 8.0
		get_viewport().push_input(d, true)
	_finger(0, false, p)


func _cover(i: int) -> Control:
	var n := 0
	for c in main.find_children("*", "Control", true, false):
		var scr: Script = c.get_script()
		if scr and scr.resource_path.ends_with("cover_card.gd") and (c as Control).is_visible_in_tree():
			if n == i:
				return c
			n += 1
	return null


func _key_pos(label: String) -> Vector2:
	var top: Control = Nav.top_layer()
	if top:
		for c in top.find_children("*", "Control", true, false):
			if str(c.get("label")) == label:
				return (c as Control).get_global_rect().get_center()
	return Vector2.ZERO


