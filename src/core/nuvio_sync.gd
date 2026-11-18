extends Node
## Nuvio-Konto für den Bereich „Filme“: anmelden (QR-Code wie in der Nuvio-TV-App oder E-Mail und
## Passwort) und dann alles aus dem Konto übernehmen – Profile, Addons, Plugins, Bibliothek,
## Weiterschauen, Gesehen, Startseiten-Layout (Reihenfolge, ausgeblendete Kataloge, eigene Titel,
## Sammlungen, Titelbild) – und Änderungen in Uzai zurückschreiben.
##
## Grundlage ist Nuvios öffentliche API (https://api.nuvio.tv, Supabase-kompatibel, öffentlicher
## „publishable key“ aus Nuvios Dokumentation). Die QR-Anmeldung nutzt dieselben Aufrufe wie Nuvio TV
## (start_device_login_session → nuvio.tv/link, poll_tv_login_session, tv-logins-exchange).
## Zugangsdaten (Tokens) liegen wie bei den anderen Konten in Uzais Einstellungen; das Passwort nie.
##
## Abgleich: beim Start, beim Öffnen von „Filme“ (höchstens alle 2 Minuten) und alle 10 Minuten.
## Addons, Plugins und Bibliothek kommen wie in den Nuvio-Apps genau so, wie sie im Konto stehen;
## Fortschritt und „Gesehen“ werden zusammengeführt (das Neuere gewinnt). Was in Uzai passiert
## (abspielen, gesehen, merken, Addons ändern), geht sofort zurück – klappt das nicht, später.

signal changed            ## angemeldet/abgemeldet, Profil, Layout oder Abgleich fertig
signal synced(ok: bool)

const Logdatei := preload("res://src/core/logdatei.gd")
const MoviesScript := preload("res://src/core/movies.gd")
const Fremd := preload("res://src/core/fremd.gd")
const API := "https://api.nuvio.tv"
const KEY := "sb_publishable_1Clq8rlTVACkdcZuqr6_AD__xUUC_EN"
const LINK_URL := "https://nuvio.tv/link"
const LEGACY_LINK_URL := "https://nuvio.tv/tv-login"
const HOME_PLATFORM := "home_catalog_shared"
const SETTINGS_PLATFORM := "tv"
const MAX_PENDING := 400
const SYNC_EVERY := 600.0
const MISS_TAGE := 7          ## kannte kein Addon den Titel: so lange nicht noch einmal fragen

var busy := false
var last_error := ""
## Zustand des Abgleichs in eigener Datei (nuvio.json): Layout, Sammlungen, Profile, Cursor der
## Änderungs-Abfragen, Warteschlange. Nicht in den Einstellungen, damit nicht jede Sendung beim
## Abspielen die ganze Einstellungsdatei neu schreibt und alle Einstellungs-Beobachter weckt.
var st := {}
var _st_timer: Timer
var _demo := false
var _timer: Timer
var _push_timer: Timer
var _progress_q := {}       ## progress_key -> Eintrag (gesammelt, alle paar Sekunden gesendet)
var _last_sync_try := 0.0


func sget(key: String, def: Variant = null) -> Variant:
	return st.get(key, def)


func sput(key: String, value: Variant) -> void:
	st[key] = value
	if _st_timer and not _demo:
		_st_timer.start()


func save_state() -> void:
	if _demo:
		return
	Config.write_json(Config.path("nuvio.json"), st)


func _ready() -> void:
	_st_timer = Timer.new()
	_st_timer.one_shot = true
	_st_timer.wait_time = 2.0
	_st_timer.timeout.connect(save_state)
	add_child(_st_timer)
	var loaded: Variant = Config.read_json(Config.path("nuvio.json"), {})
	st = loaded if loaded is Dictionary else {}
	_addon_urls_umziehen()
	_timer = Timer.new()
	_timer.wait_time = SYNC_EVERY
	_timer.timeout.connect(func() -> void: sync())
	add_child(_timer)
	_push_timer = Timer.new()
	_push_timer.one_shot = true
	_push_timer.wait_time = 6.0
	_push_timer.timeout.connect(_flush_progress)
	add_child(_push_timer)
	if "--demo" in OS.get_cmdline_user_args():
		_demo = true
		return
	Movies.local_change.connect(_on_local_change)
	if connected():
		_timer.start()
		get_tree().create_timer(4.0).timeout.connect(func() -> void: sync())


static func api() -> String:
	var env := Config.probe_env("UZAI_NUVIO_API")
	return env.trim_suffix("/") if env != "" else API


func connected() -> bool:
	return str(Config.get_value("nuvio.refresh", "")) != ""


func email() -> String:
	return str(Config.get_value("nuvio.email", ""))


func profile_id() -> int:
	return maxi(1, int(Config.get_value("nuvio.profile", 1)))


func profiles() -> Array:
	var p: Variant = sget("profiles", [])
	return p if p is Array else []


func profile_name() -> String:
	for p in profiles():
		if int(p.get("profile_index", 0)) == profile_id():
			return str(p.get("name", ""))
	return ""


## Installations-Kennung für Nuvios Sync-Ereignisse (damit eigene Änderungen nicht zurückkommen).
func client_id() -> String:
	var id := str(Config.get_value("nuvio.client_id", ""))
	if id == "":
		id = "uzai-" + Crypto.new().generate_random_bytes(9).hex_encode()
		Config.set_value("nuvio.client_id", id)
	return id


# --- Rein (für Tests) ---------------------------------------------------------------------------

## Nutzer-ID aus dem Zugangstoken (JWT, Feld „sub“).
static func jwt_sub(token: String) -> String:
	var parts := token.split(".")
	if parts.size() < 2:
		return ""
	var b := parts[1].replace("-", "+").replace("_", "/")
	while b.length() % 4 != 0:
		b += "="
	var raw := Marshalls.base64_to_raw(b)
	var d: Variant = Fremd.json(raw.get_string_from_utf8())
	return str(d.get("sub", "")) if d is Dictionary else ""


## Welches Profil gilt für Addons bzw. Plugins? Teilt ein Profil die Addons/Plugins von Profil 1,
## kommen sie von dort (wie in Nuvio).
static func scope_profile(list: Array, pid: int, kind: String) -> int:
	if pid == 1:
		return 1
	for p in list:
		if int(p.get("profile_index", 0)) == pid:
			var key := "uses_primary_addons" if kind == "addons" else "uses_primary_plugins"
			if bool(p.get(key, false)):
				return 1
	return pid


## Addons aus dem Konto: [{ url, enabled }] in Nuvios Reihenfolge, ohne doppelte.
static func addons_from_remote(rows: Array) -> Array:
	var list := rows.filter(func(r): return r is Dictionary and str(r.get("url", "")) != "")
	list.sort_custom(func(a, b): return int(a.get("sort_order", 0)) < int(b.get("sort_order", 0)))
	var out: Array = []
	var seen := {}
	for r in list:
		var u := MoviesScript.normalize_manifest_url(str(r.url))
		if u == "" or seen.has(u):
			continue
		seen[u] = true
		out.append({ "url": u, "remote": str(r.url), "enabled": bool(r.get("enabled", true)), "name": str(r.get("name", "") if r.get("name") != null else "") })
	return out


## Zurück ins Konto; Adressen so, wie Nuvio sie kennt (remote_urls: Uzais Adresse → Nuvios).
static func addons_to_remote(addons: Array, remote_urls := {}) -> Array:
	var out: Array = []
	for i in addons.size():
		var a: Dictionary = addons[i]
		out.append(
				{ "url": str(remote_urls.get(str(a.get("url", "")), a.get("url", ""))), "name": str(a.get("name", "")), "enabled": bool(a.get("enabled", true)),
				"sort_order": i })
	return out


