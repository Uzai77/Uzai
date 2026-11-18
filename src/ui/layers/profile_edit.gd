extends "res://src/ui/layers/sheet.gd"
## Ein Profil bearbeiten (Roadmap 109): Name, Bild, Farbe, PIN, Kinderprofil mit seinen Regeln,
## wechseln und löschen. Seitenleiste wie in den Einstellungen; alles mit dem Controller.
## Wer was darf, entscheidet Profiles.guard: fremde Profile mit PIN öffnen sich erst nach ihrer PIN,
## die Regeln eines Kinderprofils ändert aus dem Kinderprofil heraus nur, wer die Eltern-PIN kennt.
## Uzai erzwingt nichts an Windows – das steht auch so in der Leiste.

const Profiles := preload("res://src/core/profiles.gd")
const ProfileAvatar := preload("res://src/ui/components/profile_avatar.gd")
const ProfilePin := preload("res://src/ui/layers/profile_pin.gd")
const SELF := "res://src/ui/layers/profile_edit.gd"

const Main := preload("res://src/main.gd")
var main: Main
var pid := ""
var _rules_ok := false            ## Eltern- bzw. Profil-PIN für die Regeln schon eingegeben


## Bearbeiten öffnen; ein fremdes Profil mit PIN erst nach der PIN.
static func open_for(m: Main, id: String) -> void:
	var need := Config.profile_guard("edit", id)
	var open := func() -> void:
		var e = load(SELF).new()
		e.main = m
		e.pid = id
		e.setup("Profil bearbeiten", "", 820)
		e.help_on = true
		m.open_layer(e)
	if need == "target":
		_ask_pin(m, "check", Profiles.find(Config.profiles, id), "Zum Bearbeiten dieses Profils.", open)
	else:
		open.call()


## Neues Profil: Name über die Bildschirmtastatur, dann gleich Bearbeiten (Bild, Farbe, PIN …).
static func add_new(m: Main) -> void:
	var go := func() -> void:
		m.open_keyboard("Name des neuen Profils", "", func(text: String) -> void:
			var n := Profiles.clean_name(text)
			if n == "":
				return
			var p := Config.add_profile(n)
			if p.is_empty():
				Toasts.show_toast("Kein neues Profil", "Es gibt schon %d Profile – mehr passen nicht." % Profiles.MAX_PROFILES, "user")
				return
			open_for(m, str(p.id))
		)
	if Config.profile_guard("add", "") == "parent":
		_ask_pin(m, "parent", {}, "Neue Profile legen Eltern an.", go)
	else:
		go.call()


static func _ask_pin(m: Main, mode: String, target: Dictionary, why: String, then: Callable) -> void:
	var pin = ProfilePin.new()
	pin.mode = mode
	pin.target = target
	pin.reason = why
	pin.passed.connect(then)
	m.open_layer(pin)


func fill() -> void:
	var p := Profiles.find(Config.profiles, pid)
	if p.is_empty():
		add_label("Dieses Profil gibt es nicht mehr.", "m", "muted")
		return
	var me := pid == Config.profile_id
	_header(p, me)
	add_gap(6)
	_label("Aussehen")
	_row_action("Name ändern", "", "", "edit", func() -> void:
		main.open_keyboard("Name des Profils", str(p.name), func(text: String) -> void:
			var n := Profiles.clean_name(text)
			if n != "":
				_change({ "name": n })
		)
	)
	var av := _row_choice("Bild", "Buchstabe oder Zeichen.", str(p.avatar), Profiles.AVATARS)
	av.changed.connect(func(v: Variant) -> void: _change({ "avatar": str(v) }, false))
	var colors: Array = Profiles.COLORS.map(func(c: Array) -> Array: return [c[0], c[1]])
	var co := _row_choice("Farbe", "", str(p.color), colors)
	co.dot = Profiles.color_of(p)
	co.changed.connect(func(v: Variant) -> void:
		_change({ "color": str(v) }, false)
		if is_instance_valid(co):
			co.dot = Profiles.color_of(Profiles.find(Config.profiles, pid))
	)
	_label("PIN")
	var has_pin := p.has("pin")
	_row_action("PIN ändern" if has_pin else "PIN festlegen", "4 bis 8 Ziffern.",
		"An" if has_pin else "Aus", "lock", _set_pin, "ok" if has_pin else "")
	if has_pin:
		_row_action("PIN entfernen", "Das Profil öffnet sich danach ohne PIN.", "", "close", func() -> void:
			main.open_dialog("PIN entfernen?", "Danach kann jeder dieses Profil wählen.", [
				["PIN entfernen", func() -> void: _change({ "pin": {} })],
				["Abbrechen", func() -> void: pass],
			], "lock")
		)
	_kid_rows(p, me)
	_label("Profil")
	if not me:
		_row_action("Zu diesem Profil wechseln", "Uzai startet neu.", "", "user",
				func() -> void:
			var go := func() -> void: main.switch_profile(pid)
			if p.has("pin"):
				_ask_pin(main, "check", p, "", go)
			else:
				go.call()
		)
	if not me and Config.profile_list().size() > 1:
		_row_action("Profil löschen", "Spiele und andere Profile bleiben.", "", "trash", _ask_delete,
				"warn")
	elif me:
		_row_info("Profil löschen", "Aktives Profil nicht löschbar.", "Aktiv", "trash")


