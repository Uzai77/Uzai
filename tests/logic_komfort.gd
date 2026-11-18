extends Node
## Komfortfunktionen (docs/QOL.md): Schlaf-Timer, Nicht stören, Nachts leiser, Melden, wenn
## online, Mitteilungen entfernen, Schnellmenü-Kacheln und ihre Verdrahtung.
## Aufruf: UZAI_DATA=<leerer ordner> godot --headless --path . res://tests/logic_komfort.tscn

const SchlafTimer := preload("res://src/core/schlaf_timer.gd")
const NichtStoeren := preload("res://src/core/nicht_stoeren.gd")
const NachtTon := preload("res://src/core/nacht_ton.gd")
const Wahl := preload("res://src/ui/components/guide_quick_wahl.gd")
const Quelle := preload("res://tests/quelle.gd")
const T0 := 1_800_000_000

var fails := 0


class FakeRest extends Node:
	var active := false
	var calls: Array = []

	func enter(src := "", opts := {}) -> void:
		calls.append([src, opts])


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_schlaf_logik()
	await _schlaf_lauf()
	await _nicht_stoeren()
	_mitteilungen_leeren()
	_nacht()
	_online()
	_kacheln()
	_verdrahtung()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _schlaf_logik() -> void:
	print("Schlaf-Timer: Logik")
	check(SchlafTimer.naechste("", false) == "15" and SchlafTimer.naechste("15", false) == "30" and SchlafTimer.naechste("90", false) == "",
			"ohne Video: 15 → 30 → … → 90 → aus")
	check(SchlafTimer.naechste("90", true) == "ende" and SchlafTimer.naechste("ende", true) == "", "mit Video: nach 90 Min. „Ende“, dann aus")
	check(SchlafTimer.naechste("ende", false) == "15", "„Ende“ ohne Video: weiter zu 15")
	check(SchlafTimer.naechste("quatsch", true) == "15", "Unbekanntes: von vorn")
	check(SchlafTimer.frist("30", T0) == T0 + 1800 and SchlafTimer.frist("ende", T0) == 0 and SchlafTimer.frist("", T0) == 0, "Frist nur bei Minuten")
	check(SchlafTimer.rest_min(T0 + 1800, T0) == 30 and SchlafTimer.rest_min(T0 + 61, T0) == 2 and SchlafTimer.rest_min(T0 + 1, T0) == 1
			and SchlafTimer.rest_min(T0 - 5, T0) == 0, "verbleibende Minuten aufgerundet")
	check(not SchlafTimer.faellig("30", T0 + 10, T0) and SchlafTimer.faellig("30", T0, T0) and not SchlafTimer.faellig("ende", T0, T0 + 9)
			and not SchlafTimer.faellig("", T0, T0 + 9), "fällig erst zur Frist, nie bei „Ende“ oder aus")
	check(SchlafTimer.warnen("30", T0 + 60, T0, false) and not SchlafTimer.warnen("30", T0 + 60, T0, true) and not SchlafTimer.warnen("30", T0 + 61, T0, false)
			and not SchlafTimer.warnen("30", T0, T0, false), "eine Minute vorher genau einmal warnen")
	check(SchlafTimer.zustand("", 0, T0, "") == "" and SchlafTimer.zustand("30", T0 + 600, T0, "") == "noch 10 Min.", "Zustand: aus bzw. Restzeit")
	check(SchlafTimer.zustand("ende", 0, T0, "series") == "Nach dieser Folge" and SchlafTimer.ende_text("movie") == "Nach diesem Film"
			and SchlafTimer.ende_text("video") == "Nach diesem Video", "Ende: Folge, Film, Video")
	var o := SchlafTimer.optionen(false, "")
	check(o.size() == 5 and str(o[0][0]) == "" and not o.any(func(x) -> bool: return str(x[0]) == "ende"), "Menü ohne Video: aus und vier Zeiten")
	check(SchlafTimer.optionen(true, "series").back() == ["ende", "Nach dieser Folge"], "Menü mit Folge: „Nach dieser Folge“ zuletzt")
	for x in SchlafTimer.optionen(true, "video"):
		check(SchlafTimer.gueltig(str(x[0])), "Menüwert „%s“ ist eine Stufe" % str(x[0]))


