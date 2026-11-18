extends Node
## Ruhemodus und Spielstände – wie auf Xbox und PlayStation.
##
## Ruhemodus (Schnellmenü – Guide-Taste halten –, Guide → Ausschalten → Ruhemodus oder, wenn so
## eingestellt, die Guide-Taste etwa eine Sekunde halten):
## Bildschirm aus (nur für den Augenblick, keine Windows-Einstellung), das Spiel hält an, Uzai
## zeigt still „Ruhemodus“. Jede Taste am Controller weckt: Bildschirm an, Spiel läuft weiter und
## ist wieder vorn, „Willkommen zurück“.
## - Emulatoren hält Uzai an wie beim Guide (Prozess anhalten, siehe Launcher.set_paused).
## - PC-Spiele (Steam, Epic, EA, eigene) nur, wenn sie offline laufen und keinen Schutz gegen
##   Schummeln mitbringen (Easy Anti-Cheat, BattlEye, Vanguard …): Ein angehaltener Prozess kann
##   dort als Manipulation gelten, Online-Spiele verlieren die Verbindung. Diese laufen weiter,
##   nur Bild und Ton gehen aus – die Ruhe-Anzeige sagt das. Einstellung „PC-Spiele im Ruhemodus
##   anhalten“: Aus / Nur ohne Anti-Cheat (Standard).
## - Ton des Spiels geht aus (nur das Spiel, wie im Lautstärkemixer) und danach wieder an.
##
## PC schlafen legen (Ausschalten-Menü, mit Rückfrage): echter Energiesparmodus, das Spiel bleibt
## offen. Nach dem Aufwachen merkt Uzai den Zeitsprung und holt das Spiel wieder nach vorn.
##
## Spielstände für Emulatoren: siehe quick_resume.gd; hier laufen Merken beim Beenden, Sichern und
## Laden im Spiel.
##
## Dazu: Schlaf-Timer (schlaf_timer.gd, hängt hier an), „Nur hören“ (enter mit hoeren: das Bild wird
## dunkel, Musik und Ton laufen weiter, jede Taste weckt) und auf Wunsch Controller ausschalten
## (rest.pads_off: kabellose Xbox-Controller, die Xbox-Taste schaltet ein und weckt).

const Fremd := preload("res://src/core/fremd.gd")
const QuickResume := preload("res://src/core/quick_resume.gd")
const GuideHold := preload("res://src/core/guide_hold.gd")
const RestScreen := preload("res://src/ui/layers/rest_screen.gd")
const SchlafTimer := preload("res://src/core/schlaf_timer.gd")

const HOLD_MS := GuideHold.REST_MS  ## so lange die Guide-Taste halten (Einstellung „Ruhemodus“)
const SCREEN_OFF_AFTER := 1.2  ## Sekunden, bis der Bildschirm ausgeht (erst die Ruhe-Anzeige)
const TICK_S := 2.0
const WACH_DB := 6.0           ## Aufwachen: „open“ so viel leiser (ein Wiederkommen, kein Öffnen)
const SLEEP_GAP_S := 20        ## so viel mehr Zeit zwischen zwei Takten: der PC hat geschlafen
const KEEP_RESUME_S := 120     ## kürzere Sitzungen (Absturz beim Laden) lassen „Weiter, wo du warst“ vorn
const LOAD_HOLD_S := 2.5       ## so lange liegt Uzais Stand beim Laden auf dem Platz des Emulators
const ZURUECK_VERSUCHE := 5    ## so oft (alle 0,3 s) versuchen, den Platz des Emulators zurückzulegen

## Erkennungszeichen im Spielordner (Datei- und Ordnernamen, klein geschrieben) → Name.
const ANTI_CHEAT := [
	["easyanticheat", "Easy Anti-Cheat"], ["start_protected_game", "Easy Anti-Cheat"],
	["battleye", "BattlEye"], ["beclient", "BattlEye"], ["beservice", "BattlEye"],
	["vgk.sys", "Riot Vanguard"], ["vgc.exe", "Riot Vanguard"], ["riot vanguard", "Riot Vanguard"], ["riotclientservices", "Riot Vanguard"],
	["eaanticheat", "EA Anti-Cheat"], ["xigncode", "XIGNCODE3"], ["x3.xem", "XIGNCODE3"],
	["gameguard", "nProtect GameGuard"], ["pnkbstr", "PunkBuster"], ["punkbuster", "PunkBuster"],
	["mhyprot", "mhyprot"], ["anticheatexpert", "ACE"], ["ace-base", "ACE"], ["equ8", "EQU8"],
	["faceit", "FACEIT"], ["nprotect", "nProtect"], ["xhunter", "XIGNCODE3"],
]
const ONLINE_FEATURES := ["Online-PvP", "Online-Koop", "PvP", "Mehrspieler", "Multi-player"]
const SINGLE_FEATURES := ["Einzelspieler", "Single-player"]

