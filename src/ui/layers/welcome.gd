extends "res://src/ui/layers/layer.gd"
## Erster Start, so kurz wie möglich: Uzai findet Steam-, Epic- und PC-Spiele und die Musik von
## selbst. Es bleibt eine Anmeldung (Steam per QR-Code) und, wer will, Emulator-Spiele.
## Alles andere ist freiwillig und liegt unter Einstellungen → Konten.
## Ein ruhiger Empfang über die ganze Fläche: Das Zeichen zeichnet sich (wie beim Einschalten),
## darunter zwei große Kacheln und „Los geht's“.

const Mark := preload("res://src/ui/components/uzai_logo.gd")

const Main := preload("res://src/main.gd")
var main: Main
var _items: Array[Control] = []


func build() -> void:
	# Ein eigener, ruhiger Raum: deckend, oben ein warmer Lichtschein wie beim Einschalten.
	dim = 1.0
	_scrim.color = UzTheme.col("bg") if UzTheme.light else UzTheme.col("bg").darkened(0.35)
	set_meta("uz_hint_b", "Später")
	var glow := TextureRect.new()
	glow.texture = _glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(UzTheme.col("accent"), 0.11)
	glow.material = U.entstuft()
	glow.anchor_left = 0.5
	glow.anchor_right = 0.5
	glow.offset_left = -900
	glow.offset_right = 900
	glow.offset_top = -400
	glow.offset_bottom = 920
	add_child(glow)
	var cc := CenterContainer.new()
	U.full_rect(cc)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var col := U.vbox(0)
	col.custom_minimum_size = Vector2(1140, 0)
	cc.add_child(col)
	var mark: Control = Mark.new()
	mark.custom_minimum_size = Vector2(Mark.zeichen_breite(104.0), 104.0)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(mark)
	mark.call("play", 0.1)
	col.add_child(U.spacer(0, 26, false))
	var title := Label.new()
	title.text = "Willkommen bei Uzai"
	title.add_theme_font_override("font", UzTheme.display("title"))
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UzTheme.col("text"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	col.add_child(U.spacer(0, 12, false))
	var intro := U.label("Spiele werden automatisch gefunden.", "m", "muted", "regular", true)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.custom_minimum_size = Vector2(900, 0)
	intro.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(intro)
	col.add_child(U.spacer(0, 40, false))
	var tiles := U.hbox(28)
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tiles)
	var steam := _Tile.new()
	steam.icon = "steam"
	steam.title = "Mit Steam anmelden"
	steam.text = "Code mit der Steam-App scannen."
	steam.foot = "Etwa eine Minute"
	steam.set_meta("uz_default", true)
	steam.set_meta("uz_hint_a", "Anmelden")
	steam.activated.connect(func() -> void:
		close()
		main.open_chat({ "id": "", "name": "Steam" }, true)
	)
	tiles.add_child(steam)
	var roms := _Tile.new()
	roms.icon = "folder"
	roms.title = "Emulator-Spiele hinzufügen"
	roms.text = "Ein Ordner pro System."
	roms.foot = "Einstellungen → Emulation"
	roms.set_meta("uz_hint_a", "Ordner wählen")
	roms.activated.connect(func() -> void:
		close()
		main.goto("settings", "emulation")
	)
	tiles.add_child(roms)
	# Unter Windows öffnet die Guide-Taste sonst zusätzlich die Xbox Game Bar: gleich hier anbieten,
	# das (nur auf Knopfdruck) abzuschalten. Die Zeile erscheint erst, wenn der Helfer „an“ meldet.
	var gb_row := U.hbox(18)
	gb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gb_row.visible = false
	col.add_child(U.spacer(0, 26, false))
	col.add_child(gb_row)
	if Config.is_windows():
		_offer_gamebar(weakref(gb_row))
	col.add_child(U.spacer(0, 40, false))
	var go := U.button("Starten", "play", "primary")
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.custom_minimum_size = Vector2(260, 60)
	go.set_meta("uz_hint_a", "Starten")
	go.pressed.connect(close)
	col.add_child(go)
	col.add_child(U.spacer(0, 22, false))
	var more := U.label("Weitere Konten unter Einstellungen → Konten.", "s", "faint", "regular", true)
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(more)
	_items = [title, intro, steam, roms, go, more]
	_enter()


