extends "res://src/main_guide.gd"
## Uzai: Hauptbildschirm. Baut die Oberfläche, wechselt Bereiche (LT/RT) und
## Unterbereiche (LB/RB), öffnet Ebenen und kümmert sich um Spielstart und Guide.
## Hier stehen Aufbau, Navigation, Statuszeile, Profile, Vorbauen der Bereiche, Spielende, Videos
## und Filme; darunter liegen Schichten (jede erbt von der darunter und kennt nur sie):
##   main_fenster.gd  Uzai vorn halten und über dem Spiel einblenden
##   main_ebenen.gd   Ebenen öffnen, selten gebrauchte vorladen, Spiele starten
##   main_discord.gd  In Discord übertragen, Controller-Maus, kleine Ebenen
##   main_guide.gd    Guide-Taste, Controller-Tasten, Ausschalten, Mitteilungen, Werkzeuge

const Flug := preload("res://src/ui/flug.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const TabStrip := preload("res://src/ui/components/tab_strip.gd")
const StripPan := preload("res://src/ui/components/strip_pan.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const Boot := preload("res://src/ui/boot.gd")
const ZimmerTuer := preload("res://src/ui/components/zimmer_tuer.gd")
const Logo := preload("res://src/ui/components/uzai_logo.gd")

const SECTION_SCRIPTS := {
	"games": preload("res://src/ui/sections/games.gd"),
	"videos": preload("res://src/ui/sections/videos_view.gd"),
	"movies": preload("res://src/ui/sections/movies_view.gd"),
	"streams": preload("res://src/ui/sections/streams_view.gd"),
	"achievements": preload("res://src/ui/sections/achievements_view.gd"),
	"music": preload("res://src/ui/sections/music_view.gd"),
	"shop": preload("res://src/ui/sections/shop_view.gd"),
	"settings": preload("res://src/ui/sections/settings_view.gd"),
	"room": preload("res://src/ui/sections/room_view.gd"),
	"browser": preload("res://src/ui/sections/browser_view.gd"),
	"apps": preload("res://src/ui/sections/app_ordner.gd"),
}
## Leiste oben (src/core/leiste_oben.gd): Spiele · Shop · Profil als Wörter, daneben hinter
## einem feinen Trenner die Apps als Symbole (Musik, Videos, Filme, Streams, Zimmer, eigene Apps mit
## ihrem App-Symbol) und ganz rechts das Zahnrad (App hinzufügen: Einstellungen › Spiele › Leiste oben). Jede App ist ein eigener
## Bereich wie die anderen; passt nicht alles, sammelt der Ordner „Meine Apps“ (app_ordner.gd) die
## eigenen Apps. Freunde sind eine Seitenleiste auf Select (open_friends, freunde_leiste.gd), „Für
## dich“ auf der Startseite eine auf Start (games.gd menu_taste, fuer_dich_leiste.gd).
const LeisteOben := preload("res://src/core/leiste_oben.gd")
const AppsExtern := preload("res://src/core/apps_extern.gd")
const AppGruppe := preload("res://src/ui/app_gruppe.gd")
const ExtAppView := preload("res://src/ui/sections/ext_app_view.gd")
const FreundeLeiste := preload("res://src/ui/layers/freunde_leiste.gd")
const Rest := preload("res://src/core/rest.gd")
const Pip := preload("res://src/core/pip.gd")
const Perf := preload("res://src/core/perf.gd")
const Vorladen := preload("res://src/core/vorladen.gd")
const Ladezeit := preload("res://src/core/ladezeit.gd")
const Saver := preload("res://src/core/saver.gd")
const Trouble := preload("res://src/core/trouble.gd")
const Sicher := preload("res://src/core/sicher.gd")
const SteamGuide := preload("res://src/core/steam_guide.gd")
const SteamStill := preload("res://src/core/steam_still.gd")
const SetupWizard := preload("res://src/ui/layers/setup_wizard.gd")
const Doktor := preload("res://src/core/doktor.gd")
const DoktorLage := preload("res://src/core/doktor_lage.gd")
## So lange nach dem Start schaut der Uzai-Doktor einmal nach (Bibliothek und Helfer sind dann da).
const DOKTOR_HINT_S := 25.0
## Startparameter → Rundgang oder Probe aus tests/ (endet der Schlüssel auf "=", folgt der Bildordner).
const PROBEN := {
	"--uzai-test=": "res://tests/ui_test.gd",
	"--uzai-tabs=": "res://tests/tab_tour.gd",
	"--uzai-probe2=": "res://tests/probe2.gd",
	"--uzai-gamepage=": "res://tests/gamepage_probe.gd",
	"--uzai-tour052=": "res://tests/tour052.gd",
	"--uzai-reel": "res://tests/showreel.gd",
	"--uzai-probe=": "res://tests/probe.gd",
}
const WhatsNew := preload("res://src/ui/layers/whats_new.gd")
const Handheld := preload("res://src/core/handheld.gd")
const KopfStatus := preload("res://src/ui/components/kopf_status.gd")
const KopfRuhe := preload("res://src/ui/components/kopf_ruhe.gd")
const TouchZurueck := preload("res://src/ui/components/touch_zurueck.gd")
const VideoGrid := preload("res://src/ui/layers/video_grid.gd")
const VideoOptions := preload("res://src/ui/layers/video_options.gd")
const MovieStreams := preload("res://src/ui/layers/movie_streams.gd")
const MovieCatalog := preload("res://src/ui/layers/movie_catalog.gd")
const SessionSummary := preload("res://src/core/session_summary.gd")
const ProfilePicker := preload("res://src/ui/layers/profile_picker.gd")
const KidTime := preload("res://src/core/kid_time.gd")

var vorladen: Node            ## Gezieltes Vorladen nach kurzer Ruhe der Auswahl (src/core/vorladen.gd)
var view_host: Control
var tabs_box: HBoxContainer
var chips_box: HBoxContainer
var _chips_home: MarginContainer     ## Platz der Unterbereiche unter den Reitern
var _chips_pan: Control              ## hält chips_box, wenn die Leiste breiter ist als ihr Platz
var hint_bar: HBoxContainer
var hint_hud: MarginContainer          ## hält die Tastenhinweise
var top_bar: MarginContainer           ## Kopfleiste
var scan_label: Label
var clock_label: Label
var friends_box: HBoxContainer
var friends_label: Label
var music_box: HBoxContainer
var music_label: Label
var _bg_sig := ""              ## Video-Ton im Hintergrund: Stand, der oben zuletzt gezeigt wurde
var _top_gap: Control           ## freier Platz zwischen Reitern und Statuszeile (für den Songtitel)
var _narrow_top := false        ## große Oberfläche: obere Leiste enger, ohne Akku und Level
var _top_tight := 0             ## zu wenig Platz oben: 2 ohne Akku der Controller, 3 auch ohne Songtitel
const NARROW_TOP_W := 1500.0
var pad_box: HBoxContainer
var avatar_box: Control
var kopf_status: Control        ## der Status rechts (kopf_status.gd); music_box … avatar_box zeigen hinein
var kopf_ruhe: Control          ## die Leiste ruht, wenn man unten arbeitet (kopf_ruhe.gd, unsichtbar)
var sections := {}
var order: Array = []               ## Bereiche in der Leiste oben (Wörter, App-Symbole, Einstellungen)
var app_kids: Array = []            ## alle gezeigten Apps mit Bereich (Leiste und Ordner), in ihrer Reihenfolge
var folder_kids: Array = []         ## Apps im Ordner „Meine Apps“ (nur bei zu wenig Platz)
var _word_tabs: Array = []          ## Bereiche als Wörter (vor den App-Symbolen)
var _apps_shown: Array = []         ## [{ id, label, ext? }] der gezeigten Apps
var _slots := -1                    ## so viele App-Symbole passen (−1: alle)
var _gruppe: RefCounted             ## die App-Symbole für langes A (app_gruppe.gd)
var current := ""
var _tab_items := {}
var _started := false
var _zur_tuer_laeuft := false   ## open_room führt gerade zur Zimmertür (kein zweiter Weg daneben)
const Startwache := preload("res://src/core/startwache.gd")
const Fremd := preload("res://src/core/fremd.gd")
var _start_ms := 0              ## wann die Wache nach dem Start begann (Ticks)
var _start_taste := false       ## am Controller gedrückt, während Uzai nach dem Start nicht vorn war
var _start_bedient := false     ## ein Tastendruck ist angekommen: Die Wache hat ihren Zweck erfüllt
var _player: Control
var _slide_dir := 0             ## Richtung des Bereichswechsels (LT −1, RT +1, 0 = nach Lage)
var last_round: Dictionary = {}  ## zuletzt beendete Runde { game_id, start, end, secs, before, after } für „Gerade gespielt“

## Tiefe beim Bereichswechsel: so klein ist ein Bereich, der gerade kommt oder geht.


func _ready() -> void:
	# Ein anderes Uzai läuft schon und hat den Auftrag bekommen: hier nichts aufbauen.
	if Remote.is_second:
		return
	if _grafik_umschalten():
		return
	startphase("main")
	Config.autoloads_fertig()
	# Absturzschutz: ab hier ist dies das laufende Uzai (src/core/crash_guard.gd), der Helfer
	# startet es nach einem Absturz neu.
	Config.run_started()
	Helper.arm_crash_watch()
	DisplayServer.window_set_title("Uzai")
	# Alt+F4 und Schließen in der Taskleiste: erst die Ausschalt-Animation, dann beenden (_on_close_request).
	get_tree().auto_accept_quit = false
	if "--windowed" in OS.get_cmdline_user_args():
		get_window().mode = Window.MODE_WINDOWED
		get_window().borderless = false
	# Handheld (Steam Deck, ROG Ally …): Tastensymbole und Akku gleich richtig, aus dem gemerkten
	# Bildschirm und dem Gerätenamen (der Helfer ergänzt beim ersten Erkennen, display_fit.gd).
	Handheld.vom_start(Config.get_value("display.seen", {}), OS.get_model_name())
	_schirm_start()
	_build()
	startphase("oberflaeche")
	_start_vorn()
	UzTheme.rebuilt.connect(_rebuild)
	UzTheme.layout_changed.connect(_rebuild)
	UzTheme.background_changed.connect(func() -> void:
		if is_instance_valid(background):
			background.apply_theme()
	)
	Library.changed.connect(_on_library_changed)
	Discs.changed.connect(_on_disc_changed)
	Library.scan_state.connect(_on_scan_state)
	Voice.incoming_call.connect(_on_incoming_call)
	Launcher.state.connect(_on_launch_state)
	Launcher.window_ready.connect(_on_game_window)
	Launcher.window_changed.connect(_on_game_window_changed)
	_mit_helfer()
	Launcher.ended.connect(_on_game_ended)
	Launcher.failed.connect(_on_game_failed)
	Launcher.crashed.connect(_on_game_crashed)
	Launcher.confirm_admin = _confirm_admin
	Launcher.quit_cover = beenden_vorhang
	Launcher.quit_stuck.connect(_on_quit_stuck)
	Nav.command.connect(_on_command)
	# Letzte Eingabe (für das Vorbauen der Bereiche: nur, solange niemand drückt).
	Nav.command.connect(func(_c: String) -> void: _on_input_seen())
	Nav.focus_moved.connect(func(_c: Control) -> void: _on_input_seen())
	Helper.pad_event.connect(_on_pad_event)
	rest = Rest.new()
	rest.main = self
	add_child(rest)
	perf = Perf.new()
	perf.main = self
	add_child(perf)
	vorladen = Vorladen.new()
	vorladen.main = self
	add_child(vorladen)
	# Browser-Kern vorab einrichten, wenn in der Einrichtung zugestimmt (browser.kern_vorab; sonst erst im Bereich).
	load("res://src/core/browser_kern_lauf.gd").vorab(get_tree())
	# Leichter Modus (src/core/leicht.gd): ruhendes Menü mit halber Rate, einmal vorschlagen.
	var lt := Timer.new()
	lt.wait_time = 1.0
	lt.autostart = true
	lt.timeout.connect(_light_tick)
	add_child(lt)
	saver = Saver.new()
	saver.main = self
	add_child(saver)
	kid_time = KidTime.new()
	kid_time.main = self
	add_child(kid_time)
	# Profile (Roadmap 109): Name, Bild oder Regeln des aktiven Profils geändert.
	_kid_sig = _profile_sig()
	Config.profiles_changed.connect(_on_profiles_changed)
	pip = Pip.new()
	pip.main = self
	Video.add_child(pip)
	Pads.changed.connect(_refresh_pads)
	Remote.launch_requested.connect(_on_remote_launch)
	Remote.show_requested.connect(func() -> void:
		if not Launcher.in_game:
			_restore_window()
	)
	Config.changed.connect(_einstellung_geaendert)
	Social.updated.connect(func(_w: String) -> void: _update_status())
	# Discord-Freunde kommen online/gehen: die Zahl oben gleich mitziehen (nicht erst bei Steam).
	DiscordChat.changed.connect(_update_status)
	Music.updated.connect(_update_status)
	# Video-Ton im Hintergrund steht oben wie Musik: nur neu zeichnen, wenn sich dort etwas ändert
	# (Video.changed kommt viermal pro Sekunde).
	Video.changed.connect(func() -> void:
		var sig := "%s|%s|%s" % [Video.active and Video.background, Video.video.get("id", ""), Video.paused]
		if sig != _bg_sig:
			_bg_sig = sig
			_update_status()
	)
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)
	_tick()
	_proben_starten()
	var mode := UzTheme.boot_mode()
	# Nach einem Profilwechsel: keine Startanimation, sondern die Begrüßung mit dem Profilbild.
	if Config.profile_welcome:
		mode = "aus"
		ProfilePicker.welcome(self)
	if mode != "aus" and not "--no-boot" in OS.get_cmdline_user_args() and Remote.startup_launch == "" and not "--browser" in OS.get_cmdline_user_args():
		# Die Startseite schon jetzt aufbauen, verdeckt von der Startanimation (noch vor dem ersten
		# Bild, das Fenster ist ohnehin schwarz). Früher kam der Aufbau erst beim Ausblenden der
		# Animation und ließ sie ruckeln. Ohne Fokus: Tasten während der Animation beenden nur sie.
		_quiet_goto = true
		goto(order[0] if not order.is_empty() else "settings", "", false)
		_quiet_goto = false
		startphase("startseite")
		_boot = Boot.new().setup(mode)
		add_child(_boot)
		_boot.finished.connect(_after_boot)
		# Während der Animation: Dienste starten, Daten aller Bereiche anstoßen, Bereiche vorbauen.
		# Mit mehreren Profilen erst nach „Wer spielt?“ – die Dienste melden sich mit den
		# Anmeldungen des Profils an.
		if not Config.needs_picker():
			_boot_services()
	else:
		# Im Protokoll, warum keine Startanimation kam (am PC nachlesbar).
		print("Startanimation: keine (%s)" % ("Einstellung aus" if mode == "aus" and not Config.profile_welcome
			else "Profilwechsel" if Config.profile_welcome else "Startparameter"))
		_after_boot.call_deferred()


## Zeitpunkte des Starts (ms seit dem Programmstart) fürs Leistungsprotokoll (Perf.booted): wo die Zeit bis zur
## bedienbaren Startseite bleibt – Godot und Dienste, Oberfläche, Startseite, Startanimation.
var _startphasen: Array = []


func startphase(name_: String) -> void:
	_startphasen.append([name_, Time.get_ticks_msec()])


## Rundgänge und Proben für Bildschirmfotos (tests/), je nach Startparameter. Im fertigen Uzai fehlt
## der Ordner: Dann startet nichts, statt dass der Start mitten in _ready mit einem Fehler endet.
func _proben_starten() -> void:
	for a in OS.get_cmdline_user_args():
		var pfad := ""
		if a.begins_with("--uzai-script="):
			# Beliebige Probe (tests/probe_base.gd) mit --uzai-out=<ordner> für die Bilder.
			if probe_script_ok(a.substr(14), OS.has_feature("template")):
				pfad = a.substr(14)
		else:
			for k: String in PROBEN:
				if a == k or (k.ends_with("=") and a.begins_with(k)):
					pfad = PROBEN[k]
		if pfad == "" or not ResourceLoader.exists(pfad):
			continue
		var skript := load(pfad) as GDScript
		var knoten: Variant = skript.new() if skript != null and skript.can_instantiate() else null
		if knoten is Node:
			get_tree().root.add_child.call_deferred(knoten)


## Darf --uzai-script dieses Skript laden? Im fertigen Uzai (Export-Vorlage) nur Proben aus dem
## Projekt selbst (res://tests/, die der Export ohnehin weglässt) – sonst brächte ein Argument einer
## Verknüpfung oder eines Link-Aufrufs beliebigen GDScript-Code von der Platte zum Laufen.
static func probe_script_ok(path: String, exported: bool) -> bool:
	if not path.ends_with(".gd") or path.contains(".."):
		return false
	return path.begins_with("res://tests/") or not exported


## Was den Windows-Helfer braucht: gleich, wenn er schon läuft, sonst sobald er bereit ist.
func _mit_helfer() -> void:
	SteamStill.beim_start()
	if Helper.available:
		_no_window_animations()
		SteamGuide.beim_start(get_tree(), _steam_guide_fragen)
	else:
		Helper.helper_ready.connect(_no_window_animations, CONNECT_ONE_SHOT)
		Helper.helper_ready.connect(func() -> void: SteamGuide.beim_start(get_tree(), _steam_guide_fragen), CONNECT_ONE_SHOT)


## Bevor Uzai Steams Guide-Taste abschaltet: einmal sagen, was passiert (steam_guide.gd beim_start). Wartet, bis
## die Startseite ruhig da ist – kein Spiel, keine Ebene darüber, keine Einrichtung (die hat dafür eine eigene
## Zeile). "ja", "nein" oder "" (weggedrückt oder nach 15 Minuten keine Gelegenheit: beim nächsten Start wieder).
func _steam_guide_fragen(steam_laeuft: bool) -> String:
	var bis := Time.get_ticks_msec() + 15 * 60000
	while not (_started and Nav.top_layer() == null and not Launcher.in_game and not _launching):
		if Time.get_ticks_msec() > bis or not is_inside_tree():
			return ""
		await get_tree().create_timer(0.5).timeout
	var wahl := { "w": "" }
	var d := open_dialog(SteamGuide.FRAGE_TITEL, SteamGuide.frage_text(steam_laeuft), [
		["Verstanden", func() -> void: wahl.w = "ja"],
		["Steam behalten", func() -> void: wahl.w = "nein"],
	], "controller")
	if is_instance_valid(d) and d.is_inside_tree():
		await d.tree_exited
	return str(wahl.w)


## Eine Einstellung hat sich geändert (Config.changed): was das Hauptfenster sofort nachzieht.
func _einstellung_geaendert(k: String) -> void:
	if k == "controller.guide_combo":
		Helper.watch_pads()
	if k == SteamStill.KEY:
		SteamStill.anwenden()
	# Filme an/aus, Apps aus- oder eingeblendet, hinzugefügt oder entfernt: die Leiste neu einteilen.
	if k == "movies.enabled" or k == "apps.hidden" or k == "apps.extern":
		_rebuild()
	if k == "display.menu_fps" and not OS.low_processor_usage_mode:
		set_idle(false)
	# Bildschirm gewählt: Uzai zieht um. Größe der Oberfläche geändert: gilt für diesen Bildschirm.
	if k == "display.screen":
		_schirm_gewaehlt()
	if k == "theme.ui_scale" and _started:
		_schirm_merken()
	# Leichter Modus an/aus: Ecken, Schatten und Cover hängen am Theme – alles neu, Bildrate neu,
	# und das Menü misst ab jetzt neu (vorher/nachher in Einstellungen → System → Leistung).
	if k == "display.light":
		Leicht.idle = false
		UzTheme.apply()
		perf.reset_frames()
		if not OS.low_processor_usage_mode:
			set_idle(false)


## Into the room - always through the door, so every entry shows the hand pushing the door open and starts at
## the front of the room. From anywhere (home page tile, icon at the top, Guide, profile, at power-on), Uzai
## switches to the „Zimmer“ section and lets its door open (zimmer_tuer.gd); the door then opens the room.
## Going in directly happens only from the door itself, next to a running game (the camera then comes out of
## the TV) and when returning from a game that was started in the room.
func open_room(direkt := false) -> void:
	if direkt or ZimmerTuer.unterwegs or _zur_tuer_laeuft or Launcher.in_game or _launching or _overlay_mode or room_layer() != null \
			or not sections.has("room"):
		super(direkt)
		return
	_zur_tuer_laeuft = true
	await alle_ebenen_zu()
	var gewechselt := current != "room"
	if gewechselt:
		goto("room")
	var tuer: ZimmerTuer = null
	for i in 120:
		await get_tree().process_frame
		tuer = get_tree().get_first_node_in_group(ZimmerTuer.GRUPPE) as ZimmerTuer
		if tuer != null and tuer.is_visible_in_tree() and tuer.size.x > 10.0:
			break
		tuer = null
	# Erst wenn der Bereich angekommen ist (Wechsel in T_RAUM), geht die Tür auf.
	if tuer != null and gewechselt:
		await get_tree().create_timer(U.T_RAUM + 0.06).timeout
	_zur_tuer_laeuft = false
	if not is_instance_valid(tuer) or not tuer.is_visible_in_tree() or Launcher.in_game or room_layer() != null:
		# Der Bereich hat keine Tür gezeigt (ausgeblendet, Sicherer Modus): hinein wie bisher.
		super(false)
		return
	Nav.focus(tuer, true)
	await get_tree().process_frame
	tuer.activate()


## Läuft die Startanimation noch? Dahinter darf Teures unsichtbar entstehen (zimmer_bild.gd).
func startet() -> bool:
	return is_instance_valid(_boot)


## Nach dem Start gehört Uzai nach vorn. Meldungen vom PC (0.16.55, wieder 0.16.62): „Wenn man Uzai startet,
## kann man sich nicht bewegen, man muss kurz Guide drücken.“ Nav nimmt den Controller nur an, wenn Uzais Fenster
## vorn ist. Die Wache passt darum bis zum ersten angenommenen Tastendruck auf (höchstens Startwache.DAUER_MS):
## Sie holt Uzai nach vorn, sobald der Helfer das kann, auch wenn sich später etwas davorsetzt – außer der Nutzer
## bedient gerade mit Maus oder Tastatur etwas anderes. Die Entscheidung steht in src/core/startwache.gd; was sie
## sieht und tut, in logs/start.log. Endet auch, sobald ein Spiel startet oder Uzai mit Absicht hinten liegt
## (Video im Ausweichmodus, Discord vorn, Anmeldung im Browser).
func _start_vorn() -> void:
	if not Config.is_windows() or Library.demo or Remote.startup_launch != "":
		return
	var w := get_window()
	_start_ms = Time.get_ticks_msec()
	var hatte := false
	var geholt := 0
	var geholt_ms := -100000
	var zuletzt := ""
	await get_tree().create_timer(0.8).timeout
	while is_inside_tree() and not _closing:
		var alter := Time.get_ticks_msec() - _start_ms
		if Launcher.in_game or Launcher.is_starting() or _overlay_mode or _video_overlay or _away_for_discord or not _away_for_live.is_empty() \
				or Nav.pad_unfocused or Nav.passthrough or Music.connecting:
			break
		if w.has_focus() and w.mode != Window.MODE_MINIMIZED:
			if zuletzt != "vorn" and (zuletzt != "" or geholt > 0):
				_start_log("Uzai ist vorn (%.1f s nach dem Start, %d Mal geholt)" % [alter / 1000.0, geholt])
			hatte = true
			zuletzt = "vorn"
			_start_taste = false
			if _start_bedient or alter > Startwache.DAUER_MS:
				break
		else:
			if alter > Startwache.DAUER_MS and zuletzt != "gilt":
				break
			var st := {}
			if Helper.available:
				var r := await Helper.run("window-state", { "pids": [], "hwnd": 0 }, 0.8)
				if r.ok and r.result is Dictionary:
					st = r.result
				if not is_inside_tree() or _closing:
					break
			# Der Helfer holt mit einem kurzen Alt nach vorn: Das zählt bei Windows als Eingabe – kurz danach sagt die
			# Zeit seit der letzten Eingabe darum nichts über den Nutzer.
			var idle := Fremd.zahl(st.get("idle_ms"), -1) if Time.get_ticks_msec() - geholt_ms > 2500 else -1
			var was := Startwache.schritt({ "alter_ms": alter, "hatte": hatte, "geholt": geholt, "helfer": not st.is_empty(), "idle_ms": idle,
					"fg_eigen": _hwnd() != 0 and Fremd.zahl(st.get("fg_hwnd")) == _hwnd(), "taste": _start_taste })
			var vorn := Startwache.vorn_text(st, _hwnd(), OS.get_process_id())
			var maus := Startwache.idle_text(st)
			match was:
				"gilt":
					Nav.vorn_gilt_bis = Time.get_ticks_msec() + Startwache.GILT_MS
					if zuletzt != "gilt":
						_start_log("Windows führt Uzai als vorn, Godot meldet keinen Fokus – der Controller zählt trotzdem")
						set_idle(false)
				"holen":
					if st.is_empty():
						# Ohne Helfer lässt Windows ein Fenster im Hintergrund meist nicht vor: versuchen, aber nicht zählen.
						DisplayServer.window_move_to_foreground()
						if zuletzt != "holen":
							_start_log("Nach dem Start nicht vorn, Helfer noch nicht bereit – versuche es ohne ihn")
					else:
						geholt += 1
						geholt_ms = Time.get_ticks_msec()
						_start_log("Nicht vorn (%.1f s nach dem Start, Versuch %d), vorn: %s, Maus/Tastatur zuletzt vor %s – Uzai holt sich nach vorn"
								% [alter / 1000.0, geholt, vorn, maus])
						_restore_window()
				"ende":
					if geholt >= Startwache.HOLEN_MAX:
						_start_log("Nicht vorn, vorn: %s – Wache endet (oft genug versucht)" % vorn)
					else:
						_start_log("Nicht vorn, vorn: %s, Maus/Tastatur zuletzt vor %s – Wache endet (der Nutzer bedient etwas anderes)" % [vorn, maus])
					break
				_:
					if zuletzt != was:
						_start_log("Nicht mehr vorn, vorn: %s, Maus/Tastatur zuletzt vor %s – warte" % [vorn, maus])
			if was == "ende":
				break
			zuletzt = was
		await get_tree().create_timer(Startwache.TAKT_S).timeout


## In der ersten Minute nach dem Start, solange noch kein Tastendruck angekommen ist: Wer am Controller drückt,
## während Uzai nicht vorn ist, will Uzai bedienen – dann holt Uzai sich sofort nach vorn, statt nur darauf
## hinzuweisen, dass die Guide-Taste das täte. true: erledigt.
func _start_taste_holt() -> bool:
	if _start_ms <= 0 or _start_bedient or Time.get_ticks_msec() - _start_ms > Startwache.DAUER_MS or Launcher.in_game or Launcher.is_starting():
		return false
	_start_taste = true
	_start_log("Taste am Controller gedrückt, Uzai nicht vorn – Uzai holt sich nach vorn")
	_restore_window()
	return true


func _after_boot() -> void:
	_boot = null
	_boot_end_ms = Time.get_ticks_msec()
	if _started:
		return
	_started = true
	startphase("animation")
	perf.booted(_startphasen)
	if current == "" or not sections.has(current):
		goto(order[0] if not order.is_empty() else "settings")
	elif Nav.top_layer() == null:
		sections[current].focus_default()
	# Mehrere Profile: „Wer spielt?“ vor allem anderen. Ein anderes als das geladene startet Uzai
	# mit diesem Profil neu (switch_profile); dann geht es hier nicht weiter.
	if Config.needs_picker():
		var picked: String = await _ask_profile()
		if picked != Config.profile_id:
			return
	_start_services()
	set_idle(false)
	if not bool(Config.get_value("display.fitted", false)) and not Library.demo:
		_fit_display(bool(Config.get_value("system.first_run", true)))
	else:
		_schirm_merken()
	if not Handheld.aktiv.is_empty():
		_leistung_laden()
	# Hinweise vom Laden (Einstellungen repariert, Sicherung zurückgeholt …).
	for n in Config.notices:
		Toasts.show_toast("Uzai", str(n), "info", { "ms": 7000 })
	Config.notices.clear()
	if Remote.hung_pid > 0:
		await _ask_hung()
	if not Config.last_crash.is_empty() or Config.safe_mode:
		await _after_crash()
	if Remote.startup_launch != "":
		# Über eine Verknüpfung gestartet: direkt ins Spiel.
		_on_remote_launch(Remote.startup_launch)
		return
	# Als „Uzai Browser“ gestartet (Verknüpfung mit --browser): gleich in den Browser, Schließen beendet Uzai.
	if "--browser" in OS.get_cmdline_user_args() and BrowserDaten.verfuegbar():
		open_browser("", 0, true)
		return
	# Erster Start: Einrichtung wie bei einer Konsole (src/ui/layers/setup_wizard.gd). Kommt bei neuen
	# Nutzern von selbst; angefangen geht sie nach einem Neustart an derselben Stelle weiter. Wer Uzai schon
	# benutzt, sie aber nie abgeschlossen hat, bekommt sie angeboten (mit „Abbrechen“, wie aus den
	# Einstellungen) – fertig oder abgebrochen kommt sie nicht wieder (src/core/einrichtung.gd start_mode).
	var setup := SetupWizard.start_mode()
	SetupWizard.start_protokoll()
	# Nach einem Update einmal „Was ist neu“ – nie beim allerersten Start (dann ist alles neu).
	var fresh := setup != "" or bool(Config.get_value("system.first_run", true))
	if setup != "":
		await get_tree().create_timer(0.25).timeout
		SetupWizard.open_for(self, setup == "anbieten")
	elif bool(Config.get_value("system.first_run", true)) and not Library.demo:
		Config.set_value("system.first_run", false)
	elif str(Config.get_value("system.on_start", "home")) == "letztes" and not Library.demo and not Helper.AFTER_CRASH in OS.get_cmdline_user_args():
		var g := Library.get_game(str(Config.get_value("system.last_game", "")))
		if not g.is_empty():
			launch(g)
	elif str(Config.get_value("room.start", "klassisch")) == "zimmer" and not Config.safe_mode:
		open_room()
	# Über einer angebotenen Einrichtung keine Karte: „Was ist neu“ kommt dann beim nächsten Start.
	if setup != "anbieten":
		WhatsNew.offer(self, fresh)
	if setup == "" and not Library.demo:
		_doktor_hint.call_deferred()


# --- Aufbau ------------------------------------------------------------------

func _build() -> void:
	# Nur die Oberfläche neu: Dienste ohne Bild (Ruhemodus, Leistung, Takt) bleiben. Früher fiel
	# hier auch der Ruhemodus weg – nach einem Theme-Wechsel ging Guide halten nicht mehr.
	for ch in get_children():
		if ch != _boot and ch is Control:
			remove_child(ch)
			ch.queue_free()
	background = Background.new()
	U.full_rect(background)
	add_child(background)
	move_child(background, 0)

	shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 0)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(shell)
	add_child(shell)

	_build_kopf()
	_build_unterleiste()

	view_host = Control.new()
	view_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(view_host)
	# Erst steht das Layout, dann bewegt es sich: Ändert sich die Kopfzeile (Unterbereiche, Kopf der
	# Apps), behält der verlassene Bereich seine Lage auf dem Schirm (_halte_lage).
	view_host.item_rect_changed.connect(func() -> void:
		for sec in view_host.get_children():
			if sec is Control and (sec as Control).has_meta("uz_lage"):
				_halte_lage(sec as Control)
	)
	# Die Leiste ruht, wenn man unten arbeitet: im Inhalt tritt sie eine Spur zurück, in gerollten
	# Listen weiter; LT und RT stehen nur, solange der Cursor oben ist (kopf_ruhe.gd).
	kopf_ruhe = KopfRuhe.new().setup(top_bar, tabs_box, kopf_status, chips_box, view_host)
	add_child(kopf_ruhe)

	var bottom := U.margin(96, 0, 96, 30)
	shell.add_child(bottom)
	var brow := U.hbox(20)
	bottom.add_child(brow)
	scan_label = U.label("", "s", "faint", "medium")
	scan_label.clip_text = false
	brow.add_child(scan_label)
	brow.add_child(U.spacer(0, 44))

	layer_host = Control.new()
	layer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(layer_host)
	add_child(layer_host)

	_build_auslauf()

	# Tastenhinweise liegen über allen Ebenen, damit sie auch im Guide und über dem Spiel sichtbar sind.
	var hud := U.margin(96, 0, 96, 30)
	hud.anchor_top = 1.0
	hud.anchor_bottom = 1.0
	hud.anchor_right = 1.0
	hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(hud)
	hint_bar = HintBar.new()
	hud.add_child(hint_bar)
	hint_hud = hud
	# Zurück für Touch: über allen Ebenen, links in der Kopfleiste (nur mit dem Finger sichtbar).
	add_child(TouchZurueck.new())
	if _boot:
		move_child(_boot, get_child_count() - 1)

	Nav.root_scope = shell
	_build_bereiche()
	_slots = -1
	_build_tabs()
	_update_status()
	# Auch nach einem Neuaufbau (Theme, Profil): ein schwacher Controller steht gleich wieder oben.
	_refresh_pads()


