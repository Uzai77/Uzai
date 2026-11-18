extends RefCounted
## Oberfläche rund um Speicherplatz (Storage rechnet, Installs spricht mit Steam): vor
## „Installieren“ zeigen, ob das Spiel passt, und bei knappem Platz deutlich nachfragen; dazu die
## Unterseite Einstellungen → System → Speicher mit Laufwerken, Spielen nach Größe und Aufräumen.
## Deinstallieren und Verschieben gehen immer über den Launcher selbst – Uzai löscht und verschiebt
## keine Spieldateien. Aufräumen nur in Uzais Datenordner, mit Rückfrage. Alles mit dem Controller.

const U := preload("res://src/ui/u.gd")
const Storage := preload("res://src/core/storage.gd")
const P := preload("res://src/core/install_parse.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const SplitBar := preload("res://src/ui/components/split_bar.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const EpicScanner := preload("res://src/library/epic_scanner.gd")
const Main := preload("res://src/main.gd")
const STORES := { "steam": "Steam", "epic": "Epic Games", "ea": "EA app" }

## Demo (--demo): zwei Laufwerke wie an einem typischen Spiele-PC, damit Seite und Warnung etwas zeigen.
const DEMO_DRIVES := [
	{ "name": "C:", "label": "System", "total": 999653638144, "free": 195421011968 },
	{ "name": "D:", "label": "Spiele", "total": 1999307276288, "free": 44023414784 },
]

static var _drives: Array = []     ## letzte Antwort des Helfers („drives“); leer = noch keine
static var _measured := {}         ## Spielordner → Bytes (EA, im Hintergrund gemessen)
static var _clean_files := {}      ## Aufräum-Kennung → Dateien beim letzten Zählen
static var _spiele: Array = []     ## games_stand: die zuletzt gelesene Liste
static var _spiele_da := false     ## schon einmal gelesen? (sonst heißt „leer“ noch nicht „keine Spiele“)
static var _spiele_liest := false  ## der Hilfsfaden liest gerade
static var _spiele_warten: Array[Callable] = []


# --- Vor dem Installieren -----------------------------------------------------------------------

## Wohin ein neues Spiel geht: der gewählte Steam-Bibliotheksordner, sonst Steams Hauptordner; bei
## Epic der Standardordner des Launchers. "" = unbekannt.
static func target_dir(g: Dictionary) -> String:
	var src := str(g.get("source", ""))
	if Library.demo:
		return "D:/SteamLibrary" if src == "steam" else ("C:/Program Files/Epic Games" if src == "epic" else "")
	if src == "steam":
		var lib := str(Config.get_value("library.steam_install_lib", ""))
		if lib != "" and DirAccess.dir_exists_absolute(lib.path_join("steamapps")):
			return lib
		return Library.steam_root()
	if src == "epic":
		return Installs.epic_default_dir()
	return ""


## Freier Platz dort in Bytes, -1 unbekannt. Gibt es den Ordner noch nicht (Epic-Standardordner vor
## dem ersten Spiel), zählt der nächste vorhandene darüber.
static func free_at(dir: String) -> int:
	if dir == "":
		return -1
	if Library.demo:
		for d in DEMO_DRIVES:
			if str(d.name) == Storage.drive_of(dir):
				return int(d.free)
		return -1
	var d := dir.replace("\\", "/")
	while not DirAccess.dir_exists_absolute(d):
		var up := d.get_base_dir()
		if up == d or up == "":
			return -1
		d = up
	var da := DirAccess.open(d)
	# 0 heißt bei Godot auch „ließ sich nicht abfragen“ – lieber unbekannt als eine falsche Warnung.
	var free := int(da.get_space_left()) if da else 0
	return free if free > 0 else -1


## Platzbedarf aus den Systemanforderungen im Shop, soweit schon geladen (-1 = unbekannt).
static func need_cached(g: Dictionary) -> int:
	var appid := int(g.get("appid", 0))
	if str(g.get("source", "")) != "steam" or appid <= 0:
		return -1
	return Storage.size_from_requirements(Store.cached(appid).get("req_min", []))


## Platzbedarf, notfalls kurz aus dem Shop geholt – höchstens zwei Sekunden, länger soll
## „Installieren“ nie hängen.
static func need_for(g: Dictionary) -> int:
	var appid := int(g.get("appid", 0))
	if str(g.get("source", "")) != "steam" or appid <= 0 or not Store.cached(appid).is_empty():
		return need_cached(g)
	var box := { "done": false }
	var fetch := func() -> void:
		await Store.details(appid)
		box.done = true
	fetch.call()
	var tree := Engine.get_main_loop() as SceneTree
	var until := Time.get_ticks_msec() + 2000
	while not bool(box.done) and Time.get_ticks_msec() < until:
		await tree.process_frame
	return need_cached(g)


## Kurz für die Spielseite: „ca. 45,0 GB · 210,3 GB frei auf D:“ ("" wenn nichts bekannt).
static func page_note(g: Dictionary) -> String:
	var dir := target_dir(g)
	return Storage.note(need_cached(g), free_at(dir), Storage.drive_of(dir))


## Vor dem Installieren: passt das Spiel, geht es gleich weiter (go); wird es knapp oder passt es
## nicht, fragt Uzai deutlich nach.
static func check_install(main: Main, g: Dictionary, go: Callable) -> void:
	var dir := target_dir(g)
	var free := free_at(dir)
	var need := await need_for(g)
	if Storage.space_level(need, free) in ["", "ok"]:
		go.call()
		return
	ask_space(main, g, need, free, Storage.drive_of(dir), go)


static func ask_space(main: Main, g: Dictionary, need: int, free: int, drive: String, go: Callable) -> void:
	var title := Library.display_title(g)
	var level := Storage.space_level(need, free)
	var head := ("Zu wenig Platz auf %s" if level == "voll" else "Wenig Platz auf %s") % drive
	var text := ""
	if level == "voll":
		text = "%s braucht etwa %s, frei sind %s." % [title, P.gb(float(need)), P.gb(float(free))]
	elif need > 0:
		text = "%s braucht etwa %s. Danach blieben %s frei." % [title, P.gb(float(need)), P.gb(float(free - need))]
	else:
		text = "Noch %s frei. Größe von %s unbekannt." % [P.gb(float(free)), title]
	text += "\n\nEinstellungen → System → Speicher."
	var look := ["Speicher ansehen", func() -> void: open_page(main)]
	var cancel := ["Abbrechen", func() -> void: pass]
	var btns: Array = [["Trotzdem installieren", func() -> void: go.call()], look, cancel]
	if level == "voll":
		btns = [look, ["Trotzdem versuchen", func() -> void: go.call()], cancel]
	main.open_dialog(head, text, btns, "warning", "warn")


## Einstellungen → System → Speicher öffnen (auch aus Dialogen und anderen Seiten).
static func open_page(main: Main) -> void:
	# Spielseite oder Shop-Seite schließen: Die Speicher-Seite liegt in den Einstellungen.
	for l in Nav.layers.duplicate():
		if is_instance_valid(l) and l.has_method("close"):
			l.call("close")
	await main.goto("settings", "system")
	var sv = main.sections.get("settings")
	if sv and sv.has_method("open_more"):
		sv.open_more("Speicher")


# --- Seite „Speicher“: Spiele und Laufwerke ------------------------------------------------------

## Installierte Spiele mit Größe, soweit verlässlich bekannt: Steam (SizeOnDisk im appmanifest),
## Epic (InstallSize im Manifest), EA (Ordner gemessen, im Hintergrund – bis dahin -1). PC-Spiele
## fehlen: Ihr Ordner ist nicht sicher bekannt (oft nur eine Verknüpfung auf dem Desktop).
## Größte zuerst: [{ id, title, store, bytes, dir, drive, appid }].
## Der zuletzt gelesene Stand, ohne die Platte anzufassen – games_auffrischen() liest neu. Vor dem ersten Lesen
## leer; games_gelesen() sagt, ob „leer“ schon „keine Spiele“ heißt.
static func games_stand() -> Array:
	return _demo_games() if Library.demo else _spiele


static func games_gelesen() -> bool:
	return Library.demo or _spiele_da


## Liest die Manifeste von Steam und Epic im Hilfsfaden (bei 400 Steam-Spielen sonst 60 ms und mehr im
## Hauptfaden) und ordnet sie hier den Spielen zu. cb() nur, wenn die Liste danach anders ist oder zum ersten
## Mal da. Läuft schon ein Lesen, wartet cb auf dessen Ergebnis.
static func games_auffrischen(cb := Callable()) -> void:
	if Library.demo:
		return
	if cb.is_valid():
		_spiele_warten.append(cb)
	if _spiele_liest:
		return
	_spiele_liest = true
	var libs: Array = SteamScanner.library_dirs(Library.steam_root()).duplicate()
	var epic_dir := EpicScanner.manifest_dir()
	var roh: Variant = await Arbeit.ergebnis(func() -> Array: return [Storage.steam_installed(libs), Storage.epic_installed(epic_dir)])
	_spiele_liest = false
	var warten := _spiele_warten.duplicate()
	_spiele_warten.clear()
	if not (roh is Array and roh.size() == 2 and roh[0] is Dictionary and roh[1] is Dictionary):
		return
	var neu := _games_aus(roh[0], roh[1])
	if _spiele_da and neu == _spiele:
		return
	_spiele = neu
	_spiele_da = true
	for c in warten:
		if c.is_valid():
			c.call()


## Die gelesenen Manifeste den Spielen der Bibliothek zuordnen (Hauptfaden), dazu die EA-Spiele mit ihrer
## gemessenen Größe.
static func _games_aus(steam: Dictionary, epic: Dictionary) -> Array:
	var out: Array = []
	for appid in steam:
		var g := Library.get_game("steam:%d" % int(appid))
		if not g.is_empty():
			out.append(_entry(g, "steam", int(steam[appid].bytes), str(steam[appid].dir)))
	for app in epic:
		var g := Library.get_game("epic:%s" % app)
		if not g.is_empty() and Library.is_installed(g):
			out.append(_entry(g, "epic", int(epic[app].bytes), str(epic[app].dir)))
	for g in Library.games:
		if str(g.get("source", "")) == "ea" and Library.is_installed(g) and str(g.get("install_dir", "")) != "":
			out.append(_entry(g, "ea", int(_measured.get(str(g.install_dir), -1)), str(g.install_dir)))
	return Storage.by_size(out)


static func _entry(g: Dictionary, store: String, bytes: int, dir: String) -> Dictionary:
	return { "id": str(g.get("id", "")), "title": Library.display_title(g), "store": store, "bytes": bytes,
		"dir": dir, "drive": Storage.drive_of(dir), "appid": int(g.get("appid", 0)) }


static func _demo_games() -> Array:
	var out: Array = []
	for g in Library.games:
		var src := str(g.get("source", ""))
		if not (src in STORES) or not Library.is_installed(g):
			continue
		# Feste, glaubwürdige Größen aus der Kennung (gleich bei jedem Start).
		var h := int(str(g.get("id", "")).hash() & 0x7fffffff)
		var dir := "%s/%s" % ["D:/SteamLibrary/steamapps/common" if src == "steam" else "C:/Program Files/%s" % ("Epic Games" if src == "epic" else "EA Games"),
				Library.display_title(g)]
		out.append(_entry(g, src, (4 + h % 96) * Storage.GIB + ((h >> 7) % 1024) * 1048576, dir))
	return Storage.by_size(out)


## EA-Spiele ohne bekannte Größe im Hintergrund messen; cb(Ordner, Bytes) je Spiel.
static func measure_ea(list: Array, cb: Callable) -> void:
	for e in list:
		if str(e.store) != "ea" or int(e.bytes) >= 0:
			continue
		var dir := str(e.dir)
		var bytes := int(_measured.get(dir, -1))
		if bytes < 0:
			var r: Variant = await Arbeit.ergebnis(P.dir_size.bind(dir), Arbeit.LANG)
			bytes = r if r is int else -1
		if bytes > 0:
			_measured[dir] = bytes
			if cb.is_valid():
				cb.call(dir, bytes)


## Laufwerke für die Seite: vom Helfer (Größe und frei), ohne ihn nur die Laufwerke mit Spielen und
## Uzais Daten (nur frei). Dazu je Laufwerk, was die bekannten Spiele belegen.
static func drives(list: Array) -> Array:
	var out: Array = (DEMO_DRIVES if Library.demo else _drives).duplicate(true)
	if out.is_empty():
		var seen := {}
		var dirs: Array = [Config.data_dir]
		dirs.append_array(SteamScanner.library_dirs(Library.steam_root()))
		for e in list:
			dirs.append(str(e.dir))
		for d in dirs:
			var dr := Storage.drive_of(str(d))
			if dr == "" or seen.has(dr):
				continue
			seen[dr] = true
			out.append({ "name": dr, "label": "", "total": -1, "free": free_at(str(d)) })
	var per := Storage.games_per_drive(list)
	for d in out:
		d["games"] = int(per.get(str(d.name), 0))
	return out


## Laufwerke frisch vom Helfer holen (nur lesen). cb() nur, wenn sich etwas geändert hat.
static func refresh_drives(cb: Callable) -> void:
	if Library.demo or not Config.is_windows() or not Helper.available:
		return
	var r := await Helper.run("drives", {}, 5.0)
	var list := Storage.drives_from(r.get("result")) if bool(r.get("ok", false)) else []
	if list.is_empty() or list == _drives:
		return
	_drives = list
	if cb.is_valid():
		cb.call()


## Kurz für die Zeile „Speicher …“: freier Platz dort, wo Uzais Daten liegen.
static func summary() -> String:
	var dir := "C:/" if Library.demo else Config.data_dir
	var free := free_at(dir)
	return ("%s frei auf %s" % [P.gb(float(free)), Storage.drive_of(dir)]) if free >= 0 else ""


## Je Laufwerk Name, freier Platz und ein Balken „Spiele · Anderes · Frei“, der beim Öffnen weich
## aufläuft (wie das Speicher-Menü einer Konsole). Nur zum Ansehen, nicht auswählbar.
static func drive_card(list: Array) -> Control:
	var m := U.margin(22, 6, 22, 10)
	var col := U.vbox(20)
	m.add_child(col)
	if list.is_empty():
		col.add_child(U.label("Keine Laufwerke gefunden", "s", "muted"))
		return m
	var c_games := UzTheme.col("accent")
	var c_other := UzTheme.col("muted", 0.5)
	var c_free := UzTheme.col("text", 0.1)
	for d in list:
		var free := int(d.free)
		var total := int(d.total)
		var v := U.vbox(9)
		var top := U.hbox(12)
		top.add_child(U.label(str(d.name), "m", "text", "bold"))
		if str(d.get("label", "")) != "":
			var lb := U.label(str(d.label), "s", "muted", "medium")
			lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(lb)
		top.add_child(U.spacer())
		var txt := "Unbekannt"
		if total > 0:
			txt = "%s frei von %s" % [P.gb(float(free)), P.gb(float(total))]
		elif free >= 0:
			txt = "%s frei" % P.gb(float(free))
		var val := U.label(txt, "s", "warn" if free >= 0 and free < Storage.RESERVE else "muted", "medium")
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(val)
		v.add_child(top)
		if total > 0:
			var used := total - free
			var games_b := clampi(int(d.get("games", 0)), 0, used)
			var parts: Array = []
			if games_b > 0:
				parts.append({ "value": games_b, "color": c_games })
			if used - games_b > 0:
				parts.append({ "value": used - games_b, "color": c_other })
			if free > 0:
				parts.append({ "value": free, "color": c_free })
			v.add_child(SplitBar.new().setup(parts, 12))
		col.add_child(v)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 36)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in [["Spiele", c_games], ["Anderes", c_other], ["Frei", c_free]]:
		var h := U.hbox(9)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", UzTheme.box(it[1], 6))
		h.add_child(dot)
		h.add_child(U.label(str(it[0]), "s", "muted", "medium"))
		legend.add_child(h)
	col.add_child(legend)
	return m


