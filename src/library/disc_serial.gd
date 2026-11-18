extends RefCounted
## Seriennummern von PS1/PS2-Discs (SLES-50330 …). Sie stehen in SYSTEM.CNF der Disc und genauso im
## gerippten Abbild – darüber findet Uzai zu einer eingelegten Disc das passende Spiel aus der
## Bibliothek. Gibt es ein Abbild, startet es; sonst spielt Uzai die Disc direkt (src/core/discs.gd).
##
## Reihenfolge je Abbild: erst der Dateiname („SLES-50330 Spielname.cue“), sonst das Abbild selbst
## (ISO9660 in .iso/.img/.bin, die .cue zeigt auf die .bin). .chd, .cso, .pbp usw. sind gepackt
## und werden nur über den Dateinamen erkannt.

const Sicher := preload("res://src/core/sicher.gd")
const SYSTEMS := ["ps1", "ps2"]
## Sektoraufbau: [Sektorgröße, Beginn der 2048 Nutzdaten]. .iso hat reine 2048er-Sektoren,
## .bin Rohsektoren mit 2352 Bytes (Mode 2: Daten ab Byte 24, Mode 1: ab Byte 16).
const LAYOUTS := [[2048, 0], [2352, 24], [2352, 16]]
const READABLE := ["iso", "img", "bin"]
const CNF_MAX := 4096
const DIR_SECTORS_MAX := 32

const SHEET_MAX := 1024 * 1024       ## größer ist keine .cue oder .m3u (nie ein ganzes Abbild als Text lesen)

## Beim Laden gefüllt und danach nur gelesen: index() läuft im Hilfsfaden des Bibliotheks-Scans, normalize() zugleich
## im Hauptfaden. (Vorher wurden die Muster beim ersten Aufruf angelegt – ein zweiter Faden konnte sie halb fertig
## sehen und fand dann keine Nummer.)
## Vier Buchstaben, dann drei und zwei Ziffern; dazwischen _ - . oder Leerzeichen:
## „SLES_503.30;1“, „SLES-50330“, „sles 503.30“.
static var _re_any := RegEx.create_from_string("([A-Z]{4})[_\\-. ]?(\\d{3})\\.?(\\d{2})(?!\\d)")
## Im Dateinamen strenger: Anfang S oder P (SLES, SCUS, SLPM, PBPX …) und kein Buchstabe oder
## keine Ziffer davor, damit Wörter im Spieltitel nicht als Nummer durchgehen.
static var _re_name := RegEx.create_from_string("(?<![A-Z0-9])([SP][A-Z]{3})[_\\-. ]?(\\d{3})\\.?(\\d{2})(?!\\d)")


## Beliebige Schreibweise → „XXXX-12345“ ("" wenn keine Nummer darin steht).
static func normalize(text: String) -> String:
	var m := _re_any.search(text.to_upper())
	return "" if m == null else "%s-%s%s" % [m.get_string(1), m.get_string(2), m.get_string(3)]


## Nummer aus dem Dateinamen („SLES-50330 Shadow of the Colossus.iso“).
static func from_name(path: String) -> String:
	var m := _re_name.search(path.replace("\\", "/").get_file().to_upper())
	return "" if m == null else "%s-%s%s" % [m.get_string(1), m.get_string(2), m.get_string(3)]


## SYSTEM.CNF lesen: PS2 „BOOT2 = cdrom0:\SLES_503.30;1“, PS1 „BOOT = cdrom:\SLES_503.30;1“.
## Ergebnis { serial, system } – beides "", wenn keine Nummer drinsteht.
static func from_cnf(text: String) -> Dictionary:
	var boot := ""
	var boot2 := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges().to_upper()
		var val := line.substr(eq + 1).strip_edges()
		if key == "BOOT2":
			boot2 = val
		elif key == "BOOT":
			boot = val
	var v := boot2 if boot2 != "" else boot
	if v == "":
		return { "serial": "", "system": "" }
	# Nur der Dateiname hinter „cdrom0:\“ bzw. „cdrom:“.
	var cut := maxi(v.rfind("\\"), v.rfind(":"))
	var s := normalize(v.substr(cut + 1) if cut >= 0 else v)
	return { "serial": s, "system": ("ps2" if boot2 != "" else "ps1") if s != "" else "" }


## Nummer eines Abbilds: Dateiname zuerst, sonst SYSTEM.CNF aus dem Abbild.
static func of_file(path: String) -> String:
	var s := from_name(path)
	return s if s != "" else from_image(path)


static func from_image(path: String, depth := 0) -> String:
	var ext := path.get_extension().to_lower()
	if ext in READABLE:
		return from_cnf(read_cnf(path)).serial
	if ext == "cue":
		var bin := cue_data_file(path)
		return from_cnf(read_cnf(bin)).serial if bin != "" else ""
	if ext == "m3u" and depth < 2:
		for ref in sheet_files(path):
			var s := of_file(str(ref))
			if s != "":
				return s
	return ""


## Erste Datei aus einer .cue (Spur 1, die Daten).
static func cue_data_file(cue: String) -> String:
	var refs := sheet_files(cue)
	return str(refs[0]) if not refs.is_empty() else ""


