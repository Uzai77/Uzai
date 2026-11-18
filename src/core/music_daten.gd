extends Node
## Musik, unterste Schicht: Antworten von Spotify lesen (Playlists, Alben, Titel, Suche, Künstler,
## Mixe, Neuerscheinungen) und die Daten der Vorführung (--demo). Nur statische Funktionen ohne
## Netz und ohne Zustand – darum offline prüfbar (tests/logic_musik.gd).
## Schichten des Autoloads Music (jede kennt nur die darunter): music_daten.gd → music_spotify.gd
## → music_listen.gd → music_fuer_dich.gd → music.gd.

## Farbtöne (0…1) für Kacheln ohne Bild: je Mix ein ruhiger, einfarbiger Verlauf.
const HUES := { "mix:top": 0.07, "mix:neu": 0.47, "mix:lange": 0.86, "mix:zuletzt": 0.58,
	"weekly": 0.66, "radar": 0.97, "repeat": 0.16, "liked": 0.95, "capsule": 0.12, "rewind": 0.8, "daylist": 0.36, "mehr": 0.62 }
const DAILY_HUES := [0.3, 0.53, 0.76, 0.1, 0.4, 0.9]
const ArtistCatalog := preload("res://src/core/artist_catalog.gd")
## Je Playlist gebraucht (Beschreibung säubern, Mix erkennen): einmal übersetzt.
static var _RX_HTML := RegEx.create_from_string("<[^>]*>")
static var _RX_DAILY := RegEx.create_from_string("^daily mix \\d+$")


# --- Antworten lesen -----------------------------------------------------------------------------

## Bild-URL aus einer Spotify-Bilderliste (0: groß, 1: mittel, sonst das kleinste vorhandene).
static func _img(imgs: Variant, idx: int) -> String:
	if not (imgs is Array) or (imgs as Array).is_empty():
		return ""
	var list: Array = imgs
	var im: Variant = list[mini(idx, list.size() - 1)]
	return str((im as Dictionary).get("url", "")) if im is Dictionary and (im as Dictionary).get("url") != null else ""


## Spotify-Beschreibungen enthalten HTML (Links, &amp;): als schlichter Text.
static func clean_text(s: String) -> String:
	var out := _RX_HTML.sub(s, "", true)
	for pair in [["&amp;", "&"], ["&#x27;", "'"], ["&#39;", "'"], ["&quot;", "\""], ["&lt;", "<"], ["&gt;", ">"], ["&nbsp;", " "]]:
		out = out.replace(pair[0], pair[1])
	return out.strip_edges()


## Eine Playlist aus der Spotify-API in Uzais Form. Liest „items“ (neu) und „tracks“ (alt).
## mine: gehört dir oder du arbeitest mit – nur dann gibt Spotify die Titel heraus.
static func playlist_from(p: Variant, me_id := "") -> Dictionary:
	if not (p is Dictionary) or str((p as Dictionary).get("uri", "")) == "":
		return {}
	var d: Dictionary = p
	var tr: Variant = d.get("items") if d.get("items") is Dictionary else d.get("tracks")
	var owner: Dictionary = d.get("owner", {}) if d.get("owner") is Dictionary else {}
	var oid := str(owner.get("id", "")) if owner.get("id") != null else ""
	var collab := bool(d.get("collaborative", false)) if d.get("collaborative") != null else false
	return {
		"kind": "playlist", "id": str(d.get("id", "")), "uri": str(d.get("uri", "")), "name": str(d.get("name", "")),
		"count": int((tr as Dictionary).get("total", 0)) if tr is Dictionary and (tr as Dictionary).get("total") != null else 0,
		"art": _img(d.get("images"), 0),
		"owner": str(owner.get("display_name", "")) if owner.get("display_name") != null else "",
		"owner_id": oid, "collab": collab, "mine": me_id == "" or oid == me_id or collab,
		"desc": clean_text(str(d.get("description", ""))) if d.get("description") != null else "",
	}


