extends Node
## Bühne der Spielseite und Blöcke des Profils (src/ui/spielseite/buehne.gd), ohne Bildschirm: die
## Woche aus den Runden, kurze Zeiten, die beiden Zeilen unter dem Titel, Kürzen von hinten, Texte
## der Karten (Erfolge, Freunde, Stände), welche Karten erscheinen, die Zeile unter den Runden,
## Anteile des Vergleichs, Vitrine, Zuletzt gespielt und die Reihenfolge der Freunde.
## Aufruf: godot --headless --path . res://tests/logic_buehne.tscn → „Ergebnis: alles ok“

const Buehne := preload("res://src/ui/spielseite/buehne.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_woche()
	_zeiten()
	_zeilen()
	_karten()
	_profil()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _woche() -> void:
	print("Die Woche")
	var bias := 0
	var now := 1_800_000_000 + 12 * 3600          # mittags
	var heute := Buehne.tag(now, bias)
	var tag0 := heute * 86400                       # Mitternacht heute
	var sessions := [
		{ "id": "a", "at": tag0 + 3600, "secs": 1800 },                 # heute, 1800
		{ "id": "a", "at": tag0 - 3600, "secs": 600 },                  # gestern
		{ "id": "b", "at": tag0 - 3600, "secs": 900 },                  # gestern, anderes Spiel
		{ "id": "a", "at": tag0 - 6 * 86400 + 10, "secs": 100 },        # vor 6 Tagen: noch drin
		{ "id": "a", "at": tag0 - 7 * 86400 + 10, "secs": 5000 },       # vor 7 Tagen: raus
		{ "id": "a", "at": 0, "secs": 999 }, { "id": "a", "at": tag0, "secs": 0 }, "kaputt",
	]
	var w := Buehne.woche(sessions, "a", now, bias)
	check(w.tage == [100, 0, 0, 0, 0, 600, 1800], "nur dieses Spiel, älteste zuerst, heute zuletzt: %s" % [w.tage])
	check(int(w.gesamt) == 2500 and int(w.gespielt) == 3 and int(w.max) == 1800, "Summe, Tage mit Zeit, Höchstwert")
	check(str(w.labels[6]) == "Heute" and w.labels.size() == 7 and str(w.labels[0]) in Buehne.TAGE_KURZ, "Kurznamen, zuletzt „Heute“")
	var alle := Buehne.woche(sessions, "", now, bias)
	check(int(alle.gesamt) == 3400, "ohne Kennung zählen alle Spiele")
	check(Buehne.woche([], "a", now, bias).gesamt == 0, "ohne Runden: leer, aber sieben Tage")
	# Zeitzone: eine Runde kurz vor Mitternacht UTC liegt in Berlin schon im nächsten Tag.
	var spaet := [{ "id": "a", "at": tag0 - 1800, "secs": 300 }]
	check(Buehne.woche(spaet, "a", now, 0).tage[5] == 300 and Buehne.woche(spaet, "a", now, 3600).tage[6] == 300, "Tag nach Ortszeit")


func _zeiten() -> void:
	print("Kurze Zeiten")
	check(Buehne.zeit_kurz(0) == "0 Std." and Buehne.zeit_kurz(59) == "1 Min." and Buehne.zeit_kurz(45 * 60) == "45 Min.", "Minuten")
	check(Buehne.zeit_kurz(3600 * 3 + 1800) == "3,5 Std." and Buehne.zeit_kurz(7200) == "2 Std.", "unter 10 Stunden mit Komma, ohne ,0")
	check(Buehne.zeit_kurz(432000) == "120 Std." and Buehne.zeit_kurz(1284 * 3600) == "1.284 Std.", "große Zahlen mit Punkt")
	check(Buehne.tausender(6873) == "6.873" and Buehne.tausender(999) == "999" and Buehne.tausender(1000000) == "1.000.000", "Tausenderpunkte")
	check(Buehne.zuletzt_text("Heute") == "heute" and Buehne.zuletzt_text("Vor 3 Tagen") == "vor 3 Tagen"
		and Buehne.zuletzt_text("12.03.2024") == "am 12.03.2024" and Buehne.zuletzt_text("") == "", "zuletzt-Text im Satz")


func _zeilen() -> void:
	print("Zeilen unter dem Titel")
	var o := Buehne.oben("PlayStation 2", "PCSX2", "CRT · 480 Zeilen", PackedStringArray(), "")
	check(o == ["PlayStation 2", "PCSX2", "Bild: CRT, 480 Zeilen"], "Emulator-Spiel: System, Emulator, Bild (Punkt im Wert wird Komma)")
	check(Buehne.oben("", "", "", PackedStringArray(["Action", "RPG", "Souls"]), "FromSoftware") == ["Action, RPG", "FromSoftware"], "Steam: zwei Genres, Studio")
	check(Buehne.oben("", "", "", PackedStringArray(), "", "Epic Games") == ["Epic Games"] and Buehne.oben("", "", "", PackedStringArray(), "").is_empty(),
		"sonst die Quelle, ohne alles leer")
	check(Buehne.unten(432000, "heute", true) == ["120 Std. gespielt", "zuletzt heute"], "was es dir ist")
	check(Buehne.unten(0, "", false, "182 GB frei auf C:") == ["Noch nicht gespielt", "nicht installiert", "182 GB frei auf C:"], "nie gespielt, nicht installiert, Platz")
	var breite := func(t: String) -> float: return float(t.length()) * 10.0
	check(Buehne.passend(["Eins", "Zwei", "Drei"], 230.0, breite) == "Eins  ·  Zwei  ·  Drei", "passt ganz")
	check(Buehne.passend(["Eins", "Zwei", "Drei"], 140.0, breite) == "Eins  ·  Zwei", "hintere Angabe fällt weg")
	check(Buehne.passend(["Einundzwanzig", "Zwei"], 50.0, breite) == "Einundzwanzig", "die erste bleibt immer")
	check(Buehne.passend(["", "A", "", "B"], 999.0, breite) == "A  ·  B" and Buehne.passend([], 100.0, breite) == "", "Leeres fällt weg")


func _karten() -> void:
	print("Karten der Bühne")
	var ago := func(unix: int) -> String: return "Heute" if unix > 100 else "Gestern"
	var e := Buehne.erfolge({ "total": 42, "unlocked": 29, "list": [
		{ "title": "Alt", "unlocked": true, "date": 50 }, { "title": "Neu", "unlocked": true, "date": 500 },
		{ "title": "Geheim", "unlocked": false, "hidden": true }, { "title": "Offen", "unlocked": false }] }, ago)
	check(str(e.wert) == "29 von 42" and is_equal_approx(float(e.frac), 29.0 / 42.0) and not e.voll, "Stand und Anteil")
	check(str(e.sub) == "Zuletzt: Neu · heute", "zuletzt freigeschaltet, der neueste (%s)" % e.sub)
	var e2 := Buehne.erfolge({ "total": 5, "unlocked": 0, "list": [{ "title": "Geheim", "hidden": true }, { "title": "Erster", "unlocked": false }] }, ago)
	check(str(e2.sub) == "Als Nächstes: Erster" and str(e2.wert) == "0 von 5", "noch nichts frei: der nächste offene, nie ein geheimer")
	check(str(Buehne.erfolge({ "total": 3, "unlocked": 3 }, ago).sub) == "Alle freigeschaltet" and Buehne.erfolge({ "total": 3, "unlocked": 3 }, ago).voll, "alles geschafft")
	check(Buehne.erfolge({}, ago).is_empty() and Buehne.erfolge({ "total": 0 }, ago).is_empty(), "ohne Erfolge nichts")
	var f1 := Buehne.freunde([{ "name": "Mira", "lobby": "1" }])
	check(str(f1.titel) == "Mira spielt gerade" and str(f1.sub) == "Beitreten möglich" and f1.beitreten, "eine Person mit Lobby")
	var f3 := Buehne.freunde([{ "name": "A" }, { "name": "B" }, { "name": "C" }, { "name": "D" }])
	check(str(f3.titel) == "4 Freunde spielen gerade" and str(f3.sub) == "A, B, C …" and not f3.beitreten, "mehrere: Zahl und die ersten drei Namen")
	check(Buehne.freunde([]).is_empty(), "ohne Freunde nichts")
	check(Buehne.karten({ "secs": 100, "erfolge_bekannt": true, "freunde": 2, "staende": 1 }) == ["zeit", "erfolge", "freunde", "stand"], "alle vier in fester Reihenfolge")
	check(Buehne.karten({ "runden": 1 }) == ["zeit"] and Buehne.karten({ "erfolge_moeglich": true }) == ["erfolge"], "nur, was es gibt")
	check(Buehne.karten({}).is_empty() and Buehne.karten({ "secs": 0, "freunde": 0 }).is_empty(), "frisches Spiel: keine Karte")
	print("Pillen unter den Knöpfen")
	check(Buehne.pille_zeit(3 * 3600) == { "wert": "3 Std.", "wort": "diese Woche" }, "Woche mit Zeit")
	check(Buehne.pille_zeit(0) == { "wert": "", "wort": "Spielzeit" }, "Woche ohne Spiel: nur das Wort, keine doppelte Summe")
	check(Buehne.pille_erfolge(29, 42) == { "wert": "29 / 42", "wort": "Erfolge" }, "Erfolge als 29 / 42")
	check(str(Buehne.pille_erfolge(0, 0).wert) == "…" and str(Buehne.pille_erfolge(50, 42).wert) == "42 / 42", "lädt noch; nie mehr als alle")
	check(Buehne.pille_freunde([{ "name": "Mira" }]) == { "wert": "Mira", "wort": "spielt gerade", "roh": true }, "eine Person (der Name bleibt unübersetzt)")
	check(str(Buehne.pille_freunde([{ "name": "Ein sehr langer Steam-Name" }]).wert).length() == Buehne.NAME_MAX, "langer Name gekürzt")
	check(Buehne.pille_freunde([{ "name": "A" }, { "name": "B" }, "kaputt"]) == { "wert": "2 Freunde", "wort": "spielen gerade" }, "mehrere")
	check(Buehne.pille_freunde([]).is_empty() and Buehne.pille_staende(0).is_empty(), "ohne nichts")
	check(Buehne.pille_staende(1).wort == "Spielstand" and Buehne.pille_staende(3) == { "wert": "3", "wort": "Spielstände" }, "Spielstände")
	var dur := func(s: int) -> String: return "%d Min." % int(s / 60)
	var date := func(_u: int) -> String: return "12. März"
	var dp := func(_h: int) -> Array: return ["Abends", "moon"]
	var z := Buehne.runden_zeile({ "count": 3, "avg": 600, "longest": { "secs": 1200, "at": 5 }, "peak": 21 }, 3000, dur, date, dp, [0, 1])
	check(z == ["3 Runden · im Schnitt 10 Min.", "längste 20 Min. am 12. März", "meist abends", "noch 10 Min. bis 1 Std."], "Zeile unter den Runden: %s" % [z])
	check(Buehne.runden_zeile({}, 0, dur, date, dp, [0, 0]).is_empty(), "ohne Runden keine Zeile")
	check(Buehne.runden_zeile({ "count": 1, "avg": 60, "longest": {}, "peak": -1 }, 60, dur, date, dp, [1000, 0]).size() == 1, "ohne Tageszeit und nach dem letzten Meilenstein nur die Runden")


func _profil() -> void:
	print("Profil")
	var a := Buehne.anteile(120.0, 240.0)
	check(is_equal_approx(float(a.a), 0.5) and is_equal_approx(float(a.b), 1.0), "Anteile am größeren Wert")
	check(Buehne.anteile(0.0, 0.0) == { "a": 0.0, "b": 0.0 }, "beide null")
	var pt := func(g: Dictionary) -> int: return int(g.get("playtime", 0))
	var games := [{ "id": "a", "playtime": 10 }, { "id": "b", "playtime": 300, "favorite": true }, { "id": "c", "playtime": 900, "favorite": true }, { "id": "d" }]
	var v := Buehne.vitrine(games, pt)
	check(str(v.titel) == "Vitrine" and str(v.extra) == "2 Favoriten" and v.list.map(func(g): return g.id) == ["c", "b"], "Favoriten, längste zuerst")
	var v2 := Buehne.vitrine([{ "id": "a", "playtime": 10 }, { "id": "b", "playtime": 20 }], pt)
	check(str(v2.extra) == "am meisten gespielt" and v2.list[0].id == "b", "ohne Favoriten die meistgespielten")
	check(Buehne.vitrine([{ "id": "d" }], pt).is_empty(), "nichts gespielt, nichts markiert: keine Vitrine")
	var fr := Buehne.freunde_reihe([{ "name": "Tom", "state": "offline" }, { "name": "Lea", "state": "online" }, { "name": "Ben", "state": "game" },
		{ "name": "Ada", "state": "online" }, 7], 3)
	check(fr.list.map(func(f): return f.name) == ["Ben", "Ada", "Lea"] and int(fr.online) == 3, "im Spiel, dann online nach Namen; Kaputtes fällt weg")
