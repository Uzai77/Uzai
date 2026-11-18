extends "res://tests/probe_base.gd"
## Erster Start (Punkte 52, 53): Einrichtung → Konten (nur per QR), Fertig, danach die kurze Tour
## über der Startseite (vier Hinweise, Xbox- und PlayStation-Symbole), B beendet sie; Einstellungen
## → System mit „Kurze Tour“ und die Tour von dort.

const SetupWizard := preload("res://src/ui/layers/setup_wizard.gd")
const Tour := preload("res://src/ui/layers/tour.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.tour", false)
	Config.set_value("einrichtung.restart", false)
	Config.set_value("einrichtung.step", "konten")
	SetupWizard.open_for(main, false)
	await wait(1.6)
	await shot("01_konten", 0.3)
	await press("y")
	await wait(0.8)
	if str(Config.get_value("einrichtung.step", "")) == "extras":
		await press("y")
		await wait(0.8)
	await shot("02_fertig", 0.4)
	# In der Vorführung kommt die Tour nie von selbst; hier kurz wie bei einem echten ersten Start.
	Library.demo = false
	await press("a")
	await wait(1.7)
	Library.demo = true
	print("Tour offen: ", Nav.top_layer() != null and Nav.top_layer().get_script() == Tour)
	await shot("03_tour_guide", 0.2)
	await press("a")
	await shot("04_tour_suche", 0.6)
	await press("a")
	await shot("05_tour_optionen", 0.6)
	Config.set_value("controller.glyphs", "ps")
	await press("a")
	await shot("06_tour_einstellungen_ps", 0.6)
	await press("b")
	await wait(0.6)
	print("Tour zu: ", Nav.top_layer() == null, " · gemerkt: ", Config.get_value("einrichtung.tour", false))
	await shot("07_startseite", 0.3)
	Config.set_value("controller.glyphs", "auto")
	main.open_setting("system", "")
	await wait(1.2)
	for c in Nav.focusables(main.view_host):
		if str(c.get("title")) == "Kurze Tour":
			Nav.focus(c, true)
	await shot("08_einstellungen_system", 0.6)
	await press("a")
	await wait(1.0)
	await shot("09_tour_tastatur", 0.2)
	await press("a")
	await press("a")
	await press("a")
	await shot("10_letzter_hinweis", 0.6)
	await press("a")
	await wait(0.6)
	print("Tour nach „Los geht's“ zu: ", Nav.top_layer() == null)
	await shot("11_zurueck", 0.2)
