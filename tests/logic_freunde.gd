extends Node
## Logik des Bereichs Freunde ohne Oberfläche: Steam-Profil aus der Web-API (privat,
## öffentlich, gemeinsame Spiele), Links im Chat, Gruppen und Tage im Verlauf, Texte.
## Wer online kommt: Status vom Chat-Server einrechnen, Discord-Meldungen bündeln, die Liste
## auffrischen ohne Neuaufbau und ohne Fokusverlust.
## Aufruf: godot --headless --path . res://tests/logic_freunde.tscn

const ChatView := preload("res://src/ui/layers/chat_view.gd")
const ChatLink := preload("res://src/ui/layers/chat_link.gd")
const FriendsView := preload("res://src/ui/sections/friends_view.gd")
const GuideFriend := preload("res://src/ui/components/guide_friend.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Steam-Profil")
	var sm := Social.parse_summary({ "response": { "players": [{ "steamid": "7656", "personaname": "Mira", "personastate": 1,
		"gameextrainfo": "ELDEN RING", "gameid": "1245620", "communityvisibilitystate": 3, "timecreated": 1338595200,
		"avatarfull": "https://a/full.jpg", "lobbysteamid": "1097" }] } })
	check(sm.state == "game" and sm.game == "ELDEN RING" and sm.game_id == "1245620", "Spiel aus GetPlayerSummaries")
	check(bool(sm.public) and int(sm.created) == 1338595200 and sm.avatar == "https://a/full.jpg", "öffentlich, Erstellt, großes Bild")
	check(Social.parse_summary({ "response": { "players": [] } }).is_empty() and Social.parse_summary(null).is_empty(), "leere Antwort ergibt nichts")
	check(Social.parse_summary({ "response": { "players": [{ "personastate": 3 }] } }).state == "away", "Status abwesend")
	check(Social.parse_level({ "response": { "player_level": 42 } }) == 42, "Level")
	check(Social.parse_level({ "response": {} }) == -1 and Social.parse_level(null) == -1, "Level privat oder unbekannt")
	var rp := Social.parse_recent({ "response": {} })
	check(bool(rp.private) and (rp.games as Array).is_empty(), "Zuletzt gespielt privat (leere Antwort)")
	var r0 := Social.parse_recent({ "response": { "total_count": 0 } })
	check(not bool(r0.private) and (r0.games as Array).is_empty(), "öffentlich, aber nichts gespielt")
	var r2 := Social.parse_recent({ "response": { "total_count": 2, "games": [
		{ "appid": 10, "name": "A", "playtime_2weeks": 30, "playtime_forever": 100 },
		{ "appid": 20, "name": "B", "playtime_2weeks": 300, "playtime_forever": 900 }] } })
	check(int(r2.games[0].appid) == 20 and int(r2.games[0].two_weeks) == 300 and int(r2.games[1].total) == 100, "nach Spielzeit der zwei Wochen sortiert")
	var op := Social.parse_owned({ "response": {} })
	check(bool(op.private), "Bibliothek privat")
	var ow := Social.parse_owned({ "response": { "game_count": 3, "games": [
		{ "appid": 1, "name": "Eins", "playtime_forever": 50 }, { "appid": 2, "name": "Zwei", "playtime_forever": 5000 },
		{ "appid": 3, "name": "Drei", "playtime_forever": 0 }] } })
	check(not bool(ow.private) and (ow.games as Array).size() == 3, "Bibliothek gelesen")
	var sh := Social.shared_games(ow.games, { 2: 60, 3: 600, 99: 1 })
	check(sh.size() == 2 and int(sh[0].appid) == 2 and int(sh[0].mine) == 60 and int(sh[0].theirs) == 5000, "gemeinsame Spiele, meistgespielte zuerst")
	var tg := Social.top_game(ow.games)
	check(int(tg.get("appid", 0)) == 2 and Social.top_game([]).is_empty(), "meistgespieltes Spiel für die Kennzahlen")
	var since := Social.parse_since({ "friendslist": { "friends": [{ "steamid": "7656", "relationship": "friend", "friend_since": 1552521600 }] } })
	check(int(since.get("7656", 0)) == 1552521600, "befreundet seit aus GetFriendList")
	var known := { "id": "7656", "name": "Mira", "state": "online", "since": 1552521600 }
	var off := Social.build_profile("7656", known, null, null, null, null, {}, 0)
	check(bool(off.ok) and str(off.error) != "" and str(off.name) == "Mira", "ohne Netz: bekannte Angaben und ein Hinweis statt leerer Seite")
	check(not bool(off.recent_private) and not bool(off.games_private), "ohne Antwort gilt nichts als privat")
	var full := Social.build_profile("7656", known, { "response": { "players": [{ "steamid": "7656", "personaname": "Mira", "personastate": 1 }] } },
		{ "response": { "player_level": 42 } }, { "response": { "total_count": 0 } }, { "response": {} }, { 2: 60 }, 0)
	check(str(full.error) == "" and int(full.level) == 42 and int(full.since) == 1552521600, "Profil mit Level, befreundet seit aus der Liste")
	check(bool(full.games_private) and (full.shared as Array).is_empty() and not bool(full.recent_private),
			"private Bibliothek: keine gemeinsamen Spiele, sauber markiert")
	var dp := Social.demo_profile("76561190000000001", { "since": 1552521600 }, { 1245620: 7200, 1145360: 2800 })
	check(int(dp.level) == 42 and (dp.recent as Array).size() == 3 and (dp.shared as Array).size() == 2, "Beispielprofil für den Rundgang")
	check(str(dp.top.get("name", "")) == "Dota 2", "Beispielprofil: meistgespielt")
	var dk := Social.demo_profile("76561190000000007", {}, {})
	check(bool(dk.recent_private) and bool(dk.games_private) and int(dk.level) == -1, "Beispiel: privates Profil")
	check(Social.month_year(1552564800) == "März 2019", "Monat und Jahr")
	check(Social.hours(45) == "45 Min." and Social.hours(90) == "1,5 Std." and Social.hours(120) == "2 Std." and Social.hours(12720) == "212 Std.",
			"Spielzeit kurz")
	check(Social.join_url({ "id": "7656", "game_id": "730", "lobby": "1097", "server": "" }) == "steam://joinlobby/730/1097/7656",
			"Beitreten bleibt (startet das Spiel)")

	print("Links im Chat")
	var ls := ChatLink.find_links("Schau: https://x.de/a). Und www.example.com/b, ok?")
	check(ls.size() == 2 and str(ls[0].url) == "https://x.de/a" and str(ls[1].url) == "www.example.com/b", "Links ohne Satzzeichen am Ende")
	var lw := ChatLink.find_links("(siehe https://de.wikipedia.org/wiki/Okami_(Spiel))")
	check(lw.size() == 1 and str(lw[0].url) == "https://de.wikipedia.org/wiki/Okami_(Spiel)", "Klammern im Link bleiben, die äußere nicht")
	check(ChatLink.find_links("kein link hier, nur text.").is_empty(), "Text ohne Link")
	var yt := ChatLink.link_info("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10")
	check(yt.kind == "youtube" and yt.id == "dQw4w9WgXcQ", "YouTube (watch)")
	check(ChatLink.link_info("https://youtu.be/dQw4w9WgXcQ").id == "dQw4w9WgXcQ"
			and ChatLink.link_info("https://youtube.com/shorts/dQw4w9WgXcQ").kind == "youtube", "YouTube (kurz, Shorts)")
	var sp := ChatLink.link_info("https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC?si=x")
	check(sp.kind == "spotify" and sp.id == "spotify:track:4uLU6hMCjMI75M1A2tKUQC", "Spotify-Titel spielt in Uzai")
	check(ChatLink.link_info("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M").id == "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", "Spotify-Playlist")
	var st := ChatLink.link_info("https://store.steampowered.com/app/1245620/ELDEN_RING/")
	check(st.kind == "store" and st.id == "1245620", "Steam-Shopseite in Uzai")
	check(ChatLink.link_info("steam://joinlobby/730/1097/7656").kind == "join", "Beitreten-Link")
	var web := ChatLink.link_info("www.reddit.com/r/x")
	check(web.kind == "web" and web.host == "reddit.com" and str(web.url).begins_with("https://"), "sonstige Seite: aufs Handy")
	check(ChatLink.host_of("https://user@WWW.Example.com:8080/x?y=1") == "example.com", "Adresse ohne www, Port und Anmeldung")
	check(ChatLink.short_url("https://www.example.com/abc") == "example.com/abc", "Link kurz")
	check(ChatLink.short_url("https://example.com/" + "a".repeat(80), 42).length() == 42, "langer Link in der Mitte gekürzt")
	var og := ChatLink.og_meta('<html><head><title>Fallback</title><meta content="Bester Build &amp; mehr" property="og:title"><meta name="description" content=\'Tipps f&#252;r Anf&#x00E4;nger\'></head>')
	check(og.title == "Bester Build & mehr" and og.desc == "Tipps für Anfänger", "Vorschau: Titel und Beschreibung (Open Graph)")
	check(ChatLink.og_meta("<title>\n  Nur Titel </title>").title == "Nur Titel", "Vorschau: sonst der <title>")

	print("Chat-Verlauf")
	var now := 1760500000
	var msgs := [
		{ "me": false, "text": "a", "at": now - 3 * 86400 },
		{ "me": false, "text": "b", "at": now - 600 },
		{ "me": false, "text": "c", "at": now - 500 },
		{ "me": true, "text": "d", "at": now - 450 },
		{ "me": false, "text": "e", "at": now - 10 },
	]
	var lay := ChatView.layout(msgs, now)
	var days := lay.filter(func(e): return e.type == "day").map(func(e): return str(e.text))
	check(days.size() == 2 and days[1] == "Heute", "Tage getrennt (%s)" % ", ".join(PackedStringArray(days)))
	var ms := lay.filter(func(e): return e.type == "msg")
	check(bool(ms[1].first) and not bool(ms[1].last) and not bool(ms[2].first) and bool(ms[2].last), "gleiche Person in 5 Minuten: eine Gruppe")
	check(bool(ms[3].first) and bool(ms[3].last) and bool(ms[4].first), "Wechsel der Person beginnt eine neue Gruppe")
	check(ChatView.day_label(now - 86400, now) == "Gestern" and ChatView.day_label(now, now) == "Heute", "Heute und Gestern")
	check(ChatView.day_label(now - 3 * 86400, now) in ChatView.WEEKDAYS, "diese Woche: Wochentag")
	check(ChatView.day_label(now - 40 * 86400, now).ends_with("September") or ChatView.day_label(now - 40 * 86400, now).contains(". "), "älter: Tag und Monat")
	check(ChatView.day_label(now - 400 * 86400, now).ends_with("2024"), "anderes Jahr mit Jahreszahl")
	check(ChatView.last_seen(now - 30, now) == "gerade eben" and ChatView.last_seen(now - 7300, now) == "vor 2 Std."
			and ChatView.last_seen(now - 3 * 86400 - 10, now) == "vor 3 Tagen", "zuletzt online")
	check(ChatView.status_line({ "game": "Hades", "state": "game" }) == "Spielt Hades" and ChatView.status_line({ "state": "busy" }) == "Beschäftigt",
			"Zeile unter dem Namen")
	check(ChatView.status_line({ "state": "offline", "last": 0 }) == "Offline", "offline ohne Zeit")
	check(ChatView.msg_key({ "me": true, "text": "x", "at": 5 }) != ChatView.msg_key({ "me": false, "text": "x", "at": 5 }),
			"eigene und fremde Nachricht unterscheidbar")

	print("Angehefteter Chat neben dem Guide")
	var Guide := load("res://src/ui/layers/guide.gd")
	ChatView.pin_loesen()
	check(ChatView.pin_jetzt(now).is_empty(), "ohne geöffneten Chat: keine Spalte")
	ChatView.pin_merken({ "id": "s1", "name": "Ana" }, "steam", now - 100)
	var pj := ChatView.pin_jetzt(now)
	check(str(pj.get("kind", "")) == "steam" and str((pj.get("friend", {}) as Dictionary).get("id", "")) == "s1", "zuletzt geöffnetes Gespräch")
	check(ChatView.pin_jetzt(now + ChatView.PIN_SECS + 1).is_empty(), "lange her: keine Spalte mehr")
	ChatView.pin_merken({ "id": "d7", "name": "Bo" }, "discord", now)
	check(str(ChatView.pin_jetzt(now).kind) == "discord", "Discord genauso, das neueste zählt")
	ChatView.pin_loesen()
	check(ChatView.pin_jetzt(now).is_empty(), "X: zu, bis wieder ein Chat aufgeht")
	ChatView.pin_merken({ "id": "", "name": "?" }, "steam", now)
	check(ChatView.pin_jetzt(now).is_empty(), "ohne Kennung: nichts")
	ChatView.pin_loesen()
	var pr: Rect2 = Guide.pin_rect(Vector2(1920, 1080))
	check(pr.position.x >= Guide.PANEL_W + Guide.PIN_GAP and is_equal_approx(pr.end.x, 1920.0 - Guide.PIN_GAP) and pr.size.x == ChatView.PIN_W,
			"Spalte ganz rechts am Schirm, nicht an der Leiste (%s)" % str(pr))
	check(Guide.pin_rect(Vector2(800, 600)).size.x == 0.0, "zu schmal: keine Spalte")
	var cvs := FileAccess.get_file_as_string("res://src/ui/layers/chat_view.gd")
	check(cvs.contains("and not angeheftet:\n\t\tNav.focus(_composer, true)"), "angeheftet: nimmt dem Guide nicht den Fokus")

	print("Reiter: Zahlen")
	var keep_vd := Voice.demo
	var keep_df := DiscordChat.friends
	var keep_dd := DiscordChat.demo
	var keep_br := Voice.browse
	Voice.demo = true
	Voice.browse = [{ "id": "c1", "name": "Zocken", "members": [{ "name": "A" }, { "name": "B" }, { "name": "C" }] }]
	DiscordChat.demo = false
	DiscordChat.friends = []
	var fv = FriendsView.new()
	var dtab: Dictionary = {}
	for t in fv.subtabs():
		if str(t.id) == "discord":
			dtab = t
	check(not dtab.is_empty() and not dtab.has("count"), "Discord ohne Freundesliste: keine Zahl (nicht die Leute im Sprachkanal)")
	DiscordChat.demo = true
	DiscordChat.friends = [{ "id": "1", "state": "online" }, { "id": "2", "state": "offline" }, { "id": "3", "state": "game" }]
	for t in fv.subtabs():
		if str(t.id) == "discord":
			dtab = t
	check(int(dtab.get("count", -1)) == 2, "Discord: Freunde online")
	fv.free()
	Voice.demo = keep_vd
	Voice.browse = keep_br
	DiscordChat.friends = keep_df
	DiscordChat.demo = keep_dd

	_presence()
	await _discord_events()
	await _soft_refresh()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _f(id: String, name_: String, st: String, game := "", gid := "") -> Dictionary:
	return { "id": id, "name": name_, "avatar": "", "state": st, "game": game, "game_id": gid, "last": 0, "lobby": "", "server": "", "since": 0 }