func _schlaf_lauf() -> void:
	print("Schlaf-Timer: Ablauf")
	var rest := FakeRest.new()
	add_child(rest)
	var st = SchlafTimer.new()
	st.rest = rest
	rest.add_child(st)
	await get_tree().process_frame
	var vor := int(Time.get_unix_time_from_system())
	st.setzen("30")
	var now := int(Time.get_unix_time_from_system())
	check(st.stufe == "30" and st.bis >= vor + 1800 and st.bis <= now + 1800 and st.an(), "30 Min. gestellt")
	check(st.text().begins_with("noch "), "Kachel zeigt die Restzeit")
	st.weiter()
	check(st.stufe == "60", "Kachel: weiter auf 60")
	st.setzen("ende")
	check(st.stufe == "" and not st.an(), "„Nach diesem Video“ ohne Video: aus")
	st.setzen("15")
	st.bis = now - 1
	st._tick()
	await get_tree().process_frame
	check(st.stufe == "" and rest.calls.size() == 1 and str(rest.calls[0][0]) == "schlaf-timer", "Frist um: Ruhemodus, Timer aus")
	st.setzen("60")
	rest.active = true
	st._tick()
	check(st.stufe == "" and rest.calls.size() == 1, "schon im Ruhemodus: Timer erledigt, kein zweites Einschlafen")
	rest.active = false
	st.stufe = "ende"
	st._on_stopped()
	check(st.stufe == "", "Video von Hand beendet: „nach diesem Video“ gilt nicht weiter")
	st.stufe = "ende"
	st._on_end()
	await get_tree().process_frame
	check(st.stufe == "" and rest.calls.size() == 2, "Ende des Videos: Ruhemodus statt nächster Folge")
	st.setzen("quatsch")
	check(st.stufe == "", "ungültige Stufe: aus")
	rest.queue_free()


func _nicht_stoeren() -> void:
	print("Nicht stören")
	check(NichtStoeren.ruhig(true, false, false) and NichtStoeren.ruhig(false, true, true) and not NichtStoeren.ruhig(false, true, false)
			and not NichtStoeren.ruhig(false, false, true), "von Hand oder beim Film (wenn eingestellt)")
	check(bool(Config.DEFAULTS.notify.ruhe_film), "beim Film: Standard an")
	check(not NichtStoeren.film_laeuft() and not NichtStoeren.aktiv() and NichtStoeren.zustand() == "", "ohne Film und von Hand aus: aus")
	NichtStoeren.an = true
	check(NichtStoeren.aktiv() and NichtStoeren.zustand() == "An", "von Hand an")
	var h0: int = Toasts.history.size()
	var u0: int = Toasts.unread
	var s0: int = Toasts.still
	var b0: int = Toasts._box.get_child_count()
	Toasts.show_toast("Mira", "Kommst du?", "chat", { "stoert": true, "overlay": true })
	check(Toasts.history.size() == h0 + 1 and Toasts.unread == u0 + 1 and Toasts.still == s0 + 1, "Nachricht landet in den Mitteilungen")
	check(Toasts._box.get_child_count() == b0, "… ohne Pop-up")
	Toasts.show_toast("Bildschirmfoto gespeichert", "", "camera")
	check(Toasts._box.get_child_count() == b0 + 1, "eigene Rückmeldungen kommen weiter")
	Notify.last = {}
	Notify.pop("steam", "Mira", "Hallo", "chat", "", { "id": "76561198000000001", "name": "Mira" })
	check(Notify.last.is_empty() and Toasts.still == s0 + 2, "Steam-Nachricht still: die Guide-Taste öffnet nichts")
	NichtStoeren.an = false
	Notify.pop("steam", "Mira", "Hallo", "chat", "", { "id": "76561198000000001", "name": "Mira" })
	check(not Notify.last.is_empty() and Toasts.still == s0 + 2, "wieder aus: Pop-up wie sonst")
	Notify.last = {}
	await get_tree().process_frame


func _mitteilungen_leeren() -> void:
	print("Mitteilungen entfernen")
	Toasts.show_toast("Eins", "", "info")
	Toasts.show_toast("Zwei", "", "info")
	var n: int = Toasts.history.size()
	var old: Array = Toasts.clear_history()
	check(old.size() == n and Toasts.history.is_empty() and Toasts.unread == 0, "alle weg, nichts mehr neu")
	Toasts.show_toast("Drei", "", "info")
	Toasts.restore_history(old)
	check(Toasts.history.size() == n + 1 and str(Toasts.history[0].title) == "Drei" and str(Toasts.history[1].title) == "Zwei",
			"Rückgängig: die alten zurück, Neueres bleibt vorn")
	var viele: Array = []
	for i in 70:
		viele.append({ "title": str(i) })
	Toasts.restore_history(viele)
	check(Toasts.history.size() == 60, "höchstens 60 wie sonst")


