extends "res://src/ui/layers/layer.gd"
## Controller koppeln (Punkt 133): Bluetooth-Controller suchen und verbinden, ganz aus Uzai und mit
## dem Controller – oder, solange noch keiner verbunden ist, mit der Tastatur. Links steht, wie ein
## Controller in den Kopplungsmodus kommt, rechts sucht Uzai fortlaufend und zeigt nur Geräte der
## Gamepad-Klasse. A auf einem Controller koppelt genau diesen (der ausdrückliche Wunsch), das
## Ergebnis steht in der Zeile. Bis zu vier Controller nacheinander: Nach jedem Koppeln sucht Uzai weiter, oben
## steht, wie viele verbunden sind. Schon gekoppelte Controller stehen darunter („Gekoppelt“): verbindet sich einer
## nicht (oft nach einer Konsole), koppelt A ihn neu – nach einer Rückfrage entfernt der Helfer die alte Kopplung
## genau dieses Controllers und koppelt ihn wieder. Erreichbar aus der Einrichtung (Controller), Einstellungen →
## Controller, dem Uzai-Doktor und dem Controller-Problemlöser.
##
## Der Helfer (bt-scan, bt-pair) läuft dafür jeweils als eigener Prozess über die offizielle
## Windows-Schnittstelle (aktive Suche mit DeviceWatcher, auch was die Windows-Einstellungen verstecken): keine
## Treiber, keine Adminrechte, kein Windows-Fenster; Bluetooth schaltet
## Uzai nie selbst ein. Regeln und Prüfungen: src/core/koppeln.gd. In der Vorführung kommen
## Koppeln.DEMO-Geräte, und Koppeln gelingt nach einer kurzen Pause.

const Koppeln := preload("res://src/core/koppeln.gd")
const SELF := "res://src/ui/layers/pad_pair.gd"
const SCAN_S := 12                ## so lange sucht Windows je Runde
const PAUSE_S := 1.5              ## Pause zwischen zwei Runden
const LEFT_W := 560.0

const Main := preload("res://src/main.gd")
var main: Main
var _state := "sucht"             ## sucht | an | <Schlüssel aus Koppeln.STATUS>
var _devices: Array = []
var _results := {}                ## Kennung → Schlüssel aus Koppeln.STATUS (nach dem Koppeln)
var _busy_id := ""                ## wird gerade gekoppelt
var _busy_neu := false            ## … neu (alte Kopplung erst entfernt)
var _gekoppelt := {}              ## in dieser Sitzung gekoppelt: Kennung → true (für „n von 4 verbunden“)
var _scanning := false            ## eine Suchrunde läuft (Koppeln wartet darauf – Windows mag beides zugleich nicht)
var _rounds := 0
var _alive := true
var _list: VBoxContainer
var _status_l: Label
var _zahl_l: Label
var _radar: _Radar
var _done_box: Control
var _sig := ""
var just_done := false


static func open_for(m: Main) -> Control:
	var l = load(SELF).new()
	l.main = m
	m.open_layer(l)
	return l


func build() -> void:
	dim = 0.94
	_scrim.color = Color(UzTheme.col("bg"), dim)
	depth = false
	# Ganz deckend: Durch eine fast deckende Fläche schimmerten Texte der Startseite in den Karten.
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bg)
	add_child(bg)
	var root := U.margin(96, 70, 96, 120)
	U.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var col := U.vbox(34)
	root.add_child(col)
	var head := U.vbox(6)
	head.add_child(U.label("Controller koppeln", "xl", "text", "title"))
	head.add_child(U.label("Kopplungsmodus am Controller starten.", "m", "muted", "regular"))
	col.add_child(head)
	var body := U.hbox(64)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_howto())
	var right := U.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var top := U.hbox(16)
	right.add_child(top)
	_radar = _Radar.new()
	top.add_child(_radar)
	var tv := U.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	tv.add_child(U.label("In der Nähe", "l", "text", "bold"))
	_status_l = U.label("", "m", "muted", "regular", true)
	tv.add_child(_status_l)
	_zahl_l = U.label("", "s", "accent", "medium")
	_zahl_l.visible = false
	tv.add_child(_zahl_l)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sc)
	_list = U.vbox(0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var note := U.label("Koppelt über Windows, ohne Treiber und ohne Adminrechte.", "s", "faint", "regular", true)
	right.add_child(note)
	set_meta("uz_hints", [["x", "Erneut suchen"]])
	set_meta("uz_hint_b", "Zurück")
	_render()
	_loop()


func _first_focus() -> Control:
	return Nav.default_in(_list) if is_instance_valid(_list) else null


func close() -> void:
	_alive = false
	super()


func handle(cmd: String) -> bool:
	if cmd == "x":
		if _busy_id == "":
			_results.clear()
			_devices = []
			_state = "sucht"
			_rounds = 0
			_render()
			Sfx.play("select")
		return true
	return false


# --- Anleitung -------------------------------------------------------------------------------

func _howto() -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("text", 0.035), UzTheme.r_panel())
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(LEFT_W, 0)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := U.vbox(20)
	p.add_child(v)
	v.add_child(U.label("Kopplungsmodus", "l", "text", "bold"))
	for fam in [["xbox", "Xbox"], ["ps", "PlayStation"], ["nintendo", "Nintendo"], ["other", "Andere"]]:
		var blk := U.vbox(6)
		var h := U.hbox(10)
		var ic := U.icon("controller", 22, "accent_ink")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		h.add_child(U.label(str(fam[1]), "m", "text", "medium"))
		blk.add_child(h)
		var t := U.label(" ".join(PackedStringArray(Koppeln.steps(str(fam[0])))), "s", "muted", "regular", true)
		t.custom_minimum_size = Vector2(LEFT_W - 68, 0)
		blk.add_child(t)
		v.add_child(blk)
	var tipp := U.label(Koppeln.TIPP, "s", "faint", "regular", true)
	tipp.custom_minimum_size = Vector2(LEFT_W - 68, 0)
	v.add_child(tipp)
	return p


