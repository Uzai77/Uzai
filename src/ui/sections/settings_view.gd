extends "res://src/ui/sections/settings_suche.gd"
## Einstellungen wie auf der Konsole: links die Suche und elf Kategorien nach Häufigkeit, in der
## Mitte die Zeilen der gewählten Kategorie – Titel, rechts der Wert, höchstens eine leise
## Unterzeile –, rechts klein der Ort, der Titel und, wo es hilft, ein Satz oder eine Vorschau
## (Farbschema, Ecken, Cover, Schrift, Uhr, Startanimation, Pfade, Werte eines Systems).
## Höchstens zwei Ebenen: Seite und Unterseite („…“-Zeilen gleiten von rechts herein); Seltenes
## steht gebündelt unter „Mehr …“ am Ende einer Seite. Blätter eines Gegenstands (ein System, ein
## Emulator, ein Filter-Profil) stehen bei ihm.
##
## Bedienung: Hoch/runter in der Liste links zeigt die Kategorie sofort, A oder rechts geht
## hinein, links oder B wieder zurück; LB/RB blättert durch die Kategorien. Das Steuerkreuz bleibt
## Bewegung zwischen den Spalten – auch auf Schaltern, Auswahlen und Reglern, in Unterseiten (links
## geht aus ihr hinaus) und in der Suche. Werte ändert A: Schalter kippen, eine Auswahl mit zwei
## Werten wechselt, mit mehr öffnet sich die Auswahlliste, beim Regler beginnt A das Einstellen
## (links/rechts, A oder B fertig); sonst öffnet A Bildschirmtastatur, Dateiauswahl, Farbwahl oder
## Unterseite (setting_row.gd nur_a). Nach außen springt Uzai nur, wo es nicht anders geht, und
## sagt das vorher (Spotify, Discord, Explorer).
##
## Bewegung (Takt, src/ui/u.gd): Kategorie und Erklärung kreuzen in T_ORT, die Zeilen der neuen
## Seite kommen gestaffelt an; Werte bewegen sich in der Zeile (setting_row.gd); Treffer der
## Suche blenden einzeln ein. Ruhig (Animationen reduzieren): alles steht sofort.
##
## Rahmen und Navigation stehen hier; Bausteine, Unterseiten, Seiten und Suche in den Schichten
## darunter (settings_bausteine.gd bis settings_suche.gd, Übersicht in settings_bausteine.gd).

## Frühere Reiter und Orte → heutige Kategorie (Verknüpfungen aus anderen Bereichen und Tests).
const ALIASES := { "bibliothek": "spiele", "systeme": "emulation", "emulatoren": "emulation", "bildfilter": "emulation",
	"videos": "medien", "filme": "medien", "musik": "klang", "ton": "klang", "info": "system", "suchen": "suche" }

## Darunter (logische Zeilen) passen die Kategorien links nicht mehr untereinander: sie rollen.
const CATS_FIT_H := 1000.0
const CAT_PAD := 20.0
const FitBox := preload("res://src/ui/components/fit_box.gd")

var _cat_gen := 0
var _cat_ms := -100000         ## wann der Cursor zuletzt eine Kategorie gewählt hat
## Zwei Kategorien schneller hintereinander gewählt (Durchblättern, Halten): erst nach Verweilen bauen.
const CAT_SCHNELL_MS := 250
var _switch_focus := ""           # wohin nach LB/RB: "cats" (Liste links) oder "content"


func _init() -> void:
	super()
	id = "settings"
	title = "Einstellungen"
	icon_name = "settings"
	own_subnav = true


func subtabs() -> Array:
	return CATS.map(func(c): return { "id": c[0], "label": c[1] })


func resolve_sub(sub_id: String) -> String:
	return str(ALIASES.get(sub_id, sub_id))