func _presence() -> void:
	print("Status vom Chat-Server")
	var titles := func(appid: int) -> String: return "Hades" if appid == 1145360 else ""
	var off := _f("7", "Lea", "offline")
	off["last"] = 50
	var on := Social.merge_persona(off, { "id": "7", "status": true, "state": 1, "app_id": 0, "game_id": "", "game_name": "", "server": "" }, 1000, titles)
	check(str(on.state) == "online" and int(on.last) == 50, "offline → online")
	var pl := Social.merge_persona(on, { "id": "7", "status": true, "state": 1, "app_id": 1145360, "game_id": "1145360", "game_name": "", "server": "" }, 1000,
			titles)
	check(str(pl.state) == "game" and str(pl.game) == "Hades" and str(pl.game_id) == "1145360", "startet ein Spiel: Name aus der Bibliothek")
	var unk := Social.merge_persona(on, { "id": "7", "status": true, "state": 1, "app_id": 570, "game_id": "570", "game_name": "", "server": "" }, 1000, titles)
	check(str(unk.state) == "game" and str(unk.game) == Social.GAME_UNKNOWN, "unbekanntes Spiel: vorläufiger Name, die Web-API liefert ihn nach")
	# Quelle in der Liste: nur das Zeichen, kein Schriftzug (Discord-Logo: Zeichen links, Lücke, „Discord“).
	var logo := Image.create(300, 100, false, Image.FORMAT_RGBA8)
	logo.fill_rect(Rect2i(5, 10, 85, 80), Color.WHITE)
	logo.fill_rect(Rect2i(120, 30, 170, 40), Color.WHITE)
	var quadrat := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	quadrat.fill_rect(Rect2i(10, 10, 80, 80), Color.WHITE)
	check(GuideFriend._Logo.nur_zeichen(logo).get_width() == 85 and GuideFriend._Logo.nur_zeichen(quadrat).get_width() == 100,
			"Logo mit Schriftzug: nur das Zeichen; Zeichen allein bleibt")
	# Fremdes Spiel: Name aus dem Shop (appdetails?filters=basic), nur kurzer, druckbarer Text.
	check(Social.app_name_aus({ "570": { "success": true, "data": { "name": "Dota 2" } } }, 570) == "Dota 2", "Shop: Name zur App-ID")
	check(Social.app_name_aus({ "570": { "success": false } }, 570) == "" and Social.app_name_aus({ "571": { "success": true, "data": { "name": "X" } } }, 570) == ""
			and Social.app_name_aus([], 570) == "" and Social.app_name_aus({ "570": { "success": true, "data": "x" } }, 570) == "", "Shop: unbekannt, fremde App oder kaputte Antwort → leer")
	check(Social.app_name_aus({ "570": { "success": true, "data": { "name": " A\u0007B\n " } } }, 570) == "AB"
			and Social.app_name_aus({ "570": { "success": true, "data": { "name": "x".repeat(300) } } }, 570).length() == 120, "Shop: Steuerzeichen raus, Länge begrenzt")
	var keep := pl.duplicate()
	keep["lobby"] = "1097"
	var same := Social.merge_persona(keep, { "id": "7", "status": true, "state": 1, "app_id": 1145360, "game_id": "1145360", "game_name": "", "server": "" }, 1000,
			titles)
	check(str(same.lobby) == "1097" and str(same.game) == "Hades", "gleiches Spiel: Lobby aus der Web-API bleibt")
	var ns := Social.merge_persona(pl,
			{ "id": "7", "status": true, "state": 1, "app_id": 0, "game_id": "15190414816125648896", "game_name": "Zelda", "server": "" }, 1000, titles)
	check(str(ns.game) == "Zelda" and str(ns.state) == "game", "Nicht-Steam-Spiel mit Namen")
	var end := Social.merge_persona(pl, { "id": "7", "status": true, "state": 1, "app_id": 0, "game_id": "", "game_name": "", "server": "" }, 1000, titles)
	check(str(end.state) == "online" and str(end.game) == "" and str(end.game_id) == "", "Spiel beendet")
	var gone := Social.merge_persona(pl, { "id": "7", "status": true, "state": 0 }, 2000, titles)
	check(str(gone.state) == "offline" and str(gone.game) == "" and int(gone.last) == 2000, "geht offline: zuletzt online jetzt")
	var nm := Social.merge_persona(pl, { "id": "7", "status": false, "name": "Lea M." }, 1000, titles)
	check(str(nm.name) == "Lea M." and str(nm.state) == "game" and str(nm.game) == "Hades", "nur der Name: Status bleibt")
	var fresh := Social.merge_persona({}, { "id": "8", "status": true, "state": 3, "name": "Kai" }, 1000, titles)
	check(str(fresh.state) == "away" and str(fresh.name) == "Kai" and fresh.has("lobby") and fresh.has("since"), "neuer Freund: vollständiger Eintrag")
	var list := [_f("1", "Zoe", "offline"), _f("2", "Ann", "online"), _f("3", "Ben", "game", "X", "1"), _f("4", "Al", "online")]
	Social.sort_friends(list)
	check(list.map(func(e): return str(e.name)) == ["Ben", "Al", "Ann", "Zoe"], "Sortierung: Spiel, online (nach Namen), offline")


