extends Node
## Steam achievements and your status without the Web API, which rejects the QR login token (so achievements did not
## load and the status kept showing offline): Steam's local files (sample folder tests/fixtures/steam_pc, built by
## make_steam_pc.py), chat server responses (ClientGetUserStats, Player.GetAchievementsProgress#1), your status from
## localconfig.vdf and loginusers.vdf as Uzai shows it, and the log lines.
## Run: godot --headless --path . res://tests/logic_steam_erfolge.tscn

const SE := preload("res://src/core/steam_erfolge.gd")
const PC := preload("res://src/core/steam_am_pc.gd")
const CM := preload("res://src/core/steam_cm.gd")
const Ach := preload("res://src/core/achievements.gd")
const MyStatus := preload("res://src/core/my_status.gd")

const ROOT := "res://tests/fixtures/steam_pc"
const DIR := ROOT + "/appcache/stats"
const ACCT := 12345
const SID := "76561197960278073"     ## STEAM64 + 12345
const SID_OFF := "76561197960266505" ## STEAM64 + 777

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_dateien()
	_liste()
	_chat_server()
	await _status_lokal()
	_status_anzeige()
	_zaehlung()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _dateien() -> void:
	print("Steams Dateien am PC")
	var p := SE.schema_path(DIR, 480)
	check(SE.read_capped(p, 1 << 20).size() > 100, "Schema lesbar")
	check(SE.read_capped(p, 50).is_empty(), "größer als die Grenze: gar nicht gelesen")
	check(SE.read_capped(DIR + "/fehlt.bin", 1 << 20).is_empty(), "fehlende Datei: leer")
	check(SE.account_id(SID) == ACCT and SE.account_id("123") == 0 and SE.account_id("abc") == 0, "Konto-ID aus der SteamID64")
	var lg := SE.local_game(DIR, ACCT, 480)
	check(bool(lg.ok) and bool(lg.has_user) and (lg.bits as Dictionary).size() == 4, "Spacewar: 4 Erfolge im Schema, Spielerdatei da")
	check((lg.got as Dictionary).size() == 2 and int(lg.got.get("ACH_WIN_ONE_GAME", 0)) == 1760000000 and lg.got.has("ACH_TRAVEL_FAR"),
			"2 frei, mit Zeit aus AchievementTimes")
	check(str(lg.title) == "Spacewar", "Spielname aus dem Schema")
	var broken := SE.local_game(DIR, ACCT, 481)
	check(not bool(broken.ok), "abgeschnittenes Schema: nicht benutzt (kein Absturz)")
	var no_user := SE.local_game(DIR, ACCT, 482)
	check(bool(no_user.ok) and not bool(no_user.has_user) and (no_user.got as Dictionary).is_empty(), "Schema ohne Spielerdatei: Stand unbekannt")
	check(SE.local_count(DIR, ACCT, 480) == { "u": 2, "t": 4 } and SE.local_count(DIR, ACCT, 482).is_empty() and SE.local_count(DIR, 999, 480).is_empty(),
			"Zählung: nur mit Schema und eigener Datei")
	var apps := SE.local_apps(DIR, ACCT)
	var ids: Array = apps.map(func(e): return int(e.appid))
	ids.sort()
	check(ids == [480, 481], "eigene Statistik-Dateien im Ordner (%s)" % str(ids))
	check(SE.local_apps(DIR, 0).is_empty() and SE.local_apps("", ACCT).is_empty(), "ohne Konto oder Ordner: nichts")


func _liste() -> void:
	print("Erfolgsliste wie von der Web-API")
	var lg := SE.local_game(DIR, ACCT, 480)
	var list := SE.build_list(480, lg.bits, lg.got, { "ach_win_one_game": 61.5 })
	check(list.size() == 4, "4 Einträge")
	check(str(list[0].id) == "ACH_WIN_ONE_GAME" and str(list[0].title) == "Sieger" and bool(list[0].unlocked) and int(list[0].date) == 1760000000,
			"deutsch, frei, mit Datum")
	check(is_equal_approx(float(list[0].rarity), 61.5) and float(list[1].rarity) == -1.0, "Seltenheit ohne Groß/klein zugeordnet")
	check(str(list[0].icon) == SE.ICONS % [480, "aaa111.jpg"] and str(list[0].icon_locked) == SE.ICONS % [480, "aaa111_g.jpg"], "Bilder vom Steam-Server")
	check(str(list[2].id) == "ACH_TRAVEL_FAR" and not bool(list[2].hidden) and str(list[2].desc) == "Reise weit.", "geheimer Erfolg, frei: Text sichtbar")
	check(str(list[2].icon_locked) == str(list[2].icon), "Bildname mit ../ abgelehnt (Ersatz: das normale Bild)")
	var none := SE.build_list(480, lg.bits, {}, {})
	check(bool(none[2].hidden) and str(none[2].desc) == "Geheimer Erfolg" and str(none[2].secret) == "Reise weit.", "geheimer Erfolg, offen: verdeckt")
	check(SE.icon_url(480, "https://x.y/z.jpg") == "" and SE.icon_url(480, "..") == "" and SE.icon_url(0, "a.jpg") == "", "nur schlichte Dateinamen")
	check(SE.clean("a\nb\u0007c", 10) == "a b c" and SE.clean("x".repeat(500), 20).length() == 20, "fremde Texte: ohne Steuerzeichen, gekürzt")


