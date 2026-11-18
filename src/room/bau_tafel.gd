extends Control
## Grundlage der Tafeln im Zimmer – Bau-Menü (katalog_ui.gd) und Regal einrichten (regal_tafel.gd):
## unten eine Leiste mit den Bereichen als Zeichen (die gehobene Fläche mit dem Strich im Akzent
## gleitet zum gewählten, LB/RB an den Enden), darüber eine matte Tafel in der warmen Optik des
## Zimmers (zimmer_stil.gd) mit großen Kacheln im Raster – ein neuer Abschnitt beginnt eine neue
## Reihe –, oben Name und leise Angaben, rechts der Bereich. Derselbe Kachel-Cursor wie überall
## (UzTheme.draw_tile_focus), er gleitet; Kacheln kommen nacheinander, ein neuer Bereich gleitet aus
## seiner Richtung herein. Was in den Bereichen steht und wie eine Kachel aussieht, sagt die
## Unterklasse (_gruppen, _kacheln_fuer, _kachel_zeichnen, _texte, _aktiv).

signal gewechselt(id: String)     ## anderer Bereich oder andere Kachel gewählt (für die Probe im Zimmer)

const U := preload("res://src/ui/u.gd")
const Glyph := preload("res://src/ui/components/glyph.gd")
const Stil := preload("res://src/room/zimmer_stil.gd")

const RAND_UNTEN := 28.0          ## Leiste über dem unteren Rand
const LEISTE_H := 60.0
const ZELLE := 52.0               ## ein Bereich in der Leiste
const ZELLE_LUECKE := 4.0
const GRUPPEN_LUECKE := 28.0      ## Haarlinie zwischen zwei Gruppen von Bereichen
const KACHEL := 148.0
const LUECKE := 12.0
const SPALTEN := 6
const REIHEN := 2
const PAD := 22.0
const KOPF_H := 72.0              ## Name und Angaben oben in der Tafel

static var _glanz: GradientTexture2D        ## weicher runder Schein (Licht, Schatten, Lampen)

## Offen getypt (Control statt Zimmer): logic_baumenue betreibt Katalog und Tafeln mit einem nachgestellten Zimmer.
var zimmer: Control
var _kat := 0                     ## Index in _gruppen()
var _sel := 0
var _merk := {}                   ## Bereich → zuletzt gewählte Kachel
var _kacheln: Array = []
var _pos: Array = []              ## Stelle je Kachel im Raster (Spalte, Reihe)
var _reihen := 1
var _offen := false
var _dock := false
var _an := 0.0                    ## Tafel 0 … 1 eingeblendet
var _dock_a := 0.0                ## Leiste 0 … 1
var _sel_f := Vector2.ZERO        ## gleitende Auswahl im Raster (Spalte, Reihe)
var _kat_f := -1.0                ## gleitende Lage der Fläche unter dem gewählten Bereich
var _kat_rects: Array = []        ## Fläche je Bereich (Maus)
var _kachel_rects: Array = []     ## [Rect2, Index] (Maus)
var _hover_kat := -1
var _wechsel := 0.0               ## Bereich gewechselt: Raster kommt aus der Richtung (−1 … 1 → 0)
var _seit := 0.0                  ## Zeit seit dem Öffnen bzw. Wechsel (Kacheln nacheinander)
var _scroll := 0.0                ## erste sichtbare Reihe (gleitend)
var _scroll_ziel := 0
var _angefasst := false           ## im Bereich bewegt: erst dann zeigt das Zimmer eine Probe
var _sb := {}                     ## StyleBoxFlat je Rolle (einmal gebaut, Deckkraft je Bild)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	U.full_rect(self)
	visible = false
	set_process(false)
	Nav.device_changed.connect(func(_k: String) -> void: queue_redraw())


# --- Für die Unterklasse ------------------------------------------------------------------------------

## Bereiche: [Kennung, Name, Zeichen (icons.gd)].
func _gruppen() -> Array:
	return []


## Vor diesem Bereich steht in der Leiste eine Haarlinie (-1: keine).
func _trenner() -> int:
	return -1


func _kacheln_fuer(_id: String) -> Array:
	return []


