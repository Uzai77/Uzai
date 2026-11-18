extends Node
## Durchlauf-Probe für Discord-Direktnachrichten: Uzai → Windows-Helfer (hier PowerShell 7) →
## C#-Teil UzDsdk → nachgebaute Discord-SDK-Bibliothek (tests/fake_discord_sdk.c).
## Aufruf:
##   gcc -shared -fPIC -o <ordner>/libdiscord_partner_sdk.so tests/fake_discord_sdk.c
##   UZAI_DATA=<leer> UZAI_HELPER_SHELL=<pfad zu pwsh> LD_LIBRARY_PATH=<ordner> \
##     godot --headless --path . res://tests/net_discord_dm.tscn

var fails := 0
var toasts: Array = []


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	await Helper.run("dsdk-stop", {}, 3.0)
	get_tree().quit(1 if fails > 0 else 0)


func _wait(cond: Callable, secs := 8.0) -> bool:
	var until := Time.get_ticks_msec() + int(secs * 1000)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _run() -> void:
	if OS.get_environment("UZAI_HELPER_SHELL") == "":
		print("UZAI_HELPER_SHELL fehlt")
		fails += 1
		return
	check(await _wait(func(): return Helper.available, 30.0), "Helfer läuft")
	# Zeitkritisches läuft über einen zweiten Helfer, damit es nie hinter langen Befehlen wartet.
	check(await _wait(func(): return Helper._fast.ready, 40.0), "schneller Helfer läuft (eigener Prozess)")
	check(Helper._fast.pid > 0 and Helper._fast.pid != Helper._main.pid, "zwei getrennte Prozesse")
	# Der Hauptweg ist beschäftigt (Discord-Leitung probieren), der schnelle Weg antwortet trotzdem.
	var slow_done := [false]
	var slow_call := func() -> void:
		await Helper.run("presence", { "client_id": "1", "details": "x", "state": "y", "start": 0 }, 8.0)
		slow_done[0] = true
	slow_call.call()
	var t_quick := Time.get_ticks_msec()
	var quick := await Helper.run("steam-running", {}, 3.0)
	var quick_ms := Time.get_ticks_msec() - t_quick
	check(quick.ok and quick.result is Dictionary and (quick.result as Dictionary).has("appid"), "schneller Befehl antwortet, während der Hauptweg arbeitet")
	await _wait(func(): return slow_done[0], 10.0)
	check(quick_ms < 1500 and slow_done[0], "… ohne auf ihn zu warten (%d ms)" % quick_ms)
	var dll := Config.path("discord").path_join(DiscordChat.DLL)
	DirAccess.remove_absolute(dll)
	Config.set_value("accounts.discord_client_id", "123456789012345678")
	Config.set_value("accounts.discord_client_secret", "abcdefghijklmnopqrstuvwxyz123456")
	Config.set_value("accounts.discord_dm", true)

	print("Ohne Bibliothek")
	await DiscordChat.restart()
	check(DiscordChat.state == "keine_dll" and DiscordChat.error.contains(DiscordChat.DLL), "fehlende DLL wird erklärt: " + DiscordChat.error)

	print("SDK-Download neben Uzai.exe wird ausgepackt")
	var zip_path := OS.get_executable_path().get_base_dir().path_join("DiscordSocialSdk-1.9.0.zip")
	var can_zip := DirAccess.dir_exists_absolute(OS.get_executable_path().get_base_dir())
	var zp := ZIPPacker.new()
	if can_zip and zp.open(zip_path) == OK:
		zp.start_file("discord_social_sdk/lib/debug/discord_partner_sdk.dll")
		zp.write_file("debug".to_utf8_buffer())
		zp.close_file()
		zp.start_file("discord_social_sdk/lib/release/discord_partner_sdk.dll")
		zp.write_file("release".to_utf8_buffer())
		zp.close_file()
		zp.close()
		var got := DiscordChat.dll_path()
		check(got == dll and FileAccess.get_file_as_string(dll) == "release", "Release-DLL aus dem Zip geholt (%s)" % got)
		DirAccess.remove_absolute(zip_path)
	else:
		print("  (übersprungen: Ordner von Godot nicht beschreibbar)")
		var f := FileAccess.open(dll, FileAccess.WRITE)
		DirAccess.make_dir_recursive_absolute(dll.get_base_dir())
		f = FileAccess.open(dll, FileAccess.WRITE)
		f.store_string("x")
		f.close()

	print("Ohne Nachrichten-Rechte")
	Config.set_value("accounts.discord_token", "good")
	Config.set_value("accounts.discord_scope", "rpc rpc.voice.read")
	Config.set_value("accounts.discord_expires", int(Time.get_unix_time_from_system()) + 86400)
	await DiscordChat.restart()
	check(DiscordChat.version == "1.9.0", "SDK gestartet (Version %s)" % DiscordChat.version)
	check(DiscordChat.state == "freigabe", "Zugang ohne sdk.social_layer: einmal freigeben (%s)" % DiscordChat.state)
	check(Voice.scopes().has("sdk.social_layer") and Voice.scopes().has("rpc"), "Freigabe fragt Sprachkanal + Nachrichten an: " + str(Voice.scopes()))

	print("Abgelehnter Zugang")
	Config.set_value("accounts.discord_scope", "rpc openid sdk.social_layer")
	Config.set_value("accounts.discord_token", "bad")
	await DiscordChat.restart()
	check(DiscordChat.state == "freigabe" and DiscordChat.error.contains("nicht angenommen"), "401: neu freigeben (%s)" % DiscordChat.error)

	print("Verbunden")
	Config.set_value("accounts.discord_token", "good")
	await DiscordChat.restart()
	check(await _wait(func(): return DiscordChat.state == "bereit" and not DiscordChat.friends.is_empty()), "bereit, Freunde geladen (%s)" % DiscordChat.state)
	check(DiscordChat.me_id == "999", "eigene ID")
	check(DiscordChat.friends.size() == 2 and str(DiscordChat.friends[0].name) == "Mira" and str(DiscordChat.friends[0].game) == "Elden Ring",
			"nur Freunde (kein Blockierter), wer spielt zuerst")
	check(str(DiscordChat.friend("1002").name) == "Jonas Ü" and str(DiscordChat.friend("1002").state) == "away", "Umlaute und Zustand")
	check(int(DiscordChat.friends[0].get("since", 0)) == 1700000000 and str(DiscordChat.friends[0].get("music", "")) == "",
			"Aktivität mit Startzeit aus dem SDK (Millisekunden → Sekunden)")

	print("Senden, Antwort, Verlauf")
	var h0: Array = await DiscordChat.history("1001")
	check(h0.is_empty(), "noch leerer Verlauf")
	var err: String = await DiscordChat.send("1001", "Hallo Mira 🎮")
	check(err == "", "gesendet (%s)" % err)
	check(await _wait(func(): return DiscordChat.unread.get("1001", 0) == 1), "Antwort kommt als ungelesen an")
	var h: Array = await DiscordChat.history("1001")
	check(h.size() == 2 and bool(h[0].me) and str(h[0].text) == "Hallo Mira 🎮" and not bool(h[1].me), "Verlauf: eigene zuerst, dann die Antwort, ohne Doppelte")
	check(not DiscordChat.unread.has("1001"), "Verlauf ansehen setzt gelesen")
	DiscordChat.set_open("1001")
	await DiscordChat.send("1001", "Noch was")
	await _wait(func(): return (DiscordChat._hist.get("1001", []) as Array).size() >= 4)
	check(not DiscordChat.unread.has("1001"), "offenes Gespräch: Antwort nicht als ungelesen")
	DiscordChat.set_open("")
	var err2: String = await DiscordChat.send("1003", "x")
	check(err2.contains("befreundet"), "403: verständlicher Grund (%s)" % err2)

	print("Jemand kommt online (UserUpdated)")
	var calls0 := DiscordChat.friends_calls
	var changes := [0]
	var on_ch := func() -> void: changes[0] += 1
	DiscordChat.changed.connect(on_ch)
	var e3: String = await DiscordChat.send("1002", "!online")
	check(e3 == "", "Probe gestartet (%s)" % e3)
	check(await _wait(func(): return str(DiscordChat.friend("1002").get("state", "")) == "online"),
			"Jonas ist online, ohne dass Uzai neu startet (%s)" % str(DiscordChat.friend("1002").get("state", "")))
	await get_tree().create_timer(DiscordChat.FRIENDS_DEBOUNCE + 0.5).timeout
	check(str(DiscordChat.friend("1002").get("game", "")) == "Hades", "… und spielt Hades")
	check(DiscordChat.friends_calls - calls0 <= 2, "fünf Meldungen des SDK: höchstens zwei Abfragen (%d)" % (DiscordChat.friends_calls - calls0))
	check(changes[0] >= 1, "Freunde-Bereich, Guide und Zähler werden benachrichtigt")
	var n_ch: int = changes[0]
	await DiscordChat.refresh_friends()
	check(changes[0] == n_ch, "nachfragen ohne Änderung: keine Meldung")
	DiscordChat.changed.disconnect(on_ch)

	print("Eigener Status (Guide → dein Profil)")
	var MyStatus := load("res://src/core/my_status.gd")
	await MyStatus.refresh_discord()
	check(str(MyStatus.discord_me.get("id", "")) == "999" and MyStatus.discord_now() == "online", "eigener Status vom SDK: online (%s)" % MyStatus.discord_now())
	var se: String = await MyStatus.set_discord("dnd")
	check(se == "", "Bitte nicht stören gesetzt (%s)" % se)
	await MyStatus.refresh_discord()
	check(int(MyStatus.discord_me.get("st", -1)) == 4 and MyStatus.discord_from_sdk(str(MyStatus.discord_me.state), int(MyStatus.discord_me.st)) == "dnd",
			"SDK meldet danach Nicht stören zurück")
	se = await MyStatus.set_discord("invisible")
	await MyStatus.refresh_discord()
	check(se == "" and int(MyStatus.discord_me.get("st", -1)) == 5 and MyStatus.discord_now() == "invisible", "Unsichtbar (%s)" % se)
	var bad: Dictionary = await Helper.run("dsdk-status", { "status": 9 }, 8.0)
	check(bad.ok and not bool((bad.result as Dictionary).get("ok", true)), "unbekannter Status: Discord lehnt ab, kein Absturz")
	se = await MyStatus.set_discord("online")
	check(se == "", "wieder online")
	MyStatus.discord_pick = ""
	Config.set_value(MyStatus.CONFIG_KEY, {})

	print("Freundesliste im Guide")
	var People := load("res://src/ui/components/guide_people.gd")
	var list: Array = People.build([{ "id": "s1", "name": "Mira", "state": "online", "avatar": "", "game": "" }], {}, [], "", {}, "", "", DiscordChat.friends,
			{ "1002": 3 })
	var mira: Dictionary = {}
	var mira_s: Dictionary = {}
	var jonas: Dictionary = {}
	for e in list:
		if str(e.name) == "Mira" and not (e.dm as Dictionary).is_empty():
			mira = e
		if str(e.name) == "Mira" and not (e.steam as Dictionary).is_empty():
			mira_s = e
		if str(e.name) == "Jonas Ü":
			jonas = e
	check(list.size() == 3 and not mira.is_empty() and not mira_s.is_empty() and (mira.steam as Dictionary).is_empty() and (mira_s.dm as Dictionary).is_empty(),
			"gleicher Name bei Steam und Discord: zwei getrennte Einträge")
	check(int(jonas.get("unread", 0)) == 3 and str(jonas.key).begins_with("m:"), "Discord-Freund mit Ungelesenen")
