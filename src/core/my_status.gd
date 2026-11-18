extends RefCounted
## Dein eigener Status bei Steam und Discord (Guide → Freunde → dein Profil oben rechts).
##
## Steam: Ist Steam am PC angemeldet, gehört der Status der Steam-App. Uzai ändert ihn dann über
## Steam selbst – mit dem offiziellen Link steam://friends/status/<online|away|invisible|offline>,
## den eine zweite steam.exe minimiert und ohne Fokus an die laufende weiterreicht (es öffnet sich
## kein Fenster; tut es das doch, schließt Uzai es und holt sich den Fokus zurück). Eine eigene
## Sitzung mit ClientChangeStatus gibt es dann nicht: die ließ am PC alle Freunde offline
## erscheinen. Nur wenn Steam am PC nicht angemeldet ist, setzt Uzai den Status über seine
## eigene Verbindung (SteamCM.choose_status, braucht die Steam-Anmeldung in Uzai).
## „Nicht stören“ bietet Uzai bei Steam nicht an: Steam kennt dafür keinen Link, und es stellt in
## der Steam-App nur Mitteilungen stumm.
##
## Discord: über das Discord Social SDK, das Uzai für Nachrichten schon nutzt
## (Client::SetOnlineStatus: Online, Abwesend, Bitte nicht stören, Unsichtbar). Discords RPC
## (Sprachkanal) kann den Status nicht ändern – ohne die SDK-Verbindung sagt das Panel, wo man
## sie einrichtet, statt einen Knopf zu zeigen, der nichts tut.

const STEAM_OPTS := [["online", "Online"], ["away", "Abwesend"], ["invisible", "Unsichtbar"], ["offline", "Offline"]]
const DISCORD_OPTS := [["online", "Online"], ["idle", "Abwesend"], ["dnd", "Bitte nicht stören"], ["invisible", "Unsichtbar"]]
const STEAM_CM := { "online": 1, "away": 3, "invisible": 7, "offline": 0 }        ## EPersonaState
const DISCORD_SDK := { "online": 0, "idle": 3, "dnd": 4, "invisible": 5 }        ## discordpp::StatusType
const NAMES := { "online": "Online", "away": "Abwesend", "idle": "Abwesend", "busy": "Beschäftigt", "dnd": "Bitte nicht stören",
	"invisible": "Unsichtbar", "offline": "Offline", "game": "Im Spiel" }
const PICK_KEEP := 180          ## so lange (s) gilt deine Wahl vor Abfragen, die noch den alten Stand zeigen
const OWN_FRESH := 600          ## so lange (s) gilt dein Status laut Steams Chat-Server (SteamCM.own)
const CONFIG_KEY := "social.my_status"

static var steam_pick := ""
static var steam_pick_at := 0
static var discord_pick := ""
static var discord_pick_at := 0
static var discord_me: Dictionary = {}     ## eigener Discord-Nutzer laut SDK { name, avatar, state, st }
static var busy := {}                      ## "steam" / "discord" -> true, solange eine Änderung läuft
static var _loaded := false


# --- Reine Logik (tests/logic_guide.gd) ----------------------------------------------------------

## Steams EPersonaState (Web-API, Chat-Server) als Status-Kennung; -1 = unbekannt ("").
static func steam_from_persona(ps: int) -> String:
	match ps:
		0: return "offline"
		1, 5, 6: return "online"
		2: return "busy"
		3, 4: return "away"
		7: return "invisible"
	return ""


## Was Uzai bei Steam anzeigt. Deine Wahl gilt PICK_KEEP Sekunden lang (die Web-API hinkt nach);
## danach zählt Steam – außer bei „Unsichtbar“, das Steam nach außen als „offline“ meldet.
static func steam_shown(persona: int, pick: String, pick_age: int) -> String:
	var web := steam_from_persona(persona)
	if pick != "" and pick_age >= 0 and pick_age < PICK_KEEP:
		return pick
	if pick == "invisible" and (web == "offline" or web == ""):
		return "invisible"
	return web if web != "" else pick


## Discord-Status laut SDK (UserHandle::Status als Zahl, sonst der Name aus dem Helfer).
static func discord_from_sdk(state: String, raw := -1) -> String:
	match raw:
		0, 6: return "online"
		1: return "offline"
		3: return "idle"
		4: return "dnd"
		5: return "invisible"
	match state:
		"online": return "online"
		"away", "idle": return "idle"
		"busy", "dnd": return "dnd"
		"offline": return "offline"
	return ""


