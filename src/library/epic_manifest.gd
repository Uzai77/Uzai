extends RefCounted
## Epic-Manifeste und -Chunks lesen (rein, ohne Netz und ohne Dateien) – für Uzais eigenen
## Installer gekaufter Epic-Spiele (epic_install.gd), nach dem Vorbild der freien Launcher Legendary
## und Heroic. Eigene Umsetzung des Formats; alles Fremde gilt als feindlich:
## - Manifest binär (Kopf, Meta, Chunk-Liste, Datei-Liste) oder als altes JSON mit „Blob“-Zahlen,
## - Größen- und Mengengrenzen vor jedem Anlegen, jede Länge gegen den Rest geprüft,
## - Pfade nur relativ, ohne „..“, Laufwerke, Datenströme, Gerätenamen und Verknüpfungen, keine
##   doppelten Namen (auch nicht in anderer Schreibweise), keine Datei, die wie ein Ordner heißt,
## - SHA-1 des Manifests (Kopf und laut Epics Antwort), jedes Chunks und jeder Datei ist Pflicht,
## - verschlüsselte Manifeste und Chunks (Vorab-Downloads) lehnt Uzai ab – die gehen nur im
##   Epic Games Launcher; Kopierschutz umgeht Uzai nie.
## Adressen: Epics Antwort mit den Manifest-Adressen, nur https zu Epics Download-Servern.

const EpicOnline := preload("res://src/library/epic_online.gd")
const MAGIC := 0x44BEC00C
const CHUNK_MAGIC := 0xB1FE3AA2
## Grenzen (großzügig über allem, was echte Spiele brauchen).
const MAX_MANIFEST := 96 * 1024 * 1024        ## geladenes Manifest
const MAX_RAW := 512 * 1024 * 1024            ## Manifest entpackt
const MAX_CHUNKS := 4000000
const MAX_FILES := 1000000
const MAX_PARTS := 8000000
const MAX_WINDOW := 16 * 1024 * 1024          ## ein Chunk entpackt (echt: 1 MiB)
const MAX_FILE := 1024 * 1024 * 1024 * 1024    ## eine Datei (1 TiB)
const MAX_TOTAL := 8 * 1024 * 1024 * 1024 * 1024   ## ein Spiel (8 TiB)
const MAX_NAME := 1024                        ## Zeichen je Pfad
const MAX_STR := 65536                        ## Zeichen je anderem Text
## Epics Download-Server (aus Epics Antwort; andere Hosts lädt Uzai nie).
const CDN_HOSTS := ["epicgames-download1.akamaized.net", "download.epicgames.com", "download2.epicgames.com",
	"download3.epicgames.com", "download4.epicgames.com", "fastly-download.epicgames.com", "cloudflare.epicgamescdn.com"]
const CDN_SUFFIXES := [".epicgames.com", ".epicgamescdn.com"]
const RESERVED := ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$", "COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7",
	"COM8", "COM9", "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
const ZERO_SHA := "0000000000000000000000000000000000000000"


## Liest kleine Ganzzahlen und Epics Texte aus einem Puffer; jede Länge wird vorher geprüft
## (bad ist danach gesetzt, alles Weitere liefert 0 bzw. "").
class Rd:
	var b: PackedByteArray
	var p := 0
	var bad := ""

	func _init(data: PackedByteArray, at := 0) -> void:
		b = data
		p = at

	func left() -> int:
		return b.size() - p

	func need(n: int) -> bool:
		if bad != "":
			return false
		if n < 0 or p + n > b.size():
			bad = "kaputt"
			return false
		return true

	func u8() -> int:
		if not need(1):
			return 0
		p += 1
		return b[p - 1]

	func u32() -> int:
		if not need(4):
			return 0
		p += 4
		return b.decode_u32(p - 4)

	func s32() -> int:
		if not need(4):
			return 0
		p += 4
		return b.decode_s32(p - 4)

	func s64() -> int:
		if not need(8):
			return 0
		p += 8
		return b.decode_s64(p - 8)

	func raw(n: int) -> PackedByteArray:
		if not need(n):
			return PackedByteArray()
		p += n
		return b.slice(p - n, p)

	## Epics FString: Länge mit Endnull; negativ = UTF-16 (Zeichen), positiv = 8 Bit.
	func fstr(max_chars: int) -> String:
		var n := s32()
		if n == 0 or bad != "":
			return ""
		if n < 0:
			var chars := -n
			if chars > max_chars + 1 or not need(chars * 2):
				bad = "kaputt" if bad == "" else bad
				return ""
			var s := b.slice(p, p + chars * 2 - 2).get_string_from_utf16() if chars > 1 else ""
			p += chars * 2
			return s
		if n > max_chars + 1 or not need(n):
			bad = "kaputt" if bad == "" else bad
			return ""
		var t := b.slice(p, p + n - 1).get_string_from_ascii() if n > 1 else ""
		p += n
		return t

	func seek(to: int) -> void:
		if to < p or to > b.size():
			bad = "kaputt" if bad == "" else bad
			return
		p = to


