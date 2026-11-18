extends "res://src/ui/layers/sheet.gd"
## Spiel-Profil (Spieloptionen → Profil) oder die Vorlage für alle Spiele eines Systems
## (game leer). Was hier steht, gilt beim Start und geht nach dem Spiel zurück (profile_run.gd).
## Jede Zeile zeigt, was gilt: eigener Wert, „Wie Vorlage (…)“ oder „Nicht ändern“.
## Auflösung und Tonausgabe fragen erst beim Öffnen der Auswahl bei Windows nach.

const GameProfile := preload("res://src/core/game_profile.gd")
const SheetLayer := preload("res://src/ui/layers/sheet.gd")
const COPY_MAX := 150      ## so viele Spiele des Systems zum Übertragen (Liste bleibt flüssig)
const RECENT_MAX := 12
## Demo ohne Windows: ein Bildschirm und zwei Audiogeräte.
const DEMO_MODES := [[3840, 2160, 60], [2560, 1440, 120], [1920, 1080, 120], [1920, 1080, 60], [1280, 720, 60]]
const DEMO_AUDIO := [["{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a001}", "Wohnzimmer-TV (HDMI)"],
	["{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a002}", "Headset (USB)"]]

var game: Dictionary = {}      ## leer: Vorlage für tpl_id
var tpl_id := ""
const Main := preload("res://src/main.gd")
var main: Main
var _hdr := ""                 ## HDR laut Windows ("" unbekannt), für den Hinweis an der Zeile


func is_template() -> bool:
	return game.is_empty()


func build() -> void:
	if not is_template():
		tpl_id = GameProfile.template_id(game)
	if is_template():
		setup(tr("Vorlage: alle %s-Spiele") % _tpl_name(), tr("Gilt für jedes %s-Spiel, das selbst nichts anderes festlegt.") % _tpl_name(), 820)
	else:
		setup("Profil", Library.display_title(game), 820)
		subheading_raw = true      # Name des Spiels
	super()
	if (Config.is_windows() and Helper.available) or Library.demo:
		_load_hdr()


func _tpl_name() -> String:
	return GameProfile.template_name(tpl_id, Config.system(tpl_id))


func _gid() -> String:
	return str(game.get("id", ""))


func _game() -> Dictionary:
	return Library.get_game(_gid()) if not is_template() else {}


## Eigenes Profil (bzw. die Vorlage selbst).
func _own() -> Dictionary:
	return GameProfile.template(tpl_id) if is_template() else GameProfile.own_of(_game())


## Vorlage, aus der das Spiel erbt ({} beim Bearbeiten der Vorlage).
func _tpl() -> Dictionary:
	return {} if is_template() else GameProfile.template(tpl_id)


func _put(k: String, v: Variant) -> void:
	if is_template() and k == "actions" and v is Array and (v as Array).is_empty():
		v = null
	var p := GameProfile.with_value(_own(), k, v, is_template())
	if is_template():
		GameProfile.set_template(tpl_id, p)
	else:
		Library.set_field(_gid(), "profile", p if not p.is_empty() else null)


func _row(kind: String, t: String, v: Variant = null) -> Control:
	var r = SettingRow.new()
	r.setup(kind, t, "", v)
	r.set_meta("uz_key", "prof:" + t)
	return r


## Erste Optionen einer Zeile: erben bzw. nichts ändern.
func _base_opts(k: String) -> Array:
	var tpl := _tpl()
	if tpl.has(k):
		return [["", tr("Wie Vorlage (%s)") % GameProfile.value_text(k, tpl[k])], [GameProfile.KEEP, tr("Nicht ändern")]]
	return [["", tr("Nicht ändern")]]


## Wert einer Zeile als Text ("" = nicht gesetzt: erbt bzw. bleibt).
func _shown(k: String) -> String:
	var own := _own()
	if own.has(k):
		return GameProfile.value_text(k, own[k])
	var tpl := _tpl()
	if tpl.has(k):
		return tr("Wie Vorlage (%s)") % GameProfile.value_text(k, tpl[k])
	return tr("Nicht ändern")


