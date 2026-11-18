extends RefCounted
## „Für dich“ auf der Startseite: welche Karten es gerade gibt (Kandidaten aus echten Daten) und
## welche davon zu sehen sind. Die Karten selbst baut for_you_card.gd, games.gd ordnet sie an.
##
## Kandidat: { key, kind, weight, big (taugt als große Karte), live (kommt immer mit), lead (steht
##   immer groß vorn: „Gerade gespielt“), game_id,
##   why, icon, title, sub, hint, act (Callable) – dazu je Art: game, art_url, art_seed, music,
##   people, bars, labels, frac, sub_small (kürzer für kleine Karten), y_hint, y_act }
##
## Gemischt wird gewichtet und mit festem Startwert (pick): Was sinnvoll ist, kommt öfter, und
## dieselben Daten ergeben dieselbe Auswahl. Neu gemischt wird nur beim Betreten der Startseite,
## nach einem Spiel und nach SHUFFLE_MS – nicht bei jeder kleinen Änderung der Daten.

const U := preload("res://src/ui/u.gd")
const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const MovieArt := preload("res://src/ui/components/movie_art.gd")
const SessionSummary := preload("res://src/core/session_summary.gd")
const Backlog := preload("res://src/library/backlog.gd")
const Main := preload("res://src/main.gd")

const SHUFFLE_MS := 20 * 60 * 1000      ## spätestens nach 20 Minuten neu mischen (beim nächsten Zeigen)
const SETTLE_MS := 5000                 ## so lange nach dem Mischen darf nachkommendes noch mitmischen
const REDISCOVER_DAYS := 45             ## „Wiederentdecken“: so lange nicht gespielt …
const REDISCOVER_MIN_SECS := 2 * 3600   ## … und mindestens so lange gespielt
const NEW_DAYS := 21                    ## „Neu in deiner Bibliothek“: so lange gilt etwas als neu
const NEWS_DAYS := 21                   ## Neuigkeiten höchstens so alt
const NEWS_TTL := 6 * 3600              ## Neuigkeiten je Spiel höchstens so oft abrufen
const NEWS_RETRY := 3600                ## nach einem Fehlschlag frühestens wieder
const NEWS_APPS := 4                    ## höchstens so viele Spiele nach Neuigkeiten fragen
const NEWS_URL := "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=%d&count=3&maxlength=0&feeds=steam_community_announcements&format=json"
const NEWS_FILE := "cache/fy_news.json"


# --- Auswahl (reine Funktionen) ------------------------------------------------------------------

## Aus den Kandidaten die Karten wählen: { big: Kandidat oder {}, small: [bis zu slots-1] }.
## keep: Schlüssel der bisherigen Auswahl (Platz 0 = große Karte). Was davon noch da ist, bleibt an
## seinem Platz. live-Kandidaten kommen immer mit, sonst entscheidet das Gewicht. Je Art höchstens
## eine Karte, jedes Spiel höchstens einmal, nichts ohne Gewicht (keine leeren Karten).
static func pick(cands: Array, seed_: int, keep: Array = [], slots := 3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var pool: Array = cands.filter(func(c: Variant) -> bool: return c is Dictionary and float((c as Dictionary).get("weight", 0.0)) > 0.0)
	var by_key := {}
	for c in pool:
		by_key[str(c.get("key", ""))] = c
	var used := { "kinds": {}, "games": {} }
	var big: Dictionary = {}
	var small: Array = []
	# Gerade gespielt (lead) steht immer groß vorn.
	for c in pool:
		if bool(c.get("lead", false)):
			big = c
			_use(c, used)
			break
	# Bisherige Auswahl, soweit es sie noch gibt.
	for i in keep.size():
		var k: Dictionary = by_key.get(str(keep[i]), {})
		if k.is_empty() or not _free(k, used):
			continue
		if i == 0 and bool(k.get("big", false)) and big.is_empty():
			big = k
			_use(k, used)
		elif i > 0 and small.size() < slots - 1:
			small.append(k)
			_use(k, used)
	# Live-Kandidaten (Freund in deinem Spiel) kommen immer mit und gehen vor: Ist kein Platz frei,
	# weicht eine gewöhnliche Karte; teilen sie sich ein Spiel mit einer anderen, weicht die andere.
	var lives := pool.filter(func(c: Dictionary) -> bool: return bool(c.get("live", false)))
	lives.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.weight) > float(b.weight))
	var forced: Array = []
	for c in lives:
		if (used.kinds as Dictionary).has(str(c.get("kind", ""))):
			continue
		var gid := str(c.get("game_id", ""))
		if gid != "" and (used.games as Dictionary).has(gid):
			# Das Spiel steht schon auf einer bisherigen Karte: die weicht.
			if str(big.get("game_id", "")) == gid and not bool(big.get("live", false)):
				_unuse(big, used)
				big = {}
			for n in range(small.size() - 1, -1, -1):
				if str((small[n] as Dictionary).get("game_id", "")) == gid and not bool((small[n] as Dictionary).get("live", false)):
					_unuse(small[n], used)
					small.remove_at(n)
			if (used.games as Dictionary).has(gid):
				continue
		if small.size() + forced.size() >= slots - 1:
			var j := -1
			for n in range(small.size() - 1, -1, -1):
				if not bool((small[n] as Dictionary).get("live", false)):
					j = n
					break
			if j < 0:
				continue
			_unuse(small[j], used)
			small.remove_at(j)
		forced.append(c)
		_use(c, used)
	# Große Karte nach Gewicht (Live-Karten dürfen auch groß werden).
	if big.is_empty():
		var bigs := pool.filter(func(c: Dictionary) -> bool: return bool(c.get("big", false)) and (_free(c, used) or forced.has(c)))
		if not bigs.is_empty():
			big = _weighted(bigs, rng)
			if forced.has(big):
				forced.erase(big)
			else:
				_use(big, used)
	small.append_array(forced)
	# Rest nach Gewicht.
	while small.size() < slots - 1:
		var rest := pool.filter(func(c: Dictionary) -> bool: return _free(c, used))
		if rest.is_empty():
			break
		var c2 := _weighted(rest, rng)
		small.append(c2)
		_use(c2, used)
	return { "big": big, "small": small }


## Schlüssel einer Auswahl (für keep beim nächsten Mal). Ohne große Karte steht "" vorn.
static func keys_of(plan: Dictionary) -> Array:
	var out: Array = [str((plan.get("big", {}) as Dictionary).get("key", ""))]
	for c in plan.get("small", []):
		out.append(str((c as Dictionary).get("key", "")))
	return out


## Was eine Karte zeigt, als Text: ändert er sich, wird die Karte neu gebaut (sonst nicht).
static func card_sig(c: Dictionary) -> String:
	if c.is_empty():
		return ""
	var people := PackedStringArray()
	for p in c.get("people", []):
		people.append(str((p as Dictionary).get("name", "")))
	return "%s|%s|%s|%s|%s|%s|%s|%s|%.3f" % [c.get("key", ""), c.get("why", ""), c.get("title", ""), c.get("sub", ""),
		c.get("hint", ""), ",".join(people), str(c.get("bars", [])), c.get("art_url", ""), float(c.get("frac", -1.0))]


