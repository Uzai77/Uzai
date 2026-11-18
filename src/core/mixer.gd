extends Node
## Lautstärkemixer und Mikrofon (Punkte 22 und 12).
##
## Der Mixer zeigt nur Programme, die gerade Ton ausgeben: oben die Gesamtlautstärke, dann das
## laufende Spiel (samt Kindprozessen, auch wenn es kurz still ist), Uzai, Musik, Discord, Video
## und Browser, danach der Rest. Je Zeile ändern links/rechts den Pegel, A schaltet stumm. Der
## Windows-Helfer stellt dafür nur Pegel und Stumm (mixer, mixer-set, master-set) – wie der
## Lautstärkemixer von Windows, ohne dessen Fenster.
##
## „Mikro stumm“ (toggle_mic) schaltet mit einem Druck das Mikrofon von Windows (Standard- und
## Kommunikationsgerät, Befehl mic, nur Benutzerrechte) und, wenn Discord verbunden ist, dazu das
## Discord-Mikro über die offizielle RPC-Verbindung (Voice). Solange es aus ist, steht oben in der
## Kopfleiste und im Guide ein kleiner Hinweis (mic_badge.gd).
##
## Zeilen bauen und Antworten lesen ist statisch und ohne Windows testbar (tests/logic_mixer.gd);
## in der Demo geben ein paar erfundene Programme Ton aus.

const Fremd := preload("res://src/core/fremd.gd")

## Nachts leiser (src/core/nacht_ton.gd) hängt als Kind am Mixer: nachts geht die Gesamtlautstärke
## nicht über die Grenze.

## Mikrofon stumm bzw. wieder an (Windows oder – ohne Helfer – Discord).
signal mic_changed(muted: bool)
## Der Helfer hat einen Pegel gesetzt: echter Stand der Zeile (level -1: Programm ist weg).
signal row_changed(id: String, level: int, mute: bool)

const NachtTon := preload("res://src/core/nacht_ton.gd")
const Tonwahl := preload("res://src/core/tonwahl.gd")
const STEP := 5                 ## Prozentpunkte je Druck links/rechts
const MAX_OTHERS := 6           ## weitere Programme unter den bekannten
const MIC_POLL_S := 20.0        ## so oft den Stand des Mikrofons nachsehen (nur außerhalb eines Spiels)
const BROWSERS := { "chrome": "Chrome", "msedge": "Edge", "firefox": "Firefox", "opera": "Opera",
	"brave": "Brave", "vivaldi": "Vivaldi", "librewolf": "LibreWolf", "waterfox": "Waterfox" }
## Reihenfolge der bekannten Zeilen (alles andere danach, nach Name).
const ORDER := ["master", "spiel", "uzai", "musik", "discord", "video", "browser"]

var mic_muted := false          ## Mikrofon aus
var mic_known := false          ## Stand von Windows bekannt (sonst gilt das Discord-Mikro)
var mic_name := ""              ## Name des Mikrofons laut Windows

var _pending := {}              ## Zeilen-ID -> noch zu schicken { kind, pids, level, mute }
var _busy := {}                 ## Zeilen-ID -> ein Befehl läuft
var _demo_state := {}           ## Demo: Zeilen-ID -> { level, mute }
var _demo_mic := false
var tonwahl: Tonwahl             ## festes Ausgabegerät und FxSound (src/core/tonwahl.gd)


func _ready() -> void:
	Voice.changed.connect(_on_voice)
	add_child(NachtTon.new())
	tonwahl = Tonwahl.new()
	add_child(tonwahl)
	# Erst nach dem Start (der Audio-Teil des Helfers wird beim ersten Gebrauch übersetzt) und nur,
	# solange Uzai vorn ist und kein Spiel läuft; der Guide fragt beim Öffnen selbst nach.
	var t := Timer.new()
	t.wait_time = MIC_POLL_S
	t.timeout.connect(func() -> void:
		if not Launcher.in_game and get_window().has_focus():
			refresh_mic()
	)
	add_child(t)
	t.start()


func _is_demo() -> bool:
	return Library.demo and not Config.is_windows()


# --- Mixer ---------------------------------------------------------------------------------

