extends Node
## Erfolge von Freunden ohne Netz (src/core/achievements_friends.gd): Reihenfolge der Freunde,
## Antworten von Steam und RetroAchievements lesen (privat, gedrosselt, kaputt), wer einen Erfolg
## hat und der Satz dazu, Ranglisten (Spiel und Woche), „Als Nächstes greifbar“, Feed
## zusammenführen, Frische, fremde Texte säubern; dazu das Pop-up „komplett“ (Aussehen, Funken,
## wann ein Spiel komplett ist) und die Beispieldaten.
## Aufruf: godot --headless --path . res://tests/logic_erfolge_freunde.tscn

const F := preload("res://src/core/achievements_friends.gd")
const Un := preload("res://src/core/unlocks.gd")
const Toast := preload("res://src/ui/components/achievement_toast.gd")
const RankTile := preload("res://src/ui/components/ach/rank_tile.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_sane()
	_candidates()
	_parse()
	_who()
	_ranking()
	_reachable()
	_feed()
	_popup()
	await _ausfall()
	await _demo()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _sane() -> void:
	print("Fremde Texte")
	check(F.sane("Mira") == "Mira" and F.sane(" Jonas K. ") == "Jonas K.", "Namen bleiben, Rand weg")
	check(F.sane("a\u0007b\nc", 10) == "abc", "Steuerzeichen fliegen raus")
	check(F.sane("x".repeat(500), 32).length() == 32, "gekürzt auf die Höchstlänge")
	check(F.sane(null) == "" and F.sane({ "a": 1 }) == "" and F.sane(42) == "42", "nur Text und Zahlen")
	check(F.ra_name_ok("pixel_paul.1") and not F.ra_name_ok("a") and not F.ra_name_ok("böse name") and not F.ra_name_ok("x&y=1"),
			"RA-Namen nur aus erlaubten Zeichen (sie gehen als Parameter hinaus)")
	check(F.key_of({ "source": "steam", "appid": 620 }) == "steam:620" and F.key_of({ "source": "rom", "_ra_id": 7 }) == "ra:7"
			and F.key_of({ "source": "ra", "ra_id": 9 }) == "ra:9" and F.key_of({ "source": "pc" }) == "", "Spielschlüssel")


func _candidates() -> void:
	print("Welche Freunde zuerst")
	var friends := [
		{ "id": "76561190000000001", "name": "A", "state": "online", "game_id": "", "last": 0 },
		{ "id": "76561190000000002", "name": "B", "state": "game", "game_id": "620", "last": 0 },
		{ "id": "76561190000000003", "name": "C", "state": "offline", "game_id": "", "last": 900 },
		{ "id": "76561190000000004", "name": "D", "state": "offline", "game_id": "", "last": 100 },
		{ "id": "76561190000000005", "name": "E", "state": "game", "game_id": "440", "last": 0 },
		{ "id": "kaputt", "name": "F", "state": "online" },
	]
	var c := F.candidates(friends, 620, 8)
	var names := c.map(func(f): return str(f.name))
	check(names == ["B", "E", "A", "C", "D"], "erst wer dieses Spiel spielt, dann wer spielt, online, zuletzt gesehen (%s)" % str(names))
	check(F.candidates(friends, 620, 2).size() == 2, "höchstens so viele, wie erlaubt")
	check(str(F.candidates(friends, 620, 8, "76561190000000004")[0].name) == "D", "ein gewünschter Freund steht vorn")
	check(not F.candidates(friends, 0, 8).any(func(f): return str(f.name) == "F"), "ungültige IDs nie (sie gingen als Parameter hinaus)")


func _parse() -> void:
	print("Antworten lesen")
	var ok := F.parse_steam_friend({ "ok": true, "code": 200, "data": { "playerstats": { "success": true, "achievements": [
		{ "apiname": "A", "achieved": 1, "unlocktime": 1700000000 }, { "apiname": "B", "achieved": 0, "unlocktime": 0 },
		{ "apiname": "C", "achieved": 1, "unlocktime": 1700005000 }, { "apiname": "", "achieved": 1 }] } } })
	check(bool(ok.ok) and ok.got == { "A": 1700000000, "C": 1700005000 } and int(ok.total) == 4 and int(ok.last) == 1700005000,
			"Steam: freigeschaltete mit Zeit, Gesamtzahl, letzte Zeit")
	var priv := F.parse_steam_friend({ "ok": false, "code": 403, "data": { "playerstats": { "success": false, "error": "Profile is not public" } } })
	check(not bool(priv.ok) and priv.reason == "Profil privat", "privat erkannt")
	var thr := F.parse_steam_friend({ "ok": false, "code": 429, "data": null })
	check(not bool(thr.ok) and bool(thr.get("throttled", false)), "Drosselung erkannt")
	check(not bool(F.parse_steam_friend({}).ok) and not bool(F.parse_steam_friend({ "ok": true, "code": 200, "data": { "playerstats": { "achievements": "x" } } }).ok),
			"leer oder kaputt: nicht ok, kein Absturz")
	var fl := F.parse_ra_following({ "Count": 2, "Total": 2, "Results": [
		{ "User": "pixelpaul", "AvatarUrl": "https://media.retroachievements.org/UserPic/pixelpaul.png", "Points": 100, "PointsSoftcore": 5 },
		{ "User": "böse<script>", "Points": 1 }, { "User": "Nora_B", "AvatarUrl": "http://nein", "Points": "7" }, "kaputt"] })
	check(fl.size() == 2 and str(fl[0].id) == "pixelpaul" and int(fl[1].points) == 7, "RA-Gefolgte: nur saubere Namen, Punkte als Zahl")
	check(str(fl[1].avatar).begins_with("https://media.retroachievements.org/UserPic/"), "Bild nur über https, sonst die Standard-Adresse")
	check(F.parse_ra_following(null).is_empty() and F.parse_ra_following([{ "User": "x_y" }]).size() == 1, "auch als Liste lesbar")
	var pr := F.parse_ra_friend({ "Achievements": { "1": { "ID": 1, "DateEarnedHardcore": "2024-05-01 10:00:00" },
		"2": { "ID": 2, "DateEarned": "2024-05-02 11:00:00" }, "3": { "ID": 3 }, "4": "kaputt" } })
	check(bool(pr.ok) and int(pr.total) == 3 and int(pr.count) == 2 and pr.got.has("1") and pr.got.has("2") and int(pr.last) > 0,
			"RA-Freund: Hardcore oder Softcore zählt, offene nicht")
	check(not bool(F.parse_ra_friend(null).ok) and not bool(F.parse_ra_friend({ "Achievements": [] }).ok), "RA: ohne Daten nicht ok")


func _who() -> void:
	print("Wer hat ihn, und der Satz dazu")
	var rows := [
		{ "id": "1", "name": "Mira", "ok": true, "got": { "A": 1000, "B": 50 } },
		{ "id": "2", "name": "Jonas", "ok": true, "got": { "A": 2000 } },
		{ "id": "3", "name": "Kai", "ok": false, "got": { "A": 9999 } },
	]
	check(F.who_has(rows, "A") == ["Jonas", "Mira"] and F.who_has(rows, "B") == ["Mira"] and F.who_has(rows, "C").is_empty(),
			"neueste zuerst, nur sichtbare Freunde")
	check(F.who_has(rows, "A", 1) == ["Jonas"] and F.latest_of(rows, "A") == 2000 and F.latest_of(rows, "C") == 0, "Höchstzahl und letzte Zeit")
	check(F.who_text([], true) == "Nur du" and F.who_text(["Mira"], true) == "Du und Mira" and F.who_text(["Mira", "Jonas"], true) == "Du, Mira und Jonas",
			"freigeschaltet: Nur du / Du und Mira / Du, Mira und Jonas")
	check(F.who_text(["Mira", "Jonas", "Lea"], true) == "Du, Mira und 2 weitere", "viele: Du, Mira und 2 weitere")
	check(F.who_text([], false) == "" and F.who_text(["Mira"], false, "gestern") == "Mira hat das gestern freigeschaltet"
			and F.who_text(["Mira"], false) == "Mira hat das schon", "offen: Mira hat das gestern freigeschaltet")
	check(F.who_text(["Mira", "Jonas"], false) == "Mira und Jonas haben das schon" and F.who_text(["Mira", "Jonas", "Lea"], false) == "Mira und 2 weitere haben das schon",
			"offen, mehrere")
	var now := int(Time.get_unix_time_from_system())
	# Genau jetzt (nicht „vor 30 s“): kurz nach Mitternacht läge das sonst schon gestern.
	check(F.when_text(now) == "gerade eben" and F.when_text(0) == "", "„gerade eben“ klein, leer ohne Zeit")
	var wt := F.when_text(now - 3 * 86400)
	check(wt == "vor 3 Tagen" or wt == "vor 4 Tagen", "„vor 3 Tagen“ klein geschrieben (%s)" % wt)
	var lang := F.when_text(now - 40 * 86400)
	check(lang.begins_with("vor ") or lang.begins_with("am "), "lange her: „vor 5 Wochen“ bzw. „am <Datum>“ (%s)" % lang)


func _ranking() -> void:
	print("Ranglisten")
	var rows := [
		{ "id": "1", "name": "Mira", "ok": true, "count": 21, "total": 42, "got": {} },
		{ "id": "2", "name": "Jonas", "ok": true, "count": 29, "total": 42, "got": {} },
		{ "id": "3", "name": "Kai", "ok": false, "count": 0, "total": 0, "got": {} },
		{ "id": "4", "name": "Ben", "ok": true, "count": 21, "total": 42, "got": {} },
	]
	var r := F.ranking(rows, { "id": "me", "name": "Spieler 1", "count": 29, "total": 42 })
	var order := r.map(func(x): return "%s%d" % [x.name, x.rank])
	check(order == ["Spieler 11", "Jonas1", "Ben3", "Mira3"], "gleiche Zahl, gleicher Rang; du vor dem Freund; unsichtbare fehlen (%s)" % str(order))
	check(bool(r[0].me) and int(r[2].total) == 42, "du markiert, Gesamtzahl übernommen")
	var now := int(Time.get_unix_time_from_system())
	var feed := [
		{ "friend_id": "1", "friend": "Mira", "date": now - 3600 }, { "friend_id": "1", "friend": "Mira", "date": now - 7200 },
		{ "friend_id": "2", "friend": "Jonas", "date": now - 86400 }, { "friend_id": "2", "friend": "Jonas", "date": now - 30 * 86400 },
		{ "friend_id": "", "date": now }, "kaputt",
	]
	var w := F.weekly(feed, [now - 100, now - 200, now - 20 * 86400], { "id": "me", "name": "Du" }, now)
	var wo := w.map(func(x): return "%s%d" % [x.name, x.rank])
	check(wo == ["Du1", "Mira1", "Jonas3"], "Woche: nur die letzten 7 Tage, du mitgezählt, Gleichstand (%s)" % str(wo))
	check(int(w[0].count) == 2 and int(w[2].count) == 1 and int(w[1].last) == now - 3600, "Zahlen und letzte Zeit")
	check(RankTile.shift_for(2, 0, 414.0, 20.0) == 868.0 and RankTile.shift_for(0, 1, 414.0, 20.0) == -434.0, "Plätze rücken: Weg vom alten Platz")
	check(RankTile.shift_for(-1, 0, 414.0, 20.0) == 0.0 and RankTile.shift_for(3, 3, 414.0, 20.0) == 0.0, "neu oder gleich: kein Weg")
	RankTile.remember("test", ["a", "b", "c"])
	check(RankTile.memory.test == { "a": 0, "b": 1, "c": 2 }, "Plätze gemerkt")


func _reachable() -> void:
	print("Als Nächstes greifbar")
	var lists := [
		{ "source": "steam", "appid": 1, "title": "A", "list": [
			{ "id": "a1", "title": "leicht", "unlocked": false, "rarity": 80.0 }, { "id": "a2", "title": "mittel", "unlocked": false, "rarity": 60.0 },
			{ "id": "a3", "title": "noch eins", "unlocked": false, "rarity": 50.0 }, { "id": "a4", "title": "hab ich", "unlocked": true, "rarity": 90.0 },
			{ "id": "a5", "title": "geheim", "unlocked": false, "rarity": 70.0, "hidden": true }, { "id": "a6", "title": "schwer", "unlocked": false, "rarity": 3.0 }] },
		{ "source": "ra", "ra_id": 7, "title": "B", "list": [{ "id": "b1", "title": "retro", "unlocked": false, "rarity": 66.0, "points": 5 }] },
		{ "source": "steam", "appid": 2, "title": "C", "error": "x", "list": [{ "id": "c1", "unlocked": false, "rarity": 99.0 }] },
	]
	var r := F.reachable(lists, 8, 2)
	var ids := r.map(func(x): return str(x.id))
	check(ids == ["a1", "b1", "a2"], "häufigste zuerst, höchstens zwei je Spiel, keine geheimen, keine Fehlerlisten (%s)" % str(ids))
	check(str(r[1].source) == "ra" and int(r[1].game_id) == 7 and int(r[1].points) == 5 and str(r[0].gk) == "steam:1", "Quelle und Kennung")
	check(F.reachable(lists, 1).size() == 1 and F.reachable(lists, 8, 2, 70.0).size() == 1, "Grenze und Mindestanteil")


func _feed() -> void:
	print("Feed und Frische")
	var now := 1_800_000_000
	var a := [{ "friend_id": "1", "gk": "steam:1", "id": "x", "date": now - 100 }, { "friend_id": "1", "gk": "steam:1", "id": "y", "date": now - 10 * 86400 }]
	var b := [{ "friend_id": "1", "gk": "steam:1", "id": "x", "date": now - 100 }, { "friend_id": "2", "gk": "ra:7", "id": "z", "date": now - 50 },
		{ "friend_id": "2", "gk": "ra:7", "id": "zukunft", "date": now + 90000 }, 5]
	var m := F.merge_feed([a, b], now)
	check(m.size() == 2 and str(m[0].id) == "z" and str(m[1].id) == "x", "neueste zuerst, nichts doppelt, nur 7 Tage, nichts aus der Zukunft")
	check(F.merge_feed([a, b], now, 1).size() == 1, "Höchstzahl")
	check(F.fresh({ "at": now - 100 }, now) and not F.fresh({ "at": now - F.TTL - 1 }, now) and not F.fresh({}, now), "Stand gilt TTL Sekunden")
	# Gemerkter Feed (je Profil, damit die Seite sofort etwas zeigt): geprüft wie fremde Daten.
	var gut := { "source": "steam", "friend_id": "76561190000000004", "friend": "Mira\u0007", "avatar": "http://x/a.jpg",
		"icon": "https://cdn/x.jpg", "id": "ACH_1", "title": "Erster Sieg", "game": "Spiel", "appid": 10, "date": now - 300, "rarity": 12.5 }
	var g := F.gemerkt_lesen({ "at": now - 600, "list": [gut, { "source": "evil", "friend": "x", "title": "t", "id": "i" }, "kaputt", 7] }, now)
	check(not g.is_empty() and (g.list as Array).size() == 1, "gemerkter Feed: nur gültige Einträge")
	var e0: Dictionary = g.list[0]
	check(str(e0.friend) == "Mira" and str(e0.avatar) == "" and str(e0.icon) == "https://cdn/x.jpg" and str(e0.gk) == "steam:10",
		"Steuerzeichen weg, nur https-Bilder, Kennung neu gebildet")
	check(F.gemerkt_lesen({ "at": now - F.FEED_ALT - 1, "list": [gut] }, now).is_empty() and F.gemerkt_lesen("x", now).is_empty()
		and F.gemerkt_lesen({ "at": "1", "list": [gut] }, now).is_empty(), "zu alt oder kaputt: nichts")
	var viele: Array = []
	for i in 200:
		var c := gut.duplicate()
		c["id"] = "A%d" % i
		viele.append(c)
	check((F.gemerkt_lesen({ "at": now, "list": viele }, now).list as Array).size() == F.FEED_MAX, "höchstens FEED_MAX Einträge")
	var src := FileAccess.get_file_as_string("res://src/core/achievements_friends.gd")
	var feed_src := src.substr(src.find("func feed(force"), 2200)
	check(feed_src.contains("_quelle(box, _feed_steam") and feed_src.contains("_quelle(box, _feed_ra") and feed_src.contains("FEED_FRIST"),
		"Steam und RetroAchievements gleichzeitig, mit Frist")
	check(src.contains("func _infos(") and src.count("_dazu(gen,") >= 3, "Erfolgslisten einer Welle gleichzeitig, Teilergebnisse gleich an die Seite")


## Kommt auf die Abfragen keine Antwort (kein Netz, Drosselung), bleibt der bekannte Stand stehen. Früher stand dann
## eine leere Liste da, und sie wurde auch so gemerkt.
func _ausfall() -> void:
	print("Feed ohne Antwort")
	check(F.ausgefallen({ "ok": false, "code": 0 }) and F.ausgefallen({ "ok": false, "code": 429 }) and F.ausgefallen({ "ok": false, "code": 503 })
			and not F.ausgefallen({ "ok": false, "code": 403 }) and not F.ausgefallen({ "ok": true, "code": 200 }),
			"ausgefallen: kein Netz, Drosselung, Störung – ein „privat“ ist eine Antwort")
	var fr: Node = Achievements.friends
	var now := int(Time.get_unix_time_from_system())
	var alt := { "source": "steam", "friend_id": "76561190000000004", "friend": "Mira", "id": "A1", "title": "Erster", "game": "Spiel",
		"gk": "steam:10", "date": now - 3600 }
	var war := [fr.demo, fr._gemerkt, fr._feed, fr.paused_until]
	fr.demo = false
	fr._gemerkt = true
	fr._feed = { "at": now - F.TTL - 5, "list": [alt] }
	fr.paused_until = now + 100
	var l: Array = await fr.feed()
	check(l.size() == 1 and str(l[0].id) == "A1" and fr.feed_cached().size() == 1, "Drosselung: der bekannte Stand bleibt stehen")
	check(int(fr._feed.at) == now - F.TTL - 5 and fr.feed_frisch() and not fr.feed_loading(), "er gilt weiter als alt, wird aber nicht sofort wieder gefragt")
	fr._feed_ruhe_bis = 0
	check(not fr.feed_frisch(), "nach der Ruhezeit wird neu gefragt")
	fr.demo = war[0]
	fr._gemerkt = war[1]
	fr._feed = war[2]
	fr.paused_until = war[3]
	var liste := [{ "count": 3, "me": false, "name": "Zoe" }, { "count": 5, "me": false, "name": "Ben" }, { "count": 3, "me": true, "name": "Du" }]
	var r := F._raenge(liste)
	check(str(r[0].name) == "Ben" and int(r[0].rank) == 1 and str(r[1].name) == "Du" and int(r[1].rank) == 2 and int(r[2].rank) == 2,
			"Ränge: meiste zuerst, bei Gleichstand du vorn, gleiche Zahl gleicher Rang")
	check(F.sane("Mi\u202Era\u2066!") == "Mira!" and F.sane("a\tb\rc") == "abc", "Namen ohne umgedrehte Schreibrichtung")


func _popup() -> void:
	print("Pop-up „komplett“")
	check(Un.complete_after(42, 41, 1) and Un.complete_after(42, 40, 2) and not Un.complete_after(42, 40, 1) and not Un.complete_after(0, 0, 1)
			and not Un.complete_after(5, 5, 0), "komplett nur mit bekannter Gesamtzahl und wirklich letztem Erfolg")
	var d := Un.decorate({ "rarity": 2.1, "platform": "steam", "complete": true })
	check(d.variant == "komplett" and d.rare and d.sound == "unlock_rare" and d.sound2 == "unlock" and d.chip == "100 %"
			and d.line1.begins_with("Alle Erfolge freigeschaltet"), "komplett: Gold, zwei Klänge, Chip 100 %")
	var dr := Un.decorate({ "rarity": -1.0, "platform": "ra", "complete": true, "hardcore": true, "ra_points": 25 })
	check(dr.variant == "komplett" and dr.chip == "Gemeistert" and dr.line1 == "Alle Erfolge freigeschaltet", "RetroAchievements komplett: „Gemeistert“")
	check(Un.decorate({ "rarity": 2.1, "platform": "steam" }).variant == "rare", "ohne complete wie bisher")
	check(Toast.PALETTES.has("komplett") and int(Toast.PALETTES.komplett.sweeps) == 2 and int(Toast.PALETTES.komplett.glints) == 1, "eigene Farben mit Funken")
	var hold := 4.6
	check(Toast.frame(0.05, hold, 2, true).glint < 0.0 and Toast.frame(0.5, hold, 2, true).glint > 0.0 and Toast.frame(2.5, hold, 2, true).glint < 0.0,
			"Funken nach dem Aufspringen, höchstens bis 2,4 s")
	check(Toast.frame(0.5, hold, 2, false).glint < 0.0 and Toast.frame(0.5, hold).glint < 0.0, "ohne glints keine Funken")
	check(Toast.frame(1.5, 1.0, 2, true).glint >= 0.0 and Toast.frame(2.1, 1.0, 2, true).glint < 0.0,
			"kurzes Halten (viele warten): Funken nur, solange die Pille steht")
	var f := Toast.frame(1.2, hold, 2, true)
	check(f.l1a == 1.0 and f.wk == 1.0, "Zeitplan der Pille unverändert")


func _demo() -> void:
	print("Beispieldaten (ohne Netz)")
	var fr: Node = Achievements.friends
	check(fr != null and fr.get_parent() == Achievements, "Freunde-Modul hängt an Achievements")
	fr.demo = true
	Achievements.demo = true
	if Social.steam_friends.is_empty():
		Social.call("_load_demo")
	var b: Dictionary = await fr.board({ "source": "steam", "appid": 1245620 }, false, "76561190000000004")
	check(bool(b.ok) and str(b.key) == "steam:1245620" and int(b.total) == 42 and not (b.rows as Array).is_empty(), "Stand für Elden Ring")
	check(str(b.rows[0].id) == "76561190000000004", "gewünschter Freund steht vorn")
	var mira: Dictionary = b.rows.filter(func(r): return str(r.name) == "Mira")[0]
	check(bool(mira.ok) and int(mira.count) > 0 and int(mira.count) <= 42 and int(mira.last) > 0, "Mira hat einen Teil (%d von 42)" % int(mira.count))
	var kai: Array = b.rows.filter(func(r): return str(r.name) == "Kai")
	check(kai.is_empty() or (not bool(kai[0].ok) and str(kai[0].reason) == "Profil privat"), "Kai: Profil privat")
	var again: Dictionary = await fr.board({ "source": "steam", "appid": 1245620 })
	check(again == b, "zweite Frage kommt aus dem Speicher")
	var fl: Array = await fr.following()
	check(fl.size() == 3 and str(fl[0].id) == "pixelpaul", "RA: drei Gefolgte in der Demo")
	var rb: Dictionary = await fr.board({ "source": "ra", "ra_id": 2771 })
	check(bool(rb.ok) and int(rb.total) == 52 and (rb.rows as Array).size() == 3, "Stand für Ōkami über die Gefolgten")
	var feed: Array = await fr.feed()
	check(fr.feed_ready() and not feed.is_empty() and feed.size() <= F.FEED_MAX, "Feed mit Einträgen (%d)" % feed.size())
	var sorted := true
	for i in range(1, feed.size()):
		if int(feed[i].date) > int(feed[i - 1].date):
			sorted = false
	check(sorted and feed.all(func(e): return str(e.friend) != "" and str(e.title) != "" and str(e.game) != ""), "neueste zuerst, jeder Eintrag vollständig")
	var now := int(Time.get_unix_time_from_system())
	var w := F.weekly(feed, fr.my_recent_dates(), fr.me(), now)
	check(w.size() >= 2 and w.any(func(r): return bool(r.me)) and int(w[0].rank) == 1, "Rangliste der Woche mit dir")
	await Achievements.for_game({ "id": "gc:5afbe7cb37a915", "source": "rom" })
	var reach: Array = Achievements.reachable(8)
	check(not reach.is_empty() and reach.all(func(a): return float(a.rarity) >= 35.0 and not bool(a.get("unlocked", false))),
			"Greifbares aus den bekannten Listen (%d)" % reach.size())
	# Nichts im Datenordner selbst (der gemerkte Feed liegt nur als Zwischenspeicher im Profil, in der Demo gar nicht).
	var leak := false
	for f in DirAccess.get_files_at(Config.path("")):
		if str(f).to_lower().contains("friend") or str(f).to_lower().contains("freund"):
			leak = true
	check(not leak, "keine Datei mit Freundesdaten im Datenordner")
