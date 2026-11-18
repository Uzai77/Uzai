extends Node
## Profil-Level und Abzeichen ohne Oberfläche: Level-Kurve, Punkte (wie die Erfolgs-Pop-ups),
## Katalog, Stufen und Fortschritt, Zahlen aus Bibliothek und Sitzungen, bekannte Erfolgslisten,
## was beim ersten Lauf und danach gemeldet wird (rückwirkend kein Pop-up), Medaillen-SVG, Fanfare.
## Aufruf: godot --headless --path . res://tests/logic_abzeichen.tscn

const L := preload("res://src/core/badges_logic.gd")
const BadgesS := preload("res://src/core/badges.gd")
const Medal := preload("res://src/ui/components/badge_medal.gd")
const BadgePopupS := preload("res://src/ui/badge_popup.gd")
const UnlocksS := preload("res://src/core/unlocks.gd")
const Logos := preload("res://src/core/badge_logos.gd")

var fails := 0


## Badges mit vorgegebenen Zahlen statt Bibliothek und Netz.
class FakeBadges extends "res://src/core/badges.gd":
	var fake := {}

	func collect() -> Dictionary:
		return fake.duplicate(true)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_level()
	_points()
	_catalog()
	_tiers()
	_facts()
	_known()
	_diff()
	_art()
	await _logos()
	await _flow()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _level() -> void:
	print("Level-Kurve")
	check(L.level_of(0).level == 1 and L.level_of(-50).level == 1, "Level 1 bei 0 Punkten")
	check(L.level_step(1) == 200 and L.level_step(2) == 220, "erster Schritt 200, dann 220 (%d, %d)" % [L.level_step(1), L.level_step(2)])
	var grow_ok := true
	for lv in range(2, 30):
		var r := float(L.level_step(lv)) / float(L.level_step(lv - 1))
		if r < 1.05 or r > 1.16:
			grow_ok = false
	check(grow_ok, "jeder Schritt rund 10 % größer (Level 2–30)")
	check(L.level_step(80) == L.LEVEL_CAP and L.level_step(400) == L.LEVEL_CAP, "ab etwa Level 36 gleichbleibend %d" % L.LEVEL_CAP)
	var cons := true
	for lv in range(1, 60):
		if L.level_start(lv + 1) - L.level_start(lv) != L.level_step(lv):
			cons = false
	check(cons, "Beginn je Level passt zu den Schritten")
	var s13 := L.level_start(13)
	check(L.level_of(s13).level == 13 and int(L.level_of(s13).into) == 0, "genau am Beginn: Level 13")
	check(L.level_of(s13 - 1).level == 12 and int(L.level_of(s13 - 1).left) == 1, "einen Punkt davor: Level 12, noch 1")
	check(L.level_left_text(s13 - 120) == "Noch 120 Punkte bis Level 13", "Text „%s“" % L.level_left_text(s13 - 120))
	check(L.level_left_text(s13 - 1) == "Noch 1 Punkt bis Level 13", "Einzahl „%s“" % L.level_left_text(s13 - 1))
	var mono := true
	var last := 1
	for p in range(0, 400000, 997):
		var lv2 := int(L.level_of(p).level)
		if lv2 < last:
			mono = false
		last = lv2
	check(mono, "Level steigt nie mit mehr Punkten ab")
	check(L.level_of(1000000).level > 100, "ohne Ende: 1 Mio. Punkte über Level 100 (%d)" % L.level_of(1000000).level)
	var f := float(L.level_of(s13 + 50).frac)
	check(f > 0.0 and f < 1.0, "Anteil im Level zwischen 0 und 1")


func _points() -> void:
	print("Punkte")
	var same := true
	for p in [-1.0, 0.0, 0.4, 1.0, 4.9, 5.0, 9.9, 10.0, 19.9, 20.0, 49.9, 50.0, 100.0]:
		if L.points_for_rarity(p) != UnlocksS.points_for(p):
			same = false
	check(same, "Seltenheit → Punkte genau wie die Erfolgs-Pop-ups (Unlocks.points_for)")
	var ra_same := true
	for rp in [0, 1, 3, 5, 10, 25, 50, 100]:
		if L.points_for_ra(rp) != UnlocksS.points_for_ra(rp) or L.points_for_ra(rp, 3.0) != UnlocksS.points_for_ra(rp, 3.0):
			ra_same = false
	check(ra_same, "RetroAchievements → Punkte wie Unlocks.points_for_ra")
	check(L.points_for_rarity(0.5) == 100 and L.points_for_rarity(80.0) == 10, "10 bis 100 Punkte")
	var pts := L.points_total({ "ach_points": 1000, "hours_total": 10.7 }, { "zeit_ps2": 2, "level": 4 })
	check(int(pts.ach) == 1000 and int(pts.play) == 20 and int(pts.badges) == 75, "Erfolge + 2 je Stunde + Stufen (Bronze 25 + Silber 50)")
	check(int(pts.total) == 1095, "Veteran-Abzeichen bringt keine Punkte (sonst Kreis Level ↔ Abzeichen)")