## Was gerade Ton ausgibt, als fertige Zeilen: { ok, rows, error }.
func snapshot() -> Dictionary:
	if _is_demo():
		return { "ok": true, "rows": rows(_demo_data(), context()), "error": "" }
	if not Config.is_windows() or not Helper.available:
		return { "ok": false, "rows": [], "error": "Der Mixer braucht den Windows-Helfer." }
	var args := game_args(Launcher.pid if Launcher.in_game else 0, str(Launcher.current.get("install_dir", "")) if Launcher.in_game else "",
		Launcher.game_hwnd() if Launcher.in_game else 0)
	args["skip"] = [OS.get_process_id()]
	var data := parse_list(await Helper.run("mixer", args, 5.0))
	if not bool(data.get("found", false)):
		return { "ok": false, "rows": [], "error": "Windows hat die Lautstärken gerade nicht verraten." if bool(data.get("error", false)) else "" }
	return { "ok": true, "rows": rows(data, context()), "error": "" }


## Was zum Zuordnen nötig ist: Uzai, Video, Musik-App und Spiel.
func context() -> Dictionary:
	var keys: Array = ["spotify"]
	if str(Music.now.get("source", "")) == "windows":
		keys = Music.audio_keys(str(Music.now.get("app", ""))) + keys
	return {
		"uzai_pid": OS.get_process_id(),
		"video_pid": Video.mpv_pid(),
		"music_keys": keys,
		"music_app": str(Music.now.get("device", "")) if str(Music.now.get("source", "")) == "windows" else "",
		"local_music": Music.local_on() and not Music.now.is_empty(),
		"game": Library.display_title(Launcher.current) if Launcher.in_game else "",
	}


## Pegel einer Zeile setzen (0..100). Schnell hintereinander gedrückt, geht nur der letzte
## Stand zum Helfer; row_changed meldet danach den echten.
func set_level(row: Dictionary, level: int, unmute := false) -> void:
	var l := clampi(level, 0, 100)
	if str(row.get("kind", "")) == "master":
		l = NachtTon.begrenzt(l)
	_queue(row, l, 0 if unmute else -1)


## Wartet für diese Zeile noch ein Stand auf den Helfer? (Dann nicht mit älteren Werten überschreiben.)
func pending(id: String) -> bool:
	return _pending.has(id)


## Zeile stumm bzw. wieder hörbar.
func set_mute(row: Dictionary, on: bool) -> void:
	_queue(row, -1, 1 if on else 0)


func _queue(row: Dictionary, level: int, mute: int) -> void:
	var id := str(row.get("id", ""))
	if id == "":
		return
	var p: Dictionary = _pending.get(id, { "kind": str(row.get("kind", "app")), "pids": row.get("pids", []), "level": -1, "mute": -1,
		"was": [int(row.get("level", 100)), bool(row.get("mute", false))] })
	if level >= 0:
		p.level = level
	if mute >= 0:
		p.mute = mute
	_pending[id] = p
	if _busy.has(id):
		return
	_busy[id] = true
	while _pending.has(id):
		var job: Dictionary = _pending[id]
		_pending.erase(id)
		var r := await _apply(id, job)
		if bool(r.get("found", false)):
			row_changed.emit(id, int(r.level), bool(r.mute))
		elif not bool(r.get("error", false)):
			row_changed.emit(id, -1, false)
	_busy.erase(id)


func _apply(id: String, job: Dictionary) -> Dictionary:
	if _is_demo():
		var st: Dictionary = _demo_state.get(id, { "level": int(job.was[0]), "mute": bool(job.was[1]) })
		if int(job.level) >= 0:
			st.level = int(job.level)
		if int(job.mute) >= 0:
			st.mute = int(job.mute) == 1
		_demo_state[id] = st
		return { "found": true, "level": int(st.level), "mute": bool(st.mute) }
	if not Helper.available:
		return { "found": false, "error": true }
	if str(job.kind) == "master":
		return parse_set(await Helper.run("master-set", { "level": int(job.level), "mute": int(job.mute) }, 4.0))
	var pids: Array = (job.pids as Array).map(func(x: Variant) -> int: return int(x)).filter(func(x: int) -> bool: return x > 4)
	if pids.is_empty():
		return { "found": false, "error": false }
	return parse_set(await Helper.run("mixer-set", { "pids": pids.slice(0, 64), "level": int(job.level), "mute": int(job.mute) }, 4.0))


