extends RefCounted
## Spieler & Controller: welcher Controller Spieler 1–4 ist. Gilt für Uzai und – über
## src/core/spieler_emus.gd – für die Emulatoren (vor jedem Start eingerichtet).
##
## Ein Controller heißt hier nach seiner SDL-GUID (Godot: Input.get_joy_guid) und der wievielte
## gleicher Bauart er ist („<guid>#0“, „<guid>#1“). Zwei gleiche Xbox-Controller haben dieselbe GUID
## – dann zählt die Reihenfolge, in der Windows sie meldet (wie bei yuzu/Eden „port“). Ohne GUID
## (Vorführung, nur vom Helfer gesehen) gilt der Schlüssel aus Pads („k:x0“).
##
## Regeln:
## - Automatik: ein neuer Controller kommt auf den nächsten freien Platz.
## - Selbst zugeordnet gewinnt und wird je Controller gemerkt (Config „spieler.gemerkt“:
##   Kennung → Platz 1–4; 0 = „selbst entfernt“, die Automatik lässt ihn dann in Ruhe).
## - Ist ein Controller weg, wird sein Platz frei; kommt er wieder, bekommt er seinen gemerkten Platz
##   zurück und verdrängt dabei nur einen, der automatisch dort saß.

const SLOTS := 4
const KEY_SLOTS := "spieler.plaetze"     ## [Kennung oder "", …] für Spieler 1–4
const KEY_MEM := "spieler.gemerkt"       ## Kennung → Platz (0 = selbst entfernt)
const KEY_AUTO := "spieler.auto"         ## neue Controller füllen den nächsten freien Platz
const KEY_EMUS := "spieler.emulatoren"   ## „Immer nach Uzais Zuordnung (mehrere Spieler)“ (Standard aus)
const KEY_FEHLEND := "spieler.emu_fehlend" ## „Fehlende Belegung automatisch“ im Emulator (Standard an)
const MEM_MAX := 32                      ## so viele Controller merkt sich Uzai höchstens


# --- Kennungen ---------------------------------------------------------------------------------

## Nur 32 Hex-Zeichen (SDL-GUID); alles andere gilt als „keine GUID“.
static func clean_guid(v: Variant) -> String:
	var s := str(v if v != null else "").strip_edges().to_lower()
	if s.length() != 32:
		return ""
	for ch in s:
		if not ch in "0123456789abcdef":
			return ""
	return s


## Kennungen für eine Pads-Liste (gleiche Reihenfolge). Gleiche GUIDs zählen nach Godot-Gerät.
## Rückgabe: [{ id, guid, port }] – port = der wievielte Controller dieser Bauart (ab 0).
static func ids_for(pads: Array) -> Array:
	var order: Array = []
	for i in pads.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return int(pads[a].get("device", -1)) < int(pads[b].get("device", -1)))
	var seen := {}
	var out: Array = []
	out.resize(pads.size())
	for i in order:
		var p: Dictionary = pads[i]
		var g := clean_guid(p.get("guid", ""))
		if g == "":
			out[i] = { "id": "k:" + str(p.get("key", i)), "guid": "", "port": 0 }
			continue
		var n := int(seen.get(g, 0))
		seen[g] = n + 1
		out[i] = { "id": "%s#%d" % [g, n], "guid": g, "port": n }
	return out


static func norm_slots(v: Variant) -> Array:
	var out: Array = []
	for i in SLOTS:
		out.append(str(v[i]) if v is Array and i < (v as Array).size() and v[i] is String else "")
	return out


