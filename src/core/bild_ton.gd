extends RefCounted
## „Bild & Ton“ (Roadmap 4/16) ohne Oberfläche: Tonausgabe, Auflösung, Bildwiederholrate und HDR
## des Bildschirms, auf dem Uzai liegt – über dieselben Helfer-Befehle wie die Spiel-Profile
## (audio-list/-set, display-modes/-set/-reset/-hdr). Die Seitenleiste dazu:
## src/ui/layers/bild_ton_sheet.gd (Guide → System, auch im Spiel; Einstellungen → System → Windows).
##
## Auflösung und Hz gelten erst vorübergehend (nichts in Windows gespeichert). Wer nicht innerhalb
## von KEEP_S Sekunden „Behalten“ wählt, bekommt den alten Modus zurück – wie bei Windows, falls der
## Fernseher mit dem neuen Modus schwarz bleibt. Erst „Behalten“ schreibt ihn in Windows (display-set
## mit keep). Während der Rückfrage steht das Gerät in bildton/zurueck.json: Stürzt Uzai genau dann
## ab, stellt der nächste Start den gespeicherten Modus von Windows wieder her.
## Nachtlicht fehlt bewusst: Windows hat dafür keine offizielle Schnittstelle.

const GameProfile := preload("res://src/core/game_profile.gd")
const WinEinst := preload("res://src/core/win_einst.gd")

const KEEP_S := 15
const PENDING := "bildton/zurueck.json"
const DEVICES_MAX := 16
## Vorführung ohne Windows: ein Fernseher mit HDR und drei Tonausgaben.
const DEMO_MODES := [[3840, 2160, 120], [3840, 2160, 60], [2560, 1440, 120], [2560, 1440, 60], [1920, 1080, 120],
	[1920, 1080, 60], [1920, 1080, 50], [1280, 720, 60]]
const DEMO_AUDIO := [
	{ "id": "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a001}", "name": "LG TV (NVIDIA High Definition Audio)", "ff": 9, "default": true },
	{ "id": "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a002}", "name": "Kopfhörer (Xbox Wireless Headset)", "ff": 3, "default": false },
	{ "id": "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a003}", "name": "Lautsprecher (Realtek(R) Audio)", "ff": 1, "default": false },
]

static var _audio_id := RegEx.create_from_string("^\\{[0-9.]{1,40}\\}\\.\\{[0-9a-fA-F-]{36}\\}\\z")

## Laufende Rückfrage: { device, before: { w, h, hz }, now: { w, h, hz }, modes, t0, gen } oder {}.
## Liegt hier statt im Dialog: Wird der Dialog bei einem Neuaufbau der Oberfläche entfernt (eine neue
## Auflösung kann das auslösen), stellt die Frist trotzdem zurück.
static var ask := {}
static var _gen := 0
## Vorführung ohne Windows: Stand des erfundenen Fernsehers und der Tonausgabe.
static var demo_mode: Array = [3840, 2160, 60]
static var demo_hdr := "moeglich"
static var demo_audio := ""


# --- Ton -------------------------------------------------------------------------------------

## Art einer Tonausgabe aus der Bauform, die Windows meldet (PKEY_AudioEndpoint_FormFactor), sonst
## nach dem Namen: tv, kopfhoerer, lautsprecher oder anders.
static func audio_kind(ff: int, name: String) -> String:
	match ff:
		9: return "tv"
		3, 5: return "kopfhoerer"
		1: return "lautsprecher"
	var n := name.to_lower()
	for w in ["kopfhörer", "headphone", "headset", "earbuds"]:
		if n.contains(w):
			return "kopfhoerer"
	for w in ["hdmi", "displayport", " tv", "tv ", "fernseher", "monitor"]:
		if n.contains(w):
			return "tv"
	for w in ["lautsprecher", "speaker"]:
		if n.contains(w):
			return "lautsprecher"
	return "anders"


static func kind_icon(kind: String) -> String:
	return { "tv": "tv", "kopfhoerer": "headset" }.get(kind, "speaker")


static func kind_text(kind: String) -> String:
	return { "tv": "Fernseher oder Bildschirm", "kopfhoerer": "Kopfhörer", "lautsprecher": "Lautsprecher" }.get(kind, "Tonausgabe")


