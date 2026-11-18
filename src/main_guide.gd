extends "res://src/main_discord.gd"
## Hauptbildschirm, Schicht über main_discord.gd: Guide-Taste und Controller-Tasten (Aufnahme,
## Schnellstart), Ausschalten von Uzai und PC, Freunde, Nachrichten und Musik als Mitteilung und
## die Werkzeuge im Guide.

const PowerOff := preload("res://src/ui/power_off.gd")
const GuideHold := preload("res://src/core/guide_hold.gd")
const FriendActions := preload("res://src/ui/layers/friend_actions.gd")
const MusicActions := preload("res://src/ui/layers/music_actions.gd")
const AppTastatur := preload("res://src/ui/app_tastatur.gd")
const SpielSymbol := preload("res://src/library/spiel_symbol.gd")
const _STATE_TEXT := { "online": "Online", "away": "Abwesend", "idle": "Abwesend", "busy": "Beschäftigt", "snooze": "Abwesend", "dnd": "Bitte nicht stören" }

var rest: Node                ## Ruhemodus und Spielstände (src/core/rest.gd)
var perf: Node                ## Leistungsziele messen (src/core/perf.gd)
var saver: Node               ## Ruhebildschirm (src/core/saver.gd)
var pip: Node                 ## Bild in Bild (src/core/pip.gd), hängt an Video (überlebt _build)
var _boot: Control
var _video_overlay := false
var _guide_gen := 0


# --- Freunde, Nachrichten, Musik --------------------------------------------------

## Discord-Anruf kommt rein: außerhalb des Spiels geht der Guide auf und die Anrufkarte steht
## mittig darüber. Im Spiel kommt ein Pop-up über dem Spiel; die Guide-Taste öffnet dann die Karte
## (Uzai holt sich nie ungefragt vor ein laufendes Spiel).
func _on_incoming_call(info: Dictionary) -> void:
	# Kinderprofil mit Chats aus: kein Anruf geht auf.
	if Config.kid_blocks("chats"):
		return
	if Launcher.in_game and not Launcher.guide_open:
		Notify.call_popup(info)
		return
	if not (_guide and is_instance_valid(_guide)) and not Video.active:
		toggle_guide("discord")
		await get_tree().process_frame
		await get_tree().process_frame
	open_incoming_call(info)


func open_friend(f: Dictionary, kind := "steam", server_id := "") -> void:
	var l = FriendActions.new()
	l.friend = f
	l.kind = kind
	l.server_id = server_id
	open_layer(l)


## Liste aller erreichbaren Freunde (Steam online, Discord-Server), Auswahl ruft cb(kind, freund).
func open_friend_picker(head: String, cb: Callable, steam_only := false) -> void:
	var s = SheetLayer.new()
	s.setup(head, "Freunde", 720)
	s.fill_func = func(sheet) -> void:
		for f in Social.steam_friends:
			if f.state == "offline":
				continue
			var it = ListItemC.new()
			# Zweite Zeile: das Spiel oder der Zustand – die Quelle steht schon rechts.
			it.setup(str(f.name), Library.friend_game_title(str(f.game), str(f.get("game_id", ""))) if str(f.game) != ""
					else str(_STATE_TEXT.get(str(f.state), "Online")), "Steam")
			it.avatar = true
			it.image_url = str(f.avatar)
			it.status = str(f.state)
			var fd: Dictionary = f
			it.activated.connect(func() -> void:
				sheet.close()
				cb.call("steam", fd)
			)
			sheet.add_row(it)
		# Discord-Freunde (Direktnachrichten über das Social SDK), wenn verbunden – nicht beim
		# Einladen ins Spiel, das geht nur über Steam.
		if not steam_only and DiscordChat.can_send():
			for f2 in DiscordChat.friends:
				if str(f2.state) == "offline":
					continue
				var it2 = ListItemC.new()
				it2.setup(str(f2.name), str(f2.game) if str(f2.game) != "" else str(_STATE_TEXT.get(str(f2.state), "Online")), "Discord")
				it2.avatar = true
				it2.image_url = str(f2.avatar)
				it2.status = str(f2.state)
				var dd: Dictionary = f2
				it2.activated.connect(func() -> void:
					sheet.close()
					cb.call("discord", dd)
				)
				sheet.add_row(it2)
		if sheet.content.get_child_count() == 0:
			sheet.add_label("Niemand online.", "m", "muted")
	open_layer(s)


