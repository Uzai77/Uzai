extends Control
## Schnellaktion im Guide als große Kachel (wie Xbox-Guide und PS5-Kontrollzentrum): Symbol oben,
## Wort unten, rechts unten der Zustand („An“, „Aus“, ein Tastenkürzel). Gewählt: helle Fläche,
## Schrift dunkel, die Kachel hebt sich ein Stück. Ersetzt die kleinen Textzeilen im Raster.
## Beim Anpassen des Schnellmenüs (guide_quick.gd): gegriffen hebt sie sich weiter ab, mit Ring
## und Schatten; ausgeblendet steht sie blass mit durchgestrichenem Auge; gedimmt ist sie gerade
## nicht da. Schmal: nur das Symbol (Anpassen, Hinzufügen), leer: nur der Umriss.

signal activated

const U := preload("res://src/ui/u.gd")
const SIZE := Vector2(200, 156)
const MIN_W := 120.0
const SCHMAL_W := 76.0
const HUB := -10.0           ## gewählt: so weit hebt sie sich
const HUB_GRIFF := -24.0     ## gegriffen: noch ein Stück weiter

var title := ""
var icon_name := ""
var state := ""          ## kleiner Zustand rechts unten
var state_on := false    ## Zustand in Grün (eingeschaltet)
var schmal := false      ## nur das Symbol, schmale Kachel (vor dem Einhängen setzen)
var leer := false        ## nur der Umriss, ohne Glas (Hinzufügen)
var gedimmt := false     ## gerade nicht da (Anpassen): leiser
var gegriffen := false
var ausgeblendet := false
var _m: MarginContainer
var _lift := 0.0
var _shift := 0.0        ## seitlich versetzt gezeichnet (gleitet nach dem Verschieben zurück)
var _griff := 0.0        ## 0…1, gegriffen
var _aus := 0.0          ## 0…1, ausgeblendet
var _title_l: Label
var _state_l: Label
var _aus_ic: TextureRect


func setup(t: String, ic: String, st := "", on := false) -> Control:
	title = t
	icon_name = ic
	state = st
	state_on = on
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Breite gibt die Reihe vor: alle Kacheln teilen sich die Kartenbreite gleichmäßig. Früher
	# 200 px fest – sechs Kacheln (Emulator) ragten rechts über die Karte, drei ließen eine Lücke.
	custom_minimum_size = Vector2(SCHMAL_W if schmal else MIN_W, SIZE.y)
	size_flags_horizontal = Control.SIZE_FILL if schmal else Control.SIZE_EXPAND_FILL
	_m = U.margin(18, 18, 16, 14) if not schmal else U.margin(0, 0, 0, 0)
	U.full_rect(_m)
	_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_m)
	if schmal:
		tooltip_text = title
		var ic0 := U.icon(icon_name, 30, "muted")
		ic0.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic0.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic0.custom_minimum_size = Vector2(30, 30)
		_m.add_child(ic0)
	else:
		_build_voll()
	_aus = 1.0 if ausgeblendet else 0.0
	_look()
	focus_entered.connect(func() -> void:
		U.etikett(self, true)
		_lift_to(HUB_GRIFF if gegriffen else HUB)
	)
	focus_exited.connect(func() -> void:
		U.etikett(self, false)
		_lift_to(0.0)
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


func _build_voll() -> void:
	var col := U.vbox(0)
	_m.add_child(col)
	var top := U.hbox(0)
	var ic := U.icon(icon_name, 34, "text")
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ic.custom_minimum_size = Vector2(34, 34)
	top.add_child(ic)
	top.add_child(U.spacer())
	# Ausgeblendet (Anpassen): ein kleines durchgestrichenes Auge oben rechts.
	_aus_ic = U.icon("eye_off", 22, "muted")
	_aus_ic.custom_minimum_size = Vector2(22, 22)
	_aus_ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_aus_ic)
	col.add_child(top)
	col.add_child(U.spacer(0, 4, true))
	var t := U.label(title, "m", "text", "ui_bold", true)
	t.max_lines_visible = 2
	t.add_theme_constant_override("line_spacing", -4)
	col.add_child(t)
	_title_l = t
	resized.connect(_fit_title)
	# Ohne Zustand bleibt die Zeile frei (Text „Ag“, unsichtbar): So stehen die Wörter aller Kacheln
	# einer Reihe auf derselben Linie, auch wenn nur manche einen Zustand haben.
	var s := U.label(_state_text(), "s", "ok" if state_on else "muted", "medium")
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(s)
	_state_l = s


func _state_text() -> String:
	if ausgeblendet:
		return "Ausgeblendet"
	return state if state != "" else "Ag"