func _catalog() -> void:
	print("Katalog")
	check(L.DEFS.size() >= 25 and L.DEFS.size() <= 40, "%d Abzeichen (25–40)" % L.DEFS.size())
	var ids := {}
	var ok := true
	var cats := {}
	for c in L.CATS:
		cats[str(c[0])] = 0
	for d in L.DEFS:
		if ids.has(d.id) or not cats.has(str(d.cat)):
			ok = false
		ids[d.id] = true
		cats[str(d.cat)] = int(cats[str(d.cat)]) + 1
		var ts: Array = d.tiers
		if ts.size() != 4 or not (int(ts[0]) < int(ts[1]) and int(ts[1]) < int(ts[2]) and int(ts[2]) < int(ts[3])):
			ok = false
		var g := str(d.glyph)
		if str(d.get("mark", "")) == "" and not Medal.GLYPHS.has(g) and not Icons.P.has(g):
			ok = false
		if (d.unit as Array).size() != 2 or str(d.desc) == "":
			ok = false
	check(ok, "eindeutig, bekannte Kategorie, vier steigende Stufen, Zeichen und Texte vorhanden")
	var all_used := true
	for k in cats.keys():
		if int(cats[k]) == 0:
			all_used = false
	check(all_used, "jede Kategorie hat Abzeichen")
	for need in ["zeit_ps2", "zeit_steam", "zeit_pc", "ach_total", "ach_rare", "ach_ultra", "perfect", "platforms", "together", "captures", "streak",
			"ra_unlocked", "ra_hardcore"]:
		if L.def_of(need).is_empty():
			check(false, "Abzeichen %s fehlt" % need)
	check(L.def_of("zeit_ps2").tiers == [10, 50, 100, 500], "Spielzeit je Plattform 10/50/100/500 Std.")
	check(L.def_of("ach_total").tiers == [1, 10, 100, 1000], "Erfolge: erster, 10, 100, 1000")


func _tiers() -> void:
	print("Stufen und Fortschritt")
	var d := L.def_of("zeit_ps2")
	check(L.tier_for(d, 9.99) == 0 and L.tier_for(d, 10.0) == 1 and L.tier_for(d, 37.0) == 1, "unter 10 Std. keine, ab 10 Bronze")
	check(L.tier_for(d, 50.0) == 2 and L.tier_for(d, 100.0) == 3 and L.tier_for(d, 9999.0) == 4, "Silber, Gold, Platin")
	var p := L.progress(d, 37.4, 1)
	check(str(p.text) == "37/50 Stunden" and absf(float(p.frac) - 27.4 / 40.0) < 0.001, "„%s“, Anteil ab Bronze" % p.text)
	var p0 := L.progress(d, 3.0, 0)
	check(str(p0.text) == "3/10 Stunden" and absf(float(p0.frac) - 0.3) < 0.001, "gesperrt: „%s“" % p0.text)
	var p4 := L.progress(d, 812.0, 4)
	check(bool(p4.done) and str(p4.text) == "812 Stunden", "Platin: „%s“" % p4.text)
	check(L.tier_title(d, 3) == "100 Stunden PS2", "Titel „%s“" % L.tier_title(d, 3))
	check(L.tier_title(L.def_of("ach_total"), 1) == "Erster Erfolg" and L.tier_title(L.def_of("ach_total"), 4) == "1.000 Erfolge",
			"„Erster Erfolg“, „1.000 Erfolge“")
	check(L.tier_title(L.def_of("ach_rare"), 2) == "10 seltene Erfolge", "„10 seltene Erfolge“")
	check(L.tier_title(L.def_of("ach_ultra"), 2) == "5 Erfolge unter 1 %", "Prozentzeichen im Titel (%s)" % L.tier_title(L.def_of("ach_ultra"), 2))
	check(L.progress(L.def_of("ach_total"), 0.0, 0).text == "0/1 Erfolg", "Einzahl beim ersten Erfolg")
	var ev := L.evaluate({ "hours_ps2": 12.0 }, { "zeit_ps2": 3 })
	check(int(ev.zeit_ps2) == 3, "Verdientes geht nie verloren (Gold bleibt bei 12 Std.)")
	var r := L.compute({ "ach_points": L.level_start(6) }, {})
	check(int(r.level.level) >= 6 and int(r.tiers.level) == 1, "Level 6 → Uzai-Veteran Bronze")
	var ctx := { "ra": false, "platforms": { "ps2": true } }
	check(L.visible(L.def_of("zeit_ps2"), ctx, 0) and not L.visible(L.def_of("zeit_n64"), ctx, 0), "Plattformen nur mit Spielen dafür")
	check(not L.visible(L.def_of("ra_hardcore"), ctx, 0) and L.visible(L.def_of("ra_hardcore"), ctx, 1), "Retro nur mit RA – verdiente immer")


