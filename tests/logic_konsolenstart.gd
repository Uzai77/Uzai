extends Node
## Start-Sequenzen je Konsole (system_intro.gd, Roadmap 17): Zuordnung System → Sequenz mit
## Rückfall über die Familie und neutraler Uzai-Sequenz, echtes Logo nur mit badges.real_logos und
## Logo im Cache, Abbruch mit A/B und beim Spielfenster, Dauer und Ausblenden.
## Aufruf: godot --headless --path . res://tests/logic_konsolenstart.tscn

const SystemIntro := preload("res://src/ui/components/system_intro.gd")
const Logos := preload("res://src/core/badge_logos.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_zuordnung()
	_vollstaendig()
	await _logo()
	_abbruch()
	_dauer()
	_vorschau()
	await _endet_selbst()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _zuordnung() -> void:
	print("Zuordnung")
	var soll := { "ps2": "ps2", "ps1": "ps1", "gc": "gc", "wii": "wii", "dreamcast": "dreamcast", "xbox": "xbox", "n64": "n64",
		"snes": "snes", "megadrive": "megadrive", "nes": "8bit", "gb": "gb", "gba": "gba", "nds": "nds", "switch": "switch",
		"ps3": "welle", "xbox360": "xbox360", "saturn": "saturn", "arcade": "arcade" }
	for s in soll.keys():
		check(SystemIntro.sequenz(s) == soll[s], "%s → %s" % [s, soll[s]])
	check(SystemIntro.sequenz("psp") == "welle" and SystemIntro.variante("psp") == 1, "PSP: Welle in Blau")
	check(SystemIntro.sequenz("wiiu") == "wii" and SystemIntro.variante("wiiu") == 1, "Wii U: Wii-Sequenz, eigene Variante")
	check(SystemIntro.sequenz("gbc") == "gb" and SystemIntro.variante("gbc") == 1, "Game Boy Color: eigene Variante")
	check(SystemIntro.sequenz("gamegear") == "gb" and SystemIntro.variante("gamegear") == 2, "Game Gear: hinterleuchtet")
	check(SystemIntro.sequenz("pce") == "snes" and SystemIntro.variante("pce") == 1, "PC Engine: 16-Bit, eigene Farben")
	check(SystemIntro.sequenz("pico8") == SystemIntro.NEUTRAL and SystemIntro.sequenz("") == SystemIntro.NEUTRAL, "unbekannt: neutrale Uzai-Sequenz")
	check(SystemIntro.variante("pico8") == 0, "unbekannt: Variante 0")
	check(SystemIntro.soll({ "source": "rom", "system": "pico8" }, "theme", false, false), "unbekanntes System: läuft (neutral)")
	check(not SystemIntro.soll({ "source": "rom", "system": "ps2" }, "theme", true, false), "leichter Modus: nie")
	check(not SystemIntro.soll({ "source": "rom", "system": "ps2" }, "theme", false, true), "Animationen reduzieren: nie")
	check(not SystemIntro.soll({ "source": "steam", "system": "" }, "theme", false, false), "kein Emulator-Spiel: nie")
	# The shader intros (as up to 0.16.12) are the default again; the 3D scenes only run when selected
	# ("3D-Szenen").
	check(SystemIntro.soll({ "source": "rom", "system": "ps2" }, "3d", false, false), "„3D-Szenen“: läuft")
	check(not SystemIntro.drei_d_gewaehlt("theme") and SystemIntro.drei_d_gewaehlt("3d"), "3D nur, wenn gewählt")
	var ids: Array = SystemIntro.MODES.map(func(m): return str(m[0]))
	check(ids == ["theme", "3d", "aus"], "Wahl: An (Standard), 3D-Szenen, Aus")
	var alt_wert = Config.get_value("theme.system_intro", "theme")
	for sys in ["ps2", "gc", "ps1", "n64", "switch"]:
		Config.set_value("theme.system_intro", "theme")
		var si: Control = SystemIntro.new().setup({ "source": "rom", "system": sys })
		add_child(si)
		si.set_process(false)
		var bild: Control = si.get("_bild")
		check(si.get("_buehne") == null and bild.visible, "%s: wieder der Shader-Start wie bis 0.16.12" % sys)
		si.free()
	Config.set_value("theme.system_intro", "3d")
	var si3: Control = SystemIntro.new().setup({ "source": "rom", "system": "gc" })
	add_child(si3)
	si3.set_process(false)
	check(si3.get("_buehne") != null, "mit „3D-Szenen“: GameCube als 3D-Szene")
	si3.free()
	Config.set_value("theme.system_intro", alt_wert)


func _vollstaendig() -> void:
	print("Vollständig")
	var ohne := []
	for s in Config.systems():
		var q := SystemIntro.sequenz(str(s.id))
		if not SystemIntro.SHADER.has(q):
			ohne.append(str(s.id))
	check(ohne.is_empty(), "jedes System hat eine Sequenz mit Shader (%s)" % ", ".join(ohne))
	var fam := []
	for f in SystemIntro.FAMILIEN.keys():
		for s in SystemIntro.FAMILIEN[f]:
			if not SystemIntro.SEQUENZEN.has(s):
				fam.append(s)
	check(fam.is_empty(), "jedes System der Familien hat eine eigene Zuordnung (%s)" % ", ".join(fam))
	var fehlt := []
	for q in SystemIntro.SHADER.keys():
		if not SystemIntro.SCHRIFT.has(q):
			fehlt.append(q)
	check(fehlt.is_empty(), "jede Sequenz hat Platz und Tinte für den Namen (%s)" % ", ".join(fehlt))
	var gezeigt := {}
	for s in SystemIntro.REIHE:
		gezeigt[SystemIntro.sequenz(str(s))] = true
	check(gezeigt.size() == SystemIntro.SHADER.size(), "Vorschau zeigt alle %d Sequenzen (%d)" % [SystemIntro.SHADER.size(), gezeigt.size()])
	for f in SystemIntro.FAMILIEN_SEQUENZ.values():
		check(SystemIntro.SHADER.has(f), "Familien-Rückfall %s hat einen Shader" % f)


func _logo() -> void:
	print("Logo nur mit real_logos und Cache")
	var dir := OS.get_user_data_dir().path_join("test_konsolenstart_%d" % Time.get_ticks_msec())
	Logos.data_dir_override = dir
	Logos.media_dir_override = dir.path_join("medien")
	Logos.net = false
	var vorher: Variant = Config.get_value("badges.real_logos", true)
	Config.set_value("badges.real_logos", true)
	check(SystemIntro.logo_schluessel("ps2") == "", "an, aber nicht im Cache: Name")
	DirAccess.make_dir_recursive_absolute(dir.path_join("cache/logos"))
	var img := Image.create(120, 30, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(10, 5, 100, 20), Color(0.1, 0.2, 0.8, 1))
	img.save_png(Logos.cache_path("ps2"))
	check(SystemIntro.logo_schluessel("ps2") == "ps2", "an und im Cache: Logo")
	check(SystemIntro.logo_schluessel("pico8") == "", "System ohne Logo: Name")
	var si: Control = SystemIntro.new().setup({ "source": "rom", "system": "ps2" })
	si.size = Vector2(1920, 1080)
	add_child(si)
	# Das Logo lädt in einem Hintergrund-Task: nach der Uhr warten, nicht nach Bildern (unter Last
	# liefen 60 kopflose Bilder durch, bevor der Task fertig war).
	var bis := Time.get_ticks_msec() + 5000
	while not si.call("zeigt_logo") and Time.get_ticks_msec() < bis:
		await get_tree().process_frame
	check(bool(si.call("zeigt_logo")), "Logo im Hintergrund vorbereitet")
	si.queue_free()
	Config.set_value("badges.real_logos", false)
	check(SystemIntro.logo_schluessel("ps2") == "", "abgeschaltet: nie das Logo, auch wenn es im Cache liegt")
	var si2: Control = SystemIntro.new().setup({ "source": "rom", "system": "ps2" })
	check(str(si2.get("_logo_key")) == "" and not bool(si2.call("zeigt_logo")), "abgeschaltet: die Sequenz endet mit dem Namen")
	check(str(si2.get("name_text")) != "", "Name des Systems steht bereit (%s)" % str(si2.get("name_text")))
	si2.free()
	Config.set_value("badges.real_logos", vorher)
	Logos.data_dir_override = ""
	Logos.media_dir_override = ""
	await get_tree().process_frame


func _abbruch() -> void:
	print("Abbruch")
	if not InputMap.has_action("uz_b"):
		InputMap.add_action("uz_b")
	if not InputMap.has_action("uz_a"):
		InputMap.add_action("uz_a")
	for a in ["uz_a", "uz_b"]:
		var si: Control = SystemIntro.new().setup({ "source": "rom", "system": "gc" })
		add_child(si)
		si.set_process(false)
		si.call("at_time", 0.8)
		check(is_equal_approx(float(si.call("deckkraft", 0.8)), 1.0), "%s: vorher ganz da" % a)
		var ev := InputEventAction.new()
		ev.action = a
		ev.pressed = true
		si.call("_input", ev)
		check(float(si.get("_aus_t")) >= 0.0, "%s bricht ab" % a)
		var mitte := float(si.call("deckkraft", 0.8 + SystemIntro.ABBRUCH * 0.5))
		check(mitte > 0.0 and mitte < 1.0, "weich weg (%.2f)" % mitte)
		check(bool(si.call("vorbei", 0.8 + SystemIntro.ABBRUCH + 0.01)), "nach %.2f s vorbei" % SystemIntro.ABBRUCH)
		check(si.mouse_filter == Control.MOUSE_FILTER_IGNORE and si.focus_mode == Control.FOCUS_NONE, "fängt keine Eingaben ab")
		si.free()
	var sw: Control = SystemIntro.new().setup({ "source": "rom", "system": "ps2" })
	add_child(sw)
	sw.set_process(false)
	var l := get_node_or_null("/root/Launcher")
	check(l != null and l.is_connected("window_ready", Callable(sw, "_on_fenster")), "hört auf das Spielfenster")
	sw.call("_on_fenster", {})
	check(float(sw.get("_aus_t")) >= 0.0, "Spielfenster da: geht")
	sw.free()


func _dauer() -> void:
	print("Dauer")
	check(SystemIntro.DAUER >= 2.0 and SystemIntro.DAUER <= 3.0, "zwei bis drei Sekunden (%.1f)" % SystemIntro.DAUER)
	check(SystemIntro.NAME_AB < SystemIntro.AUS_AB and SystemIntro.AUS_AB < SystemIntro.DAUER, "Name, dann Überblenden, dann Ende")
	var si: Control = SystemIntro.new().setup({ "source": "rom", "system": "dreamcast" })
	check(is_equal_approx(float(si.call("deckkraft", 1.0)), 1.0), "Mitte: ganz da")
	check(float(si.call("deckkraft", SystemIntro.DAUER)) <= 0.001, "am Ende ganz in der Karte")
	check(float(si.call("deckkraft", 0.0)) <= 0.001, "beginnt weich")
	check(bool(si.call("vorbei", SystemIntro.DAUER)) and not bool(si.call("vorbei", 1.0)), "vorbei genau nach DAUER")
	si.free()
	# Regie: Höhepunkt kurz vor dem Namen, der Name setzt sich (106 % → 100 %), ein Glanz läuft
	# einmal über ihn, danach steht er ruhig.
	check(SystemIntro.HOEHEPUNKT < SystemIntro.NAME_AB and SystemIntro.HOEHEPUNKT > SystemIntro.NAME_AB - 0.3, "Höhepunkt kurz vor dem Namen")
	check(is_equal_approx(SystemIntro.name_mass(0.0), 1.06) and is_equal_approx(SystemIntro.name_mass(1.0), 1.0), "Name setzt sich von 106 % auf 100 %")
	check(SystemIntro.name_glanz(SystemIntro.NAME_AB) < -0.5 and SystemIntro.name_glanz(SystemIntro.AUS_AB) < -0.5, "Glanz nur, während der Name kommt")
	var lagen: Array = []
	for i in 20:
		var g := SystemIntro.name_glanz(SystemIntro.NAME_AB + 0.1 + i * 0.03)
		if g > -0.5:
			lagen.append(g)
	var steigt := lagen.size() >= 10
	for i in range(1, lagen.size()):
		steigt = steigt and float(lagen[i]) > float(lagen[i - 1])
	check(steigt, "Glanz läuft einmal von links nach rechts")


func _vorschau() -> void:
	print("Vorschau")
	var si: Control = SystemIntro.new()
	si.set("preview", true)
	add_child(si)
	si.set_process(false)
	var erste := str(si.get("sequenz_id"))
	si.call("_process", SystemIntro.DAUER + 0.5)
	check(str(si.get("sequenz_id")) != erste and int(si.get("_cycle")) == 1, "Schleife: nächste Sequenz")
	si.call("abbrechen")
	check(float(si.get("_aus_t")) < 0.0, "Vorschau: kein Abbruch")
	si.free()


func _endet_selbst() -> void:
	print("Endet von selbst")
	# Nach der Uhr, nicht nach Bildern: eine eigene Uhr, die je Bild 50 ms weiterläuft (unter Last
	# lief die Wanduhr der Prüfung davon). Zwei Bilder Aufwärmen, dann genau DAUER.
	var si: Control = SystemIntro.new().setup({ "source": "rom", "system": "n64" })
	var uhr := [100000]
	si.set("uhr_ms", func() -> int: return int(uhr[0]))
	add_child(si)
	si.set_process(false)
	var bilder := 0
	var vorher_weg := false
	while not si.is_queued_for_deletion() and bilder < 200:
		si.call("_process", 0.05)
		bilder += 1
		if bilder == 2 + int((SystemIntro.DAUER - 0.1) / 0.05) and si.is_queued_for_deletion():
			vorher_weg = true
		uhr[0] += 50
	var ende := 2 + int(ceil(SystemIntro.DAUER / 0.05))
	check(si.is_queued_for_deletion() and not vorher_weg and absi(bilder - ende) <= 1,
		"nach DAUER weg, nicht vorher (%d Bilder à 50 ms, erwartet %d)" % [bilder, ende])
	await get_tree().process_frame
	check(not is_instance_valid(si), "danach freigegeben")
