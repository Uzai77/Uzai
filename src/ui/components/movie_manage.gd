extends Control
## Addons und Plugins verwalten (wie die Addon- und Plugin-Seiten von Nuvio TV).
##
## Links die Liste in ruhigen Glaskarten: oben Installieren (Adresse über die Bildschirmtastatur
## oder vom Handy) und Aktualisieren, darunter jedes Addon mit Schalter, Pfeilen zum Verschieben
## und Entfernen. Rechts erklärt Uzai, was gerade gewählt ist – beim Addon mit Katalogen, Arten
## und Adresse. Plugins: global an/aus, Verzeichnisse hinzufügen, jede Quelle einzeln schalten.

const U := preload("res://src/ui/u.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const SheetL := preload("res://src/ui/layers/sheet.gd")
const Liste := preload("res://src/ui/components/liste.gd")

const LIST_W := 1060.0
const RES_NAMES := { "catalog": "Kataloge", "meta": "Angaben", "stream": "Quellen", "subtitles": "Untertitel", "addon_catalog": "Addon-Kataloge" }

const Main := preload("res://src/main.gd")
var main: Main
var page := "addons"
var _list: VBoxContainer
var _help_m: MarginContainer
var _help: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vw := U.view_size().x
	var list_w := clampf(vw - UzTheme.GUTTER * 2.0 - 48.0 - 520.0, 640.0, LIST_W)
	_list = U.vbox(14)
	_list.set_meta("uz_group", "mmanage:" + page)
	var lm := U.margin(UzTheme.GUTTER - 20, 6, 20, 140)
	lm.add_child(_list)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 150.0)
	sc.anchor_bottom = 1.0
	sc.offset_right = UzTheme.GUTTER + list_w
	lm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lm)
	add_child(sc)
	_help_m = U.margin(0, 24, 0, 30)
	_help_m.anchor_right = 1.0
	_help_m.anchor_bottom = 1.0
	_help_m.offset_left = UzTheme.GUTTER + list_w + 48.0
	_help_m.offset_right = -UzTheme.GUTTER
	add_child(_help_m)
	_help = U.vbox(14)
	_help_m.add_child(_help)
	if page == "plugins":
		_plugins()
	else:
		_addons()
	Nav.focus_moved.connect(_on_focus)
	_show_help(null)


func _on_focus(c: Control) -> void:
	if c != null and is_ancestor_of(c):
		_show_help(c)


# --- Bausteine ---------------------------------------------------------------------------------

## Glaskarte für eine Gruppe von Zeilen (wie in den Einstellungen).
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
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))


## Eine wählbare Fläche mit Inhalt (Name und Angaben eines Addons): hell, wenn gewählt.
class _Info extends Control:
	signal activated
	var content: Control

	func _init(c: Control) -> void:
		content = c
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m := MarginContainer.new()
		for k in [["margin_left", 16], ["margin_right", 16], ["margin_top", 12], ["margin_bottom", 12]]:
			m.add_theme_constant_override(k[0], k[1])
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.add_child(c)
		add_child(m)
		m.minimum_size_changed.connect(func() -> void: custom_minimum_size.y = m.get_combined_minimum_size().y)
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

	func _ready() -> void:
		custom_minimum_size.y = (get_child(0) as Control).get_combined_minimum_size().y

	func activate() -> void:
		activated.emit()

	func _draw() -> void:
		Liste.zeilen_auswahl(self, maxi(UzTheme.radius, UzTheme.r_panel() - 8))


func _card() -> VBoxContainer:
	var c := _Card.new()
	_list.add_child(c)
	return c.rows


func _head(text: String, extra := "") -> void:
	var m := U.margin(22, 16, 22, 0)
	var row := U.hbox(12)
	m.add_child(row)
	row.add_child(U.label(text, "s", "muted", "bold"))
	if extra != "":
		row.add_child(U.spacer())
		row.add_child(U.label(extra, "s", "faint", "medium"))
	_list.add_child(m)


