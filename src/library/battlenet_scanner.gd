extends RefCounted
## Installierte Spiele aus Battle.net. Uzai liest nur, was der Battle.net-Agent selbst ablegt:
##   - ProgramData\Battle.net\Agent\product.db (Protobuf: je Produkt Kennung, Produktcode,
##     Installationsordner, installiert ja/nein) mit einem kleinen, streng begrenzten Leser,
##   - %APPDATA%\Battle.net\Battle.net.config (JSON, „LastPlayed“ je Spiel),
##   - Namen aus den Deinstallations-Einträgen von Blizzard (liest der Helfer, nur lesen).
## Gestartet wird wie über Battle.nets eigene Verknüpfungen: „Battle.net.exe --exec="launch <Code>"“.
## Der Produktcode ist nur Buchstaben und Ziffern (geprüft), nie freier Text.

const SU := preload("res://src/library/store_util.gd")

const DB_SUB := "Battle.net/Agent/product.db"
const CONFIG_SUB := "Battle.net/Battle.net.config"
const DB_MAX := 8 * 1024 * 1024
const CODE_RE := "^[A-Za-z][A-Za-z0-9]{1,7}$"
## Kein Spiel: der Agent selbst, die App, Hilfsprogramme.
const NOT_GAMES := ["agent", "app", "bna", "bts", "battle.net", "catalogs"]
## Bekannte Spiele: Produktcode → Titel (sonst der Name aus Windows bzw. der Ordner).
const TITLES := {
	"WoW": "World of Warcraft", "WoWC": "World of Warcraft Classic", "D3": "Diablo III", "Fen": "Diablo IV",
	"OSI": "Diablo II: Resurrected", "S2": "StarCraft II", "S1": "StarCraft: Remastered", "WTCG": "Hearthstone",
	"Hero": "Heroes of the Storm", "Pro": "Overwatch 2", "W3": "Warcraft III: Reforged", "ANBS": "Diablo Immortal",
	"GRY": "Warcraft Rumble", "RTRO": "Blizzard Arcade Collection", "WLBY": "Crash Bandicoot 4",
	"VIPR": "Call of Duty: Black Ops 4", "ODIN": "Call of Duty: Modern Warfare", "ZEUS": "Call of Duty: Black Ops Cold War",
	"FORE": "Call of Duty: Vanguard", "AUKS": "Call of Duty", "LAZR": "Call of Duty: Modern Warfare 2 Campaign Remastered",
}


## db: Inhalt von product.db, names: { Ordner (klein): Name } aus Windows, last: { uid: Unix-Zeit }.
static func scan(db: PackedByteArray, names: Dictionary = {}, last: Dictionary = {}) -> Array:
	var out: Array = []
	var seen := {}
	for p in parse_db(db):
		var code := SU.id_ok(str(p.code), CODE_RE)
		var uid := str(p.uid).to_lower()
		if code == "" or uid in NOT_GAMES or code.to_lower() in NOT_GAMES or seen.has(code) or not bool(p.installed):
			continue
		var dir := SU.game_dir(str(p.dir))
		if dir == "" or not DirAccess.dir_exists_absolute(dir):
			continue
		var title := SU.title(str(TITLES.get(code, "")))
		if title == "":
			title = SU.title(str(names.get(dir.to_lower(), "")))
		if title == "":
			title = SU.title(dir.get_file())
		seen[code] = true
		var g := {
			"id": "battlenet:%s" % code,
			"title": title,
			"system": "battlenet",
			"source": "battlenet",
			"battlenet": { "code": code, "uid": SU.id_ok(uid, "^[a-z0-9_.\\-]{1,40}$") },
			"install_dir": dir,
			"installed": true,
			"install_time": FileAccess.get_modified_time(dir),
		}
		var lp := int(last.get(uid, 0))
		if lp > 0:
			g["store_last"] = lp
		out.append(g)
	return out


