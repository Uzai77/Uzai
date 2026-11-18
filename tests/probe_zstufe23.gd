extends "res://tests/probe_base.gd"
## Probe „Dein Zimmer, Stufe 2 und 3“ (Punkt 131): Fernseher mit Spielbild (Demo-Bild statt Helfer),
## die Kamerafahrt aus dem Fernseher heraus und hinein als Bildfolge, Einschalt-Effekt (Flachbild
## und Röhre), Zimmer teilen (Vorschau, QR-Code, Datei gespeichert), Zimmer einführen (Vorschau,
## Fehlerfall, übernommen), Fotomodus mit Posen und der gespeicherte Schnappschuss, dazu Leicht.
##
## Aufruf: A2_PROJ=<projekt> A2_TIMEOUT=900 bash a2_run.sh res://tests/probe_zstufe23.gd zstufe23

const Spielbild := preload("res://src/room/spielbild.gd")
const Teilen := preload("res://src/room/zimmer_teilen.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const G := preload("res://src/room/gestalt.gd")

var z: Control


## Ein erfundenes Spielbild (Jump'n'Run mit Anzeige), nur für die Probe gezeichnet.
class _Spiel extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color("#2b3f8f"), Color("#2b3f8f"), Color("#f39a6b"), Color("#f39a6b")]))
		draw_circle(Vector2(w * 0.78, h * 0.3), 70, Color("#ffe0a3"))
		draw_circle(Vector2(w * 0.78, h * 0.3), 52, Color("#fff3d1"))
		var berge := PackedVector2Array([Vector2(0, h * 0.72), Vector2(w * 0.12, h * 0.45), Vector2(w * 0.28, h * 0.66), Vector2(w * 0.45, h * 0.38),
			Vector2(w * 0.62, h * 0.64), Vector2(w * 0.82, h * 0.42), Vector2(w, h * 0.6), Vector2(w, h), Vector2(0, h)])
		draw_colored_polygon(berge, Color("#5b3f7a"))
		var huegel := PackedVector2Array()
		for i in 33:
			huegel.append(Vector2(w * i / 32.0, h * 0.78 + sin(i * 0.7) * 18.0))
		huegel.append(Vector2(w, h))
		huegel.append(Vector2(0, h))
		draw_colored_polygon(huegel, Color("#3d8a5a"))
		for i in 21:
			draw_rect(Rect2(i * 64, h - 72, 62, 70), Color("#7a4a2a"))
			draw_rect(Rect2(i * 64, h - 72, 62, 14), Color("#5fcf6e"))
		for p in [Vector2(380, 430), Vector2(700, 360)]:
			draw_rect(Rect2(p, Vector2(190, 30)), Color("#c9773a"))
			draw_rect(Rect2(p, Vector2(190, 8)), Color("#ffd36e"))
		for c in [Vector2(430, 390), Vector2(480, 390), Vector2(530, 390), Vector2(750, 320), Vector2(800, 320)]:
			draw_circle(c, 13, Color("#ffd43b"))
			draw_circle(c, 7, Color("#fff1a8"))
		var held := Vector2(250, h - 150)
		draw_rect(Rect2(held, Vector2(56, 78)), Color("#e8505b"))
		draw_rect(Rect2(held + Vector2(6, -40), Vector2(44, 44)), Color("#ffd1b0"))
		draw_circle(held + Vector2(20, -20), 5, Color.BLACK)
		draw_circle(held + Vector2(38, -20), 5, Color.BLACK)
		draw_rect(Rect2(held + Vector2(0, -48), Vector2(56, 14)), Color("#2f6fd6"))
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(40, 64), "SCORE 004250", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
		draw_string(f, Vector2(w - 260, 64), "WELT 3-2", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
		for i in 3:
			draw_circle(Vector2(52 + i * 40, 100), 13, Color("#ff5d73"))


func spielbild_bauen() -> Image:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.disable_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var s := _Spiel.new()
	s.size = Vector2(1280, 720)
	sv.add_child(s)
	add_child(sv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	img.resize(512, 288, Image.INTERPOLATE_LANCZOS)
	return img


## Kamera sofort an ihr Ziel (Software-Grafik ist langsam).
func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func vor_den_fernseher(abstand := 2.6, seitlich := 0.0) -> void:
	var tv := idx("medienwand")
	var n: Node3D = z.welt.knoten[tv]
	var vorn := n.global_transform.basis.z.normalized()
	var re := vorn.cross(Vector3.UP)
	var p: Vector3 = n.global_transform.origin + vorn * abstand + re * seitlich
	z.pos = Vector3(p.x, 0, p.z)
	var ziel_p: Vector3 = n.global_transform * Vector3(0, 1.0, 0)
	var d: Vector3 = ziel_p - Vector3(p.x, 1.62, p.z)
	z.yaw = atan2(-d.x, -d.z)
	z._yaw_soll = z.yaw
	z.pitch = asin(d.normalized().y)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("room.grafik", "mittel")
	main.goto("games")
	await wait(1.0)
	var spiel := await spielbild_bauen()
	spiel.save_png(out.path_join("00_demo_spielbild.png"))
	Spielbild.demo_bild = spiel
	Spielbild.demo_titel = "Sternenfall"
	# --- Stufe 2: aus dem Fernseher heraus (wie über Guide › Dein Zimmer im Spiel) ---------------------
	Engine.time_scale = 0.3
	main.open_room(true)
	await get_tree().process_frame
	await get_tree().process_frame
	z = Nav.top_layer()
	for k in 14:
		await shot("01_raus_%02d" % k, 0.09)
	await wait(1.0)
	Engine.time_scale = 1.0
	z.licht_setzen("z", "abend")
	z._licht_neu(false)
	vor_den_fernseher(2.4, 0.5)
	await wait(1.2)
	ziel()
	await shot("02_fernseher_spiel_abend", 1.5)
	vor_den_fernseher(1.25, 0.0)
	await wait(0.6)
	ziel()
	await shot("03_fernseher_spiel_nah", 1.2)
	# Vom Sofa aus (sitzen): so sieht man das Spiel im Zimmer.
	var sofa := idx("sofa")
	if sofa >= 0:
		z._hinsetzen(sofa)
		await wait(0.8)
		ziel()
		await shot("04_vom_sofa", 1.2)
		z._aufstehen()
	# --- Hinein: die Kamera fährt in den Fernseher, das Spiel füllt das Bild ----------------------------
	vor_den_fernseher(2.6, 0.9)
	await wait(0.6)
	ziel()
	await wait(0.4)
	Engine.time_scale = 0.3
	z.zum_spiel()
	for k in 16:
		await shot("05_rein_%02d" % k, 0.08)
	Engine.time_scale = 1.0
	await wait(1.5)
	# --- Ohne Spiel: „Zuletzt gespielt“, Einschalt-Effekt (Flachbild, dann Röhre) -----------------------
	Spielbild.demo_bild = null
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	z.licht_setzen("z", "tag")
	z._licht_neu(false)
	vor_den_fernseher(1.9, 0.0)
	await wait(0.8)
	ziel()
	await shot("06_zuletzt_gespielt", 1.0)
	Engine.time_scale = 0.06
	z.welt.tv_zeigen("Startet …", "Sternenfall", Color("#f39a6b"))
	z.welt.tv_einschalten(0.7)
	for k in 6:
		await shot("07_einschalten_flach_%d" % k, 0.012)
	Engine.time_scale = 1.0
	z._variante_setzen(idx("medienwand"), "roehre", false)
	await wait(0.6)
	vor_den_fernseher(1.5, 0.0)
	ziel()
	await wait(0.6)
	Engine.time_scale = 0.06
	z.welt.tv_einschalten(0.7)
	for k in 7:
		await shot("08_einschalten_roehre_%d" % k, 0.012)
	Engine.time_scale = 1.0
	z._variante_setzen(idx("medienwand"), "flach", false)
	await wait(0.5)
	# --- Stufe 3: Zimmer teilen (Menü › Teilen) -------------------------------------------------------------
	z._zimmer_menue()
	await wait(1.2)
	await press("down", 22, 0.1)
	await wait(0.8)
	await shot("09_menue_teilen", 0.6)
	await press("b")
	await wait(1.0)
	z.licht_setzen("z", "abend")
	z._licht_neu(false)
	z.teilen()
	await wait(4.0)
	await shot("10_teilen_qr", 1.5)
	await press("a")
	await wait(1.2)
	await shot("11_teilen_gespeichert", 0.6)
	var ex := Teilen.export_ordner()
	var dateien := DirAccess.get_files_at(str(ex[1]))
	print("Geteilte Dateien: ", dateien)
	await press("b")
	await wait(1.0)
	# Die Vorschau aus der Datei (zum Ansehen).
	if dateien.size() > 0:
		var gel := Teilen.lesen_datei(str(ex[1]).path_join(dateien[0]))
		print("Datei gelesen: ", gel.ok, " Möbel: ", (gel.get("raum", {}).get("moebel", []) as Array).size())
		var vb: PackedByteArray = gel.get("vorschau", PackedByteArray())
		if not vb.is_empty():
			var vi := Image.new()
			vi.load_jpg_from_buffer(vb)
			vi.save_png(out.path_join("12_vorschau_in_datei.png"))
	# --- Einführen: ein fremdes Neon-Zimmer mit eigenem Möbel ---------------------------------------------
	var fremd := Daten.standard()
	var r: Dictionary = Vorlagen.raum("retro", "x", "Jemandes Zimmer")
	fremd.raeume = [r]
	fremd.aktuell = "x"
	fremd.eigene = [{ "id": "e_neonbank", "name": "Neon-Bank", "ebene": "boden", "w": 3, "d": 2, "teile": [
		{ "a": "kasten", "x": 0, "y": 0, "z": 0, "b": 140, "h": 42, "t": 60, "r": 0, "f": "#2b2c30" },
		{ "a": "kissen", "x": 0, "y": 42, "z": 0, "b": 130, "h": 12, "t": 52, "r": 0, "f": "#ff4fa3" },
		{ "a": "leuchte", "x": 60, "y": 60, "z": -20, "b": 14, "h": 14, "t": 14, "r": 0, "f": "#7a5cff" }] }]
	(r.moebel as Array).append({ "t": "e_neonbank", "x": 9, "z": 7, "r": 2 })
	fremd.figur.person = "ella"
	fremd.figur.haar = "rosa"
	fremd.tier.art = "fuchs"
	var paket := Teilen.paket(Teilen.auszug(Daten.pruefe(fremd), Daten.pruefe(fremd).raeume[0]))
	katalog_zurueck()
	z.einfuehren_zeigen(Teilen.lesen_bytes(paket))
	await wait(4.0)
	await shot("13_einfuehren_vorschau", 1.5)
	await press("b")
	await wait(0.8)
	z.einfuehren_zeigen(Teilen.lesen_bytes("das ist kein zimmer".to_utf8_buffer()))
	await wait(1.5)
	await shot("14_einfuehren_fehler", 0.6)
	await press("b")
	await wait(0.8)
	# Als Vorlage aufheben (unter Menü › Vorlagen › Deine Vorlagen).
	var gel_f := Teilen.lesen_bytes(paket)
	z.vorlage_speichern(Teilen.vorbereiten(gel_f, z.daten.get("eigene", []), z.bewohner.erreichte), "Neon von Mira")
	z._anpassen_auf(z._seiten.seite_vorlagen(), -1)
	await wait(1.5)
	await shot("14b_eigene_vorlage", 0.6)
	await press("b")
	await wait(1.0)
	z.einfuehren_zeigen(Teilen.lesen_bytes(paket))
	await wait(3.0)
	await press("a")
	await wait(3.0)
	z.blick = "oben"
	z.pos = Vector3(3.0, 0, 3.0)
	await wait(1.0)
	ziel()
	await shot("15_uebernommen_von_oben", 1.5)
	z.blick = "ich"
	# --- Fotomodus und Schnappschuss -------------------------------------------------------------------
	vor_den_fernseher(2.2, -1.0)
	z.yaw += PI
	z._yaw_soll = z.yaw
	await wait(0.5)
	z.fotomodus()
	await wait(1.0)
	z._foto_pose(1)
	await wait(1.2)
	ziel()
	await shot("16_fotomodus_winken", 1.0)
	z._foto_pose(1)
	z._foto_pose(1)
	z._foto_pose(1)
	z._foto.ziel_fov = 38.0
	z._foto.fov = 38.0
	await wait(1.0)
	ziel()
	await shot("17_fotomodus_tanzen_zoom", 1.0)
	var vorher := DirAccess.get_files_at(str(Teilen.foto_ordner()[1])) if DirAccess.dir_exists_absolute(str(Teilen.foto_ordner()[1])) else PackedStringArray()
	await press("a")
	await shot("18_schnappschuss_blitz", 0.05)
	await wait(2.0)
	await shot("19_schnappschuss_meldung", 0.3)
	var neu := DirAccess.get_files_at(str(Teilen.foto_ordner()[1]))
	for f in neu:
		if not (f in vorher) and f.ends_with(".png"):
			print("Schnappschuss: ", f)
			DirAccess.copy_absolute(str(Teilen.foto_ordner()[1]).path_join(f), out.path_join("20_schnappschuss_datei.png"))
	await press("b")
	await wait(1.0)
	# --- Leicht: Fernseher mit Spielbild in der leichten Stufe ------------------------------------------------
	Spielbild.demo_bild = spiel
	z.grafik_setzen("leicht")
	await wait(2.5)
	vor_den_fernseher(2.0, 0.3)
	await wait(0.8)
	ziel()
	await shot("21_leicht_fernseher_spiel", 2.5)
	z.fotomodus()
	z._foto_pose(2)
	await wait(1.5)
	ziel()
	await shot("22_leicht_fotomodus", 1.0)
	await press("b")
	z.grafik_setzen("mittel")
	Spielbild.demo_bild = null
	# Nach einem Wechsel der Grafikstufe ein paar Sekunden warten (Software-Grafik beim Beenden).
	await wait(6.0)


## Die eigenen Möbel des Zimmers wieder im Katalog (Daten.pruefe oben meldet die fremden an).
func katalog_zurueck() -> void:
	preload("res://src/room/katalog.gd").eigene_setzen(z.daten.get("eigene", []))
