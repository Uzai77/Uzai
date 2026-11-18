extends "res://src/main_ebenen.gd"
## Hauptbildschirm, Schicht über main_ebenen.gd: In Discord übertragen (Go Live und Bildschirm
## teilen), Tasten dafür prüfen, Discord-Streams beobachten, Controller-Maus und die kleinen Ebenen
## für Audio, Bild und Ton und Mitteilungen.

const Guide := preload("res://src/ui/layers/guide.gd")
const ListItemC := preload("res://src/ui/components/list_item.gd")
const HelperScript := preload("res://src/core/helper.gd")


var discord_live := false
var _live_what := ""            ## was gerade übertragen wird ("spiel", "video")
var mouse_on := false


# --- Discord: übertragen, Maus --------------------------------------------

## Was „Übertragen“ gerade an Discord gibt: "spiel", "video" (YouTube, Filme und Serien in Uzai)
## oder "" (nichts läuft, dann gibt es den Knopf nicht).
func live_source() -> String:
	if Launcher.in_game:
		return "spiel"
	if Video.active and not Video.audio_only:
		return "video"
	return ""


## Das laufende Spiel oder Video in Discord übertragen (Go Live) oder die Übertragung beenden.
## Eine Schnittstelle dafür bietet Discord nicht (weder RPC noch Social SDK). Zwei Wege:
## 1. Tastenbelegung: Uzai drückt die Taste, die in Discord für „Toggle Screen Share“ eingetragen
##    ist. Discord hört Tastenbelegungen systemweit mit, das Spiel bleibt vorn. Ob Discord reagiert,
##    sieht Uzai nicht. Der Helfer drückt zuerst und mit fester Zeitgrenze (live-keys), die Auskunft
##    (Adminrechte, Discord-App) kommt danach; die Schritte stehen in logs/helper.log.
## 2. In der Discord-App (discord_share_in_app, geht immer): Discord kommt nach vorn – die erlaubte
##    Ausnahme –, Uzai drückt „<Spiel> streamen“ bzw. „Bildschirm teilen“ und „Live gehen“ über die
##    Bedienhilfe von Windows (UI Automation); was es nicht findet, klickst du mit der Controller-
##    Maus. Die Guide-Taste bringt das Spiel zurück nach vorn.
## system.live_method: "auto" (Taste; scheitert sie erkennbar, gleich weiter in der Discord-App),
## "keys" (nur Taste), "discord" (immer in der Discord-App).
## Übertragen wird, was Discord als Spiel erkennt: beim Video das Fenster „Uzai Video“ (mpv) – das
## muss einmal unter „Registrierte Spiele“ stehen, ebenso Emulatoren, die Discord nicht kennt.
## Eine Schnittstelle, um ein Programm dort einzutragen, hat Discord nicht (nur die Einstellung in
## der App). Darum lernt Uzai je Emulator, ob Discord ihn erkennt (system.live_detected, aus dem
## „<Spiel> streamen“-Knopf in der Discord-App): erkannt → Taste; nicht erkannt oder unbekannt →
## gleich in der Discord-App über „Bildschirm teilen“ mit dem Emulator-Fenster (geht immer), dazu
## einmal je Emulator die kurze Anleitung zum Eintragen.
## Was passiert ist, steht in logs/discord.log.
var _live_busy := false
var _away_for_live := {}         ## Discord liegt fürs Übertragen vorn: { what, start } – Guide-Taste holt zurück


