extends RefCounted
## Wer gerade da ist – für den Guide (Reiter Freunde, „Mit dir im Spiel“, Menü an Personen).
##
## Steam-Freunde, Leute aus den Discord-Servern (Widget), aus deinem Sprachkanal und deine
## Discord-Freunde werden zu einer Liste. Steam und Discord bleiben getrennt – auch bei gleichem
## Namen (das können zwei verschiedene Menschen sein); innerhalb von Discord steht jede Person nur
## einmal da (Server, Sprachkanal, Direktnachricht). Wer bei Discord offline ist, fällt weg.
## Reihenfolge: wer spielt (dein Spiel zuerst, dann offene Lobby, dann die anderen), dann wem man
## beitreten kann (anderer Sprachkanal), dann online, dann abwesend.
## Wer ungelesene Nachrichten hat (Steam oder Discord), steht ganz oben unter „Neue Nachrichten“ –
## die neueste zuerst, auch offline (sections).
## Nur reine Funktionen, damit es sich ohne Oberfläche prüfen lässt (tests/logic_guide.gd).

const SocialS := preload("res://src/core/social.gd")
const Lang := preload("res://src/core/lang.gd")

const RANK_GAME := 0
const RANK_JOIN := 1
const RANK_ONLINE := 2
const RANK_AWAY := 3
const RANK_OFFLINE := 4

const STATE_TEXT := { "online": "Online", "away": "Abwesend", "idle": "Abwesend", "busy": "Beschäftigt",
	"dnd": "Bitte nicht stören", "offline": "Offline" }
## Je kleiner, desto eher erreichbar (für zwei Angaben derselben Person).
const STATE_ORDER := { "game": 0, "online": 1, "away": 2, "idle": 2, "busy": 3, "dnd": 3, "offline": 9 }
const SKIP := " ._-|'\"·•~!?()[]{}:;,/\\#*+@&"
const DAYS := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]


## Name ohne Groß/klein, Leer- und Satzzeichen: „Jonas K.“ und „jonas_k“ sind dieselbe Person.
static func name_key(n: String) -> String:
	var out := ""
	for ch in n.to_lower():
		if not SKIP.contains(ch):
			out += ch
	return out


## Spieltitel zum Vergleichen: nur Buchstaben und Ziffern („ELDEN RING“ = „Elden Ring“).
static func title_key(t: String) -> String:
	var out := ""
	for ch in t.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


static func _entry(n: String, avatar: String, st: String) -> Dictionary:
	return { "key": "", "name": n, "avatar": avatar, "state": st, "game": "", "game_id": "", "join_url": "",
		"voice": "", "voice_id": "", "with_me": false, "server": "", "server_name": "", "unread": 0,
		"steam": {}, "discord": {}, "voice_member": {}, "dm": {}, "same_game": false, "rank": RANK_ONLINE, "last_msg": 0 }


## Die besser erreichbare von zwei Angaben (Steam sagt offline, Discord online → online).
static func better_state(a: String, b: String) -> String:
	return a if int(STATE_ORDER.get(a, 5)) <= int(STATE_ORDER.get(b, 5)) else b


