extends Container
## Leerer Zustand eines Bereichs, der noch nicht eingerichtet ist (Spiele ohne Spiele, Freunde ohne
## Konto, Wunschliste ohne Steam, Musik aus …): statt eines Textblocks eine ruhige Bühne. Dahinter
## die Form dessen, was gleich hier steht – Cover, Plakate, Videos, Personen, Alben oder Medaillen
## als matte Silhouetten, die sanft atmen –, davor das Zeichen des Dienstes, ein kurzer Titel und
## ein Knopf, der mit einem Druck auf A gleich einrichtet (Anmeldung, Spielesuche …). Die Wege
## dahin sind dieselben wie in der Einrichtung und unter Einstellungen › Konten (weg()).
##
## Ist der Bereich danach eingerichtet (fertig), baut er sich neu, und der Inhalt kommt im Takt
## herein: die Bühne kreuzt aus, das Neue blendet ein, seine Reihen gestaffelt (U.ankunft,
## U.cascade). Baut der Bereich selbst neu (eigene Signale), gilt dasselbe – die Bühne merkt beim
## Gehen, dass eingerichtet ist. Hinter einer Ebene (Anmeldung) wartet sie, bis die zu ist.
## Der Fokus liegt sofort auf dem Hauptknopf und danach auf dem neuen Inhalt.
##
## Zwei Formen: breit (ganzer Bereich, Text links mittig, Vorschau rechts daneben bis über den
## Rand) und schmal (Seitenleiste, Guide: Vorschau als Band oben, darunter Zeichen, Titel, Knöpfe).
## Animationen reduzieren (U.reduziert) und leichter Modus: die Silhouetten stehen still.

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")

const ARTEN := ["cover", "poster", "video", "personen", "musik", "erfolge"]
const ATEM_S := 5.6         ## Sekunden je Atemzug der Silhouetten
const ATEM_A := 0.3         ## so weit schwankt ihre Deckkraft (Anteil)
const GRUND_A := 0.075      ## Deckkraft der Silhouetten
const AKZENT_A := 0.16      ## die erste Silhouette trägt den Akzent (wie gleich der Cursor)
const BAND_H := 150.0       ## Höhe der Vorschau in der schmalen Form
const TEXT_W := 700.0       ## Breite der Textspalte (breit)
const RAND := 96            ## Seitenrand (breit), wie Section.GUTTER
const LUFT := 88.0          ## zwischen Textspalte und Vorschau
const PRUEF_S := 0.5        ## so oft fragt die Bühne, ob inzwischen eingerichtet ist
const WARTE_MS := 600       ## dem Bereich erst so lange Zeit geben, selbst neu zu bauen

## Der Bereich hat neu gebaut, weil jetzt eingerichtet ist.
signal eingerichtet

var art := "cover"
var symbol := ""
var titel := ""
var zeile := ""
var schmal := false
var rand := RAND
var host: Control           ## baut neu (Bereich); ohne: nur die Knöpfe
var fertig: Callable        ## true, sobald eingerichtet
var neu: Callable           ## baut neu (Standard: host.build())
var laeuft: Callable        ## true, solange gerade eingerichtet wird (Suche läuft)
var laeuft_titel := ""
var laeuft_knopf := ""

var haupt: Button           ## der Hauptknopf (Fokus beim Betreten)
var _vorschau: Control
var _inhalt: VBoxContainer
var _titel_l: Label
var _knoepfe: Array = []    ## [[Text, Callable], …]
var _gemeldet := false
var _fertig_ms := 0
var _sicht_frame := -100
var _lief := false


