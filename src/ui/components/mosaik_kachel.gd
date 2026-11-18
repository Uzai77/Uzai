extends Control
## Eine Kachel im Mosaik (src/ui/layers/mosaik_seite.gd): ein Spiel, ein Ordner, ein reines Bild
## oder ein Platzhalter – als Scheibe aus Liquid Glass (src/ui/components/glas.gd, docs/DESIGN.md ›
## Mosaik: Liquid Glass). Die Scheibe selbst und ihren Schatten zeichnet die Unterlage der Seite für
## alle Kacheln auf einmal (ein Material, eine Kopie des Schirms); die Kachel liefert dafür Lage,
## Rundung und Fokus. Bilder liegen als Fenster im Glas: ein schmaler Glasrand ringsum, darüber der
## Glanz. Welcher Ausschnitt zu sehen ist, sagt der Fokuspunkt (fx, fy, z). Spiele zeigen auf Wunsch
## unten links klein ihren Schriftzug. Ordner ohne eigenes Bild sind reines Glas mit einer Vorschau
## ihrer ersten Spiele, darunter Name und Anzahl. Ohne Bild: die Ersatz-Hülle mit Titel
## (cover_art.gd). Gewählt: die Scheibe hebt sich, die Lichtkante wird kräftiger, der Glanz wandert –
## kein Rahmen. Auch das leere Feld im Bearbeiten ist eine solche Kachel (art "zelle", ohne Glas).

signal gewaehlt

const U := preload("res://src/ui/u.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")
const Glas := preload("res://src/ui/components/glas.gd")

## { art: spiel|ordner|bild|leer|zelle, spiel, bild {art, pfad, fx, fy}, logo, name, unter,
##   ersatz (Spiel für das Ordnerbild), vorschau (Spiele eines Ordners ohne eigenes Bild) }
var was := {}
var bearbeiten := false
var waehlbar := true              ## ohne Gestalten sind Bilder und Platzhalter nicht wählbar
var gepackt := false              ## wird gerade verschoben (angehoben, mit Zeichen)
var ausschnitt := false           ## Fokuspunkt wird gerade gesetzt
var _t := 0.0
var _tw: Tween
var _clip: Panel
var _flaeche: Control
var _glanz: Control
var _oben: Control
var _rand := 0.0                  ## Glasrand um das Bildfenster (Punkte)


func setup(w: Dictionary, groesse: Vector2) -> Control:
	was = w
	# Keine Mindestgröße: Beim Umbauen morpht die Kachel von ihrer alten Größe zur neuen (size-Tween).
	size = groesse
	return self


func art() -> String:
	return str(was.get("art", ""))


## Zeigt die Kachel ein Bild im Fenster (sonst reines Glas: Ordner mit Vorschau, Platzhalter)?
func fenster() -> bool:
	var a := art()
	return a == "spiel" or a == "bild" or (a == "ordner" and not was.has("vorschau"))


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL if waehlbar else Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP if waehlbar else Control.MOUSE_FILTER_IGNORE
	# Etwas unter der Mitte: Beim Wachsen hebt sich die Scheibe mehr nach oben als nach unten.
	pivot_offset = size * Vector2(0.5, 0.6)
	resized.connect(_neu_masse)
	var a := art()
	if a != "zelle":
		add_to_group(Glas.GRUPPE)
		_rand = rand_px()
	if fenster():
		_fenster()
	elif a == "ordner":
		_vorschau()
	if a != "zelle" and a != "leer":
		_glanz = Glanz.new()
		_glanz.k = self
		_glanz.kante = 1.0 if fenster() else 0.0
		U.full_rect(_glanz)
		if fenster():
			_einruecken(_glanz, _rand)
		add_child(_glanz)
	_oben = Oben.new()
	_oben.k = self
	U.full_rect(_oben)
	add_child(_oben)
	focus_entered.connect(_fokus.bind(true))
	focus_exited.connect(_fokus.bind(false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Größe geändert (Morph beim Umbauen): Drehpunkt, Glasrand und Rundung des Fensters wachsen mit.
func _neu_masse() -> void:
	pivot_offset = size * Vector2(0.5, 0.6)
	if art() == "zelle":
		return
	var neu := rand_px()
	if neu == _rand:
		return
	_rand = neu
	if _clip:
		_einruecken(_clip, _rand)
		_clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), int(innen_radius())))
	if _glanz and fenster():
		_einruecken(_glanz, _rand)


