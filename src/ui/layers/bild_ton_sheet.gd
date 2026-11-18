extends "res://src/ui/layers/sheet.gd"
## „Bild & Ton“ (Roadmap 4/16): Guide → System, auch über dem Spiel, und Einstellungen → System →
## Windows. Wie die Schnelleinstellungen einer Konsole: oben die Tonausgaben als Zeilen (A schaltet
## um, die aktive trägt den Haken), darunter der Bildschirm, auf dem Uzai liegt – Auflösung,
## Bildwiederholrate, HDR. Neue Auflösung oder Hz fragt „Behalten?“ (keep_dialog.gd, 15 s, sonst
## zurück). Alles über die Helfer-Befehle der Spiel-Profile; Logik in src/core/bild_ton.gd.

const BildTon := preload("res://src/core/bild_ton.gd")
const WinEinst := preload("res://src/core/win_einst.gd")
const GameProfile := preload("res://src/core/game_profile.gd")
const WinRow := preload("res://src/ui/components/win_row.gd")
const KeepDialog := preload("res://src/ui/layers/keep_dialog.gd")
const SELF := "res://src/ui/layers/bild_ton_sheet.gd"

const Main := preload("res://src/main.gd")
var main: Main
var _audio := { "devices": [], "current": "" }
var _disp := {}
var _screen := ""              ## Name und Anschluss des Bildschirms („LG TV · HDMI“)
var _loaded := false
var _busy := false


static func open_for(m: Main) -> Control:
	var s = load(SELF).new()
	s.setup("Bild & Ton", "Tonausgabe und Bildschirm", 780)
	m.open_layer(s)
	return s


func build() -> void:
	super()
	_load()


func fill() -> void:
	if not _loaded:
		add_label("Einen Moment …", "s", "faint")
		return
	if not (Config.is_windows() or Library.demo):
		add_label("Das geht nur am Windows-PC.", "m", "muted")
		return
	add_label("Ton ausgeben über")
	var devs: Array = _audio.devices
	if devs.is_empty():
		add_label("Keine Tonausgabe.", "s", "faint")
	for d in devs:
		var cur := str(d.id) == str(_audio.current)
		var r = WinRow.new()
		# Nennt der Name die Art schon („Kopfhörer (…)“), bleibt die zweite Zeile leer.
		var kt := tr(BildTon.kind_text(str(d.kind)))
		r.setup(str(d.name), "" if str(d.name).to_lower().contains(kt.to_lower()) else kt, BildTon.kind_icon(str(d.kind)))
		r.on = cur
		r.state = tr("Aktiv") if cur else ""
		r.set_meta("uz_key", "bt:audio:" + str(d.id))
		r.set_meta("uz_hint_a", "—" if cur else "Hierüber ausgeben")
		if cur:
			r.set_meta("uz_default", true)
		r.activated.connect(_set_audio.bind(d))
		add_row(r)
	add_gap()
	var head := add_label("Bild")
	if _screen != "":
		head.text = "%s  ·  %s" % [tr("Bild"), _screen]
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if _disp.is_empty():
		add_label("Bildschirm nicht erkannt. Erneut öffnen.", "s", "faint")
		return
	var res = SettingRow.new()
	res.setup("action", "Auflösung")
	res.icon_name = "monitor"
	res.value_text = BildTon.res_text(int(_disp.w), int(_disp.h))
	res.on_activate = _pick_res
	res.set_meta("uz_key", "bt:res")
	add_row(res)
	var hz = SettingRow.new()
	hz.setup("action", "Bildwiederholrate")
	hz.icon_name = "speed"
	hz.value_text = BildTon.rate_text(int(_disp.hz))
	hz.on_activate = _pick_rate
	hz.set_meta("uz_key", "bt:hz")
	add_row(hz)
	var h := str(_disp.get("hdr", ""))
	var hdr = SettingRow.new()
	if h in ["an", "moeglich"]:
		hdr.setup("toggle", "HDR", "", h == "an")
		hdr.subtitle = ""
		hdr.changed.connect(_set_hdr)
	else:
		hdr.setup("info", "HDR")
		hdr.value_text = "Nicht verfügbar"
		hdr.subtitle = "Dieser Bildschirm meldet kein HDR." if h == "nein" else "Windows meldet den HDR-Stand gerade nicht."
	hdr.icon_name = "spark"
	hdr.set_meta("uz_key", "bt:hdr")
	add_row(hdr)
	add_gap(10)
	add_label(tr("Ohne „Behalten“ nach %d Sekunden zurück.") % BildTon.KEEP_S, "s",
			"faint")


func _load() -> void:
	if BildTon._demo():
		var ad: Array = BildTon.DEMO_AUDIO.duplicate(true)
		if BildTon.demo_audio == "":
			BildTon.demo_audio = str(ad[0].id)
		for d in ad:
			d["default"] = str(d.id) == BildTon.demo_audio
		_audio = BildTon.parse_audio({ "ok": true, "result": { "devices": ad } })
		_disp = BildTon.demo_info(BildTon.demo_mode, BildTon.demo_hdr)
		_screen = "LG OLED65C3 · HDMI"
	elif Helper.available:
		# Über Mixer.tonwahl: Führt FxSound den Ton, steht sein eigenes Gerät nicht in der Liste, und „Aktiv“ ist
		# das Gerät, auf das FxSound ausgibt.
		_audio = await Mixer.tonwahl.geraete_lesen()
		var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id())
		_disp = GameProfile.parse_modes(await Helper.run("display-modes", { "hwnd": hwnd }, 10.0), 200)
		var di := await Helper.run("display-info", { "hwnd": hwnd }, 8.0)
		_screen = _screen_text(di.get("result") if bool(di.get("ok", false)) else {})
	if not is_inside_tree() or _closing:
		return
	_loaded = true
	refill()
	await get_tree().process_frame
	if is_inside_tree() and Nav.top_layer() == self and (Nav.focused() == null or not content.is_ancestor_of(Nav.focused())):
		var d := Nav.default_in(content)
		if d:
			Nav.focus(d, true)