## Plugins aus dem Konto: nur JavaScript-Repositorys (Nuvio „NUVIO_JS“); CloudStream läuft unter Windows nicht.
static func plugins_from_remote(rows: Array) -> Array:
	var list := rows.filter(func(r): return r is Dictionary and str(r.get("url", "")) != "")
	list.sort_custom(func(a, b): return int(a.get("sort_order", 0)) < int(b.get("sort_order", 0)))
	var out: Array = []
	for r in list:
		var t := str(r.get("repo_type", "") if r.get("repo_type") != null else "")
		if t != "" and t != "NUVIO_JS":
			continue
		out.append({ "url": MoviesScript.normalize_repo_url(str(r.url)), "enabled": bool(r.get("enabled", true)) })
	return out


static func plugins_to_remote(repos: Array) -> Array:
	var out: Array = []
	for i in repos.size():
		var r: Dictionary = repos[i]
		out.append(
				{ "url": str(r.get("url", "")), "name": str(r.get("name", "")), "enabled": bool(r.get("enabled", true)), "sort_order": i, "repo_type": "NUVIO_JS" })
	return out


## Eintrag der Bibliothek von Nuvio → Uzai (MetaPreview + added).
static func library_from_remote(r: Dictionary) -> Dictionary:
	var genres: Array = r.get("genres", []) if r.get("genres") is Array else []
	var rating: Variant = r.get("imdb_rating")
	return {
		"id": str(r.get("content_id", "")), "type": str(r.get("content_type", "movie")), "name": _str(r.get("name")),
		"poster": _str(r.get("poster")), "background": _str(r.get("background")), "logo": "",
		"description": _str(r.get("description")), "year": _str(r.get("release_info")).left(4),
		"release_info": _str(r.get("release_info")), "imdb_rating": "" if rating == null else String.num(float(rating), 1),
		"genres": genres.map(func(g): return str(g)), "addon_id": "", "addon_base_url": _str(r.get("addon_base_url")),
		"added": int(float(r.get("added_at", 0)) / 1000.0),
	}


static func library_to_remote(e: Dictionary) -> Dictionary:
	var out := {
		"content_id": str(e.get("id", "")), "content_type": str(e.get("type", "movie")), "name": str(e.get("name", "")),
		"poster": str(e.get("poster", "")), "poster_shape": "POSTER", "background": str(e.get("background", "")),
		"description": str(e.get("description", "")), "release_info": str(e.get("release_info", e.get("year", ""))),
		"genres": (e.get("genres", []) as Array).duplicate() if e.get("genres") is Array else [],
		"added_at": int(e.get("added", Time.get_unix_time_from_system())) * 1000,
	}
	var rating := str(e.get("imdb_rating", ""))
	if rating.is_valid_float():
		out["imdb_rating"] = float(rating)
	if str(e.get("addon_base_url", "")) != "":
		out["addon_base_url"] = str(e.addon_base_url)
	return out


static func _str(v: Variant) -> String:
	return "" if v == null else str(v)


## Erste nicht leere Angabe (wie firstNonBlank in Nuvio).
static func _either(a: String, b: String) -> String:
	return a.strip_edges() if a.strip_edges() != "" else b.strip_edges()


## Nuvios Schlüssel für Fortschritt: Film = content_id, Folge = content_id_s1e2.
static func progress_key(content_id: String, season: int, episode: int) -> String:
	if season > 0 or episode > 0:
		return "%s_s%de%d" % [content_id, season, episode]
	return content_id


## Folgen-ID wie bei Stremio (tt123:1:2). Nuvio schickt sie meist mit (video_id).
static func video_id_for(r: Dictionary) -> String:
	var v := _str(r.get("video_id"))
	if v != "":
		return v
	var s := int(r.get("season", 0) if r.get("season") != null else 0)
	var e := int(r.get("episode", 0) if r.get("episode") != null else 0)
	var cid := _str(r.get("content_id"))
	return cid if s <= 0 and e <= 0 else "%s:%d:%d" % [cid, s, e]


## Fortschritt und Gesehen von Nuvio → Uzais Form { meta_id: { video_id: Eintrag } }.
static func progress_from_remote(prog_rows: Array, watched_rows: Array) -> Dictionary:
	var out := {}
	for r in watched_rows:
		if not (r is Dictionary) or _str(r.get("content_id")) == "":
			continue
		var mid := _str(r.content_id)
		var s := int(r.get("season", 0) if r.get("season") != null else 0)
		var ep := int(r.get("episode", 0) if r.get("episode") != null else 0)
		var vid := mid if s <= 0 and ep <= 0 else "%s:%d:%d" % [mid, s, ep]
		if not out.has(mid):
			out[mid] = {}
		out[mid][vid] = { "position": 0.0, "duration": 0.0, "watched": true, "updated": int(float(r.get("watched_at", 0)) / 1000.0),
			"season": s, "episode": ep, "title": "", "thumbnail": "", "type": _str(r.get("content_type")), "nuvio": true }
	for r in prog_rows:
		if not (r is Dictionary) or _str(r.get("content_id")) == "":
			continue
		var mid := _str(r.content_id)
		var vid := video_id_for(r)
		var pos := float(r.get("position", 0)) / 1000.0
		var dur := float(r.get("duration", 0)) / 1000.0
		var upd := int(float(r.get("last_watched", 0)) / 1000.0)
		var done := dur > 0.0 and pos >= dur * 0.9
		if not out.has(mid):
			out[mid] = {}
		var old: Dictionary = out[mid].get(vid, {})
		if not old.is_empty() and int(old.updated) >= upd and not done:
			# Schon gesehen (Verlauf) und danach nicht weitergeschaut.
			continue
		out[mid][vid] = { "position": 0.0 if done else pos, "duration": dur, "watched": done or bool(old.get("watched", false)) and pos < 10.0,
			"updated": upd, "season": int(r.get("season", 0) if r.get("season") != null else 0),
			"episode": int(r.get("episode", 0) if r.get("episode") != null else 0), "title": "", "thumbnail": "",
			"type": _str(r.get("content_type")), "nuvio": true }
	return out


## Zusammenführen: je Folge gewinnt der neuere Stand. Was Nuvio früher geliefert hat (nuvio = true),
## dort aber nicht mehr steht und hier seitdem nicht weitergeschaut wurde, fällt weg – so wirkt
## „Aus Weiterschauen entfernen“ in der Nuvio-App auch hier. complete: Nuvio hat alles geliefert.
static func merge_progress(local: Dictionary, remote: Dictionary, last_sync: int, complete: bool) -> Dictionary:
	var out := local.duplicate(true)
	for mid in remote.keys():
		if not out.has(mid):
			out[mid] = {}
		for vid in remote[mid].keys():
			var r: Dictionary = remote[mid][vid]
			var l: Dictionary = out[mid].get(vid, {})
			if l.is_empty() or int(r.updated) > int(l.get("updated", 0)) \
					or (int(r.updated) == int(l.get("updated", 0)) and bool(r.watched) and not bool(l.get("watched", false))):
				var keep := r.duplicate()
				for k in ["title", "thumbnail"]:
					if str(l.get(k, "")) != "":
						keep[k] = l[k]
				out[mid][vid] = keep
			else:
				l["nuvio"] = true
	if complete:
		for mid in out.keys():
			for vid in (out[mid] as Dictionary).keys():
				var l: Dictionary = out[mid][vid]
				var gone: bool = not remote.has(mid) or not (remote[mid] as Dictionary).has(vid)
				if gone and bool(l.get("nuvio", false)) and int(l.get("updated", 0)) <= last_sync:
					(out[mid] as Dictionary).erase(vid)
			if (out[mid] as Dictionary).is_empty():
				out.erase(mid)
	return out


