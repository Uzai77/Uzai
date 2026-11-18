extends Node
## Nach dem Spielen und Verlauf je Spiel (Punkte 24, 38, 100) ohne Bildschirm: Meilensteine,
## Zeitraum einer Runde (Erfolge, Aufnahmen), Zahlen für die Spielseite, „Gerade gespielt“ vorn.
## Aufruf: godot --headless --path . res://tests/logic_nachspiel.tscn

const SS := preload("res://src/core/session_summary.gd")
const FY := preload("res://src/ui/components/for_you.gd")
const SessionChart := preload("res://src/ui/components/session_chart.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Meilensteine")
	check(SS.milestone(0, 3599) == 0, "unter einer Stunde: keiner")
	check(SS.milestone(3500, 3700) == 1, "über 1 Std.: 1")
	check(SS.milestone(0, 6 * 3600) == 5, "mehrere auf einmal: der größte (5)")
	check(SS.milestone(99 * 3600, 101 * 3600) == 100, "100 Std.")
	check(SS.milestone(100 * 3600, 101 * 3600) == 0, "schon vorher erreicht: keiner")
	check(SS.milestone(999 * 3600, 1001 * 3600) == 1000, "1000 Std.")
	check(SS.marks(0) == [0, 1] and SS.marks(3 * 3600) == [1, 5] and SS.marks(100 * 3600) == [100, 250], "erreicht und nächste Marke")
	check(SS.marks(1200 * 3600) == [1000, 0], "über der letzten Marke: keine nächste")

	print("Spielzeit vor und nach der Runde")
	check(SS.totals({ "playtime": 7200 }, 1800) == [5400, 7200], "eigene Zählung enthält die Runde schon")
	check(SS.totals({ "playtime": 1800, "steam_minutes": 600 }, 1800) == [36000, 37800], "Steam-Minuten ohne die Runde: zählen als vorher")
	check(SS.totals({}, 600) == [0, 600], "neues Spiel")

	print("Tageszeit")
	var parts := {}
	for h in 24:
		parts[str(SS.daypart(h)[0])] = int(parts.get(str(SS.daypart(h)[0]), 0)) + 1
	check(SS.daypart(7) == ["Morgens", "spark"] and SS.daypart(5)[0] == "Morgens" and SS.daypart(4)[0] == "Nachts", "Morgens ab 5 Uhr")
	check(SS.daypart(12)[0] == "Mittags" and SS.daypart(15)[0] == "Nachmittags", "Mittags, Nachmittags")
	check(SS.daypart(18) == ["Abends", "moon"] and SS.daypart(22)[0] == "Abends" and SS.daypart(23) == ["Nachts", "moon"], "Abends bis 23 Uhr, dann Nachts")
	check(parts.size() == 5 and int(parts.Nachts) == 6, "jede Stunde hat genau eine Tageszeit")
	# Runden beginnen um 21 Uhr Ortszeit (bias +1 Std.): Ende 21:30, Dauer 30 Min.
	var day0 := 20000 * 86400
	var evening := [{ "at": day0 + 20 * 3600 + 1800, "secs": 1800 }, { "at": day0 + 86400 + 20 * 3600 + 2400, "secs": 1800 },
		{ "at": day0 + 9 * 3600, "secs": 600 }]
	check(SS.peak_hour(evening, 3600) == 21, "Ortszeit über bias, Beginn statt Ende (%d)" % SS.peak_hour(evening, 3600))
	check(SS.peak_hour([{ "at": day0 + 3600, "secs": 7200 }], 0) == 23, "Runde über Mitternacht: zählt am Vorabend")

	print("Verlauf je Spiel")
	var sess: Array = []
	for i in 20:
		sess.append({ "id": "a", "at": day0 + i * 86400 + 21 * 3600, "secs": 600 + i * 60 })
	sess.append({ "id": "b", "at": day0 + 5 * 86400, "secs": 99999 })
	sess.append({ "id": "a", "at": day0 + 3 * 86400, "secs": 0 })
	sess.append("kaputt")
	sess.reverse()
	var st := SS.per_game(sess, "a", 0)
	check(int(st.count) == 20, "nur Runden des Spiels, ohne leere und kaputte (%d)" % int(st.count))
	check(int(st.total) == 20 * 600 + 60 * 190 and int(st.avg) == floori(float(st.total) / 20), "Summe und Schnitt")
	check(int(st.longest.secs) == 600 + 19 * 60 and int(st.longest.at) == day0 + 19 * 86400 + 21 * 3600, "längste Runde mit Datum")
	check(int(st.first) == day0 + 21 * 3600 - 600 and int(st.last) == day0 + 19 * 86400 + 21 * 3600, "erste (Beginn) und letzte (Ende)")
	check((st.recent as Array).size() == SS.CHART_N, "Verlauf: höchstens %d Runden" % SS.CHART_N)
	check(int(st.recent[SS.CHART_N - 1].at) == int(st.last) and int(st.recent[0].at) < int(st.recent[1].at), "älteste zuerst, neueste zuletzt")
	check(int(st.peak) == 20, "Tageszeit ab drei Runden (%d)" % int(st.peak))
	var two := SS.per_game(sess.filter(func(x: Variant) -> bool: return x is Dictionary and str(x.id) == "b"), "b", 0)
	check(int(two.count) == 1 and int(two.peak) == -1, "unter drei Runden keine Tageszeit")
	check(SS.per_game(sess, "nichts", 0).is_empty(), "ohne Runden: leer")

	print("Zusammenfassung einer Runde")
	var now := day0 + 10 * 86400
	var r := { "game_id": "a", "title": "Hades", "start": now - 5400, "end": now, "secs": 5400, "before": 99 * 3600, "after": 99 * 3600 + 5400 }
	var unlocks := [
		{ "game_key": "steam:1145360", "name": "Spät", "platform": "steam", "unlocked_at": now + SS.LATE_S - 1 },
		{ "game_key": "steam:1145360", "name": "Drin", "platform": "steam", "unlocked_at": now - 600 },
		{ "game_key": "steam:1145360", "name": "Zu spät", "platform": "steam", "unlocked_at": now + SS.LATE_S + 60 },
		{ "game_key": "steam:1145360", "name": "Gestern", "platform": "steam", "unlocked_at": now - 86400 },
		{ "game_key": "steam:42", "name": "Anderes Spiel", "platform": "steam", "unlocked_at": now - 300 },
		{ "game_key": "ra:7", "name": "Retro", "platform": "ra", "unlocked_at": now - 300 },
		"kaputt",
	]
	var items := [
		{ "path": "/c/neu.mp4", "kind": "clip", "mtime": now + 30 },
		{ "path": "/c/b.png", "kind": "shot", "mtime": now - 100 },
		{ "path": "/c/a.mp4", "kind": "clip", "mtime": now - 4000 },
		{ "path": "/c/alt.mp4", "kind": "clip", "mtime": now - 86400 },
	]
	var s := SS.make(r, unlocks, "steam:1145360", false, items, { "total": 50, "unlocked": 34, "list": [] })
	var names: Array = (s.unlocks as Array).map(func(e: Dictionary) -> String: return str(e.name))
	check(names == ["Spät", "Drin"], "Erfolge des Spiels im Zeitraum, bis %d s danach (%s)" % [SS.LATE_S, ", ".join(names)])
	check(int(s.clips) == 2 and int(s.shots) == 1 and str(s.newest) == "/c/neu.mp4", "Clips und Bilder aus dem Zeitraum, neueste vorn")
	check(int(s.mark) == 100 and int(s.after) == 99 * 3600 + 5400, "100 Std. erreicht")
	check(int(s.have) == 34 and int(s.total) == 50 and int(s.secs) == 5400, "Fortschritt und Dauer")
	var rom := SS.make(r, unlocks, "", true, [], {})
	check((rom.unlocks as Array).size() == 1 and str(rom.unlocks[0].name) == "Retro", "Emulator ohne RA-Nummer: RA-Erfolge aus dem Zeitraum")
	check((SS.make(r, unlocks, "", false, [], {}).unlocks as Array).is_empty(), "unbekanntes PC-Spiel: keine fremden Erfolge")
	var err := SS.make(r, [], "steam:1", false, [], { "total": 0, "unlocked": 0, "error": "weg" })
	check(int(err.total) == 0 and int(err.mark) == 100, "Erfolge nicht abrufbar: ohne Fortschritt, Rest bleibt")

	print("Karte „Gerade gespielt“")
	check(SS.card_due(r, now + 60), "frisch: Karte")
	check(not SS.card_due(r, now + SS.SHOW_S + 1), "nach %d Std. nicht mehr" % (SS.SHOW_S / 3600))
	var short := r.duplicate()
	short.secs = SS.MIN_SECS - 1
	check(not SS.card_due(short, now + 60) and not SS.card_due({}, now), "kurze Runde oder keine: keine Karte")
	var c_lead := { "key": "runde", "kind": "runde", "weight": 0.5, "big": true, "lead": true, "game_id": "a" }
	var c_weiter := { "key": "weiter", "kind": "weiter", "weight": 5.0, "big": true, "game_id": "a" }
	var c_woche := { "key": "woche", "kind": "woche", "weight": 9.0, "big": true }
	var c_neu := { "key": "neu", "kind": "neu", "weight": 3.0, "big": true, "game_id": "b" }
	var lead_ok := true
	for seed_ in 30:
		var p := FY.pick([c_woche, c_weiter, c_neu, c_lead], seed_, ["woche", "neu"])
		if str(p.big.get("key", "")) != "runde" or (p.small as Array).any(func(c: Dictionary) -> bool: return str(c.key) == "weiter"):
			lead_ok = false
	check(lead_ok, "steht immer groß vorn (auch gegen die bisherige große Karte), Weiterspielen desselben Spiels weicht")
	var p2 := FY.pick([c_woche, c_neu], 3, ["woche", "neu"])
	check(str(p2.big.get("key", "")) == "woche", "ohne sie: bisherige Auswahl bleibt")

	print("Datum und Uhrzeit")
	var noon := now + 12 * 3600
	check(SS.day_text(noon - 60, 0, noon) == "Heute" and SS.day_text(noon - 86400, 0, noon) == "Gestern" and SS.day_text(now - 60, 0, noon) == "Gestern",
			"Heute, Gestern (nach Kalendertag)")
	check(SS.day_text(now - 5 * 86400, 0, now) != "Gestern" and SS.date_text(now - 400 * 86400, 0, now).length() > 8, "älter: Datum, anderes Jahr mit Jahr")
	check(SS.clock(day0 + 21 * 3600 + 5 * 60, 0) == "21:05" and SS.clock(day0 + 21 * 3600 + 5 * 60, 0, false) == "9:05 PM" \
		and SS.clock(day0 + 5 * 60, 0, false) == "12:05 AM", "Uhrzeit 24 und 12 Stunden")

	print("Verlauf auf der Spielseite: links/rechts")
	var chart = SessionChart.new().setup(st.recent, 0, Vector2(1200, 320))
	add_child(chart)
	check(chart.sel == SS.CHART_N - 1, "ohne Auswahl: die neueste")
	check(chart.nav_lr(-1) and chart.sel == SS.CHART_N - 2, "links: eine Runde früher")
	check(chart.nav_lr(1) and chart.sel == SS.CHART_N - 1, "rechts zurück")
	check(chart.nav_lr(1) and chart.sel == SS.CHART_N - 1, "am rechten Rand: stößt an, Fokus bleibt")
	chart.sel = 0
	check(chart.nav_lr(-1) and chart.sel == 0, "am linken Rand: stößt an, Fokus bleibt")
	chart.queue_free()

	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)
