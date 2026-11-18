extends Control
## Ein Abzeichen als Medaille – eigene Zeichnung, kein fremdes Logo. Form je Kategorie
## (Sechseck Spielzeit, Siegel Erfolge, Schild Komplett, Raute Vielfalt, Kreis Gemeinsam,
## Achteck Treue, Kassette Retro), Metall je Stufe (Bronze, Silber, Gold, Platin mit Schimmer),
## in der Mitte ein Zeichen bzw. der Kurzname der Plattform („PS2“), unten Punkte für die Stufe.
## Gesperrt: Graphit, gedämpftes Zeichen, außen ein feiner Ring mit dem Fortschritt.
##
## Gezeichnet als SVG zur Laufzeit in der Größe, in der es erscheint (doppelt gerastert, scharf
## auf 4K); der Kurzname kommt als Schrift darüber (Godot-Schrift, ebenfalls scharf).
##
## Spielzeit je Plattform: statt des Kurznamens das echte Logo der Konsole (badge_logos.gd – zur
## Laufzeit von Wikimedia Commons geladen, nicht im Repository, eigene Datei im Medienordner
## gewinnt). Es wird einfarbig im Metall der Stufe eingeprägt (helle Fläche, Schatten darunter,
## feine Glanzkante darüber), Seitenverhältnis bleibt, nie hochgezogen; gesperrt grau. Fehlt das
## Logo (offline, nicht gefunden), bleibt der Kurzname; kommt es später an, zeichnet sich die
## Medaille neu.

const METALS := [
	# Rand hell, Rand mittel, Rand dunkel, Fläche oben, Fläche unten, Zeichen
	["#4a4d55", "#33363c", "#202226", "#22242a", "#141518", "#7d818b"],
	["#ffd2a8", "#c97c46", "#6e3a1a", "#3e2616", "#1b100a", "#ffcf9e"],
	["#ffffff", "#bcc5cf", "#5f6975", "#2b3138", "#121519", "#f2f6fa"],
	["#fff3b8", "#e8bf52", "#8d5f0e", "#3f3111", "#191306", "#ffe390"],
	["#ffffff", "#bfe6f3", "#5f86a8", "#1f2d3a", "#0d141b", "#e9fbff"],
]

const SHAPES := { "zeit": "hex", "erfolge": "seal", "komplett": "shield", "vielfalt": "diamond", "sozial": "circle", "treue": "oct", "retro": "cart" }

## Eigene Zeichen (24er Raster); die übrigen kommen aus Uzais Linien-Icons (icons.gd).
const GLYPHS := {
	"cart": '<path d="M6.5 3.5h11v13l-2 2v2h-7v-2l-2-2Z"/><rect x="9" y="6.5" width="6" height="5" rx=".6"/>',
	"handheld": '<rect x="6" y="2.5" width="12" height="19" rx="2"/><rect x="8.5" y="5" width="7" height="6" rx=".6"/><path d="M8.6 16h3M10.1 14.5v3"/><circle cx="15" cy="15.2" r=".8" fill="#fff"/><circle cx="14" cy="17.4" r=".8" fill="#fff"/>',
	"diamond": '<path d="M6.5 4.5h11l3.5 4.8L12 20 3 9.3Z"/><path d="M3 9.3h18M9.5 4.5 8 9.3 12 20l4-10.7-1.5-4.8"/>',
	"crown": '<path d="M3.5 8.5 8 12l4-6.5 4 6.5 4.5-3.5-1.8 9.5H5.3Z"/><path d="M5.3 21h13.4"/>',
	"flag": '<path d="M5.5 21.5V3"/><path d="M5.5 4h12l-2.6 4 2.6 4h-12"/>',
	"layers": '<path d="M12 3.5 3 8l9 4.5L21 8Z"/><path d="M3 12l9 4.5 9-4.5M3 16l9 4.5 9-4.5"/>',
	"flame": '<path d="M12 21.5c-3.9 0-6.8-2.8-6.8-6.5 0-3.3 2.1-5.2 3.5-7.3.5 1.6 1.4 2.6 2.4 3.1C11 7 12.4 4.3 14.8 2.5c-.3 3.1 4 5.6 4 11.3 0 4.4-3 7.7-6.8 7.7Z"/><path d="M12 21.5c-1.8 0-3.1-1.4-3.1-3.2 0-1.8 1.5-3 3.1-5.2 1.6 2.2 3.1 3.4 3.1 5.2 0 1.8-1.3 3.2-3.1 3.2Z"/>',
	"calendar": '<rect x="4" y="5.5" width="16" height="15" rx="1.5"/><path d="M4 10h16M8.5 3v4.5M15.5 3v4.5M8 14h2M14 14h2M8 17h2M14 17h2"/>',
	"hourglass": '<path d="M6.5 3h11M6.5 21h11"/><path d="M7.5 3c0 5 4.5 6 4.5 9s-4.5 4-4.5 9M16.5 3c0 5-4.5 6-4.5 9s4.5 4 4.5 9"/><path d="M9.8 18.2h4.4"/>',
	"medal": '<path d="M8 2.5l4 6 4-6"/><circle cx="12" cy="15" r="6"/><path d="M12 12.2l.9 1.9 2 .2-1.5 1.3.5 2-1.9-1.1-1.9 1.1.5-2-1.5-1.3 2-.2Z"/>',
}

