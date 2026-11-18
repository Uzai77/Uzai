extends Node
## Hintergrundarbeit (src/core/arbeit.gd): Ergebnisse kommen an, Kleines wartet nicht hinter Großem,
## ein Fehler lässt niemanden ewig warten, Vorladen liefert dieselbe Ressource, und Uzai beendet
## sich, auch wenn noch Aufträge warten.
## Aufruf: godot --headless --path . res://tests/logic_arbeit.tscn

const Arbeit := preload("res://src/core/arbeit.gd")

const ZUSTAND := "res://src/core/zustand.gd"

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


static func _doppelt(n: int) -> int:
	return n * 2


static func _schlafen(ms: int) -> int:
	var bis := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < bis and not Arbeit.endet:
		OS.delay_msec(5)
	return ms


static func _merken(box: Dictionary, name: String) -> void:
	(box.schloss as Mutex).lock()
	(box.folge as Array).append(name)
	(box.schloss as Mutex).unlock()


func _ready() -> void:
	print("Ergebnis")
	check(await Arbeit.ergebnis(_doppelt.bind(21)) == 42, "ergebnis() liefert den Rückgabewert")
	var a := Arbeit.auftrag(_schlafen.bind(60), Arbeit.LANG)
	check(not a.fertig and a.wert == null, "auftrag() ist erst offen")
	await a.erledigt
	check(a.fertig and a.wert == 60, "… und meldet sich im Hauptfaden mit dem Wert")
	var weg := Node.new()
	var tot := weg.get_child_count
	weg.free()
	check(await Arbeit.ergebnis(tot) == null, "Auftrag ohne Ziel: null statt Warten ohne Ende")

	print("Spuren")
	var lange: Array = []
	for i in 6:
		lange.append(Arbeit.auftrag(_schlafen.bind(400), Arbeit.LANG))
	var t0 := Time.get_ticks_msec()
	await Arbeit.ergebnis(_doppelt.bind(1), Arbeit.SOFORT)
	var sofort := Time.get_ticks_msec() - t0
	await Arbeit.ergebnis(_doppelt.bind(1))
	var kurz := Time.get_ticks_msec() - t0
	check(sofort < 200 and kurz < 200, "Symbol und Bild warten nicht hinter langer Arbeit (%d ms, %d ms)" % [sofort, kurz])
	check(not (lange[5] as Arbeit.Auftrag).fertig, "… die lange Arbeit läuft dabei noch")
	var box := { "schloss": Mutex.new(), "folge": [] }
	for i in 4:
		Arbeit.los(_merken.bind(box, "s%d" % i), Arbeit.SOFORT)
	await Arbeit.ergebnis(_doppelt.bind(1), Arbeit.SOFORT)
	check(box.folge == ["s0", "s1", "s2", "s3"], "eine Spur arbeitet der Reihe nach")
	for l: Arbeit.Auftrag in lange:
		if not l.fertig:
			await l.erledigt
	await get_tree().process_frame
	await get_tree().process_frame
	check(Arbeit.offen() == 0, "danach ist Ruhe (offen() == 0)")

	print("Vorladen")
	Arbeit.vorladen([ZUSTAND, "user://fremd.gd", "C:/fremd.gd"])
	var bis := Time.get_ticks_msec() + 5000
	while not Arbeit._geladen.has(ZUSTAND) and Time.get_ticks_msec() < bis:
		await get_tree().process_frame
	check(Arbeit._geladen.has(ZUSTAND), "vorladen() holt die Ressource im Hintergrund")
	check(Arbeit.geladen(ZUSTAND) == load(ZUSTAND), "geladen() gibt dieselbe Ressource wie load()")
	check(Arbeit.geladen("user://fremd.gd") == null and Arbeit._geladen.size() == 1, "nur Programmteile (res://), nichts von außen")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	# Mit wartender und laufender Arbeit beenden: Der Vorgang muss trotzdem sofort enden
	# (sonst läuft die Zeitgrenze des Tests ab).
	for i in 12:
		Arbeit.los(_schlafen.bind(20000), Arbeit.LANG)
	get_tree().quit(1 if fails > 0 else 0)
