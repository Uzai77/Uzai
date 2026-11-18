extends "res://src/ui/sections/settings_system.gd"
## Einstellungen, Schicht über settings_system.gd: die Suche – ein Feld oben in der Liste links
## (wie auf der Konsole), Tastatur oder Handy wie überall in Uzai, Treffer schon beim Tippen in
## der Mitte; ohne Suchwort stehen dort die häufig gebrauchten Einstellungen. A auf einem Treffer
## führt zur Zeile (eine Unterseite öffnet sich mit ihr).

const Keyboard := preload("res://src/ui/layers/keyboard.gd")
const Search := preload("res://src/core/search.gd")

## Häufig gebraucht (ohne Suchwort): [Kategorie, Zeilen-Schlüssel, Unterseite, Titel]. Leerer
## Schlüssel: nur die Kategorie öffnen. Die Titel stehen hier, damit die Seite ohne Index steht.
const HAEUFIG := [
	["klang", "set:klang:Menüklänge", "", "Menüklänge"],
	["aussehen", "set:aussehen:Cover-Größe", "", "Cover-Größe"],
	["controller", "set:controller:Controller testen", "", "Controller testen"],
	["konten", "", "", "Konten"],
	["emulation", "set:emulation:Emulatoren einrichten", "", "Emulatoren einrichten"],
	["system", "more:system:Speicher", "", "Speicher"],
]
## Höchstens so viele Treffer in der Mitte (die Tastatur steht darunter).
const TREFFER_MAX := 8

var _suche_text := ""
var _suche_feld: Control = null
var _suche_kb: WeakRef = null
var _suche_keys := {}            # Schlüssel der zuletzt gezeigten Treffer (neue blenden ein, alte stehen)
var _suche_due := false
var _index_bau := false          # der Index wird gerade gestreckt gebaut (eine Kategorie je Bild)


# --- Das Feld oben in der Liste links -----------------------------------------------------------

## Suchfeld: matte Fläche mit Haarlinie, Lupe und das Suchwort (sonst „Suchen“). Gewählt der
## Zeilen-Cursor wie bei den Kategorien; solange getippt wird, geht die Haarlinie in den Akzent.
class _Suchfeld extends Control:
	signal picked(cid: String)
	const U := preload("res://src/ui/u.gd")
	const Liste := preload("res://src/ui/components/liste.gd")
	var cid := "suche"
	var text := ""
	var selected := false:
		set(v):
			selected = v
			set_meta("uz_selected", v)
			queue_redraw()
	var aktiv := false:            ## die Tastatur ist offen
		set(v):
			if aktiv == v:
				return
			aktiv = v
			if is_inside_tree():
				U.ankommen(self, U.T_ANTWORT, "uz_aktiv").tween_method(_set_akt, _akt, 1.0 if v else 0.0, U.T_ANTWORT)
			else:
				_akt = 1.0 if v else 0.0
	var _akt := 0.0
	var _l: Label
	var _ic: TextureRect

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 58)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		set_meta("uz_hint_a", "Suchen")
		var m := U.margin(20, 0, 16, 0)
		U.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var row := U.hbox(14)
		m.add_child(row)
		_ic = U.icon("search", 22, "muted")
		_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_ic)
		_l = U.ellipsis(U.label("Suchen", "m", "muted", "ui"))
		_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_l)
		set_text(text)
		focus_entered.connect(func() -> void:
			U.etikett(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			U.etikett(self, false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	## Das Suchwort im Feld; leer steht „Suchen“ leise da.
	func set_text(t: String) -> void:
		text = t
		if _l == null:
			return
		_l.text = t if t != "" else tr("Suchen")
		_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if t != "" else Node.AUTO_TRANSLATE_MODE_INHERIT
		# Der Cursor der Marke lässt die Schrift stehen; die Farbe wechselt mit dem Inhalt.
		if not has_focus() or UzTheme.cursor_frame():
			U.set_label_color(_l, "text" if t != "" else "muted")
			_l.remove_meta("uz_col")

	func _set_akt(v: float) -> void:
		_akt = v
		queue_redraw()

	func activate() -> void:
		picked.emit(cid)

	func _draw() -> void:
		var r := maxi(8, UzTheme.r_panel() - 6)
		var rect := Rect2(Vector2.ZERO, size)
		var line := UzTheme.col("line").lerp(UzTheme.col("accent"), _akt)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), r, 1, line), rect)
		Liste.zeilen_auswahl(self, r)