# --- Deinstallieren und Verschieben: nur über den Launcher ---------------------------------------

## A auf einem Spiel der Seite: was sich tun lässt. done() baut die Seite danach neu.
static func game_options(main: Main, e: Dictionary, done: Callable) -> void:
	var size := P.gb(float(e.bytes)) if int(e.bytes) > 0 else "Größe unbekannt"
	var text := "%s auf Laufwerk %s · %s\n%s" % [size, str(e.drive), STORES.get(str(e.store), ""), str(e.dir).replace("/", "\\")]
	var btns: Array = [
		["Deinstallieren", func() -> void: uninstall(main, e, done)],
		["Verschieben", func() -> void: move(main, e)],
	]
	if not Library.get_game(str(e.id)).is_empty():
		btns.append(["Zur Spielseite", func() -> void: main.open_game_note(Library.get_game(str(e.id)))])
	btns.append(["Zurück", func() -> void: pass])
	main.open_dialog(str(e.title), text, btns, "drive")


static func uninstall(main: Main, e: Dictionary, done: Callable) -> void:
	var title := str(e.title)
	var size := P.gb(float(e.bytes)) if int(e.bytes) > 0 else ""
	match str(e.store):
		"steam":
			var text := "Das Spiel wird von %s gelöscht. Spielstände in der Steam Cloud bleiben." % str(e.drive)
			if size != "":
				text = "Das Spiel wird von %s gelöscht, etwa %s werden frei. Spielstände in der Steam Cloud bleiben." % [str(e.drive), size]
			if Installs.steam_direct():
				main.open_dialog("%s deinstallieren?" % title, text, [
					["Deinstallieren", func() -> void: _steam_uninstall(main, e, done), "danger"],
					["Abbrechen", func() -> void: pass],
				], "trash", "warn")
			else:
				text += "\n\nOhne Steam-Anmeldung: Steam Big Picture → Einstellungen → Speicher."
				main.open_dialog("%s deinstallieren" % title, text, [
					["Big Picture öffnen", func() -> void: _big_picture()],
					["Abbrechen", func() -> void: pass],
				], "trash")
		"epic":
			main.open_dialog("%s deinstallieren" % title, "Im Epic Games Launcher: Bibliothek → „…“ → Verwalten → Deinstallieren.", [["OK", func() -> void: pass]], "trash")
		_:
			main.open_dialog("%s deinstallieren" % title,
					"In der EA app: Bibliothek → Spiel → „…“ → Deinstallieren.",
					[["OK", func() -> void: pass]], "trash")


