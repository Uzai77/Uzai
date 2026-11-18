extends RefCounted
## Eigener Hörverlauf für Spotify, nur auf diesem PC (Datei spotify_verlauf.json im Ordner des
## Profils, keine Telemetrie). Uzai merkt sich, was Spotify Connect als laufend meldet (Titel,
## Künstler, Album, Cover, Playlist bzw. Album, aus dem es lief) – so gibt es „Zuletzt gehört“,
## „Oft gehört“ und „Deine Playlists & Alben zuletzt“ auch dann, wenn Spotify Bibliothek und
## Mixe auf dem Weg der Spotify-App nicht herausgibt. Alles hier ist statisch und ohne Netz.
##
## Fremde Daten (Zustand von Spotify Connect) werden streng geprüft: nur Wörterbücher und Texte,
## Längen begrenzt, Steuer- und Richtungszeichen entfernt, URIs nur im Muster
## spotify:(track|album|playlist|artist|show|episode):<22 Zeichen>, Cover nur von Spotifys
## Bilder-Servern (i.scdn.co und Co., geladen wie jedes Cover über Media.url_texture).

const MAX := 500                      ## höchstens so viele Einträge (älteste fallen weg)
const SAME_PLAY_S := 600              ## derselbe Titel innerhalb von 10 Minuten: kein neuer Eintrag
const TEXT_MAX := 160
const NAME_MAX := 120
const KINDS := ["track", "album", "playlist", "artist", "show", "episode"]
const CONTEXT_KINDS := ["album", "playlist", "artist", "show"]
## Bilder-Server von Spotify, deren Cover Uzai lädt (Web-API, pathfinder, oEmbed – Mixe und
## „This is …“-Playlists haben eigene Server).
const ART_HOSTS := ["i.scdn.co", "mosaic.scdn.co", "image-cdn-ak.spotifycdn.com", "image-cdn-fa.spotifycdn.com", "pickasso.spotifycdn.com",
	"seed-mix-image.spotifycdn.com", "dailymix-images.scdn.co", "thisis-images.scdn.co", "newjams-images.scdn.co", "lineup-images.scdn.co",
	"charts-images.scdn.co", "mixed-media-images.spotifycdn.com", "blend-playlist-covers.spotifycdn.com", "misc.scdn.co", "t.scdn.co"]

## Beim Laden übersetzt und danach nur gelesen (vorher beim ersten Gebrauch – in zwei Fäden nicht sicher).
static var _re_uri := RegEx.create_from_string("^spotify:(track|album|playlist|artist|show|episode):[A-Za-z0-9]{22}\\z")
static var _re_art := RegEx.create_from_string("^https://([a-z0-9.-]{1,64})/[A-Za-z0-9/_.-]{1,200}\\z")
## Zeichen, die clean() entfernt. Die allermeisten Texte haben keins: Dann entfällt der Gang Zeichen für Zeichen
## (gemessen: Verlauf mit 500 Einträgen laden 22 ms, damit 8 ms).
static var _re_schmutz := RegEx.create_from_string("[\\x{00}-\\x{1F}\\x{7F}-\\x{9F}\\x{200B}-\\x{200F}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}\\x{FEFF}]")


static func _uri_re() -> RegEx:
	return _re_uri


## Spotify-URI im erlaubten Muster? kinds: nur diese Arten (leer = alle aus KINDS).
static func uri_ok(v: Variant, kinds: Array = []) -> bool:
	if not (v is String) or (v as String).length() > 40:
		return false
	if _uri_re().search(v) == null:
		return false
	return kinds.is_empty() or (v as String).get_slice(":", 1) in kinds


static func uri_kind(uri: String) -> String:
	return uri.get_slice(":", 1) if uri_ok(uri) else ""


## Cover-Adresse von Spotifys Bilder-Servern (https, bekannter Host, schlichter Pfad)? Ein Bild
## aus Spotify Connect („spotify:image:<40 hex>“) wird vorher zur Adresse bei i.scdn.co.
static func art_url(v: Variant) -> String:
	if not (v is String):
		return ""
	var s: String = v
	if s.begins_with("spotify:image:"):
		var hex := s.substr(14)
		if hex.length() == 40 and hex.is_valid_hex_number():
			return "https://i.scdn.co/image/" + hex.to_lower()
		return ""
	if s.length() > 300:
		return ""
	var m := _re_art.search(s)
	if m == null or not m.get_string(1) in ART_HOSTS or s.contains(".."):
		return ""
	return s