## Offen getypt (Node statt Main): Tests betreiben den Ruhemodus mit einer Attrappe (logic_ruhemodus).
var main: Node
var active := false
var _busy := false
var _waking := false
var _screen: Control
var _st := {}                  ## was beim Einschlafen getan wurde (siehe _pause_game)
var _ac_cache := {}            ## Spiel-ID → Name des Anti-Cheat ("" = keiner)
var _wall := 0
var _sleep_asked := 0          ## Unix-Zeit, als Uzai den PC schlafen legte
var _captured_gid := ""        ## Spiel, das eben mit gemerkter Stelle beendet wurde
var _hold_since := {}          ## Godot-Controller → Zeit (ms), seit der die Guide-Taste gedrückt ist
var _hold_fired := {}
var _keep_unfocused := false
var _woke_at := -100000
var _keep_guide_open := false
var schlaf: Node               ## Schlaf-Timer (src/core/schlaf_timer.gd)


func _ready() -> void:
	schlaf = SchlafTimer.new()
	schlaf.rest = self
	add_child(schlaf)
	Helper.pad_event.connect(_on_pad)
	Helper.helper_ready.connect(_apply_watch)
	Launcher.ended.connect(_on_game_ended)
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("rest.") or k == "controller.guide_hold":
			_apply_watch()
	)
	if Helper.available:
		_apply_watch()
	# Uzai war mitten im Sichern oder Laden abgestürzt: Plätze des Emulators wie vorher.
	var back := QuickResume.recover()
	if back > 0:
		Helper.hlog("Spielstände: %d Platz/Plätze des Emulators nach einem Abbruch wiederhergestellt" % back)
	_wall = int(Time.get_unix_time_from_system())
	var t := Timer.new()
	t.wait_time = TICK_S
	t.timeout.connect(_tick)
	add_child(t)
	t.start()


## Haltezeit und Wecken an den Controller-Wächter des Helfers geben (auch nach einem Neustart).
## Die Haltezeit gilt auch fürs Schnellmenü (main wertet „guide-hold“ dann selbst aus).
func _apply_watch() -> void:
	if not Config.is_windows():
		return
	Helper.run("pad-wake", { "hold_ms": GuideHold.hold_ms(GuideHold.mode()), "on": active })


## Guide-Taste halten führt direkt in den Ruhemodus (controller.guide_hold = "rest"). Standard ist
## das Schnellmenü, in dem der Ruhemodus vorn steht.
static func hold_enabled() -> bool:
	return GuideHold.mode() == "rest" and not _pad_owned()


## Der Controller-Problemlöser misst gerade (pad_help.gd): das Halten der Guide-Taste gehört dem Test.
static func _pad_owned() -> bool:
	var top: Node = Nav.top_layer()
	return top != null and top.has_meta("uz_pad_owned")


func _on_pad(kind: String) -> void:
	# Die Taste, die eben geweckt hat, darf beim Weiterhalten nicht gleich wieder einschlafen lassen.
	if kind == "guide-hold" and hold_enabled() and not active and Time.get_ticks_msec() - _woke_at > 2500:
		enter("hold")
	elif kind == "pad-wake" and active:
		wake("pad")


## Guide gehalten bei Controllern, die nur Godot sieht (PlayStation, Nintendo); XInput meldet der
## Helfer. Beides zusammen ist harmlos: enter() läuft nur einmal.
func _process(_dt: float) -> void:
	if not hold_enabled():
		_hold_since.clear()
		return
	if active:
		return
	var now := Time.get_ticks_msec()
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, JOY_BUTTON_GUIDE):
			if not _hold_since.has(d):
				_hold_since[d] = now
				_hold_fired.erase(d)
			elif not _hold_fired.has(d) and now - int(_hold_since[d]) >= HOLD_MS:
				_hold_fired[d] = true
				enter("hold")
				return
		else:
			_hold_since.erase(d)
			_hold_fired.erase(d)


# --- Ruhemodus ------------------------------------------------------------------------------

## Läufe von enter, die gerade unterwegs sind (siehe dort).
var _enter_offen := 0


## opts: hoeren (Nur hören: ohne Spiel, Musik und Video-Ton laufen weiter, das Bild wird nur
## dunkel – kein Ausschalten des Bildschirms, keine Diashow, Controller bleiben an).
func enter(src := "", opts := {}) -> void:
	_enter_offen += 1
	await _enter_lauf(src, opts)
	_enter_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und enter täte bis zum Neustart nichts mehr.
	if _enter_offen == 0 and _busy:
		_busy = false


