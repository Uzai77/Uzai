extends "res://tests/probe_base.gd"
## Probe „Nahtlose Übergänge“ (Punkt 90, Demo): je Übergang eine Bildfolge über den Flug, dazu ein
## Kontaktbild (alle Schritte nebeneinander) und daraus mit FFmpeg (UZAI_TEST_FFMPEG) ein kurzes
## GIF und WebM je Übergang.
##
## Die Zeit läuft dafür langsamer (Engine.time_scale): Jedes Bild wird genau dann aufgenommen, wenn
## der Flug einen bestimmten Stand erreicht hat – so zeigt die Folge den Flug, nicht die Pausen
## beim Speichern. Übergänge: Cover → Spielseite und zurück, Shop-Karte → Shop-Seite, Film-Plakat →
## Detailseite, Video → Player, Freund → Profil, Rückflug in eine geblätterte Bibliothek, B mitten
## im Flug, Rückfall ohne Karte, leichter Modus und „Animationen reduzieren“.
##
## Die Demo hat keine Bilder: Die Probe malt vorher Cover, große Bilder, Shop-Hüllen, Plakate,
## Vorschaubilder und Profilbilder und legt sie dorthin, wo Uzai sie findet.

const FlugS := preload("res://src/ui/flug.gd")
const Leicht := preload("res://src/core/leicht.gd")
const LANGSAM := 0.06           ## Zeitlupe während der Aufnahme
const SCHRITTE := 6             ## Bilder im Kontaktbild
const ANIM := 28                ## Bilder fürs Video

