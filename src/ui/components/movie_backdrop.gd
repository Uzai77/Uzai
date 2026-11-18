extends Control
## Das große Hintergrundbild eines Films – wie in Nuvio TV, scharf statt Lichtschein.
##
## Arten (layout):
##  hero    – Startseite: oben rechts (70 % der Breite, knapp zwei Drittel der Höhe). Das Bild selbst
##            wird nach links und unten durchsichtig (Maske), so geht es nahtlos in Uzais Raum mit
##            seinen Lichtern über; oben ist es zurückgenommen, damit die Leiste lesbar bleibt.
##  full    – Detailseite: ganzer Bildschirm, nach links (78 %) und unten (ab 38 %) ausgeblendet.
##  streams – Quellenwahl: ganzer Bildschirm, zu beiden Seiten dunkel, in der Mitte offen.
## Der Wechsel zwischen Titeln blendet kurz über. Schon geladene Bilder stehen sofort da; neue
## werden erst geholt, wenn man einen Augenblick (DWELL) stehen bleibt – schnelles Blättern lädt
## so nicht jedes Bild unterwegs. Ohne Bild steht ein ruhiges Farbfeld in der Farbe des Titels da.

const U := preload("res://src/ui/u.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const Leicht := preload("res://src/core/leicht.gd")

const DWELL := 0.09                ## so lange stehen bleiben, bevor ein neues Bild geladen wird
const CROSS := 0.42                ## Überblenden zwischen zwei Titeln (ruhig, nicht schlagartig)
const IMG_IN := 0.18               ## das geladene Bild über dem Farbfeld einblenden
const WARTEN := 0.45               ## so lange (nach DWELL) auf das Bild warten, dann erst das Farbfeld

## Zuletzt geladene Bilder (Adresse@Breite -> WeakRef): hält nichts fest, findet aber, was Media
## noch im Speicher hat – beim Zurückblättern steht das Bild dann ohne Warten und Blenden da.
static var _seen := {}

var layout := "hero"
var item: Dictionary = {}
var dim := 0.0                     ## zusätzlich abdunkeln (Detailseite beim Blättern)
var _slides: Array = []
var _front := 0
var _mask: TextureRect
var _shade: Control
var _ground := Color(0, 0, 0)
var _key := ""
var _gen := 0
var _front_gen := -1               ## welcher Titel (_gen) vorn steht


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	clip_contents = layout == "hero"
	var holder: Control = self
	if layout == "hero":
		_mask = TextureRect.new()
		_mask.texture = hero_mask()
		_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mask.stretch_mode = TextureRect.STRETCH_SCALE
		_mask.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_mask)
		holder = _mask
	for i in 2:
		var s := Control.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.modulate.a = 0.0
		var ph := TextureRect.new()
		ph.name = "Ph"
		ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ph.stretch_mode = TextureRect.STRETCH_SCALE
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.add_child(ph)
		var img := TextureRect.new()
		img.name = "Img"
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.add_child(img)
		holder.add_child(s)
		_slides.append(s)
	_shade = Control.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.draw.connect(_draw_shade)
	add_child(_shade)
	_ground = _room()
	resized.connect(_fit)
	_fit()


## Geteilte Elemente (src/ui/flug.gd): das Bild, das gerade vorn steht (sonst das Farbfeld).
func flug_bild() -> Dictionary:
	if _slides.is_empty():
		return {}
	var s: Control = _slides[_front]
	var img := s.get_node("Img") as TextureRect
	var n: TextureRect = img if img.texture else s.get_node("Ph") as TextureRect
	if n.texture == null:
		return {}
	return { "node": n, "radius": 0.0, "tint": Color.WHITE }


## Wo das Bild liegt (in eigenen Koordinaten).
func image_rect() -> Rect2:
	if layout == "hero":
		# Gut 16 : 9 statt 2,2 : 1: Vorschaubilder und Filmbilder werden oben und unten kaum noch
		# beschnitten (wirkten „einen Ticken zu nah“); unten läuft die Maske ohnehin unter die Reihen.
		var h := roundf(size.y * 0.64)
		return Rect2(size.x * 0.30, 0, size.x * 0.70, h)
	return Rect2(Vector2.ZERO, size)


