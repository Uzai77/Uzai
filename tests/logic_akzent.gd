extends Node
## Akzent: Graphit trägt den Akzent der Marke (Standard Markenviolett #A47BFF, bis 0.16 Lavendel, kein Gold). Die Stellen mit
## eigenem Goldton (Marke der Einstellungs-Gruppe, Licht hinter dem Guide, Licht der Erfolgs-Pop-ups)
## folgen dem Akzent und sind nur beim Gold-Akzent genau wie früher.
## Aufruf: godot --headless --path . res://tests/logic_akzent.tscn

const Aussehen := preload("res://src/core/aussehen.gd")
const Profiles := preload("res://src/core/profiles.gd")
const LAVENDEL := Color("#b8a6f0")
const VIOLETT := Color("#a47bff")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var keep := str(Config.get_value("theme.accent", ""))
	var keep_preset := str(Config.get_value("theme.preset", "theme"))
	Config.set_value("theme.preset", "theme")
	Config.set_value("theme.accent", "")
	print("Graphit (Marke)")
	check(UzTheme.col("accent") == VIOLETT, "Akzent ist das Markenviolett, kein Gold")
	check(UzTheme.col("mark") == VIOLETT and UzTheme.col("ambience") == VIOLETT, "Marke und Licht folgen dem Akzent")
	check(UzTheme.popup_palette().light == VIOLETT, "Licht der Pop-ups im Akzent")
	# Lesbar: Schrift auf dem Akzent und der Akzent auf Graphit 0/1/2.
	var auf := UzTheme.col("on_accent")
	check(_kontrast(auf, VIOLETT) >= 4.5, "Schrift auf dem Akzent lesbar (%.1f : 1)" % _kontrast(auf, VIOLETT))
	for f in ["bg", "surface", "surface_hi"]:
		check(_kontrast(VIOLETT, UzTheme.col(f)) >= 4.5, "Akzent auf %s lesbar (%.1f : 1)" % [f, _kontrast(VIOLETT, UzTheme.col(f))])
	check(_kontrast(UzTheme.col("focus"), VIOLETT) >= 1.8 and _kontrast(UzTheme.col("focus"), UzTheme.col("bg")) >= 7.0, "Fokus (hell) hebt sich vom Akzent und vom Raum ab")
	print("Anderer Akzent")
	Config.set_value("theme.accent", "#8fd0e3")
	var acc := Color("#8fd0e3")
	check(UzTheme.col("accent") == acc, "Akzent übernommen")
	check(UzTheme.col("mark") == acc and UzTheme.col("ambience") == acc, "Marke und Licht folgen dem Akzent")
	check(UzTheme.popup_palette().light == acc, "Licht der Pop-ups folgt dem Akzent")
	check(UzTheme.grund.popup.light == VIOLETT, "die Grundwerte selbst bleiben unverändert")
	check(UzTheme.col("gold") == Color("#e8c15a"), "„gold“ für Abgeschlossenes bleibt (eigene Bedeutung)")
	print("Früherer Standard von Hand gewählt: bleibt")
	Config.set_value("theme.accent", "#b8a6f0")
	check(UzTheme.col("accent") == LAVENDEL, "gespeichertes Lavendel bleibt (eigene Wahl, kein Überschreiben)")
	Config.set_value("theme.accent", "#d6d9e4")
	check(UzTheme.col("accent") == Color("#d6d9e4"), "gespeichertes Perlgrau bleibt (eigene Wahl)")
	print("Gold von Hand gewählt")
	Config.set_value("theme.accent", "#E7C27D")
	check(UzTheme.col("mark") == Color("#e8c15a"), "Marke der Gruppe: bisheriger Goldton")
	check(UzTheme.col("mark") == UzTheme.col("gold"), "… derselbe wie „gold“ (pixelgleich)")
	check(UzTheme.col("ambience") == Color(0.85, 0.7, 0.45), "Licht hinter dem Guide: bisheriger Ton")
	check(UzTheme.col("accent") == Color("#e7c27d"), "gespeichertes Gold bleibt (eigene Wahl)")
	print("Neue Profile und Grundwerte")
	check(Profiles.make_profile("Neu", []).color == "lavendel" and Profiles.COLORS[0][2] == LAVENDEL, "neues Profil: Lavendel")
	check(Profiles.clean_profile({ "id": "aaaaaaaa11", "name": "Alt", "color": "gold" }).color == "gold", "vorhandenes Profil in Gold bleibt Gold")
	check(Aussehen.werte().colors.accent == VIOLETT and Aussehen.werte().popup.light == VIOLETT, "Grundwerte des Aussehens: Markenviolett")
	Config.set_value("theme.accent", keep)
	Config.set_value("theme.preset", keep_preset)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Kontrast nach WCAG (relative Leuchtdichte).
static func _kontrast(a: Color, b: Color) -> float:
	var la := _leucht(a)
	var lb := _leucht(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _leucht(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
