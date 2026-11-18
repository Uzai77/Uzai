extends "res://tests/probe_base.gd"
## Probe „Zimmer online“ (Punkt 131, Fundament, ohne Netz): Zimmer-Menü mit „Online: Aus“, der
## Online-Bereich (klar aus), Einstellungen weiter unten, Hinweis zur IP-Adresse, Schutz, Abschottung
## prüfen (unter Linux: „Nur unter Windows“), Anklopfen mit Beispiel-Gästen, Entscheiden, Gästeliste,
## Sperrliste und die Zeile in Einstellungen → System.
##
## Aufruf: A2_PROJ=<projekt> A2_TIMEOUT=400 bash a2_run.sh res://tests/probe_zonline.gd zonline

const OnlineUi := preload("res://src/room/online_ui.gd")


func zeile(layer: Control, titel: String) -> Control:
	for c in Nav.focusables(layer):
		if str(c.get("title")) == titel:
			return c
	print("Nicht gefunden: ", titel)
	return null


func fokus(layer: Control, titel: String) -> void:
	var z := zeile(layer, titel)
	if z:
		Nav.focus(z, true)


func zu_bis(n: int) -> void:
	while Nav.layers.size() > n:
		await press("b", 1, 0.45)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.2)
	main.open_room(true)
	await wait(2.5)
	var z: Control = Nav.top_layer()
	var basis := Nav.layers.size()
	print("Zimmer offen: ", z != null and z.has_method("bauen_an"))
	# Seitenleiste „Zimmer gestalten“ (Menü-Taste) mit dem Abschnitt „Online“.
	await press("menu")
	await wait(0.6)
	await shot("01_zimmer_menue_online", 0.8)
	z.call("online_oeffnen")
	await wait(0.9)
	var o: Control = Nav.top_layer()
	print("Online-Bereich offen: ", o is OnlineUi)
	await shot("02_online_aus", 0.9)
	fokus(o, "Höchstens Gäste")
	await shot("03_einstellungen_wenn_so_weit", 0.8)
	fokus(o, "Gesperrt")
	await shot("04_sicherheit_und_vorschau", 0.9)
	fokus(o, "Hinweis zur IP-Adresse")
	await wait(0.4)
	await press("a")
	await shot("05_ip_hinweis", 1.0)
	await press("b", 1, 0.5)
	fokus(o, "Schutz")
	await wait(0.3)
	await press("a")
	await shot("06_schutz", 1.0)
	await press("b", 1, 0.5)
	fokus(o, "Abschottung prüfen")
	await wait(0.3)
	await press("a")
	await shot("07_abschottung_nur_windows", 1.0)
	await press("b", 1, 0.5)
	# Anklopfen mit Beispiel-Gästen.
	fokus(o, "Anklopfen")
	await wait(0.3)
	await press("a")
	await wait(0.9)
	print("Anklopfen offen: ", Nav.top_layer() is OnlineUi)
	await shot("08_anklopfen", 0.8)
	await press("a")
	await shot("09_anklopfen_entscheiden", 0.9)
	await press("a")
	await shot("10_hereingelassen", 1.2)
	await zu_bis(basis + 1)
	fokus(o, "Gäste im Zimmer")
	await wait(0.3)
	await press("a")
	await wait(0.9)
	await shot("11_gaeste", 0.8)
	await press("a")
	await shot("12_gast_optionen", 0.9)
	await press("down")
	await press("a")
	await shot("13_gesperrt_meldung", 1.2)
	await zu_bis(basis + 1)
	fokus(o, "Gesperrt")
	await wait(0.3)
	await press("a")
	await shot("14_sperrliste", 1.0)
	await zu_bis(basis + 1)
	fokus(o, "Zimmer offline")
	await shot("15_online_nachher", 0.9)
	await press("a")
	await shot("16_zimmer_offline", 1.2)
	await zu_bis(0)
	await wait(0.8)
	# Einstellungen → System: „Zimmer online – Aus“.
	main.open_setting("system", "set:system:Zimmer online")
	await shot("17_einstellungen_system", 1.6)
