extends RefCounted
## Steam Deck und Windows-Handhelds (Punkt 64): Erkennung, Oberflächengröße, Tastensymbole der
## eingebauten Controller, Schnellmenü-Taste, Akku des PCs und die Energieprofile als
## Leistungsstufen. Ohne Zustand außer `aktiv` (das erkannte Gerät dieser Sitzung), darum testbar
## (tests/logic_bedienung.gd).
##
## Woher: nur lokale Daten – der Gerätename aus dem BIOS (Godot: OS.get_model_name(), der Helfer
## mit „geraet-info“ zusätzlich Hersteller, Familie und Version), Diagonale und Anschluss des
## Bildschirms (display-info, display_fit.gd), Auflösung und Touch von Godot. Nichts geht hinaus.

const VALVE := 0x28DE
const ASUS := 0x0B05
const LENOVO := 0x17EF
const MSI := 0x0DB0

## Bekannte Geräte. muster: Teil des Gerätenamens (Produkt, Familie, Version); hersteller: muss
## zusätzlich passen, wo der Name allein zu allgemein ist („Claw“). zoll: Diagonale, wenn der
## Bildschirm keine meldet. vids: Hersteller der eingebauten Controller.
const GERAETE := [
	{ "id": "deck", "name": "Steam Deck", "muster": "(?i)(^|[^a-z])(jupiter|galileo)([^a-z]|$)|steam ?deck", "hersteller": "(?i)valve", "zoll": 7.4,
		"tasten": "deck", "vids": [VALVE] },
	{ "id": "ally", "name": "ROG Ally", "muster": "(?i)rog ally|(^|[^a-z0-9])rc7[12]l", "hersteller": "", "zoll": 7.0, "tasten": "handheld", "vids": [ASUS] },
	{ "id": "legion", "name": "Legion Go", "muster": "(?i)legion go", "hersteller": "", "zoll": 8.8, "tasten": "handheld", "vids": [LENOVO] },
	{ "id": "claw", "name": "MSI Claw", "muster": "(?i)(^|[^a-z])claw([^a-z]|$)", "hersteller": "(?i)micro-star|(^|[^a-z])msi([^a-z]|$)", "zoll": 7.0,
		"tasten": "handheld", "vids": [MSI] },
	{ "id": "handheld", "name": "Handheld", "muster": "(?i)aya ?neo|one ?x ?player|(^|[^a-z])gpd([^a-z]|$)|zotac zone|(^|[^a-z])ayn([^a-z]|$)", "hersteller": "",
		"zoll": 7.0, "tasten": "handheld", "vids": [] },
]
## Ohne Namen gilt ein eingebauter Bildschirm in dieser Größe als Handheld (Laptops fangen bei 10″ an).
const ZOLL := Vector2(5.0, 9.5)
## Oberfläche: bis 8,3″ 150 % (logisch 1280 × 800 bzw. 1280 × 720 – so groß wie geprüft), darüber 140 %.
const SKALA_KLEIN := 1.5
const SKALA_GROSS := 1.4
const ZOLL_GROSS := 8.3

## Sondertasten, die Handhelds ohne Herstellersoftware oft als normale Taste schicken.
const SONDER := [KEY_F13, KEY_F14, KEY_F15, KEY_F16, KEY_F17, KEY_F18, KEY_F19, KEY_F20, KEY_F21,
	KEY_F22, KEY_F23, KEY_F24, KEY_LAUNCH0, KEY_LAUNCH1, KEY_LAUNCH2, KEY_LAUNCH3, KEY_LAUNCH4,
	KEY_LAUNCH5, KEY_LAUNCH6, KEY_LAUNCH7, KEY_LAUNCH8, KEY_LAUNCH9]
## Tasten, die Uzai (oder das Tippen) schon braucht – nie als Schnellmenü-Taste.
const BELEGT := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE,
	KEY_BACKSPACE, KEY_TAB, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END, KEY_DELETE, KEY_INSERT, KEY_MENU,
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK, KEY_PRINT]

