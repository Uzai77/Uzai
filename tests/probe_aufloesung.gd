extends "res://tests/probe_base.gd"
## Probe „Alle Auflösungen“ (Punkt 63): die wichtigsten Bildschirme fotografieren und prüfen, ob
## etwas aus dem Fenster ragt. Aufruf je Auflösung (Demo, eigener Datenordner):
##   xvfb-run -s "-screen 0 2560x1080x24" <godot> --path . --resolution 2560x1080 -- --demo --no-boot \
##     --uzai-script=res://tests/probe_aufloesung.gd --uzai-out=<ordner>
## Rollende Reihen und Listen (ScrollContainer, zuschneidende Flächen) dürfen über den Rand laufen;
## gemeldet wird nur, was sichtbar abgeschnitten wäre. Am Ende: „Überlauf gesamt: N“.
## Größe der Oberfläche: --uzai-scale=1.5 stellt sie nach dem Start um (wie der Regler, samt
## Neuaufbau). 120/135/150 % auf 1280 × 720, 1920 × 1080 und 3840 × 2160 ergeben jeweils
## 1600 × 900, 1422 × 800 und 1280 × 720 logische Pixel. Zusätzlich geprüft: Das Cover-Regal
## steht über der Tastenleiste, nicht darauf.

var _found := 0
var _seen := {}


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-scale="):
			Config.set_value("theme.ui_scale", float(a.substr(13)))
			await wait(UzTheme.LAYOUT_DELAY + 1.5)
	var vs := get_viewport().get_visible_rect().size
	print("Fenster logisch: %s, Größe der Oberfläche %s" % [vs, str(UzTheme.ui_scale())])
	main.goto("games", "zuletzt")
	await look("01_startseite", 2.0)
	main.goto("media")
	await look("02_medien", 1.5)
	main.goto("videos", "shorts")
	await look("03_shorts", 1.5)
	main.goto("videos", "abos")
	await look("04_abos", 1.2)
	main.goto("streams", "kategorien")
	await look("05_kategorien", 1.5)
	main.goto("shop")
	await look("06_shop", 3.0)
	main.goto("achievements")
	await look("07_profil", 1.5)
	main.goto("friends")
	await look("08_freunde", 1.2)
	for cat in ["aussehen", "spiele", "aufnahmen", "konten", "system"]:
		main.goto("settings", cat)
		await look("09_einstellungen_" + cat, 1.0)
	main.goto("games", "zuletzt")
	await wait(0.8)
	main.open_library("ps2", "PlayStation 2")
	await look("10_raster", 1.5)
	press("b")
	await wait(0.8)
	var g := Library.get_game("ps2:sotc")
	if g.is_empty() and not Library.visible_games().is_empty():
		g = Library.visible_games()[0]
	main.open_game_note(g)
	await look("11_spielseite", 2.0)
	press("b")
	await wait(0.8)
	main.toggle_guide()
	await look("12_guide", 1.2)
	main.toggle_guide("system")
	await wait(0.4)
	main.toggle_guide("system")
	await look("13_guide_system", 1.2)
	main.toggle_guide()
	await wait(0.8)
	main.open_dialog("Shadow of the Colossus startet nicht",
			"Für PlayStation 2 ist noch kein Emulator eingerichtet. Unter Einstellungen → Emulatoren den Pfad zu PCSX2 eintragen.",
			[["Einstellungen öffnen", func() -> void: pass], ["Schließen", func() -> void: pass]], "warning", "warn")
	await look("14_dialog", 0.8)
	press("b")
	await wait(0.5)
	print("Überlauf gesamt: %d" % _found)


func look(name: String, delay: float) -> void:
	await shot(name, delay)
	_check(get_tree().root, name)
	_check_shelf(get_tree().root, name)


## Cover-Regale (Startseite, Spielseite) enden über der Tastenleiste: die Cover selbst, ohne
## Spiegelung darunter.
func _check_shelf(n: Node, where: String) -> void:
	var bar: Control = main.get("hint_bar")
	if bar == null or not bar.is_visible_in_tree():
		return
	for c in n.find_children("*", "Control", true, false):
		var scr: Script = c.get_script()
		if scr == null or not scr.resource_path.ends_with("cover_row.gd") or not (c as Control).is_visible_in_tree():
			continue
		if _alpha(c) < 0.05:
			continue
		var r := (c as Control).get_global_rect()
		var bottom := r.position.y + float(c.get("pad_top")) + float(c.get("_hmax"))
		var top := bar.get_global_rect().position.y
		if bottom > top + 2.0:
			_found += 1
			print("ÜBERLAPPUNG %s: Regal endet bei %d, Tastenleiste beginnt bei %d" % [where, bottom, top])


func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


## Sichtbare Bedienelemente, die über den Fensterrand ragen, ohne dass eine rollende oder
## zuschneidende Fläche sie hält. Je Knoten nur einmal, und nur der äußerste (nicht alle Kinder).
func _check(n: Node, where: String, clipped := false, alpha := 1.0) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is CanvasItem:
		alpha *= (n as CanvasItem).modulate.a
	# Ausgeblendet (die Startseite hinter einer Vollbild-Ebene) zählt nicht.
	if alpha < 0.05:
		return
	var c := n as Control
	if c != null:
		var scr: Script = c.get_script()
		# Cover-Regale laufen gewollt über den Rand und rollen mit der Auswahl.
		if scr != null and scr.resource_path.ends_with("cover_row.gd"):
			return
		if not clipped and c.size.x > 0.0 and c.size.y > 0.0:
			var vs := get_viewport().get_visible_rect().size
			var r := c.get_global_rect()
			var out := r.position.x < -2.0 or r.end.x > vs.x + 2.0 or r.end.y > vs.y + 2.0
			# Hintergründe und Lichtflächen dürfen größer sein als das Fenster.
			if out and c.mouse_filter != Control.MOUSE_FILTER_IGNORE or out and (c is Label or c is Button):
				var key := str(c.get_path())
				if not _seen.has(key):
					_seen[key] = true
					_found += 1
					print("ÜBERLAUF %s: %s  %s (min %s)" % [where, key.right(110), str(r), str(c.get_combined_minimum_size())])
				return
		# Was eine rollende oder zuschneidende Fläche hält, darf über ihren Rand laufen.
		if c.clip_contents or c.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			clipped = true
	for ch in n.get_children():
		_check(ch, where, clipped, alpha)
