extends Window
## Leitfaden beim Start einer eigenen App (src/core/app_steuerung.gd): kurz der Controller, den du
## gerade benutzt (Xbox-, PlayStation- oder Nintendo-Form, selbst gezeichnet – keine Markenbilder), mit
## der Belegung dieser App an den Tasten. Steht LEITFADEN_MS lang oder bis zum nächsten Druck, bei den
## ersten Starts je App von selbst, später über den Guide („Steuerung“). Derselbe Weg wie die
## Tastenzeile über der App (app_hinweis.gd): ein eigenes kleines Uzai-Fenster – randlos, durchsichtig,
## immer oben, nie fokussierbar, für die Maus durchlässig, nicht in Aufnahmen. Die App behält den Fokus.

const U := preload("res://src/ui/u.gd")
const Bildrate := preload("res://src/core/bildrate.gd")

const BASE := Vector2i(1240, 640)    ## Größe in 1080p-Punkten

const Main := preload("res://src/main.gd")
var main: Main
var _bild: Bild
var _t := 0.0
var _gedrueckt := true               ## eine Taste war schon beim Öffnen unten (zählt nicht als „weiter“)
var _weg := false


func _init() -> void:
	visible = false
	title = "Uzai Leitfaden"
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unfocusable = true
	mouse_passthrough = true
	transient = false
	exclusive = false
	force_native = true
	exclude_from_capture = true
	wrap_controls = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	content_scale_size = BASE
	_bild = Bild.new()
	_bild.anchor_right = 1.0
	_bild.anchor_bottom = 1.0
	add_child(_bild)


## Zeigt den Leitfaden für ms Millisekunden mitten auf Uzais Bildschirm (früher weg beim nächsten Druck).
func zeigen(familie: String, belegung: Dictionary, name: String, ms: int) -> void:
	_bild.familie = familie
	_bild.belegung = belegung
	_bild.titel = name
	var scr := DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	var spos := DisplayServer.screen_get_position(scr)
	var ssize := DisplayServer.screen_get_size(scr)
	var k := clampf(float(ssize.y) / 1080.0, 0.5, 4.0)
	size = Vector2i(roundi(BASE.x * k), roundi(BASE.y * k))
	position = spos + Vector2i((ssize.x - size.x) / 2, (ssize.y - size.y) / 2)
	_bild.modulate.a = 0.0
	visible = true
	# Uzai ruht hinter der App (12 Bilder/s): fürs weiche Ein- und Ausblenden kurz mehr.
	Bildrate.heben(self)
	if Config.is_windows() and Helper.available:
		Helper.run("toast-window", { "hwnd": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id()) }, 2.0)
	var tw := _bild.create_tween()
	tw.tween_property(_bild, "modulate:a", 1.0, U.T_ORT)
	tw.tween_interval(maxf(0.0, ms / 1000.0))
	tw.finished.connect(_ende)


func _process(dt: float) -> void:
	if _weg or not visible:
		return
	_t += dt
	# Guide oder Uzais Tastatur kommen nach vorn: der Leitfaden geht.
	if main and (main._guide != null or bool(main._overlay_mode)):
		_ende()
		return
	var unten := _pad_unten()
	if unten and not _gedrueckt and _t > 0.5:
		_ende()
		return
	_gedrueckt = unten


## Ist an einem Controller gerade eine Taste unten? (Godot liest Controller auch, wenn die App vorn ist.)
static func _pad_unten() -> bool:
	for dev in Input.get_connected_joypads():
		for b in 16:
			if Input.is_joy_button_pressed(dev, b):
				return true
	return false


func _ende() -> void:
	if _weg:
		return
	_weg = true
	var tw := _bild.create_tween()
	tw.tween_property(_bild, "modulate:a", 0.0, U.T_WEG)
	tw.finished.connect(func() -> void:
		Bildrate.senken(self)
		queue_free())