## Nachricht verschicken – nur über Uzais eigenen Steam-Chat, nie über ein anderes Fenster.
func send_message(kind: String, f: Dictionary, text: String) -> void:
	if Config.kid_stop("chats"):
		return
	Toasts.show_toast("Wird gesendet …", "an " + str(f.get("name", "")), "chat", { "ms": 1500, "quiet": true })
	var err := ""
	if kind == "steam" and SteamChat.logged_in():
		# Direkt über Steam: kein Fensterwechsel, Uzai bleibt, wo es ist.
		err = await SteamChat.send(str(f.get("id", "")), text)
		if err == "":
			Toasts.show_toast("Gesendet an " + str(f.get("name", "")), text, "check", { "sound": "select", "go": open_chat.bind(f), "go_text": "Chat öffnen" })
		else:
			Toasts.show_toast("Nicht gesendet", err, "warning")
		return
	if kind == "steam":
		# Nicht angemeldet: Uzai öffnet die QR-Anmeldung, die Nachricht wartet und geht danach
		# raus. Kein Fensterwechsel, Steam kommt nicht nach vorn.
		err = await Social.send_steam(str(f.get("id", "")), text)
		if err != "":
			Toasts.show_toast("Erst anmelden", err, "steam")
		return
	# Discord: Direktnachricht über das Social SDK (ohne die Discord-App nach vorn zu holen).
	var did := str(f.get("dm_id", f.get("id", ""))) if bool(f.get("dm", false)) or f.has("dm_id") else ""
	if did != "" and DiscordChat.can_send():
		err = await DiscordChat.send(did, text)
		if err == "":
			Toasts.show_toast("Gesendet an " + str(f.get("name", "")), text, "check", { "sound": "select", "go": open_discord_chat.bind(f), "go_text": "Chat öffnen" })
		else:
			Toasts.show_toast("Nicht gesendet", err, "warning")
		return
	Toasts.show_toast("Discord-Nachrichten einrichten", DiscordChat.error if DiscordChat.error != "" else "Unter Einstellungen → Konten → Discord-Nachrichten.",
			"chat")


## Freund zum laufenden Steam-Spiel einladen – direkt über Uzai, ohne Steam-Overlay.
func invite_friend(f: Dictionary) -> void:
	var g: Dictionary = Launcher.current
	Toasts.show_toast("Einladung wird geschickt …", "an " + str(f.get("name", "")), "plus", { "ms": 2000, "quiet": true })
	var r := await Social.invite_to_game(f, g)
	if r.get("how", "") == "link":
		# Der Chat war kurz vorn: Uzai bzw. das Spiel wieder nach vorn holen.
		if _guide != null or _overlay_mode:
			Helper.run("focus", { "pid": OS.get_process_id() })
		elif Launcher.in_game:
			Launcher.focus_game()
	if r.ok:
		Toasts.show_toast("Eingeladen: " + str(f.get("name", "")), str(r.text), "check", { "sound": "select", "image": str(f.get("avatar", "")) })
	else:
		Toasts.show_toast("Einladen ging nicht", str(r.text), "warning", { "ms": 6000 })


## Erfolge mit einem Steam-Freund vergleichen: erst das Spiel wählen.
func open_compare_picker(f: Dictionary) -> void:
	var list: Array = Library.sorted(Library.by_system("steam"), "recent")
	var cur := Library.get_game("steam:" + str(f.get("game_id", "")))
	if not cur.is_empty():
		list.erase(cur)
		list.push_front(cur)
	if list.is_empty():
		Toasts.show_toast("Keine Steam-Spiele", "Vergleichen geht mit Spielen aus deiner Steam-Bibliothek.", "trophy")
		return
	var opts: Array = []
	for g in list.slice(0, 40):
		opts.append([str(g.id), Library.display_title(g) + ("  ·  spielt %s gerade" % f.name if g == cur else "")])
	open_choice("Welches Spiel vergleichen?", opts, "", func(gid: Variant) -> void:
		var l = _rare("game_achievements").new()
		l.game = Library.get_game(str(gid))
		l.compare = f
		open_layer(l)
	, "mit " + str(f.get("name", "")))


func open_music_actions() -> void:
	var l = MusicActions.new()
	open_layer(l)


func open_spotify_playlists() -> void:
	if Music.mode() != "spotify" or not Music.has_spotify():
		Toasts.show_toast("Playlists brauchen Spotify", "Unter Einstellungen → Konten verbinden", "music")
		return
	await Music.load_playlists()
	var s = SheetLayer.new()
	s.setup("Playlists", "Spotify", 760)
	s.fill_func = func(sheet) -> void:
		for p in Music.playlists:
			var it = ListItemC.new()
			it.setup(str(p.name), "%d Titel" % int(p.count))
			it.image_url = str(p.art)
			it.set_meta("uz_hint_a", "Abspielen")
			var uri := str(p.uri)
			it.activated.connect(func() -> void:
				Music.play_playlist(uri)
				sheet.close()
			)
			sheet.add_row(it)
	open_layer(s)


# --- Werkzeuge im Guide ------------------------------------------------------------

## Bildschirmfoto von allem, was gerade zu sehen ist (auch Steam-Spiele), nach Bilder\Uzai.
func take_screenshot() -> void:
	if _guide and is_instance_valid(_guide):
		_guide.close()
	await get_tree().create_timer(0.6).timeout
	var title := str(Launcher.current.get("title", "")) if Launcher.in_game else ("Video" if Video.active else "Uzai")
	# Erst über FFmpeg (Desktop-Duplizierung: auch Vollbild-Spiele), sonst wie bisher über den Helfer.
	var own := await Capture.screenshot(title)
	if own != "":
		Toasts.show_toast("Bildschirmfoto gespeichert", own.get_file(), "camera",
				{ "image": own, "sound": "shutter", "force": true, "go": open_captures, "go_text": "Aufnahmen" })
		return
	var r := await Helper.run("screenshot", { "title": title }, 10.0)
	if r.ok:
		Toasts.show_toast("Bildschirmfoto gespeichert", str(r.result.get("file", "")).get_file(), "camera",
				{ "image": str(r.result.get("file", "")), "sound": "shutter", "force": true })
	else:
		Toasts.show_toast("Bildschirmfoto ging nicht", Helper.klartext(str(r.get("error", ""))), "warning")