func discord_go_live() -> void:
	var what := live_source()
	if what == "" and not discord_live:
		Toasts.show_toast("Erst ein Spiel oder Video starten", "Übertragen wird, was gerade läuft.", "discord")
		return
	if _live_busy:
		Toasts.show_toast("Einen Moment", "Uzai überträgt gerade schon.", "discord", { "ms": 2500, "overlay": true })
		return
	var keys := str(Config.get_value("system.stream_keys", "CTRL+SHIFT+F9"))
	var method := str(Config.get_value("system.live_method", "auto"))
	if not discord_live and what == "spiel" and Config.is_windows() and not Launcher.window_seen:
		Toasts.show_toast("Das Spiel startet noch", "Übertragen geht, sobald das Spiel im Bild ist.", "discord")
		return
	if not discord_live and Voice.ready_() and not Voice.in_channel():
		Toasts.show_toast("Erst in einen Sprachkanal", "Erst einem Sprachkanal beitreten (Guide → Discord).", "discord",
				{ "ms": 6000 })
		return
	if Config.is_windows() and live_route(method, live_emulator() if what == "spiel" else "", _live_detected()) == "app":
		await discord_share_in_app(what if what != "" else _live_what, not discord_live)
		return
	_live_busy = true
	if _guide and is_instance_valid(_guide):
		_guide.close()
	# Kurz: Discords Tastenbelegung gilt systemweit, das Spiel muss dafür nicht schon vorn liegen
	# (der Helfer holt es nur, wenn Uzai noch vorn ist). Vorher 0,8 s + bis 2,5 s Warten – zusammen
	# mit Discords eigenem Start dauerte „Übertragen“ etwa 5 s.
	await get_tree().create_timer(0.12).timeout
	var pids: Array = []
	var hwnd := 0
	if what == "spiel":
		await Launcher.wait_uzai_away(500)
		hwnd = Launcher.game_hwnd()
		# Das Fenster ist meist bekannt; die Prozesssuche (bei Steam/Epic über alle Prozesse) nur ohne.
		if Launcher.pid > 0:
			pids = [Launcher.pid]
		elif hwnd == 0:
			pids = await Launcher.game_pids()
	elif what == "video":
		# Video vorn: mpv liegt vorn (das „Spiel“, das Discord überträgt). Sonst liegt Uzai
		# durchsichtig darüber und behält den Fokus.
		pids = [Video.mpv_pid()] if Video.front_mode() and Video.mpv_pid() > 0 else [OS.get_process_id()]
	var args := { "pids": pids, "keys": keys, "hwnd": hwnd, "uzai_pid": OS.get_process_id() }
	# Nur das enge Format für Tastenbelegungen (der Helfer prüft es ebenso): sonst gar nicht drücken.
	var r: Dictionary = { "ok": true, "result": { "sent": false, "reason": "nicht erlaubt" } }
	if HelperScript.global_keys_ok(keys):
		r = await Helper.run("live-keys", args, 6.0)
	_live_busy = false
	Voice.log_line("Übertragen (%s, %s): %s" % [what if what != "" else "beenden", "an" if not discord_live else "aus", JSON.stringify(r)])
	var kind := live_problem_kind(r, Config.is_windows())
	if kind != "":
		var problem := live_problem(r, keys, Config.is_windows())
		if method == "auto" and live_fallback_ok(kind):
			Toasts.show_toast("Taste ging nicht – jetzt in Discord", problem, "discord", { "ms": 9000, "overlay": true })
			await discord_share_in_app(what if what != "" else _live_what, not discord_live, true)
		else:
			Toasts.show_toast("Übertragung ging nicht", problem + (" Oder im Guide unter Discord „In Discord übertragen“ wählen." if live_fallback_ok(kind) else ""),
					"warning", { "ms": 9000, "overlay": true })
		return
	discord_live = not discord_live
	_live_what = what if discord_live else ""
	if not discord_live:
		Toasts.show_toast("Übertragung beendet", "", "discord", { "sound": "back", "overlay": true })
	elif what == "video" and not bool(Config.get_value("system.video_live_hint", false)):
		# Einmal erklären, was Discord dafür braucht (danach reicht der Knopf).
		Config.set_value("system.video_live_hint", true)
		Toasts.show_toast("Video an Discord", "In Discord unter Registrierte Spiele „Uzai Video“ hinzufügen. Taste „Toggle Screen Share“: %s" % keys, "discord", { "ms": 12000, "sound": "select", "overlay": true })
	else:
		var title := live_title(what)
		var sub := "%s wird übertragen. Falls nicht: „Toggle Screen Share“ in Discord auf %s legen." % [title, keys]
		# Emulatoren kennt Discord oft nicht als Spiel – dann gibt es nichts zu übertragen. Je Emulator einmal sagen.
		# (Nur „Taste“ eingestellt; bei „auto“ nimmt ein solcher Emulator gleich den Weg über die App.)
		var emu := live_emulator() if what == "spiel" else ""
		var told: Array = (Config.get_value("system.live_hint_emus", []) as Array).duplicate()
		if emu != "" and not told.has(emu) and _live_detected().get(emu) != true:
			told.append(emu)
			Config.set_value("system.live_hint_emus", told)
			sub = "Discord erkennt %s nicht. In Discord unter Registrierte Spiele hinzufügen. Taste „Toggle Screen Share“: %s." % [str(Config.emulator(emu).get("name", "den Emulator")), keys]
		Toasts.show_toast("Übertragung an Discord", sub, "discord", { "ms": 9000, "sound": "select", "overlay": true })


## Der Emulator des laufenden Spiels ("" bei Steam-, Epic-, PC-Spielen).
func live_emulator() -> String:
	if not Launcher.in_game or str(Launcher.current.get("source", "")) != "rom":
		return ""
	return str(Launcher.current.get("emulator", Config.system(str(Launcher.current.get("system", ""))).get("emulator", "")))


## Gemerkt: Emulator → erkennt Discord ihn als Spiel (true/false).
func _live_detected() -> Dictionary:
	var v: Variant = Config.get_value("system.live_detected", {})
	return v if v is Dictionary else {}


## Welcher Weg zum Übertragen: "keys" (Taste in Discord) oder "app" (in der Discord-App).
## method: system.live_method; emu: Emulator des Spiels ("" sonst); detected: Emulator → erkannt.
## Bei „auto“ nimmt ein Emulator, den Discord nicht (oder noch nicht nachweislich) als Spiel
## erkennt, gleich den Weg über die App – die Taste überträgt nur erkannte Spiele.
static func live_route(method: String, emu: String, detected: Variant) -> String:
	if method == "discord":
		return "app"
	if method == "keys" or emu == "":
		return "keys"
	var d: Dictionary = detected if detected is Dictionary else {}
	return "keys" if d.get(emu) == true else "app"


func live_title(what: String) -> String:
	if what == "spiel":
		return str(Launcher.current.get("title", "Das Spiel"))
	if what == "video":
		return str(Video.video.get("title", "Das Video"))
	return ""


## Was am Ergebnis des Tastendrucks nicht stimmt, als Kennwort ("" = nichts gefunden):
## helper, timeout, unknown_key, no_discord, elevated, discord_elevated, stuck, rejected.
## Ob Discord wirklich überträgt, meldet Discord nicht – das bleibt ein Hinweis.
static func live_problem_kind(r: Dictionary, windows: bool) -> String:
	if not windows:
		return ""
	if not bool(r.get("ok", false)):
		return "timeout" if bool(r.get("timeout", false)) else "helper"
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	match str(res.get("reason", "")):
		"unbekannt":
			return "unknown_key"
		"nicht erlaubt":
			return "not_allowed"
		"nicht vorn":
			return "not_front"
		"geschützt":
			return "protected"
		"zu oft":
			return "too_often"
	if res.get("discord") is Array and (res.discord as Array).is_empty():
		return "no_discord"
	var self_elev := bool(res.get("self_elevated", false))
	if res.get("foreground_elevated") == true and not self_elev:
		return "elevated"
	if res.get("discord") is Array and not self_elev:
		for d in res.discord:
			if d is Dictionary and d.get("elevated") == true:
				return "discord_elevated"
	if res.has("done") and not bool(res.done):
		return "stuck"
	if res.has("expected") and int(res.get("accepted", 0)) < int(res.expected):
		return "rejected"
	return ""


