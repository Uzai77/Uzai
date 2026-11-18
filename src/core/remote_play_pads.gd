extends RefCounted
## Spieler 2 für Remote Play Together: Steam gibt den Controller deines Freundes als weiteren
## Controller ins Spiel. Viele Emulatoren hören aber nur auf Spieler 1, bis Spieler 2 belegt ist.
## Vor einem Remote-Play-Start belegt Uzai deshalb Spieler 2 mit dem nächsten Controller
## (PCSX2, DuckStation, Dolphin, Eden und die anderen yuzu-Ableger). Nach dem Spiel stellt Uzai
## genau das zurück, was es geändert hat. Hat jemand Spieler 2 selbst belegt, bleibt alles, wie es ist.
##
## Rücksicherung: in Config „remoteplay.pad_restore“ (übersteht einen Absturz von Uzai), je Datei
## { file, sections: { Name: { old, new } }, keys: [{ section, key, old, new }] }. old = null heißt
## „gab es vorher nicht“. Zurückgestellt wird nur, was noch so aussieht, wie Uzai es geschrieben hat –
## belegt jemand Spieler 2 während des Spiels selbst neu, bleibt das. Gemerkt wird vor dem Schreiben;
## lässt sich eine Datei gerade nicht zurückschreiben (der Emulator schließt noch), bleibt ihr Eintrag
## für den nächsten Versuch (höchstens RESTORE_VERSUCHE).

const Sicher := preload("res://src/core/sicher.gd")
const RESTORE_KEY := "remoteplay.pad_restore"
const RESTORE_VERSUCHE := 10
## Emulatoren, bei denen Spieler 2 von selbst geht (RetroArch nimmt Controller der Reihe nach).
const AUTO := ["retroarch", "bizhawk", "ares", "mesen", "mednafen"]
const YUZU_LIKE := { "eden": "eden", "citron": "citron", "sudachi": "sudachi", "yuzu": "yuzu" }
## Systeme, die nur einen Spieler am Gerät kennen (Mehrspieler dort über Linkkabel).
const SOLO_SYSTEMS := ["gba", "gb", "gbc", "nds", "3ds", "psp"]

## Belegung für Spieler 2, wenn Spieler 1 nur auf der Tastatur liegt (PCSX2 und DuckStation
## benennen Tasten gleich). {d} wird durch das Gerät ersetzt.
const PS_KEYS := [["Up", "DPadUp"], ["Right", "DPadRight"], ["Down", "DPadDown"], ["Left", "DPadLeft"],
	["Triangle", "Y"], ["Circle", "B"], ["Cross", "A"], ["Square", "X"], ["Select", "Back"], ["Start", "Start"],
	["L1", "LeftShoulder"], ["R1", "RightShoulder"], ["L2", "+LeftTrigger"], ["R2", "+RightTrigger"],
	["L3", "LeftStick"], ["R3", "RightStick"], ["LUp", "-LeftY"], ["LRight", "+LeftX"], ["LDown", "+LeftY"],
	["LLeft", "-LeftX"], ["RUp", "-RightY"], ["RRight", "+RightX"], ["RDown", "+RightY"], ["RLeft", "-RightX"],
	["Analog", "Guide"], ["LargeMotor", "LargeMotor"], ["SmallMotor", "SmallMotor"]]
const GC_XINPUT := [["Buttons/A", "Button A"], ["Buttons/B", "Button B"], ["Buttons/X", "Button X"],
	["Buttons/Y", "Button Y"], ["Buttons/Z", "Shoulder R"], ["Buttons/Start", "Start"],
	["Main Stick/Up", "Left Y+"], ["Main Stick/Down", "Left Y-"], ["Main Stick/Left", "Left X-"], ["Main Stick/Right", "Left X+"],
	["C-Stick/Up", "Right Y+"], ["C-Stick/Down", "Right Y-"], ["C-Stick/Left", "Right X-"], ["C-Stick/Right", "Right X+"],
	["Triggers/L", "Trigger L"], ["Triggers/R", "Trigger R"], ["Triggers/L-Analog", "Trigger L"], ["Triggers/R-Analog", "Trigger R"],
	["D-Pad/Up", "Pad N"], ["D-Pad/Down", "Pad S"], ["D-Pad/Left", "Pad W"], ["D-Pad/Right", "Pad E"], ["Rumble/Motor", "Motor L"]]


# --- INI als Text (Reihenfolge, Kommentare und Zeilenenden bleiben) ------------------------------

## Abschnitte: [{ name, lines }]; der Teil vor dem ersten Abschnitt heißt "".
static func ini_sections(text: String) -> Array:
	var out: Array = [{ "name": "", "lines": [] }]
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		var t := line.strip_edges()
		if t.begins_with("[") and t.ends_with("]"):
			out.append({ "name": t.substr(1, t.length() - 2), "lines": [] })
		else:
			(out[-1].lines as Array).append(line)
	# Die leere Zeile nach dem letzten Zeilenende gehört nicht zum Inhalt.
	var last: Array = out[-1].lines
	if not last.is_empty() and str(last[-1]) == "" and text.ends_with("\n"):
		last.pop_back()
	return out


