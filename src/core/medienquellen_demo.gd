extends RefCounted
## Demo-Daten der Filme-Quellen (Start mit --demo): ein Plex-Server „Wohnzimmer“ und ein
## Jellyfin-Server „Keller-Server“ mit ausgedachten Titeln. Die Daten sind nachgebaute Antworten
## im Format der echten Server und laufen durch dieselben Parser wie im Betrieb – so zeigt die
## Demo genau, was echte Server ergäben. Bilder sind selbst gemalte Landschaften (keine Bilder
## von Diensten), Adressen „demo://…“ führen nirgendwohin.

const Arbeit := preload("res://src/core/arbeit.gd")
const B := preload("res://src/core/medienquellen_basis.gd")
const Plex := preload("res://src/core/medienquellen_plex.gd")
const Jf := preload("res://src/core/medienquellen_jellyfin.gd")
const MovieDemo := preload("res://src/core/movies_demo.gd")

const PLEX := "demo://plex"
const JF := "demo://jellyfin"

## Plex: [Nummer, Titel, Jahr, Freigabe, Genres, Minuten, Bibliothek, Beschreibung]
const PLEX_MOVIES := [
	[101, "Leuchtturmwärter", 2023, "de/12", ["Drama"], 118, "1",
		"Ein Mann übernimmt den letzten bemannten Leuchtturm der Nordsee – und findet im Logbuch die Spur seines Vaters."],
	[102, "Glas und Stein", 2024, "de/12", ["Krimi", "Thriller"], 110, "1",
		"Eine Gutachterin soll ein gestohlenes Fenster aus einer Kathedrale finden. Der Dieb kennt sie besser als gedacht."],
	[103, "Spätsommer", 2022, "de/6", ["Komödie", "Romantik"], 97, "1",
		"Drei Schwestern erben ein Ferienhaus am See und müssen es gemeinsam verkaufen. Eigentlich."],
	[104, "Die Uhrmacherin", 2021, "de/12", ["Historie", "Drama"], 126, "1", "Genf, 1890: Eine junge Frau baut heimlich die genaueste Uhr der Stadt."],
	[105, "Signal 7", 2025, "de/16", ["Science-Fiction", "Thriller"], 105, "1",
		"Ein Radioteleskop empfängt jede Nacht um 3:07 Uhr dasselbe Signal. Bis es antwortet."],
	[106, "Dachboden", 2024, "de/18", ["Horror"], 92, "1", "Was oben liegt, sollte oben bleiben."],
	[301, "Der kleine Drache Funke", 2023, "de/0", ["Animation", "Familie"], 81, "3",
		"Funke kann kein Feuer speien – nur Seifenblasen. Genau die braucht das Tal jetzt."],
	[302, "Pinguin-Post", 2022, "de/0", ["Animation", "Abenteuer"], 76, "3",
		"Ein Pinguin liefert Briefe quer über das Eis – und verliert ausgerechnet den wichtigsten."],
	[303, "Mondfahrt", 2024, "", ["Abenteuer"], 88, "3", "Zwei Geschwister bauen im Garten eine Rakete. Die Nachbarn halten es für einen Scherz."],
	[304, "Robo und Rübe", 2025, "de/6", ["Familie", "Komödie"], 84, "3", "Ein Gartenroboter und ein Hase werden die unwahrscheinlichsten Freunde."],
]
## Plex-Serien: [Nummer, Titel, Jahr, Freigabe, Genres, Folgen je Staffel, Beschreibung]
const PLEX_SHOWS := [
	[201, "Kanalarbeit", 2022, "de/12", ["Krimi", "Drama"], [6, 6], "Zwei Kommissare ermitteln in den Schleusen und Häfen einer Stadt am Wasser."],
	[202, "Polarnacht", 2024, "de/16", ["Thriller", "Mystery"], [8],
		"Eine Forschungsstation, sechs Monate Dunkelheit und ein Funkspruch, den es nicht geben dürfte."],
	[203, "Werkstatt Ahoi", 2021, "de/0", ["Familie", "Dokumentation"], [10, 10], "Ein Bootsbauer zeigt Kindern, wie aus Holz ein Schiff wird."],
]
## Jellyfin: [Kennung, Titel, Typ, Jahr, Freigabe, Genres, Bibliothek, Beschreibung]
const JF_ITEMS := [
	["a10000000000000000000000000000a1", "Nachtfalter", "Movie", 2023, "FSK-16", ["Thriller"], "f1",
		"Ein Taxifahrer, eine Nacht, zwölf Fahrgäste – und einer davon kommt nicht an."],
	["a10000000000000000000000000000a2", "Salz", "Movie", 2022, "FSK-12", ["Drama"], "f1",
		"Eine Salzsiederei an der Küste, drei Generationen und ein Geheimnis im Keller."],
	["a10000000000000000000000000000a3", "Morgenrot", "Movie", 2025, "PG-13", ["Abenteuer"], "f1",
		"Eine Ballonfahrerin will als Erste über die Alpen – mit einer Karte von 1911."],
	["a10000000000000000000000000000a4", "Die Werft", "Series", 2021, "FSK-12", ["Drama"], "f2", "Eine Familie, eine Werft und der letzte große Auftrag."],
	["a10000000000000000000000000000a5", "Taschenlampe", "Movie", 2024, "FSK-0", ["Familie", "Animation"], "f3",
		"Ein Kind und seine Taschenlampe erkunden die Nacht im Garten."],
	["a10000000000000000000000000000a6", "Fuchsbau", "Series", 2023, "TV-MA", ["Krimi"], "f2", "Ein Anwalt verteidigt nur noch die, die er für schuldig hält."],
]