## Dateien, auf die eine .cue (FILE "…") oder .m3u (eine je Zeile) zeigt.
static func sheet_files(sheet: String) -> Array:
	var out: Array = []
	var base := sheet.get_base_dir()
	var is_cue := sheet.get_extension().to_lower() == "cue"
	var groesse := FileAccess.get_size(sheet)
	if groesse <= 0 or groesse > SHEET_MAX:
		return out
	for raw in FileAccess.get_file_as_string(sheet).split("\n"):
		var line := raw.strip_edges().trim_prefix(char(0xFEFF)).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var ref := ""
		if is_cue:
			if line.to_upper().begins_with("FILE"):
				var a := line.find("\"")
				var b := line.rfind("\"")
				if a >= 0 and b > a:
					ref = line.substr(a + 1, b - a - 1)
				else:
					var parts := line.split(" ", false)
					ref = parts[1] if parts.size() >= 3 else ""
		else:
			ref = line
		if ref != "":
			ref = ref if ref.is_absolute_path() else base.path_join(ref).simplify_path()
			# Nie eine Windows-Freigabe: read_cnf öffnete sie sonst (NTLM an einen fremden Rechner, wie rom_scanner).
			# Derselbe Rechner wie die Liste (NAS) ist erlaubt, ein anderer nie (Sicher.verweis_ok).
			if Sicher.verweis_ok(ref, base):
				out.append(ref)
	return out


## SYSTEM.CNF aus dem Wurzelverzeichnis eines ISO9660-Abbilds ("" wenn keins oder kein ISO).
## Probiert reine 2048er-Sektoren und Rohsektoren (2352, Mode 2 und Mode 1).
static func read_cnf(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	for lay in LAYOUTS:
		var pvd := _sector(f, 16, lay)
		if pvd.size() == 2048 and pvd[0] == 1 and pvd.slice(1, 6).get_string_from_ascii() == "CD001":
			return _find_root_file(f, lay, pvd, "SYSTEM.CNF")
	return ""


static func _sector(f: FileAccess, lba: int, lay: Array) -> PackedByteArray:
	var pos := lba * int(lay[0]) + int(lay[1])
	if lba < 0 or pos + 2048 > f.get_length():
		return PackedByteArray()
	f.seek(pos)
	return f.get_buffer(2048)


## Eintrag im Wurzelverzeichnis suchen und seinen Inhalt (höchstens CNF_MAX Bytes) lesen.
static func _find_root_file(f: FileAccess, lay: Array, pvd: PackedByteArray, want: String) -> String:
	# Der Eintrag des Wurzelverzeichnisses steht im Primärdeskriptor ab Byte 156.
	var root_lba := pvd.decode_u32(158)
	var root_len := pvd.decode_u32(166)
	var sectors := mini(DIR_SECTORS_MAX, ceili(root_len / 2048.0))
	for k in sectors:
		var sec := _sector(f, root_lba + k, lay)
		if sec.is_empty():
			return ""
		var i := 0
		while i + 34 <= 2048:
			var rec_len := sec[i]
			if rec_len == 0:
				break
			var name_len := sec[i + 32]
			if i + 33 + name_len > 2048:
				break
			var name := sec.slice(i + 33, i + 33 + name_len).get_string_from_ascii().to_upper().get_slice(";", 0)
			if name == want:
				return _read_extent(f, lay, sec.decode_u32(i + 2), mini(CNF_MAX, sec.decode_u32(i + 10)))
			i += rec_len
	return ""


static func _read_extent(f: FileAccess, lay: Array, lba: int, size: int) -> String:
	var out := PackedByteArray()
	var k := 0
	while out.size() < size:
		var sec := _sector(f, lba + k, lay)
		if sec.is_empty():
			break
		out.append_array(sec)
		k += 1
	return out.slice(0, size).get_string_from_ascii()


## Dateien eines Spiels, die eine Disc sein können (mehrere Discs, .m3u mit ihren Einträgen).
static func files_of(g: Dictionary) -> Array:
	var out: Array = []
	var paths: Array = g.get("discs", []) if g.get("discs") is Array else []
	if paths.is_empty():
		paths = [str(g.get("path", ""))]
	for p in paths:
		var ps := str(p)
		if ps == "":
			continue
		out.append(ps)
		if ps.get_extension().to_lower() == "m3u":
			out.append_array(sheet_files(ps))
	return out


static func is_disc_game(g: Dictionary) -> bool:
	return str(g.get("source", "")) == "rom" and str(g.get("system", "")) in SYSTEMS and not bool(g.get("missing", false))


## Seriennummern aller Dateien; cache { pfad: { serial, size, mtime } }. Geöffnet werden nur neue
## oder geänderte Dateien (Größe oder Änderungszeit anders). Läuft im Hintergrund-Thread des
## Bibliotheks-Scans; gibt [neuer Cache] zurück.
static func index(paths: Array, cache: Dictionary) -> Array:
	var out := {}
	for p in paths:
		var path := str(p)
		if out.has(path):
			continue
		var size := FileAccess.get_size(path)
		if size < 0:
			continue
		var mtime := FileAccess.get_modified_time(path)
		var old: Variant = cache.get(path)
		if old is Dictionary and int(old.get("size", -1)) == size and int(old.get("mtime", -1)) == mtime:
			out[path] = old
			continue
		out[path] = { "serial": of_file(path), "size": size, "mtime": mtime }
	return [out]
