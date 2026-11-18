extends Node
## Guide als Seitenleiste: Sitzungsuhr, schwacher Controller-Akku, Hinweise (B zuletzt, höchstens
## vier, je ein Wort), was fest im Start steht und unter „Mehr …“ nicht noch einmal, Tasten im
## Start und in Musik, keine Masken über clip_children in der Leiste (schimmerte über der
## Startseite durch). Aufruf: godot --headless --path . res://tests/logic_guidepanel.tscn

const Guide := preload("res://src/ui/layers/guide.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Sitzung")
	check(Guide.session_clock(0) == "0:00:00" and Guide.session_clock(760) == "0:12:40" and Guide.session_clock(3 * 3600 + 5) == "3:00:05",
			"Sitzung als Uhr (0:12:40)")
	print("Controller-Akku im Start nur, wenn er zählt")
	check(Guide.pad_low({ "pct": 20 }) and Guide.pad_low({ "pct": 5 }) and not Guide.pad_low({ "pct": 21 }), "bis 20 % schwach")
	check(Guide.pad_low({ "pct": -1, "level": 0 }) and not Guide.pad_low({ "pct": -1, "level": 1 }), "ohne Prozent: „fast leer“ zählt")
	check(not Guide.pad_low({ "pct": 10, "charging": true }) and not Guide.pad_low({ "pct": 10, "power": "wired" }), "lädt oder am Kabel: nicht schwach")
	print("Hinweise in der Leiste")
	var hb := HintBar.new()
	hb.inside = true
	var ordered: Array = hb._order([["a", "Auswählen"], ["b", "Schließen"], ["x", "Stumm"], ["y", "Mikro"]])
	check(str(ordered.back()[0]) == "b" and ordered.size() == 4, "B steht zuletzt")
	hb.inside = false
	check(str(hb._order([["a", ""], ["b", "Zurück"], ["x", "X"]])[1][0]) == "b", "die Leiste unten bleibt, wie sie war")
	hb.free()
	var vr := Quelle.lesen("res://src/ui/components/guide_voice_row.gd") + Quelle.lesen("res://src/ui/layers/guide.gd")
	check(not vr.contains("\"Für mich stumm\"") and vr.contains("\"Stumm\""), "Discord: X heißt kurz „Stumm“ (Zeile bricht nicht um)")
	print("Start und „Mehr …“ ohne Dopplung")
	for id in ["shot", "clip", "record", "filter", "overlay"]:
		check(GuideGame.FIXED.has(id), "„%s“ steht fest im Start, nicht unter „Mehr …“" % id)
	var acts := [{ "id": "shot", "prio": 10 }, { "id": "overlay", "prio": 0 }, { "id": "live", "prio": 12 }]
	check(GuideGame.start_extras(acts, []).is_empty(), "offenes Overlay hat eine feste Zeile: keine zweite")
	var gs := Quelle.lesen("res://src/ui/layers/guide.gd")
	check(gs.contains("if tab == \"spiel\" and _can_screenshot():") and gs.contains("main.take_screenshot()"), "X im Start: Bildschirmfoto direkt")
	check(gs.contains("if tab == \"musik\" and Music.mode() != \"aus\":\n\t\t\t\tMusic.next()"), "X in Musik: nächster Titel")
	check(gs.contains("\"spiel\": _tab_game()") and gs.contains("[\"freunde\", \"Freunde\"], [\"discord\", \"Discord\"]"),
			"Reiter: Start · Freunde · Discord · Musik · System")
	print("Leiste")
	for f in ["res://src/ui/layers/guide.gd", "res://src/ui/layers/guide_spiel.gd", "res://src/ui/layers/guide_musik.gd",
			"res://src/ui/layers/guide_basis.gd", "res://src/ui/components/guide_row.gd", "res://src/ui/components/guide_friend.gd",
			"res://src/ui/components/guide_voice_row.gd"]:
		var src := FileAccess.get_file_as_string(f)
		check(not src.contains("clip_children = "), "%s: keine Maske über clip_children" % f.get_file())
	check(gs.contains("tween_property(_panel, \"offset_left\", 0.0, U.T_ORT)") and is_equal_approx(preload("res://src/ui/u.gd").T_ORT, 0.2),
			"Leiste kommt in 200 ms (U.T_ORT) von links")
	check(GuideRow.H >= 48 and GuideRow.OUT > 0.0, "Zeilen hoch genug für den Fernseher, der Cursor ragt über die Zeile")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
