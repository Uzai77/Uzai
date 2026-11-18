extends "res://tests/probe_base.gd"
## Leistung messen (src/core/perf.gd) und die Seite unter Einstellungen → System. Mit
## UZAI_HELPER_SHELL (PowerShell) auch Speicher und Rechenzeit. Ausgabe „LE …“.

func run() -> void:
	var p = main.perf
	for i in 6:
		await press("right")
		await wait(0.3)
	await wait(2.0)
	await p.sample()
	print("LE Start %d ms, Speicher %.0f MB (Uzai %.0f MB), Menü %s" % [p.start_ms, p.mem_mb, p.mem_uzai_mb, p.menu_stats()])
	main._rebuild()
	await wait(1.0)
	print("LE nach Neuaufbau: Ruhemodus %s, Leistung %s" % [is_instance_valid(main.rest), is_instance_valid(main.perf)])
	main.goto("settings", "system")
	await wait(1.2)
	main.sections["settings"].open_more("Leistung")
	await wait(1.0)
	await shot("01_leistung", 0.4)
