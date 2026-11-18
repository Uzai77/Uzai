extends RefCounted
## Reine Logik für „Nach dem Spielen“ und den Verlauf je Spiel (Punkte 24, 38, 100) – ohne
## Zustand, darum in tests/logic_nachspiel.gd geprüft: welche Stunden-Marke eine Runde
## überschritten hat, was zur Zusammenfassung einer Runde gehört (Erfolge und Aufnahmen aus ihrem
## Zeitraum) und die Zahlen für „Deine Spielzeit“ auf der Spielseite.
##
## Alles kommt aus Uzais eigenen Daten auf diesem PC (sessions.json, Verlauf der Erfolge,
## Aufnahmeordner); nichts davon geht ins Netz.

const Lang := preload("res://src/core/lang.gd")

const MARKS_H := [1, 5, 10, 25, 50, 100, 250, 500, 1000]   ## Meilensteine je Spiel, in Stunden
const MIN_SECS := 300       ## kürzere Runden: keine Zusammenfassung (die kurze Mitteilung bleibt)
const SHOW_S := 3 * 3600    ## so lange steht „Gerade gespielt“ unter „Für dich“
const LATE_S := 180         ## Erfolge und Aufnahmen bis so lange nach dem Ende zählen noch zur Runde
const CHART_N := 14         ## so viele Runden zeigt der Verlauf auf der Spielseite
const UNLOCKS_N := 100      ## so viele neueste Erfolge aus dem Verlauf reichen für eine Runde


## Die größte Stunden-Marke zwischen vorher und nachher (Sekunden); 0 = keine überschritten.
static func milestone(before: int, after: int) -> int:
	var hit := 0
	for h in MARKS_H:
		if before < int(h) * 3600 and after >= int(h) * 3600:
			hit = int(h)
	return hit


## Die zuletzt erreichte Marke (Stunden, 0 unter der ersten) und die nächste (0 über der letzten).
static func marks(secs: int) -> Array:
	var reached := 0
	for h in MARKS_H:
		if secs >= int(h) * 3600:
			reached = int(h)
		else:
			return [reached, int(h)]
	return [reached, 0]


## Spielzeit eines Spiels vor und nach einer Runde, wie Library.playtime. g ist der Eintrag nach
## Library.record_session (playtime enthält die Runde schon); Steams eigene Minuten (steam_minutes)
## enthalten sie dagegen noch nicht und zählen deshalb als „vorher“.
static func totals(g: Dictionary, secs: int) -> Array:
	var before := maxi(maxi(int(g.get("playtime", 0)) - secs, int(g.get("steam_minutes", 0)) * 60), 0)
	return [before, before + secs]


## Tageszeit zu einer Stunde (0–23): [Name, Symbol].
static func daypart(hour: int) -> Array:
	if hour >= 5 and hour < 11:
		return ["Morgens", "spark"]
	if hour >= 11 and hour < 14:
		return ["Mittags", "spark"]
	if hour >= 14 and hour < 18:
		return ["Nachmittags", "spark"]
	if hour >= 18 and hour < 23:
		return ["Abends", "moon"]
	return ["Nachts", "moon"]


## Zu welcher Stunde die meisten Runden beginnen ({ at = Ende, secs }); bias: Zeitzone in s.
## Gleichstand: die frühere Stunde.
static func peak_hour(sessions: Array, bias: int) -> int:
	var hours: Array = []
	hours.resize(24)
	hours.fill(0)
	for se in sessions:
		var h := floori(posmod(int(se.at) - int(se.secs) + bias, 86400) / 3600.0)
		hours[h] = int(hours[h]) + 1
	var peak := 0
	for h in 24:
		if int(hours[h]) > int(hours[peak]):
			peak = h
	return peak


## „Heute“, „Gestern“ oder das Datum (aus einem anderen Jahr mit Jahr); Ortszeit über bias (s).
static func day_text(unix: int, bias: int, now: int) -> String:
	var d := floori(float(unix + bias) / 86400.0)
	var today := floori(float(now + bias) / 86400.0)
	if d == today:
		return "Heute"
	if d == today - 1:
		return "Gestern"
	return date_text(unix, bias, now)


## „12. März“, aus einem anderen Jahr „12. März 2024“.
static func date_text(unix: int, bias: int, now: int) -> String:
	var dt := Time.get_date_dict_from_unix_time(unix + bias)
	var y := int(Time.get_date_dict_from_unix_time(now + bias).year)
	return Lang.date_text(int(dt.day), int(dt.month), int(dt.year) if int(dt.year) != y else 0)


