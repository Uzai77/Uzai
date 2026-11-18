extends "res://tests/probe_base.gd"
## Startanimation und Vorstellung in der Einrichtung: Start (das U zeichnet sich, Staub im Licht),
## Willkommen, Konten mit der Szene Freunde & Medien, Fertig mit Feier.

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func run() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var boot = load("res://src/ui/boot.gd").new()
	boot.preview = true
	boot.setup("voll")
	layer.add_child(boot)
	await wait(0.3)
	boot.set_process(false)
	boot._t = 0.9
	boot.queue_redraw()
	await shot("1_start", 0.15)
	layer.queue_free()
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.restart", false)
	Config.set_value("einrichtung.tour", true)
	Config.set_value("einrichtung.mehr", false)
	Config.set_value("einrichtung.step", "willkommen")
	Wizard.open_for(main, false)
	await wait(1.0)
	var w: Node = Nav.top_layer()
	for id in ["konten", "fertig"]:
		w.call("_show_step", (w.get("_steps") as Array).find(id), 1)
		await shot("3_" + id, 3.1 if id != "fertig" else 0.9)