## Eine Antwort von ClientGetUserStats wie von Steam.
func _stats_body(res: int, with_schema: bool, packed: bool) -> PackedByteArray:
	var b := CM.Pb.f_fixed64(1, 480)
	b.append_array(CM.Pb.f_varint(2, res))
	if with_schema:
		b.append_array(CM.Pb.f_bytes(4, SE.read_capped(SE.schema_path(DIR, 480), 1 << 20)))
	# Statistik 2: Bit 0 gesetzt, ohne Zeit; Statistik 1: Bit 1 mit Zeit.
	var st := CM.Pb.f_varint(1, 2)
	st.append_array(CM.Pb.f_varint(2, 1))
	b.append_array(CM.Pb.f_msg(5, st))
	var blk := CM.Pb.f_varint(1, 1)
	var times := [0, 1700000000, 0]
	if packed:
		var raw := PackedByteArray()
		for t in times:
			var four := PackedByteArray()
			four.resize(4)
			four.encode_u32(0, t)
			raw.append_array(four)
		blk.append_array(CM.Pb.f_bytes(2, raw))
	else:
		for t in times:
			blk.append_array(CM.Pb.f_fixed32(2, t))
	b.append_array(CM.Pb.f_msg(6, blk))
	return b


func _chat_server() -> void:
	print("Chat-Server: ClientGetUserStats und GetAchievementsProgress")
	var req := CM.Pb.decode(CM.user_stats_request(480, int(SID)))
	check(int(CM.Pb.first(req, 1, 0)) == 480 and int(CM.Pb.first(req, 4, 0)) == int(SID) and int(CM.Pb.first(req, 3, 0)) == -1,
			"Anfrage: Spiel, Konto, Schema erbeten")
	var us := SE.parse_user_stats(_stats_body(1, true, false))
	check(int(us.eresult) == 1 and int(us.appid) == 480 and (us.bits as Dictionary).size() == 4 and str(us.title) == "Spacewar", "Antwort mit Schema gelesen")
	check((us.got as Dictionary).size() == 2 and int(us.got.get("ACH_WIN_100_GAMES", 0)) == 1700000000 and us.got.has("ACH_SECRET_END"),
			"frei aus Zeiten und aus dem Bitfeld der Statistik (%s)" % str(us.got))
	var pk := SE.parse_user_stats(_stats_body(1, false, true), SE.local_game(DIR, ACCT, 480).bits)
	check(int(pk.got.get("ACH_WIN_100_GAMES", 0)) == 1700000000, "Zeiten gepackt, Schema aus der Datei am PC")
	var bare := SE.parse_user_stats(_stats_body(1, false, false))
	check(bare.got.has("1/1") and (bare.bits as Dictionary).is_empty(), "ganz ohne Schema: Erfolge heißen <Statistik>/<Bit>")
	var fr := SE.friend_result(SE.parse_user_stats(_stats_body(1, true, false)))
	check(bool(fr.ok) and int(fr.total) == 4 and (fr.got as Dictionary).size() == 2 and int(fr.last) == 1700000000, "Freund: 2 von 4")
	check(str(SE.friend_result(SE.parse_user_stats(_stats_body(15, false, false))).reason) == "Profil privat", "Freund privat (EResult 15)")
	check(str(SE.friend_result({}).reason) == "Keine Antwort" and not bool(SE.friend_result({ "eresult": 2 }).ok), "keine Antwort / Fehler")
	var junk := PackedByteArray()
	for i in 600:
		junk.append((i * 37 + 11) % 256)
	var j := SE.parse_user_stats(junk)
	check(j is Dictionary and int(j.eresult) != 1, "Datenmüll: kein Absturz, nichts Gültiges")
	var pr := CM.Pb.decode(CM.progress_request(int(SID), [620, 0, 440], "german"))
	check((pr.get(3, []) as Array) == [620, 440] and CM.Pb.text(pr, 2) == "german", "Sammelfrage: nur gültige App-IDs")
	var body := PackedByteArray()
	for e in [[620, 51, 51, 0], [440, 12, 520, 0], [570, 0, 0, 0], [10, 3, 5, 1], [0, 1, 1, 0]]:
		var eb := CM.Pb.f_varint(1, e[0])
		eb.append_array(CM.Pb.f_varint(2, e[1]))
		eb.append_array(CM.Pb.f_varint(3, e[2]))
		eb.append_array(CM.Pb.f_fixed32(4, 0))
		eb.append_array(CM.Pb.f_varint(5, e[3]))
		body.append_array(CM.Pb.f_msg(1, eb))
	var got := CM.parse_progress(body)
	check(got.size() == 4 and got[620] == { "u": 51, "t": 51 } and got[440] == { "u": 12, "t": 520 } and got[570] == { "u": 0, "t": 0 },
			"Stand je Spiel gelesen")
	check(got[10] == { "u": 5, "t": 5 }, "all_unlocked zählt alle")
	check(CM.PROGRESS in CM.RARE_METHODS and CM.USER_STATS in CM.RARE_METHODS and not (CM.USER_STATS in CM.USER_METHODS),
			"neben Steam am PC automatisch nur selten")
	check(CM.session_allowed(CM.USER_STATS, 1000, 1001, true), "geöffnet (Knopfdruck): darf")


