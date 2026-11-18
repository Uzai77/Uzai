extends RefCounted
## Spiel-Profile (Roadmap 18, 43): was beim Start eines Spiels gilt und nach dem Spiel wieder
## zurückgeht – Tonausgabe, Lautstärke des Spiels, Auflösung und Bildwiederholrate, HDR,
## Controller in Uzais Menü und eine feste Liste eingebauter Aktionen. Lossless Scaling und
## Bildfilter bleiben in ihren bisherigen Feldern am Spiel („lossless“, „filter“) bzw. am System
## (Bildfilter); das Profil zeigt sie nur mit an.
##
## Ein Profil liegt am Spiel (Feld „profile“, Library.USER_FIELDS: bleibt beim Einlesen und in
## jeder Sicherung). Dazu gibt es je System eine Vorlage (Einstellung „profiles.systems.<id>“,
## z. B. für alle PS2-Spiele). Was das Spiel nicht selbst festlegt, kommt aus der Vorlage; KEEP am
## Spiel heißt „hier nichts ändern“, auch wenn die Vorlage etwas will.
##
## Aktionen gibt es nur aus ACTIONS – nie beliebige Programme oder Befehle.
##
## Nicht dabei, mit Grund: eine FPS-Grenze. Windows hat dafür keinen offiziellen Weg für normale
## Programme; die Treiber-Begrenzer von NVIDIA (NVAPI-Profile) und AMD (ADLX) schreiben
## Treibereinstellungen, was Adminrechte bzw. eine große fremde Bibliothek bräuchte, und Lossless
## Scaling hat keine Schnittstelle dafür. Emulatoren begrenzen selbst (eigene Startparameter).
##
## Alles hier ist statisch und ohne Windows testbar (tests/logic_spielprofil.gd); das Anwenden
## steht in profile_run.gd.

const Fremd := preload("res://src/core/fremd.gd")

const KEEP := "keep"
## Schlüssel eines Profils (Reihenfolge = Reihenfolge in Texten).
const KEYS := ["display", "hdr", "audio", "volume", "deadzone", "repeat_delay", "repeat_rate", "actions"]
## Nur in einer Vorlage: am Spiel steht das im bisherigen Feld „lossless“.
const TEMPLATE_KEYS := ["lossless"]
## Controller in Uzais Menü: Einstellung, kleinster und größter Wert, Schritt (wie Einstellungen →
## Controller → Feineinstellung).
const PAD := {
	"deadzone": ["controller.deadzone", 0.2, 0.8, 0.05],
	"repeat_delay": ["controller.repeat_delay", 0.15, 0.6, 0.05],
	"repeat_rate": ["controller.repeat_rate", 0.06, 0.22, 0.02],
}
## Die eingebauten Aktionen: [Kennung, Name, was sie tut, Symbol]. Jede wirkt beim Start und geht
## nach dem Spiel zurück.
const ACTIONS := [
	["mic_mute", "Mikro stumm", "Windows-Mikrofon und, wenn verbunden, das Discord-Mikro aus – nach dem Spiel wieder an.", "mic_off"],
	["music_pause", "Musik anhalten", "Läuft Musik, hält Uzai sie an und spielt sie nach dem Spiel weiter.", "music"],
	["quiet", "Pop-ups ruhig", "Keine Nachrichten und Hinweise über dem Spiel; sie warten in den Mitteilungen.", "bell"],
	["discord_dnd", "Discord: Bitte nicht stören", "Dein Discord-Status für die Spieldauer, danach wieder wie vorher.", "discord"],
]
const VOLUME_STEP := 10
const SOURCE_NAMES := { "steam": "Steam", "epic": "Epic", "ea": "EA", "pc": "PC", "gog": "GOG", "ubisoft": "Ubisoft",
	"battlenet": "Battle.net", "xboxpc": "Xbox", "amazon": "Amazon", "itch": "itch", "riot": "Riot" }

