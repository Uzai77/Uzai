extends RefCounted
## Ein kleiner, nur lesender SQLite-Leser für die Datenbanken der Launcher (GOG Galaxy
## galaxy-2.0.db, Amazon Games GameInstallInfo.sqlite, itch butler.db) – ohne neue Abhängigkeit.
## Er versteht genau das Nötige: Kopf der Datei, Tabellen-B-Bäume (innere und Blatt-Seiten),
## Überlaufseiten und das Satzformat. Kein SQL, keine Indizes, keine WITHOUT-ROWID-Tabellen, nie
## schreiben. Die Datei gilt als nicht vertrauenswürdig: Seitenzahl, Tiefe, Zeilen, Satzgröße und
## Überlaufketten sind begrenzt, jede Seite wird höchstens einmal besucht (Schleifen in kaputten
## Dateien), jeder Zugriff ist auf Grenzen geprüft. Seiten werden einzeln gelesen, nie die ganze Datei.
## Liegt ein -wal daneben (Launcher läuft gerade), fehlen höchstens die letzten Änderungen.

const MAX_FILE := 512 * 1024 * 1024
const MAX_PAGES := 200000       ## besuchte Seiten je Tabelle
const MAX_PAYLOAD := 2 * 1024 * 1024
const MAX_COLS := 200
const MAX_ROWS := 50000

var error := ""
var _f: FileAccess
var _ps := 0
var _usable := 0
var _pages := 0
var _utf16 := false


## Tabellen lesen. want: { "Tabelle": ["Spalte", …] } (Groß/klein egal) →
## { ok, error, tables: { "Tabelle": [{ Spalte: Wert }] } }. Fehlt eine Tabelle oder Spalte, ist sie
## leer bzw. null. Werte: int, float, String oder null (Blobs werden nicht übernommen).
static func read_tables(path: String, want: Dictionary, max_rows := MAX_ROWS) -> Dictionary:
	var r := new()
	var out := {}
	for t in want:
		out[t] = []
	if not r._open(path):
		return { "ok": false, "error": r.error, "tables": out }
	var schema := r._schema()
	for t in want:
		var s: Variant = schema.get(str(t).to_lower())
		if s is Dictionary:
			out[t] = r._rows(s, want[t], max_rows)
	r._f.close()
	return { "ok": r.error == "", "error": r.error, "tables": out }


## Namen der Tabellen (für Tests und Fehlersuche).
static func table_names(path: String) -> Array:
	var r := new()
	if not r._open(path):
		return []
	var names: Array = r._schema().keys()
	r._f.close()
	return names


