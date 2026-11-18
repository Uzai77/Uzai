extends Control
## Boot animation, the brand's start signature (docs/DESIGN.md): calm, precise, only the mark.
## On a dark background the U band of the mark (uzai_logo.gd) assembles large and free-standing in the
## center in a clear choreography, without a tile behind it (it reads cleaner without one). At the end
## the wordmark appears small and flat below it, then the mark glides to its place in the header.
## No sparks, no particles, no fog: only timing, curves and sharpness (all vector, in real pixels).
## Timed to the start sound (assets/sounds/start.wav, tools/synth_start.py: one clear chord):
##   0.00  Dark and silent (RUHE_VOR).
##   0.35  The light line draws through the arc in one stroke, from top left to top right.
##   0.75  The two bands settle softly around the line (outer from outside, inner from inside).
##   1.00  The whole mark settles from 106 % to its size (depth).
##   1.10  The line stands: the chord. A single, quiet light sweep passes over the U.
##   1.55  The wordmark UZAI appears small below it: flat, widely tracked, only fades in (no light, no
##         motion). Then rest (the time in which main builds in the background).
##   End   The mark glides to its place at the top left (main.brand_mark) and takes on the colors of
##         the header. Everything else fades out over the home page that is already built.
## Any button (A, B …) ends it immediately, but only after SPERRE from the start (the button that
## launched Uzai, such as the Guide button held for the watcher, does not end it right away).
## „Animationen reduzieren“ and light mode: the mark only fades in (1.9 s, sound „boot“).
## "roehre": a CRT TV switches on, with the mark inside.
##
## Smoothness: the clock follows real time and starts after three calm frames (at the latest after
## WARTE_MAX); sound and picture start together. If a frame stalls (shader compilation, the window
## opening late on the Windows PC), at most SCHRITT_MAX of it counts. Previously the clock kept running
## through such a stall, and on the PC the animation was over before a frame was visible. Every
## moment is computed from time (phasen, seek). calm() tells main when heavy work goes unnoticed: in
## the dark at the start and once the name stands. The frame times are logged at the end
## (Bildzeiten).
## With preview = true it runs silently in a loop (preview in the settings).

signal finished

const Logo := preload("res://src/ui/components/uzai_logo.gd")
const Form := preload("res://src/ui/marke_form.gd")
const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Bildzeiten := preload("res://src/ui/components/bildzeiten.gd")
## Der Raum blendet in einem Raumwechsel aus (U.T_RAUM, Kurve „Gehen“).
const FADE := U.T_RAUM
## Das Zeichen folgt seinem Ziel als kritisch gedämpfte Feder (das Ziel kann sich noch setzen);
## spätestens nach GLIDE_MAX s steht es.
const GLIDE_MAX := 1.2
## Ablauf (s), im Takt des Startklangs (tools/synth_start.py hat dieselben Zeiten).
const RUHE_VOR := 0.25           ## dunkel und still: schwere Arbeit fällt nicht auf
const LINIE_AB := 0.35           ## die Lichtlinie zieht sich …
const LINIE_S := 0.75            ## … in einem Zug (bis 1,10: der Akkord)
const AKKORD := LINIE_AB + LINIE_S
const BAND_AB := 0.75            ## die Bänder setzen sich
const BAND_S := 0.55
const MASS_S := 1.3              ## so lange setzt sich das Ganze von MASS_VON auf 100 %
const MASS_VON := 1.06
const GLANZ_AT := 1.35           ## der Lichtverlauf über das U
const GLANZ_S := 0.9
const NAME_AT := 1.55            ## die Wortmarke (klein, flach)
const NAME_S := 0.6
const LAENGE := 3.4              ## volle Fassung
const LAENGE_KURZ := 2.7         ## „kurz“: bis der Name steht
## Ruhige Fassung (Animationen reduzieren, leichter Modus): ohne Weg.
const RUHIG_LAENGE := 1.9
const R_ZEICHEN_AT := 0.3
const R_NAME_AT := 0.75
const R_IN := 0.4
## Lage: Das Feld des Zeichens ist am Ende KACHEL_ANTEIL der Bildhöhe groß (das U darin KACHEL_U
## davon, also gut ein Viertel der Bildhöhe), mittig bei MITTE_Y.
const KACHEL_ANTEIL := 0.42
const MITTE_Y := 0.5
## Wortmarke: Versalhöhe WORT_ANTEIL der Bildhöhe, WORT_ABSTAND unter dem U, Laufweite WORT_SPUR.
const WORT_ANTEIL := 0.022
const WORT_ABSTAND := 0.065
const WORT_SPUR := 0.45
## Der Grund ist immer fast schwarz (RAUM): die Wortmarke darum fest in hellem, kühlem Grau.
const WORT_FARBE := Color(0.88, 0.87, 0.93)
## Raum: fast schwarz mit einem Hauch Violett.
const RAUM := Color(0.016, 0.015, 0.022)
## Anlauf: so viele Bilder unter RUHIG_MS am Stück, dann beginnt die Uhr (spätestens nach WARTE_MAX s).
const RUHIG_BILDER := 3
const RUHIG_MS := 50.0
const WARTE_MAX := 2.5
## Höchstens so viel zählt ein einzelnes Bild auf der Uhr (s).
const SCHRITT_MAX := 0.25
## Tasten beenden erst so lange nach dem Anlaufen (s).
const SPERRE := 0.45