## Hilfe rechts: help = [Titel, Text, Zusatzzeilen?] in der Meta „uz_help“ des Elements.
func _show_help(c: Control) -> void:
	if not is_instance_valid(_help):
		return
	var h: Array = []
	if c != null and c.has_meta("uz_help"):
		h = c.get_meta("uz_help")
	else:
		h = _page_help()
	U.clear(_help)
	_help.add_child(U.label(str(h[0]), "xl", "text", "black", true))
	if h.size() > 1 and str(h[1]) != "":
		_help.add_child(U.label(str(h[1]), "m", "muted", "regular", true))
	if h.size() > 2:
		var box := U.vbox(10)
		var bm := U.margin(0, 10, 0, 0)
		bm.add_child(box)
		_help.add_child(bm)
		for line in h[2]:
			var l: Array = line
			var row := U.vbox(2)
			row.add_child(U.label(str(l[0]), "s", "faint", "bold"))
			row.add_child(U.label(str(l[1]), "m", "text", "regular", true))
			box.add_child(row)
	_help_m.modulate.a = minf(_help_m.modulate.a, 0.45)
	U.tw(_help_m, "uz_help").tween_property(_help_m, "modulate:a", 1.0, U.T_BASE)


func _page_help() -> Array:
	if page == "plugins":
		return ["Plugins", "Keine Plugins enthalten. Für deine Quellen bist du verantwortlich."]
	return ["Addons", "Außer Cinemeta keine Addons enthalten. Für deine Quellen bist du verantwortlich."]


# --- Addons ------------------------------------------------------------------------------------

func _addons() -> void:
	var top := U.margin(20, 4, 20, 4)
	var row := U.hbox(14)
	row.set_meta("uz_group", "addons-kopf")
	top.add_child(row)
	var inst := U.button("Addon installieren", "plus", "primary")
	inst.set_meta("uz_key", "addons:installieren")
	inst.set_meta("uz_default", true)
	inst.set_meta("uz_hint_a", "Adresse eingeben")
	inst.set_meta("uz_help", ["Addon installieren", "Adresse des Addons (manifest.json oder stremio://)."])
	inst.pressed.connect(func() -> void: ask_install(main))
	row.add_child(inst)
	var ref := U.button("Aktualisieren", "refresh")
	ref.set_meta("uz_key", "addons:aktualisieren")
	ref.set_meta("uz_help", ["Aktualisieren", ""])
	ref.pressed.connect(func() -> void:
		Toasts.show_toast("Addons werden aktualisiert", "", "refresh", { "quiet": true })
		var res: Variant = await Movies.refresh_addons()
		if str(res) != "" and res != null:
			Toasts.show_toast("Nicht alle Addons erreichbar", str(res), "warning", { "ms": 6000 })
		else:
			Toasts.show_toast("Addons aktualisiert", U.plural(Movies.addons.size(), "Addon", "Addons"), "check", { "quiet": true })
	)
	row.add_child(ref)
	_list.add_child(top)
	var on := 0
	for a in Movies.addons:
		if bool(a.get("enabled", true)):
			on += 1
	_head("Installiert", "%d von %d eingeschaltet" % [on, Movies.addons.size()] if not Movies.addons.is_empty() else "")
	if Movies.addons.is_empty():
		var em := U.margin(22, 6, 22, 0)
		em.add_child(U.label("Keine Addons.", "m", "muted", "regular", true))
		_list.add_child(em)
		return
	for i in Movies.addons.size():
		_addon_row(Movies.addons[i], i)


