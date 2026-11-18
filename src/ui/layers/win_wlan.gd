extends "res://src/ui/layers/sheet.gd"
## WLAN mit dem Controller (Einstellungen → System → Windows → WLAN, Uzai-Doktor „Kein Netz“):
## oben der Funk (an/aus, mit Rückfrage beim Ausschalten), dann das verbundene Netz (A: trennen),
## darunter die Netze in der Nähe – je Name nur der stärkste Zugangspunkt, mit Schloss und Balken.
## A verbindet: bekannte Netze direkt, neue mit Passwort über die Bildschirmtastatur (verdeckt, ohne
## Handy-Eingabe), offene erst nach einer Rückfrage. Y sucht neu. Alles über Windows selbst
## (src/core/win_einst.gd); Uzai speichert kein Passwort.

const WinEinst := preload("res://src/core/win_einst.gd")
const WinRow := preload("res://src/ui/components/win_row.gd")
const SELF := "res://src/ui/layers/win_wlan.gd"
const POLL_S := 1.0

const Main := preload("res://src/main.gd")
var main: Main
var _st := {}                    ## parse_wlan
var _loaded := false
var _scanning := false
var _joining := ""               ## SSID, mit der Windows gerade verbindet
static var _demo_state := {}


static func open_for(m: Main) -> Control:
	var s = load(SELF).new()
	s.setup("WLAN", "Netze in der Nähe, über Windows", 780)
	m.open_layer(s)
	return s


func build() -> void:
	set_meta("uz_hints", [["y", "Neu suchen"]])
	super()
	_scan()


func handle(cmd: String) -> bool:
	if cmd == "y":
		Sfx.play("tick")
		_scan()
		return true
	return false


func fill() -> void:
	if not _loaded:
		add_label("Sucht Netze …", "s", "faint")
		return
	var st := str(_st.state)
	if st in ["windows", "helfer", "admin", "kein", "fehler"]:
		_explain(st)
		return
	var radio = SettingRow.new()
	radio.setup("toggle", "WLAN", "", str(_st.radio) != "aus")
	radio.icon_name = "wifi"
	radio.subtitle = _net_text()
	radio.set_meta("uz_key", "wl:radio")
	radio.changed.connect(_set_radio)
	add_row(radio)
	if st == "aus" or str(_st.radio) == "aus":
		add_gap(10)
		add_label("WLAN ist aus.", "s", "faint")
		return
	if st == "zugriff":
		add_gap(10)
		_explain(st)
		return
	var nets: Array = _st.networks
	var con: Array = nets.filter(func(n: Dictionary) -> bool: return bool(n.connected))
	if not con.is_empty():
		add_gap(6)
		add_label("Verbunden")
		add_row(_net_row(con[0]))
	add_gap(6)
	var head := add_label(tr("Netze in der Nähe") + ("  ·  " + tr("sucht …") if _scanning else ""))
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var others: Array = nets.filter(func(n: Dictionary) -> bool: return not bool(n.connected))
	if others.is_empty():
		add_label("Keine weiteren Netze.", "s", "faint")
	for n in others:
		add_row(_net_row(n))


func _net_text() -> String:
	if str(_st.connected) != "":
		var i: String = { "ok": "Internet ist da", "lokal": "ohne Internet", "keins": "ohne Internet" }.get(str(_st.internet), "")
		return tr("Verbunden mit %s") % WinEinst.clean_text(_st.connected, "?") + ("  ·  " + tr(i) if i != "" else "")
	return tr("Nicht verbunden")


func _net_row(n: Dictionary) -> Control:
	var r = WinRow.new()
	var block := WinEinst.connect_block(n)
	r.setup(str(n.name), WinEinst.net_line(n), "wifi")
	r.bars = int(n.bars)
	r.lock = str(n.kind) in ["psk", "firma", "wep"]
	r.on = bool(n.connected)
	r.dim = block != ""
	if bool(n.connected):
		r.state = tr("Verbunden")
	elif str(n.ssid) == _joining:
		r.state = tr("Verbindet …")
	r.set_meta("uz_key", "wl:" + str(n.ssid))
	r.set_meta("uz_hint_a", "Trennen" if bool(n.connected) else ("Mehr dazu" if block != "" else "Verbinden"))
	r.activated.connect(_on_net.bind(n))
	return r


func _explain(code: String) -> void:
	var s := WinEinst.status(code)
	add_label(str(s[0]), "m", "text")
	add_label(str(s[1]), "s", "muted")


# --- Laden -----------------------------------------------------------------------------------

## Läufe von _scan, die gerade unterwegs sind (siehe dort).
var _scan_offen := 0


func _scan() -> void:
	_scan_offen += 1
	await _scan_lauf()
	_scan_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _scan täte bis zum Neustart nichts mehr.
	if _scan_offen == 0 and _scanning:
		_scanning = false


func _scan_lauf() -> void:
	if _scanning:
		return
	_scanning = true
	if _loaded:
		refill()
	if _demo():
		if _demo_state.is_empty():
			_demo_state = WinEinst.DEMO_WLAN.duplicate(true)
		await get_tree().create_timer(0.6).timeout
		_st = WinEinst.parse_wlan(_demo_state)
	elif Helper.available:
		var r := await Helper.run("wlan-state", { "scan": 1 }, 14.0)
		_st = WinEinst.parse_wlan(r.get("result")) if bool(r.get("ok", false)) else { "state": WinEinst.code_of(r) }
	else:
		_st = { "state": "windows" if not Config.is_windows() else "helfer" }
	_scanning = false
	if not is_inside_tree() or _closing:
		return
	_loaded = true
	refill()
	await get_tree().process_frame
	if is_inside_tree() and Nav.top_layer() == self and (Nav.focused() == null or not content.is_ancestor_of(Nav.focused())):
		var d := Nav.default_in(content)
		if d:
			Nav.focus(d, true)


