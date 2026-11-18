extends Node
## Logiktests für Gratis-Spiele und Angebote auf der Wunschliste (Punkt 110), ohne Netz: Antwort
## von Epics freeGamesPromotions und Steams GetItems als Vorlage (über JSON gelesen, wie echt –
## Zahlen kommen dann als Kommazahl an), Zwischenspeicher, Steam −100 %, „ein Angebot einmal
## melden“ und die Zeilen unter den Karten.
## Aufruf: godot --headless --path . res://tests/logic_angebote.tscn

const ShopCard := preload("res://src/ui/components/shop_card.gd")

const NOW_ISO := "2026-01-17T12:00:00.000Z"

## Wie Epic antwortet (gekürzt auf die Felder, die Uzai liest).
const EPIC := """{"data":{"Catalog":{"searchStore":{"elements":[
 {"title":"Kingdom Come: Deliverance","id":"a1","namespace":"ns1","description":"Böhmen, 1403.",
  "keyImages":[{"type":"Thumbnail","url":"https://cdn1.epicgames.com/thumb.jpg"},{"type":"OfferImageWide","url":"https://cdn1.epicgames.com/wide.jpg"},{"type":"OfferImageTall","url":"https://cdn1.epicgames.com/tall.jpg"}],
  "productSlug":null,"urlSlug":"8f3c0a1b2c","catalogNs":{"mappings":[{"pageSlug":"kingdom-come-deliverance","pageType":"productHome"}]},"offerMappings":[],
  "price":{"totalPrice":{"discountPrice":0,"originalPrice":2999,"currencyCode":"EUR","currencyInfo":{"decimals":2}}},
  "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-15T16:00:00.000Z","endDate":"2026-01-22T16:00:00.000Z","discountSetting":{"discountType":"PERCENTAGE","discountPercentage":0}}]}],"upcomingPromotionalOffers":[]}},
 {"title":"Kingdom Come: Deliverance","id":"a1","namespace":"ns1","description":"doppelt",
  "catalogNs":{"mappings":[{"pageSlug":"kingdom-come-deliverance","pageType":"productHome"}]},
  "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-15T16:00:00.000Z","endDate":"2026-01-22T16:00:00.000Z","discountSetting":{"discountPercentage":0}}]}]}},
 {"title":"Sifu","id":"b2","namespace":"ns2","description":"Sifu",
  "keyImages":[{"type":"OfferImageTall","url":"http://cdn1.epicgames.com/unsicher.jpg"}],
  "productSlug":null,"catalogNs":{"mappings":[]},"offerMappings":[{"pageSlug":"sifu","pageType":"offer"}],
  "price":{"totalPrice":{"originalPrice":3999,"currencyCode":"EUR","currencyInfo":{"decimals":2}}},
  "promotions":{"promotionalOffers":[],"upcomingPromotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-22T16:00:00.000Z","endDate":"2026-01-29T16:00:00.000Z","discountSetting":{"discountPercentage":0}}]}]}},
 {"title":"Control","id":"c3","namespace":"ns3","productSlug":"control/home",
  "price":{"totalPrice":{"originalPrice":1500,"currencyCode":"JPY","currencyInfo":{"decimals":0}}},
  "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-15T16:00:00.000Z","endDate":"2026-01-22T16:00:00.000Z","discountSetting":{"discountPercentage":"0"}}]}]}},
 {"title":"Cyberpunk 2077","id":"d4","namespace":"ns4","productSlug":"cyberpunk-2077",
  "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-15T16:00:00.000Z","endDate":"2026-01-22T16:00:00.000Z","discountSetting":{"discountPercentage":50}}]}]}},
 {"title":"Mystery Game","id":"e5","namespace":"ns5","productSlug":"[]","urlSlug":"mystery-game-01","catalogNs":{"mappings":[]},"offerMappings":[],
  "promotions":{"upcomingPromotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-22T16:00:00.000Z","endDate":"2026-01-29T16:00:00.000Z","discountSetting":{"discountPercentage":0}}]}]}},
 {"title":"Böse Adresse","id":"f6","namespace":"ns6","productSlug":"../../x?y=1","catalogNs":{"mappings":[{"pageSlug":"Evil Slug","pageType":"productHome"}]},
  "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-15T16:00:00.000Z","endDate":"2026-01-22T16:00:00.000Z","discountSetting":{"discountPercentage":0}}]}]}},
 {"title":"Vorbei","id":"g7","namespace":"ns7","productSlug":"vorbei",
  "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-08T16:00:00.000Z","endDate":"2026-01-15T16:00:00.000Z","discountSetting":{"discountPercentage":0}}]}]}},
 {"title":"","id":"h8","namespace":"ns8","productSlug":"ohne-titel",
  "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-01-15T16:00:00.000Z","endDate":"2026-01-22T16:00:00.000Z","discountSetting":{"discountPercentage":0}}]}]}},
 "kaputt", {"title":"Ohne Aktion","productSlug":"ohne"}
]}}}}"""