## Lohnt der Weg über die Discord-App? Nicht, wenn sie gar nicht läuft; nicht vor einem Anmelde-
## oder Sicherheitsfenster (Discord käme darüber) und nicht direkt nach einem Druck.
static func live_fallback_ok(kind: String) -> bool:
	return kind != "" and not kind in ["no_discord", "protected", "too_often"]


## Der Satz für die Mitteilung ("" = nichts gefunden).
static func live_problem(r: Dictionary, keys: String, windows: bool) -> String:
	var kind := live_problem_kind(r, windows)
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	match kind:
		"helper":
			return "Windows-Helfer läuft nicht (%s). Details in logs\\helper.log." % str(r.get("error", "keine Antwort"))
		"timeout":
			var ahead := int(r.get("ahead", 0))
			return "Windows-Helfer antwortet nicht%s. Details in logs\\helper.log." % (
					(" (war noch mit %d anderen Aufgaben beschäftigt)" % ahead) if ahead > 0 else "")
		"unknown_key":
			return "„%s“ in „%s“ ungültig. Beispiel: CTRL+SHIFT+F9." % [
					", ".join(PackedStringArray(res.get("unknown", []))), keys]
		"no_discord":
			return "Discord-App läuft nicht."
		"elevated":
			return "„%s“ läuft mit Administratorrechten. Tasten kommen nicht an." % str(res.get("foreground", "Das Spiel"))
		"discord_elevated":
			return "Discord läuft mit Administratorrechten. Discord normal starten."
		"stuck":
			return "Windows hat den Tastendruck nicht rechtzeitig angenommen (zuletzt: %s)." % str(res.get("stage", "?"))
		"rejected":
			return "Windows hat den Tastendruck abgewiesen (%d von %d Tastenereignissen)." % [int(res.get("accepted", 0)), int(res.expected)]
		"not_allowed":
			return "„%s“ ungültig. Erlaubt: Strg, Alt, Umschalt plus A–Z, 0–9 oder F1–F24." % keys
		"not_front":
			return "Anderes Fenster im Vordergrund. Erneut versuchen."
		"protected":
			return "Sicherheitsfenster von Windows im Vordergrund."
		"too_often":
			return "Kurz warten und erneut versuchen."
	return ""


## „In Discord übertragen“: Discord-App nach vorn (Sprachkanal geöffnet), Controller-Maus an,
## Hinweis über allem; Uzai sucht den Knopf selbst (UI Automation) und drückt ihn. Guide-Taste:
## Spiel bzw. Video wieder nach vorn, Maus aus. start: anfangen (sonst beenden). after_keys: kam
## von einer gescheiterten Taste (dann ist der Guide schon zu).
func discord_share_in_app(what: String, start := true, after_keys := false) -> void:
	if not Config.is_windows():
		Toasts.show_toast("Geht nur unter Windows", "", "discord")
		return
	if _live_busy:
		return
	if start and Voice.ready_() and not Voice.in_channel():
		Toasts.show_toast("Erst in einen Sprachkanal", "Erst einem Sprachkanal beitreten (Guide → Discord).", "discord",
				{ "ms": 6000 })
		return
	_live_busy = true
	if _guide and is_instance_valid(_guide):
		_guide.close()
	if not after_keys:
		# Erst wenn der Guide zu ist (im Spiel ist dann das Spiel wieder vorn), sonst verdeckt er Discord.
		await get_tree().create_timer(1.2 if Launcher.in_game else 0.8).timeout
	if Launcher.in_game:
		# ShaderGlass liegt ganz oben und würde Discord verdecken; die Rückkehr zeigt es wieder.
		await Launcher.hide_filter(true)
	elif Video.active and Video.front_mode():
		# mpv liegt „immer oben“ und würde Discord verdecken; die Rückkehr legt es wieder obenauf.
		Video.set_ontop(false)
	_away_for_live = { "what": what, "start": start }
	var url := Guide.discord_channel_url(Voice.channel)
	var front := await Helper.run("discord-front", { "wait_ms": 200 }, 4.0)
	var fres: Dictionary = front.result if front.get("result") is Dictionary else {}
	# Den Sprachkanal öffnen: Discord kommt nach vorn und zeigt unten links die Sprachleiste.
	# Liegt Discord nur im Infobereich, holt der Link das Fenster überhaupt erst hervor.
	if url != "" or not bool(fres.get("found", false)):
		OS.shell_open(url if url != "" else "discord://-/channels/@me")
		front = await Helper.run("discord-front", { "wait_ms": 4000 }, 9.0)
		fres = front.result if front.get("result") is Dictionary else {}
	if Video.active and Video.front_mode() and not Launcher.in_game:
		Video.set_ontop(false)   # falls das Schließen des Guides es inzwischen wieder obenauf gelegt hat
	Voice.log_line("In Discord übertragen (%s, %s): Discord vorn: %s" % [what, "an" if start else "aus", JSON.stringify(front)])
	if _away_for_live.is_empty():
		_live_busy = false
		return
	if not bool(fres.get("found", false)):
		_live_busy = false
		Toasts.show_toast("Discord-App nicht gefunden", "Discord-App am PC starten.", "warning",
				{ "ms": 8000, "overlay": true })
		return
	set_mouse_mode(true, false)
	var title := live_title(what)
	var emu := live_emulator() if what == "spiel" else ""
	var emu_name := str(Config.emulator(emu).get("name", emu)) if emu != "" else ""
	var win := "Uzai Video"
	if what == "spiel":
		win = await _game_window_title()
	var keys := live_window_keys(win, emu_name, title)
	Toasts.show_toast("In Discord übertragen", live_hint(start, title, emu_name if _live_detected().get(emu) != true else ""),
			"discord", { "ms": 20000, "overlay": true, "sound": "select", "tag": "live-hint" })
	var got := await _live_click(int(fres.get("hwnd", 0)), title, start, keys, emu)
	_live_busy = false
	Voice.log_line("In Discord übertragen: %s" % got)
	if _away_for_live.is_empty():
		return
	if got == "live" or got == "stopped":
		discord_live = got == "live"
		_live_what = what if discord_live else ""
		Toasts.show_toast("Übertragung läuft" if discord_live else "Übertragung beendet", (title + " ist live in deinem Sprachkanal.") if discord_live else "",
				"discord", { "ms": 5000, "overlay": true, "sound": "select" })
		await get_tree().create_timer(1.5).timeout
		if not _away_for_live.is_empty():
			live_return()


