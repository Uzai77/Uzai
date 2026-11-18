extends "res://tests/probe_base.gd"
## Einrichtung 6: Konten (Steam und Discord groß, der Rest nach Bereichen), Emulatoren (echter Stand)
## und der Übergang in die Startseite (Bildfolge nach „Los“).
## Aufruf: xvfb-run … -- --demo --no-boot --uzai-script=res://tests/probe_einrichtung6.gd --uzai-out=<ordner>

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const ZEITEN := [0.15, 0.35, 0.55, 0.8, 1.1, 1.5, 2.2, 3.2]


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("einrichtung.tour", true)
	for st in ["konten", "emulatoren"]:
		Config.set_value("einrichtung.done", false)
		Config.set_value("einrichtung.restart", false)
		Config.set_value("einrichtung.mehr", false)
		Config.set_value("einrichtung.step", st)
		var w: Control = Wizard.open_for(main, false)
		await wait(4.6 if st == "emulatoren" else 1.6)
		if st == "konten":
			for c in Nav.focusables(Nav.scope_root()):
				if str(c.get("titel")) == "Spotify":
					Nav.focus(c, true)
			await wait(0.4)
		await shot("e6_" + st, 0.2)
		w.set("_finished", true)
		w.call("close")
		await wait(1.0)
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.step", "fertig")
	Wizard.open_for(main, false)
	await wait(2.6)
	var t0 := Time.get_ticks_msec()
	Nav._fire("a")
	for i in ZEITEN.size():
		while (Time.get_ticks_msec() - t0) / 1000.0 < float(ZEITEN[i]):
			await get_tree().process_frame
		await shot("e6_los_%02d_%.2f" % [i, (Time.get_ticks_msec() - t0) / 1000.0], 0.0)
	print("E6 fertig, Ebene oben: ", Nav.top_layer())
