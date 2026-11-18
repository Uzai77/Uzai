extends "res://tests/probe_regal.gd"
## Spieleregal im Zimmer: Hüllen wie im Regal des Hauptmenüs (Format je System, PS2 mit weißem
## Rücken und schwarzem Kopf), vor dem Regal mit dem Steuerkreuz wählen, A nimmt die Hülle heraus
## und zeigt ihr Cover, Y-Menü mit „Umstellen“, B legt zurück. Prüft den Ablauf (Zeilen
## „PRUEFUNG“). Zum Schluss dieselbe Hülle (PS2, Cover als Scan mit eigenem Band) heraus im Regal
## des Hauptmenüs und im Zimmer nebeneinander: vergleich.png. Aufruf wie in probe_base.gd.

const ZIEL := "ps2:vergleich"


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


func blick_auf(p: Vector3) -> void:
	var dir := p - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	z._ziel = -2
	z._ziel_suchen()


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	# Logos wie in probe_regal.gd (ohne Netz: Platzhalter in Uzais Schrift, nur für die Probe).
	for k in ["ps2", "ps2_wortmarke", "ps_logo_farbe", "ps_zeichen"]:
		BadgeLogos.image_for_key(k)
	await wait(3.0)
	if BadgeLogos.image_for_key("ps2_wortmarke").is_empty():
		await _platzhalter("ps2_wortmarke", "PlayStation®2")
	if BadgeLogos.image_for_key("ps_logo_farbe").is_empty():
		_platzhalter_bunt("ps_logo_farbe")
	BadgeLogos.forget()
	var scan := _motiv("scan", 512, 728, Color("#1d3557"), Color("#e63946"), 11, true)
	Library.games.append({ "id": ZIEL, "title": "Fernweh", "system": "ps2", "source": "rom", "installed": true,
		"playtime": 3600 * 12, "last_played": int(Time.get_unix_time_from_system()), "path": "D:/Spiele/PS2/SLES-54723 Fernweh.iso",
		"images": { "cover": scan } })
	main.goto("games")
	await wait(1.0)
	main.open_room(true)
	await wait(3.0)
	z = Nav.top_layer()
	z.raum.licht.z = "abend"
	z._licht_neu()
	z.blick = "ich"
	var r := idx("spieleregal")
	z.regal_setzen(r, "fi", "alle")
	await wait(0.8)
	var c := (z.welt.boxen[r] as AABB).get_center()
	z.pos = Vector3(c.x + 0.35, 0, c.z + 1.25)
	z._koerper_setzen(z.pos)
	blick_auf(c + Vector3(0, 0.15, 0))
	await wait(0.8)
	await shot("01_regal_laufen", 1.5)
	if not z.has_method("_regal_oeffnen"):
		z._ansehen(r)
		await wait(2.0)
		await shot("02_regal_nah", 1.0)
		return
	# Beim Laufen: Blick auf eine Hülle, A nimmt sie heraus (das Regal von nahem, Cover zu dir).
	var hat_bp := false
	for _k in 30:
		if str(z._bp.get("art", "")) == "spiel":
			hat_bp = true
			break
		z.pitch -= 0.02
		z._ziel_suchen()
		await wait(0.05)
	pruefe(hat_bp and str(z._schild_aktion()[1]).begins_with(tr("Herausnehmen")), "Schild an der Hülle: „Herausnehmen“ (%s)" % str(z._schild_aktion()))
	var gid := str(z._bp.get("daten", {}).get("id", ""))
	Nav._fire("a")
	await wait(0.8)
	pruefe(z.modus == "ansehen" and not (z._raus as Dictionary).is_empty() and str(z._raus.id) == gid, "A: vor dem Regal, die Hülle ist heraus")
	await wait(1.4)
	await shot("03_huelle_raus", 0.6)
	var h: Array = z.get_meta("uz_hints", [])
	pruefe(h.size() > 0 and str(h[0][0]) == "a" and str(h[0][1]) in ["Spielen", "Installieren"], "Tastenzeile: A spielt (%s)" % str(h))
	Nav._fire("b")
	await wait(0.8)
	pruefe(z.modus == "ansehen" and (z._raus as Dictionary).is_empty(), "B legt sie zurück, das Regal bleibt")
	for _k in 3:
		Nav._fire("left")
		await wait(0.25)
	Nav._fire("rb")
	await wait(0.3)
	pruefe((z._hand as Dictionary).is_empty(), "RB stellt nichts aus Versehen um")
	await wait(1.5)
	pruefe((z._detail as Dictionary).size() > 6, "von nahem echte Hüllen wie im Hauptmenü (%d)" % (z._detail as Dictionary).size())
	await shot("02_regal_nah", 0.6)
	Nav._fire("y")
	await wait(0.5)
	var offen: bool = z._kontext.call("offen")
	pruefe(offen, "Y: Menü des Regals (Umstellen, Einräumen, Einrichten)")
	if offen:
		Nav._fire("a")
		await wait(0.5)
		pruefe(not (z._hand as Dictionary).is_empty(), "„Umstellen“: die Hülle in der Hand")
		Nav._fire("b")
		await wait(0.4)
	Nav._fire("b")
	await wait(0.8)
	pruefe(z.modus == "laufen" and (z._detail as Dictionary).is_empty(), "B: zurück ins Zimmer, die echten Hüllen gehen wieder")
	await _vergleich()
	print("PRUEFUNG Ergebnis: ", "alles ok" if fehler == 0 else "%d Fehler" % fehler)


## Dieselbe Hülle heraus: im Zimmer und im Regal des Hauptmenüs, nebeneinander.
func _vergleich() -> void:
	var m := -1
	for i in z.welt.plaetze.keys():
		for p in z.welt.plaetze[i]:
			if str(p.daten.get("id", "")) == ZIEL:
				m = int(i)
	pruefe(m >= 0, "Vergleichs-Hülle steht im Zimmer-Regal")
	if m < 0:
		return
	z._ansehen(m)
	for k in z._ans_plaetze.size():
		if str(z._ans_plaetze[k].daten.get("id", "")) == ZIEL:
			z._ans_sel = k
	z._platz_zeigen()
	z._raus_an()
	await wait(2.0)
	await shot("vergleich_zimmer", 0.4)
	Nav._fire("b")
	Nav._fire("b")
	await wait(0.6)
	z.close()
	await wait(1.0)
	var gs: Node = main.sections.get("games")
	gs.open_regal("ps2", "PlayStation 2")
	await wait(2.6)
	var l: Node = Nav.top_layer()
	var welt: Node = l.get("welt")
	for _k in 120:
		if str((welt.get("spiele") as Array)[int(welt.get("auswahl"))].get("id", "")) == ZIEL:
			break
		l.nav_dir("right")
	await wait(2.2)
	await shot("vergleich_hauptmenue", 0.4)
	var a := Image.load_from_file(out.path_join("vergleich_hauptmenue.png"))
	var b := Image.load_from_file(out.path_join("vergleich_zimmer.png"))
	if a and b:
		a.resize(960, 540)
		b.resize(960, 540)
		var v := Image.create(1920, 540, false, a.get_format())
		v.blit_rect(a, Rect2i(0, 0, 960, 540), Vector2i(0, 0))
		b.convert(a.get_format())
		v.blit_rect(b, Rect2i(0, 0, 960, 540), Vector2i(960, 0))
		v.save_png(out.path_join("regal_vergleich.png"))
		print("Bild: regal_vergleich")
