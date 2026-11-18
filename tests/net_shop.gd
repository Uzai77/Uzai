extends Node
## Netz-Probe für die Bilder im Shop: spricht mit einem nachgebauten Steam-Store
## (tests/fake_steam_store.py: GetItems mit Bildangaben und die Bildserver). Geprüft wird, dass
## Uzai die echten Bildnamen gebündelt holt und zwischenspeichert, neue Spiele (Bilder im Ordner
## mit Prüfsumme) als Hülle zeigt, sonst sauber auf die alten Adressen zurückfällt und ein
## Querformat-Bild in der Hochformat-Karte nicht verzerrt.
## Aufruf (eigener, leerer Datenordner; startet den Server selbst, wenn keine Adresse gesetzt ist):
##   UZAI_DATA=<ordner> godot --headless --path . res://tests/net_shop.tscn
## oder mit eigenem Server:
##   python3 tests/fake_steam_store.py 18767 &
##   UZAI_DATA=<ordner> UZAI_STEAM_API=http://127.0.0.1:18767 UZAI_STEAM_CDN=http://127.0.0.1:18767 \
##     godot --headless --path . res://tests/net_shop.tscn

const ShopCard := preload("res://src/ui/components/shop_card.gd")
const PORT := 18767

var fails := 0
var base := ""
var _pid := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_STEAM_API")
	if base == "":
		base = "http://127.0.0.1:%d" % PORT
		_pid = OS.create_process("python3", [ProjectSettings.globalize_path("res://tests/fake_steam_store.py"), str(PORT)])
		OS.set_environment("UZAI_STEAM_API", base)
		OS.set_environment("UZAI_STEAM_CDN", base)
		for i in 50:
			await get_tree().create_timer(0.1).timeout
			if (await Net.get_json(base + "/__reset")).ok:
				break
	if OS.get_environment("UZAI_STEAM_CDN") == "":
		OS.set_environment("UZAI_STEAM_CDN", base)
	await _run()
	if _pid > 0:
		OS.kill(_pid)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _log() -> Array:
	var r := await Net.get_json(base + "/__log")
	return r.data if r.data is Array else []


func _reset() -> void:
	await Net.get_json(base + "/__reset")


static func _count(log: Array, part: String) -> int:
	var n := 0
	for e in log:
		if (str(e.p) + "?" + str(e.q)).contains(part):
			n += 1
	return n


## Bilderkette wie in der Karte laden und auf das Ergebnis warten.
func _chain(urls: Array, max_w := 400) -> Texture2D:
	var box := { "done": false, "tex": null }
	Media.url_texture_chain(urls, max_w, func(t: Texture2D) -> void:
		box.tex = t
		box.done = true
	)
	for i in 200:
		if box.done:
			break
		await get_tree().create_timer(0.05).timeout
	return box.tex


## Seitenverhältnis eines geladenen Bildes (Uzai rechnet es auf die Kartenbreite klein).
static func _ratio(t: Texture2D, w: float, h: float) -> bool:
	return absf(float(t.get_width()) / t.get_height() - w / h) < 0.01


func _wait_assets(ids: Array) -> void:
	for i in 200:
		var busy := false
		for id in ids:
			if Media._asset_waiting.has(str(id)):
				busy = true
		if not busy:
			return
		await get_tree().create_timer(0.05).timeout


