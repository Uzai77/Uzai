extends Node
## Liedtexte (src/core/lyrics.gd) ohne Netz: LRC lesen (Zeitmarken, Grenzen, Steuerzeichen),
## Antworten von LRCLIB streng prüfen, den passenden Treffer wählen, Zwischenspeicher prüfen und
## begrenzen, Schalter „Liedtexte (LRCLIB)“; dazu Kleinigkeiten der Großansicht (jetzt_laeuft.gd).
## Aufruf: godot --headless --path . res://tests/logic_lyrics.tscn

const Lyrics := preload("res://src/core/lyrics.gd")
const Jetzt := preload("res://src/ui/layers/jetzt_laeuft.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_lrc()
	_antworten()
	_treffer()
	_speicher()
	await _platte()
	await _schalter()
	_ansicht()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _lrc() -> void:
	print("LRC lesen")
	var r := Lyrics.parse("[00:12.50] Erste Zeile\n[01:02.00] Zweite\nKaputt", "")
	check(str(r.state) == "ok" and (r.synced as Array).size() == 2 and int(r.synced[0][0]) == 12500 and int(r.synced[1][0]) == 62000,
			"Zeilen mit Zeit gelesen, ohne Zeit verworfen")
	r = Lyrics.parse("[00:01.5] a\n[00:02.123] b\n[00:03] c\n[00:04:20] d\r\n[00:05.05] e", "")
	var ms: Array = (r.synced as Array).map(func(l: Array) -> int: return int(l[0]))
	check(ms == [1500, 2123, 3000, 4200, 5050], "Formate: .x, .xxx, ohne Bruch, :xx, CRLF")
	r = Lyrics.parse("[00:30.00][00:10.00] Kehrreim\n[00:20.00] Mitte", "")
	check((r.synced as Array).map(func(l: Array) -> String: return "%d %s" % [l[0], l[1]]) == ["10000 Kehrreim", "20000 Mitte", "30000 Kehrreim"],
			"mehrere Zeitmarken je Zeile, nach Zeit sortiert")
	r = Lyrics.parse("[00:75.00] falsch\n[ar:Künstler]\n[00:aa.00] x\n[abc] y\n[00:01.00] gut", "")
	check((r.synced as Array).size() == 1 and str(r.synced[0][1]) == "gut", "Sekunden ≥ 60, Kennzeilen und Unsinn fallen weg")
	r = Lyrics.parse("[offset:+500]\n[00:02.00] früher\n[00:00.20] weg", "")
	check((r.synced as Array).size() == 1 and int(r.synced[0][0]) == 1500, "[offset] gilt, negative Zeiten fallen weg")
	r = Lyrics.parse("[00:01.00] <00:01.00>Wort <00:01.50>für <00:02.00>Wort", "")
	check(str(r.synced[0][1]) == "Wort für Wort", "Wort-Zeiten entfernt")
	r = Lyrics.parse("[00:01.00] a\u0007b\u202Ec\u0001d", "")
	check(str(r.synced[0][1]) == "abcd", "Steuerzeichen und Richtungs-Umschalter entfernt")
	r = Lyrics.parse("[00:01.00] " + "x".repeat(5000), "")
	check(str(r.synced[0][1]).length() == Lyrics.LINE_MAX, "zu lange Zeile gekürzt")
	var big := ""
	for i in 3000:
		big += "[%02d:%02d.00] z\n" % [floori(i / 60.0) % 100, i % 60]
	r = Lyrics.parse(big, "")
	check((r.synced as Array).size() == Lyrics.LINES_MAX, "höchstens LINES_MAX Zeilen")
	r = Lyrics.parse("[00:01.00] \n[00:02.00]", "")
	check((r.synced as Array).is_empty() and str(r.state) == "keine", "nur leere Zeilen: kein Liedtext")
	r = Lyrics.parse("", "\n\nEins\n\nZwei\n\n")
	check(Array(r.plain) == ["Eins", "", "Zwei"] and str(r.state) == "ok", "einfacher Text: Leerzeilen an den Rändern weg")
	check(str(Lyrics.parse("", "").state) == "keine", "ohne Text: keine")
	# Halbierende Suche wie die einfache.
	var sy: Array = Lyrics.parse("[00:01.00] a\n[00:03.00] b\n[00:03.00] c\n[00:07.00] d", "").synced
	var same := true
	for t in range(-500, 9000, 250):
		var lin := -1
		for i in sy.size():
			if int(sy[i][0]) <= t:
				lin = i
		same = same and Lyrics.line_at(sy, t) == lin
	check(same and Lyrics.line_at([], 1000) == -1, "laufende Zeile (halbierend gesucht)")


func _antworten() -> void:
	print("Antworten von LRCLIB prüfen")
	var ok := { "id": 3396226, "trackName": "I Want to Live", "artistName": "Borislav Slavov", "albumName": "Baldur's Gate 3", "duration": 233,
		"instrumental": false, "plainLyrics": "I feel", "syncedLyrics": "[00:17.12] I feel" }
	var h := Lyrics.check_hit(ok)
	check(not h.is_empty() and str(h.synced) == "[00:17.12] I feel" and float(h.duration) == 233.0, "gültiger Treffer")
	check(not Lyrics.check_hit({ "id": 1, "plainLyrics": null, "syncedLyrics": null, "instrumental": true }).is_empty(), "null-Texte erlaubt")
	check(Lyrics.check_hit([1]).is_empty() and Lyrics.check_hit("x").is_empty(), "kein Objekt: abgelehnt")
	check(Lyrics.check_hit({ "syncedLyrics": 5 }).is_empty(), "Text als Zahl: abgelehnt")
	check(Lyrics.check_hit({ "trackName": { "a": 1 } }).is_empty(), "Name als Objekt: abgelehnt")
	check(Lyrics.check_hit({ "duration": -3 }).is_empty() and Lyrics.check_hit({ "duration": "233" }).is_empty(), "Länge negativ oder als Text: abgelehnt")
	check(Lyrics.check_hit({ "instrumental": "ja" }).is_empty() and Lyrics.check_hit({ "id": "7" }).is_empty(), "falsche Typen: abgelehnt")
	check(Lyrics.check_hit({ "plainLyrics": "a".repeat(Lyrics.TEXT_MAX + 1) }).is_empty(), "zu langer Text: abgelehnt")
	check(Lyrics.check_hit({ "artistName": "b".repeat(Lyrics.NAME_MAX + 1) }).is_empty(), "zu langer Name: abgelehnt")
	var many: Array = []
	for i in 50:
		many.append(ok if i % 2 == 0 else { "syncedLyrics": [] })
	check(Lyrics.check_hits(many).size() == 10 and Lyrics.check_hits({ "a": 1 }).is_empty(), "Suche: höchstens 20 gelesen, Unsinn verworfen")
	check(Lyrics.clean_field("Titel\nmit\u0001Steuer" + "x".repeat(400)).length() == Lyrics.FIELD_MAX and not Lyrics.clean_field("a\nb").contains("\n"),
			"Anfrage: Felder ohne Steuerzeichen, gekürzt")
	check(Lyrics.url_ok(Lyrics.GET + "track_name=a") and Lyrics.url_ok(Lyrics.SEARCH + "q=a"), "nur die Wege von LRCLIB …")
	check(not Lyrics.url_ok("http://lrclib.net/api/get?x") and not Lyrics.url_ok("https://lrclib.net.evil.example/api/get?")
			and not Lyrics.url_ok("https://lrclib.net/api/publish"), "… nur https, nur lrclib.net, kein Hochladen")
	check(Lyrics.user_agent() == "Uzai v%s (https://github.com/%s)" % [Config.VERSION, Config.REPO], "eigener User-Agent mit Name und Fassung")


func _treffer() -> void:
	print("Passenden Treffer wählen")
	var a := { "synced": "", "plain": "nur Text", "instrumental": false, "duration": 200.0 }
	var b := { "synced": "[00:01.00] x", "plain": "x", "instrumental": false, "duration": 300.0 }
	var c := { "synced": "[00:01.00] y", "plain": "y", "instrumental": false, "duration": 202.0 }
	check(Lyrics.best_hit([a, b, c], 200.0) == c, "Länge passt und Zeitangaben: vor einfachem Text")
	check(Lyrics.best_hit([a, b], 200.0) == a, "Zeitangaben mit falscher Länge: lieber einfacher Text")
	var nur: Dictionary = Lyrics.best_hit([b], 120.0)
	check(str(nur.synced) == "" and str(nur.plain) == "x", "keine Länge passt: Text ohne Zeiten (läuft nicht falsch mit)")
	check(Lyrics.best_hit([b], 0.0) == b, "Länge unbekannt: erster mit Zeitangaben")
	check(Lyrics.best_hit([{ "synced": "", "plain": " ", "instrumental": true, "duration": 0.0 }], 0.0).is_empty(), "nichts Lesbares: keiner")
	var ins := Lyrics.from_hit({ "synced": "", "plain": "", "instrumental": true })
	check(str(ins.state) == "keine" and bool(ins.instrumental), "Instrumental: kein Liedtext, gemerkt")


func _speicher() -> void:
	print("Zwischenspeicher")
	var k1 := "a".sha256_text()
	var k2 := "b".sha256_text()
	var good := { "t": 100, "s": "ok", "y": [[1000, "eins"], [2000, "zwei"]], "p": ["eins"], "i": false }
	var disk := { "v": 1, "e": {
		k1: good,
		k2: { "t": 5, "s": "ok", "y": [[2000, "a"], [1000, "b"]], "p": [], "i": false },         # Zeiten rückwärts
		"kurz": good,                                                                           # Schlüssel kein SHA-256
		"c".sha256_text(): { "t": 5, "s": "boese", "y": [], "p": [], "i": false },
		"d".sha256_text(): { "t": 5, "s": "ok", "y": [[1, 2]], "p": [], "i": false },               # Text als Zahl
		"e".sha256_text(): { "t": 5, "s": "keine", "y": [], "p": [3], "i": false },
	} }
	var ch := Lyrics.check_disk(disk)
	check(ch.size() == 1 and ch.has(k1) and str(ch[k1].y[1][1]) == "zwei", "Datei geprüft wie eine fremde Antwort")
	check(Lyrics.check_disk({ "v": 2, "e": {} }).is_empty() and Lyrics.check_disk([1]).is_empty() and Lyrics.check_disk(null).is_empty(), "falsche Form: leer")
	var many := {}
	for i in 40:
		many[str(i).sha256_text()] = { "t": i, "s": "ok", "y": [[0, "x".repeat(100)]], "p": [], "i": false }
	var t1 := Lyrics.trim(many, 10, 1 << 20)
	check(t1.size() == 10 and t1.has("39".sha256_text()) and not t1.has("29".sha256_text()), "höchstens N, die ältesten gehen")
	var t2 := Lyrics.trim(many, 100, 1500)
	check(t2.size() > 0 and t2.size() < 10 and JSON.stringify(t2).length() <= 1500, "Größe begrenzt")


## Lesen und Schreiben der Datei laufen im Hintergrund; das Säubern nimmt den schnellen Weg, wenn nichts zu tun ist.
func _platte() -> void:
	print("Zwischenspeicher auf der Platte (im Hintergrund)")
	check(Lyrics.clean_text("a\tb\u202Ec\u0007d\u0085e\uFEFF") == "a bcde" and Lyrics.clean_text("Zeile ohne alles – äöü ♪") == "Zeile ohne alles – äöü ♪"
			and Lyrics.clean_text("") == "", "Säubern: Steuer- und Richtungszeichen raus, Tabulator wird Leerzeichen, Sauberes bleibt")
	Lyrics._disk = {}
	Lyrics._disk_loaded = true
	var eins := "eins".sha256_text()
	var zwei := "zwei".sha256_text()
	Lyrics._disk_put(eins, Lyrics.parse("[00:01.00] erste", ""))
	Lyrics._disk_put(zwei, Lyrics.parse("", "nur Text"))
	check(Lyrics._disk.size() == 2 and not Lyrics._disk_get(eins).is_empty(), "gemerkt: sofort im Speicher")
	var bis := Time.get_ticks_msec() + 5000
	while (Lyrics._schreibt or Lyrics._schreib_stand != null) and Time.get_ticks_msec() < bis:
		await get_tree().process_frame
	var datei: Dictionary = Lyrics._disk_lesen(Lyrics._disk_path())
	check(not Lyrics._schreibt and datei.size() == 2 and str(datei[eins].y[0][1]) == "erste" and str(datei[zwei].p[0]) == "nur Text",
			"auf der Platte steht der neueste Stand (zwei Einträge kurz nacheinander, ein Schreiber)")
	Lyrics._disk = {}
	Lyrics._disk_loaded = false
	await Lyrics._disk_laden()
	check(Lyrics._disk_loaded and Lyrics._disk.size() == 2 and not Lyrics._disk_laedt, "beim nächsten Start im Hintergrund gelesen und geprüft")
	var gewicht: Dictionary = Lyrics.trim(Lyrics._disk, 1, 1 << 20)
	check(gewicht.size() == 1 and Lyrics._gewichte.has(eins) and Lyrics._gewichte.has(zwei), "Größe je Eintrag wird einmal gerechnet und gemerkt")
	Lyrics._disk = {}


func _schalter() -> void:
	print("Schalter Liedtexte (LRCLIB)")
	Lyrics._cache.clear()
	Config.set_value("music.lrclib", false)
	var r: Dictionary = await Lyrics.fetch("To Zanarkand", "Nobuo Uematsu", "Final Fantasy X", 186000)
	check(str(r.state) == "aus", "aus: keine Anfrage, Zustand „aus“")
	Config.set_value("music.lrclib", true)
	var key := Lyrics.key_of("Titel", "Künstler")
	Lyrics._cache[key] = Lyrics.parse("[00:01.00] da", "")
	r = await Lyrics.fetch("Titel", "Künstler", "", 0)
	check(str(r.state) == "ok" and str(r.synced[0][1]) == "da", "aus dem Speicher ohne Netz")
	r = await Lyrics.fetch("", "Künstler", "", 0)
	check(str(r.state) == "keine", "ohne Titel: keine Anfrage")
	Lyrics._cache.clear()


func _ansicht() -> void:
	print("Großansicht")
	check(Jetzt._mmss(65000) == "1:05" and Jetzt._mmss(-5) == "0:00", "Zeiten")
	check(Jetzt.vol_fail_text("spotify_fest", "SHIELD") == "SHIELD lässt sich hier nicht leiser stellen"
			and Jetzt.vol_fail_text("kein_ton", "") == "Kein Ton von der Musik-App gefunden", "Lautstärke: Grund am Ort")
	check(Jetzt.tinte().get_luminance() > 0.45 and Jetzt.tinte("faint").get_luminance() > 0.2, "Schrift immer hell auf dem dunklen Grund")
