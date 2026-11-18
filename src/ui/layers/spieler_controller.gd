extends "res://src/ui/layers/layer.gd"
## Spieler & Controller: welcher Controller Spieler 1–4 ist – für Uzai und die Emulatoren.
## Links die vier Plätze, rechts Controller ohne Platz und was mit den Emulatoren geschieht.
## - A auf einem Platz: „Drück A auf dem Controller für Spieler 2“ – der Controller, auf dem dann
##   A kommt, nimmt den Platz (erkannt an Godots Gerätenummer → GUID, src/core/spieler.gd).
## - X: tauschen (danach A auf dem anderen Platz), Y: Controller vom Platz nehmen.
## - Neue Controller kommen von selbst auf den nächsten freien Platz; selbst Zugeordnetes gewinnt
##   und wird je Controller gemerkt.
## - Emulatoren (src/core/spieler_emus.gd): vor jedem Start ist Spieler 1 der Controller, mit dem
##   gestartet wurde (an; selbst gesetztes Spieler 1 gewinnt bei mehreren), auf Wunsch richtet Uzai
##   alles nach dieser Zuordnung ein (ab zwei Spielern). Läuft gerade ein
##   Emulator-Spiel, gilt es nach dem Neustart – „Spiel mit neuer Zuordnung neu starten“ merkt sich
##   vorher die Stelle, wo der Emulator das kann.
## Erreichbar aus dem Guide (Mehr › Mehrspieler, System › Controller) und Einstellungen › Controller.

const SpielerS := preload("res://src/core/spieler.gd")
const SpielerEmus := preload("res://src/core/spieler_emus.gd")
const PadsS := preload("res://src/core/pads.gd")
const QuickResume := preload("res://src/core/quick_resume.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const SELF := "res://src/ui/layers/spieler_controller.gd"
const LISTEN_S := 10.0
const SIDE_W := 640.0

const Main := preload("res://src/main.gd")
var main: Main
var _listen := 0                  ## Platz, für den „Drück A …“ läuft (0: keiner)
var _listen_until := 0
var _swap_from := 0               ## X gedrückt auf diesem Platz: A auf einem anderen tauscht
var _slots_box: VBoxContainer
var _side: VBoxContainer
var _status_l: Label
var _sig := ""
var _note := ""                   ## kurze Rückmeldung unter dem Titel (statt eines Toasts)


static func open_for(m: Main) -> Control:
	var l = load(SELF).new()
	l.main = m
	m.open_layer(l)
	return l


func build() -> void:
	dim = 0.94
	_scrim.color = Color(UzTheme.col("bg"), dim)
	depth = false
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
	head.add_child(U.label("Spieler & Controller", "xl", "text", "title"))
	_status_l = U.label("", "m", "muted", "regular")
	_status_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_child(_status_l)
	col.add_child(head)
	var body := U.hbox(64)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_slots_box = U.vbox(14)
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_slots_box)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	sc.custom_minimum_size = Vector2(SIDE_W, 0)
	body.add_child(sc)
	_side = U.vbox(0)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_side)
	set_meta("uz_hint_b", "Zurück")
	Pads.changed.connect(_render)
	_render()


func _first_focus() -> Control:
	return Nav.default_in(_slots_box) if is_instance_valid(_slots_box) else null


func _process(_dt: float) -> void:
	if _listen > 0 and Time.get_ticks_msec() > _listen_until:
		_stop_listen("Kein A gekommen – nichts geändert.")


## Solange „Drück A …“ läuft, gehören alle Controller-Tasten dieser Ebene (nie an die Liste dahinter).
func _input(event: InputEvent) -> void:
	if _listen == 0:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_stop_listen("")
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventJoypadButton):
		return
	var b := event as InputEventJoypadButton
	get_viewport().set_input_as_handled()
	if not b.pressed:
		return
	if b.is_action_pressed("uz_b"):
		_stop_listen("")
		return
	if not (b.is_action_pressed("uz_a") or b.button_index == JOY_BUTTON_A):
		return
	var id := SpielerS.id_of_device(Pads.pads, b.device)
	if id == "":
		_note = "Controller nicht erkannt. Erneut versuchen."
		_render()
		return
	var slot := _listen
	_listen = 0
	var r := SpielerS.assign(SpielerS.slots_now(), SpielerS.mem_now(), id, slot)
	SpielerS.save(r.slots, r.mem)
	Pads.refresh()
	Sfx.play("toggle_on")
	Pads.rumble(b.device, 0.3, 0.3, 0.12)
	_note = tr("Spieler %d ist jetzt %s.") % [slot, _name_of(id)]
	_render(true)


