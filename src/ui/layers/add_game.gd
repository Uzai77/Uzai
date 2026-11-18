extends "res://src/ui/layers/sheet.gd"
## Spiel hinzufügen (Punkt 117): ein Programm wählen oder einen Ordner nach Spielen durchsuchen.
## Gefundenes steht als Liste zum An- und Abhaken (Installer und Hilfsprogramme lässt GameFinder
## weg); Y ändert Namen oder Programmdatei. Cover, Hintergrund und Schriftzug holt Uzai danach
## von selbst (Steam-Bilder bei gleichem Namen, sonst SteamGridDB mit eigenem Schlüssel).

const Arbeit := preload("res://src/core/arbeit.gd")
const GameFinder := preload("res://src/library/game_finder.gd")
const EXTS := ["exe", "lnk", "url", "bat", "cmd"]
const Zustand := preload("res://src/core/zustand.gd")
## Spiel hinzufügen: Anfang, Ordner wird durchsucht (Abbrechen geht), Funde oder nichts gefunden.
const ZUSTAENDE := { "start": ["suche"], "suche": ["liste", "leer", "start"], "liste": ["suche"], "leer": ["suche"] }

const Main := preload("res://src/main.gd")
var main: Main
var _state := "start":           ## start | suche | liste | leer
	set(neu):
		Zustand.wechsel("bibliothek.spiel_hinzufuegen", ZUSTAENDE, _state, neu)
		_state = neu
var _dir := ""                   ## durchsuchter Ordner
var _found: Array = []           ## [{ folder, exe, title, others, on }]
var _job := 0


func build() -> void:
	setup("Spiel hinzufügen", "Spiele ohne Launcher: GOG, itch.io oder selbst installiert", 860.0)
	super()


## Ebene weg: ihr Stand aus Zustand.lage() (kein alter Stand im Fehlerbericht).
func _exit_tree() -> void:
	Zustand.vergessen("bibliothek.spiel_hinzufuegen")


func fill() -> void:
	match _state:
		"start": _fill_start()
		"suche": _fill_busy()
		"liste": _fill_list()
		_: _fill_empty()


func _row(kind: String, t: String, d := "", v: Variant = null) -> Control:
	var r = SettingRow.new()
	r.setup(kind, t, d, v)
	r.set_meta("uz_key", "add:" + t)
	return r


# --- Anfang --------------------------------------------------------------------------------

func _fill_start() -> void:
	# Die Erklärung als zweite Zeile: Die Beschreibung einer Zeile zeigt nur die Hilfespalte der
	# Einstellungen, in einer Leiste stünde sie nirgends.
	var scan = _row("action", "Ordner durchsuchen")
	scan.subtitle = "Jeder Unterordner wird ein Spiel."
	scan.icon_name = "search"
	scan.set_meta("uz_default", true)
	scan.on_activate = func() -> void:
		main.open_file_browser("Ordner mit Spielen", true, _scan)
	add_row(scan)
	var one = _row("action", "Programmdatei wählen")
	one.subtitle = ".exe, Verknüpfung oder Batch-Datei."
	one.icon_name = "file"
	one.on_activate = func() -> void:
		main.open_file_browser("Programmdatei wählen", false, _picked, EXTS)
	add_row(one)
	add_gap(10)
	add_label("Uzai startet dabei nichts. Cover kommen von selbst.")


func _picked(exe: String) -> void:
	var problem := GameFinder.exe_problem(exe)
	if problem != "":
		main.open_dialog("Das geht nicht", problem, [["OK", func() -> void: pass]], "warning")
		return
	main.open_keyboard("Name des Spiels", GameFinder.name_for_pick(exe), func(t: String) -> void:
		var g := Library.add_manual(t, exe)
		if g.is_empty():
			return
		Toasts.show_toast("Hinzugefügt", Library.display_title(g), "check", { "sub_raw": true, "sound": "select" })
		close()
	)


# --- Suchen --------------------------------------------------------------------------------

func _scan(dir: String) -> void:
	_dir = dir
	_state = "suche"
	_job += 1
	var job := _job
	refill()
	var known := {}
	for g in Library.by_system("pc"):
		for k in ["path", "target"]:
			if str(g.get(k, "")) != "":
				known[str(g[k]).to_lower()] = true
	var res: Variant = await Arbeit.ergebnis(GameFinder.scan.bind(dir, known), Arbeit.LANG)
	if job != _job or not is_inside_tree():
		return
	_found = []
	for c: Variant in (res if res is Array else []):
		var e: Dictionary = c
		e["on"] = true
		_found.append(e)
	_state = "liste" if not _found.is_empty() else "leer"
	refill()


