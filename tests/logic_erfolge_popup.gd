extends Node
## Erfolgs-Pop-ups ohne Netz: Uzai-Punkte aus der Seltenheit, Aussehen (normal, selten, ultra,
## retro), Steam-Zwischenspeicher (binäre KeyValues: Schema und Spielerdaten) lesen und
## vergleichen, Sitzung mit echten Dateien (Stand, neue Freischaltung, nichts doppelt),
## Web-API und RetroAchievements, Warteschlange, Zeitplan der Animation, Speichern.
## Aufruf: UZAI_DATA=<leerer ordner> godot --headless --path . res://tests/logic_erfolge_popup.tscn

const U := preload("res://src/core/unlocks.gd")
const Toast := preload("res://src/ui/components/achievement_toast.gd")
const APPID := 4242

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_points()
	_decorate()
	_diff()
	_kv()
	await _session()
	_web_and_ra()
	await _queue()
	_timeline()
	await _store()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _points() -> void:
	print("Uzai-Punkte aus der Seltenheit")
	check(U.points_for(80.0) == 10 and U.points_for(50.0) == 10, "≥ 50 % → 10")
	check(U.points_for(49.9) == 20 and U.points_for(20.0) == 20, "20–50 % → 20")
	check(U.points_for(19.9) == 30 and U.points_for(10.0) == 30, "10–20 % → 30")
	check(U.points_for(9.9) == 50 and U.points_for(5.0) == 50, "5–10 % → 50")
	check(U.points_for(4.9) == 75 and U.points_for(1.0) == 75, "1–5 % → 75")
	check(U.points_for(0.99) == 100 and U.points_for(0.0) == 100, "unter 1 % → 100")
	check(U.points_for(-1.0) == 20, "unbekannt → 20")
	check(U.points_for_ra(5, 3.0) == 75, "RA mit Seltenheit: wie Steam")
	check(U.points_for_ra(1) == 10 and U.points_for_ra(10) == 30 and U.points_for_ra(25) == 50 and U.points_for_ra(50) == 75 and U.points_for_ra(100) == 100,
			"RA ohne Seltenheit: aus den RA-Punkten")
	check(U.entry_points({ "platform": "ra", "ra_points": 10, "rarity": -1.0 }) == 30, "Eintrag RA: 10 RA-Punkte → 30")
	check(U.num_text(1240) == "1.240" and U.num_text(20) == "20" and U.num_text(1234567) == "1.234.567", "Zahlen mit Punkt: 1.240")
	check(
			U.score_list({ "source": "steam",
			"list": [{ "unlocked": true, "rarity": 60.0 }, { "unlocked": true, "rarity": 3.0 }, { "unlocked": false, "rarity": 0.5 }] }) == { "points": 85, "max": 185,
			"count": 2, "total": 3 }, "Spiel: Punkte, möglich, Anzahl")


func _decorate() -> void:
	print("Aussehen")
	for snd in ["unlock", "unlock_rare", "unlock_retro"]:
		check(ResourceLoader.exists("res://assets/sounds/%s.wav" % snd) and Sfx._streams.get(snd) != Sfx._streams.get("achievement"),
				"eigener Klang %s.wav (importiert, nicht der alte Erfolgsklang)" % snd)
	var n := U.decorate({ "rarity": 42.0, "platform": "steam" })
	check(n.variant == "normal" and n.line1 == "Erfolg freigeschaltet" and n.sound == "unlock" and not n.rare, "normal: „Erfolg freigeschaltet“, eigener Klang")
	var r := U.decorate({ "rarity": 3.2, "platform": "steam" })
	check(r.variant == "rare" and r.line1 == "Seltener Erfolg · 3,2 % der Spieler" and r.sound == "unlock_rare",
			"selten (< 10 %): „Seltener Erfolg · 3,2 % der Spieler“")
	check(U.decorate({ "rarity": 3.2, "platform": "steam" }, false).variant == "normal", "„Seltene hervorheben“ aus: normal")
	var u := U.decorate({ "rarity": 0.4, "platform": "steam" })
	check(u.variant == "ultra" and u.line1.begins_with("Ultraseltener Erfolg · 0,4 %"), "unter 1 %: ultraselten")
	check(U.decorate({ "rarity": -1.0, "platform": "steam" }).variant == "normal", "Seltenheit unbekannt: normal")
	var ra := U.decorate({ "platform": "ra", "ra_points": 10, "hardcore": true, "rarity": -1.0 })
	check(ra.variant == "retro" and ra.line1 == "Retro-Erfolg freigeschaltet · 10 RA-Punkte" and ra.chip == "Hardcore" and ra.sound == "unlock_retro",
			"retro: RA-Punkte, Hardcore, eigener Klang")
	check(U.decorate({ "platform": "ra", "ra_points": 25, "rarity": 4.0 }).line1.begins_with("Seltener Retro-Erfolg"), "retro selten")