## Hinweis-Karte, solange Discord fürs Übertragen vorn liegt. window: Fenster, das bei „Bildschirm
## teilen“ zu wählen ist (Emulator, den Discord nicht als Spiel kennt; "" sonst).
static func live_hint(start: bool, title: String, window := "") -> String:
	var keys := "Linker Stick: Maus · A: Klick · X: Rechtsklick · B: Zurück · Guide-Taste: zurück ins Spiel."
	if not start:
		return "Unten links bei deinem Sprachkanal das Bildschirm-Symbol bzw. „Stream beenden“ wählen. " + keys
	if window != "":
		return "„Bildschirm teilen“, Fenster von %s, „Live gehen“. %s" % [window, keys]
	return "„%s streamen“ oder „Bildschirm teilen“, dann „Live gehen“. %s" % [title if title != ""
			else "Spiel", keys]


## Woran Uzai das Fenster des Spiels in Discords Auswahl erkennt: Fenstertitel, Emulator, Spiel
## (ohne Doppelte, nur ab drei Zeichen – kurze Wörter träfen sonst andere Knöpfe).
static func live_window_keys(window_title: String, emu_name: String, game_title: String) -> Array:
	var out: Array = []
	for k in [window_title, emu_name, game_title]:
		var t := str(k).strip_edges().to_lower()
		if t.length() >= 3 and not out.has(t):
			out.append(t)
	return out


## Titel des Spielfensters (über den Helfer, nur lesen), "" wenn unbekannt.
func _game_window_title() -> String:
	var hwnd := Launcher.game_hwnd()
	if hwnd == 0 or Launcher.pid <= 0:
		return ""
	var r := await Helper.run("windows", { "pid": Launcher.pid }, 3.0)
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	for w in res.get("windows", []):
		if w is Dictionary and int(w.get("hwnd", 0)) == hwnd:
			return str(w.get("title", "")).left(200)
	return ""


## Was der erste Blick in Discord über das Spiel sagt: "ja" (es gibt „<Spiel> streamen“ –
## Discord erkennt es), "nein" (nur „Bildschirm teilen“) oder "" (nichts davon zu sehen).
static func live_detection(buttons: Array) -> String:
	var share := false
	for b in buttons:
		if not (b is Dictionary):
			continue
		var k := share_kind(str(b.get("name", "")))
		if k == "stream":
			return "ja"
		if k == "share":
			share = true
	return "nein" if share else ""


## Merken, ob Discord diesen Emulator als Spiel erkennt; beim ersten „nein“ einmal kurz sagen,
## wie man ihn in Discord einträgt (danach geht „Übertragen“ direkt über die Taste).
func _note_detected(emu: String, det: String) -> void:
	if emu == "" or det == "":
		return
	var d: Dictionary = _live_detected().duplicate()
	if d.get(emu) == (det == "ja"):
		return
	d[emu] = det == "ja"
	Config.set_value("system.live_detected", d)
	Voice.log_line("Übertragen: Discord erkennt %s %s als Spiel" % [emu, "" if det == "ja" else "nicht"])
	var told: Array = (Config.get_value("system.live_hint_emus", []) as Array).duplicate()
	if det == "nein" and not told.has(emu):
		told.append(emu)
		Config.set_value("system.live_hint_emus", told)
		var nm := str(Config.emulator(emu).get("name", emu))
		Toasts.show_toast("Einmal in Discord eintragen", "Discord erkennt %s nicht, das Fenster wird geteilt. In Discord unter Registrierte Spiele %s hinzufügen." % [nm, nm],
				"discord", { "ms": 12000, "overlay": true })


