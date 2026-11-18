extends Node
## Der Ausgang der Leitung zur Zimmer-Sandbox (src/room/zimmer_netz.gd, Sitzung): Warteschlange, Fenster und
## Quittungen gegen eine Pipe-Attrappe, die sich wie Uzais Pipe unter Windows verhält (Godot öffnet sie ohne
## Warten: PIPE_NOWAIT, 4 KiB Puffer). Dort ging am PC ein Rahmen still verloren (0.16.33, „pruefung v52/53“):
## Was nicht ganz in den Puffer passt, schreibt Windows nicht – oder nur den Teil, den ein wartendes Lesen
## gerade nimmt. Geprüft: kein Rahmen geht verloren, der Strom reißt nie, kein Stillstand, Grenzen schließen
## die Leitung sauber, Quittungen werden geprüft.
## Aufruf: godot --headless --path . res://tests/logic_zimmer_leitung.tscn

const ZN := preload("res://src/room/zimmer_netz.gd")
const P := preload("res://src/room/netz_protokoll.gd")

var fails := 0
var rng := RandomNumberGenerator.new()


## Uzais Pipe zur Sandbox unter Windows, ohne Warten (nach FileAccessWindowsPipe::store_buffer und WriteFile auf
## einer anonymen Pipe im Modus PIPE_NOWAIT): Ein wartendes Lesen der Sandbox nimmt sofort, was es will; passt der
## Rest nicht ganz in den freien Puffer, bleibt er draußen und store_buffer meldet nur false.
class Pipe:
	var quote := 4096
	var puffer := PackedByteArray()      ## liegt in der Pipe
	var wartet := 0                      ## die Sandbox wartet mit einem Lesen dieser Größe (0 = nein)
	var angekommen := PackedByteArray()  ## was die Sandbox gelesen hat
	var hoechst := 0                     ## höchster Pufferstand
	var fehlschlaege := 0
	var teilweise := 0                   ## Schreibvorgänge, von denen nur ein Teil ankam (Strom gerissen)

	func schreiben(b: PackedByteArray) -> bool:
		var direkt := 0
		if wartet > 0 and puffer.is_empty():
			direkt = mini(wartet, b.size())
			angekommen.append_array(b.slice(0, direkt))
			wartet = 0
		if b.size() - direkt > quote - puffer.size():
			fehlschlaege += 1
			if direkt > 0:
				teilweise += 1
			return false
		puffer.append_array(b.slice(direkt))
		hoechst = maxi(hoechst, puffer.size())
		return true

	## Wie ReadFile: bis zu n Bytes; ist nichts da, wartet die Sandbox (blockierend) mit n.
	func lesen(n: int) -> int:
		if puffer.is_empty():
			wartet = n
			return 0
		var k := mini(n, puffer.size())
		angekommen.append_array(puffer.slice(0, k))
		puffer = puffer.slice(k)
		return k


## Die Sandbox-Seite wie UzaiZimmerNetz.Netz mit UzQuittEin: liest Rahmen wie UzNetzRahmen.Genau (erst 4 Byte
## Länge, dann den Rest) und quittiert vor jedem Lesen, sobald AB Bytes offen sind.
class Sandbox:
	const AB := 512
	var pipe: Pipe
	var quittiert := 0
	var quittungen := true
	var _start := 0

	func _init(p: Pipe) -> void:
		pipe = p

	func _bedarf() -> int:
		var a := pipe.angekommen
		var da := a.size() - _start
		while da >= 4 and da >= 4 + a.decode_u32(_start):
			_start += 4 + a.decode_u32(_start)
			da = a.size() - _start
		return 4 - da if da < 4 else 4 + a.decode_u32(_start) - da

	## Bis zu `lesungen` Lesevorgänge; Quittungen gehen an die Sitzung zurück.
	func schritt(lesungen: int, s: ZN.Sitzung) -> void:
		for i in lesungen:
			# Gelesen ist alles, was angekommen ist – auch was ein wartendes Lesen direkt aus einem Schreibvorgang nahm.
			var gelesen := pipe.angekommen.size()
			if quittungen and gelesen - quittiert >= AB:
				var q := PackedByteArray([0, 0, 0, 0])
				q.encode_u32(0, gelesen & 0xFFFFFFFF)
				(s as Attrappe).zurueck.append_array(_rahmen(ZN.QUITTUNG, q))
				quittiert = gelesen
			if pipe.lesen(_bedarf()) == 0:
				return

	static func _rahmen(art: int, nutz: PackedByteArray) -> PackedByteArray:
		var b := PackedByteArray([0, 0, 0, 0, art])
		b.encode_u32(0, nutz.size() + 1)
		return b + nutz


