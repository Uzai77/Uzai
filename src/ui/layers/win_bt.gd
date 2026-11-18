extends "res://src/ui/layers/sheet.gd"
## Bluetooth mit dem Controller (Einstellungen → System → Windows → Bluetooth, Uzai-Doktor
## „Bluetooth ist aus“): oben der Funk – an/aus über Windows.Devices.Radios, nur auf deinen Druck,
## Ausschalten mit Rückfrage –, darunter die gekoppelten Geräte mit „Verbunden“. A an einem Gerät
## erklärt Verbinden und Trennen (gekoppelte Geräte verbindet Windows selbst, sobald sie an sind;
## einen offiziellen Weg, das für Programme auszulösen, gibt es nicht) und bietet „Entfernen“ an.
## Controller koppeln führt zu pad_pair.gd. Logik in src/core/win_einst.gd.

const WinEinst := preload("res://src/core/win_einst.gd")
const WinRow := preload("res://src/ui/components/win_row.gd")
const SELF := "res://src/ui/layers/win_bt.gd"

const Main := preload("res://src/main.gd")
var main: Main
var _st := {}
var _loaded := false
static var _demo_state := {}


static func open_for(m: Main) -> Control:
	var s = load(SELF).new()
	s.setup("Bluetooth", "Gekoppelte Geräte, über Windows", 780)
	m.open_layer(s)
	return s


func build() -> void:
	set_meta("uz_hints", [["y", "Neu laden"]])
	super()
	_load()


func handle(cmd: String) -> bool:
	if cmd == "y":
		Sfx.play("tick")
		_load()
		return true
	return false


func fill() -> void:
	if not _loaded:
		add_label("Einen Moment …", "s", "faint")
		return
	var st := str(_st.state)
	if not (st in ["an", "aus"]):
		var s := WinEinst.status(st)
		add_label(str(s[0]), "m", "text")
		add_label(str(s[1]), "s", "muted")
		return
	var devs: Array = _st.devices
	var n_on := devs.filter(func(d: Dictionary) -> bool: return bool(d.connected)).size()
	var radio = SettingRow.new()
	radio.setup("toggle", "Bluetooth", "", st == "an")
	radio.icon_name = "bluetooth"
	radio.subtitle = (tr("%d verbunden") % n_on) if st == "an" and n_on > 0 else ("An" if st == "an" else "Aus – gekoppelte Geräte verbinden sich nicht")
	radio.set_meta("uz_key", "bl:radio")
	radio.changed.connect(_set_radio)
	add_row(radio)
	add_gap(6)
	add_label("Gekoppelte Geräte")
	if devs.is_empty():
		add_label("Keine Geräte.", "s", "faint")
	for d in devs:
		var r = WinRow.new()
		r.setup(str(d.name), tr(_kind_text(str(d.kind))), WinEinst.bt_icon(str(d.kind)))
		r.on = bool(d.connected) and st == "an"
		r.state = tr("Verbunden") if r.on else ""
		r.dim = st != "an"
		r.set_meta("uz_key", "bl:" + str(d.id))
		r.set_meta("uz_hint_a", "Optionen")
		r.activated.connect(_on_dev.bind(d))
		add_row(r)
	add_gap(6)
	var pair = SettingRow.new()
	pair.setup("action", "Controller koppeln")
	pair.icon_name = "controller"
	pair.subtitle = "Xbox, PlayStation, Nintendo – im Kopplungsmodus"
	pair.on_activate = func() -> void: load("res://src/ui/layers/pad_pair.gd").open_for(main)
	pair.set_meta("uz_key", "bl:pair")
	add_row(pair)
	add_gap(10)


static func _kind_text(k: String) -> String:
	return { "pad": "Controller", "audio": "Kopfhörer oder Lautsprecher", "tastatur": "Tastatur", "maus": "Maus", "handy": "Telefon" }.get(k, "Bluetooth-Gerät")


func _demo() -> bool:
	return Library.demo and not Config.is_windows()


func _load() -> void:
	if _demo():
		if _demo_state.is_empty():
			_demo_state = WinEinst.DEMO_BT.duplicate(true)
		_st = WinEinst.parse_bt(_demo_state)
	elif Helper.available:
		var r := await Helper.run("bt-paired", {}, 12.0)
		_st = WinEinst.parse_bt(r.get("result")) if bool(r.get("ok", false)) else { "state": WinEinst.code_of(r), "devices": [] }
	else:
		_st = { "state": "windows" if not Config.is_windows() else "helfer", "devices": [] }
	if not is_inside_tree() or _closing:
		return
	_loaded = true
	refill()
	await get_tree().process_frame
	if is_inside_tree() and Nav.top_layer() == self and (Nav.focused() == null or not content.is_ancestor_of(Nav.focused())):
		var d := Nav.default_in(content)
		if d:
			Nav.focus(d, true)


func _on_dev(d: Dictionary) -> void:
	var how := "Verbindet sich beim Einschalten." if not bool(d.connected) \
		else "Zum Trennen das Gerät ausschalten."
	main.open_dialog(str(d.name), tr(how) + "\n\n" + tr("Danach neu koppeln."), [
		["Schließen", func() -> void: pass],
		["Entfernen", func() -> void: _unpair(d), "danger"],
	], WinEinst.bt_icon(str(d.kind)))


func _unpair(d: Dictionary) -> void:
	var code := "entfernt"
	if _demo():
		_demo_state.devices = (_demo_state.devices as Array).filter(func(e: Dictionary) -> bool: return str(e.id) != str(d.id))
	else:
		code = WinEinst.code_of(await Helper.run("bt-unpair", { "id": str(d.id) }, 20.0))
	if not is_inside_tree():
		return
	var s := WinEinst.status(code)
	if str(s[2]) == "ok":
		Toasts.show_toast(tr("Entfernt: %s") % str(d.name), str(s[1]), "bluetooth", { "quiet": true })
	else:
		Toasts.show_toast(str(s[0]), str(s[1]), "warning")
	WinEinst.refresh_lage(true)
	_load()


func _set_radio(v: Variant) -> void:
	if bool(v):
		_radio(true)
		return
	var frage: Control = main.open_dialog("Bluetooth ausschalten?",
			"Bluetooth-Geräte werden getrennt.", [
		["Ausschalten", func() -> void: _radio(false)],
		["Abbrechen", func() -> void: pass],
	], "bluetooth", "warn")
	# Wie auch immer die Rückfrage zugeht (auch mit B): Der Schalter zeigt wieder den echten Stand – früher blieb er
	# nach B auf „aus“ stehen, obwohl Bluetooth an war. Nach „Ausschalten“ lädt _radio ohnehin neu.
	frage.closed.connect(func() -> void:
		if is_inside_tree() and not _closing:
			refill()
	, CONNECT_DEFERRED)


func _radio(on: bool) -> void:
	var code := "ok"
	if _demo():
		_demo_state.code = "an" if on else "aus"
	else:
		code = WinEinst.code_of(await Helper.run("radio-set", WinEinst.radio_args("bt", on), 12.0))
	if not is_inside_tree():
		return
	if code != "ok":
		var s := WinEinst.status(code)
		Toasts.show_toast(str(s[0]), str(s[1]), "warning")
	WinEinst.refresh_lage(true)
	_load()