## Die letzten Sekunden als Clip speichern. Standard: Uzais eigene Aufnahme (Rollpuffer, siehe
## capture.gd) – der Clip endet, als der Guide aufging. Auf Wunsch wie früher über die Aufnahme von
## Windows (Game Bar) oder NVIDIA: dann drückt Uzai deren Tastenkürzel im Spiel.
func save_clip() -> void:
	if _ffmpeg_fehlt():
		return
	if _guide and is_instance_valid(_guide):
		_guide.close()
	if Capture.via_uzai():
		Pads.pulse("clip")
		Capture.save_from_guide()
		return
	await get_tree().create_timer(0.6).timeout
	var pids := await Launcher.game_pids()
	var keys := str(Config.get_value("system.clip_keys", "WIN+ALT+G"))
	if str(Capture.opt("via")) == "nvidia" and keys == "WIN+ALT+G":
		keys = "ALT+F10"
	# Die Taste geht nur ans Spiel und nur, wenn es vorn ist (der Helfer prüft das).
	var r := await Helper.run("keys", { "pids": pids, "hwnd": Launcher.game_hwnd(), "keys": keys })
	var why := HelperScript.keys_text(r, "Das Tastenkürzel unter Einstellungen → Aufnahmen prüfen.")
	if why == "":
		Toasts.show_toast("Clip wird gespeichert", "Über Windows, NVIDIA oder AMD.", "camera",
				{ "ms": 4000 })
		Pads.pulse("clip")
	else:
		Toasts.show_toast("Clip ging nicht", why, "warning")


## Steams Overlay im Spiel auf- oder zumachen: der Guide geht zu, dann bekommt das Spiel die
## Overlay-Tasten (Einstellungen, sonst Umschalt+Tab). So geht es ohne Tastatur weg, etwa wenn
## Steam es nach einer Remote-Play-Einladung offen lässt.
func steam_overlay() -> void:
	Launcher.rp_overlay_toggled()
	if _guide and is_instance_valid(_guide):
		_guide.close()
	await get_tree().create_timer(0.6).timeout
	if not Launcher.in_game:
		return
	var pids := await Launcher.game_pids()
	var r := await Helper.run("keys", { "pids": pids, "hwnd": Launcher.game_hwnd(), "keys": str(Config.get_value("system.steam_overlay_keys", "SHIFT+TAB")) })
	var why := HelperScript.keys_text(r, "Das Tastenkürzel unter Einstellungen → Im Spiel prüfen.")
	if why != "":
		Toasts.show_toast("Steam-Overlay ging nicht", why, "warning")


var _power_off: Control
var _closing := false           ## Uzai beendet sich gerade (ein weiteres Schließen beendet sofort)


# --- Ausschalten ------------------------------------------------------------------------------

## Ausschalt-Animation (src/ui/power_off.gd) auf einem der Wege, auf denen Uzai sich schließt oder
## den PC ausschaltet (PowerOff.REASONS); danach beendet der Aufrufer. Läuft schon eine (zweites
## Alt+F4, Windows schließt Uzai beim Herunterfahren): sofort beenden, nie aufhalten. Ist die
## Einstellung „Ausschalt-Animation“ aus oder das Fenster nicht zu sehen (minimiert, im Spiel
## geparkt, durchsichtig über einem Spiel oder Video): keine Animation. hold: danach schwarz
## stehen bleiben, bis power_on_again (Ruhezustand, Neustart, Herunterfahren).
func power_off(reason: String, hold := false) -> void:
	if is_instance_valid(_power_off):
		get_tree().quit()
		return
	if reason in ["quit", "quit_full", "wm_close", "hung", "restart", "shutdown"]:
		perf.log_session()
	# Bild in Bild endet mit Uzai (auch Schlafen, Neustart, Herunterfahren).
	if pip and pip.active():
		pip.power_off()
	var w := get_window()
	var shown := PowerOff.window_shown(w.visible, w.mode, DisplayServer.get_name() == "headless", _parked, _overlay_mode or _video_overlay)
	var mode := PowerOff.mode_for(reason, bool(Config.get_value("system.power_off", true)), shown, _reduced_motion())
	if mode == "aus":
		# Wie früher: Selbst beendet, blendet Uzai wenigstens kurz auf Schwarz.
		if shown and reason in ["quit", "quit_full", "hung"]:
			await _veil(true)
		return
	set_idle(false)
	var holder := CanvasLayer.new()
	holder.layer = 128
	_power_off = PowerOff.new()
	_power_off.mode = mode
	_power_off.hold = hold
	holder.add_child(_power_off)
	# Aufgeschoben: Wer gerade an alle Knoten verteilt (Schließen-Signal), lässt keine neuen zu.
	get_tree().root.add_child.call_deferred(holder)
	await _power_off.finished