static func progress_to_remote(meta_id: String, type: String, video_id: String, e: Dictionary) -> Dictionary:
	var out := { "content_id": meta_id, "content_type": "series" if type == "series" else "movie", "video_id": video_id,
		"position": int(float(e.get("position", 0)) * 1000.0), "duration": int(float(e.get("duration", 0)) * 1000.0),
		"last_watched": int(e.get("updated", Time.get_unix_time_from_system())) * 1000 }
	if int(e.get("season", 0)) > 0 or int(e.get("episode", 0)) > 0:
		out["season"] = int(e.get("season", 0))
		out["episode"] = int(e.get("episode", 0))
	if bool(e.get("watched", false)) and float(e.get("duration", 0)) > 0:
		out["position"] = out.duration
	return out


## Startseiten-Layout aus Nuvio (home_catalog_shared): { items: [{ key, enabled, order, title, collection }], hide_unreleased }.
static func layout_from_remote(settings: Variant) -> Dictionary:
	if not (settings is Dictionary):
		return {}
	var items: Array = []
	for it in settings.get("items", []):
		if not (it is Dictionary):
			continue
		var coll := bool(it.get("is_collection", false))
		var key := ("collection_" + _str(it.get("collection_id"))) if coll else "%s/%s/%s" % [_str(it.get("addon_id")), _str(it.get("type")),
				_str(it.get("catalog_id"))]
		items.append({ "key": key, "enabled": bool(it.get("enabled", true)), "order": int(it.get("order", items.size())),
			"title": _str(it.get("custom_title")), "collection": _str(it.get("collection_id")) if coll else "" })
	items.sort_custom(func(a, b): return int(a.order) < int(b.order))
	return { "items": items, "hide_unreleased": bool(settings.get("hide_unreleased_content", false)) }


## Reihen nach Nuvios Layout ordnen: ausgeblendete fallen weg, eigene Titel gelten, Sammlungen
## (coll_rows: Schlüssel collection_<id> → Reihen) stehen an ihrem Platz. Unbekannte Reihen
## (neues Addon) kommen wie bei Nuvio hinten dran.
static func apply_layout(rows: Array, layout: Dictionary, coll_rows := {}) -> Array:
	var items: Array = layout.get("items", [])
	if items.is_empty():
		return rows
	var by_key := {}
	for r in rows:
		by_key[str(r.get("key", ""))] = r
	var out: Array = []
	var used := {}
	for it in items:
		var k := str(it.key)
		used[k] = true
		if not bool(it.enabled):
			continue
		if str(it.collection) != "":
			for cr in coll_rows.get(k, []):
				out.append(cr)
			continue
		if not by_key.has(k):
			continue
		var r: Dictionary = (by_key[k] as Dictionary).duplicate()
		if str(it.title) != "":
			r["title"] = str(it.title)
		out.append(r)
	for r in rows:
		if not used.has(str(r.get("key", ""))):
			out.append(r)
	return out


## Einstellungs-Paket von Nuvio TV ({ version, features: { layout_settings: { key: { type, value } } } })
## → flache Werte der Startseite.
static func layout_settings(blob: Variant) -> Dictionary:
	if not (blob is Dictionary):
		return {}
	var feats: Variant = blob.get("features", {})
	if not (feats is Dictionary):
		return {}
	var ls: Variant = feats.get("layout_settings", {})
	if not (ls is Dictionary):
		return {}
	var out := {}
	for k in ls.keys():
		var v: Variant = ls[k]
		out[str(k)] = v.get("value") if v is Dictionary and v.has("value") else v
	return out


## Schlüssel der Kataloge fürs Titelbild (hero_catalog_keys: Liste, JSON-Text oder Komma-Liste).
static func hero_keys(settings: Dictionary) -> Array:
	var v: Variant = settings.get("hero_catalog_keys", settings.get("hero_catalog_key", ""))
	var out: Array = []
	if v is Array:
		out = v.map(func(x): return str(x))
	elif str(v).begins_with("["):
		var p: Variant = Fremd.json_roh(str(v))
		if p is Array:
			out = p.map(func(x): return str(x))
	elif str(v) != "":
		out = Array(str(v).split(",", false)).map(func(x): return str(x).strip_edges())
	return out


## Nuvio-Schlüssel eines Katalogs (catalogRowLegacyKey: addonId_typ_katalogId).
static func legacy_key(addon_id: String, type: String, catalog_id: String) -> String:
	return "%s_%s_%s" % [addon_id, type.to_lower(), catalog_id]


static func setting_on(settings: Dictionary, key: String, def := true) -> bool:
	if not settings.has(key):
		return def
	var v: Variant = settings[key]
	if v is bool:
		return v
	return str(v).to_lower() in ["true", "1"]


## Sammlungen wie in Nuvio TV: je Sammlung eine Reihe mit Ordner-Kacheln (Bild, Emoji, Form);
## ein Ordner öffnet seine Kataloge. Schlüssel collection_<id> → [Reihe]. Quellen aus Addons
## (sources mit provider „addon“ oder das ältere catalogSources); TMDB- und Trakt-Quellen fallen
## weg (dafür hat Uzai keinen Zugang).
static func collection_folders(collections: Array) -> Dictionary:
	var out := {}
	for c in collections:
		if not (c is Dictionary):
			continue
		var key := "collection_" + _str(c.get("id"))
		var folders: Array = []
		for f in (c.get("folders", []) if c.get("folders") is Array else []):
			if not (f is Dictionary):
				continue
			var srcs: Array = []
			var raw: Variant = f.get("sources") if f.get("sources") is Array else f.get("catalogSources", [])
			for s in (raw if raw is Array else []):
				if not (s is Dictionary):
					continue
				var prov := _str(s.get("provider")).to_lower()
				if prov != "" and prov != "addon":
					continue
				# Ohne Typ lässt sich die Katalog-Adresse nicht bauen.
				if _str(s.get("addonId")) == "" or _str(s.get("catalogId")) == "" or _str(s.get("type")) == "":
					continue
				srcs.append({ "addon_id": _str(s.addonId), "type": _str(s.get("type")), "catalog_id": _str(s.catalogId), "genre": _str(s.get("genre")) })
			if srcs.is_empty():
				continue
			# Bilder wie in Nuvio TV (ModernHomeModels): Kachel = coverImageUrl, sonst das Bild der
			# Sammlung; Hintergrund = heroBackdropUrl, sonst Kachelbild, sonst Bild der Sammlung.
			var c_bd := _str(c.get("backdropImageUrl"))
			var cover := _either(_str(f.get("coverImageUrl")), c_bd)
			folders.append({ "id": _str(f.get("id")), "title": _str(f.get("title")), "cover": cover,
				"backdrop": _either(_str(f.get("heroBackdropUrl")), cover), "logo": _str(f.get("titleLogoUrl")),
				"emoji": _str(f.get("coverEmoji")), "shape": _str(f.get("tileShape")).to_upper() if _str(f.get("tileShape")) != "" else "SQUARE",
				"hide_title": bool(f.get("hideTitle", false)), "sources": srcs, "collection": _str(c.get("title")) })
		if folders.is_empty():
			out[key] = []
			continue
		out[key] = [{ "key": key, "title": _str(c.get("title")), "kind": "folders", "folders": folders,
			"pin": bool(c.get("pinToTop", false)), "show_all": bool(c.get("showAllTab", true)), "items": [] }]
	return out