static func _steam_uninstall(main: Main, e: Dictionary, done: Callable) -> void:
	var why := await Installs.steam_uninstall(int(e.appid))
	if why != "":
		Toasts.show_toast("Deinstallieren ging nicht", why, "warning", { "ms": 6000 })
		return
	Toasts.show_toast("Steam deinstalliert %s" % str(e.title), ("Etwa %s werden frei." % P.gb(float(e.bytes))) if int(e.bytes) > 0
			else "Die Bibliothek merkt es von selbst.", "trash", { "ms": 4500 })
	if Library.demo:
		return
	# Steam braucht ein paar Sekunden; danach Bibliothek und Seite neu einlesen.
	main.get_tree().create_timer(8.0).timeout.connect(func() -> void:
		Library.scan()
		if done.is_valid():
			done.call()
	)


static func move(main: Main, e: Dictionary) -> void:
	var title := str(e.title)
	match str(e.store):
		"steam":
			main.open_dialog("%s verschieben" % title, "In Steam Big Picture: Einstellungen → Speicher → Spiel markieren → „Verschieben“.", [
				["Big Picture öffnen", func() -> void: _big_picture()],
				["Abbrechen", func() -> void: pass],
			], "move")
		"epic":
			main.open_dialog("%s verschieben" % title,
					"Im Epic Games Launcher: Bibliothek → „…“ → Verwalten → Verschieben.",
					[["OK", func() -> void: pass]], "move")
		_:
			main.open_dialog("%s verschieben" % title, "In der EA app: Bibliothek → Spiel → „…“ → Verwalten.", [["OK", func() -> void: pass]], "move")