## Name und leise Angaben zu einer Kachel.
func _texte(_k: Dictionary) -> Array:
	return ["", ""]


## Steht das schon so (Häkchen auf der Kachel, erste Wahl im Bereich)?
func _aktiv(_k: Dictionary) -> bool:
	return false


func _kachel_zeichnen(_k: Dictionary, _i: int, _r: Rect2, _ia: float, _gew: bool, _rc: int) -> void:
	pass


## Was die Tafel unter dem Kopf zeigt (das Raster; das Bau-Menü blendet dort auch die Farbleiste ein).
func _inhalt_zeichnen(t: Rect2, a: float) -> void:
	_raster(t, a)


## Vor einem Wechsel des Bereichs und vor dem Schließen (eine Probe zurücknehmen …).
func _verlassen() -> void:
	pass


## Weitere Bewegung je Bild; true, solange sie noch läuft.
func _jede_runde(_dt: float) -> bool:
	return false


## Neue Kacheln geladen (Bilder bestellen …).
func _geladen() -> void:
	pass


## Maus vor allem anderen (Tupfer, Farbleiste …); true: erledigt.
func _maus(_e: InputEvent, _p: Vector2) -> bool:
	return false


## Klick auf einen Bereich in der Leiste.
func _gruppe_klick(k: int) -> void:
	if k != _kat:
		kategorie_setzen(k, signi(k - _kat))


# --- Öffnen, Bereiche, Wahl -----------------------------------------------------------------------

## Leiste als Dock (Tafel zu): nur die Bereiche, ruhig.
func dock(an: bool) -> void:
	_dock = an
	if an:
		visible = true
		if _kacheln.is_empty():
			_laden(0)
	_blenden()


## Gleitet von unten herein; die Kacheln erscheinen nacheinander (behalten: für die Unterklasse).
func oeffnen(_behalten := false) -> void:
	_offen = true
	visible = true
	_angefasst = false
	_laden(0)
	_sel_f = _zelle(_sel)
	_scroll = _ziel_scroll()
	_blenden()
	gewechselt.emit(gewaehlt())


func schliessen() -> void:
	_verlassen()
	_offen = false
	_blenden()


func _blenden() -> void:
	var tw := U.tw(self, "uz_katalog", Tween.TRANS_QUART).set_parallel(true)
	tw.tween_method(func(v: float) -> void:
		_an = v
		queue_redraw(), _an, 1.0 if _offen else 0.0, U.T_MOVE if _offen else U.T_FAST)
	tw.tween_method(func(v: float) -> void:
		_dock_a = v
		queue_redraw(), _dock_a, 1.0 if (_offen or _dock) else 0.0, U.T_MOVE)
	tw.chain().tween_callback(func() -> void:
		if not _offen and not _dock:
			visible = false
			set_process(false))
	set_process(true)


func ist_offen() -> bool:
	return _offen


func kategorie(d: int) -> void:
	kategorie_setzen(posmod(_kat + d, _gruppen().size()), signi(d))


func kategorie_setzen(k: int, richtung := 0) -> void:
	_verlassen()
	_merk[_kat] = _sel
	_kat = clampi(k, 0, _gruppen().size() - 1)
	_sel = int(_merk.get(_kat, -1))
	_angefasst = false
	Sfx.play("tab")
	_laden(richtung if richtung != 0 else 1)
	_sel_f = _zelle(_sel)
	_scroll = _ziel_scroll()
	gewechselt.emit(gewaehlt())


func kategorie_id() -> String:
	var g := _gruppen()
	return str(g[_kat][0]) if _kat >= 0 and _kat < g.size() else ""


func schritt(cmd: String) -> void:
	if _kacheln.is_empty():
		Sfx.play("bump")
		return
	var c: Vector2i = _pos[_sel]
	var n := -1
	match cmd:
		"left":
			if _sel > 0 and (_pos[_sel - 1] as Vector2i).y == c.y:
				n = _sel - 1
		"right":
			if _sel + 1 < _kacheln.size() and (_pos[_sel + 1] as Vector2i).y == c.y:
				n = _sel + 1
		"up", "down":
			# In der Reihe darüber bzw. darunter die nächste Spalte (kürzere Reihen: die letzte).
			var reihe := c.y + (-1 if cmd == "up" else 1)
			var best := -1
			for i in _pos.size():
				var p: Vector2i = _pos[i]
				if p.y == reihe and (best < 0 or absi(p.x - c.x) < absi((_pos[best] as Vector2i).x - c.x)):
					best = i
			n = best
	_waehlen(n)


