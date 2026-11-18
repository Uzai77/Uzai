extends Node
## Filme und Serien, untere Schicht: reine Funktionen ohne Netz und ohne Zustand – Adressen und
## Manifeste der Addons, Metadaten, Streams (Qualität, Größe, Sortierung), Ergebnisse der Plugins
## und „Als Nächstes“. Darum offline prüfbar (tests/logic_filme.gd). movies.gd erbt davon.

const Lang := preload("res://src/core/lang.gd")
const Q := preload("res://src/core/movies_quelle.gd")
const Fremd := preload("res://src/core/fremd.gd")

const TMDB_IMG := "https://image.tmdb.org/t/p/w185"   ## Personenbilder (profile_path)
const CAST_MAX := 24

## Englische Katalognamen der bekannten Addons auf Deutsch (der Rest bleibt, wie er ist).
const CATALOG_NAMES := {
	"popular": "Beliebt", "featured": "Empfohlen", "new": "Neu", "trending": "Im Trend", "top": "Top",
	"top rated": "Am besten bewertet", "latest": "Neueste", "recently added": "Neu hinzugefügt",
	"most watched": "Meistgesehen", "calendar": "Kalender", "last videos": "Neue Folgen",
}
const LANG_NAMES := {
	"de": "Deutsch", "ger": "Deutsch", "deu": "Deutsch", "german": "Deutsch",
	"en": "Englisch", "eng": "Englisch", "english": "Englisch",
	"fr": "Französisch", "fre": "Französisch", "fra": "Französisch", "es": "Spanisch", "spa": "Spanisch",
	"it": "Italienisch", "ita": "Italienisch", "nl": "Niederländisch", "dut": "Niederländisch", "nld": "Niederländisch",
	"pl": "Polnisch", "pol": "Polnisch", "pt": "Portugiesisch", "por": "Portugiesisch", "tr": "Türkisch", "tur": "Türkisch",
	"ru": "Russisch", "rus": "Russisch", "ja": "Japanisch", "jpn": "Japanisch", "ko": "Koreanisch", "kor": "Koreanisch",
	"sv": "Schwedisch", "swe": "Schwedisch", "da": "Dänisch", "dan": "Dänisch", "no": "Norwegisch", "nor": "Norwegisch",
	"fi": "Finnisch", "fin": "Finnisch", "cs": "Tschechisch", "cze": "Tschechisch", "ces": "Tschechisch",
	"hu": "Ungarisch", "hun": "Ungarisch", "el": "Griechisch", "gre": "Griechisch", "ell": "Griechisch",
	"ar": "Arabisch", "ara": "Arabisch", "he": "Hebräisch", "heb": "Hebräisch", "zh": "Chinesisch", "chi": "Chinesisch", "zho": "Chinesisch",
	"ro": "Rumänisch", "rum": "Rumänisch", "ron": "Rumänisch", "hr": "Kroatisch", "hrv": "Kroatisch", "sr": "Serbisch", "srp": "Serbisch",
	"uk": "Ukrainisch", "ukr": "Ukrainisch", "bg": "Bulgarisch", "bul": "Bulgarisch", "hi": "Hindi", "hin": "Hindi",
}


# --- Adressen und Manifeste (reine Funktionen) -------------------------------------------------

## Adresse eines Addons vereinheitlichen: stremio:// → https://, ohne Leerraum, mit /manifest.json.
static func normalize_manifest_url(url: String) -> String:
	var u := url.strip_edges()
	if u == "":
		return ""
	var se := u.find("://")
	if se > 0:
		var scheme := u.substr(0, se).to_lower()
		if scheme not in ["http", "https"]:
			u = "https://" + u.substr(se + 3)
	else:
		u = "https://" + u
	var q := ""
	var qi := u.find("?")
	if qi >= 0:
		q = u.substr(qi)
		u = u.substr(0, qi)
	u = u.rstrip("/")
	if not u.to_lower().ends_with("/manifest.json"):
		u += "/manifest.json"
	return u + q


## Basis eines Addons: { path, query } – query (z. B. ?token=…) hängt Stremio an jede Anfrage.
static func split_base(manifest_url: String) -> Dictionary:
	var u := manifest_url
	var q := ""
	var qi := u.find("?")
	if qi >= 0:
		q = u.substr(qi)
		u = u.substr(0, qi)
	u = u.rstrip("/")
	if u.to_lower().ends_with("/manifest.json"):
		u = u.substr(0, u.length() - "/manifest.json".length())
	return { "path": u, "query": q }


