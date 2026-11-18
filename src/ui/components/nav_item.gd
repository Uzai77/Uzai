extends Control
## Ein Reiter oben (Bereich) oder darunter (Unterbereich). Wechselt beim Fokussieren,
## wie bei Konsolen üblich; A geht in den Bereich hinein. Gewählt: helle Schrift, darunter der Punkt
## im Akzent (Bereich) bzw. ein Strich (Unterbereich). Unter dem Cursor: die Pille, die Schrift darauf wird dunkel.
## Liegt der Reiter in einer Leiste (tab_strip.gd), zeichnet die Leiste Pille und Strich und
## lässt beide gleiten; der Reiter färbt dann nur seine Schrift (set_ink). Sonst zeichnet er
## beides selbst.
## Symbol-Reiter (compact, die Apps und das Zahnrad der Leiste oben, src/core/leiste_oben.gd):
## ruhend nur das Symbol, gewählt bzw. aktiv in seiner gefüllten Fassung (Icons.tab_icon). Unter
## dem Cursor gleitet daneben der Name auf (T_ORT) – die Leiste rückt weich mit, nichts springt.
## Eigene Apps zeigen statt des Symbols ihr echtes App-Symbol (bild_path), ohne eines den
## Anfangsbuchstaben in einer gerundeten Kachel (mono).

signal picked
signal opened                ## A auf dem Reiter: hinein in den Bereich

const U := preload("res://src/ui/u.gd")

var text := ""
var icon_name := ""
var count := -1
var style := "tab"
var selected := false
var compact := false        ## nur das Symbol zeigen, den Namen nur unter dem Cursor
var bild_path := ""         ## echtes App-Symbol (eigene Apps, apps_extern.gd logo_path) statt des Symbols
var mono := ""              ## Anfangsbuchstabe, wenn es weder Symbol noch App-Symbol gibt
var managed := false        ## eine Leiste (tab_strip.gd) zeichnet Pille und Strich
## Logo statt des Namens (Quellen der Startseite, badge_logos.gd line_logo): { tex, size } –
## einfarbig weiß, gefärbt wie die Schrift. Der Name bleibt in text (Vorlesen, Menüs).
var logo: Dictionary = {}
var _box: HBoxContainer
var _label: Label
var _icon: Control
var _clip: Control          ## hält den Namen eines Symbol-Reiters, gleitet auf (compact)
var _reveal := 0.0          ## 0 = nur Symbol, 1 = Name ganz da
var _reveal_tw: Tween
var _name_w := 0.0
var _count_l: Label
var _ink := 0.0
var _pad := Vector2(18, 10)


func setup(t: String, ic := "", st := "tab", sel := false, cnt := -1) -> Control:
	text = t
	icon_name = ic
	style = st
	selected = sel
	count = cnt
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var p := get_parent()
	managed = managed or (p != null and p.has_method("strip_focus"))
	set_meta("uz_selected", selected)
	# Vorher gesetzte Hinweise behalten (Quellen der Startseite: „Alle anzeigen“).
	if not has_meta("uz_hint_a"):
		set_meta("uz_hint_a", "Öffnen")
	_box = U.hbox(10)
	add_child(_box)
	if not logo.is_empty():
		_build_logo()
		return
	if compact and (icon_name != "" or bild_path != "" or mono != ""):
		_build_compact()
		return
	if icon_name != "":
		_icon = U.icon(icon_name, 26 if style == "tab" else 22, _rest())
		_box.add_child(_icon)
	_label = U.label(text, "m", _rest(), "ui_bold" if selected else "ui")
	var fs := _font_size()
	_label.add_theme_font_size_override("font_size", fs)
	_label.clip_text = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Platz für die fette Schrift freihalten: wechselt die Auswahl, verrutscht nichts.
	_label.custom_minimum_size.x = ceilf(maxf(_text_w(UzTheme.ui("ui_bold"), fs), _text_w(UzTheme.ui("ui"), fs)))
	_box.add_child(_label)
	if count > 0:
		# Anzahl klein und hochgestellt, wie eine Fußnote – keine Pille.
		_count_l = U.label(str(count), "xs", "muted", "ui")
		_count_l.clip_text = false
		_count_l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_box.add_child(_count_l)
	_pad = Vector2(18, 10) if style == "tab" else Vector2(16, 9)
	_box.position = _pad
	_box.resized.connect(func() -> void:
		custom_minimum_size = _box.size + _pad * 2
	)
	custom_minimum_size = _box.get_combined_minimum_size() + _pad * 2
	_connect()