var style := "konsole"
var preview := false
var _t := 0.0
var _length := LAENGE
var _full := true
var _done := false
var _calm := false               ## ruhige Fassung (Animationen reduzieren, leichter Modus)
var _glow_tex: GradientTexture2D
var _licht: Control              ## Raum und Lichtverlauf, entstuft (sonst Stufen im dunklen Violett)
var _c: Control                  ## Zeichen, Name; die Röhre ganz
var _flug: Control               ## das Zeichen auf dem Weg zu main.brand_mark
var _glide := false
var _glide_t := 0.0
var _g_pos := Vector2.ZERO        ## Mitte des U und seine Höhe (Feder)
var _g_h := 0.0
var _g_vel := Vector3.ZERO
var _g_von_h := 0.0               ## Höhe des U beim Abflug (für den Übergang der Farben)
var _g_mark: Control              ## Ziel: main.brand_mark (bis zur Ankunft unsichtbar)
var _deck := 1.0                  ## Deckkraft beim Ausblenden
var _zeichen_weg := false         ## das Zeichen fliegt (im Bild nicht mehr zeichnen)
var _vor := 0
var _t0_us := -1
var _letzt_us := -1               ## Zeit des letzten Bilds (µs)
var _warte_s := 0.0               ## so lange läuft der Anlauf schon
var _frozen := false
var _mess := Bildzeiten.new()


func setup(mode: String) -> Control:
	match mode:
		"roehre":
			style = "roehre"
			_length = 2.3
		"kurz":
			style = "konsole"
			_length = LAENGE_KURZ
			_full = false
		_:
			style = "konsole"
			_length = LAENGE
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if preview else Control.MOUSE_FILTER_STOP
	U.full_rect(self)
	_calm = U.reduziert() or Leicht.active
	if _calm and style == "konsole":
		_length = RUHIG_LAENGE
		_full = false
	_glow_tex = _make_glow()
	_licht = Control.new()
	_licht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_licht.material = U.entstuft()
	_licht.draw.connect(_paint_licht)
	U.full_rect(_licht)
	add_child(_licht)
	_c = Control.new()
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_paint)
	U.full_rect(_c)
	add_child(_c)
	_flug = Control.new()
	_flug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flug.draw.connect(_paint_flug)
	U.full_rect(_flug)
	_flug.visible = false
	add_child(_flug)
	_apply()