static func _einruecken(c: Control, px: float) -> void:
	c.offset_left = px
	c.offset_top = px
	c.offset_right = -px
	c.offset_bottom = -px


## Das Bildfenster: um den Glasrand eingerückt, eigene (kleinere) Rundung. Die Form schneidet nur zu
## (gezeichnet wird sie nicht, siehe U.clip_round).
func _fenster() -> void:
	var a := art()
	_clip = Panel.new()
	_clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), int(innen_radius())))
	U.clip_round(_clip)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_clip)
	_einruecken(_clip, _rand)
	add_child(_clip)
	if a == "spiel":
		var ca = CoverArt.new()
		ca.compact = size.x < 300.0
		U.full_rect(ca)
		_clip.add_child(ca)
		ca.setup(was.get("spiel", {}))
	else:
		# Ordner bzw. Bild ohne (geladenes) Bild: ein ruhiges Zeichen statt eines Lochs.
		var ic := U.icon("folder" if a == "ordner" else "image", int(clampf(size.y * 0.24, 18, 72)), "faint")
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_clip.add_child(ic)
	_flaeche = Flaeche.new()
	U.full_rect(_flaeche)
	_clip.add_child(_flaeche)
	var b: Dictionary = was.get("bild", {})
	_flaeche.fx = float(b.get("fx", 0.5))
	_flaeche.fy = float(b.get("fy", 0.5))
	_flaeche.z = float(b.get("z", 1.0))
	_laden()
	# Kleine Kachel (großes Raster): nur das Bild, ohne Name und Anzahl.
	if a == "ordner" and _mit_fuss():
		var f := _fuss(true)
		_clip.add_child(f)


func _mit_fuss() -> bool:
	return size.y >= 110.0 and size.x >= 120.0


## Schriftgröße, die mit der Kachel wächst und schrumpft.
func _schrift(anteil: float, lo: float, hi: float) -> int:
	return int(round(clampf(minf(size.x, size.y) * anteil, lo, hi)))


## Ordner ohne eigenes Bild: reines Glas, darin die ersten Spiele als kleine Hüllen, darunter Name
## und Anzahl (in kleinen Kacheln nur die Hüllen bzw. das Zeichen).
func _vorschau() -> void:
	var spiele: Array = was.get("vorschau", [])
	var pad := _rand * 2.0
	var fuss_h := 0.0
	if _mit_fuss():
		var f := _fuss(false)
		add_child(f)
		fuss_h = _schrift(0.085, 15, 30) * 2.4 + pad * 0.5
	if spiele.is_empty():
		var ic := U.icon("folder", int(clampf(size.y * 0.24, 18, 72)), "muted")
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position.y -= fuss_h * 0.5
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ic)
		return
	var n := mini(spiele.size(), 4)
	var flaeche := Vector2(size.x - pad * 2.0, size.y - pad * 2.0 - fuss_h)
	var spalten := n if flaeche.x >= flaeche.y * 1.6 else mini(n, 2)
	var gr := GridContainer.new()
	gr.columns = maxi(1, spalten)
	var luecke := int(maxf(3.0, _rand * 0.8))
	gr.add_theme_constant_override("h_separation", luecke)
	gr.add_theme_constant_override("v_separation", luecke)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(gr)
	gr.offset_left = pad
	gr.offset_top = pad
	gr.offset_right = -pad
	gr.offset_bottom = -pad - fuss_h
	add_child(gr)
	var rr := int(maxf(3.0, innen_radius() * 0.6))
	for i in n:
		var g: Dictionary = spiele[i]
		var p := Panel.new()
		p.add_theme_stylebox_override("panel", UzTheme.box(Color(0, 0, 0, 0.2), rr))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		U.clip_round(p)
		gr.add_child(p)
		# Ohne Bild die Ersatz-Hülle mit Titel, darüber (sobald geladen) die Hülle des Spiels.
		var ca = CoverArt.new()
		ca.compact = true
		U.full_rect(ca)
		p.add_child(ca)
		ca.setup(g)
		var fl := Flaeche.new()
		fl.fy = 0.3
		U.full_rect(fl)
		p.add_child(fl)
		var wf: WeakRef = weakref(fl)
		Media.game_texture(g, "cover", func(t: Texture2D) -> void:
			var f: Control = wf.get_ref()
			if f and t:
				f.set("tex", t)
				f.queue_redraw()
		)


