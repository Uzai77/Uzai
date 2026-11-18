extends Control
## Ein Ordner als Kachel im Regal: auf einer ruhigen Glasfläche ein kleiner Fächer aus bis zu
## drei Covern (vorn das erste Spiel), darunter Name und Anzahl in Sofa-Größe. Gewählt wie ein
## Cover: heller Ring, zartes Goldband, wächst. Auch „Alle anzeigen“ am Ende des Regals ist so
## eine Kachel (Ordner-Daten mit "_games", "_count", "_sub" und "_icon").

signal chosen(folder: Dictionary)

const U := preload("res://src/ui/u.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")

var folder: Dictionary = {}
var card_size := Vector2(216, 288)
var focus_scale := 1.06
var grow_left := false       ## beim Wachsen links unten bündig bleiben (Regal der Startseite)
var calm := false            ## ruhig gewählt: ohne Nachfedern (Regal der Startseite)
var _focus_t := 0.0
var _tw: Tween
var _minis: Array = []         ## Rect2 der kleinen Cover (für ihre Schatten)


func setup(f: Dictionary, override_size := Vector2.ZERO) -> Control:
	folder = f
	card_size = override_size if override_size != Vector2.ZERO else UzTheme.cover_size()
	return self


func _games() -> Array:
	if folder.has("_games"):
		return folder["_games"]
	return Library.in_folder(str(folder.get("id", "")))


func _foot_h() -> float:
	return clampf(card_size.y * 0.3, 64.0, 86.0)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = card_size
	pivot_offset = Vector2(0, card_size.y) if grow_left else card_size * 0.5
	set_meta("uz_key", "f:" + str(folder.get("id", "")))
	if not has_meta("uz_hint_a"):
		set_meta("uz_hint_a", "Ordner öffnen")
	var games := _games()
	_build_stack(games.slice(0, 3))
	_build_foot(games.size())
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Bis zu drei Cover als Fächer: vorn das erste, dahinter links und rechts etwas kleiner und
## dunkler. Die Maße ergeben sich aus der Kachel (hoch, quer oder quadratisch).
func _build_stack(games: Array) -> void:
	var area := Vector2(card_size.x, card_size.y - _foot_h())
	var mw := minf((card_size.x * 0.5 - 12.0) / 0.8, (area.y - 40.0) * 0.75)
	var front := Vector2(mw, mw / 0.75)
	var back := front * 0.86
	var off := mw * 0.367
	var cx := card_size.x * 0.5
	var bottom := area.y * 0.5 + front.y * 0.5 + 6.0
	var slots: Array = []
	# Reihenfolge = Zeichenreihenfolge: hinten zuerst.
	if games.size() >= 3:
		slots.append([games[1], Rect2(cx - off - back.x * 0.5, bottom - 10.0 - back.y, back.x, back.y), 0.55])
		slots.append([games[2], Rect2(cx + off - back.x * 0.5, bottom - 10.0 - back.y, back.x, back.y), 0.55])
	elif games.size() == 2:
		slots.append([games[1], Rect2(cx + off * 0.8 - back.x * 0.5, bottom - 10.0 - back.y, back.x, back.y), 0.55])
	if games.size() >= 1:
		var fx := cx - front.x * 0.5 - (off * 0.2 if games.size() == 2 else 0.0)
		slots.append([games[0], Rect2(fx, bottom - front.y, front.x, front.y), 1.0])
	_minis.clear()
	for s in slots:
		_minis.append(s[1])
		add_child(_mini(s[0], s[1], s[2]))
	if games.is_empty():
		# Leerer Ordner: ein ruhiges Symbol statt eines Lochs.
		var ic := U.icon(str(folder.get("_icon", "folder")), 44, "faint")
		ic.position = Vector2(cx - 22, area.y * 0.5 - 16)
		add_child(ic)