static func _free(c: Dictionary, used: Dictionary) -> bool:
	if (used.kinds as Dictionary).has(str(c.get("kind", ""))):
		return false
	var gid := str(c.get("game_id", ""))
	return gid == "" or not (used.games as Dictionary).has(gid)


static func _use(c: Dictionary, used: Dictionary) -> void:
	used.kinds[str(c.get("kind", ""))] = true
	if str(c.get("game_id", "")) != "":
		used.games[str(c.game_id)] = true


static func _unuse(c: Dictionary, used: Dictionary) -> void:
	(used.kinds as Dictionary).erase(str(c.get("kind", "")))
	(used.games as Dictionary).erase(str(c.get("game_id", "")))


## Gewichtet ziehen. Hat eine Art mehrere Kandidaten (zwei lange liegende Spiele), teilen sie sich
## das Gewicht der Art (ihr höchstes) – sonst käme eine Art nur durch ihre Menge öfter dran.
static func _weighted(list: Array, rng: RandomNumberGenerator) -> Dictionary:
	var k_max := {}
	var k_sum := {}
	for c in list:
		var k := str(c.get("kind", ""))
		k_max[k] = maxf(float(k_max.get(k, 0.0)), float(c.weight))
		k_sum[k] = float(k_sum.get(k, 0.0)) + float(c.weight)
	var eff: Array = []
	var total := 0.0
	for c in list:
		var k := str(c.get("kind", ""))
		var w := float(c.weight) * float(k_max[k]) / maxf(0.001, float(k_sum[k]))
		eff.append(w)
		total += w
	var r := rng.randf() * total
	for i in list.size():
		r -= float(eff[i])
		if r <= 0.0:
			return list[i]
	return list[list.size() - 1]


# --- Daten (reine Funktionen) --------------------------------------------------------------------

## Wie lange etwas her ist, ruhig gerundet: „Gerade eben“, „Vor 2 Std.“, „Gestern“, „Vor 8 Monaten“.
static func since(unix: int, now: int) -> String:
	if unix <= 0:
		return ""
	var s := maxi(0, now - unix)
	if s < 120:
		return "Gerade eben"
	if s < 3600:
		return "Vor %d Min." % int(s / 60.0)
	if s < 86400:
		return "Vor %d Std." % int(s / 3600.0)
	var d := int(s / 86400.0)
	if d < 2:
		return "Gestern"
	if d < 7:
		return "Vor %d Tagen" % d
	if d < 35:
		var w := int(round(d / 7.0))
		return "Vor einer Woche" if w <= 1 else "Vor %d Wochen" % w
	var m := int(round(d / 30.4))
	if m < 12:
		return "Vor einem Monat" if m <= 1 else "Vor %d Monaten" % m
	var y := int(d / 365.0)
	return "Vor über einem Jahr" if y <= 1 else "Vor %d Jahren" % y


## Spielzeit der letzten sieben Tage aus den Sitzungen ({ id, at, secs }; at = Ende):
## { values (ältester Tag zuerst, heute zuletzt), labels, total, top_id }. bias: Zeitzone in s.
static func week(sessions: Array, now: int, bias: int) -> Dictionary:
	var today := floori(float(now + bias) / 86400.0)
	var values: Array = [0, 0, 0, 0, 0, 0, 0]
	var per := {}
	for se in sessions:
		if not (se is Dictionary):
			continue
		var at := int(se.get("at", 0))
		var secs := int(se.get("secs", 0))
		if at <= 0 or secs <= 0:
			continue
		var i := 6 - (today - floori(float(at + bias) / 86400.0))
		if i < 0 or i > 6:
			continue
		values[i] = int(values[i]) + secs
		var id := str(se.get("id", ""))
		per[id] = int(per.get(id, 0)) + secs
	var labels: Array = []
	for i in 7:
		# Tag 0 (1.1.1970) war ein Donnerstag.
		labels.append(PlaytimePage.DAYS_SHORT[posmod(today - 6 + i + 4, 7)])
	var total := 0
	for v in values:
		total += int(v)
	var top_id := ""
	for id in per.keys():
		if top_id == "" or int(per[id]) > int(per[top_id]):
			top_id = str(id)
	return { "values": values, "labels": labels, "total": total, "top_id": top_id }


## Spiele, die lange liegen: mindestens REDISCOVER_MIN_SECS gespielt, seit REDISCOVER_DAYS nicht
## mehr. Meistgespielte zuerst (Favoriten zählen doppelt).
static func rediscover(games: Array, now: int) -> Array:
	var out := games.filter(func(g: Dictionary) -> bool:
		var lp := last_played(g)
		return lp > 0 and now - lp > REDISCOVER_DAYS * 86400 and playtime(g) >= REDISCOVER_MIN_SECS \
			and bool(g.get("installed", true)) and str(g.get("source", "")) != "disc")
	# Die Wertung je Spiel einmal bilden, nicht bei jedem Vergleich.
	var paare: Array = []
	for i in out.size():
		paare.append([_rd_score(out[i]), i])
	paare.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]) if float(a[0]) != float(b[0]) else int(a[1]) < int(b[1]))
	var sortiert: Array = []
	for p: Array in paare:
		sortiert.append(out[int(p[1])])
	return sortiert


static func _rd_score(g: Dictionary) -> float:
	return float(playtime(g)) * (2.0 if bool(g.get("favorite", false)) else 1.0)


## Neu in der Bibliothek: in den letzten NEW_DAYS hinzugefügt und noch nie gespielt, neueste zuerst.
## Der erste Einlesevorgang zählt nicht: Teilen sich viele Spiele (≥ 10) die früheste Stunde, war
## das die Ersteinrichtung – sonst wäre nach dem Einrichten alles „neu“.
static func new_games(games: Array, now: int) -> Array:
	var first := 0
	for g in games:
		var a := int(g.get("added", 0))
		if a > 0 and (first == 0 or a < first):
			first = a
	var bulk := games.filter(func(g: Dictionary) -> bool: return int(g.get("added", 0)) > 0 and int(g.get("added", 0)) - first < 3600).size() >= 10
	var out := games.filter(func(g: Dictionary) -> bool:
		var a := int(g.get("added", 0))
		return a > 0 and now - a < NEW_DAYS * 86400 and last_played(g) == 0 and not (bulk and a - first < 3600) \
			and str(g.get("source", "")) != "disc")
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("added", 0)) > int(b.get("added", 0)))
	return out


