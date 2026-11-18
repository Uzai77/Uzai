extends RefCounted
## Verbindungstest für „Zimmer online“ (Testbetrieb, Einstellung room.online_test; docs/PLAN_ZIMMER_ONLINE.md
## „Am Windows-PC zu prüfen“ 2–4). Zwei Sandboxen auf diesem PC: Der Gastgeber lädt „Test“ ein, der Gast klopft mit
## dem Link über die Relays an, der Gastgeber lässt ihn herein, beide bauen den WebRTC-Datenkanal auf und schicken
## sich je ein „hallo“ (Protokoll Fassung 2, beide Prüfmauern). Danach ist alles wieder zu.
##
## Unter Windows im Echtbetrieb (feste Relays, BIP-340-Signatur, STUN) – das startet die Oberfläche nur, wenn
## Online.darf_testen es erlaubt. In den Tests mit zwei Test-Sandboxen und dem Test-Relay auf 127.0.0.1 (starter, port).
## Ergebnis: { relays, gesamt (Relays des Gastes), klopft, verbunden, hin, zurueck, ok, fehler }.

const ZN := preload("res://src/room/zimmer_netz.gd")
const TP := preload("res://src/room/treffpunkt.gd")


static func _jetzt() -> int:
	return int(Time.get_unix_time_from_system())


## starter: func(rolle) -> ZN.Sitzung (Standard: Windows-Helfer im Echtbetrieb); port: 0 = feste Relays.
static func laufen(tree: SceneTree, zeit_s := 120.0, starter := Callable(), port := 0) -> Dictionary:
	var r := { "relays": 0, "gesamt": 0, "klopft": false, "verbunden": false, "hin": false, "zurueck": false, "ok": false, "fehler": "" }
	var ws: ZN.Sitzung = starter.call("gastgeber") if starter.is_valid() else ZN.windows_starten("gastgeber", true)
	var gs: ZN.Sitzung = starter.call("gast") if starter.is_valid() else ZN.windows_starten("gast", true)
	if ws == null or gs == null:
		r.fehler = "start"
		for s in [ws, gs]:
			if s != null:
				s.abbrechen()
		return r
	var wirt := TP.new("gastgeber", ws)
	var gast := TP.new("gast", gs)
	var ev := { "wirt": [], "gast": [] }
	var t0 := Time.get_ticks_msec()
	var warte := func(bis: Callable) -> bool:
		while Time.get_ticks_msec() - t0 < int(zeit_s * 1000.0):
			ev.wirt.append_array(wirt.pumpen(_jetzt()))
			ev.gast.append_array(gast.pumpen(_jetzt()))
			if ws.leitung.kaputt != "" or gs.leitung.kaputt != "":
				return false
			if bis.call():
				return true
			await tree.process_frame
		return false
	var hat := func(seite: String, art: String, was := "") -> Dictionary:
		for e in ev[seite]:
			if str(e.art) == art and (was == "" or str(e.get("was", "")) == was):
				return e
		return {}
	wirt.starten(port)
	gast.starten(port)
	if not await warte.call(func() -> bool: return wirt.relays.x > 0 and gast.relays.x > 0):
		r.fehler = _grund(wirt, gast, "relays")
		_ende(wirt, gast)
		return r
	r.relays = gast.relays.x
	r.gesamt = gast.relays.y
	var link := wirt.einladen(_jetzt(), 15, "Test", "steam")
	if link == "" or not gast.besuchen(link):
		r.fehler = "einladung"
		_ende(wirt, gast)
		return r
	# Der Gast klopft über die Relays an (signiertes Ereignis) – kommt es an, haben die Relays es angenommen.
	if not await warte.call(func() -> bool: return not hat.call("wirt", "klopft").is_empty()):
		r.fehler = _grund(wirt, gast, "klopfen")
		_ende(wirt, gast)
		return r
	r.klopft = true
	wirt.annehmen(str(hat.call("wirt", "klopft").id), _jetzt())
	var fertig := func() -> bool:
		return not hat.call("wirt", "stand", "verbunden").is_empty() and not hat.call("gast", "stand", "verbunden").is_empty()
	var aus := func() -> bool:
		return not hat.call("wirt", "stand", "gescheitert").is_empty() or not hat.call("gast", "stand", "gescheitert").is_empty()
	if not await warte.call(func() -> bool: return fertig.call() or aus.call()) or not fertig.call():
		r.fehler = "direkt"
		_ende(wirt, gast)
		return r
	r.verbunden = true
	ws.schicken(ws.leitung.senden(0, "hallo", { "geraet": "uzai" }))
	gs.schicken(gs.leitung.senden(0, "hallo", { "geraet": "uzai" }))
	await warte.call(func() -> bool: return not hat.call("gast", "nachricht").is_empty() and not hat.call("wirt", "nachricht").is_empty())
	r.hin = not hat.call("gast", "nachricht").is_empty()
	r.zurueck = not hat.call("wirt", "nachricht").is_empty()
	r.ok = r.hin and r.zurueck
	if not r.ok:
		r.fehler = "nachricht"
	_ende(wirt, gast)
	return r


static func _grund(wirt: TP, gast: TP, sonst: String) -> String:
	for s in [wirt.stand, gast.stand]:
		if s in ["signatur_fehlt", "krypto_fehlt", "direkt_fehlt", "keine_antwort"]:
			return s
	if wirt.sitzung.leitung.kaputt != "" or gast.sitzung.leitung.kaputt != "":
		return "leitung"
	return sonst


static func _ende(wirt: TP, gast: TP) -> void:
	gast.sitzung.beenden()
	wirt.offline()
