extends "res://src/core/store_daten.gd"
## Steam-Shop in Uzai: Angebote, Topseller, Neuerscheinungen, Genres, Suche, Wunschliste und
## Spieleseiten mit Trailern, Bewertungen, Erweiterungen, Neuigkeiten und Systemanforderungen –
## alles aus den Store-Schnittstellen von Steam.
##
## Dazu die Gratis-Spiele der Woche (Epic, zeitweise auch Steam) und ein Hinweis, wenn ein Spiel
## deiner Wunschliste im Angebot ist (siehe „Gratis und Angebote“ unten).
##
## Wunschliste und Warenkorb ändert Uzai direkt über dein Steam-Konto (Anmeldung per QR-Code).
## Das sind dieselben Schnittstellen, die der Steam-Shop selbst benutzt; Valve dokumentiert sie
## nicht, deshalb fängt Uzai jeden Fehler ab und sagt, was los ist. Bezahlen geht nur bei Steam:
## Uzai legt das Spiel in den Warenkorb und öffnet ihn zum Schluss im Steam-Client.
##
## Reine Funktionen (Antworten lesen, Preise, Gratis-Spiele) stehen in store_daten.gd, von dem dieser
## Autoload erbt.

signal updated
signal wishlist_changed(appid: int, on: bool)

const FEATURED := "https://store.steampowered.com/api/featuredcategories/?cc={cc}&l={l}"
const DETAILS := "https://store.steampowered.com/api/appdetails?appids=%d&cc={cc}&l={l}"
## Nur die Preise, dafür viele Spiele auf einmal (mehrere App-IDs nimmt appdetails nur mit diesem Filter).
const PRICES := "https://store.steampowered.com/api/appdetails?appids=%s&filters=price_overview&cc={cc}&l={l}"
const PRICE_BATCH := 40
const GENRE := "https://store.steampowered.com/api/getappsingenre/?genre=%s&cc={cc}&l={l}"
const SEARCH := "https://store.steampowered.com/api/storesearch/?term=%s&l={l}&cc={cc}"
## Suche mit Kategorien (Steam-Tags, mit Komma getrennt), nur Spiele (category1=998). Die Antwort nennt je Treffer
## nur Namen und Bild (parse_suche_gefiltert); so nachgesehen im November 2026.
const SEARCH_TAGS := "https://store.steampowered.com/search/results/?term=%s&tags=%s&category1=998&json=1&cc={cc}&l={l}"
const REVIEWS := "https://store.steampowered.com/appreviews/%d?json=1&language=all&purchase_type=all&num_per_page=0"
const REVIEW_TEXTS := "https://store.steampowered.com/appreviews/%d?json=1&language={l}&filter=all&day_range=365&review_type=all&purchase_type=all&num_per_page=10"
const NEWS := "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=%d&count=6&maxlength=0&feeds=steam_community_announcements&format=json"
const WISHLIST := "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?"
const WISH_ADD := "https://api.steampowered.com/IWishlistService/AddToWishlist/v1/"
const WISH_REMOVE := "https://api.steampowered.com/IWishlistService/RemoveFromWishlist/v1/"
const CART_ADD := "https://api.steampowered.com/IAccountCartService/AddItemsToCart/v1/"
const CART_PAGE := "steam://openurl/https://store.steampowered.com/cart/"
const ITEMS := "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json="
## Gratis-Spiele bei Epic: dieselbe öffentliche Liste, die Epics Shop-Seite zeigt (ohne Anmeldung).
const EPIC_FREE := "https://store-site-backend-static-ipv4.ak.epicgames.com/freeGamesPromotions?locale=%s&country={cc}&allowCountries={cc}"
const EPIC_LAUNCHER := "com.epicgames.launcher://store/p/%s"
const FREE_CACHE := "cache/gratis.json"
const FREE_TTL := 6 * 3600          ## Gratis-Liste höchstens alle 6 Stunden neu fragen
const FREE_RETRY_S := 900           ## nach einem Fehlschlag frühestens nach 15 Minuten wieder
const SALES_CACHE := "cache/wunschliste-angebote.json"
const SALES_CHECK_S := 6 * 3600.0   ## Wunschliste nebenbei alle 6 Stunden auf neue Angebote prüfen
const SALES_SINGLE := 3             ## mehr neue Angebote auf einmal: eine Sammel-Mitteilung
const SALE_NEW_S := 2 * 86400       ## so lange steht „Neu im Angebot“ in der Wunschliste


const SteamScanner := preload("res://src/library/steam_scanner.gd")
const Fremd := preload("res://src/core/fremd.gd")


const DEMO := "res://tests/demo_store.json"
const RETRY_S := 60

## Genres, wie Steam sie für getappsingenre kennt: [Schlüssel, Anzeige, Farbe]
const GENRES := [
	["Action", "Action", "#c2453a"], ["Adventure", "Abenteuer", "#3f8f6b"], ["RPG", "Rollenspiel", "#7a4fc0"],
	["Strategy", "Strategie", "#2f6fae"], ["Simulation", "Simulation", "#3c9aa5"], ["Indie", "Indie", "#c27c2e"],
	["Racing", "Rennspiel", "#b03a6a"], ["Sports", "Sport", "#3a8f3a"], ["Casual", "Gelegenheit", "#a58a3a"],
	["Free to Play", "Kostenlos", "#4a7ad0"], ["Massively Multiplayer", "Massen-Mehrspieler", "#8f4a8f"], ["Early Access", "Early Access", "#6a6a7a"],
]