func _diff() -> void:
	print("Was ist neu?")
	var now := { "A": 1000, "B": 5000, "C": 0 }
	check(U.diff_new({}, now, true, 4990) == ["B"], "erster Blick: nur nach dem Start freigeschaltete (B)")
	check(U.diff_new({}, now, true, 5030).is_empty(), "erster Blick: alles älter → nichts")
	check(U.diff_new({ "A": true, "B": true, "C": true }, now, false, 0).is_empty(), "alles bekannt → nichts")
	check(U.diff_new({ "A": true }, now, false, 0) == ["C", "B"], "danach: alles Unbekannte, nach Zeit")
	check(U.hold_for(0) > U.hold_for(1) and U.hold_for(1) > U.hold_for(3) and U.hold_for(10) == 1.0, "viele warten: kürzer halten")
	# Änderungszeit nur in Sekunden: eine gerade geänderte Datei wird auch bei gleicher Zeit gelesen.
	check(U.must_read(100, 100, 100) and U.must_read(100, 100, 102) and not U.must_read(100, 100, 103),
			"gleiche Zeit: lesen, solange die Änderung höchstens 2 s her ist")
	check(U.must_read(101, 100, 500), "andere Zeit: lesen")


# --- Binäre KeyValues ---------------------------------------------------------------------

static func kv(d: Dictionary) -> PackedByteArray:
	var b := PackedByteArray()
	for k in d.keys():
		var v: Variant = d[k]
		if v is Dictionary:
			b.append(0)
			b.append_array(str(k).to_utf8_buffer())
			b.append(0)
			b.append_array(kv(v))
			b.append(8)
		elif v is String:
			b.append(1)
			b.append_array(str(k).to_utf8_buffer())
			b.append(0)
			b.append_array((v as String).to_utf8_buffer())
			b.append(0)
		elif v is float:
			b.append(3)
			b.append_array(str(k).to_utf8_buffer())
			b.append(0)
			var f := PackedByteArray()
			f.resize(4)
			f.encode_float(0, v)
			b.append_array(f)
		else:
			b.append(2)
			b.append_array(str(k).to_utf8_buffer())
			b.append(0)
			var n := PackedByteArray()
			n.resize(4)
			n.encode_s32(0, int(v))
			b.append_array(n)
	return b


static func kv_file(d: Dictionary) -> PackedByteArray:
	var b := kv(d)
	b.append(8)
	return b


static func schema() -> Dictionary:
	var bits := {}
	var names := [["ACH_START", "Erste Schritte", "First Steps"], ["ACH_BOSS", "Bossbezwinger", "Boss Slayer"], ["ACH_SECRET", "", "Hidden One"]]
	for i in names.size():
		var nm := { "english": names[i][2] }
		if names[i][1] != "":
			nm["german"] = names[i][1]
		bits[str(i)] = { "name": names[i][0], "bit": i,
				"display": { "name": nm, "desc": { "english": "Desc %d" % i }, "hidden": "1" if i == 2 else "0", "icon": "ic%d.jpg" % i, "icon_gray": "g.jpg" } }
	return { str(APPID): { "gamename": "Testspiel", "version": "7", "stats": {
		"1": { "type": "4", "id": "1", "bits": bits },
		"2": { "type": "1", "id": "2", "name": "kills", "min": "0" } } } }


static func user(data: int, times: Dictionary) -> Dictionary:
	return { "cache": { "crc": 12345, "PendingChanges": 0, "1": { "data": data, "AchievementTimes": times }, "2": { "data": 57 } } }


