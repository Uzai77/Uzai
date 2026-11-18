extends RefCounted
## Dein Backlog (Roadmap 2): wie bei Backloggd, nur lokal. Rechnet nur – keine Knoten, kein Netz.
## Je Spiel (am Spiel in library.json, Library.USER_FIELDS – bleibt beim Einlesen und in jeder
## Sicherung):
##   status     Kennung aus STATUSES („spiele“); fehlt = kein Status
##   status_at  wann der Status gesetzt wurde (Unix-Zeit)
##   done_at    wann es durchgespielt bzw. auf 100 % kam – zählt fürs Jahresziel
##   stars      Bewertung in halben Sternen, 1 … 10 (7 = 3½ Sterne); fehlt = keine
##   review     kurze Rezension (eigener Text, wird nie übersetzt)
##   diary      Tagebuch: [{ at, secs, note }] – neueste zuerst
## Dazu, ebenfalls in library.json (Library.lists, Library.goals):
##   lists      [{ id, name, games: [Spiel-ID …] }] – eigene, sortierbare Listen
##   goals      { "2026": 12 } – so viele Spiele will ich in dem Jahr durchspielen
## Uzai setzt nie selbst einen Status: Vorschläge (suggest) stehen nur da, bis man sie annimmt.

## [Kennung, Name, Symbol]. Die Reihenfolge ist die der Abschnitte im Raster.
const STATUSES := [["spiele", "Spiele ich", "play"], ["will", "Will ich spielen", "bookmark"], ["pausiert", "Pausiert", "pause"],
	["durch", "Durchgespielt", "check"], ["voll", "100 %", "trophy"], ["abgebrochen", "Aufgegeben", "close"]]
## Zählt fürs Jahresziel.
const DONE := ["durch", "voll"]
const FIELDS := ["status", "status_at", "done_at", "stars", "review", "diary"]
const NO_STATUS := "Ohne Status"
const NO_STARS := "Ohne Bewertung"
## Filter nach Sternen: [Kennung, Name, mindestens (halbe Sterne)].
const STAR_FILTERS := [["5", "5 Sterne", 10], ["ge4", "Ab 4 Sternen", 8], ["ge3", "Ab 3 Sternen", 6], ["lt3", "Unter 3 Sternen", 0]]
const REVIEW_MAX := 600
const NOTE_MAX := 300
const DIARY_MAX := 200          ## Einträge je Spiel (die ältesten fallen weg)
const LISTS_MAX := 50
const LIST_GAMES_MAX := 500
const LIST_NAME_MAX := 40
const GOAL_MAX := 365
## Vorschläge für den Status: so lange gilt etwas als „gerade gespielt“ bzw. „liegt“.
const RECENT_DAYS := 14
const PAUSE_DAYS := 60
## Ein Tagebuch-Eintrag wird nach einer Runde erst ab dieser Länge angeboten.
const DIARY_MIN_SECS := 5 * 60

const GameFields := preload("res://src/library/game_fields.gd")
const Lang := preload("res://src/core/lang.gd")


# --- Lesen -----------------------------------------------------------------------------------

static func status_of(g: Dictionary) -> String:
	var s := str(g.get("status", ""))
	return s if s != "" and status_name(s) != "" else ""


static func status_name(s: String) -> String:
	for e in STATUSES:
		if e[0] == s:
			return str(e[1])
	return ""


static func status_icon(s: String) -> String:
	for e in STATUSES:
		if e[0] == s:
			return str(e[2])
	return "bookmark"


## Halbe Sterne 0 … 10 (0 = keine Bewertung).
static func stars_of(g: Dictionary) -> int:
	var v: Variant = g.get("stars")
	return clampi(int(v), 0, 10) if v is int or v is float else 0


## „3½ von 5“ – Text zu halben Sternen (0 = keine Bewertung).
static func stars_text(half: int) -> String:
	if half <= 0:
		return NO_STARS
	var whole := half / 2
	if half % 2 == 0:
		return "%d von 5" % whole
	return ("%d½ von 5" % whole) if whole > 0 else "½ von 5"


