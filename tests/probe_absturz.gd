extends "res://tests/probe_base.gd"
## Absturzschutz von außen (ohne --demo, fester Datenordner): --absturz=kill beendet Uzai hart wie
## ein Absturz, --absturz=look zeigt danach Hinweis, Fehlerbericht und Einstellungen, --absturz=safe
## den Sicheren Modus (nach zwei Enden beim Starten). Ausgabe „AB …“.

func run() -> void:
	var step := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--absturz="):
			step = a.substr(10)
	var marker := Config.data_dir.path_join("laeuft.json")
	print("AB Markierung da: ", FileAccess.file_exists(marker), " letzter Lauf: ", Config.last_crash, " sicher: ", Config.safe_mode)
	if step == "kill":
		main.goto("settings", "system")
		await wait(0.6)
		OS.kill(OS.get_process_id())
		return
	await shot("01_hinweis", 0.6)
	if step == "safe":
		while Nav.top_layer():
			Nav.top_layer().close()
			await wait(0.5)
		main.goto("settings", "system")
		await wait(1.2)
		await shot("04_sicher", 0.3)
		print("AB Plugins: ", Config.get_value("movies.plugins_on", true), " Start: ", Config.get_value("theme.boot", ""))
		return
	var top = Nav.top_layer()
	print("AB oben: ", top.get("heading") if top else "nichts")
	main.open_crash_report()
	await wait(1.2)
	await shot("02_bericht", 0.3)
	Nav.top_layer().close()
	await wait(0.6)
	if Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.6)
	main.goto("settings", "system")
	await wait(1.2)
	await shot("03_system", 0.3)
	print("AB Bericht-Datei: ", FileAccess.file_exists(Config.path("logs/fehlerbericht.txt")))