## Die Sitzung mit der Attrappe statt des Prozesses.
class Attrappe extends ZN.Sitzung:
	var pipe: Pipe
	var zurueck := PackedByteArray()   ## Sandbox → Uzai
	var max_offen := 0                 ## größter unquittierter Stand nach einem Schreibvorgang

	func _init(p: Pipe) -> void:
		pipe = p
		leitung = ZN.Leitung.new("gastgeber")

	func _lesen() -> PackedByteArray:
		var b := zurueck
		zurueck = PackedByteArray()
		return b

	func _schreiben(b: PackedByteArray) -> bool:
		var ok := pipe.schreiben(b)
		max_offen = maxi(max_offen, leitung.geschrieben + b.size() - leitung.quittiert)
		return ok


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	rng.seed = 1633
	_modell()
	_ohne_verlust()
	_grenzen()
	_quittung()
	_beenden()
	_zaehler()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Dieselben Rahmen wie „Abschottung prüfen“ (ZN.pruefen): gute und böse Pakete (darunter 5000 Byte), Flut in
## einem Stück, Dauer-Unsinn, Ausgehendes, Zähler.
func _pruef_rahmen() -> Array:
	var l := ZN.Leitung.new("gastgeber")
	var out: Array = [ZN.rahmen(ZN.PING, Crypto.new().generate_random_bytes(300))]
	for f in ZN.faelle():
		out.append(l.test_rein(1, f[0]))
	var flut := PackedByteArray()
	for i in 60:
		flut.append_array(l.test_rein(2, P.schreiben("pos", { "x": 100 + i, "y": 0, "z": 100, "yaw": 0, "pitch": 0 })))
	out.append(flut)
	for i in 40:
		out.append(l.test_rein(3, PackedByteArray([P.MAGIC, P.VERSION, 2, i])))
	out.append(l.senden(1, "zimmer", { "raum": P.Daten.standard_raum() }))
	out.append(ZN.rahmen(ZN.ZAEHLER))
	return out


func _alles(rahmen: Array) -> PackedByteArray:
	var b := PackedByteArray()
	for r in rahmen:
		b.append_array(r)
	return b


## Die Attrappe verhält sich wie am PC: ohne Fenster geschrieben gehen Rahmen verloren oder reißen.
func _modell() -> void:
	print("Pipe ohne Warten (Attrappe wie unter Windows)")
	var p := Pipe.new()
	check(not p.schreiben(_leer(5006)) and p.puffer.is_empty(), "5006 Byte in eine leere 4-KiB-Pipe: nichts geschrieben, store_buffer false")
	var p2 := Pipe.new()
	var verloren := 0
	for r in _pruef_rahmen():
		if not p2.schreiben(r):     # so schrieb Sitzung.schicken bis 0.16.33 (Ergebnis ungeprüft)
			verloren += 1
		p2.lesen(rng.randi_range(0, 600))
	check(verloren > 0, "die Rahmen von „Abschottung prüfen“ direkt geschrieben: %d gehen still verloren (PC: 52 statt 53)" % verloren)
	var p3 := Pipe.new()
	p3.lesen(4)                     # die Sandbox wartet auf die nächste Länge
	check(not p3.schreiben(_leer(5006)) and p3.teilweise == 1 and p3.angekommen.size() == 4, "wartet die Sandbox gerade, kommen nur 4 Byte an: der Strom risse")