func _fit() -> void:
	var r := image_rect()
	if _mask:
		_mask.position = r.position
		_mask.size = r.size
	for s in _slides:
		var c := s as Control
		c.position = Vector2.ZERO if _mask else r.position
		c.size = r.size
		c.pivot_offset = r.size * Vector2(0.6, 0.35)
		for ch in c.get_children():
			(ch as Control).position = Vector2.ZERO
			(ch as Control).size = r.size
	_shade.position = Vector2.ZERO
	_shade.size = size
	_shade.queue_redraw()


## Raumfarbe: aus dem Hintergrund von Uzai (getönt), sonst das Graphit des Farbschemas.
func _room() -> Color:
	var p := get_parent()
	if p and p.has_method("ground"):
		var c: Color = p.call("ground")
		return Color(c, 1.0)
	return UzTheme.col("bg")


func _process(_dt: float) -> void:
	var g := _room()
	if not g.is_equal_approx(_ground):
		_ground = g
		_shade.queue_redraw()


## Titel zeigen. instant: ohne Überblenden (erster Aufbau).
## Neben background bzw. thumbnail versteht der Eintrag „_urls“ (mehrere Adressen, die größte
## zuerst – Videos: maxres, dann hq) und „_ph“ (eigenes Farbfeld, etwa in der Farbe des Kanals).
##
## Übergeblendet wird erst, wenn das neue Bild fertig ist (dekodiert und zugeschnitten im
## Hintergrund-Thread, Media): Beim Zappen bleibt das letzte Bild ruhig stehen, statt erst auf das
## Farbfeld und dann, mitten im Gleiten, auf das Bild zu springen. Kommt es nicht in WARTEN, blendet
## das Farbfeld über und das Bild erscheint später darauf (ohne Sprung).
func show_item(it: Dictionary, instant := false) -> void:
	var key := str(it.get("id", ""))
	if key == _key and not it.is_empty():
		return
	_key = key
	item = it
	_gen += 1
	var gen := _gen
	if it.is_empty():
		for s in _slides:
			U.tw(s, "uz_bd").tween_property(s, "modulate:a", 0.0, CROSS)
		return
	var ph: Texture2D = it._ph if it.get("_ph") is Texture2D else (Art.backdrop_tex(key) if key != "" else null)
	var urls := urls_of(it)
	var known: Texture2D = null
	for u in urls:
		known = _known(str(u))
		if known:
			break
	# Steht noch gar nichts da (erster Aufbau): das Farbfeld sofort, das Bild kommt darüber.
	var leer := true
	for s in _slides:
		if (s as Control).modulate.a > 0.01:
			leer = false
	if known or urls.is_empty() or instant or leer:
		_blende(gen, ph, known, instant)
		if known or urls.is_empty():
			return
	# Beim schnellen Blättern erst laden, wenn man kurz stehen bleibt (nur das Ziel).
	if not instant:
		await get_tree().create_timer(DWELL).timeout
		if gen != _gen or not is_inside_tree():
			return
		# Kommt das Bild nicht bald, erst das Farbfeld – der Text steht schon beim neuen Titel.
		get_tree().create_timer(WARTEN).timeout.connect(_warten_vorbei.bind(gen, ph))
	_lade(urls, func(t: Texture2D) -> void:
		if gen != _gen or not is_inside_tree():
			return
		if t == null:
			if _front_gen != gen:
				_blende(gen, ph, null, false)
			return
		if _front_gen == gen:
			# Das Farbfeld dieses Titels steht schon: das Bild blendet darauf ein.
			var img := (_slides[_front] as Control).get_node("Img") as TextureRect
			img.texture = t
			U.tw(img, "uz_fade").tween_property(img, "modulate:a", 1.0, IMG_IN)
		else:
			_blende(gen, ph, t, false)
	, true)


func _warten_vorbei(gen: int, ph: Texture2D) -> void:
	if gen == _gen and _front_gen != gen:
		_blende(gen, ph, null, false)


