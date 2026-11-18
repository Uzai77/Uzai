extends RefCounted
## Installierte Spiele aus der itch-App (itch.io). Die App führt alles in einer SQLite-Datei
## (%APPDATA%\itch\db\butler.db): Installationen („caves“ mit Ordner, Spielzeit, zuletzt gespielt
## und dem erkannten Programm), Spiele (Titel, Art) und Speicherorte. Uzai liest sie mit seinem
## kleinen SQLite-Leser. itch.io-Spiele sind ohne Kopierschutz; die App startet dabei selbst nur die
## erkannte Programmdatei – Uzai macht es genauso (nur eine .exe im Spielordner, ohne Parameter).

const SU := preload("res://src/library/store_util.gd")
const Sql := preload("res://src/library/sqlite_reader.gd")

const DB_SUB := "itch/db/butler.db"
const CAVE_RE := "^[0-9a-fA-F\\-]{8,40}$"
## Arten, die itch.io anbietet: nur Spiele (keine Werkzeuge, Grafiken, Musik, Bücher).
const KINDS := ["", "game"]


static func scan(db: String) -> Array:
	var out: Array = []
	for g in read_db(db):
		if not DirAccess.dir_exists_absolute(str(g.install_dir)):
			continue
		g["install_time"] = FileAccess.get_modified_time(str(g.install_dir))
		out.append(g)
	return out


## Alle Spiele aus butler.db, geprüft, aber ohne nachzusehen, ob die Ordner da sind.
static func read_db(db: String) -> Array:
	var out: Array = []
	if db == "" or not FileAccess.file_exists(db):
		return out
	var r := Sql.read_tables(db, {
		"caves": ["id", "game_id", "install_folder_name", "install_location_id", "custom_install_folder", "verdict", "seconds_run", "last_touched_at"],
		"games": ["id", "title", "classification"],
		"install_locations": ["id", "path"],
	}, 10000)
	var t: Dictionary = r.tables
	var games := {}
	for row in t.games:
		if row.id is int:
			games[int(row.id)] = row
	var locs := {}
	for row in t.install_locations:
		if row.id is String and row.path is String:
			locs[str(row.id)] = str(row.path)
	var seen := {}
	for c in t.caves:
		var gm: Dictionary = games.get(int(c.game_id) if c.game_id is int else -1, {})
		var g := entry(c, gm, locs)
		if g.is_empty() or seen.has(str(g.id)):
			continue
		seen[str(g.id)] = true
		out.append(g)
	return out


## Rein: eine Installation (caves), ihr Spiel (games) und die Speicherorte → Spiel; {} sonst.
static func entry(c: Dictionary, gm: Dictionary, locs: Dictionary) -> Dictionary:
	var cave := SU.id_ok(str(c.get("id", "")) if c.get("id") is String else "", CAVE_RE)
	if cave == "":
		return {}
	var kind := str(gm.get("classification", "")) if gm.get("classification") is String else ""
	if not kind in KINDS:
		return {}
	var verdict: Variant = SU.json(str(c.verdict)) if c.get("verdict") is String else null
	if not (verdict is Dictionary):
		verdict = {}
	var dir := ""
	for cand in [str(verdict.get("basePath", "")) if verdict.get("basePath") is String else "",
			str(c.get("custom_install_folder", "")) if c.get("custom_install_folder") is String else ""]:
		dir = SU.game_dir(cand)
		if dir != "":
			break
	if dir == "":
		var base := SU.norm_path(str(locs.get(str(c.get("install_location_id", "")), "")))
		var folder := str(c.get("install_folder_name", "")) if c.get("install_folder_name") is String else ""
		if base != "" and folder != "" and not folder.contains("/") and not folder.contains("\\"):
			dir = SU.game_dir(base.path_join("apps").path_join(folder))
	if dir == "":
		return {}
	var title := SU.title(str(gm.get("title", "")) if gm.get("title") is String else "")
	if title == "":
		title = SU.title(dir.get_file())
	var gid := int(gm.get("id", 0)) if gm.get("id") is int else 0
	var g := {
		"id": "itch:%d" % gid if gid > 0 else "itch:%s" % cave.to_lower(),
		"title": title,
		"system": "itch",
		"source": "itch",
		"itch": { "cave": cave },
		"install_dir": dir,
		"installed": true,
	}
	var cands: Variant = verdict.get("candidates", [])
	if cands is Array:
		for k in (cands as Array).slice(0, 20):
			if k is Dictionary and k.get("path") is String and str(k.path).get_extension().to_lower() == "exe":
				var exe := SU.child(dir, str(k.path))
				if exe != "":
					g["path"] = exe
					break
	var secs := int(c.seconds_run) if c.get("seconds_run") is int else 0
	if secs > 0 and secs < 600000000:
		g["store_minutes"] = int(secs / 60.0)
	var last := SU.unix_of(str(c.last_touched_at)) if c.get("last_touched_at") is String else 0
	if last > 0:
		g["store_last"] = last
	return g


## Programmdatei aus der Erkennung der itch-App; {} wenn es keine gibt (dann startet Uzai nichts).
static func launch_plan(g: Dictionary) -> Dictionary:
	var dir := SU.game_dir(str(g.get("install_dir", "")))
	var exe := SU.norm_path(str(g.get("path", "")))
	if dir == "" or exe == "" or not exe.to_lower().begins_with(dir.to_lower() + "/") or not SU.exe_ok(exe):
		return {}
	return { "exe": exe, "args": "", "dir": exe.get_base_dir(), "via": "exe" }
