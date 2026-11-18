extends RefCounted
## Durchsucht einen Ordner nach Spieldateien eines Systems. Dateien, die von einer
## .cue- oder .m3u-Datei schon abgedeckt werden, tauchen nicht doppelt auf. Mehrere
## Discs desselben Spiels werden zu einem Eintrag zusammengefasst.
## Dateien, die kein Emulator starten kann, kommen gar nicht erst in die Liste: leere (abgebrochener
## Download) und .cue/.gdi/.m3u, denen eine Spur oder Disc fehlt (problem()). scan_full nennt sie.

const Sicher := preload("res://src/core/sicher.gd")
const MAX_DEPTH := 5
const SHEET_MAX := 1024 * 1024       ## größer ist keine .cue, .gdi oder .m3u (nie ein ganzes Abbild als Text lesen)

## Beim Laden gefüllt, danach nur gelesen (der Scan läuft im Hilfsfaden; clean_title ruft auch der Hauptfaden).
static var _re_gdi := RegEx.create_from_string("^\\d+\\s+\\d+\\s+\\d+\\s+\\d+\\s+(?:\"([^\"]+)\"|(\\S+))")
static var _re_klammer := RegEx.create_from_string("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]")
static var _re_serie := RegEx.create_from_string(
		"(?i)^\\s*[SP][A-Z]{3}[-_. ]?\\d{3}\\.?\\d{2}(?!\\d)[\\s_.-]*|[\\s_.-]*\\b[SP][A-Z]{3}[-_. ]?\\d{3}\\.?\\d{2}\\s*$")


static func scan(system: Dictionary, dir: String) -> Array:
	return scan_full(system, dir)[0]


## [Spiele, übersprungen] – übersprungen: [{ path, why }] mit why „leer“ oder „unvollständig“.
static func scan_full(system: Dictionary, dir: String) -> Array:
	# Ein Trenner für alles: Mit „D:\ROMs“ passten die Verweise aus .cue/.m3u (immer mit „/“) früher
	# nicht zu den gefundenen Dateien – Spuren und einzelne Discs standen dann doppelt in der Liste.
	dir = dir.replace("\\", "/").trim_suffix("/")
	var exts: Array = system.get("extensions", [])
	var files: Array = []
	_walk(dir, exts, files, 0)
	files.sort()
	var covered := {}
	for f in files:
		var ext := str(f).get_extension().to_lower()
		if ext == "cue" or ext == "m3u" or ext == "gdi":
			for ref in _references(f):
				covered[_key(ref)] = true
	var by_title := {}
	var out: Array = []
	var skipped: Array = []
	for f in files:
		var p := str(f)
		if covered.has(_key(p)):
			continue
		var why := problem(p)
		if why != "":
			skipped.append({ "path": p, "why": why })
			continue
		var title := clean_title(p.get_file().get_basename())
		var key := title.to_lower()
		if by_title.has(key):
			var first: Dictionary = by_title[key]
			var discs: Array = first.get("discs", [first.path])
			discs.append(p)
			first["discs"] = discs
			continue
		var g := {
			"id": "%s:%s" % [system.id, p.md5_text().substr(0, 14)],
			"title": title,
			"system": system.id,
			"source": "rom",
			"path": p,
			"installed": true,
			"subdir": subdir_of(dir, p),
			"install_time": FileAccess.get_modified_time(p),
		}
		by_title[key] = g
		out.append(g)
	return [out, skipped]


## Nur ASCII im Namen? Umlaute in einer .cue (oft nicht UTF-8 gespeichert) liest Uzai womöglich
## anders, als Windows sie schreibt – eine solche Spur gilt im Zweifel als vorhanden.
static func _plain(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) > 126:
			return false
	return true


static func _key(p: String) -> String:
	return p.replace("\\", "/").simplify_path().to_lower()


## Kann ein Emulator die Datei überhaupt starten? "" ja, „leer“ (0 Byte – meist ein abgebrochener
## Download) oder „unvollständig“ (.cue/.gdi/.m3u ohne Verweis oder mit fehlender Spur/Disc).
static func problem(path: String) -> String:
	# Die Größe ohne Öffnen: Bei Tausenden Spieldateien kostet jedes Öffnen Zeit (unter Windows prüft dabei der
	# Virenschutz mit).
	var size := FileAccess.get_size(path)
	if size < 0:
		return "unvollständig"
	if size == 0:
		return "leer"
	var ext := path.get_extension().to_lower()
	if ext in ["cue", "gdi", "m3u"]:
		# Sehr große „.cue“ ist keine (sondern etwas anderes mit dieser Endung): nicht lesen.
		if size > SHEET_MAX:
			return ""
		var refs := _references(path)
		if refs.is_empty():
			return "unvollständig"
		for r in refs:
			if not FileAccess.file_exists(str(r)) and _plain(str(r).get_file()):
				return "unvollständig"
	return ""


