extends RefCounted
## Remote Play Together für jedes Spiel, das Uzai startet – auch Emulator-Spiele.
##
## Steam bietet Remote Play Together nur in Steam-Spielen an, die es können. Uzai leiht sich dafür
## ein „Spender“-Spiel aus deiner Steam-Bibliothek (z. B. das kostenlose RetroArch): Dessen
## Programmdatei wird gesichert (*.uzai-original.exe) und durch einen kleinen Starter ersetzt.
## Uzai schreibt einen Auftrag (Programm, Parameter, Ordner) neben den Starter und lässt Steam den
## Spender starten. Der Starter startet das eigentliche Spiel und wartet, bis es endet; Steam hält
## alles für den Spender – mit Overlay und Remote Play Together. Startet jemand den Spender selbst
## in Steam (ohne Auftrag), startet der Starter das gesicherte Original.
## Einladen geht über die offizielle Steamworks-Schnittstelle (ISteamRemotePlay) im Helfer.
## Alles hier ist statisch; der Zustand liegt in Config („remoteplay.*“) und in den Dateien.

const Main := preload("res://src/main.gd")

const STARTER_VERSION := "3"
const JOB_FILE := "uzai-remoteplay-auftrag.txt"
const STATUS_FILE := "uzai-remoteplay-status.txt"
const LOG_FILE := "uzai-remoteplay.log"
const SUFFIX := ".uzai-original.exe"
const RETROARCH_APPID := 1118310
const APPINFO_MAX := 8 * 1024 * 1024   ## so groß darf der Eintrag eines Spiels in Steams appinfo.vdf sein
## Dateien, die nie das Hauptprogramm eines Spiels sind (Installer, Absturzmelder, Laufzeiten).
const SKIP_EXE := ["unins", "setup", "install", "redist", "vcredist", "vc_redist", "dxsetup", "dotnet", "directx",
	"crashhandler", "crashreport", "crashpad", "unitycrashhandler", "errorreporter", "bugreport", "easyanticheat",
	"battleye", "be_service", "eac_", "launcherhelper", "cefsharp", "helper", "updater", "update", "touchup",
	"steamworks", "notification_helper", "quicksfv", "dxwebsetup", "oalinst", "physx"]
const SKIP_DIRS := ["_commonredist", "commonredist", "redist", "redistributables", "directx", "vcredist", "dotnet",
	"easyanticheat", "battleye", "__installer", "installer", "support", "tools"]


# --- Einstellungen ---------------------------------------------------------------------------

static func donor() -> Dictionary:
	return {
		"appid": int(Config.get_value("remoteplay.donor_appid", 0)),
		"exe": str(Config.get_value("remoteplay.donor_exe", "")),
		"title": str(Config.get_value("remoteplay.donor_title", "")),
		"id": str(Config.get_value("remoteplay.donor_id", "")),
	}


static func configured() -> bool:
	var d := donor()
	return int(d.appid) > 0 and str(d.exe) != ""


static func donor_title() -> String:
	var t := str(donor().title)
	return t if t != "" else "dem Spender"


## Soll Uzai dieses Spiel über den Spender starten?
static func wants(g: Dictionary) -> bool:
	return wants_for(g, bool(Config.get_value("remoteplay.emulators", false)), configured(), bool(Config.get_value("remoteplay.pc", false)))


## Rein: _rp kommt von „Mit Remote Play Together starten“. Steam-Spiele und Internet-Verknüpfungen
## startet Uzai nie über den Spender (Steam-Spiele können es selbst); Epic-Spiele nur auf
## ausdrücklichen Wunsch (geht nur ohne Epic-Kopierschutz). „Immer“ gibt es für Emulator- und PC-Spiele.
static func wants_for(g: Dictionary, emulators_always: bool, ready: bool, pc_always := false) -> bool:
	var src := str(g.get("source", "rom"))
	if src == "steam" or str(g.get("url", "")) != "":
		return false
	if bool(g.get("_rp", false)):
		return true
	if not ready:
		return false
	return (emulators_always and src == "rom") or (pc_always and src == "pc")


