extends Node
## Filme-Quellen (Roadmap 35) ohne Netz: Plex, Jellyfin/Emby und Stremio-Konto mit Antworten im
## Format der echten Schnittstellen, dazu bösartige Antworten (falsche Typen, Riesenlisten,
## fremde Adressen, Pfad-Tricks, Steuerzeichen), Adressen und Heimnetz, Altersfreigaben und der
## Kinderfilter, Weiterschauen aus mehreren Quellen.
## Aufruf: godot --headless --path . res://tests/logic_medienquellen.tscn

const B := preload("res://src/core/medienquellen_basis.gd")
const Plex := preload("res://src/core/medienquellen_plex.gd")
const Jf := preload("res://src/core/medienquellen_jellyfin.gd")
const St := preload("res://src/core/medienquellen_stremio.gd")
const M := preload("res://src/core/movies.gd")
const Vault := preload("res://src/core/vault.gd")
const Konten := preload("res://src/core/konten.gd")

const O := "https://192-168-1-10.0123456789abcdef.plex.direct:32400"
const JB := "http://192.168.1.20:8096"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_basis()
	_ratings()
	_plex()
	_jellyfin()
	_stremio()
	_hostile()
	_continue()
	_accounts()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _j(v: Variant) -> PackedByteArray:
	return JSON.stringify(v).to_utf8_buffer()


# --- Basis ---------------------------------------------------------------------------------------

func _basis() -> void:
	print("Lesen und Adressen")
	check(B.json(_j({ "a": 1 })) is Dictionary and B.json("kaputt{".to_utf8_buffer()) == null and B.json(PackedByteArray()) == null, "JSON: gut, kaputt, leer")
	check(B.json(_j({ "a": "x".repeat(200) }), 100) == null, "JSON über der Größengrenze wird nicht gelesen")
	check(B.text("Ti" + char(0) + "tel" + char(0x202E) + char(7) + " ") == "Titel" and B.text(12) == "12" and B.text(3.0) == "3" and B.text(["x"]) == ""
			and B.text(null) == "", "Text ohne Steuerzeichen und Umkehrzeichen, nur Text/Zahl")
	check(B.text("x".repeat(1000)).length() == B.TEXT_MAX and B.text("a\nb") == "a b" and B.text("a\nb", B.DESC_MAX) == "a\nb",
			"Länge begrenzt, Zeilenumbruch nur in Beschreibungen")
	check(B.num("42") == 42 and B.num("4x", -1) == -1 and B.num(1e300, -1) == -1 and B.num(null, 7) == 7, "Zahlen streng")
	check(B.ident("abc123", "alnum") == "abc123" and B.ident("ab/c", "alnum") == "" and B.ident("12", "digits", 3) == ""
			and B.ident("dead-BEEF", "hex") == "dead-BEEF", "Kennungen nur aus erlaubten Zeichen")
	check(B.iso_time("2026-10-01T18:30:00.000Z") == Time.get_unix_time_from_datetime_string("2026-10-01T18:30:00") and B.iso_time("gestern") == 0, "ISO-Zeit")
	var p := B.parse_server("192.168.1.20", 8096)
	check(str(p.get("base", "")) == "http://192.168.1.20:8096" and str(p.scheme) == "http", "privat ohne Schema: http mit Standardport")
	check(str(B.parse_server("medien.example.de").get("base", "")) == "https://medien.example.de", "Name ohne Schema: https")
	check(str(B.parse_server("https://medien.example.de:8920/jellyfin/").get("base", "")) == "https://medien.example.de:8920/jellyfin",
			"Unterpfad und Port bleiben")
	check(str(B.parse_server("https://medien.example.de/jellyfin").get("origin", "")) == "https://medien.example.de", "Ursprung ohne Pfad")
	check(B.parse_server("http://user:pw@10.0.0.2").is_empty() and B.parse_server("ftp://10.0.0.2").is_empty()
			and B.parse_server("http://10.0.0.2:99999").is_empty(), "Zugangsdaten in der Adresse, fremdes Schema, falscher Port: abgelehnt")
	check(B.parse_server("http://a_b.example").is_empty() and B.parse_server("http://10.0.0.2/../x").is_empty()
			and B.parse_server("http://[fe80::1]:8096").get("host", "") == "fe80::1", "Hostname-Zeichen, Pfad-Tricks, IPv6")
	check(B.is_private_ip("10.1.2.3") and B.is_private_ip("172.20.0.1") and B.is_private_ip("192.168.0.9") and B.is_private_ip("169.254.1.1")
			and B.is_private_ip("fd12::1") and B.is_private_ip("fe80::2"), "private Adressen")
	check(not B.is_private_ip("172.32.0.1") and not B.is_private_ip("8.8.8.8") and not B.is_private_ip("2001:db8::1") and not B.is_private_ip("heimserver")
			and not B.is_private_ip("127.0.0.1"), "öffentliche Adressen, Namen und (ohne Test) Loopback nicht")
	check(B.safe_path("/library/metadata/1/thumb/2") != "" and B.safe_path("//evil.example/x") == "" and B.safe_path("/a/../b") == ""
			and B.safe_path("https://x/y") == "" and B.safe_path("/a\\b") == "" and B.safe_path("/a@b") == "" and B.safe_path("a/b") == "", "Server-Pfade streng")
	check(B.allowed_image("https://metadata-static.plex.tv/a/b.jpg", ["plex.tv"]) != ""
			and B.allowed_image("https://plex.tv.evil.example/a.jpg", ["plex.tv"]) == "" and B.allowed_image("http://metadata-static.plex.tv/a.jpg", ["plex.tv"]) == "",
			"fremde Bilder nur von *.plex.tv über https")
	check(B.origin_of("https://Host.Example:8920/x?y") == "https://host.example:8920" and Net.origin("https://Host.Example:8920/x") == "https://host.example:8920",
			"Ursprung einer Adresse")
	check(B.owner_of("plex:12") == "plex" and B.owner_of("jf:ab") == "jellyfin" and B.owner_of("emby:9") == "emby" and B.owner_of("tt123") == ""
			and B.owner_of_addon("quelle:stremio") == "stremio" and B.owner_of_addon("quelle:x") == "", "Kennungen den Quellen zuordnen")


