extends Control
## Die kleinen Szenen der Einrichtung (setup_wizard_show.gd): ruhige, gezeichnete Animationen, die
## zeigen, was Uzai besonders macht.
## "guide": Ein Spiel läuft, die Guide-Taste wird gedrückt, der Guide gleitet über das Spiel, und
## der Cursor zeigt der Reihe nach, was er kann: Freunde (wer online ist), Musik (läuft oben rechts
## mit), Bildschirmfoto (ein kurzer Blitz, das Bild landet als Mitteilung), Clip speichern (die
## letzten 30 Sekunden) und Ausschalten (Ruhemodus, Energiesparen, Herunterfahren) – dann schließt
## ein zweiter Druck den Guide, das Spiel läuft weiter.
## "freunde": Steam und Discord in einer Liste, einer ist im Sprachkanal, eine Einladung kommt.
## "medien": Apps und Medien als Kacheln mit Bild (echte Inhalte des Nutzers oder eigene Bilder,
##   einrichtung_inhalt.gd), der Cursor wandert, unten läuft Musik.
## "online": erst "freunde", dann "medien" (Szene Freunde & Medien), weich ineinander.
## "vorschau": die Reihe der Stationen im Willkommen, die nacheinander aufleuchten.
## Die Vorstellung (große Szenen über die ganze Breite, je drei Kapitel oben links):
## "emulatoren": Ein Licht tastet die eigene Sammlung ab, ihre Systeme stehen als Karten auf (Logo
##   oder Silhouette, die eigenen Cover, Zahl der Spiele – Erkannt); das Fenster rechts zeigt den
##   echten Stand je System (stand(): Bereit, Kann geladen werden, Von Hand – ein Fortschritt nur,
##   wenn nach Zustimmung wirklich geladen wird); zuletzt Spieler 1–4, die Controller landen, der
##   dritte und vierte über Multitap (Belegt).
## "schauen": links Musik, Videos, Filme, Live (nur Wörter, der Cursor wandert); rechts je eine
##   kleine Bühne mit dem, was es auf diesem PC wirklich gibt (Inhalt.schauen: eigene Alben, zuletzt
##   gesehene Videos, Weiterschauen, gefolgte Streams) – sonst eigene, ruhige Bilder (Landschaften,
##   Inhalt.landschaft) mit eigenen Namen: Lyrics laufen Wort für Wort mit, ein Video öffnet sich,
##   Filme mit „Weiterschauen“, ein Stream mit Chat und Zuschauerzahl.
## Eine Szene läuft in Schleife (PERIOD); bei „Animationen reduzieren“ steht sie still an ihrer
## schönsten Stelle (REST). Nur wenige Flächen, kein eigener Puffer; im leichten Modus höchstens
## 30 Bilder je Sekunde.

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Inhalt := preload("res://src/ui/components/einrichtung_inhalt.gd")
const BadgeLogos := preload("res://src/core/badge_logos.gd")

const PERIOD := { "guide": 9.2, "freunde": 7.2, "medien": 7.2, "online": 14.4, "vorschau": 7.0, "emulatoren": 9.6,
	"schauen": 10.0 }
const REST := { "guide": 3.2, "freunde": 4.0, "medien": 1.0, "online": 4.0, "vorschau": 0.0, "emulatoren": 6.0,
	"schauen": 1.6 }
## Die Stationen der Vorstellung (Willkommen): Zeichen und Name.
const STATIONEN := [["games", "Alle Spiele"], ["grid", "Guide"], ["friends", "Freunde"], ["apps", "Apps & Medien"], ["room", "Dein Zimmer"]]

var kind := "guide"
var t := 0.0
var _total := 0.0
var _calm := false
var _wait := 0.0
static var _glow_tex: GradientTexture2D


func setup(k: String, sz: Vector2) -> Control:
	kind = k
	custom_minimum_size = sz
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_calm = U.reduziert()
	if _calm:
		t = float(REST.get(kind, 0.0))
		_total = 10.0
		set_process(false)
	resized.connect(queue_redraw)
	# Echte Inhalte (Cover, Albumcover, Poster, Bildschirmfoto) und Logos kommen im Hintergrund.
	if kind == "emulatoren":
		_emus = Inhalt.emu_liste()
		Inhalt.anfordern(self, _emus)
		var l := BadgeLogos.loader() if BadgeLogos.enabled() else null
		if l:
			l.logo_ready.connect(func(_k: String) -> void: queue_redraw())
	elif kind in ["medien", "online"]:
		Inhalt.anfordern(self)
	elif kind == "schauen":
		_sch = Inhalt.schauen()
		Inhalt.anfordern_schauen(self, _sch)


func _process(dt: float) -> void:
	_total += dt
	t = fmod(t + dt, float(PERIOD.get(kind, 6.0)))
	if Leicht.active:
		_wait += dt
		if _wait < 1.0 / 30.0:
			return
		_wait = 0.0
	queue_redraw()


## Weicher Lichtfleck (glockenförmig), einmal gebaut.
static func glow_tex() -> GradientTexture2D:
	if _glow_tex:
		return _glow_tex
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	# Viele Stützstellen (die Glocke statt eines Vielecks) und genug Bildpunkte: kein Knick, keine
	# 8-Bit-Stufen schon in der Textur.
	for i in 33:
		var r := i / 32.0
		offs.append(r)
		cols.append(Color(1, 1, 1, (exp(-4.5 * r * r) - exp(-4.5)) / (1.0 - exp(-4.5))))
	g.offsets = offs
	g.colors = cols
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 256
	_glow_tex.height = 256
	return _glow_tex


## 0 … 1 zwischen a und b.
static func win(x: float, a: float, b: float) -> float:
	return clampf((x - a) / maxf(b - a, 0.0001), 0.0, 1.0)