func _facts() -> void:
	print("Zahlen aus Bibliothek und Sitzungen")
	var games := [
		{ "system": "ps2", "source": "rom", "secs": 37 * 3600 }, { "system": "ps2", "source": "rom", "secs": 3 * 3600 },
		{ "system": "gc", "source": "rom", "secs": 1200 }, { "system": "steam", "source": "steam", "secs": 5 * 3600 },
		{ "system": "epic", "source": "epic", "secs": 2 * 3600 }, { "system": "ea", "source": "ea", "secs": 0 },
		{ "system": "snes", "source": "rom", "secs": 4000 },
	]
	var f := L.playtime_facts(games, 600, 9)
	check(absf(float(f.hours_ps2) - 40.0) < 0.01, "PS2: 40 Std. (%.1f)" % float(f.hours_ps2))
	check(absf(float(f.hours_steam) - 10.0) < 0.01, "Steam: ganze Bibliothek zählt, wenn größer (10 Std.)")
	check(absf(float(f.hours_pc) - 2.0) < 0.01 and absf(float(f.hours_16bit) - 4000.0 / 3600.0) < 0.01, "Epic/EA als PC, SNES als 8/16 Bit")
	check(int(f.platforms) == 4, "Plattformen ab 1 Std.: PS2, Steam, PC, 8/16 Bit (%d)" % int(f.platforms))
	check(int(f.games_played) == 5 + 9, "gespielte Spiele ab 10 Min.: 5 ohne Steam + 9 laut Steam (%d)" % int(f.games_played))
	check(int(f.retro_systems) == 2 and (f.present as Dictionary).has("gc") and not (f.present as Dictionary).has("n64"),
			"Konsolen im Emulator, vorhandene Plattformen")
	var f2 := L.playtime_facts(
			[{ "system": "snes", "secs": 3600 }, { "system": "megadrive", "secs": 5 * 3600 }, { "system": "psp", "secs": 60 }, { "system": "ps2", "secs": 60 }])
	check(str(f2.get("top_16bit", "")) == "megadrive" and str(f2.get("top_handheld", "")) == "psp" and not f2.has("top_ps2") and not f2.has("top_pc"),
			"meistgespieltes System je Gruppe (für das Logo)")
	var day := 86400
	var base := 20000 * day
	var ses := [
		{ "id": "a", "at": base + 20 * 3600, "secs": 3600 }, { "id": "a", "at": base + day + 20 * 3600, "secs": 3 * 3600 },
		{ "id": "b", "at": base + 2 * day + 2 * 3600, "secs": 1800 }, { "id": "b", "at": base + 6 * day + 12 * 3600, "secs": 5 * 3600 + 60 },
		{ "id": "c", "at": base + 6 * day + 3 * 3600, "secs": 300 }, { "id": "x", "at": 0, "secs": 100 },
	]
	var sf := L.session_facts(ses, 0)
	check(int(sf.streak_best) == 3 and int(sf.days_played) == 4, "Serie 3 Tage, 4 Spieltage (%d, %d)" % [int(sf.streak_best), int(sf.days_played)])
	check(int(sf.night_sessions) == 1, "Nachteule: nur Sitzungen ab 15 Min. vor 5 Uhr (%d)" % int(sf.night_sessions))
	check(absf(float(sf.longest_session) - (5.0 + 1.0 / 60.0)) < 0.01, "längste Sitzung")
	var sf2 := L.session_facts([{ "id": "a", "at": base + 23 * 3600 + 1800, "secs": 1800 }], 2 * 3600)
	check(int(sf2.night_sessions) == 1, "Zeitzone zählt (23:30 UTC = 01:30 Ortszeit)")
	var kb := L.keep_best({ "hours_ps2": 50.0, "ach_total": 7, "x": "text" }, { "hours_ps2": 40.0, "ach_total": 9 })
	check(float(kb.hours_ps2) == 50.0 and int(kb.ach_total) == 9 and not kb.has("x"), "Höchststände gehen nie zurück")


func _known() -> void:
	print("Erfolgspunkte rückwirkend")
	var res := { "source": "steam", "appid": 620, "list": [
		{ "unlocked": true, "rarity": 60.0 }, { "unlocked": true, "rarity": 8.0 }, { "unlocked": true, "rarity": 0.5 },
		{ "unlocked": false, "rarity": 0.1 }, { "unlocked": true, "rarity": -1.0 },
	] }
	var s := L.game_summary(res)
	check(int(s.n) == 4 and int(s.p) == 10 + 50 + 100 + 20, "Liste: 4 frei, 180 Punkte (%d)" % int(s.p))
	check(int(s.r10) == 2 and int(s.r1) == 1, "selten unter 10 %: 2, unter 1 %: 1")
	var sc := UnlocksS.score_list(res)
	check(int(sc.points) == int(s.p), "gleiche Punkte wie Unlocks.score_list")
	var ra := L.game_summary({ "source": "ra", "list": [{ "unlocked": true, "rarity": -1.0, "points": 25 }, { "unlocked": true, "rarity": 40.0, "points": 5 }] })
	check(int(ra.p) == 50 + 20, "RetroAchievements: RA-Punkte ohne Seltenheit (%d)" % int(ra.p))
	var ap := L.ach_points({ "steam:620": s }, 104)
	check(int(ap.points) == 180 + 100 * L.DEFAULT_POINTS and int(ap.known) == 4,
			"Rest ohne Liste mit %d Punkten je Erfolg – Level am ersten Tag nicht null" % L.DEFAULT_POINTS)
	var m := BadgesS.merge_unlocks({ "steam:620": s },
			{ "steam:620": { "points": 90, "count": 2 }, "steam:400": { "points": 300, "count": 6 }, "test": { "points": 999, "count": 9 } },
		[{ "game_key": "steam:400", "rarity": 0.7 }, { "game_key": "steam:400", "rarity": 30.0 }, { "game_key": "steam:620", "rarity": 0.5 },
			{ "game_key": "x", "rarity": 1.0, "test": true }])
	check(int(m["steam:620"].n) == 4 and int(m["steam:620"].p) == 180, "vollständigere Liste gewinnt")
	check(int(m["steam:400"].n) == 6 and int(m["steam:400"].p) == 300 and int(m["steam:400"].r1) == 1, "Uzais Freischaltungen mit Punkten und Seltenheit")
	check(int(m["steam:620"].r1) == 1 and not m.has("test") and not m.has("x"), "seltene nicht doppelt, Proben nicht gezählt")


