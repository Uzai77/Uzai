extends "res://src/ui/sections/section.gd"
## Einstellungen, unterste Schicht: die Bausteine aller Seiten – Liste links, Gruppenkarten, Zeilen
## (Schalter, Auswahl, Regler, Text, Pfad, Aktion, Unterseite), die Erklärung rechts und das
## Verzeichnis für die globale Suche.
## Die Einstellungen bestehen aus Schichten; jede erbt von der darunter und nutzt nur sie:
## settings_bausteine.gd → settings_unterseiten.gd → settings_spiele.gd → settings_konten.gd →
## settings_medien.gd → settings_system.gd → settings_view.gd. Seiten verschiedener Schichten rufen
## sich nicht gegenseitig auf; nur die Bausteine und Unterseiten sind gemeinsam.

const Sheet := preload("res://src/ui/layers/sheet.gd")
const Preview := preload("res://src/ui/components/setting_preview.gd")
const Liste := preload("res://src/ui/components/liste.gd")

## [id, Name, Symbol, eine Zeile für die rechte Spalte] – nach Häufigkeit geordnet, Seltenes
## (System) zuletzt wie auf der Konsole. Die Suche steht darüber (settings_suche.gd).
const CATS := [
	["aussehen", "Aussehen", "palette", "Farben, Schrift, Cover, Startseite."],
	["klang", "Klang", "volume", "Menüklänge, Musik, Tonausgabe."],
	["spiele", "Spiele", "games", "Quellen, Installieren, Bilder."],
	["emulation", "Emulation", "chip", "Systeme, Emulatoren, Bildfilter."],
	["konten", "Konten", "user", "Profil und Dienste."],
	["controller", "Controller", "controller", "Tasten, Vibration, Koppeln."],
	["imspiel", "Im Spiel", "play", "Spielstart, Guide, Bildrate ×2, Remote Play."],
	["aufnahmen", "Aufnahmen", "video", "Clips und Übertragung."],
	["medien", "Medien", "tv", "Videos, Filme und Serien."],
	["mitteilungen", "Mitteilungen", "bell", "Pop-ups von Freunden, Shop und Erfolgen."],
	["system", "System", "power", "Sprache, Daten, Hilfe, über Uzai."],
]

## Kennung der Suche in der Liste links (keine Kategorie: nicht in CATS, nicht in der Leiste).
const SUCHE := "suche"

## Breiten bei 1920 px; bei großer Oberfläche (bis 150 %) schrumpfen Liste und Erklärung zuerst.
const CAT_W := 300.0
const HELP_W := 544.0
const COL_GAP := 32.0

var _list: VBoxContainer          # Inhalt der gewählten Kategorie
var _rows: VBoxContainer          # Zeilen der Gruppenkarte, die gerade gefüllt wird
var _scroll: ScrollContainer
var _cats_box: VBoxContainer
var _help_m: MarginContainer
var _help_ort: Label              # klein über dem Titel rechts: Kategorie · Gruppe
var _help_title: Label
var _help_text: Label
var _help_extra: VBoxContainer
var _sheet = null                 # Unterseite, die gerade gefüllt wird (sonst die Hauptseite)
var _open_sheet: WeakRef = null   # offene Unterseite (für Auffrischen nach einer Änderung)
var _mores := {}                  # Titel → Füllfunktion der Unterseiten der gewählten Kategorie
var _indexing := false            # search_index() baut gerade alle Seiten (ohne sie zu zeigen)
var _group := ""                  # Überschrift der Gruppe, die gerade gefüllt wird (rechts klein über dem Titel)
var _index_cache: Array = []      # Suchindex (settings_suche.gd); leer nach jeder Änderung, dann neu gebaut
var _index_teile := {}            # Zeilen je Kategorie für den Index (eine Kategorie je Bild gebaut)


func _cat(cid: String) -> Array:
	for c in CATS:
		if c[0] == cid:
			return c
	return CATS[0]


## In einer Karte beginnen alle Titel an derselben Stelle: Haben nur manche Zeilen ein Symbol,
## fallen die Symbole dort weg (früher sprangen die Titel zwischen zwei Einrückungen).
func _tidy_icons(box: Control) -> void:
	for card in box.get_children():
		if not (card is _Card):
			continue
		var rows: Array = (card as _Card).rows.get_children().filter(func(r): return "icon_name" in r)
		var with_icon := rows.filter(func(r): return str(r.get("icon_name")) != "").size()
		if with_icon > 0 and with_icon < rows.size():
			for r in rows:
				r.set("icon_name", "")


