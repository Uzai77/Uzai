extends RefCounted
## Zimmer online – Uzais Seite des Treffpunkts (Punkt 131; docs/PLAN_ZIMMER_ONLINE.md Phase 3,
## docs/ZIMMER_SICHERHEIT.md W2–W5). Verbindet die Gastgeber-Logik (online.gd) mit der Sandbox
## (zimmer_netz.gd): Einladung → Postfach in der Sandbox, „klopft“ → Anklopfen nur für Eingeladene,
## Annahme → Platz und Schlüsseltausch, Rauswerfen/Sperren → Platz zu, „Zimmer offline“ → Sandbox aus.
##
## Hier kommen nie Adressen, Relay-Texte oder Inhalte an – nur Kennungen, Fingerabdrücke (16 Hex)
## und Zustände, die die Leitung schon geprüft hat. Verschlüsselt und entschlüsselt wird nur in der
## Sandbox. Echte Relays (signiert mit libsecp256k1) und der WebRTC-Datenkanal (libdatachannel) laufen nur
## im Echtbetrieb der Sandbox (zimmer_netz.gd windows_starten(rolle, true)); in den Tests gegen ein Test-Relay
## auf 127.0.0.1.

const Online := preload("res://src/room/online.gd")
const Einladung := preload("res://src/room/einladung.gd")
const ZN := preload("res://src/room/zimmer_netz.gd")

var rolle := "gastgeber"
var online: Online
var sitzung: ZN.Sitzung
var plaetze := {}               ## Gast-ID → Platz (nur Gastgeber)
var relays := Vector2i.ZERO     ## verbunden, gesamt
var stand := ""                 ## letzter Zustand der Sandbox ("" = noch nichts)
var zaehler := {}


func _init(r: String, s: ZN.Sitzung, o: Online = null) -> void:
	rolle = r if r in ZN.ROLLEN else "gast"
	sitzung = s
	online = o if o != null else Online.new()


## Treffpunkt in der Sandbox starten (port 0 = feste Relays; ≠ 0 nur im Testbetrieb).
func starten(port := 0) -> bool:
	var b := sitzung.leitung.treff(port)
	if b.is_empty():
		return false
	sitzung.schicken(b)
	return true


## Gastgeber: neue Einladung an genau einen Freund; Rückgabe der Link (nur zum Verschicken an
## diesen Freund, nie ins Log) oder "".
func einladen(jetzt: int, minuten: int, fuer: Variant, quelle: String) -> String:
	if rolle != "gastgeber":
		return ""
	var e := online.einladen(jetzt, minuten, fuer, quelle)
	if e.is_empty():
		return ""
	sitzung.schicken(sitzung.leitung.einladung(e.kennung, e.schluessel))
	return Einladung.link(e)


## Gastgeber (Freundestest): Einladung mit kurzem Code; Rückgabe die Einladung (code nur zum Anzeigen, nie ins
## Log) oder {}.
func einladen_code(jetzt: int, minuten: int, fuer: Variant) -> Dictionary:
	if rolle != "gastgeber":
		return {}
	var e := online.einladen_code(jetzt, minuten, fuer)
	sitzung.schicken(sitzung.leitung.einladung(e.kennung, e.schluessel))
	return e


## Gastgeber: eine offene Einladung zurückziehen (das Postfach in der Sandbox schließt).
func zurueckziehen(kennung: PackedByteArray) -> bool:
	if rolle != "gastgeber" or not online.zurueckziehen(kennung):
		return false
	sitzung.schicken(sitzung.leitung.zurueck(kennung))
	return true


## Gast: mit Kennung und Schlüssel aus einem geprüften Code anklopfen (einladung.gd code_lesen).
func besuchen_mit(kennung: PackedByteArray, schluessel: PackedByteArray) -> bool:
	if rolle != "gast" or kennung.size() != Einladung.KENNUNG_BYTES or schluessel.size() != Einladung.SCHLUESSEL_BYTES:
		return false
	sitzung.schicken(sitzung.leitung.besuch(kennung, schluessel))
	return true


## Gast: mit einem Link anklopfen. false, wenn der Link nicht genau passt.
func besuchen(link: String) -> bool:
	var l := Einladung.lesen(link)
	if rolle != "gast" or l.is_empty():
		return false
	sitzung.schicken(sitzung.leitung.besuch(l.kennung, l.schluessel))
	return true