static func eo(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func eio(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _glow(c: Vector2, r: float, col: Color) -> void:
	if col.a > 0.003 and r > 1.0:
		draw_texture_rect(glow_tex(), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


func _box(r: Rect2, col: Color, border := 0, bc := Color.TRANSPARENT, rad := -1) -> void:
	if col.a <= 0.003 and border == 0:
		return
	draw_style_box(UzTheme.box(col, UzTheme.r_panel() if rad < 0 else rad, border, bc), r)


func _txt(s: String, pos: Vector2, fs: int, col: Color, weight := "regular", max_w := -1.0, uebersetzen := true) -> void:
	if col.a <= 0.003:
		return
	var f := UzTheme.font(weight)
	var text := tr(s) if uebersetzen else s
	if max_w > 0.0:
		while text.length() > 3 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
			text = text.substr(0, text.length() - 2) + "…"
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _txt_w(s: String, fs: int, weight := "regular") -> float:
	return UzTheme.font(weight).get_string_size(tr(s), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _ico(name: String, r: Rect2, col: Color) -> void:
	if col.a > 0.003:
		draw_texture_rect(Icons.tex(name, int(r.size.y)), r, false, col)


func _draw() -> void:
	match kind:
		"guide": _draw_guide()
		"freunde": _draw_freunde()
		"medien": _draw_medien()
		"vorschau": _draw_vorschau()
		"online": _draw_online()
		"emulatoren": _draw_emulatoren()
		"schauen": _draw_schauen()


## Freunde, dann Medien: beide Szenen mit eigener Zeit; beim Wechsel blendet die Fläche kurz
## darüber aus und wieder ein.
func _draw_online() -> void:
	var keep := t
	var half := float(PERIOD.freunde)
	if t < half:
		_draw_freunde()
	else:
		t = t - half
		_draw_medien()
		var cover := 1.0 - eo(win(t, 0.0, 0.35))
		cover = maxf(cover, eio(win(t, half - 0.4, half)))
		if cover > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(UzTheme.col("surface"), cover))
	t = keep


# --- Guide über dem Spiel --------------------------------------------------------------------

func _draw_guide() -> void:
	var w := size.x
	var h := size.y
	# Das Spiel: Abendhimmel, Sonne, zwei Bergketten, die verschieden schnell ziehen (es läuft).
	var top := Color("#151b34")
	var mid := Color("#3d2f5e")
	var low := Color("#c97b68")
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.45), Vector2(0, h * 0.45)]), PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.45), Vector2(w, h * 0.45), Vector2(w, h * 0.72), Vector2(0, h * 0.72)]),
			PackedColorArray([mid, mid, low, low]))
	var sun := Vector2(w * 0.68, h * 0.6)
	_glow(sun, h * 0.42, Color("#ffcf9a", 0.5))
	draw_circle(sun, h * 0.075, Color("#ffe3bd"), true, -1.0, true)
	_ridge(h * 0.62, h * 0.08, t * 9.0, Color("#2b2447"), 0.011)
	_ridge(h * 0.74, h * 0.07, t * 22.0, Color("#171329"), 0.017)
	draw_rect(Rect2(0, h * 0.82, w, h * 0.18), Color("#0f0c1b"))
	# Anzeige des Spiels oben rechts.
	for i in 3:
		draw_rect(Rect2(w - 132 + i * 26, 26, 18, 18), Color(1, 1, 1, 0.85))
	var p := eo(win(t, 0.95, 1.31)) * (1.0 - eio(win(t, 8.1, 8.45)))
	# Die Guide-Taste: ein Druck unten in der Mitte, ein Ring läuft aus – zum Öffnen und zum Schließen.
	_guide_druck(win(t, 0.45, 1.25), win(t, 0.6, 0.9))
	_guide_druck(win(t, 7.7, 8.4), win(t, 7.8, 8.1))
	if p <= 0.0:
		return
	# Das Spiel tritt zurück, der Guide liegt darüber (es läuft weiter).
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.38 * p))
	var pw := w * 0.42
	var x := lerpf(-pw - 24.0, 0.0, p)
	draw_rect(Rect2(x, 0, pw, h), Color(UzTheme.col("surface"), 0.97))
	draw_rect(Rect2(x + pw - 1, 0, 1, h), UzTheme.col("line"))
	var ink := UzTheme.col("text")
	var acc := UzTheme.col("accent")
	draw_circle(Vector2(x + 38, 44), 9, acc, true, -1.0, true)
	_txt("Guide", Vector2(x + 58, 52), 24, ink, "bold")
	_txt("Spielt gerade", Vector2(x + 30, 92), 15, UzTheme.col("faint"), "medium")
	_txt("Abendrot", Vector2(x + 30, 118), 21, ink, "bold")
	var rows := [["friends", "Freunde", "3 online"], ["music", "Musik", "Nachtfahrt"], ["camera", "Bildschirmfoto", ""], ["spark", "Clip speichern", "30 s"],
			["power", "Ausschalten", ""]]
	var y0 := 140.0
	var rh := clampf((h - y0 - 16.0) / rows.size(), 44.0, 60.0)
	# Der Cursor wandert: Freunde → Musik → Bildschirmfoto → Clip → Ausschalten.
	var cur := eo(win(t, 2.6, 2.82)) + eo(win(t, 3.7, 3.92)) + eo(win(t, 4.9, 5.12)) + eo(win(t, 6.2, 6.42))
	# Ein Druck auf A: die Zeile gibt kurz nach (Bildschirmfoto, Clip).
	var druck := sin(PI * win(t, 4.2, 4.36)) + sin(PI * win(t, 5.4, 5.56))
	var fr := Rect2(x + 14, y0 + cur * rh + 4, pw - 28, rh - 8).grow(-3.0 * druck)
	UzTheme.draw_selection(self, fr)
	for i in rows.size():
		var e := eo(win(t, 1.1 + i * 0.06, 1.45 + i * 0.06))
		var ry := y0 + i * rh + (1.0 - e) * 8.0
		var on := absf(cur - i) < 0.5
		var r: Array = rows[i]
		var cy := ry + rh * 0.5
		_ico(str(r[0]), Rect2(x + 32, cy - 12, 24, 24), Color(acc if on else UzTheme.col("muted"), e))
		_txt(str(r[1]), Vector2(x + 72, cy + 7), 19, Color(ink, e), "medium")
		var vx := x + pw - 32.0
		if str(r[2]) != "":
			var vw := _txt_w(str(r[2]), 15)
			_txt(str(r[2]), Vector2(vx - vw, cy + 6), 15, Color(UzTheme.col("faint"), e))
			vx -= vw + 12.0
		if i == 0:
			# Wer online ist: drei kleine Profilbilder, leicht übereinander.
			for k in 3:
				var c := Vector2(vx - 12.0 - k * 18.0, cy)
				draw_circle(c, 12.5, Color(UzTheme.col("surface"), e), true, -1.0, true)
				draw_circle(c, 11.0, Color(Color(str(FREUNDE[k][3])), e), true, -1.0, true)
		elif i == 1:
			# Musik läuft: leise Pegel vor dem Titel.
			for b in 4:
				var lv := 0.35 + 0.65 * absf(sin(_total * (4.1 + b * 0.9) + b)) if not _calm else 0.3 + 0.15 * b
				var bh := 4.0 + 12.0 * lv
				draw_rect(Rect2(vx - 30.0 + b * 7.0, cy + 6.0 - bh, 4, bh), Color(acc, e))
	_guide_wirkung(x + pw, w, h)


## Der Druck auf die Guide-Taste unten in der Mitte: ein Punkt im Akzent, ein Ring läuft aus.
func _guide_druck(press: float, puls: float) -> void:
	if press <= 0.0 or press >= 1.0:
		return
	var pc := Vector2(size.x * 0.5, size.y - 56)
	var a := sin(PI * press)
	draw_circle(pc, 30, Color(0, 0, 0, 0.55 * a), true, -1.0, true)
	draw_circle(pc, 11.0 * (1.0 + 0.25 * sin(PI * puls)), Color(UzTheme.col("accent"), a), true, -1.0, true)
	if not UzTheme.matt():
		draw_arc(pc, lerpf(16.0, 52.0, eo(press)), 0.0, TAU, 48, Color(UzTheme.col("accent"), 0.7 * (1.0 - press)), 2.0, true)


## Was der Guide im Spiel bewirkt, rechts neben der Leiste: Musik läuft oben mit, das
## Bildschirmfoto blitzt und landet als Mitteilung, der Clip ebenso, Ausschalten klappt auf.
func _guide_wirkung(x0: float, w: float, h: float) -> void:
	var ink := UzTheme.col("text")
	var acc := UzTheme.col("accent")
	var cw := minf(330.0, w - x0 - 36.0)
	var cx := w - cw - 18.0
	# Musik: solange der Cursor dort steht, eine kleine Leiste mit Titel und Fortschritt.
	var mu := eo(win(t, 2.75, 3.05)) * (1.0 - eio(win(t, 3.8, 4.05)))
	if mu > 0.0:
		var r := Rect2(cx, lerpf(-80.0, 18.0, mu), cw, 72)
		draw_style_box(UzTheme.flaeche(UzTheme.col("surface_hi"), UzTheme.r_panel(), 3), r)
		var cv := Rect2(r.position + Vector2(12, 12), Vector2(48, 48))
		draw_polygon(PackedVector2Array([cv.position, Vector2(cv.end.x, cv.position.y), cv.end, Vector2(cv.position.x, cv.end.y)]),
				PackedColorArray([acc.lightened(0.25), acc, acc.darkened(0.45), acc.darkened(0.1)]))
		_txt("Nachtfahrt", Vector2(cv.end.x + 14, r.position.y + 32), 17, ink, "bold", cw - 90)
		_txt("Ruhiger Mix", Vector2(cv.end.x + 14, r.position.y + 54), 14, UzTheme.col("muted"), "regular", cw - 90)
		var prog := 0.2 + 0.25 * win(t, 2.75, 4.05)
		draw_rect(Rect2(r.position.x + 12, r.end.y - 5, r.size.x - 24, 2), UzTheme.col("line"))
		draw_rect(Rect2(r.position.x + 12, r.end.y - 5, (r.size.x - 24) * prog, 2), acc)
	# Bildschirmfoto: ein kurzer Blitz über allem, dann die Mitteilung mit dem kleinen Bild.
	if t >= 4.22 and t < 4.6 and not _calm:
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.42 * (1.0 - eo(win(t, 4.22, 4.6)))))
	var bf := eo(win(t, 4.35, 4.65)) * (1.0 - eio(win(t, 5.15, 5.4)))
	if bf > 0.0:
		_mitteilung(Rect2(cx, lerpf(-90.0, 18.0, bf), cw, 76), "Bildschirmfoto gespeichert", "Aufnahmen", "")
	var cl := eo(win(t, 5.55, 5.85)) * (1.0 - eio(win(t, 6.5, 6.75)))
	if cl > 0.0:
		_mitteilung(Rect2(cx, lerpf(-90.0, 18.0, cl), cw, 76), "Clip gespeichert", "Die letzten 30 Sekunden", "clip")
	# Ausschalten: daneben klappen die Möglichkeiten auf (wie im Guide).
	var ps := eo(win(t, 6.5, 6.8)) * (1.0 - eio(win(t, 7.45, 7.7)))
	if ps > 0.0:
		var items := [["image", "Ruhemodus"], ["moon", "Energiesparen"], ["power", "Herunterfahren"]]
		var r2 := Rect2(x0 + 16.0 + (1.0 - ps) * -12.0, h - 40.0 - items.size() * 44.0 - 20.0, minf(260.0, w - x0 - 32.0), items.size() * 44.0 + 20.0)
		draw_style_box(UzTheme.flaeche(Color(UzTheme.col("surface_hi"), ps), UzTheme.r_panel(), 3), r2)
		for k in items.size():
			var iy := r2.position.y + 10.0 + k * 44.0
			var sel := k == 1 and t > 6.95
			if sel:
				UzTheme.draw_selection(self, Rect2(r2.position.x + 6, iy + 2, r2.size.x - 12, 40), -1, ps)
			_ico(str(items[k][0]), Rect2(r2.position.x + 18, iy + 12, 20, 20), Color(acc if sel else UzTheme.col("muted"), ps))
			_txt(str(items[k][1]), Vector2(r2.position.x + 50, iy + 28), 16, Color(ink, ps), "medium")


