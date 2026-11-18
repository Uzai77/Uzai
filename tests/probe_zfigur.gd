extends "res://tests/probe_base.gd"
## Probe „Figur und Haustier“ (Punkt 131 c, d): Editor in mehreren Varianten, Emotes als
## Bildfolge, Haustier-Editor, Figur im Zimmer (von oben, über die Schulter, am Jackenständer), Sitzen
## mit Controller, Haustier schläft / freut sich / liegt vor dem Fernseher / wird gestreichelt,
## gesperrte Möbel im Katalog und die Mitteilung einer Freischaltung.
##
## Aufruf: A2_PROJ=<projekt> A2_TIMEOUT=600 bash a2_run.sh res://tests/probe_zfigur.gd zfigur
## --jackenstaender: nur der Jackenständer im Zimmer und „Figur wechseln“ (zwei Bilder).

const FigurEditor := preload("res://src/room/figur/figur_editor.gd")
const D := preload("res://src/room/figur/figur_daten.gd")

var z: Control
var ed: Control


## Kamera sofort an ihr Ziel (Software-Grafik ist langsam).
func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func figur(werte: Dictionary) -> void:
	for k in werte.keys():
		ed.setze(k, str(werte[k]))


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.0)
	if "--jackenstaender" in OS.get_cmdline_user_args():
		main.open_room(true)
		await wait(3.0)
		z = Nav.top_layer()
		z.licht_setzen("z", "abend")
		z._licht_neu(false)
		await jackenstaender()
		return
	# --- Editor: Figur in Varianten -------------------------------------------------------------------
	ed = FigurEditor.new()
	ed.erreichte = ["stunde_1", "stunden_10", "stunden_100", "platin_1", "erfolge_100", "serie_7", "nacht_1"]
	main.open_layer(ed)
	await wait(2.0)
	await shot("01_editor_start", 1.0)
	for pz in [["nora", "02_editor_nora"], ["finn", "03_editor_finn"], ["mia", "04_editor_mia"]]:
		figur({ "person": pz[0] })
		await wait(1.4)
		await shot(pz[1], 0.6)
	# Gesperrtes: Leon ohne den Meilenstein (zum Ansehen, mit Schloss).
	ed.erreichte = []
	figur({ "person": "leon" })
	ed._auswahl(false)
	await wait(1.6)
	await shot("07_editor_gesperrt", 0.6)
	ed.erreichte = ["stunde_1", "stunden_10", "stunden_100", "platin_1", "erfolge_100", "serie_7", "nacht_1"]
	figur({ "person": "lea" })
	ed._sel.figur = 0
	ed._auswahl(false)
	await wait(1.2)
	# Emotes als Bildfolge.
	for e in ["winken", "jubeln", "tanzen", "daumen", "klatschen", "sitzen", "zucken"]:
		ed.avatar.emote(e)
		for k in (3 if e in ["winken", "jubeln", "tanzen"] else 2):
			await wait(0.45)
			await shot("09_emote_%s_%d" % [e, k + 1], 0.05)
	ed.avatar.emote("")
	# Haustier-Editor.
	await press("rb")
	await wait(1.4)
	await shot("10_tier_editor", 0.6)
	for a in [["hund", "braun", "bauch", "tuch"], ["fuchs", "rotbraun", "bauch", "band"], ["hase", "creme", "pfoten", "keins"],
			["drache", "mint", "sterne", "band"]]:
		ed.setze("art", a[0])
		ed.setze("fell", a[1])
		ed.setze("muster", a[2])
		ed.setze("halsband", a[3])
		await wait(1.0)
		await shot("11_tier_" + str(a[0]), 0.4)
	ed.setze("art", "katze")
	ed.setze("fell", "orange")
	ed.setze("muster", "getigert")
	ed.setze("halsband", "band")
	await press("x")
	await wait(0.5)
	await shot("12_tier_freut_sich", 0.1)
	await press("b")
	await wait(1.0)
	# --- Im Zimmer -----------------------------------------------------------------------------------------
	main.open_room(true)
	await wait(3.0)
	z = Nav.top_layer()
	z.licht_setzen("z", "abend")
	z._licht_neu(false)
	print("Bewohner da: ", z.bewohner != null)
	z.blick = "oben"
	z._oben_az = 0.62
	z._oben_az_soll = 0.62
	z.pos = Vector3(3.2, 0, 3.0)
	z.yaw = 2.3
	z._yaw_soll = 2.3
	await wait(1.5)
	ziel()
	await shot("20_zimmer_von_oben", 1.0)
	# Laufen von oben (die Figur läuft sichtbar).
	z._vel = Vector3(-1.2, 0, 0.6)
	for k in 12:
		z.pos += z._vel * 0.05
		z._yaw_soll = atan2(-z._vel.x, -z._vel.z)
		await wait(0.05)
	ziel()
	await shot("21_zimmer_laufen", 0.05)
	z._vel = Vector3.ZERO
	# Über die Schulter.
	z.blick = "schulter"
	z.pos = Vector3(3.0, 0, 3.6)
	z.yaw = 0.1
	z._yaw_soll = 0.1
	z.pitch = -0.12
	await wait(0.8)
	ziel()
	await shot("22_schulterblick", 0.8)
	await jackenstaender()
	# Emote in der Ich-Ansicht: die Kamera tritt vor die Figur.
	z.pos = Vector3(3.4, 0, 3.4)
	z.yaw = 0.5
	z._yaw_soll = 0.5
	z.pitch = -0.05
	await press("rt")
	await wait(0.6)
	await shot("25_emote_leiste", 0.4)
	await press("right", 1)
	await press("a")
	await wait(1.5)
	await shot("26_emote_ich_kamera", 0.3)
	await wait(2.0)
	# Haustier: streicheln (oben, mit Figur) und freuen.
	# Figur auf freiem Boden, das Tier zwischen ihr und der Kamera (nicht verdeckt).
	z.blick = "oben"
	z.pos = Vector3(4.25, 0, 2.45)
	z.yaw = atan2(-0.35, -0.5)
	z._yaw_soll = z.yaw
	var t: Node3D = z.bewohner.tier
	t.setze(Vector3(4.6, 0, 2.95), atan2(-0.35, -0.5), "sitzen")
	await wait(0.6)
	z._oben_zoom = 0.7
	z.bewohner.streicheln()
	await wait(1.1)
	ziel()
	await shot("27_streicheln", 0.2)
	z.bewohner.tier.freuen()
	z.bewohner.avatar.emote("jubeln")
	await wait(0.55)
	await shot("28_tier_jubelt", 0.05)
	await wait(2.5)
	# Schlafen: lange nichts getan.
	z._oben_zoom = 0.62
	ziel()
	z.bewohner.ruhe = 40.0
	t.setze(t.position, t.rotation.y, "schlafen")
	await wait(1.5)
	z.bewohner.ruhe = 40.0
	ziel()
	await shot("29_tier_schlaeft", 0.4)
	z.bewohner.ruhe = 0.0
	z._oben_zoom = 1.06
	# Sitzen auf dem Sofa mit Controller; das Tier legt sich vor den Fernseher.
	var sofa := idx("sofa")
	z._hinsetzen(sofa)
	var lage_tv: Vector3 = z._frei((z.welt.knoten[z.welt.medienwand()] as Node3D).global_transform * Vector3(0.35, 0, 1.15))
	t.setze(lage_tv, PI, "fernsehen")
	await wait(1.0)
	z.blick = "oben"
	ziel()
	await shot("30_sitzen_von_oben", 1.2)
	z.blick = "schulter"
	await wait(0.4)
	ziel()
	await shot("31_sitzen_schulter_controller", 1.0)
	z.blick = "ich"
	ziel()
	await shot("32_sitzen_ich_tier_vor_tv", 0.8)
	z._aufstehen()
	await wait(0.4)
	# Katalog: gesperrte Möbel mit Schloss; Mitteilung einer Freischaltung.
	z.bewohner.erreichte = []
	z.bauen_an()
	z.cursor = Vector2i(9, 4)
	z._raster_auffrischen()
	await wait(0.4)
	await press("a")
	await wait(0.5)
	z._katalog.call("bereich", "licht")
	await wait(4.0)
	ziel()
	await shot("33_katalog_gesperrt", 0.8)
	await press("b")
	await wait(0.3)
	await press("b")
	await wait(0.5)
	z.bewohner.daten.gemeldet = []
	z.bewohner.call("_freischaltungen_pruefen")
	z.blick = "oben"
	await wait(0.9)
	ziel()
	await shot("34_freischaltung_mitteilung", 0.3)
	# Neue Möbel: Lavalampe, Leuchtschild und Körbchen im Zimmer (frei gespielt).
	z.raum.moebel.append({ "t": "lavalampe", "x": 6, "z": 5, "r": 0, "v": "orange", "an": true })
	z.raum.moebel.append({ "t": "neonschild", "x": 1, "z": 0, "r": 0, "v": "rosa", "an": true })
	z.raum.moebel.append({ "t": "tierkorb", "x": 2, "z": 4, "r": 0, "v": "terrakotta", "an": true })
	z.licht_setzen("z", "nacht")
	z._licht_neu(false)
	z.welt.alle_moebel()
	z.pos = Vector3(2.4, 0, 3.4)
	z._oben_zoom = 0.8
	await wait(0.2)
	var korb: Node3D = z.welt.knoten[idx("tierkorb")]
	t.setze(korb.global_position, 0.6, "schlafen")
	z.bewohner.ruhe = 40.0
	await wait(1.4)
	z.bewohner.ruhe = 40.0
	ziel()
	await shot("35_neue_moebel_nacht", 1.0)
	# Figur und Tier in allen drei Grafikstufen (die Welt wird je Stufe neu gebaut).
	z.licht_setzen("z", "abend")
	z._licht_neu(false)
	for st in ["hoch", "mittel", "leicht"]:
		z.grafik_setzen(st)
		z.blick = "oben"
		z.pos = Vector3(4.25, 0, 2.45)
		z.yaw = atan2(-0.35, -0.5)
		z._yaw_soll = z.yaw
		z.bewohner.ruhe = 0.0
		z.bewohner.tier.setze(Vector3(4.6, 0, 2.95), atan2(-0.35, -0.5), "sitzen")
		z.bewohner.avatar.emote("winken")
		z._oben_zoom = 0.62
		await wait(1.2)
		ziel()
		await shot("36_stufe_" + st, 0.6)
		print("Stufe %s: Figur in der Welt %s" % [st, z.bewohner.get_parent() == z.welt])
	z.grafik_setzen("auto")
	# Nach dem Neubau der Welt übersetzt der Software-Renderer noch Shader; nicht mittendrin beenden.
	await wait(10.0)
	print("Probe Figur: fertig")