func _stop_listen(msg: String) -> void:
	_listen = 0
	_note = msg
	Sfx.play("back")
	_render(true)


func nav_command(cmd: String) -> bool:
	if cmd == "b" and _swap_from > 0:
		_swap_from = 0
		_note = ""
		Sfx.play("back")
		_render(true)
		return true
	return super(cmd)


func handle(cmd: String) -> bool:
	var f := Nav.focused()
	var slot := int(f.get_meta("uz_slot", 0)) if f else 0
	if slot == 0:
		return false
	if cmd == "x":
		_swap_from = slot
		_note = ""
		Sfx.play("select")
		_render(true)
		return true
	if cmd == "y" and SpielerS.slots_now()[slot - 1] != "":
		var name := _name_of(SpielerS.slots_now()[slot - 1])
		var r := SpielerS.remove(SpielerS.slots_now(), SpielerS.mem_now(), slot)
		SpielerS.save(r.slots, r.mem)
		Pads.refresh()
		Sfx.play("toggle_off")
		_note = tr("%s ohne Platz. A ordnet zu.") % name
		_render(true)
		return true
	return false


func _on_slot(slot: int) -> void:
	if _swap_from > 0:
		var a := _swap_from
		_swap_from = 0
		if a != slot:
			var r := SpielerS.swap(SpielerS.slots_now(), SpielerS.mem_now(), a, slot)
			SpielerS.save(r.slots, r.mem)
			Pads.refresh()
			_note = tr("Spieler %d und %d getauscht.") % [a, slot]
		else:
			_note = ""
		_render(true)
		return
	_listen = slot
	_listen_until = Time.get_ticks_msec() + int(LISTEN_S * 1000.0)
	_note = ""
	_render(true)


# --- Anzeige ---------------------------------------------------------------------------------

func _pad_by_id(id: String) -> Dictionary:
	for p in Pads.pads:
		if str(p.get("uz_id", "")) == id:
			return p
	return {}


func _name_of(id: String) -> String:
	var p := _pad_by_id(id)
	return str(p.get("name", "Controller")) if not p.is_empty() else tr("Controller")


func _type_tr(p: Dictionary) -> String:
	return " · ".join(PackedStringArray(Array(SpielerS.type_text(p).split(" · ")).map(func(x): return tr(str(x)))))


func _status_text() -> String:
	if _listen > 0:
		return tr("Drück A auf dem Controller für Spieler %d") % _listen
	if _swap_from > 0:
		return tr("Tauschen: A auf dem Platz, der mit Spieler %d tauscht") % _swap_from
	if _note != "":
		return _note
	if Pads.pads.is_empty():
		return tr("Kein Controller verbunden.")
	return tr("Neue Controller nehmen den nächsten freien Platz.") if bool(Config.get_value(SpielerS.KEY_AUTO, true)) \
			else tr("Neue Controller von Hand zuordnen.")


func _render(force := false) -> void:
	if not is_instance_valid(_slots_box):
		return
	_status_l.text = _status_text()
	set_meta("uz_hint_b", "Abbrechen" if _listen > 0 or _swap_from > 0 else "Zurück")
	_status_l.add_theme_color_override("font_color", UzTheme.col("accent_ink") if _listen > 0 or _swap_from > 0 else UzTheme.col("muted"))
	var slots := SpielerS.slots_now()
	var sig := JSON.stringify([slots, Pads.pads, _listen, _swap_from, Launcher.in_game, SpielerEmus.has_backups()])
	if sig == _sig and not force:
		return
	_sig = sig
	var keep := ""
	var f := Nav.focused()
	if f and is_ancestor_of(f):
		keep = str(f.get_meta("uz_key", ""))
	U.clear(_slots_box)
	U.clear(_side)
	for i in SpielerS.SLOTS:
		_slots_box.add_child(_slot_row(i + 1, slots[i]))
	_fill_side(slots)
	if Nav.top_layer() == self:
		var target: Control = null
		if keep != "":
			for c in Nav.focusables(self):
				if str(c.get_meta("uz_key", "")) == keep:
					target = c
		if target == null:
			target = Nav.default_in(_slots_box)
		if target and target != Nav.focused():
			Nav.focus(target, true)


