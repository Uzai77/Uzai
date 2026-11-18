extends "res://tests/probe_base.gd"
## Probe „Tür zum Zimmer“ (src/ui/components/zimmer_tuer.gd): der Bereich Zimmer (die ganze Fläche eine
## Tür, gewählt), dann A – Bilder, wenn die Hand drückt, die Tür halb offen ist (dahinter das echte
## Zimmer), die Kamera hindurchgeht, und wenn das Zimmer steht. Im Protokoll, wie lang das längste Bild
## der Fahrt dauerte (nach dem Warten auf ruhige Bilder).
##
## Aufruf: xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --resolution 1920x1080 -- --demo
##   --no-boot --uzai-script=res://tests/probe_zimmertuer.gd --uzai-out=<ordner>


func run() -> void:
	main.goto("room")
	await wait(1.6)
	var tuer: Control = null
	for n in main.find_children("*", "Control", true, false):
		if str((n as Control).get_meta("uz_key", "")) == "room:betreten" and n.has_method("activate"):
			tuer = n
	if tuer == null:
		print("TUER: nicht gefunden")
		return
	Nav.focus(tuer, true)
	await wait(1.2)
	await shot("01_tuer", 0.2)
	tuer.call("activate")
	# Erst wenn die Hand kommt, läuft die Fahrt (davor: Aufbau unter dem stillen Bild).
	var ebene: CanvasLayer = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		ebene = tuer.get("_ebene")
		if ebene and float((ebene.get_child(0).material as ShaderMaterial).get_shader_parameter("hand")) > 0.0:
			break
	if ebene == null:
		print("TUER: keine Fahrt")
		return
	print("TUER: Fahrt beginnt nach %d ms" % (Time.get_ticks_msec() - t0))
	var mat := ebene.get_child(0).material as ShaderMaterial
	var bilder := { "02_hand": [0.4, "druck"], "03_halb_auf": [0.5, "auf"], "04_hindurch": [1.6, "zoom"] }
	var laengstes := 0
	var vorher := Time.get_ticks_msec()
	for name: String in bilder:
		var grenze: float = float(bilder[name][0])
		var p: String = bilder[name][1]
		while is_instance_valid(ebene) and float(mat.get_shader_parameter(p)) < grenze:
			await RenderingServer.frame_post_draw
			laengstes = maxi(laengstes, Time.get_ticks_msec() - vorher)
			vorher = Time.get_ticks_msec()
		if is_instance_valid(ebene):
			await shot(name, 0.0)
			vorher = Time.get_ticks_msec()
	print("TUER: längstes Bild der Fahrt %d ms" % laengstes)
	await wait(2.5)
	await shot("05_zimmer", 0.4)
	print("TUER: Zimmer offen: %s, Modus %s" % [str(main.call("room_layer") != null), str(main.call("room_layer").get("modus"))])