## Symbol-Reiter: Symbol (bzw. App-Symbol, Buchstabe), daneben der Name in einer Hülle, die nur
## unter dem Cursor aufgeht. Die Zeile ist so hoch wie die der Wort-Reiter (die Leiste springt nicht).
const ICON_PX := 28
const NAME_GAP := 10.0


func _build_compact() -> void:
	_box.add_theme_constant_override("separation", 0)
	var lh := ceilf(UzTheme.ui("ui").get_height(UzTheme.size("m"))) if UzTheme.ui("ui") else 30.0
	_box.custom_minimum_size.y = maxf(lh, ICON_PX)
	if bild_path != "" or (icon_name == "" and mono != ""):
		_icon = _Mono.new()
		(_icon as _Mono).letter = mono
		_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		if bild_path != "":
			var path := bild_path
			Media.file_texture(path, ICON_PX * 2, func(t: Texture2D) -> void:
				if t != null and is_instance_valid(_icon) and _icon is _Mono:
					(_icon as _Mono).tex = t
					_apply_ink())
	else:
		_icon = U.icon(Icons.tab_icon(icon_name, selected), ICON_PX, _rest())
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_box.add_child(_icon)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.visible = false
	_clip.size_flags_vertical = Control.SIZE_FILL
	_box.add_child(_clip)
	_label = U.label(text, "s", _rest(), "ui_bold")
	_label.clip_text = false
	_label.auto_translate_mode = auto_translate_mode
	_name_w = ceilf(_text_w(UzTheme.ui("ui_bold"), UzTheme.size("s"))) + 2.0
	_clip.add_child(_label)
	_label.position = Vector2(NAME_GAP, 0)
	_label.size = Vector2(_name_w, _box.custom_minimum_size.y)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pad = Vector2(14, 10)
	_box.position = _pad
	_box.resized.connect(func() -> void:
		custom_minimum_size = _box.size + _pad * 2
	)
	custom_minimum_size = _box.get_combined_minimum_size() + _pad * 2
	_connect()
	if has_focus():
		_set_reveal(1.0)


## Wie breit der Name aufgeht (0…1).
func _set_reveal(v: float) -> void:
	_reveal = clampf(v, 0.0, 1.0)
	if _clip == null:
		return
	_clip.visible = _reveal > 0.001
	_clip.custom_minimum_size = Vector2((NAME_GAP + _name_w) * _reveal, 0)
	_label.modulate.a = clampf(_reveal * 1.6 - 0.4, 0.0, 1.0)
	_box.reset_size()
	custom_minimum_size = _box.get_combined_minimum_size() + _pad * 2


## Breite, die der Name aufgeklappt braucht (für das Einteilen der Leiste, main.gd).
func name_width() -> float:
	return NAME_GAP + _name_w if _clip else 0.0


## Logo statt Schrift: gleiche Zeilenhöhe wie der Name (die Leiste springt nicht), Logo mittig.
func _build_logo() -> void:
	var lh := ceilf(UzTheme.ui("ui").get_height(_font_size())) if UzTheme.ui("ui") else 26.0
	var sz: Vector2 = logo.get("size", Vector2(lh * 3.0, lh))
	_icon = TextureRect.new()
	_icon.texture = logo.get("tex")
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.custom_minimum_size = sz
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.modulate = UzTheme.col(_rest())
	_icon.set_meta("uz_icon", true)
	_box.custom_minimum_size.y = maxf(lh, sz.y)
	_box.add_child(_icon)
	_pad = Vector2(18, 10) if style == "tab" else Vector2(16, 9)
	_box.position = _pad
	_box.resized.connect(func() -> void:
		custom_minimum_size = _box.size + _pad * 2
	)
	custom_minimum_size = _box.get_combined_minimum_size() + _pad * 2
	_connect()


