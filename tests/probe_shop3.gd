extends "res://tests/probe_base.gd"
## Kurze Probe für den Shop (drei Bilder): Startseite mit Bühne, eine Reihe mit Auswahl und die
## Seite eines Spiels, das Freunde gerade spielen. Für zwei Spiele legt die Probe selbst gemalte
## Bilder in den Bildspeicher (wie probe_shop.gd), damit Bühne und Seite mit einem Bild zu sehen sind.


func run() -> void:
	var view = main.sections["shop"]
	_inject_art(632470, 0.08)
	_inject_art(1245620, 0.58)
	main.goto("shop")
	await shot("01_shop_start", 3.5)
	await press("down")
	await press("right", 2)
	await shot("02_shop_reihe", 1.0)
	# Die Seite eines Spiels, das Freunde gerade spielen (aus der Reihe „Bei deinen Freunden“).
	var freund: Dictionary = {}
	for it in Store.friend_items_cached():
		if int(it.get("appid", 0)) == 1245620:
			freund = it
	view.open_item(freund if not freund.is_empty() else Store.known_item(753640))
	await shot("03_shop_spiel", 3.0)


## Bilder für ein Spiel in den Bildspeicher legen (so, als wären sie schon geladen).
func _inject_art(appid: int, hue: float) -> void:
	var urls := {}
	urls[Store.CDN % [appid, "library_hero.jpg"]] = 0
	urls[Store.CDN % [appid, "header.jpg"]] = 1
	urls[Store.CDN % [appid, "capsule_616x353.jpg"]] = 1
	for i in 5:
		urls["https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/%d/ss_demo%d.1920x1080.jpg" % [appid, i]] = 2 + i
	var d: Variant = Config.read_json("res://tests/demo_store.json", {})
	var movies: Array = d.get("details", {}).get(str(appid), {}).get("movies", []) if d is Dictionary else []
	for mv in movies:
		urls[str(mv.get("thumbnail", ""))] = 9
	for u in urls.keys():
		var dest := Config.path("cache/img/web/%s.jpg" % str(u).md5_text())
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var k: int = urls[u]
		# Das große Bild im Format von Steams library_hero (etwa 3 : 1): die Bühne ist damit randvoll.
		var sz := Vector2i(1920, 620) if k == 0 else (Vector2i(600, 338) if k == 9 else Vector2i(1280, 720))
		_paint(sz.x, sz.y, fposmod(hue + k * 0.045, 1.0), k).save_jpg(dest, 0.88)


## Eine ruhige gemalte Landschaft: Himmel, Sonne, drei Bergketten.
func _paint(w: int, h: int, hue: float, seed_i: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var sky_top := Color.from_hsv(hue, 0.55, 0.32)
	var sky_bottom := Color.from_hsv(fposmod(hue + 0.09, 1.0), 0.42, 0.88)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), sky_top.lerp(sky_bottom, float(y) / h))
	var cx := int(w * (0.25 + 0.5 * fposmod(seed_i * 0.37, 1.0)))
	var cy := int(h * 0.36)
	var r := int(h * 0.11)
	for dy in range(-r, r):
		var span := int(sqrt(float(r * r - dy * dy)))
		img.fill_rect(Rect2i(cx - span, cy + dy, span * 2, 1), Color.from_hsv(fposmod(hue + 0.12, 1.0), 0.22, 1.0))
	for layer in 3:
		var base := h * (0.56 + layer * 0.12)
		var col := Color.from_hsv(fposmod(hue - 0.04, 1.0), 0.5, 0.3 - layer * 0.08)
		for x in w:
			var yy := int(base - (sin(x * 0.011 + seed_i + layer * 1.7) * 0.5 + sin(x * 0.029 + seed_i * 2.0) * 0.3 + 0.6) * h * 0.13)
			img.fill_rect(Rect2i(x, yy, 1, h - yy), col)
	return img