func _status_lokal() -> void:
	print("Dein Status aus Steam am PC")
	check(PC.vdf_value('"a"  "x\\"y\\\\z"', "a") == 'x"y\\z' and PC.vdf_value('"a" { "b" "1" }', "a") == "" and PC.vdf_value('"a" "offen', "a") == "",
			"VDF-Wert mit Escapes; Abschnitt oder offener Text: leer")
	var lc := FileAccess.get_file_as_string(ROOT + "/userdata/12345/config/localconfig.vdf")
	check(PC.persona_from_localconfig(lc, ACCT) == 3, "neuer Client: WebStorage → ePersonaState (abwesend)")
	check(PC.persona_from_localconfig(lc, 999) == 1, "anderes Konto: PersonaStateDesired")
	check(PC.persona_from_localconfig(FileAccess.get_file_as_string(ROOT + "/userdata/777/config/localconfig.vdf"), 777) == 7, "älterer Client: unsichtbar")
	check(PC.persona_from_localconfig('"FriendStoreLocalPrefs_5" "{\\"ePersonaState\\":42}"', 5) == -1 and PC.persona_from_localconfig("{kaputt", 5) == -1,
			"Unsinn: unbekannt")
	var lu := FileAccess.get_file_as_string(ROOT + "/config/loginusers.vdf")
	check(not PC.offline_mode(lu, SID) and PC.offline_mode(lu, SID_OFF) and not PC.offline_mode(lu, "1"), "Offline-Modus je Konto")
	var root := ProjectSettings.globalize_path(ROOT)
	var a: Dictionary = await PC.pc_persona(root, SID)
	check(int(a.state) == 3 and str(a.src).contains("localconfig"), "Steam am PC: abwesend (%s)" % str(a))
	check(int((await PC.pc_persona(root, SID_OFF)).state) == 0, "Offline-Modus: offline")
	check(int((await PC.pc_persona(root, "76561197960265829")).state) == 1, "nichts gespeichert: angemeldet heißt online")
	check(int((await PC.pc_persona("", SID)).state) == 1, "Steam-Ordner unbekannt: online")
	check(PC.name_of(1) == "Online" and PC.name_of(7) == "Unsichtbar", "Namen")
	# Eine große Datei (wie bei großen Bibliotheken): gelesen wird im Hilfsfaden, das Ergebnis ist dasselbe.
	var gross_root := Config.path("steam_gross")
	var gross_pfad := gross_root.path_join("userdata/101/config/localconfig.vdf")
	DirAccess.make_dir_recursive_absolute(gross_pfad.get_base_dir())
	var fuell := "\t\"apps\"\n\t{\n" + "\t\t\"LastPlayed\"\t\t\"1700000000\"\n".repeat(60000) + "\t}\n"
	var gf := FileAccess.open(gross_pfad, FileAccess.WRITE)
	gf.store_string("\"UserLocalConfigStore\"\n{\n" + fuell + "\t\"friends\"\n\t{\n\t\t\"PersonaStateDesired\"\t\t\"2\"\n\t}\n}\n")
	gf.close()
	var vor := Time.get_ticks_msec()
	var gross: Dictionary = await PC.pc_persona(gross_root, str(PC.STEAM64 + 101))
	check(int(gross.state) == 2 and str(gross.src).contains("localconfig"), "große localconfig.vdf (2 MB) im Hilfsfaden gelesen: beschäftigt (%d ms)" % (Time.get_ticks_msec() - vor))
	var wieder: Dictionary = await PC.pc_persona(gross_root, str(PC.STEAM64 + 101))
	check(int(wieder.state) == 2, "unverändert: aus dem Gemerkten, ohne neu zu lesen")