func _enter_lauf(src := "", opts := {}) -> void:
	if active or _busy:
		return
	_busy = true
	active = true
	var hoeren := bool(opts.get("hoeren", false)) and not Launcher.in_game
	# Ruhebildschirm offen (nach rest.saver_rest, vom Handy): er geht sofort, der Ruhemodus übernimmt.
	if main and main.get("saver") and is_instance_valid(main.saver.screen):
		main.saver.stop(true)
	_st = { "kind": "", "note": "", "pids": [], "muted": false, "audio": {}, "video": false, "music": false, "screen": false, "hoeren": hoeren }
	Helper.hlog("Ruhemodus an (%s)" % src)
	# Offener Guide: zu, ohne dass er gleich das Spiel wieder nach vorn holt (main._on_guide_closed
	# bricht ab, sobald sich _guide_gen ändert).
	if main and main.get("_guide") and is_instance_valid(main._guide):
		main._guide.close()
		main._guide_gen += 1
	var g: Dictionary = Launcher.current
	if Launcher.in_game:
		_keep_guide_open = Launcher.guide_open
		Launcher.guide_open = true          # solange nie das Spiel nach vorn holen
		Launcher.frozen = true              # angehalten antwortet es nicht – das ist kein Hängen
		if main:
			main._enter_overlay()
		await _pause_game(g)
	elif main and Config.is_windows() and not get_window().has_focus() and not Video.active:
		# Ohne Spiel (Desktop, anderes Programm vorn): Uzai holen. Läuft ein Video vorn (mpv), bleibt
		# es vorn – es hält nur an.
		main._restore_window()
	if Video.active and not Video.paused and not hoeren:
		Video.set_pause(true)
		_st.video = true
	if bool(Music.now.get("playing", false)) and not Launcher.in_game and not hoeren:
		Music.play_pause(false)
		_st.music = true
	if not active:
		_busy = false
		return
	_screen = RestScreen.new()
	_screen.rest = self
	_screen.game_title = Library.display_title(g) if Launcher.in_game else ""
	_screen.note = str(_st.note)
	if hoeren:
		_screen.titel = "Nur hören"
		_screen.symbol = "headset"
		_screen.game_title = str(Music.now.get("title", "")) if bool(Music.now.get("playing", false)) else str(Video.video.get("title", "")) if Video.active else ""
		_screen.note = "Läuft weiter."
	if main:
		main.open_layer(_screen)
	_keep_unfocused = Nav.pad_unfocused
	Nav.pad_unfocused = true                # jede Taste weckt, auch ohne Fensterfokus
	Helper.run("pad-wake", { "on": true, "hold_ms": GuideHold.hold_ms(GuideHold.mode()) })
	# Ein Klang, eine Bedeutung: Es geht etwas aus (kein Guide schließt hier).
	Sfx.play("toggle_off")
	_busy = false
	await get_tree().create_timer(SCREEN_OFF_AFTER).timeout
	if not active or _waking or hoeren:
		return
	if bool(Config.get_value("rest.pads_off", false)):
		_pads_off()
	if bool(Config.get_value("rest.screen_off", false)) and Config.is_windows():
		var r := await Helper.run("monitor", { "on": false }, 3.0)
		_st.screen = r.ok
	elif main and main.get("saver") != null:
		# Bildschirm bleibt an (kein neues Aushandeln am Fernseher): die Diashow des Ruhebildschirms
		# läuft über der Ruhe-Anzeige; jede Taste weckt wie sonst.
		main.saver.start(true, true)


## Kabellose Xbox-Controller ausschalten (Pads.power_off, nur, wo es geht); die Xbox-Taste schaltet
## einen wieder ein, und das weckt wie jede Taste.
func _pads_off() -> void:
	var n := 0
	for p in Pads.pads.duplicate():
		if bool(p.get("can_off", false)):
			var r: Dictionary = await Pads.power_off(p)
			if bool(r.get("ok", false)):
				n += 1
	if n > 0:
		Helper.hlog("Ruhemodus: %d Controller ausgeschaltet" % n)