## Ein Album (auch Single) aus der Spotify-API in Uzais Form.
static func album_from(a: Variant) -> Dictionary:
	if not (a is Dictionary) or str((a as Dictionary).get("uri", "")) == "":
		return {}
	var d: Dictionary = a
	var artists := PackedStringArray()
	for x in (d.get("artists", []) if d.get("artists") is Array else []):
		if x is Dictionary:
			artists.append(str(x.get("name", "")))
	return {
		"kind": "album", "id": str(d.get("id", "")), "uri": str(d.get("uri", "")), "name": str(d.get("name", "")),
		"artist": ", ".join(artists), "art": _img(d.get("images"), 1), "art_big": _img(d.get("images"), 0),
		"date": str(d.get("release_date", "")) if d.get("release_date") != null else "",
		"precision": str(d.get("release_date_precision", "day")) if d.get("release_date_precision") != null else "day",
		"type": str(d.get("album_type", "album")) if d.get("album_type") != null else "album",
		"count": int(d.get("total_tracks", 0)) if d.get("total_tracks") != null else 0,
	}


## Ein Titel aus der Spotify-API in Uzais Form. Nimmt das mittlere Albumbild (300 px).
static func track_from(t: Variant, added := 0) -> Dictionary:
	if not (t is Dictionary) or str(t.get("uri", "")) == "" or str(t.get("type", "track")) != "track":
		return {}
	var artists := PackedStringArray()
	var people: Array = []
	for a in (t.get("artists", []) if t.get("artists") is Array else []):
		if a is Dictionary:
			artists.append(str(a.get("name", "")))
			people.append({ "id": str(a.get("id", "")) if a.get("id") != null else "", "name": str(a.get("name", "")) })
	var album: Dictionary = t.get("album", {}) if t.get("album") is Dictionary else {}
	var imgs: Variant = album.get("images")
	return {
		"id": str(t.get("id", "")) if t.get("id") != null else "", "uri": str(t.uri), "title": str(t.get("name", "")),
		"artist": ", ".join(artists), "artists": people, "artist_id": str(people[0].id) if not people.is_empty() else "",
		"album": str(album.get("name", "")), "art": _img(imgs, 1),
		"art_big": _img(imgs, 0),
		"duration": int(t.get("duration_ms", 0)) if t.get("duration_ms") != null else 0,
		"explicit": bool(t.get("explicit", false)) if t.get("explicit") != null else false, "added": added,
	}


