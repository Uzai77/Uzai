extends "res://tests/probe_base.gd"
## Probe „Zimmer realistisch“: dieselben drei Kameras vorher und nachher – Ich-Ansicht am Abend mit
## Blick auf Fernseher und Sofa, das Lowboard mit den Konsolen von nah, die Figur im Schulterblick.
## Dazu eine Tagesansicht mit Fenster. Software-Grafik (xvfb) ist langsam: die Kamera springt an
## ihr Ziel, Bilder mit etwas Wartezeit (GI und Schatten brauchen ein paar Bilder).
##
## Aufruf: UZAI_DATA=$(mktemp -d) xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . \
##   --resolution 1920x1080 -- --demo --no-boot --uzai-script=res://tests/probe_zreal.gd --uzai-out=<ordner>

var z: Control


func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])
	z._rate = 40.0


## Ein Bild – mit UZAI_PROBE_NUR=<name> nur dieses eine (die anderen Stellen werden nur angefahren).
func schuss(name: String, t: float) -> void:
	var nur := OS.get_environment("UZAI_PROBE_NUR")
	if nur == "" or nur == name:
		await shot(name, t)


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func vor(t: String, abstand: float, hoehe := 1.62, seitlich := 0.0) -> void:
	var i := idx(t)
	var n: Node3D = z.welt.knoten[i]
	var vorn := n.transform.basis.z.normalized()
	var rechts := n.transform.basis.x.normalized()
	var mitte: Vector3 = (z.welt.boxen[i] as AABB).get_center()
	z.pos = Vector3(mitte.x, 0, mitte.z) + vorn * abstand + rechts * seitlich
	var dir := mitte - Vector3(z.pos.x, hoehe, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())


func zeit(t: String) -> void:
	z.raum.licht.z = t
	z.raum.licht.st = ""
	z._licht_neu(false)


func stehen(p: Vector3, yaw: float, pitch: float) -> void:
	z.pos = p
	z.yaw = yaw
	z._yaw_soll = yaw
	z.pitch = pitch
	z._koerper_setzen(p)
	ziel()


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
	# 1. Ich-Ansicht am Abend: Fernseher, Lowboard, Sofa.
	zeit("abend")
	z.blick = "ich"
	stehen(Vector3(5.0, 0, 4.35), 0.42, -0.1)
	await wait(1.5)
	z._ziel = -2
	z._ziel_suchen()
	ziel()
	await schuss("01_ich_abend", 3.0)
	# 2. Lowboard mit Konsolen von nah (Hocke).
	vor("medienwand", 1.25, 0.9, 0.0)
	z.pitch = -0.32
	stehen(z.pos, z.yaw, z.pitch)
	z._duck_um = true
	await wait(1.2)
	ziel()
	await schuss("02_lowboard_konsolen", 2.5)
	z._duck_um = false
	# 3. Schulterblick auf die Figur.
	z.blick = "schulter"
	stehen(Vector3(3.2, 0, 4.0), 2.3, -0.12)
	await wait(1.2)
	ziel()
	await schuss("03_schulterblick", 2.5)
	# 4. Tag, Blick von der Tür zum Fenster.
	z.blick = "ich"
	zeit("tag")
	stehen(Vector3(5.6, 0, 1.4), 1.25, -0.06)
	await wait(1.5)
	ziel()
	await schuss("04_ich_tag_fenster", 3.0)
	# 5. Gesicht der Figur: Fotomodus (die Figur dreht sich zur Kamera), Kamera dicht vor den Kopf.
	stehen(Vector3(3.0, 0, 2.6), 0.0, 0.0)
	await wait(0.5)
	z.fotomodus()
	await wait(0.8)
	var km: Vector3 = z.bewohner.avatar.kopf_mitte()
	var fp: Vector3 = z._foto.pos
	var hin := Vector3(fp.x - km.x, 0, fp.z - km.z).normalized()
	var o := km + hin * 0.8 + Vector3(0, 0.02, 0)
	var d2 := (km - o).normalized()
	z._foto.pos = o
	z._foto.yaw = atan2(-d2.x, -d2.z)
	z._foto.pitch = asin(clampf(d2.y, -1.0, 1.0))
	z._foto.fov = 30.0
	z._foto.ziel_fov = 30.0
	z._rate = 40.0
	await wait(1.0)
	ziel()
	await schuss("05_gesicht", 2.5)
	z._foto_aus()
	# 6. Neue Möbel: Blick zur Schreibtischecke (Gaming-Stuhl, Poster) über den Couchtisch (Vase, Tasse).
	z.blick = "ich"
	stehen(Vector3(2.3, 0, 3.3), -1.62, -0.12)
	await wait(1.2)
	ziel()
	await schuss("06_neue_moebel", 3.0)
