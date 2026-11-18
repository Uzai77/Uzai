extends Control
## Hauptbildschirm, unterste Schicht: Uzais Fenster neben dem Spiel – vorn halten, solange es
## startet (Abdeckung, Schleier), im Spiel ruhen (Bildrate, Leerlauf) und als Fenster über dem Spiel
## einblenden (Guide, Mitteilungen) und wieder zurückgeben.
## Der Hauptbildschirm besteht aus Schichten; jede erbt von der darunter und kennt nur sie:
## main_fenster.gd → main_ebenen.gd → main_discord.gd → main_guide.gd → main.gd.

const U := preload("res://src/ui/u.gd")

const DisplayFit := preload("res://src/core/display_fit.gd")
const Bildschirm := preload("res://src/core/bildschirm.gd")
const Logdatei := preload("res://src/core/logdatei.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Bildrate := preload("res://src/core/bildrate.gd")
const Vorhang := preload("res://src/core/vorhang.gd")
const Fernsehspiel := preload("res://src/room/fernsehspiel.gd")
const AppSteuerung := preload("res://src/core/app_steuerung.gd")
const AppHinweis := preload("res://src/ui/app_hinweis.gd")
const AppLeitfaden := preload("res://src/ui/app_leitfaden.gd")
const AppPadCheck := preload("res://src/core/pad_check.gd")
const Zustand := preload("res://src/core/zustand.gd")
const OverlaySpiel := preload("res://src/core/overlay_spiel.gd")
const InstallParse := preload("res://src/core/install_parse.gd")
const STARTER_MAX_MS := 240000    ## so lange sieht Uzai beim Start nach einem wartenden Fenster von Steam
const Arbeit := preload("res://src/core/arbeit.gd")
const Background := preload("res://src/ui/components/background.gd")

var background: Background
var shell: VBoxContainer
var _hint_fade: TextureRect
var _guide: Control
var _ingame: Control
var _overlay_mode := false:
	set(neu):
		_overlay_mode = neu
		_fenster_melden()


# --- Uzai nach vorn holen ------------------------------------------------------------------------

## Uzai wieder nach vorn holen (z. B. nachdem Steam den Installationsdialog gezeigt hat).
func bring_to_front() -> void:
	_restore_window()


## Installieren über Uzai (Installs): Uzai bleibt ganz oben, solange Steam oder Epic im
## Hintergrund einen Dialog zeigen, den Uzai bestätigt (wie beim Spielstart, siehe _cover).
func hold_front(on: bool) -> void:
	_cover("install", on)
	if not on:
		bring_to_front()


# --- Startbildschirm vorn halten ------------------------------------------------------------

var _veil_rect: ColorRect

## Warum Uzai gerade ganz oben bleiben muss: "start" (Spielstart, bis das Spiel vorn ist),
## "menu" (Guide oder Optionen über dem Video, mpv liegt sonst darüber). Solange einer gilt, ist
## Uzais Fenster „immer oben“, und der Helfer legt es wieder nach oben, sobald etwas darüber
## liegt (UzCover) – auch über die Taskleiste. Dauerhaft ändert sich nichts: Der Helfer hört von
## selbst auf (Zeitgrenze, Fenster weg), und Windows-Einstellungen fasst Uzai nicht an.
var _cover_why := {}
var _cover_gen := 0
var _cover_max := 0              ## Zeitgrenze, mit der der Helfer zuletzt „an“ bekam
var _see_through_on := false


## behind_front (nur beim Abgeben): Uzai gleich hinter das Vordergrundfenster legen (ein Dialog,
## der wartet). Wer erst nach dem Abgeben weitermachen darf (mpv wieder nach oben), wartet mit await.
func _cover(why: String, on: bool, behind_front := false) -> void:
	if not Config.is_windows():
		return
	var was := not _cover_why.is_empty()
	if on:
		_cover_why[why] = true
	else:
		_cover_why.erase(why)
	var now_on := not _cover_why.is_empty()
	if why == "start" and on:
		# Bildschirm, wie Windows ihn vor dem Spiel zeigt: Stellt ein Spiel im exklusiven Vollbild die
		# Auflösung um, erkennt der Guide es daran (vollbild_grund).
		_desktop_size = DisplayServer.screen_get_size(get_window().current_screen)
		# Kein Zeiger über dem Startbildschirm (Uzais eigener Zeiger, sonst zeigt Windows ihn).
		if Config.get_value("controller.hide_mouse", true):
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_cover_gen += 1
		_watch_cover(_cover_gen)
		_watch_starter(_cover_gen)
	var max_s := 3600 if _cover_why.has("menu") else 180
	# Kommt ein Grund mit längerer Zeitgrenze dazu, neu ansagen.
	if now_on == was and not (now_on and max_s > _cover_max):
		return
	_cover_max = max_s if now_on else 0
	var top := now_on or _see_through_on
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	get_window().always_on_top = top
	# Beim Abgeben gibt der Helfer den obersten Platz selbst frei (top: false), nachdem sein Faden
	# sicher steht – Godots „nicht mehr oben“ allein konnte der Faden noch überholen, und Uzai blieb
	# dauerhaft über allem.
	var args := { "hwnd": hwnd, "on": now_on, "top": top, "max_s": max_s }
	if behind_front and not now_on and not top:
		args["behind_front"] = true
	await Helper.run("cover", args, 3.0)
	if now_on or not is_inside_tree() or not _cover_why.is_empty():
		return
	# Während der Antwort umgeschaltet: Godots Wunsch gilt.
	if top and not _see_through_on:
		Helper.run("cover", { "hwnd": hwnd, "on": false, "top": false })
	elif not top and _see_through_on:
		get_window().always_on_top = true


## Während des Starts: Wartet ein Fenster auf dich (Steam-Dialog „Shader werden verarbeitet“,
## Fehlermeldung des Emulators, Windows-Abfrage), darf der Startbildschirm es nicht verdecken.
## Liegt drei Sekunden lang dasselbe fremde, kleine oder nicht bildschirmfüllende Fenster vorn,
## gibt Uzai den obersten Platz ab (der Ladebildschirm bleibt dahinter stehen).
func _watch_cover(gen: int) -> void:
	var last := 0
	var since := 0
	var pids: Array = []
	var pids_at := -10000
	while _cover_why.has("start") and gen == _cover_gen:
		await get_tree().create_timer(0.5).timeout
		if not _cover_why.has("start") or gen != _cover_gen:
			return
		if _guide != null or _overlay_mode or not Helper.available:
			last = 0
			continue
		var now := Time.get_ticks_msec()
		if now - pids_at > 3000:
			pids = await Launcher.game_pids()
			pids_at = Time.get_ticks_msec()
		var r := await Helper.run("window-state", { "pids": pids, "hwnd": Launcher.game_hwnd() }, 2.0)
		if not r.ok or not (r.result is Dictionary) or not _cover_why.has("start") or gen != _cover_gen:
			continue
		var st: Dictionary = r.result
		if not cover_should_yield(st, OS.get_process_id()):
			last = 0
			continue
		now = Time.get_ticks_msec()
		if int(st.get("fg_hwnd", 0)) != last:
			last = int(st.get("fg_hwnd", 0))
			since = now
		elif now - since >= 3000:
			Launcher.log_launch("Startbildschirm gibt den Vorrang ab: „%s“ (%s) wartet vorn" % [str(st.get("fg_title", "")), str(st.get("fg_class", ""))])
			_cover("start", false, true)
			# Um das wartende Fenster herum nicht Desktop und Taskleiste, sondern Uzais Grund.
			_vorhang("warten")
			return


## Während des Starts eines Steam-Spiels: Fragt Steam vorher etwas (Startoptionen wie „mit Mods
## starten“, Cloud-Konflikt, eine Abfrage), geht sein Fenster hinter Uzais Startbildschirm auf und
## bekommt den Vordergrund nie – man sah es nicht und wartete ewig. Uzai sieht deshalb selbst nach
## (Fenster von Steam, neu seit dem Start), und wartet eins auf eine Wahl
## (InstallParse.start_dialog_urteil), zeigt Uzai es in sich selbst und lässt es mit dem Controller
## bedienen (window_remote.gd, wie beim Installieren). Der Startbildschirm bleibt dabei stehen.
## Nur Steam-Spiele, höchstens STARTER_MAX_MS lang, nie mit offenem Guide.
func _watch_starter(gen: int) -> void:
	var g: Dictionary = Launcher.current
	if str(g.get("source", "")) != "steam" or not Helper.available:
		return
	var titel := str(g.get("title", "")).strip_edges().to_lower()
	var h_alt := 0
	var seit := 0
	var erledigt := {}
	var ende := Time.get_ticks_msec() + STARTER_MAX_MS
	while Time.get_ticks_msec() < ende:
		await get_tree().create_timer(1.0).timeout
		if not _starter_gilt(gen):
			return
		if _guide != null or _overlay_mode:
			continue
		var r := await Helper.run("proc-windows", { "names": Installs.STEAM_PROCS }, 4.0)
		if not _starter_gilt(gen):
			return
		var wins: Array = r.result.get("windows", []) if r.ok and r.result is Dictionary and r.result.get("windows") is Array else []
		var w := InstallParse.steam_start_dialog(wins, Launcher.fenster_vorher())
		var h := int(w.get("hwnd", 0))
		if h == 0 or erledigt.has(h):
			h_alt = 0
			continue
		var now := Time.get_ticks_msec()
		if h != h_alt:
			h_alt = h
			seit = now
		if now - seit < InstallParse.START_DIALOG_MS:
			continue
		var b := await Helper.run("discord-buttons", { "hwnd": h, "budget_ms": 3000, "app": "steam" }, 10.0)
		if not _starter_gilt(gen):
			return
		var res: Dictionary = b.result if b.ok and b.get("result") is Dictionary else {}
		var knoepfe: Array = res.get("buttons", []) if res.get("buttons") is Array else []
		var wt := str(w.get("title", "")).strip_edges()
		var urteil := InstallParse.start_dialog_urteil(knoepfe, titel != "" and wt.to_lower().contains(titel), Time.get_ticks_msec() - seit)
		if urteil == "warten":
			continue
		erledigt[h] = true
		Launcher.log_launch("Steam-Fenster vor dem Start: „%s“ %dx%d, %d Knöpfe – %s" % [wt.left(80), int(w.get("w", 0)), int(w.get("h", 0)), knoepfe.size(),
				"in Uzai bedienen" if urteil == "zeigen" else "Steam arbeitet, nichts zu tun"])
		if urteil == "zeigen":
			await _starter_zeigen(w, gen)


func _starter_gilt(gen: int) -> bool:
	return is_inside_tree() and gen == _cover_gen and Launcher.in_game and not Launcher.window_is_game


## Steams Fenster in Uzai bedienen, bis das Spiel sein Fenster hat oder das Fenster von Steam weg ist.
func _starter_zeigen(w: Dictionary, gen: int) -> void:
	var hwnd := int(w.get("hwnd", 0))
	# Uzai bleibt dafür oben und bekommt den Controller (hatte der Startbildschirm den Platz schon abgegeben).
	_cover("starter", true)
	bring_to_front()
	var l: Control = load("res://src/ui/layers/window_remote.gd").new()
	l.set("hwnd", hwnd)
	var wt := str(w.get("title", "")).strip_edges()
	l.set("heading", tr("Steam fragt vor dem Start") if wt == "" or wt.to_lower() == "steam" else "Steam – %s" % wt)
	l.set("done_toast", "")
	l.set("weg_schliesst", true)
	l.set("done_check", func() -> bool:
		return not _starter_gilt(gen) or (Launcher.game_hwnd() != 0 and Launcher.game_hwnd() != hwnd))
	call("open_layer", l)
	# Nicht am Signal hängen: Schließt etwas anderes die Ebene (Spielstart räumt auf), bliebe Uzai sonst oben.
	var box := { "fertig": false }
	l.connect("finished", func(_r: String) -> void: box.fertig = true)
	while not bool(box.fertig) and is_instance_valid(l) and l.is_inside_tree():
		await get_tree().process_frame
	_cover("starter", false)


## Ist das Vordergrundfenster eines, das man sehen muss (Dialog, Starter, Abfrage)? Nicht: Uzai,
## Taskleiste/Desktop, ein bildschirmfüllendes Fenster, das große Fenster des Spiels selbst.
static func cover_should_yield(st: Dictionary, own_pid: int) -> bool:
	if int(st.get("fg_hwnd", 0)) == 0 or int(st.get("fg_pid", 0)) == own_pid:
		return false
	if bool(st.get("fg_shell", false)) or bool(st.get("fg_full", false)):
		return false
	if bool(st.get("fg_game", false)) and int(st.get("fg_w", 0)) >= 640 and int(st.get("fg_h", 0)) >= 360:
		return false
	return true


# --- Vorhang: Übergänge ohne Windows (src/core/vorhang.gd) -------------------------------------

func _hwnd() -> int:
	return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)


