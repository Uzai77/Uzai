extends RefCounted
## Pakete zum Weitergeben (heute: „Zimmer teilen“, src/room/zimmer_teilen.gd): ein schlichtes ZIP
## schreiben, das Inhaltsverzeichnis eines fremden ZIP streng prüfen, bevor ein Byte entpackt wird,
## und nur in Uzais eigene Ordner schreiben – nie über eine Verknüpfung. Pakete tragen nur Daten,
## nie Code. (Früher teilten sich Themes und Zimmer diese Helfer; Themes gibt es nicht mehr.)

const Zip := preload("res://src/core/zip_pruefung.gd")

## Grenzen: Gezählt wird, was das Verzeichnis verspricht – und genau so viel Platz bekommt der
## Entpacker, mehr nicht (eine „ZIP-Bombe“ läuft ins Leere).
const MAX_DATEIEN := 64
const MAX_GESAMT := 64 * 1024 * 1024
const MAX_RATE := 120                 ## entpackt höchstens so viel mal größer als gepackt
const MAX_JSON := 256 * 1024


# --- Lesen ----------------------------------------------------------------------------------------

## Inhaltsverzeichnis eines ZIP prüfen, ohne zu entpacken (zip_pruefung.gd). haupt: die Pflichtdatei
## (JSON, höchstens MAX_JSON); erlaubt: weitere Dateien, genau diese Namen (Name → Größengrenze).
## Ordner, andere Namen, Doppelte, Verknüpfungen und Verschlüsseltes werden abgelehnt.
## Ergebnis: { ok, error, entries: [{ name, method, crc, csize, usize, data_at }] }.
static func verzeichnis(b: PackedByteArray, haupt: String, erlaubt: Dictionary = {}) -> Dictionary:
	var name_ok := func(name: String, ordner: bool) -> String:
		if ordner:
			return "ordner"
		return "" if name == haupt or erlaubt.has(name) else "name"
	var grenze := func(name: String) -> int:
		return MAX_JSON if name == haupt else int(erlaubt[name])
	var r := Zip.verzeichnis(b, { "max_eintraege": MAX_DATEIEN * 2, "max_dateien": MAX_DATEIEN, "max_name": 200, "utf8": false,
		"name_ok": name_ok, "grenze": grenze, "rate_ab": 4096, "max_rate": MAX_RATE, "max_gesamt": MAX_GESAMT })
	if bool(r.ok) and not (r.entries as Array).any(func(e: Dictionary) -> bool: return str(e.name) == haupt):
		r = { "ok": false, "fehler": "leer", "name": "" }
	if not bool(r.ok):
		return { "ok": false, "error": _zip_text(r, haupt), "entries": [] }
	return { "ok": true, "error": "", "entries": r.entries }


## Satz zu einem Fehler des ZIP-Lesers (für Protokoll und Tests; der Nutzer liest einen kürzeren).
static func _zip_text(r: Dictionary, haupt: String) -> String:
	var name := str(r.name)
	match str(r.fehler):
		"kein_zip":
			return "Das ist kein Paket (kein ZIP)."
		"zip64":
			return "Geteilte oder ZIP64-Pakete kann Uzai nicht lesen."
		"zu_viele":
			return "Das Paket enthält zu viele Dateien (höchstens %d)." % MAX_DATEIEN
		"name_kodierung":
			return "Ein Dateiname im Paket ist nicht erlaubt."
		"name":
			return "Ein Dateiname im Paket ist nicht erlaubt: %s" % name.c_escape()
		"ordner":
			return "Ein Ordner im Paket ist nicht erlaubt: %s" % name.c_escape()
		"doppelt":
			return "Eine Datei steht doppelt im Paket: %s" % name
		"verschluesselt":
			return "Verschlüsselte Pakete kann Uzai nicht lesen."
		"verknuepfung":
			return "Das Paket enthält eine Verknüpfung: %s" % name
		"verfahren":
			return "„%s“ ist mit einem Verfahren gepackt, das Uzai nicht liest." % name
		"zu_gross_datei":
			return "„%s“ ist zu groß (höchstens %d KB)." % [name, int(r.grenze) / 1024]
		"packrate":
			return "„%s“ ist ungewöhnlich stark gepackt – Uzai liest es nicht." % name
		"zu_gross":
			return "Das Paket ist entpackt zu groß (höchstens %d MB)." % (MAX_GESAMT / 1048576)
		"leer":
			return "Im Paket fehlt %s." % haupt
	return "Das Paket ist beschädigt."


# --- Schreiben ------------------------------------------------------------------------------------

## Ist dieser Pfad eine Verknüpfung (Symlink, unter Windows auch Junction)?
static func is_link(path: String) -> bool:
	var d := DirAccess.open(path.get_base_dir())
	return d != null and d.is_link(path.get_file())


