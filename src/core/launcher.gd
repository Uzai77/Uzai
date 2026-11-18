extends Node
## Startet Spiele (Emulator, Steam, Epic, EA, die weiteren Launcher aus stores.gd, eigene .exe), legt ShaderGlass über Emulatorfenster,
## setzt den Discord-Status, misst die Spielzeit und holt Uzai nach dem Spiel zurück.

signal state(text: String)
signal started(game: Dictionary)
## Das Spielfenster (oder das Fenster seines Starters) ist da – erst dann geht Uzai aus dem Weg.
## Früher minimierte sich Uzai nach festen 2,5 s: bei Steam (Update, Cloud, Anticheat) sah man
## dann den Desktop, und das Spiel bekam keinen Fokus.
signal window_ready(game: Dictionary)
signal window_changed           ## nach window_ready: ein anderes Fenster ist jetzt das Spielfenster
signal ended(game: Dictionary, seconds: int)
signal failed(game: Dictionary, reason: String)
## Das Spielfenster antwortet nicht mehr (oder wieder), siehe _check_hung.
signal hung_changed(on: bool)
## Nach „ended“: Uzai hat einen Absturz oder Fehlstart erkannt (Trouble.verdict).
signal crashed(game: Dictionary, verdict: Dictionary)
## Beenden ging nicht (Adminrechte, Windows lehnt ab, Wächter): Uzai bleibt bedienbar (main: Guide mit
## „Sofort beenden“, „Zur Startseite“, „Zurück zum Spiel“). text: warum.
signal quit_stuck(game: Dictionary, text: String)

const Fremd := preload("res://src/core/fremd.gd")
const Logdatei := preload("res://src/core/logdatei.gd")
const EpicScanner := preload("res://src/library/epic_scanner.gd")
const EpicInstallS := preload("res://src/core/epic_install.gd")
const EaScanner := preload("res://src/library/ea_scanner.gd")
const Stores := preload("res://src/library/stores.gd")
const RemotePlay := preload("res://src/core/remote_play.gd")
const SteamGuide := preload("res://src/core/steam_guide.gd")
const RemotePlayPads := preload("res://src/core/remote_play_pads.gd")
const SpielerEmus := preload("res://src/core/spieler_emus.gd")
const EmuHintergrund := preload("res://src/core/emu_hintergrund.gd")
const Trouble := preload("res://src/core/trouble.gd")
const GamePresence := preload("res://src/core/game_presence.gd")
const ProfileRun := preload("res://src/core/profile_run.gd")
const BildTon := preload("res://src/core/bild_ton.gd")
const Sicher := preload("res://src/core/sicher.gd")
const DiscsS := preload("res://src/core/discs.gd")
const AppSteuerung := preload("res://src/core/app_steuerung.gd")
const PcScanner := preload("res://src/library/pc_scanner.gd")
const Zustand := preload("res://src/core/zustand.gd")

var in_game := false:
	set(neu):
		in_game = neu
		_lauf_melden()
var guide_open := false   ## main setzt das; solange der Guide offen ist, nie das Spiel nach vorn holen
## main setzt das (src/room/fernsehspiel.gd fokus_gesperrt): Läufst du im Zimmer, während das Spiel im
## Fernseher weiterläuft, gehört der Controller Uzai – focus_game holt das Spiel dann nicht nach vorn.
var fokus_gesperrt := false
## Der laufende Emulator hält ohne Fokus an, weil er den Controller im Hintergrund nicht abschalten
## kann (emu_hintergrund.gd „anhalten“) – das Zimmer sagt es beim Aufstehen.
var hintergrund_anhalten := false
var current: Dictionary = {}
var pid := 0
var paused := false
var _sg_pid := 0
var _sg_crashes := 0
var _start_time := 0
var _kind := ""
var _steam_seen := false
var _gone := 0
var _nachfolger_da := false  ## Starter beendet, das Spiel läuft im Ordner weiter: ab da gilt der Ordner (einmal je Start)
## So lange nach dem Start darf Uzai einen Nachfolger im Spielordner übernehmen (Starter wie „FL 2027 start.exe“
## starten das Spiel und beenden sich nach Sekunden; später gehörte ein anderer Prozess im Ordner nicht mehr dazu).
const NACHFOLGER_S := 300
var _timer: Timer
var _polling := false
var _track_dir := ""        ## Ordner, in dem Uzai den Spielprozess sucht (Epic, Verknüpfungen)
var remote_play := false    ## läuft über den Remote-Play-Spender (Steam hält es für den Spender)
var _rp_id := ""            ## Auftrag an den Starter im Spender
var _rp_base := -1          ## Controller beim Start der Remote-Play-Sitzung (-1 = noch unbekannt)
var _rp_pads := -1          ## zuletzt gezählte Controller
var _rp_invite_at := 0      ## letzte Einladung aus Uzai (Unix-Zeit)
var _rp_invite_name := ""
var _rp_hint_shown := false
var _rp_overlay_open := false  ## nach einer Einladung lässt Steam oft sein Overlay im Spiel offen
var window_seen := false:      ## das Spielfenster ist da (siehe window_ready)
	set(neu):
		window_seen = neu
		_lauf_melden()
var window_is_game := false    ## … und es gehört dem Spiel selbst (sonst ein Starter: Steam-Dialog, Launcher)
var _launching := false:       ## Start läuft noch (gegen doppeltes Starten bei schnellem A)
	set(neu):
		_launching = neu
		_lauf_melden()
var _launch_gen := 0
var _presence_shown := false   ## Uzai hat einen Discord-Status zum Spiel gesetzt
var _known_windows: Array = [] ## Fenster vor dem Start: neu ist, was danach kommt
var _game_hwnd := 0
var _pads_beim_start: Array = []     ## Controller (uz_id) beim Start des Emulator-Spiels
var _pads_gemeldet := {}             ## schon gemeldete neue Controller (je Spiel einmal)
var _pads_kind := ""                 ## Art des laufenden Emulators (spieler_emus.kind_of)
## Wer im laufenden Emulator-Spiel Spieler 1 ist: { name, grund } (für Guide › Spieler & Controller).
var pads_start := {}
## main setzt das: fragt, ob ein Programm mit Adminrechten trotzdem starten soll (name, exe) -> bool.
var confirm_admin: Callable
## main setzt das: Vorhang zu (an, art: „beenden“ vor dem Schließen eines Emulators und vor jedem
## harten Beenden, „schliessen“, wenn das Spielfenster beim höflichen Schließen verschwand), bzw. wieder
## auf (false) – main_fenster.gd beenden_vorhang.
var quit_cover: Callable
var quitting := false:          ## „Beenden“ läuft gerade (ein zweites Beenden macht es hart, siehe quit_game)
	set(neu):
		quitting = neu
		_lauf_melden()
var quit_haengt := false:       ## das letzte Beenden ging nicht – Uzai blieb bedienbar, der nächste Versuch ist hart
	set(neu):
		quit_haengt = neu
		_lauf_melden()
var _quit_hart := false:        ## nicht (länger) höflich warten: noch einmal gedrückt, Fenster hängt, force
	set(neu):
		_quit_hart = neu
		_lauf_melden()
var _quit_id := 0               ## jedes Beenden zählt hoch; der Wächter löst eine alte Kette so ab
var _admin_need := {}           ## Programmdatei → verlangt Adminrechte (je Sitzung einmal geprüft)
var hung := false:              ## das Spielfenster antwortet nicht (siehe _check_hung)
	set(neu):
		hung = neu
		_lauf_melden()
var frozen := false             ## der Ruhemodus hat das Spiel angehalten (rest.gd) – dann hängt nichts
var _hung_since := 0
var _hung_pid := 0              ## Prozess hinter dem hängenden Fenster
var _hung_at := 0               ## letzte Abfrage (ms)
var _quit_asked := false        ## über Uzai beendet: dann ist das Ende nie ein Absturz


## Hast du das Spiel über Uzai beendet (Guide › Beenden, Halten)? Dann lag sein Ende nicht am Guide.
func ueber_uzai_beendet() -> bool:
	return _quit_asked
var _schnell := 0               ## so viele Rundgänge noch im kurzen Takt (Spielfenster verschwand)
## Spiel-Profil (Bildschirm, Ton, Controller, Aktionen): vor dem Start an, nach dem Spiel zurück.
var profile: Node

const WINDOW_HINT_MS := 45000   ## so lange warten, bevor der Ladebildschirm „Warte …“ sagt
const WINDOW_MAX_MS := 120000   ## danach geht Uzai trotzdem aus dem Weg
## Nach dem ersten Fenster: so lange höchstens warten, bis es vorn liegt und den Bildschirm füllt
## (Emulatoren öffnen erst ein normales Fenster und schalten dann auf Vollbild). Ein Starter
## (Steam-, Epic- oder Spiel-Launcher) bekommt weniger Zeit – den will man ja bedienen.
const READY_GAME_MS := 8000
const READY_STARTER_MS := 4000
const READY_SETTLED_MS := 2500  ## Spielfenster vorn, aber im Fenstermodus: so lange unverändert, dann gilt es
const STEAM_WAIT_S := 30.0      ## so lange auf die Anmeldung eines still gestarteten Steam warten
const POLL_S := 1.5             ## Takt, in dem Uzai nachsieht, ob das Spiel noch läuft
const POLL_SCHNELL_S := 0.5     ## … nachdem sein Fenster verschwand (der Vorhang ist dann schon zu)
## Beenden: so lange darf sich das Spiel nach der Bitte (wie Alt+F4) selbst schließen und speichern,
## dann beendet Uzai, was sicher dazugehört. Emulatoren kürzer – ihre Rückfrage beantwortet Uzai.
const QUIT_SAUBER_S := { "rom": 4.0, "pc": 8.0, "steam": 8.0 }
const QUIT_SAUBER_SONST_S := 6.0
const QUIT_NACH_S := 2.0        ## nach dem harten Beenden: spätestens dann ist es weg
## Wächter: spätestens dann ist „Beenden“ fertig, so oder so (höflich 8 s, hart mit allen Zeitgrenzen
## des Helfers weniger) – Uzai bleibt danach bedienbar.
const QUIT_MAX_S := 25.0
var quit_max_s := QUIT_MAX_S    ## (Tests setzen es kürzer: tests/logic_beenden.gd)
const QUIT_PRUEF_S := 0.25
## Eigene Apps (src/core/apps_extern.gd): Store-Apps und Programme laufen wie ein Spiel mit der
## Quelle „app“ – Guide-Taste, Vorhang, Beenden –, aber ohne Spielzeit, Erfolge, Status bei Discord
## oder Steam und ohne Spiel-Profil. „Zurück zu Uzai“ lässt sie weiterlaufen (leave_app); kept merkt
## sich solche Apps { Kennung: { pid, hwnd } }, A in Apps holt sie wieder nach vorn.
const APP := "app"
var kept := {}
## Eigene App vorn wie auf einer Konsole (src/core/app_steuerung.gd): app_fenster ist das geprüfte
## App-Fenster, app_pad: Uzai übersetzt gerade den Controller für sie; app_art: wie sie den Bildschirm
## füllt ("schon", "taste" = eigenes Vollbild der App, "randlos", "" = gar nicht).
var app_fenster := 0
var app_pad := false
var app_art := ""


static func is_app(g: Dictionary) -> bool:
	return str(g.get("source", "")) == APP


## Lebenslauf des Spiels aus den Schaltern (_launching, in_game, window_seen, hung, quitting, _quit_hart,
## quit_haengt) – für Zustand.lage() und den Fehlerbericht: aus, startet (Start läuft), wartet (läuft, sein Fenster
## kommt noch), laeuft, antwortet_nicht (Spielfenster hängt), beenden bzw. beenden_hart (Beenden läuft), haengt
## (Beenden ging nicht, Uzai bleibt bedienbar).
func lauf() -> String:
	if not in_game:
		return "startet" if _launching else "aus"
	if quitting:
		return "beenden_hart" if _quit_hart else "beenden"
	if quit_haengt:
		return "haengt"
	if hung:
		return "antwortet_nicht"
	return "laeuft" if window_seen else "wartet"


func _lauf_melden() -> void:
	Zustand.melden("spiel.lauf", lauf())


const KEIN_PROZESS := "Kein Prozess gefunden. Im Spielmenü oder Task-Manager beenden."


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_S
	_timer.timeout.connect(_poll)
	add_child(_timer)
	profile = ProfileRun.new()
	add_child(profile)
	window_ready.connect(profile.on_window)
	Config.changed.connect(func(k: String) -> void:
		if k == "steam.status_nonsteam" and in_game:
			_steam_status(true)
		# Status ein- oder ausgeschaltet: sofort zeigen bzw. leeren, nicht erst beim nächsten Spiel.
		elif k in ["accounts.discord_presence", "accounts.discord_client_id"] and in_game:
			_presence(true)
	)
	# Ist Uzai während einer Remote-Play-Sitzung abgestürzt: Emulator-Einstellungen zurück.
	call_deferred("_restore_pads")
	call_deferred("_pads_im_spiel")


## Neuer Controller mitten im Emulator-Spiel: Hinweis, wie er dazukommt (der Emulator liest seine
## Belegung nur beim Start; „Spiel mit neuer Zuordnung neu starten“ merkt sich die Stelle).
func _pads_im_spiel() -> void:
	Pads.changed.connect(func() -> void:
		if not in_game or _pads_kind == "" or str(current.get("source", "rom")) != "rom":
			return
		for e in SpielerEmus.neu_im_spiel(_pads_kind, _pads_beim_start, Pads.pads, _pads_gemeldet):
			_pads_gemeldet[str(e.id)] = true
			log_launch("Controller: neuer Controller im Spiel – Spieler %d (%s), gilt nach Neustart des Spiels" % [int(e.slot), str(e.name)])
			Toasts.show_toast("Spieler %d: %s" % [int(e.slot), str(e.name)], "Guide › Spieler & Controller › Spiel mit neuer Zuordnung neu starten.",
				"controller", { "ms": 6000 }))