# --- Freigaben -----------------------------------------------------------------------------------

func _ratings() -> void:
	print("Altersfreigaben und Kinderfilter")
	var cases := { "de/12": 12, "de/FSK 16": 16, "FSK-18": 18, "FSK 0": 0, "DE-6": 6, "PG-13": 12, "PG": 6, "G": 0, "R": 16, "NC-17": 18,
		"TV-Y7": 6, "TV-14": 16, "TV-MA": 18, "gb/15": 16, "UK-12A": 12, "12": 12, "7": 12, "18+": 18, "MA15+": 16, "AB 12 JAHREN": 12,
		"NR": -1, "Not Rated": -1, "": -1, "Approved": -1, "nonsense": -1, "de/123": -1 }
	var bad := []
	for k in cases:
		if B.age_of(k) != int(cases[k]):
			bad.append("%s→%d" % [k, B.age_of(k)])
	check(bad.is_empty(), "Freigaben auf USK-Stufen %s" % str(bad))
	check(B.rating_label("de/12") == "FSK 12" and B.rating_label("us/PG-13") == "PG-13" and B.rating_label("FSK-16") == "FSK-16", "Freigabe zum Anzeigen")
	var rules := { "age": 6, "unknown": false }
	check(B.kid_allows({ "age": 6 }, rules) and not B.kid_allows({ "age": 12 }, rules), "mit Freigabe: nur bis zur Altersstufe")
	check(not B.kid_allows({ "age": -1, "genres": ["Drama"] }, rules) and B.kid_allows({ "age": -1, "family": true }, rules)
			and B.kid_allows({ "genres": ["Familie"] }, rules), "ohne Freigabe: nur Familie/Kinder")
	check(not B.kid_allows({ "age": 16, "family": true }, rules), "Freigabe schlägt Familien-Bibliothek")
	check(B.kid_allows({ "age": -1 }, { "age": 12, "unknown": true }), "„Ohne Angabe erlauben“ der Eltern gilt")
	check(B.family_word("Kinderfilme") and B.family_word("Filme für Kids") and B.family_word("Familie & Freunde") and not B.family_word("Kinderwagen-Doku")
			and not B.family_word("Horror"), "Familien-Bibliotheken am Namen")
	var rows := [{ "key": "a", "items": [{ "id": "1", "age": 18 }, { "id": "2", "age": 0 }] }, { "key": "b", "items": [{ "id": "3", "age": 16 }] },
			{ "key": "c", "kind": "folders", "folders": [{}] },
		{ "key": "d", "kind": "folders", "source": "plex", "folders": [{ "id": "lib:1" }, { "id": "lib:3", "family": true }] },
			{ "key": "e", "kind": "folders", "source": "plex", "folders": [{ "id": "coll:9" }] }]
	var kr := B.kid_rows(rows, rules)
	check(kr.size() == 3 and (kr[0].items as Array).size() == 1 and str(kr[0].items[0].id) == "2" and str(kr[1].kind) == "folders",
			"Reihen: gefiltert, leere weg, Nuvio-Ordner bleiben")
	check(str(kr[2].key) == "d" and (kr[2].folders as Array).size() == 1 and str(kr[2].folders[0].id) == "lib:3",
			"Server-Ordner: nur Kinder-/Familien-Bibliotheken")
	check(B.kid_rows(rows, {}).size() == 5 and B.kid_filter([{ "age": 18 }], {}).size() == 1, "ohne Kinderprofil bleibt alles")


# --- Plex ----------------------------------------------------------------------------------------