## Steam GetItems: ein Spiel im Angebot mit Ende (Zahlen wie bei Steam teils als Text).
const STEAM_ITEM := """{"appid":753640,"name":"Outer Wilds","best_purchase_option":{"final_price_in_cents":"1249","original_price_in_cents":"2499","discount_pct":50,
 "active_discounts":[{"discount_amount":"1250","discount_description":"Wochenangebot","discount_end_date":1769097600}]}}"""

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var now := Store.iso_time(NOW_ISO)

	print("Zeitangaben")
	check(now == Time.get_unix_time_from_datetime_string("2026-01-17T12:00:00") and now > 0, "ISO-Zeit von Epic → Unix-Zeit (UTC)")
	check(Store.iso_time("") == 0 and Store.iso_time("morgen") == 0 and Store.iso_time("2026/01/17 12:00:00") == 0, "Unlesbares: 0")
	check(Store.epic_locale("en-US") == "en-US" and Store.epic_locale("de") == "de" and Store.epic_locale("fr\"x") == "de",
			"Sprache in Epics Adresse nur aus der Liste")

	print("Epic: Gratis-Spiele der Woche")
	var data: Variant = JSON.parse_string(EPIC)
	var free := Store.parse_epic_free(data, now, "de")
	var names := free.map(func(x: Dictionary) -> String: return str(x.name))
	check(free.size() == 3, "drei gültige Einträge (%s)" % ", ".join(names))
	var kcd: Dictionary = free[0] if not free.is_empty() else {}
	check(str(kcd.get("name", "")) == "Kingdom Come: Deliverance" and names.count("Kingdom Come: Deliverance") == 1, "doppelter Eintrag nur einmal")
	check(str(kcd.get("url", "")) == "https://store.epicgames.com/de/p/kingdom-come-deliverance" and str(kcd.get("slug", "")) == "kingdom-come-deliverance",
			"Seite aus der Produktzuordnung, nicht aus urlSlug")
	check(bool(kcd.get("free", false)) and not bool(kcd.get("upcoming", true)) and int(kcd.get("discount", 0)) == 100 and int(kcd.get("price", -1)) == 0,
			"jetzt gratis: −100 %, Preis 0")
	check(int(kcd.get("original", 0)) == 2999 and str(kcd.get("currency", "")) == "EUR", "alter Preis in Cent (Zahl kam als Kommazahl)")
	check(int(kcd.get("from", 0)) == Store.iso_time("2026-01-15T16:00:00.000Z") and int(kcd.get("until", 0)) == Store.iso_time("2026-01-22T16:00:00.000Z"),
			"Zeitraum der Aktion")
	check(str(kcd.get("capsule", "")).ends_with("/tall.jpg") and str(kcd.get("header", "")).ends_with("/wide.jpg"), "Hochbild und Querbild nach Art")
	check(str(kcd.get("store", "")) == "epic" and int(kcd.get("appid", -1)) == 0 and str(kcd.get("id", "")) == "epic:ns1:a1" and bool(kcd.get("giveaway", false)),
			"eigene Kennung, keine Steam-ID")
	var sifu := _find(free, "Sifu")
	check(bool(sifu.get("upcoming", false)) and not bool(sifu.get("free", true)) and int(sifu.get("discount", -1)) == 0, "angekündigt: noch nicht gratis")
	check(str(sifu.get("url", "")) == "https://store.epicgames.com/de/p/sifu", "Seite aus offerMappings")
	check(str(sifu.get("capsule", "x")) == "" and str(sifu.get("desc", "x")) == "", "Bild ohne https fällt weg, Beschreibung gleich Titel auch")
	var ctl := _find(free, "Control")
	check(str(ctl.get("slug", "")) == "control" and int(ctl.get("original", 0)) == 150000, "productSlug ohne /home; Währung ohne Nachkommastellen")
	check(_find(free, "Cyberpunk 2077").is_empty(), "Rabatt, aber nicht gratis: fällt weg")
	check(_find(free, "Mystery Game").is_empty(), "Geheimes Spiel ohne Seite: fällt weg")
	check(_find(free, "Böse Adresse").is_empty(), "fremde Zeichen in der Adresse: fällt weg")
	check(_find(free, "Vorbei").is_empty() and _find(free, "Ohne Aktion").is_empty(), "abgelaufen oder ohne Aktion: fällt weg")
	check(Store.parse_epic_free(data, now, "en-US").all(func(x: Dictionary) -> bool: return str(x.url).begins_with("https://store.epicgames.com/en-US/p/")),
			"englische Seiten")
	check(Store.parse_epic_free(null, now).is_empty() and Store.parse_epic_free({}, now).is_empty() and Store.parse_epic_free({ "data": "x" }, now).is_empty()
			and Store.parse_epic_free([1], now).is_empty(), "kaputte Antwort: leer")
	var lib_n := Library.games.size()
	Library.games.append({ "id": "epic:test", "source": "epic", "epic": { "namespace": "ns1", "item": "x", "app": "x" } })
	check(Store.owned_item(kcd) and not Store.owned_item(sifu) and not Store.owned_item({ "store": "epic" }), "schon in der Bibliothek: nach Epics Namespace")
	Library.games.resize(lib_n)
	var later := Store.iso_time("2026-01-23T12:00:00.000Z")
	var next := Store.parse_epic_free(data, later, "de")
	check(_find(next, "Kingdom Come: Deliverance").is_empty() and bool(_find(next, "Sifu").get("upcoming", true)) == false
			and bool(_find(next, "Sifu").get("free", false)), "eine Woche später: Sifu ist jetzt gratis")

	print("Zwischenspeicher")
	var cached: Variant = JSON.parse_string(JSON.stringify({ "at": now, "items": free }))
	var back := Store.free_from_cache(cached.items, now)
	check(back.size() == 3 and int(back[0].until) == int(kcd.until), "über JSON zurück: alles da")
	check(Store.free_from_cache(cached.items, Store.iso_time("2026-01-22T16:00:00.000Z")).size() == 1, "Abgelaufenes fällt beim Lesen weg (Sifu bleibt)")
	var bad: Array = [
		{ "store": "epic", "slug": "x", "url": "https://boese.example/p/x", "until": 0 },
		{ "store": "epic", "slug": "x", "url": "https://store.epicgames.com/de/p/y", "until": 0 },
		{ "store": "epic", "slug": "x\" & calc", "url": "https://store.epicgames.com/de/p/x\" & calc", "until": 0 },
		{ "store": "steam", "slug": "x", "url": "https://store.epicgames.com/de/p/x" }, "kaputt"]
	check(Store.free_from_cache(bad, now).is_empty(), "fremde Adresse, falscher Kurzname, fremder Shop, Unsinn: verworfen")
	var tampered: Variant = JSON.parse_string(JSON.stringify([kcd]))
	tampered[0]["capsule"] = "http://boese.example/bild.jpg"
	check(str(Store.free_from_cache(tampered, now)[0].capsule) == "", "Bild ohne https aus dem Zwischenspeicher fällt weg")
	check(not Store.free_stale(free, now), "frisch: nicht neu fragen")
	check(Store.free_stale(free, Store.iso_time("2026-01-22T16:00:01.000Z")), "Aktion vorbei oder Angekündigtes begonnen: neu fragen")

	print("Steam: zeitweise ganz kostenlos")
	var lists := {
		"specials": [
			{ "appid": 1, "name": "Gratis", "discount": 100, "price": 0, "original": 1499 },
			{ "appid": 2, "name": "Halb", "discount": 50, "price": 500, "original": 1000 },
			{ "appid": 3, "name": "Free-to-Play", "discount": 0, "price": 0, "original": 0, "free": true },
		],
		"top_sellers": [{ "appid": 1, "name": "Gratis", "discount": 100, "price": 0, "original": 1499 }],
	}
	var sg := Store.steam_giveaways(lists)
	check(sg.size() == 1 and int(sg[0].appid) == 1, "nur −100 % mit altem Preis, jedes Spiel einmal")
	check(bool(sg[0].giveaway) and bool(sg[0].free) and str(sg[0].store) == "steam", "als Gratis-Aktion markiert")
	check(not lists.specials[0].has("giveaway"), "die Shop-Liste selbst bleibt unverändert")

	print("Steam: Ende eines Angebots")
	var si := Store.from_store_item(JSON.parse_string(STEAM_ITEM))
	check(int(si.until) == 1769097600 and int(si.discount) == 50 and int(si.price) == 1249 and int(si.original) == 2499,
			"Ende aus active_discounts (Zahl kam als Kommazahl)")
	check(int(Store.from_store_item({ "appid": 5, "best_purchase_option": { "final_price_in_cents": "999" } }).until) == 0, "ohne Ende: 0")
	check(int(Store.from_store_item({ "appid": 5, "best_purchase_option": { "active_discounts": [{ "discount_end_date": "morgen" }, "x"] } }).until) == 0,
			"Unsinn als Ende: 0")

	print("Wunschliste: neue Angebote einmal melden")
	var wl := [
		{ "appid": 10, "name": "Outer Wilds", "discount": 50, "until": 5000, "price": 1249, "original": 2499 },
		{ "appid": 11, "name": "Hades II", "discount": 0, "until": 0, "price": 2999, "original": 2999 },
		{ "appid": 12, "name": "Sea of Stars", "discount": 40, "until": 0, "price": 2099, "original": 3499 },
		{ "appid": 0, "name": "kaputt", "discount": 90 }, "kaputt",
	]
	var r1 := Store.sale_news(wl, {}, 1000)
	check(_ids(r1.new) == [10, 12], "erster Blick: alle laufenden Angebote sind neu")
	check(r1.seen.size() == 2 and not r1.seen.has("11"), "ohne Rabatt: nichts gemerkt")
	var seen_json: Variant = JSON.parse_string(JSON.stringify(r1.seen))
	var r2 := Store.sale_news(wl, seen_json, 2000)
	check(r2.new.is_empty(), "nächster Start, gleiche Angebote: keine Mitteilung")
	check(int(r2.seen["10"].at) == 1000, "„seit wann“ bleibt erhalten")
	var ended := wl.duplicate(true)
	ended[0]["discount"] = 0
	var r3 := Store.sale_news(ended, r2.seen, 3000)
	check(r3.new.is_empty() and not r3.seen.has("10"), "Angebot vorbei: vergessen, keine Mitteilung")
	var again := wl.duplicate(true)
	again[0]["until"] = 9000
	var r4 := Store.sale_news(again, r3.seen, 4000)
	check(_ids(r4.new) == [10] and int(r4.seen["10"].at) == 4000, "später neues Angebot: wieder einmal melden")
	var deeper := again.duplicate(true)
	deeper[1]["discount"] = 0
	deeper[2]["discount"] = 60
	check(_ids(Store.sale_news(deeper, r4.seen, 5000).new) == [12], "Rabatt größer geworden: einmal melden")

	print("Text der Mitteilung")
	var one := Store.sale_toast([wl[0]])
	check(str(one.title) == "Outer Wilds im Angebot" and str(one.sub) == "−50 %  ·  jetzt 12,49 € statt 24,99 €", "ein Spiel: Name, Rabatt, Preis")
	var many := Store.sale_toast([wl[0], wl[2], { "appid": 13, "name": "Celeste", "discount": 75, "price": 499, "original": 1999 }])
	check(str(many.title) == "Wunschliste: 3 Spiele im Angebot" and str(many.sub) == "Am meisten gespart: Celeste (−75 %)",
			"mehrere: zusammen, mit dem größten Rabatt")
	check(Store.sale_toast([]).is_empty(), "nichts Neues: keine Mitteilung")

	print("Melden (Mitteilungen, abschaltbar)")
	var saved_wl: Array = Store.wishlist
	var saved_on: Variant = Config.get_value("notify.wish_sales", true)
	Config.set_value("notify.wish_sales", true)
	Store.wishlist = wl
	var h0 := Toasts.history.size()
	Store._note_sales()
	check(Toasts.history.size() == h0 + 2 and str(Toasts.history[0].icon) == "shop", "zwei neue Angebote: zwei Mitteilungen")
	check(Store.sale_new.has(10) and Store.sale_new.has(12) and not Store.sale_new.has(11), "„Neu im Angebot“ für die Wunschliste")
	Store._note_sales()
	check(Toasts.history.size() == h0 + 2, "nächster Blick: nichts doppelt")
	Store.wishlist = again
	Config.set_value("notify.wish_sales", false)
	Store._note_sales()
	check(Toasts.history.size() == h0 + 2, "abgeschaltet: keine Mitteilung")
	Config.set_value("notify.wish_sales", true)
	Store._note_sales()
	check(Toasts.history.size() == h0 + 2, "abgeschaltet Gesehenes kommt auch danach nicht nach")
	var h1 := Toasts.history.size()
	Store.show_sales([wl[0], wl[2], wl[0], wl[2]])
	check(Toasts.history.size() == h1 + 1, "mehr als %d auf einmal: eine Sammel-Mitteilung" % Store.SALES_SINGLE)
	Store.wishlist = saved_wl
	Config.set_value("notify.wish_sales", saved_on)

	print("Zeilen unter den Karten")
	var t := int(Time.get_unix_time_from_system())
	check(ShopCard.giveaway_when({ "upcoming": true, "from": t + 3 * 86400 }) == "Ab %s gratis" % ShopCard.day_text(t + 3 * 86400), "angekündigt: ab wann")
	check(ShopCard.giveaway_when({ "until": t + 5 * 3600 + 1800 }) == "Gratis noch 5 Std.", "endet heute: in Stunden")
	check(ShopCard.giveaway_when({ "until": t + 4 * 86400 }) == "Gratis bis %s" % ShopCard.day_text(t + 4 * 86400), "sonst: bis wann")
	check(ShopCard.giveaway_when({}) == "Gratis" and ShopCard.day_text(0) == "", "ohne Ende: nur „Gratis“")
	check(ShopCard.status_line({ "giveaway": true, "store": "epic", "until": t + 4 * 86400 }, false).ends_with(" · Epic"), "Epic dazugesagt")
	Store.sale_new = { 10: true }
	check(ShopCard.status_line({ "appid": 10, "discount": 50, "until": t + 4 * 86400 }, false) == "Neu im Angebot · bis %s" % ShopCard.day_text(t + 4 * 86400),
			"Wunschliste: neu im Angebot")
	check(ShopCard.status_line({ "appid": 12, "discount": 40, "until": t + 4 * 86400 }, false).begins_with("Angebot bis "), "schon bekanntes Angebot wie bisher")
	check(ShopCard.status_line({ "appid": 10, "discount": 50, "until": t + 4 * 86400 }, true) == "In deiner Bibliothek", "gekauft geht vor")
	Store.sale_new = {}

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _find(items: Array, name: String) -> Dictionary:
	for it in items:
		if str(it.get("name", "")) == name:
			return it
	return {}


func _ids(items: Array) -> Array:
	return items.map(func(x: Dictionary) -> int: return int(x.appid))