## Knöpfe in Discord drücken (UI Automation): erst „<Spiel> streamen“/„Bildschirm teilen“, dann im
## Fenster danach „Live gehen“. Ergebnis: "live", "stopped", "manuell" (du klickst), "fehler", "zurück".
func _live_click(hwnd: int, title: String, start: bool, want: Array = [], emu := "") -> String:
	if hwnd == 0:
		return "manuell"
	var opened := false
	var looked := false
	for attempt in 5:
		if _away_for_live.is_empty():
			return "zurück"
		var r := await Helper.run("discord-buttons", { "hwnd": hwnd, "budget_ms": 5000, "app": "discord" }, 15.0)
		var res: Dictionary = r.result if r.get("result") is Dictionary else {}
		var buttons: Array = res.get("buttons", []) if res.get("buttons") is Array else []
		Voice.log_line(
				"In Discord übertragen: %d Knöpfe gelesen%s%s" % [buttons.size(), (", Fehler: " + str(r.get("error", ""))) if not r.ok else "",
				(", " + str(res.get("error", ""))) if str(res.get("error", "")) != "" else ""])
		if not r.ok:
			return "fehler"
		if _away_for_live.is_empty():
			return "zurück"
		# Läuft schon (z. B. hat die Taste doch gewirkt): nichts mehr drücken.
		if start and live_now(buttons):
			return "live"
		if start and not opened and not looked:
			looked = true
			_note_detected(emu, live_detection(buttons))
		var pick := share_pick(buttons, title, start, opened, want)
		if pick.is_empty():
			if not start and opened:
				return "stopped"
			await get_tree().create_timer(1.0).timeout
			continue
		var inv := await Helper.run("discord-invoke", { "i": int(pick.i) }, 6.0)
		var how := str((inv.result as Dictionary).get("result", "")) if inv.get("result") is Dictionary else str(inv.get("error", ""))
		Voice.log_line("In Discord übertragen: „%s“ (%s) gedrückt: %s" % [str(pick.name), str(pick.kind), how])
		if how != "ok":
			return "manuell"
		if pick.kind == "golive":
			return "live"
		if pick.kind == "stop":
			return "stopped"
		if pick.kind == "window":
			want = []
			await get_tree().create_timer(0.6).timeout
			continue
		# „<Spiel> streamen“ wählt das Spiel schon selbst; nur „Bildschirm teilen“ braucht das Fenster.
		if pick.kind == "stream":
			want = []
		opened = true
		await get_tree().create_timer(1.2).timeout
	return "manuell"


## Welche Art Knopf in Discord (nach seiner Beschriftung, deutsch oder englisch): "stream"
## („<Spiel> streamen“), "share" („Bildschirm teilen“), "golive" („Live gehen“), "stop" oder "".
static func share_kind(name: String) -> String:
	var n := name.to_lower().strip_edges()
	if n == "":
		return ""
	for w in ["stop streaming", "stream beenden", "streaming beenden", "übertragung beenden", "stop sharing", "teilen beenden", "stream stoppen",
			"freigabe beenden"]:
		if n.contains(w):
			return "stop"
	for bad in ["ansehen", "watch", "zuschau", "beitreten", "join", "streamer", "verlassen", "leave", "lautstärke", "volume", "einstellung", "setting", "qualität",
			"quality", "vorschau", "preview", "popout", "pop-out", "vollbild", "fullscreen"]:
		if n.contains(bad):
			return ""
	if n == "live" or n.contains("go live") or n.contains("live gehen") or n.contains("live übertragen"):
		return "golive"
	for w in ["share your screen", "share screen", "screen share", "bildschirm teilen", "teile deinen bildschirm", "bildschirm freigeben",
			"bildschirmübertragung"]:
		if n.contains(w):
			return "share"
	if n.begins_with("stream ") or n.ends_with(" streamen") or n.begins_with("streame ") or n.ends_with(" übertragen"):
		return "stream"
	return ""


## Der passende Knopf aus der Liste des Helfers ({ i, name, enabled, offscreen }), {} = keiner.
## start: anfangen (Spiel-Knopf vor „Bildschirm teilen“, „Live gehen“ nur, wenn er an ist), sonst
## beenden. opened: das Fenster zum Teilen ist schon offen – dann zählt nur noch „Live gehen“,
## außer want nennt das Fenster, das dort erst zu wählen ist (live_window_keys): dann zuerst die
## Kachel, deren Name es enthält (kind "window"). Zeigt Discord sie nicht als Knopf, wählst du.
static func share_pick(buttons: Array, title: String, start: bool, opened := false, want: Array = []) -> Dictionary:
	var best := {}
	var best_score := 0
	var tk := title.to_lower().strip_edges()
	for b in buttons:
		if not (b is Dictionary):
			continue
		var name := str(b.get("name", ""))
		var kind := share_kind(name)
		var score := 0
		if not start:
			score = 10 if kind == "stop" else 0
		elif kind == "golive":
			score = 10 if bool(b.get("enabled", true)) else 0
		elif not opened and kind == "stream":
			score = 8 if tk != "" and name.to_lower().contains(tk) else 6
		elif not opened and kind == "share":
			score = 5
		elif opened and kind == "" and _names_window(name, want):
			score = 11
			kind = "window"
		if score > 0 and bool(b.get("offscreen", false)):
			score -= 1
		if score > best_score:
			best_score = score
			best = { "i": int(b.get("i", -1)), "kind": kind, "name": name }
	return best


static func _names_window(name: String, want: Array) -> bool:
	var n := name.to_lower()
	for k in want:
		if str(k) != "" and n.contains(str(k)):
			return true
	return false


## Zeigt Discord schon einen „Stream beenden“-Knopf (die Übertragung läuft)?
static func live_now(buttons: Array) -> bool:
	for b in buttons:
		if b is Dictionary and share_kind(str(b.get("name", ""))) == "stop":
			return true
	return false