## Kopfzeile: Marke, Reiter, rechts der Status (Uhr, Lupe, Profilbild).
func _build_kopf() -> void:
	# Große Oberfläche (schmaler als etwa 1500 logische Pixel, ab ~130 %): oben rücken die Teile
	# enger zusammen, und was der Guide ohnehin zeigt (Akku der Controller, Level), tritt zurück.
	_narrow_top = U.view_size().x < NARROW_TOP_W
	var top := U.margin(96, 34, 96, 0)
	shell.add_child(top)
	top_bar = top
	var top_row := U.hbox(14 if _narrow_top else 20)
	top.add_child(top_row)
	top_row.add_child(_brand())
	top_row.add_child(U.spacer(6 if _narrow_top else 26, 0, false))
	# Reiter in einer Leiste mit gleitenden Anzeigern: der Punkt im Akzent unter dem Bereich, die
	# Cursor-Pille unter dem Cursor (tab_strip.gd); LT und RT an den Enden nur, solange der Cursor
	# oben steht (kopf_ruhe.gd).
	var strip := TabStrip.new()
	strip.style = "tab"
	tabs_box = strip
	tabs_box.set_meta("uz_group", "tabs")
	tabs_box.set_meta("uz_enter", "sel")
	top_row.add_child(tabs_box)
	_top_gap = U.spacer()
	top_row.add_child(_top_gap)
	# Status rechts: nur, was gerade zählt (kopf_status.gd) – Uhr, Lupe, Profilbild mit dem Punkt
	# für Neues; Musik, Freunde und ein schwacher Akku nur, solange es sie gibt.
	kopf_status = KopfStatus.new().setup(_narrow_top, _top_gap)
	top_row.add_child(kopf_status)
	music_box = kopf_status.music_box
	music_label = kopf_status.music_label
	friends_box = kopf_status.friends_box
	friends_label = kopf_status.friends_label
	pad_box = kopf_status.pad_box
	clock_label = kopf_status.clock_label
	kopf_status.search.activated.connect(func() -> void: open_search())
	avatar_box = kopf_status.avatar     # wählbar nur ohne Reiter „Profil“ (unten gesetzt)
	avatar_box.activated.connect(func() -> void:
		if current != "achievements":
			goto("achievements")
	)


## Leiste der Unterbereiche unter dem Kopf.
func _build_unterleiste() -> void:
	# Unterbereiche: gleiche Kante wie die Quellen über dem Regal der Startseite (GUTTER − 16).
	var subm := U.margin(UzTheme.GUTTER - 16, 12, UzTheme.GUTTER, 0)
	shell.add_child(subm)
	_chips_home = subm
	var cstrip := TabStrip.new()
	cstrip.style = "chip"
	chips_box = cstrip
	chips_box.add_theme_constant_override("separation", 6)
	chips_box.set_meta("uz_group", "chips")
	chips_box.set_meta("uz_enter", "sel")
	# Viele Unterbereiche und große Oberfläche: die Leiste gleitet mit der Auswahl (strip_pan.gd).
	_chips_pan = StripPan.new().hold(chips_box)
	subm.add_child(_chips_pan)


