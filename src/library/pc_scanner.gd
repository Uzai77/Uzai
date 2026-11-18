extends RefCounted
## Liest einen Ordner mit PC-Spielen: Verknüpfungen (.lnk), Internet-Verknüpfungen (.url,
## zum Beispiel von GOG Galaxy, Battle.net, Xbox-App) und Programme (.exe). Unterordner werden
## eine Ebene tief durchsucht. Verknüpfungen löst Uzai beim Einlesen über den Windows-Helfer auf.

const SKIP_EXE := ["unins000", "uninstall", "setup", "vcredist", "dxsetup", "crashreporter", "unitycrashhandler64", "ue4prereqsetup_x64", "launcher_helper"]


static func scan(dirs: Array) -> Array:
	var out: Array = []
	for d in dirs:
		var dir := str(d)
		if dir == "" or not DirAccess.dir_exists_absolute(dir):
			continue
		_walk(dir, out, 0)
	return out


static func _walk(dir: String, out: Array, depth: int) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		var ext := f.get_extension().to_lower()
		var full := dir.path_join(f)
		if ext == "lnk" or ext == "url" or (ext == "exe" and depth == 0):
			if ext == "exe" and f.get_basename().to_lower() in SKIP_EXE:
				continue
			var g := entry(full)
			if ext == "url":
				var url := read_url(full)
				if not url_ok(url):
					continue
				# Steam-Verknüpfungen kennt Uzai schon aus der Steam-Bibliothek.
				if url.begins_with("steam://rungameid/"):
					continue
				g["url"] = url
			out.append(g)
	if depth < 1:
		for sub in da.get_directories():
			if not sub.begins_with("."):
				_walk(dir.path_join(sub), out, depth + 1)


static func entry(path: String) -> Dictionary:
	return {
		"id": "pc:%s" % path.md5_text().substr(0, 14),
		"title": clean_name(path.get_file().get_basename()),
		"system": "pc", "source": "pc", "path": path,
		"install_dir": path.get_base_dir(), "installed": true, "scanned": true,
		"install_time": FileAccess.get_modified_time(path),
	}


static func clean_name(n: String) -> String:
	for suffix in [" - Verknüpfung", " - Shortcut", " – Verknüpfung", ".exe"]:
		n = n.trim_suffix(suffix)
	return n.replace("_", " ").strip_edges()


## Starter von Spiele-Läden, deren Internet-Verknüpfungen Uzai als Spiel annimmt (GOG Galaxy, Battle.net, Xbox-App …).
## Nur diese: Eine .url in einem entpackten Spielordner kann sonst auf file://, \\server\… oder ms-…-Protokolle zeigen,
## und Uzai öffnete sie ohne die Rückfrage, die im Explorer käme.
const URL_SCHEMATA := ["steam", "com.epicgames.launcher", "goggalaxy", "battlenet", "uplay", "origin", "origin2", "eadesktop",
	"link2ea", "itch", "amazon-games", "riotclient", "msgamelaunch", "xbox", "heroic", "playnite"]


## Darf Uzai dieses Ziel einer .url öffnen? (Beim Einlesen, beim Hinzufügen und noch einmal beim Start.)
static func url_ok(url: String) -> bool:
	var i := url.find("://")
	if i <= 0 or url.length() > 2048 or url.contains("\\"):
		return false
	for ch in url:
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127:
			return false
	var schema := url.left(i).to_lower()
	# Steam nimmt in steam://run/<id>//<Parameter> Startparameter an: nur die blanke Spielnummer (bei Nicht-Steam-Spielen
	# eine 64-Bit-Zahl, bis 20 Stellen).
	if schema == "steam":
		return _RX_STEAM.search(url) != null
	return schema in URL_SCHEMATA


static var _RX_STEAM := RegEx.create_from_string("^steam://(rungameid|run)/[0-9]{1,20}/?$")


## Ziel einer .url-Datei (INI-Format: URL=…).
static func read_url(path: String) -> String:
	# Eine Internet-Verknüpfung ist winzig; etwas Großes mit dieser Endung liest Uzai nicht ein.
	var groesse := FileAccess.get_size(path)
	if groesse <= 0 or groesse > 64 * 1024:
		return ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l := line.strip_edges()
		if l.to_upper().begins_with("URL="):
			return l.substr(4)
	return ""
