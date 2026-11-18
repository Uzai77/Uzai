extends "res://src/ui/layers/sheet.gd"
## Downloads – die Zentrale (Punkt 107): was gerade lädt (Steam und Epic, mit Balken, Größe, Tempo
## und Restzeit, live), Uzais Warteschlange (danach oder heute Nacht), anstehende Steam-Updates
## und was fertig ist. A auf einer Zeile: was damit geht (InstallFlow). Unten: „Nachts laden“ und
## Steams Bandbreite – die liest Uzai nur, einstellen geht in Steam.

const Flow := preload("res://src/ui/install_flow.gd")
const DlQueue := preload("res://src/core/dl_queue.gd")

const Main := preload("res://src/main.gd")
var main: Main
var _rows := {}          ## Spiel-ID → Zeile (laufend und fertig)
var _qrows := {}         ## Spiel-ID → Zeile der Warteschlange
var _sig := ""           ## welche Zeilen in welcher Reihenfolge – ändert sich das, neu aufbauen


func _init() -> void:
	super()
	setup("Downloads", "Laden, Warteschlange und Updates", 860)


func build() -> void:
	super()
	Installs.changed.connect(_on_changed)
	Installs.queue_changed.connect(_on_queue_changed)
	_updates_holen()


## Anstehende Updates im Hintergrund auffrischen (Installs liest die Dateien im Hilfsfaden, höchstens einmal je
## Minute); kam etwas dazu oder fiel etwas weg, die Liste neu füllen. Die Seite zeigt bis dahin den letzten Stand.
func _updates_holen() -> void:
	await Installs.updates_auffrischen()
	if is_inside_tree() and _signature(_parts()) != _sig:
		refill()


func fill() -> void:
	_rows.clear()
	_qrows.clear()
	var parts := _parts()
	_sig = _signature(parts)
	var first := [true]
	if parts.active.is_empty() and parts.queue.is_empty() and parts.updates.is_empty() and parts.ended.is_empty():
		add_label("Keine Downloads.",
				"m", "muted")
	if not parts.active.is_empty():
		_head("Lädt gerade")
		for e in parts.active:
			_rows[str(e.id)] = _add(e, first, func() -> void: Flow.actions(main, str(e.id)))
	if not parts.queue.is_empty():
		_head("Warteschlange")
		for i in parts.queue.size():
			var q: Dictionary = parts.queue[i]
			var id := str(q.id)
			_qrows[id] = _add(_queue_view(q, i), first, func() -> void: Flow.queue_actions(main, id))
	if not parts.updates.is_empty():
		_head("Updates")
		for u in parts.updates:
			var uu: Dictionary = u
			_add({ "id": u.id, "title": u.title, "text": DlQueue.update_text(u.u), "phase": "update", "frac": -1.0,
				"store": "steam", "icon": "refresh" }, first, func() -> void: Flow.update_actions(main, uu))
	if not parts.ended.is_empty():
		_head("Fertig")
		for e in parts.ended:
			_rows[str(e.id)] = _add(e, first, func() -> void: Flow.actions(main, str(e.id)))
	# Unten zwei Zeilen zum Ansteuern, damit sie auch bei langer Liste erreichbar sind.
	_head("Einstellungen")
	var h := Installs.night_hours()
	var night := ("%d bis %d Uhr, nur im Ruhemodus" % [int(h[0]), int(h[1])]) if Installs.night_on() else "Aus"
	_add({ "id": "nacht", "title": "Nachts laden", "text": night, "phase": "info", "frac": -1.0, "icon": "moon", "ui": true }, first,
		func() -> void: _open_settings())
	_add({ "id": "bandbreite", "title": "Bandbreite (Steam)", "text": "%s · einstellen nur in Steam" % DlQueue.throttle_text(Installs.steam_throttle()),
		"phase": "info", "frac": -1.0, "icon": "download", "ui": true }, first, func() -> void: Flow.bandwidth_info(main))
	add_gap(10)


## Was auf die Seite kommt: { active, queue, updates, ended }.
func _parts() -> Dictionary:
	var active: Array = []
	var ended: Array = []
	for e in Installs.list():
		(active if Installs.busy(str(e.id)) else ended).append(e)
	var ups: Array = Installs.updates_stand().filter(func(u: Dictionary) -> bool:
		return not Installs.queued(str(u.id)) and str(u.u.phase) != "laeuft")
	return { "active": active, "queue": Installs.queue.duplicate(), "updates": ups, "ended": ended }