## Bild laden: eigene Datei (nur über Media, Image.load_*_from_buffer mit Größenprüfung), sonst das
## Bild des Spiels in der gewählten Art; fehlt ein Hintergrund, nimmt die Kachel die Hülle.
func _laden() -> void:
	var b: Dictionary = was.get("bild", {})
	# So groß laden, wie die Kachel (mit Zoom) es braucht: Kleine Kacheln teilen sich die üblichen
	# 360er Cover mit dem Regal (ein Bild im Speicher), große bekommen mehr. In 4K rechnet Media hoch.
	var mw := int(clampf(maxf(size.x, size.y) * 1.15 * float(b.get("z", 1.0)), 360.0, 1920.0))
	if mw <= 400:
		mw = 360
	var wf: WeakRef = weakref(_flaeche)
	var setzen := func(t: Texture2D) -> void:
		var f: Control = wf.get_ref()
		if f and t:
			f.set("tex", t)
			f.queue_redraw()
	var g: Dictionary = was.get("spiel", {}) if art() == "spiel" else was.get("ersatz", {})
	var ba := str(b.get("art", ""))
	if ba == "datei":
		Media.file_texture(str(b.get("pfad", "")), mw, setzen)
	elif not g.is_empty():
		var kind := ba if ba in ["cover", "hero", "logo"] else ("hero" if size.x > size.y * 1.4 else "cover")
		Media.game_file(g, kind, func(p: String) -> void:
			if p != "":
				Media.file_texture(p, mw, setzen)
			elif kind != "cover":
				Media.game_texture(g, "cover", setzen)
		)
	if bool(was.get("logo", false)) and art() == "spiel" and not g.is_empty():
		Media.game_texture(g, "logo", func(t: Texture2D) -> void:
			var f: Control = wf.get_ref()
			if f and t:
				f.set("logo", t)
				f.queue_redraw()
		)


## Ordner: Zeichen, Name und Anzahl unten. Auf einem Bild (verlauf) liegt ein weicher dunkler Verlauf
## darunter, auf reinem Glas trägt der Schriftschatten.
func _fuss(verlauf: bool) -> Control:
	var fs := _schrift(0.085, 15, 30)
	var pad := maxf(_rand * 2.0, 10.0)
	var m := U.margin(int(pad), 0, int(pad), int(pad * 0.9))
	m.anchor_top = 1.0
	m.anchor_bottom = 1.0
	m.anchor_right = 1.0
	m.offset_top = -fs * 2.6 - pad
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if verlauf:
		var v := TextureRect.new()
		v.texture = U.fade_texture(true, true)
		v.modulate = Color(0, 0, 0, 0.5)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		v.stretch_mode = TextureRect.STRETCH_SCALE
		m.add_child(v)
	var col := U.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(col)
	var row := U.hbox(int(fs * 0.4))
	var ic := U.icon("folder", int(fs * 0.9), "accent")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var nl := U.shadow(U.ellipsis(U.label(str(was.get("name", "")), str(fs), "text", "bold")))
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(nl)
	col.add_child(row)
	if str(was.get("unter", "")) != "":
		col.add_child(U.shadow(U.ellipsis(U.label(str(was.unter), str(int(fs * 0.78)), "muted", "medium"))))
	return m


## Fokuspunkt und Zoom live setzen (Ausschnitt).
func set_fokuspunkt(fx: float, fy: float, z := 1.0) -> void:
	if _flaeche:
		_flaeche.fx = fx
		_flaeche.fy = fy
		_flaeche.z = z
		_flaeche.queue_redraw()


