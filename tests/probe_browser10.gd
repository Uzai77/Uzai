extends "res://tests/probe_base.gd"
## Eine ganze Browser-Sitzung im Vorführmodus (Attrappe des Kerns: browser_demo.gd über dieselbe Leitung):
## öffnen, Seite laden, Steuerkreuz springt, A aktiviert, rechter Stick rollt, X Tab-Übersicht, zweiter Tab,
## Tab wechseln, B zurück, schließen, wieder öffnen. Dazu der Zeiger (L3): knapp neben einem Ziel
## losgelassen rastet er ein (Ring um das Ziel), das Steuerkreuz springt ihn weiter, A klickt, B schaltet
## ihn aus (Bilder zeiger_*.png). Geprüft: immer höchstens ein Kern (Wirt.laufend), kein Neustart
## in der Sitzung, die Steuerbefehle erreichen den Kern (Zähler der Leitung), das Ende ist sauber.
## Ausgabe „B10 ok/FAIL …“ und „B10 Ergebnis: …“, Bilder browser10_*.png.
##   UZAI_DATA=$(mktemp -d) xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --resolution 1920x1080 -- --demo --no-boot \
##     --uzai-script=res://tests/probe_browser10.gd --uzai-out=<ordner>

const Wirt := preload("res://src/core/browser_wirt.gd")
const K := preload("res://src/core/browser_karte.gd")
const Z := preload("res://src/core/browser_zeiger.gd")

var fails := 0
var hoechst := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("B10 %s %s" % ["ok  " if cond else "FAIL", what])


func _browser() -> Control:
	for l in Nav.layers:
		if is_instance_valid(l) and str(l.get_script().resource_path).ends_with("layers/browser.gd"):
			return l
	return null


func _process(_dt: float) -> void:
	hoechst = maxi(hoechst, Wirt.laufend.filter(func(w: Variant) -> bool: return is_instance_valid(w)).size())


func _zeiger(b: Control, w: Node) -> void:
	await wait(0.6)
	b.call("_zeiger_umschalten")
	_ck(bool(b.get("zeiger_an")), "L3: Zeiger an")
	var t: Dictionary = b.call("_tab")
	var v: Vector2 = b.call("_vw", t)
	var zg: RefCounted = b.get("_zg")
	var ziel := {}
	for z in t.ziele:
		var r: Rect2 = z.r
		if r.size.y <= Z.ZEILE and K.im_bild(r, v.x, v.y) and r.position.y > 60.0 and str(z.art) in ["link", "knopf"]:
			ziel = z
			break
	_ck(not ziel.is_empty(), "Link im Bild gefunden (%d Ziele)" % (t.ziele as Array).size())
	if ziel.is_empty():
		return
	var start := Vector2((ziel.r as Rect2).end.x + 14.0, (ziel.r as Rect2).get_center().y + 6.0)
	var soll := Z.einrast_punkt(start, t.ziele)
	zg.call("setzen", start)
	# Unter Last laufen wenige Bilder je Sekunde: warten, bis er steht (höchstens 4 s).
	for i in 40:
		await wait(0.1)
		if (zg.get("p") as Vector2).distance_to(soll) < 0.5:
			break
	_ck(soll.x >= 0.0 and (zg.get("p") as Vector2).distance_to(soll) < 1.0 and int((zg.get("ueber") as Dictionary).get("id", -1)) == int(ziel.id),
		"knapp daneben losgelassen: rastet ein (%s → %s)" % [str(start), str(zg.get("p"))])
	await shot("zeiger_ueber_ziel", 0.2)
	var vorher := int((zg.get("ueber") as Dictionary).get("id", -1))
	for dir in ["down", "right", "left"]:
		press(dir)
		for i in 30:
			await wait(0.1)
			var jetzt := int((zg.get("ueber") as Dictionary).get("id", -1))
			if jetzt >= 0 and jetzt != vorher and (zg.get("v") as Vector2) == Vector2.ZERO:
				break
		if int((zg.get("ueber") as Dictionary).get("id", -1)) not in [-1, vorher]:
			break
	var nach := int((zg.get("ueber") as Dictionary).get("id", -1))
	_ck(nach >= 0 and nach != vorher, "Steuerkreuz: der Zeiger springt zum nächsten Ziel (%d → %d)" % [vorher, nach])
	var z0: Dictionary = (w.get("_zaehler") as Dictionary).duplicate()
	press("a")
	await wait(0.5)
	var z1: Dictionary = w.get("_zaehler")
	_ck(int(z1.get("→klick", 0)) + int(z1.get("→aktivieren", 0)) > int(z0.get("→klick", 0)) + int(z0.get("→aktivieren", 0)), "A: Klick unter dem Zeiger geht an den Kern")
	await wait(0.6)
	if bool(b.get("zeiger_an")):
		press("b")
		await wait(0.4)
	_ck(not bool(b.get("zeiger_an")), "B: Zeiger aus")


