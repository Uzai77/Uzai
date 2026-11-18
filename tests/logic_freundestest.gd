extends Node
## Freundestest (docs/PLAN_ZIMMER_ONLINE.md „Freundestest“, docs/ZIMMER_SICHERHEIT.md W3, W6): der kurze
## Einladungscode (einladung.gd) streng und mit Fuzz – jeder Tippfehler in einem Zeichen und jeder Nachbar-Dreher
## fällt auf, fremder Text kommt nie durch, Ablauf ehrlich – und freundestest.gd gegen eine nachgebaute Sandbox in
## beiden Rollen: Einladung → Anklopfen (Name nur aus der Einladung) → Annehmen → „hallo“ → Figur, Lage, Emote,
## Schnellsatz, Zimmer (nur vom Gastgeber) → Rauswerfen → dieselbe Einladung gilt nicht mehr; Fristen, Prüfmauer,
## Protokoll ohne Code, Schlüssel und Namen. Echtes Netz: tests/net_zimmer_treff.gd.
## Aufruf: godot --headless --path . res://tests/logic_freundestest.tscn

const ZN := preload("res://src/room/zimmer_netz.gd")
const P := preload("res://src/room/netz_protokoll.gd")
const Einladung := preload("res://src/room/einladung.gd")
const Online := preload("res://src/room/online.gd")
const FT := preload("res://src/room/freundestest.gd")
const EinladungChat := preload("res://src/room/einladung_chat.gd")

var fails := 0
var rng := RandomNumberGenerator.new()


class Nachbau extends ZN.Sitzung:
	var raus: Array = []
	var rein := PackedByteArray()
	var ende := false

	func _init(rolle: String) -> void:
		leitung = ZN.Leitung.new(rolle, true)

	func schicken(b: PackedByteArray) -> void:
		if not b.is_empty() and leitung.kaputt == "":
			raus.append(b)
			ende = ende or b[4] == ZN.ENDE

	func beenden() -> void:
		schicken(ZN.Leitung.rahmen(ZN.ENDE))

	func pumpen(jetzt: float) -> Array:
		var b := rein
		rein = PackedByteArray()
		return leitung.eingang(b, jetzt)

	func laeuft() -> bool:
		return not ende

	func abbrechen() -> void:
		ende = true

	func letzter(art: int) -> PackedByteArray:
		for i in range(raus.size() - 1, -1, -1):
			if raus[i][4] == art:
				return (raus[i] as PackedByteArray).slice(5)
		return PackedByteArray()

	## Was über den Datenkanal hinausging: Arten der SENDEN-Rahmen (in Reihenfolge).
	func gesendet() -> Array:
		var out: Array = []
		for b in raus:
			if b[4] == ZN.SENDEN:
				out.append(P.ARTEN[(b as PackedByteArray)[8]])
		return out


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	rng.seed = 131
	_code()
	_fuzz()
	_chat()
	_bedingungen()
	await _gastgeber_und_gast()
	_quelltext()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _jetzt() -> int:
	return int(Time.get_unix_time_from_system())


# --- Code -------------------------------------------------------------------------------------------------

