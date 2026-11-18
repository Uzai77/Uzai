extends "res://src/ui/layers/layer.gd"
## Tabs des Uzai-Browsers als Karussell (X): je Tab eine große Karte mit Vorschau der Seite, der Tab
## vorn trägt den Punkt der Marke. Dahinter „Neuer Tab“ und – wenn es welche gibt – „Wiederherstellen“
## (zuletzt geschlossen). Links/rechts bzw. LB/RB wählen, A wechselt, X schließt den gewählten Tab,
## B zurück zur Seite.

const Kachel := preload("res://src/ui/components/browser_kachel.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const BrowserEbene := preload("res://src/ui/layers/browser.gd")

var ebene: BrowserEbene                 ## der Browser (browser.gd)
var _reihe: HBoxContainer
var _titel: Label
var _karten: Array = []


func build() -> void:
	dim = 0.86
	if is_instance_valid(_scrim):
		_scrim.color = Color(UzTheme.col("bg"), dim)
	var col := U.vbox(28)
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.anchor_right = 1.0
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(col)
	var km := U.margin(96, 0, 96, 0)
	col.add_child(km)
	_titel = U.label("", "xxl", "text")
	_titel.add_theme_font_override("font", UzTheme.display())
	km.add_child(_titel)
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	sc.custom_minimum_size = Vector2(0, 360)
	col.add_child(sc)
	var m := U.margin(96, 20, 96, 20)
	sc.add_child(m)
	_reihe = U.hbox(36)
	m.add_child(_reihe)
	_fuellen()
	set_meta("uz_hint_b", "Zurück")


func _fuellen() -> void:
	U.clear(_reihe)
	_karten.clear()
	var tabs: Dictionary = ebene.tabs
	var reihe: Array = ebene.reihe
	_titel.text = TranslationServer.translate("Tabs") + "  ·  %d" % reihe.size()
	_titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for id in reihe:
		var t: Dictionary = tabs[id]
		var k = Kachel.new()
		k.groesse = Vector2(440, 312)
		k.bild = t.get("bild", null)
		k.aktiv = int(id) == int(ebene.aktiv)
		k.setup(str(t.url), str(t.get("titel", "")), TranslationServer.translate("Privat") if bool(t.get("privat", false)) else "")
		k.set_meta("uz_key", "browser:tab:%d" % int(id))
		k.set_meta("uz_hint_a", "Wechseln")
		k.set_meta("uz_hint_x", "Schließen")
		k.set_meta("uz_on_x", func() -> void: _schliessen(int(id)))
		k.chosen.connect(func() -> void:
			close()
			ebene.tab_waehlen(int(id)))
		_reihe.add_child(k)
		_karten.append(k)
	var neu = Kachel.new()
	neu.groesse = Vector2(300, 312)
	neu.zeichen = "plus"
	neu.setup("", TranslationServer.translate("Neuer Tab"), " ")
	neu.set_meta("uz_key", "browser:tab:neu")
	neu.chosen.connect(func() -> void:
		close()
		ebene.neuer_tab(false))
	_reihe.add_child(neu)
	if not (ebene.geschlossen as Array).is_empty():
		var g: Dictionary = (ebene.geschlossen as Array)[0]
		var w = Kachel.new()
		w.groesse = Vector2(300, 312)
		w.zeichen = "undo"
		w.setup(str(g.url), TranslationServer.translate("Wiederherstellen"), str(g.get("titel", "")))
		w.set_meta("uz_key", "browser:tab:zurueck")
		w.chosen.connect(func() -> void:
			close()
			ebene.wiederherstellen())
		_reihe.add_child(w)


func _first_focus() -> Control:
	for k in _karten:
		if bool(k.get("aktiv")):
			return k
	return _karten[0] if not _karten.is_empty() else Nav.default_in(self)


func _schliessen(id: int) -> void:
	ebene.tab_schliessen(id)
	Sfx.play("back")
	await get_tree().create_timer(0.15).timeout
	if not is_inside_tree():
		return
	if (ebene.reihe as Array).is_empty():
		close()
		return
	_fuellen()
	await get_tree().process_frame
	Nav.focus(_first_focus(), true)


func nav_command(cmd: String) -> bool:
	if cmd == "b":
		close()
		return true
	if cmd == "lb" or cmd == "rb":
		Nav.move("left" if cmd == "lb" else "right")
		return true
	if cmd == "y":
		close()
		ebene.neuer_tab(false)
		return true
	return false
