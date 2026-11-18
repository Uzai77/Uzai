extends Control
## Kachel des Uzai-Browsers (Startseite, Tab-Karussell): matte Fläche im Licht von oben, groß das
## Zeichen der Seite – ihr Anfangsbuchstabe in einem Kern im Akzent, wie der Kern in der Schale des
## Uzai-Zeichens – oder ein Vorschaubild des Tabs; darunter Titel und Name der Seite. Gewählt: der eine
## Kachel-Cursor (UzTheme.draw_tile_focus) im Cursor-Takt, die Kachel hebt sich in T_ORT. A wählt.

signal chosen

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const D := preload("res://src/core/browser_daten.gd")
const Adresse := preload("res://src/core/browser_adresse.gd")

const LIFT := 10.0

var groesse := Vector2(300, 196)
var url := ""
var titel := ""
var zeile := ""                    ## leise unter dem Titel (Name der Seite, „Privat“, „Geschlossen“)
var zeichen := ""                  ## statt des Anfangsbuchstabens ein Symbol (plus, lock, refresh)
var bild: Texture2D                ## Vorschau des Tabs (Karussell)
var aktiv := false                 ## der Tab, der gerade vorn ist (Punkt der Marke)

var _focus_t := 0.0
var _hub := 0.0
var _bild: TextureRect
var _titel_l: Label
var _zeile_l: Label


func setup(u: String, t: String, z := "") -> Control:
	url = u
	titel = t if t != "" else Adresse.host_von(u)
	zeile = z if z != "" else Adresse.host_von(u)
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = groesse
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var flaeche_h := groesse.y - 64.0
	if bild:
		_bild = U.rounded_image(float(UzTheme.r_panel()))
		_bild.texture = bild
		_bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bild.size = Vector2(groesse.x, flaeche_h)
		_bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bild)
	var col := U.vbox(2)
	col.position = Vector2(4, flaeche_h + 12)
	col.size = Vector2(groesse.x - 8, 52)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_titel_l = U.ellipsis(U.label(titel, "m", "text", "medium"))
	_titel_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_titel_l)
	_zeile_l = U.ellipsis(U.label(zeile, "s", "muted"))
	_zeile_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_zeile_l)
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if has_focus():
				Nav.activate(self)
			else:
				grab_focus()
			accept_event())


func activate() -> void:
	press_feedback()
	chosen.emit()


func _on_focus(on: bool) -> void:
	Liste.takt(self, _focus_t, on, func(v: float) -> void:
		_focus_t = v
		queue_redraw())
	var t := U.ankommen(self, U.T_ORT if on else U.T_WEG, "uz_hub") if on else U.weg(self, "uz_hub")
	t.tween_method(_set_hub, _hub, 1.0 if on else 0.0, U.T_ORT if on else U.T_WEG)


func _set_hub(v: float) -> void:
	_hub = v
	if is_instance_valid(_bild):
		_bild.position.y = -U.weg_px(LIFT) * v
	queue_redraw()


func press_feedback() -> void:
	var t := U.ankommen(self, U.T_ORT, "uz_hub")
	t.tween_method(_set_hub, _hub, 0.55, U.T_ANTWORT)
	t.tween_method(_set_hub, 0.55, 1.0, U.T_ORT)


func _draw() -> void:
	var dy := -U.weg_px(LIFT) * _hub
	var r := Rect2(Vector2(0, dy), Vector2(groesse.x, groesse.y - 64.0))
	var rc := UzTheme.r_panel()
	# Fläche mit Schatten und Lichtkante oben (Tiefe statt Kontur).
	var sb := UzTheme.flaeche(UzTheme.col("surface_hi"), rc, 1)
	sb.shadow_color = Color(0, 0, 0, 0.3 + 0.16 * _focus_t)
	sb.shadow_size = int(18 + 12 * _focus_t)
	sb.shadow_offset = Vector2(0, 8 + 6 * _focus_t)
	draw_style_box(sb, r)
	if bild == null:
		_kern(r)
	if aktiv:
		draw_circle(Vector2(r.end.x - 18, r.position.y + 18), 5.0, UzTheme.col("accent"))
	if _focus_t > 0.01:
		UzTheme.draw_tile_focus(self, r, rc, clampf(_focus_t, 0.0, 1.0))


## Das Zeichen der Seite: ein Kern im Akzent mit ihrem Anfangsbuchstaben (oder einem Symbol), darum
## eine leise Schale aus Licht.
func _kern(r: Rect2) -> void:
	var c := r.get_center()
	var rad := minf(r.size.y * 0.27, 40.0)
	draw_circle(c, rad + 14.0, Color(UzTheme.col("accent"), 0.08 + 0.06 * _focus_t))
	draw_circle(c, rad, UzTheme.col("accent"))
	if zeichen != "":
		var ic: Texture2D = Icons.tex(zeichen, int(rad * 1.1))
		if ic:
			draw_texture_rect(ic, Rect2(c - Vector2.ONE * rad * 0.55, Vector2.ONE * rad * 1.1), false, UzTheme.col("bg"))
		return
	var f := UzTheme.display()
	var fs := int(rad * 1.15)
	var m := D.monogramm(url)
	var w := f.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, c + Vector2(-w.x * 0.5, fs * 0.36), m, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("bg"))