## Spiel anhalten bzw. nur stumm schalten; merkt sich alles für wake().
func _pause_game(g: Dictionary) -> void:
	if Launcher.can_pause():
		_st.kind = "rom"
		if not Launcher.paused:
			if bool(Config.get_value("system.pause_on_guide", true)):
				await Launcher.set_paused(true)
			else:
				var r := await Helper.run("suspend", { "pid": Launcher.pid })
				if r.ok and r.result is Dictionary and bool(r.result.get("ok", false)):
					Launcher.paused = true
		_st.note = "Angehalten. Es geht genau dort weiter." if Launcher.paused else "Läuft weiter, Bild und Ton sind aus."
	else:
		_st.kind = "pc"
		var pol := pc_policy(str(Config.get_value("rest.pc_suspend", "safe")), anti_cheat_for(g), online_only(_details(g)))
		var done := false
		if bool(pol.suspend) and Config.is_windows():
			var pids: Array = await Launcher.game_pids()
			for p in pids:
				var r := await Helper.run("suspend", { "pid": int(p) })
				if r.ok and r.result is Dictionary and bool(r.result.get("ok", false)):
					(_st.pids as Array).append(int(p))
					done = true
		_st.note = str(pol.note) if (done or not bool(pol.suspend)) else "Läuft weiter, Bild und Ton sind aus (Windows ließ das Spiel nicht anhalten)."
	if bool(Config.get_value("rest.mute", true)) and Config.is_windows():
		var a := Mixer.game_args(Launcher.pid, str(g.get("install_dir", "")), Launcher.game_hwnd())
		if not a.is_empty():
			var before := await Helper.app_volume(a, 0)
			if bool(before.get("found", false)) and not bool(before.get("mute", false)):
				var m := a.duplicate()
				m["on"] = true
				m["skip"] = [OS.get_process_id()]
				var r := await Helper.run("app-mute", m, 4.0)
				_st.muted = r.ok
				_st.audio = a


## Aufwecken: Bildschirm an, Spiel weiter und nach vorn. Orientierung statt Begrüßung: keine
## Mitteilung – die Auswahl setzt sich sichtbar wieder an ihren Platz (die Ebene geht, der Cursor
## steht im Antwort-Takt da). Klang: „open“ leise, gleich zum Druck (kein Guide geht auf).
func wake(src := "") -> void:
	if not active or _waking:
		return
	# Noch beim Einschlafen (Helfer antwortet): kurz warten, dann sauber zurück.
	while _busy:
		await get_tree().process_frame
	if not active or _waking:
		return
	_waking = true
	# Das Aufwachen läuft in einer eigenen Funktion: Bricht es mit einem Fehler ab, endet der Ruhemodus hier trotzdem.
	# Sonst käme man bis zum Neustart nicht mehr aus dem Ruhemodus heraus.
	await _aufwachen(src)
	if active:
		_notausgang()
	_waking = false


## Das Aufwachen brach mit einem Fehler ab: das Nötigste ohne weitere Prüfung, damit nichts angehalten, stumm oder
## dunkel bleibt. Doppelt schadet nicht (ein schon fortgesetztes Spiel läuft einfach weiter).
func _notausgang() -> void:
	Helper.hlog("Ruhemodus: Aufwachen brach ab – das Nötigste wird nachgeholt")
	Helper.run("monitor", { "on": true }, 3.0)
	if Launcher.in_game and Fremd.text(_st.get("kind")) == "rom":
		Launcher.set_paused(false)
	for p in Fremd.liste(_st.get("pids")):
		Helper.run("resume", { "pid": Fremd.zahl(p) })
	if Fremd.ja(_st.get("muted")):
		var m := Fremd.verz(_st.get("audio")).duplicate()
		m["on"] = false
		m["skip"] = [OS.get_process_id()]
		Helper.run("app-mute", m, 4.0)
	active = false
	_st = {}
	Launcher.frozen = false
	Nav.pad_unfocused = _keep_unfocused
	if is_instance_valid(_screen):
		_screen.close()
	_screen = null
	if Launcher.in_game:
		Launcher.guide_open = _keep_guide_open
		Launcher.focus_game()


## Holt alles zurück, was enter angehalten hat (nur aus wake, siehe dort).
func _aufwachen(src: String) -> void:
	_woke_at = Time.get_ticks_msec()
	# Gedrückt gehaltene Guide-Taste zählt erst nach dem Loslassen wieder (siehe _process).
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, JOY_BUTTON_GUIDE):
			_hold_since[d] = _woke_at
			_hold_fired[d] = true
	Helper.hlog("Ruhemodus aus (%s)" % src)
	Helper.run("pad-wake", { "on": false })
	if main and main.get("saver") != null and bool(main.saver.bei_ruhe):
		main.saver.bei_ruhe = false
		main.saver.stop(true)
	if bool(_st.get("screen", false)):
		Helper.run("monitor", { "on": true }, 3.0)
	Nav.pad_unfocused = _keep_unfocused
	if is_instance_valid(_screen):
		_screen.close()
	_screen = null
	Sfx.last_player = null
	Sfx.play("open")
	if is_instance_valid(Sfx.last_player):
		Sfx.last_player.volume_db -= WACH_DB
	if str(_st.get("kind", "")) == "rom" and Launcher.in_game:
		await Launcher.set_paused(false)
	for p in Fremd.liste(_st.get("pids")):
		await Helper.run("resume", { "pid": Fremd.zahl(p) })
	if bool(_st.get("muted", false)):
		var m: Dictionary = Fremd.verz(_st.get("audio")).duplicate()
		m["on"] = false
		m["skip"] = [OS.get_process_id()]
		Helper.run("app-mute", m, 4.0)
	if bool(_st.get("video", false)) and Video.active:
		Video.set_pause(false)
	if bool(_st.get("music", false)):
		Music.play_pause(false)
	active = false
	_st = {}
	Launcher.frozen = false
	if Launcher.in_game:
		Launcher.guide_open = _keep_guide_open
		if main:
			await main._leave_overlay()
		# Bildfilter: der Guide hatte ihn versteckt, sein Zurückholen fiel mit dem Ruhemodus aus.
		await Launcher.hide_filter(false)
		Launcher.focus_game()


