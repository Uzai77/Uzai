extends "res://tests/probe_base.gd"
## Probe „Neue Möbel und Zimmer-Fehler“: zwei Räume mit den Möbeln aus moebel_mehr.gd (Wohnen;
## Spielen und Licht am Abend), dann im Standardzimmer: Y auf der Tasse zeigt „Couchtisch wählen“,
## eine neue Raumgröße von oben und danach der Blick auf die Wände (gebacken, nicht schwarz), und der
## Jackenständer mit der Leiste im Zimmer.
##
## Aufruf: xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --resolution 1920x1080 -- --demo
##   --no-boot --uzai-script=res://tests/probe_zimmermoebel.gd --uzai-out=<ordner>

const Katalog := preload("res://src/room/katalog.gd")

var z: Control


func m(t: String, x: int, zz: int, r := 0, s := -1, v := "") -> Dictionary:
	var it := { "t": t, "x": x, "z": zz, "r": r, "v": v if v != "" else Katalog.std_variante(t), "an": true }
	if s >= 0:
		it["s"] = s
	return it


## Bis das Licht der Hülle gebacken ist (höchstens sek Sekunden).
func gebacken(sek := 90.0) -> void:
	var b: Variant = z.welt.get("backen")
	if b == null:
		await wait(2.0)
		return
	var vorher := int(b.get("gebacken"))
	var t0 := Time.get_ticks_msec()
	while int(b.get("gebacken")) <= vorher and Time.get_ticks_msec() - t0 < sek * 1000.0:
		await wait(0.5)
	await wait(1.0)


func kamera(o: Vector3, ziel: Vector3, fov := 62.0) -> void:
	z.modus = "fahrt"
	z.welt.kamera.global_transform = Transform3D(Basis(), o).looking_at(ziel, Vector3.UP)
	z.welt.kamera.fov = fov
	z.welt.raster.visible = false
	z.welt.schnitt(o, false)


func raum_mit(moebel: Array) -> void:
	z.raum.w = 14
	z.raum.d = 10
	z.raum.moebel = moebel
	z._welt_neu()
	await wait(0.5)


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.0)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	print("Zimmer offen: ", z != null and z.has_method("moebel_setzen"))
	var alt: Dictionary = (z.raum as Dictionary).duplicate(true)
	# 1) Wohnen.
	await raum_mit([m("sideboard", 1, 0, 0, 1), m("kraeuter", 2, 0), m("bilderwand", 1, 0), m("arcade", 6, 0), m("leiterregal", 9, 0),
		m("bett", 11, 0, 0, 1), m("fell", 11, 6, 1), m("laeufer", 3, 5, 1, 1), m("couchtisch_rund", 4, 5), m("ohrensessel", 1, 5, 1),
		m("pouf", 7, 5), m("satztisch", 3, 4), m("haengepflanze", 9, 3), m("deckenlampe", 6, 5)])
	z.stimmung_anwenden("tag")
	kamera(Vector3(3.9, 2.25, 4.85), Vector3(3.9, 0.75, 0.6), 66.0)
	await gebacken()
	await shot("zimmer6_moebel_wohnen", 0.5)
	# 2) Spielen und Licht.
	await raum_mit([m("vorhang", 1, 0, 0, 1), m("schlafsofa", 1, 1), m("fell", 2, 4, 1), m("bogenlampe", 5, 1, 3), m("deckenfluter", 0, 0),
		m("girlande", 7, 0, 0, 1), m("gamingtisch", 8, 0), m("rechner", 8, 0), m("monitor", 9, 0), m("kraeuter", 10, 1), m("gamingstuhl", 8, 2, 2),
		m("lichtervorhang", 11, 0, 0, 1, "bunt"), m("bogenhanf", 12, 1, 0, 2), m("papierlampe", 13, 1), m("wandregal", 13, 4, 3, 1),
		m("wanduhr_strahlen", 13, 2, 3), m("haengepflanze", 6, 3, 0, -1, "terrakotta"), m("pouf", 6, 5)])
	z.stimmung_anwenden("gemuetlich")
	kamera(Vector3(5.6, 2.2, 4.85), Vector3(4.4, 0.95, 0.4), 72.0)
	await gebacken()
	await shot("zimmer6_moebel_licht", 0.5)
	# 3) Fehler: Standardzimmer, Y auf der Tasse im Einrichten.
	z.raum.w = int(alt.w)
	z.raum.d = int(alt.d)
	z.raum.moebel = alt.moebel
	z._welt_neu()
	z.stimmung_anwenden("gemuetlich")
	z.modus = "laufen"
	z.bauen_an()
	var tasse := idx("tasse")
	if tasse >= 0:
		z.cursor_setzen(Vector2i(int(z.raum.moebel[tasse].x), int(z.raum.moebel[tasse].z)), false)
		await press("y")
	await wait(2.5)
	await shot("zimmer6_fehler_auswahl", 0.5)
	await press("b")
	# Raumgröße von oben ändern, dann zurück in die Ich-Ansicht: alle Wände gebacken, keine schwarz.
	z.groesse_setzen(int(z.raum.w) + 2, int(z.raum.d))
	await gebacken()
	await press("b")
	await wait(0.5)
	var w := float(z.raum.w) * 0.5
	z.blick = "ich"
	z.pos = Vector3(1.4, 0, float(z.raum.d) * 0.5 - 0.8)
	var dir := Vector3(w, 1.2, 0.0) - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = 0.12
	await gebacken(40.0)
	await shot("zimmer6_fehler_waende", 1.0)
	# Jackenständer: die Figur gleich im Zimmer wechseln.
	z._figur_wechseln()
	await wait(1.4)
	await press("right", 2, 0.4)
	await wait(1.2)
	await shot("zimmer6_garderobe", 0.4)
	await press("b")