static func ini_join(secs: Array, crlf: bool) -> String:
	var lines := PackedStringArray()
	for s in secs:
		if str(s.name) != "":
			lines.append("[%s]" % s.name)
		for l in s.lines:
			lines.append(str(l))
	var nl := "\r\n" if crlf else "\n"
	return nl.join(lines) + nl if not lines.is_empty() else ""


static func _crlf(text: String) -> bool:
	return text.contains("\r\n")


static func _find(secs: Array, name: String) -> int:
	for i in secs.size():
		if str(secs[i].name).to_lower() == name.to_lower():
			return i
	return -1


## Zeilen eines Abschnitts ohne Leerzeilen am Ende – oder null, wenn es ihn nicht gibt.
static func section_lines(text: String, name: String) -> Variant:
	var secs := ini_sections(text)
	var i := _find(secs, name)
	if i < 0:
		return null
	var lines: Array = (secs[i].lines as Array).duplicate()
	while not lines.is_empty() and str(lines[-1]).strip_edges() == "":
		lines.pop_back()
	return lines


## Abschnitt ersetzen (null entfernt ihn; fehlt er, kommt er ans Ende).
static func set_section(text: String, name: String, lines: Variant) -> String:
	var secs := ini_sections(text)
	var i := _find(secs, name)
	if lines == null:
		if i >= 0:
			secs.remove_at(i)
			# War es der letzte Abschnitt: die Leerzeile davor gehörte zu ihm.
			if i == secs.size() and i > 0:
				var prev: Array = secs[i - 1].lines
				while not prev.is_empty() and str(prev[-1]).strip_edges() == "":
					prev.pop_back()
		return ini_join(secs, _crlf(text))
	var body: Array = (lines as Array).duplicate()
	if i >= 0:
		# Leerzeile vor dem nächsten Abschnitt behalten.
		var old: Array = secs[i].lines
		if not old.is_empty() and str(old[-1]).strip_edges() == "" and i < secs.size() - 1:
			body.append("")
		secs[i].lines = body
	else:
		var prev: Array = secs[-1].lines
		if not prev.is_empty() and str(prev[-1]).strip_edges() != "":
			prev.append("")
		secs.append({ "name": name, "lines": body })
	return ini_join(secs, _crlf(text))


## „schlüssel = wert“ → [schlüssel, wert] (sonst []).
static func kv(line: String) -> Array:
	var t := line.strip_edges()
	if t == "" or t.begins_with(";") or t.begins_with("#"):
		return []
	var i := t.find("=")
	if i <= 0:
		return []
	return [t.substr(0, i).strip_edges(), t.substr(i + 1).strip_edges()]


static func lines_get(lines: Array, key: String) -> Variant:
	for l in lines:
		var p := kv(str(l))
		if not p.is_empty() and str(p[0]) == key:
			return str(p[1])
	return null


static func ini_get(text: String, section: String, key: String) -> Variant:
	var lines: Variant = section_lines(text, section)
	return null if lines == null else lines_get(lines, key)


## Wert setzen (null entfernt den Schlüssel). Schreibweise „a = b“ oder „a=b“ wie in der Datei.
static func ini_set(text: String, section: String, key: String, value: Variant) -> String:
	var secs := ini_sections(text)
	var i := _find(secs, section)
	var sep := " = " if text.contains(" = ") else "="
	if i < 0:
		if value == null:
			return text
		return set_section(text, section, ["%s%s%s" % [key, sep, value]])
	var lines: Array = secs[i].lines
	var out: Array = []
	var done := false
	for l in lines:
		var p := kv(str(l))
		if not p.is_empty() and str(p[0]) == key:
			if value != null and not done:
				var own := " = " if str(l).contains(" = ") else sep
				out.append("%s%s%s" % [key, own, value])
				done = true
			continue
		out.append(l)
	if value != null and not done:
		var at := out.size()
		while at > 0 and str(out[at - 1]).strip_edges() == "":
			at -= 1
		out.insert(at, "%s%s%s" % [key, sep, value])
	secs[i].lines = out
	return ini_join(secs, _crlf(text))


# --- Viele Schlüssel eines Abschnitts in einem Zug ------------------------------------------------
# ini_get und ini_set zerlegen bei jedem Aufruf die ganze Datei (gemessen: 1,5 und 2,3 ms bei 2700 Zeilen).
# Wer in einem Abschnitt Dutzende Schlüssel anfasst (Eden: rund 25 je Spieler, vor jedem Spielstart), öffnet
# ihn einmal: oeffnen → wert / setzen (je Schlüssel ein Nachschlagen) → fertig. Das Ergebnis ist Byte für
# Byte dasselbe wie mit ini_get und ini_set (tests/logic_remoteplay.gd vergleicht beide Wege).

