extends RefCounted
## Installierte Spiele aus Ubisoft Connect. Ubisoft Connect trägt jedes installierte Spiel in der
## Registry ein (Ubisoft\Launcher\Installs\<ID> mit „InstallDir“, dazu ein Deinstallations-Eintrag
## „Uplay Install <ID>“ mit dem Namen); beides liest der Helfer, nur lesen. Seine eigenen
## Konfigurationsdateien (verschlüsselter Zwischenspeicher) liest Uzai nicht. Gestartet wird über
## den Link, den Ubisoft Connect selbst für Verknüpfungen nutzt (uplay://launch/<ID>/0).

const SU := preload("res://src/library/store_util.gd")

const ID_RE := "^[0-9]{1,8}$"


## reg: [{ id, dir }] aus der Registry, names: { ID: Name } aus den Deinstallations-Einträgen,
## skip: Ordner, die schon eine andere Quelle zeigt (über Steam oder Epic gekaufte Ubisoft-Spiele).
static func scan(reg: Array, names: Dictionary = {}, skip: Array = []) -> Array:
	var skip_keys := {}
	for s in skip:
		skip_keys[str(s).to_lower()] = true
	var out: Array = []
	var seen := {}
	for r in SU.entries(reg, 1000):
		var id := SU.id_ok(str(r.get("id", "")), ID_RE)
		var dir := SU.game_dir(str(r.get("dir", "")))
		if id == "" or dir == "" or seen.has(id) or skip_keys.has(dir.to_lower()) or dir.to_lower().contains("/steamapps/"):
			continue
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var title := SU.title(str(names.get(id, "")))
		if title == "":
			title = SU.title(dir.get_file())
		if title == "":
			continue
		seen[id] = true
		out.append({
			"id": "ubisoft:%s" % id,
			"title": title,
			"system": "ubisoft",
			"source": "ubisoft",
			"ubisoft": { "id": id },
			"install_dir": dir,
			"installed": true,
			"install_time": FileAccess.get_modified_time(dir),
		})
	return out


## Rein: Namen aus den Deinstallations-Einträgen [{ key, name }] („Uplay Install 5059“ → { "5059": … }).
static func names_of(uninstall: Array) -> Dictionary:
	var out := {}
	for u in SU.entries(uninstall, 4000):
		var k := str(u.get("key", ""))
		if not k.begins_with("Uplay Install "):
			continue
		var id := SU.id_ok(k.trim_prefix("Uplay Install "), ID_RE)
		if id != "" and str(u.get("name", "")) != "":
			out[id] = str(u.name)
	return out


static func launch_uri(g: Dictionary) -> String:
	var id := SU.id_ok(str(SU.sub(g, "ubisoft").get("id", "")), ID_RE)
	return "uplay://launch/%s/0" % id if id != "" else ""
