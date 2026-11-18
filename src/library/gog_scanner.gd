extends RefCounted
## Installierte Spiele von GOG (mit oder ohne GOG Galaxy). Uzai liest nur, was GOG selbst auf den
## PC legt – ohne Internet, ohne Konto, ohne etwas zu ändern:
##   - die Registry unter GOG.com\Games (schreiben Galaxy und die Offline-Installer; liest der Helfer),
##   - GOG Galaxys Datenbank ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db (installierte Spiele,
##     Titel, Spielzeit, zuletzt gespielt) mit Uzais kleinem SQLite-Leser,
##   - goggame-<ID>.info im Spielordner (Titel, Programmdatei, Startparameter).
## Gestartet wird wie über Galaxys eigene Verknüpfungen (GalaxyClient.exe /command=runGame …), ohne
## Galaxy die Programmdatei aus goggame-*.info – GOG-Spiele sind ohne Kopierschutz, so starten auch
## die Verknüpfungen der Offline-Installer.

const SU := preload("res://src/library/store_util.gd")
const Sql := preload("res://src/library/sqlite_reader.gd")

const DB_SUB := "GOG.com/Galaxy/storage/galaxy-2.0.db"
const ID_RE := "^[0-9]{5,14}$"
const DEFAULT_ROOTS := ["C:/GOG Games", "C:/Program Files (x86)/GOG Galaxy/Games", "D:/GOG Games"]
const DB_MAX := 256 * 1024 * 1024
## Startparameter aus goggame-*.info: nur schlichte Zeichen (sonst ohne Parameter starten).
const ARGS_RE := "^[A-Za-z0-9 _\\-+=.,:/\\\\\"]{0,200}$"


## Alle installierten GOG-Spiele. reg: Einträge des Helfers [{ id, name, path, exe, args, wdir,
## depends }], db: Pfad der Galaxy-Datenbank ("" = keiner), roots: Ordner mit Spielordnern.
static func scan(reg: Array = [], db := "", roots: Array = DEFAULT_ROOTS) -> Array:
	var cands := {}      ## ID → { dir, name, exe }
	var order: Array = []
	for r in SU.entries(reg, 2000):
		# Zusatzinhalte hängen am Hauptspiel (dependsOn) – eigene Einträge nur für Spiele.
		if str(r.get("depends", "")).strip_edges() != "":
			continue
		var id := SU.id_ok(str(r.get("id", "")), ID_RE)
		if id == "":
			id = SU.id_ok(str(r.get("key", "")), ID_RE)
		_add(cands, order, id, str(r.get("path", "")), str(r.get("name", "")), str(r.get("exe", "")))
	var meta := read_db(db)
	for id in meta.installed:
		_add(cands, order, str(id), str(meta.installed[id]), str(meta.titles.get(id, "")), "")
	for root in roots:
		var rd := SU.norm_path(str(root))
		if rd == "" or not DirAccess.dir_exists_absolute(rd):
			continue
		for sub in DirAccess.get_directories_at(rd).slice(0, 400):
			var info := find_info(rd.path_join(sub))
			if not info.is_empty():
				_add(cands, order, str(info.id), rd.path_join(sub), str(info.name), "")
	var out: Array = []
	for id in order:
		var c: Dictionary = cands[id]
		var dir := str(c.dir)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var info := parse_info(SU.read_text(dir.path_join("goggame-%s.info" % id)))
		var g := entry(id, dir, info, str(c.name), str(c.exe))
		if g.is_empty():
			continue
		var m := int(meta.minutes.get(id, 0))
		if m > 0:
			g["store_minutes"] = m
		var last := int(meta.last.get(id, 0))
		if last > 0:
			g["store_last"] = last
		g["install_time"] = FileAccess.get_modified_time(dir)
		out.append(g)
	return out