## Der nächstliegende Erfolg: noch offen, nicht geheim, und der, den die meisten Spieler haben
## (ohne Anteile der erste offene in der Liste). Leer, wenn alles geschafft ist.
static func next_achievement(res: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for a in res.get("list", []):
		if not (a is Dictionary) or bool(a.get("unlocked", false)) or bool(a.get("hidden", false)):
			continue
		if best.is_empty() or float(a.get("rarity", -1.0)) > float(best.get("rarity", -1.0)):
			best = a
	return best


## Wie Library.last_played/playtime, aber ohne Autoload (für die reinen Funktionen und Prüfungen).
static func last_played(g: Dictionary) -> int:
	return maxi(int(g.get("last_played", 0)), int(g.get("steam_last", 0)))


static func playtime(g: Dictionary) -> int:
	return maxi(int(g.get("playtime", 0)), int(g.get("steam_minutes", 0)) * 60)


## Namen als kurze Reihe: „Mira“, „Mira und Jonas“, „Mira und 3 weitere“.
static func names(list: Array) -> String:
	var n := PackedStringArray()
	for p in list.slice(0, 2):
		n.append(str((p as Dictionary).get("name", "?")))
	if list.size() <= 2:
		return " und ".join(n)
	return "%s und %d weitere" % [n[0], list.size() - 1]


# --- Kandidaten aus den Daten --------------------------------------------------------------------

static var _ach_asked := {}      ## Spiel-ID -> true: Erfolge in dieser Sitzung schon angefragt
static var ach_ids := {}         ## Spiel-IDs, deren Erfolge „Für dich“ gerade betreffen


## Alle Kandidaten, die es gerade gibt (Arten ohne Daten fehlen einfach). seed_ wählt innerhalb
## einer Art (welches lange liegende Spiel, welche Neuigkeit), damit auch das beim Mischen wechselt.
static func gather(main: Main, seed_: int) -> Array:
	var now := int(Time.get_unix_time_from_system())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ ^ 0x5f3759df
	# Gekaufte, nicht installierte Epic-Spiele schlägt „Für dich“ nie vor.
	var vis: Array = Library.visible_games().filter(func(g: Dictionary) -> bool: return not Library.owned_only(g))
	var played: Array = Library.recent(8).filter(func(g: Dictionary) -> bool: return Library.last_played(g) > 0)
	var out: Array = []
	out.append_array(_weiter(main, played, now))
	out.append_array(_freunde(main, vis))
	out.append_array(_voice(main))
	out.append_array(_wieder(main, vis, now, rng))
	out.append_array(_neu(main, vis, now))
	out.append_array(_news(main, vis, now, rng))
	out.append_array(_erfolg(main, vis, played))
	out.append_array(_woche(main, now))
	out.append_array(_medien(main, now))
	out.append_array(_runde(main, now))
	out.append_array(_heute(main, vis, now, seed_))
	return out


static func _game_card(main: Main, kind: String, g: Dictionary, weight: float) -> Dictionary:
	var gg: Dictionary = g
	return { "key": kind, "kind": kind, "weight": weight, "big": true, "game": g, "game_id": str(g.get("id", "")),
		"title": Library.display_title(g), "y_hint": "Zum Spiel", "y_act": func() -> void: main.open_game(gg) }


## Weiterspielen: das zuletzt gespielte Spiel. Uzai kann Emulatoren keinen Spielstand beim Start
## mitgeben (Laden geht nur im Spiel über den Guide), darum startet A das Spiel ganz normal.
static func _weiter(main: Main, played: Array, now: int) -> Array:
	if played.is_empty():
		return []
	var g: Dictionary = played[0]
	if not Library.is_installed(g):
		return []
	var c := _game_card(main, "weiter", g, 5.0)
	c.why = "Weiterspielen"
	c.icon = "play"
	c.sub = "%s · %s" % [since(Library.last_played(g), now), PlaytimePage.dur(Library.playtime(g))]
	c.hint = "Weiterspielen"
	c.act = func() -> void: main.launch(g)
	return [c]


## Freunde jetzt: spielt jemand ein Spiel, das du auch hast, steht das Spiel groß da (Mitspielen
## wie bisher über das Freundes-Menü). Sonst eine Reihe Gesichter mit dem, was sie spielen.
static func _freunde(main: Main, vis: Array) -> Array:
	var on: Array = Social.steam_friends.filter(func(f: Dictionary) -> bool: return str(f.get("state", "offline")) != "offline")
	if on.is_empty():
		return []
	var gaming: Array = on.filter(func(f: Dictionary) -> bool: return str(f.get("state", "")) == "game" and str(f.get("game", "")) != "")
	var rest: Array = on.filter(func(f: Dictionary) -> bool: return not gaming.has(f))
	var people: Array = gaming + rest
	var by_app := {}
	for g in vis:
		if int(g.get("appid", 0)) > 0:
			by_app[int(g.appid)] = g
	for f in gaming:
		var g: Dictionary = by_app.get(int(str(f.get("game_id", "0"))), {})
		if g.is_empty():
			continue
		var fd: Dictionary = f
		var joinable := Social.join_url(f) != ""
		var with: Array = gaming.filter(func(o: Dictionary) -> bool: return str(o.get("game_id", "")) == str(f.game_id))
		var c := _game_card(main, "freunde", g, 6.0)
		c.live = true
		c.why = ("%s spielt gerade" % str(f.name)) if with.size() == 1 else ("%s spielen gerade" % names(with))
		c.icon = "friends"
		c.sub = "Mitspielen über Steam" if joinable else "Auch starten"
		c.hint = "Mitspielen" if joinable else "Optionen"
		# Vorn, wer mitspielt, dahinter, wer sonst gerade da ist.
		c.people = (with + people.filter(func(o: Dictionary) -> bool: return not with.has(o))).slice(0, 4)
		c.act = func() -> void: main.open_friend(fd, "steam")
		return [c]
	# Niemand in einem deiner Spiele: wer da ist und was gespielt wird.
	var line := PackedStringArray()
	for f in gaming.slice(0, 2):
		line.append("%s: %s" % [str(f.name), str(f.game)])
	var c2 := { "key": "freunde", "kind": "freunde", "weight": 3.0, "big": false, "why": "Freunde jetzt", "icon": "friends",
		"title": names(people) + (" online" if gaming.is_empty() else ""),
		"sub": " · ".join(line) if not line.is_empty() else U.plural(on.size(), "Freund online", "Freunde online"),
		"hint": "Freunde", "people": people.slice(0, 4), "act": func() -> void: main.goto("friends") }
	return [c2]


## Sprachkanal: wer gerade drin ist (wie bisher „Live in …“ bzw. „Im Sprachkanal“).
static func _voice(main: Main) -> Array:
	var others_in: Array = Voice.members.filter(func(m: Dictionary) -> bool: return not m.get("me", false)) if Voice.in_channel() else []
	if not others_in.is_empty():
		return [{ "key": "voice", "kind": "voice", "weight": 5.0, "big": false, "why": "Live in %s" % str(Voice.channel.get("name", "")),
			"icon": "headset", "title": names(others_in), "sub": "Im Guide öffnen", "hint": "Guide öffnen",
			"people": others_in.slice(0, 4), "act": func() -> void: main.toggle_guide("discord") }]
	if Voice.ready_() and not Voice.in_channel():
		for o in Voice.others:
			if not (o.members as Array).is_empty():
				var oid := str(o.id)
				return [{ "key": "voice", "kind": "voice", "weight": 4.0, "big": false, "why": "Im Sprachkanal", "icon": "headset",
					"title": names(o.members), "sub": "%s beitreten" % str(o.name), "hint": "Beitreten", "people": (o.members as Array).slice(0, 4),
					"act": func() -> void: Voice.join(oid) }]
		return []
	for ch in Social.voice_channels().slice(0, 1):
		var cid := str(ch.id)
		var cname := str(ch.name)
		return [{ "key": "voice", "kind": "voice", "weight": 4.0, "big": false, "why": "Im Sprachkanal", "icon": "headset",
			"title": names(ch.members), "sub": "%s · %s" % [ch.name, ch.server_name], "hint": "Beitreten", "people": (ch.members as Array).slice(0, 4),
			"act": func() -> void: preload("res://src/ui/layers/friend_actions.gd").join_voice(main, cid, cname) }]
	return []


## Wiederentdecken: ein Spiel, das lange liegt. Welches, entscheidet der Startwert (unter den
## meistgespielten); ein zweites steht bereit, falls das erste schon eine andere Karte hat.
static func _wieder(main: Main, vis: Array, now: int, rng: RandomNumberGenerator) -> Array:
	var list := rediscover(vis, now).slice(0, 8)
	var out: Array = []
	for n in mini(2, list.size()):
		var g: Dictionary = list.pop_at(rng.randi_range(0, list.size() - 1))
		var c := _game_card(main, "wieder", g, 3.0 if n == 0 else 1.0)
		c.key = "wieder:" + str(g.get("id", ""))
		c.why = "Wiederentdecken"
		c.icon = "history"
		c.sub = "Zuletzt %s · %s" % [U.lower_first(since(Library.last_played(g), now)), PlaytimePage.dur(Library.playtime(g))]
		c.sub_small = "%s · %s" % [since(Library.last_played(g), now), PlaytimePage.dur(Library.playtime(g))]
		c.hint = "Spielen"
		c.act = func() -> void: main.launch(g)
		out.append(c)
	return out


## Neu in deiner Bibliothek: das neueste noch nie gespielte Spiel (und wie viele neu sind).
static func _neu(main: Main, vis: Array, now: int) -> Array:
	var fresh := new_games(vis, now)
	var out: Array = []
	for n in mini(2, fresh.size()):
		var g: Dictionary = fresh[n]
		var c := _game_card(main, "neu", g, 3.0 if n == 0 else 1.0)
		c.key = "neu:" + str(g.get("id", ""))
		c.why = "Neu in deiner Bibliothek"
		c.icon = "spark"
		var when := since(int(g.get("added", 0)), now)
		c.sub = (when + " hinzugefügt") if fresh.size() == 1 else "%s · %s" % [when, U.plural(fresh.size(), "neues Spiel", "neue Spiele")]
		c.sub_small = (when + " hinzugefügt") if fresh.size() == 1 else "%s · %d neu" % [when, fresh.size()]
		c.hint = "Öffnen" if main.game_page_on() else "Spielen"
		c.act = func() -> void: main.open_game(g)
		c.erase("y_hint")
		c.erase("y_act")
		out.append(c)
	return out


## Neuigkeiten zu installierten Steam-Spielen (ISteamNews, ohne Schlüssel). Nur aus dem
## Zwischenspeicher; geladen wird nebenher über load_news (sparsam, nie im Spiel).
static func _news(main: Main, vis: Array, now: int, rng: RandomNumberGenerator) -> Array:
	var have: Array = []
	for g in news_games(vis):
		var items: Array = news_for(int(g.appid))
		if not items.is_empty() and (now - int(items[0].get("date", 0)) < NEWS_DAYS * 86400 or Library.demo):
			have.append([g, items[0]])
	var out: Array = []
	for n in mini(2, have.size()):
		var pair: Array = have.pop_at(rng.randi_range(0, have.size() - 1))
		var g: Dictionary = pair[0]
		var it: Dictionary = pair[1]
		var c := _game_card(main, "news", g, 3.0 if n == 0 else 1.0)
		c.key = "news:%d" % int(g.appid)
		c.why = "Neuigkeiten"
		c.icon = "info"
		c.title = str(it.get("title", ""))
		c.sub = "%s · %s" % [Library.display_title(g), since(int(it.get("date", 0)), now)]
		c.hint = "Lesen"
		c.act = func() -> void: open_news(main, g, it)
		out.append(c)
	return out


## Nächster Erfolg bzw. „Fast geschafft“ (wie bisher: das Spiel mit den meisten Erfolgen, ab 60 %).
static func _erfolg(main: Main, vis: Array, played: Array) -> Array:
	var out: Array = []
	ach_ids = {}
	var best: Dictionary = {}
	var best_frac := 0.0
	for g in vis:
		var res := Achievements.cached(g)
		if res.is_empty() or int(res.get("total", 0)) < 5:
			continue
		var frac := float(res.unlocked) / float(res.total)
		if frac >= 0.6 and frac < 1.0 and frac > best_frac:
			best_frac = frac
			best = g
	if not best.is_empty():
		var r2 := Achievements.cached(best)
		var bg: Dictionary = best
		var c := _game_card(main, "erfolg", best, 4.0)
		c.key = "erfolg:fast"
		c.why = "Fast geschafft"
		c.icon = "trophy"
		c.sub = "Noch %s bis 100 %%" % U.plural(int(r2.total) - int(r2.unlocked), "Erfolg", "Erfolge")
		c.hint = "Erfolge"
		c.frac = best_frac
		c.act = func() -> void: main.open_game_achievements(bg)
		out.append(c)
	# Der nächste Erfolg in den zuletzt gespielten Spielen (fehlt etwas, wird es nachgeladen).
	var w := 3.5
	for g in played.slice(0, 3):
		ach_ids[str(g.get("id", ""))] = true
		var res2 := Achievements.cached(g)
		if res2.is_empty():
			_ask_achievements(g)
			continue
		var a := next_achievement(res2)
		if a.is_empty() or int(res2.get("total", 0)) <= 0:
			continue
		var gg: Dictionary = g
		var c2 := _game_card(main, "erfolg", g, w)
		c2.key = "erfolg:" + str(g.get("id", ""))
		c2.why = "Nächster Erfolg"
		c2.icon = "trophy"
		c2.title = str(a.get("title", ""))
		c2.sub = "%s · %d von %d" % [Library.display_title(g), int(res2.unlocked), int(res2.total)]
		c2.hint = "Erfolge"
		c2.frac = float(res2.unlocked) / float(res2.total)
		c2.act = func() -> void: main.open_game_achievements(gg)
		out.append(c2)
		w *= 0.5
	if not best.is_empty():
		ach_ids[str(best.get("id", ""))] = true
	return out


## Erfolge eines zuletzt gespielten Spiels einmal je Sitzung im Hintergrund holen (meldet sich über
## Achievements.updated). Nicht im Spiel und nur, wo es eine Quelle gibt.
static func _ask_achievements(g: Dictionary) -> void:
	var gid := str(g.get("id", ""))
	if _ach_asked.has(gid) or Launcher.in_game:
		return
	var src := str(g.get("source", ""))
	if not ((src == "steam" and Achievements.has_steam()) or (src == "rom" and Achievements.has_ra())):
		return
	_ach_asked[gid] = true
	Achievements.for_game(g)


## Deine Woche: Spielzeit der letzten sieben Tage als kleine Säulen.
static func _woche(main: Main, now: int) -> Array:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var wk := week(Library.load_sessions(), now, bias)
	if int(wk.total) <= 0:
		return []
	var top := Library.get_game(str(wk.top_id))
	if not top.is_empty() and not Library.is_visible(top):
		top = {}
	return [{ "key": "woche", "kind": "woche", "weight": 2.0, "big": true, "why": "Deine Woche", "icon": "clock",
		"title": PlaytimePage.dur(int(wk.total)) + " gespielt",
		"sub": ("Am meisten: " + Library.display_title(top)) if not top.is_empty() else "in den letzten sieben Tagen",
		"bars": wk.values, "labels": wk.labels, "hint": "Spielzeit", "act": func() -> void: main.goto("achievements", "statistik") }]


## Gerade gespielt (Punkt 24): nach einer Runde ab SessionSummary.MIN_SECS steht sie ein paar
## Stunden groß vorn – Zeit, neue Erfolge, Aufnahmen, ein erreichter Meilenstein, der Fortschritt
## als Balken. A öffnet die Zusammenfassung. Abschaltbar (system.round_summary).
static func _runde(main: Main, now: int) -> Array:
	var r: Variant = main.last_round
	if not (r is Dictionary) or not Config.get_value("system.round_summary", true) or not SessionSummary.card_due(r, now):
		return []
	var g := Library.get_game(str(r.get("game_id", "")))
	if g.is_empty() or not Library.is_visible(g):
		return []
	# Kommt die Erfolgsliste nach dem Spiel neu, soll die Karte mitziehen.
	ach_ids[str(g.id)] = true
	var s := SessionSummary.make(r, Unlocks.history(SessionSummary.UNLOCKS_N), Unlocks.game_key(g), str(g.get("source", "")) == "rom", Capture.for_game(g),
			Achievements.cached(g))
	var c := _game_card(main, "runde", g, 9.0)
	c.lead = true
	c.why = ("%s geschafft" % U.plural(int(s.mark), "Stunde", "Stunden")) if int(s.mark) > 0 else "Gerade gespielt"
	c.icon = "star" if int(s.mark) > 0 else "clock"
	var parts := PackedStringArray([PlaytimePage.dur(int(s.secs))])
	var got := (s.unlocks as Array).size()
	if got > 0:
		parts.append(U.plural(got, "neuer Erfolg", "neue Erfolge"))
	var caps := int(s.clips) + int(s.shots)
	if caps > 0:
		parts.append(U.plural(caps, "Aufnahme", "Aufnahmen"))
	c.sub = " · ".join(parts)
	if int(s.total) > 0:
		c.frac = float(s.have) / float(s.total)
	c.hint = "Zusammenfassung"
	c.act = func() -> void: main.open_round_summary()
	return [c]


## Was spiele ich heute? (Backlog, Roadmap 2): dezent als kleine Karte und nur, wenn du den Backlog
## benutzt (mindestens ein Spiel mit „Spiele ich“, „Will ich spielen“ oder „Pausiert“). A öffnet
## die Spielseite; der ganze Vorschlag mit Würfeln steht unter Profil → Backlog.
static func _heute(main: Main, vis: Array, now: int, seed_: int) -> Array:
	# Gibt es Spiele mit „Spiele ich“, „Will ich spielen“ oder „Pausiert“, kommt der Vorschlag nur aus Spielen mit
	# Status (Backlog.candidates): Nur für sie rechnet Uzai Spielzeit und „zuletzt“ aus – vorher für die ganze
	# Bibliothek, bei jedem Nachrechnen von „Für dich“ (gemessen bei 3000 Spielen: 32 ms).
	var mit: Array = vis.filter(func(g: Dictionary) -> bool: return Backlog.status_of(g) != "")
	if not mit.any(func(g: Dictionary) -> bool: return Backlog.status_of(g) in ["spiele", "will", "pausiert"]):
		return []
	var info := {}
	for g in mit:
		info[str(g.get("id", ""))] = { "playtime": Library.playtime(g), "last": Library.last_played(g), "installed": Library.is_installed(g) }
	var cands := Backlog.candidates(mit, info, now)
	var pick := Backlog.pick_today(cands, seed_)
	if pick.is_empty():
		return []
	var g: Dictionary = pick.game
	var c := _game_card(main, "heute", g, 1.5)
	c.big = false
	c.why = "Was spiele ich heute?"
	c.icon = "bookmark"
	c.sub = str(pick.why)
	c.hint = "Zum Spiel"
	c.act = func() -> void: main.open_game(g)
	return [c]


## Medien weiter: Weiterschauen (Filme/Nuvio) oder was gerade an Musik läuft.
static func _medien(main: Main, now: int) -> Array:
	var out: Array = []
	if Movies.enabled():
		var cw: Array = Movies.continue_watching()
		if not cw.is_empty() and now - int(cw[0].get("updated", 0)) < 21 * 86400:
			var v: Dictionary = cw[0]
			var parts := PackedStringArray()
			if int(v.get("episode", 0)) > 0:
				parts.append(MovieArt.episode_code(int(v.get("season", 0)), int(v.episode)))
			var left := MovieArt.left_text(float(v.get("position", 0.0)), float(v.get("duration", 0.0)))
			if left != "":
				parts.append(left)
			elif bool(v.get("next_up", false)):
				parts.append("Nächste Folge")
			var vid := str(v.get("video_id", v.get("id", "")))
			var how := "start" if bool(v.get("next_up", false)) else "resume"
			out.append({ "key": "medien:film", "kind": "medien", "weight": 3.0, "big": true, "why": "Weiterschauen", "icon": "video",
				"title": str(v.get("name", "")), "sub": " · ".join(parts), "art_url": MovieArt.backdrop_url(v), "art_seed": str(v.get("id", "")),
				"frac": MovieArt.frac(float(v.get("position", 0.0)), float(v.get("duration", 0.0))),
				"hint": "Weiterschauen", "act": func() -> void: main.open_movie_streams(v, vid, how) })
	var m: Dictionary = Music.now
	if str(m.get("title", "")) != "" and bool(m.get("playing", false)):
		out.append({ "key": "medien:musik", "kind": "medien", "weight": 2.0, "big": false, "why": "Läuft gerade", "icon": "music",
			"title": str(m.title), "sub": str(m.get("artist", "")), "art_url": str(m.get("art", "")), "music": true,
			"hint": "Musik", "act": func() -> void: main.goto("music", "jetzt") })
	elif m.is_empty() and Music.mode() == "spotify" and Music.has_spotify() and not Music.local_on():
		# Nichts läuft: der zuletzt gehörte Titel aus dem eigenen Verlauf (nur auf diesem PC, höchstens
		# drei Tage alt). A macht dort weiter, wo zuletzt etwas lief (Spotify Connect).
		var last: Dictionary = Music.verlauf_list()[0] if not Music.verlauf_list().is_empty() else {}
		if not last.is_empty() and now - int(last.get("ts", 0)) < 3 * 86400:
			out.append({ "key": "medien:musik", "kind": "medien", "weight": 1.2, "big": false, "why": "Zuletzt gehört", "icon": "music",
				"title": str(last.t), "sub": str(last.get("a", "")), "art_url": str(last.get("art", "")), "music": true,
				"hint": "Weiter hören", "act": func() -> void: Music.play_pause() })
	return out


# --- Die Seitenleiste (fuer_dich_leiste.gd) -------------------------------------------------------
# Oben ein großer „Weiter“-Moment (die Runde eben, sonst Weiterspielen, sonst die große Karte der
# Mischung), darunter ruhige Abschnitte in der Listen-Sprache des Guides. Jeder Abschnitt nur mit
# Inhalt, höchstens ZEILEN_MAX Zeilen, die Reihenfolge fest. Alles aus Daten, die schon da sind
# (Kandidaten oben, Freunde, Weiterschauen, Wunschliste, Sitzungen) – nichts wird dafür geladen.
#
# Zeile: { key, icon, title, extra (leise dahinter), value (rechts), hint (A), act, y_hint, y_act,
#   game (Cover vorn), person (Profilbild vorn), music (mit ⏮ ⏯ ⏭), chevron, mehr („Alle …“, zuletzt) }

const ZEILEN_MAX := 3
const JAHR_MIN_SECS := 600              ## „Vor einem Jahr“: so lange muss es damals gelaufen sein
const SCHAUEN_TAGE := 21                ## Weiterschauen höchstens so alt
## [Kennung, Etikett] in fester Reihenfolge.
const ABSCHNITTE := [
	["freunde", "Freunde spielen"], ["erfolge", "Fast geschafft"], ["schauen", "Weiterschauen"],
	["musik", "Läuft gerade"], ["neu", "Neu in deiner Bibliothek"], ["wieder", "Wiederentdecken"],
	["news", "Neuigkeiten"], ["angebote", "Wunschliste im Angebot"], ["woche", "Deine Woche"]]
## Welche Art von Kandidat in welchem Abschnitt steht (Weiterspielen und die Runde stehen oben groß).
const ART_ABSCHNITT := { "freunde": "freunde", "voice": "freunde", "erfolg": "erfolge", "neu": "neu",
	"wieder": "wieder", "heute": "wieder", "news": "news", "woche": "woche" }
## Kandidaten, die eine genauere Fassung aus leiste_extra ersetzt (wenn es die gibt): die Gruppe
## „Freunde jetzt“ durch je eine Zeile pro Freund, der eine Film durch die Liste zum Weiterschauen.
const ERSETZT := { "freunde": "freunde", "medien:film": "schauen" }


## Oben groß: die Runde eben (lead), sonst Weiterspielen, sonst big (die große Karte der Mischung).
static func held(cands: Array, big: Dictionary = {}) -> Dictionary:
	var weiter: Dictionary = {}
	for c in cands:
		if not (c is Dictionary):
			continue
		if bool(c.get("lead", false)):
			return c
		if str(c.get("kind", "")) == "weiter" and weiter.is_empty():
			weiter = c
	return weiter if not weiter.is_empty() else big


## Die Leiste aus Kandidaten (gather) und Zeilen weiterer Quellen (extra: Abschnitt -> Zeilen, die
## vorn stehen): { hero: Kandidat oder {}, abschnitte: [{ id, label, rows }] }. Rein.
static func ordnen(cands: Array, extra: Dictionary = {}, big: Dictionary = {}) -> Dictionary:
	var hero := held(cands, big)
	var hk := str(hero.get("key", ""))
	var hg := str(hero.get("game_id", ""))
	var rows := {}
	var keys := {}
	for id in extra:
		for z in extra[id]:
			if z is Dictionary and str(id) == "wieder" and hg != "" and str(z.get("game_id", "")) == hg:
				continue
			if z is Dictionary and not keys.has(str(z.get("key", ""))):
				keys[str(z.get("key", ""))] = true
				(rows.get_or_add(str(id), []) as Array).append(z)
	var labels := {}
	for c in cands:
		if not (c is Dictionary):
			continue
		var k := str(c.get("key", ""))
		var kind := str(c.get("kind", ""))
		var id := str(ART_ABSCHNITT.get(kind, ""))
		if kind == "medien":
			id = "musik" if bool(c.get("music", false)) else "schauen"
		if id == "" or k == hk or keys.has(k):
			continue
		var ers := str(ERSETZT.get(k, ERSETZT.get(kind, "")))
		if ers != "" and not (extra.get(ers, []) as Array).is_empty():
			continue
		# Dasselbe Spiel steht schon oben groß: nicht noch einmal zum Spielen anbieten.
		if hg != "" and str(c.get("game_id", "")) == hg and kind in ["neu", "wieder", "heute"]:
			continue
		keys[k] = true
		(rows.get_or_add(id, []) as Array).append(zeile_aus(c))
		if id == "musik" and str(c.get("why", "")) == "Zuletzt gehört":
			labels[id] = "Zuletzt gehört"
	var out: Array = []
	for a in ABSCHNITTE:
		var list: Array = rows.get(str(a[0]), [])
		if list.is_empty():
			continue
		# „Alle …“ (mehr) steht immer zuletzt und zählt nicht mit.
		var mehr: Array = list.filter(func(z: Dictionary) -> bool: return bool(z.get("mehr", false)))
		var rest: Array = list.filter(func(z: Dictionary) -> bool: return not bool(z.get("mehr", false))).slice(0, ZEILEN_MAX)
		out.append({ "id": str(a[0]), "label": str(labels.get(str(a[0]), a[1])), "rows": rest + mehr.slice(0, 1) })
	return { "hero": hero, "abschnitte": out }


## Ein Kandidat als Zeile: Titel, leise der kurze Zusatz, rechts der Fortschritt bei Erfolgen.
static func zeile_aus(c: Dictionary) -> Dictionary:
	var z := { "key": str(c.get("key", "")), "icon": str(c.get("icon", "")), "title": str(c.get("title", "")),
		"extra": str(c.get("sub_small", c.get("sub", ""))), "hint": str(c.get("hint", "Öffnen")), "act": c.get("act") }
	for k in ["game", "game_id", "y_act", "y_hint", "music"]:
		if c.has(k):
			z[k] = c[k]
	if str(c.get("key", "")) == "erfolg:fast" and float(c.get("frac", -1.0)) >= 0.0:
		z["value"] = "%d %%" % floori(float(c.frac) * 100.0)
	var people: Array = c.get("people", [])
	if str(c.get("kind", "")) == "voice" and not people.is_empty():
		z["person"] = people[0]
	return z


## Freunde, die gerade etwas spielen: zuerst die in deinen Spielen (owned: App-ID -> Spiel), dann
## die übrigen; je Gruppe, wer länger dabei ist, zuerst. Rein.
static func freunde_spielen(friends: Array, owned: Dictionary) -> Array:
	var out: Array = friends.filter(func(f: Variant) -> bool:
		return f is Dictionary and str(f.get("state", "")) == "game" and str(f.get("game", "")) != "")
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ha := owned.has(int(str(a.get("game_id", "0"))))
		var hb := owned.has(int(str(b.get("game_id", "0"))))
		if ha != hb:
			return ha
		return int(a.get("since", 0)) < int(b.get("since", 0)))
	return out