func _plex() -> void:
	print("Plex")
	check(
			Plex.parse_pin({ "id": 4812, "code": "k7qz", "product": "Uzai", "trusted": false, "clientIdentifier": "c", "expiresIn": 900,
			"authToken": null }) == { "id": 4812, "code": "K7QZ", "token": "", "expires": 900 }, "PIN wartet")
	check(str(Plex.parse_pin({ "id": 4812, "code": "K7QZ", "authToken": "xyzAuthToken-123_" }).token) == "xyzAuthToken-123_", "PIN bestätigt: Schlüssel")
	check(Plex.parse_pin({ "id": "x", "code": "K7QZ" }).is_empty() and Plex.parse_pin({ "id": 1, "code": "K7/Z" }).is_empty()
			and str(Plex.parse_pin({ "id": 1, "code": "ABCD", "authToken": "a b" }).token) == "", "kaputte PIN abgelehnt, Schlüssel mit Leerzeichen nicht")
	var resources := [
		{ "name": "Wohnzimmer", "product": "Plex Media Server", "provides": "server", "owned": true, "clientIdentifier": "abcdef0123456789",
			"accessToken": "ownerToken123",
			"presence": true, "connections": [
				{ "protocol": "http", "address": "203.0.113.5", "port": 32400, "uri": "http://203.0.113.5:32400", "local": false, "relay": false },
				{ "protocol": "https", "address": "203.0.113.5", "port": 32400, "uri": "https://203-0-113-5.0123456789abcdef.plex.direct:32400", "local": false,
					"relay": false },
				{ "protocol": "http", "address": "192.168.1.10", "port": 32400, "uri": "http://192.168.1.10:32400", "local": true, "relay": false },
				{ "protocol": "https", "address": "192.168.1.10", "port": 32400, "uri": O, "local": true, "relay": false },
				{ "protocol": "https", "address": "1.2.3.4", "port": 443, "uri": "https://1-2-3-4.0123456789abcdef.plex.direct:8443", "local": false, "relay": true },
				{ "protocol": "https", "uri": "javascript:alert(1)", "local": true } ] },
		{ "name": "Bei Mama", "provides": "server", "owned": false, "clientIdentifier": "fedcba9876543210", "accessToken": "sharedToken456",
			"connections": [{ "protocol": "https", "uri": "https://5-6-7-8.fedcba9876543210.plex.direct:32400", "local": false, "relay": false }] },
		{ "name": "Handy", "provides": "client,player", "clientIdentifier": "phone0000000000", "connections": [] },
		{ "name": "Geteilt ohne Schlüssel", "provides": "server", "owned": false, "clientIdentifier": "nokey0000000000",
			"connections": [{ "uri": "https://a.plex.direct" }] },
	]
	var srv := Plex.parse_servers(resources)
	check(srv.size() == 2 and str(srv[0].name) == "Wohnzimmer" and bool(srv[0].owned) and str(srv[1].token) == "sharedToken456",
			"nur Server, geteilte nur mit eigenem Schlüssel")
	var uris: Array = srv[0].conns.map(func(c): return str(c.uri))
	check(uris == [O, "https://203-0-113-5.0123456789abcdef.plex.direct:32400", "https://1-2-3-4.0123456789abcdef.plex.direct:8443", "http://192.168.1.10:32400"],
			"Verbindungen: https im Heimnetz, https außen, Relay, http nur lokal-privat %s" % str(uris))
	check(
			Plex.parse_identity({ "MediaContainer": { "size": 0, "claimed": true, "machineIdentifier": "abcdef0123456789",
			"version": "1.41.0" } }) == "abcdef0123456789", "/identity")
	var secs := Plex.parse_sections({ "MediaContainer": { "size": 4, "Directory": [
		{ "key": "1", "type": "movie", "title": "Filme", "agent": "tv.plex.agents.movie" }, { "key": "2", "type": "show", "title": "Serien" },
		{ "key": "3", "type": "artist", "title": "Musik" }, { "key": "4", "type": "movie", "title": "Kinderfilme" },
			{ "key": "../5", "type": "movie", "title": "x" }] } })
	check(secs.size() == 3 and str(secs[1].type) == "series" and bool(secs[2].family) and not bool(secs[0].family),
			"Bibliotheken: Filme und Serien, Kinder erkannt")
	var movie := { "ratingKey": "123", "key": "/library/metadata/123", "guid": "plex://movie/5d77", "type": "movie", "title": "Matrix", "contentRating": "de/16",
		"summary": "Ein Hacker …", "audienceRating": 8.7, "year": 1999, "thumb": "/library/metadata/123/thumb/1700000000",
			"art": "/library/metadata/123/art/1700000000",
		"duration": 8160000, "originallyAvailableAt": "1999-03-31", "addedAt": 1700000000, "viewOffset": 0,
			"Genre": [{ "tag": "Action" }, { "tag": "Science-Fiction" }],
		"Image": [{ "alt": "Matrix", "type": "clearLogo", "url": "/library/metadata/123/clearLogo/1700000000" }] }
	var it := Plex.preview(movie, O, { "family": false })
	check(str(it.id) == "plex:123" and str(it.type) == "movie" and int(it.age) == 16 and str(it.content_rating) == "FSK 16" and str(it.imdb_rating) == "8.7"
			and it.genres == ["Action", "Science-Fiction"], "Film: Kennung, Freigabe, Bewertung, Genres")
	check(str(it.poster).begins_with(O + "/photo/:/transcode?width=400&height=600")
			and str(it.poster).ends_with("url=%2Flibrary%2Fmetadata%2F123%2Fthumb%2F1700000000") and str(it.logo).contains("clearLogo"),
			"Bilder vom Server, verkleinert")
	check(not str(it.poster).contains("Token") and str(it.runtime) == "136 min", "kein Schlüssel in Bildadressen; Laufzeit")
	var evil := movie.duplicate(true)
	evil.thumb = "https://evil.example/x.jpg"
	evil.art = "/library/../../etc/passwd"
	var ei := Plex.preview(evil, O)
	check(str(ei.poster) == "" and str(ei.background) == "", "fremde Bildadressen und Pfad-Tricks: kein Bild")
	var show := { "ratingKey": "200", "type": "show", "title": "Kanalarbeit", "contentRating": "TV-14", "year": 2022, "thumb": "/library/metadata/200/thumb/1",
			"leafCount": 12 }
	var lst := Plex.parse_list(
			{ "MediaContainer": { "size": 4,
			"Metadata": [movie, show, movie, { "ratingKey": "9", "type": "season", "title": "Staffel 1" }, { "ratingKey": "x1", "type": "movie", "title": "Böse" }] } },
			O)
	check(lst.size() == 2 and str(lst[1].type) == "series" and int(lst[1].age) == 16,
			"Liste: Filme und Serien, ohne Doppelte, ohne Staffeln, ohne kaputte Kennung")
	var ep := { "ratingKey": "305", "type": "episode", "title": "Gegenwind", "grandparentRatingKey": "200", "grandparentTitle": "Kanalarbeit",
		"grandparentThumb": "/library/metadata/200/thumb/1", "grandparentArt": "/library/metadata/200/art/1", "parentIndex": 1, "index": 3,
		"viewOffset": 900000, "duration": 2760000, "lastViewedAt": 1760000000, "thumb": "/library/metadata/305/thumb/1", "librarySectionID": "2" }
	var deck := ep.duplicate()
	deck.merge({ "ratingKey": "306", "index": 4, "viewOffset": 0 }, true)
	var cw := Plex.parse_continue({ "MediaContainer": { "Metadata": [ep, movie.merged({ "viewOffset": 600000, "lastViewedAt": 1760000500 }, true), deck] } }, O,
			{ "2": { "family": false } })
	check(cw.size() == 2 and str(cw[0].id) == "plex:200" and str(cw[0].video_id) == "plex:305" and int(cw[0].season) == 1 and int(cw[0].episode) == 3
			and is_equal_approx(float(cw[0].position), 900.0), "Weiterschauen: Folge steht für ihre Serie, eine je Titel")
	check(str(cw[1].video_id) == "plex:123" and is_equal_approx(float(cw[1].position), 600.0) and not bool(cw[1].next_up), "Weiterschauen: angefangener Film")
	var full := movie.duplicate(true)
	full.merge(
			{ "Role": [{ "tag": "Keanu Reeves", "role": "Neo", "thumb": "https://metadata-static.plex.tv/people/k.jpg" },
			{ "tag": "Carrie-Anne Moss", "role": "Trinity", "thumb": "https://evil.example/c.jpg" }],
		"Director": [{ "tag": "Lana Wachowski" }], "Writer": [{ "tag": "Lilly Wachowski" }], "Country": [{ "tag": "USA" }],
		"Guid": [{ "id": "imdb://tt0133093" }, { "id": "tmdb://603" }, { "id": "tvdb://1" }], "viewOffset": 1200000, "lastViewedAt": 1760000000 }, true)
	var mt := Plex.parse_meta({ "MediaContainer": { "Metadata": [full] } }, O)
	check(str(mt.imdb_id) == "tt0133093" and str(mt.tmdb_id) == "603" and mt.cast == ["Keanu Reeves", "Carrie-Anne Moss"] and mt.director == ["Lana Wachowski"],
			"Details: IDs, Besetzung, Regie")
	var ppl: Dictionary = mt.people
	check(str(ppl[M.person_key("Keanu Reeves")].photo).begins_with("https://metadata-static.plex.tv") and str(ppl[M.person_key("Carrie-Anne Moss")].photo) == "",
			"Personenbilder nur von Plex")
	check((mt.server_progress as Dictionary).has("plex:123") and is_equal_approx(float(mt.server_progress["plex:123"].position), 1200.0), "Stand des Servers")
	var leaves := {
			"MediaContainer": { "Metadata": [deck, ep, ep.merged({ "ratingKey": "301", "parentIndex": 0, "index": 1, "title": "Special" }, true),
			ep.merged({ "ratingKey": "310", "parentIndex": 2, "index": 1, "viewCount": 1, "viewOffset": 0 }, true)] } }
	var ms := Plex.parse_meta({ "MediaContainer": { "Metadata": [show] } }, O, leaves)
	var order: Array = ms.videos.map(func(v): return "%d:%d" % [int(v.season), int(v.episode)])
	check(order == ["1:3", "1:4", "2:1", "0:1"] and ms.seasons == [1, 2, 0], "Folgen sortiert, Specials zuletzt %s" % str(order))
	check(bool(ms.server_progress["plex:310"].watched) and is_equal_approx(float(ms.server_progress["plex:305"].position), 900.0), "Gesehen und Stand je Folge")
	var media := movie.duplicate(true)
	media["Media"] = [
		{ "id": 1, "duration": 8160000, "videoResolution": "4k", "height": 2160, "videoCodec": "hevc", "container": "mkv", "audioCodec": "truehd",
			"Part": [{ "id": 11, "key": "/library/parts/11/1700000000/file.mkv", "file": "D:\\Filme\\Matrix (1999)\\Matrix.mkv", "size": 31000000000, "container": "mkv",
				"Stream": [{ "streamType": 1, "codec": "hevc", "DOVIPresent": true }, { "streamType": 2, "selected": true, "displayTitle": "Deutsch (TrueHD 7.1)" },
					{ "streamType": 3, "key": "/library/streams/77", "languageCode": "ger", "displayTitle": "Deutsch (SRT extern)", "codec": "srt" },
					{ "streamType": 3, "key": "https://evil.example/sub.srt", "languageCode": "eng" }] }] },
		{ "id": 2, "videoResolution": "1080", "videoCodec": "h264",
			"Part": [{ "id": 12, "key": "/library/parts/12/1/file.mp4", "size": 4000000000, "Stream": [{ "streamType": 1, "colorTrc": "smpte2084" }] }] },
		{ "id": 3, "Part": [{ "id": 13, "key": "/etc/passwd" }] },
	]
	var sts := Plex.parse_streams({ "MediaContainer": { "Metadata": [media] } }, O, "secretTok", "cid0123", "Plex  ·  Wohnzimmer")
	check(sts.size() == 4 and str(sts[0].name) == "Direct Play" and str(sts[1].name) == "Direct Stream",
			"je Fassung Direct Play und Direct Stream, falscher Teil-Pfad fällt weg")
	check(str(sts[0].url) == O + "/library/parts/11/1700000000/file.mkv" and str(sts[0].headers["X-Plex-Token"]) == "secretTok"
			and not str(sts[0].url).contains("secretTok") and not str(sts[1].url).contains("secretTok"), "Adresse vom Server, Schlüssel nur als Kopfzeile")
	check(int(sts[0].quality) == 2160 and str(sts[0].hdr) == "DV" and str(sts[0].codec) == "HEVC" and str(sts[0].filename) == "Matrix.mkv"
			and str(sts[2].hdr) == "HDR10" and int(sts[2].quality) == 1080, "Qualität, HDR, Codec, nur Dateiname")
	check((sts[0].subtitles as Array).size() == 1 and str(sts[0].subtitles[0].url) == O + "/library/streams/77" and str(sts[0].subtitles[0].lang) == "ger",
			"externe Untertitel nur vom Server")
	check(str(sts[1].url).contains("/video/:/transcode/universal/start.m3u8?path=%2Flibrary%2Fmetadata%2F123") and str(sts[1].url).contains("directStream=1"),
			"Direct Stream über den Server")
	check(
			Plex.timeline_path("123", "playing", 5000,
			9000) == "/:/timeline?ratingKey=123&key=%2Flibrary%2Fmetadata%2F123&state=playing&time=5000&duration=9000&identifier=com.plexapp.plugins.library",
			"Timeline")
	check(Plex.scrobble_path("123", true) == "/:/scrobble?identifier=com.plexapp.plugins.library&key=123"
			and Plex.scrobble_path("1", false).begins_with("/:/unscrobble"), "Gesehen und zurück")
	check(
			Plex.items_path("1", "series", 60, 60, "addedAt:desc",
			"7") == "/library/sections/1/all?type=2&sort=addedAt%3Adesc&X-Plex-Container-Start=60&X-Plex-Container-Size=60&genre=7", "Seiten einer Bibliothek")
	var srch := Plex.parse_search(
			{ "MediaContainer": { "Hub": [{ "type": "movie", "Metadata": [movie] },
			{ "type": "artist", "Metadata": [{ "ratingKey": "5", "type": "artist", "title": "Band" }] }, { "type": "show", "Metadata": [show] }] } }, O)
	check(srch.size() == 2, "Suche: nur Filme und Serien aus den Hubs")
	var cols := Plex.parse_collections(
			{ "MediaContainer": { "Metadata": [{ "ratingKey": "901", "type": "collection", "title": "Krimis", "childCount": 4,
			"thumb": "/library/collections/901/thumb/1" }, { "ratingKey": "a", "title": "x" }] } }, O)
	check(cols.size() == 1 and str(cols[0].id) == "901" and int(cols[0].count) == 4, "Sammlungen")
	check(
			Plex.parse_genres({ "MediaContainer": { "Directory": [{ "key": "4", "title": "Action", "fastKey": "/library/sections/1/all?genre=4" },
			{ "key": "x", "title": "y" }] } }) == [{ "key": "4", "title": "Action" }], "Genres")
	check(Plex.headers("cid", "0.9.0", "tok").has("X-Plex-Token: tok") and not Plex.headers("cid", "0.9.0").has("X-Plex-Token: ")
			and Plex.headers("cid", "0.9.0").has("X-Plex-Product: Uzai"), "Kopfzeilen: Uzai als eigene App")