## Das Feld für die Liste links (settings_view.gd baut die Liste).
func _suche_feld_neu() -> Control:
	var f := _Suchfeld.new()
	f.text = _suche_text
	f.selected = sub == SUCHE
	f.set_meta("uz_key", "cat:" + SUCHE)
	f.picked.connect(func(_cid: String) -> void: _suche_oeffnen())
	# Den Index schon bauen, solange der Cursor auf dem Feld steht: das erste Zeichen findet sofort.
	f.focus_entered.connect(func() -> void: _suche_index_bald())
	_suche_feld = f
	return f


# --- Suchen -----------------------------------------------------------------------------------

## Tastatur (oder Handy) öffnen; die Treffer laufen beim Tippen in der Mitte mit.
func _suche_oeffnen() -> void:
	if _suche_kb != null and _suche_kb.get_ref() != null:
		return
	if sub != SUCHE:
		_show_cat(SUCHE)
	var kb = Keyboard.new()
	kb.heading = "Einstellung suchen"
	kb.text = _suche_text
	kb.see_through = true
	var fertig := [false]
	kb.edited.connect(func(t: String) -> void:
		_suche_text = t
		if is_instance_valid(_suche_feld):
			_suche_feld.set_text(t.strip_edges())
		# Mehrere Änderungen in einem Bild (Einfügen vom Handy, schnelles Tippen): einmal neu suchen.
		if not _suche_due:
			_suche_due = true
			_suche_live.call_deferred()
	)
	kb.done.connect(func(t: String) -> void:
		fertig[0] = true
		_suche_text = t.strip_edges()
		if is_instance_valid(_suche_feld):
			_suche_feld.set_text(_suche_text)
		_suche_live()
		# Die Tastatur geht gleich zu: Der erste Treffer bekommt den Cursor, sobald sie weg ist.
		var d := Nav.default_in(_list) if is_instance_valid(_list) else null
		if d:
			Nav.focus(d, true)
	)
	kb.closed.connect(func() -> void:
		if is_instance_valid(_suche_feld):
			_suche_feld.aktiv = false
	)
	_suche_kb = weakref(kb)
	if is_instance_valid(_suche_feld):
		_suche_feld.aktiv = true
	main.open_layer(kb)


## Treffer neu zeigen (sub ist SUCHE): die Seite in der Mitte wird neu gebaut, neue Treffer
## blenden gestaffelt ein, gebliebene stehen still.
func _suche_live() -> void:
	_suche_due = false
	if not is_instance_valid(_list) or sub != SUCHE:
		return
	_build_content()
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0


## Den Index gestreckt bauen, eine Kategorie je Bild (nie ein langes Bild): beginnt, sobald der
## Cursor auf dem Feld steht, nach dem Bild der Antwort. Tippt jemand vorher, baut _suche_index
## den Rest in einem Zug.
func _suche_index_bald() -> void:
	if _index_bau or not _index_cache.is_empty():
		return
	_index_bau = true
	for c in CATS:
		await get_tree().process_frame
		if not is_inside_tree():
			break
		if _index_cache.is_empty() and not _index_teile.has(str(c[0])):
			_suche_index_teil(c)
	_index_bau = false


func _suche_index_teil(c: Array) -> void:
	var part: Array = []
	search_index_cat(c, part)
	_index_teile[str(c[0])] = part


## Alle Zeilen aller Kategorien, einmal angeglichen für die Suche (src/core/search.gd). Der Index
## bleibt, bis sich etwas ändert (_rebuild_keep, Neuaufbau): Zeilen kommen nur mit Änderungen dazu.
func _suche_index() -> Array:
	if _index_cache.is_empty():
		var out: Array = []
		for c in CATS:
			if not _index_teile.has(str(c[0])):
				_suche_index_teil(c)
			out.append_array(_index_teile[str(c[0])])
		# Gesucht wird im Titel und in den Suchwörtern einer Zeile („Lautstärke“ findet Menüklänge).
		_index_cache = Search.prepare(out, suchtext)
	return _index_cache