## Auswahlzeile. Zahlen stehen als Text in den Optionen (die Zeile vergleicht nur gleiche Typen,
## und „“/„Nicht ändern“ sind Text) und werden beim Speichern wieder Zahlen.
func _choice_row(k: String, t: String, icon: String, opts: Array) -> Control:
	var own := _own()
	var cur: Variant = own.get(k, "")
	if cur is int or cur is float:
		cur = _num_key(k, cur)
	var r = _row("choice", t, cur)
	r.icon_name = icon
	r.options = _base_opts(k) + opts.map(func(o: Array) -> Array: return [_num_key(k, o[0]) if (o[0] is int or o[0] is float) else o[0], o[1]])
	r.changed.connect(func(v: Variant) -> void:
		_put(k, float(v) if v is String and v.is_valid_float() else v))
	add_row(r)
	return r


static func _num_key(k: String, v: Variant) -> String:
	return str(int(v)) if k == "volume" else "%.3f" % float(v)


func fill() -> void:
	var g := _game()
	var win := Config.is_windows() or Library.demo
	add_label("Bild")
	if win:
		var disp = _row("action", "Auflösung")
		disp.icon_name = "monitor"
		disp.value_text = _shown("display")
		disp.on_activate = _pick_display
		add_row(disp)
		var hdr = _choice_row("hdr", "HDR", "spark", [["an", tr("An")], ["aus", tr("Aus")]])
		if _hdr == "nein":
			hdr.subtitle = tr("Dieser Bildschirm meldet kein HDR.")
	if Lossless.exe_path() != "" or Library.demo:
		var auto_txt := str(
				{ "aus": "nie", "pc": "bei PC-Spielen", "emu": "bei Emulator-Spielen", "alle": "bei allen Spielen" }.get(str(Config.get_value("lossless.auto", "aus")),
				"nie"))
		if is_template():
			var lt = _row("choice", "Lossless Scaling beim Start", str(_own().get("lossless", "")))
			lt.options = [["", tr("Standard (%s)") % tr(auto_txt)], ["an", tr("Immer einschalten")], ["aus", tr("Nie einschalten")]]
			lt.changed.connect(func(v: Variant) -> void: _put("lossless", v))
			lt.icon_name = "bolt"
			add_row(lt)
		else:
			var tl := str(_tpl().get("lossless", ""))
			var std := (tr("Wie Vorlage (%s)") % GameProfile.value_text("lossless", tl)) if tl != "" else tr("Standard (%s)") % tr(auto_txt)
			var ls = _row("choice", "Lossless Scaling beim Start", str(g.get("lossless", "")))
			ls.icon_name = "bolt"
			ls.options = [["", std], ["an", tr("Immer einschalten")], ["aus", tr("Nie einschalten")]]
			ls.changed.connect(func(v: Variant) -> void: Library.set_field(_gid(), "lossless", v if str(v) != "" else null))
			add_row(ls)
	_filter_row(g)

	add_gap()
	add_label("Ton")
	if win:
		var au = _row("action", "Ton ausgeben über")
		au.icon_name = "speaker"
		au.value_text = _shown("audio")
		au.on_activate = _pick_audio
		add_row(au)
	var vols: Array = []
	for v in range(10, 101, GameProfile.VOLUME_STEP):
		vols.append([v, GameProfile.volume_text(v)])
	_choice_row("volume", "Lautstärke des Spiels", "volume", vols)

	add_gap()
	add_label("Controller in Uzais Menü")
	for k in GameProfile.PAD:
		var p: Array = GameProfile.PAD[k]
		var opts: Array = []
		var v := float(p[1])
		while v <= float(p[2]) + 0.0001:
			opts.append([snappedf(v, float(p[3])), GameProfile.pad_text(k, v)])
			v += float(p[3])
		var title := str({ "deadzone": "Stick-Totzone", "repeat_delay": "Wiederholen nach", "repeat_rate": "Tempo beim Halten" }[k])
		var r = _choice_row(k, title, "controller", opts)
		# Ohne eigenen Wert: der eingestellte (Einstellungen → Controller → Feineinstellung).
		if not _tpl().has(k):
			r.options[0][1] = tr("Wie eingestellt (%s)") % GameProfile.pad_text(k, float(Config.get_value(str(p[0]), p[1])))
			r.call("_refresh")

	add_gap()
	add_label("Beim Start")
	var acts = _row("action", "Aktionen")
	acts.icon_name = "bolt"
	acts.value_text = _actions_text()
	acts.on_activate = _open_actions
	add_row(acts)

	if not is_template():
		_share_rows()
	add_gap()
	add_label("Gilt beim Start. Nach dem Spiel zurückgesetzt.", "s", "faint")