var lists := {}            # specials, top_sellers, new_releases, coming_soon -> Array
var genre_lists := {}      # Genre -> { topsellers, newreleases, specials, comingsoon }
var wishlist: Array = []
var wishlist_loading := false
var wishlist_loaded := false    ## schon einmal erfolgreich gelesen (auch wenn leer)
var wishlist_angemeldet := false   ## … und zwar mit der Steam-Anmeldung (wishlist_noetig)
var wishlist_error := ""
var loading := false
var loaded_at := 0
var error := ""
var _details := {}
var _reviews := {}
var _review_texts := {}
var _news := {}
var _dlc := {}
var _failed := {}          ## appid -> Zeitpunkt des letzten Fehlschlags (nicht sofort neu fragen)
var _busy := {}
var _demo: Variant = null
var free_epic: Array = []           ## Epic: jetzt und bald gratis (Einträge wie in den Listen, store = epic)
var free_loading := false
var _free_at := 0
var _free_tried := 0
var sale_new := {}                  ## appid -> true: auf der Wunschliste seit kurzem im Angebot


func _ready() -> void:
	var t := Timer.new()
	t.wait_time = SALES_CHECK_S
	t.autostart = true
	t.timeout.connect(_check_later)
	add_child(t)
	Config.changed.connect(func(key: String) -> void:
		if key == "system.country":
			_land_gewechselt()
	)


## Anderes Land: Preise, Währung und Angebote stimmen nicht mehr – alles Gemerkte weg. Neu geholt wird
## nur, was schon einmal geladen war (wer den Shop nie geöffnet hat, löst hier keine Abfragen aus).
func _land_gewechselt() -> void:
	var shop_war_da := loaded_at > 0 or not lists.is_empty()
	var gratis_war_da := _free_at > 0 or not free_epic.is_empty()
	lists.clear()
	genre_lists.clear()
	_details.clear()
	_dlc.clear()
	_failed.clear()
	free_epic = []
	_free_at = 0
	_free_tried = 0
	loaded_at = 0
	for datei in [FREE_CACHE, SALES_CACHE]:
		if FileAccess.file_exists(Config.path(datei)):
			DirAccess.remove_absolute(Config.path(datei))
	updated.emit()
	if shop_war_da:
		refresh(true)
	if gratis_war_da:
		load_free(true)
	if wishlist_loaded and not Library.demo:
		load_wishlist()


## Läuft Uzai lange (Konsole im Wohnzimmer): Wunschliste und Gratis-Liste nebenbei auffrischen.
func _check_later() -> void:
	if wishlist_loaded and not Library.demo:
		load_wishlist()
	load_free()


## Läufe von refresh, die gerade unterwegs sind (siehe dort).
var _refresh_offen := 0


func refresh(force := false) -> void:
	_refresh_offen += 1
	await _refresh_lauf(force)
	_refresh_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh täte bis zum Neustart nichts mehr.
	if _refresh_offen == 0 and loading:
		loading = false


func _refresh_lauf(force := false) -> void:
	if loading or (not force and Time.get_unix_time_from_system() - loaded_at < 900 and not lists.is_empty()):
		return
	loading = true
	var r := await Net.get_json(_url(FEATURED))
	if not r.ok and Library.demo:
		r = { "ok": true, "data": _demo_data() }
	loading = false
	if not r.ok or not (r.data is Dictionary):
		error = "Der Steam-Shop ist gerade nicht erreichbar."
		updated.emit()
		return
	error = ""
	for key in ["specials", "top_sellers", "new_releases", "coming_soon"]:
		var block: Variant = r.data.get(key, {})
		if block is Dictionary:
			lists[key] = parse_items(Fremd.liste(block.get("items")), key == "coming_soon")
	loaded_at = int(Time.get_unix_time_from_system())
	# Bildangaben aller Spiele gebündelt holen, bevor die Karten entstehen.
	var all: Array = []
	for key in lists.keys():
		all.append_array(ids_of(lists[key]))
	Media.prefetch_steam_assets(all)
	updated.emit()
	# Spiele, bei denen die Liste nur 0 schickt: Preis (oder „kostenlos“) nachfragen.
	var pool: Array = []
	for key in lists.keys():
		pool.append_array(lists[key])
	if await fill_prices(pool):
		updated.emit()


## Topseller, Neues, Angebote und Bald in einem Genre.
func genre(key: String) -> Dictionary:
	if genre_lists.has(key):
		return genre_lists[key]
	var out := {}
	var r := await Net.get_json(_url(GENRE) % key.uri_encode())
	if r.ok and r.data is Dictionary and r.data.get("tabs") is Dictionary:
		for tab in ["topsellers", "newreleases", "specials", "comingsoon"]:
			var t: Variant = r.data.tabs.get(tab)
			if t is Dictionary:
				out[tab] = parse_items(Fremd.liste(t.get("items")), tab == "comingsoon")
	elif Library.demo:
		# Wie getappsingenre: dieselben Spiele, aber ohne Preise (die holt fill_prices nach).
		var all: Array = unique(lists.get("top_sellers", []) + lists.get("specials", []))
		out = { "topsellers": _demo_unpriced(all), "newreleases": _demo_unpriced(lists.get("new_releases", [])),
			"specials": lists.get("specials", []), "comingsoon": lists.get("coming_soon", []) }
	if not out.is_empty():
		var all: Array = []
		var pool: Array = []
		for tab in out.keys():
			all.append_array(ids_of(out[tab]))
			pool.append_array(out[tab])
		Media.prefetch_steam_assets(all)
		# getappsingenre nennt keine Preise (nur 0): erst nachfragen, dann zeigen.
		await fill_prices(pool)
		genre_lists[key] = out
	return out


## Suche im Shop (Spiele, mit Preis). tags: Kategorien (SUCH_KATEGORIEN), die die Treffer einengen – auch ohne
## Suchwort (dann: was in diesen Kategorien gerade gefragt ist).
func search(term: String, tags: Array = []) -> Array:
	var out: Array = (await search_raw(term, tags)).items
	Media.prefetch_steam_assets(ids_of(out))
	# Ohne „price“ (kostenlos oder noch nicht kaufbar) sagt erst die Nachfrage, was stimmt.
	await fill_prices(out)
	return out


