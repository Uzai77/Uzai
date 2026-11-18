extends Control
## Tastenhinweise im Zimmer, ins Bild gelegt statt als Leiste: eine ruhige Tastenzeile unten rechts
## im selben Stil wie überall (Glyphe + Wort, einzeilig, B zuletzt) – zuerst die Aktionstasten
## (A, Y, X), dahinter leiser und kleiner Schulter-, Trigger- und Menütaste, am Ende B. Früher eine
## Raute (die Tasten dort, wo sie am Controller liegen): verstreut über die Ecke, mit Wörtern in vier
## Richtungen, las sie sich schlechter als eine Zeile und sah anders aus als jede andere Seite.
## Tasten, die gerade nichts tun, fehlen. Mit Maus und Finger ist jeder Hinweis zugleich die Taste
## (wie die Hinweisleiste).
##
## Hinweise kommen im Format der Hinweisleiste: [[taste, text], …]; ein leerer Text gehört zum
## nächsten Hinweis („LB“ + „RB Drehen“ → „LB RB Drehen“). leise(true) blendet alles aus, solange
## man läuft oder die Kamera führt – stehst du still, kommen die Hinweise wieder.

const U := preload("res://src/ui/u.gd")
const Glyph := preload("res://src/ui/components/glyph.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")

const PX := 27                  ## Aktionstasten (wie die Hinweisleiste)
const PX_KLEIN := 24            ## Schulter-, Trigger- und Menütasten
const UNTEN := 56.0             ## Mitte der Zeile über dem unteren Rand
const ABSTAND := 28.0           ## zwischen zwei Hinweisen (wie die Hinweisleiste)
const FACE := ["a", "b", "x", "y"]

var _zeile: Array = []          ## [{ tasten, text, klein, a }] in der Reihenfolge der Zeile
var _flaechen: Array = []       ## [[Rect2, Taste]] für Maus und Finger
var _sicht := 1.0
var _sicht_ziel := 1.0
var _letzte := ""
var unten := UNTEN              ## Lage der Zeile über dem unteren Rand (im Bauen über der Kategorienleiste)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	U.full_rect(self)
	Nav.device_changed.connect(func(_k: String) -> void: queue_redraw())


## Neue Hinweise: Was bleibt, steht still; ein neuer oder geänderter blendet ein. Was geht, ist sofort weg –
## die Zeile steht rechtsbündig, ein Ausblenden am Platz ließe die anderen erst danach nachrücken.
func setzen(hinweise: Array) -> void:
	var sig := str(hinweise)
	if sig == _letzte:
		return
	_letzte = sig
	var alt := {}
	for e in _zeile:
		alt[",".join(PackedStringArray(e.tasten))] = e
	var neu: Array = []
	for h in reihe(hinweise):
		var k := ",".join(PackedStringArray(h.tasten))
		var e: Dictionary = alt.get(k, { "tasten": h.tasten, "text": "", "klein": h.klein, "a": 0.0 })
		alt.erase(k)
		if str(e.text) != str(h.text):
			e.text = str(h.text)
			e.a = minf(float(e.a), 0.35)
		neu.append(e)
	_zeile = neu
	set_process(true)


## Leise (beim Laufen, beim Führen der Kamera): ausblenden; sonst wieder zeigen.
func leise(an: bool) -> void:
	_sicht_ziel = 0.0 if an else 1.0
	if not is_equal_approx(_sicht, _sicht_ziel):
		set_process(true)


## Hinweise sortieren: Aktionstasten (jede einmal) und der Rest (Paare wie „LB RB Drehen“ zusammen).
static func ordnen(hinweise: Array) -> Dictionary:
	var kreuz := {}
	var rest: Array = []
	for h in hinweise:
		var c := str(h[0])
		if c in FACE and str(h[1]) != "":
			if not kreuz.has(c):
				kreuz[c] = str(h[1])
		else:
			rest.append(h)
	var zeile: Array = []
	for m in HintBar.merge(rest):
		if not zeile.any(func(e: Array) -> bool: return e[0] == m[0]):
			zeile.append(m)
	return { "kreuz": kreuz, "zeile": zeile }