static func norm_mem(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		if k is String and (k as String).length() <= 48 and (v[k] is int or v[k] is float):
			var s := int(v[k])
			if s >= 0 and s <= SLOTS:
				out[k] = s
	return out


# --- Zuordnung (rein, getestet in tests/logic_spieler.gd) ----------------------------------------

## Neuer Stand nach einer Änderung der verbundenen Controller (connected: Kennungen in der
## Reihenfolge, in der sie kamen). Gemerkte Plätze zuerst, dann – mit Automatik – der Rest.
static func auto_fill(slots: Array, connected: Array, mem: Dictionary, auto := true) -> Array:
	var out := norm_slots(slots)
	for i in SLOTS:
		if out[i] != "" and not connected.has(out[i]):
			out[i] = ""
	# Selbst entfernt: nie auf einem Platz, solange nicht neu zugeordnet.
	for i in SLOTS:
		if out[i] != "" and int(mem.get(out[i], -1)) == 0:
			out[i] = ""
	var pool: Array = []
	for id in connected:
		var s := int(mem.get(id, -1))
		if s < 1 or s > SLOTS or out[s - 1] == id:
			continue
		var holder: String = out[s - 1]
		# Dort sitzt jemand, der selbst dort hingehört: der bleibt.
		if holder != "" and int(mem.get(holder, -1)) == s:
			continue
		var was := out.find(id)
		if was >= 0:
			out[was] = ""
		out[s - 1] = id
		if holder != "":
			pool.append(holder)
	if not auto:
		return out
	for id in pool + connected:
		if out.has(id) or int(mem.get(id, -1)) == 0:
			continue
		var free := out.find("")
		if free < 0:
			break
		out[free] = id
	return out


## Selbst zuordnen: id auf Platz slot (1–4). Saß dort jemand, tauschen beide (war id noch ohne
## Platz, rückt der andere auf den nächsten freien Platz oder bleibt ohne). { slots, mem }.
static func assign(slots: Array, mem: Dictionary, id: String, slot: int) -> Dictionary:
	var out := norm_slots(slots)
	var m := mem.duplicate()
	if id == "" or slot < 1 or slot > SLOTS:
		return { "slots": out, "mem": m }
	var was := out.find(id)
	var holder: String = out[slot - 1]
	if was >= 0:
		out[was] = ""
	out[slot - 1] = id
	m[id] = slot
	if holder != "" and holder != id:
		if was >= 0:
			out[was] = holder
			m[holder] = was + 1
		else:
			var free := out.find("")
			if free >= 0:
				out[free] = holder
				if m.has(holder):
					m[holder] = free + 1
			else:
				m[holder] = 0
	return { "slots": out, "mem": _trim(m) }


## Zwei Plätze tauschen (1–4). Beide werden gemerkt.
static func swap(slots: Array, mem: Dictionary, a: int, b: int) -> Dictionary:
	var out := norm_slots(slots)
	var m := mem.duplicate()
	if a < 1 or b < 1 or a > SLOTS or b > SLOTS or a == b:
		return { "slots": out, "mem": m }
	var x: String = out[a - 1]
	out[a - 1] = out[b - 1]
	out[b - 1] = x
	if out[a - 1] != "":
		m[out[a - 1]] = a
	if out[b - 1] != "":
		m[out[b - 1]] = b
	return { "slots": out, "mem": _trim(m) }


## Controller von seinem Platz nehmen; die Automatik setzt ihn nicht wieder hin.
static func remove(slots: Array, mem: Dictionary, slot: int) -> Dictionary:
	var out := norm_slots(slots)
	var m := mem.duplicate()
	if slot >= 1 and slot <= SLOTS and out[slot - 1] != "":
		m[out[slot - 1]] = 0
		out[slot - 1] = ""
	return { "slots": out, "mem": _trim(m) }


static func _trim(m: Dictionary) -> Dictionary:
	while m.size() > MEM_MAX:
		m.erase(m.keys()[0])
	return m


# --- Für die Emulatoren ------------------------------------------------------------------------

## Spieler 1–4 als Geräte, wie die Emulatoren sie brauchen: [{} oder { id, name, guid, port, sdl,
## xinput, ra, dolphin_n, family, sdl_name }]. pads: Pads.pads (mit guid), slots: die Zuordnung.
## - sdl: Nummer für „SDL-<n>“ (DuckStation, PCSX2): SDLs Spieler-Nummer, sonst die nächste freie
##   in Geräte-Reihenfolge (so vergeben es beide Emulatoren).
## - xinput: XInput-Anschluss (0–3) oder -1.
## - ra: Gerätenummer für RetroArch (xinput-Treiber: zuerst die XInput-Anschlüsse, dann die anderen).
## - dolphin_n: der wievielte Controller mit diesem Namen (Dolphin „SDL/<n>/<Name>“).
static func players(slots: Array, pads: Array) -> Array:
	var ids := ids_for(pads)
	var by := {}
	for i in pads.size():
		by[str(ids[i].id)] = i
	var order: Array = range(pads.size())
	order.sort_custom(func(a: int, b: int) -> bool: return int(pads[a].get("device", -1)) < int(pads[b].get("device", -1)))
	var sdl := sdl_numbers(pads)
	var n_x := 0
	for p in pads:
		if int(p.get("xinput", -1)) >= 0:
			n_x += 1
	var others := 0
	var ra := {}
	var names := {}
	var dn := {}
	for i in order:
		var p: Dictionary = pads[i]
		if int(p.get("xinput", -1)) >= 0:
			ra[i] = int(p.xinput)
		else:
			ra[i] = n_x + others
			others += 1
		var nm := _sdl_name(p)
		dn[i] = int(names.get(nm, 0))
		names[nm] = int(dn[i]) + 1
	var out: Array = []
	for s in norm_slots(slots):
		if s == "" or not by.has(s):
			out.append({})
			continue
		var i: int = by[s]
		var p: Dictionary = pads[i]
		out.append({ "id": s, "name": str(p.get("name", "Controller")), "guid": str(ids[i].guid), "port": int(ids[i].port),
			"sdl": int(sdl[i]), "xinput": int(p.get("xinput", -1)), "ra": int(ra[i]), "dolphin_n": int(dn[i]),
			"family": str(p.get("family", "other")), "sdl_name": _sdl_name(p) })
	return out


## SDL-Nummer je Eintrag von pads (gleiche Reihenfolge), wie DuckStation und PCSX2 sie vergeben
## (SDLInputSource::OpenDevice): SDLs Spieler-Nummer, wenn frei, sonst die kleinste freie – in der
## Reihenfolge, in der die Geräte kommen (hier: Godot-Gerätenummer). Godot fragt dasselbe SDL; die
## Nummer ist trotzdem nur geschätzt (der Emulator öffnet die Geräte selbst), darum nehmen beide
## Emulatoren Xbox-Controller über ihren XInput-Anschluss (spieler_emus.ps_geraet).
static func sdl_numbers(pads: Array) -> Array:
	var order: Array = range(pads.size())
	order.sort_custom(func(a: int, b: int) -> bool: return int(pads[a].get("device", -1)) < int(pads[b].get("device", -1)))
	var out: Array = []
	out.resize(pads.size())
	var taken := {}
	for i in order:
		var pl := int(pads[i].get("player", -1))
		if pl >= 0 and not taken.has(pl):
			out[i] = pl
			taken[pl] = true
	for i in order:
		if out[i] != null:
			continue
		var n := 0
		while taken.has(n):
			n += 1
		out[i] = n
		taken[n] = true
	return out


## Name des Controllers, wie SDL ihn meldet (Godot fragt SDL); ohne Godot-Gerät der Anzeigename.
static func _sdl_name(p: Dictionary) -> String:
	var n := str(p.get("sdl_name", ""))
	return n if n != "" else str(p.get("name", "Controller"))


# --- Mit Config (für Pads und die Ebene) ---------------------------------------------------------

static func slots_now() -> Array:
	return norm_slots(Config.get_value(KEY_SLOTS, []))


static func mem_now() -> Dictionary:
	return norm_mem(Config.get_value(KEY_MEM, {}))


static func save(slots: Array, mem: Dictionary) -> void:
	var changed := slots != slots_now() or mem != mem_now()
	if not changed:
		return
	Config.set_value(KEY_SLOTS, slots)
	Config.set_value(KEY_MEM, mem)
	Config.save_soon()


## Aus Pads._rebuild: Zuordnung an die verbundenen Controller anpassen; schreibt „spieler“ (0 oder
## 1–4) in jeden Eintrag.
static func sync(pads: Array) -> void:
	var ids := ids_for(pads)
	var connected: Array = []
	var order: Array = range(pads.size())
	order.sort_custom(func(a: int, b: int) -> bool: return int(pads[a].get("device", -1)) < int(pads[b].get("device", -1)))
	for i in order:
		connected.append(str(ids[i].id))
	var mem := mem_now()
	var slots := auto_fill(slots_now(), connected, mem, bool(Config.get_value(KEY_AUTO, true)))
	save(slots, mem)
	for i in pads.size():
		pads[i]["uz_id"] = str(ids[i].id)
		pads[i]["spieler"] = slots.find(str(ids[i].id)) + 1


## Der Controller mit dieser Godot-Gerätenummer (für „Drück A …“) – Kennung oder "".
static func id_of_device(pads: Array, device: int) -> String:
	var ids := ids_for(pads)
	for i in pads.size():
		if int(pads[i].get("device", -2)) == device:
			return str(ids[i].id)
	return ""


## „Xbox · Funk“, „PlayStation · Bluetooth“ – Typ und Verbindung in einer kurzen Zeile.
static func type_text(p: Dictionary) -> String:
	var fam := { "xbox": "Xbox", "ps": "PlayStation", "nintendo": "Nintendo" }.get(str(p.get("family", "")), "Controller") as String
	var conn := str(p.get("conn", ""))
	return fam + (" · " + conn if conn != "" else "")