## Der weiche Auslauf am unteren Rand, unter den Tastenhinweisen.
func _build_auslauf() -> void:
	# Unten läuft alles weich in den Raum aus, damit die Hinweise nie auf Inhalt stehen.
	var fg := Gradient.new()
	fg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	fg.colors = PackedColorArray([Color(UzTheme.col("bg"), 0.0), Color(UzTheme.col("bg"), 0.7), Color(UzTheme.col("bg"), 0.92)])
	var fgt := GradientTexture2D.new()
	fgt.gradient = fg
	fgt.fill_from = Vector2(0, 0)
	fgt.fill_to = Vector2(0, 1)
	fgt.width = 8
	fgt.height = 64
	_hint_fade = TextureRect.new()
	_hint_fade.texture = fgt
	_hint_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hint_fade.stretch_mode = TextureRect.STRETCH_SCALE
	_hint_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_fade.anchor_top = 1.0
	_hint_fade.anchor_bottom = 1.0
	_hint_fade.anchor_right = 1.0
	_hint_fade.offset_top = -150
	add_child(_hint_fade)
	# Einmal verbunden, nicht bei jedem Neuaufbau (Theme, Profil) noch einmal: Die Oberfläche wird neu gebaut,
	# die Steuerung (Nav) bleibt – früher kam mit jedem Aufbau ein weiterer Zuhörer dazu.
	if not Nav.focus_moved.is_connected(_auslauf_folgen):
		Nav.focus_moved.connect(_auslauf_folgen)


## Ebenen, die bis an den Rand reichen und ihre Tasten selbst zeigen (Mosaik: Glaspille), wollen keinen
## Auslauf über ihrem Inhalt (Meta uz_ohne_auslauf).
func _auslauf_folgen(_c: Control) -> void:
	var oben := Nav.top_layer()
	var ziel := 0.0 if oben != null and oben.has_meta("uz_ohne_auslauf") else 1.0
	if is_instance_valid(_hint_fade) and float(_hint_fade.get_meta("uz_auslauf_ziel", 1.0)) != ziel:
		_hint_fade.set_meta("uz_auslauf_ziel", ziel)
		U.kreuzen(_hint_fade, "uz_auslauf").tween_property(_hint_fade, "modulate:a", ziel, U.T_ORT)


## Die Bereiche in der gespeicherten Reihenfolge anlegen (noch unsichtbar), dazu die Apps.
func _build_bereiche() -> void:
	_pre_gen += 1    # neue Bereiche: ein laufendes Vorbauen hört auf
	sections.clear()
	order.clear()
	_tab_items.clear()
	app_kids.clear()
	folder_kids.clear()
	_word_tabs.clear()
	var hidden: Array = Config.get_value("theme.hidden_sections", [])
	var saved := _section_order()
	for sid in saved:
		# Apps und Einstellungen stehen als Symbole dahinter (alte Reihenfolgen nennen Apps noch
		# einzeln, auch „media“).
		if not SECTION_SCRIPTS.has(sid) or sid in LeisteOben.KIDS or sid in [LeisteOben.FOLDER, "settings"] or hidden.has(sid):
			continue
		# Freunde stehen nicht mehr oben: Select öffnet sie als Seitenleiste (open_friends).
		if sid == "friends":
			continue
		# Kinderprofil ohne Shop (src/core/profiles.gd): der Bereich fehlt ganz.
		if sid == "shop" and Config.kid_blocks("shop"):
			continue
		_word_tabs.append(sid)
	# Apps in eigener Reihenfolge, ohne ausgeblendete; „apps“ ausgeblendet: keine App-Symbole.
	var group_hidden: bool = hidden.has(LeisteOben.FOLDER) or not saved.has(LeisteOben.FOLDER)
	_apps_shown = LeisteOben.shown(LeisteOben.all_apps(), Config.get_value("apps.order", []), Config.get_value("apps.hidden", []), group_hidden)
	_gruppe = AppGruppe.new(self, func() -> Array: return order.filter(func(x: String) -> bool: return x in app_kids),
			func() -> Control: return tabs_box, "tab:")
	# Das Bild oben rechts führt immer zum Profil; wählbar ist es nur, wenn kein Reiter dafür da ist
	# (sonst zwei Stopps für dasselbe).
	var all: Array = _word_tabs + ["settings"]
	for t in _apps_shown:
		all.append(str(t.id))
	if not _apps_shown.is_empty():
		all.append(LeisteOben.FOLDER)
	if not _word_tabs.has("achievements"):
		all.append("achievements")
	avatar_box.focus_mode = Control.FOCUS_NONE if _word_tabs.has("achievements") else Control.FOCUS_ALL
	for sid in all:
		var s = SECTION_SCRIPTS[sid].new() if SECTION_SCRIPTS.has(sid) else _ext_section(sid)
		if s == null:
			_apps_shown = _apps_shown.filter(func(t: Dictionary) -> bool: return str(t.id) != sid)
			continue
		if LeisteOben.is_app_id(sid):
			app_kids.append(sid)
		s.main = self
		U.full_rect(s)
		s.visible = false
		view_host.add_child(s)
		sections[sid] = s


## Bereich einer eigenen App (Kachel zum Starten, ext_app_view.gd).
static func _ext_section(app_id: String) -> Control:
	var e := AppsExtern.get_entry(app_id)
	if e.is_empty():
		return null
	return ExtAppView.new().setup(e)


## Gespeicherte Reihenfolge, neue Bereiche (aus einem Update) an ihrer Standardstelle eingefügt.
func _section_order() -> Array:
	var saved: Array = (Config.get_value("theme.sections", []) as Array).duplicate()
	var defaults: Array = Config.DEFAULTS.theme.sections
	for i in defaults.size():
		var sid: String = defaults[i]
		if saved.has(sid):
			continue
		var at := saved.size()
		if i > 0 and saved.has(defaults[i - 1]):
			at = saved.find(defaults[i - 1]) + 1
		saved.insert(at, sid)
	return saved


func _build_tabs() -> void:
	_fill_tabs()
	# Passt die Leiste nicht (viele eigene Apps, große Oberfläche): eigene Apps in den Ordner, bei
	# sehr wenig Platz auch eingebaute (leiste_oben.gd plan) – nie abschneiden.
	var over := _tabs_over()
	if over <= 0.0:
		return
	var icons := order.filter(func(x: String) -> bool: return LeisteOben.is_app_id(x) or x == LeisteOben.FOLDER).size()
	var slot := 0.0
	for c in tabs_box.get_children():
		if str(c.get_meta("uz_key", "")) == "tab:settings":
			slot = (c as Control).get_combined_minimum_size().x + float(tabs_box.get_theme_constant("separation"))
	_slots = maxi(1, icons - int(ceilf(over / maxf(slot, 40.0))))
	for i in 6:
		_fill_tabs()
		if _tabs_over() <= 0.0 or _slots <= 1:
			return
		_slots -= 1


## Wie viel die Leiste oben zu breit ist (≤ 0: passt). Der Name eines App-Symbols klappt unter dem
## Cursor auf – dafür bleibt Platz; was _fit_top ohnehin wegnimmt (Level, Akku der Controller,
## Songtitel), zählt nicht mit.
func _tabs_over() -> float:
	var row := tabs_box.get_parent() as Control
	if row == null or not is_instance_valid(top_bar):
		return 0.0
	var avail: float = U.view_size().x - top_bar.get_theme_constant("margin_left") - top_bar.get_theme_constant("margin_right")
	var need := row.get_combined_minimum_size().x
	for c in [pad_box, music_box]:
		if is_instance_valid(c) and (c as Control).visible:
			need -= (c as Control).get_combined_minimum_size().x + float((c as Control).get_parent().get_theme_constant("separation"))
	var name_w := 0.0
	for c in tabs_box.get_children():
		if c.has_method("name_width"):
			name_w = maxf(name_w, float(c.call("name_width")))
	return need + name_w - avail


## Die Reiter: Wörter, Trenner, App-Symbole (mit Ordner), „+“, Zahnrad.
func _fill_tabs() -> void:
	var p := LeisteOben.plan(_apps_shown, false, _slots)
	folder_kids = p.folder
	order = _word_tabs.duplicate()
	for sid in p.bar:
		if sections.has(sid):
			order.append(sid)
	order.append("settings")
	_tab_items.clear()
	U.clear(tabs_box)
	if tabs_box.has_method("snap"):
		tabs_box.call("snap")
	tabs_box.add_child(_bumper("lt"))
	# Bereiche als Wörter (bei „Symbole“ unter Einstellungen → Leiste oben auch als Symbol).
	var symbols := str(Config.get_value("theme.tabs", "auto")) == "symbole"
	for sid in _word_tabs:
		_add_tab(sid, symbols)
	# Luft statt Haarlinie zwischen den Wörtern und den Symbolen und vor dem Zahnrad: Gruppen
	# trennen sich durch Abstand, nie durch eine Linie (Premium-Durchgang).
	if not (p.bar as Array).is_empty():
		tabs_box.add_child(U.spacer(LUFT, 0, false))
	for sid in p.bar:
		if sections.has(sid):
			_add_tab(str(sid), true)
	tabs_box.add_child(U.spacer(LUFT - 8, 0, false))
	_add_tab("settings", true)
	tabs_box.add_child(_bumper("rt"))


## Abstand zwischen den Gruppen der Leiste (Wörter · Symbole · Zahnrad), zusätzlich zu den Rändern der Reiter.
const LUFT := 26


func _add_tab(sid: String, compact: bool) -> void:
	var s = sections[sid]
	var item = NavItem.new()
	var ext := AppsExtern.is_ext_id(sid)
	item.setup(s.title, s.icon_name if compact and not ext else "", "tab", sid == top_of(current))
	item.compact = compact
	if ext:
		# Eigene App: ihr echtes App-Symbol, ohne eines ihr Anfangsbuchstabe; der Name bleibt, wie er ist.
		item.bild_path = AppsExtern.logo_path(sid)
		item.mono = LeisteOben.monogram(str(s.title))
		item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	item.set_meta("uz_key", "tab:" + sid)
	# Mouse: a click only shows the section, nothing more - otherwise a click on the icon would immediately start the
	# browser or the room. Opening goes through the tile in the section (or A).
	item.set_meta("uz_klick_waehlt_nur", true)
	item.picked.connect(func() -> void:
		if top_of(current) != sid:
			_slide_dir = signi(order.find(sid) - order.find(top_of(current)))
			goto(sid, "", false)
	)
	if LeisteOben.is_app_id(sid):
		# A startet eine eigene App bzw. betritt das Zimmer gleich; Y (wie Optionen überall, auch
		# Menü-Taste und Rechtsklick), langes A oder X: Verschieben, Ausblenden, Zurückholen, bei
		# eigenen Apps Entfernen.
		if ext or sid == "room" or sid == "browser":
			item.set_meta("uz_hint_a", "Starten" if ext else ("Öffnen" if sid == "browser" else "Betreten"))
			item.opened.connect(func() -> void: open_app(sid))
		else:
			item.opened.connect(_enter_view)
		var lab := str(s.title)
		var menu := func() -> void: app_menu(sid, lab)
		item.set_meta("uz_on_hold_a", menu)
		item.set_meta("uz_on_y", menu)
		item.set_meta("uz_on_x", menu)
		item.set_meta("uz_on_menu", menu)
		item.set_meta("uz_hint_y", "Optionen")
	else:
		item.opened.connect(_enter_view)
	tabs_box.add_child(item)
	_tab_items[sid] = item


## Der Reiter oben, zu dem ein Bereich gehört: Apps im Ordner → der Ordner.
func top_of(sid: String) -> String:
	return LeisteOben.FOLDER if sid in folder_kids else sid


## Optionen einer App (Symbol oben, Kachel im Ordner, Kachel der App): Verschieben, Ausblenden,
## Zurückholen, bei eigenen Apps Entfernen (app_gruppe.gd) – in der Reihe, in der sie steht.
func app_menu(app_id: String, label: String) -> void:
	if app_id in folder_kids and sections.has(LeisteOben.FOLDER):
		var g: Variant = sections[LeisteOben.FOLDER].get("_gruppe")
		if g is RefCounted:
			(g as RefCounted).call("menu", app_id, label)
			return
	if _gruppe:
		_gruppe.call("menu", app_id, label)


## Die zuletzt benutzte App (Ziel alter Sprünge auf „Apps“), sonst die erste.
func last_app() -> String:
	var last := str(Config.get_value("apps.last", ""))
	return last if last in app_kids else (str(app_kids[0]) if not app_kids.is_empty() else "")


## A auf einer App (Symbol oben, Kachel im Ordner): eigene starten, das Zimmer betreten, sonst die
## App als Bereich öffnen.
func open_app(app_id: String) -> void:
	if not (app_id in app_kids):
		return
	Config.set_value("apps.last", app_id)
	if AppsExtern.is_ext_id(app_id):
		start_app(app_id)
	elif app_id == "room":
		open_room()
	elif app_id == "browser":
		open_browser()
	elif current != app_id:
		await goto(app_id)
	else:
		_enter_view()


## Freunde als Seitenleiste von links (Select im Hauptmenü, alte Sprünge auf „friends“): die
## Liste von Steam und Discord (friends_view.gd in schmal); sub wählt den Dienst (steam, discord …).
func open_friends(sub := "") -> void:
	var top := Nav.top_layer()
	if top is FreundeLeiste:
		if sub != "":
			top.call("_open_sub", sub)
		return
	var l = FreundeLeiste.new()
	l.start_sub = sub
	open_layer(l)


## Der Bereich Freunde in der offenen Seitenleiste (sonst null) – für Proben und Mitteilungen.
func friends_view() -> Control:
	for l in Nav.layers:
		if l is FreundeLeiste and is_instance_valid(l.get("view")):
			return l.get("view")
	return null


## Add an app (installed Store apps, pick a program - app_add.gd): Einstellungen › Spiele › Leiste oben.
## The "+" at the top of the bar was removed because it was awkward to use.
func open_add_app() -> void:
	if not LeisteOben.extern_allowed():
		return
	var l = load("res://src/ui/layers/app_add.gd").new()
	l.main = self
	open_layer(l)


## Ein App-Symbol ist verschoben worden (langes A → Verschieben): die Reihe steht schon, nur die
## Reihenfolge der Bereiche (LT/RT) und des Ordners nachziehen.
func apps_umgestellt() -> void:
	_apps_shown = LeisteOben.shown(_apps_shown, Config.get_value("apps.order", []), [])
	app_kids = _apps_shown.map(func(t: Dictionary) -> String: return str(t.id)).filter(func(x: String) -> bool: return sections.has(x))
	var p := LeisteOben.plan(_apps_shown, false, _slots)
	folder_kids = p.folder
	order = _word_tabs.duplicate()
	for sid in p.bar:
		if sections.has(sid):
			order.append(sid)
	order.append("settings")


## Tastensymbol an den Enden der Reiterleiste: etwas kleiner und leiser als in den Hinweisen, und
## nur zu sehen, solange der Cursor oben steht (kopf_ruhe.gd) – der Platz bleibt, nichts rückt.
func _bumper(cmd: String) -> Control:
	var g := U.glyph(cmd, 26)
	g.set("subtle", true)
	g.set_meta("uz_bumper", true)
	g.modulate.a = kopf_ruhe.tasten_alpha() if is_instance_valid(kopf_ruhe) else 1.0
	return g


## A auf einem Reiter: hinein in den Bereich (die Auswahl wechselt schon beim Fokussieren).
func _enter_view() -> void:
	# Hinein in eine App: sie ist die zuletzt benutzte (Ziel alter Sprünge auf „Apps“).
	if current in app_kids and str(Config.get_value("apps.last", "")) != current:
		Config.set_value("apps.last", current)
	if sections.has(current) and is_instance_valid(sections[current]):
		sections[current].focus_default()


## Das Zeichen oben links (uzai_logo.gd, stil „kopf“): in die Kopfzeile eingebunden – das U im Ton
## der Schrift, nur die Lichtlinie im Akzent, so hoch wie die Schrift der Reiter; ohne Namen.
## brand_mark.pulse() lässt ein Licht einmal durch die Linie laufen (Guide-Signatur).
var brand_mark: Control


func _brand() -> Control:
	var wm: Control = Logo.new()
	wm.set("stil", "kopf")
	wm.custom_minimum_size = Vector2(Logo.zeichen_breite(BRAND_H, Logo.KOPF_STIL == "kachel"), BRAND_H)
	wm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_mark = wm
	return wm


const BRAND_H := Logo.KOPF_H


## Unterbereiche an ihren Platz bringen: Ein Bereich kann sie selbst aufnehmen (die Startseite
## zeigt die Quellen über dem Regal), sonst stehen sie unter den Reitern.
func place_chips(host: Control) -> void:
	if not is_instance_valid(chips_box) or not is_instance_valid(_chips_pan):
		return
	var target: Control = host if is_instance_valid(host) else _chips_home
	if _chips_pan.get_parent() != target:
		if _chips_pan.get_parent():
			_chips_pan.get_parent().remove_child(_chips_pan)
		target.add_child(_chips_pan)
	if is_instance_valid(_chips_home):
		_chips_home.visible = target == _chips_home


## Vor dem Neuaufbau eines Bereichs: Unterbereiche zurückholen, damit sie nicht mit gelöscht werden.
func park_chips() -> void:
	place_chips(null)


func _build_chips(s) -> void:
	place_chips(s.chips_slot if is_instance_valid(s.chips_slot) else null)
	U.clear(chips_box)
	if chips_box.has_method("snap"):
		chips_box.call("snap")
	if is_instance_valid(_chips_pan):
		_chips_pan.call("snap")
	var subs: Array = s.subtabs()
	if (subs.size() <= 1 and s.id != "settings") or s.own_subnav:
		# Platzhalter genau so hoch wie die Unterbereiche: Die Kopfzeile behält ihre Höhe, der Inhalt
		# springt nicht (App zu App, Bereich zu Bereich).
		chips_box.add_child(U.spacer(0, _chip_h, false))
		return
	chips_box.add_child(_bumper("lb"))
	for t in subs:
		var item = NavItem.new()
		item.setup(str(t.label), "", "chip", t.id == s.sub, int(t.get("count", -1)) if s.chip_counts else -1)
		item.set_meta("uz_key", "chip:" + str(t.id))
		var sub_id := str(t.id)
		# Quellen der Startseite: das echte Logo statt des Namens, wenn es da ist (badge_logos.gd).
		if s.has_method("chip_logo"):
			item.logo = s.chip_logo(sub_id)
		item.picked.connect(func() -> void:
			if s.sub != sub_id:
				_open_sub(s, sub_id, false)
		)
		# Bereiche mit einem Raster je Quelle (Spiele): A auf der Quelle öffnet gleich alles daraus
		# (z. B. die ganze Steam-Bibliothek), statt das Regal bis ans Ende zu blättern.
		if s.has_method("open_source"):
			item.set_meta("uz_hint_a", "Alle anzeigen")
			item.opened.connect(func() -> void:
				if not s.open_source(sub_id):
					_enter_view())
		else:
			item.opened.connect(_enter_view)
		# Langes A: Quelle verschieben, ausblenden, Ausgeblendetes zurückholen (Spiele).
		if s.has_method("sub_menu"):
			var lab := str(t.label)
			item.set_meta("uz_on_hold_a", func() -> void: s.sub_menu(sub_id, lab))
		# Runter aus den Unterbereichen: an den Anfang der Seite (Kopf mit Banner bzw. Rampenlicht),
		# nicht ans Element, das gerade geometrisch darunter liegt. Nicht, wo die Unterbereiche in
		# der Seite selbst stehen (Startseite der Spiele).
		if not is_instance_valid(s.chips_slot):
			item.set_meta("uz_down", func() -> bool:
				if not sections.has(current) or sections[current] != s or Nav.default_in(s) == null:
					return false
				s.focus_default()
				return true)
		chips_box.add_child(item)
	# Aktionen hinter den Quellen (Spiele: „Hinzufügen“): tun nur etwas auf A bzw. Klick – Darüberwandern wählt keine
	# Quelle und öffnet nichts.
	if s.has_method("chip_aktionen"):
		for a in s.chip_aktionen():
			var tat = NavItem.new()
			tat.setup(str(a.label), str(a.get("icon", "")), "chip", false, -1)
			tat.set_meta("uz_key", "chip_aktion:" + str(a.id))
			tat.set_meta("uz_hint_a", str(a.label))
			var tun: Callable = a.tun
			tat.opened.connect(func() -> void: tun.call())
			chips_box.add_child(tat)
	chips_box.add_child(_bumper("rb"))
	_merke_chip_h()


