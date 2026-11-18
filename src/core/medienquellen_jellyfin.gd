extends RefCounted
## Jellyfin und Emby als Filme-Quelle (Roadmap 35) – die reinen Teile. Beide sprechen dieselbe
## Schnittstelle (Emby ist der Vorgänger von Jellyfin); Unterschiede: Jellyfin kennt Quick Connect
## (Code am Fernseher, im eigenen Konto bestätigen) und liest die Anmeldung aus „Authorization“,
## Emby aus „X-Emby-Authorization“ bzw. „X-Emby-Token“.
##
## Anmeldung nur per Quick Connect oder Name und Passwort – das Passwort geht einmal an den
## Server und wird nie gespeichert, nur der Zugangsschlüssel (im Tresor). Bilder und Dateien
## baut Uzai aus der Server-Adresse und geprüften Kennungen selbst.

const B := preload("res://src/core/medienquellen_basis.gd")
const MoviesScript := preload("res://src/core/movies.gd")

const TICKS := 10000000.0                ## 100-ns-Schritte je Sekunde (RunTimeTicks)
const PAGE := 60
const DISCOVERY_PORT := 7359
const DISCOVERY_MAX := 2048
const FIELDS := "Overview,Genres,ProductionYear,OfficialRating,CommunityRating,PremiereDate,ProviderIds,ParentId"


static func prefix(kind: String) -> String:
	return "emby:" if kind == "emby" else "jf:"


static func addon_id(kind: String) -> String:
	return "quelle:" + kind


static func source_name(kind: String) -> String:
	return "Emby" if kind == "emby" else "Jellyfin"


## Anmelde-Kopfzeile: wer fragt (Uzai, Gerät), dazu der Zugangsschlüssel, wenn es einen gibt.
static func auth_value(device_id: String, version: String, token := "") -> String:
	var s := 'MediaBrowser Client="Uzai", Device="Uzai", DeviceId="%s", Version="%s"' % [device_id, version]
	return s + (', Token="%s"' % token if token != "" else "")


static func headers(kind: String, device_id: String, version: String, token := "") -> PackedStringArray:
	var h := PackedStringArray(["Accept: application/json"])
	if kind == "emby":
		h.append("X-Emby-Authorization: " + auth_value(device_id, version, token))
		if token != "":
			h.append("X-Emby-Token: " + token)
	else:
		h.append("Authorization: " + auth_value(device_id, version, token))
	return h


## Kopfzeilen für mpv beim Abspielen (ohne Anführungszeichen: mpv bekommt sie als Argument).
static func play_headers(kind: String, device_id: String, version: String, token: String) -> Dictionary:
	if kind == "emby":
		return { "X-Emby-Token": token }
	return { "Authorization": "MediaBrowser Client=Uzai, Device=Uzai, DeviceId=%s, Version=%s, Token=%s" % [device_id, version, token] }


static func token_ok(t: Variant) -> String:
	return B.ident(t, "alnum", 16, 128)


static func id_ok(v: Variant) -> String:
	return B.ident(v, "hex", 1, 64)


# --- Server und Anmeldung ----------------------------------------------------------------------

## /System/Info/Public: { name, id, version, kind } oder {}. kind: „jellyfin“ oder „emby“.
static func parse_public_info(d: Variant) -> Dictionary:
	var p := B.dict(d)
	var id := id_ok(p.get("Id", ""))
	var ver := B.text(p.get("Version", ""), 30)
	if id == "" or ver == "":
		return {}
	var product := B.text(p.get("ProductName", ""), 60).to_lower()
	var name := B.text(p.get("ServerName", ""), 60)
	return { "name": name if name != "" else "Medienserver", "id": id, "version": ver, "kind": "jellyfin" if product.contains("jellyfin") else "emby" }


## Antwort von /QuickConnect/Initiate bzw. /QuickConnect/Connect: { secret, code, ok }.
static func parse_quick(d: Variant) -> Dictionary:
	var p := B.dict(d)
	var secret := B.ident(p.get("Secret", ""), "alnum", 16, 128)
	if secret == "":
		return {}
	return { "secret": secret, "code": B.ident(p.get("Code", ""), "alnum", 4, 12), "ok": B.flag(p.get("Authenticated", false)) }