static func review_of(g: Dictionary) -> String:
	return str(g.get("review", "")) if g.get("review") is String else ""


## Tagebuch, neueste zuerst. Kaputte Einträge fallen weg.
static func diary_of(g: Dictionary) -> Array:
	var v: Variant = g.get("diary")
	if not (v is Array):
		return []
	# „at“ nur als Zahl (library.json kann von Hand geändert sein: int() auf einem Verzeichnis bräche hier ab,
	# und auch sanitize käme dann nicht mehr dazu, den Eintrag zu entfernen).
	return (v as Array).filter(func(e): return e is Dictionary and (e.get("at") is int or e.get("at") is float) and int(e.at) > 0)


static func done_at(g: Dictionary) -> int:
	return int(g.get("done_at", 0)) if str(g.get("status", "")) in DONE else 0


## Kurz für Kopfzeilen und Optionen: „Spiele ich · 4 von 5“.
static func summary(g: Dictionary) -> String:
	var bits := PackedStringArray()
	var s := status_of(g)
	if s != "":
		bits.append(status_name(s))
	if stars_of(g) > 0:
		bits.append(stars_text(stars_of(g)))
	return " · ".join(bits)


# --- Ändern (am Spiel; Library speichert) -----------------------------------------------------

## Status setzen ("" nimmt ihn weg). true, wenn sich etwas geändert hat. Durchgespielt/100 %
## merken sich, wann – ein Wechsel zwischen den beiden behält das Datum.
static func set_status(g: Dictionary, s: String, now: int) -> bool:
	if s != "" and status_name(s) == "":
		return false
	var old := status_of(g)
	if s == old:
		return false
	if s == "":
		for k in ["status", "status_at", "done_at"]:
			g.erase(k)
		return true
	g["status"] = s
	g["status_at"] = now
	if s in DONE:
		if not (old in DONE) or int(g.get("done_at", 0)) <= 0:
			g["done_at"] = now
	else:
		g.erase("done_at")
	return true


static func set_stars(g: Dictionary, half: int) -> bool:
	var h := clampi(half, 0, 10)
	if h == stars_of(g):
		return false
	if h == 0:
		g.erase("stars")
	else:
		g["stars"] = h
	return true


static func set_review(g: Dictionary, text: String) -> bool:
	var t := GameFields.clean_text(text, REVIEW_MAX)
	if t == review_of(g):
		return false
	if t == "":
		g.erase("review")
	else:
		g["review"] = t
	return true


## Ein Eintrag ins Tagebuch (at: wann gespielt, secs: wie lange, note: eigener Satz). Gleicher
## Zeitpunkt ersetzt den alten Eintrag (zweimal gespeichert = einmal da).
static func add_diary(g: Dictionary, at: int, secs: int, note: String) -> bool:
	if at <= 0:
		return false
	var list := diary_of(g).filter(func(e): return int(e.at) != at)
	var e := { "at": at }
	if secs > 0:
		e["secs"] = secs
	var n := GameFields.clean_text(note, NOTE_MAX)
	if n != "":
		e["note"] = n
	list.append(e)
	list.sort_custom(func(a, b): return int(a.at) > int(b.at))
	g["diary"] = list.slice(0, DIARY_MAX)
	return true


static func remove_diary(g: Dictionary, at: int) -> bool:
	var list := diary_of(g)
	var rest := list.filter(func(e): return int(e.at) != at)
	if rest.size() == list.size():
		return false
	if rest.is_empty():
		g.erase("diary")
	else:
		g["diary"] = rest
	return true


## Hat das Tagebuch für diese Runde schon einen Eintrag?
static func has_entry(g: Dictionary, at: int) -> bool:
	return diary_of(g).any(func(e): return int(e.at) == at)


# --- Viele Spiele auf einmal (Raster → Auswahl bearbeiten) -------------------------------------

## Was das Backlog an vielen Spielen auf einmal ändern kann (sonst GameFields.apply_op).
const OPS := ["status", "stars"]