## Gemalte Bilder (Farbton, Landschaft) – nur für einige Titel, der Rest zeigt Farbflächen.
const ART := {
	"plex:101": [0.58, "meer"], "plex:102": [0.04, "duenen"], "plex:105": [0.66, "nacht"], "plex:201": [0.52, "meer"],
	"plex:202": [0.62, "nacht"], "plex:301": [0.1, "duenen"], "plex:302": [0.55, "meer"], "plex:104": [0.08, "duenen"],
	"jf:a10000000000000000000000000000a1": [0.7, "nacht"], "jf:a10000000000000000000000000000a2": [0.5, "meer"],
	"jf:a10000000000000000000000000000a3": [0.02, "duenen"], "jf:a10000000000000000000000000000a4": [0.56, "meer"],
}


static func art_path(id: String, kind: String) -> String:
	return Config.path("cache/demo/quelle_%s_%s.png" % [id.replace(":", "_"), kind])


## Fehlende Bilder im Hintergrund malen (wie bei den Ordnern der Filme-Demo).
static func paint_art() -> void:
	DirAccess.make_dir_recursive_absolute(art_path("x", "b").get_base_dir())
	for id in ART:
		for k in [["b", 480, 270], ["p", 220, 330]]:
			var path := art_path(str(id), str(k[0]))
			if not FileAccess.file_exists(path):
				Arbeit.los(_paint.bind(float(ART[id][0]), str(ART[id][1]), int(k[1]), int(k[2]), path))


static func _paint(hue: float, kind: String, w: int, h: int, path: String) -> void:
	var img := MovieDemo.paint(hue, kind, w, h)
	if img.save_png(path + ".tmp") == OK:
		DirAccess.rename_absolute(path + ".tmp", path)


static func _date(now: int, days_back: int) -> String:
	return Time.get_date_string_from_unix_time(now - days_back * 86400)


# --- Nachgebaute Plex-Antworten ------------------------------------------------------------------

