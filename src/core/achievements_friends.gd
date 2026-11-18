extends Node
## Erfolge von Freunden – nur anzeigen, nie speichern. Hängt als Kind an Achievements
## (Achievements.friends) und kennt drei Fragen:
##   board(g)   – wer von deinen Freunden ist in diesem Spiel wie weit (und wer hat welchen Erfolg),
##   feed()     – was Freunde in den letzten Tagen freigeschaltet haben,
##   weekly()   – Rangliste der Woche daraus (du mitgezählt); bei RetroAchievements dazu die Punkte.
## Wege sind nur die, die Uzai schon hat: Steam-Web-API mit dem Zugang aus der QR-Anmeldung bzw.
## dem eigenen Schlüssel (GetPlayerAchievements, GetRecentlyPlayedGames – Steam antwortet nur bei
## öffentlichen Profilen; privat heißt privat); lehnt die Web-API den Zugang ab (HTTP 400), Steams
## Chat-Server wie der Vergleich in der Steam-App (ClientGetUserStats je Freund, zuletzt gespielt
## aus Player.GetOwnedGames#1 – siehe steam_erfolge.gd) und RetroAchievements über die Nutzer, denen man
## folgt (API_GetUsersIFollow, API_GetGameInfoAndUserProgress mit u=, API_GetUserRecentAchievements).
## Alles liegt TTL Sekunden im Arbeitsspeicher; nur der Feed (das, was die Seite „Freunde“ zeigt) liegt
## dazu je Profil in FEED_FILE, damit die Seite beim nächsten Öffnen sofort etwas zeigt (höchstens
## FEED_ALT alt, beim Lesen geprüft wie fremde Daten) – dann wird er im Hintergrund erneuert.
## Laden: Steam und RetroAchievements gleichzeitig, je Welle zeigt die Seite, was schon da ist
## (updated „feed_teil“), und nach FEED_FRIST steht der Feed mit dem, was da ist (früher wartete
## die Seite auf jede Antwort nacheinander – bis zu einer Minute). Fremde Werte werden auf Typ,
## Länge und Zeichen geprüft (sane). Höchstens MAX_FRIENDS Freunde je Frage, Abfragen in Wellen zu
## WAVE, bei Drosselung (429) für eine Weile Schluss. Kein Abruf beim Start – erst, wenn jemand den
## Reiter „Freunde“ oder ein Spiel öffnet. Reine Teile (static) prüft tests/logic_erfolge_freunde.gd.

signal updated(what: String)
signal _part_done

const Ach := preload("res://src/core/achievements.gd")
const SocialS := preload("res://src/core/social.gd")
const UnlocksS := preload("res://src/core/unlocks.gd")
const SE := preload("res://src/core/steam_erfolge.gd")
const U := preload("res://src/ui/u.gd")
const Fremd := preload("res://src/core/fremd.gd")

const STEAM := "https://api.steampowered.com/"
const TTL := 900                ## Sekunden, die ein Stand im Arbeitsspeicher gilt
const MAX_FRIENDS := 8          ## Freunde je Frage
const WAVE := 4                 ## Abfragen gleichzeitig
const FEED_DAYS := 7
const FEED_GAMES := 3           ## zuletzt gespielte Spiele je Freund im Feed
const FEED_PAIRS := 16          ## Freund-Spiel-Paare im Feed (Steam)
const FEED_RESOLVE := 6         ## Spiele, deren Erfolgsliste der Feed eigens lädt
const FEED_MAX := 40
const NAME_MAX := 32
const TEXT_MAX := 120
const PAUSE_AFTER_429 := 180    ## Sekunden Ruhe nach einer Drosselung
const FEED_FRIENDS := 12        ## Freunde, die der Feed fragt
const FEED_FILE := "cache/freunde_feed.json"   ## je Profil (profiles.gd OWN_FILES)
const FEED_ALT := 3 * 86400     ## so alt darf der gemerkte Feed sein, um sofort zu stehen
const FEED_FRIST := 20.0        ## länger wartet der Feed nicht (s); Spätere kommen noch dazu
const TEIL_TAKT_MS := 700       ## Teilergebnisse höchstens so oft an die Seite
const LUECKE_NEU := 60          ## Sekunden, nach denen ein Feed mit fehlenden Antworten neu gefragt wird

var demo := false
var paused_until := 0           ## nach einer Drosselung: bis dahin keine Abfragen (Unix)
var _boards := {}               # Spielschlüssel -> { at, data }
var _feed := {}                 # { at, list }
var _follow := {}               # { at, list }  RetroAchievements: wem du folgst
var _busy := {}                 # Schlüssel -> true (läuft gerade)
var _teil: Array = []           # Feed-Einträge, die beim Laden schon da sind
var _feed_gen := 0              # Lauf des Feeds (späte Antworten alter Läufe zählen nicht)
var _gemerkt := false           # FEED_FILE schon gelesen
var _teil_ms := 0
var _feed_luecke := false       # dem laufenden Feed fehlen Antworten (kein Netz, Drosselung, Frist)
var _feed_ruhe_bis := 0         # nach einem Feed mit Lücke: bis dahin nicht neu fragen (Unix)


func _ready() -> void:
	demo = "--demo" in OS.get_cmdline_user_args()


# --- Reine Teile ---------------------------------------------------------------------------------

## Fremder Text: ohne Steuerzeichen, gekürzt. Namen höchstens NAME_MAX, Titel TEXT_MAX Zeichen.
static func sane(v: Variant, max_len := TEXT_MAX) -> String:
	if not (v is String or v is StringName or v is int or v is float):
		return ""
	return Fremd.sauber(str(v)).replace("\t", "").replace("\n", "").replace("\r", "").left(max_len).strip_edges()


## Schlüssel eines Spiels: "steam:<App-ID>" oder "ra:<Spiel-ID>" ("" ohne Quelle).
static func key_of(g: Dictionary) -> String:
	var ra := int(g.get("_ra_id", g.get("ra_id", g.get("game_id", 0))))
	var app := int(g.get("_appid", g.get("appid", 0)))
	if str(g.get("source", "")) == "steam" and app > 0:
		return "steam:%d" % app
	if ra > 0 and str(g.get("source", "")) != "steam":
		return "ra:%d" % ra
	if app > 0:
		return "steam:%d" % app
	return ""


## Welche Freunde gefragt werden, in dieser Reihenfolge: wer gerade dieses Spiel spielt, dann wer
## spielt, dann wer online ist, dann die zuletzt Gesehenen. Höchstens max_n. Nur Steam-Freunde
## mit gültiger ID (17 Ziffern).
static func candidates(friends: Array, appid: int, max_n := MAX_FRIENDS, pin := "") -> Array:
	var list: Array = []
	for f in friends:
		if not (f is Dictionary):
			continue
		var id := str(f.get("id", ""))
		if not id.is_valid_int() or id.length() < 16 or id.length() > 20:
			continue
		list.append(f)
	list.sort_custom(func(a, b):
		var ra := _rank_of(a, appid, pin)
		var rb := _rank_of(b, appid, pin)
		if ra != rb:
			return ra < rb
		return int(a.get("last", 0)) > int(b.get("last", 0))
	)
	return list.slice(0, max_n)