# --- PC schlafen legen -----------------------------------------------------------------------

func ask_pc_sleep() -> void:
	var text := "Wecken mit Netzschalter, Tastatur oder Maus. Ein Controller weckt den PC meist nur per Kabel oder Xbox-Funkadapter."
	if Launcher.in_game:
		text = "%s bleibt offen. Online-Spiele verlieren dabei meist die Verbindung.\n\n" % Library.display_title(Launcher.current) + text
	main.open_dialog("Energiesparen?", text, [
		["Energiesparen", func() -> void: sleep_pc(), ""],
		["Abbrechen", func() -> void: pass],
	], "moon")


func sleep_pc() -> void:
	Library.save()
	Config.save_settings()
	await get_tree().create_timer(0.6).timeout
	if not Config.is_windows():
		Toasts.show_toast("Nur unter Windows", "Schlafen legen steuert Uzai nur auf dem Konsolen-PC.", "moon")
		return
	_sleep_asked = int(Time.get_unix_time_from_system())
	# Wie Neu starten/Herunterfahren: erst die Ausschalt-Animation, nach dem Aufwachen blendet sie auf.
	if main and main.has_method("power_off_pc"):
		main.power_off_pc("sleep")
	else:
		Helper.run("power", { "action": "sleep" }, 3.0)


## Alle zwei Sekunden: Ist viel mehr Zeit vergangen, hat der PC geschlafen (eigener Wunsch,
## Zeitgeber von Windows, Netzschalter). Danach das laufende Spiel wieder nach vorn.
func _tick() -> void:
	var now := int(Time.get_unix_time_from_system())
	var gap := now - _wall
	_wall = now
	if slept(gap, TICK_S, SLEEP_GAP_S):
		_after_sleep(now, gap)


static func slept(gap_s: int, tick_s: float, limit_s: int) -> bool:
	return gap_s > int(tick_s) + limit_s


func _after_sleep(now: int, gap: int) -> void:
	var mine := _sleep_asked > 0 and now - _sleep_asked <= gap + 60
	_sleep_asked = 0
	Helper.hlog("PC war %d s weg (%s)" % [gap, "von Uzai schlafen gelegt" if mine else "von selbst"])
	# Windows braucht nach dem Aufwachen einen Moment (Anmeldung, Grafiktreiber).
	await get_tree().create_timer(2.0).timeout
	if active:
		wake("pc")
		return
	# Im Spiel (Uzai nicht zu sehen) sagt eine Mitteilung, dass es weiterläuft. Steht Uzai vorn,
	# zeigt die Auswahl, wo man war – keine Begrüßung.
	if Launcher.in_game and not Launcher.guide_open:
		Launcher.focus_game()
		Toasts.show_toast(Library.display_title(Launcher.current), "läuft weiter", "moon", { "ms": 3000, "quiet": true })


# --- Spielstände: Stelle merken beim Beenden, sichern und laden im Spiel ------------------

## Guide → Spiel beenden bei einem Emulator mit Spielständen: erst die Stelle merken.
func quit_with_resume() -> void:
	var g: Dictionary = Launcher.current.duplicate()
	if not Launcher.in_game or not QuickResume.supported(g):
		await Launcher.quit_game()
		return
	var rec := await capture(g)
	if rec.is_empty():
		Toasts.show_toast("Beendet, Stelle nicht gemerkt", "Der Emulator hat keinen Stand geschrieben (Speichern-Kürzel unter Einstellungen → Emulatoren prüfen).",
				"warning", { "ms": 6000 })
	else:
		_captured_gid = str(g.get("id", ""))
		Toasts.show_toast("Stelle gemerkt", "Beim nächsten Start: „%s“." % QuickResume.RESUME_TEXT, "save", { "ms": 3000, "quiet": true })
	await Launcher.quit_game()


