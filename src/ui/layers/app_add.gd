extends "res://src/ui/layers/sheet.gd"
## „App hinzufügen“ („+“ hinter den App-Symbolen oben): eine ruhige Liste in drei Teilen –
## „Deine Apps“ (was schon in der Reihe steht; A entfernt, kurz zurücknehmbar), „Hinzufügen“ (Store-
## Apps, die Windows für dieses Konto meldet, Helfer „store-apps“, nur lesen; bekannte Dienste wie
## Netflix, Disney+, Prime Video zuerst; A fügt hinzu) mit „Programm wählen …“ (Dateiauswahl, nur
## .exe), und „Im Store“ (bekannte Dienste, die nicht installiert sind: A sucht sie im Microsoft
## Store). Logik: src/core/apps_extern.gd.

const Skeleton := preload("res://src/ui/components/skeleton.gd")
const AppsExtern := preload("res://src/core/apps_extern.gd")
const LeisteOben := preload("res://src/core/leiste_oben.gd")
const Zustand := preload("res://src/core/zustand.gd")
## Liste der Store-Apps: lädt (höchstens 40 s beim Helfer), dann fertig.
const ZUSTAENDE := { "laden": ["fertig"], "fertig": [] }

const Main := preload("res://src/main.gd")
var main: Main
var _apps: Array = []           ## installierte Store-Apps [{ aumid, name }]
var _state := "laden":          ## laden | fertig
	set(neu):
		Zustand.wechsel("apps.hinzufuegen", ZUSTAENDE, _state, neu)
		_state = neu
var _busy := false


func build() -> void:
	setup("App hinzufügen", "", 820)
	super()
	_load()


## Ebene weg: ihr Stand aus Zustand.lage() (kein alter Stand im Fehlerbericht).
func _exit_tree() -> void:
	Zustand.vergessen("apps.hinzufuegen")


func _load() -> void:
	if Library.demo or not Config.is_windows():
		_apps = AppsExtern.demo_store_apps() if Library.demo else []
		_state = "fertig"
		refill()
		return
	var r := await Helper.run_once("store-apps", { "timeout": 40 })
	if not is_inside_tree():
		return
	_apps = AppsExtern.clean_store_list(r.result) if r.ok else []
	_state = "fertig"
	refill()


func fill() -> void:
	var mine := AppsExtern.entries()
	var plan := plan_rows(mine, _apps)
	if not mine.is_empty():
		add_label("Deine Apps")
		for e in mine:
			var prog := str(e.kind) == "prog"
			var r := _row(str(e.name), "desktop" if prog else "tv", TranslationServer.translate("Programm" if prog else "Store-App"))
			r.set_meta("uz_key", "appadd:mine:" + str(e.id))
			r.set_meta("uz_hint_a", "Entfernen")
			var eid := str(e.id)
			var ename := str(e.name)
			r.on_activate = func() -> void: _remove(eid, ename)
			add_row(r)
		add_gap()
	add_label("Hinzufügen")
	if _state == "laden":
		# Die Liste kommt: Zeilen in ihrer Form als ruhige Platzhalter, kein Text.
		var ph := Skeleton.track_rows(3, 72.0)
		ph.shapes = ph.shapes.filter(func(sh: Dictionary) -> bool: return float((sh.r as Rect2).size.x) != 52.0)
		add_row(ph)
	else:
		for a in plan.installed:
			var r := _store_row(a)
			# Der Cursor beginnt beim Hinzufügen, nie auf „Entfernen“ einer eigenen App.
			if a == plan.installed[0]:
				r.set_meta("uz_default", true)
			add_row(r)
	var pick := _row("Programm wählen …", "desktop", "")
	pick.set_meta("uz_key", "appadd:prog")
	pick.set_meta("uz_hint_a", "Auswählen")
	pick.on_activate = _pick_program
	if _state == "laden" or plan.installed.is_empty():
		pick.set_meta("uz_default", true)
	add_row(pick)
	if _state == "laden" or plan.store.is_empty():
		return
	add_gap()
	add_label("Im Store")
	for name in plan.store:
		var n := str(name)
		var off := _row(n, "tv", "")
		off.set_meta("uz_key", "appadd:store:" + n)
		off.set_meta("uz_hint_a", "Im Store suchen")
		off.on_activate = func() -> void:
			if Config.is_windows():
				OS.shell_open(AppsExtern.store_search_url(n))
		add_row(off)