# --- Suchen ----------------------------------------------------------------------------------

## Sucht fortlaufend, solange die Seite offen ist (Pause während des Koppelns).
func _loop() -> void:
	while _alive and is_inside_tree():
		if _busy_id != "":
			await get_tree().create_timer(0.4).timeout
			continue
		_scanning = true
		var res := await _scan()
		_scanning = false
		if not _alive or not is_inside_tree():
			return
		_rounds += 1
		_state = str(res.state)
		if _state == "an":
			_devices = res.devices
		_render()
		# Ohne Bluetooth, ohne Windows, mit Adminrechten oder ohne Helfer: nicht weiter fragen (X sucht neu).
		if _state in ["aus", "kein", "windows", "admin", "helfer"]:
			while _alive and is_inside_tree() and _state != "sucht":
				await get_tree().create_timer(0.4).timeout
			continue
		await get_tree().create_timer(PAUSE_S).timeout


func _scan() -> Dictionary:
	if Library.demo:
		await get_tree().create_timer(2.4).timeout
		# Gekoppelte stehen danach unter „Gekoppelt“ als verbunden.
		var demo: Array = Koppeln.DEMO.map(func(d: Dictionary) -> Dictionary:
			if str(_results.get(str(d.id), "")) != "gekoppelt":
				return d
			var k := d.duplicate()
			k.paired = true
			k.connected = true
			return k)
		return Koppeln.parse_scan({ "code": "an", "devices": demo })
	if not Config.is_windows():
		await get_tree().create_timer(0.6).timeout
		return { "state": "windows", "devices": [] }
	var r: Dictionary = await Helper.run_once("bt-scan", { "secs": SCAN_S, "timeout": SCAN_S + 6 })
	if not bool(r.get("ok", false)):
		return { "state": "helfer", "devices": [] }
	return Koppeln.parse_scan(r.get("result", {}))


# --- Koppeln ---------------------------------------------------------------------------------

func _pair(d: Dictionary, neu := false) -> void:
	if _busy_id != "":
		return
	var id := str(d.id)
	# Erste Sperre hier, die zweite im Helfer (Test-BtId und Klasse noch einmal von Windows gelesen).
	var args := Koppeln.pair_args(id, neu)
	if args.is_empty() or not Koppeln.valid_id(id):
		_results[id] = "kennung"
		_render()
		return
	_busy_id = id
	_busy_neu = neu
	_render()
	while _scanning and is_inside_tree():
		await get_tree().create_timer(0.2).timeout
	var code := ""
	if Library.demo:
		await get_tree().create_timer(2.0).timeout
		code = "gekoppelt"
	elif not Config.is_windows():
		code = "windows"
	else:
		var r: Dictionary = await Helper.run_once("bt-pair", args)
		code = Koppeln.pair_code(r.get("result", {})) if bool(r.get("ok", false)) else "helfer"
	if not is_inside_tree():
		return
	_busy_id = ""
	_busy_neu = false
	_results[id] = code
	if code in ["gekoppelt", "schon"]:
		_gekoppelt[id] = true
		Sfx.play("toggle_on")
		Pads.refresh(true)
		Toasts.show_toast("Controller gekoppelt", str(d.name), "controller", { "quiet": true })
		_done(d)
	else:
		Sfx.play("error")
	_render()