func _code() -> void:
	print("Einladungscode")
	var t := _jetzt()
	var e := Einladung.neu_code(t, 15)
	var c: String = e.code
	var a := Einladung.code_anzeige(c)
	check(c.length() == 35 and a.length() == 46 and a.begins_with("UZAI-") and a.split("-").size() == 8,
			"35 Zeichen in sieben Fünfergruppen hinter „UZAI-“ (%s…)" % a.substr(0, 10))
	var ok := true
	for ch in c:
		ok = ok and Einladung.B32.contains(ch)
	check(ok and not ("I" in c or "L" in c or "O" in c or "U" in c), "nur Crockford-Base32 (kein I, L, O, U)")
	var l := Einladung.code_lesen(a, t)
	check(bool(l.ok) and l.kennung == e.kennung and l.schluessel == e.schluessel and int(l.rest_min) >= 15 and int(l.rest_min) <= 16,
			"gelesen: Kennung und Schlüssel wie beim Gastgeber, noch 15 Min.")
	check(e.kennung.size() == 16 and e.schluessel.size() == 32 and e.kennung != e.schluessel.slice(0, 16) and int(e.bis) % 60 == 0,
			"HKDF: 16 + 32 Byte, getrennt")
	var formen := [c, c.to_lower(), "  " + a + "\n", a.replace("-", " "), "uzai " + c.to_lower(), c.replace("0", "O").replace("1", "I"),
			c.replace("1", "l"), a.replace("-", "\t")]
	var alle := true
	for f in formen:
		var x := Einladung.code_lesen(f, t)
		alle = alle and bool(x.ok) and x.schluessel == e.schluessel
	check(alle, "klein, mit Leerzeichen, ohne Präfix, O statt 0, I/l statt 1: dasselbe")
	var boese := {
		"leer": "", "nur Leerraum": "   ", "zu lang": a + " ".repeat(200), "Doppelpunkt": "uzai://" + c, "Raute": "#" + c,
		"unsichtbares Zeichen": c.substr(0, 10) + char(0x200B) + c.substr(10), "Umlaut": c.substr(0, 34) + "Ä", "NUL": c + char(0),
		"Zeichen zu wenig": c.substr(0, 34), "Zeichen zu viel": c + "0", "U im Code": c.substr(0, 34) + "U", "falsches Präfix": "UZAJ-" + c,
		"Präfix doppelt": "UZAI-" + a, "Zahl": 42, "Feld": [c], "Text mit Code darin": "Komm rein: " + a, "Link alt": Einladung.link(e),
	}
	var abgelehnt := true
	for k in boese:
		var x := Einladung.code_lesen(boese[k], t)
		if bool(x.ok) or not x.kennung.is_empty():
			abgelehnt = false
			print("    durchgekommen: ", k)
	check(abgelehnt, "%d Formen von Unsinn abgelehnt (Link, Unicode, Text drumherum, falsche Länge)" % boese.size())
	# Jeder Tippfehler in einem Zeichen, jeder Dreher zweier verschiedener Nachbarn.
	var durch := 0
	var proben := 0
	for i in c.length():
		for ch in Einladung.B32:
			if ch == c[i]:
				continue
			proben += 1
			if bool(Einladung.code_lesen(c.substr(0, i) + ch + c.substr(i + 1), t).ok):
				durch += 1
	for i in c.length() - 1:
		if c[i] != c[i + 1]:
			proben += 1
			if bool(Einladung.code_lesen(c.substr(0, i) + c[i + 1] + c[i] + c.substr(i + 2), t).ok):
				durch += 1
	check(durch == 0, "alle %d Tippfehler und Dreher erkannt" % proben)
	# Ablauf: der Gast sieht ehrlich „abgelaufen“; die Ablaufzeit lässt sich nicht verstellen (anderes Postfach).
	var alt := Einladung.neu_code(t - 30 * 60, 15)
	check(str(Einladung.code_lesen(alt.code, t).fehler) == "abgelaufen", "abgelaufen (vor 15 Min.)")
	check(bool(Einladung.code_lesen(alt.code, int(alt.bis) + 120).ok), "Uhr des Gastes 2 Min. nach: noch durchgelassen (der Gastgeber entscheidet)")
	check(str(Einladung.code_lesen(e.code, t - 3 * 86400).fehler) == "zeit", "Ablauf unplausibel weit weg: abgelehnt")
	var e2 := Einladung.neu_code(t, 15)
	check(e2.kennung != e.kennung and e2.code != e.code, "jede Einladung neu (Zufall)")
	# Online: Anklopfen mit der Kennung aus dem Code, einmalig.
	var o := Online.new()
	var ein := o.einladen_code(t, 15, "Mi\u202ela")
	check(str(ein.quelle) == "code" and str(ein.fuer) == "Mila", "Einladung per Code, Name bereinigt")
	var lk := Einladung.code_lesen(ein.code, t)
	check(o.anklopfen_kennung("a1b2c3d4e5f60718", lk.kennung, t) == "wartet" and o.annehmen("a1b2c3d4e5f60718", t) == "ok", "anklopfen und annehmen")
	check(o.anklopfen_kennung("0f1e2d3c4b5a6978", lk.kennung, t) == "falscher_schluessel", "dieselbe Einladung ein zweites Mal: nein")