static func _signature(p: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in ["active", "queue", "updates", "ended"]:
		bits.append(k + ":" + ",".join(PackedStringArray((p[k] as Array).map(func(x: Dictionary) -> String: return str(x.id)))))
	return "|".join(bits)


## Zeile der Warteschlange: Platz und warum sie wartet.
func _queue_view(q: Dictionary, i: int) -> Dictionary:
	var g := Library.get_game(str(q.id))
	var h := Installs.night_hours()
	var upd := str(q.kind) == "update"
	return { "id": q.id, "title": ("Update: %s" % Library.display_title(g)) if upd else Library.display_title(g),
		"text": "%s · %s" % [Flow.queue_place(i), DlQueue.wait_text(q, int(h[0]), int(h[1]), Installs.night_on())],
		"phase": "waiting", "frac": -1.0, "store": str(g.get("source", "")), "warn": str(q.held) in ["voll", "knapp"],
		"icon": "moon" if str(q.when) == "nachts" else "clock", "ui": upd }


## Einstellungen → Spiele → Installieren und Downloads (Nachts laden, Zeitfenster).
func _open_settings() -> void:
	close()
	await main.goto("settings", "spiele")
	var sv = main.sections.get("settings")
	if sv and sv.has_method("open_more"):
		sv.open_more("Installieren und Downloads")


func _head(t: String) -> void:
	if content.get_child_count() > 0:
		add_gap(10)
	add_label(t, "s", "muted")


func _add(e: Dictionary, first: Array, cb: Callable) -> Control:
	var r := _Row.new()
	r.e = e
	r.set_meta("uz_key", "dl:%s:%s" % [str(e.get("phase", "")), str(e.id)])
	r.set_meta("uz_hint_a", "Optionen")
	if bool(first[0]):
		r.set_meta("uz_default", true)
		first[0] = false
	r.activated.connect(cb)
	add_row(r)
	return r


func _on_changed(id: String) -> void:
	if not is_inside_tree():
		return
	_updates_holen()
	if _signature(_parts()) != _sig or not _rows.has(id):
		refill()
		return
	var r = _rows[id]
	if is_instance_valid(r):
		r.e = Installs.entry(id)
		r.update()


func _on_queue_changed() -> void:
	if not is_inside_tree():
		return
	if _signature(_parts()) != _sig:
		refill()
		return
	for i in Installs.queue.size():
		var q: Dictionary = Installs.queue[i]
		var r = _qrows.get(str(q.id))
		if is_instance_valid(r):
			r.e = _queue_view(q, i)
			r.update()


## Eine Zeile: Symbol, Titel, Zustand, Balken.
class _Row extends Control:
	signal activated

	const U := preload("res://src/ui/u.gd")
	const Bar := preload("res://src/ui/components/progress_bar.gd")

	var e := {}
	var _title: Label
	var _state: Label
	var _bar: Control
	var _icon: TextureRect

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m := U.margin(22, 14, 22, 14)
		U.full_rect(m)
		add_child(m)
		var row := U.hbox(18)
		m.add_child(row)
		var ic := str(e.get("icon", "steam" if str(e.get("store", "")) == "steam" else "games"))
		_icon = U.icon(ic, 30, "muted")
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_icon)
		var col := U.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		_title = U.ellipsis(U.label(str(e.get("title", "")), "m", "text", "ui_bold"))
		col.add_child(_title)
		_state = U.ellipsis(U.label("", "s", "muted", "regular"))
		col.add_child(_state)
		_bar = Bar.new().setup(0.0, "accent", 6, 0)
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_bar)
		custom_minimum_size.y = 104
		focus_entered.connect(func() -> void:
			U.etikett(self, true)
			queue_redraw())
		focus_exited.connect(func() -> void:
			U.etikett(self, false)
			queue_redraw())
		gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())
		update()

	func update() -> void:
		if not is_instance_valid(_state):
			return
		var phase := str(e.get("phase", ""))
		# Der Titel ist der Name eines Spiels und wird nie übersetzt; nur Zeilen von Uzai selbst ("ui") schon.
		_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT if bool(e.get("ui", false)) else Node.AUTO_TRANSLATE_MODE_DISABLED
		_title.text = str(e.get("title", ""))
		_state.text = str(e.get("text", ""))
		var frac := float(e.get("frac", -1.0))
		_bar.visible = frac >= 0.0 and phase != "failed" and phase != "cancelled"
		_bar.set("color_name", "gold" if phase == "done" else ("muted" if phase == "paused" else "accent"))
		if frac >= 0.0:
			_bar.call("set_value", frac)
		var warn := phase == "failed" or bool(e.get("warn", false))
		_state.add_theme_color_override("font_color", UzTheme.col("warn") if warn else UzTheme.col("muted"))

	func activate() -> void:
		activated.emit()

	func _draw() -> void:
		Liste.zeilen_auswahl(self)
