extends "res://tests/probe_base.gd"
## Fehler 29: Guide → dein Profil → Aufnahmen, dann B. Früher schloss B den ganzen Guide; jetzt
## liegt die Galerie über Guide und Panel, B führt zurück zum Panel. Ausgabe „GP ok/FAIL …“.

const MyProfile := preload("res://src/ui/layers/my_profile.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("GP %s %s" % ["ok  " if cond else "FAIL", what])


func _top() -> String:
	if Nav.layers.is_empty():
		return ""
	var s: Script = Nav.layers.back().get_script()
	return s.resource_path.get_file() if s else ""


func _pill(root: Node, key: String) -> Node:
	for c in root.find_children("*", "", true, false):
		if c.has_meta("uz_key") and str(c.get_meta("uz_key")) == key:
			return c
	return null


func run() -> void:
	main.toggle_guide()
	await wait(1.2)
	_ck(main._guide != null and is_instance_valid(main._guide), "Guide offen")
	var l = MyProfile.new()
	l.main = main
	l.guide = main._guide
	l.anchor = Rect2(1400, 120, 300, 80)
	main.open_layer(l)
	await wait(0.8)
	_ck(_top() == "my_profile.gd", "Panel „Dein Status“ offen (%s)" % _top())
	for key in ["me:aufnahmen", "me:abzeichen"]:
		var p := _pill(l, key)
		_ck(p != null, "Knopf %s da" % key)
		if p == null:
			continue
		p.emit_signal("pressed")
		await wait(1.0)
		_ck(_top() != "my_profile.gd" and _top() != "", "%s liegt oben (%s)" % [key, _top()])
		_ck(is_instance_valid(main._guide), "Guide bleibt offen unter %s" % key)
		await shot("01_" + key.get_slice(":", 1), 0.2)
		await press("b", 1, 0.6)
		await wait(0.6)
		_ck(_top() == "my_profile.gd", "B nach %s: zurück zum Panel (%s)" % [key, _top()])
		_ck(is_instance_valid(main._guide), "B nach %s: Guide noch offen" % key)
	print("GP Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