## Kategorie wechseln, ohne die Seite neu zu bauen: Der Inhalt blendet weich über (ohne Leerbild).
func _show_cat(cid: String) -> void:
	if cid == sub or not is_instance_valid(_list):
		return
	sub = cid
	for it in _cats_box.get_children():
		if "cid" in it:
			it.selected = it.cid == cid
	# Erst gehen, dann kommen (Takt): die alte Seite verblasst in einer Hülle an ihrem Platz, die
	# neue blendet gleich danach an derselben Stelle auf. Erklärung rechts und Mitte wechseln im
	# selben Bild. Ohne Gleiten: Schrift kann nur in ganzen Pixeln gleiten, ein paar Pixel Weg
	# kämen als einzelne Rucke noch 300 ms später an.
	U.abgang(_list, 0)
	_build_content()
	_scroll.scroll_vertical = 0
	_help_cat(cid)
	_ankunft_gestaffelt(_list, U.NACH_WEG)


## Die Zeilen einer neuen Seite kommen gestaffelt an (Kurve „Ankommen“, T_ORT): die erste Gruppe
## im ersten Bild nach dem Abgang, jede weitere U.STAFFEL später (höchstens STAFFEL_MAX Glieder,
## ruhig ohne Staffel). Schrift gleitet nicht – nur Deckkraft.
func _ankunft_gestaffelt(box: Control, verz: float) -> void:
	var i := 0
	for ch in box.get_children():
		if not (ch is Control):
			continue
		var c := ch as Control
		U.stop(c, "uz_cat")
		c.modulate.a = 0.0
		U.ankommen(c, U.T_ORT, "uz_cat").tween_property(c, "modulate:a", 1.0, U.T_ORT).set_delay(verz + U.staffel(i))
		i += 1



func _help_cat(cid: String) -> void:
	# Die kleine Zeile über dem Titel übersetzt sich nicht selbst (sie trägt sonst zusammengesetzte Orte): hier von Hand.
	if cid == SUCHE:
		_help("Suchen", "Tastatur oder Handy.", null, tr("Einstellungen"))
		return
	var c := _cat(cid)
	_help(str(c[1]), str(c[3]), null, tr("Einstellungen"))


# --- Liste links ---------------------------------------------------------------------