func _slot_row(n: int, id: String) -> Control:
	var h := U.hbox(22)
	var num := U.label(str(n), "xl", "accent_ink" if _listen == n or _swap_from == n else ("text" if id != "" else "faint"), "title")
	num.custom_minimum_size = Vector2(44, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(num)
	var p := _pad_by_id(id) if id != "" else {}
	var r = SettingRow.new()
	r.setup("action", str(p.get("name", "")) if not p.is_empty() else tr("Frei"), "")
	r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	r.icon_name = "controller"
	r.focus_radius = maxi(UzTheme.radius, UzTheme.r_panel() - 6)
	if not p.is_empty():
		r.subtitle = _type_tr(p)
		var bt := PadsS.battery_text(p)
		r.value_text = tr(bt) if bt != "" else tr("Akku ?")
		r.tone = "" if bt != "" else "faint"
	else:
		r.tone = "faint"
	if _listen == n:
		r.value_text = tr("Drück A …")
		r.tone = "accent"
	elif _swap_from == n:
		r.value_text = tr("Tauschen …")
		r.tone = "accent"
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.set_meta("uz_key", "sp:slot%d" % n)
	r.set_meta("uz_slot", n)
	r.set_meta("uz_hint_a", "Hierher tauschen" if _swap_from > 0 else "Zuordnen")
	if _swap_from == 0 and _listen == 0:
		r.set_meta("uz_hint_x", "Tauschen")
		if id != "":
			r.set_meta("uz_hint_y", "Entfernen")
	r.on_activate = func() -> void: _on_slot(n)
	h.add_child(r)
	return h


func _head(text: String) -> void:
	var l := U.label(text, "s", "muted", "medium")
	l.clip_text = false
	var m := U.margin(14, 22 if _side.get_child_count() > 0 else 0, 0, 6)
	m.add_child(l)
	_side.add_child(m)


func _row(key: String, title: String, sub: String, value: String, icon: String, cb: Callable, hint := "") -> Control:
	var r = SettingRow.new()
	r.setup("action", title, "")
	r.subtitle = sub
	r.value_text = value
	r.icon_name = icon
	r.compact = true
	r.set_meta("uz_key", key)
	if hint != "":
		r.set_meta("uz_hint_a", hint)
	r.on_activate = cb
	_side.add_child(r)
	return r


func _toggle(key: String, cfg: String, title: String) -> void:
	var r = SettingRow.new()
	# „Immer nach Uzais Zuordnung“ ist von Haus aus aus, alles andere an.
	r.setup("toggle", title, "", bool(Config.get_value(cfg, cfg != SpielerS.KEY_EMUS)))
	r.compact = true
	r.set_meta("uz_key", key)
	r.changed.connect(func(v: Variant) -> void:
		Config.set_value(cfg, bool(v))
		Config.save_soon()
		if cfg == SpielerS.KEY_AUTO:
			Pads.refresh()
		_status_l.text = _status_text())
	_side.add_child(r)


func _fill_side(slots: Array) -> void:
	var free: Array = Pads.pads.filter(func(p): return not slots.has(str(p.get("uz_id", ""))))
	if not free.is_empty():
		_head("Ohne Platz")
		for p in free:
			var pp: Dictionary = p
			_row("sp:frei:" + str(pp.get("uz_id", "")), str(pp.get("name", "Controller")), _type_tr(pp), PadsS.battery_text(pp), "controller",
				func() -> void: Pads.identify(pp), "Kurz vibrieren")
	_head("Emulatoren")
	var g: Dictionary = Launcher.current
	if Launcher.in_game and str(g.get("source", "rom")) == "rom":
		var qr: bool = main != null and main.rest != null and QuickResume.supported(g)
		var p1 := str(Launcher.pads_start.get("name", ""))
		var sub := tr("Die Zuordnung gilt nach Neustart des Spiels.")
		if p1 != "":
			sub = tr("Im Spiel ist %s Spieler 1. Anders: Platz 1 tauschen (X), dann neu starten.") % p1
		_row("sp:neustart", "Spiel mit neuer Zuordnung neu starten", sub,
			"mit Speichern" if qr else "", "restart", func() -> void: restart_game(main), "Neu starten")
	_toggle("sp:fehlend", SpielerS.KEY_FEHLEND, "Controller im Emulator automatisch")
	_toggle("sp:emus", SpielerS.KEY_EMUS, "Immer nach Uzais Zuordnung (mehrere Spieler)")
	_row("sp:jetzt", "Jetzt einrichten", "DuckStation, PCSX2, Dolphin, RetroArch, Eden …", "", "check", _open_overview, "Einrichten")
	if SpielerEmus.has_backups():
		_row("sp:original", "Originale zurückholen", "Die Einstellungen der Emulatoren wie vor Uzai.", "", "undo", _restore, "Zurückholen")
	_head("Controller")
	_toggle("sp:auto", SpielerS.KEY_AUTO, "Neue Controller automatisch zuordnen")
	_row("sp:koppeln", "Controller koppeln …", "Über Bluetooth, ohne Treiber.", "", "bluetooth",
		func() -> void: load("res://src/ui/layers/pad_pair.gd").open_for(main), "Suchen")


## Alle Emulatoren einrichten (außer dem, der läuft) und das Ergebnis zeigen.
func _open_overview() -> void:
	var rows := SpielerEmus.overview(true)
	var s = Sheet.new()
	s.setup("Emulatoren", "Spieler 1–4 nach dieser Zuordnung", 760)
	s.fill_func = func(sheet) -> void:
		if rows.is_empty():
			var it = ListItem.new()
			it.setup("Noch kein Emulator eingerichtet", "Unter Einstellungen → Emulatoren den Pfad eintragen.", "")
			it.icon_name = "controller"
			sheet.add_row(it)
		for r in rows:
			var it = ListItem.new()
			it.setup(str(r.name), str(r.text), "eingerichtet" if bool(r.ok) else "")
			it.icon_name = "check" if bool(r.ok) else "controller"
			it.set_meta("uz_hint_a", "—")
			sheet.add_row(it)
	main.open_layer(s)
	_render(true)


func _restore() -> void:
	var n := SpielerEmus.restore_all()
	_note = tr("%d Dateien zurückgeholt.") % n if n != 1 else tr("Eine Datei zurückgeholt.")
	Sfx.play("select")
	_render(true)


## Beenden (mit Stelle merken, wo der Emulator das kann), warten, mit der Stelle neu starten. Vor
## dem Start richtet der Launcher den Emulator nach der Zuordnung ein. Statisch: die Ebene ist dann zu.
static func restart_game(m: Main) -> void:
	if m == null or not Launcher.in_game:
		return
	var g: Dictionary = Launcher.current.duplicate()
	g.erase("_resume_args")
	for l in Nav.layers.duplicate():
		if is_instance_valid(l) and l.has_method("close"):
			l.close()
	var t0 := int(Time.get_unix_time_from_system())
	var rest: Variant = m.rest
	if rest != null and QuickResume.supported(g):
		await rest.quit_with_resume()
	else:
		await Launcher.quit_game()
	var waited := 0.0
	while Launcher.in_game and waited < 20.0:
		await m.get_tree().create_timer(0.25).timeout
		waited += 0.25
	if Launcher.in_game:
		Toasts.show_toast("Neustart ging nicht", "Das Spiel läuft noch. Im Guide beenden und neu starten.", "warning", { "ms": 6000 })
		return
	var go := g
	var rec := QuickResume.record(g, true)
	if not rec.is_empty() and int(rec.get("at", 0)) >= t0 - 5:
		var rg := QuickResume.resume_game(g, rec)
		if not rg.is_empty():
			go = rg
	m.launch(go)