func _header(p: Dictionary, me: bool) -> void:
	var row := U.hbox(22)
	var av = ProfileAvatar.new().setup(p, 96, true)
	row.add_child(av)
	var col := U.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := U.label(str(p.name), "xl", "text", "bold")
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(n)
	var bits: Array = ["Dein Profil" if me else "Anderes Profil"]
	if bool(p.kid):
		bits.append("Kinderprofil")
	col.add_child(U.label(" · ".join(PackedStringArray(bits)), "m", "muted", "regular"))
	row.add_child(col)
	var m := U.margin(8, 0, 8, 0)
	m.add_child(row)
	add_row(m)


func _kid_rows(p: Dictionary, me: bool) -> void:
	_label("Kinderprofil")
	var need := Config.profile_guard("rules", pid)
	if need != "" and not _rules_ok:
		_row_action("Regeln ändern", "Nur mit Eltern-PIN änderbar." if need == "parent"
				else "Dafür braucht es die PIN dieses Profils.",
			"Eltern-PIN" if need == "parent" else "PIN", "lock", func() -> void:
				_ask_pin(main, need if need == "parent" else "check", p, "Zum Ändern der Regeln.", func() -> void:
					_rules_ok = true
					refill()
				)
		)
		if bool(p.kid):
			_row_info("Regeln", _rules_text(p.rules), "", "info")
		return
	var kid := _row_toggle("Kinderprofil", "Altersstufe, Shop, Browser, Chats und Spielzeit.", bool(p.kid))
	kid.changed.connect(func(v: Variant) -> void: _change({ "kid": bool(v) }))
	if not bool(p.kid):
		if Config.parent_ids().is_empty():
			_row_info("Tipp", "Erst eine PIN für dein Profil festlegen.", "", "info")
		return
	var rules: Dictionary = (p.rules as Dictionary).duplicate()
	var age := _row_choice("Altersfreigabe bis",
			"Spiele über dieser Stufe werden ausgeblendet.", int(rules.age), Profiles.AGES)
	age.changed.connect(func(v: Variant) -> void: _rule("age", int(v)))
	var unk := _row_toggle("Spiele ohne Altersangabe zeigen",
			"Aus: Spiele ohne Altersangabe ausblenden.", bool(rules.unknown))
	unk.changed.connect(func(v: Variant) -> void: _rule("unknown", bool(v)))
	var shop := _row_toggle("Shop erlaubt", "", bool(rules.shop))
	shop.changed.connect(func(v: Variant) -> void: _rule("shop", bool(v)))
	var web := _row_toggle("Browser und Links erlaubt", "", bool(rules.browser))
	web.changed.connect(func(v: Variant) -> void: _rule("browser", bool(v)))
	var chat := _row_toggle("Chats und Sprachkanäle erlaubt",
			"Nachrichten, Anrufe und Sprachkanäle.", bool(rules.chats))
	chat.changed.connect(func(v: Variant) -> void: _rule("chats", bool(v)))
	var lim_opts: Array = Profiles.LIMITS.map(func(n: int) -> Array: return [n, "Ohne Grenze" if n == 0 else _minutes(n)])
	var lim := _row_choice("Spielzeit je Tag", "Hinweis vor Ablauf. Mehr Zeit mit Eltern-PIN.", int(rules.limit), lim_opts)
	lim.changed.connect(func(v: Variant) -> void: _rule("limit", int(v)))
	if me and int(rules.limit) > 0:
		var used := Profiles.time_used(Config.kid_time(), Config.kid_today())
		_row_info("Heute gespielt", "Zählt je Kalendertag, nur Spiele, die über Uzai laufen.", "%s von %s" % [_minutes(used / 60), _minutes(int(rules.limit))],
				"clock")