# --- Netz ---------------------------------------------------------------------------------------

func _headers(auth: bool) -> PackedStringArray:
	var h := PackedStringArray(["apikey: " + KEY, "Accept: application/json"])
	var tok := str(Config.get_value("nuvio.access", ""))
	if auth and tok != "":
		h.append("Authorization: Bearer " + tok)
	return h


## Aufruf an die API. path: „/rest/v1/rpc/name“ usw. Läuft das Token ab, wird es einmal erneuert.
func call_api(method: int, path: String, body: Variant = null, auth := true) -> Dictionary:
	if auth and connected() and int(Config.get_value("nuvio.expires", 0)) - 60 < int(Time.get_unix_time_from_system()):
		await refresh()
	var payload: Variant = body if body != null else ({} if method == HTTPClient.METHOD_POST else null)
	var r: Dictionary = await Net.send_json(api() + path, method, payload, _headers(auth), "nuvio")
	if auth and int(r.code) == 401 and connected():
		if await refresh():
			r = await Net.send_json(api() + path, method, payload, _headers(auth), "nuvio")
	if int(r.code) == 429:
		await get_tree().create_timer(1.5).timeout
		r = await Net.send_json(api() + path, method, payload, _headers(auth), "nuvio")
	if not bool(r.ok) and int(r.code) >= 200 and int(r.code) < 300:
		r["ok"] = true   # 204 ohne Inhalt
	return r


func call_rpc(name: String, params := {}, auth := true) -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + name, params, auth)


static func reason(r: Dictionary, what: String) -> String:
	var code := int(r.get("code", 0))
	var d: Variant = r.get("data")
	var msg := ""
	if d is Dictionary:
		msg = _str(d.get("msg", d.get("message", d.get("error_description", d.get("error", "")))))
	if code == 0:
		return "%s: keine Verbindung zu Nuvio." % what
	if code == 400 and msg.to_lower().contains("invalid login"):
		return "E-Mail oder Passwort stimmt nicht."
	if code == 429:
		return "%s: Nuvio bremst gerade (zu viele Anfragen). Gleich nochmal versuchen." % what
	if msg != "":
		return "%s – Nuvio meldet: „%s“." % [what, msg.left(120)]
	return "%s: Nuvio antwortet gerade nicht. Gleich nochmal versuchen." % what


func _store_session(d: Dictionary) -> void:
	Config.set_value("nuvio.access", _str(d.get("access_token")))
	if _str(d.get("refresh_token")) != "":
		Config.set_value("nuvio.refresh", _str(d.refresh_token))
	Config.set_value("nuvio.expires", int(Time.get_unix_time_from_system()) + int(d.get("expires_in", 3600) if d.get("expires_in") != null else 3600))
	var user: Variant = d.get("user")
	var uid := jwt_sub(_str(d.get("access_token")))
	if user is Dictionary:
		if _str(user.get("email")) != "":
			Config.set_value("nuvio.email", _str(user.email))
		if uid == "":
			uid = _str(user.get("id"))
	if uid != "":
		Config.set_value("nuvio.user_id", uid)
	Config.save_settings()


func refresh() -> bool:
	var tok := str(Config.get_value("nuvio.refresh", ""))
	if tok == "":
		return false
	var r: Dictionary = await Net.send_json(api() + "/auth/v1/token?grant_type=refresh_token", HTTPClient.METHOD_POST, { "refresh_token": tok }, _headers(false))
	if r.ok and r.data is Dictionary and _str(r.data.get("access_token")) != "":
		_store_session(r.data)
		return true
	if int(r.code) in [400, 401, 403]:
		# Sitzung ungültig (anderswo abgemeldet): sauber abmelden, Daten bleiben.
		last_error = "Die Nuvio-Anmeldung ist abgelaufen. Bitte neu anmelden."
		_clear_session()
		changed.emit()
	return false


func _clear_session() -> void:
	for k in ["nuvio.access", "nuvio.refresh", "nuvio.expires", "nuvio.owner"]:
		Config.set_value(k, "" if k != "nuvio.expires" else 0)
	_timer.stop()
	Config.save_settings()


# --- Anmelden -----------------------------------------------------------------------------------

## QR-Anmeldung starten: { ok, url, user_code, code, nonce, expires (s), interval, error }.
func login_start() -> Dictionary:
	var nonce := Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(24)).replace("+", "-").replace("/", "_").replace("=", "")
	var r := await call_rpc("start_device_login_session", { "p_device_nonce": nonce, "p_redirect_base_url": LINK_URL,
		"p_device_type": "tv", "p_device_name": "Uzai" }, false)
	var row := _first(r)
	if r.ok and _str(row.get("device_code")) != "":
		return { "ok": true, "url": _str(row.get("verification_uri_complete")), "user_code": _str(row.get("user_code")),
			"code": _str(row.device_code), "nonce": nonce, "expires": _secs_until(_str(row.get("expires_at")), 600),
			"interval": maxi(2, int(row.get("poll_interval_seconds", 3))) }
	# Ältere Nuvio-Server kennen nur die TV-Anmeldung.
	var r2 := await call_rpc("start_tv_login_session", { "p_device_nonce": nonce, "p_redirect_base_url": LEGACY_LINK_URL, "p_device_name": "Uzai" }, false)
	var row2 := _first(r2)
	if r2.ok and _str(row2.get("code")) != "":
		return { "ok": true, "url": _str(row2.get("web_url")), "user_code": _str(row2.code), "code": _str(row2.code), "nonce": nonce,
			"expires": _secs_until(_str(row2.get("expires_at")), 600), "interval": maxi(2, int(row2.get("poll_interval_seconds", 3))) }
	return { "ok": false, "error": reason(r if not r.ok else r2, "Nuvio hat keinen Anmelde-Code geliefert") }


static func _first(r: Dictionary) -> Dictionary:
	var d: Variant = r.get("data")
	if d is Array and not (d as Array).is_empty() and d[0] is Dictionary:
		return d[0]
	return d if d is Dictionary else {}


static func _secs_until(iso: String, def: int) -> int:
	if iso == "":
		return def
	var t := Time.get_unix_time_from_datetime_string(iso.left(19))
	var left := int(t) - int(Time.get_unix_time_from_system())
	return left if left > 0 and left < 86400 else def


## Nachfragen: "pending", "ok" (angemeldet), "expired", "denied", "error".
func login_poll(code: String, nonce: String) -> String:
	var r := await call_rpc("poll_tv_login_session", { "p_code": code, "p_device_nonce": nonce }, false)
	if not r.ok:
		last_error = reason(r, "Nuvio antwortet nicht")
		return "error"
	var st := _str(_first(r).get("status")).to_lower()
	match st:
		"approved":
			var x: Dictionary = await Net.send_json(api() + "/functions/v1/tv-logins-exchange", HTTPClient.METHOD_POST, { "code": code, "device_nonce": nonce },
					_headers(false))
			if x.ok and x.data is Dictionary and _str(x.data.get("access_token")) != "":
				_store_session(x.data)
				await _after_login()
				return "ok"
			last_error = reason(x, "Anmeldung bestätigt, aber Nuvio gab keinen Zugang")
			return "error"
		"expired":
			return "expired"
		"used", "cancelled":
			return "denied"
	return "pending"