## Erster Unterordner unter dem ROM-Ordner ("" wenn die Datei direkt darin liegt).
static func subdir_of(root: String, file: String) -> String:
	var r := root.replace("\\", "/").trim_suffix("/")
	var f := file.replace("\\", "/")
	if not f.begins_with(r + "/"):
		return ""
	var rel := f.substr(r.length() + 1)
	return rel.get_slice("/", 0) if rel.contains("/") else ""


static func _walk(dir: String, exts: Array, out: Array, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = false
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := dir.path_join(name)
			if da.current_is_dir():
				_walk(full, exts, out, depth + 1)
			elif name.get_extension().to_lower() in exts:
				out.append(full)
		name = da.get_next()
	da.list_dir_end()


## Dateien, auf die eine .cue (FILE "…"), .gdi (Spurzeilen) oder .m3u (eine je Zeile) zeigt.
static func _references(sheet: String) -> Array:
	var out: Array = []
	var base := sheet.get_base_dir()
	# Auch hier die Grenze (scan_full liest die Verweise aller Listen, bevor problem() die Größe prüft): Eine
	# mehrere GB große Datei mit dieser Endung läse Uzai sonst ganz in den Speicher.
	if FileAccess.get_size(sheet) > SHEET_MAX:
		return out
	var text := FileAccess.get_file_as_string(sheet)
	var ext := sheet.get_extension().to_lower()
	var re_gdi := _re_gdi
	for raw in text.split("\n"):
		# Ohne Byte-Order-Mark vorn (Windows-Editoren): sonst fehlte die erste Zeile.
		var line := raw.strip_edges().trim_prefix(char(0xFEFF)).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var ref := ""
		if ext == "cue":
			if line.to_upper().begins_with("FILE"):
				var a := line.find("\"")
				var b := line.rfind("\"")
				if a >= 0 and b > a:
					ref = line.substr(a + 1, b - a - 1)
				else:
					var parts := line.split(" ", false)
					ref = parts[1] if parts.size() >= 3 else ""
		elif ext == "gdi":
			# „1 0 4 2352 track01.bin 0“, Namen mit Leerzeichen in Anführungszeichen.
			var m := re_gdi.search(line)
			if m:
				ref = m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
		else:
			ref = line
		if ref != "":
			ref = ref.replace("\\", "/")
			ref = ref if ref.is_absolute_path() else base.path_join(ref).simplify_path()
			# Nie eine Windows-Freigabe (//server/…, \??\UNC\…): Schon das Nachsehen beim Einlesen schickte die
			# Windows-Anmeldung (NTLM) an den Rechner, den eine fremde .cue/.m3u nennt.
			# Liegt die Liste selbst auf einem NAS, gelten Verweise auf denselben Rechner (Sicher.verweis_ok).
			if Sicher.verweis_ok(ref, base):
				out.append(ref)
	return out


## "Legend of Zelda, The - The Minish Cap (Europe) (En,Fr,De) [!]" -> "The Legend of Zelda - The Minish Cap"
## "SLES-50330 Shadow of the Colossus" -> "Shadow of the Colossus" (PS-Seriennummer für die
## Disc-Erkennung im Dateinamen, im Titel stört sie).
static func clean_title(stem: String) -> String:
	var t := _re_klammer.sub(stem, "", true)
	var without := _re_serie.sub(t, "", true).strip_edges()
	if without != "":
		t = without
	t = t.replace("_", " ").strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	var sep := t.find(" - ")
	var head := t if sep < 0 else t.substr(0, sep)
	var tail := "" if sep < 0 else t.substr(sep)
	for art in [", The", ", Die", ", Der", ", Das", ", A", ", An"]:
		if head.ends_with(art):
			head = art.substr(2) + " " + head.substr(0, head.length() - art.length())
			break
	t = head + tail
	return t if t != "" else stem
