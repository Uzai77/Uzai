extends Node
## Guide › Start (docs/PLAN_GUIDE3.md): Bühne mit Kontext (Spielzeit, nächster Erfolg, Aufnahme),
## Neues (Mitteilungen, Downloads), Freunde-Block, Schnellleiste – die reinen Regeln aus
## guide_start.gd und der Aufbau ohne Dopplung. Aufruf: godot --headless --path . res://tests/logic_guidestart.tscn

const GuideStart := preload("res://src/ui/components/guide_start.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const IconsS := preload("res://src/core/icons.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_buehne()
	_erfolge()
	_neues()
	_freunde()
	_schnellleiste()
	_aufbau()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _buehne() -> void:
	print("Bühne: Zeile unter dem Titel")
	var now := int(Time.get_unix_time_from_system())
	check(GuideStart.stage_sub(0, 50400) == "Zuletzt gespielt  ·  14 Std.", "ohne Zeitpunkt (Launcher-Spielzeit): „Zuletzt gespielt · 14 Std.“")
	check(GuideStart.stage_sub(0, 0) == "Noch nicht gespielt", "nie gespielt: klar gesagt")
	check(GuideStart.stage_sub(now - 30, 3600) == "Gerade gespielt  ·  1 Std.", "eben gespielt: wann und wie viel (%s)" % GuideStart.stage_sub(now - 30, 3600))
	check(GuideStart.stage_sub(now - 30, 0) == "Gerade gespielt", "ohne Spielzeit nur das Wann")
	check(GuideStart.stage_sub(now - 3 * 86400, 7200) == "Zuletzt vor 3 Tagen  ·  2 Std.", "vor Tagen: „Zuletzt vor 3 Tagen · 2 Std.“ (%s)" % GuideStart.stage_sub(now - 3 * 86400, 7200))
	print("Spielzeit unter dem Balken im Spiel")
	check(GuideStart.time_bit(0, 600, 0) == "", "erste Runde, unter einer Stunde insgesamt: nichts (die Sitzungsuhr reicht)")
	check(GuideStart.time_bit(0, 600, 432000) == "Insgesamt 120 Std.", "erste Runde heute: Spielzeit insgesamt")
	check(GuideStart.time_bit(3000, 600, 432000) == "Heute 1 Std.  ·  Insgesamt 120 Std.", "heute schon gespielt: Heute samt dieser Sitzung, dazu insgesamt (%s)" % GuideStart.time_bit(3000, 600, 432000))
	check(GuideStart.time_bit(3000, 600, 1800) == "Heute 1 Std.", "unter einer Stunde insgesamt: nur Heute")
	check(GuideStart.time_bit(30, 600, 432000) == "Insgesamt 120 Std.", "unter einer Minute heute zählt nicht als „heute“")
	var sessions := [{ "id": "g", "at": now - 60, "secs": 600 }, { "id": "g", "at": now - 86400 * 2, "secs": 1200 }, { "id": "x", "at": now - 120, "secs": 300 }]
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	check(GuideStart.today_secs(sessions, "g", now, bias) == 600, "heute: nur die Runden von heute und von diesem Spiel")
	check(GuideStart.today_secs(sessions, "", now, bias) == 900, "ohne Spiel: alle Runden von heute")


func _erfolge() -> void:
	print("Erfolge: Neu bzw. Als Nächstes")
	var now := int(Time.get_unix_time_from_system())
	var list := [
		{ "title": "Erste Schritte", "unlocked": true, "date": now - 86400, "rarity": 90.0 },
		{ "title": "Godrick", "unlocked": true, "date": now - 300, "rarity": 60.0 },
		{ "title": "Malenia", "unlocked": false, "rarity": 4.0 },
		{ "title": "Leyndell", "unlocked": false, "rarity": 45.0 },
		{ "title": "Geheim", "unlocked": false, "rarity": 70.0, "hidden": true },
	]
	var p := GuideStart.pick_achievement(list, now - 600)
	check(str(p.kind) == "neu" and str(p.a.title) == "Godrick", "in dieser Sitzung freigeschaltet: der neue")
	check(GuideStart.achievement_line(p) == "Neu: Godrick", "Zeile „Neu: …“")
	var q := GuideStart.pick_achievement(list, now - 60)
	check(str(q.kind) == "naechster" and str(q.a.title) == "Leyndell", "sonst der häufigste offene – nicht der geheime, nicht der seltenste (%s)" % str(q.get("a", {}).get("title", "")))
	check(GuideStart.achievement_line(q) == "Als Nächstes: Leyndell", "Zeile „Als Nächstes: …“")
	check(GuideStart.pick_achievement(list, 0).kind == "naechster", "ohne Sitzungsbeginn (kein Spiel): nie „neu“")
	check(GuideStart.pick_achievement([{ "title": "Alles", "unlocked": true, "date": 5 }], 0).is_empty(), "alles frei und nichts Neues: keine Zeile")
	check(GuideStart.pick_achievement([], 0).is_empty() and GuideStart.achievement_line({}) == "", "leer: nichts")


func _neues() -> void:
	print("Neues: Mitteilungen und Downloads")
	var hist := [{ "title": "A", "kind": "" }, { "title": "B", "kind": "abzeichen" }, { "title": "C" }, { "title": "D" }]
	check(GuideStart.notes(hist, 0).is_empty(), "nichts Ungelesenes: keine Zeile")
	check(GuideStart.notes(hist, 1).map(func(h): return str(h.title)) == ["A"], "eine neue: nur die")
	check(GuideStart.notes(hist, 5).map(func(h): return str(h.title)) == ["A", "C"], "höchstens zwei, Abzeichen stehen nur unter „Mitteilungen“")
	check(GuideStart.downloads_line([]).is_empty(), "keine Downloads: keine Zeile")
	var one := GuideStart.downloads_line([{ "title": "Hades", "phase": "download", "frac": 0.43 }])
	check(str(one.extra) == "Hades  ·  43 %" and str(one.value) == "" and int(one.active) == 1, "ein Download: Titel und Prozent (%s)" % str(one))
	var two := GuideStart.downloads_line([{ "title": "Hades", "phase": "download", "frac": 0.43 }, { "title": "Elden Ring", "phase": "wartet", "frac": -1.0 }])
	check(str(two.value) == "2 aktiv", "zwei: „2 aktiv“")
	var done := GuideStart.downloads_line([{ "title": "Hades", "phase": "done", "frac": 1.0 }])
	check(str(done.extra) == "Hades" and str(done.value) == "Fertig" and int(done.active) == 0, "fertig: ohne Prozent, „Fertig“")
	check(str(GuideStart.downloads_line([{ "title": "X", "phase": "failed", "frac": 0.2 }]).value) == "", "abgebrochen: kein „Fertig“")
	var now := int(Time.get_unix_time_from_system())
	check(GuideStart.fresh({ "mtime": now - 3600 }, now) and not GuideStart.fresh({ "mtime": now - 2 * 86400 }, now) and not GuideStart.fresh({}, now),
			"Aufnahme ohne Spiel im Start nur, wenn sie von heute ist")


func _freunde() -> void:
	print("Freunde im Start")
	var gs := Quelle.lesen("res://src/ui/layers/guide.gd")
	check(not gs.contains("_friends_block") and not gs.contains("_FriendsBlock"), "keine Freunde im Start (der Reiter Freunde liegt daneben)")


func _schnellleiste() -> void:
	print("Schnellleiste")
	var alles := GuideStart.quick_ids({ "mic": true, "volume": true, "pads": true, "rest": true })
	check(alles == ["mic", "volume", "pads", "rest", "power"], "Mikro, Lautstärke, Controller, Ruhemodus, Ausschalten (%s)" % str(alles))
	check(GuideStart.quick_ids({}) == ["power"], "ohne Windows, Controller und Ruhemodus bleibt Ausschalten")
	check(GuideStart.quick_ids({ "volume": true, "rest": true }) == ["volume", "rest", "power"], "kein Mikrofon (kein Helfer, kein Discord): kein Mikro-Knopf")
	check(alles.size() <= 5, "höchstens fünf Knöpfe – mehr passt nicht in die Leiste")
	for ic in ["mic", "mic_off", "volume", "controller", "moon", "power", "trophy", "video", "download", "camera"]:
		check(IconsS.P.has(ic), "Symbol „%s“ gibt es" % ic)


## Aufbau ohne Dopplung: was der Start zeigt, steht nicht noch einmal unter „Mehr …“ oder in System.
func _aufbau() -> void:
	print("Aufbau ohne Dopplung")
	var gs := Quelle.lesen("res://src/ui/layers/guide.gd")
	check(gs.contains("_set_strip(GuideStart.quick_strip(self))") and gs.contains("GuideStart.context_rows(self) + GuideStart.news_rows(self)"),
			"Start: Kontext, Neues und Schnellleiste aus guide_start.gd")
	check(gs.contains("_holder.offset_bottom = -FOOT_H - GuideStart.STRIP_H") and gs.contains("[_head, _tabs_bar, _holder, _strip, _foot]"),
			"Schnellleiste fest unten (die Liste endet darüber) und Teil der Schrift beim Auf- und Zugehen")
	check(gs.contains("U.kreuz_aus(tw, old)") and gs.contains("U.NACH_WEG if dir != 0") and not gs.contains("U.T_WEG / 3.0"),
			"Reiterwechsel kreuzt: Altes hält ein Bild und geht sine in-out, Neues kommt NACH_WEG später")
	check(gs.contains("func _nachblenden()") and gs.contains("_old_keys.has(k)"), "leiser Neuaufbau: nur Neues blendet nach")
	check(gs.contains("func flaeche() -> Control:") and gs.contains("tween_property(_scrim, \"color\", ziel, U.T_ORT)") and gs.contains("func _exit_motion("),
			"Öffnen mit Tiefe: Fläche vor Schrift, Abdunklung blendet, Schließen mit Schrift zuerst")
	check(not gs.contains("U.T_MOVE") and not gs.contains("T_FAST") , "Reiterstrich und Seite im Takt (T_ORT, T_WEG, NACH_WEG), keine alten Namen")
	check(not gs.contains("setup(\"Lautstärke\", \"volume\")") and not gs.contains("setup(\"Mikrofon\""), "Lautstärke und Mikro nicht mehr als Zeilen unter „Mehr …“")
	check(not gs.contains("Mixer.snapshot()"), "beim Öffnen kein Mixer-Schnappschuss mehr (Helfer-Aufruf nur noch im Mixer selbst)")
	check(not gs.contains("NOTES_MAX") and not gs.contains("_act(\"Mitteilungen\"") and gs.contains("icon_button(\"bell\")"),
			"Mitteilungen nur als Glocke oben im Kopf, nicht mehr in System")
	check(not gs.contains("_act(\"Downloads\""), "System: Downloads nicht mehr unter „Mehr …“ (stehen im Start, solange etwas lädt)")
	var gg := Quelle.lesen("res://src/ui/components/guide_game.gd")
	check(not gg.contains("Erfolge\" % [int(res.unlocked), int(res.total)]"), "Spielblock: Zahlen stehen in der Zeile „Erfolge“, nicht unter dem Balken")
	check(gg.contains("int(res.get(\"total\", 0)) <= 0:") and gg.contains("if Capture.for_game(game, 1).is_empty():"),
			"„Mehr › Spiel“: Erfolge und Aufnahmen nur, solange der Start sie nicht zeigt")
	var st := FileAccess.get_file_as_string("res://src/ui/components/guide_start.gd")
	check(st.contains("Achievements.cached(game)") and not st.contains("Achievements.for_game("), "Kontext aus dem Zwischenspeicher, keine Abfrage beim Öffnen")
	check(st.contains("Capture.thumb(path") and st.contains("Media.file_texture("), "Vorschaubild der Aufnahme kommt nach, blockiert nicht")
	check(st.contains("set_meta(\"uz_row\", true)") and st.contains("set_meta(\"uz_mem\", true)"), "Schnellleiste: links/rechts in der Leiste, Auswahl gemerkt")
	var sp := FileAccess.get_file_as_string("res://src/ui/layers/guide_spiel.gd")
	check(sp.contains("GuideStartS.time_bit(") and sp.contains("GuideStartS.stage_sub("), "Zeile unter dem Titel: Spielzeit im Spiel, Wann und Wie viel ohne Spiel")
	check(sp.contains("if fresh:") and sp.contains("GuideStartS.capture_row(self, cap)"), "ohne Spiel: heutige Aufnahme in der Liste, sonst unter „Mehr …“")
	var vb := Quelle.lesen("res://src/ui/layers/guide_basis.gd")
	check(Guide.volume_none_text("kein_spiel") == "Kein Spiel läuft" and vb.length() > 0, "LT/RT ohne Spiel: ein kurzer Satz")
