extends "res://src/ui/layers/layer.gd"
## Filme-Quellen wählen (Roadmap 35): oben Nuvio, dann Addons, Plex, Jellyfin, Emby
## und das Stremio-Konto. Links je Quelle eine Glaskarte mit Stand, An/Aus und Reihenfolge
## (Reihen auf der Startseite in dieser Folge), rechts erklärt Uzai die gewählte Quelle samt
## Hinweisen (Anmeldung, Heimnetz, „deine Quellen, deine Verantwortung“). A auf einer Quelle:
## verbinden bzw. ihre Möglichkeiten. Beim ersten Öffnen von „Filme“ kommt die Seite von selbst
## (first): oben dann „Fertig“. B schließt.

const Manage := preload("res://src/ui/components/movie_manage.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const FitBox := preload("res://src/ui/components/fit_box.gd")

const HEAD_H := 250.0
const LIST_W := 1060.0

const Main := preload("res://src/main.gd")
var main: Main
var first := false
var _list: VBoxContainer
var _help_m: MarginContainer
var _help: VBoxContainer
var _body: Control
var _queued := false


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Schließen" if first else "Zurück")
	var hm := U.margin(UzTheme.GUTTER, 58, UzTheme.GUTTER, 0)
	hm.anchor_right = 1.0
	add_child(hm)
	var hv := U.vbox(12)
	hm.add_child(hv)
	hv.add_child(U.label("Woher kommen deine Filme?" if first else "Filme-Quellen", "xxl", "text", "title"))
	var sub := U.label("Mehrere gleichzeitig möglich.", "m", "muted", "regular", true)
	sub.custom_minimum_size = Vector2(1100, 0)
	hv.add_child(sub)
	_fill()
	Quellen.changed.connect(_on_changed)
	Movies.changed.connect(_on_changed)
	NuvioSync.changed.connect(_on_changed)


func _first_focus() -> Control:
	var d := Nav.default_in(_body) if is_instance_valid(_body) else null
	return d if d else Nav.default_in(self)


func close() -> void:
	if first:
		Quellen.mark_chosen()
	super()


func _exit_tree() -> void:
	if Nav.focus_moved.is_connected(_on_focus):
		Nav.focus_moved.disconnect(_on_focus)
	if Quellen.changed.is_connected(_on_changed):
		Quellen.changed.disconnect(_on_changed)
	if Movies.changed.is_connected(_on_changed):
		Movies.changed.disconnect(_on_changed)
	if NuvioSync.changed.is_connected(_on_changed):
		NuvioSync.changed.disconnect(_on_changed)


## Liste und Erklärung (neu) aufbauen.
func _fill() -> void:
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_body)
	_body.offset_top = HEAD_H
	add_child(_body)
	var vw := U.view_size().x
	var list_w := clampf(vw - UzTheme.GUTTER * 2.0 - 48.0 - 520.0, 640.0, LIST_W)
	_list = U.vbox(14)
	_list.set_meta("uz_group", "quellen")
	var lm := U.margin(UzTheme.GUTTER - 20, 6, 20, 140)
	lm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lm.add_child(_list)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 150.0)
	sc.anchor_bottom = 1.0
	sc.offset_right = UzTheme.GUTTER + list_w
	sc.add_child(lm)
	_body.add_child(sc)
	# Unten frei für die Tastenleiste; reicht der Platz nicht (große Oberfläche), wird die
	# Erklärung kleiner, statt über die Tasten zu laufen.
	_help_m = U.margin(0, 6, 0, 110)
	_help_m.anchor_right = 1.0
	_help_m.anchor_bottom = 1.0
	_help_m.offset_left = UzTheme.GUTTER + list_w + 48.0
	_help_m.offset_right = -UzTheme.GUTTER
	_body.add_child(_help_m)
	var fit := FitBox.new()
	_help_m.add_child(fit)
	_help = U.vbox(14)
	fit.add_child(_help)
	if first:
		var top := U.margin(20, 0, 20, 4)
		var row := U.hbox(14)
		row.set_meta("uz_group", "quellen-kopf")
		top.add_child(row)
		var done := U.button("Fertig", "check", "primary")
		done.set_meta("uz_key", "quellen:fertig")
		done.set_meta("uz_hint_a", "Zu den Filmen")
		done.set_meta("uz_help", ["Fertig", "Mit den eingeschalteten Quellen weiter."])
		done.pressed.connect(close)
		row.add_child(done)
		_list.add_child(top)
	_nuvio_row()
	var on := Quellen.order()
	var kinds: Array = on.duplicate()
	for k in Quellen.KINDS:
		if not kinds.has(k):
			kinds.append(k)
	if on.is_empty():
		_head("Quellen")
	else:
		_head("Eingeschaltet", "Reihenfolge wie auf der Startseite")
	for i in kinds.size():
		var k: String = kinds[i]
		if i == on.size() and not on.is_empty():
			_head("Weitere Quellen")
		_source_row(k, on.find(k), on.size(), i == 0)
	var note := U.margin(22, 10, 22, 0)
	var nl := U.label("Kinderprofile sehen nur freigegebene Titel.", "s", "faint", "regular", true)
	note.add_child(nl)
	_list.add_child(note)
	Nav.focus_moved.connect(_on_focus)
	_show_help(null)