## Antwort auf „audio-list“ → { devices: [{ id, name, kind }], current } (current "" = unbekannt).
## Kennungen wie beim Setzen geprüft, Namen bereinigt; höchstens DEVICES_MAX.
static func parse_audio(r: Dictionary) -> Dictionary:
	var out := { "devices": [], "current": "" }
	var res: Variant = r.get("result")
	if not bool(r.get("ok", false)) or not (res is Dictionary):
		return out
	var list: Variant = (res as Dictionary).get("devices", [])
	if not (list is Array):
		return out
	var seen := {}
	for d in list:
		if not (d is Dictionary) or (out.devices as Array).size() >= DEVICES_MAX:
			continue
		var id := str((d as Dictionary).get("id", ""))
		if _audio_id.search(id) == null or seen.has(id):
			continue
		seen[id] = true
		var nm := WinEinst.clean_text(d.get("name", ""), TranslationServer.translate("Tonausgabe"))
		(out.devices as Array).append({ "id": id, "name": nm, "kind": audio_kind(int(d.get("ff", -1)), nm) })
		if bool(d.get("default", false)):
			out.current = id
	return out


# --- Bild ------------------------------------------------------------------------------------

## Auflösungen aus den Modi (parse_modes), ohne doppelte, die größte zuerst.
static func resolutions(modes: Array) -> Array:
	var out: Array = []
	var seen := {}
	for m in modes:
		var k := "%dx%d" % [int(m.w), int(m.h)]
		if seen.has(k):
			continue
		seen[k] = true
		out.append({ "w": int(m.w), "h": int(m.h) })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.w) * int(a.h) > int(b.w) * int(b.h) or (int(a.w) * int(a.h) == int(b.w) * int(b.h) and int(a.w) > int(b.w)))
	return out


## Bildwiederholraten, die der Bildschirm in dieser Auflösung anbietet, die höchste zuerst.
static func rates(modes: Array, w: int, h: int) -> Array:
	var out: Array = []
	for m in modes:
		if int(m.w) == w and int(m.h) == h and not out.has(int(m.hz)):
			out.append(int(m.hz))
	out.sort()
	out.reverse()
	return out


## Für eine neue Auflösung: dieselbe Rate, wenn es sie gibt, sonst die nächstkleinere, sonst die
## kleinste – nie ungefragt höher (manche Fernseher bleiben bei zu viel Hz schwarz). 0 = keine.
static func pick_rate(modes: Array, w: int, h: int, want: int) -> int:
	var rs := rates(modes, w, h)
	if rs.is_empty():
		return 0
	if rs.has(want):
		return want
	for r in rs:
		if int(r) < want:
			return int(r)
	return int(rs[rs.size() - 1])


static func res_text(w: int, h: int) -> String:
	return "%d × %d" % [w, h]


static func rate_text(hz: int) -> String:
	return "%d Hz" % hz


## Auftrag für „display-set“, {} wenn der Modus nicht in der Liste des Bildschirms steht.
static func set_args(info: Dictionary, w: int, h: int, hz: int, keep := false) -> Dictionary:
	if not GameProfile.valid_device(info.get("device", "")):
		return {}
	var found := false
	for m in info.get("modes", []):
		if int(m.w) == w and int(m.h) == h and int(m.hz) == hz:
			found = true
	if not found:
		return {}
	var a := { "device": str(info.device), "w": w, "h": h, "hz": hz }
	if keep:
		a["keep"] = 1
	return a


static func same_mode(info: Dictionary, w: int, h: int, hz: int) -> bool:
	return int(info.get("w", 0)) == w and int(info.get("h", 0)) == h and int(info.get("hz", 0)) == hz


## Demo: die Antwort, die „display-modes“ auf diesem Fernseher gäbe.
static func demo_info(cur: Array = [3840, 2160, 60], hdr := "moeglich") -> Dictionary:
	var ms: Array = DEMO_MODES.map(func(m: Array) -> Dictionary: return { "w": m[0], "h": m[1], "hz": m[2] })
	return { "device": "\\\\.\\DISPLAY1", "w": int(cur[0]), "h": int(cur[1]), "hz": int(cur[2]), "hdr": hdr, "modes": ms }


# --- Rückfrage „Behalten?“ -------------------------------------------------------------------

