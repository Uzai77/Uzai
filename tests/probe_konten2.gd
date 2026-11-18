extends "res://tests/probe_base.gd"
## Einrichtung, Schritt Konten: SteamGridDB empfohlen, alle Konten zur Wahl; danach Einstellungen → Konten.

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.mehr", true)
	Config.set_value("einrichtung.step", "konten")
	Wizard.open_for(main, false)
	await wait(2.4)
	await shot("01_einrichtung_konten", 0.3)
	await press("a")
	await wait(1.2)
	await shot("02_steamgriddb", 0.4)