## Abschnitt zum Bearbeiten öffnen (fehlt er, legt ihn das erste setzen an – wie ini_set).
static func oeffnen(text: String, section: String) -> Dictionary:
	var secs := ini_sections(text)
	var doc := { "secs": secs, "i": _find(secs, section), "name": section, "pos": {}, "doppelt": {}, "text": text,
		"sep": " = " if text.contains(" = ") else "=", "crlf": _crlf(text), "n": 0 }
	if int(doc.i) >= 0:
		var lines: Array = secs[int(doc.i)].lines
		for n in lines.size():
			var p := kv(str(lines[n]))
			if p.is_empty():
				continue
			if not (doc.pos as Dictionary).has(p[0]):
				doc.pos[p[0]] = n
			else:
				# Derselbe Schlüssel noch einmal: ini_set lässt beim Schreiben nur den ersten stehen.
				if not (doc.doppelt as Dictionary).has(p[0]):
					doc.doppelt[p[0]] = []
				(doc.doppelt[p[0]] as Array).append(n)
	return doc


## Zeilen des Abschnitts, wie sie jetzt sind ([] wenn es ihn nicht gibt).
static func zeilen(doc: Dictionary) -> Array:
	if int(doc.i) < 0:
		return []
	return (doc.secs[int(doc.i)].lines as Array).filter(func(l: Variant) -> bool: return l != null)


## Wert eines Schlüssels (null, wenn es ihn nicht gibt) – wie ini_get.
static func wert(doc: Dictionary, key: String) -> Variant:
	if not (doc.pos as Dictionary).has(key):
		return null
	return str(kv(str(doc.secs[int(doc.i)].lines[int(doc.pos[key])]))[1])


## Wert setzen – wie ini_set mit einem Wert: Die Zeile bleibt an ihrem Platz und in ihrer Schreibweise
## („a = b“ oder „a=b“), ein neuer Schlüssel kommt hinter die letzte Zeile des Abschnitts.
static func setzen(doc: Dictionary, key: String, value: String) -> void:
	doc.n = int(doc.n) + 1
	var secs: Array = doc.secs
	if int(doc.i) < 0:
		var prev: Array = secs[-1].lines
		if not prev.is_empty() and str(prev[-1]).strip_edges() != "":
			prev.append("")
		secs.append({ "name": str(doc.name), "lines": [] })
		doc.i = secs.size() - 1
	var lines: Array = secs[int(doc.i)].lines
	if (doc.pos as Dictionary).has(key):
		var n := int(doc.pos[key])
		lines[n] = "%s%s%s" % [key, " = " if str(lines[n]).contains(" = ") else str(doc.sep), value]
		for d: int in (doc.doppelt as Dictionary).get(key, []):
			lines[d] = null
		(doc.doppelt as Dictionary).erase(key)
		return
	var at := lines.size()
	while at > 0 and (lines[at - 1] == null or str(lines[at - 1]).strip_edges() == ""):
		at -= 1
	# Dahinter stehen nur Leerzeilen und Entferntes: Kein gemerkter Platz verschiebt sich.
	lines.insert(at, "%s%s%s" % [key, str(doc.sep), value])
	doc.pos[key] = at


## Wie oft setzen gerufen wurde (wer wissen will, ob ein Schritt etwas geändert hat).
static func geaendert(doc: Dictionary) -> int:
	return int(doc.n)


## Der neue Text – unverändert der alte, wenn nichts gesetzt wurde. Danach gilt das Geöffnete nicht mehr.
static func fertig(doc: Dictionary) -> String:
	if int(doc.n) == 0:
		return str(doc.text)
	if int(doc.i) >= 0:
		var sec: Dictionary = doc.secs[int(doc.i)]
		sec.lines = (sec.lines as Array).filter(func(l: Variant) -> bool: return l != null)
	return ini_join(doc.secs, bool(doc.crlf))


# --- Geräte in Belegungen ----------------------------------------------------------------------

## PCSX2/DuckStation: „SDL-0/A“ → „SDL-1/A“ (auch Akkorde mit „ & “). Tastatur, Maus: "".
static func shift_binding(value: String, by := 1) -> String:
	var parts := PackedStringArray()
	var re := RegEx.create_from_string("^(SDL|XInput|DInput)-(\\d+)/(.+)$")
	for part in value.split(" & "):
		var m := re.search(part.strip_edges())
		if m == null:
			return ""
		parts.append("%s-%d/%s" % [m.get_string(1), int(m.get_string(2)) + by, m.get_string(3)])
	return " & ".join(parts)


