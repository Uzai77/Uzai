extends "res://tests/probe_base.gd"
## Bildfolgen vom Guide (Aufgehen, Reiterwechsel, Menü an einer Person), um die Bewegung zu
## beurteilen. Jedes Bild kostet etwas Zeit zum Speichern; die Abstände sind daher ungefähr.


func _frames(prefix: String, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("%s_%02d.png" % [prefix, i]))


func run() -> void:
	main.goto("games", "zuletzt")
	await wait(0.6)
	main.toggle_guide()
	await _frames("m1_auf", 8)
	await wait(0.8)
	Nav._fire("rb")
	await _frames("m2_rb", 8)
	await wait(0.8)
	Nav._fire("rb")
	await _frames("m3_rb", 6)
	await wait(0.8)
	Nav._fire("a")
	await _frames("m4_menue", 6)
	await wait(0.5)
	Nav._fire("b")
	await wait(0.3)
	Nav._fire("guide")
	await _frames("m5_zu", 5)
