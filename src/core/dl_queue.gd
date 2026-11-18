extends RefCounted
## Download-Zentrale (Punkt 107): Uzais eigene Warteschlange vor Steam und Epic, anstehende
## Steam-Updates und „nachts im Ruhemodus“. Steam lädt immer nur ein Spiel zur Zeit und hat eine
## eigene Warteschlange, die sich von außen nicht umsortieren lässt. Darum hält Uzai, was warten
## soll, selbst zurück und gibt Steam (bzw. Epic) erst das nächste, wenn das vorige fertig ist –
## so gilt die Reihenfolge, die du in Uzai einstellst.
##
## Nachts: Nur wenn der PC ohnehin an ist und Uzai im Ruhemodus wartet, innerhalb des
## eingestellten Zeitfensters. Uzai weckt den PC nie und ändert keine Energieeinstellung.
## Bandbreite: Die setzt nur Steam selbst (Einstellungen → Downloads); Uzai liest sie nur aus.
## Ohne Fenster testbar (tests/logic_dlzentrale.gd).

const P := preload("res://src/core/install_parse.gd")
const VDF := preload("res://src/library/vdf.gd")
const Storage := preload("res://src/core/storage.gd")

const KINDS := ["install", "update"]
const WHENS := ["jetzt", "nachts"]
const MAX := 50                  ## mehr Einträge nimmt die Warteschlange nicht

## Steam „läuft gerade“ (Laden, Vorbereiten, Auspacken, Prüfen).
const _RUNNING := P.ST_UPDATE_RUNNING | P.ST_DOWNLOADING | P.ST_PREALLOCATING | P.ST_STAGING | P.ST_COMMITTING | P.ST_VALIDATING | P.ST_ADDING_FILES


# --- Anstehende Updates (aus Steams appmanifest, nur lesen) ---------------------------------------

## Steht für dieses installierte Spiel ein Update an? {} = nein. Sonst { phase (wartet | laeuft |
## pausiert), total, got, remaining (Bytes, -1 unbekannt), result (Steams Fehlercode, 0 = keiner),
## scheduled (Unix-Zeit, zu der Steam es selbst plant, 0 = nicht geplant) }.
static func update_state(st: Dictionary) -> Dictionary:
	var flags := int(str(VDF.get_ci(st, "StateFlags", "0")))
	if (flags & P.ST_FULLY_INSTALLED) == 0 and (flags & _RUNNING) == 0:
		return {}
	if (flags & P.ST_UPDATE_REQUIRED) == 0:
		return {}
	var total := _num(VDF.get_ci(st, "BytesToDownload", "0"))
	var got := _num(VDF.get_ci(st, "BytesDownloaded", "0"))
	var phase := "wartet"
	if (flags & P.ST_UPDATE_PAUSED) != 0:
		phase = "pausiert"
	elif (flags & _RUNNING) != 0:
		phase = "laeuft"
	return { "phase": phase, "total": total, "got": got, "remaining": maxi(total - got, 0) if total > 0 else -1,
		"result": int(_num(VDF.get_ci(st, "UpdateResult", "0"))), "scheduled": int(_num(VDF.get_ci(st, "ScheduledAutoUpdate", "0"))) }


## Kurz für eine Zeile: „Update · 1,2 GB“, „Update läuft · 40 %“, „Update pausiert“.
static func update_text(u: Dictionary) -> String:
	var rest := int(u.get("remaining", -1))
	var total := int(u.get("total", 0))
	match str(u.get("phase", "")):
		"laeuft":
			if total > 0:
				return "Update läuft · %d %%" % int(100.0 * float(u.get("got", 0)) / float(total))
			return "Update läuft"
		"pausiert":
			return "Update pausiert in Steam"
	var t := "Update · %s" % P.gb(float(rest)) if rest > 0 else "Update steht an"
	if int(u.get("result", 0)) != 0:
		t += " · Steam meldet Fehler %d" % int(u.result)
	return t


# --- Warteschlange ---------------------------------------------------------------------------------

## Eintrag: { id, kind (install | update), when (jetzt | nachts), added (Unix-Zeit), accept
## (Platz, den du schon bestätigt hast: ok | knapp | voll), held (warum er gerade wartet, "" = nicht) }.
static func entry(id: String, kind: String, when: String, now: int, accept := "ok") -> Dictionary:
	return { "id": id, "kind": kind if kind in KINDS else "install", "when": when if when in WHENS else "jetzt",
		"added": now, "accept": accept if accept in ["ok", "knapp", "voll"] else "ok", "held": "" }


## Aus den Einstellungen gelesen: nur saubere Einträge, jede ID einmal, höchstens MAX.
static func sanitize(v: Variant) -> Array:
	var out: Array = []
	var seen := {}
	if not (v is Array):
		return out
	for e in v:
		if not (e is Dictionary):
			continue
		var id := str(e.get("id", ""))
		if id == "" or id.length() > 200 or seen.has(id) or not str(e.get("kind", "")) in KINDS:
			continue
		seen[id] = true
		var x := entry(id, str(e.kind), str(e.get("when", "jetzt")), int(e.get("added", 0)), str(e.get("accept", "ok")))
		out.append(x)
		if out.size() >= MAX:
			break
	return out