## Ergebnis einer Anmeldung (/Users/AuthenticateByName, /Users/AuthenticateWithQuickConnect):
## { token, user_id, user_name } oder {}.
static func parse_auth(d: Variant) -> Dictionary:
	var p := B.dict(d)
	var u := B.dict(p.get("User", {}))
	var tok := token_ok(p.get("AccessToken", ""))
	var uid := id_ok(u.get("Id", ""))
	if tok == "" or uid == "":
		return {}
	return { "token": tok, "user_id": uid, "user_name": B.text(u.get("Name", ""), 60) }


## Antwort auf den Rundruf „who is JellyfinServer?“ (UDP 7359). Nur kleine JSON-Antworten von
## einer privaten Adresse; die genannte Adresse muss genau der Absender sein (sonst könnte ein
## Gerät im Netz auf einen fremden Server zeigen). { name, id, address } oder {}.
static func parse_discovery(body: PackedByteArray, sender_ip: String) -> Dictionary:
	if body.size() > DISCOVERY_MAX or not B.is_private_ip(sender_ip):
		return {}
	var p := B.dict(B.json(body, DISCOVERY_MAX))
	var srv := B.parse_server(B.text(p.get("Address", ""), 200))
	var id := id_ok(p.get("Id", ""))
	if srv.is_empty() or id == "" or str(srv.host) != sender_ip.to_lower():
		return {}
	var name := B.text(p.get("Name", ""), 60)
	return { "name": name if name != "" else sender_ip, "id": id, "address": str(srv.base) }


# --- Bibliotheken und Titel --------------------------------------------------------------------

## Bibliotheken (/Users/<id>/Views): { id, name, type: movies|tvshows|boxsets|mixed, family }.
static func parse_views(d: Variant) -> Array:
	var out: Array = []
	for v in B.arr(B.dict(d).get("Items", []), 60):
		var it := B.dict(v)
		var id := id_ok(it.get("Id", ""))
		var ct := B.text(it.get("CollectionType", "mixed"), 20).to_lower()
		if ct == "":
			ct = "mixed"
		if id == "" or ct not in ["movies", "tvshows", "boxsets", "mixed", "homevideos"]:
			continue
		var name := B.text(it.get("Name", ""), 60)
		out.append({ "id": id, "name": name, "type": ct, "family": B.family_word(name) })
	return out


static func img(base: String, id: String, kind: String, tag: Variant, max_w: int) -> String:
	var t := B.ident(tag, "alnum", 1, 64)
	if id == "" or t == "":
		return ""
	return "%s/Items/%s/Images/%s?tag=%s&maxWidth=%d&quality=90" % [base, id, kind, t, max_w]


static func _backdrop(base: String, it: Dictionary) -> String:
	var tags := B.arr(it.get("BackdropImageTags", []), 4)
	if not tags.is_empty():
		return img(base, id_ok(it.get("Id", "")), "Backdrop/0", tags[0], 1920)
	var ptags := B.arr(it.get("ParentBackdropImageTags", []), 4)
	if not ptags.is_empty():
		return img(base, id_ok(it.get("ParentBackdropItemId", "")), "Backdrop/0", ptags[0], 1920)
	return ""


static func _genres(v: Variant) -> Array:
	var out: Array = []
	for g in B.arr(v, 12):
		var s := B.text(g, 40)
		if s != "" and not out.has(s):
			out.append(s)
	return out.slice(0, 6)


static func _year(it: Dictionary) -> String:
	var y := B.num(it.get("ProductionYear", 0))
	if y >= 1870 and y <= 2200:
		return str(y)
	var d := B.text(it.get("PremiereDate", ""), 30)
	return d.substr(0, 4) if d.length() >= 4 and d.substr(0, 4).is_valid_int() else ""