func _restore_pads() -> void:
	RemotePlayPads.restore_all()
	# Und was ein Emulator-Start fürs Weiterlaufen im Hintergrund umgestellt hatte (emu_hintergrund.gd).
	EmuHintergrund.zurueck()
	# Ebenso, was ein Spiel-Profil an Windows umgestellt hatte (Bildschirm, HDR, Ton …).
	profile.restore_pending()
	# Und eine Auflösung aus „Bild & Ton“, deren Rückfrage ein Absturz unterbrochen hat.
	BildTon.restore_pending()


# --- Starten -----------------------------------------------------------------

## Startphase: der Start läuft (Emulator vielleicht schon da), in_game ist noch falsch.
func is_starting() -> bool:
	return _launching and not in_game


func launch(g0: Dictionary) -> void:
	# Gekauft, aber nicht installiert (Epic): nichts zu starten – installiert wird über main.install_epic().
	if in_game or _launching or Library.owned_only(g0):
		return
	# Dasselbe Spiel in mehreren Launchern: über den gewählten starten (ID und Titel bleiben).
	var g := Library.launch_target(g0)
	_launching = true
	if not is_app(g):
		await profile.apply(g)
	var ok := await _launch(g)
	_launching = false
	if not ok:
		profile.restore()
		return
	in_game = true
	_start_time = int(Time.get_unix_time_from_system())
	Library.touch(str(g.id))
	# Disc vom Laufwerk und eigene Apps: kein Spiel der Bibliothek – nichts davon bleibt zurück.
	if not str(g.id).begins_with("disc:") and not is_app(g):
		Config.set_value("system.last_game", str(g.id))
	_presence(true)
	_steam_status(true)
	started.emit(g)
	_timer.start()
	if is_app(g):
		_await_app_window(g, _launch_gen)
	else:
		_await_window(g, _launch_gen)


func _launch(g: Dictionary) -> bool:
	current = g
	_launch_gen += 1
	window_seen = false
	window_is_game = false
	_game_hwnd = 0
	_known_windows = await _window_snapshot()
	_kind = str(g.get("source", "rom"))
	pid = 0
	_sg_pid = 0
	_steam_seen = false
	_gone = 0
	_nachfolger_da = false
	paused = false
	remote_play = false
	_rp_id = ""
	_rp_base = -1
	_rp_pads = -1
	_rp_invite_at = 0
	_rp_invite_name = ""
	_rp_hint_shown = false
	_rp_overlay_open = false
	hung = false
	frozen = false
	_hung_since = 0
	_hung_pid = 0
	_quit_asked = false
	if RemotePlay.wants(g):
		if not await _launch_remote_play(g):
			return false
		# Über den Spender kennt Uzai den Prozess – auch bei Epic-Spielen (dann wie ein PC-Spiel).
		_kind = "rom" if str(g.get("source", "rom")) == "rom" else "pc"
	else:
		match _kind:
			APP:
				if not await _launch_app(g):
					return false
			"rom":
				if not await _launch_rom(g):
					return false
			"steam":
				await _ensure_steam()
				state.emit("Steam startet %s …" % g.title)
				# start_url: „Beitreten“ bei einem Freund (Steam startet das Spiel und verbindet).
				var su := str(g.get("start_url", ""))
				OS.shell_open(su if Sicher.steam_join_ok(su) else "steam://rungameid/%d" % int(g.get("appid", 0)))
			"epic":
				if EpicInstallS.is_uzai(g):
					# Von Uzai installiert: die Programmdatei selbst, mit Epics üblichen Parametern und
					# – wie Legendary – einem frischen Einmal-Code für die Epic-Anmeldung im Spiel
					# (erst direkt vor dem Start geholt, siehe _launch_exe). Uzai kennt dann den
					# Prozess wie bei einem PC-Spiel.
					var ge := g.duplicate()
					ge["epic_start"] = true
					if not await _launch_exe(ge):
						return false
					_kind = "pc"
				else:
					state.emit("Epic startet %s …" % g.title)
					OS.shell_open(EpicScanner.launch_uri(g))
			"ea":
				# Über die EA app (Anmeldung, Kopierschutz); ohne Start-Link die Programmdatei selbst.
				# Das Spielende erkennt Uzai wie bei Epic am Prozess im Spielordner.
				var ea_uri := EaScanner.launch_uri(g)
				if ea_uri != "":
					state.emit("EA app startet %s …" % g.title)
					OS.shell_open(ea_uri)
				elif not await _launch_exe(g):
					return false
			_:
				if Stores.is_extra(_kind):
					if not await _launch_store(g):
						return false
				elif not await _launch_exe(g):
					return false
	return true


## Weitere Launcher (stores.gd): über den Link des Launchers (Ubisoft, Xbox, Amazon), sein Programm
## mit festen, geprüften Parametern (GOG Galaxy, Battle.net, Riot) oder die Programmdatei des Spiels
## (GOG ohne Galaxy, itch.io). Das Spielende erkennt Uzai wie bei Epic am Prozess im Spielordner –
## nie am Launcher selbst, der nach dem Spiel weiterläuft.
func _launch_store(g: Dictionary) -> bool:
	var cl: Dictionary = await Library.ensure_store_clients()
	var plan := Stores.launch_plan(g, cl, bool(Config.get_value("library.gog_galaxy", true)))
	var who := Stores.name_of(_kind)
	if plan.has("uri"):
		state.emit("%s startet %s …" % [who, g.title])
		OS.shell_open(str(plan.uri))
		return true
	if not plan.has("exe"):
		failed.emit(g, str(plan.get("why", "%s kann dieses Spiel gerade nicht starten." % who)))
		return false
	var exe := str(plan.exe)
	if str(plan.get("via", "")) == "exe" and not await _admin_ok(exe, str(g.title)):
		failed.emit(g, "")
		return false
	var via := str(plan.get("via", ""))
	if via == "exe":
		state.emit("%s startet …" % g.title)
	else:
		state.emit("%s startet %s …" % ["GOG Galaxy" if via == "galaxy" else who, g.title])
	var p := 0
	if Helper.available:
		var r := await Helper.run("start", { "exe": _win(exe), "args": str(plan.get("args", "")), "dir": _win(str(plan.get("dir", exe.get_base_dir()))) }, 30.0)
		p = int((r.result as Dictionary).get("pid", 0)) if r.ok and r.result is Dictionary else 0
		if not r.ok and bool(r.get("timeout", false)):
			p = 1
	else:
		p = OS.create_process(exe, Helper.win_args(split_args(str(plan.get("args", "")))))
	if p <= 0:
		failed.emit(g, "%s ließ sich nicht starten." % who)
		return false
	# Der Prozess ist der Launcher bzw. ein Starter: Uzai folgt dem Spielordner, nie dieser Kennung.
	pid = 0
	return true


## Eigene App starten (Helfer „app-start“, prüft alles selbst noch einmal): Store-App über ihre
## App-Kennung, Programm mit Argumentliste. Läuft sie schon im Hintergrund (Zurück zu Uzai), holt
## Uzai sie nur nach vorn – ein Programm startet dann nicht ein zweites Mal. Ohne Windows (Vorschau,
## Tests) läuft sie zum Schein.
func _launch_app(g: Dictionary) -> bool:
	var e: Dictionary = g.get("app", {})
	var aid := str(e.get("id", ""))
	var was: Dictionary = kept.get(aid, {})
	kept.erase(aid)
	if not Config.is_windows() or not Helper.available:
		if Library.demo or not Config.is_windows():
			state.emit("%s startet …" % g.title)
			return true
		failed.emit(g, "Der Windows-Helfer ist gerade nicht bereit.")
		return false
	if str(e.get("kind", "")) == "prog" and int(was.get("pid", 0)) > 0 and await process_alive(int(was.pid)):
		pid = int(was.pid)
		_game_hwnd = int(was.get("hwnd", 0))
		return true
	state.emit("%s startet …" % g.title)
	var req := { "kind": str(e.get("kind", "")) }
	if req.kind == "store":
		req["aumid"] = str(e.get("aumid", ""))
	else:
		req["path"] = str(e.get("path", ""))
		req["args"] = (e.get("args", []) as Array).duplicate()
	var r := await Helper.run("app-start", req, 20.0)
	if not r.ok or not (r.result is Dictionary) or int((r.result as Dictionary).get("pid", 0)) <= 0:
		var err := str(r.get("error", ""))
		failed.emit(g, Helper.klartext(err, "").strip_edges() if err != "" else TranslationServer.translate("%s ließ sich nicht starten.") % g.title)
		return false
	pid = int(r.result.pid)
	return true


## Fenster der App suchen (Store-Apps: der Rahmen um ihren Inhalt; auch ein Fenster, das schon
## offen war) – sonst wie bei Spielen ein neues großes Fenster.
func _await_app_window(g: Dictionary, gen: int) -> void:
	if not Config.is_windows() or not Helper.available:
		_window_found(g, gen, {})
		return
	var t0 := Time.get_ticks_msec()
	while in_game and gen == _launch_gen:
		var h := _game_hwnd
		if h == 0 and (pid > 0 or str((g.get("app", {}) as Dictionary).get("kind", "")) == "store"):
			var r := await Helper.run("app-window", { "pid": pid, "aumid": str((g.get("app", {}) as Dictionary).get("aumid", "")) }, 4.0)
			h = int((r.result as Dictionary).get("hwnd", 0)) if r.ok and r.result is Dictionary else 0
		if not in_game or gen != _launch_gen:
			return
		if h != 0:
			_window_found(g, gen, { "hwnd": h, "pid": pid, "game": true })
			return
		var n := await Helper.run("new-window", { "known": _known_windows, "pids": [pid] if pid > 0 else [], "skip": [OS.get_process_id()] }, 4.0)
		if not in_game or gen != _launch_gen:
			return
		if n.ok and n.result is Dictionary and bool(n.result.get("found", false)):
			var w: Dictionary = n.result
			w["game"] = true
			_window_found(g, gen, w)
			return
		if Time.get_ticks_msec() - t0 > WINDOW_MAX_MS:
			_window_found(g, gen, {})
			return
		await get_tree().create_timer(0.5).timeout


## „Zurück zu Uzai“: die App läuft weiter, Uzai kommt nach vorn (wie nach dem Spielende, nur ohne
## Beenden). A in Apps holt sie wieder nach vorn.
func leave_app() -> void:
	if not in_game or not is_app(current) or quitting:
		return
	var aid := str((current.get("app", {}) as Dictionary).get("id", ""))
	if aid != "":
		kept[aid] = { "pid": pid, "hwnd": _game_hwnd }
	_quit_asked = true
	_finish()


# --- Eigene App wie auf einer Konsole (src/core/app_steuerung.gd) ------------------------------------

## Die App liegt vorn: randlos auf den ganzen Bildschirm – erst ihr eigenes Vollbild (F11 bei Web-Apps,
## nur an genau dieses Fenster, wenn es vorn ist), sonst nimmt der Helfer dem Fenster Titelleiste und
## Rahmen. Uzai liegt dabei noch oben (Startbildschirm): Man sieht das Umschalten nicht.
func _app_vorn(gen: int) -> void:
	var e: Dictionary = current.get("app", {})
	app_fenster = 0
	app_art = ""
	if not Config.is_windows() or not Helper.available or _game_hwnd == 0:
		return
	var prof := AppSteuerung.profil(e)
	var r := await Helper.run("app-vollbild", AppSteuerung.vollbild_auftrag(e, _game_hwnd, true, str(prof.vollbild)), 4.0)
	if gen != _launch_gen or not in_game:
		return
	var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
	if str(res.get("art", "")) == "taste":
		await get_tree().create_timer(AppSteuerung.TASTE_WARTEN_MS / 1000.0).timeout
		if gen != _launch_gen or not in_game:
			return
		r = await Helper.run("app-vollbild", AppSteuerung.vollbild_auftrag(e, _game_hwnd, true), 4.0)
		res = r.result if r.ok and r.result is Dictionary else {}
		if str(res.get("art", "")) == "schon":
			res["art"] = "taste"
	if not bool(res.get("done", false)):
		log_launch("App-Fenster nicht übernommen: %s" % str(res.get("why", r.get("error", ""))))
		return
	app_fenster = _game_hwnd
	app_art = str(res.get("art", ""))
	log_launch("App im Vollbild (%s, Profil %s)" % [app_art, str(prof.id)])
	await app_steuerung(AppSteuerung.an(e))


## Controller als Tasten für die App vorn ein- oder ausschalten (Helfer „app-pad“, Hauptweg).
func app_steuerung(on: bool) -> void:
	if not Config.is_windows() or not Helper.available:
		app_pad = false
		return
	var e: Dictionary = current.get("app", {})
	var req := AppSteuerung.pad_auftrag(e, app_fenster) if on and in_game and is_app(current) and app_fenster != 0 else {}
	if req.is_empty():
		app_pad = false
		await Helper.run("app-pad", { "an": false }, 3.0)
		return
	var r := await Helper.run("app-pad", req, 4.0)
	app_pad = r.ok and r.result is Dictionary and bool((r.result as Dictionary).get("an", false))