static func _has_any_binding(lines: Array) -> bool:
	for l in lines:
		var p := kv(str(l))
		if not p.is_empty() and str(p[1]).contains("/"):
			return true
	return false


# --- Je Emulator: neuer Dateiinhalt und was sich geändert hat -----------------------------------
# Rückgabe: { text, sections, keys, note } oder {} (nichts zu tun).

## PCSX2 ([Pad1]/[Pad2], Typ DualShock2) und DuckStation (Typ AnalogController).
static func plan_ps(text: String, default_type: String, next_pad: int) -> Dictionary:
	var p1: Variant = section_lines(text, "Pad1")
	var p2: Variant = section_lines(text, "Pad2")
	var p1_lines: Array = p1 if p1 != null else []
	var type1 := str(lines_get(p1_lines, "Type")) if lines_get(p1_lines, "Type") != null else default_type
	if type1 == "None" or type1 == "":
		type1 = default_type
	if p2 != null and _has_any_binding(p2):
		# Spieler 2 ist schon belegt: höchstens einstecken, wenn der Anschluss leer steht.
		var t2: Variant = lines_get(p2, "Type")
		if t2 != null and str(t2) != "None":
			return {}
		return { "text": ini_set(text, "Pad2", "Type", type1), "sections": {}, "note": "",
			"keys": [{ "section": "Pad2", "key": "Type", "old": t2, "new": type1 }] }
	var lines: Array = ["Type = " + type1]
	var any := false
	for l in p1_lines:
		var p := kv(str(l))
		if p.is_empty() or str(p[0]) == "Type":
			continue
		if str(p[1]).contains("/"):
			var b := shift_binding(str(p[1]))
			if b == "":
				continue
			lines.append("%s = %s" % [p[0], b])
			any = true
		else:
			lines.append("%s = %s" % [p[0], p[1]])
	if not any:
		# Spieler 1 spielt auf der Tastatur: der erste Controller ist dann der deines Freundes.
		lines = ["Type = " + type1]
		for k in PS_KEYS:
			lines.append("%s = SDL-%d/%s" % [k[0], next_pad, k[1]])
	return { "text": set_section(text, "Pad2", lines), "keys": [], "note": "",
		"sections": { "Pad2": { "old": p2, "new": lines } } }


## Dolphin GameCube: GCPadNew.ini [GCPad2]. Geräte heißen „XInput/0/Gamepad“, „SDL/0/Name“.
static func plan_gc(text: String, next_xinput: int) -> Dictionary:
	var p1: Variant = section_lines(text, "GCPad1")
	var p2: Variant = section_lines(text, "GCPad2")
	if p2 != null and str(lines_get(p2, "Device") if lines_get(p2, "Device") != null else "") != "" and lines_get(p2, "Buttons/A") != null:
		return {}
	var lines := gc_lines(p1 if p1 != null else [], next_xinput)
	return { "text": set_section(text, "GCPad2", lines), "keys": [], "note": "",
		"sections": { "GCPad2": { "old": p2, "new": lines } } }


## Belegung für Spieler 2 aus Spieler 1: gleiches Gerät, nächste Nummer. Liegt Spieler 1 auf
## Tastatur oder einem SDL-/DInput-Gerät, bekommt Spieler 2 den nächsten XInput-Controller
## (so meldet Steam den Controller deines Freundes) mit der üblichen Belegung.
static func gc_lines(p1: Array, next_xinput: int) -> Array:
	var dev := str(lines_get(p1, "Device")) if lines_get(p1, "Device") != null else ""
	var m := RegEx.create_from_string("^XInput/(\\d+)/(.+)$").search(dev)
	if m != null:
		var out: Array = []
		for l in p1:
			var p := kv(str(l))
			if p.is_empty():
				continue
			if str(p[0]) == "Device":
				out.append("Device = XInput/%d/%s" % [int(m.get_string(1)) + 1, m.get_string(2)])
			else:
				out.append("%s = %s" % [p[0], p[1]])
		return out
	var lines: Array = ["Device = XInput/%d/Gamepad" % next_xinput]
	for k in GC_XINPUT:
		lines.append("%s = `%s`" % [k[0], k[1]])
	lines.append("Main Stick/Dead Zone = 10.0")
	lines.append("C-Stick/Dead Zone = 10.0")
	return lines


## Dolphin.ini: Anschluss 2 als normaler GameCube-Controller (6), wenn dort nichts steckt.
static func plan_dolphin_ini(text: String) -> Dictionary:
	var v: Variant = ini_get(text, "Core", "SIDevice1")
	if v != null and str(v) != "0":
		return {}
	return { "text": ini_set(text, "Core", "SIDevice1", "6"), "sections": {}, "note": "",
		"keys": [{ "section": "Core", "key": "SIDevice1", "old": v, "new": "6" }] }