func hat_bild() -> bool:
	return _flaeche != null and _flaeche.get("tex") != null


func _fokus(on: bool) -> void:
	if _tw:
		_tw.kill()
	# Die gewählte Kachel liegt über ihren Nachbarn: zuletzt gezeichnet (kein z_index – der hübe
	# sie auch über Menüs und Pillen, die darüber liegen).
	if on and get_parent():
		get_parent().move_child(self, -1)
	_tw = U.ankommen(self, U.T_ORT, "mz_fokus").set_parallel(true)
	# Wie ein Cover: minimal wachsen (focus.scale), große Kacheln höchstens ein paar Punkte. Eine
	# angehobene Kachel (Verschieben) steht sichtbar höher: etwas größer, mit tieferem Schatten.
	var s := minf(UzTheme.focus_scale(), 1.0 + 28.0 / maxf(1.0, maxf(size.x, size.y)))
	if gepackt:
		s = maxf(s, 1.0 + 40.0 / maxf(1.0, maxf(size.x, size.y)))
	s = U.wachsen(s) if on else 1.0
	_tw.tween_property(self, "scale", Vector2.ONE * s, U.T_ORT)
	_tw.tween_method(func(v: float) -> void:
		_t = v
		lage_neu()
	, _t, 1.0 if on else 0.0, U.T_ANTWORT)
	if on and is_inside_tree():
		# Das Licht steht links über der gewählten Kachel: alle Lichtkanten drehen sich leicht mit.
		var vs := U.view_size()
		var r := get_global_rect()
		var ziel := (r.get_center() + Vector2(-0.45 * r.size.x, -0.9 * r.size.y - 120.0)) / vs
		Glas.licht_zu(self, ziel)


## Reihenfolge der Scheiben in der Unterlage: gewählte und angehobene zuletzt (oben).
func lage_rang() -> float:
	return _t + (2.0 if gepackt else 0.0)


func lage_neu() -> void:
	if _oben:
		_oben.queue_redraw()
	if _glanz:
		_glanz.queue_redraw()
	queue_redraw()


func activate() -> void:
	gewaehlt.emit()


## Maßstab der Kachel gegenüber einer normalen (6 × 3): Schatten, Rundung, Zeichen und Abstände
## wachsen und schrumpfen mit der Rastergröße.
func groesse_k() -> float:
	return clampf(minf(size.x, size.y) / 238.0, 0.35, 1.8)


func radius() -> int:
	return int(round(clampf(minf(size.x, size.y) * 0.11, 6.0, 34.0)))


## Glasrand um das Bildfenster.
func rand_px() -> float:
	return roundf(clampf(minf(size.x, size.y) * 0.045, 3.0, 12.0))


func innen_radius() -> float:
	return maxf(3.0, float(radius()) - _rand * 0.8)


## Schatten unter der Scheibe – gezeichnet von der Unterlage (ci) der Seite, unter allen Scheiben.
func schatten_zeichnen(ci: CanvasItem, r: Rect2, a: float) -> void:
	var k := groesse_k()
	var sh := StyleBoxFlat.new()
	sh.draw_center = false
	sh.set_corner_radius_all(radius())
	sh.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(0.28 + 0.2 * _t + (0.2 if gepackt else 0.0)) * a)
	sh.shadow_size = int((12 + 16 * _t + (16 if gepackt else 0)) * k)
	sh.shadow_offset = Vector2(0, (6 + 8 * _t) * k)
	ci.draw_style_box(sh, r)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := radius()
	var k := groesse_k()
	var a := art()
	if a == "zelle":
		# Leeres Feld im Bearbeiten: nur eine Haarlinie und ein leises Plus.
		UzTheme.draw_hairline(self, r.grow(-2), rad, Color(UzTheme.col("surface"), 0.35))
		var c := size * 0.5
		var ink := Color(UzTheme.col("faint"), 0.7)
		var arm := 10.0 * k
		draw_line(c - Vector2(arm, 0), c + Vector2(arm, 0), ink, 2.0, true)
		draw_line(c - Vector2(0, arm), c + Vector2(0, arm), ink, 2.0, true)
	if _t > 0.01:
		# Gewählt: ein weicher Schein im Akzent rund um die Scheibe (kein Ring).
		var gl := StyleBoxFlat.new()
		gl.draw_center = false
		gl.set_corner_radius_all(rad)
		gl.shadow_color = Color(UzTheme.col("accent"), 0.2 * _t)
		gl.shadow_size = int(maxf(6.0, 16.0 * k) * _t)
		gl.anti_aliasing = true
		draw_style_box(gl, r)
	if a == "leer":
		# Platzhalter: im Glas ein feines Fadenkreuz.
		var c := size * 0.5
		var rr := clampf(minf(size.x, size.y) * 0.16, 6.0, 34.0)
		var ink := Color(UzTheme.col("text"), 0.6)
		draw_arc(c, rr, 0, TAU, 48, ink, 2.0, true)
		draw_line(c - Vector2(rr * 1.6, 0), c + Vector2(rr * 1.6, 0), ink, 2.0, true)
		draw_line(c - Vector2(0, rr * 1.6), c + Vector2(0, rr * 1.6), ink, 2.0, true)
		draw_circle(c, 2.5, ink)


