extends Node
## Schnelles Laden der Medien-Bereiche: Ladezeiten fürs Protokoll, Bilder nur in der Nähe der
## Auswahl (Reihen und Raster), Zwischenstände von Feed und Shorts, Wartezeit der Filme-Startseite
## (oben zuerst, gemerkte Einträge), eigene Netz-Spur für YouTube-Feeds, JSON im Hintergrund,
## vorab aufgelöste Videos beim Start von mpv.
## Aufruf: godot --headless --path . res://tests/logic_laden.tscn

const Ladezeit := preload("res://src/core/ladezeit.gd")
const MedienReihen := preload("res://src/ui/components/medien_reihen.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")
const MoviesScript := preload("res://src/core/movies.gd")
const YouTubeScript := preload("res://src/core/youtube.gd")
const VideoScript := preload("res://src/core/video.gd")
const NetScript := preload("res://src/core/net.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Karte zum Zählen: lädt ihr „Bild“ erst mit wake(), wenn lazy gesetzt ist.
class Karte extends Control:
	var lazy := false
	var woke := false

	func _ready() -> void:
		if not lazy:
			wake()

	func wake() -> void:
		lazy = false
		woke = true


func _ready() -> void:
	print("Ladezeiten fürs Protokoll")
	var lines: Array = []
	Ladezeit.schreiber = func(z: String) -> void: lines.append(z)
	Ladezeit.oeffnen("Videos", "Startseite", 1000)
	check(Ladezeit.melden("Videos", { "inhalt": true, "fertig": false, "quelle": "gemerkt" }, 1040) == "", "erster Inhalt allein: noch keine Zeile")
	var z := Ladezeit.melden("Videos", { "inhalt": true, "fertig": true, "quelle": "frisch" }, 3000)
	check(z == "Laden Videos · Startseite: erster Inhalt nach 40 ms (gemerkt), vollständig nach 2000 ms", "eine Zeile mit beiden Zeiten (%s)" % z)
	check(lines.size() == 1 and lines[0] == z, "Zeile geht ins Protokoll")
	check(Ladezeit.melden("Videos", { "inhalt": true, "fertig": true }, 4000) == "", "danach nichts mehr bis zum nächsten Öffnen")
	Ladezeit.oeffnen("Filme", "Start", 0)
	check(Ladezeit.melden("Filme", { "inhalt": false, "fertig": false }, 500) == "", "Platzhalter: noch nichts")
	var z2 := Ladezeit.melden("Filme", { "inhalt": false, "fertig": false }, Ladezeit.FRIST_MS + 1)
	check(z2.contains("kein Inhalt") and z2.contains("noch nicht vollständig"), "nach der Frist: „noch nicht vollständig“ (%s)" % z2)
	Ladezeit.oeffnen("Streams", "", 0)
	check(Ladezeit.melden("Streams", { "inhalt": false, "fertig": true }, 300).contains("kein Inhalt, vollständig nach 300 ms"), "leere Seite, fertig geladen")
	Ladezeit.schreiber = Callable()

	print("Bilder nur in der Nähe der Auswahl")
	check(MedienReihen.bild_jetzt(0, 0, 0, 0) and MedienReihen.bild_jetzt(2, 8, 0, 0), "oben: drei Reihen, je neun Karten gleich")
	check(not MedienReihen.bild_jetzt(3, 0, 0, 0) and not MedienReihen.bild_jetzt(0, 9, 0, 0), "weiter unten und weiter rechts erst später")
	check(MedienReihen.bild_jetzt(4, 0, 3, 0) and MedienReihen.bild_jetzt(3, 12, 3, 5) and not MedienReihen.bild_jetzt(1, 0, 3, 0),
			"mitgehend: eine Reihe darüber, zwei darunter, acht Karten rechts der gewählten")
	var mr = MedienReihen.new().setup(100.0)
	add_child(mr)
	var karten: Array = []
	for r in 6:
		var row: Dictionary = mr.add_row("Reihe %d" % r, "", "t%d" % r, 200.0)
		var reihe: Array = []
		for k in 20:
			var c := Karte.new()
			c.custom_minimum_size = Vector2(300, 200)
			mr.add_card(row, c, { "id": "%d-%d" % [r, k] })
			reihe.append(c)
		karten.append(reihe)
	var woke := func(r: int, k: int) -> bool: return bool((karten[r][k] as Karte).woke)
	check(woke.call(0, 0) and woke.call(2, 8) and not woke.call(2, 9) and not woke.call(3, 0) and not woke.call(5, 19), "beim Aufbau: nur oben links Bilder")
	var in_reihe := func(r: int) -> int: return (mr.rows[r].shelf as ScrollContainer).row.get_child_count()
	check(in_reihe.call(3) == 20 and in_reihe.call(4) == 0 and in_reihe.call(5) == 0, "oben zuerst: vier Reihen gleich, die übrigen kommen danach")
	check(mr.card_in(5) == karten[5][0] and in_reihe.call(5) == 20, "wer eine Reihe braucht, bekommt sie sofort")
	await get_tree().process_frame
	await get_tree().process_frame
	check(in_reihe.call(4) == 20, "je Bild eine Reihe nachgefüllt")
	mr.snap(3)
	check(woke.call(3, 0) and woke.call(5, 8) and not woke.call(5, 9), "Reihe 3 gewählt: bis Reihe 5 kommen die Bilder")
	(karten[3][10] as Control).focus_mode = Control.FOCUS_ALL
	(karten[3][10] as Control).grab_focus()
	check(woke.call(3, 18) and not woke.call(3, 19), "rechts weiter: acht Karten voraus")
	mr.queue_free()
	var vc = VideoCard.new()
	# Eigenes Bild als Datei, die es nicht gibt: nichts geht ins Netz.
	vc.setup({ "id": "tw:probe", "title": "Test", "thumb": "user://gibt_es_nicht.jpg" }, 352.0)
	vc.lazy = true
	add_child(vc)
	check(vc.get("_wait_url") != "", "Videokarte mit lazy: Bild wartet")
	vc.wake()
	check(vc.get("_wait_url") == "" and not vc.lazy, "wake() lädt es (einmal)")
	vc.queue_free()

	print("Zwischenstände von Feed und Shorts")
	check(YouTubeScript.teil_zeigen(true, 3, YouTubeScript.TEIL_MS), "erster Start: was da ist, gleich zeigen")
	check(not YouTubeScript.teil_zeigen(false, 3, 99999), "mit gemerktem Stand: erst am Ende tauschen")
	check(not YouTubeScript.teil_zeigen(true, 0, 99999) and not YouTubeScript.teil_zeigen(true, 3, 100), "nur mit Neuem und höchstens alle TEIL_MS")
	var e := YouTubeScript.einmal([{ "id": "a" }, { "id": "b" }, { "id": "a", "x": 1 }, "kaputt"])
	check(e.size() == 2 and not (e[0] as Dictionary).has("x"), "jedes Video einmal, das erste gewinnt")

	print("Filme: wie lange die Startseite wartet")
	var job := func(done: bool) -> Dictionary: return { "done": done }
	check(MoviesScript.home_wait_over([], 0, false), "keine Kataloge: nicht warten")
	check(MoviesScript.home_wait_over([job.call(true), job.call(true), job.call(true), job.call(false)], MoviesScript.HOME_TOP_MS, false), "oberste drei da: Seite steht, Rest kommt nach")
	check(not MoviesScript.home_wait_over([job.call(true), job.call(true), job.call(true), job.call(false)], 50, false), "kommt alles gleich: kurz auf den Rest warten")
	check(not MoviesScript.home_wait_over([job.call(true), job.call(false), job.call(true)], 1000, false), "zweite Reihe fehlt noch: warten")
	check(MoviesScript.home_wait_over([job.call(false), job.call(false)], int(MoviesScript.HOME_WAIT_OLD * 1000.0), true), "gemerkte Einträge: nur kurz warten")
	check(not MoviesScript.home_wait_over([job.call(false), job.call(false)], int(MoviesScript.HOME_WAIT * 1000.0) + 1, false), "ohne Antwort und ohne Gemerktes: weiter Platzhalter")
	check(MoviesScript.home_wait_over([job.call(false), job.call(false), job.call(false), job.call(true)], int(MoviesScript.HOME_WAIT * 1000.0) + 1, false),
			"nach HOME_WAIT mit Teilergebnis zeigen")
	check(MoviesScript.CATALOG_TIMEOUT <= 10.0, "ein Katalog hält die Seite höchstens 10 s auf")

	print("Netz: Spuren und JSON im Hintergrund")
	check(NetScript.MAX_PARALLEL.has("yt") and Net._running.has("yt"), "YouTube-Feeds haben eine eigene Spur")
	check(YouTubeScript.RSS_TIMEOUT <= 15.0, "ein Feed wartet nicht länger als andere Anfragen")
	var small := '{"a": [1, 2, 3]}'.to_utf8_buffer()
	check(NetScript.parse_json_now(small) is Dictionary and NetScript.parse_json_now("kein json".to_utf8_buffer()) == null
			and NetScript.parse_json_now(PackedByteArray()) == null, "JSON lesen: kaputt und leer geben null")
	var big_list: Array = []
	for i in 6000:
		big_list.append({ "id": "tt%07d" % i, "name": "Titel %d" % i, "poster": "https://example.org/p/%d.jpg" % i })
	var big := JSON.stringify({ "metas": big_list }).to_utf8_buffer()
	check(big.size() >= NetScript.JSON_OFF_BYTES, "großer Katalog (%d KB) geht in den Hintergrund" % (big.size() / 1024))
	var got: Variant = await Net.parse_json(big)
	check(got is Dictionary and (got.metas as Array).size() == 6000 and str(got.metas[5999].id) == "tt0005999", "Hintergrund liest dasselbe")
	var kl: Variant = await Net.parse_json('["x"]'.to_utf8_buffer())
	check(kl is Array and kl == ["x"], "kleine Antwort gleich gelesen")

	print("Videos: vorab aufgelöst starten")
	var pre := { "v": "https://rr1.googlevideo.com/v", "a": "https://rr1.googlevideo.com/a", "ua": "Mozilla/5.0" }
	var a := VideoScript.pre_args(pre, "https://www.youtube.com/watch?v=abcdefghijk")
	check(a == PackedStringArray(["--audio-files-append=https://rr1.googlevideo.com/a", "--user-agent=Mozilla/5.0", "https://rr1.googlevideo.com/v"]),
			"mpv bekommt Bild, Ton und User-Agent direkt (%s)" % str(a))
	check(VideoScript.pre_args({}, "https://www.youtube.com/watch?v=abcdefghijk") == PackedStringArray(["https://www.youtube.com/watch?v=abcdefghijk"]),
			"ohne Vorab: die Adresse für yt-dlp wie bisher")
	var yt := { "id": "abcdefghijk" }
	check(VideoScript.pre_ok(yt, false, false), "YouTube-Video ohne Untertitel: vorab erlaubt")
	check(not VideoScript.pre_ok(yt, true, false) and not VideoScript.pre_ok(yt, false, true), "mit Untertiteln oder nur Ton: über yt-dlp in mpv")
	check(not VideoScript.pre_ok({ "id": "x", "movies": true }, false, false) and not VideoScript.pre_ok({ "id": "abcdefghijk", "twitch": {} }, false, false)
			and not VideoScript.pre_ok({ "id": "abcdefghijk", "url": "https://x/y.mp4" }, false, false) and not VideoScript.pre_ok({ "id": "abcdefghijk", "live": true }, false, false),
			"Filme, Twitch, direkte Adressen und Live nie")
	check(VideoScript.shorts_order(5, 10) == [6, 7, 4] and VideoScript.shorts_order(0, 2) == [1] and VideoScript.shorts_order(9, 10) == [8],
			"Shorts: zwei voraus, eins zurück")
	check(VideoScript.start_text({ "id": "abcdefghijk" }, true, 640, "vorab aufgelöst", 2100) == "Shorts: Start bis Bild 640 ms (vorab aufgelöst, Auflösen vorher 2100 ms)",
			"Protokollzeile Shorts")
	check(VideoScript.start_text({ "id": "x", "movies": true }, false, 3000, "direkt") == "Film: Start bis Bild 3000 ms (direkt)", "Protokollzeile Film")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
