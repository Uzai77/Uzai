extends "res://tests/probe_base.gd"
## Probe „Zimmer anpassen“ (Punkt 131, Demo): Möbel umfärben mit Palette und Farbrad, Material
## und Muster, Beine, Möbel-Baukasten (Bühne, Teil, im Katalog, im Zimmer), Wände, Boden, Decke,
## Fenster, Licht-Stimmungen samt Stimmungs-Rad und Wetter, Regal-Sortierungen und -Darstellungen,
## Hüllen je System, Vorlagen und Raumgröße. Alles über dieselben Wege wie mit dem Controller.
##
## Aufruf (drei Teile, Bilder alle in out_zanpassung):
##   A2_PROJ=<projekt> A2_TIMEOUT=1700 bash a2_run.sh res://tests/probe_zanpassung.gd zanpassung --teil=1   (2, 3)

const Daten := preload("res://src/room/zimmer_daten.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")

var z: Control


## Kamera sofort an ihr Ziel (Software-Grafik ist langsam).
func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])
	z._rate = 40.0


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func vor(t: String, abstand: float, hoehe := 1.62, seitlich := 0.0) -> void:
	var i := idx(t)
	var n: Node3D = z.welt.knoten[i]
	var vorn := n.transform.basis.z.normalized()
	var rechts := n.transform.basis.x.normalized()
	var mitte: Vector3 = (z.welt.boxen[i] as AABB).get_center()
	z.pos = Vector3(mitte.x, 0, mitte.z) + vorn * abstand + rechts * seitlich
	var dir := mitte - Vector3(z.pos.x, hoehe, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())


func ich(x: float, zz: float, yaw: float, pitch := -0.1) -> void:
	z.blick = "ich"
	z.pos = Vector3(x, 0, zz)
	z.yaw = yaw
	z._yaw_soll = yaw
	z.pitch = pitch


## Bis die Zeile mit diesem Text gewählt ist (wie mit dem Steuerkreuz).
func zeile(text: String, ui: Control = null) -> void:
	var u: Control = ui if ui else z._ui
	var zeilen: Array = u.get("_zeilen")
	var ziel_i := -1
	for i in zeilen.size():
		if str(zeilen[i].daten.get("text", "")) == text and ziel_i < 0 and not (str(zeilen[i].daten.get("art", "")) in ["abschnitt", "info"]):
			ziel_i = i
	if ziel_i < 0:
		print("Zeile nicht gefunden: ", text)
		return
	# Direkt wählen (wie viele Drücke auf dem Steuerkreuz, aber ohne Wartezeit je Bild).
	var sel: Array = u.get("_sel")
	sel[sel.size() - 1] = ziel_i
	u.emit_signal("schritt_neu")
	u.call("_auswahl", false)
	await wait(0.05)


func zu() -> void:
	while z.modus in ["anpassen", "baukasten", "rad", "katalog"]:
		await press("b", 1, 0.15)
	await wait(0.3)


func run() -> void:
	var teil := 1
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--teil="):
			teil = int(str(a).substr(7))
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.0)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	print("Zimmer offen: ", z != null and z.has_method("moebel_setzen"), " – Teil ", teil)
	z.stimmung_anwenden("gemuetlich")
	await wait(0.6)
	match teil:
		1: await teil_moebel()
		2: await teil_raum_licht()
		3: await teil_regal_vorlagen()


