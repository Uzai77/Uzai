extends Node
## Brücke zu Windows. Startet helper/uzai-helper.ps1 einmal im Hintergrund und schickt
## ihm Befehle (Fenster fokussieren, Emulator pausieren, Tasten, Medientasten, Discord-Status).
## Auf anderen Systemen tut sie nichts und meldet { ok = false }.

const Logdatei := preload("res://src/core/logdatei.gd")
const Fremd := preload("res://src/core/fremd.gd")

signal helper_ready
signal pad_event(kind: String)    ## vom Controller-Wächter, auch wenn ein Spiel im Vordergrund ist
signal rpc_event(kind: String, msg: Variant)   ## von der Discord-Leitung ("discord", "discord-closed")
signal dsdk_event(msg: Variant)                ## vom Discord Social SDK (Nachrichten, Zustand)

var available := false
var _script := ""
var _next_id := 1

## Zwei Helfer-Prozesse: der Hauptweg für alles mit Zustand oder langer Laufzeit (Discord, Musik-
## Infos, Prozesssuche, Controller-Wächter) und ein schneller Weg nur für zeitkritische Befehle.
## Vorher lief alles nacheinander durch einen Prozess: Eine Musik-Abfrage (bis 3 s) oder ein
## Discord-Befehl (bis 20 s) hielt Fokus, Pause und Spielstart auf – im Guide über dem Spiel
## reagierte der Controller dann erst Sekunden später.
const FAST := ["focus", "spiel-minimieren", "keys", "kill", "suspend", "resume", "alive", "start", "new-window", "windows-snapshot",
	"hide-windows", "show-hidden", "steam-running", "no-anim", "toast-window", "pad-count", "media", "discs", "volume",
	"window-alive", "close-window", "steam-state", "steam-silent", "cover", "window-state", "cursor-park",
	"live-keys", "discord-front", "app-volume", "lossless", "lossless-start", "pad-pulse", "pad-off", "pip",
	"window-hung", "exit-code", "mixer", "mixer-set", "master-set", "mic", "vorhang", "vorhang-wache", "raum-ton", "prozessbaum", "baum-beenden",
	"app-start", "app-window", "app-vollbild"]

## Vorhang und Wache (UzEbenen im Helfer) leben in einem Prozess: alles dorthin, wohin der
## erste dieser Befehle ging – sonst zöge ein „aus“ im anderen Prozess ins Leere. Das ist der schnelle
## Weg, sobald sein Prozess läuft (auch wenn er noch übersetzt: dann wartet der Befehl kurz). Früher
## nahm der erste Befehl (5 s nach dem Start, der schnelle Weg war noch nicht bereit) den Hauptweg –
## und Vorhang und Wache warteten dort für immer hinter Discord, Musik und der Prozesssuche: Uzai
## gab nach einer Sekunde auf und räumte sich weg, bevor der Vorhang stand.
## Ebenso der Ton aus dem Fernseher („raum-ton“, src/room/raumton.gd): Der Helfer merkt sich die
## Kanal-Lautstärken von vorher – „aus“ muss in denselben Prozess.
const EBENEN := ["vorhang", "vorhang-wache", "raum-ton"]

## Befehle, die nicht hinter einem anderen warten sollen: Ist ihr Weg gerade beschäftigt und der
## andere frei, nehmen sie den anderen (Discord-Übertragung: Ein voller schneller Weg ließ den
## Tastendruck früher in die Zeitüberschreitung laufen). Nur für Befehle ohne Reihenfolge-Bezug
## (anhalten/fortsetzen dürfen nie überholen).
const EITHER := ["live-keys", "discord-front"]

var _main := Lane.new("main")
var _fast := Lane.new("fast")
var _cover_lane: Lane            ## bekam das letzte „cover an“ (siehe run)
var _ebenen_lane: Lane           ## führt Vorhang, Wache und Raumton (siehe EBENEN)
var _hide_lane: Lane             ## bekam das letzte „hide-windows“ (ShaderGlass beim Guide, siehe run)
var _voll_lane: Lane             ## bekam das letzte „app-vollbild“ an (merkt sich, wie das App-Fenster vorher war)

## Kommt eine Minute lang keine Antwort, obwohl Befehle warten, hängt der Helfer (z. B. an einer
## Discord-Leitung): beenden und neu starten. Höchstens 3 Neustarts je 10 Minuten.
const HUNG_MS := 60000
const RESTART_WINDOW_MS := 600000


class Lane:
	var name := ""
	var io: FileAccess
	var err: FileAccess
	var pid := 0
	var buf := PackedByteArray()
	var ready := false
	var replies := {}
	var inflight := {}          ## id -> Zeitpunkt (ms): Befehle, auf deren Antwort jemand wartet
	var dropped := {}           ## ids nach Zeitüberschreitung: späte Antworten verwerfen
	var last_reply_ms := 0
	var restart_times: Array = []
	var started_ms := 0

	func _init(n: String) -> void:
		name = n


