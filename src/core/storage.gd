extends RefCounted
## Speicherplatz (Punkte 10 und 106): wie groß ein Spiel ist und ob es noch aufs Laufwerk passt,
## Laufwerke mit Belegung, installierte Spiele nach Größe und was Uzai von seinen eigenen Daten
## aufräumen darf. Uzai löscht und verschiebt nie selbst Spieldateien – Deinstallieren und
## Verschieben machen die Launcher (StorageFlow). Aufräumen gibt es nur für Zwischenspeicher,
## Protokolle und den Aufnahme-Puffer im Datenordner; jeder Pfad wird vor dem Löschen geprüft.
## Ohne Zustand und ohne Windows, darum testbar (tests/logic_speicher.gd).

const VDF := preload("res://src/library/vdf.gd")
const P := preload("res://src/core/install_parse.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

const GIB := 1073741824
## So viel soll nach einer Installation mindestens frei bleiben (Updates, Windows, Auslagerungsdatei).
const RESERVE := 10 * GIB

## Was „Aufräumen“ anbietet: [Kennung, Name, Ordner im Datenordner, Erklärung]. Alles darin legt
## Uzai bei Bedarf von selbst wieder an. Einstellungen, Bibliothek, Anmeldungen, Sicherungen,
## Medienordner und fertige Clips stehen hier nicht und werden nie angefasst.
const CLEAN := [
	["bilder", "Zwischengespeicherte Bilder", "cache/img",
		"Cover und Hintergründe aus dem Netz. Werden bei Bedarf neu geladen."],
	["listen", "Weitere Zwischenspeicher", "cache", "Gemerkte Listen und Vorschaubilder (Startseiten, Shop, Spielinfos, Vorschaubilder der Aufnahmen). Uzai holt sie neu; das erste Öffnen dauert dann etwas länger."],
	["protokolle", "Protokolle", "logs", "Uzais Protokolle für die Fehlersuche. Ein Fehlerbericht enthält danach nur, was ab jetzt passiert."],
	["puffer", "Aufnahme-Puffer", "capture/puffer",
		"Die letzten Sekunden für „Clip speichern“. Geht nur, solange der Puffer ruht – kein Spiel vorn, keine Aufnahme. Fertige Clips bleiben."],
]


## Unter cache/ liegt auch, was Uzai nicht neu holen kann. Das bleibt beim Aufräumen stehen: die Stellen von
## „Weiterschauen“ bei Twitch und die letzte Warteschlange der eigenen Musik.
const CLEAN_BLEIBT := ["cache/twitch.json", "cache/musik/zuletzt.json"]


# --- Größe und Platz ----------------------------------------------------------------------------

## Platzbedarf aus Steams Systemanforderungen ([[Bezeichnung, Wert], …], Store.parse_requirements):
## „Speicherplatz: 50 GB verfügbarer Speicherplatz“, englisch „Storage: 50 GB available space“,
## ältere Seiten „Festplatte“ oder „Hard Drive“. Steam meint mit GB Windows-GB (1024³).
## Bytes, -1 = steht nicht da.
static func size_from_requirements(req: Array) -> int:
	var num := RegEx.create_from_string("(?i)(\\d+(?:[.,]\\d+)?)\\s*(TB|GB|MB|GiB|MiB)\\b")
	for kv in req:
		if not (kv is Array) or (kv as Array).size() < 2:
			continue
		var k := str(kv[0]).to_lower()
		if k.contains("arbeit") or k.contains("memory") or k.contains("grafik") or k.contains("graphics"):
			continue
		if not (k.contains("speicher") or k.contains("storage") or k.contains("festplatte") or k.contains("hard drive")
				or k.contains("hard disk") or k.contains("disk space") or k.contains("hdd")):
			continue
		var m := num.search(str(kv[1]))
		if m == null:
			continue
		var n := float(m.get_string(1).replace(",", "."))
		var unit := m.get_string(2).to_upper()
		var mult := 1048576.0 if unit in ["MB", "MIB"] else (1099511627776.0 if unit == "TB" else float(GIB))
		return int(n * mult)
	return -1


## Wie es nach der Installation aussähe: "ok", "knapp" (danach weniger als RESERVE frei, oder bei
## unbekannter Größe jetzt schon), "voll" (passt nicht), "" (freier Platz unbekannt).
static func space_level(need: int, free: int) -> String:
	if free < 0:
		return ""
	if need > 0 and free < need:
		return "voll"
	if free - maxi(need, 0) < RESERVE:
		return "knapp"
	return "ok"


## Kurz für Spiel- und Shopseite: „ca. 45,0 GB · 210,3 GB frei auf C:“ (fehlt etwas, nur der Rest).
static func note(need: int, free: int, drive: String) -> String:
	var parts := PackedStringArray()
	if need > 0:
		parts.append("ca. " + P.gb(float(need)))
	if free >= 0:
		parts.append(("%s frei auf %s" % [P.gb(float(free)), drive]) if drive != "" else ("%s frei" % P.gb(float(free))))
	return " · ".join(parts)


## Größe für Aufräumen: kleine Mengen nicht als „0 MB“.
static func size_text(bytes: int) -> String:
	return "unter 1 MB" if bytes > 0 and bytes < 1048576 else P.gb(float(bytes))


## Laufwerk eines Pfads: „C:“ unter Windows, „/“ sonst, "" wenn nicht erkennbar.
static func drive_of(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.length() >= 2 and p[1] == ":" and p.unicode_at(0) < 128 and p[0].to_upper() != p[0].to_lower():
		return p.left(2).to_upper()
	return "/" if p.begins_with("/") else ""


## Laufwerke aus der Antwort des Helfers (Befehl „drives“): [{ name „C:“, label, total, free }].
## Nur, was plausibel ist – ein kaputter Eintrag fällt weg, statt falsche Balken zu zeichnen.
static func drives_from(result: Variant) -> Array:
	var out: Array = []
	if not (result is Dictionary) or not (result.get("drives") is Array):
		return out
	for d in result.drives:
		if not (d is Dictionary):
			continue
		var name := drive_of(str(d.get("name", "")))
		var total := int(d.get("total", 0))
		var free := int(d.get("free", -1))
		if name.length() != 2 or total <= 0 or free < 0 or free > total:
			continue
		out.append({ "name": name, "label": str(d.get("label", "")).strip_edges().left(40), "total": total, "free": free })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) < str(b.name))
	return out