const Logos := preload("res://src/core/badge_logos.gd")

static var _cache := {}

var def: Dictionary = {}
var tier := 0
var px := 120
var ring := -1.0             ## 0…1: Fortschritt außen (nur gesperrt/teilweise), < 0 aus
var pips := true             ## Punkte für die Stufe
var glow := 0.0              ## 0…1: Schein dahinter (Pop-up, gewählt)
var _tex: Texture2D


func setup(d: Dictionary, t: int, size_px := 120, progress := -1.0) -> Control:
	def = d
	tier = clampi(t, 0, 4)
	px = size_px
	ring = progress
	return self


func _ready() -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex = texture_for(def, tier, px, pips)
	# Logo noch nicht da: neu zeichnen, sobald es geladen ist.
	if Logos.group_of(def) != "" and not has_logo(_tex):
		var l := Logos.loader()
		if l and not l.is_connected("logo_ready", _on_logo):
			l.connect("logo_ready", _on_logo)
	queue_redraw()


func _on_logo(key: String) -> void:
	if not Logos.keys_for(def, top_system(def)).has(key):
		return
	_tex = texture_for(def, tier, px, pips)
	queue_redraw()


func set_glow(v: float) -> void:
	glow = v
	queue_redraw()


func _draw() -> void:
	var s := float(px)
	var r := Rect2(Vector2.ZERO, Vector2(s, s))
	if glow > 0.01:
		var gc := Color(METALS[maxi(tier, 1)][1])
		for i in 6:
			var k := 1.0 - float(i) / 6.0
			draw_circle(r.get_center(), s * (0.42 + 0.16 * (1.0 - k)), Color(gc, 0.07 * glow * k))
	if ring >= 0.0 and tier < 4:
		var c := r.get_center()
		var rr := s * 0.5 - 2.0
		draw_arc(c, rr, 0.0, TAU, 72, UzTheme.col("text", 0.08), 3.0, true)
		if ring > 0.004:
			draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * clampf(ring, 0.0, 1.0), maxi(8, int(72 * ring)), UzTheme.col("accent", 0.9), 3.0, true)
	var inset := s * 0.07 if ring >= 0.0 and tier < 4 else 0.0
	if _tex:
		draw_texture_rect(_tex, r.grow(-inset), false)
	draw_mark(self, r.grow(-inset), def, tier, 1.0, _tex)


## Ob in der Textur schon das Logo der Konsole steckt (dann kein Kurzname darüber).
static func has_logo(tex: Texture2D) -> bool:
	return tex != null and tex.has_meta("uz_logo")


## System mit der meisten Spielzeit in der Gruppe des Abzeichens (aus Badges.facts) oder "".
static func top_system(d: Dictionary) -> String:
	var g := Logos.group_of(d)
	if g == "":
		return ""
	var ml := Engine.get_main_loop()
	var b: Node = (ml as SceneTree).root.get_node_or_null("/root/Badges") if ml is SceneTree else null
	if b == null:
		return ""
	var f: Variant = b.get("facts")
	return str((f as Dictionary).get("top_" + g, "")) if f is Dictionary else ""