## Nuvio ganz oben als eigene Wahl: das Konto bringt Addons, Bibliothek und Weiterschauen mit
## (die Reihen kommen dann über „Addons“). A meldet an bzw. öffnet das Konto.
func _nuvio_row() -> void:
	var con := NuvioSync.connected()
	_head("Nuvio")
	var rows := _card()
	var line := U.hbox(10)
	rows.add_child(line)
	var body := U.hbox(18)
	body.add_child(_badge("nuvio"))
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := U.hbox(12)
	nr.add_child(U.label("Nuvio", "m", "text", "ui_bold"))
	if con:
		nr.add_child(U.label("An", "s", "ok", "bold"))
	col.add_child(nr)
	var who := NuvioSync.email()
	col.add_child(U.ellipsis(U.label(("Verbunden" + ("  ·  " + who if who != "" else "")) if con else "Nicht verbunden", "s", "muted", "regular")))
	var what := U.label("Addons, Bibliothek, Weiterschauen", "s", "faint", "regular", true)
	what.max_lines_visible = 2
	col.add_child(what)
	body.add_child(col)
	var help := ["Nuvio", "Anmeldung per QR-Code.", []]
	var tun := func() -> void:
		if NuvioSync.connected():
			main.open_setting("konten", "", "Nuvio")
		else:
			Quellen.set_on("addons", true)
			main.open_nuvio_login()
	var info = Manage._Info.new(body)
	info.set_meta("uz_key", "quelle:nuvio")
	info.set_meta("uz_hint_a", "Konto" if con else "Verbinden")
	info.set_meta("uz_help", help)
	info.set_meta("uz_default", true)
	info.activated.connect(tun)
	line.add_child(info)
	var cb := U.button("Konto" if con else "Verbinden", "qr" if not con else "user", "flat" if con else "primary")
	cb.custom_minimum_size = Vector2(0, 56)
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb.set_meta("uz_key", "quelle-verbinden:nuvio")
	cb.set_meta("uz_help", help)
	cb.pressed.connect(tun)
	line.add_child(cb)
	line.add_child(U.spacer(6, 0, false))


func _head(text: String, extra := "") -> void:
	var m := U.margin(22, 16, 22, 0)
	var row := U.hbox(12)
	m.add_child(row)
	row.add_child(U.label(text, "s", "muted", "bold"))
	if extra != "":
		row.add_child(U.spacer())
		row.add_child(U.label(extra, "s", "faint", "medium"))
	_list.add_child(m)


func _card() -> VBoxContainer:
	var c = Manage._Card.new()
	_list.add_child(c)
	return c.rows