## Suche im Shop ohne Preise und Bilder: { ok (Steam hat geantwortet), items }.
func search_raw(term: String, tags: Array = []) -> Dictionary:
	term = term.strip_edges()
	var nummern := such_tags(tags)
	if term == "" and nummern.is_empty():
		return { "ok": false, "items": [] }
	var out: Array = []
	var ok := false
	if not nummern.is_empty():
		var r2 := await Net.get_json(_url(SEARCH_TAGS) % [term.uri_encode(), "%2C".join(PackedStringArray(nummern.map(func(n: int) -> String: return str(n))))])
		if r2.ok and r2.data is Dictionary:
			ok = true
			out = parse_suche_gefiltert(r2.data)
		elif Library.demo:
			ok = true
			out = _demo_suche(term, nummern)
		return { "ok": ok, "items": unique(out) }
	var r := await Net.get_json(_url(SEARCH) % term.uri_encode())
	if r.ok and r.data is Dictionary:
		ok = true
		for it in Fremd.zeilen(r.data, "items"):
			if not (it is Dictionary) or str(it.get("type", "app")) != "app":
				continue
			out.append(parse_search_item(it))
	elif Library.demo:
		out = _demo_suche(term, [])
		ok = true
	return { "ok": ok, "items": unique(out) }


## Vorführmodus: Suche in den mitgelieferten Listen. Kategorien kennt die Vorlage nicht – jede lässt einen
## festen Teil der Spiele übrig, damit man die Wirkung sieht.
func _demo_suche(term: String, nummern: Array) -> Array:
	var all: Array = unique(
			lists.get("top_sellers", []) + lists.get("specials", []) + lists.get("new_releases", []) + lists.get("coming_soon", []) + _demo_retro())
	return all.filter(func(x: Dictionary) -> bool:
		if term != "" and not str(x.get("name", "")).to_lower().contains(term.to_lower()):
			return false
		for nr in nummern:
			if (int(x.get("appid", 0)) / 10) % 3 == int(nr) % 3:
				return false
		return true)


# --- Preise nachfragen -----------------------------------------------------------------------

## Preise nachladen, wo eine Liste keinen nennt: appdetails mit filters=price_overview in
## Stapeln (cc/l wie die übrigen Abfragen). Ohne price_overview ist ein Spiel kostenlos oder noch
## nicht kaufbar – das klärt GetItems (is_free). Ändert die Einträge selbst (dieselben
## Wörterbücher wie in den Listen). Rückgabe: true, wenn sich ein Preis geändert hat.
func fill_prices(items: Array) -> bool:
	var ids: Array = []
	for it in items:
		if needs_price(it) and not ids.has(int(it.appid)):
			ids.append(int(it.appid))
	if ids.is_empty():
		return false
	var found := {}
	if Library.demo:
		found = _demo_prices(ids)
	else:
		for i in range(0, ids.size(), PRICE_BATCH):
			var chunk: PackedStringArray = []
			for id in ids.slice(i, i + PRICE_BATCH):
				chunk.append(str(id))
			var r := await Net.get_json(_url(PRICES) % ",".join(chunk))
			if r.ok:
				found.merge(parse_price_batch(r.data), true)
		# Kein Preis bei Steam: kostenlos oder (noch) nicht zu kaufen? GetItems weiß es.
		var no_price: Array = ids.filter(func(id): return found.has(id) and not bool(found[id].get("has_price", false)))
		for i in range(0, no_price.size(), 50):
			var got := await _items(no_price.slice(i, i + 50))
			for e in got:
				found[int(e.appid)] = { "has_price": int(e.price) > 0, "price": int(e.price), "original": maxi(int(e.original), int(e.price)),
					"discount": int(e.discount), "free": bool(e.get("free", false)) }
	return apply_prices(items, found)


## Zuletzt gesuchte Begriffe (neueste zuerst).
func recent_searches() -> Array:
	var v: Variant = Config.get_value("shop.recent_searches", [])
	return (v as Array).duplicate() if v is Array else []


func remember_search(term: String) -> void:
	term = term.strip_edges()
	if term == "":
		return
	var out: Array = [term]
	for t in recent_searches():
		if str(t).to_lower() != term.to_lower() and out.size() < 6:
			out.append(str(t))
	Config.set_value("shop.recent_searches", out)


# --- Wunschliste ---------------------------------------------------------------------------

## Läufe von load_wishlist, die gerade unterwegs sind (siehe dort).
var _load_wishlist_offen := 0


## Deine Wunschliste mit aktuellen Preisen. Mit der Steam-Anmeldung auch, wenn sie privat ist.
func load_wishlist() -> void:
	_load_wishlist_offen += 1
	await _load_wishlist_lauf()
	_load_wishlist_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und load_wishlist täte bis zum Neustart nichts mehr.
	if _load_wishlist_offen == 0 and wishlist_loading:
		wishlist_loading = false


## Does the wishlist need to be read (again)? Never read yet, or read as empty before the Steam login was
## complete. Otherwise the page could stay empty until "Neu laden" showed the real list. Steam probably answers a
## request for a private wishlist without login with an empty list rather than an error, and at startup Uzai reads
## it before the login is complete. This is not confirmed, but a second read does no harm.
func wishlist_noetig() -> bool:
	if wishlist_loading:
		return false
	return not wishlist_loaded or (wishlist.is_empty() and not wishlist_angemeldet and SteamChat.logged_in())