## Mit E-Mail und Passwort. "" oder Fehlertext.
func login_password(mail: String, password: String) -> String:
	var r: Dictionary = await Net.send_json(api() + "/auth/v1/token?grant_type=password", HTTPClient.METHOD_POST,
			{ "email": mail.strip_edges(), "password": password }, _headers(false))
	if not (r.ok and r.data is Dictionary and _str(r.data.get("access_token")) != ""):
		last_error = reason(r, "Anmeldung bei Nuvio ging nicht")
		return last_error
	if _str(r.data.get("user", {}).get("email") if r.data.get("user") is Dictionary else "") == "":
		Config.set_value("nuvio.email", mail.strip_edges())
	_store_session(r.data)
	await _after_login()
	return ""


func _after_login() -> void:
	sput("first_sync", true)
	sput("last_sync", 0)
	sput("cursors", {})
	sput("owner", "")
	Config.save_settings()
	_timer.start()
	changed.emit()
	await load_profiles()
	sync(true)


func logout() -> void:
	if connected():
		await call_api(HTTPClient.METHOD_POST, "/auth/v1/logout?scope=local")
	_clear_session()
	Config.set_value("nuvio.email", "")
	Config.set_value("nuvio.profile", 1)
	st = {}
	save_state()
	Config.save_settings()
	Movies.invalidate_home()
	changed.emit()


func load_profiles() -> Array:
	var r := await call_rpc("sync_pull_profiles")
	if r.ok and r.data is Array:
		var list: Array = (r.data as Array).filter(func(p): return p is Dictionary)
		list.sort_custom(func(a, b): return int(a.get("profile_index", 0)) < int(b.get("profile_index", 0)))
		sput("profiles", list)
		if not list.any(func(p): return int(p.get("profile_index", 0)) == profile_id()) and not list.is_empty():
			Config.set_value("nuvio.profile", int(list[0].get("profile_index", 1)))
		return list
	return profiles()


func set_profile(pid: int) -> void:
	if pid == profile_id():
		return
	Config.set_value("nuvio.profile", pid)
	sput("last_sync", 0)
	Movies.invalidate_home()
	Config.save_settings()
	changed.emit()
	sync(true)


## Wem gehören die Daten? Bei verknüpften Geräten ein anderes Konto (get_sync_owner).
func _owner() -> String:
	var r := await call_rpc("get_sync_owner")
	if r.ok:
		var d: Variant = r.data
		var id := ""
		if d is String:
			id = d
		elif d is Dictionary:
			id = _str(d.get("user_id", d.get("id", "")))
		elif d is Array and not (d as Array).is_empty():
			id = _str(d[0].get("user_id", d[0].get("id", ""))) if d[0] is Dictionary else str(d[0])
		if id != "":
			return id
	return str(Config.get_value("nuvio.user_id", ""))


# --- Abgleich -----------------------------------------------------------------------------------

## Abgleichen. "" oder Fehlertext. Ohne force höchstens alle 2 Minuten, und nie während ein
## Spiel oder Film läuft (dann zählt jede Millisekunde) – das holt der nächste Takt nach.
var _sync_durch := false     ## der letzte Abgleich lief bis zum Ende (siehe sync)


func sync(force := false) -> String:
	if not connected() or busy:
		return ""
	var now := Time.get_unix_time_from_system()
	if not force and (now - _last_sync_try < 120.0 or Launcher.in_game or Video.active):
		return ""
	_last_sync_try = now
	busy = true
	changed.emit()
	var t0 := Time.get_ticks_msec()
	_sync_durch = false
	var err := await _sync_inner()
	busy = false
	# Brach der Abgleich mit einem Fehler ab, käme hier ein leerer Text an – wie bei einem gelungenen. Dann gälte
	# er als erledigt (auch der erste), obwohl nichts übernommen wurde.
	if err == "" and not _sync_durch:
		err = "Der Abgleich mit Nuvio brach mit einem Fehler ab. Später noch einmal versuchen."
	last_error = err
	_log("Abgleich %s in %d ms" % ["ok" if err == "" else "Fehler: " + err, Time.get_ticks_msec() - t0])
	if err == "":
		sput("last_sync", int(Time.get_unix_time_from_system()))
		sput("first_sync", false)
	synced.emit(err == "")
	changed.emit()
	return err


signal _job_done


func _run_one(c: Callable, box: Dictionary, i: int) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _run_one_arbeit(c, box, i)
	box.left = int(box.left) - 1
	_job_done.emit()


func _run_one_arbeit(c: Callable, box: Dictionary, i: int) -> void:
	var r: Variant = await c.call()
	(box.res as Array)[i] = r


## Mehrere Aufrufe gleichzeitig (das Netz begrenzt Nuvio auf wenige parallele Verbindungen).
func _all(calls: Array) -> Array:
	var box := { "res": [], "left": calls.size() }
	(box.res as Array).resize(calls.size())
	for i in calls.size():
		_run_one(calls[i], box, i)
	while int(box.left) > 0:
		await _job_done
	return box.res


## Alle Seiten einer Änderungs-Abfrage ab dem Cursor: { ok, events, cursor }.
func _pull_delta(name: String, pid: int, since: int) -> Dictionary:
	var events: Array = []
	var cur := since
	for page in 20:
		var r := await call_rpc(name, { "p_profile_id": pid, "p_since_event_id": cur, "p_limit": 1000 })
		if not r.ok or not (r.data is Array):
			return { "ok": false, "events": events, "cursor": cur, "r": r }
		for ev in Fremd.zeilen(r.data):
			if ev is Dictionary:
				events.append(ev)
				cur = maxi(cur, int(ev.get("event_id", cur)))
		if (r.data as Array).size() < 1000:
			break
	return { "ok": true, "events": events, "cursor": cur }


func _cursor_of(r: Dictionary) -> int:
	var d: Variant = r.get("data")
	if d is int or d is float:
		return int(d)
	if d is String and str(d).is_valid_int():
		return int(d)
	return -1


