extends RefCounted
## Leistung des laufenden Spiels im Guide (Roadmap 5): Last des Prozessors, Arbeitsspeicher, Last
## und Speicher der Grafikkarte, Temperatur und das aktive Energieprofil von Windows – ruhig, ohne
## Zahlenflackern. Anders als perf.gd (Uzai misst sich selbst) geht es hier um den ganzen PC und
## das Spiel darin.
##
## Woher die Werte kommen (alles mit Benutzerrechten, nichts im Spiel, kein Treiber):
## - Prozessor und Arbeitsspeicher: Windows selbst (GetSystemTimes, GlobalMemoryStatusEx), das
##   Spiel über seine Prozesse.
## - Grafikkarte und Grafikspeicher: die Leistungsindikatoren von Windows („GPU Engine“, „GPU
##   Adapter Memory“, „GPU Process Memory“) – dieselben, die der Task-Manager zeigt. Die Größe
##   des Grafikspeichers aus DXGI.
## - Temperatur: nur NVIDIA über nvml.dll aus dem Treiber (offiziell, ohne Adminrechte). Für AMD,
##   Intel und den Prozessor bietet Windows ohne Adminrechte keinen offiziellen Weg – dann steht
##   ehrlich „Nicht verfügbar“ da.
## - Bilder je Sekunde fehlen mit Absicht: Windows gibt sie nur über ETW-Ereignisse heraus, und die
##   brauchen Adminrechte (oder die Gruppe „Leistungsprotokollbenutzer“); sonst ginge es nur über
##   einen Eingriff ins Spiel. Beides macht Uzai nicht.
##
## Der Helfer misst in einem eigenen Faden nur, solange Uzai nachfragt (Befehl „perf-live“ mit
## Haltedauer): Guide zu, Karte weg → nach wenigen Sekunden ruht er wieder. Im leichten Modus
## seltener. Rechnen und Texte ohne Fenster testbar (tests/logic_leistungsanzeige.gd).