## Höhe einer Leiste mit Unterbereichen (nach dem Anordnen gemessen) für den Platzhalter.
var _chip_h := 46.0


func _merke_chip_h() -> void:
	await get_tree().process_frame
	if is_instance_valid(chips_box) and chips_box.is_visible_in_tree() and chips_box.size.y > 8.0 \
			and chips_box.get_children().any(func(c: Node) -> bool: return c is NavItem):
		_chip_h = chips_box.size.y


var _rebuild_queued := false
var _quiet_goto := false
var _goto_after := ""            ## nach dem nächsten Neuaufbau diese App zeigen (show_app_soon)


## Nach dem Neuaufbau (neue App oben in der Leiste) den Cursor auf ihr Symbol.
func show_app_soon(id: String) -> void:
	_goto_after = id
	_rebuild()


func _rebuild() -> void:
	# Mehrere Änderungen kurz hintereinander nur einmal umsetzen.
	if _rebuild_queued:
		return
	_rebuild_queued = true
	await get_tree().process_frame
	# Erst nach dem Bildsignal umbauen (aufgeschoben): Mitten in process_frame nähme _build Ebenen
	# und Bereiche aus dem Baum, deren eigenes „await process_frame“ im selben Signal danach noch
	# weiterläuft – get_tree() wäre dort null (Freund, 2560 × 1440: die Bildschirmerkennung stellt
	# beim ersten Start die Größe um, während die Einrichtung schon offen ist). Aufgeschoben gehen
	# die alten Knoten noch in diesem Bild weg, bevor sie weiterlaufen könnten.
	_rebuild_jetzt.call_deferred()


func _rebuild_jetzt() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	var keep_key := ""
	var f := Nav.focused()
	if f and f.has_meta("uz_key"):
		keep_key = str(f.get_meta("uz_key"))
	var keep_sec := current
	var keep_sub := ""
	if sections.has(current):
		keep_sub = sections[current].sub
	current = ""
	_build()
	# Eben hinzugefügte App (app_add.gd): ihr Bereich, der Cursor auf ihr Symbol oben (bzw. auf ihre
	# Kachel im Ordner „Meine Apps“).
	if _goto_after != "" and sections.has(_goto_after):
		keep_sec = _goto_after
		keep_sub = ""
		keep_key = "tab:" + _goto_after
		if _goto_after in folder_kids:
			keep_sec = LeisteOben.FOLDER
			keep_key = "app:" + _goto_after
	_goto_after = ""
	# Die offene App ist ausgeblendet oder entfernt worden: die zuletzt benutzte (bzw. der erste Reiter).
	if keep_sec != "" and not sections.has(keep_sec):
		keep_sec = last_app() if LeisteOben.is_app_id(keep_sec) and not app_kids.is_empty() else (str(order[0]) if not order.is_empty() else "")
		keep_sub = ""
		if keep_key.begins_with("tab:"):
			keep_key = "tab:" + top_of(keep_sec)
	if keep_sec != "":
		# Neuaufbau nach einer Einstellung: ohne Einflug und ohne Klang, die Seite bleibt stehen.
		_quiet_goto = true
		await goto(keep_sec, keep_sub, keep_key == "")
		_quiet_goto = false
		if keep_key != "":
			_refocus(keep_key)


func _refocus(key: String) -> void:
	await get_tree().process_frame
	for c in Nav.focusables(shell):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return
	if sections.has(current) and is_instance_valid(sections[current]):
		sections[current].focus_default()


# --- Navigation zwischen Bereichen -------------------------------------------

func goto(sec_id: String, sub_id := "", focus_view := true) -> void:
	# Ein Bereichswechsel bei offenem Guide: die Seite zeichnet sich wieder selbst (main_fenster.gd).
	_seite_weiter()
	# Freunde sind kein Bereich mehr: jeder Sprung dorthin (Guide, Für dich, Themes) öffnet die
	# Seitenleiste.
	if sec_id == "friends":
		open_friends(sub_id)
		return
	# Alte Ziele „apps“ und „media“: die genannte bzw. zuletzt benutzte App (leiste_oben.gd).
	var ziel: Array = LeisteOben.resolve_goto(sec_id, sub_id, app_kids, order, str(Config.get_value("apps.last", "")))
	sec_id = str(ziel[0])
	sub_id = str(ziel[1])
	if not sections.has(sec_id):
		return
	# Richtung: wie gedrückt (LT/RT, auch über das Ende hinaus), sonst nach der Lage der Reiter.
	var dir := _slide_dir
	if dir == 0:
		dir = signi(order.find(top_of(sec_id)) - order.find(top_of(current))) if current != "" else 1
	if dir == 0:
		# Von App zu App: nach ihrer Lage in der Reihe.
		dir = signi(app_kids.find(sec_id) - app_kids.find(current))
	if dir == 0:
		dir = 1
	_slide_dir = 0
	# Von App zu App (Symbole nebeneinander): ein Ortswechsel – kürzer, kleiner Weg.
	var ort: bool = current in app_kids and sec_id in app_kids
	if current != "" and sections.has(current) and current != sec_id:
		sections[current].on_leave()
		_exit_section(sections[current], dir, ort)
	var changed := current != sec_id
	current = sec_id
	for sid in _tab_items.keys():
		_tab_items[sid].set_selected(sid == top_of(sec_id))
	if is_instance_valid(avatar_box) and avatar_box.has_method("set_selected"):
		avatar_box.set_selected(sec_id == "achievements" and not order.has("achievements"))
	if not _tab_items.has(top_of(sec_id)) and tabs_box.has_method("clear_line"):
		tabs_box.call("clear_line")
	var s = sections[sec_id]
	# Kommt ein Bereich zurück, während er noch hinausgleitet: Ausgang abbrechen.
	if s.has_meta("uz_skip"):
		s.remove_meta("uz_skip")
		U.stop(s, "uz_sec")
		U.stop(s, "uz_slide")
		_lage_ende(s)
	U.titel_zurueck(s)
	s.visible = true
	if changed and is_instance_valid(background):
		background.pan_to(order.find(top_of(sec_id)), order.size())
	var subs: Array = s.subtabs()
	var pick: String = s.resolve_sub(sub_id) if sub_id != "" else ""
	# Bereich neu betreten (LT/RT, Reiter): immer vorn anfangen – erster Unterbereich, erstes
	# Element. Nur ein Neuaufbau desselben Bereichs behält den Unterbereich; Ebenen (Spielseite,
	# Details) berühren das nicht, B kehrt dorthin zurück, wo man war.
	var fresh := changed and sub_id == "" and not _quiet_goto
	if pick == "" or not subs.any(func(t): return t.id == pick):
		var keep: bool = not fresh and subs.any(func(t): return t.id == s.sub)
		pick = s.sub if keep else (str(subs[0].id) if not subs.is_empty() else "")
	if fresh:
		s.reset_position()
	# Ladezeiten der Medien-Bereiche messen (logs/leistung.log, src/core/ladezeit.gd).
	if s.has_method("lade_stand") and (changed or s.sub != pick):
		var lab := pick
		for t in subs:
			if str(t.id) == pick:
				lab = str(t.get("label", pick))
		Ladezeit.oeffnen(str(s.title), lab)
	s.sub = pick
	# Von außen gezielt geöffnet (z. B. „Spieleordner festlegen“): der Bereich darf gleich in den
	# Inhalt springen statt auf seine Unterbereiche.
	s.set_meta("uz_deep_link", sub_id != "")
	if sec_id != "games":
		background.clear_image()
	if sec_id in ["settings", "friends", "shop", "room"]:
		background.neutral()
	if s.needs_build():
		s.build()
	else:
		s.reenter()
	# Vorgebaut zählt nur für das erste Betreten; danach gilt wieder keep_built.
	s.prebuilt = false
	_build_chips(s)
	if not changed:
		Ladezeit.pruefen(s)
	if changed and _quiet_goto:
		s.on_enter()
		Ladezeit.pruefen(s)
		s.modulate.a = 1.0
		s.scale = Vector2.ONE
	elif changed:
		Sfx.play("tab")
		s.on_enter()
		Ladezeit.pruefen(s)
		# Takt: erst gehen, dann kommen. Der alte Bereich geht sofort (T_WEG), der neue kommt gleich
		# danach (nach dem Aufbau-Bild) aus der Richtung des Wechsels gleitend (Bereich W_BEREICH in T_RAUM,
		# App zu App als Ortswechsel W_ORT in T_ORT). Als eine Fläche, ohne Staffel der Reihen und ohne
		# Skalierung: Gestaffelt deckte der neue Bereich anfangs zu wenig (gemessen: ein Helligkeitsloch
		# auf hellen Seiten, letzte Bewegung erst bei 600 ms), und skaliert wird Schrift weich.
		U.stop(s, "uz_sec")
		U.stop(s, "uz_ankunft")
		s.modulate.a = 0.0
		s.scale = Vector2.ONE
		# Erst nach dem Aufbau-Frame starten: sonst springt die Bewegung im ersten Bild um ~die Hälfte.
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(s) and current == sec_id:
			var dauer := U.T_ORT if ort else U.T_RAUM
			U.slide_x(s, (U.W_ORT if ort else U.W_BEREICH) * dir, dauer)
			var tw := U.ankommen(s, U.T_ORT, "uz_sec")
			tw.tween_property(s, "modulate:a", 1.0, U.T_ORT)
	if focus_view:
		await get_tree().process_frame
		if is_instance_valid(s) and s.is_inside_tree() and current == sec_id:
			s.focus_default()


## Der verlassene Bereich geht: Er gleitet sofort ein Stück zur anderen Seite (W_ORT, ease-out – er
## verlässt den Schirm nicht ganz) und kreuzt mit dem neuen (Kurve „Kreuzen“: ein Bild halten, dann
## sanft in T_WEG – zusammen decken beide in jedem Bild über 85 %, kein dunkles Zwinkern). Nur sein
## großer Titel weicht zuerst (U.titel_weichen, T_ANTWORT): zwei Titel stehen nie übereinander. Er
## ist aus dem Fluss gehoben: Ändert sich im selben Bild die Kopfzeile, bleibt er, wo er war
## (_halte_lage). Für die Steuerung ist er sofort weg (uz_skip).
func _exit_section(s: Control, dir: int, ort := false) -> void:
	if not is_instance_valid(s) or not s.visible:
		return
	s.set_meta("uz_skip", true)
	U.stop(s, "uz_ankunft")
	U.stop(s, "uz_slide")
	s.scale = Vector2.ONE
	# Ein Bereich, der die ganze Fläche deckt (Zimmer: die Tür), kreuzt nicht: Er stünde sonst noch
	# halb sichtbar im neuen Bereich und „zöge mit“. Er geht sofort und kurz (T_ANTWORT), ohne Gleiten.
	if s.get("ganze_flaeche") == true:
		var kurz := U.weg(s, "uz_sec")
		kurz.tween_property(s, "modulate:a", 0.0, U.T_ANTWORT)
		kurz.tween_callback(func() -> void:
			if is_instance_valid(s) and sections.get(current) != s:
				s.visible = false
				s.modulate.a = 1.0)
		return
	s.set_meta("uz_lage", s.get_global_rect())
	s.set_meta("uz_dx", 0.0)
	var weg := U.weg_px(U.W_ORT * (0.5 if ort else 1.0)) * dir
	var tw := U.weg(s, "uz_sec").set_parallel(true)
	U.kreuz_aus(tw, s)
	U.titel_weichen(s)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(s):
			s.set_meta("uz_dx", v)
			_halte_lage(s)
	, 0.0, -weg, U.T_WEG).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(func() -> void:
		if not is_instance_valid(s):
			return
		if sections.get(current) != s:
			s.visible = false
		_lage_ende(s)
	)
	_halte_lage(s)


## Den verlassenen Bereich an seiner gemerkten Lage auf dem Schirm halten (plus Weggleiten).
func _halte_lage(s: Control) -> void:
	if not s.has_meta("uz_lage") or not is_instance_valid(view_host):
		return
	var g: Rect2 = s.get_meta("uz_lage")
	var inv := view_host.get_global_transform().affine_inverse()
	var p := inv * g.position
	var sz := inv.basis_xform(g.size)
	var dx := float(s.get_meta("uz_dx", 0.0))
	s.offset_left = p.x + dx
	s.offset_top = p.y
	s.offset_right = p.x + dx + sz.x - view_host.size.x
	s.offset_bottom = p.y + sz.y - view_host.size.y


func _lage_ende(s: Control) -> void:
	if s.has_meta("uz_lage"):
		s.remove_meta("uz_lage")
	s.offset_left = 0.0
	s.offset_top = 0.0
	s.offset_right = 0.0
	s.offset_bottom = 0.0


## Reiter neu zeichnen, wenn sich die Unterbereiche ändern (zum Beispiel neue Merkliste).
func refresh_chips() -> void:
	if sections.has(current):
		var keep := Nav.focused()
		var on_chips := keep != null and chips_box.is_ancestor_of(keep)
		_build_chips(sections[current])
		if on_chips:
			for c in chips_box.get_children():
				if c.get_meta("uz_selected", false):
					Nav.focus(c, true)


## Bereiche, deren Reiter beim Wechsel weiter hereingleiten (siehe _open_sub).
const MEDIEN_REITER := ["videos", "movies", "streams"]


func _open_sub(s, sub_id: String, focus_view := true) -> void:
	var ids: Array = (s.subtabs() as Array).map(func(t): return str(t.id))
	var d := signi(ids.find(sub_id) - ids.find(str(s.sub)))
	# Anderer Unterbereich (LB/RB): auch dort vorn anfangen.
	s.reset_position()
	s.sub = sub_id
	for c in chips_box.get_children():
		if c.has_method("set_selected"):
			c.set_selected(str(c.get_meta("uz_key", "")) == "chip:" + sub_id)
	Sfx.play("tab")
	# Kann der Bereich nur den Inhalt der Quelle tauschen (Startseite), bleibt der Rest stehen:
	# kein Flackern, kein Neuaufbau der Quellenleiste, der Fokus bleibt, wo er ist.
	if s.has_method("switch_sub") and s.switch_sub(d):
		if focus_view:
			await get_tree().process_frame
			if is_instance_valid(s) and s.is_inside_tree():
				s.focus_default()
		return
	# Ortswechsel (Takt): Der alte Inhalt geht in einer Hülle W_ORT zur Gegenseite und verblasst,
	# der neue kommt ein Drittel davon später aus der Richtung des Wechsels – nie ein leeres Bild.
	# Nur wo die Unterbereiche nicht selbst im Bereich liegen (Startseite: Quellen sind Teil der
	# Seite und wechseln über switch_sub).
	if d != 0 and not is_instance_valid(s.chips_slot) and s.is_visible_in_tree():
		U.stop(s, "uz_sec")
		U.stop(s, "uz_slide")
		s.modulate.a = 1.0
		s.offset_left = 0.0
		s.offset_right = 0.0
		U.abgang(s, d)
		s.build()
		# Medien (Videos, Filme, Streams): der neue Reiter gleitet weiter und ruhiger herein –
		# beim Durchschalten soll man den Wechsel spüren.
		if str(s.id) in MEDIEN_REITER:
			U.ankunft(s, d, U.T_RAUM, U.NACH_WEG, U.W_BEREICH)
		else:
			U.ankunft(s, d)
	else:
		s.build()
		U.cascade.call_deferred(s)
	if focus_view:
		await get_tree().process_frame
		if is_instance_valid(s) and s.is_inside_tree():
			s.focus_default()


func _step_section(d: int) -> void:
	if order.is_empty():
		return
	var i := order.find(top_of(current))
	# Im Profil (Bild oben rechts, nicht in der Leiste): RT zum ersten, LT zum letzten Reiter.
	if i < 0:
		i = -1 if d > 0 else 0
	var nxt: String = order[(i + d + order.size()) % order.size()]
	var on_tabs := Nav.focused() != null and tabs_box.is_ancestor_of(Nav.focused())
	_slide_dir = d
	await goto(nxt, "", not on_tabs)
	if on_tabs:
		Nav.focus(_tab_items[nxt], true)


func _step_sub(d: int) -> void:
	var s = sections.get(current)
	if s == null:
		return
	var subs: Array = s.subtabs()
	if subs.size() <= 1:
		return
	var i := 0
	for k in subs.size():
		if subs[k].id == s.sub:
			i = k
	var nxt := str(subs[(i + d + subs.size()) % subs.size()].id)
	var on_chips := Nav.focused() != null and chips_box.is_ancestor_of(Nav.focused())
	await _open_sub(s, nxt, not on_chips)
	if on_chips:
		for c in chips_box.get_children():
			if str(c.get_meta("uz_key", "")) == "chip:" + nxt:
				Nav.focus(c, true)