## Eine Kategorie: Symbol und Wort, 64 px hoch. Gewählt und der Cursor steht im Inhalt: ein
## kurzer Strich im Akzent links (Marke) bzw. eine leise Fläche; er kommt und geht im Cursor-Takt.
## Steht der Cursor darauf: der Zeilen-Cursor.
class _Cat extends Control:
	signal picked(cid: String)
	const U := preload("res://src/ui/u.gd")
	var cid := ""
	var text := ""
	var icon := ""
	var selected := false:
		set(v):
			selected = v
			set_meta("uz_selected", v)
			_strich_takt()
	var _strich := 0.0            ## 0 … 1: der Strich der gewählten Kategorie (ohne Cursor darauf)

	## Der Strich kommt in T_ANTWORT und geht in T_ANTWORT (Kurve „Gehen“), wie ein Cursor.
	func _strich_takt() -> void:
		var want := 1.0 if selected and not has_focus() else 0.0
		if not is_inside_tree() or is_equal_approx(_strich, want):
			_strich = want
			queue_redraw()
			return
		var tw := U.ankommen(self, U.T_ANTWORT, "uz_strich") if want > 0.5 else U.weg(self, "uz_strich")
		tw.tween_method(func(v: float) -> void:
			_strich = v
			queue_redraw(), _strich, want, U.T_ANTWORT)

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 64)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		set_meta("uz_hint_a", "Öffnen")
		var m := U.margin(20, 0, 16, 0)
		U.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var row := U.hbox(16)
		m.add_child(row)
		var ic := U.icon(icon, 24, "muted")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var l := U.label(text, "m", "text", "ui_bold")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.clip_text = false
		row.add_child(l)
		_strich = 1.0 if selected and not has_focus() else 0.0
		focus_entered.connect(func() -> void:
			U.etikett(self, true)
			_strich_takt()
		)
		focus_exited.connect(func() -> void:
			U.etikett(self, false)
			_strich_takt()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func activate() -> void:
		picked.emit(cid)

	func _draw() -> void:
		var r := maxi(8, UzTheme.r_panel() - 6)
		var h := 28.0 * _strich
		var strich := Rect2(0, size.y * 0.5 - h * 0.5, 3, h)
		# Eckig (Marke): gewählt nur ein kurzer Strich im Akzent links (wie der Strich unter dem
		# Reiter), keine Fläche; der Cursor ist der Zeilen-Cursor wie im Guide.
		if UzTheme.strict():
			if _strich > 0.001:
				draw_rect(strich, UzTheme.col("accent", _strich))
			Liste.zeilen_auswahl(self, r)
			return
		if _strich > 0.001:
			draw_style_box(UzTheme.box(UzTheme.col("text", 0.06 * _strich), r), Rect2(Vector2.ZERO, size))
			draw_rect(Rect2(strich.position, Vector2(4, h)), UzTheme.col("mark", _strich))
		U.draw_focus(self, r)


# --- Bausteine -------------------------------------------------------------------

## Eine Gruppenkarte: ruhige Glasfläche, feine Linien zwischen den Zeilen (nicht an der Auswahl).
class _Card extends MarginContainer:
	var rows: VBoxContainer

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(k, 6)
		rows = VBoxContainer.new()
		rows.add_theme_constant_override("separation", 0)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rows)

	func _draw() -> void:
		# Eckig (Marke): keine Karte – Abschnitte trennen Etikett und Haarlinie wie im Guide.
		if UzTheme.strict():
			return
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))
		var kids: Array[Control] = []
		for ch in rows.get_children():
			if ch is Control and (ch as Control).visible:
				kids.append(ch as Control)
		for i in range(1, kids.size()):
			var a := kids[i - 1]
			var b := kids[i]
			var fa: float = a.get_meta("uz_f", 0.0)
			var fb: float = b.get_meta("uz_f", 0.0)
			var alpha := 0.07 * (1.0 - maxf(fa, fb))
			if alpha <= 0.002:
				continue
			var y := rows.position.y + b.position.y
			draw_line(Vector2(rows.position.x + 20.0, y), Vector2(rows.position.x + rows.size.x - 20.0, y), UzTheme.col("text", alpha), 1.0)


## Wohin neue Zeilen kommen: die offene Unterseite oder die Hauptseite.
func _container() -> VBoxContainer:
	return _sheet.content if _sheet != null else _list


func _card_rows() -> VBoxContainer:
	if _rows == null or not is_instance_valid(_rows):
		var card := _Card.new()
		_container().add_child(card)
		_rows = card.rows
	return _rows