## Dolphin Wii: WiimoteNew.ini [Wiimote2] als emulierte Wiimote wie Spieler 1, nächstes Gerät.
static func plan_wii(text: String) -> Dictionary:
	var w1: Variant = section_lines(text, "Wiimote1")
	var w2: Variant = section_lines(text, "Wiimote2")
	if w2 != null and str(lines_get(w2, "Source")) in ["1", "2"] and str(lines_get(w2, "Device") if lines_get(w2, "Device") != null else "") != "":
		return {}
	var w1_lines: Array = w1 if w1 != null else []
	if w1 != null and lines_get(w1_lines, "Source") != null and str(lines_get(w1_lines, "Source")) != "1":
		return { "note": "echte Wiimotes – Spieler 2 verbindet seine selbst" }
	var dev := str(lines_get(w1_lines, "Device")) if lines_get(w1_lines, "Device") != null else ""
	var m := RegEx.create_from_string("^(XInput|SDL|DInput|WGInput)/(\\d+)/(.+)$").search(dev)
	if m == null or m.get_string(3).to_lower().contains("keyboard"):
		return { "note": "Spieler 1 nutzt keinen Controller – Spieler 2 in Dolphin einmal selbst belegen" }
	# Wiimote-Belegungen hängen an den Tastennamen des Geräts: gleiche Art, nächste Nummer.
	var lines: Array = []
	for l in w1_lines:
		var p := kv(str(l))
		if p.is_empty():
			continue
		if str(p[0]) == "Device":
			lines.append("Device = %s/%d/%s" % [m.get_string(1), int(m.get_string(2)) + 1, m.get_string(3)])
		elif str(p[0]) == "Source":
			lines.append("Source = 1")
		else:
			lines.append("%s = %s" % [p[0], p[1]])
	if lines_get(lines, "Source") == null:
		lines.push_front("Source = 1")
	return { "text": set_section(text, "Wiimote2", lines), "keys": [], "note": "",
		"sections": { "Wiimote2": { "old": w2, "new": lines } } }


## Eden, Citron, Sudachi, yuzu: qt-config.ini [Controls], Schlüssel player_0_* → player_1_*.
## Belegungen sehen so aus: "engine:sdl,port:0,guid:…,button:1" – Spieler 2 bekommt port + 1.
static func plan_yuzu(text: String) -> Dictionary:
	var ctl: Variant = section_lines(text, "Controls")
	if ctl == null:
		return { "note": "noch keine Steuerung eingestellt – Eden einmal starten und Spieler 1 belegen" }
	if str(lines_get(ctl, "player_1_connected")) == "true":
		return {}
	var keys: Array = []
	var any_pad := false
	var out := text
	var port := RegEx.create_from_string("port:(\\d+)")
	for l in ctl:
		var p := kv(str(l))
		if p.is_empty() or not str(p[0]).begins_with("player_0_"):
			continue
		var k := "player_1_" + str(p[0]).substr(9)
		var v := str(p[1])
		if k.begins_with("player_1_connected"):
			continue
		if v.contains("engine:"):
			var inner := v.trim_prefix("\"").trim_suffix("\"")
			if inner.contains("engine:keyboard") or inner.contains("engine:mouse"):
				continue
			var m := port.search(inner)
			if m != null:
				inner = inner.replace("port:" + m.get_string(1), "port:%d" % (int(m.get_string(1)) + 1))
				any_pad = true
			v = "\"%s\"" % inner if v.begins_with("\"") else inner
		elif k == "player_1_type" and v == "4":
			v = "0"   # Handheld geht nur für Spieler 1: Spieler 2 als Pro Controller.
		keys.append({ "section": "Controls", "key": k, "old": ini_get(text, "Controls", k), "new": v })
	if not any_pad:
		return { "note": "Spieler 1 spielt auf der Tastatur – Spieler 2 in Eden einmal selbst belegen" }
	keys.append({ "section": "Controls", "key": "player_1_connected\\default", "old": ini_get(text, "Controls", "player_1_connected\\default"), "new": "false" })
	keys.append({ "section": "Controls", "key": "player_1_connected", "old": ini_get(text, "Controls", "player_1_connected"), "new": "true" })
	for e in keys:
		out = ini_set(out, "Controls", str(e.key), e.new)
	return { "text": out, "sections": {}, "keys": keys, "note": "" }


# --- Rücksicherung -----------------------------------------------------------------------------

