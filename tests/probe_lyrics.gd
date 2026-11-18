extends "res://tests/probe_base.gd"
## „Jetzt läuft“ groß (jetzt_laeuft.gd): Einstieg über das Cover im Guide-Reiter Musik, die
## Großansicht mit zeitgenauem Liedtext und ohne Liedtext (Cover mittig). Ohne Netz: Cover selbst
## gemalt, Liedtext vorab im Speicher. Bilder: lyrics_*.png.

const Lyrics := preload("res://src/core/lyrics.gd")


## Ein Cover zum Zeigen: warme Fläche mit Kreis (selbst gemalt, keine fremden Bilder).
func _cover() -> String:
	var img := Image.create(600, 600, false, Image.FORMAT_RGBA8)
	var a := Color("#E0603A")
	var b := Color("#3B2A7A")
	for y in 600:
		for x in 600:
			var c := a.lerp(b, clampf((x * 0.4 + y * 0.8) / 720.0, 0.0, 1.0))
			var d := Vector2(x - 380, y - 230).length()
			if d < 150.0:
				c = c.lerp(Color("#F4C76B"), clampf((150.0 - d) / 12.0, 0.0, 1.0))
			img.set_pixel(x, y, c)
	var p := Config.path("probe_cover.png")
	img.save_png(p)
	return p


func _focus_key(key: String, dirs: Array) -> void:
	for d in dirs:
		if str(Nav.focused().get_meta("uz_key", "")) == key:
			return
		await press(d, 1, 0.15)


func run() -> void:
	var now: Dictionary = Music.now.duplicate()
	now["art"] = _cover()
	Music.now = now
	var lrc := ""
	var zeilen := ["Licht fällt durch das offene Fenster", "Die Straße schläft noch, nur wir zwei", "Ein Lied, das keiner kennt", "",
		"Wir zählen leise bis zum Morgen", "Und jede Zahl ist ein Versprechen", "Halt still, gleich kommt der Ton", "Und dann sind wir wach"]
	for i in 60:
		lrc += "[%02d:%02d.00] %s\n" % [floori(i * 4 / 60.0), (i * 4) % 60, zeilen[i % zeilen.size()]]
	var key := Lyrics.key_of(str(now.get("title", "")), str(now.get("artist", "")))
	Lyrics._cache[key] = Lyrics.parse(lrc, "")
	Music.updated.emit()
	main.toggle_guide("musik")
	await wait(1.4)
	await _focus_key("m:gross", ["up", "up", "up", "left", "up", "left"])
	print("LY Fokus: ", Nav.focused().get_meta("uz_key", ""))
	await shot("lyrics_guide_cover", 0.4)
	await press("a", 1, 2.2)
	print("LY Ebene: ", Nav.top_layer().get_script().resource_path if Nav.top_layer() else "-")
	await shot("lyrics_gross", 0.3)
	await press("b", 1, 0.6)
	# Ohne Liedtext: das Cover allein in der Mitte.
	Lyrics._cache[key] = Lyrics.result("keine")
	await press("a", 1, 2.0)
	await shot("lyrics_ohne_text", 0.3)
	await press("b", 1, 0.5)