## Zeile in die aktuelle Gruppe. help_title ersetzt den Titel rechts, extra baut eine Vorschau.
## In einer Unterseite steht die Erklärung unten in der Leiste (ohne Vorschau).
func _add(r: Control, desc: String, help_title := "", extra: Callable = Callable()) -> Control:
	if not r.has_meta("uz_key"):
		r.set_meta("uz_key", "set:%s:%s%s" % [sub, (str(_sheet.heading) + ":") if _sheet != null else "", r.get("title")])
	if "focus_radius" in r:
		r.set("focus_radius", maxi(UzTheme.radius, UzTheme.r_panel() - 6))
	if "compact" in r:
		r.set("compact", true)
	# Rechts gibt es neben den Zeilen nichts mehr (nur die Erklärung): nicht nach oben springen.
	r.set_meta("uz_lr_block", true)
	# Das Steuerkreuz bewegt zwischen den Spalten, Werte ändert A (setting_row.gd nur_a): links
	# geht zurück – auf der Hauptseite zu den Kategorien, in einer Unterseite aus ihr hinaus wie B.
	if "nur_a" in r:
		r.set("nur_a", true)
	if _sheet != null and _sheet.has_method("nav_command"):
		var zur: WeakRef = weakref(_sheet)
		r.set_meta("uz_links_zurueck", func() -> void:
			var sh = zur.get_ref()
			if sh != null and not sh.get("_closing"):
				sh.nav_command("b"))
	var t := help_title if help_title != "" else str(r.get("title"))
	var show: Callable
	if _sheet != null:
		var sw: WeakRef = weakref(_sheet)
		var m: Node = main
		var key := str(r.get_meta("uz_key"))
		show = func() -> void:
			var sh = sw.get_ref()
			if sh:
				sh.set_help(desc)
			if m:
				m.set_meta("uz_set_more_key", key)
	else:
		# Rechts klein darüber, wo die Zeile steht: „Aussehen · Stil“.
		var ort := tr(str(_cat(sub)[1])) if sub != SUCHE else tr("Suchen")
		if _group != "":
			ort += "  ·  " + tr(_group)
		if desc == "" and help_title == "" and not extra.is_valid() and sub != SUCHE:
			# Ohne Satz und Vorschau stünde rechts nur der Titel der Zeile noch einmal: Dort bleibt die
			# Kategorie stehen. In der Suche sagt der Ort über dem Titel, wo die Zeile zu Hause ist.
			var cid := sub
			show = func() -> void: _help_cat(cid)
		else:
			show = func() -> void: _help(t, desc, extra, ort)
	r.focus_entered.connect(show)
	if r.has_signal("changed"):
		r.connect("changed", func(_v: Variant) -> void:
			if is_instance_valid(r) and r.has_focus():
				show.call()
		)
	var holder := _card_rows()
	holder.add_child(r)
	var card := holder.get_parent() as Control
	r.draw.connect(card.queue_redraw)
	return r


func _head(text: String, extra := "") -> void:
	var box := _container()
	var first := box.get_child_count() == 0
	if _sheet == null:
		_group = text
	if UzTheme.strict():
		# Abschnitt wie im Guide: über jedem (außer dem ersten) eine Haarlinie, dann das Etikett
		# in kleinen Versalien; die Zahl rechts leise dahinter.
		if not first:
			var lm := U.margin(20, 0, 20, 0)
			lm.add_child(Liste.linie(12))
			box.add_child(lm)
		var sm := U.margin(22, 10 if first else 2, 22, 6)
		sm.add_child(Liste.abschnitt(text, extra))
		box.add_child(sm)
		_rows = null
		return
	var m := U.margin(22, 16 if first else 26, 22, 10)
	var row := U.hbox(12)
	m.add_child(row)
	row.add_child(U.label(text, "s", "muted", "bold"))
	if extra != "":
		row.add_child(U.spacer())
		row.add_child(U.label(extra, "s", "faint", "medium"))
	box.add_child(m)
	_rows = null


## Eine Unterseite: Zeile mit dem Titel, A öffnet sie von rechts. fill baut ihre Zeilen mit denselben
## Bausteinen (_toggle, _choice, _text …) wie die Hauptseite. Der Pfeil rechts sagt „geht weiter“;
## drei Punkte dazu („Steam …“) sagten es zweimal. Nur „Mehr …“ behält sie: Dort sind sie das Wort.
func _more(t: String, desc: String, value_text: String, icon: String, fill: Callable, tone := "") -> Control:
	_mores[t] = fill
	var r := _action(t + " …" if t == "Mehr" else t, desc, value_text, func() -> void: open_more(t), icon, tone)
	r.set_meta("uz_key", "more:%s:%s" % [sub, t])
	return r


## „Mehr …“ am Ende einer Kategorie: Seltenes, eine Ebene tiefer. Eigene Karte ohne Überschrift.
## Nur auf Hauptseiten – eine Unterseite bekommt keine zweite darunter (höchstens zwei Ebenen).
func _mehr(fill: Callable) -> Control:
	_rows = null
	_group = ""
	return _more("Mehr", "", "", "more", fill)