static func _big_picture() -> void:
	if Library.demo:
		Toasts.show_toast("Demo: Steam würde jetzt Big Picture öffnen", "", "steam", { "ms": 3000 })
		return
	OS.shell_open("steam://open/bigpicture")


# --- Aufräumen: nur Uzais eigene Daten -----------------------------------------------------------

## Was jeder Aufräum-Eintrag freigäbe, im Hintergrund gezählt: cb(Kennung, Bytes, Dateien).
static func measure_clean(cb: Callable) -> void:
	var dd := Config.data_dir
	for c in Storage.CLEAN:
		var id := str(c[0])
		var r: Variant = await Arbeit.ergebnis(Storage.clean_files.bind(dd, id), Arbeit.LANG)
		var files: Array = r if r is Array else []
		_clean_files[id] = files
		if cb.is_valid():
			cb.call(id, Storage.files_bytes(files), files.size())


## A auf einem Aufräum-Eintrag: zeigen, was frei wird, und erst nach „Löschen“ löschen.
static func ask_clean(main: Main, id: String, done: Callable) -> void:
	var def: Array = []
	for c in Storage.CLEAN:
		if c[0] == id:
			def = c
	if def.is_empty():
		return
	if id == "puffer" and (Capture.state != "aus" or Capture.recording or Capture.saving):
		Toasts.show_toast("Geht gerade nicht", "Der Aufnahme-Puffer läuft (Spiel vorn oder Aufnahme). Danach noch einmal.", "warning", { "ms": 5000 })
		return
	if not _clean_files.has(id):
		Toasts.show_toast("Einen Moment", "Uzai zählt noch, was frei würde.", "clock", { "ms": 2500 })
		return
	var files: Array = _clean_files[id]
	if files.is_empty():
		Toasts.show_toast("Schon leer", str(def[1]), "check", { "ms": 2500 })
		return
	var text := "Gibt etwa %s frei (%s). %s" % [Storage.size_text(Storage.files_bytes(files)),
			U.plural(files.size(), "Datei", "Dateien"), str(def[3])]
	main.open_dialog("%s löschen?" % str(def[1]), text, [
		["Löschen", func() -> void: _clean(id, files, done), "danger"],
		["Abbrechen", func() -> void: pass],
	], "trash", "warn")


static func _clean(id: String, files: Array, done: Callable) -> void:
	# Der Puffer könnte inzwischen angelaufen sein (Spiel gestartet): dann nichts anfassen.
	if id == "puffer" and (Capture.state != "aus" or Capture.recording or Capture.saving):
		Toasts.show_toast("Geht gerade nicht", "Der Aufnahme-Puffer läuft gerade. Danach noch einmal.", "warning", { "ms": 4000 })
		return
	var r: Variant = await Arbeit.ergebnis(Storage.delete_files.bind(files, Config.data_dir), Arbeit.LANG)
	var res: Dictionary = r if r is Dictionary else {}
	_clean_files.erase(id)
	var left := int(res.get("left", 0))
	Toasts.show_toast("Aufgeräumt: %s frei" % Storage.size_text(int(res.get("freed", 0))),
			"%s gelöscht" % U.plural(int(res.get("count", 0)), "Datei", "Dateien") + (" · %d in Gebrauch, bleiben" % left if left > 0 else ""), "check",
			{ "sound": "select", "ms": 4000 })
	if done.is_valid():
		done.call()