func _addon_row(a: Dictionary, i: int) -> void:
	var aid := str(a.get("id", ""))
	var name_ := str(a.get("name", aid))
	var enabled := bool(a.get("enabled", true))
	var rows := _card()
	var line := U.hbox(10)
	rows.add_child(line)
	var body := U.hbox(18)
	var badge := _logo(a)
	body.add_child(badge)
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := U.hbox(12)
	nr.add_child(U.label(name_, "m", "text" if enabled else "muted", "ui_bold"))
	var ver := str(a.get("version", ""))
	if ver != "":
		nr.add_child(U.label("v" + ver, "s", "faint", "medium"))
	if not enabled:
		nr.add_child(U.label("Aus", "s", "warn", "bold"))
	col.add_child(nr)
	var what := _what(a)
	if what != "":
		col.add_child(U.ellipsis(U.label(what, "s", "muted", "regular")))
	var desc := str(a.get("description", "")).strip_edges()
	if desc != "":
		var dl := U.ellipsis(U.label(desc, "s", "faint", "regular"))
		col.add_child(dl)
	body.add_child(col)
	var info := _Info.new(body)
	info.set_meta("uz_key", "addon:" + aid)
	info.set_meta("uz_hint_a", "Mehr")
	info.set_meta("uz_hint_x", "Ausschalten" if enabled else "Einschalten")
	info.set_meta("uz_on_x", func() -> void: _set_enabled(aid, not enabled, name_))
	info.set_meta("uz_help", _addon_help(a))
	info.activated.connect(func() -> void: _addon_actions(a, i))
	if i == 0:
		info.set_meta("uz_entry", true)
	line.add_child(info)
	var sw := U.button("An" if enabled else "Aus", "check" if enabled else "close", "flat")
	sw.custom_minimum_size = Vector2(128, 56)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.set_meta("uz_key", "addon-an:" + aid)
	sw.set_meta("uz_hint_a", "Ausschalten" if enabled else "Einschalten")
	sw.set_meta("uz_help", _addon_help(a))
	sw.pressed.connect(func() -> void: _set_enabled(aid, not enabled, name_))
	line.add_child(sw)
	var up := Art.icon_button("arrow_up")
	up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	up.disabled = i == 0
	up.set_meta("uz_key", "addon-hoch:" + aid)
	up.set_meta("uz_hint_a", "Nach oben")
	up.set_meta("uz_help", ["Nach oben", "Obere Addons zuerst."])
	up.pressed.connect(func() -> void: _move(aid, -1))
	line.add_child(up)
	var dn := Art.icon_button("arrow_down")
	dn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dn.disabled = i == Movies.addons.size() - 1
	dn.set_meta("uz_key", "addon-runter:" + aid)
	dn.set_meta("uz_hint_a", "Nach unten")
	dn.set_meta("uz_help", up.get_meta("uz_help"))
	dn.pressed.connect(func() -> void: _move(aid, 1))
	line.add_child(dn)
	var rm := U.button("", "trash", "icon")
	rm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rm.set_meta("uz_key", "addon-weg:" + aid)
	rm.set_meta("uz_hint_a", "Entfernen")
	rm.set_meta("uz_help", ["Entfernen", "„%s“ wird aus Uzai entfernt." % name_])
	rm.pressed.connect(func() -> void: _remove(aid, name_))
	line.add_child(rm)
	line.add_child(U.spacer(6, 0, false))