## Eine Mitteilung oben rechts (wie in Uzai): ein kleines Bild des Spiels, Titel und eine Zeile.
func _mitteilung(r: Rect2, titel: String, zeile: String, art: String) -> void:
	draw_style_box(UzTheme.flaeche(UzTheme.col("surface_hi"), UzTheme.r_panel(), 3), r)
	var th := Rect2(r.position + Vector2(12, 12), Vector2(80, r.size.y - 24))
	draw_polygon(PackedVector2Array([th.position, Vector2(th.end.x, th.position.y), th.end, Vector2(th.position.x, th.end.y)]),
			PackedColorArray([Color("#151b34"), Color("#3d2f5e"), Color("#c97b68"), Color("#2b2447")]))
	draw_circle(th.position + Vector2(th.size.x * 0.68, th.size.y * 0.62), 5.0, Color("#ffe3bd"), true, -1.0, true)
	if art == "clip":
		draw_circle(th.position + Vector2(10, 10), 4.5, UzTheme.col("live"), true, -1.0, true)
	var tw := r.size.x - th.size.x - 40.0
	_txt(titel, Vector2(th.end.x + 14, r.position.y + 34), 17, UzTheme.col("text"), "bold", tw)
	_txt(zeile, Vector2(th.end.x + 14, r.position.y + 58), 14, UzTheme.col("muted"), "regular", tw)


## Eine Bergkette: Summe zweier Wellen, zieht mit off nach links.
func _ridge(base: float, amp: float, off: float, col: Color, f: float) -> void:
	var w := size.x
	var pts := PackedVector2Array([Vector2(0, size.y)])
	var x := 0.0
	while x <= w + 24.0:
		var u := x + off
		pts.append(Vector2(x, base - amp * (0.6 * sin(u * f) + 0.4 * sin(u * f * 2.3 + 1.7))))
		x += 24.0
	pts.append(Vector2(w + 24.0, size.y))
	draw_colored_polygon(pts, col)


# --- Freunde von Steam und Discord -------------------------------------------------------------

const FREUNDE := [
	["Mia", "Spielt Hades", "steam", "#7aa2ff"],
	["Jonas", "Im Sprachkanal · Abendrunde", "discord", "#69e39a"],
	["Lena", "Spielt Celeste", "steam", "#f29ad8"],
	["Kai", "Online", "discord", "#e7c27d"],
]


func _draw_freunde() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), UzTheme.col("surface"))
	var out := 1.0 - eio(win(t, 6.75, 7.15))
	var ink := UzTheme.col("text")
	var head := eo(win(t, 0.05, 0.4)) * out
	_txt("Freunde", Vector2(30, 52), 26, Color(ink, head), "bold")
	var on := "4 online"
	_txt(on, Vector2(w - 30 - _txt_w(on, 16, "medium"), 50), 16, Color(UzTheme.col("faint"), head), "medium")
	var y0 := 78.0
	var rh := (h - y0 - 18.0) / 4.0
	var cur := eo(win(t, 1.6, 1.82))
	# Der Cursor wie überall: eine gehobene, matte Fläche, keine Linie darum.
	UzTheme.draw_selection(self, Rect2(14, y0 + cur * rh + 3, w - 28, rh - 6), -1, out)
	for i in FREUNDE.size():
		var f: Array = FREUNDE[i]
		var e := eo(win(t, 0.25 + i * 0.12, 0.65 + i * 0.12)) * out
		if e <= 0.0:
			continue
		var ry := y0 + i * rh
		var dx := (1.0 - e) * 26.0
		var cy := ry + rh * 0.5
		var av := Color(str(f[3]))
		draw_circle(Vector2(56 + dx, cy), 25, Color(av, e), true, -1.0, true)
		var ini := str(f[0]).substr(0, 1)
		var iw := _txt_w(ini, 22, "bold")
		_txt(ini, Vector2(56 + dx - iw * 0.5, cy + 8), 22, Color(UzTheme.text_on(av), e), "bold")
		draw_circle(Vector2(75 + dx, cy + 18), 8, Color(UzTheme.col("surface"), e), true, -1.0, true)
		draw_circle(Vector2(75 + dx, cy + 18), 5.5, Color(UzTheme.col("ok"), e), true, -1.0, true)
		_txt(str(f[0]), Vector2(98 + dx, cy - 4), 21, Color(ink, e), "bold")
		var st := str(f[1])
		_txt(st, Vector2(98 + dx, cy + 22), 16, Color(UzTheme.col("muted"), e))
		if str(f[2]) == "discord" and i == 1:
			# Im Sprachkanal: leise Pegel neben dem Status.
			var bx := 98 + dx + _txt_w(st, 16) + 12.0
			for b in 4:
				var lv := 0.35 + 0.65 * absf(sin(_total * 5.3 + b * 1.7)) if not _calm else 0.6
				var bh := 4.0 + 12.0 * lv
				draw_rect(Rect2(bx + b * 7, cy + 17 - bh, 4, bh), Color(UzTheme.col("ok"), e))
		var src := "Steam" if str(f[2]) == "steam" else "Discord"
		var sw := _txt_w(src, 15, "medium")
		_txt(src, Vector2(w - 34 - sw + dx, cy + 6), 15, Color(UzTheme.col("faint"), e), "medium")
		_ico(str(f[2]), Rect2(w - 66 - sw + dx, cy - 11, 22, 22), Color(UzTheme.col("faint"), e))
	# Eine Einladung kommt (wie im echten Uzai oben rechts) und geht wieder.
	var inv := eo(win(t, 2.6, 2.95)) * (1.0 - eio(win(t, 5.4, 5.75)))
	if inv > 0.0:
		var cw := 372.0
		var r := Rect2(w - cw - 18, lerpf(-110.0, 16.0, inv), cw, 92)
		draw_style_box(UzTheme.flaeche(UzTheme.col("surface_hi"), UzTheme.r_panel(), 3), r)
		var ac := Vector2(r.position.x + 44, r.position.y + 46)
		draw_circle(ac, 22, Color(FREUNDE[2][3]), true, -1.0, true)
		_txt("L", Vector2(ac.x - 7, ac.y + 8), 20, UzTheme.text_on(Color(FREUNDE[2][3])), "bold")
		_txt("Lena lädt dich ein", Vector2(r.position.x + 80, r.position.y + 40), 18, ink, "bold", cw - 140)
		_txt("Celeste · jetzt beitreten", Vector2(r.position.x + 80, r.position.y + 66), 15, UzTheme.col("muted"), "regular", cw - 140)
		_ico("join", Rect2(r.end.x - 48, r.position.y + 32, 28, 28), UzTheme.col("accent"))


# --- Apps und Medien ---------------------------------------------------------------------------

const KACHELN := [["music", "Musik"], ["video", "YouTube"], ["film", "Filme & Serien"], ["live", "Twitch"], ["image", "Aufnahmen"], ["apps", "Apps"]]
const WEG := [0, 1, 2, 5, 4, 3]


## Die Kacheln zeigen echte Inhalte, wenn es sie gibt (Albumcover, Filmposter, das große Bild eines
## eigenen Spiels als Stream, das neueste Bildschirmfoto – einrichtung_inhalt.gd), sonst eigene
## Bilder; der Name steht auf einem Schleier unten, das Zeichen in einer kleinen Marke oben links.
func _draw_medien() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), UzTheme.col("surface"))
	var pad := 26.0
	var gap := 14.0
	var bar_h := 96.0
	var tw := (w - pad * 2.0 - gap * 2.0) / 3.0
	var th := (h - pad * 2.0 - bar_h - gap * 2.0) / 2.0
	var rect_of := func(i: int) -> Rect2:
		return Rect2(pad + (i % 3) * (tw + gap), pad + int(i / 3.0) * (th + gap), tw, th)
	# Der Cursor wandert über die Kacheln (je 1,2 s, gleitet in 0,22 s).
	var step := int(t / 1.2) % WEG.size()
	var mv := eo(win(fmod(t, 1.2), 0.0, 0.22))
	var from: Rect2 = rect_of.call(WEG[(step + WEG.size() - 1) % WEG.size()])
	var to: Rect2 = rect_of.call(WEG[step])
	if _calm:
		from = to
		mv = 1.0
	var ink := UzTheme.col("text")
	var acc := UzTheme.col("accent")
	var rad := float(UzTheme.r_panel())
	var zeit := _total if not _calm else 2.0
	for i in KACHELN.size():
		var r: Rect2 = rect_of.call(i)
		var on: bool = i == int(WEG[step])
		var lift := mv if on else 0.0
		var rr := r.grow(4.0 * lift)
		Inhalt.schatten(self, rr, rad, 0.35 + 0.45 * lift)
		var art: String = Inhalt.ARTEN[i]
		var tex := Inhalt.bild(art)
		if tex:
			Inhalt.bild_zeichnen(self, rr, tex, rad, 1.0, 1.0 + 0.05 * lift, Vector2(0.5, 0.3))
		else:
			Inhalt.illu(self, art, rr, rad, zeit, acc)
		if art == "live":
			var lp := Rect2(rr.position + Vector2(rr.size.x - 78.0, 16.0), Vector2(60, 24))
			draw_style_box(UzTheme.box(UzTheme.col("danger"), 6), lp)
			_txt_c("LIVE", lp.get_center() + Vector2(0, 6), 14, Color.WHITE, "bold")
		Inhalt.schleier(self, rr, rad, 0.45, 0.82)
		# Oben links das Zeichen in einer kleinen dunklen Marke, unten der Name.
		var mc := rr.position + Vector2(36, 36)
		draw_circle(mc, 20.0, Color(0, 0, 0, 0.42), true, -1.0, true)
		var k: Array = KACHELN[i]
		_ico(str(k[0]), Rect2(mc - Vector2(12, 12), Vector2(24, 24)), acc.lerp(Color.WHITE, 0.35) if on else Color(1, 1, 1, 0.92))
		_txt(str(k[1]), Vector2(rr.position.x + 22, rr.end.y - 20), 19, Color.WHITE, "bold", rr.size.x - 40)
		if not on:
			draw_colored_polygon(Inhalt.rund(rr, rad), Color(0, 0, 0, 0.16))
	var fr := Rect2(from.position.lerp(to.position, mv), from.size).grow(4.0 * mv + 3.0)
	_box(fr, Color(0, 0, 0, 0), 3, UzTheme.col("focus"), int(rad) + 3)
	# Unten läuft Musik: Hülle (das echte Albumcover, wenn es eins gibt), Titel, Pegel und Fortschritt.
	var b := Rect2(pad, h - pad - bar_h, w - pad * 2.0, bar_h)
	_box(b, UzTheme.col("surface_hi"))
	var cv := Rect2(b.position + Vector2(16, 16), Vector2(64, 64))
	var mt := Inhalt.bild("musik")
	if mt:
		Inhalt.bild_zeichnen(self, cv, mt, 6.0)
	else:
		Inhalt.illu(self, "musik", cv, 6.0, zeit, acc)
	_txt("Nachtfahrt", Vector2(cv.end.x + 18, b.position.y + 42), 19, ink, "bold")
	_txt("Ruhiger Mix", Vector2(cv.end.x + 18, b.position.y + 68), 15, UzTheme.col("muted"))
	var ex := b.end.x - 120.0
	for i in 6:
		var lv := 0.3 + 0.7 * absf(sin(_total * (3.1 + i * 0.7) + i)) if not _calm else 0.3 + 0.1 * i
		var bh := 8.0 + 36.0 * lv
		draw_rect(Rect2(ex + i * 14, b.position.y + 66 - bh, 8, bh), acc)
	var prog := fmod(_total, 40.0) / 40.0 if not _calm else 0.35
	draw_rect(Rect2(b.position.x + 16, b.end.y - 6, (b.size.x - 32), 2), UzTheme.col("line"))
	draw_rect(Rect2(b.position.x + 16, b.end.y - 6, (b.size.x - 32) * prog, 2), acc)