## Im Guide umgestellt: gilt für diese App ab sofort und beim nächsten Start.
func app_steuerung_setzen(on: bool) -> void:
	if not is_app(current):
		return
	AppSteuerung.setzen(current.get("app", {}), on)
	await app_steuerung(on)


## Die App geht (Schließen, Zurück zu Uzai): Controller-Übersetzung aus, das Fenster wie vorher – erst,
## wenn Uzai vorn ist (sonst sähe man es kleiner werden).
func _app_ende(e: Dictionary) -> void:
	var h := app_fenster
	app_fenster = 0
	app_art = ""
	if not Config.is_windows() or not Helper.available:
		app_pad = false
		return
	if app_pad:
		app_pad = false
		Helper.run("app-pad", { "an": false }, 3.0)
	if h == 0:
		return
	var req := AppSteuerung.vollbild_auftrag(e, h, false)
	if req.is_empty():
		return
	await get_tree().create_timer(1.0).timeout
	# Inzwischen wieder geöffnet (A in Apps): dann bleibt es im Vollbild.
	if (in_game or _launching) and str((current.get("app", {}) as Dictionary).get("id", "")) == str(e.get("id", "")):
		return
	Helper.run("app-vollbild", req, 4.0)


## Läuft diese App noch im Hintergrund? Fragt nach und vergisst, was nicht mehr läuft.
func app_kept(aid: String) -> bool:
	var k: Dictionary = kept.get(aid, {})
	if k.is_empty():
		return false
	var alive := false
	if int(k.get("hwnd", 0)) != 0 and Config.is_windows() and Helper.available:
		var r := await Helper.run("window-alive", { "hwnd": int(k.hwnd) }, 3.0)
		alive = r.ok and r.result is Dictionary and bool(r.result.get("alive", false))
	elif int(k.get("pid", 0)) > 0:
		alive = await process_alive(int(k.pid))
	else:
		alive = not Config.is_windows()
	if not alive:
		kept.erase(aid)
	return alive


## Läuft Steam nicht, startet es über steam:// mit Update-, Anmelde- und Bibliotheksfenster im
## Vordergrund. Darum vorher still starten (-silent, minimiert ohne Fokus) und warten, bis jemand
## angemeldet ist; höchstens STEAM_WAIT_S, danach geht der Start trotzdem weiter.
func _ensure_steam() -> void:
	if not Config.is_windows() or not Helper.available:
		return
	var r := await Helper.run("steam-state", {}, 4.0)
	if not r.ok or not (r.result is Dictionary) or bool(r.result.get("running", false)):
		return
	# Steam ist zu: der Moment, neue Konten bei der Guide-Taste nachzuziehen (steam_guide.gd).
	await SteamGuide.nachziehen(get_tree())
	var s := await Helper.run("steam-silent", {}, 6.0)
	if not s.ok or not (s.result is Dictionary) or not bool(s.result.get("started", false)):
		return
	state.emit("Steam wird vorbereitet …")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < STEAM_WAIT_S * 1000.0:
		await get_tree().create_timer(1.0).timeout
		r = await Helper.run("steam-state", {}, 4.0)
		if r.ok and r.result is Dictionary and int(r.result.get("user", 0)) != 0:
			# Angemeldet; Steam braucht danach noch einen Moment, bis es Startbefehle annimmt.
			await get_tree().create_timer(2.0).timeout
			return


# --- Warten auf das Spielfenster -------------------------------------------------------------

func _window_snapshot() -> Array:
	if not Config.is_windows() or not Helper.available:
		return []
	var r := await Helper.run("windows-snapshot", { "skip": [OS.get_process_id()] }, 4.0)
	return r.result.get("hwnds", []) if r.ok and r.result is Dictionary else []


## Wartet, bis ein neues großes Fenster da ist (Spiel oder sein Starter), holt es nach vorn und
## meldet window_ready. Ohne Helfer (Linux, Tests) sofort.
func _await_window(g: Dictionary, gen: int) -> void:
	if not Config.is_windows() or not Helper.available:
		_window_found(g, gen, {})
		return
	var t0 := Time.get_ticks_msec()
	var hinted := false
	var pids: Array = []
	var pids_at := -10000
	while in_game and gen == _launch_gen:
		# Prozesse suchen (Steam/Epic: im Spielordner) ist teurer – nur alle 3 s.
		if Time.get_ticks_msec() - pids_at > 3000:
			pids = await game_pids()
			pids_at = Time.get_ticks_msec()
		var r := await Helper.run("new-window", { "known": _known_windows, "pids": pids, "skip": [OS.get_process_id()] }, 4.0)
		if not in_game or gen != _launch_gen:
			return
		if r.ok and r.result is Dictionary and bool(r.result.get("found", false)):
			_window_found(g, gen, r.result)
			return
		var waited := Time.get_ticks_msec() - t0
		if waited > WINDOW_MAX_MS:
			_window_found(g, gen, {})
			return
		if waited > WINDOW_HINT_MS and not hinted:
			hinted = true
			state.emit("Warte auf das Spielfenster … · Guide: Spiel beenden")
		await get_tree().create_timer(0.6).timeout


func _window_found(g: Dictionary, gen: int, w: Dictionary) -> void:
	if gen != _launch_gen or not in_game:
		return
	_game_hwnd = int(w.get("hwnd", 0))
	window_is_game = bool(w.get("game", false))
	if _game_hwnd != 0 and not guide_open and not is_app(current):
		Helper.run("focus", { "hwnd": _game_hwnd, "pids": [int(w.get("pid", 0))] })
	# Eigene App: gleich randlos im Vollbild (Uzai deckt noch; F11 braucht sie vorn), dann wie ein Spiel.
	if is_app(current) and _game_hwnd != 0:
		if not guide_open:
			await Helper.run("focus", { "hwnd": _game_hwnd, "pids": [int(w.get("pid", 0))] }, 3.0)
		if gen != _launch_gen or not in_game:
			return
		await _app_vorn(gen)
		if gen != _launch_gen or not in_game:
			return
	# Erst wenn das Fenster wirklich vorn liegt (und meist schon im Vollbild ist), geht Uzais
	# Startbildschirm weg. Vorher sah man dazwischen das Emulatorfenster, die Taskleiste und den
	# Mauszeiger.
	if _game_hwnd != 0:
		await _await_front(gen, bool(w.get("game", false)), int(w.get("pid", 0)))
		if gen != _launch_gen or not in_game:
			return
	window_seen = true
	window_ready.emit(g)
	# Verknüpfung ohne bekannten Prozess: dem jeweils neuesten großen Fenster folgen (erst der
	# Starter, dann das Spiel). Daran erkennt Uzai das Spielende und kann es beenden.
	if _kind == "link" and _game_hwnd != 0:
		_follow_link_windows(gen)
		return
	# Erst kam ein Starter (Steam-Fenster, Epic, Launcher des Spiels)? Sobald das Spiel selbst ein
	# Fenster hat, bekommt es den Fokus – sonst landen Controller und Tastatur im Starter.
	if not w.is_empty() and not bool(w.get("game", false)):
		_follow_game_window(gen)


## Wartet, bis das gefundene Fenster (oder ein anderes Fenster des Spiels, auch ShaderGlass) vorn
## liegt und den Bildschirm füllt; höchstens READY_GAME_MS bzw. READY_STARTER_MS. Liegt es vorn,
## bleibt aber im Fenstermodus (so eingestellt), gilt es nach READY_SETTLED_MS als fertig.
## Liegt etwas anderes vorn (Uzai, ein Starter), holt Uzai das Spiel nach vorn – nur das Spiel.
func _await_front(gen: int, is_game: bool, win_pid: int) -> void:
	if not Config.is_windows() or not Helper.available:
		return
	var t0 := Time.get_ticks_msec()
	var limit := READY_GAME_MS if is_game else READY_STARTER_MS
	var pids := await game_pids()
	if win_pid > 0 and not pids.has(win_pid) and is_game:
		pids.append(win_pid)
	if _sg_pid > 0:
		pids.append(_sg_pid)
	var good := 0
	var settled_at := 0
	var settled_key := ""
	var focus_at := Time.get_ticks_msec()
	var last: Dictionary = {}
	while in_game and gen == _launch_gen and Time.get_ticks_msec() - t0 < limit:
		await get_tree().create_timer(0.25).timeout
		if not in_game or gen != _launch_gen or guide_open:
			continue
		var r := await Helper.run("window-state", { "pids": pids, "hwnd": _game_hwnd }, 2.0)
		if not r.ok or not (r.result is Dictionary):
			continue
		var st: Dictionary = r.result
		last = st
		var now := Time.get_ticks_msec()
		if bool(st.get("fg_game", false)) and bool(st.get("fg_full", false)):
			good += 1
			if good >= 2:
				log_launch("vorn im Vollbild nach %d ms: „%s“ (%s)" % [now - t0, str(st.get("fg_title", "")), str(st.get("fg_class", ""))])
				return
			continue
		good = 0
		if bool(st.get("fg_game", false)):
			# Vorn, aber im Fenster: wartet, bis sich Größe und Fenster nicht mehr ändern.
			var key := "%s|%s|%s" % [str(st.get("fg_hwnd", 0)), str(st.get("fg_w", 0)), str(st.get("fg_h", 0))]
			if key != settled_key:
				settled_key = key
				settled_at = now
			elif now - settled_at >= READY_SETTLED_MS:
				log_launch("vorn im Fenster nach %d ms: „%s“ %sx%s" % [now - t0, str(st.get("fg_title", "")), str(st.get("fg_w", 0)), str(st.get("fg_h", 0))])
				return
			continue
		settled_key = ""
		# Das Fenster ist wieder zu (ein Starter hat sich geschlossen): nicht weiter warten.
		if not bool(st.get("target_alive", true)) and not is_game:
			break
		if now - focus_at > 1200:
			focus_at = now
			Helper.run("focus", { "hwnd": _game_hwnd, "pids": pids })
	log_launch(
			"nicht vorn nach %d ms (Grenze), vorn: „%s“ (%s, Prozess %s, Vollbild %s)" % [Time.get_ticks_msec() - t0, str(last.get("fg_title", "")),
			str(last.get("fg_class", "")), str(last.get("fg_pid", "")), str(last.get("fg_full", ""))])


## Das zuletzt gefundene Spielfenster (0: keins bekannt).
## Prozess, dem das Spielfenster gehört (0: unbekannt). Bei Spielen aus einem Laden ist pid 0; der
## Helfer nennt den Prozess hinter dem Fenster. Ohne Fenster: der gestartete Prozess.
func fenster_pid() -> int:
	if _game_hwnd != 0 and Helper.available:
		var w := await Helper.run("window-hung", { "hwnd": _game_hwnd }, 2.0)
		var p := int((w.result as Dictionary).get("pid", 0)) if w.ok and w.result is Dictionary else 0
		if p > 4:
			return p
	return maxi(pid, 0)


## Fenster, die es vor diesem Start schon gab (für „neu seit dem Start“).
func fenster_vorher() -> Array:
	return _known_windows


func game_hwnd() -> int:
	return _game_hwnd


## Wartet, bis Uzai nicht mehr vorn liegt (Guide zu, Fenster minimiert), höchstens max_ms.
## Tasten fürs Spiel (Discord, Lossless Scaling) gingen sonst an Uzai.
func wait_uzai_away(max_ms := 2500) -> void:
	if not Config.is_windows():
		return
	var t0 := Time.get_ticks_msec()
	while (guide_open or get_window().has_focus()) and Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().create_timer(0.1).timeout


## Protokoll des Spielstarts (logs/launch.log): wann welches Fenster vorn lag.
func log_launch(text: String) -> void:
	if Library.demo:
		return
	Logdatei.zeile(Config.path("logs/launch.log"), "%s: %s" % [str(current.get("title", "")), text], 200000)


func _follow_link_windows(gen: int) -> void:
	var known := _known_windows.duplicate()
	known.append(_game_hwnd)
	var t0 := Time.get_ticks_msec()
	while in_game and gen == _launch_gen and Time.get_ticks_msec() - t0 < WINDOW_MAX_MS:
		await get_tree().create_timer(3.0).timeout
		if not in_game or gen != _launch_gen:
			return
		var r := await Helper.run("new-window", { "known": known, "pids": [], "skip": [OS.get_process_id()] }, 4.0)
		if r.ok and r.result is Dictionary and bool(r.result.get("found", false)):
			_game_hwnd = int(r.result.get("hwnd", 0))
			known.append(_game_hwnd)
			window_is_game = true          # nach dem Starter: das neueste große Fenster ist das Spiel
			window_changed.emit()
			if not guide_open:
				Helper.run("focus", { "hwnd": _game_hwnd, "pids": [int(r.result.get("pid", 0))] })


func _follow_game_window(gen: int) -> void:
	var known := _known_windows.duplicate()
	known.append(_game_hwnd)
	var t0 := Time.get_ticks_msec()
	while in_game and gen == _launch_gen and Time.get_ticks_msec() - t0 < WINDOW_MAX_MS:
		await get_tree().create_timer(2.0).timeout
		if not in_game or gen != _launch_gen:
			return
		var pids := await game_pids()
		if pids.is_empty():
			if pid <= 0 and str(current.get("install_dir", "")) == "":
				return          # Prozess nicht bestimmbar (Verknüpfung): nichts zu verfolgen
			continue
		var r := await Helper.run("new-window", { "known": known, "pids": pids, "skip": [OS.get_process_id()] }, 4.0)
		if r.ok and r.result is Dictionary and bool(r.result.get("game", false)):
			_game_hwnd = int(r.result.get("hwnd", 0))
			window_is_game = true
			window_changed.emit()
			if not guide_open:
				Helper.run("focus", { "hwnd": _game_hwnd, "pids": pids })
			return


