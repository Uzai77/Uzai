extends RefCounted
## Eigene Apps wie auf einer Konsole (docs/PLAN_APPS.md): Store-Apps und Programme liegen randlos auf
## dem ganzen Bildschirm, dahinter steht Uzai als Kulisse (nie Desktop oder Taskleiste), und der
## Controller wird zu Tasten – nur für genau dieses App-Fenster (Helfer „app-vollbild“ und „app-pad“,
## docs/SECURITY.md „Apps“ und „Eingaben an Fenster“).
##   Vollbild   erst das eigene Vollbild der App (F11 bei Web-Apps wie Netflix, Disney+), nur wenn sie
##              vorn ist; deckt sie den Bildschirm dann noch nicht, nimmt der Helfer ihrem Fenster
##              Titelleiste und Rahmen und legt es über den ganzen Bildschirm (über die Taskleiste).
##              „Zurück zu Uzai“ und Schließen stellen das Fenster wieder her, wie es war.
##   Controller Steuerkreuz und linker Stick sind die Pfeiltasten, A/B/X/Y/LB/RB die Tasten des Profils,
##              der rechte Stick bewegt den Mauszeiger nur im App-Fenster (RT klickt) – der Rückfall für
##              Seiten ohne Tastatur-Bedienung. Guide (und View + Start) bleiben bei Uzai, die Maus mit
##              dem Controller (Guide) hat Vorrang.
##   Textfeld   hat in der App ein Textfeld den Fokus, öffnet Y Uzais Bildschirmtastatur (gleich nach A
##              bzw. einem Klick geht sie von selbst auf, sonst steht kurz „Y Tastatur“); der Text geht
##              danach als Zeichen nur an genau dieses Fenster (Helfer „app-text“, src/ui/app_tastatur.gd).
##   Rand       im Vollbild bleibt der Mauszeiger knapp unter dem oberen Rand, solange die App vorn liegt
##              (dort blendet Windows bzw. der Browser sonst Titelleiste und „X“ ein).
##   Leitfaden  bei den ersten Starts je App steht kurz der Controller mit ihrer Belegung (app_leitfaden.gd);
##              später über den Guide („Steuerung“).
## Profile je bekannter App, sonst STANDARD. Apps mit eigener Controller-Bedienung (Kodi, Plex HTPC,
## Moonlight, Steam Link) übersetzt Uzai von sich aus nicht; je App umschaltbar im Guide (apps.steuerung).
## Ohne Windows prüfbar: tests/logic_app_steuerung.gd.

const AppsExtern := preload("res://src/core/apps_extern.gd")

const KEY := "apps.steuerung"   ## { App-Kennung: an/aus } – nur, wo du es selbst umgestellt hast
const MAX := 40
## Tasten, die Uzai an ein App-Fenster schickt – dieselbe Liste prüft der Helfer (Test-KeyCombo „app“).
const ERLAUBT := ["F11", "ESC", "UP", "DOWN", "LEFT", "RIGHT", "ENTER", "SPACE", "BACKSPACE", "TAB", "SHIFT+TAB"]
const KNOEPFE := ["a", "b", "x", "y", "lb", "rb"]
const STANDARD := { "a": "ENTER", "b": "ESC", "x": "SPACE", "y": "F11", "lb": "SHIFT+TAB", "rb": "TAB" }
const HINWEIS_MS := 2000        ## so lange steht die Tastenzeile unten, wenn die App vorn ist
const LEITFADEN_KEY := "apps.leitfaden"
const LEITFADEN_MAL := 3        ## so oft steht der Leitfaden beim Start einer App von selbst
const LEITFADEN_MS := 4200      ## so lange (oder bis zum nächsten Druck)
const TEXT_MAX := 500           ## so viele Zeichen gehen auf einmal an ein Textfeld (wie UzPad.AppTextMax)
## Was eine Taste in der App tut – kurze Beschriftung am Controller (Leitfaden).
const NAMEN := { "ENTER": "Auswählen", "ESC": "Zurück", "BACKSPACE": "Zurück", "SPACE": "Pause", "F11": "Vollbild",
	"TAB": "Nächstes", "SHIFT+TAB": "Vorheriges" }
const TASTE_WARTEN_MS := 900    ## nach F11: so lange darf die App für ihr Vollbild brauchen