func _discord_events() -> void:
	print("Discord: Meldungen des SDK")
	var keep_runner: Callable = DiscordChat.runner
	var keep_started := DiscordChat._started
	var keep_demo := DiscordChat.demo
	var keep_friends := DiscordChat.friends
	var answer := { "list": [{ "id": "1", "name": "Sana", "state": "offline" }, { "id": "2", "name": "Kai", "state": "online" }] }
	var calls := [0]
	DiscordChat.runner = func(cmd: String, _args: Dictionary, _t: float) -> Dictionary:
		if cmd == "dsdk-friends":
			calls[0] += 1
			await get_tree().create_timer(0.05).timeout
			return { "ok": true, "result": { "ok": true, "friends": (answer.list as Array).duplicate(true) } }
		return { "ok": true, "result": { "ok": true } }
	DiscordChat.demo = false
	DiscordChat._started = true
	DiscordChat._friends_sig = ""
	var changes := [0]
	var on_ch := func() -> void: changes[0] += 1
	DiscordChat.changed.connect(on_ch)
	for i in 12:
		Helper.dsdk_event.emit({ "type": "user", "id": str(i) })
	await get_tree().create_timer(DiscordChat.FRIENDS_DEBOUNCE + 0.4).timeout
	check(calls[0] == 1, "zwölf Meldungen beim Verbinden: eine Abfrage (%d)" % calls[0])
	check(changes[0] == 1 and DiscordChat.friend("2").get("state", "") == "online", "Freundesliste da, eine Änderung gemeldet")
	answer.list = [{ "id": "1", "name": "Sana", "state": "online", "game": "Balatro" }, { "id": "2", "name": "Kai", "state": "online" }]
	Helper.dsdk_event.emit({ "type": "user", "id": "1" })
	await get_tree().create_timer(DiscordChat.FRIENDS_DEBOUNCE + 0.3).timeout
	check(str(DiscordChat.friend("1").get("state", "")) == "online" and str(DiscordChat.friends[0].name) == "Sana" and changes[0] == 2,
			"Sana kommt online und spielt: steht oben, Änderung gemeldet")
	Helper.dsdk_event.emit({ "type": "user", "id": "2" })
	await get_tree().create_timer(DiscordChat.FRIENDS_DEBOUNCE + 0.3).timeout
	check(calls[0] == 3 and changes[0] == 2, "Meldung ohne Änderung: kein Neuaufbau")
	DiscordChat.refresh_friends()
	DiscordChat.refresh_friends()
	DiscordChat.refresh_friends()
	await get_tree().create_timer(0.4).timeout
	check(calls[0] == 5, "drei Abfragen auf einmal: eine läuft, danach genau eine weitere (%d)" % (calls[0] - 3))
	DiscordChat.changed.disconnect(on_ch)
	DiscordChat.runner = keep_runner
	DiscordChat._started = keep_started
	DiscordChat.demo = keep_demo
	DiscordChat.friends = keep_friends
	DiscordChat._friends_sig = ""