## MetaPreview für Film oder Serie; Folgen (Weiterschauen, Als Nächstes) werden zu ihrer Serie
## mit Angaben zur Folge. lib: { family } der Bibliothek.
static func preview(v: Variant, base: String, kind: String, lib := {}) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var it: Dictionary = v
	var t := str(it.get("Type", ""))
	if t == "Episode":
		return _episode_item(it, base, kind, lib)
	if t not in ["Movie", "Series"]:
		return {}
	var id := id_ok(it.get("Id", ""))
	var name := B.text(it.get("Name", ""))
	if id == "" or name == "":
		return {}
	var tags := B.dict(it.get("ImageTags", {}))
	var raw_rating := B.text(it.get("OfficialRating", ""), 24)
	var score: Variant = it.get("CommunityRating")
	var y := _year(it)
	var out := {
		"id": prefix(kind) + id, "type": "movie" if t == "Movie" else "series", "name": name,
		"poster": img(base, id, "Primary", tags.get("Primary", ""), 400), "background": _backdrop(base, it),
		"logo": img(base, id, "Logo", tags.get("Logo", ""), 800), "description": B.text(it.get("Overview", ""), B.DESC_MAX),
		"year": y, "release_info": y, "imdb_rating": "%.1f" % float(score) if (score is float or score is int) and float(score) > 0.0 and float(score) <= 10.0
			else "",
		"genres": _genres(it.get("Genres", [])), "addon_id": addon_id(kind), "poster_shape": "",
		"age": B.age_of(raw_rating), "content_rating": B.rating_label(raw_rating), "family": bool(lib.get("family", false)), "source": kind,
	}
	var ticks := B.num(it.get("RunTimeTicks", 0))
	if t == "Movie" and ticks > 0:
		out["runtime"] = "%d min" % int(round(ticks / TICKS / 60.0))
	return out


static func _episode_item(it: Dictionary, base: String, kind: String, lib: Dictionary) -> Dictionary:
	var id := id_ok(it.get("Id", ""))
	var sid := id_ok(it.get("SeriesId", ""))
	var name := B.text(it.get("SeriesName", ""))
	if id == "" or sid == "" or name == "":
		return {}
	var ud := B.dict(it.get("UserData", {}))
	var pos := B.num(ud.get("PlaybackPositionTicks", 0)) / TICKS
	var raw_rating := B.text(it.get("OfficialRating", ""), 24)
	return {
		"id": prefix(kind) + sid, "type": "series", "name": name,
		"poster": img(base, sid, "Primary", it.get("SeriesPrimaryImageTag", ""), 400), "background": _backdrop(base, it), "logo": "",
		"description": B.text(it.get("Overview", ""), B.DESC_MAX), "year": "", "release_info": "", "imdb_rating": "", "genres": [],
		"addon_id": addon_id(kind), "poster_shape": "", "age": B.age_of(raw_rating), "content_rating": B.rating_label(raw_rating),
		"family": bool(lib.get("family", false)), "source": kind,
		"video_id": prefix(kind) + id, "season": B.num(it.get("ParentIndexNumber", 0)), "episode": B.num(it.get("IndexNumber", 0)),
		"episode_title": B.text(it.get("Name", "")), "thumbnail": img(base, id, "Primary", B.dict(it.get("ImageTags", {})).get("Primary", ""), 640),
		"position": pos, "duration": B.num(it.get("RunTimeTicks", 0)) / TICKS, "updated": B.iso_time(ud.get("LastPlayedDate", "")),
		"next_up": pos <= 0.0,
	}


## Titel einer Liste ({ Items: [...] } oder eine reine Liste wie /Items/Latest), ohne Doppelte.
static func parse_list(d: Variant, base: String, kind: String, lib := {}) -> Array:
	var list := B.arr(d, 500) if d is Array else B.arr(B.dict(d).get("Items", []), 500)
	var out: Array = []
	var seen := {}
	for v in list:
		var it := preview(v, base, kind, lib)
		if it.is_empty() or seen.has(str(it.id)):
			continue
		seen[str(it.id)] = true
		# Neue Folgen (/Items/Latest) stehen für ihre Serie – ohne Angaben zur Folge.
		for k in ["video_id", "season", "episode", "episode_title", "thumbnail", "position", "duration", "updated", "next_up"]:
			it.erase(k)
		out.append(it)
	return out