## Ruhezustand, Neustart, Herunterfahren: erst die Animation, dann der Befehl an Windows. Das Bild
## bleibt schwarz; nach dem Aufwachen (oder wenn Windows nicht ausschaltet, etwa weil ein Programm
## es aufhält) blendet Uzai wieder auf.
func power_off_pc(action: String) -> void:
	if action in ["restart", "shutdown"]:
		# Windows beendet Uzai dabei womöglich hart: kein Absturz (src/core/crash_guard.gd).
		Config.run_where("aus")
	await power_off(action, true)
	Helper.run("power", { "action": action })
	await get_tree().create_timer(2.5 if action == "sleep" else 8.0, true, false, true).timeout
	power_on_again()


func power_on_again() -> void:
	if is_instance_valid(_power_off):
		_power_off.reveal()
	_power_off = null


## „Animationen reduzieren“ (falls eingestellt): kurze Fassung ohne Bewegung.
func _reduced_motion() -> bool:
	return bool(Config.get_value("theme.reduce_motion", false))


## Alt+F4, Schließen in der Taskleiste (auto_accept_quit ist aus): Animation, dann ganz beenden – ohne Wächter
## für die Guide-Taste (Helper sperrt ihn beim selben Signal). Gespeichert ist da schon (_notification).
func _on_close_request() -> void:
	if Remote.is_second or _closing:
		# Zweites Alt+F4 (oder Windows drängt beim Herunterfahren): sofort.
		get_tree().quit()
		return
	_closing = true
	_quit_failsafe()
	# Das Signal kommt mitten im Verteilen an alle Knoten; neue Knoten erst im nächsten Bild.
	await get_tree().process_frame
	await power_off("wm_close")
	get_tree().quit()


## Was auch immer beim Ausschalten hängt: Uzai beendet sich spätestens nach CAP + 0,5 s.
func _quit_failsafe() -> void:
	get_tree().create_timer(PowerOff.CAP + 0.5, true).timeout.connect(func() -> void: get_tree().quit())


## Eine Desktop-Verknüpfung will ein Spiel starten (Uzai lief schon oder wurde dafür gestartet).
func _on_remote_launch(game_id: String) -> void:
	var g := Library.get_game(game_id)
	if g.is_empty():
		_restore_window()
		Toasts.show_toast("Spiel nicht gefunden",
				"Spiel nicht in der Bibliothek. Verknüpfung neu anlegen.", "warning")
		return
	if Launcher.in_game:
		Toasts.show_toast("Es läuft schon ein Spiel", str(Launcher.current.get("title", "")), "games")
		return
	_restore_window()
	launch(g)


## Verknüpfung auf dem Desktop oder im Startmenü, die das Spiel direkt über Uzai startet
## (mit Spielzeit, Bildfilter, Guide). Symbol: das des Spiels (spiel_symbol.gd), sonst Uzais.
func create_shortcut(g: Dictionary, where := "desktop") -> void:
	if not Config.is_windows():
		Toasts.show_toast("Nur unter Windows", "Verknüpfungen legt Uzai nur am Windows-PC an.", "warning")
		return
	var icon := await _shortcut_icon(g)
	var r := await Helper.run("shortcut", {
		"name": Library.display_title(g), "target": OS.get_executable_path().replace("/", "\\"),
		# Ohne Fenster (--headless): Läuft Uzai schon, gibt die Verknüpfung nur weiter, statt kurz ein
		# zweites Vollbild aufblitzen zu lassen (Remote startet sich sonst selbst mit Fenster neu).
		"args": "--headless -- --launch=%s" % str(g.get("id", "")), "icon": icon.replace("/", "\\"), "where": where,
	})
	if r.ok:
		Toasts.show_toast("Verknüpfung angelegt", "%s · %s" % [Library.display_title(g), "Desktop" if where == "desktop" else "Startmenü"], "link",
				{ "sound": "select", "go": open_game_note.bind(g), "go_text": "Zum Spiel" })
	else:
		Toasts.show_toast("Verknüpfung ging nicht", Helper.klartext(str(r.get("error", ""))), "warning")


## Symbol für die Verknüpfung: Emulator bzw. Programmdatei, sonst die im Installationsordner (im
## Faden gesucht), sonst das Symbol aus der Bibliothek als .ico, erst zuletzt Uzai.
func _shortcut_icon(g: Dictionary) -> String:
	var emu := Config.emulator(str(g.get("emulator", Config.system(str(g.get("system", ""))).get("emulator", ""))))
	var icon := SpielSymbol.direkt(g, str(emu.get("exe", "")))
	var dir := SpielSymbol.ordner(g)
	if icon == "" and dir != "" and DirAccess.dir_exists_absolute(dir):
		var exe: Variant = await Arbeit.ergebnis(SpielSymbol.aus_ordner.bind(dir, str(g.get("title", ""))), Arbeit.LANG)
		icon = exe if exe is String else ""
	if icon == "":
		icon = SpielSymbol.ico_schreiben(Media.local_path(g, "icon"), Config.path("cache/symbole"), str(g.get("id", "")))
	return icon if icon != "" else OS.get_executable_path()


## Guide-Taste vom Controller-Wächter des Helfers (kommt auch, wenn ein Spiel vorn ist).
func _on_pad_event(kind: String) -> void:
	# Der Vorhang hat sich zugezogen, weil das Spielfenster verschwand (main_fenster.gd).
	if kind == "vorhang":
		_vorhang_ausgeloest()
		return
	if kind == "guide":
		toggle_guide("", "helper")
	elif kind == "guide-up" or kind == "guide-hold":
		_guide_press_done(_hold.helper(kind))
	elif kind == "clip":
		clip_hotkey("chord")
	elif kind == "app-tastatur" or kind == "app-textfeld":
		# Textfeld in einer eigenen App: Uzais Tastatur bzw. kurz „Y Tastatur“ (app_tastatur.gd).
		AppTastatur.melden(self, kind)