## Zuletzt verlangter Vorhang (src/core/vorhang.gd ANLAESSE, "" = auf). Kein fester Ablauf: Start (start, starter,
## warten), Beenden, Wache (schliessen) und Spielende verlangen ihn unabhängig voneinander – im Zimmer und hinter
## einer eigenen App fehlt „ende“, dann folgt der nächste Start direkt auf den letzten Auftrag.
const ZUSTAENDE_VORHANG := {
	"*": ["", "start", "starter", "warten", "beenden", "schliessen", "ende"],
	"": [], "start": [], "starter": [], "warten": [], "beenden": [], "schliessen": [], "ende": [],
}
var _vorhang_anlass := "":
	set(neu):
		Zustand.wechsel("spiel.vorhang", ZUSTAENDE_VORHANG, _vorhang_anlass, neu)
		_vorhang_anlass = neu
## Die Wache hat zugezogen (Spielfenster weg), und das Spiel zeigt noch kein neues Fenster – dann deckt
## der Vorhang, und der Guide muss darüber (toggle_guide), nicht darunter.
var _spiel_weg := false


## Vorhang zu (start, starter, warten, beenden, schliessen, ende) oder auf (sonst). Wartet, bis der
## Helfer ihn wirklich zeigt (gemalt und von Windows dargestellt) – höchstens 1,5 s –, damit Uzai sein
## Fenster erst danach umstellt. true: er steht. „schliessen“ holt die Prozesse des Spiels fürs Loch selbst.
func _vorhang(anlass: String, pids: Array = []) -> bool:
	_vorhang_anlass = anlass
	if not Config.is_windows() or not Helper.available:
		return false
	if anlass == "schliessen" and pids.is_empty():
		pids = await Launcher.spiel_pids()
		if not Launcher.in_game:
			return false          # inzwischen zu: „ende“ gilt
	var r := await Helper.run("vorhang", Vorhang.auftrag(anlass, _hwnd(), UzTheme.col("bg"), pids), 1.5)
	return r.ok and r.result is Dictionary and bool((r.result as Dictionary).get("sichtbar", false))


## Beenden (Launcher.quit_cover): Vorhang zu, bevor sich ein Emulator schließt und bevor Uzai hart
## beendet („beenden“: auch über dem Vollbild – das Fenster, das zugeht, sieht man so nicht), bzw. wenn
## das Spielfenster beim höflichen Schließen verschwand („schliessen“: eine Rückfrage des Spiels bleibt
## zu sehen). an = false: Es lief weiter, Vorhang auf.
## Im Zimmer (Spiel im Fernseher) liegt Uzai ohnehin vorn, hinter einer eigenen App liegt Uzai als
## Kulisse (dort käme kein „ende“, das den Vorhang wieder abnimmt), und ein deckender Guide
## (_enter_overlay) deckt selbst – ein Vorhang läge sonst über ihm.
func beenden_vorhang(an: bool, art := "beenden") -> void:
	if Fernsehspiel.uzai_vorn(_tv) or _kulisse:
		return
	if an:
		if _overlay_mode and _overlay_deckend:
			return
		await _vorhang("schliessen" if art == "schliessen" else "beenden")
	elif Launcher.in_game:
		await _vorhang("")


## Wache über dem laufenden Spiel: verschwindet sein Fenster, zieht der Helfer den Vorhang sofort zu
## (siehe _on_pad_event „vorhang“). Nur solange Uzai ruht oder durchsichtig darüberliegt – im
## Zimmer deckt Uzai selbst.
func vorhang_wache() -> void:
	if not Config.is_windows() or not Helper.available:
		return
	# Eigene App: Uzai liegt als Kulisse dahinter – geht ihr Fenster zu, sieht man Uzai, nicht Windows.
	var an := Launcher.in_game and Launcher.window_seen and not Fernsehspiel.uzai_vorn(_tv) and not _kulisse
	if not Launcher.in_game:
		_spiel_weg = false
	var r := await Helper.run("vorhang-wache", Vorhang.wache(_hwnd(), Launcher.game_hwnd() if an else 0), 3.0)
	if an and r.ok and r.result is Dictionary and bool((r.result as Dictionary).get("an", false)):
		_spiel_weg = false


## Die Wache hat den Vorhang zugezogen (Spielfenster weg): gleich nachsehen, ob das Spiel zu ist
## (sonst erst beim nächsten Rundgang in bis zu drei Sekunden) – dann übernimmt _on_game_ended. Liegt
## inzwischen ein anderes Fenster des Spiels im Vollbild vorn (Starter → Spiel, neues Fenster), folgt
## ihm die Wache, und der Vorhang geht. Beendet Uzai das Spiel gerade (oder läuft es nach
## WACHE_LAEUFT_MS noch ohne Fenster: speichert, fährt herunter), wird er zu „schliessen“: schwarz bis
## zum Ende, ein Loch nur um ein Fenster des Spiels (Rückfrage, neues Fenster) – Vorhang.nach_wache.
## Früher wurde er nach 3 s zum Start-Vorhang mit Loch um jedes Fenster: Windows legte nach dem
## Spielfenster den Browser oder Explorer nach vorn, und man sah sie kurz, bis Uzai das Ende bemerkte.
const WACHE_LAEUFT_MS := 3000


func _vorhang_ausgeloest() -> void:
	_spiel_weg = true
	Launcher.schnell_pruefen()
	var t0 := Time.get_ticks_msec()
	var pids: Array = []
	var voll := 0
	var gedeckt := false
	while Launcher.in_game and _spiel_weg and Time.get_ticks_msec() - t0 < Vorhang.SCHLIESSEN_MS:
		await get_tree().create_timer(0.15).timeout
		if not Launcher.in_game or not _spiel_weg or _overlay_mode or not Config.is_windows() or not Helper.available:
			continue
		if pids.is_empty():
			pids = await Launcher.spiel_pids()
		var r := await Helper.run("window-state", { "pids": pids, "hwnd": Launcher.game_hwnd() }, 1.0)
		if not Launcher.in_game or _overlay_mode:
			continue
		var st: Dictionary = r.result if r.ok and r.result is Dictionary else {}
		var fg_game := bool(st.get("fg_game", false)) and int(st.get("fg_hwnd", 0)) != 0
		voll = voll + 1 if fg_game and bool(st.get("fg_full", false)) else 0
		match Vorhang.nach_wache(Time.get_ticks_msec() - t0, Launcher.quitting, fg_game, voll, gedeckt, WACHE_LAEUFT_MS):
			"folgen":
				# Die Wache folgt dem neuen Fenster (sonst sähe sie nur das alte, längst weg).
				Helper.run("vorhang-wache", Vorhang.wache(_hwnd(), int(st.get("fg_hwnd", 0))))
				_spiel_weg = false
				return
			"schliessen":
				gedeckt = true
				await _vorhang("schliessen", pids)


## Nach der Rückkehr aus dem Spiel: Vorhang weg, sobald Uzai gezeichnet hat und vorn ist. Gezählt
## werden nur Bilder, seit Uzais Fenster wieder offen ist (minimiert zeigte Windows noch das alte).
func _vorhang_nach_rueckkehr() -> void:
	if not Config.is_windows() or not Helper.available:
		return
	var t0 := Time.get_ticks_msec()
	var b0 := -1
	while is_inside_tree() and not Launcher.in_game:
		await get_tree().process_frame
		if b0 < 0 and get_window().mode != Window.MODE_MINIMIZED:
			b0 = Engine.get_frames_drawn()
		var bilder := Engine.get_frames_drawn() - b0 if b0 >= 0 else 0
		if Vorhang.darf_weg(bilder, get_window().has_focus(), Time.get_ticks_msec() - t0):
			break
	if not Launcher.in_game:
		Helper.run("vorhang", Vorhang.auftrag("", 0))


