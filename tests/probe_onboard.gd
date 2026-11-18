extends "res://tests/probe_base.gd"
## Einrichtung als Moment (Willkommen mit Licht und großem Zeichen, Spiele-Höhepunkt mit Tiefe und
## Glanz, Die Guide-Taste mit echtem Druck, Konten mit Steam und Discord, Bereit, Auflösen in die
## Startseite; der Controller wird still erkannt). Nach „Los“
## baut sich die Startseite auf (startseite_aufbau.gd): ein Bild mitten im
## Aufbau (Licht, Leiste, Titel), eins, während die Cover landen, und das Ende.
## Aufruf wie probe_base.gd, mit --demo.

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.restart", false)
	Config.set_value("einrichtung.tour", true)
	Config.set_value("einrichtung.mehr", false)
	Config.set_value("einrichtung.step", "willkommen")
	Wizard.probe_pad = true
	Wizard._detected = "Xbox Wireless Controller"
	Wizard.open_for(main, false)
	await shot("01a_willkommen_licht", 0.55)
	await shot("01_willkommen", 1.7)
	await press("a")
	await shot("03_spiele_flug", 0.8)
	await shot("04_spiele", 2.4)
	await press("a")
	await shot("05a_guide", 3.0)
	# Die echte Guide-Taste: der Guide öffnet sich über der Einrichtung, B schließt ihn.
	await press("guide")
	await wait(1.2)
	await shot("05b_guide_offen", 0.2)
	await press("b")
	await shot("05c_guide_ausprobiert", 1.2)
	await press("a")
	await shot("05f_konten", 1.2)
	await press("a")
	await shot("06_bereit", 1.6)
	await press("a")
	# press() wartet nach dem Druck 0,18 s: Bilder bei etwa 0,6 s, 1,15 s und 2,4 s nach „Los“.
	await shot("07_aufbau_licht", 0.42)
	await shot("08_aufbau_cover", 0.5)
	await shot("09_startseite", 1.2)