# --- Jellyfin / Emby -----------------------------------------------------------------------------

func _jellyfin() -> void:
	print("Jellyfin und Emby")
	var info := Jf.parse_public_info({ "LocalAddress": "http://192.168.1.20:8096", "ServerName": "Keller", "Version": "10.10.7", "ProductName": "Jellyfin Server",
		"OperatingSystem": "", "Id": "6c4b7f1e0f2a4b4e8b0a7f6c2d1e3a5b", "StartupWizardCompleted": true })
	check(str(info.kind) == "jellyfin" and str(info.name) == "Keller" and str(info.id) == "6c4b7f1e0f2a4b4e8b0a7f6c2d1e3a5b", "Server-Info Jellyfin")
	check(
			str(Jf.parse_public_info({ "ServerName": "Emby", "Version": "4.8.10.0", "Id": "0123456789abcdef0123456789abcdef",
			"LocalAddress": "http://10.0.0.5:8096" }).kind) == "emby" and Jf.parse_public_info({ "ServerName": "x" }).is_empty(),
			"Server-Info Emby, ohne Kennung nichts")
	var q := Jf.parse_quick(
			{ "Authenticated": false, "Secret": "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0", "Code": "482913", "DeviceId": "x",
			"DeviceName": "Uzai", "AppName": "Uzai", "AppVersion": "0.9.0", "DateAdded": "2026-10-23T10:00:00Z" })
	check(str(q.code) == "482913" and not bool(q.ok) and str(q.secret).length() == 64, "Quick Connect beginnt")
	check(bool(Jf.parse_quick({ "Authenticated": true, "Secret": "0f1e2d3c4b5a69788796a5b4c3d2e1f0", "Code": "482913" }).ok)
			and Jf.parse_quick({ "Secret": "kurz" }).is_empty(), "Quick Connect bestätigt; kaputtes Geheimnis abgelehnt")
	var auth := Jf.parse_auth(
			{ "User": { "Name": "Robin", "ServerId": "s", "Id": "4f1c2a3b5d6e7f8091a2b3c4d5e6f708", "Policy": { "IsAdministrator": true } }, "SessionInfo": {},
			"AccessToken": "a1b2c3d4e5f60718293a4b5c6d7e8f90", "ServerId": "s" })
	check(str(auth.token) == "a1b2c3d4e5f60718293a4b5c6d7e8f90" and str(auth.user_id) == "4f1c2a3b5d6e7f8091a2b3c4d5e6f708" and str(auth.user_name) == "Robin",
			"Anmeldung: Schlüssel und Benutzer")
	check(Jf.parse_auth({ "User": { "Id": "x y" }, "AccessToken": "a1b2c3d4e5f60718293a4b5c6d7e8f90" }).is_empty()
			and Jf.parse_auth({ "User": { "Id": "abc" }, "AccessToken": "kurz" }).is_empty(), "kaputte Anmeldung abgelehnt")
	var disc := _j({ "Address": "http://192.168.1.20:8096", "Id": "6c4b7f1e0f2a4b4e8b0a7f6c2d1e3a5b", "Name": "Keller", "EndpointAddress": null })
	check(str(Jf.parse_discovery(disc, "192.168.1.20").get("address", "")) == "http://192.168.1.20:8096", "Heimnetz-Suche: Antwort vom Server selbst")
	check(Jf.parse_discovery(disc, "192.168.1.99").is_empty(), "Antwort zeigt auf ein anderes Gerät: verworfen")
	check(Jf.parse_discovery(_j({ "Address": "http://203.0.113.9:8096", "Id": "aa", "Name": "x" }), "203.0.113.9").is_empty(),
			"Antwort aus dem Internet: verworfen")
	check(
			Jf.parse_discovery(("{\"Address\":\"http://192.168.1.20:8096\",\"Id\":\"aa\",\"Name\":\"" + "x".repeat(3000) + "\"}").to_utf8_buffer(),
			"192.168.1.20").is_empty() and Jf.parse_discovery("kein json".to_utf8_buffer(), "192.168.1.20").is_empty(), "zu große oder kaputte Antwort: verworfen")
	var views := Jf.parse_views(
			{ "Items": [{ "Name": "Filme", "Id": "f1a2", "CollectionType": "movies" }, { "Name": "Serien", "Id": "f3a4", "CollectionType": "tvshows" },
		{ "Name": "Musik", "Id": "f5", "CollectionType": "music" }, { "Name": "Kinder", "Id": "f6", "CollectionType": "movies" },
			{ "Name": "Böse", "Id": "../x", "CollectionType": "movies" }], "TotalRecordCount": 5 })
	check(views.size() == 3 and bool(views[2].family) and str(views[1].type) == "tvshows", "Bibliotheken (Views)")
	var mov := { "Name": "Nachtfalter", "ServerId": "s", "Id": "a10000000000000000000000000000a1", "Type": "Movie", "ProductionYear": 2023,
			"OfficialRating": "FSK-16",
		"CommunityRating": 7.4, "RunTimeTicks": 66000000000, "Overview": "Ein Taxifahrer …", "Genres": ["Thriller"],
			"ImageTags": { "Primary": "7c1e9b", "Logo": "aa11" },
		"BackdropImageTags": ["0e5d"],
			"UserData": { "PlaybackPositionTicks": 25000000000, "PlayCount": 0, "Played": false, "LastPlayedDate": "2026-10-20T19:30:00.0000000Z" },
		"ProviderIds": { "Imdb": "tt7654321", "Tmdb": "12345" },
			"People": [{ "Name": "Mara L", "Id": "b1", "Role": "Kapitänin", "Type": "Actor", "PrimaryImageTag": "c3" }, { "Name": "Lea S", "Type": "Director" }],
		"MediaSources": [
			{ "Protocol": "File", "Id": "a10000000000000000000000000000a1", "Path": "/media/filme/Nachtfalter.mkv", "Container": "mkv", "Size": 5200000000,
			"MediaStreams": [{ "Codec": "hevc", "Type": "Video", "Height": 2160, "Width": 3840, "VideoRange": "HDR", "VideoRangeType": "DOVIWithHDR10" },
				{ "Type": "Audio", "DisplayTitle": "Deutsch – EAC3 5.1" },
					{ "Type": "Subtitle", "Codec": "subrip", "Language": "ger", "DisplayTitle": "Deutsch", "IsExternal": true, "Index": 3 },
				{ "Type": "Subtitle", "Codec": "PGSSUB", "IsExternal": false, "Index": 4 }] },
			{ "Protocol": "Http", "Id": "fremd", "Path": "https://evil.example/stream" }] }
	var p := Jf.preview(mov, JB, "jellyfin", { "family": false })
	check(str(p.id) == "jf:a10000000000000000000000000000a1" and int(p.age) == 16
			and str(p.poster) == JB + "/Items/a10000000000000000000000000000a1/Images/Primary?tag=7c1e9b&maxWidth=400&quality=90",
			"Film: Kennung, Freigabe, Bild vom Server")
	check(str(p.background).contains("/Images/Backdrop/0?tag=0e5d") and str(p.logo).contains("/Images/Logo?tag=aa11") and str(p.runtime) == "110 min"
			and str(p.imdb_rating) == "7.4", "Hintergrund, Schriftzug, Laufzeit, Bewertung")
	check(Jf.preview(mov, JB, "emby").get("id") == "emby:a10000000000000000000000000000a1", "Emby-Kennung")
	var ep := { "Name": "Gegenwind", "Id": "e1", "Type": "Episode", "SeriesId": "a4", "SeriesName": "Die Werft", "SeriesPrimaryImageTag": "s1",
			"ParentIndexNumber": 2, "IndexNumber": 5,
		"RunTimeTicks": 27000000000, "UserData": { "PlaybackPositionTicks": 9000000000, "LastPlayedDate": "2026-10-21T20:00:00Z" }, "ParentBackdropItemId": "a4",
			"ParentBackdropImageTags": ["bb"] }
	var nxt := ep.merged({ "Id": "e2", "IndexNumber": 6, "UserData": { "PlaybackPositionTicks": 0 } }, true)
	var cw := Jf.parse_continue({ "Items": [ep, mov] }, { "Items": [nxt, ep] }, JB, "jellyfin")
	check(cw.size() == 2 and str(cw[0].video_id) == "jf:e1" and int(cw[0].season) == 2 and is_equal_approx(float(cw[0].position), 900.0)
			and str(cw[0].background).contains("/Items/a4/Images/Backdrop/0"), "Weiterschauen: Folge mit Stand, Bild der Serie")
	check(str(cw[1].id) == "jf:a10000000000000000000000000000a1" and is_equal_approx(float(cw[1].position), 2500.0),
			"Weiterschauen: Film; Als Nächstes derselben Serie nicht doppelt")
	var eps := {
			"Items": [nxt, ep, ep.merged({ "Id": "e0", "ParentIndexNumber": 0, "IndexNumber": 1 }, true), ep.merged({ "Id": "e9", "Type": "Trailer" }, true)] }
	var series := { "Name": "Die Werft", "Id": "a4", "Type": "Series", "OfficialRating": "FSK-12", "ImageTags": {} }
	var ms := Jf.parse_meta(series, JB, "jellyfin", eps)
	check(ms.videos.map(func(v): return str(v.id)) == ["jf:e1", "jf:e2", "jf:e0"] and ms.seasons == [2, 0], "Folgen der Serie sortiert, keine Trailer")
	var mm := Jf.parse_meta(mov, JB, "jellyfin")
	check(mm.cast == ["Mara L"] and mm.director == ["Lea S"] and str(mm.imdb_id) == "tt7654321"
			and str(mm.people[M.person_key("Mara L")].photo).contains("/Items/b1/Images/Primary?tag=c3"), "Besetzung mit Bildern vom Server, IDs")
	var stand: Dictionary = mm.server_progress[str(mm.id)]
	check(is_equal_approx(float(stand.position), 2500.0) and not bool(stand.watched), "Stand vom Server: angefangener Film")
	var nochmal := mov.merged({ "UserData": { "PlaybackPositionTicks": 12000000000, "Played": true, "LastPlayedDate": "2026-10-22T19:30:00Z" } }, true)
	var stand2: Dictionary = Jf.parse_meta(nochmal, JB, "jellyfin").server_progress[str(mm.id)]
	check(is_equal_approx(float(stand2.position), 1200.0) and not bool(stand2.watched),
			"schon gesehen und erneut angefangen: der Stand bleibt (%s s)" % str(stand2.position))
	var fertig := mov.merged({ "UserData": { "PlaybackPositionTicks": 0, "Played": true } }, true)
	var stand3: Dictionary = Jf.parse_meta(fertig, JB, "jellyfin").server_progress[str(mm.id)]
	check(bool(stand3.watched) and is_zero_approx(float(stand3.position)), "gesehen ohne Stand: gesehen")
	var auth_h := Jf.play_headers("jellyfin", "dev1", "0.9.0", "tok123")
	var sts := Jf.parse_streams(mov, JB, "jellyfin", auth_h, "Jellyfin  ·  Keller")
	check(sts.size() == 1 and str(sts[0].url) == JB + "/Videos/a10000000000000000000000000000a1/stream?static=true&mediaSourceId=a10000000000000000000000000000a1",
			"Datei direkt vom Server, Http-Quellen fallen weg")
	check(str(sts[0].hdr) == "DV" and int(sts[0].quality) == 2160 and str(sts[0].headers.Authorization).contains("Token=tok123")
			and not str(sts[0].url).contains("tok123"), "Qualität, HDR; Schlüssel nur in der Kopfzeile")
	check((sts[0].subtitles as Array).size() == 1
			and str(sts[0].subtitles[0].url) == JB + "/Videos/a10000000000000000000000000000a1/a10000000000000000000000000000a1/Subtitles/3/Stream.srt",
			"externe Untertitel (eingebettete liest mpv selbst)")
	check(Jf.play_headers("emby", "d", "v", "t") == { "X-Emby-Token": "t" } and Jf.headers("emby", "d", "v", "t").has("X-Emby-Token: t")
			and Jf.headers("jellyfin", "d", "v").size() == 2, "Kopfzeilen für Emby und Jellyfin")
	var body := Jf.progress_body("a1", "ms", "sess", 90.5, true)
	check(int(body.PositionTicks) == 905000000 and bool(body.IsPaused) and str(body.PlayMethod) == "DirectPlay", "Fortschritt in Ticks")
	check(Jf.items_path("u1", "f1", 60, 60, "DateCreated", "Sci-Fi & Fantasy").contains("SortOrder=Descending")
			and Jf.items_path("u1", "f1", 0, 60, "SortName", "Sci-Fi & Fantasy").ends_with("&Genres=Sci-Fi%20%26%20Fantasy"), "Seiten einer Bibliothek")
	check(
			Jf.parse_collections({ "Items": [{ "Id": "c1", "Name": "Krimis", "Type": "BoxSet", "ChildCount": 3 }, { "Id": "c2", "Name": "x", "Type": "Movie" }] },
			JB).size() == 1, "Sammlungen (BoxSets)")