## Für main (Dienste starten, Bereiche vorbauen): Ist gerade ein Moment, in dem ein langes Bild
## nicht auffällt? Im Dunkeln am Anfang und sobald der Name steht. Röhre: sobald das Bild steht.
## Nicht im Anlauf: der soll nach wenigen ruhigen Bildern vorbei sein (sonst stünde der Schirm lange
## schwarz, während main baut).
func calm() -> bool:
	if _done or preview:
		return false
	if _t0_us < 0 and not _frozen:
		return false
	if _t < RUHE_VOR:
		return true
	var from := 1.2
	if style == "konsole":
		from = R_NAME_AT + R_IN + 0.1 if _calm else NAME_AT + NAME_S + 0.1
	return _t >= from


func _process(dt: float) -> void:
	if preview:
		_t += dt
		if _t > _length + 1.1:
			_t = 0.0
		_apply()
		return
	if _frozen:
		return
	var jetzt := Time.get_ticks_usec()
	var bild_s := (jetzt - _letzt_us) / 1000000.0 if _letzt_us >= 0 else 0.0
	_letzt_us = jetzt
	if _t0_us < 0:
		# Aufwärmen: Die ersten Bilder zeigen den dunklen Raum (darin wird die Schrift vorbereitet).
		# Erst wenn einige Bilder ruhig kommen, laufen Uhr und Klang los – gemeinsam.
		_warte_s += bild_s
		_vor = _vor + 1 if bild_s * 1000.0 < RUHIG_MS else 0
		if anlaufen(_vor, _warte_s):
			_t0_us = jetzt
			if style == "konsole" and not _calm:
				Sfx.play_start()
			else:
				Sfx.play("boot")
	else:
		_t += uhr_schritt(bild_s)
		_mess.bild(_t)
	if _glide:
		_glide_step(dt)
	_apply()
	if _t >= _length and not _done:
		finish()


func _gui_input(e: InputEvent) -> void:
	if not preview and e is InputEventMouseButton and e.pressed:
		taste()


func _unhandled_input(e: InputEvent) -> void:
	if not preview and (e is InputEventKey or e is InputEventJoypadButton) and e.is_pressed() and not e.is_echo():
		taste()


## Eine Taste (auch über main: Befehle, Guide-Taste): beendet die Animation, aber erst ab SPERRE
## nach dem Anlaufen – vorher war es die Taste, mit der Uzai gestartet wurde.
func taste() -> void:
	if darf_beenden(_t0_us >= 0, _t, _frozen):
		finish()


## Anlauf vorbei? Genug ruhige Bilder am Stück oder lange genug gewartet.
static func anlaufen(ruhige: int, gewartet_s: float) -> bool:
	return ruhige >= RUHIG_BILDER or gewartet_s >= WARTE_MAX


## So viel rückt die Uhr in einem Bild vor: die echte Zeit, ein Hänger höchstens SCHRITT_MAX.
static func uhr_schritt(bild_s: float) -> float:
	return clampf(bild_s, 0.0, SCHRITT_MAX)


## Darf eine Taste die Animation beenden? Erst, wenn sie läuft und SPERRE vorbei ist.
static func darf_beenden(laeuft: bool, t: float, fest := false) -> bool:
	return fest or (laeuft and t >= SPERRE)