func _load_wishlist_lauf() -> void:
	if wishlist_loading:
		return
	wishlist_loading = true
	var angemeldet := SteamChat.logged_in()
	# Eine leere Seite zeigt gleich, dass geladen wird („Neu laden“ blieb sonst ohne jede Regung).
	if wishlist.is_empty():
		updated.emit()
	if Library.demo:
		while loading:
			await get_tree().process_frame
		if lists.is_empty():
			await refresh()
		var demo_ids: Array = _demo_data().get("wishlist", [])
		wishlist = await _items(demo_ids)
		wishlist_loaded = true
		_note_sales()
		wishlist_loading = false
		updated.emit()
		return
	var sid := await Social.steam_id()
	if sid == "":
		wishlist_loading = false
		updated.emit()
		return
	var r := await Net.get_json(WISHLIST + await Social.steam_query({ "steamid": sid }))
	var ids: Array = []
	if r.ok and r.data is Dictionary:
		var resp: Dictionary = r.data.get("response", {}) if r.data.get("response") is Dictionary else {}
		var items := Fremd.zeilen(resp.get("items"))
		items.sort_custom(func(a, b): return int(a.get("priority", 0)) < int(b.get("priority", 0)))
		for it in items:
			ids.append(int(it.get("appid", 0)))
		wishlist_error = ""
	else:
		wishlist_error = "Die Wunschliste ist privat." if int(r.code) in [401, 403] else "Steam antwortet gerade nicht."
	var out: Array = []
	for i in range(0, mini(ids.size(), 150), 50):
		out.append_array(await _items(ids.slice(i, i + 50)))
	if r.ok:
		wishlist = out
		wishlist_loaded = true
		wishlist_angemeldet = angemeldet
		_note_sales()
	wishlist_loading = false
	updated.emit()


func wishlisted(appid: int) -> bool:
	for it in wishlist:
		if int(it.get("appid", 0)) == appid:
			return true
	return false


## Darf Uzai die Wunschliste und den Warenkorb ändern? Dafür braucht es die Steam-Anmeldung per QR.
func can_change() -> bool:
	return Library.demo or SteamChat.logged_in()


## Spiel auf die Wunschliste setzen oder davon nehmen – direkt über dein Steam-Konto.
## Rückgabe: { ok, text, login } – login: Es fehlt die Anmeldung (oder sie ist abgelaufen).
func set_wishlisted(appid: int, on: bool, item: Dictionary = {}) -> Dictionary:
	if appid <= 0:
		return { "ok": false, "login": false, "text": "Unbekanntes Spiel." }
	if Library.demo:
		_set_local_wish(appid, on, item)
		return { "ok": true, "login": false, "text": "" }
	var tok := await _user_token()
	if tok == "":
		return { "ok": false, "login": true, "text": "Für die Wunschliste meldest du dich einmal mit der Steam-App an." }
	var r := await _service_post(WISH_ADD if on else WISH_REMOVE, { "access_token": tok, "appid": appid })
	# Schon drauf (29: doppelt) bzw. schon weg (42: nicht gefunden) zählt als erledigt.
	if bool(r.ok) or int(r.eresult) in [29, 42]:
		_set_local_wish(appid, on, item)
		return { "ok": true, "login": false, "text": "" }
	return { "ok": false, "login": int(r.code) in [401, 403] or int(r.eresult) == 15,
		"text": service_error(int(r.code), int(r.eresult), "Die Wunschliste") }


func _set_local_wish(appid: int, on: bool, item: Dictionary) -> void:
	if on and not wishlisted(appid):
		var it := item if not item.is_empty() else known_item(appid)
		if it.is_empty():
			it = { "appid": appid, "name": "", "price": 0, "original": 0, "discount": 0, "currency": "",
				"header": CDN % [appid, "header.jpg"], "capsule": CDN % [appid, "capsule_616x353.jpg"], "until": 0 }
		wishlist.push_front(it)
	elif not on:
		wishlist = wishlist.filter(func(x): return int(x.get("appid", 0)) != appid)
	wishlist_changed.emit(appid, on)
	updated.emit()


## Ein Spiel, das Uzai schon aus einer Liste kennt ({} wenn nicht).
func known_item(appid: int) -> Dictionary:
	var pools: Array = [wishlist, _retro_classics]
	if Library.demo:
		pools.append(_demo_retro())
	for k in lists.keys():
		pools.append(lists[k])
	for g in genre_lists.values():
		for t in (g as Dictionary).values():
			pools.append(t)
	for pool in pools:
		for it in pool:
			if it is Dictionary and int(it.get("appid", 0)) == appid:
				return it
	return {}


# --- Spiele der Freunde ------------------------------------------------------------------------

const FRIENDS_TTL_MS := 600000       ## die Reihe „Bei deinen Freunden“ höchstens alle 10 Minuten neu fragen
var _friend_items := { "key": "", "items": [], "at": -600000 }
var _friend_busy := false


## Shop-Einträge (Name, Preis, Bilder) zu den Spielen, die Freunde gerade spielen – dieselbe
## Store-Schnittstelle wie die Wunschliste (GetItems), gemerkt je Satz von App-IDs.
func friend_items(ids: Array) -> Array:
	var clean: Array = []
	for id in ids.slice(0, 50):
		if int(id) > 0 and not clean.has(int(id)):
			clean.append(int(id))
	if clean.is_empty():
		return []
	var key := ",".join(clean.map(func(x: int) -> String: return str(x)))
	if str(_friend_items.key) == key and Time.get_ticks_msec() - int(_friend_items.at) < FRIENDS_TTL_MS:
		return _friend_items.items
	while _friend_busy:
		await get_tree().process_frame
	if str(_friend_items.key) == key and Time.get_ticks_msec() - int(_friend_items.at) < FRIENDS_TTL_MS:
		return _friend_items.items
	_friend_busy = true
	var out: Array = await _items(clean)
	_friend_busy = false
	_friend_items = { "key": key, "items": out, "at": Time.get_ticks_msec() }
	return out


## Was zuletzt für die Freunde geladen wurde (ohne zu warten).
func friend_items_cached() -> Array:
	return _friend_items.items


# --- Warenkorb und Bezahlen ----------------------------------------------------------------