func _launch_rom(g: Dictionary) -> bool:
	var cmd := _rom_command(g)
	if cmd.has("error"):
		failed.emit(g, str(cmd.error))
		return false
	var emu: Dictionary = cmd.emu
	if not await _admin_ok(str(cmd.exe), str(emu.get("name", "Der Emulator"))):
		failed.emit(g, "")
		return false
	_spieler_einrichten(g, cmd)
	_hintergrund_einrichten(cmd)
	state.emit("%s startet …" % emu.get("name", "Emulator"))
	pid = await _start_process(str(cmd.exe), str(cmd.args), str(cmd.dir))
	if pid <= 0:
		failed.emit(g, "%s ließ sich nicht starten." % emu.get("name", "Der Emulator"))
		return false
	_apply_filter(g, cmd.sys, emu)
	return true


## Emulator, Parameter und Ordner für ein Emulator-Spiel – oder { error }.
func _rom_command(g: Dictionary) -> Dictionary:
	var sys := Config.system(str(g.get("system", "")))
	var emu_id := str(g.get("emulator", sys.get("emulator", "")))
	var emu := Config.emulator(emu_id)
	var exe := str(emu.get("exe", ""))
	if emu.is_empty() or exe == "" or not FileAccess.file_exists(exe):
		return {
				"error": "Für %s ist noch kein Emulator eingerichtet. Unter Einstellungen → Emulatoren den Pfad zu %s eintragen." % [sys.get("name", "dieses System"),
				emu.get("name", "einem Emulator")] }
	var rom := str(g.get("path", ""))
	var template := str(emu.get("args", "\"{rom}\""))
	var line := ""
	# Disc direkt vom Laufwerk (src/core/discs.gd): kein Abbild, keine Datei, nur das Laufwerk.
	var drv := str(g.get("_disc_drive", ""))
	if drv != "":
		line = DiscsS.direct_args(emu_id, template, drv)
		if line == "":
			return {
					"error": "%s kann keine Disc direkt vom Laufwerk spielen. Ein Abbild der Disc in den Spieleordner legen und es ihr zuordnen." % emu.get("name",
					"Der Emulator") }
	else:
		if not FileAccess.file_exists(rom):
			return { "error": "Die Spieldatei wurde nicht gefunden:\n%s\n\nUnter Einstellungen → Spiele „Spiele neu einlesen“ räumt Einträge ohne Datei auf." % rom }
		line = fill_args(template, rom, str(sys.get("core", "")), exe, str(g.get("title", "")))
		var extra := str(g.get("args", ""))
		if extra != "":
			line += " " + extra
	# Spielstände (quick_resume.gd): Stand beim Start laden. Vor allen anderen Parametern,
	# denn DuckStation und PCSX2 nehmen nach „--“ alles als Dateinamen.
	var resume := str(g.get("_resume_args", ""))
	if resume != "":
		line = resume + " " + line
	return { "exe": exe, "args": line, "dir": exe.get_base_dir(), "sys": sys, "emu": emu }


## Remote Play Together: Auftrag an den Starter im Spender schreiben, den Spender über Steam
## starten und auf den echten Spielprozess warten. Pause, Guide, Bildfilter und Lossless Scaling
## arbeiten danach mit diesem Prozess wie bei einem normalen Start.
func _launch_remote_play(g: Dictionary) -> bool:
	var cmd := {}
	if str(g.get("source", "rom")) == "rom":
		cmd = _rom_command(g)
	else:
		var exe := str(g.get("target", g.get("path", "")))
		if exe.get_extension().to_lower() == "lnk" and Helper.available:
			var l := await Helper.run("lnk", { "path": _win(exe) })
			if l.ok and l.result is Dictionary:
				exe = str(l.result.get("target", "")).replace("\\", "/")
				cmd = { "args": str(l.result.get("args", "")), "dir": str(l.result.get("dir", "")).replace("\\", "/") }
		if str(g.get("path", "")).get_extension().to_lower() == "lnk" and lnk_ziel_gesperrt(exe):
			cmd = { "error": "Diese Verknüpfung startet %s – das öffnet Uzai nicht als Spiel." % exe.get_file() }
		elif exe == "" or not FileAccess.file_exists(exe) or exe.get_extension().to_lower() != "exe":
			cmd = { "error": "Die Programmdatei wurde nicht gefunden:\n%s" % exe }
		else:
			var wd := str(g.get("install_dir", cmd.get("dir", "")))
			cmd = { "exe": exe, "args": (str(cmd.get("args", "")) + " " + str(g.get("args", ""))).strip_edges(), "dir": wd if wd != "" else exe.get_base_dir() }
	if cmd.has("error"):
		failed.emit(g, str(cmd.error))
		return false
	state.emit("Remote Play wird vorbereitet …")
	var adm := await RemotePlay.admin_check(str(cmd.exe))
	if adm != "":
		failed.emit(g, adm)
		return false
	var err := await RemotePlay.ensure_ready()
	if err != "":
		failed.emit(g, err)
		return false
	var d := RemotePlay.donor()
	if Config.is_windows():
		var r := await Helper.run("steam-running")
		if r.ok and int(r.result.get("appid", 0)) == int(d.appid):
			failed.emit(g, "%s läuft schon über Steam. Beende es zuerst, dann startet Uzai das Spiel darüber." % RemotePlay.donor_title())
			return false
	if cmd.has("emu"):
		_spieler_einrichten(g, cmd)
		_hintergrund_einrichten(cmd)
	if cmd.has("emu") and bool(Config.get_value("remoteplay.player2", true)):
		await _prepare_player2(g, cmd)
	_rp_id = RemotePlay.write_job({ "exe": _win(str(cmd.exe)), "args": str(cmd.args), "dir": _win(str(cmd.dir)) })
	if _rp_id == "":
		RemotePlayPads.restore_all()
		failed.emit(g, "Uzai darf im Ordner von %s nicht schreiben." % RemotePlay.donor_title())
		return false
	await _ensure_steam()
	state.emit("Steam startet %s für Remote Play …" % RemotePlay.donor_title())
	OS.shell_open("steam://rungameid/%d" % int(d.appid))
	# Nur dieser eine Weg: ein zweiter Startbefehl käme ohne Auftrag an und startete das Original.
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().create_timer(0.5).timeout
		var st := RemotePlay.read_status(_rp_id)
		if str(st.get("zustand", "")) == "fehler":
			RemotePlayPads.restore_all()
			var why := str(st.get("fehler", "unbekannter Fehler"))
			if why.begins_with("admin:"):
				failed.emit(g, RemotePlay.admin_problem(str(cmd.exe).get_file(), "manifest", false))
			else:
				failed.emit(g, "Der Starter meldet: %s" % why)
			return false
		if int(st.get("pid", "0")) > 0:
			pid = int(st.pid)
			break
		if Time.get_ticks_msec() - t0 > 120000:
			RemotePlay.clear_job()
			RemotePlayPads.restore_all()
			failed.emit(g, "Steam hat %s nicht gestartet. Läuft Steam, und ist das Spiel installiert?" % RemotePlay.donor_title())
			return false
	remote_play = true
	if cmd.has("emu"):
		_apply_filter(g, cmd.sys, cmd.emu)
	return true


## Spieler & Controller (src/core/spieler_emus.gd): Spieler 1 im Emulator ist der Controller, mit dem
## das Spiel gestartet wurde (bzw. auf Wunsch alles nach Uzais Zuordnung), solange er noch nicht läuft.
## Gilt für jeden Emulator-Start: Bibliothek, Disc vom Laufwerk, Weiterspielen, Neustart aus dem Guide
## und Remote Play. Bleibt eingerichtet (die Originaldatei liegt in Uzais Ablage). Jede Entscheidung
## steht im launch.log, z. B. „Controller: PCSX2 Spieler 1 → XInput-0 (…)“, dazu jeder Controller mit
## Godot-Gerät, GUID, XInput-Anschluss und SDL-Nummer und die benutzte Datei.
func _spieler_einrichten(g: Dictionary, cmd: Dictionary) -> void:
	var emu: Dictionary = cmd.emu
	var res := SpielerEmus.vor_start(str(emu.get("id", "")), str(cmd.exe), str(g.get("system", "")))
	var name := str(emu.get("name", "Emulator"))
	_pads_kind = SpielerEmus.kind_of(str(emu.get("id", "")), str(cmd.exe))
	_pads_beim_start = Pads.pads.map(func(p: Dictionary) -> String: return str(p.get("uz_id", "")))
	_pads_gemeldet = {}
	pads_start = res.get("p1", {})
	for l in res.get("log", []):
		log_launch("Controller: %s%s%s" % [name, " " if str(l).begins_with("Spieler") else ": ", str(l)])


## Weiterlaufen im Hintergrund (src/core/emu_hintergrund.gd): Steht man im Zimmer auf, läuft das Spiel
## im Fernseher weiter und der Controller gehört der Figur. Nach dem Spiel kommen die alten Werte zurück.
func _hintergrund_einrichten(cmd: Dictionary) -> void:
	var emu: Dictionary = cmd.emu
	var res := EmuHintergrund.vor_start(str(emu.get("id", "")), str(cmd.exe), str(emu.get("name", "Emulator")))
	hintergrund_anhalten = bool(res.get("anhalten", false))
	if str(res.get("log", "")) != "":
		log_launch("Hintergrund: " + str(res.log))


## Spieler 2 im Emulator auf den nächsten Controller legen (wird nach dem Spiel zurückgestellt).
func _prepare_player2(g: Dictionary, cmd: Dictionary) -> void:
	var xi := 1
	if Config.is_windows() and Helper.available:
		var r := await Helper.run("pad-count", {}, 3.0)
		if r.ok and r.result is Dictionary:
			xi = int(r.result.get("n", 1))
	var emu: Dictionary = cmd.emu
	var res := RemotePlayPads.prepare(str(emu.get("id", "")), str(cmd.exe), str(g.get("system", "")), xi, Input.get_connected_joypads().size())
	var name := str(emu.get("name", "Emulator"))
	if not (res.done as Array).is_empty():
		Toasts.show_toast("Spieler 2 ist bereit", "%s: Spieler 2 hört auf den nächsten Controller. Nach dem Spiel stellt Uzai alles zurück." % name, "controller",
				{ "ms": 4500, "quiet": true })
	elif str(res.note) != "":
		Toasts.show_toast("Spieler 2 bei %s" % name, str(res.note).substr(0, 1).to_upper() + str(res.note).substr(1) + ".", "controller",
				{ "ms": 6000, "quiet": true })


## Aus RemotePlay.invite: für „Spieler 2 ist verbunden“ und den Hinweis, wenn keiner kommt.
func rp_invited(who: String) -> void:
	_rp_invite_name = who
	_rp_invite_at = int(Time.get_unix_time_from_system())
	_rp_hint_shown = false
	_rp_overlay_open = true


## Liegt nach einer Einladung vermutlich noch Steams Overlay über dem Spiel? Dann steht der
## Guide gleich auf „Steam-Overlay“ (A macht es zu, ohne Tastatur). Nach 5 Minuten nicht mehr.
func rp_overlay_due() -> bool:
	return _rp_overlay_open and in_game and int(Time.get_unix_time_from_system()) - _rp_invite_at < 300


func rp_overlay_toggled() -> void:
	_rp_overlay_open = false


## Während einer Remote-Play-Sitzung: Controller zählen (Starter im Spender und Helfer).
func _watch_pads() -> void:
	var n := int(RemotePlay.read_status(_rp_id).get("pads", "-1"))
	if Config.is_windows() and Helper.available:
		var r := await Helper.run("pad-count", {}, 3.0)
		if r.ok and r.result is Dictionary:
			n = maxi(n, int(r.result.get("n", -1)))
	if n < 0 or not in_game:
		return
	if _rp_base < 0:
		_rp_base = n
		_rp_pads = n
		return
	var ch := RemotePlay.pad_change(_rp_base, _rp_pads, n)
	_rp_pads = n
	if ch == "verbunden":
		_rp_hint_shown = true
		var sub := ("%s spielt jetzt mit." % _rp_invite_name) if _rp_invite_name != "" else "Zweiter Controller verbunden."
		Toasts.show_toast("Spieler 2 ist verbunden", sub, "controller", { "sound": "select", "ms": 5000 })
	elif ch == "getrennt":
		Toasts.show_toast("Spieler 2 ist weg", "Der zweite Controller hat die Verbindung getrennt.", "controller", { "ms": 5000 })
	elif RemotePlay.pad_hint_due(_rp_invite_at, int(Time.get_unix_time_from_system()), _rp_base, n, _rp_hint_shown):
		_rp_hint_shown = true
		Toasts.show_toast("Noch kein zweiter Controller",
				"Hat %s die Einladung angenommen? Guide → „Steam-Overlay“, dort unter Remote Play beim Freund das Controller-Symbol einschalten." % (_rp_invite_name
				if _rp_invite_name != "" else "dein Freund"), "controller", { "ms": 9000 })


## Ziele einer Spiel-Verknüpfung (.lnk), die Uzai nie startet: Kommandozeilen und Skript-Hosts – eine .lnk in einem
## entpackten Spielordner kann auf „cmd.exe /c …“ zeigen. Enger als die Sperrliste für eigene Apps (apps_extern.gd):
## explorer.exe (Store- und Game-Pass-Spiele über shell:AppsFolder), java/javaw, python und Co. starten echte Spiele.
const LNK_GESPERRT := ["cmd", "powershell", "powershell_ise", "pwsh", "wscript", "cscript", "mshta", "rundll32", "regsvr32",
	"wsl", "wslhost", "bash", "wt", "windowsterminal", "conhost", "openconsole", "msiexec", "msbuild", "installutil", "regasm",
	"regsvcs", "cmstp", "certutil", "bitsadmin", "schtasks", "forfiles", "hh", "wmic", "msxsl", "scriptrunner", "reg", "regedit",
	"runas", "sc", "pcalua", "presentationhost"]


