extends HBoxContainer
## Reiterleiste mit gleitenden Anzeigern (Bereiche oben, Unterbereiche darunter).
## - Oben („tab“) zeigt ein Punkt im Akzent (Ø PUNKT) den Bereich, mittig unter dem gewählten Wort
##   bzw. Symbol – keine Linie. Unter den Unterbereichen („chip“) ein Strich so breit wie das Wort.
##   Beide gleiten beim Wechsel hinüber: die Vorderkante eilt voraus, die Hinterkante folgt – wie
##   ein Tropfen, nichts springt.
## - Steht der Cursor auf der Leiste, gleitet die Cursor-Pille (UzTheme.draw_selection) unter den
##   Wörtern mit, und die Schrift wird genau so weit dunkel, wie die Pille unter ihr liegt; der Punkt
##   weicht ihr und kommt zurück, sobald der Cursor die Leiste verlässt.
## Die Reiter (nav_item.gd) zeichnen in dieser Leiste nichts selbst. Ziele werden in jedem Bild
## neu gelesen: verschiebt sich die Leiste (Reiter klappt auf), folgen die Anzeiger.

const U := preload("res://src/ui/u.gd")

## Durchmesser des Punkts unter dem Bereich.
const PUNKT := 7.0

var style := "tab"            ## "tab": Punkt mittig unter dem Bereich; "chip": Strich so breit wie das Wort

var _pill := Rect2()          ## aktuelle Lage der Pille (eigene Koordinaten)
var _pill_from := Rect2()
var _pill_item: Control
var _pill_k := 1.0            ## Fortschritt der Bewegung 0…1
var _pill_on := false
var _pill_vis := 0.0          ## 0 = unsichtbar, 1 = ganz da
var _line := Rect2()
var _line_from := Rect2()
var _line_item: Control
var _line_k := 1.0
var _press := 0.0
var _snap := true             ## nächstes Platzieren ohne Bewegung (Leiste neu gebaut)
var _hover_item: Control      ## Reiter unter der Maus (schweben.gd → nav_item.zeiger_schweben)
var _hover_on := false
var _hover_vis := 0.0         ## 0…1, blendet weich ein und aus


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)


func _ready() -> void:
	sort_children.connect(_on_sorted)
	set_process(false)


## Nach dem Neubau der Reiter: Anzeiger beim nächsten Ordnen ohne Bewegung setzen. Die Pille
## verschwindet sofort (ihr Reiter ist weg); bekommt ein neuer Reiter den Fokus, wächst sie dort neu auf.
func snap() -> void:
	_snap = true
	_pill_item = null
	_pill_on = false
	_pill_vis = 0.0
	_line_item = null
	queue_redraw()


# --- Meldungen der Reiter --------------------------------------------------------------

func strip_focus(item: Control, on: bool) -> void:
	if on:
		var visible_now := _pill_vis > 0.05 and _pill.size.x > 0.0
		_pill_item = item
		_pill_on = true
		if visible_now and not _snap:
			_pill_from = _pill
			_pill_k = 0.0
		else:
			_pill_k = 1.0
			_pill = _item_rect(item)
	elif item == _pill_item:
		_pill_on = false
	_wake()


func strip_selected(item: Control, initial := false) -> void:
	if item == _line_item and not initial:
		return
	var had := is_instance_valid(_line_item) and _line.size.x > 0.0
	_line_item = item
	if had and not initial and not _snap:
		_line_from = _line
		_line_k = 0.0
	else:
		_line_k = 1.0
	_wake()


## Kein Reiter gewählt (Profil über das Bild oben rechts): der Strich verschwindet.
func clear_line() -> void:
	_line_item = null
	_line = Rect2()
	_line_k = 1.0
	_wake()


## Mouse over a tab: a soft glow beneath it - glass with accent light like the tiles, no pill (that belongs to the
## cursor), so the tabs at the top react to the mouse as well. Nothing gets selected by this.
func strip_hover(item: Control, on: bool) -> void:
	if on:
		if item != _hover_item:
			_hover_vis = 0.0
		_hover_item = item
		_hover_on = true
	elif item == _hover_item:
		_hover_on = false
	_wake()


func strip_press(_item: Control, _x := true) -> void:
	_press = 1.0
	_wake()


# --- Bewegung ---------------------------------------------------------------------------

func _wake() -> void:
	set_process(true)
	_place()
	queue_redraw()


func _on_sorted() -> void:
	if _snap and get_child_count() > 0:
		_snap = false
		_line_k = 1.0
		_pill_k = 1.0
		if not is_instance_valid(_line_item) or not bool(_line_item.get_meta("uz_selected", false)):
			_line_item = _find_selected()
	_place()
	queue_redraw()


func _process(dt: float) -> void:
	var busy := false
	var vt := 1.0 if _pill_on and is_instance_valid(_pill_item) else 0.0
	if _pill_vis != vt:
		var dur := U.FOCUS_IN * 1.4 if vt > 0.5 else U.FOCUS_OUT
		_pill_vis = move_toward(_pill_vis, vt, dt / dur)
		busy = true
	if _pill_k < 1.0:
		_pill_k = minf(1.0, _pill_k + dt / U.T_FOCUS)
		busy = true
	if _line_k < 1.0:
		_line_k = minf(1.0, _line_k + dt / U.T_MOVE)
		busy = true
	if _press > 0.0:
		_press = maxf(0.0, _press - dt / (U.T_PRESS + U.T_BASE))
		busy = true
	var ht := 1.0 if _hover_on and is_instance_valid(_hover_item) else 0.0
	if _hover_vis != ht:
		_hover_vis = move_toward(_hover_vis, ht, dt / (U.FOCUS_IN if ht > 0.5 else U.FOCUS_OUT))
		busy = true
	_place()
	queue_redraw()
	if not busy:
		set_process(false)