var _bilder := ""
var _bericht: Array = []


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	_bilder = Config.path("probe_bilder")
	DirAccess.make_dir_recursive_absolute(_bilder)
	await _saeen()
	main.goto("games")
	await wait(2.5)
	await shot("00_start", 0.3)

	# 1. Startseite: Cover → Spielseite und zurück.
	var gs: Control = main.sections.games
	await _waehle("g:", 2)
	await _folge("01_spielseite_auf", func() -> void: Nav._fire("a"))
	await wait(1.0)
	await _folge("02_spielseite_zu", func() -> void: Nav._fire("b"))
	await wait(1.0)

	# 2. Shop: Karte → Shop-Seite und zurück.
	main.goto("shop")
	await wait(4.0)
	var sk := await _waehle("shop:")
	if sk:
		await _folge("03_shop_auf", func() -> void: Nav._fire("a"))
		await wait(1.5)
		await _folge("04_shop_zu", func() -> void: Nav._fire("b"))
		await wait(1.0)

	# 3. Filme: Plakat → Detailseite und zurück.
	main.goto("movies")
	await wait(3.0)
	if await _waehle("m:", 0, "poster"):
		await _folge("05_film_auf", func() -> void: Nav._fire("a"))
		await wait(1.5)
		await _folge("06_film_zu", func() -> void: Nav._fire("b"))
		await wait(1.0)

	# 4. Videos: Vorschaubild → Player (Vorführung ohne mpv) und zurück.
	main.goto("videos")
	await wait(3.0)
	if await _waehle("v:"):
		await _folge("07_video_auf", func() -> void: Nav._fire("a"))
		await wait(1.5)
		await _folge("08_video_zu", func() -> void: Nav._fire("b"))
		await wait(1.0)

	# 5. Freunde: Profilbild → Profil (Y) und zurück.
	main.goto("friends")
	await wait(2.5)
	if await _waehle("fr:"):
		await _folge("09_freund_auf", func() -> void: Nav._fire("y"))
		await wait(1.5)
		await _folge("10_freund_zu", func() -> void: Nav._fire("b"))
		await wait(1.0)

	# 6. Bibliothek: Sie geht vor der Spielseite zu, das Cover fliegt trotzdem aus dem Raster.
	main.goto("games")
	await wait(1.5)
	main.open_library("alle", "Alle Spiele")
	await wait(2.0)
	await press("down", 2, 0.3)
	await wait(1.0)
	await _folge("11_bibliothek_auf", func() -> void: Nav._fire("a"))
	await wait(1.2)
	Nav._fire("b")
	await wait(1.5)

	# 7. Shop: Seite offen, dahinter rückt die Liste weiter (nachgeladen, neu sortiert) – das Bild
	# fliegt an die neue Stelle der Karte.
	main.goto("shop")
	await wait(2.0)
	var sk2 := await _waehle("shop:", 0, "", 260.0)
	if sk2:
		Nav._fire("a")
		await wait(1.6)
		var sc := _scroller(main.sections.shop)
		if sc:
			sc.scroll_vertical = int(sc.scroll_vertical + 300)
		await wait(0.4)
		await _folge("12_shop_zu_geblaettert", func() -> void: Nav._fire("b"))
		await wait(1.0)

	# 8. B mitten im Flug: Das Bild kehrt von dort um, wo es gerade ist.
	main.goto("games")
	await wait(1.5)
	await _waehle("g:", 3)
	await _folge("13_b_mitten_im_flug", func() -> void:
		Nav._fire("a")
		get_tree().create_timer(FlugS.T_AUF * 0.12).timeout.connect(func() -> void: Nav._fire("b"))
	, 0.0, true)
	await wait(1.5)

	# 9. Rückfall: Die Karte ist beim Schließen nicht mehr da (Startseite neu gebaut, anderes Spiel
	# vorn) – die Seite blendet nur aus.
	await _waehle("g:", 1)
	Nav._fire("a")
	await wait(1.5)
	var top: Control = Nav.top_layer()
	var key := str(top.get_meta("uz_flug", "")) if top else ""
	for n in gs.find_children("*", "Control", true, false):
		if key != "" and str(n.get_meta("uz_flug", "")) == key:
			n.set_meta("uz_flug", "weg")
	await _folge("14_rueckfall_ohne_karte", func() -> void: Nav._fire("b"))
	await wait(1.0)

	# 10. Leichter Modus (kürzer, ohne wachsenden Schatten) und „Animationen reduzieren“.
	main.goto("games")
	await wait(1.0)
	await _waehle("g:", 2)
	Leicht.active = true
	await _folge("15_leicht_auf", func() -> void: Nav._fire("a"))
	await wait(1.0)
	Nav._fire("b")
	await wait(1.0)
	Leicht.active = false
	Config.set_value("theme.reduce_motion", true)
	await _folge("16_reduziert_auf", func() -> void: Nav._fire("a"), 0.35)
	await wait(1.0)
	Nav._fire("b")
	await wait(1.0)
	Config.set_value("theme.reduce_motion", false)

	# 11. Eingaben im Flug: zweimal A schnell hintereinander öffnet eine Seite, nicht zwei; ein
	# „runter“ im selben Augenblick geht an die neue Seite.
	await _waehle("g:", 2)
	var vorher := Nav.layers.size()
	Nav._fire("a")
	Nav._fire("a")
	Nav._fire("down")
	await wait(1.0)
	_bericht.append(
			"Doppel-A: %d Ebene(n) neu (soll 1), Auswahl danach: %s" % [Nav.layers.size() - vorher, str(Nav.focused().get_meta("uz_key", Nav.focused().get_class()))
			if Nav.focused() else "-"])
	Nav._fire("b")
	await wait(1.0)

	var f := FileAccess.open(out.path_join("bericht.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_bericht) + "\n")
	f.close()
	print("\n".join(_bericht))


# --- Aufnahme -----------------------------------------------------------------------------------

## Einen Übergang in Zeitlupe aufnehmen: SCHRITTE Bilder fürs Kontaktbild (während der Bewegung,
## gleich: über die ganze Zeit verteilt), ANIM kleine Bilder fürs Video. Aufgenommen wird, bis alle
## Flüge gelandet und ausgeblendet sind (ohne Flug: min_s Sekunden Spielzeit).
func _folge(name: String, los: Callable, min_s := 0.0, gleich := false) -> void:
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var vorher := FlugS.protokoll.size()
	Engine.time_scale = LANGSAM
	await RenderingServer.frame_post_draw
	var bilder: Array = [_bild()]
	var zeiten: Array = [0.0]
	los.call()
	var t := 0.0
	var gesehen := false
	var ende := -1.0
	while t < 3.0:
		await RenderingServer.frame_post_draw
		t += get_process_delta_time()
		var laufend := _fluege()
		if not laufend.is_empty():
			gesehen = true
			ende = -1.0
		elif gesehen and ende < 0.0:
			ende = t
		bilder.append(_bild())
		zeiten.append(t)
		if ende >= 0.0 and t > ende + 0.12 and t > min_s:
			break
		if not gesehen and t > maxf(min_s, 0.25):
			break
	Engine.time_scale = 1.0
	await wait(0.5)
	bilder.append(_bild())
	zeiten.append(t + 0.05)
	_speichern(name, dir, bilder, zeiten, gleich)
	var neu: Array = FlugS.protokoll.slice(vorher)
	_bericht.append(
			"%s: %d Bilder über %.2f s, Flüge %s" % [name, bilder.size(), t, str(neu.map(func(p): return "%s/%s%s" % [p.key, p.art, " zurück" if p.zurueck else ""]))])


func _fluege() -> Array:
	var a: Array = []
	for k in FlugS._laufend.keys():
		var f: Variant = FlugS._laufend[k]
		if f != null and is_instance_valid(f):
			a.append(f)
	# Fertige Flüge stehen nicht mehr in _laufend, blenden aber noch aus.
	for n in main.layer_host.get_children():
		if n.get_script() == FlugS and not a.has(n):
			a.append(n)
	return a


func _bild() -> Image:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


## Aus allen Bildern: SCHRITTE für Kontaktbild und Einzelbilder, ANIM gleich verteilte fürs Video.
func _speichern(name: String, dir: String, bilder: Array, staende: Array, gleich := false) -> void:
	var n := bilder.size()
	var max_s: float = staende.back()
	var pick := func(ziel: float) -> int:
		var best := 0
		for i in n:
			if absf(float(staende[i]) - ziel) < absf(float(staende[best]) - ziel):
				best = i
		return best
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.03))
	# Die Feder bewegt sich in den ersten gut 0,3 s; danach schwingt sie nur noch aus. Darum vier
	# Bilder in dieser Zeit und als letztes das fertige Bild.
	var marken := [0.0, 0.07, 0.15, 0.24, 0.36]
	for s in SCHRITTE:
		var i: int = n - 1 if s >= marken.size() else pick.call(float(marken[s]) * FlugS.T_AUF)
		if gleich:
			i = pick.call(max_s * float(s) / float(SCHRITTE - 1))
		var img: Image = (bilder[i] as Image).duplicate()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.path_join("%s_%d.png" % [name, s + 1]))
		img.resize(636, 358, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, 636, 358), Vector2i(2 + (s % 3) * 639, 2 + (s / 3) * 360))
	sheet.save_png(out.path_join("%s_kontakt.png" % name))
	for a in ANIM:
		var i: int = pick.call(max_s * float(a) / float(ANIM - 1))
		var img: Image = (bilder[i] as Image).duplicate()
		img.convert(Image.FORMAT_RGB8)
		img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img.save_jpg(dir.path_join("%03d.jpg" % a), 0.92)
	_video(name, dir)
	print("Folge: ", name, " (", n, " Bilder)")