## „LG TV · HDMI“ aus display-info (Name vom Bildschirm selbst: fremder Text, bereinigt).
static func _screen_text(d: Variant) -> String:
	if not (d is Dictionary):
		return ""
	var name := WinEinst.clean_text((d as Dictionary).get("name", ""), "", 40)
	var tech: String = { "hdmi": "HDMI", "dp": "DisplayPort", "intern": TranslationServer.translate("eingebaut"),
			"drahtlos": TranslationServer.translate("drahtlos") }.get(str(d.get("tech", "")), "")
	return "  ·  ".join(PackedStringArray([name, tech].filter(func(x: String) -> bool: return x != "")))


# --- Ton -------------------------------------------------------------------------------------

func _set_audio(d: Dictionary) -> void:
	if str(d.id) == str(_audio.current) or _busy:
		return
	_busy = true
	var ok := true
	if BildTon._demo():
		BildTon.demo_audio = str(d.id)
	else:
		ok = await Mixer.tonwahl.ausgeben_ueber(str(d.id), _audio)
	_busy = false
	if not is_inside_tree():
		return
	if not ok:
		Toasts.show_toast("Tonausgabe nicht umgestellt", "Gerät nicht übernommen. Erneut versuchen.", "warning")
		return
	Sfx.play("select")
	_audio.current = str(d.id)
	for r in content.get_children():
		if r is WinRow and str(r.get_meta("uz_key", "")).begins_with("bt:audio:"):
			var on := str(r.get_meta("uz_key")) == "bt:audio:" + str(d.id)
			r.set_state(tr("Aktiv") if on else "", on)
			r.set_meta("uz_hint_a", "—" if on else "Hierüber ausgeben")
	Nav.focus_moved.emit(Nav.focused())


# --- Bild ------------------------------------------------------------------------------------

func _pick_res() -> void:
	var opts: Array = []
	for m in BildTon.resolutions(_disp.modes):
		var k := "%dx%d" % [int(m.w), int(m.h)]
		var t := BildTon.res_text(int(m.w), int(m.h))
		if int(m.w) == int(_disp.w) and int(m.h) == int(_disp.h):
			t += "  (%s)" % tr("jetzt")
		opts.append([k, t])
	main.open_choice("Auflösung", opts, "%dx%d" % [int(_disp.w), int(_disp.h)], func(v: Variant) -> void:
		var p := str(v).split("x")
		if p.size() != 2:
			return
		var w := int(p[0])
		var h := int(p[1])
		_try(w, h, BildTon.pick_rate(_disp.modes, w, h, int(_disp.hz)))
	, tr("Ohne „Behalten“ nach %d Sekunden zurück.") % BildTon.KEEP_S)


func _pick_rate() -> void:
	var opts: Array = []
	for r in BildTon.rates(_disp.modes, int(_disp.w), int(_disp.h)):
		opts.append([int(r), BildTon.rate_text(int(r)) + ("  (%s)" % tr("jetzt") if int(r) == int(_disp.hz) else "")])
	main.open_choice("Bildwiederholrate", opts, int(_disp.hz), func(v: Variant) -> void:
		_try(int(_disp.w), int(_disp.h), int(v))
	, tr("Mehr Hz: flüssigeres Bild."))


func _try(w: int, h: int, hz: int) -> void:
	if hz <= 0 or BildTon.same_mode(_disp, w, h, hz) or _busy:
		return
	_busy = true
	var r := await BildTon.change_mode(_disp, w, h, hz, _after)
	_busy = false
	if not bool(r.get("ok", false)):
		if is_inside_tree():
			Toasts.show_toast("Auflösung nicht umgestellt",
					tr("%s abgelehnt.") % (BildTon.res_text(w, h) + " · " + BildTon.rate_text(hz)), "warning")
		return
	var d = KeepDialog.new()
	d.text = "%s  ·  %s" % [BildTon.res_text(w, h), BildTon.rate_text(hz)]
	main.open_layer(d)
	_reload()


## Ende der Rückfrage (Behalten, Zurück, Frist um): neu lesen, und ohne Antwort kurz sagen, warum.
func _after(kept: bool, timeout: bool) -> void:
	if timeout and not kept:
		Toasts.show_toast("Zurückgestellt", "", "monitor")
	_reload()


func _reload() -> void:
	if not is_inside_tree() or _closing:
		return
	if BildTon._demo():
		_disp = BildTon.demo_info(BildTon.demo_mode, BildTon.demo_hdr)
	elif Helper.available:
		var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id())
		var info := GameProfile.parse_modes(await Helper.run("display-modes", { "hwnd": hwnd }, 10.0), 200)
		if not info.is_empty():
			_disp = info
	if is_inside_tree() and not _closing:
		refill()


func _set_hdr(v: Variant) -> void:
	var on := bool(v)
	var ok := true
	if BildTon._demo():
		BildTon.demo_hdr = "an" if on else "moeglich"
	else:
		var r := GameProfile.reply(await Helper.run("display-hdr", { "device": str(_disp.device), "on": 1 if on else 0 }, 12.0))
		ok = bool(r.get("ok", false))
	if not is_inside_tree():
		return
	if not ok:
		Toasts.show_toast("HDR nicht umgestellt", "HDR nicht umgestellt. Kabel und Bildschirm prüfen.", "warning")
	_reload()