## Was der Helfer für das Spiel braucht: Spiel samt Kindprozessen (Prozess, Spielordner, Fenster).
## Ohne Prozess, Ordner und Fenster: leer (dann kein Befehl). Für Mixer, Guide und Ruhemodus.
static func game_args(game_pid: int, install_dir: String, hwnd: int) -> Dictionary:
	var a := {}
	if game_pid > 0:
		a["pids"] = [game_pid]
	if install_dir.strip_edges() != "":
		a["dir"] = install_dir.strip_edges().replace("/", "\\")
	if hwnd != 0:
		a["hwnd"] = hwnd
	return a


## Antwort von „mixer“: { found, error, master: { level, mute, device } | {}, apps: [...] }.
static func parse_list(r: Dictionary) -> Dictionary:
	var d := _json(r)
	if d.is_empty():
		return { "found": false, "error": true }
	if not bool(d.get("found", false)):
		return { "found": false, "error": d.has("error") or d.has("timeout") }
	var apps: Array = []
	for a in d.get("apps", []):
		if a is Dictionary and int(a.get("pid", 0)) > 4:
			apps.append({ "pid": int(a.pid), "name": str(a.get("name", "")).to_lower(), "desc": str(a.get("desc", "")).strip_edges(),
				"level": clampi(int(a.get("level", 100)), 0, 100), "mute": bool(a.get("mute", false)),
				"game": bool(a.get("game", false)), "active": bool(a.get("active", true)) })
	var m: Variant = d.get("master")
	var master: Dictionary = {}
	if m is Dictionary:
		master = { "level": clampi(int(m.get("level", 0)), 0, 100), "mute": bool(m.get("mute", false)), "device": str(m.get("device", "")) }
	return { "found": true, "error": false, "master": master, "apps": apps }


## Antwort von „mixer-set“, „master-set“: { found, level, mute, error }.
static func parse_set(r: Dictionary) -> Dictionary:
	var d := _json(r)
	if d.is_empty():
		return { "found": false, "level": -1, "mute": false, "error": true }
	if not bool(d.get("found", false)):
		return { "found": false, "level": -1, "mute": false, "error": d.has("error") or d.has("timeout") }
	return { "found": true, "level": clampi(int(d.get("level", 0)), 0, 100), "mute": bool(d.get("mute", false)), "error": false }


static func _json(r: Dictionary) -> Dictionary:
	var res: Variant = r.get("result")
	if not bool(r.get("ok", false)) or not (res is Dictionary):
		return {}
	# Mit Fremd.json: Der Helfer schreibt für „unbekannt“ null (ein Programm ohne Beschreibung, ein Gerät ohne
	# Pegel) – als „fehlt“ gelesen greifen die Ersatzwerte, statt dass int(null) die ganze Liste abbricht.
	var parsed: Variant = Fremd.json(str((res as Dictionary).get("json", "")))
	return parsed if parsed is Dictionary else {}


## Die Zeilen des Mixers aus der Antwort (parse_list) und dem Zusammenhang (context):
## [{ id, kind, title, sub, icon, pids, level, mute }]. Mehrere Prozesse eines Programms (Browser,
## Discord) werden eine Zeile; deren Pegel ist der lauteste, stumm nur, wenn alle stumm sind.
static func rows(data: Dictionary, c: Dictionary) -> Array:
	var out: Array = []
	var master: Dictionary = data.get("master", {})
	if not master.is_empty():
		var dev := str(master.get("device", ""))
		out.append({ "id": "master", "kind": "master", "title": "Gesamt", "sub": dev if dev != "" else "Alles, was der PC ausgibt",
			"icon": "volume", "pids": [], "level": int(master.level), "mute": bool(master.mute) })
	var groups := {}
	var others: Array = []
	for a in data.get("apps", []):
		var g := classify(a, c)
		var id := str(g.id)
		if not groups.has(id):
			groups[id] = g.merged({ "kind": "app", "pids": [], "level": 0, "mute": true, "active": false }, false)
			if not (id in ORDER):
				others.append(id)
		var row: Dictionary = groups[id]
		(row.pids as Array).append(int(a.pid))
		row.level = maxi(int(row.level), int(a.level))
		row.mute = bool(row.mute) and bool(a.mute)
		row.active = bool(row.active) or bool(a.get("active", true))
	for id in ORDER:
		if groups.has(id):
			out.append(groups[id])
	others.sort_custom(func(x: String, y: String) -> bool: return str(groups[x].title).naturalnocasecmp_to(str(groups[y].title)) < 0)
	for id in others.slice(0, MAX_OTHERS):
		out.append(groups[id])
	for r in out:
		r.erase("active")
	return out