## GIF und WebM aus den Einzelbildern (FFmpeg aus UZAI_TEST_FFMPEG; fehlt es, nur die Bilder).
## Etwa halbe Geschwindigkeit, damit man den Flug sieht; am Ende steht das letzte Bild eine Sekunde.
func _video(name: String, dir: String) -> void:
	var ff := OS.get_environment("UZAI_TEST_FFMPEG")
	if ff == "" or not FileAccess.file_exists(ff):
		return
	var src := dir.path_join("%03d.jpg")
	var hold := "tpad=stop_mode=clone:stop_duration=1"
	var out_ := []
	OS.execute(ff, ["-y", "-loglevel", "error", "-framerate", "14", "-i", src, "-vf",
		hold + ",scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
		"-loop", "0", out.path_join(name + ".gif")], out_, true)
	OS.execute(ff, ["-y", "-loglevel", "error", "-framerate", "14", "-i", src, "-vf", hold, "-c:v", "libvpx-vp9",
		"-b:v", "0", "-crf", "32", "-pix_fmt", "yuv420p", out.path_join(name + ".webm")], out_, true)


# --- Finden -------------------------------------------------------------------------------------

## Karte wählen (n-te von links in der Reihe der besten, min_y: tiefer auf der Seite) und warten,
## bis die Liste sie ins Bild gerückt hat.
func _waehle(prefix: String, n := 0, art := "", min_y := 0.0) -> Control:
	var c := _karte_unter(prefix, Nav.scope_root(), art, n, min_y)
	if c == null:
		_bericht.append("keine Karte für " + prefix)
		return null
	Nav.focus(c, true)
	await wait(1.4)
	return c