## Einträge einer Liste: neu { item: {...} }, alt { track: {...} }, oder der Titel selbst (Top-Titel).
static func tracks_from_items(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if not (it is Dictionary):
			continue
		var d: Dictionary = it
		var inner: Variant = d.get("item")
		if not (inner is Dictionary):
			inner = d.get("track")
		if not (inner is Dictionary) and not d.has("track") and not d.has("item"):
			inner = d
		var t := track_from(inner)
		if not t.is_empty():
			out.append(t)
	return out


static func restricted_text() -> String:
	return "Spotify gibt eigenen Apps die Titel nur bei Playlists heraus, die dir gehören oder an denen du mitarbeitest."


## Seitenadresse aus context-resolve als volle Adresse: „hm://…“ und „/…“ auf spclient, sonst wie sie ist.
static func spclient_url(base: String, u: String) -> String:
	if u == "" or u.begins_with("http"):
		return u
	if u.begins_with("hm://"):
		return base + "/" + u.substr(5)
	return base + ("" if u.begins_with("/") else "/") + u


## Antwort von context-resolve: { tracks: [{ uri, id, title, artist, album, art }], next }.
## Seiten ohne Titel nennen nur eine Adresse (page_url): die erste davon kommt als next zurück.
static func context_tracks(d: Variant) -> Dictionary:
	var out := { "tracks": [], "next": "" }
	if not (d is Dictionary):
		return out
	for pg in ((d as Dictionary).get("pages", []) if (d as Dictionary).get("pages") is Array else []):
		if not (pg is Dictionary):
			continue
		var tracks: Variant = (pg as Dictionary).get("tracks")
		if not (tracks is Array) or (tracks as Array).is_empty():
			var pu := str((pg as Dictionary).get("page_url", "")) if (pg as Dictionary).get("page_url") != null else ""
			if pu != "" and str(out.next) == "":
				out.next = pu
			continue
		for t in tracks:
			var uri := str(t.get("uri", "")) if t is Dictionary else ""
			if not uri.begins_with("spotify:track:"):
				continue
			var m: Dictionary = t.get("metadata", {}) if t.get("metadata") is Dictionary else {}
			out.tracks.append({ "id": uri.get_slice(":", 2), "uri": uri, "title": str(m.get("title", "")), "artist": str(m.get("artist_name", "")),
				"artists": [], "artist_id": "", "album": str(m.get("album_title", "")), "art": str(m.get("image_url", "")),
					"art_big": str(m.get("image_large_url", m.get("image_url", ""))),
				"duration": int(str(m.get("duration", "0"))), "explicit": false, "added": 0 })
		var nx := str((pg as Dictionary).get("next_page_url", "")) if (pg as Dictionary).get("next_page_url") != null else ""
		if nx != "":
			out.next = nx
	return out


## Antwort von /search in Uzais Form: { tracks, artists, albums, playlists } (leere Treffer –
## Spotify schickt bei Playlists oft null – fallen weg). Öffentlich für die Tests.
static func parse_search(d: Variant, me_id := "") -> Dictionary:
	var out := { "tracks": [], "artists": [], "albums": [], "playlists": [] }
	if not (d is Dictionary):
		return out
	for t in _items_of(d, "tracks"):
		var tr := track_from(t)
		if not tr.is_empty():
			out.tracks.append(tr)
	for a in _items_of(d, "artists"):
		var ar := artist_from(a)
		if not ar.is_empty():
			out.artists.append(ar)
	for a in _items_of(d, "albums"):
		var al := album_from(a)
		if not al.is_empty():
			out.albums.append(al)
	for p in _items_of(d, "playlists"):
		var pl := playlist_from(p, me_id)
		if not pl.is_empty():
			out.playlists.append(pl)
	return out


static func _items_of(d: Dictionary, key: String) -> Array:
	var part: Variant = d.get(key)
	if part is Dictionary and (part as Dictionary).get("items") is Array:
		return (part as Dictionary).items
	return []


# --- Künstler (auch für die Vorführung) ----------------------------------------------------------

## Ein Künstler aus der Spotify-API in Uzais Form ({} ohne ID).
static func artist_from(a: Variant) -> Dictionary:
	if not (a is Dictionary) or str((a as Dictionary).get("id", "")) in ["", "<null>"]:
		return {}
	var d: Dictionary = a
	var fol: Variant = d.get("followers")
	var genres: Array = []
	for g in (d.get("genres", []) if d.get("genres") is Array else []):
		if str(g) != "":
			genres.append(str(g))
	var aid := str(d.id)
	return {
		"kind": "artist", "id": aid, "uri": str(d.get("uri", "")) if str(d.get("uri", "")) not in ["", "<null>"] else "spotify:artist:" + aid,
		"name": str(d.get("name", "")), "art": _img(d.get("images"), 1), "art_big": _img(d.get("images"), 0),
		"followers": int((fol as Dictionary).get("total", 0)) if fol is Dictionary and (fol as Dictionary).get("total") != null else -1,
		"genres": genres,
	}


## Veröffentlichungen eines Künstlers, aufgeteilt in Alben und Singles/EPs, neueste zuerst, ohne
## doppelte Fassungen (Spotify führt dasselbe Album oft mehrfach). Öffentlich für die Tests.
static func split_releases(items: Array) -> Dictionary:
	var albums: Array = []
	var singles: Array = []
	var seen := {}
	for it in items:
		var al: Dictionary = it if it is Dictionary and str((it as Dictionary).get("kind", "")) == "album" else album_from(it)
		if al.is_empty():
			continue
		var grp := str((it as Dictionary).get("album_group", "")) if it is Dictionary and (it as Dictionary).get("album_group") != null else ""
		if grp == "appears_on":
			continue
		var single := str(al.get("type", "album")) == "single"
		var key := ("s:" if single else "a:") + str(al.get("name", "")).to_lower().strip_edges()
		if seen.has(key):
			continue
		seen[key] = true
		(singles if single else albums).append(al)
	var newest := func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("date", "")) > str(b.get("date", ""))
	albums.sort_custom(newest)
	singles.sort_custom(newest)
	return { "albums": albums, "singles": singles }