static func _rank_of(f: Dictionary, appid: int, pin: String) -> int:
	if pin != "" and str(f.get("id", "")) == pin:
		return 0
	var st := str(f.get("state", "offline"))
	if st == "game" and appid > 0 and str(f.get("game_id", "")) == str(appid):
		return 1
	if st == "game":
		return 2
	if st != "offline":
		return 3
	return 4


## GetPlayerAchievements eines Freundes: { ok, reason, got: { api: Unix-Zeit }, total, last }.
## Nicht öffentlich (403, „not public“): reason; Spiel ohne Statistik (400): wie „nichts“.
static func parse_steam_friend(r: Dictionary) -> Dictionary:
	var out := { "ok": false, "reason": "", "got": {}, "total": 0, "last": 0 }
	var code := int(r.get("code", 0))
	var data: Variant = r.get("data")
	var ps: Dictionary = data.playerstats if data is Dictionary and data.get("playerstats") is Dictionary else {}
	var err := str(ps.get("error", "")).to_lower()
	if code == 429:
		out.reason = "Steam bremst gerade."
		out["throttled"] = true
		return out
	if code == 403 or err.contains("not public"):
		out.reason = "Profil privat"
		return out
	if not bool(r.get("ok", false)) or ps.is_empty() or not bool(ps.get("success", true)):
		out.reason = "Nicht sichtbar" if code != 0 else "Keine Antwort"
		if code == 400 or err.contains("no stats"):
			out.reason = "Keine Erfolge"
		return out
	var list: Variant = ps.get("achievements", [])
	if not (list is Array):
		out.reason = "Nicht sichtbar"
		return out
	out.ok = true
	for a in list:
		if not (a is Dictionary):
			continue
		out.total += 1
		if int(a.get("achieved", 0)) == 1:
			var api := sane(a.get("apiname", ""), 128)
			if api == "":
				continue
			var at := maxi(0, int(a.get("unlocktime", 0)))
			out.got[api] = at
			out.last = maxi(int(out.last), at)
	return out