static func _plex_movie(r: Array, now: int) -> Dictionary:
	var rk: int = r[0]
	var media := [{ "id": rk * 10, "duration": int(r[5]) * 60000, "videoResolution": "1080", "height": 1080, "videoCodec": "hevc", "container": "mkv",
		"Part": [
			{ "id": rk * 10 + 1, "key": "/library/parts/%d/1700000000/file.mkv" % (rk * 10 + 1), "file": "/media/filme/%s.mkv" % r[1], "size": 6800000000 + rk * 1000,
			"Stream": [{ "streamType": 1, "colorTrc": "smpte2084" if rk == 105 else "bt709" },
				{ "streamType": 2, "selected": true, "displayTitle": "Deutsch (EAC3 5.1)" },
				{ "streamType": 3, "key": "/library/streams/%d" % (rk * 100), "languageCode": "ger", "displayTitle": "Deutsch (SRT extern)" }] }] }]
	if rk == 105:
		media.push_front(
				{ "id": rk * 10 + 5, "duration": int(r[5]) * 60000, "videoResolution": "4k", "height": 2160, "videoCodec": "hevc", "container": "mkv",
				"title": "4K-Fassung",
			"Part": [{ "id": rk * 10 + 6, "key": "/library/parts/%d/1700000000/file.mkv" % (rk * 10 + 6), "file": "/media/filme/Signal 7 (4K).mkv", "size": 31000000000,
				"Stream": [{ "streamType": 1, "DOVIPresent": true }, { "streamType": 2, "selected": true, "displayTitle": "Deutsch (TrueHD Atmos 7.1)" }] }] })
	return { "ratingKey": str(rk), "key": "/library/metadata/%d" % rk, "type": "movie", "title": r[1], "year": r[2], "contentRating": r[3],
		"summary": r[7], "audienceRating": 6.4 + float(rk % 7) * 0.4, "duration": int(r[5]) * 60000, "thumb": "/library/metadata/%d/thumb/1" % rk,
		"art": "/library/metadata/%d/art/1" % rk, "addedAt": now - rk * 3600, "librarySectionID": r[6],
		"Genre": (r[4] as Array).map(func(g): return { "tag": g }),
		"Role": [{ "tag": "Mara Lindqvist", "role": "Hauptrolle" }, { "tag": "Jonas Feld", "role": "Bruder" }, { "tag": "Ada Brückner", "role": "Nachbarin" }],
		"Director": [{ "tag": "Lea Sommer" }], "Writer": [{ "tag": "Tom Weidner" }], "Country": [{ "tag": "Deutschland" }],
		"Guid": [{ "id": "tmdb://%d" % (900000 + rk) }], "Media": media }


static func _plex_show(r: Array, now: int) -> Dictionary:
	return { "ratingKey": str(r[0]), "key": "/library/metadata/%d/children" % r[0], "type": "show", "title": r[1], "year": r[2], "contentRating": r[3],
		"summary": r[6], "audienceRating": 7.9, "thumb": "/library/metadata/%d/thumb/1" % r[0], "art": "/library/metadata/%d/art/1" % r[0],
		"addedAt": now - int(r[0]) * 1800, "librarySectionID": "2", "Genre": (r[4] as Array).map(func(g): return { "tag": g }),
		"Role": [{ "tag": "Paul Okafor", "role": "Kommissar" }, { "tag": "Ada Brückner", "role": "Kommissarin" }], "Director": [{ "tag": "Lea Sommer" }] }


static func _plex_leaves(r: Array, now: int) -> Array:
	var out: Array = []
	var counts: Array = r[5]
	var n := 0
	for s in counts.size():
		for e in int(counts[s]):
			n += 1
			var ek := int(r[0]) * 100 + n
			out.append({ "ratingKey": str(ek), "type": "episode", "title": MovieDemo.EP_TITLES[n % MovieDemo.EP_TITLES.size()], "parentIndex": s + 1, "index": e + 1,
				"grandparentRatingKey": str(r[0]), "grandparentTitle": r[1], "summary": "Folge %d der %d. Staffel." % [e + 1, s + 1],
				"originallyAvailableAt": _date(now, 900 - n * 7), "duration": 2760000, "thumb": "/library/metadata/%d/thumb/1" % ek,
				"viewCount": 1 if r[0] == 201 and n <= 2 else 0, "viewOffset": 900000 if r[0] == 201 and n == 3 else 0, "lastViewedAt": now - 7200 if r[0] == 201 and n == 3
					else 0,
				"Media": [{ "id": ek * 10, "videoResolution": "1080", "height": 1080, "videoCodec": "h264", "container": "mkv",
					"Part": [
						{ "id": ek * 10 + 1, "key": "/library/parts/%d/1700000000/file.mkv" % (ek * 10 + 1), "file": "/media/serien/%s/S%02dE%02d.mkv" % [r[1], s + 1, e + 1],
						"size": 1400000000,
						"Stream": [{ "streamType": 2, "selected": true, "displayTitle": "Deutsch (AAC Stereo)" }] }] }] })
	return out