## Lässt sich dieses Spiel überhaupt über den Spender starten (für die Spieloptionen)?
static func possible_for(g: Dictionary) -> bool:
	var src := str(g.get("source", "rom"))
	return src in ["rom", "pc", "epic"] and str(g.get("url", "")) == ""


# --- Spieler 2 und Adminrechte (rein, für Launcher und Tests) ----------------------------------

## Was hat sich bei den Controllern getan? base: Anzahl beim Start, prev: zuletzt, now: jetzt
## (-1 = unbekannt). "verbunden", "getrennt" oder "".
static func pad_change(base: int, prev: int, now: int) -> String:
	if base < 0 or prev < 0 or now < 0 or now == prev:
		return ""
	if now > prev and now > base:
		return "verbunden"
	if now < prev and prev > base:
		return "getrennt"
	return ""


## Hinweis, wenn nach einer Einladung kein zweiter Controller kommt (einmal, nach 90 s).
static func pad_hint_due(invited_at: int, now_s: int, base: int, cur: int, shown: bool) -> bool:
	if shown or invited_at <= 0 or base < 0 or cur < 0:
		return false
	return cur <= base and now_s - invited_at >= 90


## Rein: Startet Steam das Spiel überhaupt? Verlangt es Adminrechte und Steam hat keine, kann der
## Starter es nicht starten (Windows fragt dann nach, und Steam käme an das Fenster nicht heran).
## why: "manifest" (steht in der Programmdatei) oder "kompat" (Eigenschaften → Kompatibilität).
static func admin_problem(name: String, why: String, steam_elevated: bool) -> String:
	if why == "" or steam_elevated:
		return ""
	if why == "kompat":
		return "%s ist auf „Als Administrator ausführen“ gestellt. Steam läuft ohne Adminrechte und kann es so nicht für Remote Play starten. Abhilfe: Rechtsklick auf die Programmdatei → Eigenschaften → Kompatibilität → Haken bei „Programm als Administrator ausführen“ entfernen." % name
	return "%s verlangt Administratorrechte. Remote Play geht dann nur, wenn auch Steam als Administrator läuft (Steam beenden, Rechtsklick → „Als Administrator ausführen“)." % name


static func admin_check(exe: String) -> String:
	if not Config.is_windows() or not Helper.available:
		return ""
	var r := await Helper.run("rp-check", { "exe": _win(exe) }, 8.0)
	if not r.ok or not (r.result is Dictionary):
		return ""
	var why := "manifest" if bool(r.result.get("manifest_admin", false)) else ("kompat" if bool(r.result.get("compat_admin", false)) else "")
	return admin_problem(exe.get_file(), why, bool(r.result.get("steam_elevated", false)))


# --- Dateien im Ordner des Spenders ----------------------------------------------------------

static func original_path(exe: String) -> String:
	return exe.get_base_dir().path_join(exe.get_file().get_basename() + SUFFIX)


static func starter_path() -> String:
	return Config.path("remoteplay/uzai-starter-%s.exe" % STARTER_VERSION)


## Rein: Zustand aus drei Beobachtungen.
## bereit – Starter liegt da, Original gesichert · nicht_eingerichtet – nur das Original ·
## ueberschrieben – Steam hat die Datei ersetzt (Update, Dateiprüfung) · starter_fehlt – nur die
## Sicherung · ohne_original – Starter ohne Sicherung · fehlt – gar nichts (Spiel deinstalliert?)
static func state_of(exe_exists: bool, backup_exists: bool, exe_is_starter: bool) -> String:
	if exe_exists and exe_is_starter:
		return "bereit" if backup_exists else "ohne_original"
	if exe_exists:
		return "ueberschrieben" if backup_exists else "nicht_eingerichtet"
	return "starter_fehlt" if backup_exists else "fehlt"


static func same_file(a: String, b: String) -> bool:
	if not FileAccess.file_exists(a) or not FileAccess.file_exists(b):
		return false
	if _size(a) != _size(b):
		return false
	return FileAccess.get_md5(a) == FileAccess.get_md5(b)