## Guide → Sichern: ein eigener Stand mit Bild, das Spiel läuft weiter.
func save_place() -> void:
	var g: Dictionary = Launcher.current.duplicate()
	var gid := str(g.get("id", ""))
	if not Launcher.in_game or not QuickResume.supported(g):
		return
	if QuickResume.own_full(gid):
		Toasts.show_toast("Alle %d Plätze belegt" % QuickResume.OWN_MAX, "Auf der Spielseite unter „Spielstände“ einen entfernen.", "save", { "ms": 5000 })
		return
	var rec := await capture(g, "own")
	if rec.is_empty():
		Toasts.show_toast("Sichern ging nicht", "Der Emulator hat keinen Stand geschrieben (Speichern-Kürzel unter Einstellungen → Emulatoren prüfen).", "warning", { "ms": 6000 })
		return
	Toasts.show_toast("Gesichert", "Platz %d von %d" % [QuickResume.own_count(gid), QuickResume.OWN_MAX], "save", { "sound": "select", "ms": 2500 })


## Guide → Laden: einen Stand aus Uzais Ablage ins laufende Spiel holen. Der Emulator lädt über sein
## Kürzel nur seinen eigenen Platz – darum liegt Uzais Stand kurz dort, danach ist der Platz wieder
## wie vorher (auch nach einem Absturz, siehe QuickResume.recover).
func load_place(rec: Dictionary) -> void:
	var slot := str(rec.get("slot_file", ""))
	var src := str(rec.get("file", ""))
	if not Launcher.in_game or slot == "" or not FileAccess.file_exists(src) or not Launcher.has_hotkey("load"):
		Toasts.show_toast("Laden ging nicht", "Dieser Stand passt nicht mehr zum Emulator. Im Guide unter „Laden“ einen anderen wählen.", "warning")
		return
	await _wait_game_front()
	var bdir := Config.path(QuickResume.DIR).path_join("sicherung")
	DirAccess.make_dir_recursive_absolute(bdir)
	var backup := ""
	if FileAccess.file_exists(slot):
		backup = bdir.path_join("laden_" + slot.get_file())
		if DirAccess.copy_absolute(slot, backup) != OK:
			Toasts.show_toast("Laden ging nicht", "Der Platz des Emulators ließ sich nicht sichern – Uzai lässt ihn, wie er ist.", "warning")
			return
	QuickResume.journal_put([{ "slot": slot, "backup": backup, "ours": QuickResume._size(src) if backup == "" else -1 }])
	var ok := DirAccess.copy_absolute(src, slot) == OK and await Launcher.hotkey("load")
	# Der Emulator liest den Platz gleich nach dem Kürzel; erst danach zurücklegen.
	await get_tree().create_timer(LOAD_HOLD_S).timeout
	var zurueck := true
	if backup != "":
		zurueck = await _zuruecklegen(backup, slot)
		if zurueck:
			DirAccess.remove_absolute(backup)
	elif FileAccess.file_exists(slot):
		DirAccess.remove_absolute(slot)
	if zurueck:
		QuickResume.journal_clear()
	else:
		_spaeter_zurueck([{ "slot": slot, "backup": backup }])
	if ok:
		Toasts.show_toast("Geladen", QuickResume.state_line(rec, int(Time.get_unix_time_from_system())), "load", { "sound": "select", "ms": 2500 })
	else:
		Toasts.show_toast("Tastenkürzel kam nicht an", "Der Emulator hat nicht reagiert. Die Kürzel unter Einstellungen → Emulatoren prüfen.", "warning")


## Die gesicherte Datei zurück auf den Platz des Emulators. Der Emulator hält seine Datei manchmal noch einen
## Augenblick fest: darum ein paar Versuche. false: ging nicht.
func _zuruecklegen(backup: String, slot: String) -> bool:
	for i in ZURUECK_VERSUCHE:
		if DirAccess.copy_absolute(backup, slot) == OK:
			return true
		await get_tree().create_timer(0.3).timeout
	return false


## Plätze, die sich nicht zurücklegen ließen: Die Sicherung bleibt liegen und der Merkzettel stehen, der nächste
## Start von Uzai legt sie zurück (QuickResume.recover) – außer der Emulator hat inzwischen selbst dorthin
## gespeichert („stand“: Änderungszeit des Platzes jetzt). Früher wurde die Sicherung trotzdem gelöscht: Der eigene
## Spielstand des Emulators auf diesem Platz war dann weg.
func _spaeter_zurueck(plaetze: Array) -> void:
	var offen: Array = []
	for p in plaetze:
		offen.append({ "slot": str(p.slot), "backup": str(p.backup), "ours": -1, "stand": FileAccess.get_modified_time(str(p.slot)) })
	QuickResume.journal_put(offen)
	Helper.hlog("Spielstände: %d Platz/Plätze des Emulators ließen sich nicht gleich zurücklegen – beim nächsten Start von Uzai" % offen.size())