static func lnk_ziel_gesperrt(ziel: String) -> bool:
	return ziel != "" and ziel.replace("\\", "/").get_file().to_lower().trim_suffix(".exe") in LNK_GESPERRT


func _launch_exe(g: Dictionary) -> bool:
	# Internet-Verknüpfungen (GOG Galaxy, Battle.net, Xbox-App …) startet Windows selbst.
	if str(g.get("url", "")) != "":
		# Auch beim Start prüfen: library.json kann aus einer Sicherung kommen.
		if not PcScanner.url_ok(str(g.url)):
			failed.emit(g, "Diese Verknüpfung zeigt nicht auf einen Spiele-Starter – Uzai öffnet sie nicht.")
			return false
		state.emit("%s startet …" % g.title)
		OS.shell_open(str(g.url))
		_kind = "link"
		_track_dir = ""
		return true
	var exe := str(g.get("target", g.get("path", "")))
	# Auch ein beim Einlesen aufgelöstes Ziel prüfen (library.json kann aus einer Sicherung oder älteren Fassung kommen).
	if str(g.get("path", "")).get_extension().to_lower() == "lnk" and lnk_ziel_gesperrt(exe):
		failed.emit(g, "Diese Verknüpfung startet %s – das öffnet Uzai nicht als Spiel." % exe.replace("\\", "/").get_file())
		return false
	# Verknüpfung, die beim Einlesen noch nicht aufgelöst war: jetzt auflösen und das Programm
	# selbst starten – dann kennt Uzai den Prozess (Spielende, „Spiel beenden“, Pause).
	if exe.get_extension().to_lower() == "lnk" and Config.is_windows() and Helper.available:
		var lr := await Helper.run("lnk", { "path": exe.replace("/", "\\") }, 5.0)
		var tgt := str((lr.result as Dictionary).get("target", "")) if lr.ok and lr.result is Dictionary else ""
		if lnk_ziel_gesperrt(tgt):
			failed.emit(g, "Diese Verknüpfung startet %s – das öffnet Uzai nicht als Spiel." % tgt.replace("\\", "/").get_file())
			return false
		if tgt.to_lower().ends_with(".exe"):
			g["target"] = tgt.replace("\\", "/")
			g["args"] = str((lr.result as Dictionary).get("args", g.get("args", "")))
			var wd0 := str((lr.result as Dictionary).get("dir", "")).replace("\\", "/")
			g["install_dir"] = wd0 if wd0 != "" else str(g.target).get_base_dir()
			exe = str(g.target)
	if exe.get_extension().to_lower() == "lnk":
		state.emit("%s startet …" % g.title)
		OS.shell_open(exe.replace("/", "\\") if Config.is_windows() else exe)
		_kind = "link"
		_track_dir = ""
		return true
	if not FileAccess.file_exists(exe):
		failed.emit(g, "Die Programmdatei wurde nicht gefunden:\n%s" % exe)
		return false
	if not await _admin_ok(exe, str(g.title)):
		failed.emit(g, "")
		return false
	state.emit("%s startet …" % g.title)
	# Eigener Arbeitsordner (Spieloptionen) nur zum Starten; install_dir bleibt der Ordner des
	# Spiels, an dem Uzai seinen Prozess wiederfindet.
	var wd := str(g.get("work_dir", g.get("install_dir", exe.get_base_dir())))
	# Epic-Spiel von Uzai: Parameter als Liste, der Einmal-Code erst jetzt (nach der Admin-Frage),
	# damit er nicht abläuft. Er steht nur in dieser Liste und geht nur an diesen Start.
	var argv := PackedStringArray()
	if bool(g.get("epic_start", false)):
		argv = await EpicInstallS.start_argv(g, exe)
	pid = await _start_process(exe, str(g.get("args", "")), wd if wd != "" else exe.get_base_dir(), argv)
	if pid <= 0:
		failed.emit(g, "Das Spiel ließ sich nicht starten.")
		return false
	return true


## Verlangt das Programm Adminrechte (Manifest oder „Als Administrator ausführen“) und läuft Uzai
## ohne, fragt main vorher nach (siehe main._confirm_admin). Einmal je Sitzung je Programm geprüft;
## „Immer starten“ merkt es sich dauerhaft.
func _admin_ok(exe: String, name_: String) -> bool:
	if not Config.is_windows() or not Helper.available or not confirm_admin.is_valid() or exe.get_extension().to_lower() != "exe":
		return true
	if (Config.get_value("launcher.admin_ok", []) as Array).has(exe):
		return true
	if not _admin_need.has(exe):
		var r := await Helper.run("rp-check", { "exe": _win(exe) }, 8.0)
		var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
		_admin_need[exe] = (bool(res.get("manifest_admin", false)) or bool(res.get("compat_admin", false))) and not bool(res.get("self_elevated", true))
	if not bool(_admin_need[exe]):
		return true
	return await confirm_admin.call(name_, exe)


## argv: feste, geprüfte Parameter als Liste (Epic-Spiele von Uzai); der Helfer quotet jeden
## einzeln, args_line (deine eigenen Startparameter) kommt wie bisher dahinter.
func _start_process(exe: String, args_line: String, dir: String, argv := PackedStringArray()) -> int:
	if Helper.available:
		# watch: Der Helfer behält den Prozess im Blick, damit sein Rückgabewert nach dem Ende lesbar
		# bleibt (Absturz erkennen, siehe _after_end).
		var req := { "exe": _win(exe), "args": args_line, "dir": _win(dir), "watch": true }
		if not argv.is_empty():
			req["argv"] = Array(argv)
		var r := await Helper.run("start", req, 30.0)
		req.clear()
		if r.ok:
			return int(r.result.get("pid", 0))
		# Zeitüberschreitung: Der Helfer kann den Start noch ausführen (er arbeitet der Reihe nach).
		# Selbst nachzustarten ergab zwei Emulatoren auf derselben Speicherkarte – dann lieber nicht.
		if bool(r.get("timeout", false)):
			return 0
	# Ohne Helfer nie mit Einmal-Code: Godot schriebe die Befehlszeile bei einem Fehler ins Protokoll.
	var p := OS.create_process(exe, Helper.win_args(EpicInstallS.without_code(argv) + split_args(args_line)))
	_own_pids[p] = true
	return p


## Läuft der Prozess noch? Godot kennt unter Windows nur Prozesse, die es selbst gestartet hat;
## alles, was der Helfer startet (Emulatoren, ShaderGlass), fragt Uzai beim Helfer nach.
## Früher galt so jedes Emulatorspiel nach 1,5 s als beendet (Guide kam nicht über das Spiel).
var _own_pids := {}


func process_alive(p: int) -> bool:
	if p <= 0:
		return false
	if _own_pids.has(p) or not Config.is_windows():
		return OS.is_process_running(p)
	# Ohne Helfer (startet gerade neu) kennt Godot unter Windows nur selbst gestartete Prozesse –
	# ein Emulator vom Helfer galt dann nach 3 s als beendet. Lieber weiterlaufen lassen.
	if not Helper.available:
		return true
	var r := await Helper.run("alive", { "pid": p }, 3.0)
	if not r.ok or not (r.result is Dictionary):
		return true          # Helfer gerade beschäftigt: lieber weiterlaufen lassen
	# Nur ein klares „nein“ zählt: Alles andere (Feld fehlt, falscher Typ) hieße sonst „Spiel beendet“.
	var lebt: Variant = r.result.get("alive", true)
	return lebt if lebt is bool else true


func _apply_filter(g: Dictionary, sys: Dictionary, emu: Dictionary) -> void:
	var flt := Config.filter(active_filter_id(g))
	if flt.is_empty() or flt.get("type") != "shaderglass" or not Config.get_value("shaderglass.enabled", true):
		return
	var sg := str(Config.get_value("shaderglass.exe", ""))
	if sg == "" or not FileAccess.file_exists(sg):
		# Silent: a notice at game start would be disruptive. The skip is recorded in launch.log.
		log_launch("Bildfilter übersprungen: ShaderGlass ist nicht eingerichtet")
		return
	var hint := str(emu.get("window_hint", emu.get("name", "")))
	var ignore := "^%s( [vV]?[0-9][^|]*)?$" % _regex_escape(hint)
	var r := await Helper.run_once("shaderglass", { "pid": pid, "exe": _win(sg), "profile": sgp_text(flt), "ignore": ignore, "timeout": 30 })
	# Für die Fehlersuche (logs/launch.log): welcher Filter, welches Fenster, welche Werte.
	var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
	var own_sgp := str(flt.get("sgp", ""))
	var wie := "läuft" if bool(res.get("ok", false)) else "nicht gestartet (%s)" % str(res.get("reason", r.get("error", "")))
	log_launch("Bildfilter „%s“ (%s): %s, Fenster „%s“ · %s" % [str(flt.get("id", "")), own_sgp.get_file() if own_sgp != "" else "Werte von Uzai", wie,
		str(res.get("title", "")), sgp_text(flt).replace("\n", " · ").left(400)])
	if r.ok and r.result is Dictionary and r.result.get("ok", false):
		_sg_pid = int(r.result.get("sg_pid", 0))
	# Ging es nicht, steht der Grund im launch.log; im Spiel kein Hinweis (störte beim Start).


func active_filter_id(g: Dictionary) -> String:
	var own := str(g.get("filter", ""))
	if own != "":
		return "" if own == "aus" else own
	return str(Config.system(str(g.get("system", ""))).get("filter", ""))


## Eine ShaderGlass-Profildatei (.sgp) aus einem Filter-Profil. Eine eigene .sgp hat Vorrang.
func sgp_text(flt: Dictionary) -> String:
	var own := str(flt.get("sgp", ""))
	if own != "" and FileAccess.file_exists(own):
		return FileAccess.get_file_as_string(own)
	var lines := PackedStringArray([
		'ProfileVersion "1.1"',
		'PixelSize "%s"' % flt.get("pixel_size", "1"),
		'DPIScaling "0"',
		'AspectRatio "1"',
		'ShaderCategory "%s"' % flt.get("category", "crt"),
		'ShaderName "%s"' % flt.get("shader", "crt-guest-advanced-hd"),
		'FrameSkip "1"',
		'OutputScale "100"',
		'FlipH "0"',
		'FlipV "0"',
		'Vertical "0"',
		'Clone "1"',
		'CaptureCursor "0"',
		'Transparent "0"',
		'ScaleLocked "0"',
	])
	var params: Dictionary = flt.get("params", {})
	for k in params.keys():
		lines.append('Param-%s "%s"' % [k, str(float(params[k]))])
	return "\n".join(lines)


# --- Während des Spiels ------------------------------------------------------

func _poll() -> void:
	if not in_game or _polling:
		return
	_polling = true
	# Die Prüfung läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, kommt hier „noch da“ an und
	# _polling wird trotzdem gelöst. Sonst merkte Uzai bis zum Neustart nicht mehr, dass das Spiel zu Ende ist.
	var alive := not await _spiel_weg()
	if alive and remote_play:
		await _watch_pads()
	if alive and in_game:
		await _check_hung()
	_polling = false
	if _schnell > 0:
		_schnell -= 1
		if _schnell == 0:
			_timer.wait_time = POLL_S
	# ShaderGlass abgestürzt: Bildfilter für dieses Spiel aus, Spiel wieder nach vorn.
	if alive and in_game and _sg_pid > 0 and not await process_alive(_sg_pid):
		_sg_pid = 0
		_sg_hidden = false
		_sg_crashes += 1
		Toasts.show_toast("Bildfilter beendet", "ShaderGlass ist abgestürzt. Das Spiel läuft ohne Filter weiter; im Guide lässt er sich wieder einschalten.", "tv",
				{ "ms": 6000 })
		if not guide_open:
			focus_game()
	if not alive:
		_finish()


## Nachfolger eines Starters: ein anderer Prozess im Ordner des Spiels. Nur einmal je Start, nur in den ersten
## NACHFOLGER_S Sekunden und nur in einem echten Spielordner (kill_dir_ok – nie „Programme“ oder das Profil). 0 = keiner.
func _nachfolger() -> int:
	var dir := str(current.get("install_dir", ""))
	if not nachfolger_erlaubt(_nachfolger_da, dir, int(Time.get_unix_time_from_system()) - _start_time) or not Config.is_windows() \
			or not Helper.available:
		return 0
	var r := await Helper.run("find-process", { "dir": _win(dir) })
	return nachfolger_aus(Fremd.liste(r.result, "pids") if r.ok else [], pid, OS.get_process_id())


static func nachfolger_erlaubt(schon: bool, dir: String, seit_s: int) -> bool:
	return not schon and dir != "" and kill_dir_ok(dir) and seit_s >= 0 and seit_s <= NACHFOLGER_S


## Der erste Prozess aus der Liste, der weder der alte noch Uzai selbst ist.
static func nachfolger_aus(pids: Array, alt: int, uzai: int) -> int:
	for p in pids:
		var n := int(p) if (p is int or p is float) else 0
		if n > 0 and n != alt and n != uzai:
			return n
	return 0


