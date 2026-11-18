extends RefCounted
## Guide › Spiel: Leistung des laufenden Spiels (Roadmap 5). Unter den Schnellaktionen eine ruhige
## Leiste (CPU, GPU, RAM, VRAM, Temperatur), A öffnet die Seitenleiste „Leistung“: Prozessor,
## Grafikkarte, Arbeits- und Grafikspeicher je mit dem Anteil des Spiels, Temperatur, das
## Energieprofil von Windows (umschaltbar, wenn Windows es dem Benutzer erlaubt – nach dem Spiel
## stellt Uzai es zurück) und „In der Ecke anzeigen“. Auch als eigene Kachel wählbar („Leistung“).
## Gefragt wird nur, solange Leiste oder Seitenleiste zu sehen sind (src/core/perf_live.gd).

const U := preload("res://src/ui/u.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const ListItem := preload("res://src/ui/components/list_item.gd")
const PerfLive := preload("res://src/core/perf_live.gd")
const Main := preload("res://src/main.gd")

const NOTE := "Bilder je Sekunde zeigt Uzai nicht: Windows gibt sie nur mit Adminrechten heraus, sonst ginge es nur über einen Eingriff ins Spiel. Temperaturen liest Uzai ohne Adminrechte nur bei NVIDIA-Grafikkarten."


## Die Leiste im Reiter Spiel; misst, solange sie im Baum ist.
static func strip() -> Control:
	var t := Strip.new()
	t.set_meta("uz_key", "g:perf")
	t.set_meta("uz_hint_a", "Leistung")
	_poll(t, func(snap: Dictionary) -> void: t.set_parts(PerfLive.strip_parts(snap)))
	return t


## Alle every_s Sekunden messen, solange host im Baum ist (Guide zu → Timer weg → Helfer ruht).
static func _poll(host: Node, show: Callable) -> void:
	var timer := Timer.new()
	timer.wait_time = PerfLive.every_s()
	timer.autostart = true
	host.add_child(timer)
	var tick := func() -> void:
		var s: Dictionary = await PerfLive.fetch()
		if is_instance_valid(host) and host.is_inside_tree():
			show.call(s)
	timer.timeout.connect(tick)
	tick.call_deferred()


## Seitenleiste „Leistung“.
static func open(main: Main) -> Control:
	var s = Sheet.new()
	s.setup("Leistung", Library.display_title(Launcher.current) if Launcher.in_game else "", 680)
	s.set_meta("uz_key", "guide:perf")
	if Launcher.guide_open:
		s.set_meta("uz_hints_center", true)
	var st := { "rows": [], "plans": {} }
	s.fill_func = func(sheet) -> void:
		var live: Array = []
		for r in PerfLive.rows(PerfLive.last):
			var lr := LiveRow.new()
			lr.set_row(r)
			sheet.add_row(lr)
			live.append(lr)
		st.rows = live
		_plan_rows(sheet, st)
		sheet.add_gap(14)
		var on := bool(Config.get_value("system.perf_corner", false))
		var cr = ListItem.new()
		cr.setup("In der Ecke anzeigen", "Klein oben links über dem Spiel", "An" if on else "Aus")
		cr.icon_name = "pip"
		cr.set_meta("uz_key", "perf:corner")
		cr.set_meta("uz_hint_a", "Ausschalten" if on else "Einschalten")
		cr.activated.connect(func() -> void:
			Config.set_value("system.perf_corner", not on)
			sheet.refill()
		)
		sheet.add_row(cr)
		sheet.add_gap(10)
		sheet.add_label(NOTE)
	_poll(s, func(snap: Dictionary) -> void:
		var rows := PerfLive.rows(snap)
		var live: Array = st.rows
		for i in mini(rows.size(), live.size()):
			if is_instance_valid(live[i]):
				(live[i] as LiveRow).set_row(rows[i]))
	main.open_layer(s)
	_load_plans(s, st)
	return s


static func _load_plans(sheet: Sheet, st: Dictionary) -> void:
	var p: Dictionary = await PerfLive.load_plans()
	if not is_instance_valid(sheet):
		return
	st.plans = p
	sheet.refill()


## Energieprofil: Überschrift, darunter jedes Profil von Windows (das aktive mit Haken). Umschalten
## nur, wenn Windows es diesem Benutzer erlaubt; sonst nur das aktive zur Ansicht.
static func _plan_rows(sheet: Sheet, st: Dictionary) -> void:
	sheet.add_gap(14)
	var head := U.label("Energieprofil", "s", "muted", "medium")
	head.clip_text = false
	var hm := U.margin(14, 0, 0, 2)
	hm.add_child(head)
	sheet.add_row(hm)
	var p: Dictionary = st.plans
	if p.is_empty():
		sheet.add_row(_info_row("Wird gelesen …", ""))
		return
	if not bool(p.ok) or (p.plans as Array).is_empty():
		sheet.add_row(_info_row("Nicht verfügbar", "Windows nennt gerade kein Energieprofil"))
		return
	var stored := str(Config.get_value("system.power_restore", ""))
	var can := bool(p.can_set)
	for plan in p.plans:
		var id := str(plan.id)
		var active := id == str(p.active)
		if not can and not active:
			continue
		var nm := PerfLive.plan_name(id, str(plan.name))
		var sub := ""
		if active and stored != "" and stored != id:
			sub = "Nach dem Spiel stellt Uzai das vorige wieder ein"
		elif not can:
			sub = "Windows erlaubt hier nur eins" if (p.plans as Array).size() <= 1 else "Umschalten erlaubt Windows hier nicht"
		elif stored == id and not active:
			sub = "Vor dem Spiel eingestellt"
		var r = ListItem.new()
		r.setup(str(nm.text), sub, "Aktiv" if active else "")
		r.icon_name = "check" if active else "bolt"
		r.sub_color = "faint"
		r.set_meta("uz_key", "perf:plan:" + id)
		if bool(nm.own):
			_raw(r, str(nm.text))
		if can and not active:
			r.set_meta("uz_hint_a", "Einschalten")
			r.activated.connect(func() -> void: _switch(sheet, st, id))
		sheet.add_row(r)


static func _switch(sheet: Sheet, st: Dictionary, id: String) -> void:
	var before := str((st.plans as Dictionary).get("active", ""))
	var ok: bool = await PerfLive.switch_plan(before, id)
	if not ok:
		Toasts.show_toast("Nicht umgeschaltet", "Windows hat den Energiesparplan nicht gewechselt. Gleich noch einmal versuchen.", "warning", { "ms": 4000 })
		return
	Sfx.play("select")
	(st.plans as Dictionary)["active"] = id
	if is_instance_valid(sheet):
		sheet.refill()


static func _info_row(t: String, sub: String) -> Control:
	var r := LiveRow.new()
	r.set_row(["plan", t, "bolt", "", sub, -1.0])
	return r


## Name von Windows oder vom Nutzer: nie übersetzen (Beschriftung mit genau diesem Text).
static func _raw(row: Control, text: String) -> void:
	var off := func() -> void:
		for l in row.find_children("*", "Label", true, false):
			if (l as Label).text == text:
				(l as Label).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if row.is_node_ready():
		off.call()
	else:
		row.ready.connect(off)


## Eine Zeile der Übersicht: Symbol, Titel, darunter leise der Anteil des Spiels, rechts der Wert,
## unten ein feiner Balken. Nicht wählbar – nur zum Ansehen; neue Werte tauschen leise.
class LiveRow extends Control:
	const UU := preload("res://src/ui/u.gd")
	const Bar := preload("res://src/ui/components/progress_bar.gd")

	var _icon: TextureRect
	var _title: Label
	var _sub: Label
	var _value: Label
	var _bar: Control
	var _row: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size.y = 78
		var m := UU.margin(14, 8, 18, 8)
		UU.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var row := UU.hbox(18)
		m.add_child(row)
		_icon = UU.icon("speed", 28, "muted")
		_icon.custom_minimum_size = Vector2(40, 52)
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_icon)
		var col := UU.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var top := UU.hbox(12)
		col.add_child(top)
		_title = UU.ellipsis(UU.label("", "m", "text", "ui"))
		top.add_child(_title)
		_value = UU.label("", "m", "text", "ui_bold")
		_value.clip_text = false
		top.add_child(_value)
		_sub = UU.ellipsis(UU.label("", "s", "faint", "regular"))
		col.add_child(_sub)
		col.add_child(UU.spacer(0, 4, false))
		_bar = Bar.new().setup(0.0, "accent", 4, 0)
		col.add_child(_bar)

	## [Kennung, Titel, Symbol, Wert, Zeile, Anteil] aus PerfLive.rows.
	func set_row(r: Array) -> void:
		if _row.is_empty() or str(_row[2]) != str(r[2]):
			_icon.texture = Icons.tex(str(r[2]), 28)
		_row = r
		_title.text = str(r[1])
		_value.text = str(r[3])
		_sub.text = str(r[4])
		var f := float(r[5])
		# Ein gemessener Wert setzt sich in T_RAUM („Ankommen“) – ruhig, nie sprunghaft.
		var tw := UU.ankommen(_bar, UU.T_RAUM, "uz_bar")
		tw.set_parallel(true)
		tw.tween_property(_bar, "modulate:a", 1.0 if f >= 0.0 else 0.0, UU.T_ORT)
		if f >= 0.0:
			tw.tween_method(_bar.set_value, float(_bar.get("value")), f, UU.T_RAUM)
		# Warm wird es erst ab 85 °C bzw. fast voller Last – ruhig, nicht alarmierend.
		_bar.set("color_name", "warn" if f >= 0.95 or (str(r[0]) == "temp" and f >= 85.0 / 90.0) else "accent")