func _ready() -> void:
	if (not Config.is_windows() or Remote.is_second) and _test_shell() == "":
		set_process(false)
		return
	_script = _extract()
	_start(_main)
	# Den zweiten etwas später: Beide übersetzen beim Start denselben C#-Teil, das soll nicht mit
	# der Startanimation um die Rechenzeit kämpfen. Bis dahin geht alles über den Hauptweg.
	get_tree().create_timer(4.0).timeout.connect(func() -> void: _start(_fast))


## Windows PowerShell mit vollem Pfad: nie ein Programm gleichen Namens aus dem Uzai- oder
## Arbeitsordner (Windows sucht dort zuerst).
static func ps_exe() -> String:
	var root := OS.get_environment("SystemRoot")
	var p := root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	return p.replace("/", "\\") if root != "" and FileAccess.file_exists(p) else "powershell.exe"


## Windows PowerShell für 32 Bit (lädt 32-Bit-Bibliotheken wie steam_api.dll), mit vollem Pfad. "" = nicht da:
## run_once nimmt dann das übliche PowerShell, und der Helfer meldet, dass die Bibliothek nicht passt. Nie ein
## Pfad ohne Laufwerk – ohne den Windows-Ordner entstünde sonst einer, der im Arbeitsordner gesucht würde.
static func ps32_exe() -> String:
	var root := OS.get_environment("SystemRoot")
	if root == "":
		root = OS.get_environment("WINDIR")
	var p := root.path_join("SysWOW64/WindowsPowerShell/v1.0/powershell.exe")
	return p.replace("/", "\\") if root != "" and FileAccess.file_exists(p) else ""


## Nur für Tests: PowerShell 7 unter Linux (UZAI_HELPER_SHELL=<pfad zu pwsh>) statt Windows-PowerShell.
static func _test_shell() -> String:
	return Config.probe_env("UZAI_HELPER_SHELL")


func _extract() -> String:
	var dest := Config.path("helper/uzai-helper.ps1")
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var src := FileAccess.get_file_as_bytes("res://helper/uzai-helper.ps1")
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f:
		# Mit BOM speichern, damit Windows PowerShell 5 Umlaute richtig liest.
		f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
		f.store_buffer(src)
		f.close()
	return dest


## Zeichen, bei denen Godot unter Windows ein Argument in Anführungszeichen setzt.
const WIN_QUOTE_CHARS := " &()[]{}^=;!'+,`~"


## Argumente für OS.create_process / OS.execute_with_pipe (Punkt 73). Godot setzt ein Argument
## unter Windows nur in Anführungszeichen, maskiert darin aber nichts: Ein „"“ – etwa aus einem
## Titel, einer Suche oder einem Addon – beendete das Argument vorzeitig, und der Rest wurde zu
## eigenen Optionen des Programms (bei mpv bis hin zu einem fremden Skript). Darum: keine
## Steuerzeichen, „"“ wird zu „'“, und ein Rückstrich am Ende eines Arguments in Anführungszeichen
## wird verdoppelt (sonst hebt er das schließende Zeichen auf). Unter Linux bleibt alles, wie es ist.
static func win_args(args: PackedStringArray, windows := (OS.get_name() == "Windows")) -> PackedStringArray:
	if not windows:
		return args
	var out := PackedStringArray()
	for raw in args:
		var a := ""
		for ch in raw:
			var c := ch.unicode_at(0)
			if c < 0x20 or c == 0x7F:
				continue
			a += "'" if ch == "\"" else ch
		var quoted := false
		for ch in WIN_QUOTE_CHARS:
			if a.contains(ch):
				quoted = true
				break
		if quoted:
			var n := 0
			while n < a.length() and a[a.length() - 1 - n] == "\\":
				n += 1
			a += "\\".repeat(n)
		out.append(a)
	return out