func _fuzz() -> void:
	print("Fuzz des Code-Lesers")
	var t := _jetzt()
	var zeichen := Einladung.B32 + "abcdefghijklmnopqrstuvwxyzILOU-  :/#%\\\"'{}[]<>&;|\t\nä\u200b\u202e"
	var ok_n := 0
	var form_ok := true
	for i in 20000:
		var s := ""
		var n := rng.randi_range(0, 130)
		for j in n:
			s += zeichen[rng.randi_range(0, zeichen.length() - 1)]
		if rng.randf() < 0.3:
			s = "UZAI-" + s
		var r := Einladung.code_lesen(s, t)
		if bool(r.ok):
			ok_n += 1
			form_ok = form_ok and r.kennung.size() == 16 and r.schluessel.size() == 32
	check(form_ok and ok_n <= 2, "20000 zufällige Eingaben: kein Absturz, %d zufällig gültig" % ok_n)
	var gut := 0
	for i in 5000:
		var s := ""
		for j in 35:
			s += Einladung.B32[rng.randi_range(0, 31)]
		if bool(Einladung.code_lesen(s, t).ok):
			gut += 1
	check(gut <= 1, "5000 zufällige Codes aus dem richtigen Alphabet: %d mit passender Prüfsumme und Zeit" % gut)
	var e := Einladung.neu_code(t, 60)
	var c: String = e.code
	var heil := 0
	for i in 3000:
		var b := c.to_ascii_buffer()
		for k in rng.randi_range(1, 4):
			b[rng.randi_range(0, b.size() - 1)] = rng.randi_range(0, 255)
		var r := Einladung.code_lesen(b.get_string_from_ascii(), t)
		if bool(r.ok) and r.schluessel != e.schluessel:
			heil += 1
	check(heil == 0, "3000 verstümmelte Codes: keiner landet in einem anderen Postfach")


# --- Freundestest gegen eine nachgebaute Sandbox -----------------------------------------------------------

# --- Einladung im Chat (Phase 6: gefälscht, wiederholt, Flut) ------------------------------------------------