## Weiterschauen (/Items/Resume) und Als Nächstes (/Shows/NextUp) zusammen, neueste zuerst.
static func parse_continue(resume: Variant, next_up: Variant, base: String, kind: String, libs := {}) -> Array:
	var out: Array = []
	var seen := {}
	for si in 2:
		var src: Variant = resume if si == 0 else next_up
		for v in B.arr(B.dict(src).get("Items", []), 60):
			if not (v is Dictionary):
				continue
			var lib: Dictionary = libs.get(id_ok(v.get("ParentId", "")), {})
			var it := preview(v, base, kind, lib)
			if it.is_empty() or seen.has(str(it.id)):
				continue
			seen[str(it.id)] = true
			if not it.has("video_id"):
				var ud := B.dict(v.get("UserData", {}))
				var pos := B.num(ud.get("PlaybackPositionTicks", 0)) / TICKS
				it.merge({ "video_id": str(it.id), "season": 0, "episode": 0, "episode_title": "", "thumbnail": "", "position": pos,
					"duration": B.num(v.get("RunTimeTicks", 0)) / TICKS, "updated": B.iso_time(ud.get("LastPlayedDate", "")), "next_up": pos <= 0.0 }, true)
			if si == 1:
				it.next_up = true
				it.position = 0.0
			out.append(it)
	return out


## Sammlungen (BoxSets) als Ordner: { id, title, poster, background, count }.
static func parse_collections(d: Variant, base: String) -> Array:
	var out: Array = []
	for v in B.arr(B.dict(d).get("Items", []), 60):
		var it := B.dict(v)
		var id := id_ok(it.get("Id", ""))
		var title := B.text(it.get("Name", ""), 80)
		if id == "" or title == "" or str(it.get("Type", "")) != "BoxSet":
			continue
		out.append({ "id": id, "title": title, "poster": img(base, id, "Primary", B.dict(it.get("ImageTags", {})).get("Primary", ""), 400),
			"background": _backdrop(base, it), "count": B.num(it.get("ChildCount", 0)) })
	return out


static func parse_genres(d: Variant) -> Array:
	var out: Array = []
	for v in B.arr(B.dict(d).get("Items", []), 120):
		var n := B.text(B.dict(v).get("Name", ""), 40)
		if n != "" and not n.contains("|"):
			out.append({ "key": n, "title": n })
	return out


# --- Details, Folgen, Abspielen ----------------------------------------------------------------