## Ob das laufende Spiel zu Ende ist. Fragt je nach Art des Starts am Fenster, am Prozess oder bei Steam nach.
func _spiel_weg() -> bool:
	var alive := true
	match _kind:
		APP:
			# Am Fenster der App (Store-Apps gehören zu einem fremden Rahmen-Prozess), sonst am Prozess.
			if _game_hwnd != 0 and Config.is_windows() and Helper.available:
				var r := await Helper.run("window-alive", { "hwnd": _game_hwnd }, 3.0)
				if r.ok and r.result is Dictionary and not bool(r.result.get("alive", true)):
					_gone += 1
					alive = _gone < 2
				else:
					_gone = 0
			elif pid > 0 and Config.is_windows():
				alive = await process_alive(pid)
		"steam":
			if Config.is_windows():
				var r := await Helper.run("steam-running")
				var running := Fremd.zahl(Fremd.weg(r.result, "appid")) if r.ok else -1
				if running == int(current.get("appid", -2)):
					_steam_seen = true
					_gone = 0
				elif _steam_seen and running >= 0:
					_gone += 1
					alive = _gone < 2
				elif not _steam_seen and running >= 0 and Time.get_unix_time_from_system() - _start_time > 180:
					# Nur mit Antwort des Helfers: Hängt er (oder fehlt), „endet“ sonst jedes Steam-Spiel nach 3 min.
					alive = false
		"link":
			# Ohne bekannten Prozess: am Spielfenster. Ist es zu, ist das Spiel aus (früher lief es für
			# Uzai „für immer“, und der Guide kam durchsichtig über den Desktop).
			if _game_hwnd != 0 and Config.is_windows() and Helper.available:
				var r := await Helper.run("window-alive", { "hwnd": _game_hwnd }, 3.0)
				if r.ok and r.result is Dictionary and not bool(r.result.get("alive", true)):
					_gone += 1
					alive = _gone < 2
				else:
					_gone = 0
		"epic", "ea", "gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot":
			if Config.is_windows() and str(current.get("install_dir", "")) != "":
				var r := await Helper.run("find-process", { "dir": _win(str(current.install_dir)) })
				# Keine Antwort (Helfer hängt oder startet neu) heißt „läuft noch“ – wie beim Nachfolger und process_alive.
				# Früher galt sie als „nicht gefunden“: zweimal still, und Uzai holte sich über das laufende Spiel.
				if not r.ok:
					pass
				elif not Fremd.liste(r.result, "pids").is_empty():
					_steam_seen = true
					_gone = 0
				elif _steam_seen:
					_gone += 1
					alive = _gone < 2
				elif Time.get_unix_time_from_system() - _start_time > 180:
					alive = false
		_:
			if _nachfolger_da and pid <= 0 and not paused:
				# Nach einem Starter: am Ordner des Spiels. Antwortet der Helfer nicht, gilt das Spiel als noch da.
				var rf := await Helper.run("find-process", { "dir": _win(str(current.get("install_dir", ""))) })
				if rf.ok:
					if nachfolger_aus(Fremd.liste(rf.result, "pids"), 0, OS.get_process_id()) > 0:
						_gone = 0
					else:
						_gone += 1
						alive = _gone < 2
			elif pid > 0 and not paused:
				alive = await process_alive(pid)
				if not alive and remote_play:
					# Der Starter meldet, wenn das Spiel in einem neuen Prozess weiterläuft.
					var np := Fremd.zahl(RemotePlay.read_status(_rp_id).get("pid"))
					if np > 0 and np != pid:
						pid = np
						alive = true
				if not alive and not remote_play:
					# Ein Starter des Spiels (eigenes kleines Programm) hat das Spiel gestartet und sich beendet:
					# Das Spiel läuft als anderer Prozess im Spielordner weiter. Vorher hielt Uzai es für beendet –
					# das Spiel lag dann hinter Uzai, nicht bedienbar, und der Guide zeigte kein Spiel. Ab jetzt
					# gilt der Ordner (wie bei Epic und GOG): Das Spiel läuft, solange dort etwas läuft.
					var nach := await _nachfolger()
					if nach > 0:
						log_launch("Starter (Prozess %d) beendet – das Spiel läuft im Ordner weiter (Prozess %d)" % [pid, nach])
						pid = 0
						_nachfolger_da = true
						alive = true
						_follow_game_window(_launch_gen)
				if not alive:
					# Manche Emulatoren starten sich einmal neu (Updater, Starter): kurz nachsehen.
					_gone += 1
					alive = _gone < 2
				else:
					_gone = 0
	return not alive


## Das Spielfenster ist eben verschwunden (der Vorhang hat sich zugezogen): ein paar Rundgänge im
## kurzen Takt, damit Uzai ohne die üblichen drei Sekunden zurückkommt. Startet sich das Spiel nur
## neu (neues Fenster), läuft es einfach weiter.
func schnell_pruefen() -> void:
	if not in_game:
		return
	_schnell = 8
	_timer.wait_time = POLL_SCHNELL_S
	_timer.start()
	_poll()


## Spiel aus dem Guide heraus beenden. Klappt immer – es gibt keinen Zustand, in dem Uzai festhängt:
##   1. höflich: wie Alt+F4 an das Spielfenster; das Spiel darf kurz speichern (QUIT_SAUBER_S). Fragt ein
##      Emulator nach („Wirklich beenden?“), ist „Beenden“ die Antwort – dann gleich weiter. Hängt das
##      Fenster (Windows: „reagiert nicht“) oder drückst du noch einmal Beenden (im Guide „Sofort
##      beenden“), wartet Uzai nicht länger. force (oder es hing schon vorher): gleich hart.
##   2. hart, hinter dem Vorhang: der Prozessbaum, den Uzai gestartet hat (Starter → Spiel, cmd →
##      Emulator), bzw. bei Steam, Epic & Co. die Prozesse im Spielordner und der Prozess hinter dem
##      hängenden Fenster nach denselben Regeln – nie Windows, Steam, Discord, Explorer oder Uzai selbst.
##   3. Ist es danach noch da (Adminrechte, Windows lehnt ab) oder dauert alles länger als QUIT_MAX_S
##      (Wächter): quit_stuck – main öffnet den Guide mit „Sofort beenden“, „Zur Startseite“ (das Spiel
##      läuft im Hintergrund weiter, loslassen) und „Zurück zum Spiel“. quitting bleibt nie hängen.
## Früher: War der Helfer beschäftigt (etwa an ein hängendes Fenster gekoppelt), lief jeder Aufruf
## bis an seine Zeitgrenze – quitting blieb so eine Minute und länger true, und jeder weitere Druck auf
## Beenden tat nichts; ein hängendes Spiel ließ sich nur über „Sofort beenden“ beenden, wenn Uzai das
## Hängen schon bemerkt hatte, und nach „läuft noch“ ging es nicht mehr zurück.
func quit_game(force := false) -> void:
	if not in_game:
		return
	if quitting:
		# Noch einmal Beenden, während es noch beendet: nicht länger höflich warten.
		if not _quit_hart:
			_quit_hart = true
			log_launch("Beenden: noch einmal gedrückt – sofort hart")
		return
	_quit_asked = true
	quitting = true
	_quit_id += 1
	var q := _quit_id
	_quit_hart = quit_gleich_hart(force, hung, quit_haengt)
	quit_haengt = false
	_quit_waechter(q)
	var ende := await _quit_ablauf(q)
	if q != _quit_id:
		return          # der Wächter hat übernommen (oder das Spiel endete inzwischen)
	_quit_id += 1
	quitting = false
	if ende == "":
		_finish()
	elif ende != "-":
		_quit_haengt(ende)


## Der Wächter: Spätestens nach QUIT_MAX_S ist „Beenden“ fertig – auch wenn ein Helfer-Aufruf nicht
## zurückkommt. Die alte Kette hört dann auf (_quit_id).
func _quit_waechter(q: int) -> void:
	await get_tree().create_timer(quit_max_s).timeout
	if q != _quit_id or not quitting or not in_game:
		return
	log_launch("Beenden: Wächter nach %.0f s – Uzai bleibt bedienbar" % quit_max_s)
	_quit_id += 1
	quitting = false
	_quit_haengt(QUIT_ZU_LANG)


## Beenden ging nicht: Uzai bleibt bedienbar (main_guide.gd _on_quit_stuck), der nächste Versuch ist gleich hart.
func _quit_haengt(text: String) -> void:
	if not in_game:
		return
	quit_haengt = true
	quit_stuck.emit(current, text)


## Die Schritte von quit_game. "" = zu, "-" = nichts mehr zu tun (endete von selbst, Wächter), sonst
## warum es noch läuft (Satz für den Guide).
func _quit_ablauf(q: int) -> String:
	if not _quit_hart:
		await _unpause_for_quit()
	if not _quit_weiter(q, _launch_gen):
		return "-"
	await profile.before_quit()
	if not _quit_weiter(q, _launch_gen):
		return "-"
	if not Config.is_windows() or not Helper.available:
		if pid > 0 and await process_alive(pid):
			OS.kill(pid)
		return ""
	# Steam hat das Spiel nie gestartet (nicht angemeldet, Update, Fehler): sofort zurück, statt bis zu
	# drei Minuten im Spielzustand festzuhängen.
	if _kind == "steam" and not _steam_seen and not window_seen and pid <= 0:
		return ""
	var gen := _launch_gen
	var plan := quit_plan(_kind, pid, kill_dir_ok(str(current.get("install_dir", ""))))
	var win_pid := 0
	if not _quit_hart:
		if bool(plan.vorhang):
			await _quit_vorhang("beenden")
		# 1. Höflich: an das Spielfenster – gehört es nicht zum gestarteten Prozess, an dessen Hauptfenster.
		var r := await Helper.run("close-window", { "hwnd": _game_hwnd, "pid": pid }, 3.0)
		if r.ok and r.result is Dictionary:
			win_pid = int(r.result.get("pid", 0))
		if pid > 0 and win_pid != pid and _quit_weiter(q, gen):
			await Helper.run("close-window", { "hwnd": 0, "pid": pid }, 3.0)
		log_launch("Beenden: höflich (%s, Fenster von Prozess %d), bis %.0f s" % [_kind, win_pid, float(plan.sauber_s)])
		var gone := await _wait_quit(float(plan.sauber_s), bool(plan.dialog_hart), gen, q)
		if not _quit_weiter(q, gen):
			return "-"
		if gone:
			return ""
	# 2. Hart, nur was sicher dazugehört – hinter dem Vorhang (sonst sähe man kurz Windows).
	await _quit_vorhang("beenden")
	if not _quit_weiter(q, gen):
		return "-"
	var hard := await _quit_hard(plan, win_pid)
	if not _quit_weiter(q, gen):
		return "-"
	if await _wait_quit(QUIT_NACH_S, false, gen):
		return "" if _quit_weiter(q, gen) else "-"
	if not _quit_weiter(q, gen):
		return "-"
	# 3. Läuft noch.
	var denied := bool(hard.denied)
	var any := bool(hard.any)
	log_launch("Beenden: läuft noch (%s)" % ("Adminrechte" if denied else ("nichts Sicheres gefunden" if not any else "Windows hat abgelehnt")))
	return quit_grund(denied, any)


## Läuft dieses Beenden noch (nicht vom Wächter abgelöst, Spiel nicht inzwischen von selbst zu)?
func _quit_weiter(q: int, gen: int) -> bool:
	return q == _quit_id and in_game and gen == _launch_gen


## Vorhang fürs Beenden (main_fenster.gd beenden_vorhang; im Zimmer, über einer eigenen App oder bei
## offenem Guide tut main nichts).
func _quit_vorhang(art: String) -> void:
	if quit_cover.is_valid():
		await quit_cover.call(true, art)


## Im Guide heißt Beenden „Sofort beenden“ (und beendet ohne höfliche Bitte), solange Beenden schon
## läuft, das Spiel nicht antwortet oder der letzte Versuch scheiterte.
func quit_sofort() -> bool:
	return in_game and (quitting or hung or quit_haengt)


## Was beim Beenden wozu gehört (ohne Windows prüfbar: tests/logic_beenden.gd).
##   sauber_s     so lange nach der höflichen Bitte warten
##   baum         den von Uzai gestarteten Prozess samt Kindern beenden
##   ordner       Prozesse im Spielordner (Steam, Epic, EA, weitere Launcher – Uzai startete sie nicht)
##   fenster_pid  den Prozess hinter dem Fenster, dem Uzai gefolgt ist (Verknüpfung, Launcher)
##   dialog_hart  fragt das Programm nach, gleich hart (Emulatoren)
##   vorhang      während des Schließens den Vorhang zu (Emulatoren; ein PC-Spiel darf seine
##                Rückfrage zeigen)
const KILL_DIR_SAMMEL := ["program files", "program files (x86)", "programdata", "windows", "users", "appdata",
	"local", "roaming", "common", "steamapps", "steamlibrary", "epic games", "games", "gog games", "desktop", "downloads",
	"documents", "origin games", "ea games", "ubisoft game launcher", "xboxgames"]


static func quit_plan(kind: String, own_pid: int, has_dir: bool) -> Dictionary:
	var p := { "sauber_s": float(QUIT_SAUBER_S.get(kind, QUIT_SAUBER_SONST_S)), "baum": own_pid > 0, "ordner": false, "fenster_pid": false,
		"dialog_hart": kind == "rom", "vorhang": kind == "rom" }
	if own_pid <= 0:
		p.ordner = has_dir and kind != "link"
		p.fenster_pid = kind in ["link", "epic", "ea"] or Stores.is_extra(kind)
	return p


