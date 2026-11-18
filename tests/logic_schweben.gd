extends Node
## Maus im Klick-Modus (src/core/schweben.gd, zeiger.gd): Darüberfahren wählt nichts – auch nicht nach Verweilen –, über
## Wählbarem ist der Zeiger eine Hand, ein Klick wählt und löst in einem Schritt aus; nichts, was gerade abgebaut wird.
## Aufruf: godot --headless --path . res://tests/logic_schweben.tscn → „Ergebnis: alles ok“

const U := preload("res://src/ui/u.gd")

var fails := 0
var ui: Control


## Wie ein Reiter der Kopfleiste (nav_item.gd): Klicks gehen über Nav.klick, A löst activate aus.
class Reiter extends Control:
	var geoeffnet := 0

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size = Vector2(160, 50)
		set_meta("uz_klick_waehlt_nur", true)
		gui_input.connect(func(e: InputEvent) -> void: Nav.klick(self, e))

	func activate() -> void:
		geoeffnet += 1


## Wie eine Kachel, die unter der Maus leuchtet (cover_card.gd, video_card.gd, movie_card.gd).
class Leuchte extends Button:
	var an := false

	func zeiger_schweben(v: bool) -> void:
		an = v


## Wie die echten Karten (video_card.gd, movie_card.gd): Hoch/Runter geben sie an die Reihen ab.
class Karte extends Button:
	var nav_ud_cb: Callable

	func nav_ud(d: int) -> bool:
		return nav_ud_cb.is_valid() and bool(nav_ud_cb.call(d))


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	Engine.max_fps = 60
	ui = Control.new()
	ui.size = Vector2(1280, 720)
	add_child(ui)
	Nav.root_scope = ui
	# Headless meldet kein Fenster „Maus ist drin“ – ohne das merkt sich Godot nicht, was unter der Maus liegt.
	get_viewport().notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	await get_tree().process_frame
	await _darueber()
	await _klick()
	await _geloescht()
	await _medienreihen()
	await _reiter_und_glow()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit()


