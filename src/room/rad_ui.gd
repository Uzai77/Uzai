extends Control
## Rad-Menü im Zimmer (Punkt 131): ein ruhiger Kreis mit bis zu zwölf Einträgen, gewählt mit dem
## Steuerkreuz (links/rechts reihum) oder dem linken Stick (Richtung zeigt auf den Eintrag). Jeder
## Eintrag wird beim Wählen sofort vorgeführt (vorschau), A übernimmt, B stellt den alten Stand
## wieder her. Gebraucht für die Licht-Stimmungen.
##
## Einträge: [[id, Name, Farbe (Color), Name vom Nutzer (bool, freiwillig: nie übersetzen)]]

signal gewaehlt(id: String)
signal abgebrochen

const U := preload("res://src/ui/u.gd")
const Glyph := preload("res://src/ui/components/glyph.gd")
const RADIUS := 250.0

var titel := ""
var eintraege: Array = []
var vorschau: Callable          ## (id) Vorschau im Zimmer
var _sel := 0
var _an := 0.0
var _dreh := 0.0               ## weich nachlaufende Markierung (Index als Kommazahl)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	visible = false
	Nav.device_changed.connect(func(_k: String) -> void: queue_redraw())


func oeffnen(t: String, liste: Array, aktuell: String) -> void:
	titel = t
	eintraege = liste
	_sel = 0
	for i in liste.size():
		if str(liste[i][0]) == aktuell:
			_sel = i
	_dreh = float(_sel)
	visible = true
	var tw := U.ankommen(self, U.T_ORT, "uz_rad")
	tw.tween_method(func(v: float) -> void:
		_an = v
		queue_redraw(), _an, 1.0, U.T_ORT)


func schliessen() -> void:
	var tw := U.tw(self, "uz_rad", Tween.TRANS_CUBIC, Tween.EASE_IN)
	tw.tween_method(func(v: float) -> void:
		_an = v
		queue_redraw(), _an, 0.0, U.T_FAST)
	tw.tween_callback(func() -> void: visible = false)


func ist_offen() -> bool:
	return visible and _an > 0.5


func gewaehlte_id() -> String:
	return str(eintraege[_sel][0]) if _sel < eintraege.size() else ""


func schritt(cmd: String) -> void:
	if eintraege.is_empty():
		return
	var n := _sel
	match cmd:
		"left", "up": n = posmod(_sel - 1, eintraege.size())
		"right", "down": n = posmod(_sel + 1, eintraege.size())
	_waehlen(n)


## Linker Stick: der Eintrag, in dessen Richtung er zeigt.
func stick(v: Vector2) -> void:
	if v.length() < 0.55 or eintraege.is_empty():
		return
	var a := fposmod(atan2(v.x, -v.y), TAU)
	var n := int(round(a / TAU * eintraege.size())) % eintraege.size()
	if n != _sel:
		_waehlen(n)


func _waehlen(n: int) -> void:
	if n == _sel:
		return
	# Kürzester Weg um den Kreis für die nachlaufende Markierung.
	var ziel := float(n)
	var k := float(eintraege.size())
	while ziel - _dreh > k * 0.5:
		ziel -= k
	while _dreh - ziel > k * 0.5:
		ziel += k
	_sel = n
	Sfx.play("move")
	var tw := U.tw(self, "uz_rad_dreh", Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void:
		_dreh = v
		queue_redraw(), _dreh, ziel, U.T_FOCUS)
	if vorschau.is_valid():
		vorschau.call(gewaehlte_id())


func taste(cmd: String) -> bool:
	match cmd:
		"a":
			Sfx.play("select")
			gewaehlt.emit(gewaehlte_id())
			schliessen()
		"b", "lt":
			Sfx.play("back")
			abgebrochen.emit()
			schliessen()
	return true


func _name(i: int) -> String:
	var e: Array = eintraege[i]
	return str(e[1]) if e.size() > 3 and bool(e[3]) else tr(str(e[1]))


func _draw() -> void:
	if _an <= 0.01 or eintraege.is_empty():
		return
	var m := size * 0.5
	var k := clampf(_an, 0.0, 1.2)
	var r := RADIUS * (0.86 + 0.14 * k)
	var a := clampf(_an, 0.0, 1.0)
	# Leiser Schleier, dann die Scheibe.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.32 * a))
	draw_circle(m, r + 34.0, Color(UzTheme.col("surface"), 0.9 * a))
	draw_arc(m, r + 34.0, 0, TAU, 96, Color(1, 1, 1, 0.06 * a), 2.0, true)
	var n := eintraege.size()
	var f := UzTheme.font("ui_bold")
	# Markierung: weicher goldener Bogen hinter dem gewählten Eintrag.
	var mw := _dreh / n * TAU - PI * 0.5
	var breite := TAU / n
	draw_arc(m, r - 4.0, mw - breite * 0.42, mw + breite * 0.42, 32, Color(UzTheme.col("accent"), 0.95 * a), 10.0, true)
	for i in n:
		var w := float(i) / n * TAU - PI * 0.5
		var p := m + Vector2(cos(w), sin(w)) * (r - 64.0)
		var c: Color = eintraege[i][2]
		var an := i == _sel
		draw_circle(p, (30.0 if an else 22.0) * k, Color(0, 0, 0, 0.3 * a))
		draw_circle(p, (27.0 if an else 19.0) * k, Color(c, a))
		if an:
			draw_arc(p, 31.0 * k, 0, TAU, 40, Color(UzTheme.col("focus"), a), 3.0, true)
		var t := _name(i)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("xs")).x
		var lp := p + Vector2(-tw * 0.5, 50.0 * k)
		draw_string(f, lp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("xs"), Color(UzTheme.col("text") if an else UzTheme.col("muted"), a))
	# Mitte: Titel und Name des gewählten Eintrags.
	var tt := tr(titel)
	var tw2 := f.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("xs")).x
	draw_string(f, m + Vector2(-tw2 * 0.5, -18), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("xs"), Color(UzTheme.col("accent_ink"), a))
	var name_ := _name(_sel)
	var fd := UzTheme.display("bold")
	var nw := fd.get_string_size(name_, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("l")).x
	draw_string(fd, m + Vector2(-nw * 0.5, 22), name_, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("l"), Color(UzTheme.col("text"), a))
	# Tasten in den Zeichen des Geräts (früher feste Buchstaben „A“ und „B“ – am PlayStation-Controller
	# und an der Tastatur stimmten sie nicht).
	var gset := Nav.glyph_set()
	var fr := UzTheme.font("regular")
	var fx := UzTheme.size("xs")
	var teile: Array = []
	var gesamt := 0.0
	for e: Array in [["a", "Übernehmen"], ["b", "Zurück"]]:
		var gs := Glyph.size_for(str(e[0]), 20, gset)
		var wort := tr(str(e[1]))
		var ww := fr.get_string_size(wort, HORIZONTAL_ALIGNMENT_LEFT, -1, fx).x
		teile.append([str(e[0]), gs, wort, ww])
		gesamt += gs.x + 7.0 + ww
	gesamt += 20.0 * (teile.size() - 1)
	var hx := m.x - gesamt * 0.5
	for e: Array in teile:
		var gs: Vector2 = e[1]
		Glyph.paint(self, str(e[0]), 20, Rect2(Vector2(hx, m.y + 47.0 - gs.y * 0.5), gs), gset, 0.75, a)
		hx += gs.x + 7.0
		draw_string(fr, Vector2(hx, m.y + 52.0), str(e[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, fx, Color(UzTheme.col("faint"), a))
		hx += float(e[3]) + 20.0
