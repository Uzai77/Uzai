extends Node
## Ein Druck, ein Klang auch bei schweren Ebenen (Plan „Gefühl 2“, R12): Nav.activate spielt den
## Klang des Drucks nach der Handlung. Öffnet sie nach 100 ms Aufbau eine Ebene („open“), bleibt
## „select“ still; spielt sie selbst nichts, klingt „select“; spielt sie einen eigenen Klang
## (Schalter), bleibt der stehen. Dazu: „Fertig“ der Einrichtung und Aufwachen ohne „launch“/„guide“.
## Aufruf: godot --headless --path . res://tests/logic_klang_druck.tscn

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


class _Knopf extends Control:
	var dauer_ms := 0
	var klang := ""

	func activate() -> void:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < dauer_ms:
			pass
		if klang != "":
			Sfx.play(klang)


func _namen_seit(n0: int) -> Array:
	var out: Array = []
	var r: Array = Sfx._recent
	for i in range(n0, r.size()):
		out.append(str(r[i][2]))
	return out


func _druck(dauer_ms: int, klang: String) -> Array:
	# Abstand zum vorigen Druck: sonst zählte er als derselbe.
	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var k := _Knopf.new()
	k.dauer_ms = dauer_ms
	k.klang = klang
	k.focus_mode = Control.FOCUS_ALL
	add_child(k)
	Sfx._recent.clear()
	Nav.activate(k)
	var namen := _namen_seit(0)
	k.queue_free()
	return namen


func _ready() -> void:
	Config.set_value("theme.sounds", true)
	var a: Array = await _druck(100, "open")
	check(a == ["open"], "schwere Ebene (100 ms Aufbau, dann „open“): nur „open“, kein „select“ davor (%s)" % str(a))
	var b: Array = await _druck(0, "")
	check(b == ["select"], "ohne eigenen Klang: „select“ (%s)" % str(b))
	var c: Array = await _druck(0, "toggle_on")
	check(c == ["toggle_on"], "Schalter klingt selbst: „select“ bleibt still (%s)" % str(c))
	var d: Array = await _druck(30, "launch")
	check(d == ["launch"], "Spielstart: nur „launch“ (%s)" % str(d))
	# Klang-Bedeutung an den Aufrufstellen (Quelltext: welcher Klang wo).
	var wiz := FileAccess.get_file_as_string("res://src/ui/layers/setup_wizard_bausteine.gd")
	check(wiz.contains("Sfx.play(\"boot\")") and not wiz.contains("Sfx.play(\"launch\")"), "Einrichtung „Fertig“: Start-Signatur „boot“, kein „launch“")
	var rest := FileAccess.get_file_as_string("res://src/core/rest.gd")
	check(not rest.contains("Sfx.play(\"guide\")") and not rest.contains("Sfx.play(\"guide_close\")"), "Ruhemodus: kein Guide-Klang ohne Guide")
	check(not rest.contains("Toasts.show_toast(\"Willkommen zurück\", title"), "Aufwachen ohne „Willkommen zurück“")
	var zim := FileAccess.get_file_as_string("res://src/room/zimmer_ansehen.gd")
	check(not zim.contains("Sfx.play(\"launch\")"), "Zimmer: „launch“ nur beim echten Spielstart")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
