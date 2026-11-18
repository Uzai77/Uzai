extends "res://tests/probe_base.gd"
## Probe Plattenspieler und Konsolen (Demo): das Lowboard mit den Konsolen der Demo-Systeme, eine
## Konsole aus der Nähe, der Plattenspieler mit Cover (eigenes Testbild im Zwischenspeicher).
## Aufruf: siehe probe_base.gd, --uzai-script=res://tests/probe_plattenkonsole.gd

var z: Control


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


## Freie Kamera (wie während einer Fahrt): Ort und Ziel im Raum des Möbels.
func kamera(t: String, von: Vector3, auf: Vector3, fov := 50.0) -> void:
	var n: Node3D = z.welt.knoten[idx(t)]
	z.modus = "fahrt"
	var cam: Camera3D = z.welt.kamera
	cam.global_transform = Transform3D(Basis(), n.global_transform * von).looking_at(n.global_transform * auf, Vector3.UP)
	cam.fov = fov


func run() -> void:
	main.goto("games")
	await wait(1.0)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	z.raum.licht.z = "abend"
	z._licht_neu()
	await wait(0.5)
	kamera("medienwand", Vector3(0.0, 0.62, 1.55), Vector3(0, 0.3, 0.0), 52.0)
	await shot("01_lowboard_konsolen", 1.5)
	var tv: Node3D = z.welt.knoten[idx("medienwand")]
	var ks: Dictionary = tv.get_meta("konsolen", {})
	if ks.has("gc"):
		var k: Node3D = ks["gc"]
		konsole_an(k)
		var p := k.position
		kamera("medienwand", p + Vector3(0.16, 0.2, 0.42), p + Vector3(-0.02, 0.05, 0), 40.0)
		await shot("02_konsole_nah", 1.2)
	# Plattenspieler: ein eigenes Testbild als Cover im Zwischenspeicher, Musik läuft.
	var bild := Image.create(400, 400, false, Image.FORMAT_RGB8)
	for y in 400:
		for x in 400:
			bild.set_pixel(x, y, Color(0.85 - y / 900.0, 0.42 + x / 1400.0, 0.3 + 0.25 * sin(x * 0.03) * cos(y * 0.02)))
	var pfad := Config.path("cache/musik/cover/probe.png")
	DirAccess.make_dir_recursive_absolute(pfad.get_base_dir())
	bild.save_png(pfad)
	Music.now = { "id": "probe", "title": "Abendlicht", "artist": "Uzai", "art": pfad, "duration": 200000, "playing": true }
	await wait(2.5)
	var ps := idx("plattenspieler")
	if ps >= 0:
		kamera("plattenspieler", Vector3(0.12, 0.42, 0.55), Vector3(-0.03, 0.1, -0.05), 46.0)
		await shot("03_plattenspieler_cover", 1.0)
	# Einlegen ohne Bild: ein Spiel der PS2 läuft auf der PS2 (Lade auf, Disc hinein, LED an).
	var g: Dictionary = Library.by_system("ps2")[0]
	z.modus = "laufen"
	var ps2: Node3D = ks.get("ps2")
	if ps2 != null:
		konsole_aus(ps2)
		z._einlegen({ "art": "spiel", "daten": g })
		await wait(2.2)
		print("Einlegen PS2: LED an = ", ps2.get_meta("an", false), ", Disc drin = ", (ps2.get_meta("einlass") as Node3D).get_child_count())


func konsole_an(k: Node3D) -> void:
	preload("res://src/room/konsolen.gd").einstecken(k, Color("#c04a3a"))


func konsole_aus(k: Node3D) -> void:
	preload("res://src/room/konsolen.gd").strom(k, false)
