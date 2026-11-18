extends Control
## Eine kleine Pille der Spielseite unter den Knöpfen: vorn ein Zeichen (Ring der Erfolge, die Woche
## als sieben Mini-Säulen, Gesichter der Freunde, Symbol der Spielstände), dahinter Wert und Wort
## („29 / 42 Erfolge“, „3 Std. diese Woche“, „Mira spielt gerade“, „2 Spielstände“). Leicht wie
## eine Zeile: in Ruhe ohne Fläche und Schatten (nur Zeichen und Text, klein), gewählt kommt die
## Fläche (sel) mit weichem Schein im Akzent – kein Rahmen, kein Wachsen. A (chosen) tut, was früher die große Karte der Bühne tat.
## Ring und Säulen füllen sich beim Erscheinen einmal (T_RAUM); „Animationen reduzieren“: sofort.

signal chosen

const U := preload("res://src/ui/u.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Leicht := preload("res://src/core/leicht.gd")

const H := 42.0             ## Höhe der Pille
const PAD_L := 14.0
const PAD_R := 18.0
const GAP := 10.0           ## zwischen Zeichen und Text
const ZEICHEN := 22.0       ## Breite des Zeichens (Ring, Symbol)
const WOCHE_W := 30.0       ## Breite der sieben Mini-Säulen
const SCHRIFT := "s"        ## Schriftgröße von Wert und Wort
const GESICHT := 26         ## Gesicht eines Freundes
const GESICHT_STEP := 18.0

var art := "zeit"           ## zeit | erfolge | freunde | stand | klang
var wert := ""              ## kräftig vorn („29 / 42“), "" ohne
var wort := ""              ## leise dahinter („Erfolge“)
var wert_roh := false       ## der Wert ist ein Name (Freund): nie übersetzen
var frac := 0.0             ## Anteil des Rings (erfolge)
var voll := false           ## alles geschafft: Ring in Gold
var week: Array = []        ## Sekunden je Tag, älteste zuerst (zeit)
var faces: Array = []       ## [{ name, avatar }] (freunde)
var delay_i := 0            ## Platz in der Reihe (Staffel)
var _t := 0.0               ## Füllen von Ring und Säulen 0…1
## klang: Der Klang läuft – die vier Säulen bewegen sich (ruhig: stehen sie in mittlerer Höhe).
var lebt := false:
	set(neu):
		lebt = neu
		set_process(art == "klang" and lebt and not U.reduziert())
		queue_redraw()
var _phase := 0.0


func setup_chip(a: String, w: String, wo: String) -> Control:
	art = a
	wert = w
	wort = wo
	return self


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	_messen()
	if art == "freunde":
		var n := mini(faces.size(), 3)
		for i in n:
			var f: Dictionary = faces[i]
			var av := Avatar.new()
			av.setup(str(f.get("name", "")), str(f.get("avatar", "")), "", GESICHT)
			av.mouse_filter = Control.MOUSE_FILTER_IGNORE
			av.position = Vector2(PAD_L - 4.0 + GESICHT_STEP * i, (H - GESICHT) * 0.5)
			add_child(av)
	focus_entered.connect(func() -> void: U.focus_anim(self, true))
	focus_exited.connect(func() -> void: U.focus_anim(self, false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)
	set_process(art == "klang" and lebt and not U.reduziert())
	_fuellen()


func activate() -> void:
	chosen.emit()


func _process(dt: float) -> void:
	_phase += dt
	queue_redraw()


## Wert und Wort nachträglich setzen (Erfolge, sobald die Liste da ist): Breite neu, das Neue kreuzt
## im Cursor-Takt.
func set_values(w: String, wo: String, f := -1.0, v := false) -> void:
	var neu := w != wert or wo != wort
	wert = w
	wort = wo
	if f >= 0.0:
		frac = f
		voll = v
	_messen()
	queue_redraw()
	if neu and is_inside_tree() and not U.reduziert():
		modulate.a = 0.4
		U.ankommen(self, U.T_ANTWORT, "uz_tausch").tween_property(self, "modulate:a", 1.0, U.T_ANTWORT)


func _wert() -> String:
	return wert if wert_roh else tr(wert)


func _zeichen_w() -> float:
	if art == "freunde":
		var n := clampi(faces.size(), 1, 3)
		return GESICHT + GESICHT_STEP * (n - 1) - 4.0
	if art == "zeit" and not week.is_empty():
		return WOCHE_W
	return ZEICHEN


func _messen() -> void:
	var w := PAD_L + _zeichen_w() + GAP + _text_w() + PAD_R
	custom_minimum_size = Vector2(ceilf(w), H)


func _text_w() -> float:
	var fs := UzTheme.size(SCHRIFT)
	var w := 0.0
	if wert != "":
		w += UzTheme.ui("ui_bold").get_string_size(_wert(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if wort != "":
		if wert != "":
			w += _space()
		w += UzTheme.font("medium").get_string_size(tr(wort), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return w


func _space() -> float:
	return UzTheme.font("medium").get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size(SCHRIFT)).x


## Ring und Säulen füllen sich einmal – gestaffelt in der Reihe, im ruhigen Modus sofort.
func _fuellen() -> void:
	if U.reduziert() or not (art in ["zeit", "erfolge"]):
		_t = 1.0
		queue_redraw()
		return
	var wr: WeakRef = weakref(self)
	U.ankommen(self, U.T_RAUM, "uz_fill").tween_method(func(v: float) -> void:
		var me: Control = wr.get_ref()
		if me:
			me.set("_t", v)
			me.queue_redraw()
	, 0.0, 1.0, U.T_RAUM).set_delay(U.T_ANTWORT + U.staffel(delay_i))


func _draw() -> void:
	var f: float = clampf(float(get_meta("uz_f", 0.0)), 0.0, 1.0) if has_meta("uz_f") else 0.0
	var r := Rect2(Vector2.ZERO, size)
	var rad := mini(UzTheme.r_pill(), int(H * 0.5) - 1)
	# In Ruhe nichts als Zeichen und Text; gewählt die Fläche mit Schatten und leisem Schein im Akzent.
	if f > 0.01:
		var sh := StyleBoxFlat.new()
		sh.draw_center = false
		sh.set_corner_radius_all(rad)
		sh.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(0.38 * f))
		sh.shadow_size = int(round(14.0 * f))
		sh.shadow_offset = Vector2(0, 5.0 * f)
		draw_style_box(sh, r)
	if f > 0.01 and not Leicht.active:
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.set_corner_radius_all(rad)
		glow.shadow_color = Color(UzTheme.col("accent"), UzTheme.TILE_GLOW_A * f)
		glow.shadow_size = int(round(UzTheme.TILE_GLOW_S * 0.8))
		draw_style_box(glow, r)
	if f > 0.01:
		draw_style_box(UzTheme.flaeche(Color(UzTheme.col("sel"), f), rad), r)
	var cy := H * 0.5
	var zx := PAD_L
	match art:
		"erfolge":
			_draw_ring(Vector2(zx + ZEICHEN * 0.5, cy))
		"zeit":
			_draw_week(Rect2(zx, cy - 9.0, _zeichen_w(), 18.0))
		"stand":
			draw_texture_rect(Icons.tex("save", 20), Rect2(zx + 1.0, cy - 10.0, 20, 20), false, UzTheme.col("accent"))
		"klang":
			_draw_klang(Rect2(zx + 1.0, cy - 8.0, ZEICHEN - 2.0, 16.0))
	# Wert kräftig, Wort leise – beide in einer Grundlinie.
	var fs := UzTheme.size(SCHRIFT)
	var x := PAD_L + _zeichen_w() + GAP
	var fb := UzTheme.ui("ui_bold")
	var fm := UzTheme.font("medium")
	var base := cy + (fb.get_ascent(fs) - fb.get_descent(fs)) * 0.5
	if wert != "":
		var ink: Color = UzTheme.col("faint") if wert == "…" else UzTheme.col("text").lerp(UzTheme.col("on_focus"), f)
		draw_string(fb, Vector2(x, base), _wert(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		x += fb.get_string_size(_wert(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + _space()
	if wort != "":
		draw_string(fm, Vector2(x, base), tr(wort), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			(UzTheme.col("muted") if wert != "" else UzTheme.col("text")).lerp(UzTheme.col("on_focus"), f))


## Kleiner Ring: Spur leise, der Anteil im Akzent (alles geschafft: Gold), füllt sich mit _t.
func _draw_ring(c: Vector2) -> void:
	var rad := ZEICHEN * 0.5 - 2.0
	draw_arc(c, rad, 0.0, TAU, 40, UzTheme.col("text", 0.14), 3.0, true)
	var a := clampf(frac, 0.0, 1.0) * _t
	if a > 0.005:
		draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * a, maxi(8, int(40 * a)), UzTheme.col("gold" if voll else "accent"), 3.0, true)


## Sieben Mini-Säulen, heute im Akzent; Tage ohne Spiel als Punkt.
## Vier Säulen wie eine kleine Pegelanzeige: bewegt, solange der Klang läuft, sonst niedrig und leise.
func _draw_klang(area: Rect2) -> void:
	var n := 4
	var schritt := area.size.x / n
	var bw := maxf(2.0, schritt - 2.0)
	for i in n:
		var h := 3.0
		if lebt:
			# Jede Säule in eigenem Takt; ruhig („Animationen reduzieren“) steht sie auf fester Höhe.
			var welle := 0.5 + 0.5 * sin(_phase * (4.2 + 1.3 * i) + 1.7 * i)
			h = area.size.y * (0.3 + 0.7 * (welle if is_processing() else [0.6, 1.0, 0.45, 0.8][i]))
		var c := UzTheme.col("accent") if lebt else UzTheme.col("faint", 0.9)
		draw_rect(Rect2(area.position.x + schritt * i, area.end.y - h, bw, h), c)


func _draw_week(area: Rect2) -> void:
	var n := week.size()
	if n == 0:
		draw_texture_rect(Icons.tex("clock", 20), Rect2(area.position.x + 1.0, area.get_center().y - 10.0, 20, 20), false, UzTheme.col("accent"))
		return
	var mx := 1
	for v in week:
		mx = maxi(mx, int(v))
	var col_w := area.size.x / n
	var bw := maxf(2.0, col_w - 1.5)
	for i in n:
		var v := int(week[i])
		var x := area.position.x + col_w * i
		var c := UzTheme.col("accent") if i == n - 1 else UzTheme.col("text", 0.34)
		if v > 0:
			var h := maxf(3.0, area.size.y * float(v) / float(mx)) * _t
			draw_rect(Rect2(x, area.end.y - h, bw, h), c)
		else:
			draw_circle(Vector2(x + bw * 0.5, area.end.y - 1.5), 1.5, UzTheme.col("faint", 0.8))
