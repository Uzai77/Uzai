extends Node
## Kopfleiste: Status rechts nur mit dem, was zählt (kopf_status.gd: schwache Controller, Freunde
## nur online, Punkt für Neues am Profilbild), die Leiste ruht im Inhalt (kopf_ruhe.gd: Stufen,
## LT/RT nur oben, gerollte Listen), der Punkt der Marke unter dem Bereich (tab_strip.gd) und die
## Leiste in main.gd ohne Haarlinie, Glocke und Level. Ohne main.gd: eigene kleine Bäume.
## Bilder: tests/probe_leiste.gd, Bedienung im echten Uzai: tests/probe_reiter.gd.
## Aufruf: godot --headless --path . res://tests/logic_kopf.tscn

const KopfStatus := preload("res://src/ui/components/kopf_status.gd")
const KopfRuhe := preload("res://src/ui/components/kopf_ruhe.gd")
const TabStrip := preload("res://src/ui/components/tab_strip.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const U := preload("res://src/ui/u.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	var unread := Toasts.unread
	_pads()
	_freunde()
	_stufen()
	await _punkt()
	await _status()
	await _ruhe()
	_quelle()
	Toasts.unread = unread
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _pads() -> void:
	print("Controller oben: nur schwache")
	var pads := [
		{ "slot": 1, "level": 3 }, { "slot": 2, "level": 1 }, { "slot": 3, "level": 0, "charging": true },
		{ "slot": 4, "level": -1 }, { "slot": 5, "level": 1, "power": "wired" }, { "slot": 6, "level": 0 },
	]
	var s := KopfStatus.pads_schwach(pads)
	check(s.map(func(p: Dictionary) -> int: return int(p.slot)) == [2, 6], "schwach und leer stehen oben, nicht voll, ladend, unbekannt oder am Kabel: %s" % str(s.map(func(p): return p.slot)))
	check(KopfStatus.pads_schwach([]).is_empty() and KopfStatus.PAD_OK == 2, "ohne Controller nichts; ab mittel gilt als gut")


func _freunde() -> void:
	print("Freunde oben: nur, wenn jemand online ist")
	check(not KopfStatus.freunde_zeigen(0, true), "angemeldet, niemand online: nichts")
	check(KopfStatus.freunde_zeigen(1, true), "einer online: Symbol mit grünem Punkt und Zahl")
	check(not KopfStatus.freunde_zeigen(5, false), "ohne Anmeldung nichts")


func _stufen() -> void:
	print("Ruhe der Leiste: Stufen")
	check(KopfRuhe.stufe(true, false, false, false) == "leiste", "Cursor oben: leiste")
	check(KopfRuhe.stufe(false, true, false, false) == "oben", "Cursor in den Unterbereichen: oben")
	check(KopfRuhe.stufe(false, false, true, false) == "inhalt", "Cursor im Inhalt: inhalt")
	check(KopfRuhe.stufe(false, false, true, true) == "tief", "Liste gerollt: tief")
	check(KopfRuhe.stufe(false, false, false, false) == "oben", "nirgends (Übergang): wie oben, nichts flackert")
	var st: Dictionary = KopfRuhe.STUFEN
	check(st.keys().filter(func(k: String) -> bool: return float(st[k].tasten) > 0.0) == ["leiste"], "LT/RT nur, wenn der Cursor oben steht")
	check(float(st.leiste.leiste) == 1.0 and float(st.oben.leiste) == 1.0 and float(st.inhalt.leiste) < 1.0 and float(st.tief.leiste) < float(st.inhalt.leiste),
			"oben ganz da, im Inhalt zurück, gerollt weiter zurück")
	check(float(st.tief.leiste) >= 0.45 and float(st.tief.status) >= 0.5, "nie weg: der Bereich bleibt aus drei Metern lesbar")


## Der Punkt unter dem Bereich (Leiste oben) und der Strich unter dem Unterbereich.
func _punkt() -> void:
	print("Reiterleiste: Punkt statt Strich")
	var strip = TabStrip.new()
	strip.style = "tab"
	add_child(strip)
	var a = NavItem.new()
	a.setup("Spiele", "", "tab", true)
	var b = NavItem.new()
	b.setup("Shop", "", "tab", false)
	strip.add_child(a)
	strip.add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	var r: Rect2 = strip._line_rect(a)
	var ir: Rect2 = a.ink_rect()
	ir.position += a.position
	check(r.size == Vector2(TabStrip.PUNKT, TabStrip.PUNKT) and TabStrip.PUNKT >= 6.0, "ein runder Punkt (Ø %.0f), keine Linie" % TabStrip.PUNKT)
	check(absf(r.get_center().x - ir.get_center().x) <= 1.0 and r.end.y <= strip.size.y, "mittig unter dem Wort, innerhalb der Leiste")
	check(strip._line_item == a and strip._line.size.x > 0.0, "der Punkt liegt unter dem gewählten Reiter")
	var mid := TabStrip.stretch(strip._line_rect(a), strip._line_rect(b), 0.4)
	check(mid.size.x > TabStrip.PUNKT * 2.0 and mid.size.y == TabStrip.PUNKT, "unterwegs ein Tropfen: die Vorderkante eilt voraus")
	var chips = TabStrip.new()
	chips.style = "chip"
	add_child(chips)
	var c = NavItem.new()
	c.setup("Zuletzt", "", "chip", true)
	chips.add_child(c)
	await get_tree().process_frame
	var cr: Rect2 = chips._line_rect(c)
	check(cr.size.y < 3.0 and absf(cr.size.x - c.ink_rect().size.x) < 1.0, "Unterbereiche: weiter der Strich so breit wie das Wort")
	strip.free()
	chips.free()


func _status() -> void:
	print("Status rechts")
	var st = KopfStatus.new().setup(false, null)
	add_child(st)
	await get_tree().process_frame
	var names: Array = st.get_children().map(func(n: Node) -> String:
		return str(n.get_class()) + ":" + (str(n.get_script().resource_path.get_file()) if n.get_script() else ""))
	check(st.get_children().size() >= 7 and st.get_child(st.get_child_count() - 1) == st.avatar and st.get_child(st.get_child_count() - 2) == st.search
			and st.get_child(st.get_child_count() - 3) == st.clock_label, "Reihenfolge: … Uhr, Lupe, Profilbild (%d Teile)" % st.get_child_count())
	check(not names.any(func(n: String) -> bool: return n.contains("profile_badges")), "keine Level-Pille oben")
	check(st.search.focus_mode == Control.FOCUS_ALL and str(st.search.get_meta("uz_key")) == "me:search" and str(st.search.get_meta("uz_hint_a")) == "Suchen",
			"Lupe wählbar, A: Suchen")
	check(st.avatar.focus_mode == Control.FOCUS_NONE and str(st.avatar.get_meta("uz_key")) == "me:avatar", "Profilbild erst wählbar, wenn kein Reiter „Profil“ da ist")
	check(st.clock_label.text.length() >= 4 and st.clock_label.text.contains(":"), "Uhr steht: %s" % st.clock_label.text)
	# Punkt für Neues.
	Toasts.unread = 0
	st.tick()
	check(not st.avatar._punkt.visible, "ohne Neues kein Punkt")
	Toasts.unread = 2
	st.tick()
	await get_tree().create_timer(U.T_ANTWORT + 0.1).timeout
	check(st.avatar._punkt.visible and st.avatar._punkt.k > 0.95, "Neues: der Punkt im Akzent am Profilbild ist da")
	check(st.avatar._punkt.position.x > KopfStatus.KNOPF * 0.6 and st.avatar._punkt.position.y < 4.0, "oben rechts am Bild")
	Toasts.unread = 0
	st.tick()
	await get_tree().create_timer(U.T_ANTWORT + 0.1).timeout
	check(not st.avatar._punkt.visible, "gelesen: weg")
	# Controller.
	st.set_pads([{ "slot": 1, "level": 3, "name": "Xbox" }, { "slot": 2, "level": 2, "name": "DualSense" }])
	check(not st.pad_box.visible and not st.hat_schwache(), "zwei volle Controller: nichts oben")
	st.set_pads([{ "slot": 1, "level": 3, "name": "Xbox" }, { "slot": 2, "level": 1, "name": "DualSense" }])
	check(st.pad_box.visible and st.hat_schwache() and st.pad_box.get_child_count() == 2, "einer schwach: Symbol und sein Akku")
	# Profilbild und Freunde.
	st.refresh("p1", {}, false)
	check(st.avatar.bild() != null and st.avatar.get_child(st.avatar.get_child_count() - 1) == st.avatar._punkt, "Profilbild gesetzt, der Punkt bleibt obenauf")
	check(st.friends_box.visible == KopfStatus.freunde_zeigen(KopfStatus.online_friends(), Social.has_steam() or DiscordChat.logged_in()),
			"Freunde nach der Regel (%s)" % str(st.friends_box.visible))
	st.refresh("p1", { "title": "To Zanarkand", "artist": "Nobuo Uematsu", "playing": true }, true)
	check(st.music_box.visible and st.music_label.text.begins_with("To Zanarkand") and st.music_label.custom_minimum_size.x <= 240.0,
			"läuft gerade: Titel, höchstens so breit wie der Platz (%s)" % st.music_label.text)
	st.refresh("p1", {}, false)
	check(not st.music_box.visible, "nichts läuft: nichts da")
	st.free()


## Die Leiste ruht: eigener kleiner Baum mit Kopf, Reitern, Unterbereichen und einer rollenden Liste.
func _ruhe() -> void:
	print("Ruhe der Leiste im Baum")
	var root := Control.new()
	root.size = Vector2(1200, 800)
	add_child(root)
	var kopf := Control.new()
	kopf.size = Vector2(1200, 60)
	root.add_child(kopf)
	var strip = TabStrip.new()
	strip.style = "tab"
	kopf.add_child(strip)
	var lt := Control.new()
	lt.set_meta("uz_bumper", true)
	strip.add_child(lt)
	var tab = NavItem.new()
	tab.setup("Spiele", "", "tab", true)
	strip.add_child(tab)
	var lupe := Button.new()
	lupe.position = Vector2(1000, 0)
	kopf.add_child(lupe)
	var status := Control.new()
	kopf.add_child(status)
	var chips := Control.new()
	chips.position = Vector2(0, 70)
	root.add_child(chips)
	var chip := Button.new()
	chips.add_child(chip)
	var inhalt := Control.new()
	inhalt.position = Vector2(0, 140)
	inhalt.size = Vector2(1200, 600)
	root.add_child(inhalt)
	var sc := ScrollContainer.new()
	sc.size = Vector2(600, 300)
	inhalt.add_child(sc)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(500, 1400)
	sc.add_child(col)
	var zeile := Button.new()
	col.add_child(zeile)
	var ruhe = KopfRuhe.new().setup(kopf, strip, status, chips, inhalt)
	root.add_child(ruhe)
	await get_tree().process_frame
	await get_tree().process_frame
	var w := U.T_ORT + 0.12
	tab.grab_focus()
	await get_tree().create_timer(w).timeout
	check(ruhe.aktuell == "leiste" and is_equal_approx(lt.modulate.a, 1.0) and is_equal_approx(strip.modulate.a, 1.0), "Cursor auf einem Reiter: alles da, LT/RT sichtbar")
	lupe.grab_focus()
	await get_tree().create_timer(w).timeout
	check(ruhe.aktuell == "leiste" and is_equal_approx(lt.modulate.a, 1.0), "Cursor auf der Lupe: wie oben")
	chip.grab_focus()
	await get_tree().create_timer(w).timeout
	check(ruhe.aktuell == "oben" and lt.modulate.a < 0.01 and is_equal_approx(strip.modulate.a, 1.0), "Unterbereiche: LT/RT weg, Reiter ganz da")
	zeile.grab_focus()
	await get_tree().create_timer(w).timeout
	var soll: Dictionary = KopfRuhe.STUFEN.inhalt
	check(ruhe.aktuell == "inhalt" and absf(strip.modulate.a - float(soll.leiste)) < 0.02 and absf(status.modulate.a - float(soll.status)) < 0.02,
			"im Inhalt: Reiter %.2f, Status %.2f" % [strip.modulate.a, status.modulate.a])
	sc.scroll_vertical = 200
	await get_tree().process_frame
	check(KopfRuhe.gerollt(zeile, inhalt), "die Liste unter dem Cursor ist gerollt")
	# Der nächste Fokus (oder das Nachsehen nach T_RAUM) nimmt die tiefe Stufe.
	ruhe.anwenden(true)
	await get_tree().create_timer(w).timeout
	soll = KopfRuhe.STUFEN.tief
	check(ruhe.aktuell == "tief" and absf(strip.modulate.a - float(soll.leiste)) < 0.02, "gerollt: die Leiste tritt weiter zurück (%.2f)" % strip.modulate.a)
	var t0 := Time.get_ticks_msec()
	tab.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	check(strip.modulate.a > float(soll.leiste) + 0.1, "zurück nach oben: schon im ersten Bild heller (%.2f nach %d ms)" % [strip.modulate.a, Time.get_ticks_msec() - t0])
	await get_tree().create_timer(U.T_ANTWORT + 0.1).timeout
	check(ruhe.aktuell == "leiste" and is_equal_approx(strip.modulate.a, 1.0) and is_equal_approx(lt.modulate.a, 1.0), "oben: ganz da im Antwort-Takt")
	root.free()


## main.gd: keine Haarlinie, keine Glocke, keine Level-Pille mehr in der Leiste; Status und Ruhe eingebaut.
func _quelle() -> void:
	print("main.gd")
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	check(not src.contains("class _Trenner") and not src.contains("bell_box") and not src.contains("_lv_pill"), "Trenner, Glocke und Level-Pille sind weg")
	check(src.contains("KopfStatus.new().setup(") and src.contains("KopfRuhe.new().setup("), "Status und Ruhe aus den eigenen Bauteilen")
	check(src.contains("g.set_meta(\"uz_bumper\", true)"), "LT/RT als Tastenhinweise der Ruhe")
	var ts := FileAccess.get_file_as_string("res://src/ui/components/tab_strip.gd")
	check(not ts.contains("h - 4.0, 22.0, 3.0"), "kein 22 × 3 Strich mehr unter dem Bereich")