## Guide zu, Emulator läuft wieder und ist vorn (main._on_guide_closed): erst dann Kürzel und Bild.
func _wait_game_front() -> void:
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(0.5).timeout
	while main and bool(main.get("_overlay_mode")) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.4).timeout


## Speichern-Kürzel drücken, die neue Datei finden, als Stand in Uzais Ablage legen, den Platz des
## Emulators wiederherstellen. kind: "auto" (beim Beenden) oder "own" (Guide → Sichern).
## Gibt den neuen Stand zurück ({} wenn es nicht ging).
func capture(g: Dictionary, kind := "auto") -> Dictionary:
	var emu_id := QuickResume.emulator_id(g)
	var prof := QuickResume.profile(emu_id)
	var emu := Config.emulator(emu_id)
	var dirs := QuickResume.expand_dirs(prof, str(emu.get("exe", "")), QuickResume.env_dirs())
	var gid := str(g.get("id", ""))
	var store := Config.path(QuickResume.DIR)
	DirAccess.make_dir_recursive_absolute(store)
	await _wait_game_front()
	if not Launcher.in_game or dirs.is_empty():
		return {}
	var at := int(Time.get_unix_time_from_system())
	var sid := QuickResume.new_id(at)
	var base := store.path_join("%s_%s" % [safe_name(gid), sid])
	var shot := base + ".jpg"
	var shot_ok := false
	if Config.is_windows():
		var r := await Helper.run("thumb", { "file": shot.replace("/", "\\"), "w": 480 }, 8.0)
		shot_ok = r.ok and FileAccess.file_exists(shot)
	Toasts.show_toast("Stelle wird gemerkt …" if kind == "auto" else "Wird gesichert …", "", "save", { "ms": 2500, "quiet": true })
	var pattern := str(prof.get("pattern", ""))
	var before := QuickResume.scan(dirs, pattern)
	var known := ""
	var prev: Array = QuickResume.states(g)
	if not prev.is_empty():
		known = str((prev[0] as Dictionary).get("slot_file", ""))
	var bdir := store.path_join("sicherung")
	DirAccess.make_dir_recursive_absolute(bdir)
	var backups := {}
	var offen: Array = []
	var i := 0
	for p in QuickResume.backup_candidates(before, QuickResume.name_tokens(g), known):
		var b := bdir.path_join("%d_%s" % [i, str(p).get_file()])
		if DirAccess.copy_absolute(str(p), b) == OK:
			backups[str(p)] = b
			offen.append({ "slot": str(p), "backup": b, "ours": -1 })
		i += 1
	QuickResume.journal_put(offen)
	var f := ""
	if await Launcher.hotkey("save"):
		f = await _wait_written(dirs, pattern, before)
	var rec := {}
	var bleibt: Array = []        # Plätze, die sich nicht zurücklegen ließen (siehe _spaeter_zurueck)
	if f != "":
		rec = { "id": sid, "emulator": emu_id, "at": at, "slot_file": f, "title": str(g.get("title", "")) }
		if str(prof.get("mode", "file")) == "entry":
			rec["slot"] = int(QuickResume.entry_for(f).get("slot", 0))
		var target := base + "." + f.get_extension()
		if DirAccess.copy_absolute(f, target) == OK:
			rec["file"] = target
			if shot_ok:
				rec["shot"] = shot
		else:
			rec = {}
		# Platz des Emulators wie vorher: gesicherte Datei zurück, neu angelegte wieder weg.
		if backups.has(f):
			if not await _zuruecklegen(str(backups[f]), f):
				bleibt.append({ "slot": f, "backup": str(backups[f]) })
		elif not before.has(f):
			DirAccess.remove_absolute(f)
		elif not rec.is_empty():
			Helper.hlog("Spielstände: %s war schon belegt und ließ sich vorher nicht sichern" % f)
	for p in backups.keys():
		if not bleibt.any(func(o: Dictionary) -> bool: return str(o.slot) == str(p)):
			DirAccess.remove_absolute(str(backups[p]))
	if bleibt.is_empty():
		QuickResume.journal_clear()
	else:
		_spaeter_zurueck(bleibt)
	if rec.is_empty():
		if shot_ok:
			DirAccess.remove_absolute(shot)
		return {}
	return QuickResume.add(gid, rec, kind)


## Wartet, bis der Emulator eine Datei geschrieben hat und ihre Größe stehen bleibt.
func _wait_written(dirs: Array, pattern: String, before: Dictionary) -> String:
	var t0 := Time.get_ticks_msec()
	var f := ""
	var last := -2
	while Time.get_ticks_msec() - t0 < QuickResume.WAIT_MS:
		await get_tree().create_timer(0.4).timeout
		var after := QuickResume.scan(dirs, pattern)
		var c := QuickResume.changed_file(before, after)
		if c == "":
			continue
		var sz := int((after[c] as Array)[1])
		if c == f and sz == last:
			return f
		f = c
		last = sz
	return f