## Den Plan wieder herausrechnen: nur was noch aussieht wie von Uzai geschrieben.
static func undo_text(text: String, entry: Dictionary) -> String:
	var out := text
	var secs: Dictionary = entry.get("sections", {}) if entry.get("sections") is Dictionary else {}
	for name in secs.keys():
		# Nur echte Abschnitte mit Zeilen ohne Umbruch: Der Abschnitt "" ist der Vorspann der Datei (ohne Abschnitte die
		# ganze Datei) – ein gemerkter Eintrag dafür hätte alles ersetzen können.
		var sec: Variant = secs[name]
		if str(name) == "" or not (sec is Dictionary) or not _zeilen_ok(sec.get("old")) or not _zeilen_ok(sec.get("new", [])):
			continue
		var now: Variant = section_lines(out, str(name))
		if now != null and _same_lines(now, sec.get("new", [])):
			out = set_section(out, str(name), sec.get("old"))
	var keys: Array = entry.get("keys", []) if entry.get("keys") is Array else []
	for i in range(keys.size() - 1, -1, -1):
		if not (keys[i] is Dictionary):
			continue
		var e: Dictionary = keys[i]
		# Einzelne Schlüssel dürfen im Vorspann stehen (RetroArch kennt keine Abschnitte), aber nie über mehrere Zeilen.
		if _umbruch(e.get("section")) or _umbruch(e.get("key")) or _umbruch(e.get("old")) or _umbruch(e.get("new")):
			continue
		var now: Variant = ini_get(out, str(e.section), str(e.key))
		if now != null and str(now) == str(e.new):
			out = ini_set(out, str(e.section), str(e.key), e.get("old"))
	return out


static func _umbruch(v: Variant) -> bool:
	return v != null and (str(v).contains("\n") or str(v).contains("\r"))


## Gemerkte Zeilen eines Abschnitts: eine Liste (oder null = Abschnitt gab es nicht) aus Zeilen ohne Umbruch.
static func _zeilen_ok(v: Variant) -> bool:
	if v == null:
		return true
	if not (v is Array):
		return false
	for l in v:
		if _umbruch(l):
			return false
	return true


static func _same_lines(a: Variant, b: Variant) -> bool:
	if not (a is Array) or not (b is Array):
		return false
	var x: Array = (a as Array).filter(func(l): return not kv(str(l)).is_empty())
	var y: Array = (b as Array).filter(func(l): return not kv(str(l)).is_empty())
	if x.size() != y.size():
		return false
	for i in x.size():
		if kv(str(x[i])) != kv(str(y[i])):
			return false
	return true


# --- Wo die Emulatoren ihre Einstellungen haben --------------------------------------------------

static func _docs() -> String:
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).replace("\\", "/")


static func _env(n: String) -> String:
	return OS.get_environment(n).replace("\\", "/")