## Schwarzer Schleier über allem (Spielstart), damit Uzai nicht hart verschwindet.
func _veil(on: bool) -> void:
	if not on:
		if is_instance_valid(_veil_rect):
			_veil_rect.queue_free()
		_veil_rect = null
		return
	if not is_instance_valid(_veil_rect):
		_veil_rect = ColorRect.new()
		_veil_rect.color = Color.BLACK
		_veil_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		U.full_rect(_veil_rect)
		add_child(_veil_rect)
	_veil_rect.modulate.a = 0.0
	var tw := _veil_rect.create_tween()
	tw.tween_property(_veil_rect, "modulate:a", 1.0, 0.22)
	await tw.finished


## Im Spiel minimiert liegen – durchsichtig und leer. Windows zeigt beim Wiederherstellen (Guide)
## kurz das zuletzt gezeigte Bild; so ist das nichts statt eines halben Guides auf Schwarz.
var _parked := false:
	set(neu):
		_parked = neu
		_fenster_melden()


func _park() -> void:
	_parked = true
	if Launcher.in_game and Launcher.is_app(Launcher.current):
		_kulisse_zeigen()
		return
	_kulisse = false
	shell.visible = false
	background.visible = false
	if _ingame and is_instance_valid(_ingame):
		_ingame.visible = false
	if is_instance_valid(_veil_rect):
		_veil_rect.visible = false
	see_through(true)
	# Erst jetzt (durchsichtig, gleich minimiert): Der Startbildschirm muss nicht mehr vorn bleiben.
	_cover("start", false)
	await RenderingServer.frame_post_draw
	if Launcher.in_game and not _overlay_mode and _parked:
		get_window().mode = Window.MODE_MINIMIZED
		Launcher.focus_game()
		_ruhe_takt()
		vorhang_wache()


func _unpark() -> void:
	_parked = false
	_spiel_minimiert = false
	_kulisse = false
	_overlay_deckend = false
	shell.visible = true
	background.visible = true
	if _ingame and is_instance_valid(_ingame):
		_ingame.visible = true
	see_through(false)


## Wo Uzais Fenster neben dem Spiel liegt (Zustand.lage(), Fehlerbericht), aus den Schaltern _overlay_mode,
## _overlay_deckend, _spiel_minimiert, _kulisse und _parked: vorn (Menü, Startbildschirm), geparkt (minimiert
## hinter dem Spiel), kulisse (hinter einer eigenen App), guide (durchsichtig über dem Spiel, auch im Zimmer
## aufgestanden), guide_deckend (Spielfenster weg, Beenden), guide_minimiert (exklusives Vollbild: das Spiel
## liegt kurz minimiert).
func fenster_lage() -> String:
	if _overlay_mode:
		if _ov_im_spiel:
			return "guide_im_spiel"
		if _spiel_minimiert:
			return "guide_minimiert"
		return "guide_deckend" if _overlay_deckend else "guide"
	if _kulisse:
		return "kulisse"
	return "geparkt" if _parked else "vorn"


func _fenster_melden() -> void:
	Zustand.melden("spiel.fenster", fenster_lage())


## Eigene App vorn (src/core/app_steuerung.gd): Uzai bleibt als Kulisse dahinter liegen, statt sich zu
## minimieren – randlos über dem ganzen Bildschirm, nur der ruhende Hintergrund, kaum Rechenzeit. Beim
## Start, nach dem Guide und beim Schließen sieht man so Uzai statt Desktop und Taskleiste; die App
## selbst liegt randlos im Vollbild darüber (Launcher._app_vorn).
var _kulisse := false:
	set(neu):
		_kulisse = neu
		_fenster_melden()


func _kulisse_zeigen() -> void:
	_kulisse = true
	shell.visible = false
	background.visible = true
	if _ingame and is_instance_valid(_ingame):
		_ingame.visible = false
	if is_instance_valid(_veil_rect):
		_veil_rect.visible = false
	# Nicht mehr durchsichtig und nicht mehr „immer oben“ – Windows legt Uzai dabei über die normalen
	# Fenster; gleich danach holt der Helfer die App wieder darüber.
	see_through(false)
	_cover("start", false)
	Launcher.focus_game()
	set_idle(true)
	vorhang_wache()


## Tastenzeile kurz unten über der App (app_hinweis.gd), solange sie vorn ist. Ohne eigene Hinweise
## beim Start: bei den ersten Starts je App stattdessen der Leitfaden (Controller mit Belegung).
func app_hinweis(hints: Array = []) -> void:
	if not Config.is_windows() or not Launcher.in_game or not Launcher.is_app(Launcher.current) or _guide != null or _overlay_mode:
		return
	var e: Dictionary = Launcher.current.get("app", {})
	if hints.is_empty() and AppSteuerung.leitfaden_faellig(e) and app_leitfaden(false):
		return
	var w := AppHinweis.new()
	add_child(w)
	w.zeigen(hints if not hints.is_empty() else AppSteuerung.hinweis(e), AppSteuerung.HINWEIS_MS)


## Leitfaden über der App (app_leitfaden.gd): der Controller, den du benutzt, mit der Belegung dieser
## App. von_hand: aus dem Guide (zählt nicht zu den ersten Starts). true: er steht.
func app_leitfaden(von_hand: bool) -> bool:
	if not Config.is_windows() or not Launcher.in_game or not Launcher.is_app(Launcher.current) or _guide != null or _overlay_mode:
		return false
	var e: Dictionary = Launcher.current.get("app", {})
	var fam := AppSteuerung.familie(str(Config.get_value("controller.glyphs", "auto")),
			AppPadCheck.glyphs_for(Nav.pad_name, Nav.pad_vid), not Input.get_connected_joypads().is_empty())
	if fam == "":
		return false
	if not von_hand:
		AppSteuerung.leitfaden_gezeigt(e)
	var w := AppLeitfaden.new()
	w.main = self
	add_child(w)
	w.zeigen(fam, AppSteuerung.belegung(e), str(e.get("name", "")), AppSteuerung.LEITFADEN_MS)
	return true


## Während ein Spiel läuft (oder Uzai im Hintergrund liegt) kaum Rechenzeit verbrauchen.
## 12 Bilder pro Sekunde reichen, damit die Guide-Taste sofort reagiert. Im Menü so viele, wie der
## Bildschirm zeigt – über 144 Hz die halbe Rate (src/core/display_fit.gd).
## fps 0: so viele wie im Menü. sparsam: der Sparmodus der Engine (Pausen zwischen den Bildern) – nicht
## bei ruhiger Bewegung wie der Kamerafahrt des Ruhebildschirms, dort ruckelte sie.
func set_idle(on: bool, fps := 12, sparsam := true) -> void:
	OS.low_processor_usage_mode = on and sparsam
	Leicht.idle = false
	Engine.max_fps = (fps if fps > 0 else _menu_fps()) if on else _menu_fps()
	Bildrate.gesetzt()
	if background:
		background.set_process(not on)
		background.pause_motion(on)


## Bildrate im Menü: über 144 Hz die halbe (display_fit.gd); im leichten Modus höchstens 60 und,
## solange das Menü ruht, höchstens 30 (src/core/leicht.gd). 0 = so viele, wie der Bildschirm zeigt.
func _menu_fps() -> int:
	var hz := DisplayServer.screen_get_refresh_rate(get_window().current_screen)
	if Leicht.active:
		return Leicht.idle_fps(hz) if Leicht.idle else Leicht.menu_fps(hz)
	return DisplayFit.menu_fps(hz, str(Config.get_value("display.menu_fps", "auto")))


# --- Fenster: über dem Spiel einblenden ---------------------------------------

## deckend: Das Spielfenster ist weg oder Beenden läuft bzw. ging nicht – der Guide liegt dann auf
## Uzais Grund statt durchsichtig über dem Spiel; danach geht der Vorhang darunter (sonst läge er
## über dem Guide, und dahinter wäre der Desktop).
func _enter_overlay(deckend := false) -> void:
	if not Config.is_windows() or _overlay_mode:
		return
	_overlay_mode = true
	_overlay_deckend = deckend
	_parked = false
	_eigen_ms = Time.get_ticks_msec()
	set_idle(false)
	shell.visible = false
	background.visible = deckend
	# Hinter dem deckenden Guide das Bild des laufenden Spiels – nicht das der Hülle, die zuletzt auf
	# der Startseite gewählt war (aus Suche, Zimmer oder „Zuletzt gespielt“ gestartet, war es ein anderes).
	if deckend and Launcher.in_game and background and not Library.get_game(_spiel_id()).is_empty():
		background.show_game(Library.get_game(_spiel_id()))
	if _ingame and is_instance_valid(_ingame):
		_ingame.visible = false
	see_through(true)
	DisplayServer.window_move_to_foreground()
	# Windows lässt Fenster aus dem Hintergrund nicht einfach nach vorn: der Helfer hilft nach.
	_overlay_focus()
	if deckend:
		_vorhang_unter_guide()


## Deckender Guide: erst wenn Uzai gezeichnet hat, den Vorhang abnehmen.
func _vorhang_unter_guide() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if _overlay_mode and _overlay_deckend and Launcher.in_game:
		await _vorhang("")


var _overlay_pad_forced := false
var _overlay_deckend := false:
	set(neu):
		_overlay_deckend = neu
		_fenster_melden()
var _admin_hint_shown := false


## Fokus für den Guide über dem Spiel holen, bis zu dreimal. Der Controller gilt dem Guide sofort –
## nicht erst, wenn Windows den Fokus herausgibt: Früher nahm er ihn erst nach drei gescheiterten
## Versuchen an (je bis zu drei Sekunden Frist), solange war der Guide zu sehen, aber nicht zu
## bedienen. Das Spiel bekommt die Tasten bis zum Fokuswechsel ohnehin; Emulatoren sind angehalten.
## Klappt der Fokus gar nicht (Spiel mit Adminrechten), sagt Uzai es einmal.
func _overlay_focus() -> void:
	Nav.pad_unfocused = true
	_overlay_pad_forced = true
	for i in 3:
		await Helper.run("focus", { "pid": OS.get_process_id() }, 3.0)
		await get_tree().create_timer(0.15).timeout
		if not _overlay_mode or get_window().has_focus():
			return
	if not _overlay_mode:
		return
	Launcher.log_launch("Guide: Windows gibt Uzai den Fokus nicht (drei Versuche) – der Controller bedient ihn trotzdem")
	if not _admin_hint_shown:
		_admin_hint_shown = true
		Toasts.show_toast("Windows lässt Uzai nicht nach vorn",
				"Das Spiel läuft vermutlich mit Administratorrechten. Der Guide geht trotzdem; die Tastatur erreicht ihn nicht.", "warning", { "ms": 6000 })


