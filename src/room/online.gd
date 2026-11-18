extends RefCounted
## Zimmer online – was der Gastgeber entscheidet (Punkt 131, Stufe 4; docs/ZIMMER_SICHERHEIT.md):
## Einladen, Anklopfen, Hereinlassen, Ablehnen, Rauswerfen, Sperren, Höchstzahl der Gäste. Reine
## Logik ohne Netz: Hier entsteht keine Verbindung. BEREIT ist seit der Gesamtprüfung (Phase 6,
## docs/ZIMMER_SICHERHEIT.md Abschnitt 10) gesetzt – online geht das Zimmer trotzdem nur, wenn alle
## vier Bedingungen von darf_online erfüllt sind. Nur von Uzai zu Uzai; der Gast im Browser ruht.
##
## Nur Eingeladene können anklopfen: Jede Einladung geht an genau einen Freund (Steam-Chat oder
## Discord-Direktnachricht) und trägt dessen Namen aus Uzais eigener Freundesliste. Gäste schicken
## keinen Namen – angezeigt wird der Name, unter dem du den Freund eingeladen hast. Erkannt wird ein
## Gast am Fingerabdruck seines Sitzungsschlüssels (16 Hex-Zeichen). Anklopfen geht nur mit dem
## Schlüssel einer gültigen Einladung und ist je Minute begrenzt; was darüber kommt, wird ohne
## Antwort verworfen.

const Einladung := preload("res://src/room/einladung.gd")

const BEREIT := true
const MAX_WARTEND := 8
const ANKLOPFEN_JE_MINUTE := 6
const MAX_GAESTE_GRENZE := 8
const QUELLEN := ["steam", "discord", "code"]   ## wohin die Einladung ging (code: Freundestest, selbst verschickt)
const MAX_NAME := 24

var max_gaeste := 4
var einladungen: Array = []         ## [Einladung.neu(…) + { fuer, quelle }]
var wartend: Array = []             ## [{ id, name, quelle, seit }]
var gaeste: Array = []              ## [{ id, name, quelle, seit }]
var gesperrt := {}                  ## id → Name (zum Wiedererkennen in der Liste)
var _klopfen: Array = []            ## Zeitpunkte der letzten Anklopfer (Sekunden)


## Darf das Zimmer online gehen? Nur, wenn alles zugleich gilt:
##   eingeschaltet    die Einstellung „Zimmer online“ ist an (Standard aus)
##   admin            Uzai läuft nicht mit Adminrechten
##   abschottung_ok   „Abschottung prüfen“ hat in dieser Sitzung auf diesem PC alles bestanden (Uzai
##                    prüft vor dem ersten Mal selbst: Container, beide Prüfmauern, beide Bibliotheken)
##   hinweis_gesehen  der ehrliche Hinweis kam, dass Eingeladene die IP-Adresse sehen
## Fehlt eine Angabe, gilt sie als nicht erfüllt.
static func darf_online(eingeschaltet: bool, admin: bool, abschottung_ok := false, hinweis_gesehen := false) -> bool:
	return BEREIT and eingeschaltet and not admin and abschottung_ok and hinweis_gesehen


## Gemerktes Ergebnis von „Abschottung prüfen“ (Einstellung room.online_abschottung): bestanden mit genau
## dieser Uzai-Fassung? Nur für die Anzeige und dafür, dass das Einschalten nicht erklärt werden muss –
## geprüft wird trotzdem in jeder Sitzung neu (Adminrechte und Umgebung können sich ändern).
static func abschottung_gemerkt(eintrag: Variant, fassung: String) -> bool:
	if not (eintrag is Dictionary) or fassung == "":
		return false
	var ok: Variant = (eintrag as Dictionary).get("ok")
	return ok is bool and bool(ok) and str((eintrag as Dictionary).get("fassung", "")) == fassung


## Testbetrieb mit echten Relays und WebRTC (Einstellung room.online_test, Standard aus) – für den
## Verbindungstest und einen Besuch zum Ausprobieren, ohne „Zimmer online“ einzuschalten: nur eingeschaltet, nie
## mit Adminrechten und nur, wenn „Abschottung prüfen“ gerade alles bestanden hat (Container, beide Prüfmauern,
## beide Netz-Bibliotheken geladen, Prüfsumme und Selbsttest). Öffnet nichts von selbst.
static func darf_testen(eingeschaltet: bool, admin: bool, abschottung_ok: bool) -> bool:
	return eingeschaltet and not admin and abschottung_ok


