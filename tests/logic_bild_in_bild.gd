extends Node
## Bild in Bild ohne Windows: Lage und Größe in der Ecke (Rand, Skalierung, Arbeitsbereich,
## mehrere Bildschirme), Einrasten, Stick, Ablauf (rein, raus, Spiel, Guide, Verschieben, Ruhemodus,
## fremdes Programm vorn, Ausschalten), wer vorn liegt, mpv-Argumente und -Befehle, Lautstärke
## (gleich laut wie im Vollbild, eigene Stufe nur auf Wunsch), Reiter im Guide (zuerst, Vollbild
## vorn), neues Video während des Beendens, Guide ohne Pause, englische Zeile und die Vorschau.
## Aufruf: godot --headless --path . res://tests/logic_bild_in_bild.tscn

const Pip := preload("res://src/core/pip.gd")
const GuidePip := preload("res://src/ui/components/guide_pip.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const Lang := preload("res://src/core/lang.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	Config.settings.erase("pip")

	print("Größe und Lage")
	var work := Rect2i(0, 0, 1920, 1040)       # 1080p, Taskleiste unten 40 px
	var m := Pip.size_for(work, "m")
	check(m == Vector2i(538, 302), "Mittel: 28 %% der Breite, 16:9 (%s)" % str(m))
	check(absf(float(m.x) / float(m.y) - 16.0 / 9.0) < 0.01, "Seitenverhältnis 16:9")
	var br := Pip.place(work, Vector2(1, 1), m)
	check(br.end == Vector2i(1920 - 28, 1040 - 28), "unten rechts mit Rand, über der Taskleiste (%s)" % str(br))
	var tl := Pip.place(work, Vector2(0, 0), m)
	check(tl.position == Vector2i(28, 28), "oben links mit Rand")
	check(Pip.size_for(work, "s").x < m.x and m.x < Pip.size_for(work, "l").x, "Klein < Mittel < Groß")
	check(Pip.size_for(Rect2i(0, 0, 1280, 680), "s").x == 320, "nie schmaler als 320 px (kleiner Bildschirm)")
	var tiny := Pip.size_for(Rect2i(0, 0, 1000, 200), "l")
	check(tiny.y == 144 and tiny.x == 256, "flacher Platz: Höhe begrenzt, 16:9 bleibt (%s)" % str(tiny))
	var hi := Rect2i(0, 0, 1080, 1880)
	var pr := Pip.place(hi, Vector2(1, 1), Pip.size_for(hi, "l"))
	check(hi.encloses(pr) and pr.size.x == 410, "Hochkant-Bildschirm: passt hinein (%s)" % str(pr))

	print("Skalierung (DPI)")
	check(Pip.dpi_scale(96) == 1.0 and Pip.dpi_scale(144) == 1.5 and Pip.dpi_scale(0) == 1.0 and Pip.dpi_scale(72) == 1.0,
			"96 = 100 %, 144 = 150 %, unbekannt = 100 %")
	var w4 := Rect2i(0, 0, 3840, 2100)
	var m4 := Pip.size_for(w4, "m", 1.5)
	var br4 := Pip.place(w4, Vector2(1, 1), m4, 1.5)
	check(br4.end == Vector2i(3840 - 42, 2100 - 42), "150 %%: Rand 42 px (%s)" % str(br4))
	check(Pip.size_for(Rect2i(0, 0, 1700, 900), "s", 1.5).x == 480, "150 %: Mindestbreite 480 px")

	print("Mehrere Bildschirme, Arbeitsbereich, Umkehrung")
	var right_mon := Rect2i(1920, -200, 2560, 1400)
	var r2 := Pip.place(right_mon, Vector2(1, 0), Pip.size_for(right_mon, "m"))
	check(right_mon.encloses(r2) and r2.position.y == -172 and r2.end.x == 1920 + 2560 - 28, "zweiter Bildschirm rechts, höher: oben rechts dort (%s)" % str(r2))
	var mid := Pip.place(work, Vector2(0.25, 0.6), m)
	var back := Pip.fractions(work, mid, 1.0)
	check(absf(back.x - 0.25) < 0.01 and absf(back.y - 0.6) < 0.01, "Lage aus dem Fenster zurückrechnen (Maus): %s" % str(back))
	check(Pip.fractions(work, Rect2i(-500, 5000, 538, 303), 1.0) == Vector2(0, 1), "außerhalb: an den Rand")
	var cl := Pip.clamp_rect(Rect2i(1800, 900, 538, 302), work)
	check(work.encloses(cl) and cl.size == Vector2i(538, 302), "halb aus dem Bild: ganz hinein (%s)" % str(cl))
	check(Pip.clamp_rect(Rect2i(0, 0, 3000, 2000), work).size == work.size, "größer als der Platz: auf den Platz")
	check(Pip.geometry(Rect2i(1354, 709, 538, 303), Rect2i(0, 0, 1920, 1080)) == "538x303+1354+709", "mpv --geometry relativ zum Bildschirm")
	check(Pip.geometry(Rect2i(-1892, 28, 538, 303), Rect2i(-1920, 0, 1920, 1080)) == "538x303+28+28", "Bildschirm links vom Hauptbildschirm")

	print("Einrasten, Ecken, Stick")
	check(Pip.snap(Vector2(0.03, 0.97)) == Vector2(0, 1) and Pip.snap(Vector2(0.5, 0.4)) == Vector2(0.5, 0.4), "nah am Rand rastet ein, in der Mitte nicht")
	check(Pip.corner_of(Vector2(1, 1)) == "unten_rechts" and Pip.corner_of(Vector2(0, 0)) == "oben_links" and Pip.corner_of(Vector2(0.5, 1)) == "frei",
			"Ecken erkannt, sonst frei")
	var free := Pip.free_space(work, m)
	check(free == Vector2(1920 - 56 - m.x, 1040 - 56 - m.y), "freier Platz")
	check(Pip.stick_delta(Vector2(0.15, 0.1), 0.016, free) == Vector2.ZERO, "Totzone: kein Zittern")
	var d1 := Pip.stick_delta(Vector2(1, 0), 1.0, free)
	check(absf(d1.x * free.x - Pip.MOVE_SPEED) < 0.5 and d1.y == 0.0, "voller Ausschlag: %d px pro Sekunde" % int(Pip.MOVE_SPEED))
	var d2 := Pip.stick_delta(Vector2(0.5, 0), 1.0, free)
	check(d2.x > 0.0 and d2.x < d1.x * 0.4, "halber Ausschlag deutlich langsamer (weiche Kurve)")
	check(absf(Pip.stick_delta(Vector2(1, 0), 1.0, free, 1.5).x * free.x - Pip.MOVE_SPEED * 1.5) < 0.5, "Tempo wächst mit der Skalierung")
	check(Pip.step_size("m", 1) == "l" and Pip.step_size("l", 1) == "l" and Pip.step_size("s", -1) == "s" and Pip.step_size("?", -1) == "s",
			"Größe: Klein/Mittel/Groß, am Ende bleibt es")
	check(Pip.next_opacity(100) == 85 and Pip.next_opacity(85) == 70 and Pip.next_opacity(70) == 100 and Pip.next_opacity(33) == 100,
			"Deckkraft 100 → 85 → 70 → 100")

	print("Ablauf")
	var st := { "mode": "aus", "lage": "oben" }
	var s1 := Pip.step(st, "an")
	check(s1.mode == "an" and s1.lage == "oben" and s1.actions == ["klein"], "aus dem Player: klein, obenauf")
	var s2 := Pip.step({ "mode": "an", "lage": "oben", "guide": true }, "guide_auf")
	check(s2.lage == "unter" and s2.actions == ["unter_uzai"], "Guide auf: Bild direkt unter Uzai (Guide bleibt bedienbar)")
	var s3 := Pip.step({ "mode": s2.mode, "lage": s2.lage, "guide": true }, "bewegen")
	check(s3.mode == "bewegen" and s3.lage == "oben" and s3.actions == ["nach_oben"], "Verschieben: Bild obenauf")
	var s4 := Pip.step({ "mode": s3.mode, "lage": s3.lage, "guide": true }, "bewegen_fertig")
	check(s4.mode == "an" and s4.lage == "unter" and s4.actions == ["einrasten", "merken", "unter_uzai"], "A: einrasten, merken, wieder unter den Guide")
	var s4b := Pip.step({ "mode": "bewegen", "lage": "oben", "guide": true }, "bewegen_zurueck")
	check(s4b.mode == "an" and s4b.actions == ["zuruecksetzen", "unter_uzai"], "B: zurück an die alte Stelle")
	var s5 := Pip.step({ "mode": "bewegen", "lage": "oben", "guide": false }, "guide_zu")
	check(s5.mode == "an" and s5.lage == "oben" and s5.actions == ["merken", "nach_oben"], "Guide-Taste beim Verschieben: neue Stelle bleibt")
	var s6 := Pip.step({ "mode": "an", "lage": "unter" }, "guide_zu")
	check(s6.lage == "oben" and s6.actions == ["nach_oben"], "Guide zu: wieder über dem Spiel")
	var s7 := Pip.step({ "mode": "an", "lage": "oben" }, "ruhe")
	check(s7.lage == "weg" and s7.actions == ["verstecken"], "Ruhemodus: versteckt (Video hält an)")
	check(Pip.step({ "mode": "an", "lage": "weg" }, "bewegen").mode == "an", "versteckt: nicht verschiebbar")
	var s8 := Pip.step({ "mode": "an", "lage": "weg" }, "wach")
	check(s8.lage == "oben" and s8.actions == ["zeigen", "nach_oben"], "Aufwachen: wieder da")
	var s9 := Pip.step({ "mode": "an", "lage": "oben" }, "vollbild", true)
	check(s9.mode == "an" and s9.actions == ["erst_spiel"], "im Spiel kein Vollbild (ruhiger Hinweis)")
	var s10 := Pip.step({ "mode": "an", "lage": "oben" }, "vollbild", false)
	check(s10.mode == "aus" and s10.actions == ["gross"], "ohne Spiel: zurück ins Vollbild")
	check(Pip.step({ "mode": "an", "lage": "unter" }, "ausschalten").actions == ["aus"], "Ausschalten schließt Bild in Bild (sofort)")
	check(Pip.step({ "mode": "an", "lage": "oben" }, "schliessen").actions == ["stopp"], "Schließen merkt sich die Stelle, dann zu")
	check(Pip.step({ "mode": "an", "lage": "oben" }, "gestoppt").mode == "aus", "Video anders beendet: aus")
	var s11 := Pip.step({ "mode": "an", "lage": "oben" }, "spiel_fenster", true)
	check(s11.mode == "an" and s11.actions == ["umziehen", "vollbild_pruefen"], "Spiel ist da: auf dessen Bildschirm, exklusives Vollbild prüfen")
	check(Pip.step({ "mode": "an", "lage": "oben" }, "spiel_ende").mode == "an", "Spiel beendet: Bild in Bild bleibt")
	check(Pip.step({ "mode": "aus", "lage": "oben" }, "guide_auf").actions.is_empty() and Pip.step({ "mode": "aus" }, "spiel_fenster").actions.is_empty(),
			"aus: nichts zu tun")
	var s12 := Pip.step({ "mode": "aus", "lage": "oben", "guide": true }, "start")
	check(s12.mode == "an" and s12.lage == "unter" and s12.actions == ["fenster"], "gleich als Bild in Bild aus dem Guide")
	check(Pip.exclusive_hint().contains("randlos"), "Hinweis bei exklusivem Vollbild nennt das randlose Fenster")

	print("Anderes Programm vorn (Alt+Tab, Desktop)")
	var f1 := Pip.step({ "mode": "an", "lage": "oben" }, "fremd_vorn")
	check(f1.lage == "fremd" and f1.actions == ["verstecken"], "fremdes Programm vorn: Bild versteckt (nicht mehr über allem)")
	var f2 := Pip.step({ "mode": "an", "lage": "fremd" }, "wieder_vorn")
	check(f2.lage == "oben" and f2.actions == ["zeigen", "nach_oben"], "Uzai oder Spiel wieder vorn: Bild wieder da, obenauf")
	var f3 := Pip.step({ "mode": "an", "lage": "fremd", "guide": true }, "guide_auf")
	check(f3.lage == "unter" and f3.actions == ["zeigen", "unter_uzai"], "Guide-Taste von dort: Bild kommt mit, unter den Guide")
	check(Pip.step({ "mode": "an", "lage": "fremd" }, "guide_zu").lage == "fremd", "Guide zu, fremdes Programm noch vorn: bleibt versteckt")
	check(Pip.step({ "mode": "an", "lage": "fremd" }, "bewegen").mode == "an", "versteckt: nicht verschiebbar")
	check(Pip.step({ "mode": "an", "lage": "unter" }, "fremd_vorn").actions.is_empty() and Pip.step({ "mode": "an", "lage": "weg" }, "fremd_vorn").lage == "weg"
			and Pip.step({ "mode": "bewegen", "lage": "oben" }, "fremd_vorn").lage == "oben", "nur aus „oben“ (Guide, Ruhemodus, Verschieben: nicht)")
	var f4 := Pip.step({ "mode": "an", "lage": "fremd" }, "vollbild", false)
	check(f4.mode == "aus" and f4.actions == ["zeigen", "gross"], "Vollbild aus dem Versteck: erst zeigen, dann groß")
	check(Pip.step({ "mode": "an", "lage": "fremd" }, "ruhe").lage == "weg", "Ruhemodus von dort: versteckt bleibt versteckt")
	check(Pip.step({ "mode": "an", "lage": "oben" }, "wieder_vorn").actions.is_empty(), "schon oben: nichts zu tun")
	var own := 4000
	var mpv := 4100
	check(Pip.unser_vorn({ "fg_hwnd": 11, "fg_pid": own }, own, mpv, false, 0, []), "Uzai vorn: unser")
	check(Pip.unser_vorn({ "fg_hwnd": 12, "fg_pid": mpv }, own, mpv, false, 0, []), "das Video selbst vorn (mpv): unser")
	check(not Pip.unser_vorn({ "fg_hwnd": 13, "fg_pid": 777 }, own, mpv, false, 0, []), "ohne Spiel ein anderes Programm (Browser, Desktop): fremd")
	check(Pip.unser_vorn({ "fg_hwnd": 0, "fg_pid": 0 }, own, mpv, false, 0, []) and Pip.unser_vorn({}, own, mpv, true, 50, [9]),
			"niemand vorn bzw. keine Antwort: nichts ändern")
	check(Pip.unser_vorn({ "fg_hwnd": 50, "fg_pid": 900, "game_pid": 900 }, own, mpv, true, 50, []), "im Spiel: Spielfenster vorn")
	check(Pip.unser_vorn({ "fg_hwnd": 51, "fg_pid": 900, "game_pid": 900 }, own, mpv, true, 50, []), "im Spiel: anderes Fenster desselben Prozesses")
	check(Pip.unser_vorn({ "fg_hwnd": 52, "fg_pid": 901, "game_pid": 900 }, own, mpv, true, 50, [901]), "im Spiel: Prozess des Spiels (Starter-Baum)")
	check(not Pip.unser_vorn({ "fg_hwnd": 53, "fg_pid": 777, "game_pid": 900 }, own, mpv, true, 50, [901]), "im Spiel: Alt+Tab in ein anderes Programm – fremd")
	check(Pip.unser_vorn({ "fg_hwnd": 53, "fg_pid": 777, "game_pid": 0 }, own, mpv, true, 0, []), "Spiel ohne bekanntes Fenster und Prozess: nicht verstecken")

	print("mpv")
	var wa := Video.window_args(true, 0, "538x303+1354+709")
	check(wa.has("--ontop") and wa.has("--border=no") and wa.has("--geometry=538x303+1354+709") and not wa.has("--fullscreen"),
			"Bild in Bild: obenauf, ohne Rahmen, an seinem Platz: %s" % str(wa))
	check(wa.has("--cursor-autohide=1000"), "Mauszeiger zum Ziehen sichtbar")
	var wf := Video.window_args(false, 1)
	check(wf.has("--geometry=100%x100%+0+0") and wf.has("--fs-screen=1") and wf.has("--screen=1"), "Vollbild wie bisher auf Uzais Bildschirm")
	var on := Video.pip_cmds(true)
	check(on.has(["set_property", "fullscreen", false]) and on.has(["set_property", "auto-window-resize", false]),
			"rein: Vollbild aus, nächstes Video ändert die Größe nicht")
	var off := Video.pip_cmds(false)
	check(off.has(["set_property", "fullscreen", true]) and off.has(["set_property", "cursor-autohide", "always"]), "raus: Vollbild, Zeiger wieder weg")
	check(Video.osd_hints().any(func(h): return h[1] == "Bild in Bild"), "Leiste in mpv nennt ≡ Bild in Bild")

	print("Lautstärke")
	check(Pip._num("pip.gibtsnicht", 0.5) == 0.5, "kaputte oder fehlende Werte: Standard")
	var keep_yt: Variant = Config.get_value("youtube.volume", 100)
	Config.set_value("youtube.volume", 90)
	Config.set_value("pip.volume", 40)
	Video.pip = true
	check(not Video.own_pip_volume() and Video.volume_key() == "youtube.volume" and Video.volume_level() == 90,
			"Bild in Bild: so laut wie im Vollbild (%d), auch mit alter eigener Stufe" % Video.volume_level())
	Video.volume(-Video.VOLUME_STEP)
	Video.pip = false
	check(Video.volume_level() == 85, "leiser im Bild in Bild gilt auch im Vollbild – Verkleinern ändert den Ton nie")
	Config.settings.erase("pip")
	Config.set_value("pip.own_volume", true)
	Video.pip = true
	check(Video.volume_key() == "pip.volume" and Video.volume_level() == 85, "eigene Stufe eingeschaltet: beginnt bei der Stufe des Vollbilds")
	Video.volume(-Video.VOLUME_STEP)
	check(int(Config.get_value("pip.volume", 0)) == 80 and int(Config.get_value("youtube.volume", 0)) == 85, "dann ändert leiser nur Bild in Bild")
	Video.pip = false
	check(Video.volume_level() == 85, "im Vollbild die eigene Stufe des Vollbilds")
	Config.settings.erase("pip")
	Config.set_value("youtube.volume", keep_yt)
	check(Guide.volume_target("pip", true, false, {}, false) == "video", "Guide-Reiter Bild in Bild: LT/RT = Lautstärke des Videos")
	check(Guide.volume_target("spiel", true, false, {}, false) == "spiel", "Reiter Spiel mit Bild in Bild: LT/RT bleibt das Spiel")

	print("Vorschau (ohne mpv): rein, Guide, Verschieben, Ruhemodus, Vollbild, zu")
	var main := MainStub.new()
	U_full(main)
	add_child(main)
	var host := Control.new()
	main.add_child(host)
	main.layer_host = host
	var pip = Pip.new()
	pip.main = main
	add_child(pip)
	main.pip = pip
	check(GuidePip.tabs(Guide.TABS, main).size() == Guide.TABS.size(), "ohne Bild in Bild: Reiter wie immer")
	Video.play([{ "id": "pip-test", "title": "Testvideo", "url": "https://example.invalid/v.mp4", "duration": 600 }], 0)
	await get_tree().create_timer(0.7).timeout
	check(Video.active and Video.sim, "Video läuft (Simulation)")
	var ok: bool = await pip.enter()
	check(ok and pip.mode == "an" and Video.pip, "rein")
	var tabs := GuidePip.tabs(Guide.TABS, main)
	check(tabs.size() == Guide.TABS.size() + 1 and str(tabs[0][0]) == "pip" and str(tabs[1][0]) == "spiel",
			"Guide: Reiter „Bild in Bild“ zuerst (der Guide geht dort auf), der Rest dahinter")
	check(GuidePip.pill_ids(false, false) == [["full", true], ["play", false], ["close", false]], "ohne Spiel: Vollbild vorgewählt, dann Pause, Schließen")
	check(GuidePip.pill_ids(true, true) == [["play", true], ["help", false], ["close", false]] and GuidePip.pill_ids(true, false).size() == 2,
			"im Spiel kein Vollbild: Pause vorn")
	check(Guide.tab_fit([60, 50, 80, 70, 60], 470.0) == { "pad": 12.0, "fs": 20 } and Guide.tab_fit([60, 50, 80, 70, 60, 70], 500.0).pad == 8.0,
			"Reiter: Abstand wie bisher, wenn Platz ist")
	var eng := Guide.tab_fit([70, 48, 90, 72, 56, 64], 468.0)
	check(int(eng.fs) == 20 and float(eng.pad) < 8.0 and float(eng.pad) >= 4.0 and 400.0 + float(eng.pad) * 12.0 <= 468.0,
			"etwas zu lang: enger statt unter RB (%s)" % str(eng))
	var de := Guide.tab_fit([100, 47, 99, 71, 55, 69], 468.0)
	check(float(de.pad) == 4.0 and int(de.fs) < 20 and 441.0 * float(de.fs) / 20.0 + 48.0 <= 468.0, "„Bild in Bild“ zuerst (Deutsch): kleinere Schrift (%s)" % str(de))
	check(int(Guide.tab_fit([300, 300], 100.0).fs) == 16, "nie kleiner als 16 px")
	await get_tree().create_timer(Pip.ENTER_MS / 1000.0 + 0.15).timeout
	var sim: Control = pip._sim
	check(is_instance_valid(sim) and sim.visible, "Vorschau da")
	check(is_instance_valid(sim) and Rect2i(Rect2(sim.position, sim.size)) == pip.rect(),
			"in der Ecke angekommen (%s)" % (str(Rect2(sim.position, sim.size)) if is_instance_valid(sim) else "-"))
	check(sim.get_index() > host.get_index(), "obenauf (über Uzais Ebenen)")
	main._guide = Control.new()
	await get_tree().process_frame
	await get_tree().process_frame
	check(pip.lage == "unter" and sim.get_index() < host.get_index(), "Guide auf: unter dem Guide")
	var f0: Vector2 = pip.lage_f()
	await pip.move_begin()
	check(pip.mode == "bewegen" and sim.get_index() > host.get_index(), "Verschieben: obenauf")
	pip.move_by_stick(Vector2(-1, 0), 0.5)
	check(pip.lage_f().x < f0.x and pip.lage_f().y == f0.y, "Stick nach links: wandert nach links")
	pip.set_size("l")
	await pip.move_end(false)
	check(pip.lage_f() == f0 and pip.size_key() == "m" and pip.mode == "an", "B: Stelle und Größe zurück")
	await pip.move_begin()
	pip.move_by_stick(Vector2(-1, -1), 30.0)
	await pip.move_end(true)
	check(pip.corner() == "oben_links", "ganz nach oben links geschoben, eingerastet")
	pip.set_corner("unten_rechts")
	check(pip.lage_f() == Vector2(1, 1) and float(Config.get_value("pip.fx", 0)) == 1.0, "Ecke gewählt und gemerkt")
	main._guide.free()
	main._guide = null
	await get_tree().process_frame
	await get_tree().process_frame
	check(pip.lage == "oben", "Guide zu: wieder obenauf")
	var rs := RestStub.new()
	main.rest = rs
	rs.active = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(pip.lage == "weg" and not sim.visible, "Ruhemodus: versteckt")
	rs.active = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(pip.lage == "oben" and sim.visible, "aufgewacht: wieder da")
	check(pip.cycle_opacity() == 85 and absf(sim.modulate.a - 0.85) < 0.01, "Deckkraft 85 %")
	await pip.leave()
	check(pip.mode == "aus" and not Video.pip and main.opened == 1, "Vollbild: Player wieder auf")
	await pip.enter()
	Video.stop()
	await get_tree().create_timer(0.1).timeout
	check(pip.mode == "aus" and not Video.pip and not Video.active, "Video beendet: Bild in Bild aus")
	await pip.enter()
	check(pip.mode == "aus", "ohne Video kein Bild in Bild")
	rs.free()
	Config.settings.erase("pip")

	print("")
	print("Neues Video, während das alte noch beendet wird")
	Video.play([{ "id": "alt", "title": "Alt", "url": "https://example.invalid/a.mp4", "duration": 600 }], 0)
	# Ein eigener Kindprozess steht für das alte mpv (das Beenden schießt ihn ab, nur ihn).
	var alt := OS.create_process("/bin/sleep", ["20"])
	Video.sim = false
	Video._pid = alt
	Video.stop()
	Video.play([{ "id": "neu", "title": "Neu", "url": "https://example.invalid/n.mp4", "duration": 600 }], 0)
	await get_tree().create_timer(0.5).timeout
	check(Video.active and str(Video.video.get("id", "")) == "neu", "das Beenden des alten nimmt das neue nicht mit (läuft: %s)" % str(Video.video.get("id", "")))
	Video.stop()
	var psrc := (load("res://src/core/pip.gd") as GDScript).source_code
	check(psrc.contains("await Video.stop()"), "Schließen wartet, bis mpv zu ist")

	print("Guide hält kein Video an")
	var gsrc := (load("res://src/main_guide.gd") as GDScript).source_code
	check(not gsrc.contains("Video.set_pause(true)") and not gsrc.contains("_resume_video"), "Guide auf: keine Pause, Guide zu: nichts fortzusetzen")
	var msrc := (load("res://src/main.gd") as GDScript).source_code
	check(msrc.contains("if not Video.paused and not guide_auf:"), "Video vorn: der Guide darüber hält nicht an (Optionen weiter)")
	var spsrc := (load("res://src/ui/layers/guide_spiel.gd") as GDScript).source_code
	check(spsrc.contains("\"g:video_pause\"") and spsrc.contains("Video.toggle_pause()"), "Reiter Video: Pause nur auf Knopfdruck")

	print("Englisch")
	Lang.apply("en")
	Video.play([{ "id": "en-test", "title": "Test", "url": "https://example.invalid/e.mp4", "duration": 600 }], 0)
	await get_tree().create_timer(0.8).timeout
	check(Pip.status_text().begins_with("Picture-in-picture  ·  Playing"), "Zeile im Guide auf Englisch (%s)" % Pip.status_text())
	var om := Video.meta_for_osd()
	check((om.hints as Array).any(func(h): return h[1] == "Volume") and (om.hints as Array).any(func(h): return h[1] == "Picture-in-picture")
			and not (om.hints as Array).any(func(h): return h[1] == "Lautstärke"), "Tasten in der Leiste von mpv auf Englisch")
	check(str(om.txt.next) == "UP NEXT" and str(om.txt.paused) == "Paused" and str(om.txt.volume) == "Volume", "feste Texte der Leiste übersetzt")
	Video.stop()
	Lang.release()
	TranslationServer.set_locale("de")
	check(str(Video.osd_texts().next) == "ALS NÄCHSTES" and str(Video.osd_texts().ends) == "Endet um %s", "Deutsch: wie bisher")

	print("")
	print("Neues Video, während Bild in Bild läuft")
	var main_src := (load("res://src/main.gd") as GDScript).source_code
	check(main_src.contains("if pip != null and pip.active():") and main_src.contains("await pip.close()") and main_src.contains('opts["pip"] = false'),
			"anderes Video: Bild in Bild beenden, neues groß starten")
	check(main_src.contains("if same:\n\t\t\tpip.leave()\n\t\t\treturn"), "dasselbe Video: nur wieder groß")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


static func U_full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)


class MainStub extends Control:
	var layer_host: Control
	var _guide: Control
	var rest: Node
	var pip: Node
	var opened := 0

	func open_movie_player() -> void:
		opened += 1


class RestStub extends Node:
	var active := false