## Neu koppeln (gekoppelt, verbindet sich aber nicht): erst fragen – es entfernt die alte Kopplung in Windows.
func _neu_fragen(d: Dictionary) -> void:
	if _busy_id != "" or not is_instance_valid(main):
		return
	main.open_dialog("Neu koppeln?", "Uzai entfernt die alte Kopplung dieses Controllers in Windows und koppelt ihn neu. Vorher den Kopplungsmodus starten.", [
		["Neu koppeln", func() -> void: _pair(d, true)],
		["Abbrechen", func() -> void: pass],
	], "bluetooth")


## Wie viele Controller verbunden sind: aus der Suche, dazu die in dieser Sitzung gekoppelten.
func _anzahl() -> int:
	var ids := {}
	for d in _devices:
		if Koppeln.rang(d) == 2:
			ids[str(d.id)] = true
	for id in _gekoppelt:
		ids[id] = true
	return ids.size()


## Gekoppelt: oben groß bestätigen, „Fertig“ schließt.
func _done(d: Dictionary) -> void:
	if is_instance_valid(_done_box):
		_done_box.queue_free()
	_done_box = U.vbox(16)
	var h := U.hbox(18)
	var ok := U.icon("check", 40, "ok")
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ok)
	var nm := U.label(tr("%s ist gekoppelt") % str(d.name), "l", "text", "bold")
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Controllers
	h.add_child(nm)
	_done_box.add_child(h)
	if _anzahl() < Koppeln.MAX_PADS:
		_done_box.add_child(U.label("Nächsten Controller in den Kopplungsmodus bringen – Uzai sucht weiter.", "m", "muted", "regular", true))
	var fin := U.button("Fertig", "check", "primary")
	fin.custom_minimum_size = Vector2(220, 58)
	fin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fin.set_meta("uz_key", "pp:fertig")
	fin.pressed.connect(close)
	_done_box.add_child(fin)
	_done_box.add_child(U.spacer(0, 10, false))
	just_done = true


# --- Anzeige ---------------------------------------------------------------------------------

