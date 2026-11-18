extends "res://tests/probe_base.gd"
## Einrichtung 7: Konten mittig und ausgewogen (Lage der Teile wird ausgegeben), Emulatoren ohne
## Retro-Spiele. Umgebung UZAI_E7_BILDER=1: Bildschirmfotos.
## Aufruf: xvfb-run … -- --demo --no-boot --uzai-script=res://tests/probe_einrichtung7.gd --uzai-out=<ordner>

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func run() -> void:
	var bilder := OS.get_environment("UZAI_E7_BILDER") == "1"
	var tag := "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	Config.set_value("controller.glyphs", "xbox")
	for st in ["konten", "emulatoren"]:
		Wizard.probe_ohne_retro = st == "emulatoren"
		Config.set_value("einrichtung.done", false)
		Config.set_value("einrichtung.restart", false)
		Config.set_value("einrichtung.mehr", false)
		Config.set_value("einrichtung.step", st)
		var w: Control = Wizard.open_for(main, false)
		await wait(2.4 if st == "emulatoren" else 1.6)
		if st == "konten":
			var gross: Array = []
			var klein: Array = []
			for c in Nav.focusables(Nav.scope_root()):
				if c.get("gross") == true:
					gross.append(c.get_global_rect())
				elif c.get("titel") != null and str(c.get("titel")) != "":
					klein.append(c.get_global_rect())
				if str(c.get("titel")) == "Spotify":
					Nav.focus(c, true)
			await wait(0.4)
			var mitte := get_viewport().get_visible_rect().size.x * 0.5
			var g_l: float = gross.map(func(r: Rect2) -> float: return r.position.x).min()
			var g_r: float = gross.map(func(r: Rect2) -> float: return r.end.x).max()
			var k_l: float = klein.map(func(r: Rect2) -> float: return r.position.x).min()
			var k_r: float = klein.map(func(r: Rect2) -> float: return r.end.x).max()
			var spalten := {}
			for r: Rect2 in klein:
				var x := snappedf(r.position.x, 1.0)
				spalten[x] = maxf(float(spalten.get(x, 0.0)), r.end.y)
			var go: Control = w.get("_default")
			var hint: Control = w.get("_aside_d")
			print("E7 %s Mitte %.0f | Kacheln %.0f–%.0f (Mitte %.0f, Breiten %s) | Spalten %.0f–%.0f (Mitte %.0f, Breiten %s, Enden %s) | Zeile Mitte %.0f | Weiter Mitte %.0f" % [
				tag, mitte, g_l, g_r, (g_l + g_r) * 0.5, str(gross.map(func(r: Rect2) -> int: return int(r.size.x))),
				k_l, k_r, (k_l + k_r) * 0.5, str(klein.map(func(r: Rect2) -> int: return int(r.size.x)).slice(0, 2)), str(spalten.values()),
				hint.get_global_rect().get_center().x, go.get_global_rect().get_center().x])
		if bilder:
			await shot("einrichtung7_%s_%s" % [st, tag], 0.2)
		w.set("_finished", true)
		w.call("close")
		await wait(1.0)
	Wizard.probe_ohne_retro = false