## Das Gerät dieser Sitzung ({} = kein Handheld): { id, name, zoll, skala, tasten, grund }.
static var aktiv: Dictionary = {}


# --- Erkennen ---------------------------------------------------------------------------------

## info: { maker, product, family, version, model (Texte), zoll (Diagonale, 0 = unbekannt),
## intern (eingebauter Bildschirm) }. Ergebnis wie `aktiv`, {} wenn es kein Handheld ist.
static func erkennen(info: Dictionary) -> Dictionary:
	var maker := _clean(info.get("maker", ""))
	var namen := PackedStringArray()
	for k in ["product", "family", "version", "model"]:
		var s := _clean(info.get(k, ""))
		if s != "" and not namen.has(s):
			namen.append(s)
	var text := " ".join(namen)
	var zoll := float(info.get("zoll", 0.0))
	for g in GERAETE:
		if RegEx.create_from_string(str(g.muster)).search(text) == null:
			continue
		if str(g.hersteller) != "" and RegEx.create_from_string(str(g.hersteller)).search(maker + " " + text) == null:
			continue
		var z := zoll if zoll > 0.0 else float(g.zoll)
		return { "id": str(g.id), "name": str(g.name), "zoll": z, "skala": skala_fuer(z), "tasten": str(g.tasten), "grund": "name" }
	if bool(info.get("intern", false)) and zoll >= ZOLL.x and zoll <= ZOLL.y:
		return { "id": "handheld", "name": "Handheld", "zoll": zoll, "skala": skala_fuer(zoll), "tasten": "handheld", "grund": "bildschirm" }
	return {}


static func skala_fuer(zoll: float) -> float:
	return SKALA_GROSS if zoll > ZOLL_GROSS else SKALA_KLEIN


## Texte aus dem BIOS sind fremde Daten: kurz, ohne Steuerzeichen; Platzhalter der Hersteller
## („To be filled by O.E.M.“, „Default string“) zählen nicht.
static func _clean(v: Variant) -> String:
	var s := str(v).left(64)
	var out := ""
	for ch in s:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges()
	var low := out.to_lower()
	if low in ["", "default string", "to be filled by o.e.m.", "system product name", "system manufacturer", "genericdevice", "not applicable", "none"]:
		return ""
	return out


## Antwort des Helfers auf „geraet-info“ auf das Nötige beschränken.
static func clean_info(raw: Dictionary) -> Dictionary:
	return { "maker": _clean(raw.get("maker", "")), "product": _clean(raw.get("product", "")),
		"family": _clean(raw.get("family", "")), "version": _clean(raw.get("version", "")) }


## Beim Start: was Uzai schon weiß (gemerkter Bildschirm, Godots Gerätename). Der Helfer ergänzt
## später (display_fit.detect). Setzt `aktiv`.
static func vom_start(seen: Dictionary, model: String) -> Dictionary:
	var info := { "model": model }
	for k in ["maker", "product", "family", "version"]:
		info[k] = seen.get(k, "")
	info["zoll"] = _diag(seen)
	info["intern"] = str(seen.get("tech", "")) == "intern"
	aktiv = erkennen(info)
	return aktiv


static func _diag(seen: Dictionary) -> float:
	var w := float(seen.get("w_cm", 0))
	var h := float(seen.get("h_cm", 0))
	var d := sqrt(w * w + h * h) / 2.54
	return d if d >= 3.0 and d <= 120.0 else 0.0


# --- Tastensymbole ----------------------------------------------------------------------------