func _on_command(cmd: String) -> void:
	if cmd == "unfocused":
		if _start_taste_holt():
			return
	else:
		_start_bedient = true
	if _boot and is_instance_valid(_boot):
		_boot.taste()
		return
	# Liegt eine Ebene offen (Seitenleiste, Dialog), schaltet dahinter nichts um.
	if cmd in ["lt", "rt", "lb", "rb"] and Nav.top_layer() != null:
		return
	match cmd:
		"lt": _step_section(-1)
		"rt": _step_section(1)
		"lb": _step_sub(-1)
		"rb": _step_sub(1)
		"guide": toggle_guide("", Nav.guide_src)
		# Schnellmenü-Taste der Handhelds (bzw. selbst belegt): wie Guide-Taste halten.
		"quick": toggle_guide(Guide.QUICK)
		"capture": clip_hotkey("share")
		"capture_chord": clip_hotkey("chord")
		"unfocused":
			Toasts.show_toast("Ein anderes Fenster ist vorn", "Die Guide-Taste holt Uzai zurück.", "controller",
					{ "overlay": true, "ms": 4500, "quiet": true, "sound": "notify" })
		"view":
			# Pop-ups zuerst (Nachricht öffnen); sonst schaltet View im Zimmer den Modus (Leben, Bauen,
			# Foto); im Hauptmenü öffnet bzw. schließt Select die Freunde (Seitenleiste).
			if not Toasts.open_latest():
				var zim := room_layer()
				var top := Nav.top_layer()
				if zim and top == zim:
					zim.call("nav_command", "view")
				elif top is FreundeLeiste:
					Sfx.play("back")
					top.call("close")
				elif top == null and not Launcher.in_game:
					open_friends()
		"search":
			# Über einer offenen Ebene (Dialog, Spielseite, Guide) nicht – die hat den Vorrang.
			if Nav.top_layer() == null:
				open_search()
		"menu":
			var f := Nav.active()
			if f and Nav.top_layer() == null and view_host.is_ancestor_of(f) and sections.has(current) \
					and sections[current].has_method("menu_taste") and sections[current].menu_taste():
				# Bereich mit eigener Menü-Taste, vor allem anderen (Startseite: „Für dich“ als
				# Seitenleiste – auf dem Cover tat Start sonst dasselbe wie Y; Videos: neu laden).
				pass
			elif f and f.get("game") is Dictionary and not (f.get("game") as Dictionary).is_empty():
				open_game_options(f.get("game"))
			elif f and f.has_meta("uz_on_menu") and Nav.top_layer() == null:
				# Optionen einer App (Symbol oben, Kachel): wie Y.
				(f.get_meta("uz_on_menu") as Callable).call()
			else:
				toggle_guide("", "menu")
		"b":
			var f2 := Nav.focused()
			# Bereiche mit Unterseiten (Shop → Genre) gehen erst eine Ebene zurück.
			if f2 and view_host.is_ancestor_of(f2) and sections.has(current) and sections[current].has_method("handle_back") and sections[current].handle_back():
				Sfx.play("back")
				return
			if f2 and chips_box.is_ancestor_of(f2):
				_focus_top()
				Sfx.play("back")
			elif f2 and view_host.is_ancestor_of(f2):
				# Nach oben heißt auch: die Seite wieder von vorn (Kopf sichtbar, runter führt zum
				# ersten Element statt an die alte Stelle ganz unten).
				# Bereiche, die selbst rollen (Filme: Reihen statt ScrollContainer), sagen es per scrolled().
				var rolled := Nav.scroll_page_top(f2)
				if sections.has(current) and (rolled or (sections[current].has_method("scrolled") and sections[current].scrolled())):
					sections[current].reset_position()
				for c in chips_box.get_children():
					if c.get_meta("uz_selected", false):
						Nav.focus(c, true)
						Sfx.play("back")
						return
				_focus_top()
				Sfx.play("back")


## Nach oben: auf den Reiter des Bereichs – im Profil (kein Reiter) auf das Bild oben rechts.
func _focus_top() -> void:
	var t: Control = _tab_items.get(top_of(current))
	if t == null and is_instance_valid(avatar_box) and avatar_box.focus_mode == Control.FOCUS_ALL:
		t = avatar_box
	if t:
		Nav.focus(t, true)


# --- Statuszeile ---------------------------------------------------------------

var _tick_n := 0


func _tick() -> void:
	if _kid_rebuild_due and Nav.layers.is_empty() and not Launcher.in_game:
		_kid_rebuild_due = false
		_rebuild()
	# Uhr und der Punkt für neue Mitteilungen am Profilbild.
	if is_instance_valid(kopf_status):
		kopf_status.tick()
	_tick_n += 1
	if _tick_n % 60 == 1 and not Launcher.in_game:
		_refresh_pads()
	if not is_instance_valid(_power_off):
		Config.run_where("spiel" if Launcher.in_game else current)
	_schirm_takt(_started and not _closing and not _video_overlay)


## Akkustand der Controller oben rechts: nur schwache (kopf_status.gd; alle stehen im Guide).
func _refresh_pads() -> void:
	if not is_instance_valid(kopf_status):
		return
	kopf_status.set_pads(Pads.pads)
	_fit_top()


## Profilbild (mehrere Profile: das Uzai-Profil, sonst das Bild aus Steam), Freunde online und
## „läuft gerade“ neu lesen (kopf_status.gd).
func _update_status() -> void:
	if not is_instance_valid(kopf_status):
		return
	var now := now_playing(Music.now)
	kopf_status.refresh(_profile_sig(), now, _music_wanted(now))
	_fit_top()


## Bei großer Oberfläche (ab ~130 %) ist oben kein Platz für den Songtitel.
func _music_wanted(now: Dictionary) -> bool:
	return not now.is_empty() and get_viewport().get_visible_rect().size.x >= 1700.0 and _top_tight < 3


## Reicht oben der Platz nicht (viele Reiter, große Oberfläche), treten nacheinander der Akku
## eines schwachen Controllers (steht auch im Guide) und der Songtitel zurück – die Reiter bleiben
## immer ganz, und nichts schiebt die Seite über den Rand.
func _fit_top() -> void:
	if not is_instance_valid(top_bar) or not is_instance_valid(tabs_box) or not is_instance_valid(kopf_status):
		return
	var row := tabs_box.get_parent() as Control
	var avail: float = U.view_size().x - top_bar.get_theme_constant("margin_left") - top_bar.get_theme_constant("margin_right")
	var now := now_playing(Music.now)
	for t in 4:
		_top_tight = t
		pad_box.visible = kopf_status.hat_schwache() and not _narrow_top and t < 2
		music_box.visible = _music_wanted(now)
		if row.get_combined_minimum_size().x <= avail:
			return


## Was oben neben dem Pegel steht: der Video-Ton im Hintergrund (den hat man eben selbst gestartet),
## sonst die Musik ({ title, artist, playing } wie Music.now).
static func now_playing(music: Dictionary) -> Dictionary:
	if Video.active and Video.background:
		return { "title": str(Video.video.get("title", "Video")), "artist": str(Video.video.get("channel", "")), "playing": not Video.paused }
	return music


## Freunde online (Steam und Discord, getrennt wie in den Listen) – die Zahl neben dem
## Freunde-Symbol oben und im Guide (kopf_status.gd).
static func online_friends() -> int:
	return KopfStatus.online_friends()


func _on_scan_state(text: String) -> void:
	scan_label.text = text


## Einem Freund ins Spiel folgen (Steam „Beitreten“) – wie ein normaler Spielstart: Ladebildschirm,
## Uzai geht aus dem Weg, Guide, „Spiel beenden“ und Spielzeit funktionieren. Früher öffnete jede
## Stelle nur den Steam-Link: Uzai blieb im Vollbild vorn, das Spiel startete dahinter, und aus dem
## Guide ließ sich so ein zweites Spiel starten.
func join_game(f: Dictionary, url := "") -> void:
	if url == "":
		url = Social.join_url(f)
	if not Sicher.steam_join_ok(url):
		return
	var gid := str(f.get("game_id", ""))
	var who := str(f.get("name", ""))
	if Launcher.in_game:
		# Im selben Spiel verbindet Steam einfach (Lobby beitreten); ein anderes Spiel nicht daneben starten.
		if gid != "" and str(Launcher.current.get("appid", "")) == gid:
			OS.shell_open(url)
			Toasts.show_toast("Beitreten", "Steam verbindet dich mit %s." % who, "play", { "sound": "launch" })
		else:
			Toasts.show_toast("Es läuft schon ein Spiel", "Erst beenden, dann %s beitreten." % who, "warning")
		return
	var g := Library.get_game("steam:" + gid) if gid != "" else {}
	if g.is_empty():
		g = { "id": "steam:" + gid, "title": Library.friend_game_title(str(f.get("game", "")), gid), "source": "steam", "system": "steam",
			"appid": int(gid) if gid.is_valid_int() else 0, "installed": true }
	var g2 := g.duplicate()
	g2["start_url"] = url
	Toasts.show_toast("Beitreten", "Steam verbindet dich mit %s." % who, "play", { "ms": 2500, "quiet": true })
	launch(g2)


## Disc eingelegt: kurz melden, View startet gleich das Abbild. Ohne passendes Abbild nennt die
## Meldung die Disc beim Namen; View spielt sie dann direkt vom Laufwerk (ohne dass Uzai etwas
## anlegt), kann der Emulator das nicht, ordnet View ihr ein Abbild zu.
## Entfernen bleibt still (die Startseite nimmt die Plakette wieder weg).
func _on_disc_changed(inserted: bool) -> void:
	if not inserted or Launcher.in_game:
		return
	var g := Discs.game()
	if g.is_empty():
		var short := str(Config.system(Discs.system).get("short", "PS"))
		var direct := Discs.can_play()
		Toasts.show_toast("%s eingelegt" % Discs.title() if Discs.disc_name != "" else "%s-Disc erkannt" % short,
			("%s · spielt direkt vom Laufwerk" if direct else "%s · noch kein Abbild in der Bibliothek") % Discs.serial, "disc", {
			"ms": 7000, "tag": "disc",
			"open": play_disc if direct else open_disc_assign, "open_text": "Spielen" if direct else "Abbild zuordnen",
			"go": play_disc if direct else open_disc_assign, "go_text": "Spielen" if direct else "Abbild zuordnen",
		})
		return
	Toasts.show_toast("Disc eingelegt", Library.display_title(g), "disc", {
		"sub_raw": true,
		"open": open_game_note.bind(g),
		"open_text": "Öffnen",
		"go": open_game_note.bind(g),
		"go_text": "Zum Spiel",
	})


## Eingelegte Disc ohne Abbild direkt vom Laufwerk spielen (src/core/discs.gd). Kann der Emulator
## das nicht, bleibt „Abbild zuordnen“.
func play_disc() -> void:
	Toasts.dismiss("disc")
	var g := Discs.direct_game()
	if g.is_empty():
		open_disc_assign()
		return
	launch(g)


## Der eingelegten Disc ein Abbild aus der Bibliothek zuordnen (bleibt gespeichert). Oben die
## Spiele, deren Titel zur Disc passt; gestartet wird danach immer dieses Abbild.
func open_disc_assign() -> void:
	if Discs.serial == "":
		Toasts.show_toast("Keine Disc im Laufwerk", "", "disc", { "quiet": true, "sound": "error" })
		return
	Toasts.dismiss("disc")
	var serial := Discs.serial
	var sys := Discs.system
	var s = SheetLayer.new()
	var short := str(Config.system(sys).get("short", "PS"))
	s.setup("Abbild zuordnen", "%s  ·  %s-Disc %s" % [Discs.title(), short, serial], 760)
	s.fill_func = func(sheet) -> void:
		var list: Array = Library.disc_candidates(serial, sys)
		if list.is_empty():
			sheet.add_label("Keine %s-Spiele. Abbild in den Spieleordner legen.%s" % [short,
					" A spielt die Disc vom Laufwerk." if Discs.can_play() else ""], "m", "muted")
			return
		sheet.add_label("Abbild zu dieser Disc wählen.", "s", "faint")
		for g in list:
			var it = ListItemC.new()
			var p := str(g.get("path", ""))
			it.setup(Library.display_title(g), p.get_file(), "")
			it.icon_name = "disc"
			it.set_meta("uz_hint_a", "Zuordnen")
			it.activated.connect(func() -> void:
				Discs.link(str(g.id))
				sheet.close()
				Toasts.show_toast("Disc zugeordnet", "%s startet jetzt, wenn diese Disc drin ist." % Library.display_title(g), "check", {
					"sound": "select", "go": open_game_note.bind(g), "go_text": "Zum Spiel" })
			)
			sheet.add_row(it)
	open_layer(s)


func _on_library_changed() -> void:
	if Launcher.in_game or not sections.has(current):
		return
	if current == "games" or current == "settings":
		var keep := ""
		var f := Nav.focused()
		if f and f.has_meta("uz_key"):
			keep = str(f.get_meta("uz_key"))
		elif f and f.get("game") is Dictionary:
			keep = "g:" + str((f.get("game") as Dictionary).get("id", ""))
		var s = sections[current]
		s.build()
		_build_chips(s)
		if Nav.top_layer() == null and keep != "":
			_refocus(keep)
		elif Nav.top_layer() == null and (f == null or not is_instance_valid(f)):
			s.focus_default()


# --- Einstellungen und Suche öffnen, Uzai beenden ------------------------------------------------

## Ein Bereich sucht selbst weiter (Treffer aus der Suche über alles: „Alle Treffer …“).
func search_in(sid: String, q: String) -> void:
	if sid == "music":
		load("res://src/ui/components/music_bits.gd").open_search(self, q)
		return
	if not sections.has(sid) or not sections[sid].has_method("search_for"):
		return
	await goto(sid, "suche")
	if sections.has(sid) and current == sid:
		sections[sid].search_for(q)


## Eine Einstellung zeigen: Kategorie öffnen und die Zeile wählen (in einer Unterseite: diese auf).
func open_setting(cat: String, key: String, more := "") -> void:
	if not sections.has("settings"):
		return
	await goto("settings", cat)
	if current == "settings":
		sections["settings"].focus_row(key, more)


## Uzai beenden – mit Rückfrage. Vorher kurz auf Schwarz blenden. Ist „Nach dem Schließen im
## Hintergrund bereit“ an (Helper.wake_active), heißt es „schließen“: Uzai beendet sich trotzdem ganz,
## nur ein winziger Wächter wartet auf die Guide-Taste und startet Uzai dann neu. full: „Uzai ganz
## beenden“ – ohne Wächter, danach geht es nur mit Maus oder Tastatur weiter.
func ask_quit_uzai(full := false) -> void:
	var game := "Das laufende Spiel wird vorher beendet. " if Launcher.in_game else ""
	if Helper.wake_active() and not full:
		# Schließen ist hier harmlos (die Guide-Taste holt Uzai zurück) und steht vorn – außer ein Spiel
		# läuft, das dabei endet: dann steht Abbrechen vorn wie bisher.
		open_dialog("Uzai schließen?",
				game + "Guide-Taste startet Uzai wieder.", [
			["Schließen", func() -> void: _quit_uzai(), "danger" if Launcher.in_game else ""],
			["Ganz beenden", func() -> void: _quit_uzai(false), "danger"],
			["Abbrechen", func() -> void: pass],
		], "desktop")
		return
	var text := "Danach startet Uzai nur mit Maus oder Tastatur."
	if full and Helper.wake_active():
		text = "Beendet auch den Hintergrund. Danach startet Uzai nur mit Maus oder Tastatur."
	open_dialog("Uzai ganz beenden?" if full else "Uzai beenden?", game + text, [
		["Beenden", func() -> void: _quit_uzai(false), "danger"],
		["Abbrechen", func() -> void: pass],
	], "desktop")


# --- Profile (Roadmap 109) ----------------------------------------------------------------------

## „Wer spielt?“ beim Start: wartet auf die Wahl (mit PIN, wenn das Profil eine hat).
func _ask_profile() -> String:
	var l = ProfilePicker.new()
	l.main = self
	l.mode = "start"
	var res := [""]
	l.chosen.connect(func(id: String) -> void:
		res[0] = id
		if id != Config.profile_id:
			switch_profile(id)
	)
	open_layer(l)
	# Verschwindet die Auswahl, ohne dass gewählt wurde, geht es mit dem geladenen Profil weiter (sonst bliebe der
	# Start hier für immer stehen).
	while res[0] == "" and is_instance_valid(l):
		await get_tree().process_frame
	return res[0] if res[0] != "" else Config.profile_id


## Guide → Profil wechseln, Einstellungen → Konten: mode "switch" oder "manage".
func open_profiles(mode := "switch") -> void:
	if mode == "switch" and Launcher.in_game:
		Toasts.show_toast("Es läuft noch ein Spiel", "Erst das Spiel beenden, dann das Profil wechseln.", "warning")
		return
	var l = ProfilePicker.new()
	l.main = self
	l.mode = mode
	l.chosen.connect(func(id: String) -> void:
		if id != Config.profile_id:
			switch_profile(id)
	)
	open_layer(l)


## In ein anderes Profil wechseln: Uzai startet mit --profil=<id> neu. So kommt jedes Profil mit
## seinen eigenen Anmeldungen, Diensten und Daten hoch – nichts vom vorigen bleibt im Speicher.
## Die Auswahl hat schon zur Mitte geblendet; das neue Uzai begrüßt an derselben Stelle.
func switch_profile(id: String) -> void:
	if id == Config.profile_id or _closing or _profile_by_id(id).is_empty():
		return
	# Ein laufendes Spiel beendet Uzai nie von sich aus (ungespeicherter Fortschritt).
	if Launcher.in_game:
		Toasts.show_toast("Es läuft noch ein Spiel", "Erst das Spiel beenden, dann das Profil wechseln.", "warning")
		return
	Library.save()
	Config.save_settings()
	Config.profiles["last"] = id
	Config.save_profiles()
	# Proben (tests/probe_*.gd) starten nichts neu.
	if Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--uzai-script=")):
		print("Profilwechsel zu ", id)
		return
	Helper.wake_started = true
	var user := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool:
		return not (a.begins_with("--nach-neustart=") or a.begins_with("--launch=") or a.begins_with("--profil=") or a in ["--sicherer-modus", "--profilwechsel"]))
	var args := Array(OS.get_cmdline_args())
	args.append("--")
	args.append_array(user)
	args.append("--profil=" + id)
	args.append("--profilwechsel")
	args.append("--nach-neustart=%d" % OS.get_process_id())
	_uzai_starten(args)
	_closing = true
	_quit_failsafe()
	get_tree().quit()


func _profile_by_id(id: String) -> Dictionary:
	for p in Config.profile_list():
		if str(p.id) == id:
			return p
	return {}


var _kid_sig := ""


## Was am aktiven Profil die Oberfläche ändert: Name, Bild, Farbe, Kinderprofil und Regeln.
func _profile_sig() -> String:
	var p := Config.profile()
	return "%s|%s|%s|%s|%s|%d" % [p.get("name", ""), p.get("avatar", ""), p.get("color", ""), Config.is_kid(), JSON.stringify(p.get("rules", {})),
			Config.profile_list().size()]