## o: { art, symbol, titel, zeile?, knopf, tun, neben?, neben_tun?, schmal?, rand?, host?, fertig?,
## neu?, laeuft?, laeuft_titel?, laeuft_knopf? }
func setup(o: Dictionary) -> Control:
	art = str(o.get("art", "cover")) if str(o.get("art", "cover")) in ARTEN else "cover"
	symbol = str(o.get("symbol", ""))
	titel = str(o.get("titel", ""))
	zeile = str(o.get("zeile", ""))
	schmal = bool(o.get("schmal", false))
	rand = int(o.get("rand", 0 if schmal else RAND))
	host = o.get("host") if o.get("host") is Control else null
	fertig = o.get("fertig") if o.get("fertig") is Callable else Callable()
	neu = o.get("neu") if o.get("neu") is Callable else Callable()
	laeuft = o.get("laeuft") if o.get("laeuft") is Callable else Callable()
	laeuft_titel = str(o.get("laeuft_titel", ""))
	laeuft_knopf = str(o.get("laeuft_knopf", ""))
	_knoepfe = []
	if str(o.get("knopf", "")) != "" and o.get("tun") is Callable:
		_knoepfe.append([str(o.knopf), o.tun])
	if str(o.get("neben", "")) != "" and o.get("neben_tun") is Callable:
		_knoepfe.append([str(o.neben), o.neben_tun])
	if str(o.get("dritte", "")) != "" and o.get("dritte_tun") is Callable:
		_knoepfe.append([str(o.dritte), o.dritte_tun])
	_bauen()
	return self


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	tree_exiting.connect(_on_weg)
	if fertig.is_valid() or laeuft.is_valid():
		var t := Timer.new()
		t.wait_time = PRUEF_S
		t.autostart = true
		t.timeout.connect(_pruefen)
		add_child(t)
	_laeuft_zeigen()


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		_sicht_frame = Engine.get_process_frames()


func _bauen() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_vorschau = _Vorschau.new()
	_vorschau.set("art", art)
	add_child(_vorschau)
	_inhalt = U.vbox(0)
	_inhalt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inhalt)
	if schmal:
		_inhalt.add_child(U.spacer(0, int(BAND_H), false))
		_inhalt.add_child(U.spacer(0, 18, false))
		var kopf := U.hbox(16)
		kopf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if symbol != "":
			var s := _scheibe(52, 24)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			kopf.add_child(s)
		_titel_l = U.label(titel, "l", "text", "bold", true)
		_titel_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_titel_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kopf.add_child(_titel_l)
		_inhalt.add_child(kopf)
		if zeile != "":
			_inhalt.add_child(U.spacer(0, 8, false))
			_inhalt.add_child(U.label(zeile, "s", "muted", "regular", true))
	else:
		if symbol != "":
			var s2 := _scheibe(76, 36)
			s2.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_inhalt.add_child(s2)
			_inhalt.add_child(U.spacer(0, 28, false))
		_titel_l = U.label(titel, "xl", "text", "bold", true)
		_titel_l.set_meta("uz_titel", true)
		_inhalt.add_child(_titel_l)
		if zeile != "":
			_inhalt.add_child(U.spacer(0, 10, false))
			_inhalt.add_child(U.label(zeile, "m", "muted", "regular", true))
	if _knoepfe.is_empty():
		return
	_inhalt.add_child(U.spacer(0, 22 if schmal else 34, false))
	var reihe := U.hbox(14)
	reihe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_inhalt.add_child(reihe)
	for i in _knoepfe.size():
		var k: Array = _knoepfe[i]
		# Knöpfe nur mit Wort: was A tut, steht unten in der Tastenzeile.
		var b := U.button(str(k[0]), "", "primary" if i == 0 else "normal")
		b.set_meta("uz_key", "leer:%d" % i)
		var cb: Callable = k[1]
		if i == 0:
			b.set_meta("uz_default", true)
			haupt = b
			b.pressed.connect(func() -> void:
				if not _laeuft_jetzt():
					cb.call())
		else:
			b.pressed.connect(func() -> void: cb.call())
		reihe.add_child(b)


## Zeichen des Dienstes auf einer runden, matten Fläche (Akzent auf Graphit).
func _scheibe(d: int, px: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UzTheme.flaeche(UzTheme.col("surface_hi"), 999))
	p.custom_minimum_size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(U.icon(symbol, px, "accent"))
	p.add_child(cc)
	return p


func _get_minimum_size() -> Vector2:
	if not is_instance_valid(_inhalt):
		return Vector2.ZERO
	var cm := _inhalt.get_combined_minimum_size()
	return Vector2(cm.x + rand * 2.0, cm.y) if schmal else Vector2.ZERO


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or not is_instance_valid(_inhalt):
		return
	fit_child_in_rect(_vorschau, Rect2(Vector2.ZERO, size))
	if schmal:
		var cm := _inhalt.get_combined_minimum_size()
		fit_child_in_rect(_inhalt, Rect2(rand, 0, maxf(size.x - rand * 2.0, cm.x), cm.y))
		_vorschau.set("feld", Rect2(rand, 0, maxf(size.x - rand * 2.0, 1.0), BAND_H))
		return
	var w := clampf(size.x * 0.38, 420.0, TEXT_W)
	if is_instance_valid(_titel_l):
		_titel_l.custom_minimum_size.x = w
	var ch := _inhalt.get_combined_minimum_size()
	w = maxf(w, ch.x)
	# Etwas über der Mitte: das Auge sucht oben zuerst.
	var y := roundf(maxf(0.0, (size.y - ch.y) * 0.44))
	fit_child_in_rect(_inhalt, Rect2(rand, y, w, ch.y))
	var x0 := rand + w + LUFT
	_vorschau.set("feld", Rect2(x0, 0, maxf(size.x - x0, 1.0), size.y))


