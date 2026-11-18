extends "res://tests/probe_base.gd"
## Einrichten im Zimmer, neu gedacht (direkt im Raum, Hinweise im Bild): Bilder aller Bau- und
## Einrichtschritte und die Zahl der Tastendrücke je Aufgabe (Bauen mit der View-Taste, Modus-Leiste) – Möbel hinstellen, drehen, verschieben,
## wegräumen, Wand und Boden ändern, zurück ins Zimmer. Zielen mit dem Stick (Blick auf das Möbel
## oder die Wand) zählt nicht als Tastendruck; jede Aufgabe beginnt beim Laufen in der Ich-Ansicht.
##
## Aufruf (vier Teile, Software-Grafik ist langsam), je Teil --teil=1 … 4:
##   A2_PROJ=<worktree> A2_TIMEOUT=600 bash a2_run.sh res://tests/probe_zimmerbau.gd zimmerbau_1 --teil=1

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")

var z: Control
var n := 0
var log_ := []


func tu(cmd: String, mal := 1) -> void:
	for i in mal:
		n += 1
		await press(cmd, 1, 0.22)


func ziel() -> void:
	var soll: Array = z._kamera_soll()
	z.welt.kamera.transform = soll[0]
	z.welt.kamera.fov = float(soll[1])


func idx(t: String) -> int:
	for i in (z.raum.moebel as Array).size():
		if str(z.raum.moebel[i].t) == t:
			return i
	return -1


func cursor_zu(c: Vector2i) -> void:
	for _k in 40:
		if z.cursor == c:
			return
		var best := ""
		var bd := 999
		for d in ["up", "down", "left", "right"]:
			var vor := Vector2(-sin(z._oben_az), -cos(z._oben_az))
			var re := Vector2(-vor.y, vor.x)
			var v: Vector2 = { "up": vor, "down": -vor, "left": -re, "right": re }[d]
			var s := Vector2i(int(signf(v.x)), 0) if absf(v.x) > absf(v.y) else Vector2i(0, int(signf(v.y)))
			var dist := absi(z.cursor.x + s.x - c.x) + absi(z.cursor.y + s.y - c.y)
			if dist < bd:
				bd = dist
				best = d
		await tu(best)


func moebel_zelle(i: int) -> Vector2i:
	var it: Dictionary = z.raum.moebel[i]
	return Vector2i(int(it.x), int(it.z))


func start_laufen(wo := Vector3(1.9, 0, 4.4)) -> void:
	while z.modus != "laufen":
		await press("b")
		await wait(0.3)
	z.blick = "ich"
	z.pos = wo
	z.yaw = -1.3
	z._yaw_soll = -1.3
	z.pitch = -0.25
	z._ziel = -2
	z._ziel_suchen()
	ziel()
	await wait(0.4)
	n = 0


## Mit dem Stick zielen (zählt nicht als Tastendruck): Blick auf einen Punkt im Raum.
func blick_auf(p: Vector3) -> void:
	var dir := p - Vector3(z.pos.x, 1.62, z.pos.z)
	z.yaw = atan2(-dir.x, -dir.z)
	z._yaw_soll = z.yaw
	z.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	z._ziel = -2
	z._ziel_suchen()
	ziel()
	await wait(0.3)


func blick_auf_moebel(t: String) -> void:
	await blick_auf((z.welt.boxen[idx(t)] as AABB).get_center())


func ergebnis(name_: String, ok: bool) -> void:
	var t := "%s: %d Tastendrücke (%s)" % [name_, n, "erreicht" if ok else "NICHT erreicht"]
	log_.append(t)
	print("SCHRITTE ", t)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	main.goto("games")
	await wait(1.0)
	main.open_room(true)
	await wait(2.5)
	z = Nav.top_layer()
	z.raum.licht.z = "abend"
	z._licht_neu()
	await start_laufen()
	var teil := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--teil="):
			teil = int(a.substr(7))
	match teil:
		1: await teil_1()
		2: await teil_2()
		3: await teil_3()
		4: await teil_4()
	print("Hinweisleiste von main im Zimmer leer: ", main.hint_bar.get_child_count() == 0)
	var f := FileAccess.open(out.path_join("schritte_nachher_%d.txt" % teil), FileAccess.WRITE)
	f.store_string("\n".join(log_) + "\n")
	f.close()