func _sync_inner() -> String:
	if profiles().is_empty():
		await load_profiles()
	if not connected():
		return last_error
	await flush_pending()
	var pid := profile_id()
	var owner := str(sget("owner", ""))
	if owner == "":
		owner = await _owner()
		if owner == "":
			return "Nuvio-Konto unbekannt (bitte neu anmelden)."
		sput("owner", owner)
	var first := bool(sget("first_sync", false))
	# Beim ersten Mal: was Uzai schon hatte (Bibliothek, Fortschritt), ins Konto schreiben. Erst wenn alles dort
	# angekommen ist, wird übernommen, was im Konto steht: Die Bibliothek gilt danach „genau wie im Konto“ – was nicht
	# ankam (Netz weg, Dienst bremst), wäre sonst aus Uzai verschwunden.
	if first and not await _push_local_everything(pid):
		return "Uzais Bibliothek ließ sich nicht ganz ins Nuvio-Konto schreiben. Nichts wurde übernommen; der Abgleich versucht es später wieder."
	# 1) Einstellungen, Addons, Plugins, Layout – klein, gleichzeitig.
	var ap := scope_profile(profiles(), pid, "addons")
	var pp := scope_profile(profiles(), pid, "plugins")
	var oq := owner.uri_encode()
	var cfg := await _all([
		func() -> Dictionary: return await call_api(HTTPClient.METHOD_GET,
			"/rest/v1/addons?select=url,name,enabled,sort_order&user_id=eq.%s&profile_id=eq.%d&order=sort_order" % [oq, ap]),
		func() -> Dictionary: return await call_api(HTTPClient.METHOD_GET,
			"/rest/v1/plugins?select=url,name,enabled,sort_order,repo_type&user_id=eq.%s&profile_id=eq.%d&order=sort_order" % [oq, pp]),
		func() -> Dictionary: return await call_rpc("sync_pull_home_catalog_settings", { "p_profile_id": pid, "p_platform": HOME_PLATFORM }),
		func() -> Dictionary: return await call_rpc("sync_pull_collections", { "p_profile_id": pid }),
		func() -> Dictionary: return await call_rpc("sync_pull_profile_settings_blob", { "p_profile_id": pid, "p_platform": SETTINGS_PLATFORM }),
	])
	var ar: Dictionary = cfg[0]
	if not ar.ok:
		return reason(ar, "Addons aus Nuvio ließen sich nicht laden")
	var home_changed := false
	var addons := addons_from_remote(ar.data if ar.data is Array else [])
	if not addons.is_empty():
		var urls := {}
		for a in addons:
			urls[str(a.url)] = str(a.remote)
		Config.set_value(ADDON_URLS, urls)
		if await Movies.apply_remote_addons(addons):
			home_changed = true
	elif first and not Movies.addons.is_empty():
		_push_addons()
	var pr: Dictionary = cfg[1]
	if pr.ok and pr.data is Array:
		var plugs := plugins_from_remote(pr.data)
		if not plugs.is_empty() or not first:
			await Movies.apply_remote_plugins(plugs)
		elif not Movies.plugin_repos.is_empty():
			_push_plugins()
	if (cfg[2] as Dictionary).ok:
		home_changed = _put_if_changed("layout", layout_from_remote(_first(cfg[2]).get("settings_json", {}))) or home_changed
	if (cfg[3] as Dictionary).ok:
		var cj: Variant = _first(cfg[3]).get("collections_json", [])
		home_changed = _put_if_changed("collections", cj if cj is Array else []) or home_changed
	if (cfg[4] as Dictionary).ok:
		home_changed = _put_if_changed("settings", layout_settings(_first(cfg[4]).get("settings_json", {}))) or home_changed
	# 2) Bibliothek, Fortschritt, Gesehen: beim ersten Mal ganz, danach nur die Änderungen.
	var cursors: Dictionary = (sget("cursors", {}) as Dictionary).duplicate() if sget("cursors", {}) is Dictionary else {}
	var key := str(pid)
	var cur: Dictionary = cursors.get(key, {}) if cursors.get(key) is Dictionary else {}
	var err := ""
	if cur.is_empty():
		err = await _bootstrap(pid, cur)
	else:
		err = await _incremental(pid, cur)
	if err != "":
		return err
	cursors[key] = cur
	sput("cursors", cursors)
	if home_changed:
		Movies.invalidate_home()
	_sync_durch = true
	return ""


func _put_if_changed(key: String, value: Variant) -> bool:
	if JSON.stringify(sget(key, null)) == JSON.stringify(value):
		return false
	sput(key, value)
	return true


## Erstes Mal (oder neues Profil): Cursor merken, dann alles holen und übernehmen.
func _bootstrap(pid: int, cur: Dictionary) -> String:
	var cs := await _all([
		func() -> Dictionary: return await call_rpc("sync_get_library_delta_cursor", { "p_profile_id": pid }),
		func() -> Dictionary: return await call_rpc("sync_get_watch_progress_delta_cursor", { "p_profile_id": pid }),
		func() -> Dictionary: return await call_rpc("sync_get_watched_items_delta_cursor", { "p_profile_id": pid }),
	])
	var lib: Array = []
	var off := 0
	while true:
		var lr := await call_rpc("sync_pull_library", { "p_profile_id": pid, "p_limit": 500, "p_offset": off })
		if not lr.ok or not (lr.data is Array):
			return reason(lr, "Bibliothek aus Nuvio ließ sich nicht laden")
		for row in Fremd.zeilen(lr.data):
			if row is Dictionary and _str(row.get("content_id")) != "":
				lib.append(library_from_remote(row))
		if (lr.data as Array).size() < 500 or off >= 20000:
			break
		off += 500
	var data := await _all([
		func() -> Dictionary: return await call_rpc("sync_pull_watch_progress", { "p_profile_id": pid, "p_limit": 200 }),
		func() -> Dictionary: return await call_rpc("sync_pull_watched_items", { "p_profile_id": pid, "p_page": 1, "p_page_size": 5000 }),
	])
	var wp: Dictionary = data[0]
	var wi: Dictionary = data[1]
	var remote := progress_from_remote(wp.data if wp.ok and wp.data is Array else [], wi.data if wi.ok and wi.data is Array else [])
	Movies.apply_remote_data(lib, merge_progress(Movies.data.progress, remote, 0, false))
	for i in 3:
		var c := _cursor_of(cs[i])
		cur[["lib", "progress", "watched"][i]] = maxi(c, 0)
	await _fill_missing_items(remote)
	return ""


## Danach: nur Änderungen seit dem Cursor (meist ein paar Einträge, oft gar keine).
func _incremental(pid: int, cur: Dictionary) -> String:
	var ds := await _all([
		func() -> Dictionary: return await _pull_delta("sync_pull_library_delta", pid, int(cur.get("lib", 0))),
		func() -> Dictionary: return await _pull_delta("sync_pull_watch_progress_delta", pid, int(cur.get("progress", 0))),
		func() -> Dictionary: return await _pull_delta("sync_pull_watched_items_delta", pid, int(cur.get("watched", 0))),
	])
	for d in ds:
		if not bool(d.ok):
			var rr: Dictionary = d.get("r", {})
			# Kennt der Server die Änderungs-Abfrage nicht (älter): beim nächsten Mal wieder ganz.
			if int(rr.get("code", 0)) == 404:
				cur.clear()
				return ""
			return reason(rr, "Änderungen aus Nuvio ließen sich nicht laden")
	var lib_ev: Array = ds[0].events
	var prog_ev: Array = ds[1].events
	var watch_ev: Array = ds[2].events
	cur["lib"] = int(ds[0].cursor)
	cur["progress"] = int(ds[1].cursor)
	cur["watched"] = int(ds[2].cursor)
	if lib_ev.is_empty() and prog_ev.is_empty() and watch_ev.is_empty():
		return ""
	var lib := apply_library_delta(Movies.library_items(), lib_ev) if not lib_ev.is_empty() else Movies.library_items()
	var prog := apply_progress_delta(Movies.data.progress, prog_ev, watch_ev)
	Movies.apply_remote_data(lib, prog)
	await _fill_missing_items(progress_from_remote(prog_ev.filter(func(e): return str(e.get("operation", "")) != "delete"), []))
	return ""


## Für Weiterschauen braucht Uzai Name und Bilder; Nuvios Fortschritt hat sie nicht. Nur für
## Titel, die wirklich in Weiterschauen landen können, höchstens 8 je Abgleich; was kein Addon
## kennt, wird nicht bei jedem Abgleich neu versucht, sondern erst nach MISS_TAGE wieder (ein neues
## Addon kennt den Titel vielleicht).
func _fill_missing_items(remote: Dictionary) -> void:
	var now := int(Time.get_unix_time_from_system())
	var miss := miss_gueltig(sget("meta_miss", {}), now)
	var want: Array = []
	for mid in remote.keys():
		if (Movies.data.items as Dictionary).has(mid) or miss.has(mid):
			continue
		var newest := 0
		var type := "movie"
		var useful := false
		for vid in remote[mid].keys():
			var e: Dictionary = remote[mid][vid]
			newest = maxi(newest, int(e.updated))
			if int(e.get("season", 0)) > 0 or str(e.get("type", "")) == "series":
				type = "series"
			if not bool(e.watched) and float(e.position) >= 10.0:
				useful = true
		if type == "series" and now - newest < 60 * 86400:
			useful = true
		if useful:
			want.append({ "id": mid, "type": type, "at": newest })
	want.sort_custom(func(a, b): return int(a.at) > int(b.at))
	var got := false
	for w in want.slice(0, 8):
		var m: Dictionary = await Movies.meta(str(w.type), str(w.id))
		if m.is_empty():
			miss[str(w.id)] = now
		else:
			Movies.remember(m)
			got = true
	sput("meta_miss", miss)
	if got:
		Movies.save()
		Movies.notify_changed()