## Möbel umfärben (Palette, Farbrad), Material, Muster, Beine, Baukasten, Katalog „Eigene“.
func teil_moebel() -> void:
	await press("y")
	var sofa := idx("sofa")
	z.cursor = Vector2i(int(z.raum.moebel[sofa].x) + 1, int(z.raum.moebel[sofa].z))
	z._raster_auffrischen()
	await press("y")
	ziel()
	await zeile("Farbe")
	await press("right", 4, 0.1)
	ziel()
	await shot("01_sofa_umfaerben", 1.0)
	await press("a")
	await press("right", 3, 0.1)
	await press("down", 1, 0.1)
	await shot("02_farbpalette", 0.8)
	var fw: Control = z._ui.get("_farbwahl")
	fw.set("_sel", (fw.get("_liste") as Array).size())
	await press("a")
	await press("lb", 3, 0.1)
	await press("up", 2, 0.1)
	await shot("03_farbrad", 0.8)
	await press("a")
	await zeile("Material")
	for _i in 30:
		if str(z.raum.moebel[sofa].get("m", "")) == "samt":
			break
		await press("right", 1, 0.05)
	await zeile("Muster")
	await press("right", 3, 0.1)
	await zeile("Beine")
	await press("right", 3, 0.1)
	ziel()
	await shot("04_material_muster_beine", 1.0)
	await zu()
	z.moebel_setzen(idx("couchtisch"), "m", "marmor")
	z._schritt_offen = true
	z.moebel_setzen(idx("couchtisch"), "be", "haarnadel")
	z._schritt_offen = true
	z.moebel_setzen(idx("sessel"), "m", "leder")
	z._schritt_offen = true
	z.moebel_setzen(idx("sessel"), "f", "#8a5233")
	z._schritt_offen = true
	z.moebel_setzen(idx("sitzsack"), "mu", "punkte")
	z._schritt_offen = true
	z.moebel_setzen(idx("spieleregal"), "m", "schwarz")
	z._schritt_offen = true
	z.moebel_setzen(idx("stehlampe"), "m2", "chrom")
	z._bauen_aus()
	ich(5.6, 4.6, 0.95, -0.42)
	ziel()
	await shot("05_materialien_ich", 1.4)
	# Baukasten: Leseplatz aus Tisch, Stange, Schirm und Kissen.
	z.bauen_an()
	z.baukasten_oeffnen("")
	await wait(0.8)
	var bk: Control = z._baukasten
	for teil in [["stange", { "x": 30, "y": 45, "h": 100, "m": "messing" }], ["schirm", { "x": 30, "y": 128, "f": "#c4913c" }],
			["kissen", { "x": -10, "y": 45, "b": 40, "h": 10, "t": 34, "f": "#87977a" }]]:
		bk.call("_teil_neu", teil[0])
		var werte: Dictionary = teil[1]
		bk.call("aendern", func() -> void:
			var t: Dictionary = bk.def.teile[bk.def.teile.size() - 1]
			t.merge(werte, true))
	bk.def.name = "Leseplatz"
	bk.call("_neu_bauen")
	bk.ui.call("auffrischen")
	await shot("06_baukasten_buehne", 1.4)
	await zeile("7 · Lampenschirm", bk.ui)
	await press("a")
	await zeile("Höhe über dem Boden", bk.ui)
	await press("rb", 1, 0.1)
	await shot("07_baukasten_teil", 1.0)
	await press("b")
	await press("b")
	await wait(1.0)
	print("Eigene Möbel: ", (z.daten.eigene as Array).size(), " – in der Hand: ", str(z._halten.get("t", "")))
	z.cursor = Vector2i(8, 4)
	z._halten.x = 8
	z._halten.z = 4
	z._getragen_zeigen()
	z._raster_auffrischen()
	await press("a")
	await wait(0.3)
	z.cursor = Vector2i(3, 2)
	z._raster_auffrischen()
	await press("a")
	await wait(0.3)
	z._katalog.call("bereich", "eigene")
	await wait(2.5)
	ziel()
	await shot("08_katalog_eigene", 0.8)
	await press("b")
	var eig := -1
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t).begins_with("e_"):
			eig = i
	print("Eigenes Möbel im Zimmer: ", eig >= 0)
	z._bauen_aus()
	if eig >= 0:
		vor(str(z.raum.moebel[eig].t), 1.7, 1.45)
	z.blick = "ich"
	ziel()
	await shot("09_eigenes_im_zimmer", 1.2)