func _connect() -> void:
	focus_entered.connect(func() -> void:
		_update_compact()
		if managed:
			_strip_call("strip_focus", true)
		else:
			U.etikett(self, true)
			queue_redraw()
		picked.emit()
	)
	focus_exited.connect(func() -> void:
		_update_compact()
		if managed:
			_strip_call("strip_focus", false)
		else:
			U.etikett(self, false)
			queue_redraw()
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)
	if managed:
		_apply_ink()
		if selected:
			_strip_call("strip_selected", true)


func _font_size() -> int:
	return UzTheme.size("m") if style == "tab" else UzTheme.size("m") - 1


func _text_w(f: Font, fs: int) -> float:
	# atr: übersetzt nur, wenn der Reiter übersetzt wird (eigene Apps tragen ihren Namen unverändert).
	return f.get_string_size(atr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f else 0.0


func _rest() -> String:
	return "text" if selected else "muted"


## Maus darüber (schweben.gd): in einer Leiste (tab_strip.gd) zeichnet die Leiste den Schein.
func zeiger_schweben(an: bool) -> void:
	if managed:
		_strip_call("strip_hover", an)


func _strip_call(method: String, arg: bool) -> void:
	var p := get_parent()
	if p and p.has_method(method):
		p.call(method, self, arg)


## A auf dem Reiter: in den Bereich hinein (die Auswahl wechselt schon beim Fokussieren).
func activate() -> void:
	opened.emit()


func activate_sound() -> String:
	return "move"


## Eindrücken übernimmt die Leiste (die Pille gibt kurz nach), sonst wie überall.
func press_feedback() -> void:
	if managed:
		_strip_call("strip_press", true)
		return
	if pivot_offset == Vector2.ZERO:
		pivot_offset = size * 0.5
	var tw := U.tw(self, "uz_press")
	tw.tween_property(self, "scale", Vector2.ONE * 0.96, U.T_PRESS)
	tw.tween_property(self, "scale", Vector2.ONE, U.T_BASE)


## Wo die Schrift liegt (für den Strich und die Färbung), in eigenen Koordinaten.
func ink_rect() -> Rect2:
	if _clip:
		var ir := Rect2(_box.position + _icon.position, _icon.size)
		if _clip.visible and _clip.size.x > NAME_GAP:
			ir = ir.merge(Rect2(_box.position + _clip.position + Vector2(NAME_GAP, 0), Vector2(_clip.size.x - NAME_GAP, _clip.size.y)))
		return ir
	if _label and _label.visible:
		var lr := Rect2(_box.position + _label.position, _label.size)
		if _icon:
			lr = lr.merge(Rect2(_box.position + _icon.position, _icon.size))
		return lr
	if _icon:
		return Rect2(_box.position + _icon.position, _icon.size)
	return Rect2(Vector2.ZERO, size)


## Wie weit die helle Pille unter der Schrift liegt (0…1): Schrift und Symbol werden dunkel.
func set_ink(f: float) -> void:
	var v := clampf(f, 0.0, 1.0)
	if absf(v - _ink) < 0.004 and v != 0.0 and v != 1.0:
		return
	_ink = v
	_apply_ink()


func _apply_ink() -> void:
	var dark := UzTheme.col("on_focus")
	var col := UzTheme.col(_rest()).lerp(dark, _ink)
	if _label:
		_label.add_theme_color_override("font_color", col)
	if _icon is _Mono and (_icon as _Mono).tex != null:
		# Echtes App-Symbol: in seinen Farben, ruhend etwas zurückgenommen.
		_icon.modulate = Color(1, 1, 1).lerp(Color(0.8, 0.8, 0.82), 0.0 if selected or _ink > 0.5 or has_focus() else 1.0)
	elif _icon:
		_icon.modulate = col
	if _count_l:
		_count_l.add_theme_color_override("font_color", UzTheme.col("muted").lerp(dark, _ink))


func _update_compact() -> void:
	if not compact or _icon == null or _clip == null:
		return
	if _icon is TextureRect and icon_name != "":
		(_icon as TextureRect).texture = Icons.tex(Icons.tab_icon(icon_name, selected or has_focus()), ICON_PX)
	var want := 1.0 if has_focus() else 0.0
	if is_equal_approx(want, _reveal) and not (_reveal_tw and _reveal_tw.is_valid()):
		return
	if _reveal_tw and _reveal_tw.is_valid():
		_reveal_tw.kill()
	if not is_inside_tree():
		_set_reveal(want)
		return
	_reveal_tw = create_tween()
	_reveal_tw.tween_method(_set_reveal, _reveal, want, U.T_ORT if want > 0.5 else U.T_WEG).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func set_selected(on: bool) -> void:
	selected = on
	_update_compact()
	set_meta("uz_selected", on)
	if _label and _clip == null:
		_label.add_theme_font_override("font", UzTheme.ui("ui_bold" if on else "ui"))
	if managed:
		_apply_ink()
		if on:
			_strip_call("strip_selected", false)
		return
	var focused := has_focus()
	if focused:
		U.etikett(self, false, false)
	# Eine noch laufende Überblendung (vom Verlassen des Reiters) darf die neue Farbe nicht
	# überschreiben – sonst bliebe ein abgewählter Reiter hell.
	for n: Node in [_label, _icon]:
		if n and n.has_meta("uz_ctw"):
			var old: Variant = n.get_meta("uz_ctw")
			if old is Tween and (old as Tween).is_valid():
				(old as Tween).kill()
			n.remove_meta("uz_ctw")
		if n and n.has_meta("uz_col"):
			n.remove_meta("uz_col")
		if n and n.has_meta("uz_mod"):
			n.remove_meta("uz_mod")
	if _label:
		_label.add_theme_color_override("font_color", UzTheme.col(_rest()))
	if _icon:
		_icon.modulate = UzTheme.col(_rest())
	if focused:
		U.etikett(self, true, false)
	queue_redraw()


func _draw() -> void:
	if managed:
		return
	U.draw_focus(self, 999)
	if selected and float(get_meta("uz_f", 0.0)) < 0.5:
		var ir := ink_rect()
		if style == "tab":
			# Bereich: der Punkt der Marke mittig unter dem Wort (wie in der Leiste, tab_strip.gd).
			draw_circle(Vector2(roundf(ir.get_center().x), size.y - 4.5), 3.5, UzTheme.col("accent"))
		else:
			# Unterbereich: Strich so breit wie das Wort.
			draw_style_box(UzTheme.box(UzTheme.col("accent"), 1), Rect2(ir.position.x, size.y - 3, ir.size.x, 2))


## Steuerkreuz hoch/runter mit eigenem Ziel (Meta "uz_up" / "uz_down", Callable → bool).
func nav_ud(d: int) -> bool:
	var key := "uz_up" if d < 0 else "uz_down"
	if has_meta(key):
		var cb: Variant = get_meta(key)
		if cb is Callable and (cb as Callable).is_valid():
			return bool((cb as Callable).call())
	return false


## Eigene App ohne Symbol: ihr App-Symbol (tex), bis es geladen ist bzw. ohne eines der
## Anfangsbuchstabe in einer gerundeten Kachel mit dem Strich der Symbole – gefärbt wie sie.
class _Mono extends Control:
	var letter := ""
	var tex: Texture2D:
		set(v):
			tex = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_meta("uz_icon", true)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if tex:
			draw_texture_rect(tex, r, false)
			return
		var k := size.x / 24.0
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(maxi(1, roundi(2.0 * k)))
		sb.set_corner_radius_all(roundi(5.5 * k))
		sb.border_color = Color.WHITE
		sb.anti_aliasing = true
		draw_style_box(sb, r.grow(-2.5 * k))
		var f := UzTheme.display("bold") if UzTheme.display("bold") else UzTheme.ui("ui_bold")
		var fs := roundi(size.y * 0.5)
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Grundlinie so, dass die Versalhöhe (etwa 0,7 der Oberlänge) mittig sitzt.
		var cap := f.get_ascent(fs) * 0.7
		draw_string(f, Vector2((size.x - w) * 0.5, (size.y + cap) * 0.5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