# --- Vorschau im Willkommen --------------------------------------------------------------------

## Die Stationen leuchten zuerst nacheinander auf, danach wandert ein leises Licht von einer zur
## nächsten (je 1,4 s).
func _draw_vorschau() -> void:
	var n := STATIONEN.size()
	var cw := size.x / n
	var ink := UzTheme.col("text")
	var acc := UzTheme.col("accent")
	var spot := -1
	if _total > 1.6 and not _calm:
		spot = int((_total - 1.6) / 1.4) % n
	for i in n:
		var s: Array = STATIONEN[i]
		var e := eo(win(_total, 0.55 + i * 0.12, 0.95 + i * 0.12))
		if e <= 0.0:
			continue
		var cx := cw * (i + 0.5)
		var on := i == spot
		var glow := 0.0
		if on:
			var ph := fmod(_total - 1.6, 1.4) / 1.4
			glow = sin(PI * clampf(ph, 0.0, 1.0))
		var box := Rect2(cx - 34, (1.0 - e) * 10.0, 68, 68)
		_box(box, Color(UzTheme.col("text"), (0.05 + 0.04 * glow) * e), 1, Color(acc, 0.6 * glow * e))
		_ico(str(s[0]), Rect2(box.get_center() - Vector2(17, 17), Vector2(34, 34)), Color(UzTheme.col("muted").lerp(acc, glow), e))
		var lw := _txt_w(str(s[1]), 16, "medium")
		_txt(str(s[1]), Vector2(cx - lw * 0.5, box.end.y + 30), 16, Color(UzTheme.col("muted").lerp(ink, glow), e), "medium")


# --- Vorstellung: gemeinsame Teile -----------------------------------------------------------

## Raum der großen Szenen: oben eine Spur heller, unten Tiefe, von oben fällt Licht im Akzent (wie
## das Material der Flächen, Kernlicht).
func _raum(licht: Vector2) -> void:
	var w := size.x
	var h := size.y
	var top := UzTheme.col("surface").lerp(UzTheme.col("text"), 0.035)
	var bot := UzTheme.col("bg")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), PackedColorArray([top, top, bot, bot]))
	_glow(licht, h * 1.1, Color(UzTheme.col("accent"), 0.11))
	_glow(licht, h * 0.4, Color(UzTheme.col("accent").lerp(Color.WHITE, 0.3), 0.06))


## Kapitel oben links: kurze Wörter, das aktuelle hell mit einem Strich im Akzent, der sich in seinem
## Abschnitt füllt. teile: [[ab, bis, Wort], …].
func _kapitel(teile: Array, at: Vector2, a := 1.0) -> void:
	if a <= 0.01:
		return
	var x := at.x
	var ink := UzTheme.col("text")
	for k0 in teile:
		var k: Array = k0
		var an := t >= float(k[0]) and t < float(k[1])
		var wd := _txt_w(str(k[2]), 19, "bold")
		_txt(str(k[2]), Vector2(x, at.y + 20), 19, Color(ink, (1.0 if an else 0.45) * a), "bold")
		draw_rect(Rect2(x, at.y + 32, wd, 2), Color(UzTheme.col("line"), a))
		if an:
			var p := clampf((t - float(k[0])) / (float(k[1]) - float(k[0])), 0.0, 1.0)
			draw_rect(Rect2(x, at.y + 32, wd * p, 2), Color(UzTheme.col("accent"), a))
		x += wd + 36.0


## Text mittig um x (Grundlinie y).
func _txt_c(s_: String, at: Vector2, fs: int, col: Color, weight := "regular") -> void:
	_txt(s_, Vector2(at.x - _txt_w(s_, fs, weight) * 0.5, at.y), fs, col, weight)


## Ein Ring, der beim Landen ausläuft (x: 0 … 1), dazu ein Lichtschein.
func _landung(c: Vector2, x: float, r0: float, a: float) -> void:
	if x <= 0.0 or x >= 1.0 or _calm or a <= 0.01:
		return
	var acc := UzTheme.col("accent")
	draw_arc(c, lerpf(r0, r0 * 2.6, eo(x)), 0.0, TAU, 56, Color(acc, 0.7 * (1.0 - x) * a), 2.0, true)
	_glow(c, r0 * 3.0, Color(acc, 0.2 * (1.0 - x) * a))


# --- Emulatoren ------------------------------------------------------------------------------

## Honest rather than a demo: a scene that looks as if every emulator were already being set up would be
## misleading, so it only shows what really exists on this PC (stand() from the setup). No ring fills up
## and no „Lädt …“ appears while nothing is loading; progress only appears while a download approved by
## the user (retro_einrichten.gd) is actually running.
const EMU_KAPITEL := [[0.0, 3.2, "Erkannt"], [3.2, 6.4, "Emulatoren"], [6.4, 9.6, "Belegt"]]
## Zustand je System → [Text, Farbe]. bereit: Emulator gefunden · angebot: Uzai kann ihn von der
## offiziellen Quelle laden, erst nach Zustimmung · laedt/wartet: ein Laden läuft wirklich ·
## selbst: Uzai lädt dafür nichts (von Hand einrichten).
const EMU_ZUSTAND := {
	"bereit": ["Bereit", "ok"],
	"angebot": ["Kann geladen werden", "muted"],
	"wartet": ["Wartet …", "muted"],
	"laedt": ["Lädt …", "accent"],
	"selbst": ["Von Hand", "faint"],
}

var _emus: Array = []           ## Karten: die Systeme der Sammlung (einrichtung_inhalt.emu_liste, mit dem echten Stand)
var _emu_stand: Array = []      ## echter Stand je System mit Spielen: { sys, kurz, name, spiele, zustand, pct, emu, emu_name, farbe }
var _emu_echt := false          ## stand() kam: nur echte Systeme (ohne: Beispiel, ohne Zustand)


## The real state (setup_wizard_show.gd _emu_stand, twice per second). If there are systems with
## games, only those appear on the cards; otherwise a calm empty state (leer(), _emu_leer) instead of
## example cards and an empty window, which would look odd when there is nothing to set up yet.
func stand(liste: Array) -> void:
	_emu_echt = true
	_emu_stand = liste.duplicate(true)
	var basis := {}
	for e in Inhalt.emu_liste():
		basis[str(e.sys)] = e
	if liste.is_empty():
		_emus = []
	else:
		_emus = []
		for s in liste:
			var b: Dictionary = (basis.get(str(s.sys), {}) as Dictionary).duplicate()
			b.merge(s, true)
			_emus.append(b)
	queue_redraw()