## Text aus fremden Daten: nur Zeichenketten, ohne Steuer- und Richtungszeichen, gekürzt.
static func clean(v: Variant, max_len := TEXT_MAX) -> String:
	if not (v is String):
		return ""
	var s: String = v
	if s.length() > max_len * 4:
		s = s.left(max_len * 4)
	var out := ""
	if _re_schmutz.search(s) == null:
		out = s
	else:
		for i in s.length():
			var c := s.unicode_at(i)
			if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) \
					or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
				out += " " if c in [9, 10, 13] else ""
				continue
			out += s[i]
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.left(max_len).strip_edges()


static func _d(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## Eintrag aus dem Zustand von Spotify Connect (Antwort von connect-state, wie Intern.cluster sie
## liest). {} wenn gerade nichts Gültiges spielt. extra: Titel/Künstler/Album aus der
## Mediensitzung von Windows, falls Spotify Connect nur die Kennung des Titels nennt.
static func from_cluster(raw: Variant, now_s: int, extra: Dictionary = {}) -> Dictionary:
	var cd := _d(raw)
	var ps := _d(cd.get("player_state"))
	# Nur ein echtes true zählt (ein Vergleich mit == bräche bei einem anderen Typ mit einem Skriptfehler ab).
	var spielt: Variant = ps.get("is_playing")
	var pausiert: Variant = ps.get("is_paused")
	if ps.is_empty() or not (spielt is bool and spielt) or (pausiert is bool and pausiert):
		return {}
	var tr := _d(ps.get("track"))
	var md := _d(tr.get("metadata"))
	var cm := _d(ps.get("context_metadata"))
	var art: Variant = md.get("image_xlarge_url", md.get("image_large_url", md.get("image_url", "")))
	var e := {
		"u": tr.get("uri", ""), "t": md.get("title", ""), "a": md.get("artist_name", ""), "al": md.get("album_title", ""),
		"alu": md.get("album_uri", ""), "aru": md.get("artist_uri", ""), "art": art,
		"c": ps.get("context_uri", ""), "cn": cm.get("context_description", md.get("context_description", "")),
		"ts": now_s,
	}
	if clean(e.t) == "" and not extra.is_empty():
		e.t = extra.get("title", "")
		e.a = extra.get("artist", "")
		e.al = extra.get("album", "")
	return entry(e)


## Eintrag aus „Läuft gerade“ (Music.now, Web-API mit eigener Spotify-App).
static func from_now(n: Dictionary, now_s: int) -> Dictionary:
	if not bool(n.get("playing", false)) or str(n.get("source", "")) == "windows":
		return {}
	return entry({ "u": n.get("uri", ""), "t": n.get("title", ""), "a": n.get("artist", ""), "al": n.get("album", ""),
		"art": n.get("art", ""), "c": n.get("context", ""), "cn": n.get("context_name", ""), "ts": now_s })


## Ein Eintrag streng geprüft (aus dem Netz oder aus der eigenen Datei). {} wenn er nicht taugt.
static func entry(v: Variant) -> Dictionary:
	var d := _d(v)
	var u: Variant = d.get("u")
	if not uri_ok(u, ["track", "episode"]):
		return {}
	var t := clean(d.get("t"))
	if t == "":
		return {}
	var c: Variant = d.get("c")
	var c_ok := uri_ok(c, CONTEXT_KINDS)
	var alu: Variant = d.get("alu")
	var aru: Variant = d.get("aru")
	var ts: Variant = d.get("ts")
	var e := {
		"u": str(u), "t": t, "a": clean(d.get("a")), "al": clean(d.get("al")),
		"alu": str(alu) if uri_ok(alu, ["album"]) else "", "aru": str(aru) if uri_ok(aru, ["artist"]) else "",
		"art": art_url(d.get("art")), "c": str(c) if c_ok else "", "cn": clean(d.get("cn"), NAME_MAX) if c_ok else "",
		"ts": int(ts) if (ts is int or ts is float) and float(ts) > 0.0 and float(ts) < 4.0e9 else 0,
	}
	# Den Namen des Kontexts kennt Spotify Connect nicht immer: beim Album ist es das Album, beim
	# Künstler der Künstler.
	if e.c != "" and e.cn == "":
		if e.c == e.alu and e.al != "":
			e.cn = e.al
		elif e.c == e.aru and e.a != "":
			e.cn = e.a
	return e


## Neuer Eintrag vorn (neueste zuerst). Derselbe Titel wie der neueste kurz danach (Pause,
## Gerätewechsel, mehrfaches Lesen) ergänzt nur fehlende Angaben. Höchstens max Einträge.
static func add(list: Array, e: Dictionary, max_n := MAX) -> Array:
	if e.is_empty():
		return list
	var out := list.duplicate()
	if not out.is_empty() and out[0] is Dictionary and str(out[0].get("u", "")) == str(e.u) \
			and int(e.ts) - int(out[0].get("ts", 0)) < SAME_PLAY_S:
		var head: Dictionary = (out[0] as Dictionary).duplicate()
		for k in ["art", "c", "cn", "al", "alu", "aru", "a"]:
			if str(head.get(k, "")) == "" and str(e.get(k, "")) != "":
				head[k] = e[k]
		out[0] = head
		return out
	out.push_front(e)
	if out.size() > max_n:
		out.resize(max_n)
	return out


## Verlauf aus der eigenen Datei (Inhalt schon als JSON gelesen): jeder Eintrag geprüft.
static func load_list(v: Variant) -> Array:
	var items: Variant = _d(v).get("items")
	var out: Array = []
	if not (items is Array):
		return out
	for it in (items as Array).slice(0, MAX):
		var e := entry(it)
		if not e.is_empty():
			out.append(e)
	return out


static func to_file(list: Array) -> Dictionary:
	return { "v": 1, "items": list.slice(0, MAX) }


## Ein Eintrag in Uzais Form eines Titels (wie Music.track_from).
static func as_track(e: Dictionary) -> Dictionary:
	var u := str(e.get("u", ""))
	return { "id": u.get_slice(":", 2), "uri": u, "title": str(e.get("t", "")), "artist": str(e.get("a", "")), "artists": [],
		"artist_id": str(e.get("aru", "")).get_slice(":", 2), "album": str(e.get("al", "")), "art": str(e.get("art", "")),
		"art_big": str(e.get("art", "")), "duration": 0, "explicit": false, "added": int(e.get("ts", 0)),
		"context": str(e.get("c", "")) }


## Zuletzt gehört: jeder Titel einmal, neueste zuerst.
static func recent(list: Array, n := 20) -> Array:
	var seen := {}
	var out: Array = []
	for e in list:
		var u := str(e.get("u", ""))
		if seen.has(u):
			continue
		seen[u] = true
		out.append(as_track(e))
		if out.size() >= n:
			break
	return out


## Oft gehört: Titel, die mindestens min_plays-mal liefen, die häufigsten zuerst (bei Gleichstand
## der zuletzt gehörte). Jeder Titel mit „plays“.
static func frequent(list: Array, n := 20, min_plays := 2) -> Array:
	var count := {}
	var first := {}
	var order: Array = []
	for i in list.size():
		var u := str(list[i].get("u", ""))
		if not count.has(u):
			count[u] = 0
			first[u] = i
			order.append(u)
		count[u] += 1
	var pick: Array = order.filter(func(u: String) -> bool: return int(count[u]) >= min_plays)
	pick.sort_custom(func(a: String, b: String) -> bool:
		if int(count[a]) != int(count[b]):
			return int(count[a]) > int(count[b])
		return int(first[a]) < int(first[b]))
	var out: Array = []
	for u in pick.slice(0, n):
		var t := as_track(list[int(first[u])])
		t["plays"] = int(count[u])
		out.append(t)
	return out


## Deine Playlists & Alben zuletzt (aus den Kontexten): jede einmal, neueste zuerst.
## { kind, id, uri, name, art, sub, ts } – kind wie bei Musik-Kacheln ("album", "playlist", "artist", "show").
static func contexts(list: Array, n := 12) -> Array:
	var seen := {}
	var out: Array = []
	for e in list:
		var c := str(e.get("c", ""))
		if c == "" or seen.has(c):
			continue
		seen[c] = true
		var kind := uri_kind(c)
		var nm := str(e.get("cn", ""))
		if nm == "":
			nm = { "album": str(e.get("al", "")), "artist": str(e.get("a", "")) }.get(kind, "")
		out.append({ "kind": kind, "id": c.get_slice(":", 2), "uri": c, "name": nm, "art": str(e.get("art", "")),
			"artist": str(e.get("a", "")) if kind == "album" else "", "last": str(e.get("t", "")), "ts": int(e.get("ts", 0)) })
		if out.size() >= n:
			break
	return out


## Der zuletzt gehörte Eintrag ({} wenn der Verlauf leer ist).
static func last(list: Array) -> Dictionary:
	return list[0] if not list.is_empty() and list[0] is Dictionary else {}