## Darf Uzai beim Beenden alles beenden, was aus diesem Ordner läuft? Nur bei einem echten
## Spielordner: mindestens zwei Ebenen unter dem Laufwerk und kein Sammelordner wie „Program Files“,
## „steamapps\common“ oder das Benutzerprofil – ein falsch erkannter Ordner beendet sonst fremde Programme.
static func kill_dir_ok(dir: String) -> bool:
	var d := dir.replace("/", "\\").strip_edges().rstrip("\\")
	var parts := Array(d.split("\\", false))
	if parts.size() < 3 or not str(parts[0]).ends_with(":"):
		return false
	var last := str(parts[-1]).to_lower()
	if last in KILL_DIR_SAMMEL:
		return false
	return not (parts.size() == 3 and str(parts[1]).to_lower() == "users")


## Hat ein Emulator nach der Bitte eine Rückfrage vorn (ein anderes, kleineres Fenster desselben
## Programms)?
static func quit_is_dialog(st: Dictionary, hwnd: int) -> bool:
	var fg := int(st.get("fg_hwnd", 0))
	return bool(st.get("fg_game", false)) and fg != 0 and fg != hwnd and not bool(st.get("fg_full", false))


## Sofort hart (ohne höfliche Bitte)? Ausdrücklich verlangt („Sofort beenden“), das Fenster hängt schon
## („reagiert nicht“ – es holt die Bitte nie ab), oder der letzte Versuch scheiterte.
static func quit_gleich_hart(force: bool, haengt: bool, schon_gescheitert: bool) -> bool:
	return force or haengt or schon_gescheitert


## Warum es nach dem harten Beenden noch läuft (Satz für den Guide).
static func quit_grund(denied: bool, any: bool) -> String:
	if denied:
		return KILL_DENIED
	return KEIN_PROZESS if not any else WINDOWS_LEHNT_AB


## Während der höflichen Bitte: nicht länger warten? hart: noch einmal gedrückt, haengt: das Fenster
## antwortet nicht (IsHungAppWindow, Windows' „reagiert nicht“).
static func quit_nicht_warten(hart: bool, haengt: bool) -> bool:
	return hart or haengt


## Ein angehaltenes Spiel (Guide offen, Emulator eingefroren) kann sich nicht selbst schließen.
func _unpause_for_quit() -> void:
	if not (paused or _pause_busy or _want_paused):
		return
	await set_paused(false)
	var t0 := Time.get_ticks_msec()
	while in_game and (paused or _pause_busy) and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().create_timer(0.05).timeout


## Wartet höchstens seconds, bis vom Spiel nichts mehr läuft. true: weg. dialog_hart: Taucht eine
## Rückfrage auf, nicht weiter warten (false). Ebenso, wenn du noch einmal Beenden drückst
## (_quit_hart) oder das Fenster hängt. Ist das Spielfenster schon weg, das Spiel aber noch nicht zu
## (speichert, fährt herunter), zieht Uzai den Vorhang „schliessen“ zu – falls die Wache es nicht
## schon tat: kein Desktop dazwischen, eine Rückfrage des Spiels bleibt zu sehen.
func _wait_quit(seconds: float, dialog_hart: bool, gen: int, q := -1) -> bool:
	var t0 := Time.get_ticks_msec()
	var gedeckt := false
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await get_tree().create_timer(QUIT_PRUEF_S).timeout
		if gen != _launch_gen or not in_game or (q >= 0 and q != _quit_id):
			return true
		if not await _quit_alive():
			return true
		if q < 0 or not quitting or gen != _launch_gen:
			continue
		var fenster_haengt := false
		if _game_hwnd != 0:
			var h := await Helper.run("window-hung", { "hwnd": _game_hwnd }, 1.5)
			if h.ok and h.result is Dictionary:
				fenster_haengt = bool((h.result as Dictionary).get("hung", false))
				if not gedeckt and q == _quit_id and not bool((h.result as Dictionary).get("alive", true)):
					gedeckt = true
					await _quit_vorhang("schliessen")
		if quit_nicht_warten(_quit_hart, fenster_haengt or hung):
			log_launch("Beenden: %s – Uzai wartet nicht länger" % ("Fenster reagiert nicht" if fenster_haengt or hung else "noch einmal gedrückt"))
			return false
		if dialog_hart and gen == _launch_gen:
			var r := await Helper.run("window-state", { "pids": [pid] if pid > 0 else [], "hwnd": _game_hwnd }, 1.5)
			if r.ok and r.result is Dictionary and quit_is_dialog(r.result, _game_hwnd):
				log_launch("Beenden: Rückfrage „%s“ – Uzai beendet ohne zu warten" % str((r.result as Dictionary).get("fg_title", "")))
				return false
	return false


## Läuft vom Spiel noch etwas? Eigener Prozess: sein Baum (auch ein Spiel, das der Starter gestartet
## hat). Sonst: das Spielfenster oder Prozesse im Spielordner – erst wenn beides weg ist, ist es zu.
func _quit_alive() -> bool:
	if pid > 0:
		var r := await Helper.run("prozessbaum", { "pid": pid }, 3.0)
		if r.ok and r.result is Dictionary and (r.result as Dictionary).get("pids") is Array:
			return not ((r.result as Dictionary).pids as Array).is_empty()
		return await process_alive(pid)
	if _game_hwnd != 0:
		var w := await Helper.run("window-alive", { "hwnd": _game_hwnd }, 2.0)
		if not (w.ok and w.result is Dictionary and not bool((w.result as Dictionary).get("alive", true))):
			return true
	var dir := str(current.get("install_dir", ""))
	if dir != "" and _kind != "link":
		var f := await Helper.run("find-process", { "dir": _win(dir) }, 3.0)
		return not f.ok or not (f.result is Dictionary) or not ((f.result as Dictionary).get("pids", []) as Array).is_empty()
	return false


## Prozesse des Spiels samt Kindern (für das Loch im Vorhang „schliessen“: nur deren Fenster bleiben zu
## sehen). Eigener Prozess: sein Baum; sonst wie game_pids.
func spiel_pids() -> Array:
	if pid > 0 and Config.is_windows() and Helper.available:
		var r := await Helper.run("prozessbaum", { "pid": pid }, 2.0)
		if r.ok and r.result is Dictionary and (r.result as Dictionary).get("pids") is Array and not ((r.result as Dictionary).pids as Array).is_empty():
			return (r.result as Dictionary).pids
	return await game_pids()


## Hart beenden nach plan. { denied: Windows hat abgelehnt (Adminrechte), any: es gab etwas Sicheres }
## Dazu der Prozess hinter dem hängenden Fenster (früher nur bei „Sofort beenden“), wenn er sicher zum
## Spiel gehört: im Spielordner (wie game_pids, nur bei einem echten Spielordner) oder – Verknüpfung –
## das Fenster, dem Uzai gefolgt ist. Der Helfer beendet nie Windows, Steam, Discord oder Uzai selbst
## und nichts mit Adminrechten.
func _quit_hard(plan: Dictionary, win_pid: int) -> Dictionary:
	var denied := false
	var any := false
	if bool(plan.baum) and pid > 0:
		var k := await Helper.run("baum-beenden", { "pid": pid }, 6.0)
		var res: Dictionary = k.result if k.ok and k.result is Dictionary else {}
		denied = bool(res.get("denied", false))
		any = int(res.get("pids", 0)) > 0
		log_launch("Beenden: Prozessbaum von %d – %d beendet, %d übrig%s" % [pid, int(res.get("n", 0)), int(res.get("rest", 0)), " (abgelehnt)" if denied else ""])
	# Ohne höfliche Bitte (sofort hart) kennt Uzai den Prozess hinter dem Spielfenster noch nicht.
	if win_pid <= 0 and bool(plan.fenster_pid) and _game_hwnd != 0:
		var w := await Helper.run("window-hung", { "hwnd": _game_hwnd }, 2.0)
		if w.ok and w.result is Dictionary:
			win_pid = int((w.result as Dictionary).get("pid", 0))
	var more: Array = []
	if bool(plan.ordner):
		more = (await game_pids()).duplicate()
	if bool(plan.fenster_pid) and win_pid > 4 and not more.has(win_pid):
		more.append(win_pid)
	var hp := await _hung_pid_sicher(more)
	if hp > 0 and hp != pid:
		more.append(hp)
	for p in more:
		any = true
		var k2 := await Helper.run("kill", { "pid": int(p) }, 4.0)
		if k2.ok and k2.result is Dictionary and bool((k2.result as Dictionary).get("denied", false)):
			denied = true
	if not more.is_empty():
		log_launch("Beenden: %d weitere Prozesse (Ordner, Fenster)%s" % [more.size(), " (abgelehnt)" if denied else ""])
	return { "denied": denied, "any": any }


## Der Prozess hinter dem hängenden Fenster, wenn er sicher zum Spiel gehört (sonst 0): Verknüpfung
## (das Fenster, dem Uzai gefolgt ist), im Baum des eigenen Prozesses oder in einem echten Spielordner.
func _hung_pid_sicher(schon: Array) -> int:
	if _hung_pid <= 4 or schon.has(_hung_pid) or _hung_pid == pid:
		return 0
	if _kind == "link":
		return _hung_pid
	if pid > 0:
		var r := await Helper.run("prozessbaum", { "pid": pid }, 3.0)
		var baum: Array = (r.result as Dictionary).get("pids", []) if r.ok and r.result is Dictionary else []
		if baum.map(func(x: Variant) -> int: return int(x)).has(_hung_pid):
			return 0          # gehört zum Baum, den baum-beenden schon beendet
	var dir := str(current.get("install_dir", ""))
	if dir == "" or not kill_dir_ok(dir):
		return 0
	var f := await Helper.run("find-process", { "dir": _win(dir) }, 3.0)
	var found: Array = (f.result as Dictionary).get("pids", []) if f.ok and f.result is Dictionary else []
	return _hung_pid if found.map(func(x: Variant) -> int: return int(x)).has(_hung_pid) else 0


## Beenden ging nicht (Adminrechte): Uzai lässt das Spiel im Hintergrund weiterlaufen und kommt zurück
## zur Startseite (Guide › „Zur Startseite“). Nur danach – nie mitten im Beenden.
func loslassen() -> void:
	if not in_game or quitting:
		return
	log_launch("Beenden: Uzai lässt das Spiel im Hintergrund weiterlaufen")
	_quit_asked = true
	_finish()


const KILL_DENIED := "Läuft mit Administratorrechten. Im Spielmenü oder Task-Manager beenden."
const WINDOWS_LEHNT_AB := "Windows hat das Beenden abgelehnt. Im Task-Manager (Strg+Umschalt+Esc) geht es."
const QUIT_ZU_LANG := "Windows hat zu lange gebraucht."


## Hängt das Spiel? Windows hält ein Fenster für hängend, das 5 s lang keine Nachrichten abholt
## („Keine Rückmeldung“). Erst wenn das Trouble.HUNG_MS lang ohne Unterbrechung so bleibt, sagt Uzai
## es. Angehalten (Guide, Ruhemodus) antwortet ein Spiel nie – dann zählt nichts.
func _check_hung() -> void:
	# Alle 3 s reicht (die Grenze liegt bei 10 s); angehalten bleibt der letzte Stand stehen.
	if paused or frozen or Time.get_ticks_msec() - _hung_at < 3000:
		return
	_hung_at = Time.get_ticks_msec()
	if _game_hwnd == 0 or not window_seen or not Config.is_windows() or not Helper.available:
		_hung_since = 0
		_set_hung(false)
		return
	var r := await Helper.run("window-hung", { "hwnd": _game_hwnd }, 3.0)
	if not in_game or paused or frozen or not r.ok or not (r.result is Dictionary):
		return
	var res: Dictionary = r.result
	var now := Time.get_ticks_msec()
	_hung_since = Trouble.hung_since(_hung_since, bool(res.get("hung", false)), now)
	if _hung_since > 0:
		_hung_pid = int(res.get("pid", 0))
	_set_hung(Trouble.is_hung(_hung_since, now))


func _set_hung(on: bool) -> void:
	if on == hung:
		return
	hung = on
	hung_changed.emit(on)
	if on:
		Toasts.show_toast("%s antwortet nicht" % Library.display_title(current), "Im Guide lässt es sich sofort beenden.", "warning", { "ms": 8000 })


func _finish() -> void:
	if not in_game:
		return
	var facts := { "quit": _quit_asked, "kind": _kind, "window": window_seen, "steam_seen": _steam_seen,
		"remote": remote_play, "pid": pid, "dir": str(current.get("install_dir", "")), "start": _start_time }
	in_game = false
	hintergrund_anhalten = false
	quitting = false
	quit_haengt = false
	_quit_hart = false
	_quit_id += 1
	hung = false
	_hung_since = 0
	_timer.stop()
	_schnell = 0
	_timer.wait_time = POLL_S
	if _sg_pid > 0:
		if Helper.available:
			Helper.run("kill", { "pid": _sg_pid })
		else:
			OS.kill(_sg_pid)
	_sg_pid = 0
	_presence(false)
	_steam_status(false, end_reason(_quit_asked, _kind, int(Time.get_unix_time_from_system()) - _start_time))
	profile.restore()
	_game_hwnd = 0
	window_seen = false
	paused = false
	_want_paused = false
	_launch_gen += 1
	if remote_play:
		RemotePlayPads.restore_all()
	remote_play = false
	EmuHintergrund.zurueck()
	var secs := int(Time.get_unix_time_from_system()) - _start_time
	var g := current
	if is_app(g):
		_app_ende(g.get("app", {}))
	Library.record_session(str(g.id), secs)
	current = {}
	pid = 0
	_pads_kind = ""
	ended.emit(g, secs)
	_after_end(g, secs, facts)


