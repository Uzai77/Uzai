extends RefCounted
## Kacheln im Schnellmenü selbst wählen und ordnen (Guide-Taste halten, guide_quick.gd): welche es
## gibt, die gespeicherte Auswahl (system.quick_tiles) und die Schritte im Bearbeiten-Modus –
## verschieben, ausblenden, hinzufügen. Ohne Fenster testbar (tests/logic_schnellmenu.gd).
## Leer gespeichert heißt: die Standard-Auswahl, genau wie vor dem Anpassen.

## Jede Kachel: [Kennung, Name, Symbol, wann sie da ist ("" = immer)]. In dieser Reihenfolge
## stehen sie unter „Kachel hinzufügen“.
const KACHELN := [
	["shot", "Bildschirmfoto", "camera", "Spiel, Video"],
	["clip", "Clip speichern", "spark", "Im Spiel"],
	["aufnahme", "Aufnehmen", "record", "Im Spiel"],
	["mic", "Mikro", "mic", "Mit Mikro"],
	["ton", "Lautstärke", "volume", "Unter Windows"],
	["musik", "Musik", "play", "Mit Musik"],
	["weiter", "Nächster Titel", "next", "Mit Musik"],
	["leistung", "Leistung", "speed", "Mit Akku"],
	["pip", "Bild verschieben", "move", "Bild in Bild"],
	["freunde", "Freunde", "friends", ""],
	["pads", "Controller", "controller", "Mit Controller"],
	["mitteilungen", "Mitteilungen", "bell", ""],
	["aufnahmen", "Aufnahmen", "image", ""],
	["zimmer", "Zimmer", "home", "Ohne Video"],
	["einstellungen", "Einstellungen", "settings", "Nicht im Spiel"],
	["rest", "Ruhemodus", "moon", ""],
	["schlaf", "Schlaf-Timer", "clock", ""],
	["ruhe", "Nicht stören", "bell", ""],
	["hoeren", "Nur hören", "headset", "Musik, ohne Spiel"],
	["beenden", "Beenden", "close", ""],
	["guide", "Guide", "grid", ""],
]

## Die Auswahl vor dem Anpassen – so sieht das Schnellmenü aus, bis jemand es ändert.
const STANDARD := ["shot", "clip", "mic", "leistung", "pip", "rest", "beenden", "guide"]

## Höchstens so viele Kacheln: Die Leiste bleibt schmal genug für 1080p und 4K (je TILE_W).
const MAX := 8

## Fest dabei: ohne sie kommt man nicht mehr in den Guide.
const FEST := "guide"

## Frühere Kennungen der drei Beenden-Kacheln: heute eine („beenden“), die Lage entscheidet.
const ALT := { "quit": "beenden", "video_stop": "beenden", "power": "beenden" }

## So viele Einträge eines gespeicherten Werts werden höchstens angesehen.
const ROH_MAX := 64


static func bekannt(id: String) -> bool:
	return KACHELN.any(func(k): return str(k[0]) == id)


static func _eintrag(id: String) -> Array:
	for k in KACHELN:
		if str(k[0]) == id:
			return k
	return []


static func name_of(id: String) -> String:
	var k := _eintrag(id)
	return str(k[1]) if not k.is_empty() else id


static func icon_of(id: String) -> String:
	var k := _eintrag(id)
	return str(k[2]) if not k.is_empty() else "grid"


## Kurzer Hinweis, wann die Kachel im Schnellmenü steht („Im Spiel“); "" = immer.
static func wann(id: String) -> String:
	var k := _eintrag(id)
	return str(k[3]) if not k.is_empty() else ""


## Gespeicherten Wert prüfen: nur bekannte Kennungen (Texte), jede einmal, höchstens MAX, der
## Guide immer dabei. Kein Array, leer oder nichts Brauchbares: die Standard-Auswahl.
static func pruefen(v: Variant) -> Array:
	if not (v is Array) or (v as Array).is_empty():
		return STANDARD.duplicate()
	var out: Array = []
	var n := 0
	for x in v:
		n += 1
		if n > ROH_MAX:
			break
		if not (x is String or x is StringName):
			continue
		var id := str(ALT.get(str(x), str(x)))
		if bekannt(id) and not out.has(id):
			out.append(id)
	if out.is_empty():
		return STANDARD.duplicate()
	if not out.has(FEST):
		out = out.filter(func(i): return i != FEST)
		out.resize(mini(out.size(), MAX - 1))
		out.append(FEST)
	elif out.size() > MAX:
		var ohne := out.filter(func(i): return i != FEST)
		ohne.resize(MAX - 1)
		var stelle := mini(out.find(FEST), MAX - 1)
		ohne.insert(stelle, FEST)
		out = ohne
	return out


## Die Auswahl aus den Einstellungen (geprüft).
static func auswahl() -> Array:
	return pruefen(Config.get_value("system.quick_tiles", []))