func _kv() -> void:
	print("Steam-Zwischenspeicher (binäre KeyValues)")
	var sb := U.parse_kv(kv_file(schema()))
	check(sb.has(str(APPID)) and str(sb[str(APPID)].gamename) == "Testspiel", "Schema gelesen")
	var bits := U.schema_bits(sb)
	check(bits.size() == 3 and bits["1/0"].api == "ACH_START" and bits["1/0"].title == "Erste Schritte" and bits["1/2"].title == "Hidden One",
			"Bits → Namen (deutsch, sonst englisch)")
	check(bits["1/2"].hidden and bits["1/1"].icon == "ic1.jpg", "versteckt und Bilddatei")
	var ub := U.parse_kv(kv_file(user(0b011, { "0": 1700000000, "1": 1700000500 })))
	var got := U.unlocked_from_stats(ub, bits)
	check(got == { "ACH_START": 1700000000, "ACH_BOSS": 1700000500 }, "freigeschaltet aus data-Bits und Zeiten (Zahl-Statistik ignoriert)")
	check(U.unlocked_from_stats(ub, {}) == { "1/0": 1700000000, "1/1": 1700000500 }, "ohne Schema: Statistik/Bit")
	check(U.parse_kv(PackedByteArray([0, 65, 66])).is_empty(), "abgeschnittene Datei → leer, kein Absturz")
	check(U.parse_kv(PackedByteArray([9, 65, 0])).is_empty(), "unbekannter Typ → leer")
	var flt := U.parse_kv(kv_file({ "x": { "f": 1.5, "s": "ä" } }))
	check(is_equal_approx(float(flt.x.f), 1.5) and str(flt.x.s) == "ä", "Kommazahl und UTF-8")


func _session() -> void:
	print("Sitzung mit echten Dateien")
	var dir := Config.path("steamtest/appcache/stats")
	DirAccess.make_dir_recursive_absolute(dir)
	var started := int(Time.get_unix_time_from_system())
	Config.set_value("accounts.steam_id", "76561198000000123")
	var acc := 76561198000000123 - 76561197960265728
	var userf := dir.path_join("UserGameStats_%d_%d.bin" % [acc, APPID])
	_write(dir.path_join("UserGameStatsSchema_%d.bin" % APPID), kv_file(schema()))
	# Vorher: ACH_START schon lange frei.
	_write(userf, kv_file(user(0b001, { "0": started - 86400 })))
	_write(dir.path_join("UserGameStats_999_%d.bin" % APPID), kv_file(user(0b111, { "0": 1, "1": 2, "2": 3 })))
	var before := Unlocks.history().size()
	var shown0: int = Unlocks.popups.shown
	Unlocks.begin_steam_session(APPID, "Testspiel", dir, started)
	check(str(Unlocks.session().file) == userf, "Datei des eigenen Kontos (Konto-ID aus der Steam-ID)")
	check(Unlocks.session().known.has("ACH_START") and Unlocks.history().size() == before, "erster Blick: Stand, kein Pop-up für Altes")
	# Freischaltung im Spiel: Bit 1 dazu, neue Zeit; Steam schreibt die Datei neu.
	await get_tree().create_timer(1.1).timeout
	_write(userf, kv_file(user(0b011, { "0": started - 86400, "1": started + 5 })))
	Unlocks._poll_file()
	await get_tree().create_timer(0.1).timeout
	var h := Unlocks.history()
	check(h.size() == before + 1 and str(h[0].api) == "ACH_BOSS" and str(h[0].name) == "Bossbezwinger", "neuer Erfolg erkannt: Name aus dem Schema")
	check(str(h[0].icon).ends_with("/%d/ic1.jpg" % APPID) and str(h[0].game_key) == "steam:%d" % APPID, "Bild-Adresse und Spielschlüssel")
	check(Unlocks.popups.shown + Unlocks.popups.waiting() > shown0, "Pop-up gezeigt")
	# Dieselbe Datei noch einmal geschrieben (andere Zeit): nichts doppelt.
	await get_tree().create_timer(1.1).timeout
	_write(userf, kv_file(user(0b011, { "0": started - 86400, "1": started + 5 })))
	Unlocks._poll_file()
	check(Unlocks.history().size() == before + 1, "unverändert neu geschrieben: nichts doppelt")
	# Web-API meldet denselben (andere Schreibweise): nichts doppelt; einen weiteren: neu.
	Unlocks._take("web", { "ach_boss": started + 5, "ACH_START": 1 }, false)
	check(Unlocks.history().size() == before + 1, "Web-API meldet denselben (andere Groß/klein): nichts doppelt")
	Unlocks._take("web", { "ACH_SECRET": started + 9 }, false)
	await get_tree().create_timer(0.05).timeout
	check(Unlocks.history().size() == before + 2 and str(Unlocks.history()[0].name) == "Hidden One", "Web-API: weiterer Erfolg neu")
	# Neue Sitzung: was während des Starts (nach since) freigeschaltet wurde, kommt auch beim ersten Blick.
	await get_tree().create_timer(1.1).timeout
	_write(userf, kv_file(user(0b011, { "0": started - 86400, "1": started + 5 })))
	var started2 := started + 3
	var h0 := Unlocks.history().size()
	Unlocks.begin_steam_session(APPID, "Testspiel", dir, started2)
	check(Unlocks.session().known.has("ACH_BOSS") and Unlocks.history().size() == h0,
			"neue Sitzung liest die Datei gleich; schon gemeldeter Erfolg nicht noch einmal (Verlauf)")
	# Steam schreibt gleich noch einmal (meist in derselben Sekunde, also gleiche Änderungszeit).
	_write(userf, kv_file(user(0b111, { "0": started - 86400, "1": started + 5, "2": started + 9 })))
	Unlocks._poll_file()
	check(Unlocks.session().known.has("ACH_SECRET"), "zweimal kurz hintereinander geschrieben: die zweite Fassung wird gelesen")
	Unlocks._stop()