## Angebote auf der Wunschliste: zuerst, was neu im Angebot ist (neu: App-ID -> true), dann der
## höchste Rabatt. Rein.
static func angebote(wish: Array, neu: Dictionary = {}) -> Array:
	var out: Array = wish.filter(func(it: Variant) -> bool: return it is Dictionary and int(it.get("discount", 0)) > 0)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var na := neu.has(int(a.get("appid", 0)))
		var nb := neu.has(int(b.get("appid", 0)))
		if na != nb:
			return na
		return int(a.discount) > int(b.discount))
	return out


## Was vor einem Jahr lief (363 bis 367 Tage her, zusammen mindestens JAHR_MIN_SECS): { id, secs,
## heute (genau heute vor einem Jahr) } oder {}. bias: Zeitzone in s. Rein.
static func vor_einem_jahr(sessions: Array, now: int, bias: int) -> Dictionary:
	var today := floori(float(now + bias) / 86400.0)
	var per := {}
	var genau := {}
	for se in sessions:
		if not (se is Dictionary) or int(se.get("at", 0)) <= 0:
			continue
		var d := today - floori(float(int(se.at) + bias) / 86400.0)
		if d < 363 or d > 367:
			continue
		var id := str(se.get("id", ""))
		per[id] = int(per.get(id, 0)) + int(se.get("secs", 0))
		if d == 365 or d == 366:
			genau[id] = true
	var best := ""
	for id in per:
		if int(per[id]) >= JAHR_MIN_SECS and (best == "" or int(per[id]) > int(per[best])):
			best = str(id)
	if best == "":
		return {}
	return { "id": best, "secs": int(per[best]), "heute": genau.has(best) }


