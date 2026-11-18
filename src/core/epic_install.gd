extends Node
## Uzais eigener Installer für gekaufte Epic-Spiele – ohne Epic Games Launcher, wie Heroic und
## Legendary (inoffiziell, nur nach ausdrücklicher Wahl; Epic kann das jederzeit ändern). Hängt als
## Kind an Installs (Installs.epic), das Fortschritt, Mitteilungen und die Downloads-Liste zeigt.
##
## Ablauf: Mit der vorhandenen Epic-Anmeldung (epic_account.gd) fragt Uzai Epic nach den Adressen
## des Manifests, lädt es ohne Anmeldung vom Download-Server, prüft seine SHA-1 laut Epic und liest
## es mit dem eigenen, strengen Leser (epic_manifest.gd). Dann laden mehrere Fäden die Chunks (nur
## https zu Epics Download-Servern, keine Weiterleitungen, Größengrenzen), prüfen jeden (SHA-1),
## schreiben die Teile in Zwischendateien „<Datei>.uzai-teil“ im Spielordner und prüfen jede fertige
## Datei (SHA-1 laut Manifest). Erst wenn alles stimmt, ersetzen die Zwischendateien die echten –
## ein abgebrochenes Update lässt das alte Spiel heil.
## Pausieren und Abbrechen jederzeit; der Stand (welche Chunks und Dateien fertig sind) liegt im
## Datenordner, so geht es auch nach einem Neustart weiter. „Prüfen und aktualisieren“ holt eine
## neue Fassung oder prüft alle Dateien und lädt nur kaputte neu.
##
## Geschrieben wird nur im Spielordner unter dem gewählten Ordner, nie über Verknüpfungen; gelöscht
## (Abbrechen, Deinstallieren, weggefallene Dateien beim Update) nur, was laut Manifest dazugehört.
## Anmeldedaten gehen nur in der Kopfzeile an Epics Dienst, nie an die Download-Server, nie ins
## Protokoll. Ausgeführt wird nichts – das Spiel startet erst, wenn du es startest (ohne
## Voraussetzungs-Installer und ohne Adminrechte).

const M := preload("res://src/library/epic_manifest.gd")
const P := preload("res://src/core/install_parse.gd")
const Lang := preload("res://src/core/lang.gd")
const Fremd := preload("res://src/core/fremd.gd")
const Logdatei := preload("res://src/core/logdatei.gd")
const LAUNCHER_HOST := "https://launcher-public-service-prod06.ol.epicgames.com"
const DIR := "epic_uzai"            ## im gemeinsamen Datenordner: installed.json, <App>.manifest, <App>.job.*
const WORKERS := 6
const TEMP := ".uzai-teil"
const SAVE_S := 5.0
const ATTEMPTS := 6

## App-Name → Auftrag (siehe _new_job). phase: prep | run | check | finish | paused | done | failed | cancelled.
var jobs := {}


# --- Abfragen --------------------------------------------------------------------------------

## Kann Uzai dieses Spiel selbst installieren? (Epic-Anmeldung in Uzai und Katalog-Angaben.)
static func can_install(g: Dictionary) -> bool:
	var e: Variant = g.get("epic", {})
	if not (e is Dictionary) or str(g.get("source", "")) != "epic":
		return false
	if str(e.get("namespace", "")) == "" or str(e.get("item", "")) == "" or not _app_ok(str(e.get("app", ""))):
		return false
	return Library.epic_account != null and Library.epic_account.logged_in()


static var _APP_NAME := RegEx.create_from_string("^[A-Za-z0-9_.\\-]{1,128}$")


static func _app_ok(app: String) -> bool:
	return _APP_NAME.search(app) != null


## Hat Uzai dieses Spiel selbst installiert?
static func is_uzai(g: Dictionary) -> bool:
	return bool(g.get("epic_uzai", false))


func busy(app: String) -> bool:
	return jobs.has(app) and str(jobs[app].phase) in ["prep", "run", "check", "finish"]


## Stand eines Auftrags für die Downloads-Liste: { phase, text, got, total, frac, dl }.
func status(app: String) -> Dictionary:
	if not jobs.has(app):
		return {}
	var j: Dictionary = jobs[app]
	j.mutex.lock()
	var out := { "phase": str(j.phase), "text": str(j.text), "got": float(j.got), "total": float(j.total), "dl": float(j.dl),
		"error": str(j.err) }
	j.mutex.unlock()
	out["frac"] = clampf(out.got / out.total, 0.0, 1.0) if out.total > 0.0 else -1.0
	return out


static func dir_path() -> String:
	return Config.shared_path(DIR)


## Von Uzai installierte Spiele: { App: { dir, exe, args, build, hash, ns, item, title, account, size, at } }.
static func records() -> Dictionary:
	var d: Variant = Config.read_json(dir_path().path_join("installed.json"), {})
	var out := {}
	if not (d is Dictionary):
		return out
	for k in d.keys():
		var r: Variant = d[k]
		if r is Dictionary and _app_ok(str(k)) and str(r.get("dir", "")) != "":
			out[str(k)] = r
	return out


static func _save_records(recs: Dictionary) -> void:
	Config.write_json(dir_path().path_join("installed.json"), recs)


## Spiele-Liste von Epic (Launcher-Dateien und Konto) mit Uzais Installationen ergänzen: Was Uzai
## installiert hat, ist „installiert“ und startet über die Programmdatei. Fehlt ein Spiel in der
## Liste (z. B. Konto gerade nicht erreichbar), kommt es aus Uzais Angaben dazu – nur für das Konto,
## mit dem es installiert wurde.
static func apply_records(list: Array, recs: Dictionary, account := "") -> Array:
	var seen := {}
	for g in list:
		var e: Variant = g.get("epic", {})
		var app := str(e.get("app", "")) if e is Dictionary else ""
		if not recs.has(app):
			continue
		seen[app] = true
		if bool(g.get("installed", false)) and not bool(g.get("epic_uzai", false)):
			continue                         # vom Launcher installiert: der gewinnt
		_mark(g, recs[app])
	for app in recs.keys():
		var r: Dictionary = recs[app]
		if seen.has(app) or account == "" or str(r.get("account", "")) != account:
			continue
		var g := { "id": "epic:%s" % app, "title": str(r.get("title", app)), "system": "epic", "source": "epic",
			"epic": { "namespace": str(r.get("ns", "")), "item": str(r.get("item", "")), "app": str(app) } }
		_mark(g, r)
		list.append(g)
	return list


