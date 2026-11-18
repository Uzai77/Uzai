extends "res://tests/probe_base.gd"
## Messung „ist alles Englisch?“: Uzai im Demo-Modus auf Englisch durch die wichtigen Bildschirme
## schicken und alle sichtbaren Texte sammeln, die nach der Übersetzung noch deutsch aussehen
## (Umlaute, ß, häufige deutsche Wörter). Namen aus den Demo-Daten (Spiele, Freunde) sind
## ausgenommen. Ergebnis: <out>/funde.txt („Bildschirm | Text | Grund | Katalog“), Zeilen „EN …“.
## Vorher im Datenordner settings.json mit {"system": {"language": "en"}} anlegen:
##   UZAI_DATA=$D xvfb-run … -- --demo --no-boot --uzai-script=res://tests/probe_englisch.gd --uzai-out=<ordner>

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const E := preload("res://src/core/einrichtung.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const Pruef := preload("res://tests/englisch_pruef.gd")

var _pruef: Pruef
var _funde: Array = []
var _gesehen := {}


func run() -> void:
	print("EN Sprache: ", TranslationServer.get_locale())
	_pruef = Pruef.new()
	_pruef.namen_aus_demo()
	Config.set_value("controller.glyphs", "xbox")
	await _scan("start")
	for sid in main.sections.keys():
		if sid == "settings":
			continue
		main.goto(sid)
		await wait(1.1)
		await _scan("bereich:" + str(sid))
	for sub in ["aussehen", "klang", "spiele", "emulation", "konten", "controller", "imspiel", "aufnahmen", "medien", "mitteilungen", "system"]:
		main.goto("settings", sub)
		await wait(0.7)
		await _scan("einstellungen:" + sub)
	main.goto("games")
	await wait(0.6)
	for t in Guide.TABS + [[Guide.QUICK, ""]]:
		main.toggle_guide(str(t[0]))
		await wait(1.0)
		await _scan("guide:" + str(t[0]))
		await _close_all()
	# Im Spiel: Guide-Start mit dem laufenden Spiel.
	var rec: Array = Library.recent(2)
	if not rec.is_empty():
		Launcher.in_game = true
		Launcher.current = Library.get_game(str(rec[0].id))
		main.toggle_guide()
		await wait(1.0)
		await _scan("guide:imspiel")
		await _close_all()
		Launcher.in_game = false
		Launcher.current = {}
		main.open_game(Library.get_game(str(rec[0].id)), true)
		await wait(1.2)
		await _scan("spielseite")
		await _close_all()
		main.open_game_options(Library.get_game(str(rec[0].id)))
		await wait(0.6)
		await _scan("spieloptionen")
		await _close_all()
	for ebene in ["open_friends", "open_power", "open_notifications", "open_search", "open_captures"]:
		main.call(ebene)
		await wait(0.9)
		await _scan("ebene:" + ebene)
		await _close_all()
	main.open_dialog("Wirklich beenden?", "Nicht gespeicherter Fortschritt geht verloren.", [["Beenden", func() -> void: pass], ["Abbrechen", func() -> void: pass]])
	await wait(0.5)
	await _scan("dialog")
	await _close_all()
	# Einrichtung: jeder Schritt.
	for st in E.STEPS:
		Config.set_value("einrichtung.done", false)
		Config.set_value("einrichtung.restart", false)
		Config.set_value("einrichtung.mehr", true)
		Config.set_value("einrichtung.step", st)
		var w: Control = Wizard.open_for(main, false)
		await wait(1.6 if st == "emulatoren" else 0.9)
		await _scan("einrichtung:" + st)
		w.set("_finished", true)
		w.call("close")
		await wait(0.4)
	Config.set_value("einrichtung.done", true)
	_schreiben()


func _close_all() -> void:
	var n := 0
	while Nav.top_layer() and n < 8:
		Nav.top_layer().close()
		n += 1
		await wait(0.12)
	await wait(0.3)


func _scan(wo: String) -> void:
	await RenderingServer.frame_post_draw
	var vor := _funde.size()
	for t in _pruef.sichtbare_texte(get_tree().root):
		var grund := _pruef.deutsch(t)
		if grund == "" or _gesehen.has(t):
			continue
		_gesehen[t] = true
		_funde.append([wo, t, grund, "Katalog" if _pruef.im_katalog(t) else "-"])
	print("EN %-28s %d neu" % [wo, _funde.size() - vor])


func _schreiben() -> void:
	var f := FileAccess.open(out.path_join("funde.txt"), FileAccess.WRITE)
	for x in _funde:
		var zeile := "%s | %s | %s | %s" % [x[0], str(x[1]).replace("\n", "⏎"), x[2], x[3]]
		f.store_line(zeile)
		print("EN> ", zeile)
	f.close()
	print("EN Funde: ", _funde.size())