## Das Bild der Kachel, mit Fokuspunkt zugeschnitten (wie STRETCH_KEEP_ASPECT_COVERED, aber der
## Ausschnitt wandert mit fx/fy), und unten links der Schriftzug.
class Flaeche extends Control:
	var tex: Texture2D
	var logo: Texture2D
	var fx := 0.5
	var fy := 0.5
	var z := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if tex == null:
			return
		var ts := tex.get_size()
		if ts.x <= 0.0 or ts.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
			return
		var s := maxf(size.x / ts.x, size.y / ts.y) * maxf(z, 1.0)
		var src := Vector2(size.x / s, size.y / s)
		var pos := Vector2((ts.x - src.x) * clampf(fx, 0.0, 1.0), (ts.y - src.y) * clampf(fy, 0.0, 1.0))
		draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), Rect2(pos, src))
		if logo == null:
			return
		var ls := logo.get_size()
		if ls.x <= 0.0 or ls.y <= 0.0:
			return
		# Klein wie im Vorbild: höchstens 40 % der Breite und 26 % der Höhe, unten links.
		var k := minf(size.x * 0.4 / ls.x, size.y * 0.26 / ls.y)
		var lz := ls * k
		var pad := clampf(minf(size.x, size.y) * 0.07, 5.0, 22.0)
		var lr := Rect2(Vector2(pad, size.y - pad - lz.y), lz)
		draw_texture_rect(U.fade_texture(true, true), Rect2(0, size.y * 0.55, size.x, size.y * 0.45), false, Color(0, 0, 0, 0.45))
		draw_texture_rect(logo, lr, false)


## Glanz über dem Bildfenster bzw. über reinem Glas (gemeinsames Material, liest den Schirm nicht).
class Glanz extends Control:
	var k: Control
	var kante := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		material = Glas.glanz()
		resized.connect(queue_redraw)

	func _draw() -> void:
		var t: float = k.get("_t")
		var rad: float = float(k.call("innen_radius")) if kante > 0.0 else float(k.call("radius"))
		draw_rect(Rect2(Vector2.ZERO, size), Glas.farbe(t, rad, size, kante, 1.0))


## Über allem: im Bearbeiten die Zeichen (angehoben, Ausschnitt).
class Oben extends Control:
	var k: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if bool(k.get("gepackt")) or bool(k.get("ausschnitt")):
			# Zeichen oben rechts im Akzent: diese Kachel bewegt sich gerade mit dem Steuerkreuz.
			var g: float = k.call("groesse_k")
			var rr := maxf(8.0, 17.0 * g)
			var c := Vector2(size.x - rr - 9 * g, rr + 9 * g)
			draw_circle(c, rr, UzTheme.col("accent"))
			var ip := int(maxf(10.0, 20.0 * g))
			var tex := Icons.tex("move" if bool(k.get("gepackt")) else "image", ip)
			if tex:
				draw_texture_rect(tex, Rect2(c - Vector2(ip, ip) * 0.5, Vector2(ip, ip)), false, UzTheme.col("bg"))
