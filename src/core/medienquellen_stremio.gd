extends RefCounted
## Stremio-Konto als Filme-Quelle (Roadmap 35) – die reinen Teile. Nur, was dem Nutzer gehört:
## seine Bibliothek, sein Weiterschauen und die Liste SEINER installierten Addons.
##
## Rechtlich (R1, R3): Uzai liefert, voreinstellt und empfiehlt keine Addons. Übernommen wird nur
## auf ausdrücklichen Wunsch, was der Nutzer selbst in Stremio installiert hat – mit dem Hinweis
## „deine Quellen, deine Verantwortung“. Die Anbindung ist inoffiziell (dieselbe Schnittstelle wie
## die Stremio-Apps, ohne sich als eine davon auszugeben) und wird nie „offiziell“ genannt.
## Angemeldet wird per Code auf link.stremio.com (wie an Fernsehern), nie mit Passwort in Uzai.

const B := preload("res://src/core/medienquellen_basis.gd")
const MoviesScript := preload("res://src/core/movies.gd")

const LINK_API := "https://link.stremio.com/api/v2"
const API := "https://api.strem.io/api"
const LINK_PAGE := "https://link.stremio.com"
const LINK_HOSTS := ["link.stremio.com", "www.stremio.com", "stremio.com"]
const ADDON := "quelle:stremio"
const LIB_MAX := 3000


static func link_base() -> String:
	var env := Config.probe_env("UZAI_STREMIO_LINK")
	return env.trim_suffix("/") if env != "" else LINK_API


static func api_base() -> String:
	var env := Config.probe_env("UZAI_STREMIO_API")
	return env.trim_suffix("/") if env != "" else API


static func _result(d: Variant) -> Variant:
	return B.dict(d).get("result")


## Antwort auf …/create?type=Create: { code, link } – link nur auf Stremios eigene Seite.
static func parse_link(d: Variant) -> Dictionary:
	var r := B.dict(_result(d))
	var code := B.ident(r.get("code", ""), "alnum", 4, 16).to_upper()
	if code == "":
		return {}
	var link := B.text(r.get("link", ""), 200)
	var o := B.origin_of(link)
	var ok := false
	for h in LINK_HOSTS:
		if o == "https://" + h:
			var rest := link.substr(o.length())
			ok = rest == "" or B.safe_path(rest if rest.begins_with("/") else "/" + rest) != ""
	return { "code": code, "link": link if ok else LINK_PAGE }


## Antwort auf …/read?type=Read&code=…: der Anmelde-Schlüssel, solange noch nicht bestätigt "".
static func parse_auth_key(d: Variant) -> String:
	return B.ident(B.dict(_result(d)).get("authKey", ""), "token", 16, 256)


static func parse_email(d: Variant) -> String:
	var e := B.text(B.dict(_result(d)).get("email", ""), 120)
	return e if e.contains("@") and not e.contains(" ") else ""


## Installierte Addons des Kontos (addonCollectionGet): nur https-Adressen, ohne Doppelte.
## { url, name } – die Adresse ist die des manifest.json, wie Uzai sie selbst installiert.
static func parse_addons(d: Variant) -> Array:
	var out: Array = []
	var seen := {}
	for a in B.arr(B.dict(_result(d)).get("addons", []), 120):
		var ad := B.dict(a)
		var url := B.text(ad.get("transportUrl", ""), 2000)
		if not url.to_lower().begins_with("https://") or B.origin_of(url) == "" or url.contains(" "):
			continue
		var u := MoviesScript.normalize_manifest_url(url)
		if seen.has(u):
			continue
		seen[u] = true
		var name := B.text(B.dict(ad.get("manifest", {})).get("name", ""), 60)
		out.append({ "url": u, "name": name if name != "" else B.origin_of(url).trim_prefix("https://") })
	return out


## Kennung eines Titels in Stremio (tt…, kitsu:…): nur harmlose Zeichen.
static func _sid(v: Variant) -> String:
	var s := B.text(v, 100)
	if s == "":
		return ""
	for ch in s:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in [":", ".", "_", "-"]):
			return ""
	return s