## Eine Edition (Paket) in den Warenkorb deines Steam-Kontos legen. Bezahlt wird danach in Steam.
## Rückgabe: { ok, text, login }
func add_to_cart(packageid: int) -> Dictionary:
	if packageid <= 0:
		return { "ok": false, "login": false, "text": "Für dieses Spiel bietet Steam gerade keine Kaufoption an." }
	if Library.demo:
		return { "ok": true, "login": false, "text": "" }
	var tok := await _user_token()
	if tok == "":
		return { "ok": false, "login": true, "text": "Für den Warenkorb meldest du dich einmal mit der Steam-App an." }
	var input := JSON.stringify({ "user_country": Config.land(), "items": [{ "packageid": packageid }] })
	var r := await _service_post(CART_ADD, { "access_token": tok, "input_json": input })
	if bool(r.ok):
		return { "ok": true, "login": false, "text": "" }
	return { "ok": false, "login": int(r.code) in [401, 403] or int(r.eresult) == 15,
		"text": service_error(int(r.code), int(r.eresult), "Der Warenkorb") }


## Der letzte Schritt: Steam zeigt den Warenkorb, dort wird bezahlt.
func open_cart() -> void:
	if Config.kid_stop("shop"):
		return
	if not Library.demo:
		OS.shell_open(CART_PAGE)


## Rückfall ohne Steam-Anmeldung: die Seite des Spiels im Steam-Client.
func open_in_steam(appid: int) -> void:
	if not Library.demo:
		OS.shell_open("steam://store/%d" % appid)


## Kostenlose Spiele holt sich der Steam-Client selbst (Lizenz und Installation in einem).
func install_free(appid: int) -> void:
	if not Library.demo:
		OS.shell_open("steam://install/%d" % appid)


## Zugang für Änderungen am Konto: nur der Zugang aus der QR-Anmeldung, nie ein API-Schlüssel.
func _user_token() -> String:
	var auth: Dictionary = await Social.steam_auth()
	if str(auth.get("access_token", "")) != "":
		return str(auth.access_token)
	if SteamChat.logged_in() and not SteamChat.demo:
		return await SteamChat._token()
	return ""


## POST an eine Steam-Dienstschnittstelle. Steam meldet Fehler oft mit HTTP 200 und dem Kopf
## „x-eresult“ (1 = in Ordnung). Rückgabe: { ok, code, eresult, data, message }
func _service_post(url: String, fields: Dictionary) -> Dictionary:
	var parts := PackedStringArray()
	for k in fields.keys():
		parts.append("%s=%s" % [str(k).uri_encode(), str(fields[k]).uri_encode()])
	var r: Dictionary = await Net.request(url, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), HTTPClient.METHOD_POST, "&".join(parts))
	var head := read_eresult(r.get("headers", PackedStringArray()))
	var data: Variant = null
	var body: PackedByteArray = r.get("body", PackedByteArray())
	if body.size() > 0:
		data = Fremd.json(body.get_string_from_utf8())
	return { "ok": bool(r.get("ok", false)) and int(head.eresult) == 1, "code": int(r.get("code", 0)),
		"eresult": int(head.eresult), "data": data, "message": str(head.message) }


# --- Bilder, Angaben, Bewertungen -----------------------------------------------------------

## Name, Preis und Bilder zu App-IDs (Store-Schnittstelle, bis 50 auf einmal).
func _items(ids: Array) -> Array:
	var out: Array = []
	if ids.is_empty():
		return out
	if Library.demo:
		var known: Dictionary = _demo_data().get("items", {}) if _demo_data().get("items") is Dictionary else {}
		for id in ids:
			var it := known_item(int(id))
			if it.is_empty() and known.get(str(id)) is Dictionary:
				var parsed := parse_items([known[str(id)]], bool(known[str(id)].get("coming_soon", false)))
				if not parsed.is_empty():
					it = parsed[0]
			if not it.is_empty():
				out.append(it)
		return out
	var q: Array = []
	for id in ids:
		q.append({ "appid": int(id) })
	var input := JSON.stringify({ "ids": q, "context": { "language": Lang.api("steam"), "country_code": Config.land() },
		"data_request": { "include_assets": true, "include_all_purchase_options": true, "include_release": true } })
	var r := await Net.get_json(ITEMS + input.uri_encode())
	if not r.ok or not (r.data is Dictionary):
		return out
	var resp: Dictionary = r.data.get("response", {}) if r.data.get("response") is Dictionary else {}
	for it in Fremd.zeilen(resp.get("store_items")):
		var e := from_store_item(it)
		if not e.is_empty():
			out.append(e)
			Media.remember_steam_assets(int(e.appid), e.assets)
	return out


## Was schon geladen ist, ohne zu warten ({} wenn noch nicht gefragt oder nichts da).
func cached(appid: int) -> Dictionary:
	return _details.get(appid, {})


func details(appid: int) -> Dictionary:
	while _busy.has(appid):
		await get_tree().process_frame
	if _details.has(appid):
		return _details[appid]
	var now := int(Time.get_unix_time_from_system())
	if now - int(_failed.get(appid, -RETRY_S)) < RETRY_S:
		return {}
	_busy[appid] = true
	var r := await Net.get_json(_url(DETAILS) % appid)
	_busy.erase(appid)
	var out := {}
	var answered := false
	if r.ok and r.data is Dictionary:
		answered = true
		var entry: Variant = r.data.get(str(appid), {})
		if entry is Dictionary and entry.get("success", false) and entry.get("data") is Dictionary:
			out = parse_details(entry.data)
	elif Library.demo:
		answered = true
		out = _demo_details(appid)
	if answered:
		_details[appid] = out
		Config.cap(_details, 200)
		# Genre und Jahr bleiben am Spiel der Bibliothek (Filter und Abschnitte im Raster).
		Library.remember_store_meta(appid, out)
	else:
		_failed[appid] = now
	return out