## Nur Namen, wie RetroAchievements sie vergibt (2–32 Zeichen: Buchstaben, Ziffern, _ . -) – sie
## gehen als Abfrage-Parameter wieder hinaus.
static func ra_name_ok(name: String) -> bool:
	return name.length() >= 2 and name.length() <= 32 \
		and Ach._only(name, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")


## API_GetUsersIFollow: [{ id, name, avatar, points, soft }] – id ist bei RetroAchievements der Name.
static func parse_ra_following(data: Variant) -> Array:
	var out: Array = []
	var rows: Variant = data.get("Results", []) if data is Dictionary else data
	if not (rows is Array):
		return out
	for u in rows:
		if not (u is Dictionary):
			continue
		var name := sane(u.get("User", ""), NAME_MAX)
		if not ra_name_ok(name):
			continue
		var pic := sane(u.get("AvatarUrl", ""), 200)
		if pic != "" and not pic.begins_with("https://"):
			pic = ""
		if pic == "":
			pic = "%s/UserPic/%s.png" % [Ach.RA_MEDIA, name]
		out.append({ "id": name, "name": name, "avatar": pic, "points": maxi(0, int(u.get("Points", 0))),
			"soft": maxi(0, int(u.get("PointsSoftcore", 0))), "state": "" })
	return out


## API_GetGameInfoAndUserProgress mit u=Freund: { ok, got: { id: Unix-Zeit }, total, count, last }.
static func parse_ra_friend(data: Variant) -> Dictionary:
	var out := { "ok": false, "reason": "Keine Antwort", "got": {}, "total": 0, "count": 0, "last": 0 }
	if not (data is Dictionary):
		return out
	var achs: Variant = (data as Dictionary).get("Achievements", {})
	if not (achs is Dictionary):
		return out
	out.ok = true
	out.reason = ""
	for k in achs.keys():
		var a: Variant = achs[k]
		if not (a is Dictionary):
			continue
		out.total += 1
		var hc := str(a.get("DateEarnedHardcore", "")) if a.get("DateEarnedHardcore") != null else ""
		var sc := str(a.get("DateEarned", "")) if a.get("DateEarned") != null else ""
		if hc == "" and sc == "":
			continue
		var at := Ach._ra_date(hc if hc != "" else sc)
		out.got[sane(a.get("ID", k), 32)] = at
		out.count += 1
		out.last = maxi(int(out.last), at)
	return out


## Wer von den Freunden einen Erfolg hat: Namen (höchstens max_n), nach Zeit, neueste zuerst.
static func who_has(rows: Array, api: String, max_n := 6) -> Array:
	var hits: Array = []
	for r in rows:
		if not (r is Dictionary) or not bool(r.get("ok", false)):
			continue
		var got: Dictionary = r.get("got", {})
		if got.has(api):
			hits.append([int(got[api]), str(r.get("name", ""))])
	hits.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	var out: Array = []
	for h in hits.slice(0, max_n):
		out.append(str(h[1]))
	return out


## Zeit der letzten Freischaltung dieses Erfolgs unter den Freunden (0: keine).
static func latest_of(rows: Array, api: String) -> int:
	var best := 0
	for r in rows:
		if r is Dictionary and bool(r.get("ok", false)):
			best = maxi(best, int((r.get("got", {}) as Dictionary).get(api, 0)))
	return best


## Der Satz zu einem Erfolg: „Nur du“, „Du und Mira“, „Du, Mira und 2 weitere“ – offen:
## „Mira hat das gestern freigeschaltet“, „Mira und Jonas haben das schon“.
## Ohne Freund mit dem Erfolg und ohne eigenen: "" (dann sagt die Seltenheit etwas).
static func who_text(names: Array, mine: bool, when_text := "") -> String:
	var n := names.size()
	if mine:
		if n == 0:
			return "Nur du"
		if n == 1:
			return "Du und %s" % str(names[0])
		if n == 2:
			return "Du, %s und %s" % [str(names[0]), str(names[1])]
		return "Du, %s und %d weitere" % [str(names[0]), n - 1]
	if n == 0:
		return ""
	if n == 1:
		if when_text != "":
			return "%s hat das %s freigeschaltet" % [str(names[0]), when_text]
		return "%s hat das schon" % str(names[0])
	if n == 2:
		return "%s und %s haben das schon" % [str(names[0]), str(names[1])]
	return "%s und %d weitere haben das schon" % [str(names[0]), n - 1]


## „gestern“, „heute“, „vor 3 Tagen“, sonst das Datum – klein geschrieben für den Satz.
static func when_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var a: String = U.ago(unix)
	if a == "Gerade eben":
		return "gerade eben"
	if a in ["Heute", "Gestern"] or a.begins_with("Vor "):
		return a.substr(0, 1).to_lower() + a.substr(1)
	return "am " + a if a != "" else ""


## Rangliste je Spiel: [{ id, name, avatar, count, total, me, rank }], meiste zuerst, gleiche Zahl
## gleicher Rang. Nur Freunde, deren Stand sichtbar ist; du stehst immer drin.
static func ranking(rows: Array, me: Dictionary) -> Array:
	var list: Array = []
	var mine := me.duplicate()
	mine["me"] = true
	list.append(mine)
	for r in rows:
		if r is Dictionary and bool(r.get("ok", false)):
			list.append({ "id": str(r.get("id", "")), "name": str(r.get("name", "")), "avatar": str(r.get("avatar", "")),
				"state": str(r.get("state", "")), "count": int(r.get("count", 0)), "total": int(r.get("total", me.get("total", 0))), "me": false,
				"last": int(r.get("last", 0)) })
	return _raenge(list)


## Meiste zuerst (bei gleicher Zahl du vor den anderen, dann nach Namen); gleiche Zahl heißt gleicher Rang.
static func _raenge(list: Array) -> Array:
	list.sort_custom(func(a, b):
		if int(a.count) != int(b.count):
			return int(a.count) > int(b.count)
		if bool(a.me) != bool(b.me):
			return bool(a.me)
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)
	var rank := 0
	var last := -1
	for i in list.size():
		if int(list[i].count) != last:
			rank = i + 1
			last = int(list[i].count)
		list[i]["rank"] = rank
	return list


## Rangliste der Woche aus dem Feed: wer hat in den letzten FEED_DAYS Tagen wie viel freigeschaltet.
## me_dates: die eigenen Zeiten; me: { id, name, avatar }.
static func weekly(feed: Array, me_dates: Array, me: Dictionary, now: int) -> Array:
	var since := now - FEED_DAYS * 86400
	var per := {}
	for e in feed:
		if not (e is Dictionary) or int(e.get("date", 0)) < since:
			continue
		var fid := str(e.get("friend_id", ""))
		if fid == "":
			continue
		if not per.has(fid):
			per[fid] = { "id": fid, "name": str(e.get("friend", "")), "avatar": str(e.get("avatar", "")), "count": 0, "me": false,
				"source": str(e.get("source", "")), "last": 0 }
		per[fid].count += 1
		per[fid].last = maxi(int(per[fid].last), int(e.get("date", 0)))
	var mine := 0
	var mine_last := 0
	for d in me_dates:
		if int(d) >= since:
			mine += 1
			mine_last = maxi(mine_last, int(d))
	var list: Array = per.values()
	list.append({ "id": str(me.get("id", "me")), "name": str(me.get("name", "Du")), "avatar": str(me.get("avatar", "")), "count": mine, "me": true,
		"source": "", "last": mine_last })
	return _raenge(list)


## Als Nächstes greifbar: offene, nicht geheime Erfolge, die die meisten Spieler haben (ab
## min_pct, Standard: die Stufe „häufig“), über alle geladenen Listen, häufigste zuerst, höchstens
## per_game je Spiel. Format wie die Erfolgskarten (title, desc, game, icon, rarity, source,
## appid, game_id, id).
static func reachable(lists: Array, limit := 8, per_game := 2, min_pct := 35.0) -> Array:
	var all: Array = []
	for res in lists:
		if not (res is Dictionary) or res.has("error"):
			continue
		var src := str(res.get("source", "steam"))
		var gk := "%s:%d" % [src, int(res.get("ra_id", 0)) if src == "ra" else int(res.get("appid", 0))]
		for a in res.get("list", []):
			if not (a is Dictionary) or bool(a.get("unlocked", false)) or bool(a.get("hidden", false)):
				continue
			var pct := float(a.get("rarity", -1.0))
			if pct < min_pct:
				continue
			all.append({ "id": str(a.get("id", "")), "title": str(a.get("title", "")), "desc": str(a.get("desc", "")), "game": str(res.get("title", "")),
				"icon": str(a.get("icon_locked", a.get("icon", ""))), "icon_open": str(a.get("icon", "")), "rarity": pct, "source": src,
				"appid": int(res.get("appid", 0)), "game_id": int(res.get("ra_id", 0)), "points": int(a.get("points", 0)), "gk": gk, "date": 0,
				"hardcore": false })
	all.sort_custom(func(x, y): return float(x.rarity) > float(y.rarity))
	var out: Array = []
	var per := {}
	for a in all:
		var n := int(per.get(a.gk, 0))
		if n >= per_game:
			continue
		per[a.gk] = n + 1
		out.append(a)
		if out.size() >= limit:
			break
	return out


## Feed zusammenführen: nach Zeit, nur die letzten FEED_DAYS Tage, nichts doppelt, höchstens max_n.
static func merge_feed(parts: Array, now: int, max_n := FEED_MAX) -> Array:
	var since := now - FEED_DAYS * 86400
	var seen := {}
	var out: Array = []
	for p in parts:
		for e in p:
			if not (e is Dictionary) or int(e.get("date", 0)) < since or int(e.get("date", 0)) > now + 3600:
				continue
			var k := "%s|%s|%s" % [e.get("friend_id", ""), e.get("gk", ""), e.get("id", "")]
			if seen.has(k):
				continue
			seen[k] = true
			out.append(e)
	out.sort_custom(func(a, b): return int(a.date) > int(b.date))
	return out.slice(0, max_n)


## Ist ein Stand noch frisch?
static func fresh(entry: Dictionary, now: int, ttl := TTL) -> bool:
	return not entry.is_empty() and now - int(entry.get("at", 0)) < ttl


## Blieb diese Abfrage ohne brauchbare Antwort, ohne dass der Dienst „nein“ gesagt hat (kein Netz, Drosselung,
## Störung dort)? Dann fehlt dem Feed etwas, und der Stand davor darf nicht als überholt gelten.
static func ausgefallen(r: Dictionary) -> bool:
	var code := int(r.get("code", 0))
	return not bool(r.get("ok", false)) and (code == 0 or code == 429 or code >= 500)


# --- Stand je Spiel ---------------------------------------------------------------------------------

## Was schon da ist, ohne zu fragen ({} wenn nichts).
func board_cached(g: Dictionary) -> Dictionary:
	var hit: Dictionary = _boards.get(key_of(g), {})
	return hit.get("data", {}) if not hit.is_empty() else {}


## Wer von deinen Freunden ist in diesem Spiel wie weit. pin: dieser Freund zuerst.
## { ok, key, source, total, rows: [{ id, name, avatar, state, ok, reason, count, got, last }],
##   hidden: wie viele Freunde nichts zeigen, error, at }
func board(g: Dictionary, force := false, pin := "") -> Dictionary:
	var key := key_of(g)
	if key == "":
		return { "ok": false, "key": "", "rows": [], "error": "Für dieses Spiel gibt es keine Erfolge.", "at": 0 }
	var now := int(Time.get_unix_time_from_system())
	var hit: Dictionary = _boards.get(key, {})
	if not force and fresh(hit, now) and (pin == "" or _has_row(hit.data, pin)):
		return hit.data
	var bk := "board:" + key
	if _busy.has(bk):
		while _busy.has(bk):
			await updated
		var da: Dictionary = (_boards.get(key, {}) as Dictionary).get("data", {})
		# Der Lauf, auf den gewartet wurde, kannte den gewünschten Freund vielleicht nicht: dann einmal für ihn.
		if pin == "" or _has_row(da, pin):
			return da
	_busy[bk] = true
	var out: Dictionary
	if demo:
		await get_tree().create_timer(0.35).timeout
		out = _demo_board(key, pin)
	elif key.begins_with("steam:"):
		out = await _board_steam(int(key.get_slice(":", 1)), pin, now)
	else:
		out = await _board_ra(int(key.get_slice(":", 1)), pin, now)
	out["key"] = key
	out["at"] = int(Time.get_unix_time_from_system())
	_boards[key] = { "at": out.at, "data": out }
	Config.cap(_boards, 40)
	_busy.erase(bk)
	updated.emit(bk)
	return out


static func _has_row(b: Dictionary, id: String) -> bool:
	for r in b.get("rows", []):
		if str(r.get("id", "")) == id:
			return true
	return false


func _board_steam(appid: int, pin: String, now: int) -> Dictionary:
	var out := { "ok": false, "source": "steam", "total": 0, "rows": [], "hidden": 0, "error": "" }
	if not Social.has_steam():
		out.error = "Kein Steam-Konto verbunden."
		return out
	if now < paused_until:
		out.error = "Steam bremst gerade. Gleich noch einmal."
		return out
	var cands := candidates(Social.steam_friends, appid, MAX_FRIENDS, pin)
	if cands.is_empty():
		out.error = "Keine Steam-Freunde in der Liste."
		return out
	if not Achievements.steam_web_ok():
		return await _board_steam_cm(appid, cands, out)
	var i := 0
	while i < cands.size():
		var chunk: Array = cands.slice(i, i + WAVE)
		var urls := {}
		for f in chunk:
			urls[str(f.id)] = STEAM + "ISteamUserStats/GetPlayerAchievements/v1/?" + await Social.steam_query({ "appid": appid, "steamid": str(f.id) })
		var box := await _parts(urls)
		if i == 0 and _refused_all(box, chunk):
			return await _board_steam_cm(appid, cands, out)
		var throttled := false
		for f in chunk:
			var p := parse_steam_friend(box.get(str(f.id), {}))
			if bool(p.get("throttled", false)):
				throttled = true
			out.rows.append(_row(f, p))
			if bool(p.ok):
				out.total = maxi(int(out.total), int(p.total))
			else:
				out.hidden += 1
		if throttled:
			paused_until = int(Time.get_unix_time_from_system()) + PAUSE_AFTER_429
			break
		i += WAVE
		if i < cands.size():
			await get_tree().create_timer(0.15).timeout
	out.ok = out.rows.any(func(r): return bool(r.ok))
	if not out.ok and out.error == "":
		out.error = "Von deinen Freunden zeigt hier niemand seine Erfolge – Steam zeigt sie nur bei öffentlichen Spieldetails."
	return out


## Hat die Web-API alle Abfragen dieser Welle abgelehnt (HTTP 400 ohne Angabe von Steam – so lehnt
## sie den Zugang der QR-Anmeldung ab)? Dann merkt Achievements das, und es geht ohne sie weiter.
func _refused_all(box: Dictionary, chunk: Array) -> bool:
	var code := 0
	for f in chunk:
		var r: Dictionary = box.get(str(f.id), {})
		var ps: Variant = r.get("data").get("playerstats") if r.get("data") is Dictionary else null
		if bool(r.get("ok", false)) or (ps is Dictionary and str(ps.get("error", "")) != ""):
			return false
		code = int(r.get("code", 0))
	return not chunk.is_empty() and Achievements._web_refused(code)


## Vergleich über Steams Chat-Server (ClientGetUserStats je Freund, auf Knopfdruck). Namen der
## Erfolge aus deinem Schema am PC, sonst aus der Antwort.
func _board_steam_cm(appid: int, cands: Array, out: Dictionary) -> Dictionary:
	var sid := await Social.steam_id()
	var dir := Achievements._local_stats_dir()
	var hint: Dictionary = SE.local_game(dir, SE.account_id(sid), appid).bits if dir != "" else {}
	var pairs: Array = cands.map(func(f): return [appid, str(f.id)])
	var r: Dictionary = await SteamCM.user_stats(str(Config.get_value("accounts.steam_chat_refresh", "")), pairs, true)
	if (r.results as Dictionary).is_empty():
		out.error = "Steam antwortet gerade nicht. Später nochmal versuchen."
		SteamChat.diag_log("erfolge-freunde", "cm0:%d" % appid, "Erfolge der Freunde (App %d): Web-API abgelehnt → Chat-Server ohne Antwort" % appid)
		return out
	for f in cands:
		var body: Variant = (r.results as Dictionary).get("%d:%s" % [appid, str(f.id)])
		var us: Dictionary = SE.parse_user_stats(body, hint) if body is PackedByteArray else {}
		if hint.is_empty() and not (us.get("bits", {}) as Dictionary).is_empty():
			hint = us.bits
		var p := SE.friend_result(us)
		out.rows.append(_row(f, p))
		if bool(p.ok):
			out.total = maxi(int(out.total), int(p.total))
		else:
			out.hidden += 1
	out.ok = out.rows.any(func(row): return bool(row.ok))
	if not out.ok and out.error == "":
		out.error = "Von deinen Freunden zeigt hier niemand seine Erfolge – Steam zeigt sie nur bei öffentlichen Spieldetails."
	var shown: int = out.rows.filter(func(row): return bool(row.ok)).size()
	SteamChat.diag_log("erfolge-freunde", "cm:%d:%d" % [appid, shown],
			"Erfolge der Freunde (App %d): Web-API abgelehnt → Chat-Server, %d von %d sichtbar" % [appid, shown, cands.size()])
	return out


func _row(f: Dictionary, p: Dictionary) -> Dictionary:
	return { "id": str(f.get("id", "")), "name": sane(f.get("name", ""), NAME_MAX), "avatar": str(f.get("avatar", "")), "state": str(f.get("state", "")),
		"ok": bool(p.get("ok", false)), "reason": str(p.get("reason", "")), "count": (p.get("got", {}) as Dictionary).size(), "got": p.get("got", {}),
		"total": int(p.get("total", 0)), "last": int(p.get("last", 0)) }


func _board_ra(ra_id: int, pin: String, now: int) -> Dictionary:
	var out := { "ok": false, "source": "ra", "total": 0, "rows": [], "hidden": 0, "error": "" }
	if not Achievements.has_ra():
		out.error = "RetroAchievements ist nicht verbunden."
		return out
	if now < paused_until:
		out.error = "RetroAchievements bremst gerade. Gleich noch einmal."
		return out
	var fl := await following()
	if fl.is_empty():
		out.error = "Du folgst auf retroachievements.org noch niemandem."
		return out
	var cands: Array = fl.duplicate()
	if pin != "":
		cands.sort_custom(func(a, b): return str(a.id) == pin and str(b.id) != pin)
	cands = cands.slice(0, MAX_FRIENDS)
	var i := 0
	while i < cands.size():
		var chunk: Array = cands.slice(i, i + WAVE)
		var urls := {}
		for f in chunk:
			urls[str(f.id)] = Achievements._ra_url("API_GetGameInfoAndUserProgress.php", { "g": ra_id, "u": str(f.id) })
		var box := await _parts(urls)
		var throttled := false
		for f in chunk:
			var r: Dictionary = box.get(str(f.id), {})
			if int(r.get("code", 0)) == 429:
				throttled = true
			var p := parse_ra_friend(r.get("data") if bool(r.get("ok", false)) else null)
			out.rows.append(_row(f, p))
			if bool(p.ok):
				out.total = maxi(int(out.total), int(p.total))
			else:
				out.hidden += 1
		if throttled:
			paused_until = int(Time.get_unix_time_from_system()) + PAUSE_AFTER_429
			break
		i += WAVE
		if i < cands.size():
			await get_tree().create_timer(0.2).timeout
	out.ok = out.rows.any(func(r): return bool(r.ok))
	if not out.ok and out.error == "":
		out.error = "RetroAchievements antwortet gerade nicht."
	return out


func following_cached() -> Array:
	return _follow.get("list", [])


## RetroAchievements: wem du folgst (TTL zwischengespeichert). [{ id, name, avatar, points, soft }]
func following(force := false) -> Array:
	var now := int(Time.get_unix_time_from_system())
	if not force and fresh(_follow, now, TTL * 4):
		return _follow.list
	if demo:
		_follow = { "at": now, "list": _demo_following() }
		return _follow.list
	if not Achievements.has_ra():
		return []
	if _busy.has("follow"):
		# Läuft schon (die Seite baut sich beim Laden öfter neu): nicht noch einmal fragen.
		while _busy.has("follow"):
			await get_tree().process_frame
		return _follow.get("list", [])
	_busy["follow"] = true
	var r := await Net.get_json(Achievements._ra_url("API_GetUsersIFollow.php", { "c": 100 }))
	_busy.erase("follow")
	if not r.ok:
		if int(r.get("code", 0)) == 429:
			paused_until = now + PAUSE_AFTER_429
		return _follow.get("list", [])
	_follow = { "at": now, "list": parse_ra_following(r.data) }
	updated.emit("follow")
	return _follow.list


# --- Feed -------------------------------------------------------------------------------------------

## Was die Seite jetzt zeigen kann: der letzte Stand (auch von der Platte), beim Laden mit dem,
## was schon angekommen ist.
func feed_cached() -> Array:
	_gemerkt_laden()
	if _teil.is_empty():
		return _feed.get("list", [])
	return merge_feed([_teil, _feed.get("list", [])], int(Time.get_unix_time_from_system()))


## Gibt es schon etwas zu zeigen (auch leer, auch ein älterer Stand)?
func feed_ready() -> bool:
	_gemerkt_laden()
	return not _feed.is_empty() or not _teil.is_empty()


## Ist der Stand frisch (sonst lädt die Seite im Hintergrund neu)? Nach einem Lauf mit fehlenden Antworten
## gilt er LUECKE_NEU Sekunden als frisch, damit die Seite nicht bei jedem Aufbau neu fragt.
func feed_frisch() -> bool:
	var now := int(Time.get_unix_time_from_system())
	return fresh(_feed, now) or now < _feed_ruhe_bis


## Dem Lauf gen fehlt eine Antwort (siehe ausgefallen).
func _luecke(gen: int) -> void:
	if gen == _feed_gen:
		_feed_luecke = true


func feed_loading() -> bool:
	return _busy.has("feed")


## Der gemerkte Feed (FEED_FILE): Liste geprüfter Einträge oder [] (zu alt, kaputt, fremd).
static func gemerkt_lesen(v: Variant, now: int) -> Dictionary:
	if not (v is Dictionary) or not (v.get("list") is Array):
		return {}
	var at := int(v.get("at", 0)) if (v.get("at") is int or v.get("at") is float) else 0
	if at <= 0 or now - at > FEED_ALT or at > now + 3600:
		return {}
	var out: Array = []
	for e in v.list:
		if out.size() >= FEED_MAX:
			break
		var c := eintrag_pruefen(e)
		if not c.is_empty():
			out.append(c)
	return { "at": at, "list": merge_feed([out], now) }


## Ein Feed-Eintrag von der Platte: nur bekannte Felder, Typen und Längen wie beim Abruf.
static func eintrag_pruefen(e: Variant) -> Dictionary:
	if not (e is Dictionary):
		return {}
	var src := str(e.get("source", ""))
	if not src in ["steam", "ra"]:
		return {}
	var num := func(k: String) -> int: return int(e.get(k, 0)) if (e.get(k) is int or e.get(k) is float) else 0
	var bild := func(k: String) -> String:
		var u := sane(e.get(k, ""), 400)
		return u if u.begins_with("https://") else ""
	var out := { "source": src, "friend_id": sane(e.get("friend_id", ""), 40), "friend": sane(e.get("friend", ""), NAME_MAX),
		"avatar": bild.call("avatar"), "id": sane(e.get("id", ""), 128), "title": sane(e.get("title", ""), TEXT_MAX),
		"desc": sane(e.get("desc", ""), 240), "game": sane(e.get("game", ""), TEXT_MAX), "icon": bild.call("icon"),
		"appid": maxi(0, num.call("appid")), "game_id": maxi(0, num.call("game_id")), "date": maxi(0, num.call("date")),
		"rarity": clampf(float(e.get("rarity", -1.0)) if (e.get("rarity") is float or e.get("rarity") is int) else -1.0, -1.0, 100.0),
		"points": clampi(num.call("points"), 0, 10000), "hardcore": e.get("hardcore") is bool and bool(e.get("hardcore")) }
	if out.friend == "" or out.title == "" or out.id == "":
		return {}
	out["gk"] = "%s:%d" % [src, out.appid if src == "steam" else out.game_id]
	return out


func _gemerkt_laden() -> void:
	if _gemerkt or demo:
		return
	_gemerkt = true
	if not _feed.is_empty():
		return
	var g := gemerkt_lesen(Config.read_json(Config.path(FEED_FILE), {}), int(Time.get_unix_time_from_system()))
	if not g.is_empty():
		_feed = g


func _merken() -> void:
	if demo or _feed.is_empty():
		return
	Config.write_json(Config.path(FEED_FILE), { "at": int(_feed.at), "list": _feed.list })


## Neue Einträge eines Laufs: an die Seite (höchstens alle TEIL_TAKT_MS); kommen sie nach der Frist,
## gehen sie gleich in den Stand.
func _dazu(gen: int, neu: Array) -> void:
	if gen != _feed_gen or neu.is_empty():
		return
	if not _busy.has("feed"):
		var now := int(Time.get_unix_time_from_system())
		_feed = { "at": int(_feed.get("at", now)), "list": merge_feed([neu, _feed.get("list", [])], now) }
		_merken()
		updated.emit("feed")
		return
	_teil.append_array(neu)
	var ms := Time.get_ticks_msec()
	if ms - _teil_ms >= TEIL_TAKT_MS:
		_teil_ms = ms
		updated.emit("feed_teil")


## Was Freunde zuletzt freigeschaltet haben, neueste zuerst: [{ source, friend_id, friend, avatar,
## title, desc, game, icon, appid, game_id, date, rarity, points, hardcore, gk, id }]
func feed(force := false) -> Array:
	var now := int(Time.get_unix_time_from_system())
	if not force and feed_frisch():
		return _feed.get("list", [])
	if _busy.has("feed"):
		while _busy.has("feed"):
			await updated
		return _feed.get("list", [])
	_busy["feed"] = true
	_feed_gen += 1
	var gen := _feed_gen
	_teil = []
	_teil_ms = 0
	_feed_luecke = false
	if demo:
		await get_tree().create_timer(0.4).timeout
		_teil = _demo_feed()
	elif now < paused_until:
		_feed_luecke = true
	else:
		# Steam und RetroAchievements gleichzeitig; nach FEED_FRIST steht, was da ist.
		var box := { "left": 0 }
		if Social.has_steam():
			box.left += 1
			_quelle(box, _feed_steam.bind(now, gen))
		if Achievements.has_ra():
			box.left += 1
			_quelle(box, _feed_ra.bind(gen))
		var bis := Time.get_ticks_msec() + int(FEED_FRIST * 1000.0)
		while int(box.left) > 0 and Time.get_ticks_msec() < bis:
			await get_tree().create_timer(0.2).timeout
		if int(box.left) > 0:
			_feed_luecke = true
	var jetzt := int(Time.get_unix_time_from_system())
	if _feed_luecke:
		# Nicht jede Antwort kam (kein Netz, Drosselung, Frist): Was bekannt war, bleibt stehen – ohne Netz stünde
		# sonst eine leere Liste da, auch auf der Platte. Der Stand gilt weiter als alt; bald wird neu gefragt.
		_feed = { "at": int(_feed.get("at", 0)), "list": merge_feed([_teil, _feed.get("list", [])], jetzt) }
		_feed_ruhe_bis = jetzt + LUECKE_NEU
		if not _teil.is_empty():
			_merken()
	else:
		_feed = { "at": jetzt, "list": merge_feed([_teil], jetzt) }
		_feed_ruhe_bis = 0
		_merken()
	_teil = []
	_busy.erase("feed")
	updated.emit("feed")
	return _feed.get("list", [])


## Eine Quelle des Feeds laufen lassen (ihre Einträge kommen über _dazu).
func _quelle(box: Dictionary, lauf: Callable) -> void:
	await lauf.call()
	box.left = int(box.left) - 1


func _feed_steam(now: int, gen := -1) -> Array:
	var out: Array = []
	var cands := candidates(Social.steam_friends, 0, FEED_FRIENDS)
	if cands.is_empty():
		return out
	if not Achievements.steam_web_ok():
		return await _feed_steam_cm(now, cands, gen)
	# 1. Welche Spiele spielten die Freunde zuletzt (nur öffentliche Profile antworten).
	var pairs: Array = []
	var i := 0
	while i < cands.size() and pairs.size() < FEED_PAIRS:
		var chunk: Array = cands.slice(i, i + WAVE)
		var urls := {}
		for f in chunk:
			urls[str(f.id)] = STEAM + "IPlayerService/GetRecentlyPlayedGames/v1/?" + await Social.steam_query({ "steamid": str(f.id), "count": FEED_GAMES })
		var box := await _parts(urls)
		for f in chunk:
			var r: Dictionary = box.get(str(f.id), {})
			if ausgefallen(r):
				_luecke(gen)
			if int(r.get("code", 0)) == 429:
				paused_until = now + PAUSE_AFTER_429
				return out
			if not bool(r.get("ok", false)):
				continue
			var rc := SocialS.parse_recent(r.get("data"))
			for gm in rc.games:
				if pairs.size() < FEED_PAIRS and int(gm.get("appid", 0)) > 0:
					pairs.append([f, int(gm.appid), sane(gm.get("name", ""), TEXT_MAX)])
		i += WAVE
	# 2. Je Paar der Stand; Namen, Bilder und Seltenheit aus der eigenen Liste des Spiels (die
	# Listen einer Welle gleichzeitig).
	var known := {}
	var k := 0
	while k < pairs.size():
		var vorher := out.size()
		var chunk: Array = pairs.slice(k, k + WAVE)
		var urls := {}
		for p in chunk:
			var f: Dictionary = p[0]
			urls["%s:%d" % [f.id, int(p[1])]] = STEAM + "ISteamUserStats/GetPlayerAchievements/v1/?" + await Social.steam_query({ "appid": int(p[1]),
				"steamid": str(f.id) })
		var box := await _parts(urls)
		var treffer: Array = []
		for p in chunk:
			var f: Dictionary = p[0]
			var appid := int(p[1])
			var r: Dictionary = box.get("%s:%d" % [f.id, appid], {})
			if ausgefallen(r):
				_luecke(gen)
			if int(r.get("code", 0)) == 429:
				paused_until = now + PAUSE_AFTER_429
				return out
			var pf := parse_steam_friend(r)
			if not bool(pf.ok):
				continue
			var since := now - FEED_DAYS * 86400
			var fresh_apis: Array = []
			for api in pf.got.keys():
				if int(pf.got[api]) >= since:
					fresh_apis.append(api)
			if fresh_apis.is_empty():
				continue
			treffer.append([f, appid, str(p[2]), pf, fresh_apis])
		await _infos(treffer.map(func(t): return [t[1], t[2]]), known)
		for t in treffer:
			var info: Dictionary = known.get(int(t[1]), {})
			for api in t[4]:
				var a: Dictionary = info.get(api, {})
				if not a.is_empty():
					out.append(_entry("steam", t[0], a, str(t[2]), int(t[1]), 0, int(t[3].got[api])))
		_dazu(gen, out.slice(vorher))
		k += WAVE
		if k < pairs.size():
			await get_tree().create_timer(0.15).timeout
	return out


## Feed über Steams Chat-Server (die Web-API lehnt ab): je Freund die Spiele der letzten zwei Wochen
## (Player.GetOwnedGames#1), dann je Paar der Stand (ClientGetUserStats) – alles in einer Sitzung.
func _feed_steam_cm(now: int, cands: Array, gen := -1) -> Array:
	var out: Array = []
	var tok := str(Config.get_value("accounts.steam_chat_refresh", ""))
	var pairs: Array = []
	var geantwortet := 0
	for f in cands:
		if pairs.size() >= FEED_PAIRS:
			break
		var g: Dictionary = await SteamCM.games_of(tok, int(str(f.id)), true)
		if not bool(g.ok):
			continue
		geantwortet += 1
		var recent: Array = (g.games as Array).filter(func(x): return x is Dictionary and int(x.get("playtime_2weeks", 0)) > 0)
		recent.sort_custom(func(a, b): return int(a.get("rtime_last_played", 0)) > int(b.get("rtime_last_played", 0)))
		for gm in recent.slice(0, FEED_GAMES):
			if pairs.size() < FEED_PAIRS:
				pairs.append([f, int(gm.appid), sane(gm.get("name", ""), TEXT_MAX)])
	if pairs.is_empty():
		# Hat kein einziger Freund geantwortet, war es eher die Verbindung als lauter private Profile.
		if geantwortet == 0:
			_luecke(gen)
		return out
	var r: Dictionary = await SteamCM.user_stats(tok, pairs.map(func(p): return [int(p[1]), str(p[0].id)]), true)
	if (r.results as Dictionary).is_empty():
		_luecke(gen)
	var known := {}
	var since := now - FEED_DAYS * 86400
	var treffer: Array = []
	for p in pairs:
		var f: Dictionary = p[0]
		var appid := int(p[1])
		var body: Variant = (r.results as Dictionary).get("%d:%s" % [appid, str(f.id)])
		if not (body is PackedByteArray):
			continue
		var pf := SE.friend_result(SE.parse_user_stats(body))
		if not bool(pf.ok):
			continue
		var fresh_apis: Array = (pf.got as Dictionary).keys().filter(func(api): return int(pf.got[api]) >= since)
		if fresh_apis.is_empty():
			continue
		treffer.append([f, appid, str(p[2]), pf, fresh_apis])
	await _infos(treffer.map(func(t): return [t[1], t[2]]), known)
	for t in treffer:
		var info: Dictionary = known.get(int(t[1]), {})
		for api in t[4]:
			var a: Dictionary = info.get(api, {})
			if not a.is_empty():
				out.append(_entry("steam", t[0], a, str(t[2]), int(t[1]), 0, int(t[3].got[api])))
	_dazu(gen, out)
	SteamChat.diag_log("erfolge-feed", "cm:%d:%d" % [pairs.size(), out.size()],
			"Erfolge der Freunde (Feed): Web-API abgelehnt → Chat-Server, %d Spiele, %d Erfolge" % [pairs.size(), out.size()])
	return out


## Erfolgslisten mehrerer Spiele ([[App-ID, Titel] …]) gleichzeitig nach known holen.
func _infos(spiele: Array, known: Dictionary) -> void:
	var box := { "left": 0 }
	var dabei := {}
	for sp in spiele:
		var appid := int(sp[0])
		if known.has(appid) or dabei.has(appid):
			continue
		dabei[appid] = true
		box.left += 1
		_info_eins(box, appid, str(sp[1]), known)
	while int(box.left) > 0:
		await _part_done


func _info_eins(box: Dictionary, appid: int, title: String, known: Dictionary) -> void:
	await _steam_info(appid, title, known)
	box.left = int(box.left) - 1
	_part_done.emit()


## Erfolgsliste eines Spiels als api -> Eintrag: aus dem Zwischenspeicher, sonst höchstens
## FEED_RESOLVE Spiele eigens laden (die Listen nützen danach auch dir).
func _steam_info(appid: int, title: String, known: Dictionary) -> Dictionary:
	if known.has(appid):
		return known[appid]
	var res: Dictionary = Achievements._steam_lists.get(appid, {})
	if res.is_empty():
		if int(known.get("_laden", 0)) >= FEED_RESOLVE:
			return {}
		known["_laden"] = int(known.get("_laden", 0)) + 1
		res = await Achievements.steam_game(appid, title)
	var map := {}
	for a in res.get("list", []):
		map[str(a.get("id", ""))] = a
	known[appid] = map
	return map


func _feed_ra(gen := -1) -> Array:
	var out: Array = []
	var fl := await following()
	if _follow.is_empty():
		_luecke(gen)          # die Liste der Gefolgten kam nie an
	var cands: Array = fl.slice(0, FEED_FRIENDS)
	var i := 0
	while i < cands.size():
		var chunk: Array = cands.slice(i, i + WAVE)
		var urls := {}
		for f in chunk:
			urls[str(f.id)] = Achievements._ra_url("API_GetUserRecentAchievements.php", { "u": str(f.id), "m": FEED_DAYS * 1440 })
		var box := await _parts(urls)
		var vorher := out.size()
		for f in chunk:
			var r: Dictionary = box.get(str(f.id), {})
			if ausgefallen(r):
				_luecke(gen)
			if int(r.get("code", 0)) == 429:
				paused_until = int(Time.get_unix_time_from_system()) + PAUSE_AFTER_429
				_dazu(gen, out.slice(vorher))
				return out
			if not bool(r.get("ok", false)):
				continue
			for a in UnlocksS.parse_ra_recent(r.get("data")):
				out.append(_entry("ra", f, { "id": str(a.id), "title": str(a.title), "desc": str(a.desc), "icon": str(a.icon), "rarity": -1.0,
					"points": int(a.points), "hardcore": bool(a.hardcore) }, str(a.game), 0, int(a.game_id), int(a.at)))
		_dazu(gen, out.slice(vorher))
		i += WAVE
		if i < cands.size():
			await get_tree().create_timer(0.2).timeout
	return out


func _entry(source: String, f: Dictionary, a: Dictionary, game: String, appid: int, game_id: int, at: int) -> Dictionary:
	return { "source": source, "friend_id": str(f.get("id", "")), "friend": sane(f.get("name", ""), NAME_MAX), "avatar": str(f.get("avatar", "")),
		"id": sane(a.get("id", ""), 128), "title": sane(a.get("title", ""), TEXT_MAX), "desc": sane(a.get("desc", ""), 240), "game": sane(game, TEXT_MAX),
		"icon": str(a.get("icon", "")), "appid": appid, "game_id": game_id, "date": at, "rarity": float(a.get("rarity", -1.0)),
		"points": int(a.get("points", 0)), "hardcore": bool(a.get("hardcore", false)),
		"gk": "%s:%d" % [source, appid if source == "steam" else game_id] }


## Die eigenen Freischaltungen der letzten Tage (Zeiten) für die Rangliste der Woche.
func my_recent_dates() -> Array:
	var out: Array = []
	var seen := {}
	for a in Achievements.recent_unlocks:
		var k := "%s|%s" % [a.get("game", ""), a.get("title", "")]
		if not seen.has(k):
			seen[k] = true
			out.append(int(a.get("date", 0)))
	for h in Unlocks.history(80):
		var k2 := "%s|%s" % [h.get("game", ""), h.get("name", "")]
		if not seen.has(k2):
			seen[k2] = true
			out.append(int(h.get("unlocked_at", 0)))
	return out


## Du, so wie du in Ranglisten stehst.
func me() -> Dictionary:
	var sm: Dictionary = Achievements.steam_me
	var name := str(sm.get("name", Social.me.get("name", "")))
	if name == "":
		name = str(Achievements.ra_profile.get("name", "Du"))
	return { "id": str(sm.get("id", "me")), "name": name, "avatar": str(sm.get("avatar", Social.me.get("avatar", ""))) }


# --- Mehrere Abfragen zugleich --------------------------------------------------------------------

func _parts(urls: Dictionary) -> Dictionary:
	var box := { "left": urls.size() }
	if urls.is_empty():
		box.erase("left")
		return box
	for k in urls.keys():
		_part(box, str(k), str(urls[k]))
	while int(box.left) > 0:
		await _part_done
	box.erase("left")
	return box


func _part(box: Dictionary, key: String, url: String) -> void:
	var r := await Net.get_json(url)
	box[key] = r
	box["left"] = int(box.left) - 1
	_part_done.emit()


# --- Beispieldaten (--demo) --------------------------------------------------------------------------

const DEMO_FOLLOW := [["pixelpaul", 18420, 2100], ["Nora_B", 9100, 300], ["Timo_K", 2300, 0]]


func _demo_following() -> Array:
	var out: Array = []
	for d in DEMO_FOLLOW:
		out.append({ "id": str(d[0]), "name": str(d[0]), "avatar": "", "points": int(d[1]), "soft": int(d[2]), "state": "" })
	return out


## Spiel eines Steam-Freundes in der Demo: besitzt er es laut Social.DEMO_PROFILES? (null: privat)
static func _demo_owns(friend_id: String, appid: int) -> Variant:
	var d: Dictionary = SocialS.DEMO_PROFILES.get(friend_id, {})
	if d.is_empty() or d.get("owned") == null:
		return null
	for g in d.owned:
		if int(g[0]) == appid:
			return true
	return false


## Stand eines Freundes in der Demo: die häufigeren Erfolge hat er, mit Streuung je Freund; die
## Zeiten liegen in den letzten Tagen (für „gestern“) bis Wochen.
static func demo_got(list: Array, friend_id: String, strength: float, now: int) -> Dictionary:
	var got := {}
	for a in list:
		var pct := float(a.get("rarity", -1.0))
		var h := absi(("%s%s" % [a.get("id", ""), friend_id]).hash())
		if pct > strength and h % 5 != 0:
			got[str(a.id)] = now - 1800 - (h % 23) * 43200 - (h % 7) * 3600
	return got


func _demo_board(key: String, pin: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var steam := key.begins_with("steam:")
	var out := { "ok": false, "source": "steam" if steam else "ra", "total": 0, "rows": [], "hidden": 0, "error": "" }
	var res: Dictionary = {}
	if steam:
		res = Achievements.demo_game(key)
	else:
		for gid in Ach.DEMO.keys():
			if int(Ach.DEMO[gid].get("ra_id", 0)) == int(key.get_slice(":", 1)):
				res = Achievements.demo_game(str(gid))
	if res.is_empty():
		out.error = "Für dieses Spiel gibt es keine Erfolge."
		return out
	var list: Array = res.get("list", [])
	out.total = list.size()
	var people: Array = candidates(Social.steam_friends, int(key.get_slice(":", 1)), MAX_FRIENDS, pin) if steam else _demo_following()
	for f in people:
		var fid := str(f.id)
		var owns: Variant = _demo_owns(fid, int(key.get_slice(":", 1))) if steam else true
		var p := { "ok": false, "reason": "", "got": {}, "total": 0, "last": 0 }
		if owns == null:
			p.reason = "Profil privat"
		elif owns == false:
			p.reason = "Spiel nicht in der Bibliothek"
		else:
			var strength := 6.0 + float(absi(fid.hash()) % 40)
			p.got = demo_got(list, fid, strength, now)
			p.ok = true
			p.total = list.size()
			for v in p.got.values():
				p.last = maxi(int(p.last), int(v))
		out.rows.append(_row(f, p))
		if not p.ok:
			out.hidden += 1
	out.ok = out.rows.any(func(r): return bool(r.ok))
	return out


func _demo_feed() -> Array:
	var now := int(Time.get_unix_time_from_system())
	var out: Array = []
	for gid in Ach.DEMO.keys():
		var d: Dictionary = Ach.DEMO[gid]
		if int(d.got) <= 0:
			continue
		var res := Achievements.demo_game(str(gid))
		if res.is_empty():
			continue
		var steam := str(res.source) == "steam"
		var key := "steam:%d" % int(res.get("appid", 0)) if steam else "ra:%d" % int(res.get("ra_id", 0))
		var b := _demo_board(key, "")
		for r in b.rows:
			if not bool(r.ok):
				continue
			var f := { "id": r.id, "name": r.name, "avatar": r.avatar }
			var by_id := {}
			for a in res.list:
				by_id[str(a.id)] = a
			for api in (r.got as Dictionary).keys():
				var at := int(r.got[api])
				if at < now - FEED_DAYS * 86400:
					continue
				var a: Dictionary = by_id.get(str(api), {})
				if a.is_empty():
					continue
				out.append(_entry(str(res.source), f, a, str(res.title), int(res.get("appid", 0)), int(res.get("ra_id", 0)), at))
	return merge_feed([out], now)