func _nacht() -> void:
	print("Nachts leiser")
	check(NachtTon.im_fenster(23, 22, 7) and NachtTon.im_fenster(3, 22, 7) and not NachtTon.im_fenster(7, 22, 7) and not NachtTon.im_fenster(12, 22, 7),
			"22 bis 7 Uhr: über Mitternacht, bis ausschließlich")
	check(NachtTon.im_fenster(2, 0, 6) and not NachtTon.im_fenster(6, 0, 6) and not NachtTon.im_fenster(23, 0, 6), "0 bis 6 Uhr")
	check(not NachtTon.im_fenster(5, 7, 7), "gleiche Stunden: nie")
	check(NachtTon.grenze_bei("30", 22, 7, 23) == 30 and NachtTon.grenze_bei("30", 22, 7, 12) == -1 and NachtTon.grenze_bei("aus", 22, 7, 23) == -1,
			"Grenze nur im Fenster und nur, wenn an")
	check(NachtTon.grenze_bei("1", 22, 7, 23) == 5 and NachtTon.grenze_bei("400", 22, 7, 23) == 100 and NachtTon.grenze_bei("30", 99, -4, 23) == 30,
			"Werte aus der Datei begrenzt")
	check(NachtTon.senken_auf(80, 30) == 30 and NachtTon.senken_auf(20, 30) == -1 and NachtTon.senken_auf(30, 30) == -1 and NachtTon.senken_auf(80, -1) == -1,
			"nur senken, nie lauter")
	check(str(Config.DEFAULTS.system.nacht_laut) == "aus", "Standard aus")
	var h := int(Time.get_datetime_dict_from_system().hour)
	var keep := [Config.get_value("system.nacht_laut"), Config.get_value("system.nacht_von"), Config.get_value("system.nacht_bis")]
	Config.set_value("system.nacht_laut", "30")
	Config.set_value("system.nacht_von", str(h))
	Config.set_value("system.nacht_bis", str((h + 1) % 24))
	check(NachtTon.jetzt() == 30 and NachtTon.begrenzt(80) == 30 and NachtTon.begrenzt(20) == 20, "jetzt im Fenster: Mixer höchstens 30 %")
	Config.set_value("system.nacht_laut", "aus")
	check(NachtTon.jetzt() == -1 and NachtTon.begrenzt(80) == 80, "aus: keine Grenze")
	Config.set_value("system.nacht_laut", keep[0])
	Config.set_value("system.nacht_von", keep[1])
	Config.set_value("system.nacht_bis", keep[2])
	for o in NachtTon.STUFEN + NachtTon.VON + NachtTon.BIS:
		check(str(o[0]) == "aus" or str(o[0]).is_valid_int(), "Wahl „%s“ ist eine Zahl oder aus" % str(o[1]))


func _online() -> void:
	print("Melden, wenn online")
	var a := "76561198000000001"
	var b := "76561198000000002"
	var keep: Variant = Config.get_value("notify.watch", [])
	check(Notify.watch_id_ok(a) and not Notify.watch_id_ok("") and not Notify.watch_id_ok("12ab5") and not Notify.watch_id_ok("-1234567")
			and not Notify.watch_id_ok("1".repeat(30)), "nur Steam-IDs aus Ziffern")
	Config.set_value("notify.watch", [a, a, 7, "x", null, b])
	check(Notify.watch_list() == [a, b], "gespeicherte Liste geprüft: doppelte und Fremdes fallen weg")
	Config.set_value("notify.watch", "kaputt")
	check(Notify.watch_list().is_empty(), "keine Liste: leer")
	Config.set_value("notify.watch", [])
	Notify.watch_set(a, true)
	check(Notify.watching(a) and not Notify.watching(b), "merken")
	Notify.watch_set("böse", true)
	check(Notify.watch_list() == [a], "Unsinn wird nicht gemerkt")
	var prev := { a: false, b: false }
	var friends := [{ "id": a, "state": "online" }, { "id": b, "state": "online" }, "kaputt"]
	check(Notify.came_online(prev, friends, [a]).size() == 1, "nur gemerkte Freunde")
	check(Notify.came_online({}, friends, [a, b]).is_empty(), "erste Liste nach dem Start: nichts melden")
	check(Notify.came_online({ a: true }, friends, [a]).is_empty(), "war schon online: nichts")
	check(Notify.came_online(prev, [{ "id": a, "state": "offline" }], [a]).is_empty(), "noch offline: nichts")
	# Ablauf über Social: erst offline, dann online → eine leise Mitteilung, die in den Chat führt.
	Toasts.clear_history()
	var sf: Array = Social.steam_friends
	Notify._online = {}
	Social.steam_friends = [{ "id": a, "name": "Mira", "state": "offline", "avatar": "" }]
	Notify._on_social("steam")
	var h0: int = Toasts.history.size()
	Social.steam_friends = [{ "id": a, "name": "Mira", "state": "online", "avatar": "" }]
	Notify._on_social("discord")
	check(Toasts.history.size() == h0, "Discord-Meldung: Steam-Liste nicht neu ansehen")
	Notify._on_social("steam")
	check(Toasts.history.size() == h0 + 1 and str(Toasts.history[0].title) == "Mira" and str(Toasts.history[0].sub) == "ist jetzt online",
			"online gekommen: Mitteilung")
	check((Toasts.history[0].get("go", Callable()) as Callable).is_valid() and str(Toasts.history[0].go_text) == "Chat öffnen", "… führt in den Chat")
	Notify._on_social("steam")
	check(Toasts.history.size() == h0 + 1, "bleibt online: nur einmal")
	Notify.watch_set(a, false)
	check(not Notify.watching(a), "nicht mehr melden")
	Social.steam_friends = sf
	Notify._online = {}
	Config.set_value("notify.watch", keep)