# --- Stremio -------------------------------------------------------------------------------------

func _stremio() -> void:
	print("Stremio-Konto")
	var l := St.parse_link({ "result": { "code": "XU4K2", "link": "https://link.stremio.com?code=XU4K2", "qrcode": "data:image/png;base64,AAA" } })
	check(str(l.code) == "XU4K2" and str(l.link) == "https://link.stremio.com?code=XU4K2", "Anmelde-Code mit Link")
	check(str(St.parse_link({ "result": { "code": "AB12", "link": "https://evil.example/phish" } }).link) == St.LINK_PAGE
			and St.parse_link({ "error": { "message": "x" } }).is_empty(), "fremder Link wird Stremios Seite; Fehler ergibt nichts")
	check(St.parse_auth_key({ "result": { "authKey": "auth_key_0123456789abcdef" } }) == "auth_key_0123456789abcdef"
			and St.parse_auth_key({ "error": { "code": 1 } }) == "", "Anmelde-Schlüssel")
	var addons := St.parse_addons({ "result": { "addons": [
		{ "transportUrl": "https://v3-cinemeta.strem.io/manifest.json", "transportName": "http", "manifest": { "id": "com.linvo.cinemeta", "name": "Cinemeta" },
			"flags": { "official": true, "protected": true } },
		{ "transportUrl": "http://127.0.0.1:11470/local-addon/manifest.json", "manifest": { "name": "Local Files" } },
		{ "transportUrl": "https://addon.example/abc/manifest.json", "manifest": { "name": "Mein Addon" } },
		{ "transportUrl": "https://addon.example/abc/manifest.json", "manifest": { "name": "Doppelt" } },
		{ "transportUrl": "javascript:alert(1)" }, { "transportUrl": 5 } ] } })
	check(addons.size() == 2 and str(addons[1].url) == "https://addon.example/abc/manifest.json" and str(addons[1].name) == "Mein Addon",
			"eigene Addons: nur https, ohne Doppelte")
	var lib := St.parse_library({ "result": [
		{ "_id": "tt0133093", "name": "Matrix", "type": "movie", "poster": "https://images.metahub.space/poster/medium/tt0133093/img", "posterShape": "poster",
			"removed": false, "temp": false,
			"_ctime": "2025-01-01T10:00:00.000Z", "_mtime": "2026-10-20T10:00:00.000Z",
				"state": { "lastWatched": "2026-10-20T21:00:00.000Z", "timeWatched": 600000, "timeOffset": 1800000,
			"overallTimeWatched": 600000, "timesWatched": 0, "flaggedWatched": 0, "duration": 8160000, "video_id": "tt0133093", "watched": "", "noNotif": false },
				"behaviorHints": { "defaultVideoId": null } },
		{ "_id": "tt0903747", "name": "Breaking Bad", "type": "series", "poster": "http://unsicher.example/p.jpg", "removed": false, "temp": false,
			"_mtime": "2026-10-21T10:00:00.000Z",
			"state": { "timeOffset": 600000, "duration": 2900000, "video_id": "tt0903747:2:5", "lastWatched": "2026-10-22T21:00:00.000Z" } },
		{ "_id": "tt1", "name": "Entfernt", "type": "movie", "removed": true, "temp": false, "state": { "timeOffset": 0 } },
		{ "_id": "tt2", "name": "Nur kurz", "type": "movie", "removed": true, "temp": true, "state": { "timeOffset": 50000, "video_id": "tt2" } },
		{ "_id": "evil/../x", "name": "Böse", "type": "movie" }, { "_id": "yt1", "name": "Kanal", "type": "channel" } ] })
	check(lib.size() == 4 and str(lib[1].poster) == M.metahub("poster", "tt0903747"),
			"Bibliothek: kaputte Kennungen und Kanäle fallen weg, unsichere Bilder ersetzt")
	var shown := St.library(lib)
	check(shown.size() == 2 and str(shown[0].id) == "tt0903747" and not shown[0].has("raw"), "Bibliothek: ohne Entfernte, zuletzt geändert zuerst, ohne Rohdaten")
	var cw := St.continue_items(lib)
	check(cw.size() == 3 and str(cw[0].video_id) == "tt0903747:2:5" and int(cw[0].season) == 2 and int(cw[0].episode) == 5
			and is_equal_approx(float(cw[0].position), 600.0), "Weiterschauen wie Stremio (auch vorübergehende)")
	var raw: Dictionary = lib[0].raw
	var ch := St.put_change(raw, 2400.0, 8160.0, "tt0133093", false, 1761300000)
	check(int(ch.state.timeOffset) == 2400000 and str(ch.state.lastWatched).begins_with("2025-10-24T") and str(ch._mtime).ends_with(".000Z")
			and str(ch.posterShape) == "poster" and int(ch.state.overallTimeWatched) == 600000, "Fortschritt zurück: nur der Stand ändert sich")
	check(int(St.put_change(raw, 8000.0, 8160.0, "tt0133093", true, 1761300000).state.flaggedWatched) == 1 and int(raw.state.timeOffset) == 1800000,
			"zu Ende: gesehen; das Original bleibt unverändert")