## Text einer Zeile für die Suche: Titel und Suchwörter, wie sie im Code stehen (deutsch), und in der Sprache der
## Oberfläche. Ohne das fand die englische Oberfläche nichts – „volume“ steht in keinem deutschen Titel.
static func suchtext(s: Dictionary) -> String:
	var teile := PackedStringArray()
	for t: String in [str(s.get("title", "")), str(s.get("such", ""))]:
		if t == "":
			continue
		teile.append(t)
		var u := str(TranslationServer.translate(t))
		if u != t:
			teile.append(u)
	return " ".join(teile)


## Für die Suche über alles (global_search.gd): der fertige Index. Er entsteht gestreckt, eine Kategorie je Bild
## (in einem Zug gemessen 0,12 s, beim ersten Mal 0,4 s – mitten im Tippen), und bleibt, bis sich etwas ändert.
func suche_index_gestreckt() -> Array:
	if _index_cache.is_empty():
		if not _index_bau:
			await _suche_index_bald()
		while _index_bau and is_inside_tree():
			await get_tree().process_frame
	return _suche_index() if is_inside_tree() else []


## Nach einem Neuaufbau kennt der Index die Seiten nicht mehr: beim nächsten Mal neu.
func _suche_index_vergessen() -> void:
	_index_cache.clear()
	_index_teile.clear()


## Die Seite in der Mitte: Treffer zum Suchwort, sonst „Häufig“.
func _suche_seite() -> void:
	var q := _suche_text.strip_edges()
	if q == "":
		_suche_keys.clear()
		_head("Häufig")
		for h in HAEUFIG:
			var cat := str(h[0])
			var hit := { "cat": cat, "key": str(h[1]), "more": str(h[2]), "title": str(h[3]), "cat_name": str(_cat(cat)[1]), "desc": "" }
			var r := _action(str(hit.title), "", str(hit.cat_name), func() -> void: _suche_gehe(hit), str(_cat(cat)[2]))
			r.set_meta("uz_key", "suche:" + str(hit.key) if str(hit.key) != "" else "suche:cat:" + cat)
		return
	var treffer := Search.rank(_suche_index(), q, TREFFER_MAX)
	_head("Treffer" if not treffer.is_empty() else "Suche", q)
	if treffer.is_empty():
		_info_row("Nichts zu „%s“" % q, "Anders schreiben oder kürzer.", "", "search")
		_suche_keys.clear()
		return
	var seen := {}
	var neu := 0
	for s in treffer:
		var hit: Dictionary = s
		var where := str(hit.cat_name) + ((" › " + str(hit.more)) if str(hit.more) != "" else "")
		var r := _action(str(hit.title), str(hit.desc), where, func() -> void: _suche_gehe(hit), str(_cat(str(hit.cat))[2]))
		var k := "suche:" + str(hit.key)
		r.set_meta("uz_key", k)
		seen[k] = true
		# Neu dazugekommene Treffer kommen gestaffelt an („Ankommen“, T_ORT); gebliebene stehen still.
		if not _suche_keys.has(k) and not _indexing:
			r.modulate.a = 0.0
			U.ankommen(r, U.T_ORT, "uz_treffer").tween_property(r, "modulate:a", 1.0, U.T_ORT).set_delay(U.staffel(neu))
			neu += 1
	_suche_keys = seen


## Eine Zeile aus dem Index: nach Schlüssel, sonst die erste der Kategorie bzw. Unterseite.
func _suche_eintrag(cat: String, key: String, more: String) -> Dictionary:
	for s in _suche_index():
		var hit: Dictionary = s[3]
		if str(hit.cat) != cat:
			continue
		if key == "":
			if more == "" and str(hit.more) == "":
				return { "title": str(_cat(cat)[1]), "desc": str(_cat(cat)[3]), "cat": cat, "cat_name": str(_cat(cat)[1]), "more": "", "key": "" }
			if more != "" and str(hit.more) == more:
				return hit
		elif str(hit.key) == key and str(hit.more) == more:
			return hit
	return {}


## Zum Treffer: die Kategorie blendet in der Mitte über, der Cursor steht auf der Zeile; liegt
## sie in einer Unterseite, öffnet die sich mit ihr. Kein Neuaufbau der ganzen Seite.
func _suche_gehe(hit: Dictionary) -> void:
	var cat := str(hit.cat)
	_show_cat(cat)
	await get_tree().process_frame
	if not is_inside_tree() or sub != cat:
		return
	if str(hit.key) == "":
		var d := Nav.default_in(_list)
		if d:
			Nav.focus(d, true)
		return
	focus_row(str(hit.key), str(hit.more))