func _karte_unter(prefix: String, root: Node, art := "", nth := 0, min_y := 0.0) -> Control:
	var vp := get_viewport().get_visible_rect()
	var alle: Array = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.has_meta("uz_flug") or not str(c.get_meta("uz_flug")).begins_with(prefix) or not c.is_visible_in_tree():
			continue
		if c.focus_mode == Control.FOCUS_NONE:
			continue
		if art != "" and str(c.get("mode")) != art:
			continue
		var r := c.get_global_rect()
		if r.position.y < min_y or r.position.y > vp.size.y * 2.5 or r.position.x < 0.0 or r.end.x > vp.size.x:
			continue
		if not c.has_method("flug_bild") or (c.call("flug_bild") as Dictionary).is_empty():
			continue
		alle.append(c)
	if alle.is_empty():
		return null
	# Oberste Reihe (gleiche Höhe ± 40), darin die n-te von links.
	alle.sort_custom(func(x: Control, y: Control) -> bool: return x.get_global_rect().position.y < y.get_global_rect().position.y)
	var top_y: float = (alle[0] as Control).get_global_rect().position.y
	var reihe := alle.filter(func(c: Control) -> bool: return absf(c.get_global_rect().position.y - top_y) < 40.0)
	reihe.sort_custom(func(x: Control, y: Control) -> bool: return x.get_global_rect().position.x < y.get_global_rect().position.x)
	return reihe[mini(nth, reihe.size() - 1)]


func _scroller(n: Node) -> ScrollContainer:
	for c in n.find_children("*", "ScrollContainer", true, false):
		var sc := c as ScrollContainer
		if sc.is_visible_in_tree() and sc.get_v_scroll_bar().max_value > sc.size.y + 100:
			return sc
	return null


# --- Bilder für die Demo ------------------------------------------------------------------------

