extends "res://tests/probe_base.gd"
## Probe für die Bilder im Shop (Demo, ohne Netz): Fast alle Spiele haben hier absichtlich nur ein
## Querformat-Bild (Kapsel 616 × 353 mit hellem „Schriftzug“ links), drei Spiele eine Hülle unter
## einer Adresse mit Prüfsumme (wie neue Spiele bei Steam). Zu sehen sein soll: Hüllen füllen die
## Karte, Querbilder liegen ganz und unverzerrt über ihrer weichen Fassung – in Regalen, Rampenlicht,
## Listen, Genres, Wunschliste und bei den Erweiterungen (dort bleibt die Karte quer).

const COVERS := [1903340, 1145350, 2379780]


func run() -> void:
	_seed()
	var view = main.sections["shop"]
	main.goto("shop")
	await shot("01_entdecken", 4.5)
	await press("down", 2)
	await shot("02_regal", 1.2)
	await press("down", 1)
	await shot("03_rampenlicht", 1.2)
	await press("down", 2)
	await shot("04_regale_unten", 1.2)
	main.goto("shop", "specials")
	await shot("05_angebote_raster", 2.0)
	main.goto("shop", "genres")
	await shot("06_genres", 2.5)
	await press("a")
	await shot("07_genre_seite", 2.5)
	await press("b")
	main.goto("shop", "wunschliste")
	await shot("08_wunschliste", 2.5)
	main.goto("shop", "entdecken")
	await wait(0.8)
	view.open_item(Store.known_item(753640))
	await wait(2.0)
	for i in 4:
		await press("down")
	await shot("09_erweiterungen_quer", 1.5)


## Bildangaben und Bilder so in die Speicher legen, als hätte Steam sie geschickt.
func _seed() -> void:
	var now := int(Time.get_unix_time_from_system())
	Media._assets_loaded = true
	var d: Variant = Config.read_json("res://tests/demo_store.json", {})
	var ids := {}
	for key in ["specials", "top_sellers", "new_releases", "coming_soon"]:
		for it in d.get(key, {}).get("items", []):
			ids[int(it.id)] = true
	for k in (d.get("items", {}) as Dictionary).keys():
		ids[int(k)] = true
	for w in d.get("wishlist", []):
		ids[int(w)] = true
	var i := 0
	for id in ids.keys():
		i += 1
		var hue := fposmod(i * 0.137, 1.0)
		if id in COVERS:
			# Neues Spiel: Hülle nur im Ordner mit Prüfsumme.
			Media._assets[str(id)] = { "_t": now, "asset_url_format": "steam/apps/%d/${FILENAME}?t=1" % id,
				"library_capsule": "c0ffee/library_600x900.jpg", "main_capsule": "c0ffee/capsule_616x353.jpg" }
			_put(Media.STORE_ASSETS + "steam/apps/%d/c0ffee/library_600x900.jpg?t=1" % id, _paint(600, 900, hue, true))
			_put(Media.STORE_ASSETS + "steam/apps/%d/c0ffee/capsule_616x353.jpg?t=1" % id, _paint(616, 353, hue, false))
		else:
			# Steam kennt keine Hülle: nur Kapsel und Kopfbild (quer).
			Media._assets[str(id)] = { "_t": now }
		_put(Store.CDN % [id, "capsule_616x353.jpg"], _paint(616, 353, hue, false))
		_put(Store.CDN % [id, "header.jpg"], _paint(460, 215, hue, false))


func _put(url: String, img: Image) -> void:
	var dest := Config.path("cache/img/web/%s.jpg" % url.md5_text())
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	img.save_jpg(dest, 0.9)


## Gemalte Spielbilder: Himmel, Sonne, Berge und ein heller Balken als „Schriftzug“ (links im
## Querbild, oben in der Hülle) – so sieht man sofort, ob das ganze Bild zu sehen ist und ob es
## gestreckt wurde (die Sonne muss rund bleiben).
func _paint(w: int, h: int, hue: float, tall: bool) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var top := Color.from_hsv(hue, 0.6, 0.35)
	var bottom := Color.from_hsv(fposmod(hue + 0.08, 1.0), 0.45, 0.9)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), top.lerp(bottom, float(y) / h))
	var r := int(minf(w, h) * 0.16)
	var c := Vector2i(int(w * (0.5 if tall else 0.72)), int(h * (0.42 if tall else 0.36)))
	for dy in range(-r, r):
		var span := int(sqrt(float(r * r - dy * dy)))
		img.fill_rect(Rect2i(c.x - span, c.y + dy, span * 2, 1), Color.from_hsv(fposmod(hue + 0.12, 1.0), 0.2, 1.0))
	for layer in 3:
		var base := h * (0.62 + layer * 0.1)
		var col := Color.from_hsv(fposmod(hue - 0.04, 1.0), 0.5, 0.28 - layer * 0.08)
		for x in w:
			var yy := int(base - (sin(x * 0.013 + layer * 1.7) * 0.5 + sin(x * 0.031 + hue * 9.0) * 0.3 + 0.6) * h * 0.12)
			img.fill_rect(Rect2i(x, yy, 1, h - yy), col)
	var logo := Rect2i(int(w * 0.08), int(h * 0.1), int(w * 0.84), int(h * 0.09)) if tall else Rect2i(int(w * 0.06), int(h * 0.3), int(w * 0.42), int(h * 0.16))
	img.fill_rect(logo, Color(1, 1, 1, 1))
	img.fill_rect(Rect2i(logo.position + Vector2i(6, 6), logo.size - Vector2i(12, 12)), Color.from_hsv(hue, 0.7, 0.55))
	return img