## Unterseite der gewählten Kategorie öffnen (auch von außen, z. B. „Remote Play Together“).
func open_more(t: String, focus_key := "") -> void:
	var fill: Callable = _mores.get(t, Callable())
	if not fill.is_valid():
		return
	var s = Sheet.new()
	s.setup(t, str(_cat(sub)[1]), 900)
	s.help_on = true
	s.fill_func = func(sheet) -> void:
		var keep_sheet = _sheet
		var keep_rows := _rows
		_sheet = sheet
		_rows = null
		fill.call()
		_tidy_icons(sheet.content)
		_sheet = keep_sheet
		_rows = keep_rows
	var m: Node = main
	var cat := sub
	m.set_meta("uz_set_more", { "cat": cat, "title": t })
	s.closed.connect(func() -> void:
		if is_instance_valid(m) and m.has_meta("uz_set_more") and str((m.get_meta("uz_set_more") as Dictionary).get("title", "")) == t:
			m.remove_meta("uz_set_more")
			m.remove_meta("uz_set_more_key")
	)
	_open_sheet = weakref(s)
	main.open_layer(s)
	if focus_key != "":
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(s) and is_instance_valid(s.content):
			for c in Nav.focusables(s.content):
				if str(c.get_meta("uz_key", "")) == focus_key:
					Nav.focus(c, true)
					break


## Nach einem Neuaufbau der ganzen Oberfläche (Farbschema, Ecken, Schrift …) liegt die Unterseite,
## in der die Änderung passiert ist, wieder offen – mit dem Cursor auf derselben Zeile.
func _reopen_more() -> void:
	if main == null or not main.has_meta("uz_set_more"):
		return
	var info: Dictionary = main.get_meta("uz_set_more")
	if str(info.get("cat", "")) != sub:
		return
	var key := str(main.get_meta("uz_set_more_key", ""))
	# Erst ein Bild warten: Die alte Unterseite (mit der alten Oberfläche) ist dann wirklich weg.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and Nav.top_layer() == null and main.has_meta("uz_set_more"):
		open_more(str(info.get("title", "")), key)


# --- Für die globale Suche (src/ui/layers/global_search.gd) ------------------------------------

## Alle Zeilen aller Kategorien, auch die in Unterseiten: [{ title, desc, cat, cat_name, more, key,
## path (Config-Schlüssel), such (weitere Suchwörter, Meta "uz_such") }].
## Die Seiten werden dafür wie sonst gebaut, nur nicht gezeigt – so passt die Suche immer zu dem,
## was dort steht, ohne zweite Liste.
func search_index() -> Array:
	var out: Array = []
	for c in CATS:
		search_index_cat(c, out)
	return out


## Eine Kategorie für den Index bauen (Seite und ihre Unterseiten), ohne sie zu zeigen; die
## Zeilen kommen nach out. Die Suche in den Einstellungen baut so eine Kategorie je Bild.
func search_index_cat(c: Array, out: Array) -> void:
	var keep := [sub, _list, _rows, _sheet, _mores.duplicate(), _group]
	_indexing = true
	sub = str(c[0])
	_list = U.vbox(0)
	_rows = null
	_sheet = null
	_mores.clear()
	_build_content()
	_index_rows(_list, c, "", out)
	for t in _mores.keys():
		var box := _IndexSheet.new()
		box.heading = str(t)
		_sheet = box
		_rows = null
		(_mores[t] as Callable).call()
		_index_rows(box.content, c, str(t), out)
		box.content.free()
	_sheet = null
	_list.free()
	sub = keep[0]
	_list = keep[1]
	_rows = keep[2]
	_sheet = keep[3]
	_mores = keep[4]
	_group = keep[5]
	_indexing = false


func _index_rows(box: Node, cat: Array, more: String, out: Array) -> void:
	for ch in box.get_children():
		if ch is SettingRow and ch.has_meta("uz_key") and str(ch.get("title")) != "":
			out.append({ "title": str(ch.get("title")).trim_suffix(" …"), "desc": str(ch.get("desc")), "cat": str(cat[0]),
				"cat_name": str(cat[1]), "more": more, "key": str(ch.get_meta("uz_key")), "path": str(ch.get_meta("uz_path", "")),
				"such": str(ch.get_meta("uz_such", "")) })
		else:
			_index_rows(ch, cat, more, out)


## Platz für die Zeilen einer Unterseite beim Bauen des Index (wie Sheet: heading und content).
class _IndexSheet extends RefCounted:
	var heading := ""
	var content := VBoxContainer.new()


## Von der Suche: Zeile wählen (liegt sie in einer Unterseite, öffnet sich diese mit der Zeile).
func focus_row(key: String, more := "") -> void:
	if more != "":
		open_more(more, key)
		return
	if not is_instance_valid(_list):
		return
	for c in Nav.focusables(_list):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return