func _write(path: String, b: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func _web_and_ra() -> void:
	print("Web-API und RetroAchievements")
	var p: Variant = U.parse_player({ "playerstats": { "success": true, "achievements": [
		{ "apiname": "A", "achieved": 1, "unlocktime": 100 }, { "apiname": "B", "achieved": 0, "unlocktime": 0 }] } })
	check(p == { "A": 100 }, "GetPlayerAchievements: nur freigeschaltete")
	check(U.parse_player({ "playerstats": { "success": false, "error": "Profile is not public" } }) == null, "privat → null (kein Stand)")
	var ra := U.parse_ra_recent([
		{ "AchievementID": 11, "Title": "Ring-Sammler", "Description": "100 Ringe", "BadgeName": "123", "Points": 10, "HardcoreMode": 1, "GameTitle": "Sonic",
			"GameID": 1, "Date": "2026-10-17 10:00:00" },
		{ "AchievementID": 11, "Title": "Ring-Sammler", "Points": 10, "HardcoreMode": 0, "GameID": 1, "Date": "2026-10-17 09:00:00" },
		"kaputt"])
	check(ra.size() == 2 and ra[0].key == "11:hc" and ra[1].key == "11:sc", "Hardcore und Softcore getrennt (Hardcore später ist neu)")
	check(str(ra[0].icon) == "https://media.retroachievements.org/Badge/123.png" and ra[0].hardcore and int(ra[0].at) > 0, "Abzeichen, Hardcore, Zeit")
	var known := {}
	var now := {}
	for a in ra:
		now[a.key] = int(a.at)
	check(U.diff_new(known, now, true, int(ra[0].at) + 600).is_empty(), "RA erster Blick: Stand")
	known["11:sc"] = true
	check(U.diff_new(known, now, false, 0) == ["11:hc"], "RA danach: nur das Neue")
	check(U.game_key({ "source": "ra", "ra_id": 7 }) == "ra:7" and U.game_key({ "source": "steam", "appid": 5 }) == "steam:5", "Spielschlüssel")


func _queue() -> void:
	print("Warteschlange")
	var pops = Unlocks.popups
	pops.clear()
	var base: int = pops.shown
	for i in 4:
		var e := { "name": "Erfolg %d" % i, "points": 20, "rarity": 30.0, "platform": "steam", "icon": "" }
		pops.show_entry(e, U.decorate(e))
	check(pops.shown == base + 1 and pops.waiting() == 3, "eins läuft, drei warten")
	var cur: Control = pops.current
	check(is_equal_approx(float(cur.get("hold")), U.hold_for(3)), "läuft kürzer, solange andere warten")
	var t0 := Time.get_ticks_msec()
	while pops.busy() or pops.waiting() > 0:
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 20000:
			break
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	check(pops.shown == base + 4 and pops.waiting() == 0, "alle nacheinander gezeigt")
	check(secs < 4 * (Toast.IN_END + U.hold_for(0) + Toast.OUT_LEN), "zusammen schneller als einzeln (%.1f s)" % secs)
	for k in ["normal", "rare", "ultra", "retro"]:
		pops.clear()
		Unlocks.test_popup(k)
		var d: Dictionary = pops.current.get("deco") if is_instance_valid(pops.current) else {}
		check(str(d.get("variant", "")) == k, "Test-Pop-up „%s“ zeigt diese Art" % k)
	pops.clear()


func _timeline() -> void:
	print("Zeitplan der Animation")
	var hold := 3.4
	var f0 := Toast.frame(0.0, hold)
	check(f0.s == 0.0 and f0.wk == 0.0, "Beginn: Kreis noch nicht da")
	var peak := 0.0
	var t := 0.0
	while t < 0.5:
		peak = maxf(peak, Toast.frame(t, hold).s)
		t += 0.005
	check(peak > 1.13 and peak <= 1.15, "springt über (bis 1,15)")
	check(is_equal_approx(Toast.frame(0.5, hold).s, 1.0), "steht danach bei 1")
	check(Toast.frame(0.28, hold).wk == 0.0 and Toast.frame(0.95, hold).wk == 1.0, "öffnet sich nach dem Aufspringen zur Pille")
	check(Toast.frame(0.5, hold).l1a == 0.0 and Toast.frame(1.2, hold).l1a == 1.0 and Toast.frame(1.2, hold).l2a == 1.0, "Schrift erst in der offenen Pille")
	check(Toast.frame(1.0, hold).l1x == 0.0 or absf(Toast.frame(1.0, hold).l1x) < 0.1, "Schrift gleitet an ihren Platz")
	check(Toast.frame(1.31, hold).pk == 1.0 and Toast.frame(0.75, hold).pk < 0.5, "Punkte zählen hoch")
	check(Toast.frame(0.3, hold).ring > 0.0 and Toast.frame(0.9, hold).ring < 0.0, "Lichtring läuft einmal aus")
	var he := Toast.IN_END + hold
	check(Toast.frame(he + 0.25, hold).l1a == 0.0 and Toast.frame(he + 0.25, hold).wk > 0.5, "erst geht die Schrift, dann schließt sich die Pille")
	check(Toast.frame(he + 0.55, hold).wk == 0.0, "wieder ein Kreis")
	check(Toast.frame(he + Toast.OUT_LEN, hold).done and Toast.frame(he + Toast.OUT_LEN, hold).s <= 0.0001, "am Ende weg")
	check(Toast.frame(2.5, hold, 2).sweep >= 0.0 and Toast.frame(2.5, 1.0, 2).sweep < 0.0 and Toast.frame(2.5, hold, 1).sweep < 0.0,
			"zweiter Schimmer nur für seltene und nur mit Zeit")
	var total := Toast.IN_END + hold + Toast.OUT_LEN
	check(total > 4.5 and total < 5.6, "ganz etwa 5 Sekunden (%.1f s)" % total)
	var font := UzTheme.ui("ui_bold")
	var long := "Der allerletzte Wächter des vergessenen Nordens und seiner sieben verlorenen Schätze"
	var cut := Toast.fit(font, long, 27, 400.0)
	check(cut.ends_with("…") and font.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x <= 400.0, "lange Namen: gekürzt mit …")
	var e := { "name": long, "points": 20, "rarity": 30.0, "platform": "steam", "icon": "" }
	var toast: Control = Toast.new().setup(e, U.decorate(e), 3.4)
	check(float(toast.call("full_width")) <= Toast.MAX_W and str(toast.call("line2")).ends_with("…"), "Pille wird nicht breiter als erlaubt")
	toast.free()


func _store() -> void:
	print("Speichern und Schnittstelle")
	var n0: int = Unlocks.total_points()
	var got := []
	var cb := func(x: Dictionary) -> void: got.append(x)
	Unlocks.unlocked.connect(cb)
	Unlocks.record({ "game": "Sonic", "game_key": "ra:1", "api": "77", "name": "Ring-Sammler", "points": 30, "rarity": -1.0, "platform": "ra",
		"unlocked_at": 1760000000, "hardcore": true, "ra_points": 10, "icon": "" })
	Unlocks.record({ "game": "Sonic", "game_key": "ra:1", "api": "77", "name": "Ring-Sammler", "points": 30, "rarity": -1.0, "platform": "ra",
		"unlocked_at": 1760000001, "hardcore": true, "ra_points": 10, "icon": "" })
	Unlocks.unlocked.disconnect(cb)
	check(got.size() == 1 and str(got[0].platform) == "ra", "Signal unlocked einmal (doppelt verworfen)")
	check(Unlocks.total_points() == n0 + 30 and Unlocks.points_for_game("ra:1") >= 30, "Punkte je Spiel und insgesamt")
	var h0: Dictionary = Unlocks.history(1)[0]
	check(h0.has_all(["game", "name", "points", "rarity", "platform", "unlocked_at"]), "Verlauf mit allen Feldern")
	Config.write_json(Config.path(U.FILE), Unlocks._data)
	var d: Variant = Config.read_json(Config.path(U.FILE), null)
	check(d is Dictionary and (d.history as Array).size() == Unlocks.history().size() and d.games.has("ra:1"), "gespeichert im Datenordner (unlocks.json)")
	var PU = load("res://src/ui/sections/profile_unlocks.gd")
	check(
			PU.summary(1240, { "a": { "title": "Hades", "points": 340 }, "b": { "title": "Celeste", "points": 90 } }) == "1.240 Uzai-Punkte · am meisten in Hades (340)",
			"Profil: Summe und Spiel mit den meisten Punkten")
	var ce: Dictionary = PU.card_entry({ "name": "X", "game": "Sonic", "game_key": "ra:7", "platform": "ra", "ra_points": 10, "unlocked_at": 5 })
	check(ce.source == "ra" and int(ce.game_id) == 7 and int(ce.points) == 10 and int(ce.date) == 5, "Profil: Eintrag führt zum Spiel (RA)")
	# Eine Speicherdatei mit Einträgen anderer Form: nur die passenden bleiben, nichts bricht ab.
	var heil: Dictionary = Unlocks._data.duplicate(true)
	Config.write_json(Config.path(U.FILE), { "v": 1, "games": { "ra:1": { "points": 30 }, "kaputt": 7, "auch": "text" },
		"history": [5, "x", { "game_key": "ra:1", "api": "77", "hardcore": true }, [1]] })
	Unlocks._load()
	check(Unlocks.total_points() == 30 and Unlocks.history().size() == 1 and Unlocks.games().size() == 1,
			"Speicherdatei mit Einträgen anderer Form: nur die passenden bleiben")
	Unlocks.record({ "game": "Sonic", "game_key": "ra:1", "api": "78", "name": "Zweiter", "points": 5, "platform": "ra", "unlocked_at": 3 })
	check(Unlocks.total_points() == 35 and Unlocks.history().size() == 2, "danach lässt sich weiter eintragen")
	Unlocks._data = heil
	Config.write_json(Config.path(U.FILE), heil)
	# Spielende räumt die Sitzung ab.
	Unlocks.begin_steam_session(APPID, "Testspiel", Config.path("gibt_es_nicht"))
	await Unlocks._on_ended({}, 0)
	check(Unlocks._s.is_empty(), "Spielende: Sitzung beendet")
	# Mitteilungsliste: neuester Eintrag vorn, übliche Felder ergänzt, begrenzt, ohne den Zähler zu erhöhen.
	var alt_liste: Array = Toasts.history
	var vor: int = Toasts.unread
	Toasts.history = []
	for i in Toasts.MERK_MAX + 5:
		Toasts.merken({ "title": "T%d" % i })
	check(Toasts.history.size() == Toasts.MERK_MAX and str(Toasts.history[0].title) == "T%d" % (Toasts.MERK_MAX + 4)
			and (Toasts.history[0] as Dictionary).has_all(["sub", "icon", "at", "image", "go", "go_text"]) and Toasts.unread == vor,
			"Mitteilungsliste: neuester vorn, übliche Felder, begrenzt, ohne Zähler")
	Toasts.history = alt_liste