static func _add(cands: Dictionary, order: Array, id: String, dir: String, name: String, exe: String) -> void:
	var d := SU.game_dir(dir)
	if id == "" or d == "":
		return
	if not cands.has(id):
		cands[id] = { "dir": d, "name": "", "exe": "" }
		order.append(id)
	var c: Dictionary = cands[id]
	if str(c.name) == "" and name != "":
		c["name"] = name
	if str(c.exe) == "" and exe != "":
		c["exe"] = exe


## Rein: ein Spiel aus Ordner, goggame-*.info und Registry. {} ohne Titel und ohne Startweg.
static func entry(id: String, dir: String, info: Dictionary, reg_name := "", reg_exe := "") -> Dictionary:
	if SU.id_ok(id, ID_RE) == "" or SU.game_dir(dir) == "":
		return {}
	# Zusatzinhalt mit eigener info-Datei: gehört zum Hauptspiel.
	if str(info.get("root", "")) != "" and str(info.get("root", "")) != id:
		return {}
	var title := SU.title(str(info.get("name", "")))
	if title == "":
		title = SU.title(reg_name)
	if title == "":
		title = SU.title(dir.get_file())
	var exe := ""
	if str(info.get("exe", "")) != "":
		exe = SU.child(dir, str(info.exe))
	if exe == "" and reg_exe != "":
		var re := SU.norm_path(reg_exe)
		if re.to_lower().begins_with(dir.to_lower() + "/"):
			exe = re
	if exe != "" and exe.get_extension().to_lower() != "exe":
		exe = ""
	var g := {
		"id": "gog:%s" % id,
		"title": title,
		"system": "gog",
		"source": "gog",
		"gog": { "id": id },
		"install_dir": SU.game_dir(dir),
		"installed": true,
	}
	if exe != "":
		g["path"] = exe
		var args := str(info.get("args", ""))
		if args != "" and SU.id_ok(args, ARGS_RE) != "" and args.count("\"") % 2 == 0:
			g.gog["args"] = args
		var wd := SU.child(dir, str(info.get("wdir", ""))) if str(info.get("wdir", "")) != "" else ""
		if wd != "":
			g.gog["wdir"] = wd
	return g


## Erste goggame-*.info im Ordner → { id, name }; {} ohne.
static func find_info(dir: String) -> Dictionary:
	for f in DirAccess.get_files_at(dir).slice(0, 300):
		if f.begins_with("goggame-") and f.ends_with(".info"):
			var id := SU.id_ok(f.trim_prefix("goggame-").trim_suffix(".info"), ID_RE)
			if id == "":
				continue
			var info := parse_info(SU.read_text(dir.path_join(f)))
			if str(info.get("root", "")) in ["", id]:
				return { "id": id, "name": str(info.get("name", "")) }
	return {}


## Rein: goggame-<ID>.info (JSON) → { id, root, name, exe, args, wdir } – exe aus der ersten
## Hauptaufgabe (isPrimary, FileTask), relativ zum Spielordner.
static func parse_info(text: String) -> Dictionary:
	var d: Variant = SU.json(text)
	if not (d is Dictionary):
		return {}
	var out := {
		"id": SU.id_ok(str(d.get("gameId", "")), ID_RE),
		"root": SU.id_ok(str(d.get("rootGameId", "")), ID_RE),
		"name": str(d.get("name", "")) if d.get("name") is String else "",
	}
	var tasks: Variant = d.get("playTasks", [])
	if tasks is Array:
		var pick := {}
		for t in (tasks as Array).slice(0, 50):
			if not (t is Dictionary) or str(t.get("type", "")) != "FileTask" or not (t.get("path") is String):
				continue
			if not (str(t.get("category", "game")) in ["game", "launcher"]):
				continue
			if pick.is_empty() or bool(t.get("isPrimary", false)):
				pick = t
				if bool(t.get("isPrimary", false)):
					break
		if not pick.is_empty():
			out["exe"] = str(pick.path)
			out["args"] = str(pick.get("arguments", "")) if pick.get("arguments") is String else ""
			out["wdir"] = str(pick.get("workingDir", "")) if pick.get("workingDir") is String else ""
	return out