# --- Feindliche Antworten ------------------------------------------------------------------------

func _hostile() -> void:
	print("Feindliche Antworten")
	var weird: Array = [null, 5, "text", [], {}, [1, "a", null], { "MediaContainer": "x" }, { "MediaContainer": { "Metadata": "x", "Directory": 5 } },
		{ "Items": { "a": 1 } }, { "result": "x" }, { "result": { "addons": "x" } }]
	var crashed := false
	for w in weird:
		var all := [Plex.parse_pin(w), Plex.parse_servers(w), Plex.parse_sections(w), Plex.parse_list(w, O), Plex.parse_continue(w, O), Plex.parse_meta(w, O, w),
			Plex.parse_streams(w, O, "t", "c", "l"), Plex.parse_search(w, O), Plex.parse_collections(w, O), Plex.parse_genres(w), Plex.parse_identity(w),
			Jf.parse_public_info(w), Jf.parse_quick(w), Jf.parse_auth(w), Jf.parse_views(w), Jf.parse_list(w, JB, "jellyfin"), Jf.parse_continue(w, w, JB, "jellyfin"),
			Jf.parse_meta(w, JB, "jellyfin", w), Jf.parse_streams(w, JB, "jellyfin", {}, "l"), Jf.parse_collections(w, JB), Jf.parse_genres(w),
			St.parse_link(w), St.parse_auth_key(w), St.parse_addons(w), St.parse_library(w)]
		for r in all:
			if not ((r is Array and (r as Array).is_empty()) or (r is Dictionary and (r as Dictionary).is_empty()) or (r is String and r == "")):
				crashed = true
	check(not crashed, "falsche Typen überall: leere Ergebnisse statt Absturz")
	var many: Array = []
	for i in 5000:
		many.append({ "ratingKey": str(i + 1), "type": "movie", "title": "T%d" % i })
	check(Plex.parse_list({ "MediaContainer": { "Metadata": many } }, O).size() == 500, "Riesenliste wird gekappt")
	var nasty := { "ratingKey": "1", "type": "movie", "title": "<b>Titel</b>" + char(0) + char(27) + "[31m", "summary": 12345, "year": "1999; DROP",
			"contentRating": { "x": 1 },
		"Genre": [{ "tag": ["x"] }, { "tag": "Drama" }, "kaputt"], "duration": "lang", "audienceRating": 99, "thumb": 7 }
	var it := Plex.preview(nasty, O)
	check(str(it.name) == "<b>Titel</b>[31m" and str(it.description) == "12345" and str(it.year) == "" and int(it.age) == -1 and it.genres == ["Drama"]
			and str(it.imdb_rating) == "" and str(it.poster) == "", "Werte mit falschem Typ werden leer, Text bleibt Text")


