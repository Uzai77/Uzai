extends Control
## Ein Tastensymbol (A, B, LB, Enter …) passend zum Eingabegerät: Xbox, PlayStation,
## Nintendo, Tastatur oder der eingebaute Controller eines Handhelds (Steam Deck: L1/R1, die
## anderen wie Xbox, beide einfarbig wie die Tasten am Gerät). Wechselt automatisch, wenn der
## Nutzer das Gerät wechselt.
## Ruhig gezeichnet: Glasscheibe ohne Rand (helle Haarlinien wirkten am Fernseher wie weiße
## Striche), Buchstabe bzw. Zeichen einfarbig in der Schriftfarbe – keine bunten Tasten.

const Logo := preload("res://src/ui/components/uzai_logo.gd")

var cmd := "a"
var px := 30
var subtle := false         ## leiser (an den Enden der Reiterleisten)
var force := ""             ## feste Art (xbox, ps, nintendo, keys, deck, handheld) statt der des Geräts – Vorschau im Problemlöser

const KEYS := { "a": "Enter", "b": "Esc", "x": "X", "y": "Y", "lb": "Q", "rb": "E", "lt": "Bild↑", "rt": "Bild↓", "guide": "G", "menu": "M", "view": "V",
		"search": "F" }
const XBOX := { "a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT", "menu": "≡", "view": "⧉", "search": "RS" }
const NINTENDO := { "a": "A", "b": "B", "x": "X", "y": "Y", "lb": "L", "rb": "R", "lt": "ZL", "rt": "ZR", "menu": "+", "view": "−", "search": "RS" }
const PS := { "lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "menu": "≡", "view": "⧉", "search": "R3" }
const DECK := { "a": "A", "b": "B", "x": "X", "y": "Y", "lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "menu": "≡", "view": "⧉", "search": "R3" }


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Nie auf die Zeilenhöhe strecken: das Symbol bleibt so groß, wie es ist, und mittig.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Nav.device_changed.connect(func(_k: String) -> void:
		_resize()
		queue_redraw()
	)
	_resize()


func _resize() -> void:
	custom_minimum_size = size_for(cmd, px, force if force != "" else Nav.glyph_set())
	size = custom_minimum_size


## Größe eines Tastensymbols (auch für Bauteile, die es selbst zeichnen).
static func size_for(c: String, p: int, gset: String) -> Vector2:
	var w := float(p)
	if c == "ud" or c == "lr":
		w = float(p)
	elif gset == "keys":
		var t: String = KEYS.get(c, c)
		w = maxf(p, UzTheme.font("bold").get_string_size(TranslationServer.translate(t), HORIZONTAL_ALIGNMENT_LEFT, -1, int(p * 0.5)).x + p * 0.6)
	elif c in ["lb", "rb", "lt", "rt", "search"]:
		w = p * 1.5
	return Vector2(w, p)


func _draw() -> void:
	var gset := force if force != "" else Nav.glyph_set()
	paint(self, cmd, px, Rect2((size - custom_minimum_size) * 0.5, custom_minimum_size), gset, 0.62 if subtle else 1.0, 1.0)


## Ein Tastensymbol auf ci zeichnen (Glyph selbst und Bauteile, die es in ihr Bild setzen). r: Fläche, k: leiser (0 … 1),
## alpha: Deckkraft.
static func paint(ci: CanvasItem, c: String, p: int, r: Rect2, gset: String, k: float, alpha: float) -> void:
	var center := r.get_center()
	var rad := p * 0.5
	var fg := Color(UzTheme.col("text"), 0.94 * k * alpha)
	var disc := Color(UzTheme.col("text"), (0.15 if not UzTheme.light else 0.1) * k * alpha)
	if c == "ud":
		# Steuerkreuz hoch/runter (bzw. Pfeiltasten): zwei kleine Spitzen übereinander.
		if gset == "keys":
			ci.draw_style_box(UzTheme.round_box(disc, int(p * 0.24)), r)
		else:
			ci.draw_circle(center, rad - 1, disc)
		var tw := p * 0.2
		var th := p * 0.15
		var gap := p * 0.07
		ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -gap - th * 2.0), center + Vector2(tw, -gap), center + Vector2(-tw, -gap)]), fg)
		ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0, gap + th * 2.0), center + Vector2(-tw, gap), center + Vector2(tw, gap)]), fg)
		return
	if c == "lr":
		# Steuerkreuz links/rechts: dieselben Spitzen nebeneinander.
		if gset == "keys":
			ci.draw_style_box(UzTheme.round_box(disc, int(p * 0.24)), r)
		else:
			ci.draw_circle(center, rad - 1, disc)
		var lw := p * 0.2
		var lh := p * 0.15
		var lg := p * 0.07
		ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-lg - lh * 2.0, 0), center + Vector2(-lg, -lw), center + Vector2(-lg, lw)]), fg)
		ci.draw_colored_polygon(PackedVector2Array([center + Vector2(lg + lh * 2.0, 0), center + Vector2(lg, lw), center + Vector2(lg, -lw)]), fg)
		return
	if gset == "keys":
		# Taste der Tastatur: flache Kappe aus Glas.
		var sb := UzTheme.round_box(disc, int(p * 0.24))
		ci.draw_style_box(sb, r)
		_text(ci, KEYS.get(c, c), r, fg, int(p * 0.48), "medium")
		return
	if c == "guide":
		# Die Guide-Taste trägt das Zeichen: das U-Band flach im Akzent.
		ci.draw_circle(center, rad - 1, disc)
		Logo.draw_mark(ci, center, p * 0.52, Color(UzTheme.col("accent"), 0.96 * k * alpha))
		return
	# Schultertasten und der gedrückte rechte Stick (Suche): Pille mit Kürzel.
	if c in ["lb", "rb", "lt", "rt", "search"]:
		var labels: Dictionary = PS if gset == "ps" else (NINTENDO if gset == "nintendo" else (DECK if gset == "deck" else XBOX))
		var sb2 := UzTheme.round_box(disc, int(p * 0.34))
		ci.draw_style_box(sb2, r)
		_text(ci, labels.get(c, c), r, fg, int(p * 0.42), "bold")
		return
	if c in ["menu", "view"]:
		ci.draw_circle(center, rad - 1, disc)
		var lbl: Dictionary = NINTENDO if gset == "nintendo" else XBOX
		_text(ci, lbl.get(c, ""), r, fg, int(p * 0.55), "bold")
		return
	if gset == "ps":
		ci.draw_circle(center, rad - 1, disc)
		var pc := fg
		var s := rad * 0.4
		match c:
			"a":
				ci.draw_line(center + Vector2(-s, -s), center + Vector2(s, s), pc, 2.2, true)
				ci.draw_line(center + Vector2(-s, s), center + Vector2(s, -s), pc, 2.2, true)
			"b":
				ci.draw_arc(center, s, 0, TAU, 28, pc, 2.2, true)
			"x":
				ci.draw_rect(Rect2(center - Vector2(s, s), Vector2(s, s) * 2), pc, false, 2.2)
			"y":
				var pts := PackedVector2Array(
						[center + Vector2(0, -s * 1.1), center + Vector2(s * 1.05, s * 0.75), center + Vector2(-s * 1.05, s * 0.75), center + Vector2(0, -s * 1.1)])
				ci.draw_polyline(pts, pc, 2.2, true)
		return
	var labels2: Dictionary = NINTENDO if gset == "nintendo" else XBOX
	ci.draw_circle(center, rad - 1, disc)
	_text(ci, labels2.get(c, c), r, fg, int(p * 0.55), "bold")