static func _offer_gamebar(rr: WeakRef) -> void:
	var res := await Helper.run("gamebar", {}, 6.0)
	var row = rr.get_ref()
	if row == null or not res.get("ok", false) or not (res.get("result") is Dictionary):
		return
	if not bool((res.result as Dictionary).get("enabled", true)):
		return
	var r: HBoxContainer = row
	var l := U.label("Die Guide-Taste öffnet unter Windows zusätzlich die Xbox Game Bar.", "s", "muted", "regular")
	r.add_child(l)
	var b := U.button("Guide-Taste nur für Uzai", "controller")
	b.pressed.connect(func() -> void:
		var done := await Helper.run("gamebar", { "set": false }, 6.0)
		var row2 = rr.get_ref()
		if row2 == null:
			return
		var ok := bool(done.get("ok", false))
		for c in (row2 as Node).get_children():
			c.queue_free()
		(row2 as Node).add_child(
				U.label("Erledigt. Game Bar mit Win + G." if ok else "Ging nicht. Später unter Einstellungen → Controller.", "s", "muted", "regular"))
	)
	r.add_child(b)
	r.visible = true


static func _glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	# Viele Stützstellen (die Glocke statt eines Vielecks) und genug Bildpunkte: kein Knick, keine
	# 8-Bit-Stufen schon in der Textur.
	for i in 33:
		var r := i / 32.0
		offs.append(r)
		cols.append(Color(1, 1, 1, (exp(-4.5 * r * r) - exp(-4.5)) / (1.0 - exp(-4.5))))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 512
	t.height = 512
	return t


## Nacheinander herein: Titel, Text, Kacheln, Knopf – jeweils leicht von unten.
func _enter() -> void:
	var i := 0
	for c in _items:
		c.modulate.a = 0.0
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		var delay := 0.35 + i * 0.07
		t.tween_property(c, "modulate:a", 1.0, U.T_ENTER).set_delay(delay)
		if c is _Tile:
			t.tween_method((c as _Tile).set_rise, 18.0, 0.0, U.T_ENTER + 0.1).set_delay(delay)
		i += 1


## Große Kachel mit Zeichen, Titel, zwei Zeilen Text und einem leisen Fuß.
## Gewählt: helle Fläche (Schrift wird dunkel), hebt sich leicht, ein feiner Goldschein.
class _Tile extends Control:
	signal activated

	const UU := preload("res://src/ui/u.gd")

	var icon := ""
	var title := ""
	var text := ""
	var foot := ""
	var _rise := 0.0
	var _m: MarginContainer

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(540, 220)
		_m = UU.margin(34, 30, 34, 28)
		UU.full_rect(_m)
		add_child(_m)
		# Die Kachel ist so hoch, wie ihr Inhalt es braucht (umbrechender Text).
		_m.minimum_size_changed.connect(func() -> void:
			custom_minimum_size.y = maxf(220.0, _m.get_combined_minimum_size().y)
		)
		var col := UU.vbox(10)
		_m.add_child(col)
		var ic := UU.icon(icon, 40, "text")
		ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(ic)
		col.add_child(UU.spacer(0, 4, false))
		col.add_child(UU.label(title, "l", "text", "bold"))
		var t := UU.label(text, "m", "muted", "regular", true)
		t.custom_minimum_size = Vector2(470, 0)
		col.add_child(t)
		col.add_child(UU.spacer(0, 4, true))
		col.add_child(UU.label(foot, "s", "faint", "medium"))
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			_lift(true)
		)
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			_lift(false)
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	## Gewählt hebt sich die Kachel um ein paar Pixel (Inhalt und Fläche zusammen).
	func _lift(on: bool) -> void:
		var tw := UU.tw(self, "uz_lift", Tween.TRANS_CUBIC)
		tw.tween_method(_set_lift_y, _m.position.y, _rise - (8.0 if on else 0.0), UU.T_FOCUS if on else UU.T_BASE)

	func _set_lift_y(y: float) -> void:
		_m.position.y = y
		queue_redraw()

	func set_rise(v: float) -> void:
		_rise = v
		if _m:
			_set_lift_y(v - (8.0 if has_focus() else 0.0))

	func activate() -> void:
		activated.emit()

	func _draw() -> void:
		var f: float = get_meta("uz_f", 1.0 if has_focus() else 0.0)
		var r := Rect2(Vector2(0, _m.position.y if _m else 0.0), size)
		var rad := UzTheme.r_panel()
		if f > 0.01:
			var g := UzTheme.box(Color(0, 0, 0, 0), rad)
			g.shadow_color = Color(UzTheme.col("accent"), 0.28 * f * UzTheme.glow_k())
			g.shadow_size = int(22 * f)
			draw_style_box(g, r)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.06), rad, 1, UzTheme.col("stroke")), r)
		if f > 0.01:
			var sb := UzTheme.focus_fill(rad)
			sb.bg_color.a *= f
			draw_style_box(sb, r)