## Volle Angaben aus /Users/<id>/Items/<id>; episodes: /Shows/<id>/Episodes der Serie.
static func parse_meta(d: Variant, base: String, kind: String, episodes: Variant = null, lib := {}) -> Dictionary:
	var it := B.dict(d)
	var out := preview(it, base, kind, lib)
	if out.is_empty() or out.has("video_id"):
		return {}
	var cast: Array = []
	var people := {}
	var director: Array = []
	var writer: Array = []
	for p in B.arr(it.get("People", []), 60):
		var pp := B.dict(p)
		var n := B.text(pp.get("Name", ""), 80)
		if n == "":
			continue
		match str(pp.get("Type", "")):
			"Actor", "GuestStar":
				if cast.size() < MoviesScript.CAST_MAX:
					cast.append(n)
					people[MoviesScript.person_key(n)] = { "name": n, "photo": img(base, id_ok(pp.get("Id", "")), "Primary", pp.get("PrimaryImageTag", ""), 185),
						"character": B.text(pp.get("Role", ""), 80) }
			"Director":
				if director.size() < 4:
					director.append(n)
			"Writer":
				if writer.size() < 4:
					writer.append(n)
	var prog := {}
	var videos: Array = []
	var pre := prefix(kind)
	if out.type == "series" and episodes != null:
		for v in B.arr(B.dict(episodes).get("Items", []), 3000):
			var e := B.dict(v)
			var eid := id_ok(e.get("Id", ""))
			if eid == "" or str(e.get("Type", "Episode")) != "Episode":
				continue
			videos.append({ "id": pre + eid, "title": B.text(e.get("Name", "")), "season": B.num(e.get("ParentIndexNumber", 0)),
				"episode": B.num(e.get("IndexNumber", 0)), "released": B.text(e.get("PremiereDate", ""), 30).substr(0, 10),
				"thumbnail": img(base, eid, "Primary", B.dict(e.get("ImageTags", {})).get("Primary", ""), 640),
				"overview": B.text(e.get("Overview", ""), B.DESC_MAX), "available": true })
			_progress_of(e, pre + eid, prog)
		MoviesScript.sort_videos(videos)
	elif out.type == "movie":
		_progress_of(it, str(out.id), prog)
	var seasons: Array = []
	for v in videos:
		if not (int(v.season) in seasons):
			seasons.append(int(v.season))
	seasons.sort()
	if 0 in seasons:
		seasons.erase(0)
		seasons.append(0)
	var ids := B.dict(it.get("ProviderIds", {}))
	var countries := B.arr(it.get("ProductionLocations", []), 2)
	out.merge({
		"released": B.text(it.get("PremiereDate", ""), 30).substr(0, 10), "cast": cast, "people": people, "director": director,
		"writer": writer, "trailers": [], "links": [], "country": B.text(countries[0], 60) if not countries.is_empty() else "",
		"awards": "", "videos": videos, "seasons": seasons, "imdb_id": B.ident(ids.get("Imdb", ""), "alnum", 3, 16),
		"tmdb_id": B.ident(ids.get("Tmdb", ""), "digits", 1, 12), "default_video_id": str(out.id) if out.type == "movie" else "",
		"server_progress": prog,
	}, true)
	return out


static func _progress_of(it: Dictionary, vid: String, into: Dictionary) -> void:
	var ud := B.dict(it.get("UserData", {}))
	var pos := B.num(ud.get("PlaybackPositionTicks", 0)) / TICKS
	var seen := B.flag(ud.get("Played", false))
	if pos > 0.0 or seen:
		# Schon gesehen und erneut angefangen (Played und ein Stand): Der Stand zählt, wie bei Plex. Vorher fiel er
		# weg – der Titel galt dann weder als gesehen noch als angefangen.
		into[vid] = { "position": maxf(pos, 0.0), "duration": B.num(it.get("RunTimeTicks", 0)) / TICKS, "watched": seen and pos <= 0.0,
			"updated": B.iso_time(ud.get("LastPlayedDate", "")) }