static func _text(ci: CanvasItem, t: String, r: Rect2, color: Color, fs: int, weight := "bold") -> void:
	var f := UzTheme.font(weight)
	var tt := TranslationServer.translate(t)
	var sz := f.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + (r.size.y - sz.y) * 0.5 + f.get_ascent(fs))
	# Center on the visible glyph, not on line height and advance: otherwise "A" sat up to half a point off center
	# depending on size, which is a whole pixel in 4K.
	var ink := tinte(f, tt, fs)
	if ink.size.x > 0.0:
		pos = r.get_center() - ink.get_center()
	ci.draw_string(f, pos, tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Kasten der sichtbaren Zeichen eines Worts, bezogen auf den Anfang der Grundlinie (gemerkt je Schrift, Wort und Größe).
## Leer, wenn ein Zeichen nicht in der Schrift selbst steckt (Ersatzschrift) – dann gilt die alte Mitte.
static var _tinten := {}


static func tinte(f: Font, t: String, fs: int) -> Rect2:
	var key := "%d|%s|%d" % [f.get_instance_id(), t, fs]
	if _tinten.has(key):
		return _tinten[key]
	var out := Rect2()
	var rids := f.get_rids()
	var ts := TextServerManager.get_primary_interface()
	if not rids.is_empty() and ts and t.length() <= 8:
		var rid: RID = rids[0]
		var gr := Vector2i(fs, 0)
		var x := 0.0
		var erst := true
		for i in t.length():
			var gi := ts.font_get_glyph_index(rid, fs, t.unicode_at(i), 0)
			if gi == 0:
				out = Rect2()
				break
			ts.font_render_glyph(rid, gr, gi)
			var g := Rect2(Vector2(x, 0.0) + ts.font_get_glyph_offset(rid, gr, gi), ts.font_get_glyph_size(rid, gr, gi))
			out = g if erst else out.merge(g)
			erst = false
			x += ts.font_get_glyph_advance(rid, fs, gi).x
	if _tinten.size() > 256:
		_tinten.clear()
	_tinten[key] = out
	return out