## Bildfilter: am Spiel wie in den Spieloptionen, in der Vorlage der Filter des Systems.
func _filter_row(g: Dictionary) -> void:
	var sys := Config.system(tpl_id)
	if (not is_template() and str(g.get("source", "")) != "rom") or (is_template() and not sys.has("emulator")):
		return
	var opts: Array = [["aus", tr("Aus")]]
	for f in Config.filters():
		opts.append([str(f.id), str(f.name)])
	var fr = _row("choice", "Bildfilter", str(g.get("filter", "")) if not is_template() else str(sys.get("filter", "")))
	fr.icon_name = "tv"
	if is_template():
		fr.options = [["", tr("Aus")]] + opts.slice(1)
		fr.changed.connect(func(v: Variant) -> void: Config.set_system(tpl_id, "filter", v))
	else:
		var sf := str(sys.get("filter", ""))
		fr.options = [["", tr("Wie alle %s-Spiele (%s)") % [str(sys.get("short", "")), str(Config.filter(sf).get("name", sf)) if sf != "" else tr("aus")]]] + opts
		fr.changed.connect(func(v: Variant) -> void: Library.set_field(_gid(), "filter", v))
	add_row(fr)


func _actions_text() -> String:
	var own := _own()
	var list: Array = own.get("actions", _tpl().get("actions", []))
	if list.is_empty():
		return tr("Keine")
	return GameProfile.value_text("actions", list)


func _share_rows() -> void:
	add_gap()
	add_label("Teilen")
	var own := _own()
	var tname := _tpl_name()
	var has_own := not own.is_empty() or str(_game().get("lossless", "")) != ""
	if has_own:
		var cp = _row("action", "Auf andere Spiele übertragen")
		cp.icon_name = "send"
		cp.on_activate = _open_copy
		add_row(cp)
	var tp = _row("action", tr("Vorlage für alle %s-Spiele") % tname)
	tp.icon_name = "bookmark"
	var ts := GameProfile.summary(GameProfile.template(tpl_id), 2)
	tp.value_text = ts if ts != "" else tr("Leer")
	tp.on_activate = func() -> void:
		var s = load("res://src/ui/layers/profile_sheet.gd").new()
		s.tpl_id = tpl_id
		s.main = main
		s.closed.connect(refill)
		main.open_layer(s)
	add_row(tp)
	if own.is_empty():
		return
	var mk = _row("action", tr("Als Vorlage für alle %s-Spiele") % tname)
	mk.icon_name = "save"
	mk.on_activate = func() -> void:
		main.open_dialog(tr("Vorlage für alle %s-Spiele?") % tname,
				tr("Gilt für jedes %s-Spiel ohne eigenes Profil.") % tname, [
			[tr("Übernehmen"), func() -> void:
				var old: Variant = Config.get_value(GameProfile.TEMPLATES_KEY, {})
				old = (old as Dictionary).duplicate(true) if old is Dictionary else {}
				var p := own.duplicate(true)
				for k in p.keys():
					if str(p[k]) == GameProfile.KEEP:
						p.erase(k)
				GameProfile.set_template(tpl_id, p)
				Undo.offer_setting("Vorlage gespeichert", tr("alle %s-Spiele") % tname, "bookmark", GameProfile.TEMPLATES_KEY, old, refill)
				refill()],
			[tr("Abbrechen"), func() -> void: pass],
		], "bookmark")
	add_row(mk)
	var rs = _row("action", "Profil zurücksetzen")
	rs.icon_name = "undo"
	rs.on_activate = func() -> void:
		var snap := Library.snapshot([_gid()])
		Library.set_field(_gid(), "profile", null)
		Undo.offer_games("Profil zurückgesetzt", Library.display_title(_game()), "undo", snap, refill)
		refill()
	add_row(rs)