# --- Weiterschauen aus mehreren Quellen -----------------------------------------------------------

func _continue() -> void:
	print("Weiterschauen gemischt")
	var local := [{ "id": "tt1", "updated": 100 }, { "id": "plex:5", "updated": 200 }, { "id": "jf:aa", "updated": 300 }, { "id": "plex:6", "updated": 50 }]
	var remote := [{ "id": "plex:5", "updated": 250, "source": "plex", "cw_at": 400 }, { "id": "tt1", "updated": 90, "source": "stremio", "cw_at": 400 },
			{ "id": "plex:7", "updated": 10, "source": "plex", "cw_at": 400 }]
	var out := M.merge_continue(local, remote, ["plex", "stremio"])
	var ids: Array = out.map(func(x): return str(x.id))
	check(ids == ["plex:5", "tt1", "plex:7"], "neuerer Stand gewinnt, abgemeldete Quelle fällt weg, vom Server Beendetes verschwindet %s" % str(ids))
	check(int(out[0].updated) == 250 and int(out[1].updated) == 100, "je Titel der neuere Stand")


# --- Konten und Tresor ---------------------------------------------------------------------------

func _accounts() -> void:
	print("Konten und Tresor")
	for k in ["plex.token", "plex.server_token", "jellyfin.token", "emby.token", "stremio.auth"]:
		check(k in Vault.SECRETS, "%s liegt nur verschlüsselt" % k)
	for id in ["plex", "jellyfin", "emby", "stremio"]:
		check(not Konten.find(id).is_empty() and str(Konten.find(id).page) == "Filme-Quellen", "%s unter Konten mit Abmelden" % id)
	var store := { "plex.token": "t", "plex.server": { "id": "x" }, "plex.client_id": "keep" }
	Konten.forget("plex", func(k: String, v: Variant) -> void: store[k] = v)
	check(str(store["plex.token"]) == "" and str(store["plex.server"]) == "" and str(store["plex.client_id"]) == "keep",
			"Abmelden leert die Anmeldung, die Gerätekennung bleibt")