## Zurück aus Discord (Guide-Taste oder nach „Live gehen“): Maus aus, Spiel bzw. Video wieder vorn,
## Bildfilter wieder an. Discord bleibt nie vorn liegen.
func live_return() -> void:
	_away_for_live = {}
	Toasts.dismiss("live-hint")
	if mouse_on:
		set_mouse_mode(false)
	Sfx.play("back")
	if Launcher.in_game:
		await Launcher.hide_filter(false)
		Launcher.focus_game()
	elif Video.active and Video.front_mode() and Video.mpv_pid() > 0:
		Video.set_ontop(true)
		Helper.run("focus", { "pid": Video.mpv_pid() })
	elif Video.active:
		DisplayServer.window_move_to_foreground()
		Helper.run("focus", { "pid": OS.get_process_id() })
	else:
		_restore_window()


## Einstellungen → System → „Übertragung prüfen“: drückt die Tastenkombination einmal bei Uzai
## selbst und zeigt, was ankam, dazu was Uzai über Helfer, Discord und Rechte weiß. So fällt ein
## Tippfehler in der Kombination auf, ebenso eine fehlende Discord-App oder Adminrechte.
func test_stream_keys() -> void:
	var keys := str(Config.get_value("system.stream_keys", "CTRL+SHIFT+F9"))
	if not Config.is_windows():
		open_dialog("Übertragung prüfen", "Das geht nur unter Windows.", [["OK", func() -> void: pass]], "discord")
		return
	var probe := _KeyProbe.new()
	add_child(probe)
	var r: Dictionary = { "ok": true, "result": { "sent": false, "reason": "nicht erlaubt" } }
	if HelperScript.global_keys_ok(keys):
		r = await Helper.run("live-keys", { "pids": [OS.get_process_id()], "keys": keys, "uzai_pid": OS.get_process_id(), "focus_ms": 0 }, 8.0)
	await get_tree().create_timer(0.3).timeout
	var got: Array = probe.got.duplicate()
	probe.queue_free()
	var extra := { "helper": Helper.status() }
	if Launcher.in_game:
		var pids := await Launcher.game_pids()
		if not pids.is_empty():
			var d := await Helper.run("discord-diag", { "pids": pids }, 6.0)
			if d.ok and d.result is Dictionary:
				extra["game"] = d.result.get("game", [])
	Voice.log_line("Übertragung prüfen: %s, angekommen: %s, %s" % [JSON.stringify(r), str(got), JSON.stringify(extra)])
	var chan := -1
	if Voice.ready_():
		chan = 1 if Voice.in_channel() else 0
	open_dialog("Übertragung prüfen", live_report(r, got, keys, chan, str(Voice.channel.get("name", "")), extra), [["OK", func() -> void: pass]], "discord")


static func live_report(r: Dictionary, got: Array, keys: String, chan: int, chan_name: String, extra := {}) -> String:
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	var lines := PackedStringArray()
	var hs: Dictionary = extra.get("helper", {}) if extra.get("helper") is Dictionary else {}
	if not hs.is_empty():
		if not bool(hs.get("available", false)):
			lines.append("Windows-Helfer: läuft nicht – was PowerShell meldet, steht in logs\\helper.log.")
		else:
			var fast: Dictionary = hs.get("fast", {})
			lines.append("Windows-Helfer: läuft%s." % ("" if bool(fast.get("ready", false)) else " (nur der Hauptweg, der schnelle ist nicht bereit)"))
	if not bool(r.get("ok", false)):
		lines.append("Taste: Der Helfer hat nicht geantwortet (%s)." % str(r.get("error", "")))
	elif str(res.get("reason", "")) == "unbekannt":
		lines.append("Taste „%s“: Uzai versteht „%s“ nicht – bitte z. B. CTRL+SHIFT+F9 eintragen." % [keys, ", ".join(PackedStringArray(res.get("unknown", [])))])
	elif str(res.get("reason", "")) in ["nicht erlaubt", "nicht vorn", "geschützt", "zu oft"]:
		lines.append("Taste „%s“: nicht gedrückt. %s" % [keys, live_problem(r, keys, true)])
	elif got.is_empty():
		lines.append(
				"Taste „%s“: Uzai hat gedrückt, aber nichts kam an. Läuft ein Programm mit Administratorrechten vorn, oder fängt ein anderes Programm die Taste ab?" % keys)
	else:
		lines.append("Taste „%s“ kommt so an: %s. Genau so muss sie in Discord stehen." % [keys, " + ".join(PackedStringArray(got))])
	if res.has("expected"):
		var fb := int(res.get("fallback", 0))
		lines.append(
				"Windows hat %d von %d Tastenereignissen angenommen%s." % [int(res.get("accepted", 0)), int(res.expected), (", %d davon über den Ersatzweg" % fb) if fb > 0
				else ""])
	var dc: Array = res.get("discord", []) if res.get("discord") is Array else []
	var self_elev := bool(res.get("self_elevated", false))
	if dc.is_empty():
		lines.append("Discord-App: läuft nicht (Übertragen geht nur mit der App am PC).")
	else:
		var d: Dictionary = dc[0]
		var elev := " – mit Administratorrechten, Uzai nicht: Tasten kommen dann nicht an, Discord normal starten" if d.get("elevated") == true \
				and not self_elev else ""
		lines.append("Discord-App: läuft (%s)%s." % [str(d.get("name", "Discord")), elev])
	if res.has("self_elevated"):
		var line := "Rechte: Uzai " + ("mit" if self_elev else "ohne") + " Administratorrechte"
		for g in (extra.get("game", []) if extra.get("game") is Array else []):
			if g is Dictionary and g.get("elevated") == true and not self_elev:
				line += ", „%s“ mit – dort kommen Tasten nicht an" % str(g.get("name", "das Spiel"))
		lines.append(line + ".")
	if chan == 1:
		lines.append("Sprachkanal: du bist in „%s“." % chan_name)
	elif chan == 0:
		lines.append("Sprachkanal: keiner – Discord überträgt nur in einen Sprachkanal oder Anruf.")
	else:
		lines.append("Sprachkanal: unbekannt (Discord ist in Uzai nicht verbunden).")
	lines.append("In Discord: Einstellungen → Tastenbelegung → „Tastenbelegung hinzufügen“ → Aktion „Toggle Screen Share“ → diese Tasten. Discord muss das Spiel erkennen (Einstellungen → Registrierte Spiele; Emulatoren dort einmal hinzufügen). Ob Discord wirklich überträgt, meldet Discord Uzai nicht.")
	lines.append("Alternative: Guide → Discord → „In Discord übertragen“.")
	return "\n".join(lines)