func _run() -> void:
	await _reset()
	print("Bildangaben gebündelt holen")
	Media.prefetch_steam_assets([100, 200, 300, 400, 200])
	await _wait_assets([100, 200, 300, 400])
	var log := await _log()
	check(_count(log, "/IStoreBrowseService/GetItems/v1/") == 1, "eine Anfrage für vier Spiele (%d)" % _count(log, "GetItems"))
	var q := str(log[0].q).uri_decode() if not log.is_empty() else ""
	check(q.contains("\"appid\":100") and q.contains("\"appid\":400") and q.contains("\"include_assets\":true") and q.contains("\"country_code\":\"DE\"")
			and q.contains("\"language\":\"german\""), "Anfrage mit allen IDs, Bildangaben, Sprache und Land")
	var a200 := Media.cached_steam_assets(200)
	check(str(a200.get("library_capsule", "")) == "a1b2c3/library_600x900.jpg" and int(a200.get("_t", 0)) > 0,
			"neues Spiel: Hülle im Ordner mit Prüfsumme, mit Zeitstempel gemerkt")
	check(Media.cached_steam_assets(400).has("_t") and not Media.cached_steam_assets(400).has("asset_url_format"), "unbekanntes Spiel: als „keine Bilder“ gemerkt")
	Media.save_assets_now()     # gebündeltes Speichern sofort auslösen
	var file: Variant = Config.read_json(Config.path(Media.ASSETS_FILE), {})
	check(file is Dictionary and (file as Dictionary).has("200") and (file as Dictionary).has("300"), "im Datei-Speicher (cache/steam_assets.json)")

	print("Bilder für die Karten")
	await _reset()
	var t200 := await _chain(Store.art_urls({ "appid": 200, "capsule": Store.CDN % [200, "capsule_616x353.jpg"] }, true, 400))
	log = await _log()
	check(t200 != null and _ratio(t200, 600, 900), "neues Spiel: Hülle (600 × 900) statt Querformat")
	check(_count(log, "/apps/200/a1b2c3/library_600x900.jpg") == 1 and _count(log, "/apps/200/library_600x900") == 0,
			"direkt die echte Adresse, keine Fehlgriffe auf die alte")
	var t100 := await _chain(Store.art_urls({ "appid": 100 }, true, 900))
	check(t100 != null and t100.get_size().y > t100.get_size().x, "altes Spiel: Hülle wie bisher")
	await _reset()
	var t300 := await _chain(Store.art_urls({ "appid": 300, "capsule": Store.CDN % [300, "capsule_616x353.jpg"] }, true, 400))
	log = await _log()
	check(t300 != null and _ratio(t300, 616, 353), "Spiel ohne Hülle: Kapsel")
	check(_count(log, "/apps/300/library") == 0, "dabei keine Anfrage nach einer Hülle, die es nicht gibt")
	await _reset()
	var it400 := { "appid": 400, "capsule": Store.CDN % [400, "capsule_616x353.jpg"], "header": Store.CDN % [400, "header.jpg"] }
	var t400 := await _chain(Store.art_urls(it400, true, 400))
	log = await _log()
	check(t400 != null and _ratio(t400, 616, 353) and _count(log, "/apps/400/library_600x900") == 2,
			"Steam kennt das Spiel nicht: alte Adressen versucht, dann Kapsel")
	await _reset()
	await _chain(Store.art_urls(it400, true, 400))
	log = await _log()
	check(_count(log, "/apps/400/library_600x900") == 0, "beim nächsten Aufbau keine Fehlgriffe mehr (eben erst gescheitert)")

	print("Seite eines Spiels")
	await _reset()
	var hero := await _chain(Store.hero_urls(200, Media.cached_steam_assets(200), 1920), 1920)
	var logo := await _chain(Store.logo_urls(200, Media.cached_steam_assets(200)), 1000)
	log = await _log()
	check(hero != null and hero.get_size() == Vector2(1920, 620) and _count(log, "/apps/200/a1b2c3/library_hero.jpg") == 1,
			"großes Bild aus dem Ordner mit Prüfsumme")
	check(logo != null and logo.get_size() == Vector2(640, 360), "Schriftzug aus dem Ordner mit Prüfsumme")

	print("Speicher und Ablauf")
	Media.save_assets_now()
	Media._assets = {}
	Media._assets_loaded = false
	await _reset()
	var again := await Media.steam_assets(200)
	log = await _log()
	check(str(again.get("library_capsule", "")) == "a1b2c3/library_600x900.jpg" and _count(log, "GetItems") == 0, "nach dem Neustart aus der Datei, ohne Anfrage")
	(Media._assets["200"] as Dictionary)["_t"] = int(Time.get_unix_time_from_system()) - 8 * 86400
	var stale := await Media.steam_assets(200)
	check(str(stale.get("library_capsule", "")) != "", "alte Angaben sofort nutzbar")
	await _wait_assets([200])
	log = await _log()
	check(_count(log, "GetItems") == 1 and Media.assets_fresh(Media.cached_steam_assets(200), int(Time.get_unix_time_from_system())),
			"nach einer Woche im Hintergrund aufgefrischt")

	print("Steam antwortet nicht")
	await _reset()
	await Net.get_json(base + "/__set?fail=1")
	var got500 := await Media.steam_assets(500)
	check(got500.is_empty() and Media._asset_failed.has("500"), "Fehler: keine Angaben, Zeitpunkt gemerkt")
	await Media.steam_assets(500)
	Media.prefetch_steam_assets([500])
	await get_tree().create_timer(0.3).timeout
	log = await _log()
	check(_count(log, "GetItems") == 1, "nicht bei jedem Aufbau neu fragen (%d)" % _count(log, "GetItems"))
	await Net.get_json(base + "/__set?fail=0&delay=3")
	var box := { "a": null, "at": 0 }
	var t0 := Time.get_ticks_msec()
	Media.with_steam_assets(600, func(a: Dictionary) -> void:
		box.a = a
		box.at = Time.get_ticks_msec() - t0
	, 1.0)
	for i in 60:
		if box.a != null:
			break
		await get_tree().create_timer(0.05).timeout
	check(box.a is Dictionary and (box.a as Dictionary).is_empty() and int(box.at) < 1800, "Karte wartet höchstens kurz (%d ms), dann alte Adressen" % int(box.at))
	await _wait_assets([600])
	check(Media.cached_steam_assets(600).has("_t"), "späte Antwort landet trotzdem im Speicher")
	await Net.get_json(base + "/__set?delay=0")

	print("Shop-Einträge aus GetItems")
	await _reset()
	Media._assets.erase("300")
	var items := await Store._items([200, 300])
	log = await _log()
	check(items.size() == 2 and str(items[0].capsule).contains("/200/a1b2c3/capsule_616x353.jpg") and str(items[0].header).contains("/200/a1b2c3/header.jpg"),
			"Kapsel und Kopfbild mit Prüfsumme")
	check(_count(log, "include_assets") == 1 and _count(log, "include_all_purchase_options") == 1, "Preise und Bilder in einer Anfrage")
	check(Media.cached_steam_assets(300).has("main_capsule"), "Bildangaben daraus mit gemerkt")

	print("Karte im Shop")
	var cards := {}
	for id in [200, 300]:
		var c = ShopCard.new().setup(
				{ "appid": id, "name": "Spiel %d" % id, "capsule": Store.CDN % [id, "capsule_616x353.jpg"], "header": Store.CDN % [id, "header.jpg"], "price": 999 }, 228.0)
		add_child(c)
		cards[id] = c
	for i in 100:
		if cards[200]._img.get("texture") != null and cards[300]._img.get("texture") != null:
			break
		await get_tree().create_timer(0.05).timeout
	var tex200: Texture2D = cards[200]._img.get("texture")
	var tex300: Texture2D = cards[300]._img.get("texture")
	check(tex200 != null and tex200.get_height() > tex200.get_width() and not bool(cards[200]._img.call("fitted")), "Hochformat-Karte mit Hülle: randvoll")
	check(tex300 != null and tex300.get_width() > tex300.get_height() and bool(cards[300]._img.call("fitted")),
			"Hochformat-Karte mit Querbild: ganz gezeigt statt gestreckt")
	for c in cards.values():
		(c as Node).queue_free()