func _diff() -> void:
	print("Was gemeldet wird")
	var old := {}
	var now := { "zeit_ps2": 3, "ach_total": 2, "perfect": 0 }
	var first := L.diff(old, now, 0, 9, true)
	check((first.popups as Array).is_empty() and not first.level_up and int(first.summary) == 2, "erster Lauf: kein Pop-up, nur „2 Abzeichen“")
	var later := L.diff({ "zeit_ps2": 2, "ach_total": 2 }, { "zeit_ps2": 3, "ach_total": 2, "perfect": 1 }, 9, 10, false)
	check((later.popups as Array).size() == 2 and str(later.popups[0].id) == "zeit_ps2" and int(later.popups[0].tier) == 3, "danach: neue Stufen, höchste zuerst")
	check(bool(later.level_up) and int(later.summary) == 0, "Level-Aufstieg gemeldet")
	var same := L.diff(now, now, 9, 9, false)
	check((same.popups as Array).is_empty() and not same.level_up, "nichts Neues: nichts")
	check(not L.diff({}, {}, 0, 3, false).level_up, "ohne alten Stand kein Level-Pop-up")


func _art() -> void:
	print("Medaillen und Pop-up")
	var ok := true
	for shape in ["circle", "hex", "oct", "seal", "diamond", "cart", "shield"]:
		for t in 5:
			var img := Image.new()
			if img.load_svg_from_string(Medal.svg(shape, "trophy", t), 1.0) != OK or img.get_width() != 100:
				ok = false
	check(ok, "SVG jeder Form und Stufe lesbar")
	var all_glyphs := true
	for g in Medal.GLYPHS.keys():
		var img2 := Image.new()
		if img2.load_svg_from_string(Medal.svg("circle", str(g), 3), 1.0) != OK:
			all_glyphs = false
	check(all_glyphs, "eigene Zeichen lesbar")
	var tex := Medal.texture_for(L.def_of("zeit_ps2"), 3, 120)
	check(tex.get_width() == 240, "doppelt gerastert (scharf auf 4K): %d px für 120" % tex.get_width())
	check(Medal.texture_for(L.def_of("zeit_ps2"), 3, 120) == tex, "zwischengespeichert")
	var img3 := Medal.texture_for(L.def_of("perfect"), 0, 60).get_image()
	var c := img3.get_pixel(60, 60)
	check(c.a > 0.9 and c.r < 0.4, "gesperrt: dunkles Graphit in der Mitte")
	var e := BadgePopupS.entry_of({ "kind": "badge", "id": "zeit_ps2", "tier": 3 })
	var d := BadgePopupS.deco_of({ "kind": "badge", "id": "zeit_ps2", "tier": 3 })
	check(str(e.name) == "100 Stunden PS2" and int(e.points) == 100 and str(d.chip) == "Gold", "Pop-up: Titel, +100 Punkte, Chip Gold")
	check(str(BadgePopupS.deco_of({ "kind": "badge", "id": "zeit_ps2", "tier": 4 }).variant) == "ultra", "Platin wie ultraselten")
	check(int(BadgePopupS.entry_of({ "kind": "badge", "id": "level", "tier": 2 }).points) == 0, "Veteran ohne Punkte")
	check(BadgePopupS.summary_text({ "count": 14, "first": true }) == "Du hast 14 Abzeichen freigeschaltet", "Zusammenfassung beim ersten Lauf")
	check(BadgePopupS.summary_text({ "count": 3 }) == "3 neue Abzeichen" and BadgePopupS.summary_text({ "count": 1 }) == "1 neues Abzeichen",
			"Zusammenfassung danach")
	var fan := BadgePopupS.make_fanfare()
	var loud := 0
	for i in range(0, fan.data.size() - 1, 400):
		loud = maxi(loud, absi(fan.data.decode_s16(i)))
	check(fan.get_length() > 1.4 and fan.get_length() < 2.0 and loud > 3000 and loud < 32767, "Fanfare: %.2f s, hörbar, nicht übersteuert" % fan.get_length())


