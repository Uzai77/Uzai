extends Node
## Steam-Shop, untere Schicht: reine Funktionen ohne Netz und ohne Zustand – Antworten der
## Store-Schnittstellen lesen (Spiele, Preise, Details, Editionen, Anforderungen, Bewertungen,
## Neuigkeiten), Bild-Adressen, Texte für Preise und Fehler, Gratis-Spiele von Epic und Steam.
## Darum offline prüfbar (tests/logic_shop.gd, tests/logic_angebote.gd). store.gd erbt davon.

const Lang := preload("res://src/core/lang.gd")
const CDN := "https://shared.steamstatic.com/store_item_assets/steam/apps/%d/%s"
const EPIC_PAGE := "https://store.epicgames.com/%s/p/%s"

const MediaS := preload("res://src/core/media.gd")


## Bilder eines Shop-Eintrags, beste zuerst – mit dem, was Uzai schon über die Bilder weiß
## (Store-Angaben im Eintrag oder im gemeinsamen Speicher von Media).
static func art_urls(it: Dictionary, portrait := true, want_px := 0) -> Array:
	var a := art_assets(it)
	if a.is_empty() and int(it.get("appid", 0)) > 0:
		a = Media.cached_steam_assets(int(it.appid))
	return art_urls_from(it, a, portrait, want_px)


## Bildangaben, die ein Eintrag selbst mitbringt (aus GetItems), sonst {}.
static func art_assets(it: Dictionary) -> Dictionary:
	return it.get("assets", {}) if it.get("assets") is Dictionary else {}


## Bildadressen aus den Store-Angaben (a: assets aus GetItems, {} wenn unbekannt), beste zuerst.
## Hochformat: Steams Hülle (600 × 900) unter ihrem echten Namen – bei neuen Spielen liegt sie in
## einem Ordner mit Prüfsumme, die alte feste Adresse gibt es dort nicht. Nur wenn Steam nichts
## gesagt hat, kommen die alten Adressen dran. Danach das Kapselbild und das Kopfbild (quer; die
## Karte zeigt sie dann unverzerrt). want_px: so breit wird das Bild gebraucht – bis 600 Punkte
## reicht die einfache Hülle, darüber kommt die doppelte zuerst.
static func art_urls_from(it: Dictionary, a: Dictionary, portrait := true, want_px := 0) -> Array:
	var out: Array = []
	var id := int(it.get("appid", 0))
	if portrait and id > 0:
		var covers: Array = MediaS.asset_urls(a, "cover", str(id))
		if str(a.get("asset_url_format", "")) == "":
			covers = [CDN % [id, "library_600x900_2x.jpg"], CDN % [id, "library_600x900.jpg"]]
		if want_px > 0 and want_px <= 600:
			covers.reverse()
		_add(out, covers)
	_add(out, MediaS.asset_urls(a, "capsule", str(id)))
	_add(out, [str(it.get("capsule", ""))])
	_add(out, MediaS.asset_urls(a, "wide", str(id)))
	_add(out, [str(it.get("header", ""))])
	return out


## Großes Bild für die Seite eines Spiels und das Rampenlicht (library_hero), beste zuerst.
static func hero_urls(appid: int, a: Dictionary, want_px := 1920) -> Array:
	var out: Array = MediaS.asset_urls(a, "hero", str(appid))
	if want_px <= 1920:
		out.reverse()
	if str(a.get("asset_url_format", "")) == "":
		out = [CDN % [appid, "library_hero.jpg"]]
	return out


## Schriftzug des Spiels (library_logo), beste zuerst.
static func logo_urls(appid: int, a: Dictionary) -> Array:
	if str(a.get("asset_url_format", "")) == "":
		return [CDN % [appid, "logo.png"]]
	return MediaS.asset_urls(a, "logo", str(appid))


static func _add(out: Array, urls: Array) -> void:
	for u in urls:
		if str(u) != "" and not out.has(str(u)):
			out.append(str(u))