## Clip ohne Menü: Guide halten + X (Helfer, Xbox-Controller) oder die Share-/Aufnahme-Taste
## (Xbox Series, Switch Pro; über Godot). Der Guide, der beim Halten aufging, schließt gleich wieder;
## der Clip endet beim Druck der Guide-Taste, der Guide ist also nicht darin.
func clip_hotkey(src := "") -> void:
	# Die gehaltene Guide-Taste gehört zum Clip: kein Schnellmenü, und der Guide von eben geht wieder zu.
	if src == "chord":
		_hold.cancel()
	if not Capture.via_uzai() or not bool(Capture.opt("hotkey")):
		return
	if src == "chord" and _guide and is_instance_valid(_guide):
		_guide.close()
	Pads.pulse("clip")
	Capture.hotkey(src)


## Längere Aufnahme starten oder beenden (höchstens 10 Minuten).
func toggle_record() -> void:
	if not Capture.recording and _ffmpeg_fehlt():
		return
	if _guide and is_instance_valid(_guide):
		_guide.close()
	Capture.toggle_record()


## Fehlt FFmpeg für Uzais eigene Aufnahme: fragen, solange der Guide noch offen ist. Ginge der
## Guide zuerst zu, käme das Spiel nach vorn und die Frage läge unbedienbar dahinter. „Laden“ lädt
## im Hintergrund und schließt dann den Guide; das Spiel läuft weiter.
func _ffmpeg_fehlt() -> bool:
	if not (Capture.via_uzai() and Config.is_windows() and not Capture.has_ffmpeg()):
		return false
	load("res://src/ui/layers/captures.gd").ask_install(self, func() -> void:
		if _guide and is_instance_valid(_guide):
			_guide.close())
	return true


## Galerie „Aufnahmen“: Clips und Bildschirmfotos nach Spielen, abspielen, kürzen, teilen.
## focus: diese Aufnahme gleich wählen (z. B. „Ansehen“ aus einer Mitteilung im Spiel).
func open_captures(focus := "") -> void:
	var l = load("res://src/ui/layers/captures.gd").new()
	l.focus_path = focus
	open_layer(l)


# --- Guide-Taste ---------------------------------------------------------------------------------

var _guide_opening := false     ## Guide wird gerade geöffnet (wartet z. B. auf den Bildfilter)
var _guide_cancel := false      ## zweiter Druck während des Öffnens: gar nicht erst aufgehen
var _press := {}                ## letzter Druck der Guide-Taste: Quelle -> Zeit (ms)
var _hold := GuideHold.new()    ## Guide-Taste kurz (Guide) oder gehalten (Schnellmenü)
var _hold_menu := false         ## gehalten, während der Guide noch aufging (im Spiel): er geht als Schnellmenü auf

## Wie lange zwei Meldungen aus verschiedenen Quellen als derselbe Druck gelten. Godot und der
## Helfer melden die Guide-Taste beide (der Helfer fragt alle 30 ms ab, im Spiel auch später);
## beim Akkord View + Start kommt Start allein ("menu") schon vorweg – der Akkord danach gehört
## dazu, solange Start gehalten ist. Aus derselben Quelle ist jeder Druck echt: zweimal schnell
## drücken macht den Guide auf und wieder zu.
const _SAME_PRESS := { "helper|pad": 700, "combo|helper": 700, "combo|menu": 3000, "helper|menu": 3000 }


## Gehört dieser Druck zu einem eben gemeldeten (andere Quelle, dieselbe Geste)?
func _guide_dup(src: String) -> bool:
	var now := Time.get_ticks_msec()
	if src == "":
		return false
	# Prellen: dieselbe Quelle meldet nur einmal je Druck.
	if _press.has(src) and now - int(_press[src]) < 90:
		return true
	# Start allein fängt immer einen neuen Druck an; zu ihm gehört nur der Akkord, der folgt.
	if not _press.has(src) and src != "menu":
		for other in _press.keys():
			if str(other) == "menu" and src == "helper" and not Nav.start_held():
				continue
			var both := [src, str(other)]
			both.sort()
			var pair := "|".join(PackedStringArray(both))
			if now - int(_press[other]) < int(_SAME_PRESS.get(pair, 0)):
				_press[src] = now
				return true
	_press = { src: now }
	return false