## Leitung lesen und verarbeiten. Rückgabe für die Oberfläche:
##   { art: "klopft", id, name, quelle } (nur Eingeladene, die warten dürfen),
##   { art: "stand", was, a, b }, { art: "treff_zaehler", … }, { art: "kaputt", grund },
##   { art: "nachricht", platz, m } (über den Datenkanal, beide Prüfmauern bestanden), { art: "raus", platz, von },
##   { art: "zaehler", … } (Prüfmauer 1, auf Anfrage).
func pumpen(jetzt: int) -> Array:
	var out: Array = []
	for e in sitzung.pumpen(float(jetzt)):
		match str(e.art):
			"klopft":
				var r := online.anklopfen_kennung(str(e.gast), e.kennung, jetzt)
				if r == "wartet":
					var w: Dictionary = online.wartend[online.wartend.size() - 1]
					out.append({ "art": "klopft", "id": str(e.gast), "name": str(w.name), "quelle": str(w.quelle) })
				elif r != "schon_da":
					sitzung.schicken(sitzung.leitung.entscheid(str(e.gast), -1))   # still abweisen
			"stand":
				stand = str(e.was)
				if stand == "relays":
					relays = Vector2i(int(e.a), int(e.b))
				elif (stand == "zu" or stand == "gescheitert") and rolle == "gastgeber":
					_platz_weg(int(e.a))
				out.append(e)
			"nachricht", "raus", "zaehler":
				out.append(e)
			"treff_zaehler":
				zaehler = e
				out.append(e)
	if sitzung.leitung.kaputt != "":
		out.append({ "art": "kaputt", "grund": sitzung.leitung.kaputt })
	if rolle == "gastgeber":
		for k in online.aufraeumen(jetzt):
			sitzung.schicken(sitzung.leitung.zurueck(k))
	return out


## Hereinlassen: Online entscheidet (Höchstzahl, Einladung noch gültig), dann Platz und Annahme in
## der Sandbox. Erst danach tauschen beide Seiten Verbindungsdaten (und damit die IP-Adresse).
func annehmen(id: String, jetzt: int) -> String:
	var platz := _freier_platz()
	if platz < 0:
		return "voll"
	var r := online.annehmen(id, jetzt)
	if r != "ok":
		if r == "abgelaufen":
			sitzung.schicken(sitzung.leitung.entscheid(id, -1))
		return r
	plaetze[id] = platz
	sitzung.schicken(sitzung.leitung.entscheid(id, platz))
	for k in online.aufraeumen(jetzt):    # einmalig: das Postfach ist ab jetzt zu
		sitzung.schicken(sitzung.leitung.zurueck(k))
	return "ok"


func ablehnen(id: String) -> bool:
	if not online.ablehnen(id):
		return false
	sitzung.schicken(sitzung.leitung.entscheid(id, -1))
	return true


func rauswerfen(id: String) -> bool:
	if not online.rauswerfen(id):
		return false
	_schliessen(id)
	return true


func sperren(id: String) -> bool:
	var war_da := plaetze.has(id)
	if not online.sperren(id):
		return false
	if war_da:
		_schliessen(id)
	else:
		sitzung.schicken(sitzung.leitung.entscheid(id, -1))
	return true


## „Zimmer offline“ mit einem Druck: alle raus, alle Einladungen ungültig, Sandbox beendet.
func offline() -> void:
	online.offline()
	plaetze.clear()
	sitzung.beenden()


func zaehler_anfordern() -> void:
	sitzung.schicken(ZN.rahmen(ZN.TREFF_ZAEHLER))


func _schliessen(id: String) -> void:
	if plaetze.has(id):
		sitzung.schicken(sitzung.leitung.schliessen(int(plaetze[id])))
		plaetze.erase(id)


func _platz_weg(platz: int) -> void:
	for id in plaetze.keys():
		if int(plaetze[id]) == platz:
			plaetze.erase(id)
			online.rauswerfen(id)
			sitzung.schicken(sitzung.leitung.schliessen(platz))
			return


func _freier_platz() -> int:
	var belegt := plaetze.values()
	for i in ZN.PLAETZE:
		if not (i in belegt):
			return i
	return -1
