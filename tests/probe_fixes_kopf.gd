extends "res://tests/probe_base.gd"
## Probe Spielseite mit „Weiter, wo du warst“ bei Oberfläche 100 %, 125 % und 150 %: Die Hülle
## rechts bleibt ganz im Bild. Gibt „FK ok/FAIL …“ aus.

const QR := preload("res://src/core/quick_resume.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var g: Dictionary = Library.by_system("ps2")[0]
	var gid := str(g.id)
	var now := int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(Config.path(QR.DIR))
	var f := Config.path(QR.DIR).path_join("probe_k.p2s")
	var fa := FileAccess.open(f, FileAccess.WRITE)
	fa.store_string("stand")
	fa.close()
	QR.add(gid, { "emulator": "pcsx2", "at": now - 3600, "file": f, "slot_file": "C:/PCSX2/sstates/x.p2s", "title": str(g.title) }, "auto")
	for sc in [1.0, 1.25, 1.5]:
		Config.set_value("theme.ui_scale", sc)
		await wait(0.8)
		main.open_game(g)
		await wait(1.8)
		var page: Node = Nav.top_layer()
		var cov: Control = page.call("flug_ziel") if page and page.has_method("flug_ziel") else null
		var vw := get_viewport().get_visible_rect().size.x
		var r := cov.get_global_rect() if cov else Rect2()
		print("FK %s Oberfläche %d %%: Hülle %d..%d von %d" % ["ok  " if cov and r.end.x <= vw + 1.0 and r.position.x > 0.0 else "FAIL", int(sc * 100), int(r.position.x), int(r.end.x), int(vw)])
		if sc != 1.25:
			await shot("kopf_%d" % int(sc * 100), 0.3)
		while Nav.top_layer():
			Nav.top_layer().close()
			await wait(0.3)
	Config.set_value("theme.ui_scale", 1.0)
