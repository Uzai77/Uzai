extends "res://tests/probe_base.gd"
## Probe „Schnellmenü anpassen“: Schnellmenü mit der schmalen Kachel „Anpassen“, Bearbeiten-Modus
## ohne Spiel (gedimmte Kacheln mit Hinweis), im Spiel greifen und verschieben, ausblenden, „+“ mit
## der Liste, Fertig (gespeichert) und der Weg aus den Einstellungen. Gibt „SM ok/FAIL …“ aus.

const Guide := preload("res://src/ui/layers/guide.gd")
const GuideQuick := preload("res://src/ui/components/guide_quick.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("SM %s %s" % ["ok  " if cond else "FAIL", what])


func _key() -> String:
	var f := Nav.focused()
	return str(f.get_meta("uz_key", "")) if f else ""


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.5)


func _bis(key: String) -> void:
	var n := 0
	while _key() != key and n < 12:
		await press("right", 1, 0.15)
		n += 1


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("system.quick_tiles", [])
	# 1. Ohne Spiel: Schnellmenü, dann Anpassen mit der Menü-Taste.
	main.toggle_guide(Guide.QUICK)
	await shot("01_schnellmenue", 1.2)
	await _bis("qm:anpassen")
	await shot("02_anpassen_gewaehlt", 0.4)
	await press("menu", 1, 0.6)
	var g: Control = main._guide
	_ck(GuideQuick.bearbeitet(g), "Menü-Taste: Bearbeiten-Modus")
	await shot("03_bearbeiten_ohne_spiel", 0.4)
	await press("b", 1, 0.6)
	_ck(is_instance_valid(g) and not GuideQuick.bearbeitet(g), "B: fertig, das Schnellmenü bleibt offen")
	await _close_all()
	# 2. Im Spiel: greifen, verschieben, ausblenden, hinzufügen.
	Launcher.in_game = true
	Launcher.current = Library.get_game(Library.recent(1)[0].id)
	main.toggle_guide(Guide.QUICK)
	await wait(1.2)
	await shot("04_schnellmenue_spiel", 0.2)
	await press("menu", 1, 0.6)
	g = main._guide
	await press("right", 1, 0.3)
	_ck(_key() == "qe:clip", "zweite Kachel gewählt (%s)" % _key())
	await press("a", 1, 0.3)
	await press("right", 1, 0.08)
	await shot("05_gegriffen_unterwegs", 0.0)
	await press("right", 1, 0.5)
	await shot("06_gegriffen_verschoben", 0.2)
	var liste: Array = GuideQuick._stand(g).liste
	_ck(liste.find("clip") == 3, "Clip zwei Plätze weiter (%s)" % str(liste))
	await press("a", 1, 0.4)
	await press("right", 1, 0.3)
	await press("x", 1, 0.5)
	_ck((GuideQuick._stand(g).aus as Array).size() == 1, "X: ausgeblendet (%s)" % str(GuideQuick._stand(g).aus))
	await shot("07_ausgeblendet", 0.3)
	await _bis("qe:guide")
	await press("x", 1, 0.5)
	_ck(GuideQuick._stand(g).aus.size() == 1, "Guide lässt sich nicht ausblenden")
	await wait(2.4)
	await _bis("qe:neu")
	await press("a", 1, 0.9)
	await shot("08_hinzufuegen_liste", 0.2)
	await press("down", 1, 0.3)
	await press("a", 1, 0.9)
	await shot("09_hinzugefuegt", 0.3)
	await press("b", 1, 0.8)
	var gespeichert: Variant = Config.get_value("system.quick_tiles", [])
	_ck(gespeichert is Array and (gespeichert as Array).size() == 8 and (gespeichert as Array).has("guide"), "B: gespeichert (%s)" % str(gespeichert))
	await shot("10_fertig_im_spiel", 0.4)
	await _close_all()
	Launcher.in_game = false
	Launcher.current = {}
	await wait(0.5)
	# 3. Aus den Einstellungen: gleich im Bearbeiten-Modus, B führt zurück.
	main.goto("settings", "im_spiel")
	await wait(1.2)
	var q: Control = GuideQuick.oeffnen_zum_anpassen(main)
	await wait(1.0)
	_ck(q != null and GuideQuick.bearbeitet(q), "Einstellungen: Schnellmenü gleich zum Anpassen")
	await shot("11_aus_einstellungen", 0.2)
	await press("b", 1, 0.8)
	_ck(main._guide == null, "B: zurück in die Einstellungen")
	await shot("12_einstellungen", 0.4)
	print("SM Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
