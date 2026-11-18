extends "res://tests/probe_base.gd"
## Probe „Musikquelle wählbar“ (Demo): Einstellungen → Medien (Musikquelle, Musikordner, Browser),
## Musik ohne Ordner, danach mit einem erzeugten Beispielordner: Alben, Interpreten, Titel, ein
## Album, Läuft gerade mit „Als Nächstes“, Guide-Reiter Musik mit „Alben“ und die Kopfleiste.


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.4)


## Fokus auf das Bedienelement, in dem dieser Text steht.
func _focus_text(root: Node, text: String) -> bool:
	for c in Nav.focusables(root):
		if _has_text(c, text):
			Nav.focus(c, true)
			return true
	return false


func _has_text(n: Node, text: String) -> bool:
	if (n is Label or n is Button) and str(n.get("text")).contains(text):
		return true
	for ch in n.get_children():
		if _has_text(ch, text):
			return true
	return false


static func _le(n: int, w := 4) -> PackedByteArray:
	var b := PackedByteArray()
	for i in w:
		b.append((n >> (8 * i)) & 0xFF)
	return b


## Kurzes, stilles WAV mit Angaben (RIFF-INFO).
static func _wav(title: String, artist: String, album: String, track: int, ms: int) -> PackedByteArray:
	var fmt := _le(1, 2) + _le(1, 2) + _le(8000) + _le(16000) + _le(2, 2) + _le(16, 2)
	var lst := "INFO".to_ascii_buffer()
	for kv in [["INAM", title], ["IART", artist], ["IPRD", album], ["ITRK", str(track)]]:
		var v := str(kv[1]).to_utf8_buffer()
		v.append(0)
		if v.size() % 2 == 1:
			v.append(0)
		lst.append_array(str(kv[0]).to_ascii_buffer() + _le(v.size()) + v)
	var data := PackedByteArray()
	data.resize(16 * ms)
	var body := "WAVE".to_ascii_buffer()
	for ch in [["fmt ", fmt], ["LIST", lst], ["data", data]]:
		body.append_array(str(ch[0]).to_ascii_buffer() + _le((ch[1] as PackedByteArray).size()) + ch[1])
	return "RIFF".to_ascii_buffer() + _le(body.size()) + body


## Ruhiges Cover: Verlauf aus zwei Farben mit einem Kreis.
static func _cover(a: Color, b: Color) -> PackedByteArray:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var c := a.lerp(b, (x + y) / 510.0)
			var d := Vector2(x - 170, y - 96).length()
			if d < 54:
				c = c.lightened(0.35)
			img.set_pixel(x, y, c)
	return img.save_png_to_buffer()


static func _write(path: String, b: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func _make_library(dir: String) -> void:
	var albums := [
		["Nachtfahrt", "Lichtbogen", [Color("#1d2b64"), Color("#f8cdda")], ["Auffahrt", "Neonregen", "Tunnel", "Morgengrau"]],
		["Pixelwälder", "Lichtbogen", [Color("#134e5e"), Color("#71b280")], ["Moos", "Lichtung", "Unterholz"]],
		["Kassette B", "Die Halbtöne", [Color("#4b134f"), Color("#c94b4b")], ["Seite A", "Bandsalat", "Rückspulen", "Seite B", "Ende"]],
		["Sonntagssofa", "Mira Hell", [Color("#3a6186"), Color("#89253e")], ["Kaffee", "Regenfenster"]],
	]
	for al in albums:
		var adir := dir.path_join(str(al[1])).path_join(str(al[0]))
		_write(adir.path_join("folder.png"), _cover(al[2][0], al[2][1]))
		var i := 0
		for t in al[3]:
			i += 1
			_write(adir.path_join("%02d %s.wav" % [i, t]), _wav(str(t), str(al[1]), str(al[0]), i, 900 + i * 37))


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var dir := Config.path("probe_musik/Musik")
	_make_library(dir)
	# 1) Einstellungen: Musikquelle mit allen vier Wegen, „Auch Musik im Browser“ bei Windows.
	Config.set_value("system.music_mode", "tasten")
	await main.goto("settings", "medien")
	await wait(0.6)
	_focus_text(main.sections.settings, "Auch Musik im Browser")
	await shot("01_einstellungen_windows", 0.8)
	# 2) Eigene Musik ohne Ordner: Musik zeigt die Karte zum Einrichten.
	Config.set_value("system.music_mode", "lokal")
	Config.set_value("music.local_dir", "")
	main.sections.settings._rebuild_keep()
	await wait(0.6)
	_focus_text(main.sections.settings, "Musikordner")
	await shot("02_einstellungen_lokal_ohne_ordner", 0.8)
	await main.goto("music", "alben")
	await shot("03_musik_ohne_ordner", 1.0)
	# 3) Ordner gewählt: einlesen, Alben, Interpreten, Titel.
	Config.set_value("music.local_dir", dir)
	await wait(0.2)
	while Music.local.scanning:
		await wait(0.1)
	print("Eingelesen: %d Titel, %d Alben, %d Interpreten" % [Music.local.tracks.size(), Music.local.albums.size(), Music.local.artists.size()])
	await main.goto("music", "alben")
	await shot("04_alben", 1.2)
	await press("right")
	await shot("05_alben_fokus", 0.8)
	await main.goto("music", "interpreten")
	await shot("06_interpreten", 1.0)
	await main.goto("music", "titel")
	await shot("07_titel", 1.0)
	# 4) Album öffnen, ab dem zweiten Titel abspielen.
	await main.goto("music", "alben")
	await wait(0.6)
	await press("a")
	await shot("08_album", 1.0)
	await press("right")
	await press("down")
	await press("a")
	await wait(0.6)
	print("Läuft: %s · %s · danach %d" % [str(Music.now.get("title", "")), str(Music.local.context_name), Music.queue_list.size()])
	await _close_all()
	await main.goto("music", "jetzt")
	await shot("09_laeuft_gerade", 1.4)
	await press("right", 2)
	await press("a")
	await shot("10_zufall_an", 0.8)
	# 5) Guide → Musik mit „Alben“, dann die Alben-Liste über dem Guide.
	main.toggle_guide("musik")
	await shot("11_guide_musik", 1.2)
	LocalUi().open_albums_sheet(main)
	await shot("12_guide_alben", 1.0)
	await _close_all()
	# 6) Kopfleiste und Medien-Startseite zeigen den Titel.
	await main.goto("games")
	await shot("13_kopfleiste", 1.0)
	print("Kopfleiste: %s" % str(Music.now.get("title", "")))
	var was := bool(Music.now.get("playing", false))
	Music.play_pause()
	await wait(0.3)
	print("Pause/Abspielen: spielte %s → spielt %s" % [str(was), str(bool(Music.now.get("playing", false)))])


func LocalUi() -> GDScript:
	return load("res://src/ui/local_music_ui.gd")