## Eine Quelle: Zeichen, Name, Stand und eine Zeile, was sie bringt; daneben An/Aus (oder
## Verbinden) und die Pfeile für die Reihenfolge.
func _source_row(kind: String, idx: int, n_on: int, entry: bool) -> void:
	var name_ := str(Quellen.NAMES.get(kind, kind))
	var con: bool = Quellen.connected(kind)
	var on := idx >= 0
	var rows := _card()
	var line := U.hbox(10)
	rows.add_child(line)
	var body := U.hbox(18)
	body.add_child(_badge(kind))
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := U.hbox(12)
	nr.add_child(U.label(name_, "m", "text" if on or not con else "muted", "ui_bold"))
	if on and con:
		nr.add_child(U.label("An", "s", "ok", "bold"))
	elif on:
		nr.add_child(U.label("Wartet auf Anmeldung", "s", "warn", "bold"))
	if con and Quellen.plain_http(kind):
		nr.add_child(U.label("Heimnetz, unverschlüsselt", "s", "faint", "medium"))
	col.add_child(nr)
	col.add_child(U.ellipsis(U.label(Quellen.status_text(kind), "s", "muted", "regular")))
	# Was die Quelle bringt, ganz lesbar: höchstens zwei Zeilen statt „…“.
	var what := U.label(_what(kind), "s", "faint", "regular", true)
	what.max_lines_visible = 2
	col.add_child(what)
	body.add_child(col)
	var info = Manage._Info.new(body)
	info.set_meta("uz_key", "quelle:" + kind)
	info.set_meta("uz_hint_a", "Optionen" if con else "Verbinden")
	info.set_meta("uz_help", _help_for(kind))
	info.activated.connect(func() -> void: _actions(kind))
	line.add_child(info)
	if con:
		var sw := U.button("An" if on else "Aus", "check" if on else "close", "flat")
		sw.custom_minimum_size = Vector2(128, 56)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.set_meta("uz_key", "quelle-an:" + kind)
		sw.set_meta("uz_hint_a", "Ausschalten" if on else "Einschalten")
		sw.set_meta("uz_help", _help_for(kind))
		sw.pressed.connect(func() -> void: _toggle(kind, not on))
		line.add_child(sw)
	else:
		var cb := U.button("Verbinden", "link", "primary" if first and entry else "flat")
		cb.custom_minimum_size = Vector2(0, 56)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.set_meta("uz_key", "quelle-verbinden:" + kind)
		cb.set_meta("uz_help", _help_for(kind))
		cb.pressed.connect(func() -> void: _connect(kind))
		line.add_child(cb)
	var up := Art.icon_button("arrow_up")
	up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	up.disabled = not on or idx == 0
	up.set_meta("uz_key", "quelle-hoch:" + kind)
	up.set_meta("uz_hint_a", "Nach oben")
	up.set_meta("uz_help", ["Reihenfolge", "Reihenfolge wie auf der Startseite."])
	up.pressed.connect(func() -> void: Quellen.move(kind, -1))
	line.add_child(up)
	var dn := Art.icon_button("arrow_down")
	dn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dn.disabled = not on or idx >= n_on - 1
	dn.set_meta("uz_key", "quelle-runter:" + kind)
	dn.set_meta("uz_hint_a", "Nach unten")
	dn.set_meta("uz_help", up.get_meta("uz_help"))
	dn.pressed.connect(func() -> void: Quellen.move(kind, 1))
	line.add_child(dn)
	line.add_child(U.spacer(6, 0, false))