## App-IDs einer Liste von Einträgen (für das gebündelte Vorab-Holen der Bildangaben).
static func ids_of(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if it is Dictionary and int(it.get("appid", 0)) > 0:
			out.append(int(it.appid))
	return out


## Einträge aus featuredcategories / getappsingenre in Uzais Form (ohne Pakete, ohne doppelte).
## coming: die Liste „Bald“ – dort steht oft noch kein Preis.
## Preis 0 heißt hier nur „kein Preis mitgeschickt“ (getappsingenre schickt fast immer 0), nicht
## „kostenlos“: free bleibt aus, bis fill_prices nachgefragt hat.
static func parse_items(raw: Array, coming := false) -> Array:
	var items: Array = []
	var seen := {}
	for it in raw:
		if not (it is Dictionary):
			continue
		var id := int(it.get("id", 0))
		if id == 0 or seen.has(id) or int(it.get("type", 0)) != 0:
			continue
		seen[id] = true
		items.append({
			"appid": id, "name": str(it.get("name", "")),
			"discount": int(it.get("discount_percent", 0)),
			"price": int(it.get("final_price", 0)) if it.get("final_price") != null else 0,
			"original": int(it.get("original_price", 0)) if it.get("original_price") != null else 0,
			"currency": str(it.get("currency", "")),
			"header": str(it.get("header_image", "")) if str(it.get("header_image", "")) != "" else CDN % [id, "header.jpg"],
			"capsule": str(it.get("large_capsule_image", "")) if str(it.get("large_capsule_image", "")) != "" else CDN % [id, "capsule_616x353.jpg"],
			"until": int(it.get("discount_expiration", 0)) if it.get("discount_expiration") != null else 0,
			"coming": coming or bool(it.get("coming_soon", false)),
			"free": false,
		})
	return items


## Ein Treffer aus storesearch. Ohne „price“ bleibt der Preis offen (0), nicht „kostenlos“.
static func parse_search_item(it: Dictionary) -> Dictionary:
	var id := int(it.get("id", 0))
	var pr: Dictionary = it.get("price", {}) if it.get("price") is Dictionary else {}
	var fin := int(pr.get("final", 0))
	var ini := maxi(int(pr.get("initial", fin)), fin)
	return { "appid": id, "name": str(it.get("name", "")), "price": fin, "original": ini,
		"discount": int(round(100.0 - fin * 100.0 / ini)) if ini > 0 and fin < ini else 0,
		"currency": str(pr.get("currency", "")), "header": CDN % [id, "header.jpg"], "capsule": CDN % [id, "capsule_616x353.jpg"],
		"until": 0, "metascore": int(str(it.get("metascore", "0"))) if str(it.get("metascore", "")).is_valid_int() else 0,
		"free": false, "checked": fin > 0 }


## Kategorien für die Suche im Shop: [Nummer des Steam-Tags, Anzeige]. Die Nummern stammen aus Steams eigener
## Liste (store.steampowered.com/tagdata/populartags), nachgesehen im November 2026.
const SUCH_KATEGORIEN := [
	[19, "Action"], [21, "Abenteuer"], [122, "Rollenspiel"], [9, "Strategie"], [599, "Simulation"], [492, "Indie"],
	[1774, "Shooter"], [1625, "Plattformer"], [1664, "Rätsel"], [1667, "Horror"], [1662, "Survival"], [1695, "Open World"],
	[1716, "Roguelike"], [699, "Rennspiel"], [701, "Sport"], [1743, "Kampfspiel"], [597, "Gelegenheit"],
	[1685, "Koop"], [3841, "Lokaler Koop"], [3859, "Mehrspieler"], [113, "Kostenlos"],
]
const SUCH_TAGS_MAX := 3          ## so viele Kategorien zugleich (jede weitere engt weiter ein)
const SUCH_TREFFER_MAX := 36


## Nur Nummern, die Uzai als Kategorie kennt, jede einmal, höchstens SUCH_TAGS_MAX – was in die Adresse der
## Suche darf.
static func such_tags(tags: Variant) -> Array:
	var out: Array = []
	if not (tags is Array):
		return out
	for t in tags:
		var nr := _whole(t)
		if out.has(nr) or out.size() >= SUCH_TAGS_MAX:
			continue
		if SUCH_KATEGORIEN.any(func(k: Array) -> bool: return int(k[0]) == nr):
			out.append(nr)
	return out


## Anzeige-Namen dieser Kategorien („Action, Koop“), übersetzt.
static func such_tag_namen(tags: Array) -> String:
	var namen := PackedStringArray()
	for k in SUCH_KATEGORIEN:
		if tags.has(int(k[0])):
			namen.append(TranslationServer.translate(str(k[1])))
	return ", ".join(namen)


## Antwort der Shop-Suche mit Kategorien (search/results, json=1): { items: [{ name, logo }] } – ohne Nummer und
## ohne Preis. Die Nummer des Spiels steht nur in der Adresse des Bilds (…/steam/apps/620/…); Pakete und Bundles
## (…/subs/…, …/bundles/…) haben keine Spieleseite und bleiben weg. Preise holt danach fill_prices.
static func parse_suche_gefiltert(data: Variant, max_n := SUCH_TREFFER_MAX) -> Array:
	var out: Array = []
	if not (data is Dictionary) or not ((data as Dictionary).get("items") is Array):
		return out
	var re := RegEx.create_from_string("/steam/apps/(\\d{1,10})/")
	for it in (data as Dictionary)["items"]:
		if out.size() >= max_n:
			break
		if not (it is Dictionary) or not (it.get("logo") is String) or not (it.get("name") is String):
			continue
		var m := re.search(str(it.logo))
		var id := int(m.get_string(1)) if m != null else 0
		var name := str(it.name).strip_edges().left(200)
		if id <= 0 or name == "":
			continue
		out.append({ "appid": id, "name": name, "price": 0, "original": 0, "discount": 0, "currency": "",
			"header": CDN % [id, "header.jpg"], "capsule": CDN % [id, "capsule_616x353.jpg"], "until": 0, "metascore": 0,
			"free": false, "checked": false })
	return out


# --- Preise nachfragen -----------------------------------------------------------------------

## Braucht der Eintrag noch einen Preis? (nicht kostenlos, kein Preis, noch nicht nachgefragt)
static func needs_price(it: Variant) -> bool:
	return it is Dictionary and int(it.get("appid", 0)) > 0 and not bool(it.get("free", false)) \
		and int(it.get("price", 0)) <= 0 and not bool(it.get("checked", false))


## Nachgefragte Preise in die Einträge schreiben. found: appid -> { has_price, price, original,
## discount, currency?, free? }. Rückgabe: true, wenn sich etwas geändert hat.
static func apply_prices(items: Array, found: Dictionary) -> bool:
	var changed := false
	for it in items:
		if not (it is Dictionary) or not found.has(int(it.get("appid", 0))):
			continue
		var p: Dictionary = found[int(it.appid)]
		it["checked"] = true
		if bool(p.get("has_price", false)):
			it["price"] = int(p.price)
			it["original"] = int(p.get("original", p.price))
			it["discount"] = int(p.get("discount", 0))
			if p.has("currency"):
				it["currency"] = str(p.currency)
			changed = true
		if bool(p.get("free", false)):
			it["free"] = true
			changed = true
	return changed


## Antwort von appdetails?appids=…&filters=price_overview: appid -> { has_price, price, original,
## discount, currency }. Kostenlose (und noch nicht kaufbare) Spiele schicken data: [] – dann
## has_price = false. Erfolglose Einträge fehlen (dort bleibt der Preis offen).
static func parse_price_batch(data: Variant) -> Dictionary:
	var out := {}
	if not (data is Dictionary):
		return out
	for k in (data as Dictionary).keys():
		var e: Variant = data[k]
		if not str(k).is_valid_int() or not (e is Dictionary) or not bool(e.get("success", false)):
			continue
		var d: Variant = e.get("data")
		var po: Variant = d.get("price_overview") if d is Dictionary else null
		if po is Dictionary and str(po.get("final", "")).is_valid_float():
			var fin := int(po.final)
			var ini := maxi(int(po.get("initial", fin)) if str(po.get("initial", "")).is_valid_float() else fin, fin)
			out[int(str(k))] = { "has_price": fin > 0, "price": fin, "original": ini,
				"discount": int(po.get("discount_percent", 0)) if str(po.get("discount_percent", "")).is_valid_float() else 0,
				"currency": str(po.get("currency", "")) }
		else:
			out[int(str(k))] = { "has_price": false }
	return out


## Was auf der Preis-Pille steht: „Kostenlos“ nur bei echtem is_free, sonst der Preis – und
## ohne bekannten Preis gar nichts.
static func price_label(it: Dictionary) -> String:
	if bool(it.get("free", false)):
		return "Kostenlos"
	if int(it.get("price", 0)) > 0:
		return price_text(int(it.price), str(it.get("currency", "")))
	return ""


## Jede App nur einmal (Reihenfolge bleibt).
static func unique(items: Array) -> Array:
	var seen := {}
	var out: Array = []
	for it in items:
		if it is Dictionary and not seen.has(int(it.get("appid", 0))):
			seen[int(it.get("appid", 0))] = true
			out.append(it)
	return out


# --- Warenkorb und Bezahlen ----------------------------------------------------------------

## Steht das Paket laut Antwort von AddItemsToCart im Warenkorb?
static func cart_has(data: Variant, packageid: int) -> bool:
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return false
	var resp: Dictionary = data.response
	if resp.get("line_item_ids") is Array and not (resp.line_item_ids as Array).is_empty():
		return true
	var cart: Variant = resp.get("cart")
	if cart is Dictionary and cart.get("line_items") is Array:
		for li in cart.line_items:
			if li is Dictionary and int(li.get("packageid", 0)) == packageid:
				return true
	return false


## eresult und Fehlertext aus den Antwortköpfen (fehlt der Kopf, gilt 1 = in Ordnung).
static func read_eresult(headers: Variant) -> Dictionary:
	var out := { "eresult": 1, "message": "" }
	if not (headers is PackedStringArray or headers is Array):
		return out
	for h in headers:
		var line := str(h)
		var low := line.to_lower()
		if low.begins_with("x-eresult:"):
			var v := line.substr(10).strip_edges()
			if v.is_valid_int():
				out.eresult = int(v)
		elif low.begins_with("x-error_message:"):
			out.message = line.substr(16).strip_edges()
	return out


## Verständliche Meldung zu einem Fehler der Steam-Schnittstellen.
static func service_error(code: int, eresult: int, what: String) -> String:
	if code in [401, 403] or eresult == 15:
		return "Steam hat die Anmeldung nicht angenommen. Bitte neu mit der Steam-App anmelden."
	if code == 0:
		return "Steam ist gerade nicht erreichbar. Ist das Internet da?"
	if code == 429 or eresult == 84:
		return "Steam bremst gerade zu viele Anfragen. Gleich noch einmal versuchen."
	if code >= 500:
		return "Steam hat gerade Probleme. Später noch einmal versuchen."
	if eresult != 1:
		return "%s ließ sich nicht ändern. Steam hat abgelehnt – später noch einmal versuchen." % what
	return "%s ließ sich nicht ändern. Gleich noch einmal versuchen." % what


# --- Trailer ------------------------------------------------------------------------------

## Ein Trailer als Eintrag für den Videoplayer (wie ein YouTube-Video, aber mit direkter Adresse).
static func trailer_video(item: Dictionary, mv: Dictionary) -> Dictionary:
	var nm := str(item.get("name", ""))
	var mname := str(mv.get("name", ""))
	var title := nm if mname == "" or mname.to_lower() == nm.to_lower() else "%s – %s" % [nm, mname]
	return { "id": "steam-trailer-%d" % int(mv.get("id", 0)), "title": title, "channel": "Trailer aus dem Steam-Shop",
		"url": str(mv.get("url", "")), "thumb": str(mv.get("thumb", "")), "duration": 0, "source": "steam_trailer" }


# --- Bilder, Angaben, Bewertungen -----------------------------------------------------------

static func from_store_item(it: Variant) -> Dictionary:
	if not (it is Dictionary) or int(it.get("appid", 0)) == 0:
		return {}
	var id := int(it.appid)
	var bp: Dictionary = it.get("best_purchase_option", {}) if it.get("best_purchase_option") is Dictionary else {}
	var fin := int(str(bp.get("final_price_in_cents", "0"))) if str(bp.get("final_price_in_cents", "0")).is_valid_int() else 0
	var ori := maxi(int(str(bp.get("original_price_in_cents", fin))) if str(bp.get("original_price_in_cents", "")).is_valid_int() else fin, fin)
	var a: Dictionary = it.get("assets", {}) if it.get("assets") is Dictionary else {}
	var header := CDN % [id, "header.jpg"]
	var capsule := CDN % [id, "capsule_616x353.jpg"]
	var hs := MediaS.asset_urls(a, "wide", str(id))
	var cs := MediaS.asset_urls(a, "capsule", str(id))
	if not hs.is_empty():
		header = str(hs[0])
	if not cs.is_empty():
		capsule = str(cs[0])
	var rel: Dictionary = it.get("release", {}) if it.get("release") is Dictionary else {}
	# Ende des Rabatts (wie im Shop: „Angebot bis …“), wenn Steam es mitschickt.
	var until := 0
	for d in (bp.get("active_discounts", []) if bp.get("active_discounts") is Array else []):
		if d is Dictionary:
			until = maxi(until, _whole(d.get("discount_end_date")))
	# DLC: zu welchem Spiel es gehört (lebendige Kacheln zeigen „DLC −30 %“ am Spiel).
	var rel_items: Dictionary = it.get("related_items", {}) if it.get("related_items") is Dictionary else {}
	return { "appid": id, "name": str(it.get("name", "")), "price": fin, "original": ori,
		"discount": int(bp.get("discount_pct", 0)), "currency": "", "header": header,
		"capsule": capsule, "until": until, "assets": a, "parent": _whole(rel_items.get("parent_appid")),
		"coming": bool(rel.get("is_coming_soon", false)), "free": bool(it.get("is_free", false)), "checked": true }


## Links to a game's other Steam pages (discussions, guides, artwork etc.) next to the store info:
## [{ id, name, icon, url }], in the UI language (l=). The Workshop only if the game has one. They open in
## Uzai's browser (store_game.steam_seiten_zeile).
static func steam_seiten(appid: int, workshop := false) -> Array:
	if appid <= 0:
		return []
	var out: Array = []
	for e in [["diskussionen", "Diskussionen", "chat", "discussions/"], ["guides", "Guides", "bulb", "guides/"],
			["artworks", "Artworks", "palette", "images/"], ["screenshots", "Screenshots", "image", "screenshots/"],
			["videos", "Videos", "video", "videos/"], ["workshop", "Workshop", "wand", "workshop/"],
			["hub", "Community-Hub", "friends", ""]]:
		if str(e[0]) == "workshop" and not workshop:
			continue
		out.append({ "id": str(e[0]), "name": str(e[1]), "icon": str(e[2]),
			"url": "https://steamcommunity.com/app/%d/%s?l=%s" % [appid, str(e[3]), str(Lang.api("steam"))] })
	return out


static func parse_details(d: Dictionary) -> Dictionary:
	var genres := PackedStringArray()
	for gen in d.get("genres", []):
		if gen is Dictionary:
			genres.append(str(gen.get("description", "")))
	var cats := PackedStringArray()
	var workshop := false
	for c in d.get("categories", []):
		if not (c is Dictionary):
			continue
		var n := str(c.get("description", ""))
		if _whole(c.get("id")) == 30 or n.to_lower().contains("workshop"):
			workshop = true
		if n in ["Einzelspieler", "Mehrspieler", "Koop", "Online-Koop", "PvP", "Online-PvP", "Volle Controllerunterstützung", "Teilweise Controllerunterstützung",
				"Steam-Errungenschaften", "Steam Cloud", "Geteilter Bildschirm/Splitscreen", "Remote Play Together", "Single-player", "Multi-player", "Co-op",
				"Full controller support", "Steam Achievements"]:
			cats.append(n)
	var shots: Array = []
	for s in (d.get("screenshots", []) as Array).slice(0, 12) if d.get("screenshots") is Array else []:
		if s is Dictionary and str(s.get("path_full", "")) != "":
			shots.append(str(s.get("path_full", "")))
	var po: Dictionary = d.get("price_overview", {}) if d.get("price_overview") is Dictionary else {}
	var langs_raw := str(d.get("supported_languages", ""))
	var langs := _strip_html(langs_raw)
	var rd: Dictionary = d.get("release_date", {}) if d.get("release_date") is Dictionary else {}
	var dlc_ids: Array = []
	for id in d.get("dlc", []) if d.get("dlc") is Array else []:
		dlc_ids.append(int(id))
	var req: Dictionary = d.get("pc_requirements", {}) if d.get("pc_requirements") is Dictionary else {}
	var full: Dictionary = d.get("fullgame", {}) if d.get("fullgame") is Dictionary else {}
	var age := int(str(d.get("required_age", "0"))) if str(d.get("required_age", "0")).is_valid_int() else 0
	var ratings: Dictionary = d.get("ratings", {}) if d.get("ratings") is Dictionary else {}
	var usk: Dictionary = ratings.get("usk", {}) if ratings.get("usk") is Dictionary else {}
	if age == 0 and str(usk.get("rating", "")).is_valid_int():
		age = int(str(usk.rating))
	return {
		"name": str(d.get("name", "")),
		"type": str(d.get("type", "game")),
		"about": _strip_html(str(d.get("short_description", ""))),
		"long": _strip_html(str(d.get("about_the_game", ""))).left(6000),
		"genres": genres, "features": cats, "screens": shots, "workshop": workshop,
		"header": str(d.get("header_image", "")),
		"background": str(d.get("background_raw", d.get("background", ""))),
		"release": str(rd.get("date", "")),
		"coming": bool(rd.get("coming_soon", false)),
		"developer": ", ".join(PackedStringArray(d.get("developers", []) if d.get("developers") is Array else [])),
		"publisher": ", ".join(PackedStringArray(d.get("publishers", []) if d.get("publishers") is Array else [])),
		"metacritic": int(d.get("metacritic", {}).get("score", 0)) if d.get("metacritic") is Dictionary else 0,
		"free": bool(d.get("is_free", false)),
		"age": age,
		"my_lang": (Lang.api("names") as Array).any(func(n: String) -> bool: return langs.to_lower().contains(n)),
		"my_lang_audio": voiced(langs_raw, Lang.api("names")),
		"price": int(po.get("final", 0)), "original": int(po.get("initial", 0)), "discount": int(po.get("discount_percent", 0)),
		"price_text": str(po.get("final_formatted", "")),
		"dlc": dlc_ids.size(),
		"dlc_ids": dlc_ids,
		"movies": parse_movies(d.get("movies", [])),
		"editions": parse_editions(d),
		"req_min": parse_requirements(str(req.get("minimum", ""))),
		"req_rec": parse_requirements(str(req.get("recommended", ""))),
		"controller": str(d.get("controller_support", "")),
		"achievements": int(d.get("achievements", {}).get("total", 0)) if d.get("achievements") is Dictionary else 0,
		"recommendations": int(d.get("recommendations", {}).get("total", 0)) if d.get("recommendations") is Dictionary else 0,
		"fullgame": { "appid": int(str(full.get("appid", "0"))) if str(full.get("appid", "0")).is_valid_int() else 0, "name": str(full.get("name", "")) },
		"deck": false,
	}


## Sprachausgabe in einer dieser Sprachen? Steam markiert vertonte Sprachen mit einem Sternchen.
static func voiced(langs_raw: String, names: Array) -> bool:
	var re := RegEx.create_from_string("(?i)(%s)\\s*<strong>\\s*\\*\\s*</strong>" % "|".join(PackedStringArray(names)))
	return re.search(langs_raw) != null


## Adresse mit der Sprache der Oberfläche ({l}) und dem Land für die Preise ({cc}).
static func _url(fmt: String) -> String:
	return fmt.replace("{l}", Lang.api("steam")).replace("{cc}", Config.land())


## Trailer aus appdetails. Steam liefert inzwischen meist HLS/DASH (hls_h264, dash_h264,
## dash_av1), ältere Einträge noch mp4/webm je Qualität. mpv spielt alles davon.
static func parse_movies(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for m in raw:
		if not (m is Dictionary):
			continue
		var url := ""
		if str(m.get("hls_h264", "")).begins_with("http"):
			url = str(m.hls_h264)
		for fmt in ["mp4", "webm"]:
			var v: Variant = m.get(fmt)
			if url == "" and v is Dictionary:
				for q in ["max", "480"]:
					if url == "" and str(v.get(q, "")).begins_with("http"):
						url = str(v[q])
		for key in ["dash_h264", "dash_av1"]:
			if url == "" and str(m.get(key, "")).begins_with("http"):
				url = str(m[key])
		if url == "":
			continue
		out.append({ "id": int(m.get("id", 0)), "name": str(m.get("name", "")),
			"thumb": str(m.get("thumbnail", "")).replace("http://", "https://"),
			"url": url.replace("http://", "https://"), "highlight": bool(m.get("highlight", false)) })
	return out


## Editionen zum Kaufen (package_groups „default“): [{ packageid, name, price, original, discount }]
static func parse_editions(d: Dictionary) -> Array:
	var out: Array = []
	var groups: Array = d.get("package_groups", []) if d.get("package_groups") is Array else []
	var pick: Dictionary = {}
	for g in groups:
		if g is Dictionary and (pick.is_empty() or str(g.get("name", "")) == "default"):
			pick = g
			if str(g.get("name", "")) == "default":
				break
	var subs: Array = pick.get("subs", []) if pick.get("subs") is Array else []
	for s in subs:
		if not (s is Dictionary) or int(s.get("packageid", 0)) <= 0:
			continue
		var raw := str(s.get("option_text", ""))
		var text := _strip_html(raw)
		var nm := text
		var cut := text.rfind(" - ")
		if cut > 0:
			nm = text.left(cut)
		var price := int(s.get("price_in_cents_with_discount", 0))
		var original := price
		var om := _P_ALT.search(raw)
		if om:
			original = maxi(price, cents_of(om.get_string(1)))
		var pct := 0
		var pm := _P_PROZENT.search(str(s.get("percent_savings_text", "")))
		if pm:
			pct = int(pm.get_string(1))
		elif original > price and original > 0:
			pct = int(round(100.0 - price * 100.0 / original))
		out.append({ "packageid": int(s.packageid), "name": nm.strip_edges(), "price": price, "original": original,
			"discount": pct, "free": bool(s.get("is_free_license", false)) })
	return out


## „24,99€“ → 2499
static func cents_of(s: String) -> int:
	var m := _P_CENT.search(s.replace(".", "").replace(" ", "") if s.contains(",") else s)
	if m:
		return int(m.get_string(1)) * 100 + int(m.get_string(2))
	var w := _P_GANZ.search(s)
	return int(w.get_string(1)) * 100 if w else 0


## Systemanforderungen (HTML aus appdetails) als Zeilen [Bezeichnung, Wert]; Hinweise ohne
## Bezeichnung haben "" vorn.
static func parse_requirements(html: String) -> Array:
	var out: Array = []
	if html.strip_edges() == "":
		return out
	var found := _A_PUNKT.search_all(html)
	if found.is_empty():
		for line in _strip_html(html).split("\n"):
			var t := line.strip_edges()
			var c := t.find(":")
			if t == "" or t.to_lower().begins_with("mindest") or t.to_lower().begins_with("empfohlen"):
				continue
			if c > 0 and c < 40:
				out.append([t.left(c).strip_edges(), t.substr(c + 1).strip_edges()])
			else:
				out.append(["", t])
		return out
	for m in found:
		var part := m.get_string(1)
		var km := _A_NAME.search(part)
		var flat := func(s: String) -> String: return _strip_html(s).replace("\n", " ").strip_edges()
		if km:
			var k: String = flat.call(km.get_string(1))
			var v: String = flat.call(km.get_string(2))
			k = k.trim_suffix(":").strip_edges()
			if v != "":
				out.append([k, v])
			elif k != "":
				out.append(["", k])
		else:
			var note: String = flat.call(part)
			if note != "":
				out.append(["", note])
	return out


static func parse_review_texts(data: Variant, limit := 3) -> Array:
	var out: Array = []
	if not (data is Dictionary) or not (data.get("reviews") is Array):
		return out
	for rv in data.reviews:
		if not (rv is Dictionary):
			continue
		var text := clean_text(str(rv.get("review", "")))
		if text.length() < 40:
			continue
		var author: Dictionary = rv.get("author", {}) if rv.get("author") is Dictionary else {}
		var mins := int(author.get("playtime_at_review", author.get("playtime_forever", 0)))
		out.append({ "up": bool(rv.get("voted_up", true)), "text": text, "hours": mins / 60.0,
			"date": int(rv.get("timestamp_created", 0)), "helpful": int(rv.get("votes_up", 0)) })
		if out.size() >= limit:
			break
	return out


static func parse_news(data: Variant, limit := 3) -> Array:
	var out: Array = []
	if not (data is Dictionary) or not (data.get("appnews") is Dictionary):
		return out
	var items: Variant = data.appnews.get("newsitems", [])
	if not (items is Array):
		return out
	for n in items:
		if not (n is Dictionary):
			continue
		var title := _strip_html(str(n.get("title", ""))).replace("\n", " ")
		var text := clean_text(str(n.get("contents", "")))
		if title == "":
			continue
		var tags: Array = n.tags if n.get("tags") is Array else []
		out.append({ "title": title, "date": int(n.get("date", 0)), "text": text, "author": str(n.get("author", "")),
			"patch": tags.has("patchnotes") })
		if out.size() >= limit:
			break
	return out


## Steams Einstufung nach Anteil und Menge der positiven Bewertungen, auf Deutsch.
static func review_label(pos: int, total: int) -> String:
	if total <= 0:
		return "Keine Bewertungen"
	var p := pos * 100.0 / total
	if p >= 95 and total >= 500:
		return "Äußerst positiv"
	if p >= 80:
		return "Sehr positiv" if total >= 50 else "Positiv"
	if p >= 70:
		return "Größtenteils positiv"
	if p >= 40:
		return "Ausgeglichen"
	if p >= 20:
		return "Größtenteils negativ"
	return "Sehr negativ" if total >= 50 else "Negativ"


## Preis als Text. currency: die Währung des Eintrags ("currency", wenn der Shop sie nennt); ohne
## Angabe ("") die des eingestellten Landes – die Anfragen an den Shop nennen dasselbe Land.
static func price_text(cents: int, currency := "") -> String:
	if cents <= 0:
		return "Kostenlos"
	return Lang.betrag(cents, currency if currency != "" else Config.waehrung())


## Große Zahlen mit Punkt: 41237 → „41.237“
static func num_text(n: int) -> String:
	return Lang.tausender(n)


## Sortieren und filtern für die Listen im Shop.
static func sorted(items: Array, how: String, hide_owned_ids: Dictionary = {}) -> Array:
	var out := items.filter(func(x): return not hide_owned_ids.has(int(x.appid)))
	match how:
		"rabatt": out.sort_custom(func(a, b): return int(a.discount) > int(b.discount))
		"preis": out.sort_custom(func(a, b): return _price_key(a) < _price_key(b))
		"name": out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


## Sortierschlüssel „Preis“: kostenlos zuerst, ohne bekannten Preis zum Schluss.
static func _price_key(it: Dictionary) -> int:
	if bool(it.get("free", false)):
		return -1
	return int(it.get("price", 0)) if int(it.get("price", 0)) > 0 else 1 << 40


# Die Muster für Texte aus dem Shop, einmal übersetzt: Eine Spielseite ruft _strip_html und clean_text dutzendfach auf
# (jede Bewertung, jede Neuigkeit, jede Zeile der Anforderungen), früher mit vier bis neun neuen Mustern je Aufruf.
static var _H_UMBRUCH := RegEx.create_from_string("(?i)<br\\s*/?>|</p>|</li>|</h[1-6]>")
static var _H_MARKE := RegEx.create_from_string("<[^>]+>")
static var _H_ZEILENENDE := RegEx.create_from_string("[ \\t]+\\n")
static var _H_LEERZEILEN := RegEx.create_from_string("\n{3,}")
static var _B_WEG := RegEx.create_from_string(
		"(?is)\\[img\\].*?\\[/img\\]|\\[previewyoutube[^\\]]*\\].*?\\[/previewyoutube\\]|\\{STEAM_CLAN_IMAGE\\}\\S*|\\[video[^\\]]*\\].*?\\[/video\\]")
static var _B_PUNKT := RegEx.create_from_string("(?i)\\[\\*\\]")
static var _B_BLOCK := RegEx.create_from_string("(?i)\\[/?(h[1-6]|p|list|olist|hr|quote|table|tr)[^\\]]*\\]")
static var _B_MARKE := RegEx.create_from_string("\\[/?[a-zA-Z0-9_]+(=[^\\]]*)?\\]")
static var _B_ABSATZ := RegEx.create_from_string("\n[ \t]*\n[ \t\n]*")
static var _A_PUNKT := RegEx.create_from_string("(?is)<li>(.*?)</li>")
static var _A_NAME := RegEx.create_from_string("(?is)^\\s*<strong>(.*?)</strong>(.*)$")
static var _P_ALT := RegEx.create_from_string("discount_original_price\">([^<]+)<")
static var _P_PROZENT := RegEx.create_from_string("(\\d+)\\s*%")
static var _P_CENT := RegEx.create_from_string("(\\d+)[.,](\\d{2})")
static var _P_GANZ := RegEx.create_from_string("(\\d+)")


static func _strip_html(s: String) -> String:
	var t := _H_MARKE.sub(_H_UMBRUCH.sub(s, "\n", true), "", true)
	# „&amp;“ zuletzt: Sonst würde „&amp;lt;“ erst zu „&lt;“ und dann noch einmal zu „<“.
	t = t.replace("&quot;", "\"").replace("&nbsp;", " ").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
	return _H_LEERZEILEN.sub(_H_ZEILENENDE.sub(t, "\n", true), "\n\n", true).strip_edges()


## Text aus Bewertungen und Ankündigungen lesbar machen: BB-Code, HTML, Bilder und Links raus.
static func clean_text(s: String) -> String:
	var t := _B_WEG.sub(s, "", true)
	t = _B_PUNKT.sub(t, "\n• ", true)
	t = _B_BLOCK.sub(t, "\n", true)
	t = _strip_html(_B_MARKE.sub(t, "", true))
	return _B_ABSATZ.sub(t, "\n\n", true).strip_edges()


# --- Demo ---------------------------------------------------------------------------------

## Demo: Listen ohne Preise, wie getappsingenre sie schickt (Kopien – die Listen behalten ihre).
static func _demo_unpriced(items: Array) -> Array:
	var out: Array = []
	for it in items:
		var c: Dictionary = (it as Dictionary).duplicate()
		c["price"] = 0
		c["original"] = 0
		c["discount"] = 0
		c["until"] = 0
		c.erase("checked")
		c["free"] = false
		out.append(c)
	return out


# --- Gratis und Angebote -------------------------------------------------------------------

static func _end_key(it: Dictionary) -> int:
	return int(it.get("until", 0)) if int(it.get("until", 0)) > 0 else 1 << 40


## Steam-Spiele, die gerade ganz kostenlos zu behalten sind (−100 %), aus den Shop-Listen.
static func steam_giveaways(from: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for key in ["specials", "top_sellers", "new_releases"]:
		for it in from.get(key, []):
			if not (it is Dictionary) or seen.has(int(it.get("appid", 0))):
				continue
			if int(it.get("discount", 0)) >= 100 and int(it.get("price", 0)) == 0 and int(it.get("original", 0)) > 0:
				var c: Dictionary = (it as Dictionary).duplicate()
				c["giveaway"] = true
				c["free"] = true
				c["store"] = "steam"
				c["upcoming"] = false
				out.append(c)
				seen[int(it.appid)] = true
	return out


## Ist ein Eintrag der gemerkten Liste abgelaufen oder hat ein angekündigter begonnen?
static func free_stale(items: Array, now: int) -> bool:
	for it in items:
		if bool(it.get("upcoming", false)) and int(it.get("from", 0)) > 0 and int(it.from) <= now:
			return true
		if not bool(it.get("upcoming", false)) and int(it.get("until", 0)) > 0 and int(it.until) <= now:
			return true
	return false


## Gemerkte Liste: nur, was noch gilt, und nur Felder in der erwarteten Form (die Datei könnte
## verändert sein: Adresse und Kurzname wie beim Lesen von Epic, Bilder nur über https).
static func free_from_cache(raw: Array, now: int) -> Array:
	var out: Array = []
	for it in raw:
		if not (it is Dictionary) or str(it.get("store", "")) != "epic" or not slug_ok(str(it.get("slug", ""))):
			continue
		if not _epic_page_ok(str(it.get("url", ""))) or not str(it.url).ends_with("/p/" + str(it.slug)):
			continue
		if int(it.get("until", 0)) > 0 and int(it.until) <= now:
			continue
		for k in ["capsule", "header"]:
			if not str(it.get(k, "")).begins_with("https://"):
				it[k] = ""
		out.append(it)
	return out


## Antwort von freeGamesPromotions → Einträge in Uzais Form. Gratis heißt bei Epic: ein Angebot
## mit discountPercentage 0 (zu zahlender Anteil) – jetzt (promotionalOffers) oder angekündigt
## (upcomingPromotionalOffers); ob es schon läuft, sagt sein Zeitraum (eine ältere Antwort kennt
## den Wochenwechsel noch nicht). Geheime Platzhalter („Mystery Game“) ohne Seite fallen weg.
static func parse_epic_free(data: Variant, now: int, locale := "de") -> Array:
	var out: Array = []
	var els: Variant = null
	if data is Dictionary:
		var d: Variant = data.get("data")
		var cat: Variant = d.get("Catalog") if d is Dictionary else null
		var ss: Variant = cat.get("searchStore") if cat is Dictionary else null
		els = ss.get("elements") if ss is Dictionary else null
	if not (els is Array):
		return out
	var seen := {}
	for el in els:
		if not (el is Dictionary):
			continue
		var promo: Variant = el.get("promotions")
		if not (promo is Dictionary):
			continue
		var w := _epic_window(promo.get("promotionalOffers"), now)
		if w.is_empty():
			w = _epic_window(promo.get("upcomingPromotionalOffers"), now)
		if w.is_empty():
			continue
		var soon := int(w.from) > now
		var slug := epic_slug(el)
		var title := str(el.get("title", "")).strip_edges()
		if slug == "" or title == "" or title.length() > 200:
			continue
		var key := str(el.get("namespace", "")) + ":" + str(el.get("id", slug))
		if seen.has(key):
			continue
		seen[key] = true
		var tp: Dictionary = el.get("price", {}).get("totalPrice", {}) if el.get("price") is Dictionary and el.price.get("totalPrice") is Dictionary else {}
		var dec := clampi(_whole(tp.currencyInfo.get("decimals"), 2), 0, 4) if tp.get("currencyInfo") is Dictionary else 2
		var orig := maxi(_whole(tp.get("originalPrice")), 0)
		if dec != 2:
			orig = int(round(orig * pow(10.0, 2 - dec)))
		var desc := str(el.get("description", "")).strip_edges()
		out.append({
			"store": "epic", "appid": 0, "id": "epic:" + key, "name": title,
			"desc": desc.left(400) if desc != title else "",
			"capsule": epic_image(el, ["OfferImageTall", "DieselStoreFrontTall", "Thumbnail"]),
			"header": epic_image(el, ["OfferImageWide", "DieselStoreFrontWide", "featuredMedia"]),
			"price": 0, "original": orig, "currency": str(tp.get("currencyCode", "")),
			"discount": 0 if soon else 100, "free": not soon, "giveaway": true,
			"upcoming": soon, "from": int(w.from), "until": int(w.until),
			"url": EPIC_PAGE % [epic_locale(locale), slug], "slug": slug, "ns": str(el.get("namespace", "")),
		})
	return out


## Zeitraum eines Gratis-Angebots { from, until }, das noch nicht vorbei ist – {} wenn keins
## (oder keins kostenlos ist).
static func _epic_window(groups: Variant, now: int) -> Dictionary:
	if not (groups is Array):
		return {}
	for g in groups:
		var offers: Variant = g.get("promotionalOffers") if g is Dictionary else null
		if not (offers is Array):
			continue
		for o in offers:
			if not (o is Dictionary) or not (o.get("discountSetting") is Dictionary):
				continue
			if _whole(o.discountSetting.get("discountPercentage"), -1) != 0:
				continue
			var from := iso_time(str(o.get("startDate", "")))
			var until := iso_time(str(o.get("endDate", "")))
			if from > 0 and until > from and until > now:
				return { "from": from, "until": until }
	return {}


## Seite des Spiels bei Epic: erst die Produktseite aus den Zuordnungen, sonst der Kurzname.
## urlSlug nicht: Das ist oft nur eine Kennung, die Seite dazu gibt es nicht. Nur Kleinbuchstaben,
## Ziffern und Bindestriche – so landet nichts Fremdes in der Adresse.
static func epic_slug(el: Dictionary) -> String:
	var cands: Array = []
	var ns: Variant = el.get("catalogNs")
	if ns is Dictionary and ns.get("mappings") is Array:
		for m in ns.mappings:
			if m is Dictionary and str(m.get("pageType", "")) == "productHome":
				cands.append(str(m.get("pageSlug", "")))
	for m in (el.get("offerMappings", []) if el.get("offerMappings") is Array else []):
		if m is Dictionary:
			cands.append(str(m.get("pageSlug", "")))
	cands.append(str(el.get("productSlug", "")).trim_suffix("/home"))
	for c in cands:
		if slug_ok(c):
			return c
	return ""


static func slug_ok(s: String) -> bool:
	if s == "" or s.length() > 120 or s.begins_with("-"):
		return false
	for ch in s:
		if not (ch >= "a" and ch <= "z") and not (ch >= "0" and ch <= "9") and ch != "-":
			return false
	return true


static func _epic_page_ok(url: String) -> bool:
	return url.begins_with("https://store.epicgames.com/")


## Bild in der gewünschten Art (Reihenfolge = Vorrang); nur https.
static func epic_image(el: Dictionary, kinds: Array) -> String:
	var imgs: Array = el.get("keyImages", []) if el.get("keyImages") is Array else []
	for k in kinds:
		for im in imgs:
			if im is Dictionary and str(im.get("type", "")) == str(k) and str(im.get("url", "")).begins_with("https://"):
				return str(im.url)
	return ""


## Sprache für Epics Shop-Adresse: de, en-US …
static func epic_locale(api_locale: String) -> String:
	return api_locale if api_locale in ["de", "en-US"] else "de"


## Ganze Zahl aus JSON: Zahlen kommen dort als Kommazahl an, große Steam-Werte oft als Text.
static func _whole(v: Variant, fallback := 0) -> int:
	if v is int or v is float:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return int(v)
	return fallback


## „2026-10-29T15:00:00.000Z“ → Unix-Zeit (UTC), 0 wenn nicht lesbar.
static func iso_time(s: String) -> int:
	s = s.strip_edges()
	if s.length() < 19 or s[4] != "-" or s[10] != "T":
		return 0
	var t := Time.get_unix_time_from_datetime_string(s.left(19))
	return t if t > 0 else 0


## Neue Angebote auf der Wunschliste: { new: [Einträge], seen: { appid: { k: "Rabatt:Ende", at } } }.
## Ein Angebot meldet Uzai einmal; endet es und kommt später ein neues, wieder. Beim ersten
## Blick überhaupt zählen alle laufenden Angebote als neu. at: seit wann Uzai es kennt.
static func sale_news(items: Array, seen: Dictionary, now: int) -> Dictionary:
	var out_seen := {}
	var fresh: Array = []
	for it in items:
		if not (it is Dictionary) or int(it.get("appid", 0)) <= 0 or int(it.get("discount", 0)) <= 0:
			continue
		var key := "%d:%d" % [int(it.discount), int(it.get("until", 0))]
		var id := str(int(it.appid))
		var old: Variant = seen.get(id)
		if old is Dictionary and str(old.get("k", "")) == key:
			out_seen[id] = { "k": key, "at": int(old.get("at", now)) }
		else:
			out_seen[id] = { "k": key, "at": now }
			fresh.append(it)
	return { "new": fresh, "seen": out_seen }


## Text der Mitteilung zu neuen Angeboten: { title, sub, appid } – ein Spiel einzeln, mehrere
## zusammen (appid 0).
static func sale_toast(fresh: Array) -> Dictionary:
	if fresh.is_empty():
		return {}
	if fresh.size() == 1:
		var it: Dictionary = fresh[0]
		return { "title": "%s im Angebot" % str(it.get("name", "")), "appid": int(it.appid),
			"sub": "−%d %%  ·  jetzt %s statt %s" % [int(it.discount), price_text(int(it.get("price", 0))), price_text(int(it.get("original", 0)))] }
	var best: Dictionary = fresh[0]
	for it in fresh:
		if int(it.get("discount", 0)) > int(best.get("discount", 0)):
			best = it
	return { "title": "Wunschliste: %d Spiele im Angebot" % fresh.size(), "appid": 0,
		"sub": "Am meisten gespart: %s (−%d %%)" % [str(best.get("name", "")), int(best.get("discount", 0))] }