## Tastensymbole für diesen Controller auf diesem Gerät: „deck“ bzw. „handheld“ für den
## eingebauten, sonst "" (dann gilt die übliche Erkennung). Unter Windows meldet sich der
## eingebaute Controller meist als XInput-Gerät ohne Hersteller – auf einem Handheld ist das er.
static func tasten_fuer(geraet: Dictionary, pad_name: String, vid: int) -> String:
	if geraet.is_empty():
		return ""
	var n := pad_name.to_lower()
	var vids: Array = []
	for g in GERAETE:
		if str(g.id) == str(geraet.get("id", "")):
			vids = g.vids
	if str(geraet.get("id", "")) == "deck":
		return "deck" if vid == VALVE or n.contains("steam") or n.contains("valve") or n.contains("deck") else ""
	if vid in vids or n.contains("ally") or n.contains("legion") or n.contains("claw"):
		return "handheld"
	if vid <= 0 and (n.contains("xinput") or n.contains("xbox 360") or n == ""):
		return "handheld"
	return ""


# --- Schnellmenü-Taste ------------------------------------------------------------------------

## Darf diese Taste die Schnellmenü-Taste werden? Nur, was Uzai und das Tippen nicht brauchen:
## F-Tasten, Sondertasten oder eine Taste mit Strg/Alt/Windows.
static func taste_frei(kc: int, mods: int) -> bool:
	if kc in BELEGT or kc == KEY_NONE or (kc == KEY_F4 and mods & KEY_MASK_ALT != 0):
		return false
	if kc in SONDER or (kc >= KEY_F1 and kc <= KEY_F12):
		return true
	return mods & (KEY_MASK_CTRL | KEY_MASK_ALT | KEY_MASK_META) != 0


## Knöpfe am Controller, die Uzai nicht belegt (Paddel, Zusatztasten der Handhelds).
static func knopf_frei(b: int) -> bool:
	return b >= JOY_BUTTON_PADDLE1 and b < JOY_BUTTON_MAX and b != JOY_BUTTON_TOUCHPAD


