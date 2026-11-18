extends RefCounted
## Installierte Spiele des Riot Client (League of Legends, VALORANT, Legends of Runeterra …). Der
## Riot Client legt je Spiel unter ProgramData\Riot Games\Metadata\<Produkt>.<Zweig>\ eine kleine
## YAML-Datei mit dem Spielordner ab und in RiotClientInstalls.json, wo er selbst liegt. Uzai liest
## nur diese Dateien (nur einfache „Schlüssel: Wert“-Zeilen, streng begrenzt). Gestartet wird wie über
## Riots eigene Verknüpfungen: RiotClientServices.exe --launch-product=<Produkt> --launch-patchline=<Zweig>.
## Anmeldung und Anti-Cheat bleiben ganz beim Riot Client.

const SU := preload("res://src/library/store_util.gd")

const BASE_SUB := "Riot Games"
const PRODUCT_RE := "^[a-z][a-z0-9_]{1,31}$"
const LINE_RE := "^[a-z][a-z0-9_]{1,15}$"
const NOT_GAMES := ["riot_client", "rc", "riotclient"]
const TITLES := { "league_of_legends": "League of Legends", "valorant": "VALORANT", "bacon": "Legends of Runeterra", "lion": "2XKO" }


## base: ProgramData\Riot Games (für Tests austauschbar).
static func scan(base: String) -> Array:
	var out: Array = []
	var meta := base.path_join("Metadata")
	if base == "" or not DirAccess.dir_exists_absolute(meta):
		return out
	var seen := {}
	for sub in DirAccess.get_directories_at(meta).slice(0, 100):
		var parts := sub.split(".")
		if parts.size() != 2:
			continue
		var product := SU.id_ok(parts[0], PRODUCT_RE)
		var line := SU.id_ok(parts[1], LINE_RE)
		if product == "" or line == "" or product in NOT_GAMES or seen.has(product + "." + line):
			continue
		var y := {}
		for f in DirAccess.get_files_at(meta.path_join(sub)).slice(0, 50):
			if f.begins_with(sub) and f.get_extension().to_lower() == "yaml":
				y = parse_yaml(SU.read_text(meta.path_join(sub).path_join(f), 128 * 1024))
				if y.has("product_install_full_path"):
					break
		var g := entry(product, line, str(y.get("product_install_full_path", "")))
		if g.is_empty() or not DirAccess.dir_exists_absolute(str(g.install_dir)):
			continue
		seen[product + "." + line] = true
		g["install_time"] = FileAccess.get_modified_time(str(g.install_dir))
		out.append(g)
	return out


static func entry(product: String, line: String, dir: String) -> Dictionary:
	var p := SU.id_ok(product, PRODUCT_RE)
	var l := SU.id_ok(line, LINE_RE)
	var d := SU.game_dir(dir)
	if p == "" or l == "" or d == "" or p in NOT_GAMES:
		return {}
	var title := str(TITLES.get(p, ""))
	if title == "":
		title = SU.title(d.get_file())
	if l != "live":
		title += " (%s)" % l.to_upper()
	return {
		"id": "riot:%s" % p if l == "live" else "riot:%s.%s" % [p, l],
		"title": title,
		"system": "riot",
		"source": "riot",
		"riot": { "product": p, "line": l },
		"install_dir": d,
		"installed": true,
	}


## Rein: nur Zeilen „schlüssel: wert“ ohne Einrückung (verschachteltes bleibt unbeachtet), Werte
## ohne Anführungszeichen. Höchstens 2000 Zeilen.
static func parse_yaml(text: String) -> Dictionary:
	var out := {}
	var n := 0
	for raw in text.split("\n"):
		n += 1
		if n > 2000:
			break
		var l := raw.trim_suffix("\r")
		if l == "" or l.begins_with(" ") or l.begins_with("\t") or l.begins_with("#") or not l.contains(": "):
			continue
		var k := l.get_slice(": ", 0).strip_edges()
		var v := l.substr(k.length() + 2).strip_edges()
		if v.length() >= 2 and ((v.begins_with("\"") and v.ends_with("\"")) or (v.begins_with("'") and v.ends_with("'"))):
			v = v.substr(1, v.length() - 2)
		if SU.id_ok(k, "^[a-z_]{1,64}$") != "" and not out.has(k):
			out[k] = v
	return out


## RiotClientServices.exe aus RiotClientInstalls.json; "" wenn nicht da oder nicht plausibel.
static func client_exe(base: String) -> String:
	var d: Variant = SU.json(SU.read_text(base.path_join("RiotClientInstalls.json"), 64 * 1024))
	if not (d is Dictionary):
		return ""
	for k in ["rc_default", "rc_live"]:
		var p := SU.norm_path(str(d.get(k, "")) if d.get(k) is String else "")
		if p != "" and p.get_file().to_lower() == "riotclientservices.exe" and SU.exe_ok(p):
			return p
	return ""


static func launch_plan(g: Dictionary, client: String) -> Dictionary:
	var e := SU.sub(g, "riot")
	var p := SU.id_ok(str(e.get("product", "")), PRODUCT_RE)
	var l := SU.id_ok(str(e.get("line", "")), LINE_RE)
	if p == "" or l == "" or client == "" or not SU.exe_ok(client) or client.get_file().to_lower() != "riotclientservices.exe":
		return {}
	var c := SU.norm_path(client)
	return { "exe": c, "args": "--launch-product=%s --launch-patchline=%s" % [p, l], "dir": c.get_base_dir(), "via": "client" }