## Zusatzwerte im Stremio-Format: genre=Sci-Fi&skip=100 (Werte wie encodeURIComponent).
static func extra_string(extra: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in extra.keys():
		var v := str(extra[k])
		if v == "":
			continue
		parts.append("%s=%s" % [str(k).uri_encode(), v.uri_encode()])
	return "&".join(parts)


## /{resource}/{type}/{id}.json bzw. /{resource}/{type}/{id}/{extra}.json – wie Stremio und Nuvio.
static func resource_url(manifest_url: String, resource: String, type: String, id: String, extra := {}) -> String:
	var b := split_base(manifest_url)
	var ex := extra_string(extra)
	var p := "%s/%s/%s/%s" % [b.path, resource, type.uri_encode(), id.uri_encode()]
	if ex != "":
		p += "/" + ex
	return p + ".json" + str(b.query)


## Katalog-Adresse wie Nuvio: ohne Zusätze /catalog/t/id.json oder …/skip=N.json, sonst alle Zusätze.
static func catalog_url(manifest_url: String, type: String, catalog_id: String, skip := 0, extra := {}) -> String:
	var ex := extra.duplicate()
	if skip > 0 and not ex.has("skip"):
		ex["skip"] = str(skip)
	return resource_url(manifest_url, "catalog", type, catalog_id, ex)


## Einträge einer Katalog-Antwort: { metas: [...] } wie Stremio, auch { metasDetailed } oder eine
## bloße Liste (manche Addons). Sonst leer.
static func catalog_metas(data: Variant) -> Array:
	if data is Array:
		return data
	if data is Dictionary:
		for k in ["metas", "metasDetailed"]:
			if (data as Dictionary).get(k) is Array:
				return data[k]
	return []


const _NET_WHY := {
	HTTPRequest.RESULT_CANT_RESOLVE: "Name nicht auflösbar (DNS)", HTTPRequest.RESULT_CANT_CONNECT: "keine Verbindung",
	HTTPRequest.RESULT_CONNECTION_ERROR: "Verbindung abgebrochen", HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS-Fehler (Zertifikat)",
	HTTPRequest.RESULT_TIMEOUT: "Zeitüberschreitung", HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "Antwort zu groß",
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "zu viele Weiterleitungen", HTTPRequest.RESULT_NO_RESPONSE: "keine Antwort",
	HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: "Antwort nicht entpackbar",
}


## Warum ein Katalog nichts brachte – fürs Protokoll (logs/filme.log) und die Meldung. "" = ok,
## "leer" = gültig, aber ohne Einträge. r: Antwort von _fetch (ok, code, data, result, bytes, ctype).
static func catalog_reason(r: Dictionary, ms := 0, timeout_s := 0.0) -> String:
	var res := int(r.get("result", 0))
	var code := int(r.get("code", 0))
	if res > 0 and res != HTTPRequest.RESULT_SUCCESS:
		return str(_NET_WHY.get(res, "Netzfehler %d" % res))
	if res < 0 and code == 0:
		return "nicht gesendet (Adresse?)"
	if code == 0:
		return "Zeitüberschreitung" if timeout_s > 0.0 and ms >= int(timeout_s * 1000.0) - 50 else "keine Antwort"
	var kb := "%d KB" % ceili(int(r.get("bytes", 0)) / 1024.0) if int(r.get("bytes", 0)) > 0 else "leer"
	var ct := str(r.get("ctype", "")).get_slice(";", 0).strip_edges()
	if code < 200 or code >= 300:
		return "HTTP %d (%s%s)" % [code, (ct + ", ") if ct != "" else "", kb]
	var data: Variant = r.get("data")
	if data == null:
		return "kein JSON (%s%s)" % [(ct + ", ") if ct != "" else "", kb]
	if not (data is Array) and not (data is Dictionary and ((data as Dictionary).get("metas") is Array or (data as Dictionary).get("metasDetailed") is Array)):
		if data is Dictionary and (data as Dictionary).has("err"):
			return "Addon meldet Fehler: %s" % str(data.err).left(60)
		return "ohne „metas“ (%s)" % kb
	var list := catalog_metas(data)
	if list.is_empty():
		return "leer"
	if not list.any(func(m): return m is Dictionary and _s((m as Dictionary).get("id", "")) != ""):
		return "Einträge ohne ID"
	return ""


## Kurz für die Meldung, wenn kein Katalog etwas brachte: der häufigste Grund in Worten („Zugriff gesperrt“),
## sonst "". Den genauen Grund mit HTTP-Code hat logs/filme.log (catalog_reason).
static func catalog_summary(jobs: Array) -> String:
	var count := {}
	for j in jobs:
		if not (j is Dictionary) or not bool(j.get("done", false)) or bool(j.get("ok", false)):
			continue
		var w := str(j.get("why", "")).get_slice(" (", 0)
		if w != "":
			count[w] = int(count.get(w, 0)) + 1
	var best := ""
	for w in count:
		if best == "" or int(count[w]) > int(count[best]):
			best = w
	return _in_worten(best)


## HTTP-Codes für die Meldung in Worte: Sichtbare Texte nennen keine rohen Codes (tests/logic_konsistenz.gd).
static func _in_worten(w: String) -> String:
	if not w.begins_with("HTTP "):
		return w
	var code := int(w.substr(5))
	if code == 401 or code == 403:
		return "Zugriff gesperrt"
	if code == 404 or code == 410:
		return "Katalog nicht gefunden"
	if code == 429:
		return "zu viele Anfragen"
	if code >= 500:
		return "Server antwortet nicht"
	return "unerwartete Antwort"


static func _str_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if x is Dictionary:      # manche Addons liefern Einträge { name, … } statt Namen
				x = x.get("name")
			if x != null and str(x).strip_edges() != "":
				out.append(str(x).strip_edges())
	elif v is String and str(v) != "":
		out.append(str(v))
	return out


## Manifest lesen. Leer, wenn es kein Addon ist.
static func parse_manifest(m: Dictionary, url: String) -> Dictionary:
	var id := str(m.get("id", "")).strip_edges()
	var raw_res: Variant = m.get("resources", [])
	if id == "" or not (raw_res is Array) or (raw_res as Array).is_empty():
		return {}
	var types := _str_array(m.get("types", []))
	var res_names: Array = []
	var res_info: Array = []
	for r in raw_res:
		if r is String:
			res_names.append(str(r))
			res_info.append({ "name": str(r), "types": types.duplicate(), "id_prefixes": [] })
		elif r is Dictionary and str(r.get("name", "")) != "":
			res_names.append(str(r.name))
			res_info.append(
					{ "name": str(r.name), "types": _str_array(r.get("types", types)) if r.has("types") else types.duplicate(),
					"id_prefixes": _str_array(r.get("idPrefixes", [])) })
	var cats: Array = []
	var raw_cats: Variant = m.get("catalogs", [])
	if raw_cats is Array:
		for c in raw_cats:
			if not (c is Dictionary) or str(c.get("id", "")) == "" or str(c.get("type", "")) == "":
				continue
			var extra: Array = []
			var raw_extra: Variant = c.get("extra", [])
			var required := _str_array(c.get("extraRequired", []))
			var supported := _str_array(c.get("extraSupported", []))
			if raw_extra is Array:
				for x in raw_extra:
					if x is String:
						extra.append({ "name": str(x).to_lower(), "required": str(x) in required, "options": [] })
					elif x is Dictionary and str(x.get("name", "")) != "":
						extra.append({ "name": str(x.name).to_lower(), "required": Fremd.ja(x.get("isRequired")) or str(x.name) in required,
							"options": _str_array(x.get("options", [])), "default": str(x.get("default", "")) if x.get("default") != null else "" })
			for s in supported:
				if not extra.any(func(e): return str(e.name) == str(s).to_lower()):
					extra.append({ "name": str(s).to_lower(), "required": str(s) in required, "options": [] })
			cats.append({ "type": str(c.type), "id": str(c.id), "name": str(c.get("name", c.id)) if c.get("name") != null else str(c.id), "extra": extra })
	var hints: Dictionary = m.get("behaviorHints", {}) if m.get("behaviorHints") is Dictionary else {}
	return {
		"id": id, "name": str(m.get("name", id)), "version": str(m.get("version", "")),
		"description": str(m.get("description", "")) if m.get("description") != null else "",
		"logo": bild(m.get("logo", "")),
		"background": bild(m.get("background", "")),
		"url": url, "enabled": true, "types": types, "resources": res_names, "resource_info": res_info,
		"id_prefixes": _str_array(m.get("idPrefixes", [])), "catalogs": cats,
		"configurable": Fremd.ja(hints.get("configurable")), "config_required": Fremd.ja(hints.get("configurationRequired")),
		"loaded": true,
	}


## Kann das Addon diese Ressource für Typ und ID liefern? (Nuvio: supportsResource)
static func supports(a: Dictionary, resource: String, type: String, id: String) -> bool:
	for r in a.get("resource_info", []):
		if str(r.name) != resource:
			continue
		var types: Array = r.get("types", [])
		if not types.is_empty() and not (type in types):
			continue
		var pre: Array = r.get("id_prefixes", [])
		if pre.is_empty():
			pre = a.get("id_prefixes", [])
		if pre.is_empty():
			return true
		for p in pre:
			if id.begins_with(str(p)):
				return true
	return false


## Welche Addons nach Details gefragt werden, in Nuvios Reihenfolge: passender Typ und ID-Präfix,
## dann das oberste Addon mit Details für diese ID, sonst Addons ohne Präfix-Angabe.
static func meta_candidates(list: Array, type: String, id: String) -> Array:
	var out: Array = []
	var seen := {}
	for a in list:
		if bool(a.get("enabled", true)) and supports(a, "meta", type, id):
			out.append(a)
			seen[str(a.id)] = true
	if out.is_empty():
		for a in list:
			if not bool(a.get("enabled", true)) or seen.has(str(a.id)):
				continue
			if not (a.get("resources", []) as Array).has("meta"):
				continue
			var any_type := false
			for r in a.get("resource_info", []):
				if str(r.name) == "meta" and ((r.types as Array).is_empty() or type in r.types):
					any_type = true
			if any_type and (a.get("id_prefixes", []) as Array).is_empty():
				out.append(a)
	return out


## Katalog nur mit Zusätzen nutzbar, die Uzai nicht liefern kann (Pflicht-Genre o. Ä.)?
static func catalog_needs(cat: Dictionary, have: Array) -> bool:
	for e in cat.get("extra", []):
		if bool(e.get("required", false)) and not (str(e.name) in have):
			return true
	return false


static func catalog_has(cat: Dictionary, extra_name: String) -> bool:
	for e in cat.get("extra", []):
		if str(e.name) == extra_name:
			return true
	return false


static func type_label(type: String, plural := true) -> String:
	match type:
		"movie":
			return "Filme" if plural else "Film"
		"series":
			return "Serien" if plural else "Serie"
		"channel":
			return "Kanäle" if plural else "Kanal"
		"tv":
			return "TV"
		"anime":
			return "Anime"
	return type.capitalize()


static func catalog_title(cat: Dictionary) -> String:
	var n := str(cat.get("name", cat.get("id", "")))
	var de: String = CATALOG_NAMES.get(n.to_lower(), n)
	return "%s – %s" % [de, type_label(str(cat.get("type", "")))]


# --- Metadaten (reine Funktionen) -------------------------------------------------------------

static func _s(v: Variant) -> String:
	if v == null:
		return ""
	if v is float and float(v) == floorf(float(v)):
		return str(int(v))
	return str(v).strip_edges()


static func _year_of(m: Dictionary) -> String:
	var y := _s(m.get("year", ""))
	if y.length() >= 4 and y.substr(0, 4).is_valid_int():
		return y.substr(0, 4)
	var ri := _s(m.get("releaseInfo", ""))
	if ri.length() >= 4 and ri.substr(0, 4).is_valid_int():
		return ri.substr(0, 4)
	var rel := _s(m.get("released", ""))
	return rel.substr(0, 4) if rel.length() >= 4 and rel.substr(0, 4).is_valid_int() else ""


static func _links_of(m: Dictionary, category: String) -> Array:
	var out: Array = []
	var links: Variant = m.get("links", [])
	if links is Array:
		for l in links:
			if l is Dictionary and _s(l.get("category", "")).to_lower() == category.to_lower() and _s(l.get("name", "")) != "":
				out.append(_s(l.name))
	return out


## Bildadressen von metahub (Stremio) für IMDb-IDs, wenn das Addon keine liefert.
static func metahub(kind: String, id: String) -> String:
	if not id.begins_with("tt"):
		return ""
	return "https://images.metahub.space/%s/medium/%s/img" % [kind, id.get_slice(":", 0)]


## Fremde Texte der Kataloge und Details (Name, Beschreibung, Folgentitel) höchstens so lang: Ein Addon könnte sonst
## mit einem riesigen Text jede Karte und die Detailseite lahmlegen. Echte Texte liegen weit darunter.
const TITEL_MAX := 300
const BESCHREIBUNG_MAX := 6000


## Bildadresse eines Addons: nur http(s). Ein Pfad (C:\…, \\server\…, \??\UNC\…) würde sonst als Datei auf diesem PC
## geöffnet – bei einer Freigabe schickte Windows dabei die Anmeldung (NTLM) an den fremden Rechner.
static func bild(v: Variant) -> String:
	var s := _s(v) if v != null else ""
	return s if s.begins_with("https://") or s.begins_with("http://") else ""


## MetaPreview aus einem Katalog- oder Meta-Eintrag.
static func parse_meta_preview(m: Dictionary, addon_id: String, fallback_type := "") -> Dictionary:
	var id := _s(m.get("id", ""))
	var genres := _str_array(m.get("genres", []))
	if genres.is_empty():
		genres = _str_array(m.get("genre", []))
	if genres.is_empty():
		genres = _links_of(m, "Genres")
	var poster := bild(m.get("poster", ""))
	var bg := bild(m.get("background", ""))
	var logo := bild(m.get("logo", ""))
	return {
		"id": id, "type": _s(m.get("type", fallback_type)) if _s(m.get("type", "")) != "" else fallback_type,
		"name": _s(m.get("name", "")).left(TITEL_MAX), "poster": poster if poster != "" else metahub("poster", id),
		"background": bg if bg != "" else metahub("background", id), "logo": logo if logo != "" else metahub("logo", id),
		"description": _s(m.get("description", "")).left(BESCHREIBUNG_MAX), "year": _year_of(m), "release_info": _s(m.get("releaseInfo", "")).left(TITEL_MAX),
		"imdb_rating": _s(m.get("imdbRating", "")), "genres": genres, "addon_id": addon_id,
		"poster_shape": _s(m.get("posterShape", "")),
	}


static func _num(v: Variant, fallback := -1) -> int:
	if v is int or v is float:
		return int(v)
	if v is String and str(v).is_valid_int():
		return int(v)
	return fallback


static func today() -> String:
	return Time.get_date_string_from_system(true)


## Folgen nach Staffel und Folge, Specials (Staffel 0) ans Ende – wie Stremio und Nuvio.
static func sort_videos(videos: Array) -> void:
	videos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a.season)
		var sb := int(b.season)
		if (sa == 0) != (sb == 0):
			return sb == 0
		if sa != sb:
			return sa < sb
		if int(a.episode) != int(b.episode):
			return int(a.episode) < int(b.episode)
		return str(a.released) < str(b.released)
	)