func _mini(g: Dictionary, r: Rect2, bright: float) -> Control:
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), maxi(6, UzTheme.r_cover() - 4)))
	U.clip_round(clip)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = r.position
	clip.size = r.size
	clip.modulate = Color(bright, bright, bright, 1.0)
	var art = CoverArt.new()
	art.compact = true
	art.show_title = false
	U.full_rect(art)
	clip.add_child(art)
	art.setup(g)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(tr)
	clip.add_child(tr)
	var wt: WeakRef = weakref(tr)
	Media.game_texture(g, "cover", func(t: Texture2D) -> void:
		var t2: TextureRect = wt.get_ref()
		if t2 and t:
			t2.texture = t
	)
	return clip


func _build_foot(n: int) -> void:
	var fh := _foot_h()
	var m := U.margin(16, 0, 14, 12)
	m.position = Vector2(0, card_size.y - fh)
	m.size = Vector2(card_size.x, fh)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var col := U.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(col)
	var row := U.hbox(8)
	var ic := U.icon(str(folder.get("_icon", "folder")), 20, "accent")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var name_l := U.ellipsis(U.label(str(folder.get("name", "")), "m", "text", "bold"))
	row.add_child(name_l)
	col.add_child(row)
	var sub := str(folder.get("_sub", ""))
	if sub == "":
		sub = U.plural(n, "Spiel", "Spiele")
	col.add_child(U.ellipsis(U.label(sub, "s", "muted", "medium")))


func _on_focus(on: bool) -> void:
	if _tw:
		_tw.kill()
	_tw = U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Wie ein Cover: rein etwas länger, raus kurz.
	_tw.tween_property(self, "scale", Vector2.ONE * (focus_scale if on else 1.0), 0.32 if on else 0.2).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_method(func(v: float) -> void:
		_focus_t = v
		queue_redraw()
	, _focus_t, 1.0 if on else 0.0, 0.18)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := UzTheme.r_cover()
	# Schatten der Kachel, gewählt etwas mehr – wie bei den Covern.
	var sh := StyleBoxFlat.new()
	sh.draw_center = false
	sh.set_corner_radius_all(rad)
	sh.shadow_color = Color(0, 0, 0, 0.32 + 0.22 * _focus_t)
	sh.shadow_size = int(18 + 18 * _focus_t)
	sh.shadow_offset = Vector2(0, 10 + 8 * _focus_t)
	draw_style_box(sh, r)
	draw_style_box(UzTheme.box(UzTheme.col("surface_hi"), rad, 1, UzTheme.col("stroke")), r)
	# Ganz leichtes Licht von oben, damit die Fläche nicht stumpf wirkt.
	draw_texture_rect(U.fade_texture(true), Rect2(2, 2, size.x - 4, size.y * 0.55), false, Color(UzTheme.col("text"), 0.035))
	for m in _minis:
		var ms := StyleBoxFlat.new()
		ms.draw_center = false
		ms.set_corner_radius_all(maxi(6, rad - 4))
		ms.shadow_color = Color(0, 0, 0, 0.45)
		ms.shadow_size = 10
		ms.shadow_offset = Vector2(0, 5)
		draw_style_box(ms, m)
	if _focus_t > 0.01:
		var band := StyleBoxFlat.new()
		band.draw_center = false
		band.set_border_width_all(6)
		band.border_color = Color(UzTheme.col("accent"), 0.24 * _focus_t)
		band.set_corner_radius_all(rad + 9)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			band.set_expand_margin(side, 9)
		band.anti_aliasing = true
		draw_style_box(band, r)
		var ring := UzTheme.focus_ring(_focus_t)
		ring.shadow_size = 0
		draw_style_box(ring, r)


func activate() -> void:
	chosen.emit(folder)


## Steuerkreuz hoch/runter wie bei den Covern (Meta "uz_up" / "uz_down").
func nav_ud(d: int) -> bool:
	var key := "uz_up" if d < 0 else "uz_down"
	if has_meta(key):
		var cb: Variant = get_meta(key)
		if cb is Callable and (cb as Callable).is_valid():
			return bool((cb as Callable).call())
	return false