func _fill_busy() -> void:
	var l := add_label("%s wird durchsucht …" % _short(_dir), "m", "muted")
	# Ruhiges Atmen, solange gesucht wird.
	var tw := l.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(l, "modulate:a", 0.45, U.T_AMBIENT)
	tw.tween_property(l, "modulate:a", 1.0, U.T_AMBIENT)
	var back = _row("action", "Abbrechen")
	back.icon_name = "close"
	back.set_meta("uz_default", true)
	back.on_activate = func() -> void:
		_job += 1
		_state = "start"
		refill()
	add_row(back)


func _fill_empty() -> void:
	add_label("In %s hat Uzai keine neuen Spiele gefunden. Schon Bekanntes und Hilfsprogramme zählen nicht mit." % _short(_dir), "m", "muted")
	add_gap(6)
	_restart_rows(true)


func _fill_list() -> void:
	var on := _found.filter(func(c: Dictionary) -> bool: return bool(c.on)).size()
	# „Hinzufügen“ steht oben und ist gewählt: Meist stimmt die Liste, dann genügt ein Druck. Unter
	# den Funden lag der Knopf bei dreißig Spielen dreißig Zeilen tief.
	var add = _row("action", "Hinzufügen")
	add.icon_name = "plus"
	add.tone = "accent"
	add.value_text = U.plural(on, "Spiel", "Spiele")
	add.set_meta("uz_key", "add:los")
	add.set_meta("uz_default", true)
	add.on_activate = _add_selected
	add_row(add)
	add_gap(4)
	add_label("%s in %s" % [U.plural(_found.size(), "Spiel", "Spiele"), _short(_dir)], "m", "muted")
	add_gap(4)
	for i in _found.size():
		var c: Dictionary = _found[i]
		var r = _row("toggle", str(c.title), "", bool(c.on))
		r.subtitle = _relative(str(c.exe))
		r.icon_name = "games"
		r.set_meta("uz_key", "add:%d" % i)
		r.set_meta("uz_hint_y", "Umbenennen" if (c.others as Array).is_empty() else "Ändern")
		r.set_meta("uz_on_y", func() -> void: _edit(i))
		r.changed.connect(func(v: Variant) -> void:
			_found[i].on = bool(v)
			_update_add())
		add_row(r)
	add_gap()
	_restart_rows(false)


func _restart_rows(first: bool) -> void:
	var again = _row("action", "Anderen Ordner durchsuchen")
	again.icon_name = "folder"
	if first:
		again.set_meta("uz_default", true)
	again.on_activate = func() -> void:
		main.open_file_browser("Ordner mit Spielen", true, _scan)
	add_row(again)


## Wert der Zeile „Hinzufügen“ ohne die Liste neu zu bauen (der Fokus bleibt beim Haken).
func _update_add() -> void:
	for c in content.get_children():
		if c.has_meta("uz_key") and str(c.get_meta("uz_key")) == "add:los":
			c.value_text = U.plural(_found.filter(func(e: Dictionary) -> bool: return bool(e.on)).size(), "Spiel", "Spiele")


func _edit(i: int) -> void:
	var c: Dictionary = _found[i]
	var umbenennen := func() -> void:
		main.open_keyboard("Name des Spiels", str(c.title), func(t: String) -> void:
			if t.strip_edges() != "":
				_found[i].title = t.strip_edges()
				refill())
	# Nur eine Programmdatei: Es gibt nichts zu wählen – gleich der Name (keine Liste mit einer Zeile).
	if (c.others as Array).is_empty():
		umbenennen.call()
		return
	main.open_choice(str(c.title), [["name", "Namen ändern"], ["exe", "Andere Programmdatei"]], "", func(what: Variant) -> void:
		if str(what) == "name":
			umbenennen.call()
		elif str(what) == "exe":
			var exes: Array = [[str(c.exe), _relative(str(c.exe))]]
			for o in c.others:
				exes.append([str(o), _relative(str(o))])
			main.open_choice("Programmdatei", exes, str(c.exe), func(p: Variant) -> void:
				_found[i].exe = str(p)
				refill(), "Welche Datei startet das Spiel?")
	)


func _add_selected() -> void:
	var n := 0
	for c in _found:
		if bool(c.on) and not Library.add_manual(str(c.title), str(c.exe)).is_empty():
			n += 1
	if n == 0:
		return
	Toasts.show_toast("%s hinzugefügt" % U.plural(n, "Spiel", "Spiele"), "Unter Spiele → PC. Cover holt Uzai von selbst.", "check", { "sound": "select" })
	close()


func _relative(path: String) -> String:
	var root := _dir.replace("\\", "/").trim_suffix("/")
	return path.substr(root.length() + 1) if path.begins_with(root + "/") else path


static func _short(path: String) -> String:
	var p := path.replace("\\", "/").trim_suffix("/")
	return "„%s“" % (p.get_file() if p.get_file() != "" else p)
