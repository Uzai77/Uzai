extends Node
## Ausgeblendete Spiele (Nutzertest: „geht trotzdem nicht weg bei der Haupt-Bibliothek“): in keiner
## Liste außer „Ausgeblendete Spiele“ – auch nicht mit der alten Einstellung „Ausgeblendete Spiele
## zeigen“ – und das Raster merkt, dass sich seine Spiele geändert haben.
## Aufruf: godot --headless --path . res://tests/logic_ausblenden.tscn

const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")
const GameFilter := preload("res://src/library/game_filter.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ids(list: Array) -> Array:
	return list.map(func(g): return str(g.get("id", "")))


func _ready() -> void:
	Library.load_demo()
	var recent := Library.recent(24)
	check(not recent.is_empty(), "Demo-Bibliothek mit „Zuletzt“")
	var g: Dictionary = recent[0]
	var gid := str(g.id)
	var sys := str(g.get("system", ""))
	Library.set_field(gid, "favorite", true)
	var fid := Library.create_folder("Testordner", "")
	Library.set_in_folder(gid, fid, true)
	var vor := Library.visible_games()
	check(_ids(vor).has(gid) and _ids(Library.favorites()).has(gid) and _ids(Library.in_folder(fid)).has(gid), "vorher überall zu sehen")

	print("Ausblenden")
	# Die alte Einstellung „Ausgeblendete Spiele zeigen“ darf sie nicht mehr in die Listen holen.
	Config.set_value("library.show_hidden", true)
	Library.set_field(gid, "hidden", true)
	var nach := Library.visible_games()
	check(not _ids(nach).has(gid), "nicht unter „Alle“ (visible_games)")
	check(not _ids(Library.recent(24)).has(gid), "nicht in „Zuletzt“ (Startseite, Guide, Für dich)")
	check(not _ids(Library.favorites()).has(gid), "nicht unter „Favoriten“")
	check(not _ids(Library.by_system(sys)).has(gid), "nicht in seiner Quelle (%s)" % sys)
	check(not _ids(Library.in_folder(fid)).has(gid), "nicht im Ordner")
	check(not _ids(GameFilter.apply(nach, {}, {})).has(gid), "nicht im gefilterten Raster")
	check(_ids(Library.hidden_games()).has(gid), "aber in „Ausgeblendete Spiele“")
	check(Library.is_visible(Library.get_game(gid), true) and not Library.is_visible(Library.get_game(gid)), "is_visible: nur mit with_hidden")

	print("Raster zieht nach")
	check(LibraryGrid.same_games(vor, Library.visible_games().duplicate()) == false, "Raster erkennt: ein Spiel weniger")
	check(LibraryGrid.same_games(nach, Library.visible_games()), "gleiche Spiele: kein Neufüllen")
	check(not LibraryGrid.same_games([{ "id": "a" }, { "id": "b" }], [{ "id": "b" }, { "id": "a" }]), "andere Reihenfolge zählt als Änderung")

	print("Wieder zeigen")
	Library.set_field(gid, "hidden", null)
	check(_ids(Library.visible_games()).has(gid) and _ids(Library.favorites()).has(gid), "wieder überall da")
	check(not _ids(Library.hidden_games()).has(gid), "nicht mehr unter „Ausgeblendete Spiele“")
	Config.set_value("library.show_hidden", false)
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit()