## Zeilen aus Quellen, die die Karten nicht einzeln zeigen: wer was spielt, Weiterschauen (Filme
## und YouTube), Angebote der Wunschliste, was vor einem Jahr lief.
static func leiste_extra(main: Main) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var vis: Array = Library.visible_games().filter(func(g: Dictionary) -> bool: return not Library.owned_only(g))
	return { "freunde": _z_freunde(main, vis), "schauen": _z_schauen(main, now), "angebote": _z_angebote(main),
		"wieder": _z_jahr(main, now) }


static func _z_freunde(main: Main, vis: Array) -> Array:
	var own := {}
	for g in vis:
		if int(g.get("appid", 0)) > 0:
			own[int(g.appid)] = g
	var list := freunde_spielen(Social.steam_friends, own)
	var out: Array = []
	for f in list.slice(0, ZEILEN_MAX):
		var fd: Dictionary = f
		var g: Dictionary = own.get(int(str(f.get("game_id", "0"))), {})
		var z := { "key": "fr:" + str(f.get("id", "")), "title": str(f.get("name", "")), "extra": str(f.get("game", "")),
			"person": fd, "hint": "Mitspielen" if Social.join_url(f) != "" else "Optionen",
			"act": func() -> void: main.open_friend(fd, "steam") }
		if not g.is_empty():
			var gg: Dictionary = g
			z["y_hint"] = "Zum Spiel"
			z["y_act"] = func() -> void: main.open_game(gg)
		out.append(z)
	var on: int = Social.steam_friends.filter(func(f: Dictionary) -> bool: return str(f.get("state", "offline")) != "offline").size()
	if not out.is_empty() and on > out.size():
		out.append({ "key": "fr:alle", "icon": "friends", "title": "Alle Freunde", "value": str(on), "chevron": true, "mehr": true,
			"hint": "Freunde", "act": func() -> void: main.goto("friends") })
	return out


