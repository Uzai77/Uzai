extends "res://tests/probe_base.gd"
## Uzai stellt sich selbst ein (Punkt 96): Größe der Oberfläche ohne Neuaufbau, Zeilen unter
## Einstellungen → Aussehen, Regler in der Einrichtung (mit dem Controller). Ausgabe „SB …“.
## Aufruf: a2_run.sh res://tests/probe_bildschirm.gd bildschirm [--groesse=0.85]

func run() -> void:
	var start_scale := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--groesse="):
			start_scale = float(a.substr(10))
	if start_scale > 0.0:
		# Vergleichsbild: dieselbe Größe von Anfang an (Neuaufbau beim Start).
		await shot("01_start_%d" % roundi(start_scale * 100.0), 1.0)
		return
	await shot("01_start_100", 1.0)
	Config.set_value("theme.ui_scale", 0.85)
	await wait(0.6)
	print("SB Faktor: ", get_tree().root.content_scale_factor)
	await shot("02_live_85", 0.4)
	Config.set_value("display.seen", { "name": "DELL U2723QE", "tech": "dp", "w_cm": 60, "h_cm": 34, "hz": 240.0, "hdr": "moeglich" })
	main.goto("settings", "aussehen")
	await wait(1.2)
	await press("down", 10)
	await shot("03_aussehen", 0.6)
	await press("down", 2)
	await shot("04_automatisch", 0.4)
	Config.set_value("theme.ui_scale", 1.0)
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.step", "darstellung")
	load("res://src/ui/layers/setup_wizard.gd").open_for(main, false)
	await wait(1.4)
	# Mit dem Controller: runter von „Menüklänge“ führt zur Größe rechts, links stellt kleiner.
	for i in 5:
		await press("down")
	var f := Nav.focused()
	print("SB Fokus nach 5× runter: ", f.get_meta("uz_key", "") if f else "-")
	await press("left", 3)
	await wait(0.3)
	print("SB Größe nach 3× links: ", Config.get_value("theme.ui_scale"))
	await shot("05_einrichtung", 0.4)