## steam: Social.steam_friends · discord: Social.discord · voice: Voice.members ·
## my_channel: dein Sprachkanal ("" wenn keiner) · unread: SteamChat.unread ·
## my_appid / my_title: das laufende Spiel ("" ohne Spiel) · dms: DiscordChat.friends (deine
## Discord-Freunde, Direktnachrichten über das Social SDK) · dm_unread: DiscordChat.unread ·
## steam_last / dm_last: Zeit der letzten Nachricht je Freund (SteamChat.last_at, DiscordChat.last_at).
static func build(steam: Array, discord: Dictionary, voice: Array, my_channel: String, unread: Dictionary,
		my_appid := "", my_title := "", dms: Array = [], dm_unread: Dictionary = {}, steam_last: Dictionary = {}, dm_last: Dictionary = {}) -> Array:
	var out: Array = []
	var by_key := {}
	for f in steam:
		if not (f is Dictionary):
			continue
		var fd: Dictionary = f
		var sid := str(fd.get("id", ""))
		var st := str(fd.get("state", "offline"))
		var n := int(unread.get(sid, 0))
		if st == "offline" and n == 0:
			continue
		var e := _entry(str(fd.get("name", "?")), str(fd.get("avatar", "")), st)
		e["key"] = "s:" + sid
		e["steam"] = fd
		e["game"] = str(fd.get("game", ""))
		e["game_id"] = str(fd.get("game_id", ""))
		e["join_url"] = SocialS.join_url(fd)
		e["unread"] = n
		e["last_msg"] = int(steam_last.get(sid, 0))
		out.append(e)
	# Ab hier nur Discord: zusammengeführt wird nur unter Discord-Einträgen.
	for sid in discord.keys():
		var srv: Dictionary = discord[sid] if discord[sid] is Dictionary else {}
		var chans := {}
		for c in srv.get("channels", []):
			if c is Dictionary:
				chans[str(c.get("id", ""))] = str(c.get("name", ""))
		for m in srv.get("members", []):
			if not (m is Dictionary):
				continue
			var md: Dictionary = m
			var st2 := str(md.get("state", "online"))
			var k2 := name_key(str(md.get("name", "")))
			if st2 == "offline" or k2 == "":
				continue
			var e2: Dictionary = by_key.get(k2, {})
			if e2.is_empty():
				e2 = _entry(str(md.get("name", "?")), str(md.get("avatar", "")), st2)
				e2["key"] = "d:" + k2
				out.append(e2)
				by_key[k2] = e2
			else:
				e2["state"] = better_state(str(e2.state), st2)
			e2["discord"] = md
			e2["server"] = str(sid)
			e2["server_name"] = str(srv.get("name", ""))
			if str(e2.avatar) == "":
				e2["avatar"] = str(md.get("avatar", ""))
			if str(e2.game) == "":
				e2["game"] = str(md.get("game", ""))
			var ch := str(md.get("channel", ""))
			if ch != "":
				e2["voice_id"] = ch
				e2["voice"] = str(chans.get(ch, ""))
				e2["with_me"] = my_channel != "" and ch == my_channel
	for m in voice:
		if not (m is Dictionary) or bool(m.get("me", false)):
			continue
		var vd: Dictionary = m
		var k3 := name_key(str(vd.get("name", "")))
		if k3 == "":
			continue
		var e3: Dictionary = by_key.get(k3, {})
		if e3.is_empty():
			e3 = _entry(str(vd.get("name", "?")), str(vd.get("avatar", "")), "online")
			e3["key"] = "v:" + str(vd.get("id", k3))
			out.append(e3)
			by_key[k3] = e3
		else:
			# Wer mit dir im Kanal ist, ist da – auch wenn Steam „offline“ meldet.
			e3["state"] = better_state(str(e3.state), "online")
		e3["voice_member"] = vd
		e3["voice_id"] = my_channel
		e3["with_me"] = true
		if str(e3.avatar) == "":
			e3["avatar"] = str(vd.get("avatar", ""))
		if str(e3.game) == "":
			e3["game"] = str(vd.get("game", ""))
	# Discord-Freunde aus dem Social SDK: dieselbe Person wie bei Steam/im Server (gleicher Name)
	# bekommt nur die Nachrichten-Möglichkeit dazu; offline nur mit ungelesenen Nachrichten.
	for f in dms:
		if not (f is Dictionary):
			continue
		var fd: Dictionary = f
		var did := str(fd.get("id", ""))
		var n4 := int(dm_unread.get(did, 0))
		var st4 := str(fd.get("state", "offline"))
		if st4 == "offline" and n4 == 0:
			continue
		var k4 := name_key(str(fd.get("name", "")))
		var e4: Dictionary = by_key.get(k4, {}) if k4 != "" else {}
		if e4.is_empty():
			k4 = name_key(str(fd.get("username", "")))
			e4 = by_key.get(k4, {}) if k4 != "" else {}
		if e4.is_empty():
			e4 = _entry(str(fd.get("name", "?")), str(fd.get("avatar", "")), st4)
			e4["key"] = "m:" + did
			out.append(e4)
			if k4 != "":
				by_key[k4] = e4
		else:
			e4["state"] = better_state(str(e4.state), st4)
		e4["dm"] = fd
		e4["unread"] = int(e4.unread) + n4
		e4["last_msg"] = maxi(int(e4.last_msg), int(dm_last.get(did, 0)))
		if str(e4.avatar) == "":
			e4["avatar"] = str(fd.get("avatar", ""))
		if str(e4.game) == "":
			e4["game"] = str(fd.get("game", ""))
	var mine := title_key(my_title)
	for e in out:
		var g := str(e.game)
		e["same_game"] = (my_appid != "" and str(e.game_id) == my_appid) or (mine != "" and g != "" and title_key(g) == mine)
		e["rank"] = rank(e)
	out.sort_custom(before)
	return out