func _key_of(c: Control) -> String:
	return str(c.get_meta("uz_key", "")) if c != null else ""


func _soft_refresh() -> void:
	print("Freunde-Liste: auffrischen ohne Neuaufbau")
	var keep_sf := Social.steam_friends
	Social.steam_friends = [_f("1", "Ann", "online"), _f("2", "Ben", "offline"), _f("3", "Cem", "offline"), _f("4", "Dan", "offline")]
	var fv = FriendsView.new()
	fv.size = Vector2(600, 900)
	add_child(fv)
	fv.sub = "steam"
	fv.build()
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: Dictionary = fv._rows(fv._left)
	check(rows.has("fr:1") and rows.has("fr:4"), "Liste aufgebaut")
	check(fv.get_child_count() == 1 and fv.get_child(0) is ScrollContainer, "nur die Liste, keine Karte daneben")
	Nav.focus(rows["fr:2"], true)
	await get_tree().process_frame
	check(_key_of(Nav.focused()) == "fr:2", "Ben gewählt")
	var sc := fv._left.get_parent() as ScrollContainer
	# Cem kommt online: Liste ordnet sich neu, Ben bleibt gewählt.
	Social.steam_friends = [_f("1", "Ann", "online"), _f("3", "Cem", "online"), _f("2", "Ben", "offline"), _f("4", "Dan", "offline")]
	fv._on_social("steam")
	await get_tree().process_frame
	rows = fv._rows(fv._left)
	check(_key_of(Nav.focused()) == "fr:2" and Nav.focused() == rows.get("fr:2"), "Cem kommt online: Fokus bleibt auf Ben")
	check(fv.get_child_count() == 1 and fv._left.get_parent() == sc, "kein Neuaufbau des Bereichs (Liste und Bildlauf bleiben)")
	var online_rows := 0
	for c in fv._left.get_children():
		if str(c.get_meta("uz_key", "")) == "fr:3":
			break
		if c.has_meta("uz_key"):
			online_rows += 1
	check(online_rows == 1, "Cem steht jetzt unter „Online“ (nach Ann)")
	# Ben selbst kommt online: er rückt nach oben, bleibt aber gewählt.
	Social.steam_friends = [_f("1", "Ann", "online"), _f("2", "Ben", "online"), _f("3", "Cem", "online"), _f("4", "Dan", "offline")]
	fv._on_social("steam")
	await get_tree().process_frame
	check(_key_of(Nav.focused()) == "fr:2" and fv._left.get_parent() == sc, "Ben kommt online: Fokus bleibt")
	# Ben ist nicht mehr da: Fokus an den Anfang.
	Social.steam_friends = [_f("1", "Ann", "online"), _f("3", "Cem", "online"), _f("4", "Dan", "offline")]
	fv._on_social("steam")
	await get_tree().process_frame
	check(_key_of(Nav.focused()) == "fr:1", "Ben weg: Fokus auf den Anfang der Liste")
	fv.queue_free()
	Social.steam_friends = keep_sf