static func discord_shown(sdk: String, pick: String, pick_age: int) -> String:
	if pick != "" and pick_age >= 0 and pick_age < PICK_KEEP:
		return pick
	if pick == "invisible" and (sdk == "offline" or sdk == ""):
		return "invisible"
	return sdk if sdk != "" else pick


## Your status according to Steam as EPersonaState (pure function, tested): first the fresh state from the
## chat server (own, Player.GetPlayerLinkDetails#1 for you), then the Web API (me), then whatever else Uzai
## knows. The Web API rejects the token from the QR sign-in (HTTP 400); the status used to stay empty then.
## pc: your status in Steam on the PC (SteamCM.pc_persona, from Steam's files; -1 = Steam on the PC is not
## signed in). If the Steam app is signed in, its status wins, because Uzai's own session has no status of
## its own and would show you as "offline". Only a more specific state from Steam (away, busy …) takes
## precedence over a stored "online".
static func steam_persona(own: Dictionary, me: Dictionary, cm_persona: int, now: int, pc := -1) -> int:
	var fresh := own.has("state") and now - int(own.get("at", 0)) < OWN_FRESH
	if pc >= 0:
		var seen: Array = []
		if fresh:
			seen.append(int(own.state))
		if me.has("personastate"):
			seen.append(int(me.personastate))
		for st in seen:
			if pc == 1 and int(st) in [2, 3, 4, 5, 6]:
				return int(st)
		return pc
	if fresh:
		return int(own.state)
	if me.has("personastate"):
		return int(me.personastate)
	if own.has("state"):
		return int(own.state)
	return cm_persona


## Was Steam-Freunde gerade von dir sehen (rein, getestet) – „Dein Status“ zeigt das.
## own: SteamCM.own (Stand vom Chat-Server), persona: dein Status (-1 = unbekannt), sent: was Uzai
## als Nicht-Steam-Spiel meldet (SteamCM.showing()) und wann (sent_at), raised: Uzai hat dich dafür
## „online“ gemeldet (Steam am PC zu), steam_game: Titel des laufenden Steam-Spiels ("" = keins).
## Gilt der Stand vom Chat-Server und ist er neuer als die letzte Spielmeldung, zählt er – sonst
## Uzais eigenes Wissen. "" = unbekannt.
## pc >= 0 (Steam am PC angemeldet): der Status kommt aus persona (steam_persona mit pc), das Spiel
## weiter vom Chat-Server.
static func steam_seen(own: Dictionary, now: int, persona: int, sent: String, sent_at: int, raised: bool, steam_game: String, pc := -1) -> String:
	var fresh := own.has("state") and now - int(own.get("at", 0)) < OWN_FRESH and int(own.get("at", 0)) >= sent_at
	var st := int(own.state) if fresh else (1 if raised and sent != "" else persona)
	if pc >= 0 and persona >= 0:
		st = persona
	var id := steam_from_persona(st)
	if id == "":
		return ""
	if id in ["offline", "invisible"]:
		return name_of("offline")
	var game := ""
	if fresh:
		if str(own.get("game_id", "")) != "":
			game = str(own.get("game", ""))
			if game == "":
				game = steam_game if steam_game != "" else sent
	else:
		game = steam_game if steam_game != "" else sent
	return ("Spielt " + game) if game != "" else name_of(id)


## Wie Uzai deinen Steam-Status ändert:
## client  – über die Steam-App am PC (steam://friends/status/…), sie ist angemeldet
## cm      – über Uzais eigene Verbindung (Steam am PC ist nicht angemeldet)
## login   – Steam am PC ist aus und Uzai ist nicht bei Steam angemeldet
## unknown – nicht feststellbar, ob Steam am PC läuft: lieber nichts senden (sonst wären womöglich
##           alle Freunde offline, wie beim Nutzer)
static func steam_route(windows: bool, helper_ok: bool, pc_running: bool, pc_user: bool, cm_login: bool, pc_maybe: bool) -> String:
	if windows and helper_ok and pc_running and pc_user:
		return "client"
	if windows and not helper_ok:
		return "unknown"
	if not cm_login:
		return "login"
	if pc_maybe:
		return "unknown"
	return "cm"


## Der offizielle Steam-Link für einen Status ("" bei unbekanntem Status).
static func steam_url(id: String) -> String:
	return "steam://friends/status/" + id if STEAM_CM.has(id) else ""


## steam.exe aus dem Steam-Ordner der Registry (c:/program files (x86)/steam).
static func steam_exe(steam_path: String) -> String:
	var p := steam_path.strip_edges().replace("/", "\\").trim_suffix("\\")
	return "" if p == "" else p + "\\steam.exe"