static func parse_video(v: Dictionary, now_date := "") -> Dictionary:
	var d := now_date if now_date != "" else today()
	var season := _num(v.get("season", 0), 0)
	var ep := _num(v.get("episode", v.get("number", 0)), 0)
	var title := _s(v.get("name", v.get("title", "")))
	if title == "":
		title = _s(v.get("title", ""))
	if title == "" and ep > 0:
		title = "Folge %d" % ep
	var rel := _s(v.get("released", v.get("firstAired", "")))
	var avail: bool
	if v.has("available") and v.get("available") is bool:
		avail = bool(v.available)
	else:
		avail = rel == "" or rel.substr(0, 10) <= d
	return {
		"id": _s(v.get("id", "")), "title": title.left(TITEL_MAX), "season": season, "episode": ep, "released": rel,
		"thumbnail": bild(v.get("thumbnail", "")), "overview": _s(v.get("overview", v.get("description", ""))).left(BESCHREIBUNG_MAX), "available": avail,
	}


## Bildadresse einer Person. Volle Adressen bleiben (http von TMDB wird https), TMDB-Pfade wie
## „/abc.jpg“ (credits_cast.profile_path) bekommen die TMDB-Bildadresse davor. Sonst leer.
static func person_photo(v: Variant) -> String:
	var s := _s(v)
	if s == "" or s == "null":
		return ""
	if s.begins_with("//"):
		s = "https:" + s
	if s.begins_with("http://image.tmdb.org/"):
		s = "https://" + s.substr(7)
	if s.begins_with("https://") or s.begins_with("http://"):
		return s
	if s.begins_with("/") and s.get_extension().to_lower() in ["jpg", "jpeg", "png", "webp"]:
		return TMDB_IMG + s
	return ""


