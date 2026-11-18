extends "res://tests/probe_base.gd"
## Probe „Spiel im Fernseher“ (fernsehspiel.gd, Demo-Bild statt Helfer): Einlegen → die Kamera setzt
## sich vor den Fernseher („Startet …“); im Zimmer läuft das Spiel im Fernseher; A am Fernseher fährt
## hinein ins Vollbild (Bildfolge), das Zimmer wartet dahinter; die Guide-Taste fährt zurück an den
## Platz (Bildfolge, ohne Guide); Beamer und Röhre; Spielende. Das Spielfenster selbst gibt es unter
## Linux nicht: Ein Bild des Spiels liegt an seiner Stelle unter Uzai (wie am PC hinter dem durchsichtigen
## Fenster), und Uzai ruht hier nicht (kein Minimieren, sonst zeichnete xvfb nichts mehr).
##
## Aufruf: xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --resolution 1920x1080 -- --demo
##   --no-boot --uzai-script=res://tests/probe_fernsehspiel.gd --uzai-out=<ordner>

const U := preload("res://src/ui/u.gd")
const Spielbild := preload("res://src/room/spielbild.gd")
const Z23 := preload("res://tests/probe_zstufe23.gd")

var z: Control
var _spiel_ebene: CanvasLayer


func spielbild_bauen() -> Image:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.disable_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var s: Control = Z23._Spiel.new()
	s.size = Vector2(1280, 720)
	sv.add_child(s)
	add_child(sv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	return img


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


## Das Spielfenster: ein Bild des Spiels unter Uzai (Ebene -1), bildschirmfüllend.
func spiel_zeigen(img: Image, an: bool) -> void:
	if not an:
		if is_instance_valid(_spiel_ebene):
			_spiel_ebene.queue_free()
		return
	_spiel_ebene = CanvasLayer.new()
	_spiel_ebene.layer = -1
	var t := TextureRect.new()
	t.texture = ImageTexture.create_from_image(img)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = U.view_size()
	_spiel_ebene.add_child(t)
	get_tree().root.add_child(_spiel_ebene)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("room.grafik", "mittel")
	main.goto("games")
	await wait(1.0)
	var spiel := await spielbild_bauen()
	main.open_room(true)
	await wait(2.6)
	z = Nav.top_layer()
	z.licht_setzen("z", "abend")
	z._licht_neu(false)
	await wait(0.5)
	# --- Eingelegt: die Kamera setzt sich vor den Fernseher, das Spiel startet --------------------------
	z.set("_start_titel", "Sternenfall")
	z.set("_start_farbe", Color("#f39a6b"))
	main.set("_tv", "startet")
	z.tv_wechsel("startet")
	await wait(1.6)
	z.tv_status("Steam startet Sternenfall …")
	await shot("01_startet", 0.6)
	print("Hinweise beim Start: ", z.get_meta("uz_hints", []))
	# --- Im Zimmer: das Spiel läuft im Fernseher --------------------------------------------------------
	Launcher.in_game = true
	Spielbild.demo_bild = spiel
	Spielbild.demo_titel = "Sternenfall"
	# Wie im Programm (fernsehspiel.gd weiter): Das Fenster kam (vollbild), dann aufgestanden – „startet“ → „zimmer“ gibt es nicht.
	main.set("_tv", "vollbild")
	main.set("_tv", "zimmer")
	main.set("_overlay_mode", true)
	z.tv_wechsel("zimmer")
	await wait(2.4)
	await shot("02_im_zimmer", 0.4)
	print("Ziel-Handlung am Fernseher: ", z.call("_ziel_handlung"))
	# --- A am Fernseher: hinein ins Vollbild -------------------------------------------------------------
	Engine.time_scale = 0.35
	z.zum_spiel()
	for k in 4:
		await shot("03_hinein_%d" % k, 0.38 * 0.35 * 2.0)
	Engine.time_scale = 1.0
	await wait(1.4)
	spiel_zeigen(spiel, true)
	main.shell.visible = false
	main.background.visible = false
	await shot("04_vollbild", 0.4)
	print("Vollbild: Zustand %s, Zimmer offen %s, sichtbar %s, Modus %s, Bildrate dahinter %d" % [main.call("tv_zustand"),
		main.call("room_layer") != null, z.visible, z.modus, int(z.call("ruhe_fps"))])
	# --- Guide-Taste im Vollbild: zurück ins Zimmer, ohne Guide --------------------------------------------
	main.set("_overlay_mode", false)
	Engine.time_scale = 0.35
	main.toggle_guide("", "pad")
	main.shell.visible = false
	main.background.visible = false
	for k in 5:
		await shot("05_zurueck_%d" % k, 0.3 * 0.35 * 2.0)
	Engine.time_scale = 1.0
	await wait(1.6)
	spiel_zeigen(spiel, false)
	await shot("06_wieder_im_zimmer", 0.4)
	print("Zurück: Zustand %s, Guide offen %s, Modus %s" % [main.call("tv_zustand"), main.get("_guide") != null, z.modus])
	# --- Beamer und Röhre ----------------------------------------------------------------------------------
	for v in ["beamer", "roehre"]:
		z._variante_setzen(idx("medienwand"), v, false)
		await wait(0.6)
		await z._zum_fernseher(0.2)
		await wait(1.2)
		await shot("07_%s" % v, 0.3)
	z._variante_setzen(idx("medienwand"), "flach", false)
	await wait(0.4)
	# --- Spiel aus: aufstehen vor dem Fernseher ---------------------------------------------------------------
	Spielbild.demo_bild = null
	Launcher.in_game = false
	main.set("_tv", "")
	z.tv_wechsel("")
	await wait(1.4)
	await shot("08_aus", 0.4)
	print("Nach dem Ende: Modus %s" % str(z.modus))