# --- Manifest ---------------------------------------------------------------------------------

## Manifest (binär oder JSON) → { ok, error, m }. error ist ein kurzer Code: zu_gross, kaputt,
## pruefsumme, verschluesselt, pfad, verknuepfung, doppelt, grenze, leer.
## m: { feature, app, build, exe, args, prereq_name, prereq_path, prereq_args, chunks: [{ g, path,
## sha, win, size }], index: { GUID → Nummer }, files: [{ name, sha, flags, size, parts: [[Chunk,
## Versatz im Chunk, Länge], …] }], total (Bytes der Dateien), download (Bytes aller Chunks) }.
static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_MANIFEST:
		return _no("zu_gross")
	if data.size() < 4:
		return _no("kaputt")
	var r: Dictionary
	if data[0] == 0x7B:
		r = parse_json(data)
	else:
		r = parse_binary(data)
	if not bool(r.ok):
		return r
	var why := check(r.m)
	return r if why == "" else _no(why)


static func _no(code: String) -> Dictionary:
	return { "ok": false, "error": code, "m": {} }


static func parse_binary(data: PackedByteArray) -> Dictionary:
	var h := Rd.new(data)
	if h.u32() != MAGIC:
		return _no("kaputt")
	var head_size := h.u32()
	var size_raw := h.u32()
	var size_packed := h.u32()
	var sha := h.raw(20).hex_encode()
	var stored := h.u8()
	var version := h.u32()
	if h.bad != "" or head_size < 41 or head_size > 4096 or head_size > data.size():
		return _no("kaputt")
	if stored & 0x2:
		return _no("verschluesselt")
	if stored & ~0x3:
		return _no("kaputt")
	if size_raw <= 0 or size_raw > MAX_RAW or version <= 0 or version > 1000:
		return _no("grenze" if size_raw > MAX_RAW else "kaputt")
	var body := data.slice(head_size)
	if stored & 0x1:
		if size_packed != body.size() or body.is_empty():
			return _no("kaputt")
		body = body.decompress(size_raw, FileAccess.COMPRESSION_DEFLATE)
		if body.size() != size_raw:
			return _no("kaputt")
	elif body.size() != size_raw:
		return _no("kaputt")
	if sha != ZERO_SHA and sha1_hex(body) != sha:
		return _no("pruefsumme")
	if stored & 0x1 and sha == ZERO_SHA:
		return _no("pruefsumme")
	return _body(body)


