extends Node
## Spiele über Uzai installieren – Steam und Epic –, ohne dass du ein anderes Fenster bedienst.
##
## Steam, Weg 1 („direkt“): Steams eigener Fern-Download, derselbe, mit dem die Steam-App am Handy
## ein Spiel auf dem PC installiert (Dienst ClientComm.InstallClientApp, über die Web-API mit dem
## Zugang aus Uzais Steam-Anmeldung oder über Steams Chat-Server). Steam lädt dann in seinen
## Standardordner, ganz ohne Dialog. Pausieren/Fortsetzen (SetClientAppUpdateState) und Abbrechen
## (UninstallClientApp) gehen genauso.
## Steam, Weg 2 („Dialog“, ohne Steam-Anmeldung in Uzai oder wenn Weg 1 scheitert): steam://install
## öffnet Steams Dialog, Uzai bleibt dabei ganz oben (UzCover) und drückt „Installieren“ über die
## Bedienhilfe-Schnittstelle von Windows (UI Automation) bzw. Enter. Was Uzai nicht selbst
## entscheiden darf (Lizenz) oder nicht findet, erscheint in Uzai: als Auswahl der Knöpfe oder
## als Bild des Fensters, bedient mit dem Controller (WindowRemote) – nie mit der Maus.
## Steam, eigener Bibliotheksordner (Einstellung): nur wenn Steam geschlossen ist (oder du einen
## kurzen Neustart erlaubst) legt Uzai Steams appmanifest im gewählten Ordner an; Steam lädt dann
## beim Start genau dorthin.
## Epic, Weg 1 („Uzai“, nur nach ausdrücklicher Wahl, mit Epic-Anmeldung in Uzai): Uzais eigener
## Installer wie Heroic/Legendary (epic_install.gd, Kind „EpicInstall“) – ohne Launcher, in den
## gewählten Ordner, mit Pausieren, Abbrechen, Fortsetzen, Update und Prüfen.
## Epic, Weg 2 (Launcher): Der Launcher hat keine Schnittstelle zum Installieren. Uzai öffnet den
## offiziellen Installationslink und bleibt oben. Den Dialog zeichnet der Launcher selbst (Unreal-
## Fenster mit eingebetteter Webseite ohne Bedienhilfe-Baum) – UI Automation findet dort keine
## Knöpfe. Darum zeigt Uzai das Fenster gleich in Uzai und bedient es mit dem Controller
## (WindowRemote; das Fenster behält dabei die Tastatur). Fortschritt aus Manifests\Pending und – soweit
## lesbar – aus dem Protokoll des Launchers; Pausieren und Abbrechen gehen dort nur im Launcher.
##
## Fortschritt: Steams appmanifest_<appid>.acf (Bytes, Status), mit Web-Zugang zusätzlich
## ClientComm.GetClientAppList (Tempo, Restzeit). Fertig: Spiel wird „installiert“, Mitteilung mit
## „Spielen“. Protokoll: logs/installs.log.
##
## Download-Zentrale (Punkt 107, Logik in dl_queue.gd): Uzais eigene Warteschlange („danach“ oder
## „heute Nacht“) gibt Steam bzw. Epic erst das nächste Spiel, wenn das vorige fertig ist.
## Anstehende Steam-Updates liest Uzai aus den appmanifests und stößt sie auf Wunsch an – mit
## demselben Auftrag wie die Steam-App am Handy (SetClientAppUpdateState). Nachts nur, wenn der PC
## ohnehin an ist und Uzai im Ruhemodus wartet; den PC weckt Uzai nie.

signal changed(game_id: String)
signal finished(game_id: String)
## Warteschlange oder anstehende Updates haben sich geändert (Downloads-Seite neu aufbauen).
signal queue_changed