## Status im Kopf der Profilseite (rein, getestet): web – Zustand aus dem Profil der Web-API ("" =
## nicht geladen, etwa weil Steam den Zugang ablehnt), mine – steam_now(), pc – Steam am PC
## angemeldet und sein Status bekannt. Ohne Web-Stand oder neben Steam am PC zählt dein Status, wie
## Uzai ihn sonst zeigt; „Im Spiel“ aus der Web-API bleibt.
static func profile_state(web: String, mine: String, pc: bool) -> String:
	if web == "game":
		return web
	if mine != "" and (web == "" or pc):
		return mine
	return web if web != "" else "offline"


## Statusfarbe am Profilbild (Avatar.STATUS_COLORS).
static func dot(id: String) -> String:
	match id:
		"online", "game": return id
		"away", "idle": return "away"
		"busy", "dnd": return "busy"
	return "offline"


static func name_of(id: String) -> String:
	return str(NAMES.get(id, "Unbekannt"))


## Zweite Zeile der Profilkarte: was läuft, sonst die Status beider Dienste.
static func card_line(steam_id: String, discord_id: String, has_steam: bool, has_discord: bool, playing: String) -> String:
	if playing != "":
		return playing
	var parts: PackedStringArray = []
	if has_steam:
		parts.append("Steam " + (name_of(steam_id) if steam_id != "" else "–"))
	if has_discord:
		parts.append("Discord " + (name_of(discord_id) if discord_id != "" else "–"))
	if parts.is_empty():
		return "Kein Konto verbunden"
	return "  ·  ".join(parts)


## Gesamtstatus fürs Profilbild: der „sichtbarste“ beider Dienste (wie dich Freunde sehen).
static func overall(steam_id: String, discord_id: String, in_game: bool) -> String:
	if in_game and (steam_id in ["online", "away", "busy"] or discord_id in ["online", "idle", "dnd"]):
		return "game"
	for k in ["online", "away", "idle", "busy", "dnd"]:
		if steam_id == k or discord_id == k:
			return dot(k)
	return "offline"


## Kurzer Satz unter „Steam“ im Panel: über welchen Weg die Änderung geht.
static func route_note(route: String) -> String:
	match route:
		"client": return "über Steam am PC"
		"cm": return "über Uzai – Steam am PC ist aus"
		"login": return "Steam am PC ist aus. Für den Status ohne Steam-App: unter Einstellungen → Konten bei Steam anmelden."
		"unknown": return "Steam am PC gerade nicht erreichbar. Status in Steam ändern."
		"demo": return "Vorführung"
	return ""


## Ein Fenster, das nach dem Steam-Link vorn liegt: schließen, wenn es neu ist und zu Steam gehört.
static func steam_window_to_close(fg: Dictionary, before: Array, steam_windows: Array, my_pid: int) -> int:
	var h := int(fg.get("fg_hwnd", 0))
	if h == 0 or int(fg.get("fg_pid", 0)) == my_pid or before.has(h):
		return 0
	for w in steam_windows:
		if w is Dictionary and int(w.get("hwnd", 0)) == h:
			return h
	return 0


# --- Zustand ------------------------------------------------------------------------------------

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var d: Variant = Config.get_value(CONFIG_KEY, {})
	if d is Dictionary:
		steam_pick = str(d.get("steam", ""))
		steam_pick_at = int(d.get("steam_at", 0))
		discord_pick = str(d.get("discord", ""))
		discord_pick_at = int(d.get("discord_at", 0))


static func _save() -> void:
	Config.set_value(CONFIG_KEY, { "steam": steam_pick, "steam_at": steam_pick_at, "discord": discord_pick, "discord_at": discord_pick_at })


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


static func demo() -> bool:
	return Social.demo or Library.demo


static func has_steam() -> bool:
	return demo() or Social.has_steam() or SteamChat.logged_in() or Config.is_windows()


static func has_discord() -> bool:
	return DiscordChat.logged_in()


## Dein Steam-Status, wie Uzai ihn zeigt ("" = unbekannt).
static func steam_now() -> String:
	_load()
	var ps := steam_persona(SteamCM.own, Social.me, SteamCM.persona_state, _now(), SteamCM.pc_persona)
	if demo() and steam_pick == "":
		return "online"
	return steam_shown(ps, steam_pick, _now() - steam_pick_at)


static func discord_now() -> String:
	_load()
	if not has_discord():
		return ""
	if demo() and discord_pick == "" and discord_me.is_empty():
		return "online"
	var sdk := discord_from_sdk(str(discord_me.get("state", "")), int(discord_me.get("st", -1)))
	return discord_shown(sdk, discord_pick, _now() - discord_pick_at)