func _waehlen(n: int) -> void:
	if n < 0 or n >= _kacheln.size():
		Sfx.play("bump")
		return
	if n == _sel:
		return
	_sel = n
	_angefasst = true
	Sfx.play("move")
	set_process(true)
	_geladen()
	gewechselt.emit(gewaehlt())


func gewaehlt() -> String:
	return str(kachel().get("id", ""))


func kachel() -> Dictionary:
	return _kacheln[_sel] if _sel >= 0 and _sel < _kacheln.size() else {}


## Im Bereich bewegt (vorher zeigt das Zimmer keine Probe: es bleibt, wie es ist).
func angefasst() -> bool:
	return _angefasst


## Nach Rückgängig oder einer Änderung von außen: Kacheln neu lesen, die Wahl bleibt.
func auffrischen() -> void:
	_verlassen()
	_angefasst = false
	var id := gewaehlt()
	_laden(0)
	for i in _kacheln.size():
		if str(_kacheln[i].id) == id:
			_sel = i
	_sel_f = _zelle(_sel)
	queue_redraw()


func _zelle(i: int) -> Vector2:
	return Vector2(_pos[i]) if i >= 0 and i < _pos.size() else Vector2.ZERO


## Erste sichtbare Reihe, damit die gewählte Kachel im Bild ist (die Tafel zeigt REIHEN Reihen).
func _ziel_scroll() -> float:
	var reihe := int(_zelle(_sel).y)
	if reihe < _scroll_ziel:
		_scroll_ziel = reihe
	elif reihe > _scroll_ziel + REIHEN - 1:
		_scroll_ziel = reihe - REIHEN + 1
	_scroll_ziel = clampi(_scroll_ziel, 0, maxi(0, _reihen - REIHEN))
	return float(_scroll_ziel)


func _laden(richtung: int) -> void:
	_kacheln = _kacheln_fuer(kategorie_id())
	# Stellen im Raster: ein neuer Abschnitt (reihe) beginnt eine neue Reihe.
	_pos.clear()
	var c := 0
	var r := 0
	for i in _kacheln.size():
		if i > 0 and (bool(_kacheln[i].get("reihe", false)) or c >= SPALTEN):
			r += 1
			c = 0
		_pos.append(Vector2i(c, r))
		c += 1
	_reihen = r + 1
	# Ohne gemerkte Wahl: was schon so ist, sonst die erste Kachel.
	if _sel < 0 or _sel >= _kacheln.size():
		_sel = 0
		for i in _kacheln.size():
			if _aktiv(_kacheln[i]):
				_sel = i
				break
	_seit = 0.0
	_wechsel = float(richtung)
	if richtung != 0:
		U.tw(self, "uz_katalog_wechsel", Tween.TRANS_QUART).tween_property(self, "_wechsel", 0.0, U.T_MOVE)
	_geladen()
	set_process(true)
	queue_redraw()


func _process(dt: float) -> void:
	_seit += dt
	_sel_f = _sel_f.lerp(_zelle(_sel), 1.0 - exp(-dt * 16.0))
	_scroll = lerpf(_scroll, _ziel_scroll(), 1.0 - exp(-dt * 12.0))
	_kat_f = float(_kat) if _kat_f < 0.0 else lerpf(_kat_f, float(_kat), 1.0 - exp(-dt * 16.0))
	var weiter := _jede_runde(dt)
	queue_redraw()
	var ruhig := _sel_f.distance_to(_zelle(_sel)) < 0.002 and absf(_scroll - _ziel_scroll()) < 0.002 and _seit > 1.0 and absf(_wechsel) < 0.001 \
		and absf(_kat_f - _kat) < 0.002 and not weiter
	if ruhig and (_an >= 1.0 or _an <= 0.0) and (_dock_a >= 1.0 or _dock_a <= 0.0):
		set_process(false)


