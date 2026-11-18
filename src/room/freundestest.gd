extends Node
## Der Besuch im Zimmer – Zimmer online und der Testbetrieb (entstanden als „Freundestest“:
## docs/PLAN_ZIMMER_ONLINE.md, docs/ZIMMER_SICHERHEIT.md W3, W5, W6, W13): ein echter Besuch zwischen zwei PCs. Der Gastgeber erzeugt eine
## Einladung mit kurzem Code (einladung.gd neu_code) und schickt ihn selbst (Messenger, QR-Code); der Gast gibt
## ihn ein, klopft über die Relays an, der Gastgeber lässt ihn herein, dann laufen beide über den WebRTC-Datenkanal
## (Protokoll Fassung 2, beide Prüfmauern) gemeinsam durch das Zimmer des Gastgebers.
##
## Ein Knoten unter der Wurzel (aktiv), damit der Besuch weiterläuft, wenn Menüs auf- und zugehen. Er pumpt die
## Leitung in jedem Bild, schickt die eigene Lage (12-mal je Sekunde, nur bei Bewegung, sonst jede Sekunde) und
## hält fest, was von der Gegenseite kam – nur geprüfte Zahlen und Kennungen aus festen Listen (figuren()).
## Das Zimmer (zimmer.gd, besucher.gd) zeigt daraus die Figuren; der Gast sieht das Zimmer des Gastgebers
## (gast_raum, schon durch pruefe_raum), baut aber nichts und speichert es nie.
##
## Namen kommen nur aus der eigenen Einladung (Gastgeber) – der Gast schickt keinen; beim Gast heißt der
## Gastgeber „Gastgeber“. Nur ohne Adminrechte und nur, wenn „Abschottung prüfen“ in dieser Sitzung bestanden hat
## (darf). Protokoll: logs/zimmer_online.log – Schritte, Zustände, Gründe, Zähler; nie Code, Schlüssel,
## Kennungen, Namen, Adressen oder Inhalte.