static var _device := RegEx.create_from_string("^\\\\\\\\\\.\\\\DISPLAY[0-9]{1,2}\\z")
static var _audio_id := RegEx.create_from_string("^\\{[0-9.]{1,40}\\}\\.\\{[0-9a-fA-F-]{36}\\}\\z")


## Nur „\\.\DISPLAY1“ … „\\.\DISPLAY99“ (wie der Helfer).
static func valid_device(x: Variant) -> bool:
	return x is String and _device.search(x) != null


static func action_ids() -> Array:
	return ACTIONS.map(func(a: Array) -> String: return str(a[0]))


## Ein Profil auf Bekanntes beschränken (aus library.json oder den Einstellungen – könnte von Hand
## verändert sein). template: Vorlage (kennt „lossless“, kein KEEP).
static func clean(raw: Variant, template := false) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	for k in KEYS + (TEMPLATE_KEYS if template else []):
		if not d.has(k):
			continue
		var v: Variant = d[k]
		if not template and str(v) == KEEP and k != "actions":
			out[k] = KEEP
			continue
		var c: Variant = clean_value(k, v)
		if c != null:
			out[k] = c
	return out


## Ein einzelner Wert, geprüft; null = unbrauchbar.
static func clean_value(k: String, v: Variant) -> Variant:
	match k:
		"display":
			if not (v is Dictionary):
				return null
			var w := int(v.get("w", 0))
			var h := int(v.get("h", 0))
			var hz := int(v.get("hz", 0))
			if w < 640 or w > 16384 or h < 480 or h > 16384 or hz < 24 or hz > 1000:
				return null
			return { "w": w, "h": h, "hz": hz }
		"hdr", "lossless":
			return str(v) if str(v) in ["an", "aus"] else null
		"audio":
			if not (v is Dictionary) or _audio_id.search(str(v.get("id", ""))) == null:
				return null
			var name := str(v.get("name", "")).strip_edges().left(80)
			return { "id": str(v.id), "name": name if name != "" else "Audiogerät" }
		"volume":
			if not (v is int or v is float):
				return null
			return clampi(snappedi(int(v), VOLUME_STEP), 0, 100)
		"actions":
			if not (v is Array):
				return null
			var ids := action_ids()
			return ids.filter(func(id: String) -> bool: return (v as Array).has(id))
	if PAD.has(k):
		if not (v is int or v is float):
			return null
		var p: Array = PAD[k]
		return clampf(snappedf(float(v), float(p[3])), float(p[1]), float(p[2]))
	return null


## Kennung der Vorlage für ein Spiel: sein System (ps2, snes …), bei PC-Spielen der Laden.
static func template_id(g: Dictionary) -> String:
	var sys := str(g.get("system", ""))
	return sys if sys != "" else str(g.get("source", ""))


## „PS2“, „Steam“ … (für „Vorlage für alle PS2-Spiele“).
static func template_name(id: String, sys: Dictionary) -> String:
	var n := str(sys.get("short", sys.get("name", "")))
	if n == "":
		n = str(SOURCE_NAMES.get(id, id.to_upper()))
	return n


## Was gilt: Vorlage, darüber das Spiel; KEEP fällt weg. Lossless kommt nur aus der Vorlage (das
## Spiel hat sein eigenes Feld, das lossless.gd vorher fragt).
static func effective(own: Dictionary, tpl: Dictionary) -> Dictionary:
	var out := {}
	for k in KEYS:
		var v: Variant = own.get(k, tpl.get(k))
		if v == null or str(v) == KEEP:
			continue
		if k == "actions" and (v as Array).is_empty():
			continue
		out[k] = v
	if tpl.has("lossless"):
		out["lossless"] = tpl.lossless
	return out


## Profil des Spiels selbst (ohne Vorlage).
static func own_of(g: Dictionary) -> Dictionary:
	return clean(g.get("profile", {}))