## Wände, Boden, Decke, Fenster, Licht-Stimmungen, Stimmungs-Rad, Wetter.
func teil_raum_licht() -> void:
	z._zimmer_menue()
	await zeile("Wände")
	await press("a")
	await zeile("Hintere Wand")
	await press("a")
	await zeile("Material")
	await press("right", 2, 0.1)
	await zeile("Tapetenmuster")
	await press("left", 1, 0.1)
	ziel()
	await shot("10_wand_tapete", 1.2)
	await press("b", 2, 0.1)
	z.wand_setzen("links", "m", "ziegel")
	z.wand_setzen("links", "f", "#9c5a40")
	await zeile("Boden")
	await press("a")
	await zeile("Art")
	await press("right", 2, 0.1)
	ziel()
	await shot("11_boden_fischgrat", 1.2)
	await press("b")
	for e in [["decke", "a", "balken"], ["fenster", "a", "raster"], ["fenster", "v", "gardine"], ["fenster", "g", 3]]:
		z._schritt_offen = true
		z.raum_setzen(e[0], e[1], e[2])
	await zeile("Fenster")
	await press("a")
	ziel()
	await shot("12_fenster_seite", 1.2)
	await zu()
	ich(3.2, 2.2, 1.75, 0.02)
	ziel()
	await shot("13_fenster_ich", 1.2)
	ich(5.0, 4.35, 0.42)
	for st in ["kino", "neon", "gemuetlich", "morgen"]:
		z.stimmung_anwenden(st)
		# Software-Grafik ist zu langsam für den weichen Übergang: Endstand fürs Bild.
		z._licht_neu(false)
		await wait(0.3)
		ziel()
		await shot("14_stimmung_" + st, 0.5)
	await press("lt")
	await press("right", 2, 0.2)
	await wait(1.0)
	ziel()
	await shot("15_stimmungsrad", 0.4)
	await press("a")
	z._schritt_offen = true
	z.licht_setzen("z", "abend")
	z._schritt_offen = true
	z.licht_setzen("we", "schnee")
	z._licht_neu(false)
	await wait(0.3)
	ich(2.6, 2.4, 1.6, 0.05)
	ziel()
	await shot("16_wetter_schnee", 1.2)
	z._schritt_offen = true
	z.licht_setzen("we", "klar")
	z._schritt_offen = true
	z.lampe_setzen(idx("stehlampe"), "c", "#ff4fa3")
	z._zimmer_menue()
	await zeile("Licht und Stimmung")
	await press("a")
	await zeile("Farbtemperatur")
	await press("left", 2, 0.1)
	ziel()
	await shot("17_licht_seite", 1.2)
	await zu()


## Regal: Einstellungen, Sortierungen, Darstellungen, Hüllen, eigene Reihenfolge; Vorlagen, Größe.
func teil_regal_vorlagen() -> void:
	var regal := idx("spieleregal")
	vor("spieleregal", 1.35, 1.45)
	z._ansehen(regal)
	ziel()
	await wait(0.5)
	await press("x")
	await zeile("Sortierung")
	await press("right")
	ziel()
	await shot("18_regal_einrichten", 1.2)
	await zu()
	for d in [["titel", "ruecken"], ["system", "cover"], ["spielzeit", "gemischt"]]:
		z._schritt_offen = true
		z.regal_setzen(regal, "so", d[0])
		z._schritt_offen = true
		z.regal_setzen(regal, "da", d[1])
		vor("spieleregal", 1.35, 1.45)
		ziel()
		await shot("19_regal_%s_%s" % [d[0], d[1]], 1.4)
	z._schritt_offen = true
	z.regal_setzen(regal, "de", "viel")
	for sid in ["snes", "gba", "n64", "ps2", "switch"]:
		z.huelle_setzen(sid, "jewel")
	vor("spieleregal", 1.35, 1.45)
	ziel()
	await shot("20_regal_huellen_deko", 1.2)
	z._schritt_offen = true
	z.regal_setzen(regal, "so", "manuell")
	z.regal_setzen(regal, "da", "ruecken")
	vor("spieleregal", 1.35, 1.45)
	z._ansehen(regal)
	await press("rb", 3, 0.2)
	ziel()
	await wait(0.4)
	ziel()
	await shot("21_regal_eigene_reihenfolge", 0.6)
	await press("b")
	z.regal_setzen(idx("plattenregal"), "da", "ruecken")
	z.regal_setzen(idx("plattenregal"), "so", "name")
	vor("plattenregal", 1.1, 1.15)
	ziel()
	await shot("22_platten_ruecken", 1.2)
	var vorher := (z._rueck as Array).size()
	for _i in 6:
		z.rueckgaengig()
	print("Rückgängig: %d → %d Schritte" % [vorher, (z._rueck as Array).size()])
	z._zimmer_menue()
	await zeile("Vorlagen")
	await press("a")
	ziel()
	await shot("23_vorlagen_seite", 1.0)
	await zu()
	z.blick = "oben"
	z._oben_az = 0.62
	z._oben_az_soll = 0.62
	for v in Vorlagen.LISTE:
		z.vorlage_uebernehmen(str(v[0]))
		z._licht_neu(false)
		await wait(0.3)
		ziel()
		await shot("24_vorlage_" + str(v[0]), 1.4)
	z.vorlage_uebernehmen("gemuetlich")
	z.groesse_setzen(18, 12)
	await wait(1.0)
	ziel()
	await shot("25_raum_gross", 1.4)
	z.speichern()
	var geladen := Daten.laden()
	print(
			"Gespeichert und geprüft: %d Möbel, %d eigene, Raum %d × %d" % [(geladen.raeume[0].moebel as Array).size(), (geladen.eigene as Array).size(),
			int(geladen.raeume[0].w), int(geladen.raeume[0].d)])