func _leave_overlay() -> void:
	if not _overlay_mode:
		return
	_ov_aus()
	# Im Zimmer aufgestanden: Uzai bleibt durchsichtig vorn mit dem Fokus (das Zimmer deckt alles).
	if _tv == "zimmer" and Launcher.in_game and _tv_zimmer():
		return
	_overlay_mode = false
	_overlay_deckend = false
	if _overlay_pad_forced:
		_overlay_pad_forced = false
		Nav.pad_unfocused = false
	# Im Zimmer gestartet, das Fenster kam, während der Guide offen war: erst in den Fernseher fahren.
	if Launcher.in_game and Launcher.window_seen and _tv == "startet":
		_tv_einsteigen()
		return
	# Im Spiel durchsichtig und leer minimieren (siehe _park). Ist das Spielfenster noch nicht da,
	# bleibt der Ladebildschirm stehen statt des Desktops.
	if Launcher.in_game and Launcher.window_seen:
		await _park()
		return
	_unpark()
	# Guide in der Startphase zu: Der Emulator war vorn, er bekommt den Fokus zurück. Den
	# Ladebildschirm davorzuholen verdeckte ihn bis zum Ende des Starts.
	if Launcher.is_starting():
		Launcher.focus_game()
		return
	_restore_window()


# --- Overlay im Spiel (Versuch, docs/OVERLAY.md, src/core/overlay_spiel.gd) -----------------------

## Der Guide wird gerade im Spiel selbst gezeichnet (statt das Spiel aus dem Vollbild zu nehmen).
var _ov_im_spiel := false:
	set(neu):
		_ov_im_spiel = neu
		_fenster_melden()
var _ov_pid := 0                     ## Prozess, in dem die Bibliothek läuft (0: keiner)
var _ov_zaehler := 0                 ## Zähler der Bilddatei (gerade: vollständig)
var _ov_nein := {}                   ## Spiel → Grund, warum es in diesem Lauf nicht geht

const OV_BILD_S := 0.066             ## so oft schreibt Uzai das Bild des Guides, solange er im Spiel steht
const OV_WACHE_S := 0.4              ## danach nachsehen, ob das Spiel den Vordergrund behalten hat


## Kann der Guide in diesem Spiel selbst erscheinen? Nur wenn es für das Spiel eingeschaltet ist, kein
## Schutzprogramm im Spielordner liegt und der Starter die Bibliothek laden konnte. Jede Absage gilt
## für den Rest des Laufs und steht in launch.log; dann bleibt es beim Minimieren (_spiel_kurz_weg).
func _overlay_spiel_bereit() -> bool:
	if not Config.is_windows() or not Helper.available:
		return false
	var id := _spiel_id()
	if _ov_nein.has(id):
		return false
	var g := Library.get_game(id)
	if not bool(g.get("overlay", false)):
		return false
	# Der Prozess hinter dem Spielfenster: Bei Spielen aus einem Laden (Steam, Epic) kennt Uzai sonst
	# keinen (Launcher.pid ist dort 0) – das Overlay griff bei ihnen nie. Er muss aus dem Spielordner
	# laufen (derselbe Ordner, den Uzai gleich nach Schutzprogrammen durchsieht), sonst bleibt es aus.
	var pid: int = await Launcher.fenster_pid()
	if not Launcher.in_game or id != _spiel_id() or not OverlaySpiel.prozess_passt(pid, Launcher.pid, await Launcher.game_pids()):
		return false
	if _ov_pid == pid:
		return true
	var namen: Variant = await Arbeit.ergebnis(OverlaySpiel.ordner_namen.bind(str(g.get("install_dir", ""))))
	if not Launcher.in_game or id != _spiel_id():
		return false
	var e := OverlaySpiel.erlaubt(g, true, namen if namen is Array else [])
	if not bool(e.ok):
		_ov_nein[id] = str(e.grund)
		Launcher.log_launch("Overlay im Spiel: nicht für dieses Spiel (%s%s)" % [str(e.grund), (" – " + str(e.schutz)) if str(e.schutz) != "" else ""])
		return false
	var bin := OverlaySpiel.auslegen(Config.path(OverlaySpiel.BIN))
	var bild := Config.path(OverlaySpiel.BILD)
	_ov_zaehler = OverlaySpiel.bild_schreiben(bild, Image.create(4, 4, false, Image.FORMAT_RGBA8), false, maxi(_ov_zaehler, 0))
	if bin == "" or _ov_zaehler < 0:
		_ov_nein[id] = "dateien"
		Launcher.log_launch("Overlay im Spiel: Bibliothek oder Bilddatei ließ sich nicht anlegen")
		return false
	# Erst die 32-Bit-Fassung (ältere Spiele), bei „falsche Bitbreite“ die andere. Im Hintergrund: Der
	# Starter wartet auf das Spiel.
	var erg := 12
	for bits: int in [32, 64]:
		var a := Arbeit.auftrag(OverlaySpiel.starter.bind(bin, bits, pid, bild), Arbeit.SOFORT)
		await a.erledigt
		erg = int(a.wert)
		if erg != 12:
			break
	Launcher.log_launch("Overlay im Spiel: Starter meldet %d (%s)" % [erg, str(OverlaySpiel.ERGEBNIS.get(erg, "?"))])
	if erg in [1, 5] and Launcher.in_game and id == _spiel_id():
		_ov_pid = pid
		return true
	_ov_nein[id] = "starter %d" % erg
	return false


## Guide im Spiel: Uzais Fenster zeichnet durchsichtig weiter, nimmt dem Spiel aber den Vordergrund
## nicht (kein Fokus, kein Minimieren). Das Bild des Guides geht über die Datei ins Spiel; der
## Controller gilt Uzai ohne Fokus. Nimmt Windows dem Spiel trotzdem den Vordergrund, geht es wie
## bisher deckend weiter (_ov_wache).
func _enter_overlay_spiel() -> void:
	if _overlay_mode:
		return
	_overlay_mode = true
	_overlay_deckend = false
	_ov_im_spiel = true
	_parked = false
	set_idle(false)
	shell.visible = false
	background.visible = false
	if _ingame and is_instance_valid(_ingame):
		_ingame.visible = false
	get_window().unfocusable = true
	see_through(true)
	Nav.pad_unfocused = true
	_overlay_pad_forced = true
	Launcher.log_launch("Guide im Spiel: Uzai bleibt im Hintergrund, das Bild geht über die Bibliothek ins Spiel")
	_ov_pumpe()
	_ov_wache()


## Solange der Guide im Spiel steht: sein Bild (der Bereich der Leiste) in die Datei.
func _ov_pumpe() -> void:
	var bild := Config.path(OverlaySpiel.BILD)
	while _ov_im_spiel and is_inside_tree():
		await RenderingServer.frame_post_draw
		if not _ov_im_spiel:
			return
		var img := get_viewport().get_texture().get_image()
		var teil := _ov_ausschnitt(img)
		if teil != null:
			var z := OverlaySpiel.bild_schreiben(bild, teil, _guide != null, _ov_zaehler)
			if z >= 0:
				_ov_zaehler = z
		await get_tree().create_timer(OV_BILD_S).timeout