func _saeen() -> void:
	var i := 0
	# Spiele: Cover und großes Bild im Medienordner (wie eigene Bilder).
	for g in Library.games:
		i += 1
		var hue := fposmod(i * 0.173, 1.0)
		var sys := str(g.get("system", ""))
		var name_ := Media.safe_name(str(g.get("title", "")))
		var cdir := Config.media_dir().path_join(sys).path_join("cover")
		var hdir := Config.media_dir().path_join(sys).path_join("hero")
		DirAccess.make_dir_recursive_absolute(cdir)
		DirAccess.make_dir_recursive_absolute(hdir)
		_maler(600, 900, hue, true).save_jpg(cdir.path_join(name_ + ".jpg"), 0.9)
		_maler(1920, 620, hue, false).save_jpg(hdir.path_join(name_ + ".jpg"), 0.88)
	Media._missing.clear()
	Media._local.clear()
	# Shop: Hüllen und Kapseln, als hätte Steam sie geschickt (wie probe_shopbilder.gd).
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
	var j := 0
	for id in ids.keys():
		j += 1
		var hue := fposmod(j * 0.137 + 0.05, 1.0)
		Media._assets[str(id)] = { "_t": now, "asset_url_format": "steam/apps/%d/${FILENAME}?t=1" % id,
			"library_capsule": "c0ffee/library_600x900.jpg", "main_capsule": "c0ffee/capsule_616x353.jpg" }
		_put(Media.STORE_ASSETS + "steam/apps/%d/c0ffee/library_600x900.jpg?t=1" % id, _maler(600, 900, hue, true))
		_put(Media.STORE_ASSETS + "steam/apps/%d/c0ffee/capsule_616x353.jpg?t=1" % id, _maler(616, 353, hue, false))
		_put(Store.CDN % [id, "capsule_616x353.jpg"], _maler(616, 353, hue, false))
		_put(Store.CDN % [id, "header.jpg"], _maler(460, 215, hue, false))
	# Filme: Plakat und Hintergrundbild als Dateien (die Demo hat nur Farbfelder).
	var k := 0
	var seen := {}
	for it in _alle_mit(Movies.get("_demo"), "poster"):
		var id := str(it.get("id", ""))
		if id == "":
			continue
		if not seen.has(id):
			k += 1
			var hue := fposmod(k * 0.211 + 0.6, 1.0)
			var pp := _bilder.path_join("poster_%s.jpg" % id.md5_text().substr(0, 10))
			var bp := _bilder.path_join("bild_%s.jpg" % id.md5_text().substr(0, 10))
			_maler(500, 750, hue, true).save_jpg(pp, 0.9)
			_maler(1600, 900, hue, false).save_jpg(bp, 0.88)
			seen[id] = [pp, bp]
		it["poster"] = seen[id][0]
		it["background"] = seen[id][1]
	# Videos: Vorschaubilder.
	var v_i := 0
	for list in [YouTube.feed, YouTube.trending, YouTube.recs, YouTube.shorts, YouTube.data.later, YouTube.data.history]:
		for v in list:
			v_i += 1
			var tp := _bilder.path_join("thumb_%s.jpg" % str(v.get("id", v_i)).md5_text().substr(0, 10))
			if not FileAccess.file_exists(tp):
				_maler(640, 360, fposmod(v_i * 0.29, 1.0), false).save_jpg(tp, 0.9)
			v["thumb"] = tp
	# Freunde: Profilbilder.
	var a_i := 0
	for fr in Social.steam_friends:
		a_i += 1
		var ap := _bilder.path_join("avatar_%d.png" % a_i)
		_gesicht(184, fposmod(a_i * 0.31, 1.0)).save_png(ap)
		fr["avatar"] = ap
	# Startseite neu, mit Bildern.
	Library.changed.emit()
	await wait(1.0)


func _alle_mit(v: Variant, key: String) -> Array:
	var out: Array = []
	if v is Dictionary:
		if (v as Dictionary).has(key):
			out.append(v)
		for x in (v as Dictionary).values():
			out.append_array(_alle_mit(x, key))
	elif v is Array:
		for x in v:
			out.append_array(_alle_mit(x, key))
	return out


func _put(url: String, img: Image) -> void:
	var dest := Config.path("cache/img/web/%s.jpg" % url.md5_text())
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	img.save_jpg(dest, 0.9)


## Gemalte Bilder: Himmel, Sonne, Berge und ein heller „Schriftzug“ (wie probe_shopbilder.gd).
func _maler(w: int, h: int, hue: float, tall: bool) -> Image:
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
			var yy := int(base - (sin(x * 0.013 * 1200.0 / w + layer * 1.7) * 0.5 + sin(x * 0.031 * 1200.0 / w + hue * 9.0) * 0.3 + 0.6) * h * 0.12)
			img.fill_rect(Rect2i(x, yy, 1, h - yy), col)
	var logo := Rect2i(int(w * 0.08), int(h * 0.08), int(w * 0.84), int(h * 0.09)) if tall else Rect2i(int(w * 0.06), int(h * 0.3), int(w * 0.42), int(h * 0.16))
	img.fill_rect(logo, Color(1, 1, 1, 1))
	img.fill_rect(Rect2i(logo.position + Vector2i(6, 6), logo.size - Vector2i(12, 12)), Color.from_hsv(hue, 0.7, 0.55))
	return img


## Ein schlichtes Profilbild: Farbfläche mit hellem Kreis (Kopf) und Bogen (Schultern).
func _gesicht(s: int, hue: float) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var bg := Color.from_hsv(hue, 0.55, 0.55)
	img.fill(bg)
	var fg := Color.from_hsv(fposmod(hue + 0.5, 1.0), 0.25, 0.95)
	var cx := s / 2
	for y in s:
		for x in s:
			var p := Vector2(x - cx, y - s * 0.4)
			var q := Vector2(x - cx, y - s * 1.05)
			if p.length() < s * 0.2 or q.length() < s * 0.42:
				img.set_pixel(x, y, fg)
	return img