## Modus vorübergehend setzen und die Frist starten. { ok, error } – error "mode" (nicht in der Liste),
## sonst die Antwort von Windows. on_end(kept, timeout) ruft die Frist bzw. answer() einmal auf.
static func change_mode(info: Dictionary, w: int, h: int, hz: int, on_end := Callable()) -> Dictionary:
	var a := set_args(info, w, h, hz)
	if a.is_empty() or same_mode(info, w, h, hz):
		return { "ok": false, "error": "mode" }
	if not ask.is_empty():
		await answer(false)
	if _demo():
		demo_mode = [w, h, hz]
	else:
		write_pending(str(info.device))
		var r := GameProfile.reply(await Helper.run("display-set", a, 12.0))
		if not bool(r.get("ok", false)):
			clear_pending()
			return { "ok": false, "error": str(r.get("error", "windows")) }
	_gen += 1
	var g := _gen
	ask = { "device": str(info.device), "before": { "w": int(info.w), "h": int(info.h), "hz": int(info.hz) },
		"now": { "w": w, "h": h, "hz": hz }, "modes": info.get("modes", []), "t0": Time.get_ticks_msec(), "gen": g, "on_end": on_end }
	var tree := Engine.get_main_loop() as SceneTree
	tree.create_timer(KEEP_S + 0.25).timeout.connect(func() -> void:
		if int(ask.get("gen", -1)) == g:
			answer(false, true))
	return { "ok": true }


## Antwort auf „Behalten?“: keep schreibt den Modus in Windows, sonst geht der alte zurück
## (erst vorübergehend wie vorher, klappt das nicht, der gespeicherte Modus von Windows).
## Gibt "" zurück oder einen Satz, was nicht ging.
static func answer(keep: bool, timeout := false) -> String:
	if ask.is_empty():
		return ""
	var q := ask
	ask = {}
	var info := { "device": q.device, "modes": q.modes }
	var msg := ""
	if _demo():
		if not keep:
			demo_mode = [int(q.before.w), int(q.before.h), int(q.before.hz)]
	elif keep:
		var r := GameProfile.reply(await Helper.run("display-set", set_args(info, int(q.now.w), int(q.now.h), int(q.now.hz), true), 12.0))
		if not bool(r.get("ok", false)):
			msg = TranslationServer.translate(
					"Windows hat die Auflösung nur bis zum nächsten Neustart übernommen. Für immer: in Windows unter Einstellungen → System → Anzeige.")
	else:
		var back := set_args(info, int(q.before.w), int(q.before.h), int(q.before.hz))
		var r2 := GameProfile.reply(await Helper.run("display-set", back, 12.0)) if not back.is_empty() else {}
		if not bool(r2.get("ok", false)):
			await Helper.run("display-reset", { "device": str(q.device) }, 12.0)
	if not _demo():
		clear_pending()
	var cb: Callable = q.get("on_end", Callable())
	if cb.is_valid():
		cb.call(keep, timeout)
	return msg


static func asking() -> bool:
	return not ask.is_empty()


static func ask_left() -> int:
	return left_s(int(ask.get("t0", 0)), Time.get_ticks_msec()) if not ask.is_empty() else 0


static func _demo() -> bool:
	return Library.demo and not Config.is_windows()


## Noch so viele ganze Sekunden bis zum Zurückstellen (aufgerundet, nie unter 0).
static func left_s(start_ms: int, now_ms: int, total := KEEP_S) -> int:
	return clampi(ceili((total * 1000 - (now_ms - start_ms)) / 1000.0), 0, total)


static func expired(start_ms: int, now_ms: int, total := KEEP_S) -> bool:
	return now_ms - start_ms >= total * 1000


static func pending_path() -> String:
	return Config.path(PENDING)


static func write_pending(dev: String) -> void:
	if not GameProfile.valid_device(dev):
		return
	var p := pending_path()
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({ "display": dev }))
		f.close()


static func clear_pending() -> void:
	if FileAccess.file_exists(pending_path()):
		DirAccess.remove_absolute(pending_path())


## Gemerktes Gerät aus der Datei, streng geprüft; "" = nichts zu tun.
static func read_pending(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 1024:
		return ""
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK or not (j.data is Dictionary):
		return ""
	var dev := str((j.data as Dictionary).get("display", ""))
	return dev if GameProfile.valid_device(dev) else ""


## Beim Start von Uzai (launcher.gd): lief beim letzten Mal eine Rückfrage, als Uzai endete, den
## gespeicherten Modus von Windows zurückholen.
static func restore_pending() -> void:
	var dev := read_pending(pending_path())
	if dev == "":
		clear_pending()
		return
	if not Config.is_windows():
		clear_pending()
		return
	if not Helper.available:
		await Helper.helper_ready
	await Helper.run("display-reset", { "device": dev }, 12.0)
	clear_pending()