## Nach dem Spielende nachsehen, ob es ein Absturz war (Trouble.verdict). Den Rückgabewert kennt
## der Helfer nur bei Prozessen, die er selbst gestartet hat; das Anwendungsprotokoll von Windows
## hilft auch bei Steam, Epic und EA (über den Spielordner).
func _after_end(g: Dictionary, secs: int, f: Dictionary) -> void:
	if not Config.is_windows() or not Helper.available:
		return
	f["secs"] = secs
	var p := int(f.pid)
	if p > 0:
		# Auch nach „Beenden“ fragen: Der Helfer gibt dabei seinen Griff auf den Prozess frei.
		var r := await Helper.run("exit-code", { "pid": p }, 3.0)
		f["code"] = int(r.result.get("code", -1)) if r.ok and r.result is Dictionary else -1
	if bool(f.quit) or bool(f.remote) or is_app(g):
		return
	if p > 0 or str(f.dir) != "":
		var w := await Helper.run("crash-event", { "since": int(f.start), "pid": p, "dir": _win(str(f.dir)) }, 8.0)
		if w.ok and w.result is Dictionary:
			f["wer"] = w.result
	var v := Trouble.verdict(f)
	if not v.is_empty():
		crashed.emit(g, v)


## Emulator anhalten, solange der Guide offen ist (nur Emulatoren, nie Steam-Spiele).
## Gewünschter Zustand wird gemerkt und nachgezogen: Wurde der Guide geschlossen, während der
## Helfer noch „anhalten“ bearbeitete, blieb der Emulator früher für immer eingefroren.
var _want_paused := false
var _pause_busy := false


## Läufe von set_paused, die gerade unterwegs sind (siehe dort).
var _set_paused_offen := 0


func set_paused(on: bool) -> void:
	_set_paused_offen += 1
	await _set_paused_lauf(on)
	_set_paused_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und set_paused täte bis zum Neustart nichts mehr.
	if _set_paused_offen == 0 and _pause_busy:
		_pause_busy = false


func _set_paused_lauf(on: bool) -> void:
	if on and not Config.get_value("system.pause_on_guide", true):
		on = false
	# Guide während des Beendens: nicht anhalten – das Spiel soll sich ja schließen.
	if on and quitting:
		on = false
	_want_paused = on
	if _pause_busy:
		return
	_pause_busy = true
	var gen := _launch_gen
	while in_game and gen == _launch_gen and _kind == "rom" and pid > 0 and paused != _want_paused:
		var want := _want_paused
		var r := await Helper.run("suspend" if want else "resume", { "pid": pid })
		if gen != _launch_gen:
			break
		if not (r.ok and r.result is Dictionary and bool(r.result.get("ok", false))):
			break
		paused = want
	_pause_busy = false


func filter_active() -> bool:
	return _sg_pid > 0


## ShaderGlass, solange sein Bild zu sehen ist (sonst 0): Spiel im Fernseher zeigt dann dieses Bild.
func filter_pid() -> int:
	return _sg_pid if _sg_pid > 0 and not _sg_hidden else 0


## ShaderGlass liegt als oberstes Fenster über dem Spiel und würde den Guide verdecken.
## Solange der Guide offen ist, wird es versteckt (läuft aber weiter).
var _sg_hidden := false


func hide_filter(on: bool) -> void:
	if not Config.is_windows():
		return
	if on and _sg_pid > 0 and not _sg_hidden:
		var r := await Helper.run("hide-windows", { "pid": _sg_pid }, 3.0)
		_sg_hidden = r.ok
	elif not on and _sg_hidden:
		_sg_hidden = false
		await Helper.run("show-hidden", {}, 3.0)


func filter_possible() -> bool:
	if not in_game or _kind != "rom":
		return false
	var flt := Config.filter(active_filter_id(current))
	return not flt.is_empty() and flt.get("type") == "shaderglass" and str(Config.get_value("shaderglass.exe", "")) != ""


## Bildfilter während des Spiels aus- oder wieder einschalten.
func toggle_filter() -> void:
	if not in_game:
		return
	if _sg_pid > 0:
		Helper.run("kill", { "pid": _sg_pid })
		_sg_pid = 0
		return
	var sys := Config.system(str(current.get("system", "")))
	var emu := Config.emulator(str(current.get("emulator", sys.get("emulator", ""))))
	await _apply_filter(current, sys, emu)


func can_pause() -> bool:
	return in_game and _kind == "rom" and pid > 0


## Speichern, Laden, Bildschirmfoto: schickt das Tastenkürzel des Emulators.
func hotkey(action: String) -> bool:
	if not in_game or _kind != "rom":
		return false
	var emu := Config.emulator(str(current.get("emulator", Config.system(str(current.get("system", ""))).get("emulator", ""))))
	var keys := str(emu.get("keys", {}).get(action, ""))
	if keys == "":
		return false
	if paused:
		await set_paused(false)
	# Nur ans Emulatorfenster und nur, wenn es vorn ist (der Helfer prüft das).
	var r := await Helper.run("keys", { "pid": pid, "hwnd": _game_hwnd, "keys": keys })
	return r.ok and r.get("result") is Dictionary and bool((r.result as Dictionary).get("sent", false))


func has_hotkey(action: String) -> bool:
	if not in_game or _kind != "rom":
		return false
	var emu := Config.emulator(str(current.get("emulator", Config.system(str(current.get("system", ""))).get("emulator", ""))))
	return str(emu.get("keys", {}).get(action, "")) != ""


func focus_game() -> void:
	if fokus_gesperrt:
		return
	var pids := await game_pids()
	if fokus_gesperrt:
		return
	if not pids.is_empty() or _game_hwnd != 0:
		Helper.run("focus", { "hwnd": _game_hwnd, "pids": pids })


## Die Steamworks-Bibliothek, die ein Steam-Spiel mitbringt (für Einladungen ohne Overlay).
func find_steam_api(g: Dictionary) -> String:
	var dir := str(g.get("install_dir", ""))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return ""
	return _find_file(dir, ["steam_api64.dll", "steam_api.dll"], 4)


static func _find_file(dir: String, names: Array, depth: int) -> String:
	var da := DirAccess.open(dir)
	if da == null:
		return ""
	for f in da.get_files():
		if f.to_lower() in names:
			return dir.path_join(f)
	if depth > 0:
		for sub in da.get_directories():
			var r := _find_file(dir.path_join(sub), names, depth - 1)
			if r != "":
				return r
	return ""


## Prozesse des Spiels: beim Emulator bekannt, bei Steam und Epic über den Installationsordner gesucht.
func game_pids() -> Array:
	if pid > 0:
		return [pid]
	var dir := str(current.get("install_dir", ""))
	if not in_game or dir == "" or not Config.is_windows():
		return []
	var r := await Helper.run("find-process", { "dir": _win(dir) })
	return r.result.get("pids", []) if r.ok else []


func elapsed() -> int:
	return int(Time.get_unix_time_from_system()) - _start_time if in_game and _start_time > 0 else 0


## Discord-Status beim Spielen (GamePresence): Titel, Laden bzw. System, Zeit seit dem Start und
## das Cover über seine öffentliche Adresse. Erst mit dem Cover, das ohne Warten bekannt ist; muss
## Uzai danach fragen, kommt es mit einer zweiten Meldung nach. Aus (Einstellung, Spieloptionen)
## oder Spielende: sofort leeren.
func _presence(on: bool) -> void:
	var g := Library.get_game(str(current.get("id", "")))
	if g.is_empty():
		g = current
	if not on or not in_game or not _presence_wanted() or GamePresence.hidden(g) or is_app(current):
		if _presence_shown:
			_presence_shown = false
			Helper.run("presence-clear")
		return
	var gen := _launch_gen
	var image := Media.presence_image_known(g)
	_presence_send(g, image)
	if image != "":
		return
	image = await Media.presence_image(g)
	if image != "" and in_game and gen == _launch_gen and _presence_shown:
		_presence_send(g, image)


func _presence_wanted() -> bool:
	return Config.is_windows() and bool(Config.get_value("accounts.discord_presence", true)) \
		and Voice.client_id() != ""


func _presence_send(g: Dictionary, image: String) -> void:
	var sys := str(Config.system(str(g.get("system", ""))).get("name", ""))
	var a := GamePresence.activity(g, image, _start_time, sys)
	if a.is_empty():
		return
	a["client_id"] = Voice.client_id()
	if Voice.builtin():
		a["small"] = Voice.PRESENCE_SMALL
	_presence_shown = true
	Helper.run("presence", a)


## Spieloptionen → „Im Discord-Status zeigen“ geändert: läuft dieses Spiel, gleich übernehmen.
func refresh_presence(game_id: String) -> void:
	if in_game and str(current.get("id", "")) == game_id:
		_presence(true)


## Steam-Freunde sehen „Spielt Nicht-Steam-Spiel: <Titel>“ (über Uzais Steam-Anmeldung, sonst
## passiert nichts). Nicht bei Steam-Spielen (meldet Steam selbst) und nicht über den
## Remote-Play-Spender (dann zeigt Steam den Spender).
var _steam_hint_shown := false   ## Hinweis „erst bei Steam anmelden“ (einmal je Sitzung)


## Warum Uzai ein Spiel für beendet hält (rein, getestet; steht in steam.log bei „Spielt: nichts“):
## Lief das Spiel weiter, zeigt die Zeile, dass Uzai den Prozess verloren hat (Emulator startet neu).
static func end_reason(quit_asked: bool, kind: String, secs: int) -> String:
	var how := "in Uzai beendet"
	if not quit_asked:
		how = "Spielfenster zu" if kind in ["link", APP] else ("Steam meldet kein Spiel mehr" if kind == "steam" else "Spielprozess beendet")
	return "%s nach %d s" % [how, maxi(0, secs)]


func _steam_status(on: bool, why := "") -> void:
	var title := ""
	if on and str(current.get("source", "rom")) != "steam" and not is_app(current) and not remote_play and bool(Config.get_value("steam.status_nonsteam", true)):
		title = Library.display_title(current)
	if title == SteamCM.games_name:
		return
	# Ist Steam am PC angemeldet, kommt dein Status von dort (offline/unsichtbar ist dann deine
	# Wahl). Sonst meldet Uzai für die Spieldauer „online“, damit Freunde das Spiel sehen.
	if title != "" and Config.is_windows() and Helper.available:
		var r := await Helper.run("steam-state", {}, 4.0)
		# Nur eine echte Antwort zählt: Ohne sie bleibt der letzte bekannte Stand (und ohne den
		# meldet Uzai keinen Status – siehe SteamCM.needs_raise).
		if r.ok and r.result is Dictionary:
			SteamCM.pc_signed_in = bool(r.result.get("running", false)) and int(r.result.get("user", 0)) != 0
			SteamCM.pc_known = true
		if not in_game or Library.display_title(current) != title:
			return
	SteamCM.set_games_played(title, why)
	SteamChat.update_live()
	if title != "" and not _steam_hint_shown and bool(SteamChat.game_status().get("login", false)):
		_steam_hint_shown = true
		Toasts.show_toast("Steam zeigt dein Spiel nicht",
				"Für „Spielt %s“ bei Steam-Freunden einmal in Uzai bei Steam anmelden: Einstellungen → Konten → Steam." % title, "steam", { "ms": 6000, "quiet": true })


# --- Hilfen ------------------------------------------------------------------

## Platzhalter in den Startparametern eines Emulators ersetzen.
static func fill_args(template: String, rom: String, core: String, exe: String, title: String) -> String:
	# Rein textuell: Ein Titel aus Scraper-Daten mit „"“ schloss sonst die Anführungszeichen der Vorlage und hängte eigene
	# Parameter an; ein Ordner im Laufwerksstamm („D:\“) machte aus „"{rom_dir}"“ ein maskiertes Anführungszeichen.
	return template.replace("{rom}", _win(rom)).replace("{rom_dir}", _ordner_arg(_win(rom.get_base_dir()))) \
		.replace("{rom_name}", rom.get_file().get_basename().replace("\"", "")).replace("{title}", title.replace("\"", "")) \
		.replace("{core}", core.replace("\"", "")).replace("{emudir}", _ordner_arg(_win(exe.get_base_dir())))


## Ordner als Parameter: ein abschließender Rückstrich verdoppelt (sonst maskiert er das folgende „"“).
static func _ordner_arg(p: String) -> String:
	return p + "\\" if p.ends_with("\\") else p


## Windows-Pfad: „/“ → „\“ und doppelte Trenner zusammenfassen (Steam lieferte „C:\/Program Files…“,
## daraus wurde „C:\\Program Files…“ – das passte zu keinem Prozesspfad). UNC-Anfang bleibt.
static func _win(p: String) -> String:
	if OS.get_name() != "Windows":
		return p
	return win_path(p)


static func win_path(p: String) -> String:
	var s := p.replace("/", "\\")
	var unc := s.begins_with("\\\\")
	while s.contains("\\\\"):
		s = s.replace("\\\\", "\\")
	return ("\\" + s) if unc else s


static func _regex_escape(s: String) -> String:
	var out := ""
	for ch in s:
		if ch in [".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|", "\\"]:
			out += "\\"
		out += ch
	return out


## Zerlegt eine Kommandozeile in Argumente und beachtet dabei Anführungszeichen.
static func split_args(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var quoted := false
	var has := false
	for ch in line:
		if ch == "\"":
			quoted = not quoted
			has = true
		elif ch == " " and not quoted:
			if has or cur != "":
				out.append(cur)
			cur = ""
			has = false
		else:
			cur += ch
	if has or cur != "":
		out.append(cur)
	return out