# --- Auswahl mit Windows ---------------------------------------------------------------------

func _load_hdr() -> void:
	var info := await _display_info()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var h := str(info.get("hdr", ""))
	if h != _hdr:
		_hdr = h
		if h == "nein":
			refill()


## Bildschirm unter Uzai: { device, w, h, hz, hdr, modes } – in der Demo erfunden.
func _display_info() -> Dictionary:
	if Library.demo and not Config.is_windows():
		var ms: Array = DEMO_MODES.map(func(m: Array) -> Dictionary: return { "w": m[0], "h": m[1], "hz": m[2] })
		return { "device": "\\\\.\\DISPLAY1", "w": 1920, "h": 1080, "hz": 60, "hdr": "moeglich", "modes": ms }
	if not Helper.available:
		return {}
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id())
	return GameProfile.parse_modes(await Helper.run("display-modes", { "hwnd": hwnd }, 10.0))


func _pick_display() -> void:
	var info := await _display_info()
	if info.is_empty():
		Toasts.show_toast("Bildschirm nicht lesbar", "Auflösungen nicht verfügbar. Erneut versuchen.", "warning")
		return
	var opts := _base_opts("display")
	var by := {}
	for m in info.modes:
		var key := "%dx%d@%d" % [int(m.w), int(m.h), int(m.hz)]
		by[key] = m
		var txt := GameProfile.mode_text(m)
		if int(m.w) == int(info.w) and int(m.h) == int(info.h) and int(m.hz) == int(info.hz):
			txt += " (%s)" % tr("jetzt")
		opts.append([key, txt])
	var own := _own()
	var cur := ""
	if own.get("display") is Dictionary:
		cur = "%dx%d@%d" % [int(own.display.w), int(own.display.h), int(own.display.hz)]
	elif str(own.get("display", "")) == GameProfile.KEEP:
		cur = GameProfile.KEEP
	main.open_choice("Auflösung", opts, cur, func(v: Variant) -> void:
		_put("display", by.get(str(v), v))
		refill()
	, tr("Nur für dieses Spiel."))


func _pick_audio() -> void:
	var devs: Array = []
	if Library.demo and not Config.is_windows():
		devs = DEMO_AUDIO.map(func(d: Array) -> Dictionary: return { "id": d[0], "name": d[1] })
	elif Helper.available:
		var r := await Helper.run("audio-list", {}, 8.0)
		if r.ok and r.result is Dictionary:
			for d in (r.result as Dictionary).get("devices", []):
				if d is Dictionary:
					devs.append({ "id": str(d.get("id", "")), "name": str(d.get("name", "")) })
	if devs.is_empty():
		Toasts.show_toast("Audiogeräte nicht lesbar", "Geräte nicht verfügbar. Erneut versuchen.", "warning")
		return
	var opts := _base_opts("audio")
	var by := {}
	for d in devs:
		by[str(d.id)] = d
		opts.append([str(d.id), str(d.name)])
	var own := _own()
	var cur := str(own.audio.id) if own.get("audio") is Dictionary else str(own.get("audio", ""))
	main.open_choice("Ton ausgeben über", opts, cur, func(v: Variant) -> void:
		_put("audio", by.get(str(v), v))
		refill()
	, tr("Nach dem Spiel wieder das bisherige Gerät."))


# --- Aktionen --------------------------------------------------------------------------------