## Das Bild: der Controller und die Belegung an den Tasten. Auch ohne eigenes Fenster nutzbar (Proben).
class Bild extends Control:
	const Glyph := preload("res://src/ui/components/glyph.gd")
	const LINKS := ["lb", "dpad"]
	const RECHTS := ["rb", "y", "x", "b", "a", "rs", "rt"]
	## Lage der Tasten je Form (vom Mittelpunkt des Controllers, 1080p-Punkte).
	const LAGE := {
		"xbox": { "lb": Vector2(-150, -128), "rb": Vector2(150, -128), "rt": Vector2(176, -150), "ls": Vector2(-118, -38),
			"dpad": Vector2(-62, 40), "rs": Vector2(62, 40), "face": Vector2(122, -38), "view": Vector2(-36, -44),
			"menu": Vector2(36, -44), "guide": Vector2(0, -84) },
		"ps": { "lb": Vector2(-150, -126), "rb": Vector2(150, -126), "rt": Vector2(176, -148), "ls": Vector2(-62, 44),
			"dpad": Vector2(-124, -36), "rs": Vector2(62, 44), "face": Vector2(124, -36), "view": Vector2(-96, -86),
			"menu": Vector2(96, -86), "guide": Vector2(0, 12) },
		"nintendo": { "lb": Vector2(-150, -128), "rb": Vector2(150, -128), "rt": Vector2(176, -150), "ls": Vector2(-118, -38),
			"dpad": Vector2(-62, 40), "rs": Vector2(62, 40), "face": Vector2(122, -38), "view": Vector2(-36, -44),
			"menu": Vector2(36, -44), "guide": Vector2(0, -84) },
	}
	## Wo A, B, X und Y am Kreuz der Tasten sitzen (Nintendo: A rechts, B unten, X oben, Y links).
	const KREUZ := {
		"xbox": { "y": Vector2(0, -34), "b": Vector2(34, 0), "a": Vector2(0, 34), "x": Vector2(-34, 0) },
		"ps": { "y": Vector2(0, -34), "b": Vector2(34, 0), "a": Vector2(0, 34), "x": Vector2(-34, 0) },
		"nintendo": { "x": Vector2(0, -34), "a": Vector2(34, 0), "b": Vector2(0, 34), "y": Vector2(-34, 0) },
	}

	var familie := "xbox"
	var belegung := {}
	var titel := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _gset() -> String:
		return familie if familie in ["ps", "nintendo"] else "xbox"

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# Fläche: matt, weich gerundet, mit Haarlinie (Marke: kein Glas).
		var sb := UzTheme.box(Color(UzTheme.col("surface"), 0.96), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
		draw_style_box(sb, r)
		var k := size.y / 640.0
		var c := Vector2(size.x * 0.5, size.y * 0.53)
		if titel != "":
			var f := UzTheme.ui("ui")
			var fs := int(22 * k)
			var tw := f.get_string_size(titel, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(c.x - tw * 0.5, 56 * k), titel, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted"))
		var fam: String = familie if LAGE.has(familie) else "xbox"
		var lage: Dictionary = LAGE[fam]
		var zeilen := _zeilen(c, k, fam, lage)
		_gehaeuse(c, k, fam)
		_linien(zeilen, c, k, lage)
		_tasten(c, k, fam, lage)
		_beschriftung(zeilen, c, k, lage)

	# --- Gehäuse ---------------------------------------------------------------------------------

	func _kapsel(a: Vector2, b: Vector2, rad: float, col: Color) -> void:
		draw_circle(a, rad, col, true, -1.0, true)
		draw_circle(b, rad, col, true, -1.0, true)
		var n := (b - a).normalized().orthogonal() * rad
		draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), col)

	func _rund(rect: Rect2, rad: float, col: Color) -> void:
		var s := StyleBoxFlat.new()
		s.bg_color = col
		s.set_corner_radius_all(int(rad))
		s.anti_aliasing = true
		s.corner_detail = 12
		draw_style_box(s, rect)

	## Die Form aus wenigen weichen Teilen (Körper, zwei Griffe); erst etwas größer in der Haarlinie,
	## dann die Fläche darüber – so bekommt die ganze Form einen feinen Rand.
	func _gehaeuse(c: Vector2, k: float, fam: String) -> void:
		var body := Color(UzTheme.col("surface_hi")).lerp(UzTheme.col("text"), 0.05)
		var rand := UzTheme.col("stroke").lerp(UzTheme.col("text"), 0.12)
		var schulter := body.darkened(0.18)
		var lage: Dictionary = LAGE[fam]
		# Trigger und Schultertasten hinter dem Körper.
		for s in [-1.0, 1.0]:
			var t: Vector2 = c + (lage.rt as Vector2) * Vector2(s, 1.0) * k
			_rund(Rect2(t - Vector2(30, 14) * k, Vector2(60, 30) * k), 13 * k, schulter.darkened(0.12))
		for s in [-1.0, 1.0]:
			var p: Vector2 = c + (lage.rb as Vector2) * Vector2(s, 1.0) * k
			_rund(Rect2(p - Vector2(58, 12) * k, Vector2(116, 26) * k), 12 * k, schulter)
		var lang := 160.0 if fam == "ps" else 138.0
		var griff := 58.0 if fam == "ps" else 64.0
		for pass_ in 2:
			var grow := (2.0 * k) if pass_ == 0 else 0.0
			var col := rand if pass_ == 0 else body
			_rund(Rect2(c + Vector2(-206, -114) * k - Vector2(grow, grow), Vector2(412, 172) * k + Vector2(grow, grow) * 2.0), 74 * k + grow, col)
			for s in [-1.0, 1.0]:
				_kapsel(c + Vector2(146 * s, -12) * k, c + Vector2(178 * s, lang) * k, griff * k + grow, col)

	# --- Tasten ----------------------------------------------------------------------------------

	func _tasten(c: Vector2, k: float, fam: String, lage: Dictionary) -> void:
		var tief := Color(UzTheme.col("bg"), 0.55)
		var ring := Color(UzTheme.col("text"), 0.16)
		# Sticks: Mulde mit Kappe.
		for st in ["ls", "rs"]:
			var p: Vector2 = c + (lage[st] as Vector2) * k
			draw_circle(p, 34 * k, tief, true, -1.0, true)
			draw_circle(p, 24 * k, Color(UzTheme.col("surface_hi")).lerp(UzTheme.col("text"), 0.1), true, -1.0, true)
			draw_arc(p, 24 * k, 0, TAU, 40, ring, 1.5 * k, true)
		# Steuerkreuz.
		var d: Vector2 = c + (lage.dpad as Vector2) * k
		draw_circle(d, 36 * k, tief, true, -1.0, true)
		var arm := Color(UzTheme.col("surface_hi")).lerp(UzTheme.col("text"), 0.14)
		_rund(Rect2(d - Vector2(26, 9) * k, Vector2(52, 18) * k), 4 * k, arm)
		_rund(Rect2(d - Vector2(9, 26) * k, Vector2(18, 52) * k), 4 * k, arm)
		# Kleine Mitteltasten (Ansicht, Menü) und bei PlayStation das Feld oben.
		if fam == "ps":
			# Deckend: die Linie zur Guide-Taste läuft darunter.
			var feld := Color(UzTheme.col("surface_hi")).lerp(UzTheme.col("text"), 0.05).lerp(UzTheme.col("bg"), 0.32)
			_rund(Rect2(c + Vector2(-60, -104) * k, Vector2(120, 66) * k), 12 * k, feld)
		for m in ["view", "menu"]:
			_rund(Rect2(c + (lage[m] as Vector2) * k - Vector2(11, 7) * k, Vector2(22, 14) * k), 7 * k, tief)
		# Tasten am Kreuz: das Zeichen wie in den Hinweisen; was in dieser App nichts tut, leise.
		var kreuz: Dictionary = KREUZ[fam]
		var face: Vector2 = c + (lage.face as Vector2) * k
		draw_circle(face, 62 * k, Color(UzTheme.col("bg"), 0.18), true, -1.0, true)
		var px := int(30 * k)
		for btn in ["a", "b", "x", "y"]:
			var p: Vector2 = face + (kreuz[btn] as Vector2) * k
			var aktiv := belegung.has(btn)
			Glyph.paint(self, btn, px, Rect2(p - Vector2(px, px) * 0.5, Vector2(px, px)), _gset(), 1.0, 1.0 if aktiv else 0.35)
		# Guide: der Punkt der Marke.
		var g: Vector2 = c + (lage.guide as Vector2) * k
		var gp := int((26 if fam == "ps" else 32) * k)
		Glyph.paint(self, "guide", gp, Rect2(g - Vector2(gp, gp) * 0.5, Vector2(gp, gp)), _gset(), 1.0, 1.0)

	# --- Beschriftung ----------------------------------------------------------------------------

	## Wo die Linien an der Taste ansetzen (unter ihr: die Taste deckt den Anfang). A, B, X und Y tragen
	## dasselbe Zeichen wie ihre Zeile und brauchen keine Linie; „Bewegen“ führt zu Steuerkreuz und
	## linkem Stick (beide sind die Pfeiltasten).
	func _anker(btn: String, c: Vector2, k: float, lage: Dictionary) -> Array:
		match btn:
			"dpad":
				return [c + (lage.dpad as Vector2) * k, c + (lage.ls as Vector2) * k]
			"rs":
				return [c + (lage.rs as Vector2) * k]
			"lb":
				return [c + ((lage.lb as Vector2) + Vector2(-50, 0)) * k]
			"rb":
				return [c + ((lage.rb as Vector2) + Vector2(50, 0)) * k]
			"rt":
				return [c + ((lage.rt as Vector2) + Vector2(24, 0)) * k]
		return []

	## Die Zeilen in zwei ruhigen Spalten links und rechts (nach der Höhe ihrer Taste, nie enger als
	## gap): [{ b, seite, y, anker }].
	func _zeilen(c: Vector2, k: float, fam: String, lage: Dictionary) -> Array:
		var out: Array = []
		var gap := 50.0 * k
		for seite in [-1, 1]:
			var liste: Array = (LINKS if seite < 0 else RECHTS).filter(func(b: String) -> bool: return belegung.has(b))
			var zeilen: Array = []
			for b in liste:
				var hoehe: float
				if b in ["a", "b", "x", "y"]:
					hoehe = c.y + ((lage.face as Vector2).y + (KREUZ[fam][b] as Vector2).y) * k
				else:
					hoehe = ((_anker(b, c, k, lage)[0]) as Vector2).y
				zeilen.append({ "b": b, "seite": seite, "h": hoehe, "anker": _anker(b, c, k, lage) })
			zeilen.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.h) < float(q.h))
			var y0 := c.y - 20.0 * k - gap * float(zeilen.size() - 1) * 0.5
			for i in zeilen.size():
				zeilen[i]["y"] = y0 + gap * float(i)
			out.append_array(zeilen)
		return out

	func _linien(zeilen: Array, c: Vector2, k: float, lage: Dictionary) -> void:
		var linie := Color(UzTheme.col("text"), 0.22)
		for z in zeilen:
			var seite := int(z.seite)
			var y := float(z.y)
			var knick := Vector2(c.x + float(seite) * 300.0 * k, y)
			var ende := Vector2(c.x + float(seite) * 322.0 * k, y)
			for a in z.anker:
				draw_polyline(PackedVector2Array([a as Vector2, knick, ende]), linie, 1.5 * k, true)
		if belegung.has("guide"):
			var g: Vector2 = c + (lage.guide as Vector2) * k
			draw_line(g, Vector2(g.x, c.y - 189.0 * k), linie, 1.5 * k, true)

	## Je Zeile Taste und Wort; Guide steht über dem Controller.
	func _beschriftung(zeilen: Array, c: Vector2, k: float, lage: Dictionary) -> void:
		var f := UzTheme.font("medium")
		var fs := int(24 * k)
		for z in zeilen:
			var seite := int(z.seite)
			var y := float(z.y)
			var col_x := c.x + float(seite) * 330.0 * k
			var btn: String = z.b
			var text := TranslationServer.translate(str(belegung[btn]))
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var gw := 30.0 * k * (1.5 if btn in ["lb", "rb", "rt", "rs"] else 1.0)
			var gx := col_x if seite > 0 else col_x - gw
			var tx := gx + gw + 12.0 * k if seite > 0 else gx - 12.0 * k - tw
			_symbol(btn, Rect2(Vector2(gx, y - 15.0 * k), Vector2(gw, 30.0 * k)), k)
			draw_string(f, Vector2(tx, y + f.get_ascent(fs) * 0.5 - 2.0 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
		if belegung.has("guide"):
			var g: Vector2 = c + (lage.guide as Vector2) * k
			var text := TranslationServer.translate(str(belegung.guide))
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(g.x - tw * 0.5, c.y - 199.0 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))

	## Tastensymbol in der Spalte (Steuerkreuz selbst gezeichnet, rechter Stick wie bei der Suche).
	func _symbol(btn: String, r: Rect2, k: float) -> void:
		var px := int(r.size.y)
		match btn:
			"dpad":
				var m := r.get_center()
				draw_circle(m, r.size.y * 0.5 - 1.0, Color(UzTheme.col("text"), 0.15), true, -1.0, true)
				var fg := Color(UzTheme.col("text"), 0.94)
				draw_rect(Rect2(m - Vector2(9, 3) * k, Vector2(18, 6) * k), fg)
				draw_rect(Rect2(m - Vector2(3, 9) * k, Vector2(6, 18) * k), fg)
			"rs":
				Glyph.paint(self, "search", px, r, _gset(), 1.0, 1.0)
			_:
				Glyph.paint(self, btn, px, r, _gset(), 1.0, 1.0)
