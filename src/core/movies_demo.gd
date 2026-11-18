extends RefCounted
## Demo-Daten für „Filme“ (Start mit --demo): ausgedachte Filme und Serien mit Staffeln, Streams
## aus zwei Addons und einem Plugin, angefangene Titel und „Als Nächstes“. Keine Netz-Adressen für
## Bilder – die Oberfläche zeigt dann ihre eigenen Farbflächen. Nur die Ordner der Sammlung haben
## Hintergrundbilder: selbst gemalte Landschaften (paint_art), keine Bilder der Dienste.

const Arbeit := preload("res://src/core/arbeit.gd")

const MOVIES := [
	["tt9100001", "Nordlicht", "2024", "7.8", ["Drama", "Abenteuer"],
		"Eine Meteorologin folgt im Winter einem rätselhaften Lichtsignal bis an den Rand der Arktis.", "124 min"],
	["tt9100002", "Die letzte Fähre", "2023", "7.1", ["Thriller", "Krimi"],
		"Auf der letzten Überfahrt des Jahres verschwindet ein Passagier – und niemand will ihn gesehen haben.", "98 min"],
	["tt9100003", "Stahlherz", "2025", "6.9", ["Action", "Science-Fiction"],
		"Ein Bergungsteam findet in einer stillgelegten Fabrik eine Maschine, die noch arbeitet.", "116 min"],
	["tt9100004", "Sommer in Lissabon", "2022", "7.3", ["Romantik", "Komödie"],
		"Zwei Fremde teilen sich aus Versehen dieselbe Ferienwohnung – für einen ganzen Sommer.", "104 min"],
	["tt9100005", "Das Archiv", "2024", "8.1", ["Mystery", "Drama"],
		"Eine Archivarin entdeckt in alten Akten Hinweise auf einen Fall, der nie abgeschlossen wurde.", "131 min"],
	["tt9100006", "Funkenflug", "2021", "6.5", ["Animation", "Familie"], "Ein kleiner Glühwurm will das größte Lichterfest des Waldes retten.", "89 min"],
	["tt9100007", "Kaltfront", "2025", "7.0", ["Thriller"], "Ein Schneesturm schließt sechs Fremde in einer Berghütte ein. Einer von ihnen lügt.", "102 min"],
	["tt9100008", "Die Kartografin", "2023", "7.6", ["Historie", "Drama"], "1820: Eine junge Frau vermisst heimlich ein Land, das es auf keiner Karte gibt.",
		"138 min"],
	["tt9100009", "Nachtzug nach Triest", "2022", "7.2", ["Krimi", "Mystery"], "Ein Schlafwagen, ein vertauschter Koffer und eine Nacht, die nicht enden will.",
		"110 min"],
	["tt9100010", "Lautlos", "2024", "6.8", ["Horror"], "In einem Dorf, in dem niemand spricht, ist jedes Geräusch eine Gefahr.", "95 min"],
]

## id, Name, Jahr, Bewertung, Genres, Beschreibung, Folgen je Staffel, Start der ersten Staffel (Tage zurück)
const SERIES := [
	["tt9200001", "Hafenstadt", "2021", "8.4", ["Krimi", "Drama"],
		"Eine Kommissarin kehrt in ihre Heimatstadt zurück, wo jeder jeden kennt – und jeder etwas verbirgt.", [6, 6, 4], 1500],
	["tt9200002", "Funkstille", "2023", "7.9", ["Science-Fiction", "Mystery"], "Ein Funker empfängt Nachrichten, die erst in dreißig Jahren gesendet werden.",
		[8, 8], 400],
	["tt9200003", "Die Gärtnerei", "2022", "7.4", ["Komödie"], "Vier Freundinnen übernehmen eine Gärtnerei, von Pflanzen haben sie keine Ahnung.", [10], 900],
	["tt9200004", "Grenzland", "2020", "8.0", ["Western", "Drama"], "Zwei Familien, ein Tal und ein Streit, der drei Generationen dauert.", [6, 6, 6], 2000],
	["tt9200005", "Lichtjahre", "2025", "7.2", ["Science-Fiction"], "Die Besatzung eines Frachters erwacht – zweihundert Jahre zu spät.", [5], 20],
	["tt9200006", "Unter Wasser", "2019", "7.7", ["Dokumentation"], "Eine Reise zu den Lebewesen der Tiefsee, die kaum ein Mensch je gesehen hat.", [4, 4], 2400],
]

