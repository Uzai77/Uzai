extends "res://tests/probe_base.gd"
## Wächter nach einem Absturz (Punkt 133), mit PowerShell als Helfer (UZAI_HELPER_SHELL) und
## eigenem X-Server: Uzai geht in die Einstellungen und stirbt hart; der Helfer startet es mit
## --nach-absturz neu, das neue Uzai schreibt neu.txt (Bereich, letzter Lauf) und macht ein Bild.

func run() -> void:
	if Helper.AFTER_CRASH in OS.get_cmdline_user_args():
		await wait(2.0)
		var f := FileAccess.open(out.path_join("neu.txt"), FileAccess.WRITE)
		f.store_string("Bereich %s, letzter Lauf %s" % [main.current, Config.last_crash])
		f.close()
		await shot("02_neu", 0.3)
		return
	while not Helper.available:
		await wait(0.2)
	# Godot nimmt --path aus den Argumenten (die exportierte Uzai.exe braucht es nicht): hier selbst.
	var engine := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "1920x1080"])
	var r: Dictionary = await Helper.run("crash-watch", Helper.crash_job(OS.get_executable_path(), engine, OS.get_cmdline_user_args(),
		OS.get_process_id(), Config.path("laeuft.json"), Helper.ps_exe(), Helper._script, ""))
	print("WA scharf: ", r.ok)
	# Wie nach 90 s: gelungener Start.
	Config._run.stable = true
	Config._touch_run()
	main.goto("settings", "system")
	await wait(1.5)
	await shot("01_vorher", 0.2)
	print("WA Markierung: ", FileAccess.get_file_as_string(Config.path("laeuft.json")), " Helfer ", Helper.pids())
	OS.kill(OS.get_process_id())
