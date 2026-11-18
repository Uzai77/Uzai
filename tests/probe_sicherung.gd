extends "res://tests/probe_base.gd"
## Einstellungen → System → Sicherungen: anlegen und Liste. Ausgabe „SI …“.

func run() -> void:
	var Backup := load("res://src/core/backup.gd")
	Backup.create(Config.data_dir, "update-0.8.2-0.8.3")
	main.goto("settings", "system")
	await wait(1.2)
	var sv = main.sections["settings"]
	sv.open_more("Sicherungen")
	await wait(1.0)
	await shot("01_sicherungen", 0.4)
	print("SI Liste: ", Backup.list(Config.data_dir).size())
