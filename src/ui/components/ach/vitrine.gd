extends MarginContainer
## Vitrine: die besten Momente an einem Ort – eine ruhige, matte Fläche mit bis zu fünf großen
## Abzeichen auf einem Boden aus einer Haarlinie, hinter der Mitte ein warmes Goldlicht. Jeder
## Moment ist eine Kachel (A öffnet die Erfolge des Spiels): seltenster Erfolg, gemeistertes
## Spiel, das Neueste. Gold nur als Licht, Haken und für Gemeistertes; sonst die Farben der
## Seltenheit. Keine Liste: ein Blick, dann weiter.
## Aufbau im Takt: die Fläche steht sofort, der Boden zeichnet sich von der Mitte her (T_RAUM),
## das Licht kommt mit T_LICHT, die Abzeichen steigen gestaffelt (U.staffel) ein Stück auf und
## blenden ein; Gold und Ultraseltenes glimmt danach einmal. Ruhig: alles steht gleich da.

signal chosen(item: Dictionary)

const U := preload("res://src/ui/u.gd")
const Ach := preload("res://src/core/achievements.gd")
const Emblem := preload("res://src/ui/components/ach/emblem.gd")
const Cabinet := preload("res://src/ui/components/ach/cabinet.gd")

const H := 300                 ## Höhe der Fläche
const PAD := 28
const GAP := 18
const EMBLEM := 118            ## Größe der Abzeichen
const TOP := 14                ## Luft über den Abzeichen in der Kachel
const LINE_Y := PAD - 6 + TOP + EMBLEM + 10   ## der Boden: knapp unter den Abzeichen

var items: Array = []          ## [{ kind: "ach"|"game", a: Eintrag, name, caption, game, tier, gold, key }]
var gutter := 96
var _bg: Control


func setup(list: Array, side := 96) -> Control:
	items = list
	gutter = side
	return self


