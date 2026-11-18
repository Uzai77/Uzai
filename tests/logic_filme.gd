extends Node
## Logik des Bereichs Filme ohne Netz und Oberfläche: Addon-Adressen wie Stremio, Manifeste,
## welche Addons gefragt werden, Details und Folgen, Streams (Qualität, HDR, Größe, gecacht,
## Sortierung), Plugin-Ergebnisse wie Nuvio, „Als Nächstes“ und Weiterschauen, mpv-Argumente.
## Aufruf: godot --headless --path . res://tests/logic_filme.tscn

const M := preload("res://src/core/movies.gd")
const V := preload("res://src/core/video.gd")
const NS := preload("res://src/core/nuvio_sync.gd")
const FT := preload("res://src/ui/components/nuvio_folder_tile.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("movies.json: innere Form")
	var gut := { "library": [{ "id": "tt1", "name": "A" }], "progress": { "tt1": { "tt1:1:1": { "position": 12.0, "watched": false } }, "tt2": {} },
		"items": { "tt1": { "name": "A" } }, "hidden": { "tt9": 1700000000 }, "dismissed": ["tt1:1:2"] }
	check(M.daten_pruefen(gut) == gut, "eine heile Datei bleibt, wie sie ist")
	var kaputt := { "library": [{ "id": "tt1" }, "text", null, { "name": "ohne id" }, 5],
		"progress": { "tt1": { "a": { "position": 1.0 }, "b": "text", "c": null }, "tt2": [1, 2], "tt3": "x" },
		"items": { "tt1": { "name": "A" }, "tt2": "text", "tt3": [] }, "hidden": "nein", "dismissed": ["tt1:1:2", 7, null, {}], "fremd": 1 }
	var p := M.daten_pruefen(kaputt)
	check(p.library == [{ "id": "tt1" }], "Bibliothek: nur Einträge mit id")
	check(p.progress == { "tt1": { "a": { "position": 1.0 } } }, "Fortschritt: je Titel nur Einträge, die Verzeichnisse sind (%s)" % str(p.progress))
	check(p.items == { "tt1": { "name": "A" } } and p.hidden == {} and p.dismissed == ["tt1:1:2"] and not p.has("fremd"), "Angaben, Verborgenes, Abgewähltes: nur die erwartete Form")
	var leer := M.daten_pruefen({ "library": "x", "progress": [], "items": null })
	check(leer == { "library": [], "progress": {}, "items": {}, "hidden": {}, "dismissed": [] }, "falsche Arten ganz oben: leere Vorgabe, alle fünf Teile da")

	print("Addon-Adressen")
	check(M.normalize_manifest_url("stremio://addon.example/abc/manifest.json") == "https://addon.example/abc/manifest.json", "stremio:// wird https://")
	check(M.normalize_manifest_url(" https://addon.example/abc/ ") == "https://addon.example/abc/manifest.json", "Basis-Adresse bekommt /manifest.json")
	check(M.normalize_manifest_url("addon.example/x/manifest.json?token=1") == "https://addon.example/x/manifest.json?token=1", "ohne Schema, Abfrage bleibt")
	var base := "https://addon.example/cfg=a|b/manifest.json?t=9"
	check(M.split_base(base).path == "https://addon.example/cfg=a|b" and M.split_base(base).query == "?t=9", "Basis und Abfrage getrennt")
	check(M.resource_url(base, "stream", "series", "tt0903747:1:2") == "https://addon.example/cfg=a|b/stream/series/tt0903747%3A1%3A2.json?t=9",
			"Stream-Adresse, ID kodiert wie encodeURIComponent")
	check(M.catalog_url(base, "movie", "top") == "https://addon.example/cfg=a|b/catalog/movie/top.json?t=9", "Katalog ohne Zusätze")
	check(M.catalog_url(base, "movie", "top", 100) == "https://addon.example/cfg=a|b/catalog/movie/top/skip=100.json?t=9", "nur skip: …/skip=100.json")
	var u := M.catalog_url("https://a.example/manifest.json", "movie", "top", 50, { "genre": "Science Fiction", "search": "Ä & B" })
	check(u == "https://a.example/catalog/movie/top/genre=Science%20Fiction&search=%C3%84%20%26%20B&skip=50.json", "Zusätze kodiert, skip hinten: " + u)
	check(M.configure_url_for("https://a.example/x/manifest.json") == "https://a.example/x/configure", "Seite zum Einrichten")
	check(M.normalize_repo_url("https://repo.example/plugins") == "https://repo.example/plugins/manifest.json"
			and M.normalize_repo_url("https://r.example/list.json") == "https://r.example/list.json", "Plugin-Repo-Adresse wie Nuvio")

	print("Manifest")
	var man := {
		"id": "org.test", "name": "Test", "version": "1.0.0", "types": ["movie", "series"], "idPrefixes": ["tt"],
		"resources": ["catalog", { "name": "meta", "types": ["series"], "idPrefixes": ["kitsu:"] }, "stream", "subtitles"],
		"catalogs": [
			{ "type": "movie", "id": "top", "name": "Popular", "extra": [{ "name": "genre", "options": ["Action", "Drama"] }, { "name": "skip" }] },
			{ "type": "movie", "id": "year", "name": "New", "extra": [{ "name": "genre", "isRequired": true, "options": ["2026"] }] },
			{ "type": "movie", "id": "suche", "name": "Search", "extra": [{ "name": "search", "isRequired": true }] },
			{ "type": "series", "id": "alt", "name": "Alt", "extraSupported": ["search", "genre"], "extraRequired": ["genre"] },
		],
		"behaviorHints": { "configurable": true },
	}
	var a := M.parse_manifest(man, "https://t.example/manifest.json")
	check(str(a.id) == "org.test" and a.resources == ["catalog", "meta", "stream", "subtitles"], "Ressourcen als Namen")
	check(bool(a.configurable) and not bool(a.config_required), "einrichtbar erkannt")
	check(M.parse_manifest({ "id": "x" }, "u").is_empty() and M.parse_manifest({ "resources": ["stream"] }, "u").is_empty(), "ohne id oder resources: kein Addon")
	check(M.supports(a, "stream", "movie", "tt1") and not M.supports(a, "stream", "movie", "kitsu:1") and not M.supports(a, "stream", "channel", "tt1"),
			"Stream: Typ und ID-Präfix")
	check(M.supports(a, "meta", "series", "kitsu:5") and not M.supports(a, "meta", "series", "tt5") and not M.supports(a, "meta", "movie", "kitsu:5"),
			"Präfix der Ressource gilt vor dem des Addons")
	var cats: Array = a.catalogs
	check(not M.catalog_needs(cats[0], []) and M.catalog_needs(cats[1], []) and M.catalog_needs(cats[2], []) and not M.catalog_needs(cats[2], ["search"]),
			"Pflicht-Zusätze erkannt")
	check(M.catalog_needs(cats[3], ["search"]) and M.catalog_has(cats[3], "search"), "altes Format extraRequired/extraSupported")
	check(M.catalog_title(cats[0]) == "Beliebt – Filme" and M.catalog_title({ "name": "Meine Liste", "type": "series" }) == "Meine Liste – Serien",
			"Katalognamen auf Deutsch")
	var cine := M.parse_manifest(M.CINEMETA_MANIFEST, M.CINEMETA_URL)
	var other := M.parse_manifest({ "id": "o", "name": "O", "types": ["movie", "series"], "resources": ["meta"], "catalogs": [] }, "https://o/manifest.json")
	other.enabled = true
	cine.enabled = true
	var mc := M.meta_candidates([other, cine], "movie", "tt42")
	check(mc.size() == 2 and str(mc[0].id) == "o", "Details: Reihenfolge der Addons, beide passen")
	var mc2 := M.meta_candidates([cine, other], "movie", "kitsu:9")
	check(mc2.size() == 1 and str(mc2[0].id) == "o", "kitsu-ID: Cinemeta (nur tt) fällt raus")

	print("Details")
	var raw := {
		"id": "tt100", "type": "series", "name": "Serie", "releaseInfo": "2019–2023", "imdbRating": 8.5, "genre": ["Drama"],
		"links": [{ "name": "Ada", "category": "Cast", "url": "x" }, { "name": "Bo", "category": "Directors", "url": "y" }],
		"trailerStreams": [{ "title": "Trailer", "ytId": "abc" }], "trailers": [{ "source": "abc", "type": "Trailer" }, { "source": "def", "type": "Teaser" }],
		"moviedb_id": 4711, "behaviorHints": { "defaultVideoId": null },
		"videos": [
			{ "id": "tt100:2:1", "name": "Zwei Eins", "season": 2, "episode": 1, "released": "2021-01-01T00:00:00.000Z" },
			{ "id": "tt100:0:1", "name": "Special", "season": 0, "episode": 1, "released": "2018-01-01T00:00:00.000Z" },
			{ "id": "tt100:1:2", "title": "Eins Zwei", "season": 1, "number": 2, "released": "2020-01-08T00:00:00.000Z" },
			{ "id": "tt100:1:1", "name": "Eins Eins", "season": 1, "episode": 1, "released": "2020-01-01T00:00:00.000Z", "overview": "Start" },
			{ "id": "tt100:2:2", "season": 2, "episode": 2, "released": "2099-01-01T00:00:00.000Z" },
		],
	}
	var meta := M.parse_meta(raw, "c", "series", "2026-06-01")
	var order: Array = (meta.videos as Array).map(func(v): return str(v.id))
	check(order == ["tt100:1:1", "tt100:1:2", "tt100:2:1", "tt100:2:2", "tt100:0:1"], "Folgen sortiert, Specials hinten: " + str(order))
	check(meta.seasons == [1, 2, 0], "Staffeln mit 0 am Ende: " + str(meta.seasons))
	check(str(meta.year) == "2019" and str(meta.imdb_rating) == "8.5" and meta.genres == ["Drama"], "Jahr, Bewertung, Genre (genre statt genres)")
	check(meta.cast == ["Ada"] and meta.director == ["Bo"], "Besetzung und Regie aus links")
	check((meta.trailers as Array).size() == 2 and str(meta.trailers[0].yt_id) == "abc", "Trailer ohne Doppelte")
	check(str(meta.tmdb_id) == "4711" and str(meta.imdb_id) == "tt100", "TMDB-ID aus moviedb_id")
	check(str(meta.videos[1].title) == "Eins Zwei" and int(meta.videos[1].episode) == 2, "Titel und Folge aus title/number")
	check(str(meta.videos[3].title) == "Folge 2" and not bool(meta.videos[3].available), "fehlender Titel → „Folge 2“, Zukunft nicht verfügbar")
	check(str(meta.background).contains("metahub") and str(meta.logo).contains("/logo/"), "Bilder von metahub, wenn das Addon keine liefert")
	check(meta.people is Dictionary and not M.has_photos(meta.people), "nur Namen: Personen ohne Bilder")

	print("Besetzung mit Bildern")
	# Cinemeta: cast nur Namen, Bilder in app_extras.cast (volle Adresse) und credits_cast (TMDB-Pfad).
	var cm_raw := {
		"id": "tt42", "type": "movie", "name": "Film",
		"cast": ["Tim Robbins", "Morgan Freeman", "Bob Gunton"], "director": ["Frank Darabont"],
		"app_extras": { "cast": [
			{ "name": "Tim Robbins", "character": "Andy Dufresne", "photo": "https://image.tmdb.org/t/p/w276_and_h350_face/tim.jpg" },
			{ "name": "Morgan Freeman", "character": "Ellis Boyd 'Red' Redding", "photo": null },
		], "directors": [{ "name": "Frank Darabont", "photo": "http://image.tmdb.org/t/p/w276_and_h350_face/frank.jpg" }] },
		"credits_cast": [
			{ "id": 1, "name": "Tim Robbins", "character": "Andy", "profile_path": "/anders.jpg" },
			{ "id": 2, "name": "Morgan Freeman", "character": "Red", "profile_path": "/morgan.jpg" },
			{ "id": 3, "name": "Bob Gunton", "character": "Warden Norton", "profile_path": null },
			{ "id": 4, "name": "William Sadler", "character": "Heywood", "profile_path": "/william.png" },
		],
		"credits_crew": [{ "id": 9, "name": "Roger Deakins", "job": "Director of Photography", "profile_path": "/roger.jpg" }],
	}
	var cm := M.parse_meta(cm_raw, "com.linvo.cinemeta", "movie")
	var pp: Dictionary = cm.people
	check(cm.cast == ["Tim Robbins", "Morgan Freeman", "Bob Gunton", "William Sadler"], "Besetzung: cast vorn, weitere aus credits_cast: " + str(cm.cast))
	check(str(pp["tim robbins"].photo) == "https://image.tmdb.org/t/p/w276_and_h350_face/tim.jpg" and str(pp["tim robbins"].character) == "Andy Dufresne",
			"app_extras zuerst (Bild und Figur)")
	check(str(pp["morgan freeman"].photo) == M.TMDB_IMG + "/morgan.jpg" and str(pp["morgan freeman"].character).begins_with("Ellis"),
			"fehlendes Bild aus credits_cast.profile_path mit TMDB-Bildadresse")
	check(str(pp["bob gunton"].photo) == "" and str(pp["william sadler"].photo) == M.TMDB_IMG + "/william.png", "ohne Bild bleibt leer (Initialen)")
	check(str(pp["frank darabont"].photo).begins_with("https://image.tmdb.org/") and str(pp["roger deakins"].photo).ends_with("/roger.jpg"),
			"Regie und Team: http → https, credits_crew")
	check(M.has_photos(pp) and cm.director == ["Frank Darabont"], "has_photos, Regie bleibt Name")
	# Addons, die cast als Einträge liefern (statt Namen); Bild unter anderem Feldnamen.
	var obj := M.parse_meta(
			{ "id": "x1", "name": "X",
			"cast": [{ "name": "Ada Muster", "character": "Ärztin", "image": "//cdn.example/ada.webp" }, { "name": "  Bo  Beispiel " }, null, ""],
		"director": [{ "name": "Cleo Regie" }] }, "a", "movie")
	check(obj.cast == ["Ada Muster", "Bo  Beispiel"] and obj.director == ["Cleo Regie"],
			"cast/director als Einträge → Namen: " + str(obj.cast) + str(obj.director))
	check(str(obj.people["ada muster"].photo) == "https://cdn.example/ada.webp" and str(obj.people[M.person_key("Bo Beispiel")].name) == "Bo  Beispiel",
			"//-Adresse wird https, Schlüssel ohne Groß/Leerzeichen")
	check(M.person_photo("abc.jpg") == "" and M.person_photo("/kein-bild") == "" and M.person_photo(42) == "" and M.person_photo("null") == "",
			"keine Adresse: leer")
	# TMDB-Antwort /credits bzw. /aggregate_credits (Serien: Figur in roles).
	var tm := M.parse_people(
			{ "credits_cast": [{ "name": "Ada Muster", "profile_path": "/ada.jpg", "roles": [{ "character": "Kapitänin" }] }], "credits_crew": [] })
	check(str(tm["ada muster"].photo) == M.TMDB_IMG + "/ada.jpg" and str(tm["ada muster"].character) == "Kapitänin", "aggregate_credits: Bild und Figur")
	var merged := M.merge_people({ "ada muster": { "name": "Ada Muster", "photo": "", "character": "" } }, tm)
	check(str(merged["ada muster"].photo).ends_with("/ada.jpg") and str(merged["ada muster"].character) == "Kapitänin", "merge_people ergänzt Fehlendes")
	var many: Array = []
	for i in 40:
		many.append({ "name": "Person %d" % i, "profile_path": "/p%d.jpg" % i })
	check((M.parse_meta({ "id": "x2", "name": "Y", "credits_cast": many }, "a", "movie").cast as Array).size() == M.CAST_MAX, "Besetzung höchstens CAST_MAX")
	var sv := M.split_video_id("tt100:2:5")
	check(str(sv.meta_id) == "tt100" and int(sv.season) == 2 and int(sv.episode) == 5, "Folgen-ID zerlegt")
	check(str(M.split_video_id("kitsu:42:7").meta_id) == "kitsu:42" and int(M.split_video_id("kitsu:42:7").episode) == 7
			and str(M.split_video_id("tt9").meta_id) == "tt9", "kitsu und Film")

	print("Streams lesen")
	var addon := { "id": "s", "name": "Quelle" }
	var st := M.parse_stream({ "name": "Quelle\n4K DV | HDR", "title": "Film.2160p.REMUX.HEVC.Atmos\n👤 12 💾 41.2 GB ⚙️ X", "url": "https://cdn/x.mkv",
		"behaviorHints": { "bingeGroup": "q-4k", "filename": "Film.mkv", "proxyHeaders": { "request": { "Referer": "https://r/", "User-Agent": "UA" } } } }, addon)
	check(int(st.quality) == 2160 and str(st.hdr) == "DV" and str(st.codec) == "HEVC", "4K, DV, HEVC aus Name/Titel")
	check(int(st.size_bytes) == int(41.2 * 1073741824.0) and str(st.size_text) == "41,2 GB", "Größe aus dem Titel: " + str(st.size_text))
	check(str(st.headers.Referer) == "https://r/" and str(st.headers["User-Agent"]) == "UA" and str(st.binge_group) == "q-4k" and str(st.filename) == "Film.mkv",
			"Kopfzeilen (proxyHeaders), bingeGroup, Dateiname")
	check(not bool(st.cached) and not bool(st.is_p2p) and str(st.source) == "addon", "nicht gecacht, kein P2P")
	var p2p := M.parse_stream({ "name": "T", "title": "x 1080p", "infoHash": "abc", "fileIdx": 1 }, addon)
	check(bool(p2p.is_p2p) and str(p2p.url) == "" and str(p2p.info_hash) == "abc", "infoHash ist P2P, ohne Adresse")
	check(M.parse_stream({ "ytId": "x" }, addon).is_empty() and M.parse_stream({ "externalUrl": "https://x" }, addon).is_empty(),
			"ytId/externalUrl ohne Adresse: weg")
	check(bool(M.parse_stream({ "name": "[RD+] T 720p", "url": "u" }, addon).cached) and bool(M.parse_stream({ "name": "⚡ x", "url": "u" }, addon).cached),
			"gecacht: [RD+] und ⚡")
	check(not M.is_cached("[RD download] x") and M.is_cached("TB+ 1080p") and M.is_cached("Instant 4K") and not M.is_cached("uncached"),
			"gecacht nur bei echten Zeichen")
	check(M.quality_of("WEB-DL 1080p") == 1080 and M.quality_of("Full HD") == 720 and M.quality_of("hdrip") == 0 and M.quality_of("SD 576p") == 480
			and M.quality_of("2K") == 1440, "Auflösung wie Nuvio")
	check(M.hdr_of("HDR10+ x") == "HDR10+" and M.hdr_of("hdr10") == "HDR10" and M.hdr_of("Dolby Vision") == "DV" and M.hdr_of("HLG") == "HLG"
			and M.hdr_of("hdrip") == "", "HDR-Arten")
	check(M.size_of("850 MB") == 850 * 1048576 and M.size_of("1,5 GB") == int(1.5 * 1073741824.0) and M.size_of("2 GiB") == 2 * 1073741824
			and M.size_of("ohne") == 0, "Größen mit Komma und GiB")
	check(M.size_text(850 * 1048576) == "850 MB" and M.size_text(0) == "", "Größe als Text")
	var desc_only := M.parse_stream({ "name": "Q", "description": "WEBRip 720p · 1.4 GB", "url": "u" }, addon)
	check(int(desc_only.quality) == 720 and int(desc_only.size_bytes) > 1400000000, "neue Addons: alles in description")

	print("Sortierung")
	var list := [
		{ "id": "a", "is_p2p": false, "cached": false, "quality": 2160, "size_bytes": 40, "order": 0 },
		{ "id": "b", "is_p2p": false, "cached": true, "quality": 720, "size_bytes": 1, "order": 1 },
		{ "id": "c", "is_p2p": false, "cached": false, "quality": 1080, "size_bytes": 9, "order": 2 },
		{ "id": "d", "is_p2p": false, "cached": false, "quality": 1080, "size_bytes": 12, "order": 3 },
		{ "id": "e", "is_p2p": false, "cached": false, "quality": 0, "size_bytes": 99, "order": 4 },
		{ "id": "f", "is_p2p": true, "cached": true, "quality": 2160, "size_bytes": 99, "order": 5 },
		{ "id": "g", "is_p2p": false, "cached": false, "quality": 1080, "size_bytes": 12, "order": 1 },
	]
	var ids := func(l: Array) -> String: return "".join(PackedStringArray(l.map(func(s): return str(s.id))))
	check(ids.call(M.sort_streams(list, 0)) == "bagdcef",
			"auto: gecacht, dann höchste Qualität, Größe, Addon-Reihenfolge – " + str(ids.call(M.sort_streams(list, 0))))
	check(ids.call(M.sort_streams(list, 1080)) == "bgdcaef",
			"1080p bevorzugt: erst 1080, dann darunter, dann darüber – " + str(ids.call(M.sort_streams(list, 1080))))
	check(M.stream_key({ "url": "u", "name": "n" }) == M.stream_key({ "url": "u", "name": "n", "x": 1 })
			and M.stream_key({ "url": "u", "name": "n" }) != M.stream_key({ "url": "u", "name": "m" }), "doppelte Streams: Adresse plus Name")
	var last := { "binge_group": "q-1080", "addon_id": "s", "quality": 1080 }
	var cands := [{ "id": "1", "binge_group": "x", "addon_id": "s", "quality": 2160 }, { "id": "2", "binge_group": "q-1080", "addon_id": "s", "quality": 1080 }]
	check(str(M.pick_next_stream(cands, last).id) == "2" and str(M.pick_next_stream(cands, {}).id) == "1", "nächste Folge: gleiche bingeGroup, sonst der erste")

	print("Plugins wie Nuvio")
	var sc := { "id": "r1:alpha", "name": "Alpha", "types": ["movie", "tv"] }
	var pr := M.parse_plugin_result(
			{ "name": "Alpha", "title": "Film (2024)", "url": "https://p/v.m3u8", "quality": "1080p", "size": "2.3 GB", "language": "Deutsch",
		"headers": { "Referer": "https://p/", "X": 5 }, "subtitles": [{ "url": "https://p/de.vtt", "language": "de" }] }, sc)
	check(str(pr.name) == "Alpha - 1080p" and str(pr.title) == "Film (2024)" and str(pr.description) == "2.3 GB • Deutsch",
			"Name mit Qualität, Beschreibung Größe • Sprache")
	check(int(pr.quality) == 1080 and int(pr.size_bytes) > 2000000000 and str(pr.source) == "plugin" and str(pr.addon_id) == "plugin:r1:alpha",
			"Qualität, Größe, Quelle")
	check(str(pr.headers.Referer) == "https://p/" and str(pr.headers.X) == "5" and (pr.subtitles as Array).size() == 1 and str(pr.subtitles[0].lang) == "de",
			"Kopfzeilen und Untertitel")
	# Schon beim Einlesen fallen Untertitel weg, deren Adresse kein http(s) ist (Datei, Netzwerkfreigabe).
	var pr2 := M.parse_plugin_result({ "name": "Alpha", "url": "https://p/v.m3u8", "subtitles": [{ "url": "\\\\fremd\\freigabe\\a.srt", "language": "de" },
		{ "url": "C:/geheim.txt" }, { "url": "https://p/en.vtt", "language": "en" }] }, sc)
	check((pr2.subtitles as Array).size() == 1 and str(pr2.subtitles[0].url) == "https://p/en.vtt", "Plugin: Untertitel nur über http(s)")
	var as2 := M.parse_stream({ "url": "https://a/v.mkv", "subtitles": [{ "url": "file:///c:/x.srt", "lang": "de" }, { "url": "smb://fremd/a.srt" },
		{ "url": "HTTPS://a/de.srt", "lang": "de" }] }, { "id": "a", "name": "A" })
	check((as2.subtitles as Array).size() == 1 and str(as2.subtitles[0].url) == "HTTPS://a/de.srt", "Addon: Untertitel nur über http(s)")
	check(M.parse_plugin_result({ "url": { "url": "https://p/2" }, "title": "x" }, sc).url == "https://p/2", "url als Objekt")
	check(M.parse_plugin_result({ "url": "[object Object]" }, sc).is_empty() and M.parse_plugin_result({ "title": "x" }, sc).is_empty(),
			"kaputte Ergebnisse fallen weg")
	check(str(M.parse_plugin_result({ "url": "https://p/3", "quality": "4K" }, sc).name) == "Alpha - 4K"
			and int(M.parse_plugin_result({ "url": "https://p/3", "quality": "4K" }, sc).quality) == 2160, "4K-Qualität")
	check(M.plugin_media_type("series", ["movie", "tv"], 1, 2) == "tv" and M.plugin_media_type("series", ["movie", "series"], 1, 2) == "series"
			and M.plugin_media_type("movie", [], 0, 0) == "movie", "Medientyp für getStreams")
	check(M.scraper_supports(sc, "series") and M.scraper_supports(sc, "movie") and not M.scraper_supports({ "types": ["movie"] }, "series"), "Scraper nach Typ")

	print("Als Nächstes")
	var vids := [
		{ "id": "s:1:1", "season": 1, "episode": 1, "released": "2020-01-01", "available": true },
		{ "id": "s:1:2", "season": 1, "episode": 2, "released": "2020-01-08", "available": true },
		{ "id": "s:1:3", "season": 1, "episode": 3, "released": "", "available": true },
		{ "id": "s:1:4", "season": 1, "episode": 4, "released": "", "available": false },
		{ "id": "s:2:1", "season": 2, "episode": 1, "released": "2026-05-01", "available": true },
		{ "id": "s:2:2", "season": 2, "episode": 2, "released": "2026-09-01", "available": false },
		{ "id": "s:0:1", "season": 0, "episode": 1, "released": "2019-01-01", "available": true },
	]
	check(str(M.next_video(vids, 1, 1, "", "2026-06-01").id) == "s:1:2", "nächste Folge in der Staffel")
	check(str(M.next_video(vids, 1, 2, "", "2026-06-01").id) == "s:1:3", "ohne Datum, aber verfügbar")
	check(M.next_video(vids, 1, 3, "", "2026-06-01").is_empty(), "ohne Datum und nicht verfügbar: nichts")
	check(str(M.next_video(vids, 0, 0, "s:1:4", "2026-06-01").id) == "s:2:1", "Staffelwechsel mit erreichtem Datum (Suche über die ID)")
	check(M.next_video(vids, 2, 1, "", "2026-06-01").is_empty() and M.next_video(vids, 1, 4, "", "2026-04-01").is_empty(), "noch nicht ausgestrahlt: nichts")
	check(M.next_video(vids, 0, 1, "", "2026-06-01").is_empty(), "Specials sind kein Anfang")

	print("Weiterschauen")
	var now := 1_800_000_000
	var d := {
		"items": {
			"tt1": { "id": "tt1", "type": "movie", "name": "Film" },
			"tt2": { "id": "tt2", "type": "series", "name": "Serie", "videos": vids },
			"tt3": { "id": "tt3", "type": "series", "name": "Zweite", "videos": vids },
			"tt4": { "id": "tt4", "type": "movie", "name": "Gesehen" },
			"tt5": { "id": "tt5", "type": "series", "name": "Ausgeblendet", "videos": vids },
		},
		"progress": {
			"tt1": { "tt1": { "position": 600.0, "duration": 6000.0, "watched": false, "updated": now - 50 } },
			"tt2": { "s:1:1": { "position": 0.0, "duration": 1000.0, "watched": true, "updated": now - 300, "season": 1, "episode": 1 },
				"s:1:2": { "position": 0.0, "duration": 1000.0, "watched": true, "updated": now - 400, "season": 1, "episode": 2 } },
			"tt3": { "s:1:1": { "position": 0.0, "duration": 1000.0, "watched": true, "updated": now - 900, "season": 1, "episode": 1 },
				"s:1:2": { "position": 120.0, "duration": 1000.0, "watched": false, "updated": now - 10, "season": 1, "episode": 2, "title": "Zwei" } },
			"tt4": { "tt4": { "position": 0.0, "duration": 6000.0, "watched": true, "updated": now - 5 } },
			"tt5": { "s:1:1": { "position": 0.0, "duration": 1000.0, "watched": true, "updated": now - 20, "season": 1, "episode": 1 } },
		},
		"hidden": { "tt5": now - 10 }, "dismissed": [],
	}
	var cw := M.build_continue(d, "2026-06-01")
	var cw_ids: Array = cw.map(func(c): return "%s/%s" % [c.id, c.video_id])
	check(cw_ids == ["tt3/s:1:2", "tt1/tt1", "tt2/s:1:3"], "angefangen und Als Nächstes, neueste zuerst: " + str(cw_ids))
	if cw.size() == 3:
		check(not bool(cw[0].next_up) and float(cw[0].position) == 120.0 and str(cw[0].episode_title) == "Zwei", "angefangene Folge mit Stelle und Titel")
		check(bool(cw[2].next_up) and int(cw[2].season) == 1 and int(cw[2].episode) == 3 and float(cw[2].position) == 0.0,
				"Als Nächstes nach der am weitesten geschauten Folge")
		check(not cw[0].has("videos"), "ohne Folgenliste im Eintrag")
	d.dismissed = ["tt2:1:2"]
	check(M.build_continue(d, "2026-06-01").size() == 2, "Als Nächstes ausgeblendet bleibt weg")

	print("mpv für Filme")
	var args := V.stream_args({ "headers": { "User-Agent": "UA/1", "Referer": "https://r/", "X-Token": "a,b" }, "media_title": "Serie – S01E02", "movies": {} })
	check("--user-agent=UA/1" in args and "--referrer=https://r/" in args and "--http-header-fields-append=X-Token: a,b" in args,
			"Kopfzeilen als mpv-Argumente: " + str(args))
	check("--force-media-title=Serie – S01E02" in args and "--ytdl=no" in args, "Titel und kein yt-dlp für direkte Dateien")
	check(V.stream_args({ "id": "yt" }).is_empty(), "YouTube-Videos bekommen nichts dazu")
	# Untertitel aus Addons und Plugins: nur http(s) geht an mpv. Eine Netzwerkfreigabe ließe Windows die Anmeldung des
	# Nutzers an einen fremden Rechner schicken, eine Datei läse mpv vom PC. Früher wurde nur die nachgereichte Liste
	# geprüft, nicht die, die mit dem Stream kam.
	var roh := [{ "url": "\\\\fremd\\freigabe\\a.srt", "lang": "de" }, { "url": "C:/Users/x/geheim.txt" }, { "url": "file:///c:/x.srt" },
		{ "url": "smb://fremd/freigabe/a.srt" }, { "url": "edl://x" }, "kein Eintrag", null, { "lang": "de" },
		{ "url": " https://subs.example/a b.srt ", "lang": "de" }, { "url": "http://subs.example/c.srt", "lang": "en" }]
	var sicher := V.sichere_untertitel(roh)
	check(sicher.size() == 2 and str(sicher[0].url) == "https://subs.example/a%20b.srt" and str(sicher[1].url) == "http://subs.example/c.srt",
			"Untertitel: nur Adressen über http(s) bleiben, bereinigt (keine Freigabe, keine Datei, kein anderes Protokoll)")
	check(V.sichere_untertitel(null).is_empty() and V.sichere_untertitel("x").is_empty(), "Untertitel: keine Liste ist eine leere Liste")
	var vquelle := FileAccess.get_file_as_string("res://src/core/video.gd")
	var senden := vquelle.substr(vquelle.find("func _send_subs("), 1600)
	check(senden.contains("sichere_untertitel(video.get(\"subtitles\"))") and senden.find("sichere_untertitel(") < senden.find("sub-add"),
			"Untertitel: geprüft wird unmittelbar vor dem Befehl an mpv (auch die Liste, die mit dem Stream kam)")
	var subs := V.sort_subtitles([{ "url": "1", "lang": "fre" }, { "url": "2", "lang": "eng" }, { "url": "3", "lang": "ger" }, { "url": "4", "lang": "de" }],
			"de,en")
	check(subs.map(func(s): return str(s.url)) == ["3", "4", "2", "1"], "Untertitel: bevorzugte Sprachen zuerst (ger = de)")

	print("Nuvio: Änderungen der Bibliothek")
	var nlib := [{ "id": "tt1", "name": "Eins" }, { "id": "tt2", "name": "Zwei" }, { "id": "tt3", "name": "Drei" }]
	var nev := [{ "event_id": 3, "content_id": "tt9", "name": "Neun" }, { "event_id": 1, "content_id": "tt2", "operation": "delete" },
		{ "event_id": 2, "content_id": "tt8", "name": "Acht" }, { "event_id": 4, "content_id": "tt8", "name": "Acht neu" },
		{ "event_id": 5, "content_id": "tt3", "operation": "delete" }, { "event_id": 6, "content_id": "tt3", "name": "Drei wieder" },
		{ "event_id": 7, "content_id": "", "name": "ohne Kennung" }]
	var nach := NS.apply_library_delta(nlib, nev)
	check(nach.map(func(e): return str(e.name)) == ["Drei wieder", "Acht neu", "Neun", "Eins"],
			"je Titel zählt das letzte Ereignis, Neues vorn (das jüngste zuerst), Gelöschtes weg: " + str(nach.map(func(e): return str(e.name))))
	check(nlib.size() == 3 and NS.apply_library_delta(nlib, []).size() == 3, "die alte Liste bleibt, wie sie war; ohne Ereignisse ändert sich nichts")
	var mjetzt := 2000 * 86400
	check(NS.miss_gueltig({ "tt1": mjetzt - 86400, "tt2": mjetzt - (NS.MISS_TAGE + 1) * 86400, "tt3": "kaputt" }, mjetzt).keys() == ["tt1"]
			and NS.miss_gueltig(null, mjetzt).is_empty(), "„kennt kein Addon“ gilt nur ein paar Tage (ein neues Addon kennt den Titel vielleicht)")

	print("Nuvio-Sammlungen als Ordner")
	var cf := NS.collection_folders([
		{ "id": "neu", "title": "Abend", "pinToTop": true, "showAllTab": false, "folders": [
			{ "id": "f1", "title": "Krimi", "tileShape": "landscape", "coverImageUrl": "https://bild/krimi.jpg", "coverEmoji": "🔍", "hideTitle": true,
				"sources": [{ "provider": "addon", "addonId": "a.eins", "type": "movie", "catalogId": "krimi", "genre": "Thriller" },
					{ "provider": "tmdb", "tmdbListId": 42 }] },
			{ "id": "f2", "title": "Nur TMDB", "sources": [{ "provider": "tmdb", "tmdbListId": 7 }, { "provider": "trakt", "listId": "x" }] },
		] },
		{ "id": "alt", "title": "Klassik", "folders": [
			{ "id": "g1", "title": "Alt", "catalogSources": [{ "addonId": "a.zwei", "type": "series", "catalogId": "top" }] },
		] },
		{ "id": "leer", "title": "Leer", "folders": [{ "id": "h1", "title": "Nichts", "catalogSources": [] }] },
	])
	check(cf.keys().size() == 3 and cf.has("collection_neu") and cf.has("collection_alt") and cf.has("collection_leer"),
			"je Sammlung ein Schlüssel collection_<id>")
	var r_neu: Dictionary = cf.collection_neu[0] if (cf.get("collection_neu", []) as Array).size() == 1 else {}
	check(str(r_neu.get("key", "")) == "collection_neu" and str(r_neu.get("title", "")) == "Abend" and str(r_neu.get("kind", "")) == "folders"
			and (r_neu.get("items", [0]) as Array).is_empty(), "eine Ordner-Reihe mit Titel der Sammlung, ohne Titel-Einträge")
	check(bool(r_neu.get("pin", false)) and not bool(r_neu.get("show_all", true)), "pinToTop und showAllTab übernommen")
	var fs: Array = r_neu.get("folders", [])
	check(fs.size() == 1, "Ordner ohne Addon-Quelle (nur TMDB/Trakt) fällt weg")
	if fs.size() == 1:
		var f1: Dictionary = fs[0]
		check(str(f1.id) == "f1" and str(f1.title) == "Krimi" and str(f1.collection) == "Abend", "Ordner mit Name und Sammlung")
		check(str(f1.cover) == "https://bild/krimi.jpg" and str(f1.emoji) == "🔍" and bool(f1.hide_title) and str(f1.shape) == "LANDSCAPE",
				"Titelbild, Emoji, Name ausgeblendet, Form groß geschrieben")
		check(f1.sources == [{ "addon_id": "a.eins", "type": "movie", "catalog_id": "krimi", "genre": "Thriller" }],
				"nur die Addon-Quelle, TMDB übersprungen: " + str(f1.sources))
	var r_alt: Dictionary = cf.collection_alt[0] if (cf.get("collection_alt", []) as Array).size() == 1 else {}
	var ga: Array = r_alt.get("folders", [])
	check(ga.size() == 1 and ga[0].sources == [{ "addon_id": "a.zwei", "type": "series", "catalog_id": "top", "genre": "" }], "ältere catalogSources gelesen")
	check(ga.size() == 1 and str(ga[0].shape) == "SQUARE" and str(ga[0].cover) == "" and str(ga[0].emoji) == "" and not bool(ga[0].hide_title),
			"ohne Angaben: quadratisch, ohne Bild und Emoji, Name sichtbar")
	check(not bool(r_alt.get("pin", true)) and bool(r_alt.get("show_all", false)), "ohne Angaben: nicht oben angeheftet, „Alle“ sichtbar")
	check((cf.collection_leer as Array).is_empty(), "Sammlung ohne brauchbare Ordner: keine Reihe")
	check(fs.size() == 1 and str(fs[0].backdrop) == "https://bild/krimi.jpg", "ohne heroBackdropUrl: Hintergrund = Kachelbild (wie Nuvio)")
	check(ga.size() == 1 and str(ga[0].backdrop) == "" and str(ga[0].logo) == "", "ohne Bilder: kein Hintergrund, kein Schriftzug")
	var cb := NS.collection_folders([{ "id": "b", "title": "Bild", "backdropImageUrl": "https://bild/samml.jpg", "folders": [
		{ "id": "o1", "title": "Eigen", "heroBackdropUrl": " https://bild/hero.jpg ", "coverImageUrl": "https://bild/kachel.jpg",
			"titleLogoUrl": "https://bild/logo.png",
			"catalogSources": [{ "addonId": "a", "type": "movie", "catalogId": "c" }] },
		{ "id": "o2", "title": "Ohne", "catalogSources": [{ "addonId": "a", "type": "movie", "catalogId": "c" }] },
	] }])
	var bf: Array = (cb.collection_b[0] as Dictionary).folders if (cb.get("collection_b", []) as Array).size() == 1 else []
	check(bf.size() == 2 and str(bf[0].backdrop) == "https://bild/hero.jpg" and str(bf[0].cover) == "https://bild/kachel.jpg"
			and str(bf[0].logo) == "https://bild/logo.png", "heroBackdropUrl vor Kachelbild, Schriftzug übernommen")
	check(bf.size() == 2 and str(bf[1].backdrop) == "https://bild/samml.jpg" and str(bf[1].cover) == "https://bild/samml.jpg",
			"Ordner ohne Bilder: Bild der Sammlung für Kachel und Hintergrund")
	check(is_equal_approx(FT.row_height([{ "shape": "LANDSCAPE" }, { "shape": "POSTER", "hide_title": true }]), 342.0),
			"Reihenhöhe: höchste Kachel samt Name (max(252+52, 342) = 342)")

	print("Startseite ohne Antwort")
	var mh: Node = M.new()
	var ad := { "id": "a.eins" }
	var ok_job := { "addon": ad, "cat": { "type": "movie", "id": "neu", "name": "Neu" }, "items": [{ "id": "tt1" }], "ok": true }
	var bad_job := { "addon": ad, "cat": { "type": "movie", "id": "top", "name": "Top" }, "items": [], "ok": false }
	var gone_job := { "addon": ad, "cat": { "type": "series", "id": "top", "name": "Top" }, "items": [], "ok": false }
	var hr: Array = mh._assemble_home([ok_job, bad_job, gone_job], {}, { "a.eins/movie/top": [{ "id": "tt9" }], "a.eins/movie/neu": [{ "id": "alt" }] })
	check(hr.map(func(r): return str(r.key)) == ["a.eins/movie/neu", "a.eins/movie/top"],
			"fehlgeschlagener Katalog zeigt seinen alten Stand, ohne alten fällt er weg: " + str(hr.map(func(r): return str(r.key))))
	check(hr.size() == 2 and str(hr[0].items[0].id) == "tt1" and str(hr[1].items[0].id) == "tt9", "frische Antwort schlägt den alten Stand")
	print("Kataloge: Grund je Katalog (Freund-Test 0.16.51: 0 von 4, ohne Grund)")
	var meta_ok := { "metas": [{ "id": "tt0111161", "name": "Film" }] }
	check(M.catalog_reason({ "ok": true, "code": 200, "data": meta_ok, "result": 0, "bytes": 900 }) == "", "Cinemeta-Antwort mit metas: ok")
	check(M.catalog_reason({ "ok": true, "code": 200, "data": { "metas": [] }, "result": 0, "bytes": 12 }) == "leer", "leere Liste: leer, kein Fehler")
	var h403 := M.catalog_reason({ "ok": false, "code": 403, "data": null, "result": 0, "bytes": 5300, "ctype": "text/html; charset=UTF-8" })
	check(h403 == "HTTP 403 (text/html, 6 KB)", "Sperrseite: HTTP-Code, Art und Größe (%s)" % h403)
	check(M.catalog_reason({ "ok": false, "code": 0, "result": HTTPRequest.RESULT_CANT_RESOLVE }) == "Name nicht auflösbar (DNS)", "DNS")
	check(M.catalog_reason({ "ok": false, "code": 0, "result": HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR }).begins_with("TLS-Fehler"), "TLS (Virenschutz mit HTTPS-Prüfung)")
	check(M.catalog_reason({ "ok": false, "code": 0, "result": HTTPRequest.RESULT_TIMEOUT }) == "Zeitüberschreitung", "Zeitlimit")
	var html := M.catalog_reason({ "ok": false, "code": 200, "data": null, "result": 0, "bytes": 2048, "ctype": "text/html" })
	check(html == "kein JSON (text/html, 2 KB)", "Portal- oder Fehlerseite mit 200: kein JSON (%s)" % html)
	check(M.catalog_reason({ "ok": true, "code": 200, "data": { "err": "not found" }, "result": 0, "bytes": 20 }).begins_with("Addon meldet Fehler"), "Fehler im JSON")
	check(M.catalog_reason({ "ok": true, "code": 200, "data": { "items": [] }, "result": 0, "bytes": 20 }).begins_with("ohne „metas“"), "falsches Format")
	check(M.catalog_reason({ "ok": true, "code": 200, "data": { "metasDetailed": [{ "id": "tt1" }] }, "result": 0, "bytes": 20 }) == ""
			and M.catalog_metas({ "metasDetailed": [{ "id": "tt1" }] }).size() == 1, "metasDetailed wird genommen")
	check(M.catalog_metas([{ "id": "tt1" }]).size() == 1 and M.catalog_metas(null).is_empty(), "bloße Liste ja, nichts nein")
	check(M.catalog_reason({ "ok": true, "code": 200, "data": { "metas": [{ "name": "ohne" }] }, "result": 0, "bytes": 20 }) == "Einträge ohne ID", "ohne IDs")
	var sj := [{ "done": true, "ok": false, "why": "HTTP 403 (text/html, 6 KB)" }, { "done": true, "ok": false, "why": "HTTP 403 (text/html, 6 KB)" },
		{ "done": true, "ok": false, "why": "Zeitüberschreitung" }, { "done": false, "ok": false, "why": "" }]
	check(M.catalog_summary(sj) == "Zugriff gesperrt", "Meldung: häufigster Grund, kurz und ohne Code (%s)" % M.catalog_summary(sj))
	check(M.catalog_summary([{ "done": true, "ok": false, "why": "HTTP 503 (text/html, 1 KB)" }]) == "Server antwortet nicht"
		and M.catalog_summary([{ "done": true, "ok": false, "why": "Zeitüberschreitung" }]) == "Zeitüberschreitung", "andere Codes in Worten, Netzgründe bleiben")
	check(M.catalog_summary([{ "done": true, "ok": true, "why": "" }]) == "", "alles ok: kein Grund")
	var mh2: Node = M.new()
	mh2._assemble_home(sj.map(func(j): return (j as Dictionary).merged({ "addon": ad, "cat": { "type": "movie", "id": "top", "name": "Popular" }, "items": [] })), {})
	check(str(mh2.error).contains("Zugriff gesperrt") and not str(mh2.error).contains("HTTP"), "Fehlermeldung nennt den Grund ohne Code: " + str(mh2.error))
	mh2.free()

	_folder_names()
	await _demo()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Demo-Daten (wie mit --demo): alles ohne Netz, ohne Bildadressen.
func _folder_names() -> void:
	print("Ordner: Namen der Reiter")
	var MC := preload("res://src/ui/layers/movie_catalog.gd")
	var adds := [
		{ "id": "a.trakt",
			"catalogs": [{ "id": "trakt.list.jane.best", "type": "movie", "name": "Beste Filme 2024" }, { "id": "x", "type": "series", "name": "Serienliste" }] },
		{ "id": "a.other", "catalogs": [{ "id": "nur.hier", "type": "movie", "name": "Woanders" }] },
	]
	check(str(MC.find_catalog(adds, "a.trakt", "movie", "trakt.list.jane.best").get("name", "")) == "Beste Filme 2024", "Katalog im eigenen Addon gefunden")
	check(str(MC.find_catalog(adds, "a.trakt", "Movies", "trakt.list.jane.best").get("name", "")) == "Beste Filme 2024",
			"Typ anders geschrieben: trotzdem gefunden")
	check(str(MC.find_catalog(adds, "a.trakt", "series", "x,genre=Drama").get("name", "")) == "Serienliste", "Kennung mit Komma: Teil davor zählt")
	check(str(MC.find_catalog(adds, "a.weg", "movie", "nur.hier").get("name", "")) == "Woanders", "Addon-Kennung anders: in allen Addons gesucht")
	check(MC.readable_id("trakt.list.jane.best-of-2024") == "Best of 2024" and MC.readable_id("trakt_list_12345") == "",
			"ohne Treffer: lesbarer Name aus der Kennung")
	var fo := { "id": "f9", "title": "Abend", "emoji": "🌙", "collection": "Samml", "backdrop": "", "logo": "",
		"sources": [{ "addon_id": "a.x", "type": "movie", "catalog_id": "top", "genre": "" },
			{ "addon_id": "a.x", "type": "series", "catalog_id": "top", "genre": "" }] }
	var fi: Dictionary = MC.folder_item(fo, "https://bild/titel.jpg")
	check(str(fi.name) == "🌙  Abend" and str(fi.kind) == "folder" and str(fi.id).begins_with("ordner:"), "Ordner für den Kopf: Name mit Emoji, eigene Kennung")
	check(str(fi.hero_line) == "Sammlung  ·  Samml  ·  2 Kataloge", "Zeile: Sammlung und Zahl der Kataloge: " + str(fi.hero_line))
	check(str(fi.background) == "https://bild/titel.jpg" and str(MC.folder_item(fo.merged({ "backdrop": "b.jpg" }, true), "x.jpg").background) == "b.jpg",
			"Ersatzbild nur ohne eigenes")
	check(str(MC.folder_item(fo.merged({ "hide_title": true }, true)).name) == "", "Name in Nuvio ausgeblendet: im Kopf auch")


func _demo() -> void:
	print("Demo")
	var md: Node = M.new()
	add_child(md)
	md._load_demo()
	var rows: Array = await md.home_rows()
	check(rows.size() == 5 and (rows[0].items as Array).size() == 10 and (rows[1].items as Array).size() == 6,
			"vier Reihen mit Filmen und Serien, dazu eine Sammlung")
	check(rows.size() == 5 and str(rows[4].get("kind", "")) == "folders" and (rows[4].folders as Array).size() == 3,
			"Sammlung „Streamingdienste“ als Ordner-Reihe mit drei Kacheln")
	var no_urls := true
	for r in rows:
		for it in r.items:
			if str(it.poster) + str(it.background) + str(it.logo) != "":
				no_urls = false
	check(no_urls, "keine Bildadressen in den Demo-Daten")
	var dfs: Array = rows[4].folders if rows.size() == 5 else []
	check(dfs.size() == 3 and dfs.all(func(f): return str(f.backdrop).ends_with(".png") and not str(f.backdrop).begins_with("http")),
			"Demo-Ordner: Hintergrundbilder als eigene Dateien, nicht aus dem Netz")
	var pi: Image = preload("res://src/core/movies_demo.gd").paint(0.63, "nacht", 160, 90)
	check(pi.get_width() == 160 and pi.get_height() == 90 and Media.vivid_color(pi) is Color, "gemaltes Ordner-Bild hat Größe und eine kräftige Farbe")
	check(md.hero_items().size() == 6 and md.addons.size() == 4 and md.plugin_repos.size() == 1, "großes Bild, Addons, Plugins")
	var sm: Dictionary = await md.meta("series", "tt9200001")
	check(sm.seasons == [1, 2, 3, 0] and (sm.videos as Array).size() == 17, "Serie mit drei Staffeln und Special")
	var lj: Dictionary = await md.meta("series", "tt9200005")
	check(bool(lj.videos[2].available) and not bool(lj.videos[3].available), "Lichtjahre: letzte Folgen noch nicht ausgestrahlt")
	var parts: Array = []
	var sl: Array = await md.streams("series", "tt9200001:1:1", func(l: Array) -> void: parts.append(l.size()))
	check(sl.size() == 6 and parts.size() == 3 and not sl.any(func(s): return bool(s.is_p2p)),
			"Streams aus zwei Addons und einem Plugin, P2P weg (%d, %s)" % [sl.size(), str(parts)])
	check(bool(sl[0].cached) and int(sl[1].quality) == 2160 and str(sl[0].url).contains("tt9200001:1:1"), "gecacht zuerst, dann 4K")
	var st: Array = md.stream_sources_status()
	check(st.size() == 4 and str(st[3].state) == "fehler" and str(st[3].error) != "", "kaputter Scraper meldet sich")
	var cw: Array = md.continue_watching()
	var ids: Array = cw.map(func(c): return "%s/%s/%s" % [c.id, c.video_id, "n" if bool(c.next_up) else "a"])
	check(ids == ["tt9100005/tt9100005/a", "tt9200002/tt9200002:1:4/a", "tt9200001/tt9200001:2:3/n"], "Weiterschauen: " + str(ids))
	check(md.library_items().size() == 3 and md.in_library("tt9200001"), "Bibliothek")
	var found: Array = await md.search("nord")
	check(found.size() == 1 and str(found[0].items[0].name) == "Nordlicht", "Suche")
	var subs: Array = await md.subtitles("movie", "tt9100001")
	check(subs.size() == 2, "Untertitel")
	check((await md.install_addon("https://x.example/manifest.json")).contains("Demo"), "im Demo-Modus kein Installieren")
	print("Quellen einer Antwort: begrenzt und über mehrere Bilder")
	var viele: Array = []
	for i in 1000:
		viele.append({ "url": "https://x.example/%d.mkv" % i, "name": "Quelle %d German 1080p" % i })
	viele[3] = "kaputt"
	var addon := { "id": "t", "name": "T" }
	var lesen := func(s: Dictionary, i: int) -> Dictionary: return M.parse_stream(s, addon, i)
	var bild0 := Engine.get_process_frames()
	var gelesen: Array = await md._streams_lesen({ "id": int(md._job_id) }, viele, lesen)
	var bilder := Engine.get_process_frames() - bild0
	check(gelesen.size() == M.STREAMS_JE_QUELLE - 1 and str(gelesen[0].langs) == str(["DE"]),
			"höchstens %d je Antwort, Kaputtes fällt weg (%d von 1000)" % [M.STREAMS_JE_QUELLE, gelesen.size()])
	check(bilder >= int(M.STREAMS_JE_QUELLE / float(M.STREAMS_JE_BILD)) - 1, "über mehrere Bilder verteilt (%d Bilder)" % bilder)
	var kurz: Array = await md._streams_lesen({ "id": int(md._job_id) - 1 }, viele, lesen)
	check(kurz.size() <= M.STREAMS_JE_BILD, "läuft inzwischen eine andere Suche, hört der Lauf nach dem ersten Stück auf (%d)" % kurz.size())
	md.queue_free()