const ZN := preload("res://src/room/zimmer_netz.gd")
const TP := preload("res://src/room/treffpunkt.gd")
const P := preload("res://src/room/netz_protokoll.gd")
const Online := preload("res://src/room/online.gd")
const Einladung := preload("res://src/room/einladung.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Logdatei := preload("res://src/core/logdatei.gd")

const LOG := "logs/zimmer_online.log"
const LOG_MAX := 256 * 1024
const POS_TAKT := 1.0 / 12.0
const POS_RUHE := 1.0               ## steht man still, geht die Lage nur jede Sekunde
const ZIMMER_TAKT := 2.0            ## so oft schaut der Gastgeber, ob sich sein Zimmer geändert hat
const RELAYS_FRIST := 45.0
const KLOPF_FRIST := 150.0          ## Gast: ohne Annahme so lange (die Sandbox klopft 8-mal alle 15 s)
const VERBINDEN_FRIST := 90.0       ## nach der Annahme bis „verbunden“
const HALLO_FRIST := 20.0           ## nach „verbunden“ bis zum „hallo“ der Gegenseite (Schema-Stempel)
const ABSCHIED := 0.6               ## „tschuess“ geht noch hinaus, dann endet die Sandbox
const WIRT := "gastgeber"           ## Schlüssel der Figur des Gastgebers beim Gast

## Gründe, warum etwas nicht klappte (für Oberfläche und Protokoll).
const GRUENDE := {
	"start": "Abschottung startet nicht", "relays": "Keine Relays erreichbar", "krypto_fehlt": "Verschlüsselung fehlt",
	"signatur_fehlt": "Signatur fehlt", "direkt_fehlt": "Datenkanal fehlt", "leitung": "Abschottung beendet",
	"keine_antwort": "Keine Antwort – Einladung benutzt, abgelaufen oder zurückgezogen?",
	"direkt": "Direktverbindung kam nicht zustande", "fassung": "Andere Uzai-Fassung", "zu": "Verbindung beendet",
	"unsinn": "Gegenseite schickte Unsinn", "verlassen": "Besuch verlassen", "offline": "Zimmer offline",
	"code": "Code ungültig", "abgelaufen": "Einladung abgelaufen",
}

signal geaendert
signal klopft(id: String, name: String)
signal hinweis(titel: String, text: String, icon: String)

static var aktiv: Node = null
## „Abschottung prüfen“ hat in dieser Sitzung alles bestanden (Container, Prüfmauern, beide Bibliotheken,
## ohne Adminrechte) – nur dann gibt es den Freundestest.
static var abschottung_ok := false

var rolle := ""
var tp: TP
## Besuch: Gastgeber start → bereit (Relays da); Gast start → klopft → angenommen → verbinde (Datenkanal offen) →
## verbunden („hallo“ der Gegenseite). Jeder Wartezustand hat eine Frist (_fristen); ende von überall (Grund in grund).
const ZUSTAENDE := {
	"*": ["ende"],
	"start": ["bereit", "klopft"],
	"bereit": [],
	"klopft": ["angenommen", "verbinde"],
	"angenommen": ["verbinde"],
	"verbinde": ["verbunden"],
	"verbunden": [],
	"ende": [],
}
var zustand := "start":
	set(neu):
		Zustand.wechsel("online.freundestest", ZUSTAENDE, zustand, neu)
		zustand = neu
var grund := ""          ## Kennung aus GRUENDE, wenn zustand „ende“ ist
var einladung := {}      ## Gastgeber: die offene Einladung (code nur zum Anzeigen)
var anklopfer: Array = []   ## Gastgeber: [{ id, name }]
var gaeste := {}         ## Gastgeber: Platz → Gast (siehe _neuer_gast)
var wirt := {}           ## Gast: der Gastgeber (gleiche Form)
var gast_raum := {}      ## Gast: das Zimmer des Gastgebers (geprüft)
var raum_stand := 0      ## zählt hoch, wenn gast_raum neu ist
var ui := true           ## Hinweise und Anklopf-Dialog (Tests: aus)
var starter := Callable()   ## func(rolle) -> ZN.Sitzung (Tests); sonst der Helfer im Echtbetrieb
var port := 0            ## 0 = feste Relays; ≠ 0 nur Test-Relay auf 127.0.0.1
var leitung_zaehler := {}   ## letzte Zähler der Prüfmauer 1 (Diagnose)

var _ich := { "p": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0 }
var _gesendet := {}      ## zuletzt verschickte Lage
var _pos_t := 0.0
var _pos_zuletzt := -100.0
var _zimmer_t := 0.0
var _zimmer_bytes := PackedByteArray()
var _raum := {}          ## Gastgeber: das eigene Zimmer (vom offenen Zimmer, sonst aus der Datei)
var _figur := {}         ## { figur, tier } – die eigene Figur
var _seit := 0.0         ## Zeit im aktuellen Zustand
var _uhr := 0.0
var _relays_alt := Vector2i(-1, -1)
var _code_daten := {}    ## Gast: Kennung und Schlüssel aus dem Code (nur im Speicher)
var _aufgehoert := false ## die Abschottung ist schon beendet (_aufhoeren)


## Darf ein Besuch jetzt starten? Entweder Zimmer online mit allen vier Bedingungen (Online.darf_online) oder
## der Testbetrieb – beides nur mit bestandener Abschottung (ohne Adminrechte) und unter Windows, außer in
## Tests mit eigenem starter.
static func darf(mit_starter := false) -> bool:
	return (normal_an() or Online.darf_testen(bool(Config.get_value("room.online_test", false)), false, abschottung_ok)) \
			and (mit_starter or (OS.get_name() == "Windows"))


## Zimmer online als normale Funktion: eingeschaltet, Hinweis gesehen, Abschottung in dieser Sitzung bestanden.
static func normal_an() -> bool:
	return Online.darf_online(bool(Config.get_value("room.online", false)), false, abschottung_ok, bool(Config.get_value("room.online_hinweis", false)))


## Ergebnis von „Abschottung prüfen“ merken (Probe r, Test-Gegenstelle g): ok nur mit allem und ohne Admin.
static func abschottung_merken(r: Dictionary, g: Dictionary) -> bool:
	abschottung_ok = bool(r.get("ok", false)) and bool(g.get("ok", false)) and int(r.get("secp", 0)) == 1 and int(r.get("rtc", 0)) == 1 \
			and str(r.get("fehler", "")) != "admin"
	# Je Fassung merken (nur Anzeige; in jeder Sitzung prüft Uzai neu). Fällt die Prüfung durch, ist auch das Gemerkte weg.
	Config.set_value("room.online_abschottung", { "fassung": Config.VERSION, "ok": true } if abschottung_ok else {})
	return abschottung_ok


static func laeuft() -> bool:
	return aktiv != null and is_instance_valid(aktiv) and str(aktiv.zustand) != "ende"


## Läuft gerade ein Besuch mit offener Datenleitung (für Emote-Leiste und Schnellsätze)?
static func verbunden() -> bool:
	if not laeuft():
		return false
	if str(aktiv.rolle) == "gast":
		return str(aktiv.zustand) == "verbunden"
	for g in (aktiv.gaeste as Dictionary).values():
		if bool(g.hallo):
			return true
	return false


static func grund_text(g: String) -> String:
	return str(GRUENDE.get(g, g))


# --- Start ----------------------------------------------------------------------------------------

## Gastgeber starten (eine laufende Sitzung endet vorher). Rückgabe der Knoten (zustand „ende“, wenn es nicht ging).
static func gastgeber_starten(tree: SceneTree, st := Callable(), p := 0, mit_ui := true) -> Node:
	return _neu(tree, "gastgeber", st, p, mit_ui)


## Gast mit Code starten. Der Code wird vorher streng gelesen (einladung.gd code_lesen); passt er nicht, endet
## der Knoten sofort mit „code“ bzw. „abgelaufen“ – dann wird gar nicht erst angeklopft.
static func gast_starten(tree: SceneTree, code: String, st := Callable(), p := 0, mit_ui := true) -> Node:
	var l := Einladung.code_lesen(code, int(Time.get_unix_time_from_system()))
	var n := _neu(tree, "gast", st, p, mit_ui, l)
	return n


static func _neu(tree: SceneTree, r: String, st: Callable, p: int, mit_ui: bool, code := {}) -> Node:
	if aktiv != null and is_instance_valid(aktiv):
		if laeuft():
			aktiv._ende("offline" if str(aktiv.rolle) == "gastgeber" else "verlassen")
		aktiv.queue_free()
	var n: Node = load("res://src/room/freundestest.gd").new()
	n.name = "Freundestest"
	n.rolle = r
	n.starter = st
	n.port = p
	n.ui = mit_ui
	n._code_daten = code
	aktiv = n
	n._starten()
	tree.root.add_child.call_deferred(n)     # auch aus einem _ready heraus (die Wurzel baut dann gerade)
	return n


func _starten() -> void:
	_log("— %s startet (Uzai %s, %s, %s, Relays: %s)" % [rolle, str(ProjectSettings.get_setting("application/config/version", "?")),
			OS.get_name(), "Zimmer online" if normal_an() else "Testbetrieb", "Test-Relay" if port != 0 else "feste"])
	var d := Daten.laden()
	_figur = { "figur": d.get("figur", FD.standard_figur()), "tier": d.get("tier", FD.standard_tier()) }
	for r in d.get("raeume", []):
		if str(r.get("id", "")) == str(d.get("aktuell", "")):
			_raum = r
	if _raum.is_empty() and not (d.get("raeume", []) as Array).is_empty():
		_raum = d.raeume[0]
	if rolle == "gast" and not bool(_code_daten.get("ok", false)):
		_ende(str(_code_daten.get("fehler", "code")) if str(_code_daten.get("fehler", "")) == "abgelaufen" else "code")
		return
	# Letzte Schranke vor dem Netz: Ohne eigenen starter (Tests) geht nichts hinaus, wenn die Bedingungen
	# nicht alle gelten – egal, wer diese Funktion gerufen hat.
	if not starter.is_valid() and not darf():
		_log("Start verweigert: Bedingungen für Zimmer online nicht erfüllt")
		_ende("start")
		return
	var s: ZN.Sitzung = starter.call(rolle) if starter.is_valid() else ZN.windows_starten(rolle, true)
	if s == null:
		_ende("start")
		return
	tp = TP.new(rolle, s)
	tp.online.einstellen(int(Config.get_value("room.online_max", 4)))
	if not tp.starten(port):
		_ende("start")
		return
	_log("Abschottung gestartet, Treffpunkt angefragt")
	if rolle == "gast":
		tp.besuchen_mit(_code_daten.kennung, _code_daten.schluessel)
		_log("Code gelesen (noch %d Min. gültig laut Code), klopfe an" % int(_code_daten.rest_min))
		_code_daten = {}       # nicht länger als nötig im Speicher
		_zu("klopft")


# --- Gastgeber ----------------------------------------------------------------------------------------

## Neue Einladung (eine offene wird dabei zurückgezogen). Rückgabe die Einladung (code nur zum Anzeigen) oder {}.
func einladen(fuer: Variant, minuten := -1) -> Dictionary:
	if rolle != "gastgeber" or zustand == "ende" or tp == null:
		return {}
	zurueckziehen()
	var m := minuten if minuten > 0 else int(Config.get_value("room.online_gueltig", 60))
	einladung = tp.einladen_code(_jetzt(), m, fuer)
	if not einladung.is_empty():
		_log("Einladung erstellt (%d Min. gültig, einmalig)" % int((int(einladung.bis) - _jetzt()) / 60.0 + 0.5))
	geaendert.emit()
	return einladung


## Offene Einladung zurückziehen (danach kann damit niemand mehr anklopfen).
func zurueckziehen() -> bool:
	if einladung.is_empty() or tp == null:
		return false
	var ok := tp.zurueckziehen(einladung.kennung)
	einladung = {}
	if ok:
		_log("Einladung zurückgezogen")
	geaendert.emit()
	return ok


## Restzeit der offenen Einladung in Sekunden (0 = keine offen).
func einladung_rest() -> int:
	if einladung.is_empty() or bool(einladung.get("benutzt", false)):
		return 0
	return maxi(0, int(einladung.bis) - _jetzt())


func annehmen(id: String) -> String:
	var i := _anklopfer_index(id)
	if i < 0 or tp == null:
		return "unbekannt"
	var name_ := str(anklopfer[i].name)
	anklopfer.remove_at(i)
	var r := tp.annehmen(id, _jetzt())
	_log("Anklopfen angenommen: %s" % r)
	if r == "ok":
		var platz := int(tp.plaetze[id])
		gaeste[platz] = _neuer_gast(id, name_)
		einladung = {}         # einmalig: das Postfach ist zu
	geaendert.emit()
	return r


func ablehnen(id: String) -> void:
	var i := _anklopfer_index(id)
	if i >= 0:
		anklopfer.remove_at(i)
	if tp:
		tp.ablehnen(id)
	_log("Anklopfen abgelehnt")
	geaendert.emit()


func rauswerfen(platz: int, sperren := false) -> void:
	if not gaeste.has(platz) or tp == null:
		return
	var g: Dictionary = gaeste[platz]
	if sperren:
		tp.sperren(str(g.id))
	else:
		tp.rauswerfen(str(g.id))
	gaeste.erase(platz)
	_log("Gast auf Platz %d %s" % [platz, "gesperrt" if sperren else "rausgeworfen"])
	geaendert.emit()


func sperren_anklopfer(id: String) -> void:
	var i := _anklopfer_index(id)
	if i >= 0:
		anklopfer.remove_at(i)
	if tp:
		tp.sperren(id)
	_log("Anklopfen gesperrt")
	geaendert.emit()


## Gastgeber: das eigene Zimmer (vom offenen Zimmer; geht beim nächsten Takt an die Gäste, wenn es sich änderte).
func raum_setzen(r: Dictionary) -> void:
	if rolle == "gastgeber" and not r.is_empty():
		_raum = r


func figur_setzen(figur: Variant, tier: Variant) -> void:
	var neu := { "figur": FD.pruefe_figur(figur), "tier": FD.pruefe_tier(tier) }
	if neu.hash() == _figur.hash():
		return
	_figur = neu
	_an_alle("figur", _figur)


# --- Beide ---------------------------------------------------------------------------------------------

## Die eigene Lage im Zimmer (Meter, Bogenmaß) – jedes Bild vom Zimmer.
func ich_setzen(p: Vector3, yaw: float, pitch: float) -> void:
	_ich = { "p": p, "yaw": yaw, "pitch": pitch }


func emote_senden(id: String) -> void:
	if id in P.EMOTES:
		_an_alle("emote", { "id": id })


func satz_senden(id: String) -> void:
	_an_alle("satz", { "id": id })


## Ende: Gastgeber „Zimmer offline“ (alle raus, Einladung ungültig, Sandbox aus), Gast „verlassen“ (sagt
## vorher „tschuess“ und lässt der Nachricht einen Augenblick).
func beenden(g := "") -> void:
	if zustand == "ende":
		return
	var gr := g if g != "" else ("offline" if rolle == "gastgeber" else "verlassen")
	if tp != null and rolle == "gast" and zustand == "verbunden" and gr == "verlassen":
		_an_alle("tschuess", {})
		_log("Ende: verlassen")
		grund = gr
		zustand = "ende"
		geaendert.emit()
		_abschied_laufen()
		return
	_ende(gr)


## Wer außer dir im Zimmer ist: Schlüssel → { name, figur, p, yaw, pitch, emote, emote_n, satz, satz_n }.
## Nur, wer sein „hallo“ (gleiches Schema) geschickt hat.
func figuren() -> Dictionary:
	var out := {}
	if rolle == "gast":
		if bool(wirt.get("hallo", false)):
			out[WIRT] = wirt
	else:
		for platz in gaeste:
			if bool(gaeste[platz].hallo):
				out["p%d" % platz] = gaeste[platz]
	return out


## Kurzer Stand für die Oberfläche.
func stand_text() -> String:
	if zustand == "ende":
		return tr("Hat nicht geklappt – %s") % tr(grund_text(grund)) if not (grund in ["verlassen", "offline", "zu"]) else tr(grund_text(grund))
	if rolle == "gast":
		match zustand:
			"klopft":
				return tr("Klopfe an …")
			"angenommen", "verbinde":
				return tr("Hereingelassen – verbinde …")
			"verbunden":
				return tr("Verbunden")
		return tr("Starte …")
	if tp == null or tp.relays.x == 0:
		return tr("Verbinde mit den Relays …")
	var da := figuren().size()
	if da > 0:
		return tr("%d im Zimmer") % da
	if not anklopfer.is_empty():
		return tr("Jemand klopft an")
	return tr("Einladung offen") if einladung_rest() > 0 else tr("Bereit")


func bereit() -> bool:
	return tp != null and tp.relays.x > 0 and zustand != "ende"


# --- Jedes Bild -------------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if tp == null or zustand == "ende":
		return
	_uhr += dt
	_seit += dt
	for e in tp.pumpen(_jetzt()):
		_ereignis(e)
		if zustand == "ende":
			return
	_fristen()
	if zustand == "ende":
		return
	_lage_senden(dt)
	if rolle == "gastgeber":
		_zimmer_t += dt
		if _zimmer_t >= ZIMMER_TAKT:
			_zimmer_t = 0.0
			_zimmer_senden(false)
		if not einladung.is_empty() and einladung_rest() == 0:
			_log("Einladung abgelaufen")
			einladung = {}
			geaendert.emit()


func _ereignis(e: Dictionary) -> void:
	match str(e.art):
		"kaputt":
			_log("Leitung zu (%s)" % str(e.grund))
			_ende("leitung")
		"klopft":
			if rolle == "gastgeber":
				anklopfer.append({ "id": str(e.id), "name": str(e.name) })
				_log("Jemand klopft an (mit dieser Einladung)")
				klopft.emit(str(e.id), str(e.name))
				if ui:
					_klopf_dialog(str(e.id), str(e.name))
				geaendert.emit()
		"stand":
			_stand(str(e.was), int(e.a), int(e.b))
		"raus":
			_log("Prüfmauer (%s): Gegenseite auf Platz %d reißt die Grenzen" % [str(e.von), int(e.platz)])
			if rolle == "gastgeber":
				var g: Dictionary = gaeste.get(int(e.platz), {})
				if not g.is_empty():
					_melden(tr("%s musste gehen") % str(g.name), "Zu viele oder ungültige Nachrichten", "warning")
					rauswerfen(int(e.platz))
			else:
				_ende("unsinn")
		"nachricht":
			_nachricht(int(e.platz), e.m)
		"zaehler":
			leitung_zaehler = e
			_log("Zähler Leitung: angenommen %d, verworfen %d, gedrosselt %d, hinaus verworfen %d" % [int(e.angenommen), int(e.verworfen), int(e.gedrosselt),
					int(e.aus_verworfen)])
		"treff_zaehler":
			_log("Zähler Treffpunkt: gesehen %d, Unsinn %d, Krypto %d, wiederholt %d, gedrosselt %d, Relay-Fehler %d" % [
					int(e.gesehen), int(e.unsinn), int(e.krypto), int(e.wiederholt), int(e.gedrosselt), int(e.relay)])


func _stand(was: String, a: int, b: int) -> void:
	match was:
		"relays":
			var r := Vector2i(a, b)
			if r != _relays_alt:
				_relays_alt = r
				_log("Relays: %d von %d" % [a, b])
				if a > 0 and zustand == "start" and rolle == "gastgeber":
					_zu("bereit")
				geaendert.emit()
		"angenommen":
			if rolle == "gast" and zustand == "klopft":
				_log("Hereingelassen, Direktverbindung wird aufgebaut")
				_zu("angenommen")
				_melden("Hereingelassen", "Verbinde …", "friends")
		"verbunden":
			_log("Direktverbindung offen (Platz %d)" % a)
			if rolle == "gast":
				if zustand in ["angenommen", "klopft"]:
					_zu("verbinde")
					wirt = _neuer_gast("", tr("Gastgeber"))
					_hallo_senden(0)
			elif gaeste.has(a):
				gaeste[a].verbunden = true
				gaeste[a].seit_verbunden = _uhr
				_hallo_senden(a)
		"zu", "gescheitert":
			_log("Sitzung %s (Platz %d)" % ["beendet" if was == "zu" else "gescheitert", a])
			if rolle == "gast":
				_ende("zu" if was == "zu" else "direkt")
			elif gaeste.has(a):
				var g: Dictionary = gaeste[a]
				gaeste.erase(a)
				if was == "zu":
					_melden(tr("%s ist weg") % str(g.name), "Verbindung beendet", "friends")
				else:
					_melden(tr("Verbindung zu %s kam nicht zustande") % str(g.name), "Ohne Vermittlungsserver klappt das nicht überall.", "warning")
				geaendert.emit()
		"keine_antwort":
			_log("Keine Antwort auf das Anklopfen")
			if rolle == "gast":
				_ende("keine_antwort")
		"krypto_fehlt", "signatur_fehlt", "direkt_fehlt":
			_log("Abschottung meldet: %s" % was)
			_ende(was)


## Eine geprüfte Nachricht (beide Prüfmauern bestanden). Vor dem „hallo“ (gleiches Schema) zählt nichts.
func _nachricht(platz: int, m: Dictionary) -> void:
	var g: Dictionary = wirt if rolle == "gast" else gaeste.get(platz, {})
	if g.is_empty() or (rolle == "gast" and platz != 0):
		return
	var a := str(m.a)
	var d: Dictionary = m.d
	if a == "hallo":
		if not bool(g.hallo):
			g.hallo = true
			_log("„hallo“ der Gegenseite: gleiche Fassung (%s)" % str(d.geraet))
			_senden(platz, "figur", _figur)
			_senden(platz, "pos", _pos_jetzt())
			if rolle == "gastgeber":
				_zimmer_senden(true, platz)
				_melden(tr("%s ist im Zimmer") % str(g.name), "Zimmer online" if normal_an() else "Freundestest", "friends")
			else:
				_zu("verbunden")
				_melden("Verbunden", "Du bist im Zimmer deines Freundes", "friends")
				var mn := get_tree().current_scene
				if ui and mn and mn.has_method("room_layer") and mn.call("room_layer") == null:
					mn.call("open_room")
			geaendert.emit()
		return
	if not bool(g.hallo):
		return
	match a:
		"pos":
			g.p = P.pos_welt(d)
			g.yaw = int(d.yaw) / 1000.0
			g.pitch = int(d.pitch) / 1000.0
			g.pos_n = int(g.pos_n) + 1
		"emote":
			g.emote = str(d.id)
			g.emote_n = int(g.emote_n) + 1
		"satz":
			g.satz = str(d.id)
			g.satz_n = int(g.satz_n) + 1
		"figur":
			g.figur = FD.pruefe_figur((d.figur as Dictionary))
			g.figur_n = int(g.figur_n) + 1
		"zimmer":
			if rolle == "gast":
				var r: Dictionary = d.raum
				if r.hash() != gast_raum.hash():
					gast_raum = r
					raum_stand += 1
					_log("Zimmer des Gastgebers erhalten (%d Möbel)" % (r.get("moebel", []) as Array).size())
					geaendert.emit()
		"tschuess":
			_log("Gegenseite verabschiedet sich")
			if rolle == "gastgeber":
				_melden(tr("%s ist gegangen") % str(g.name), "", "friends")
				rauswerfen(platz)
			else:
				_ende("zu")


func _neuer_gast(id: String, name_: String) -> Dictionary:
	return { "id": id, "name": name_, "seit": _jetzt(), "verbunden": false, "hallo": false, "seit_verbunden": 0.0, "figur": FD.standard_figur(),
			"figur_n": 0, "p": Vector3(-1, 0, -1), "yaw": 0.0, "pitch": 0.0, "pos_n": 0, "emote": "", "emote_n": 0, "satz": "", "satz_n": 0 }


func _fristen() -> void:
	if zustand == "start" and _seit > RELAYS_FRIST and (tp == null or tp.relays.x == 0):
		_ende("relays")
	elif rolle == "gast" and zustand == "klopft" and _seit > KLOPF_FRIST:
		_ende("keine_antwort")
	elif rolle == "gast" and zustand == "angenommen" and _seit > VERBINDEN_FRIST:
		_ende("direkt")
	elif rolle == "gast" and zustand == "verbinde" and _seit > HALLO_FRIST:
		_ende("fassung")
	elif rolle == "gastgeber":
		for platz in gaeste.keys():
			var g: Dictionary = gaeste[platz]
			if bool(g.verbunden) and not bool(g.hallo) and _uhr - float(g.seit_verbunden) > HALLO_FRIST:
				_log("Kein „hallo“ von Platz %d: andere Fassung" % platz)
				_melden(tr("%s hat eine andere Uzai-Fassung") % str(g.name), "Beide brauchen dieselbe Fassung.", "warning")
				rauswerfen(platz)


func _pos_jetzt() -> Dictionary:
	return P.pos_aus(_ich.p, float(_ich.yaw), float(_ich.pitch))


func _lage_senden(dt: float) -> void:
	_pos_t += dt
	if _pos_t < POS_TAKT:
		return
	_pos_t = 0.0
	var d := _pos_jetzt()
	if d.hash() == _gesendet.hash() and _uhr - _pos_zuletzt < POS_RUHE:
		return
	if _an_alle("pos", d):
		_gesendet = d
		_pos_zuletzt = _uhr


## An alle verbundenen Gegenseiten (Gastgeber: jeder Gast für sich; Gast: der Gastgeber). true, wenn an jemanden.
func _an_alle(art: String, d: Dictionary) -> bool:
	if tp == null or zustand == "ende":
		return false
	var an := false
	if rolle == "gast":
		if zustand == "verbunden":
			an = _senden(0, art, d)
	else:
		for platz in gaeste:
			if bool(gaeste[platz].hallo):
				an = _senden(platz, art, d) or an
	return an


func _senden(platz: int, art: String, d: Dictionary) -> bool:
	var b := tp.sitzung.leitung.senden(platz, art, d)
	if b.is_empty():
		return false
	tp.sitzung.schicken(b)
	return true


func _hallo_senden(platz: int) -> void:
	_senden(platz, "hallo", { "geraet": "uzai" })


## Gastgeber: das Zimmer an die Gäste (nur Katalog-Nummern; eigene Möbel bleiben zu Hause), wenn es sich
## geändert hat oder ein Gast neu ist (nur_platz ≥ 0).
func _zimmer_senden(immer: bool, nur_platz := -1) -> void:
	if _raum.is_empty():
		return
	var b := P.schreiben("zimmer", { "raum": _raum })
	if b.is_empty():
		_log("Zimmer passt nicht ins Schema – nicht gesendet")
		return
	if not immer and b == _zimmer_bytes:
		return
	if b != _zimmer_bytes:
		_log("Zimmer gesendet (%d Byte)" % b.size())
	_zimmer_bytes = b
	if nur_platz >= 0:
		_senden(nur_platz, "zimmer", { "raum": _raum })
	else:
		_an_alle("zimmer", { "raum": _raum })


func _anklopfer_index(id: String) -> int:
	for i in anklopfer.size():
		if str(anklopfer[i].id) == id:
			return i
	return -1


func _zu(z: String) -> void:
	zustand = z
	_seit = 0.0
	geaendert.emit()


func _ende(g: String) -> void:
	if zustand == "ende":
		return
	grund = g
	_log("Ende: %s" % g)
	zustand = "ende"
	_aufhoeren()
	if ui and not (g in ["verlassen", "offline"]):
		_melden(rolle_titel(), stand_text(), "warning" if g != "zu" else "friends")
	geaendert.emit()


func rolle_titel() -> String:
	return tr("Besuch") if rolle == "gast" or normal_an() else tr("Freundestest")


func _abschied_laufen() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(ABSCHIED * 1000.0) and is_inside_tree():
		tp.pumpen(_jetzt())
		await get_tree().process_frame
	_aufhoeren()


func _aufhoeren() -> void:
	if _aufgehoert:
		return
	_aufgehoert = true
	if tp != null:
		if tp.sitzung.leitung.kaputt != "":
			tp.sitzung.abbrechen()     # der Sandbox wird nichts mehr geglaubt: Prozess beenden
		else:
			tp.zaehler_anfordern()
		if rolle == "gastgeber":
			tp.offline()
		else:
			tp.sitzung.beenden()
	anklopfer.clear()
	gaeste.clear()
	einladung = {}


func _melden(titel: String, text: String, icon: String) -> void:
	hinweis.emit(titel, text, icon)
	if ui:
		Toasts.show_toast(titel, text, icon)


func _klopf_dialog(id: String, name_: String) -> void:
	var mn := get_tree().current_scene
	if mn == null or not mn.has_method("open_dialog"):
		return
	Sfx.play("open")
	# Der Dialog kommt von selbst, vielleicht mitten in einen Tastendruck: Die Auswahl liegt auf „Später“ –
	# hereingelassen (und damit die IP-Adresse gezeigt) wird nur mit Absicht. „Später“ lässt den Gast warten;
	# entschieden wird dann unter „Zimmer online“.
	mn.open_dialog(tr("%s möchte rein") % name_, tr("Aus deiner Einladung. Nach dem Hereinlassen sieht %s deine IP-Adresse.") % name_, [
		["Hereinlassen", func() -> void: annehmen(id)],
		["Ablehnen", func() -> void: ablehnen(id)],
		["Sperren", func() -> void: sperren_anklopfer(id)],
		["Später", func() -> void: pass, "start"],
	], "user")


func _jetzt() -> int:
	return int(Time.get_unix_time_from_system())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		# Wie auch immer der Knoten geht (ein neuer Besuch ersetzt ihn, während der Abschied noch läuft; Uzai
		# beendet sich): Die Abschottung endet mit ihm.
		_aufhoeren()
		if aktiv == self:
			aktiv = null


## Protokoll für die Fehlersuche (der Nutzer kann es schicken): nur Schritte, Zustände, Gründe, Zähler.
func _log(text: String) -> void:
	Logdatei.zeile(Config.path(LOG), text, LOG_MAX, "  " + rolle)