## Inhalt nach dem Kopf: Meta, Chunk-Liste, Datei-Liste (der Rest – eigene Felder, verschlüsselte
## Teile – braucht Uzai nicht).
static func _body(body: PackedByteArray) -> Dictionary:
	var r := Rd.new(body)
	var m := {}
	var meta_size := r.u32()
	var data_version := r.u8()
	var feature := r.u32()
	r.u8()                                   # is_file_data (nur sehr alte Manifeste)
	r.u32()                                  # app_id
	m["feature"] = feature
	m["app"] = r.fstr(MAX_NAME)
	m["build"] = r.fstr(MAX_NAME)
	m["exe"] = r.fstr(MAX_NAME)
	m["args"] = r.fstr(MAX_STR)
	var prereqs := r.u32()
	if prereqs > 64:
		return _no("grenze")
	for i in prereqs:
		r.fstr(MAX_NAME)
	m["prereq_name"] = r.fstr(MAX_NAME)
	m["prereq_path"] = r.fstr(MAX_NAME)
	m["prereq_args"] = r.fstr(MAX_STR)
	if data_version >= 1:
		r.fstr(MAX_NAME)                     # Build-ID
	if data_version >= 2:
		r.fstr(MAX_NAME)                     # Deinstallieren: Programm und Parameter (führt Uzai nie aus)
		r.fstr(MAX_STR)
	if r.bad != "" or meta_size < r.p or meta_size > body.size() or feature <= 0 or feature > 1000:
		return _no("kaputt")
	r.seek(meta_size)
	var cdl := _chunk_list(r, feature)
	if not bool(cdl.ok):
		return cdl
	m["chunks"] = cdl.chunks
	m["index"] = cdl.index
	var fml := _file_list(r, cdl.index)
	if not bool(fml.ok):
		return fml
	m["files"] = fml.files
	return { "ok": true, "error": "", "m": m }


static func _chunk_list(r: Rd, feature: int) -> Dictionary:
	var start := r.p
	var size := r.u32()
	r.u8()                                   # Version der Liste
	var n := r.u32()
	if r.bad != "" or size < 9 or size > r.b.size() - start:
		return _no("kaputt")
	if n > MAX_CHUNKS:
		return _no("grenze")
	# Je Chunk mindestens 57 Bytes (ab Fassung 22: 93) – sonst passt die Liste nicht.
	var per := 93 if feature >= 22 else 57
	if n * per > size - 9:
		return _no("kaputt")
	var guids := PackedStringArray()
	var raw_guids: Array = []
	guids.resize(n)
	for i in n:
		var gb := r.raw(16)
		raw_guids.append(gb)
		guids[i] = "%08X%08X%08X%08X" % [gb.decode_u32(0), gb.decode_u32(4), gb.decode_u32(8), gb.decode_u32(12)]
	var hashes: Array = []
	for i in n:
		hashes.append(r.raw(8))
	var shas := PackedStringArray()
	shas.resize(n)
	for i in n:
		shas[i] = r.raw(20).hex_encode()
	var groups := PackedInt32Array()
	groups.resize(n)
	for i in n:
		groups[i] = r.u8()
	var wins := PackedInt64Array()
	wins.resize(n)
	for i in n:
		wins[i] = r.u32()
	var sizes := PackedInt64Array()
	sizes.resize(n)
	for i in n:
		sizes[i] = r.s64()
	if feature >= 22:
		for i in n:
			# Schlüssel-Kennung: gesetzt = verschlüsselter Chunk.
			if r.raw(16) != PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]):
				return _no("verschluesselt")
		for i in n:
			r.u32()
		for i in n:
			r.raw(16)
	if r.bad != "" or r.p - start > size:
		return _no("kaputt")
	r.seek(start + size)
	var chunks: Array = []
	var index := {}
	for i in n:
		var g := guids[i]
		if index.has(g):
			return _no("doppelt")
		index[g] = i
		var w := wins[i]
		if w <= 0 or w > MAX_WINDOW or sizes[i] <= 0 or sizes[i] > w + 4096 or groups[i] > 99:
			return _no("grenze")
		chunks.append({ "g": g, "path": chunk_path(feature, groups[i], hashes[i], raw_guids[i]), "sha": shas[i], "win": w, "size": sizes[i] })
	return { "ok": true, "chunks": chunks, "index": index }