static func gueltige_id(id: Variant) -> bool:
	if not (id is String) or (id as String).length() != 16:
		return false
	for ch in (id as String):
		if not (ch in "0123456789abcdef"):
			return false
	return true


func einstellen(max_n: int) -> void:
	max_gaeste = clampi(max_n, 1, MAX_GAESTE_GRENZE)


## Jemand klopft an (Nachricht schon entschlüsselt und geprüft). Antwort: „wartet“, „schon_da“,
## „gesperrt“, „falscher_schluessel“, „gedrosselt“, „voll“, „ungueltig“. Nur „wartet“ zeigt der
## Gastgeber an; alles andere bleibt still. Name und Weg kommen aus der Einladung, nie vom Gast.
func anklopfen(id: String, schluessel: PackedByteArray, jetzt: int) -> String:
	if not gueltige_id(id):
		return "ungueltig"
	_klopfen = _klopfen.filter(func(t: int) -> bool: return jetzt - t < 60)
	if _klopfen.size() >= ANKLOPFEN_JE_MINUTE:
		return "gedrosselt"
	_klopfen.append(jetzt)
	if gesperrt.has(id):
		return "gesperrt"
	var e := _einladung_zu(schluessel, jetzt)
	if e.is_empty():
		return "falscher_schluessel"
	if _finde(wartend, id) >= 0 or _finde(gaeste, id) >= 0:
		return "schon_da"
	if wartend.size() >= MAX_WARTEND:
		return "voll"
	wartend.append({ "id": id, "name": str(e.fuer), "quelle": str(e.quelle), "seit": jetzt, "schluessel": schluessel })
	return "wartet"


## Hereinlassen: „ok“, „voll“ (Höchstzahl erreicht), „abgelaufen“ (Einladung inzwischen ungültig)
## oder „unbekannt“. Erst danach dürfte eine direkte Verbindung entstehen (und die IP fließen).
func annehmen(id: String, jetzt: int) -> String:
	var i := _finde(wartend, id)
	if i < 0:
		return "unbekannt"
	if gaeste.size() >= max_gaeste:
		return "voll"
	var w: Dictionary = wartend[i]
	var e := _einladung_zu(w.schluessel, jetzt)
	if e.is_empty():
		wartend.remove_at(i)
		return "abgelaufen"
	e["benutzt"] = true
	wartend.remove_at(i)
	gaeste.append({ "id": w.id, "name": w.name, "quelle": w.quelle, "seit": jetzt })
	return "ok"


func ablehnen(id: String) -> bool:
	var i := _finde(wartend, id)
	if i >= 0:
		wartend.remove_at(i)
	return i >= 0


func rauswerfen(id: String) -> bool:
	var i := _finde(gaeste, id)
	if i >= 0:
		gaeste.remove_at(i)
	return i >= 0


## Sperren: raus (oder aus der Warteliste) und künftig still abgewiesen.
func sperren(id: String) -> bool:
	for liste in [wartend, gaeste]:
		var i := _finde(liste, id)
		if i >= 0:
			gesperrt[id] = str(liste[i].name)
			liste.remove_at(i)
			return true
	return false


func entsperren(id: String) -> bool:
	return gesperrt.erase(id)


## „Zimmer offline“ mit einem Druck: alle raus, niemand wartet mehr, alle Einladungen ungültig.
func offline() -> void:
	wartend.clear()
	gaeste.clear()
	einladungen.clear()
	_klopfen.clear()


## Neue Einladung an genau einen Freund (fuer: sein Name aus Uzais Freundesliste, quelle: steam
## oder discord). Immer nur einmal nutzbar und kurz gültig; andere bleiben gültig, bis sie ablaufen,
## benutzt sind oder „offline“ sie zurückzieht.
func einladen(jetzt: int, minuten: int, fuer: Variant, quelle: String) -> Dictionary:
	if not (quelle in QUELLEN):
		return {}
	var e := Einladung.neu(jetzt, minuten, true)
	e["fuer"] = anzeige_name(fuer)
	e["quelle"] = quelle
	einladungen.append(e)
	return e


## Freundestest: Einladung mit kurzem Code (einladung.gd neu_code), den du selbst verschickst. Sonst wie einladen.
func einladen_code(jetzt: int, minuten: int, fuer: Variant) -> Dictionary:
	var e := Einladung.neu_code(jetzt, minuten)
	e["fuer"] = anzeige_name(fuer)
	e["quelle"] = "code"
	einladungen.append(e)
	return e