const Lang := preload("res://src/core/lang.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Fremd := preload("res://src/core/fremd.gd")

const EVERY_S := 1.0             ## so oft, solange die Übersicht zu sehen ist
const EVERY_LIGHT_S := 2.5       ## im leichten Modus
const HOLD_K := 4.0              ## der Helfer misst noch so viele Abstände weiter, dann ruht er
const BACKOFF_S := 5.0           ## nach einer Zeitüberschreitung so lange nicht nachfragen
const GB := 1073741824.0
const NVIDIA := 0x10DE

## Bekannte Energieprofile von Windows: eigene Namen (übersetzbar), sonst der Name von Windows.
const PLANS := {
	"381b4222-f694-41f0-9685-ff5bb260df2e": "Ausbalanciert",
	"8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c": "Höchstleistung",
	"a1841308-3541-4fab-bc81-f71556f20b4a": "Energiesparmodus",
	"e9a42b02-d5df-448d-aa00-03f14749eb61": "Ultimative Leistung",
}

## Zuletzt gemessen (normalisiert), für Kachel und Ecke ohne eigene Abfrage.
static var last: Dictionary = {}
static var _busy := false
static var _pause_until := 0
static var _at := 0                ## wann zuletzt gefragt (ms)
static var _warm := false         ## der C#-Teil ist übersetzt (das erste Mal dauert es länger)
static var _pids: Array = []
static var _pids_for := ""        ## für welches Spiel _pids gelten (Kennung und Startzeit)
static var _pids_retry := 0
static var _demo_plan := ""


## Abstand zwischen zwei Abfragen in Sekunden.
static func every_s() -> float:
	return EVERY_LIGHT_S if Leicht.active else EVERY_S


## Eine frische Messung holen (oder {} ohne Helfer). Nie zwei Abfragen gleichzeitig, und Karte und
## Seitenleiste teilen sich eine je Abstand.
static func fetch() -> Dictionary:
	var now := Time.get_ticks_msec()
	if now - _at < int(every_s() * 800.0) and not last.is_empty():
		return last
	if Library.demo:
		_at = now
		last = normalize(demo_raw(now))
		return last
	if _busy or not Helper.available or now < _pause_until:
		return last
	_busy = true
	_at = now
	var pids := await _game_pids()
	var ms := int(every_s() * 1000.0)
	var r: Dictionary = await Helper.run("perf-live", { "pids": pids, "every": ms, "hold": int(ms * HOLD_K) }, 2.0 if _warm else 12.0)
	_busy = false
	if bool(r.get("timeout", false)):
		_pause_until = Time.get_ticks_msec() + int(BACKOFF_S * 1000.0)
		return last
	var raw := parse_reply(r)
	if raw.is_empty():
		return last
	_warm = true
	last = normalize(raw)
	return last


## Prozesse des Spiels einmal je Spiel (bei Steam und Epic sucht der Helfer im Spielordner).
static func _game_pids() -> Array:
	if not Launcher.in_game:
		return []
	# Startzeit statt Spielzeit: elapsed wächst, die Differenz zur Uhr bleibt (± 1 s).
	var key := "%s@%d" % [str(Launcher.current.get("id", "")), int(Time.get_unix_time_from_system()) - Launcher.elapsed()]
	# Noch nichts gefunden (Spiel startet noch): höchstens alle 10 s neu suchen.
	if _pids_for != "" and _same_game(_pids_for, key) and (not _pids.is_empty() or Time.get_ticks_msec() < _pids_retry):
		return _pids
	var found: Array = await Launcher.game_pids()
	_pids = found.filter(func(p: Variant) -> bool: return int(p) > 4).slice(0, 16).map(func(p: Variant) -> int: return int(p))
	_pids_for = key
	_pids_retry = Time.get_ticks_msec() + 10000
	return _pids


static func _same_game(a: String, b: String) -> bool:
	var pa := a.rsplit("@", true, 1)
	var pb := b.rsplit("@", true, 1)
	return pa.size() == 2 and pb.size() == 2 and pa[0] == pb[0] and absi(int(pa[1]) - int(pb[1])) <= 2


## Antwort des Helfers: { json } → Wörterbuch (leer, wenn nichts Brauchbares kam).
static func parse_reply(r: Dictionary) -> Dictionary:
	var res: Variant = r.get("result")
	if not bool(r.get("ok", false)) or not (res is Dictionary):
		return {}
	var js := str((res as Dictionary).get("json", ""))
	if js == "" or js.length() > 20000:
		return {}
	var d: Variant = Fremd.json_roh(js)
	return d if d is Dictionary else {}


# --- Rechnen (ohne Fenster, getestet) -----------------------------------------------------------

## Rohwerte des Helfers in feste Grenzen: Prozente 0..100, Bytes ≥ 0, unbekannt = -1.
## { warming, cpu, cores, ram_used, ram_total, gpu, gpu_name, vendor, vram_used, vram_total,
##   gpu_temp, game_cpu, game_ram, game_gpu, game_vram, gpu_counters }
static func normalize(raw: Dictionary) -> Dictionary:
	if bool(raw.get("warming", false)):
		return { "warming": true }
	if raw.has("error"):
		return { "error": true }
	var out := {}
	for k in ["cpu", "gpu", "game_cpu", "game_gpu"]:
		out[k] = _pct(raw.get(k))
	for k in ["ram_used", "ram_total", "vram_used", "vram_total", "game_ram", "game_vram"]:
		out[k] = _bytes(raw.get(k))
	# Belegt kann nie mehr sein als vorhanden (Windows zählt geteilten Speicher manchmal mit).
	if float(out.ram_total) > 0.0:
		out.ram_used = minf(float(out.ram_used), float(out.ram_total))
	if float(out.vram_total) > 0.0 and float(out.vram_used) > float(out.vram_total):
		out.vram_used = float(out.vram_total)
	var t := _num(raw.get("gpu_temp"))
	out["gpu_temp"] = t if t > 0.0 and t < 130.0 else -1.0
	out["cores"] = clampi(int(_num(raw.get("cores"))), 0, 1024)
	out["vendor"] = clampi(int(_num(raw.get("vendor"))), 0, 0xFFFF)
	out["gpu_name"] = str(raw.get("gpu_name", "")).strip_edges().left(80)
	out["gpu_counters"] = bool(raw.get("gpu_counters", false))
	return out


static func _num(v: Variant) -> float:
	if v is int or v is float:
		var f := float(v)
		return f if is_finite(f) else -1.0
	return -1.0


static func _pct(v: Variant) -> float:
	var f := _num(v)
	return -1.0 if f < 0.0 else clampf(f, 0.0, 100.0)


static func _bytes(v: Variant) -> float:
	var f := _num(v)
	return -1.0 if f < 0.0 else f


static func pct_text(p: float) -> String:
	return "–" if p < 0.0 else "%d %%" % roundi(p)


## „6,1 GB“ (unter 10 GB mit einer Stelle), „512 MB“ unter 1 GB.
static func gb_text(bytes: float) -> String:
	if bytes < 0.0:
		return "–"
	var g := bytes / GB
	if g < 1.0:
		return "%d MB" % roundi(bytes / 1048576.0)
	return Lang.dec("%.1f GB" % g) if g < 10.0 else "%d GB" % roundi(g)


## „6,1 / 8 GB“: belegt von vorhanden (die Größe ohne Nachkommastelle, wenn glatt).
static func used_of(used: float, total: float) -> String:
	if used < 0.0:
		return "–"
	if total <= 0.0:
		return gb_text(used)
	var tg := total / GB
	var tt := ("%d" % roundi(tg)) if absf(tg - roundf(tg)) < 0.05 or tg >= 10.0 else Lang.dec("%.1f" % tg)
	var ug := used / GB
	var ut := Lang.dec("%.1f" % ug) if ug < 10.0 else "%d" % roundi(ug)
	return "%s / %s GB" % [ut, tt]


static func temp_text(t: float) -> String:
	return "–" if t <= 0.0 else "%d °C" % roundi(t)


## Zeilen der Übersicht: [Kennung, Titel, Symbol, Wert, Zeile darunter, Anteil 0..1 oder -1].
## Unbekanntes steht ehrlich da („Nicht verfügbar“ mit Grund), statt geschätzt zu werden.
static func rows(s: Dictionary) -> Array:
	if s.is_empty() or bool(s.get("warming", false)) or bool(s.get("error", false)):
		var wait := "Wird gemessen …" if not bool(s.get("error", false)) else "Gerade nicht messbar"
		return [["cpu", "Prozessor", "chip", "–", wait, -1.0], ["gpu", "Grafikkarte", "monitor", "–", wait, -1.0],
			["ram", "Arbeitsspeicher", "memory", "–", wait, -1.0], ["vram", "Grafikspeicher", "memory", "–", wait, -1.0],
			["temp", "Temperatur", "thermo", "–", wait, -1.0]]
	var out: Array = []
	var cpu := float(s.get("cpu", -1.0))
	var gc := float(s.get("game_cpu", -1.0))
	var cores := int(s.get("cores", 0))
	var cpu_sub := ("Spiel %s" % pct_text(gc)) if gc >= 0.0 else ""
	if cores > 0:
		cpu_sub = _join([cpu_sub, Lang.count(cores, "Kern", "Kerne")])
	out.append(["cpu", "Prozessor", "chip", pct_text(cpu), cpu_sub, cpu / 100.0 if cpu >= 0.0 else -1.0])
	var gpu := float(s.get("gpu", -1.0))
	var gg := float(s.get("game_gpu", -1.0))
	var name := str(s.get("gpu_name", ""))
	if gpu < 0.0:
		var why := "Windows meldet keine Werte (ältere Treiber)" if not bool(s.get("gpu_counters", false)) else "Nicht verfügbar"
		out.append(["gpu", "Grafikkarte", "monitor", "–", why, -1.0])
	else:
		out.append(["gpu", "Grafikkarte", "monitor", pct_text(gpu), _join([("Spiel %s" % pct_text(gg)) if gg >= 0.0 else "", name]), gpu / 100.0])
	var ru := float(s.get("ram_used", -1.0))
	var rt := float(s.get("ram_total", -1.0))
	var gr := float(s.get("game_ram", -1.0))
	out.append(["ram", "Arbeitsspeicher", "memory", used_of(ru, rt), ("Spiel %s" % gb_text(gr)) if gr >= 0.0 else "",
		ru / rt if ru >= 0.0 and rt > 0.0 else -1.0])
	var vu := float(s.get("vram_used", -1.0))
	var vt := float(s.get("vram_total", -1.0))
	var gv := float(s.get("game_vram", -1.0))
	if vu < 0.0:
		out.append(["vram", "Grafikspeicher", "memory", "–", "Nicht verfügbar", -1.0])
	else:
		out.append(["vram", "Grafikspeicher", "memory", used_of(vu, vt), ("Spiel %s" % gb_text(gv)) if gv >= 0.0 else "",
			vu / vt if vt > 0.0 else -1.0])
	var t := float(s.get("gpu_temp", -1.0))
	if t > 0.0:
		# 0 °C ist kein Ende der Skala: der Balken zeigt den Weg bis 90 °C (dort drosseln die meisten).
		out.append(["temp", "Temperatur", "thermo", temp_text(t), "Grafikkarte", clampf(t / 90.0, 0.0, 1.0)])
	else:
		out.append(["temp", "Temperatur", "thermo", "Nicht verfügbar", temp_why(int(s.get("vendor", 0))), -1.0])
	return out


## Warum keine Temperatur da ist – ehrlich und kurz.
static func temp_why(vendor: int) -> String:
	if vendor == NVIDIA:
		return "Der NVIDIA-Treiber gibt sie gerade nicht heraus"
	return "Ohne Adminrechte nur bei NVIDIA-Grafikkarten lesbar"


## Leiste im Guide (Reiter Spiel): [Beschriftung, Wert, Anteil 0..1 oder -1] – Prozessor,
## Grafikkarte, Arbeits- und Grafikspeicher, Temperatur (nur wenn bekannt). Gleich viele Teile,
## solange sich die Ausstattung nicht ändert: Werte tauschen, nichts springt.
static func strip_parts(s: Dictionary) -> Array:
	if s.is_empty() or bool(s.get("warming", false)) or bool(s.get("error", false)):
		return [["CPU", "–", -1.0], ["GPU", "–", -1.0], ["RAM", "–", -1.0], ["VRAM", "–", -1.0]]
	var cpu := float(s.get("cpu", -1.0))
	var gpu := float(s.get("gpu", -1.0))
	var ru := float(s.get("ram_used", -1.0))
	var rt := float(s.get("ram_total", -1.0))
	var vu := float(s.get("vram_used", -1.0))
	var vt := float(s.get("vram_total", -1.0))
	var out: Array = [["CPU", pct_text(cpu), cpu / 100.0 if cpu >= 0.0 else -1.0], ["GPU", pct_text(gpu), gpu / 100.0 if gpu >= 0.0 else -1.0],
		["RAM", used_of(ru, rt), ru / rt if ru >= 0.0 and rt > 0.0 else -1.0], ["VRAM", used_of(vu, vt), vu / vt if vu >= 0.0 and vt > 0.0 else -1.0]]
	var t := float(s.get("gpu_temp", -1.0))
	if t > 0.0:
		out.append(["GPU", temp_text(t), clampf(t / 90.0, 0.0, 1.0)])
	return out


## Kleine Anzeige in der Ecke über dem Spiel: „CPU 34 %   GPU 87 %   71 °C   6,1 GB“ als Teile
## [Beschriftung, Wert] (Beschriftung leise, Wert hell).
static func corner_parts(s: Dictionary) -> Array:
	if s.is_empty() or bool(s.get("warming", false)) or bool(s.get("error", false)):
		return [["", "…"]]
	var out: Array = [["CPU", pct_text(float(s.get("cpu", -1.0)))]]
	var gpu := float(s.get("gpu", -1.0))
	if gpu >= 0.0:
		out.append(["GPU", pct_text(gpu)])
	var t := float(s.get("gpu_temp", -1.0))
	if t > 0.0:
		out.append(["", temp_text(t)])
	var vu := float(s.get("vram_used", -1.0))
	if vu >= 0.0:
		out.append(["VRAM", gb_text(vu)])
	else:
		out.append(["RAM", gb_text(float(s.get("ram_used", -1.0)))])
	return out


## Dieselbe Anzeige im Zimmer (src/room/leistung.gd): Uzai misst sich dort selbst – Bilder je Sekunde,
## Zeit der Grafikkarte und des Prozessors je Bild: „120 Bilder/s   GPU 3,1 ms   CPU 2,4 ms“.
## Unbekannt (noch nicht gemessen): „–“.
static func zimmer_parts(fps: float, gpu_ms: float, cpu_ms: float) -> Array:
	var ms := func(v: float) -> String: return "–" if v <= 0.0 else Lang.dec("%.1f ms" % v)
	return [["", TranslationServer.translate("%d Bilder/s") % roundi(fps) if fps > 0.0 else "–"], ["GPU", ms.call(gpu_ms)], ["CPU", ms.call(cpu_ms)]]


static func _join(parts: Array) -> String:
	return "  ·  ".join(PackedStringArray(parts.filter(func(x): return str(x) != "")))


# --- Energieprofil ------------------------------------------------------------------------------

## Name eines Energieprofils: bekannte mit eigenem (übersetzbarem) Namen, sonst der von Windows.
## { text, own } – own = true: Name von Windows oder vom Nutzer, nie übersetzen.
static func plan_name(id: String, win_name: String) -> Dictionary:
	var k := id.to_lower()
	if PLANS.has(k):
		return { "text": str(PLANS[k]), "own": false }
	var n := win_name.strip_edges().left(60)
	return { "text": n if n != "" else "Eigenes Profil", "own": n != "" }


## Antwort von „power-plans“: { ok, active, can_set, plans: [{ id, name }] } streng geprüft.
static func parse_plans(raw: Dictionary) -> Dictionary:
	var out := { "ok": false, "active": "", "can_set": false, "plans": [] }
	if not bool(raw.get("ok", false)):
		return out
	var re := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	var seen := {}
	for p in (raw.get("plans", []) if raw.get("plans") is Array else []):
		if not (p is Dictionary):
			continue
		var id := str(p.get("id", "")).to_lower()
		if re.search(id) == null or seen.has(id) or (out.plans as Array).size() >= 16:
			continue
		seen[id] = true
		(out.plans as Array).append({ "id": id, "name": str(p.get("name", "")).strip_edges().left(60) })
	var act := str(raw.get("active", "")).to_lower()
	out.active = act if seen.has(act) else ""
	out.can_set = bool(raw.get("can_set", false)) and (out.plans as Array).size() > 1
	out.ok = true
	return out


## Was Uzai sich zum Zurückstellen merkt, nachdem im Guide umgeschaltet wurde: das Profil von
## vorher – einmal, beim ersten Umschalten. Wer zurück aufs Ausgangsprofil wechselt, braucht
## nichts mehr zurückzustellen ("").
static func after_switch(stored: String, before: String, chosen: String) -> String:
	if stored == "":
		return before if before != "" and chosen != before else ""
	return "" if chosen == stored else stored


## Energieprofile von Windows lesen: { ok, active, can_set, plans }.
static func load_plans() -> Dictionary:
	if Library.demo:
		var d := demo_plans()
		d.active = _demo_plan if _demo_plan != "" else str(d.active)
		return parse_plans(d)
	if not Helper.available:
		return parse_plans({})
	return parse_plans(parse_reply(await Helper.run("power-plans", {}, 10.0)))


## Ein Energieprofil einschalten (nur eins aus der Liste von Windows). true, wenn es geklappt hat.
static func set_plan(id: String) -> bool:
	if not RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").search(id):
		return false
	if Library.demo:
		_demo_plan = id
		return true
	if not Helper.available:
		return false
	return bool(parse_reply(await Helper.run("power-plan-set", { "id": id }, 10.0)).get("ok", false))


## Im Guide gewählt: einschalten und sich das Profil von vorher merken (für nach dem Spiel).
static func switch_plan(before: String, id: String) -> bool:
	if not await set_plan(id):
		return false
	Config.set_value("system.power_restore", after_switch(str(Config.get_value("system.power_restore", "")), before, id))
	return true


## Nach dem Spiel (und beim Start nach einem Absturz): das gemerkte Profil zurückstellen – einmal;
## klappt es nicht (Profil gelöscht, Windows verbietet es), bleibt es dabei.
static func restore_plan() -> void:
	var id := str(Config.get_value("system.power_restore", ""))
	if id == "":
		return
	Config.set_value("system.power_restore", "")
	var ok := await set_plan(id)
	Media.log_line("leistung", "Energieprofil zurückgestellt: %s" % ("ja" if ok else "nein"))
	if ok:
		Toasts.show_toast("Energieprofil zurückgestellt", "Wie vor dem Spiel", "bolt", { "ms": 3000, "quiet": true })


# --- Demo ---------------------------------------------------------------------------------------

## Ruhig schwankende Beispielwerte für die Demo (und die Bildschirm-Probe).
static func demo_raw(ms: int) -> Dictionary:
	var t := ms / 1000.0
	return {
		"cpu": 31.0 + 6.0 * sin(t * 0.7), "cores": 16, "ram_used": 11.4 * GB + 0.2 * GB * sin(t * 0.3), "ram_total": 32.0 * GB,
		"gpu": 86.0 + 5.0 * sin(t * 1.1), "gpu_name": "NVIDIA GeForce RTX 4070", "vendor": NVIDIA, "gpu_counters": true,
		"vram_used": 7.3 * GB, "vram_total": 12.0 * GB, "gpu_temp": 68.0 + 2.0 * sin(t * 0.2),
		"game_cpu": 22.0 + 4.0 * sin(t * 0.7), "game_ram": 6.2 * GB, "game_gpu": 83.0 + 5.0 * sin(t * 1.1), "game_vram": 6.6 * GB,
	}


static func demo_plans() -> Dictionary:
	return { "ok": true, "active": "381b4222-f694-41f0-9685-ff5bb260df2e", "can_set": true, "plans": [
		{ "id": "381b4222-f694-41f0-9685-ff5bb260df2e", "name": "Balanced" },
		{ "id": "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", "name": "High performance" },
		{ "id": "a1841308-3541-4fab-bc81-f71556f20b4a", "name": "Power saver" }] }