## Hinten anstellen. Steht das Spiel schon drin, gilt nur der neue Zeitpunkt (Platz bleibt).
static func add(queue: Array, e: Dictionary) -> Array:
	var out := queue.duplicate(true)
	for x in out:
		if str(x.id) == str(e.id):
			x["when"] = str(e.when)
			x["held"] = ""
			return out
	if out.size() < MAX:
		out.append(e.duplicate())
	return out


static func remove(queue: Array, id: String) -> Array:
	return queue.filter(func(x: Dictionary) -> bool: return str(x.id) != id)


static func index_of(queue: Array, id: String) -> int:
	for i in queue.size():
		if str(queue[i].id) == id:
			return i
	return -1


## Einen Platz nach oben (-1) oder unten (+1); am Rand bleibt alles, wie es ist.
static func move(queue: Array, id: String, delta: int) -> Array:
	var out := queue.duplicate(true)
	var i := index_of(out, id)
	var j := i + delta
	if i < 0 or j < 0 or j >= out.size():
		return out
	var tmp: Dictionary = out[i]
	out[i] = out[j]
	out[j] = tmp
	return out


## Liegt diese Stunde im Zeitfenster? Über Mitternacht geht es auch (23 bis 6). Gleiche Stunden:
## kein Fenster.
static func in_window(hour: int, from_h: int, to_h: int) -> bool:
	if from_h == to_h:
		return false
	if from_h < to_h:
		return hour >= from_h and hour < to_h
	return hour >= from_h or hour < to_h


## Darf dieser Eintrag jetzt anlaufen? ctx: { night (Fenster und Ruhemodus), playing (ID des
## laufenden Spiels) }. Das Spiel, das gerade läuft, bekommt nie ein Update.
static func may_start(e: Dictionary, ctx: Dictionary) -> bool:
	if str(e.get("when", "")) == "nachts" and not bool(ctx.get("night", false)):
		return false
	if str(e.get("id", "")) == str(ctx.get("playing", "")) and str(ctx.get("playing", "")) != "":
		return false
	return true


## Reihenfolge der Kandidaten, die jetzt anlaufen dürften: [Index, …]. Läuft schon etwas
## (ctx.busy), keiner – das nächste kommt erst, wenn das vorige fertig ist.
static func candidates(queue: Array, ctx: Dictionary) -> Array:
	var out: Array = []
	if bool(ctx.get("busy", false)):
		return out
	for i in queue.size():
		if may_start(queue[i], ctx):
			out.append(i)
	return out


## Platz vor dem Start (Bytes; -1 unbekannt): "" = darf los, sonst „voll“ bzw. „knapp“ – außer du
## hast genau das beim Einreihen schon bestätigt. Unbekannt hält nie auf.
static func space_hold(need: int, free: int, accept: String) -> String:
	var level := Storage.space_level(need, free)
	if level == "voll" and accept != "voll":
		return "voll"
	if level == "knapp" and not (accept in ["knapp", "voll"]):
		return "knapp"
	return ""


## Warum ein Eintrag wartet, als Zeile in der Liste.
static func wait_text(e: Dictionary, from_h: int, to_h: int, night_on: bool) -> String:
	match str(e.get("held", "")):
		"voll":
			return "Wartet: zu wenig Platz"
		"knapp":
			return "Wartet: wenig Platz – A zum Starten"
		"anmeldung":
			return "Wartet: Steam-Anmeldung in Uzai fehlt"
		"anwesend":
			return "Startet, sobald du in Uzai bist"
	if str(e.get("when", "")) == "nachts":
		if not night_on:
			return "Für die Nacht vorgemerkt · „Nachts laden“ ist aus"
		return "Heute Nacht · %s bis %s Uhr im Ruhemodus" % [hour_text(from_h), hour_text(to_h)]
	return "Wartet, bis der vorige Download fertig ist"


static func hour_text(h: int) -> String:
	return "%d" % h


# --- Bandbreite (Steam) ---------------------------------------------------------------------------

## Steams Grenze in kbit/s aus config.vdf (DownloadThrottleKbps): 0 = ohne Grenze, -1 = unbekannt.
## Nur dieser eine Wert wird gesucht; der Rest der Datei bleibt unbeachtet.
static func throttle_kbps(text: String) -> int:
	var rx := RegEx.create_from_string("(?i)\"DownloadThrottleKbps\"\\s+\"(\\d{1,9})\"")
	var m := rx.search(text)
	return int(m.get_string(1)) if m != null else -1


static func throttle_text(kbps: int) -> String:
	if kbps < 0:
		return "Unbekannt"
	if kbps == 0:
		return "Ohne Grenze"
	return "Höchstens %s" % P.speed_text(float(kbps) * 125.0)


# --- Nach dem Ruhemodus ---------------------------------------------------------------------------

## Eine Zeile für alles, was im Ruhemodus fertig wurde: „Elden Ring · Hades“ bzw. „Elden Ring,
## Hades und 2 weitere“ (kein freies „und“ zwischen Titeln – das bliebe in jeder Sprache stehen).
static func summary(titles: Array) -> String:
	if titles.is_empty():
		return ""
	if titles.size() <= 2:
		return " · ".join(PackedStringArray(titles))
	return "%s, %s und %d weitere" % [str(titles[0]), str(titles[1]), titles.size() - 2]


static func _num(v: Variant) -> int:
	var s := str(v)
	return int(s) if s.is_valid_int() else 0