func finish() -> void:
	if _done or preview:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Steht das Zeichen schon, gleitet es an seinen Platz oben links (nicht bei „Animationen
	# reduzieren“: dann blendet alles mit aus).
	_g_mark = _brand_mark()
	var steht := _zeichen_steht()
	if not U.reduziert() and _g_mark != null and steht:
		var s := _view_size()
		var zr := zeichen_rect(s)
		_g_pos = zr.get_center()
		_g_h = zr.size.y * Logo.KACHEL_U * _mass(_t)
		_g_von_h = _g_h
		_glide = true
		_zeichen_weg = true
		_g_mark.modulate.a = 0.0
		_flug.visible = true
		_flug.queue_redraw()
	finished.emit()
	var tw := U.weg(self, "uz_boot_aus")
	tw.tween_method(_set_deck, 1.0, 0.0, FADE)
	await tw.finished
	while _glide and is_inside_tree():
		await get_tree().process_frame
	set_process(false)
	queue_free()


func _set_deck(v: float) -> void:
	_deck = v
	_c.modulate.a = v
	_licht.modulate.a = v


func _exit_tree() -> void:
	# Wie auch immer die Animation endet: das Zeichen der Kopfzeile ist danach zu sehen.
	if is_instance_valid(_g_mark):
		_g_mark.modulate.a = 1.0
	if not preview and not _frozen and _t0_us >= 0:
		_mess.melden("Startanimation")


## Für Proben: einen festen Zeitpunkt zeigen (läuft dann nicht mehr von selbst weiter).
func seek(t: float) -> void:
	_frozen = true
	_t = t
	if is_node_ready():
		_apply()


func _view_size() -> Vector2:
	return size if size.x > 10 else get_viewport_rect().size


## Das Zeichen der Kopfzeile (Ziel des Flugs), sofern main es schon hat.
func _brand_mark() -> Control:
	var m: Variant = get_parent().get("brand_mark") if get_parent() else null
	return m as Control if m is Control and is_instance_valid(m) else null


## Steht das Zeichen schon ganz (Bänder gesetzt)?
func _zeichen_steht() -> bool:
	if style == "roehre":
		return _t / _length > 0.6
	if _calm:
		return float(phasen_ruhig(_t)[0]) > 0.5
	return float(phasen(_t).baender) > 0.9


## Ziel des Flugs: Mitte und Höhe des U im Zeichen der Kopfzeile, auf dem Schirm.
func _target() -> Array:
	if not is_instance_valid(_g_mark) or not _g_mark.is_inside_tree() or _g_mark.size.y < 4.0:
		return []
	var xf := _g_mark.get_global_transform()
	var mitte: Vector2 = get_global_transform().affine_inverse() * (xf * (_g_mark.size * 0.5))
	return [mitte, float(_g_mark.call("_u_hoehe")) * xf.get_scale().y]


## Ein Bild des Flugs: Lage und Größe folgen dem Ziel als Feder; angekommen übernimmt das Zeichen
## der Kopfzeile im selben Bild.
func _glide_step(dt: float) -> void:
	_glide_t += dt
	var tg := _target()
	if tg.is_empty():
		if _glide_t > GLIDE_MAX:
			_end_glide()
		return
	var to: Vector2 = tg[0]
	var th: float = tg[1]
	var sx := U.spring_step(_g_pos.x, _g_vel.x, to.x, dt)
	var sy := U.spring_step(_g_pos.y, _g_vel.y, to.y, dt)
	var sh := U.spring_step(_g_h, _g_vel.z, th, dt)
	_g_pos = Vector2(sx.x, sy.x)
	_g_h = sh.x
	_g_vel = Vector3(sx.y, sy.y, sh.y)
	_flug.queue_redraw()
	var near := _g_pos.distance_to(to) < 0.5 and absf(_g_h - th) < 0.05 and _g_vel.length() < 4.0
	if near or _glide_t > GLIDE_MAX:
		_end_glide()


func _end_glide() -> void:
	_glide = false
	_flug.visible = false
	if is_instance_valid(_g_mark):
		_g_mark.modulate.a = 1.0


## Das Zeichen auf dem Weg: legt die Kachel ab und geht in die Farben der Kopfzeile über, je näher
## es seiner Größe dort kommt.
func _paint_flug() -> void:
	if not _glide:
		return
	var ziel := _target()
	var zh: float = ziel[1] if not ziel.is_empty() else _g_h
	var p := clampf((_g_von_h - _g_h) / maxf(_g_von_h - zh, 0.001), 0.0, 1.0)
	var akzent := UzTheme.col("accent")
	var a := Logo.farben("marke", akzent)
	var b := Logo.farben(Logo.KOPF_STIL, akzent)
	var f := {}
	for k in ["aussen", "innen"]:
		f[k] = [(a[k][0] as Color).lerp(b[k][0], p), (a[k][1] as Color).lerp(b[k][1], p)]
	f.linie = (a.linie as Color).lerp(b.linie, p)
	f.kachel = a.kachel
	f.kante = a.kante
	var kachel_bleibt := 1.0 if Logo.KOPF_STIL == "kachel" else 0.0
	Logo.zeichne(_flug, _g_pos, _g_h, f, { "kachel": lerpf(0.0, kachel_bleibt, minf(p * 1.6, 1.0)) })


# --- Ablauf (reine Rechnung, tests/logic_einschalten.gd) -----------------------------------------

## Wo das Zeichen (die Kachel) am Ende auf einer Fläche s steht.
static func zeichen_rect(s: Vector2) -> Rect2:
	var seite := s.y * KACHEL_ANTEIL
	return Rect2(Vector2(s.x * 0.5 - seite * 0.5, s.y * MITTE_Y - seite * 0.5), Vector2(seite, seite))


## Wo die Wortmarke am Ende sichtbar steht (Versalhöhe = Höhe des Rechtecks), mittig unter dem U.
static func wort_rect(s: Vector2) -> Rect2:
	var zr := zeichen_rect(s)
	var h := s.y * WORT_ANTEIL
	var rand := _wort_rand()
	var w := (float(rand[1]) - float(rand[0])) * h
	var oben := zr.get_center().y + zr.size.y * Logo.KACHEL_U * 0.5 + s.y * WORT_ABSTAND
	return Rect2(Vector2(s.x * 0.5 - w * 0.5, oben), Vector2(w, h))


## Linker und rechter Rand der gesperrten Wortmarke in Versalhöhen, vom Ursprung aus, den
## Logo.zeichne_wort nimmt (es spreizt die Buchstaben um die Mitte − 0,4).
static func _wort_rand() -> Array:
	var xs: Array = Form.wort_x()
	var p := float(xs[4]) * 0.5 - 0.4
	return [-p * WORT_SPUR, float(xs[4]) + (float(xs[3]) - p) * WORT_SPUR]


## Wie groß das Zeichen zur Zeit t ist (setzt sich von MASS_VON auf 1).
static func _mass(t: float) -> float:
	return lerpf(MASS_VON, 1.0, _ease_out((t - LINIE_AB) / MASS_S))


## Der Zustand zum Zeitpunkt t (Werte 0 … 1; glanz −1 … 1, außerhalb: aus).
static func phasen(t: float) -> Dictionary:
	var g := _ease_io((t - GLANZ_AT) / GLANZ_S)
	return {
		"linie": _sine((t - LINIE_AB) / LINIE_S),
		"baender": _ease_out((t - BAND_AB) / BAND_S),
		"mass": (_mass(t) - 1.0) / (MASS_VON - 1.0),
		"glanz": lerpf(-1.3, 1.3, g) if g > 0.0 and g < 1.0 else -9.0,
		"schein": 0.6 * _ease_out((t - LINIE_AB) / 1.2),
		"name": _ease_out((t - NAME_AT) / NAME_S),
	}


## Ruhige Fassung: [Zeichen, Name] blenden ohne Weg ein.
static func phasen_ruhig(t: float) -> Array:
	return [_sine((t - R_ZEICHEN_AT) / R_IN), _sine((t - R_NAME_AT) / R_IN)]


# --- Zeichnen ----------------------------------------------------------------------------------

func _apply() -> void:
	_licht.queue_redraw()
	_c.queue_redraw()


## queue_redraw() von außen (Proben setzen _t und zeichnen neu) erreicht so auch die Lagen.
func _draw() -> void:
	if _c:
		_apply()


func _paint() -> void:
	var s := _view_size()
	if style == "roehre":
		_draw_crt(s)
	else:
		if _t0_us < 0 and not preview and not _frozen:
			return
		if _calm:
			var r := phasen_ruhig(_t)
			_draw_marke(s, { "linie": 1.0, "baender": 1.0, "mass": 0.0, "glanz": -9.0, "schein": 0.4, "name": float(r[1]) }, float(r[0]))
		else:
			_draw_marke(s, phasen(_t), 1.0)


## Das Zeichen in der Lage am Ende (ohne Kachel); ph wie phasen(), a: Deckkraft des Zeichens.
func _draw_marke(s: Vector2, ph: Dictionary, a: float) -> void:
	var zr := zeichen_rect(s)
	var akzent := UzTheme.boot_color("accent")
	var mass := lerpf(1.0, MASS_VON, float(ph.mass))
	if not _zeichen_weg:
		zeichen(_c, zr.get_center(), zr.size.y * Logo.KACHEL_U * mass, ph, a, akzent)
	wort_unter(_c, zr.get_center(), zr.size.y * Logo.KACHEL_U, clampf(float(ph.get("name", 0.0)), 0.0, 1.0) * a)


## Das U-Band frei (ohne Kachel) in den Markenfarben um mitte, u_h hoch, im Stand ph (phasen()) –
## auch für alle, die das Zeichen wie hier zeigen (Willkommen der Einrichtung).
static func zeichen(ci: CanvasItem, mitte: Vector2, u_h: float, ph: Dictionary, a: float, akzent: Color) -> void:
	Logo.zeichne(ci, mitte, u_h, Logo.farben("marke", akzent), {
		"alpha": a, "kachel": 0.0,
		"baender": float(ph.baender), "weg": float(ph.linie), "glanz": float(ph.glanz) })


## Die Wortmarke unter einem U (Mitte u_mitte, Höhe u_h ohne das Setzen) wie am Ende der
## Startanimation: klein, flach, weit gesperrt, im hellen Grau (farbe), ohne Licht; Größe und Abstand
## im Verhältnis zum U wie hier (WORT_ANTEIL, WORT_ABSTAND). n: Deckkraft, hebt sich beim Einblenden
## eine Spur.
static func wort_unter(ci: CanvasItem, u_mitte: Vector2, u_h: float, n: float, farbe := WORT_FARBE) -> void:
	if n <= 0.003:
		return
	var bild_h := u_h / (KACHEL_ANTEIL * Logo.KACHEL_U)
	var h := bild_h * WORT_ANTEIL
	var rand := _wort_rand()
	var w := (float(rand[1]) - float(rand[0])) * h
	var oben := u_mitte.y + u_h * 0.5 + bild_h * WORT_ABSTAND
	var grund := Vector2(u_mitte.x - w * 0.5 - float(rand[0]) * h, oben + h + (1.0 - n) * h * 0.4)
	Logo.zeichne_wort(ci, grund, h, { "farbe": Color(farbe, 0.86 * n), "licht": Color(0, 0, 0, 0), "weg": 0.0, "spur": WORT_SPUR })


## Platz, den Zeichen und Wortmarke zusammen brauchen (U u_h hoch): [Breite, Höhe ab Oberkante des U].
static func marke_mass(u_h: float) -> Vector2:
	var bild_h := u_h / (KACHEL_ANTEIL * Logo.KACHEL_U)
	var rand := _wort_rand()
	var w := (float(rand[1]) - float(rand[0])) * bild_h * WORT_ANTEIL
	return Vector2(maxf(Logo.zeichen_breite(u_h, false), w), u_h + bild_h * (WORT_ABSTAND + WORT_ANTEIL))


# --- Hilfen ------------------------------------------------------------------------------------

static func _ease_io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 4.0)