func _on_profiles_changed() -> void:
	var sig := _profile_sig()
	if sig == _kid_sig:
		return
	var kid_before := _kid_sig.get_slice("|", 3) + _kid_sig.get_slice("|", 4)
	_kid_sig = sig
	if is_instance_valid(avatar_box):
		avatar_box.set_meta("url", "-")
		_update_status()
	# Kinderprofil an/aus oder neue Regeln: sichtbare Spiele sofort, die Bereiche (Shop) neu,
	# sobald keine Ebene mehr offen ist (der Neuaufbau nähme sie sonst mit).
	if kid_before != sig.get_slice("|", 3) + sig.get_slice("|", 4):
		Library.forget_visible()
		Library.changed.emit()
		_kid_rebuild_due = true


var _kid_rebuild_due := false


## Dienste gestaffelt starten (jeder kostet ein paar Millisekunden und löst Neuaufbauten aus),
## den Bibliotheks-Scan 2 s nach dem Ausblenden der Startanimation. Mit Startanimation laufen die
## Dienste schon während der Animation an (_boot_services), sonst hier nach dem Ausblenden.
func _start_services() -> void:
	var tree := get_tree()
	if not _services_on:
		_services_on = true
		await tree.create_timer(0.6).timeout
		if Config.safe_mode:
			# Sicherer Modus: keine Dienste im Hintergrund, nichts vorbauen.
			return
		Social.start()
		await tree.create_timer(0.2).timeout
		Voice.start()
		await tree.create_timer(0.2).timeout
		Music.start()
		YouTube.start()
		Twitch.start()
		if Achievements.has_ra() or Achievements.has_steam():
			Achievements.refresh_overview()
		# Ohne Startanimation (Einstellung „aus“): die Bereiche jetzt auf der Startseite vorbauen,
		# solange dort niemand drückt. Nicht mit --no-boot (Proben, Tests) und nicht beim Start
		# über eine Verknüpfung (gleich ins Spiel).
		if not "--no-boot" in OS.get_cmdline_user_args() and Remote.startup_launch == "":
			_prebuild()
		await tree.create_timer(1.0).timeout
	else:
		await tree.create_timer(2.0).timeout
	# In beiden Zweigen: Mit Startanimation (Standard) liefen die Dienste schon in _boot_services, und der Updater
	# entstand früher nur im ersten Zweig – im normalen Start also nie.
	if updater == null and not Config.safe_mode:
		updater = load("res://src/core/updater.gd").new()
		updater.name = "Updater"
		add_child(updater)
		updater.spaeter_pruefen()
	if Config.get_value("library.scan_on_start", true) and not Library.demo:
		Library.scan()
	await tree.create_timer(2.0).timeout
	_preload_rare()


var _services_on := false
## Selbst-Update über die GitHub-Releases (src/core/updater.gd); null bis die Dienste laufen und im Sicheren Modus.
var updater: Node = null


## Dienste während der Startanimation starten: Was Freunde, Musik, Videos und Profil zeigen, ist
## so beim ersten Wechsel schon da. Je ein Dienst pro Bild, aber nur in den ruhigen Momenten der
## Animation (Boot.calm: die dunkle Standby-Phase vor dem Anspringen der LED und wenn der Name
## steht) – früher fielen Social, Voice und Musik nach festen 0,2/0,35/0,5 s genau auf das Anspringen
## des Punkts und das Fließen des Lichts und ließen den Start ruckeln. Danach lädt jeder Bereich
## seine Daten vor und baut sich unsichtbar auf (_prebuild).
func _boot_services() -> void:
	_services_on = true
	await _boot_ruhig()
	Social.start()
	await _boot_ruhig()
	Voice.start()
	await _boot_ruhig()
	Music.start()
	await _boot_ruhig()
	YouTube.start()
	Twitch.start()
	await _boot_ruhig()
	# Profil: lädt achievements_view.prefetch (dieselben Bedingungen wie bisher hier), ist der
	# Bereich ausgeblendet, hier.
	if not sections.has("achievements") and (Achievements.has_ra() or Achievements.has_steam()):
		Achievements.refresh_overview()
	_prebuild()


## Ein Bild warten und, solange die Startanimation läuft, bis sie in einem ruhigen Moment ist
## (Boot.calm). Ohne Animation: nur das eine Bild.
func _boot_ruhig() -> void:
	var tree := get_tree()
	await tree.process_frame
	while is_instance_valid(_boot) and not _boot.calm() and not _boot.is_queued_for_deletion():
		await tree.process_frame


# --- Bereiche vorbauen ------------------------------------------------------------------------
# Früher baute sich jeder Bereich erst beim ersten Betreten auf und fing dann an zu laden: Beim
# ersten Durchblättern mit LT/RT stand überall „wird geladen“. Jetzt stößt jeder Bereich während
# der Startanimation seine Abrufe an (prefetch, je Bild einer, die Abrufe laufen parallel) und
# baut sich unsichtbar auf, sobald seine Daten da sind (prebuild). Ein Aufbau kostet je nach
# Bereich einige Millisekunden bis zu einem Bild: höchstens einer je Bild, mit zwei Bildern Pause
# und nur im ruhigen Teil der Animation (Boot.calm). Was dort nicht fertig wird (Daten kamen
# spät, Daten änderten sich), folgt auf der Startseite – nie während des Ausblendens, nur wenn
# eine Weile niemand drückt und höchstens PRE_WINDOW_MS lang. Wer die Startseite verlässt, beendet
# das Vorbauen; die übrigen Bereiche bauen beim Betreten wie bisher. Die Startseite selbst
# (Spiele) wird nie vorgebaut, ausgeblendete Bereiche gibt es gar nicht erst.

const PRE_WINDOW_MS := 20000     ## so lange nach der Startanimation darf noch nachgebaut werden
const PRE_IDLE_MS := 900         ## auf der Startseite nur, wenn so lange niemand gedrückt hat
const PRE_TRIES := 3             ## höchstens so oft je Bereich (Daten, die sich dauernd ändern)
var _pre_gen := 0
var _boot_end_ms := -1
var _last_input_ms := 0


func _prebuild() -> void:
	_pre_gen += 1
	var gen := _pre_gen
	var home := current
	var tree := get_tree()
	var todo := _prebuild_order(home)
	# Leichter Modus: nur die Nachbarn vorbauen (weniger Speicher und Arbeit beim Start).
	if Leicht.active:
		todo = todo.slice(0, Leicht.PREBUILD_MAX)
	# 1) Daten anstoßen (während der Startanimation nur in ihren ruhigen Momenten).
	for sid in todo:
		await _boot_ruhig()
		if not _pre_alive(gen, home):
			return
		var s = sections.get(sid)
		if s != null and is_instance_valid(s) and not s.visible:
			s.prefetch()
	# 2) Unsichtbar aufbauen.
	var tries := {}
	while _pre_alive(gen, home):
		await tree.process_frame
		if not _pre_alive(gen, home):
			return
		if _boot_end_ms >= 0 and Time.get_ticks_msec() - _boot_end_ms > PRE_WINDOW_MS:
			return
		if not _pre_moment():
			continue
		var pick = null
		var waiting := false
		for sid in todo:
			var s = sections.get(sid)
			if s == null or not is_instance_valid(s) or s.visible or s.prebuilt_fresh():
				continue
			if int(tries.get(sid, 0)) >= PRE_TRIES:
				continue
			if not s.data_ready():
				waiting = true
				continue
			tries[sid] = int(tries.get(sid, 0)) + 1
			pick = s
			break
		if pick == null:
			if not waiting:
				# Alles steht. Ändert sich danach etwas, baut goto beim Betreten wie bisher.
				return
			continue
		pick.prebuild()
		# Luft für die Animation bzw. die Startseite.
		await tree.process_frame
		await tree.process_frame


## Ruht die Auswahl länger in irgendeinem Bereich (Vorladen.REST_MS), baut sich einer der beiden
## Nachbarn (LT/RT) unsichtbar auf, wenn er sich seit seinem letzten Aufbau geändert hat bzw. beim
## Betreten ohnehin neu bauen würde – der Aufbau fällt dann in die Ruhe statt in den Wechsel. Einer
## je Ruhepunkt; nicht die Startseite (Spiele), nie mit offener Ebene, im Spiel oder beim Start.
func prebuild_neighbors() -> void:
	if not _started or Config.safe_mode or Nav.top_layer() != null or Launcher.in_game or _launching or is_instance_valid(_boot):
		return
	var home := top_of(current)
	var h := order.find(home)
	if h < 0 or order.size() < 2:
		return
	for sid in [order[(h + 1) % order.size()], order[(h - 1 + order.size()) % order.size()]]:
		var s = sections.get(sid)
		if sid == home or sid == "games" or s == null or not is_instance_valid(s) or s.visible:
			continue
		if s.prebuilt_fresh() or not s.needs_build() or not s.data_ready():
			continue
		s.prebuild()
		return


## Nachbarn der Startseite zuerst (RT und LT führen dorthin), dann weiter außen.
func _prebuild_order(home: String) -> Array:
	var out: Array = []
	var n := order.size()
	var h := order.find(home)
	if h < 0:
		return out
	for d in range(1, n):
		for sid in [order[(h + d) % n], order[(h - d + n) % n]]:
			if sid != home and sid != "games" and not out.has(sid):
				out.append(sid)
				# Ordner „Meine Apps“: dann auch die Apps darin.
				if sid == LeisteOben.FOLDER:
					out.append_array(folder_kids)
	return out


func _pre_alive(gen: int, home: String) -> bool:
	return gen == _pre_gen and is_inside_tree() and current == home and sections.has(home) \
		and not Launcher.in_game and not _launching


## Darf in diesem Bild ein Bereich aufgebaut werden?
func _pre_moment() -> bool:
	if Nav.top_layer() != null:
		return false
	if is_instance_valid(_boot):
		return _boot.calm()
	if _boot_end_ms < 0:
		# Ohne Startanimation: _boot_end_ms setzt _after_boot.
		return false
	var now := Time.get_ticks_msec()
	# Nicht während des Ausblenden (0,5 s) und nicht, solange jemand auf der Startseite drückt.
	return now - _boot_end_ms > 900 and now - _last_input_ms > PRE_IDLE_MS


## Ein altes Uzai hält den Anschluss, antwortet aber nicht (Remote.hung_pid): fragen, ob es weg
## soll. Sonst laufen zwei, und Verknüpfungen landen beim hängenden.
func _ask_hung() -> void:
	if not await Remote.hung_is_uzai():
		Remote.hung_pid = 0
		return
	var box := { "done": false }
	var l := open_dialog("Uzai hängt im Hintergrund",
			"Ein älteres Uzai reagiert nicht. Beenden? Ungespeichertes geht verloren.", [
		["Altes Uzai beenden", func() -> void:
			box.done = true
			if await Remote.end_hung():
				Toasts.show_toast("Altes Uzai beendet", "Dieses Uzai hat übernommen.", "check", { "sound": "select" })],
		["Dieses Uzai schließen", func() -> void: _quit_uzai(false)],
	], "warning", "warn")
	l.closed.connect(func() -> void: box.done = true)
	while not bool(box.done):
		await get_tree().process_frame


## Nach einem unerwarteten Ende (src/core/crash_guard.gd): sagen, was war, und anbieten, was
## hilft. Über eine Verknüpfung gestartet (gleich ins Spiel) nur als Mitteilung.
func _after_crash() -> void:
	var c: Dictionary = Config.last_crash
	if not c.is_empty() and Helper.AFTER_CRASH in OS.get_cmdline_user_args():
		# Der Helfer hat Uzai gleich wieder gestartet: dorthin zurück, wo es war.
		var w := str(c.get("where", ""))
		if (sections.has(w) or w == "media") and w != current:
			goto(w)
		Toasts.show_toast("Uzai lief kurz nicht", "Neu gestartet.", "warning",
				{ "ms": 7000 })
		return
	if c.is_empty() or Remote.startup_launch != "":
		if Config.safe_mode:
			Toasts.show_toast("Sicherer Modus", "Normal neu starten: Einstellungen → System.", "warning", { "ms": 7000 })
		elif not c.is_empty():
			Toasts.show_toast("Uzai wurde unerwartet beendet", "Fehlerbericht: Einstellungen → System.", "warning", { "ms": 7000 })
		return
	var where := where_name(str(c.get("where", "")))
	var buttons: Array
	var head := "Uzai wurde unerwartet beendet"
	var text := "Uzai wurde zuletzt unerwartet beendet%s." % ((" (" + where + ")") if where != "" else "")
	if Config.safe_mode:
		head = "Sicherer Modus"
		text = "Zweimal unerwartet beendet. Uzai läuft im Sicheren Modus."
		buttons = [
			["Im Sicheren Modus bleiben", func() -> void: pass],
			["Fehlerbericht", func() -> void: open_crash_report()],
			["Normal neu starten", func() -> void: restart_uzai()],
		]
	else:
		buttons = [
			["Weiter", func() -> void: pass],
			["Fehlerbericht", func() -> void: open_crash_report()],
			["Im Sicheren Modus neu starten", func() -> void: restart_uzai(true)],
		]
	var box := { "done": false }
	var l := open_dialog(head, text, buttons, "warning", "warn")
	l.closed.connect(func() -> void: box.done = true)
	while not bool(box.done):
		await get_tree().process_frame


## Lesbarer Ort für Hinweis und Bericht („im Spiel“, „in Filme“).
func where_name(w: String) -> String:
	if w == "spiel":
		return "im Spiel"
	var s = sections.get(w)
	if s != null and is_instance_valid(s) and str(s.title) != "":
		return "in " + str(s.title)
	return ""


## Uzai-Doktor (Punkt 133): alle bekannten Probleme als Karten mit „Beheben“.
func open_doktor() -> Control:
	return load("res://src/ui/layers/doktor.gd").open_for(self)


## Ist etwas Wichtiges kaputt, einmal ein leiser Hinweis auf der Startseite (abschaltbar unter
## Einstellungen → System bzw. im Doktor) – nie zweimal wegen derselben Sache, nie über einer
## Ebene oder im Spiel. Die Ansicht-Taste öffnet den Doktor.
func _doktor_hint(wait := DOKTOR_HINT_S) -> bool:
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	if Launcher.in_game or Nav.top_layer() != null or not is_inside_tree():
		return false
	var cards := Doktor.cards(DoktorLage.gather())
	var sig := Doktor.hint_sig(cards, bool(Config.get_value("system.doktor_hint", true)), str(Config.get_value("system.doktor_seen", "")))
	if sig == "":
		return false
	Config.set_value("system.doktor_seen", sig)
	var top: Dictionary = cards[0]
	var n := int(Doktor.summary(cards).wichtig)
	var sub := str(top.title) if n == 1 else "%s – und %s" % [tr(str(top.title)), tr("1 weiteres Problem") if n == 2 else tr("%d weitere Probleme") % (n - 1)]
	Toasts.show_toast("Uzai-Doktor", sub, "warning", { "open": open_doktor, "open_text": "Ansehen", "go": open_doktor, "go_text": "Uzai-Doktor", "ms": 9000 })
	return true


## Fehlerbericht als GitHub-Meldung zum Abschicken mit dem Handy (src/ui/layers/crash_report.gd).
func open_crash_report() -> void:
	open_layer(load("res://src/ui/layers/crash_report.gd").new())


## Grafik „Kompatibel“ (Einstellungen › System): Läuft Uzai noch mit Forward+, startet es einmal
## sofort neu mit dem einfachen Renderer – für PCs, auf denen Vulkan Fehler macht (etwa schwarze
## Flächen bei durchsichtigen Pop-ups über Spielen). Nur einmal: --rendering-method steht dann dabei.
func _grafik_umschalten() -> bool:
	if str(Config.get_value("system.grafik", "realistisch")) != "kompatibel":
		return false
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or "--rendering-method" in OS.get_cmdline_args():
		return false
	Helper.wake_started = true
	_uzai_starten(neustart_args())
	get_tree().quit()
	return true


## Startparameter für ein neues Uzai: ohne Einmal-Angaben, mit der gewählten Grafik.
func neustart_args(safe := false) -> Array:
	var user := Array(OS.get_cmdline_user_args()).filter(
			func(a: String) -> bool: return not a.begins_with("--nach-neustart=") and not a.begins_with(
			"--launch=") and a != "--sicherer-modus" and a != "--profilwechsel")
	var args: Array = []
	var skip := false
	# Der Bildschirm kommt aus der Einstellung (bildschirm.gd), die Grafik ebenso.
	for a in Bildschirm.mit_schirm(Array(OS.get_cmdline_args()), Config.get_value("display.screen", Bildschirm.AUTO), DisplayServer.get_screen_count()):
		if skip:
			skip = false
			continue
		if a == "--rendering-method":
			skip = true
			continue
		args.append(a)
	if str(Config.get_value("system.grafik", "realistisch")) == "kompatibel":
		args.append_array(["--rendering-method", "gl_compatibility"])
	args.append("--")
	args.append_array(user)
	if safe:
		args.append("--sicherer-modus")
	args.append("--nach-neustart=%d" % OS.get_process_id())
	return args


## Ein neues Uzai aus diesem heraus starten. Rechnet dieses auf jedem Bildschirm scharf (bildschirm.gd),
## tut es das neue gleich auch – sonst müsste es sich dafür ein zweites Mal selbst starten.
func _uzai_starten(args: Array) -> void:
	Bildschirm.vor_neustart(Bildschirm.eigen and bool(Config.get_value("display.dpi_eigen", true)))
	OS.create_process(OS.get_executable_path(), PackedStringArray(args))
	Bildschirm.nach_neustart()


## Uzai neu starten (etwa nach „Sicherung zurückholen“). Das neue Uzai wartet, bis dieses ganz
## zu ist (Config: --nach-neustart), sonst hielte es dieses für das laufende und gäbe nur weiter.
## safe: im Sicheren Modus (src/core/crash_guard.gd), sonst normal.
func restart_uzai(safe := false) -> void:
	if Launcher.in_game:
		await Launcher.quit_game()
	Library.save()
	Config.save_settings()
	# Kein Wächter für die Guide-Taste: es kommt gleich ein neues Uzai.
	Helper.wake_started = true
	_uzai_starten(neustart_args(safe))
	_closing = true
	_quit_failsafe()
	await power_off("quit")
	get_tree().quit()