## Der Teil des Bildes, in dem der Guide steht (links, ganze Höhe), höchstens so groß wie erlaubt.
func _ov_ausschnitt(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	var b := float(img.get_width())
	if _guide != null and is_instance_valid(_guide) and _guide.get("_panel") is Control:
		var r: Rect2 = get_viewport().get_final_transform() * (_guide.get("_panel") as Control).get_global_rect()
		b = clampf(r.end.x, 16.0, float(img.get_width()))
	var w := mini(int(ceil(b)), OverlaySpiel.MAX_BREITE)
	var h := mini(img.get_height(), OverlaySpiel.MAX_HOEHE)
	return img.get_region(Rect2i(0, 0, w, h))


## Hat das Spiel den Vordergrund behalten? Sonst hat Windows Uzai doch aktiviert (das Spiel liegt
## minimiert): dann weiter wie ohne Overlay – deckend, und beim Schließen kommt das Spiel zurück.
func _ov_wache() -> void:
	await get_tree().create_timer(OV_WACHE_S).timeout
	if not _ov_im_spiel or not Launcher.in_game:
		return
	var pids: Array = [Launcher.pid] if Launcher.pid > 0 else []
	var r := await Helper.run("window-state", { "pids": pids, "hwnd": Launcher.game_hwnd() }, 0.6)
	if not _ov_im_spiel or not r.ok or not (r.result is Dictionary):
		return
	var st: Dictionary = r.result
	if bool(st.get("fg_game", false)) and not bool(st.get("target_iconic", false)):
		return
	Launcher.log_launch("Guide im Spiel: das Spiel hat den Vordergrund verloren (vorn „%s“) – weiter deckend wie ohne Overlay" % str(st.get("fg_title", "")))
	_ov_aus()
	_overlay_deckend = true
	background.visible = true
	_spiel_minimiert = true
	_guide_auf_ms = Time.get_ticks_msec()
	_weg_seit_ms = _guide_auf_ms
	DisplayServer.window_move_to_foreground()
	_overlay_focus()
	_vorhang_unter_guide()
	_fenster_nachfuehren()


## Overlay im Spiel verstecken und Uzais Fenster wieder normal (beim Schließen des Guides, beim Rückfall).
func _ov_aus() -> void:
	if not _ov_im_spiel:
		return
	_ov_im_spiel = false
	var z := OverlaySpiel.sichtbar_setzen(Config.path(OverlaySpiel.BILD), false, _ov_zaehler)
	if z >= 0:
		_ov_zaehler = z
	get_window().unfocusable = false


# --- Guide über exklusivem Vollbild, Alt+Tab -----------------------------------------------------

var _desktop_size := Vector2i.ZERO   ## Bildschirm vor dem Spiel (beim Start gemerkt, siehe _cover)
var _eigen_ms := -100000             ## wann Uzai sich zuletzt selbst nach vorn geholt hat
var _oben_abgegeben := false         ## Fokus verloren: „immer oben“ ist bis zur Rückkehr aus
## Der Guide hat das Spiel kurz minimiert (bzw. es lag minimiert).
var _spiel_minimiert := false:
	set(neu):
		_spiel_minimiert = neu
		_fenster_melden()
var _guide_auf_ms := 0
## Wann der Guide dem Spiel zuletzt den Vordergrund genommen bzw. zurückgegeben hat (−1: nichts offen).
## Endet das Spiel kurz danach von selbst, verträgt es das nicht (guide_tod).
var _weg_seit_ms := -1
var _weg_fehl := {}                  ## Spiel → wie oft es sich in diesem Lauf nicht minimieren ließ

const WEG_MS := 1600                 ## so lange darf das Minimieren dauern, bevor der Guide aufgibt
const WEG_NOCHMAL_MS := 700          ## danach bittet Uzai einmal neu
const WEG_FEHL_MAX := 2              ## so oft in einem Lauf, dann lässt die Guide-Taste das Spiel in Ruhe
const TOD_MS := 8000                 ## endet das Spiel so kurz nach dem Wechsel, lag es am Wechsel


## Warum der Guide das Spiel kurz aus dem Weg nimmt ("" = gar nicht): exklusives Direct3D-Vollbild
## (Windows meldet QUNS 3), ein Spiel, das für sein Vollbild die Auflösung umgestellt hat (LWJGL,
## ältere Spiele), oder es liegt schon minimiert (Alt+Tab aus dem exklusiven Vollbild). Über solchen
## Spielen zeigt Windows kein Fenster – der durchsichtige Guide lag unsichtbar dahinter bzw. über
## dem Desktop. Ohne Bildschirm prüfbar.
static func vollbild_grund(st: Dictionary, desktop: Vector2i, jetzt: Vector2i) -> String:
	if bool(st.get("target_iconic", false)):
		return "minimiert"
	if not bool(st.get("fg_game", false)):
		return ""
	if int(st.get("quns", 0)) == 3:
		return "d3d"
	if desktop.x > 0 and jetzt.x > 0 and jetzt != desktop and bool(st.get("fg_full", false)):
		return "aufloesung"
	return ""


## Zeile für launch.log zum Grund (vollbild_grund).
static func vollbild_text(grund: String, desktop: Vector2i, jetzt: Vector2i) -> String:
	match grund:
		"d3d":
			return "Guide über exklusivem Vollbild (Windows meldet D3D-Vollbild): Spiel kurz minimiert, Guide deckend"
		"aufloesung":
			return "Guide über exklusivem Vollbild (Bildschirm %d×%d statt %d×%d): Spiel kurz minimiert, Guide deckend" % [jetzt.x, jetzt.y, desktop.x, desktop.y]
		"minimiert":
			return "Guide: das Spiel liegt minimiert (Alt+Tab aus dem Vollbild) – Guide deckend, beim Schließen kommt es zurück"
	return ""


## Nach „spiel-minimieren“: Ist das Spiel aus dem Weg? "weg": minimiert, oder Uzai liegt vorn und
## Windows meldet kein D3D-Vollbild mehr. Sonst "warten", einmal "nochmal" (WEG_NOCHMAL_MS), am Ende
## "aufgeben" (WEG_MS). Ohne Bildschirm prüfbar.
static func weg_urteil(st: Dictionary, ms: int, nochmal_getan: bool, own_pid: int) -> String:
	if bool(st.get("target_iconic", false)):
		return "weg"
	if not st.is_empty() and int(st.get("fg_pid", 0)) == own_pid and int(st.get("quns", 0)) != 3 and not bool(st.get("fg_game", false)):
		return "weg"
	if ms >= WEG_MS:
		return "aufgeben"
	if ms >= WEG_NOCHMAL_MS and not nochmal_getan:
		return "nochmal"
	return "warten"


## Endete das Spiel, weil der Guide ihm den Vordergrund nahm? Ja, wenn es kurz nach dem Wechsel
## (hin oder zurück) von selbst zuging – nicht, wenn du es über Uzai beendet hast.
static func guide_tod(seit_wechsel_ms: int, ueber_uzai_beendet: bool) -> bool:
	return seit_wechsel_ms >= 0 and seit_wechsel_ms <= TOD_MS and not ueber_uzai_beendet


## Darf die Guide-Taste dieses Spiel aus dem exklusiven Vollbild nehmen? Nein, wenn es dabei schon
## einmal abgestürzt ist (Feld guide_vollbild = "nie", in den Spieloptionen wieder einschaltbar) oder
## sich in diesem Lauf WEG_FEHL_MAX-mal nicht minimieren ließ. Liegt es schon minimiert, immer.
static func guide_vollbild_geht(grund: String, feld: String, fehl: int) -> bool:
	if grund == "" or grund == "minimiert":
		return true
	return feld != "nie" and fehl < WEG_FEHL_MAX


func _spiel_id() -> String:
	return str(Launcher.current.get("id", ""))


## Für toggle_guide (main_guide.gd): geht der Guide über diesem Spiel im exklusiven Vollbild?
func _guide_vollbild_ok(grund: String) -> bool:
	var g := Library.get_game(_spiel_id())
	var ok := guide_vollbild_geht(grund, str(g.get("guide_vollbild", "")), int(_weg_fehl.get(_spiel_id(), 0)))
	if not ok:
		Launcher.log_launch("Guide-Taste im exklusiven Vollbild: dieses Spiel bleibt in Ruhe (%s)" % (
				"endete früher dabei" if str(g.get("guide_vollbild", "")) == "nie" else "ließ sich nicht minimieren"))
	return ok


## Fragt den Helfer (kurz, höchstens 0,4 s), ob das Spiel exklusiv im Vollbild vorn liegt.
func _vollbild_pruefen() -> String:
	if not Config.is_windows() or not Helper.available or Launcher.game_hwnd() == 0 or Launcher.is_app(Launcher.current) or _tv != "":
		return ""
	var pids: Array = [Launcher.pid] if Launcher.pid > 0 else []
	var r := await Helper.run("window-state", { "pids": pids, "hwnd": Launcher.game_hwnd() }, 0.4)
	if not r.ok or not (r.result is Dictionary):
		return ""
	return vollbild_grund(r.result, _desktop_size, DisplayServer.screen_get_size(get_window().current_screen))


## Exklusives Vollbild: das Spiel minimieren (wie Steam Big Picture und Playnite, ohne Tastendruck):
## Windows stellt den Bildschirm zurück, der Guide liegt deckend darüber. Danach passt Uzai sein
## Fenster an, sobald der Bildschirm wieder seine Größe hat.
func _spiel_kurz_weg(grund: String) -> void:
	_spiel_minimiert = true
	_guide_auf_ms = Time.get_ticks_msec()
	var jetzt := DisplayServer.screen_get_size(get_window().current_screen)
	Launcher.log_launch(vollbild_text(grund, _desktop_size, jetzt))
	if grund != "minimiert":
		_weg_seit_ms = _guide_auf_ms
		var pids: Array = [Launcher.pid] if Launcher.pid > 0 else []
		Helper.run("spiel-minimieren", { "hwnd": Launcher.game_hwnd(), "pids": pids, "own": OS.get_process_id() }, 1.0)
		_spiel_weg_pruefen(_guide_auf_ms)
	_fenster_nachfuehren()


## Hat das Minimieren gewirkt? Sonst läge der Guide unsichtbar hinter dem Vollbild und nähme dem Spiel
## den Controller – man säße vor einem Spiel, das eingefroren wirkt. Einmal neu bitten; nach WEG_MS
## aufgeben: Guide zu, das Spiel behält Bildschirm und Eingabe.
func _spiel_weg_pruefen(marke: int) -> void:
	var pids: Array = [Launcher.pid] if Launcher.pid > 0 else []
	var nochmal := false
	var st: Dictionary = {}
	while _spiel_minimiert and marke == _guide_auf_ms and Launcher.in_game and is_inside_tree():
		await get_tree().create_timer(0.15).timeout
		if not (_spiel_minimiert and marke == _guide_auf_ms and Launcher.in_game):
			return
		var r := await Helper.run("window-state", { "pids": pids, "hwnd": Launcher.game_hwnd() }, 0.6)
		if not (_spiel_minimiert and marke == _guide_auf_ms and Launcher.in_game):
			return
		if r.ok and r.result is Dictionary:
			st = r.result
		var ms := Time.get_ticks_msec() - marke
		match weg_urteil(st, ms, nochmal, OS.get_process_id()):
			"weg":
				_weg_fehl.erase(_spiel_id())
				Launcher.log_launch("Guide: Spiel aus dem Weg nach %d ms" % ms)
				return
			"nochmal":
				nochmal = true
				Launcher.log_launch("Guide: Spiel liegt nach %d ms noch im Vollbild vorn – noch einmal minimieren" % ms)
				Helper.run("spiel-minimieren", { "hwnd": Launcher.game_hwnd(), "pids": pids, "own": OS.get_process_id() }, 1.0)
			"aufgeben":
				_weg_fehl[_spiel_id()] = int(_weg_fehl.get(_spiel_id(), 0)) + 1
				Launcher.log_launch("Guide: Spiel ließ sich nicht minimieren (%d ms, vorn „%s“, D3D-Vollbild %s) – Guide zu, das Spiel behält den Bildschirm" % [
						ms, str(st.get("fg_title", "")), "ja" if int(st.get("quns", 0)) == 3 else "nein"])
				_guide_aufgeben()
				return


## Der Guide ist nicht zu sehen: zumachen und dem Spiel alles zurückgeben (kein „Spiel zurückholen“ –
## es lag nie minimiert).
func _guide_aufgeben() -> void:
	_spiel_minimiert = false
	_weg_seit_ms = -1
	Sfx.play("error")
	if _guide != null and is_instance_valid(_guide):
		_guide.call("close")


## Das Spiel ist zu (main.gd _on_game_ended): Lag es am Guide? Dann merkt Uzai es am Spiel, lässt es
## im exklusiven Vollbild künftig in Ruhe und sagt es einmal – mit dem Weg, es wieder einzuschalten.
func guide_tod_melden(g: Dictionary) -> void:
	var seit := Time.get_ticks_msec() - _weg_seit_ms if _weg_seit_ms >= 0 else -1
	_weg_seit_ms = -1
	_ov_aus()
	_ov_pid = 0
	if not guide_tod(seit, Launcher.ueber_uzai_beendet()):
		return
	var id := str(g.get("id", ""))
	if id == "" or Library.get_game(id).is_empty():
		return
	Library.set_field(id, "guide_vollbild", "nie")
	Launcher.log_launch("Guide: Das Spiel endete %d ms nach dem Wechsel aus dem exklusiven Vollbild – künftig bleibt es dort in Ruhe (Spieloptionen: „Guide im Vollbild“)" % seit)
	Toasts.show_toast("Guide im Vollbild ist für dieses Spiel aus",
			tr("„%s“ endete, als der Guide aufging. In den Spieloptionen wieder einschaltbar.") % Library.display_title(g), "warning", { "ms": 9000 })


## Solange der Bildschirm nach dem Minimieren noch umschaltet: Uzais Fenster folgt (sonst blieb es
## 1920×1081 auf einem 2560er Bildschirm stehen – im Log „Fenster 1920×1081 über Bildschirm 2560×1440“).
## Sechs Sekunden: Ältere Spiele und Fernseher brauchen für den Wechsel der Auflösung länger als drei.
const NACHFUEHREN_MS := 6000


func _fenster_nachfuehren() -> void:
	var t0 := Time.get_ticks_msec()
	var w := get_window()
	while Time.get_ticks_msec() - t0 < NACHFUEHREN_MS and is_inside_tree() and _overlay_mode and _see_through_on:
		await get_tree().create_timer(0.1).timeout
		if not _overlay_mode or not _see_through_on:
			return
		var scr := w.current_screen
		var pos := DisplayServer.screen_get_position(scr)
		var sz := DisplayServer.screen_get_size(scr) + Vector2i(0, 1)
		if w.position != pos or w.size != sz:
			w.position = pos
			w.size = sz
			Launcher.log_launch("Guide: Bildschirm wieder %d×%d nach %d ms – Uzais Fenster angepasst" % [sz.x, sz.y - 1, Time.get_ticks_msec() - t0])


## Guide zu, das Spiel war minimiert: zurück nach vorn holen und im Log sagen, ob es geklappt hat.
func _spiel_zurueck() -> void:
	if not _spiel_minimiert:
		return
	_spiel_minimiert = false
	var t0 := Time.get_ticks_msec()
	if _weg_seit_ms >= 0:
		_weg_seit_ms = t0             # ab jetzt zählt das Zurückholen (guide_tod)
	Launcher.focus_game()
	if not Config.is_windows() or not Helper.available:
		return
	var pids: Array = [Launcher.pid] if Launcher.pid > 0 else []
	var st: Dictionary = {}
	var versuche := 0
	while Time.get_ticks_msec() - t0 < 4000 and Launcher.in_game and _guide == null:
		await get_tree().create_timer(0.25).timeout
		var r := await Helper.run("window-state", { "pids": pids, "hwnd": Launcher.game_hwnd() }, 1.0)
		if not r.ok or not (r.result is Dictionary):
			continue
		st = r.result
		if bool(st.get("fg_game", false)) and not bool(st.get("target_iconic", false)):
			Launcher.log_launch("Guide zu: Spiel wieder vorn nach %d ms (Guide offen %d s)" % [Time.get_ticks_msec() - t0, (t0 - _guide_auf_ms) / 1000])
			return
		versuche += 1
		if versuche % 4 == 0:
			Launcher.focus_game()
	if Launcher.in_game and _guide == null:
		Launcher.log_launch("Guide zu: Spiel nicht vorn nach %d ms, vorn: „%s“ (%s)" % [Time.get_ticks_msec() - t0, str(st.get("fg_title", "")), str(st.get("fg_class", ""))])
		# Antwortet es nicht mehr? Dann steht es im Log, und die Wache über hängende Spiele übernimmt.
		var h := await Helper.run("window-hung", { "hwnd": Launcher.game_hwnd() }, 1.0)
		if h.ok and h.result is Dictionary and bool((h.result as Dictionary).get("hung", false)):
			Launcher.log_launch("Guide zu: das Spielfenster antwortet nicht (Windows: „Keine Rückmeldung“)")


## Fokus kommt oder geht (main.gd _notification). Alt+Tab weg, während Uzai durchsichtig ganz oben
## liegt (Guide über dem Spiel, im Zimmer aufgestanden): Uzai gibt „immer oben“ ab – sonst blieb sein
## Bild über dem Fenster liegen, zu dem man gewechselt hatte, und nahm ihm Maus und Blick („Bild
## friert ein“). Zurück bei Uzai: wieder oben. Alt+Tab auf das im Spiel minimierte, leere Uzai: der
## Guide geht auf, statt dass ein durchsichtiges Fenster vor allem liegt.
func fokus_wechsel(rein: bool) -> void:
	if not Config.is_windows():
		return
	var w := get_window()
	if not rein:
		if _see_through_on and w.always_on_top and Launcher.in_game and not _parked and _cover_why.is_empty():
			w.always_on_top = false
			_oben_abgegeben = true
			Launcher.log_launch("Alt+Tab: Uzai hat den Fokus verloren (%s) – gibt „immer oben“ ab" % ("Guide offen" if _guide != null else _tv))
		return
	if _oben_abgegeben:
		_oben_abgegeben = false
		if _see_through_on:
			w.always_on_top = true
	if Launcher.in_game and _parked and not _overlay_mode and _guide == null and not _kulisse and Time.get_ticks_msec() - _eigen_ms > 1500:
		_alt_tab_zu_uzai()


## Video im Vollbild, und der Fokus ist weg: Liegt jetzt ein anderes Programm oder der Desktop vorn
## (st: Antwort „window-state“)? Nicht fremd: Uzai selbst und mpv. Unbekannt (kein Fenster vorn)
## zählt nicht als fremd – dann bleibt alles, wie es ist.
static func video_soll_weichen(st: Dictionary, own_pid: int, mpv_pid: int) -> bool:
	var p := int(st.get("fg_pid", 0))
	if int(st.get("fg_hwnd", 0)) == 0 or p <= 0:
		return false
	return p != own_pid and not (mpv_pid > 0 and p == mpv_pid)


func _alt_tab_zu_uzai() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var w := get_window()
	if not (Launcher.in_game and _parked and not _overlay_mode and _guide == null and w.has_focus() and w.mode != Window.MODE_MINIMIZED):
		return
	Launcher.log_launch("Alt+Tab zu Uzai während des Spiels: Guide geht auf (statt eines leeren, durchsichtigen Fensters)")
	call("toggle_guide")


# --- Spiel im Fernseher des Zimmers (src/room/fernsehspiel.gd) ----------------------------------

## Zustand (fernsehspiel.gd). Jeder Wechsel stellt ein, ob das Spiel nach vorn darf (nicht, solange du
## im Zimmer läufst, Launcher.fokus_gesperrt); dann wacht Uzai über den Fokus.
var _tv := "":
	set(z):
		var war := _tv
		Zustand.wechsel("zimmer.fernseher", Fernsehspiel.ZUSTAENDE_TV, _tv, z)
		_tv = z
		Launcher.fokus_gesperrt = Fernsehspiel.fokus_gesperrt(z)
		if z == "zimmer" and war != "zimmer":
			_tv_gen += 1
			_tv_zimmer_wache.call_deferred(_tv_gen)
var _tv_gen := 0


func tv_zustand() -> String:
	return _tv


## Das offene Zimmer (oder null).
func _tv_zimmer() -> Control:
	for l in Nav.layers:
		if is_instance_valid(l) and l.has_method("tv_wechsel"):
			return l
	return null


## Das offene Zimmer erfährt jeden Wechsel (Kamera, Hinweise, Live-Bild).
func _tv_melden() -> void:
	var zim := _tv_zimmer()
	if zim:
		zim.call("tv_wechsel", _tv)


## Im Zimmer eingelegt, das Spielfenster ist da: Die Kamera fährt in den Fernseher (zimmer_ansehen.gd
## ins_spiel), am Ende liegt das Spiel randlos vorn (main_ebenen.gd zimmer_zum_spiel). Uzai bleibt bis
## dahin vorn. Ohne Zimmer (zu, während es startete) wie jedes Spiel.
func _tv_einsteigen() -> void:
	if Config.is_windows() and Helper.available:
		Helper.run("vorhang", Vorhang.auftrag("", 0))       # falls er für einen Dialog zu war
	var zim := _tv_zimmer()
	if zim:
		zim.call("ins_spiel")
		return
	_tv = Fernsehspiel.weiter(_tv, "ende")
	await _park()


## Ein anderes Fenster ist jetzt das Spielfenster (Starter → Spiel): Die Wache folgt ihm.
func _on_game_window_changed() -> void:
	vorhang_wache()
	# Erst kam ein Starter, jetzt das Spiel: Ab jetzt die übliche Frist, bis es den Bildschirm deckt.
	if _vorhang_anlass == "starter" and _parked and Launcher.window_is_game:
		_vorhang("start")


## Bildrate, solange Uzai im Spiel ruht. Ohne Zimmer: Ruhe-Rate (set_idle, 12 Bilder/s). Wartet das
## Zimmer hinter dem Spiel (Vollbild aus dem Fernseher), bestimmt es selbst (zimmer_basis.gd ruhe_fps):
## Es zeichnet dann nichts (Uzai ist minimiert), läuft aber weiter.
func _ruhe_takt() -> void:
	var zim := _tv_zimmer()
	if _tv == "vollbild" and zim:
		set_idle(true, int(zim.call("ruhe_fps")), false)
	else:
		set_idle(true)


## Aufgestanden (fernsehspiel „zimmer“): Uzai behält den Fokus, der Controller steuert die Figur.
## Legt sich das Spiel selbst wieder nach vorn (manche tun das, auch nach einem Dialog oder Ladebild),
## nimmt Uzai den Fokus zurück – nur, wenn wirklich ein Fenster des Spiels vorn liegt, nie einem
## anderen Programm. Sonst bekäme das Spiel jeden Schritt der Figur mit.
func _tv_zimmer_wache(gen: int) -> void:
	if not Config.is_windows() or not Helper.available:
		return
	var geholt := 0
	while _tv == "zimmer" and gen == _tv_gen and is_inside_tree():
		await get_tree().create_timer(Fernsehspiel.PRUEF_S).timeout
		if _tv != "zimmer" or gen != _tv_gen or not Launcher.in_game:
			return
		if get_window().has_focus():
			continue
		var pids := await Launcher.game_pids()
		var r := await Helper.run("window-state", { "pids": pids, "hwnd": Launcher.game_hwnd() }, 2.0)
		if _tv != "zimmer" or gen != _tv_gen or not r.ok or not (r.result is Dictionary):
			continue
		if not bool((r.result as Dictionary).get("fg_game", false)):
			continue
		geholt += 1
		if geholt == 1 or geholt % 20 == 0:
			Launcher.log_launch("Fernseher: das Spiel lag vorn, während du im Zimmer läufst – Uzai nimmt den Fokus zurück (%d×)" % geholt)
		DisplayServer.window_move_to_foreground()
		Helper.run("focus", { "pid": OS.get_process_id() })


## Durchsichtig über einem anderen Fenster (Video, Spiel). Ein Fenster, das genau den ganzen
## Bildschirm bedeckt, schaltet Windows in den exklusiven Vollbildmodus; dann ist alles
## Durchsichtige schwarz (Ton ja, Bild nein). Deshalb randlos und einen Pixel größer.
func see_through(on: bool) -> void:
	var w := get_window()
	# Über Video und Spiel kein dunkler Verlauf unten.
	if is_instance_valid(_hint_fade):
		_hint_fade.visible = not on
	if on:
		_ueber_ganzen_schirm()
		get_viewport().transparent_bg = true
		w.transparent = true
		w.always_on_top = true
		_see_through_on = true
		_menue_durchsicht = false
	else:
		_see_through_on = false
		_menue_durchsicht = false
		# Hält Uzai gerade den Startbildschirm vorn (siehe _cover), bleibt es oben.
		w.always_on_top = not _cover_why.is_empty()
		w.transparent = false
		get_viewport().transparent_bg = false
		# Randlos bleiben: Mit Rahmen zeigte Windows bei jedem Minimieren und Zurückholen (Spiel-
		# und Videostart) kurz Titelleiste und blauen Fensterrand.
		w.borderless = not ("--windowed" in OS.get_cmdline_user_args())


## Randlos über den ganzen Bildschirm, einen Pixel höher (siehe see_through).
func _ueber_ganzen_schirm() -> void:
	var w := get_window()
	var scr := w.current_screen
	if w.mode != Window.MODE_WINDOWED:
		w.mode = Window.MODE_WINDOWED
	w.borderless = true
	w.position = DisplayServer.screen_get_position(scr)
	w.size = DisplayServer.screen_get_size(scr) + Vector2i(0, 1)


## Menü über dem Video, wenn mpv vorn liegt (Guide, Optionen): Uzai nur durchsichtig – das Video
## bleibt dahinter zu sehen wie ein Spiel hinter dem Guide. Obenauf hält es _cover("menu"), darum
## hier kein „immer oben“. Vorher deckte Uzais leere Fläche das Video ganz zu.
var _menue_durchsicht := false


func menue_durchsichtig(on: bool) -> void:
	if not Config.is_windows() or _see_through_on or on == _menue_durchsicht:
		return
	_menue_durchsicht = on
	var w := get_window()
	if on:
		_ueber_ganzen_schirm()
	# Wie über dem Spiel: kein dunkler Verlauf unten über dem Video.
	if is_instance_valid(_hint_fade):
		_hint_fade.visible = not on
	get_viewport().transparent_bg = on
	w.transparent = on


func _restore_window() -> void:
	if not Config.is_windows():
		return
	_eigen_ms = Time.get_ticks_msec()
	var w := get_window()
	if "--windowed" in OS.get_cmdline_user_args():
		w.mode = Window.MODE_WINDOWED
	else:
		w.borderless = true
		w.mode = Window.MODE_FULLSCREEN
	DisplayServer.window_move_to_foreground()
	Helper.run("focus", { "pid": OS.get_process_id() })
	# Zurück aus Spiel oder Video: der Zeiger bleibt weg, solange der Controller bedient.
	if Nav.device == "pad" and Config.get_value("controller.hide_mouse", true):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


# --- Die Seite als stehendes Bild (hinter dem Guide) ---------------------------------------------

## Schichten der Sichtbarkeit (CanvasItem.visibility_layer): SEITE tragen Hintergrund und Oberfläche,
## solange sie als stehendes Bild gezeigt werden (das Fenster lässt diese Schicht dann aus); RAUS bekommt für
## das eine Bild des Ablichtens alles, was nicht aufs Bild gehört (Ebenen, Tastenzeile, Mitteilungen).
const SCHICHT_RAUS := 2
const SCHICHT_SEITE := 4
## So lange bleibt das Abbild nach dem Schließen des Guide noch stehen: Die Auswahl kehrt auf die Seite
## zurück und richtet sich darunter wieder ein (Kachel wächst, Zeile rückt) – zu sehen ist davon nichts.
const AUFTAU_S := 0.35

var _stand: TextureRect           ## das Abbild der Seite, solange sie nicht gezeichnet wird
var _stand_vp: SubViewport        ## zeichnet das Abbild (dieselbe Zeichenfläche, nur die Seite)
var _stand_gen := 0               ## zählt mit jedem Abbild (ein neues macht das alte ungültig)
var _stand_wach := 0              ## zählt mit jeder Wache und jedem Auftauen (nur die jüngste gilt)
var _stand_hg_lief := true        ## lief der Hintergrund, bevor die Seite stand? (danach wieder so)
var _stand_im_bau := false        ## das Abbild ist bestellt, aber noch nicht gezeichnet


## Der Guide liegt über dem Menü: Die Seite dahinter steht still und abgedunkelt, wurde aber in jedem Bild
## voll gezeichnet – gemessen gut die Hälfte der Arbeit je Bild. In voller 4K-Auflösung ruckelte der Guide
## dadurch beim Öffnen und Blättern (Meldung zu 0.16.56). Jetzt lichtet Uzai Hintergrund und Oberfläche ab:
## ein zweiter Viewport auf derselben Zeichenfläche, der nur diese beiden zeichnet – punktgenau dasselbe Bild
## (geprüft in 1080p und 1440p), ohne Umweg über den Arbeitsspeicher. Bis der Guide zugeht, zeigt das
## Fenster nur dieses Bild; die Seite selbst bleibt, wie sie ist (sichtbar, wählbar, ihre Abläufe laufen).
##
## Das Abbild entsteht im Bild des Tastendrucks – die Auswahl steht da noch auf der Seite (die Ebene nimmt
## sie erst im nächsten Bild, layer.gd open) – und wird danach nicht mehr erneuert. Bis 0.16.59 lichtete
## Uzai nach 0,1 / 0,25 / 0,6 s neu ab: Man sah in Stufen, wie die Auswahl die Seite verließ (Reiterzeile
## rückt, Kachel schrumpft) – „Symbole und Text bewegen sich“. Jetzt steht die Seite so, wie sie beim Druck
## war, und kommt genau so zurück (seite_auftauen).
func seite_anhalten() -> void:
	# Steht sie schon (der Guide ging zu und gleich wieder auf, oder er macht dem Schnellmenü Platz):
	# Sie bleibt stehen, ein laufendes Auftauen entfällt.
	if is_instance_valid(_stand_vp):
		_stand_wach += 1
		_stand_wache(_stand_wach)
		return
	if not is_instance_valid(shell) or not shell.visible or not background.visible \
			or _overlay_mode or Launcher.in_game or Launcher.is_starting() or Video.watching() or DisplayServer.get_name() == "headless":
		return
	_stand_gen += 1
	var gen := _stand_gen
	var w := get_window()
	var vp := SubViewport.new()
	vp.size = w.size
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.gui_disable_input = true
	vp.world_2d = w.world_2d
	vp.canvas_cull_mask = 1 | SCHICHT_SEITE
	# Wie das Fenster zeichnet: Filter, Raster, Schärfe der Schrift – sonst weicht das Abbild sichtbar ab.
	vp.canvas_item_default_texture_filter = w.canvas_item_default_texture_filter
	vp.canvas_item_default_texture_repeat = w.canvas_item_default_texture_repeat
	vp.snap_2d_transforms_to_pixel = w.snap_2d_transforms_to_pixel
	vp.snap_2d_vertices_to_pixel = w.snap_2d_vertices_to_pixel
	vp.msaa_2d = w.msaa_2d
	vp.use_hdr_2d = w.use_hdr_2d
	vp.oversampling_override = w.get_oversampling()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	vp.canvas_transform = w.get_final_transform()
	_stand_vp = vp
	background.visibility_layer = SCHICHT_SEITE
	shell.visibility_layer = SCHICHT_SEITE
	# Der Hintergrund treibt langsam (Lichter, Farbe): solange er als Bild steht, hält er an – sonst spränge
	# er beim Schließen von der abgelichteten Lage in die, bis zu der er inzwischen getrieben wäre.
	_stand_hg_lief = background.is_processing()
	background.set_process(false)
	background.pause_motion(true)
	_stand_im_bau = true
	await _seite_ablichten()
	if gen != _stand_gen or not is_instance_valid(vp) or not is_instance_valid(shell):
		return
	_stand_im_bau = false
	_stand = TextureRect.new()
	_stand.texture = vp.get_texture()
	_stand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stand.stretch_mode = TextureRect.STRETCH_SCALE
	_stand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_stand)
	add_child(_stand)
	move_child(_stand, shell.get_index() + 1)
	w.canvas_cull_mask = w.canvas_cull_mask & ~SCHICHT_SEITE
	_stand_wach += 1
	_stand_wache(_stand_wach)