# --- Nachgebaute Jellyfin-Antworten --------------------------------------------------------------

static func _jf_item(r: Array) -> Dictionary:
	var id := str(r[0])
	return { "Id": id, "Name": r[1], "Type": r[2], "ProductionYear": r[3], "OfficialRating": r[4], "Genres": r[5], "ParentId": r[6],
		"Overview": r[7], "CommunityRating": 7.2, "RunTimeTicks": 66000000000 if r[2] == "Movie" else 0,
		"ImageTags": { "Primary": "p" + id.substr(30) }, "BackdropImageTags": ["b" + id.substr(30)],
		"UserData": { "PlaybackPositionTicks": 25000000000 if r[1] == "Salz" else 0, "Played": false, "LastPlayedDate": "2026-10-20T19:30:00.0000000Z"
			if r[1] == "Salz" else null },
		"People": [{ "Name": "Mara Lindqvist", "Type": "Actor", "Role": "Kapitänin" }, { "Name": "Lea Sommer", "Type": "Director" }],
		"MediaSources": [{ "Id": id, "Protocol": "File", "Container": "mkv", "Size": 5200000000, "Path": "/media/%s.mkv" % r[1],
			"MediaStreams": [{ "Type": "Video", "Codec": "hevc", "Height": 2160, "Width": 3840, "VideoRangeType": "HDR10" },
				{ "Type": "Audio", "DisplayTitle": "Deutsch – Dolby Digital+ 5.1" },
				{ "Type": "Subtitle", "Codec": "subrip", "Language": "ger", "DisplayTitle": "Deutsch – SRT", "IsExternal": true, "Index": 3 }] }] }


static func _jf_episodes(r: Array) -> Array:
	var out: Array = []
	for s in 2:
		for e in 5:
			var eid := "e%03d%s" % [s * 10 + e, str(r[0]).substr(4)]
			out.append({ "Id": eid, "Name": MovieDemo.EP_TITLES[(s * 5 + e) % MovieDemo.EP_TITLES.size()], "Type": "Episode", "ParentIndexNumber": s + 1,
				"IndexNumber": e + 1, "Overview": "Folge %d der %d. Staffel." % [e + 1, s + 1], "PremiereDate": "202%d-0%d-1%dT00:00:00.0000000Z" % [2 + s, e + 1, e],
				"ImageTags": { "Primary": "t" + eid.substr(0, 6) }, "RunTimeTicks": 27000000000, "SeriesId": r[0], "SeriesName": r[1],
				"UserData": { "PlaybackPositionTicks": 0, "Played": s == 0 and e < 2 } })
	return out


# --- Aufbau --------------------------------------------------------------------------------------