func build() -> void:
	sub = resolve_sub(sub)
	if sub != SUCHE and not CATS.any(func(c): return c[0] == sub):
		sub = CATS[0][0]
	U.clear(self)
	_rows = null
	_sheet = null
	_suche_index_vergessen()
	# Der Zustand von Discord ändert sich im Hintergrund (Freigabe in der Discord-App):
	# Konten zeigt ihn immer aktuell an.
	if not Voice.changed.is_connected(_on_voice_changed):
		Voice.changed.connect(_on_voice_changed)
		DiscordChat.changed.connect(_on_voice_changed)
	if Library.epic_account and not Library.epic_account.changed.is_connected(_on_epic_changed):
		Library.epic_account.changed.connect(_on_epic_changed)
	var vw := U.view_size().x
	var avail := vw - GUTTER * 2.0
	var cat_w := clampf(avail * 0.18, 230.0, CAT_W)
	var help_w := clampf(avail * 0.32, 340.0, HELP_W)
	var list_x := GUTTER + cat_w + COL_GAP
	var list_w := avail - cat_w - help_w - COL_GAP * 2.0
	# Kein HBox als Wurzel, und der Inhalt zuerst: So findet U.cascade die Liste der Einstellungen.
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(root)
	add_child(root)
	_list = U.vbox(0)
	_list.set_meta("uz_group", "settings:content")
	_list.set_meta("uz_mem", true)
	var lm := U.margin(20, 6, 20, 96)
	lm.add_child(_list)
	_scroll = scroll_v(lm)
	_scroll.set_meta("uz_pad_v", 150.0)
	_scroll.anchor_bottom = 1.0
	_scroll.offset_left = list_x - 20.0
	_scroll.offset_right = list_x + list_w + 20.0
	root.add_child(_scroll)
	# Links die Suche und die Kategorien.
	var cm := U.margin(0, 12, 0, 0)
	cm.offset_left = GUTTER - 16.0
	cm.offset_right = GUTTER + cat_w
	cm.anchor_bottom = 1.0
	root.add_child(cm)
	_cats_box = U.vbox(4)
	_cats_box.set_meta("uz_group", "settings:cats")
	_cats_box.set_meta("uz_enter", "sel")
	if U.view_size().y < CATS_FIT_H:
		# Große Oberfläche: Nicht alle Kategorien passen untereinander – die Liste rollt mit der
		# Auswahl (Rand innen, damit das Glimmen der Auswahl nicht abgeschnitten wird).
		cm.offset_left -= CAT_PAD
		cm.offset_right += CAT_PAD
		cm.add_theme_constant_override("margin_top", 0)
		var pad := U.margin(int(CAT_PAD), 12, int(CAT_PAD), 40)
		pad.add_child(_cats_box)
		var csc := scroll_v(pad)
		csc.set_meta("uz_pad_v", 90.0)
		cm.add_child(csc)
	else:
		cm.add_child(_cats_box)
	_build_cats()
	# Rechts die Erklärung: Ort klein, Titel in der Titelschrift, ein Satz, Vorschau.
	_help_m = U.margin(0, 26, 0, 30)
	_help_m.anchor_right = 1.0
	_help_m.anchor_bottom = 1.0
	_help_m.offset_left = list_x + list_w + COL_GAP
	_help_m.offset_right = -GUTTER
	root.add_child(_help_m)
	var help := U.vbox(16)
	_help_m.add_child(help)
	_help_ort = U.label("", "cap", "faint", "medium")
	_help_ort.uppercase = true
	_help_ort.clip_text = false
	_help_ort.add_theme_font_override("font", Liste.caps_font())
	_help_ort.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	help.add_child(_help_ort)
	_help_title = U.label("", "xl", "text", "title" if UzTheme.strict() else "black", true)
	help.add_child(_help_title)
	_help_text = U.label("", "m", "muted", "regular", true)
	help.add_child(_help_text)
	_help_extra = U.vbox(10)
	var em := U.margin(0, 10, 0, 0)
	em.add_child(_help_extra)
	# Vorschauen passen sich dem Platz an (große Oberfläche: kleiner statt über den Rand).
	var fit := FitBox.new()
	fit.add_child(em)
	help.add_child(fit)
	_build_content()
	_help_cat(sub)
	_reopen_more()


## Die Liste links: oben das Suchfeld, darunter die Kategorien.
func _build_cats() -> void:
	var feld := _suche_feld_neu()
	feld.focus_entered.connect(_on_cat_focus.bind(SUCHE))
	_cats_box.add_child(feld)
	_cats_box.add_child(U.spacer(0, 6, false))
	for c in CATS:
		var item := _Cat.new()
		item.cid = str(c[0])
		item.text = str(c[1])
		item.icon = str(c[2])
		item.selected = item.cid == sub
		item.set_meta("uz_key", "cat:" + item.cid)
		item.focus_entered.connect(_on_cat_focus.bind(item.cid))
		item.picked.connect(func(_cid: String) -> void: _enter_content())
		_cats_box.add_child(item)