func _ps_args(extra: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var a := PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", _script])
	if _test_shell() != "":
		# PowerShell 7 unter Linux kennt -WindowStyle nicht.
		a = PackedStringArray(["-NoProfile", "-NonInteractive", "-File", _script])
	a.append_array(extra)
	return a


func _start(l: Lane) -> void:
	var info: Dictionary = OS.execute_with_pipe(_test_shell() if _test_shell() != "" else ps_exe(), _ps_args(), false)
	if info.is_empty():
		push_warning("Uzai: Windows-Helfer (%s) konnte nicht starten" % l.name)
		hlog("%s: PowerShell ließ sich nicht starten" % l.name)
		return
	l.io = info.get("stdio")
	l.err = info.get("stderr")
	l.pid = int(info.get("pid", 0))
	l.buf.clear()
	l.started_ms = Time.get_ticks_msec()
	hlog("%s: gestartet (PowerShell %d)" % [l.name, l.pid])


func _process(_dt: float) -> void:
	for l in [_main, _fast]:
		_pump(l)


func _pump(l: Lane) -> void:
	if l.io == null:
		return
	var chunk := l.io.get_buffer(8192)
	# Fehlerkanal mitlesen: Läuft er voll, bleibt PowerShell beim nächsten Schreiben stehen.
	if l.err:
		var e := l.err.get_buffer(8192)
		if e.size() > 0:
			hlog("%s meldet: %s" % [l.name, e.get_string_from_utf8().strip_edges().left(4000)])
	if chunk.size() > 0:
		l.buf.append_array(chunk)
		while true:
			var nl := l.buf.find(10)
			if nl < 0:
				break
			var line := l.buf.slice(0, nl).get_string_from_utf8().strip_edges()
			l.buf = l.buf.slice(nl + 1)
			_on_line(l, line)
	if Engine.get_process_frames() % 60 == 0 and l.ready and not l.inflight.is_empty():
		var now := Time.get_ticks_msec()
		var oldest := now
		for t in l.inflight.values():
			oldest = mini(oldest, int(t))
		if now - oldest > HUNG_MS and now - l.last_reply_ms > HUNG_MS:
			_restart(l, "antwortet seit einer Minute nicht")
	if Engine.get_process_frames() % 180 == 0 and l.pid > 0 and not OS.is_process_running(l.pid):
		_restart(l, "beendet")


func _restart(l: Lane, why: String) -> void:
	push_warning("Uzai: Windows-Helfer (%s) %s – Neustart" % [l.name, why])
	hlog("%s: %s – Neustart%s" % [l.name, why, "" if l.ready else " (war noch nie bereit)"])
	# Den Fehlerkanal des alten Prozesses noch auslesen: Dort steht, warum er nicht lief.
	if l.err:
		var e := l.err.get_buffer(65536)
		if e.size() > 0:
			hlog("%s meldet: %s" % [l.name, e.get_string_from_utf8().strip_edges().left(4000)])
	l.ready = false
	if l == _main:
		available = false
	if l.pid > 0 and OS.is_process_running(l.pid):
		OS.kill(l.pid)
	l.io = null
	l.err = null
	for id in l.inflight.keys():
		l.dropped[id] = true
	l.inflight.clear()
	var now := Time.get_ticks_msec()
	l.restart_times = l.restart_times.filter(func(t: int) -> bool: return now - t < RESTART_WINDOW_MS)
	if l.restart_times.size() >= 3:
		return
	l.restart_times.append(now)
	_start(l)


func _on_line(l: Lane, line: String) -> void:
	if line == "":
		return
	# Der Helfer schickt bei Erfolg „error: null“ und bei einem Fehler „result: null“ (PowerShell); mit
	# Fremd.json heißt das „fehlt“. Vorher wurde aus dem null der Text „<null>“ – als Fehlermeldung.
	var msg: Variant = Fremd.json(line)
	if not (msg is Dictionary):
		hlog("%s schreibt: %s" % [l.name, line.left(1000)])
		return
	var id := int(msg.get("id", -2))
	if id > 0:
		l.last_reply_ms = Time.get_ticks_msec()
		l.inflight.erase(id)
		if l.dropped.has(id):
			l.dropped.erase(id)
			return
	if id == -1:
		var ev := str(msg.get("event", ""))
		if ev == "dsdk":
			dsdk_event.emit(msg.get("msg", null))
		elif ev.begins_with("discord"):
			rpc_event.emit(ev, msg.get("msg", null))
		else:
			pad_event.emit(ev)
		return
	if id == 0:
		hlog("%s: bereit nach %.1f s" % [l.name, (Time.get_ticks_msec() - l.started_ms) / 1000.0])
		l.ready = true
		l.last_reply_ms = Time.get_ticks_msec()
		if l == _main:
			available = true
			helper_ready.emit()
			watch_pads()
			# Nach einem Neustart des Helfers (hing 60 s oder endete) kennt der neue Prozess den Auftrag nicht: wieder
			# scharf machen, sonst bliebe ein späterer Absturz ohne Neustart und ohne Guide-Wächter.
			if _crash_watch_scharf:
				arm_crash_watch()
			# Vom Wächter per Guide-Taste gestartet: Uzai sicher nach vorn (der Wächter versucht es
			# auch; Windows lässt neu gestartete Programme nicht immer vor).
			# Nur beim ersten Start des Helfers, nie nach einem Neustart mitten im Spiel.
			if not _woken_focused and WOKEN in OS.get_cmdline_user_args():
				_woken_focused = true
				run("focus", { "pid": OS.get_process_id() })
		return
	l.replies[id] = msg


## Startet den Controller-Wächter im Helfer (Guide-Taste im Spiel).
func watch_pads() -> void:
	run("pad-watch", { "combo": bool(Config.get_value("controller.guide_combo", true)) })


## Schickt einen Befehl und wartet auf die Antwort: { ok, result, error }. Nach einer
## Zeitüberschreitung zusätzlich timeout = true: der Befehl kann dann noch ausgeführt werden
## (der Helfer arbeitet der Reihe nach) – nie einfach selbst nachholen (doppelter Spielstart).
## Prozesse der Helfer (für die Leistungsmessung, src/core/perf.gd).
func pids() -> Array:
	return [_main, _fast].filter(func(l: Lane) -> bool: return l != null and l.pid > 0).map(func(l: Lane) -> int: return l.pid)


const KEINE_ANTWORT := "Helfer antwortet nicht"


## Kam auf einen Befehl gar keine Antwort (Helfer startet neu, ist beschäftigt, läuft nicht)? Dann lohnt ein späterer
## Versuch – anders als bei einer Absage, die sich nur wiederholen würde.
static func ohne_antwort(r: Dictionary) -> bool:
	return not Fremd.ja(r.get("ok")) and (Fremd.ja(r.get("timeout")) or str(r.get("error", "")) == KEINE_ANTWORT)


func run(cmd: String, args: Dictionary = {}, timeout := 6.0) -> Dictionary:
	if not Config.is_windows() and _test_shell() == "":
		return { "ok": false, "error": "nur unter Windows" }
	# Unter Windows heißt „keine Leitung“: Der Helfer läuft nicht (gestorben, Neustarts verbraucht) – früher stand dann
	# „Das geht nur am Windows-PC.“ auf dem Bildschirm.
	if _main.io == null:
		return { "ok": false, "error": KEINE_ANTWORT }
	var t0 := Time.get_ticks_msec()
	# Zeitkritisches über den schnellen Weg, solange er bereit ist; sonst wie bisher.
	var l: Lane = _fast if cmd in FAST and _fast.ready and _fast.io != null else _main
	# „cover“: Der Faden, der Uzai oben hält, läuft in dem Helfer, der „an“ bekam (in den ersten
	# Sekunden ist der schnelle Weg noch nicht bereit). „aus“ muss dorthin, sonst hielte er weiter.
	if cmd == "cover":
		if bool(args.get("on", false)):
			_cover_lane = l
		elif _cover_lane != null and _cover_lane.io != null:
			l = _cover_lane
	# „hide-windows“ merkt sich im Helfer, was es versteckt hat (ShaderGlass, solange der Guide offen
	# ist) – „show-hidden“ muss in denselben, sonst bliebe der Bildfilter unsichtbar.
	if cmd == "hide-windows":
		_hide_lane = l
	elif cmd == "show-hidden" and _hide_lane != null and _hide_lane.io != null:
		l = _hide_lane
	# „app-vollbild“ merkt sich im Helfer, wie das App-Fenster vorher war – „zurück“ muss in denselben.
	# („app-pad“ geht immer den Hauptweg: dort liest der Controller-Wächter.)
	if cmd == "app-vollbild":
		if bool(args.get("an", false)):
			_voll_lane = l
		elif _voll_lane != null and _voll_lane.io != null:
			l = _voll_lane
	if cmd in EBENEN:
		if _ebenen_lane == null or _ebenen_lane.io == null:
			_ebenen_lane = _fast if ebenen_weg(_fast.io != null) == "fast" else _main
		l = _ebenen_lane
	# mpv mit either = true (Video.volume: fester Wert, Reihenfolge egal) darf ebenso ausweichen –
	# sonst wartete die Lautstärke hinter der mpv-Abfrage und allem anderen im Hauptweg.
	if cmd in EITHER or (cmd == "mpv" and bool(args.get("either", false))):
		l = _main if pick_lane(_lane_info(_fast), _lane_info(_main)) == "main" else _fast
		if l == _fast and (not _fast.ready or _fast.io == null):
			l = _main
	var ahead := l.inflight.size()
	var ahead_ms := _busy_ms(l)
	if cmd in EITHER:
		hlog("%s: %s geschickt (%d Befehle davor, ältester seit %d ms)" % [l.name, cmd, ahead, ahead_ms])
	while not l.ready:
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return { "ok": false, "error": KEINE_ANTWORT }
	if l.io == null:
		return { "ok": false, "error": KEINE_ANTWORT }
	var id := _next_id
	_next_id += 1
	l.inflight[id] = Time.get_ticks_msec()
	l.io.store_string(JSON.stringify({ "id": id, "cmd": cmd, "args": args }) + "\n")
	l.io.flush()
	while not l.replies.has(id):
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			l.inflight.erase(id)
			l.dropped[id] = true
			hlog("%s: %s nach %.1f s ohne Antwort (%d Befehle davor, ältester seit %d ms)" % [l.name, cmd, timeout, ahead, ahead_ms])
			return { "ok": false, "error": "Zeitüberschreitung", "timeout": true, "lane": l.name, "ahead": ahead, "ahead_ms": ahead_ms }
	var r := antwort(l.replies[id])
	l.replies.erase(id)
	if not r.ok:
		hlog("%s: Befehl %s ging nicht: %s" % [l.name, cmd, str(r.error).left(600)])
	return r


## Was run() und run_once() aus einer Zeile des Helfers machen: { ok, result, error }. Fehlt etwas (der Helfer
## schickt bei Erfolg keinen Fehler und bei einem Fehler kein Ergebnis), steht dort {} bzw. "" – nie null.
static func antwort(msg: Variant) -> Dictionary:
	var d := Fremd.verz(msg)
	return { "ok": Fremd.ja(d.get("ok")), "result": d.get("result", {}), "error": Fremd.text(d.get("error")) }


## Welcher Weg Vorhang, Wache und Raumton bekommen (siehe EBENEN): der schnelle, sobald sein Prozess
## läuft – nie der Hauptweg, nur weil der schnelle gerade noch übersetzt.
static func ebenen_weg(fast_laeuft: bool) -> String:
	return "fast" if fast_laeuft else "main"


## Ein Fehler des Helfers als Satz für Menschen: was passiert ist und was man tun kann. Die
## rohe Meldung (oft eine englische Systemmeldung oder ein Code) steht schon in logs\helper.log;
## auf dem Bildschirm steht sie nie. rat: der Vorschlag, wenn der Fehler selbst keinen hat.
## Die Sätze kommen schon übersetzt heraus (zusammengesetzt fände sie der Katalog nicht).
static func klartext(err: String, rat := "Gleich noch einmal versuchen.") -> String:
	var e := err.strip_edges()
	var r := TranslationServer.translate(rat)
	match e.to_lower():
		"", "keine antwort":
			return TranslationServer.translate("Windows hat nicht geantwortet.") + " " + r
		"nur unter windows":
			return TranslationServer.translate("Das geht nur am Windows-PC.")
		"helfer antwortet nicht", "powershell startet nicht":
			return "%s %s %s" % [TranslationServer.translate("Uzais Windows-Helfer antwortet nicht."), r,
					TranslationServer.translate("Hilft das nicht, Uzai neu starten.")]
		"zeitüberschreitung":
			return TranslationServer.translate("Windows hat zu lange gebraucht.") + " " + r
	# Codes in Klammern („(88890008)“, „(0x80070005)“) weg; englische oder technische Meldungen
	# (Ausnahmen, Pfade, Codes) durch einen ruhigen Satz ersetzen.
	e = _CODE_RE.sub(e, "", true).strip_edges().trim_suffix(".")
	if e == "" or e.length() > 140 or _TECH_RE.search(e) != null:
		return TranslationServer.translate("Windows hat es nicht zugelassen.") + " " + r
	return TranslationServer.translate(e + ".") + " " + r

## Tastenbelegung für Discord oder Lossless Scaling (Helfer: keys mit global, live-keys) im engen
## Format, das auch der Helfer nur annimmt (Test-KeyCombo „global“): Strg, Alt, Umschalt und genau
## eine Taste aus A–Z, 0–9, F1–F24 – Buchstaben und Ziffern nur mit Strg oder Alt; nie die
## Windows-Taste, nie Alt+F4, keine Taste doppelt, höchstens 4 Tasten. Uzai prüft vorher selbst:
## Ein Kürzel aus fremden Einstellungen (Lossless Scaling) wird so gar nicht erst übernommen.
static func global_keys_ok(keys: String) -> bool:
	if keys.length() == 0 or keys.length() > 40 or _KEYS_RE.search(keys) == null:
		return false
	var seen := {}
	var main := ""
	for part in keys.to_upper().split("+", false):
		var p := part.strip_edges()
		if p == "":
			continue
		var k := ""
		if p in ["SHIFT", "UMSCHALT", "UMSCH", "LSHIFT", "RSHIFT"]:
			k = "shift"
		elif p in ["CTRL", "STRG", "CONTROL", "CTL", "LCTRL", "RCTRL"]:
			k = "ctrl"
		elif p in ["ALT", "LALT", "RALT", "ALTGR"]:
			k = "alt"
		elif p.length() == 1 or _FKEY_RE.search(p) != null:
			k = "taste"
			main = p
		else:
			return false
		if seen.has(k):
			return false
		seen[k] = true
	if main == "" or seen.size() > 4:
		return false
	if main.length() > 1:
		return not (main == "F4" and seen.has("alt"))
	return seen.has("ctrl") or seen.has("alt")


## Warum der Helfer eine Taste nicht gedrückt hat (Befehl „keys“), als Satz – "" = gedrückt.
## rat: der Vorschlag, wenn der Grund selbst keinen hat. Sätze kommen schon übersetzt heraus.
static func keys_text(r: Dictionary, rat: String) -> String:
	if not bool(r.get("ok", false)):
		return klartext(str(r.get("error", "")), rat)
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	if bool(res.get("sent", false)):
		return ""
	var t := TranslationServer.translate(rat)
	match str(res.get("reason", "")):
		"nicht vorn":
			if str(res.get("window", "")) == "":
				return TranslationServer.translate("Spielfenster nicht gefunden.") + " " + t
			return TranslationServer.translate("Windows hat das Spiel nicht nach vorn gelassen – Uzai drückt Tasten nur dort.") + " " + t
		"nicht erlaubt":
			return TranslationServer.translate("Dieses Tastenkürzel lässt Uzai nicht zu.") + " " + t
		"unbekannt":
			return TranslationServer.translate("Uzai versteht das Tastenkürzel nicht.") + " " + t
		"geschützt":
			return TranslationServer.translate("Vorn liegt ein Anmelde- oder Sicherheitsfenster von Windows – dorthin drückt Uzai nie Tasten.")
		"zu oft":
			return TranslationServer.translate("Gerade erst gedrückt – einen Moment warten.")
	return TranslationServer.translate("Windows hat es nicht zugelassen.") + " " + t

static var _KEYS_RE := RegEx.create_from_string("^[A-Za-z0-9+ ]+\\z")
static var _FKEY_RE := RegEx.create_from_string("^F([1-9]|1[0-9]|2[0-4])\\z")

const _CODE_PAT :="\\s*\\(((0x)?[0-9A-Fa-f]*\\d[0-9A-Fa-f]*|(Fehler|Code|HTTP)\\s*[0-9A-Fa-fx]+)[^)]*\\)"
const _TECH_PAT := "(?i)exception|hresult|0x[0-9a-f]{4,}|\\b(the|is|was|not|cannot|could|failed|denied|error|access|object|reference|null|argument|path|file|because|unable)\\b|[A-Za-z]:\\\\|\\bat line\\b|\\w+\\.\\w+\\("
static var _CODE_RE := RegEx.create_from_string(_CODE_PAT)
static var _TECH_RE := RegEx.create_from_string(_TECH_PAT)


## Lautstärke einzelner Programme wie im Lautstärkemixer von Windows – nie die Gesamtlautstärke.
## args: pids/dir/hwnd (Spiel samt Kindprozessen, Video) oder keys (Musik-App, siehe
## Music.audio_keys); delta in Prozentpunkten (0 = nur lesen). Uzai selbst ist immer ausgenommen.
## Rückgabe { found, level 0..100, mute, error }; found = false: kein Ton dieses Programms
## gefunden; error = true: Helfer nicht erreichbar oder Zeitgrenze (dann weiß Uzai es nicht).
var _audio_warm := false   ## der Audio-Teil des Helfers ist übersetzt (das erste Mal dauert länger)


func app_volume(args: Dictionary, delta: int) -> Dictionary:
	var a := args.duplicate()
	a["delta"] = clampi(delta, -100, 100)
	a["skip"] = [OS.get_process_id()]
	var r := await run("app-volume", a, 3.0 if _audio_warm else 8.0)
	if bool(r.get("ok", false)):
		_audio_warm = true
	return parse_app_volume(r)


static func parse_app_volume(r: Dictionary) -> Dictionary:
	var out := { "found": false, "level": -1, "mute": false, "error": true }
	var res: Variant = r.get("result")
	if not bool(r.get("ok", false)) or not (res is Dictionary) or str((res as Dictionary).get("json", "")) == "":
		return out
	var parsed: Variant = Fremd.json(str((res as Dictionary).get("json", "")))
	if not (parsed is Dictionary):
		return out
	var d: Dictionary = parsed
	out["error"] = d.has("timeout") or d.has("error")
	if bool(d.get("found", false)) and int(d.get("level", -1)) >= 0:
		out["found"] = true
		out["level"] = clampi(int(d.get("level", -1)), 0, 100)
		out["mute"] = bool(d.get("mute", false))
	return out


## Wie beschäftigt ein Weg ist: bereit, wartende Befehle, seit wann der älteste wartet (ms).
func _lane_info(l: Lane) -> Dictionary:
	return { "ready": l.ready and l.io != null, "n": l.inflight.size(), "ms": _busy_ms(l) }


func _busy_ms(l: Lane) -> int:
	var now := Time.get_ticks_msec()
	var oldest := now
	for t in l.inflight.values():
		oldest = mini(oldest, int(t))
	return now - oldest


## Weg für Befehle aus EITHER: der schnelle, außer er ist nicht bereit oder hängt an einem Befehl
## (über 1 s) und der Hauptweg ist frei oder weniger lange beschäftigt. "fast" oder "main".
static func pick_lane(fast: Dictionary, main: Dictionary) -> String:
	if not bool(fast.get("ready", false)):
		return "main"
	if int(fast.get("n", 0)) == 0 or int(fast.get("ms", 0)) < 1000:
		return "fast"
	if not bool(main.get("ready", false)):
		return "fast"
	if int(main.get("n", 0)) == 0 or int(main.get("ms", 0)) < int(fast.get("ms", 0)):
		return "main"
	return "fast"


## Zustand für „Übertragung prüfen“: läuft der Helfer, welche Wege sind bereit, wie beschäftigt.
func status() -> Dictionary:
	return { "available": available, "main": _lane_info(_main), "fast": _lane_info(_fast) }


## So lange darf der Hauptweg zum ersten Mal brauchen (Windows PowerShell übersetzt beim Start den
## C#-Teil; auf langsamen PCs mit Virenscanner dauert das), bevor der Uzai-Doktor „blockiert“ sagt.
const BLOCKED_MS := 45000


## Für den Uzai-Doktor: "" (nicht unter Windows), "ok", "startet" oder "blockiert" (startet nicht,
## nie bereit geworden oder dreimal hintereinander ausgefallen).
func state() -> String:
	if not Config.is_windows() and _test_shell() == "":
		return ""
	if available:
		return "ok"
	if _main.io == null or _main.restart_times.size() >= 3:
		return "blockiert"
	return "blockiert" if Time.get_ticks_msec() - _main.started_ms > BLOCKED_MS else "startet"


## „Beheben“ im Uzai-Doktor: den Hauptweg neu starten, auch nach drei Ausfällen (der Nutzer will es
## ausdrücklich). Ändert nichts an Windows.
func retry() -> void:
	if state() in ["", "ok"]:
		return
	_main.restart_times.clear()
	if _script == "":
		_script = _extract()
	if _main.io == null:
		hlog("main: Neustart auf Wunsch (Uzai-Doktor)")
		_start(_main)
	else:
		_restart(_main, "auf Wunsch neu gestartet (Uzai-Doktor)")


## Rein: Epics Einmal-Code für den Spielstart (-AUTH_PASSWORD=…) unkenntlich machen. Er geht nur
## als Liste an den Helfer und kommt in keiner Meldung vor; das hier ist die letzte Sicherung, falls
## eine Fehlerausgabe von PowerShell ihn doch einmal enthielte.
static func redact(text: String) -> String:
	return _AUTH_RE.sub(text, "$1…", true)

## Einmal übersetzt statt bei jeder Protokollzeile.
static var _AUTH_RE := RegEx.create_from_string("(?i)(-AUTH_PASSWORD=)[^\\s\"',}\\]]*")


## Protokoll des Helfers (logs/helper.log): Start, Bereitschaft, Fehlerausgabe von PowerShell
## (z. B. wenn der C#-Teil unter Windows PowerShell 5 nicht übersetzt), fehlgeschlagene Befehle.
## Vorher wurde der Fehlerkanal nur geleert – warum der Helfer nicht lief, stand nirgends.
func hlog(text: String) -> void:
	if not Config.is_windows() and _test_shell() == "":
		return
	Logdatei.zeile(Config.path("logs/helper.log"), redact(text), 300000)


## Länger dauernde Befehle in einem eigenen Prozess (blockiert Uzai nicht).
## ps: anderes PowerShell, z. B. die 32-Bit-Version für 32-Bit-Spiele.
## Mit Zeitgrenze (args.timeout + 20 s, mindestens 60 s): hängt der Prozess, wird er beendet,
## statt den Spielstart für immer festzuhalten.
func run_once(cmd: String, args: Dictionary = {}, ps := "") -> Dictionary:
	if not Config.is_windows():
		return { "ok": false, "error": "nur unter Windows" }
	var payload := Marshalls.utf8_to_base64(JSON.stringify({ "id": 1, "cmd": cmd, "args": args }))
	var info: Dictionary = OS.execute_with_pipe(ps if ps != "" else ps_exe(), _ps_args(PackedStringArray(["-Once", payload])), false)
	if info.is_empty():
		return { "ok": false, "error": "PowerShell startet nicht" }
	var io: FileAccess = info.get("stdio")
	var err_io: FileAccess = info.get("stderr")   # mitlesen, sonst blockiert ein voller Fehlerkanal
	var p := int(info.get("pid", 0))
	var limit_ms := int(maxf(60.0, float(args.get("timeout", 0)) + 20.0) * 1000.0)
	var t0 := Time.get_ticks_msec()
	var raw := PackedByteArray()
	while true:
		var chunk := io.get_buffer(65536)
		raw.append_array(chunk)
		if err_io:
			err_io.get_buffer(65536)
		if chunk.is_empty():
			if not OS.is_process_running(p):
				raw.append_array(io.get_buffer(65536))
				break
			if Time.get_ticks_msec() - t0 > limit_ms:
				OS.kill(p)
				return { "ok": false, "error": "Zeitüberschreitung", "timeout": true }
			await get_tree().process_frame
	var text := raw.get_string_from_utf8()
	for line in text.split("\n"):
		var msg: Variant = Fremd.json(line.strip_edges())
		if msg is Dictionary and msg.has("ok"):
			return antwort(msg)
	return { "ok": false, "error": "keine Antwort" }


# --- Nach dem Schließen im Hintergrund bereit ---------------------------------------------------
# Uzai beendet sich beim Schließen ganz (Fenster, Grafik, Dienste, beide Helfer: kein Speicher, keine
# Rechenzeit). Übrig bleibt nur ein winziger Wächter: dasselbe Skript mit -Watch, das nur einen
# kleinen C#-Teil übersetzt und die Controller abfragt. Guide-Taste → Uzai.exe startet neu, also im
# Vollbild mit der Startanimation wie sonst. Kein Autostart, keine Registry: Der Wächter endet mit
# der Windows-Sitzung, sobald Uzai wieder läuft, oder gar nicht erst gestartet („Uzai ganz beenden“).

const WOKEN := "--woken"         ## Uzai wurde vom Wächter gestartet (Guide-Taste)
const AFTER_CRASH := "--nach-absturz"   ## vom Helfer nach einem Absturz neu gestartet
var wake_started := false         ## Wächter läuft schon (beim Beenden nur einmal starten)
var _woken_focused := false


## Ist „Im Hintergrund bereit“ hier überhaupt möglich und eingeschaltet?
func wake_active() -> bool:
	return (Config.is_windows() or _test_shell() != "") and bool(Config.get_value("system.background_wake", true))


## Darf dieses Uzai beim Schließen den Wächter starten? Nur das echte: nicht in Tests, Proben und im
## Vorführmodus, nicht als zweites Uzai, das nur einen Auftrag weitergibt.
static func wake_allowed(enabled: bool, user_args: PackedStringArray, second: bool) -> bool:
	if not enabled or second:
		return false
	for a in user_args:
		if a == "--demo" or a == "--no-boot" or a.begins_with("--uzai-"):
			return false
	return true


## Auftrag für den Wächter. Uzai startet wie gewohnt (dieselben Engine-Argumente ohne --headless, keine
## eigenen wie --launch oder --windowed), nur mit --woken. pid_file: uzai.pid, das jedes Uzai beim
## Start neu schreibt – ändert es sich, lief Uzai auf anderem Weg an und der Wächter geht.
static func wake_payload(exe: String, engine_args: PackedStringArray, combo: bool, pid_file: String, parent: int) -> Dictionary:
	var args: Array = []
	for a in engine_args:
		if a != "--headless":
			args.append(a)
	args.append("--")
	args.append(WOKEN)
	var win := exe.replace("\\", "/")
	return { "exe": win.replace("/", "\\"), "dir": win.get_base_dir().replace("/", "\\"), "args": args, "combo": combo,
		"pid_file": pid_file.replace("/", "\\"), "parent": parent }


## Wächter nach einem Absturz (Punkt 133, Crash-Restart in uzai-helper.ps1): stürzt Uzai ab,
## startet der Hauptweg des Helfers es neu – dort, wo es war, mit --nach-absturz. Lief ein Spiel,
## wird er stattdessen zum Wächter für die Guide-Taste. Nicht in Tests und nicht als zweites Uzai.
## Einmal scharf gemacht (main.gd): gilt auch für jeden späteren Helfer-Prozess.
var _crash_watch_scharf := false


func arm_crash_watch() -> void:
	if not wake_allowed(true, OS.get_cmdline_user_args(), Remote.is_second):
		return
	_crash_watch_scharf = true
	if not available:
		return   # sobald der Helfer bereit ist, schickt ihn die Bereit-Meldung (auch nach jedem Neustart des Helfers)
	run("crash-watch", crash_job(OS.get_executable_path(), OS.get_cmdline_args(), OS.get_cmdline_user_args(), OS.get_process_id(),
		Config.path("laeuft.json"), ps_exe(), _script, Marshalls.utf8_to_base64(JSON.stringify(wake_payload(OS.get_executable_path(),
		OS.get_cmdline_args(), bool(Config.get_value("controller.guide_combo", true)), Config.path(Remote.PID_FILE), OS.get_process_id())))))


## Auftrag für den Neustart nach einem Absturz: dieselben Argumente ohne --headless und ohne die
## einmaligen (Verknüpfung, Neustart, Sicherer Modus, Guide-Taste), dazu --nach-absturz.
static func crash_job(exe: String, engine_args: PackedStringArray, user_args: PackedStringArray, pid: int, marker: String, ps: String, script: String,
		watch: String, windows := (OS.get_name() == "Windows")) -> Dictionary:
	var args: Array = Array(engine_args).filter(func(a: String) -> bool: return a != "--headless")
	args.append("--")
	for a in user_args:
		# Das Profil (--profil=…) bleibt, die Begrüßung nach einem Wechsel nicht.
		if not (a.begins_with("--launch=") or a.begins_with("--nach-") or a in ["--sicherer-modus", WOKEN, "--profilwechsel"]):
			args.append(a)
	args.append(AFTER_CRASH)
	var unix := exe.replace("\\", "/")
	var native := func(p: String) -> String: return p.replace("/", "\\") if windows else p
	return { "pid": pid, "marker": native.call(marker), "exe": native.call(unix), "dir": native.call(unix.get_base_dir()),
		"args": args, "ps": ps, "script": script, "watch": watch }


## Beim Schließen über Ausschalten → „Uzai schließen“: Wächter starten, wenn die Einstellung an ist
## (Alt+F4 und die Taskleiste beenden ganz, ohne Wächter). true, wenn er läuft. Er wartet selbst, bis dieses Uzai ganz weg ist.
func start_wake_watch() -> bool:
	if wake_started:
		return true
	if _script == "" or not wake_active() or not wake_allowed(true, OS.get_cmdline_user_args(), Remote.is_second):
		return false
	var job := wake_payload(OS.get_executable_path(), OS.get_cmdline_args(), bool(Config.get_value("controller.guide_combo", true)),
		Config.path(Remote.PID_FILE), OS.get_process_id())
	var payload := Marshalls.utf8_to_base64(JSON.stringify(job))
	var shell := _test_shell() if _test_shell() != "" else ps_exe()
	wake_started = OS.create_process(shell, _ps_args(PackedStringArray(["-Watch", payload])), false) > 0
	return wake_started


func _notification(what: int) -> void:
	# Alt+F4 or closing from the taskbar: quit completely, like „Ganz beenden“, with no watcher left in the
	# background, because Alt+F4 is expected to close the app for good. Uzai stays ready in the background only
	# via „Uzai schließen“ in the Guide; that path starts the watcher itself beforehand (main._quit_uzai).
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not wake_started:
		wake_started = true
	if what == NOTIFICATION_PREDELETE:
		# Leitung schließen statt die Helfer zu töten: Sie lesen dann das Ende ihrer Eingabe und räumen selbst auf
		# (ein angehaltenes Spiel läuft weiter, Stummschaltung und Raumton zurück, Steams Mitteilungen wieder an) und
		# enden. Getötet taten sie das nie – nach Alt+F4 mit offenem Guide blieb ein Emulator für immer angehalten.
		# Den Neustart nach einem Absturz lösen sie dabei nicht aus: Config löscht laeuft.json beim Beenden.
		for l in [_main, _fast]:
			l.io = null
			l.err = null