static func _z_schauen(main: Main, now: int) -> Array:
	var out: Array = []
	if Movies.enabled():
		for v in Movies.continue_watching().slice(0, 2):
			if now - int(v.get("updated", 0)) >= SCHAUEN_TAGE * 86400:
				continue
			var vd: Dictionary = v
			var parts := PackedStringArray()
			if int(v.get("episode", 0)) > 0:
				parts.append(MovieArt.episode_code(int(v.get("season", 0)), int(v.episode)))
			var left := MovieArt.left_text(float(v.get("position", 0.0)), float(v.get("duration", 0.0)))
			if left != "":
				parts.append(left)
			elif bool(v.get("next_up", false)):
				parts.append("Nächste Folge")
			var vid := str(v.get("video_id", v.get("id", "")))
			var how := "start" if bool(v.get("next_up", false)) else "resume"
			out.append({ "key": "film:" + str(v.get("id", "")), "icon": "video", "title": str(v.get("name", "")),
				"extra": " · ".join(parts), "hint": "Weiterschauen", "act": func() -> void: main.open_movie_streams(vd, vid, how) })
	for e in YouTube.continue_list().slice(0, 2):
		if now - int(e.get("at", 0)) >= SCHAUEN_TAGE * 86400:
			continue
		var ed: Dictionary = e
		var parts2 := PackedStringArray()
		if str(e.get("channel", "")) != "":
			parts2.append(str(e.channel))
		var left2 := MovieArt.left_text(float(e.get("pos", 0)), float(e.get("duration", 0)))
		if left2 != "":
			parts2.append(left2)
		out.append({ "key": "yt:" + str(e.get("id", "")), "icon": "video", "title": str(e.get("title", "")),
			"extra": " · ".join(parts2), "hint": "Weiterschauen", "act": func() -> void: main.open_video([ed], 0) })
	return out


