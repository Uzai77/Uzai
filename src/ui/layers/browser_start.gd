extends Control
## Startseite des Uzai-Browsers – von Uzai gezeichnet, keine Webseite: oben die Marke mit „Uzai Browser“
## (dorthin fliegt die Marke der Startbühne, browser.gd Aufgang), groß die Suche, darunter als Kacheln deine
## Lesezeichen, die als App angehefteten Seiten und was du zuletzt besucht bzw. offen hattest. Leere Reihen
## fehlen. A auf der Suche öffnet die Tastatur, A auf einer Kachel die Seite.

signal suchen
signal oeffnen(url: String, zoom: int)

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const Kachel := preload("res://src/ui/components/browser_kachel.gd")
const D := preload("res://src/core/browser_daten.gd")
const Adresse := preload("res://src/core/browser_adresse.gd")
const Logo := preload("res://src/ui/components/uzai_logo.gd")

const GUTTER := 96
const MAX_JE_REIHE := 12

var _feld: Control
var _maschine_l: Label
var _marke: Control
var _marke_an := true


func _ready() -> void:
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	aufbauen()


func aufbauen() -> void:
	U.clear(self)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	U.full_rect(sc)
	add_child(sc)
	var col := U.vbox(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(col)
	col.add_child(U.spacer(0, 72, false))
	var kopf := U.margin(GUTTER, 0, GUTTER, 0)
	col.add_child(kopf)
	var zeile := U.hbox(22)
	kopf.add_child(zeile)
	_marke = Marke.new()
	_marke.custom_minimum_size = Vector2(56, 56)
	_marke.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_marke.modulate.a = 1.0 if _marke_an else 0.0
	zeile.add_child(_marke)
	var titel := U.label("Uzai Browser", "xxl", "text")
	titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	titel.add_theme_font_override("font", UzTheme.display())
	zeile.add_child(titel)
	zeile.add_child(U.spacer(1, 0, true))
	_maschine_l = U.label(Adresse.maschine(D.suchmaschine()).name, "s", "muted", "medium")
	_maschine_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_maschine_l.size_flags_vertical = Control.SIZE_SHRINK_END
	zeile.add_child(_maschine_l)
	col.add_child(U.spacer(0, 26, false))
	var fm := U.margin(GUTTER, 0, GUTTER, 0)
	col.add_child(fm)
	_feld = Suchfeld.new()
	_feld.set_meta("uz_key", "browser:suche")
	_feld.set_meta("uz_default", true)
	_feld.set_meta("uz_hint_a", "Suchen")
	_feld.connect("gewaehlt", func() -> void: suchen.emit())
	fm.add_child(_feld)
	col.add_child(U.spacer(0, 30, false))
	_reihe(col, "Favoriten", D.liste("favoriten"), "fav")
	_reihe(col, "Apps", D.liste("apps"), "app")
	_reihe(col, "Zuletzt besucht", D.liste("zuletzt"), "zul")
	_reihe(col, "Zuletzt geöffnet", D.liste("sitzung"), "sit")
	col.add_child(U.spacer(0, 120, false))


func _reihe(col: VBoxContainer, titel: String, eintraege: Array, art: String) -> void:
	if eintraege.is_empty():
		return
	var hm := U.margin(GUTTER, 10, GUTTER, 0)
	hm.add_child(U.label(titel, "l", "muted", "medium"))
	col.add_child(hm)
	var shelf = Shelf.new().setup("browser:" + art, 28, true, 18, GUTTER, 26)
	col.add_child(shelf)
	for i in mini(eintraege.size(), MAX_JE_REIHE):
		var e: Dictionary = eintraege[i]
		var k = Kachel.new().setup(str(e.url), str(e.titel))
		k.set_meta("uz_key", "browser:%s:%d" % [art, i])
		k.set_meta("uz_hint_a", "Öffnen")
		var zoom := int(e.get("zoom", 0))
		k.chosen.connect(func() -> void: oeffnen.emit(str(e.url), zoom))
		shelf.add(k)


func standard() -> Control:
	return _feld


## Wo die kleine Marke im Kopf steht (Schirm-Koordinaten des Zeichens selbst) – Ziel des Aufgangs; leer, solange
## die Seite noch keinen Platz hat.
func marke_rect() -> Rect2:
	if _marke == null or not is_instance_valid(_marke) or not _marke.is_inside_tree() or _marke.size.y < 2.0:
		return Rect2()
	return _marke.call("zeichen_rect")


## Die eigene Marke erst zeigen, wenn die fliegende da ist (Aufgang); sonst stünde sie kurz doppelt.
func marke_zeigen(an: bool) -> void:
	_marke_an = an
	if is_instance_valid(_marke):
		if an and _marke.modulate.a < 0.99:
			U.ankommen(_marke, U.T_ANTWORT, "uz_marke").tween_property(_marke, "modulate:a", 1.0, U.T_ANTWORT)
		elif not an:
			_marke.modulate.a = 0.0


## Die kleine Marke im Kopf: das Zeichen flach im Akzent mit Licht in der Fuge.
class Marke extends Control:
	const Logo2 := preload("res://src/ui/components/uzai_logo.gd")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hoehe() -> float:
		return size.y * 0.86

	func zeichen_rect() -> Rect2:
		var h := hoehe()
		var w := Logo2.zeichen_breite(h)
		var xf := get_global_transform()
		return Rect2(xf * (size * 0.5 - Vector2(w, h) * 0.5), Vector2(w, h) * xf.get_scale())

	func _draw() -> void:
		var akz := UzTheme.col("accent")
		Logo2.draw_mark(self, size * 0.5, hoehe(), akz, Logo2.licht_von(akz))


## Das große Suchfeld: eine Pille im Licht, gewählt hebt sie sich mit dem Cursor der Marke.
class Suchfeld extends Control:
	signal gewaehlt

	var _t := 0.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(1100, 96)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 22)
		h.position = Vector2(36, 0)
		h.size = Vector2(1100 - 72, 96)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		var ic := U.icon("search", 34, "muted")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var l := U.label("Suchen oder Adresse eingeben", "l", "muted")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		focus_entered.connect(func() -> void: _takt(true))
		focus_exited.connect(func() -> void: _takt(false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())

	func activate() -> void:
		gewaehlt.emit()

	func _takt(on: bool) -> void:
		Liste.takt(self, _t, on, func(v: float) -> void:
			_t = v
			queue_redraw())

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := UzTheme.flaeche(UzTheme.col("surface_hi"), UzTheme.r_pill(), 1)
		draw_style_box(sb, r)
		if _t > 0.01:
			UzTheme.draw_selection(self, r, UzTheme.r_pill(), _t)