## Kreis mit Logo oder Anfangsbuchstaben in der Farbe des Addons.
func _logo(a: Dictionary) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(56, 56)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hue := Art.hue_of(str(a.get("id", "")))
	var col := Color.from_hsv(hue, 0.42, 0.5)
	c.draw.connect(func() -> void: c.draw_circle(Vector2(28, 28), 28.0, col, true, -1.0, true))
	var l := U.label(Art.initials(str(a.get("name", "?"))).substr(0, 1), "l", "text", "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(56, 56)
	c.add_child(l)
	var logo := str(a.get("logo", ""))
	if logo != "":
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(56, 56)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.material = U.rounded_mat(28.0)
		(tr.material as ShaderMaterial).set_shader_parameter("size", Vector2(56, 56))
		c.add_child(tr)
		Art.load_image(logo, 112, func(t: Texture2D) -> void:
			if t and is_instance_valid(tr):
				tr.texture = t
				l.visible = false
		)
	return c


static func _type_word(t: String) -> String:
	match t:
		"movie": return "Filme"
		"series", "tv": return "Serien"
		"channel": return "Kanäle"
	return t


## Was ein Addon liefert, kurz: „Kataloge, Quellen · Filme, Serien“.
static func _what(a: Dictionary) -> String:
	var res := PackedStringArray()
	for r in a.get("resources", []):
		var rn := str(r.get("name", "")) if r is Dictionary else str(r)
		if RES_NAMES.has(rn) and not res.has(RES_NAMES[rn]):
			res.append(RES_NAMES[rn])
	var types := PackedStringArray()
	for t in a.get("types", []):
		var tn := _type_word(str(t))
		if not types.has(tn):
			types.append(tn)
	var parts := PackedStringArray()
	if not res.is_empty():
		parts.append(", ".join(res))
	if not types.is_empty():
		parts.append(", ".join(types))
	return Art.SEP.join(parts)


func _addon_help(a: Dictionary) -> Array:
	var lines: Array = []
	var what := _what(a)
	if what != "":
		lines.append(["Liefert", what])
	var cats := PackedStringArray()
	for c in a.get("catalogs", []):
		cats.append("%s (%s)" % [str(c.get("name", c.get("id", ""))), "Filme" if str(c.get("type", "")) == "movie" else "Serien"])
	if not cats.is_empty():
		lines.append(["Kataloge", "\n".join(cats)])
	if bool(a.get("configurable", false)):
		lines.append(["Einstellungen", "Im Browser einstellen, dann die neue Adresse installieren."])
	lines.append(["Adresse", str(a.get("url", ""))])
	var head := str(a.get("name", "")) + ("" if bool(a.get("enabled", true)) else " (aus)")
	return [head, str(a.get("description", "")), lines]


func _addon_actions(a: Dictionary, i: int) -> void:
	var aid := str(a.get("id", ""))
	var name_ := str(a.get("name", aid))
	var on := bool(a.get("enabled", true))
	var acts: Array = [["Ausschalten" if on else "Einschalten", "check" if not on else "close", func() -> void: _set_enabled(aid, not on, name_)]]
	if i > 0:
		acts.append(["Nach oben", "chevron_left", func() -> void: _move(aid, -1)])
	if i < Movies.addons.size() - 1:
		acts.append(["Nach unten", "chevron_right", func() -> void: _move(aid, 1)])
	acts.append(["Entfernen", "trash", func() -> void: _remove(aid, name_)])
	open_actions(main, name_, "Addon" + (Art.SEP + "v" + str(a.get("version", "")) if str(a.get("version", "")) != "" else ""), acts)


func _set_enabled(aid: String, on: bool, name_: String) -> void:
	Movies.set_addon_enabled(aid, on)
	Toasts.show_toast("Eingeschaltet" if on else "Ausgeschaltet", name_, "check" if on else "close", { "quiet": true })


func _move(aid: String, d: int) -> void:
	Movies.move_addon(aid, d)


func _remove(aid: String, name_: String) -> void:
	main.open_dialog("„%s“ entfernen?" % name_, "Kataloge und Quellen dieses Addons werden entfernt.", [
		["Entfernen", func() -> void:
			Movies.remove_addon(aid)
			Toasts.show_toast("Entfernt", name_, "trash", { "quiet": true }), "danger"],
		["Behalten", func() -> void: pass],
	])


## Adresse über die Bildschirmtastatur (oder vom Handy) und installieren.
static func ask_install(m: Main) -> void:
	m.open_keyboard("Adresse des Addons", "", func(url: String) -> void:
		var u := url.strip_edges()
		if u == "":
			return
		Toasts.show_toast("Addon wird installiert …", u, "download", { "quiet": true })
		var err: Variant = await Movies.install_addon(u)
		if str(err) == "":
			Toasts.show_toast("Addon installiert", str(Movies.addons[Movies.addons.size() - 1].get("name", "")) if not Movies.addons.is_empty() else "", "check",
					{ "sound": "select" })
		else:
			Toasts.show_toast("Nicht installiert", str(err), "warning", { "sound": "error", "ms": 6000 })
	)


# --- Plugins -----------------------------------------------------------------------------------

func _plugins() -> void:
	var on: bool = Movies.plugins_enabled()
	var rows := _card()
	var t = SettingRow.new()
	t.setup("toggle", "Plugins verwenden", "", on)
	t.subtitle = ""
	t.set_meta("uz_key", "plugins:an")
	t.set_meta("uz_default", true)
	t.set_meta("uz_help", ["Plugins verwenden", ""])
	t.focus_radius = maxi(UzTheme.radius, UzTheme.r_panel() - 6)
	t.changed.connect(func(v: Variant) -> void: Movies.set_plugins_enabled(bool(v)))
	rows.add_child(t)
	var top := U.margin(20, 6, 20, 4)
	var row := U.hbox(14)
	top.add_child(row)
	var add := U.button("Verzeichnis hinzufügen", "plus", "flat")
	add.set_meta("uz_key", "plugins:neu")
	add.set_meta("uz_hint_a", "Adresse eingeben")
	add.set_meta("uz_help",
			["Verzeichnis hinzufügen",
			"Adresse des Verzeichnisses."])
	add.pressed.connect(_ask_repo)
	row.add_child(add)
	_list.add_child(top)
	var repos: Array = Movies.plugin_repos
	_head("Verzeichnisse", U.plural(repos.size(), "Verzeichnis", "Verzeichnisse") if not repos.is_empty() else "")
	if repos.is_empty():
		var em := U.margin(22, 6, 22, 0)
		em.add_child(U.label("Keine Verzeichnisse.", "m", "muted", "regular", true))
		_list.add_child(em)
		return
	for r in repos:
		_repo(r, on)


func _repo(r: Dictionary, global_on: bool) -> void:
	var rid := str(r.get("id", ""))
	var name_ := str(r.get("name", rid))
	var scrapers: Array = r.get("scrapers", [])
	var rows := _card()
	var line := U.hbox(10)
	rows.add_child(line)
	var body := U.hbox(18)
	body.add_child(_logo({ "id": rid, "name": name_, "logo": "" }))
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(U.label(name_, "m", "text", "ui_bold"))
	var on_n := scrapers.filter(func(s: Dictionary) -> bool: return bool(s.get("enabled", true))).size()
	col.add_child(U.ellipsis(U.label("%s%s%d eingeschaltet" % [U.plural(scrapers.size(), "Quelle", "Quellen"), Art.SEP, on_n], "s", "muted", "regular")))
	col.add_child(U.ellipsis(U.label(str(r.get("url", "")), "s", "faint", "regular")))
	body.add_child(col)
	var info := _Info.new(body)
	info.set_meta("uz_key", "repo:" + rid)
	info.set_meta("uz_hint_a", "Mehr")
	info.set_meta("uz_help", [name_, "Plugin-Verzeichnis", [["Adresse", str(r.get("url", ""))], ["Quellen", U.plural(scrapers.size(), "Quelle", "Quellen")]]])
	info.activated.connect(func() -> void:
		open_actions(main, name_, "Plugin-Verzeichnis", [["Entfernen", "trash", func() -> void: _remove_repo(rid, name_)]])
	)
	line.add_child(info)
	var rm := U.button("", "trash", "icon")
	rm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rm.set_meta("uz_key", "repo-weg:" + rid)
	rm.set_meta("uz_hint_a", "Entfernen")
	rm.set_meta("uz_help", ["Verzeichnis entfernen", "„%s“ und seine Quellen werden entfernt." % name_])
	rm.pressed.connect(func() -> void: _remove_repo(rid, name_))
	line.add_child(rm)
	line.add_child(U.spacer(6, 0, false))
	for s in scrapers:
		var sid := str(s.get("id", ""))
		var row = SettingRow.new()
		row.setup("toggle", str(s.get("name", sid)), "", bool(s.get("enabled", true)))
		var parts := PackedStringArray()
		if str(s.get("version", "")) != "":
			parts.append("Version " + str(s.version))
		var types := PackedStringArray()
		for t in s.get("types", []):
			types.append(_type_word(str(t)))
		if not types.is_empty():
			parts.append(", ".join(types))
		row.subtitle = Art.SEP.join(parts) + ("" if global_on else Art.SEP + "Plugins sind aus")
		row.set_meta("uz_key", "scraper:" + sid)
		row.set_meta("uz_help", [str(s.get("name", sid)), "Quelle aus „%s“." % name_])
		row.focus_radius = maxi(UzTheme.radius, UzTheme.r_panel() - 6)
		row.changed.connect(func(v: Variant) -> void: Movies.set_scraper_enabled(sid, bool(v)))
		rows.add_child(row)


func _ask_repo() -> void:
	main.open_keyboard("Adresse des Plugin-Verzeichnisses", "", func(url: String) -> void:
		var u := url.strip_edges()
		if u == "":
			return
		Toasts.show_toast("Verzeichnis wird geladen …", u, "download", { "quiet": true })
		var err: Variant = await Movies.add_plugin_repo(u)
		if str(err) == "":
			Toasts.show_toast("Verzeichnis hinzugefügt", u, "check", { "sound": "select" })
		else:
			Toasts.show_toast("Nicht hinzugefügt", str(err), "warning", { "sound": "error", "ms": 6000 })
	)


func _remove_repo(rid: String, name_: String) -> void:
	main.open_dialog("„%s“ entfernen?" % name_, "Das Verzeichnis und seine Quellen werden entfernt.", [
		["Entfernen", func() -> void: Movies.remove_plugin_repo(rid), "danger"],
		["Behalten", func() -> void: pass],
	])


## Seitenleiste mit Handlungen: [[Titel, Symbol, Callable, Wert?], …]. Jede Handlung schließt sie.
static func open_actions(m: Main, head: String, sub_t: String, actions: Array) -> void:
	var s = SheetL.new()
	s.setup(head, sub_t, 720)
	s.fill_func = func(sheet) -> void:
		for a in actions:
			var r = SettingRow.new()
			r.setup("action", str(a[0]))
			r.icon_name = str(a[1])
			if a.size() > 3:
				r.value_text = str(a[3])
			var cb: Callable = a[2]
			r.on_activate = func() -> void:
				sheet.close()
				cb.call()
			sheet.add_row(r)
	m.open_layer(s)
