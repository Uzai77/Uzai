extends Node
## Discord-Freunde und Übertragen: was Uzai aus Discords offiziellen Angaben über die Aktivität
## eines Freundes macht (src/core/discord_activity.gd – Uzais eigener Status, Musik, Stream, Dauer,
## Server-Widgets, gemeinsame Server, Spiel in der Bibliothek), dass die Freundesliste die Form
## übernimmt (DiscordChat.parse_friends), welche Zeile Discord in der Mitgliederliste zeigt
## (GamePresence) und wie Uzai Emulatoren überträgt, die Discord nicht als Spiel kennt (Weg,
## Fenster in Discords Auswahl, gelernte Erkennung).
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_discord_freunde.tscn → „Ergebnis: alles ok“

const DcActivity := preload("res://src/core/discord_activity.gd")
const GamePresence := preload("res://src/core/game_presence.gd")
const Main := preload("res://src/main.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Aktivität aus dem SDK")
	_normalize()
	print("Was der Freund gerade tut")
	_of()
	print("Server-Widgets und Bibliothek")
	_widgets()
	print("Freundesliste")
	_parse()
	print("Eigener Status")
	check(int(GamePresence.activity({ "source": "rom", "system": "ps2", "title": "Ōkami" }, "", 5, "PlayStation 2").get("display", -1)) == 2,
			"Emulator-Spiel: Freunde sehen „Spielt Ōkami“ statt „Spielt Uzai“")
	print("Übertragen: Emulatoren")
	_live()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _normalize() -> void:
	var u := DcActivity.normalize({ "game": "Uzai", "details": "Ratchet & Clank", "activity_state": "PlayStation 2 · Uzai", "start": 1700000000000 })
	check(u.game == "Ratchet & Clank" and u.details == "PlayStation 2" and u.activity_state == "", "Uzais Status: Titel ist das Spiel, System als Zusatz")
	check(int(u.since) == 1700000000, "Startzeit: Millisekunden → Sekunden")
	var pc := DcActivity.normalize({ "game": "Uzai", "details": "Hades", "activity_state": "Uzai", "start": 1700000000 })
	check(pc.game == "Hades" and pc.details == "" and int(pc.since) == 1700000000, "nur „Uzai“ als Zusatz: fällt weg, Sekunden bleiben")
	var app := DcActivity.normalize({ "game": "MeinUzai", "details": "Celeste", "activity_state": "Steam", "app": "42" }, "42")
	check(app.game == "Celeste" and app.details == "Steam", "eigene App-ID erkannt, auch ohne „· Uzai“")
	var other := DcActivity.normalize({ "game": "Elden Ring", "details": "Limgrave", "activity_state": "Stufe 40", "app": "7" }, "42")
	check(other.game == "Elden Ring" and other.details == "Limgrave" and other.activity_state == "Stufe 40", "fremde App: bleibt, wie Discord es meldet")
	var mu := DcActivity.normalize({ "game": "Uzai", "type": 2, "details": "To Zanarkand", "activity_state": "von Nobuo Uematsu", "start": 1000 })
	check(mu.game == "" and mu.music == "To Zanarkand" and mu.artist == "Nobuo Uematsu", "Musik (Typ 2): kein Spiel, Titel und Künstler")
	var none := DcActivity.normalize({ "game": "", "details": "", "start": 1700000000000 })
	check(none.game == "" and int(none.since) == 0, "ohne Aktivität: keine Startzeit")
	var dirty := DcActivity.normalize({ "game": "A\nB\u0007", "details": 5, "start": "x" })
	check(dirty.game == "A B" and dirty.details == "" and int(dirty.since) == 0, "fremde Daten: Steuerzeichen raus, falsche Typen leer")
	check(DcActivity.normalize({ "game": "x".repeat(400) }).game.length() == 128, "höchstens 128 Zeichen")


func _of() -> void:
	var now := 1700003000
	var g := DcActivity.of({ "game": "Ratchet & Clank", "details": "PlayStation 2", "since": 1700000000 })
	check(g.kind == "game" and DcActivity.headline(g) == "Spielt Ratchet & Clank", "Spiel: „Spielt …“")
	check(DcActivity.subline(g, now) == "PlayStation 2  ·  seit 50 Min.", "Zusatz mit Dauer (%s)" % DcActivity.subline(g, now))
	var m := DcActivity.of({ "music": "To Zanarkand", "artist": "Nobuo Uematsu", "since": now - 95 })
	check(DcActivity.headline(m) == "Hört To Zanarkand" and DcActivity.subline(m, now) == "Nobuo Uematsu  ·  seit 1 Min.", "Musik: „Hört …“, Künstler, Dauer")
	check(DcActivity.headline(DcActivity.of({ "streaming": true })) == "Streamt", "Stream ohne Spiel: „Streamt“")
	check(DcActivity.of({ "game": "", "state": "online" }).kind == "", "nichts bekannt: keine Aktivität (die Oberfläche lässt die Zeile weg)")
	check(DcActivity.of({}, "Balatro").title == "Balatro" and DcActivity.subline(DcActivity.of({}, "Balatro"), now) == "", "Widget: nur der Name")
	check(DcActivity.of({ "game": "Hades" }, "Balatro").title == "Hades", "SDK vor Widget")
	check(DcActivity.since_text(now + 60, now) == "" and DcActivity.since_text(now - 3 * 86400, now) == "" and DcActivity.since_text(0, now) == "",
			"unsinnige Zeiten (Zukunft, Tage her, keine): nichts")