func _find_selected() -> Control:
	for ch in get_children():
		if ch is Control and ch.has_method("set_ink") and bool(ch.get_meta("uz_selected", false)):
			return ch
	return null


func _item_rect(item: Control) -> Rect2:
	if not is_instance_valid(item):
		return Rect2()
	var sz := item.size if item.size.x > 0.0 else item.custom_minimum_size
	return Rect2(item.position, sz)


func _line_rect(item: Control) -> Rect2:
	if not is_instance_valid(item) or not item.has_method("ink_rect"):
		return Rect2()
	var ir: Rect2 = item.call("ink_rect")
	ir.position += item.position
	var h := size.y if size.y > 0.0 else item.size.y
	if style == "tab":
		# Bereich: der Punkt mittig unter dem Wort bzw. Symbol, unten bündig mit dem alten Strich.
		return Rect2(roundf(ir.get_center().x - PUNKT * 0.5), h - PUNKT - 1.0, PUNKT, PUNKT)
	return Rect2(ir.position.x, h - 3.0, ir.size.x, 2.5)


## Bewegung zwischen zwei Lagen: die Vorderkante eilt voraus, die Hinterkante folgt.
static func stretch(from: Rect2, to: Rect2, k: float, lag := 0.14) -> Rect2:
	if k >= 1.0 or from.size.x <= 0.0:
		return to
	var lead := 1.0 - pow(1.0 - k, 3.0)
	var tk := clampf((k - lag) / (1.0 - lag), 0.0, 1.0)
	var trail := 1.0 - pow(1.0 - tk, 3.0)
	var right := to.get_center().x >= from.get_center().x
	var l := lerpf(from.position.x, to.position.x, trail if right else lead)
	var r := lerpf(from.end.x, to.end.x, lead if right else trail)
	var y := lerpf(from.position.y, to.position.y, lead)
	var h := lerpf(from.size.y, to.size.y, lead)
	return Rect2(l, y, maxf(r - l, 0.0), h)


func _place() -> void:
	if not is_instance_valid(_line_item):
		_line_item = _find_selected()
	var lt := _line_rect(_line_item)
	_line = stretch(_line_from, lt, _line_k, 0.26) if _line_k < 1.0 else lt
	if is_instance_valid(_pill_item):
		var pt := _item_rect(_pill_item)
		_pill = stretch(_pill_from, pt, _pill_k, 0.12) if _pill_k < 1.0 else pt
	# Schrift: dunkel, soweit die Pille unter ihr liegt.
	var vis := _ease(_pill_vis)
	for ch in get_children():
		if ch is Control and ch.has_method("set_ink"):
			var it := ch as Control
			var ir: Rect2 = it.call("ink_rect")
			ir.position += it.position
			var cover := 0.0
			if vis > 0.0 and ir.size.x > 0.0:
				cover = clampf((minf(_pill.end.x, ir.end.x) - maxf(_pill.position.x, ir.position.x)) / ir.size.x, 0.0, 1.0)
			it.call("set_ink", cover * vis)


static func _ease(v: float) -> float:
	return v * v * (3.0 - 2.0 * v)


func _draw() -> void:
	var vis := _ease(_pill_vis)
	# Schein unter dem Reiter unter der Maus – nicht unter dem, auf dem die Pille schon liegt.
	var hv := _ease(_hover_vis)
	if hv > 0.01 and is_instance_valid(_hover_item) and not (_hover_item == _pill_item and vis > 0.5):
		var hr := _item_rect(_hover_item).grow_individual(-2.0, -1.0, -2.0, -1.0)
		UzTheme.draw_hover(self, hr, 999, hv)
	if is_instance_valid(_line_item) and _line.size.x > 0.0 and vis < 0.99:
		var lc := Color(UzTheme.col("accent"), 1.0 - vis)
		if style == "tab":
			# Der Punkt: rund, unterwegs ein kurzer Tropfen (stretch) – eigene Box, damit er in
			# jedem Theme rund bleibt (keine Rundungsgrenze wie bei Flächen).
			var dot := StyleBoxFlat.new()
			dot.bg_color = lc
			dot.set_corner_radius_all(int(ceilf(_line.size.y * 0.5)))
			dot.anti_aliasing = true
			draw_style_box(dot, _line)
		else:
			draw_style_box(UzTheme.box(lc, int(ceilf(_line.size.y * 0.5))), _line)
	if vis > 0.01 and _pill.size.x > 0.0:
		var k := (1.0 - vis) * 6.0 + sin(PI * clampf(1.0 - _press, 0.0, 1.0)) * 2.0
		var r := _pill.grow_individual(-k, -k * 0.5, -k, -k * 0.5)
		UzTheme.draw_selection(self, r, 999, vis, 0.9)