static func _size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f else -1


## Ist das ein Starter von Uzai (egal welcher Version)? Der Name der Klasse steht in der Datei.
## Wichtig nach einem Uzai-Update: ein alter Starter darf nie für das Original gehalten werden.
static func is_starter(p: String) -> bool:
	var n := _size(p)
	if n <= 0 or n > 4 * 1024 * 1024:
		return false
	return bytes_contain(FileAccess.get_file_as_bytes(p), "UzaiStarter".to_ascii_buffer())


static func bytes_contain(hay: PackedByteArray, needle: PackedByteArray) -> bool:
	if needle.is_empty():
		return true
	var first := needle[0]
	var i := hay.find(first)
	while i >= 0 and i + needle.size() <= hay.size():
		if hay.slice(i, i + needle.size()) == needle:
			return true
		i = hay.find(first, i + 1)
	return false


static func state(exe: String, starter: String) -> String:
	return state_of(FileAccess.file_exists(exe), FileAccess.file_exists(original_path(exe)), is_starter(exe) or same_file(exe, starter))


## Starter an die Stelle der Programmdatei legen: richtet ein und repariert still, wenn Steam die
## Datei ersetzt hat (dann ist die neue Datei das aktuelle Original und wird zur Sicherung).
## Rückgabe: "" oder ein Hinweis.
static func place(exe: String, starter: String) -> String:
	if not FileAccess.file_exists(starter):
		return "Der Starter fehlt."
	var backup := original_path(exe)
	match state(exe, starter):
		"bereit", "ohne_original":
			if same_file(exe, starter):
				return ""
			# Starter aus einer älteren Uzai-Version: nur austauschen, die Sicherung bleibt.
		"fehlt":
			return "Die Programmdatei des Spenders wurde nicht gefunden:\n%s" % exe
		"nicht_eingerichtet", "ueberschrieben":
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
				return "Die alte Sicherung ließ sich nicht ersetzen. Läuft der Spender gerade?"
			if DirAccess.rename_absolute(exe, backup) != OK:
				return "Die Programmdatei ließ sich nicht sichern. Läuft der Spender gerade, oder fehlt das Schreibrecht im Steam-Ordner?"
	if DirAccess.copy_absolute(starter, exe) != OK:
		# Nichts kaputt zurücklassen: Original wieder an seinen Platz.
		if not FileAccess.file_exists(exe) and FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, exe)
		return "Der Starter ließ sich nicht in den Ordner des Spenders legen."
	return ""


## Original wiederherstellen. Hat Steam die Datei inzwischen selbst ersetzt, ist sie schon das
## Original; dann fällt nur die alte Sicherung weg.
static func restore(exe: String, starter: String) -> String:
	var backup := original_path(exe)
	match state(exe, starter):
		"bereit", "starter_fehlt":
			if FileAccess.file_exists(exe) and DirAccess.remove_absolute(exe) != OK:
				return "Der Starter ließ sich nicht entfernen. Läuft der Spender gerade?"
			if DirAccess.rename_absolute(backup, exe) != OK:
				return "Das Original ließ sich nicht zurücklegen."
		"ueberschrieben":
			DirAccess.remove_absolute(backup)
		"ohne_original":
			return "Die Sicherung des Originals fehlt. In Steam unter Eigenschaften → Installierte Dateien → „Dateien auf Fehler prüfen“ holt Steam es zurück."
	for f in [JOB_FILE, STATUS_FILE, LOG_FILE]:
		var p := exe.get_base_dir().path_join(f)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	return ""


## Den Starter bauen (einmal je Starter-Version; unter Windows über den Helfer mit Add-Type).
static func build_starter() -> String:
	var path := starter_path()
	if FileAccess.file_exists(path):
		return ""
	if not Config.is_windows():
		return "Der Starter lässt sich nur unter Windows bauen."
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var r := await Helper.run_once("remoteplay-build", { "out": _win(path) })
	if r.ok and r.result is Dictionary and bool(r.result.get("ok", false)) and FileAccess.file_exists(path):
		return ""
	var why := str(r.get("error", ""))
	if r.result is Dictionary and str(r.result.get("reason", "")) != "":
		why = str(r.result.reason)
	return "Der Starter ließ sich nicht bauen%s." % ((": " + why) if why != "" else "")


