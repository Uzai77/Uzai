extends RefCounted
## Liest installierte Steam-Spiele direkt aus den Steam-Dateien (ohne Internet, ohne Konto).

const VDF := preload("res://src/library/vdf.gd")
const SKIP_IDS := [228980, 1070560, 1391110, 1628350, 250820, 1493710]
const SKIP_WORDS := ["proton", "steam linux runtime", "steamworks", "redistributable", "steamvr", "dedicated server", "soundtrack", " sdk", "steam audio"]

const DEFAULT_ROOTS := [
	"C:/Program Files (x86)/Steam",
	"C:/Program Files/Steam",
	"D:/Steam",
	"D:/Program Files (x86)/Steam",
	"E:/Steam",
]


static func find_root(configured: String, registry: String) -> String:
	for cand in [configured, registry]:
		var c := str(cand).replace("\\", "/")
		if c != "" and DirAccess.dir_exists_absolute(c.path_join("steamapps")):
			return c
	for c in DEFAULT_ROOTS:
		if DirAccess.dir_exists_absolute(str(c).path_join("steamapps")):
			return c
	var home := OS.get_environment("HOME")
	if home != "":
		for c in [home.path_join(".steam/steam"), home.path_join(".local/share/Steam")]:
			if DirAccess.dir_exists_absolute(c.path_join("steamapps")):
				return c
	return ""


static func library_dirs(root: String) -> Array:
	var out: Array = []
	if root == "":
		return out
	out.append(root)
	var lf := VDF.parse_file(root.path_join("steamapps/libraryfolders.vdf"))
	var folders: Variant = VDF.get_ci(lf, "libraryfolders", {})
	if folders is Dictionary:
		for k in folders.keys():
			var entry: Variant = folders[k]
			var p := ""
			if entry is Dictionary:
				p = str(VDF.get_ci(entry, "path", ""))
			elif entry is String:
				p = entry
			p = p.replace("\\", "/")
			if p != "" and not out.has(p) and DirAccess.dir_exists_absolute(p):
				out.append(p)
	return out


static func scan(root: String) -> Array:
	var out: Array = []
	var seen := {}
	for lib in library_dirs(root):
		var apps := str(lib).path_join("steamapps")
		var da := DirAccess.open(apps)
		if da == null:
			continue
		for f in da.get_files():
			if not (f.begins_with("appmanifest_") and f.ends_with(".acf")):
				continue
			var acf := VDF.parse_file(apps.path_join(f))
			var st: Variant = VDF.get_ci(acf, "AppState", {})
			if not (st is Dictionary):
				continue
			var appid := int(str(VDF.get_ci(st, "appid", "0")))
			var name := str(VDF.get_ci(st, "name", ""))
			if appid == 0 or name == "" or seen.has(appid) or is_tool_app(appid, name):
				continue
			seen[appid] = true
			var installdir := str(VDF.get_ci(st, "installdir", ""))
			out.append({
				"id": "steam:%d" % appid,
				"title": name,
				"system": "steam",
				"source": "steam",
				"appid": appid,
				"install_dir": apps.path_join("common").path_join(installdir),
				"installed": true,
				"steam_last": int(str(VDF.get_ci(st, "LastPlayed", "0"))),
				"install_time": int(str(VDF.get_ci(st, "LastUpdated", "0"))),
			})
	return out


## Installierte Erweiterungen aus einem appmanifest: Steam führt unter „InstalledDepots“ bei den
## Depots einer Erweiterung deren App-ID („dlcappid“). Erweiterungen ohne eigene Dateien (nur
## freigeschaltet) stehen dort nicht – ihr Besitz bleibt unbekannt. { appid: true }
static func installed_dlc(acf: Dictionary) -> Dictionary:
	var out := {}
	var st: Variant = VDF.get_ci(acf, "AppState", {})
	var deps: Variant = VDF.get_ci(st, "InstalledDepots", {}) if st is Dictionary else null
	if not (deps is Dictionary):
		return out
	for k in deps.keys():
		var dep: Variant = deps[k]
		var id := int(str(VDF.get_ci(dep, "dlcappid", "0"))) if dep is Dictionary else 0
		if id > 0:
			out[id] = true
	return out


## Dasselbe für ein Spiel in einem der Bibliotheksordner ({} ohne Steam oder appmanifest).
static func installed_dlc_of(root: String, appid: int) -> Dictionary:
	if appid <= 0:
		return {}
	for lib in library_dirs(root):
		var p := str(lib).path_join("steamapps/appmanifest_%d.acf" % appid)
		if FileAccess.file_exists(p):
			return installed_dlc(VDF.parse_file(p))
	return {}


## Werkzeug statt Spiel (Proton, Redistributables …)? Nicht „is_tool“: so heißt schon die
## Methode jedes Skripts (Script.is_tool), SteamScanner.is_tool(…) rief die falsche auf.
static func is_tool_app(appid: int, name: String) -> bool:
	if appid in SKIP_IDS:
		return true
	var low := " " + name.to_lower()
	for w in SKIP_WORDS:
		if low.contains(w):
			return true
	return false
