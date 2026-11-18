extends Node
## Your Steam status and "Spielt …" alongside Steam on the PC, so the profile reflects the status correctly:
## Uzai does not jump to "playing nothing" during a game, logs why a game ends, does not close a short
## session out from under a second one, retries soon after a dropout instead of staying empty for five
## minutes, never overwrites the friends list with 0, and shows in the profile what friends really see.
## Run: godot --headless --path . res://tests/logic_steam_status.tscn

const CM := preload("res://src/core/steam_cm.gd")
const Soc := preload("res://src/core/social.gd")
const MyStatus := preload("res://src/core/my_status.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_spiel()
	await _sitzung()
	_liste()
	_profil()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Sitzung „angemeldet“ wie bei Steam: über verbinde, offen und anmelden (steam.verbindung, src/core/steam_cm.gd) –
## ein Sprung direkt von „zu“ stünde als ZUSTAND-VERSTOSS da.
func _angemeldet() -> void:
	for s in ["zu", "verbinde", "offen", "anmelden", "angemeldet"]:
		SteamCM.state = s


func _log_text() -> String:
	return FileAccess.get_file_as_string(Config.path("logs/steam.log"))


func _spiel() -> void:
	print("„Spielt …“ während des Spiels")
	check(CM.games_want("Yu-Gi-Oh!", true, false) == "Yu-Gi-Oh!", "Dauerverbindung steht: das Spiel wird gemeldet")
	check(CM.games_want("Yu-Gi-Oh!", false, false) == "" and CM.games_want("Yu-Gi-Oh!", true, true) == "",
			"ohne Verbindung oder wenn Steam am PC selbst spielt: nichts")
	var p := Config.path("logs/steam.log")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	# Sitzung wie beim Nutzer: Steam am PC angemeldet, Dauerverbindung nur für das Spiel (ohne Netz:
	# _send schickt ohne Verbindung nichts, es zählt, was Uzai daraus macht).
	var keep_fields := { "state": SteamCM.state, "live": SteamCM.live, "games_name": SteamCM.games_name,
		"pc_signed_in": SteamCM.pc_signed_in, "pc_known": SteamCM.pc_known, "persona_state": SteamCM.persona_state }
	_angemeldet()
	SteamCM.live = true
	SteamCM.pc_signed_in = true
	SteamCM.pc_known = true
	SteamCM.persona_state = -1
	SteamCM.set_games_played("Yu-Gi-Oh! GX Tag Force Evolution")
	check(SteamCM.showing() == "Yu-Gi-Oh! GX Tag Force Evolution", "Spielstart: Freunde sollen das Spiel sehen")
	# Was danach im Spiel passiert (Status von Steam, Social, Prüfung von Steam am PC), darf das Spiel
	# nicht zurücknehmen.
	SteamCM.set_persona(1)
	SteamCM.set_persona(0)
	SteamCM.send_status_if_needed()
	SteamCM.set_games_played("Yu-Gi-Oh! GX Tag Force Evolution")
	check(SteamCM.showing() == "Yu-Gi-Oh! GX Tag Force Evolution" and not _log_text().contains("Spielt: nichts"),
			"Status-Meldungen während des Spiels: kein Sprung auf „spielt nichts“")
	check(not _log_text().contains("Status gemeldet") and not _log_text().contains("Status für das Spiel"),
			"neben Steam am PC meldet Uzai keinen eigenen Status (sonst stand das Konto bei Abriss offline)")
	check(Launcher.end_reason(false, "rom", 33) == "Spielprozess beendet nach 33 s" and Launcher.end_reason(true, "rom", 9) == "in Uzai beendet nach 9 s"
			and Launcher.end_reason(false, "link", 5).begins_with("Spielfenster zu"), "Grund fürs Spielende")
	SteamCM.set_games_played("", Launcher.end_reason(false, "rom", 33))
	check(SteamCM.showing() == "" and _log_text().contains("Spielt: nichts (Spielprozess beendet nach 33 s)"),
			"Spielende steht mit Grund und Dauer im Protokoll")
	SteamCM.keep = "x"
	SteamCM.stop_keep("kein Nicht-Steam-Spiel, Steam am PC angemeldet")
	check(_log_text().contains("Dauerverbindung beendet (kein Nicht-Steam-Spiel, Steam am PC angemeldet)") and _log_text().count("Spielt: nichts") == 1,
			"Uzai schließt die Sitzung selbst – das steht da, ohne zweites „spielt nichts“")
	SteamCM.state = keep_fields.state
	SteamCM.live = keep_fields.live
	SteamCM.games_name = keep_fields.games_name
	SteamCM._games_sent = ""
	SteamCM.pc_signed_in = keep_fields.pc_signed_in
	SteamCM.pc_known = keep_fields.pc_known
	SteamCM.persona_state = keep_fields.persona_state
	var cm_src := Quelle.lesen("res://src/core/steam_cm.gd")
	check(cm_src.contains("_steam_status(false, end_reason(") or Quelle.lesen("res://src/core/launcher.gd").contains("_steam_status(false, end_reason("),
			"Launcher gibt den Grund mit")


func _sitzung() -> void:
	print("Kurze Sitzungen nacheinander statt gleichzeitig")
	# Läuft eine Anmeldung, wartet die zweite (kein zweiter Logon auf derselben Verbindung).
	SteamCM._logon_busy = true
	var got := []
	var second := func() -> void: got.append(await SteamCM.logon("kein.zugang.da"))
	second.call()
	await get_tree().process_frame
	await get_tree().process_frame
	check(got.is_empty(), "zweite Anmeldung wartet auf die erste")
	# Die erste ist fertig (angemeldet): die zweite nutzt dieselbe Sitzung, ohne eigenen Logon.
	_angemeldet()
	SteamCM._logged_for = "kein.zugang.da"
	SteamCM._logon_busy = false
	var until := Time.get_ticks_msec() + 5000
	while got.is_empty() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(got == [""] and not SteamCM._logon_busy, "danach nutzt sie dieselbe Sitzung (%s)" % str(got))
	SteamCM.state = "zu"
	SteamCM._logged_for = ""
	# Erfolg wird sofort dem Zugang zugeordnet: Wer im selben Bild dazukommt, nutzt die Sitzung.
	var src := Quelle.lesen("res://src/core/steam_cm.gd")
	check(src.contains("state = \"angemeldet\"\n\t\t\t\t# Gleich hier merken, für welchen Zugang: Wer im selben Bild dazukommt, nutzt die Sitzung.\n\t\t\t\t_logged_for = _logon_token"),
			"angemeldet und Zugang im selben Schritt")
	# Eine Abfrage braucht die Sitzung noch: nicht schließen.
	SteamCM._ws = WebSocketPeer.new()
	SteamCM._holds = 1
	SteamCM.close_when_idle()
	check(SteamCM._ws != null, "eine zweite Abfrage läuft: die kurze Sitzung bleibt")
	SteamCM._holds = 0
	SteamCM.close_when_idle()
	check(SteamCM._ws == null, "danach schließt sie")
	# Aussetzer: nicht fünf Minuten warten.
	var L := CM.LINK_DETAILS
	var now := int(Time.get_unix_time_from_system())
	SteamCM._rare_at[L] = now
	SteamCM._logon_result = -1
	SteamCM._rare_failed(L, true)
	var at := int(SteamCM._rare_at[L])
	check(not CM.session_allowed(L, at, now + CM.RARE_RETRY_S - 2) and CM.session_allowed(L, at, now + CM.RARE_RETRY_S + 1),
			"keine Antwort: neuer Versuch nach %d s statt nach %d s" % [CM.RARE_RETRY_S, CM.FRIENDS_GAP_S])
	SteamCM._rare_at[L] = now
	SteamCM._logon_result = 5
	SteamCM._rare_failed(L, true)
	check(int(SteamCM._rare_at[L]) == now, "Zugang abgelehnt: kein schneller Neuversuch")
	SteamCM._rare_at[L] = now
	SteamCM._logon_result = -1
	SteamCM._rare_failed(L, false)
	check(int(SteamCM._rare_at[L]) == now, "auf Knopfdruck (keine kurze Sitzung): Sperre unberührt")
	SteamCM.reset_rare()


func _liste() -> void:
	print("Freundesliste nie mit 0 überschreiben")
	check(Soc.keep_old_list(0, 77, 77), "Steam nennt 77, Namen kamen nicht: die alten 77 bleiben")
	check(not Soc.keep_old_list(5, 77, 77) and not Soc.keep_old_list(0, 77, 0), "neue Angaben oder noch nichts bekannt: neue Liste")
	var soc_src := Quelle.lesen("res://src/core/social.gd")
	check(soc_src.contains("SteamCM.friends_list.connect(_on_cm_list)"), "Liste kommt mit einer Sitzung: Uzai nutzt sie gleich mit")
	check(soc_src.contains("if out.is_empty() and not old.is_empty():"), "Chat-Server-Weg: leere Antwort ersetzt die Liste nicht")


func _profil() -> void:
	print("Was Freunde von dir sehen")
	var now := 1_800_000_000
	var own := { "at": now - 5, "state": 1, "game": "Yu-Gi-Oh! GX Tag Force Evolution", "game_id": "15190414816125648896" }
	check(MyStatus.steam_persona(own, {}, -1, now) == 1, "eigener Status vom Chat-Server, auch ohne Web-API (HTTP 400)")
	check(MyStatus.steam_persona(own, { "personastate": 3 }, -1, now) == 1, "frischer Stand vom Chat-Server geht der Web-API vor")
	check(MyStatus.steam_persona({ "at": now - 4000, "state": 1 }, { "personastate": 3 }, -1, now) == 3, "alter Stand: die Web-API zählt")
	check(MyStatus.steam_persona({}, {}, -1, now) == -1, "nichts bekannt: unbekannt")
	check(MyStatus.steam_seen(own, now, 1, "Yu-Gi-Oh! GX Tag Force Evolution", now - 10, false, "") == "Spielt Yu-Gi-Oh! GX Tag Force Evolution",
			"Steam bestätigt das Spiel")
	var no_game := { "at": now - 1, "state": 1, "game": "", "game_id": "" }
	check(MyStatus.steam_seen(no_game, now, 1, "Zelda", now - 10, false, "") == "Online", "Steam zeigt das Spiel nicht: „Online“, nicht „Spielt“")
	check(MyStatus.steam_seen({ "at": now - 1, "state": 0 }, now, 0, "Zelda", now - 10, false, "") == "Offline",
			"in Steam offline/unsichtbar: Freunde sehen dich offline (und kein Spiel)")
	check(MyStatus.steam_seen({}, now, 1, "Zelda", now, false, "") == "Spielt Zelda", "noch nicht nachgesehen: was Uzai meldet")
	check(MyStatus.steam_seen(own, now, 1, "Zelda", now + 1, false, "") == "Spielt Zelda", "neue Spielmeldung nach dem letzten Stand: die neue zählt")
	check(MyStatus.steam_seen({}, now, 1, "", 0, false, "ELDEN RING") == "Spielt ELDEN RING", "Steam-Spiel läuft (lokal bekannt)")
	check(MyStatus.steam_seen({}, now, 0, "Zelda", now, true, "") == "Spielt Zelda", "Steam am PC zu, Uzai meldet dich für das Spiel online")
	check(MyStatus.steam_seen({}, now, -1, "", 0, false, "") == "", "nichts bekannt: keine Behauptung")
	check(CM.own_text(1, "Zelda", "15190414816125648896") == "online, spielt „Zelda“ (Nicht-Steam-Spiel)"
			and CM.own_text(1, "", "1245620").ends_with("(Steam-Spiel)") and CM.own_text(0, "", "") == "offline (Steam zeigt kein Spiel)",
			"Protokollzeile „Freunde sehen dich: …“")
	var cm_src := Quelle.lesen("res://src/core/steam_cm.gd")
	var ro := cm_src.substr(cm_src.find("func refresh_own("), cm_src.find("func _confirm_own(") - cm_src.find("func refresh_own("))
	check(ro.contains("if state != \"angemeldet\" or me == \"\":\n\t\treturn") and not ro.contains("logon("),
			"eigener Status nur über eine stehende Sitzung, nie eine eigene dafür")