## Die Tastenzeile: A, Y, X, dann leiser die übrigen Tasten, B zuletzt. [{ tasten, text, klein }]
static func reihe(hinweise: Array) -> Array:
	var o := ordnen(hinweise)
	var kreuz: Dictionary = o.kreuz
	var out: Array = []
	for c in ["a", "y", "x"]:
		if kreuz.has(c):
			out.append({ "tasten": [c], "text": str(kreuz[c]), "klein": false })
	for m in o.zeile:
		out.append({ "tasten": m[0], "text": str(m[1]), "klein": true })
	if kreuz.has("b"):
		out.append({ "tasten": ["b"], "text": str(kreuz.b), "klein": false })
	return out


func _process(dt: float) -> void:
	var fertig := true
	var k := 1.0 - exp(-dt * 12.0)
	for e in _zeile:
		e.a = move_toward(float(e.a), 1.0, dt / U.T_BASE)
		if float(e.a) < 1.0:
			fertig = false
	_sicht = lerpf(_sicht, _sicht_ziel, k * 0.7) if absf(_sicht - _sicht_ziel) > 0.01 else _sicht_ziel
	if not is_equal_approx(_sicht, _sicht_ziel):
		fertig = false
	queue_redraw()
	if fertig:
		set_process(false)


# --- Zeichnen -----------------------------------------------------------------------------------

## Rechtsbündig von rechts nach links: B steht ganz rechts, davor der Rest.
func _draw() -> void:
	_flaechen.clear()
	if _sicht <= 0.01:
		return
	var gset := Nav.glyph_set()
	var f := UzTheme.font("medium")
	var x := size.x - UzTheme.GUTTER
	var y := size.y - unten
	for i in range(_zeile.size() - 1, -1, -1):
		var e: Dictionary = _zeile[i]
		var klein := bool(e.klein)
		var px := PX_KLEIN if klein else PX
		var fs := UzTheme.size("xs" if klein else "s")
		var text := tr(str(e.text))
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tasten: Array = e.tasten
		var gw := 0.0
		for t in tasten:
			gw += Glyph.size_for(str(t), px, gset).x + 4.0
		var breite := gw + 6.0 + tw
		x -= breite
		var gx := x
		for t in tasten:
			var gs := Glyph.size_for(str(t), px, gset)
			Glyph.paint(self, str(t), px, Rect2(Vector2(gx, y - gs.y * 0.5), gs), gset, 0.8 if klein else 1.0, float(e.a) * _sicht)
			_flaechen.append([Rect2(Vector2(gx - 3.0, y - 20.0), Vector2(gs.x + 6.0 + (tw + 10.0 if t == tasten.back() else 0.0), 40.0)), str(t)])
			gx += gs.x + 4.0
		_wort(f, Vector2(gx + 2.0, y + fs * 0.36), text, fs, float(e.a) * (0.86 if klein else 1.0), tw)
		x -= ABSTAND


## Ein Wort über dem Zimmer: Tinte mit weichem dunklem Schatten, damit es auf hellen Wänden trägt.
func _wort(f: Font, p: Vector2, text: String, fs: int, a: float, breite: float) -> void:
	var aa := a * _sicht
	draw_string(f, p + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, breite + 1.0, fs, Color(0, 0, 0, 0.42 * aa))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, breite + 1.0, fs, Color(UzTheme.col("text"), 0.92 * aa))


# --- Maus und Finger ----------------------------------------------------------------------------

func _has_point(p: Vector2) -> bool:
	if _sicht < 0.5:
		return false
	for fl in _flaechen:
		if (fl[0] as Rect2).has_point(p):
			return true
	return false


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for fl in _flaechen:
			if (fl[0] as Rect2).has_point((e as InputEventMouseButton).position):
				accept_event()
				HintBar.tippen(str(fl[1]))
				return