## Rein: was von der Merkliste „kennt kein Addon“ noch gilt (Kennung → Zeitpunkt, jünger als MISS_TAGE).
static func miss_gueltig(v: Variant, now: int) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			var t: Variant = v[k]
			if (t is int or t is float) and now - int(t) < MISS_TAGE * 86400:
				out[str(k)] = int(t)
	return out


## Rein: Bibliothek nach Änderungs-Ereignissen (in Reihenfolge) – neue nach vorn. Je Titel zählt das
## letzte Ereignis; ein Durchgang über Ereignisse und Bibliothek (auch Tausende Ereignisse nach einem
## Import im Konto halten Uzai nicht an).
static func apply_library_delta(lib: Array, events: Array) -> Array:
	var evs := events.duplicate()
	evs.sort_custom(func(a, b): return int(a.get("event_id", 0)) < int(b.get("event_id", 0)))
	var zuletzt := {}                # Kennung → letztes Ereignis, in der Reihenfolge der letzten Ereignisse
	for ev in evs:
		var cid := _str(ev.get("content_id"))
		if cid != "":
			zuletzt.erase(cid)
			zuletzt[cid] = ev
	var out: Array = []
	var cids: Array = zuletzt.keys()
	cids.reverse()
	for cid in cids:
		if str(zuletzt[cid].get("operation", "upsert")) != "delete":
			out.append(library_from_remote(zuletzt[cid]))
	for e in lib:
		if not zuletzt.has(str(e.get("id", ""))):
			out.append((e as Dictionary).duplicate(true))
	return out


## Rein: Fortschritt/Gesehen nach Änderungs-Ereignissen. Neues gewinnt; „gelöscht“ in Nuvio
## (z. B. aus Weiterschauen entfernt) löscht hier, wenn hier seitdem nichts Neueres passiert ist.
static func apply_progress_delta(local: Dictionary, prog_events: Array, watched_events: Array) -> Dictionary:
	var ups_p: Array = prog_events.filter(func(e): return str(e.get("operation", "upsert")) != "delete")
	var ups_w: Array = watched_events.filter(func(e): return str(e.get("operation", "upsert")) != "delete")
	var out := merge_progress(local, progress_from_remote(ups_p, ups_w), 0, false)
	for ev in prog_events:
		if str(ev.get("operation", "")) != "delete":
			continue
		var mid := _str(ev.get("content_id"))
		var vid := video_id_for(ev)
		var e: Dictionary = (out.get(mid, {}) as Dictionary).get(vid, {})
		if not e.is_empty() and not bool(e.get("watched", false)) and int(e.get("updated", 0)) <= int(float(ev.get("last_watched", 0)) / 1000.0) + 1:
			(out[mid] as Dictionary).erase(vid)
	for ev in watched_events:
		if str(ev.get("operation", "")) != "delete":
			continue
		var mid := _str(ev.get("content_id"))
		var s := int(ev.get("season", 0) if ev.get("season") != null else 0)
		var ep := int(ev.get("episode", 0) if ev.get("episode") != null else 0)
		var vid := mid if s <= 0 and ep <= 0 else "%s:%d:%d" % [mid, s, ep]
		var e: Dictionary = (out.get(mid, {}) as Dictionary).get(vid, {})
		if not e.is_empty() and bool(e.get("watched", false)):
			(out[mid] as Dictionary).erase(vid)
	for mid in out.keys():
		if (out[mid] as Dictionary).is_empty():
			out.erase(mid)
	return out


func _log(text: String) -> void:
	if _demo:
		return
	Logdatei.zeile(Config.path("logs/nuvio.log"), text, 300000)


## Gibt zurück, ob das Konto alles angenommen hat. Nur dann darf danach übernommen werden, was im Konto steht.
func _push_local_everything(pid: int) -> bool:
	var gut := true
	var lib: Array = Movies.library_items().map(func(e): return library_to_remote(e))
	for i in range(0, lib.size(), 500):
		var r := await call_rpc("sync_push_library_items", { "p_profile_id": pid, "p_origin_client_id": client_id(), "p_items": lib.slice(i, i + 500) })
		gut = gut and Fremd.ja(r.get("ok"))
	var entries: Array = []
	var watched: Array = []
	for mid in (Movies.data.progress as Dictionary).keys():
		var item: Dictionary = Movies.data.items.get(mid, {})
		for vid in (Movies.data.progress[mid] as Dictionary).keys():
			var e: Dictionary = Movies.data.progress[mid][vid]
			var type := str(item.get("type", "series" if int(e.get("season", 0)) > 0 else "movie"))
			if bool(e.get("watched", false)):
				watched.append(_watched_row(mid, type, e))
			elif float(e.get("position", 0)) >= 10.0:
				entries.append(progress_to_remote(mid, type, vid, e))
	for i in range(0, entries.size(), 200):
		var r := await call_rpc("sync_push_watch_progress", { "p_profile_id": pid, "p_entries": entries.slice(i, i + 200) })
		gut = gut and Fremd.ja(r.get("ok"))
	for i in range(0, watched.size(), 500):
		var r := await call_rpc("sync_push_watched_items", { "p_profile_id": pid, "p_items": watched.slice(i, i + 500) })
		gut = gut and Fremd.ja(r.get("ok"))
	return gut


static func _watched_row(mid: String, type: String, e: Dictionary) -> Dictionary:
	var row := { "content_id": mid, "content_type": "series" if type == "series" else "movie", "title": str(e.get("title", "")),
		"watched_at": int(e.get("updated", Time.get_unix_time_from_system())) * 1000 }
	if int(e.get("season", 0)) > 0 or int(e.get("episode", 0)) > 0:
		row["season"] = int(e.get("season", 0))
		row["episode"] = int(e.get("episode", 0))
	return row


# --- Zurückschreiben ----------------------------------------------------------------------------

## Movies meldet Änderungen in Uzai (nie die, die gerade aus Nuvio kamen).
func _on_local_change(kind: String, info: Dictionary) -> void:
	if not connected():
		return
	var pid := profile_id()
	match kind:
		"progress":
			var e: Dictionary = info.entry
			if bool(e.get("watched", false)):
				_queue("sync_push_watched_items", { "p_profile_id": pid, "p_items": [_watched_row(str(info.meta_id), str(info.type), e)] })
			var row := progress_to_remote(str(info.meta_id), str(info.type), str(info.video_id), e)
			_progress_q[progress_key(str(info.meta_id), int(e.get("season", 0)), int(e.get("episode", 0)))] = row
			if _push_timer.is_stopped():
				_push_timer.start()
		"watched":
			var e: Dictionary = info.entry
			if bool(info.on):
				_queue("sync_push_watched_items", { "p_profile_id": pid, "p_items": [_watched_row(str(info.meta_id), str(info.type), e)] })
			else:
				var key := { "content_id": str(info.meta_id) }
				if int(e.get("season", 0)) > 0 or int(e.get("episode", 0)) > 0:
					key["season"] = int(e.get("season", 0))
					key["episode"] = int(e.get("episode", 0))
				_queue("sync_delete_watched_items", { "p_profile_id": pid, "p_keys": [key] })
				_queue("sync_delete_watch_progress",
						{ "p_profile_id": pid, "p_progress_key": progress_key(str(info.meta_id), int(e.get("season", 0)), int(e.get("episode", 0))) })
		"continue_removed":
			_queue("sync_delete_watch_progress", { "p_profile_id": pid, "p_keys": info.keys })
		"library_add":
			_queue("sync_push_library_items", { "p_profile_id": pid, "p_origin_client_id": client_id(), "p_items": [library_to_remote(info.entry)] })
		"library_remove":
			_queue("sync_delete_library_items", { "p_profile_id": pid, "p_origin_client_id": client_id(),
				"p_keys": [{ "content_id": str(info.id), "content_type": str(info.type) }] })
		"addons":
			_push_addons()
		"plugins":
			_push_plugins()