## Titel aus der Suche, an denen dieser Künstler beteiligt ist (Ersatz für die Top-Titel).
static func tracks_of_artist(tracks: Array, artist_id: String, artist_name: String) -> Array:
	var out: Array = []
	var nm := artist_name.to_lower().strip_edges()
	for t in tracks:
		if not (t is Dictionary):
			continue
		var hit := false
		for p in (t as Dictionary).get("artists", []):
			if p is Dictionary \
					and ((artist_id != "" and str(p.get("id", "")) == artist_id) or (str(p.get("id", "")) == "" and nm != "" and str(p.get("name", "")).to_lower() == nm)):
				hit = true
		if hit:
			out.append(t)
	return out


## Vorführung: Spielt ein Titel aus „Alle Titel“, kennt die Vorführung ihn danach (play_list).
static var _demo_more := {}


static func demo_remember(t: Dictionary) -> void:
	_demo_more[str(t.get("uri", ""))] = t


## Vorführung: alle Veröffentlichungen eines Künstlers für „Alle Titel“, neueste zuerst (wie
## /artists/{id}/albums, mit Gastauftritt auf Wunsch).
static func demo_artist_releases(nm: String, guest := false) -> Array:
	var page := demo_artist(nm)
	var rel: Array = (page.albums as Array) + (page.singles as Array)
	if guest:
		rel.append({ "kind": "album", "id": "demogast%d" % (absi(nm.hash()) % 1000), "uri": "spotify:album:demogast%d" % (absi(nm.hash()) % 1000),
			"name": "Spielemusik-Gala 2023 – Live", "artist": "Verschiedene", "art": "", "art_big": "", "date": "2023-08-25", "precision": "day",
			"type": "compilation", "count": 6, "group": "appears_on" })
	return ArtistCatalog.parse_releases(rel)


## Vorführung: Titel einer Veröffentlichung für „Alle Titel“ (verschiedene Namen je Album; „Best
## of“ und Remaster wiederholen ältere Titel, damit man das Zusammenfassen sieht).
static func demo_release_items(al: Dictionary, nm: String) -> Array:
	var adj := ["Leises", "Fernes", "Altes", "Letztes", "Kaltes", "Goldenes", "Stilles", "Erstes", "Weites"]
	var noun := ["Lied", "Licht", "Echo", "Feuer", "Meer", "Tor", "Land", "Herz", "Spiel", "Ufer"]
	var pool := func(k: int) -> String: return "%s %s" % [adj[k % adj.size()], noun[int(k / float(adj.size())) % noun.size()]]
	var name_s := str(al.get("name", ""))
	var low := name_s.to_lower()
	var n := clampi(int(al.get("count", 6)), 1, 14)
	var titles: Array = []
	var start := absi(str(al.get("id", "")).hash()) % 9 * 9
	if low.contains("klavier"):
		for i in n:
			titles.append("Klavierstück Nr. %d" % (i + 1))
	elif low.contains("best of"):
		# Ältere Titel noch einmal (gleiche Länge): bleiben nur in ihrer ersten Fassung.
		for i in n:
			titles.append("Klavierstück Nr. %d" % (i + 1) if i % 3 == 0 else pool.call(i * 5))
	elif low.contains("remaster"):
		for i in n:
			titles.append("Klavierstück Nr. %d - Remastered 2025" % (i + 1))
	elif low.contains("live"):
		for i in n:
			titles.append(pool.call(start + i) + " (Live)")
	elif low.contains("frühe"):
		for i in n:
			titles.append(pool.call(i * 5))
	elif str(al.get("type", "")) == "single":
		titles.append(name_s.get_slice(" (", 0))
		if n > 1:
			titles.append(name_s.get_slice(" (", 0) + " (Instrumental)")
	else:
		for t in demo_tracks() + _demo_extra_tracks():
			if str(t.artist) == nm and name_s.begins_with(str(t.album)):
				titles.append(str(t.title))
		for i in n - titles.size():
			titles.append(pool.call(start + i))
	var out: Array = []
	var aid := str(al.get("id", "x"))
	for i in titles.size():
		var title: String = titles[i]
		var base := title.get_slice(" - Remastered", 0)
		var t := { "id": "%s_a%d" % [aid, i], "uri": "spotify:track:%s_a%d" % [aid, i], "title": title, "artist": nm,
			"artists": [{ "id": "demoart:" + nm, "name": nm }], "album": name_s, "art": str(al.get("art", "")), "art_big": "",
			"duration": 95000 + base.md5_text().substr(0, 6).hex_to_int() % 200000, "explicit": false, "added": 0 }
		for k in demo_tracks() + _demo_extra_tracks():
			if str(k.title) == title and str(k.artist) == nm:
				t["id"] = str(k.id)
				t["uri"] = str(k.uri)
				t["duration"] = int(k.duration)
		if str(al.get("group", "")) == "appears_on" and i % 3 != 0:
			# Sampler: die meisten Titel sind von anderen.
			t["artist"] = "Gastorchester"
			t["artists"] = [{ "id": "demogast", "name": "Gastorchester" }]
		out.append(t)
	return out


