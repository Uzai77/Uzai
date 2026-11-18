extends "res://tests/probe_base.gd"
## Quellen der Startseite ordnen (langes A): Menü, Verschieben mit links/rechts, kurzes A wie
## bisher, Ausblenden und zurückholen, ausgeblendete Spiele zurückholen. Ausgabe „QU ok/FAIL …“.

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("QU %s %s" % ["ok  " if cond else "FAIL", what])


func _chips() -> Array:
	var out: Array = []
	for c in main.chips_box.get_children():
		var k := str(c.get_meta("uz_key", ""))
		if k.begins_with("chip:"):
			out.append(k.substr(5))
	return out


func _chip(id: String) -> Control:
	for c in main.chips_box.get_children():
		if str(c.get_meta("uz_key", "")) == "chip:" + id:
			return c
	return null


## A gedrückt halten (wie am Controller) bzw. kurz drücken.
func _a(hold: bool) -> void:
	Input.action_press("uz_a")
	Nav._fire("a")
	await wait(0.7 if hold else 0.08)
	Input.action_release("uz_a")
	await wait(0.6)


func _pick(text: String) -> bool:
	var l := Nav.top_layer()
	if l == null:
		return false
	for c in l.find_children("*", "", true, false):
		if c is Control and str(c.get("title")) == text and (c as Control).focus_mode != Control.FOCUS_NONE:
			Nav.focus(c, true)
			await wait(0.3)
			await press("a", 1, 0.8)
			return true
	return false


func _titles() -> Array:
	var out: Array = []
	var l := Nav.top_layer()
	if l:
		for c in l.find_children("*", "", true, false):
			if c is Control and c.get("title") is String and (c as Control).focus_mode != Control.FOCUS_NONE:
				out.append(str(c.get("title")))
	return out


func run() -> void:
	var before := _chips()
	print("QU Quellen: %s" % str(before))
	var first: String = before[2]          # z. B. PS2
	# Kurzes A: wie bisher alle Spiele der Quelle.
	Nav.focus(_chip(first), true)
	await wait(0.6)
	await _a(false)
	_ck(Nav.top_layer() != null and Nav.top_layer().get("sub_id") == first, "kurzes A: alle Spiele der Quelle")
	await press("b", 1, 1.0)
	# Langes A: Menü.
	Nav.focus(_chip(first), true)
	await wait(0.4)
	await _a(true)
	var t := _titles()
	_ck(t.has("Verschieben") and t.has("Ausblenden"), "langes A: Menü %s" % str(t))
	await shot("q1_menue", 0.3)
	await _pick("Verschieben")
	await wait(0.4)
	_ck(Nav.top_layer() != null and Nav.top_layer().has_method("nav_dir"), "Verschieben: Rahmen um die Quelle")
	await shot("q2_verschieben", 0.2)
	await press("left", 1, 0.06)
	await shot("q3_gleitet", 0.0)
	await wait(0.5)
	await press("left", 1, 0.6)
	await shot("q4_vorn", 0.1)
	var now := _chips()
	_ck(now.find(first) == 0 and now.size() == before.size(), "zweimal links: vorn (%s)" % str(now.slice(0, 4)))
	await press("a", 1, 0.6)
	_ck(Nav.top_layer() == null and Nav.focused() == _chip(first), "A: fertig, Quelle bleibt gewählt")
	main._rebuild()
	await wait(1.2)
	_ck(_chips().find(first) == 0, "Reihenfolge gemerkt (nach Neuaufbau)")

	# Ausblenden und zurückholen.
	var victim: String = _chips()[3]
	Nav.focus(_chip(victim), true)
	await wait(0.4)
	await _a(true)
	await _pick("Ausblenden")
	await wait(0.8)
	_ck(not _chips().has(victim), "„%s“ ausgeblendet" % victim)
	await shot("q5_ausgeblendet", 0.2)
	Nav.focus(_chip(first), true)
	await wait(0.4)
	await _a(true)
	t = _titles()
	_ck(t.has("Ausgeblendete Quellen (1)"), "Menü: Ausgeblendete Quellen (1)")
	await _pick("Ausgeblendete Quellen (1)")
	await wait(0.6)
	await shot("q6_zurueckholen", 0.2)
	_ck(_titles().size() == 1, "Liste mit der ausgeblendeten Quelle")
	var lab: String = _titles()[0] if not _titles().is_empty() else ""
	await _pick(lab)
	await wait(0.8)
	_ck(_chips().has(victim), "„%s“ wieder da" % victim)

	# Ausgeblendete Spiele zurückholen.
	var g: Dictionary = main.sections["games"].games_for("zuletzt")[1]
	var gid := str(g.id)
	Library.set_field(gid, "hidden", true)
	await wait(1.0)
	_ck(not Library.visible_games().any(func(x): return str(x.id) == gid), "Spiel ausgeblendet")
	Nav.focus(_chip(first), true)
	await wait(0.4)
	await _a(true)
	_ck(_titles().has("Ausgeblendete Spiele (1)"), "Menü: Ausgeblendete Spiele (1)")
	await _pick("Ausgeblendete Spiele (1)")
	await wait(1.2)
	var grid := Nav.top_layer()
	_ck(grid != null and grid.get("sub_id") == "ausgeblendet", "Raster „Ausgeblendete Spiele“")
	await shot("q7_ausgeblendete_spiele", 0.3)
	# Dort: Optionen → Ausblenden aus.
	main.open_game_options(Library.get_game(gid))
	await wait(1.0)
	await _pick("Ausblenden")
	await wait(0.6)
	_ck(Library.visible_games().any(func(x): return str(x.id) == gid), "Optionen → Ausblenden aus: Spiel wieder da")
	await press("b", 1, 0.8)
	await press("b", 1, 1.0)
	print("QU Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