static func _mark(g: Dictionary, r: Dictionary) -> void:
	var dir := str(r.get("dir", ""))
	g["installed"] = true
	g["install_dir"] = dir
	g["path"] = dir.path_join(str(r.get("exe", ""))) if str(r.get("exe", "")) != "" else ""
	g["epic_uzai"] = true


## Startparameter für ein von Uzai installiertes Spiel, als Liste (der Helfer setzt jeden Eintrag
## einzeln gequotet in die Befehlszeile, nie über cmd oder PowerShell): Parameter aus dem Manifest
## und Epics übliche Angaben, mit exchange auch der Einmal-Code für die Epic-Anmeldung im Spiel.
## Deine eigenen zusätzlichen Startparameter hängt der Launcher wie bei jedem Spiel dahinter.
static func launch_argv(g: Dictionary, exchange := "") -> PackedStringArray:
	var e: Dictionary = g.get("epic", {}) if g.get("epic") is Dictionary else {}
	var r: Dictionary = records().get(str(e.get("app", "")), {})
	return M.launch_args(str(r.get("args", "")), str(e.get("app", "")), str(e.get("namespace", "")),
		str(Config.get_value("accounts.epic_name", "")), str(Config.get_value("accounts.epic_account_id", "")), str(Lang.api("epic")),
		exchange)


## Rein: Einmal-Code holen? Nur mit eingeschalteter Einstellung (Konten → Epic Games → Mehr),
## verbundenem Epic-Konto, einer echten .exe (nie eine Batchdatei, die cmd deuten würde) und dem
## Helfer, der die Liste sicher zur Befehlszeile macht. Ob ein Spiel die Anmeldung braucht, steht
## weder im Manifest noch im Katalog verlässlich – darum wie Legendary immer, Spiele ohne Epic-
## Anmeldung übergehen die Parameter.
static func game_login_wanted(enabled: bool, logged_in: bool, exe: String, helper: bool) -> bool:
	return enabled and logged_in and helper and exe.get_extension().to_lower() == "exe"


## Startparameter für den Start gleich jetzt: holt dafür (falls gewollt) einen frischen Einmal-Code.
## Klappt das nicht, startet das Spiel trotzdem – ohne Code und mit einer ruhigen Mitteilung.
static func start_argv(g: Dictionary, exe: String) -> PackedStringArray:
	var acc: Node = Library.epic_account
	var enabled := bool(Config.get_value("accounts.epic_game_login", true))
	var code := ""
	if acc != null and game_login_wanted(enabled, acc.logged_in(), exe, Helper.available):
		code = await acc.exchange_code()
		if code == "":
			Toasts.show_toast("Ohne Epic-Anmeldung gestartet", "Die Epic-Anmeldung ist abgelaufen (Konten → Epic Games)." if str(acc.state) == "abgelaufen"
				else "Epic war gerade nicht erreichbar.", "games", { "quiet": true })
	elif acc != null and enabled and str(acc.state) == "abgelaufen" and acc.account_name() != "":
		Toasts.show_toast("Ohne Epic-Anmeldung gestartet", "Die Epic-Anmeldung ist abgelaufen (Konten → Epic Games).", "games", { "quiet": true })
	return launch_argv(g, code)