static func _demo_artist_info(nm: String) -> Dictionary:
	return { "kind": "artist", "id": "demoart:" + nm, "uri": "spotify:artist:demo", "name": nm, "art": "", "art_big": "",
		"followers": 40000 + absi(nm.hash()) % 900000, "genres": ["Videospielmusik", "Soundtrack"] }


## Vorführung: eine Künstlerseite aus den Beispieldaten, aufgefüllt mit erfundenen Alben.
static func demo_artist(nm: String) -> Dictionary:
	var all: Array = demo_tracks() + _demo_extra_tracks()
	var top: Array = all.filter(func(t): return str(t.artist) == nm)
	var rel: Array = (demo_albums() + _demo_saved_albums()).filter(func(a): return str(a.artist) == nm)
	var extra := [["%s – Best of", "album", "2024-11-08", 18], ["Live in Tokio", "album", "2022-03-18", 14], ["Klavierstücke", "album", "2019-06-21", 12],
		["Nachtflug", "single", "2026-09-26", 1], ["Morgenrot (Orchesterfassung)", "single", "2025-05-02", 2],
		["Klavierstücke (Remastered)", "album", "2025-01-17", 12], ["Erste Schritte", "album", "2014-10-03", 10], ["Frühe Aufnahmen", "single", "2016-04-08", 4]]
	for i in extra.size():
		var e: Array = extra[i]
		var title := str(e[0]) % nm if str(e[0]).contains("%s") else str(e[0])
		rel.append({ "kind": "album", "id": "demoart%d_%d" % [absi(nm.hash()) % 1000, i], "uri": "spotify:album:demoart%d_%d" % [absi(nm.hash()) % 1000, i],
			"name": title, "artist": nm, "art": "", "art_big": "", "date": e[2], "precision": "day", "type": e[1], "count": e[3] })
	var split := split_releases(rel)
	var seen := {}
	for t in top:
		seen[str(t.title)] = true
	for al in split.albums + split.singles:
		for t in demo_album_tracks(al):
			if top.size() < 8 and not seen.has(str(t.title)):
				seen[str(t.title)] = true
				top.append(t)
	return { "ok": true, "artist": _demo_artist_info(nm), "top": top, "albums": split.albums, "singles": split.singles, "top_from": "top", "error": "" }


# --- Mixe und Neuerscheinungen -------------------------------------------------------------------

