extends "res://tests/probe_base.gd"
## Probe „Nie warten“ (Punkt 93, Demo): misst, wo man in Uzai sichtbar wartet – Startseite beim
## Start, Reiterwechsel (erster Besuch), Spielseite (gleich bzw. nach kurzer Ruhe geöffnet), Guide,
## Shop-Seite eines Spiels, Bibliothek beim schnellen Blättern. Je Schritt:
##   block  – so lange hing der Aufruf selbst (ms, ein Bild steht so lange),
##   frame  – längstes Bild in der ersten Sekunde (ms, ohne die Messung selbst),
##   fertig – bis nichts mehr lädt: kein Platzhalter, kein Cover ohne Bild, 300 ms kein Sprung
##            (ms ab dem Aufruf; „>4000“ = in 4 s nicht fertig),
##   warten – wie lange Platzhalter oder Cover ohne Bild zu sehen waren (ms),
##   spruenge – wie oft sichtbarer Inhalt im Layout um mehr als 6 Punkte versetzt wurde
##            (wie CLS: nur Verschiebungen von schon Sichtbarem, nicht das Erscheinen),
##   flaeche – Summe der versetzten Fläche in Bildschirmen.
## Ergebnis zusätzlich als messung.json im Ausgabeordner (vorher/nachher vergleichen).
##
## Bilder: Die Demo hat keine. Vor dem Lauf Testbilder (Cover 600 × 900, Hero 3840 × 1240, Logo)
## unter <UZAI_DATA>/media/<system>/[hero|logo]/<Name>.jpg ablegen – ohne sie misst die Probe nur
## Platzhalter und Sprünge. Die Werte schwanken mit Software-Grafik stark: mehrmals messen.

const CAP_MS := 4000
const JUMP_PX := 6.0

var CoverCard: Script = load("res://src/ui/components/cover_card.gd")
var _ph_scripts: Array = []
var results: Dictionary = {}

var _root_fn: Callable
var _rec := false
var _t0 := 0
var _prev_frame := 0
var _scan_us := 0
var _pos := {}
var r: Dictionary = {}


func _ready() -> void:
	# Bekannte Platzhalter (je nach Stand des Codes gibt es sie oder nicht).
	for pair in [["res://src/ui/sections/section.gd", "_Skeleton"], ["res://src/ui/components/track_page.gd", "_Skeleton"],
			["res://src/ui/sections/music_view.gd", "_Ghost"], ["res://src/ui/sections/friends_view.gd", "_GhostRow"],
			["res://src/ui/components/ach/skeleton.gd", ""], ["res://src/ui/components/skeleton.gd", ""]]:
		if not ResourceLoader.exists(pair[0]):
			continue
		var sc: Script = load(pair[0])
		if pair[1] == "":
			_ph_scripts.append(sc)
		else:
			var inner: Variant = sc.get_script_constant_map().get(pair[1])
			if inner is Script:
				_ph_scripts.append(inner)
	super._ready()


