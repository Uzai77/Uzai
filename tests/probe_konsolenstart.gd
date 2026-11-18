extends "res://tests/probe_base.gd"
## Probe „Start-Sequenzen je Konsole“ (system_intro.gd): ein Kontaktbogen aller Sequenzen zu einem
## Zeitpunkt (UZAI_PROBE_T, Standard 1,1 s) und Standbilder einzelner Systeme
## (UZAI_PROBE_STILLS=ps2:1.2,gc:1.5 …).

const SystemIntro := preload("res://src/ui/components/system_intro.gd")


func run() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var bogen := OS.get_environment("UZAI_PROBE_T")
	if bogen != "":
		for zeit in bogen.split(","):
			await _bogen(layer, float(zeit))
	var st := OS.get_environment("UZAI_PROBE_STILLS")
	if st != "":
		for e in st.split(","):
			var teil := e.split(":")
			await _still(layer, teil[0], float(teil[1]) if teil.size() > 1 else 1.2)
	layer.queue_free()


func _intro(layer: CanvasLayer, sys: String, zeit: float) -> Control:
	var si: Control = SystemIntro.new().setup({ "source": "rom", "system": sys })
	si.size = Vector2(1920, 1080)
	layer.add_child(si)
	si.set_process(false)
	si.call("at_time", zeit)
	return si


func _bogen(layer: CanvasLayer, zeit: float) -> void:
	var sheet := Image.create(1920, 1080, false, Image.FORMAT_RGB8)
	var i := 0
	for sys in SystemIntro.REIHE:
		var si := _intro(layer, str(sys), zeit)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(384, 216, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, 384, 216), Vector2i((i % 5) * 384, (i / 5) * 216))
		si.free()
		i += 1
	sheet.save_png(out.path_join("bogen_%04d.png" % int(zeit * 1000.0)))
	print("Bild: bogen ", zeit)


func _still(layer: CanvasLayer, sys: String, zeit: float) -> void:
	var si := _intro(layer, sys, zeit)
	await shot("start_%s_%04d" % [sys, int(zeit * 1000.0)], 0.05)
	si.free()
