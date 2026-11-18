extends Control
## Ersatzbild im Shop, solange das echte Bild lädt (oder wenn es keins gibt): ein ruhiger Verlauf
## in einer Farbe, die zum Spiel gehört (aus der App-ID, also immer dieselbe), zwei weiche
## Lichter und auf Wunsch der Name wie auf einer Kapsel. Liegt in einer runden Bildmaske.

const U := preload("res://src/ui/u.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")

var appid := 0
var title := ""
var show_title := true
var title_px := 0               ## Schriftgröße des Namens (0: passend zur Höhe)
static var _glow: GradientTexture2D


func setup(id: int, t := "", with_title := true) -> Control:
	appid = id
	title = t
	show_title = with_title
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Farbton des Spiels (goldener Schnitt über die ID: Nachbarn sehen verschieden aus).
static func hue_of(id: int) -> float:
	return fposmod(float(absi(id)) * 0.6180339887 + 0.07, 1.0)


static func tint_of(id: int) -> Color:
	return Color.from_hsv(hue_of(id), 0.5, 0.62)


static func glow() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0 or h < 2.0:
		return
	var hue := hue_of(appid)
	var top := Color.from_hsv(hue, 0.42, 0.30)
	var bottom := Color.from_hsv(fposmod(hue + 0.06, 1.0), 0.5, 0.13)
	# Diagonaler Verlauf: oben links am hellsten, unten rechts fast Raum.
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([top.lightened(0.08), top, bottom.darkened(0.2), bottom]))
	var g := glow()
	var light := Color.from_hsv(fposmod(hue - 0.03, 1.0), 0.35, 1.0)
	draw_texture_rect(g, Rect2(w * 0.42, -h * 0.55, w * 0.9, h * 1.4), false, Color(light, 0.2))
	draw_texture_rect(g, Rect2(-w * 0.25, h * 0.35, w * 0.7, h * 1.0), false, Color(light, 0.08))
	if show_title and title != "":
		# Oben links wie ein Schriftzug: unten rechts sitzt auf Karten die Preis-Pille, oben rechts
		# das Herz der Wunschliste.
		var font := UzTheme.display("black")
		var fs := title_px if title_px > 0 else int(clampf(h * 0.15, 16.0, 64.0))
		var pad := maxf(14.0, h * 0.1)
		var tw := w - pad * 2.0 - 40.0
		# Größe nach dem längsten Wort: Kein Wort wird mehr mitten durchgeschnitten („Oute Wild“,
		# „Hollo Knig“). Die Breite wächst mit der Schriftgröße, also einmal nachrechnen reicht.
		var longest := 0.0
		for word in title.split(" ", false):
			longest = maxf(longest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if longest > tw and longest > 0.0:
			fs = maxi(13, int(floorf(fs * tw / longest)) - 1)
		var y := pad + fs * 0.8
		# Der Name eines Spiels wird nie übersetzt (kein tr()).
		draw_multiline_string(font, Vector2(pad, y + 2), title, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 3, Color(0, 0, 0, 0.3))
		draw_multiline_string(font, Vector2(pad, y), title, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 3, Color(1, 1, 1, 0.9))


# --- Bilder unverzerrt zeigen ------------------------------------------------------------------
# Hat Steam für ein Spiel nur ein Querformat-Bild (Kapsel, Kopfbild), wird es in der Hochformat-
# Karte weder gestreckt noch grob beschnitten (beschnitten blieben von 616 × 353 nur gut ein Drittel
# der Breite übrig, ohne Schriftzug und stark vergrößert, also unscharf). Stattdessen liegt das
# ganze Bild scharf etwas über der Mitte, dahinter füllt eine weichgezeichnete Fassung desselben
# Bildes die Karte – Farben und Stimmung bleiben, nichts wirkt leer oder verzogen.

const BG := preload("res://src/ui/components/background.gd")
static var _soft_cache := {}
static var _soft_order: Array = []


## Passt ein Bild zur Form der Fläche (höchstens ein Viertel breiter oder schmaler)? Dann füllt es
## sie, mittig leicht beschnitten. Sonst zeigt draw_art es ganz. fill: erlaubtes Verhältnis der
## Seitenverhältnisse (Bild zu Fläche), unten und oben.
static func fits(tex: Vector2, box: Vector2, fill := Vector2(0.8, 1.25)) -> bool:
	if tex.x <= 0.0 or tex.y <= 0.0 or box.x <= 0.0 or box.y <= 0.0:
		return true
	var r := (tex.x / tex.y) / (box.x / box.y)
	return r >= fill.x and r <= fill.y


## Ausschnitt eines Bildes, der eine Fläche füllt (mittig; zoom > 1 rückt heran). Gleiches
## Seitenverhältnis wie die Fläche – so wird nie verzerrt.
static func cover_src(tex: Vector2, box: Vector2, zoom := 1.0) -> Rect2:
	var sc := maxf(box.x / tex.x, box.y / tex.y) * maxf(zoom, 0.01)
	var src_size := box / sc
	return Rect2((tex - src_size) * 0.5, src_size)


## Platz für das ganze Bild in einer Fläche: eingepasst, waagerecht mittig, senkrecht bei y_at
## (0 oben, 1 unten).
static func fit_rect(tex: Vector2, box: Rect2, y_at := 0.5) -> Rect2:
	var sc := minf(box.size.x / tex.x, box.size.y / tex.y)
	var sz := tex * sc
	return Rect2(box.position + Vector2((box.size.x - sz.x) * 0.5, (box.size.y - sz.y) * y_at), sz)


## Weichgezeichnete Fassung eines Bildes, je Bild gemerkt; null, wenn es sich nicht lesen lässt.
## steps > 0: nur klein gerechnet (etwa 2 × steps Punkte breit) für den Weichzeichner-Shader des
## Hintergrunds (shop_pic.gd); steps = 0: auf der CPU weich wieder vergrößert, zum direkten
## Zeichnen auf kleinen Flächen (Genre-Kacheln).
static func soft_of(t: Texture2D, steps := 0) -> Texture2D:
	if t == null:
		return null
	var key := "%d:%d" % [t.get_instance_id(), steps]
	if _soft_cache.has(key):
		return _soft_cache[key]
	var out: Texture2D = null
	var src := t.get_image()
	if src != null and not src.is_empty():
		var img := BG.soft_image(src, steps if steps > 0 else 12)
		if img != null:
			if steps <= 0:
				img.resize(img.get_width() * 6, img.get_height() * 6, Image.INTERPOLATE_CUBIC)
			out = ImageTexture.create_from_image(img)
	_soft_cache[key] = out
	_soft_order.append(key)
	if _soft_order.size() > 64:
		_soft_cache.erase(_soft_order.pop_front())
	return out


## Bild in eine Fläche zeichnen, nie verzerrt: passt es (fits), füllt es die Fläche; sonst liegt
## es ganz über seiner weichen Fassung (soft, siehe soft_of). zoom wirkt nur auf das Füllende.
## align: wohin das eingepasste Bild rückt (Karten: mittig, etwas über der Preis-Pille).
## backdrop = false: den Hintergrund zeichnet jemand anders (shop_pic.gd mit Shader).
static func draw_art(ci: CanvasItem, t: Texture2D, r: Rect2, soft: Texture2D = null, a := 1.0, zoom := 1.0, align := Vector2(0.5, 0.42), backdrop := true,
		fill := Vector2(0.8, 1.25)) -> void:
	if t == null or r.size.x < 1.0 or r.size.y < 1.0:
		return
	var ts := t.get_size()
	# Helle Bilder leicht gedämpft wie alle Kacheln (Zuschnitt.tone_of).
	var tone := Zuschnitt.tone_of(t)
	if fits(ts, r.size, fill):
		# Ausschnitt dort, wo das Wichtige ist (Zuschnitt), sonst mittig.
		var src := cover_src(ts, r.size, zoom)
		if t.has_meta("uz_look"):
			src = Zuschnitt.window(t.get_meta("uz_look"), ts, src.size)
		ci.draw_texture_rect_region(t, r, src, Color(tone, a))
		return
	if backdrop and soft != null:
		ci.draw_texture_rect_region(soft, r, cover_src(soft.get_size(), r.size, zoom), Color(0.6, 0.6, 0.6, a))
	elif backdrop:
		ci.draw_rect(r, Color(0.06, 0.065, 0.08, a))
	var f := fit_rect(ts, r, align.y)
	f.position.x = r.position.x + (r.size.x - f.size.x) * align.x
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.shadow_color = Color(0, 0, 0, 0.45 * a)
	sh.shadow_size = 18
	sh.shadow_offset = Vector2(0, 6)
	ci.draw_style_box(sh, f)
	ci.draw_texture_rect(t, f, false, Color(tone, a))