## Kurzname der Plattform („PS2“) mitten auf die Medaille in rect (auch für die Pop-ups); nicht,
## wenn die Textur tex schon das Logo trägt.
static func draw_mark(ci: CanvasItem, rect: Rect2, d: Dictionary, t: int, alpha := 1.0, tex: Texture2D = null) -> void:
	var mark := str(d.get("mark", ""))
	if mark == "" or has_logo(tex):
		return
	var f := UzTheme.display("black")
	var inner := rect.size.x
	var fs := int(inner * (0.27 if mark.length() <= 3 else 0.22))
	if fs < 4:
		return
	var w := f.get_string_size(TranslationServer.translate(mark), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var col := Color(str(METALS[clampi(t, 0, 4)][5]))
	col.a = (0.75 if t == 0 else 1.0) * alpha
	var c := rect.get_center()
	var y := c.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5 - inner * 0.03
	ci.draw_string(f, Vector2(c.x - w * 0.5 + 1.0, y + 1.5), TranslationServer.translate(mark), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45 * alpha))
	ci.draw_string(f, Vector2(c.x - w * 0.5, y), TranslationServer.translate(mark), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Textur einer Medaille (zwischengespeichert je Form, Zeichen, Stufe und Größe).
static func texture_for(d: Dictionary, t: int, size_px: int, with_pips := true) -> Texture2D:
	var shape := str(SHAPES.get(str(d.get("cat", "")), "circle"))
	var logo := Logos.image_for(d, top_system(d))
	var glyph := "" if str(d.get("mark", "")) != "" or not logo.is_empty() else str(d.get("glyph", "star"))
	var key := "%s|%s|%d|%d|%s|%s" % [shape, glyph, t, size_px, with_pips, str(logo.get("key", ""))]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	var scale := float(size_px) / 100.0 * 2.0
	var err := img.load_svg_from_string(svg(shape, glyph, t, with_pips), scale)
	if err != OK:
		img = Image.create(size_px * 2, size_px * 2, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	if not logo.is_empty():
		emboss(img, logo.img, t, scale, t > 0 and with_pips)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	if not logo.is_empty():
		tex.set_meta("uz_logo", str(logo.key))
	_cache[key] = tex
	return tex


## Das Logo in die Fläche der Medaille prägen (img im 100er Raster mal scale): Glanzkante oben,
## Schatten unten, darauf die Fläche im Metall der Stufe.
static func emboss(img: Image, logo: Image, t: int, scale: float, lift: bool) -> void:
	var m: Array = METALS[clampi(t, 0, 4)]
	var src := Vector2i(logo.get_width(), logo.get_height())
	var box := Logos.box_for(float(src.x) / float(maxi(src.y, 1))) * scale
	var sz := Logos.fit(src, box)
	if sz.x < 2 or sz.y < 2:
		return
	var c := Vector2(50.0, 47.0 if lift else 50.0) * scale
	var pos := Vector2i(roundi(c.x - sz.x * 0.5), roundi(c.y - sz.y * 0.5))
	var top: Color
	var bottom: Color
	var alpha := 1.0
	if t == 0:
		top = Color(str(m[5])).lerp(Color.WHITE, 0.08)
		bottom = Color(str(m[5])).darkened(0.18)
		alpha = 0.72
	else:
		top = Color(str(m[5])).lerp(Color.WHITE, 0.22)
		bottom = Color(str(m[1])).lerp(Color(str(m[5])), 0.35)
	var face := Logos.tinted(logo, sz, top, bottom, alpha)
	var whole := Rect2i(Vector2i.ZERO, sz)
	var d := maxi(1, roundi(scale * 0.9))
	var shadow := Logos.silhouette(face, Color(0, 0, 0, 0.6 if t > 0 else 0.45))
	var shine := Logos.silhouette(face, Color(1, 1, 1, 0.22 if t > 0 else 0.08))
	img.blend_rect(shine, whole, pos - Vector2i(0, maxi(1, d / 2)))
	img.blend_rect(shadow, whole, pos + Vector2i(0, d))
	img.blend_rect(face, whole, pos)


## Die Medaille als SVG (100er Raster).
static func svg(shape: String, glyph: String, t: int, with_pips := true) -> String:
	var m: Array = METALS[clampi(t, 0, 4)]
	var outer := _shape(shape, 50.0, 50.0, 47.0)
	var inner := _shape(shape, 50.0, 50.0, 38.5)
	var line := _shape(shape, 50.0, 50.0, 41.5)
	var defs := '<defs>'
	defs += '<linearGradient id="rim" x1="0.15" y1="0" x2="0.85" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.45" stop-color="%s"/>' % [m[0], m[1]]
	if t == 4:
		defs += '<stop offset="0.7" stop-color="#e6d6ff"/>'
	defs += '<stop offset="1" stop-color="%s"/></linearGradient>' % m[2]
	defs += '<radialGradient id="face" cx="0.38" cy="0.28" r="0.85"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient>' % [m[3],
			m[4]]
	defs += '<linearGradient id="hi" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="%s"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/></linearGradient>' % ("0.10" if t == 0 else "0.22")
	defs += '</defs>'
	var body := ''
	# Schatten unter der Medaille, dann Rand, Fläche, feine Linie, Glanz.
	body += '<g transform="translate(0 1.6)" opacity="0.35">%s</g>' % outer.replace("FILL", "#000000")
	body += outer.replace("FILL", "url(#rim)")
	body += inner.replace("FILL", "url(#face)")
	body += line.replace("FILL", "none").replace("/>", ' stroke="%s" stroke-opacity="%s" stroke-width="1.1"/>' % [m[0], "0.25" if t == 0 else "0.55"])
	if t == 4:
		# Platin: feine Strahlen auf der Fläche.
		var rays := ''
		for i in 12:
			var a := TAU * float(i) / 12.0
			rays += 'M50 50L%.2f %.2f' % [50.0 + cos(a) * 36.0, 50.0 + sin(a) * 36.0]
		body += '<path d="%s" stroke="#bfefff" stroke-opacity="0.13" stroke-width="2.4"/>' % rays
	body += inner.replace("FILL", "url(#hi)")
	if glyph != "":
		var g := str(GLYPHS.get(glyph, Icons.P.get(glyph, Icons.P.get("star", ""))))
		var col := str(m[5])
		g = g.replace('fill="#fff"', 'fill="%s"' % col)
		var op := "0.7" if t == 0 else "1"
		var k := 1.75
		var off := 50.0 - 12.0 * k
		body += '<g transform="translate(%.2f %.2f) scale(%.3f)" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">%s</g>' % [off, off - 3.0 if t > 0 and with_pips else off, k, col, op, g]
	if t > 0 and with_pips:
		var n := t
		var gap := 6.0
		var x0 := 50.0 - gap * float(n - 1) * 0.5
		for i in n:
			body += '<circle cx="%.2f" cy="77" r="1.9" fill="%s"/>' % [x0 + gap * i, m[5]]
	return '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">%s%s</svg>' % [defs, body]


## Umriss einer Form mit Mittelpunkt (cx, cy) und „Radius“ r; FILL wird ersetzt.
static func _shape(shape: String, cx: float, cy: float, r: float) -> String:
	match shape:
		"circle":
			return '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="FILL"/>' % [cx, cy, r]
		"hex":
			return '<polygon points="%s" fill="FILL" stroke-linejoin="round"/>' % _poly(cx, cy, r, 6, -PI * 0.5, 1.0)
		"oct":
			return '<polygon points="%s" fill="FILL"/>' % _poly(cx, cy, r, 8, PI / 8.0, 1.0)
		"seal":
			return '<polygon points="%s" fill="FILL"/>' % _poly(cx, cy, r, 32, 0.0, 0.92)
		"diamond":
			var q := r * 0.96
			var rad := r * 0.16
			return '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" transform="rotate(45 %.2f %.2f)" fill="FILL"/>' % [cx - q * 0.72, cy - q * 0.72,
					q * 1.44, q * 1.44, rad, cx, cy]
		"cart":
			var w := r * 1.62
			var h := r * 1.86
			return '<path d="M%.2f %.2fh%.2fl%.2f %.2fv%.2fa%.2f %.2f 0 0 1-%.2f %.2fh-%.2fa%.2f %.2f 0 0 1-%.2f-%.2fZ" fill="FILL"/>' % [
				cx - w * 0.5, cy - h * 0.5, w * 0.78, w * 0.22, w * 0.22, h - w * 0.22 - r * 0.2, r * 0.2, r * 0.2, r * 0.2, r * 0.2,
				w - r * 0.4, r * 0.2, r * 0.2, r * 0.2, r * 0.2]
		"shield":
			var w2 := r * 0.86
			return '<path d="M%.2f %.2fC%.2f %.2f %.2f %.2f %.2f %.2fV%.2fC%.2f %.2f %.2f %.2f %.2f %.2fC%.2f %.2f %.2f %.2f %.2f %.2fV%.2fC%.2f %.2f %.2f %.2f %.2f %.2fZ" fill="FILL"/>' % [
				cx, cy - r,
				cx + w2 * 0.45, cy - r * 0.78, cx + w2 * 0.8, cy - r * 0.8, cx + w2, cy - r * 0.78,
				cy + r * 0.05,
				cx + w2, cy + r * 0.55, cx + w2 * 0.45, cy + r * 0.85, cx, cy + r,
				cx - w2 * 0.45, cy + r * 0.85, cx - w2, cy + r * 0.55, cx - w2, cy + r * 0.05,
				cy - r * 0.78,
				cx - w2 * 0.8, cy - r * 0.8, cx - w2 * 0.45, cy - r * 0.78, cx, cy - r]
	return '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="FILL"/>' % [cx, cy, r]


## Eckpunkte eines Vielecks; inner < 1: jede zweite Ecke eingezogen (Siegel).
static func _poly(cx: float, cy: float, r: float, n: int, rot: float, inner: float) -> String:
	var pts := PackedStringArray()
	for i in n:
		var a := rot + TAU * float(i) / float(n)
		var rr := r if i % 2 == 0 or inner >= 1.0 else r * inner
		pts.append("%.2f,%.2f" % [cx + cos(a) * rr, cy + sin(a) * rr])
	return " ".join(pts)
