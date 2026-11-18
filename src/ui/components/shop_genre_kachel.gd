extends Control
## Genre im Shop als Kachel: ein ruhiger Kasten, randvoll mit drei Spielen, die in diesem Genre
## gerade oben stehen (Topseller bei Steam), unten links der Name. Gewählt hebt sich die Kachel
## und trägt den Kachel-Cursor der Marke (feine Lichtkante, Akzent-Schein). Ohne Bilder bleibt
## eine ruhige Fläche – nie eine Genre-Farbe.

signal chosen

const U := preload("res://src/ui/u.gd")
const ArtC := preload("res://src/ui/components/shop_art.gd")
const W := 412.0
const H := 206.0

var key := ""
var index := 0
var label := ""
var _frame: Panel
var _art: Control
var _ring: Control


func setup(k: String, text: String, i := 0) -> Control:
	key = k
	label = text
	index = i
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, H)
	set_meta("uz_key", "genre:" + key)
	set_meta("uz_hint_a", "Öffnen")
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_panel() - 6))
	_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = custom_minimum_size
	add_child(_frame)
	_art = _Art.new()
	_art.label = label
	U.full_rect(_art)
	_frame.add_child(_art)
	_ring = _Ring.new()
	_ring.size = custom_minimum_size
	_ring.tile = self
	add_child(_ring)
	focus_entered.connect(func() -> void: U.focus_anim(self, true))
	focus_exited.connect(func() -> void: U.focus_anim(self, false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)
	_load()


## Die drei Spiele des Genres holen (Steam: Topseller; bleibt bis zum Neustart gemerkt).
func _load() -> void:
	var wself: WeakRef = weakref(self)
	var res: Dictionary = await Store.genre(key)
	var me: Control = wself.get_ref()
	if me == null:
		return
	var items: Array = res.get("topsellers", []) if res.get("topsellers") is Array else []
	if items.is_empty() and res.get("newreleases") is Array:
		items = res.newreleases
	# Vorführung: alle Genres haben dieselbe Liste – versetzt, damit nicht jede Kachel gleich aussieht.
	if Library.demo and items.size() > 3:
		var off := (index * 3) % items.size()
		items = items.slice(off) + items.slice(0, off)
	me.call("_set_items", items.slice(0, 3))


## Die Bilder der Spiele nebeneinander in die Kachel. Liegen sie im Speicher (Zurück aus einem
## Genre), stehen sie sofort – ohne Staffel, ohne Aufblenden.
func _set_items(items: Array) -> void:
	var wart: WeakRef = weakref(_art)
	var sync := { "on": true }
	for i in mini(items.size(), 3):
		var it0: Dictionary = items[i]
		var slot := i
		Media.with_steam_assets(int(it0.get("appid", 0)), func(assets: Dictionary) -> void:
			if wart.get_ref() == null:
				return
			var urls := Store.art_urls_from(it0, assets if not assets.is_empty() else Store.art_assets(it0), true, int(W * 0.5 * Media.px_scale()))
			Media.url_texture_chain(urls, int(W * 0.5), func(t: Texture2D) -> void:
				var a: Control = wart.get_ref()
				if a and t:
					a.call("show_tex", t, slot, bool(sync.on))
			)
		)
	sync.on = false


func activate() -> void:
	chosen.emit()


func f() -> float:
	return float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0


func _draw() -> void:
	var k := f()
	var lift := -10.0 * k
	_frame.position.y = lift
	_ring.position.y = lift
	_ring.queue_redraw()
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.set_corner_radius_all(UzTheme.r_panel() - 6)
	sh.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(0.3 + 0.2 * k))
	sh.shadow_size = int(12 + 12 * k)
	sh.shadow_offset = Vector2(0, 8)
	draw_style_box(sh, Rect2(Vector2(4, 6 + lift), size - Vector2(8, 8)))


## Inneres der Kachel: drei Spiele nebeneinander, randvoll, unten links ein dunkler Verlauf für den
## Namen. Ein Querformat-Bild (Spiel ohne Hülle) wird nicht verzerrt, sondern ganz gezeigt.
class _Art extends Control:
	const GAP := 3.0
	var label := ""
	var _tex: Array = [null, null, null]
	var _soft: Array = [null, null, null]
	var _a: Array = [0.0, 0.0, 0.0]
	static var _shade: GradientTexture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Bild in seine Spalte: aus dem Speicher (sofort) gleich deckend, sonst in T_ORT.
	func show_tex(t: Texture2D, slot := 0, sofort := false) -> void:
		_tex[slot] = t
		_soft[slot] = ArtC.soft_of(t) if t.get_width() > t.get_height() else null
		if sofort:
			_a[slot] = 1.0
			queue_redraw()
			return
		U.ankommen(self, U.T_ORT, "uz_bild%d" % slot).tween_method(func(v: float) -> void:
			_a[slot] = v
			queue_redraw()
		, float(_a[slot]), 1.0, U.T_ORT)

	static func shade() -> GradientTexture2D:
		if _shade == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.0)])
			_shade = GradientTexture2D.new()
			_shade.gradient = g
			_shade.fill_from = Vector2(0, 1)
			_shade.fill_to = Vector2(0.6, 0.15)
			_shade.width = 128
			_shade.height = 64
		return _shade

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), UzTheme.col("surface_hi"))
		var n := 0
		for t in _tex:
			if t != null:
				n += 1
		var cols := maxi(1, 3 if n >= 3 else n)
		var cw := (w - GAP * (cols - 1)) / cols
		var k := 0
		for i in 3:
			var t: Texture2D = _tex[i]
			if t == null or k >= cols:
				continue
			var cell := Rect2(k * (cw + GAP), 0, cw, h)
			k += 1
			ArtC.draw_art(self, t, cell, _soft[i], float(_a[i]))
		draw_texture_rect(shade(), Rect2(Vector2.ZERO, size), false)
		var font := UzTheme.display("black")
		var fs := 30
		var tw := w - 52.0
		var block := font.get_multiline_string_size(tr(label), HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 2)
		var y := h - 22.0 - block.y + font.get_ascent(fs)
		draw_multiline_string(font, Vector2(26, y + 2), tr(label), HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 2, Color(0, 0, 0, 0.4))
		draw_multiline_string(font, Vector2(26, y), tr(label), HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 2, Color(1, 1, 1, 0.97))


## Der Kachel-Cursor über dem Bild (außerhalb der Bildmaske, damit der Schein zu sehen ist).
class _Ring extends Control:
	var tile: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k: float = tile.call("f")
		UzTheme.draw_tile_focus(self, Rect2(Vector2.ZERO, size), UzTheme.r_panel() - 6, minf(k, 1.0))
