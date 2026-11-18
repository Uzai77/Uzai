extends "res://tests/probe_base.gd"
## Bau-Menü im Zimmer (katalog_ui.gd): erst wählen, dann platzieren – das Menü mit gewähltem Möbel,
## das Möbel am Cursor (grün: passt), Absetzen führt zurück ins Menü, B legt es zurück. Prüft dabei den
## Ablauf (Zeilen „PRUEFUNG“ im Protokoll). Aufruf wie in probe_base.gd.

const Daten := preload("res://src/room/zimmer_daten.gd")

var z: Control
var fehler := 0


func pruefe(ok: bool, was: String) -> void:
	print("PRUEFUNG ", "ok   " if ok else "FAIL ", was)
	if not ok:
		fehler += 1


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.0)
	main.open_room(true)
	await wait(3.0)
	z = Nav.top_layer()
	z.raum.licht.z = "abend"
	z._licht_neu()
	await press("view")
	await wait(0.8)
	var vorher := (z.raum.moebel as Array).size()
	pruefe(z.modus == "bauen" and not z._katalog.call("ist_offen"), "Bauen: das Menü ist zu, nur die Leiste")
	await press("rt")
	await wait(3.0)
	await press("right", 2)
	await wait(0.6)
	pruefe(z.modus == "katalog" and (z._halten as Dictionary).is_empty(), "Wählen im Menü: noch nichts im Zimmer")
	await shot("01_menue", 2.0)
	var id := str(z._katalog.call("gewaehlt"))
	await press("a")
	await wait(0.6)
	pruefe(z.modus == "bauen" and str(z._halten.get("t", "")) == id and z._halten_idx < 0 and not z._katalog.call("ist_offen"),
		"A: %s hängt am Cursor, das Menü tritt zurück" % id)
	var x0 := int(z._halten.x)
	var z0 := int(z._halten.z)
	await press("right", 2, 0.25)
	await press("down", 1, 0.25)
	pruefe(int(z._halten.x) != x0 or int(z._halten.z) != z0, "Steuerkreuz schiebt das Möbel")
	await press("rb")
	# Bis es passt, weiterschieben (höchstens ein paar Schritte): das Feld darunter wird grün.
	for _k in 8:
		if Daten.passt(z.raum, z._halten, -1):
			break
		await press("left", 1, 0.25)
	await shot("02_platzieren", 1.0)
	await press("a")
	await wait(0.8)
	pruefe((z.raum.moebel as Array).size() == vorher + 1 and z.modus == "katalog" and str(z._katalog.call("gewaehlt")) == id,
		"A setzt ab, zurück im Menü bei derselben Kachel")
	await press("a")
	await wait(0.5)
	await press("b")
	await wait(0.6)
	pruefe(z.modus == "katalog" and (z.raum.moebel as Array).size() == vorher + 1, "B legt es zurück ins Menü")
	await press("b")
	await wait(0.6)
	pruefe(not z._katalog.call("ist_offen") and z._katalog._bilder._warte.is_empty(), "Menü zu: nichts wartet auf ein Bild")
	print("PRUEFUNG Ergebnis: ", "alles ok" if fehler == 0 else "%d Fehler" % fehler)
