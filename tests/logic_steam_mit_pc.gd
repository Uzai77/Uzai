extends Node
## Nicht-Steam-Spiel neben Steam am PC (steam_cm.gd status_mit_pc): Für die Dauer des Spiels meldet Uzai den Status,
## den Steam am PC schon zeigt – sonst sieht niemand das Spiel. Nie offline oder unsichtbar. Rein, ohne Netz und ohne
## Dateien. Aufruf: godot --headless --path . res://tests/logic_steam_mit_pc.tscn → „Ergebnis: alles ok“

const CM := preload("res://src/core/steam_cm.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	check(CM.status_mit_pc(true, false, 1, true, -1) == 1, "Spiel läuft, Steam am PC online: Uzai meldet „online“ mit")
	check(CM.status_mit_pc(true, false, 3, true, -1) == 3, "abwesend bleibt abwesend")
	check(CM.status_mit_pc(false, false, 1, true, -1) == 0, "kein Spiel: kein Status")
	check(CM.status_mit_pc(true, false, 1, false, -1) == 0, "Steam am PC zu: der alte Weg (needs_raise) gilt")
	check(CM.status_mit_pc(true, true, 1, true, -1) == 0, "Status der Sitzung steht schon: nichts doppelt")
	check(CM.status_mit_pc(true, false, 0, true, -1) == 0 and CM.status_mit_pc(true, false, -1, true, -1) == 0
			and CM.status_mit_pc(true, false, CM.PERSONA_INVISIBLE, true, -1) == 0,
			"offline, unbekannt oder unsichtbar: nie etwas melden")
	check(CM.status_mit_pc(true, false, 1, true, CM.PERSONA_OFFLINE) == 0 and CM.status_mit_pc(true, false, 1, true, CM.PERSONA_INVISIBLE) == 0,
			"im Guide offline oder unsichtbar gewählt: nichts")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)