## Die zuletzt geschriebene vorhandene Datei aus den Kandidaten ("" wenn keine).
## Eine Einstellungsdatei eines Emulators so lesen, dass Uzai sie Byte für Byte wieder schreiben kann:
## { ok, text, bom }. ok = false, wenn sie kein sauberes UTF-8 ist (Umlaute in einer anderen Kodierung, ein
## Nullbyte): Gemessen in Godot 4.5.1 werden solche Zeichen beim Lesen ersetzt oder der Text endet am Nullbyte –
## Uzai schriebe die Datei dann kaputt zurück (etwa einen Pfad mit „ü“). Solche Dateien fasst Uzai nicht an.
## bom: Die Datei beginnt mit der UTF-8-Marke (PPSSPP schreibt sie); Godot lässt sie beim Lesen weg,
## write_text setzt sie wieder davor.
static func lesen_treu(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var bom := bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF
	var kern := bytes.slice(3) if bom else bytes
	if kern.has(0):
		return { "ok": false, "text": "", "bom": bom }
	var text := kern.get_string_from_utf8()
	return { "ok": text.to_utf8_buffer() == kern, "text": text, "bom": bom }


## Text an die Stelle einer Einstellungsdatei: erst daneben schreiben und nachzählen (volle Platte: Eine halbe Datei
## ersetzte sonst die Einstellungen des Emulators), dann tauschen. Ein Absturz mittendrin lässt nie eine halbe Datei.
## bom: wie lesen_treu es gemeldet hat.
static func write_text(path: String, text: String, bom := false) -> bool:
	var bytes := PackedByteArray([0xEF, 0xBB, 0xBF]) if bom else PackedByteArray()
	bytes.append_array(text.to_utf8_buffer())
	var tmp := path + ".uzai-neu"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	if not Config.ganz_geschrieben(tmp, bytes.size()):
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	# Tauschen ging nicht (Ordner ohne Recht zum Umbenennen): direkt hineinschreiben.
	DirAccess.remove_absolute(tmp)
	var g := FileAccess.open(path, FileAccess.WRITE)
	if g == null:
		return false
	g.store_buffer(bytes)
	g.close()
	return Config.ganz_geschrieben(path, bytes.size())


const FREMD_KODIERT := "%s hat eine Zeichenkodierung, die Uzai nicht sicher zurückschreiben kann – bleibt, wie sie ist"


static func newest(cands: Array) -> String:
	var best := ""
	var best_t := -1
	for c in cands:
		var p := str(c)
		if p == "":
			continue
		if FileAccess.file_exists(p):
			var t := FileAccess.get_modified_time(p)
			if t > best_t:
				best = p
				best_t = t
	return best


## Rein: Kandidaten für die Einstellungsdatei(en) eines Emulators. Tragbare Installationen
## (portable.txt neben dem Programm) zuerst; sonst Dokumente bzw. AppData.
static func candidates(emu_id: String, exe_dir: String, docs: String, appdata: String, localappdata: String, portable: bool) -> Dictionary:
	match emu_id:
		"pcsx2":
			if portable:
				return { "ini": [exe_dir.path_join("inis/PCSX2.ini")] }
			return { "ini": [docs.path_join("PCSX2/inis/PCSX2.ini"), exe_dir.path_join("inis/PCSX2.ini")] }
		"duckstation":
			if portable:
				return { "ini": [exe_dir.path_join("settings.ini")] }
			return { "ini": [localappdata.path_join("DuckStation/settings.ini"), docs.path_join("DuckStation/settings.ini")] }
		"dolphin":
			var roots: Array = [exe_dir.path_join("User")] if portable else [appdata.path_join("Dolphin Emulator"), docs.path_join("Dolphin Emulator")]
			return {
				"gc": roots.map(func(r): return str(r).path_join("Config/GCPadNew.ini")),
				"core": roots.map(func(r): return str(r).path_join("Config/Dolphin.ini")),
				"wii": roots.map(func(r): return str(r).path_join("Config/WiimoteNew.ini")),
			}
	if YUZU_LIKE.has(emu_id):
		if portable:
			return { "ini": [exe_dir.path_join("user/config/qt-config.ini")] }
		return { "ini": [appdata.path_join(str(YUZU_LIKE[emu_id])).path_join("config/qt-config.ini"), exe_dir.path_join("user/config/qt-config.ini")] }
	return {}


static func is_portable(emu_id: String, exe_dir: String) -> bool:
	if emu_id == "pcsx2":
		return FileAccess.file_exists(exe_dir.path_join("portable.ini")) or FileAccess.file_exists(exe_dir.path_join("portable.txt"))
	if emu_id == "duckstation":
		# DuckStation (src/core/core.cpp): auch eine settings.ini neben der exe heißt tragbar.
		return FileAccess.file_exists(exe_dir.path_join("portable.txt")) or FileAccess.file_exists(exe_dir.path_join("settings.ini"))
	if emu_id == "dolphin":
		return FileAccess.file_exists(exe_dir.path_join("portable.txt"))
	if YUZU_LIKE.has(emu_id):
		return DirAccess.dir_exists_absolute(exe_dir.path_join("user"))
	return false


## Kurzer Satz für die Einstellungen und den Start: was Uzai bei diesem Emulator für Spieler 2 tut.
static func support_text(emu_id: String, system: String) -> String:
	if system in SOLO_SYSTEMS:
		return "Auf diesem System gibt es nur einen Spieler am Gerät – dein Freund kann zuschauen."
	if emu_id in AUTO:
		return "Spieler 2 nimmt der Emulator von selbst."
	if emu_id in ["pcsx2", "duckstation", "dolphin"] or YUZU_LIKE.has(emu_id):
		return "Uzai belegt Spieler 2 für die Sitzung und stellt danach alles zurück."
	return "Spieler 2 im Emulator einmal selbst auf den zweiten Controller legen."


## Rein: welcher Emulator das ist – nach Kennung, sonst nach Dateiname (eigene Einträge).
static func kind_of(emu_id: String, exe: String) -> String:
	var id := emu_id.to_lower()
	if id in ["pcsx2", "duckstation", "dolphin"] or YUZU_LIKE.has(id) or id in AUTO:
		return id
	var f := exe.get_file().to_lower()
	for k in ["pcsx2", "duckstation", "dolphin", "eden", "citron", "sudachi", "yuzu", "retroarch"]:
		if f.begins_with(k):
			return k
	return id


# --- Ausführen ---------------------------------------------------------------------------------

## Vor dem Remote-Play-Start. next_xinput/next_sdl: Nummer, die der Controller deines Freundes
## bekommt (so viele Controller stecken gerade). Rückgabe: { done: [Dateien], note }.
static func prepare(emu: String, exe: String, system: String, next_xinput: int, next_sdl: int) -> Dictionary:
	restore_all()
	var emu_id := kind_of(emu, exe)
	if system in SOLO_SYSTEMS or emu_id in AUTO:
		return { "done": [], "note": "" }
	var dir := exe.get_base_dir()
	var c := candidates(emu_id, dir, _docs(), _env("APPDATA"), _env("LOCALAPPDATA"), is_portable(emu_id, dir))
	if c.is_empty():
		return { "done": [], "note": "" }
	var jobs: Array = []   # [Datei, Callable(text) -> Dictionary]
	match emu_id:
		"pcsx2":
			jobs.append([newest(c.ini), func(t: String) -> Dictionary: return plan_ps(t, "DualShock2", next_sdl)])
		"duckstation":
			jobs.append([newest(c.ini), func(t: String) -> Dictionary: return plan_ps(t, "AnalogController", next_sdl)])
		"dolphin":
			if system == "wii":
				jobs.append([newest(c.wii), func(t: String) -> Dictionary: return plan_wii(t)])
			else:
				jobs.append([newest(c.gc), func(t: String) -> Dictionary: return plan_gc(t, next_xinput)])
				jobs.append([newest(c.core), func(t: String) -> Dictionary: return plan_dolphin_ini(t)])
		_:
			jobs.append([newest(c.ini), func(t: String) -> Dictionary: return plan_yuzu(t)])
	var done: Array = []
	var notes := PackedStringArray()
	# Was sich eben nicht zurückstellen ließ, bleibt gemerkt.
	var rest: Variant = Config.get_value(RESTORE_KEY, [])
	var saved: Array = (rest as Array).duplicate(true) if rest is Array else []
	for j in jobs:
		var path := str(j[0])
		if path == "":
			notes.append("Einstellungen nicht gefunden – Emulator einmal normal starten")
			continue
		var roh := lesen_treu(path)
		if not bool(roh.ok):
			notes.append(FREMD_KODIERT % path.get_file())
			continue
		var text := str(roh.text)
		var plan: Dictionary = (j[1] as Callable).call(text)
		if str(plan.get("note", "")) != "":
			notes.append(str(plan.note))
		if not plan.has("text") or str(plan.text) == text:
			continue
		# Erst merken, dann schreiben: Stürzt Uzai dazwischen ab, weiß es beim nächsten Start noch, was zurückzustellen
		# ist. Ein gemerkter Plan, der nie geschrieben wurde, ändert beim Zurückstellen nichts (undo_text).
		saved.append({ "file": path, "sections": plan.get("sections", {}), "keys": plan.get("keys", []) })
		Config.set_value(RESTORE_KEY, saved.duplicate(true))
		Config.save_settings()
		if not write_text(path, str(plan.text), bool(roh.bom)):
			notes.append("%s ist schreibgeschützt" % path.get_file())
			saved.pop_back()
			Config.set_value(RESTORE_KEY, saved.duplicate(true))
			Config.save_settings()
			continue
		done.append(path)
	return { "done": done, "note": "; ".join(notes) }


## Dateien, die eine gemerkte Rückstellung anfassen darf (dieselben wie beim Einrichten der Controller).
const RUECK_NAMEN := ["pcsx2.ini", "settings.ini", "gcpadnew.ini", "dolphin.ini", "wiimotenew.ini", "qt-config.ini"]
const RUECK_MAX := 2 * 1024 * 1024


## Die gemerkte Liste liegt in den gemeinsamen Einstellungen und kommt mit jeder Sicherung zurück: Eine fremde
## Sicherung könnte sonst beliebige Textdateien umschreiben lassen, ohne Druck beim Start. Nur bekannte Namen, nur
## unter den Ordnern eines eingerichteten Emulators oder unter Dokumente/AppData, lokal, höchstens 2 MB.
static func rueck_ok(path: String) -> bool:
	var roots: Array = [_docs(), _env("APPDATA"), _env("LOCALAPPDATA")]
	for e in Config.emulators():
		if e is Dictionary and str(e.get("exe", "")) != "":
			roots.append(str(e.exe).get_base_dir())
	return Sicher.datei_unter(path, roots, RUECK_NAMEN, RUECK_MAX)


## Nach dem Spiel (und beim Start von Uzai, falls es vorher abgestürzt ist).
static func restore_all() -> void:
	var list: Variant = Config.get_value(RESTORE_KEY, [])
	if not (list is Array) or (list as Array).is_empty():
		return
	var offen: Array = []
	for e in list:
		if not (e is Dictionary) or not rueck_ok(str(e.get("file", ""))):
			continue
		var path := str(e.file)
		var roh := lesen_treu(path)
		if not bool(roh.ok):
			continue
		var text := str(roh.text)
		var back := undo_text(text, e)
		if back != text and not write_text(path, back, bool(roh.bom)):
			# Gerade gesperrt (der Emulator schließt noch): nicht vergessen, beim nächsten Mal wieder versuchen.
			var nochmal: Dictionary = (e as Dictionary).duplicate(true)
			nochmal["versuche"] = int(nochmal.get("versuche", 0)) + 1 if nochmal.get("versuche") is int or nochmal.get("versuche") is float else 1
			if int(nochmal.versuche) < RESTORE_VERSUCHE:
				offen.append(nochmal)
	Config.set_value(RESTORE_KEY, offen)
	Config.save_settings()