# --- Zeichnen -----------------------------------------------------------------------------------

func _tafel() -> Rect2:
	var w := PAD * 2.0 + SPALTEN * KACHEL + (SPALTEN - 1) * LUECKE
	var h := KOPF_H + REIHEN * KACHEL + (REIHEN - 1) * LUECKE + PAD
	var unten := size.y - RAND_UNTEN - LEISTE_H - 14.0
	return Rect2(UzTheme.GUTTER, unten - h, w, h)


func _leiste_rect() -> Rect2:
	var t := _tafel()
	return Rect2(t.position.x, size.y - RAND_UNTEN - LEISTE_H, t.size.x, LEISTE_H)


## Matte Fläche (Rolle: Aussehen einmal gebaut, Deckkraft je Bild), Lichtkante oben, Schatten.
func _flaeche(rolle: String, r: Rect2, farbe: Color, a: float, radius: int, stufe := 0) -> void:
	if a <= 0.01:
		return
	var sb: StyleBoxFlat = _sb.get(rolle)
	if sb == null:
		sb = UzTheme.flaeche(farbe, radius, stufe)
		sb.anti_aliasing = true
		_sb[rolle] = sb
		sb.set_meta("schatten", sb.shadow_color)
		sb.set_meta("kante", sb.border_color)
	sb.bg_color = Color(farbe, farbe.a * a)
	var sc: Color = sb.get_meta("schatten")
	sb.shadow_color = Color(sc, sc.a * a)
	var kc: Color = sb.get_meta("kante")
	sb.border_color = Color(kc, kc.a * a)
	draw_style_box(sb, r)


func _draw() -> void:
	_kat_rects.clear()
	_kachel_rects.clear()
	if _dock_a > 0.01:
		_leiste(_dock_a)
	if _an > 0.01:
		var a := clampf(_an, 0.0, 1.0)
		var t := _tafel()
		t.position.y += (1.0 - a) * 24.0
		_flaeche("tafel", t, Color(Stil.FLAECHE, 1.0), a, UzTheme.r_panel(), 3)
		var tn := _kopf_texte()
		_kopf(t, a, str(tn[0]), str(tn[1]))
		_inhalt_zeichnen(t, a)


## Titel und Angaben im Kopf (Unterklasse: z. B. die Farbe statt der Kachel).
func _kopf_texte() -> Array:
	return _texte(kachel())