func _widgets() -> void:
	var servers := { "1": { "name": "Retro-Runde", "members": [{ "name": "Sana", "game": "PCSX2" }, { "name": "kai", "game": "" }] },
		"2": { "name": "Zocken", "members": [{ "name": "KAI" }] }, "3": "kaputt" }
	check(DcActivity.widget_game({ "name": "sana" }, servers) == "PCSX2", "Widget-Aktivität über den Namen")
	check(DcActivity.widget_game({ "name": "Kai" }, servers) == "", "ohne Aktivität im Widget: nichts")
	var sh := DcActivity.shared_servers({ "name": "Kai Neu", "username": "kai" }, servers)
	check(sh.size() == 2 and sh.has("Retro-Runde") and sh.has("Zocken"), "gemeinsame Server auch über den Nutzernamen, kaputte Einträge übergangen")
	var lib := [{ "title": "RATCHET & CLANK", "installed": false }, { "title": "Ratchet & Clank", "id": "rom:r" }]
	check(str(DcActivity.owned("Ratchet & Clank", lib).get("id", "")) == "rom:r", "Spiel in der Bibliothek (installiert, Schreibweise egal)")
	check(DcActivity.owned("", lib).is_empty() and DcActivity.owned("Okami", lib).is_empty(), "kein Titel oder nicht da: nichts")


func _parse() -> void:
	var list := DiscordChat.parse_friends([
		{ "id": "1", "name": "Sana", "state": "online", "game": "Uzai", "details": "Ratchet & Clank", "activity_state": "PlayStation 2 · Uzai", "start": 1700000000000 },
		{ "id": "2", "name": "Kai", "state": "online", "game": "Uzai", "type": 2, "details": "To Zanarkand", "activity_state": "von Nobuo Uematsu" },
		{ "id": "3", "name": "Noor", "state": "away" },
	])
	var s := list.filter(func(f): return f.id == "1")[0] as Dictionary
	check(s.game == "Ratchet & Clank" and s.details == "PlayStation 2" and int(s.since) == 1700000000 and bool(s.dm), "Freund mit Uzais Status")
	check(str(list[0].id) == "1", "wer spielt, steht vorn")
	var k := list.filter(func(f): return f.id == "2")[0] as Dictionary
	check(k.game == "" and k.music == "To Zanarkand", "Freund hört Musik: steht nicht als „spielt“")


func _live() -> void:
	check(Main.live_route("auto", "pcsx2", {}) == "app", "unbekannt, ob Discord PCSX2 kennt: gleich über die App (Fenster teilen)")
	check(Main.live_route("auto", "pcsx2", { "pcsx2": false }) == "app", "nicht erkannt: über die App")
	check(Main.live_route("auto", "pcsx2", { "pcsx2": true }) == "keys", "erkannt: Taste, ohne Umweg")
	check(Main.live_route("auto", "", {}) == "keys" and Main.live_route("keys", "pcsx2", {}) == "keys", "Steam-Spiel oder nur Taste: Taste")
	check(Main.live_route("discord", "", {}) == "app" and Main.live_route("auto", "duckstation", "kaputt") == "app", "immer App; kaputte Einstellung: App")
	var keys := Main.live_window_keys("PCSX2 v2.2.0 | Ratchet & Clank", "PCSX2", "Ratchet & Clank")
	check(keys.size() == 3 and keys[1] == "pcsx2", "Fenster-Merkmale: Titel, Emulator, Spiel (klein)")
	check(Main.live_window_keys("", "PS", "pcsx2").size() == 1, "kurze und doppelte fallen weg")
	var pick0 := [{ "i": 0, "name": "Bildschirm teilen", "enabled": true }, { "i": 1, "name": "Mikrofon stummschalten", "enabled": true }]
	check(Main.live_detection(pick0) == "nein", "nur „Bildschirm teilen“: Discord kennt das Spiel nicht")
	check(Main.live_detection([{ "name": "PCSX2 streamen" }]) == "ja" and Main.live_detection([{ "name": "Mikro" }]) == "", "„… streamen“: erkannt; nichts: offen")
	var dlg := [{ "i": 0, "name": "Go Live", "enabled": false }, { "i": 1, "name": "Discord", "enabled": true },
		{ "i": 2, "name": "PCSX2 v2.2.0 | Ratchet & Clank", "enabled": true }, { "i": 3, "name": "Abbrechen", "enabled": true }]
	var p := Main.share_pick(dlg, "Ratchet & Clank", true, true, keys)
	check(int(p.get("i", -1)) == 2 and str(p.kind) == "window", "Auswahl offen: erst das Emulator-Fenster")
	check(Main.share_pick(dlg, "Ratchet & Clank", true, true, []).is_empty(), "Fenster gewählt, Live gehen noch aus: nichts drücken")
	dlg[0].enabled = true
	check(str(Main.share_pick(dlg, "Ratchet & Clank", true, true, []).kind) == "golive", "danach „Live gehen“")
	check(str(Main.share_pick(dlg, "x", true, false, keys).get("kind", "")) != "window", "vor dem Öffnen nie eine Fenster-Kachel")
	check(Main.live_hint(true, "Ratchet & Clank", "PCSX2").contains("Fenster von PCSX2") and not Main.live_hint(true, "Hades").contains("Fenster von"),
			"Hinweis-Karte nennt das Fenster nur, wenn Discord das Spiel nicht kennt")