func _start() -> void:
	main = get_tree().current_scene
	# Startseite ab Programmstart: beobachten, sobald es sie gibt.
	_begin("start", func() -> Control: return main.sections.get("games") if "sections" in main else null, Time.get_ticks_usec())
	await _finish(6000)
	await wait(1.0)
	await run()
	var f := FileAccess.open(out.path_join("messung.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("Probe fertig: ", out)
	get_tree().quit()


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	# Reiterwechsel: jeder Bereich zum ersten Mal (ohne Startanimation, also ohne Vorbauen beim
	# Start – wie nach dem Zeitfenster oder wenn sich die Daten geändert haben). Vorher gut zwei
	# Sekunden auf der Startseite ruhen, wie man es tut (dann baut Uzai die Nachbarn vor).
	var tabs: Array = main.order.duplicate()
	for sid in tabs:
		if sid == "games":
			continue
		await wait(2.6)
		await measure("reiter_" + sid, func() -> Control: return main.sections.get(sid),
			func() -> void: main.goto(sid))
		await wait(0.6)
		main.goto("games")
	# Zweiter Besuch: schon gebaut.
	for sid in ["shop", "music", "settings"]:
		if not main.sections.has(sid):
			continue
		await wait(1.0)
		await measure("wieder_" + sid, func() -> Control: return main.sections.get(sid),
			func() -> void: main.goto(sid))
		await wait(0.4)
		main.goto("games")
	await wait(1.5)
	# Spielseite: einmal sofort nach dem Wählen geöffnet, einmal nach kurzer Ruhe.
	var gs: Node = main.sections.games
	for step in [["spielseite_sofort", 2, 0.15], ["spielseite_ruhe", 2, 1.4], ["spielseite_ruhe_steam", -1, 1.4]]:
		main.goto("games")
		await wait(1.0)
		var n: int = step[1]
		if n < 0:
			n = _steam_offset(gs)
		await press("right", n, 0.12)
		await wait(float(step[2]))
		var g: Dictionary = gs.get("_selected")
		print("Spiel: ", g.get("title", ""), " (", g.get("source", ""), ")")
		await measure(step[0], func() -> Control: return Nav.top_layer(), func() -> void: main.open_game(g))
		await wait(0.3)
		await press("b")
		await wait(0.8)
		await press("left", 12, 0.05)
	# Guide
	await wait(1.0)
	await measure("guide", func() -> Control: return Nav.top_layer(), func() -> void: main.toggle_guide())
	await wait(0.3)
	main.toggle_guide()
	await wait(1.0)
	# Shop: Seite eines Spiels nach kurzer Ruhe auf der Karte.
	if main.sections.has("shop"):
		main.goto("shop")
		await wait(2.0)
		var shop: Node = main.sections.shop
		var card: Control = null
		for c in Nav.focusables(shop):
			var it: Variant = c.get("item")
			if it is Dictionary and int((it as Dictionary).get("appid", 0)) > 0:
				card = c
				if c.get_index() >= 2:
					break
		if card:
			Nav.focus(card, true)
			await wait(1.4)
			var item: Dictionary = card.get("item")
			print("Shop: ", item.get("name", item.get("title", "")))
			await measure("shop_seite", func() -> Control: return Nav.top_layer(), func() -> void: shop.open_item(item))
		await wait(0.3)
		await press("b")
		await wait(0.8)
		main.goto("games")
		await wait(1.0)
	# Bibliothek: schnell nach unten blättern (Cover, die erst unterwegs laden).
	main.open_library("alle", "Alle Spiele")
	await wait(1.5)
	var lib := Nav.top_layer()
	if lib:
		await measure("bibliothek_blaettern", func() -> Control: return Nav.top_layer(), func() -> void:
			for i in 6:
				Nav._fire("down")
				await get_tree().create_timer(0.08).timeout
		)
		await press("b")
	await _show_placeholders()


## Zum Ansehen: die gemeinsamen Platzhalter in ihren Formen (nur, wenn es sie gibt).
func _show_placeholders() -> void:
	if not ResourceLoader.exists("res://src/ui/components/skeleton.gd"):
		return
	var Sk: Script = load("res://src/ui/components/skeleton.gd")
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "top", "right"]:
		m.add_theme_constant_override("margin_" + k, 96)
	bg.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 40)
	m.add_child(col)
	col.add_child(Sk.cards(5, UzTheme.cover_size()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	for i in 4:
		row.add_child(Sk.tile(200.0))
	var people := VBoxContainer.new()
	people.custom_minimum_size = Vector2(420, 0)
	for i in 3:
		people.add_child(Sk.person())
	row.add_child(people)
	col.add_child(row)
	var tr: Control = Sk.track_rows(3)
	col.add_child(tr)
	await shot("platzhalter_a", 0.4)
	await shot("platzhalter_b", 0.5)
	bg.queue_free()


## Position des ersten Steam-Spiels im Regal der Startseite (zum Nachladen von Store-Daten).
func _steam_offset(gs: Node) -> int:
	var shelf: Variant = gs.get("_shelf")
	if shelf == null:
		return 3
	var list: Array = shelf.items()
	var start := -1
	for i in list.size():
		var g: Variant = (list[i] as Control).get("game")
		if g is Dictionary:
			if start < 0:
				start = i
			if str((g as Dictionary).get("source", "")) == "steam" and i - start >= 3:
				return i - start
	return 4


# --- Messen -------------------------------------------------------------------------------------

func measure(name: String, root_fn: Callable, action: Callable) -> void:
	var t := Time.get_ticks_usec()
	_begin(name, root_fn, t)
	action.call()
	r.block = roundi((Time.get_ticks_usec() - t) / 1000.0)
	await _finish(CAP_MS)


func _begin(name: String, root_fn: Callable, t0: int) -> void:
	_root_fn = root_fn
	_t0 = t0
	_pos.clear()
	_prev_frame = 0
	r = { "name": name, "block": 0, "frame": 0.0, "fertig": -1, "warten": 0, "spruenge": 0, "flaeche": 0.0,
		"_ok_since": -1, "_last_jump": 0, "_last_ms": 0, "_what": "" }
	_rec = true


func _finish(cap: int) -> void:
	while _rec:
		await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - _t0) / 1000
		if ms > cap or (int(r._ok_since) >= 0 and ms - int(r._ok_since) > 500 and ms - int(r._last_jump) > 500):
			_rec = false
	var done := int(r._ok_since)
	if done < 0:
		print("  noch offen: ", r.get("_what", "(Wurzel nicht sichtbar)"))
	r.fertig = maxi(done, int(r._last_jump)) if done >= 0 else -1
	for k in r.keys():
		if str(k).begins_with("_"):
			r.erase(k)
	r.flaeche = snappedf(float(r.flaeche), 0.001)
	r.frame = snappedf(float(r.frame), 0.1)
	results[r.name] = r.duplicate()
	print("MESS %-24s block %4d ms  frame %6.1f ms  fertig %5s ms  warten %5d ms  spruenge %3d  flaeche %.3f" % [
		r.name, r.block, r.frame, str(r.fertig) if int(r.fertig) >= 0 else ">%d" % cap, r.warten, r.spruenge, r.flaeche])


func _process(_dt: float) -> void:
	if not _rec:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _t0) / 1000
	if _prev_frame > 0 and ms < 1000:
		r.frame = maxf(float(r.frame), (now - _prev_frame - _scan_us) / 1000.0)
	_prev_frame = now
	var root: Variant = _root_fn.call()
	if not (root is Control) or not is_instance_valid(root) or not (root as Control).is_visible_in_tree():
		_scan_us = Time.get_ticks_usec() - now
		r._last_ms = ms
		return
	var view := get_viewport().get_visible_rect()
	var seen := {}
	var state := { "ph": 0, "bare": 0 }
	_scan(root, root, view, seen, state)
	var dt := ms - int(r._last_ms)
	r._last_ms = ms
	if int(state.ph) > 0 or int(state.bare) > 0:
		r.warten = int(r.warten) + dt
		r._ok_since = -1
		r._what = str(state.get("what", ""))
	elif int(r._ok_since) < 0:
		r._ok_since = ms
	_pos = seen
	_scan_us = Time.get_ticks_usec() - now


