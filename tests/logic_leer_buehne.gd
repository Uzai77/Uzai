extends Node
## Leere Bühne (src/ui/components/leer_buehne.gd): Silhouetten jeder Art liegen im Feld, werden zum
## Rand hin leiser und tragen vorn den Akzent; das Band der schmalen Form bleibt in seiner Höhe;
## der Atem bleibt in seinen Grenzen (ruhig: still). Knöpfe nur mit Wort, Fokus auf dem Hauptknopf;
## läuft die Einrichtung, sagt es der Titel; eingerichtet baut der Bereich neu (selbst oder von außen)
## und sein Inhalt kommt herein; die Wege zum Einrichten gibt es für jeden Dienst.
## Aufruf: godot --headless --path . res://tests/logic_leer_buehne.tscn → „Ergebnis: alles ok“

const U := preload("res://src/ui/u.gd")
const LeerBuehne := preload("res://src/ui/components/leer_buehne.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Ein Bereich zum Neubauen: zählt seine Aufbauten.
class FakeHost extends Control:
	var gebaut := 0

	func build() -> void:
		gebaut += 1
		for ch in get_children():
			remove_child(ch)
			ch.queue_free()
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.set_meta("uz_default", true)
		add_child(b)


func _ready() -> void:
	Config.set_value("theme.reduce_motion", false)
	_formen()
	_atem()
	_wege()
	await _knoepfe()
	await _selbst_neu()
	await _von_aussen()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _formen() -> void:
	var feld := Rect2(900, 0, 1020, 800)
	for art in LeerBuehne.ARTEN:
		var f: Array = LeerBuehne._Vorschau.formen_fuer(art, feld, false)
		check(f.size() >= 4, "%s: genug Silhouetten (%d)" % [art, f.size()])
		var drin := f.all(func(s: Dictionary) -> bool:
			var r: Rect2 = s.r
			return r.position.x >= feld.position.x - 0.5 and r.position.y >= -0.5 and r.end.y <= feld.end.y + 0.5 and r.position.x < feld.end.x)
		check(drin, "%s: alle im Feld (nur rechts darf es über den Rand)" % art)
		check(bool(f[0].get("akzent", false)) and f.filter(func(s: Dictionary) -> bool: return bool(s.get("akzent", false))).size() == 1,
			"%s: genau die erste trägt den Akzent" % art)
		var hinten: Dictionary = f[0]
		for s in f:
			if (s.r as Rect2).position.x > (hinten.r as Rect2).position.x and not bool(s.get("kreis", false)) == not bool(f[0].get("kreis", false)):
				hinten = s
		check(float(f[0].a) > float(hinten.a), "%s: zum Rand hin leiser" % art)
		var band: Array = LeerBuehne._Vorschau.formen_fuer(art, Rect2(0, 0, 560, LeerBuehne.BAND_H), true)
		check(not band.is_empty() and band.all(func(s: Dictionary) -> bool: return (s.r as Rect2).end.y <= LeerBuehne.BAND_H + 0.5),
			"%s: das Band bleibt in seiner Höhe" % art)
	check(LeerBuehne._Vorschau.formen_fuer("cover", Rect2(0, 0, 4, 4), false).is_empty(), "ohne Platz: keine Silhouetten")


func _atem() -> void:
	var lo := 9.0
	var hi := -9.0
	for i in 200:
		var a: float = LeerBuehne._Vorschau.atem(i * 0.013, 0.7)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	check(lo >= 1.0 - LeerBuehne.ATEM_A - 0.001 and hi <= 1.0001 and hi - lo > LeerBuehne.ATEM_A * 0.8, "Atem zwischen %.2f und 1" % (1.0 - LeerBuehne.ATEM_A))
	Config.set_value("theme.reduce_motion", true)
	var r1: float = LeerBuehne._Vorschau.atem(0.1, 0.0)
	var r2: float = LeerBuehne._Vorschau.atem(0.6, 0.0)
	check(is_equal_approx(r1, r2), "Animationen reduzieren: die Silhouetten stehen still")
	Config.set_value("theme.reduce_motion", false)


func _wege() -> void:
	for d in ["steam", "discord", "spotify", "youtube", "twitch", "nuvio", "retro", "spiele"]:
		check(LeerBuehne.weg(self, d).is_valid(), "Weg zum Einrichten: " + d)
	check(not LeerBuehne.weg(self, "gibtsnicht").is_valid(), "unbekannter Dienst: kein Weg")


func _knoepfe() -> void:
	var host := FakeHost.new()
	host.size = Vector2(1920, 800)
	add_child(host)
	var gedrueckt := [0]
	var sucht := [false]
	var b: Control = LeerBuehne.new().setup({ "art": "cover", "symbol": "games", "titel": "Deine Spiele erscheinen hier.",
		"knopf": "Spiele suchen", "tun": func() -> void: gedrueckt[0] += 1, "neben": "Ordner wählen", "neben_tun": func() -> void: pass,
		"laeuft": func() -> bool: return sucht[0], "laeuft_titel": "Spiele werden gesucht …", "laeuft_knopf": "Sucht …" })
	U.full_rect(b)
	host.add_child(b)
	await get_tree().process_frame
	var haupt: Button = b.get("haupt")
	check(haupt != null and haupt.text == "Spiele suchen" and haupt.has_meta("uz_default"), "Hauptknopf mit Wort, Fokus darauf (uz_default)")
	check(Nav.default_in(host) == haupt, "der erste Fokus landet auf dem Hauptknopf")
	var btns := _knoepfe_in(b)
	check(btns.size() == 2 and btns.all(func(x: Button) -> bool: return x.icon == null), "zwei Knöpfe, beide ohne Symbol")
	haupt.pressed.emit()
	check(gedrueckt[0] == 1, "A auf dem Hauptknopf richtet ein")
	sucht[0] = true
	b.call("_laeuft_zeigen")
	var t: Label = b.get("_titel_l")
	check(t.text == "Spiele werden gesucht …" and haupt.text == "Sucht …", "läuft die Suche, sagt es der Titel")
	haupt.pressed.emit()
	check(gedrueckt[0] == 1, "während der Suche startet A sie nicht noch einmal")
	sucht[0] = false
	b.call("_laeuft_zeigen")
	check(t.text == "Deine Spiele erscheinen hier." and haupt.text == "Spiele suchen", "danach wieder der Titel")
	host.queue_free()
	await get_tree().process_frame


## Eingerichtet, während die Bühne zu sehen ist: Sie baut den Bereich selbst neu.
func _selbst_neu() -> void:
	var host := FakeHost.new()
	host.size = Vector2(1920, 800)
	add_child(host)
	var ok := [false]
	var b: Control = LeerBuehne.new().setup({ "art": "personen", "symbol": "steam", "titel": "Freunde", "knopf": "Steam verbinden",
		"tun": func() -> void: ok[0] = true, "host": host, "fertig": func() -> bool: return ok[0] })
	U.full_rect(b)
	host.add_child(b)
	await get_tree().process_frame
	var gemeldet := [0]
	b.connect("eingerichtet", func() -> void: gemeldet[0] += 1)
	b.call("_pruefen")
	check(host.gebaut == 0, "noch nicht eingerichtet: nichts passiert")
	(b.get("haupt") as Button).pressed.emit()
	b.call("_pruefen")
	check(host.gebaut == 0, "eingerichtet: erst kurz dem Bereich Zeit lassen")
	b.set("_fertig_ms", Time.get_ticks_msec() - LeerBuehne.WARTE_MS - 10)
	b.call("_pruefen")
	check(host.gebaut == 1 and gemeldet[0] == 1, "danach baut der Bereich neu (einmal)")
	check(host.modulate.a < 0.05, "der neue Inhalt kommt herein (blendet auf)")
	await get_tree().create_timer(U.T_ORT * 2.0 + 0.1).timeout
	check(host.modulate.a > 0.99, "und steht danach ganz da")
	check(Nav.focused() != null and host.is_ancestor_of(Nav.focused()), "die Auswahl liegt auf dem neuen Inhalt")
	host.queue_free()
	await get_tree().process_frame


## Der Bereich baut von sich aus neu (eigene Signale) und ist jetzt eingerichtet: der Inhalt kommt herein.
func _von_aussen() -> void:
	var host := FakeHost.new()
	host.size = Vector2(1920, 800)
	add_child(host)
	var ok := [false]
	var b: Control = LeerBuehne.new().setup({ "art": "video", "symbol": "video", "titel": "YouTube", "knopf": "Anmelden",
		"tun": func() -> void: pass, "host": host, "fertig": func() -> bool: return ok[0] })
	U.full_rect(b)
	host.add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	ok[0] = true
	host.build()
	await get_tree().process_frame
	check(host.gebaut == 1 and host.modulate.a < 0.5, "von außen neu gebaut: der Inhalt blendet herein")
	await get_tree().create_timer(U.T_ORT * 2.0 + 0.1).timeout
	check(host.modulate.a > 0.99, "und steht danach ganz da")
	# Neu gebaut ohne eingerichtet zu sein (anderer Grund): kein Hereinkommen.
	var host2 := FakeHost.new()
	add_child(host2)
	var b2: Control = LeerBuehne.new().setup({ "art": "musik", "titel": "Musik", "knopf": "Einschalten", "tun": func() -> void: pass,
		"host": host2, "fertig": func() -> bool: return false })
	host2.add_child(b2)
	await get_tree().process_frame
	host2.build()
	await get_tree().process_frame
	check(host2.modulate.a > 0.99, "nicht eingerichtet: der Bereich baut ohne Hereinkommen neu")
	host.queue_free()
	host2.queue_free()
	await get_tree().process_frame


func _knoepfe_in(n: Node) -> Array:
	var out: Array = []
	for ch in n.get_children():
		if ch is Button:
			out.append(ch)
		out.append_array(_knoepfe_in(ch))
	return out
