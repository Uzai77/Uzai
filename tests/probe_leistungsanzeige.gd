extends "res://tests/probe_base.gd"
## Probe „Leistungsanzeige“ (Demo, Roadmap 5): Leiste „Leistung“ im Guide (Reiter Spiel), die
## Seitenleiste mit laufenden Werten, Energieprofil umschalten, Kachel „Leistung“ selbst gewählt,
## die Ecke über dem Spiel (eigenes Fenster) und das Zurückstellen nach dem Spiel.


func _focus_key(key: String) -> bool:
	var top := Nav.top_layer()
	if not top:
		return false
	for c in Nav.focusables(top):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return true
	return false


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.4)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	Launcher.in_game = true
	Launcher.current = g
	main.toggle_guide()
	await wait(1.6)
	await shot("01_guide_leiste", 0.4)
	print("Leiste gefunden: %s" % str(_focus_key("g:perf")))
	await shot("02_leiste_gewaehlt", 1.4)
	await press("a")
	await shot("03_seitenleiste", 1.6)
	await shot("04_seitenleiste_spaeter", 2.2)
	print("Profil Höchstleistung wählbar: %s" % str(_focus_key("perf:plan:8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")))
	await press("a")
	await shot("05_hoechstleistung", 1.0)
	print("Zurückstellen gemerkt: %s" % str(Config.get_value("system.power_restore", "")))
	_focus_key("perf:corner")
	await press("a")
	await wait(0.4)
	print("Ecke an: %s" % str(Config.get_value("system.perf_corner", false)))
	await _close_all()
	Config.set_value("system.guide_tiles", ["perf", "", "", ""])
	main.toggle_guide()
	await wait(1.4)
	print("Kachel gefunden: %s" % str(_focus_key("q:Leistung")))
	await shot("06_kachel", 0.6)
	await _close_all()
	await wait(1.5)
	var corner: Window = main.perf.get("_corner")
	print("Ecke sichtbar: %s" % str(is_instance_valid(corner) and corner.visible))
	if is_instance_valid(corner):
		await RenderingServer.frame_post_draw
		corner.get_texture().get_image().save_png(out.path_join("07_ecke.png"))
	main.toggle_guide()
	await wait(0.8)
	print("Ecke im Guide versteckt: %s" % str(not (is_instance_valid(corner) and corner.visible)))
	await _close_all()
	Launcher.in_game = false
	Launcher.ended.emit(g, 60)
	await wait(1.0)
	print(
			"Nach dem Spiel: zurückgestellt %s, Ecke weg %s" % [str(Config.get_value("system.power_restore", "")) == "",
			str(not is_instance_valid(main.perf.get("_corner")))])
	await shot("08_nach_spiel", 0.8)