func _chat() -> void:
	print("Einladung im Chat")
	var t := _jetzt()
	var code := str(Einladung.neu_code(t, 60).code)
	var satz := Einladung.chat_text(code)
	check(satz.contains(Einladung.code_anzeige(code)) and not satz.contains("http") and not satz.contains("://") and satz.length() < 90,
			"gesendet wird ein kurzer Satz mit dem Code – kein Link")
	var l := Einladung.code_im_text(satz, t)
	check(bool(l.ok) and str(l.code) == code and int(l.rest_min) > 50, "der eigene Satz wird beim Freund wieder als Einladung erkannt")
	check(bool(Einladung.code_im_text("hey, schau mal: " + Einladung.code_anzeige(code).to_lower().replace("-", " ") + ". bis gleich", t).ok),
			"klein geschrieben, mit Leerzeichen, mitten im Satz: erkannt")
	check(not bool(Einladung.code_im_text(Einladung.code_anzeige(code) + "X", t).ok)
			and not bool(Einladung.code_im_text(Einladung.code_anzeige(code).left(30), t).ok),
			"zu lang (geht in einem Wort weiter) oder abgeschnitten: kein Code")
	var falsch := code.left(34) + ("0" if code[34] != "0" else "1")
	check(str(Einladung.code_im_text("UZAI-" + falsch, t).fehler) == "pruefsumme", "ein Zeichen falsch: Prüfzeichen passt nicht")
	check(str(Einladung.code_im_text(satz, t + 3 * 3600).fehler) == "abgelaufen", "abgelaufene Einladung wird nicht angeboten")
	check(str(Einladung.code_im_text("uzai ist toll, komm online", t).fehler) == "keiner" and str(Einladung.code_im_text(12345, t).fehler) == "keiner"
			and str(Einladung.code_im_text("", t).fehler) == "keiner", "Text ohne Code, leer oder kein Text: nichts")
	check(not bool(Einladung.code_im_text("x".repeat(Einladung.CHAT_MAX) + satz, t).ok) and not bool(Einladung.code_im_text("UZAI".repeat(100000) + satz,
			t).ok),
			"hinter den ersten 400 Zeichen liest Uzai nicht weiter (auch nicht bei riesigen Nachrichten)")
	var zeichen := "UZAI-0123456789ABCDEFGHJKMNPQRSTVWXYZ oil-_./:;<>\"'%{}\n\t"
	var durch := 0
	for i in 3000:
		var s := "UZAI" if i % 2 == 0 else ""
		for k in rng.randi_range(0, 60):
			s += zeichen[rng.randi() % zeichen.length()]
		if bool(Einladung.code_im_text(s, t).ok):
			durch += 1
	check(durch == 0, "3000 zufällige Nachrichten mit „UZAI“: keine geht als Einladung durch")

	var ec := EinladungChat.new()
	check(str(ec.pruefen(satz, true, false, "f1", t).grund) == "aus", "Zimmer online aus: Nachrichten werden nicht auf Einladungen gelesen")
	check(str(ec.pruefen(satz, false, true, "x9", t).grund) == "kein_freund" and str(ec.pruefen(satz, true, true, "", t).grund) == "kein_freund",
			"Text von Nicht-Freunden: übergangen")
	var a: Dictionary = ec.pruefen(satz, true, true, "f1", t)
	check(str(a.art) == "anbieten" and str(a.code) == code, "gültige Einladung eines Freundes: „Zimmer betreten“ anbieten")
	check(str(ec.pruefen(satz, true, true, "f1", t + 200).grund) == "wiederholt" and str(ec.pruefen(satz, true, true, "f2", t + 200).grund) == "wiederholt",
			"derselbe Code noch einmal (auch von einem anderen Freund weitergereicht): kein zweites Angebot")
	var zweit := Einladung.chat_text(str(Einladung.neu_code(t, 60).code))
	check(str(ec.pruefen(zweit, true, true, "f1", t + 10).grund) == "flut", "zweite Einladung desselben Freundes binnen einer Minute: übergangen")
	var angeboten := 1
	for i in 12:
		var x: Dictionary = ec.pruefen(Einladung.chat_text(str(Einladung.neu_code(t, 60).code)), true, true, "g%d" % i, t + 20 + i)
		if str(x.art) == "anbieten":
			angeboten += 1
	check(angeboten == EinladungChat.JE_10_MIN, "Flut über viele Freunde: höchstens %d Angebote in zehn Minuten" % EinladungChat.JE_10_MIN)
	check(not bool(ec.stand(code).benutzt) and bool(ec.stand(code).bekannt), "angeboten, aber noch nicht benutzt")
	ec.benutzt(code, t + 30)
	check(bool(ec.stand(code).benutzt) and not JSON.stringify(ec._gesehen).contains(code),
			"nach dem Anklopfen: benutzt; gemerkt ist nur ein Fingerabdruck, nie der Code")
	# Über die Mitteilungen: nur mit eingeschaltetem Zimmer online und nur von Freunden wird „Zimmer betreten“ angeboten.
	var merk := [Config.get_value("room.online", false), Config.get_value("room.online_hinweis", false)]
	var frisch := Einladung.chat_text(str(Einladung.neu_code(t, 60).code))
	Config.set_value("room.online", false)
	check(not Notify._zimmer_einladung(frisch, true, "steam:7", "Mila", ""), "Mitteilung: Zimmer online aus – gewöhnliche Chat-Nachricht")
	Config.set_value("room.online", true)
	Config.set_value("room.online_hinweis", true)
	check(not Notify._zimmer_einladung(frisch, false, "steam:8", "Fremder", ""), "Mitteilung: kein Freund – gewöhnliche Chat-Nachricht")
	var vorher := Toasts.history.size()
	check(Notify._zimmer_einladung(frisch, true, "steam:7", "Mila", "") and Toasts.history.size() == vorher + 1
			and str(Toasts.history[0].go_text) == "Zimmer betreten" and not str(Toasts.history[0].sub).contains("UZAI"),
			"Mitteilung: Einladung eines Freundes – „Zimmer betreten“, der Code steht nicht im Text")
	check(not Notify._zimmer_einladung(frisch, true, "steam:7", "Mila", ""), "Mitteilung: dieselbe Nachricht noch einmal – kein zweites Angebot")
	Config.set_value("room.online", merk[0])
	Config.set_value("room.online_hinweis", merk[1])
	for i in 300:
		ec.benutzt(str(Einladung.neu_code(t, 60).code), t)
	check(ec._gesehen.size() <= EinladungChat.MERK_MAX and ec._je_freund.size() <= EinladungChat.MERK_MAX, "das Gemerkte wächst nicht unbegrenzt")