static func _sine(x: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(x, 0.0, 1.0))


## n Lichtpunkte, fest gesät: [x, y, z, Phase, Größe]. Nicht zu dicht an die Mitte. (Die Bühne der
## Einrichtung nutzt sie.)
static func motes(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7707
	var out: Array = []
	var guard := 0
	while out.size() < n and guard < n * 8:
		guard += 1
		var x := rng.randf()
		var y := rng.randf_range(0.04, 1.0)
		if absf(x - 0.5) < 0.12 and absf(y - 0.47) < 0.18:
			continue
		out.append([x, y, rng.randf_range(0.35, 1.0), rng.randf() * TAU, rng.randf_range(0.6, 1.0)])
	return out


## Der Raum der ruhigen Fassung und der Röhre: bei dunklen Schemata tiefer als sonst, bei hellen hell.
static func _room() -> Color:
	return UzTheme.col("bg") if UzTheme.light else UzTheme.col("bg").darkened(0.6)


func _make_glow() -> GradientTexture2D:
	# Weicher Lichtabfall (glockenförmig, viele Stufen): keine sichtbaren Ringe im Dunkeln.
	var gr := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in 17:
		var r := i / 16.0
		offs.append(r)
		cols.append(Color(1, 1, 1, (exp(-5.0 * r * r) - exp(-5.0)) / (1.0 - exp(-5.0))))
	gr.offsets = offs
	gr.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = gr
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


## Raum und der eine, leise Lichtverlauf hinter dem Zeichen – auf einer eigenen, entstuften Lage
## (U.entstuft: feines Rauschen unter einer Stufe), damit das dunkle Violett weich statt in Ringen
## abfällt. Die Röhre zeichnet ihr eigenes Licht.
func _paint_licht() -> void:
	if style == "roehre":
		return
	var s := _view_size()
	_licht.draw_rect(Rect2(Vector2.ZERO, s), RAUM if not _calm else _room())
	if _t0_us < 0 and not preview and not _frozen:
		return
	var schein := 0.4 * float(phasen_ruhig(_t)[0]) if _calm else float(phasen(_t).schein)
	if schein > 0.0:
		var zr := zeichen_rect(s)
		var c := Color(Logo.licht_von(UzTheme.boot_color("accent")), 0.07 * schein)
		_glow(_licht, zr.get_center(), zr.size.y * 1.6, c)


func _glow(ci: CanvasItem, center: Vector2, radius: float, c: Color) -> void:
	if c.a <= 0.003 or radius <= 1.0 or _glow_tex == null:
		return
	ci.draw_texture_rect(_glow_tex, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, c)


# --- Röhre -------------------------------------------------------------------------------------

## Erst ein heller Strich, dann klappt das Bild auf; darin erscheint das Zeichen.
func _draw_crt(s: Vector2) -> void:
	var k := _t / _length
	var u := s.y / 1080.0
	_c.draw_rect(Rect2(Vector2.ZERO, s), Color.BLACK)
	var c := s * 0.5
	var p1 := clampf(k / 0.2, 0.0, 1.0)
	var line_w := s.x * ease(p1, 0.4)
	var p2 := clampf((k - 0.2) / 0.18, 0.0, 1.0)
	var h := lerpf(2.0, s.y, ease(p2, 3.2))
	var glow := Color(1, 1, 1, (1.0 - p2) * 0.95)
	if p2 < 1.0:
		_c.draw_rect(Rect2(c.x - line_w * 0.5, c.y - h * 0.5, line_w, h), Color(UzTheme.col("bg"), p2).lerp(glow, 1.0 - p2))
		_c.draw_rect(Rect2(c.x - line_w * 0.5, c.y - 1, line_w, 2), Color(1, 1, 1, (1.0 - p2)))
		_glow(_c, c, 260.0 * u * (1.0 - p2 * 0.5), Color(1, 1, 1, 0.25 * (1.0 - p2)))
	else:
		_c.draw_rect(Rect2(Vector2.ZERO, s), _room())
	var p3 := _ease_out((k - 0.36) / 0.3)
	if p3 > 0.0:
		_draw_marke(s, { "linie": 1.0, "baender": 1.0, "mass": 0.0, "glanz": -9.0, "schein": 0.5, "name": p3 }, p3)
	# Zeilen der Röhre, die langsam verschwinden.
	var a := 0.06 * (1.0 - clampf((k - 0.7) / 0.3, 0.0, 1.0))
	if a > 0.0:
		var yy := 0.0
		while yy < s.y:
			_c.draw_line(Vector2(0, yy), Vector2(s.x, yy), Color(0, 0, 0, a * 3.0), 1.0)
			yy += 4.0 * maxf(u, 0.5)