static func apply_op(g: Dictionary, op: String, value: Variant, now: int) -> bool:
	match op:
		"status":
			return set_status(g, str(value), now)
		"stars":
			return set_stars(g, int(value))
	return false


## Wie viele Spiele eine Änderung wirklich träfe (für die Rückfrage), ohne etwas zu ändern.
static func op_count(list: Array, op: String, value: Variant) -> int:
	var n := 0
	for g in list:
		if apply_op((g as Dictionary).duplicate(true), op, value, 1):
			n += 1
	return n


# --- Vorschlag für den Status ------------------------------------------------------------------

## Was Uzai als Status vorschlagen würde – nur ein Vorschlag, gesetzt wird er nie von selbst.
## ach: [freigeschaltet, gesamt] oder []. { status, why } oder leer.
static func suggest(g: Dictionary, playtime: int, last: int, ach: Array, now: int) -> Dictionary:
	var s := status_of(g)
	if s == "abgebrochen":
		return {}
	if ach.size() >= 2 and int(ach[1]) > 0 and int(ach[0]) >= int(ach[1]) and s != "voll":
		return { "status": "voll", "why": "Alle %d Erfolge geholt" % int(ach[1]) }
	if s in DONE:
		return {}
	var days := (now - last) / 86400 if last > 0 else -1
	if s in ["", "will", "pausiert"] and playtime > 0 and days >= 0 and days < RECENT_DAYS:
		return { "status": "spiele", "why": "Zuletzt gespielt %s" % _days_ago(days) }
	if s == "spiele" and days >= PAUSE_DAYS:
		return { "status": "pausiert", "why": "Seit %d Tagen nicht gespielt" % days }
	return {}


static func _days_ago(d: int) -> String:
	if d <= 0:
		return "heute"
	if d == 1:
		return "gestern"
	return "vor %d Tagen" % d


# --- Was spiele ich heute? ---------------------------------------------------------------------

## Kandidaten für „Was spiele ich heute?“ mit Gewicht und Grund: [{ game, weight, why }].
## info: Spiel-ID → { playtime, last, installed } (vom Aufrufer, damit das hier ohne Library rechnet).
## Nie: durchgespielt, 100 %, abgebrochen, ausgeblendet. Gibt es Spiele mit „Spiele ich“, „Will ich
## spielen“ oder „Pausiert“, kommt der Vorschlag nur aus ihnen – sonst aus Unberührtem und lange
## Liegendem.
static func candidates(list: Array, info: Dictionary, now: int) -> Array:
	var all := _candidates(list, info, now)
	var own: Array = all.filter(func(c): return status_of(c.game) != "")
	return own if not own.is_empty() else all


static func _candidates(list: Array, info: Dictionary, now: int) -> Array:
	var out: Array = []
	for g in list:
		if bool(g.get("hidden", false)):
			continue
		var s := status_of(g)
		if s in DONE or s == "abgebrochen":
			continue
		var i: Dictionary = info.get(str(g.get("id", "")), {})
		var secs := int(i.get("playtime", 0))
		var last := int(i.get("last", 0))
		var inst := bool(i.get("installed", true))
		var days := (now - last) / 86400 if last > 0 else -1
		var w := 0.0
		var why := ""
		match s:
			"spiele":
				w = 6.0
				why = "Du spielst es gerade" + ((" · zuletzt %s" % _days_ago(days)) if days >= 0 else "")
			"will":
				w = 5.0
				why = "Steht auf deiner Liste" + (" und ist installiert" if inst else "")
			"pausiert":
				w = 3.0
				why = ("Liegt seit %d Tagen – Zeit, weiterzumachen?" % days) if days >= 7 else "Pausiert – vielleicht geht es heute weiter"
			_:
				if secs == 0 and inst:
					w = 1.5
					why = "Schon installiert und noch nie gespielt"
				elif secs > 0 and days >= 30:
					w = 1.0
					why = "Lange nicht gespielt (%s)" % _days_ago(days)
		if w <= 0.0:
			continue
		if not inst:
			w *= 0.4
			why += " · noch nicht installiert"
		if stars_of(g) >= 8:
			w *= 1.3
		out.append({ "game": g, "weight": w, "why": why })
	return out