## Speichern: wie der Standard → leer (folgt späteren Standards), sonst die Liste.
static func speichern(liste: Array) -> void:
	var p := pruefen(liste)
	Config.set_value("system.quick_tiles", [] if p == STANDARD else p)


## Steht die Kachel id in dieser Lage im Schnellmenü? ctx wie GuideQuick.context: shot, game,
## video, voice, mic, leistung, pip, musik, ton, aufnahme, pads, zimmer, hoeren (Musik oder Ton
## eines Videos läuft im Hintergrund).
static func da(id: String, ctx: Dictionary) -> bool:
	match id:
		"shot":
			return bool(ctx.get("shot", false))
		"clip":
			return bool(ctx.get("shot", false)) and bool(ctx.get("game", false))
		"aufnahme":
			return bool(ctx.get("shot", false)) and bool(ctx.get("game", false)) and bool(ctx.get("aufnahme", false))
		"mic":
			return bool(ctx.get("voice", false)) or bool(ctx.get("mic", false))
		"ton":
			return bool(ctx.get("ton", false))
		"musik", "weiter":
			return bool(ctx.get("musik", false))
		"leistung":
			return bool(ctx.get("leistung", false))
		"pip":
			return bool(ctx.get("pip", false))
		"pads":
			return bool(ctx.get("pads", false))
		"zimmer":
			return bool(ctx.get("zimmer", false))
		"einstellungen":
			return not bool(ctx.get("game", false)) and not bool(ctx.get("video", false))
		"hoeren":
			return bool(ctx.get("hoeren", false)) and not bool(ctx.get("game", false))
	return bekannt(id)


## „Beenden“ in dieser Lage: Spiel beenden, Video beenden oder Ausschalten.
static func beenden_id(ctx: Dictionary) -> String:
	if bool(ctx.get("game", false)):
		return "quit"
	if bool(ctx.get("video", false)):
		return "video_stop"
	return "power"


## Die Kacheln, die gerade zu sehen sind, in der gewählten Reihenfolge (Beenden schon aufgelöst).
static func sichtbar(liste: Array, ctx: Dictionary) -> Array:
	var out: Array = []
	for id in liste:
		if da(str(id), ctx):
			out.append(beenden_id(ctx) if str(id) == "beenden" else str(id))
	return out


# --- Bearbeiten: Stand { liste, aus } – aus sind die ausgeblendeten (fallen beim Speichern weg) ---

static func stand(liste: Array) -> Dictionary:
	return { "liste": pruefen(liste), "aus": [] }


## Was gespeichert wird: die Liste ohne das Ausgeblendete.
static func ergebnis(s: Dictionary) -> Array:
	var aus: Array = s.get("aus", [])
	return (s.get("liste", []) as Array).filter(func(i): return not aus.has(i))


## Wie viele Kacheln noch dazu passen.
static func frei(s: Dictionary) -> int:
	return MAX - ergebnis(s).size()


## Kachel an Stelle i um d Plätze verschieben (am Rand bleibt sie stehen). Neue Liste.
static func verschieben(liste: Array, i: int, d: int) -> Array:
	var out := liste.duplicate()
	if i < 0 or i >= out.size():
		return out
	var j := clampi(i + d, 0, out.size() - 1)
	if j == i:
		return out
	var id: Variant = out[i]
	out.remove_at(i)
	out.insert(j, id)
	return out


## Aus- bzw. wieder einblenden. Der Guide bleibt immer; Einblenden nur, solange Platz ist.
## Neuer Stand, unverändert, wenn es nicht geht.
static func umschalten(s: Dictionary, id: String) -> Dictionary:
	var out := s.duplicate(true)
	var aus: Array = out.aus
	if id == FEST or not (out.liste as Array).has(id):
		return out
	if aus.has(id):
		if frei(s) <= 0:
			return out
		aus.erase(id)
	else:
		aus.append(id)
	return out


## Was sich noch hinzufügen lässt: alle bekannten Kacheln, die nicht in der Liste stehen.
static func verfuegbar(s: Dictionary) -> Array:
	var liste: Array = s.get("liste", [])
	var out: Array = []
	for k in KACHELN:
		if not liste.has(str(k[0])):
			out.append(str(k[0]))
	return out


## Kachel id hinzufügen: vor den Guide, wenn er am Ende steht, sonst ans Ende. Ist die Liste mit
## Ausgeblendetem voll, weicht zuerst eine ausgeblendete. Unverändert, wenn es nicht geht.
static func hinzufuegen(s: Dictionary, id: String) -> Dictionary:
	var out := s.duplicate(true)
	var liste: Array = out.liste
	var aus: Array = out.aus
	if not bekannt(id) or liste.has(id) or frei(s) <= 0:
		return out
	if liste.size() >= MAX and not aus.is_empty():
		liste.erase(aus[0])
		aus.remove_at(0)
	if liste.size() >= MAX:
		return out
	var stelle := liste.size() - 1 if not liste.is_empty() and str(liste.back()) == FEST else liste.size()
	liste.insert(stelle, id)
	return out