## Bekannte Apps (Suchwörter im Namen, in der App-Kennung bzw. im Programmnamen; das erste passende
## gilt). b: Zurück je nach App – Web-Apps kennen Esc, Plex und Kodi Backspace. vollbild: die Taste für
## das eigene Vollbild der App ("" = gleich randlos). eigen: kann selbst Controller.
const PROFILE := [
	{ "id": "netflix", "name": "Netflix", "match": ["netflix"], "vollbild": "F11" },
	{ "id": "disney", "name": "Disney+", "match": ["disney"], "vollbild": "F11" },
	{ "id": "prime", "name": "Prime Video", "match": ["primevideo", "prime video", "amazonvideo"], "tasten": { "b": "BACKSPACE" }, "vollbild": "" },
	{ "id": "crunchyroll", "name": "Crunchyroll", "match": ["crunchyroll"], "vollbild": "F11" },
	{ "id": "youtube", "name": "YouTube", "match": ["youtube"], "vollbild": "F11" },
	{ "id": "plexhtpc", "name": "Plex HTPC", "match": ["plex htpc", "plexhtpc"], "tasten": { "b": "BACKSPACE" }, "vollbild": "", "eigen": true },
	{ "id": "plex", "name": "Plex", "match": ["plex"], "tasten": { "b": "BACKSPACE" }, "vollbild": "" },
	{ "id": "kodi", "name": "Kodi", "match": ["kodi"], "tasten": { "b": "BACKSPACE" }, "vollbild": "", "eigen": true },
	{ "id": "moonlight", "name": "Moonlight", "match": ["moonlight"], "vollbild": "", "eigen": true },
	{ "id": "steamlink", "name": "Steam Link", "match": ["steamlink", "steam link"], "vollbild": "", "eigen": true },
]


static func taste_ok(t: Variant) -> bool:
	return t is String and (t as String) in ERLAUBT


## Belegung vollständig und nur aus der Erlaubnisliste ("" = Knopf tut nichts)?
static func tasten_ok(m: Variant) -> bool:
	if not (m is Dictionary) or (m as Dictionary).size() != KNOEPFE.size():
		return false
	for k in KNOEPFE:
		var v: Variant = (m as Dictionary).get(k)
		if not (v is String) or (v != "" and not taste_ok(v)):
			return false
	return true


## Wonach gesucht wird: Name, Paketname der Store-App bzw. Dateiname des Programms (klein).
static func _heu(e: Dictionary) -> String:
	var s := str(e.get("name", ""))
	if str(e.get("kind", "")) == "store":
		s += " " + str(AppsExtern.split_aumid(e.get("aumid", "")).get("name", ""))
	else:
		s += " " + AppsExtern.norm_path(e.get("path", "")).get_file().get_basename()
	return s.to_lower()


## Profil einer eigenen App: { id, name, tasten, vollbild, eigen }. Unbekannte: STANDARD ("standard").
static func profil(e: Dictionary) -> Dictionary:
	var heu := _heu(e)
	for p in PROFILE:
		for w in p.match:
			if heu.contains(str(w)):
				var t := STANDARD.duplicate()
				t.merge(p.get("tasten", {}), true)
				return { "id": str(p.id), "name": str(p.name), "tasten": t, "vollbild": str(p.get("vollbild", "")), "eigen": bool(p.get("eigen", false)) }
	return { "id": "standard", "name": "", "tasten": STANDARD.duplicate(), "vollbild": "", "eigen": false }


static func _gespeichert() -> Dictionary:
	var v: Variant = Config.get_value(KEY, {})
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		if out.size() >= MAX:
			break
		if AppsExtern.is_ext_id(k) and v[k] is bool:
			out[k] = v[k]
	return out


## Übersetzt Uzai den Controller für diese App? Was du umgestellt hast, sonst: nicht bei Apps, die
## selbst Controller können.
static func an(e: Dictionary) -> bool:
	var g := _gespeichert()
	var id := str(e.get("id", ""))
	if g.has(id):
		return bool(g[id])
	return not bool(profil(e).eigen)


static func setzen(e: Dictionary, on: bool) -> void:
	var id := str(e.get("id", ""))
	if not AppsExtern.is_ext_id(id):
		return
	var g := _gespeichert()
	if on == not bool(profil(e).eigen):
		g.erase(id)
	else:
		g[id] = on
	Config.set_value(KEY, g)


## Wer das Fenster ist (der Helfer prüft es selbst: Kennung bzw. Programmpfad).
static func _wer(e: Dictionary, hwnd: int) -> Dictionary:
	if hwnd <= 0 or not AppsExtern.entry_ok(e):
		return {}
	var d := { "hwnd": hwnd, "kind": str(e.kind) }
	if e.kind == "store":
		d["aumid"] = str(e.aumid)
	else:
		d["path"] = AppsExtern.norm_path(e.path)
	return d