static func _file_list(r: Rd, index: Dictionary) -> Dictionary:
	var start := r.p
	var size := r.u32()
	var version := r.u8()
	var n := r.u32()
	if r.bad != "" or size < 9 or size > r.b.size() - start:
		return _no("kaputt")
	if n > MAX_FILES:
		return _no("grenze")
	# Je Datei mindestens 37 Bytes (Name, Ziel, SHA-1, Kennzeichen, zwei Zähler).
	if n * 37 > size - 9:
		return _no("kaputt")
	var files: Array = []
	for i in n:
		files.append({ "name": r.fstr(MAX_NAME), "sha": "", "flags": 0, "size": 0, "parts": [] })
	for i in n:
		if r.fstr(MAX_NAME) != "":
			return _no("verknuepfung")
	for i in n:
		files[i].sha = r.raw(20).hex_encode()
	for i in n:
		files[i].flags = r.u8()
	for i in n:
		var tags := r.u32()
		if tags > 256 or r.bad != "":
			return _no("grenze")
		for t in tags:
			r.fstr(MAX_NAME)
	var parts_total := 0
	for i in n:
		var k := r.u32()
		parts_total += k
		if r.bad != "" or parts_total > MAX_PARTS or k * 28 > r.left():
			return _no("grenze" if parts_total > MAX_PARTS else "kaputt")
		var parts: Array = []
		var fsize := 0
		for j in k:
			var at := r.p
			var psize := r.u32()
			var gb := r.raw(16)
			var off := r.u32()
			var len := r.u32()
			if r.bad != "" or psize < 28 or psize > 4096:
				return _no("kaputt")
			r.seek(at + psize)
			var g := "%08X%08X%08X%08X" % [gb.decode_u32(0), gb.decode_u32(4), gb.decode_u32(8), gb.decode_u32(12)]
			if not index.has(g):
				return _no("kaputt")
			parts.append([int(index[g]), off, len])
			fsize += len
		files[i].parts = parts
		files[i].size = fsize
	if version >= 1:
		for i in n:
			if r.u32() != 0:
				r.raw(16)
		for i in n:
			r.fstr(MAX_NAME)
	if version >= 2:
		for i in n:
			r.raw(32)
	if r.bad != "" or r.p - start > size:
		return _no("kaputt")
	r.seek(start + size)
	return { "ok": true, "files": files }


