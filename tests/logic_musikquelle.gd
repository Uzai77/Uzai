extends Node
## Musikquelle wählbar (Punkt 34): Tag-Leser (auch mit kaputten und übergroßen Dateien),
## Bibliothek aus einem Beispielordner, Pfade und Verknüpfungen, Warteschlange und Zufall,
## Wiedergabe, Merken und die Quellenwahl in Music, auch Spotify und eigene Musik zugleich (aktive
## Quelle). Alle Dateien erzeugt der Test selbst.
## Aufruf: godot --headless --path . res://tests/logic_musikquelle.tscn

const Tags := preload("res://src/core/music_tags.gd")
const LocalMusic := preload("res://src/core/music_local.gd")
const MusicS := preload("res://src/core/music.gd")
const Presence := preload("res://src/core/music_presence.gd")

var fails := 0
var root := ""


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	root = Config.path("musiktest/Musik")
	DirAccess.make_dir_recursive_absolute(root)
	_id3()
	_ogg()
	_wav()
	_broken()
	_real()
	_paths()
	_library()
	_queue()
	_gross()
	await _player()
	await _source()
	await _beide()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


# --- Dateien bauen ------------------------------------------------------------------------------

static func _ss(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F])


static func _be(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])


static func _le(n: int, w := 4) -> PackedByteArray:
	var b := PackedByteArray()
	for i in w:
		b.append((n >> (8 * i)) & 0xFF)
	return b


static func _txt(enc: int, s: String) -> PackedByteArray:
	var b := PackedByteArray([enc])
	match enc:
		0:
			for ch in s:
				b.append(ch.unicode_at(0) & 0xFF)
		1:
			b.append_array([0xFF, 0xFE])
			b.append_array(s.to_utf16_buffer())
		3:
			b.append_array(s.to_utf8_buffer())
	return b


## ID3v2.3/2.4-Tag aus [Kennung, Daten]-Paaren.
static func _id3tag(ver: int, frames: Array) -> PackedByteArray:
	var body := PackedByteArray()
	for f in frames:
		var data: PackedByteArray = f[1]
		body.append_array(str(f[0]).to_ascii_buffer())
		body.append_array(_ss(data.size()) if ver == 4 else _be(data.size()))
		body.append_array([0, 0])
		body.append_array(data)
	body.append_array(PackedByteArray([0, 0, 0, 0]))     # Auffüllung
	var out := PackedByteArray([0x49, 0x44, 0x33, ver, 0, 0])
	out.append_array(_ss(body.size()))
	out.append_array(body)
	return out


## Ein MPEG-1-Layer-III-Rahmen mit 128 kbit/s und 44,1 kHz, danach Füllbytes (konstante Bitrate).
static func _mpeg(bytes: int) -> PackedByteArray:
	var b := PackedByteArray([0xFF, 0xFB, 0x90, 0x64])
	b.resize(bytes)
	return b


static func _png() -> PackedByteArray:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.3, 0.2))
	return img.save_png_to_buffer()


