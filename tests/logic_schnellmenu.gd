extends Node
## Schnellmenü anpassen: Auswahl und Standard, Prüfen gespeicherter Werte, Verschieben,
## Aus- und Einblenden, Hinzufügen, Kontext (gerade nicht da) und dass der Guide nie verschwindet.
## Aufruf: godot --headless --path . res://tests/logic_schnellmenu.tscn

const Wahl := preload("res://src/ui/components/guide_quick_wahl.gd")
const GuideQuick := preload("res://src/ui/components/guide_quick.gd")
const IconsS := preload("res://src/core/icons.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_standard()
	_pruefen()
	_kontext()
	_bearbeiten()
	_speichern()
	_quelle()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _standard() -> void:
	print("Standard wie bisher")
	var keep: Variant = Config.get_value("system.quick_tiles", [])
	Config.set_value("system.quick_tiles", [])
	check(Config.DEFAULTS.system.quick_tiles is Array and (Config.DEFAULTS.system.quick_tiles as Array).is_empty(), "Standard in den Einstellungen: leer")
	check(Wahl.auswahl() == Wahl.STANDARD, "leer: die bisherige Auswahl")
	# Dieselben Lagen wie früher – dieselben Kacheln in derselben Reihenfolge.
	check(GuideQuick.ids({ "shot": true, "game": true, "voice": true }) == ["shot", "clip", "mic", "rest", "quit", "guide"], "im Spiel wie bisher")
	check(GuideQuick.ids({ "shot": true, "video": true }) == ["shot", "rest", "video_stop", "guide"], "Video wie bisher")
	check(GuideQuick.ids({}) == ["rest", "power", "guide"], "nichts läuft wie bisher")
	check(GuideQuick.ids({ "shot": true, "game": true, "mic": true, "leistung": true, "pip": true })
			== ["shot", "clip", "mic", "leistung", "pip", "rest", "quit", "guide"], "alles da: höchstens acht, Guide zuletzt")
	check(GuideQuick.ids({ "musik": true, "ton": true, "pads": true, "zimmer": true, "aufnahme": true }) == ["rest", "power", "guide"],
			"neue Kacheln nicht im Standard")
	check(Wahl.STANDARD.size() <= Wahl.MAX and Wahl.MAX == 8, "Standard passt in die Leiste (höchstens acht)")
	for k in Wahl.KACHELN:
		check(IconsS.P.has(str(k[2])), "Kachel %s: Symbol „%s“ gibt es" % [k[0], k[2]])
	for id in Wahl.STANDARD:
		check(Wahl.bekannt(str(id)), "Standard-Kachel %s ist bekannt" % id)
	Config.set_value("system.quick_tiles", keep)


func _pruefen() -> void:
	print("Gespeicherte Werte prüfen")
	check(Wahl.pruefen("kaputt") == Wahl.STANDARD and Wahl.pruefen(null) == Wahl.STANDARD and Wahl.pruefen({}) == Wahl.STANDARD, "kein Array: Standard")
	check(Wahl.pruefen([7, null, "unbekannt", {}]) == Wahl.STANDARD, "nichts Brauchbares: Standard")
	check(Wahl.pruefen(["musik", "musik", "guide", "musik"]) == ["musik", "guide"], "doppelt zählt einmal")
	check(Wahl.pruefen(["musik", "ton"]) == ["musik", "ton", "guide"], "ohne Guide: er kommt ans Ende")
	check(Wahl.pruefen(["guide", "musik"]) == ["guide", "musik"], "Guide vorn bleibt vorn")
	check(Wahl.pruefen(["quit", "power", "shot"]) == ["beenden", "shot", "guide"], "alte Kennungen werden „Beenden“, einmal")
	var lang: Array = []
	for k in Wahl.KACHELN:
		lang.append(str(k[0]))
	var p := Wahl.pruefen(lang)
	check(p.size() == Wahl.MAX and p.has("guide"), "zu lang: gekürzt, Guide bleibt (%s)" % str(p))
	var ohne_guide := lang.filter(func(i): return i != "guide")
	var q := Wahl.pruefen(ohne_guide)
	check(q.size() == Wahl.MAX and q.back() == "guide", "zu lang ohne Guide: Guide als letzte (%s)" % str(q))
	var riesig: Array = []
	for i in 5000:
		riesig.append("x%d" % i)
	riesig.append("musik")
	check(Wahl.pruefen(riesig) == Wahl.STANDARD, "riesiger Wert: nur der Anfang wird angesehen")
	check(Wahl.pruefen([&"musik"]) == ["musik", "guide"], "StringName geht auch")


func _kontext() -> void:
	print("Kontext: nur was gerade geht")
	var wahl := ["clip", "pip", "musik", "einstellungen", "beenden", "guide"]
	check(GuideQuick.ids({}, wahl) == ["einstellungen", "power", "guide"], "ohne Spiel kein Clip, ohne Bild in Bild kein Verschieben, keine Musik")
	check(GuideQuick.ids({ "shot": true, "game": true, "pip": true, "musik": true }, wahl) == ["clip", "pip", "musik", "quit", "guide"],
			"im Spiel: Clip, Bild verschieben, Musik; Einstellungen nicht")
	check(GuideQuick.ids({ "shot": true, "video": true }, wahl) == ["video_stop", "guide"], "Video: Video beenden statt Ausschalten")
	check(Wahl.da("aufnahme", { "shot": true, "game": true, "aufnahme": true }) and not Wahl.da("aufnahme", { "shot": true, "game": true }),
			"Aufnehmen nur mit Uzais eigener Aufnahme")
	check(Wahl.da("guide", {}) and Wahl.da("beenden", {}) and Wahl.da("freunde", {}), "Guide, Beenden, Freunde immer")
	var alles := { "shot": true, "game": true, "video": true, "voice": true, "mic": true, "leistung": true, "pip": true, "musik": true, "ton": true,
		"aufnahme": true, "pads": true, "zimmer": true }
	for k in Wahl.KACHELN:
		var id := str(k[0])
		var immer := Wahl.da(id, {}) and Wahl.da(id, alles)
		check(immer == (Wahl.wann(id) == ""), "%s: Hinweis „wann“ genau dann, wenn nicht immer da" % id)


func _bearbeiten() -> void:
	print("Bearbeiten")
	var s := Wahl.stand(Wahl.STANDARD)
	check(Wahl.frei(s) == 0 and Wahl.verfuegbar(s).has("musik") and not Wahl.verfuegbar(s).has("shot"), "Standard: voll, „Musik“ lässt sich hinzufügen")
	check(Wahl.verschieben(["a", "b", "c"], 0, 1) == ["b", "a", "c"], "nach rechts")
	check(Wahl.verschieben(["a", "b", "c"], 2, -1) == ["a", "c", "b"], "nach links")
	check(Wahl.verschieben(["a", "b", "c"], 0, -1) == ["a", "b", "c"] and Wahl.verschieben(["a", "b", "c"], 2, 1) == ["a", "b", "c"], "am Rand bleibt sie")
	check(Wahl.verschieben(["a", "b"], 5, 1) == ["a", "b"], "falsche Stelle: nichts")
	var g := Wahl.umschalten(s, "guide")
	check(g == s and Wahl.ergebnis(g).has("guide"), "der Guide lässt sich nicht ausblenden")
	var a := Wahl.umschalten(s, "leistung")
	check((a.aus as Array) == ["leistung"] and not Wahl.ergebnis(a).has("leistung") and Wahl.frei(a) == 1, "ausblenden: fällt beim Speichern weg, Platz frei")
	check(Wahl.umschalten(a, "leistung").aus == [], "wieder einblenden")
	var b := Wahl.hinzufuegen(a, "musik")
	check(b.liste == ["shot", "clip", "mic", "pip", "rest", "beenden", "musik", "guide"] and b.aus == [],
			"hinzufügen vor den Guide; die ausgeblendete weicht (%s)" % str(b.liste))
	check(Wahl.hinzufuegen(b, "ton") == b, "voll: nichts")
	check(Wahl.umschalten(Wahl.umschalten(b, "shot"), "shot") == b, "ein und aus gibt den Stand zurück")
	var voll := Wahl.umschalten(b, "shot")
	voll = Wahl.hinzufuegen(voll, "ton")
	check(not (voll.liste as Array).has("shot") and (voll.liste as Array).has("ton") and Wahl.frei(voll) == 0,
			"voll mit Ausgeblendetem: die ausgeblendete macht Platz")
	check(Wahl.hinzufuegen(Wahl.stand(["musik"]), "musik").liste == ["musik", "guide"], "doppelt: nichts")
	check(Wahl.hinzufuegen(Wahl.stand(["musik"]), "quatsch").liste == ["musik", "guide"], "unbekannt: nichts")
	check(Wahl.hinzufuegen(Wahl.stand(["guide", "musik"]), "ton").liste == ["guide", "musik", "ton"], "Guide vorn: neue ans Ende")
	var orig := Wahl.stand(Wahl.STANDARD)
	Wahl.umschalten(orig, "shot")
	Wahl.hinzufuegen(orig, "musik")
	check(orig == Wahl.stand(Wahl.STANDARD), "der Stand selbst bleibt unverändert")
	# Ein Nutzer blendet alles aus: der Guide bleibt, und darüber Anpassen.
	var nur := Wahl.stand(Wahl.STANDARD)
	for id in Wahl.STANDARD:
		nur = Wahl.umschalten(nur, str(id))
	check(Wahl.ergebnis(nur) == ["guide"], "alles ausgeblendet: der Guide bleibt")
	check(GuideQuick.ids({}, Wahl.ergebnis(nur)) == ["guide"], "und steht im Schnellmenü")


func _speichern() -> void:
	print("Speichern")
	var keep: Variant = Config.get_value("system.quick_tiles", [])
	Wahl.speichern(Wahl.STANDARD)
	check(Config.get_value("system.quick_tiles", null) == [], "wie Standard: leer gespeichert (folgt späteren Standards)")
	check(GuideQuick.zusammenfassung() == "Standard", "Einstellungen: „Standard“")
	Wahl.speichern(["musik", "weiter", "guide"])
	check(Config.get_value("system.quick_tiles", null) == ["musik", "weiter", "guide"], "eigene Auswahl gespeichert")
	check(Wahl.auswahl() == ["musik", "weiter", "guide"], "und gelesen")
	check(GuideQuick.ids({}) == ["guide"] and GuideQuick.ids({ "musik": true }) == ["musik", "weiter", "guide"], "das Schnellmenü folgt ihr")
	Wahl.speichern(["shot", "shot", "unbekannt"])
	check(Config.get_value("system.quick_tiles", null) == ["shot", "guide"], "geprüft gespeichert")
	Config.set_value("system.quick_tiles", ["x", 3])
	check(Wahl.auswahl() == Wahl.STANDARD, "kaputter Wert in der Datei: Standard")
	Config.set_value("system.quick_tiles", keep)


func _quelle() -> void:
	print("Verdrahtung")
	var gq := Quelle.lesen("res://src/ui/components/guide_quick.gd")
	check(gq.contains("\"menu\":") and gq.contains("anpassen(g)") and gq.contains("\"qm:anpassen\""), "Menü-Taste und schmale Kachel: Anpassen")
	for k in Wahl.KACHELN:
		var id := str(k[0])
		check(gq.contains("\"%s\":" % id), "Kachel %s hat eine Handlung" % id)
	var gd := Quelle.lesen("res://src/ui/layers/guide.gd")
	check(gd.contains("GuideQuick.command(self, cmd)") and gd.contains("GuideQuick.nav_dir(self, dir)"), "Guide: B und Richtungen beim Anpassen")
	var sv := Quelle.lesen("res://src/ui/sections/settings_medien.gd")
	check(sv.contains("GuideQuick.oeffnen_zum_anpassen(main)"), "Einstellungen → Im Spiel: Kacheln im Schnellmenü")
