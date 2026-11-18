extends "res://tests/probe_base.gd"
## Einrichtung, Anfang und Vorstellung: Willkommen (das Zeichen wie im Intro), Die Guide-Taste (oben
## das U), Dein Zimmer (echtes 3D-Zimmer, drei Figuren spielen), Schauen & Hören (je Station ein Bild).
## UZAI_E5_NUR="zimmer,medien" beschränkt auf einzelne Schritte.

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const Szene := preload("res://src/ui/components/einrichtung_szene.gd")
const Zimmerszene := preload("res://src/ui/components/einrichtung_zimmer.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var nur := OS.get_environment("UZAI_E5_NUR")
	var vor := OS.get_environment("UZAI_E5_VOR")
	for st in [["willkommen", 3.4], ["guide", 3.0], ["zimmer", 4.5], ["medien", 2.0]]:
		if nur != "" and not nur.contains(str(st[0])):
			continue
		Config.set_value("einrichtung.done", false)
		Config.set_value("einrichtung.restart", false)
		Config.set_value("einrichtung.mehr", false)
		Config.set_value("einrichtung.step", str(st[0]))
		var w: Control = Wizard.open_for(main, false)
		await wait(float(st[1]))
		if str(st[0]) == "medien":
			var sz: Control = _finde(w, Szene)
			if sz:
				sz.set_process(false)
				for k in 4:
					sz.set("t", 1.4 + k * 2.5)
					sz.queue_redraw()
					await shot(vor + "medien_%d" % k, 0.3)
		else:
			await shot(vor + str(st[0]), 0.2)
		if str(st[0]) == "zimmer":
			var z: Control = _finde(w, Zimmerszene)
			if z:
				var welt: Node = z.get("_welt")
				print("E5 Möbel: ", (welt.get("raum").moebel as Array).size(), " von ", (Zimmerszene.retro_raum().moebel as Array).size(),
						" · Figuren: ", (z.get("_figuren") as Array).size())
		w.set("_finished", true)
		w.call("close")
		await wait(1.0)


func _finde(n: Node, sc: Script) -> Control:
	if n.get_script() == sc:
		return n as Control
	for c in n.get_children():
		var f := _finde(c, sc)
		if f:
			return f
	return null