func _scan(n: Node, root: Control, view: Rect2, seen: Dictionary, state: Dictionary) -> void:
	for c in n.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		var ctl := c as Control
		var gr := ctl.get_global_rect()
		var on := view.intersects(gr) and gr.size.x > 2.0 and gr.size.y > 2.0
		var sc: Script = ctl.get_script()
		if on and sc != null and _ph_scripts.has(sc):
			state.ph = int(state.ph) + 1
			state.what = str(root.get_path_to(ctl))
			continue
		if on and ctl is Label and ((ctl as Label).text.contains("lädt") or (ctl as Label).text.contains("Lädt") or (ctl as Label).text.contains("geladen")):
			state.ph = int(state.ph) + 1
			state.what = (ctl as Label).text
		if on and sc == CoverCard and ctl.has_method("image_requested") and ctl.call("image_requested"):
			var img: Variant = ctl.get("_img")
			if img is Control and not (img as Control).visible:
				state.bare = int(state.bare) + 1
				state.what = "Cover ohne Bild"
		var track := on and (ctl.focus_mode != Control.FOCUS_NONE or ctl is Label or ctl is TextureRect) and gr.size.x * gr.size.y >= 400.0
		if track:
			var p := _layout_pos(ctl, root)
			var id := ctl.get_instance_id()
			seen[id] = p
			if _pos.has(id):
				var d: Vector2 = p - _pos[id]
				if d.length() > JUMP_PX:
					r.spruenge = int(r.spruenge) + 1
					r.flaeche = float(r.flaeche) + (gr.size.x * gr.size.y) / (view.size.x * view.size.y)
					r._last_jump = (Time.get_ticks_usec() - _t0) / 1000
		# In Karten und Knöpfe nicht hinein: sie bewegen sich als Ganzes.
		if ctl.focus_mode == Control.FOCUS_NONE or ctl == root:
			_scan(ctl, root, view, seen, state)


## Lage im Layout relativ zur Wurzel: nur die Positionen (Skalierung beim Fokus und das
## Hereingleiten der Wurzel zählen nicht als Sprung).
static func _layout_pos(c: Control, root: Control) -> Vector2:
	var p := Vector2.ZERO
	var n: Node = c
	while n != null and n != root:
		if n is Control:
			p += (n as Control).position
		n = n.get_parent()
		if n is ScrollContainer:
			p += Vector2((n as ScrollContainer).scroll_horizontal, (n as ScrollContainer).scroll_vertical)
	return p
