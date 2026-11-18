extends RefCounted
## ZIP-Pakete aus fremden Quellen prüfen, ohne sie zu entpacken, und einzelne Einträge im Speicher
## entpacken – ein Leser für geteilte Zimmer (paket.gd, zimmer_teilen.gd) und für
## Programm-Pakete (retro_auto.gd, retro_laden.gd). Was im Paket stehen darf (Namen, Größen,
## Packrate), gibt der Aufrufer vor; seine Fehlertexte bildet er aus dem Fehlercode.
## Immer abgelehnt: geteilte und ZIP64-Pakete, Verschlüsselung, Verknüpfungen, andere Verfahren als
## Speichern und Deflate, lokale Köpfe, die nicht zum Verzeichnis passen, Daten hinter dem
## Verzeichnis oder übereinander, doppelte Namen (auch in anderer Schreibweise) und eine Datei, die
## so heißt wie ein Ordner mit anderen Dateien darin.

## Beim Laden gefüllt und danach nur gelesen: Pakete prüft auch ein Hilfsfaden (retro_laden.gd). Eine Tabelle, die
## sich erst beim ersten Aufruf füllt, könnte ein zweiter Faden halb fertig sehen – und ein gutes Paket ablehnen.
static var _crc_table := _crc_tabelle()


## Inhaltsverzeichnis prüfen. regeln:
##   max_archiv     größtes Paket in Bytes (0 = keine eigene Grenze, der Aufrufer prüft vorher)
##   max_eintraege  höchstens so viele Einträge im Verzeichnis
##   max_dateien    höchstens so viele Dateien
##   max_name       längster Name in Bytes
##   utf8           Namen dürfen UTF-8 sein (Kennzeichen im Eintrag), sonst nur ASCII
##   name_ok        Callable(name: String, ordner: bool) -> String: "" = erlaubt, sonst Fehlercode
##   grenze         Callable(name: String) -> int: größte entpackte Größe der Datei, -1 = keine eigene
##   rate_ab        Packrate erst ab dieser entpackten Größe prüfen
##   max_rate       entpackt höchstens so viel mal größer als gepackt
##   max_gesamt     entpackt zusammen höchstens so viel
## Ergebnis: { ok, fehler, name, grenze, entries: [{ name, method, crc, csize, usize, data_at }],
## dirs, total }. fehler: kein_zip, zip64, zu_viele, leer, kaputt, name_kodierung, doppelt,
## verschluesselt, verknuepfung, ordner, verfahren, zu_gross_datei, packrate, zu_gross – oder der
## Code aus name_ok; name ist dann der Name im Paket.
static func verzeichnis(b: PackedByteArray, regeln: Dictionary) -> Dictionary:
	var n := b.size()
	var max_archiv := int(regeln.get("max_archiv", 0))
	if n < 22 or (max_archiv > 0 and n > max_archiv):
		return _nein("kein_zip")
	# Ende des Verzeichnisses suchen (höchstens 64 KB Kommentar dahinter).
	var eocd := -1
	var i := n - 22
	var stop := maxi(-1, n - 22 - 65536)
	while i > stop:
		if b[i] == 0x50 and b[i + 1] == 0x4b and b[i + 2] == 0x05 and b[i + 3] == 0x06:
			eocd = i
			break
		i -= 1
	if eocd < 0:
		return _nein("kein_zip")
	var count := b.decode_u16(eocd + 10)
	var cd_size := b.decode_u32(eocd + 12)
	var cd_at := b.decode_u32(eocd + 16)
	if b.decode_u16(eocd + 4) != 0 or b.decode_u16(eocd + 6) != 0 or b.decode_u16(eocd + 8) != count or count == 0xFFFF or cd_at == 0xFFFFFFFF:
		return _nein("zip64")
	if count == 0:
		return _nein("leer")
	if count > int(regeln.max_eintraege):
		return _nein("zu_viele")
	if cd_at + cd_size > eocd:
		return _nein("kaputt")
	var name_ok: Callable = regeln.name_ok
	var grenze: Callable = regeln.grenze
	var entries: Array = []
	var dirs: Array = []
	var seen := {}
	var spans: Array = []
	var total := 0
	var p := cd_at
	for k in count:
		if p + 46 > eocd or b.decode_u32(p) != 0x02014b50:
			return _nein("kaputt")
		var made := b.decode_u16(p + 4)
		var flags := b.decode_u16(p + 8)
		var method := b.decode_u16(p + 10)
		var crc := b.decode_u32(p + 16)
		var csize := b.decode_u32(p + 20)
		var usize := b.decode_u32(p + 24)
		var nlen := b.decode_u16(p + 28)
		var xlen := b.decode_u16(p + 30)
		var clen := b.decode_u16(p + 32)
		var eattr := b.decode_u32(p + 38)
		var lho := b.decode_u32(p + 42)
		if nlen == 0 or nlen > int(regeln.max_name) or p + 46 + nlen > eocd:
			return _nein("kaputt")
		var name_b := b.slice(p + 46, p + 46 + nlen)
		p += 46 + nlen + xlen + clen
		var name := name_b.get_string_from_utf8() if bool(regeln.get("utf8", false)) and flags & 0x800 else name_b.get_string_from_ascii()
		if name.to_utf8_buffer() != name_b:
			return _nein("name_kodierung", name)
		var ordner := name.ends_with("/")
		var why: String = name_ok.call(name, ordner)
		if why != "":
			return _nein(why, name)
		var low := name.to_lower().trim_suffix("/")
		if seen.has(low):
			return _nein("doppelt", name)
		seen[low] = true
		if flags & 0x1:
			return _nein("verschluesselt", name)
		# Verknüpfungen (Unix-Symlinks) gibt es in keinem Paket, das Uzai liest.
		if (made >> 8) == 3 and ((eattr >> 16) & 0xF000) == 0xA000:
			return _nein("verknuepfung", name)
		if ordner:
			if usize != 0:
				return _nein("ordner", name)
			dirs.append(name.trim_suffix("/"))
			continue
		if method != 0 and method != 8:
			return _nein("verfahren", name)
		if csize == 0xFFFFFFFF or usize == 0xFFFFFFFF:
			return _nein("zip64", name)
		var limit: int = grenze.call(name)
		if limit >= 0 and usize > limit:
			var r := _nein("zu_gross_datei", name)
			r["grenze"] = limit
			return r
		if method == 0 and csize != usize:
			return _nein("kaputt", name)
		if method == 8 and usize > int(regeln.rate_ab) and usize > csize * int(regeln.max_rate):
			return _nein("packrate", name)
		total += usize
		if total > int(regeln.max_gesamt):
			return _nein("zu_gross", name)
		# Lokaler Kopf: gleicher Name, Daten liegen vor dem Verzeichnis.
		if lho + 30 > cd_at or b.decode_u32(lho) != 0x04034b50:
			return _nein("kaputt", name)
		var ln := b.decode_u16(lho + 26)
		var lx := b.decode_u16(lho + 28)
		if ln != nlen or b.slice(lho + 30, lho + 30 + ln) != name_b:
			return _nein("kaputt", name)
		var data_at := lho + 30 + ln + lx
		if data_at + csize > cd_at:
			return _nein("kaputt", name)
		spans.append([lho, data_at + csize])
		entries.append({ "name": name, "method": method, "crc": crc, "csize": csize, "usize": usize, "data_at": data_at })
		if entries.size() > int(regeln.max_dateien):
			return _nein("zu_viele")
	# Daten, die sich überlappen, gibt es nur in gebauten Bomben.
	spans.sort_custom(func(a: Array, c: Array) -> bool: return int(a[0]) < int(c[0]))
	for j in range(1, spans.size()):
		if int(spans[j][0]) < int(spans[j - 1][1]):
			return _nein("kaputt")
	if entries.is_empty():
		return _nein("leer")
	# Eine Datei darf nicht so heißen wie ein Ordner, in dem andere Dateien liegen.
	var namen := {}
	for e in entries:
		namen[str(e.name).to_lower()] = true
	for e in entries:
		var parts := str(e.name).to_lower().split("/")
		for j in range(1, parts.size()):
			if namen.has("/".join(parts.slice(0, j))):
				return _nein("kaputt", str(e.name))
	return { "ok": true, "fehler": "", "name": "", "entries": entries, "dirs": dirs, "total": total }