## Ist das Abbild bestellt, aber noch nicht gezeichnet? (Der Guide nimmt die Auswahl erst danach.)
func seite_im_bau() -> bool:
	return _stand_im_bau


## Solange die Seite steht: nachsehen, ob sie wieder selbst gezeichnet werden muss.
func _stand_wache(wache: int) -> void:
	while wache == _stand_wach and is_inside_tree():
		await get_tree().create_timer(0.2).timeout
		if wache == _stand_wach and _seite_muss_weiter():
			_seite_weiter()


## Der Guide ist zu. Die Auswahl steht wieder auf der Seite, richtet sich dort aber erst ein; das Abbild
## zeigt die Seite schon so, wie sie danach dasteht. Es bleibt darum noch AUFTAU_S stehen und weicht dann
## der Seite, ohne dass sich etwas bewegt. Wer in der Zeit schon weiterdrückt, bekommt die Seite sofort.
func seite_auftauen() -> void:
	if not is_instance_valid(_stand):
		_seite_weiter()
		return
	_stand_wach += 1
	var wache := _stand_wach
	var fokus := Nav.focused()
	var bis := Time.get_ticks_msec() + int(AUFTAU_S * 1000.0)
	while Time.get_ticks_msec() < bis:
		await get_tree().process_frame
		if wache != _stand_wach:
			return
		if Nav.focused() != fokus or _seite_muss_weiter(false):
			break
	if wache == _stand_wach:
		_seite_weiter()