static func person_key(name_: String) -> String:
	return " ".join(name_.strip_edges().to_lower().split(" ", false))


## Ein Eintrag einer Personenliste: Name, Bild, Rolle (Figur oder Aufgabe). Leer ohne Namen.
static func _person_entry(v: Variant) -> Dictionary:
	if v is String:
		return { "name": _s(v), "photo": "", "character": "" } if _s(v) != "" else {}
	if not (v is Dictionary):
		return {}
	var name_ := _s(v.get("name", v.get("original_name", "")))
	if name_ == "":
		return {}
	var photo := ""
	for k in ["photo", "profile_path", "profile", "image", "avatar", "picture", "thumbnail"]:
		photo = person_photo(v.get(k))
		if photo != "":
			break
	var ch := _s(v.get("character", v.get("role", "")))
	if ch == "" and v.get("roles") is Array and not (v.roles as Array).is_empty() and v.roles[0] is Dictionary:
		ch = _s(v.roles[0].get("character", ""))     # TMDB aggregate_credits (Serien)
	return { "name": name_, "photo": photo, "character": ch }


## Personen mit Bildern aus allem, was Addons und TMDB liefern: { schlüssel: { name, photo, character } }.
## Quellen in dieser Reihenfolge (das erste Bild gewinnt): cast als Liste von Einträgen,
## app_extras.cast/directors/writers (Cinemeta), credits_cast/credits_crew (TMDB-Form, auch die
## TMDB-Antwort /credits mit cast/crew). Reine Namen tragen nichts bei.
static func parse_people(m: Dictionary) -> Dictionary:
	var out := {}
	var lists: Array = []
	var ax: Dictionary = m.get("app_extras", {}) if m.get("app_extras") is Dictionary else {}
	for src in [m.get("cast"), ax.get("cast"), ax.get("directors"), ax.get("writers"), m.get("credits_cast"), m.get("credits_crew")]:
		if src is Array:
			lists.append(src)
	for l in lists:
		for v in l:
			var e := _person_entry(v)
			if e.is_empty():
				continue
			var k := person_key(str(e.name))
			if not out.has(k):
				out[k] = e
				continue
			var have: Dictionary = out[k]
			if str(have.photo) == "" and str(e.photo) != "":
				have.photo = e.photo
			if str(have.character) == "" and str(e.character) != "":
				have.character = e.character
	return out


static func has_photos(people: Variant) -> bool:
	if people is Dictionary:
		for v in people.values():
			if v is Dictionary and str(v.get("photo", "")) != "":
				return true
	return false


