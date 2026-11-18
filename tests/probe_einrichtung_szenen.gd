extends "res://tests/probe_base.gd"
## Probe „Einrichtung, Szenen“: die Vorstellung Emulatoren (Erkannt, Geladen, Belegt) und die
## Kacheln von Freunde & Medien (einrichtung_szene.gd) in der Größe der Einrichtung, je an festen
## Zeitpunkten – zum Vergleich vorher/nachher; zuletzt mit einem echten Bildschirmfoto (Aufnahmen, Live).

const Szene := preload("res://src/ui/components/einrichtung_szene.gd")
const Inhalt := preload("res://src/ui/components/einrichtung_inhalt.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	# Ein echtes Bildschirmfoto von Uzai selbst (Startseite) – für die Kacheln Aufnahmen und Live.
	await wait(0.5)
	await RenderingServer.frame_post_draw
	var foto := ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	var cl := CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	bg.size = Vector2(1920, 1080)
	cl.add_child(bg)
	for z in [["emu_1_erkannt", 2.2], ["emu_2_geladen", 4.2], ["emu_3_fertig", 5.6], ["emu_4_belegt", 8.8]]:
		await _szene(cl, "emulatoren", Rect2(110, 220, 1700, 640), float(z[1]), str(z[0]))
	await _szene(cl, "medien", Rect2(470, 230, 980, 620), 1.9, "medien_1")
	Inhalt._setzen("aufnahmen", foto)
	Inhalt._setzen("live", foto)
	await _szene(cl, "medien", Rect2(470, 230, 980, 620), 5.6, "medien_2_echt")


func _szene(cl: CanvasLayer, kind: String, r: Rect2, at: float, name: String) -> void:
	var s: Control = Szene.new().setup(kind, Vector2.ZERO)
	s.position = r.position
	s.size = r.size
	s.clip_contents = true
	cl.add_child(s)
	await wait(1.2)
	s.set_process(false)
	s.set("t", at)
	s.set("_total", at + 10.0)
	s.queue_redraw()
	await shot(name, 0.3)
	s.queue_free()