## Was in der Liste steht: installed – installierte Store-Apps, die noch nicht in der Reihe stehen
## (bekannte Dienste zuerst, unter ihrem Namen), store – Namen bekannter Dienste, die fehlen.
static func plan_rows(mine: Array, installed: Array) -> Dictionary:
	var have := {}
	for e in mine:
		have[str(e.id)] = true
	var used := {}
	var inst: Array = []
	var store: Array = []
	for k in AppsExtern.katalog_rows(installed):
		var a: Dictionary = k.app
		if a.is_empty():
			store.append(str(k.name))
			continue
		used[str(a.aumid)] = true
		if not have.has(AppsExtern.make_id("store", str(a.aumid))):
			inst.append({ "aumid": str(a.aumid), "name": str(k.name) })
	for a in installed:
		if used.has(str(a.aumid)) or have.has(AppsExtern.make_id("store", str(a.aumid))):
			continue
		inst.append({ "aumid": str(a.aumid), "name": str(a.name) })
	return { "installed": inst, "store": store }


## Eigene App entfernen: Liste zu, die Reihe baut sich neu; „Rückgängig“ holt sie zurück.
func _remove(app_id: String, name: String) -> void:
	close()
	LeisteOben.remove_app(app_id, name)


func _row(t: String, ic: String, val: String) -> Control:
	var r = SettingRow.new()
	r.setup("action", t)
	r.icon_name = ic
	r.value_text = val
	return r


func _store_row(a: Dictionary) -> Control:
	var app_id := AppsExtern.make_id("store", str(a.aumid))
	var r := _row(str(a.name), "tv", "")
	r.set_meta("uz_key", "appadd:" + app_id)
	r.set_meta("uz_hint_a", "Hinzufügen")
	var aumid := str(a.aumid)
	var name := str(a.name)
	r.on_activate = func() -> void: _add_store(aumid, name)
	return r


func _add_store(aumid: String, name: String) -> void:
	if _busy:
		return
	var r := AppsExtern.add_store(aumid, name)
	if not bool(r.ok):
		Toasts.show_toast("App hinzufügen", str(r.get("why", "")), "warning")
		return
	var id := str(r.id)
	close()
	main.show_app_soon(id)
	if bool(r.get("neu", false)):
		_fetch_logo(main, id, aumid)


## Logo der Store-App holen (Helfer „app-logo“), geprüft ablegen; die Kachel zeigt es dann.
static func _fetch_logo(m: Main, id: String, aumid: String) -> void:
	if not Config.is_windows() or not Helper.available:
		return
	var r := await Helper.run("app-logo", { "aumid": aumid }, 15.0)
	if not r.ok or not (r.result is Dictionary) or not bool(r.result.get("found", false)):
		return
	if AppsExtern.save_logo(id, r.result.get("png", "")) and is_instance_valid(m):
		var secs: Dictionary = m.sections
		var s: Variant = secs.get(id)
		if s is Control and is_instance_valid(s):
			(s as Control).call("build")
		# Das Symbol oben (bzw. die Kachel im Ordner) bekommt das Logo; der Cursor bleibt, wo er war.
		m._rebuild()


## „Programm wählen …“: Dateiauswahl (nur .exe), dann prüfen – Uzai und der Helfer.
func _pick_program() -> void:
	var m := main
	close()
	m.open_file_browser("Programm wählen", false, func(path: String) -> void: _picked(m, path), ["exe"])


static func _picked(m: Main, path: String) -> void:
	var p := AppsExtern.norm_path(path)
	var why := AppsExtern.path_problem(p)
	var name := ""
	if why == "" and Config.is_windows() and Helper.available:
		var r := await Helper.run("prog-check", { "path": p }, 8.0)
		var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
		if not bool(res.get("ok", false)):
			why = AppsExtern.clean_name(res.get("why", ""))
			if why == "":
				why = "Uzai konnte das Programm nicht prüfen."
		name = AppsExtern.clean_name(res.get("name", ""))
	if why != "":
		m.open_dialog("Das geht nicht", why, [["OK", func() -> void: pass]], "warning")
		return
	var res := AppsExtern.add_prog(p, name)
	if not bool(res.ok):
		m.open_dialog("Das geht nicht", str(res.get("why", "")), [["OK", func() -> void: pass]], "warning")
		return
	m.show_app_soon(str(res.id))
