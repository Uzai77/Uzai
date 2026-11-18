extends "res://tests/probe_base.gd"
## Umbauen beim Laufen (zimmer_umbau.gd): ein Möbel mit gehaltenem A nehmen und vor dir tragen (Feld
## grün), eine Wand nach außen ziehen (Geisterwand, was an ihr steht, rückt mit), eine Hülle im Regal
## von Hand umstellen. Prüft den Ablauf (Zeilen „PRUEFUNG“). Aufruf wie in probe_base.gd.

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")

var z: Control
var fehler := 0


func pruefe(ok: bool, was: String) -> void:
	print("PRUEFUNG ", "ok   " if ok else "FAIL ", was)
	if not ok:
		fehler += 1


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


## A gedrückt halten (wie am Controller): erst die Taste, dann so lange warten.
func halten_a(sek := 0.7) -> void:
	Input.action_press("uz_a")
	Nav._fire("a")
	await wait(sek)
	Input.action_release("uz_a")
	await wait(0.2)


func blick_auf(p: Vector3) -> void:
	var dir := p - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	z._ziel = -2
	z._ziel_suchen()


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.0)
	main.open_room(true)
	await wait(3.0)
	z = Nav.top_layer()
	z.raum.licht.z = "abend"
	z._licht_neu()
	z.blick = "ich"
	var zl := Katalog.ZELLE

	# --- 1. Tragen beim Laufen: Sitzsack mit gehaltenem A, vor dir am Raster.
	var s := idx("sitzsack")
	z.pos = Vector3(3.6, 0, 2.6)
	blick_auf((z.welt.boxen[s] as AABB).get_center())
	await wait(0.5)
	pruefe(z._ziel == s and str(z._schild_aktion()[1]).contains("Verschieben"), "Schild am Sitzsack: „Halten: Verschieben“ (%s)" % str(z._schild_aktion()))
	var vorher := Vector2i(int(z.raum.moebel[s].x), int(z.raum.moebel[s].z))
	await halten_a()
	pruefe(z.modus == "laufen" and z._lauf_tragen and z._halten_idx == s, "A halten: der Sitzsack schwebt vor dir, du läufst weiter")
	# Eine freie Stelle suchen und hinschauen (zielen mit dem Stick).
	var frei := Vector2i(-1, -1)
	for zz in range(2, 8):
		for xx in range(5, 9):
			var probe: Dictionary = (z._halten as Dictionary).duplicate()
			probe.x = xx
			probe.z = zz
			if frei.x < 0 and Daten.passt(z.raum, probe, s):
				frei = Vector2i(xx, zz)
	z.pos = Vector3((frei.x + 1.0) * zl, 0, minf((frei.y + 1.0) * zl + 2.0, float(z.raum.d) * zl - 0.3))
	z._koerper_setzen(z.pos)
	blick_auf(Vector3((frei.x + 1.0) * zl, 0.0, (frei.y + 1.0) * zl))
	await wait(0.4)
	z._ziel_suchen()
	pruefe(Daten.passt(z.raum, z._halten, s), "Blick auf eine freie Stelle: Feld grün (%s)" % str(Vector2i(int(z._halten.x), int(z._halten.z))))
	await shot("01_tragen", 1.0)
	Nav._fire("a")
	await wait(0.8)
	var nachher := Vector2i(int(z.raum.moebel[s].x), int(z.raum.moebel[s].z))
	pruefe(not z._lauf_tragen and nachher != vorher and z.modus == "laufen", "A setzt ab, ohne Bauen und ohne Ansicht von oben (%s → %s)" % [vorher, nachher])

	# --- 2. Raum größer: vor der rechten Wand A halten, Steuerkreuz nach außen.
	var w0 := int(z.raum.w)
	z.pos = Vector3(float(w0) * zl - 1.5, 0, 3.75)
	z._koerper_setzen(z.pos)
	z.yaw = -PI * 0.5
	z._yaw_soll = z.yaw
	z.pitch = 0.05
	z._ziel = -2
	z._ziel_suchen()
	await wait(0.4)
	pruefe(z._ziel_wand == "rechts" or z._ziel >= 0, "vor der Wand: „Raum größer/kleiner“ (%s, Ziel %d)" % [z._ziel_wand, z._ziel])
	if z._ziel_wand == "rechts":
		await halten_a()
	else:
		z._wand_ziehen_auf("rechts")
	pruefe(z.modus == "wand", "Wand ziehen")
	await press("up", 2, 0.3)
	pruefe(int(z._wz.delta) == 2 and bool(z._wz.plan.ok), "Steuerkreuz: zwei Felder nach außen, nichts im Weg (%s)" % str(z._wz.plan.get("mit", [])))
	await shot("02_wand", 1.2)
	Nav._fire("a")
	await wait(1.2)
	pruefe(int(z.raum.w) == w0 + 2 and z.modus == "laufen", "A übernimmt: der Raum ist breiter (%d → %d)" % [w0, int(z.raum.w)])

	# --- 3. Regal von Hand: eine Hülle nehmen, ein Fach höher liegend hinlegen.
	var r := idx("spieleregal")
	z.regal_setzen(r, "fi", "alle")
	await wait(0.6)
	z._ansehen(r)
	await wait(1.2)
	# Umstellen steht im Menü des Regals (Y, erster Eintrag), nicht mehr auf RB: nichts verrutscht aus Versehen.
	Nav._fire("y")
	await wait(0.4)
	Nav._fire("a")
	await wait(0.4)
	pruefe(not (z._hand as Dictionary).is_empty(), "Y, „Umstellen“: die Hülle in der Hand")
	var gid := str(z._hand.get("id", ""))
	Nav._fire("up")
	await wait(0.3)
	for _k in 3:
		if str(z._hand.lage) == "liegend":
			break
		Nav._fire("rb")
		await wait(0.3)
	if not z._hand_passt():
		Nav._fire("left")
		await wait(0.3)
	await shot("03_regal_hand", 1.2)
	var fach := int(z._hand.get("fach", 0))
	Nav._fire("a")
	await wait(1.0)
	var rg: Dictionary = z.raum.moebel[r].get("rg", {})
	var pl: Dictionary = rg.get("pl", {})
	var lg: Dictionary = rg.get("lg", {})
	pruefe(str(rg.get("so", "")) == "manuell" and int(pl.get(gid, -9)) == fach and str(lg.get(gid, "")) == "liegend",
		"A legt sie hin: eigene Ordnung mit Fach und Lage (%s)" % str(rg.get("lg", {})))
	var da := false
	for p in z.welt.plaetze.get(r, []):
		if str(p.daten.get("id", "")) == gid and int(p.fach) == fach and str(p.get("lage", "")) == "liegend":
			da = true
	pruefe(da, "im Regal liegt sie im neuen Fach")
	print("PRUEFUNG Ergebnis: ", "alles ok" if fehler == 0 else "%d Fehler" % fehler)