## Ein Vorschlag aus den Kandidaten: gewichtet, mit festem Startwert (dieselben Daten und derselbe
## Wurf ergeben dasselbe Spiel). skip: Spiel-IDs, die gerade schon dran waren (Würfeln).
static func pick_today(cands: Array, seed_: int, skip: Array = []) -> Dictionary:
	var pool: Array = cands.filter(func(c): return not skip.has(str((c.game as Dictionary).get("id", ""))))
	if pool.is_empty():
		pool = cands
	if pool.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var total := 0.0
	for c in pool:
		total += float(c.weight)
	var r := rng.randf() * total
	for c in pool:
		r -= float(c.weight)
		if r <= 0.0:
			return c
	return pool[pool.size() - 1]


# --- Jahresziel -------------------------------------------------------------------------------

static func year_of(unix: int, bias := 0) -> int:
	return int(Time.get_date_dict_from_unix_time(unix + bias).year) if unix > 0 else 0


## Durchgespielt in einem Jahr: Spiele, neueste zuerst.
static func done_in(list: Array, year: int, bias := 0) -> Array:
	var out: Array = list.filter(func(g): return done_at(g) > 0 and year_of(done_at(g), bias) == year)
	out.sort_custom(func(a, b): return done_at(a) > done_at(b))
	return out


## Stand eines Jahresziels: { year, target, done, left, frac, ahead } – ahead: wie viele Spiele man
## gegenüber gleichmäßigem Tempo vorn (> 0) bzw. hinten (< 0) liegt (nur im laufenden Jahr).
static func goal_state(list: Array, year: int, target: int, now: int, bias := 0) -> Dictionary:
	var done := done_in(list, year, bias).size()
	var out := { "year": year, "target": target, "done": done, "left": maxi(0, target - done),
		"frac": clampf(float(done) / float(target), 0.0, 1.0) if target > 0 else 0.0, "ahead": 0 }
	if target > 0 and year_of(now, bias) == year:
		var start := int(Time.get_unix_time_from_datetime_dict({ "year": year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0 })) - bias
		var end := int(Time.get_unix_time_from_datetime_dict({ "year": year + 1, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0 })) - bias
		var part := clampf(float(now - start) / float(maxi(1, end - start)), 0.0, 1.0)
		out.ahead = done - floori(target * part)
	return out


## Ruhiger Satz zum Ziel („Noch 7 bis Jahresende – gut im Plan“).
static func goal_text(st: Dictionary) -> String:
	if int(st.target) <= 0:
		return ""
	if int(st.done) >= int(st.target):
		return "Ziel erreicht – alles darüber ist Zugabe."
	var left := Lang.count(int(st.left), "Spiel", "Spiele")
	var a := int(st.ahead)
	if a > 0:
		return "Noch %s – du liegst %s vorn." % [left, Lang.count(a, "Spiel", "Spiele")]
	if a < 0:
		return "Noch %s – %s hinter dem Plan, kein Grund zur Eile." % [left, Lang.count(-a, "Spiel", "Spiele")]
	return "Noch %s – genau im Plan." % left