## Guide auf oder zu. src: woher der Druck kam ("pad", "combo", "menu", "helper"); leer, wenn
## Uzai selbst den Guide öffnet (Anruf, Probe) – dann zählt jeder Aufruf.
func toggle_guide(tab := "", src := "") -> void:
	if _guide_dup(src):
		return
	# Ruhebildschirm: die Guide-Taste weckt nur (auch über den Helfer, solange er ausblendet).
	# Öffnet Uzai den Guide selbst (Anruf), geht er sofort, und der Guide kommt.
	if saver and is_instance_valid(saver.screen):
		if src != "":
			saver.stop()
			return
		saver.stop(true)
	# Spiel im Zimmer (fernsehspiel.gd): Im Vollbild fährt die Guide-Taste zurück ins Zimmer – gleich beim
	# Drücken, ohne Halten, und ohne dass der Guide aufgeht; erst der nächste Druck öffnet ihn dort.
	# Öffnet Uzai den Guide selbst (src leer: Anruf), gilt das nicht.
	if Launcher.in_game and tab == "" and src != "" and src != "menu" and _guide == null and not (rest and rest.active) \
			and _away_for_live.is_empty() and Fernsehspiel.guide_taste(_tv) == "aufstehen":
		tv_aufstehen()
		return
	# Das Zimmer liegt noch über dem Guide, aus dem es geöffnet wurde (kurz nach Guide › Dein Zimmer):
	# erst in den Zustand „im Zimmer“ (der Guide darunter geht, das Zimmer bleibt) – sonst schlösse
	# der Guide das Zimmer mit.
	var zim := room_layer()
	if Launcher.in_game and zim and _guide and is_instance_valid(_guide) and Nav.layers.find(zim) > Nav.layers.find(_guide):
		tv_aufstehen()
		return
	# Messschritte des Controller-Problemlösers: Die Guide-Taste gehört dem Test (der Helfer meldet sie trotzdem).
	var top := Nav.top_layer()
	if top and top.has_meta("uz_pad_owned") and not Launcher.in_game:
		return
	# Im Ruhemodus weckt die Guide-Taste nur (Spiel weiter, Bildschirm an).
	if rest and rest.active:
		rest.wake("guide")
		return
	if _guide_opening:
		# Der Guide wartet noch (Bildfilter verstecken): der zweite Druck bricht das Öffnen ab.
		_guide_cancel = true
		return
	if mouse_on:
		set_mouse_mode(false)
	# Discord liegt fürs Übertragen vorn: Spiel bzw. Video zurück nach vorn, kein Guide.
	if not _away_for_live.is_empty():
		live_return()
		return
	if _boot and is_instance_valid(_boot):
		_boot.taste()
		return
	# Zurück aus den Discord-Streams: nur Uzai nach vorn holen, der Guide bleibt zu.
	# Im Spiel öffnet der Guide wie immer über dem Spiel.
	if _away_for_discord:
		_away_for_discord = false
		if not Launcher.in_game and not Launcher.is_starting() and Config.is_windows() and not get_window().has_focus():
			_restore_window()
			Sfx.play("back")
			return
	_guide_gen += 1
	if _guide and is_instance_valid(_guide):
		_guide.close()
		return
	for l in Nav.layers.duplicate():
		if is_instance_valid(l) and l.get_script() == Guide:
			return
	# Der Guide geht beim Drücken auf, nicht erst beim Loslassen (src/core/guide_hold.gd). Bleibt die
	# Taste gedrückt, macht er dem Schnellmenü Platz (_guide_press_done).
	_druck_merken(tab, src)
	Launcher.guide_open = true
	# Kam im Spiel gerade eine Nachricht (Pop-up über dem Spiel), öffnet der Guide gleich dort:
	# Steam beim Chat, Discord bei den Mitteilungen.
	# Auch außerhalb des Spiels: Guide gleich nach einem Pop-up führt in den Chat.
	var pending: Dictionary = Notify.take_pending(Launcher.in_game) if tab == "" else {}
	if str(pending.get("kind", "")) == "discord":
		tab = "system"
	if Launcher.in_game:
		# ShaderGlass liegt ganz oben und würde den Guide verdecken: solange verstecken.
		if Launcher.filter_active():
			_guide_opening = true
			_guide_cancel = false
			await Launcher.hide_filter(true)
			_guide_opening = false
			if _guide_cancel:
				await _guide_abbrechen()
				return
		# Exklusives Vollbild (oder das Spiel liegt minimiert): Darüber zeigt Windows kein Fenster. Kurz
		# fragen (höchstens 0,4 s, sonst wenige Millisekunden), dann das Spiel minimieren und den Guide
		# deckend zeigen (main_fenster.gd _spiel_kurz_weg). Ein zweiter Druck bricht ab.
		var grund := ""
		if Launcher.in_game and not _overlay_mode and not Launcher.quitting:
			_guide_opening = true
			_guide_cancel = false
			grund = await _vollbild_pruefen()
			_guide_opening = false
			if _guide_cancel or not Launcher.in_game:
				await _guide_abbrechen()
				return
			# Endete früher dabei oder ließ sich nicht minimieren: Die Taste lässt das Spiel in Ruhe.
			if not _guide_vollbild_ok(grund):
				Launcher.guide_open = false
				Sfx.play("error")
				await Launcher.hide_filter(false)
				return
		var im_spiel := await _overlay_spiel_warten(grund)
		if im_spiel == "abbruch":
			return
		# Endete das Spiel in der Wartezeit, nicht mehr durchsichtig über den Desktop legen.
		# Spielfenster weg, Beenden läuft oder ging nicht: deckend (der Vorhang läge sonst über dem Guide).
		if im_spiel == "ja":
			# Versuch je Spiel (docs/OVERLAY.md): Der Guide erscheint im Spiel, es bleibt im Vollbild.
			_enter_overlay_spiel()
		elif Launcher.in_game and grund != "":
			_enter_overlay(true)
			_spiel_kurz_weg(grund)
			Launcher.set_paused(true)
		elif Launcher.in_game:
			_enter_overlay(guide_deckend(Launcher.quitting, Launcher.quit_haengt, _spiel_weg))
			Launcher.set_paused(true)
	elif Launcher.is_starting():
		# Startphase: Ist der Emulator schon vorn, liegt der Guide durchsichtig darüber wie im
		# Spiel, statt Uzai im Vollbild vor das startende Spiel zu holen.
		if not get_window().has_focus() and Config.is_windows():
			_enter_overlay()
	elif not get_window().has_focus() and Config.is_windows():
		_restore_window()
	# A video keeps playing, full size or picture-in-picture; opening the Guide must not pause it.
	# Pausing happens only explicitly: in the Guide, „Pause“ on the „Video“ or „Bild in Bild“ tab.
	# A sidebar from the left (friends on Select) closes, because the Guide opens in the same place.
	for l in Nav.layers.duplicate():
		if is_instance_valid(l) and l.has_meta("uz_links_leiste") and not l.get("_closing"):
			l.call("close")
	# Die Taste blieb gedrückt, während der Guide noch wartete (Spiel im Vollbild): gleich das Schnellmenü.
	tab = Guide.QUICK if _hold_menu and tab == "" else tab
	_hold_menu = false
	Sfx.play("guide")
	_guide = Guide.new()
	_guide.main = self
	_guide.start_tab = tab
	_guide.closed.connect(_on_guide_closed)
	_guide.open(layer_host)
	if str(pending.get("kind", "")) in ["steam", "discord_dm", "discord_call"]:
		# Erst wenn der Guide auf dem Stapel liegt, damit der Chat darüber kommt.
		await get_tree().process_frame
		await get_tree().process_frame
		if _guide and is_instance_valid(_guide):
			if str(pending.kind) == "steam":
				open_chat(pending.target)
			elif str(pending.kind) == "discord_call":
				open_incoming_call(pending.target)
			else:
				open_discord_chat(pending.target)