## Echte Konsolen-Logos: Zuordnung, Cache-Pfad, Antwort der Commons-API, Rückfall auf den
## Kurznamen, eigene Datei gewinnt, Prägung in Metall, nie hochgezogen. Ohne Netz.
func _logos() -> void:
	print("Konsolen-Logos")
	Logos.net = false
	var tmp := OS.get_cache_dir().path_join("uzai_logos_%d" % Time.get_ticks_usec()) if OS.get_environment("UZAI_DATA") == "" else OS.get_environment(
			"UZAI_DATA").path_join("logo_test")
	DirAccess.make_dir_recursive_absolute(tmp.path_join("media/logos"))
	Logos.data_dir_override = tmp.path_join("data")
	Logos.media_dir_override = tmp.path_join("media")
	Logos.forget()
	# Rechtliches (R4): Uzai bringt keine Hersteller-Logos mit; geladen wird zur Laufzeit (Standard
	# an, einmal umgestellt über badges.rev), abschaltbar.
	var logos_was := bool(Config.get_value("badges.real_logos", true))
	check(Config.DEFAULTS.badges.real_logos == true and int(Config.DEFAULTS.badges.rev) == 2, "Konsolen-Logos laden: Standard an")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/logos")), "keine Logos im Projekt")
	Config.set_value("badges.real_logos", false)
	check(not Logos.enabled(), "ausgeschaltet: kein Laden")
	Config.set_value("badges.real_logos", true)
	# Zuordnung vollständig: jedes Plattform-Abzeichen hat ein Logo, jedes System der Gruppen auch.
	var ok := true
	var n := 0
	for d in L.DEFS:
		if str(d.get("need", "")).begins_with("plat:"):
			n += 1
			var ks := Logos.keys_for(d)
			if ks.is_empty() or not Logos.LOGOS.has(str(ks[0])):
				ok = false
				print("    ohne Logo: ", d.id)
	check(ok and n == L.PLATFORMS.size(), "jedes der %d Plattform-Abzeichen hat ein Logo" % n)
	var sys_ok := true
	for g in L.PLATFORMS.keys():
		if not Logos.GROUP_LOGO.has(g):
			sys_ok = false
		for sy in L.PLATFORMS[g]:
			if not Logos.SYSTEM_LOGO.has(sy) or not Logos.LOGOS.has(str(Logos.SYSTEM_LOGO[sy])):
				sys_ok = false
				print("    System ohne Logo: ", sy)
	check(sys_ok, "jedes System der Gruppen (auch PSP, Mega Drive, DS) hat ein Logo")
	var files_ok := true
	for k in Logos.LOGOS.keys():
		var fs: Array = Logos.LOGOS[k].files
		if fs.is_empty():
			files_ok = false
		for fn in fs:
			if not (str(fn).ends_with(".svg") or str(fn).ends_with(".png")) or str(fn).contains("/") or str(fn).contains("|"):
				files_ok = false
	check(files_ok, "Commons-Dateinamen gültig (SVG/PNG, ohne / und |)")
	check(Logos.keys_for(L.def_of("zeit_16bit"), "megadrive") == ["megadrive", "snes"], "8/16 Bit: meistgespieltes System zuerst, SNES als Rückfall")
	check(Logos.keys_for(L.def_of("zeit_16bit"), "ps2") == ["snes"] and Logos.keys_for(L.def_of("zeit_handheld"), "psp") == ["psp", "gba"],
			"fremdes System zählt nicht; Handhelds: PSP vor Game Boy Advance")
	check(Logos.keys_for(L.def_of("zeit_pc"), "epic") == ["windows"] and Logos.keys_for(L.def_of("zeit_ps2")) == ["ps2"], "Epic → Windows-Logo, PS2 → PS2")
	check(Logos.keys_for(L.def_of("zeit_total")).is_empty() and Logos.keys_for(L.def_of("perfect")).is_empty(), "Abzeichen ohne Plattform: kein Logo")
	check(Logos.override_names(L.def_of("zeit_16bit"), "megadrive") == ["16bit", "megadrive", "snes"], "eigene Dateien: Gruppe, dann Logo-Namen")
	# Cache im Datenordner.
	var cp := Logos.cache_path("ps2")
	check(cp == tmp.path_join("data/cache/logos/ps2.png"), "Cache: <Daten>/cache/logos/ps2.png (%s)" % cp.get_file())
	var url := Logos.api_url(Logos.COMMONS_API, ["PlayStation 2 logo.svg", "PS2 logo.svg"])
	check(url.begins_with("https://commons.wikimedia.org/w/api.php?") and url.contains("iiurlwidth=960")
			and url.contains("File%3APlayStation%202%20logo.svg%7CFile%3APS2%20logo.svg"), "API-Abfrage: alle Namen auf einmal, Breite 960")
	check(Logos.filepath_url("Wii.svg") == "https://commons.wikimedia.org/wiki/Special:FilePath/Wii.svg?width=960", "Rückfall Special:FilePath mit Breite")
	# Antwort der API: erster vorhandener Name in Wunschreihenfolge, Titel normalisiert.
	var resp := { "query": { "normalized": [], "pages": [
		{ "title": "File:PlayStation 2 logo.svg", "missing": true },
		{ "title": "File:PS2 logo.svg",
			"imageinfo": [{ "thumburl": "https://upload.wikimedia.org/x/960px-PS2_logo.svg.png", "thumbwidth": 960, "thumbheight": 220, "mime": "image/svg+xml",
			"url": "https://upload.wikimedia.org/x/PS2_logo.svg" }] },
		{ "title": "File:Playstation 2 logo.svg", "imageinfo": [{ "thumburl": "https://upload.wikimedia.org/other.png", "mime": "image/svg+xml" }] } ] } }
	var pk := Logos.pick(resp, ["PlayStation 2 logo.svg", "PS2_logo.svg", "Playstation 2 logo.svg"])
	check(str(pk.get("url", "")).ends_with("960px-PS2_logo.svg.png") and int(pk.width) == 960,
			"fehlende Datei übersprungen, nächste in Reihenfolge (Unterstrich egal)")
	var small := {
			"query": { "pages": { "1": { "title": "File:Tiny.png",
			"imageinfo": [{ "url": "https://upload.wikimedia.org/Tiny.png", "width": 120, "height": 80, "mime": "image/png" }] } } } }
	check(str(Logos.pick(small, ["tiny.png"]).get("url", "")) == "https://upload.wikimedia.org/Tiny.png", "kleines Rasterbild: Original, nie hochgezogen")
	check(Logos.pick({ "query": { "pages": [{ "title": "File:A.svg", "missing": true }] } }, ["A.svg"]).is_empty() and Logos.pick(null, ["A.svg"]).is_empty()
			and Logos.pick({ "error": {} }, ["A.svg"]).is_empty(), "nichts gefunden / kaputte Antwort: leer")
	var now := 2000000000
	check(Logos.should_try(null, now) and not Logos.should_try({ "miss": true, "at": now - 86400 }, now)
			and Logos.should_try({ "miss": true, "at": now - 15 * 86400 }, now), "nicht gefunden: erst nach 14 Tagen wieder suchen")
	# Bilder: nie hochziehen, Seitenverhältnis bleibt.
	check(Logos.fit(Vector2i(50, 20), Vector2(200, 200)) == Vector2i(50, 20) and Logos.fit(Vector2i(960, 240), Vector2(124, 60)) == Vector2i(124, 31),
			"Seitenverhältnis bleibt, nie hochgezogen")
	var white := Image.create(80, 40, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	white.fill_rect(Rect2i(20, 10, 30, 12), Color(0.1, 0.2, 0.8))
	var prep := Logos.prepare(white)
	check(prep != null and prep.get_width() == 30 and prep.get_height() == 12,
			"weißer Hintergrund wird durchsichtig und abgeschnitten (%s)" % (str(prep.get_size()) if prep else "null"))
	# Rückfall: kein Logo da → Kurzname wie bisher.
	var d2 := L.def_of("zeit_ps2")
	check(Logos.local_source(d2).source == "" and Logos.image_for(d2).is_empty(), "offline und nichts im Cache: kein Logo")
	var t0 := Medal.texture_for(d2, 3, 90)
	check(not Medal.has_logo(t0), "Rückfall: Medaille ohne Logo, Kurzname „PS2“ wird gezeichnet")
	# Cache vorhanden → Logo in der Medaille.
	var logo := Image.create(300, 120, false, Image.FORMAT_RGBA8)
	logo.fill(Color(0, 0, 0, 0))
	logo.fill_rect(Rect2i(10, 10, 280, 100), Color(0.0, 0.3, 0.9))
	logo.fill_rect(Rect2i(40, 30, 60, 60), Color(1, 1, 1))
	DirAccess.make_dir_recursive_absolute(cp.get_base_dir())
	logo.save_png(cp)
	check(Logos.local_source(d2).source == "cache", "Logo im Cache gefunden")
	var t1 := Medal.texture_for(d2, 3, 90)
	check(Medal.has_logo(t1) and str(t1.get_meta("uz_logo")) == "ps2" and t1 != t0, "Medaille trägt das Logo (kein Kurzname darüber)")
	var im0 := t0.get_image()
	var im1 := t1.get_image()
	var cx := im1.get_width() / 2
	var cy := int(im1.get_height() * 0.47)
	var px1 := im1.get_pixel(cx - 25, cy)
	var gold := Color(str(Medal.METALS[3][5]))
	check(px1.get_luminance() > im0.get_pixel(cx - 25, cy).get_luminance() + 0.2 and absf(px1.h - gold.h) < 0.08 and px1.s > 0.15,
			"eingeprägt in Gold (Farbton des Metalls, nicht Blau): %s" % px1.to_html(false))
	var t_l := Medal.texture_for(d2, 0, 90)
	var pl := t_l.get_image().get_pixel(cx - 25, cy)
	check(Medal.has_logo(t_l) and pl.s < 0.12 and pl.get_luminance() < 0.6, "gesperrt: dasselbe Logo grau und gedämpft (%s)" % pl.to_html(false))
	check(t1.get_image().has_mipmaps(), "mit Mipmaps (scharf beim Verkleinern)")
	# Eigene Datei im Medienordner gewinnt (auch als SVG, unter dem Gruppennamen).
	FileAccess.open(tmp.path_join("media/logos/ps2.svg"), FileAccess.WRITE).store_string(
			'<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><circle cx="20" cy="20" r="18" fill="#000"/></svg>')
	var src := Logos.local_source(d2)
	check(src.source == "eigen" and str(src.path).ends_with("ps2.svg"), "eigene Datei im Medienordner gewinnt vor dem Download")
	var t2 := Medal.texture_for(d2, 3, 90)
	check(Medal.has_logo(t2) and t2 != t1, "eigenes SVG in der Medaille")
	var ov_img := Logos.load_image(str(src.path))
	check(ov_img != null and ov_img.get_width() >= 900, "SVG groß gerastert (%d px)" % (ov_img.get_width() if ov_img else 0))
	logo.save_png(tmp.path_join("media/logos/16bit.png"))
	check(Logos.local_source(L.def_of("zeit_16bit"), "megadrive").source == "eigen", "eigene Datei unter dem Gruppennamen (16bit.png)")
	check(Logos.local_source(L.def_of("zeit_gc")).source == "", "andere Plattformen bleiben beim Kurznamen")
	# Laden ausgeschaltet: Geladenes (Cache) bleibt unsichtbar, eigene Dateien gelten weiter.
	Config.set_value("badges.real_logos", false)
	DirAccess.remove_absolute(tmp.path_join("media/logos/ps2.svg"))
	Logos.forget()
	check(Logos.local_source(d2).source == "cache" and Logos.image_for(d2).is_empty(), "aus: Logo im Cache wird nicht gezeigt")
	check(not Medal.has_logo(Medal.texture_for(d2, 3, 90)), "aus: Medaille mit Kurznamen")
	check(str(Logos.image_for(L.def_of("zeit_16bit"), "megadrive").get("source", "")) == "eigen", "aus: eigene Datei gilt weiter")
	# Quellen-Zeile der Startseite: jede Plattform hat einen Logo-Schlüssel mit Commons-Namen.
	Config.set_value("badges.real_logos", true)
	Logos.forget()
	var want := ["ps1", "ps2", "ps3", "ps4", "ps5", "psp", "vita", "gc", "wii", "wiiu", "switch", "n64", "snes", "nes", "gb", "gbc",
		"gba", "nds", "3ds", "megadrive", "saturn", "dreamcast", "xbox", "steam", "epic", "gog", "ea", "ubisoft", "battlenet", "itch",
		"amazon", "riot"]
	var missing: Array = want.filter(func(k: String) -> bool:
		return Logos.source_key(k) == "" or not Logos.LOGOS.has(Logos.source_key(k)) or (Logos.LOGOS[Logos.source_key(k)].files as Array).is_empty())
	check(missing.is_empty(), "Quellen-Zeile: alle %d Plattformen mit Logo %s" % [want.size(), str(missing)])
	check(Logos.source_key("zuletzt") == "" and Logos.source_key("favoriten") == "" and Logos.source_key("alle") == "", "Zuletzt, Favoriten, Alle: Text")
	check(Logos.search_url("Wii U").contains("gsrsearch=Wii%20U%20logo") and Logos.search_url("x").begins_with(Logos.COMMONS_API), "Suche nur auf Commons")
	var hits := { "query": { "pages": [
		{ "index": 2, "title": "File:Wii U logo.svg", "imageinfo": [{ "thumburl": "https://upload.wikimedia.org/b.png", "thumbwidth": 960, "thumbheight": 300 }] },
		{ "index": 1, "title": "File:Wii U console.jpg", "imageinfo": [{ "thumburl": "https://upload.wikimedia.org/a.png" }] },
		{ "index": 0, "title": "File:Wii logo.svg", "imageinfo": [{ "thumburl": "https://upload.wikimedia.org/c.png" }] }] } }
	check(str(Logos.pick_search(hits, "Wii U").get("title", "")) == "File:Wii U logo.svg", "Suche: nur SVG-Logo mit allen Wörtern")
	# Einfarbig: farbiges Logo mit weißer Innenfläche → Loch; schwarze Schrift bleibt ganz.
	var mono := Logos.mono(Logos.prepare(logo))
	check(mono != null and mono.get_pixel(60, 50).a < 0.1 and mono.get_pixel(5, 5).a > 0.9 and mono.get_pixel(5, 5).r > 0.99,
			"einfarbig weiß, weiße Innenfläche wird zum Loch")
	var allwhite := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	allwhite.fill(Color(1, 1, 1, 1))
	allwhite.fill_rect(Rect2i(0, 0, 2, 2), Color(0, 0, 0, 0))
	check(Logos.mono(allwhite).get_pixel(20, 10).a > 0.9, "weißes Logo bleibt ganz")
	var wide := Logos.line_size(6.0, 21.0, 118.0)
	var square := Logos.line_size(1.0, 21.0, 118.0)
	check(wide.y == 20.0 or wide.y == 21.0 or wide.x == 118.0, "Schriftzug: Zeilenhöhe bzw. höchstens 118 breit (%s)" % str(wide))
	check(square.y > 21.0 and square.y <= 30.0, "kompaktes Zeichen etwas größer, gleiche Wirkung (%s)" % str(square))
	var ll := Logos.line_logo("ps2", 21.0, 118.0)
	check(not ll.is_empty() and (ll.tex as Texture2D).get_height() >= int(ll.size.y * 2.4) and (ll.tex as Texture2D).get_image().has_mipmaps(),
			"Logo der Quelle aus dem Cache: scharf für 4K, mit Mipmaps")
	# Beim Start im Hintergrund vorbereitet: dasselbe Bild wie beim ersten Gebrauch, ohne Arbeit im Hauptfaden.
	var direkt := (ll.tex as Texture2D).get_image().get_data()
	Logos.forget()
	Logos._warm = false
	var da := Logos._vorhandene()
	check(da.size() == 2 and str(da[0][0]).begins_with("o:16bit|") and str(da[1][0]).begins_with("ps2|"),
			"auf der Platte: die eigene Datei und das geladene Logo (%d)" % da.size())
	await Logos.aufwaermen()
	check(Logos._images.size() == 2 and Logos._mono_voll.size() == 2, "im Hilfsfaden vorbereitet: Bild und einfarbige Fassung liegen bereit")
	var vorher := Logos._images.duplicate()
	var ll2 := Logos.line_logo("ps2", 21.0, 118.0)
	check(not ll2.is_empty() and (ll2.tex as Texture2D).get_image().get_data() == direkt and Logos._images == vorher,
			"danach kommt das Logo aus dem Vorbereiteten: dieselben Bildpunkte wie beim ersten Gebrauch")
	Config.set_value("badges.real_logos", false)
	Logos.forget()
	Logos._warm = false
	check(Logos._vorhandene().size() == 1, "aus: nur die eigene Datei wird vorbereitet")
	Config.set_value("badges.real_logos", true)
	Config.set_value("badges.real_logos", false)
	check(Logos.line_logo("ps2", 21.0, 118.0).is_empty(), "aus: Quelle zeigt den Namen")
	Config.set_value("badges.real_logos", logos_was)
	Logos.data_dir_override = ""
	Logos.media_dir_override = ""
	Logos.forget()


## Ablauf mit echtem Badges (eigene Datei): erster Lauf still mit Zusammenfassung, danach
## einzelne Pop-ups, nächster Start gesammelt.
func _flow() -> void:
	print("Ablauf: rückwirkend kein Pop-up")
	var path := Config.path("badges_test.json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var b := FakeBadges.new()
	b.file = "badges_test.json"
	b.popups = false
	b.fake = { "hours_ps2": 120.0, "hours_total": 300.0, "ach_total": 15, "ach_points": 900, "streak_best": 4, "present": { "ps2": true } }
	add_child(b)
	await get_tree().process_frame
	b.recompute()
	check(b.announced.is_empty(), "beim Start wird nur gesammelt")
	check(not FileAccess.file_exists(path), "vor dem Abschluss nichts gespeichert")
	b._started_ms = -10000000
	b._check_settled()
	var n_first := int(b.earned_count())
	check(b.announced.size() == 1 and str(b.announced[0].kind) == "summary" and bool(b.announced[0].first), "erster Lauf: genau eine Zusammenfassung")
	check(int(b.announced[0].count) == n_first and n_first >= 4, "„Du hast %d Abzeichen freigeschaltet“" % n_first)
	check(FileAccess.file_exists(path), "danach gespeichert")
	b.announced.clear()
	b.fake["hours_ps2"] = 600.0
	b.recompute()
	var got := b.announced.filter(func(i): return str(i.kind) == "badge")
	check(got.size() == 1 and str(got[0].id) == "zeit_ps2" and int(got[0].tier) == 4, "neu verdient: ein Pop-up (Platin PS2)")
	b.announced.clear()
	b.recompute()
	check(b.announced.is_empty(), "gleicher Stand: nichts doppelt")
	b.fake["ach_points"] = 900 + L.level_start(b.level_number() + 2)
	b.recompute()
	check(b.announced.any(func(i): return str(i.kind) == "level"), "Level-Aufstieg: Level-Pop-up")
	var lv := b.level_number()
	b.queue_free()
	await get_tree().process_frame
	# Nächster Start: drei neue Abzeichen kamen dazu, während Uzai zu war.
	var b2 := FakeBadges.new()
	b2.file = "badges_test.json"
	b2.popups = false
	b2.fake = { "hours_ps2": 600.0, "hours_total": 300.0, "ach_total": 150, "ach_points": 900 + L.level_start(lv + 2), "streak_best": 8, "captures": 1,
			"present": { "ps2": true } }
	add_child(b2)
	await get_tree().process_frame
	b2.recompute()
	check(b2.announced.is_empty(), "nächster Start: erst sammeln")
	b2._started_ms = -10000000
	b2._check_settled()
	check(b2.announced.size() == 1 and str(b2.announced[0].kind) == "summary" and not bool(b2.announced[0].first) and int(b2.announced[0].count) == 3,
		"seit dem letzten Mal: eine Zusammenfassung „3 neue Abzeichen“ (%s)" % str(b2.announced))
	var hist_ok := Toasts.history.any(func(h): return str(h.get("title", "")).contains("Abzeichen"))
	check(hist_ok, "steht auch in den Mitteilungen")
	b2.queue_free()
	DirAccess.remove_absolute(path)
