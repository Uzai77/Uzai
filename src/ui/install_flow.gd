extends RefCounted
## Oberfläche rund ums Installieren (Installs macht die Arbeit): „Installieren“ drücken, vorher
## den Platz prüfen (StorageFlow), bei einem gewählten Steam-Bibliotheksordner kurz nachfragen,
## laufende Downloads anhalten oder abbrechen, die Downloads-Liste öffnen. Lädt schon etwas oder
## ist „Nachts laden“ an: danach, gleich oder heute Nacht (Warteschlange, dl_queue.gd). Dazu die
## Knöpfe für Einträge der Warteschlange und anstehende Updates. Epic: mit Uzais eigenem
## Installer (einmal gefragt, mit Hinweis, Ordner wählen) oder über den Launcher; für von Uzai
## installierte Spiele „Prüfen und aktualisieren“ und „Deinstallieren“. Alles mit dem Controller,
## ohne fremde Fenster.

const Downloads := preload("res://src/ui/layers/downloads.gd")
const P := preload("res://src/core/install_parse.gd")
const StorageFlow := preload("res://src/ui/storage_flow.gd")
const Storage := preload("res://src/core/storage.gd")
const DlQueue := preload("res://src/core/dl_queue.gd")
const EpicInstallS := preload("res://src/core/epic_install.gd")
const Main := preload("res://src/main.gd")

## Der eine Satz beim ersten Mal (R3: inoffiziell, nur auf ausdrücklichen Wunsch, mit Hinweis).
const UZAI_NOTE := "Uzai lädt und installiert das Spiel selbst."


## „Installieren“ auf einem gekauften Spiel. Läuft schon etwas: was man damit tun kann.
static func begin(main: Main, g: Dictionary) -> void:
	var id := str(g.get("id", ""))
	Installs.main = main
	if Installs.queued(id):
		queue_actions(main, id)
		return
	if Installs.busy(id):
		actions(main, id)
		return
	var src := str(g.get("source", ""))
	if not (src in ["steam", "epic"]):
		return
	# Passt das Spiel nicht oder wird es knapp, fragt Uzai vorher deutlich nach.
	StorageFlow.check_install(main, g, func() -> void: _begin_checked(main, g))


## Lädt schon etwas oder ist „Nachts laden“ an: wann? Sonst gleich los.
static func _begin_checked(main: Main, g: Dictionary) -> void:
	var now_dl: Array = Installs.list().filter(func(e: Dictionary) -> bool: return Installs.busy(str(e.id)) and str(e.phase) != "paused")
	var night := Installs.night_on() and Installs.silent(g)
	if now_dl.is_empty() and not night:
		_begin_now(main, g)
		return
	var accept := _accepted(g)
	var title := Library.display_title(g)
	var btns: Array = []
	var text := ""
	if not now_dl.is_empty():
		text = "%s lädt gerade. %s kommt danach." % [str(now_dl[0].title), title]
		btns.append(["Danach laden", func() -> void: _queue(main, g, "jetzt", accept)])
		btns.append(["Gleich mitladen", func() -> void: _begin_now(main, g)])
	else:
		btns.append(["Jetzt laden", func() -> void: _begin_now(main, g)])
	if night:
		var h := Installs.night_hours()
		text += ("\n\n" if text != "" else "") + "Download zwischen %d und %d Uhr im Ruhemodus." % [
				int(h[0]), int(h[1])]
		btns.append(["Heute Nacht laden", func() -> void: _queue(main, g, "nachts", accept)])
	btns.append(["Abbrechen", func() -> void: pass])
	main.open_dialog("%s laden" % title, text, btns, "download")


## Der Platz, den du eben bestätigt hast (StorageFlow.check_install lief schon): ok | knapp | voll.
static func _accepted(g: Dictionary) -> String:
	var level := Storage.space_level(StorageFlow.need_cached(g), StorageFlow.free_at(StorageFlow.target_dir(g)))
	return level if level in ["knapp", "voll"] else "ok"


static func _queue(main: Main, g: Dictionary, when: String, accept: String) -> void:
	Installs.main = main
	Installs.enqueue(g, "install", when, accept)
	Toasts.show_toast("Für heute Nacht vorgemerkt" if when == "nachts" else "In der Warteschlange", Library.display_title(g), "download",
		{ "ms": 3500, "quiet": true, "sub_raw": true, "open": func() -> void: open_downloads(main), "open_text": "Downloads" })