## Deckkraft von Inhalt und Auge nach gedimmt/ausgeblendet; die Zustandszeile nach ihrem Text.
func _look() -> void:
	if _m:
		_m.modulate.a = (0.5 if gedimmt else 1.0) * lerpf(1.0, 0.42, _aus)
	if _aus_ic:
		_aus_ic.modulate.a = _aus
	if _state_l:
		_state_l.self_modulate.a = 0.0 if (state == "" and not ausgeblendet) else 1.0
	queue_redraw()


## Schmale Kachel (viele Kacheln in einer Reihe): passt das längste Wort nicht, eine Stufe
## kleiner, notfalls zwei – sonst bräche „Bildschirmfoto“ mitten im Wort um.
func _fit_title() -> void:
	if not is_instance_valid(_title_l):
		return
	var room := size.x - 36.0
	var f := UzTheme.font("ui_bold")
	var longest := 0.0
	for w in title.split(" "):
		longest = maxf(longest, f.get_string_size(tr(w), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x)
	var fs := UzTheme.size("m")
	if longest > room:
		var klein := 0.0
		for w in title.split(" "):
			klein = maxf(klein, f.get_string_size(tr(w), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("s")).x)
		fs = UzTheme.size("s") if klein <= room else UzTheme.size("xs")
	if _title_l.get_theme_font_size("font_size") != fs:
		_title_l.add_theme_font_size_override("font_size", fs)


func activate() -> void:
	activated.emit()


## Ausblenden bzw. wieder einblenden (Anpassen): blasser, Auge, „Ausgeblendet“.
func set_aus(on: bool, weich := true) -> void:
	ausgeblendet = on
	if _state_l:
		_state_l.text = _state_text()
		U.set_label_color(_state_l, "muted" if on or not state_on else "ok")
	if not is_inside_tree() or not weich:
		_aus = 1.0 if on else 0.0
		_look()
		return
	U.ankommen(self, U.T_ORT, "uz_aus").tween_method(_set_aus, _aus, 1.0 if on else 0.0, U.T_ORT)


## Greifen bzw. ablegen (Anpassen): weiter angehoben, Ring in der Akzentfarbe, Schatten darunter.
func set_griff(on: bool) -> void:
	gegriffen = on
	U.ankommen(self, U.T_ORT, "uz_griff").tween_method(_set_griff, _griff, 1.0 if on else 0.0, U.T_ANTWORT if on else U.T_ORT)
	if has_focus():
		_lift_to(HUB_GRIFF if on else HUB)


## Nach dem Verschieben: von dx (alter Platz) an den neuen gleiten (Kurve „Ankommen“, T_ORT).
func gleiten(dx: float) -> void:
	_set_shift(U.weg_px(dx))
	U.ankommen(self, U.T_ORT, "uz_shift").tween_method(_set_shift, _shift, 0.0, U.T_ORT)


func _lift_to(y: float) -> void:
	var tw := U.tw(self, "uz_lift", Tween.TRANS_CUBIC)
	tw.tween_method(_set_lift, _lift, y, U.T_FOCUS if y < 0.0 else U.T_BASE)


func _set_lift(y: float) -> void:
	_lift = y
	_place()


func _set_aus(v: float) -> void:
	_aus = v
	_look()


func _set_griff(v: float) -> void:
	_griff = v
	queue_redraw()


func _set_shift(x: float) -> void:
	_shift = x
	_place()


func _place() -> void:
	if _m:
		_m.position = Vector2(_shift, _lift)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(_shift, _lift), size)
	var rad := maxi(8, UzTheme.r_panel() - 6)
	if _griff > 0.01:
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0.0)
		sh.set_corner_radius_all(rad)
		sh.shadow_color = Color(0, 0, 0, 0.5 * _griff)
		sh.shadow_size = int(round(28.0 * _griff))
		sh.shadow_offset = Vector2(0, 14.0 * _griff)
		draw_style_box(sh, r)
	if leer:
		var o := StyleBoxFlat.new()
		o.draw_center = false
		o.set_border_width_all(2)
		o.border_color = Color(UzTheme.col("text"), 0.14)
		o.set_corner_radius_all(rad)
		o.anti_aliasing = true
		draw_style_box(o, r)
	else:
		var glass := UzTheme.col("glass")
		var k := lerpf(1.0, 0.45, _aus) * (0.6 if gedimmt else 1.0)
		draw_style_box(UzTheme.box(Color(glass, glass.a * k), rad, 1, UzTheme.col("stroke")), r)
	U.draw_focus(self, rad, r)
	if _griff > 0.01:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(3)
		ring.border_color = Color(UzTheme.col("accent"), _griff)
		ring.set_corner_radius_all(rad + 6)
		ring.anti_aliasing = true
		draw_style_box(ring, r.grow(6))