## Name und Bild fürs Profil: Steam, sonst Discord, sonst der Spielername aus den Einstellungen.
static func profile() -> Dictionary:
	var n := str(Social.me.get("name", ""))
	var a := str(Social.me.get("avatar", ""))
	if n == "":
		n = str(SteamCM.own.get("name", ""))
		a = str(SteamCM.own.get("avatar", ""))
	if n == "":
		n = str(discord_me.get("name", ""))
		a = str(discord_me.get("avatar", ""))
	if n == "":
		n = str(Config.get_value("system.player_name", "Spieler 1"))
	return { "name": n, "avatar": a }


## Was gerade läuft (fürs Profil): „Spielt …“ bzw. „Schaut ein Video“.
static func playing() -> String:
	if Launcher.in_game and not Launcher.current.is_empty():
		return "Spielt " + Library.display_title(Launcher.current)
	if Video.active:
		return "Hört ein Video" if Video.background else "Schaut ein Video"
	return ""


## Was Steam-Freunde jetzt von dir sehen ("" = unbekannt oder kein Steam).
static func steam_seen_now() -> String:
	if demo():
		return playing() if playing().begins_with("Spielt") else "Online"
	if not SteamChat.logged_in() and not Social.has_steam():
		return ""
	var sg := ""
	if Launcher.in_game and str(Launcher.current.get("source", "")) == "steam":
		sg = Library.display_title(Launcher.current)
	var ps := steam_persona(SteamCM.own, Social.me, SteamCM.persona_state, _now(), SteamCM.pc_persona)
	return steam_seen(SteamCM.own, _now(), ps, SteamCM.showing(), SteamCM.games_at, SteamCM._raised, sg, SteamCM.pc_persona)


## Eigenen Discord-Nutzer (Name, Bild, Status) beim SDK erfragen.
static func refresh_discord() -> void:
	if demo() or not has_discord():
		return
	var r: Dictionary = await DiscordChat.runner.call("dsdk-me", {}, 6.0)
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if res.get("me") is Dictionary:
		discord_me = res.me


# --- Ändern -------------------------------------------------------------------------------------

## Weg für Steam jetzt feststellen (fragt den Helfer, ob Steam am PC angemeldet ist).
static func steam_route_now() -> String:
	if demo():
		return "demo"
	var win := Config.is_windows()
	var ok := false
	var running := false
	var user := false
	if win and Helper.available:
		var r := await Helper.run("steam-state", {}, 4.0)
		if r.ok and r.result is Dictionary:
			ok = true
			running = bool(r.result.get("running", false))
			user = int(r.result.get("user", 0)) != 0
	# Steam am PC eben ausgegangen: SteamChat soll das auch wissen, bevor Uzai selbst sendet.
	if ok and not (running and user) and SteamCM.pc_maybe() and SteamChat.logged_in():
		await SteamChat._check_pc()
	return steam_route(win, ok, running, user, SteamChat.logged_in(), SteamCM.pc_maybe())


## Steam-Status setzen. Rückgabe: "" oder ein Satz, warum es nicht ging.
static func set_steam(id: String) -> String:
	_load()
	if not STEAM_CM.has(id) or busy.get("steam", false):
		return ""
	busy["steam"] = true
	# "ok" heißt gesetzt. Bricht _set_steam mit einem Skriptfehler ab, kommt hier "" an (gemessen): Das ist kein
	# Erfolg – sonst zeigte Uzai einen Status, der nie gesetzt wurde.
	var erg: String = await _set_steam(id)
	busy.erase("steam")
	if erg != "ok":
		return erg if erg != "" else "Der Status ließ sich gerade nicht ändern. Noch einmal versuchen."
	steam_pick = id
	steam_pick_at = _now()
	_save()
	return ""


## "ok" oder ein Satz, warum es nicht ging.
static func _set_steam(id: String) -> String:
	var route := await steam_route_now()
	match route:
		"demo":
			await (Engine.get_main_loop() as SceneTree).create_timer(0.35).timeout
			return "ok"
		"client":
			await _via_client(id)
			return "ok"
		"cm":
			var tok := str(Config.get_value("accounts.steam_chat_refresh", ""))
			var err: String = await SteamCM.choose_status(tok, int(STEAM_CM[id]))
			if err == "" and id in ["online", "away"] and SteamCM.keep == "":
				# Ohne Steam am PC ist Uzais Sitzung die einzige: sie bleibt, sonst wärst du gleich offline.
				SteamCM.keep_online(tok)
			if err == "":
				Social.me["personastate"] = int(STEAM_CM[id])
			return err if err != "" else "ok"
	var hinweis := route_note(route)
	return hinweis if hinweis != "" else "ok"