# --- Eingerichtet? ---------------------------------------------------------------------------

func _laeuft_jetzt() -> bool:
	return laeuft.is_valid() and bool(laeuft.call())


## Läuft gerade die Einrichtung (Suche), sagt es der Titel, und der Hauptknopf ruht.
func _laeuft_zeigen() -> void:
	var on := _laeuft_jetzt()
	if on == _lief:
		return
	var vorbei := _lief and not on
	_lief = on
	# Die Suche ist durch und fand nichts: der Bereich baut neu (er sagt dann, was jetzt hilft).
	if vorbei and is_instance_valid(host) and not (fertig.is_valid() and bool(fertig.call())):
		var h := host
		var f := _hat_fokus()
		_gemeldet = true
		(func() -> void:
			bau(h)
			if f and is_instance_valid(h) and h.is_inside_tree():
				var d := Nav.default_in(h)
				if d:
					Nav.focus(d, true)).call_deferred()
		return
	if is_instance_valid(_titel_l):
		_titel_l.text = laeuft_titel if on and laeuft_titel != "" else titel
	if is_instance_valid(haupt) and not _knoepfe.is_empty():
		haupt.text = laeuft_knopf if on and laeuft_knopf != "" else str(_knoepfe[0][0])


func _pruefen() -> void:
	if _gemeldet or not is_visible_in_tree():
		return
	_laeuft_zeigen()
	if not fertig.is_valid() or not is_instance_valid(host):
		return
	# Hinter einer Ebene (Anmeldung) nicht umbauen: erst, wenn man wieder hierher sieht.
	var top := Nav.top_layer()
	if (top != null and not top.is_ancestor_of(self)) or not bool(fertig.call()):
		_fertig_ms = 0
		return
	var jetzt := Time.get_ticks_msec()
	if _fertig_ms == 0:
		_fertig_ms = jetzt
	if jetzt - _fertig_ms >= WARTE_MS:
		_neu_bauen()


## Eingerichtet: die Bühne kreuzt aus, der Bereich baut neu, sein Inhalt kommt herein.
func _neu_bauen() -> void:
	_gemeldet = true
	var h := host
	var f := _hat_fokus()
	eingerichtet.emit()
	U.abgang(h, 0)
	if neu.is_valid():
		neu.call()
	else:
		bau(h)
	herein(h, f)


## Baut der Bereich selbst neu (eigene Signale), während die Bühne zu sehen war, und ist jetzt
## eingerichtet: der neue Inhalt kommt ebenso im Takt herein.
func _on_weg() -> void:
	if _gemeldet or not fertig.is_valid() or not is_instance_valid(host):
		return
	if Engine.get_process_frames() - _sicht_frame > 2 or not bool(fertig.call()):
		return
	_gemeldet = true
	var h := host
	var f := _hat_fokus()
	(func() -> void: herein(h, f)).call_deferred()


## Lag die Auswahl auf der Bühne (oder hinter der Ebene, die sie geöffnet hat)?
func _hat_fokus() -> bool:
	if not is_inside_tree():
		return false
	var f := get_viewport().gui_get_focus_owner()
	if f == null or is_ancestor_of(f):
		return true
	var top := Nav.top_layer()
	if top != null and not top.is_ancestor_of(self) and top.has_meta("uz_prev_focus"):
		var p: Variant = top.get_meta("uz_prev_focus")
		return p is Node and is_instance_valid(p) and is_ancestor_of(p)
	return false


## Bereich neu bauen (und seine Unterbereiche oben, falls er vorn ist).
static func bau(h: Control) -> void:
	if not is_instance_valid(h) or not h.has_method("build"):
		return
	h.call("build")
	var m: Variant = h.get("main")
	if m is Node and is_instance_valid(m) and (m as Node).has_method("refresh_chips") and str((m as Node).get("current")) == str(h.get("id")):
		(m as Node).call("refresh_chips")