## Welche Zeile ein Programm bekommt: { id, title, sub, icon }.
static func classify(a: Dictionary, c: Dictionary) -> Dictionary:
	var pid := int(a.get("pid", 0))
	var name := str(a.get("name", "")).to_lower()
	var desc := str(a.get("desc", ""))
	if bool(a.get("game", false)):
		var gt := str(c.get("game", ""))
		return { "id": "spiel", "title": gt if gt != "" else "Spiel", "sub": "Das laufende Spiel", "icon": "games" }
	if pid > 0 and pid == int(c.get("uzai_pid", 0)):
		return { "id": "uzai", "title": "Uzai", "sub": "Menüklänge und deine Musik" if bool(c.get("local_music", false)) else "Menüklänge und Vorschauen",
				"icon": "spark" }
	if pid > 0 and pid == int(c.get("video_pid", 0)):
		return { "id": "video", "title": "Video", "sub": "YouTube, Twitch und Filme in Uzai", "icon": "video" }
	if name in (c.get("music_keys", []) as Array):
		var app := str(c.get("music_app", ""))
		return { "id": "musik", "title": app if app != "" else ("Spotify" if name.begins_with("spotify") else _nice(name, desc)), "sub": "Musik", "icon": "music" }
	if name.begins_with("discord"):
		return { "id": "discord", "title": "Discord", "sub": "Sprachkanal und Anrufe", "icon": "discord" }
	if BROWSERS.has(name):
		return { "id": "browser", "title": str(BROWSERS[name]), "sub": "Browser", "icon": "monitor" }
	return { "id": "app:" + name, "title": _nice(name, desc), "sub": name + ".exe" if name != "" else "", "icon": "speaker" }


## Name eines Programms: die Beschreibung aus der Programmdatei („Steam Client WebHelper“),
## sonst der Dateiname mit großem Anfang.
static func _nice(name: String, desc: String) -> String:
	if desc != "":
		return desc
	return name.capitalize() if name != "" else "Programm"


## Wert rechts in der Zeile: „45 %“ oder „Stumm“.
static func level_text(level: int, mute: bool) -> String:
	return "Stumm" if mute else "%d %%" % clampi(level, 0, 100)


## Neuer Pegel nach links/rechts (in STEP-Schritten, an den Rändern fest).
static func step_level(level: int, dir: int) -> int:
	return clampi(snappedi(level, STEP) + STEP * signi(dir), 0, 100)


## Demo ohne Windows: ein Spiel, Musik, Discord, ein Browser und ein Programm geben Ton aus.
func _demo_data() -> Dictionary:
	var c := context()
	var apps: Array = []
	if Launcher.in_game:
		apps.append({ "pid": 4100, "name": "game", "desc": "", "level": 100, "mute": false, "game": true })
	apps.append({ "pid": int(c.uzai_pid), "name": "uzai", "desc": "", "level": 100, "mute": false })
	apps.append({ "pid": 4200, "name": "spotify", "desc": "Spotify", "level": 70, "mute": false })
	apps.append({ "pid": 4300, "name": "discord", "desc": "Discord", "level": 90, "mute": false })
	apps.append({ "pid": 4301, "name": "discord", "desc": "Discord", "level": 90, "mute": false })
	apps.append({ "pid": 4400, "name": "msedge", "desc": "Microsoft Edge", "level": 55, "mute": true })
	apps.append({ "pid": 4500, "name": "obs64", "desc": "OBS Studio", "level": 100, "mute": false })
	var data := { "found": true, "master": { "level": 62, "mute": false, "device": "Wohnzimmer-TV (HDMI)" }, "apps": apps }
	# Was in der Demo schon verstellt wurde, bleibt (wie bei Windows).
	for r in rows(data, c):
		if _demo_state.has(str(r.id)):
			var st: Dictionary = _demo_state[str(r.id)]
			if str(r.id) == "master":
				data.master.level = int(st.level)
				data.master.mute = bool(st.mute)
			else:
				for a in apps:
					if int(a.pid) in (r.pids as Array):
						a.level = int(st.level)
						a.mute = bool(st.mute)
	return data