## Vor jedem Start: Starter da? Steam-Updates und die Dateiprüfung ersetzen ihn – dann still neu.
static func ensure_ready() -> String:
	if not configured():
		return "Remote Play Together ist noch nicht eingerichtet: Einstellungen → System → Remote Play Together."
	var err := await build_starter()
	if err != "":
		return err
	return place(str(donor().exe), starter_path())


## Spender einrichten: Starter bauen, alten Spender zurücksetzen, Datei ersetzen, merken.
static func install(g: Dictionary, exe: String) -> String:
	var err := await build_starter()
	if err != "":
		return err
	var old := donor()
	if str(old.exe) != "" and str(old.exe) != exe:
		restore(str(old.exe), starter_path())
	err = place(exe, starter_path())
	if err != "":
		return err
	Config.set_value("remoteplay.donor_appid", int(g.get("appid", 0)))
	Config.set_value("remoteplay.donor_exe", exe)
	Config.set_value("remoteplay.donor_title", str(g.get("title", "")))
	Config.set_value("remoteplay.donor_id", str(g.get("id", "")))
	return ""


static func uninstall() -> String:
	var d := donor()
	var err := ""
	if str(d.exe) != "":
		err = restore(str(d.exe), starter_path())
	if err == "":
		for k in ["donor_appid", "donor_exe", "donor_title", "donor_id"]:
			Config.set_value("remoteplay." + k, 0 if k == "donor_appid" else "")
	return err


## Zustand für die Einstellungen: [Text, Ton].
static func status_text() -> Array:
	if not configured():
		return ["Nicht eingerichtet", "faint"]
	var exe := str(donor().exe)
	if not FileAccess.file_exists(starter_path()):
		return ["Starter wird beim ersten Start gebaut", "faint"] if FileAccess.file_exists(original_path(exe)) else ["Fehlt", "warn"]
	match state(exe, starter_path()):
		"bereit": return ["Bereit", "ok"]
		"ohne_original": return ["Bereit, Original fehlt", "warn"]
		"ueberschrieben", "starter_fehlt": return ["Steam hat ihn ersetzt – Uzai legt ihn beim Start neu an", "faint"]
	return ["Spender nicht gefunden", "warn"]


# --- Auftrag und Rückmeldung -----------------------------------------------------------------

## Rein: Auftragsdatei für den Starter. Zeilen „schlüssel=wert“, env darf mehrfach vorkommen.
static func job_text(id: String, zeit: int, cmd: Dictionary) -> String:
	var lines := PackedStringArray(["# Auftrag von Uzai für den Remote-Play-Starter", "id=" + id, "zeit=%d" % zeit])
	for k in ["exe", "dir", "args"]:
		lines.append("%s=%s" % [k, _one_line(str(cmd.get(k, "")))])
	var env: Dictionary = cmd.get("env", {}) if cmd.get("env") is Dictionary else {}
	for k in env.keys():
		if str(k) != "" and not str(k).contains("="):
			lines.append("env=%s=%s" % [str(k), _one_line(str(env[k]))])
	return "\r\n".join(lines) + "\r\n"


## Rein: liest Auftrag und Status (wie ParseKv im Starter). env landet als Liste unter "env".
static func parse_kv(text: String) -> Dictionary:
	var out := { "env": [] }
	for raw in text.trim_prefix("﻿").split("\n"):
		var line := raw.trim_suffix("\r")
		if line == "" or line.begins_with("#"):
			continue
		var i := line.find("=")
		if i <= 0:
			continue
		var k := line.substr(0, i).strip_edges()
		var v := line.substr(i + 1)
		if k == "env":
			(out.env as Array).append(v)
		else:
			out[k] = v
	return out