## Der neue Inhalt von h kommt herein: Kreuzen mit der Bühne (T_ORT), die Reihen gestaffelt.
## fokus: die Auswahl geht auf das Erste des neuen Inhalts (liegt eine Ebene darüber: sobald sie zu ist).
static func herein(h: Control, fokus: bool) -> void:
	if not is_instance_valid(h) or not h.is_inside_tree():
		return
	U.ankunft(h, 0, U.T_ORT)
	U.cascade(h)
	if not fokus:
		return
	h.get_tree().process_frame.connect(func() -> void:
		if not is_instance_valid(h) or not h.is_visible_in_tree():
			return
		var d := Nav.default_in(h)
		if d:
			Nav.focus(d, true)
	, CONNECT_ONE_SHOT)


# --- Wege zum Einrichten -----------------------------------------------------------------------

## Der bestehende Weg, einen Dienst einzurichten (wie in der Einrichtung und unter Einstellungen ›
## Konten): steam, discord, spotify, youtube, twitch, nuvio, retro, spiele. Unbekannt: leer.
static func weg(m: Node, dienst: String) -> Callable:
	match dienst:
		"steam":
			return func() -> void: m.call("open_chat", { "id": "", "name": "Steam" }, true)
		"discord":
			return func() -> void:
				var l: Control = load("res://src/ui/layers/discord_connect.gd").new()
				l.set("autostart", Voice.configured())
				m.call("open_layer", l)
		"spotify":
			return func() -> void: spotify(m)
		"youtube":
			return func() -> void:
				if ResourceLoader.exists("res://src/ui/layers/yt_tv_login.gd") and YouTube.get("tv") != null:
					m.call("open_layer", load("res://src/ui/layers/yt_tv_login.gd").new())
				else:
					m.call("open_yt_login")
		"twitch":
			return func() -> void: m.call("open_twitch_login")
		"nuvio":
			return func() -> void: m.call("open_nuvio_login")
		"retro":
			return func() -> void: m.call("open_ra_login")
		"spiele":
			return func() -> void:
				if not Library.scanning:
					Library.scan(true, true)
	return Callable()


## Spotify: gleich „Mit Spotify anmelden“ (die echte Anmeldeseite im Uzai-Browser, spotify_anmelden.gd) – ohne
## Zwischenfrage. Die eigene Spotify-App steht als zweiter Weg unter Einstellungen › Konten › Spotify.
static func spotify(m: Node) -> void:
	load("res://src/ui/layers/spotify_anmelden.gd").start(m)


# --- Vorschau ----------------------------------------------------------------------------------