# --- Mikrofon ------------------------------------------------------------------------------

## Mikro stumm bzw. wieder an – mit einem Druck (Guide, Schnellmenü): Windows-Mikrofon und, wenn
## verbunden, das Discord-Mikro. Zeigt kurz, was passiert ist (im Spiel über dem Spiel).
func toggle_mic() -> void:
	await set_mic(not mic_aus())


## Mikro aus? Das Windows-Mikrofon oder das eigene in Discord – ein Zustand für jede Anzeige
## (Schnellleiste, Schnellmenü, deine Zeile im Sprachkanal, das Menü an dir selbst).
func mic_aus() -> bool:
	return mic_muted or (Voice.ready_() and Voice.self_mute)


func set_mic(on: bool) -> void:
	var win := false
	if _is_demo():
		_demo_mic = on
		mic_known = true
		mic_name = "Headset-Mikrofon"
		win = true
	elif Config.is_windows() and Helper.available:
		var r := parse_mic(await Helper.run("mic", { "mute": 1 if on else 0 }, 4.0))
		if bool(r.found):
			mic_known = true
			mic_name = str(r.name)
			on = bool(r.mute)
			win = true
	var discord := Voice.ready_()
	if discord and Voice.self_mute != on:
		Voice.set_self_mute(on)
	if not win and not discord:
		Toasts.show_toast("Kein Mikrofon gefunden", "Windows meldet kein Aufnahmegerät, und Discord ist nicht verbunden.", "mic",
				{ "ms": 4000, "quiet": true, "overlay": true })
		return
	_set_muted(on)
	Sfx.play("toggle_off" if on else "toggle_on")
	Toasts.show_toast("Mikro aus" if on else "Mikro an", mic_text(win, discord, mic_name), "mic_off" if on else "mic",
			{ "ms": 2400, "quiet": true, "overlay": true })


## Zweite Zeile der Meldung: welches Mikrofon, und ob Discord mitgeschaltet wurde.
static func mic_text(win: bool, discord: bool, name: String) -> String:
	if win and discord:
		return ("%s · auch in Discord" % name) if name != "" else "Windows und Discord"
	if win:
		return name if name != "" else "Mikrofon von Windows"
	return "Nur in Discord"


## Stand des Windows-Mikrofons nachsehen (z. B. in Windows oder am Headset umgeschaltet).
func refresh_mic() -> void:
	if _is_demo():
		mic_known = true
		mic_name = "Headset-Mikrofon"
		_set_muted(_demo_mic)
		return
	if not Config.is_windows() or not Helper.available:
		return
	var r := parse_mic(await Helper.run("mic", { "mute": -1 }, 4.0))
	if bool(r.found):
		mic_known = true
		mic_name = str(r.name)
		_set_muted(bool(r.mute))


## Wie refresh_mic, aber nicht gleich beim Start (dann übernimmt der regelmäßige Blick).
func refresh_soon() -> void:
	if Time.get_ticks_msec() > int(MIC_POLL_S * 1000.0):
		refresh_mic()


## Antwort von „mic“: { found, mute, name }.
static func parse_mic(r: Dictionary) -> Dictionary:
	var d := _json(r)
	if not bool(d.get("found", false)):
		return { "found": false, "mute": false, "name": "" }
	return { "found": true, "mute": bool(d.get("mute", false)), "name": str(d.get("name", "")).strip_edges() }


## Ohne Windows-Mikrofon gilt das Discord-Mikro (auch in Discord selbst umgeschaltet).
func _on_voice() -> void:
	if not mic_known:
		_set_muted(Voice.ready_() and Voice.self_mute)


func _set_muted(on: bool) -> void:
	if on == mic_muted:
		return
	mic_muted = on
	mic_changed.emit(on)