## Fassungen (MediaSources) eines Titels zum Abspielen, direkt als Datei vom Server (Direct
## Play), im Format der Addon-Streams; externe Untertitel des Servers dazu.
static func parse_streams(d: Variant, base: String, kind: String, auth: Dictionary, label: String) -> Array:
	var it := B.dict(d)
	var id := id_ok(it.get("Id", ""))
	if id == "":
		return []
	var out: Array = []
	var sources := B.arr(it.get("MediaSources", []), 8)
	for i in sources.size():
		var ms := B.dict(sources[i])
		var msid := B.ident(ms.get("Id", ""), "token", 1, 80)
		if msid == "" or str(ms.get("Protocol", "File")) not in ["File", ""]:
			continue
		var q := 0
		var hdr := ""
		var vc := ""
		var audio := ""
		var subs: Array = []
		for s in B.arr(ms.get("MediaStreams", []), 80):
			var st := B.dict(s)
			match str(st.get("Type", "")):
				"Video":
					if q == 0:
						q = _quality(B.num(st.get("Height", 0)), B.num(st.get("Width", 0)))
						vc = B.text(st.get("Codec", ""), 12)
						var rt := B.text(st.get("VideoRangeType", st.get("VideoRange", "")), 20).to_upper()
						hdr = "DV" if rt.begins_with("DOVI") else ("HDR10+" if rt == "HDR10PLUS" else ("HDR10" if rt in ["HDR10", "HDR"] else ("HLG" if rt == "HLG" else "")))
				"Audio":
					if audio == "":
						audio = B.text(st.get("DisplayTitle", ""), 60)
				"Subtitle":
					if B.flag(st.get("IsExternal", false)):
						var fmt := _sub_format(B.text(st.get("Codec", ""), 12).to_lower())
						var idx := B.num(st.get("Index", -1), -1)
						if fmt != "" and idx >= 0:
							var lang := B.ident(st.get("Language", ""), "token", 2, 8)
							subs.append({ "id": "%s-sub:%s:%d" % [kind, msid, idx], "url": "%s/Videos/%s/%s/Subtitles/%d/Stream.%s" % [base, id, msid, idx, fmt],
								"lang": lang, "label": MoviesScript.lang_label(lang) + "  ·  " + B.text(st.get("DisplayTitle", "Untertitel"), 40) })
		var size := B.num(ms.get("Size", 0))
		var file := B.text(ms.get("Path", ""), 260).replace("\\", "/").get_file()
		var desc := PackedStringArray()
		for x in [B.text(ms.get("Container", ""), 10).to_upper(), audio, B.text(ms.get("Name", ""), 40) if sources.size() > 1 else ""]:
			if str(x) != "":
				desc.append(str(x))
		out.append({
			"id": "%s-src:%s" % [kind, msid], "name": "Direct Play", "title": file, "description": "  ·  ".join(desc),
			"addon_id": addon_id(kind), "addon_name": label, "url": "%s/Videos/%s/stream?static=true&mediaSourceId=%s" % [base, id, msid.uri_encode()],
			"headers": auth.duplicate(), "quality": q, "hdr": hdr, "codec": _codec(vc), "size_bytes": size, "size_text": MoviesScript.size_text(size),
			"is_p2p": false, "info_hash": "", "source": "server", "subtitles": subs, "filename": file, "cached": true,
			"binge_group": kind + "-direct", "order": i, "media_source": msid,
		})
	return out


static func _quality(h: int, w: int) -> int:
	if h >= 1600 or w >= 3200:
		return 2160
	if h >= 1000 or w >= 1800:
		return 1080
	if h >= 650 or w >= 1200:
		return 720
	return 480 if h > 0 else 0


static func _codec(c: String) -> String:
	match c.to_lower():
		"hevc", "h265": return "HEVC"
		"h264", "avc": return "AVC"
		"av1": return "AV1"
		"vp9": return "VP9"
	return ""


static func _sub_format(codec: String) -> String:
	match codec:
		"subrip", "srt": return "srt"
		"ass": return "ass"
		"ssa": return "ssa"
		"webvtt", "vtt": return "vtt"
	return ""


# --- Pfade ---------------------------------------------------------------------------------------

static func items_path(user_id: String, parent_id: String, start: int, size: int, sort := "SortName", genre := "", recursive := true) -> String:
	var order := "Descending" if sort in ["DateCreated", "DatePlayed", "PremiereDate"] else "Ascending"
	var p := "/Users/%s/Items?ParentId=%s&IncludeItemTypes=Movie,Series&SortBy=%s&SortOrder=%s&StartIndex=%d&Limit=%d&Fields=%s&EnableUserData=true" % [
		user_id, parent_id, sort, order, maxi(start, 0), clampi(size, 1, 200), FIELDS]
	if recursive:
		p += "&Recursive=true"
	return p + ("&Genres=" + genre.uri_encode() if genre != "" else "")


## Wiedergabe-Meldung (/Sessions/Playing, …/Progress, …/Stopped).
static func progress_body(item_id: String, msid: String, session: String, pos_s: float, paused := false) -> Dictionary:
	return { "ItemId": item_id, "MediaSourceId": msid, "PlaySessionId": session, "PositionTicks": int(maxf(pos_s, 0.0) * TICKS),
		"CanSeek": true, "IsPaused": paused, "IsMuted": false, "PlayMethod": "DirectPlay", "EventName": "TimeUpdate" }
