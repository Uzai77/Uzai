extends Node
## Nie warten (Punkt 93): Regeln des gezielten Vorladens (wann, wie viel, was), der gemeinsame
## Platzhalter (Schimmer, Formen, Übergang ins Ergebnis) und das Postergitter, das die nächste
## Seite früher holt und solange Platzhalter in Plakatform zeigt.
## Aufruf: godot --headless --path . res://tests/logic_vorladen.tscn

const Vorladen := preload("res://src/core/vorladen.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")
const PosterGrid := preload("res://src/ui/components/poster_grid.gd")
const Leicht := preload("res://src/core/leicht.gd")

signal _page_go

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Wann vorgeladen wird")
	check(Vorladen.allowed(false, false, false), "Menü: ja")
	check(not Vorladen.allowed(true, false, false), "im Spiel: nie")
	check(not Vorladen.allowed(false, true, false), "beim Starten eines Spiels: nie")
	check(not Vorladen.allowed(false, false, true), "im Ruhemodus: nie")
	check(Vorladen.dwell_ms(false) >= 400, "erst nach kurzer Ruhe, nicht beim Blättern (%d ms)" % Vorladen.dwell_ms(false))
	check(Vorladen.dwell_ms(true) > Vorladen.dwell_ms(false), "leichter Modus: später")
	check(Vorladen.max_jobs(true) < Vorladen.max_jobs(false) and Vorladen.max_jobs(false) <= 8, "Budget je Ruhepunkt, leicht kleiner")
	check(Vorladen.REST_MS > Vorladen.dwell_ms(false), "Bereiche nebenan erst nach längerer Ruhe")

	print("Was vorgeladen wird")
	var steam := { "id": "steam:1", "source": "steam", "appid": 1245620 }
	var rom := { "id": "ps2:1", "source": "rom", "system": "ps2" }
	var epic := { "id": "epic:1", "source": "epic" }
	check(Vorladen.game_jobs(steam, false) == ["logo", "hero", "store", "shots", "ach"], "Steam-Spiel: Schriftzug, Bild, Store, Bilder, Erfolge")
	check(Vorladen.game_jobs(rom, false) == ["logo", "hero", "wiki", "shots", "ach"], "Emulator-Spiel: Wikipedia statt Store")
	check(Vorladen.game_jobs(rom, false, false) == ["logo", "hero", "shots", "ach"], "ohne Infos aus dem Netz: kein Wikipedia")
	check(Vorladen.game_jobs(epic, true) == ["logo", "hero"], "leichter Modus: nur die beiden Bilder")
	check(not Vorladen.game_jobs({ "source": "steam", "appid": 0 }, false).has("store"), "Steam ohne App-ID: kein Store")

	print("Raster: nächste Seite früher")
	check(Vorladen.page_from(42, 7, false) == 14, "42 Karten, 7 Spalten: ab Karte 14 (vier Reihen vor dem Ende)")
	check(Vorladen.page_from(42, 7, true) == 28, "leicht: zwei Reihen vor dem Ende")
	check(Vorladen.page_from(10, 7, false) == 0, "kurze Liste: gleich")

	print("Platzhalter")
	var lo := 1.0
	var hi := 0.0
	for i in 200:
		var a := Skeleton.alpha_at(float(i % 20) * 96.0, float(i) * 0.031)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	check(lo >= Skeleton.BASE_A - 0.0001 and hi <= Skeleton.BASE_A + Skeleton.GLOW_A + 0.0001 and hi - lo > 0.02,
			"Schimmer ruhig zwischen %.3f und %.3f" % [lo, hi])
	check(absf(Skeleton.alpha_at(100.0, 0.3) - Skeleton.alpha_at(100.0, 1.3)) < 0.0001, "eine Welle je PERIOD, überall im Takt")
	Leicht.active = true
	check(Skeleton.alpha_at(100.0, 0.3) == Skeleton.BASE_A and Skeleton.alpha_at(900.0, 0.7) == Skeleton.BASE_A, "leichter Modus: ruhige Fläche ohne Schimmer")
	Leicht.active = false
	var cards := Skeleton.cards(5, Vector2(216, 288))
	check(cards.custom_minimum_size == Vector2(5 * 216 + 4 * 24, 288) and cards.shapes.size() == 5, "Kartenreihe: Größe wie fünf Karten")
	check(float(cards.shapes[4].a) < float(cards.shapes[0].a), "weiter rechts blasser")
	var tile := Skeleton.tile(200.0)
	check(tile.custom_minimum_size == Vector2(200, 276) and tile.shapes.size() == 3, "Kachel: Bild und zwei Zeilen, so hoch wie die echte")
	check(Skeleton.person().custom_minimum_size.y == 84.0 and bool(Skeleton.person().shapes[0].circle), "Person: rundes Bild, 84 hoch")
	check(Skeleton.track_rows(8).custom_minimum_size.y == 608.0, "Titelzeilen: acht Zeilen à 76")
	var one := Skeleton.new().setup(Vector2(184, 184), -1, true)
	check(one.custom_minimum_size == Vector2(184, 184) and bool(one.shapes[0].circle), "einzelne Form (Erfolge-Seite)")
	for n in [cards, tile, one]:
		check(n.is_in_group(Skeleton.GROUP) and n.mouse_filter == Control.MOUSE_FILTER_IGNORE and n.focus_mode == Control.FOCUS_NONE,
				"nie fokussierbar, leicht zu finden (%s)" % str(n.custom_minimum_size))
	for n in [cards, tile, one]:
		n.free()

	print("Übergang ins Ergebnis")
	var box := VBoxContainer.new()
	add_child(box)
	var before := Label.new()
	box.add_child(before)
	var sk := Skeleton.tile(100.0)
	box.add_child(sk)
	box.add_child(Label.new())
	var res := Control.new()
	Skeleton.swap(sk, res)
	check(res.get_parent() == box and res.get_index() == 1, "Ergebnis an der Stelle des Platzhalters")
	check(box.get_child_count() == 3 and res.modulate.a == 0.0, "Platzhalter weg, Ergebnis blendet ein")
	await get_tree().create_timer(0.5).timeout
	check(res.modulate.a > 0.99, "nach dem Einblenden ganz da")
	var sk2 := Skeleton.fill(0)
	box.add_child(sk2)
	Skeleton.fade_out(sk2)
	await get_tree().create_timer(0.5).timeout
	check(not is_instance_valid(sk2), "fade_out: weich weg und entfernt")
	box.queue_free()

	print("Postergitter")
	var pg = PosterGrid.new()
	pg.size = Vector2(1920, 1080)
	var pages := [0]
	pg.loader = func(skip: int) -> Array:
		pages[0] += 1
		await _page_go
		var out: Array = []
		for i in 14:
			out.append({ "id": "m%d" % (skip + i), "name": "Film %d" % (skip + i), "type": "movie" })
		return out
	add_child(pg)
	pg.reload()
	await get_tree().process_frame
	var grid: GridContainer = pg.get("_grid")
	var ghosts := grid.get_children().filter(func(c: Node) -> bool: return c.is_in_group(Skeleton.GROUP))
	check(ghosts.size() == 14, "erste Seite lädt: zwei Reihen Platzhalter (%d)" % ghosts.size())
	check(pg.get("_status").text == "", "kein „Lädt …“")
	_page_go.emit()
	await get_tree().process_frame
	var cards_n := grid.get_children().filter(func(c: Node) -> bool: return not c.is_in_group(Skeleton.GROUP) and not c.is_queued_for_deletion()).size()
	check(cards_n == 14 and grid.get_child_count() == 14, "Karten an der Stelle der Platzhalter (%d)" % grid.get_child_count())
	var cell: Vector2 = (grid.get_child(0) as Control).get_combined_minimum_size()
	pg.load_more()
	await get_tree().process_frame
	ghosts = grid.get_children().filter(func(c: Node) -> bool: return c.is_in_group(Skeleton.GROUP))
	check(ghosts.size() == 7 and (ghosts[0] as Control).custom_minimum_size == cell, "nächste Seite: eine Reihe Platzhalter in Kartengröße %s" % str(cell))
	_page_go.emit()
	await get_tree().process_frame
	check(grid.get_child_count() == 28 and pages[0] == 2, "zweite Seite da")
	pg.queue_free()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