## Über die laufende Steam-App: zweite steam.exe mit dem Link, minimiert und ohne Fokus.
static func _via_client(id: String) -> String:
	var url := steam_url(id)
	var p := await Helper.run("steam-path", {}, 4.0)
	var dir := str(p.result.get("path", "")) if p.ok and p.result is Dictionary else ""
	var exe := steam_exe(dir)
	var tree := Engine.get_main_loop() as SceneTree
	var had_focus := tree != null and tree.root.has_focus()
	# Welche großen Fenster gibt es schon? Nur ein neues Steam-Fenster darf Uzai gleich schließen.
	var before: Array = []
	if had_focus:
		var snap := await Helper.run("windows-snapshot", { "skip": [OS.get_process_id()] }, 3.0)
		if snap.ok and snap.result is Dictionary:
			before = (snap.result.get("hwnds", []) as Array).map(func(h): return int(h))
	var sent := false
	if exe != "":
		var r := await Helper.run("start", { "exe": exe, "args": url, "quiet": true }, 6.0)
		sent = r.ok and r.result is Dictionary and int(r.result.get("pid", 0)) > 0
	if not sent:
		OS.shell_open(url)
	if had_focus:
		_keep_front(dir.replace("/", "\\"), before)
	return ""


## Bleibt Uzai vorn? Zweimal nachsehen; liegt ein neues Steam-Fenster vorn, schließen und Uzai
## wieder nach vorn holen (nie zum Spiel oder Desktop wechseln).
static func _keep_front(steam_dir: String, before: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var me := OS.get_process_id()
	for wait_s in [0.6, 1.4]:
		await tree.create_timer(wait_s).timeout
		if tree.root.has_focus():
			continue
		var fg := await Helper.run("window-state", {}, 3.0)
		if fg.ok and fg.result is Dictionary and steam_dir != "":
			# Fenster von Steam nach Prozessnamen (der Helfer kennt „proc-windows“ nur in dieser Form).
			var pw := await Helper.run("proc-windows", { "names": Installs.STEAM_PROCS }, 4.0)
			var wins: Array = pw.result.get("windows", []) if pw.ok and pw.result is Dictionary else []
			var h := steam_window_to_close(fg.result, before, wins, me)
			if h != 0:
				await Helper.run("close-window", { "hwnd": h }, 3.0)
		DisplayServer.window_move_to_foreground()
		await Helper.run("focus", { "pid": me }, 3.0)


## Discord-Status setzen. Rückgabe: "" oder warum nicht.
static func set_discord(id: String) -> String:
	_load()
	if not DISCORD_SDK.has(id) or busy.get("discord", false):
		return ""
	if not has_discord():
		return "Discord ist nicht verbunden."
	busy["discord"] = true
	# In einer eigenen Funktion: Bricht sie ab, wird hier trotzdem gelöst (sonst ließe sich der Status bis zum
	# Neustart nicht mehr ändern), und "" gilt nicht als Erfolg.
	var erg: String = await _set_discord(id)
	busy.erase("discord")
	if erg != "ok":
		return erg if erg != "" else "Discord hat nicht geantwortet."
	discord_pick = id
	discord_pick_at = _now()
	_save()
	refresh_discord()
	return ""


## "ok" oder ein Satz, warum es nicht ging.
static func _set_discord(id: String) -> String:
	if demo():
		await (Engine.get_main_loop() as SceneTree).create_timer(0.35).timeout
		return "ok"
	var r: Dictionary = await DiscordChat.runner.call("dsdk-status", { "status": int(DISCORD_SDK[id]) }, 12.0)
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if not bool(r.get("ok", false)) or not bool(res.get("ok", false)):
		return discord_error(str(res.get("error", r.get("error", ""))))
	return "ok"


## Fehler des Helfers als Satz.
static func discord_error(e: String) -> String:
	var low := e.to_lower()
	if low == "unsupported" or low.contains("entry point") or low.contains("einstiegspunkt"):
		return "Diese Fassung der Discord-Bibliothek kann den Status nicht ändern. Bitte in der Discord-App."
	if low.contains("unknown command") or low.contains("unbekannt"):
		return "Der Helfer ist zu alt. Uzai bitte neu starten."
	if e == "":
		return "Discord hat nicht geantwortet."
	return "Discord: " + e
