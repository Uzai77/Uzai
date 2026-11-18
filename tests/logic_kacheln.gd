extends Node
## Lebendige Kacheln (Roadmap 101 → 124): welcher Zustand auf einem Cover steht (Rangfolge,
## höchstens einer), jede Quelle für sich (Update, Statusseite, Freunde, Wunschliste, Erfolge,
## Neuigkeiten), fremde Daten der Statusseite, Abschalten, und die Schicht auf einem echten Cover
## (Abzeichen, Aufwachen, Leichter Modus, Auswahlmodus).
## Aufruf: godot --headless --path . res://tests/logic_kacheln.tscn

const K := preload("res://src/core/kacheln.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const Leicht := preload("res://src/core/leicht.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_rank()
	_update()
	_friends()
	_sale()
	_achievements()
	_news()
	_status()
	await _tile()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _rank() -> void:
	print("Rangfolge")
	var f := { "kind": "freunde" }
	var u := { "kind": "update" }
	var p := { "kind": "patch" }
	var l := { "kind": "update_laeuft" }
	var g := { "kind": "gestoert" }
	check(K.best([p, u, f]) == f, "Freunde vor Update vor Patch")
	check(K.best([f, g]) == g and K.best([g, l]) == l, "Störung vor Freunden, laufendes Update vor allem")
	check(K.best([{}, {}, null]).is_empty(), "nichts los: kein Zustand")
	check(K.best([{ "kind": "erfolge" }, { "kind": "rabatt" }]).kind == "rabatt", "Rabatt vor neuen Erfolgen")
	check(K.best([{ "kind": "unbekannt" }, p]) == p, "Unbekanntes verliert")
	check(K.norm("Rocket League®") == "rocket league" and K.norm("  FORTNITE ") == "fortnite", "Titel vergleichbar (Zeichen, Groß/klein, Leerraum)")
	check(K.norm("Ōkami: HD") == "ōkami hd", "Umlaute und Längen bleiben")


func _update() -> void:
	print("Update")
	var run := K.update_state({ "kind": "update", "phase": "downloading", "frac": 0.42, "text": "noch 3 Min." }, {})
	check(run.kind == "update_laeuft" and run.text == "Update · 42 %" and is_equal_approx(float(run.frac), 0.42), "lädt über Uzai: Prozent und Balken")
	check(K.update_state({ "kind": "update", "phase": "paused", "frac": 0.5 }, {}).text == "Update pausiert", "pausiert")
	check(K.update_state({ "kind": "install", "phase": "downloading", "frac": 0.2 }, {}).is_empty(), "Installation ist kein Update (zeigt das Cover selbst)")
	check(K.update_state({ "kind": "update", "phase": "done" }, {}).is_empty(), "fertig: nichts mehr")
	var wait := K.update_state({}, { "phase": "wartet", "remaining": 2576980378, "total": 2576980378 })
	check(wait.kind == "update" and wait.text == "Update · 2,4 GB", "wartet in Steam: Größe (%s)" % wait.get("text", ""))
	check(K.update_state({}, { "phase": "wartet", "remaining": -1 }).text == "Update verfügbar", "Größe unbekannt")
	check(K.update_state({}, {}).is_empty(), "kein Update")


func _friends() -> void:
	print("Freunde")
	check(K.friends_state([], []).is_empty(), "niemand: nichts")
	var one := K.friends_state([{ "name": "Mira", "avatar": "" }], [])
	check(one.text == "spielt gerade" and one.more == "Mira" and one.people.size() == 1, "eine Person")
	var two := K.friends_state([{ "name": "Mira" }], [{ "name": "Sana" }, { "name": "mira" }])
	check(two.text == "2 spielen gerade" and two.more == "Mira und Sana", "Steam und Discord, niemand doppelt")
	var many := K.friends_state([{ "name": "A" }, { "name": "B" }, { "name": "C" }, { "name": "D" }], [])
	check(many.more == "A, B und 2 weitere" and many.people.size() == 3, "viele: höchstens drei Gesichter")
	var dc := [{ "name": "Sana", "state": "online", "game": "ELDEN RING" }, { "name": "Jo", "state": "offline", "game": "Elden Ring" },
			{ "name": "Kai", "state": "online", "game": "Hades" }]
	check(K.discord_playing(dc, "Elden Ring").size() == 1, "Discord: gleicher Name, nur wer online ist")
	check(K.discord_playing(dc, "").is_empty() and K.discord_playing([5, "x"], "Hades").is_empty(), "leerer Titel, Unsinn in der Liste")


func _sale() -> void:
	print("Wunschliste")
	var wl := [
		{ "appid": 10, "name": "Spiel", "discount": 25, "price": 1499 },
		{ "appid": 11, "name": "Erweiterung", "discount": 40, "price": 1999 },
		{ "appid": 12, "name": "Anderes DLC", "discount": 60, "price": 499, "parent": 10 },
		{ "appid": 13, "name": "Ohne Angebot", "discount": 0, "parent": 10 },
	]
	var own := K.sale_state(10, wl.slice(0, 1), [])
	check(own.kind == "rabatt" and own.text == "−25 %" and own.more.contains("Wunschliste"), "das Spiel selbst im Angebot")
	var dlc := K.sale_state(10, wl, [11])
	check(dlc.text == "DLC −60 %" and dlc.more.begins_with("Anderes DLC"), "größtes Angebot gewinnt (DLC über parent)")
	check(K.sale_state(10, wl.slice(1, 2), [11]).text == "DLC −40 %", "DLC über die Spielangaben (dlc_ids)")
	check(K.sale_state(99, wl, []).is_empty() and K.sale_state(0, wl, [11]).is_empty(), "fremdes Spiel, keine App-ID: nichts")
	check(K.sale_state(10, [wl[3], "x", 7], [13]).is_empty(), "ohne Rabatt und mit Unsinn: nichts")


func _achievements() -> void:
	print("Neue Erfolge")
	var now := 1_800_000_000
	var s1 := K.ach_step({}, 40, now)
	check(s1[1].is_empty() and int(s1[0].n) == 40, "erster Blick: nur merken")
	var s2 := K.ach_step(s1[0], 45, now + 100)
	check(s2[1].get("text", "") == "+5 neue Erfolge" and int(s2[0].n) == 45, "fünf mehr: „+5 neue Erfolge“")
	var s3 := K.ach_step(s2[0], 46, now + 200)
	check(s3[1].get("text", "") == "+6 neue Erfolge", "kurz danach noch einer: zählt mit (+6)")
	check(int(s3[0].plus) == 6, "Summe gemerkt")
	var later := K.ach_step(s3[0], 46, now + 200 + K.ACH_DAYS * 86400)
	check(later[1].is_empty(), "nach %d Tagen: vorbei" % K.ACH_DAYS)
	check(K.ach_step(s3[0], 30, now + 300)[1].is_empty(), "weniger (anderer Stand): nichts, neu merken")
	check(K.ach_step(s1[0], 0, now)[1].is_empty(), "keine Angabe: nichts")


func _news() -> void:
	print("Neuigkeiten")
	var bias := 3600
	# 12:00 Ortszeit an einem Tag (UTC 11:00).
	var noon := 1_800_000_000 - ((1_800_000_000 + bias) % 86400) + 12 * 3600 - bias
	var today := K.news_state([{ "title": "Patch 1.2", "date": noon - 3 * 3600, "patch": true }], noon, bias)
	check(today.kind == "patch" and today.text == "Patch heute" and today.more == "Patch 1.2", "Patch von heute früh")
	var yday := K.news_state([{ "title": "Ankündigung", "date": noon - 20 * 3600 }], noon, bias)
	check(yday.kind == "news" and yday.text == "Neuigkeit gestern", "gestern Abend: gestern")
	check(K.news_state([{ "title": "Alt", "date": noon - 3 * 86400 }], noon, bias).is_empty(), "älter: nichts")
	check(K.news_state([{ "title": "Zukunft", "date": noon + 86400 }], noon, bias).is_empty(), "Datum in der Zukunft: nichts")
	check(K.news_state([], noon, bias).is_empty() and K.news_state(["x"], noon, bias).is_empty(), "leer oder Unsinn: nichts")


func _status() -> void:
	print("Statusseite")
	var data := { "components": [
		{ "id": "f", "name": "Fortnite", "status": "operational", "group_id": null, "group": true, "components": ["f1", "f2"] },
		{ "id": "f1", "name": "Login", "status": "operational", "group_id": "f" },
		{ "id": "f2", "name": "Matchmaking", "status": "partial_outage", "group_id": "f" },
		{ "id": "r", "name": "Rocket League", "status": "under_maintenance", "group_id": null },
		{ "id": "s", "name": "Epic Games Store", "status": "operational", "group_id": null },
		"Unsinn", { "name": "ohne id" },
	] }
	var p := K.parse_status(data)
	check(p.bad.get("fortnite") == "partial_outage", "Gruppe: schlimmster Unterpunkt zählt (Matchmaking)")
	check(p.bad.get("rocket league") == "under_maintenance" and not p.bad.has("epic games store"), "Wartung ja, läuft nein")
	check(p.names.has("epic games store") and not p.names.has("login"), "Namen nur der obersten Ebene")
	check(K.parse_status("kaputt").bad.is_empty() and K.parse_status({ "components": "x" }).bad.is_empty() and K.parse_status(null).names.is_empty(),
			"kaputte Antworten: nichts")
	var big := { "components": [] }
	for i in 5000:
		big.components.append({ "id": str(i), "name": "Dienst %d" % i, "status": "major_outage", "group_id": null })
	check(K.parse_status(big).names.size() == K.STATUS_MAX, "riesige Antwort: höchstens %d Einträge" % K.STATUS_MAX)
	var long_name := { "components": [{ "id": "x", "name": "A".repeat(5000), "status": "major_outage", "group_id": null }] }
	check(str(K.parse_status(long_name).names[0]).length() <= 80, "lange Namen gekürzt")
	var now := 1_800_000_000
	var st := { "at": now - 60, "ok": true, "names": p.names, "bad": p.bad }
	var s := K.status_state("Fortnite", st, now)
	check(s.kind == "gestoert" and s.text == "Server gestört" and s.more == "Laut Epic-Statusseite", "Fortnite: gestört, mit Quelle")
	check(K.status_state("Rocket League®", st, now).text == "Wartung", "Rocket League: Wartung")
	check(K.status_state("Hades", st, now).is_empty(), "nicht auf der Seite: nichts")
	check(K.status_state("Fortnite", { "at": now - K.STATUS_MAX_AGE - 1, "bad": p.bad }, now).is_empty(), "alter Stand: lieber nichts")
	check(K.status_wanted([{ "source": "epic", "title": "X" }], []) and K.status_wanted([{ "source": "steam", "title": "Rocket League" }], ["rocket league"]),
			"fragen: Epic-Spiel oder bekannter Name")
	check(not K.status_wanted([{ "source": "steam", "title": "Hades" }], ["fortnite"]), "sonst nie fragen")


## Die Schicht auf einem echten Cover: Abzeichen, Aufwachen, Leichter Modus, Auswahlmodus, aus.
func _tile() -> void:
	print("Kachel")
	var g := { "id": "steam:777001", "source": "steam", "system": "steam", "appid": 777001, "title": "Probespiel", "installed": true }
	var saved: Array = Social.steam_friends
	Social.steam_friends = [{ "id": "1", "name": "Mira", "avatar": "", "state": "game", "game": "Probespiel", "game_id": "777001" }]
	var card = CoverCard.new().setup(g, false, Vector2(216, 288))
	card.live = true
	add_child(card)
	await get_tree().process_frame
	await get_tree().process_frame
	var layer: Control = card._live
	check(layer != null and layer.state.get("kind", "") == "freunde", "Freund spielt: Abzeichen „spielt gerade“")
	check(is_instance_valid(layer._pill) and layer._pill.size.x > 40.0 and layer._pill.position.x >= 0.0, "Abzeichen liegt auf dem Cover")
	var h0: float = layer._pill.size.y
	Leicht.active = false
	card.grab_focus()
	await get_tree().create_timer(layer.WAKE_S + 0.7).timeout
	check(layer.awake() and layer._pill.size.y > h0 + 4.0, "Auswahl ruht: wacht auf, zweite Zeile")
	card.release_focus()
	await get_tree().create_timer(0.4).timeout
	check(not layer.awake() and absf(layer._pill.size.y - h0) < 1.0, "Auswahl weg: schläft wieder")
	Leicht.active = true
	card.grab_focus()
	await get_tree().create_timer(layer.WAKE_S + 0.5).timeout
	check(not layer.awake(), "Leichter Modus: kein Aufwachen, nur das Abzeichen")
	card.release_focus()
	Leicht.active = false
	# Ein Update lädt über Uzai: geht den Freunden vor.
	Installs.items[str(g.id)] = { "id": str(g.id), "kind": "update", "phase": "downloading", "frac": 0.3, "text": "", "store": "steam", "started": 0 }
	Installs.changed.emit(str(g.id))
	await get_tree().process_frame
	await get_tree().process_frame
	check(layer.state.get("kind", "") == "update_laeuft" and layer.state.text == "Update · 30 %", "laufendes Update verdrängt die Freunde")
	Installs.items.erase(str(g.id))
	card.set_checked(false)
	await get_tree().process_frame
	check(layer.state.is_empty() and not is_instance_valid(layer._pill), "Auswahlmodus: kein Abzeichen")
	card.checked = -1
	layer.refresh()
	check(layer.state.get("kind", "") == "freunde", "zurück: wieder da")
	Config.set_value("system.live_tiles", false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(layer.state.is_empty(), "abgeschaltet: nichts")
	Config.set_value("system.live_tiles", true)
	Social.steam_friends = saved
	card.queue_free()