func _help(t: String, d: String, extra: Variant = null, ort := "") -> void:
	if not is_instance_valid(_help_title):
		return
	# Steht schon genau das da (mehrere Zeilen ohne eigenen Satz hintereinander): nichts blendet neu.
	var gleich: bool = extra == null and _help_extra.get_child_count() == 0 and _help_title.text == t and _help_text.text == d
	if gleich and (not is_instance_valid(_help_ort) or _help_ort.text == ort):
		return
	if is_instance_valid(_help_ort):
		_help_ort.text = ort
		_help_ort.visible = ort != ""
	_help_title.text = t
	_help_text.text = d
	_help_text.visible = d != ""
	U.clear(_help_extra)
	var c: Control = null
	if extra is Callable and (extra as Callable).is_valid():
		c = (extra as Callable).call()
	elif extra is Control:
		c = extra as Control
	if c:
		_help_extra.add_child(c)
	# Rechts wechselt der Inhalt weich: kurz zurücknehmen und im selben Takt wie die Mitte (T_ORT)
	# aufblenden, damit beide zusammen ankommen. Ohne Nachrücken (ganze Pixel rucken, siehe _show_cat).
	_help_m.modulate.a = minf(_help_m.modulate.a, 0.45)
	_help_m.add_theme_constant_override("margin_top", 26)
	U.ankommen(_help_m, U.T_ORT, "uz_help").tween_property(_help_m, "modulate:a", 1.0, U.T_ORT)


func _toggle(path: String, t: String, desc: String, extra: Callable = Callable()) -> Control:
	var r = SettingRow.new()
	r.setup("toggle", t, desc, bool(Config.get_value(path, false)))
	r.set_meta("uz_path", path)
	r.changed.connect(func(v: Variant) -> void: Config.set_value(path, bool(v)))
	return _add(r, desc, "", extra)


func _choice(path: String, t: String, desc: String, options: Array, extra: Callable = Callable()) -> Control:
	var r = SettingRow.new()
	r.setup("choice", t, desc, Config.get_value(path))
	r.set_meta("uz_path", path)
	r.options = options
	r.changed.connect(func(v: Variant) -> void:
		Config.set_value(path, v)
		# Wahlen, von denen weitere Zeilen abhängen: Seite neu aufbauen.
		# (theme.* baut ohnehin die ganze Oberfläche neu.)
		if path in ["system.music_mode", "youtube.cookies"]:
			_rebuild_keep.call_deferred()
	)
	return _add(r, desc, "", extra)


func _slider(path: String, t: String, desc: String, lo: float, hi: float, st: float, fmt := "%d %%", scale := 100.0) -> Control:
	var r = SettingRow.new()
	r.setup("slider", t, desc, float(Config.get_value(path, lo)))
	r.set_meta("uz_path", path)
	r.min_v = lo
	r.max_v = hi
	r.step = st
	r.fmt = fmt
	r.fmt_scale = scale
	r.changed.connect(func(v: Variant) -> void: Config.set_value(path, float(v)))
	return _add(r, desc)


func _action(t: String, desc: String, value_text: String, cb: Callable, icon := "", tone := "", extra: Callable = Callable(), help_title := "") -> Control:
	var r = SettingRow.new()
	r.setup("action", t, desc)
	r.value_text = value_text
	r.on_activate = cb
	r.icon_name = icon
	r.tone = tone
	return _add(r, desc, help_title, extra)


## Nur zum Lesen: kein Pfeil, A tut nichts (früher sahen solche Zeilen aus wie Knöpfe).
func _info_row(t: String, desc: String, value_text: String, icon := "", extra: Callable = Callable()) -> Control:
	var r = SettingRow.new()
	r.setup("info", t, desc)
	r.value_text = value_text
	r.icon_name = icon
	return _add(r, desc, "", extra)


## Wo man Schlüssel bekommt: die Handy-Eingabe bietet den Link direkt an.
const KEY_LINKS := {
	"accounts.steam_key": "https://steamcommunity.com/dev/apikey",
	"accounts.ra_key": "https://retroachievements.org/settings",
	"accounts.sgdb_key": "https://www.steamgriddb.com/profile/preferences/api",
	"accounts.spotify_client_id": "https://developer.spotify.com/dashboard",
	"accounts.discord_client_id": "https://discord.com/developers/applications",
	"accounts.discord_client_secret": "https://discord.com/developers/applications",
	"accounts.twitch_client_id": "https://dev.twitch.tv/console/apps",
	"movies.tmdb_key": "https://www.themoviedb.org/settings/api",
}


