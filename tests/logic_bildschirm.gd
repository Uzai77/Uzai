extends Node
## Uzai stellt sich selbst ein (Punkt 96): Fernseher, Monitor oder Laptop aus Name, Anschluss und
## Bildgröße, passende Größe der Oberfläche, Bildrate im Menü, Kurztext, nichts aus Unklarem.
## Aufruf: godot --headless --path . res://tests/logic_bildschirm.tscn

const DisplayFit := preload("res://src/core/display_fit.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Größe")
	check(roundi(DisplayFit.inches(121.8, 68.5)) == 55, "121,8 × 68,5 cm sind 55 Zoll")
	check(DisplayFit.inches(16, 9) == 0.0 and DisplayFit.inches(0, 0) == 0.0, "nur Seitenverhältnis oder nichts: keine Größe")
	print("Art")
	var cases := [
		[{ "tech": "intern", "w_cm": 34, "h_cm": 19 }, "laptop", "eingebauter Bildschirm"],
		[{ "name": "LG TV SSCR2", "tech": "hdmi" }, "tv", "„LG TV …“"],
		[{ "name": "SONY TV  *00" }, "tv", "„SONY TV“"],
		[{ "name": "Panasonic-TV" }, "tv", "„Panasonic-TV“"],
		[{ "name": "Philips FTV" }, "tv", "„Philips FTV“"],
		[{ "name": "SAMSUNG", "w_cm": 16, "h_cm": 9 }, "tv", "nur der Markenname, Größe unbrauchbar"],
		[{ "name": "SAMSUNG", "w_cm": 60, "h_cm": 34 }, "monitor", "Markenname mit 27 Zoll: Monitor"],
		[{ "name": "DELL U2723QE", "w_cm": 60, "h_cm": 34, "tech": "dp" }, "monitor", "Monitor mit Modellname"],
		[{ "name": "ATVISION X1", "w_cm": 53, "h_cm": 30 }, "monitor", "„tv“ mitten im Wort zählt nicht"],
		[{ "name": "Unbekannt", "w_cm": 121, "h_cm": 68 }, "tv", "ab 40 Zoll: Fernseher"],
		[{ "name": "LG ULTRAGEAR", "w_cm": 0, "h_cm": 0 }, "", "keine Größe, kein Hinweis: unklar"],
		[{ "hz": 60.0 }, "", "ohne Helfer: unklar"],
	]
	for c in cases:
		check(DisplayFit.kind_of(c[0]) == c[1], "%s → %s" % [c[2], c[1] if c[1] != "" else "unklar"])
	print("Oberfläche")
	check(DisplayFit.scale_for("tv", 55.0) == 1.0 and DisplayFit.scale_for("tv", 0.0) == 1.0, "Fernseher: 100 %")
	check(DisplayFit.scale_for("tv", 32.0) == 1.1, "kleiner Fernseher: größer")
	check(DisplayFit.scale_for("monitor", 27.0) == 0.85 and DisplayFit.scale_for("monitor", 34.0) == 0.9, "Monitor: kleiner, großer Monitor etwas weniger")
	check(DisplayFit.scale_for("laptop", 14.0) == 0.9 and DisplayFit.scale_for("", 0.0) == 1.0, "Laptop; unklar bleibt Standard")
	for v in DisplayFit.SCALE.values():
		check(float(v) >= 0.8 and float(v) <= 1.5, "%d %% liegt im Bereich des Reglers" % roundi(float(v) * 100.0))
	print("Bildrate im Menü")
	check(DisplayFit.menu_fps(60.0, "auto") == 0 and DisplayFit.menu_fps(144.0, "auto") == 0, "bis 144 Hz: alle Bilder")
	check(DisplayFit.menu_fps(240.0, "auto") == 120 and DisplayFit.menu_fps(360.0, "auto") == 180, "240/360 Hz: halbe Rate")
	check(DisplayFit.menu_fps(165.0, "auto") == 0, "165 Hz: halbe Rate wäre unter 100, also alle")
	check(DisplayFit.menu_fps(240.0, "voll") == 0 and DisplayFit.menu_fps(0.0, "auto") == 0, "„Volle Rate“ und unbekannte Hz: keine Grenze")
	print("Text und Helfer")
	check(DisplayFit.summary({ "name": "LG TV", "w_cm": 121, "h_cm": 68, "hz": 119.88, "hdr": "an" }) == "Fernseher  ·  55″  ·  120 Hz  ·  HDR an", "Kurztext")
	check(DisplayFit.summary({ "hz": 60.0, "hdr": "moeglich" }) == "60 Hz  ·  HDR möglich (in Windows aus)", "ohne Art nur, was bekannt ist")
	check(DisplayFit.summary({}) == "", "nichts erkannt: leer")
	check(DisplayFit.summary({ "name": "LG TV", "w_cm": 121, "h_cm": 68, "hz": 120.0 }, true) == "Fernseher  ·  55″", "kurz: Art und Größe")
	var c2 := DisplayFit.clean({ "name": "x".repeat(200), "tech": "rm -rf", "w_cm": 99999, "h_cm": -5, "hdr": "vielleicht" })
	check(str(c2.name).length() == 64 and c2.tech == "" and c2.w_cm == 1000 and c2.h_cm == 0 and c2.hdr == "", "Antwort des Helfers begrenzt")
	print("Einstellen")
	Config.set_value("theme.ui_scale", 1.0)
	check(DisplayFit.apply({ "name": "DELL U2723QE", "w_cm": 60, "h_cm": 34 }, true) == "monitor"
			and is_equal_approx(float(Config.get_value("theme.ui_scale")), 0.85), "erster Start: Standard wird Startwert")
	check(is_equal_approx(get_tree().root.content_scale_factor, 0.85), "sofort sichtbar, ohne Neuaufbau")
	Config.set_value("theme.ui_scale", 1.2)
	DisplayFit.apply({ "name": "LG TV" }, true)
	check(is_equal_approx(float(Config.get_value("theme.ui_scale")), 1.2), "erster Start: eigene Wahl bleibt")
	DisplayFit.apply({ "name": "LG TV" }, false)
	check(is_equal_approx(float(Config.get_value("theme.ui_scale")), 1.0) and str(Config.get_value("display.seen", {}).get("name", "")) == "LG TV",
			"auf Wunsch: gesetzt und gemerkt")
	Config.set_value("theme.ui_scale", 1.0)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
