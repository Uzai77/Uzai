extends "res://src/ui/sections/settings_bausteine.gd"
## Einstellungen, Schicht über settings_bausteine.gd: Blätter und Hilfen, die mehrere Kategorien
## brauchen – ein System mit Spieleordner und Emulator, ein Emulator, ein Filter-Profil, Spotify
## verbinden, Sprachen, Game Bar, „Über Uzai“ und der Datenordner.

const Mark := preload("res://src/ui/components/uzai_logo.gd")

const Lang := preload("res://src/core/lang.gd")
const RetroAuto := preload("res://src/core/retro_auto.gd")
const SteamGuide := preload("res://src/core/steam_guide.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
## Reiter der Leiste oben (Einstellungen steht immer da); „apps“ steht für alle App-Symbole
## (src/core/leiste_oben.gd), die einzelnen Apps schaltet „Apps“ darunter.
## Freunde stehen nicht mehr oben (Select öffnet sie als Seitenleiste, freunde_leiste.gd).
const BILDER_MAX := 20000   ## bis hierhin zählt das Blatt „Datenordner“ den Bildspeicher
const SECTION_NAMES := { "games": "Spiele", "shop": "Shop", "achievements": "Profil", "apps": "Apps" }
const SECTION_ORDER := ["games", "shop", "achievements", "apps"]

const LANGS := { "de": "Deutsch", "en": "Englisch", "fr": "Französisch", "es": "Spanisch", "it": "Italienisch", "nl": "Niederländisch",
	"pl": "Polnisch", "pt": "Portugiesisch", "ru": "Russisch", "tr": "Türkisch", "ja": "Japanisch", "ko": "Koreanisch", "zh": "Chinesisch" }


# --- Hilfen und Unterseiten (System, Emulator, Filter, Datenordner) ------------------------

## Bereiche in der Reihenfolge der Leiste oben.
func _section_order() -> Array:
	var out: Array = []
	for sid in Config.get_value("theme.sections", []):
		if SECTION_NAMES.has(sid) and not out.has(sid):
			out.append(sid)
	for sid2 in SECTION_ORDER:
		if not out.has(sid2):
			out.append(sid2)
	return out


func _new_folder() -> void:
	var opts: Array = [["", "Alle Systeme"]]
	for sys in Config.systems_enabled():
		opts.append([str(sys.id), str(sys.name)])
	opts.append(["steam", "Steam"])
	if Config.get_value("library.epic_enabled", true):
		opts.append(["epic", "Epic"])
	if Config.get_value("library.ea_enabled", true):
		opts.append(["ea", "EA"])
	for id in Library.Stores.EXTRA:
		if Library.Stores.enabled(id):
			opts.append([id, Library.Stores.name_of(id, true)])
	opts.append(["pc", "PC"])
	main.open_choice("Ordner für welches System?", opts, "", func(sys_id: Variant) -> void:
		main.open_keyboard("Name des Ordners", "", func(n: String) -> void:
			var fid := Library.create_folder(n, str(sys_id))
			if fid != "":
				_rebuild_keep()
				main.open_folder_picker(fid)
		)
	)


func _add_pc_game() -> void:
	main.open_add_game()


## Abmelden auf der Seite eines Dienstes, mit Rückfrage: Die Zeile steht dort ganz oben unter dem Cursor –
## ein doppelt gedrücktes A hat sonst die Anmeldung gekostet (neu geht sie nur mit Handy oder Browser).
## Im Dialog steht der Cursor auf „Abbrechen“.
func _abmelden_fragen(dienst: String, tun: Callable) -> void:
	main.open_dialog("Von %s abmelden?" % dienst, "Die Anmeldung bei %s wird gelöscht. Spiele und Einstellungen bleiben." % dienst, [
		["Abmelden", tun, "danger"],
		["Abbrechen", func() -> void: pass],
	], "user", "warn")


func _system_row(sys: Dictionary) -> void:
	var sid := str(sys.id)
	var r = SettingRow.new()
	r.setup("toggle", str(sys.name), "", bool(sys.get("enabled", false)))
	r.dot = _system_color(sys)
	var n := Library.count_by_system(sid)
	var emu := str(Config.emulator(str(sys.get("emulator", ""))).get("name", ""))
	var parts := PackedStringArray()
	if n > 0:
		parts.append(U.plural(n, "Spiel", "Spiele"))
	if emu != "":
		parts.append(emu)
	r.subtitle = " · ".join(parts)
	# Eingeschaltet steht das System mit seinem Blatt auf der Seite Emulation (keine dritte Ebene hier).
	r.changed.connect(func(v: Variant) -> void:
		Config.set_system(sid, "enabled", bool(v))
		Library.changed.emit()
	)
	_add(r, "")


func _system_sheet(sid: String) -> void:
	var s = Sheet.new()
	var sys := Config.system(sid)
	s.setup(str(sys.name), "System", 820)
	s.fill_func = func(sheet) -> void:
		var cur := Config.system(sid)
		var dir := Config.rom_dir(sid)
		var dr = SettingRow.new()
		dr.setup("action", "Spieleordner")
		dr.icon_name = "folder"
		dr.value_text = dir if dir != "" else "Nicht festgelegt"
		dr.tone = "faint" if dir == "" else ""
		dr.on_activate = func() -> void:
			main.open_file_browser("Ordner für " + str(cur.name), true, func(p: String) -> void:
				Config.set_rom_dir(sid, p)
				sheet.refill()
				_rebuild_keep()
				Library.scan()
			, [], dir)
		sheet.add_row(dr)
		sheet.add_gap(8)
		var emus: Array = []
		for e in Config.emulators_for(sid):
			emus.append([str(e.id), str(e.name)])
		var er = SettingRow.new()
		er.setup("choice", "Emulator", "", str(cur.get("emulator", "")))
		er.options = emus if not emus.is_empty() else [["", "Keiner"]]
		er.icon_name = "chip"
		er.changed.connect(func(v: Variant) -> void: Config.set_system(sid, "emulator", v))
		sheet.add_row(er)
		var flts: Array = [["", "Aus"]]
		for f in Config.filters():
			flts.append([str(f.id), str(f.name)])
		var fr = SettingRow.new()
		fr.setup("choice", "Bildfilter", "", str(cur.get("filter", "")))
		fr.options = flts
		fr.icon_name = "tv"
		fr.changed.connect(func(v: Variant) -> void: Config.set_system(sid, "filter", v))
		sheet.add_row(fr)
		var sf = SettingRow.new()
		sf.setup("toggle", "Unterordner als Ordner", "", bool(cur.get("subfolders", true)))
		sf.icon_name = "folder"
		sf.changed.connect(func(v: Variant) -> void:
			Config.set_system(sid, "subfolders", bool(v))
			Library.changed.emit()
		)
		sheet.add_row(sf)
		sheet.add_gap(8)
		var cr = SettingRow.new()
		cr.setup("action", "Farbe")
		cr.icon_name = "palette"
		cr.value_text = "Reiter und Cover"
		cr.swatch = _system_color(cur)
		cr.on_activate = func() -> void:
			main.open_color_picker("Farbe für " + str(cur.name), _system_color(cur), func(c: Color) -> void:
				Config.set_system(sid, "color", "#" + c.to_html(false))
				sheet.refill()
			)
		sheet.add_row(cr)
		for spec in [["name", "Name", "edit"], ["short", "Kurzname im Reiter", "tag"]]:
			var key: String = spec[0]
			var tr = SettingRow.new()
			tr.setup("action", spec[1])
			tr.icon_name = str(spec[2])
			tr.value_text = str(cur.get(key, ""))
			tr.on_activate = func() -> void:
				main.open_keyboard(str(spec[1]), str(cur.get(key, "")), func(v: String) -> void:
					if v.strip_edges() != "":
						Config.set_system(sid, key, v.strip_edges())
					sheet.refill()
				)
			sheet.add_row(tr)
		var xr = SettingRow.new()
		xr.setup("action", "Dateiendungen")
		xr.icon_name = "file"
		xr.value_text = ", ".join(PackedStringArray(cur.get("extensions", [])))
		xr.on_activate = func() -> void:
			main.open_keyboard("Dateiendungen, mit Komma getrennt", ", ".join(PackedStringArray(cur.get("extensions", []))), func(v: String) -> void:
				var list: Array = []
				for part in v.split(","):
					var e := part.strip_edges().trim_prefix(".").to_lower()
					if e != "":
						list.append(e)
				Config.set_system(sid, "extensions", list)
				sheet.refill()
			)
		sheet.add_row(xr)
		if str(cur.get("emulator", "")) == "retroarch":
			var core = SettingRow.new()
			core.setup("action", "RetroArch-Kern")
			core.icon_name = "chip"
			core.value_text = str(cur.get("core", ""))
			core.on_activate = func() -> void:
				main.open_keyboard("Kern (Dateiname ohne _libretro.dll)", str(cur.get("core", "")), func(v: String) -> void:
					Config.set_system(sid, "core", v.strip_edges())
					sheet.refill()
				)
			sheet.add_row(core)
		sheet.add_gap()
		var off = SettingRow.new()
		off.setup("action", "System ausschalten" if bool(cur.get("enabled", false)) else "System einschalten")
		off.icon_name = "power"
		off.on_activate = func() -> void:
			var now_on := bool(Config.system(sid).get("enabled", false))
			Config.set_system(sid, "enabled", not now_on)
			Library.changed.emit()
			_rebuild_keep()
			if now_on:
				sheet.close()
			else:
				sheet.refill()
		sheet.add_row(off)
		sheet.add_label("Ordner, Emulator und Spielzeit bleiben gespeichert.", "s", "faint")
	main.open_layer(s)


func _ready_count(list: Array) -> String:
	var ok := 0
	for e in list:
		var exe := str(e.get("exe", ""))
		if exe != "" and FileAccess.file_exists(exe):
			ok += 1
	return "%d von %d bereit" % [ok, list.size()]


func _emu_row(e: Dictionary) -> void:
	var exe := str(e.get("exe", ""))
	var ok := exe != "" and FileAccess.file_exists(exe)
	var eid := str(e.id)
	var names := PackedStringArray()
	for sid in e.get("systems", []):
		names.append(str(Config.system(str(sid)).get("short", sid)))
	var shown_names := names
	if names.size() > 4:
		shown_names = names.slice(0, 4)
		shown_names.append("+%d" % (names.size() - 4))
	var r = _action(str(e.name), "",
		"Bereit" if ok else ("Datei fehlt" if exe != "" else "Nicht eingerichtet"),
			func() -> void: _emu_sheet(eid), "chip", "ok" if ok else ("warn" if exe != "" else "faint"),
		func() -> Control:
			return Preview.table([
				["Programm", exe.get_file() if exe != "" else "Noch nicht gewählt"],
				["Systeme", ", ".join(names) if not names.is_empty() else "Keine"],
				["Startparameter", str(e.get("args", "")) if str(e.get("args", "")) != "" else "Keine"],
			]))
	r.subtitle = " · ".join(shown_names)


func _new_emulator() -> void:
	var opts: Array = [["", "Leer anfangen"]]
	for e in Config.emulators():
		opts.append([str(e.id), "Kopie von %s" % str(e.name)])
	main.open_choice("Neuer Emulator", opts, "", func(tpl: Variant) -> void:
		var base_name := "" if str(tpl) == "" else str(Config.emulator(str(tpl)).get("name", ""))
		main.open_keyboard("Name des Emulators", base_name, func(n: String) -> void:
			n = n.strip_edges()
			if n == "":
				return
			var new_id := Config.add_emulator(n, str(tpl))
			_rebuild_keep()
			_emu_sheet(new_id)
		)
	, "Vorlage wählen")


func _emu_sheet(eid: String) -> void:
	var s = Sheet.new()
	s.setup(str(Config.emulator(eid).get("name", eid)), "Eigener Emulator" if Config.emulator(eid).get("custom", false) else "Emulator", 880)
	s.fill_func = func(sheet) -> void:
		var e := Config.emulator(eid)
		if e.is_empty():
			sheet.close()
			return
		var pr = SettingRow.new()
		pr.setup("action", "Programmdatei")
		pr.icon_name = "file"
		var exe := str(e.get("exe", ""))
		pr.value_text = exe if exe != "" else ("z. B. " + str(e.get("exe_hint", "")) if str(e.get("exe_hint", "")) != "" else "Nicht gewählt")
		pr.tone = "faint" if exe == "" else ("" if FileAccess.file_exists(exe) else "warn")
		pr.on_activate = func() -> void:
			main.open_file_browser("Programmdatei von " + str(e.name), false, func(p: String) -> void:
				Config.set_emulator(eid, "exe", p)
				sheet.refill()
			, ["exe", "bat", "cmd"], str(e.get("exe", "")).get_base_dir())
		sheet.add_row(pr)
		if e.get("custom", false):
			var nr = SettingRow.new()
			nr.setup("action", "Name")
			nr.icon_name = "edit"
			nr.value_text = str(e.get("name", ""))
			nr.on_activate = func() -> void:
				main.open_keyboard("Name des Emulators", str(e.get("name", "")), func(v: String) -> void:
					if v.strip_edges() != "":
						Config.set_emulator(eid, "name", v.strip_edges())
					sheet.refill()
				)
			sheet.add_row(nr)
		var sysr = SettingRow.new()
		sysr.setup("action", "Systeme")
		sysr.icon_name = "games"
		var sn := PackedStringArray()
		for sid in e.get("systems", []):
			sn.append(str(Config.system(str(sid)).get("short", sid)))
		sysr.value_text = ", ".join(sn) if not sn.is_empty() else "Keine"
		sysr.on_activate = func() -> void: _emu_systems(eid, sheet)
		sheet.add_row(sysr)
		for sid in e.get("systems", []):
			var sys := Config.system(str(sid))
			if sys.is_empty() or not sys.get("enabled", false):
				continue
			var dr = SettingRow.new()
			dr.setup("toggle", "Standard für %s" % sys.name, "", str(sys.get("emulator", "")) == eid)
			dr.dot = _system_color(sys)
			var sidc := str(sid)
			dr.changed.connect(func(v: Variant) -> void:
				if v:
					Config.set_system(sidc, "emulator", eid)
				sheet.refill()
			)
			sheet.add_row(dr)
		var ar = SettingRow.new()
		ar.setup("action", "Startparameter")
		ar.icon_name = "keyboard"
		ar.value_text = str(e.get("args", ""))
		ar.on_activate = func() -> void:
			main.open_keyboard("Startparameter", str(e.get("args", "")), func(v: String) -> void:
				Config.set_emulator(eid, "args", v.strip_edges())
				sheet.refill()
			)
		sheet.add_row(ar)
		sheet.add_label("Platzhalter: {rom} · {rom_dir} · {rom_name} · {title} · {core} · {emudir}", "s", "faint")
		sheet.add_gap()
		sheet.add_label("Tastenkürzel für den Guide", "s", "muted")
		for spec in [["save", "Speichern", "save"], ["load", "Laden", "load"], ["screenshot", "Bildschirmfoto", "camera"]]:
			var k: String = spec[0]
			var kr = SettingRow.new()
			kr.setup("action", spec[1])
			kr.icon_name = str(spec[2])
			var cur := str(e.get("keys", {}).get(k, ""))
			kr.value_text = cur if cur != "" else "Keins"
			kr.tone = "faint" if cur == "" else ""
			kr.on_activate = func() -> void:
				main.open_keyboard("Tastenkürzel für " + str(spec[1]), cur, func(v: String) -> void:
					var keys: Dictionary = (Config.emulator(eid).get("keys", {}) as Dictionary).duplicate()
					keys[k] = v.strip_edges()
					Config.set_emulator(eid, "keys", keys)
					sheet.refill()
				)
			sheet.add_row(kr)
		var wr = SettingRow.new()
		wr.setup("action", "Fenstername beim Start")
		wr.icon_name = "monitor"
		wr.value_text = str(e.get("window_hint", ""))
		wr.on_activate = func() -> void:
			main.open_keyboard("So heißt das Fenster, bevor das Spiel läuft", str(e.get("window_hint", "")), func(v: String) -> void:
				Config.set_emulator(eid, "window_hint", v.strip_edges())
				sheet.refill()
			)
		sheet.add_row(wr)
		sheet.add_gap()
		if RetroAuto.KATALOG.has(eid):
			var uz: Dictionary = e.get("uzai", {}) if e.get("uzai") is Dictionary else {}
			var src = SettingRow.new()
			src.setup("action", "Von der offiziellen Quelle")
			src.icon_name = "download"
			src.value_text = (tr("Von Uzai eingerichtet · %s") % str(uz.get("fassung", ""))) if not uz.is_empty() else tr("Laden und einrichten")
			src.tone = "ok" if not uz.is_empty() else "accent"
			src.on_activate = func() -> void:
				var l: Control = load("res://src/ui/layers/retro_einrichten.gd").open_for(main, {}, [], eid)
				l.closed.connect(func() -> void:
					if is_instance_valid(sheet):
						sheet.refill())
			sheet.add_row(src)
		var test = SettingRow.new()
		test.setup("action", "Emulator allein öffnen")
		test.icon_name = "play"
		test.value_text = "Für Steuerung und BIOS"
		test.on_activate = func() -> void:
			var exe2 := str(Config.emulator(eid).get("exe", ""))
			if exe2 == "" or not FileAccess.file_exists(exe2):
				Toasts.show_toast("Programmdatei fehlt", "Erst die .exe des Emulators wählen.", "warning")
				return
			if OS.create_process(exe2, PackedStringArray()) <= 0:
				Toasts.show_toast("%s startet nicht" % str(e.name), "Programmdatei prüfen oder neu wählen.", "warning")
				return
			Toasts.show_toast(str(e.name) + " ist offen", "Uzai läuft im Hintergrund weiter.", "chip", { "ms": 5000 })
		sheet.add_row(test)
		var copy = SettingRow.new()
		copy.setup("action", "Als eigenen Emulator kopieren")
		copy.icon_name = "plus"
		copy.on_activate = func() -> void:
			main.open_keyboard("Name der Kopie", str(e.get("name", "")) + " (eigen)", func(n: String) -> void:
				if n.strip_edges() != "":
					var nid := Config.add_emulator(n.strip_edges(), eid)
					sheet.close()
					_rebuild_keep()
					_emu_sheet(nid)
			)
		sheet.add_row(copy)
		if e.get("custom", false):
			var del = SettingRow.new()
			del.setup("action", "Emulator löschen")
			del.icon_name = "trash"
			del.on_activate = func() -> void:
				main.open_dialog("Emulator löschen?", "„%s“ wird entfernt. Betroffene Systeme brauchen einen anderen Emulator." % str(e.name), [
					["Löschen", func() -> void:
						var back := Config.emulator_backup(eid)
						Config.delete_emulator(eid)
						sheet.close()
						_rebuild_keep()
						Undo.offer_calls("Emulator gelöscht", str(e.name), "trash", [Config.restore_emulator.bind(back)], _rebuild_keep), "danger"],
					["Behalten", func() -> void: pass],
				])
			sheet.add_row(del)
	main.open_layer(s)


func _emu_systems(eid: String, parent) -> void:
	var s = Sheet.new()
	s.setup("Systeme", str(Config.emulator(eid).get("name", "")), 640)
	s.fill_func = func(sheet) -> void:
		var cur: Array = Config.emulator(eid).get("systems", [])
		for sys in Config.systems():
			var sid := str(sys.id)
			var r = SettingRow.new()
			r.setup("toggle", str(sys.name), "", cur.has(sid))
			r.dot = _system_color(sys)
			r.changed.connect(func(v: Variant) -> void:
				var list: Array = (Config.emulator(eid).get("systems", []) as Array).duplicate()
				list.erase(sid)
				if v:
					list.append(sid)
				Config.set_emulator(eid, "systems", list)
			)
			sheet.add_row(r)
	s.closed.connect(func() -> void:
		if is_instance_valid(parent):
			parent.refill()
	)
	main.open_layer(s)


func _filter_sheet(fid: String) -> void:
	var s = Sheet.new()
	var f := Config.filter(fid)
	s.setup(str(f.get("name", fid)), "Bildfilter-Profil", 820)
	s.fill_func = func(sheet) -> void:
		var cur := Config.filter(fid)
		sheet.add_label(str(cur.get("note", "")), "m", "muted")
		sheet.add_gap(4)
		sheet.add_row(Preview.table(cur.get("show", [])))
		sheet.add_gap()
		var own = SettingRow.new()
		own.setup("action", "Eigene ShaderGlass-Profildatei")
		own.icon_name = "file"
		own.value_text = str(cur.get("sgp", "")).get_file() if str(cur.get("sgp", "")) != "" else "Keine"
		own.tone = "faint" if str(cur.get("sgp", "")) == "" else ""
		own.on_activate = func() -> void:
			main.open_file_browser("ShaderGlass-Profil (.sgp)", false, func(p: String) -> void:
				Config.set_value("filters.%s.sgp" % fid, p)
				sheet.refill()
			, ["sgp"])
		sheet.add_row(own)
		if str(cur.get("sgp", "")) != "":
			var rm = SettingRow.new()
			rm.setup("action", "Eigene Datei entfernen")
			rm.icon_name = "trash"
			rm.on_activate = func() -> void:
				Config.set_value("filters.%s.sgp" % fid, "")
				sheet.refill()
			sheet.add_row(rm)
		sheet.add_label("In ShaderGlass über „Save Profile“ speichern, dann hier wählen.", "s", "faint")
	main.open_layer(s)


func _connect_spotify() -> void:
	Toasts.show_toast("Spotify-Anmeldung", "Im Browser bestätigen.", "music")
	var err: String = await Music.connect_spotify()
	Toasts.show_toast("Spotify verbunden" if err == "" else "Spotify nicht verbunden", err, "music" if err == "" else "warning")
	if is_inside_tree() and sub == "konten":
		_rebuild_keep()


func _lang_names(codes: String) -> String:
	var out := PackedStringArray()
	for c in codes.split(","):
		var k := c.strip_edges().to_lower()
		if k != "":
			out.append(str(LANGS.get(k, k)))
	return ", ".join(out)


func _setup_tools() -> void:
	Toasts.show_toast("YouTube wird eingerichtet", "Das kann ein paar Minuten dauern.", "download")
	var err := await YouTube.setup_tools()
	Toasts.show_toast("Fertig" if err == "" else "Nicht ganz geklappt", err, "video" if err == "" else "warning")
	if is_inside_tree() and sub == "medien":
		_rebuild_keep()


## Schalter mit eigenem Standardwert (die Filme-Werte stehen nicht in Config.DEFAULTS).
func _toggle_def(path: String, t: String, desc: String, def: bool) -> Control:
	var r = SettingRow.new()
	r.setup("toggle", t, desc, bool(Config.get_value(path, def)))
	r.set_meta("uz_path", path)
	r.changed.connect(func(v: Variant) -> void: Config.set_value(path, bool(v)))
	return _add(r, desc)


## Xbox Game Bar auf der Guide-Taste: Unter Windows öffnet die Taste sonst zusätzlich die Game
## Bar (holt sich den Fokus über dem Spiel). Umgeschaltet wird nur auf Knopfdruck – dieselbe
## Einstellung des eigenen Windows-Kontos wie unter Windows → Spielen → Game Bar.
func _gamebar_row() -> void:
	var r = _action("Xbox Game Bar auf der Guide-Taste", "Win + G öffnet sie immer.", "…", Callable(), "controller")
	if not Config.is_windows():
		r.value_text = "Nur unter Windows"
		return
	var rr: WeakRef = weakref(r)
	var m: Node = main
	r.on_activate = func() -> void:
		var row = rr.get_ref()
		if row == null:
			return
		if bool(row.get_meta("uz_gamebar_on", true)):
			m.open_dialog("Guide-Taste nur für Uzai?", "Game Bar weiter mit Win + G.", [
				["Abschalten", func() -> void: _set_gamebar(rr, false)],
				["Abbrechen", func() -> void: pass],
			], "controller")
		else:
			_set_gamebar(rr, true)
	# Für den Suchindex gebaut (nicht gezeigt): Windows nicht erst fragen.
	if not _indexing:
		_fetch_gamebar(rr)


static func _fetch_gamebar(rr: WeakRef) -> void:
	_show_gamebar(rr, await Helper.run("gamebar", {}, 4.0))


static func _show_gamebar(rr: WeakRef, res: Dictionary) -> void:
	var row = rr.get_ref()
	if row == null:
		return
	if not res.get("ok", false) or not (res.get("result") is Dictionary):
		row.value_text = "Unbekannt"
		return
	var on := bool((res.result as Dictionary).get("enabled", true))
	row.set_meta("uz_gamebar_on", on)
	row.value_text = "An – öffnet mit" if on else "Aus"


static func _set_gamebar(rr: WeakRef, on: bool) -> void:
	var res := await Helper.run("gamebar", { "set": on }, 4.0)
	_show_gamebar(rr, res)
	if res.get("ok", false):
		Toasts.show_toast("Guide-Taste", "Die Game Bar öffnet wieder mit der Guide-Taste." if on
				else "Game Bar mit Win + G.", "controller", { "sound": "select" })
	else:
		Toasts.show_toast("Guide-Taste nicht umgestellt", Helper.klartext(str(res.get("error", "Helfer antwortet nicht"))), "warning")


## Steam öffnet mit der Guide-Taste Big Picture (steam_guide.gd). Umstellen startet Steam kurz neu.
func _steam_guide_row() -> void:
	var r = _action("Steam auf der Guide-Taste", "An: öffnet zusätzlich Big Picture. Uzai schaltet das beim ersten Start ab, das gilt auch ohne Uzai. Umstellen startet Steam kurz neu.", "…", Callable(), "controller")
	if not Config.is_windows():
		r.value_text = "Nur unter Windows"
		return
	var rr: WeakRef = weakref(r)
	var m: Node = main
	r.on_activate = func() -> void:
		var row = rr.get_ref()
		if row == null or not row.has_meta("uz_steam_aus"):
			return
		var aus := bool(row.get_meta("uz_steam_aus"))
		m.open_dialog("Steam wieder auf der Guide-Taste?" if aus else "Guide-Taste nur für Uzai?", "Steam startet dafür kurz neu.", [
			["Einschalten" if aus else "Abschalten", func() -> void: _set_steam_guide(rr, not aus, m.get_tree())],
			["Abbrechen", func() -> void: pass],
		], "controller")
	if not _indexing:
		_fetch_steam_guide(rr)


static func _fetch_steam_guide(rr: WeakRef) -> void:
	_show_steam_guide(rr, await SteamGuide.stand())


static func _show_steam_guide(rr: WeakRef, aus: Variant) -> void:
	var row = rr.get_ref()
	if row == null:
		return
	if aus == null:
		row.value_text = "Kein Steam"
		return
	row.set_meta("uz_steam_aus", bool(aus))
	row.value_text = "Aus" if bool(aus) else "An – öffnet mit"


static func _set_steam_guide(rr: WeakRef, aus: bool, tree: SceneTree) -> void:
	var row = rr.get_ref()
	if row != null:
		row.value_text = "Steam startet neu …"
	var res := await SteamGuide.stellen(tree, aus, true)
	if bool(res.ok):
		Config.set_value("controller.steam_guide_aus", aus)
		Toasts.show_toast("Guide-Taste", "Nur noch für Uzai." if aus else "Steam öffnet wieder mit.", "controller", { "sound": "select" })
	elif str(res.grund) != "laeuft_schon":
		Toasts.show_toast("Guide-Taste nicht umgestellt", SteamGuide.grund_text(str(res.grund)), "warning")
	_show_steam_guide(rr, await SteamGuide.stand())


## Kopf der Info-Seite: das Zeichen, der Name, die Version.
func _about_card() -> Control:
	var card := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel())
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := U.hbox(30)
	card.add_child(row)
	var mark: Control = Mark.new()
	mark.custom_minimum_size = Vector2(Mark.zeichen_breite(108.0), 108.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var col := U.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Die Wortmarke UZAI (hier steht der Name).
	var name_l: Control = Mark.new()
	name_l.set("mode", "wort")
	name_l.custom_minimum_size = Vector2(Mark.word_width(40.0), 40.0)
	name_l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(name_l)
	col.add_child(U.spacer(0, 8, false))
	col.add_child(U.label("Version %s · %s" % [Config.VERSION, U.plural(Library.visible_games().size(), "Spiel", "Spiele")], "m", "muted", "medium"))
	row.add_child(col)
	return card


## Der Datenordner in Uzai selbst: wo er liegt, was darin ist. Der Explorer ist nur noch die
## letzte, ausdrücklich benannte Möglichkeit (zum Ablegen eigener Dateien).
func _data_sheet() -> void:
	var s = Sheet.new()
	s.setup("Datenordner", "Was Uzai speichert", 820)
	s.fill_func = func(sheet) -> void:
		sheet.add_row(Preview.path_box(Config.data_dir, "Portabel: neben Uzai.exe." if Config.portable else ""))
		sheet.add_gap(10)
		# Der Bildspeicher kann zehntausende Dateien haben: gezählt wird im Hilfsfaden, die Zahl kommt nach.
		var halter := U.vbox(0)
		halter.add_child(Preview.table(_daten_zeilen(-1)))
		sheet.add_row(halter)
		_bilder_zaehlen(halter)
		sheet.add_gap(10)
		var ex = SettingRow.new()
		ex.setup("action", "Im Windows-Explorer öffnen")
		ex.icon_name = "desktop"
		ex.value_text = "Verlässt Uzai"
		ex.tone = "faint"
		ex.on_activate = func() -> void:
			OS.shell_open(Config.data_dir)
			Toasts.show_toast("Explorer ist offen", "Uzai läuft im Hintergrund weiter.", "folder", { "ms": 5000 })
		sheet.add_row(ex)
		sheet.add_label("Für eigene Klänge (Ordner „sounds“) und Cover (Ordner „media“).", "s", "faint")
	main.open_layer(s)


## Zeilen der Übersicht im Blatt „Datenordner“; imgs < 0 = wird noch gezählt.
func _daten_zeilen(imgs: int) -> Array:
	var sounds := _count_files(Config.path("sounds"), 200)
	return [
		["Einstellungen", _file_size(Config.path("settings.json"))],
		["Bibliothek", U.plural(Library.visible_games().size(), "Spiel", "Spiele")],
		["Zwischengespeicherte Bilder", "…" if imgs < 0 else (("%d+" % imgs) if imgs >= BILDER_MAX else str(imgs))],
		["Eigene Klänge (Ordner „sounds“)", "Keine" if sounds == 0 else str(sounds)],
		["Medienordner", "Eigener Ordner" if str(Config.get_value("library.media_dir", "")) != "" else "„media“ im Datenordner"],
	]


func _bilder_zaehlen(halter: Control) -> void:
	var hr: WeakRef = weakref(halter)
	var n: Variant = await Arbeit.ergebnis(_count_files.bind(Config.path("cache/img"), BILDER_MAX))
	var h = hr.get_ref()
	if h and n is int:
		U.clear(h)
		h.add_child(Preview.table(_daten_zeilen(n)))


static func _count_files(dir: String, cap: int) -> int:
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var n := 0
	var stack: Array[String] = [dir]
	while not stack.is_empty() and n < cap:
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		n += da.get_files().size()
		for sub_dir in da.get_directories():
			stack.append(d.path_join(sub_dir))
	return n


static func _file_size(p: String) -> String:
	if not FileAccess.file_exists(p):
		return "Noch keine"
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return "–"
	var b := f.get_length()
	if b < 1024:
		return "%d Byte" % b
	return Lang.dec("%.1f KB" % (b / 1024.0))
