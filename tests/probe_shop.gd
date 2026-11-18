extends "res://tests/probe_base.gd"
## Probe für den Shop: Entdecken, Kategorien, Listen, Genres, Wunschliste, Suche und die Seite
## eines Spiels (oben, Medien, tief gescrollt, Kaufen, Lesen, Trailer). Für eine zweite Seite
## (Hades II) legt die Probe selbst gemalte Bilder in den Bildspeicher, damit man sieht, wie die
## Seite mit echten Bildern wirkt – ohne Netz und ohne fremde Markenbilder.


func run() -> void:
	var view = main.sections["shop"]
	_inject_art(1145350, 0.58)
	_inject_art(632470, 0.08)
	main.goto("shop")
	await shot("01_entdecken", 3.5)
	await press("down")
	await shot("02_kategorien", 0.8)
	await press("right", 2)
	await shot("02b_kategorie_gewaehlt", 0.6)
	await press("down")
	await shot("03_wunschliste_im_angebot", 0.9)
	await press("down", 3)
	await shot("04_entdecken_unten", 0.9)
	main.goto("shop", "specials")
	await shot("05_angebote", 1.2)
	main.goto("shop", "coming_soon")
	await shot("05b_bald", 1.0)
	main.goto("shop", "genres")
	await shot("06_genres", 1.0)
	await press("a")
	await shot("07_genre_seite", 1.5)
	await press("b")
	main.goto("shop", "wunschliste")
	await shot("08_wunschliste", 1.5)
	main.goto("shop", "suche")
	await shot("09_suche_leer", 1.0)
	view._run_search("o")
	await shot("10_suche_treffer", 1.5)
	# Seite eines Spiels, nur mit Ersatzbildern (wie im Demo-Modus ohne Netz)
	main.goto("shop", "entdecken")
	await wait(0.8)
	view.open_item(Store.known_item(753640))
	await shot("11_detail_oben", 2.5)
	await press("down")
	await shot("12_detail_medien", 0.9)
	await press("down")
	await shot("13_detail_ueber", 0.9)
	await press("down")
	await shot("14_detail_editionen", 0.9)
	await press("down")
	await shot("15_detail_erweiterungen", 0.9)
	await press("down")
	await shot("16_detail_bewertungen", 0.9)
	await press("right")
	await shot("16b_detail_bewertung_gewaehlt", 0.7)
	await press("down")
	await shot("17_detail_neuigkeiten", 0.9)
	await press("a")
	await shot("17b_neuigkeit_lesen", 0.9)
	await press("b")
	await press("down")
	await shot("18_detail_anforderungen", 0.9)
	await press("a")
	await shot("19_lesen", 0.9)
	await press("down", 3)
	await shot("19b_lesen_geblaettert", 0.6)
	await press("b")
	await press("up", 9)
	await shot("20_detail_wieder_oben", 1.0)
	# Kaufen: bestätigen in Uzai, Edition wählen
	await press("a")
	await shot("21_kaufen", 1.0)
	await press("up")
	await shot("22_kaufen_edition", 0.6)
	await press("a")
	await shot("23_kaufen_edition2", 0.6)
	await press("down")
	await press("a")
	await shot("23b_bezahlen", 1.2)
	# Wunschliste direkt in Uzai
	await press("right")
	await press("a")
	await shot("24_von_wunschliste", 1.2)
	await press("a")
	await wait(0.8)
	# Trailer im eigenen Player, danach zurück auf die Seite
	await press("right")
	await shot("24b_trailer_knopf", 0.6)
	await press("a")
	await shot("25_trailer", 2.0)
	await press("b")
	await shot("26_nach_trailer", 2.0)
	await press("b")
	await wait(0.8)
	# Dieselbe Seite mit (selbst gemalten) Bildern
	view.open_item(Store.known_item(1145350))
	await shot("27_detail_mit_bildern", 3.0)
	await press("down")
	await shot("28_detail_mit_bildern_medien", 1.2)
	await press("right")
	await press("a")
	await shot("29_bild_gross", 1.2)
	await press("b")
	await press("b")
	await wait(0.8)
	main.goto("shop", "wunschliste")
	await shot("30_wunschliste", 1.2)
	await press("x")
	await shot("31_wunschliste_entfernt", 1.2)
	# Weitere Zustände der Seite: gekauft, kostenlos, bald, Erweiterung
	main.goto("shop", "entdecken")
	await wait(0.6)
	for pair in [[1086940, "32_gekauft"], [230410, "33_kostenlos"], [9000002, "34_bald"], [1622100, "35_erweiterung"]]:
		var it := Store.known_item(int(pair[0]))
		if it.is_empty():
			it = { "appid": int(pair[0]), "name": "" }
		view.open_item(it)
		await shot(str(pair[1]), 2.0)
		await press("b")
		await wait(0.5)


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
	var hero_src := OS.get_environment("UZAI_DEMO_ART").path_join("hero.jpg")
	for u in urls.keys():
		var dest := Config.path("cache/img/web/%s.jpg" % str(u).md5_text())
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var k: int = urls[u]
		var img: Image = null
		if k == 0 and FileAccess.file_exists(hero_src):
			img = Image.load_from_file(hero_src)
		if img == null:
			img = _paint(1280 if k != 9 else 600, 720 if k != 9 else 338, fposmod(hue + k * 0.045, 1.0), k)
		img.save_jpg(dest, 0.88)


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