## Nutzerbewertungen: { label: "Sehr positiv", percent: 92, total: 12345 }
func reviews(appid: int) -> Dictionary:
	if _reviews.has(appid):
		return _reviews[appid]
	var r := await Net.get_json(REVIEWS % appid)
	var out := {}
	var data: Variant = r.data if r.ok else (_demo_get("reviews", appid) if Library.demo else null)
	if data is Dictionary and data.get("query_summary") is Dictionary:
		var q: Dictionary = data.query_summary
		var total := int(q.get("total_reviews", 0))
		var pos := int(q.get("total_positive", 0))
		out = { "label": review_label(pos, total), "percent": int(round(pos * 100.0 / total)) if total > 0 else 0, "total": total }
	if r.ok or Library.demo:
		_reviews[appid] = out
		Config.cap(_reviews, 200)
	return out


## Ein paar hilfreiche Bewertungen auf Deutsch: [{ up, text, hours, date, helpful }]
func review_texts(appid: int) -> Array:
	if _review_texts.has(appid):
		return _review_texts[appid]
	var r := await Net.get_json(_url(REVIEW_TEXTS) % appid)
	var out: Array = []
	if r.ok:
		out = parse_review_texts(r.data, 3)
	elif Library.demo:
		out = parse_review_texts(_demo_get("reviews", appid), 3)
	if r.ok or Library.demo:
		_review_texts[appid] = out
		Config.cap(_review_texts, 200)
	return out


## Neuigkeiten der Entwickler (Steam-Ankündigungen): [{ title, date, text, author, patch }]
## (patch: von den Entwicklern als Patchnotes markiert)
func news(appid: int) -> Array:
	if _news.has(appid):
		return _news[appid]
	var r := await Net.get_json(NEWS % appid)
	var out: Array = []
	if r.ok:
		out = parse_news(r.data, 3)
	elif Library.demo:
		out = parse_news(_demo_get("news", appid), 3)
	if r.ok or Library.demo:
		_news[appid] = out
		Config.cap(_news, 200)
	return out


## Erweiterungen (DLC) eines Spiels mit Preis und Bild.
func dlc_items(appid: int) -> Array:
	if _dlc.has(appid):
		return _dlc[appid]
	var d := await details(appid)
	var ids: Array = d.get("dlc_ids", [])
	var out: Array = []
	if not ids.is_empty():
		out = await _items(ids.slice(0, 40))
	_dlc[appid] = out
	Config.cap(_dlc, 200)
	return out


## Erweiterungen eines Spiels, die Steam auf diesem PC installiert hat: { appid: true }. Mehr
## weiß Uzai über den Besitz von Erweiterungen nicht (siehe SteamScanner.installed_dlc).
func dlc_installed(appid: int) -> Dictionary:
	if Library.demo or appid <= 0:
		return {}
	return SteamScanner.installed_dlc_of(Library.steam_root(), appid)


func owned(appid: int) -> bool:
	return not Library.get_game("steam:%d" % appid).is_empty()


## Schon in der Bibliothek? Steam nach App-ID, Gratis-Spiele von Epic nach ihrem Namespace
## (installiert, aus dem Launcher-Katalog oder vom Epic-Konto).
func owned_item(it: Dictionary) -> bool:
	if int(it.get("appid", 0)) > 0:
		return owned(int(it.appid))
	var ns := str(it.get("ns", ""))
	if ns == "" or str(it.get("store", "")) != "epic":
		return false
	for g in Library.games:
		if g.get("epic") is Dictionary and str(g.epic.get("namespace", "")) == ns:
			return true
	return false


func owned_ids() -> Dictionary:
	var out := {}
	for g in Library.games:
		if str(g.get("source", "")) == "steam":
			out[int(g.get("appid", 0))] = true
	return out


# --- Demo ---------------------------------------------------------------------------------

func _demo_data() -> Dictionary:
	if _demo == null:
		_demo = Config.read_json(DEMO, {})
	return _demo if _demo is Dictionary else {}


func _demo_get(kind: String, appid: int) -> Variant:
	var block: Variant = _demo_data().get(kind, {})
	if not (block is Dictionary):
		return null
	return block.get(str(appid), block.get("_default"))


## Demo statt appdetails/GetItems: Preis aus den Angaben (details) oder aus den Shop-Listen.
func _demo_prices(ids: Array) -> Dictionary:
	var out := {}
	var block: Variant = _demo_data().get("details", {})
	for id in ids:
		var d: Variant = block.get(str(id)) if block is Dictionary else null
		if d is Dictionary:
			var p := parse_price_batch(
					{ str(id): { "success": true, "data": { "price_overview": d.get("price_overview") } if d.get("price_overview") is Dictionary else [] } })
			out[int(id)] = p.get(int(id), { "has_price": false })
			out[int(id)]["free"] = bool(d.get("is_free", false))
			continue
		for k in lists.keys():
			for it in lists[k]:
				if int(it.get("appid", 0)) == int(id) and int(it.get("price", 0)) > 0:
					out[int(id)] = { "has_price": true, "price": int(it.price), "original": int(it.get("original", it.price)), "discount": int(it.get("discount", 0)) }
		if not out.has(int(id)):
			out[int(id)] = { "has_price": false }
	return out


## Angaben für den Demo-Modus: eigene Einträge, sonst ein Beispiel mit dem Namen des Spiels.
func _demo_details(appid: int) -> Dictionary:
	var block: Variant = _demo_data().get("details", {})
	if not (block is Dictionary):
		return {}
	if block.get(str(appid)) is Dictionary:
		return parse_details(block[str(appid)])
	if not (block.get("_default") is Dictionary):
		return {}
	var d: Dictionary = (block["_default"] as Dictionary).duplicate(true)
	var it := known_item(appid)
	d["name"] = str(it.get("name", "Spiel"))
	var out := parse_details(d)
	# Die Vorlage kennt nur einen festen Preis: Die Seite zeigte den der Liste (9,99 €), der
	# Kauf-Dialog den der Vorlage (19,99 €). Die eine Kaufoption trägt den Preis des Spiels.
	var eds: Array = out.get("editions", [])
	if int(it.get("price", 0)) > 0 and eds.size() == 1 and eds[0] is Dictionary:
		for k in ["price", "original", "discount"]:
			eds[0][k] = int(it.get(k, 0))
		eds[0]["original"] = maxi(int(eds[0]["original"]), int(eds[0]["price"]))
	return out