## Den Titel gen auf die weniger sichtbare Ebene legen und überblenden: Farbfeld ph, darüber das
## Bild tex (oder noch keins).
func _blende(gen: int, ph: Texture2D, tex: Texture2D, instant: bool) -> void:
	_front_gen = gen
	var a0 := (_slides[0] as Control).modulate.a
	var a1 := (_slides[1] as Control).modulate.a
	var ni := 1 - _front if is_equal_approx(a0, a1) else (0 if a0 < a1 else 1)
	var nxt: Control = _slides[ni]
	var old: Control = _slides[1 - ni]
	_front = ni
	nxt.get_parent().move_child(nxt, 1)
	var phr := nxt.get_node("Ph") as TextureRect
	var img := nxt.get_node("Img") as TextureRect
	U.stop(img, "uz_fade")
	U.stop(nxt, "uz_bd")
	phr.texture = ph
	img.texture = tex
	img.modulate.a = 1.0 if tex else 0.0
	# The image stays still (no camera move any more: resetting the scale from 1.03 to 1 looked like
	# zooming out and stuttering).
	nxt.scale = Vector2.ONE
	U.stop(old, "uz_bd")
	if instant:
		nxt.modulate.a = 1.0
		old.modulate.a = 0.0
		return
	# Das neue legt sich über das alte, das alte bleibt darunter voll stehen und geht erst danach:
	# Beide halb durchsichtig übereinander (Geisterbild, Raum scheint durch) gibt es so nicht.
	nxt.modulate.a = 0.0
	if old.modulate.a < 0.99:
		# Mitten in einem Wechsel: Das ältere blendet zügig mit, statt stehen zu bleiben.
		U.tw(old, "uz_bd", Tween.TRANS_SINE, Tween.EASE_IN_OUT).tween_property(old, "modulate:a", 0.0, CROSS)
	var tw := U.tw(nxt, "uz_bd", Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	tw.tween_property(nxt, "modulate:a", 1.0, CROSS)
	var ow: WeakRef = weakref(old)
	tw.finished.connect(func() -> void:
		var o: Control = ow.get_ref()
		if o and gen == _front_gen:
			U.stop(o, "uz_bd")
			o.modulate.a = 0.0)


## Die Adressen eines Eintrags, die größte zuerst.
static func urls_of(it: Dictionary) -> Array:
	var urls: Array = (it._urls as Array).filter(func(u: Variant) -> bool: return str(u) != "") if it.get("_urls") is Array else []
	if urls.is_empty() and Art.backdrop_url(it) != "":
		urls = [Art.backdrop_url(it)]
	return urls


## Breite fürs Laden ohne feste Fläche (Detailseite, Quellenwahl).
func _breite() -> int:
	return 1920 if layout != "hero" else 1400


## Oben rechts (hero) wird nur der sichtbare Ausschnitt in Schirmgröße geladen – ohne Mipmaps, im
## Hintergrund-Thread zugeschnitten (Media.url_fit): ein Drittel des Hochladens von früher.
func _flaeche() -> Vector2:
	return image_rect().size if layout == "hero" and size.x > 0.0 else Vector2.ZERO


func _lade(urls: Array, cb: Callable, dringend := false) -> void:
	var a := _flaeche()
	if a != Vector2.ZERO:
		Media.url_fit_chain(urls, a, cb, dringend)
	else:
		var w := _breite()
		Media.url_texture_chain(urls, w, func(t: Texture2D) -> void:
			if t:
				_remember(str(urls[0]), w, t)
			cb.call(t)
		)


## Bilder der Nachbarn vorladen (nicht dringend: sie warten, während der Hintergrund überblendet).
## Je Eintrag eine Adresse oder eine Liste (die größte zuerst). Danach stehen sie beim
## Weiterblättern sofort da.
func vorladen(liste: Array) -> void:
	for e in liste:
		var urls: Array = (e as Array) if e is Array else [e]
		urls = urls.filter(func(u: Variant) -> bool: return str(u) != "")
		if urls.is_empty():
			continue
		var da := false
		for u in urls:
			if _known(str(u)):
				da = true
				break
		if not da:
			_lade(urls, func(_t: Texture2D) -> void: pass)


## Schon fertig geladen (Media hat es noch)? Lädt nichts.
func _known(url: String) -> Texture2D:
	var a := _flaeche()
	if a != Vector2.ZERO:
		return Media.cached_url_fit(url, a)
	var w := _breite()
	var ref: Variant = _seen.get("%s@%d" % [url, w])
	var t: Texture2D = (ref as WeakRef).get_ref() as Texture2D if ref is WeakRef else null
	if t == null and url.begins_with("http"):
		t = Media.cached_texture(Media.url_path(url), w)
	return t


static func _remember(url: String, w: int, t: Texture2D) -> void:
	if _seen.size() > 300:
		_seen.clear()
	_seen["%s@%d" % [url, w]] = weakref(t)


func set_dim(v: float) -> void:
	dim = clampf(v, 0.0, 1.0)
	_shade.queue_redraw()


# --- Verläufe --------------------------------------------------------------------------------

func _draw_shade() -> void:
	var bg := _ground
	match layout:
		"full":
			_grad_h(Rect2(0, 0, size.x * 0.78, size.y), bg,
				[[0.0, 1.0], [0.10, 0.95], [0.22, 0.84], [0.36, 0.70], [0.52, 0.52], [0.66, 0.34], [0.78, 0.18], [0.90, 0.07], [1.0, 0.0]])
			var y1 := size.y * 0.38
			_grad_v(Rect2(0, y1, size.x, size.y - y1 + 1), bg,
				[[0.0, 0.0], [0.10, 0.05], [0.22, 0.18], [0.36, 0.38], [0.52, 0.60], [0.66, 0.78], [0.78, 0.91], [0.90, 0.97], [1.0, 1.0]])
			_grad_v(Rect2(0, 0, size.x, 170), bg, [[0.0, 0.5], [1.0, 0.0]])
		"streams":
			_grad_h(Rect2(0, 0, size.x, size.y), bg,
				[[0.0, 1.0], [0.15, 0.85], [0.30, 0.40], [0.50, 0.15], [0.70, 0.40], [0.85, 0.85], [1.0, 1.0]])
			_grad_v(Rect2(0, size.y * 0.6, size.x, size.y * 0.4 + 1), bg, [[0.0, 0.0], [1.0, 0.85]])
	if dim > 0.0:
		_shade.draw_rect(Rect2(Vector2.ZERO, size), Color(bg, dim))


## Maske für das Bild oben rechts: links über 45 % der Breite und unten ab 70 % der Höhe weich
## durchsichtig (wie die Verläufe in Nuvio), oben zurückgenommen für die Leiste.
static var _hmask: ImageTexture


static func hero_mask() -> Texture2D:
	if _hmask:
		return _hmask
	var w := 192
	var h := 108
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var hs := [[0.0, 0.0], [0.099, 0.14], [0.207, 0.44], [0.342, 0.84], [0.45, 1.0], [1.0, 1.0]]
	var vs := [[0.0, 1.0], [0.52, 1.0], [0.7, 0.66], [0.87, 0.24], [1.0, 0.0]]
	for y in h:
		var v := float(y) / float(h - 1)
		var top := 0.4 + 0.6 * smoothstep(0.0, 0.34, v)
		var av := _ramp(vs, v) * top
		for x in w:
			var u := float(x) / float(w - 1)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(_ramp(hs, u) * av * 0.95, 0.0, 1.0)))
	_hmask = ImageTexture.create_from_image(img)
	return _hmask