## Rein: dieselben Parameter ohne Einmal-Code – für jeden Weg außer dem Helfer (Godots eigener
## Prozessstart schreibt die Befehlszeile bei einem Fehler ins Protokoll).
static func without_code(argv: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for a in argv:
		if not (a.begins_with("-AUTH_LOGIN=") or a.begins_with("-AUTH_PASSWORD=") or a.begins_with("-AUTH_TYPE=")):
			out.append(a)
	return out


# --- Starten, Anhalten, Abbrechen --------------------------------------------------------------

## Installieren (kind „install“, base: gewählter Ordner, darin legt Uzai den Spielordner an) oder
## „check“ (installiertes Spiel: neue Fassung holen, sonst alle Dateien prüfen und kaputte neu
## laden). Läuft im Hintergrund; den Stand liefert status(). "" = gestartet, sonst der Grund.
func start(g: Dictionary, base: String, kind := "install") -> String:
	var e: Dictionary = g.get("epic", {}) if g.get("epic") is Dictionary else {}
	var app := str(e.get("app", ""))
	if not _app_ok(app) or str(e.get("namespace", "")) == "" or str(e.get("item", "")) == "":
		return "Für dieses Spiel fehlen Epics Angaben. Einstellungen → Konten → Epic Games: „Jetzt neu einlesen“."
	if busy(app):
		return ""
	var rec: Dictionary = records().get(app, {})
	var root := ""
	if kind == "check":
		if rec.is_empty():
			return "Dieses Spiel hat Uzai nicht selbst installiert."
		root = str(rec.dir)
	else:
		var why := base_problem(base)
		if why != "":
			return why
		root = _root_for(base, Library.display_title(g), app, rec)
		if root == "":
			return "Im gewählten Ordner kann Uzai keinen Spielordner anlegen. Einen anderen Ordner wählen."
	var j := _new_job(app, g, root, kind)
	jobs[app] = j
	_log("%s: %s nach %s" % [app, kind, root])
	_run(j)
	return ""


func _new_job(app: String, g: Dictionary, root: String, kind: String) -> Dictionary:
	var e: Dictionary = g.get("epic", {})
	return { "app": app, "id": str(g.get("id", "")), "title": Library.display_title(g), "ns": str(e.namespace), "item": str(e.item),
		"kind": kind, "root": root, "phase": "prep", "text": "Fragt Epic nach dem Spiel …", "mutex": Mutex.new(), "stop": "",
		"err": "", "got": 0, "total": 0, "dl": 0, "next": 0, "tasks": [], "m": {}, "raw": PackedByteArray(), "hash": "",
		"build": "", "bases": [], "loop": _loopback() }


## Anhalten: die Fäden hören nach dem laufenden Chunk auf; der Stand bleibt.
func pause(app: String) -> void:
	_signal_stop(app, "pause")


## Weiter nach Pause, Fehler oder Neustart von Uzai.
func resume(g: Dictionary) -> String:
	var app := str((g.get("epic", {}) as Dictionary).get("app", ""))
	if busy(app):
		return ""
	var j: Dictionary = jobs.get(app, {})
	var kind := str(j.get("kind", ""))
	var root := str(j.get("root", ""))
	if j.is_empty():
		var saved := _load_job(app)
		if saved.is_empty():
			return "Kein angefangener Download – nochmal installieren."
		kind = str(saved.kind)
		root = str(saved.root)
	if kind == "check":
		return start(g, "", "check")
	var nj := _new_job(app, g, root, kind)
	jobs[app] = nj
	_run(nj)
	return ""


## Abbrechen: Fäden anhalten, Zwischendateien löschen; bei einer neuen Installation auch den
## (dann leeren) Spielordner. Ein angefangenes Update lässt das Spiel, wie es war.
func cancel(app: String) -> void:
	if busy(app):
		_signal_stop(app, "cancel")
		return
	var saved := _load_job(app)
	if not saved.is_empty():
		var j := { "app": app, "root": str(saved.root), "kind": aufraeum_art(str(saved.kind), str(saved.root), records().get(app, {})),
			"phase": "cancelled", "m": {} }
		var raw := FileAccess.get_file_as_bytes(dir_path().path_join(app + ".job.manifest"))
		var pr := M.parse(raw) if not raw.is_empty() else { "ok": false }
		if bool(pr.ok):
			j.m = pr.m
		await _threaded(func() -> void: _cleanup(j))
		_drop_job(app)
	if jobs.has(app):
		jobs[app].phase = "cancelled"
		jobs[app].text = "Abgebrochen"


## Was beim Abbrechen wegfällt: bei einer neuen Installation alles laut Dateiliste – außer Uzai hat das Spiel in
## genau diesem Ordner schon fertig installiert. Dann fallen wie bei einem Update nur die Zwischendateien weg; sonst
## löschte ein abgebrochenes erneutes Installieren das vorhandene, heile Spiel.
static func aufraeum_art(kind: String, root: String, rec: Dictionary) -> String:
	return "update" if kind == "install" and root != "" and str(rec.get("dir", "")) == root else kind


func _signal_stop(app: String, why: String) -> void:
	if not jobs.has(app):
		return
	var j: Dictionary = jobs[app]
	j.mutex.lock()
	if str(j.stop) == "":
		j.stop = why
	j.mutex.unlock()


## Angefangener Download nach einem Neustart von Uzai? (Dann „Fortsetzen“ anbieten.)
func has_saved(app: String) -> bool:
	return not _load_job(app).is_empty()


# --- Ablauf ----------------------------------------------------------------------------------

func _run(j: Dictionary) -> void:
	var ok := await _prepare(j)
	if not ok:
		if str(j.phase) == "prep":
			_phase(j, "failed", str(j.err) if str(j.err) != "" else "Epic hat den Download nicht herausgegeben.")
		return
	if str(j.phase) == "done":
		return
	# Eigene Fäden (nicht Godots Arbeiter-Pool: Downloads warten lange auf das Netz und hielten
	# sonst andere Hintergrundarbeit auf); der Hauptfaden zeigt nur den Stand und sichert ihn.
	_phase(j, "run", "Wird geladen …")
	for i in mini(WORKERS, maxi(1, (j.order as Array).size())):
		var t := Thread.new()
		t.start(_worker.bind(j))
		(j.tasks as Array).append(t)
	var saved_at := Time.get_ticks_msec()
	while (j.tasks as Array).any(func(t: Thread) -> bool: return t.is_alive()):
		await get_tree().create_timer(0.25).timeout
		if Time.get_ticks_msec() - saved_at > SAVE_S * 1000.0:
			saved_at = Time.get_ticks_msec()
			_save_job(j)
	for t in j.tasks:
		(t as Thread).wait_to_finish()
	j.tasks = []
	_save_job(j)
	var stop := str(j.stop)
	if stop == "cancel":
		var weg := { "root": str(j.root), "kind": aufraeum_art(str(j.kind), str(j.root), records().get(str(j.app), {})), "m": j.m }
		await _threaded(func() -> void: _cleanup(weg))
		_drop_job(str(j.app))
		_phase(j, "cancelled", "Abgebrochen")
		return
	if str(j.err) != "":
		_phase(j, "failed", _error_text(str(j.err)))
		return
	if stop == "pause":
		_phase(j, "paused", "Pausiert")
		return
	_phase(j, "finish", "Wird abgeschlossen …")
	var why := { "e": "" }
	await _threaded(func() -> void: why.e = _switch(j))
	if str(why.e) != "":
		_phase(j, "failed", _error_text(str(why.e)))
		return
	_finish_record(j)
	_phase(j, "done", "Aktualisiert" if str(j.kind) != "install" else "Fertig installiert")


## Anmeldung, Epics Antwort, Manifest, Plan, Platz, Ordner. false = gescheitert (j.err) oder fertig
## ohne Arbeit (Phase done).
func _prepare(j: Dictionary) -> bool:
	var tok := ""
	if Library.epic_account != null:
		tok = await Library.epic_account.access_token()
	if tok == "":
		j.err = "anmeldung"
		_phase(j, "failed", _error_text("anmeldung"))
		return false
	var url := "%s/launcher/api/public/assets/v2/platform/Windows/namespace/%s/catalogItem/%s/app/%s/label/Live" % [
		_host(), str(j.ns).uri_encode(), str(j.item).uri_encode(), str(j.app).uri_encode()]
	var r := await Net.request(url, PackedStringArray(["Authorization: Bearer " + tok]), HTTPClient.METHOD_GET, "", 20.0, "api", 4 * 1024 * 1024, false)
	tok = ""
	if not r.ok:
		j.err = "nicht_erreichbar" if int(r.code) == 0 else ("anmeldung" if int(r.code) == 401 else "kein_download")
		_log("%s: Epic antwortet %d" % [j.app, int(r.code)])
		_phase(j, "failed", _error_text(str(j.err)))
		return false
	var js := JSON.new()
	var a := M.parse_assets(js.data if js.parse((r.body as PackedByteArray).get_string_from_utf8()) == OK else null, bool(j.loop))
	if not bool(a.ok):
		j.err = str(a.error)
		_phase(j, "failed", _error_text(str(j.err)))
		return false
	j.bases = a.bases
	j.build = a.build
	var rec: Dictionary = records().get(str(j.app), {})
	var old := {}
	var have := {}
	if str(j.kind) == "check":
		if str(rec.get("hash", "")) == str(a.hash):
			# Gleiche Fassung: alle Dateien prüfen, nur kaputte neu laden.
			_phase(j, "check", "Prüft die Dateien …")
			var mf := FileAccess.get_file_as_bytes(dir_path().path_join(str(j.app) + ".manifest"))
			var box := { "r": {} }
			await _threaded(func() -> void: box.r = M.parse(mf))
			if not bool(box.r.get("ok", false)):
				j.err = "kaputt"
				_phase(j, "failed", _error_text("kaputt"))
				return false
			j.m = box.r.m
			j.raw = mf
			j.hash = a.hash
			j.total = int(j.m.total)
			var hb := { "h": {} }
			await _threaded(func() -> void: hb.h = _verify(j))
			have = hb.h
			if str(j.stop) != "":
				_phase(j, "cancelled" if str(j.stop) == "cancel" else "paused", "Abgebrochen" if str(j.stop) == "cancel" else "Pausiert")
				return false
			var p0 := M.plan(j.m, {}, have)
			if (p0.files as Array).is_empty():
				_phase(j, "done", "Alle Dateien in Ordnung")
				return true
			_log("%s: %d Dateien neu zu laden" % [j.app, (p0.files as Array).size()])
			return await _plan_and_dirs(j, p0)
		var omf := FileAccess.get_file_as_bytes(dir_path().path_join(str(j.app) + ".manifest"))
		var ob := { "r": {} }
		await _threaded(func() -> void: ob.r = M.parse(omf))
		old = ob.r.m if bool(ob.r.get("ok", false)) else {}
	# Manifest vom Download-Server (ohne Anmeldung), SHA-1 laut Epic.
	_phase(j, "prep", "Lädt die Dateiliste …")
	var raw := PackedByteArray()
	for u in a.urls:
		var mr := await Net.request(str(u), PackedStringArray(), HTTPClient.METHOD_GET, "", 60.0, "api", M.MAX_MANIFEST, false)
		if mr.ok and M.sha1_hex(mr.body) == str(a.hash):
			raw = mr.body
			break
		_log("%s: Manifest von %s: %s" % [j.app, Net.origin(str(u)), "Prüfsumme falsch" if mr.ok else "Fehler %d" % int(mr.code)])
	if raw.is_empty():
		j.err = "manifest"
		_phase(j, "failed", _error_text("manifest"))
		return false
	var pb := { "r": {} }
	await _threaded(func() -> void: pb.r = M.parse(raw))
	if not bool(pb.r.get("ok", false)):
		j.err = str(pb.r.get("error", "kaputt"))
		_log("%s: Manifest abgelehnt (%s)" % [j.app, j.err])
		_phase(j, "failed", _error_text(str(j.err)))
		return false
	j.m = pb.r.m
	j.raw = raw
	j.hash = a.hash
	var p := M.plan(j.m, old, have)
	if (p.files as Array).is_empty() and (p.remove as Array).is_empty():
		_finish_record(j)
		_phase(j, "done", "Schon aktuell")
		return true
	return await _plan_and_dirs(j, p)


## Plan mit dem gesicherten Stand verbinden, Platz prüfen, Ordner anlegen (im Hilfsfaden).
func _plan_and_dirs(j: Dictionary, p: Dictionary) -> bool:
	j.plan = p
	var saved := _load_job(str(j.app))
	var same: bool = not saved.is_empty() and str(saved.get("hash", "")) == str(j.hash) and str(saved.get("root", "")) == str(j.root)
	var nc: int = (j.m.chunks as Array).size()
	var nf: int = (j.m.files as Array).size()
	j.cdone = _mask(str(saved.get("cdone", "")) if same else "", nc)
	j.fdone = _mask(str(saved.get("fdone", "")) if same else "", nf)
	if not same and not saved.is_empty() and str(saved.get("root", "")) == str(j.root):
		# Andere Fassung als beim Anhalten: alte Zwischendateien zählen nicht mehr.
		var oj := { "root": str(j.root), "kind": "update", "m": j.m }
		await _threaded(func() -> void: _cleanup(oj))
	_save_job(j)
	var res := { "e": "" }
	await _threaded(func() -> void: res.e = _build(j))
	if str(res.e) != "":
		j.err = str(res.e)
		_phase(j, "failed", _error_text(str(res.e)))
		return false
	var free := -1
	var da := DirAccess.open(str(j.root))
	if da:
		free = int(da.get_space_left())
	var need := int(j.total) - int(j.got) + 64 * 1024 * 1024
	if free >= 0 and free < need:
		j.err = "platz"
		_phase(j, "failed", "Zu wenig Platz: %s gebraucht, %s frei. Platz schaffen oder einen anderen Ordner wählen." % [P.gb(float(need)), P.gb(float(free))])
		return false
	return true


## Im Hilfsfaden: Ordner sicher anlegen, für jeden Chunk die Teile, die er füllt, und je Datei,
## wie viele Teile noch fehlen. Dateien ohne Teile (leer) und schon fertige zählen sofort.
func _build(j: Dictionary) -> String:
	var root := str(j.root)
	var why := _ensure_dir(root, "")
	if why != "":
		return why
	var made := {}
	var links := {}
	var files: Array = j.m.files
	var refs := {}
	var left: Array = []
	left.resize(files.size())
	left.fill(0)
	var order: Array = []
	var queued := {}
	var total := 0
	var got := 0
	for fi in j.plan.files:
		var f: Dictionary = files[fi]
		total += int(f.size)
		var rel := str(f.name)
		var dir := rel.get_base_dir()
		if dir != "" and not made.has(dir.to_lower()):
			why = _ensure_dir(root, dir)
			if why != "":
				return why
			made[dir.to_lower()] = true
		var final := root.path_join(rel)
		# Auch die Zwischendatei nicht: Durch eine Verknüpfung mit ihrem Namen schriebe Uzai woandershin.
		if _is_link(root, rel, links) or _is_link(root, rel + TEMP, links) or DirAccess.dir_exists_absolute(final) or DirAccess.dir_exists_absolute(final + TEMP):
			return "pfad"
		if j.fdone[fi] == 1:
			if FileAccess.file_exists(final + TEMP) or FileAccess.file_exists(final):
				got += int(f.size)
				continue
			j.fdone[fi] = 0
		var have_tmp := FileAccess.file_exists(final + TEMP)
		var off := 0
		var n := 0
		for part in f.parts:
			var c := int(part[0])
			# Schon geschrieben, wenn der Chunk fertig ist und die Zwischendatei noch da.
			if j.cdone[c] == 1 and have_tmp:
				got += int(part[2])
			else:
				if not refs.has(c):
					refs[c] = []
				(refs[c] as Array).append([fi, off, int(part[1]), int(part[2])])
				n += 1
				if not queued.has(c):
					queued[c] = true
					order.append(c)
			off += int(part[2])
		left[fi] = n
		if n == 0:
			var fe := _finish_file(j, fi)
			if fe != "":
				return fe
	# Chunks, die neu müssen, gelten bis dahin als offen.
	for c in queued.keys():
		j.cdone[c] = 0
	j.refs = refs
	j.left = left
	j.order = order
	j.mutex.lock()
	j.total = total
	j.got = got
	j.mutex.unlock()
	return ""


## Ordner unter dem Spielordner anlegen – Teil für Teil, nie durch eine Verknüpfung.
static func _ensure_dir(root: String, rel: String) -> String:
	var parent := root.get_base_dir()
	var top := DirAccess.open(parent)
	if top == null or top.is_link(root.get_file()):
		return "pfad"
	if not DirAccess.dir_exists_absolute(root) and DirAccess.make_dir_absolute(root) != OK:
		return "schreiben"
	var cur := root
	if rel == "":
		return ""
	for seg in rel.split("/"):
		var da := DirAccess.open(cur)
		if da == null:
			return "schreiben"
		var nxt := cur.path_join(seg)
		if FileAccess.file_exists(nxt):
			return "pfad"
		if da.dir_exists(seg):
			if da.is_link(seg):
				return "pfad"
		elif da.make_dir(seg) != OK:
			return "schreiben"
		cur = nxt
	return ""


## Liegt auf dem Weg zur Datei (oder bei ihr selbst) eine Verknüpfung? cache: Ordner → sicher, damit
## jeder Ordner bei vielen Dateien nur einmal angesehen wird.
static func _is_link(root: String, rel: String, cache: Dictionary = {}) -> bool:
	var dir := rel.get_base_dir()
	if dir != "":
		if not cache.has(dir):
			cache[dir] = not _is_link(root, dir, cache)
		if not bool(cache[dir]):
			return true
	var da: DirAccess = cache.get("@" + dir)
	if da == null:
		da = DirAccess.open(root.path_join(dir))
		if da == null:
			return false
		cache["@" + dir] = da
	return da.is_link(rel.get_file())


# --- Fäden -----------------------------------------------------------------------------------

func _worker(j: Dictionary) -> void:
	var conn := {}
	while true:
		j.mutex.lock()
		var c := -1
		if str(j.stop) == "" and str(j.err) == "" and int(j.next) < (j.order as Array).size():
			c = int(j.order[int(j.next)])
			j.next = int(j.next) + 1
		j.mutex.unlock()
		if c < 0:
			break
		var info: Dictionary = j.m.chunks[c]
		var got := _fetch_chunk(j, conn, info)
		if not bool(got.ok):
			if str(got.error) != "stop":
				_fail(j, str(got.error))
			break
		var data: PackedByteArray = got.data
		var finished: Array = []
		var werr := ""
		j.mutex.lock()
		for ref in j.refs.get(c, []):
			werr = _write_part(str(j.root), str(j.m.files[int(ref[0])].name), int(ref[1]), data, int(ref[2]), int(ref[3]))
			if werr != "":
				break
			j.left[int(ref[0])] -= 1
			j.got = int(j.got) + int(ref[3])
			if j.left[int(ref[0])] == 0:
				finished.append(int(ref[0]))
		if werr == "":
			j.cdone[c] = 1
		j.dl = int(j.dl) + int(info.size)
		j.mutex.unlock()
		if werr != "":
			_fail(j, werr)
			break
		var ferr := ""
		for fi in finished:
			ferr = _finish_file(j, fi)
			if ferr != "":
				break
		if ferr != "":
			_fail(j, ferr)
			break
	if conn.get("hc") is HTTPClient:
		(conn.hc as HTTPClient).close()


func _fail(j: Dictionary, why: String) -> void:
	j.mutex.lock()
	if str(j.err) == "":
		j.err = why
	j.mutex.unlock()


func _stopped(j: Dictionary) -> bool:
	j.mutex.lock()
	var s: bool = str(j.stop) != "" or str(j.err) != ""
	j.mutex.unlock()
	return s


## Laufende Übertragung abbrechen? Nur bei „Abbrechen“ und Fehlern – beim Pausieren lädt jeder Faden
## seinen Chunk noch fertig (sonst wäre das Angefangene umsonst).
func _aborted(j: Dictionary) -> bool:
	j.mutex.lock()
	var s: bool = str(j.stop) == "cancel" or str(j.err) != ""
	j.mutex.unlock()
	return s


## Einen Chunk laden und prüfen; bei Fehlern ein paar Versuche. Alle Fäden nehmen den Server, der
## zuletzt geliefert hat (j.good); antwortet einer gar nicht oder mit einem Fehler, meidet ihn dieser
## Faden. Kam nur Verfälschtes an, heißt der Grund „pruefsumme“.
func _fetch_chunk(j: Dictionary, conn: Dictionary, info: Dictionary) -> Dictionary:
	var bases: Array = j.bases
	var n := bases.size()
	var bad: Dictionary = conn.get("bad", {})
	conn["bad"] = bad
	var last := "nicht_erreichbar"
	var corrupt := false
	j.mutex.lock()
	var bi := int(j.get("good", 0)) % n
	j.mutex.unlock()
	for attempt in ATTEMPTS:
		if _stopped(j):
			return { "ok": false, "error": "stop" }
		if bad.has(bi) and bad.size() < n:
			for k in n:
				if not bad.has((bi + k) % n):
					bi = (bi + k) % n
					break
		var url := str(bases[bi]) + "/" + str(info.path)
		if not M.cdn_ok(url, bool(j.loop)):
			return { "ok": false, "error": "adresse" }
		var r := _http_get(j, conn, url, int(info.size) + 8192)
		if int(r.code) == 200:
			var d := M.decode_chunk(r.body, info)
			if bool(d.ok):
				j.mutex.lock()
				j.good = bi
				j.mutex.unlock()
				return d
			if str(d.error) == "verschluesselt":
				return d
			corrupt = true
			last = str(d.error)
			# Verfälscht: beim nächsten Versuch ein anderer Server, falls es einen gibt.
			if n > 1 and bad.size() < n - 1:
				bi = (bi + 1) % n
		elif str(r.get("error", "")) == "stop":
			return { "ok": false, "error": "stop" }
		else:
			last = "nicht_erreichbar" if int(r.code) == 0 else "server"
			bad[bi] = true
			if bad.size() >= n:
				bad.clear()
			bi = (bi + 1) % n
			continue
		OS.delay_msec(200 * (attempt + 1))
	return { "ok": false, "error": "pruefsumme" if corrupt else last }


## GET im Faden mit eigener, wiederverwendeter Verbindung (keine Weiterleitungen, Größengrenze,
## Zeitgrenzen, abbrechbar). Hat der Server eine alte Verbindung inzwischen geschlossen, gleich
## einmal mit einer neuen. { code, body, error }.
func _http_get(j: Dictionary, conn: Dictionary, url: String, max_bytes: int) -> Dictionary:
	var reused: bool = conn.get("hc") is HTTPClient
	var r := _http_once(j, conn, url, max_bytes)
	if reused and int(r.code) == 0 and str(r.get("error", "")) == "":
		if conn.get("hc") is HTTPClient:
			(conn.hc as HTTPClient).close()
		conn.erase("hc")
		r = _http_once(j, conn, url, max_bytes)
	# Server ohne Keep-Alive: die Verbindung nicht für die nächste Anfrage aufheben.
	if conn.get("hc") is HTTPClient and (conn.hc as HTTPClient).get_status() != HTTPClient.STATUS_CONNECTED:
		(conn.hc as HTTPClient).close()
		conn.erase("hc")
	return r


func _http_once(j: Dictionary, conn: Dictionary, url: String, max_bytes: int) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url.substr(8 if tls else 7)
	var cut := rest.find("/")
	var hostport := rest.substr(0, cut)
	var path := rest.substr(cut)
	var host := hostport
	var port := 443 if tls else 80
	if hostport.contains(":"):
		host = hostport.get_slice(":", 0)
		port = hostport.get_slice(":", 1).to_int()
	var key := "%s|%s|%d" % [tls, host, port]
	var hc: HTTPClient = conn.get("hc")
	if hc == null or str(conn.get("key", "")) != key or hc.get_status() != HTTPClient.STATUS_CONNECTED:
		if hc != null:
			hc.close()
		hc = HTTPClient.new()
		hc.read_chunk_size = 256 * 1024
		conn.hc = hc
		conn.key = key
		if hc.connect_to_host(host, port, TLSOptions.client() if tls else null) != OK:
			return { "code": 0, "body": PackedByteArray() }
		var t0 := Time.get_ticks_msec()
		while hc.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
			hc.poll()
			if Time.get_ticks_msec() - t0 > 20000 or _aborted(j):
				hc.close()
				return { "code": 0, "body": PackedByteArray(), "error": "stop" if _aborted(j) else "" }
			OS.delay_msec(5)
		if hc.get_status() != HTTPClient.STATUS_CONNECTED:
			hc.close()
			return { "code": 0, "body": PackedByteArray() }
	if hc.request(HTTPClient.METHOD_GET, path, PackedStringArray(["User-Agent: " + Net.UA, "Accept-Encoding: identity"])) != OK:
		hc.close()
		return { "code": 0, "body": PackedByteArray() }
	var t1 := Time.get_ticks_msec()
	while hc.get_status() == HTTPClient.STATUS_REQUESTING:
		hc.poll()
		if Time.get_ticks_msec() - t1 > 30000 or _aborted(j):
			hc.close()
			return { "code": 0, "body": PackedByteArray(), "error": "stop" if _aborted(j) else "" }
		OS.delay_msec(2)
	if not (hc.get_status() in [HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]) or not hc.has_response():
		hc.close()
		return { "code": 0, "body": PackedByteArray() }
	var code := hc.get_response_code()
	if hc.get_response_body_length() > max_bytes:
		hc.close()
		return { "code": code, "body": PackedByteArray(), "error": "gross" }
	var body := PackedByteArray()
	var quiet := Time.get_ticks_msec()
	while hc.get_status() == HTTPClient.STATUS_BODY:
		hc.poll()
		var part := hc.read_response_body_chunk()
		if part.is_empty():
			if Time.get_ticks_msec() - quiet > 30000 or _aborted(j):
				hc.close()
				return { "code": 0, "body": PackedByteArray(), "error": "stop" if _aborted(j) else "" }
			OS.delay_msec(2)
			continue
		quiet = Time.get_ticks_msec()
		body.append_array(part)
		if body.size() > max_bytes:
			hc.close()
			return { "code": code, "body": PackedByteArray(), "error": "gross" }
	return { "code": code, "body": body }


## Einen Teil in die Zwischendatei schreiben (unter der Sperre des Auftrags).
static func _write_part(root: String, rel: String, at: int, data: PackedByteArray, from: int, len: int) -> String:
	var tmp := root.path_join(rel) + TEMP
	var f := FileAccess.open(tmp, FileAccess.READ_WRITE) if FileAccess.file_exists(tmp) else FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "schreiben"
	f.seek(at)
	f.store_buffer(data.slice(from, from + len))
	var err := f.get_error()
	f.close()
	return "" if err == OK else "schreiben"


## Fertige Zwischendatei prüfen (SHA-1 laut Manifest). Stimmt sie nicht, fliegt sie weg, und ihre
## Chunks gelten als offen – „Fortsetzen“ lädt sie neu.
func _finish_file(j: Dictionary, fi: int) -> String:
	var f: Dictionary = j.m.files[fi]
	var tmp := str(j.root).path_join(str(f.name)) + TEMP
	if not FileAccess.file_exists(tmp):
		var w := FileAccess.open(tmp, FileAccess.WRITE)
		if w == null:
			return "schreiben"
		w.close()
	if file_sha1(tmp) != str(f.sha) or FileAccess.get_size(tmp) != int(f.size):
		DirAccess.remove_absolute(tmp)
		j.mutex.lock()
		for part in f.parts:
			j.cdone[int(part[0])] = 0
		j.mutex.unlock()
		_log_t("%s: Datei %s: Prüfsumme falsch" % [j.app, f.name])
		return "pruefsumme_datei"
	j.mutex.lock()
	j.fdone[fi] = 1
	j.mutex.unlock()
	return ""


static func file_sha1(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA1)
	var n := f.get_length()
	while f.get_position() < n:
		h.update(f.get_buffer(1024 * 1024))
	f.close()
	return h.finish().hex_encode()


## Prüfen (im Faden): SHA-1 jeder Datei → { Name klein: SHA-1 } der heilen.
func _verify(j: Dictionary) -> Dictionary:
	var good := {}
	var links := {}
	for f in j.m.files:
		if _stopped(j):
			break
		var p := str(j.root).path_join(str(f.name))
		if not _is_link(str(j.root), str(f.name), links) and FileAccess.file_exists(p) and FileAccess.get_size(p) == int(f.size) and file_sha1(p) == str(f.sha):
			good[str(f.name).to_lower()] = str(f.sha)
		j.mutex.lock()
		j.got = int(j.got) + int(f.size)
		j.mutex.unlock()
	j.mutex.lock()
	j.got = 0
	j.mutex.unlock()
	return good


## Zum Schluss (im Faden): Zwischendateien an ihren Platz, beim Update weggefallene Dateien löschen.
func _switch(j: Dictionary) -> String:
	var root := str(j.root)
	var links := {}
	for fi in j.plan.files:
		if j.fdone[fi] != 1:
			return "kaputt"
	for fi in j.plan.files:
		var final := root.path_join(str(j.m.files[fi].name))
		if not FileAccess.file_exists(final + TEMP):
			continue
		if _is_link(root, str(j.m.files[fi].name), links) or _is_link(root, str(j.m.files[fi].name) + TEMP, links):
			return "pfad"
		if FileAccess.file_exists(final) and DirAccess.remove_absolute(final) != OK:
			return "schreiben"
		if DirAccess.rename_absolute(final + TEMP, final) != OK:
			return "schreiben"
	for rel in j.plan.remove:
		var safe := M.safe_path(str(rel))
		if safe != "" and not _is_link(root, safe, links) and FileAccess.file_exists(root.path_join(safe)):
			DirAccess.remove_absolute(root.path_join(safe))
	return ""


## Abbrechen/Deinstallieren (im Faden): Zwischendateien weg; bei kind „install“ bzw. „uninstall“
## auch die Dateien laut Manifest und danach leere Ordner (nie durch Verknüpfungen).
static func _cleanup(j: Dictionary) -> void:
	var root := str(j.root)
	if root == "" or not DirAccess.dir_exists_absolute(root):
		return
	var all := str(j.kind) in ["install", "uninstall"]
	var dirs := {}
	var links := {}
	for f in (j.m.get("files", []) as Array):
		var rel := M.safe_path(str(f.name))
		if rel == "" or _is_link(root, rel, links):
			continue
		var p := root.path_join(rel)
		if FileAccess.file_exists(p + TEMP) or _is_link(root, rel + TEMP, links):
			DirAccess.remove_absolute(p + TEMP)
		if all and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		var d := rel.get_base_dir()
		while d != "":
			dirs[d] = true
			d = d.get_base_dir()
	if not all:
		return
	var list: Array = dirs.keys()
	list.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for d in list:
		var p := root.path_join(str(d))
		if not _is_link(root, str(d), {}) and DirAccess.get_files_at(p).is_empty() and DirAccess.get_directories_at(p).is_empty():
			DirAccess.remove_absolute(p)
	if DirAccess.get_files_at(root).is_empty() and DirAccess.get_directories_at(root).is_empty():
		DirAccess.remove_absolute(root)


# --- Deinstallieren --------------------------------------------------------------------------

## Ein von Uzai installiertes Spiel entfernen: nur die Dateien laut Manifest im Spielordner, dann
## leere Ordner. "" = erledigt.
func uninstall(g: Dictionary) -> String:
	var app := str((g.get("epic", {}) as Dictionary).get("app", "")) if g.get("epic") is Dictionary else ""
	var recs := records()
	if not recs.has(app) or busy(app):
		return "Dieses Spiel hat Uzai nicht selbst installiert."
	var raw := FileAccess.get_file_as_bytes(dir_path().path_join(app + ".manifest"))
	var pr := M.parse(raw) if not raw.is_empty() else { "ok": false }
	if not bool(pr.ok):
		return "Uzais Dateiliste zu diesem Spiel fehlt – den Ordner bitte selbst löschen: %s" % str(recs[app].dir)
	var j := { "root": str(recs[app].dir), "kind": "uninstall", "m": pr.m }
	await _threaded(func() -> void: _cleanup(j))
	recs.erase(app)
	_save_records(recs)
	DirAccess.remove_absolute(dir_path().path_join(app + ".manifest"))
	jobs.erase(app)
	_log("%s: deinstalliert" % app)
	return ""


# --- Ordner ----------------------------------------------------------------------------------

## Taugt der gewählte Ordner? "" = ja. Nicht in Windows- und Programmordnern (die bräuchten
## Adminrechte), muss es geben und beschreibbar sein.
static func base_problem(base: String) -> String:
	var b := base.replace("\\", "/").trim_suffix("/")
	if b == "" or not DirAccess.dir_exists_absolute(b):
		return "Den Ordner gibt es nicht (mehr). Einen anderen Ordner wählen."
	var low := b.to_lower() + "/"
	for env in ["WINDIR", "ProgramFiles", "ProgramFiles(x86)", "ProgramData"]:
		var v := OS.get_environment(env).replace("\\", "/").trim_suffix("/").to_lower()
		if v != "" and low.begins_with(v + "/"):
			return "In diesen Ordner darf nur Windows mit Adminrechten schreiben. Einen anderen Ordner wählen, z. B. D:\\Spiele."
	var probe := b.path_join(".uzai-probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return "In diesen Ordner kann Uzai nicht schreiben. Einen anderen Ordner wählen."
	f.close()
	DirAccess.remove_absolute(probe)
	return ""


## Spielordner im gewählten Ordner: Name des Spiels; gehört der Name schon etwas anderem, mit Zahl.
static func _root_for(base: String, title: String, app: String, rec: Dictionary) -> String:
	if not rec.is_empty() and str(rec.get("dir", "")).get_base_dir() == base.trim_suffix("/"):
		return str(rec.dir)
	var name := P.install_dir_name(title)
	if name == "":
		name = app
	var b := base.replace("\\", "/").trim_suffix("/")
	var saved: Variant = Config.read_json(dir_path().path_join(app + ".job.json"), {})
	for i in 20:
		var cand := b.path_join(name if i == 0 else "%s (%d)" % [name, i + 1])
		if saved is Dictionary and str(saved.get("root", "")) == cand:
			return cand
		if not DirAccess.dir_exists_absolute(cand) and not FileAccess.file_exists(cand):
			return cand
		if DirAccess.get_files_at(cand).is_empty() and DirAccess.get_directories_at(cand).is_empty():
			return cand
	return ""


# --- Stand sichern ---------------------------------------------------------------------------

func _save_job(j: Dictionary) -> void:
	if not j.has("cdone"):
		return
	j.mutex.lock()
	var c := PackedByteArray(j.cdone)
	var f := PackedByteArray(j.fdone)
	j.mutex.unlock()
	var dp := dir_path()
	DirAccess.make_dir_recursive_absolute(dp)
	var mp := dp.path_join(str(j.app) + ".job.manifest")
	if not FileAccess.file_exists(mp) or str(Fremd.verz(Config.read_json(dp.path_join(str(j.app) + ".job.json"), {})).get("hash", "")) != str(j.hash):
		var w := FileAccess.open(mp, FileAccess.WRITE)
		if w:
			w.store_buffer(j.raw)
			w.close()
	Config.write_json(dp.path_join(str(j.app) + ".job.json"), { "v": 1, "app": str(j.app), "kind": str(j.kind), "root": str(j.root),
		"hash": str(j.hash), "cdone": _pack(c), "fdone": _pack(f) })


func _load_job(app: String) -> Dictionary:
	if not _app_ok(app):
		return {}
	var d: Variant = Config.read_json(dir_path().path_join(app + ".job.json"), {})
	if not (d is Dictionary) or str(d.get("app", "")) != app or str(d.get("root", "")) == "":
		return {}
	return d


func _drop_job(app: String) -> void:
	for suf in [".job.json", ".job.manifest", ".job.json.bak"]:
		var p := dir_path().path_join(app + str(suf))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _pack(mask: PackedByteArray) -> String:
	return "%d:%s" % [mask.size(), Marshalls.raw_to_base64(mask.compress(FileAccess.COMPRESSION_DEFLATE))] if not mask.is_empty() else "0:"


## Gesicherte Maske lesen; passt sie nicht zur Größe, fängt Uzai neu an (alles offen).
static func _mask(s: String, n: int) -> Array:
	var out: Array = []
	out.resize(n)
	out.fill(0)
	if s == "" or not s.contains(":") or s.get_slice(":", 0).to_int() != n or n == 0:
		return out
	var b64 := s.get_slice(":", 1)
	if RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$").search(b64) == null:
		return out
	var raw := Marshalls.base64_to_raw(b64)
	var m := raw.decompress(n, FileAccess.COMPRESSION_DEFLATE) if not raw.is_empty() else PackedByteArray()
	if m.size() != n:
		return out
	for i in n:
		out[i] = 1 if m[i] == 1 else 0
	return out


func _finish_record(j: Dictionary) -> void:
	var dp := dir_path()
	DirAccess.make_dir_recursive_absolute(dp)
	var w := FileAccess.open(dp.path_join(str(j.app) + ".manifest"), FileAccess.WRITE)
	if w:
		w.store_buffer(j.raw)
		w.close()
	var recs := records()
	var m: Dictionary = j.m
	recs[str(j.app)] = { "dir": str(j.root), "exe": str(m.get("exe", "")), "args": str(m.get("args", "")).left(2048), "build": str(j.build).left(256),
		"hash": str(j.hash), "ns": str(j.ns), "item": str(j.item), "title": str(j.title), "size": int(m.get("total", 0)),
		"account": str(Config.get_value("accounts.epic_account_id", "")), "at": int(Time.get_unix_time_from_system()),
		"prereq": str(m.get("prereq_name", "")).left(256) }
	_save_records(recs)
	_drop_job(str(j.app))
	var id := str(j.id)
	if not Library.get_game(id).is_empty():
		Library.set_field(id, "install_dir", str(j.root))
		Library.set_field(id, "path", str(j.root).path_join(str(m.get("exe", ""))) if str(m.get("exe", "")) != "" else "")
		Library.set_field(id, "epic_uzai", true)
		Library.set_field(id, "installed", true)


# --- Hilfen ----------------------------------------------------------------------------------

func _phase(j: Dictionary, phase: String, text: String) -> void:
	j.mutex.lock()
	j.phase = phase
	j.text = text
	j.mutex.unlock()
	if phase in ["done", "failed", "cancelled", "paused"]:
		_log("%s: %s – %s" % [j.app, phase, text])


## Längere Arbeit (Lesen, Prüfen, Aufräumen) in einem eigenen Faden; der Hauptfaden wartet ohne
## zu ruckeln.
func _threaded(work: Callable) -> void:
	var t := Thread.new()
	t.start(work)
	while t.is_alive():
		await get_tree().process_frame
	t.wait_to_finish()


static func _loopback() -> bool:
	return Config.probe_env("UZAI_TEST_LOOPBACK") == "1"


## Epics Dienst für die Manifest-Adressen; UZAI_EPIC_API lenkt ihn für Netz-Proben um (…/launcher).
static func _host() -> String:
	var t := Config.probe_env("UZAI_EPIC_API").trim_suffix("/")
	return t + "/launcher" if t != "" else LAUNCHER_HOST


static func _error_text(code: String) -> String:
	match code:
		"anmeldung": return "Die Anmeldung bei Epic fehlt oder ist abgelaufen. Einstellungen → Konten → Epic Games: neu anmelden."
		"nicht_erreichbar": return "Epic ist gerade nicht erreichbar. Internetverbindung prüfen, dann „Fortsetzen“."
		"kein_download": return "Epic gibt für dieses Spiel keinen Download heraus (nicht für Windows oder nicht in deiner Bibliothek). Im Epic Games Launcher installieren."
		"server": return "Epics Download-Server antworten gerade nicht. Später „Fortsetzen“."
		"manifest": return "Die Dateiliste von Epic kam nicht oder nicht unversehrt an. Später nochmal versuchen."
		"verschluesselt": return "Dieses Spiel liegt bei Epic verschlüsselt (Vorab-Download). Das geht nur im Epic Games Launcher."
		"pruefsumme": return "Ein Teil kam wiederholt nicht unversehrt an (Prüfsumme falsch) – nichts Kaputtes wurde übernommen. Später „Fortsetzen“."
		"pruefsumme_datei": return "Eine Datei stimmte nach dem Laden nicht (Prüfsumme). „Fortsetzen“ lädt sie neu."
		"schreiben": return "Uzai kann im Spielordner nicht schreiben. Ist das Laufwerk voll oder schreibgeschützt? Einen anderen Ordner wählen."
		"pfad", "verknuepfung", "doppelt": return "Epics Dateiliste enthält unsichere Pfade – aus Sicherheitsgründen installiert Uzai das nicht. Im Epic Games Launcher installieren."
		"adresse": return "Epic nannte keinen bekannten Download-Server – aus Sicherheitsgründen lädt Uzai nichts. Im Epic Games Launcher installieren."
		"grenze", "zu_gross": return "Epics Dateiliste ist größer als erlaubt – aus Sicherheitsgründen installiert Uzai das nicht. Im Epic Games Launcher installieren."
	return "Epics Dateiliste ließ sich nicht lesen. Im Epic Games Launcher installieren oder später nochmal versuchen."


func _log(text: String) -> void:
	Logdatei.zeile(Config.path("logs/installs.log"), "Epic (Uzai): " + text, 256 * 1024)


## Aus einem Faden: das Protokoll schreibt der Hauptfaden.
func _log_t(text: String) -> void:
	call_deferred("_log", text)