func teil_1() -> void:
	await wait(1.2)
	await shot("nachher_01_laufen", 0.2)
	# --- T1 Möbel platzieren: Stehlampe aus dem Katalog (RT geht von überall auf).
	var lampen_vorher := (z.raum.moebel as Array).filter(func(m: Dictionary) -> bool: return str(m.t) == "stehlampe").size()
	await tu("view")
	ziel()
	await tu("rt")
	await wait(0.6)
	var kats: Array = Katalog.KATEGORIEN.map(func(k: Array) -> String: return str(k[0]))
	await tu("rb", kats.find("licht"))
	await wait(2.0)
	var ids: Array = Katalog.in_kategorie("licht")
	await tu("right", ids.find("stehlampe"))
	await wait(0.5)
	ziel()
	await shot("nachher_03_katalog", 1.0)
	await tu("a")
	await tu("b")
	var lampen := (z.raum.moebel as Array).filter(func(m: Dictionary) -> bool: return str(m.t) == "stehlampe").size()
	ergebnis("Möbel platzieren", lampen == lampen_vorher + 1)


func teil_2() -> void:
	# Leeres Feld im Einrichten (für das Bild): Blick auf freien Boden.
	await start_laufen()
	await blick_auf(Vector3(1.75, 0, 3.6))
	await press("view")
	ziel()
	await shot("nachher_02_bauen_leer", 1.0)
	# --- T2 Drehen: Sessel um 90°.
	await start_laufen()
	var r0 := int(z.raum.moebel[idx("sessel")].r)
	await blick_auf_moebel("sessel")
	await tu("view")
	ziel()
	await shot("nachher_05_bauen_auf_moebel", 1.0)
	await tu("lb")
	await tu("b")
	ergebnis("Drehen", int(z.raum.moebel[idx("sessel")].r) != r0)
	z.rueckgaengig()
	# --- T3 Verschieben: Sitzsack zwei Felder nach links (du stehst gleich daneben).
	await start_laufen(Vector3(4.0, 0, 1.6))
	var c0 := moebel_zelle(idx("sitzsack"))
	await blick_auf_moebel("sitzsack")
	await tu("view")
	await tu("a")
	await cursor_zu(c0 + Vector2i(-2, 0))
	ziel()
	await shot("nachher_04_tragen", 0.8)
	await tu("a")
	await tu("b")
	ergebnis("Verschieben", moebel_zelle(idx("sitzsack")) == c0 + Vector2i(-2, 0))
	# Kein Platz: das Schild sagt es, bevor man drückt.
	await start_laufen()
	await blick_auf_moebel("sitzsack")
	await press("view")
	await press("a")
	z.cursor_setzen(moebel_zelle(idx("couchtisch")), false)
	ziel()
	await shot("nachher_11_kein_platz", 0.9)
	await press("b")


func teil_3() -> void:
	# --- T4 Löschen: die Stehlampe in der Ecke.
	var vorher_anz := (z.raum.moebel as Array).size()
	await blick_auf_moebel("stehlampe")
	await tu("view")
	await tu("a")
	ziel()
	await shot("nachher_07_wegraeumen", 0.8)
	await tu("x")
	await tu("b")
	ergebnis("Löschen", (z.raum.moebel as Array).size() == vorher_anz - 1)
	# Möbel anpassen (Y am Möbel): die Seitenleiste so hoch wie ihre Seite.
	await start_laufen()
	await blick_auf_moebel("sofa")
	await press("view")
	await press("y")
	await wait(0.4)
	ziel()
	await shot("nachher_06a_aktionen_am_moebel", 0.9)
	await press("down", 3)
	await press("a")
	await wait(0.5)
	ziel()
	await shot("nachher_06_moebel_anpassen", 0.9)


func teil_4() -> void:
	# --- T5 Wand ändern: die hintere Wand (Blick auf sie), Material. T7 zurück ins Zimmer.
	var m0 := str(z.raum.waende.hinten.m)
	await blick_auf(Vector3(2.6, 1.6, 0.0))
	await tu("view")
	ziel()
	await shot("nachher_09a_wand_gewaehlt", 1.0)
	await tu("a")
	await wait(0.4)
	ziel()
	await tu("right")
	await shot("nachher_09_wand_seite", 0.8)
	ergebnis("Wand ändern (hintere Wand)", str(z.raum.waende.hinten.m) != m0)
	n = 0
	while z.modus != "laufen":
		await tu("b")
	ergebnis("Zurück ins Zimmer (aus der Wand-Seite)", z.modus == "laufen")
	z.rueckgaengig()
	# --- T6 Boden ändern: Blick auf freien Boden, Y.
	await start_laufen()
	var b0 := str(z.raum.boden.a)
	await blick_auf(Vector3(1.75, 0, 3.6))
	await tu("view")
	await tu("y")
	await tu("right")
	ergebnis("Boden ändern", str(z.raum.boden.a) != b0)
	z.rueckgaengig()
	await start_laufen()
	await tu("menu")
	await wait(0.6)
	ziel()
	await shot("nachher_08_zimmer_menue", 0.8)
	await press("b")
	await wait(0.4)
	await press("lt")
	await shot("nachher_10_stimmung", 0.9)
	await press("b")
	await wait(0.4)