## Demo: offizielle Retro-Sammlungen (tests/demo_store.json „retro“), wie Treffer der Suche.
func _demo_retro() -> Array:
	var raw: Variant = _demo_data().get("retro", [])
	return parse_items(raw if raw is Array else [])


# --- Retro-Klassiker (Roadmap 130) ---------------------------------------------------------------
# Für die Reihe im Shop: offizielle Sammlungen klassischer Spiele im Steam-Shop – über die
# vorhandene Shop-Suche (storesearch), nichts anderes. Welche Treffer passen, entscheidet
# RetroKlassiker (nur die bekannten Sammlungen). Antworten liegen drei Tage im Datenordner, damit der
# Shop nicht bei jedem Öffnen fragt. Nie ROM-, BIOS- oder Firmware-Quellen (R5).

const RetroKlassiker := preload("res://src/core/retro_klassiker.gd")
const RETRO_CACHE := "cache/retro_shop.json"
const RETRO_TTL := 3 * 86400
const RETRO_KEEP := 240              ## so viele Suchwörter merkt sich der Zwischenspeicher
const RETRO_GAP := 0.25              ## Pause zwischen zwei Suchen (Sekunden), Steam nicht bedrängen
var _retro := {}                     ## Suchwort (klein) -> { t, ok, items: [{ appid, name }] }
var _retro_loaded := false
var _retro_busy := {}
var _retro_classics: Array = []
var _retro_classics_busy := false
var _retro_classics_at := 0          ## letzter Versuch (ms)


func _retro_load() -> void:
	if _retro_loaded:
		return
	_retro_loaded = true
	var disk: Variant = Config.read_json(Config.path(RETRO_CACHE), {})
	if not (disk is Dictionary):
		return
	var now := int(Time.get_unix_time_from_system())
	for k in disk.keys():
		var e: Variant = disk[k]
		if not (k is String) or (k as String).length() > 120 or not (e is Dictionary):
			continue
		var t := int(e.get("t", 0)) if (e.get("t") is int or e.get("t") is float) else 0
		if now - t > RETRO_TTL or t > now + 86400:
			continue
		_retro[k] = { "t": t, "ok": true, "items": RetroKlassiker.clean_cached(e.get("items")) }
		if _retro.size() >= RETRO_KEEP:
			break


## Zwischenspeicher schreiben – gebündelt: mehrere Suchen hintereinander schreiben einmal.
var _retro_save_due := false


func _retro_save_soon() -> void:
	if _retro_save_due:
		return
	_retro_save_due = true
	await get_tree().create_timer(2.0).timeout
	_retro_save_due = false
	_retro_save()


func _retro_save() -> void:
	var out := {}
	for k in _retro.keys():
		var e: Dictionary = _retro[k]
		if bool(e.get("ok", false)):
			out[k] = { "t": int(e.t), "items": (e.items as Array).map(func(it: Dictionary) -> Dictionary: return { "appid": int(it.appid), "name": str(it.name) }) }
	Config.write_json(Config.path(RETRO_CACHE), out)


## Eine Shop-Suche für die Retro-Klassiker (gemerkt). { ok, items }: items nur mit appid und Namen
## (für RetroKlassiker.pick); Preise und Bilder holt retro_items für die gewählten Treffer.
func retro_search(term: String) -> Dictionary:
	_retro_load()
	var k := term.strip_edges().to_lower().left(120)
	if k == "":
		return { "ok": false, "items": [] }
	while _retro_busy.has(k):
		await get_tree().process_frame
	var now := int(Time.get_unix_time_from_system())
	var have: Dictionary = _retro.get(k, {})
	if not have.is_empty() and now - int(have.get("t", 0)) < RETRO_TTL:
		return have
	_retro_busy[k] = true
	var r: Dictionary = await search_raw(term)
	_retro_busy.erase(k)
	var items: Array = (r.items as Array).map(func(it: Dictionary) -> Dictionary: return { "appid": int(it.appid), "name": str(it.name) })
	var e := { "t": now, "ok": bool(r.ok), "items": items.slice(0, 20) }
	if bool(r.ok):
		_retro[k] = e
		while _retro.size() > RETRO_KEEP:
			_retro.erase(_retro.keys()[0])
		_retro_save_soon()
	return e


## Aus gewählten Treffern ganze Shop-Einträge (Preis, Bild): bekannte aus den Listen, sonst neu
## gebaut (wie ein Treffer der Suche), Preise einmal gebündelt nachgefragt.
func retro_items(picked: Array) -> Array:
	var out: Array = []
	for it in picked:
		var id := int((it as Dictionary).get("appid", 0))
		var known := known_item(id)
		if not known.is_empty():
			out.append(known)
		else:
			out.append(parse_search_item({ "id": id, "name": str(it.get("name", "")) }))
	Media.prefetch_steam_assets(ids_of(out))
	await fill_prices(out)
	return out


## Reihe „Retro-Klassiker“ im Shop: die bekannten Sammlungen, je der passende Treffer. Einmal je
## Sitzung (und aus dem Zwischenspeicher); signalisiert über updated.
func retro_classics() -> Array:
	return _retro_classics


## Läufe von load_retro_classics, die gerade unterwegs sind (siehe dort).
var _load_retro_classics_offen := 0


func load_retro_classics() -> void:
	_load_retro_classics_offen += 1
	await _load_retro_classics_lauf()
	_load_retro_classics_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und load_retro_classics täte bis zum Neustart nichts mehr.
	if _load_retro_classics_offen == 0 and _retro_classics_busy:
		_retro_classics_busy = false