func _rein(s: Nachbau, art: int, nutz: PackedByteArray) -> void:
	s.rein.append_array(ZN.rahmen(art, nutz))


func _takt(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


## Zimmer online als normale Funktion: die vier Bedingungen und die letzte Schranke vor dem Netz.
func _bedingungen() -> void:
	print("Zimmer online: Bedingungen")
	FT.abschottung_ok = false
	# Zimmer online als normale Funktion: nur mit Einstellung, Hinweis und bestandener Abschottung zugleich.
	var merk := [Config.get_value("room.online", false), Config.get_value("room.online_hinweis", false), Config.get_value("room.online_test", false)]
	Config.set_value("room.online_test", false)
	Config.set_value("room.online", true)
	Config.set_value("room.online_hinweis", true)
	check(not FT.normal_an() and not FT.darf(true), "eingeschaltet und Hinweis gesehen, aber Abschottung nicht bestanden: offline")
	FT.abschottung_ok = true
	check(FT.normal_an() and FT.darf(true), "alle Bedingungen erfüllt: Zimmer online möglich")
	Config.set_value("room.online_hinweis", false)
	check(not FT.normal_an() and not FT.darf(true), "ohne den Hinweis zur IP-Adresse: offline")
	Config.set_value("room.online_hinweis", true)
	Config.set_value("room.online", false)
	check(not FT.normal_an() and not FT.darf(true), "ausgeschaltet: offline")
	var ohne_recht: Node = FT.gastgeber_starten(get_tree(), Callable(), 0, false)
	check(str(ohne_recht.zustand) == "ende" and str(ohne_recht.grund) == "start", "Start ohne erfüllte Bedingungen endet sofort (letzte Schranke vor dem Netz)")
	ohne_recht.queue_free()
	FT.aktiv = null
	Config.set_value("room.online", merk[0])
	Config.set_value("room.online_hinweis", merk[1])
	Config.set_value("room.online_test", merk[2])
	FT.abschottung_ok = false


func _gastgeber_und_gast() -> void:
	print("Freundestest, Gastgeber")
	var sb := { "gastgeber": null, "gast": null, "starts": 0 }
	var starter := func(rolle: String) -> ZN.Sitzung:
		sb[rolle] = Nachbau.new(rolle)
		sb.starts = int(sb.starts) + 1
		return sb[rolle]
	FT.abschottung_ok = false
	check(not FT.darf(true), "ohne bestandene Abschottung: kein Freundestest")
	check(not FT.abschottung_merken({ "ok": true, "secp": 1, "rtc": 1, "fehler": "admin" }, { "ok": true }), "mit Adminrechten: nein")
	var beide := FT.abschottung_merken({ "ok": true, "secp": 1, "rtc": 1 }, { "ok": true })
	check(beide and not FT.abschottung_merken({ "ok": true, "secp": 1, "rtc": 2 }, { "ok": true }),
			"nur mit beiden Bibliotheken")
	var w: Node = FT.gastgeber_starten(get_tree(), starter, 4242, false)
	var ws: Nachbau = sb.gastgeber
	check(ws != null and w.zustand == "start" and not ws.letzter(ZN.TREFF).is_empty(), "Sandbox gestartet, Treffpunkt angefragt")
	_rein(ws, ZN.STAND, PackedByteArray([1, 1, 1]))
	await _takt()
	check(w.zustand == "bereit" and w.bereit(), "Relays verbunden: bereit")
	var e: Dictionary = w.einladen("Mila", 15)
	var code: String = e.get("code", "")
	check(code.length() == 35 and ws.letzter(ZN.EINLADUNG) == (e.kennung as PackedByteArray) + (e.schluessel as PackedByteArray)
			and w.einladung_rest() > 14 * 60,
			"Einladung: Postfach in der Sandbox offen, Restzeit sichtbar")
	# Zurückziehen und neu.
	var alt_k: PackedByteArray = e.kennung
	check(w.zurueckziehen() and ws.letzter(ZN.ZURUECK) == alt_k and w.einladung_rest() == 0, "zurückgezogen: Postfach zu")
	e = w.einladen("Mila", 15)
	code = e.code
	var fp := "a1b2c3d4e5f60718"
	var gemeldet := []
	w.klopft.connect(func(id: String, n: String) -> void: gemeldet.append([id, n]))
	_rein(ws, ZN.KLOPFT, (e.kennung as PackedByteArray) + fp.hex_decode())
	_rein(ws, ZN.KLOPFT, alt_k + "0f1e2d3c4b5a6978".hex_decode())     # zurückgezogene Einladung
	await _takt()
	check(gemeldet.size() == 1 and gemeldet[0][1] == "Mila" and w.anklopfer.size() == 1, "„Mila möchte rein“ – Name aus der Einladung, die alte bleibt still")
	check(w.annehmen(fp) == "ok" and w.gaeste.has(0) and ws.letzter(ZN.ENTSCHEID) == fp.hex_decode() + PackedByteArray([0]) and w.einladung.is_empty(),
			"hereingelassen: Platz 0, Einladung verbraucht")
	_rein(ws, ZN.STAND, PackedByteArray([6, 0, 0]))
	await _takt()
	check(ws.gesendet() == ["hallo"] and w.figuren().is_empty(), "verbunden: „hallo“ hinaus, vor dem „hallo“ des Gastes zählt nichts")
	_rein(ws, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("pos", { "x": 100, "y": 0, "z": 100, "yaw": 0, "pitch": 0 }))
	_rein(ws, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("hallo", { "geraet": "uzai" }))
	await _takt()
	var f: Dictionary = w.figuren()
	check(f.has("p0") and int(f.p0.pos_n) == 0 and ws.gesendet().slice(0, 4) == ["hallo", "figur", "pos", "zimmer"],
			"„hallo“ des Gastes: Figur, Lage und Zimmer hinaus (%s)" % str(ws.gesendet()))
	w.ich_setzen(Vector3(2.5, 0, 3.0), 1.0, -0.2)
	w.emote_senden("winken")
	w.satz_senden("hallo")
	w.emote_senden("gibts_nicht")
	await _takt(10)
	var g := ws.gesendet()
	check("emote" in g and "satz" in g and g.count("emote") == 1, "Emote und Schnellsatz hinaus, unbekanntes Emote nicht")
	var figur_neu: Dictionary = P.lesen(P.schreiben("figur", { "figur": { "person": "ben" }, "tier": {} }), false).d
	_rein(ws, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("pos", { "x": 120, "y": 0, "z": 340, "yaw": 1571, "pitch": 0 }))
	_rein(ws, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("emote", { "id": "tanzen" }))
	_rein(ws, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("satz", { "id": "gg" }))
	_rein(ws, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("figur", { "figur": figur_neu.figur, "tier": figur_neu.tier }))
	await _takt()
	f = w.figuren()
	check(f.has("p0") and f.p0.p.is_equal_approx(Vector3(1.2, 0, 3.4)) and absf(float(f.p0.yaw) - 1.571) < 0.001 and f.p0.emote == "tanzen"
			and int(f.p0.emote_n) == 1
			and f.p0.satz == "gg" and str(f.p0.figur.person) == "ben", "vom Gast: Lage, Blick, Emote, Schnellsatz, Figur")
	check(f.has("p0") and str(f.p0.name) == "Mila", "angezeigt wird „Mila“ (aus der Einladung)")
	w.rauswerfen(0)
	check(w.gaeste.is_empty() and ws.letzter(ZN.SCHLIESSEN) == PackedByteArray([0]), "rausgeworfen: Platz zu")
	_rein(ws, ZN.KLOPFT, (e.kennung as PackedByteArray) + "deadbeef00c0ffee".hex_decode())
	await _takt()
	check(gemeldet.size() == 1 and w.anklopfer.is_empty() and ws.letzter(ZN.ENTSCHEID) == "deadbeef00c0ffee".hex_decode() + PackedByteArray([0xFF]),
			"dieselbe Einladung noch einmal: still abgewiesen")
	# Ein Gast, der kein „hallo“ schickt (andere Fassung), fliegt nach der Frist raus.
	e = w.einladen("Ben", 15)
	_rein(ws, ZN.KLOPFT, (e.kennung as PackedByteArray) + "1234abcd5678ef90".hex_decode())
	await _takt()
	w.annehmen("1234abcd5678ef90")
	_rein(ws, ZN.STAND, PackedByteArray([6, 0, 0]))
	await _takt()
	w.gaeste[0].seit_verbunden = -1000.0
	await _takt()
	check(w.gaeste.is_empty(), "kein „hallo“ (andere Fassung): nach der Frist raus")
	# Ein Gast schickt ein Zimmer: Prüfmauer 1 hätte das abweisen müssen – Uzai glaubt der Sandbox nicht mehr.
	_rein(ws, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("zimmer", { "raum": P.Daten.standard_raum() }))
	await _takt()
	check(w.zustand == "ende" and w.grund == "leitung" and ws.ende, "Zimmer von einem Gast: Leitung zu, Sandbox beendet")

	print("Freundestest, Gast")
	var gst: Node = FT.gast_starten(get_tree(), "UZAI-" + "0".repeat(35), starter, 4242, false)
	check(gst.zustand == "ende" and gst.grund == "code" and sb.gast == null, "falscher Code: gar nicht erst angeklopft (keine Sandbox)")
	gst = FT.gast_starten(get_tree(), Einladung.neu_code(_jetzt() - 3600, 15).code, starter, 4242, false)
	check(gst.zustand == "ende" and gst.grund == "abgelaufen" and sb.gast == null, "abgelaufener Code: „Einladung abgelaufen“")
	var e3 := Einladung.neu_code(_jetzt(), 15)
	gst = FT.gast_starten(get_tree(), Einladung.code_anzeige(e3.code).to_lower(), starter, 4242, false)
	var gs: Nachbau = sb.gast
	check(gs != null and gst.zustand == "klopft" and gs.letzter(ZN.BESUCH) == (e3.kennung as PackedByteArray) + (e3.schluessel as PackedByteArray),
			"Code eingegeben: „Klopfe an …“ mit Kennung und Schlüssel des Gastgebers")
	_rein(gs, ZN.STAND, PackedByteArray([2, 0, 0]))
	await _takt()
	check(gst.zustand == "angenommen", "„Hereingelassen“")
	_rein(gs, ZN.STAND, PackedByteArray([6, 0, 0]))
	await _takt()
	check(gst.zustand == "verbinde" and gs.gesendet() == ["hallo"] and not FT.verbunden(), "Kanal offen: „hallo“ hinaus, wartet auf den Gastgeber")
	_rein(gs, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("hallo", { "geraet": "uzai" }))
	_rein(gs, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("zimmer", { "raum": P.Daten.standard_raum() }))
	_rein(gs, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("pos", { "x": 300, "y": 0, "z": 200, "yaw": -800, "pitch": 0 }))
	await _takt()
	f = gst.figuren()
	check(gst.zustand == "verbunden" and FT.verbunden() and f.has("gastgeber") and str(f.gastgeber.name) == "Gastgeber", "„Verbunden“: der Gastgeber ist da")
	check(not gst.gast_raum.is_empty() and int(gst.raum_stand) == 1 and f.has("gastgeber") and f.gastgeber.p.is_equal_approx(Vector3(3, 0, 2)),
			"Zimmer und Lage des Gastgebers da (geprüft)")
	gst.ich_setzen(Vector3(1, 0, 1), 0.5, 0.0)
	await _takt(12)
	check("pos" in gs.gesendet() and "figur" in gs.gesendet(), "eigene Figur und Lage hinaus")
	_rein(gs, ZN.STAND, PackedByteArray([7, 0, 0]))
	await _takt()
	check(gst.zustand == "ende" and gst.grund == "zu" and gs.ende and not FT.verbunden(), "Gastgeber beendet: „Verbindung beendet“, Sandbox zu")
	# Fristen: keine Antwort aufs Anklopfen, keine Direktverbindung.
	gst = FT.gast_starten(get_tree(), Einladung.neu_code(_jetzt(), 15).code, starter, 4242, false)
	gst._seit = FT.KLOPF_FRIST + 1.0
	await _takt()
	check(gst.grund == "keine_antwort", "ohne Annahme: „Keine Antwort“ nach der Frist")
	gst = FT.gast_starten(get_tree(), Einladung.neu_code(_jetzt(), 15).code, starter, 4242, false)
	gs = sb.gast
	_rein(gs, ZN.STAND, PackedByteArray([2, 0, 0]))
	await _takt()
	gst._seit = FT.VERBINDEN_FRIST + 1.0
	await _takt()
	check(gst.grund == "direkt" and str(gst.stand_text()).contains("Direktverbindung"), "angenommen, aber keine Direktverbindung: Grund genannt")
	# Gast verlässt: „tschuess“, dann zu.
	gst = FT.gast_starten(get_tree(), Einladung.neu_code(_jetzt(), 15).code, starter, 4242, false)
	gs = sb.gast
	_rein(gs, ZN.STAND, PackedByteArray([2, 0, 0]))
	_rein(gs, ZN.STAND, PackedByteArray([6, 0, 0]))
	_rein(gs, ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben("hallo", { "geraet": "uzai" }))
	await _takt()
	gst.beenden()
	await get_tree().create_timer(FT.ABSCHIED + 0.3).timeout
	check(gs.gesendet().has("tschuess") and gs.ende and gst.grund == "verlassen", "Besuch verlassen: „tschuess“, dann Sandbox zu")
	# Protokoll: Schritte ja, Geheimnisse nein.
	var log := FileAccess.get_file_as_string(Config.path(FT.LOG))
	var geheim := [code, Einladung.code_anzeige(code), e3.code, (e3.kennung as PackedByteArray).hex_encode(), (e3.schluessel as PackedByteArray).hex_encode(),
			Einladung.b64url(e3.schluessel), "Mila", "Ben", fp]
	var sauber := log.length() > 200
	for x in geheim:
		sauber = sauber and not log.contains(str(x))
	check(sauber and log.contains("Einladung erstellt") and log.contains("Ende: zu"), "logs/zimmer_online.log: Schritte und Gründe, kein Code, Schlüssel, Name")
	if is_instance_valid(FT.aktiv):
		FT.aktiv.queue_free()


func _quelltext() -> void:
	print("Quelltext")
	var verboten := ["str_to_var", "bytes_to_var", "Expression", "ResourceLoader", "JSON", "base64_to_variant", "OS.shell_open", "OS.execute("]
	var sauber := true
	for d in ["res://src/room/freundestest.gd", "res://src/room/einladung.gd", "res://src/room/besucher.gd"]:
		var s := FileAccess.get_file_as_string(d)
		for v in verboten:
			if s.contains(v):
				sauber = false
				print("    ", d.get_file(), ": ", v)
	check(sauber, "Freundestest, Code-Leser, Besucher: nichts wird ausgeführt oder als Ressource geladen")
