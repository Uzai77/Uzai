extends Node
## Logik des Musik-Bereichs ohne Oberfläche und ohne Netz: Spotify-Antworten (alte und neue Form
## nach den Änderungen 2026), Bibliothek über URIs, Mixe von Spotify aus Suchtreffern, eigenes
## Release Radar, „Lange nicht gehört“, Geräte, Fehlertexte und die Köpfe der Titellisten.
## Aufruf: godot --headless --path . res://tests/logic_musik.tscn

const TrackList := preload("res://src/ui/layers/track_list.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const Lyrics := preload("res://src/core/lyrics.gd")
const MusicShare := preload("res://src/ui/layers/music_share.gd")
const ArtistPage := preload("res://src/ui/layers/artist_page.gd")
const Catalog := preload("res://src/core/artist_catalog.gd")
const ArtistTracks := preload("res://src/ui/layers/artist_tracks.gd")
const MusicView := preload("res://src/ui/sections/music_view.gd")
const U := preload("res://src/ui/u.gd")
const BG := preload("res://src/ui/components/background.gd")
const Quelle := preload("res://tests/quelle.gd")
const Web := preload("res://src/core/spotify_web.gd")
const P := preload("res://src/core/browser_protokoll.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Titel und Einträge")
	var t1 := { "uri": "spotify:track:1", "id": "1", "name": "Eins", "duration_ms": 1000, "artists": [{ "name": "A" }],
			"album": { "name": "Al", "images": [{ "url": "g" }, { "url": "m" }] } }
	var t2 := { "uri": "spotify:track:2", "id": "2", "name": "Zwei", "artists": [], "album": { "name": "B", "images": null } }
	var mixed: Array = Music.tracks_from_items([
		{ "item": t1, "added_at": "x" },                    # neu (2026)
		{ "track": t2 },                                     # alt
		{ "item": t2, "track": t1 },                         # Übergang: beide da, item zählt
		{ "item": null },                                    # gelöscht
		{ "track": null },
		{ "item": { "uri": "spotify:episode:9", "type": "episode" } },
		t1,                                                  # Top-Titel: der Titel selbst
	])
	check(mixed.size() == 4, "Einträge mit item, track und direkt; leere und Folgen raus (%d)" % mixed.size())
	check(str(mixed[0].title) == "Eins" and str(mixed[1].title) == "Zwei" and str(mixed[2].title) == "Zwei", "item hat Vorrang vor track")
	check(str(mixed[1].art) == "" and int(mixed[1].duration) == 0, "fehlende Bilder und Länge stören nicht")

	print("Playlists und Alben")
	var pn := Music.playlist_from({ "uri": "spotify:playlist:p", "id": "p", "name": "Neu", "items": { "total": 12 }, "images": null,
		"owner": { "id": "ich", "display_name": "Ich" }, "description": "Mit <a href=\"x\">Link</a> &amp; mehr" }, "ich")
	check(int(pn.count) == 12 and pn.mine and str(pn.art) == "", "neue Form: Anzahl unter items, Bilder dürfen fehlen")
	check(str(pn.desc) == "Mit Link & mehr", "Beschreibung ohne HTML")
	var po := Music.playlist_from(
			{ "uri": "spotify:playlist:q", "id": "q", "name": "Alt", "tracks": { "total": 7 }, "owner": { "id": "lena" }, "collaborative": false }, "ich")
	check(int(po.count) == 7 and not po.mine, "alte Form: Anzahl unter tracks; fremde Playlist ist nicht deine")
	check(Music.playlist_from({ "uri": "spotify:playlist:r", "owner": { "id": "lena" }, "collaborative": true }, "ich").mine, "Mitarbeit zählt als deine")
	check(Music.playlist_from(null).is_empty() and Music.playlist_from({ "name": "ohne uri" }).is_empty(), "leere Suchtreffer (null) werden übersprungen")
	var al := Music.album_from({ "uri": "spotify:album:a", "id": "a", "name": "Platte", "artists": [{ "name": "X" }, { "name": "Y" }], "album_type": "single",
		"release_date": "2026-10-01", "release_date_precision": "day", "total_tracks": 2, "images": [{ "url": "640" }, { "url": "300" }, { "url": "64" }] })
	check(str(al.artist) == "X, Y" and str(al.type) == "single" and str(al.art) == "300" and str(al.art_big) == "640", "Album mit Künstlern, Art und Bildern")

	print("Bibliothek über URIs")
	var q := Music.library_query(["spotify:track:abc", "spotify:album:def"])
	check(q == "spotify%3Atrack%3Aabc,spotify%3Aalbum%3Adef", "URIs kodiert und mit Komma getrennt: " + q)
	var many: Array = []
	for i in 50:
		many.append("spotify:track:%d" % i)
	check(Music.library_query(many).split(",").size() == 40, "höchstens 40 URIs je Abruf")
	var by := Music.ids_by_type(["spotify:track:a", "spotify:track:b", "spotify:album:c", "kaputt"])
	check((by.track as Array) == ["a", "b"] and (by.album as Array) == ["c"] and by.size() == 2, "Rückfall: IDs je Art für die alten Wege")

	print("Mixe von Spotify (über die Suche)")
	check(Music.spotify_mix_kind("Dein Mix der Woche") == "weekly" and Music.spotify_mix_kind("Discover Weekly") == "weekly",
			"Mix der Woche auf Deutsch und Englisch")
	check(Music.spotify_mix_kind("Release Radar") == "radar" and Music.spotify_mix_kind("Daily Mix 3") == "daily"
			and Music.spotify_mix_kind("In Dauerschleife") == "repeat", "Release Radar, Daily Mix, Dauerschleife")
	check(Music.spotify_mix_kind("Daily Mix Hits 2024") == "" and Music.spotify_mix_kind("Meine Release Radar Kopie") == "", "ähnliche Namen zählen nicht")
	var found: Array = [
		{ "id": "x", "name": "Release Radar", "owner_id": "jemand" },
		{ "id": "d2", "name": "Daily Mix 2", "owner_id": "spotify" },
		{ "id": "rr", "name": "Release Radar", "owner_id": "spotify" },
		{ "id": "rr2", "name": "Release Radar", "owner_id": "spotify" },
		{ "id": "dw", "name": "Discover Weekly", "owner_id": "spotify" },
		{ "id": "d1", "name": "Daily Mix 1", "owner_id": "spotify" },
		{ "id": "d2", "name": "Daily Mix 2", "owner_id": "spotify" },
	]
	var mx := Music.pick_spotify_mixes(found)
	var ids: Array = mx.map(func(m): return str(m.id))
	check(ids == ["dw", "rr", "d1", "d2"], "nur Spotify als Besitzer, je Art einmal, Reihenfolge Woche, Radar, Daily: " + str(ids))
	check(str(mx[0].kind) == "spotify_mix" and str(mx[0].sub) == "Jeden Montag neu" and float(mx[2].hue) != float(mx[3].hue), "Kachel-Angaben und eigene Farbtöne")

	print("Neu von deinen Künstlern")
	var now_unix := int(Time.get_unix_time_from_datetime_dict({ "year": 2026, "month": 10, "day": 15, "hour": 12, "minute": 0, "second": 0 }))
	check(Music.release_unix("2026-10-09", "day") > 0 and Music.release_unix("2026", "year") == 0 and Music.release_unix("kaputt") == 0,
			"Datum nach Genauigkeit (nur Jahr: unbekannt)")
	var rel := Music.fresh_releases([
		{ "id": "a", "name": "Alt", "artist": "K", "date": "2026-07-01", "precision": "day" },
		{ "id": "b", "name": "Neu", "artist": "K", "date": "2026-10-10", "precision": "day" },
		{ "id": "c", "name": "Neu", "artist": "K", "date": "2026-09-20", "precision": "day" },
		{ "id": "d", "name": "Monat", "artist": "L", "date": "2026-10", "precision": "month" },
		{ "id": "e", "name": "Zukunft", "artist": "M", "date": "2027-01-01", "precision": "day" },
		{ "id": "f", "name": "Jahr", "artist": "N", "date": "2026", "precision": "year" },
	], now_unix, 42)
	var rids: Array = rel.map(func(a): return str(a.id))
	check(rids == ["b", "d"], "sechs Wochen, neueste zuerst, Single und Album mit gleichem Namen nur einmal: " + str(rids))

	print("Eigene Mixe")
	var long_l: Array = [{ "id": "1" }, { "id": "2" }, { "id": "3" }, { "id": "4" }]
	var lu := Music.long_unheard(long_l, [{ "id": "2" }], [{ "id": "4" }])
	check(lu.map(func(t): return str(t.id)) == ["1", "3"], "Lange nicht gehört: ohne Top der letzten Wochen und ohne Zuletzt gehört")
	check(Music.arts_of([{ "art": "a" }, { "art": "a" }, { "art": "" }, { "art": "b" }, { "art": "c" }, { "art": "d" }, { "art": "e" }]) == ["a", "b", "c", "d"],
			"Mosaik: bis zu vier verschiedene Bilder")
	var keep_top := Music.top_tracks
	var keep_long := Music.top_long
	var keep_recent := Music.recent_list
	var keep_new := Music.new_releases
	Music._demo_for_you()
	var own: Array = Music.own_mixes().map(func(m): return str(m.id))
	check(own == ["mix:top", "mix:neu", "mix:lange", "mix:zuletzt"], "Beispieldaten ergeben alle vier eigenen Mixe: " + str(own))
	check(Music.spotify_mixes.size() == 4, "Beispiel: fremde „Release Radar“-Kopie wird nicht genommen")
	Music.top_tracks = keep_top
	Music.top_long = keep_long
	Music.recent_list = keep_recent
	Music.new_releases = keep_new
	Music.spotify_mixes = []

	print("Geräte")
	var devs := [{ "id": "h", "name": "Handy", "type": "Smartphone", "active": false }, { "id": "b", "name": "Büro", "type": "Computer", "active": false },
			{ "id": "w", "name": "WOHNZIMMER", "type": "Computer", "active": false }]
	check(Music.pick_device(devs, "wohnzimmer") == "w", "dieser PC nach Namen")
	check(Music.pick_device(devs, "") == "b", "sonst der erste PC")
	devs[0].active = true
	check(Music.pick_device(devs, "wohnzimmer") == "h", "ein laufendes Gerät geht vor")
	check(Music.pick_pc(devs, "wohnzimmer") == "w" and Music.pick_pc([{ "id": "h", "type": "Smartphone" }], "") == "", "nur PCs, wenn Spotify hier starten soll")

	print("Fehlertexte")
	check(Music.error_reason({ "data": { "error": { "status": 403, "message": "Player command failed", "reason": "PREMIUM_REQUIRED" } } }) == "PREMIUM_REQUIRED",
			"Grund aus der Fehlerantwort")
	check(Music.error_reason({ "data": null }) == "" and Music.error_reason({ "data": { "error": { "status": 404 } } }) == "", "ohne Grund: leer")
	check(Music.control_error(403, "PREMIUM_REQUIRED", false).contains("Premium"), "ohne Premium: klar gesagt")
	check(Music.control_error(404, "", true).contains("nicht abspielen"), "gesperrte Liste: verständlich")
	check(Music.control_error(429, "", false).contains("bremst"), "zu viele Anfragen")

	print("Titellisten")
	var i_album := TrackList.info_for({ "kind": "album", "name": "Platte", "artist": "X", "date": "2026-10-01", "type": "single" })
	check(str(i_album.kicker) == "Single · 2026" and str(i_album.sub) == "X", "Album: Art und Jahr, Künstler")
	var i_mix := TrackList.info_for({ "kind": "spotify_mix", "name": "Release Radar", "sub": "Jeden Freitag neu", "uri": "spotify:playlist:rr" })
	check(bool(i_mix.restricted) and str(i_mix.kicker).begins_with("Von Spotify") and not TrackList.loader_for({ "kind": "spotify_mix" }).is_valid(),
			"Mix von Spotify: ehrlich gesperrt, kein Abruf der Titel")
	check(TrackList.loader_for({ "kind": "playlist", "id": "p" }).is_valid() and TrackList.loader_for({ "kind": "album", "id": "a" }).is_valid(),
			"Playlist und Album laden ihre Titel")
	check(str(TrackList.info_for({ "name": "Liste", "owner": "Lena" }).kicker) == "Playlist · von Lena", "Playlist ohne Art: von wem")

	print("Kacheln")
	check(MusicTile.tonal(0.3) == MusicTile.tonal(0.3) and MusicTile.tonal(0.3) != MusicTile.tonal(0.6), "gemalte Cover je Farbton nur einmal gerechnet")
	Music.now = { "id": "abc", "uri": "spotify:track:abc" }
	check(Music.share_link() == "https://open.spotify.com/track/abc", "Link für Handy und Freunde")
	Music.now = { "id": "123", "uri": "", "source": "windows" }
	check(Music.share_link() == "", "Windows-Mediensitzung: kein Spotify-Link")
	Music.now = {}

	print("Songtext im Guide")
	var lyr := Lyrics.parse("[00:01.00] Eins\n[00:03.00] Zwei\n[00:05.00] \n[00:07.00] Drei\n[00:09.00] Vier", "")
	check(Guide.lyric_pair(lyr.synced, 500) == ["", "Eins"], "vor der ersten Zeile: nur die nächste")
	check(Guide.lyric_pair(lyr.synced, 3500) == ["Zwei", "Drei"], "laufende Zeile und die nächste (Leerzeile übersprungen)")
	check(Guide.lyric_pair(lyr.synced, 9500) == ["Vier", ""], "letzte Zeile: nichts danach")
	var st: Dictionary = Guide.stanzas(lyr, 7500)
	check(st.verses == ["Eins\nZwei", "Drei\nVier"] and int(st.current) == 1, "Strophen an Leerzeilen, laufende Strophe gewählt")
	check(int(Guide.stanzas(lyr, 5500).current) == 1, "laufende Zeile ist eine Pause: die nächste Strophe")
	var pl: Dictionary = Guide.stanzas(Lyrics.parse("", "A\nB\n\nC"), 0)
	check(pl.verses == ["A\nB", "C"] and int(pl.current) == -1, "ohne Zeitangaben: Strophen, keine laufende")
	check((Guide.stanzas(Lyrics.parse("", ""), 0).verses as Array).is_empty(), "kein Songtext: nichts")

	_kuenstler_und_suche()
	_zusammen_hoeren()
	_rueckmeldung7()
	await _wie_die_app()
	_intern()
	await _in_scheiben()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## U.in_scheiben: viele Kacheln, ohne das Bild anzuhalten (Raster der Playlists, Alben und Interpreten).
func _in_scheiben() -> void:
	print("Viele Kacheln in Scheiben")
	var baue := func(i: int) -> Control:
		var c := Control.new()
		c.set_meta("uz_key", "k%d" % i)
		return c
	var a := Control.new()
	add_child(a)
	U.in_scheiben(a, 20, baue, 24, 30)
	check(a.get_child_count() == 20, "wenige: alle sofort, wie bisher")
	var b := Control.new()
	add_child(b)
	U.in_scheiben(b, 100, baue, 24, 30)
	check(b.get_child_count() == 24, "viele: die ersten 24 sofort")
	await get_tree().process_frame
	check(b.get_child_count() == 54, "ein Bild später 30 mehr (%d)" % b.get_child_count())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(b.get_child_count() == 100 and str(b.get_child(99).get_meta("uz_key")) == "k99", "nach vier Bildern alle 100, in der Reihenfolge")
	# Die gehaltene Auswahl: bis zu ihr ohne Pause, dann noch eine Scheibe dahinter.
	var c2 := Control.new()
	add_child(c2)
	var ist_80 := func(k: Node) -> bool:
		return str(k.get_meta("uz_key", "")) == "k80"
	U.in_scheiben(c2, 200, baue, 24, 30, ist_80)
	check(c2.get_child_count() == 81 + 30, "gehaltene Karte Nummer 80: sofort bis zu ihr und 30 dahinter (%d)" % c2.get_child_count())
	# Den Behälter gibt es nicht mehr: Das Bauen endet, nichts hängt nach.
	var d := Control.new()
	add_child(d)
	var gebaut := [0]
	var zaehle := func(_i: int) -> Control:
		gebaut[0] += 1
		return Control.new()
	U.in_scheiben(d, 500, zaehle, 24, 30)
	remove_child(d)
	d.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(gebaut[0] == 24, "Behälter weg: Es wird nichts mehr gebaut (%d)" % gebaut[0])
	# Eine Karte ausgelassen (null) bringt die Zählung nicht durcheinander.
	var e := Control.new()
	add_child(e)
	var jede_zweite := func(i: int) -> Control:
		return null if i % 2 == 1 else Control.new()
	U.in_scheiben(e, 10, jede_zweite, 24, 30)
	check(e.get_child_count() == 5, "ausgelassene Karten fehlen einfach")
	for n in [a, b, c2, e]:
		n.queue_free()


func _kuenstler_und_suche() -> void:
	print("Künstler am Titel")
	var tr := Music.track_from(
			{ "uri": "spotify:track:1", "id": "1", "name": "Eins", "artists": [{ "id": "a1", "name": "A" }, { "id": "a2", "name": "B" }], "album": { "name": "Al" } })
	check(str(tr.artist) == "A, B" and str(tr.artist_id) == "a1" and (tr.artists as Array).size() == 2, "Titel kennt seine Künstler mit ID")
	check(str(Music.track_from({ "uri": "spotify:track:2", "artists": [] }).artist_id) == "", "ohne Künstler: keine ID")
	Music.now = { "title": "X", "artist": "Nobuo Uematsu, Jemand", "artists": [] }
	check(Music.artist_of_now() == { "id": "", "name": "Nobuo Uematsu" }, "Windows-Titel: erster Name ohne ID")
	Music.now = { "title": "X", "artist": "A, B", "artist_id": "a1", "artists": [{ "id": "a1", "name": "A" }] }
	check(Music.artist_of_now() == { "id": "a1", "name": "A" }, "Spotify-Titel: erster Künstler mit ID")
	Music.now = {}
	check(Music.artist_of_now().is_empty(), "nichts läuft: kein Künstler")

	print("Künstler aus der API")
	var ar := Music.artist_from({ "id": "k", "uri": "spotify:artist:k", "name": "Koji", "followers": { "total": 1234567 }, "genres": ["game", ""],
		"images": [{ "url": "640" }, { "url": "320" }] })
	check(str(ar.kind) == "artist" and str(ar.art) == "320" and str(ar.art_big) == "640" and int(ar.followers) == 1234567 and ar.genres == ["game"],
			"Bild, Follower, Genres")
	var bare := Music.artist_from({ "id": "k2", "name": "Ohne", "images": null, "followers": null, "genres": null })
	check(str(bare.uri) == "spotify:artist:k2" and str(bare.art) == "" and int(bare.followers) == -1 and (bare.genres as Array).is_empty(),
			"Development Mode: fehlende Felder stören nicht")
	check(Music.artist_from(null).is_empty() and Music.artist_from({ "name": "ohne id" }).is_empty(), "leere Treffer übersprungen")
	check(ArtistPage.meta_text(ar, 3) == "1,2 Mio. Follower  ·  game  ·  3 Veröffentlichungen", "Angaben: " + ArtistPage.meta_text(ar, 3))
	check(ArtistPage.meta_text(bare, 0) == "" and ArtistPage.count_text(45210) == "45 Tsd." and ArtistPage.count_text(812) == "812",
			"ohne Angaben leer; Zahlen kurz")

	print("Veröffentlichungen")
	var rel := Music.split_releases([
		{ "uri": "spotify:album:1", "id": "1", "name": "Erstes", "album_type": "album", "release_date": "2019-01-01", "album_group": "album" },
		{ "uri": "spotify:album:2", "id": "2", "name": "Neues", "album_type": "album", "release_date": "2024-05-01", "album_group": "album" },
		{ "uri": "spotify:album:3", "id": "3", "name": "neues", "album_type": "album", "release_date": "2024-05-01", "album_group": "album" },
		{ "uri": "spotify:album:4", "id": "4", "name": "Single", "album_type": "single", "release_date": "2025-01-01", "album_group": "single" },
		{ "uri": "spotify:album:5", "id": "5", "name": "Sampler", "album_type": "compilation", "release_date": "2026-01-01", "album_group": "appears_on" },
		null,
	])
	check((rel.albums as Array).map(func(a): return str(a.id)) == ["2", "1"], "Alben neueste zuerst, doppelte Fassung nur einmal")
	check((rel.singles as Array).map(func(a): return str(a.id)) == ["4"], "Singles getrennt, „erscheint auf“ raus")
	var hits := [Music.track_from({ "uri": "spotify:track:x", "id": "x", "artists": [{ "id": "k", "name": "Koji" }] }),
		Music.track_from({ "uri": "spotify:track:y", "id": "y", "artists": [{ "id": "z", "name": "Koji Cover" }] }),
		Music.track_from({ "uri": "spotify:track:w", "id": "w", "artists": [{ "id": "q", "name": "Feat" }, { "id": "k", "name": "Koji" }] })]
	check(Music.tracks_of_artist(hits, "k", "Koji").map(func(t): return str(t.id)) == ["x", "w"], "Suchtreffer als Ersatz für Top-Titel: nur mit dem Künstler")
	_alle_titel()

	print("Suche")
	var sr := Music.parse_search({ "tracks": { "items": [{ "uri": "spotify:track:1", "id": "1", "name": "T", "artists": [] }, null] },
		"artists": { "items": [{ "id": "k", "name": "K" }, null] }, "albums": { "items": [] }, "playlists": { "items": [null] } })
	check((sr.tracks as Array).size() == 1 and (sr.artists as Array).size() == 1 and (sr.albums as Array).is_empty() and (sr.playlists as Array).is_empty(),
			"Titel, Künstler, Alben, Playlists; null übersprungen")
	check((Music.parse_search(null).artists as Array).is_empty(), "keine Antwort: leere Listen")
	var ds := Music.demo_search("toby")
	check((ds.artists as Array).size() == 1 and str(ds.artists[0].name) == "Toby Fox" and (ds.tracks as Array).size() == 2,
			"Vorführung: Künstler und Titel gefunden")
	var da := Music.demo_artist("Koji Kondo")
	var titles: Array = (da.top as Array).map(func(t): return str(t.title))
	var uniq := {}
	for t in titles:
		uniq[t] = true
	check(bool(da.ok) and titles.size() == 8 and uniq.size() == 8 and not (da.albums as Array).is_empty() and not (da.singles as Array).is_empty(),
			"Vorführung: Künstlerseite mit acht verschiedenen Titeln, Alben und Singles")


func _zusammen_hoeren() -> void:
	print("Song schicken: alle Freunde")
	var steam := [{ "id": "1", "name": "Tom", "state": "offline", "game": "" }, { "id": "2", "name": "Mira", "state": "game", "game": "Hades" },
		{ "id": "3", "name": "Lea", "state": "away", "game": "" }, { "id": "4", "name": "Kai", "state": "online", "game": "" }]
	var disc := [{ "id": "d1", "name": "Sana", "state": "online", "game": "Balatro", "dm": true }, { "id": "d2", "name": "Ben", "state": "offline", "game": "" }]
	var all := MusicShare.targets(steam, disc, true)
	check(all.map(func(e): return str(e.name)) == ["Mira", "Sana", "Kai", "Lea", "Ben", "Tom"],
			"online zuerst (Spiel, online, abwesend), Offline am Ende: " + str(all.map(func(e): return str(e.name))))
	check(str(all[1].kind) == "discord" and str(all[1].sub) == "Spielt Balatro" and not bool(all[5].online), "Discord-Freunde dabei, Offline wählbar")
	check(MusicShare.targets(steam, disc, false).size() == 4, "ohne Discord-Nachrichten nur Steam")
	check(MusicShare.targets([], [], true).is_empty(), "keine Freunde: leer")

	print("Zusammen hören")
	check(Music.jam_link("https://open.spotify.com/socialsession/abc123") != "" and Music.jam_link(" https://spotify.link/xyz ") == "https://spotify.link/xyz",
			"Jam-Link aus der Zwischenablage erkannt")
	check(Music.jam_link("https://example.com/x") == "" and Music.jam_link("hallo du") == "", "anderes ist kein Jam-Link")
	var song := { "title": "To Zanarkand", "artist": "Nobuo Uematsu" }
	var t1 := Music.together_text(song, "https://open.spotify.com/track/x", "", 95000)
	check(t1.contains("„To Zanarkand“ von Nobuo Uematsu") and t1.contains("1:35") and t1.ends_with("https://open.spotify.com/track/x"),
			"Einladung mit Titel, Stelle und Link: " + t1)
	var t2 := Music.together_text(song, "https://open.spotify.com/track/x", "https://open.spotify.com/socialsession/j", 0)
	check(t2.contains("Spotify-Jam") and t2.ends_with("socialsession/j") and not t2.contains("track/x"), "mit Jam-Link: in die Jam")
	var t3 := Music.together_text(song, "https://open.spotify.com/track/x", "https://spotify.link/j", 0)
	check(not t3.contains("Jam") and t3.ends_with("https://spotify.link/j"), "Kurzlink: ohne „Jam offen“")
	check(Music.hears(song, "Uzai", "To Zanarkand", "von Nobuo Uematsu") == "gleich", "Uzais Musikstatus beim Freund: derselbe Titel")
	check(Music.hears(song, "Spotify", "to zanarkand", "Nobuo Uematsu") == "gleich", "Spotify-Status: derselbe Titel, groß/klein egal")
	check(Music.hears(song, "Spotify", "Anderer Titel", "X") == "spotify" and Music.hears(song, "Hades", "", "") == "",
			"anderer Titel: nur „hört Spotify“; Spiel: nichts")
	check(Music.hears(song, "Uzai", "To Zanarkand", "von Jemand anderem") == "", "gleicher Titel, anderer Künstler: nicht dasselbe")
	var d2 := [{ "id": "d1", "name": "Sana", "state": "online", "game": "Uzai", "details": "To Zanarkand", "activity_state": "von Nobuo Uematsu" },
		{ "id": "d2", "name": "Ben", "state": "offline", "game": "Uzai", "details": "To Zanarkand", "activity_state": "" },
		{ "id": "d3", "name": "Kai", "state": "online", "game": "Spotify", "details": "Etwas", "activity_state": "" }]
	var s2 := [{ "id": "7", "name": "Lea", "state": "online", "game": "Spotify" }, { "id": "8", "name": "Kai", "state": "online", "game": "Spotify" }]
	var inv := { "steam:9": { "name": "Sana" } }
	var lst := Music.listening(song, d2, s2, inv)
	check(lst.map(func(l): return str(l.name)) == ["Sana", "Kai", "Lea"],
			"wer mithört: gleiche zuerst, Offline raus, jeder einmal: " + str(lst.map(func(l): return str(l.name))))
	check(str(lst[0].how) == "gleich" and bool(lst[0].invited) and not bool(lst[2].invited), "Einladung per Name erkannt (Steam eingeladen, Discord hört mit)")
	check(Music.listening({}, d2, s2).is_empty(), "nichts läuft: niemand hört mit")
	check(Music.together_line(lst, []) == "Sana hört mit", "Zeile: wer mithört")
	check(Music.together_line([], [{ "name": "Kai" }, { "name": "Lea" }]) == "Kai und Lea eingeladen – noch nicht dabei", "Zeile: eingeladen")
	check(
			Music.together_line([{ "name": "A", "how": "spotify" }, { "name": "B", "how": "spotify" }, { "name": "C", "how": "spotify" }],
			[]) == "A, B und 1 weitere hören auch Spotify", "Zeile: hören auch Spotify")
	check(Music.together_line([], []) == "", "Zeile: nichts")
	Music.now = {}
	check(not MusicShare.can_share(), "„Zusammen hören einladen“ nur, wenn ein Spotify-Titel läuft")
	Music.now = { "id": "x", "uri": "spotify:track:x", "title": "T", "playing": true }
	check(MusicShare.can_share(), "läuft ein Spotify-Titel: Einladen möglich")
	Music.now = {}


## „Alle Titel“: Veröffentlichungen sortieren, Titel zusammenfassen (ursprüngliche Fassung bleibt),
## Suchtreffer, Wartezeit bei 429, Angaben und die Vorführung.
func _alle_titel() -> void:
	print("Alle Titel: Veröffentlichungen")
	var rel := Catalog.parse_releases([
		{ "uri": "spotify:album:a", "id": "a", "name": "Alt", "album_type": "album", "release_date": "2010-02-01", "album_group": "album" },
		{ "uri": "spotify:album:s", "id": "s", "name": "Single", "album_type": "single", "release_date": "2024-01-01", "album_group": "single" },
		{ "uri": "spotify:album:n", "id": "n", "name": "Neu", "album_type": "album", "release_date": "2024-01-01", "album_group": "album" },
		{ "uri": "spotify:album:n2", "id": "n2", "name": "neu", "album_type": "album", "release_date": "2024-01-01", "album_group": "album" },
		{ "uri": "spotify:album:j", "id": "j", "name": "Jahr", "album_type": "album", "release_date": "2015", "release_date_precision": "year" },
		{ "uri": "spotify:album:g", "id": "g", "name": "Sampler", "album_type": "compilation", "release_date": "2020-01-01", "album_group": "appears_on" },
		null, { "name": "ohne uri" },
	])
	check(rel.map(func(a): return str(a.id)) == ["n", "s", "g", "j", "a"],
			"neueste zuerst, bei gleichem Datum Album vor Single, gleiche Fassung einmal: " + str(rel.map(func(a): return str(a.id))))
	check(str(rel[2].group) == "appears_on" and Catalog.album_line(rel[3]) == "Jahr · 2015" and Catalog.album_line({ "name": "Ohne" }) == "Ohne",
			"Gruppe gemerkt; Album mit Jahr")

	print("Alle Titel: gleiche Aufnahme erkennen")
	check(Catalog.norm_title("Hit - Remastered 2011") == "hit" and Catalog.norm_title("Hit (2009 Remaster)") == "hit"
			and Catalog.norm_title("Hit [Remastered]") == "hit", "Remaster-Zusätze fallen weg")
	check(Catalog.norm_title("  Mein   Lied ") == "mein lied" and Catalog.norm_title("Hit - Live") == "hit - live"
			and Catalog.norm_title("Re-Master-Plan") == "re-master-plan", "anderes bleibt (Live ist eine andere Aufnahme)")
	check(Catalog.same_track({ "title": "Hit", "duration": 200000 }, { "title": "HIT - 2011 Remaster", "duration": 201500 }),
			"gleicher Name, Länge bis 2 s gleich: dieselbe")
	check(not Catalog.same_track({ "title": "Hit", "duration": 200000 }, { "title": "Hit", "duration": 260000 }),
			"gleicher Name, andere Länge (z. B. Extended): verschieden")
	check(Catalog.release_rank({ "name": "Platte", "type": "album" }) == 0 and Catalog.release_rank({ "name": "Platte", "type": "single" }) == 1,
			"Album vor Single")
	check(Catalog.release_rank({ "name": "Platte (Deluxe Edition)", "type": "album" }) == 2
			and Catalog.release_rank({ "name": "Best Of", "type": "compilation" }) == 4, "Deluxe/Best of/Sampler hinten")
	check(Catalog.release_rank({ "name": "Platte", "type": "album" }, "Hit - Remastered 2011") == 2, "Remaster im Titelnamen zählt auch")

	print("Alle Titel: zusammenfassen")
	var mk := func(id: String, title: String, dur: int, al: Dictionary) -> Dictionary:
		return Catalog.decorate({ "id": id, "uri": "spotify:track:" + id, "title": title, "duration": dur, "art": "" }, al)
	var remaster := { "uri": "spotify:album:r", "id": "r", "name": "Platte (Remastered)", "type": "album", "date": "2021-01-01" }
	var orig := { "uri": "spotify:album:o", "id": "o", "name": "Platte", "type": "album", "date": "2001-01-01" }
	var single := { "uri": "spotify:album:s", "id": "s", "name": "Hit", "type": "single", "date": "2000-12-01" }
	var list: Array = []
	Catalog.merge(list, [mk.call("r1", "Hit - Remastered", 200000, remaster), mk.call("r2", "Zwei", 150000, remaster)])
	check(list.size() == 2 and str(list[0].album_line) == "Platte (Remastered) · 2021" and int(list[0].rank) == 2, "erste Runde: Remaster-Titel stehen da")
	var moved := Catalog.merge(list, [mk.call("o1", "Hit", 200700, orig), mk.call("o2", "Zwei", 150300, orig), mk.call("o3", "Drei", 99000, orig)])
	check(moved and list.map(func(t): return str(t.id)) == ["o1", "o2", "o3"],
			"Original ersetzt das Remaster (rückt ans Ende, Reihenfolge bleibt): " + str(list.map(func(t): return str(t.id))))
	moved = Catalog.merge(list, [mk.call("s1", "Hit", 200000, single), mk.call("o3b", "Drei", 99000, orig)])
	check(not moved and list.size() == 3 and str(list[0].id) == "o1", "ältere Single verdrängt die Albumfassung nicht; dieselbe zweimal: einmal")
	var older := { "uri": "spotify:album:x", "id": "x", "name": "Erstes", "type": "album", "date": "1999-01-01" }
	moved = Catalog.merge(list, [mk.call("x1", "Zwei", 150000, older)])
	check(moved and str(list[-1].id) == "x1" and list.size() == 3, "gleicher Rang: die ältere Veröffentlichung bleibt")
	var s_list: Array = [mk.call("a", "Eins", 100000, remaster), mk.call("b", "Zwei", 100000, remaster)]
	Catalog.merge(s_list, [mk.call("c", "Eins", 100000, orig)], true)
	check(s_list.map(func(t): return str(t.id)) == ["c", "b"], "Suche: bessere Fassung an derselben Stelle")
	Catalog.merge(s_list, [{ "title": "ohne uri" }, null, mk.call("d", "", 5, orig)])
	check(s_list.size() == 3, "Einträge ohne URI übersprungen")

	print("Alle Titel: Titel eines Albums und Suchtreffer")
	var raw := [
			{ "type": "track", "id": "t1", "uri": "spotify:track:t1", "name": "Mit", "duration_ms": 1000,
			"artists": [{ "id": "k", "name": "K" }, { "id": "z", "name": "Z" }] },
		{ "type": "track", "id": "t2", "uri": "spotify:track:t2", "name": "Ohne", "duration_ms": 1000, "artists": [{ "id": "z", "name": "Z" }] }, null]
	var rt := Catalog.release_tracks(raw, rel[2], "k")
	check(rt.size() == 1 and str(rt[0].title) == "Mit" and str(rt[0].album_uri) == "spotify:album:g" and int(rt[0].rank) == 2,
			"Gastauftritt: nur Titel mit dem Künstler, Album zum Abspielen")
	check(Catalog.release_tracks(raw, rel[0]).size() == 2 and str(Catalog.release_tracks(raw, rel[0])[0].album) == "Neu",
			"eigenes Album: alle Titel mit Albumname")
	var sr := Catalog.search_tracks([{ "type": "track", "id": "q1", "uri": "spotify:track:q1", "name": "Q", "artists": [{ "id": "k", "name": "K" }],
		"album": { "uri": "spotify:album:qa", "id": "qa", "name": "Quelle", "album_type": "single", "release_date": "2018-05-05" } },
		{ "type": "track", "id": "q2", "uri": "spotify:track:q2", "name": "Q2", "artists": [{ "id": "y", "name": "K Cover" }], "album": null }], "k", "K")
	check(sr.size() == 1 and str(sr[0].album_line) == "Quelle · 2018" and int(sr[0].rank) == 1 and str(sr[0].date) == "2018-05-05",
			"Suchtreffer: nur der Künstler, mit Album, Jahr und Rang")
	check(Catalog.wait_secs("3", 0) == 3 and Catalog.wait_secs("", 0) == 2 and Catalog.wait_secs("x", 2) == 6 and Catalog.wait_secs("0", 0) == 1,
			"429: Retry-After in Sekunden, sonst 2, 4, 6 …")

	print("Alle Titel: Angaben und Vorführung")
	check(ArtistTracks.meta_text(0, "", -1, 0, false) == "", "lädt noch: keine Zeile (Platzhalter statt „Lädt …“)")
	check(ArtistTracks.meta_text(24, "alben", 9, 3, false) == "24 Titel  ·  3 von 9 Veröffentlichungen",
			"unterwegs: " + ArtistTracks.meta_text(24, "alben", 9, 3, false))
	check(ArtistTracks.meta_text(61, "alben", 9, 9, true) == "61 Titel  ·  aus 9 Veröffentlichungen"
			and ArtistTracks.meta_text(1, "suche", -1, 0, true) == "1 Titel  ·  aus der Suche", "fertig und aus der Suche")
	var drel := Music.demo_artist_releases("Nobuo Uematsu")
	var all: Array = []
	for al in drel:
		Catalog.merge(all, Catalog.release_tracks(Music.demo_release_items(al, "Nobuo Uematsu"), al))
	var dt: Array = all.map(func(t): return str(t.title))
	check(drel.size() >= 8 and all.size() >= 40, "Vorführung: %d Veröffentlichungen, %d Titel" % [drel.size(), all.size()])
	check(dt.has("To Zanarkand") and dt.has("Klavierstück Nr. 1") and not dt.any(func(x): return str(x).contains("Remastered")),
			"Vorführung: bekannte Titel dabei, Remaster zusammengefasst")
	var kl: Dictionary = all[dt.find("Klavierstück Nr. 1")]
	check(str(kl.album) == "Klavierstücke", "Vorführung: das Original bleibt (nicht Best of, nicht Remaster)")
	check(Music.demo_artist_releases("Nobuo Uematsu", true).size() == drel.size() + 1, "Vorführung: mit Gastauftritten ein Sampler mehr")


## Soft background, volume control in „Läuft gerade“, music apps only.
func _rueckmeldung7() -> void:
	print("Nur Musik-Apps (keine Browser, Videos, Discord, Spiele)")
	var yes := ["Spotify.exe", "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", "C:\\Program Files\\foobar2000\\foobar2000.exe", "MusicBee.exe",
		"AIMP.exe", "winamp.exe", "AppleInc.AppleMusicWin_nzyj5cx40ttqa!App", "iTunes.exe", "TIDAL.exe", "Deezer.exe", "Amazon Music.exe", "MediaMonkey.exe"]
	var all_yes := true
	for a in yes:
		if not Music.is_music_app(a):
			all_yes = false
			print("    nicht erkannt: ", a)
	check(all_yes, "Spotify (Programm und Store-App) und Musik-Player zählen")
	var no := ["Chrome", "chrome.exe", "MSEdge", "308046B0AF4A39CB", "opera.exe", "Brave.ABC123", "Vivaldi.XYZ", "Discord.exe", "com.squirrel.Discord.Discord",
		"com.github.th-ch.youtube-music", "Chrome._crx_cinhimbnkkaeohfgghhklpknlkffjgod", "steam.exe", "eldenring.exe",
			"Microsoft.ZuneVideo_8wekyb3d8bbwe!Microsoft.ZuneVideo",
		"Netflix", "mpv.exe", "Uzai.exe", "", "  "]
	var all_no := true
	for a in no:
		if Music.is_music_app(a, Music.PT_MUSIC):
			all_no = false
			print("    fälschlich Musik: ", a)
	check(all_no, "Browser (auch YouTube darin), YouTube Music, Discord, Steam, Spiele, Videos, Uzai: nie")
	var zune := "Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic"
	check(Music.is_music_app(zune, Music.PT_MUSIC) and not Music.is_music_app(zune, Music.PT_VIDEO) and not Music.is_music_app(zune, Music.PT_UNKNOWN),
			"Medienwiedergabe: nur wenn sie Musik spielt, nicht bei Videos")
	check(Music.is_music_app("vlc.exe", Music.PT_MUSIC) and not Music.is_music_app("vlc.exe", Music.PT_VIDEO), "VLC: Musik ja, Video nein")
	check(Music.is_music_app("Spotify.exe", Music.PT_VIDEO), "Video-Podcast in Spotify ist trotzdem Spotify")
	print("Welche Sitzung")
	var chrome := { "app": "Chrome", "playing": true, "type": Music.PT_VIDEO }
	var spot := { "app": "Spotify.exe", "playing": false, "type": Music.PT_MUSIC }
	var foo := { "app": "foobar2000.exe", "playing": true, "type": Music.PT_MUSIC }
	check(Music.pick_session([chrome, spot], "Chrome") == 1, "YouTube im Browser läuft, Spotify pausiert: Spotify")
	check(Music.pick_session([spot, foo], "Spotify.exe") == 1, "spielende Musik-App vor der pausierten aktuellen")
	check(Music.pick_session([foo, { "app": "MusicBee.exe", "playing": true }], "MusicBee.exe") == 1, "beide spielen: die aktuelle")
	check(Music.pick_session([spot, { "app": "MusicBee.exe", "playing": false }], "") == 0, "nichts spielt: die erste")
	check(Music.pick_session([chrome, { "app": "MSEdge", "playing": true }], "Chrome") == -1 and Music.pick_session([], "") == -1, "nur Browser: keine")
	var mf: Dictionary = Music.media_filter()
	check(mf.allow == Music.MUSIC_APPS and mf.audio == Music.MUSIC_IF_AUDIO and mf.deny == Music.NOT_MUSIC, "Helfer bekommt dieselben Listen")
	var msrc := Quelle.lesen("res://src/core/music.gd")
	check(msrc.contains("Helper.run(\"media-info\", media_filter()") and msrc.contains("is_music_app(str(r.result.get(\"app\""),
			"Abfrage mit Listen und doppelt geprüft (auch bei älterem Helfer)")
	check(not msrc.contains("Helper.run(\"media\", {") and msrc.contains("func media_key("), "Medientasten nur über media_key (gezielt an die Musik-App)")
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(ps.contains("function Find-MusicSession") and ps.contains("GetSessions()") and ps.contains("'media-info' { return (Get-MediaInfo $a) }"),
			"Helfer: sucht unter allen Sitzungen die Musik-App")
	check(ps.contains("TryTogglePlayPauseAsync") and ps.contains("TrySkipNextAsync") and ps.contains("TrySkipPreviousAsync") and ps.contains("other = $true"),
			"Helfer: Tasten an die Sitzung der Musik-App, sonst nichts")
	check(ps.contains("type = (Get-PlaybackType $s)"), "Helfer meldet die Art der Sitzung (Musik/Video)")

	print("Lautstärke der Musik")
	check(Music.volume_plan({ "title": "A", "source": "windows", "app": "Spotify.exe" }, true, true) == "app", "Musik-App über Windows: ihre Audiositzung")
	check(Music.volume_plan({ "title": "A", "volume": 40, "device_type": "Computer" }, true, true) == "spotify", "Spotify meldet Lautstärke: Web-API")
	check(Music.volume_plan({ "title": "A", "volume": -1, "device_type": "Computer" }, true, true) == "spotify_app",
			"Spotify ohne Lautstärke am PC: Spotify-App im Mixer")
	check(Music.volume_plan({ "title": "A", "volume": -1, "device_type": "Speaker" }, true, true) == "spotify_fest", "Lautsprecher ohne Lautstärke: nur Hinweis")
	check(Music.volume_plan({ "title": "A", "volume": -1 }, true, false) == "spotify_fest", "ohne Windows: kein Mixer")
	check(Music.volume_plan({}, true, true) == "" and Music.volume_plan({ "title": "A" }, false, true) == "",
			"nichts läuft bzw. ohne Konto und ohne Windows-Quelle: nichts")
	check(not msrc.contains("Helper.run(\"volume\"") and not msrc.contains("\"volup\"") and not msrc.contains("\"voldown\""),
			"nie die Gesamtlautstärke von Windows")
	Music.now = { "title": "A", "source": "windows", "app": "MusicBee.exe", "device": "MusicBee", "volume": -1 }
	Music.app_level = 30
	Music.set("_app_level_key", Music.level_key(Music.now))
	check(Music.shown_volume() == 30, "Regler zeigt den Pegel der Musik-App")
	Music.now = { "title": "B", "source": "windows", "app": "AIMP.exe", "device": "AIMP", "volume": -1 }
	check(Music.shown_volume() == -1, "andere App: Pegel erst lesen, nicht den alten zeigen")
	Music.now = { "title": "C", "volume": 62 }
	check(Music.shown_volume() == 62, "Spotify: Wert von Spotify")
	Music.now = {}
	Music.app_level = -1
	check(MusicView.vol_fail_text("spotify_fest", "Küche").contains("Küche") and MusicView.vol_fail_text("kein_ton", "AIMP") == "Kein Ton von AIMP gefunden"
		and MusicView.vol_fail_text("keine_musik", "") == "Gerade läuft keine Musik", "klare Hinweise, wenn nichts zu stellen ist")
	var vsrc := FileAccess.get_file_as_string("res://src/ui/sections/music_view.gd")
	check(not vsrc.contains("func trigger(cmd: String) -> bool") and vsrc.contains("\"uz_grid_nav\"") and vsrc.contains("Music.change_volume("),
			"Läuft gerade: Lautstärke am Regler (links/rechts), LT/RT wechseln wie überall den Bereich")
	var main_src := Quelle.lesen("res://src/main.gd")
	check(not main_src.contains("has_method(\"trigger\")"), "main fragt keinen Bereich mehr nach LT/RT (kein Bereich nimmt sie)")
	check(FileAccess.get_file_as_string("res://src/ui/components/hint_bar.gd").contains("\"extra_hints\""), "Hinweisleiste zeigt LT/RT Musik-Lautstärke")
	check(Guide.volume_hint("spotify_fest") == "Spotify-Lautstärke"
			and Quelle.lesen("res://src/ui/layers/guide.gd").contains("Music.change_volume("),
			"Guide: Spotify ohne Lautstärke geht über die Spotify-App")

	print("Weicher Hintergrund (Albumbild)")
	check(vsrc.contains("show_soft(t, \"music:\" + url)") and not vsrc.contains("show_texture(t, \"music:\""), "Läuft gerade: Albumbild weich wie ein Spiel-Cover")
	check(vsrc.contains("main.background.show_soft(tex, \"mt:\""), "gewählte Kachel: ebenso")
	var bsrc := FileAccess.get_file_as_string("res://src/ui/components/background.gd")
	check(bsrc.contains("func show_soft(") and bsrc.contains("Media.soft(t, ART_STEPS") and bsrc.contains("-soft_radius(ART_STEPS)"),
			"show_soft: klein gerechnet (Hintergrund-Thread) und im Shader geglättet")
	var src := Image.create(640, 640, false, Image.FORMAT_RGBA8)
	src.fill(Color(0.2, 0.3, 0.4))
	var soft: Image = BG.soft_image(src, BG.ART_STEPS)
	check(soft.get_width() <= BG.ART_STEPS * 2 and soft.get_width() >= BG.ART_STEPS and not soft.has_mipmaps(),
			"640-Punkte-Albumbild → %d Punkte, ohne Mipmaps" % soft.get_width())


## Mit Spotify angemeldet (Spotify-Sitzung im Browser-Kern): Regeln der Sitzung, Schlüssel von der Seite, Ablauf und
## Erneuern, Rückfall in den Grundmodus, Abmelden, nichts Geheimes in Protokoll und Einstellungen; dazu welche
## Anmeldung gilt, Mixe aus „Für dich gemacht“ und made-for-x, context-resolve, Titellisten.
func _wie_die_app() -> void:
	await _web_sitzung()
	print("Wie die Spotify-App: welche Anmeldung gilt")
	var keep := {}
	for k in ["spotify_client_id", "spotify_refresh", "spotify_web", "spotify_mode"]:
		keep[k] = Config.get_value("accounts." + k, "")
	Config.set_value("accounts.spotify_client_id", "")
	Config.set_value("accounts.spotify_refresh", "")
	Config.set_value("accounts.spotify_web", false)
	Config.set_value("accounts.spotify_mode", "")
	check(Music.login_mode() == "" and not Music.has_spotify() and not Music.mix_titles() and Music.search_limit() == 10, "ohne Anmeldung: nichts")
	Config.set_value("accounts.spotify_client_id", "id")
	Config.set_value("accounts.spotify_refresh", "r")
	check(Music.login_mode() == "eigen" and Music.has_spotify() and not Music.mix_titles(), "nur eigene Client-ID (wie bisher)")
	Config.set_value("accounts.spotify_web", true)
	check(Music.login_mode() == "eigen" and not Music.mix_titles() and Music.search_limit() == 10, "beide: die eigene App zuerst (Spotify sperrt den App-Weg)")
	Config.set_value("accounts.spotify_mode", "app")
	check(Music.login_mode() == "app" and Music.mix_titles() and Music.search_limit() == 20, "App-Anmeldung ausdrücklich gewählt: die App")
	var i_mix := TrackList.info_for({ "kind": "spotify_mix", "id": "rr", "name": "Release Radar", "sub": "Jeden Freitag neu", "uri": "spotify:playlist:rr" })
	check(not i_mix.has("restricted") and TrackList.loader_for({ "kind": "spotify_mix", "id": "rr" }).is_valid(),
			"Mix von Spotify: Titelliste wie bei einer Playlist")
	Config.set_value("accounts.spotify_mode", "eigen")
	check(Music.login_mode() == "eigen", "eigene gewählt: die eigene")
	Config.set_value("accounts.spotify_mode", "app")
	Music.set("_app_off_until", int(Time.get_unix_time_from_system()) + 100)
	check(Music.login_mode() == "eigen", "App-Anmeldung abgelehnt: eigene übernimmt für eine Weile")
	Config.set_value("accounts.spotify_refresh", "")
	check(Music.login_mode() == "app", "ohne eigene bleibt es bei der App (mit Hinweis)")
	Music.set("_app_off_until", 0)
	# Obergrenze: höchstens BUDGET_READ lesende Anfragen je 30 s, Steuern bis BUDGET_ALL.
	var b_keep: Array = Music.get("_budget")
	var b: Array = []
	for i in Music.BUDGET_READ:
		b.append(Time.get_ticks_msec())
	Music.set("_budget", b)
	check(not Music.budget_ok(true) and Music.budget_ok(false), "Obergrenze: Lesen wartet, Steuern geht noch")
	var old_b: Array = []
	for i in Music.BUDGET_ALL:
		old_b.append(Time.get_ticks_msec() - Music.BUDGET_WINDOW_MS - 1000)
	Music.set("_budget", old_b)
	check(Music.budget_ok(true) and (Music.get("_budget") as Array).is_empty(), "Obergrenze: ältere als 30 s zählen nicht")
	Music.set("_budget", b_keep)
	for k in keep:
		Config.set_value("accounts." + k, keep[k])

	print("Wie die Spotify-App: Mixe")
	var mfx := { "content": { "items": [
		{ "type": "view", "content": { "items": [{ "uri": "spotify:playlist:rep", "name": "On Repeat", "owner": { "id": "spotify" } },
			{ "uri": "spotify:album:x", "name": "Album" }] } },
		{ "type": "view",
			"content": { "items": [{ "uri": "spotify:playlist:cap", "name": "Time Capsule", "owner": { "id": "spotify" }, "images": [{ "url": "c" }] }] } }] } }
	var pls: Array = Music.collect_playlists(mfx)
	check(pls.size() == 2 and str(pls[1].name) == "Time Capsule", "made-for-x: Playlists aus verschachtelten Ansichten, Alben nicht")
	check(Music.collect_playlists({ "playlists": { "items": [null, { "uri": "spotify:playlist:a", "name": "A" }] } }).size() == 1,
			"Kategorie: playlists.items, leere Einträge weg")
	check(Music.spotify_mix_kind("Deine Zeitkapsel") == "capsule" and Music.spotify_mix_kind("Repeat Rewind") == "rewind"
			and Music.spotify_mix_kind("daylist • chill dienstag") == "daylist", "Zeitkapsel, Repeat Rewind, daylist")
	var found: Array = [
		{ "id": "chill", "name": "Chill Mix", "owner_id": "spotify", "mfy": true },
		{ "id": "edit", "name": "Top Hits Deutschland", "owner_id": "spotify" },
		{ "id": "cap", "name": "Deine Zeitkapsel", "owner_id": "spotify" },
		{ "id": "rr", "name": "Release Radar", "owner_id": "spotify", "mfy": true },
		{ "id": "fan", "name": "Chill Mix", "owner_id": "fan", "mfy": true },
	]
	var ids: Array = Music.pick_spotify_mixes(found).map(func(m): return str(m.id))
	check(ids == ["rr", "cap", "chill"], "Release Radar, Zeitkapsel, dann weitere aus „Für dich gemacht“ – keine Redaktions-Listen, keine Fans: " + str(ids))
	var many: Array = []
	for n in 30:
		many.append({ "id": "m%d" % n, "name": "Mix %d" % n, "owner_id": "spotify", "mfy": true })
	check(Music.pick_spotify_mixes(many).size() == 16, "höchstens 16 Mixe")

	print("Wie die Spotify-App: context-resolve")
	var ctx := Music.context_tracks({ "pages": [
		{
			"tracks": [{ "uri": "spotify:track:a1", "metadata": { "title": "Eins", "artist_name": "K", "duration": "1000" } }, { "uri": "spotify:episode:e" },
			{ "uri": "spotify:track:a2" }] },
		{ "page_url": "hm://context-resolve/v1/page/2" }] })
	check((ctx.tracks as Array).size() == 2 and str(ctx.tracks[0].title) == "Eins" and int(ctx.tracks[0].duration) == 1000
			and str(ctx.next) == "hm://context-resolve/v1/page/2", "Titel-URIs, Angaben aus der Liste, Folgeseite")
	check(Music.spclient_url("https://sp", "hm://a/b") == "https://sp/a/b" and Music.spclient_url("https://sp", "/a") == "https://sp/a"
		and Music.spclient_url("https://sp", "https://x/y") == "https://x/y" and Music.spclient_url("https://sp", "") == "", "Folgeseiten: hm:// und /… auf spclient")
	var lsrc := FileAccess.get_file_as_string("res://src/ui/layers/spotify_anmelden.gd")
	check(lsrc.contains("l.set(\"spotify\", true)") and lsrc.contains("Web.ANMELDEN_URL") and not FileAccess.file_exists("res://src/ui/layers/spotify_app_login.gd"),
			"Anmelde-Ebene: die Anmeldeseite im Uzai-Browser (Spotify-Modus), der QR-Weg ist ersetzt")
	var lb := FileAccess.get_file_as_string("res://src/ui/components/leer_buehne.gd") + FileAccess.get_file_as_string("res://src/ui/layers/setup_wizard_konten.gd")
	check(lb.contains("spotify_anmelden.gd\").start(") and not lb.contains("[\"Per QR-Code\"") and not lb.contains("[\"Eigene Spotify-App\""), "Bühne und Einrichtung: gleich „Mit Spotify anmelden“, ohne Wahl-Dialog")
	var texte := ""
	for f in ["res://src/ui/sections/settings_konten.gd", "res://src/ui/sections/music_view.gd", "res://src/ui/layers/spotify_check.gd",
			"res://src/core/music_spotify.gd", "res://src/core/music.gd", "res://src/core/music_listen.gd", "res://src/ui/layers/spotify_anmelden.gd"]:
		for line in FileAccess.get_file_as_string(f).split("\n"):
			if not line.strip_edges().begins_with("#"):
				texte += line + "\n"
	var verboten: Array = ["inoffiziell", "kann gesperrt", "nicht von Spotify", "Per QR-Code anmelden", "Mit QR-Code anmelden", "neu anmelden (QR-Code)",
			"QR-Anmeldung\" if using"].filter(
			func(w: String) -> bool: return texte.contains("\"" + w) or texte.contains(" " + w))
	check(verboten.is_empty(), "keine Warnprosa und kein QR-Weg in sichtbaren Texten %s" % str(verboten))


## Spotify-Sitzung ohne Netz und ohne Kern: die Seite ist ein nachgebautes Callable (Web.quelle).
func _web_sitzung() -> void:
	print("Mit Spotify angemeldet: Regeln der Sitzung")
	check(Web.erlaubt("https://accounts.spotify.com/de/login?continue=x") and Web.erlaubt("https://open.spotify.com/") and Web.erlaubt("https://challenge.spotify.com/c/x")
			and Web.erlaubt("https://accounts.google.com/o/oauth2") and Web.erlaubt("https://appleid.apple.com/auth"), "Spotify und seine Anmeldedienste")
	check(not Web.erlaubt("http://open.spotify.com/") and not Web.erlaubt("https://spotify.com.boese.de/") and not Web.erlaubt("https://boese-spotify.com/")
			and not Web.erlaubt("https://example.com/") and not Web.erlaubt("javascript:alert(1)") and not Web.erlaubt("https://127.0.0.1/")
			and not Web.erlaubt("https://www.google.com/search"), "sonst nichts: kein http, keine fremden oder ähnlichen Namen, nicht dieser PC")
	var tok := "BQD" + "aB3-_x9".repeat(20)
	var ct := "AAE" + "q+/=Zz0".repeat(20)
	var w := Web.aus_ereignis({ "t": "spotify", "token": tok, "client": ct, "version": "1.2.73.157.gd7f98bd8" })
	check(str(w.get("token", "")) == tok and str(w.client) == ct and str(w.version) == "1.2.73.157.gd7f98bd8", "Schlüssel, Client-Token und Fassung aus dem Ereignis")
	check(Web.aus_ereignis({ "t": "spotify", "token": "kurz", "client": "", "version": "" }).is_empty()
			and Web.aus_ereignis({ "t": "spotify", "token": tok + " x", "client": "", "version": "" }).is_empty()
			and Web.aus_ereignis({ "t": "spotify", "token": "x".repeat(2049), "client": "", "version": "" }).is_empty()
			and Web.aus_ereignis({ "t": "tab", "token": tok }).is_empty(), "zu kurz, fremde Zeichen, zu lang, andere Art: verworfen")
	var w2 := Web.aus_ereignis({ "t": "spotify", "token": tok, "client": "a b", "version": "1.2;x" })
	check(not w2.is_empty() and str(w2.client) == "" and str(w2.version) == "", "kaputter Client-Token oder Fassung: ohne sie weiter")
	var pe := P.ereignis(JSON.stringify({ "t": "spotify", "token": tok, "client": ct, "version": "1.2.3" }))
	check(str(pe.get("token", "")) == tok and P.ereignis(JSON.stringify({ "t": "spotify", "token": "a\u0000b", "client": "", "version": "" })).is_empty()
			and P.ereignis(JSON.stringify({ "t": "spotify", "token": tok, "client": "", "version": "", "mehr": 1 })).size() == 4,
			"Leitung: festes Schema (Zeichensatz, Länge, fremde Felder fallen weg)")
	check(Web.auf_anmeldung("https://accounts.spotify.com/de/login?continue=https%3A%2F%2Fopen.spotify.com%2F") and not Web.auf_anmeldung("https://open.spotify.com/")
			and not Web.auf_anmeldung("https://accounts.spotify.com/de/status"), "Seite auf der Anmeldung erkannt")
	check(Music.web_konto_urteil(200, { "data": { "me": { "profile": { "username": "lena", "name": "Lena" } } } }) == "ja"
			and Music.web_konto_urteil(200, { "data": { "me": null } }) == "nein" and Music.web_konto_urteil(401, null) == "nein"
			and Music.web_konto_urteil(0, null) == "?" and Music.web_konto_urteil(400, { "errors": [] }) == "?", "Konto prüfen: ja, nein, unklar")
	# Abmelden löscht den Ordner der Sitzung – nur unter …/Uzai/browser/spotify-daten/profil/<kennung>.
	var basis := OS.get_user_data_dir().path_join("t_spotify/Uzai/browser/spotify-daten/profil/standard")
	DirAccess.make_dir_recursive_absolute(basis.path_join("Network"))
	var fh := FileAccess.open(basis.path_join("Network/Cookies"), FileAccess.WRITE)
	fh.store_string("sp_dc")
	fh.close()
	check(not Web.ordner_loeschen(OS.get_user_data_dir()) and not Web.ordner_loeschen(basis + "/../../x") and DirAccess.dir_exists_absolute(basis),
			"fremde Pfade löscht es nie")
	check(Web.ordner_loeschen(basis) and not DirAccess.dir_exists_absolute(basis), "Ordner der Sitzung ganz gelöscht (Cookies, Speicher)")
	check(Music.app_uri({ "context_uri": "spotify:playlist:" + "a".repeat(22) }) == "spotify:playlist:" + "a".repeat(22)
			and Music.app_uri({ "uris": ["spotify:track:" + "b".repeat(22)] }) == "spotify:track:" + "b".repeat(22)
			and Music.app_uri({ "context_uri": "spotify:playlist:x;calc" }) == "" and Music.app_uri(null) == "", "ohne Premium: spotify:-Adresse für die Spotify-App, nur geprüfte Formen")

	print("Mit Spotify angemeldet: Schlüssel von der Seite")
	var keep := {}
	for k in ["spotify_client_id", "spotify_refresh", "spotify_web", "spotify_mode", "spotify_app_refresh"]:
		keep[k] = Config.get_value("accounts." + k, "")
	var keep_partner: String = Music.get("_partner")
	var keep_api: String = Music.get("_api_base")
	Music.set("_partner", "http://127.0.0.1:9/pathfinder")   # kein Netz: die Kontoprüfung bleibt unklar und hält nichts auf
	Music.set("_api_base", "http://127.0.0.1:9/v1")
	Config.set_value("accounts.spotify_client_id", "")
	Config.set_value("accounts.spotify_refresh", "")
	Config.set_value("accounts.spotify_mode", "")
	Config.set_value("accounts.spotify_app_refresh", "alte-qr-erneuerung")
	Music._qr_weg_vergessen()
	check(str(Config.get_value("accounts.spotify_app_refresh", "")) == "", "frühere QR-Anmeldung beim Start gelöscht")
	Config.set_value("accounts.spotify_web", true)
	check(Music.login_mode() == "app" and Music.app_mode() and Music.mix_titles(), "mit Spotify angemeldet: dieser Weg gilt")
	var web: Node = Music.web_sitzung()
	var box := { "n": 0, "r": { "ok": true, "token": tok, "client": ct, "version": "1.2.80" } }
	web.set("quelle", func() -> Dictionary:
		box.n = int(box.n) + 1
		await get_tree().create_timer(0.05).timeout
		return (box.r as Dictionary).duplicate())
	Music._token = ""
	Music.set("_web_aus_bis", 0)
	Music.problem = ""
	check(await Music._ensure_token() and Music._token == tok and str(Music.get("_client_token")) == ct and Music._app_version() == "1.2.80" and int(box.n) == 1,
			"Schlüssel, Client-Token und Fassung von der Seite (kein eigenes Rechnen)")
	check(await Music._ensure_token() and int(box.n) == 1, "gültiger Schlüssel: die Seite wird nicht neu gefragt")
	Music.set("_token_until", int(Time.get_unix_time_from_system()) - 1)
	box.r = { "ok": true, "token": tok + "2", "client": ct, "version": "1.2.80" }
	check(await Music._ensure_token() and Music._token == tok + "2" and int(box.n) == 2, "abgelaufen: neuer Schlüssel von der Seite (die Seite erneuert)")
	check(int(Music.get("_token_until")) - int(Time.get_unix_time_from_system()) <= Web.GILT_S, "Ablauf vorsichtig (höchstens %d Min.)" % (Web.GILT_S / 60))
	Music._token = ""
	var calls: Array = []
	var ok_n := { "n": 0 }
	for i in 5:
		calls.append(func() -> void:
			if await Music._ensure_token():
				ok_n.n = int(ok_n.n) + 1)
	await Music._parallel(calls)
	check(int(box.n) == 3 and int(ok_n.n) == 5, "fünf Abrufe gleichzeitig: die Seite nur einmal gefragt (%d), alle haben den Schlüssel" % int(box.n))

	print("Mit Spotify angemeldet: Rückfall in den Grundmodus")
	box.r = { "ok": false, "why": "zeit" }
	Music._token = ""
	var t0 := Time.get_ticks_msec()
	check(not await Music._ensure_token() and Music.grundmodus() and Music.problem == "app", "kein Schlüssel von der Seite: Grundmodus")
	check(int(Music.get("_web_aus_bis")) > int(Time.get_unix_time_from_system()) and Config.get_value("accounts.spotify_web", false) == true,
			"Anmeldung bleibt, nächster Versuch später")
	var n_vor := int(box.n)
	check(not await Music._ensure_token() and int(box.n) == n_vor and Time.get_ticks_msec() - t0 < 3000, "bis dahin kein neuer Kern-Start, nichts wartet")
	var pt := Music.problem_text("app")
	check(pt != "" and not pt.contains("inoffiziell") and not pt.contains("gesperrt") and not pt.contains("blockiert") and pt.contains("Läuft gerade"),
			"kurze, sachliche Meldung: " + pt)
	Music.set("_web_aus_bis", 0)
	Music.set("_app_off_until", 0)
	Music.problem = ""
	box.r = { "ok": false, "why": "abgemeldet" }
	Music._token = ""
	check(not await Music._ensure_token() and not Music.app_ready() and Music.problem == "abgelaufen", "Seite abgemeldet: neu anmelden (Hinweis), nichts hängt")
	Music.problem = ""
	Music.app_note = ""
	Music.set("_app_off_until", 0)

	print("Mit Spotify angemeldet: Abmelden löscht alles")
	Config.set_value("accounts.spotify_web", true)
	box.r = { "ok": true, "token": tok, "client": ct, "version": "1.2.80" }
	Music._token = ""
	await Music._ensure_token()
	await _web_bruecke(web, tok, ct)
	Music.disconnect_spotify("app")
	check(not Music.app_ready() and Music._token == "" and str(Music.get("_client_token")) == "" and str(Music.get("_web_geprueft")) == ""
			and Music.login_mode() == "", "Abmelden: Anmeldung, Schlüssel und Client-Token weg")
	Config.save_settings()
	var disk := FileAccess.get_file_as_string(Config.path("settings.json"))
	var logs := ""
	for lp in ["logs/spotify.log", "logs/browser_kern.log"]:
		if FileAccess.file_exists(Config.path(lp)):
			logs += FileAccess.get_file_as_string(Config.path(lp))
	check(not disk.contains(tok) and not disk.contains(ct) and not disk.contains("aB3-_x9"), "kein Schlüssel in settings.json")
	check(logs.contains("Spotify-Sitzung") and not logs.contains(tok) and not logs.contains(ct) and not logs.contains("aB3-_x9"), "kein Geheimnis im Protokoll")
	web.set("quelle", Callable())
	Music.set("_partner", keep_partner)
	Music.set("_api_base", keep_api)
	Music.problem = ""
	Music.set("_app_off_until", 0)
	for k in keep:
		Config.set_value("accounts." + k, keep[k])


## Mit Spotify angemeldet: alle Abrufe der Sitzung laufen über die Seite (Web.abfrage, hier nachgebaut mit
## abfrage_quelle); die eigene Client-ID und was die Regeln nicht zulassen, gehen direkt. Kontoprüfung ohne klares
## Ergebnis hält die Anmeldung nicht auf, ein klares „kein Konto“ schon. Diagnose ohne Werte im Protokoll.
func _web_bruecke(web: Node, tok: String, ct: String) -> void:
	print("Mit Spotify angemeldet: Abrufe über die Seite")
	var log_p := Config.path("logs/spotify.log")
	var gesehen: Array = []
	var antworten := { "pathfinder": { "code": 200, "text": "{\"data\":{\"me\":{\"libraryV3\":{\"totalCount\":0,\"items\":[]}}}}" },
		"konto": { "code": 200, "text": "{\"data\":{\"me\":{\"profile\":{\"username\":\"lena\",\"name\":\"Lena\"}}}}" } }
	web.set("abfrage_quelle", func(ziel: String, methode: String, pfad: String, inhalt: String) -> Dictionary:
		var konto := inhalt.contains("\"profileAttributes\"")
		if not konto:
			gesehen.append({ "ziel": ziel, "methode": methode, "pfad": pfad, "inhalt": inhalt })
		await get_tree().process_frame
		return antworten.get("konto" if konto else ziel, { "code": 404, "text": "{\"error\":{\"status\":404,\"message\":\"nicht da\"}}" }))
	check(bool(web.call("bruecke")), "Brücke an (Seite fragt)")
	Music.set("_web_aus_bis", 0)
	Music.problem = ""
	Music._pf_off = ""
	Music.set("_pf_seen", {})
	Music._token = ""
	check(await Music._ensure_token() and Music._tok_mode == "app", "Schlüssel von der Seite")
	var pf: Dictionary = await Music._pf("libraryV3", Music._lib_vars("Playlists", 50, 0))
	check(bool(pf.ok) and pf.data is Dictionary and gesehen.size() == 1 and str(gesehen[0].ziel) == "pathfinder" and str(gesehen[0].methode) == "POST"
			and str(gesehen[0].pfad) == "/pathfinder/v2/query" and str(gesehen[0].inhalt).contains("\"operationName\":\"libraryV3\""),
			"pathfinder über die Seite (POST, fester Pfad, nur Inhalt von Uzai)")
	var rs: Dictionary = await Music._spc(HTTPClient.METHOD_GET, "/recently-played/v3/user/lena/recently-played?format=json&limit=50")
	check(not bool(rs.ok) and int(rs.code) == 404 and str(gesehen[-1].ziel) == "spclient" and str(gesehen[-1].pfad).begins_with("/recently-played/v3/"),
			"spclient über die Seite (Pfad ohne Host)")
	var ra: Dictionary = await Music._api(HTTPClient.METHOD_GET, "/me/playlists?limit=50")
	check(str(gesehen[-1].ziel) == "webapi" and str(gesehen[-1].pfad) == "/v1/me/playlists?limit=50" and int(ra.code) == 404, "Web-API über die Seite (/v1/…)")
	var n0 := gesehen.size()
	var rp: Dictionary = await Music._api(HTTPClient.METHOD_PUT, "/me/player/volume?volume_percent=40")
	check(gesehen.size() == n0 and int(rp.get("code", 0)) == 0, "PUT der Web-API: nicht über die Seite (Regeln), direkt wie bisher")
	antworten["webapi"] = { "code": 429, "text": "", "warte": 7 }
	var r429: Dictionary = await Music._netz(HTTPClient.METHOD_GET, Music.get("_api_base") + "/me", null, PackedStringArray(), true)
	check(int(r429.code) == 429 and Net.header(r429, "Retry-After") == "7" and not bool(r429.ok), "429 mit Retry-After aus der Seite")
	antworten["webapi"] = { "code": 200, "text": "{\"id\":\"lena\"", "gekuerzt": true }
	var rk: Dictionary = await Music._netz(HTTPClient.METHOD_GET, Music.get("_api_base") + "/me", null, PackedStringArray(), true)
	check(not bool(rk.ok) and rk.data == null, "gekürzte Antwort: nicht lesbar, kein halbes JSON")
	var rx: Dictionary = await Music._netz(HTTPClient.METHOD_GET, Music.get("_api_base") + "/me", null, PackedStringArray(), false)
	check(gesehen.size() == n0 + 2 and int(rx.code) == 0, "eigene Client-ID: direkt, nie über die Seite")
	print("Mit Spotify angemeldet: Kontoprüfung über die Seite")
	var ereig := { "t": "spotify", "token": tok, "client": ct, "version": "1.2.80" }
	antworten["konto"] = { "code": 403, "text": "{\"errors\":[{\"message\":\"Client/request not allowed %s\"}]}" % tok }
	antworten["webapi"] = { "code": 403, "text": "" }
	Config.set_value("accounts.spotify_web", false)
	check(not await Music.web_angemeldet(ereig, false) and not Music.app_ready(), "Kontoprüfung abgelehnt, Seite noch auf der Anmeldung: nicht angemeldet")
	check(await Music.web_angemeldet(ereig, true) and Music.app_ready(), "Kontoprüfung ohne klares Ergebnis, Seite angemeldet: Anmeldung gilt trotzdem")
	antworten["konto"] = { "code": 401, "text": "" }
	Config.set_value("accounts.spotify_web", false)
	check(not await Music.web_angemeldet(ereig, true) and not Music.app_ready(), "klares „kein Konto“ (401): keine Anmeldung")
	antworten["konto"] = { "code": 200, "text": "{\"errors\":[{\"message\":\"PersistedQueryNotFound\"}]}" }
	check(await Music.web_angemeldet(ereig, true) and Music.app_ready(), "veralteter Hash: blockiert die Anmeldung nicht")
	var logs := FileAccess.get_file_as_string(log_p) if FileAccess.file_exists(log_p) else ""
	check(logs.contains("Kopfzeilen der Seite – Schlüssel ja, client-token ja, Fassung ja") and logs.contains("Seite → pathfinder profileAttributes: HTTP 403 – ")
			and logs.contains("Hash veraltet") and logs.contains("Seite → webapi /v1/me: HTTP 429"), "Diagnose: Kopfzeilen, HTTP-Code je Art, Fehlertext, Hash")
	check(not logs.contains(tok) and not logs.contains(ct) and not logs.contains("aB3-_x9aB3-_x9"), "Diagnose ohne Schlüssel und Kennungen")
	web.set("abfrage_quelle", Callable())
	Config.set_value("accounts.spotify_web", true)
	Music.problem = ""
	Music._pf_off = ""
	Music.set("_app_off_until", 0)


## Übersetzer für die internen Wege (pathfinder, Spotify Connect) – ohne Netz.
func _intern() -> void:
	print("Interne Wege: Übersetzer")
	var I := preload("res://src/core/spotify_intern.gd")
	var t: Dictionary = I.track({ "uri": "spotify:track:abc", "name": "Lied", "duration": { "totalMilliseconds": 200000 },
		"contentRating": { "label": "EXPLICIT" }, "artists": { "items": [{ "uri": "spotify:artist:k1", "profile": { "name": "K" } }] },
		"albumOfTrack": { "name": "LP", "coverArt": { "sources": [{ "url": "s", "width": 64 }, { "url": "b", "width": 640 }, { "url": "m", "width": 300 }] } } })
	var ut: Dictionary = Music.track_from(t)
	check(str(ut.id) == "abc" and str(ut.title) == "Lied" and int(ut.duration) == 200000 and bool(ut.explicit) and str(ut.artist_id) == "k1",
			"Titel von pathfinder in Uzais Form")
	check(str(ut.art) == "m" and str(ut.art_big) == "b", "Albumbild: mittel und groß aus den Quellen (nach Breite sortiert)")
	check(I.track({ "name": "ohne" }, "spotify:track:x").get("id") == "x" and I.track({ "uri": "spotify:episode:e" }).is_empty(),
			"Adresse neben den Daten (_uri); Folgen sind keine Titel")
	var al: Dictionary = I.album({ "uri": "spotify:album:a", "name": "A", "type": "EP", "date": { "isoString": "2024-03-01T00:00:00Z", "precision": "DAY" } })
	check(str(al.album_type) == "single" and str(al.release_date) == "2024-03-01" and str(al.release_date_precision) == "day",
			"EP zählt als Single, Datum aus isoString")
	check(str(I.album({ "uri": "spotify:album:b", "date": { "year": 1999 } }).release_date) == "1999", "nur Jahr")
	var pl: Dictionary = Music.playlist_from(
			I.playlist({ "uri": "spotify:playlist:p", "name": "Mix", "ownerV2": { "data": { "uri": "spotify:user:spotify", "name": "Spotify" } },
			"content": { "totalCount": 50 } }))
	check(str(pl.owner_id) == "spotify" and int(pl.count) == 50, "Playlist: Besitzer aus ownerV2, Anzahl aus content")
	check(I.playlist({ "uri": "spotify:user:ich:folder:x", "name": "Ordner" }).is_empty(), "Ordner der Bibliothek sind keine Playlists")
	check(I.lookup({ "data": { "lookup": [{ "data": { "saved": true } }, { "saved": false }] } }, 2) == [true, false]
			and I.lookup({ "data": { "lookup": [] } }, 1).is_empty(), "areEntitiesInLibrary: der Reihe nach, zu kurze Antwort zählt nicht")
	check(
			I.recent_uris({ "playContexts": [{ "lastPlayedTrackUri": "spotify:track:a" }, { "lastPlayedTrackUri": "spotify:track:a" },
			{ "lastPlayedTrackUri": "spotify:episode:e" }, { "lastPlayedTrackUri": "spotify:track:b" }] }) == ["spotify:track:a", "spotify:track:b"],
			"zuletzt gehört: jeder Titel einmal, keine Folgen")
	var c := { "active_device_id": "pc", "devices": {
		"pc": { "device_id": "pc", "name": "PC", "device_type": "COMPUTER", "volume": 32768 },
		"hobs_uzai": { "device_id": "hobs_uzai", "name": "Uzai", "device_type": "COMPUTER", "capabilities": { "hidden": true } },
		"tel": { "device_id": "tel", "name": "Handy", "device_type": "SMARTPHONE" } },
		"player_state": { "is_playing": true, "is_paused": false, "timestamp": "1000000", "position_as_of_timestamp": "5000", "duration": "200000",
			"options": { "shuffling_context": true, "repeating_track": true }, "context_uri": "spotify:playlist:p",
			"track": { "uri": "spotify:track:t", "metadata": { "title": "Jetzt", "artist_name": "K", "image_url": "spotify:image:ff" } },
			"next_tracks": [{ "uri": "spotify:track:n", "metadata": { "title": "Danach" } }, { "uri": "spotify:delimiter" }] } }
	var info: Dictionary = I.cluster(c, "hobs_uzai", 1002000)
	check((info.devices as Array).size() == 2 and str(info.active) == "pc", "Geräte ohne Uzais verstecktes Gerät")
	check(int(info.progress) == 7000 and bool(info.playing) and bool(info.shuffle) and str(info.repeat) == "track",
			"Stelle rechnet weiter, Zufall und Wiederholen")
	check(str(info.track.art) == "https://i.scdn.co/image/ff" and int(info.devices[0].volume) == 50, "Bild-Adresse und Lautstärke in Prozent")
	check((info.queue as Array).size() == 1 and str(info.queue[0].title) == "Danach", "Als Nächstes ohne Trenner")
	var leer := c.duplicate(true)
	leer.player_state.track.metadata["image_xlarge_url"] = ""
	leer.player_state.track.metadata["image_large_url"] = ""
	check(str(I.cluster(leer, "hobs_uzai", 1002000).track.art) == "https://i.scdn.co/image/ff",
			"leere große Bildfelder: das kleinere Cover statt gar keinem (Guide zeigte nur den Namen)")
	check(I.erstes({ "a": "", "b": null, "c": "x" }, ["a", "b", "c"]) == "x" and I.erstes({}, ["a"]) == "", "erstes: leer und null zählen nicht")
	var paused: Dictionary = I.cluster({ "player_state": { "is_playing": true, "is_paused": true, "timestamp": "0", "position_as_of_timestamp": "5000" } }, "",
			999999)
	check(not bool(paused.playing) and int(paused.progress) == 5000, "pausiert: Stelle bleibt stehen")
	check(I.pick_target(info, "") == "pc", "Ziel: das aktive Gerät")
	var idle := { "active": "",
			"devices": [{ "id": "tel", "name": "Handy", "type": "Smartphone" }, { "id": "a", "name": "Andere", "type": "Computer" },
			{ "id": "b", "name": "WOHNZIMMER", "type": "Computer" }] }
	check(I.pick_target(idle, "wohnzimmer") == "b" and I.pick_target(idle, "") == "a" and I.pick_target({ "devices": [] }, "") == "",
			"ohne aktives: dieser PC, sonst ein PC")
	# „Auf diesem PC“ (the default): never switch to another device on its own.
	var tv := { "active": "tel",
			"devices": [{ "id": "tel", "name": "SHIELD", "type": "TV", "active": true }, { "id": "b", "name": "WOHNZIMMER", "type": "Computer" }] }
	check(I.pick_target(tv, "wohnzimmer", "pc") == "b", "auf diesem PC: der PC, auch wenn gerade der Fernseher spielt")
	check(I.pick_target(tv, "wohnzimmer", "aktiv") == "tel", "wie früher wählbar: das Gerät, das gerade läuft")
	var ohne_pc := { "active": "", "devices": [{ "id": "tel", "name": "SHIELD", "type": "TV" }, { "id": "a", "name": "Laptop", "type": "Computer" }] }
	check(I.pick_target(ohne_pc, "wohnzimmer", "pc") == "", "auf diesem PC, Spotify hier nicht offen: kein Ziel – Uzai startet es, statt auszuweichen")
	check(I.pick_target(tv, "wohnzimmer", "pc", "tel") == "tel", "ein hier gewähltes Gerät gilt, solange es spielt")
	check(I.pick_target(idle, "wohnzimmer", "pc", "tel") == "b", "spielt es nicht mehr: wieder dieser PC")
	check(I.dieser_pc(idle.devices, "wohnzimmer") == "b" and I.dieser_pc(idle.devices, "") == "a" and I.dieser_pc(idle.devices, "anders") == ""
			and I.dieser_pc(["kaputt", { "type": "Computer", "name": null }, { "id": [], "type": 7 }], "") == "", "dieser PC nach Namen; fremde Daten stören nicht")
	check(I.fremd_aktiv(tv, "wohnzimmer") and not I.fremd_aktiv(tv, "wohnzimmer", "tel") and not I.fremd_aktiv(idle, "wohnzimmer")
			and not I.fremd_aktiv({ "active": "b", "devices": tv.devices }, "wohnzimmer"), "fremd ist, was weder dieser PC noch hier gewählt ist")
	check(Music.dealer_nochmal(0, true, "app") and not Music.dealer_nochmal(1, true, "app") and not Music.dealer_nochmal(0, false, "app")
			and not Music.dealer_nochmal(0, true, "eigen"), "Dealer lehnt einen älteren Schlüssel ab: einmal sofort mit einem frischen")
	var ms := FileAccess.get_file_as_string("res://src/core/music_spotify.gd")
	var st := ms.substr(ms.find("func _store_token("), 700)
	check(st.contains("_dealer_retry_at = 0") and ms.substr(ms.find("func _schluessel_frisch("), 400).contains("schluessel_verwerfen(_token)"),
			"ein neuer Schlüssel hebt die Wartezeit des Dealers auf; ein abgelehnter wird nicht noch einmal geholt")
	check(str(Config.DEFAULTS.system.spotify_ort) == "pc" and Music.spotify_ort() in ["pc", "aktiv"], "voreingestellt: auf diesem PC")
	var M := HTTPClient.METHOD_PUT
	var play: Array = I.commands_for(M, "/me/player/play", { "context_uri": "spotify:playlist:p", "offset": { "uri": "spotify:track:t" } })
	check(play.size() == 1 and str(play[0].endpoint) == "play" and str(play[0].context.url) == "context://spotify:playlist:p"
			and str(play[0].options.skip_to.track_uri) == "spotify:track:t", "Abspielen ab Titel: Kontext mit skip_to")
	var einzel: Dictionary = I.commands_for(M, "/me/player/play", { "context_uri": "spotify:track:t" })[0]
	check(str(einzel.context.uri) == "spotify:track:t" and not (einzel.options as Dictionary).has("skip_to"),
			"einzelner Titel: Der Titel ist der Kontext, nichts zu überspringen")
	var lst: Array = I.commands_for(M, "/me/player/play", { "uris": ["spotify:track:a", "spotify:track:b"] })
	check((lst[0].context.pages[0].tracks as Array).size() == 2 and not (lst[0].context as Dictionary).has("uri"), "lose Liste als eigene Seiten")
	# Play commands use the full form: Spotify accepted the short form, but the app on the PC loaded nothing.
	for befehl in [play[0], einzel, lst[0]]:
		var d: Dictionary = befehl
		check((d.context as Dictionary).get("metadata") is Dictionary and d.options.get("initially_paused") == false and d.options.get("seek_to") == 0
				and d.logging_params.get("page_instance_ids") is Array and d.logging_params.get("interaction_ids") is Array
				and (d.logging_params as Dictionary).has("command_id") and str(d.play_origin.get("referrer_identifier", "")) != "",
				"Abspielbefehl in der vollständigen Form (%s)" % I.play_art({ "context_uri": str(d.context.get("uri", "")) } if d.context.has("uri") else { "uris": [1] }))
	check(str(I.commands_for(M, "/me/player/play", null)[0].endpoint) == "resume" and str(I.commands_for(M, "/me/player/pause", null)[0].endpoint) == "pause",
			"Weiter/Pause")
	check(int(I.commands_for(M, "/me/player/seek?position_ms=1234", null)[0].value) == 1234
			and I.commands_for(M, "/me/player/shuffle?state=true", null)[0].value == true, "Spulen und Zufall")
	var rep: Array = I.commands_for(M, "/me/player/repeat?state=context", null)
	check(rep.size() == 2 and rep[0].value == true and rep[1].value == false, "Wiederholen: Playlist an, Titel aus")
	var qu: Array = I.commands_for(HTTPClient.METHOD_POST, "/me/player/queue?uri=spotify%3Atrack%3Aq", null)
	check(str(qu[0].track.uri) == "spotify:track:q" and str(qu[0].track.provider) == "queue", "Warteschlange: add_to_queue")
	check(I.commands_for(HTTPClient.METHOD_GET, "/me/playlists", null).is_empty(), "Lesen ist kein Steuerbefehl")
	_abspielen_nachsehen()


## Nach dem Abspielbefehl zählt, was das Gerät meldet – nicht, dass Spotify den Befehl angenommen hat.
func _abspielen_nachsehen() -> void:
	var I := preload("res://src/core/spotify_intern.gd")
	var pl := { "context_uri": "spotify:playlist:p", "offset": { "uri": "spotify:track:t" } }
	var ganz := { "context_uri": "spotify:album:a" }
	var lose := { "uris": ["spotify:track:a", "spotify:track:b"] }
	var einer := { "context_uri": "spotify:track:t" }
	check(I.play_wunsch(pl) == { "titel": "spotify:track:t", "kontext": "spotify:playlist:p", "lose": false }
			and I.play_wunsch(ganz) == { "titel": "", "kontext": "spotify:album:a", "lose": false }
			and I.play_wunsch(lose) == { "titel": "spotify:track:a", "kontext": "", "lose": true }
			and I.play_wunsch(einer) == { "titel": "spotify:track:t", "kontext": "", "lose": false }
			and I.play_wunsch(null).is_empty() and I.play_wunsch({ "uris": [] }).is_empty() and I.play_wunsch("kaputt").is_empty(),
			"Wunsch aus dem Befehl: Titel, Kontext, lose Liste; Fortsetzen hat keinen")
	check(I.play_einzeln(pl) == { "context_uri": "spotify:track:t" } and I.play_einzeln(lose) == { "context_uri": "spotify:track:a" }
			and I.play_einzeln(ganz).is_empty() and I.play_einzeln(einer).is_empty() and I.play_einzeln({ "uris": ["spotify:episode:e"] }).is_empty(),
			"als einzelner Titel: nur mit bestimmtem Titel, und nicht, wenn es schon einer ist")
	check(I.play_wege("a", lose) == ["a", "b", "c", "d"] and I.play_wege("d", lose) == ["d", "a", "b", "c"]
			and I.play_wege("b", pl) == ["b", "a", "c", "d"] and I.play_wege("c", ganz) == ["a", "b"] and I.play_wege("unsinn", einer) == ["a", "b"],
			"Wege: der gemerkte zuerst; Titel allein und Titel im Album nur, wo es einen bestimmten Titel gibt")
	check(I.play_album(lose, "spotify:album:x") == { "context_uri": "spotify:album:x", "offset": { "uri": "spotify:track:a" } }
			and I.play_album(pl, "spotify:album:x") == { "context_uri": "spotify:album:x", "offset": { "uri": "spotify:track:t" } }
			and I.play_album(lose, "").is_empty() and I.play_album(lose, "spotify:playlist:p").is_empty() and I.play_album(ganz, "spotify:album:x").is_empty()
			and I.play_album(einer, "spotify:album:x").is_empty() and I.play_album(lose, "spotify:album:" + "x".repeat(80)).is_empty(),
			"Titel im Album: nur mit bestimmtem Titel und echter Album-Adresse")
	check(I.liked_context("uzai.77_x-1") == "spotify:user:uzai.77_x-1:collection" and I.liked_context("") == ""
			and I.liked_context("a:b") == "" and I.liked_context("a/b") == "" and I.liked_context("x".repeat(65)) == "",
			"Lieblingssongs als Kontext: nur mit gültiger Kennung")
	var w := I.play_wunsch(pl)
	var geraet := func(aktiv: String, titel: String, spielt: bool, kontext := "") -> Dictionary:
		return { "active": aktiv, "track": { "uri": titel }, "playing": spielt, "context": kontext }
	check(I.play_stand(geraet.call("pc", "spotify:track:t", true), "pc", "spotify:track:alt", w) == "ja", "der gewünschte Titel läuft auf dem Zielgerät: ja")
	check(I.play_stand(geraet.call("pc", "", false), "pc", "", w) == "nein", "Gerät aktiv, aber kein Titel geladen (so stand es am PC): nein")
	check(I.play_stand(geraet.call("tv", "spotify:track:t", true), "pc", "", w) == "nein", "läuft auf einem anderen Gerät: nein")
	check(I.play_stand(geraet.call("pc", "spotify:track:t", false), "pc", "", w) == "pausiert", "geladen, steht aber: pausiert")
	check(I.play_stand(geraet.call("pc", "spotify:track:alt", true), "pc", "spotify:track:alt", w) == "nein", "es läuft noch der alte Titel: nein")
	check(I.play_stand(geraet.call("pc", "spotify:track:tausch", true), "pc", "spotify:track:alt", w) == "ja",
			"ein neuer Titel läuft (Spotify tauscht Fassungen je Land): ja")
	check(I.play_stand(geraet.call("pc", "spotify:track:gestern", false), "pc", "", w) == "nein", "ein anderer Titel steht nur da: kein Beleg")
	var wg := I.play_wunsch(ganz)
	check(I.play_stand(geraet.call("pc", "spotify:track:x", true, "spotify:album:a"), "pc", "spotify:track:x", wg) == "ja"
			and I.play_stand(geraet.call("pc", "spotify:track:x", false, "spotify:album:a"), "pc", "", wg) == "pausiert"
			and I.play_stand(geraet.call("pc", "spotify:track:x", true, "spotify:album:b"), "pc", "spotify:track:x", wg) == "nein",
			"ganze Liste: der Kontext zählt")
	check(I.play_stand({ "active": 7, "track": "kaputt", "playing": "ja" }, "pc", "", w) == "nein" and I.play_stand({}, "", "", {}) == "nein",
			"fremde Daten stören nicht")
	check(I.play_art(lose) == "Titelliste (2)" and I.play_art(pl) == "playlist ab Titel" and I.play_art(ganz) == "album" and I.play_art(einer) == "Titel"
			and I.play_art({ "context_uri": "spotify:user:x:collection" }) == "Liste" and I.play_art(null) == "", "fürs Protokoll: Art ohne Kennungen")
	check(I.play_bild(geraet.call("pc", "", false), "pc") == "Gerät aktiv: ja, Titel geladen: nein, läuft: nein", "fürs Protokoll: was das Gerät zeigt")
	var ms := FileAccess.get_file_as_string("res://src/core/music_spotify.gd")
	var cp := ms.substr(ms.find("func _connect_play("), 2600)
	check(cp.contains("_play_warten(") and cp.contains("CODE_STUMM") and cp.contains("Config.set_value(key, weg)"),
			"Abspielen sieht nach, nimmt sonst den nächsten Weg und merkt sich den, der ging")
	check(Music.connect_error(Music.CODE_STUMM).contains("nicht gestartet") and Music.connect_error(Music.CODE_STUMM) != Music.connect_error(0),
			"angenommen, aber nicht gestartet: eigene Meldung")