static func clean_goals(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		var y := int(str(k)) if str(k).is_valid_int() else 0
		var n: Variant = v[k]
		if y >= 1970 and y <= 2200 and (n is int or n is float) and int(n) > 0:
			out[str(y)] = mini(int(n), GOAL_MAX)
	return out


# --- Listen -----------------------------------------------------------------------------------

## Gespeicherte Listen prüfen: nur echte Listen mit Namen und Spiel-IDs, keine doppelten.
static func clean_lists(v: Variant) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	var ids := {}
	for l in v:
		if not (l is Dictionary):
			continue
		var name := GameFields.clean_text(str(l.get("name", "")), LIST_NAME_MAX)
		var id := str(l.get("id", ""))
		if name == "" or id == "" or ids.has(id):
			continue
		ids[id] = true
		var games: Array = []
		var seen := {}
		var raw: Variant = l.get("games", [])
		for gid in (raw if raw is Array else []):
			var s := str(gid)
			if s != "" and not seen.has(s) and games.size() < LIST_GAMES_MAX:
				seen[s] = true
				games.append(s)
		out.append({ "id": id, "name": name, "games": games })
		if out.size() >= LISTS_MAX:
			break
	return out


static func new_list(lists: Array, name: String, now: int) -> Dictionary:
	var n := GameFields.clean_text(name, LIST_NAME_MAX)
	if n == "" or lists.size() >= LISTS_MAX:
		return {}
	var id := "l_" + ("%s%d" % [n, now]).md5_text().substr(0, 8)
	var l := { "id": id, "name": n, "games": [] }
	lists.append(l)
	return l


static func list_by_id(lists: Array, id: String) -> Dictionary:
	for l in lists:
		if str(l.get("id", "")) == id:
			return l
	return {}


## Spiel in eine Liste (ans Ende) bzw. heraus. true, wenn sich etwas geändert hat.
static func list_toggle(l: Dictionary, gid: String, on: bool) -> bool:
	var games: Array = l.get("games", [])
	if on == games.has(gid):
		return false
	if on:
		if games.size() >= LIST_GAMES_MAX:
			return false
		games.append(gid)
	else:
		games.erase(gid)
	l["games"] = games
	return true


## Ein Spiel in der Liste um einen Platz verschieben (dir -1 nach vorn, +1 nach hinten).
static func list_move(l: Dictionary, gid: String, dir: int) -> bool:
	var games: Array = l.get("games", [])
	var i := games.find(gid)
	var j := i + dir
	if i < 0 or j < 0 or j >= games.size():
		return false
	games[i] = games[j]
	games[j] = gid
	return true


static func lists_with(lists: Array, gid: String) -> Array:
	return lists.filter(func(l): return (l.get("games", []) as Array).has(gid))


# --- Filter und Abschnitte (game_filter.gd) ---------------------------------------------------

## Passt das Spiel zum Status-Filter? "?" = ohne Status.
static func status_matches(g: Dictionary, f: String) -> bool:
	return status_of(g) == ("" if f == "?" else f)


static func stars_match(g: Dictionary, f: String) -> bool:
	var h := stars_of(g)
	match f:
		"?": return h == 0
		"lt3": return h > 0 and h < 6
	for e in STAR_FILTERS:
		if e[0] == f:
			return h >= int(e[2])
	return true


static func star_filter_name(f: String) -> String:
	if f == "?":
		return NO_STARS
	for e in STAR_FILTERS:
		if e[0] == f:
			return str(e[1])
	return ""


# --- Laden ------------------------------------------------------------------------------------

## Beim Laden: nur, was zu den Feldern passt (library.json kann von Hand geändert sein).
static func sanitize(g: Dictionary) -> void:
	if g.has("status") and status_of(g) == "":
		for k in ["status", "status_at", "done_at"]:
			g.erase(k)
	for k in ["status_at", "done_at"]:
		if g.has(k):
			if g[k] is int or g[k] is float:
				g[k] = int(g[k])
			else:
				g.erase(k)
	if g.has("done_at") and not (str(g.get("status", "")) in DONE):
		g.erase("done_at")
	if g.has("stars"):
		var h := stars_of(g)
		if h <= 0:
			g.erase("stars")
		else:
			g["stars"] = h
	if g.has("review"):
		var r := GameFields.clean_text(review_of(g), REVIEW_MAX)
		if r == "":
			g.erase("review")
		else:
			g["review"] = r
	if g.has("diary"):
		var out: Array = []
		for e in diary_of(g):
			var x := { "at": int(e.at) }
			if (e.get("secs") is int or e.get("secs") is float) and int(e.secs) > 0:
				x["secs"] = int(e.secs)
			var n := GameFields.clean_text(str(e.get("note", "")), NOTE_MAX)
			if n != "":
				x["note"] = n
			out.append(x)
		out.sort_custom(func(a, b): return int(a.at) > int(b.at))
		if out.is_empty():
			g.erase("diary")
		else:
			g["diary"] = out.slice(0, DIARY_MAX)

