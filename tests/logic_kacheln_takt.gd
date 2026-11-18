extends Node
## Ein Cursor-Takt auch für Medien-Kacheln (Plan „Gefühl 2“, B4/B5): Film-, Video-, Musik- und
## Medien-Kachel stehen gewählt im ersten Bild zu mindestens 70 % da (Liste.takt), abgewählt fällt
## der Ring sofort auf höchstens 30 %; ein Lichtstreif läuft nur, wo das Theme ihn will (Graphit
## nicht); Eindrücken lässt den Ring stehen.
## Aufruf: godot --headless --path . res://tests/logic_kacheln_takt.tscn

const MediaTile := preload("res://src/ui/components/media_tile.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const MovieCard := preload("res://src/ui/components/movie_card.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _streifen(c: Node) -> int:
	var n := 0
	for k in c.find_children("*", "", true, false):
		if k.get_script() and str(k.get_script().resource_path).ends_with("shine.gd"):
			n += 1
	return n


func _ready() -> void:
	var paare := [
		["Medien-Kachel", MediaTile.new().setup("kodi", "Kodi", "tv", 0.5, "Programm"), MediaTile.new().setup("plex", "Plex", "tv", 0.2, "App")],
		["Musik-Kachel", MusicTile.new().setup({ "name": "Mix 1" }), MusicTile.new().setup({ "name": "Mix 2" })],
		["Film", MovieCard.new().setup({ "id": "tt1", "name": "Film 1" }, "grid"), MovieCard.new().setup({ "id": "tt2", "name": "Film 2" }, "grid")],
		["Video", VideoCard.new().setup({ "id": "v1", "title": "Video 1" }), VideoCard.new().setup({ "id": "v2", "title": "Video 2" })],
	]
	var will := UzTheme.focus_shine()
	for p in paare:
		var box := HBoxContainer.new()
		add_child(box)
		var a: Control = p[1]
		var b: Control = p[2]
		box.add_child(a)
		box.add_child(b)
		await get_tree().process_frame
		a.grab_focus()
		for i in 30:
			await get_tree().process_frame
		b.grab_focus()
		var neu := float(b.get("_focus_t"))
		var alt := float(a.get("_focus_t"))
		check(neu >= 0.7 and alt <= 0.3, "%s: neuer Ring sofort %.2f (≥ 0,7), alter sofort %.2f (≤ 0,3)" % [p[0], neu, alt])
		for i in 20:
			await get_tree().process_frame
		check(float(b.get("_focus_t")) >= 0.99 and float(a.get("_focus_t")) <= 0.01, "%s: nach 330 ms gesetzt" % p[0])
		check(will or _streifen(box) == 0, "%s: Lichtstreif nur, wo das Theme ihn will (%d)" % [p[0], _streifen(box)])
		b.call("press_feedback")
		await get_tree().process_frame
		check(float(b.get("_focus_t")) >= 0.99, "%s: Eindrücken lässt den Ring stehen" % p[0])
		box.queue_free()
		await get_tree().process_frame
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