func run() -> void:
	var s0 := Wirt.sitzungen
	main.goto("browser")
	await wait(1.0)
	main.open_browser("", 0, false, {})
	await wait(1.4)
	var b := _browser()
	_ck(b != null, "Browser offen")
	if b == null:
		print("B10 Ergebnis: 1 Fehler")
		return
	var w: Node = b.get("wirt")
	_ck(Wirt.sitzungen == s0 + 1 and Wirt.laufend.size() == 1 and bool(w.get("bereit")), "ein Kern, bereit")
	b.call("_oeffnen", "https://uzai.example/start", true, 0)
	await wait(1.6)
	_ck(str(b.get("modus")) == "seite", "Seite offen")
	press("down", 3, 0.25)
	press("right", 2, 0.25)
	await wait(0.4)
	var t: Dictionary = b.call("_tab")
	_ck(int(t.get("fokus", -1)) >= 0, "Steuerkreuz: Fokus auf einem Ziel (%d)" % int(t.get("fokus", -1)))
	await shot("browser10_seite_fokus", 0.3)
	press("a")
	await wait(0.6)
	await shot("browser10_nach_a", 0.2)
	await _zeiger(b, w)
	press("x")
	await wait(0.9)
	var top := Nav.top_layer()
	_ck(top != null and str(top.get_script().resource_path).ends_with("browser_tabs.gd"), "X: Tab-Übersicht offen, kein Absturz")
	await shot("browser10_tabs", 0.3)
	press("b")
	await wait(0.5)
	_ck(Nav.top_layer() == b, "B: zurück zur Seite")
	# Zweiter Tab und wechseln.
	b.call("neuer_tab", false)
	await wait(0.4)
	b.call("_oeffnen", "https://uzai.example/zwei", true, 0)
	await wait(1.4)
	_ck((b.get("reihe") as Array).size() == 2, "zweiter Tab")
	press("x")
	await wait(0.8)
	press("left")
	await wait(0.3)
	press("a")
	await wait(0.8)
	_ck(Nav.top_layer() == b and int(b.get("aktiv")) == int((b.get("reihe") as Array)[0]), "Tab gewechselt")
	var z: Dictionary = w.get("_zaehler")
	var steuer := ["→fokus", "→aktivieren", "→tab-neu", "→tab-wahl"]   # Steuerkreuz: fokus (springe ist der Sprung über Bereiche)
	var fehlt := steuer.filter(func(a: String) -> bool: return int(z.get(a, 0)) == 0)
	_ck(fehlt.is_empty(), "Steuerbefehle erreichen den Kern %s (gezählt: %s)" % [str(fehlt), str(z)])
	_ck(Wirt.sitzungen == s0 + 1, "kein Neustart in der Sitzung")
	# Schließen: B auf der Seite (zurück), B auf der Startseite (zu).
	b.call("_zeige_start")
	await wait(0.4)
	press("b")
	await wait(1.4)
	_ck(_browser() == null and Wirt.laufend.filter(func(x: Variant) -> bool: return is_instance_valid(x)).is_empty(), "zu: Kern sauber beendet")
	main.open_browser("", 0, false, {})
	await wait(1.4)
	var b2 := _browser()
	_ck(b2 != null and Wirt.sitzungen == s0 + 2 and Wirt.laufend.size() == 1, "wieder offen: neue Sitzung, ein Kern")
	_ck(hoechst <= 1, "nie mehr als ein Kern zugleich (%d)" % hoechst)
	if b2:
		b2.call("close")
		await wait(1.0)
	print("B10 Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