func _demo() -> bool:
	return Library.demo and not Config.is_windows()


# --- Handlungen ------------------------------------------------------------------------------

func _on_net(n: Dictionary) -> void:
	if _joining != "":
		return
	if bool(n.connected):
		main.open_dialog(tr("Von %s trennen?") % str(n.name), "", [
			["Trennen", _disconnect],
			["Abbrechen", func() -> void: pass],
		], "wifi")
		return
	var block := WinEinst.connect_block(n)
	if block != "":
		var s := WinEinst.status(block)
		main.open_dialog(str(s[0]), str(s[1]), [["OK", func() -> void: pass]], "wifi", "warn")
		return
	if WinEinst.needs_key(n):
		_ask_key(n)
	elif str(n.kind) == "offen" and not bool(n.known):
		main.open_dialog(tr("Mit %s verbinden?") % str(n.name), "Offenes Netz, nicht verschlüsselt.", [
			["Verbinden", func() -> void: _connect(n, "")],
			["Abbrechen", func() -> void: pass],
		], "wifi", "warn")
	else:
		_connect(n, "")


## Passwort über die Bildschirmtastatur: verdeckt, ohne Handy-Eingabe. Passt es nicht zu den Regeln
## von WPA, sagt Uzai es sofort (und fragt neu), statt Windows raten zu lassen.
func _ask_key(n: Dictionary) -> void:
	var kb = load("res://src/ui/layers/keyboard.gd").new()
	kb.heading = tr("Passwort für %s") % str(n.name)
	kb.secret = true
	kb.phone_ok = false
	kb.done.connect(func(t: String) -> void:
		kb.text = ""
		if t == "":
			return
		var why := WinEinst.key_problem(t)
		if why != "":
			Toasts.show_toast("Passwort passt nicht", tr(why) + " " + tr("Noch einmal eingeben."), "warning")
			_ask_key.call_deferred(n)
			return
		_connect(n, t))
	main.open_layer(kb)


func _connect(n: Dictionary, key: String) -> void:
	var args := WinEinst.connect_args(n, key)
	key = ""
	if args.is_empty():
		_report("daten")
		return
	_joining = str(n.ssid)
	refill()
	var code := ""
	if _demo():
		args.clear()
		await get_tree().create_timer(1.4).timeout
		_demo_state.connected = str(n.ssid)
		for e in _demo_state.networks:
			if str(e.ssid) == str(n.ssid):
				e.known = true
		code = "verbunden"
	else:
		var r := await Helper.run("wlan-connect", args, 15.0)
		args.clear()
		code = WinEinst.code_of(r)
		var t0 := Time.get_ticks_msec()
		while code in ["gestartet", "laeuft"] and Time.get_ticks_msec() - t0 < 50000:
			await get_tree().create_timer(POLL_S).timeout
			code = WinEinst.code_of(await Helper.run("wlan-poll", {}, 6.0))
			if code == "nichts":
				code = "fehler"
	_joining = ""
	if not is_inside_tree():
		return
	_report(code, str(n.name))
	if code == "passwort" and str(n.kind) == "psk":
		var again := n.duplicate()
		again.known = false
		_ask_key(again)
	WinEinst.refresh_lage(true)
	_scan()


func _disconnect() -> void:
	var code := "getrennt"
	if _demo():
		_demo_state.connected = ""
	else:
		code = WinEinst.code_of(await Helper.run("wlan-disconnect", {}, 8.0))
	if not is_inside_tree():
		return
	_report(code)
	WinEinst.refresh_lage(true)
	_scan()


func _set_radio(v: Variant) -> void:
	var on := bool(v)
	if on:
		_radio(true)
		return
	var frage: Control = main.open_dialog("WLAN ausschalten?", "Ohne Kabel ist der PC dann offline.", [
		["Ausschalten", func() -> void: _radio(false)],
		["Abbrechen", func() -> void: pass],
	], "wifi", "warn")
	# Wie auch immer die Rückfrage zugeht (auch mit B): Der Schalter zeigt wieder den echten Stand (wie bei Bluetooth).
	frage.closed.connect(func() -> void:
		if is_inside_tree() and not _closing:
			refill()
	, CONNECT_DEFERRED)


func _radio(on: bool) -> void:
	var code := "ok"
	if _demo():
		_demo_state.radio = "an" if on else "aus"
		_demo_state.code = "ok" if on else "aus"
	else:
		code = WinEinst.code_of(await Helper.run("radio-set", WinEinst.radio_args("wlan", on), 12.0))
	if not is_inside_tree():
		return
	if code != "ok":
		_report(code)
	WinEinst.refresh_lage(true)
	_scan()


## Ergebnis als Mitteilung: Erfolg leise, alles andere mit Rat (Sätze aus WinEinst.STATUS).
func _report(code: String, name := "") -> void:
	var s := WinEinst.status(code)
	if str(s[2]) == "ok":
		var title := (tr("Verbunden mit %s") % name) if code == "verbunden" and name != "" else tr(str(s[0]))
		Toasts.show_toast(title, str(s[1]), "wifi", { "quiet": true })
	else:
		Toasts.show_toast(str(s[0]), str(s[1]), "warning" if str(s[2]) == "warn" else "wifi")
