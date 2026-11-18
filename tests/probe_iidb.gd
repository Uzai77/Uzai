extends "res://tests/probe_base.gd"
## Probe iiDB: Anmeldeseite, „Spiele scrapen“ mit iiDB, Bildwahl eines Spiels (Galerie mit „Mehr laden“,
## Reiter Banner) und die Wahl bei mehreren Treffern. Ohne Netz: Antworten in der Form der Doku kommen
## aus dieser Datei (Media.iidb.test), die Vorschauen sind farbige Flächen im Cache. Der Schlüssel der
## Probe steht nur in der Config dieses Datenordners.

const Iidb := preload("res://src/core/iidb.gd")

var _mehrdeutig := false


func run() -> void:
	await wait(1.0)
	var l: Control = load("res://src/ui/layers/iidb_login.gd").new()
	l.main = main
	main.open_layer(l)
	await shot("iidb_anmeldung", 1.2)
	await press("b")
	await wait(0.5)

	Config.set_value(Iidb.KEY_PATH, "probe-schluessel-nur-fuer-bilder")
	Media.iidb.test = _antwort
	Media.iidb.zugang = { "ok": true, "stufe": "supporter", "rps": 5, "name": "probe" }
	Media.iidb_einschalten()
	var s = load("res://src/ui/layers/spiele_scrapen.gd").new()
	s.main = main
	main.open_layer(s)
	await shot("iidb_scrapen", 1.2)
	await press("b")
	await wait(0.5)

	var spiele: Array = Library.visible_games().filter(func(g: Dictionary) -> bool: return str(g.get("source", "")) in ["rom", "disc"])
	if spiele.size() < 2:
		return
	main.open_art_picker(spiele[0], "iidb")
	await shot("iidb_bildwahl", 2.5)
	await press("down", 2)
	await shot("iidb_bildwahl_unten", 1.0)
	await press("rb", 2)
	await shot("iidb_bildwahl_banner", 2.0)
	await press("b")
	await wait(0.5)

	_mehrdeutig = true
	main.open_art_picker(spiele[1], "iidb")
	await shot("iidb_wahl", 2.0)
	await press("b")
	await wait(0.3)
	await press("b")
	await wait(0.4)


## Nachgebaute Antworten von iiDB.
func _antwort(a: Dictionary) -> Dictionary:
	var pfad := str(a.get("pfad", ""))
	var data: Variant = {}
	if pfad == "/resolve/batch":
		if _mehrdeutig:
			data = { "results": [{ "match": { "status": "needs_choice", "parent": null }, "artwork_status": "not_requested", "artwork": {},
				"candidates": [{ "id": 11.0, "name": "Shadow of the Colossus", "year": 2005.0, "primary_platform": "PlayStation 2" },
					{ "id": 12.0, "name": "Shadow of the Colossus", "year": 2018.0, "primary_platform": "PlayStation 4" },
					{ "id": 13.0, "name": "Shadow of the Colossus HD", "year": 2011.0, "primary_platform": "PlayStation 3" }] }] }
		else:
			data = { "results": [{ "match": { "status": "matched", "parent": { "id": 46185.0, "name": "Okami", "year": 2006.0 } },
				"artwork_status": "not_requested", "artwork": {} }] }
	elif pfad.ends_with("/gallery"):
		var art := str(a.query.asset_type)
		var ab := 100 if str(a.query.get("cursor", "")) != "" else 0
		var items: Array = []
		for i in (9 if art == "boxart" else 5):
			var id := 1000 + ab + i + art.hash() % 500
			var url := "https://assets.iisu.network/probe/%s_%d.png" % [art, id]
			_vorschau(url, art, i + ab)
			items.append({ "id": float(id), "type": art, "url": url, "revision": "r1", "thumbnail_url": url, "region": ["Europe", "USA", "Japan"][i % 3] })
		data = { "parent_id": 46185.0, "name": "Okami", "type": art, "items": items,
			"page": { "limit": 24.0, "total": 40.0, "next_cursor": "seite2" if ab == 0 and art == "boxart" else null, "has_more": ab == 0 and art == "boxart" } }
	return { "code": 200, "data": data, "headers": PackedStringArray() }


## Eine farbige Fläche als Vorschau in den Cache, wo Media.url_texture sie sucht.
func _vorschau(url: String, art: String, n: int) -> void:
	var gr := { "boxart": Vector2i(330, 450), "banner": Vector2i(480, 270), "hero": Vector2i(620, 200) }
	var g: Vector2i = gr.get(art, Vector2i(300, 300))
	var img := Image.create(g.x, g.y, false, Image.FORMAT_RGBA8)
	var c := Color.from_hsv(fmod(0.06 + n * 0.17, 1.0), 0.5, 0.72)
	for y in g.y:
		img.fill_rect(Rect2i(0, y, g.x, 1), c.darkened(float(y) / g.y * 0.6))
	var p := Media.url_path(url)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)