## Einmal ablichten: Für dieses eine Bild steht alles andere auf der Schicht, die der zweite Viewport auslässt.
func _seite_ablichten() -> void:
	if not is_instance_valid(_stand_vp):
		return
	var raus := {}
	for ch in get_children() + get_tree().root.get_children():
		var ci := ch as CanvasItem
		if ci != null and ci != self and ci != background and ci != shell:
			raus[ci] = ci.visibility_layer
			ci.visibility_layer = SCHICHT_RAUS
	_stand_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	for ci: CanvasItem in raus:
		if is_instance_valid(ci):
			ci.visibility_layer = int(raus[ci])


## Muss die Seite wieder selbst gezeichnet werden? Guide zu (mit_guide), ein Spiel startet, die Oberfläche
## ist neu gebaut oder das Fenster hat eine andere Größe.
func _seite_muss_weiter(mit_guide := true) -> bool:
	return (mit_guide and not is_instance_valid(_guide)) or not is_instance_valid(_stand) or not is_instance_valid(_stand_vp) \
			or not is_instance_valid(shell) or not shell.visible or _overlay_mode or Launcher.in_game or Launcher.is_starting() \
			or _stand_vp.size != get_window().size


## Die Seite wieder selbst zeichnen (Guide zu, Bereichswechsel, Spielstart).
func _seite_weiter() -> void:
	if not is_instance_valid(_stand_vp) and not is_instance_valid(_stand):
		return
	_stand_gen += 1
	_stand_wach += 1
	_stand_im_bau = false
	var w := get_window()
	w.canvas_cull_mask = w.canvas_cull_mask | SCHICHT_SEITE
	if is_instance_valid(background):
		background.visibility_layer = 1
		background.set_process(_stand_hg_lief)
		background.pause_motion(false)
	if is_instance_valid(shell):
		shell.visibility_layer = 1
	if is_instance_valid(_stand):
		_stand.queue_free()
	if is_instance_valid(_stand_vp):
		_stand_vp.queue_free()
	_stand = null
	_stand_vp = null