## Hört kurz mit, welche Tasten bei Uzai ankommen (für test_stream_keys).
class _KeyProbe extends Node:
	var got: Array = []

	func _input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k == null or not k.pressed or k.echo:
			return
		var txt := OS.get_keycode_string(k.keycode)
		if k.location == KEY_LOCATION_LEFT:
			txt += " (links)"
		elif k.location == KEY_LOCATION_RIGHT:
			txt += " (rechts)"
		if not got.has(txt):
			got.append(txt)


## Streams von Freunden ansehen: Discord bietet dafür keine Schnittstelle, also holt Uzai die
## Discord-App mit dem Sprachkanal nach vorn – die eine bewusste Ausnahme. Die Guide-Taste
## bringt dich zurück (im Spiel wie immer in den Guide über dem Spiel).
var _away_for_discord := false


func watch_discord_streams() -> void:
	if Config.kid_stop("chats"):
		return
	var url := Guide.discord_channel_url(Voice.channel)
	if url == "":
		Toasts.show_toast("In keinem Sprachkanal", "", "discord")
		return
	if _guide and is_instance_valid(_guide):
		_guide.close()
	Toasts.show_toast("Discord kommt nach vorn", "Guide-Taste bringt dich zurück", "discord", { "ms": 4000 })
	# Erst wenn der Guide zu ist (im Spiel ist dann das Spiel wieder vorn), sonst verdeckt es Discord.
	await get_tree().create_timer(1.2 if Launcher.in_game else 0.8).timeout
	if Launcher.in_game:
		# ShaderGlass liegt ganz oben und würde Discord verdecken; der nächste Guide zeigt es wieder.
		await Launcher.hide_filter(true)
	_away_for_discord = true
	OS.shell_open(url)


## Maus mit dem Controller (für Discord und alles, was keine Controller-Steuerung hat).
## hint: die übliche Mitteilung zeigen („In Discord übertragen“ hat eine eigene Hinweis-Karte).
func set_mouse_mode(on: bool, hint := true) -> void:
	mouse_on = on
	Nav.passthrough = on
	if Config.is_windows():
		await Helper.run("mouse", { "on": on, "combo": bool(Config.get_value("controller.guide_combo", true)) })
	if on and hint:
		if _guide and is_instance_valid(_guide):
			_guide.close()
		Toasts.show_toast("Maus mit dem Controller", "Linker Stick bewegt, rechter Stick scrollt, A klickt, X Rechtsklick, B Zurück. Guide-Taste beendet.",
				"controller", { "ms": 6000 })


# --- Kleine Ebenen: Audio, Bild und Ton, Mitteilungen --------------------------------------------

## „Ton ausgeben über“: die Tonausgänge des PCs. Führt FxSound den Ton, stellt Uzai FxSound um (sein eigenes
## Gerät steht nicht in der Liste), sonst das Standardgerät von Windows (Mixer.tonwahl). Ist ein festes Gerät
## gewählt, wird die Wahl hier zum festen. Gibt die Auswahl zurück (null, wenn sich nichts lesen ließ).
func open_audio_devices() -> Control:
	var tw := Mixer.tonwahl
	var liste: Dictionary = await tw.geraete_lesen()
	if (liste.devices as Array).is_empty():
		Toasts.show_toast("Audiogeräte nicht lesbar", "Gleich noch einmal versuchen.", "warning")
		return null
	var opts: Array = []
	for d in liste.devices:
		opts.append([str(d.id), str(d.name)])
	return open_choice("Ton ausgeben über", opts, str(liste.current), func(id: Variant) -> void:
		var name := ""
		for o in opts:
			if o[0] == str(id):
				name = str(o[1])
		if await tw.ausgeben_ueber(str(id), liste):
			Toasts.show_toast("Ton über " + name, "Bleibt fest." if tw.fest_an() else "", "speaker", { "sound": "select" })
		else:
			Toasts.show_toast("Tonausgabe nicht umgestellt", "Gerät nicht übernommen. Erneut versuchen.", "warning")
	)