## Uhrzeit „21:10“ (ohne 24-Stunden-Uhr „9:10 PM“).
static func clock(unix: int, bias: int, h24 := true) -> String:
	var t := Time.get_time_dict_from_unix_time(unix + bias)
	if h24:
		return "%02d:%02d" % [t.hour, t.minute]
	var h: int = int(t.hour) % 12
	return "%d:%02d %s" % [12 if h == 0 else h, t.minute, "PM" if int(t.hour) >= 12 else "AM"]


## Die Runden eines Spiels aus sessions.json ({ id, at, secs }) als Zahlen für die Spielseite:
## { count, total, avg, longest: { secs, at }, first (Beginn der ersten), last (Ende der letzten),
##   peak (Stunde; -1 unter drei Runden), recent: die letzten CHART_N als { secs, at }, älteste
##   zuerst }. Leer ohne Runden. Uzai merkt sich insgesamt die letzten 2000 Runden – „first“ ist
## also die erste, die Uzai noch kennt.
static func per_game(sessions: Array, gid: String, bias: int) -> Dictionary:
	var mine: Array = []
	for se in sessions:
		if se is Dictionary and str(se.get("id", "")) == gid and int(se.get("secs", 0)) > 0 and int(se.get("at", 0)) > 0:
			mine.append(se)
	if mine.is_empty():
		return {}
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at) > int(b.at))
	var total := 0
	var longest: Dictionary = mine[0]
	for se in mine:
		total += int(se.secs)
		if int(se.secs) > int(longest.secs):
			longest = se
	var recent: Array = []
	for se in mine.slice(0, CHART_N):
		recent.push_front({ "secs": int(se.secs), "at": int(se.at) })
	var first: Dictionary = mine[mine.size() - 1]
	return { "count": mine.size(), "total": total, "avg": floori(float(total) / mine.size()),
		"longest": { "secs": int(longest.secs), "at": int(longest.at) },
		"first": int(first.at) - int(first.secs), "last": int(mine[0].at),
		"peak": peak_hour(mine, bias) if mine.size() >= 3 else -1, "recent": recent }


## Die Zusammenfassung einer Runde.
## round_: { game_id, title, start, end, secs, before, after } (main merkt sich das am Ende).
## unlocks: Verlauf der Erfolge (Unlocks.history, neueste zuerst); key: Schlüssel des Spiels darin
##   („steam:…“, „ra:…“, "" unbekannt). rom: Emulator-Spiel – ohne bekannte RA-Nummer zählen dann
##   alle RetroAchievements-Erfolge aus dem Zeitraum (es läuft immer nur ein Spiel).
## items: Aufnahmen des Spiels (Capture.for_game, neueste zuerst). ach: Erfolgsliste des Spiels
##   (Achievements.cached) für den Fortschritt.
## Ergebnis: { game_id, title, secs, end, after, mark, unlocks, clips, shots, newest, have, total }
static func make(round_: Dictionary, unlocks: Array, key: String, rom: bool, items: Array, ach: Dictionary) -> Dictionary:
	var from := int(round_.get("start", 0))
	var to := int(round_.get("end", 0)) + LATE_S
	var got: Array = []
	for e in unlocks:
		if not (e is Dictionary):
			continue
		var at := int(e.get("unlocked_at", 0))
		var k := str(e.get("game_key", ""))
		if at < from or at > to:
			continue
		if (key != "" and k == key) or (key == "" and rom and str(e.get("platform", "")) == "ra"):
			got.append(e)
	var clips := 0
	var shots := 0
	var newest := ""
	for it in items:
		var mt := int(it.get("mtime", 0))
		if mt < from or mt > to:
			continue
		if str(it.get("kind", "")) == "clip":
			clips += 1
		else:
			shots += 1
		if newest == "":
			newest = str(it.get("path", ""))
	var ok := not ach.has("error")
	return { "game_id": str(round_.get("game_id", "")), "title": str(round_.get("title", "")), "secs": int(round_.get("secs", 0)),
		"end": int(round_.get("end", 0)), "after": int(round_.get("after", 0)),
		"mark": milestone(int(round_.get("before", 0)), int(round_.get("after", 0))),
		"unlocks": got, "clips": clips, "shots": shots, "newest": newest,
		"have": int(ach.get("unlocked", 0)) if ok else 0, "total": int(ach.get("total", 0)) if ok else 0 }


## Ob die Karte „Gerade gespielt“ (noch) gilt: lang genug gespielt und nicht zu lange her.
static func card_due(round_: Dictionary, now: int) -> bool:
	return not round_.is_empty() and int(round_.get("secs", 0)) >= MIN_SECS and now - int(round_.get("end", 0)) < SHOW_S