## Einen Eintrag (aus verzeichnis) im Speicher entpacken; null = beschädigt. Deflate läuft als
## GZIP-Strom (Kopf davor, Prüfsumme und Größe aus dem Verzeichnis dahinter) durch den Entpacker
## der Engine: Er bekommt genau die versprochene Größe als Puffer und prüft am Ende die Prüfsumme.
## Gespeicherte Einträge prüft Uzai selbst gegen ihre CRC-32.
static func entpacken(b: PackedByteArray, e: Dictionary) -> Variant:
	var raw := b.slice(int(e.data_at), int(e.data_at) + int(e.csize))
	if int(e.method) == 0:
		return raw if crc32(raw) == int(e.crc) else null
	if int(e.usize) == 0:
		return PackedByteArray()
	if raw.is_empty():
		return null
	var gz := PackedByteArray([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
	gz.append_array(raw)
	var tail := PackedByteArray()
	tail.resize(8)
	tail.encode_u32(0, int(e.crc))
	tail.encode_u32(4, int(e.usize))
	gz.append_array(tail)
	var out := gz.decompress(int(e.usize), FileAccess.COMPRESSION_GZIP)
	if out.size() != int(e.usize):
		return null
	return out


## CRC-32 (wie in ZIP und GZIP).
static func _crc_tabelle() -> PackedInt64Array:
	var t := PackedInt64Array()
	t.resize(256)
	for n in 256:
		var c := n
		for k in 8:
			c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
		t[n] = c
	return t


static func crc32(data: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for b in data:
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


static func _nein(fehler: String, name := "") -> Dictionary:
	return { "ok": false, "fehler": fehler, "name": name }