## Ordner anlegen; keiner der Ordner ab base darf eine Verknüpfung sein. "" = gut, sonst der Grund.
static func safe_dir(base: String, dir: String) -> String:
	# Der Ordner selbst oder einer darunter – nicht bloß derselbe Anfang („…/Uzai2“ liegt daneben).
	if base == "" or not (dir == base or dir.begins_with(base.trim_suffix("/") + "/")):
		return "Uzai schreibt nur in seine eigenen Ordner."
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir
	while p.length() >= base.length() and p != "":
		if is_link(p):
			return "Der Ordner ist eine Verknüpfung – Uzai schreibt dort nicht."
		if p == base:
			break
		p = p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return "Uzai kann den Ordner nicht anlegen."
	return ""


## Uzais eigener Ordner zum Weitergeben: Dokumente\Uzai (in Tests und ohne Dokumente-Ordner der
## Datenordner). Geschrieben wird nur ab hier.
static func export_basis() -> String:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if OS.get_environment("UZAI_DATA") != "" or docs == "":
		return Config.path("export")
	return docs.path_join("Uzai")


## Ein ZIP aus [[Name, Bytes], …] – so schlicht wie möglich: keine Ordner-Einträge, keine
## Erweiterungen, feste Zeit, Deflate oder (wenn es nichts bringt oder für den Prüfer zu stark
## gepackt wäre) gespeichert. Prüfsummen selbst gerechnet.
static func zip(entries: Array) -> PackedByteArray:
	var out := PackedByteArray()
	var central := PackedByteArray()
	var date := ((2026 - 1980) << 9) | (1 << 5) | 1
	for e in entries:
		var name := str(e[0])
		var data: PackedByteArray = e[1]
		var nb := name.to_ascii_buffer()
		var crc := Zip.crc32(data)
		var method := 0
		var body := data
		var packed := deflate(data)
		if not packed.is_empty() and packed.size() < data.size() and not (data.size() > 4096 and data.size() > packed.size() * (MAX_RATE - 10)):
			method = 8
			body = packed
		var at := out.size()
		var lh := PackedByteArray()
		lh.resize(30)
		lh.encode_u32(0, 0x04034b50)
		lh.encode_u16(4, 20)
		lh.encode_u16(6, 0)
		lh.encode_u16(8, method)
		lh.encode_u16(10, 0)
		lh.encode_u16(12, date)
		lh.encode_u32(14, crc)
		lh.encode_u32(18, body.size())
		lh.encode_u32(22, data.size())
		lh.encode_u16(26, nb.size())
		lh.encode_u16(28, 0)
		out.append_array(lh)
		out.append_array(nb)
		out.append_array(body)
		var ch := PackedByteArray()
		ch.resize(46)
		ch.encode_u32(0, 0x02014b50)
		ch.encode_u16(4, 20)
		ch.encode_u16(6, 20)
		ch.encode_u16(8, 0)
		ch.encode_u16(10, method)
		ch.encode_u16(12, 0)
		ch.encode_u16(14, date)
		ch.encode_u32(16, crc)
		ch.encode_u32(20, body.size())
		ch.encode_u32(24, data.size())
		ch.encode_u16(28, nb.size())
		ch.encode_u16(30, 0)
		ch.encode_u16(32, 0)
		ch.encode_u16(34, 0)
		ch.encode_u16(36, 0)
		ch.encode_u32(38, 0)
		ch.encode_u32(42, at)
		central.append_array(ch)
		central.append_array(nb)
	var cd_at := out.size()
	out.append_array(central)
	var eo := PackedByteArray()
	eo.resize(22)
	eo.encode_u32(0, 0x06054b50)
	eo.encode_u16(8, entries.size())
	eo.encode_u16(10, entries.size())
	eo.encode_u32(12, central.size())
	eo.encode_u32(16, cd_at)
	out.append_array(eo)
	return out


## Rohes Deflate über den GZIP-Packer der Engine: Kopf (10 Bytes) und Schluss (8 Bytes) ab.
## Leer, wenn der Kopf nicht die erwartete schlichte Form hat.
static func deflate(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()
	var gz := data.compress(FileAccess.COMPRESSION_GZIP)
	if gz.size() < 18 or gz[0] != 0x1f or gz[1] != 0x8b or gz[2] != 8 or gz[3] != 0:
		return PackedByteArray()
	if gz.decode_u32(gz.size() - 4) != data.size() & 0xffffffff or gz.decode_u32(gz.size() - 8) != Zip.crc32(data):
		return PackedByteArray()
	return gz.slice(10, gz.size() - 8)