func _leiste(a: float) -> void:
	var r := _leiste_rect()
	_flaeche("leiste", r, Color(Stil.FLAECHE, 1.0), a, UzTheme.r_panel(), 2)
	var gset := Nav.glyph_set()
	var gs := Glyph.size_for("lb", 24, gset)
	var leise := 0.75 if _offen else 0.45
	Glyph.paint(self, "lb", 24, Rect2(Vector2(r.position.x + 16.0, r.get_center().y - gs.y * 0.5), gs), gset, leise, a)
	Glyph.paint(self, "rb", 24, Rect2(Vector2(r.end.x - 16.0 - gs.x, r.get_center().y - gs.y * 0.5), gs), gset, leise, a)
	var gruppen := _gruppen()
	if gruppen.is_empty():
		return
	var trenner := _trenner()
	var breite := gruppen.size() * ZELLE + (gruppen.size() - 1) * ZELLE_LUECKE + (GRUPPEN_LUECKE - ZELLE_LUECKE if trenner > 0 else 0.0)
	var x := r.get_center().x - breite * 0.5
	var y := r.position.y + (LEISTE_H - 48.0) * 0.5
	for i in gruppen.size():
		if i == trenner:
			# Haarlinie zwischen den Gruppen (Raum | Möbel).
			draw_rect(Rect2(x + (GRUPPEN_LUECKE - ZELLE_LUECKE) * 0.5 - ZELLE_LUECKE * 0.5 - 0.5, y + 10.0, 1.0, 28.0), Color(Stil.LINIE, Stil.LINIE.a * a * 1.6))
			x += GRUPPEN_LUECKE - ZELLE_LUECKE
		_kat_rects.append(Rect2(x, y, ZELLE, 48.0))
		x += ZELLE + ZELLE_LUECKE
	# Gehobene Fläche und Strich gleiten zum gewählten Bereich.
	var f := clampf(_kat_f if _kat_f >= 0.0 else float(_kat), 0.0, gruppen.size() - 1.0)
	var i0 := int(floorf(f))
	var i1 := mini(i0 + 1, gruppen.size() - 1)
	var ra: Rect2 = _kat_rects[i0]
	var rb: Rect2 = _kat_rects[i1]
	var pl := Rect2(ra.position.lerp(rb.position, f - i0), ra.size)
	_flaeche("zelle", pl, Stil.FLAECHE_HOCH.lightened(0.05), a, UzTheme.r_panel() - 4)
	draw_rect(Rect2(pl.position.x + 14.0, pl.end.y - 5.0, pl.size.x - 28.0, 3.0), Color(UzTheme.col("accent"), a))
	for k in gruppen.size():
		var kr: Rect2 = _kat_rects[k]
		var nah := clampf(1.0 - absf(f - k), 0.0, 1.0)
		var c := Stil.LEISE.lerp(Stil.TINTE, nah)
		draw_texture_rect(Icons.tex(str(gruppen[k][2]), 28), Rect2(kr.get_center() - Vector2(14, 16), Vector2(28, 28)), false,
			Color(c, a * lerpf(0.8, 1.0, nah)))
	# Maus: Name des Bereichs über dem Zeichen.
	if _hover_kat >= 0 and _hover_kat < _kat_rects.size():
		var hr: Rect2 = _kat_rects[_hover_kat]
		var fs := UzTheme.size("xs")
		var fo := UzTheme.font("medium")
		var name_ := tr(str(gruppen[_hover_kat][1]))
		var tw := fo.get_string_size(name_, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var schild := Rect2(hr.get_center().x - tw * 0.5 - 12.0, (r.position.y if _offen else hr.position.y) - 44.0, tw + 24.0, 32.0)
		_flaeche("schild", schild, Color(Stil.FLAECHE_HOCH, 1.0), a, UzTheme.r_panel() - 4, 1)
		draw_string(fo, Vector2(schild.position.x + 12.0, schild.get_center().y + fs * 0.36), name_, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Stil.TINTE, a))


## Kopf: links Titel (groß) und Angaben (leise), rechts leise der Bereich mit seinem Zeichen.
func _kopf(t: Rect2, a: float, titel: String, info: String) -> void:
	var gruppen := _gruppen()
	var fb := UzTheme.display("bold")
	var fl := UzTheme.size("l")
	var fs := UzTheme.size("s")
	var fr := UzTheme.font("regular")
	var x := t.position.x + PAD
	var y := t.position.y + 46.0
	var gx := t.end.x - PAD
	if _kat >= 0 and _kat < gruppen.size():
		var gname := tr(str(gruppen[_kat][1]))
		gx -= fr.get_string_size(gname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(fr, Vector2(gx, y), gname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Stil.LEISE, a))
		draw_texture_rect(Icons.tex(str(gruppen[_kat][2]), 22), Rect2(gx - 32.0, y - fs * 0.36 - 12.0, 22, 22), false, Color(Stil.LEISE, a))
	var max_w := gx - 48.0 - x
	draw_string(fb, Vector2(x, y), titel, HORIZONTAL_ALIGNMENT_LEFT, max_w * 0.62, fl, Color(Stil.TINTE, a))
	var tw := minf(fb.get_string_size(titel, HORIZONTAL_ALIGNMENT_LEFT, -1, fl).x, max_w * 0.62)
	draw_string(fr, Vector2(x + tw + 18.0, y), info, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, max_w - tw - 18.0), fs, Color(Stil.LEISE, a))


func _kachel_rect(t: Rect2, c: Vector2) -> Rect2:
	return Rect2(t.position.x + PAD + c.x * (KACHEL + LUECKE), t.position.y + KOPF_H + (c.y - _scroll) * (KACHEL + LUECKE), KACHEL, KACHEL)