## Alle Playlists irgendwo in einer Antwort (Kategorie: playlists.items, made-for-x: verschachtelte
## Ansichten mit content.items, /me/playlists: items). Spotify ändert die Form der internen Ansichten
## öfter; darum wird alles durchsucht, was nach Playlist aussieht.
static func collect_playlists(d: Variant, depth := 0) -> Array:
	var out: Array = []
	if depth > 6:
		return out
	if d is Dictionary:
		var dd: Dictionary = d
		if str(dd.get("uri", "")).begins_with("spotify:playlist:") and dd.get("name") != null:
			out.append(dd)
			return out
		for k in dd.keys():
			if dd[k] is Dictionary or dd[k] is Array:
				out.append_array(collect_playlists(dd[k], depth + 1))
	elif d is Array:
		for x in d:
			out.append_array(collect_playlists(x, depth + 1))
	return out


## Welcher Mix von Spotify ist das? weekly, radar, repeat, daily, capsule, rewind, daylist oder "".
static func spotify_mix_kind(name: String) -> String:
	var n := name.strip_edges().to_lower()
	if n in ["discover weekly", "dein mix der woche", "mix der woche"]:
		return "weekly"
	if n == "release radar":
		return "radar"
	if n in ["on repeat", "in dauerschleife"]:
		return "repeat"
	if n in ["time capsule", "deine zeitkapsel", "zeitkapsel", "your time capsule"]:
		return "capsule"
	if n == "repeat rewind":
		return "rewind"
	if n == "daylist" or n.begins_with("daylist "):
		return "daylist"
	if _RX_DAILY.search(n) != null:
		return "daily"
	return ""


## Aus Treffern die echten Mixe von Spotify (Besitzer „spotify“), je Art einer, sortiert. Was aus
## „Für dich gemacht“ kommt (mfy), zählt auch ohne bekannten Namen (etwa „Chill Mix“) – höchstens 16.
static func pick_spotify_mixes(lists: Array) -> Array:
	var order := { "weekly": 0, "radar": 1, "repeat": 2, "daily": 3, "capsule": 4, "rewind": 5, "daylist": 6, "mehr": 7 }
	var sub := { "weekly": "Jeden Montag neu", "radar": "Jeden Freitag neu", "repeat": "Was du gerade oft hörst", "daily": "Jeden Tag neu",
		"capsule": "Deine Lieblinge von damals", "rewind": "Früher oft gehört", "daylist": "Passt zur Tageszeit", "mehr": "Für dich gemacht" }
	var seen := {}
	var out: Array = []
	for p in lists:
		if not (p is Dictionary) or str(p.get("owner_id", "")) != "spotify" or out.size() >= 16:
			continue
		var kind := spotify_mix_kind(str(p.get("name", "")))
		if kind == "" and bool(p.get("mfy", false)):
			kind = "mehr"
		if kind == "":
			continue
		var key := str(p.get("name", "")).to_lower() if kind in ["daily", "mehr"] else kind
		if seen.has(key) or seen.has(str(p.get("id", ""))):
			continue
		seen[key] = true
		seen[str(p.get("id", ""))] = true
		var m: Dictionary = (p as Dictionary).duplicate()
		m["kind"] = "spotify_mix"
		m["mix"] = kind
		m["sub"] = sub[kind]
		var num := int(str(p.get("name", "")).get_slice(" ", 2)) if kind == "daily" else 0
		m["hue"] = DAILY_HUES[(num - 1) % DAILY_HUES.size()] if kind == "daily" and num > 0 else float(HUES.get(kind, 0.6))
		m["order"] = int(order[kind]) * 10 + (num if kind == "daily" else out.size() if kind == "mehr" else 0)
		out.append(m)
	out.sort_custom(func(a, b): return int(a.order) < int(b.order))
	return out