func _status_anzeige() -> void:
	print("Wie Uzai deinen Status zeigt")
	var now := 100000
	var off := { "at": now - 5, "state": 0 }
	check(MyStatus.steam_persona(off, {}, -1, now) == 0, "ohne Steam am PC: wie bisher")
	check(MyStatus.steam_persona(off, {}, -1, now, 1) == 1, "Steam am PC online: nicht „offline“, auch wenn der Chat-Server 0 meldet")
	check(MyStatus.steam_persona({}, {}, -1, now, 1) == 1, "nur Steam am PC bekannt: online")
	check(MyStatus.steam_persona({ "at": now - 5, "state": 3 }, {}, -1, now, 1) == 3, "abwesend laut Steam geht „online“ vor")
	check(MyStatus.steam_persona({}, { "personastate": 3 }, -1, now, 1) == 3 and MyStatus.steam_persona({}, { "personastate": 0 }, -1, now, 1) == 1,
			"Web-API: abwesend zählt, offline nicht")
	check(MyStatus.steam_persona(off, {}, -1, now, 7) == 7 and MyStatus.steam_from_persona(7) == "invisible", "unsichtbar bleibt unsichtbar")
	check(MyStatus.steam_seen(off, now, 1, "", 0, false, "", 1) == "Online", "„Freunde sehen“: online")
	check(MyStatus.steam_seen({ "at": now - 5, "state": 0, "game_id": "480", "game": "Spacewar" }, now, 1, "", 0, false, "", 1) == "Spielt Spacewar",
			"Spiel weiter vom Chat-Server")
	check(MyStatus.steam_seen(off, now, 0, "", 0, false, "") == "Offline", "ohne Steam am PC: unverändert")
	check(MyStatus.profile_state("", "online", false) == "online" and MyStatus.profile_state("", "", false) == "offline", "Profil ohne Web-API: wie überall")
	check(MyStatus.profile_state("offline", "away", true) == "away" and MyStatus.profile_state("game", "online", true) == "game",
			"neben Steam am PC zählt dein Status; „Im Spiel“ bleibt")
	check(MyStatus.profile_state("offline", "online", false) == "offline", "Web-API da, Steam am PC aus: Web-API")


func _zaehlung() -> void:
	print("Zählung und Protokoll")
	var owned := [{ "appid": 1, "minutes": 10 }, { "appid": 2, "minutes": 10 }]
	var cache := { "1": { "m": 10, "u": 0, "t": 0, "at": 1000 }, "2": { "m": 10, "u": 0, "t": 0, "at": 1000, "v": Ach.COUNT_VERSION } }
	var todo := Ach.count_todo(owned, cache, 2000, false)
	check(todo.size() == 1 and int(todo[0].appid) == 1, "„ohne Erfolge“ aus älterer Fassung wird neu gezählt")
	var pa := Ach.parse_player_ach({ "ok": false, "code": 400, "data": null })
	check(str(pa.state) == "error", "HTTP 400 ohne Angabe: kein „ohne Erfolge“ (abgelehnter Zugang)")
	check(SE.log_text("", 12, 30, 40, 900) == "Erfolge: Web-API abgelehnt → lokal (Steam-Ordner) 12 + Chat-Server 30, 40 Spiele, 900 Erfolge",
			"Zeile im Protokoll: %s" % SE.log_text("", 12, 30, 40, 900))
	check(SE.log_text("(zuletzt gespielt)", 0, 0, 0, 0).contains("weder lokal noch Chat-Server"), "nichts gefunden: steht so da")