func _kacheln() -> void:
	print("Schnellmenü-Kacheln")
	for id in ["schlaf", "ruhe", "hoeren"]:
		check(Wahl.bekannt(id) and not Wahl.STANDARD.has(id), "%s: wählbar, nicht im Standard" % id)
	check(Wahl.da("schlaf", {}) and Wahl.da("ruhe", { "game": true }), "Schlaf-Timer und Nicht stören immer")
	check(Wahl.da("hoeren", { "hoeren": true }) and not Wahl.da("hoeren", { "hoeren": true, "game": true }) and not Wahl.da("hoeren", {}),
			"Nur hören nur mit Musik und ohne Spiel")


func _verdrahtung() -> void:
	print("Verdrahtung")
	var rest := Quelle.lesen("res://src/core/rest.gd")
	check(rest.contains("SchlafTimer.new()") and rest.contains("\"hoeren\"") and rest.contains("_pads_off()") and rest.contains("rest.pads_off"),
			"Ruhemodus: Schlaf-Timer, Nur hören, Controller aus")
	check(rest.contains("not Video.paused and not hoeren") and rest.contains("not active or _waking or hoeren"),
			"Nur hören: nichts anhalten, kein Bildschirm aus, keine Diashow")
	var pm := Quelle.lesen("res://src/ui/layers/power_menu.gd")
	check(pm.contains("\"schlaf\"") and pm.contains("\"hoeren\"") and pm.contains("open_choice(\"Schlaf-Timer\""), "Ausschalten-Menü: Schlaf-Timer und Nur hören")
	check(Quelle.lesen("res://src/ui/layers/video_player.gd").contains("\"Schlaf-Timer\""), "Video, Y → Wiedergabe: Schlaf-Timer")
	check(Quelle.lesen("res://src/ui/layers/guide.gd").contains("NichtStoeren.umschalten()"), "Guide → System: Nicht stören")
	check(Quelle.lesen("res://src/ui/layers/friend_actions.gd").contains("Notify.watch_set("), "Freundes-Menü: Melden, wenn online")
	check(Quelle.lesen("res://src/main_discord.gd").contains("Toasts.clear_history()") and Quelle.lesen("res://src/main_discord.gd").contains("\"uz_on_y\""),
			"Mitteilungen: Y entfernt alle")
	check(Quelle.lesen("res://src/core/mixer.gd").contains("NachtTon.begrenzt(") and Quelle.lesen("res://src/core/mixer.gd").contains("NachtTon.new()"),
			"Mixer: nachts begrenzt, Prüfung hängt am Mixer")
	for p in ["res://src/core/social.gd", "res://src/core/store.gd"]:
		check(Quelle.lesen(p).contains("\"stoert\": true"), "%s: Hinweis von außen" % p.get_file())
	var sv := Quelle.lesen("res://src/ui/sections/settings_system.gd")
	check(sv.contains("\"rest.pads_off\"") and sv.contains("\"system.nacht_laut\"") and sv.contains("\"notify.ruhe_film\""), "Einstellungen: alle drei Schalter")