## Galaxy-Datenbank → { installed: { ID: Ordner }, titles: { ID: Titel }, minutes: { ID: Minuten },
## last: { ID: Unix-Zeit } }. Leer ohne Datei oder bei kaputter Datei.
static func read_db(path: String) -> Dictionary:
	var out := { "installed": {}, "titles": {}, "minutes": {}, "last": {} }
	if path == "" or not FileAccess.file_exists(path):
		return out
	var r := Sql.read_tables(path, {
		"InstalledBaseProducts": ["productId", "installationPath"],
		"LimitedDetails": ["productId", "title"],
		"GameTimes": ["releaseKey", "minutesInGame"],
		"LastPlayedDates": ["gameReleaseKey", "lastPlayedDate"],
	}, 20000)
	var t: Dictionary = r.tables
	for row in t.InstalledBaseProducts:
		var id := SU.id_ok(str(row.productId), ID_RE) if row.productId is int else ""
		if id != "" and row.installationPath is String:
			out.installed[id] = str(row.installationPath)
	for row in t.LimitedDetails:
		var id := SU.id_ok(str(row.productId), ID_RE) if row.productId is int else ""
		if id != "" and row.title is String and not out.titles.has(id):
			out.titles[id] = str(row.title)
	for row in t.GameTimes:
		var id := _release_id(row.releaseKey)
		if id != "" and row.minutesInGame is int and int(row.minutesInGame) > 0 and int(row.minutesInGame) < 10000000:
			out.minutes[id] = maxi(int(out.minutes.get(id, 0)), int(row.minutesInGame))
	for row in t.LastPlayedDates:
		var id := _release_id(row.gameReleaseKey)
		var at := SU.unix_of(str(row.lastPlayedDate)) if row.lastPlayedDate is String else 0
		if id != "" and at > 0:
			out.last[id] = maxi(int(out.last.get(id, 0)), at)
	return out


## „gog_1207658924“ → „1207658924“ (andere Plattformen in Galaxy: "").
static func _release_id(v: Variant) -> String:
	if not (v is String) or not str(v).begins_with("gog_"):
		return ""
	return SU.id_ok(str(v).substr(4), ID_RE)


## Startweg: über GOG Galaxy (galaxy: GalaxyClient.exe, "" = ohne Galaxy) oder die Programmdatei.
## { exe, args, dir } bzw. {} wenn es keinen gibt. Alles stammt aus geprüften Werten: ID nur Ziffern,
## Ordner ohne Anführungszeichen (SU.norm_path), Parameter nur schlichte Zeichen.
static func launch_plan(g: Dictionary, galaxy := "") -> Dictionary:
	var e := SU.sub(g, "gog")
	var id := SU.id_ok(str(e.get("id", "")), ID_RE)
	var dir := SU.game_dir(str(g.get("install_dir", "")))
	if id == "" or dir == "":
		return {}
	if galaxy != "" and SU.exe_ok(galaxy) and galaxy.get_file().to_lower() == "galaxyclient.exe":
		return { "exe": SU.norm_path(galaxy), "args": "/command=runGame /gameId=%s /path=\"%s\"" % [id, dir.replace("/", "\\")],
			"dir": SU.norm_path(galaxy).get_base_dir(), "via": "galaxy" }
	var exe := SU.norm_path(str(g.get("path", "")))
	if exe == "" or not exe.to_lower().begins_with(dir.to_lower() + "/") or not SU.exe_ok(exe):
		return {}
	var args := str(e.get("args", ""))
	if args != "" and (SU.id_ok(args, ARGS_RE) == "" or args.count("\"") % 2 != 0):
		args = ""
	var wd := SU.norm_path(str(e.get("wdir", "")))
	if wd == "" or not wd.to_lower().begins_with(dir.to_lower()):
		wd = exe.get_base_dir()
	return { "exe": exe, "args": args, "dir": wd, "via": "exe" }
