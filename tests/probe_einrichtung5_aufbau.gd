extends "res://tests/probe_base.gd"
## Auflösen der Einrichtung in die Startseite (setup_wizard.gd _ausklang, startseite_aufbau.gd): eine
## Bildfolge nach „Los“ – einmal bei der ersten Einrichtung, einmal neu eingerichtet aus den
## Einstellungen (dort geht es erst unter der Bühne auf die Startseite).

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const Aufbau := preload("res://src/ui/sections/startseite_aufbau.gd")
const ZEITEN := [0.1, 0.35, 0.6, 0.85, 1.1, 1.4, 1.7, 2.1, 2.6, 3.4]


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	await _folge("erst", false)
	main.open_setting("system", "")
	await wait(1.2)
	await _folge("neu", true)


func _folge(name: String, aus_einstellungen: bool) -> void:
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.restart", aus_einstellungen)
	Config.set_value("einrichtung.tour", true)
	Config.set_value("einrichtung.mehr", true)
	Config.set_value("einrichtung.step", "fertig")
	Wizard.open_for(main, false)
	await wait(2.6)
	await shot("%s_00_bereit" % name, 0.1)
	var t0 := Time.get_ticks_msec()
	Nav._fire("a")
	for i in ZEITEN.size():
		while (Time.get_ticks_msec() - t0) / 1000.0 < float(ZEITEN[i]):
			await get_tree().process_frame
		var ab := -1.0
		for c in main.get_children():
			if c.get_script() == Aufbau:
				ab = float(c.get("_t"))
		await shot("%s_%02d_%.2f" % [name, i + 1, (Time.get_ticks_msec() - t0) / 1000.0], 0.0)
		print("E5 %s %.2f s nach Los, Aufbau bei %.2f s, Bilder/s %d" % [name, (Time.get_ticks_msec() - t0) / 1000.0, ab, Engine.get_frames_per_second()])
	print("E5 Aufbau ", name, " fertig, Ebene oben: ", Nav.top_layer())
	await wait(1.0)