static func _apic(img: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray([0])
	b.append_array("image/png".to_ascii_buffer())
	b.append_array([0, 3])                              # Art: Vorderseite
	b.append_array("Cover".to_ascii_buffer())
	b.append(0)
	b.append_array(img)
	return b


static func _write(path: String, b: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


## Ogg-Seite (Prüfsumme 0 – der Leser prüft sie nicht, er prüft Längen).
static func _ogg_page(packet: PackedByteArray, granule: int, serial: int, seq: int) -> PackedByteArray:
	var table := PackedByteArray()
	var n := packet.size()
	while n >= 255:
		table.append(255)
		n -= 255
	table.append(n)
	var b := "OggS".to_ascii_buffer()
	b.append_array([0, 0])
	b.append_array(_le(granule, 8))
	b.append_array(_le(serial))
	b.append_array(_le(seq))
	b.append_array(_le(0))
	b.append(table.size())
	b.append_array(table)
	b.append_array(packet)
	return b


static func _vorbis_ident(rate: int) -> PackedByteArray:
	var b := PackedByteArray([1])
	b.append_array("vorbis".to_ascii_buffer())
	b.append_array(_le(0))
	b.append(2)
	b.append_array(_le(rate))
	b.append_array(_le(0))
	b.append_array(_le(128000))
	b.append_array(_le(0))
	b.append_array([0xB8, 1])
	return b


static func _vorbis_comments(list: Array, count_override := -1) -> PackedByteArray:
	var b := PackedByteArray([3])
	b.append_array("vorbis".to_ascii_buffer())
	var vendor := "Uzai-Test".to_utf8_buffer()
	b.append_array(_le(vendor.size()))
	b.append_array(vendor)
	b.append_array(_le(list.size() if count_override < 0 else count_override))
	for c in list:
		var cb := str(c).to_utf8_buffer()
		b.append_array(_le(cb.size()))
		b.append_array(cb)
	b.append(1)
	return b


static func _wav_bytes(info: Dictionary, ms := 1000) -> PackedByteArray:
	var fmt := PackedByteArray()
	fmt.append_array(_le(1, 2))       # PCM
	fmt.append_array(_le(1, 2))       # mono
	fmt.append_array(_le(8000))
	fmt.append_array(_le(16000))      # Bytes je Sekunde
	fmt.append_array(_le(2, 2))
	fmt.append_array(_le(16, 2))
	var lst := "INFO".to_ascii_buffer()
	for k in info:
		var v := str(info[k]).to_utf8_buffer()
		v.append(0)
		if v.size() % 2 == 1:
			v.append(0)
		lst.append_array(str(k).to_ascii_buffer())
		lst.append_array(_le(v.size()))
		lst.append_array(v)
	var data := PackedByteArray()
	data.resize(16 * ms)
	var body := "WAVE".to_ascii_buffer()
	for ch in [["fmt ", fmt], ["LIST", lst], ["data", data]]:
		body.append_array(str(ch[0]).to_ascii_buffer())
		body.append_array(_le((ch[1] as PackedByteArray).size()))
		body.append_array(ch[1])
	var out := "RIFF".to_ascii_buffer()
	out.append_array(_le(body.size()))
	out.append_array(body)
	return out


# --- Tag-Leser ----------------------------------------------------------------------------------

func _id3() -> void:
	print("ID3 (MP3)")
	var p := root.path_join("Band/Album A/01 - Erstes.mp3")
	var tag := _id3tag(3, [["TIT2", _txt(1, "Größte Hits ♪")], ["TPE1", _txt(0, "Bänd")], ["TALB", _txt(3, "Album A")],
		["TPE2", _txt(3, "Bänd")], ["TRCK", _txt(0, "2/12")], ["TPOS", _txt(0, "1/2")], ["TYER", _txt(0, "2004")],
		["APIC", _apic(_png())]])
	var b := tag
	b.append_array(_mpeg(16000))
	_write(p, b)
	var t := Tags.read(p)
	check(str(t.get("title")) == "Größte Hits ♪" and str(t.get("artist")) == "Bänd" and str(t.get("album")) == "Album A",
			"v2.3: Titel (UTF-16), Interpret (Latin-1), Album (UTF-8)")
	check(int(t.get("track")) == 2 and int(t.get("disc")) == 1 and int(t.get("year")) == 2004 and str(t.get("album_artist")) == "Bänd",
			"Nummer „2/12“, CD, Jahr, Album-Interpret")
	check(absi(int(t.get("dur", 0)) - 1000) < 30 and not t.has("pic"),
			"Länge aus der Bitrate (≈ 1 s, %d ms), ohne Bild, wenn nicht gewünscht" % int(t.get("dur", 0)))
	var tp := Tags.read(p, true)
	check(tp.get("pic") is PackedByteArray and str(tp.get("pic_ext")) == "png", "eingebettetes Cover als PNG")
	# v2.4 mit Jahr als Datum, v2.2 mit drei Buchstaben, ID3v1 am Ende, Xing für die genaue Länge.
	var p4 := root.path_join("Band/Album A/02 Zweites.mp3")
	var x := _mpeg(600)
	x[36] = 0x58; x[37] = 0x69; x[38] = 0x6E; x[39] = 0x67      # „Xing“
	x.encode_u32(40, 0)
	x[43] = 1                                                     # Rahmen-Anzahl vorhanden
	x[44] = 0; x[45] = 0; x[46] = 0; x[47] = 77                   # 77 Rahmen × 1152 / 44100 ≈ 2011 ms
	var b4 := _id3tag(4,
			[["TIT2", _txt(3, "Zweites")], ["TDRC", _txt(3, "1999-05-01")], ["TPE2", _txt(3, "Bänd")], ["TALB", _txt(3, "Album A")], ["TRCK", _txt(3, "1")]])
	b4.append_array(x)
	_write(p4, b4)
	var t4 := Tags.read(p4)
	check(str(t4.get("title")) == "Zweites" and int(t4.get("year")) == 1999, "v2.4: Jahr aus „1999-05-01“")
	check(absi(int(t4.get("dur", 0)) - 2011) < 5, "Länge genau aus dem Xing-Kopf (%d ms)" % int(t4.get("dur", 0)))
	var v1 := PackedByteArray()
	v1.resize(128)
	v1[0] = 0x54; v1[1] = 0x41; v1[2] = 0x47
	var ttl := "Nur v1".to_ascii_buffer()
	for i in ttl.size():
		v1[3 + i] = ttl[i]
	var art := "Alte Band".to_ascii_buffer()
	for i in art.size():
		v1[33 + i] = art[i]
	v1[126] = 7
	var p1 := root.path_join("Einzeln/v1.mp3")
	var b1 := _mpeg(8000)
	b1.append_array(v1)
	_write(p1, b1)
	var t1 := Tags.read(p1)
	check(str(t1.get("title")) == "Nur v1" and str(t1.get("artist")) == "Alte Band" and int(t1.get("track")) == 7, "ID3v1 am Dateiende (mit Nummer)")
	# Großes Cover mitten im Tag: Ohne Bildwunsch wird es übersprungen statt gelesen, die Angaben dahinter kommen an.
	var bild := _png()
	var bild_kurz := bild.size()
	bild.resize(300000)
	var pg := root.path_join("Einzeln/gross.mp3")
	for ver in [3, 4]:
		var bg := _id3tag(ver, [["TIT2", _txt(3, "Mit Cover")], ["APIC", _apic(bild)], ["TPE1", _txt(3, "Hinten")], ["TRCK", _txt(0, "9")]])
		var tag_ende := bg.size()
		bg.append_array(_mpeg(16000))
		_write(pg, bg)
		var tg := Tags.read(pg)
		check(str(tg.get("title")) == "Mit Cover" and str(tg.get("artist")) == "Hinten" and int(tg.get("track", 0)) == 9
				and absi(int(tg.get("dur", 0)) - 1000) < 30 and not tg.has("pic"), "v2.%d mit großem Cover: Angaben davor und dahinter, Länge stimmt" % ver)
		var fg := FileAccess.open(pg, FileAccess.READ)
		var klein := Tags.id3_kleine(fg, ver, tag_ende)
		fg.close()
		check(klein.size() > 30 and klein.size() < 200, "v2.%d: gelesen werden nur die kleinen Rahmen (%d von %d Bytes)" % [ver, klein.size(), tag_ende])
		var tgp := Tags.read(pg, true)
		check(tgp.get("pic") is PackedByteArray and (tgp.pic as PackedByteArray).size() == 300000 and bild_kurz < 300000
				and str(tgp.get("title")) == "Mit Cover", "v2.%d: mit Bildwunsch kommt das Cover ganz" % ver)
	var kopf := func(ver: int, marken: int) -> PackedByteArray: return PackedByteArray([0x49, 0x44, 0x33, ver, 0, marken, 0, 0, 0, 0])
	check(Tags.id3_springbar(kopf.call(3, 0)) and Tags.id3_springbar(kopf.call(4, 0x80)) and not Tags.id3_springbar(kopf.call(3, 0x80))
			and not Tags.id3_springbar(kopf.call(4, 0x40)) and not Tags.id3_springbar(kopf.call(2, 0)),
			"Überspringen nur, wo die Rahmen so in der Datei stehen, wie ihre Größe sagt")
	# Kaputte Größen brechen nichts ab: Rahmen ragt über den Tag hinaus, Datei endet mitten im Rahmen.
	var heil := _txt(3, "Heil")
	var kaputt := PackedByteArray([0x49, 0x44, 0x33, 3, 0, 0])
	kaputt.append_array(_ss(90000))                              # der Tag behauptet, länger zu sein als die Datei
	kaputt.append_array("TIT2".to_ascii_buffer())
	kaputt.append_array(_be(heil.size()))
	kaputt.append_array([0, 0])
	kaputt.append_array(heil)
	kaputt.append_array("TPE1".to_ascii_buffer())
	kaputt.append_array(_be(5000))                               # Rahmen ragt über das Dateiende
	kaputt.append_array([0, 0, 3, 0x41])
	_write(pg, kaputt)
	check(str(Tags.read(pg).get("title")) == "Heil", "Rahmen über das Dateiende hinaus: was davor steht, bleibt")
	var head := PackedByteArray([0x49, 0x44, 0x33, 2, 0, 0])
	var fr := "TT2".to_ascii_buffer()
	var d := _txt(0, "Drei Zeichen")
	fr.append_array([0, 0, d.size()])
	fr.append_array(d)
	head.append_array(_ss(fr.size()))
	var t2 := Tags.id3v2(head.slice(0, 10), fr)
	check(str(t2.get("title")) == "Drei Zeichen", "ID3v2.2 (TT2)")
	check(Tags.unsync(PackedByteArray([1, 0xFF, 0, 2, 0xFF, 0, 0xFF])) == PackedByteArray([1, 0xFF, 2, 0xFF, 0xFF]), "Unsynchronisation rückgängig")
	check(Tags.utf16(PackedByteArray([0xFE, 0xFF, 0, 0x41, 0xD8, 0x3D, 0xDE, 0x00])) == "A😀", "UTF-16 Big Endian mit Ersatzpaar")
	check(Tags.utf8(PackedByteArray([0x4D, 0xFC, 0x6C, 0x6C])) == "Müll", "kaputtes UTF-8 wird als Latin-1 gelesen")


func _ogg() -> void:
	print("Ogg Vorbis")
	var img := _png()
	var block := _be(3)
	block.append_array(_be(9))
	block.append_array("image/png".to_ascii_buffer())
	block.append_array(_be(0))
	block.append_array(_be(4)); block.append_array(_be(4)); block.append_array(_be(24)); block.append_array(_be(0))
	block.append_array(_be(img.size()))
	block.append_array(img)
	var comments := _vorbis_comments(["TITLE=Ogg-Lied", "ARTIST=Sängerin", "ALBUM=Ogg-Album", "TRACKNUMBER=3",
		"DATE=2011", "METADATA_BLOCK_PICTURE=" + Marshalls.raw_to_base64(block), "UNBEKANNT=egal", "kaputt-ohne-gleich"])
	var b := _ogg_page(_vorbis_ident(44100), 0, 7, 0)
	b.append_array(_ogg_page(comments, 0, 7, 1))
	b.append_array(_ogg_page(PackedByteArray([5, 1, 2, 3]), 88200, 7, 2))
	var p := root.path_join("Sängerin/Ogg-Album/03.ogg")
	_write(p, b)
	var t := Tags.read(p, true)
	check(str(t.get("title")) == "Ogg-Lied" and str(t.get("artist")) == "Sängerin" and int(t.get("track")) == 3 and int(t.get("year")) == 2011,
			"Kommentare gelesen")
	check(int(t.get("dur", 0)) == 2000, "Länge aus der letzten Seite (2 s)")
	check(t.get("pic") is PackedByteArray and str(t.get("pic_ext")) == "png", "Cover aus METADATA_BLOCK_PICTURE")
	var opus := "OpusHead".to_ascii_buffer()
	opus.append_array([1, 2, 0, 0, 0x80, 0xBB, 0, 0, 0, 0, 0])
	var po := root.path_join("Sängerin/opus.ogg")
	_write(po, _ogg_page(opus, 0, 1, 0))
	check(bool(Tags.read(po).get("unsupported", false)), "Ogg mit Opus: nicht abspielbar erkannt")
	var huge := _vorbis_comments(["TITLE=x"], 0x7FFFFFFF)
	check(str(Tags.vorbis_comments(huge).get("title", "")) == "x", "riesige Kommentar-Anzahl: liest nur, was da ist")


func _wav() -> void:
	print("WAV")
	var p := root.path_join("Feld/Aufnahme.wav")
	_write(p, _wav_bytes({ "INAM": "Feldaufnahme", "IART": "Ich", "IPRD": "Draußen", "ITRK": "4" }))
	var t := Tags.read(p)
	check(str(t.get("title")) == "Feldaufnahme" and str(t.get("artist")) == "Ich" and str(t.get("album")) == "Draußen" and int(t.get("track")) == 4,
			"RIFF-INFO gelesen")
	check(int(t.get("dur", 0)) == 1000, "Länge aus Datenmenge und Bytes je Sekunde")
	check(LocalMusic.load_stream(p) != null, "Godot spielt die WAV-Datei ab (Laufzeit-Lader)")


func _broken() -> void:
	print("Kaputte und übergroße Dateien")
	var dir := Config.path("musiktest/kaputt")
	# ID3 mit riesiger Größe, Datei aber winzig.
	var a := PackedByteArray([0x49, 0x44, 0x33, 3, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F, 0x54, 0x49, 0x54, 0x32, 0x7F, 0xFF, 0xFF, 0xFF])
	_write(dir.path_join("riesig.mp3"), a)
	check(Tags.read(dir.path_join("riesig.mp3")) is Dictionary, "ID3-Größe 256 MB bei 18 Bytes: kein Absturz")
	# Rahmen größer als der Tag, kaputte Kennung, Text ohne Inhalt.
	var t := Tags.id3v2(PackedByteArray([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 20]), PackedByteArray([0x54, 0x49, 0x54, 0x32, 0, 0, 9, 0, 0, 0, 3, 0x41]))
	check(not t.has("title"), "Rahmen länger als der Tag wird nicht gelesen")
	var t2 := Tags.id3v2(PackedByteArray([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 20]), PackedByteArray([0x01, 0x02, 0x03, 0x04, 0, 0, 0, 2, 0, 0, 3, 0x41]))
	check(t2.is_empty(), "Unsinn als Rahmen-Kennung: Schluss")
	# APIC mit Nicht-Bild.
	var bad_pic := PackedByteArray([0])
	bad_pic.append_array("image/jpeg".to_ascii_buffer())
	bad_pic.append_array([0, 3, 0])
	bad_pic.append_array("<script>".to_ascii_buffer())
	var tb := _id3tag(3, [["APIC", bad_pic], ["TIT2", _txt(0, "Ok")]])
	var t3 := Tags.id3v2(tb.slice(0, 10), tb.slice(10), true)
	check(str(t3.get("title")) == "Ok" and not t3.has("pic"), "Bild, das kein JPEG/PNG ist, fällt weg")
	# Zufällige Bytes als MP3, OGG und WAV.
	var rng := RandomNumberGenerator.new()
	rng.seed = 34
	var ok := true
	for ext in ["mp3", "ogg", "wav"]:
		for i in 20:
			var junk := PackedByteArray()
			junk.resize(rng.randi_range(0, 3000))
			for k in junk.size():
				junk[k] = rng.randi() & 0xFF
			if i % 3 == 0 and ext == "ogg" and junk.size() > 30:
				junk[0] = 0x4F; junk[1] = 0x67; junk[2] = 0x67; junk[3] = 0x53
			if i % 3 == 0 and ext == "wav" and junk.size() > 12:
				for k in 4:
					junk[k] = "RIFF".unicode_at(k)
					junk[8 + k] = "WAVE".unicode_at(k)
			var jp := dir.path_join("zufall%d.%s" % [i, ext])
			_write(jp, junk)
			var r := Tags.read(jp, true)
			if not (r is Dictionary):
				ok = false
			for k in ["title", "artist", "album"]:
				if r.has(k) and str(r[k]).length() > Tags.TEXT_MAX:
					ok = false
	check(ok, "60 Dateien mit Zufallsbytes: kein Absturz, Texte begrenzt")
	# Text über der Grenze und Steuerzeichen.
	var long := "A".repeat(5000) + "\u0007"
	var tl := _id3tag(3, [["TIT2", _txt(3, long)]])
	var t4 := Tags.id3v2(tl.slice(0, 10), tl.slice(10))
	check(str(t4.get("title")).length() == Tags.TEXT_MAX, "Text auf %d Zeichen gekürzt" % Tags.TEXT_MAX)
	check(Tags.clean("a" + String.chr(1) + "b\nc\u200b") == "a b c\u200b", "Steuerzeichen werden zu Leerzeichen")


# --- Echte Dateien (von FFmpeg, wenn vorhanden: UZAI_TEST_FFMPEG) -----------------------------

func _real() -> void:
	var ff := OS.get_environment("UZAI_TEST_FFMPEG")
	if ff == "" or not FileAccess.file_exists(ff):
		print("Echte Dateien: übersprungen (kein FFmpeg)")
		return
	print("Echte Dateien von FFmpeg")
	var dir := ProjectSettings.globalize_path(Config.path("musiktest/echt"))
	DirAccess.make_dir_recursive_absolute(dir)
	var src := ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2.5"]
	var jobs := [
		["a.mp3",
			["-metadata", "title=Echt MP3", "-metadata", "artist=Lame Band", "-metadata", "album=Echt", "-metadata", "track=5/9", "-metadata", "date=2020", "-c:a",
			"libmp3lame", "-b:a", "96k"]],
		["b.ogg", ["-metadata", "title=Echt OGG", "-metadata", "artist=Vorbis Band", "-c:a", "libvorbis"]],
		["c.wav", ["-metadata", "title=Echt WAV", "-metadata", "artist=Wav Band"]],
	]
	for j in jobs:
		var args: Array = src + j[1] + [dir.path_join(j[0])]
		OS.execute(ff, PackedStringArray(args))
	OS.execute(ff,
			PackedStringArray(["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "color=c=red:s=8x8:d=1", "-frames:v", "1", dir.path_join("rot.png")]))
	OS.execute(ff,
			PackedStringArray(["-hide_banner", "-loglevel", "error", "-y", "-i", dir.path_join("a.mp3"), "-i", dir.path_join("rot.png"), "-map", "0", "-map", "1", "-c",
			"copy",
		"-id3v2_version", "3", "-metadata:s:v", "comment=Cover (front)", dir.path_join("d.mp3")]))
	var want := { "a.mp3": ["Echt MP3", "Lame Band"], "b.ogg": ["Echt OGG", "Vorbis Band"], "c.wav": ["Echt WAV", "Wav Band"] }
	for f in want:
		var t := Tags.read(dir.path_join(f))
		var st: AudioStream = LocalMusic.load_stream(dir.path_join(f))
		check(str(t.get("title")) == want[f][0] and str(t.get("artist")) == want[f][1], "%s: Titel und Interpret" % f)
		check(absi(int(t.get("dur", 0)) - 2500) < 150, "%s: Länge %d ms (2500 erwartet)" % [f, int(t.get("dur", 0))])
		check(st != null and absf(st.get_length() - 2.5) < 0.2, "%s: Godot spielt sie ab" % f)
	var ta := Tags.read(dir.path_join("a.mp3"))
	check(int(ta.get("track")) == 5 and str(ta.get("album")) == "Echt" and int(ta.get("year")) == 2020, "MP3: Nummer, Album, Jahr (ID3v2.4 von FFmpeg)")
	var td := Tags.read(dir.path_join("d.mp3"), true)
	check(str(td.get("pic_ext")) == "png" and str(td.get("title")) == "Echt MP3", "MP3 mit Cover (ID3v2.3): Bild gefunden")


# --- Pfade, Verknüpfungen, gemerkte Daten ------------------------------------------------------

func _paths() -> void:
	print("Pfade und Verknüpfungen")
	check(LocalMusic.inside(root + "/Band/a.mp3", root) and LocalMusic.inside(root.replace("/", "\\") + "\\Band\\a.mp3", root), "im Ordner, auch mit Backslashes")
	check(not LocalMusic.inside(root + "/../geheim.mp3", root) and not LocalMusic.inside(root + "2/a.mp3", root),
			"„..“ und ein Nachbarordner mit gleichem Anfang: draußen")
	check(not LocalMusic.inside(root + "/a.exe", root) and not LocalMusic.inside("file://" + root + "/a.mp3", root) and not LocalMusic.inside(root + "/a.mp3", ""),
			"fremde Endung, Adresse, leerer Ordner: nein")
	# Verknüpfungen nach draußen: Ordner und Datei.
	var outside := Config.path("musiktest/draussen")
	_write(outside.path_join("fremd.mp3"), _mpeg(4000))
	var da := DirAccess.open(root)
	var linked_dir := da.create_link(outside, root.path_join("Link-Ordner")) == OK
	var linked_file := da.create_link(outside.path_join("fremd.mp3"), root.path_join("link.mp3")) == OK
	if linked_dir and linked_file:
		var files := LocalMusic.list_files(root)
		var names := files.map(func(f: Array) -> String: return str(f[0]).get_file())
		check(not names.has("fremd.mp3") and not names.has("link.mp3"), "Einlesen folgt keiner Verknüpfung (Ordner und Datei)")
		check(not LocalMusic.playable(root.path_join("Link-Ordner/fremd.mp3"), root) and not LocalMusic.playable(root.path_join("link.mp3"), root),
				"Abspielen durch eine Verknüpfung: abgelehnt")
	else:
		check(false, "Verknüpfungen für den Test anlegen")
	check(LocalMusic.playable(root.path_join("Band/Album A/01 - Erstes.mp3"), root), "echte Datei im Ordner: erlaubt")
	# Gemerktes Verzeichnis mit untergeschobenen Einträgen.
	var idx := Config.path("musiktest/index.json")
	Config.write_json(idx, { "version": LocalMusic.INDEX_VERSION, "root": root, "files": {
		root + "/ok.mp3": { "m": 1, "s": 2, "t": { "title": "Gut", "track": "drei", "dur": 1e20, "pic": "x" } },
		"/etc/passwd.mp3": { "m": 1, "s": 2, "t": { "title": "Böse" } },
		root + "/../raus.mp3": { "m": 1, "s": 2, "t": {} },
		root + "/kaputt.mp3": "kein Eintrag" } })
	var got := LocalMusic.load_index(idx, root)
	check(got.size() == 1 and got.has(root + "/ok.mp3"), "gemerktes Verzeichnis: nur Einträge im Ordner")
	var e: Dictionary = got.get(root + "/ok.mp3", {})
	check(str(e.get("t", {}).get("title")) == "Gut" and not e.t.has("track") and not e.t.has("dur") and not e.t.has("pic"), "falsche Typen und Werte fallen weg")
	check(LocalMusic.load_index(idx, root + "/anders").is_empty(), "anderer Ordner: Verzeichnis gilt nicht")


# --- Bibliothek ----------------------------------------------------------------------------------

func _library() -> void:
	print("Bibliothek")
	var r := "/m"
	var E := func(path: String, t: Dictionary) -> Dictionary: return { "path": path, "t": t }
	var entries: Array = [
		E.call("/m/Band/A/02.mp3", { "title": "Zwei", "artist": "The Band", "album_artist": "The Band", "album": "A", "track": 2, "year": 2001 }),
		E.call("/m/Band/A/01.mp3", { "title": "Eins", "artist": "The Band", "album_artist": "The Band", "album": "A", "track": 1, "year": 2001 }),
		E.call("/m/Band/A/CD2/01.mp3", { "title": "Bonus", "artist": "The Band", "album_artist": "The Band", "album": "A", "track": 1, "disc": 2 }),
		E.call("/m/Sampler/x.mp3", { "title": "X", "artist": "Anna", "album": "Hits 2020" }),
		E.call("/m/Sampler/y.mp3", { "title": "Y", "artist": "Bert", "album": "Hits 2020" }),
		E.call("/m/Lose/03 - Mein_Lied.mp3", {}),
		E.call("/m/root.mp3", { "title": "Ganz oben", "artist": "Abba" }),
		E.call("/anderswo/x.mp3", { "title": "Fremd" }),
	]
	var lib := LocalMusic.build_library(entries, r, { "the band|a": "/m/Band/A/cover.jpg" })
	var albums: Array = lib.albums
	var tracks: Array = lib.tracks
	check(tracks.size() == 7, "Titel außerhalb des Ordners fehlen (%d)" % tracks.size())
	var a: Dictionary = albums.filter(func(x): return str(x.name) == "A")[0] if albums.any(func(x): return str(x.name) == "A") else {}
	check(not a.is_empty() and (a.tracks as Array).map(func(t): return str(t.title)) == ["Eins", "Zwei", "Bonus"],
			"Album über Ordner hinweg, sortiert nach CD und Nummer")
	check(str(a.get("art", "")) == "/m/Band/A/cover.jpg" and int(a.get("year", 0)) == 2001 and str(a.get("artist")) == "The Band",
			"Cover, Jahr, Interpret des Albums")
	# Teils ohne Nummer: Der frühere Vergleich (Nummer nur, wenn beide eine haben) ergab hier einen Kreis – die
	# Reihenfolge hing von der Folge im Ordner ab. Jetzt gilt für so ein Album der Dateiname, in jeder Ankunftsfolge.
	var halb: Array = [
		E.call("/m/Halb/B/03 z.mp3", { "title": "Drei", "artist": "Halb", "album": "B", "track": 1 }),
		E.call("/m/Halb/B/02 m.mp3", { "title": "Zwei", "artist": "Halb", "album": "B" }),
		E.call("/m/Halb/B/01 a.mp3", { "title": "Eins", "artist": "Halb", "album": "B", "track": 2 }),
	]
	var titel := func(liste: Array) -> Array:
		var gebaut: Dictionary = LocalMusic.build_library(liste, r)
		return ((gebaut.albums as Array)[0].tracks as Array).map(func(t): return str(t.title))
	var gedreht: Array = [halb[1], halb[2], halb[0]]
	var rueck: Array = [halb[2], halb[1], halb[0]]
	check(titel.call(halb) == ["Eins", "Zwei", "Drei"] and titel.call(gedreht) == ["Eins", "Zwei", "Drei"] and titel.call(rueck) == ["Eins", "Zwei", "Drei"],
			"Album mit teils fehlenden Nummern: nach Dateiname, in jeder Ankunftsfolge gleich (%s)" % str(titel.call(halb)))
	var jahre: Array = [
		E.call("/m/J/Z/1.mp3", { "title": "t", "artist": "Jahr", "album_artist": "Jahr", "album": "Z", "track": 1, "year": 2001 }),
		E.call("/m/J/M/1.mp3", { "title": "t", "artist": "Jahr", "album_artist": "Jahr", "album": "M", "track": 1 }),
		E.call("/m/J/A/1.mp3", { "title": "t", "artist": "Jahr", "album_artist": "Jahr", "album": "A", "track": 1, "year": 2005 }),
	]
	var namen := func(liste: Array) -> Array:
		var gebaut: Dictionary = LocalMusic.build_library(liste, r)
		return (gebaut.albums as Array).map(func(x): return str(x.name))
	var soll_jahre := ["Z", "A", "M"]
	check(namen.call(jahre) == soll_jahre and namen.call([jahre[1], jahre[2], jahre[0]]) == soll_jahre
			and namen.call([jahre[2], jahre[1], jahre[0]]) == soll_jahre,
			"Alben eines Interpreten: nach Jahr, die ohne Jahr dahinter – in jeder Ankunftsfolge gleich (%s)" % str(namen.call(jahre)))
	check(LocalMusic._track_less({ "disc": 0, "track": 0, "path": "b" }, { "disc": 0, "track": 3, "path": "a" })
			and not LocalMusic._track_less({ "disc": 0, "track": 3, "path": "a" }, { "disc": 0, "track": 0, "path": "b" }),
			"der Vergleich selbst ist eindeutig (nie A vor B und B vor A)")
	var s: Array = albums.filter(func(x): return str(x.name) == "Hits 2020")
	check(s.size() == 1 and str(s[0].artist) == LocalMusic.VARIOUS and int(s[0].count) == 2, "Sampler ohne Album-Interpret: ein Album, „Verschiedene Interpreten“")
	var lose: Array = tracks.filter(func(t): return str(t.path).ends_with("Mein_Lied.mp3"))
	check(not lose.is_empty() and str(lose[0].title) == "Mein Lied" and str(lose[0].album) == "Lose" and str(lose[0].artist) == LocalMusic.UNKNOWN_ARTIST,
			"ohne Angaben: Titel aus dem Dateinamen, Album aus dem Ordner")
	check(LocalMusic.artist_from_path("/m/Die Probe/Nachtfahrt/01 Auffahrt.wav", "/m") == "Die Probe",
			"ohne Angaben: Interpret aus dem Ordner über dem Album")
	check(LocalMusic.artist_from_path("/m/Lose/Mein_Lied.mp3", "/m") == LocalMusic.UNKNOWN_ARTIST
			and LocalMusic.artist_from_path("/m/Ganz oben.mp3", "/m") == LocalMusic.UNKNOWN_ARTIST,
			"Album direkt im Musikordner oder Datei ganz oben: Interpret bleibt unbekannt")
	var top: Array = tracks.filter(func(t): return str(t.title) == "Ganz oben")
	check(not top.is_empty() and str(top[0].album) == LocalMusic.NO_ALBUM, "Datei direkt im Musikordner: „Ohne Album“")
	var names: Array = (lib.artists as Array).map(func(x): return str(x.name))
	check(names.find("Abba") < names.find("The Band") and names.back() == LocalMusic.VARIOUS,
			"Interpreten sortiert („The Band“ unter B), Sammlungen zuletzt (%s)" % str(names))
	check(str(tracks[0].uri).begins_with("lokal:") and str(tracks[0].id).begins_with("lokal:"), "Titel mit eigener Kennung „lokal:“")
	check(LocalMusic.title_from_file("C:/Musik/07. Song_Name.ogg") == "Song Name", "Nummer vorn im Dateinamen fällt weg")


# --- Warteschlange ------------------------------------------------------------------------------

## Eine große Sammlung: Verzeichnis lesen und Bibliothek bauen dürfen das Bild nicht lange anhalten.
func _gross() -> void:
	print("Große Sammlung (Zeiten)")
	var wurzel := Config.path("musiktest/Gross")
	var eintraege: Array = []
	for i in 6000:
		eintraege.append({ "path": "%s/Band %d/Album %d/%02d - Lied %d.mp3" % [wurzel, i % 120, i % 600, i % 12 + 1, i], "m": 1700000000 + i, "s": 4000000 + i,
			"t": { "title": "Lied Nummer %d mit etwas Titel" % i, "artist": "Band %d" % (i % 120), "album": "Album %d" % (i % 600),
				"album_artist": "Band %d" % (i % 120), "track": i % 12 + 1, "year": 1990 + i % 30, "dur": 200000 + i } })
	var datei := Config.path("musiktest/gross_index.json")
	var t0 := Time.get_ticks_msec()
	LocalMusic.save_index(datei, wurzel, eintraege)
	var t1 := Time.get_ticks_msec()
	var alt: Dictionary = LocalMusic.load_index(datei, wurzel)
	var t2 := Time.get_ticks_msec()
	var lib: Dictionary = LocalMusic.build_library(eintraege, wurzel)
	var t3 := Time.get_ticks_msec()
	print("    6000 Titel: Verzeichnis schreiben %d ms, lesen und prüfen %d ms, Bibliothek bauen %d ms" % [t1 - t0, t2 - t1, t3 - t2])
	check(alt.size() == 6000 and (lib.tracks as Array).size() == 6000 and (lib.albums as Array).size() == 600 and (lib.artists as Array).size() == 120,
			"6000 Titel: Verzeichnis und Bibliothek vollständig")
	check(str(alt[str(eintraege[5].path)].t.title) == "Lied Nummer 5 mit etwas Titel" and int(alt[str(eintraege[5].path)].t.track) == 6, "Angaben kommen unverändert zurück")
	check(Tags.clean("Sauberer Titel") == "Sauberer Titel" and Tags.clean("  a  b\tc\u0085d ") == "a b c d" and Tags.clean("x".repeat(400)).length() == Tags.TEXT_MAX
			and Tags.clean(" " + "y".repeat(400)).length() == Tags.TEXT_MAX and Tags.clean("") == "", "Angaben säubern: schneller Weg und gründlicher ergeben dasselbe")


func _queue() -> void:
	print("Warteschlange")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var o := LocalMusic.make_order(10, 4, true, rng)
	var sorted := o.duplicate()
	sorted.sort()
	check(o[0] == 4 and sorted == range(10) and o != range(10), "Zufall: gewählter Titel zuerst, jeder genau einmal")
	check(LocalMusic.make_order(5, 2, false) == [0, 1, 2, 3, 4], "ohne Zufall: der Reihe nach")
	check(LocalMusic.next_pos(2, 3, "off", true) == -1 and LocalMusic.next_pos(2, 3, "context", true) == 0, "Ende der Liste: Schluss bzw. von vorn")
	check(LocalMusic.next_pos(1, 3, "track", true) == 1 and LocalMusic.next_pos(1, 3, "track", false) == 2,
			"Titel wiederholen: am Ende ja, „Weiter“ geht trotzdem weiter")
	check(LocalMusic.prev_pos(0, 3, "off") == 0 and LocalMusic.prev_pos(0, 3, "context") == 2, "Zurück am Anfang")


# --- Wiedergabe ---------------------------------------------------------------------------------

func _player() -> void:
	print("Wiedergabe")
	var dir := Config.path("musiktest/Spielen")
	for i in 3:
		_write(dir.path_join("Album/%02d.wav" % (i + 1)), _wav_bytes({ "INAM": "Lied %d" % (i + 1), "IART": "Test", "IPRD": "Album", "ITRK": str(i + 1) }, 1500))
	_write(dir.path_join("Album/folder.png"), _png())
	Config.set_value("music.local_dir", dir)
	var lm = LocalMusic.new()
	add_child(lm)
	await lm.scan(true)
	check((lm.tracks as Array).size() == 3 and (lm.albums as Array).size() == 1, "eingelesen: 3 Titel, 1 Album")
	check(str((lm.albums as Array)[0].art).ends_with("folder.png"), "Albumbild aus folder.png im Ordner")
	var album: Dictionary = (lm.albums as Array)[0]
	lm.play_tracks(album.tracks, 1, str(album.akey), "Album")
	await _frames(20)
	var n: Dictionary = lm.now_dict()
	check(str(n.get("title")) == "Lied 2" and bool(n.get("playing")) and str(n.get("source")) == "lokal", "spielt ab dem gewählten Titel")
	check(absi(int(n.get("duration", 0)) - 1500) < 50, "Länge vom geladenen Klang (%d ms)" % int(n.get("duration", 0)))
	check((lm.upcoming() as Array).map(func(t): return str(t.title)) == ["Lied 3"], "Als Nächstes: der Rest des Albums")
	lm.toggle()
	var at: int = lm.position_ms()
	await _frames(10)
	check(not lm.playing() and lm.position_ms() == at, "Pause hält die Stelle")
	lm.toggle()
	lm.next()
	lm.toggle()
	await _frames(20)
	check(str(lm.current().title) == "Lied 3" and not lm.playing(), "Pause, während der nächste Titel lädt: bleibt angehalten")
	lm.toggle()
	check(lm.playing(), "Weiter")
	lm.previous()
	await _frames(20)
	check(str(lm.current().title) == "Lied 2", "Zurück (am Anfang des Titels)")
	lm.enqueue((album.tracks as Array)[0])
	check(str((lm.upcoming() as Array)[0].title) == "Lied 1", "X: kommt als Nächstes")
	lm.set_shuffle(true)
	check(str(lm.current().title) == "Lied 2" and lm.shuffle, "Zufall an: der laufende Titel bleibt")
	lm.cycle_repeat()
	check(lm.repeat == "context", "Wiederholen: aus → Liste")
	lm.set_volume(130)
	check(lm.volume == 100 and int(Config.get_value("music.local_volume", 0)) == 100, "Lautstärke begrenzt und gemerkt")
	lm.set_volume(80)
	# Untergeschobener Titel von draußen wird nicht gespielt.
	lm.play_tracks([{ "path": "/etc/hosts.wav", "title": "Böse", "uri": "lokal:/etc/hosts.wav" }], 0)
	check(str(lm.current().get("title", "")) != "Böse", "Titel außerhalb des Musikordners: wird nicht eingereiht")
	lm._save_state()
	var lm2 = LocalMusic.new()
	add_child(lm2)
	await lm2.scan()
	lm2.restore()
	check(str(lm2.current().get("title", "")) == str(lm.current().title) and not lm2.playing(),
			"nach dem Neustart: letzte Warteschlange da, spielt nicht von selbst")
	# Gemerkter Stand mit fremdem Pfad.
	Config.write_json(LocalMusic.state_path(), { "root": LocalMusic.root(), "paths": ["/etc/passwd"], "pos": 0 })
	var lm3 = LocalMusic.new()
	add_child(lm3)
	await lm3.scan()
	lm3.restore()
	check(lm3.current().is_empty(), "gemerkte Warteschlange mit fremdem Pfad: nichts übernommen")
	# Fehlt inzwischen ein Titel vor dem zuletzt gehörten, bleibt es beim selben Titel (vorher: der danach).
	var alle: Array = (lm3.tracks as Array).map(func(t): return str(t.path))
	alle.sort()
	Config.write_json(LocalMusic.state_path(), { "root": LocalMusic.root(), "paths": ["%s/weg.wav" % dir, alle[0], alle[1], alle[2]], "pos": 2, "ms": 700 })
	lm3.restore()
	check(str(lm3.current().get("path", "")) == str(alle[1]) and lm3.position_ms() == 700, "Titel davor fehlt: derselbe Titel an derselben Stelle")
	Config.write_json(LocalMusic.state_path(), { "root": LocalMusic.root(), "paths": [alle[0], "%s/weg.wav" % dir, alle[2]], "pos": 1, "ms": 700,
		"shuffle": "ja", "repeat": 5 })
	lm3.restore()
	check(str(lm3.current().get("path", "")) == str(alle[2]) and lm3.position_ms() == 0 and not lm3.shuffle and lm3.repeat == "off",
			"der Titel selbst fehlt: der nächste von vorn; Angaben anderer Art brechen nichts ab")
	# Große Sammlung: Die Warteschlange ist das Stück rund um den gewählten Titel.
	check(LocalMusic.fenster_ab(100, 70) == 0 and LocalMusic.fenster_ab(5000, 10) == 0 and LocalMusic.fenster_ab(5000, 3000) == 2500
			and LocalMusic.fenster_ab(5000, 4999) == 3000, "Fenster der Warteschlange um den gewählten Titel")
	var viele: Array = []
	for i in LocalMusic.QUEUE_MAX + 500:
		var t: Dictionary = (lm3.tracks as Array)[i % 3].duplicate()
		t["nr"] = i
		viele.append(t)
	lm3.play_tracks(viele, LocalMusic.QUEUE_MAX + 400)
	check(int(lm3.current().get("nr", -1)) == LocalMusic.QUEUE_MAX + 400 and (lm3.queue as Array).size() == LocalMusic.QUEUE_MAX,
			"Titel hinter der Höchstzahl gewählt: genau er spielt (vorher: der erste)")
	lm3.stop()
	lm.stop()
	check(not lm.playing(), "Anhalten beim Wechsel der Quelle")
	for x in [lm, lm2, lm3]:
		x.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Quellenwahl ----------------------------------------------------------------------------------

func _source() -> void:
	print("Quellenwahl")
	check(not MusicS.is_music_app("chrome.exe", MusicS.PT_MUSIC) and MusicS.is_music_app("chrome.exe", MusicS.PT_MUSIC, true), "Browser nur, wenn eingeschaltet")
	check(not MusicS.is_music_app("YouTube.exe", 0, true) and MusicS.is_music_app("AppleInc.AppleMusicWin_nzyj5cx40ttqa!App", 0),
			"YouTube-App bleibt draußen, Apple Music zählt")
	var f: Dictionary = MusicS.filter_for(true)
	check((f.allow as Array).has("firefox") and not (f.deny as Array).has("firefox") and (f.deny as Array).has("youtube"), "Liste für den Helfer mit Browsern")
	var Guide := load("res://src/ui/layers/guide.gd")
	var lok := { "title": "Lied", "source": "lokal", "volume": 80 }
	check(Guide.volume_target("musik", false, false, lok, false) == "lokal" and Guide.volume_hint("lokal") == "Musik-Lautstärke",
			"Guide: LT/RT stellen die eigene Musik, auch ohne Spotify-Konto")
	Config.set_value("system.music_mode", "lokal")
	await get_tree().create_timer(0.3).timeout
	while Music.local.scanning:
		await get_tree().process_frame
	check(Music.local_on() and not (Music.local.tracks as Array).is_empty(), "Quelle „lokal“: Music liest den Ordner ein")
	Music.play_list(Music.local.albums[0].tracks, 0)
	await _frames(20)
	check(str(Music.now.get("source")) == "lokal" and bool(Music.now.get("playing")) and str(Music.local.context_name) == "Album",
			"Music.now zeigt die eigene Musik, ganzes Album als Liste")
	check(Music.queue_list.size() == 2, "Warteschlange für „Als Nächstes“ (%d)" % Music.queue_list.size())
	var v: Dictionary = await Music.change_volume(-10)
	check(bool(v.ok) and str(v.via) == "lokal" and int(Music.local.volume) == 70, "Lautstärke-Regler stellt nur den eigenen Player")
	Music.play_pause()
	await _frames(2)
	check(not bool(Music.now.get("playing")), "Pause über Music")
	var act := Presence.activity(Music.now, Music.progress_ms(), 1000000)
	check(act.is_empty(), "Discord-Status: angehalten steht nichts da")
	Music.play_pause()
	await _frames(2)
	act = Presence.activity(Music.now, Music.progress_ms(), 1000000)
	check(str(act.get("details")) == "Lied 1" and not act.has("image") and not act.has("buttons"), "Discord-Status: Titel, kein lokales Bild, kein Spotify-Knopf")
	check(not Presence.neu_setzen("a", 1004, "a", 1005) and not Presence.neu_setzen("a", 1005, "a", 1004) and not Presence.neu_setzen("a", 1007, "a", 1004),
			"Discord-Status: der Beginn schwankt um eine Sekunde, auch über eine Fünfergrenze: nicht neu senden")
	check(Presence.neu_setzen("b", 1004, "a", 1004) and Presence.neu_setzen("a", 1040, "a", 1004) and Presence.neu_setzen("a", 1004, "", 0),
			"Discord-Status: neuer Titel, Sprung im Titel oder noch nichts gezeigt: senden")
	Music.toggle_like()
	check(not bool(Music.now.get("liked")), "Herz gibt es bei eigener Musik nicht")
	Config.set_value("system.music_mode", "tasten")
	await _frames(2)
	check(not Music.local.playing() and Music.now.get("source", "") != "lokal", "andere Quelle: eigene Musik hält an")


# --- Spotify und eigene Musik zugleich ------------------------------------------------------------

func _beide() -> void:
	print("Spotify und eigene Musik")
	# Spotify „verbunden“, aber jede Anfrage geht ins Leere (nichts verlässt den Rechner).
	for k in ["_api_base", "_accounts", "_spclient", "_partner", "_clienttoken_url"]:
		Music.set(k, "http://127.0.0.1:9")
	var View := load("res://src/ui/sections/music_view.gd")
	Config.set_value("system.music_mode", "lokal")
	await get_tree().create_timer(0.3).timeout
	while Music.local.scanning:
		await get_tree().process_frame
	var v = View.new()
	check((v.subtabs() as Array).map(func(t: Dictionary) -> String: return str(t.id)) == ["alben", "interpreten", "titel", "jetzt"],
			"ohne Spotify: wie bisher nur die eigene Sammlung")
	Music.play_list(Music.local.albums[0].tracks, 0)
	await _frames(20)
	Config.set_value("accounts.spotify_client_id", "0123456789abcdef0123456789abcdef")
	Config.set_value("accounts.spotify_refresh", "nur-ein-test")
	Config.set_value("system.music_mode", "spotify")
	await _frames(5)
	check(Music.has_spotify() and Music.beide() and Music.lokal_da(), "Spotify mit Musikordner: beide Quellen")
	check(Music.aktiv == "lokal" and Music.local_on() and Music.local.wants_play() and str(Music.now.get("source")) == "lokal",
			"Spotify verbunden, während die eigene Musik läuft: sie spielt weiter")
	var ids: Array = (v.subtabs() as Array).map(func(t: Dictionary) -> String: return str(t.id))
	check(ids.has("fuerdich") and ids.has("playlists") and ids.has("eigene") and not ids.has("alben"), "Musik-Tab: Spotify-Reiter und ein Reiter „Eigene Musik“")
	await Music.play_context("spotify:playlist:test")
	check(Music.aktiv == "spotify" and not Music.local_on() and not Music.local.wants_play() and str(Music.now.get("source", "")) != "lokal",
			"Playlist von Spotify gestartet: eigene Musik hält an, Läuft gerade folgt Spotify")
	# Spotify spielt (wie eine Abfrage es meldet), dann ein eigenes Album.
	Music.now = { "id": "sp1", "uri": "spotify:track:sp1", "title": "Von Spotify", "artist": "Band", "playing": true, "device": "Handy" }
	Music.queue_list = [{ "id": "sp2", "uri": "spotify:track:sp2", "title": "Danach" }]
	var heard := [0]
	var count_q := func() -> void: heard[0] += 1
	Music.quelle_changed.connect(count_q)
	Music.play_list(Music.local.albums[0].tracks, 1)
	await _frames(20)
	check(Music.aktiv == "lokal" and str(Music.now.get("source")) == "lokal" and bool(Music.now.get("playing")) and heard[0] == 1,
			"eigenes Album gestartet: es spielt, Guide und Musik-Tab hören vom Wechsel")
	var act := Presence.activity(Music.now, Music.progress_ms(), 1000000)
	check(str(act.get("details")) == str(Music.now.get("title")) and not act.has("buttons"), "Discord-Status: der eigene Titel")
	check(str(Music._spotify_now.get("title")) == "Von Spotify" and not bool(Music._spotify_now.get("playing")), "Spotify gilt als angehalten")
	check(not Music.queue_list.is_empty() and str(Music.queue_list[0].uri).begins_with("lokal:"), "Als Nächstes: die eigene Warteschlange")
	Music.load_queue()
	await Music.poll()
	check(str(Music.now.get("source")) == "lokal" and str(Music.queue_list[0].uri).begins_with("lokal:"), "Abfragen bei Spotify überschreiben die eigene Musik nicht")
	var title := str(Music.now.get("title"))
	Music.play_pause()
	await _frames(2)
	check(not Music.local.playing() and Music.aktiv == "lokal", "X: Pause trifft die eigene Musik")
	Music.next()
	await _frames(10)
	check(str(Music.now.get("title")) != title and str(Music.now.get("source")) == "lokal", "Nächster Titel: in der eigenen Musik")
	await Music.play_context("spotify:playlist:test")
	check(Music.aktiv == "spotify" and not Music.local.wants_play() and str(Music.now.get("title")) == "Von Spotify"
			and str(Music.queue_list[0].get("id")) == "sp2" and heard[0] == 2, "wieder Spotify: Läuft gerade und Als Nächstes von Spotify")
	Music.quelle_changed.disconnect(count_q)
	Config.set_value("music.local_dir", "")
	await _frames(2)
	ids = (v.subtabs() as Array).map(func(t: Dictionary) -> String: return str(t.id))
	check(not Music.beide() and not Music.local_on() and ids.has("eigene") and ids.has("fuerdich"),
			"ohne Musikordner: Spotify wie bisher, dazu der Reiter „Eigene Musik“ mit der Ordnerwahl")
	v.free()
	Config.set_value("accounts.spotify_client_id", "")
	Config.set_value("accounts.spotify_refresh", "")
	Config.set_value("system.music_mode", "tasten")
