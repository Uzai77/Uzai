extends RefCounted
## Zimmer online – Einladungen, die über den Chat kommen (Steam-Freund, Discord-Freund). Entscheidet nur,
## ob Uzai „Zimmer betreten“ anbietet; betreten wird nie von selbst. Reine Logik ohne Netz
## (tests/logic_freundestest.gd).
##
## Regeln (docs/ZIMMER_SICHERHEIT.md, Abschnitt 10):
##   - Nur Nachrichten von Freunden aus Uzais eigener Freundesliste; alles andere wird übergangen.
##   - Nur, wenn Zimmer online eingeschaltet ist – sonst liest Uzai Nachrichten gar nicht darauf.
##   - Der Code wird nur gelesen und geprüft (Einladung.code_im_text): Länge, Zeichen, Prüfzeichen, Ablauf.
##   - Derselbe Code wird nur einmal angeboten (Wiederholung); gemerkt wird nur ein Fingerabdruck, nie der Code.
##   - Flut: höchstens ein Angebot je Freund in JE_FREUND_S und JE_10_MIN insgesamt in zehn Minuten.

const Einladung := preload("res://src/room/einladung.gd")

const JE_FREUND_S := 60
const JE_10_MIN := 6
const MERK_MAX := 64

var _gesehen := {}       ## Fingerabdruck → { t, benutzt }
var _je_freund := {}     ## Freund → Zeitpunkt des letzten Angebots
var _zeiten: Array = []  ## Zeitpunkte der letzten Angebote


## Fingerabdruck eines Codes (16 Hex aus SHA-256) – zum Wiedererkennen, ohne den Code zu behalten.
static func abdruck(code: String) -> String:
	return ("UZ-chat-1:" + code).sha256_text().left(16)


## Soll Uzai für diese Nachricht „Zimmer betreten“ anbieten?
## { art: "anbieten" | "nichts", code, rest_min, grund } – grund bei „nichts“: "aus", "kein_freund", "keiner",
## "ungueltig", "abgelaufen", "wiederholt", "flut".
func pruefen(text: Variant, von_freund: bool, online_an: bool, freund_id: String, jetzt: int) -> Dictionary:
	var nein := { "art": "nichts", "code": "", "rest_min": 0, "grund": "" }
	if not online_an:
		nein.grund = "aus"
		return nein
	if not von_freund or freund_id == "":
		nein.grund = "kein_freund"
		return nein
	var l := Einladung.code_im_text(text, jetzt)
	if not bool(l.ok):
		nein.grund = "keiner" if str(l.fehler) == "keiner" else ("abgelaufen" if str(l.fehler) == "abgelaufen" else "ungueltig")
		return nein
	var a := abdruck(str(l.code))
	if _gesehen.has(a):
		nein.grund = "wiederholt"
		return nein
	_zeiten = _zeiten.filter(func(t: int) -> bool: return jetzt - t < 600)
	if jetzt - int(_je_freund.get(freund_id, -100000)) < JE_FREUND_S or _zeiten.size() >= JE_10_MIN:
		nein.grund = "flut"
		return nein
	_merken(a, jetzt)
	_je_freund[freund_id] = jetzt
	if _je_freund.size() > MERK_MAX:
		_je_freund.erase(_je_freund.keys()[0])
	_zeiten.append(jetzt)
	return { "art": "anbieten", "code": str(l.code), "rest_min": int(l.rest_min), "grund": "" }


## Kennt Uzai diesen Code schon aus dem Chat, und wurde damit schon angeklopft? Für die Anzeige im Chat
## (ausgegraut). { bekannt, benutzt }
func stand(code: String) -> Dictionary:
	var e: Dictionary = _gesehen.get(abdruck(code), {})
	return { "bekannt": not e.is_empty(), "benutzt": bool(e.get("benutzt", false)) }


## Mit diesem Code wurde angeklopft: Er wird nicht noch einmal angeboten.
func benutzt(code: String, jetzt: int) -> void:
	_merken(abdruck(code), jetzt)
	_gesehen[abdruck(code)]["benutzt"] = true


func _merken(a: String, jetzt: int) -> void:
	if not _gesehen.has(a) and _gesehen.size() >= MERK_MAX:
		_gesehen.erase(_gesehen.keys()[0])
	if not _gesehen.has(a):
		_gesehen[a] = { "t": jetzt, "benutzt": false }