func _on_game_ended(g: Dictionary, secs: int) -> void:
	var gid := str(g.get("id", ""))
	QuickResume.cleanup_entries()
	if gid == _captured_gid:
		_captured_gid = ""
	elif secs >= KEEP_RESUME_S:
		# Anders beendet (im Emulator, „Nur beenden“, Absturz) und länger gespielt: Die gemerkte
		# Stelle ist älter als der Fortschritt. Sie bleibt unter „Spielstände“, steht aber nicht
		# mehr als „Weiter, wo du warst“ vorn.
		QuickResume.mark_stale(gid)
	if active and _st.get("kind", "") != "":
		_st.kind = ""
		_st.pids = []
		_st.muted = false


# --- Reine Logik (getestet in tests/logic_ruhemodus.gd) -------------------------------------

static func safe_name(s: String) -> String:
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["-", "_"] else "_"
	return out if out != "" else "spiel"


## Anti-Cheat in einer Liste von Datei- und Ordnernamen (beliebige Schreibweise) – Name oder "".
static func anti_cheat_of(names: Array) -> String:
	for n in names:
		var s := str(n).to_lower()
		for ac in ANTI_CHEAT:
			if s.contains(str(ac[0])):
				return str(ac[1])
	for n in names:
		var s := str(n).to_lower()
		if s.contains("anticheat") or s.contains("anti-cheat") or s.contains("anti_cheat"):
			return "Anti-Cheat"
	return ""


## Namen im Spielordner (bis drei Ebenen, höchstens 6000) plus der Ordnerpfad selbst (Riot Games).
static func folder_names(dir: String, depth := 3, cap := 6000) -> Array:
	var out: Array = [dir.to_lower()]
	_names_into(dir, depth, cap, out)
	return out


static func _names_into(dir: String, depth: int, cap: int, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null or out.size() >= cap:
		return
	for f in da.get_files():
		out.append(f)
	var subs := da.get_directories()
	for s in subs:
		out.append(s)
	if depth > 0:
		for s in subs:
			if out.size() >= cap:
				return
			_names_into(dir.path_join(s), depth - 1, cap, out)


func anti_cheat_for(g: Dictionary) -> String:
	var gid := str(g.get("id", ""))
	if _ac_cache.has(gid):
		return str(_ac_cache[gid])
	var dir := str(g.get("install_dir", ""))
	if dir == "" and str(g.get("path", "")) != "":
		dir = str(g.get("path", "")).get_base_dir()
	var ac := anti_cheat_of(folder_names(dir)) if dir != "" and DirAccess.dir_exists_absolute(dir) else ""
	# Riot (Vanguard) liegt nicht im Spielordner.
	if ac == "" and (dir.to_lower().contains("riot games") or str(g.get("title", "")).to_lower() in ["valorant", "league of legends"]):
		ac = "Riot Vanguard"
	_ac_cache[gid] = ac
	return ac


func _details(g: Dictionary) -> Dictionary:
	if str(g.get("source", "")) == "steam" and int(g.get("appid", 0)) > 0:
		return Store.cached(int(g.appid))
	return {}


## Nur online spielbar? (Steam-Angaben: MMO, oder Mehrspieler ohne Einzelspieler)
static func online_only(details: Dictionary) -> bool:
	for gen in Array(details.get("genres", [])):
		var s := str(gen).to_lower()
		if s.contains("massively multiplayer") or s.contains("mmo"):
			return true
	var feats := Array(details.get("features", []))
	if feats.is_empty():
		return false
	for f in SINGLE_FEATURES:
		if feats.has(f):
			return false
	for f in ONLINE_FEATURES:
		if feats.has(f):
			return true
	return false


## Darf Uzai ein PC-Spiel anhalten? mode: "off" | "safe". { suspend, note }
static func pc_policy(mode: String, anti_cheat: String, online: bool) -> Dictionary:
	if mode == "off":
		return { "suspend": false, "note": "Läuft weiter, Bild und Ton sind aus. (PC-Spiele hält Uzai laut Einstellung nicht an.)" }
	if anti_cheat != "":
		return { "suspend": false, "note": "Läuft weiter, Bild und Ton sind aus: %s erkannt – ein angehaltenes Spiel könnte als Schummeln gelten." % anti_cheat }
	if online:
		return { "suspend": false, "note": "Läuft weiter, Bild und Ton sind aus: Online-Spiel – angehalten bräche die Verbindung ab." }
	return { "suspend": true, "note": "Angehalten. Es geht genau dort weiter." }

