extends "res://tests/probe_base.gd"
## Uzai-Browser im Vorführmodus (Platzhalter-Seite statt Kern): Startbühne und ihr Aufgang in den Browser,
## Startseite, Seite mit Fokusrahmen, Leiste und Link-Vorschau, Kontextrad, Gliederung, Fernbedienung Plus,
## Kern laden; dazu Springen, Bereiche, Zoom, Tabs und B. Ausgabe „BR ok/FAIL …“, Bilder 01–09.

const K := preload("res://src/core/browser_karte.gd")
const P := preload("res://src/core/browser_protokoll.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("BR %s %s" % ["ok  " if cond else "FAIL", what])


func _ebene() -> Control:
	for l in Nav.layers:
		if is_instance_valid(l) and str(l.get_script().resource_path).ends_with("layers/browser.gd"):
			return l
	return null


## Ein Bild nach n gezeichneten Bildern (ohne Wartezeit dazwischen).
func bild(name: String, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("Bild: ", name)


func _oben(endung: String) -> bool:
	var top := Nav.top_layer()
	return top != null and str(top.get_script().resource_path).ends_with(endung)


func run() -> void:
	Config.set_value("browser.favoriten", [
		{ "url": "https://www.tagesschau.de/", "titel": "Nachrichten" }, { "url": "https://www.youtube.com/", "titel": "Videos" },
		{ "url": "https://de.wikipedia.org/", "titel": "Wikipedia" }, { "url": "https://www.chefkoch.de/", "titel": "Rezepte" },
		{ "url": "https://www.dwd.de/", "titel": "Wetter" }])
	Config.set_value("browser.apps", [{ "url": "https://www.zdf.de/", "titel": "Mediathek", "zoom": 125 },
		{ "url": "https://www.twitch.tv/", "titel": "Twitch", "zoom": 100 }])
	Config.set_value("browser.zuletzt", [{ "url": "https://uzai.example/start", "titel": "Platzhalter" },
		{ "url": "https://www.heise.de/", "titel": "heise online" }, { "url": "https://www.kicker.de/", "titel": "Kicker" }])
	_ck(main.app_kids.has("browser"), "Browser als App oben in der Leiste")
	# Startbühne und Aufgang
	main.goto("browser")
	await wait(1.5)
	var f: Control = Nav.focused()
	_ck(f != null and str(f.get_meta("uz_key", "")) == "browser:oeffnen", "Startbühne: Cursor auf der Bühne")
	await shot("01_startbuehne", 0.5)
	Nav._fire("a")
	# Zwischenbilder des Aufgangs nach Bildern statt Zeit (unter xvfb sind Bilder langsam): früh und mittendrin.
	await bild("02_aufgang_a", 3)
	await bild("02_aufgang_b", 3)
	await wait(1.2)
	var b := _ebene()
	_ck(b != null and str(b.get("modus")) == "start", "Browser offen: Startseite")
	_ck(b != null and b.get("_aufgang") == null, "Aufgang zu Ende")
	_ck(Nav.focused() != null and str(Nav.focused().get_meta("uz_key", "")) == "browser:suche", "Cursor auf der Suche")
	await shot("03_startseite", 0.5)
	b.call("_oeffnen", "https://uzai.example/start", true, 0)
	await wait(1.2)
	_ck(str(b.get("modus")) == "seite" and int(b.get("aktiv")) > 0, "Seite offen, ein Tab")
	var t: Dictionary = b.call("_tab")
	var f0 := int(t.fokus)
	_ck(f0 > 0, "Fokus auf einem Ziel der Seite")
	_ck(not (t.get("blocker", {}) as Dictionary).is_empty(), "Blocker-Pille: Zahlen der Seite da")
	await press("right", 1, 0.3)
	_ck(int(b.call("_tab").fokus) != f0, "rechts: nächstes Ziel")
	await press("rb", 1, 0.4)
	var t2: Dictionary = b.call("_tab")
	var z: Dictionary = K.finde(t2.ziele, int(t2.fokus))
	_ck(not z.is_empty() and int(z.bereich) == P.BEREICHE.find("seite"), "RB: in die Seitenleiste")
	# Link-Vorschau: der Link führt zu einer anderen Seite, nach 0,9 s steht ihr Name unter dem Rahmen.
	await wait(1.4)
	var rahmen: Control = b.get("_rahmen")
	_ck(rahmen != null and str(rahmen.get("_hinweis")) == "beliebt.example", "Link-Vorschau: Name der Seite unter dem Rahmen (%s)" % str(rahmen.get("_hinweis")))
	b.call("_ui_zeigen", 4.0)
	await shot("04_seite_fokus", 0.6)
	await press("lb", 2, 0.4)
	await press("down", 2, 0.35)
	await press("rt", 1, 0.5)
	_ck(int(b.call("_tab").zoom) == 110, "RT: Zoom 110 %")
	await press("lt", 1, 0.5)
	Input.action_press("uz_a")
	Nav._fire("a")
	await wait(0.75)
	Input.action_release("uz_a")
	await wait(0.4)
	_ck(_oben("browser_rad.gd"), "A halten: Kontextrad")
	await shot("05_kontextrad", 0.4)
	if _oben("browser_rad.gd"):
		Nav.top_layer().close()
		await wait(0.5)
	# Gliederung der Seite
	b.wirt.senden("gliederung", { "tab": int(b.get("aktiv")) })
	await wait(0.9)
	_ck(_oben("sheet.gd"), "Gliederung als Liste")
	await shot("06_gliederung", 0.4)
	if _oben("sheet.gd"):
		Nav.top_layer().close()
		await wait(0.5)
	# Fernbedienung Plus: Video läuft, die Leiste unten zeigt Zeit, Lautstärke, Tempo.
	for a in ["spielen", "tempo_auf", "vor"]:
		b.wirt.senden("video", { "tab": int(b.get("aktiv")), "aktion": a })
	await wait(0.3)
	b.set("video_an", true)
	b.call("_tasten_setzen")
	b.call("_ui_zeigen", 4.0)
	await wait(0.2)
	var leiste: Control = b.get("_video_leiste")
	_ck(leiste != null and leiste.visible and int((b.call("_tab").video as Dictionary).get("tempo", 0)) == 125, "Fernbedienung Plus: Leiste mit Tempo")
	await shot("07_video_fernbedienung", 0.5)
	await press("b", 1, 0.4)
	_ck(not bool(b.get("video_an")), "B: Fernbedienung aus")
	# Kern laden: die Frage, dann der Fortschritt (gespielt).
	b.call("_kern_anbieten")
	await wait(0.9)
	_ck(_oben("browser_kern_ui.gd"), "Kern laden: Frage mit Erklärung")
	await shot("08_kern_frage", 0.4)
	await press("a", 1, 0.3)
	await shot("09_kern_laedt", 0.7)
	await wait(2.6)
	_ck(not _oben("browser_kern_ui.gd"), "Kern geladen (gespielt): Frage zu")
	await press("b", 1, 0.5)
	_ck(str(b.get("modus")) == "start" or bool(b.call("_tab").get("zurueck", false)), "B: zurück bzw. Startseite")
	b.close()
	await wait(0.6)
	_ck(_ebene() == null and main.shell.visible, "B/Schließen: Uzai wieder da")
	print("BR Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