## Rein: product.db → [{ uid, code, dir, installed }]. Kaputtes oder Fremdes: so viel wie lesbar.
static func parse_db(b: PackedByteArray) -> Array:
	var out: Array = []
	if b.is_empty() or b.size() > DB_MAX:
		return out
	for f in proto_fields(b, 0, b.size()):
		if int(f[0]) != 1 or int(f[1]) != 2 or out.size() >= 500:
			continue
		var p := { "uid": "", "code": "", "dir": "", "installed": true }
		for g in proto_fields(b, int(f[2]), int(f[3])):
			match int(g[0]):
				1: p.uid = _str(b, g)
				2: p.code = _str(b, g)
				3:
					for s in proto_fields(b, int(g[2]), int(g[3])):
						if int(s[0]) == 1:
							p.dir = _str(b, s)
				4:
					# CachedProductState → BaseProductState → installed (Feld 1, bool)
					for s in proto_fields(b, int(g[2]), int(g[3])):
						if int(s[0]) == 1 and int(s[1]) == 2:
							for t in proto_fields(b, int(s[2]), int(s[3])):
								if int(t[0]) == 1 and int(t[1]) == 0:
									p.installed = int(t[2]) != 0
		out.append(p)
	return out


static func _str(b: PackedByteArray, f: Array) -> String:
	if int(f[1]) != 2 or int(f[3]) - int(f[2]) > 2048:
		return ""
	return b.slice(int(f[2]), int(f[3])).get_string_from_utf8()


## Rein: Protobuf-Felder im Bereich [from, to) → [[Nummer, Art, a, b]]: Art 0 (Zahl: a = Wert),
## Art 2 (Länge: a..b), 1/5 werden übersprungen. Bei Unsinn (Art 3/4/6/7, Längen über das Ende)
## endet die Liste dort. Höchstens 20000 Felder.
static func proto_fields(b: PackedByteArray, from: int, to: int) -> Array:
	var out: Array = []
	var o := from
	to = mini(to, b.size())
	while o < to and out.size() < 20000:
		var k := _varint(b, o, to)
		if k.is_empty():
			break
		var key: int = k[0]
		o = k[1]
		var num := key >> 3
		var wt := key & 7
		if num <= 0:
			break
		match wt:
			0:
				var v := _varint(b, o, to)
				if v.is_empty():
					break
				out.append([num, 0, v[0], 0])
				o = v[1]
			1:
				o += 8
			5:
				o += 4
			2:
				var l := _varint(b, o, to)
				if l.is_empty() or int(l[0]) < 0 or int(l[1]) + int(l[0]) > to:
					break
				out.append([num, 2, l[1], int(l[1]) + int(l[0])])
				o = int(l[1]) + int(l[0])
			_:
				break
	return out


static func _varint(b: PackedByteArray, o: int, to: int) -> Array:
	var v := 0
	var shift := 0
	while o < to and shift < 64:
		var c := b[o]
		v |= (c & 0x7f) << shift
		o += 1
		if c < 0x80:
			return [v, o]
		shift += 7
	return []


## Rein: Battle.net.config (JSON) → { uid (klein): Unix-Zeit von „LastPlayed“ }.
static func parse_config(text: String) -> Dictionary:
	var out := {}
	var d: Variant = SU.json(text)
	if not (d is Dictionary) or not (d.get("Games") is Dictionary):
		return out
	for k in (d.Games as Dictionary).keys().slice(0, 500):
		var e: Variant = d.Games[k]
		if not (e is Dictionary):
			continue
		var v := str(e.get("LastPlayed", ""))
		if v.is_valid_int() and int(v) > 946684800 and int(v) < 4102444800:
			out[str(k).to_lower()] = int(v)
	return out


## Battle.net-Programm im Ordner (aus Windows): erst der kleine Starter, sonst die App selbst.
static func client_exe(dir: String) -> String:
	var d := SU.norm_path(dir)
	if d == "":
		return ""
	for n in ["Battle.net Launcher.exe", "Battle.net.exe"]:
		if SU.exe_ok(d.path_join(n)):
			return d.path_join(n)
	return ""


## { exe, args, dir } für den Start über Battle.net; {} ohne Programm oder mit ungültigem Code.
static func launch_plan(g: Dictionary, client: String) -> Dictionary:
	var code := SU.id_ok(str(SU.sub(g, "battlenet").get("code", "")), CODE_RE)
	if code == "" or client == "" or not SU.exe_ok(client):
		return {}
	var c := SU.norm_path(client)
	return { "exe": c, "args": "--exec=\"launch %s\"" % code, "dir": c.get_base_dir(), "via": "client" }