static func _one_line(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ")


static func job_dir() -> String:
	return str(donor().exe).get_base_dir()


static func write_job(cmd: Dictionary) -> String:
	var id := "%d%04d" % [Time.get_ticks_msec() % 100000000, randi() % 10000]
	var dir := job_dir()
	var st := dir.path_join(STATUS_FILE)
	if FileAccess.file_exists(st):
		DirAccess.remove_absolute(st)
	var f := FileAccess.open(dir.path_join(JOB_FILE), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(job_text(id, int(Time.get_unix_time_from_system()), cmd))
	f.close()
	return id


static func clear_job() -> void:
	var p := job_dir().path_join(JOB_FILE)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


## Rückmeldung des Starters zu genau diesem Auftrag ({} solange keine da ist).
static func read_status(id: String) -> Dictionary:
	var p := job_dir().path_join(STATUS_FILE)
	if id == "" or not FileAccess.file_exists(p):
		return {}
	var st := parse_kv(FileAccess.get_file_as_string(p))
	return st if str(st.get("id", "")) == id else {}


# --- Hauptprogramm des Spenders erkennen ------------------------------------------------------

## Alle .exe im Ordner (bis zwei Ebenen tief) mit Größe: [{ rel, size }].
static func list_exes(dir: String, depth := 2, prefix := "") -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.get_extension().to_lower() == "exe":
			var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
			out.append({ "rel": prefix + f, "size": fa.get_length() if fa else 0 })
	if depth > 0:
		for sub in da.get_directories():
			if sub.to_lower() in SKIP_DIRS:
				continue
			out.append_array(list_exes(dir.path_join(sub), depth - 1, prefix + sub + "/"))
	return out


static func _skip(rel: String) -> bool:
	var low := rel.to_lower()
	if low.ends_with(SUFFIX):
		return true
	for d in low.split("/").slice(0, -1):
		if d in SKIP_DIRS:
			return true
	var name := low.get_file()
	for w in SKIP_EXE:
		if name.contains(w):
			return true
	return false


static func _key(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## Rein: Welche Datei startet Steam? 1. schon eingerichtet (es gibt eine Sicherung), 2. laut
## Steam (appinfo), 3. die einzige, 4. die, deren Name zum Spiel passt, 5. sonst die größte –
## dann mit sure = false, und Uzai lässt wählen. Rückgabe: { rel, sure, candidates }.
static func pick_main_exe(files: Array, appinfo: Array, title: String) -> Dictionary:
	var have := {}
	for f in files:
		have[str(f.rel).to_lower()] = f
	for f in files:
		var r := str(f.rel)
		if r.to_lower().ends_with(SUFFIX):
			var main := r.substr(0, r.length() - SUFFIX.length()) + ".exe"
			return { "rel": main, "sure": true, "candidates": [main] }
	var cands: Array = files.filter(func(f): return not _skip(str(f.rel)))
	cands.sort_custom(func(a, b): return int(a["size"]) > int(b["size"]))
	var names: Array = cands.map(func(f): return str(f.rel))
	for e in appinfo:
		var rel := str(e).replace("\\", "/").trim_prefix("./").trim_prefix("/")
		if have.has(rel.to_lower()) and not _skip(rel):
			return { "rel": str(have[rel.to_lower()].rel), "sure": true, "candidates": names }
	if cands.is_empty():
		return { "rel": "", "sure": false, "candidates": [] }
	if cands.size() == 1:
		return { "rel": names[0], "sure": true, "candidates": names }
	var tk := _key(title)
	if tk != "":
		# Erst genau gleich, dann „fängt so an“ (retroarch vor retroarch_angle).
		for exact in [true, false]:
			for f in cands:
				var nk := _key(str(f.rel).get_file().get_basename())
				if nk == "":
					continue
				if (exact and nk == tk) or (not exact and nk.length() >= 4 and (tk.begins_with(nk) or nk.begins_with(tk))):
					return { "rel": str(f.rel), "sure": true, "candidates": names }
	return { "rel": names[0], "sure": false, "candidates": names }


## Rein: .exe-Angaben aus dem Eintrag eines Spiels in Steams appinfo.vdf (Startoptionen, in der
## Reihenfolge, in der Steam sie führt). Werte stehen dort als Text mit 0-Byte am Ende.
static func exes_in_blob(blob: PackedByteArray) -> Array:
	var out: Array = []
	var start := 0
	for i in blob.size():
		if blob[i] != 0:
			continue
		if i - start >= 5:
			var s := blob.slice(start, i)
			# Bis zum letzten Steuerzeichen abschneiden (Typ-Byte, Schlüsselnummer davor).
			var cut := 0
			for j in s.size():
				if s[j] < 32:
					cut = j + 1
			var text := s.slice(cut).get_string_from_utf8()
			if text.to_lower().ends_with(".exe") and not out.has(text):
				out.append(text)
		start = i + 1
	return out


## Den Eintrag einer App aus appinfo.vdf (Versionen 27, 28, 29). Leer, wenn nicht lesbar.
static func appinfo_entry(path: String, appid: int) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 16:
		return PackedByteArray()
	var magic := f.get_32()
	f.get_32()   # Universum
	if magic == 0x07564429:
		f.get_64()   # Lage der Schlüsseltabelle
	elif magic != 0x07564428 and magic != 0x07564427:
		return PackedByteArray()
	while f.get_position() + 8 <= f.get_length():
		var id := f.get_32()
		if id == 0:
			break
		var size := f.get_32()
		# Die Größe steht in der Datei: nie mehr anfordern, als noch da ist (eine beschädigte Datei verlangte sonst
		# bis zu 4 GB Speicher), und kein Eintrag ist größer als APPINFO_MAX.
		if size > f.get_length() - f.get_position():
			break
		if id == appid:
			return f.get_buffer(size) if size <= APPINFO_MAX else PackedByteArray()
		f.seek(f.get_position() + size)
	return PackedByteArray()


static func appinfo_exes(appid: int) -> Array:
	var root := Library.steam_root()
	if root == "" or appid <= 0:
		return []
	return exes_in_blob(appinfo_entry(root.path_join("appcache/appinfo.vdf"), appid))


## Für die Einrichtung: { exe (voller Pfad), sure, candidates (volle Pfade), error }.
static func detect_exe(g: Dictionary) -> Dictionary:
	var dir := str(g.get("install_dir", ""))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return { "error": "Der Ordner von %s wurde nicht gefunden." % g.get("title", "diesem Spiel") }
	var pick := pick_main_exe(list_exes(dir), appinfo_exes(int(g.get("appid", 0))), str(g.get("title", "")))
	if str(pick.rel) == "":
		return { "error": "Im Ordner von %s liegt keine Programmdatei." % g.get("title", "diesem Spiel") }
	return { "exe": dir.path_join(str(pick.rel)), "sure": bool(pick.sure),
		"candidates": (pick.candidates as Array).map(func(r): return dir.path_join(str(r))), "error": "" }


# --- Einrichten (Einstellungen) --------------------------------------------------------------

## Installierte Steam-Spiele als Spender, RetroArch (kostenlos) zuerst.
static func donor_candidates() -> Array:
	var list: Array = Library.games.filter(func(g): return str(g.get("source", "")) == "steam" and bool(g.get("installed", true)) and int(g.get("appid", 0)) > 0)
	list.sort_custom(func(a, b):
		var ra := int(a.appid) == RETROARCH_APPID
		var rb := int(b.appid) == RETROARCH_APPID
		if ra != rb:
			return ra
		return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0
	)
	return list


## Spender wählen, Programmdatei erkennen (sonst fragen), einrichten. done() danach.
static func choose_donor(main: Main, done: Callable) -> void:
	var list := donor_candidates()
	if list.is_empty():
		Toasts.show_toast("Keine installierten Steam-Spiele", "Installiere ein Spiel mit Remote Play Together, z. B. RetroArch (kostenlos).", "steam", { "ms": 6000 })
		return
	var opts: Array = []
	for g in list:
		var t := Library.display_title(g)
		opts.append([str(g.id), t + ("  ·  kostenlos, empfohlen" if int(g.appid) == RETROARCH_APPID else "")])
	main.open_choice("Spender-Spiel wählen", opts, str(donor().id), func(v: Variant) -> void:
		var g := Library.get_game(str(v))
		if g.is_empty():
			return
		var det := detect_exe(g)
		if str(det.get("error", "")) != "":
			Toasts.show_toast("Einrichten ging nicht", str(det.error), "warning", { "ms": 6000 })
			return
		var cands: Array = det.candidates
		if bool(det.sure) or cands.size() <= 1:
			_install_with_toast(g, str(det.exe), done)
			return
		var eopts: Array = cands.map(func(p): return [str(p), str(p).trim_prefix(str(g.install_dir) + "/")])
		main.open_choice("Welche Datei startet Steam?", eopts, str(det.exe), func(p: Variant) -> void:
			_install_with_toast(g, str(p), done)
		, "Die größte steht oben. Meist heißt sie wie das Spiel.")
	, "Ein Steam-Spiel, das Remote Play Together kann. Uzai ersetzt seine Programmdatei durch einen Starter (mit Sicherung).")


static func _install_with_toast(g: Dictionary, exe: String, done: Callable) -> void:
	Toasts.show_toast("Remote Play wird eingerichtet …", Library.display_title(g), "steam", { "sub_raw": true, "ms": 2500, "quiet": true })
	var err := await install(g, exe)
	if err == "":
		Toasts.show_toast("Remote Play Together bereit", "%s ist jetzt der Spender (%s)." % [Library.display_title(g), exe.get_file()], "check",
				{ "sound": "select", "ms": 5000 })
	else:
		Toasts.show_toast("Einrichten ging nicht", err, "warning", { "ms": 7000 })
	if done.is_valid():
		done.call()


# --- Einladen ----------------------------------------------------------------------------------

## Kann Uzai gerade zu Remote Play Together einladen? Über den Spender oder im Steam-Spiel.
static func can_invite() -> bool:
	if not Launcher.in_game:
		return false
	return Launcher.remote_play or str(Launcher.current.get("source", "")) == "steam"


## Steamworks-Bibliothek für die Einladung: im Spender bzw. Spiel, sonst irgendeine aus einem
## installierten Steam-Spiel (die App-ID kommt aus der Umgebung, nicht aus der Datei).
static func steam_api_for(dir: String) -> String:
	if dir != "" and DirAccess.dir_exists_absolute(dir):
		var own := Launcher.find_steam_api({ "install_dir": dir })
		if own != "":
			return own
	var n := 0
	for g in Library.games:
		if str(g.get("source", "")) != "steam" or not bool(g.get("installed", true)):
			continue
		var d := str(g.get("install_dir", ""))
		if d == "" or d == dir or not DirAccess.dir_exists_absolute(d):
			continue
		var p := Launcher._find_file(d, ["steam_api64.dll"], 2)
		if p != "":
			return p
		n += 1
		if n > 40:
			break
	return ""


## Rückgabe: { ok, text }.
static func send_invite(friend_id: String) -> Dictionary:
	var t := _invite_target()
	if str(t.error) != "":
		return { "ok": false, "text": str(t.error) }
	var title := str(t.title)
	var r := await Helper.run_once("remoteplay-invite", { "dll": _win(str(t.dll)), "appid": str(t.appid), "friend": friend_id }, str(t.ps))
	if r.ok and r.result is Dictionary and bool(r.result.get("ok", false)):
		return { "ok": true, "text": "Die Einladung zu %s ist unterwegs. Dein Freund nimmt sie in Steam an und spielt dann mit dem eigenen Controller mit. Bleibt Steams Overlay offen: Guide → „Steam-Overlay“." % title }
	var why := str(r.result.get("reason", "")) if r.result is Dictionary else str(r.get("error", ""))
	return { "ok": false, "text": overlay_hint((why + ".") if why != "" else "Steam hat nicht geantwortet.") }


## Wohin die Einladung geht: App-ID (Spender oder Steam-Spiel), Steamworks-Bibliothek und das
## passende PowerShell (32 Bit für steam_api.dll). error ist gesetzt, wenn es nicht geht.
static func _invite_target() -> Dictionary:
	if not Config.is_windows():
		return { "error": "Remote Play Together geht nur unter Windows mit Steam." }
	var appid := 0
	var dir := ""
	if Launcher.remote_play:
		appid = int(donor().appid)
		dir = str(donor().exe).get_base_dir()
	else:
		appid = int(Launcher.current.get("appid", 0))
		dir = str(Launcher.current.get("install_dir", ""))
	var dll := steam_api_for(dir)
	if appid <= 0 or dll == "":
		return { "error": overlay_hint("Uzai hat keine Steamworks-Bibliothek gefunden.") }
	var ps := ""
	if dll.get_file().to_lower() == "steam_api.dll":
		ps = Helper.ps32_exe()
	return { "error": "", "appid": appid, "dll": dll, "ps": ps, "title": Library.display_title(Launcher.current) }


## Mehrere auf einmal (alle aus dem Discord-Call, siehe call_invite.gd): ein Helfer-Prozess,
## nacheinander mit kurzer Pause; wer schon in der Sitzung ist, bekommt keine Einladung.
## Rückgabe: { ok, text, joined: [Steam-IDs in der Sitzung], results: { Steam-ID: { ok, skipped, reason } } }.
static func send_invites(ids: Array) -> Dictionary:
	var out := { "ok": false, "text": "", "joined": [], "results": {} }
	var t := _invite_target()
	if str(t.error) != "":
		out.text = str(t.error)
		return out
	var r := await Helper.run_once("remoteplay-invite", { "dll": _win(str(t.dll)), "appid": str(t.appid),
		"friends": ",".join(PackedStringArray(ids.map(func(x): return str(x)))), "timeout": 20 + 2 * ids.size() }, str(t.ps))
	if not r.ok or not (r.result is Dictionary):
		out.text = overlay_hint((str(r.get("error", "")) + ".") if str(r.get("error", "")) != "" else "Steam hat nicht geantwortet.")
		return out
	var res: Dictionary = r.result
	out.ok = bool(res.get("ok", false))
	out.joined = (res.get("joined", []) as Array).map(func(x): return str(x)) if res.get("joined") is Array else []
	for e in (res.get("results", []) if res.get("results") is Array else []):
		if e is Dictionary:
			out.results[str(e.get("friend", ""))] = { "ok": bool(e.get("ok", false)), "skipped": str(e.get("skipped", "")), "reason": str(e.get("reason", "")) }
	if not out.ok:
		var why := str(res.get("reason", ""))
		out.text = overlay_hint((why + ".") if why != "" else "Steam hat die Einladungen nicht angenommen.")
	return out


## Rückfall: im Steam-Overlay einladen. Uzai holt dabei nichts nach vorn; das Overlay geht über
## den Guide („Steam-Overlay“) oder die Tasten auf, beides ohne Aufstehen.
static func overlay_hint(why: String) -> String:
	var keys := str(Config.get_value("system.steam_overlay_keys", "SHIFT+TAB")).replace("SHIFT", "Umschalt").replace("TAB", "Tab")
	return "%s Lade im Steam-Overlay ein: Guide → „Steam-Overlay“ (oder %s) → Freund → „Remote Play Together“." % [why, keys]


## Aus dem Guide: Einladung schicken und das Ergebnis als Mitteilung zeigen.
static func invite(f: Dictionary) -> void:
	var who := str(f.get("name", ""))
	Toasts.show_toast("Remote-Play-Einladung wird geschickt …", "an " + who, "steam", { "ms": 2000, "quiet": true })
	var r := await send_invite(str(f.get("id", "")))
	if bool(r.ok):
		Launcher.rp_invited(who)
		Toasts.show_toast("Zu Remote Play eingeladen: " + who, str(r.text), "check", { "sound": "select", "ms": 7000, "image": str(f.get("avatar", "")) })
	else:
		Toasts.show_toast("Einladen ging nicht", str(r.text), "warning", { "ms": 9000 })


static func _win(p: String) -> String:
	return p.replace("/", "\\") if OS.get_name() == "Windows" else p