## Links die Systeme als Karten (Logo oder eigene Silhouette, die Cover der eigenen Spiele, Zahl der
## Spiele); ein Licht tastet die Sammlung ab, ein Haken nur dort, wo der Emulator wirklich da ist.
## Rechts ein Fenster mit dem echten Stand je System (Bereit, Kann geladen werden, Von Hand – ein
## Fortschritt nur, wenn wirklich geladen wird). Zum Schluss (Belegt) zeigt das Fenster Spieler 1–4.
func _draw_emulatoren() -> void:
	var w := size.x
	var h := size.y
	if leer():
		_emu_leer()
		return
	if _emus.is_empty():
		_emus = Inhalt.emu_liste()
	_raum(Vector2(w * 0.32, -h * 0.15))
	var aus := 1.0 - eio(win(t, 9.2, 9.6))
	var a := eo(win(t, 0.0, 0.35)) * aus if not _calm else 1.0
	_kapitel(EMU_KAPITEL, Vector2(36, 24), a)
	var n := _emus.size()
	var top := 92.0
	var bottom := h - 64.0
	var left_w := (w - 72.0) * 0.6
	var cols := 3
	var rows := maxi(2, int(ceilf(n / float(cols))))
	var gap := 18.0
	var cw := (left_w - gap * (cols - 1)) / cols
	var ch := (bottom - top - gap * (rows - 1)) / maxf(rows, 1.0)
	# Das Licht, das die Sammlung abtastet (0,25 … 2,6 s).
	var scan := win(t, 0.25, 2.6) if not _calm else 1.0
	var sx := lerpf(36.0 - 60.0, 36.0 + left_w + 60.0, eio(scan))
	var erkannt := 0
	for i in n:
		var r := Rect2(36.0 + (i % cols) * (cw + gap), top + int(i / float(cols)) * (ch + gap), cw, ch)
		var seen := 1.0 if scan >= 1.0 else clampf((sx - r.position.x) / cw, 0.0, 1.0)
		if seen > 0.6:
			erkannt += 1
		var e := eo(seen)
		if a * e <= 0.01:
			continue
		_emu_karte(_emus[i], Rect2(r.position + Vector2(0, (1.0 - e) * 24.0), r.size), a * e, eo(win(seen, 0.55, 1.0)))
	if scan > 0.0 and scan < 1.0:
		var sa := sin(PI * scan) * a
		var acc := UzTheme.col("accent")
		_glow(Vector2(sx, (top + bottom) * 0.5), (bottom - top) * 0.7, Color(acc, 0.2 * sa))
		draw_rect(Rect2(sx - 1.0, top - 24.0, 2.0, bottom - top + 48.0), Color(acc.lerp(Color.WHITE, 0.5), 0.85 * sa))
	# Rechts das Fenster: erst der Stand, ab Belegt die Plätze der Spieler.
	var pr := Rect2(36.0 + left_w + 36.0, top, w - 36.0 - (36.0 + left_w + 36.0), bottom - top)
	var hoch := eio(win(t, 6.3, 6.8)) if not _calm else 0.0
	var pa := a * eo(win(t, 0.4, 0.9)) if not _calm else 1.0
	if pa > 0.01:
		Inhalt.schatten(self, pr, float(UzTheme.r_panel()), 0.7 * pa)
		draw_style_box(UzTheme.flaeche(Color(UzTheme.col("surface_hi"), 0.94 * pa), UzTheme.r_panel(), 3), pr)
		draw_rect(Rect2(pr.position.x + 18.0, pr.position.y + 1.0, pr.size.x - 36.0, 1.0), Color(1, 1, 1, 0.08 * pa))
		if hoch < 1.0:
			_emu_liste(pr, pa * (1.0 - hoch))
		if hoch > 0.0:
			_emu_spieler(pr, pa * hoch)
	# Unten, was wirklich ist.
	var zeile := ""
	var offen := _emu_stand.filter(func(s: Dictionary) -> bool: return str(s.zustand) == "angebot").size()
	var laeuft := _emu_stand.any(func(s: Dictionary) -> bool: return str(s.zustand) in ["laedt", "wartet"])
	if t < 3.2:
		if _emu_stand.size() > 0 and erkannt > 0:
			zeile = tr("%d Systeme erkannt") % mini(erkannt, _emu_stand.size()) if _emu_stand.size() != 1 else tr("Ein System erkannt")
	elif t < 6.3:
		if laeuft:
			zeile = tr("Lädt von der offiziellen Quelle")
		elif offen > 0:
			zeile = tr("Geladen wird erst nach deiner Zustimmung")
		elif not _emu_stand.is_empty():
			zeile = tr("Alle Emulatoren bereit")
	elif t > 7.6:
		zeile = tr("Spieler 1–4 automatisch belegt")
	if zeile != "":
		_txt(zeile, Vector2(36, h - 24), 21, Color(UzTheme.col("muted"), a), "medium", -1.0, false)


## Ohne Emulator-Spiele (der echte Stand ist da und leer)?
func leer() -> bool:
	return _emu_echt and _emu_stand.is_empty()


## Leerer Zustand: kein Abtasten, keine Kapitel, keine erfundenen Systeme. In der Mitte ruhig drei
## Silhouetten (Heimkonsole, Handheld, Disc-Konsole) im Kernlicht, darunter Satz und Zeile. Kommt
## einmal weich (nicht in der Schleife der Szene); darunter steht auf der Seite „Ordner hinzufügen“.
func _emu_leer() -> void:
	var w := size.x
	var h := size.y
	_raum(Vector2(w * 0.5, -h * 0.1))
	var a := eo(win(_total, 0.0, 0.6)) if not _calm else 1.0
	var ink := UzTheme.col("text")
	var mitte := Vector2(w * 0.5, h * 0.36)
	_glow(mitte, h * 0.42, Color(UzTheme.col("accent"), 0.12 * a))
	var s := minf(h * 0.3, 150.0)
	var reihe := [["snes", -1.0], ["gba", 0.0], ["ps1", 1.0]]
	for r0 in reihe:
		var sys := str(r0[0])
		var k := float(r0[1])
		var c := mitte + Vector2(k * s * 1.25, absf(k) * s * 0.06)
		var farbe := Color(str(Config.system(sys).get("color", "#7a5fd0"))).darkened(0.35)
		Inhalt.silhouette(self, sys, c, s * (0.82 if k == 0.0 else 1.0), Color(ink, (0.55 if k == 0.0 else 0.35) * a), Color(farbe, a))
	_txt_c("Keine Retro-Spiele gefunden", Vector2(w * 0.5, h * 0.7), 30, Color(ink, a), "bold")
	_txt_c("Uzai liest Spieleordner jederzeit ein.", Vector2(w * 0.5, h * 0.7 + 42.0), 20, Color(UzTheme.col("muted"), a), "regular")


## Eine Karte: oben die Cover der eigenen Spiele dieses Systems (leicht aufgefächert) oder die
## eigene Silhouette der Konsole, unten das Logo (zur Laufzeit) bzw. der Name und die Zahl der Spiele.
## Ein Haken nur, wenn der Emulator wirklich da ist.
func _emu_karte(e: Dictionary, r: Rect2, ca: float, hk: float) -> void:
	var ink := UzTheme.col("text")
	var sc: Color = e.farbe
	var rad := float(UzTheme.r_panel())
	Inhalt.schatten(self, r, rad, 0.55 * ca)
	var huelle := Inhalt.rund(r, rad)
	Inhalt.verlauf(self, huelle, r, Color(UzTheme.col("surface_hi").lerp(sc, 0.12), ca), Color(UzTheme.col("surface"), ca))
	_glow(r.position + Vector2(r.size.x * 0.3, r.size.y * 0.25), r.size.y * 0.75, Color(sc, 0.16 * ca))
	draw_rect(Rect2(r.position.x + rad, r.position.y + 1.0, r.size.x - rad * 2.0, 1.0), Color(1, 1, 1, 0.1 * ca))
	var bild := Rect2(r.position + Vector2(16, 16), Vector2(r.size.x - 32.0, r.size.y * 0.58 - 16.0))
	var covers: Array = []
	for k in 3:
		var tex := Inhalt.bild("cover:%s:%d" % [str(e.sys), k])
		if tex:
			covers.append(tex)
	if covers.is_empty():
		Inhalt.silhouette(self, str(e.sys), bild.get_center() + Vector2(0, bild.size.y * 0.08), minf(bild.size.x * 0.62, bild.size.y * 1.25),
				Color(ink, 0.9 * ca), sc)
	else:
		var chh := bild.size.y * 0.98
		var cww := chh * 0.72
		var reihe := [1, 2, 0] if covers.size() == 3 else range(covers.size())
		for k: int in reihe:
			if k >= covers.size():
				continue
			var off := (k - (covers.size() - 1) * 0.5)
			var dreh := off * 0.12
			var cr := Rect2(-cww * 0.5, -chh * 0.5, cww, chh)
			draw_set_transform(bild.get_center() + Vector2(off * cww * 0.62, absf(off) * chh * 0.05), dreh, Vector2.ONE * (1.0 - absf(off) * 0.1))
			Inhalt.schatten(self, cr, 4.0, 0.6 * ca)
			Inhalt.bild_zeichnen(self, cr, covers[k], 4.0, ca)
			draw_set_transform(Vector2.ZERO)
	# Unten: Logo oder Name, darunter die Zahl der eigenen Spiele bzw. der volle Name.
	var ly := r.position.y + r.size.y * 0.62
	var lr := Rect2(r.position.x + 18.0, ly, r.size.x - 70.0, minf(30.0, r.size.y * 0.14))
	var key := str(BadgeLogos.SYSTEM_LOGO.get(str(e.sys), ""))
	if not Inhalt.logo(self, key, lr, Color(ink, ca), true):
		_txt(str(e.kurz), Vector2(lr.position.x, lr.end.y - 3.0), int(lr.size.y * 0.95), Color(ink, ca), "bold", lr.size.x)
	var sub := U.plural(int(e.spiele), "Spiel", "Spiele") if int(e.spiele) > 0 else str(e.name)
	_txt(sub, Vector2(r.position.x + 18.0, r.end.y - 18.0), 15, Color(UzTheme.col("muted"), ca), "medium", r.size.x - 36.0)
	if hk > 0.0 and str(e.get("zustand", "")) == "bereit":
		var hc := Vector2(r.end.x - 26.0, r.end.y - 26.0)
		draw_circle(hc, 13.0 * hk, Color(UzTheme.col("ok"), ca), true, -1.0, true)
		_ico("check", Rect2(hc - Vector2(8, 8), Vector2(16, 16)), Color(UzTheme.col("bg"), ca * hk))


