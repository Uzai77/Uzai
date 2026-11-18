extends RefCounted
## Installierte Spiele aus Amazon Games (Prime Gaming). Die App führt ihre Installationen in einer
## SQLite-Datei (%LOCALAPPDATA%\Amazon Games\Data\Games\Sql\GameInstallInfo.sqlite, Tabelle DbSet);
## Uzai liest sie mit seinem kleinen SQLite-Leser. Ohne Datei: die Deinstallations-Einträge, die
## Amazon Games in Windows anlegt (liest der Helfer, nur lesen). Gestartet wird über den Link der App
## (amazon-games://play/<ID>), wie ihre eigenen Verknüpfungen.

const SU := preload("res://src/library/store_util.gd")
const Sql := preload("res://src/library/sqlite_reader.gd")

const DB_SUB := "Amazon Games/Data/Games/Sql/GameInstallInfo.sqlite"
const ID_RE := "^amzn1\\.adg\\.product\\.[0-9a-fA-F\\-]{8,64}$"


## db: Pfad von GameInstallInfo.sqlite, uninstall: Deinstallations-Einträge [{ key, name, dir, cmd }].
static func scan(db := "", uninstall: Array = []) -> Array:
	var rows := read_db(db)
	rows.append_array(from_uninstall(uninstall))
	var out: Array = []
	var seen := {}
	for e in rows:
		var g := entry(str(e.id), str(e.dir), str(e.name))
		if g.is_empty() or seen.has(str(g.id)) or not DirAccess.dir_exists_absolute(str(g.install_dir)):
			continue
		seen[str(g.id)] = true
		g["install_time"] = FileAccess.get_modified_time(str(g.install_dir))
		out.append(g)
	return out


## Installierte aus GameInstallInfo.sqlite → [{ id, dir, name }] (ungeprüft, das macht entry()).
static func read_db(db: String) -> Array:
	var rows: Array = []
	if db == "" or not FileAccess.file_exists(db):
		return rows
	var r := Sql.read_tables(db, { "DbSet": ["Id", "InstallDirectory", "Installed", "ProductTitle"] }, 5000)
	for row in r.tables.DbSet:
		if row.Installed is int and int(row.Installed) == 0:
			continue
		rows.append({ "id": str(row.Id) if row.Id is String else "", "dir": str(row.InstallDirectory) if row.InstallDirectory is String else "",
			"name": str(row.ProductTitle) if row.ProductTitle is String else "" })
	return rows


static func entry(id: String, dir: String, name: String) -> Dictionary:
	var gid := SU.id_ok(id, ID_RE)
	var d := SU.game_dir(dir)
	if gid == "" or d == "":
		return {}
	var title := SU.title(name)
	if title == "":
		title = SU.title(d.get_file())
	return {
		"id": "amazon:%s" % gid.trim_prefix("amzn1.adg.product."),
		"title": title,
		"system": "amazon",
		"source": "amazon",
		"amazon": { "id": gid },
		"install_dir": d,
		"installed": true,
	}


## Rein: Deinstallations-Einträge von Amazon Games („…\Amazon Game Remover.exe" -m Game -p <ID>)
## → [{ id, dir, name }].
static func from_uninstall(list: Array) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(?i)Amazon Game Remover\\.exe\"?\\s.*-p\\s+(amzn1\\.adg\\.product\\.[0-9a-fA-F\\-]{8,64})")
	for u in SU.entries(list, 4000):
		var cmd := str(u.get("cmd", ""))
		if cmd.length() > 2000:
			continue
		var m := re.search(cmd)
		if m != null:
			out.append({ "id": m.get_string(1), "dir": str(u.get("dir", "")), "name": str(u.get("name", "")) })
	return out


static func launch_uri(g: Dictionary) -> String:
	var id := SU.id_ok(str(SU.sub(g, "amazon").get("id", "")), ID_RE)
	return "amazon-games://play/%s" % id if id != "" else ""
