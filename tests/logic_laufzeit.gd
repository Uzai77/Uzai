extends Node
## Laufzeit-Fehler aus der Prüfung vor der Veröffentlichung (audit RR-14..RR-18), am Quelltext festgehalten: Die
## Wege brauchen den Helfer, ein laufendes Spiel oder mpv und lassen sich headless nicht nachspielen.
## Aufruf: godot --headless --path . res://tests/logic_laufzeit.tscn

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _body(datei: String, fn: String) -> String:
	var s := FileAccess.get_file_as_string(datei)
	var a := s.find("func %s(" % fn)
	if a < 0:
		return ""
	var b := s.find("\nfunc ", a + 5)
	return s.substr(a, (b - a) if b > 0 else -1)


func _ready() -> void:
	print("Spiel aus einem Laden: Helfer ohne Antwort heißt „läuft“")
	var poll := _body("res://src/core/launcher.gd", "_spiel_weg")
	var i := poll.find("\"epic\", \"ea\", \"gog\"")
	var laden := poll.substr(i, poll.find("\n\t\t_:", i) - i)
	check(laden.find("if not r.ok:") > 0 and laden.find("if not r.ok:") < laden.find("_gone += 1"), "find-process ohne Antwort zählt nicht als beendet")
	var steam := poll.substr(poll.find("\"steam\":"), 900)
	check(steam.contains("not _steam_seen and running >= 0"), "Steam: 3-Minuten-Grenze nur mit Antwort des Helfers")

	print("mpv endet mit Uzai")
	var v := FileAccess.get_file_as_string("res://src/core/video.gd")
	var ex := _body("res://src/core/video.gd", "_exit_tree")
	check(ex.contains("OS.kill") and ex.contains("_pid_endet"), "Video._exit_tree beendet laufendes und gerade endendes mpv")
	check(_body("res://src/core/video.gd", "stop").contains("_pid_endet = pid"), "stop() merkt das endende mpv")
	check(v.count("func _exit_tree(") == 1, "genau ein _exit_tree")

	print("Controller nach einem Spiel im Zimmer-Fernseher")
	var ende := _body("res://src/main.gd", "_on_game_ended")
	var z := ende.find("if _overlay_pad_forced:")
	check(z > 0 and ende.find("Nav.pad_unfocused = false", z) > z and z < ende.find("_overlay_mode = false"), "Controller-Zwang wird zurückgesetzt")

	print("Einlesen ohne Netz")
	var lib := _body("res://src/library/library.gd", "_einlesen")
	var o := lib.find("owned.is_empty() and mit_gekauften")
	check(o > 0 and lib.find("bleibt.append(\"steam\")", o) > o and lib.find("bleibt.append(\"steam\")", o) < lib.find("_merge_owned(found, owned", o),
		"leere Liste der gekauften Spiele: Steam-Einträge bleiben")

	print("Guide öffnet nur einmal")
	var tg := _body("res://src/main_guide.gd", "toggle_guide")
	var ow := _body("res://src/main_guide.gd", "_overlay_spiel_warten")
	var k := ow.find("await _overlay_spiel_bereit()")
	check(tg.contains("await _overlay_spiel_warten(grund)") and k > 0 and ow.rfind("_guide_opening = true", k) > ow.rfind("_guide_opening = false", k),
		"Overlay-Prüfung läuft mit _guide_opening")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