const EP_TITLES := ["Ankunft", "Spuren", "Die Nacht davor", "Gegenwind", "Alte Rechnungen", "Ebbe", "Leuchtfeuer", "Das Versprechen",
	"Falsche Fährte", "Heimkehr", "Unter Verdacht", "Die Wahrheit"]


## Hintergrundbilder der Demo-Ordner: Farbton von Himmel und Land, Art der Landschaft.
const ART := {
	"f1": [0.98, "duenen"],
	"f2": [0.63, "nacht"],
	"f3": [0.50, "meer"],
}
const ART_W := 640
const ART_H := 360


static func art_path(id: String) -> String:
	return Config.path("cache/demo/ordner_%s.png" % id)


## Fehlende Ordner-Bilder im Hintergrund malen. Sie liegen danach als Dateien
## im Cache und laden wie echte Bilder – Farbe und Verkleinern macht Media wie sonst auch.
## Den Pfad bestimmt der Hauptthread: Der Thread fasst Config nie an (beim Beenden ist es schon weg).
static func paint_art() -> void:
	DirAccess.make_dir_recursive_absolute(art_path("x").get_base_dir())
	for id in ART:
		var path := art_path(str(id))
		if not FileAccess.file_exists(path):
			Arbeit.los(_paint.bind(str(id), path))


static func _paint(id: String, path: String) -> void:
	var img := paint(float(ART[id][0]), str(ART[id][1]), ART_W, ART_H)
	# Erst fertig schreiben, dann umbenennen: nie ein halbes Bild laden.
	if img.save_png(path + ".tmp") == OK:
		DirAccess.rename_absolute(path + ".tmp", path)