func _ready() -> void:
	add_theme_constant_override("margin_left", gutter)
	add_theme_constant_override("margin_right", gutter)
	add_theme_constant_override("margin_top", 0)
	add_theme_constant_override("margin_bottom", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, H)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_bg = _Boden.new()
	_bg.set("n", items.size())
	U.full_rect(_bg)
	holder.add_child(_bg)
	var m := U.margin(PAD, PAD - 6, PAD, PAD)
	U.full_rect(m)
	holder.add_child(m)
	var row := U.hbox(GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var n := maxi(1, items.size())
	var w := floorf((U.view_size().x - gutter * 2.0 - PAD * 2.0 - GAP * (n - 1)) / float(n))
	for i in items.size():
		var it: Dictionary = items[i]
		var t := Moment.new()
		t.item = it
		t.index = i
		t.tile_size = Vector2(w, H - PAD * 2 + 6)
		t.set_meta("uz_key", "vitrine:" + str(it.get("key", i)))
		t.set_meta("uz_hint_a", "Erfolge des Spiels")
		if i == 0:
			t.set_meta("uz_entry", true)
		t.chosen.connect(func() -> void: chosen.emit(it))
		row.add_child(t)


## Der Boden: matte Fläche mit Haarlinie, Goldlicht hinter der Mitte, eine Linie, auf der die
## Abzeichen stehen. Beim Erscheinen zeichnet sich die Linie von der Mitte her, das Licht kommt
## langsam (Hintergrund: T_LICHT).
class _Boden extends Control:
	var n := 0
	var _t := 0.0                ## Boden 0…1
	var _l := 0.0                ## Licht 0…1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		if U.reduziert():
			_t = 1.0
			_l = 1.0
			return
		var wr: WeakRef = weakref(self)
		var tw := U.ankommen(self, U.T_RAUM, "uz_boden").set_parallel(true)
		tw.tween_method(func(v: float) -> void:
			var me: Control = wr.get_ref()
			if me:
				me.set("_t", v)
				me.queue_redraw()
		, 0.0, 1.0, U.T_RAUM)
		tw.tween_method(func(v: float) -> void:
			var me: Control = wr.get_ref()
			if me:
				me.set("_l", v)
				me.queue_redraw()
		, 0.0, 1.0, U.T_LICHT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rad := UzTheme.r_panel()
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0)
		sh.set_corner_radius_all(rad)
		sh.shadow_color = Color(0, 0, 0, 0.3)
		sh.shadow_size = 18
		sh.shadow_offset = Vector2(0, 8)
		draw_style_box(sh, r)
		draw_style_box(UzTheme.box(UzTheme.col("surface", 0.92), rad, 1, UzTheme.col("text", 0.06)), r)
		# Goldlicht hinter der Mitte (das einzige warme Licht der Seite), oben weich zur Fläche.
		var c := Vector2(size.x * 0.5, float(LINE_Y) - EMBLEM * 0.45)
		var rr := size.y * 0.95
		if _l > 0.0:
			draw_texture_rect(Cabinet._radial(), Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(UzTheme.col("gold"), 0.11 * _l))
		# Der Boden, auf dem die Abzeichen stehen: eine Linie, die zu den Seiten ausläuft – und
		# beim Erscheinen von der Mitte her wächst.
		var y := float(LINE_Y)
		var segs := 40
		var x0 := 36.0
		var x1 := size.x - 36.0
		for k in segs:
			var mid := absf((float(k) + 0.5) / segs - 0.5) * 2.0
			if mid > _t:
				continue
			var a0 := x0 + (x1 - x0) * float(k) / segs
			var a1 := x0 + (x1 - x0) * float(k + 1) / segs
			var s := sin(PI * (float(k) + 0.5) / segs)
			draw_line(Vector2(a0, y), Vector2(a1, y), UzTheme.col("text", 0.11 * s), 1.5)


## Eine Kachel der Vitrine: großes Abzeichen, darunter Name, eine Zeile Bedeutung, das Spiel.
## Gewählt: eine matte Platte hebt sich (kein eigener Schatten – die Vitrine trägt ihn).
class Moment extends "res://src/ui/components/ach/tile.gd":
	var item: Dictionary = {}
	var index := 0
	var _emblem: Control

	func _init() -> void:
		super()
		lift = 8.0

	func _ready() -> void:
		super()
		# Aufsteigen und einblenden, gestaffelt; danach glimmt Gold und Ultraseltenes einmal.
		arrive_from(Vector2(0, 18), U.T_RAUM, U.staffel(index), true)
		var em := _emblem
		if em and float(em.get("glow")) > 0.0 and not U.reduziert():
			celebrate(U.staffel(index) + U.T_RAUM)

	func build_body() -> void:
		var v := U.vbox(6)
		v.alignment = BoxContainer.ALIGNMENT_BEGIN
		U.full_rect(v)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(v)
		# Die Abzeichen stehen in jeder Kachel auf derselben Höhe – auf dem Boden der Vitrine.
		v.add_child(U.spacer(0, TOP - 6, false))
		var a: Dictionary = item.get("a", {})
		var tier := int(item.get("tier", Ach.rarity_tier(float(a.get("rarity", -1.0)))))
		var em := Emblem.new().setup(str(a.get("icon", "")), true, tier, EMBLEM)
		em.gold = bool(item.get("gold", false))
		em.glow = 0.7 if em.gold or tier == 3 else 0.0
		em.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_emblem = em
		v.add_child(em)
		v.add_child(U.spacer(0, 6, false))
		var nm := U.ellipsis(U.label(str(item.get("name", a.get("title", ""))), "s", "text", "ui_bold"))
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Name von Steam bzw. RetroAchievements
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.custom_minimum_size.x = tile_size.x - 24
		nm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(nm)
		var cap_col := "gold" if em.gold else ("accent" if tier == 3 else "muted")
		var cap := U.ellipsis(U.label(str(item.get("caption", "")), "xs", cap_col, "medium"))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.custom_minimum_size.x = tile_size.x - 24
		cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(cap)
		var g := str(item.get("game", ""))
		if g != "":
			var gl := U.ellipsis(U.label(g, "xs", "faint", "regular"))
			gl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			gl.custom_minimum_size.x = tile_size.x - 24
			gl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(gl)

	## Beim Erscheinen glimmt das Abzeichen einmal auf (für das Neueste).
	func celebrate(delay := 0.3) -> void:
		if _emblem == null:
			return
		var em := _emblem
		var base: float = em.get("glow")
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_method(func(v: float) -> void:
			if is_instance_valid(em):
				em.call("set_glow", maxf(base, sin(v * PI)))
		, 0.0, 1.0, 1.2).set_trans(Tween.TRANS_SINE)

	func _draw() -> void:
		var f: float = float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
		var rad := radius()
		var r := Rect2(Vector2(shift.x, -_lift + shift.y), size)
		if f <= 0.01:
			return
		# Gewählt: eine matte Platte hebt sich, dazu nur eine feine Linie des Cursors (kein dicker
		# Rahmen um die Vitrine-Stücke – die Platte und das Anheben sagen genug).
		draw_style_box(UzTheme.box(UzTheme.col("surface_hi", 0.92 * f), rad), r)
		var ring := UzTheme.focus_ring(f, rad)
		ring.shadow_size = 0
		ring.set_border_width_all(2)
		ring.border_color = Color(ring.border_color, ring.border_color.a * 0.6)
		draw_style_box(ring, r)