func _open_actions() -> void:
	var s = SheetLayer.new()
	s.setup("Aktionen beim Start", tr("Nach dem Spiel geht jede zurück."), 760)
	s.fill_func = func(sheet) -> void:
		var own := _own()
		var tpl := _tpl()
		var list: Array = own.get("actions", tpl.get("actions", []))
		for a in GameProfile.ACTIONS:
			var id := str(a[0])
			var r = SettingRow.new()
			r.setup("toggle", str(a[1]), "", list.has(id))
			r.icon_name = str(a[3])
			r.subtitle = tr(str(a[2]))
			r.set_meta("uz_key", "act:" + id)
			r.changed.connect(func(v: Variant) -> void:
				var now: Array = (_own().get("actions", _tpl().get("actions", [])) as Array).duplicate()
				now.erase(id)
				if v:
					now.append(id)
				_put("actions", now)
			)
			sheet.add_row(r)
		if not is_template() and own.has("actions") and tpl.has("actions"):
			sheet.add_gap()
			var back = SettingRow.new()
			back.setup("action", "Wie Vorlage")
			back.icon_name = "bookmark"
			back.value_text = GameProfile.value_text("actions", tpl.actions)
			back.set_meta("uz_key", "act:vorlage")
			back.on_activate = func() -> void:
				_put("actions", null)
				sheet.refill()
			sheet.add_row(back)
		sheet.add_gap()
	s.closed.connect(refill)
	main.open_layer(s)


# --- Übertragen ------------------------------------------------------------------------------

func _open_copy() -> void:
	var gid := _gid()
	var picked := {}
	var same: Array = Library.visible_games().filter(func(x: Dictionary) -> bool:
		return str(x.get("id", "")) != gid and GameProfile.template_id(x) == tpl_id)
	same.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Library.display_title(a).naturalnocasecmp_to(Library.display_title(b)) < 0)
	var recent: Array = Library.visible_games().filter(func(x: Dictionary) -> bool:
		return str(x.get("id", "")) != gid and GameProfile.template_id(x) != tpl_id and int(x.get("last_played", 0)) > 0)
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("last_played", 0)) > int(b.get("last_played", 0)))
	var s = SheetLayer.new()
	s.setup("Profil übertragen", Library.display_title(_game()), 820)
	s.fill_func = func(sheet) -> void:
		var go = SettingRow.new()
		go.setup("action", "Jetzt übertragen")
		go.icon_name = "send"
		go.set_meta("uz_key", "copy:go")
		go.value_text = tr("Erst Spiele wählen")
		go.on_activate = func() -> void:
			if picked.is_empty():
				Sfx.play("bump")
				return
			_copy_to(picked.keys())
			sheet.close()
		sheet.add_row(go)
		var add_games := func(list: Array) -> void:
			for x in list:
				var xid := str(x.id)
				var r = SettingRow.new()
				r.setup("toggle", Library.display_title(x), "", picked.has(xid))
				r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				r.set_meta("uz_key", "copy:" + xid)
				var have := GameProfile.summary(GameProfile.own_of(x), 2)
				if have != "":
					r.subtitle = tr("Hat schon: %s") % have
				r.changed.connect(func(v: Variant) -> void:
					if v:
						picked[xid] = true
					else:
						picked.erase(xid)
					go.value_text = U.plural(picked.size(), "Spiel", "Spiele") if not picked.is_empty() else tr("Erst Spiele wählen")
				)
				sheet.add_row(r)
		if not same.is_empty():
			sheet.add_gap()
			sheet.add_label(tr("Alle %s-Spiele") % _tpl_name())
			add_games.call(same.slice(0, COPY_MAX))
		if not recent.is_empty():
			sheet.add_gap()
			sheet.add_label("Zuletzt gespielt")
			add_games.call(recent.slice(0, RECENT_MAX))
		sheet.add_gap()
		sheet.add_label("Ersetzt das Profil des Spiels.", "s", "faint")
	main.open_layer(s)


## Profil (samt Lossless und – bei Emulator-Spielen – Bildfilter) auf diese Spiele; zurücknehmbar.
func _copy_to(ids: Array) -> void:
	var src := _game()
	var own := _own()
	var snap := Library.snapshot(ids)
	for id in ids:
		var x := Library.get_game(str(id))
		if x.is_empty():
			continue
		Library.set_field(str(id), "profile", own.duplicate(true) if not own.is_empty() else null)
		Library.set_field(str(id), "lossless", src.get("lossless"))
		if str(src.get("source", "")) == "rom" and str(x.get("source", "")) == "rom":
			Library.set_field(str(id), "filter", src.get("filter"))
	Undo.offer_games("Profil übertragen", U.plural(ids.size(), "Spiel", "Spiele"), "send", snap)