## Woher jemand kommt: "steam" (auch wenn derselbe Mensch bei Discord ist) oder "discord".
static func source(e: Dictionary) -> String:
	return "steam" if not (e.get("steam", {}) as Dictionary).is_empty() else "discord"


## Für den Guide: zuerst „Neue Nachrichten“ (alle mit Ungelesenem, die neueste oben, egal ob online),
## dann nach Lage getrennt – Im Spiel (dein Spiel zuerst, dann wem man beitreten kann,
## dann die anderen), Online (wer in einem anderen Sprachkanal ist zuerst), Abwesend (auch beschäftigt,
## bitte nicht stören), Offline (nur mit Ungelesenem). Steam und Discord stehen zusammen in einem
## Abschnitt; die Zeile zeigt die Quelle (mixed). Reihenfolge innerhalb bleibt (before), die Zahl
## steht nur hier. [{ id, title, items }], leere Abschnitte fallen weg.
static func sections(list: Array) -> Array:
	var out: Array = []
	var neu: Array = list.filter(func(e): return int(e.get("unread", 0)) > 0)
	if not neu.is_empty():
		neu.sort_custom(newest_first)
		out.append({ "id": "neu", "title": "Neue Nachrichten", "items": neu })
	list = list.filter(func(e): return int(e.get("unread", 0)) <= 0)
	for g in [["spiel", "Im Spiel", [RANK_GAME]], ["online", "Online", [RANK_JOIN, RANK_ONLINE]], ["abwesend", "Abwesend", [RANK_AWAY]],
			["offline", "Offline", [RANK_OFFLINE]]]:
		var ranks: Array = g[2]
		var items: Array = list.filter(func(e): return ranks.has(int(e.rank)))
		if not items.is_empty():
			out.append({ "id": g[0], "title": g[1], "items": items })
	return out


## Stehen Leute aus Steam und Discord in einer Liste? Nur dann zeigt jede Zeile ihre Quelle.
static func mixed(list: Array) -> bool:
	var srcs := {}
	for e in list:
		srcs[source(e)] = true
	return srcs.size() > 1


static func rank(e: Dictionary) -> int:
	var st := str(e.get("state", "online"))
	if st == "offline":
		return RANK_OFFLINE
	if str(e.get("game", "")) != "":
		return RANK_GAME
	if str(e.get("join_url", "")) != "" or (str(e.get("voice_id", "")) != "" and not bool(e.get("with_me", false))):
		return RANK_JOIN
	if st in ["away", "idle", "busy", "dnd"]:
		return RANK_AWAY
	return RANK_ONLINE


## Reihenfolge innerhalb einer Stufe: dein Spiel, beitretbar, ungelesen, dann nach Namen.
static func before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.rank) != int(b.rank):
		return int(a.rank) < int(b.rank)
	if bool(a.same_game) != bool(b.same_game):
		return bool(a.same_game)
	var ja := str(a.join_url) != ""
	var jb := str(b.join_url) != ""
	if ja != jb:
		return ja
	if (int(a.unread) > 0) != (int(b.unread) > 0):
		return int(a.unread) > 0
	return str(a.name).naturalnocasecmp_to(str(b.name)) < 0