func _push_addons() -> void:
	var pid := profile_id()
	if scope_profile(profiles(), pid, "addons") != pid:
		return   # teilt die Addons von Profil 1: wie Nuvio dort nichts schreiben
	# Ohne die Liste selbst: Die Adressen tragen oft Zugangsschlüssel und gehören nicht offen in nuvio.json (die auch in
	# jede Sicherung kommt). Sie wird erst beim Senden aus Movies.addons gebaut (_pending_senden).
	_queue("sync_push_addons", { "p_profile_id": pid }, true)


## Nuvios Adressen der Addons (Uzais Adresse → Nuvios): versiegelt in den Einstellungen wie movies.addons.
const ADDON_URLS := "nuvio.addon_urls"


func _addon_urls() -> Dictionary:
	var v: Variant = Config.get_value(ADDON_URLS, {})
	return v if v is Dictionary else {}


## Ältere Fassungen hielten die Adressen offen in nuvio.json (addon_urls und in der Warteschlange): umziehen.
func _addon_urls_umziehen() -> void:
	var weg := false
	if st.get("addon_urls") is Dictionary:
		if _addon_urls().is_empty():
			Config.set_value(ADDON_URLS, st.addon_urls)
		weg = true
	st.erase("addon_urls")
	var pend: Variant = st.get("pending", [])
	for job in (pend if pend is Array else []):
		if job is Dictionary and job.get("params") is Dictionary and (job.params as Dictionary).has("p_addons"):
			(job.params as Dictionary).erase("p_addons")
			weg = true
	if weg and not "--demo" in OS.get_cmdline_user_args():
		save_state()


func _push_plugins() -> void:
	var pid := profile_id()
	if scope_profile(profiles(), pid, "plugins") != pid:
		return
	_queue("sync_push_plugins", { "p_profile_id": pid, "p_plugins": plugins_to_remote(Movies.plugin_repos) }, true)


func _flush_progress() -> void:
	if _progress_q.is_empty():
		return
	var rows: Array = _progress_q.values()
	_progress_q = {}
	_queue("sync_push_watch_progress", { "p_profile_id": profile_id(), "p_entries": rows })


## In die Warteschlange (übersteht Neustarts) und gleich versuchen. replace: ältere gleiche Aufträge
## ersetzen (volle Listen wie Addons).
func _queue(name: String, params: Dictionary, replace := false) -> void:
	var list: Array = (sget("pending", []) as Array).duplicate(true) if sget("pending", []) is Array else []
	if replace:
		list = list.filter(func(p): return str(p.get("rpc", "")) != name)
	list.append({ "rpc": name, "params": params })
	if list.size() > MAX_PENDING:
		list = list.slice(list.size() - MAX_PENDING)
	sput("pending", list)
	flush_pending()


var _flushing := false


func flush_pending() -> void:
	if _flushing or not connected():
		return
	_flushing = true
	# In einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird _flushing hier trotzdem gelöst.
	await _pending_senden()
	_flushing = false


func _pending_senden() -> void:
	while true:
		var list := Fremd.liste(sget("pending", []))
		if list.is_empty():
			break
		# Ein kaputter Eintrag (Datei von Hand geändert, halb geschrieben) fliegt raus, statt die Schlange für immer zu
		# verstopfen.
		var job := Fremd.verz(list[0])
		if Fremd.text(job.get("rpc")) != "":
			var params := Fremd.verz(job.get("params")).duplicate(true)
			if Fremd.text(job.get("rpc")) == "sync_push_addons":
				params["p_addons"] = addons_to_remote(Movies.addons, _addon_urls())
			var r := await call_rpc(Fremd.text(job.get("rpc")), params)
			if not r.ok and Fremd.zahl(r.get("code")) not in [400, 404, 409, 422]:
				break   # Netz weg: später nochmal (falsche Aufträge fliegen raus)
		var now_list := Fremd.liste(sget("pending", [])).duplicate(true)
		if not now_list.is_empty():
			now_list.remove_at(0)
		sput("pending", now_list)


func pending_count() -> int:
	var list: Variant = sget("pending", [])
	return (list as Array).size() if list is Array else 0


# --- Für die Startseite --------------------------------------------------------------------------

func layout() -> Dictionary:
	if not connected():
		return {}
	var l: Variant = sget("layout", {})
	return l if l is Dictionary else {}


func settings() -> Dictionary:
	if not connected():
		return {}
	var s: Variant = sget("settings", {})
	return s if s is Dictionary else {}


func collections() -> Array:
	if not connected():
		return []
	var c: Variant = sget("collections", [])
	return c if c is Array else []


## Für Movies.home_rows: Reihen wie in der Nuvio-App anordnen. Ohne Layout im Konto stehen
## angepinnte Sammlungen oben, die anderen unten.
func arrange(rows: Array, coll_rows: Dictionary) -> Array:
	var lay := layout()
	if not (lay.get("items", []) as Array).is_empty():
		return apply_layout(rows, lay, coll_rows)
	var top: Array = []
	var bottom: Array = []
	for k in coll_rows.keys():
		for r in coll_rows[k]:
			(top if bool(r.get("pin", false)) else bottom).append(r)
	return top + rows + bottom


## Schlüssel (addon/typ/katalog) der Kataloge, die im Nuvio-Layout aus sind.
func disabled_keys() -> Dictionary:
	var out := {}
	for it in layout().get("items", []):
		if not bool(it.get("enabled", true)) and str(it.get("collection", "")) == "":
			out[str(it.key)] = true
	return out


## Reihen mit Ordner-Kacheln je Sammlung (collection_<id> → [Reihe]), siehe collection_folders.
func collection_folder_rows() -> Dictionary:
	return collection_folders(collections())


## Kennung für Movies' Zwischenspeicher der Startseite.
func layout_sig() -> String:
	if not connected():
		return ""
	return str(JSON.stringify(layout()).hash()) + ":" + str(JSON.stringify(collections()).hash()) + ":" + str(profile_id())


## Reihen fürs große Titelbild (hero_catalog_keys), leer = die ersten Reihen wie bisher.
func hero_rows(rows: Array) -> Array:
	var keys := hero_keys(settings())
	if keys.is_empty():
		return []
	return rows.filter(func(r): return legacy_key(str(r.get("addon_id", "")), str(r.get("type", "")), str(r.get("catalog_id", ""))) in keys)


func hero_enabled() -> bool:
	return setting_on(settings(), "hero_section_enabled", true)


func continue_enabled() -> bool:
	return setting_on(settings(), "continue_watching_enabled", true)


func status_text() -> String:
	if not connected():
		return "Nicht angemeldet"
	if busy:
		return "Wird abgeglichen …"
	var at := int(sget("last_sync", 0))
	var who := email() if email() != "" else "Nuvio-Konto"
	if at <= 0:
		return who
	var mins := int((Time.get_unix_time_from_system() - at) / 60.0)
	return "%s · abgeglichen %s" % [who, "gerade eben" if mins < 1 else ("vor %d Min." % mins if mins < 60 else "vor %d Std." % int(mins / 60.0))]
