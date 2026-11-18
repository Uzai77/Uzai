extends VBoxContainer
## Guide › System: der Abschnitt „Controller“ wie im Xbox-Guide. Je Controller eine Zeile mit
## Name, Spieler, Verbindung und Akku; A öffnet die Seitenleiste dazu (vibrieren lassen, testen,
## bei kabellosen Xbox-Controllern ausschalten). Höchstens zwei Zeilen, bei mehr Controllern führt
## die zweite zu allen. Aktualisiert sich, wenn Pads.changed kommt.

const U := preload("res://src/ui/u.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const ListItem := preload("res://src/ui/components/list_item.gd")
const PadTest := preload("res://src/ui/layers/pad_test.gd")
const PadsS := preload("res://src/core/pads.gd")

const Main := preload("res://src/main.gd")
var main: Main
var _rows: VBoxContainer
var _count: Label
var _sig := ""


func setup(m: Main) -> Control:
	main = m
	return self


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := U.hbox(10)
	var l := U.label("Controller", "s", "muted", "medium")
	l.clip_text = false
	head.add_child(l)
	_count = U.label("", "s", "faint", "regular")
	_count.clip_text = false
	head.add_child(_count)
	add_child(head)
	_rows = U.vbox(8)
	add_child(_rows)
	_fill()
	Pads.changed.connect(_on_changed)


func _on_changed() -> void:
	# Liegt die Auswahl gerade in einer Zeile, bleibt sie dort (gleicher Schlüssel).
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f and is_ancestor_of(f) else ""
	_fill()
	if key != "":
		for c in Nav.focusables(_rows):
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				return
		var d := Nav.default_in(_rows)
		if d:
			Nav.focus(d, true)


func _fill() -> void:
	var list: Array = Pads.pads
	var sig := JSON.stringify(list)
	if sig == _sig and _rows.get_child_count() > 0:
		return
	_sig = sig
	U.clear(_rows)
	_count.text = "" if list.size() < 2 else "%d verbunden" % list.size()
	if list.is_empty():
		var none := U.label("Kein Controller verbunden.", "s", "faint", "regular", true)
		_rows.add_child(none)
		return
	# Eine Zeile, damit es neben allen Schnellaktionen in die Karte passt: ein Controller direkt,
	# mehrere zusammen (je ein Akku mit Spieler-Nummer), A führt dann zur Liste aller.
	if list.size() == 1:
		var r := _PadRow.new()
		r.pad = list[0]
		r.set_meta("uz_key", "pad:" + str(list[0].key))
		r.set_meta("uz_hint_a", "Optionen")
		r.picked.connect(func() -> void: open_pad(main, list[0]))
		_rows.add_child(r)
		return
	var all := _PadRow.new()
	all.title = "%d Controller" % list.size()
	all.sub = ", ".join(PackedStringArray(list.map(func(p): return str(p.name))))
	all.summary = list
	all.set_meta("uz_key", "pad:all")
	all.set_meta("uz_hint_a", "Alle Controller")
	all.picked.connect(func() -> void: open_all(main))
	_rows.add_child(all)


## Seitenleiste zu einem Controller: Zustand, vibrieren lassen, testen, ausschalten.
static func open_pad(m: Main, p: Dictionary) -> void:
	if m == null:
		return
	var s = Sheet.new()
	s.setup(str(p.get("name", "Controller")), PadsS.detail_text(p), 700)
	s.fill_func = func(sheet) -> void:
		var bt := PadsS.battery_text(p)
		var info = ListItem.new()
		info.setup("Akku", _battery_long(p), bt)
		info.icon_name = "controller"
		info.set_meta("uz_hint_a", "—")
		sheet.add_row(info)
		var conn = ListItem.new()
		conn.setup("Verbindung", _conn_long(p), str(p.get("conn", "")) if str(p.get("conn", "")) != "" else "unbekannt")
		conn.icon_name = "link"
		conn.set_meta("uz_hint_a", "—")
		sheet.add_row(conn)
		sheet.add_gap(10)
		var vib = ListItem.new()
		vib.setup("Kurz vibrieren lassen", "Welcher Controller ist das?", "")
		vib.icon_name = "controller"
		vib.set_meta("uz_default", true)
		vib.activated.connect(func() -> void: Pads.identify(p))
		sheet.add_row(vib)
		var test = ListItem.new()
		test.setup("Controller testen", "Tasten, Sticks, Trigger und Vibration ansehen", "")
		test.icon_name = "play"
		test.activated.connect(func() -> void:
			var t = PadTest.new()
			t.device = int(p.get("device", -1))
			m.open_layer(t)
		)
		sheet.add_row(test)
		if bool(p.get("can_off", false)):
			var off = ListItem.new()
			off.setup("Controller ausschalten", "Über eine nicht offizielle Windows-Funktion (XInput) – nur kabellose Xbox-Controller.", "")
			off.icon_name = "power"
			off.activated.connect(func() -> void:
				var r: Dictionary = await Pads.power_off(p)
				if bool(r.get("ok", false)):
					Toasts.show_toast("Controller ausgeschaltet", "%s · Spieler %d" % [p.get("name", ""), int(p.get("slot", 1))], "controller", { "sound": "select" })
					if is_instance_valid(sheet):
						sheet.close()
				else:
					Toasts.show_toast("Ausschalten ging nicht", Helper.klartext(str(r.get("error", "")), "Am Controller die Guide-Taste etwa zehn Sekunden halten."),
							"warning", { "ms": 7000 })
			)
			sheet.add_row(off)
		spieler_row(m, sheet)
	m.open_layer(s)


## Alle Controller in einer Seitenleiste; A öffnet die Leiste zu einem.
static func open_all(m: Main) -> void:
	if m == null:
		return
	var s = Sheet.new()
	s.setup("Controller", "%d verbunden" % Pads.pads.size(), 700)
	s.fill_func = func(sheet) -> void:
		for p in Pads.pads:
			var it = ListItem.new()
			it.setup(str(p.name), PadsS.detail_text(p), PadsS.battery_text(p))
			it.icon_name = "controller"
			it.activated.connect(func() -> void: open_pad(m, p))
			sheet.add_row(it)
		spieler_row(m, sheet)
	m.open_layer(s)


## Zuletzt in beiden Leisten: Spieler & Controller (src/ui/layers/spieler_controller.gd).
static func spieler_row(m: Main, sheet) -> void:
	sheet.add_gap(10)
	var sp = ListItem.new()
	sp.setup("Spieler & Controller", "Welcher Controller Spieler 1–4 ist", "")
	sp.icon_name = "controller"
	sp.activated.connect(func() -> void: load("res://src/ui/layers/spieler_controller.gd").open_for(m))
	sheet.add_row(sp)


static func _battery_long(p: Dictionary) -> String:
	if str(p.get("power", "")) == "wired":
		return "Am Kabel, ohne Akku."
	if int(p.get("level", -1)) < 0:
		if str(p.get("family", "")) == "ps":
			return "Noch kein Stand – ein DualSense über Bluetooth meldet ihn erst, wenn ein Spiel oder Steam ihn ganz eingeschaltet hat."
		return "Windows meldet für diesen Controller keinen Stand."
	var t := { "alkaline": "AA-Batterien", "nimh": "Akku (Play & Charge oder NiMH)", "battery": "Eingebauter Akku" }.get(str(p.get("power", "")), "Akku") as String
	return t + (" · wird geladen" if bool(p.get("charging", false)) else "")


static func _conn_long(p: Dictionary) -> String:
	match str(p.get("conn", "")):
		"Kabel":
			return "Über USB-Kabel."
		"Funk":
			return "Kabellos (Xbox-Funkadapter oder Empfänger)." if str(p.get("family", "")) == "xbox" else "Kabellos über den Funkadapter."
		"Bluetooth":
			return "Kabellos über Bluetooth."
	return "Godot sieht den Controller, Windows sagt nichts über die Verbindung."


## Eine Zeile: Controller-Symbol mit Spieler-Nummer, Name, Spieler · Verbindung, rechts der Akku.
class _PadRow extends Control:
	signal picked
	const UU := preload("res://src/ui/u.gd")
	const PB := preload("res://src/ui/components/pad_battery.gd")
	const PS := preload("res://src/core/pads.gd")
	var pad: Dictionary = {}
	var summary: Array = []     ## mehrere Controller: rechts je ein Akku mit Spieler-Nummer
	var title := ""
	var sub := ""

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 66)
		var m := UU.margin(12, 8, 18, 8)
		UU.full_rect(m)
		add_child(m)
		var row := UU.hbox(16)
		m.add_child(row)
		var ib := _Badge.new()
		ib.row = self
		ib.slot = int(pad.get("slot", 0))
		row.add_child(ib)
		var col := UU.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		col.add_child(UU.ellipsis(UU.label(title if title != "" else str(pad.get("name", "Controller")), "m", "text", "ui_bold")))
		var s := sub if sub != "" or pad.is_empty() else PS.detail_text(pad)
		if s != "":
			col.add_child(UU.ellipsis(UU.label(s, "s", "muted", "regular")))
		if not summary.is_empty():
			var bx := UU.hbox(10)
			bx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(bx)
			PB.fill(bx, summary, 16.0, self)
			if bx.get_child_count() > 0:
				bx.get_child(0).queue_free()       # das Controller-Symbol steht schon links
		if not pad.is_empty():
			var bt := PS.battery_text(pad)
			if int(pad.get("level", -1)) >= 0 or str(pad.get("power", "")) == "wired" or bool(pad.get("charging", false)):
				var b = PB.new()
				b.setup(pad, 17.0)
				b.ink_from = self
				row.add_child(b)
			var v := UU.label(bt if bt != "" else "Akku ?", "s", "muted" if bt != "" else "faint", "medium")
			v.clip_text = false
			v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(v)
		draw.connect(ib.queue_redraw)
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func activate() -> void:
		picked.emit()

	func _draw() -> void:
		UU.draw_focus(self, UzTheme.radius + 2)