## Den Inhalt der gewählten Kategorie (neu) bauen; Liste links und Erklärung bleiben stehen.
func _build_content() -> void:
	if not is_instance_valid(_list):
		return
	U.clear(_list)
	_rows = null
	_group = ""
	_mores.clear()
	match sub:
		SUCHE: _suche_seite()
		"aussehen": _aussehen()
		"klang": _klang()
		"spiele": _spiele()
		"emulation": _emulation()
		"konten": _konten()
		"controller": _controller()
		"imspiel": _im_spiel()
		"aufnahmen": _aufnahmen()
		"medien": _medien()
		"mitteilungen": _mitteilungen()
		"system": _system()
	_tidy_icons(_list)
	var first := Nav.default_in(_list)
	if first:
		first.set_meta("uz_default", true)
		first.set_meta("uz_entry", true)


## In der Liste links: Ein einzelner Schritt zeigt die Kategorie sofort (Antwort im ersten Bild);
## beim schnellen Durchblättern oder Halten erst nach kurzem Verweilen (dann wird nicht jede Seite
## gebaut). Die Erklärung rechts wechselt immer mit der Mitte (_show_cat), nicht vorher – sonst
## passten beide kurz nicht zusammen.
func _on_cat_focus(cid: String) -> void:
	if cid == sub:
		_help_cat(cid)
	_cat_gen += 1
	var gen := _cat_gen
	var jetzt := Time.get_ticks_msec()
	var schnell := jetzt - _cat_ms < CAT_SCHNELL_MS
	_cat_ms = jetzt
	if not schnell:
		_show_cat(cid)
		return
	await get_tree().create_timer(0.12).timeout
	if gen == _cat_gen and is_inside_tree():
		_show_cat(cid)


func _enter_content() -> void:
	var cid := _focused_cat()
	if cid == SUCHE:
		_suche_oeffnen()
		return
	_show_cat(cid)
	var d := Nav.default_in(_list)
	if d:
		Nav.focus(d)


func _focused_cat() -> String:
	var f := Nav.focused()
	if f and is_instance_valid(_cats_box) and _cats_box.is_ancestor_of(f) and "cid" in f:
		return str(f.get("cid"))
	return sub


## LB/RB aus main: nur den Inhalt tauschen.
func switch_sub(_dir := 0) -> bool:
	if not is_instance_valid(_list):
		return false
	var f := Nav.focused()
	_switch_focus = "cats" if f != null and is_instance_valid(_cats_box) and _cats_box.is_ancestor_of(f) else "content"
	var want := resolve_sub(sub)
	sub = "" # erzwingt den Wechsel
	_show_cat(want)
	return true


func focus_default() -> void:
	# Eine Unterseite liegt offen (z. B. nach einem Neuaufbau): ihr nicht den Fokus nehmen.
	if Nav.top_layer() != null:
		return
	var deep: bool = get_meta("uz_deep_link", false)
	set_meta("uz_deep_link", false)
	# Von außen gezielt geöffnet: gleich in den Inhalt. Nach LB/RB: dorthin, wo der Cursor war.
	# Sonst (Bereich betreten): in die Liste links, wie bei der PS5.
	var want := "content" if deep else _switch_focus
	_switch_focus = ""
	if want == "":
		var f := Nav.focused()
		want = "content" if f != null and is_instance_valid(_list) and _list.is_ancestor_of(f) else "cats"
	if want == "cats":
		for it in _cats_box.get_children():
			if "cid" in it and it.cid == sub:
				Nav.focus(it, true)
				return
	var d := Nav.default_in(_list)
	if d:
		Nav.focus(d, true)


## B im Inhalt: zurück in die Liste links (erst von dort geht B zur Leiste oben).
func back_hint() -> String:
	var f := Nav.focused()
	return "Zurück" if f and is_instance_valid(_list) and _list.is_ancestor_of(f) else "Nach oben"


func handle_back() -> bool:
	var f := Nav.focused()
	if f and is_instance_valid(_list) and _list.is_ancestor_of(f):
		for it in _cats_box.get_children():
			if "cid" in it and it.cid == sub:
				Nav.focus(it, true)
				return true
	return false