func _load_retro_classics_lauf() -> void:
	var now_ms := Time.get_ticks_msec()
	if _retro_classics_busy or not _retro_classics.is_empty() or (_retro_classics_at > 0 and now_ms - _retro_classics_at < 600000):
		return
	_retro_classics_at = now_ms     # ohne Netz frühestens nach 10 Minuten wieder
	_retro_classics_busy = true
	var lists_found: Array = []
	for c in RetroKlassiker.shop_collections():
		var k := str(c.suche).to_lower()
		var cached := _retro.has(k)
		var r: Dictionary = await retro_search(str(c.suche))
		if not bool(r.ok):
			break
		lists_found.append(RetroKlassiker.pick(r.items, str(c.suche), 1, true))
		if not cached:
			await get_tree().create_timer(RETRO_GAP).timeout
	var picked := RetroKlassiker.merge_unique(lists_found, 24)
	if not picked.is_empty():
		_retro_classics = await retro_items(picked)
	_retro_classics_busy = false
	if not _retro_classics.is_empty():
		updated.emit()


# --- Gratis und Angebote -------------------------------------------------------------------
# Gratis-Spiele der Woche bei Epic (öffentliche Liste, ohne Anmeldung) und zeitweise kostenlose
# bei Steam (Angebote mit −100 %). „Holen“ geht immer beim Anbieter: Uzai zeigt die Seite als
# QR-Code und öffnet sie nur auf Knopfdruck – es holt oder kauft nie selbst.

## Läufe von load_free, die gerade unterwegs sind (siehe dort).
var _load_free_offen := 0


## Epic-Gratis-Spiele laden (Zwischenspeicher im Datenordner, höchstens alle FREE_TTL Sekunden;
## früher, wenn ein Angebot abgelaufen ist – aber nach einem Fehlschlag nicht vor FREE_RETRY_S).
func load_free(force := false) -> void:
	_load_free_offen += 1
	await _load_free_lauf(force)
	_load_free_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und load_free täte bis zum Neustart nichts mehr.
	if _load_free_offen == 0 and free_loading:
		free_loading = false


func _load_free_lauf(force := false) -> void:
	if free_loading:
		return
	var now := int(Time.get_unix_time_from_system())
	if free_epic.is_empty() and _free_at == 0 and not Library.demo:
		var c: Variant = Config.read_json(Config.path(FREE_CACHE), {})
		if c is Dictionary and c.get("items") is Array:
			_free_at = int(c.get("at", 0))
			free_epic = free_from_cache(c.items, now)
	var due := now - _free_at >= FREE_TTL or free_stale(free_epic, now)
	if not force and (not due or now - _free_tried < FREE_RETRY_S):
		return
	_free_tried = now
	free_loading = true
	var data: Variant = null
	var at := now
	if Library.demo:
		# Die Beispiele gelten ab ihrem Stichtag – verschoben, als wäre heute dieser Tag.
		data = _demo_data().get("epic_free")
		var ref := iso_time(str(_demo_data().get("epic_free_ref", "")))
		at = ref if ref > 0 else now
	else:
		var r := await Net.get_json(_url(EPIC_FREE) % str(Lang.api("epic")))
		data = r.data if r.ok else null
	free_loading = false
	if data == null:
		return
	free_epic = parse_epic_free(data, at, str(Lang.api("epic")))
	for it in free_epic:
		it["from"] = int(it.from) + now - at
		it["until"] = int(it.until) + now - at
	_free_at = now
	if not Library.demo:
		Config.write_json(Config.path(FREE_CACHE), { "at": now, "items": free_epic })
	updated.emit()


## Jetzt gratis: Epic und Steam (−100 %), was zuerst endet, zuerst.
func free_now() -> Array:
	var now := int(Time.get_unix_time_from_system())
	var out: Array = free_epic.filter(func(x: Dictionary) -> bool: return not bool(x.upcoming) and (int(x.until) == 0 or int(x.until) > now))
	out.append_array(steam_giveaways(lists))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _end_key(a) < _end_key(b))
	return out


## Bald gratis (Epic kündigt die nächste Woche an), was zuerst beginnt, zuerst.
func free_soon() -> Array:
	var out: Array = free_epic.filter(func(x: Dictionary) -> bool: return bool(x.upcoming))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("from", 0)) < int(b.get("from", 0)))
	return out


## Nach dem Laden der Wunschliste: neue Angebote einmal melden (Einstellungen → Mitteilungen).
func _note_sales() -> void:
	var path := Config.path(SALES_CACHE)
	var c: Variant = Config.read_json(path, {})
	var seen: Dictionary = c.get("seen", {}) if c is Dictionary and c.get("seen") is Dictionary else {}
	var now := int(Time.get_unix_time_from_system())
	var res := sale_news(wishlist, seen, now)
	Config.write_json(path, { "seen": res.seen })
	# Kennzeichnung in der Wunschliste: seit höchstens SALE_NEW_S im Angebot.
	sale_new.clear()
	for id in res.seen:
		if now - int(res.seen[id].at) < SALE_NEW_S:
			sale_new[int(id)] = true
	if Library.demo or not bool(Config.get_value("notify.wish_sales", true)):
		return
	show_sales(res.new)


## Neue Angebote melden: bis SALES_SINGLE je eine Mitteilung, mehr auf einmal (Steam-Sale) zusammen.
func show_sales(fresh: Array) -> void:
	if fresh.size() <= SALES_SINGLE:
		for it in fresh:
			_sale_toast(sale_toast([it]))
	else:
		_sale_toast(sale_toast(fresh))


func _sale_toast(t: Dictionary) -> void:
	if t.is_empty():
		return
	var tree := get_tree()
	var go := func() -> void:
		var m: Node = tree.current_scene
		if m and m.has_method("goto"):
			m.call("goto", "shop", "wunschliste")
	Toasts.show_toast(str(t.title), str(t.sub), "shop", { "ms": 7000, "open": go, "open_text": "Wunschliste", "go": go, "go_text": "Wunschliste", "stoert": true })