static func _ramp(stops: Array, t: float) -> float:
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if t <= float(b[0]):
			var k := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			k = k * k * (3.0 - 2.0 * k)
			return lerpf(float(a[1]), float(b[1]), clampf(k, 0.0, 1.0))
	return float(stops[stops.size() - 1][1])


func _grad_h(rect: Rect2, c: Color, stops: Array) -> void:
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		var x0 := rect.position.x + rect.size.x * float(a[0])
		var x1 := rect.position.x + rect.size.x * float(b[0])
		var ca := Color(c, float(a[1]))
		var cb := Color(c, float(b[1]))
		_shade.draw_polygon(PackedVector2Array([Vector2(x0, rect.position.y), Vector2(x1, rect.position.y), Vector2(x1, rect.end.y), Vector2(x0, rect.end.y)]),
			PackedColorArray([ca, cb, cb, ca]))


func _grad_v(rect: Rect2, c: Color, stops: Array) -> void:
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		var y0 := rect.position.y + rect.size.y * float(a[0])
		var y1 := rect.position.y + rect.size.y * float(b[0])
		var ca := Color(c, float(a[1]))
		var cb := Color(c, float(b[1]))
		_shade.draw_polygon(PackedVector2Array([Vector2(rect.position.x, y0), Vector2(rect.end.x, y0), Vector2(rect.end.x, y1), Vector2(rect.position.x, y1)]),
			PackedColorArray([ca, ca, cb, cb]))