## Das Fenster mit dem echten Stand: Kopf „x von y bereit“, je System mit Spielen eine Zeile mit dem
## Zeichen des Emulators, für welches System und dem Zustand. Fortschritt (Ring, Prozent) nur, wenn
## wirklich geladen wird. Ohne Emulator-Spiele ein ruhiger Satz statt einer erfundenen Liste.
func _emu_liste(pr: Rect2, a: float) -> void:
	var ink := UzTheme.col("text")
	var muted := UzTheme.col("muted")
	var okc := UzTheme.col("ok")
	var acc := UzTheme.col("accent")
	var n := mini(_emu_stand.size(), 6)
	_txt("Emulatoren", pr.position + Vector2(24, 40), 21, Color(ink, a), "bold")
	if n == 0:
		_txt_c(tr("Noch keine Emulator-Spiele") if _emu_echt else "", pr.get_center() + Vector2(0, 4), 18, Color(muted, a), "medium")
		return
	var bereit := _emu_stand.filter(func(s: Dictionary) -> bool: return str(s.zustand) == "bereit").size()
	var zahl := tr("%d von %d bereit") % [bereit, _emu_stand.size()]
	var zw := _txt_w(zahl, 15, "medium")
	_txt(zahl, Vector2(pr.end.x - 24.0 - zw, pr.position.y + 39.0), 15, Color(okc if bereit == _emu_stand.size() else muted, a), "medium", -1.0, false)
	draw_rect(Rect2(pr.position.x + 24.0, pr.position.y + 58.0, pr.size.x - 48.0, 1.0), Color(UzTheme.col("line"), a))
	var y0 := pr.position.y + 66.0
	var rh := minf(78.0, (pr.end.y - 10.0 - y0) / maxf(n, 1.0))
	for i in n:
		var e: Dictionary = _emu_stand[i]
		var ra := a * (eo(win(t, 0.5 + i * 0.12, 0.9 + i * 0.12)) if not _calm else 1.0)
		if ra <= 0.01:
			continue
		var cy := y0 + i * rh + rh * 0.5
		var x := pr.position.x + 24.0 + (1.0 - ra / maxf(a, 0.001)) * 16.0
		var zr := minf(21.0, rh * 0.34)
		var zc := Vector2(x + zr + 4.0, cy)
		var zst := str(e.zustand)
		Inhalt.emu_zeichen(self, e if str(e.emu) != "" else e.merged({ "emu_name": str(e.kurz) }), zc, zr, ra * (1.0 if zst == "bereit" else 0.55))
		if zst == "laedt":
			draw_arc(zc, zr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(e.pct), 0.02, 1.0), 48, Color(acc, ra), 2.5, true)
		var tx := zc.x + zr + 16.0
		var stat_w := 200.0
		var nm := str(e.emu_name) if str(e.emu_name) != "" else tr("Kein Emulator")
		var unter := tr("für %s") % str(e.kurz) + " · " + U.plural(int(e.spiele), "Spiel", "Spiele")
		var platz := pr.end.x - tx - stat_w - 24.0
		if rh >= 54.0:
			_txt(nm, Vector2(tx, cy - 2.0), 18, Color(ink, ra), "bold", platz, false)
			_txt(unter, Vector2(tx, cy + 20.0), 14, Color(muted, ra), "regular", platz, false)
		else:
			# Wenig Höhe (viele Systeme): eine Zeile, Name und System nebeneinander.
			_txt(nm, Vector2(tx, cy + 6.0), 17, Color(ink, ra), "bold", platz, false)
			var nw := minf(_txt_w(nm, 17, "bold"), platz)
			_txt(str(e.kurz), Vector2(tx + nw + 10.0, cy + 6.0), 14, Color(muted, ra), "medium", maxf(0.0, platz - nw - 10.0), false)
		var zs: Array = EMU_ZUSTAND.get(zst, ["", "muted"])
		var txt := tr(str(zs[0]))
		if zst == "laedt" and float(e.pct) > 0.0:
			txt += " %d %%" % int(clampf(float(e.pct), 0.0, 1.0) * 100.0)
		var col := UzTheme.col(str(zs[1]))
		var sx := pr.end.x - 24.0
		var tw := _txt_w(txt, 15, "medium")
		_txt(txt, Vector2(sx - tw, cy + 6.0), 15, Color(col, ra), "medium", -1.0, false)
		if zst == "bereit":
			var hc := Vector2(sx - tw - 18.0, cy + 1.0)
			draw_circle(hc, 9.0, Color(okc, ra), true, -1.0, true)
			_ico("check", Rect2(hc - Vector2(6, 6), Vector2(12, 12)), Color(UzTheme.col("bg"), ra))
		elif zst == "angebot":
			draw_circle(Vector2(sx - tw - 14.0, cy + 1.0), 4.0, Color(acc, ra), true, -1.0, true)


## Belegt: im Fenster vier Plätze (2 × 2), je ein Controller fliegt hinein und landet mit Licht;
## Spieler 3 und 4 über Multitap.
func _emu_spieler(pr: Rect2, a: float) -> void:
	var acc := UzTheme.col("accent")
	var ink := UzTheme.col("text")
	var gap := 16.0
	var inner := pr.grow(-24.0)
	inner.position.y += 20.0
	inner.size.y -= 20.0
	var sw := (inner.size.x - gap) * 0.5
	var sh := (inner.size.y - gap) * 0.5
	for p in 4:
		var r := Rect2(inner.position + Vector2((p % 2) * (sw + gap), int(p / 2.0) * (sh + gap)), Vector2(sw, sh))
		var ins := (eo(win(t, 6.55 + p * 0.08, 6.95 + p * 0.08)) if not _calm else 1.0) * a
		if ins <= 0.01:
			continue
		draw_style_box(UzTheme.flaeche(Color(UzTheme.col("surface"), 0.9 * ins), UzTheme.r_panel(), 1), r)
		_txt_c(tr("Spieler %d") % (p + 1), Vector2(r.get_center().x, r.end.y - 16.0), 16, Color(UzTheme.col("muted"), ins), "medium")
		var land := eo(win(t, 6.95 + p * 0.36, 7.5 + p * 0.36)) if not _calm else 1.0
		var c := Vector2(r.get_center().x, lerpf(pr.end.y + 60.0, r.position.y + sh * 0.42, land))
		if land > 0.0:
			var s := minf(56.0, sh * 0.5)
			_ico("controller", Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), Color(ink, land * a))
		if land >= 1.0:
			draw_rect(Rect2(r.position.x + 16.0, r.end.y - 5.0, r.size.x - 32.0, 3.0), Color(acc, a))
			_landung(c, win(t, 7.5 + p * 0.36, 8.3 + p * 0.36), 18.0, a)
	var mt := (eo(win(t, 8.0, 8.4)) if not _calm else 1.0) * a
	if mt > 0.01:
		# Zwischen Spieler 3 und 4.
		var mr := Rect2(inner.get_center().x - 75.0, inner.position.y + sh + gap * 0.5 - 18.0, 150.0, 36.0)
		draw_style_box(UzTheme.flaeche(Color(UzTheme.col("surface_hi"), mt), 999, 2), mr)
		_ico("link", Rect2(mr.position + Vector2(14, 8), Vector2(20, 20)), Color(acc, mt))
		_txt("Multitap", Vector2(mr.position.x + 42.0, mr.position.y + 25.0), 16, Color(ink, mt), "bold")


# --- Schauen & Hören ---------------------------------------------------------------------------

const SCHAUEN := ["Musik", "Videos", "Filme", "Live"]
## Eigene Zeilen (kein fremdes Lied).
const LYRICS := ["Lichter ziehen vorbei", "Die Stadt schläft noch nicht", "Wir fahren durch die Nacht", "Und alles leuchtet",
	"Bis der Morgen kommt", "Lichter ziehen vorbei"]
const CHAT := [["Mira", "Was für ein Sprung!"], ["Jonas", "GG"], ["Noor", "Noch eine Runde?"], ["Kai", "Grüße aus Hamburg"], ["Lea", "Das Licht da hinten …"]]
const SEG := 2.5
## Eigene Bilder, wo es nichts Eigenes gibt: [Farbton, Art] der Landschaft (Inhalt.landschaft) und
## eigene Namen.
const EIGEN_VIDEOS := [[0.07, 0, "4:12"], [0.04, 2, "12:40"], [0.5, 2, "8:03"], [0.92, 0, "21:17"], [0.33, 0, "6:55"], [0.6, 1, "15:02"]]
const EIGEN_FILME := [[0.63, 1], [0.04, 0], [0.5, 2], [0.86, 0], [0.3, 1]]
var _sch := {}                   ## Inhalt.schauen(): echte Inhalte je Station