func _text(path: String, t: String, desc: String, secret := false, placeholder := "Nicht eingetragen") -> Control:
	var cur := str(Config.get_value(path, ""))
	var shown := placeholder if cur == "" else ("•••• " + cur.right(4) if secret else cur)
	var r := _action(t, desc, shown, func() -> void: _edit_text(path, t, secret), "", "faint" if cur == "" else "")
	r.set_meta("uz_path", path)
	return r


## Text in den Einstellungen per Tastatur (oder Handy) ändern.
func _edit_text(path: String, t: String, secret := false) -> void:
	main.open_keyboard(t, str(Config.get_value(path, "")), func(v: String) -> void:
		Config.set_value(path, v.strip_edges())
		_rebuild_keep()
	, secret, str(KEY_LINKS.get(path, "")))


func _path(path: String, t: String, desc: String, want_dir: bool, exts: Array = [], on_set: Callable = Callable(), note := "") -> Control:
	var cur := str(Config.get_value(path, ""))
	var shown := cur if cur != "" else "Nicht festgelegt"
	var picked := func(p: String) -> void:
		Config.set_value(path, p)
		if on_set.is_valid():
			on_set.call(p)
		_rebuild_keep()
	var r := _action(t, desc, shown, func() -> void:
		main.open_file_browser(t, want_dir, picked, exts, cur.get_base_dir() if not want_dir and cur != "" else cur)
	, "folder" if want_dir else "file", "faint" if cur == "" else "", func() -> Control: return Preview.path_box(cur, note))
	r.set_meta("uz_path", path)
	return r


var _voice_shown := ""


func _on_voice_changed() -> void:
	var now := "%s|%s|%s|%s" % [Voice.state, Voice.error, DiscordChat.state, DiscordChat.error]
	if not (sub in ["konten", "mitteilungen", "aufnahmen"]) or now == _voice_shown or not is_visible_in_tree():
		return
	_voice_shown = now
	_rebuild_keep()


var _epic_shown := ""


## Epic-Konto angemeldet, abgeglichen oder abgelaufen: Konten bzw. Spiele zeigen es gleich. Liegt
## gerade eine Ebene darüber (die Anmeldung), erst nach deren Schließen.
func _on_epic_changed() -> void:
	var acc = Library.epic_account
	var now := "%s|%s|%d" % [acc.state, acc.last_error, acc.owned_count()]
	if not (sub in ["konten", "spiele"]) or now == _epic_shown or not is_visible_in_tree():
		return
	var sh = _open_sheet.get_ref() if _open_sheet else null
	var host: Node = main.layer_host if main else null
	if host:
		for i in range(host.get_child_count() - 1, -1, -1):
			var top := host.get_child(i)
			if top.get("_closing") == true:
				continue
			if top != sh and top.has_signal("closed"):
				if not top.is_connected("closed", _on_epic_changed):
					top.connect("closed", _on_epic_changed, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
				return
			break
	_epic_shown = now
	_rebuild_keep()


## Inhalt der gewählten Kategorie (neu) bauen. Die Seiten kennt erst settings_view.gd, das diese
## Funktion überschreibt; hier rufen sie die Bausteine (Auffrischen, Suche).
func _build_content() -> void:
	pass


## Nach einer Änderung: Hauptseite neu (Werte auf den „…“-Zeilen) und eine offene Unterseite
## auffrischen; sonst die Seite neu bauen und den Cursor auf derselben Zeile lassen.
func _rebuild_keep() -> void:
	_index_cache.clear()
	_index_teile.clear()
	var sh = _open_sheet.get_ref() if _open_sheet else null
	if sh != null and is_instance_valid(sh) and sh.is_inside_tree() and not sh.get("_closing"):
		_build_content()
		sh.refill()
		return
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f else ""
	_build_content()
	await get_tree().process_frame
	for c in Nav.focusables(self):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return


func _system_color(sys: Dictionary) -> Color:
	var c := str(sys.get("color", ""))
	return Color(c) if c.is_valid_html_color() else UzTheme.col("faint")