## Runder Fleck mit Anfangsbuchstaben in einer eigenen Farbe – keine fremden Logos (R4).
func _badge(kind: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(56, 56)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hue := { "nuvio": 0.8, "addons": 0.11, "plex": 0.09, "jellyfin": 0.75, "emby": 0.36, "stremio": 0.68 }.get(kind, 0.5) as float
	var colr := Color.from_hsv(hue, 0.45, 0.52)
	c.draw.connect(func() -> void: c.draw_circle(Vector2(28, 28), 28.0, colr, true, -1.0, true))
	var ic := U.icon("qr" if kind == "nuvio" else "grid" if kind == "addons" else ("bookmark" if kind == "stremio" else "drive"), 26, "text")
	ic.position = Vector2(15, 15)
	c.add_child(ic)
	return c


static func _what(kind: String) -> String:
	match kind:
		"addons": return "Kataloge und Quellen aus Addons"
		"plex": return "Bibliotheken vom Plex-Server"
		"jellyfin": return "Bibliotheken vom Jellyfin-Server"
		"emby": return "Bibliotheken vom Emby-Server"
		"stremio": return "Bibliothek und Weiterschauen aus Stremio"
	return ""


func _help_for(kind: String) -> Array:
	var lines: Array = []
	var text := ""
	match kind:
		"addons":
			text = "Keine Addons enthalten. Für deine Quellen bist du verantwortlich."
		"plex":
			text = "Anmeldung über plex.tv/link."
		"jellyfin":
			text = "Anmeldung mit Quick Connect oder Passwort."
		"emby":
			text = "Anmeldung mit Name und Passwort."
		"stremio":
			text = "Keine Addons enthalten. Für deine Quellen bist du verantwortlich."
	if Quellen.connected(kind) and kind != "addons":
		lines.append(["Stand", Quellen.status_text(kind)])
	return [str(Quellen.NAMES.get(kind, kind)), text, lines]


func _on_focus(c: Control) -> void:
	if c != null and is_instance_valid(_body) and _body.is_ancestor_of(c):
		_show_help(c)


func _show_help(c: Control) -> void:
	if not is_instance_valid(_help):
		return
	var h: Array = c.get_meta("uz_help") if c != null \
			and c.has_meta("uz_help") else ["Filme-Quellen",
			""]
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
			var row := U.vbox(2)
			row.add_child(U.label(str(line[0]), "s", "faint", "bold"))
			row.add_child(U.label(str(line[1]), "m", "text", "regular", true))
			box.add_child(row)
	_help_m.modulate.a = minf(_help_m.modulate.a, 0.45)
	U.tw(_help_m, "uz_help").tween_property(_help_m, "modulate:a", 1.0, U.T_BASE)


# --- Aktionen ----------------------------------------------------------------------------------

func _toggle(kind: String, on: bool) -> void:
	Quellen.set_on(kind, on)
	Toasts.show_toast("Eingeschaltet" if on else "Ausgeschaltet", str(Quellen.NAMES.get(kind, kind)), "check" if on else "close", { "quiet": true })


func _connect(kind: String) -> void:
	match kind:
		"plex": main.open_plex_login()
		"jellyfin", "emby": main.open_jellyfin_login(kind)
		"stremio": main.open_stremio_login()
		"addons": _toggle("addons", true)


## Möglichkeiten einer Quelle (A): verbinden, Server wechseln, neu laden, Addons übernehmen, abmelden.
func _actions(kind: String) -> void:
	var name_ := str(Quellen.NAMES.get(kind, kind))
	if not Quellen.connected(kind):
		_connect(kind)
		return
	var on: bool = Quellen.is_on(kind)
	var acts: Array = [["Ausschalten" if on else "Einschalten", "close" if on else "check", func() -> void: _toggle(kind, not on)]]
	match kind:
		"addons":
			acts.append(["Addons und Plugins verwalten", "grid", func() -> void:
				close()
				main.goto("movies", "addons")])
			acts.append(["Nuvio-Konto" if NuvioSync.connected() else "Mit Nuvio anmelden", "qr", func() -> void:
				if NuvioSync.connected():
					main.open_setting("konten", "", "Nuvio")
				else:
					main.open_nuvio_login()])
		"plex":
			acts.append(["Anderen Server wählen", "drive", func() -> void: main.open_plex_login(true)])
		"jellyfin", "emby":
			acts.append(["Neu anmelden oder anderer Server", "drive", func() -> void: main.open_jellyfin_login(kind)])
		"stremio":
			acts.append(["Eigene Addons übernehmen …", "download", func() -> void: main.open_stremio_login("addons")])
			var wb := bool(Config.get_value("stremio.write_back", true))
			acts.append(["Fortschritt an Stremio melden: " + ("An" if wb else "Aus"), "history", func() -> void:
				Config.set_value("stremio.write_back", not wb)
				Toasts.show_toast("Fortschritt an Stremio", "An" if not wb else "Aus", "history", { "quiet": true })])
	if kind != "addons":
		acts.append(["Abmelden", "close", func() -> void: _sign_out(kind)])
	Manage.open_actions(main, name_, Quellen.status_text(kind), acts)


func _sign_out(kind: String) -> void:
	var name_ := str(Quellen.NAMES.get(kind, kind))
	main.open_dialog("Von %s abmelden?" % name_, "Anmeldung und Server werden entfernt. Die Bibliotheken bleiben unverändert.",
			[
		["Abmelden", func() -> void:
			await Quellen.sign_out(kind)
			Toasts.show_toast("Abgemeldet", name_, "check", { "quiet": true }), "danger"],
		["Abbrechen", func() -> void: pass],
	], "user", "warn")


## Neu aufbauen (einmal je Bild), die Auswahl per Schlüssel behalten.
func _on_changed() -> void:
	if _queued or _closing:
		return
	_queued = true
	await get_tree().process_frame
	_queued = false
	if not is_inside_tree() or _closing:
		return
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f and is_ancestor_of(f) else ""
	if Nav.focus_moved.is_connected(_on_focus):
		Nav.focus_moved.disconnect(_on_focus)
	_fill()
	for c in Nav.focusables(self):
		if key != "" and str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	var d := Nav.default_in(_body)
	if d and (f == null or not is_ancestor_of(f)) and Nav.top_layer() == self:
		Nav.focus(d, true)