func _draw_schauen() -> void:
	var w := size.x
	var h := size.y
	var ink := UzTheme.col("text")
	var muted := UzTheme.col("muted")
	_raum(Vector2(w * 0.62, -h * 0.2))
	var i := int(t / SEG) % SCHAUEN.size()
	var lt := fmod(t, SEG)
	# Links die Stationen (nur Wörter), der Cursor gleitet von einer zur nächsten; unter der
	# aktuellen füllt sich ein feiner Strich im Akzent mit ihrer Zeit.
	var nav_w := w * 0.2
	var rh := 72.0
	var gap := 10.0
	var y0 := (h - rh * 4.0 - gap * 3.0) * 0.5
	var mv := eo(win(lt, 0.0, 0.25)) if not _calm else 1.0
	var vor := (i + SCHAUEN.size() - 1) % SCHAUEN.size()
	var cy := lerpf(y0 + vor * (rh + gap), y0 + i * (rh + gap), mv)
	UzTheme.draw_selection(self, Rect2(28, cy, nav_w - 28.0, rh))
	for k in SCHAUEN.size():
		var on := k == i
		var ry := y0 + k * (rh + gap)
		_txt(str(SCHAUEN[k]), Vector2(56, ry + 46), 26, ink if on else muted, "bold")
	# Rechts die Bühne; der neue Inhalt blendet ein und setzt sich, der alte geht.
	var st := Rect2(nav_w + 28.0, 26.0, w - nav_w - 56.0, h - 52.0)
	draw_style_box(UzTheme.flaeche(UzTheme.col("surface_hi"), UzTheme.r_panel(), 2), st)
	var a := 1.0 if _calm else eo(win(lt, 0.05, 0.45)) * (1.0 - eio(win(lt, SEG - 0.22, SEG)))
	var inner := st.grow(-24.0)
	match i:
		0: _schauen_musik(inner, lt, a)
		1: _schauen_video(inner, lt, a)
		2: _schauen_film(inner, lt, a)
		3: _schauen_live(inner, lt, a)


## Echte Einträge einer Station (Inhalt.schauen).
func _echt(art: String) -> Array:
	return _sch.get(art, []) as Array


## Bild eines echten Eintrags (null, solange es nicht geladen ist).
func _bild(e: Variant) -> Texture2D:
	return Inhalt.bild(str((e as Dictionary).key)) if e is Dictionary else null


## Musik: das Cover groß (das eigene Album, sonst ein eigenes Bild), Titel und Interpret. Eigene
## Musik: darunter läuft der Titel, daneben die nächsten Alben. Sonst laufen die Lyrics Zeile für
## Zeile, die aktuelle füllt sich Wort für Wort.
func _schauen_musik(r: Rect2, lt: float, a: float) -> void:
	var acc := UzTheme.col("accent")
	var ink := UzTheme.col("text")
	var muted := UzTheme.col("muted")
	var echt := _echt("musik")
	var cs := r.size.y * 0.86
	var cv := Rect2(r.position + Vector2(0, (r.size.y - cs) * 0.5), Vector2(cs, cs))
	_glow(cv.get_center(), cs * 0.9, Color(acc, 0.18 * a))
	Inhalt.schatten(self, cv, 10.0, 0.5 * a)
	var tex := _bild(echt[0]) if not echt.is_empty() else null
	if tex:
		Inhalt.bild_zeichnen(self, cv, tex, 10.0, a, 1.0 + 0.02 * lt / SEG, Vector2(0.5, 0.5))
	else:
		Inhalt.landschaft(self, cv, 10.0, 0.74, 1, _total, a, glow_tex())
	var x := cv.end.x + 40.0
	var tw := r.end.x - x - 140.0
	var titel := str(echt[0].titel) if tex else "Nachtfahrt"
	var zeile := str(echt[0].zeile) if tex else "Ruhiger Mix"
	_txt(titel, Vector2(x, r.position.y + 40.0), 32, Color(ink, a), "bold", tw, not tex)
	_txt(zeile, Vector2(x, r.position.y + 74.0), 19, Color(muted, a), "regular", tw, not tex)
	if tex:
		# Die eigene Musik: Fortschritt des Titels, darunter die nächsten Alben mit ihren Covern.
		var bar := Rect2(x, r.position.y + 100.0, minf(tw, 520.0), 4.0)
		var p := 0.2 + 0.25 * lt / SEG if not _calm else 0.3
		draw_rect(bar, Color(ink, 0.14 * a))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)), Color(acc, a))
		_txt("Als Nächstes", Vector2(x, r.position.y + r.size.y * 0.5), 17, Color(muted, a), "bold")
		var ks := minf(96.0, r.size.y * 0.3)
		for j in range(1, mini(echt.size(), 4)):
			var kr := Rect2(x + (j - 1) * (ks + 24.0), r.position.y + r.size.y * 0.5 + 18.0, ks, ks)
			var kt := _bild(echt[j])
			if kt:
				Inhalt.bild_zeichnen(self, kr, kt, 8.0, a * 0.95, 1.0, Vector2(0.5, 0.5))
			else:
				Inhalt.landschaft(self, kr, 8.0, fposmod(0.74 + j * 0.21, 1.0), j % 3, _total, a, glow_tex())
			_txt(str(echt[j].titel), Vector2(kr.position.x, kr.end.y + 24.0), 15, Color(ink, 0.85 * a), "medium", ks, false)
	else:
		# Lyrics: Jede Zeile 0,6 s, sie rücken weich nach oben.
		var pos := lt / 0.6 if not _calm else 1.4
		var base := r.position.y + r.size.y * 0.62
		var f := UzTheme.font("bold")
		for j in LYRICS.size():
			var d := float(j) - pos
			if d < -1.6 or d > 2.6:
				continue
			var y := base + d * 46.0
			var cur := j == int(pos)
			var fs := 30 if cur else 24
			var la := a * clampf(1.0 - absf(d) * 0.35, 0.15, 1.0)
			var text := tr(str(LYRICS[j]))
			if not cur:
				draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, 0.5 * la))
				continue
			# Die aktuelle Zeile füllt sich Zeichen für Zeichen im Akzent (wie Karaoke).
			var fill := (pos - floorf(pos)) * text.length() * 1.15
			var cx := x
			for ci in text.length():
				var chs := text[ci]
				var col := acc.lerp(ink, 0.25) if float(ci) < fill else Color(ink, 0.55)
				draw_char(f, Vector2(cx, y), chs, fs, Color(col, la))
				cx += f.get_char_size(chs.unicode_at(0), fs).x
	# Pegel rechts unten.
	for b in 7:
		var lv := 0.3 + 0.7 * absf(sin(_total * (3.1 + b * 0.7) + b)) if not _calm else 0.3 + 0.1 * b
		var bh := 8.0 + 34.0 * lv
		draw_rect(Rect2(r.end.x - 120.0 + b * 15.0, r.end.y - 10.0 - bh, 9.0, bh), Color(acc, a))


## Videos: sechs Vorschaubilder (zuletzt gesehen, sonst eigene) mit ihrer Länge, der Cursor wandert,
## eines öffnet sich zum Player mit seinem Titel.
func _schauen_video(r: Rect2, lt: float, a: float) -> void:
	var acc := UzTheme.col("accent")
	var echt := _echt("videos")
	var g := 16.0
	var tw := (r.size.x - g * 2.0) / 3.0
	var th := minf(tw * 9.0 / 16.0, (r.size.y - g) / 2.0)
	var auf := eio(win(lt, 1.2, 1.7)) if not _calm else 0.0
	var wahl := 1 if lt > 0.6 or _calm else 0
	var player := Rect2(r.position, Vector2(r.size.x, minf(r.size.y, r.size.x * 9.0 / 16.0)))
	# Die gewählte Kachel zuletzt: Sie wächst über die anderen zum Player.
	var reihe: Array = range(6).filter(func(x: int) -> bool: return x != wahl)
	reihe.append(wahl)
	for k: int in reihe:
		var tr_ := Rect2(r.position + Vector2((k % 3) * (tw + g), int(k / 3.0) * (th + g)), Vector2(tw, th))
		var on := k == wahl
		var rr := tr_
		if on:
			rr = Rect2(tr_.position.lerp(player.position, auf), tr_.size.lerp(player.size, auf))
		var ka := a if on else a * (1.0 - auf)
		if ka <= 0.01:
			continue
		var tex := _bild(echt[k]) if k < echt.size() else null
		var eig: Array = EIGEN_VIDEOS[k]
		if tex:
			Inhalt.bild_zeichnen(self, rr, tex, 8.0, ka, 1.0, Vector2(0.5, 0.5))
		else:
			Inhalt.landschaft(self, rr, 8.0, float(eig[0]), int(eig[1]), _total * 0.6 + k, ka, glow_tex())
		var dauer := str(eig[2])
		if tex:
			var s_ := int(echt[k].dauer)
			dauer = "%d:%02d" % [floori(s_ / 60.0), s_ % 60] if s_ > 0 else ""
		if dauer != "" and (not on or auf < 0.3):
			var dw := _txt_w(dauer, 15, "bold") + 16.0
			var dr := Rect2(tr_.end.x - dw - 10.0, tr_.end.y - 34.0, dw, 24.0) if not on else Rect2(rr.end.x - dw - 10.0, rr.end.y - 34.0, dw, 24.0)
			draw_style_box(UzTheme.box(Color(0, 0, 0, 0.62 * ka), 6), dr)
			_txt(dauer, dr.position + Vector2(8, 18), 15, Color(1, 1, 1, ka), "bold", -1.0, false)
		if on and auf < 0.5:
			UzTheme.draw_tile_focus(self, rr, 8, a)
	if auf > 0.0:
		# Titel, Taste und Fortschritt wachsen mit dem Bild (nie über den anderen Kacheln).
		var von := Rect2(r.position + Vector2((wahl % 3) * (tw + g), int(wahl / 3.0) * (th + g)), Vector2(tw, th))
		player = Rect2(von.position.lerp(player.position, auf), von.size.lerp(player.size, auf))
		var pc := player.get_center()
		Inhalt.schleier(self, player, 8.0, 0.55, 0.75 * a * auf)
		var echt_bild := wahl < echt.size() and _bild(echt[wahl]) != null
		var titel := str(echt[wahl].titel) if echt_bild else "Ein Abend am Meer"
		_txt(titel, Vector2(player.position.x + 24.0, player.end.y - 44.0), 24, Color(1, 1, 1, a * auf * auf), "bold", player.size.x - 48.0, not echt_bild)
		draw_circle(pc, 40.0, Color(0, 0, 0, 0.4 * a * auf), true, -1.0, true)
		_ico("play", Rect2(pc - Vector2(20, 20), Vector2(40, 40)), Color(1, 1, 1, a * auf))
		var prog := 0.18 + 0.4 * win(lt, 1.7, SEG)
		var bar := Rect2(player.position.x + 24.0, player.end.y - 22.0, player.size.x - 48.0, 4.0)
		draw_rect(bar, Color(1, 1, 1, 0.25 * a * auf))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * prog, 4.0)), Color(acc, a * auf))