## Namen der Besetzung: cast (Namen oder Einträge), sonst links „Cast“, sonst app_extras/credits.
## Die ersten Namen aus cast bleiben vorn; weitere aus den Listen mit Bildern kommen dahinter.
static func _cast_names(m: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	var add := func(n: String) -> void:
		if n != "" and not seen.has(person_key(n)) and out.size() < CAST_MAX:
			seen[person_key(n)] = true
			out.append(n)
	if m.get("cast") is Array:
		for v in m.cast:
			add.call(str(_person_entry(v).get("name", "")))
	elif m.get("cast") is String:
		for n in str(m.cast).split(",", false):
			add.call(n.strip_edges())
	if out.is_empty():
		for n in _links_of(m, "Cast"):
			add.call(str(n))
	var ax: Dictionary = m.get("app_extras", {}) if m.get("app_extras") is Dictionary else {}
	for src in [ax.get("cast"), m.get("credits_cast")]:
		if src is Array:
			for v in src:
				add.call(str(_person_entry(v).get("name", "")))
	return out


## Meta (Detailseite) aus der Antwort eines Addons.
static func parse_meta(m: Dictionary, addon_id: String, fallback_type := "", now_date := "") -> Dictionary:
	var out := parse_meta_preview(m, addon_id, fallback_type)
	var cast := _cast_names(m)
	var director := _str_array(m.get("director", []))
	if director.is_empty():
		director = _links_of(m, "Directors")
	var writer := _str_array(m.get("writer", []))
	if writer.is_empty():
		writer = _links_of(m, "Writers")
	var trailers: Array = []
	var seen := {}
	if m.get("trailerStreams") is Array:
		for t in m.trailerStreams:
			if t is Dictionary and _s(t.get("ytId", "")) != "" and not seen.has(_s(t.ytId)):
				seen[_s(t.ytId)] = true
				trailers.append({ "title": _s(t.get("title", "Trailer")), "yt_id": _s(t.ytId) })
	if m.get("trailers") is Array:
		for t in m.trailers:
			if t is Dictionary and _s(t.get("source", "")) != "" and not seen.has(_s(t.source)):
				seen[_s(t.source)] = true
				trailers.append({ "title": _s(t.get("type", "Trailer")), "yt_id": _s(t.source) })
	var links: Array = []
	if m.get("links") is Array:
		for l in m.links:
			if l is Dictionary:
				links.append({ "name": _s(l.get("name", "")), "category": _s(l.get("category", "")), "url": _s(l.get("url", "")) })
	var videos: Array = []
	if m.get("videos") is Array:
		for v in m.videos:
			if v is Dictionary and _s(v.get("id", "")) != "":
				videos.append(parse_video(v, now_date))
	sort_videos(videos)
	var seasons: Array = []
	for v in videos:
		if not (int(v.season) in seasons):
			seasons.append(int(v.season))
	seasons.sort()
	if 0 in seasons:
		seasons.erase(0)
		seasons.append(0)
	var hints: Dictionary = m.get("behaviorHints", {}) if m.get("behaviorHints") is Dictionary else {}
	out.merge({
		"runtime": _s(m.get("runtime", "")), "released": _s(m.get("released", "")),
		"cast": cast, "people": parse_people(m), "director": director, "writer": writer, "trailers": trailers, "links": links,
		"country": _s(m.get("country", "")), "awards": _s(m.get("awards", "")), "videos": videos, "seasons": seasons,
		"imdb_id": _s(m.get("imdb_id", out.id if str(out.id).begins_with("tt") else "")),
		"tmdb_id": _s(m.get("moviedb_id", m.get("tmdb_id", ""))),
		"default_video_id": _s(hints.get("defaultVideoId", "")),
	}, true)
	return out


## "tt123:2:5" → { meta_id, season, episode }; "kitsu:42:7" → Folge ohne Staffel.
static func split_video_id(video_id: String) -> Dictionary:
	var parts := video_id.split(":")
	if parts.size() >= 3 and parts[parts.size() - 1].is_valid_int() and parts[parts.size() - 2].is_valid_int() and parts[0].begins_with("tt"):
		return { "meta_id": ":".join(parts.slice(0, parts.size() - 2)), "season": int(parts[parts.size() - 2]), "episode": int(parts[parts.size() - 1]) }
	if parts.size() >= 3 and parts[parts.size() - 1].is_valid_int() and not parts[0].begins_with("tt"):
		return { "meta_id": ":".join(parts.slice(0, parts.size() - 1)), "season": 0, "episode": int(parts[parts.size() - 1]) }
	return { "meta_id": video_id, "season": 0, "episode": 0 }


# --- Streams (reine Funktionen) -----------------------------------------------------------------

static var _rx := {}


static func _re(key: String, pattern: String) -> RegEx:
	if not _rx.has(key):
		var r := RegEx.new()
		r.compile(pattern)
		_rx[key] = r
	return _rx[key]


static func _token(text: String, alts: String) -> bool:
	return _re("tok:" + alts, "(^|[^a-z0-9])(" + alts + ")([^a-z0-9]|$)").search(text) != null


## Auflösung aus Freitext wie Nuvio (2160p/4K/UHD, 1440p/2K, 1080p/FHD, 720p/HD, 576p, 480p/SD, 360p).
static func quality_of(text: String) -> int:
	var t := text.to_lower()
	if _token(t, "2160p?|4k|uhd"):
		return 2160
	if _token(t, "1440p?|2k"):
		return 1440
	if _token(t, "1080p?|1080i|fhd"):
		return 1080
	if _token(t, "720p?|hd"):
		return 720
	if _token(t, "576p?|480p?|360p?|sd"):
		return 480
	return 0


## HDR-Art aus Freitext: DV, HDR10+, HDR10, HLG, HDR oder "".
static func hdr_of(text: String) -> String:
	var t := text.to_lower()
	if _token(t, "dv|dovi|dolby[ ._-]?vision"):
		return "DV"
	if t.contains("hdr10+") or t.contains("hdr10plus"):
		return "HDR10+"
	if _token(t, "hdr10"):
		return "HDR10"
	if _token(t, "hlg"):
		return "HLG"
	if _token(t, "hdr"):
		return "HDR"
	return ""


static func codec_of(text: String) -> String:
	var t := text.to_lower()
	if _token(t, "av1"):
		return "AV1"
	if _token(t, "hevc|h265|h\\.265|x265"):
		return "HEVC"
	if _token(t, "avc|h264|h\\.264|x264"):
		return "AVC"
	if _token(t, "xvid|divx"):
		return "XviD"
	return ""


## Größe aus Freitext ("💾 1.81 GB", "850 MB") in Bytes, 0 wenn keine.
static func size_of(text: String) -> int:
	var m := _re("size", "(?i)(\\d+(?:[.,]\\d+)?)\\s*(TB|GB|MB|KB|TiB|GiB|MiB|KiB)\\b").search(text)
	if m == null:
		return 0
	var v := float(m.get_string(1).replace(",", "."))
	var unit := m.get_string(2).to_upper().replace("I", "")
	var mult := { "TB": 1099511627776.0, "GB": 1073741824.0, "MB": 1048576.0, "KB": 1024.0 }
	return int(v * float(mult.get(unit, 0.0)))


static func size_text(bytes: int) -> String:
	if bytes <= 0:
		return ""
	var gb := float(bytes) / 1073741824.0
	if gb >= 1.0:
		return Lang.dec("%.1f GB" % gb)
	return "%d MB" % maxi(1, int(round(float(bytes) / 1048576.0)))


## Gecacht bei einem Debrid-Dienst: „[RD+]“, „RD+“, „⚡“, „Instant“, „Cached“.
static func is_cached(text: String) -> bool:
	if _re("cache1", "(?i)\\[(RD|AD|PM|TB|DL|OC|ED|PKP|EN|DB|PP|TRB|SD|TR)\\+\\]").search(text) != null:
		return true
	if _re("cache2", "(?i)(^|[^a-z0-9])(RD|AD|PM|TB|DL|ED)\\+").search(text) != null:
		return true
	if text.contains("⚡"):
		return true
	return _re("cache3", "(?i)(^|[^a-z0-9])(instant|cached)([^a-z0-9]|$)").search(text) != null


static func _hash_id(parts: Array) -> String:
	return ("|".join(PackedStringArray(parts.map(func(p): return str(p))))).md5_text().substr(0, 16)


static func _headers_of(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v.keys():
			if k is String and (v[k] is String or v[k] is int or v[k] is float):
				out[str(k)] = _s(v[k])
	return out


static func _parse_subs(raw: Variant, source := "") -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for s in raw:
		if not (s is Dictionary):
			continue
		var url := _s(s.get("url", ""))
		# Nur http(s): Eine Datei oder Netzwerkfreigabe als Untertitel öffnete mpv sonst auf dem PC (Video.sichere_untertitel
		# prüft vor dem Befehl noch einmal).
		if url == "" or url.contains("[object") or not _http(url):
			continue
		var lang := _s(s.get("lang", s.get("language", "")))
		out.append({ "id": _s(s.get("id", url)), "url": url, "lang": lang, "label": lang_label(lang) + ("" if source == "" else "  ·  " + source) })
	return out


static func lang_label(lang: String) -> String:
	var l := lang.to_lower()
	return str(LANG_NAMES.get(l, lang if lang != "" else "Unbekannt"))


## Stream eines Addons lesen. Leer, wenn er nicht abspielbar ist (nur ytId/externalUrl).
static func parse_stream(s: Dictionary, a: Dictionary, order := 0) -> Dictionary:
	var url := _s(s.get("url", ""))
	var ihash := _s(s.get("infoHash", ""))
	if url == "" and ihash == "":
		return {}
	var hints: Dictionary = s.get("behaviorHints", {}) if s.get("behaviorHints") is Dictionary else {}
	var proxy: Dictionary = hints.get("proxyHeaders", {}) if hints.get("proxyHeaders") is Dictionary else {}
	# Fremde Texte: nur als Text, ohne Steuerzeichen, in der Länge begrenzt (movies_quelle.gd).
	var nm := _txt(s.get("name", ""), Q.NAME_MAX)
	var title := _txt(s.get("title", ""))
	var desc := _txt(s.get("description", ""))
	var filename := _txt(hints.get("filename", ""), Q.FILE_MAX, false)
	var text := " ".join(PackedStringArray([nm, title, desc, filename]))
	var size := _num(hints.get("videoSize", 0), 0)
	if size <= 0:
		size = size_of(desc)
	if size <= 0:
		size = size_of(title)
	if size <= 0:
		size = size_of(nm)
	var p2p := ihash != "" or url.begins_with("magnet:")
	return Q.enrich({
		"id": _hash_id([a.get("id", ""), url, ihash, s.get("fileIdx", ""), nm, title]),
		"name": nm if nm != "" else str(a.get("name", "")), "title": title, "description": desc,
		"addon_id": str(a.get("id", "")), "addon_name": str(a.get("name", "")),
		"url": "" if p2p else url, "headers": _headers_of(proxy.get("request", {})),
		"quality": quality_of(text), "hdr": hdr_of(text), "codec": codec_of(text),
		"size_bytes": size, "size_text": size_text(size), "is_p2p": p2p, "info_hash": ihash,
		"source": "addon", "subtitles": _parse_subs(s.get("subtitles", []), str(a.get("name", ""))),
		"filename": filename, "cached": is_cached(" ".join(PackedStringArray([nm, title, desc]))),
		"binge_group": _s(hints.get("bingeGroup", "")), "order": order,
	})


## Nuvio: Plugins kennen „movie“ und „tv“; „series“ nur, wenn der Scraper es selbst angibt.
static func plugin_media_type(type: String, supported: Array, season: int, episode: int) -> String:
	var t := "tv" if type.to_lower() in ["series", "tv", "show"] else type.to_lower()
	if t == "tv" and season > 0 and episode > 0:
		for s in supported:
			if str(s).to_lower() == "series":
				return "series"
	return t


static func scraper_supports(sc: Dictionary, type: String) -> bool:
	var norm := func(v: String) -> String: return "tv" if v.to_lower() in ["series", "show", "other", "tv"] else v.to_lower()
	var want: String = norm.call(type)
	var types: Array = sc.get("types", ["movie", "tv"])
	for t in types:
		if norm.call(str(t)) == want:
			return true
	return false


static func _http(url: String) -> bool:
	var u := url.to_lower()
	return u.begins_with("https://") or u.begins_with("http://")


static func _clean(v: Variant) -> String:
	var s := _s(v)
	return "" if s.contains("[object") else s


## Fremder Text (Name, Titel, Beschreibung): nur Text und Zahlen, gesäubert und begrenzt.
static func _txt(v: Variant, max_len := Q.TEXT_MAX, multiline := true) -> String:
	if v is String or v is StringName:
		var s := Q.clean(str(v), max_len, multiline)
		return "" if s.contains("[object") else s
	if v is int or v is float:
		return _s(v)
	return ""


## Sprachfeld eines Plugins: Text („Deutsch“, „de, en“) oder Liste von Kürzeln.
static func _lang_field(v: Variant) -> String:
	if v is Array:
		return ", ".join(PackedStringArray((v as Array).slice(0, Q.LANGS_MAX).map(func(x): return _txt(x, 24, false))))
	return _txt(v, 80, false)


## Ergebnis eines Plugin-Scrapers wie Nuvio (parseJsonResults + toPluginStream). Leer, wenn unbrauchbar.
static func parse_plugin_result(item: Dictionary, scraper: Dictionary, order := 0) -> Dictionary:
	var u: Variant = item.get("url")
	var url := ""
	if u is String:
		url = _clean(u)
	elif u is Dictionary:
		url = _clean(u.get("url", ""))
	if url == "":
		return {}
	var title := _txt(item.get("title", ""))
	var nm := _txt(item.get("name", ""), Q.NAME_MAX)
	var quality := _txt(item.get("quality", ""), 40, false)
	var sname := str(scraper.get("name", "Plugin"))
	var disp_name := nm if nm != "" else (title if title != "" else sname)
	if quality != "" and not disp_name.contains(quality):
		disp_name += " - " + quality
	var size_str := _txt(item.get("size", ""), 40, false)
	var lang := _lang_field(item.get("language", item.get("lang", "")))
	var hints: Dictionary = item.get("behaviorHints", {}) if item.get("behaviorHints") is Dictionary else {}
	var filename := _txt(item.get("filename", hints.get("filename", "")), Q.FILE_MAX, false)
	var desc_parts := PackedStringArray()
	if size_str != "":
		desc_parts.append(size_str)
	if lang != "":
		desc_parts.append(lang)
	var desc := " • ".join(desc_parts)
	var own_desc := _txt(item.get("description", ""))
	if own_desc != "":
		desc = own_desc if desc == "" else desc + "\n" + own_desc
	var text := " ".join(PackedStringArray([disp_name, title, quality, desc, filename]))
	var q := 0
	var ql := quality.to_lower()
	if ql.contains("4k") or ql.contains("2160"):
		q = 2160
	elif ql.contains("1440"):
		q = 1440
	elif ql.contains("1080"):
		q = 1080
	elif ql.contains("720"):
		q = 720
	elif ql.contains("480") or ql.contains("360") or ql.contains("576"):
		q = 480
	if q == 0:
		q = quality_of(text)
	var size := size_of(size_str)
	if size <= 0:
		size = size_of(text)
	var ihash := _clean(item.get("infoHash", ""))
	var p2p := ihash != "" or url.begins_with("magnet:")
	var subs: Array = []
	if item.get("subtitles") is Array:
		for s in item.subtitles:
			if s is Dictionary and _http(_clean(s.get("url", ""))):
				var l := _clean(s.get("language", s.get("lang", "")))
				subs.append({ "id": _clean(s.get("id", s.url)), "url": _clean(s.url), "lang": l, "label": lang_label(l) + "  ·  " + sname })
	return Q.enrich({
		"id": _hash_id(["plugin", scraper.get("id", ""), url, disp_name]),
		"name": disp_name, "title": title if title != "" else (nm if nm != "" else sname), "description": desc,
		"addon_id": "plugin:" + str(scraper.get("id", "")), "addon_name": sname,
		"url": "" if p2p else url, "headers": _headers_of(item.get("headers", {})),
		"quality": q, "hdr": hdr_of(text), "codec": codec_of(text), "size_bytes": size, "size_text": size_text(size),
		"is_p2p": p2p, "info_hash": ihash, "source": "plugin", "subtitles": subs, "filename": filename,
		"cached": is_cached(text), "binge_group": "plugin-" + str(scraper.get("id", "")), "order": order,
	}, lang)


## Sortierwert der Qualität: bevorzugte Stufe zuerst, darunter absteigend, darüber danach, unbekannt zuletzt.
static func quality_score(q: int, pref: int) -> int:
	if q <= 0:
		return 3000000
	if pref <= 0:
		return 10000 - q
	if q <= pref:
		return pref - q
	return 100000 + (q - pref)


## Reihenfolge: direkt vor P2P, gecacht, gewünschte Sprache (lang, z. B. "DE"; "" = egal),
## Qualität (bevorzugte zuerst), Größe, dann Addon-Reihenfolge.
static func sort_streams(list: Array, pref: int, lang := "") -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.is_p2p) != bool(b.is_p2p):
			return not bool(a.is_p2p)
		if bool(a.cached) != bool(b.cached):
			return bool(a.cached)
		if lang != "":
			var la := Q.lang_rank(a, lang)
			var lb := Q.lang_rank(b, lang)
			if la != lb:
				return la < lb
		var qa := quality_score(int(a.quality), pref)
		var qb := quality_score(int(b.quality), pref)
		if qa != qb:
			return qa < qb
		if int(a.size_bytes) != int(b.size_bytes):
			return int(a.size_bytes) > int(b.size_bytes)
		return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	return out


static func pref_quality() -> int:
	var q := str(Config.get_value("movies.quality", "auto"))
	return int(q) if q.is_valid_int() else 0


## Sprache, deren Quellen oben stehen („movies.lang_first“): auto = Sprache der Oberfläche,
## „aus“ = egal (""), sonst das Kürzel. Gibt z. B. "DE".
static func pref_lang() -> String:
	var v := str(Config.get_value("movies.lang_first", "auto"))
	if v == "aus" or v == "":
		return ""
	if v == "auto":
		v = str(Config.get_value("system.language", "de"))
	return Q.code_of(v)


## Gleiche Streams nur einmal (Nuvio: infoHash bzw. Adresse plus Name).
static func stream_key(s: Dictionary) -> String:
	if str(s.get("info_hash", "")) != "":
		return "h:" + str(s.info_hash).to_lower() + ":" + str(s.get("name", ""))
	return "u:" + str(s.get("url", "")) + "|" + str(s.get("name", ""))


# --- Als Nächstes (reine Funktionen) ----------------------------------------------------------

## Nächste Folge nach (Staffel, Folge) wie Nuvio: Specials überspringen; beim Staffelwechsel nur mit
## bekanntem, schon erreichtem Datum; in derselben Staffel ausgestrahlt oder ohne Datum, aber verfügbar.
static func next_video(videos: Array, season: int, episode: int, video_id := "", now_date := "") -> Dictionary:
	var d := now_date if now_date != "" else today()
	var eps: Array = []
	var sorted_ok := true
	var ps := -1
	var pe := -1
	for v in videos:
		var vs := int(v.season)
		var ve := int(v.episode)
		if vs == 0 or ve <= 0:
			continue
		if vs < ps or (vs == ps and ve < pe):
			sorted_ok = false
		ps = vs
		pe = ve
		eps.append(v)
	# Gespeicherte Folgen sind schon sortiert – nur sortieren, wenn nicht (spart viel Zeit).
	if not sorted_ok:
		sort_videos(eps)
	var idx := -1
	for i in eps.size():
		if int(eps[i].season) == season and int(eps[i].episode) == episode:
			idx = i
			break
	if idx < 0 and video_id != "":
		for i in eps.size():
			if str(eps[i].id) == video_id:
				idx = i
				break
	if idx < 0:
		return {}
	var cur_season := int(eps[idx].season)
	for i in range(idx + 1, eps.size()):
		var v: Dictionary = eps[i]
		var rel := str(v.get("released", "")).substr(0, 10)
		if int(v.season) != cur_season:
			if rel == "" or rel > d:
				return {}
			return v
		if rel != "" and rel <= d:
			return v
		if rel == "" and bool(v.get("available", true)):
			return v
		return {}
	return {}


## Weiterschauen aus den gespeicherten Daten wie Nuvio: angefangene Filme und Folgen (neueste je
## Serie), sonst „Als Nächstes“ nach der am weitesten geschauten Folge. Neueste zuerst.
static func build_continue(d: Dictionary, now_date := "") -> Array:
	var out: Array = []
	var prog: Dictionary = d.get("progress", {})
	var items: Dictionary = d.get("items", {})
	var hidden: Dictionary = d.get("hidden", {})
	var dismissed: Array = d.get("dismissed", [])
	for meta_id in prog.keys():
		var item: Dictionary = items.get(meta_id, {})
		if item.is_empty():
			continue
		var entries: Dictionary = prog[meta_id]
		var latest_prog := {}
		var latest_done := {}
		var furthest := {}
		for vid in entries.keys():
			var e: Dictionary = entries[vid]
			var ent := e.duplicate()
			ent["video_id"] = vid
			if bool(e.get("watched", false)):
				if latest_done.is_empty() or int(e.updated) > int(latest_done.updated):
					latest_done = ent
				if furthest.is_empty() or int(e.get("season", 0)) > int(furthest.get("season", 0)) \
						or (int(e.get("season", 0)) == int(furthest.get("season", 0)) and int(e.get("episode", 0)) > int(furthest.get("episode", 0))):
					furthest = ent
			elif float(e.get("position", 0)) >= 10.0:
				if latest_prog.is_empty() or int(e.updated) > int(latest_prog.updated):
					latest_prog = ent
		var hide_at := int(hidden.get(meta_id, 0))
		# Flach kopieren ohne Folgenliste (die tiefe Kopie aller Folgen kostete bei großen
		# Bibliotheken eine halbe Sekunde je Aufruf).
		var base := {}
		for k in item.keys():
			if k != "videos":
				base[k] = item[k]
		if not latest_prog.is_empty() and (latest_done.is_empty() or int(latest_prog.updated) >= int(latest_done.updated)):
			if int(latest_prog.updated) <= hide_at:
				continue
			base.merge({ "video_id": str(latest_prog.video_id), "season": int(latest_prog.get("season", 0)), "episode": int(latest_prog.get("episode", 0)),
				"episode_title": str(latest_prog.get("title", "")), "position": float(latest_prog.position), "duration": float(latest_prog.get("duration", 0)),
				"updated": int(latest_prog.updated), "next_up": false, "thumbnail": str(latest_prog.get("thumbnail", "")) }, true)
			out.append(base)
			continue
		if furthest.is_empty() or str(item.get("type", "")) != "series":
			continue
		if int(latest_done.updated) <= hide_at:
			continue
		var nv := next_video(item.get("videos", []), int(furthest.get("season", 0)), int(furthest.get("episode", 0)), str(furthest.video_id), now_date)
		if nv.is_empty() or entries.has(str(nv.id)) and bool((entries[str(nv.id)] as Dictionary).get("watched", false)):
			continue
		if "%s:%d:%d" % [meta_id, int(furthest.get("season", 0)), int(furthest.get("episode", 0))] in dismissed:
			continue
		base.merge({ "video_id": str(nv.id), "season": int(nv.season), "episode": int(nv.episode), "episode_title": str(nv.get("title", "")),
			"position": 0.0, "duration": 0.0, "updated": int(latest_done.updated), "next_up": true, "thumbnail": str(nv.get("thumbnail", "")),
			"released": str(nv.get("released", "")) }, true)
		out.append(base)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.updated) > int(b.updated))
	return out.slice(0, 40)