## Eine ruhige Landschaft: Himmel mit Licht, Hügelketten (hinten blass, vorn dunkel), je nach Art
## Dünen im Abendrot, Berge unter Sternen oder ein Meer mit Lichtspur.
static func paint(hue: float, kind: String, w: int, h: int) -> Image:
	var horizon := 0.62 if kind == "meer" else 0.58
	var sun := Vector2(0.70, 0.50) if kind != "nacht" else Vector2(0.74, 0.22)
	var sky_top := Color.from_hsv(fposmod(hue + 0.04, 1.0), 0.70, 0.16 if kind == "nacht" else 0.30)
	var sky_low := Color.from_hsv(fposmod(hue - 0.05, 1.0), 0.55, 0.42 if kind == "nacht" else 0.92)
	var glow := Color.from_hsv(fposmod(hue + 0.08, 1.0), 0.25 if kind == "nacht" else 0.45, 1.0)
	# Höhen der Hügelketten je Spalte vorab (hinten → vorn).
	var ridges: Array = []
	var layers := 0 if kind == "meer" else 3
	for l in layers:
		var hs := PackedFloat32Array()
		hs.resize(w)
		var base := horizon + 0.02 + l * 0.11
		var amp := (0.10 if kind == "nacht" else 0.05) * (1.0 - l * 0.25)
		for x in w:
			var u := float(x) / float(w)
			var y := base - amp * (0.6 * sin(u * (3.0 + l * 1.7) * TAU + l * 1.3) + 0.4 * sin(u * (7.0 + l * 2.3) * TAU + l * 0.7))
			if kind == "nacht":
				y -= amp * 0.5 * absf(sin(u * (11.0 + l) * TAU))
			hs[x] = y
		ridges.append(hs)
	var data := PackedByteArray()
	data.resize(w * h * 3)
	var i := 0
	for y in h:
		var v := float(y) / float(h - 1)
		for x in w:
			var u := float(x) / float(w - 1)
			var c: Color
			var d := Vector2((u - sun.x) * float(w) / float(h), v - sun.y).length()
			if v < horizon or kind != "meer":
				c = sky_top.lerp(sky_low, pow(clampf(v / horizon, 0.0, 1.0), 1.6))
				c = c.lerp(glow, clampf(1.0 - d / 0.55, 0.0, 1.0) ** 2 * 0.55)
				var disc := 0.05 if kind == "nacht" else 0.09
				c = c.lerp(Color(1.0, 0.97, 0.9), clampf((disc - d) / 0.006, 0.0, 1.0) * 0.9)
				if kind == "nacht" and v < horizon:
					var n := float(hash(Vector2i(x, y)) & 0xFFFF) / 65535.0
					if n > 0.997:
						c = c.lerp(Color(1, 1, 1), 0.85 * (1.0 - v / horizon))
			else:
				# Wasser: gespiegelter Himmel, dunkler nach vorn, mit Lichtspur unter der Sonne.
				var mv := (v - horizon) / (1.0 - horizon)
				c = sky_low.lerp(sky_top, clampf(mv * 1.4, 0.0, 1.0)).darkened(0.35 + mv * 0.4)
				var lane := clampf(1.0 - absf(u - sun.x) * float(w) / float(h) / (0.05 + mv * 0.25), 0.0, 1.0)
				var wave := 0.5 + 0.5 * sin(v * 260.0 + sin(u * 40.0) * 2.0)
				c = c.lerp(glow, lane * wave * (0.75 - mv * 0.4))
			for l in layers:
				var top: float = (ridges[l] as PackedFloat32Array)[x]
				# Kante weich über einen Bildpunkt (sonst Treppen, wenn das Bild groß gezogen wird).
				var cov := clampf((v - top) * float(h) + 0.5, 0.0, 1.0)
				if cov > 0.0:
					var land := Color.from_hsv(fposmod(hue + 0.02 * l, 1.0), 0.55, 0.30 - l * 0.09)
					# Hintere Ketten im Dunst: der Himmelsfarbe näher.
					land = land.lerp(sky_low, 0.45 - l * 0.2)
					c = c.lerp(land.darkened(clampf((v - top) * 1.5, 0.0, 0.5)), cov)
			data[i] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			data[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			data[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			i += 3
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)


static func _date(now: int, days_ago: int) -> String:
	return Time.get_datetime_string_from_unix_time(now - days_ago * 86400).substr(0, 10) + "T00:00:00.000Z"


## Wie ein echter Dienst liefert die Demo ihre Angaben in der Sprache der Oberfläche (Titel und
## Beschreibungen stehen im Katalog); die Oberfläche zeigt sie unübersetzt.
static func _preview(row: Array, type: String) -> Dictionary:
	return {
		"id": row[0], "type": type, "name": _t(row[1]), "poster": "", "background": "", "logo": "",
		"description": _t(row[5]), "year": row[2], "release_info": row[2], "imdb_rating": row[3],
		"genres": (row[4] as Array).map(func(g: Variant) -> String: return _t(g)), "addon_id": "demo.cinemeta", "poster_shape": "",
	}


static func _meta(row: Array, type: String, now: int) -> Dictionary:
	var m := _preview(row, type)
	m.merge({
		"runtime": row[6] if type == "movie" else "48 min", "released": str(row[2]) + "-03-14T00:00:00.000Z",
		"cast": ["Mara Lindqvist", "Jonas Feld", "Ada Brückner", "Paul Okafor"], "director": ["Lea Sommer"], "writer": ["Tom Weidner"],
		"trailers": [], "links": [], "country": _t("Deutschland"), "awards": "", "videos": [], "seasons": [],
		"imdb_id": row[0], "tmdb_id": str(int(str(row[0]).substr(2)) % 100000), "default_video_id": row[0] if type == "movie" else "",
	}, true)
	if type == "series":
		var counts: Array = row[6]
		var start := int(row[7])
		var vids: Array = []
		var day := start
		for s in counts.size():
			for e in int(counts[s]):
				var rel := _date(now, day)
				vids.append({ "id": "%s:%d:%d" % [row[0], s + 1, e + 1], "title": _t(EP_TITLES[(s * 3 + e) % EP_TITLES.size()]),
					"season": s + 1, "episode": e + 1, "released": rel, "thumbnail": "",
					"overview": _t("Folge %d der %d. Staffel von „%s“.") % [e + 1, s + 1, _t(row[1])], "available": day >= 0 })
				day -= 7
			day -= 120
		# Specials ans Ende (wie Cinemeta).
		vids.append({ "id": "%s:0:1" % row[0], "title": _t("Hinter den Kulissen"), "season": 0, "episode": 1, "released": _date(now, start),
			"thumbnail": "", "overview": _t("Ein Blick hinter die Kulissen."), "available": true })
		m.videos = vids
		var seasons: Array = []
		for s in counts.size():
			seasons.append(s + 1)
		seasons.append(0)
		m.seasons = seasons
	return m


static func _t(x: Variant) -> String:
	return TranslationServer.translate(str(x))


static func build(now: int) -> Dictionary:
	var metas := {}
	var movies: Array = []
	var series: Array = []
	for row in MOVIES:
		movies.append(_preview(row, "movie"))
		metas[row[0]] = _meta(row, "movie", now)
	for row in SERIES:
		series.append(_preview(row, "series"))
		metas[row[0]] = _meta(row, "series", now)
	var by_rating := func(list: Array) -> Array:
		var l := list.duplicate(true)
		l.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.imdb_rating) > float(b.imdb_rating))
		return l
	var rows := [
		{ "key": "demo.cinemeta/movie/top", "title": "Beliebt – Filme", "type": "movie", "addon_id": "demo.cinemeta", "catalog_id": "top", "extra": {},
			"items": movies, "see_all": true },
		{ "key": "demo.cinemeta/series/top", "title": "Beliebt – Serien", "type": "series", "addon_id": "demo.cinemeta", "catalog_id": "top", "extra": {},
			"items": series, "see_all": true },
		{ "key": "demo.cinemeta/movie/imdbRating", "title": "Empfohlen – Filme", "type": "movie", "addon_id": "demo.cinemeta", "catalog_id": "imdbRating",
			"extra": {}, "items": by_rating.call(movies), "see_all": true },
		{ "key": "demo.cinemeta/series/imdbRating", "title": "Empfohlen – Serien", "type": "series", "addon_id": "demo.cinemeta", "catalog_id": "imdbRating",
			"extra": {}, "items": by_rating.call(series), "see_all": true },
		# Nuvio-Sammlung als Ordner (wie in Nuvio TV): Kacheln, A öffnet den Ordner mit seinen Katalogen.
		{ "key": "collection_demo", "title": "Streamingdienste", "kind": "folders", "show_all": true, "items": [], "folders": [
			{ "id": "f1", "backdrop": art_path("f1"), "title": "Netflix", "cover": "", "emoji": "", "shape": "LANDSCAPE", "hide_title": false,
				"collection": "Streamingdienste",
				"sources": [{ "addon_id": "demo.cinemeta", "type": "movie", "catalog_id": "top", "genre": "" },
					{ "addon_id": "demo.cinemeta", "type": "series", "catalog_id": "top", "genre": "" }] },
			{ "id": "f2", "backdrop": art_path("f2"), "title": "Disney+", "cover": "", "emoji": "", "shape": "LANDSCAPE", "hide_title": false,
				"collection": "Streamingdienste",
				"sources": [{ "addon_id": "demo.cinemeta", "type": "movie", "catalog_id": "imdbRating", "genre": "" }] },
			{ "id": "f3", "backdrop": art_path("f3"), "title": "Prime Video", "cover": "", "emoji": "", "shape": "LANDSCAPE", "hide_title": false,
				"collection": "Streamingdienste",
				"sources": [{ "addon_id": "demo.cinemeta", "type": "series", "catalog_id": "imdbRating", "genre": "" }] },
		] },
	]
	var hero: Array = []
	for i in 3:
		hero.append(movies[i * 2 + 1].duplicate(true))
		hero.append(series[i].duplicate(true))
	var cm := preload("res://src/core/movies.gd").CINEMETA_MANIFEST.duplicate(true)
	cm["id"] = "demo.cinemeta"
	var addons := [
		cm,
		{ "id": "demo.streams", "version": "1.2.0", "name": "Mein Stream-Addon", "description": "Ein selbst eingetragenes Addon mit direkten Streams.",
			"types": ["movie", "series"], "idPrefixes": ["tt"], "resources": ["stream"], "catalogs": [], "behaviorHints": { "configurable": true } },
		{ "id": "demo.zweit", "version": "0.4.1", "name": "Zweites Addon", "description": "Noch ein Addon mit Streams.",
			"types": ["movie", "series"], "idPrefixes": ["tt"], "resources": ["stream"], "catalogs": [] },
		{ "id": "demo.subs", "version": "1.0.0", "name": "Untertitel-Addon", "description": "Untertitel in vielen Sprachen.",
			"types": ["movie", "series"], "idPrefixes": ["tt"], "resources": ["subtitles"], "catalogs": [] },
	]
	var headers := { "User-Agent": "Uzai-Demo", "Referer": "https://example.invalid/" }
	var stream_sources := [
		{ "id": "demo.streams", "name": "Mein Stream-Addon", "kind": "addon", "streams": [
			{ "name": "Mein Addon\n4K DV | HDR", "url": "demo://stream/{id}/2160",
				"title": "Titel.2024.German.DL.2160p.WEB-DL.DV.HDR.HEVC.DDP5.1.Atmos-UZAI\n👤 154 💾 18.4 GB ⚙️ Beispiel-Tracker\nMulti Audio / 🇩🇪 / 🇬🇧",
				"behaviorHints": { "bingeGroup": "demo-2160", "filename": "Titel.2024.German.DL.2160p.WEB-DL.DV.HDR.HEVC.DDP5.1.Atmos-UZAI.mkv" } },
			{ "name": "[RD+] Mein Addon\n1080p", "title": "Titel.2024.1080p.BluRay.x264.DTS-HD.MA.5.1-GRP\n💾 9.2 GB ⚙️ Beispiel-Tracker\n🇬🇧 / 🇫🇷",
				"url": "demo://stream/{id}/1080rd", "behaviorHints": { "bingeGroup": "demo-1080", "filename": "Titel.2024.1080p.BluRay.x264.DTS-HD.MA.5.1-GRP.mkv" } },
			{ "name": "Mein Addon\n1080p", "url": "demo://stream/{id}/1080",
				"description": "📄 Titel.2024.1080p.WEB-DL.HDR10+.HEVC.EAC3.5.1-GRP.mkv\n📹 HEVC • 10bit • HDR10+\n🔊 DD+ 5.1\n🗣️ 🇬🇧\n💾 5.6 GB 👥 88",
				"behaviorHints": { "bingeGroup": "demo-1080b", "proxyHeaders": { "request": headers } } },
			{ "name": "Mein Addon\n720p", "description": "WEBRip 720p · 1.4 GB", "url": "demo://stream/{id}/720" },
			{ "name": "P2P\n1080p", "title": "Titel.2024.1080p 💾 4.1 GB", "infoHash": "0123456789abcdef0123456789abcdef01234567" },
		] },
		{ "id": "demo.zweit", "name": "Zweites Addon", "kind": "addon", "streams": [
			{ "name": "Zweit\nSD", "title": "Titel.2024.iTALiAN.480p.DVDRip.XviD-GRP\n700 MB", "url": "demo://zweit/{id}/480",
				"subtitles": [{ "id": "z-de", "url": "demo://zweit/de.srt", "lang": "ger" }] },
		] },
		{ "id": "plugin:rdemo:beispiel", "name": "Beispiel-Scraper", "kind": "plugin", "streams": [
			{ "name": "Beispiel", "title": "Titel 1080p", "url": "demo://plugin/{id}/1080", "quality": "1080p", "size": "2.3 GB", "language": "Deutsch",
				"headers": headers },
		] },
		{ "id": "plugin:rdemo:kaputt", "name": "Kaputter Scraper", "kind": "plugin", "error": "Zeitlimit (60 s) überschritten", "streams": [] },
	]
	var plugin_repos := [
		{ "id": "rdemo", "name": "Beispiel-Repository", "url": "https://example.invalid/manifest.json", "enabled": true, "version": "1.0.0",
			"description": "Nur für den Demo-Modus.", "scrapers": [
				{ "id": "rdemo:beispiel", "name": "Beispiel-Scraper", "version": "1.0.0", "description": "", "types": ["movie", "tv"], "logo": "", "enabled": true,
					"formats": [], "languages": ["de"], "settings": {} },
				{ "id": "rdemo:kaputt", "name": "Kaputter Scraper", "version": "0.9.0", "description": "", "types": ["movie", "tv"], "logo": "", "enabled": true,
					"formats": [], "languages": [], "settings": {} },
				{ "id": "rdemo:aus", "name": "Abgeschalteter Scraper", "version": "2.1.0", "description": "", "types": ["movie"], "logo": "", "enabled": false,
					"formats": [], "languages": [], "settings": {} },
			] },
	]
	# Fortschritt: ein Film zur Hälfte, eine Serie mitten in Staffel 1, eine mit „Als Nächstes“.
	var items := {}
	for id in ["tt9100005", "tt9200001", "tt9200002", "tt9200004"]:
		var m: Dictionary = metas[id]
		var it := m.duplicate(true)
		for k in ["runtime", "released", "cast", "director", "writer", "trailers", "links", "country", "awards", "seasons", "default_video_id", "imdb_id"]:
			it.erase(k)
		var vids: Array = []
		for v in m.videos:
			vids.append({ "id": v.id, "season": v.season, "episode": v.episode, "title": v.title, "released": v.released, "thumbnail": "", "available": v.available })
		it.videos = vids
		items[id] = it
	var progress := {
		"tt9100005": {
			"tt9100005": { "position": 3140.0, "duration": 7860.0, "watched": false, "updated": now - 3600, "season": 0, "episode": 0, "title": "", "thumbnail": "" } },
		"tt9200002": {
			"tt9200002:1:4": { "position": 1010.0, "duration": 2880.0, "watched": false, "updated": now - 7200, "season": 1, "episode": 4, "title": _t(EP_TITLES[3]),
			"thumbnail": "" } },
		"tt9200001": {},
		"tt9200004": {
			"tt9200004:3:6": { "position": 0.0, "duration": 2900.0, "watched": true, "updated": now - 86400 * 9, "season": 3, "episode": 6, "title": "",
			"thumbnail": "" } },
	}
	for i in 8:
		var s := 1 if i < 6 else 2
		var e := i + 1 if i < 6 else i - 5
		progress["tt9200001"]["tt9200001:%d:%d" % [s, e]] = { "position": 0.0, "duration": 2880.0, "watched": true,
			"updated": now - 86400 * 2 - (8 - i) * 3000, "season": s, "episode": e, "title": _t(EP_TITLES[((s - 1) * 3 + e - 1) % EP_TITLES.size()]), "thumbnail": "" }
	var library: Array = []
	for id in ["tt9100001", "tt9200001", "tt9200002"]:
		var p := (metas[id] as Dictionary)
		library.append({ "id": p.id, "type": p.type, "name": p.name, "poster": "", "background": "", "logo": "", "description": p.description,
			"year": p.year, "imdb_rating": p.imdb_rating, "genres": (p.genres as Array).duplicate(), "addon_id": "demo.cinemeta", "added": now - 86400 * 3 })
	return {
		"addons": addons, "rows": rows, "hero": hero, "metas": metas, "stream_sources": stream_sources, "plugin_repos": plugin_repos,
		"data": { "library": library, "progress": progress, "items": items, "hidden": {}, "dismissed": [] },
	}