## „Neue Nachrichten“: die letzte Nachricht zuerst; ohne bekannte Zeit nach Lage, dann nach Namen.
static func newest_first(a: Dictionary, b: Dictionary) -> bool:
	var ta := int(a.get("last_msg", 0))
	var tb := int(b.get("last_msg", 0))
	if ta != tb:
		return ta > tb
	if int(a.get("rank", 0)) != int(b.get("rank", 0)):
		return int(a.get("rank", 0)) < int(b.get("rank", 0))
	return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0


## Punkt am Bild: spielt, im Sprachkanal oder der Zustand.
static func dot(e: Dictionary) -> String:
	var st := str(e.get("state", "online"))
	if st == "offline":
		return "offline"
	if str(e.get("game", "")) != "":
		return "game"
	if str(e.get("voice_id", "")) != "":
		return "voice"
	return st if STATE_TEXT.has(st) else "online"


## Was die Person gerade macht, in wenigen Wörtern (ohne Spiel: Sprachkanal oder Zustand).
static func doing(e: Dictionary) -> String:
	if bool(e.get("with_me", false)):
		return "Mit dir im Sprachkanal"
	if str(e.get("voice", "")) != "":
		return "Im Kanal " + str(e.voice)
	if str(e.get("voice_id", "")) != "":
		return "Im Sprachkanal"
	if str(e.get("state", "")) == "game":
		return "Im Spiel"
	return str(STATE_TEXT.get(str(e.get("state", "")), "Online"))


static func count_online(list: Array) -> int:
	return list.filter(func(e): return int(e.rank) < RANK_OFFLINE).size()


## Was unter deinem eigenen Bild im Sprachkanal steht (statt „du“).
static func me_status(speaking: bool, self_mute: bool, self_deaf: bool, live: bool, game: String, video: bool) -> String:
	if self_deaf:
		return "Ton aus"
	if self_mute:
		return "Mikro aus"
	if speaking:
		return "spricht"
	if live and game != "":
		return "überträgt " + game
	if game != "":
		return "spielt " + game
	if video:
		return "schaut ein Video"
	return "Mikro an"


## Dauer kurz: „12 Min.“, „1,5 Std.“, „120 Std.“.
static func dur(secs: int) -> String:
	if secs < 3600:
		return TranslationServer.translate("%d Min.") % maxi(1, int(secs / 60.0))
	var h := secs / 3600.0
	if h >= 10.0:
		return TranslationServer.translate("%s Std.") % str(int(h))
	var s := "%.1f" % h
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return TranslationServer.translate("1 Std.") if s == "1" else TranslationServer.translate("%s Std.") % Lang.dec(s)


## Spielzeit der letzten sieben Tage (ältester zuerst, heute ganz rechts) aus den Sitzungen
## [{ id, at, secs }]. gid "" zählt alle Spiele. bias_min: Zeitzone in Minuten.
static func week(sessions: Array, gid: String, now: int, bias_min: int) -> Array:
	var bias := bias_min * 60
	var today := floori((now + bias) / 86400.0)
	var out: Array = [0, 0, 0, 0, 0, 0, 0]
	for s in sessions:
		if not (s is Dictionary):
			continue
		if gid != "" and str(s.get("id", "")) != gid:
			continue
		var day := floori((int(s.get("at", 0)) + bias) / 86400.0)
		var i := 6 - (today - day)
		if i >= 0 and i < 7:
			out[i] = int(out[i]) + int(s.get("secs", 0))
	return out


## Kurznamen der sieben Tage passend zu week().
static func week_labels(now: int, bias_min: int) -> Array:
	var out: Array = []
	for i in 7:
		var d := Time.get_datetime_dict_from_unix_time(now + bias_min * 60 - (6 - i) * 86400)
		out.append(DAYS[int(d.weekday)])
	return out


static func sum(values: Array) -> int:
	var t := 0
	for v in values:
		t += int(v)
	return t
