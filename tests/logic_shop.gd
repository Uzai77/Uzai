extends Node
## Logiktests für den Shop (ohne Oberfläche und ohne Netz): Trailer, Editionen, Preise,
## Systemanforderungen, Bewertungen, Neuigkeiten, Antworten der Steam-Dienste.
## Aufruf: godot --headless --path . res://tests/logic_shop.tscn

const StoreGame := preload("res://src/ui/layers/store_game.gd")
const Icons := preload("res://src/core/icons.gd")
const ShopView := preload("res://src/ui/sections/shop_view.gd")
const Lang := preload("res://src/core/lang.gd")
const ShopCard := preload("res://src/ui/components/shop_card.gd")
const ShopArt := preload("res://src/ui/components/shop_art.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Trailer")
	var mv := Store.parse_movies([
		{ "id": 1, "name": "Launch", "thumbnail": "http://x/movie.293x165.jpg", "hls_h264": "http://video/hls_h264_master.m3u8",
			"dash_h264": "https://video/dash.mpd", "highlight": true },
		{ "id": 2, "name": "Alt", "mp4": { "480": "https://cdn/movie480.mp4", "max": "https://cdn/movie_max.mp4" }, "webm": { "max": "https://cdn/movie_max.webm" } },
		{ "id": 3, "name": "Nur DASH", "dash_av1": "https://video/av1.mpd" },
		{ "id": 4, "name": "Nichts" },
		"kaputt",
	])
	check(mv.size() == 3, "Trailer ohne Adresse fallen weg")
	check(str(mv[0].url) == "https://video/hls_h264_master.m3u8" and str(mv[0].thumb).begins_with("https://"), "HLS zuerst, immer https")
	check(str(mv[1].url) == "https://cdn/movie_max.mp4", "ältere Einträge: mp4 in bester Qualität")
	check(str(mv[2].url) == "https://video/av1.mpd", "zur Not DASH")
	check(Store.parse_movies(null).is_empty() and Store.parse_movies({}).is_empty(), "keine Trailer: leere Liste")
	var tv := Store.trailer_video({ "name": "Outer Wilds", "appid": 753640 }, mv[0])
	check(str(tv.id) == "steam-trailer-1" and str(tv.url) == str(mv[0].url) and str(tv.title) == "Outer Wilds – Launch", "Trailer als Eintrag für den Videoplayer")
	check(str(Store.trailer_video({ "name": "Hades" }, { "id": 5, "name": "hades", "url": "u" }).title) == "Hades", "kein doppelter Name im Titel")
	check(Video.url({ "id": "x", "url": "https://video.invalid/trailer.m3u8" }) == "https://video.invalid/trailer.m3u8", "der Videoplayer spielt direkte Adressen (Trailer)")

	print("Editionen und Preise")
	var eds := Store.parse_editions({ "package_groups": [
		{ "name": "subscriptions", "subs": [{ "packageid": 9, "option_text": "Abo - 4,99€", "price_in_cents_with_discount": 499 }] },
		{ "name": "default", "subs": [
			{ "packageid": 336209, "percent_savings_text": "-50% ", "option_text": "Outer Wilds - <span class=\"discount_original_price\">24,99€</span> 12,49€",
				"price_in_cents_with_discount": 1249 },
			{ "packageid": 600001, "percent_savings_text": "", "option_text": "Deluxe - Edition - 34,99€", "price_in_cents_with_discount": 3499 },
			{ "packageid": 0, "option_text": "kaputt" },
		] },
	] })
	check(eds.size() == 2 and int(eds[0].packageid) == 336209, "Gruppe „default“, Pakete ohne ID fallen weg")
	check(str(eds[0].name) == "Outer Wilds" and int(eds[0].price) == 1249 and int(eds[0].original) == 2499 and int(eds[0].discount) == 50,
			"Name, Preis, alter Preis, Rabatt")
	check(str(eds[1].name) == "Deluxe - Edition" and int(eds[1].discount) == 0 and int(eds[1].original) == 3499, "Name mit Bindestrich bleibt ganz")
	check(Store.parse_editions({}).is_empty() and Store.parse_editions({ "package_groups": "x" }).is_empty(), "ohne Kaufoptionen: leer")
	check(Store.cents_of("24,99€") == 2499 and Store.cents_of("1.249,99 €") == 124999 and Store.cents_of("$9.99") == 999 and Store.cents_of("5€") == 500,
			"Preistext in Cent")
	check(Store.price_text(1249) == "12,49 €" and Store.price_text(0) == "Kostenlos" and Store.price_text(5) == "0,05 €", "Preis als Text")
	# Das Land für die Preise ist eine Einstellung (Standard: nach der Sprache). Adressen und Währung folgen ihr.
	var keep_land: Variant = Config.get_value("system.country", "auto")
	Config.set_value("system.country", "auto")
	check(Store._url(Store.FEATURED).contains("cc=DE&") and Store._url(Store.SEARCH).ends_with("&cc=DE") and not Store._url(Store.PRICES).contains("{"),
			"Shop fragt mit dem Land der Sprache (Deutsch: DE)")
	check(Store._url(Store.EPIC_FREE).contains("country=DE&allowCountries=DE"), "Epic-Gratisliste ebenso")
	Config.set_value("system.country", "US")
	check(Store._url(Store.FEATURED).contains("cc=US&") and Store._url(Store.DETAILS).contains("cc=US&") and Store._url(Store.GENRE).contains("cc=US&")
			and Store._url(Store.EPIC_FREE).contains("country=US&allowCountries=US"), "Land USA: alle Adressen mit US")
	check(Store.price_text(1249) == "12,49 $" and Store.price_text(1249, "EUR") == "12,49 €" and Store.price_text(0) == "Kostenlos",
			"Preis ohne Angabe in der Währung des Landes, mit Angabe in der des Eintrags")
	check(load("res://src/library/epic_online.gd").bulk_url("https://h", "ns", ["a"]).contains("&country=US&"), "Epic-Katalog mit dem Land")
	Config.set_value("system.country", keep_land)
	check(Store.num_text(41237) == "41.237" and Store.num_text(999) == "999" and Store.num_text(1234567) == "1.234.567", "große Zahlen mit Punkt")
	var items := Store.parse_items([{ "id": 7, "name": "Bald", "final_price": null, "original_price": null }], true)
	check(items.size() == 1 and items[0].coming and int(items[0].price) == 0, "Liste „Bald“: ohne Preis, als bald markiert")
	check(ShopCard.status_line(items[0], false) == "Bald erhältlich", "Karte sagt „Bald erhältlich“ statt „Kostenlos“")
	check(ShopCard.status_line({ "price": 0, "original": 0, "free": true }, false) == "Kostenlos spielbar"
			and ShopCard.status_line({}, true) == "In deiner Bibliothek", "Zeile unter der Karte")
	check(ShopCard.status_line({ "price": 0, "original": 0 }, false) == "", "Preis 0 ohne is_free: nicht „Kostenlos“")

	print("Preise nachfragen (Reihe „Weil du … spielst“, Genres, Suche)")
	# getappsingenre schickt zu den Spielen nur 0 – das ist kein Preis, sondern keiner.
	var gl := Store.parse_items(
			[{ "id": 1086940, "type": 0, "name": "Baldur's Gate 3", "discount_percent": 0, "original_price": 0, "final_price": 0, "currency": "EUR" },
		{ "id": 230410, "type": 0, "name": "Warframe", "final_price": 0 }, { "id": 9, "type": 1, "name": "Paket" }])
	check(gl.size() == 2 and not gl[0].free and Store.price_label(gl[0]) == "" and Store.needs_price(gl[0]),
			"Liste mit 0: kein Preis, kein „Kostenlos“, wird nachgefragt")
	var pb := Store.parse_price_batch({
		"1086940": { "success": true,
			"data": { "price_overview": { "currency": "EUR", "initial": 5999, "final": 4199, "discount_percent": 30, "final_formatted": "41,99€" } } },
		"230410": { "success": true, "data": [] },
		"5": { "success": false },
		"x": { "success": true, "data": { "price_overview": { "final": 1 } } },
		"7": "kaputt",
		"8": { "success": true, "data": { "price_overview": { "currency": "EUR", "final": 999.0 } } },
	})
	check(pb.size() == 3 and bool(pb[1086940].has_price) and int(pb[1086940].price) == 4199 and int(pb[1086940].original) == 5999
			and int(pb[1086940].discount) == 30, "appdetails (price_overview): Preis in Cent, alter Preis, Rabatt")
	check(not bool(pb[230410].has_price) and not pb.has(5) and int(pb[8].price) == 999 and int(pb[8].original) == 999,
			"data: [] heißt kein Preis; Fehlschläge fehlen; ohne initial gilt final")
	check(Store.parse_price_batch(null).is_empty() and Store.parse_price_batch([]).is_empty(), "kaputte Antwort: leer")
	var changed := Store.apply_prices(gl, { 1086940: pb[1086940], 230410: { "has_price": false, "free": true } })
	check(changed and int(gl[0].price) == 4199 and int(gl[0].discount) == 30 and Store.price_label(gl[0]) == "41,99 €" and not Store.needs_price(gl[0]),
			"nachgefragter Preis landet im Eintrag")
	check(bool(gl[1].free) and Store.price_label(gl[1]) == "Kostenlos" and ShopCard.status_line(gl[1], false) == "Kostenlos spielbar",
			"„Kostenlos“ nur mit echtem is_free (GetItems)")
	var soon := Store.parse_items([{ "id": 77, "name": "Bald", "final_price": null }], true)
	Store.apply_prices(soon, { 77: { "has_price": false } })
	check(not Store.needs_price(soon[0]) and Store.price_label(soon[0]) == "" and not soon[0].free,
			"ohne Preis bei Steam: gar kein Preis (und nicht noch einmal fragen)")
	check(not Store.needs_price({ "appid": 3, "price": 0, "free": true }) and not Store.needs_price({ "appid": 3, "price": 999 })
			and not Store.needs_price({ "appid": 0 }), "Kostenlose und bepreiste Einträge fragt Uzai nicht nach")
	var sr := Store.parse_search_item({ "id": 570, "type": "app", "name": "Dota 2" })
	var sp := Store.parse_search_item({ "id": 753640, "name": "Outer Wilds", "price": { "currency": "EUR", "initial": 2499, "final": 1249 } })
	check(Store.price_label(sr) == "" and Store.needs_price(sr) and int(sp.price) == 1249 and int(sp.discount) == 50 and not Store.needs_price(sp),
			"Suche: ohne „price“ offen, mit Preis gleich fertig")
	var gi := Store.from_store_item({ "appid": 570, "name": "Dota 2", "is_free": true })
	var gn := Store.from_store_item({ "appid": 12, "name": "Ohne Kaufoption" })
	check(bool(gi.free) and Store.price_label(gi) == "Kostenlos" and Store.price_label(gn) == "" and not Store.needs_price(gn),
			"GetItems: is_free zählt, ohne Kaufoption kein Preis")
	check(ShopCard.status_line(gn, false) == "" and Store.price_label({ "price": 1999 }) == "19,99 €", "alte Einträge mit Preis bleiben, wie sie sind")
	var srt := Store.sorted([{ "appid": 1, "price": 0 }, { "appid": 2, "price": 500 }, { "appid": 3, "price": 0, "free": true }], "preis")
	check(int(srt[0].appid) == 3 and int(srt[1].appid) == 2 and int(srt[2].appid) == 1, "nach Preis: kostenlos zuerst, ohne Preis zum Schluss")
	check(Store.unique([{ "appid": 1 }, { "appid": 2 }, { "appid": 1 }]).size() == 2, "jedes Spiel nur einmal")

	print("Angaben aus dem Store")
	var html := "<strong>Mindestanforderungen:</strong><br><ul class=\"bb_ul\"><li>Erfordert einen 64-Bit-Prozessor<br></li><li><strong>Betriebssystem:</strong> Windows 10<br></li><li><strong>Grafik:</strong> GTX 660<br>oder besser</li><li><strong>Speicherplatz:</strong> 8 GB verfügbarer Speicherplatz</li></ul>"
	var req := Store.parse_requirements(html)
	check(req.size() == 4 and str(req[0][0]) == "" and str(req[1][0]) == "Betriebssystem" and str(req[1][1]) == "Windows 10",
			"Systemanforderungen als Zeilen, Hinweis ohne Bezeichnung")
	check(str(req[2][1]) == "GTX 660 oder besser", "Zeilenumbrüche im Wert werden Leerzeichen")
	check(Store.parse_requirements("").is_empty() and Store.parse_requirements("Betriebssystem: Windows 11").size() == 1, "leer und ohne Liste")
	var main_rows := StoreGame._req_main(req)
	check(main_rows.size() == 3 and str(main_rows[0][0]) == "Betriebssystem", "wichtigste Zeilen in fester Reihenfolge")
	check(Store.voiced("Englisch<strong>*</strong>, Deutsch<strong>*</strong>", ["deutsch", "german"])
			and not Store.voiced("Englisch<strong>*</strong>, Deutsch", ["deutsch", "german"]), "deutsche Sprachausgabe erkannt")
	var det := Store.parse_details({ "name": "X", "type": "dlc", "pc_requirements": [], "dlc": [5, 6], "fullgame": { "appid": "42", "name": "Basis" },
		"achievements": { "total": 31 }, "controller_support": "full", "ratings": { "usk": { "rating": "12" } }, "movies": [{ "id": 1, "hls_h264": "https://v" }] })
	check(det.req_min.is_empty() and det.dlc == 2 and det.dlc_ids == [5, 6] and int(det.fullgame.appid) == 42,
			"Anforderungen als leere Liste (Steam schickt dann [])")
	check(int(det.achievements) == 31 and str(det.controller) == "full" and int(det.age) == 12 and (det.movies as Array).size() == 1,
			"Erfolge, Controller, Freigabe, Trailer")
	check(StoreGame._year("18. Juni 2020") == "2020" and StoreGame._year("Bald") == "", "Jahr aus dem Datum")
	# Die anderen Seiten des Spiels bei Steam (Diskussionen, Artworks …), Workshop nur, wenn es einen gibt.
	var seiten := Store.steam_seiten(730)
	var ids: Array = seiten.map(func(s: Dictionary) -> String: return str(s.id))
	check(ids == ["diskussionen", "guides", "artworks", "screenshots", "videos", "hub"], "Steam-Seiten: Diskussionen bis Community-Hub, ohne Workshop")
	check(str(seiten[0].url) == "https://steamcommunity.com/app/730/discussions/?l=" + str(Lang.api("steam")),
			"Adresse der Diskussionen mit der Sprache der Oberfläche")
	check(str(seiten[2].url).begins_with("https://steamcommunity.com/app/730/images/"), "Artworks liegen unter images/")
	check(Store.steam_seiten(730, true).any(func(s: Dictionary) -> bool: return str(s.id) == "workshop"), "mit Workshop, wenn das Spiel einen hat")
	check(Store.steam_seiten(0).is_empty() and Store.steam_seiten(-5, true).is_empty(), "ohne gültige Nummer keine Seiten")
	check(bool(Store.parse_details({ "categories": [{ "id": 30, "description": "Steam Workshop" }] }).workshop)
			and not bool(det.workshop), "Workshop aus den Kategorien des Shops erkannt")
	for s in Store.steam_seiten(730, true):
		check(Icons.P.has(str(s.icon)), "Symbol „%s“ gibt es" % str(s.icon))

	print("Suche mit Kategorien")
	# Form der Antwort wie von Steam (search/results, json=1): nur Name und Bild; die Nummer steht in der Adresse.
	var roh := { "desc": "", "items": [
		{ "name": "Portal", "logo": "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/400/capsule_sm_120.jpg?t=1745368554" },
		{ "name": "Portal 2", "logo": "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/620/bd23943dcd0280aa2cdc066e2f86d2185cfd4cce/capsule_sm_120.jpg?t=1" },
		{ "name": "Ein Paket", "logo": "https://shared.fastly.steamstatic.com/store_item_assets/steam/subs/802975/capsule_sm_120.jpg?t=1690303827" },
		{ "name": "", "logo": "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/5/capsule_sm_120.jpg" },
		{ "name": "Ohne Bild" }, { "name": 7, "logo": 9 }, "Unsinn", null,
		{ "name": "Portal Knights", "logo": "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/374040/capsule_sm_120_german.jpg?t=1793371507" },
	] }
	var gef := Store.parse_suche_gefiltert(roh)
	check(gef.size() == 3 and int(gef[0].appid) == 400 and int(gef[1].appid) == 620 and int(gef[2].appid) == 374040,
			"Treffer: Nummer aus der Adresse des Bilds, Pakete und Unlesbares bleiben weg")
	check(str(gef[1].name) == "Portal 2" and Store.needs_price(gef[1]) and str(gef[1].capsule).contains("/apps/620/"),
			"Treffer ohne Preis: der wird nachgefragt; Bilder wie bei den anderen Listen")
	check(Store.parse_suche_gefiltert(roh, 2).size() == 2 and Store.parse_suche_gefiltert(null).is_empty()
			and Store.parse_suche_gefiltert({ "items": "x" }).is_empty() and Store.parse_suche_gefiltert([1]).is_empty(), "Obergrenze; Unsinn gibt eine leere Liste")
	check(Store.such_tags([19, "1685", 19, 77777, null, 3.5, "x", 122, 9]) == [19, 1685, 122],
			"Kategorien für die Adresse: nur bekannte Nummern, jede einmal, höchstens %d" % Store.SUCH_TAGS_MAX)
	check(Store.such_tags("19").is_empty() and Store.such_tags([]).is_empty(), "keine Liste: keine Kategorien")
	var nummern := {}
	for k in Store.SUCH_KATEGORIEN:
		nummern[int(k[0])] = true
		check(int(k[0]) > 0 and str(k[1]) != "", "Kategorie „%s“ hat Nummer und Namen" % str(k[1]))
	check(nummern.size() == Store.SUCH_KATEGORIEN.size(), "keine Nummer doppelt")
	check(Store.such_tag_namen([1685, 19]) == "Action, Koop" and Store.such_tag_namen([]) == "", "Namen in der Reihenfolge der Liste")
	check(ShopView.kategorien_nach([], 19) == [19] and ShopView.kategorien_nach([19], 19) == [] and ShopView.kategorien_nach([19, 21], 0) == [],
			"Kategorie zuschalten, abschalten, „Alle“ leert")
	check(ShopView.kategorien_nach([19, 21, 122], 9) == [21, 122, 9], "mehr als %d: die älteste weicht" % Store.SUCH_TAGS_MAX)
	check(ShopView.such_kopf(12, "portal", "Action, Koop") == "12 Treffer für „portal“ in Action, Koop"
			and ShopView.such_kopf(1, "portal", "") == "1 Treffer für „portal“", "Zeile über den Treffern mit und ohne Kategorien")
	check(ShopView.such_kopf(5, "", "Action") == "Beliebt in Action" and ShopView.such_kopf(0, "", "Action") == "Keine Treffer in Action."
			and ShopView.such_kopf(0, "x", "") == "Keine Treffer für „x“." and ShopView.such_kopf(0, "x", "Action") == "Keine Treffer für „x“ in Action.",
			"ohne Suchwort „Beliebt in …“, ohne Treffer sagt die Zeile, wo gesucht wurde")

	print("Bewertungen und Neuigkeiten")
	var rv := Store.parse_review_texts({ "reviews": [
		{ "voted_up": true, "review": "kurz", "author": { "playtime_at_review": 60 } },
		{ "voted_up": false, "review": "[b]Zu schwer[/b] für mich, aber wunderschön gemacht. [spoiler]Ende[/spoiler] Trotzdem lohnt es sich.",
			"author": { "playtime_at_review": 600 }, "timestamp_created": 1700000000 },
	] }, 3)
	check(rv.size() == 1 and not rv[0].up and is_equal_approx(float(rv[0].hours), 10.0), "zu kurze Bewertungen fallen weg, Spielzeit in Stunden")
	check(not str(rv[0].text).contains("[") and str(rv[0].text).begins_with("Zu schwer"), "BB-Code raus")
	var news := Store.parse_news({ "appnews": { "newsitems": [
		{ "title": "Update &amp; mehr", "date": 1758300000,
			"contents": "[h2]Neu[/h2][list][*]Kamera[*]Logbuch[/list][img]{STEAM_CLAN_IMAGE}/1/a.png[/img]Viel Spaß!" },
		{ "title": "", "contents": "ohne Titel" },
	] } }, 3)
	check(news.size() == 1 and str(news[0].title) == "Update & mehr", "Neuigkeiten mit Titel, HTML-Zeichen lesbar")
	check(str(news[0].text).contains("• Kamera") and not str(news[0].text).contains("STEAM_CLAN_IMAGE") and str(news[0].text).ends_with("Viel Spaß!"),
			"Aufzählungen bleiben, Bilder fallen weg")
	check(Store.parse_news(null).is_empty() and Store.parse_review_texts({}).is_empty(), "kaputte Antworten: leer")
	check(Store._strip_html("A<br/>B &amp; C &lt;x&gt; &quot;d&quot;<p>E</p>  \n\n\n\nF") == "A\nB & C <x> \"d\"E\n\nF", "HTML: Umbrüche, Zeichen, Leerzeilen – "
			+ Store._strip_html("A<br/>B &amp; C &lt;x&gt; &quot;d&quot;<p>E</p>  \n\n\n\nF").c_escape())
	check(Store._strip_html("&amp;lt;b&amp;gt;") == "&lt;b&gt;", "HTML: „&amp;“ wird zuletzt gelesen (nichts doppelt)")
	check(Store.clean_text("[h1]Neu[/h1][list][*]Eins[*]Zwei[/list][img]x.png[/img][url=https://x.example]hier[/url] {STEAM_CLAN_IMAGE}/1/a.png") == "Neu\n\n• Eins\n• Zwei\nhier",
			"BB-Code: Überschrift, Liste, Bild und Link – " + Store.clean_text("[h1]Neu[/h1][list][*]Eins[*]Zwei[/list][img]x.png[/img][url=https://x.example]hier[/url] {STEAM_CLAN_IMAGE}/1/a.png").c_escape())
	check(StoreGame._short("Ein langer Satz mit vielen Wörtern darin", 20) == "Ein langer Satz mit …" and StoreGame._short("kurz", 20) == "kurz",
			"Kacheltext am Wortende gekürzt")

	print("Bildadressen aus dem Store")
	# So antwortet GetItems für ein neues Spiel: Bilder in einem Ordner mit Prüfsumme.
	var neu := { "asset_url_format": "steam/apps/3527290/${FILENAME}?t=1750000000",
		"main_capsule": "9f3c/capsule_616x353.jpg", "header": "9f3c/header.jpg",
		"library_capsule": "9f3c/library_600x900.jpg", "library_capsule_2x": "9f3c/library_600x900_2x.jpg",
		"library_hero": "9f3c/library_hero.jpg", "library_hero_2x": "9f3c/library_hero_2x.jpg", "library_logo": "9f3c/logo.png" }
	var base := "https://shared.steamstatic.com/store_item_assets/steam/apps/3527290/9f3c/"
	var it := { "appid": 3527290, "capsule": "https://x/cap.jpg", "header": "https://x/head.jpg" }
	var u := Store.art_urls_from(it, neu, true)
	check(u.size() == 6 and str(u[0]) == base + "library_600x900_2x.jpg?t=1750000000" and str(u[1]) == base + "library_600x900.jpg?t=1750000000",
			"Hochformat: Hülle unter ihrem echten Namen, 2× zuerst")
	check(str(u[2]) == base + "capsule_616x353.jpg?t=1750000000" and str(u[3]) == "https://x/cap.jpg" and str(u[5]) == "https://x/head.jpg",
			"danach Kapsel und Kopfbild (Store, dann Liste)")
	check(u.filter(func(x): return str(x).contains("/3527290/library_600x900")).is_empty(), "keine alte feste Adresse, wenn Steam die Namen kennt")
	check(str(Store.art_urls_from(it, neu, true, 400)[0]).ends_with("9f3c/library_600x900.jpg?t=1750000000"), "kleine Karte: einfache Hülle reicht (2× danach)")
	var quer := { "asset_url_format": "steam/apps/77/${FILENAME}", "main_capsule": "capsule_616x353.jpg", "header": "header.jpg" }
	var uq := Store.art_urls_from({ "appid": 77 }, quer, true)
	check(uq.size() == 2 and str(uq[0]).ends_with("/77/capsule_616x353.jpg"), "Spiel ohne Hülle: gleich das Querformat (keine Fehlgriffe)")
	var ua := Store.art_urls_from({ "appid": 77, "capsule": "c.jpg" }, {}, true)
	check(ua.size() == 3 and str(ua[0]).ends_with("/77/library_600x900_2x.jpg") and str(ua[2]) == "c.jpg", "Steam unbekannt: alte Adressen, dann Kapsel")
	check(Store.art_urls_from({ "appid": 77 }, { "_t": 5 }, true).size() == 2, "Steam kennt keine Bilder (nur _t): alte Adressen")
	check(
			Store.art_urls_from(it, neu, false) == [base + "capsule_616x353.jpg?t=1750000000", "https://x/cap.jpg", base + "header.jpg?t=1750000000",
			"https://x/head.jpg"], "Querformat (Erweiterungen): Kapsel, Kopfbild")
	var hu := Store.hero_urls(3527290, neu, 1920)
	check(hu.size() == 2 and str(hu[0]).ends_with("9f3c/library_hero.jpg?t=1750000000"), "großes Bild: einfache Größe für 1080p")
	check(str(Store.hero_urls(3527290, neu, 3840)[0]).ends_with("library_hero_2x.jpg?t=1750000000"), "großes Bild: doppelte Größe für 4K")
	check(Store.hero_urls(5, {}) == [Store.CDN % [5, "library_hero.jpg"]] and Store.logo_urls(5, {}) == [Store.CDN % [5, "logo.png"]],
			"ohne Angaben: alte Adressen")
	check(Store.logo_urls(3527290, neu) == [base + "logo.png?t=1750000000"] and Store.hero_urls(77, quer).is_empty(),
			"Schriftzug aus dem Store; ohne großes Bild nichts Erfundenes")
	var fs := Store.from_store_item({ "appid": 3527290, "name": "Neu", "assets": neu, "best_purchase_option": { "final_price_in_cents": "1999" } })
	check(str(fs.capsule) == base + "capsule_616x353.jpg?t=1750000000" and str(fs.header) == base + "header.jpg?t=1750000000"
			and (fs.assets as Dictionary).has("library_capsule"), "Eintrag aus GetItems: Kapsel und Kopfbild mit Prüfsumme, Angaben dabei")
	check(Store.ids_of([{ "appid": 5 }, { "appid": 0 }, "x", { "appid": 7 }]) == [5, 7], "App-IDs für das gebündelte Holen")
	var resp := { "response": { "store_items": [{ "appid": 3527290, "assets": neu }, { "appid": 9, "success": 2 }, { "id": 11, "assets": quer }, "kaputt"] } }
	var pa := Media.parse_store_assets(resp)
	check(pa.size() == 2 and pa.has("3527290") and pa.has("11"), "Antwort von GetItems: Bilder je App (ohne Bilder: nichts)")
	check(Media.parse_store_assets(null).is_empty() and Media.parse_store_assets({ "response": "x" }).is_empty(), "kaputte Antwort: leer")
	var now := 1_800_000_000
	check(Media.assets_fresh({ "asset_url_format": "f", "_t": now - 86400 }, now), "Angaben eine Woche frisch")
	check(not Media.assets_fresh({ "asset_url_format": "f", "_t": now - 8 * 86400 }, now), "nach einer Woche neu fragen")
	check(Media.assets_fresh({ "_t": now - 3600 }, now) and not Media.assets_fresh({ "_t": now - 2 * 86400 }, now), "„keine Bilder“ gilt einen Tag")
	check(not Media.assets_fresh({}, now) and not Media.assets_fresh({ "asset_url_format": "f" }, now), "unbekannt oder ohne Zeit (alter Speicher): neu fragen")
	OS.set_environment("UZAI_STEAM_API", "http://127.0.0.1:1/")
	check(Net.redirected("https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?a=1") == "http://127.0.0.1:1/IStoreBrowseService/GetItems/v1/?a=1",
			"Netz-Probe: Steam-Schnittstelle umlenkbar")
	check(Net.redirected("https://shared.steamstatic.com/x.jpg") == "https://shared.steamstatic.com/x.jpg", "Bildserver bleibt ohne eigene Variable")
	OS.unset_environment("UZAI_STEAM_API")
	check(Net.redirected("https://api.steampowered.com/x") == "https://api.steampowered.com/x", "ohne Variable: unverändert")

	print("Bilder nie verzerrt")
	var card := Vector2(340, 510)
	check(ShopArt.fits(Vector2(600, 900), card) and ShopArt.fits(Vector2(1200, 1800), card), "Hülle füllt die Hochformat-Karte")
	check(not ShopArt.fits(Vector2(616, 353), card) and not ShopArt.fits(Vector2(460, 215), card), "Kapsel und Kopfbild passen nicht ins Hochformat")
	check(ShopArt.fits(Vector2(616, 353), Vector2(320, 183)) and ShopArt.fits(Vector2(460, 215), Vector2(320, 183)),
			"Querformat-Karten (Erweiterungen) nehmen Kapsel und Kopfbild")
	var spot := Vector2(1728, 450)
	check(ShopArt.fits(Vector2(3840, 1240), spot, Vector2(0.6, 1.6)) and not ShopArt.fits(Vector2(616, 353), spot, Vector2(0.6, 1.6)),
			"Rampenlicht: großes Bild füllt, Kapsel steht ganz daneben")
	var src := ShopArt.cover_src(Vector2(616, 353), card)
	check(is_equal_approx(src.size.x / src.size.y, card.x / card.y) and src.position.x > 0.0 and is_zero_approx(src.position.y),
			"Füllen: Ausschnitt im Seitenverhältnis der Karte (nie gestreckt)")
	var fr := ShopArt.fit_rect(Vector2(616, 353), Rect2(Vector2.ZERO, card), 0.42)
	check(is_equal_approx(fr.size.x, 340.0) and is_equal_approx(fr.size.x / fr.size.y, 616.0 / 353.0) and fr.position.y > 100.0 and fr.end.y < 360.0,
			"Querbild ganz, im eigenen Seitenverhältnis, über der Preis-Pille")
	var tall := ShopArt.fit_rect(Vector2(600, 900), Rect2(0, 0, 320, 183))
	check(is_equal_approx(tall.size.y, 183.0) and is_equal_approx(tall.position.x, (320.0 - 122.0) * 0.5), "Hochbild in der Querkarte: ganz und mittig")

	print("Steam-Dienste (Wunschliste, Warenkorb)")
	var h := Store.read_eresult(PackedStringArray(["Content-Type: application/json", "X-eresult: 15", "x-error_message: Access Denied"]))
	check(int(h.eresult) == 15 and str(h.message) == "Access Denied", "Fehlercode aus dem Antwortkopf")
	check(int(Store.read_eresult(PackedStringArray(["Content-Type: x"])).eresult) == 1 and int(Store.read_eresult(null).eresult) == 1,
			"ohne Kopf gilt: in Ordnung")
	check(Store.service_error(401, 1, "Die Wunschliste").contains("Anmeldung"), "abgelaufene Anmeldung verständlich")
	check(Store.service_error(0, 1, "x").contains("nicht erreichbar"), "kein Netz verständlich")
	check(Store.service_error(200, 2, "Der Warenkorb").contains("noch einmal") and not Store.service_error(200, 2, "Der Warenkorb").contains("2"),
			"sonstiger Fehler: Handlungsempfehlung statt Code")
	check(Store.cart_has({ "response": { "line_item_ids": ["123"] } }, 1)
			and Store.cart_has({ "response": { "cart": { "line_items": [{ "packageid": 7 }] } } }, 7), "Warenkorb bestätigt das Paket")
	check(not Store.cart_has({ "response": {} }, 7) and not Store.cart_has(null, 7), "leere Antwort: nicht bestätigt")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