func _knopf(text: String, pos: Vector2, eltern: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.position = pos
	b.size = Vector2(200, 50)
	eltern.add_child(b)
	return b


## Maus an pos bewegen, wie es Windows meldet (mit echter Bewegung).
func _maus(pos: Vector2) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.relative = Vector2(6, 3)
	get_viewport().push_input(m, true)          # Koordinaten der Oberfläche (headless rechnete sonst über die Fenstergröße um)
	await get_tree().process_frame


func _druck(pos: Vector2, gedrueckt: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = gedrueckt
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e, true)
	await get_tree().process_frame


func _darueber() -> void:
	print("Darüberfahren")
	var a := _knopf("A", Vector2(40, 40), ui)
	var b := _knopf("B", Vector2(40, 100), ui)
	Nav.focus(a, true)
	await get_tree().process_frame
	await _maus(Vector2(140, 125))
	await get_tree().create_timer(0.4).timeout
	check(Nav.focused() == a, "Darüberfahren wählt nichts, auch nicht nach Verweilen (Reiter schalten nicht um)")
	check(Nav.schweben.zeiger_form == Input.CURSOR_POINTING_HAND, "über Wählbarem ist der Zeiger sofort eine Hand")
	await _maus(Vector2(900, 600))
	check(Nav.schweben.zeiger_form == Input.CURSOR_ARROW, "daneben wieder der Pfeil")
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


func _klick() -> void:
	print("Klick")
	var a := _knopf("A", Vector2(40, 40), ui)
	var b := _knopf("B", Vector2(40, 100), ui)
	var gedrueckt := [0]
	b.pressed.connect(func() -> void: gedrueckt[0] += 1)
	Nav.focus(a, true)
	await get_tree().process_frame
	await _maus(Vector2(140, 125))
	await _druck(Vector2(140, 125), true)
	await _druck(Vector2(140, 125), false)
	await get_tree().process_frame
	check(Nav.focused() == b, "ein Klick wählt das Ziel")
	check(int(gedrueckt[0]) == 1, "… und löst es im selben Klick genau einmal aus")
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


func _rad(pos: Vector2, runter: bool) -> void:
	for gedrueckt in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN if runter else MOUSE_BUTTON_WHEEL_UP
		e.pressed = gedrueckt
		e.factor = 1.0
		e.position = pos
		e.global_position = pos
		get_viewport().push_input(e, true)
	for i in 3:
		await get_tree().process_frame


## Videos, Filme, Streams (medien_bereich.gd + medien_reihen.gd): Rad senkrecht Reihe für Reihe – auch über der Bühne –,
## mit gedrückter Maustaste nach links ziehen rollt die Reihe nach rechts.
func _medienreihen() -> void:
	print("Videos, Filme, Streams")
	var sec: Control = load("res://src/ui/sections/medien_bereich.gd").new()
	sec.size = Vector2(1280, 720)
	ui.add_child(sec)
	var reihen: Control = load("res://src/ui/components/medien_reihen.gd").new()
	sec.add_child(reihen)
	reihen.setup(160)
	sec.set("_reihen", reihen)
	for i in 3:
		var row: Dictionary = reihen.add_row("Reihe %d" % i, "", "t%d" % i, 150)
		for j in 12:
			var b := Karte.new()
			b.text = "%d-%d" % [i, j]
			b.focus_mode = Control.FOCUS_ALL
			b.custom_minimum_size = Vector2(200, 150)
			reihen.add_card(row, b)
	reihen.flush()
	for i in 10:
		await get_tree().process_frame
	var zeile := func(idx: int) -> Control: return reihen.rows[idx].shelf
	var erste: Control = (zeile.call(0) as ScrollContainer).get("row").get_child(0)
	Nav.focus(erste, true)
	for i in 30:
		await get_tree().process_frame
	await _rad(erste.get_global_rect().get_center(), true)
	check((zeile.call(1) as Control).is_ancestor_of(Nav.focused()), "Rad über einer Karte: eine Reihe tiefer (nicht seitwärts)")
	await get_tree().create_timer(0.2).timeout
	await _rad(Vector2(640, 60), true)
	check((zeile.call(2) as Control).is_ancestor_of(Nav.focused()), "Rad über der Bühne: ebenfalls eine Reihe tiefer")
	await get_tree().create_timer(0.2).timeout
	await _rad(Vector2(640, 60), false)
	check((zeile.call(1) as Control).is_ancestor_of(Nav.focused()), "Rad hoch: eine Reihe höher")
	# Schnell gedreht (drei Rastungen kurz hintereinander): nur ein Schritt, nicht drei.
	await get_tree().create_timer(0.2).timeout
	await _rad(Vector2(640, 60), true)
	await _rad(Vector2(640, 60), true)
	await _rad(Vector2(640, 60), true)
	check((zeile.call(2) as Control).is_ancestor_of(Nav.focused()), "schnell gedreht: nur eine Reihe weiter, nicht drei")
	await get_tree().create_timer(0.2).timeout
	await _rad(Vector2(640, 60), false)
	for i in 30:
		await get_tree().process_frame
	var shelf := zeile.call(1) as ScrollContainer
	var vorher := shelf.scroll_horizontal
	var karte: Control = Nav.focused()
	var start := karte.get_global_rect().get_center()
	var gedrueckt := [0]
	(karte as Button).pressed.connect(func() -> void: gedrueckt[0] += 1)
	await _druck(start, true)
	for k in 8:
		await _maus(start - Vector2(50.0 * (k + 1), 0))
	await _druck(start - Vector2(400, 0), false)
	check(shelf.scroll_horizontal > vorher + 200, "mit gedrückter Maustaste nach links ziehen: die Reihe rollt nach rechts")
	check(int(gedrueckt[0]) == 0, "Ziehen öffnet nichts")
	sec.queue_free()
	await get_tree().process_frame


func _reiter_und_glow() -> void:
	print("Kopfleiste und Leuchten")
	var a := _knopf("A", Vector2(40, 400), ui)
	var r := Reiter.new()
	r.position = Vector2(300, 400)
	ui.add_child(r)
	Nav.focus(a, true)
	await get_tree().process_frame
	var p := Vector2(380, 425)
	await _maus(p)
	await _druck(p, true)
	await _druck(p, false)
	check(Nav.focused() == r and r.geoeffnet == 0, "Reiter oben: der erste Klick zeigt nur (öffnet nicht Browser oder Zimmer)")
	await _druck(p, true)
	await _druck(p, false)
	check(r.geoeffnet == 0, "… auch ein zweiter Klick öffnet nicht (dafür die Kachel im Bereich)")
	Nav.activate(r)
	check(r.geoeffnet == 1, "… A öffnet weiterhin")
	var k := Leuchte.new()
	k.focus_mode = Control.FOCUS_ALL
	k.position = Vector2(600, 400)
	k.size = Vector2(200, 120)
	ui.add_child(k)
	await _maus(Vector2(700, 460))
	check(k.an and Nav.focused() == r, "Kachel unter der Maus leuchtet – gewählt wird nichts")
	await _maus(Vector2(1000, 650))
	check(not k.an, "Maus weg: kein Leuchten mehr")
	await _maus(Vector2(700, 460))
	var vorher := str(Nav.device)
	Nav.set_device("pad")
	await get_tree().process_frame
	check(not k.an, "zum Controller gegriffen: kein Leuchten mehr")
	Nav.device = vorher
	# Kacheln ohne eigenen Schein (Musik, Shop, Apps …): Schein von schweben.gd; Zeilen und Knöpfe nicht.
	var fremd := _knopf("Kachel", Vector2(900, 380), ui)
	fremd.size = Vector2(180, 180)
	var zeile := _knopf("Zeile", Vector2(40, 560), ui)
	zeile.size = Vector2(700, 56)
	await _maus(Vector2(990, 470))
	check(Nav.schweben.glanz_ziel == fremd, "fremde Kachel unter der Maus: Schein von schweben.gd")
	await _maus(Vector2(300, 588))
	check(Nav.schweben.glanz_ziel == null, "breite Zeile: kein Schein (nur die Hand)")
	await _maus(Vector2(700, 460))
	check(Nav.schweben.glanz_ziel == null and k.an, "Kachel mit eigenem Schein: keiner doppelt von schweben.gd")
	# Reiter der Bildwahl (art_picker.gd): mit der Maus anklickbar statt nur LB/RB.
	var picker: GDScript = load("res://src/ui/layers/art_picker.gd")
	var gerufen := [0]
	var reiter_bild: Control = picker.call("_klickbar", PanelContainer.new(), func() -> void: gerufen[0] += 1)
	reiter_bild.position = Vector2(40, 650)
	reiter_bild.size = Vector2(120, 40)
	ui.add_child(reiter_bild)
	await _maus(Vector2(100, 670))
	await _druck(Vector2(100, 670), true)
	await _druck(Vector2(100, 670), false)
	check(int(gerufen[0]) == 1, "Bildwahl: ein Klick auf den Reiter (Cover, Logo …) wechselt die Bildart")
	# Ruhige Knöpfe (U.ruhig, Spielseite): unter der Maus ein Schein, gewählt wird nichts.
	var knopf := Button.new()
	knopf.text = "Optionen"
	knopf.focus_mode = Control.FOCUS_ALL
	knopf.position = Vector2(300, 600)
	knopf.size = Vector2(220, 56)
	ui.add_child(knopf)
	U.ruhig(knopf)
	var vorher_schatten := (knopf.get_theme_stylebox("normal") as StyleBoxFlat).shadow_size
	await _maus(Vector2(400, 628))
	var sb := knopf.get_theme_stylebox("normal") as StyleBoxFlat
	check(sb.shadow_size > vorher_schatten and Nav.focused() != knopf, "Knopf der Spielseite unter der Maus: Schein, nicht gewählt")
	await _maus(Vector2(1200, 700))
	check((knopf.get_theme_stylebox("normal") as StyleBoxFlat).shadow_size == vorher_schatten, "Maus weg: wieder ruhig")
	for c in [a, r, k, fremd, zeile, reiter_bild, knopf]:
		c.queue_free()
	await get_tree().process_frame


func _geloescht() -> void:
	print("Abgebaute Seite")
	var neu := _knopf("Neu", Vector2(400, 40), ui)
	var alt := _knopf("Alt", Vector2(40, 40), ui)
	Nav.focus(neu, true)
	alt.queue_free()                      # wie U.clear: im selben Bild noch da
	await _maus(Vector2(140, 65))
	check(Nav.schweben.ziel() == null, "eine schon zum Löschen vorgemerkte Zeile ist kein Ziel")
	neu.queue_free()
	await get_tree().process_frame
