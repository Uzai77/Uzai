extends RefCounted
## Angaben aus eigenen Musikdateien (Punkt 34, lokale Musik): Titel, Interpret, Album,
## Album-Interpret, Nummer, CD, Jahr, Länge und das eingebettete Cover. Eigener, kleiner Leser für
## ID3v2.2–2.4 und ID3v1 (MP3), Vorbis-Kommentare (OGG) und RIFF-INFO (WAV).
##
## Die Dateien kommen von irgendwoher, darum: nur lesen, jede Größe gegen das Dateiende und feste
## Obergrenzen prüfen, nie mehr als nötig in den Speicher, nichts davon als Code oder Godot-Objekt
## laden (kein str_to_var, keine Ressourcen). Was nicht passt, fällt still weg – eine kaputte
## Datei ergibt einfach weniger Angaben. Ohne Zustand und ohne Fenster testbar (tests/logic_musikquelle.gd).

## Abspielbar ohne neue Abhängigkeit: Godot lädt MP3, Ogg Vorbis und WAV zur Laufzeit. FLAC und
## Opus kann Godot 4.5 nicht abspielen – solche Dateien zeigt Uzai gar nicht erst an.
const EXTS := ["mp3", "ogg", "wav"]

const TAG_MAX := 16 * 1024 * 1024       ## ID3v2: mehr liest Uzai nicht (große Cover dahinter fallen weg)
const TEXT_MAX := 300                   ## Zeichen je Angabe
const PIC_MAX := 8 * 1024 * 1024        ## eingebettetes Cover höchstens so groß
const OGG_MAX := 4 * 1024 * 1024        ## Kopf einer Ogg-Datei (Kennung und Kommentare) höchstens so groß
const OGG_TAIL := 65536                 ## so viel vom Ende einer Ogg-Datei für die Länge
const MP3_SYNC_MAX := 65536             ## so weit nach dem ersten MP3-Rahmen suchen
const COMMENTS_MAX := 1000              ## Vorbis-Kommentare je Datei
const RIFF_CHUNKS_MAX := 64
const KLEIN_MAX := 16384                ## größere ID3-Rahmen überspringt das Einlesen ohne Cover (Text ist nie so lang)
const RAHMEN_MAX := 512                 ## so viele ID3-Rahmen je Tag sieht es dabei an
## Bitraten (kbit/s) je MPEG-Version und Schicht, Abtastraten von MPEG 1.
const MP3_BITRATEN := {
	"1-1": [32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
	"1-2": [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
	"1-3": [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
	"2-1": [32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
	"2-x": [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
}
const MP3_RATEN := [44100, 48000, 32000]

## Schlüssel der Vorbis-Kommentare (klein geschrieben) → Feld.
const VORBIS_KEYS := { "title": "title", "artist": "artist", "album": "album", "albumartist": "album_artist",
	"album artist": "album_artist", "album_artist": "album_artist", "tracknumber": "track", "discnumber": "disc",
	"date": "year", "year": "year" }
## ID3v2.3/2.4 und ID3v2.2 → Feld.
const ID3_FRAMES := { "TIT2": "title", "TPE1": "artist", "TALB": "album", "TPE2": "album_artist", "TRCK": "track",
	"TPOS": "disc", "TYER": "year", "TDRC": "year", "TDOR": "year", "TLEN": "len",
	"TT2": "title", "TP1": "artist", "TAL": "album", "TP2": "album_artist", "TRK": "track", "TPA": "disc",
	"TYE": "year", "TLE": "len" }
## RIFF-INFO (WAV) → Feld.
const RIFF_KEYS := { "INAM": "title", "IART": "artist", "IPRD": "album", "ITRK": "track", "IPRT": "track", "ICRD": "year" }


## Angaben einer Datei: { title, artist, album, album_artist, track, disc, year, dur (ms) } – fehlende
## Felder fehlen. want_pic: auch das Cover als { pic (Bytes), pic_ext ("jpg" | "png") }.
## {} = keine lesbare Musikdatei; { unsupported: true } = Ogg ohne Vorbis (z. B. Opus).
static func read(path: String, want_pic := false) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var size := f.get_length()
	var out := {}
	match path.get_extension().to_lower():
		"mp3":
			out = _mp3(f, size, want_pic)
		"ogg":
			out = _ogg(f, size, want_pic)
		"wav":
			out = _wav(f, size, want_pic)
	f.close()
	return out


# --- MP3: ID3v2, ID3v1 und Länge ----------------------------------------------------------------

static func _mp3(f: FileAccess, size: int, want_pic: bool) -> Dictionary:
	var out := {}
	var audio_at := 0
	if size >= 10:
		var head := f.get_buffer(10)
		if head.size() == 10 and head[0] == 0x49 and head[1] == 0x44 and head[2] == 0x33:
			var tag_size := syncsafe(head, 6)
			if tag_size >= 0:
				var footer := 10 if (head[3] == 4 and (head[5] & 0x10) != 0) else 0
				audio_at = 10 + tag_size + footer
				if not want_pic and id3_springbar(head):
					out = id3v2(head, id3_kleine(f, head[3], mini(size, 10 + tag_size)), false)
				else:
					var want := mini(tag_size, mini(TAG_MAX, maxi(0, size - 10)))
					out = id3v2(head, f.get_buffer(want), want_pic)
	# ID3v1 am Ende ergänzt, was oben fehlt.
	var v1_len := 0
	if size >= 128:
		f.seek(size - 128)
		var t := f.get_buffer(128)
		if t.size() == 128 and t[0] == 0x54 and t[1] == 0x41 and t[2] == 0x47:
			v1_len = 128
			var v1 := id3v1(t)
			for k in v1:
				if not out.has(k):
					out[k] = v1[k]
	if not out.has("dur"):
		var dur := _mp3_duration(f, size, audio_at, v1_len)
		if dur > 0:
			out["dur"] = dur
	return out


## Stehen die Rahmen so in der Datei, wie ihre Größe sagt? Dann lassen sich große überspringen, ohne sie zu lesen:
## ID3v2.3 ohne „Unsynchronisation“ über den ganzen Tag, 2.3 und 2.4 ohne erweiterten Kopf. Alles andere
## (selten) liest _mp3 wie bisher am Stück.
static func id3_springbar(head: PackedByteArray) -> bool:
	if head.size() < 10:
		return false
	return (head[3] == 3 and (head[5] & 0xC0) == 0) or (head[3] == 4 and (head[5] & 0x40) == 0)


## Die kleinen Rahmen eines ID3v2-Tags aus der Datei holen, hintereinander wie im Tag (für id3v2). Große – das
## eingebettete Cover, oft ein halbes Megabyte – werden übersprungen statt gelesen: Beim Einlesen einer Sammlung
## las Uzai sonst je Datei das ganze Cover mit, nur um Titel und Interpret zu finden. ende: erstes Byte hinter dem Tag.
static func id3_kleine(f: FileAccess, ver: int, ende: int) -> PackedByteArray:
	var out := PackedByteArray()
	var pos := 10
	for i in RAHMEN_MAX:
		if pos + 10 > ende:
			break
		f.seek(pos)
		var h := f.get_buffer(10)
		if h.size() < 10 or h[0] == 0:
			break
		var fsize := _be32(h, 4) if ver == 3 else syncsafe(h, 4)
		if fsize <= 0 or pos + 10 + fsize > ende:
			break
		if fsize <= KLEIN_MAX:
			var d := f.get_buffer(fsize)
			if d.size() < fsize:
				break
			out.append_array(h)
			out.append_array(d)
		pos += 10 + fsize
	return out


## ID3v2-Größe (vier Bytes zu je 7 Bit). -1, wenn ein Byte das oberste Bit gesetzt hat.
static func syncsafe(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return -1
	var n := 0
	for i in 4:
		if (b[at + i] & 0x80) != 0:
			return -1
		n = (n << 7) | b[at + i]
	return n


static func _be32(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return -1
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


static func _le32(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return -1
	return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)


## „Unsynchronisation“ rückgängig: jedes 0xFF 0x00 wird zu 0xFF.
static func unsync(b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(b.size())
	var n := 0
	var i := 0
	while i < b.size():
		out[n] = b[i]
		n += 1
		if b[i] == 0xFF and i + 1 < b.size() and b[i + 1] == 0x00:
			i += 1
		i += 1
	out.resize(n)
	return out


## Rahmen eines ID3v2-Tags lesen. head: die zehn Kopf-Bytes, body: der Tag dahinter.
static func id3v2(head: PackedByteArray, body: PackedByteArray, want_pic := false) -> Dictionary:
	var out := {}
	var ver := head[3]
	if ver < 2 or ver > 4:
		return out
	var flags := head[5]
	if ver < 4 and (flags & 0x80) != 0:
		body = unsync(body)
	var pos := 0
	if ver >= 3 and (flags & 0x40) != 0:
		# Erweiterter Kopf: überspringen (2.3: Größe ohne die vier Größen-Bytes, 2.4: mit).
		var ext := _be32(body, 0) + 4 if ver == 3 else syncsafe(body, 0)
		if ext < 4 or ext > body.size():
			return out
		pos = ext
	var id_len := 3 if ver == 2 else 4
	var head_len := 6 if ver == 2 else 10
	var pics: Array = []
	while pos + head_len <= body.size():
		if body[pos] == 0:
			break                      # Auffüllung
		var id := ""
		for i in id_len:
			var c := body[pos + i]
			if not ((c >= 0x41 and c <= 0x5A) or (c >= 0x30 and c <= 0x39)):
				return _finish(out, pics, want_pic)
			id += String.chr(c)
		var fsize := 0
		var fflags := 0
		if ver == 2:
			fsize = (body[pos + 3] << 16) | (body[pos + 4] << 8) | body[pos + 5]
		elif ver == 3:
			fsize = _be32(body, pos + 4)
			fflags = (body[pos + 8] << 8) | body[pos + 9]
		else:
			fsize = syncsafe(body, pos + 4)
			fflags = (body[pos + 8] << 8) | body[pos + 9]
		pos += head_len
		if fsize <= 0 or pos + fsize > body.size():
			break
		var data := body.slice(pos, pos + fsize)
		pos += fsize
		# Verschlüsselte oder gepackte Rahmen nicht anfassen.
		if ver == 3 and (fflags & 0x00C0) != 0:
			continue
		if ver == 4:
			if (fflags & 0x000C) != 0:
				continue
			var skip := 0
			if (fflags & 0x0040) != 0:
				skip += 1                  # Gruppen-Kennung
			if (fflags & 0x0001) != 0:
				skip += 4                  # Datenlänge
			if skip > 0:
				if skip >= data.size():
					continue
				data = data.slice(skip)
			if (fflags & 0x0002) != 0 or (flags & 0x80) != 0:
				data = unsync(data)
		if id == "APIC" or id == "PIC":
			if want_pic and pics.size() < 8:
				var p := _apic(data, id == "PIC")
				if not p.is_empty():
					pics.append(p)
			continue
		var field := str(ID3_FRAMES.get(id, ""))
		if field == "" or out.has(field) and field != "year":
			continue
		var text := id3_text(data)
		if text == "":
			continue
		_put(out, field, text)
	return _finish(out, pics, want_pic)


static func _finish(out: Dictionary, pics: Array, want_pic: bool) -> Dictionary:
	if out.has("len"):
		var ms := int(str(out.len).to_int())
		out.erase("len")
		if ms > 0 and ms < 86400000:
			out["dur"] = ms
	if want_pic and not pics.is_empty():
		# Vorderseite (Art 3) vor allen anderen.
		var best: Dictionary = pics[0]
		for p in pics:
			if int(p.kind) == 3:
				best = p
				break
		out["pic"] = best.bytes
		out["pic_ext"] = best.ext
	return out


## Ein Feld eintragen: Text säubern, Nummern („3/12“) und Jahr („2004-05-01“) als Zahl.
static func _put(out: Dictionary, field: String, text: String) -> void:
	text = clean(text)
	if text == "":
		return
	match field:
		"track", "disc":
			var n := int(text.get_slice("/", 0).strip_edges().to_int())
			if n > 0 and n < 10000:
				out[field] = n
		"year":
			var y := int(text.left(4).to_int()) if text.length() >= 4 else 0
			if y >= 1000 and y < 3000 and not out.has("year"):
				out["year"] = y
		"len":
			out["len"] = text
		_:
			out[field] = text


## Text eines Rahmens nach seiner Kodierung (erstes Byte): 0 Latin-1, 1 UTF-16 mit BOM,
## 2 UTF-16BE, 3 UTF-8. Mehrere Werte (durch 0 getrennt): der erste.
static func id3_text(data: PackedByteArray) -> String:
	if data.size() < 2:
		return ""
	return decode(data.slice(1), data[0])


static func decode(b: PackedByteArray, enc: int) -> String:
	match enc:
		0:
			return latin1(_until_zero(b, 1))
		1, 2:
			return utf16(_until_zero(b, 2), enc == 2)
		3:
			return utf8(_until_zero(b, 1))
	return ""


## UTF-8, wenn die Bytes gültiges UTF-8 sind, sonst Latin-1 (viele alte Dateien). So meldet
## Godot bei fremden Bytes keine Dekodierfehler ins Protokoll.
static func utf8(b: PackedByteArray) -> String:
	return b.get_string_from_utf8() if is_utf8(b) else latin1(b)


static func is_utf8(b: PackedByteArray) -> bool:
	var i := 0
	while i < b.size():
		var c := b[i]
		var n := 0
		var lo := 0x80
		var hi := 0xBF
		if c < 0x80:
			i += 1
			continue
		elif c >= 0xC2 and c <= 0xDF:
			n = 1
		elif c >= 0xE0 and c <= 0xEF:
			n = 2
			lo = 0xA0 if c == 0xE0 else 0x80
			hi = 0x9F if c == 0xED else 0xBF
		elif c >= 0xF0 and c <= 0xF4:
			n = 3
			lo = 0x90 if c == 0xF0 else 0x80
			hi = 0x8F if c == 0xF4 else 0xBF
		else:
			return false
		if i + n >= b.size():
			return false
		for k in range(1, n + 1):
			var d := b[i + k]
			if (k == 1 and (d < lo or d > hi)) or (k > 1 and (d < 0x80 or d > 0xBF)):
				return false
		i += n + 1
	return true


## Bytes bis zur ersten Null (bei UTF-16 bis zu zwei Null-Bytes an gerader Stelle).
static func _until_zero(b: PackedByteArray, width: int) -> PackedByteArray:
	var i := 0
	while i + width <= b.size():
		if b[i] == 0 and (width == 1 or b[i + 1] == 0):
			return b.slice(0, i)
		i += width
	return b


static func latin1(b: PackedByteArray) -> String:
	var s := ""
	for i in mini(b.size(), TEXT_MAX * 2):
		s += String.chr(b[i])
	return s


## UTF-16 mit oder ohne Byte-Order-Mark; be: ohne BOM als Big Endian lesen. Ersatzpaare werden
## zusammengesetzt, kaputte Hälften fallen weg.
static func utf16(b: PackedByteArray, be := false) -> String:
	var i := 0
	if b.size() >= 2:
		if b[0] == 0xFF and b[1] == 0xFE:
			be = false
			i = 2
		elif b[0] == 0xFE and b[1] == 0xFF:
			be = true
			i = 2
	var s := ""
	var hi := 0
	var n := 0
	while i + 1 < b.size() and n < TEXT_MAX * 2:
		var u: int = (b[i] << 8 | b[i + 1]) if be else (b[i] | b[i + 1] << 8)
		i += 2
		n += 1
		if u >= 0xD800 and u <= 0xDBFF:
			hi = u
			continue
		if u >= 0xDC00 and u <= 0xDFFF:
			if hi != 0:
				s += String.chr(0x10000 + ((hi - 0xD800) << 10) + (u - 0xDC00))
			hi = 0
			continue
		hi = 0
		if u != 0:
			s += String.chr(u)
	return s


## Alles, was clean() ersetzt oder zusammenfasst (Steuerzeichen, zwei Leerzeichen hintereinander).
static var _RX_UNSAUBER := RegEx.create_from_string("[\\x{00}-\\x{1F}\\x{7F}-\\x{9F}\\x{FEFF}]|  ")


## Steuerzeichen raus, Leerraum zusammen, gekürzt.
static func clean(s: String) -> String:
	# Fast immer ist nichts zu tun: ein Suchlauf der Engine statt Zeichen für Zeichen im Skript (diese Funktion läuft
	# für jede Angabe jedes Titels).
	if _RX_UNSAUBER.search(s) == null:
		return s.strip_edges().left(TEXT_MAX)
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 0x20 or (c >= 0x7F and c < 0xA0) or c == 0xFEFF:
			out += " "
		else:
			out += ch
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.left(TEXT_MAX)


## Bild aus APIC (2.3/2.4) bzw. PIC (2.2): nur JPEG und PNG, höchstens PIC_MAX.
static func _apic(data: PackedByteArray, v22: bool) -> Dictionary:
	if data.size() < 4:
		return {}
	var enc := data[0]
	var pos := 1
	if v22:
		pos = 4                         # drei Buchstaben Format
	else:
		while pos < data.size() and data[pos] != 0:
			pos += 1
		pos += 1                        # MIME-Typ samt Null
	if pos >= data.size():
		return {}
	var kind := data[pos]
	pos += 1
	# Beschreibung samt Ende (bei UTF-16 zwei Null-Bytes an gerader Stelle).
	var w := 2 if enc in [1, 2] else 1
	while pos + w <= data.size():
		if data[pos] == 0 and (w == 1 or data[pos + 1] == 0):
			pos += w
			break
		pos += w
	if pos >= data.size():
		return {}
	var img := data.slice(pos)
	var ext := image_ext(img)
	if ext == "" or img.size() > PIC_MAX:
		return {}
	return { "kind": kind, "bytes": img, "ext": ext }


## "jpg" | "png" | "" nach den ersten Bytes.
static func image_ext(b: PackedByteArray) -> String:
	if b.size() >= 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		return "jpg"
	if b.size() >= 8 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47 and b[4] == 0x0D and b[5] == 0x0A and b[6] == 0x1A and b[7] == 0x0A:
		return "png"
	return ""


## ID3v1 (128 Bytes am Dateiende, Latin-1).
static func id3v1(t: PackedByteArray) -> Dictionary:
	var out := {}
	if t.size() != 128:
		return out
	for spec in [["title", 3, 30], ["artist", 33, 30], ["album", 63, 30], ["year", 93, 4]]:
		var txt := latin1(_until_zero(t.slice(int(spec[1]), int(spec[1]) + int(spec[2])), 1))
		_put(out, str(spec[0]), txt)
	# ID3v1.1: Nummer im letzten Byte des Kommentars, davor eine Null.
	if t[125] == 0 and t[126] != 0:
		out["track"] = int(t[126])
	return out


## Länge aus dem ersten MPEG-Rahmen: genau über Xing/Info bzw. VBRI, sonst als konstante Bitrate
## geschätzt. 0 = unbekannt.
static func _mp3_duration(f: FileAccess, size: int, audio_at: int, v1_len: int) -> int:
	if audio_at >= size:
		return 0
	f.seek(audio_at)
	var buf := f.get_buffer(mini(MP3_SYNC_MAX, size - audio_at))
	var i := 0
	while i + 4 <= buf.size():
		if buf[i] == 0xFF and (buf[i + 1] & 0xE0) == 0xE0:
			var h := mp3_header(buf[i + 1], buf[i + 2], buf[i + 3])
			if not h.is_empty():
				var frames := _vbr_frames(buf, i, h)
				if frames > 0:
					return int(frames * float(h.spf) / float(h.rate) * 1000.0)
				var audio := size - (audio_at + i) - v1_len
				return int(audio * 8000.0 / float(h.bitrate))
		i += 1
	return 0


## Kopf eines MPEG-Audio-Rahmens: { version (1, 2, 25), layer, bitrate (Bit/s), rate (Hz), spf
## (Samples je Rahmen), mono }. {} = kein gültiger Kopf.
static func mp3_header(b1: int, b2: int, b3: int) -> Dictionary:
	var ver_bits := (b1 >> 3) & 3            # 0: 2.5, 2: 2, 3: 1
	var layer_bits := (b1 >> 1) & 3          # 1: III, 2: II, 3: I
	var br_idx := (b2 >> 4) & 15
	var sr_idx := (b2 >> 2) & 3
	if ver_bits == 1 or layer_bits == 0 or br_idx == 0 or br_idx == 15 or sr_idx == 3:
		return {}
	var v1 := ver_bits == 3
	var layer := 4 - layer_bits
	var key := ("1-%d" % layer) if v1 else ("2-1" if layer == 1 else "2-x")
	var bitrate: int = int(MP3_BITRATEN[key][br_idx - 1]) * 1000
	var rate: int = MP3_RATEN[sr_idx]
	if ver_bits == 2:
		rate /= 2
	elif ver_bits == 0:
		rate /= 4
	var spf := 384 if layer == 1 else (1152 if layer == 2 or v1 else 576)
	return { "version": 1 if v1 else (2 if ver_bits == 2 else 25), "layer": layer, "bitrate": bitrate, "rate": rate, "spf": spf,
		"mono": ((b3 >> 6) & 3) == 3 }


## Anzahl der Rahmen aus einem Xing/Info- bzw. VBRI-Kopf im ersten Rahmen (0: keiner).
static func _vbr_frames(buf: PackedByteArray, at: int, h: Dictionary) -> int:
	var side: int = (32 if not bool(h.mono) else 17) if int(h.version) == 1 else (17 if not bool(h.mono) else 9)
	var x := at + 4 + side
	if x + 12 <= buf.size():
		var tag := buf.slice(x, x + 4).get_string_from_ascii()
		if tag == "Xing" or tag == "Info":
			var fl := _be32(buf, x + 4)
			if fl >= 0 and (fl & 1) != 0:
				return maxi(0, _be32(buf, x + 8))
	var v := at + 4 + 32
	if v + 18 <= buf.size() and buf.slice(v, v + 4).get_string_from_ascii() == "VBRI":
		return maxi(0, _be32(buf, v + 14))
	return 0


# --- Ogg Vorbis: Kennung, Kommentare, Länge ----------------------------------------------------

## Pakete der ersten Ogg-Seiten zusammensetzen, bis Kennung und Kommentar da sind (höchstens OGG_MAX).
static func _ogg(f: FileAccess, size: int, want_pic: bool) -> Dictionary:
	var packets: Array = []
	var cur := PackedByteArray()
	var read := 0
	var serial := -1
	while packets.size() < 2 and f.get_position() + 27 <= size and read < OGG_MAX:
		var hdr := f.get_buffer(27)
		if hdr.size() < 27 or hdr.slice(0, 4).get_string_from_ascii() != "OggS":
			break
		var segs := hdr[26]
		var table := f.get_buffer(segs)
		if table.size() < segs:
			break
		var page_serial := _le32(hdr, 14)
		var total := 0
		for v in table:
			total += v
		if f.get_position() + total > size:
			break
		read += 27 + segs + total
		var data := f.get_buffer(total)
		if serial == -1:
			serial = page_serial
		elif page_serial != serial:
			continue                     # andere Spur im selben Container
		var at := 0
		for v in table:
			if cur.size() + v > OGG_MAX:
				return _ogg_result(packets, f, size, serial, want_pic)
			cur.append_array(data.slice(at, at + v))
			at += v
			if v < 255:
				packets.append(cur)
				cur = PackedByteArray()
				if packets.size() >= 2:
					break
	return _ogg_result(packets, f, size, serial, want_pic)


static func _ogg_result(packets: Array, f: FileAccess, size: int, serial: int, want_pic: bool) -> Dictionary:
	if packets.is_empty():
		return {}
	var ident: PackedByteArray = packets[0]
	if ident.size() >= 8 and ident.slice(0, 8).get_string_from_ascii() == "OpusHead":
		return { "unsupported": true }
	if ident.size() < 16 or ident[0] != 1 or ident.slice(1, 7).get_string_from_ascii() != "vorbis":
		return {}
	var rate := _le32(ident, 12)
	var out := {}
	if packets.size() >= 2:
		out = vorbis_comments(packets[1], want_pic)
	var granule := _ogg_last_granule(f, size, serial)
	if rate > 0 and granule > 0:
		var ms := int(granule * 1000.0 / rate)
		if ms > 0 and ms < 86400000:
			out["dur"] = ms
	return out


## Kommentar-Paket („\x03vorbis“, Länge + Hersteller, Anzahl, je Länge + „SCHLÜSSEL=Wert“).
static func vorbis_comments(p: PackedByteArray, want_pic := false) -> Dictionary:
	var out := {}
	if p.size() < 11 or p[0] != 3 or p.slice(1, 7).get_string_from_ascii() != "vorbis":
		return out
	var pos := 7
	var vlen := _le32(p, pos)
	if vlen < 0 or pos + 4 + vlen > p.size():
		return out
	pos += 4 + vlen
	var n := _le32(p, pos)
	pos += 4
	if n < 0:
		return out
	for i in mini(n, COMMENTS_MAX):
		var l := _le32(p, pos)
		pos += 4
		if l < 0 or pos + l > p.size():
			break
		var c := p.slice(pos, pos + l)
		pos += l
		var eq := c.find(0x3D)          # „=“
		if eq <= 0:
			continue
		var key := c.slice(0, eq).get_string_from_ascii().to_lower()
		var val := c.slice(eq + 1)
		if key == "metadata_block_picture" or key == "coverart":
			if want_pic and not out.has("pic") and val.size() <= PIC_MAX * 4 / 3 + 1024:
				var raw := Marshalls.base64_to_raw(val.get_string_from_ascii())
				var img := flac_picture(raw) if key == "metadata_block_picture" else raw
				var ext := image_ext(img)
				if ext != "" and img.size() <= PIC_MAX:
					out["pic"] = img
					out["pic_ext"] = ext
			continue
		var field := str(VORBIS_KEYS.get(key, ""))
		if field == "" or (out.has(field) and field != "year"):
			continue
		_put(out, field, utf8(val))
	return out


## Bild aus einem FLAC-Bildblock (Art, MIME, Beschreibung, Maße, Daten – alles Big Endian).
static func flac_picture(b: PackedByteArray) -> PackedByteArray:
	var pos := 4
	var ml := _be32(b, pos)
	if ml < 0 or ml > 256:
		return PackedByteArray()
	pos += 4 + ml
	var dl := _be32(b, pos)
	if dl < 0 or dl > 65536:
		return PackedByteArray()
	pos += 4 + dl + 16
	var n := _be32(b, pos)
	pos += 4
	if n <= 0 or pos + n > b.size():
		return PackedByteArray()
	return b.slice(pos, pos + n)


## Granule der letzten Seite derselben Spur (Samples bis zum Ende). 0 = unbekannt.
static func _ogg_last_granule(f: FileAccess, size: int, serial: int) -> int:
	var start := maxi(0, size - OGG_TAIL)
	f.seek(start)
	var b := f.get_buffer(size - start)
	var i := b.size() - 27
	while i >= 0:
		if b[i] == 0x4F and b[i + 1] == 0x67 and b[i + 2] == 0x67 and b[i + 3] == 0x53 and _le32(b, i + 14) == serial:
			var g := b.decode_s64(i + 6)
			return g if g > 0 else 0
		i -= 1
	return 0


# --- WAV: RIFF-INFO und Länge ------------------------------------------------------------------

static func _wav(f: FileAccess, size: int, want_pic: bool) -> Dictionary:
	var out := {}
	var head := f.get_buffer(12)
	if head.size() < 12 or head.slice(0, 4).get_string_from_ascii() != "RIFF" or head.slice(8, 12).get_string_from_ascii() != "WAVE":
		return out
	var byte_rate := 0
	var data_len := 0
	var n := 0
	while f.get_position() + 8 <= size and n < RIFF_CHUNKS_MAX:
		n += 1
		var ch := f.get_buffer(8)
		var id := ch.slice(0, 4).get_string_from_ascii()
		var len := _le32(ch, 4)
		var at := f.get_position()
		if len < 0:
			break
		var end := at + len + (len & 1)
		match id:
			"fmt ":
				var fmt := f.get_buffer(mini(len, 64))
				byte_rate = maxi(0, _le32(fmt, 8))
			"data":
				data_len = mini(len, size - at)
			"LIST":
				if len <= 1024 * 1024:
					var lst := f.get_buffer(len)
					if lst.size() >= 4 and lst.slice(0, 4).get_string_from_ascii() == "INFO":
						var info := riff_info(lst.slice(4))
						for k in info:
							if not out.has(k):
								out[k] = info[k]
			"id3 ", "ID3 ":
				if len >= 10 and len <= TAG_MAX:
					var tag := f.get_buffer(len)
					if tag.size() >= 10 and tag[0] == 0x49 and tag[1] == 0x44 and tag[2] == 0x33:
						var t2 := id3v2(tag.slice(0, 10), tag.slice(10), want_pic)
						for k in t2:
							out[k] = t2[k]
		if end > size:
			break
		f.seek(end)
	if byte_rate > 0 and data_len > 0 and not out.has("dur"):
		out["dur"] = int(data_len * 1000.0 / byte_rate)
	return out


## Unterblöcke einer LIST/INFO-Liste (Kennung, Länge, Text mit Null).
static func riff_info(b: PackedByteArray) -> Dictionary:
	var out := {}
	var pos := 0
	var n := 0
	while pos + 8 <= b.size() and n < RIFF_CHUNKS_MAX:
		n += 1
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var len := _le32(b, pos + 4)
		pos += 8
		if len < 0 or pos + len > b.size():
			break
		var field := str(RIFF_KEYS.get(id, ""))
		if field != "" and not out.has(field):
			_put(out, field, utf8(_until_zero(b.slice(pos, pos + len), 1)))
		pos += len + (len & 1)
	return out