## „Immer dieses Gerät“: das feste Ausgabegerät wählen – Uzai stellt zurück darauf, sobald es wieder da ist
## (Fernseher war aus). „Aus“ lässt Windows und FxSound selbst wählen. Gibt die Auswahl zurück.
func open_ton_fest() -> Control:
	var tw := Mixer.tonwahl
	var liste: Dictionary = await tw.geraete_lesen()
	var opts: Array = [["", "Aus", "Windows und FxSound wählen selbst"]]
	for d in liste.devices:
		opts.append([str(d.id), str(d.name), ""])
	# Das feste Gerät ist gerade nicht angeschlossen: Es steht trotzdem da.
	var fest := tw.fest_id()
	if fest != "" and not opts.any(func(o: Array) -> bool: return str(o[0]) == fest):
		opts.append([fest, tw.fest_name() if tw.fest_name() != "" else "Tonausgabe", "gerade nicht da"])
	return open_choice("Immer dieses Gerät", opts, fest, func(id: Variant) -> void:
		if str(id) == "":
			tw.fest_setzen("", "")
			Toasts.show_toast("Kein festes Gerät", "Windows und FxSound wählen selbst.", "speaker", { "sound": "select" })
			return
		if str(id) == fest:
			return
		# Der Name, wie Windows ihn nennt (so kennt ihn auch FxSound).
		var roh: Array = liste.get("roh", []) if liste.get("roh") is Array else []
		var da: Dictionary = tw.finde(roh, str(id), "")
		tw.fest_setzen(str(id), str(da.get("name", "")))
		var name := ""
		for o in opts:
			if o[0] == str(id):
				name = str(o[1])
		Toasts.show_toast("Ton bleibt auf " + name, "Uzai stellt zurück, sobald es wieder da ist.", "lock", { "sound": "select" })
		if not da.is_empty():
			await tw.ausgeben_ueber(str(id), liste)
	, "Uzai stellt zurück darauf, sobald es wieder da ist")


## Bild & Ton (Guide → System, Einstellungen → System → Windows): src/ui/layers/bild_ton_sheet.gd.
func open_bild_ton() -> void:
	load("res://src/ui/layers/bild_ton_sheet.gd").open_for(self)


func open_notifications() -> void:
	Toasts.unread = 0
	var s = SheetLayer.new()
	var n := Toasts.history.size()
	s.setup("Mitteilungen", "Nichts Neues" if n == 0 else ("Die letzte" if n == 1 else "Die letzten %d" % n), 760)
	s.fill_func = func(sheet) -> void:
		# Ohne Steam-Anmeldung in Uzai kommt keine Steam-Nachricht an: das steht hier oben, A meldet an
		# (Freund-Test 0.16.53: „notifications still do not work“ – ohne Hinweis, woran es liegt).
		if steam_hint_due(SteamChat.weg(), Library.steam_root() != "", Library.demo):
			var hint = ListItemC.new()
			hint.setup("Steam-Nachrichten", "Nicht verbunden – keine Pop-ups", "")
			hint.icon_name = "steam"
			hint.set_meta("uz_hint_a", "Anmelden")
			hint.activated.connect(func() -> void: open_chat({ "id": "", "name": "Steam" }, true))
			sheet.add_row(hint)
		if Toasts.history.is_empty():
			sheet.add_label("Keine Mitteilungen.", "m", "muted")
			return
		# Y: alle auf einmal entfernen, mit Rückgängig (die Liste kommt dann wieder).
		var leeren := func() -> void:
			var old: Array = Toasts.clear_history()
			sheet.refill()
			Undo.offer_calls("Mitteilungen entfernt", U.plural(old.size(), "Mitteilung", "Mitteilungen"), "bell",
					[Toasts.restore_history.bind(old)], func() -> void:
				if is_instance_valid(sheet) and sheet.is_inside_tree():
					sheet.refill())
		for h in Toasts.history:
			var it = ListItemC.new()
			var tx: Array = Toasts.texte(h)
			it.setup(str(tx[0]), str(tx[1]), tr(U.ago(int(h.at))))
			it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			it.sub_lines = 3
			it.icon_name = str(h.icon)
			if str(h.get("image", "")) != "":
				it.image_url = str(h.image)
			var go: Callable = h.get("go", Callable())
			if go.is_valid():
				it.set_meta("uz_hint_a", str(h.get("go_text", "Öffnen")))
				it.activated.connect(open_note.bind(h))
			else:
				it.set_meta("uz_hint_a", "—")
			it.set_meta("uz_hint_y", "Alle entfernen")
			it.set_meta("uz_on_y", leeren)
			sheet.add_row(it)
	open_layer(s)


## Mitteilungen: oben „Steam-Nachrichten – Nicht verbunden“, wenn Steam-Pop-ups an sind, Steam auf dem PC ist
## und Uzai dort nicht angemeldet ist (weg: SteamChat.weg). (rein, getestet)
static func steam_hint_due(weg: String, steam_da: bool, demo: bool) -> bool:
	return weg == "keiner" and steam_da and not demo


## Eine Mitteilung aus der Liste öffnen: dorthin, worum es ging (Chat, Spiel, Erfolge). Das Ziel
## kommt über den Guide bzw. die Liste, B führt zurück. false, wenn sie kein Ziel hat.
func open_note(h: Dictionary) -> bool:
	var go: Callable = h.get("go", Callable())
	if not go.is_valid():
		return false
	go.call()
	return true


## Ziel einer Mitteilung zu einem Spiel: außerhalb des Spiels seine Seite (der Guide geht dafür
## zu), im Spiel seine Erfolge über dem Guide (die Spielseite würde starten wollen).
func open_game_note(g: Dictionary) -> void:
	var cur := Library.get_game(str(g.get("id", "")))
	if cur.is_empty():
		Toasts.show_toast("Spiel nicht mehr da", "%s ist nicht mehr in der Bibliothek." % str(g.get("title", "Das Spiel")), "warning",
				{ "quiet": true, "sound": "error" })
		return
	if Launcher.in_game:
		open_game_achievements(cur)
		return
	if _guide and is_instance_valid(_guide):
		_guide.close()
	await alle_ebenen_zu()
	if game_page_on():
		var l = GamePage.new()
		l.game = cur
		open_layer(l)
	else:
		open_game_options(cur)