## Runde Glasfläche mit Controller-Symbol; unten rechts klein die Spieler-Nummer.
class _Badge extends Control:
	const UU := preload("res://src/ui/u.gd")
	var row: Control
	var slot := 0
	var _ic: TextureRect

	func _ready() -> void:
		custom_minimum_size = Vector2(46, 46)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cc := CenterContainer.new()
		cc.set_anchors_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cc)
		_ic = UU.icon("controller", 24, "text")
		cc.add_child(_ic)

	func _draw() -> void:
		var f: float = 0.0
		if is_instance_valid(row):
			f = row.get_meta("uz_f", 1.0 if row.has_focus() else 0.0)
		var bg := UzTheme.col("glass_hi").lerp(UzTheme.col("on_focus", 0.08), f)
		draw_style_box(UzTheme.box(bg, 15), Rect2(Vector2.ZERO, size))
		if slot <= 0:
			return
		var font := UzTheme.font("bold")
		var fs := 15
		var c := Vector2(size.x - 6, size.y - 6)
		draw_circle(c, 10.0, UzTheme.col("accent").lerp(UzTheme.col("on_focus"), f))
		var t := str(slot)
		var w := font.get_string_size(TranslationServer.translate(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + font.get_ascent(fs) * 0.5 - 2.0), TranslationServer.translate(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			UzTheme.col("on_accent").lerp(UzTheme.col("sel"), f))