## Ändert einen Schlüssel eines Profils und gibt das neue zurück (null/"" = Schlüssel weg).
static func with_value(p: Dictionary, k: String, v: Variant, template := false) -> Dictionary:
	var out := p.duplicate(true)
	if v == null or (v is String and v == ""):
		out.erase(k)
	elif not template and str(v) == KEEP and k != "actions":
		out[k] = KEEP
	else:
		var c: Variant = clean_value(k, v)
		if c == null:
			return out
		out[k] = c
	return out


# --- Texte ---------------------------------------------------------------------------------

static func mode_text(m: Dictionary) -> String:
	return "%d × %d · %d Hz" % [int(m.get("w", 0)), int(m.get("h", 0)), int(m.get("hz", 0))]


static func volume_text(v: int) -> String:
	return "%d %%" % v


static func pad_text(k: String, v: float) -> String:
	if k == "deadzone":
		return ("%.2f" % v).replace(".", ",")
	return "%d ms" % roundi(v * 1000.0)


static func action_name(id: String) -> String:
	for a in ACTIONS:
		if str(a[0]) == id:
			return str(a[1])
	return id


## Wert eines Schlüssels als kurzer Text (für Zeilen und die Zusammenfassung).
static func value_text(k: String, v: Variant) -> String:
	if v == null:
		return ""
	if str(v) == KEEP:
		return TranslationServer.translate("Nicht ändern")
	match k:
		"display": return mode_text(v)
		"hdr": return TranslationServer.translate("HDR an") if str(v) == "an" else TranslationServer.translate("HDR aus")
		"lossless": return TranslationServer.translate("Lossless an") if str(v) == "an" else TranslationServer.translate("Lossless aus")
		"audio": return str((v as Dictionary).get("name", ""))
		"volume": return volume_text(int(v))
		"actions":
			return ", ".join(PackedStringArray((v as Array).map(func(id: Variant) -> String: return TranslationServer.translate(action_name(str(id))))))
	if PAD.has(k):
		return pad_text(k, float(v))
	return str(v)


## Kurz, was ein Profil tut: „1920 × 1080 · 60 Hz, HDR an, Fernseher, 2 weitere“. "" = nichts.
static func summary(p: Dictionary, max_items := 3) -> String:
	var parts := PackedStringArray()
	var pad := 0
	for k in KEYS + TEMPLATE_KEYS:
		if not p.has(k) or str(p[k]) == KEEP:
			continue
		if PAD.has(k):
			pad += 1
			if pad > 1:
				continue
			parts.append(TranslationServer.translate("Controller"))
			continue
		if k == "actions" and (p[k] as Array).is_empty():
			continue
		if k == "volume":
			parts.append(TranslationServer.translate("Lautstärke %d %%") % int(p[k]))
			continue
		parts.append(value_text(k, p[k]))
	if parts.size() > max_items:
		var rest := parts.size() - max_items
		parts = parts.slice(0, max_items)
		parts.append(TranslationServer.translate("1 weitere") if rest == 1 else TranslationServer.translate("%d weitere") % rest)
	return ", ".join(parts)


# --- Antworten des Helfers -------------------------------------------------------------------

## Antwort von „display-modes“: { device, w, h, hz, hdr, modes: [{ w, h, hz }] } – Modi absteigend
## (erst Bildpunkte, dann Hz), ohne doppelte, höchstens max_n. {} = nichts Brauchbares.
static func parse_modes(r: Dictionary, max_n := 60) -> Dictionary:
	var d := _json(r)
	var dev := str(d.get("device", ""))
	if not valid_device(dev):
		return {}
	var seen := {}
	var modes: Array = []
	for m in d.get("modes", []):
		var c: Variant = clean_value("display", m)
		if c == null:
			continue
		var key := mode_text(c)
		if seen.has(key):
			continue
		seen[key] = true
		modes.append(c)
	modes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.w) * int(a.h)
		var pb := int(b.w) * int(b.h)
		if pa != pb:
			return pa > pb
		if int(a.w) != int(b.w):
			return int(a.w) > int(b.w)
		return int(a.hz) > int(b.hz))
	var hdr := str(d.get("hdr", ""))
	return { "device": dev, "w": int(d.get("w", 0)), "h": int(d.get("h", 0)), "hz": int(d.get("hz", 0)),
		"hdr": hdr if hdr in ["an", "moeglich", "nein"] else "", "modes": modes.slice(0, max_n) }