## Gespeicherte Belegung prüfen: { art: "taste"|"knopf", code, mods } oder {}.
static func belegung(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d := v as Dictionary
	var code := int(d.get("code", 0)) if (d.get("code") is int or d.get("code") is float) else 0
	var mods := int(d.get("mods", 0)) if (d.get("mods") is int or d.get("mods") is float) else 0
	mods &= KEY_MASK_CTRL | KEY_MASK_ALT | KEY_MASK_META | KEY_MASK_SHIFT
	match str(d.get("art", "")):
		"taste":
			return { "art": "taste", "code": code, "mods": mods } if taste_frei(code, mods) else {}
		"knopf":
			return { "art": "knopf", "code": code, "mods": 0 } if knopf_frei(code) else {}
	return {}


## Ist dieses Ereignis die Schnellmenü-Taste? Ohne eigene Belegung auf einem Handheld die
## Sondertasten (F13–F24, Start-Tasten).
static func ist_schnelltaste(e: InputEvent, beleg: Dictionary, handheld: bool) -> bool:
	if e is InputEventKey:
		var k := e as InputEventKey
		var kc := int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
		if str(beleg.get("art", "")) == "taste":
			return kc == int(beleg.code) and _mods(k) == int(beleg.mods)
		return beleg.is_empty() and handheld and kc in SONDER
	if e is InputEventJoypadButton:
		return str(beleg.get("art", "")) == "knopf" and (e as InputEventJoypadButton).button_index == int(beleg.code)
	return false


static func _mods(k: InputEventKey) -> int:
	var m := 0
	if k.ctrl_pressed:
		m |= KEY_MASK_CTRL
	if k.alt_pressed:
		m |= KEY_MASK_ALT
	if k.meta_pressed:
		m |= KEY_MASK_META
	if k.shift_pressed:
		m |= KEY_MASK_SHIFT
	return m


## Eine Belegung aus einem gedrückten Ereignis, {} wenn es dafür nicht taugt.
static func belegung_aus(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		var kc := int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
		return belegung({ "art": "taste", "code": kc, "mods": _mods(k) })
	if e is InputEventJoypadButton:
		return belegung({ "art": "knopf", "code": (e as InputEventJoypadButton).button_index })
	return {}


## Name einer Belegung für die Einstellungen („F15“, „Strg + Alt + K“, „Paddel 1“).
static func belegung_text(b: Dictionary) -> String:
	if b.is_empty():
		return "Nicht belegt"
	if str(b.art) == "knopf":
		return preload("res://src/core/pad_check.gd").button_name(int(b.code), "xbox")
	var tt := func(w: String) -> String: return TranslationServer.translate(w)
	return OS.get_keycode_string(int(b.code) | int(b.mods)).replace("Ctrl", tt.call("Strg")).replace("Shift", tt.call("Umschalt")) \
		.replace("Meta", "Windows").replace("+", " + ")


# --- Akku des PCs -----------------------------------------------------------------------------

## Antwort von „pc-akku“ streng geprüft: { ok, akku (hat einen), prozent (-1 unbekannt), laedt,
## netz, sparen, minuten (-1 unbekannt) }.
static func parse_akku(raw: Dictionary) -> Dictionary:
	var out := { "ok": false, "akku": false, "prozent": -1, "laedt": false, "netz": false, "sparen": false, "minuten": -1 }
	if not bool(raw.get("ok", false)):
		return out
	out.ok = true
	out.akku = bool(raw.get("akku", false))
	var p: Variant = raw.get("prozent", -1)
	out.prozent = clampi(int(p), -1, 100) if (p is int or p is float) else -1
	out.laedt = bool(raw.get("laedt", false))
	out.netz = bool(raw.get("netz", false))
	out.sparen = bool(raw.get("sparen", false))
	var m: Variant = raw.get("minuten", -1)
	out.minuten = clampi(int(m), -1, 24 * 60) if (m is int or m is float) else -1
	return out


## Stufe 0…3 wie bei den Controllern (pad_battery.gd), -1 unbekannt.
static func akku_stufe(prozent: int) -> int:
	if prozent < 0:
		return -1
	if prozent <= 10:
		return 0
	return 1 if prozent <= 30 else (2 if prozent <= 70 else 3)


## Text neben dem Symbol oben: „73 %“; die lange Form mit „lädt auf“ bzw. der Restzeit.
static func akku_text(a: Dictionary, lang := false) -> String:
	if not bool(a.get("akku", false)) or int(a.get("prozent", -1)) < 0:
		return ""
	var t := "%d %%" % int(a.prozent)
	if not lang:
		return t
	if bool(a.get("laedt", false)):
		return t + " · " + TranslationServer.translate("lädt auf")
	if int(a.get("minuten", -1)) > 0 and not bool(a.get("netz", false)):
		var m := int(a.minuten)
		return t + " · " + (TranslationServer.translate("noch %d h %02d min") % [m / 60, m % 60] if m >= 60 else TranslationServer.translate("noch %d min") % m)
	return t


# --- Leistung (Energieprofile) ----------------------------------------------------------------

## Reihenfolge der bekannten Profile von sparsam nach stark; eigene Profile von Windows dahinter.
const STUFEN := ["a1841308-3541-4fab-bc81-f71556f20b4a", "381b4222-f694-41f0-9685-ff5bb260df2e",
	"8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", "e9a42b02-d5df-448d-aa00-03f14749eb61"]


## Das nächste Energieprofil (Kachel „Leistung“ im Schnellmenü): reihum, sparsam → stark → sparsam.
## plans: [{ id, name }] wie PerfLive.parse_plans. "" ohne Wahl.
static func naechstes_profil(plans: Array, active: String) -> String:
	if plans.size() < 2:
		return ""
	var ids: Array = plans.map(func(p: Dictionary) -> String: return str(p.get("id", "")))
	ids.sort_custom(_vor)
	var i := ids.find(active)
	return str(ids[(i + 1) % ids.size()]) if i >= 0 else str(ids[0])


static func _vor(a: String, b: String) -> bool:
	var ia := STUFEN.find(a)
	var ib := STUFEN.find(b)
	if ia < 0 and ib < 0:
		return a < b
	if ia < 0 or ib < 0:
		return ib < 0
	return ia < ib