func _render() -> void:
	if not is_instance_valid(_list):
		return
	var searching := _busy_id == "" and _state in ["sucht", "an"]
	_radar.active = searching
	var st: Array = Koppeln.status(_state) if not _state in ["sucht", "an"] else []
	var n := _anzahl()
	_zahl_l.visible = n > 0
	_zahl_l.text = tr("Verbunden: %d von %d") % [mini(n, Koppeln.MAX_PADS), Koppeln.MAX_PADS]
	var neue := _devices.filter(func(d: Dictionary) -> bool: return Koppeln.rang(d) == 0)
	if _busy_id != "":
		_status_l.text = "Koppelt neu …" if _busy_neu else "Koppelt …"
	elif not st.is_empty():
		_status_l.text = str(st[1])
	elif neue.is_empty():
		_status_l.text = "Sucht … Noch kein Controller im Kopplungsmodus." if _rounds > 0 else "Sucht …"
	else:
		_status_l.text = "Ein Controller gefunden. A koppelt ihn." if neue.size() == 1 else tr("%d Controller gefunden. A koppelt den gewählten.") % neue.size()
	var sig := JSON.stringify([_state, _devices, _results, _busy_id, _busy_neu, is_instance_valid(_done_box), n])
	if sig == _sig:
		return
	_sig = sig
	var keep := ""
	var f := Nav.focused()
	if f and _list.is_ancestor_of(f):
		keep = str(f.get_meta("uz_key", ""))
	for ch in _list.get_children():
		if ch == _done_box:
			_list.remove_child(ch)
			continue
		ch.queue_free()
		_list.remove_child(ch)
	if is_instance_valid(_done_box):
		_list.add_child(_done_box)
	var card := _Card.new()
	_list.add_child(card)
	var card2 := _Card.new()
	var titel2 := U.label("Gekoppelt", "m", "muted", "medium")
	var m2 := U.margin(8, 18, 0, 6)
	m2.add_child(titel2)
	for d in _devices:
		var dd: Dictionary = d
		var id := str(dd.id)
		var rg := Koppeln.rang(dd)
		var r = SettingRow.new()
		r.setup("action", str(dd.name), "")
		r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var kind := "Bluetooth LE" if bool(dd.le) else "Bluetooth"
		if rg == 0:
			r.subtitle = "%s · %s" % [tr(kind), tr(["Signal schwach", "Signal schwach", "Signal gut", "Signal stark"][Koppeln.bars(int(dd.signal))])]
		else:
			r.subtitle = "%s · %s" % [tr(kind), tr("verbunden" if rg == 2 else "nicht verbunden")]
		r.icon_name = "controller"
		r.focus_radius = maxi(UzTheme.radius, UzTheme.r_panel() - 6)
		r.set_meta("uz_key", "pp:" + id)
		var res := str(_results.get(id, ""))
		var ok := res in ["gekoppelt", "schon"]
		if _busy_id == id:
			r.value_text = tr("Koppelt neu …" if _busy_neu else "Koppelt …")
			r.tone = "accent"
		elif res != "":
			var s2: Array = Koppeln.status(res)
			r.value_text = tr(str(s2[0]))
			r.tone = str(s2[2])
		elif rg == 2:
			r.value_text = tr("Verbunden")
			r.tone = "ok"
			ok = true
		elif rg == 1:
			r.value_text = tr("Neu koppeln")
			r.tone = "accent"
		else:
			r.value_text = tr("Koppeln")
			r.tone = "accent"
		if rg == 0:
			r.set_meta("uz_hint_a", "Koppeln" if res == "" else ("Gekoppelt" if ok else "Noch einmal"))
			r.on_activate = func() -> void:
				if not ok:
					_pair(dd)
		else:
			r.set_meta("uz_hint_a", "Neu koppeln")
			r.on_activate = func() -> void: _neu_fragen(dd)
		var ziel: _Card = card if rg == 0 else card2
		ziel.rows.add_child(r)
		r.draw.connect(ziel.queue_redraw)
		# Ergebnis mit Erklärung direkt darunter (nur wenn es nicht geklappt hat); „nicht verbunden“ erklärt sich auch.
		var why_text := ""
		if res != "" and not ok:
			why_text = str(Koppeln.status(res)[1])
		elif rg == 1 and res == "" and _busy_id != id:
			why_text = str(Koppeln.status("getrennt")[1])
		if why_text != "":
			var why := U.label(why_text, "s", "muted", "regular", true)
			var m := U.margin(78, 0, 28, 14)
			m.add_child(why)
			ziel.rows.add_child(m)
	card.visible = not neue.is_empty()
	if neue.is_empty() and not is_instance_valid(_done_box):
		_list.add_child(_empty())
	if card2.rows.get_child_count() > 0:
		_list.add_child(m2)
		_list.add_child(card2)
	else:
		card2.queue_free()
		m2.queue_free()
	if Nav.top_layer() == self:
		var target: Control = null
		# Gerade gekoppelt: „Fertig“ ist der nächste Schritt.
		if just_done and is_instance_valid(_done_box):
			just_done = false
			keep = ""
		if keep != "":
			for c in Nav.focusables(_list):
				if str(c.get_meta("uz_key", "")) == keep:
					target = c
		if target == null and is_instance_valid(_done_box):
			target = Nav.default_in(_done_box)
		if target == null:
			target = Nav.default_in(_list)
		if target and target != Nav.focused():
			Nav.focus(target, true)


## Platzhalter, solange noch nichts gefunden ist (gleich groß wie eine Zeile, nichts springt).
func _empty() -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("text", 0.035), UzTheme.r_panel())
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(18)
	p.add_child(h)
	var ic := U.icon("controller", 30, "faint")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := U.label(
			"Controller in den Kopplungsmodus bringen. Er erscheint, sobald Windows ihn findet.", "m",
			"muted", "regular", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	return p


## Karte mit Zeilen (wie in den Einstellungen).
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
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))


## Ruhiges Suchzeichen: ein Punkt, um den langsam Ringe auslaufen (solange gesucht wird).
class _Radar extends Control:
	var active := true
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(76, 76)

	func _process(dt: float) -> void:
		if active or _t > 0.0:
			_t = _t + dt if active else 0.0
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var acc := UzTheme.col("accent")
		draw_circle(c, 34.0, UzTheme.col("text", 0.05), true, -1.0, true)
		if active:
			for i in 2:
				var k := fmod(_t / 1.8 + i * 0.5, 1.0)
				draw_arc(c, 10.0 + 24.0 * k, 0, TAU, 48, Color(acc, 0.55 * (1.0 - k)), 2.0, true)
		var ic: Texture2D = Icons.tex("bluetooth", 26)
		if ic:
			draw_texture_rect(ic, Rect2(c - Vector2(13, 13), Vector2(26, 26)), false, UzTheme.col("accent_ink") if active else UzTheme.col("muted"))
