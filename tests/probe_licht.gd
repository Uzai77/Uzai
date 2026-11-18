extends "res://tests/probe_base.gd"
## Probe „Licht im Zimmer“: Blick vom Sofa-Eck auf Fernseher, Stehlampe und linke Wand – abends,
## nachts und am Tag, die Stehlampe an (UZAI_PROBE_FARBE: in dieser Farbe, z. B. ff4fa3), der
## Fernseher mit laufendem Spielbild. Dazu der Fernseher von nah (Ruhebild mit der Marke).
##
## Aufruf: UZAI_DATA=$(mktemp -d) xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . \
##   --resolution 1920x1080 -- --demo --no-boot --uzai-script=res://tests/probe_licht.gd --uzai-out=<ordner>
## UZAI_PROBE_ZEITEN=abend,nacht,tag (Vorgabe), UZAI_PROBE_STIMMUNG=<kennung> (z. B. neon).

const G := preload("res://src/room/gestalt.gd")

var z: Control


func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])
	z._rate = 40.0


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func stehen(p: Vector3, yaw: float, pitch: float) -> void:
	z.pos = p
	z.yaw = yaw
	z._yaw_soll = yaw
	z.pitch = pitch
	z._koerper_setzen(p)
	ziel()


## Ein buntes, helles Spielbild (Himmel, Wiese, Sonne) für den Fernseher.
func spielbild() -> Image:
	var img := Image.create(320, 180, false, Image.FORMAT_RGB8)
	for y in 180:
		for x in 320:
			var t := float(y) / 180.0
			var c := Color("#6fb6ff").lerp(Color("#d8ecff"), t * 1.6) if t < 0.6 else Color("#4caa3c").lerp(Color("#2f7a2a"), (t - 0.6) * 2.5)
			if Vector2(x - 250, y - 40).length() < 18.0:
				c = Color("#fff4c0")
			img.set_pixel(x, y, c)
	return img


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var stufe := OS.get_environment("UZAI_PROBE_STUFE")
	if stufe != "":
		Config.set_value("room.grafik", stufe)
	main.goto("games")
	await wait(0.8)
	main.open_room(true)
	await wait(3.0)
	z = Nav.top_layer()
	print("Zimmer offen: ", z != null and z.has_method("bauen_an"), " Stufe: ", z.stufe, " Renderer: ", RenderingServer.get_current_rendering_method())
	var farbe := OS.get_environment("UZAI_PROBE_FARBE")
	var sl := idx("stehlampe")
	if sl >= 0:
		z.raum.moebel[sl].an = true
		if farbe != "":
			z.raum.moebel[sl]["l"] = { "c": "#" + farbe }
	z.blick = "ich"
	# Fernseher von nah: das Ruhebild mit der Marke.
	z.raum.licht.z = "abend"
	z.raum.licht.st = ""
	z._licht_neu(false)
	stehen(Vector3(2.4, 0, 2.2), 0.05, -0.16)
	await wait(2.5)
	ziel()
	await shot("tv_ruhebild", 2.5)
	z.welt.tv_live(spielbild(), true)
	var zeiten := OS.get_environment("UZAI_PROBE_ZEITEN")
	var st := OS.get_environment("UZAI_PROBE_STIMMUNG")
	var liste := (zeiten if zeiten != "" else "abend,nacht,tag").split(",")
	if st != "":
		# Eine Stimmung bringt ihre Tageszeit, Lampen und Farben mit (gestalt.gd STIMMUNGEN).
		z.raum.licht.merge(G.stimmung(st), true)
		liste = [str(z.raum.licht.z)]
	for t in liste:
		z.raum.licht.z = t
		z.raum.licht.st = st
		z._licht_neu(false)
		stehen(Vector3(5.5, 0, 4.4), 0.98, -0.12)
		await wait(3.0)
		ziel()
		await shot("raum_" + t + ("_" + st if st != "" else ""), 3.0)
