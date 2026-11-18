extends Node
## D-pad in the settings: left/right always moves between the columns, so left never changes a value
## instead of going back – right into the rows, left back to the category, out of a sub-page and back
## out of the search. A changes values: toggles flip, a choice with two values switches, one with more
## opens the choice list, a slider is adjusted after A (left/right), and A or B ends that. LB/RB page
## through as before.
## Run: UZAI_DATA=<empty> godot --headless --path . res://tests/logic_einstellungen_steuerkreuz.tscn

const ChoiceList := preload("res://src/ui/layers/choice_list.gd")
const SheetS := preload("res://src/ui/layers/sheet.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")

var fails := 0
var main: Node
var s: Node


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	Library.load_demo()
	Config.set_value("theme.boot", "aus")
	await get_tree().process_frame
	main = load("res://src/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _warte(1.2)
	s = main.sections.get("settings")
	await _spalten()
	await _schalter_und_auswahl()
	await _regler()
	await _unterseite()
	await _suche()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _in_kats(c: Control) -> bool:
	var k: Variant = s.get("_cats_box")
	return c != null and k is Control and (k as Control).is_ancestor_of(c)


func _in_liste(c: Control) -> bool:
	var l: Variant = s.get("_list")
	return c != null and l is Control and (l as Control).is_ancestor_of(c)


## Erste Zeile einer Art in der Mitte, die keinen theme.*-Schlüssel ändert (die bauen alles neu;
## ruhig sind nur die, die gleich wirken: Musik, Licht, Abdunklung).
const RUHIG := ["theme.music", "theme.aurora", "theme.dim", "theme.sound_volume"]


func _zeile(art: String, mehr_als_zwei := -1) -> Control:
	for r in Nav.focusables(s.get("_list")):
		var pfad := str(r.get_meta("uz_path", ""))
		# Sprache und Theme bauen die ganze Oberfläche neu: nicht zum Probieren.
		if r.get("kind") != art or (pfad.begins_with("theme.") and not pfad in RUHIG) or pfad.contains("lang"):
			continue
		if mehr_als_zwei >= 0 and ((r.get("options") as Array).size() > 2) != (mehr_als_zwei == 1):
			continue
		return r
	return null


func _kategorie(cid: String) -> void:
	main.goto("settings", cid)
	await _warte(0.5)
	s = main.sections.get("settings")


func _spalten() -> void:
	print("Spalten: rechts hinein, links zurück")
	await _kategorie("klang")
	Nav.focus(Nav.default_in(s.get("_cats_box")), true)
	for it in (s.get("_cats_box") as Control).get_children():
		if "cid" in it and str(it.cid) == "klang":
			Nav.focus(it, true)
	Nav.move("right")
	await _warte(0.1)
	check(_in_liste(Nav.focused()), "rechts aus der Kategorie: in die Zeilen")
	var t := _zeile("toggle")
	for cid in ["mitteilungen", "medien", "aufnahmen", "system"]:
		if t != null:
			break
		await _kategorie(cid)
		t = _zeile("toggle")
	check(t != null and bool(t.get("nur_a")), "Zeilen der Einstellungen ändern Werte nur mit A")
	if t == null:
		return
	Nav.focus(t, true)
	var v: bool = bool(t.get("value"))
	Nav.move("left")
	await _warte(0.1)
	check(_in_kats(Nav.focused()) and bool(t.get("value")) == v, "links auf einem Schalter: zurück zur Kategorie, Wert bleibt")
	check("cid" in Nav.focused() and str(Nav.focused().cid) == str(s.sub), "zurück auf die gewählte Kategorie")
	var kat := str(s.sub)
	Nav.focus(t, true)
	Nav.move("right")
	check(Nav.focused() == t and bool(t.get("value")) == v, "rechts auf einem Schalter: Anstoß, Wert bleibt")
	Nav._fire("lb")
	await _warte(0.5)
	check(str(s.sub) != kat, "LB blättert die Kategorie wie bisher (%s → %s)" % [kat, str(s.sub)])


func _schalter_und_auswahl() -> void:
	print("A ändert Werte")
	for cid in ["klang", "spiele", "controller", "imspiel", "mitteilungen", "system", "aufnahmen", "medien"]:
		await _kategorie(cid)
		var t := _zeile("toggle")
		if t:
			Nav.focus(t, true)
			var v: bool = bool(t.get("value"))
			Nav._fire("a")
			check(bool(t.get("value")) != v, "A kippt den Schalter „%s“" % str(t.get("title")))
			Nav._fire("a")
			break
	var zwei_ok := false
	var viele_ok := false
	for cid in ["klang", "spiele", "controller", "imspiel", "aufnahmen", "medien", "mitteilungen", "system", "emulation"]:
		await _kategorie(cid)
		if not zwei_ok:
			var zwei := _zeile("choice", 0)
			if zwei:
				zwei_ok = true
				Nav.focus(zwei, true)
				var v0: Variant = zwei.get("value")
				Nav._fire("a")
				check(zwei.get("value") != v0 and Nav.top_layer() == null, "Auswahl mit zwei Werten: A wechselt („%s“)" % str(zwei.get("title")))
				Nav._fire("a")
				await _warte(0.2)
		if not viele_ok:
			var viele := _zeile("choice", 1)
			if viele:
				viele_ok = true
				Nav.focus(viele, true)
				var v1: Variant = viele.get("value")
				Nav.move("left")
				check(_in_kats(Nav.focused()) and viele.get("value") == v1, "Auswahl: links geht zurück, kein Wechsel")
				Nav.focus(viele, true)
				Nav._fire("a")
				await _warte(0.5)
				var cl := Nav.top_layer()
				check(cl is ChoiceList, "Auswahl mit mehr Werten: A öffnet die Auswahlliste („%s“)" % str(viele.get("title")))
				if cl is ChoiceList:
					var anders: Variant = null
					for o in viele.get("options"):
						if o[0] != v1:
							anders = o[0]
							break
					var pfad := str(viele.get_meta("uz_path"))
					(cl as ChoiceList).picked.emit(anders)
					check(Config.get_value(pfad) == anders and (not is_instance_valid(viele) or viele.get("value") == anders),
							"gewählter Wert gilt und steht in der Zeile")
					cl.close()
					await _warte(0.4)
					Config.set_value(pfad, v1)
		if zwei_ok and viele_ok:
			break
	check(zwei_ok and viele_ok, "beide Arten von Auswahl gefunden")


func _regler() -> void:
	print("Regler: A stellt ein, A oder B beendet")
	var r: Control = null
	for cid in ["klang", "controller", "aussehen", "imspiel", "aufnahmen", "medien", "system"]:
		await _kategorie(cid)
		r = _zeile("slider")
		if r:
			break
	check(r != null, "Regler gefunden")
	if r == null:
		return
	Nav.focus(r, true)
	var v := float(r.get("value"))
	Nav.move("right")
	check(is_equal_approx(float(r.get("value")), v), "rechts ohne Einstellen: Wert bleibt")
	Nav.move("left")
	check(_in_kats(Nav.focused()) and is_equal_approx(float(r.get("value")), v), "links ohne Einstellen: zurück zur Kategorie")
	Nav.focus(r, true)
	Nav._fire("a")
	check(bool(r.get("_stellen")), "A beginnt das Einstellen")
	var hints := HintBar.collect()
	check(hints.has(["lr", "Ändern"]) and hints.has(["a", "Fertig"]) and hints.has(["b", "Fertig"]), "Hinweise: links/rechts „Ändern“, A und B „Fertig“")
	Nav.move("left")
	check(Nav.focused() == r and float(r.get("value")) < v, "beim Einstellen: links verringert, der Cursor bleibt")
	Nav.move("right")
	check(is_equal_approx(float(r.get("value")), v), "rechts erhöht wieder")
	Nav._fire("b")
	check(not bool(r.get("_stellen")) and Nav.focused() == r, "B beendet das Einstellen und bleibt auf der Zeile")
	Nav._fire("a")
	Nav._fire("a")
	check(not bool(r.get("_stellen")), "A beendet das Einstellen ebenso")
	Nav._fire("a")
	Nav.move("down")
	await _warte(0.1)
	check(not bool(r.get("_stellen")) and Nav.focused() != r, "runter verlässt die Zeile, das Einstellen endet")


func _unterseite() -> void:
	print("Unterseite: links geht hinaus")
	for cid in ["aussehen", "klang", "controller", "system"]:
		await _kategorie(cid)
		var mehr: Control = null
		for r in Nav.focusables(s.get("_list")):
			if str(r.get_meta("uz_key", "")).begins_with("more:"):
				mehr = r
				break
		if mehr == null:
			continue
		Nav.focus(mehr, true)
		Nav._fire("a")
		await _warte(0.5)
		var sh := Nav.top_layer()
		check(sh is SheetS, "A öffnet die Unterseite „%s“" % str(mehr.get("title")))
		if not (sh is SheetS):
			return
		var z: Control = null
		for c in Nav.focusables(sh):
			if c.get("nur_a") == true and c.get("kind") in ["toggle", "choice", "slider"]:
				z = c
				break
		if z == null:
			z = Nav.default_in(sh)
		Nav.focus(z, true)
		var v: Variant = z.get("value") if "value" in z else null
		Nav.move("right")
		check(Nav.top_layer() == sh and (v == null or z.get("value") == v), "rechts in der Unterseite: nichts ändert sich")
		Nav.move("left")
		await _warte(0.5)
		check(Nav.top_layer() == null and (v == null or not is_instance_valid(z) or z.get("value") == v), "links: aus der Unterseite hinaus, Wert bleibt")
		check(Nav.focused() != null and str(Nav.focused().get_meta("uz_key", "")) == str(mehr.get_meta("uz_key", "")), "Cursor wieder auf „%s“" % str(mehr.get("title")))
		return
	check(false, "eine Unterseite gefunden")


func _suche() -> void:
	print("Suche: links zurück")
	await _kategorie("suche")
	var r: Control = Nav.default_in(s.get("_list"))
	check(r != null, "Häufiges in der Suche")
	if r == null:
		return
	Nav.focus(r, true)
	Nav.move("left")
	await _warte(0.1)
	check(_in_kats(Nav.focused()), "links aus der Suche: zurück in die Liste links")


func _warte(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