## Overlay im Spiel (Versuch, docs/OVERLAY.md) für den Guide: „ja“, „nein“ oder „abbruch“ (zweiter Druck). Die Prüfung
## fragt den Helfer mehrmals; solange gilt „öffnet gerade“ – sonst startete ein zweiter Druck (oder Halten fürs
## Schnellmenü) eine zweite Kette, zwei Guides lagen auf dem Stapel und die Guide-Taste tat im Spiel nichts mehr.
func _overlay_spiel_warten(grund: String) -> String:
	if not (Launcher.in_game and grund in ["d3d", "aufloesung"]):
		return "nein"
	_guide_opening = true
	_guide_cancel = false
	var ok: bool = await _overlay_spiel_bereit() and Launcher.in_game
	_guide_opening = false
	if _guide_cancel:
		await _guide_abbrechen()
		return "abbruch"
	return "ja" if ok else "nein"


## Zweiter Druck, während der Guide noch wartete: nicht öffnen, Bildfilter wieder zeigen.
func _guide_abbrechen() -> void:
	_guide_cancel = false
	Launcher.guide_open = false
	Sfx.play("guide_close")
	await Launcher.hide_filter(false)


## Ein Druck, der den Guide öffnet: merken, ob er zum Halten wird (nur die echte Guide-Taste, nur mit
## Schnellmenü – guide_hold.gd). Der Guide selbst wartet darauf nicht.
func _druck_merken(tab: String, src: String) -> void:
	var looping := _hold.waiting
	_hold_menu = false
	if tab == "" and _hold.druck(src, Time.get_ticks_msec()) and not looping:
		_wait_guide_press()


## Laufender Druck der Guide-Taste: Godot sieht die Taste selbst (PlayStation, Nintendo, Taste G),
## beim Helfer entscheiden seine Meldungen „guide-up“ und „guide-hold“ (_on_pad_event).
func _wait_guide_press() -> void:
	while _hold.waiting and is_inside_tree():
		await get_tree().process_frame
		_guide_press_done(_hold.tick(Time.get_ticks_msec(), Input.is_action_pressed("uz_guide", true)))


## Die Guide-Taste blieb gedrückt („menu“): Der Guide, der beim Drücken aufging, macht dem Schnellmenü
## Platz. Wartet er noch (Spiel im Vollbild), geht er gleich als Schnellmenü auf.
func _guide_press_done(what: String) -> void:
	if what != "menu":
		return
	if _guide_opening:
		_hold_menu = true
		return
	if _guide and is_instance_valid(_guide):
		if _guide.start_tab == Guide.QUICK:
			return
		_guide.close()
	toggle_guide(Guide.QUICK)