## Erscheinungsdatum als Unix-Zeit (Tag oder Monat; nur ein Jahr ist zu ungenau: 0).
static func release_unix(date: String, precision := "day") -> int:
	var p := date.split("-")
	if p.size() < 2 or precision == "year":
		return 0
	var y := int(p[0])
	var m := int(p[1])
	var d := int(p[2]) if p.size() > 2 else 1
	if y < 1900 or m < 1 or m > 12:
		return 0
	return int(Time.get_unix_time_from_datetime_dict({ "year": y, "month": m, "day": clampi(d, 1, 31), "hour": 12, "minute": 0, "second": 0 }))


## Neue Veröffentlichungen: höchstens days Tage alt, neueste zuerst, jedes Werk nur einmal
## (Single und gleichnamiges Album zählen einmal).
static func fresh_releases(albums: Array, now_unix: int, days := 42) -> Array:
	var cands: Array = []
	for a in albums:
		if not (a is Dictionary):
			continue
		var t := release_unix(str(a.get("date", "")), str(a.get("precision", "day")))
		if t <= 0 or t > now_unix + 2 * 86400 or now_unix - t > days * 86400:
			continue
		var c: Dictionary = (a as Dictionary).duplicate()
		c["released"] = t
		cands.append(c)
	cands.sort_custom(func(x, y): return int(x.released) > int(y.released))
	var seen := {}
	var out: Array = []
	for c in cands:
		var key := (str(c.get("name", "")) + "|" + str(c.get("artist", ""))).to_lower()
		if seen.has(key) or seen.has(str(c.get("id", ""))):
			continue
		seen[key] = true
		seen[str(c.get("id", ""))] = true
		out.append(c)
	return out


## Früher oft gehört, zuletzt kaum: über Jahre meistgehört, aber nicht in den letzten Wochen.
static func long_unheard(long_list: Array, short_list: Array, recent: Array, limit := 50) -> Array:
	var skip := {}
	for t in short_list + recent:
		if t is Dictionary:
			skip[str(t.get("id", ""))] = true
	var out: Array = []
	for t in long_list:
		if t is Dictionary and not skip.has(str(t.get("id", ""))):
			out.append(t)
			if out.size() >= limit:
				break
	return out


## Bis zu n verschiedene Albumbilder (für die Kachel eines Mixes).
static func arts_of(list: Array, n := 4) -> Array:
	var out: Array = []
	for t in list:
		var a := str(t.get("art", "")) if t is Dictionary else ""
		if a != "" and not out.has(a):
			out.append(a)
			if out.size() >= n:
				break
	return out