func _leer(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(P.MAGIC)
	return b


## Mit Warteschlange und Fenster: alles kommt genau an, in Reihenfolge, nie mehr als FENSTER in der Pipe.
func _ohne_verlust() -> void:
	print("Warteschlange und Fenster")
	var laeufe := 0
	var gut := 0
	var hoechst := 0
	var offen := 0
	for lauf in 40:
		var rahmen := _pruef_rahmen() if lauf < 20 else _zufall_rahmen(rng.randi_range(1, 120))
		var p := Pipe.new()
		var s := Attrappe.new(p)
		var sb := Sandbox.new(p)
		if lauf % 3 == 0:
			sb.schritt(1, s)          # die Sandbox wartet schon (Lesen offen)
		var gesendet := 0
		var i := 0
		var t := 0.0
		while i < 4000 and (gesendet < rahmen.size() or s.wartend() > 0 or not p.puffer.is_empty()):
			i += 1
			# Uzai schickt manchmal viele auf einmal, manchmal keinen; die Sandbox ist mal schnell, mal träge.
			for k in rng.randi_range(0, 8):
				if gesendet < rahmen.size():
					s.schicken(rahmen[gesendet])
					gesendet += 1
			sb.schritt(rng.randi_range(0, 6) if lauf % 2 == 0 else rng.randi_range(0, 2), s)
			t += 0.016
			s.pumpen(t)
		laeufe += 1
		if p.angekommen == _alles(rahmen) and p.fehlschlaege == 0 and s.leitung.kaputt == "" and s.wartend() == 0:
			gut += 1
		else:
			print("    Lauf %d: %d/%d Byte, Fehlschläge %d, kaputt „%s“, wartend %d" % [lauf, p.angekommen.size(), _alles(rahmen).size(), p.fehlschlaege,
					s.leitung.kaputt, s.wartend()])
		hoechst = maxi(hoechst, p.hoechst)
		offen = maxi(offen, s.max_offen)
	check(gut == laeufe, "%d Läufe (Prüf-Rahmen und Zufall bis 8 KiB, Sandbox mal schnell, mal träge): jedes Byte genau einmal, in Reihenfolge, kein Fehlschlag" % laeufe)
	check(hoechst <= ZN.FENSTER and offen <= ZN.FENSTER, "nie mehr als das Fenster unquittiert (höchstens %d Byte in der Pipe, Fenster %d)" % [hoechst, ZN.FENSTER])
	# Kein Stillstand: Die Sandbox liest alles und wartet; offen bleibt weniger als AB – Uzai schreibt weiter.
	var p2 := Pipe.new()
	var s2 := Attrappe.new(p2)
	var sb2 := Sandbox.new(p2)
	s2.schicken(ZN.rahmen(ZN.PING, _leer(ZN.MAX_RAHMEN)))
	for k in 20:
		sb2.schritt(50, s2)
		s2.pumpen(0.0)
	check(p2.angekommen.size() == ZN.MAX_RAHMEN + 5 and s2.wartend() == 0, "ein Rahmen größer als Fenster und Pipe (8 KiB) kommt in Stücken ganz an")


func _zufall_rahmen(n: int) -> Array:
	var out: Array = []
	for i in n:
		var g := rng.randi_range(0, ZN.MAX_RAHMEN) if rng.randf() < 0.1 else rng.randi_range(0, 200)
		var b := PackedByteArray()
		b.resize(g)
		for k in g:
			b[k] = rng.randi() & 0xFF
		out.append(ZN.rahmen(ZN.PING, b))
	return out


## Grenzen: Ein Schreibvorgang scheitert trotz Fenster (Pipe kleiner als gedacht) → Leitung zu, nichts weiter;
## die Sandbox liest nicht mehr → Warteschlange voll → Leitung zu.
func _grenzen() -> void:
	print("Grenzen")
	var p := Pipe.new()
	p.quote = 1000
	var s := Attrappe.new(p)
	s.schicken(ZN.rahmen(ZN.PING, _leer(2000)))
	var vorher := p.puffer.size()
	s.schicken(ZN.rahmen(ZN.PING, _leer(10)))
	s.pumpen(0.0)
	check(s.leitung.kaputt == "schreiben" and s.wartend() == 0 and p.puffer.size() == vorher, "Schreiben scheitert trotz Fenster: Leitung zu („schreiben“), danach geht nichts mehr hinaus")
	var p2 := Pipe.new()
	var s2 := Attrappe.new(p2)
	var n := 0
	while s2.leitung.kaputt == "" and n < 1000:
		s2.schicken(ZN.rahmen(ZN.PING, _leer(4000)))
		n += 1
	check(s2.leitung.kaputt == "voll" and n * 4005 > ZN.MAX_WARTEND and s2.wartend() == 0 and p2.fehlschlaege == 0,
			"Sandbox liest nicht: nach %d KiB Warteschlange Leitung zu („voll“), nichts still verloren" % (ZN.MAX_WARTEND / 1024))
	check(p2.puffer.size() <= ZN.FENSTER, "in der Pipe nie mehr als das Fenster")


func _q(n: int) -> PackedByteArray:
	var b := PackedByteArray([0, 0, 0, 0])
	b.encode_u32(0, n & 0xFFFFFFFF)
	return Sandbox._rahmen(ZN.QUITTUNG, b)


## Quittungen der Sandbox sind fremde Daten: genau 4 Byte, nie mehr als geschrieben, nie rückwärts.
func _quittung() -> void:
	print("Quittungen")
	var l := ZN.Leitung.new("gastgeber")
	l.geschrieben = 100
	check(l.eingang(_q(50), 1.0).is_empty() and l.quittiert == 50 and l.kaputt == "", "Quittung bis 50 von 100: angenommen, kein Ereignis")
	check(l.eingang(_q(50), 1.0).is_empty() and l.quittiert == 50 and l.kaputt == "", "dieselbe noch einmal: nichts Neues")
	var faelle := { "mehr als geschrieben": _q(101), "rückwärts": _q(40), "zu kurz": Sandbox._rahmen(ZN.QUITTUNG, PackedByteArray([1, 2, 3])),
			"zu lang": Sandbox._rahmen(ZN.QUITTUNG, PackedByteArray([1, 2, 3, 4, 5])) }
	var zu := 0
	for k in faelle:
		var lk := ZN.Leitung.new("gastgeber")
		lk.geschrieben = 100
		lk.quittiert = 50
		lk.eingang(faelle[k], 1.0)
		if lk.kaputt == "quittung":
			zu += 1
		else:
			print("    bleibt offen: ", k)
	check(zu == faelle.size(), "Leitung zu bei: %s" % ", ".join(faelle.keys()))
	var lw := ZN.Leitung.new("gastgeber")
	lw.quittiert = 4294967296 - 10
	lw.geschrieben = 4294967296 + 100
	lw.eingang(_q(50), 1.0)
	check(lw.kaputt == "" and lw.quittiert == 4294967296 + 50, "Zähler über 4 GiB (u32 läuft über): richtig weitergezählt")
	check(ZN.rahmen(ZN.QUITTUNG).is_empty(), "Uzai selbst baut keine Quittung (nur Sandbox → Uzai)")


## beenden(): Wartendes fällt weg, ein angefangener Rahmen wird fertig, dann ENDE – der Strom bleibt heil.
func _beenden() -> void:
	print("Ende")
	var p := Pipe.new()
	var s := Attrappe.new(p)
	var sb := Sandbox.new(p)
	var gross := ZN.rahmen(ZN.PING, _leer(ZN.MAX_RAHMEN))
	s.schicken(gross)
	for i in 5:
		s.schicken(ZN.rahmen(ZN.PING, _leer(100)))
	s.beenden()
	for k in 30:
		sb.schritt(50, s)
		s.pumpen(0.0)
	check(p.angekommen == gross + ZN.rahmen(ZN.ENDE) and s.wartend() == 0, "angefangener Rahmen ganz, dann ENDE; Wartendes verworfen")
	var p2 := Pipe.new()
	var s2 := Attrappe.new(p2)
	s2.beenden()
	check(p2.puffer == ZN.rahmen(ZN.ENDE), "ohne Wartendes: ENDE sofort")


## ZAEHLER der Sandbox: Fassung 5 mit der Zahl der TEST_REIN-Rahmen (20 Byte), ältere mit 16.
func _zaehler() -> void:
	print("Zähler und Grund")
	var z := PackedByteArray()
	z.resize(20)
	for i in 5:
		z.encode_u32(i * 4, i + 1)
	var l := ZN.Leitung.new("gastgeber")
	var e := l.eingang(ZN.rahmen(ZN.ZAEHLER, z), 1.0)
	check(e.size() == 1 and e[0].rein == 5 and e[0].aus_verworfen == 4, "20 Byte: angekommene TEST_REIN-Rahmen gelesen")
	var e2 := l.eingang(ZN.rahmen(ZN.ZAEHLER, z.slice(0, 16)), 1.0)
	check(e2.size() == 1 and e2[0].rein == -1 and l.kaputt == "", "16 Byte (ältere Sandbox): rein unbekannt (-1)")
	l.eingang(ZN.rahmen(ZN.ZAEHLER, z.slice(0, 18)), 1.0)
	check(l.kaputt == "zaehler", "andere Länge: Leitung zu")
	check(ZN._kaputt_grund("mauer1").begins_with("pruefung ") and ZN._kaputt_grund("schreiben").begins_with("leitung ")
			and ZN._kaputt_grund("quittung").begins_with("leitung "), "Grund: Prüfmauer (Sandbox ließ Falsches durch) getrennt von Leitung (Schreiben, Quittung …)")