func _raster(t: Rect2, a: float) -> void:
	var wa := a * (1.0 - absf(_wechsel))
	var dx := _wechsel * 40.0
	var oben := t.position.y + KOPF_H - 4.0
	var unten := t.position.y + KOPF_H + REIHEN * KACHEL + (REIHEN - 1) * LUECKE + 4.0
	var rc := UzTheme.r_panel() - 2
	for i in _kacheln.size():
		var k: Dictionary = _kacheln[i]
		var r := _kachel_rect(t, _zelle(i))
		r.position.x += dx
		if r.end.y < oben or r.position.y > unten:
			continue
		# Am Rand der Tafel weich aus (Reihen, die hinein- oder hinausgleiten).
		var rand := clampf(minf(r.end.y - oben, unten - r.position.y) / (KACHEL * 0.5), 0.0, 1.0)
		var auf := clampf((_seit - i * 0.025) / U.T_ENTER, 0.0, 1.0)
		var ia := wa * auf * rand
		if ia <= 0.01:
			continue
		_kachel_rects.append([r, i])
		_kachel_zeichnen(k, i, r, ia, i == _sel, rc)
		if _aktiv(k):
			_haekchen(r, ia)
	# Derselbe Cursor wie überall, er gleitet über das Raster.
	if not _kacheln.is_empty():
		var cr := _kachel_rect(t, _sel_f)
		cr.position.x += dx
		UzTheme.draw_tile_focus(self, cr, rc, wa)
	# Mehr Reihen, als hineinpassen: leiser Hinweis rechts (wie weit es geht).
	if _reihen > REIHEN:
		var h := REIHEN * KACHEL + (REIHEN - 1) * LUECKE
		var bx := t.end.x - 9.0
		var by := t.position.y + KOPF_H
		draw_rect(Rect2(bx, by, 2.0, h), Color(Stil.LINIE, a))
		draw_rect(Rect2(bx, by + h * (_scroll / _reihen), 2.0, h * (float(REIHEN) / _reihen)), Color(Stil.TINTE, 0.6 * a))


## Kleines Häkchen im Akzent: so steht es schon im Zimmer.
func _haekchen(r: Rect2, a: float) -> void:
	var m := Vector2(r.end.x - 18.0, r.position.y + 18.0)
	draw_circle(m, 12.0, Color(Stil.FLAECHE, 0.92 * a), true, -1.0, true)
	draw_texture_rect(Icons.tex("check", 16), Rect2(m - Vector2(8, 8), Vector2(16, 16)), false, Color(UzTheme.col("accent"), a))


## Grund einer Kachel (gewählt eine Spur heller).
func _grund(r: Rect2, a: float, gew: bool, rc: int) -> void:
	_flaeche("kachel_g" if gew else "kachel", r, Stil.KACHEL.lightened(0.06) if gew else Stil.KACHEL, a, rc)


## Zeichen mit kurzem Wort darunter (Neu, Mehr, Aktionen).
func _zeichen_kachel(r: Rect2, a: float, gew: bool, rc: int, zeichen: String, wort: String, farbe := Stil.TINTE) -> void:
	_grund(r, a, gew, rc)
	var m := r.get_center() - Vector2(0, 12)
	draw_texture_rect(Icons.tex(zeichen, 40), Rect2(m - Vector2(20, 20), Vector2(40, 40)), false, Color(farbe, a * (1.0 if gew else 0.8)))
	_wort_unten(r, a, wort)


## Kurzes Wort unten in der Kachel (roh: Name vom Nutzer bzw. der Bibliothek, nie übersetzt).
func _wort_unten(r: Rect2, a: float, wort: String, abstand := 26.0, roh := false) -> void:
	var fs := UzTheme.size("xs")
	var fo := UzTheme.font("medium")
	var t := _passend(wort if roh else tr(wort), fo, fs, r.size.x - 16.0)
	var ww := fo.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(fo, Vector2(r.get_center().x - ww * 0.5, r.end.y - abstand), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Stil.LEISE, a))