const P := preload("res://src/core/install_parse.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const Fremd := preload("res://src/core/fremd.gd")
const Logdatei := preload("res://src/core/logdatei.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const EpicScanner := preload("res://src/library/epic_scanner.gd")
const DlQueue := preload("res://src/core/dl_queue.gd")
const EpicInstallS := preload("res://src/core/epic_install.gd")
const VDF := preload("res://src/library/vdf.gd")
const API := "https://api.steampowered.com/IClientCommService/"
const ENDED := ["done", "failed", "cancelled"]
const POLL_S := 1.5
const STEAM_PROCS := ["steamwebhelper", "steam"]
const EPIC_PROCS := ["EpicGamesLauncher", "EpicWebHelper"]
const STEAM_WAIT_S := 60.0
const QUEUE_S := 5.0           ## so oft schaut die Warteschlange, ob das Nächste darf
const UPDATES_S := 60.0        ## anstehende Updates höchstens so oft aus den appmanifests lesen

## Spiel-ID → Eintrag { id, store, appid, app, title, phase, how, text, frac, got, total, speed,
## can_pause, manifest, lib, started, … }. phase: start | dialog | ask | preparing | queued |
## downloading | paused | installing | done | failed | cancelled.
var items := {}
const Main := preload("res://src/main.gd")
var main: Main                 ## für Auswahl und Fenster-Bedienung (InstallFlow setzt es)
var epic: Node                 ## Uzais eigener Epic-Installer (epic_install.gd)
var _timer: Timer
var _session := ""             ## Steam-Sitzung dieses PCs (client_instanceid)
var _ticks := 0
var _disk := {}                ## Spiel-ID → { busy, bytes, at }
var _web_ok := true            ## Web-Zugang hat ClientComm angenommen (sonst nur appmanifest)
## Uzais Warteschlange (dl_queue.gd): [{ id, kind, when, added, accept, held }], vorn das Nächste.
var queue: Array = []
var _updates: Array = []       ## anstehende Steam-Updates (pending_updates), zwischengespeichert
var _updates_at := -1000000
var _updates_liest := false    ## der Hilfsfaden liest gerade die appmanifests (updates_auffrischen)
var _rest_was := false         ## Ruhemodus beim letzten Blick (für die Meldung danach)
var _quiet_done: Array = []    ## im Ruhemodus fertig geworden: Titel für die Meldung beim Aufwachen
var _demo_updates: Array = []  ## Demo: anstehende Updates
## Nur für Tests: feste Lage statt Ruhemodus, Uhrzeit und Spiel ({ night, playing, rest, game }).
var ctx_override := {}


func _ready() -> void:
	epic = EpicInstallS.new()
	epic.name = "EpicInstall"
	add_child(epic)
	_timer = Timer.new()
	_timer.wait_time = POLL_S
	_timer.timeout.connect(_poll)
	add_child(_timer)
	Library.changed.connect(_on_library_changed)
	queue = DlQueue.sanitize(Config.get_value("downloads.queue", []))
	var qt := Timer.new()
	qt.wait_time = QUEUE_S
	qt.timeout.connect(_queue_tick)
	add_child(qt)
	qt.start()
	_restore.call_deferred()


# --- Abfragen ---------------------------------------------------------------------------------

## Läuft für dieses Spiel gerade eine Installation (auch: wartet auf einen Dialog)?
func busy(id: String) -> bool:
	return items.has(id) and not (str(items[id].get("phase", "")) in ENDED)


func entry(id: String) -> Dictionary:
	return items.get(id, {})


## Alle Einträge, laufende zuerst, dann neueste.
func list() -> Array:
	var out: Array = items.values().duplicate()
	out.sort_custom(func(a, b) -> bool:
		var ra := 0 if not (str(a.phase) in ENDED) else 1
		var rb := 0 if not (str(b.phase) in ENDED) else 1
		if ra != rb:
			return ra < rb
		return int(a.started) > int(b.started))
	return out


func active_count() -> int:
	return items.values().filter(func(e): return not (str(e.phase) in ENDED)).size()


## Lässt sich dieser Download aus Uzai anhalten/abbrechen? (Steam mit Uzai-Anmeldung, Uzais
## eigener Epic-Installer.)
func can_control(id: String) -> bool:
	var e := entry(id)
	if busy(id) and str(e.get("how", "")) == "uzai":
		return true
	return busy(id) and str(e.get("store", "")) == "steam" and steam_direct()


## Kann Uzai Steam Aufträge geben, ohne dass ein Steam-Fenster aufgeht? (Steam-Anmeldung in Uzai.)
func steam_direct() -> bool:
	return Library.demo or (SteamChat.logged_in() and not SteamChat.demo)


## Steam soll ein installiertes Spiel deinstallieren – derselbe Auftrag wie „Deinstallieren“ in der
## Steam-App am Handy. Steam löscht dann selbst; Uzai fasst keine Spieldatei an. "" = angenommen.
func steam_uninstall(appid: int) -> String:
	if appid <= 0:
		return "Keine Steam-App-ID"
	_log("Deinstallieren angefragt: %d" % appid)
	if Library.demo:
		return ""
	var r := await _steam_remote("UninstallClientApp", appid)
	return "" if r.ok else steam_refused(str(r.get("error", "")))


## Steams Bibliotheksordner mit freiem Platz: [{ path, free (Bytes, -1 unbekannt) }].
func steam_libraries() -> Array:
	var out: Array = []
	for lib in SteamScanner.library_dirs(Library.steam_root()):
		var free := -1
		var da := DirAccess.open(str(lib))
		if da:
			free = int(da.get_space_left())
		out.append({ "path": str(lib), "free": free })
	return out


## Standard-Speicherort des Epic Games Launchers ("" = unbekannt).
func epic_default_dir() -> String:
	var la := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	if la == "":
		return ""
	for sub in ["Windows", "WindowsEditor"]:
		var p := la.path_join("EpicGamesLauncher/Saved/Config/%s/GameUserSettings.ini" % sub)
		if FileAccess.file_exists(p):
			var d := P.epic_default_dir(FileAccess.get_file_as_string(p))
			if d != "":
				return d
	return ""


# --- Starten ----------------------------------------------------------------------------------

## Installation anstoßen. opts: lib (Steam-Bibliotheksordner, "" = Standard), restart (Steam darf
## dafür kurz neu starten), auto (Dialoge selbst bestätigen, Standard: Einstellung), unattended
## (aus der Warteschlange, während du nicht da bist: nie ein Dialog – lieber „nicht geladen“),
## uzai (Epic mit Uzais eigenem Installer: dir = gewählter Ordner, kind „install“ oder „check“).
func start(g: Dictionary, opts := {}) -> void:
	var id := str(g.get("id", ""))
	var src := str(g.get("source", ""))
	if id == "" or busy(id) or not (src in ["steam", "epic"]):
		return
	items[id] = _new_entry(g)
	_log("Start: %s (%s) %s" % [str(items[id].title), src, JSON.stringify(opts)])
	_changed(id)
	_timer.start()
	if Library.demo:
		_demo_run(id)
		return
	# Welche Steam-Fenster schon offen waren (Freundesliste …): die bleiben nachher, wie sie sind.
	if src == "steam" and Config.is_windows() and Helper.available:
		items[id]["keep"] = await _hwnds(STEAM_PROCS)
	if src == "steam":
		await _steam_start(id, g, opts)
	elif bool(opts.get("uzai", false)):
		_uzai_start(id, g, opts)
	else:
		await _epic_start(id, g, opts)
	_save()


func _new_entry(g: Dictionary) -> Dictionary:
	return {
		"id": str(g.get("id", "")), "store": str(g.get("source", "")), "appid": int(g.get("appid", 0)),
		"app": str((g.get("epic", {}) as Dictionary).get("app", "")) if g.get("epic") is Dictionary else "",
		"title": Library.display_title(g), "phase": "start", "how": "", "text": "Wird vorbereitet …",
		"frac": -1.0, "got": 0.0, "total": 0.0, "speed": 0.0, "approx": false, "can_pause": false,
		"manifest": "", "lib": "", "seen": false, "started": int(Time.get_unix_time_from_system()),
		"samples": [], "error": "", "kind": "install",
	}


## Ein Spiel, das Steam schon lädt (z. B. vor dem Neustart von Uzai oder in Steam angestoßen):
## in die Liste aufnehmen, damit Fortschritt und Fertig-Meldung kommen.
func track(g: Dictionary) -> void:
	var id := str(g.get("id", ""))
	if id == "" or busy(id) or str(g.get("source", "")) != "steam" or Library.is_installed(g):
		return
	var path := _find_manifest(int(g.get("appid", 0)))
	if path == "":
		return
	var e := _new_entry(g)
	e["phase"] = "preparing"
	e["how"] = "steam"
	e["manifest"] = path
	e["seen"] = true
	e["can_pause"] = true
	items[id] = e
	_poll_steam(id)
	_changed(id)
	_timer.start()


## Ein Update, das Steam gerade selbst lädt: in die Liste, damit Fortschritt und Meldung kommen.
func track_update(g: Dictionary) -> void:
	var id := str(g.get("id", ""))
	var path := _find_manifest(int(g.get("appid", 0)))
	if id == "" or busy(id) or path == "":
		return
	var e := _new_entry(g)
	e.merge({ "kind": "update", "phase": "preparing", "how": "steam", "manifest": path, "seen": true, "can_pause": true,
		"text": "Steam aktualisiert …" }, true)
	items[id] = e
	_poll_steam(id)
	_changed(id)
	_timer.start()


## Alle nicht installierten Steam-Spiele der Bibliothek, für die Steam schon ein appmanifest hat;
## dazu Updates, die Steam gerade lädt.
func discover() -> void:
	if Library.demo:
		return
	for g in Library.games:
		if str(g.get("source", "")) == "steam" and not Library.is_installed(g) and not busy(str(g.get("id", ""))):
			track(g)
	for u in pending_updates(true):
		if str(u.u.phase) == "laeuft":
			track_update(Library.get_game(str(u.id)))


# --- Steam ------------------------------------------------------------------------------------

func _steam_start(id: String, g: Dictionary, opts: Dictionary) -> void:
	var appid := int(g.get("appid", 0))
	if appid <= 0:
		_end(id, "failed", "Keine Steam-App-ID")
		return
	var auto := bool(opts.get("auto", Config.get_value("library.install_auto", true)))
	var away := bool(opts.get("unattended", false))
	if away and (not Config.is_windows() or not Helper.available):
		_end(id, "failed", "Steam hat den Auftrag nicht angenommen – ohne dich öffnet Uzai keinen Dialog.")
		return
	if not Config.is_windows() or not Helper.available:
		OS.shell_open("steam://install/%d" % appid)
		_upd(id, { "phase": "preparing", "how": "dialog", "text": "Steam zeigt seinen Installationsdialog (ohne Windows-Helfer bestätigt Uzai ihn nicht)." })
		return
	var lib := str(opts.get("lib", ""))
	if lib != "" and await _steam_to_folder(id, g, lib, bool(opts.get("restart", false))):
		return
	if not busy(id):
		return
	_upd(id, { "text": "Steam wird vorbereitet …" })
	await _steam_ensure()
	if not busy(id):
		return
	var r := await _steam_remote("InstallClientApp", appid)
	if r.ok:
		_log("Steam: Fern-Download angenommen (%s)" % str(r.get("via", "")))
		_upd(id, { "phase": "preparing", "how": "direkt", "can_pause": true, "text": "Steam startet den Download …" })
		# Steam legt das appmanifest gleich an. Kommt keins, fragt Steam wohl doch etwas (Lizenz,
		# zu wenig Platz) – dann wie beim Dialog weiter.
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 25000:
			await get_tree().create_timer(1.0).timeout
			if not busy(id):
				return
			if _find_manifest(appid) != "":
				_tidy(STEAM_PROCS, items[id].get("keep", []))
				_poll_steam(id)
				return
		_log("Steam: nach 25 s kein appmanifest – sehe nach einem Dialog")
		if away:
			_end(id, "failed", "Steam fragt wohl etwas (Lizenz, Platz) – das zeigt Uzai erst, wenn du da bist.")
		elif auto:
			await _steam_dialog(id, g, false)
		return
	if away:
		_end(id, "failed", "Steam hat den Auftrag nicht angenommen – ohne dich öffnet Uzai keinen Dialog.")
		return
	_log("Steam: Fern-Download geht nicht (%s) – Steams Dialog" % str(r.get("error", "")))
	if not auto:
		OS.shell_open("steam://install/%d" % appid)
		_upd(id, { "phase": "preparing", "how": "dialog", "text": "Steam fragt nach dem Speicherort – dort bestätigen." })
		return
	await _steam_dialog(id, g, true)


## Steams Dialog: Uzai bleibt oben und bestätigt ihn.
func _steam_dialog(id: String, g: Dictionary, open_url: bool) -> void:
	_upd(id, { "phase": "dialog", "how": "dialog", "text": "Steam fragt nach – Uzai bestätigt den Dialog …" })
	_hold(true)
	var before := await _hwnds(STEAM_PROCS)
	if open_url:
		OS.shell_open("steam://install/%d" % int(g.get("appid", 0)))
	var res := await _confirm(id, "steam", before, 45000)
	_hold(false)
	_after_confirm(id, res)


## Steam soll laufen und angemeldet sein (still gestartet, ohne Fenster). false: nicht da.
func _steam_ensure() -> bool:
	var r := await Helper.run("steam-state", {}, 4.0)
	if r.ok and r.result is Dictionary and bool(r.result.get("running", false)) and int(r.result.get("user", 0)) != 0:
		return true
	if not (r.ok and r.result is Dictionary and bool(r.result.get("running", false))):
		var s := await Helper.run("steam-silent", {}, 6.0)
		if not s.ok or not (s.result is Dictionary) or not bool(s.result.get("started", false)):
			return false
		_log("Steam still gestartet")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < STEAM_WAIT_S * 1000.0:
		await get_tree().create_timer(1.0).timeout
		r = await Helper.run("steam-state", {}, 4.0)
		if r.ok and r.result is Dictionary and int(r.result.get("user", 0)) != 0:
			await get_tree().create_timer(3.0).timeout
			return true
	return false


## In einen gewählten Bibliotheksordner: Steam liest neue appmanifeste nur beim Start. Darum nur,
## wenn Steam zu ist – oder du einen kurzen Neustart erlaubt hast (steam://exit, Steams eigenes
## Beenden). Uzai legt nur eine neue Datei an (nie eine vorhandene ändern); lehnt Steam sie ab,
## entfernt Steam sie selbst. false: anderer Weg (Standardordner).
func _steam_to_folder(id: String, g: Dictionary, lib: String, restart: bool) -> bool:
	var appid := int(g.get("appid", 0))
	var apps := lib.path_join("steamapps")
	if _find_manifest(appid) != "" or not DirAccess.dir_exists_absolute(apps):
		return false
	var dirname := P.install_dir_name(str(g.get("title", "")))
	if dirname == "":
		dirname = "app_%d" % appid
	if DirAccess.dir_exists_absolute(apps.path_join("common").path_join(dirname)):
		_log("Steam: Ordner %s gibt es schon – lieber Steams Weg" % dirname)
		return false
	var r := await Helper.run("steam-state", {}, 4.0)
	var running: bool = r.ok and r.result is Dictionary and bool(r.result.get("running", false))
	if running:
		if not restart or Launcher.in_game:
			return false
		_upd(id, { "text": "Steam wird kurz beendet …" })
		_log("Steam: Neustart für den Ordner %s" % lib)
		OS.shell_open("steam://exit")
		var t0 := Time.get_ticks_msec()
		while running and Time.get_ticks_msec() - t0 < 45000:
			await get_tree().create_timer(1.0).timeout
			r = await Helper.run("steam-state", {}, 4.0)
			running = r.ok and r.result is Dictionary and bool(r.result.get("running", false))
		if running:
			_log("Steam: hat sich nicht beendet – Standardordner")
			return false
		await get_tree().create_timer(2.0).timeout
	var path := apps.path_join("appmanifest_%d.acf" % appid)
	if FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_log("Steam: appmanifest nicht schreibbar (%s)" % path)
		return false
	f.store_string(P.steam_manifest_text(appid, str(g.get("title", "")), dirname, SteamChat.my_id() if SteamChat.logged_in() else ""))
	f.close()
	_log("Steam: appmanifest in %s angelegt" % apps)
	_upd(id, { "phase": "preparing", "how": "ordner", "lib": lib, "manifest": path, "can_pause": true, "text": "Steam startet und lädt nach %s …" % lib })
	await _steam_ensure()
	# Steam reiht so ein Spiel als „Aktualisierung nötig“ ein; mit Anmeldung schiebt Uzai es an.
	if busy(id):
		await _steam_remote("InstallClientApp", appid)
	return true


## Warum Steam einen Auftrag nicht angenommen hat, als Satz mit dem, was zu tun ist. Die Einzelheiten
## (Web-API, EResult) stehen schon im Protokoll.
static func steam_refused(err: String) -> String:
	if err == NO_STEAM_LOGIN:
		return "Dafür braucht Uzai die Steam-Anmeldung: Einstellungen → Konten → Steam."
	if err.begins_with(NO_STEAM_HERE):
		return "Steam läuft auf diesem PC gerade nicht. Steam starten und noch einmal versuchen."
	return "Steam hat nicht reagiert. Gleich noch einmal versuchen."


const NO_STEAM_LOGIN := "keine Steam-Anmeldung in Uzai"
const NO_STEAM_HERE := "Steam auf diesem PC nicht gefunden"


## ClientComm-Aufruf für dieses Spiel (InstallClientApp, UninstallClientApp, SetClientAppUpdateState).
func _steam_remote(method: String, appid: int, action := -1) -> Dictionary:
	if not SteamChat.logged_in() or SteamChat.demo:
		return { "ok": false, "error": NO_STEAM_LOGIN }
	var sess := await _steam_session()
	if sess == "":
		return { "ok": false, "error": NO_STEAM_HERE + " (GetAllClientLogonInfo)" }
	var params := { "appid": appid, "client_instanceid": sess }
	var pb := PackedByteArray()
	if method == "SetClientAppUpdateState":
		params["action"] = action
		pb.append_array(SteamCM.Pb.f_varint(1, appid))
		pb.append_array(SteamCM.Pb.f_varint(2, action))
		pb.append_array(SteamCM.Pb.f_varint(3, P.u64_parse(sess)))
	else:
		pb.append_array(SteamCM.Pb.f_varint(1, appid))
		pb.append_array(SteamCM.Pb.f_varint(2, P.u64_parse(sess)))
	var r := await _clientcomm(method, params, pb)
	if not r.ok:
		# Vielleicht eine alte Sitzung (Steam neu gestartet): einmal frisch fragen.
		_session = ""
	return r


## Die Steam-Sitzung dieses PCs (gleicher Rechnername). Steam braucht nach dem Start ein paar
## Sekunden, bis sie gemeldet ist.
func _steam_session() -> String:
	if _session != "":
		return _session
	var st := await Helper.run("steam-state", {}, 4.0)
	var local: bool = st.ok and st.result is Dictionary and bool(st.result.get("running", false))
	for attempt in 3:
		var r := await _clientcomm("GetAllClientLogonInfo", {}, PackedByteArray())
		if r.ok:
			var list: Array = P.sessions_from_json(r.get("data")) if str(r.get("via", "")) == "web" else P.sessions_from_pb(SteamCM.Pb, r.get("body", PackedByteArray()))
			_session = P.pick_session(list, OS.get_environment("COMPUTERNAME"), local)
			_log("Steam-Sitzungen: %d, diese: %s" % [list.size(), _session if _session != "" else "keine"])
			if _session != "":
				return _session
		await get_tree().create_timer(3.0).timeout
	return ""


## Steams ClientComm-Dienst: erst Web-API mit dem Zugang aus der Anmeldung (keine zusätzliche
## Sitzung bei Steam), sonst über Steams Chat-Server (kurze Sitzung – nur, weil du es anstößt).
## { ok, via (web|cm), data (JSON) bzw. body (protobuf), error }
func _clientcomm(method: String, params: Dictionary, pb: PackedByteArray) -> Dictionary:
	var err := ""
	var tok := ""
	if SteamChat.logged_in() and not SteamChat.demo:
		tok = await SteamChat._token()
	if tok != "":
		var q := params.duplicate()
		q["access_token"] = tok
		var r: Dictionary
		if method.begins_with("Get"):
			r = await Net.get_json(API + method + "/v1/?" + Net.query(q))
		else:
			r = await Net.post_form(API + method + "/v1/", q)
		var er := Net.header(r, "x-eresult")
		if r.ok and (er == "" or er == "1"):
			_web_ok = true
			return { "ok": true, "via": "web", "data": r.data }
		err = "Web-API HTTP %d, EResult %s" % [int(r.code), er if er != "" else "?"]
		if int(r.code) in [401, 403]:
			SteamChat.drop_access()
			_web_ok = false
	if SteamChat.can_send() and not SteamChat.demo and method != "GetClientAppList":
		var cr: Dictionary = await SteamCM.call_authed(str(Config.get_value("accounts.steam_chat_refresh", "")), "ClientComm.%s#1" % method, pb)
		if cr.ok:
			return { "ok": true, "via": "cm", "body": cr.body }
		err += ("; " if err != "" else "") + "Chat-Server: %s (EResult %d)" % [str(cr.get("error", "")), int(cr.get("eresult", 0))]
	_log("ClientComm.%s: %s" % [method, err if err != "" else "keine Anmeldung"])
	return { "ok": false, "error": err if err != "" else "keine Steam-Anmeldung in Uzai" }


var _libs: Array = []
var _libs_at := -100000


## Steams Bibliotheksordner (10 s zwischengespeichert: libraryfolders.vdf nicht bei jedem Blick lesen).
func _steam_libs() -> Array:
	if Time.get_ticks_msec() - _libs_at > 10000:
		_libs = SteamScanner.library_dirs(Library.steam_root())
		_libs_at = Time.get_ticks_msec()
	return _libs


func _find_manifest(appid: int) -> String:
	if appid <= 0:
		return ""
	for lib in _steam_libs():
		var p := str(lib).path_join("steamapps/appmanifest_%d.acf" % appid)
		if FileAccess.file_exists(p):
			return p
	return ""


func _poll_steam(id: String) -> void:
	var e: Dictionary = items[id]
	var path := str(e.get("manifest", ""))
	if path == "" or not FileAccess.file_exists(path):
		path = _find_manifest(int(e.appid))
	if path == "":
		if bool(e.get("seen", false)):
			_end(id, "cancelled", "In Steam abgebrochen oder entfernt")
		return
	e["manifest"] = path
	e["seen"] = true
	e["lib"] = path.get_base_dir().get_base_dir()
	var st: Variant = VDF.get_ci(VDF.parse_file(path), "AppState", {})
	if not (st is Dictionary):
		return
	var s := P.steam_state(st)
	if bool(s.done):
		_complete_steam(id, path, st)
		return
	if str(e.phase) in ["dialog", "ask"]:
		# Download läuft: die Bedienung in Uzai ist erledigt.
		e["phase"] = "preparing"
	var got := float(s.got)
	var total := float(s.total)
	var speed := _speed(e, got)
	var eta := -1.0
	var live: Dictionary = e.get("live", {})
	if not live.is_empty() and Time.get_ticks_msec() - int(live.get("at", 0)) < 15000:
		# Steam selbst weiß es genauer (GetClientAppList): Bytes, Tempo, Restzeit.
		if float(live.get("total", 0.0)) > 0.0:
			got = float(live.got)
			total = float(live.total)
		if float(live.get("rate", 0.0)) > 0.0:
			speed = float(live.rate)
		eta = float(live.get("eta", -1.0))
	var phase := str(s.phase)
	if phase in ["paused", "queued"]:
		speed = 0.0
	var word := str({ "paused": "Pausiert", "downloading": "Wird geladen", "installing": "Wird installiert" }.get(phase, ""))
	var frac := float(s.frac) if total <= 0.0 or phase == "installing" else clampf(got / total, 0.0, 1.0)
	var text := str(s.text)
	if phase == "installing":
		text = P.line(word, frac, 0.0, 0.0, 0.0)
	elif word != "":
		text = P.line(word, frac, got, total, speed)
	if eta > 0.0 and phase == "downloading" and not text.contains("noch "):
		text += " · " + P.eta_text(eta, 1.0)
	_upd(id, { "phase": phase, "frac": frac, "got": got, "total": total, "speed": speed, "text": text }, false)
	# Alle paar Runden Steam selbst fragen (nur mit Web-Zugang, keine zusätzliche Sitzung).
	if _web_ok and _ticks % 4 == 0 and phase in ["downloading", "preparing", "installing"]:
		_fetch_live(id)


## Live-Stand von Steam (GetClientAppList, nur Web-API).
func _fetch_live(id: String) -> void:
	var e: Dictionary = items.get(id, {})
	if e.is_empty() or bool(e.get("live_busy", false)) or not SteamChat.logged_in() or SteamChat.demo:
		return
	e["live_busy"] = true
	var sess := await _steam_session()
	if sess != "" and items.has(id):
		var r := await _clientcomm("GetClientAppList", { "client_instanceid": sess, "fields": "games", "filters": "changing", "filter_appids[0]": int(e.appid) },
				PackedByteArray())
		if r.ok and items.has(id):
			var a := P.client_app(r.get("data"), int(e.appid))
			if not a.is_empty():
				a["at"] = Time.get_ticks_msec()
				items[id]["live"] = a
	if items.has(id):
		items[id]["live_busy"] = false


func _complete_steam(id: String, path: String, st: Dictionary) -> void:
	var dir := path.get_base_dir().path_join("common").path_join(str(VDF.get_ci(st, "installdir", "")))
	Library.set_field(id, "install_dir", dir)
	Library.set_field(id, "installed", true)
	_end(id, "done", "Aktualisiert" if str(items[id].get("kind", "")) == "update" else "Fertig installiert")


# --- Epic mit Uzais eigenem Installer -----------------------------------------------------------

func _uzai_start(id: String, g: Dictionary, opts: Dictionary) -> void:
	var kind := str(opts.get("kind", "install"))
	var e: Dictionary = items[id]
	e.merge({ "how": "uzai", "can_pause": true, "kind": "update" if kind == "check" else "install", "epic": Fremd.verz(g.get("epic")).duplicate() }, true)
	var why: String = epic.start(g, str(opts.get("dir", "")), kind)
	if why != "":
		_end(id, "failed", why)
		return
	_upd(id, { "phase": "preparing", "text": "Fragt Epic nach dem Spiel …" if kind != "check" else "Sucht nach einer neuen Fassung …" })


func _poll_uzai(id: String) -> void:
	var e: Dictionary = items[id]
	var st: Dictionary = epic.status(str(e.app))
	if st.is_empty():
		return
	var upd := str(e.get("kind", "")) == "update"
	match str(st.phase):
		"prep":
			_upd(id, { "phase": "preparing", "frac": -1.0, "text": str(st.text) }, false)
		"check":
			_upd(id, { "phase": "installing", "frac": float(st.frac), "got": float(st.got), "total": float(st.total), "speed": 0.0,
				"text": P.line("Wird geprüft", float(st.frac), float(st.got), float(st.total), 0.0) }, false)
		"run":
			var sp := _speed(e, float(st.got))
			_upd(id, { "phase": "downloading", "frac": float(st.frac), "got": float(st.got), "total": float(st.total), "speed": sp, "approx": false,
				"text": P.line("Wird aktualisiert" if upd else "Wird geladen", float(st.frac), float(st.got), float(st.total), sp) }, false)
		"finish":
			_upd(id, { "phase": "installing", "frac": 1.0, "speed": 0.0, "text": "Wird abgeschlossen …" }, false)
		"paused":
			_upd(id, { "phase": "paused", "speed": 0.0, "samples": [], "text": "Pausiert" })
		"done":
			_end(id, "done", str(st.text))
		"failed":
			_end(id, "failed", str(st.text))
		"cancelled":
			_end(id, "cancelled", "Abgebrochen")


## Pausieren, Fortsetzen, Abbrechen bei Uzais eigenem Installer. "" = ok.
func _uzai_control(id: String, what: String) -> String:
	var e := entry(id)
	var app := str(e.get("app", ""))
	match what:
		"pause":
			epic.pause(app)
			_upd(id, { "text": "Hält an …", "speed": 0.0 })
		"resume":
			var g := Library.get_game(id)
			if g.is_empty():
				g = { "id": id, "title": str(e.title), "source": "epic", "epic": e.get("epic", {}) }
			var why: String = epic.resume(g)
			if why != "":
				return why
			_upd(id, { "phase": "preparing", "text": "Wird fortgesetzt …", "samples": [] })
			_timer.start()
		"cancel":
			await epic.cancel(app)
			_end(id, "cancelled", "Abgebrochen – Uzai hat die angefangenen Dateien gelöscht")
	return ""


# --- Epic -------------------------------------------------------------------------------------

func _epic_start(id: String, g: Dictionary, opts: Dictionary) -> void:
	if EpicScanner.install_uri(g) == "":
		_end(id, "failed", "Für dieses Spiel fehlen die Angaben des Epic Games Launchers.")
		return
	var auto := bool(opts.get("auto", Config.get_value("library.install_auto", true)))
	if not Config.is_windows() or not Helper.available or not auto:
		Library.start_epic_install(g)
		_upd(id, { "phase": "preparing", "how": "dialog", "text": "Der Epic Games Launcher zeigt seinen Installationsdialog – dort bestätigen." })
		return
	_upd(id, { "phase": "dialog", "how": "dialog", "text": "Epic Games Launcher öffnet …" })
	_hold(true)
	var before := await _hwnds(EPIC_PROCS)
	Library.start_epic_install(g)
	# Startet der Launcher erst, dauert es (Anmeldung, Aktualisierung des Launchers).
	var res := await _confirm(id, "epic", before, 90000)
	_hold(false)
	_after_confirm(id, res)


func _poll_epic(id: String) -> void:
	var e: Dictionary = items[id]
	var g := Library.get_game(id)
	if not g.is_empty() and Library.is_installed(g):
		_end(id, "done", "Fertig installiert")
		return
	var pend := P.epic_pending(EpicScanner.manifest_dir(), str(e.app))
	if pend.is_empty():
		if bool(e.get("seen", false)):
			# Nicht mehr „Pending“: fertig (das Manifest liegt jetzt eine Ebene höher) oder
			# abgebrochen. Library liest Epic neu und meldet ein fertiges Spiel.
			if _ticks % 4 == 0:
				Library.refresh_epic()
			_upd(id, { "phase": "installing", "frac": -1.0, "text": "Epic schließt die Installation ab …" }, false)
			if int(Time.get_unix_time_from_system()) - int(e.get("gone_at", 0)) > 120 and int(e.get("gone_at", 0)) > 0:
				_end(id, "cancelled", "Im Epic Games Launcher abgebrochen")
			elif int(e.get("gone_at", 0)) == 0:
				e["gone_at"] = int(Time.get_unix_time_from_system())
		elif not (str(e.phase) in ["dialog", "ask"]):
			_upd(id, { "text": "Wartet auf den Epic Games Launcher …" }, false)
		return
	e["seen"] = true
	e["gone_at"] = 0
	if str(e.phase) in ["dialog", "ask", "start"]:
		e["phase"] = "preparing"
	var lp := _epic_log(str(e.app))
	var total := float(pend.get("size", 0.0))
	if not lp.is_empty() and float(lp.frac) >= 0.0:
		var t := float(lp.total) if float(lp.total) > 0.0 else total
		var got := float(lp.got) if float(lp.total) > 0.0 else (t * float(lp.frac) if t > 0.0 else 0.0)
		var sp := float(lp.speed) if float(lp.speed) > 0.0 else _speed(e, got)
		_upd(id, { "phase": "downloading", "frac": float(lp.frac), "got": got, "total": t, "speed": sp, "approx": false,
			"text": P.line("Wird geladen", float(lp.frac), got, t, sp) }, false)
		return
	var loc := str(pend.get("location", ""))
	if total > 0.0 and loc != "" and DirAccess.dir_exists_absolute(loc):
		_measure(id, loc)
		var d: Dictionary = _disk.get(id, {})
		if d.has("bytes"):
			var got2 := minf(float(d.bytes), total)
			var frac := clampf(got2 / total, 0.0, 0.99)
			var sp2 := _speed(e, got2)
			_upd(id, { "phase": "downloading", "frac": frac, "got": got2, "total": total, "speed": sp2, "approx": true,
				"text": P.line("Wird geladen", frac, got2, total, sp2, true) }, false)
			return
	_upd(id, { "phase": "downloading", "frac": -1.0, "text": "Epic lädt das Spiel herunter …" }, false)


## Fortschritt aus dem Protokoll des Launchers – nur, wenn es gerade geschrieben wird.
func _epic_log(app: String) -> Dictionary:
	var la := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	if la == "":
		return {}
	var p := la.path_join("EpicGamesLauncher/Saved/Logs/EpicGamesLauncher.log")
	if not FileAccess.file_exists(p) or int(Time.get_unix_time_from_system()) - FileAccess.get_modified_time(p) > 90:
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var n := f.get_length()
	f.seek(maxi(0, n - 65536))
	var tail := f.get_buffer(mini(n, 65536)).get_string_from_utf8()
	f.close()
	return P.epic_log_progress(tail, app)


## Größe des Spielordners im Hintergrund messen (höchstens alle 6 s).
func _measure(id: String, dir: String) -> void:
	var d: Dictionary = _disk.get(id, {})
	if bool(d.get("busy", false)) or Time.get_ticks_msec() - int(d.get("at", -100000)) < 6000:
		return
	d["busy"] = true
	_disk[id] = d
	var bytes: Variant = await Arbeit.ergebnis(P.dir_size.bind(dir), Arbeit.LANG)
	d["busy"] = false
	d["at"] = Time.get_ticks_msec()
	if bytes is int and bytes >= 0:
		d["bytes"] = bytes


# --- Dialoge bestätigen -----------------------------------------------------------------------

## Den Installationsdialog von Steam bzw. Epic bestätigen, während Uzai oben bleibt.
## "ok" (Download läuft), "cancel" (du hast abgebrochen), "timeout".
func _confirm(id: String, store: String, before: Array, budget_ms: int) -> String:
	var until := Time.get_ticks_msec() + budget_ms
	var presses := 0
	var tried_enter := false
	var no_buttons_since := 0
	var title := str(items[id].title)
	while Time.get_ticks_msec() < until:
		if not busy(id):
			return "cancel"
		if _started(id):
			return "ok"
		var wins := await _windows(STEAM_PROCS if store == "steam" else EPIC_PROCS)
		var w := P.steam_dialog_pick(wins, before, title) if store == "steam" else P.epic_window_pick(wins)
		if w.is_empty():
			await get_tree().create_timer(0.8).timeout
			continue
		var hwnd := Fremd.zahl(w.get("hwnd"))
		if store == "epic":
			# Epics Dialog ist eine eingebettete Webseite im Unreal-Fenster des Launchers, ohne
			# Bedienhilfe-Baum: UI Automation findet dort nie Knöpfe (früher wartete Uzai darauf, und
			# danach gingen die Tasten verloren). Kurz warten, bis der Dialog steht, dann in Uzai zeigen.
			await get_tree().create_timer(2.5).timeout
			if _started(id):
				return "ok"
			return await _remote(id, store, w)
		var r := await Helper.run("discord-buttons", { "hwnd": hwnd, "budget_ms": 4000, "app": "steam" }, 12.0)
		var res: Dictionary = r.result if r.ok and r.get("result") is Dictionary else {}
		var buttons: Array = res.get("buttons", []) if res.get("buttons") is Array else []
		if _started(id):
			return "ok"
		var pick := P.dialog_pick(buttons)
		_log("%s: Fenster „%s“, %d Knöpfe%s" % [store, str(w.get("title", "")), buttons.size(), (", drücke „%s“" % str(pick.name)) if not pick.is_empty() else ""])
		if not pick.is_empty() and presses < 6:
			var inv := await Helper.run("discord-invoke", { "i": int(pick.i) }, 6.0)
			var how := str((inv.result as Dictionary).get("result", "")) if inv.get("result") is Dictionary else str(inv.get("error", ""))
			_log("%s: „%s“ gedrückt: %s" % [store, str(pick.name), how])
			presses += 1
			await get_tree().create_timer(1.5).timeout
			continue
		# Erkennbar ein Installationsdialog (Installieren, Weiter, Lizenz …), aber Uzai darf oder
		# kann nicht selbst wählen: du wählst in Uzai. Sonst (Launcher lädt noch, nur Navigation)
		# weiter warten.
		var choices := P.dialog_choices(buttons)
		if choices.any(func(c): return str(c.kind) in ["install", "next", "agree", "finish"]):
			# Bekannte Knöpfe zeigen; unbekannte nur in kleinen Dialogen (im Launcher-Fenster stünde
			# sonst die ganze Navigation in der Liste).
			if store == "epic" or choices.size() > 6:
				choices = choices.filter(func(c): return str(c.kind) != "")
			var picked := await _ask_buttons(id, store, w, choices)
			if picked == "cancel":
				return "cancel"
			if picked == "remote":
				return await _remote(id, store, w)
			await get_tree().create_timer(1.5).timeout
			continue
		# Keine Knöpfe über UI Automation: bei Steams eigenem Installationsfenster einmal Enter
		# (der vorgewählte Knopf ist „Installieren“), sonst das Fenster in Uzai bedienen.
		if store == "steam" and not tried_enter and str(w.get("title", "")).to_lower().contains("install"):
			tried_enter = true
			var k := await Helper.run("window-keys", { "hwnd": hwnd, "keys": "ENTER", "back_pid": OS.get_process_id() }, 5.0)
			_log("steam: Enter an „%s“: %s" % [str(w.get("title", "")), JSON.stringify(k.get("result", k.get("error", "")))])
			await get_tree().create_timer(2.0).timeout
			continue
		if no_buttons_since == 0:
			no_buttons_since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - no_buttons_since > (4000 if store == "steam" else 12000):
			return await _remote(id, store, w)
		await get_tree().create_timer(1.0).timeout
	return "timeout"


## Läuft der Download schon (Steam: appmanifest da, Epic: Pending-Manifest oder fertig)?
func _started(id: String) -> bool:
	var e: Dictionary = items.get(id, {})
	if e.is_empty():
		return false
	if str(e.store) == "steam":
		return _find_manifest(int(e.appid)) != ""
	if str(e.app) in EpicScanner.pending_apps():
		return true
	var g := Library.get_game(id)
	return not g.is_empty() and Library.is_installed(g)


func _after_confirm(id: String, res: String) -> void:
	if not items.has(id):
		return
	_log("Dialog: %s" % res)
	if res == "ok":
		_tidy(STEAM_PROCS if str(items[id].store) == "steam" else EPIC_PROCS, items[id].get("keep", []))
		_upd(id, { "phase": "preparing", "text": "Download startet …" })
		_refocus()
	elif res == "alt":
		# Im Fenster gewählt: lieber mit Uzais eigenem Installer.
		_end(id, "cancelled", "Im Epic Games Launcher nicht gestartet")
		_refocus()
		var g := Library.get_game(id)
		if main != null and is_instance_valid(main) and not g.is_empty():
			main.install_epic_uzai(g)
	elif res == "cancel":
		_end(id, "cancelled", "Abgebrochen")
		_refocus()
	elif busy(id):
		_end(id, "failed", "%s hat den Download nicht gestartet." % ("Steam" if str(items[id].store) == "steam" else "Der Epic Games Launcher"))
		_refocus()


## Knöpfe des Dialogs als Auswahl in Uzai (Lizenz, mehrere „Installieren“, Unbekanntes).
## "pressed", "remote" oder "cancel".
func _ask_buttons(id: String, store: String, w: Dictionary, choices: Array) -> String:
	if main == null or not is_instance_valid(main):
		return "remote"
	_upd(id, { "phase": "ask", "text": "Wartet auf deine Auswahl in Uzai …" })
	_refocus()
	var opts: Array = []
	for c in choices:
		var sub := ""
		match str(c.kind):
			"agree": sub = "Lizenzvereinbarung – Uzai stimmt nie selbst zu"
			"install": sub = "Installation starten"
			"cancel": sub = "Installation nicht starten"
		opts.append([int(c.i), str(c.name), sub])
	opts.append(["remote", "Fenster in Uzai bedienen", "Bild des Fensters, Steuerkreuz und A"])
	var box := { "v": null, "done": false }
	var head := "%s fragt nach" % ("Steam" if store == "steam" else "Epic Games")
	var auswahl: Variant = main.open_choice(head, opts, null, func(v: Variant) -> void:
		box.v = v
		box.done = true, str(w.get("title", "")))
	# B schließt ohne Wahl. Gibt main die Ebene nicht zurück, ist es die oberste. Früher immer so:
	# Ging im selben Bild etwas anderes darüber auf, hing die falsche Ebene am Ausgang.
	var layer: Control = auswahl as Control
	if layer == null:
		await get_tree().process_frame
		layer = Nav.top_layer()
	if layer and layer.has_signal("closed"):
		layer.closed.connect(func() -> void: box.done = true)
	# Ohne Ebene gäbe es keinen Ausgang: dann wie abgebrochen.
	while not bool(box.done) and is_instance_valid(layer):
		await get_tree().process_frame
	if box.v == null:
		return "cancel"
	if str(box.v) == "remote":
		return "remote"
	var chosen := {}
	for c in choices:
		if int(c.i) == int(box.v):
			chosen = c
	var inv := await Helper.run("discord-invoke", { "i": int(box.v) }, 6.0)
	_log("%s: von dir gewählt „%s“: %s" % [store, str(chosen.get("name", "?")), JSON.stringify(inv.get("result", inv.get("error", "")))])
	if str(chosen.get("kind", "")) == "cancel":
		return "cancel"
	_upd(id, { "phase": "dialog", "text": "Warten auf Download …" })
	return "pressed"


## Das Fenster in Uzai bedienen: Bild des Fensters, Tasten über den Controller. "ok" oder "cancel".
func _remote(id: String, store: String, w: Dictionary) -> String:
	if main == null or not is_instance_valid(main):
		return "timeout"
	_upd(id, { "phase": "ask", "text": "Fenster wird in Uzai bedient …" })
	_refocus()
	var remote_layer: GDScript = load("res://src/ui/layers/window_remote.gd")
	var l = remote_layer.new()
	l.hwnd = Fremd.zahl(w.get("hwnd"))
	var who := "Steam" if store == "steam" else "Epic Games Launcher"
	var wt := str(w.get("title", "")).strip_edges()
	l.heading = who if wt == "" or wt.to_lower() == who.to_lower() or wt.to_lower() == "steam" else "%s – %s" % [who, wt]
	l.done_check = func() -> bool: return _started(id)
	if store == "epic":
		# Das Fenster behält die Tastatur, solange es in Uzai bedient wird (sonst setzt der Launcher
		# den Fokus bei jedem Wechsel zurück), und Uzai nimmt den Controller im Hintergrund an.
		l.hold_focus = true
		var g := Library.get_game(id)
		if not g.is_empty() and EpicInstallS.can_install(g):
			l.alt_text = "Ohne Launcher installieren"
	main.open_layer(l)
	var box := { "r": "" }
	l.finished.connect(func(r: String) -> void: box.r = r)
	# Verschwindet die Ebene, ohne sich zu melden, gilt das als abgebrochen (sonst hinge die Schleife für immer, und
	# Uzai bliebe ganz oben).
	while box.r == "" and is_instance_valid(l):
		await get_tree().process_frame
	return box.r if box.r in ["ok", "alt"] else "cancel"


# --- Pausieren, Fortsetzen, Abbrechen ---------------------------------------------------------

func pause(id: String) -> String:
	if str(entry(id).get("how", "")) == "uzai":
		return await _uzai_control(id, "pause")
	return await _control(id, "SetClientAppUpdateState", 0, "paused", "Pausiert")


func resume(id: String) -> String:
	if str(entry(id).get("how", "")) == "uzai":
		return await _uzai_control(id, "resume")
	return await _control(id, "SetClientAppUpdateState", 1, "preparing", "Wird fortgesetzt …")


## Abbrechen: Steam entfernt dabei auch, was schon geladen ist. "" = ok, sonst der Grund.
func cancel(id: String) -> String:
	var e := entry(id)
	if e.is_empty():
		return "Nicht in der Liste"
	if str(e.get("how", "")) == "uzai":
		return await _uzai_control(id, "cancel")
	if str(e.phase) in ["dialog", "ask", "start"]:
		_end(id, "cancelled", "Abgebrochen")
		return ""
	var why := await _control(id, "UninstallClientApp", -1, "cancelled", "Abgebrochen")
	if why == "":
		_end(id, "cancelled", "Abgebrochen – Steam entfernt die geladenen Dateien")
	return why


func _control(id: String, method: String, action: int, phase: String, text: String) -> String:
	var e := entry(id)
	if e.is_empty() or str(e.store) != "steam":
		return "Geht nur bei Steam – Epic lässt sich nur im Launcher anhalten."
	if Library.demo:
		_upd(id, { "phase": phase, "text": text, "speed": 0.0 })
		e["demo_paused"] = phase == "paused"
		return ""
	var r := await _steam_remote(method, int(e.appid), action)
	if not r.ok:
		return steam_refused(str(r.get("error", "")))
	_upd(id, { "phase": phase, "text": text, "speed": 0.0 })
	e["samples"] = []
	return ""


## Fertige, abgebrochene und gescheiterte Einträge aus der Liste nehmen.
func dismiss(id: String) -> void:
	if items.has(id) and not busy(id):
		items.erase(id)
		_save()
		changed.emit(id)


# --- Warteschlange, Updates, nachts (Download-Zentrale) -----------------------------------------

## Steht dieses Spiel in Uzais Warteschlange?
func queued(id: String) -> bool:
	return DlQueue.index_of(queue, id) >= 0


func queue_entry(id: String) -> Dictionary:
	var i := DlQueue.index_of(queue, id)
	return queue[i] if i >= 0 else {}


## Hinten anstellen: kind install | update, when jetzt | nachts; accept: der Platz, den du schon
## bestätigt hast (ok | knapp | voll). Läuft gerade nichts und darf es jetzt, startet es gleich.
func enqueue(g: Dictionary, kind: String, when: String, accept := "ok") -> void:
	var id := str(g.get("id", ""))
	if id == "" or busy(id):
		return
	queue = DlQueue.add(queue, DlQueue.entry(id, kind, when, int(Time.get_unix_time_from_system()), accept))
	_log("Warteschlange: %s (%s, %s)" % [Library.display_title(g), kind, when])
	_save_queue()
	_queue_tick()


func unqueue(id: String) -> void:
	if queued(id):
		queue = DlQueue.remove(queue, id)
		_save_queue()


func queue_move(id: String, delta: int) -> void:
	queue = DlQueue.move(queue, id, delta)
	_save_queue()


func queue_when(id: String, when: String) -> void:
	var i := DlQueue.index_of(queue, id)
	if i < 0 or not (when in DlQueue.WHENS):
		return
	queue[i]["when"] = when
	queue[i]["held"] = ""
	_save_queue()
	_queue_tick()


## Sofort anstoßen, auch wenn noch etwas lädt (Steam stellt es dann selbst hinten an). Den Platz
## hast du mit diesem Druck bestätigt. "" = angestoßen, sonst der Grund.
func start_queued(id: String) -> String:
	var e := queue_entry(id)
	if e.is_empty():
		return "Nicht in der Warteschlange"
	unqueue(id)
	var g := Library.get_game(id)
	if g.is_empty():
		return "Das Spiel ist nicht mehr in der Bibliothek."
	if str(e.kind) == "update":
		return await update_now(g)
	start(g, {})
	return ""


func _save_queue() -> void:
	Config.set_value("downloads.queue", queue.map(func(x: Dictionary) -> Dictionary:
		return { "id": x.id, "kind": x.kind, "when": x.when, "added": x.added, "accept": x.accept }))
	queue_changed.emit()


## Anstehende Steam-Updates der Bibliothek: [{ id, appid, title, u (DlQueue.update_state) }],
## größte zuerst, ohne die, die gerade über Uzai laden. Höchstens alle UPDATES_S neu gelesen.
func pending_updates(force := false) -> Array:
	if Library.demo:
		return _demo_updates.filter(func(x: Dictionary) -> bool: return not busy(str(x.id)))
	# Liest der Hilfsfaden gerade (updates_auffrischen), gilt so lange der alte Stand – nie zweimal dieselben Dateien.
	if (force or Time.get_ticks_msec() - _updates_at > int(UPDATES_S * 1000.0)) and not _updates_liest:
		_updates_at = Time.get_ticks_msec()
		_updates = _updates_aus(_manifeste_lesen(_steam_libs()))
	return _updates.filter(func(x: Dictionary) -> bool: return not busy(str(x.id)))


## Der Stand von pending_updates, ohne etwas von der Platte zu lesen (für Seiten: erst zeigen, was bekannt ist,
## und mit updates_auffrischen nachziehen).
func updates_stand() -> Array:
	return (_demo_updates if Library.demo else _updates).filter(func(x: Dictionary) -> bool: return not busy(str(x.id)))


## Frischt den Stand auf wie pending_updates (höchstens alle UPDATES_S), aber die Dateien liest der Hilfsfaden:
## Bei vielen Steam-Spielen stockte sonst einmal je Minute das Bild, solange Startseite oder Downloads offen sind.
## Mit await; kehrt sofort zurück, wenn der Stand frisch ist oder schon gelesen wird.
func updates_auffrischen() -> void:
	if Library.demo or _updates_liest or Time.get_ticks_msec() - _updates_at <= int(UPDATES_S * 1000.0):
		return
	_updates_liest = true
	var libs: Array = _steam_libs().duplicate()
	var roh: Variant = await Arbeit.ergebnis(func() -> Array: return _manifeste_lesen(libs))
	_updates_liest = false
	if roh is Array:
		_updates_at = Time.get_ticks_msec()
		_updates = _updates_aus(roh)


## Reine Dateiarbeit (läuft auch im Hilfsfaden): die appmanifests dieser Steam-Bibliotheken, bei denen ein Update
## ansteht – [{ appid (Text), u (DlQueue.update_state) }].
static func _manifeste_lesen(libs: Array) -> Array:
	var out: Array = []
	for lib in libs:
		var apps := str(lib).path_join("steamapps")
		var da := DirAccess.open(apps)
		if da == null:
			continue
		for f in da.get_files():
			if not (f.begins_with("appmanifest_") and f.ends_with(".acf")):
				continue
			var st: Variant = VDF.get_ci(VDF.parse_file(apps.path_join(f)), "AppState", {})
			if not (st is Dictionary):
				continue
			var u := DlQueue.update_state(st)
			if not u.is_empty():
				out.append({ "appid": str(VDF.get_ci(st, "appid", "0")), "u": u })
	return out


## Dazu die Spiele der Bibliothek (nur im Hauptfaden), größtes Update zuerst.
func _updates_aus(roh: Array) -> Array:
	var out: Array = []
	for r: Dictionary in roh:
		var g := Library.get_game("steam:%s" % str(r.appid))
		if g.is_empty():
			continue
		out.append({ "id": str(g.id), "appid": int(g.get("appid", 0)), "title": Library.display_title(g), "u": r.u })
	out.sort_custom(func(a, b) -> bool: return int(a.u.remaining) > int(b.u.remaining))
	return out


## Steht für dieses Spiel ein Update an? Nur aus dem schon gelesenen Stand (liest nichts von der
## Platte; pending_updates frischt ihn auf). {} = nein oder lädt gerade über Uzai.
func update_known(id: String) -> Dictionary:
	return {} if busy(id) else _update_of(id)


func _update_of(id: String) -> Dictionary:
	for x in (_demo_updates if Library.demo else _updates):
		if str(x.id) == id:
			return x.u
	return {}


## Ein anstehendes Update jetzt anstoßen – derselbe Auftrag wie „Aktualisieren“ in der Steam-App
## am Handy. Steam lädt dann selbst; Uzai zeigt den Fortschritt. "" = angestoßen, sonst der Grund.
func update_now(g: Dictionary) -> String:
	var id := str(g.get("id", ""))
	var appid := int(g.get("appid", 0))
	if appid <= 0 or str(g.get("source", "")) != "steam":
		return "Updates startet Uzai nur bei Steam-Spielen."
	if busy(id):
		return ""
	if not steam_direct():
		return "Aus Uzai geht das mit der Steam-Anmeldung (Einstellungen → Konten → Steam). Sonst lädt Steam das Update selbst."
	var e := _new_entry(g)
	e.merge({ "kind": "update", "phase": "preparing", "how": "direkt", "can_pause": true, "seen": true,
		"text": "Steam startet das Update …", "manifest": _find_manifest(appid) }, true)
	items[id] = e
	_log("Update angestoßen: %s" % str(e.title))
	_changed(id)
	queue_changed.emit()
	_timer.start()
	if Library.demo:
		var u := _update_of(id)
		e["demo_total"] = float(u.get("total", 0)) if float(u.get("total", 0)) > 0.0 else 2.0 * 1073741824.0
		_demo_run(id)
		return ""
	# Fortsetzen startet ein wartendes Update; kennt Steam das nicht, geht es wie ein Install-Auftrag.
	var r := await _steam_remote("SetClientAppUpdateState", appid, 1)
	if not r.ok:
		r = await _steam_remote("InstallClientApp", appid)
	if not r.ok:
		var why := steam_refused(str(r.get("error", "")))
		_end(id, "failed", why)
		return why
	_save()
	return ""


## „Nachts laden“ eingeschaltet?
func night_on() -> bool:
	return bool(Config.get_value("downloads.night", false))


## Zeitfenster [ab, bis] in vollen Stunden.
func night_hours() -> Array:
	return [clampi(int(str(Config.get_value("downloads.night_from", "1"))), 0, 23),
		clampi(int(str(Config.get_value("downloads.night_to", "6"))), 0, 23)]


## Darf die Nacht-Warteschlange jetzt laden? Eingeschaltet, im Zeitfenster und Uzai im Ruhemodus.
func night_now() -> bool:
	if ctx_override.has("night"):
		return bool(ctx_override.night)
	if not night_on() or not _rest_active():
		return false
	var h := night_hours()
	return DlQueue.in_window(int(Time.get_datetime_dict_from_system().hour), int(h[0]), int(h[1]))


func _rest_active() -> bool:
	if ctx_override.has("rest"):
		return bool(ctx_override.rest)
	var m: Node = main if main != null and is_instance_valid(main) else (get_tree().current_scene if is_inside_tree() else null)
	var r: Variant = m.get("rest") if m != null else null
	return r is Object and bool((r as Object).get("active"))


func _in_game() -> bool:
	return bool(ctx_override.get("game", Launcher.in_game))


## Lädt gerade etwas (nicht pausiert)? Dann wartet die Warteschlange.
func _downloading() -> bool:
	return items.values().any(func(e: Dictionary) -> bool: return not (str(e.phase) in ENDED) and str(e.phase) != "paused")


## Kann dieser Eintrag ohne dich anlaufen (kein Fenster, keine Rückfrage)? Steam mit Uzais
## Anmeldung ja; Epic und Steam ohne Anmeldung zeigen einen Dialog – die warten, bis du in Uzai bist.
func silent(g: Dictionary) -> bool:
	return str(g.get("source", "")) == "steam" and steam_direct()


## Platz vor dem Start (Storage, StorageFlow): "" = darf los, sonst warum nicht.
func _space_hold(e: Dictionary, g: Dictionary) -> String:
	var sf: Script = load("res://src/ui/storage_flow.gd")
	var need := -1
	var dir := ""
	if str(e.kind) == "update":
		need = int(_update_of(str(e.id)).get("remaining", -1))
		dir = str(g.get("install_dir", ""))
	else:
		need = int(sf.call("need_cached", g))
		dir = str(sf.call("target_dir", g))
	return DlQueue.space_hold(need, int(sf.call("free_at", dir)), str(e.accept))


## Alle paar Sekunden: die Meldung nach dem Ruhemodus, nachts anstehende Updates einreihen und –
## wenn nichts mehr lädt – das Nächste der Warteschlange anstoßen.
func _queue_tick() -> void:
	var rest := _rest_active()
	if _rest_was and not rest and not _quiet_done.is_empty():
		Toasts.show_toast("Im Ruhemodus geladen", DlQueue.summary(_quiet_done), "download", { "ms": 6500 })
		_quiet_done.clear()
	_rest_was = rest
	var night := night_now()
	var dirty := false
	if night and bool(Config.get_value("downloads.night_updates", true)) and steam_direct():
		var now := int(Time.get_unix_time_from_system())
		for u in pending_updates():
			if str(u.u.phase) == "wartet" and not queued(str(u.id)):
				queue = DlQueue.add(queue, DlQueue.entry(str(u.id), "update", "nachts", now))
				dirty = true
	if queue.is_empty():
		if dirty:
			_save_queue()
		return
	var playing := str(ctx_override.get("playing", str(Launcher.current.get("id", "")) if Launcher.in_game else ""))
	var ctx := { "busy": _downloading(), "night": night, "playing": playing }
	var drop: Array = []
	for i in DlQueue.candidates(queue, ctx):
		var e: Dictionary = queue[i]
		var g := Library.get_game(str(e.id))
		var upd := str(e.kind) == "update"
		# Nicht mehr nötig: Spiel weg, schon installiert, Update schon erledigt (z. B. in Steam).
		if g.is_empty() or (not upd and Library.is_installed(g)) or (upd and pending_updates().all(func(x: Dictionary) -> bool: return str(x.id) != str(e.id))):
			drop.append(str(e.id))
			continue
		var held := ""
		if not silent(g) and (_in_game() or rest):
			held = "anwesend"
		elif upd and not steam_direct():
			held = "anmeldung"
		else:
			held = _space_hold(e, g)
		if held != str(e.get("held", "")):
			e["held"] = held
			dirty = true
		if held != "":
			continue
		_log("Warteschlange startet: %s (%s)" % [Library.display_title(g), "nachts" if str(e.when) == "nachts" else "danach"])
		queue = DlQueue.remove(queue, str(e.id))
		for d in drop:
			queue = DlQueue.remove(queue, str(d))
		_save_queue()
		if upd:
			update_now(g)
		else:
			start(g, { "unattended": rest or _in_game() })
		return
	for d in drop:
		queue = DlQueue.remove(queue, str(d))
	if dirty or not drop.is_empty():
		_save_queue()


## Steams Bandbreitengrenze (kbit/s; 0 = keine, -1 = unbekannt) aus config.vdf – nur gelesen,
## ändern geht nur in Steam (Einstellungen → Downloads).
func steam_throttle() -> int:
	if Library.demo:
		return 0
	var root := Library.steam_root()
	var p := root.path_join("config/config.vdf") if root != "" else ""
	if p == "" or not FileAccess.file_exists(p):
		return -1
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return -1
	return DlQueue.throttle_kbps(f.get_buffer(mini(f.get_length(), 4 * 1048576)).get_string_from_utf8())


## Vorführung: zwei anstehende Updates, damit die Zentrale etwas zeigt.
func demo_fill() -> void:
	if not Library.demo or not _demo_updates.is_empty():
		return
	for x in [["steam:1245620", 2.4], ["steam:1145360", 0.6]]:
		var g := Library.get_game(str(x[0]))
		if g.is_empty():
			continue
		var b := int(float(x[1]) * 1073741824.0)
		_demo_updates.append({ "id": str(g.id), "appid": int(g.get("appid", 0)), "title": Library.display_title(g),
			"u": { "phase": "wartet", "total": b, "got": 0, "remaining": b, "result": 0, "scheduled": 0 } })


# --- Ablauf -----------------------------------------------------------------------------------

func _poll() -> void:
	_ticks += 1
	var any := false
	for id in items.keys():
		if not items.has(id) or not busy(str(id)):
			continue
		any = true
		if bool(items[id].get("demo", false)):
			continue
		if str(items[id].store) == "steam":
			_poll_steam(str(id))
		elif str(items[id].get("how", "")) == "uzai":
			_poll_uzai(str(id))
		else:
			_poll_epic(str(id))
	if not any:
		_timer.stop()


func _on_library_changed() -> void:
	for id in items.keys():
		if not busy(str(id)) or str(items[id].store) != "epic" or str(items[id].get("how", "")) == "uzai":
			continue
		var g := Library.get_game(str(id))
		if not g.is_empty() and Library.is_installed(g):
			_end(str(id), "done", "Fertig installiert")


func _speed(e: Dictionary, got: float) -> float:
	var now := Time.get_ticks_msec()
	var s: Array = e.get("samples", [])
	if not s.is_empty() and float(s[s.size() - 1][1]) > got:
		s.clear()
	s.append([now, got])
	while s.size() > 2 and now - int(s[0][0]) > 30000:
		s.pop_front()
	e["samples"] = s
	return P.speed_from(s)


func _upd(id: String, fields: Dictionary, log_it := true) -> void:
	if not items.has(id):
		return
	var e: Dictionary = items[id]
	var before := str(e.get("phase", "")) + "|" + str(e.get("text", ""))
	e.merge(fields, true)
	if log_it and before != str(e.phase) + "|" + str(e.text):
		_log("%s: %s – %s" % [str(e.title), str(e.phase), str(e.text)])
	_changed(id)


func _end(id: String, phase: String, text: String) -> void:
	if not items.has(id) or not busy(id):
		return
	var e: Dictionary = items[id]
	e["phase"] = phase
	e["text"] = text
	e["speed"] = 0.0
	if phase == "done":
		e["frac"] = 1.0
	_log("%s: %s – %s" % [str(e.title), phase, text])
	_save()
	_changed(id)
	var upd := str(e.get("kind", "")) == "update"
	if phase == "done":
		finished.emit(id)
		if upd:
			# Erledigt: beim nächsten Blick neu lesen (Demo: aus der Liste).
			_updates_at = -1000000
			_demo_updates = _demo_updates.filter(func(u: Dictionary) -> bool: return str(u.id) != id)
			queue_changed.emit()
	if not (phase in ["done", "failed"]):
		return
	# Im Ruhemodus still: gesammelt, eine Meldung beim Aufwachen (nachts klingt nichts).
	if _rest_active():
		_quiet_done.append(str(e.title) if phase == "done" else "%s (%s)" % [str(e.title), "nicht geladen"])
		return
	# Im Spiel nur kurz und leise über dem Spiel.
	if _in_game():
		Toasts.show_toast(("Aktualisiert" if upd else "Fertig installiert") if phase == "done" else "Download gescheitert", str(e.title), "check" if phase == "done"
				else "warning", { "ms": 3500, "quiet": true, "overlay": true })
		return
	if phase == "done":
		var g := Library.get_game(id)
		var opts := { "sound": "select", "ms": 7000, "overlay": true }
		if main != null and is_instance_valid(main) and not g.is_empty():
			var m := main
			opts["open"] = func() -> void: m.call("launch", Library.get_game(id))
			opts["open_text"] = "Spielen"
			opts["go"] = func() -> void: m.call("open_game_note", Library.get_game(id))
			opts["go_text"] = "Zum Spiel"
		Toasts.show_toast("Aktualisiert" if upd else "Fertig installiert", "%s ist bereit zum Spielen." % str(e.title), "check", opts)
	else:
		Toasts.show_toast("Nicht aktualisiert" if upd else "Nicht installiert", "%s: %s" % [str(e.title), text], "warning", { "ms": 7000 })


func _changed(id: String) -> void:
	changed.emit(id)


## Uzai bleibt ganz oben, solange ein Launcher-Dialog wartet (main._cover „install“).
func _hold(on: bool) -> void:
	if main != null and is_instance_valid(main):
		main.hold_front(on)


func _refocus() -> void:
	if main != null and is_instance_valid(main):
		main.bring_to_front()


## Sichtbare Fenster der Launcher-Prozesse (proc-windows im Helfer).
func _windows(names: Array, minimize := false, keep: Array = []) -> Array:
	var r := await Helper.run("proc-windows", { "names": names, "minimize": minimize, "keep": keep }, 6.0)
	if r.ok and r.result is Dictionary and r.result.get("windows") is Array:
		return r.result.windows
	return []


func _hwnds(names: Array) -> Array:
	var out: Array = []
	for w in Fremd.zeilen(await _windows(names)):
		out.append(Fremd.zahl(w.get("hwnd")))
	return out


## Nach dem Bestätigen: Fenster der Launcher minimieren (ohne Fokus), Uzai bleibt vorn. keep:
## Fenster, die schon vorher offen waren (bei Steam z. B. die Freundesliste), bleiben.
func _tidy(names: Array, keep: Array = []) -> void:
	if not Config.is_windows() or not Helper.available:
		return
	await get_tree().create_timer(1.0).timeout
	var n := (await _windows(names, true, keep)).size()
	_log("Launcher-Fenster aufgeräumt (%d gesehen)" % n)
	_refocus()


# --- Merken über einen Neustart ---------------------------------------------------------------

func _save() -> void:
	var out: Array = []
	for e in items.values():
		if not (str(e.phase) in ENDED):
			out.append({ "id": e.id, "store": e.store, "appid": e.appid, "app": e.app, "title": e.title, "how": e.how,
				"started": e.started, "manifest": e.manifest, "kind": str(e.get("kind", "install")), "epic": e.get("epic", {}) })
	Config.set_value("installs.active", out)


func _restore() -> void:
	if Library.demo:
		return
	var saved: Variant = Config.get_value("installs.active", [])
	if not (saved is Array):
		return
	var now := int(Time.get_unix_time_from_system())
	for s in saved:
		if not (s is Dictionary):
			continue
		var id := str(s.get("id", ""))
		var g := Library.get_game(id)
		var upd := str(s.get("kind", "")) == "update"
		if g.is_empty() or (Library.is_installed(g) and not upd) or now - int(s.get("started", 0)) > 3 * 86400:
			continue
		var e := _new_entry(g)
		if str(s.get("how", "")) == "uzai":
			# Uzais eigener Installer: wartet mit dem gesicherten Stand auf „Fortsetzen“.
			if not epic.has_saved(str(e.app)):
				continue
			e.merge({ "phase": "paused", "how": "uzai", "can_pause": true, "started": int(s.get("started", now)), "text": "Pausiert – „Fortsetzen“ lädt weiter",
				"kind": "update" if upd else "install", "epic": Fremd.verz(g.get("epic")).duplicate() }, true)
			items[id] = e
			continue
		e.merge({ "phase": "preparing", "how": str(s.get("how", "")), "started": int(s.get("started", now)),
			"manifest": str(s.get("manifest", "")), "text": "Wird fortgesetzt …", "can_pause": str(s.get("store", "")) == "steam",
			"kind": "update" if upd else "install" }, true)
		e["seen"] = str(e.manifest) != ""
		items[id] = e
	if not items.is_empty():
		_timer.start()
	discover()
	_save()


# --- Demo ------------------------------------------------------------------------------------

## Demo: ein Download, der in gut 30 s durchläuft (für den Rundgang und zum Ausprobieren).
func _demo_run(id: String) -> void:
	var e: Dictionary = items[id]
	e["demo"] = true
	e["how"] = "direkt" if str(e.store) == "steam" else "dialog"
	e["can_pause"] = str(e.store) == "steam"
	var upd := str(e.get("kind", "")) == "update"
	_upd(id,
			{ "phase": "preparing", "text": ("Steam startet das Update …" if upd else "Steam startet den Download …") if str(e.store) == "steam" else "Epic lädt …" })
	var total: float = float(e.get("demo_total", 8.4 * 1073741824.0))
	var got := 0.0
	await get_tree().create_timer(1.5).timeout
	while busy(id) and got < total:
		await get_tree().create_timer(0.5).timeout
		if not busy(id):
			return
		if bool(items[id].get("demo_paused", false)) or str(items[id].phase) == "paused":
			continue
		got = minf(total, got + total / 60.0)
		var sp := total / 30.0
		_upd(id, { "phase": "downloading", "frac": got / total, "got": got, "total": total, "speed": sp,
			"text": P.line("Wird aktualisiert" if upd else "Wird geladen", got / total, got, total, sp) }, false)
	if not busy(id):
		return
	Library.set_field(id, "installed", true)
	_end(id, "done", "Aktualisiert" if upd else "Fertig installiert")


func _log(text: String) -> void:
	Logdatei.zeile(Config.path("logs/installs.log"), text, 256 * 1024)