## Je Laufwerk, wie viel davon die bekannten Spiele belegen (für den Balken „Spiele · Anderes · Frei“).
static func games_per_drive(games: Array) -> Dictionary:
	var out := {}
	for g in games:
		var b := int(g.get("bytes", -1))
		var dr := str(g.get("drive", ""))
		if b > 0 and dr != "":
			out[dr] = int(out.get(dr, 0)) + b
	return out


## Größte zuerst, unbekannte Größen (noch gemessen) ans Ende, gleich große nach Titel.
static func by_size(games: Array) -> Array:
	var out := games.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var x := int(a.get("bytes", -1))
		var y := int(b.get("bytes", -1))
		if x != y:
			return x > y
		return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0
	)
	return out


# --- Was die Launcher über installierte Spiele wissen ---------------------------------------------

## Größe aus einem Steam-appmanifest (AppState, SizeOnDisk), -1 unbekannt.
static func steam_size(st: Dictionary) -> int:
	var s := str(VDF.get_ci(st, "SizeOnDisk", ""))
	return int(s) if s.is_valid_int() and int(s) > 0 else -1


## Alle Steam-Spiele der Bibliotheksordner, die Steam als installiert führt:
## appid → { bytes, lib, dir }. Nur lesen.
static func steam_installed(libs: Array) -> Dictionary:
	var out := {}
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
			var appid := int(str(VDF.get_ci(st, "appid", "0")))
			if appid <= 0 or out.has(appid):
				continue
			out[appid] = { "bytes": steam_size(st), "lib": str(lib),
				"dir": apps.path_join("common").path_join(str(VDF.get_ci(st, "installdir", ""))) }
	return out


## Epic-Manifeste (*.item im Manifests-Ordner): AppName → { bytes (InstallSize), dir }.
static func epic_installed(manifest_dir: String) -> Dictionary:
	var out := {}
	var da := DirAccess.open(manifest_dir)
	if da == null:
		return out
	for f in da.get_files():
		if not f.ends_with(".item"):
			continue
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(manifest_dir.path_join(f))) != OK or not (j.data is Dictionary):
			continue
		var data: Dictionary = j.data
		var app := str(data.get("AppName", ""))
		if app == "" or bool(data.get("bIsIncompleteInstall", false)):
			continue
		var size := int(data.get("InstallSize", -1)) if (data.get("InstallSize") is float or data.get("InstallSize") is int) else -1
		out[app] = { "bytes": size if size > 0 else -1, "dir": str(data.get("InstallLocation", "")).replace("\\", "/") }
	return out


# --- Aufräumen: nur in Uzais Datenordner ---------------------------------------------------------

static func _norm(p: String) -> String:
	var s := p.replace("\\", "/")
	while s.length() > 1 and s.ends_with("/") and not s.ends_with(":/"):
		s = s.substr(0, s.length() - 1)
	return s


