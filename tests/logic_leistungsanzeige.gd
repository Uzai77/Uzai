extends Node
## Leistungsanzeige im Guide (Roadmap 5, src/core/perf_live.gd): Rohwerte des Helfers prüfen,
## Zeilen, Karte und Ecke aus Beispielwerten, Energieprofile, Zurückstellen nach dem Spiel.
## Aufruf: godot --headless --path . res://tests/logic_leistungsanzeige.tscn

const PerfLive := preload("res://src/core/perf_live.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")
const GB := 1073741824.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Rohwerte")
	var raw := { "ok": true, "cpu": 34.4, "cores": 8, "ram_used": 9.8 * GB, "ram_total": 16.0 * GB, "gpu": 87.2, "gpu_name": "NVIDIA GeForce RTX 3070",
		"vendor": 0x10DE, "vram_used": 6.1 * GB, "vram_total": 8.0 * GB, "gpu_temp": 71, "game_cpu": 21.0, "game_ram": 3.2 * GB, "game_gpu": 85.0,
		"game_vram": 5.4 * GB, "gpu_counters": true }
	var s := PerfLive.normalize(raw)
	check(is_equal_approx(float(s.cpu), 34.4) and int(s.cores) == 8, "Prozessor und Kerne übernommen")
	check(is_equal_approx(float(s.gpu_temp), 71.0), "Temperatur übernommen")
	var odd := PerfLive.normalize(
			{ "cpu": 140.0, "gpu": -3, "gpu_temp": 400, "ram_used": 20.0 * GB, "ram_total": 16.0 * GB, "vram_used": 9.0 * GB, "vram_total": 8.0 * GB,
		"gpu_name": "x".repeat(300), "cores": "8", "game_cpu": "12" })
	check(float(odd.cpu) == 100.0 and float(odd.gpu) == -1.0, "Prozente begrenzt, negativ = unbekannt")
	check(float(odd.gpu_temp) < 0.0, "unmögliche Temperatur verworfen")
	check(float(odd.ram_used) == float(odd.ram_total) and float(odd.vram_used) == float(odd.vram_total), "belegt nie mehr als vorhanden")
	check(str(odd.gpu_name).length() == 80, "Name gekürzt")
	check(int(odd.cores) == 0 and float(odd.game_cpu) == -1.0, "Text statt Zahl: unbekannt")
	check(bool(PerfLive.normalize({ "warming": true }).warming), "misst noch an")
	check(bool(PerfLive.normalize({ "error": "x" }).error), "Fehler bleibt ein Fehler")
	check(PerfLive.parse_reply({ "ok": true, "result": { "json": "{\"cpu\": 5}" } }).get("cpu") == 5.0, "Antwort des Helfers gelesen")
	check(PerfLive.parse_reply({ "ok": true, "result": { "json": "[1]" } }).is_empty(), "keine Liste statt Wörterbuch")
	check(PerfLive.parse_reply({ "ok": true, "result": { "json": "{" + " ".repeat(30000) + "}" } }).is_empty(), "zu große Antwort verworfen")
	check(PerfLive.parse_reply({ "ok": false }).is_empty(), "ohne Erfolg: nichts")

	print("Texte")
	check(PerfLive.pct_text(34.4) == "34 %" and PerfLive.pct_text(-1.0) == "–", "Prozent")
	check(PerfLive.gb_text(6.1 * GB) == "6,1 GB", "6,1 GB (Komma)")
	check(PerfLive.gb_text(12.4 * GB) == "12 GB" and PerfLive.gb_text(512.0 * 1048576.0) == "512 MB", "groß ohne, klein in MB")
	check(PerfLive.used_of(6.1 * GB, 8.0 * GB) == "6,1 / 8 GB", "6,1 / 8 GB")
	check(PerfLive.used_of(11.4 * GB, 31.9 * GB) == "11 / 32 GB", "ab 10 GB ganze Zahlen")
	check(PerfLive.used_of(1.5 * GB, 5.5 * GB) == "1,5 / 5,5 GB", "Größe mit Stelle, wenn nicht glatt")
	check(PerfLive.temp_text(70.6) == "71 °C" and PerfLive.temp_text(-1.0) == "–", "Temperatur")

	print("Übersicht")
	var r := PerfLive.rows(s)
	check(r.size() == 5 and r.map(func(x): return x[0]) == ["cpu", "gpu", "ram", "vram", "temp"], "fünf Zeilen in fester Reihenfolge")
	check(r[0][3] == "34 %" and str(r[0][4]).begins_with("Spiel 21 %"), "Prozessor: gesamt und Spiel")
	check(r[1][3] == "87 %" and str(r[1][4]).contains("RTX 3070"), "Grafikkarte mit Name")
	check(r[3][3] == "6,1 / 8 GB" and r[3][4] == "Spiel 5,4 GB", "Grafikspeicher mit Spiel")
	check(r[4][3] == "71 °C" and absf(float(r[4][5]) - 71.0 / 90.0) < 0.001, "Temperatur mit Balken bis 90 °C")
	var amd := PerfLive.normalize({ "cpu": 10.0, "gpu": 50.0, "vendor": 0x1002, "gpu_counters": true, "ram_used": GB, "ram_total": 8.0 * GB })
	var ra := PerfLive.rows(amd)
	check(ra[4][3] == "Nicht verfügbar" and str(ra[4][4]).contains("NVIDIA"), "AMD: Temperatur ehrlich nicht verfügbar")
	check(ra[3][3] == "–" and ra[3][4] == "Nicht verfügbar", "ohne Grafikspeicher-Wert: nicht verfügbar")
	check(ra[0][4] == "", "Spiel unbekannt: keine Zeile darunter")
	var old := PerfLive.rows(PerfLive.normalize({ "cpu": 10.0, "gpu_counters": false }))
	check(old[1][3] == "–" and str(old[1][4]).contains("keine Werte"), "ohne GPU-Indikatoren: Grund statt Zahl")
	check(PerfLive.rows({ "warming": true })[0][4] == "Wird gemessen …", "erste Sekunde: wird gemessen")
	check(PerfLive.rows({}).size() == 5, "leer: trotzdem alle Zeilen (nichts springt)")

	print("Leiste und Ecke")
	var sp := PerfLive.strip_parts(s)
	check(sp.map(func(x): return x[1]) == ["34 %", "87 %", "9,8 / 16 GB", "6,1 / 8 GB", "71 °C"], "Leiste: CPU, GPU, RAM, VRAM, Temperatur")
	check(PerfLive.strip_parts(amd).size() == 4 and PerfLive.strip_parts(amd)[3][2] == -1.0, "Leiste ohne Temperatur, VRAM ohne Balken")
	check(PerfLive.strip_parts({ "warming": true }).size() == 4, "Leiste beim Anmessen: gleich viele Teile")
	var parts := PerfLive.corner_parts(s)
	check(parts == [["CPU", "34 %"], ["GPU", "87 %"], ["", "71 °C"], ["VRAM", "6,1 GB"]], "Ecke: CPU, GPU, Temperatur, VRAM")
	check(PerfLive.corner_parts({}) == [["", "…"]], "Ecke ohne Werte")
	var zp := PerfLive.zimmer_parts(119.6, 3.14, 2.4)
	check(zp == [["", "120 Bilder/s"], ["GPU", "3,1 ms"], ["CPU", "2,4 ms"]], "Ecke im Zimmer: Bilder/s, Grafikkarte und Prozessor je Bild – %s" % str(zp))
	check(PerfLive.zimmer_parts(0.0, 0.0, -1.0) == [["", "–"], ["GPU", "–"], ["CPU", "–"]], "Ecke im Zimmer vor der ersten Messung")

	print("Energieprofile")
	var pl := PerfLive.parse_plans({ "ok": true, "active": "8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C", "can_set": true, "plans": [
		{ "id": "381b4222-f694-41f0-9685-ff5bb260df2e", "name": "Balanced" }, { "id": "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", "name": "High performance" },
		{ "id": "nicht; shutdown", "name": "x" }, { "id": "381b4222-f694-41f0-9685-ff5bb260df2e", "name": "doppelt" }, "kein Wörterbuch",
		{ "id": "11111111-2222-3333-4444-555555555555", "name": "  Mein Spielprofil  " }] })
	check(pl.ok and (pl.plans as Array).size() == 3, "nur gültige, keine doppelten")
	check(pl.active == "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" and pl.can_set, "aktives klein geschrieben, umschaltbar")
	var one := PerfLive.parse_plans(
			{ "ok": true, "active": "381b4222-f694-41f0-9685-ff5bb260df2e", "can_set": true, "plans": [{ "id": "381b4222-f694-41f0-9685-ff5bb260df2e", "name": "B" }] })
	check(not one.can_set, "nur ein Profil: nichts umzuschalten")
	check(PerfLive.parse_plans({ "ok": true, "active": "ffffffff-ffff-ffff-ffff-ffffffffffff", "plans": [] }).active == "", "aktives muss in der Liste stehen")
	check(PerfLive.plan_name("381B4222-F694-41F0-9685-FF5BB260DF2E", "Balanced") == { "text": "Ausbalanciert", "own": false }, "bekanntes Profil: eigener Name")
	check(PerfLive.plan_name("11111111-2222-3333-4444-555555555555", "  Mein Spielprofil  ") == { "text": "Mein Spielprofil", "own": true },
			"eigenes Profil: Name von Windows, nie übersetzt")
	var a := "381b4222-f694-41f0-9685-ff5bb260df2e"
	var h := "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
	var e := "a1841308-3541-4fab-bc81-f71556f20b4a"
	check(PerfLive.after_switch("", a, h) == a, "erstes Umschalten: vorheriges gemerkt")
	check(PerfLive.after_switch(a, h, e) == a, "weiter umgeschaltet: das ursprüngliche bleibt gemerkt")
	check(PerfLive.after_switch(a, h, a) == "", "zurück aufs ursprüngliche: nichts mehr zurückzustellen")
	check(PerfLive.after_switch("", a, a) == "", "dasselbe gewählt: nichts gemerkt")

	print("Guide")
	check(GuideGame.CHOICES.any(func(x): return x[0] == "perf"), "Leistung als eigene Kachel wählbar")
	var plan := GuideGame.plan([{ "id": "shot", "prio": 10 }, { "id": "clip", "prio": 11 }, { "id": "perf", "prio": GuideGame.SHEET_ONLY }])
	check(not (plan.primary as Array).has("perf") and (plan.more as Array).has("perf"), "automatisch nur unter „Mehr“")
	var pinned := GuideGame.plan([{ "id": "shot", "prio": 10 }, { "id": "perf", "prio": GuideGame.SHEET_ONLY }], 4, ["perf", "", "", ""])
	check(pinned.primary[0] == "perf", "selbst gewählt: vorn auf seinem Platz")
	var d := PerfLive.normalize(PerfLive.demo_raw(12345))
	check(float(d.gpu) > 0.0 and float(d.gpu_temp) > 0.0 and float(d.vram_total) > 0.0, "Demo-Werte vollständig")

	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit()