# --- Bildschirm (src/core/bildschirm.gd) ---------------------------------------------------------

var _schirm := -1                 ## Bildschirm, auf dem Uzai liegt (Nummer von Godot)
var _schirm_neu := 0              ## so viele Sekunden liegt das Fenster schon auf einem anderen


## One line in logs/start.log: displays at startup, which window was in front, display changes.
## Helps diagnose problems on a PC, such as no input until Guide is pressed, or a pixelated image on a second display.
func _start_log(text: String) -> void:
	if not Library.demo:
		Logdatei.zeile(Config.path("logs/start.log"), "%s %s" % [Config.VERSION, text], 60000)


## Beim Start: auf den gewählten Bildschirm (falls Uzai nicht schon dort geöffnet wurde), merken, wo es
## liegt, und die Lage ins Protokoll. Im scharfen Lauf: Sind alle Bildschirme gleich skaliert, braucht es
## den Neustart beim nächsten Mal nicht (display.dpi_gleich).
func _schirm_start() -> void:
	var w := get_window()
	var anzahl := DisplayServer.get_screen_count()
	var wahl := Bildschirm.index(Config.get_value("display.screen", Bildschirm.AUTO), anzahl)
	if wahl >= 0 and wahl != w.current_screen and not Library.demo:
		w.current_screen = wahl
	_schirm = w.current_screen
	var teile := PackedStringArray()
	var flaechen: Array = []
	var dpis: Array = []
	for i in anzahl:
		var g := DisplayServer.screen_get_size(i)
		flaechen.append(Rect2i(DisplayServer.screen_get_position(i), g))
		dpis.append(DisplayServer.screen_get_dpi(i))
		teile.append("%d: %d×%d, %d dpi%s" % [i + 1, g.x, g.y, int(dpis[i]), " (Haupt)" if i == DisplayServer.get_primary_screen() else ""])
	_start_log("Start: Bildschirme [%s], Uzai auf %d, gewählt %s, scharf je Bildschirm: %s" % ["; ".join(teile), _schirm + 1,
			str(Config.get_value("display.screen", Bildschirm.AUTO)), "ja" if Bildschirm.eigen else "nein"])
	if Library.demo:
		return
	if Bildschirm.eigen:
		var gleich := Bildschirm.anordnung(flaechen) if Bildschirm.gleich_skaliert(dpis) else ""
		if gleich != str(Config.get_value("display.dpi_gleich", "")):
			Config.set_value("display.dpi_gleich", gleich)
	# Die Größe der Oberfläche von diesem Bildschirm (zuletzt lief Uzai vielleicht auf dem anderen).
	var gemerkt := Bildschirm.skala_von(Config.get_value("display.skalen", {}), _schirm_key())
	if gemerkt > 0.0 and not is_equal_approx(gemerkt, UzTheme.ui_scale()):
		Config.set_value("theme.ui_scale", gemerkt)


## In den Einstellungen gewählt: Uzai zieht gleich um; den Rest macht der Sekundentakt.
func _schirm_gewaehlt() -> void:
	var w := get_window()
	var wahl := Bildschirm.index(Config.get_value("display.screen", Bildschirm.AUTO), DisplayServer.get_screen_count())
	if wahl >= 0 and wahl != w.current_screen:
		w.current_screen = wahl


## Jede Sekunde (main._tick): Liegt Uzai auf einem anderen Bildschirm als bisher – verschoben mit
## Win+Umschalt+Pfeil, in den Einstellungen gewählt, der alte abgezogen? Erst wenn es dort zwei Sekunden
## liegt (beim Umschalten springt die Nummer kurz) und nie neben einem Spiel.
func _schirm_takt(bereit: bool) -> void:
	var w := get_window()
	if not bereit or Library.demo or Launcher.in_game or Launcher.is_starting() or _overlay_mode or w.mode == Window.MODE_MINIMIZED:
		_schirm_neu = 0
		return
	var s := w.current_screen
	if s < 0 or s == _schirm:
		_schirm_neu = 0
		return
	_schirm_neu += 1
	if _schirm_neu < 2:
		return
	_schirm_neu = 0
	_schirm = s
	_schirm_gewechselt()


## Uzai liegt auf einem anderen Bildschirm: Vollbild in dessen Größe, Bildrate des Menüs nach seiner
## Bildwiederholrate, Größe der Oberfläche für ihn.
func _schirm_gewechselt() -> void:
	var w := get_window()
	var g := DisplayServer.screen_get_size(_schirm)
	var p := DisplayServer.screen_get_position(_schirm)
	_start_log("Bildschirm gewechselt: jetzt %d (%d×%d, %d dpi), Fenster %d×%d" % [_schirm + 1, g.x, g.y, DisplayServer.screen_get_dpi(_schirm),
			w.size.x, w.size.y])
	var passt := absi(w.size.x - g.x) <= 2 and absi(w.size.y - g.y) <= 2 and absi(w.position.x - p.x) <= 2 and absi(w.position.y - p.y) <= 2
	if not passt and w.mode == Window.MODE_FULLSCREEN and DisplayServer.get_screen_count() > 1:
		# Mit Win+Umschalt+Pfeil verschoben: Windows lässt Größe und Lage vom alten Bildschirm stehen. Godot
		# legt ein Vollbildfenster nur beim Wechsel des Bildschirms neu aus (und ändert im Vollbild sonst weder
		# Größe noch Lage) – also einmal hinüber und zurück, beides vor dem nächsten Bild.
		var ziel := _schirm
		w.current_screen = (ziel + 1) % DisplayServer.get_screen_count()
		w.current_screen = ziel
	if not OS.low_processor_usage_mode:
		set_idle(false)
	_schirm_groesse()


func _schirm_key() -> String:
	var s := _schirm if _schirm >= 0 else get_window().current_screen
	return Bildschirm.schluessel(DisplayServer.screen_get_size(s), DisplayServer.screen_get_dpi(s))


## Die Größe der Oberfläche gilt für den Bildschirm, auf dem Uzai gerade liegt.
func _schirm_merken() -> void:
	if Library.demo:
		return
	var alt: Variant = Config.get_value("display.skalen", {})
	var key := _schirm_key()
	if is_equal_approx(Bildschirm.skala_von(alt, key), UzTheme.ui_scale()):
		return
	Config.set_value("display.skalen", Bildschirm.skala_merken(alt if alt is Dictionary else {}, key, UzTheme.ui_scale()))


## Größe der Oberfläche für den neuen Bildschirm: die von dort gemerkte; kennt Uzai ihn noch nicht,
## stellt es sich ein wie beim ersten Start (display_fit.gd) und sagt es.
func _schirm_groesse() -> void:
	var gemerkt := Bildschirm.skala_von(Config.get_value("display.skalen", {}), _schirm_key())
	if gemerkt > 0.0:
		if not is_equal_approx(gemerkt, UzTheme.ui_scale()):
			Config.set_value("theme.ui_scale", gemerkt)
		return
	var hier := _schirm
	var seen: Dictionary = await DisplayFit.detect(get_window())
	if hier != _schirm or not is_inside_tree():
		return
	var kind := DisplayFit.apply(seen, false)
	_schirm_merken()
	if kind != "":
		Toasts.show_toast(DisplayFit.KIND_DONE[kind], "Oberfläche %d %% (Einstellungen → Aussehen)." % roundi(UzTheme.ui_scale() * 100.0),
				"tv", { "ms": 7000 })