## Name auf einem Bild (Oberfläche, Fenster, Stimmung): unten ein weicher dunkler Verlauf, darauf hell.
func _name_auf_bild(r: Rect2, a: float, rc: int, wort: String, roh := false) -> void:
	var h := 40.0
	var y0 := r.end.y - h
	var p := PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0)])
	var rr := float(maxi(rc, 0))
	for s in 6:
		var w := PI * 0.5 * s / 5.0
		p.append(Vector2(r.end.x - rr, r.end.y - rr) + Vector2(cos(w), sin(w)) * rr)
	for s in 6:
		var w := PI * 0.5 + PI * 0.5 * s / 5.0
		p.append(Vector2(r.position.x + rr, r.end.y - rr) + Vector2(cos(w), sin(w)) * rr)
	var cs := PackedColorArray()
	for q in p:
		cs.append(Color(0.05, 0.04, 0.03, 0.62 * a * clampf((q.y - y0) / h, 0.0, 1.0)))
	draw_polygon(p, cs)
	var fs := UzTheme.size("xs")
	var fo := UzTheme.font("medium")
	var t := _passend(wort if roh else tr(wort), fo, fs, r.size.x - 20.0)
	Stil.text(self, fo, Vector2(r.position.x + 10.0, r.end.y - 11.0), t, fs, Color(Stil.TINTE, a))


## Text, der in breite passt (sonst gekürzt mit „…“).
static func _passend(t: String, f: Font, fs: int, breite: float) -> String:
	if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= breite:
		return t
	var n := t.length()
	while n > 1 and f.get_string_size(t.substr(0, n) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > breite:
		n -= 1
	return t.substr(0, n).strip_edges() + "…"


static func _schein() -> GradientTexture2D:
	if _glanz == null:
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
		_glanz = GradientTexture2D.new()
		_glanz.gradient = gr
		_glanz.fill = GradientTexture2D.FILL_RADIAL
		_glanz.fill_from = Vector2(0.5, 0.5)
		_glanz.fill_to = Vector2(1.0, 0.5)
		_glanz.width = 128
		_glanz.height = 128
	return _glanz


## Umriss einer gerundeten Fläche (für Bilder und Verläufe in Kachelform).
static func _rund_punkte(r: Rect2, rc: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var rr := clampf(rc, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var ecken := [[r.position + Vector2(rr, rr), PI], [Vector2(r.end.x - rr, r.position.y + rr), PI * 1.5],
		[r.end - Vector2(rr, rr), 0.0], [Vector2(r.position.x + rr, r.end.y - rr), PI * 0.5]]
	for e in ecken:
		for s in 6:
			var w: float = float(e[1]) + PI * 0.5 * s / 5.0
			p.append((e[0] as Vector2) + Vector2(cos(w), sin(w)) * rr)
	return p


func _bild_rund(tex: Texture2D, r: Rect2, rc: int, mod: Color) -> void:
	var p := _rund_punkte(r, rc)
	var uv := PackedVector2Array()
	for q in p:
		uv.append((q - r.position) / r.size)
	draw_colored_polygon(p, mod, uv, tex)


## Senkrechter Verlauf in Kachelform (oben → unten).
func _verlauf(r: Rect2, rc: int, oben: Color, unten: Color) -> void:
	var p := _rund_punkte(r, rc)
	var cs := PackedColorArray()
	for q in p:
		cs.append(oben.lerp(unten, clampf((q.y - r.position.y) / r.size.y, 0.0, 1.0)))
	draw_polygon(p, cs)


# --- Maus und Finger ----------------------------------------------------------------------------

func _has_point(p: Vector2) -> bool:
	if not (_offen or _dock):
		return false
	if _leiste_rect().has_point(p):
		return true
	return _offen and _tafel().has_point(p)


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouse):
		return
	var p := (e as InputEventMouse).position
	var hover := -1
	for k in _kat_rects.size():
		if (_kat_rects[k] as Rect2).has_point(p):
			hover = k
	if hover != _hover_kat:
		_hover_kat = hover
		queue_redraw()
	if _maus(e, p):
		return
	var treffer := -1
	for kr in _kachel_rects:
		if (kr[0] as Rect2).has_point(p):
			treffer = int(kr[1])
	if e is InputEventMouseMotion:
		if _offen and treffer >= 0 and treffer != _sel:
			_waehlen(treffer)
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if hover >= 0:
		_gruppe_klick(hover)
		return
	if _offen and treffer >= 0:
		_waehlen(treffer)
		Nav._fire("a")