static func _z_angebote(main: Main) -> Array:
	if not Store.wishlist_loaded or Config.kid_blocks("shop"):
		return []
	var secs: Variant = main.sections if main else null
	if not (secs is Dictionary) or not (secs as Dictionary).has("shop"):
		return []
	var out: Array = []
	for it in angebote(Store.wishlist, Store.sale_new).slice(0, ZEILEN_MAX):
		var item: Dictionary = it
		var neu := Store.sale_new.has(int(it.get("appid", 0)))
		var oeffnen := func() -> void:
			var sv: Variant = (main.sections as Dictionary).get("shop")
			if sv is Node and is_instance_valid(sv) and (sv as Node).has_method("open_item"):
				(sv as Node).call("open_item", item)
			else:
				main.goto("shop", "wunschliste")
		out.append({ "key": "wunsch:%d" % int(it.get("appid", 0)), "icon": "tag", "title": str(it.get("name", "")),
			"extra": ("−%d %%" % int(it.discount)) + (" · neu" if neu else ""), "value": Store.price_label(it), "hint": "Ansehen",
			"act": oeffnen })
	return out


static func _z_jahr(main: Main, now: int) -> Array:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var j := vor_einem_jahr(Library.load_sessions(), now, bias)
	if j.is_empty():
		return []
	var g := Library.get_game(str(j.id))
	if g.is_empty() or not Library.is_visible(g) or Library.owned_only(g):
		return []
	var gg: Dictionary = g
	var da := Library.is_installed(g)
	var los := func() -> void:
		if da:
			main.launch(gg)
		else:
			main.open_game(gg)
	return [{ "key": "jahr:" + str(g.id), "game": g, "game_id": str(g.id), "title": Library.display_title(g),
		"extra": ("Heute vor einem Jahr" if bool(j.heute) else "Vor einem Jahr") + " · " + PlaytimePage.dur(int(j.secs)),
		"hint": "Spielen" if da else "Zum Spiel", "y_hint": "Zum Spiel", "y_act": func() -> void: main.open_game(gg), "act": los }]