## Antworten mit { json } (display-set, display-reset, display-hdr): das Innere oder {}.
static func _json(r: Dictionary) -> Dictionary:
	var res: Variant = r.get("result")
	if not bool(r.get("ok", false)) or not (res is Dictionary):
		return {}
	var parsed: Variant = Fremd.json_roh(str((res as Dictionary).get("json", "")))
	return parsed if parsed is Dictionary else {}


static func reply(r: Dictionary) -> Dictionary:
	return _json(r)


# --- Zurückstellen ---------------------------------------------------------------------------

## Tonausgabe nach dem Spiel: zurück auf before, aber nur, wenn noch das Gerät des Profils gilt
## (hat jemand währenddessen selbst umgestellt, bleibt seine Wahl). "" = nichts tun.
static func audio_back(now_id: String, set_id: String, before_id: String, known: Array) -> String:
	if before_id == "" or before_id == set_id or now_id != set_id or not known.has(before_id):
		return ""
	return before_id



# --- Vorlagen je System --------------------------------------------------------------------

const TEMPLATES_KEY := "profiles.systems"


static func template_for(g: Dictionary) -> Dictionary:
	return template(template_id(g))


static func template(id: String) -> Dictionary:
	var all: Variant = Config.get_value(TEMPLATES_KEY, {})
	return clean((all as Dictionary).get(id, {}), true) if all is Dictionary and id != "" else {}


static func set_template(id: String, p: Dictionary) -> void:
	if id == "":
		return
	var all: Variant = Config.get_value(TEMPLATES_KEY, {})
	var next: Dictionary = (all as Dictionary).duplicate(true) if all is Dictionary else {}
	var c := clean(p, true)
	if c.is_empty():
		next.erase(id)
	else:
		next[id] = c
	Config.set_value(TEMPLATES_KEY, next)


## Gemerkter Stand aus profile/zurueck.json (profile_run.gd), streng geprüft: nur bekannte Teile,
## Gerät „\\.\DISPLAYn“, Audio-Kennungen wie audio-list sie liefert.
static func clean_pending(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	var d: Dictionary = v
	if valid_device(d.get("display", "")):
		out["display"] = str(d.display)
	if d.get("hdr") is Dictionary and valid_device(d.hdr.get("device", "")) and str(d.hdr.get("before", "")) in ["an", "moeglich"]:
		out["hdr"] = { "device": str(d.hdr.device), "before": str(d.hdr.before), "set": "aus" if str(d.hdr.before) == "an" else "an" }
	if d.get("audio") is Dictionary and _audio_id.search(str(d.audio.get("before", ""))) != null and _audio_id.search(str(d.audio.get("set", ""))) != null:
		out["audio"] = { "before": str(d.audio.before), "set": str(d.audio.set) }
	if d.get("mic") is bool and d.mic:
		out["mic"] = true
	if str(d.get("discord", "")) in ["online", "idle"]:
		out["discord"] = str(d.discord)
	return out


## „Bildschirm, HDR, Tonausgabe“ – was nach einem Absturz zurückgestellt wurde.
static func restored_text(p: Dictionary) -> String:
	var names := { "display": "Bildschirm", "hdr": "HDR", "audio": "Tonausgabe", "mic": "Mikrofon", "discord": "Discord-Status" }
	var parts := PackedStringArray()
	for k in names:
		if p.has(k):
			parts.append(TranslationServer.translate(str(names[k])))
	return ", ".join(parts)