static func _begin_now(main: Main, g: Dictionary) -> void:
	var src := str(g.get("source", ""))
	if src == "epic":
		_epic(main, g)
		return
	var lib := str(Config.get_value("library.steam_install_lib", ""))
	if lib == "" or not DirAccess.dir_exists_absolute(lib.path_join("steamapps")) or Library.demo or not Config.is_windows():
		_go(main, g, {})
		return
	# Eigener Ordner: Steam liest ein neues Spiel dort nur beim Start ein.
	var r := await Helper.run("steam-state", {}, 4.0)
	var running: bool = r.ok and r.result is Dictionary and bool(r.result.get("running", false))
	if not running:
		_go(main, g, { "lib": lib })
		return
	var btns := [
		["In den Steam-Standardordner", func() -> void: _go(main, g, {})],
	]
	if not Launcher.in_game:
		btns.push_front(["Steam kurz neu starten", func() -> void: _go(main, g, { "lib": lib, "restart": true })])
	btns.append(["Abbrechen", func() -> void: pass])
	main.open_dialog("Nach %s installieren?" % lib,
		"Anderer Ordner: Steam startet kurz neu.", btns, "download")


## Epic: Uzais eigener Installer, wenn gewählt und mit Epic-Anmeldung in Uzai – beim ersten Mal
## mit dem Hinweis und der Wahl; sonst wie bisher über den Launcher.
static func _epic(main: Main, g: Dictionary) -> void:
	if Library.demo or not EpicInstallS.can_install(g):
		_go(main, g, {})
	elif not bool(Config.get_value("library.epic_uzai_asked", false)):
		ask_uzai(main, g, Library.launchers.get("epic", false))
	elif bool(Config.get_value("library.epic_uzai", false)):
		begin_uzai(main, g)
	else:
		_go(main, g, {})


## Einmal fragen (ein Satz, ein Schalter). with_launcher: auch „Mit dem Epic Games Launcher“.
static func ask_uzai(main: Main, g: Dictionary, with_launcher := true) -> void:
	var btns: Array = [["Ohne Launcher installieren", func() -> void:
		Config.set_value("library.epic_uzai", true)
		Config.set_value("library.epic_uzai_asked", true)
		begin_uzai(main, g)]]
	if with_launcher:
		btns.append(["Mit dem Epic Games Launcher", func() -> void:
			Config.set_value("library.epic_uzai_asked", true)
			_go(main, g, {})])
	btns.append(["Abbrechen", func() -> void: pass])
	main.open_dialog("Ohne Epic Games Launcher installieren?", UZAI_NOTE, btns, "download")


## Mit Uzais Installer los; beim ersten Mal (oder wenn der Ordner fehlt) erst den Ordner wählen.
static func begin_uzai(main: Main, g: Dictionary) -> void:
	if not bool(Config.get_value("library.epic_uzai", false)):
		ask_uzai(main, g, false)
		return
	var base := str(Config.get_value("library.epic_uzai_dir", ""))
	if base != "" and EpicInstallS.base_problem(base) == "":
		_go(main, g, { "uzai": true, "dir": base })
		return
	pick_uzai_dir(main, func(p: String) -> void: _go(main, g, { "uzai": true, "dir": p }))


## Ordner für Epic-Spiele wählen (Uzais Dateiauswahl, nur Ordner); done(p) mit dem geprüften Ordner.
static func pick_uzai_dir(main: Main, done: Callable = Callable()) -> void:
	var cur := str(Config.get_value("library.epic_uzai_dir", ""))
	main.open_file_browser("Ordner für Epic-Spiele", true, func(p: String) -> void:
		var dir := p.replace("\\", "/").trim_suffix("/")
		var why := EpicInstallS.base_problem(dir)
		if why != "":
			Toasts.show_toast("Anderer Ordner nötig", why, "warning", { "ms": 6000 })
			return
		Config.set_value("library.epic_uzai_dir", dir)
		if done.is_valid():
			done.call(dir)
	, [], cur)


## Von Uzai installiertes Epic-Spiel: neue Fassung holen, sonst alle Dateien prüfen.
static func epic_check(main: Main, g: Dictionary) -> void:
	if not EpicInstallS.can_install(g):
		Toasts.show_toast("Epic-Anmeldung fehlt", "Für Updates bei Epic anmelden.", "warning", { "ms": 6000 })
		return
	if Installs.busy(str(g.get("id", ""))):
		actions(main, str(g.get("id", "")))
		return
	_go(main, g, { "uzai": true, "kind": "check" })