static func build(now: int) -> Dictionary:
	var plex_movies := PLEX_MOVIES.map(func(r: Array) -> Dictionary: return _plex_movie(r, now))
	var plex_shows := PLEX_SHOWS.map(func(r: Array) -> Dictionary: return _plex_show(r, now))
	var sections := { "MediaContainer": { "Directory": [{ "key": "1", "type": "movie", "title": "Filme" }, { "key": "2", "type": "show", "title": "Serien" },
		{ "key": "3", "type": "movie", "title": "Kinderfilme" }] } }
	var libs := {}
	for l in Plex.parse_sections(sections):
		libs[str(l.key)] = l
	var lists := {}
	var metas := {}
	var streams := {}
	var by_lib := { "1": [], "2": [], "3": [] }
	for m in plex_movies:
		by_lib[str(m.librarySectionID)].append(m)
	by_lib["2"] = plex_shows
	for k in by_lib:
		lists["plex|lib:" + k] = Plex.parse_list({ "MediaContainer": { "Metadata": by_lib[k] } }, PLEX, libs[k])
	for m in plex_movies:
		var mc := { "MediaContainer": { "Metadata": [m] } }
		metas[Plex.PREFIX + str(m.ratingKey)] = Plex.parse_meta(mc, PLEX, null, libs[str(m.librarySectionID)])
		streams[Plex.PREFIX + str(m.ratingKey)] = Plex.parse_streams(mc, PLEX, "demo", "demo", "Wohnzimmer")
	for i in plex_shows.size():
		var leaves := _plex_leaves(PLEX_SHOWS[i], now)
		var mc2 := { "MediaContainer": { "Metadata": [plex_shows[i]] } }
		metas[Plex.PREFIX + str(plex_shows[i].ratingKey)] = Plex.parse_meta(mc2, PLEX, { "MediaContainer": { "Metadata": leaves } }, libs["2"])
		for e in leaves:
			streams[Plex.PREFIX + str(e.ratingKey)] = Plex.parse_streams({ "MediaContainer": { "Metadata": [e] } }, PLEX, "demo", "demo", "Wohnzimmer")
	var leaves1 := _plex_leaves(PLEX_SHOWS[0], now)
	var leaves2 := _plex_leaves(PLEX_SHOWS[1], now)
	var cw_plex := Plex.parse_continue({ "MediaContainer": { "Metadata": [
		(plex_movies[1] as Dictionary).merged({ "viewOffset": 2400000, "lastViewedAt": now - 1800 }),
			(leaves1[2] as Dictionary).merged({ "grandparentThumb": "/t", "grandparentArt": "/a" }),
		(leaves2[1] as Dictionary).merged({ "lastViewedAt": now - 86400 }) ] } }, PLEX, libs)
	var colls := [{ "id": "901", "title": "Lieblingskrimis", "poster": "", "background": "", "count": 4, "lib": { "type": "movie" } },
		{ "id": "902", "title": "Weihnachten", "poster": "", "background": "", "count": 3, "lib": { "type": "movie" } }]
	lists["plex|coll:901"] = [lists["plex|lib:1"][1], lists["plex|lib:1"][4]]
	lists["plex|coll:902"] = (lists["plex|lib:3"] as Array).slice(0, 3)
	# Jellyfin
	var views := { "Items": [{ "Id": "f1", "Name": "Filme", "CollectionType": "movies" }, { "Id": "f2", "Name": "Serien", "CollectionType": "tvshows" },
		{ "Id": "f3", "Name": "Familie", "CollectionType": "movies" }] }
	var jlibs := {}
	for v in Jf.parse_views(views):
		jlibs[str(v.id)] = v
	var jf_items := JF_ITEMS.map(func(r: Array) -> Dictionary: return _jf_item(r))
	for lid in ["f1", "f2", "f3"]:
		lists["jellyfin|lib:" + lid] = Jf.parse_list({ "Items": jf_items.filter(func(it: Dictionary) -> bool: return str(it.ParentId) == lid) }, JF, "jellyfin",
				jlibs[lid])
	var auth := Jf.play_headers("jellyfin", "demo", "demo", "demo")
	for i in jf_items.size():
		var it: Dictionary = jf_items[i]
		var eps: Variant = { "Items": _jf_episodes(JF_ITEMS[i]) } if str(it.Type) == "Series" else null
		metas["jf:" + str(it.Id)] = Jf.parse_meta(it, JF, "jellyfin", eps, jlibs[str(it.ParentId)])
		streams["jf:" + str(it.Id)] = Jf.parse_streams(it, JF, "jellyfin", auth, "Keller-Server")
		if eps != null:
			for e in eps.Items:
				var ed: Dictionary = (it as Dictionary).duplicate(true)
				ed.Id = e.Id
				streams["jf:" + str(e.Id)] = Jf.parse_streams(ed, JF, "jellyfin", auth, "Keller-Server")
	var cw_jf := Jf.parse_continue({ "Items": [jf_items[1]] }, { "Items": [] }, JF, "jellyfin", jlibs)
	var out := {
		"servers": {
			"plex": { "id": "demo0plex0server", "name": "Wohnzimmer", "uri": PLEX, "owned": true, "http": false, "local": true },
			"jellyfin": { "base": JF, "name": "Keller-Server", "id": "demo", "http": true },
		},
		"plex_servers": [
			{ "id": "demo0plex0server", "name": "Wohnzimmer", "owned": true, "online": true, "token": "",
				"conns": [{ "uri": PLEX, "local": true, "relay": false, "http": false }] },
			{ "id": "demo0plex0mama00", "name": "Bei Mama", "owned": false, "online": true, "token": "",
				"conns": [{ "uri": PLEX, "local": false, "relay": true, "http": false }] },
		],
		"discovered": [{ "name": "Keller-Server", "id": "demo", "address": "http://192.168.178.40:8096" },
			{ "name": "NAS im Flur", "id": "demo2", "address": "http://192.168.178.12:8096" }],
		"stremio_addons": [{ "url": "https://addon.example.invalid/manifest.json", "name": "Eigenes Addon (Demo)", "have": false }],
		"lists": lists, "metas": metas, "streams": streams,
		"slots": {
			"plex": { "libs": libs, "cw": cw_plex, "colls": colls, "libs_list": [libs["1"], libs["2"], libs["3"]] },
			"jellyfin": { "libs": jlibs, "cw": cw_jf, "colls": [], "libs_list": [jlibs["f1"], jlibs["f2"], jlibs["f3"]] },
		},
	}
	_put_art(out)
	return out