## keep_ready: mit „Nach dem Schließen im Hintergrund bereit“ den Wächter für die Guide-Taste starten.
func _quit_uzai(keep_ready := true) -> void:
	if Launcher.in_game:
		await Launcher.quit_game()
	Library.save()
	Config.save_settings()
	# Der Wächter startet vor der Animation (er wartet selbst, bis Uzai weg ist) – so auch dann,
	# wenn das Ausschalten abgekürzt oder von Windows beendet wird.
	if keep_ready:
		Helper.start_wake_watch()
	else:
		# Ganz beenden: kein Wächter, auch nicht über ein Schließen-Signal von Windows danach.
		Helper.wake_started = true
	_closing = true
	_quit_failsafe()
	await power_off("quit_full" if not keep_ready else "quit")
	get_tree().quit()


# --- Leichter Modus, Bildschirm und Spielende ----------------------------------------------------

## Uzais Fenster ohne Windows-Animation beim Minimieren und Wiederherstellen (Guide über dem
## Spiel, Spielende): sonst „zoomt“ ein Bild aus der Taskleiste über das Spiel.
func _no_window_animations() -> void:
	if Config.is_windows():
		Helper.run("no-anim", { "hwnd": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE) })
		# Den Vorhang (UzEbenen) schon jetzt übersetzen lassen, nicht erst beim ersten Spielstart.
		get_tree().create_timer(5.0).timeout.connect(func() -> void: Helper.run("vorhang", Vorhang.auftrag("", 0), 20.0))
		# Ebenso den Ton-Teil (UzAudio) für den Fernseher im Zimmer: Übersetzt erst beim Spielstart, hielt
		# er den schnellen Weg 1–2 s auf (helper.log „window-state/raum-ton nach 2.0 s ohne Antwort“).
		# „aus“ ohne gemerkte Werte tut nichts.
		get_tree().create_timer(9.0).timeout.connect(func() -> void: Helper.run("raum-ton", { "aus": true }, 20.0))


func _on_input_seen() -> void:
	_last_input_ms = Time.get_ticks_msec()
	if Leicht.idle:
		Leicht.idle = false
		if not OS.low_processor_usage_mode:
			Engine.max_fps = _menu_fps()
			Bildrate.gesetzt()


## Jede Sekunde: Im leichten Modus ruht das Menü nach Leicht.IDLE_MS ohne Eingabe mit halber Rate
## (nichts bewegt sich dort von selbst; eine Taste holt die volle Rate sofort zurück). Läuft ein
## Video oder Spiel, nie. Bei „Automatisch“ schaut Uzai einmal je Minute, ob es ihn vorschlägt.
var _light_checks := 0


func _light_tick() -> void:
	if Leicht.active and not Leicht.idle and not OS.low_processor_usage_mode and not Launcher.in_game and not _launching \
			and not Video.active and Time.get_ticks_msec() - _last_input_ms >= Leicht.IDLE_MS:
		Leicht.idle = true
		Engine.max_fps = _menu_fps()
		Bildrate.gesetzt()
	_light_checks += 1
	if _light_checks % 60 == 0:
		_light_check()


## Leichter Modus vorschlagen: einmal, nur bei „Automatisch“, und nur mit einem ehrlichen Grund
## (Software-Grafik oder ein Menü, das hier messbar ruckelt – src/core/leicht.gd). Nie in der Demo.
func _light_check() -> void:
	var setting := str(Config.get_value("display.light", "auto"))
	if Library.demo or setting != "auto" or bool(Config.get_value("display.light_asked", false)):
		return
	var menu: Dictionary = perf.menu_stats()
	var why := Leicht.reasons(Leicht.device(), menu)
	if Leicht.should_suggest(setting, false, why):
		suggest_light(why, menu)


## Die ruhige Mitteilung mit dem Vorschlag (A führt zur Einstellung; sonst geschieht nichts).
func suggest_light(why: Array, menu: Dictionary) -> void:
	Config.set_value("display.light_asked", true)
	var to_row := func() -> void: open_setting("aussehen", "set:aussehen:Mehr:Leichter Modus", "Mehr")
	Toasts.show_toast("Leichter Modus?", Leicht.reason_text(why, menu), "speed",
			{ "ms": 9000, "open": to_row, "open_text": "Ansehen", "go": to_row, "go_text": "Ansehen" })


## Den Bildschirm einmal erkennen (src/core/display_fit.gd). Bei neuen Nutzern stellt das die
## Größe der Oberfläche passend ein; bei allen anderen merkt es sich nur, was es gesehen hat
## (Einstellungen → Aussehen) – ein Update verstellt nichts.
func _fit_display(fresh: bool) -> void:
	if not Helper.available:
		await Helper.helper_ready
	var seen: Dictionary = await DisplayFit.detect(get_window())
	Config.set_value("display.fitted", true)
	if not fresh:
		Config.set_value("display.seen", seen)
		_schirm_merken()
		return
	var kind := DisplayFit.apply(seen, true)
	_schirm_merken()
	if kind != "":
		Toasts.show_toast(DisplayFit.KIND_DONE[kind], "Oberfläche %d %% (Einstellungen → Aussehen)." % roundi(UzTheme.ui_scale() * 100.0),
				"tv", { "ms": 7000 })


## Handheld: die Energieprofile fürs Schnellmenü („Leistung“) gleich bereithalten.
func _leistung_laden() -> void:
	if not Helper.available and not Library.demo:
		await Helper.helper_ready
	await preload("res://src/ui/components/guide_quick.gd").plaene_laden()


func _on_game_failed(g: Dictionary, reason: String) -> void:
	Nav.game_mode = false
	_cover("start", false)
	_vorhang("")
	if _tv != "":
		_tv = Fernsehspiel.weiter(_tv, "ende")
		_tv_melden()
	if _ingame and is_instance_valid(_ingame):
		_ingame.queue_free()
	_ingame = null
	# Aus dem Zimmer gestartet: zurück ins Zimmer (die Meldung kommt darüber).
	if has_meta("zimmer_zurueck"):
		remove_meta("zimmer_zurueck")
		open_room(true)
	# Leerer Grund: bewusst abgebrochen (z. B. Adminrechte), keine Fehlermeldung.
	if reason == "":
		return
	Sfx.play("error")
	if Launcher.is_app(g):
		open_dialog("%s startet nicht" % g.get("title", "Die App"), reason, [["OK", func() -> void: pass]], "warning", "warn")
		return
	# Der Weg in die Einstellungen hilft nur bei Emulator-Spielen (Emulator, Ordner, BIOS). Bei Steam,
	# Epic oder einem PC-Spiel führte der Knopf früher ebenfalls zu den Emulatoren.
	if str(g.get("source", "")) in ["rom", "disc"]:
		open_dialog("%s startet nicht" % g.get("title", "Das Spiel"), reason, [
			["Einstellungen öffnen", func() -> void: goto("settings", "emulation")],
			["Schließen", func() -> void: pass],
		], "warning", "warn")
		return
	open_dialog("%s startet nicht" % g.get("title", "Das Spiel"), reason, [["OK", func() -> void: pass]], "warning", "warn")


func _on_game_ended(g: Dictionary, secs: int) -> void:
	# Für „Gerade gespielt“ (vor dem Neuaufbau der Startseite unten): Zeitraum und Spielzeit davor/danach.
	var now := int(Time.get_unix_time_from_system())
	var cur := Library.get_game(str(g.get("id", "")))
	var tot := SessionSummary.totals(cur if not cur.is_empty() else g, secs)
	last_round = { "game_id": str(g.get("id", "")), "start": now - secs, "end": now, "secs": secs, "before": tot[0], "after": tot[1] }
	var app := Launcher.is_app(g)
	var summary := bool(Config.get_value("system.round_summary", true)) and secs >= SessionSummary.MIN_SECS and not app
	if app:
		last_round = {}
	Nav.game_mode = false
	_cover("start", false)
	guide_tod_melden(g)
	# Im Zimmer: Uzai liegt schon vorn. Sonst deckt der Vorhang die Rückkehr, bis Uzai gezeichnet hat und
	# vorn ist (meist hat die Wache ihn schon zugezogen); wartete das Zimmer hinter dem Spiel, fährt die
	# Kamera dann aus dem Fernseher (zimmer_ansehen.gd tv_wechsel).
	# Eigene App: Uzai lag als Kulisse dahinter und ist schon zu sehen – kein Vorhang dazwischen.
	var uzai_vorn := Fernsehspiel.uzai_vorn(_tv) or _kulisse
	if _tv != "":
		_tv = Fernsehspiel.weiter(_tv, "ende")
	vorhang_wache()
	if not uzai_vorn:
		await _vorhang("ende")
	discord_live = false
	_live_what = ""
	# Lag Discord fürs Übertragen vorn: Controller-Maus aus (Uzai kommt ohnehin zurück).
	if not _away_for_live.is_empty():
		_away_for_live = {}
		if mouse_on:
			set_mouse_mode(false)
	# Eigene App: die Controller-Maus (im Guide eingeschaltet) geht mit ihr aus.
	elif app and mouse_on:
		set_mouse_mode(false, false)
	set_idle(false)
	if _guide and is_instance_valid(_guide):
		_guide.close()
	# Im Zimmer-Fernseher aufgestanden: _leave_overlay kehrte früh zurück und setzte den Controller-Zwang nie zurück –
	# danach nahm Uzai den Controller auch ohne Fokus an (Tasten für ein anderes Fenster bedienten Uzai dahinter).
	if _overlay_pad_forced:
		_overlay_pad_forced = false
		Nav.pad_unfocused = false
	_overlay_mode = false
	_veil(false)
	_unpark()
	_restore_window()
	_tv_melden()
	if not uzai_vorn:
		_vorhang_nach_rueckkehr()
	# Der Ladebildschirm bleibt stehen, die Startseite baut sich darunter neu auf, dann blendet
	# er weich aus (vorher: harter Schnitt und ein Bild lang leeres „Für dich“).
	var ing := _ingame
	_ingame = null
	await get_tree().process_frame
	if current == "games":
		var s = sections["games"]
		s.build()
		_build_chips(s)
		s.focus_default()
	if ing and is_instance_valid(ing):
		await get_tree().process_frame
		# Spielstart-Karte: kurz „Zurück in Uzai“ über dem Bild des Spiels, dann ausblenden.
		if is_instance_valid(ing) and ing.has_method("returning"):
			await ing.returning()
		if is_instance_valid(ing):
			# Spielstart-Karte: Schrift zuerst, dann kreuzt die Karte mit der Startseite (gehen()) –
			# ihr großer Titel steht nie über dem der Startseite.
			if ing.has_method("gehen"):
				ing.call("gehen")
			else:
				var tw := U.kreuzen(ing, "uz_karte_weg")
				tw.tween_property(ing, "modulate:a", 0.0, U.T_WEG)
				tw.tween_callback(ing.queue_free)
	# Aus dem Zimmer gestartet: wieder dorthin.
	if has_meta("zimmer_zurueck"):
		remove_meta("zimmer_zurueck")
		open_room(true)
	if secs > 60 and not app:
		Toasts.show_toast(str(g.get("title", "")),
				"Diesmal %s · insgesamt %s" % [U.playtime(secs).replace(" gespielt", ""), U.playtime(int(tot[1])).replace(" gespielt", "")], "clock",
			{ "sound": "select", "go": open_round_summary if summary else open_game_note.bind(g), "go_text": "Zusammenfassung" if summary else "Zum Spiel" })
	if summary:
		_round_refresh(g)


## Eigene App starten (Store-App oder Programm, src/core/apps_extern.gd). Ein Programm fragt beim
## ersten Start nach, jede App nach dem Wiederherstellen einer Sicherung (die Bestätigung gilt nur
## für diesen PC). Läuft sie im Hintergrund (Zurück zu Uzai), kommt sie nur wieder nach vorn.
func start_app(id: String) -> void:
	var e := AppsExtern.get_entry(id)
	if e.is_empty() or not LeisteOben.extern_allowed() or Launcher.in_game or _launching:
		return
	if AppsExtern.needs_ask(e):
		var what := str(e.path) if str(e.kind) == "prog" else str(e.aumid)
		open_dialog("„%s“ starten?" % str(e.name), what, [
			["Starten", func() -> void:
				AppsExtern.confirm(e)
				launch(AppsExtern.launch_game(e)), ""],
			["Abbrechen", func() -> void: pass],
		], "desktop" if str(e.kind) == "prog" else "tv")
		return
	launch(AppsExtern.launch_game(e))


## Nach der Runde die Erfolgsliste des Spiels einmal neu holen (nur wenn es eine hat): Fortschritt
## in „Gerade gespielt“ und auf der Spielseite stimmt dann. Etwas später, damit Erfolge aus den
## letzten Sekunden schon gemeldet sind.
func _round_refresh(g: Dictionary) -> void:
	await get_tree().create_timer(20.0).timeout
	var res := Achievements.cached(g)
	if not Launcher.in_game and not res.is_empty() and int(res.get("total", 0)) > 0:
		Achievements.for_game(g, true)


## Zusammenfassung der letzten Runde (Karte „Gerade gespielt“, Mitteilung nach dem Spiel).
func open_round_summary() -> void:
	var g := Library.get_game(str(last_round.get("game_id", "")))
	if g.is_empty() or Launcher.in_game:
		return
	var l = _rare("round_summary").new()
	l.game = g
	l.data = SessionSummary.make(last_round, Unlocks.history(SessionSummary.UNLOCKS_N), Unlocks.game_key(g), str(g.get("source", "")) == "rom",
		Capture.for_game(g), Achievements.cached(g))
	open_layer(l)


## Absturz oder Fehlstart erkannt (Launcher.crashed, src/core/trouble.gd): was Uzai gesehen hat,
## ehrliche Tipps je Quelle, „Neu starten“ und – wo es passt – ein Knopf, der hilft.
func _on_game_crashed(g: Dictionary, v: Dictionary) -> void:
	# Erst die Rückkehr nach Uzai zu Ende ausblenden lassen.
	await get_tree().create_timer(0.6).timeout
	if Launcher.in_game or _launching:
		return
	var game := Library.get_game(str(g.get("id", "")))
	if game.is_empty():
		game = g
	var tips := Trouble.tips(game, v)
	# Mehrzeilig: Zeile für Zeile übersetzen (die Übersetzung nimmt sonst nur ganze Texte).
	var lines := PackedStringArray()
	for t in tips.lines:
		lines.append("•  " + tr(str(t)))
	var buttons: Array = [["Neu starten", func() -> void: launch(game)]]
	for a in tips.actions:
		buttons.append([str(a[0]), _trouble_action.bind(str(a[1]), game)])
	buttons.append(["Schließen", func() -> void: pass])
	Sfx.play("error")
	open_dialog(Trouble.headline(Library.display_title(game), v), tr(Trouble.what_happened(v)) + "\n\n" + "\n".join(lines), buttons, "warning", "warn")


func _trouble_action(id: String, g: Dictionary) -> void:
	match id:
		"validate":
			# Steam zeigt dabei ein eigenes Fenster: Uzai bleibt davor, die Prüfung läuft dahinter.
			Toasts.show_toast("Steam prüft die Spieldateien", "Läuft im Hintergrund. Danach neu starten.", "steam",
					{ "ms": 7000 })
			if Library.demo:
				return
			_cover("validate", true)
			OS.shell_open("steam://validate/%d" % int(g.get("appid", 0)))
			await get_tree().create_timer(6.0).timeout
			_cover("validate", false)
			bring_to_front()
		"options":
			open_game_options(g)
		"emulator":
			await goto("settings", "emulation")
			var sv = sections.get("settings")
			if sv and sv.has_method("open_emulator"):
				sv.open_emulator(str(g.get("emulator", Config.system(str(g.get("system", ""))).get("emulator", ""))))


# --- Videos ----------------------------------------------------------------------

func open_video(list: Array, idx := 0, opts := {}) -> void:
	if Launcher.in_game:
		Toasts.show_toast("Erst das Spiel beenden", "Videos laufen, wenn kein Spiel offen ist.", "video")
		return
	if not YouTube.tools_ready():
		goto("videos", "fuerdich")
		if not Config.is_windows() or YouTube.setting_up:
			var tw_list := not list.is_empty() and str((list[0] as Dictionary).get("id", "")).begins_with("tw:")
			Toasts.show_toast("Der Player wird eingerichtet" if YouTube.setting_up else ("Der Player ist noch nicht eingerichtet" if tw_list
				else "YouTube ist noch nicht eingerichtet"), "" if YouTube.setting_up else ("Einrichten unter Videos." if tw_list
				else "Unter Videos „Jetzt einrichten“ wählen."), "video")
			return
		# Erster Start auf einem frischen PC: gleich einrichten (geprüfte Downloads, Punkt 74) statt
		# nur darauf hinzuweisen – danach startet das Video auf Knopfdruck.
		Toasts.show_toast("Der Player wird eingerichtet", "yt-dlp und mpv, etwa 150 MB.", "download", { "ms": 5000 })
		var err := await YouTube.setup_tools()
		var again := func() -> void: open_video(list, idx, opts)
		Toasts.show_toast("Player ist bereit" if err == "" else "Einrichten nicht ganz geklappt", "Video starten." if err == "" else err,
			"video" if err == "" else "warning", { "ms": 9000, "sound": "select" if err == "" else "error", "open": again,
			"open_text": "Abspielen" if err == "" else "Erneut versuchen", "go": again, "go_text": "Abspielen" if err == "" else "Erneut versuchen" })
		return
	if list.is_empty():
		return
	# Picture-in-picture is running: same video → just go full size again; a different one → close the
	# small window first and start the new video fresh in fullscreen. Otherwise the new video would take
	# over the small corner and the player would never go full size. close() waits until mpv has exited;
	# otherwise the new video would load into the exiting mpv and both would close.
	if pip != null and pip.active():
		var same := Video.active and str(Video.video.get("id", "")) != "" \
				and str(Video.video.get("id", "")) == str((list[clampi(idx, 0, list.size() - 1)] as Dictionary).get("id", ""))
		if same:
			pip.leave()
			return
		await pip.close()
	opts = opts.duplicate()
	opts["pip"] = false
	# Die gewählte Karte merken: Ihr Bild fliegt gleich in den Player (src/ui/flug.gd), auch wenn
	# vorher noch Ebenen zugehen.
	Flug.merke(Nav.focused())
	await alle_ebenen_zu()
	Sfx.play("open")
	_player = _rare("video_player").new()
	_player.main = self
	Video.play(list, idx, opts)
	open_layer(_player)
	video_mode_changed()