func _on_guide_closed() -> void:
	_guide = null
	Launcher.guide_open = false
	seite_auftauen()
	var gen := _guide_gen
	if _overlay_mode and not Launcher.in_game:
		_leave_overlay()
	if Launcher.in_game:
		# Erst ausblenden lassen, sonst blitzt die Startseite kurz über dem Spiel auf.
		await get_tree().create_timer(0.14).timeout
		if gen != _guide_gen or _guide:
			return
		await Launcher.set_paused(false)
		if gen != _guide_gen or _guide:
			return
		# Im Zimmer aufgestanden (fernsehspiel „zimmer“): Uzai bleibt vorn, das Spiel läuft weiter.
		if _tv == "zimmer" and room_layer():
			return
		# Deckender Guide zu, während das Spiel sich schließt bzw. sein Fenster weg ist: erst der Vorhang
		# (Loch nur um Fenster des Spiels), dann gibt Uzai ab – sonst sähe man dazwischen Windows.
		if _overlay_deckend and (Launcher.quitting or _spiel_weg) and not Fernsehspiel.uzai_vorn(_tv):
			await _vorhang("schliessen")
			if gen != _guide_gen or _guide or not Launcher.in_game:
				return
		# Das Spiel lag minimiert (exklusives Vollbild): schon zurückholen, solange der Guide noch deckt.
		if _spiel_minimiert:
			Launcher.focus_game()
		_leave_overlay()
		await Launcher.hide_filter(false)
		# Schnell wieder geöffnet: das Spiel nicht vor den neuen Guide holen.
		if gen != _guide_gen or _guide:
			return
		if _spiel_minimiert:
			_spiel_zurueck()
		else:
			Launcher.focus_game()


## Liegt der Guide im Spiel deckend auf Uzais Grund statt durchsichtig über dem Spiel? Wenn Beenden
## läuft oder nicht ging oder das Spielfenster weg ist (die Wache hat zugezogen).
static func guide_deckend(beendet: bool, ging_nicht: bool, fenster_weg: bool) -> bool:
	return beendet or ging_nicht or fenster_weg


## Beenden ging nicht (Launcher.quit_stuck: Adminrechte, Windows lehnt ab, Wächter): Uzai bleibt
## bedienbar. Der Guide geht deckend auf (der Vorhang darunter geht), darüber die Wahl: noch einmal
## hart, zur Startseite (das Spiel läuft im Hintergrund weiter) oder zurück zum Spiel.
## Früher kam nur eine Mitteilung; Uzai blieb im Spiel, und es ging nicht zurück.
func _on_quit_stuck(g: Dictionary, text: String) -> void:
	# Einen Schritt später: Wer auf quit_game wartete (Uzai ausschalten, Ruhemodus), ist dann schon weiter.
	await get_tree().process_frame
	if not Launcher.in_game or Launcher.quitting or _closing:
		return
	Sfx.play("error")
	if not (_guide and is_instance_valid(_guide)):
		toggle_guide()
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		# Guide schon offen: deckend machen, dann geht der Vorhang vom harten Beenden (er läge über ihm).
		_overlay_deckend = true
		background.visible = true
		_vorhang_unter_guide()
	if not Launcher.in_game or Launcher.quitting:
		return
	open_dialog("%s läuft noch" % Library.display_title(g), text, quit_stuck_knoepfe(text != Launcher.KILL_DENIED,
		func() -> void:
			if _guide and is_instance_valid(_guide):
				_guide.close()
			Launcher.quit_game(true),
		func() -> void: Launcher.loslassen(),
		func() -> void:
			if _guide and is_instance_valid(_guide):
				_guide.close()), "warning", "warn")


## Knöpfe nach „läuft noch“ (ohne Bildschirm prüfbar): Bei Adminrechten hilft noch einmal hart nicht.
## Die Auswahl steht auf „Zur Startseite“ (das Spiel läuft im Hintergrund weiter), B zuletzt.
static func quit_stuck_knoepfe(nochmal: bool, hart: Callable, startseite: Callable, zurueck: Callable) -> Array:
	var out: Array = []
	if nochmal:
		out.append(["Sofort beenden", hart, "danger"])
	out.append(["Zur Startseite", startseite])
	out.append(["Zurück zum Spiel", zurueck])
	return out


## Speichern, Laden, Bildschirmfoto aus dem Guide: erst wenn das Spiel wieder vorn ist.
func guide_hotkey(action: String, done_text: String) -> void:
	await get_tree().create_timer(0.5).timeout
	if await Launcher.hotkey(action):
		Toasts.show_toast(done_text, str(Launcher.current.get("title", "")), "check", { "sound": "select" })
	else:
		Toasts.show_toast("Tastenkürzel kam nicht an", "Der Emulator hat nicht reagiert. Die Kürzel unter Einstellungen → Emulatoren prüfen.", "warning")


## Bildfilter aus dem Guide: erst wenn der Guide zu ist (ShaderGlass liegt ganz oben).
func guide_filter() -> void:
	await get_tree().create_timer(0.5).timeout
	await Launcher.toggle_filter()
	Toasts.show_toast("Bildfilter " + ("an" if Launcher.filter_active() else "aus"), "", "tv", { "sound": "select" })


func guide_lossless() -> void:
	await get_tree().create_timer(0.6).timeout
	var err := await Lossless.toggle()
	if err != "":
		Toasts.show_toast("Lossless Scaling", err, "bolt", { "ms": 7000 })
	elif Lossless.note != "":
		Toasts.show_toast("Lossless Scaling: Kürzel gedrückt", Lossless.note, "bolt", { "ms": 7000, "sound": "select" })
	else:
		Toasts.show_toast("Lossless Scaling " + ("an" if Lossless.active else "aus"), "Tastenkürzel " + Lossless.hotkey_text(), "bolt", { "sound": "select" })