## Filme: ein großes Bild (langsam näher) mit Titel, darunter die Reihe mit „Weiterschauen“ – die
## eigenen Filme und Serien, sonst eigene Bilder.
func _schauen_film(r: Rect2, lt: float, a: float) -> void:
	var acc := UzTheme.col("accent")
	var ink := UzTheme.col("text")
	var echt := _echt("filme")
	var zoom := 1.0 + 0.05 * lt / SEG
	var bd := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.62))
	var bg := Inhalt.bild("s:" + str(_sch.get("bild", ""))) if str(_sch.get("bild", "")) != "" else null
	var erst := _bild(echt[0]) if not echt.is_empty() else null
	if bg:
		Inhalt.bild_zeichnen(self, bd, bg, 8.0, a, zoom, Vector2(0.5, 0.3))
	elif erst:
		Inhalt.bild_zeichnen(self, bd, erst, 8.0, a, zoom, Vector2(0.5, 0.25))
	else:
		Inhalt.landschaft(self, bd, 8.0, 0.98, 0, _total * 0.4, a, glow_tex())
	Inhalt.schleier(self, bd, 8.0, 0.35, 0.7 * a)
	var titel := str(echt[0].titel) if erst else "Nordlicht"
	var zeile := ""
	if erst:
		zeile = str(echt[0].zeile)
		if float(echt[0].anteil) > 0.0:
			zeile = tr("Weiterschauen") + (" · " + zeile if zeile != "" else "")
	else:
		zeile = tr("2 Std. 4 Min. · Abenteuer")
	_txt(titel, Vector2(bd.position.x + 26.0, bd.end.y - 54.0), 34, Color(Color.WHITE, a), "bold", bd.size.x - 52.0, not erst)
	_txt(zeile, Vector2(bd.position.x + 26.0, bd.end.y - 24.0), 17, Color(1, 1, 1, 0.78 * a), "medium", bd.size.x - 52.0, false)
	var pw := (r.size.x - 4.0 * 14.0) / 5.0
	var ph := r.end.y - bd.end.y - 14.0
	for k in 5:
		var pr := Rect2(r.position.x + k * (pw + 14.0), bd.end.y + 14.0, pw, ph)
		var pt := _bild(echt[k]) if k < echt.size() else null
		if pt:
			Inhalt.bild_zeichnen(self, pr, pt, 8.0, a, 1.0, Vector2(0.5, 0.3))
		else:
			var eig: Array = EIGEN_FILME[k]
			Inhalt.landschaft(self, pr, 8.0, float(eig[0]), int(eig[1]), _total * 0.3 + k * 3.0, a, glow_tex())
		if k == 0:
			UzTheme.draw_tile_focus(self, pr, 8, a)
			var anteil := float(echt[0].anteil) if pt and float(echt[0].anteil) > 0.0 else 0.62
			Inhalt.schleier(self, pr, 8.0, 0.4, 0.8 * a)
			draw_rect(Rect2(pr.position.x + 10.0, pr.end.y - 10.0, (pr.size.x - 20.0), 3.0), Color(1, 1, 1, 0.3 * a))
			draw_rect(Rect2(pr.position.x + 10.0, pr.end.y - 10.0, (pr.size.x - 20.0) * anteil, 3.0), Color(acc, a))
			_txt("Weiterschauen", Vector2(pr.position.x + 10.0, pr.end.y - 18.0), 14, Color(ink, a), "bold", pr.size.x - 20.0)


## Live: ein Stream (ein gefolgter Kanal, der gerade sendet, sonst ein eigenes Bild) mit LIVE und
## Zuschauerzahl; rechts der Chat bzw. die anderen Kanäle, die gerade live sind.
func _schauen_live(r: Rect2, lt: float, a: float) -> void:
	var ink := UzTheme.col("text")
	var muted := UzTheme.col("muted")
	var echt := _echt("live")
	var fw := r.size.x * 0.66
	var fr := Rect2(r.position, Vector2(fw, minf(r.size.y, fw * 9.0 / 16.0)))
	var tex := _bild(echt[0]) if not echt.is_empty() else null
	if tex:
		Inhalt.bild_zeichnen(self, fr, tex, 8.0, a, 1.0 + 0.03 * lt / SEG, Vector2(0.5, 0.5))
	else:
		Inhalt.landschaft(self, fr, 8.0, 0.66, 1, _total * 2.0, a, glow_tex())
	Inhalt.schleier(self, fr, 8.0, 0.6, 0.7 * a)
	var lp := Rect2(fr.position + Vector2(18, 18), Vector2(74, 30))
	draw_style_box(UzTheme.box(Color(UzTheme.col("danger"), a), 6), lp)
	_txt_c("LIVE", lp.get_center() + Vector2(0, 7), 17, Color(1, 1, 1, a), "bold")
	var zahl := int(echt[0].zahl) if tex else (int(12340 + lt * 37.0) if not _calm else 12408)
	if zahl > 0:
		_txt(tr("%s Zuschauer") % _tausend(zahl), Vector2(lp.end.x + 14.0, lp.position.y + 22.0), 17, Color(1, 1, 1, 0.9 * a), "medium", -1.0, false)
	var kanal := str(echt[0].titel) if tex else "Nachtflug"
	var titel := str(echt[0].zeile) if tex else "Bis zum letzten Level"
	_txt(kanal, Vector2(fr.position.x + 20.0, fr.end.y - 46.0), 22, Color(1, 1, 1, a), "bold", fr.size.x - 40.0, not tex)
	_txt(titel, Vector2(fr.position.x + 20.0, fr.end.y - 20.0), 16, Color(1, 1, 1, 0.78 * a), "medium", fr.size.x - 40.0, not tex)
	var cx := fr.end.x + 20.0
	var cw := r.end.x - cx
	if tex and echt.size() > 1:
		# Die anderen Kanäle, die gerade senden.
		for j in range(1, mini(echt.size(), 5)):
			var ein := eo(win(lt - (j - 1) * 0.2, 0.0, 0.3)) if not _calm else 1.0
			var row := Rect2(cx + (1.0 - ein) * 40.0, r.position.y + (j - 1) * 72.0, cw, 62.0)
			draw_style_box(UzTheme.flaeche(Color(UzTheme.col("surface"), 0.9 * a * ein), UzTheme.r_panel(), 1), row)
			var bt := _bild(echt[j])
			var br := Rect2(row.position + Vector2(8, 8), Vector2(82, 46))
			if bt:
				Inhalt.bild_zeichnen(self, br, bt, 6.0, a * ein, 1.0, Vector2(0.5, 0.5))
			_txt(str(echt[j].titel), row.position + Vector2(102, 27), 16, Color(ink, a * ein), "bold", cw - 114.0, false)
			_txt(tr("%s Zuschauer") % _tausend(int(echt[j].zahl)), row.position + Vector2(102, 49), 14, Color(muted, a * ein), "medium", cw - 114.0, false)
		return
	# Chat: alle 0,45 s eine neue Zeile, sie gleitet von rechts herein.
	var n := mini(CHAT.size(), int(lt / 0.45) + 1) if not _calm else 4
	for j in n:
		var ein := eo(win(lt - j * 0.45, 0.0, 0.25)) if not _calm else 1.0
		var row := Rect2(cx + (1.0 - ein) * 40.0, r.position.y + j * 62.0, cw, 54.0)
		draw_style_box(UzTheme.flaeche(Color(UzTheme.col("surface"), 0.9 * a * ein), UzTheme.r_panel(), 1), row)
		var msg: Array = CHAT[j]
		_txt(str(msg[0]), row.position + Vector2(14, 22), 15, Color(UzTheme.col("accent"), a * ein), "bold")
		_txt(str(msg[1]), row.position + Vector2(14, 44), 16, Color(ink, a * ein), "regular", cw - 28.0)


static func _tausend(n: int) -> String:
	var s_ := str(n)
	return s_.substr(0, s_.length() - 3) + "." + s_.substr(s_.length() - 3) if n >= 1000 else s_