func _open(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		error = "fehlt"
		return false
	_f = FileAccess.open(path, FileAccess.READ)
	if _f == null:
		error = "nicht lesbar"
		return false
	var n := _f.get_length()
	if n < 512 or n > MAX_FILE:
		error = "Größe"
		_f.close()
		return false
	var h := _f.get_buffer(100)
	if h.size() < 100 or h.slice(0, 16).get_string_from_ascii() != "SQLite format 3":
		error = "keine SQLite-Datei"
		_f.close()
		return false
	_ps = _u16(h, 16)
	if _ps == 1:
		_ps = 65536
	if _ps < 512 or _ps > 65536 or (_ps & (_ps - 1)) != 0:
		error = "Seitengröße"
		_f.close()
		return false
	_usable = _ps - h[20]
	var enc := _u32(h, 56)
	if _usable < 480 or enc > 2:
		error = "Format"
		_f.close()
		return false
	_utf16 = enc == 2
	_pages = floori(float(n) / _ps)
	return true


func _page(n: int) -> PackedByteArray:
	if n < 1 or n > _pages:
		return PackedByteArray()
	_f.seek((n - 1) * _ps)
	var b := _f.get_buffer(_ps)
	# Eine halbe Seite (die Datei wurde gerade kürzer, Lesefehler) gilt als keine: Die Leser unten greifen
	# sonst über ihr Ende hinaus.
	return b if b.size() == _ps else PackedByteArray()


## sqlite_master (Seite 1): Tabellen mit Wurzelseite und Spaltennamen.
func _schema() -> Dictionary:
	var out := {}
	for rec in _walk(1, MAX_ROWS):
		var v: Array = rec[1]
		if v.size() < 5 or str(v[0]) != "table" or not (v[3] is int) or not (v[4] is String):
			continue
		var cols := columns(str(v[4]))
		if cols.is_empty():
			continue
		out[str(v[1]).to_lower()] = { "root": int(v[3]), "cols": cols.names, "rowid": int(cols.rowid) }
	return out


func _rows(s: Dictionary, want: Array, max_rows: int) -> Array:
	var names: Array = s.cols
	var idx := {}
	for w in want:
		var k := names.find(str(w).to_lower())
		idx[str(w)] = k
	var out: Array = []
	for rec in _walk(int(s.root), max_rows):
		var v: Array = rec[1]
		var row := {}
		for w in idx:
			var k: int = idx[w]
			var val: Variant = v[k] if k >= 0 and k < v.size() else null
			if k >= 0 and k == int(s.rowid) and val == null:
				val = rec[0]
			row[w] = val if not (val is PackedByteArray) else null
		out.append(row)
	return out


## Alle Sätze eines Tabellen-B-Baums: [[rowid, [Werte]]], höchstens max_rows.
func _walk(root: int, max_rows: int) -> Array:
	var out: Array = []
	var stack: Array = [root]
	var seen := {}
	# Jede Seite kommt höchstens einmal auf den Stapel: In einem heilen Baum hat jede Seite genau eine Mutter. Sonst
	# könnte eine kaputte Datei mit vielen inneren Seiten (je bis zu 32.000 Verweise) den Stapel auf Gigabytes treiben.
	var geplant := { root: true }
	while not stack.is_empty() and out.size() < max_rows:
		var pg: int = stack.pop_back()
		if seen.has(pg) or seen.size() >= MAX_PAGES:
			if seen.has(pg):
				error = "Schleife"
			continue
		seen[pg] = true
		var b := _page(pg)
		if b.is_empty():
			continue
		var off := 100 if pg == 1 else 0
		var kind := b[off]
		var cells := _u16(b, off + 3)
		if kind == 13:
			if off + 8 + cells * 2 > _usable:
				error = "Seite"
				continue
			for i in cells:
				var rec := _leaf_cell(b, _u16(b, off + 8 + i * 2), seen)
				if not rec.is_empty():
					out.append(rec)
					if out.size() >= max_rows:
						break
		elif kind == 5:
			if off + 12 + cells * 2 > _usable:
				error = "Seite"
				continue
			var kinder: Array = [_u32(b, off + 8)]
			for i in range(cells - 1, -1, -1):
				var cp := _u16(b, off + 12 + i * 2)
				if cp + 4 <= _usable:
					kinder.append(_u32(b, cp))
			for kind_seite: int in kinder:
				if geplant.has(kind_seite):
					error = "Schleife"
				elif kind_seite >= 1 and kind_seite <= _pages and geplant.size() < MAX_PAGES:
					geplant[kind_seite] = true
					stack.append(kind_seite)
	return out


## Eine Zelle einer Blattseite → [rowid, Werte]; [] wenn kaputt oder zu groß.
func _leaf_cell(b: PackedByteArray, cp: int, seen: Dictionary) -> Array:
	if cp < 8 or cp >= _usable:
		return []
	var a := varint(b, cp)
	var size: int = a[0]
	var r := varint(b, a[1])
	var at: int = r[1]
	if size < 0 or size > MAX_PAYLOAD or at > _usable:
		return []
	var x := _usable - 35
	var local := size
	if size > x:
		var m := floori((_usable - 12) * 32 / 255.0) - 23
		var k := m + ((size - m) % (_usable - 4))
		local = k if k <= x else m
	if at + local > _usable:
		return []
	var p := b.slice(at, at + local)
	if local < size:
		if at + local + 4 > _usable:
			return []
		var nxt := _u32(b, at + local)
		var hops := 0
		while p.size() < size and nxt != 0:
			hops += 1
			if seen.has(-nxt) or hops > 4096:
				return []
			seen[-nxt] = true
			var o := _page(nxt)
			if o.size() < 4:
				return []
			nxt = _u32(o, 0)
			p.append_array(o.slice(4, 4 + mini(_usable - 4, size - p.size())))
		if p.size() < size:
			return []
	var vals: Variant = record(p, _utf16)
	return [r[0], vals] if vals != null else []


## Rein: ein Satz im SQLite-Satzformat → Werte; null wenn kaputt.
static func record(p: PackedByteArray, utf16 := false) -> Variant:
	var h := varint(p, 0)
	var hs: int = h[0]
	var o: int = h[1]
	if hs < 1 or hs > p.size():
		return null
	var types: Array = []
	while o < hs:
		var t := varint(p, o)
		types.append(t[0])
		o = t[1]
		if types.size() > MAX_COLS:
			return null
	var d := hs
	var out: Array = []
	for t in types:
		var n := 0
		var v: Variant = null
		match t:
			0: n = 0
			1, 2, 3, 4: n = t
			5: n = 6
			6, 7: n = 8
			8: v = 0
			9: v = 1
			10, 11: return null
			_:
				if t < 0:
					return null
				n = (t - 12) >> 1 if t % 2 == 0 else (t - 13) >> 1
		if d + n > p.size():
			return null
		if t >= 1 and t <= 6:
			v = _int_be(p, d, n)
		elif t == 7:
			var fb := p.slice(d, d + 8)
			fb.reverse()
			v = fb.decode_double(0)
		elif t >= 12 and t % 2 == 0:
			v = p.slice(d, d + n)
		elif t >= 13:
			var raw := p.slice(d, d + n)
			v = raw.get_string_from_utf16() if utf16 else raw.get_string_from_utf8()
		d += n
		out.append(v)
	return out


## Rein: Spaltennamen aus „CREATE TABLE x (…)“ → { names: [klein], rowid: Platz der Spalte, die
## die rowid ist (INTEGER PRIMARY KEY), sonst -1 }. {} für WITHOUT ROWID oder Unlesbares.
static func columns(sql: String) -> Dictionary:
	var a := sql.find("(")
	var z := sql.rfind(")")
	if a < 0 or z <= a or sql.length() > 100000:
		return {}
	if sql.substr(z).to_upper().contains("WITHOUT"):
		return {}
	var body := sql.substr(a + 1, z - a - 1)
	var defs := PackedStringArray()
	var depth := 0
	var quote := ""
	var cur := ""
	for ch in body:
		if quote != "":
			cur += ch
			if ch == quote:
				quote = ""
			continue
		match ch:
			"\"", "'", "`":
				quote = ch
			"[":
				quote = "]"
			"(":
				depth += 1
			")":
				depth -= 1
			",":
				if depth == 0:
					defs.append(cur)
					cur = ""
					continue
		cur += ch
	defs.append(cur)
	var names: Array = []
	var rowid := -1
	for d0 in defs:
		var d := d0.strip_edges()
		if d == "":
			continue
		var name := ""
		var rest := ""
		var q := d[0]
		var close: String = { "\"": "\"", "`": "`", "[": "]", "'": "'" }.get(q, "")
		if close != "":
			var e := d.find(close, 1)
			if e < 0:
				return {}
			name = d.substr(1, e - 1)
			rest = d.substr(e + 1)
		else:
			var sp := d.find(" ")
			name = d if sp < 0 else d.substr(0, sp)
			rest = "" if sp < 0 else d.substr(sp)
			if name.to_upper() in ["CONSTRAINT", "PRIMARY", "UNIQUE", "CHECK", "FOREIGN"]:
				continue
		var up := " ".join(rest.to_upper().split(" ", false))
		if up.begins_with("INTEGER PRIMARY KEY") and not up.contains(" DESC"):
			rowid = names.size()
		names.append(name.to_lower())
		if names.size() > MAX_COLS:
			return {}
	return { "names": names, "rowid": rowid } if not names.is_empty() else {}


## Rein: SQLite-Varint ab o → [Wert, nächste Stelle]; am Ende der Daten [0, Ende].
static func varint(b: PackedByteArray, o: int) -> Array:
	var v := 0
	for i in 9:
		if o + i >= b.size():
			return [0, b.size()]
		var c := b[o + i]
		if i == 8:
			return [(v << 8) | c, o + 9]
		v = (v << 7) | (c & 0x7f)
		if c < 0x80:
			return [v, o + i + 1]
	return [v, o + 9]


static func _int_be(b: PackedByteArray, o: int, n: int) -> int:
	var v := 0
	for i in n:
		v = (v << 8) | b[o + i]
	# Vorzeichen (Zweierkomplement) für kürzere Zahlen als 8 Bytes.
	if n < 8 and (b[o] & 0x80) != 0:
		v -= 1 << (n * 8)
	return v


static func _u16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1] if o + 1 < b.size() and o >= 0 else 0


static func _u32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3] if o + 3 < b.size() and o >= 0 else 0