## Leiste: links das Symbol, dann je Wert eine leise Beschriftung, der Wert und darunter ein feiner
## Balken. Glas wie die Karten darunter; gewählt hell (Etikett). A öffnet die Seitenleiste.
class Strip extends Control:
	signal activated

	const UU := preload("res://src/ui/u.gd")
	const Bar := preload("res://src/ui/components/progress_bar.gd")
	const H := 72.0

	var _row: HBoxContainer
	var _cells: Array = []        ## [Beschriftung, Wert, Balken]

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size.y = H
		var m := UU.margin(22, 10, 24, 10)
		UU.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		_row = UU.hbox(28)
		m.add_child(_row)
		var ic := UU.icon("speed", 30, "text")
		ic.set_meta("uz_icon", true)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(ic)
		var t := UU.label("Leistung", "m", "text", "ui_bold")
		t.clip_text = false
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(t)
		set_parts(PerfLive.strip_parts(PerfLive.last))

	func _ready() -> void:
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			queue_redraw())
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			queue_redraw())
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())

	## [Beschriftung, Wert, Anteil] aus PerfLive.strip_parts; die Balken gleiten zum neuen Stand.
	func set_parts(parts: Array) -> void:
		if parts.size() != _cells.size():
			for c in _cells:
				(c[3] as Node).queue_free()
			_cells.clear()
			for p in parts:
				var col := UU.vbox(4)
				col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				col.alignment = BoxContainer.ALIGNMENT_CENTER
				var top := UU.hbox(8)
				col.add_child(top)
				var k := UU.label("", "s", "muted", "medium")
				k.clip_text = false
				top.add_child(k)
				var v := UU.label("", "m", "text", "ui_bold")
				v.clip_text = false
				top.add_child(v)
				var bar := Bar.new().setup(0.0, "accent", 3, 0)
				col.add_child(bar)
				_row.add_child(col)
				_cells.append([k, v, bar, col])
			if has_focus():
				UU.etikett(self, true, false)
		for i in parts.size():
			var p: Array = parts[i]
			var c: Array = _cells[i]
			(c[0] as Label).text = str(p[0])
			(c[1] as Label).text = str(p[1])
			var bar: Control = c[2]
			var f := float(p[2])
			bar.modulate.a = 1.0 if f >= 0.0 else 0.0
			if f >= 0.0:
				UU.ankommen(bar, UU.T_RAUM, "uz_bar").tween_method(bar.set_value, float(bar.get("value")), f, UU.T_RAUM)

	func activate() -> void:
		activated.emit()

	func _draw() -> void:
		var rad := maxi(8, UzTheme.r_panel() - 6)
		draw_style_box(UzTheme.box(UzTheme.col("glass"), rad, 1, UzTheme.col("stroke")), Rect2(Vector2.ZERO, size))
		UU.draw_focus(self, rad)