## Von Uzai installiertes Epic-Spiel entfernen (nur seine Dateien laut Epics Liste).
static func epic_uninstall(main: Main, g: Dictionary) -> void:
	main.open_dialog("%s deinstallieren?" % Library.display_title(g),
			"Die Spieldateien in %s werden gelöscht. Spielstände bleiben." % str(g.get("install_dir", "")).replace("/", "\\"), [
		["Deinstallieren", func() -> void:
			var why: String = await Installs.epic.uninstall(g)
			if why != "":
				Toasts.show_toast("Nicht deinstalliert", why, "warning", { "ms": 7000 })
				return
			var id := str(g.get("id", ""))
			Library.set_field(id, "installed", false)
			Library.set_field(id, "epic_uzai", null)
			Library.set_field(id, "path", "")
			Library.set_field(id, "install_dir", "")
			Toasts.show_toast("Deinstalliert", Library.display_title(g), "trash", { "sub_raw": true, "ms": 3500, "quiet": true })],
		["Behalten", func() -> void: pass],
	], "trash", "warn")


static func _go(main: Main, g: Dictionary, opts: Dictionary) -> void:
	Installs.main = main
	Installs.start(g, opts)
	Toasts.show_toast("Wird installiert", "%s · Fortschritt unter Downloads und auf der Spielseite." % Library.display_title(g), "download",
		{ "ms": 3500, "quiet": true, "open": func() -> void: open_downloads(main), "open_text": "Downloads" })


## Was mit einem laufenden oder beendeten Download geht.
static func actions(main: Main, id: String, from_page := false) -> void:
	var e := Installs.entry(id)
	if e.is_empty():
		return
	var btns: Array = []
	var phase := str(e.phase)
	var g := Library.get_game(id)
	if phase == "done":
		if not g.is_empty():
			btns.append(["Spielen", func() -> void: main.launch(Library.get_game(id))])
		btns.append(["Aus der Liste", func() -> void: Installs.dismiss(id)])
	elif phase in ["failed", "cancelled"]:
		if not g.is_empty():
			btns.append(["Nochmal installieren", func() -> void:
				Installs.dismiss(id)
				begin(main, Library.get_game(id))])
		btns.append(["Aus der Liste", func() -> void: Installs.dismiss(id)])
	else:
		if Installs.can_control(id):
			if phase == "paused":
				btns.append(["Fortsetzen", func() -> void: _do(id, "resume")])
			elif phase in ["downloading", "preparing", "queued", "installing"]:
				btns.append(["Pausieren", func() -> void: _do(id, "pause")])
			btns.append(["Abbrechen", func() -> void: _ask_cancel(main, id)])
		elif phase in ["dialog", "ask", "start"]:
			btns.append(["Abbrechen", func() -> void: _do(id, "cancel")])
	if not g.is_empty() and not from_page:
		btns.append(["Zur Spielseite", func() -> void: main.open_game_note(Library.get_game(id))])
	btns.append(["Zurück", func() -> void: pass])
	var note := str(e.text)
	if str(e.store) == "epic" and str(e.get("how", "")) != "uzai" and not (phase in ["done", "failed", "cancelled"]):
		note += "\n\nPausieren nur im Epic Games Launcher."
	elif str(e.store) == "steam" and not Installs.can_control(id) and not (phase in ["done", "failed", "cancelled"]):
		note += "\n\nPausieren mit Steam-Anmeldung."
	main.open_dialog(str(e.title), note, btns, "download")


static func _do(id: String, what: String) -> void:
	var why := ""
	match what:
		"pause": why = await Installs.pause(id)
		"resume": why = await Installs.resume(id)
		"cancel": why = await Installs.cancel(id)
	if why != "":
		Toasts.show_toast({ "pause": "Anhalten ging nicht", "resume": "Fortsetzen ging nicht", "cancel": "Abbrechen ging nicht" }.get(what, "Ging nicht"), why,
				"warning", { "ms": 6000 })


static func _ask_cancel(main: Main, id: String) -> void:
	var e := Installs.entry(id)
	# Der Knopf sagt, was er tut („Abbrechen“ schließt sonst überall nur die Frage), und die Auswahl liegt
	# auf „Weiter laden“: Zweimal A auf „Abbrechen“ löschte vorher einen halb geladenen Download.
	main.open_dialog("Download abbrechen?", "Download abbrechen, %s wird gelöscht." % str(e.get("title", "")), [
		["Download abbrechen", func() -> void: _do(id, "cancel"), "danger"],
		["Weiter laden", func() -> void: pass],
	], "warning", "warn")