static func _minutes(n: int) -> String:
	if n < 60:
		return "%d Min." % n
	if n % 60 == 0:
		return "%d Std." % (n / 60)
	return "%d Std. %d Min." % [n / 60, n % 60]


static func _rules_text(r: Dictionary) -> String:
	var bits: Array = ["bis %d Jahre" % int(r.get("age", 12))]
	if int(r.get("limit", 0)) > 0:
		bits.append("%s am Tag" % _minutes(int(r.limit)))
	for k in [["shop", "Shop"], ["browser", "Browser"], ["chats", "Chats"]]:
		if not bool(r.get(k[0], false)):
			bits.append("%s aus" % k[1])
	return " · ".join(PackedStringArray(bits))


func _rule(key: String, v: Variant) -> void:
	var r: Dictionary = (Profiles.find(Config.profiles, pid).get("rules", {}) as Dictionary).duplicate()
	r[key] = v
	_change({ "rules": r }, false)


func _change(changes: Dictionary, rebuild := true) -> void:
	if not Config.update_profile(pid, changes):
		return
	if rebuild:
		refill()
	else:
		# Nur den Kopf neu (Bild, Farbe): die Zeile mit dem Fokus bleibt stehen.
		var first := content.get_child(0) if content.get_child_count() > 0 else null
		if first:
			var av := first.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.has_method("set_profile"))
			for a in av:
				a.set_profile(Profiles.find(Config.profiles, pid))


func _set_pin() -> void:
	var pin = ProfilePin.new()
	pin.mode = "set"
	pin.target = Profiles.find(Config.profiles, pid)
	pin.reason = "4 bis 8 Ziffern. Zweimal eingeben."
	pin.made.connect(func(rec: Dictionary) -> void:
		_change({ "pin": rec })
		Toasts.show_toast("PIN gespeichert", "Gilt ab jetzt.", "lock")
	)
	main.open_layer(pin)


func _ask_delete() -> void:
	var p := Profiles.find(Config.profiles, pid)
	var need := Config.profile_guard("delete", pid)
	if need == "no":
		return
	var confirm := func() -> void:
		main.open_dialog("„%s“ löschen?" % str(p.name), "Einstellungen, Anmeldungen, Spielzeit und Zimmer dieses Profils werden gelöscht. Nicht rückgängig zu machen.", [
			["Endgültig löschen", func() -> void:
				var r := Config.delete_profile(pid)
				if bool(r.ok):
					Toasts.show_toast("Profil gelöscht", str(r.text) if str(r.text) != "" else "Seine Daten sind weg, alles andere ist geblieben.", "trash")
					close()
				else:
					Toasts.show_toast("Nicht gelöscht", str(r.text), "warning")],
			["Abbrechen", func() -> void: pass],
		], "trash", "danger")
	if need == "":
		confirm.call()
	else:
		_ask_pin(main, "parent" if need == "parent" else "check", p, "Zum Löschen dieses Profils.", confirm)


# --- Zeilen -----------------------------------------------------------------------------------

func _label(text: String) -> void:
	var m := U.margin(22, 18, 22, 6)
	m.add_child(U.label(text, "s", "muted", "bold"))
	add_row(m)


func _prep(r: Control, desc: String) -> Control:
	r.set_meta("uz_key", "profil-edit:%s:%s" % [pid, r.get("title")])
	r.set("compact", true)
	r.focus_entered.connect(func() -> void: set_help(desc))
	add_row(r)
	return r


func _row_action(t: String, desc: String, value_text: String, icon: String, cb: Callable, tone := "") -> Control:
	var r = SettingRow.new()
	r.setup("action", t, desc)
	r.value_text = value_text
	r.on_activate = cb
	r.icon_name = icon
	r.tone = tone
	return _prep(r, desc)


func _row_info(t: String, desc: String, value_text: String, icon: String) -> Control:
	var r = SettingRow.new()
	r.setup("info", t, desc)
	r.value_text = value_text
	r.icon_name = icon
	return _prep(r, desc)


func _row_toggle(t: String, desc: String, on: bool) -> Control:
	var r = SettingRow.new()
	r.setup("toggle", t, desc, on)
	return _prep(r, desc)


func _row_choice(t: String, desc: String, v: Variant, options: Array) -> Control:
	var r = SettingRow.new()
	r.setup("choice", t, desc, v)
	r.options = options
	return _prep(r, desc)