static func plural_text(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


# --- Vorführung (--demo) ----------------------------------------------------------

## Alle Beispieltitel nach URI (Listen, Alben, Mixe).
static func _demo_known() -> Dictionary:
	var out := _demo_more.duplicate()
	for t in demo_tracks() + _demo_extra_tracks():
		out[str(t.uri)] = t
	for a in demo_albums() + _demo_saved_albums():
		for t in demo_album_tracks(a):
			out[str(t.uri)] = t
	return out


static func demo_tracks() -> Array:
	var names := [["To Zanarkand", "Nobuo Uematsu", "Final Fantasy X", 186000], ["Gerudo Valley", "Koji Kondo", "Ocarina of Time", 132000],
		["Snake Eater", "Cynthia Harrell", "Metal Gear Solid 3", 245000], ["Dearly Beloved", "Yoko Shimomura", "Kingdom Hearts", 154000],
		["Bloody Tears", "Konami Kukeiha Club", "Castlevania II", 121000], ["Green Hill Zone", "Masato Nakamura", "Sonic the Hedgehog", 158000],
		["Aquatic Ambience", "David Wise", "Donkey Kong Country", 236000], ["One-Winged Angel", "Nobuo Uematsu", "Final Fantasy VII", 437000],
		["Sanctuary Guardian", "Toby Fox", "Undertale", 182000], ["Still Alive", "Ellen McLain", "Portal", 176000]]
	var out: Array = []
	for i in names.size():
		var n: Array = names[i]
		out.append(
				{ "id": "demo%d" % i, "uri": "spotify:track:demo%d" % i, "title": n[0], "artist": n[1], "album": n[2], "art": "", "art_big": "", "duration": n[3],
				"explicit": false, "added": 0 })
	return out


## Weitere Beispieltitel (Top-Titel und „Lange nicht gehört“ sollen sich unterscheiden).
static func _demo_extra_tracks() -> Array:
	var names := [["Megalovania", "Toby Fox", "Undertale", 156000], ["Resurrections", "Lena Raine", "Celeste", 539000],
		["Hornet", "Christopher Larkin", "Hollow Knight", 119000], ["Light of Nibel", "Gareth Coker", "Ori and the Blind Forest", 182000],
		["Apotheosis", "Austin Wintory", "Journey", 212000], ["Baba Yetu", "Christopher Tin", "Civilization IV", 211000],
		["Zelda's Lullaby", "Koji Kondo", "Ocarina of Time", 98000], ["Bad Apple!!", "ZUN", "Lotus Land Story", 219000]]
	var out: Array = []
	for i in names.size():
		var n: Array = names[i]
		out.append(
				{ "id": "demox%d" % i, "uri": "spotify:track:demox%d" % i, "title": n[0], "artist": n[1], "album": n[2], "art": "", "art_big": "", "duration": n[3],
				"explicit": false, "added": 0 })
	return out


static func demo_albums() -> Array:
	var now_unix := int(Time.get_unix_time_from_system())
	var list := [["Hades II – Original Soundtrack", "Darren Korb", "album", 3, 24], ["Astro Bot – Original Soundtrack", "Kenneth C M Young", "album", 9, 31],
		["Echoes of Wisdom", "Koji Kondo", "single", 12, 2], ["Silksong Suite", "Christopher Larkin", "single", 17, 1],
		["Clair Obscur: Expedition 33", "Lorien Testard", "album", 26, 40], ["Neon Nights", "Masayoshi Soken", "single", 33, 1]]
	var out: Array = []
	for i in list.size():
		var a: Array = list[i]
		var d := Time.get_datetime_dict_from_unix_time(now_unix - int(a[3]) * 86400)
		out.append({ "kind": "album", "id": "demoalb%d" % i, "uri": "spotify:album:demoalb%d" % i, "name": a[0], "artist": a[1], "art": "", "art_big": "",
			"date": "%04d-%02d-%02d" % [d.year, d.month, d.day], "precision": "day", "type": a[2], "count": a[4] })
	return out


static func _demo_saved_albums() -> Array:
	var list := [["Undertale Soundtrack", "Toby Fox", 101], ["Celeste Original Soundtrack", "Lena Raine", 21], ["Hollow Knight", "Christopher Larkin", 27],
		["Final Fantasy X Original Soundtrack", "Nobuo Uematsu", 91], ["Ori and the Blind Forest", "Gareth Coker", 32], ["Journey", "Austin Wintory", 18]]
	var out: Array = []
	for i in list.size():
		var a: Array = list[i]
		out.append({ "kind": "album", "id": "demosav%d" % i, "uri": "spotify:album:demosav%d" % i, "name": a[0], "artist": a[1], "art": "", "art_big": "",
			"date": "", "precision": "year", "type": "album", "count": a[2] })
	return out


## Titel eines Beispielalbums (fünf bis acht Titel mit dem Namen des Albums).
static func demo_album_tracks(album: Dictionary) -> Array:
	var base := ["Prolog", "Aufbruch", "Unter Sternen", "Das Lied der Stadt", "Sturm", "Stille Wasser", "Heimkehr", "Epilog"]
	var n := 5 + (str(album.get("id", "")).hash() % 4 + 4) % 4
	var out: Array = []
	for i in n:
		var aid := str(album.get("id", "x"))
		out.append({ "id": "%s_%d" % [aid, i], "uri": "spotify:track:%s_%d" % [aid, i], "title": base[i % base.size()], "artist": str(album.get("artist", "")),
			"album": str(album.get("name", "")), "art": str(album.get("art", "")), "art_big": "", "duration": 150000 + i * 23000, "explicit": false, "added": 0 })
	return out