## Auftrag „app-vollbild“: an (mit der Vollbild-Taste der App, "" = gleich randlos) bzw. zurück.
## {} = nichts zu tun.
static func vollbild_auftrag(e: Dictionary, hwnd: int, on: bool, taste := "") -> Dictionary:
	var d := _wer(e, hwnd)
	if d.is_empty():
		return {}
	d["an"] = on
	d["taste"] = taste if on and taste_ok(taste) else ""
	return d


## Auftrag „app-pad“ (an): Fenster und die Tasten des Profils. {} = nichts einzuschalten.
static func pad_auftrag(e: Dictionary, hwnd: int) -> Dictionary:
	var d := _wer(e, hwnd)
	var t: Dictionary = profil(e).tasten if not d.is_empty() else {}
	if d.is_empty() or not tasten_ok(t):
		return {}
	d["an"] = true
	d["tasten"] = t
	return d


## Tastenzeile, die kurz unten steht, wenn die App vorn ist (B zuletzt vor Guide, docs/DESIGN.md).
static func hinweis(e: Dictionary) -> Array:
	if an(e):
		return [["b", "Zurück"], ["guide", "Uzai"]]
	return [["guide", "Uzai"]]


## Tastenzeile, wenn in der App ein Textfeld den Fokus bekommt (ohne eigenen Druck).
static func hinweis_textfeld() -> Array:
	return [["y", "Tastatur"], ["guide", "Uzai"]]


# --- Text aus Uzais Tastatur ---------------------------------------------------------------------

## Text, der an ein Textfeld der App gehen darf (wie UzPad.AppTextOk im Helfer): 1–500 Zeichen, keine
## Steuerzeichen (auch kein Zeilenumbruch, kein Tab), keine Richtungs- und unsichtbaren Formatzeichen.
static func text_ok(t: Variant) -> bool:
	if not (t is String):
		return false
	var s: String = t
	if s.length() < 1 or s.length() > TEXT_MAX:
		return false
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 32 or (c >= 0x7F and c <= 0x9F) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF or (c >= 0xD800 and c <= 0xDFFF):
			return false
	return true


## Auftrag „app-text“: Fenster und Text. {} = nichts zu senden.
static func text_auftrag(e: Dictionary, hwnd: int, text: String) -> Dictionary:
	var d := _wer(e, hwnd)
	if d.is_empty() or not text_ok(text):
		return {}
	d["text"] = text
	return d


# --- Leitfaden: der Controller mit der Belegung der App ------------------------------------------

## Belegung für den Leitfaden: { knopf: Beschriftung } – nur, was Uzai in dieser App übersetzt (aus: {}).
## Dazu immer Guide (Uzai); mit Übersetzung Steuerkreuz (Bewegen), rechter Stick (Zeiger) und RT (Klicken).
static func belegung(e: Dictionary) -> Dictionary:
	var out := { "guide": "Uzai" }
	if not an(e):
		return out
	var t: Dictionary = profil(e).tasten
	for k in KNOEPFE:
		var taste := str(t.get(k, ""))
		if taste != "" and NAMEN.has(taste):
			out[k] = str(NAMEN[taste])
	out["dpad"] = "Bewegen"
	out["rs"] = "Zeiger"
	out["rt"] = "Klicken"
	return out


static func _leitfaden_zahlen() -> Dictionary:
	var v: Variant = Config.get_value(LEITFADEN_KEY, {})
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		if out.size() >= MAX:
			break
		if AppsExtern.is_ext_id(k) and (v[k] is int or v[k] is float):
			out[k] = clampi(int(v[k]), 0, 99)
	return out


## Steht der Leitfaden beim Start dieser App noch von selbst? (Die ersten LEITFADEN_MAL Male.)
static func leitfaden_faellig(e: Dictionary) -> bool:
	var id := str(e.get("id", ""))
	return AppsExtern.is_ext_id(id) and int(_leitfaden_zahlen().get(id, 0)) < LEITFADEN_MAL


## Der Leitfaden stand einmal (von selbst).
static func leitfaden_gezeigt(e: Dictionary) -> void:
	var id := str(e.get("id", ""))
	if not AppsExtern.is_ext_id(id):
		return
	var z := _leitfaden_zahlen()
	z[id] = mini(int(z.get(id, 0)) + 1, 99)
	Config.set_value(LEITFADEN_KEY, z)


## Welcher Controller gezeichnet wird: Tastensymbole aus den Einstellungen bzw. vom Controller, der
## zuletzt benutzt wurde (auch wenn zuletzt Maus oder Tastatur dran waren). "" = kein Controller da.
static func familie(glyphs_setting: String, pad_set: String, pads_da: bool) -> String:
	if glyphs_setting in ["xbox", "ps", "nintendo"]:
		return glyphs_setting
	if not pads_da:
		return ""
	if pad_set in ["ps", "nintendo"]:
		return pad_set
	return "xbox"