## Altes JSON-Manifest: Zahlen als „Blob“ (je Byte drei Ziffern, Little Endian).
static func parse_json(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_MANIFEST / 2:
		return _no("zu_gross")
	var j := JSON.new()
	if j.parse(data.get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return _no("kaputt")
	var d: Dictionary = j.data
	var feature := blob_int(str(d.get("ManifestFileVersion", "013000000000")))
	if feature <= 0 or feature > 1000:
		return _no("kaputt")
	var m := { "feature": feature, "app": _js(d, "AppNameString"), "build": _js(d, "BuildVersionString"), "exe": _js(d, "LaunchExeString"),
		"args": _js(d, "LaunchCommand"), "prereq_name": _js(d, "PrereqName"), "prereq_path": _js(d, "PrereqPath"), "prereq_args": _js(d, "PrereqArgs") }
	var sizes: Variant = d.get("ChunkFilesizeList")
	var hashes: Variant = d.get("ChunkHashList")
	var shas: Variant = d.get("ChunkShaList")
	var groups: Variant = d.get("DataGroupList")
	if not (sizes is Dictionary and hashes is Dictionary and shas is Dictionary and groups is Dictionary):
		return _no("kaputt")
	if (sizes as Dictionary).size() > MAX_CHUNKS:
		return _no("grenze")
	var chunks: Array = []
	var index := {}
	for key in sizes.keys():
		var g := str(key).to_upper()
		if g.length() != 32 or not g.is_valid_hex_number() or index.has(g):
			return _no("kaputt" if not index.has(g) else "doppelt")
		var hb := blob_bytes(str(hashes.get(key, "")), 8)
		var sha := str(shas.get(key, "")).to_lower()
		var grp := blob_int(str(groups.get(key, "")))
		var fs := blob_int(str(sizes[key]))
		if hb.is_empty() or sha.length() != 40 or not sha.is_valid_hex_number() or grp < 0 or grp > 99 or fs <= 0 or fs > 1024 * 1024 + 4096:
			return _no("kaputt")
		var gb := PackedByteArray()
		gb.resize(16)
		for k in 4:
			gb.encode_u32(k * 4, ("0x" + g.substr(k * 8, 8)).hex_to_int())
		index[g] = chunks.size()
		chunks.append({ "g": g, "path": chunk_path(feature, grp, hb, gb), "sha": sha, "win": 1024 * 1024, "size": fs })
	var fl: Variant = d.get("FileManifestList")
	if not (fl is Array):
		return _no("kaputt")
	if (fl as Array).size() > MAX_FILES:
		return _no("grenze")
	var files: Array = []
	var parts_total := 0
	for f in fl:
		if not (f is Dictionary) or not (f.get("FileChunkParts") is Array):
			return _no("kaputt")
		if str(f.get("SymlinkTarget", "")) != "":
			return _no("verknuepfung")
		var sb := blob_bytes(str(f.get("FileHash", "")), 20)
		if sb.size() != 20:
			return _no("kaputt")
		var parts: Array = []
		var fsize := 0
		parts_total += (f.FileChunkParts as Array).size()
		if parts_total > MAX_PARTS:
			return _no("grenze")
		for cp in f.FileChunkParts:
			if not (cp is Dictionary):
				return _no("kaputt")
			var g := str(cp.get("Guid", "")).to_upper()
			if not index.has(g):
				return _no("kaputt")
			var off := blob_int(str(cp.get("Offset", "")))
			var len := blob_int(str(cp.get("Size", "")))
			if off < 0 or len < 0:
				return _no("kaputt")
			parts.append([int(index[g]), off, len])
			fsize += len
		var flags := (1 if bool(f.get("bIsReadOnly", false)) else 0) | (2 if bool(f.get("bIsCompressed", false)) else 0) \
			| (4 if bool(f.get("bIsUnixExecutable", false)) else 0)
		files.append({ "name": str(f.get("Filename", "")), "sha": sb.hex_encode(), "flags": flags, "size": fsize, "parts": parts })
	m["chunks"] = chunks
	m["index"] = index
	m["files"] = files
	return { "ok": true, "error": "", "m": m }


static func _js(d: Dictionary, k: String) -> String:
	var v: Variant = d.get(k, "")
	return str(v).left(MAX_STR) if v is String else ""


## „Blob“-Zahl (bis 7 Bytes, damit sie in eine Ganzzahl passt); -1 bei Unsinn.
static func blob_int(s: String) -> int:
	var b := blob_bytes(s, 7)
	if b.is_empty():
		return -1
	var v := 0
	for i in range(b.size() - 1, -1, -1):
		v = (v << 8) | b[i]
	return v


## „Blob“ → Bytes, aufgefüllt auf n; leer bei Unsinn (falsche Länge, Ziffern, Wert über 255).
## Längere Blobs dürfen nur Nullen hinter n haben.
static func blob_bytes(s: String, n: int) -> PackedByteArray:
	if s == "" or s.length() % 3 != 0 or s.length() > 3 * 64 or not s.is_valid_int() or s.begins_with("-") or s.begins_with("+"):
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(n)
	for i in s.length() / 3:
		var v := s.substr(i * 3, 3).to_int()
		if v > 255:
			return PackedByteArray()
		if i < n:
			out[i] = v
		elif v != 0:
			return PackedByteArray()
	return out


## Pfad eines Chunks auf Epics Servern (je Fassung ein eigener Ordner).
static func chunk_path(feature: int, group: int, hash8: PackedByteArray, guid16: PackedByteArray) -> String:
	if feature >= 22:
		return "ChunksV5/plain/%02d/%s_%s.chunk" % [group, _b64url(hash8), _b64url(guid16)]
	var dir := "ChunksV4" if feature >= 15 else ("ChunksV3" if feature >= 6 else ("ChunksV2" if feature >= 3 else "Chunks"))
	return "%s/%02d/%08X%08X_%08X%08X%08X%08X.chunk" % [dir, group, hash8.decode_u32(4), hash8.decode_u32(0),
		guid16.decode_u32(0), guid16.decode_u32(4), guid16.decode_u32(8), guid16.decode_u32(12)]


static func _b64url(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").rstrip("=")


## Gelesenes Manifest prüfen: Pfade, Doppelte, Teile im Chunk, Größen, Prüfsummen. "" = gut.
static func check(m: Dictionary) -> String:
	var files: Array = m.get("files", [])
	var chunks: Array = m.get("chunks", [])
	if files.is_empty():
		return "leer"
	var names := {}
	var dirs := {}
	var total := 0
	for f in files:
		var p := safe_path(str(f.name))
		if p == "":
			return "pfad"
		var low := p.to_lower()
		if names.has(low):
			return "doppelt"
		names[low] = true
		var cut := low.rfind("/")
		while cut > 0:
			dirs[low.substr(0, cut)] = true
			cut = low.rfind("/", cut - 1)
		f["name"] = p
		var sha := str(f.sha)
		if sha.length() != 40 or sha == ZERO_SHA:
			return "pruefsumme"
		if int(f.size) < 0 or int(f.size) > MAX_FILE:
			return "grenze"
		for part in f.parts:
			var c: Dictionary = chunks[int(part[0])]
			if int(part[2]) <= 0 or int(part[1]) < 0 or int(part[1]) + int(part[2]) > int(c.win):
				return "kaputt"
		total += int(f.size)
		if total > MAX_TOTAL:
			return "grenze"
	for d in dirs.keys():
		if names.has(d):
			return "doppelt"
	var dl := 0
	for c in chunks:
		dl += int(c.size)
	m["total"] = total
	m["download"] = dl
	var exe := safe_path(str(m.get("exe", "")))
	m["exe"] = exe if exe != "" and names.has(exe.to_lower()) else ""
	return ""


## Ein Pfad aus dem Manifest, sicher relativ zum Spielordner ("/" als Trenner), "" = abgelehnt:
## leer, absolut, Laufwerk, „..“/„.“, leere Teile, Datenströme (:), Steuerzeichen, Windows-
## Sonderzeichen, Gerätenamen (auch mit Endung), Punkt oder Leerzeichen am Ende, zu lang.
static var _RX_VERBOTEN := RegEx.create_from_string("[\\x{00}-\\x{1F}\\x{7F}<>:\"|?*]")


static func safe_path(name: String) -> String:
	var p := name.replace("\\", "/")
	if p == "" or p.length() > MAX_NAME or p.begins_with("/"):
		return ""
	# Steuerzeichen und Windows-Sonderzeichen in einem Lauf der Engine (ein Manifest hat bis zu einigen hunderttausend
	# Pfaden; Zeichen für Zeichen im Skript kostete das Sekunden).
	if _RX_VERBOTEN.search(p) != null:
		return ""
	var parts := p.split("/", true)
	for seg in parts:
		if seg == "" or seg == "." or seg == ".." or seg.ends_with(".") or seg.ends_with(" ") or seg.begins_with(" "):
			return ""
		var stem := seg.get_slice(".", 0).to_upper().strip_edges()
		if stem in RESERVED:
			return ""
	return "/".join(parts)


# --- Chunks ----------------------------------------------------------------------------------

## Geladener Chunk → { ok, data (entpackt, genau win Bytes), error }. Geprüft: Kopf (Fassung 1–4),
## GUID wie im Manifest, nicht verschlüsselt, Größen, SHA-1 laut Manifest (Pflicht, wenn das
## Manifest eine nennt; sonst muss der Kopf eine nennen – und die Datei-Prüfsumme gilt immer).
static func decode_chunk(raw: PackedByteArray, info: Dictionary) -> Dictionary:
	var r := Rd.new(raw)
	if raw.size() < 41 or raw.size() > int(info.get("win", 0)) + 8192 or r.u32() != CHUNK_MAGIC:
		return { "ok": false, "error": "kaputt" }
	var ver := r.u32()
	var head := r.u32()
	var packed := r.u32()
	var gb := r.raw(16)
	r.raw(8)
	var stored := r.u8()
	var head_sha := ""
	var usize := -1
	if ver >= 2:
		head_sha = r.raw(20).hex_encode()
		r.u8()
	if ver >= 3:
		usize = r.u32()
	if ver >= 4:
		if r.raw(16) != PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]):
			return { "ok": false, "error": "verschluesselt" }
		r.raw(16)
	var want_head := { 1: 41, 2: 62, 3: 66, 4: 98 }
	if r.bad != "" or ver < 1 or ver > 4 or head != int(want_head[ver]) or r.p != head:
		return { "ok": false, "error": "kaputt" }
	if stored & 0x2:
		return { "ok": false, "error": "verschluesselt" }
	if stored & ~0x3 or packed <= 0 or packed > raw.size() - head:
		return { "ok": false, "error": "kaputt" }
	var g := "%08X%08X%08X%08X" % [gb.decode_u32(0), gb.decode_u32(4), gb.decode_u32(8), gb.decode_u32(12)]
	var win := int(info.get("win", 0))
	if g != str(info.get("g", "")) or (usize >= 0 and usize != win):
		return { "ok": false, "error": "kaputt" }
	var data := raw.slice(head, head + packed)
	if stored & 0x1:
		data = data.decompress(win, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != win:
		return { "ok": false, "error": "kaputt" }
	var want := str(info.get("sha", ""))
	if want == ZERO_SHA or want == "":
		want = head_sha
	if want == ZERO_SHA or want == "":
		return { "ok": false, "error": "pruefsumme" }
	if head_sha != "" and head_sha != ZERO_SHA and head_sha != want:
		return { "ok": false, "error": "pruefsumme" }
	if sha1_hex(data) != want:
		return { "ok": false, "error": "pruefsumme" }
	return { "ok": true, "data": data, "error": "" }


static func sha1_hex(data: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA1)
	if not data.is_empty():
		h.update(data)
	return h.finish().hex_encode()


# --- Epics Antwort mit den Manifest-Adressen --------------------------------------------------

## Antwort von launcher/api/public/assets/v2/… → { ok, error, hash, build, urls, bases }. Nur ein
## Eintrag (wie Legendary), SHA-1 des Manifests Pflicht, nur Adressen zu Epics Download-Servern.
static func parse_assets(data: Variant, loopback := false) -> Dictionary:
	var out := { "ok": false, "error": "kaputt", "hash": "", "build": "", "urls": [], "bases": [] }
	if not (data is Dictionary) or not (data.get("elements") is Array) or (data.elements as Array).size() != 1:
		return out
	var el: Variant = data.elements[0]
	if not (el is Dictionary) or not (el.get("manifests") is Array):
		return out
	var h := str(el.get("hash", "")).to_lower()
	if h.length() != 40 or not h.is_valid_hex_number() or h == ZERO_SHA:
		out.error = "pruefsumme"
		return out
	for mf in el.manifests:
		if not (mf is Dictionary):
			continue
		var uri := str(mf.get("uri", ""))
		if not cdn_ok(uri, loopback) or uri.contains("?"):
			continue
		var q := PackedStringArray()
		var params: Variant = mf.get("queryParams", [])
		var bad := false
		if params is Array:
			for p in params:
				if not (p is Dictionary):
					continue
				var k := str(p.get("name", ""))
				var v := str(p.get("value", ""))
				if not _query_ok(k) or not _query_ok(v):
					bad = true
				q.append("%s=%s" % [k, v])
		if bad or (out.urls as Array).size() >= 16:
			continue
		var base := uri.substr(0, uri.rfind("/"))
		if not (base in out.bases):
			(out.bases as Array).append(base)
		(out.urls as Array).append(uri + ("?" + "&".join(q) if not q.is_empty() else ""))
	if (out.urls as Array).is_empty():
		out.error = "adresse"
		return out
	out.ok = true
	out.error = ""
	out.hash = h
	out.build = str(el.get("buildVersion", "")).left(256)
	return out


static func _query_ok(s: String) -> bool:
	if s == "" or s.length() > 4096:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if c <= 32 or c >= 127 or s[i] in ["#", "&", "\"", "<", ">", "\\"]:
			return false
	return true


## Darf Uzai von dieser Adresse laden? Nur https zu Epics Download-Servern (Standard-Anschluss,
## ohne Anmeldedaten in der Adresse), Pfad ohne „..“, Rückstriche und Leerzeichen. loopback: http zu
## 127.0.0.1 für Netz-Proben mit nachgebautem Server.
static func cdn_ok(url: String, loopback := false) -> bool:
	if url.length() > 2048:
		return false
	var rest := ""
	if url.begins_with("https://"):
		rest = url.substr(8)
	elif loopback and url.begins_with("http://127.0.0.1:"):
		rest = url.substr(7)
	else:
		return false
	var cut := rest.find("/")
	if cut <= 0:
		return false
	var host := rest.substr(0, cut).to_lower()
	var path := rest.substr(cut)
	if host.contains("@") or path.contains("..") or path.contains("\\") or path.contains("#"):
		return false
	for i in path.length():
		var c := path.unicode_at(i)
		if c <= 32 or c >= 127:
			return false
	if loopback and host.begins_with("127.0.0.1:"):
		return host.substr(10).is_valid_int()
	if host.contains(":"):
		return false
	if host in CDN_HOSTS:
		return true
	for suf in CDN_SUFFIXES:
		if host.ends_with(suf) and host.length() > str(suf).length():
			return true
	return false


# --- Planen ----------------------------------------------------------------------------------

## Was zu tun ist: neues Manifest m gegen das alte (old, {} bei neuer Installation) und die Dateien,
## deren Prüfsumme Uzai schon kennt (have: Name → SHA-1, z. B. aus dem Prüfen). Ergebnis:
## { files: [Nummern in m.files, die geladen werden], remove: [Namen aus old, die wegfallen],
## chunks: [Chunk-Nummern in Ladereihenfolge], bytes (Größe der zu ladenden Dateien), download }.
static func plan(m: Dictionary, old: Dictionary = {}, have: Dictionary = {}) -> Dictionary:
	var old_sha := {}
	for f in old.get("files", []):
		old_sha[str(f.name).to_lower()] = str(f.sha)
	var want: Array = []
	var keep := {}
	var bytes := 0
	var i := 0
	for f in m.files:
		var low := str(f.name).to_lower()
		keep[low] = true
		var known := str(have.get(low, old_sha.get(low, "")))
		if known != str(f.sha):
			want.append(i)
			bytes += int(f.size)
		i += 1
	var remove: Array = []
	for f in old.get("files", []):
		if not keep.has(str(f.name).to_lower()):
			remove.append(str(f.name))
	var order: Array = []
	var seen := {}
	var dl := 0
	for fi in want:
		for part in m.files[fi].parts:
			var c := int(part[0])
			if not seen.has(c):
				seen[c] = true
				order.append(c)
				dl += int(m.chunks[c].size)
	return { "files": want, "remove": remove, "chunks": order, "bytes": bytes, "download": dl }


## Startparameter wie beim Epic Games Launcher bzw. Legendary (core.py, get_launch_parameters),
## als Liste – jeder Eintrag bleibt ein Argument. exchange: Einmal-Code für die Epic-Anmeldung im
## Spiel (epic_account.gd, exchange_code); nur wenn er genau wie ein Code aussieht, kommen
## -AUTH_LOGIN/-AUTH_PASSWORD/-AUTH_TYPE dazu, sonst startet das Spiel ohne und meldet sich selbst.
## Texte aus fremden Daten nur in sicherer Form („\z“ statt „$“: kein Zeilenumbruch am Ende).
static func launch_args(m_args: String, app: String, ns: String, user: String, user_id: String, locale: String,
		exchange := "") -> PackedStringArray:
	var out := PackedStringArray()
	for a in _split_args(m_args):
		if a.length() <= 512 and _query_ok(a.replace(" ", "_")):
			out.append(a)
		if out.size() >= 32:
			break
	var name_ok := RegEx.create_from_string("^[A-Za-z0-9_.\\- ]{1,32}\\z")
	var id_ok := RegEx.create_from_string("^[A-Za-z0-9]{1,64}\\z")
	if EpicOnline.exchange_ok(exchange):
		out.append("-AUTH_LOGIN=unused")
		out.append("-AUTH_PASSWORD=" + exchange)
		out.append("-AUTH_TYPE=exchangecode")
	if id_ok.search(app) != null:
		out.append("-epicapp=" + app)
	out.append("-epicenv=Prod")
	out.append("-EpicPortal")
	if name_ok.search(user) != null:
		out.append("-epicusername=" + user)
	if id_ok.search(user_id) != null:
		out.append("-epicuserid=" + user_id)
	if RegEx.create_from_string("^[a-z]{2}(-[A-Z]{2})?\\z").search(locale) != null:
		out.append("-epiclocale=" + locale)
	if id_ok.search(ns) != null:
		out.append("-epicsandboxid=" + ns)
	return out


static func _split_args(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var quoted := false
	for ch in line.left(MAX_STR):
		if ch == "\"":
			quoted = not quoted
		elif ch == " " and not quoted:
			if cur != "":
				out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out