## Ein Eintrag der Warteschlange: jetzt starten, nach vorn oder hinten, heute Nacht oder sobald
## frei, herausnehmen.
static func queue_actions(main: Main, id: String) -> void:
	var e := Installs.queue_entry(id)
	if e.is_empty():
		return
	var g := Library.get_game(id)
	var i := DlQueue.index_of(Installs.queue, id)
	var n: int = Installs.queue.size()
	var btns: Array = [["Jetzt starten", func() -> void: _start_queued(id)]]
	if i > 0:
		btns.append(["Nach vorn", func() -> void: Installs.queue_move(id, -1)])
	if i < n - 1:
		btns.append(["Nach hinten", func() -> void: Installs.queue_move(id, 1)])
	if str(e.when) == "nachts":
		btns.append(["Sobald frei laden", func() -> void: Installs.queue_when(id, "jetzt")])
	elif Installs.night_on() and Installs.silent(g):
		btns.append(["Erst heute Nacht", func() -> void: Installs.queue_when(id, "nachts")])
	btns.append(["Aus der Warteschlange", func() -> void: Installs.unqueue(id)])
	btns.append(["Zurück", func() -> void: pass])
	var h := Installs.night_hours()
	var note := "%s · %s" % [queue_place(i), DlQueue.wait_text(e, int(h[0]), int(h[1]), Installs.night_on())]
	if str(e.held) == "anwesend":
		note += "\n\nStartet, wenn Uzai im Vordergrund ist (Dialog von %s)." % ("der Epic Games Launcher"
				if str(g.get("source", "")) == "epic" else "Steam")
	var title := ("Update: %s" % Library.display_title(g)) if str(e.kind) == "update" else Library.display_title(g)
	main.open_dialog(title, note, btns, "download")


static func queue_place(i: int) -> String:
	return "Als Nächstes" if i == 0 else "An %d. Stelle" % (i + 1)


## Wo man die Bandbreite einstellt (nur Steam kann das; Uzai liest sie nur aus).
static func bandwidth_info(main: Main) -> void:
	main.open_dialog("Bandbreite (Steam)",
		"Gerade: %s.\n\nÄndern in Steam: Einstellungen → Downloads." % DlQueue.throttle_text(Installs.steam_throttle()),
		[["OK", func() -> void: pass]], "download")


static func _start_queued(id: String) -> void:
	var why := await Installs.start_queued(id)
	if why != "":
		Toasts.show_toast("Download startet nicht", why, "warning", { "ms": 6000 })


## Ein anstehendes Steam-Update: jetzt, nach den Downloads oder heute Nacht.
static func update_actions(main: Main, u: Dictionary) -> void:
	var id := str(u.id)
	var g := Library.get_game(id)
	if g.is_empty():
		return
	var info: Dictionary = u.u
	var note := DlQueue.update_text(info)
	var btns: Array = []
	if Installs.steam_direct():
		btns.append(["Fortsetzen" if str(info.phase) == "pausiert" else "Jetzt aktualisieren", func() -> void: _update(id)])
		btns.append(["Nach den Downloads", func() -> void: Installs.enqueue(Library.get_game(id), "update", "jetzt")])
		if Installs.night_on():
			btns.append(["Heute Nacht", func() -> void: Installs.enqueue(Library.get_game(id), "update", "nachts")])
	else:
		note += "\n\nStarten mit Steam-Anmeldung. Sonst lädt Steam beim Spielstart."
	if int(info.get("result", 0)) != 0:
		note += "\n\nSteam-Fehler %d." % int(info.result)
	btns.append(["Zur Spielseite", func() -> void: main.open_game_note(Library.get_game(id))])
	btns.append(["Zurück", func() -> void: pass])
	main.open_dialog("Update: %s" % str(u.title), note, btns, "refresh")


static func _update(id: String) -> void:
	var why := await Installs.update_now(Library.get_game(id))
	if why != "":
		Toasts.show_toast("Update startet nicht", why, "warning", { "ms": 6000 })


static func open_downloads(main: Main) -> void:
	Installs.main = main
	Installs.demo_fill()
	Installs.discover()
	var l = Downloads.new()
	l.main = main
	main.open_layer(l)


## Steams Bibliotheksordner für die Einstellung „Speicherort neuer Steam-Spiele“.
static func steam_lib_options() -> Array:
	var out: Array = [["", "Steam-Standardordner", "Wie in Steam eingestellt"]]
	for l in Installs.steam_libraries():
		var free := int(l.get("free", -1))
		out.append(
				[str(l.path), str(l.path).replace("/", "\\"), ("%s frei · Steam startet kurz neu" % P.gb(float(free))) if free >= 0
				else "Steam startet kurz neu"])
	return out