## Jackenständer in der Ich-Ansicht (Schild „Figur wechseln“), dann A: die Kamera tritt vor die Figur,
## die Figurenwahl geht auf; wieder zu.
func jackenstaender() -> void:
	var js := idx("jackenstaender")
	print("Jackenständer im Zimmer: ", js)
	if js < 0:
		return
	var n: Node3D = z.welt.knoten[js]
	var mitte: Vector3 = n.global_transform * Vector3(0, 1.1, 0)
	var vorn := n.global_transform.basis.z.normalized()
	z.blick = "ich"
	z.modus = "laufen"
	z.pos = Vector3(mitte.x, 0, mitte.z) + vorn * 1.5 + n.global_transform.basis.x.normalized() * 0.3
	var dir: Vector3 = mitte - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	await wait(1.2)
	ziel()
	print("Ziel: ", z._ziel, " Handlung: ", z._ziel_handlung())
	await shot("23_jackenstaender_ich", 1.0)
	# Nah dran, leicht von der Seite: Stoff, Falten, Holz.
	z.pos = Vector3(mitte.x, 0, mitte.z) + vorn * 0.85 + n.global_transform.basis.x.normalized() * 0.55
	dir = mitte - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	await wait(1.0)
	await shot("23_jackenstaender_nah", 0.6)
	z._figur_wechseln()
	await wait(1.6)
	await shot("24_figur_wechseln", 0.6)
	var oben: Variant = Nav.top_layer()
	if oben and oben != z and oben.has_method("close"):
		oben.close()
	await wait(1.4)
	print("Kamera zurück: ", not z.bewohner.selfie())