## Gemalte Bilder an die Titel hängen (Startseite, Details, Weiterschauen).
static func _put_art(d: Dictionary) -> void:
	var put := func(it: Variant) -> void:
		if not (it is Dictionary):
			return
		if ART.has(str(it.get("id", ""))):
			it["background"] = art_path(str(it.id), "b")
			it["poster"] = art_path(str(it.id), "p")
			return
		# Ohne gemaltes Bild: Farbfläche statt einer Adresse, die nirgendwohin führt.
		for k in ["background", "poster", "logo", "thumbnail"]:
			if str(it.get(k, "")).begins_with("demo://"):
				it[k] = ""
	for k in d.lists:
		for it in d.lists[k]:
			put.call(it)
	for k in d.metas:
		put.call(d.metas[k])
	for s in d.slots.values():
		for it in s.cw:
			put.call(it)


## Daten einer Quelle wie nach dem Laden (_load in medienquellen.gd).
static func slot(d: Dictionary, kind: String) -> Dictionary:
	if not (d.slots as Dictionary).has(kind):
		return { "rows": [], "cw": [], "libs": {}, "err": "", "items": [] }
	var s: Dictionary = d.slots[kind]
	var libs: Array = []
	var recent: Array = []
	for l in s.libs_list:
		var lid := str(l.get("key", l.get("id", "")))
		libs.append(
				{ "id": lid, "title": str(l.get("title", l.get("name", ""))), "type": "series" if str(l.type) in ["series", "tvshows"] else "movie",
				"family": bool(l.family) })
		var items: Array = (d.lists.get("%s|lib:%s" % [kind, lid], []) as Array).duplicate(true)
		items.reverse()
		recent.append(items)
	return { "rows": Quellen._build_rows(kind, libs, recent, s.colls), "cw": (s.cw as Array).duplicate(true), "libs": s.libs, "err": "", "items": [] }


static func catalog(d: Dictionary, kind: String, catalog_id: String, skip: int, genre: String) -> Array:
	var list: Array = (d.lists.get("%s|%s" % [kind, catalog_id], []) as Array).duplicate(true)
	if genre != "":
		list = list.filter(func(it: Dictionary) -> bool: return genre in it.genres)
	return list.slice(skip, skip + Plex.PAGE)


static func genres(d: Dictionary, kind: String) -> Array:
	var seen := {}
	for k in d.lists:
		if str(k).begins_with(kind + "|"):
			for it in d.lists[k]:
				for g in it.genres:
					seen[str(g)] = true
	var names := seen.keys()
	names.sort()
	return names.map(func(n): return { "key": n, "title": n })


static func search(d: Dictionary, kind: String, q: String) -> Array:
	var lq := q.to_lower()
	var out: Array = []
	var seen := {}
	for k in d.lists:
		if str(k).begins_with(kind + "|lib:"):
			for it in d.lists[k]:
				if str(it.name).to_lower().contains(lq) and not seen.has(str(it.id)):
					seen[str(it.id)] = true
					out.append((it as Dictionary).duplicate(true))
	return out


static func streams(d: Dictionary, _kind: String, video_id: String) -> Array:
	return ((d.streams as Dictionary).get(video_id, []) as Array).duplicate(true)
