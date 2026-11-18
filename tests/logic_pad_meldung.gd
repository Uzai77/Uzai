extends Node
## „Controller verbunden“ (Nutzertest: „Man braucht beim Start nicht immer zu sehen, dass der
## Controller an ist“): nie beim Start oder Aufwachen, nie für einen Controller, der in dieser
## Sitzung schon da war – nur ein neuer während der Benutzung.
## Aufruf: godot --headless --path . res://tests/logic_pad_meldung.tscn

const NavS := preload("res://src/core/nav.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var s := NavS.PAD_TOAST_START_MS
	var w := NavS.PAD_TOAST_WAKE_MS
	var nie := -w
	check(not NavS.pad_toast_due(800, nie, false), "beim Start (nach 0,8 s): keine Meldung")
	check(not NavS.pad_toast_due(s - 1, nie, false), "kurz vor Ende der Startzeit: keine Meldung")
	check(NavS.pad_toast_due(s + 60000, nie, false), "neuer Controller mitten in der Benutzung: Meldung")
	check(not NavS.pad_toast_due(s + 60000, nie, true), "derselbe Controller wieder an (schon da gewesen): keine Meldung")
	check(not NavS.pad_toast_due(600000, 600000 - 2000, false), "2 s nach dem Aufwachen: keine Meldung")
	check(not NavS.pad_toast_due(600000, 600000 - w + 1, false), "kurz vor Ende der Aufwachzeit: keine Meldung")
	check(NavS.pad_toast_due(600000, 600000 - w - 1, false), "lange nach dem Aufwachen ein neuer: Meldung")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit()