## Bibliothek (datastoreGet, collection libraryItem): geprüfte Einträge mit Fortschritt.
## raw: der Eintrag, wie Stremio ihn geschickt hat (für das Zurückschreiben des Fortschritts).
static func parse_library(d: Variant) -> Array:
	var out: Array = []
	for v in B.arr(_result(d), LIB_MAX):
		var e := B.dict(v)
		var id := _sid(e.get("_id", ""))
		var t := str(e.get("type", ""))
		var name := B.text(e.get("name", ""))
		if id == "" or name == "" or t not in ["movie", "series"]:
			continue
		var st := B.dict(e.get("state", {}))
		var poster := B.text(e.get("poster", ""), 600)
		if not poster.begins_with("https://") or poster.contains(" "):
			poster = MoviesScript.metahub("poster", id)
		var vid := _sid(st.get("video_id", ""))
		var sv := MoviesScript.split_video_id(vid) if vid != "" else { "season": 0, "episode": 0 }
		var updated := B.iso_time(st.get("lastWatched", ""))
		out.append({
			"id": id, "type": t, "name": name, "poster": poster, "background": MoviesScript.metahub("background", id),
			"logo": MoviesScript.metahub("logo", id), "description": "", "year": "", "release_info": "", "imdb_rating": "", "genres": [],
			"addon_id": "", "poster_shape": B.text(e.get("posterShape", ""), 12), "age": -1, "family": false, "source": "stremio",
			"removed": B.flag(e.get("removed", false)), "temp": B.flag(e.get("temp", false)),
			"position": B.num(st.get("timeOffset", 0)) / 1000.0, "duration": B.num(st.get("duration", 0)) / 1000.0,
			"video_id": vid if vid != "" else (id if t == "movie" else ""), "season": int(sv.season), "episode": int(sv.episode),
			"watched": B.num(st.get("flaggedWatched", 0)) > 0 or B.num(st.get("timesWatched", 0)) > 0,
			"updated": updated, "mtime": B.iso_time(e.get("_mtime", "")), "raw": e,
		})
	return out


## Was in der Bibliothek liegt (nicht entfernt, nicht nur vorübergehend), zuletzt geändert zuerst.
static func library(items: Array) -> Array:
	var out := items.filter(func(e: Dictionary) -> bool: return not bool(e.removed) and not bool(e.temp))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.mtime) > int(b.mtime))
	return out.map(func(e: Dictionary) -> Dictionary: return _clean(e))


## Weiterschauen wie in Stremio: angefangen (Stelle > 0), auch vorübergehende Einträge.
static func continue_items(items: Array) -> Array:
	var out: Array = []
	for e in items:
		if float(e.position) <= 0.0 or (bool(e.removed) and not bool(e.temp)) or str(e.video_id) == "":
			continue
		var it := _clean(e)
		it.merge({ "video_id": str(e.video_id), "season": int(e.season), "episode": int(e.episode), "episode_title": "",
			"thumbnail": "", "position": float(e.position), "duration": float(e.duration), "updated": int(e.updated), "next_up": false }, true)
		out.append(it)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.updated) > int(b.updated))
	return out.slice(0, 40)


static func _clean(e: Dictionary) -> Dictionary:
	var out := {}
	for k in ["id", "type", "name", "poster", "background", "logo", "description", "year", "release_info", "imdb_rating", "genres", "addon_id", "poster_shape",
			"age", "family", "source"]:
		out[k] = e[k]
	return out


## Eintrag mit neuem Stand für datastorePut: nur der Fortschritt ändert sich, alles andere bleibt,
## wie Stremio es geschickt hat. Zeiten in Millisekunden, Datum als ISO-Text.
static func put_change(raw: Dictionary, pos_s: float, dur_s: float, video_id: String, done: bool, now: int) -> Dictionary:
	var e := raw.duplicate(true)
	var st: Dictionary = e.get("state", {}) if e.get("state") is Dictionary else {}
	var iso := Time.get_datetime_string_from_unix_time(now) + ".000Z"
	st["timeOffset"] = 0 if done else int(maxf(pos_s, 0.0) * 1000.0)
	if dur_s > 0.0:
		st["duration"] = int(dur_s * 1000.0)
	if video_id != "":
		st["video_id"] = video_id
	st["lastWatched"] = iso
	if done:
		st["timesWatched"] = B.num(st.get("timesWatched", 0)) + 1
		st["flaggedWatched"] = 1
	e["state"] = st
	e["_mtime"] = iso
	return e
