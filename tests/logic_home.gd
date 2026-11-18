extends Node
## Logik der Startseite, Spielseite und Bibliothek ohne Bildschirm.
## Aufruf: godot --headless --path . res://tests/logic_home.tscn

const CoverArt := preload("res://src/ui/components/cover_art.gd")
const CoverRow := preload("res://src/ui/components/cover_row.gd")
const GamePage := preload("res://src/ui/layers/game_page.gd")
const Games := preload("res://src/ui/sections/games.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Ersatz-Cover: Titel nie mitten im Wort trennen")
	var font := UzTheme.display("black")
	# 144 px: Platz für den Titel auf einem 200 px breiten Cover („Mehr für …“ auf der Spielseite).
	var fs := CoverArt.fit_size("Cyberpunk 2077", font, 32, 20, 144.0)
	check(fs > 0 and fs < 32, "langes Wort: Schrift kleiner statt getrennt (%d)" % fs)
	check(font.get_string_size("Cyberpunk", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= 144.0, "„Cyberpunk“ passt in die Zeile")
	check(CoverArt.fit_size("Ico", font, 32, 20, 160.0) == 32, "kurzer Titel bleibt groß")
	check(CoverArt.fit_size("Donaudampfschifffahrtsgesellschaft", font, 32, 20, 160.0) < 0, "zu langes Wort: Trennen erlaubt (negativ)")
	check(CoverArt.fit_size("Abc", font, 12, 20, 160.0) == 12, "Untergrenze über dem Start: kein Hängenbleiben")

	print("Installation über Steam (appmanifest)")
	var s1 := GamePage.install_state({ "StateFlags": "4", "BytesToDownload": "100", "BytesDownloaded": "100" })
	check(bool(s1.done) and float(s1.frac) == 1.0, "StateFlags 4: fertig")
	var s2 := GamePage.install_state({ "StateFlags": "1026", "BytesToDownload": "9663676416", "BytesDownloaded": "3758096384" })
	check(not bool(s2.done) and absf(float(s2.frac) - 0.3889) < 0.01, "lädt: Anteil stimmt (%.3f)" % float(s2.frac))
	check(str(s2.text).contains("38 %") and str(s2.text).contains("9,0 GB") and str(s2.text).contains("3,5 GB"), "lädt: Text mit Prozent und GB (%s)" % s2.text)
	var s3 := GamePage.install_state({ "StateFlags": "1538", "BytesToDownload": "1000", "BytesDownloaded": "10" })
	check(str(s3.text).begins_with("Pausiert"), "Bit 512: pausiert")
	var s4 := GamePage.install_state({ "StateFlags": "1026" })
	check(float(s4.frac) < 0.0 and not bool(s4.done), "noch keine Größe: ohne Balken")
	var s5 := GamePage.install_state({ "stateflags": "6", "BytesToDownload": "50", "BytesDownloaded": "0" })
	check(not bool(s5.done), "4 + 2 (Aktualisierung nötig) zählt nicht als fertig; Schlüssel ohne Groß/klein")
	check(GamePage._gb(52428800.0) == "50 MB", "unter 1 GB in MB")

	print("Regal der Startseite")
	var row = CoverRow.new()
	row.setup("t", 34, true, 82, 96, 46)
	add_child(row)
	row.size = Vector2(1920, 420)
	var cards: Array = []
	for i in 12:
		var c := Control.new()
		c.custom_minimum_size = Vector2(216, 288)
		c.size = Vector2(216, 288)
		c.focus_mode = Control.FOCUS_ALL
		row.add(c)
		cards.append(c)
	row.show_item(cards[3])
	check(is_equal_approx(row._target(), 3 * (216 + 34)), "gewähltes Cover steht links an der Kante")
	row.show_item(cards[11])
	var total := 12 * (216 + 34) - 34 + 216 * 0.14
	check(is_equal_approx(row._target(), total - (1920 - 192)), "am Ende kein leeres Band (hält an)")
	row.show_item(cards[0])
	check(row._target() == 0.0, "erstes Cover: keine Verschiebung")
	var few = CoverRow.new()
	few.setup("t2", 34, true, 82, 96, 46)
	add_child(few)
	few.size = Vector2(1920, 420)
	var two: Array = []
	for i in 2:
		var c2 := Control.new()
		c2.custom_minimum_size = Vector2(216, 288)
		c2.size = Vector2(216, 288)
		few.add(c2)
		two.append(c2)
	few.show_item(two[1])
	check(few._target() == 0.0, "wenige Cover: Reihe bleibt stehen")
	check(row.items().size() == 12 and row.custom_minimum_size.y == 82 + 288 + 46, "Höhe: Luft oben, Cover, Spiegelung")

	print("Bibliotheks-Raster: Steuerkreuz nach Lage im Gitter")
	var LG := load("res://src/ui/layers/library_grid.gd")
	# 10 Karten, 7 Spalten: Reihe 0 = 0…6, Reihe 1 = 7…9
	check(LG.grid_target(0, 10, 7, "right") == 1 and LG.grid_target(6, 10, 7, "right") == -1, "rechts bis zum Rand, dann nicht weiter")
	check(LG.grid_target(7, 10, 7, "left") == -1 and LG.grid_target(8, 10, 7, "left") == 7, "links nur innerhalb der Reihe")
	check(LG.grid_target(2, 10, 7, "down") == 9 and LG.grid_target(1, 10, 7, "down") == 8, "runter in die kürzere Reihe")
	check(LG.grid_target(5, 10, 7, "down") == 9, "runter, wo die Reihe schon zu Ende ist: letzte Karte")
	check(LG.grid_target(8, 10, 7, "down") == -1 and LG.grid_target(3, 10, 7, "up") == -1, "unten und oben am Rand: Nav sucht selbst (Kopfzeile)")
	check(LG.grid_target(9, 10, 7, "right") == -1 and LG.grid_target(9, 10, 7, "up") == 2, "letzte Karte")

	print("Quellen der Startseite")
	var gs = Games.new()
	gs.sub = "ps2"
	check(gs._source_name() == str(Config.system("ps2").get("name", "PS2")), "„Alle anzeigen“ nennt das System ausgeschrieben")
	gs.sub = "steam"
	check(gs._source_name() == "Steam", "Steam")
	gs.free()

	_for_you()
	_fuer_dich_leiste()

	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## „Für dich“: Auswahl und Mischen (reine Funktionen in for_you.gd).
func _for_you() -> void:
	const FY := preload("res://src/ui/components/for_you.gd")
	print("Für dich: Auswahl")
	var mk := func(key: String, kind: String, w: float, big := true, gid := "", live := false) -> Dictionary:
		return { "key": key, "kind": kind, "weight": w, "big": big, "game_id": gid, "live": live, "title": key }
	var cands: Array = [mk.call("weiter", "weiter", 5.0, true, "g1"), mk.call("wieder:g2", "wieder", 3.0, true, "g2"),
		mk.call("wieder:g3", "wieder", 1.0, true, "g3"), mk.call("woche", "woche", 2.0), mk.call("voice", "voice", 5.0, false),
		mk.call("news:g1", "news", 3.0, true, "g1"), mk.call("erfolg:g4", "erfolg", 4.0, true, "g4"), mk.call("leer", "neu", 0.0)]
	var empty := FY.pick([], 1)
	check((empty.big as Dictionary).is_empty() and (empty.small as Array).is_empty(), "keine Kandidaten: keine Karten")
	var p1 := FY.pick(cands, 42)
	check(FY.keys_of(p1) == FY.keys_of(FY.pick(cands, 42)), "gleicher Startwert: gleiche Auswahl")
	var ok_rules := true
	var ok_big := true
	var ok_count := true
	var differs := false
	for sd in 300:
		var p := FY.pick(cands, sd)
		var all: Array = [p.big] + p.small
		var kinds := {}
		var games := {}
		for c in all:
			if (c as Dictionary).is_empty():
				continue
			if kinds.has(c.kind) or (str(c.game_id) != "" and games.has(c.game_id)) or float(c.weight) <= 0.0:
				ok_rules = false
			kinds[c.kind] = true
			if str(c.game_id) != "":
				games[c.game_id] = true
		ok_big = ok_big and bool((p.big as Dictionary).get("big", false))
		ok_count = ok_count and (p.small as Array).size() == 2
		differs = differs or FY.keys_of(p) != FY.keys_of(p1)
	check(ok_rules, "je Art eine Karte, jedes Spiel einmal, nichts ohne Gewicht")
	check(ok_big and ok_count, "immer eine große Karte, die groß taugt, und zwei kleine")
	check(differs, "andere Startwerte mischen anders")
	# Gewicht: weiter (5) kommt deutlich öfter als woche (2); zwei Spiele einer Art zählen nicht doppelt.
	var n_weiter := 0
	var n_woche := 0
	for sd in 600:
		var ks := FY.keys_of(FY.pick(cands, sd))
		n_weiter += 1 if ks.has("weiter") else 0
		n_woche += 1 if ks.has("woche") else 0
	check(n_weiter > n_woche * 1.4, "Gewicht zählt: Weiterspielen öfter als die Woche (%d zu %d)" % [n_weiter, n_woche])
	var share: Array = [mk.call("a", "a", 3.0), mk.call("b1", "b", 3.0), mk.call("b2", "b", 1.0, true, "x")]
	for i in 6:
		share.append(mk.call("f%d" % i, "f%d" % i, 3.0))
	var n_a := 0
	var n_b := 0
	for sd in 2000:
		var ks3 := FY.keys_of(FY.pick(share, sd))
		n_a += 1 if ks3.has("a") else 0
		n_b += 1 if ks3.has("b1") or ks3.has("b2") else 0
	check(n_b < n_a * 1.12 and n_b > n_a * 0.88, "mehrere Kandidaten einer Art teilen sich ihr Gewicht (%d zu %d)" % [n_b, n_a])
	# Stabil: die bisherige Auswahl bleibt, solange es sie gibt; fällt eine weg, rückt nur ihr Platz nach.
	var keep := ["woche", "voice", "erfolg:g4"]
	check(FY.keys_of(FY.pick(cands, 7, keep)) == keep, "bisherige Auswahl bleibt stehen (anderer Startwert egal)")
	var without := cands.filter(func(c: Dictionary) -> bool: return c.key != "voice")
	var k2 := FY.keys_of(FY.pick(without, 7, keep))
	check(k2[0] == "woche" and k2.has("erfolg:g4") and not k2.has("voice") and k2.size() == 3, "weggefallene Karte wird ersetzt, der Rest bleibt (%s)" % str(k2))
	var no_big := FY.pick(cands, 7, ["voice", "woche"])
	check(str((no_big.big as Dictionary).get("key", "")) != "voice", "eine Karte, die nicht groß taugt, wird nie groß")
	# Live (Freund in deinem Spiel) kommt immer mit und verdrängt eine Karte mit demselben Spiel.
	var live_c: Array = cands + [mk.call("freunde", "freunde", 6.0, true, "g4", true)]
	var always := true
	var no_dup := true
	for sd in 200:
		var ks2 := FY.keys_of(FY.pick(live_c, sd, ["erfolg:g4", "weiter", "woche"] if sd % 2 == 0 else []))
		always = always and ks2.has("freunde")
		no_dup = no_dup and not ks2.has("erfolg:g4")
	check(always and no_dup, "Live-Karte immer dabei, das gleiche Spiel nicht doppelt")
	var few := FY.pick([mk.call("voice", "voice", 5.0, false)], 3)
	check((few.big as Dictionary).is_empty() and (few.small as Array).size() == 1, "nur kleine Kandidaten: keine leere große Karte")
	check(FY.card_sig(cands[0]) != FY.card_sig(cands[1]) and FY.card_sig({}) == "", "Inhalt je Karte als Text (nur bei Änderung neu bauen)")

	print("Für dich: Daten")
	var now := 1_800_000_000
	check(FY.since(now - 30, now) == "Gerade eben" and FY.since(now - 7200, now) == "Vor 2 Std.", "vor kurzem, vor 2 Std.")
	check(FY.since(now - 130000, now) == "Gestern" and FY.since(now - 3 * 86400, now) == "Vor 3 Tagen", "gestern, vor 3 Tagen")
	check(FY.since(now - 240 * 86400, now) == "Vor 8 Monaten" and FY.since(now - 800 * 86400, now) == "Vor 2 Jahren",
			"Monate, Jahre (%s)" % FY.since(now - 240 * 86400, now))
	var wk := FY.week([{ "id": "a", "at": now - 60, "secs": 600 }, { "id": "b", "at": now - 3 * 86400, "secs": 3600 },
		{ "id": "b", "at": now - 3 * 86400 + 100, "secs": 1800 }, { "id": "c", "at": now - 10 * 86400, "secs": 9000 }, { "id": "x", "secs": 50 }], now, 0)
	check(int(wk.values[6]) == 600 and int(wk.values[3]) == 5400 and int(wk.total) == 6000, "Woche: heute rechts, älter als 7 Tage zählt nicht")
	check(str(wk.top_id) == "b" and (wk.labels as Array).size() == 7, "Woche: meistgespieltes Spiel, sieben Tage")
	var old_g := { "id": "o", "last_played": now - 200 * 86400, "playtime": 30 * 3600 }
	var fav_g := { "id": "f", "last_played": now - 100 * 86400, "playtime": 20 * 3600, "favorite": true }
	var recent_g := { "id": "r", "last_played": now - 5 * 86400, "playtime": 90 * 3600 }
	var short_g := { "id": "s", "last_played": now - 300 * 86400, "playtime": 600 }
	var rd := FY.rediscover([old_g, fav_g, recent_g, short_g], now)
	check(rd.size() == 2 and str(rd[0].id) == "f", "Wiederentdecken: lange liegend, lange gespielt; Favorit zuerst")
	var bulk: Array = []
	for i in 12:
		bulk.append({ "id": "b%d" % i, "added": now - 5 * 86400 + i })
	bulk.append({ "id": "neu", "added": now - 2 * 86400 })
	bulk.append({ "id": "gespielt", "added": now - 86400, "last_played": now - 3600 })
	var ng := FY.new_games(bulk, now)
	check(ng.size() == 1 and str(ng[0].id) == "neu", "Neu: Ersteinrichtung und Gespieltes zählen nicht")
	check(FY.new_games([{ "id": "alt", "added": now - 60 * 86400 }, { "id": "ohne" }], now).is_empty(), "Neu: zu alt oder ohne Datum zählt nicht")
	var few_new := FY.new_games([{ "id": "x", "added": now - 3 * 86400 }, { "id": "y", "added": now - 86400 }], now)
	check(few_new.size() == 2 and str(few_new[0].id) == "y", "Neu: wenige neue Spiele, neuestes zuerst")
	var na := FY.next_achievement({ "list": [{ "title": "A", "unlocked": true, "rarity": 90.0 }, { "title": "B", "unlocked": false, "rarity": 12.0 },
		{ "title": "C", "unlocked": false, "rarity": 40.0, "hidden": true }, { "title": "D", "unlocked": false, "rarity": 33.0 }] })
	check(str(na.get("title", "")) == "D", "nächster Erfolg: offen, nicht geheim, der häufigste")
	check(FY.next_achievement({ "list": [{ "title": "A", "unlocked": true }] }).is_empty(), "alles geschafft: kein nächster Erfolg")
	check(FY.names([{ "name": "Mira" }]) == "Mira" and FY.names([{ "name": "Mira" }, { "name": "Jonas" }]) == "Mira und Jonas" \
		and FY.names([{ "name": "A" }, { "name": "B" }, { "name": "C" }]) == "A und 2 weitere", "Namen kurz")


## Die Seitenleiste „Für dich“: oben groß, darunter Abschnitte (reine Funktionen in for_you.gd).
func _fuer_dich_leiste() -> void:
	const FY := preload("res://src/ui/components/for_you.gd")
	print("Für dich: Seitenleiste")
	var weiter := { "key": "weiter", "kind": "weiter", "game_id": "g1", "title": "Ico" }
	var runde := { "key": "runde", "kind": "runde", "lead": true, "game_id": "g1", "title": "Ico" }
	var film := { "key": "medien:film", "kind": "medien", "title": "Film" }
	check(FY.held([weiter, runde]) == runde and FY.held([weiter]) == weiter and FY.held([film], film) == film and FY.held([]).is_empty(),
			"oben: die Runde eben, sonst Weiterspielen, sonst die große Karte")
	var cands: Array = [weiter,
		{ "key": "neu:g1", "kind": "neu", "game_id": "g1", "title": "Ico" }, { "key": "neu:g2", "kind": "neu", "game_id": "g2", "title": "Rez" },
		{ "key": "erfolg:fast", "kind": "erfolg", "game_id": "g3", "title": "Okami", "frac": 0.86, "sub": "Noch 3 Erfolge bis 100 %" },
		{ "key": "freunde", "kind": "freunde", "title": "Mira online" }, { "key": "voice", "kind": "voice", "title": "Jonas", "people": [{ "name": "Jonas" }] },
		film, { "key": "medien:musik", "kind": "medien", "music": true, "why": "Zuletzt gehört", "title": "Song" },
		{ "key": "woche", "kind": "woche", "title": "4 Std. gespielt" }]
	var o := FY.ordnen(cands)
	var ids: Array = (o.abschnitte as Array).map(func(a: Dictionary) -> String: return str(a.id))
	check(o.hero == weiter and ids == ["freunde", "erfolge", "schauen", "musik", "neu", "woche"], "feste Reihenfolge, nur mit Inhalt (%s)" % str(ids))
	var neu: Array = (o.abschnitte[ids.find("neu")] as Dictionary).rows
	check(neu.size() == 1 and str(neu[0].key) == "neu:g2", "das Spiel oben steht nicht noch einmal unter Neu")
	var er: Dictionary = (o.abschnitte[ids.find("erfolge")] as Dictionary).rows[0]
	check(str(er.value) == "86 %" and str(er.extra).begins_with("Noch 3"), "Fast geschafft: rechts der Stand")
	check(str((o.abschnitte[ids.find("musik")] as Dictionary).label) == "Zuletzt gehört", "nichts läuft: „Zuletzt gehört“")
	var fr: Array = (o.abschnitte[0] as Dictionary).rows
	check(fr.size() == 2 and str(fr[1].key) == "voice" and (fr[1].person as Dictionary).name == "Jonas", "Freunde: Gruppe und Sprachkanal")
	var ex := { "freunde": [{ "key": "fr:1", "title": "Mira" }, { "key": "fr:2", "title": "Ben" }, { "key": "fr:3", "title": "Dan" },
		{ "key": "fr:4", "title": "Eva" }, { "key": "fr:alle", "title": "Alle", "mehr": true }],
		"schauen": [{ "key": "yt:1", "title": "Video" }], "wieder": [{ "key": "jahr:g1", "game_id": "g1", "title": "Ico" }] }
	var o2 := FY.ordnen(cands, ex)
	var ids2: Array = (o2.abschnitte as Array).map(func(a: Dictionary) -> String: return str(a.id))
	var fr2: Array = (o2.abschnitte[0] as Dictionary).rows
	check(fr2.size() == FY.ZEILEN_MAX + 1 and str(fr2[0].key) == "fr:1" and str(fr2[FY.ZEILEN_MAX].key) == "fr:alle",
			"je Abschnitt höchstens %d Zeilen, einzelne Freunde vorn, „Alle Freunde“ zuletzt" % FY.ZEILEN_MAX)
	check(not fr2.any(func(z: Dictionary) -> bool: return str(z.key) == "freunde"), "einzelne Freunde ersetzen die Gruppe")
	var sch: Array = (o2.abschnitte[ids2.find("schauen")] as Dictionary).rows
	check(sch.size() == 1 and str(sch[0].key) == "yt:1", "Weiterschauen: die Liste ersetzt die eine Karte")
	check(not ids2.has("wieder"), "„Vor einem Jahr“ nicht für das Spiel, das oben steht")
	print("Für dich: Freunde, Angebote, vor einem Jahr")
	var own := { 10: { "id": "a" } }
	var fs := FY.freunde_spielen([{ "name": "A", "state": "game", "game": "X", "game_id": "20", "since": 1 },
		{ "name": "B", "state": "game", "game": "Y", "game_id": "10", "since": 5 }, { "name": "C", "state": "online" },
		{ "name": "D", "state": "game", "game": "" }], own)
	check(fs.size() == 2 and str(fs[0].name) == "B", "wer spielt: zuerst in deinen Spielen, ohne Spiel nicht")
	var an := FY.angebote([{ "appid": 1, "discount": 0 }, { "appid": 2, "discount": 30 }, { "appid": 3, "discount": 75 }, { "appid": 4, "discount": 10 }], { 4: true })
	check(an.map(func(it: Dictionary) -> int: return int(it.appid)) == [4, 3, 2], "Angebote: neu zuerst, dann der höchste Rabatt, ohne Rabatt nicht")
	var now := 400 * 86400 + 43200
	var j := FY.vor_einem_jahr([{ "id": "x", "at": now - 365 * 86400, "secs": 1800 }, { "id": "y", "at": now - 364 * 86400, "secs": 1200 },
		{ "id": "x", "at": now - 300 * 86400, "secs": 9000 }, { "id": "z", "at": now - 365 * 86400, "secs": 120 }], now, 0)
	check(str(j.get("id", "")) == "x" and int(j.secs) == 1800 and bool(j.heute), "vor einem Jahr: das, was damals am längsten lief")
	check(FY.vor_einem_jahr([{ "id": "z", "at": now - 365 * 86400, "secs": 120 }], now, 0).is_empty()
			and FY.vor_einem_jahr([{ "id": "x", "at": now - 200 * 86400, "secs": 9000 }], now, 0).is_empty(), "nur mit echten Daten von damals")
