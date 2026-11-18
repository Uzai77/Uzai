extends "res://tests/probe_base.gd"
## Setup in English at 2560 × 1440 while display detection changes the UI size (rebuild with the
## setup open), step by step with A; focus and progress are printed. Environment UZAI_FE=pin: the
## pinned chat next to the Guide (screenshot with focus in the Guide and in the chat, X closes).
## Run: xvfb-run … -- --demo --no-boot --uzai-script=res://tests/probe_freund_extras.gd --uzai-out=<folder>

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const Lang := preload("res://src/core/lang.gd")


func run() -> void:
	if OS.get_environment("UZAI_FE") == "pin":
		await _pin()
	else:
		await _einrichtung()


func _wo() -> String:
	var top := Nav.top_layer()
	var f := Nav.focused()
	var step := ""
	if top and top.get_script() == Wizard:
		var steps: Array = top.get("_steps")
		var i := int(top.get("_idx"))
		step = str(steps[i]) if i >= 0 and i < steps.size() else "?"
	return "Schritt %s | Ebene %s | Fokus %s" % [step, top.get_script().resource_path.get_file() if top else "-",
			("in der Ebene" if top and top.is_ancestor_of(f) else "WEG") if f else "KEINER"]


func _einrichtung() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("system.language", "en")
	Lang.release()
	Lang.apply("en")
	UzTheme.rebuilt.emit()
	await wait(0.8)
	Wizard.open_for(main, true)
	await wait(1.2)
	print("FE vorher: ", _wo())
	# Wie die Bildschirmerkennung beim ersten Start (Monitor: 85 %), während die Einrichtung offen ist.
	Config.set_value("theme.ui_scale", 0.85)
	await wait(1.6)
	print("FE nach Neuaufbau: ", _wo())
	var last := ""
	var same := 0
	for i in 14:
		var w := _wo()
		if w == last:
			same += 1
		else:
			same = 0
		last = w
		print("FE %02d: %s" % [i, w])
		if same >= 2:
			print("FE steht: ", w)
			break
		var top := Nav.top_layer()
		var go: Variant = top.get("_default") if top and top.get_script() == Wizard else null
		if go is Control and is_instance_valid(go) and (go as Control).is_visible_in_tree():
			Nav.focus(go)
			await wait(0.1)
		await press("a")
		await wait(1.4)
	await shot("einrichtung_en_2560", 0.2)


func _pin() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games", "zuletzt")
	await wait(0.6)
	main.open_chat(Social.steam_friends[0])
	await wait(1.2)
	await press("b")
	await wait(0.6)
	main.toggle_guide()
	await wait(1.4)
	var g := Nav.top_layer()
	var pin: Variant = g.get("_pin") if g else null
	var im_guide: bool = g != null and g.is_ancestor_of(Nav.focused()) and not (pin as Control).is_ancestor_of(Nav.focused())
	print("FE Pin da: ", pin is Control and is_instance_valid(pin), " | Fokus im Guide: ", im_guide)
	await press("down")
	var row := Nav.focused()
	await press("right")
	await wait(0.4)
	print("FE Zeile verlassen: Fläche %s, Fokus dort: %s" % [row.get("_f"), row.has_focus()])
	print("FE rechts: Fokus im Chat: ", is_instance_valid(pin) and (pin as Control).is_ancestor_of(Nav.focused()), " (", Nav.focused().get_class(), ")")
	await shot("guide_chat_angeheftet", 0.5)
	await press("left")
	await wait(0.3)
	print("FE links: zurück im Guide: ", not (pin as Control).is_ancestor_of(Nav.focused()))
	await press("right")
	print("FE wieder rechts: Fokus im Chat: ", (pin as Control).is_ancestor_of(Nav.focused()))
	await press("x")
	await wait(0.6)
	print("FE X: Spalte weg: ", not is_instance_valid(pin) or not (pin as Control).is_inside_tree(), " | Fokus im Guide: ", g.is_ancestor_of(Nav.focused()))
	await press("b")
	await wait(0.6)
	main.toggle_guide()
	await wait(1.0)
	print("FE wieder auf: keine Spalte: ", Nav.top_layer().get("_pin") == null)