## Anklopfen, wie es der Treffpunkt meldet: nur die Kennung des Postfachs (der Schlüssel bleibt in
## der Einladung). Unbekannte Kennung zählt wie ein falscher Schlüssel.
func anklopfen_kennung(id: String, kennung: PackedByteArray, jetzt: int) -> String:
	var e := einladung_mit(kennung)
	return anklopfen(id, e.get("schluessel", PackedByteArray()), jetzt)


func einladung_mit(kennung: PackedByteArray) -> Dictionary:
	for e in einladungen:
		if kennung.size() == Einladung.KENNUNG_BYTES and Crypto.new().constant_time_compare(e.kennung, kennung):
			return e
	return {}


## Einladung zurückziehen (Kennung): danach kann damit niemand mehr anklopfen.
func zurueckziehen(kennung: PackedByteArray) -> bool:
	var e := einladung_mit(kennung)
	if e.is_empty():
		return false
	einladungen.erase(e)
	return true


## Abgelaufene und benutzte Einladungen entfernen; Rückgabe: ihre Kennungen (deren Postfächer
## schließt der Treffpunkt dann auch in der Sandbox).
func aufraeumen(jetzt: int) -> Array:
	var weg: Array = []
	for e in einladungen.duplicate():
		if not Einladung.gueltig(e, jetzt):
			weg.append(e.kennung)
			einladungen.erase(e)
	return weg


func _einladung_zu(schluessel: PackedByteArray, jetzt: int) -> Dictionary:
	for e in einladungen:
		if Einladung.passt(e, schluessel) and Einladung.gueltig(e, jetzt):
			return e
	return {}


static func _finde(liste: Array, id: String) -> int:
	for i in liste.size():
		if str(liste[i].id) == id:
			return i
	return -1


## Beispiel-Gäste für die Vorschau (kein Netz): zwei sind da, zwei klopfen an, einer ist gesperrt.
func beispiel(jetzt: int) -> void:
	offline()
	gesperrt.clear()
	var k := func(id: String, fuer: String, quelle: String, t: int) -> void:
		anklopfen(id, einladen(t - 60, 60, fuer, quelle).schluessel, t)
	k.call("a1b2c3d4e5f60718", "Mila", "discord", jetzt - 1500)
	k.call("0f1e2d3c4b5a6978", "Jonas", "steam", jetzt - 1100)
	annehmen("a1b2c3d4e5f60718", jetzt - 1400)
	annehmen("0f1e2d3c4b5a6978", jetzt - 1000)
	k.call("deadbeef00c0ffee", "Ben", "steam", jetzt - 400)
	sperren("deadbeef00c0ffee")
	k.call("9a8b7c6d5e4f3021", "Sophie", "discord", jetzt - 70)
	k.call("1234abcd5678ef90", "Lea", "steam", jetzt - 20)
	_klopfen.clear()


## Name eines Freundes aus Steam oder Discord (fremder Text, nur zur Anzeige beim Gastgeber): nur
## erlaubte Zeichen, Leerraum zusammengefasst, gekürzt; „Freund“, wenn nichts bleibt.
static func anzeige_name(v: Variant) -> String:
	if not (v is String) or (v as String).length() > MAX_NAME * 8:
		return "Freund"
	var s: String = v
	var out := ""
	var leer := false
	for i in s.length():
		var c := s.unicode_at(i)
		if c == 9 or c == 10 or c == 13 or c == 32 or c == 0xA0 or c == 0x3000 or (c >= 0x2000 and c <= 0x200A):
			leer = out != ""
			continue
		if _verboten(c):
			continue
		if leer:
			out += " "
			leer = false
		out += char(c)
		if out.length() >= MAX_NAME:
			break
	return out if out != "" else "Freund"


## Unsichtbare Zeichen und Richtungs-Steuerzeichen (Bidi-Tricks: Text, der anders aussieht, als er
## ist), dazu alle Steuerzeichen (unter 32, 127, 128–159) und Ersatzzeichen-Hälften.
static func _verboten(c: int) -> bool:
	if c < 32 or (c >= 127 and c < 160):
		return true
	if c == 0xAD or c == 0x34F or c == 0x61C or c == 0x115F or c == 0x1160 or c == 0x180E or c == 0x3164 or c == 0xFEFF or c == 0xFFA0:
		return true
	if (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F):
		return true
	if (c >= 0xFFF0 and c <= 0xFFFF) or (c >= 0xE0000 and c <= 0xE0FFF) or (c >= 0xFE00 and c <= 0xFE0F):
		return true
	return c >= 0xD800 and c <= 0xDFFF