## Fenster passend zum Video: durchsichtig über mpv, bei „Nur Ton“ normal. Läuft nur der Ton im
## Hintergrund, ist Uzai ganz normal zu sehen.
func video_mode_changed() -> void:
	var on := Video.active and not Video.background
	if not Config.is_windows() or Video.sim:
		_oberflaeche_unter_video(on, true)
		background.visible = not on or Video.sim
		return
	var want := on and not Video.audio_only
	_oberflaeche_unter_video(on, false)
	if want == _video_overlay:
		return
	_video_overlay = want
	# Ausweichmodus „Video vorn“: mpv liegt obenauf und zeigt seine eigene, schlichte Anzeige.
	# Uzai bleibt dahinter, behält aber die Eingaben und steuert mpv weiter.
	see_through(want and not Video.front_mode())
	Nav.pad_unfocused = want and Video.front_mode()
	background.visible = not want
	if want:
		# mpv öffnet sein Fenster gleich darunter und holt sich kurz den Fokus: zurückholen.
		for i in 3:
			await get_tree().create_timer(0.9).timeout
			if not _video_overlay:
				return
			Helper.run("focus", { "pid": OS.get_process_id() })


## Die Oberfläche unter dem Player: Sie geht nicht in einem Bild (ein Loch, bis der Player deckt),
## sondern kreuzt mit ihm – ohne mpv dahinter (Vorführung), sobald der Player zu kommen beginnt
## (beim Flug erst, wenn das Bild fast da ist); unter Windows liegt mpv dahinter, dann geht sie
## gleich. Danach ist sie unsichtbar.
func _oberflaeche_unter_video(on: bool, deckt: bool) -> void:
	if not on:
		U.stop(shell, "uz_shell")
		if int(shell.get_meta("uz_hidden_by", 0)) == 0:
			shell.modulate.a = 1.0
		shell.visible = true
		return
	if not shell.visible or shell.has_meta("uz_video_weg"):
		return
	shell.set_meta("uz_video_weg", true)
	if deckt:
		# Bis der Player zu kommen beginnt (Flug: wenn das Bild fast da ist), höchstens 0,5 s.
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 500 and is_instance_valid(_player) and _player.modulate.a < 0.05:
			await get_tree().process_frame
	shell.remove_meta("uz_video_weg")
	if not (Video.active and not Video.background):
		return
	var tw := U.kreuzen(shell, "uz_shell")
	tw.tween_property(shell, "modulate:a", 0.0, U.T_WEG).set_delay(U.NACH_WEG)
	tw.tween_callback(func() -> void:
		if Video.active and not Video.background:
			shell.visible = false
	)


## Nur Ton im Hintergrund (Player → ≡ oder Optionen): der Player geht zu, der Ton läuft weiter,
## Uzai steht wieder dort, wo du vor dem Video warst. Gesteuert wird im Guide (Reiter „Video-Ton“).
func video_to_background() -> void:
	on_video_closed()
	_update_status()
	Toasts.show_toast("Läuft im Hintergrund weiter", "Nur Ton – steuern im Guide unter „Video-Ton“.", "music", { "ms": 3500 })


## Video gleich als Ton im Hintergrund starten (Optionen eines Videos), ohne den Player zu öffnen.
func play_in_background(list: Array, idx := 0) -> void:
	if Launcher.in_game:
		Toasts.show_toast("Erst das Spiel beenden", "Videos laufen, wenn kein Spiel offen ist.", "video")
		return
	if not YouTube.tools_ready() or list.is_empty():
		Toasts.show_toast("YouTube ist noch nicht eingerichtet", "Unter Videos „Jetzt einrichten“ wählen.", "video")
		return
	if Video.active and Video.pip and pip:
		await pip.close()
	Video.play(list, idx, { "audio": true, "background": true })
	_update_status()
	Toasts.show_toast("Läuft im Hintergrund", "Nur Ton – steuern im Guide unter „Video-Ton“.", "music", { "ms": 3500 })


## Video-Ton im Hintergrund wieder groß im Player (Guide → „Mit Bild“). with_picture: Bild an.
func resume_player(with_picture := false) -> void:
	if not Video.active or not Video.background or is_instance_valid(_player) or Launcher.in_game:
		return
	await alle_ebenen_zu()
	Video.background = false
	if with_picture:
		Video.set_quality(str(Config.get_value("youtube.quality", "1080")))
	Sfx.play("open")
	_player = _rare("video_player").new()
	_player.main = self
	open_layer(_player)
	video_mode_changed()
	_update_status()


## Video vorn: Menüs über dem Video (Optionen, Guide, Dialoge) brauchen Uzai obenauf; danach liegt
## es wieder vorn. Optionen und Dialoge halten es solange an; der Guide nicht – das Video läuft
## dahinter weiter, angehalten wird nur ausdrücklich (Guide › Video › Pause).
var _menu_over_video := false
var _paused_for_menu := false


func _process(_dt: float) -> void:
	if not _video_overlay or not Video.active or Video.sim or not Video.front_mode():
		if _menu_over_video:
			_cover("menu", false)
		_menu_over_video = false
		_paused_for_menu = false
		return
	var over: bool = is_instance_valid(_player) and Nav.top_layer() != _player
	if over == _menu_over_video:
		return
	_menu_over_video = over
	if over:
		var guide_auf := _guide != null and is_instance_valid(_guide)
		if not Video.paused and not guide_auf:
			_paused_for_menu = true
			Video.set_pause(true)
		_menu_over_video_on()
	else:
		_video_front_again()
		if _paused_for_menu:
			_paused_for_menu = false
			Video.set_pause(false)
		Video.osd("covered", [false])
		Video.osd("show", [3.0])


## Ein Menü kommt über das Video (mpv vorn): Das Video bleibt dahinter zu sehen (Uzai durchsichtig,
## mpvs Leiste weg – sonst stünden Titel und Balken hinter dem Guide), wie ein Spiel hinter dem Guide.
## Durchsichtig wird Uzai, solange mpv noch oben liegt; nach vorn kommt es erst mit einem fertig
## durchsichtigen Bild (sonst stand kurz Schwarz über dem Video).
func _menu_over_video_on() -> void:
	Video.osd("covered", [true])
	menue_durchsichtig(true)
	# Zwei fertige Bilder abwarten, höchstens 150 ms (zeichnet Uzai gerade nicht, wartet nichts ewig).
	var bilder := Engine.get_frames_drawn() + 2
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() < bilder and Time.get_ticks_msec() - t0 < 150:
		await get_tree().process_frame
	if not _menu_over_video:
		return
	# Uzai ganz nach oben, bevor mpv sein „immer oben“ abgibt: Ein Fenster, das „immer oben“
	# verlässt, landet über allen anderen – also wieder über Uzai. Dann blieb vom Guide
	# (Guide-Taste im Film) nur die Pause, der Guide selbst lag unsichtbar hinter dem Video.
	_cover("menu", true)
	Video.set_ontop(false)
	DisplayServer.window_move_to_foreground()
	_menu_focus()


## Menü über dem Video zu: mpv erst wieder nach oben, wenn der Helfer Uzai sicher nicht mehr anhebt
## (sonst landete Uzai zuletzt doch über mpv, und das Video lief unsichtbar dahinter weiter).
func _video_front_again() -> void:
	await _cover("menu", false)
	if not _menu_over_video and _video_overlay and Video.active and Video.front_mode():
		Video.set_ontop(true)
		# Undurchsichtig erst, wenn mpv sicher wieder darüber liegt (sonst kurz Schwarz über dem Video).
		await get_tree().create_timer(0.5).timeout
	if not _menu_over_video:
		menue_durchsichtig(false)


## Fokus für ein Menü über dem Video holen, auch wenn mpv ihn eben noch hatte (bis zu dreimal).
func _menu_focus() -> void:
	for i in 3:
		await Helper.run("focus", { "pid": OS.get_process_id() }, 3.0)
		await get_tree().create_timer(0.2).timeout
		if not _menu_over_video or get_window().has_focus():
			return


func on_video_closed() -> void:
	_player = null
	_video_gewichen = false
	_cover("menu", false)
	# Mit dem Video-Fenster endet auch Discords Übertragung.
	if _live_what == "video":
		discord_live = false
		_live_what = ""
	_video_overlay_off()
	_oberflaeche_unter_video(false, false)
	background.visible = true
	# Film aus einer Ebene gestartet (Quellenwahl): dorthin zurück, nicht in den Bereich.
	if _restore_under_player():
		return
	await get_tree().process_frame
	if sections.has(current):
		var s = sections[current]
		if current == "videos":
			s.build()
			_build_chips(s)
		s.focus_default()


func _video_overlay_off() -> void:
	if not _video_overlay:
		return
	_video_overlay = false
	Nav.pad_unfocused = false
	see_through(false)
	_restore_window()


## opts: wie bei open_video (Shorts: { shorts: true } – dann spielt „Abspielen“ sie nacheinander).
func open_video_options(v: Dictionary, list: Array = [], idx := 0, opts := {}) -> void:
	var l = VideoOptions.new()
	l.video = v
	l.list = list
	l.index = maxi(idx, 0)
	l.play_opts = opts
	open_layer(l)


func open_channel(channel_id: String, name_: String) -> void:
	var l = VideoGrid.new()
	l.heading = name_
	l.subheading = "Kanal"
	l.channel_id = channel_id
	l.loader = func() -> Array: return await YouTube.channel_videos(channel_id)
	open_layer(l)


func open_video_grid(head: String, sub: String, loader: Callable) -> void:
	var l = VideoGrid.new()
	l.heading = head
	l.subheading = sub
	l.loader = loader
	open_layer(l)


func open_yt_login() -> void:
	open_layer(_rare("yt_login").new())


func open_nuvio_login() -> void:
	open_layer(_rare("nuvio_login").new())


## Filme-Quellen (Roadmap 35): Addons, Plex, Jellyfin, Emby, Stremio-Konto. first: beim ersten
## Öffnen von „Filme“ (oben „Fertig“).
func open_movie_sources(first := false) -> void:
	var l = _rare("movie_sources").new()
	l.first = first
	open_layer(l)


## Plex verbinden (PIN über plex.tv/link); servers_only: angemeldet, nur den Server wechseln.
func open_plex_login(servers_only := false) -> void:
	var l = _rare("plex_login").new()
	l.servers_only = servers_only
	open_layer(l)


func open_jellyfin_login(kind := "jellyfin") -> void:
	var l = _rare("jellyfin_login").new()
	l.kind = kind
	open_layer(l)


## Stremio-Konto (nach Hinweis); page „addons“: die eigenen Addons zum Übernehmen.
func open_stremio_login(page := "") -> void:
	var l = _rare("stremio_login").new()
	l.page = page
	open_layer(l)


## RetroAchievements verbinden: Name und Web-API-Schlüssel per Handy, geprüft vor dem Speichern.
func open_ra_login() -> Control:
	return open_layer(_rare("ra_login").new())


## Eigenes Spiel ohne Launcher hinzufügen: Programm wählen oder Ordner durchsuchen (Punkt 117).
func open_add_game() -> Control:
	return open_layer(_rare("add_game").new())


## Fehlender Launcher (steam | epic | ea): die offizielle Seite, sonst nichts.
func open_launcher_offer(id: String) -> Control:
	var l = _rare("launcher_offer").new()
	l.launcher = id
	return open_layer(l)


## Twitch (Streams): Anmeldung wie die Twitch-App am Fernseher, Kanal- und Kategorieseite.
func open_twitch_login() -> Control:
	return open_layer(_rare("twitch_login").new())


func open_stream_channel(login: String, name_ := "") -> void:
	if login == "":
		return
	var l = _rare("stream_page").new()
	l.login = login
	l.heading = name_ if name_ != "" else login
	open_layer(l)


func open_stream_game(game: Dictionary) -> void:
	var l = _rare("stream_page").new()
	l.game = game
	l.heading = str(game.get("title", "Kategorie"))
	open_layer(l)


# --- Video im Vollbild weicht anderen Programmen (Alt+Tab) ---------------------------------------

## mpv und Uzais durchsichtiges Fenster liegen beim Video „immer oben“. Wechselt man mit Alt+Tab oder
## der Windows-Taste zu einem anderen Programm, bliebe es dahinter unsichtbar. Darum tritt das Video
## dann zurück: mpv minimiert sich (der Ton läuft weiter), Uzai gibt den obersten Platz ab und legt
## sich hinter das Fenster vorn. Zurück zu Uzai (oder zu mpv): alles wieder wie vorher.
var _video_gewichen := false
var _video_wache_an := false


func _video_fokus(rein: bool) -> void:
	if rein:
		if _video_gewichen:
			_video_zurueck()
		return
	if _video_overlay and Video.active and not Video.sim and not Video.pip and not Launcher.in_game and not _video_wache_an and Helper.available:
		_video_wache()


## Sieht nach, wer vorn liegt, solange Uzai beim Video keinen Fokus hat: zweimal hintereinander ein
## fremdes Programm → weichen; danach mpv wieder vorn (Taskleiste) → zurück. Endet mit dem Fokus.
func _video_wache() -> void:
	_video_wache_an = true
	var fremd := 0
	var runden := 0
	while is_inside_tree() and _video_overlay and Video.active and not Launcher.in_game and not get_window().has_focus():
		runden += 1
		await get_tree().create_timer(0.35 if runden < 8 else 1.0).timeout
		var r := await Helper.run("window-state", {}, 2.0)
		if not r.ok or not (r.result is Dictionary) or get_window().has_focus():
			continue
		var st: Dictionary = r.result
		if _video_gewichen:
			if Video.mpv_pid() > 0 and int(st.get("fg_pid", 0)) == Video.mpv_pid():
				_video_zurueck()
				break
			continue
		fremd = fremd + 1 if video_soll_weichen(st, OS.get_process_id(), Video.mpv_pid()) else 0
		if fremd >= 2 and _video_overlay and Video.active:
			await _video_weichen(str(st.get("fg_title", "")))
	_video_wache_an = false


func _video_weichen(vorn: String) -> void:
	_video_gewichen = true
	Launcher.log_launch("Video: „%s“ liegt vorn – das Video tritt zurück (Ton läuft weiter)" % vorn.left(60))
	Video.zuruecktreten(true)
	# Ein Menü über dem Video hält Uzai sonst oben (und der Helfer hebt es immer wieder an).
	if _cover_why.has("menu"):
		await _cover("menu", false)
	if _see_through_on or get_window().always_on_top:
		get_window().always_on_top = false
		await Helper.run("cover", { "hwnd": _hwnd(), "on": false, "top": false, "behind_front": true }, 3.0)


func _video_zurueck() -> void:
	_video_gewichen = false
	if not (_video_overlay and Video.active):
		return
	Launcher.log_launch("Video: wieder vorn")
	# Mit einem Menü über dem Video liegt Uzai obenauf, sonst wieder mpv bzw. Uzai durchsichtig darüber.
	Video.zuruecktreten(false, not _menu_over_video or not Video.front_mode())
	await get_tree().create_timer(0.3).timeout
	if not (_video_overlay and Video.active) or _video_gewichen:
		return
	if _see_through_on:
		get_window().always_on_top = true
	if _menu_over_video:
		_cover("menu", true)
		_menu_focus()
	else:
		DisplayServer.window_move_to_foreground()
		Helper.run("focus", { "pid": OS.get_process_id() })


# --- Fenster im Hintergrund und Schließen --------------------------------------------------------

func _notification(what: int) -> void:
	# Im Hintergrund (Desktop, anderes Programm) sparsam laufen, ohne Spiel und ohne Overlay.
	# Nav.pad_unfocused: Uzai bedient gerade ein Fenster im Hintergrund (WindowRemote) – nicht ruhen.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _started and not Launcher.in_game and not _overlay_mode and not _video_overlay and not Nav.pad_unfocused:
		set_idle(true, 20)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and not Launcher.in_game:
		set_idle(false)
	# Alt+Tab im Spiel: „immer oben“ abgeben bzw. zurück, leeres Uzai → Guide (main_fenster.gd).
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		fokus_wechsel(what == NOTIFICATION_APPLICATION_FOCUS_IN)
		_video_fokus(what == NOTIFICATION_APPLICATION_FOCUS_IN)
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_away_for_discord = false
		# Zurück aus dem Epic Games Launcher: fertige Installation gleich zeigen.
		Library.on_focus_in()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if Video.active:
			Video.stop()
		Library.save()
		YouTube.save()
		Movies.save()
		Config.save_settings()
		_on_close_request()


# --- Filme -------------------------------------------------------------------------------------

## Detailseite eines Films oder einer Serie (MetaPreview genügt, die Seite lädt den Rest).
func open_movie(item: Dictionary) -> void:
	if item.is_empty():
		return
	var l = _rare("movie_detail").new()
	l.item = item
	open_layer(l)


## Quellen für einen Film oder eine Folge. mode: ask (bei Fortschritt fragen), resume, start.
func open_movie_streams(meta: Dictionary, video_id: String, mode := "ask") -> void:
	var l = MovieStreams.new()
	l.meta = meta
	l.video_id = video_id
	l.mode = mode
	open_layer(l)


## „Alle anzeigen“ einer Reihe der Startseite.
func open_movie_catalog(row: Dictionary) -> void:
	var l = MovieCatalog.new()
	l.row = row
	open_layer(l)


## Ordner einer Nuvio-Sammlung: oben ein Reiter je Katalog (und „Alle“), darunter das Raster.
func open_movie_folder(folder: Dictionary, show_all := true) -> void:
	var l = MovieCatalog.new()
	l.folder = folder
	l.show_all = show_all
	l.row = { "title": str(folder.get("title", "")) }
	open_layer(l)


var _under_player: Array = []
var _player_prev: Control


## Nach Movies.play(): Uzais Leiste über dem Film. Die Ebenen darunter (Detail, Quellen) bleiben
## offen, sind aber unsichtbar, solange der Film läuft – sie würden ihn sonst verdecken.
func open_movie_player() -> void:
	if not Video.active or is_instance_valid(_player):
		return
	if Launcher.in_game:
		return
	_player_prev = Nav.focused()
	_under_player.clear()
	for l in Nav.layers:
		if is_instance_valid(l) and l.visible:
			l.visible = false
			_under_player.append(l)
	Sfx.play("open")
	_player = _rare("video_player").new()
	_player.main = self
	open_layer(_player)
	video_mode_changed()


func _restore_under_player() -> bool:
	var any := false
	for l in _under_player:
		if is_instance_valid(l):
			(l as Control).visible = true
			any = true
	_under_player.clear()
	if any:
		var prev := _player_prev
		_player_prev = null
		if is_instance_valid(prev) and prev.is_visible_in_tree():
			Nav.focus(prev, true)
		elif Nav.top_layer():
			var d := Nav.default_in(Nav.top_layer())
			if d:
				Nav.focus(d, true)
	return any