## Ein Ordner, in dem Aufräumen überhaupt etwas tun darf: absolut, ohne „..“ und nicht ein Laufwerk
## oder die oberste Ebene (mindestens zwei Ordner tief, wie …/AppData/…/Uzai).
static func data_dir_ok(data_dir: String) -> bool:
	var d := _norm(data_dir)
	if not d.is_absolute_path() or d.contains("://"):
		return false
	var segs := Array(d.split("/", false)).filter(func(x: String) -> bool: return not x.ends_with(":"))
	return segs.size() >= 2 and not segs.has("..") and not segs.has(".")


## Ordner eines Aufräum-Eintrags (absolut), "" für unbekannte Kennungen.
static func clean_root(data_dir: String, id: String) -> String:
	for c in CLEAN:
		if c[0] == id:
			return _norm(data_dir).path_join(str(c[2]))
	return ""


## Darf Aufräumen diese Datei löschen? Nur unter einem der Aufräum-Ordner von Uzais Datenordner,
## ohne „..“ oder „.“ im Pfad, nie ein Ordner selbst. Groß-/Kleinschreibung muss stimmen (die Pfade
## baut Uzai selbst; was abweicht, kommt von woanders und bleibt).
static func may_delete(path: String, data_dir: String) -> bool:
	if not data_dir_ok(data_dir):
		return false
	var p := _norm(path)
	if p == "" or not p.is_absolute_path() or p.contains("://"):
		return false
	for seg in p.split("/", false):
		if seg == ".." or seg == ".":
			return false
	for b in CLEAN_BLEIBT:
		if p == _norm(data_dir).path_join(b):
			return false
	for c in CLEAN:
		var root := _norm(data_dir).path_join(str(c[2]))
		if p.begins_with(root + "/") and p.length() > root.length() + 1:
			return true
	return false


## Dateien, die ein Aufräum-Eintrag löschen würde: [[Pfad, Bytes], …]. Verknüpfungen (auch
## Abzweigungen unter Windows) werden nie verfolgt oder gelöscht; ist der Aufräum-Ordner selbst
## eine, gibt es nichts. „listen“ lässt die Bilder aus (eigener Eintrag). Höchstens max Dateien.
static func clean_files(data_dir: String, id: String, max_files := 200000) -> Array:
	var out: Array = []
	var root := clean_root(data_dir, id)
	if root == "" or not data_dir_ok(data_dir) or not DirAccess.dir_exists_absolute(root):
		return out
	if _through_link(root, data_dir, {}):
		return out
	var skip := clean_root(data_dir, "bilder") if id == "listen" else ""
	var stack: Array = [root]
	while not stack.is_empty() and out.size() < max_files and not Arbeit.endet:
		var d: String = stack.pop_back()
		if d == skip:
			continue
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.include_hidden = true
		for sub in da.get_directories():
			if not da.is_link(sub):
				stack.append(d.path_join(sub))
		for f in da.get_files():
			if da.is_link(f):
				continue
			var p := d.path_join(f)
			if may_delete(p, data_dir):
				out.append([p, maxi(0, FileAccess.get_size(p))])
	return out


static func files_bytes(files: Array) -> int:
	var n := 0
	for f in files:
		n += int(f[1])
	return n


## Liegt auf dem Weg vom Datenordner bis zu path (einschließlich) eine Verknüpfung oder Abzweigung?
## Dann zeigt der Pfad womöglich nach draußen. seen merkt sich geprüfte Ordner (viele Dateien
## liegen im selben). Was sich nicht prüfen lässt, gilt als Verknüpfung.
static func _through_link(path: String, data_dir: String, seen: Dictionary) -> bool:
	var base := _norm(data_dir)
	var p := _norm(path)
	if not p.begins_with(base + "/"):
		return true
	var walk := base
	for seg in p.trim_prefix(base + "/").split("/", false):
		var next := walk.path_join(seg)
		if not seen.has(next):
			var up := DirAccess.open(walk)
			seen[next] = up == null or up.is_link(seg)
		if seen[next]:
			return true
		walk = next
	return false


## Löscht genau diese Dateien (aus clean_files), jede vorher noch einmal geprüft – auch, dass kein
## Ordner auf dem Weg eine Verknüpfung ist. Ordner bleiben stehen. Gesperrte Dateien (gerade in
## Gebrauch) zählen als „übrig“. { freed, count, left }.
static func delete_files(files: Array, data_dir: String) -> Dictionary:
	var res := { "freed": 0, "count": 0, "left": 0 }
	var seen := {}
	for f in files:
		if Arbeit.endet:
			break
		var p := str(f[0])
		if not may_delete(p, data_dir) or _through_link(p, data_dir, seen) or not FileAccess.file_exists(p):
			res.left = int(res.left) + 1
			continue
		if DirAccess.remove_absolute(p) == OK:
			res.freed = int(res.freed) + int(f[1])
			res.count = int(res.count) + 1
		else:
			res.left = int(res.left) + 1
	return res