## Die Form dessen, was gleich hier steht: matte Silhouetten in der Größe des späteren Inhalts, zum
## Rand hin leiser, die erste im Akzent. Sie atmen langsam, jede ein wenig versetzt – kein Schimmer
## (der heißt „lädt gerade“), kein Pulsieren im Gleichtakt.
class _Vorschau extends Control:
	var art := "cover"
	var feld := Rect2():
		set(v):
			if v != feld:
				feld = v
				_lage()
	var formen: Array = []      ## { r: Rect2, rad, a, phase, kreis, akzent }
	var _t := 0.0
	var _sb: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		clip_contents = true

	func _ready() -> void:
		set_process(atmet())

	static func atmet() -> bool:
		return not (U.reduziert() or Leicht.active)

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		_t += dt
		queue_redraw()

	## Formen für das Feld berechnen (bei jeder Größenänderung, nie je Bild).
	func _lage() -> void:
		formen = formen_fuer(art, feld, feld.size.y <= BAND_H + 0.5)
		queue_redraw()

	func _draw() -> void:
		if _sb == null:
			_sb = StyleBoxFlat.new()
			_sb.anti_aliasing = true
		var welle := _t / ATEM_S
		for f in formen:
			var a := float(f.a) * atem(welle, float(f.phase))
			var col := UzTheme.col("accent", a * AKZENT_A / GRUND_A) if bool(f.get("akzent", false)) \
					else UzTheme.col("text", a)
			var r: Rect2 = f.r
			if bool(f.get("kreis", false)):
				draw_circle(r.get_center(), minf(r.size.x, r.size.y) * 0.5, col, true, -1.0, true)
				continue
			_sb.bg_color = col
			_sb.set_corner_radius_all(int(f.rad))
			draw_style_box(_sb, r)

	## Atem: 1 − ATEM_A … 1, langsam und je Form versetzt; ruhig steht er bei 1 − ATEM_A/2.
	static func atem(welle: float, phase: float) -> float:
		if not atmet():
			return 1.0 - ATEM_A * 0.5
		var s := 0.5 + 0.5 * sin(TAU * welle - phase)
		return 1.0 - ATEM_A + ATEM_A * s

	## Die Silhouetten einer Art im Feld r (schmal: ein Band). Ohne Fenster testbar.
	static func formen_fuer(art_: String, r: Rect2, band: bool) -> Array:
		var out: Array = []
		if r.size.x < 8.0 or r.size.y < 8.0:
			return out
		if art_ == "personen":
			return _personen(r, band)
		var rc := UzTheme.r_cover()
		var ts := Vector2(UzTheme.cover_size())
		var balken := 0
		var gap := 28.0
		var kreis := false
		match art_:
			"poster":
				ts = Vector2(200, 300)
			"video":
				ts = Vector2(400, 225)
				balken = 2
			"musik":
				ts = Vector2(236, 236)
				balken = 2
			"erfolge":
				ts = Vector2(132, 132)
				balken = 1
				gap = 52.0
				kreis = true
		var unter := 0.0 if balken == 0 else 18.0 + 30.0 * balken
		var reihen := 1 if band else (3 if art_ == "erfolge" else 2)
		var hoch := ts.y + unter
		# So groß, dass die Reihen ins Feld passen (Band: eine Reihe in seiner Höhe).
		var k := minf(1.0, (r.size.y * (1.0 if band else 0.8) - gap * (reihen - 1)) / (hoch * reihen))
		ts = (ts * k).round()
		unter = roundf(unter * k)
		gap = roundf(gap * maxf(k, 0.6))
		hoch = ts.y + unter
		var y0 := r.position.y + (0.0 if band else roundf((r.size.y - (hoch * reihen + gap * (reihen - 1))) * 0.5))
		for zr in reihen:
			var x := r.position.x
			var sp := 0
			while x < r.position.x + r.size.x and sp < 12:
				var y := y0 + zr * (hoch + gap)
				var cx := x + ts.x * 0.5
				# Zum Rand hin leiser, die hinteren Reihen eine Spur mehr.
				var leise := 1.0 - 0.72 * smoothstep(r.position.x, r.position.x + r.size.x, cx)
				var a := GRUND_A * leise * (1.0 - 0.18 * zr)
				var ph := sp * 0.55 + zr * 0.9
				out.append({ "r": Rect2(x, y, ts.x, ts.y), "rad": rc, "a": a, "phase": ph, "kreis": kreis,
					"akzent": zr == 0 and sp == 0 })
				for bi in balken:
					var bw := ts.x * (0.72 if bi == 0 else 0.44)
					var bh := roundf((14.0 if bi == 0 else 10.0) * maxf(k, 0.6))
					var by := y + ts.y + roundf(18.0 * k) + bi * roundf(30.0 * k)
					var bx := x + (ts.x - bw) * 0.5 if kreis else x
					out.append({ "r": Rect2(bx, by, bw, bh), "rad": int(bh * 0.5), "a": a * 0.8, "phase": ph + 0.3 })
				x += ts.x + gap
				sp += 1
		return out

	## Personen als Liste: rundes Bild, Name, Zeile – wie gleich die Freunde.
	static func _personen(r: Rect2, band: bool) -> Array:
		var out: Array = []
		var d := 48.0 if band else 60.0
		var zh := 72.0 if band else 92.0
		var n := int(floor((r.size.y + (zh - d)) / zh))
		n = clampi(n, 1, 7)
		var spalten := 1 if band or r.size.x < 900.0 else 2
		var sw := r.size.x / spalten
		for sp in spalten:
			for i in n:
				var x := r.position.x + sp * sw
				var y := r.position.y + i * zh
				# Im Band (Seitenleiste, Guide) leiser: es soll nicht wie eine Liste beim Laden aussehen.
				var leise := (1.0 - 0.12 * i) * (1.0 - 0.45 * sp) * (0.7 if band else 1.0)
				var a := GRUND_A * leise
				var ph := i * 0.7 + sp * 1.1
				out.append({ "r": Rect2(x, y, d, d), "rad": 0, "a": a, "phase": ph, "kreis": true,
					"akzent": i == 0 and sp == 0 })
				var bx := x + d + 20.0
				var bw := minf(300.0, sw - d - 60.0)
				out.append({ "r": Rect2(bx, y + d * 0.5 - 17.0, bw, 15.0), "rad": 7, "a": a, "phase": ph + 0.3 })
				out.append({ "r": Rect2(bx, y + d * 0.5 + 7.0, bw * 0.6, 11.0), "rad": 5, "a": a * 0.75, "phase": ph + 0.5 })
		return out