# --- Neuigkeiten (ISteamNews/GetNewsForApp) -------------------------------------------------------

static var _news_cache := {}     ## App-ID (Text) -> { at, ok, items }
static var _news_loaded := false
static var _news_busy := false

## Beispiele für die Demo (Titel, Text, vor so vielen Stunden, als Patchnotes markiert).
const DEMO_NEWS := {
	1245620: [["Patch 1.16: Feinschliff für Nachtherrschaft und Kolosseum", "Mit diesem Patch verbessern wir die Bildrate in großen Gebieten und beheben mehrere Fehler im Kolosseum.\n\nDie Steuerung mit dem Controller reagiert im Inventar nun schneller, und die Kamera bleibt beim Reiten ruhiger.", 30, true]],
	367520: [
		["Hollow Knight: Silksong – Hornet bekommt ein neues Abenteuer",
		"Danke für eure Geduld! Wir haben neue Bilder aus Silksong und eine kleine Aktualisierung für Hollow Knight: Die deutschen Texte wurden überarbeitet.", 76]],
	413150: [
		["Stardew Valley 1.6.15",
		"Ein kleines Update mit Fehlerbehebungen für den Mehrspielermodus. Außerdem bleiben Geschenke an Dorfbewohner jetzt zuverlässig gespeichert.", 52]],
	2379780: [["Balatro: Freunde-von-Jimbo-Paket 4", "Neue Kartenrücken aus euren Lieblingsspielen sind da – kostenlos für alle. Viel Spaß beim Mischen!", 120]],
}


## Installierte Steam-Spiele, für die sich Neuigkeiten lohnen: zuletzt gespielt (60 Tage) oder
## Favorit, zuletzt gespielte zuerst. Höchstens NEWS_APPS.
static func news_games(vis: Array) -> Array:
	var now := int(Time.get_unix_time_from_system())
	var out := vis.filter(func(g: Dictionary) -> bool:
		return str(g.get("source", "")) == "steam" and int(g.get("appid", 0)) > 0 and bool(g.get("installed", true)) \
			and (now - last_played(g) < 60 * 86400 or bool(g.get("favorite", false))))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return last_played(a) > last_played(b))
	return out.slice(0, NEWS_APPS)


## Neuigkeiten eines Spiels aus dem Zwischenspeicher ([{ title, date, text, author }], neueste zuerst).
static func news_for(appid: int) -> Array:
	_news_load()
	if Library.demo and DEMO_NEWS.has(appid):
		var now := int(Time.get_unix_time_from_system())
		var out: Array = []
		for n in DEMO_NEWS[appid]:
			out.append({ "title": str(n[0]), "text": str(n[1]), "date": now - int(n[2]) * 3600, "author": "", "patch": n.size() > 3 and bool(n[3]) })
		return out
	return (_news_cache.get(str(appid), {}) as Dictionary).get("items", [])


## Fehlende oder alte Neuigkeiten nachladen (nacheinander, je Spiel höchstens alle NEWS_TTL),
## danach done() aufrufen, wenn etwas Neues kam. Nie im Spiel, nie in der Demo.
static func load_news(vis: Array, done: Callable) -> void:
	if _news_busy or Library.demo or Launcher.in_game:
		return
	_news_load()
	var now := int(Time.get_unix_time_from_system())
	var due: Array = []
	for g in news_games(vis):
		var e: Dictionary = _news_cache.get(str(g.appid), {})
		var ttl := NEWS_TTL if bool(e.get("ok", false)) else NEWS_RETRY
		if e.is_empty() or now - int(e.get("at", 0)) > ttl:
			due.append(int(g.appid))
	if due.is_empty():
		return
	_news_busy = true
	var got := false
	for appid in due:
		var r: Dictionary = await Net.get_json(NEWS_URL % appid)
		var items: Array = Store.parse_news(r.data, 3) if r.ok else []
		for it in items:
			it["text"] = str(it.get("text", "")).left(6000)
		_news_cache[str(appid)] = { "at": int(Time.get_unix_time_from_system()), "ok": bool(r.ok), "items": items }
		got = got or not items.is_empty()
	Config.cap(_news_cache, 60)
	Config.write_json(Config.path(NEWS_FILE), _news_cache)
	_news_busy = false
	if got and done.is_valid():
		done.call()


static func _news_load() -> void:
	if _news_loaded:
		return
	_news_loaded = true
	if Library.demo:
		return
	var d: Variant = Config.read_json(Config.path(NEWS_FILE), {})
	if d is Dictionary:
		_news_cache = d


## Eine Neuigkeit lesen (dieselbe Leseansicht wie im Shop).
static func open_news(main: Main, g: Dictionary, it: Dictionary) -> void:
	var reader = load("res://src/ui/layers/store_game.gd")._Reader.new()
	reader.heading = str(it.get("title", ""))
	reader.heading_raw = true      # Titel der Neuigkeit
	reader.sub = "%s · %s" % [Library.display_title(g), U.date(int(it.get("date", 0)))]
	reader.paragraphs = Array(str(it.get("text", "")).split("\n\n"))
	main.open_layer(reader)
