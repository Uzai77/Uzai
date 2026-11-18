extends RefCounted
## Schnellmenü (Punkt 21): Guide-Taste halten, wie das Kontrollzentrum bei Xbox und PlayStation.
## Eine schmale Leiste unten in der Mitte mit wenigen großen Kacheln – Bildschirmfoto, Clip, Mikro, Bild in Bild verschieben,
## Ruhemodus, Spiel beenden bzw. Ausschalten und der ganze Guide. Es ist der Guide selbst in klein
## (guide.gd mit start_tab QUICK): Über dem Spiel liegt er genauso, hält Emulatoren an, und B oder
## die Guide-Taste schließen ihn. Die Auswahl (ids) ist testbar.
## Auf Handhelds und Laptops im Akkubetrieb kommt „Leistung“ dazu: schaltet reihum durch die
## Energieprofile von Windows (sparsam → ausgewogen → stark), im Spiel mit Zurückstellen danach.
## Anpassen (Menü-Taste oder die schmale Kachel am Ende, auch aus den Einstellungen): Kacheln
## greifen und verschieben (A, links/rechts oder LB/RB), X blendet aus, „+“ fügt hinzu, B speichert.
## Welche Kacheln es gibt und was gespeichert wird, steht in guide_quick_wahl.gd.

const U := preload("res://src/ui/u.gd")
const QuickTile := preload("res://src/ui/components/quick_tile.gd")
const Wahl := preload("res://src/ui/components/guide_quick_wahl.gd")
const Handheld := preload("res://src/core/handheld.gd")
const PerfLive := preload("res://src/core/perf_live.gd")
const PcAkku := preload("res://src/ui/components/pc_akku.gd")
const GuidePip := preload("res://src/ui/components/guide_pip.gd")
const GuidePads := preload("res://src/ui/components/guide_pads.gd")
const MixerSheet := preload("res://src/ui/layers/mixer_sheet.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const ListItem := preload("res://src/ui/components/list_item.gd")
const PadsS := preload("res://src/core/pads.gd")
const NichtStoeren := preload("res://src/core/nicht_stoeren.gd")
const Main := preload("res://src/main.gd")

## Energieprofile, zuletzt gelesen (PerfLive.parse_plans) – für die Kachel „Leistung“.
static var plaene: Dictionary = {}
## Das nächste Schnellmenü geht gleich im Bearbeiten-Modus auf (aus den Einstellungen).
static var sofort_anpassen := false

const TILE_W := 176.0
const GAP := 14.0
const RAND := 28.0
## Breiter wird die Leiste nicht (1080 Zeilen; bei 4K gleich groß): die Kacheln teilen sich dann den Platz.
const MAX_BREITE := 1600.0
const BOTTOM := 132.0          ## Abstand der Leiste zum unteren Rand (über der Tastenleiste)


## Welche Kacheln es gerade gibt, in dieser Reihenfolge. ctx: { shot (Bildschirmfoto geht), game
## (Spiel läuft), video (Video läuft), voice (im Sprachkanal), mic (Windows-Mikrofon schaltbar),
## leistung (Handheld oder Akkubetrieb, Energieprofile umschaltbar), pip (Bild in Bild läuft),
## musik, ton, aufnahme, pads, zimmer }. wahl: eigene Auswahl (sonst aus den Einstellungen).
static func ids(ctx: Dictionary, wahl: Variant = null) -> Array:
	return Wahl.sichtbar(Wahl.auswahl() if wahl == null else Wahl.pruefen(wahl), ctx)


static func context(g: Control) -> Dictionary:
	var main: Main = g.main
	return { "shot": g._can_screenshot(), "game": Launcher.in_game, "video": Video.watching(),
		"voice": Voice.ready_() and Voice.in_channel(), "mic": (Config.is_windows() and Helper.available) or Library.demo,
		"leistung": leistung_da(), "pip": main != null and main.pip != null and main.pip.active(),
		"musik": Music.mode() != "aus", "ton": Config.is_windows() or Library.demo, "aufnahme": Capture.via_uzai(),
		"pads": not Pads.pads.is_empty(),
		"zimmer": main != null and main.room_layer() == null and not Video.watching(),
		"hoeren": bool(Music.now.get("playing", false)) or (Video.active and Video.background and not Video.paused) }


## Leistung gehört ins Schnellmenü, wo man unterwegs ist: Handheld oder Laptop ohne Netzteil.
static func leistung_da() -> bool:
	return (not Handheld.aktiv.is_empty() or PcAkku.zeigen(PcAkku.stand)) and bool(plaene.get("can_set", false))


## Energieprofile einmal lesen (beim Start auf Handhelds, sonst beim Öffnen des Schnellmenüs).
static func plaene_laden() -> void:
	plaene = await PerfLive.load_plans()


## Kachel je Kennung: [Titel, Symbol, Zustand, eingeschaltet, Hinweis A, Handlung].
static func tile(g: Control, id: String) -> Array:
	var main: Main = g.main
	match id:
		"shot":
			return ["Bildschirmfoto", "camera", "", false, "Bildschirmfoto", func() -> void: main.take_screenshot()]
		"clip":
			return ["Clip speichern", "spark", Capture.clip_state_text(), Capture.state == "puffer", "Clip speichern", func() -> void: main.save_clip()]
		"aufnahme":
			# Wie „Aufnehmen“ im Guide: längere Aufnahme, höchstens 10 Minuten.
			var rec := Capture.recording
			return ["Aufnahme" if rec else "Aufnehmen", "record", Capture.record_text() if rec else "", rec,
				"Beenden und speichern" if rec else "Aufnahme starten", func() -> void: main.toggle_record()]
		"mic":
			# Wie „Mikro“ im Guide (Mixer): Windows-Mikrofon und, wenn verbunden, Discord zusammen.
			var muted := Mixer.mic_aus()
			return ["Mikro", "mic_off" if muted else "mic", "Aus" if muted else "An", not muted, "Mikro an" if muted else "Mikro aus", func() -> void:
				await Mixer.toggle_mic()
				refill(g, "mic")]
		"ton":
			return ["Lautstärke", "volume", "", false, "Mixer", func() -> void: MixerSheet.open_for(main)]
		"musik":
			var spielt := bool(Music.now.get("playing", false))
			var hat := str(Music.now.get("title", "")) != ""
			return ["Musik", "pause" if spielt else "play", ("Läuft" if spielt else "Pausiert") if hat else "", spielt and hat,
				"Pause" if spielt else "Abspielen", func() -> void:
					Music.play_pause()
					await g.get_tree().create_timer(0.4).timeout
					if is_instance_valid(g) and g.is_inside_tree():
						refill(g, "musik")]
		"weiter":
			return ["Nächster Titel", "next", "", false, "Nächster Titel", func() -> void: Music.next()]
		"leistung":
			var act := str(plaene.get("active", ""))
			var wn := ""
			for p in plaene.get("plans", []):
				if str(p.get("id", "")) == act:
					wn = str(p.get("name", ""))
			return ["Leistung", "speed", str(PerfLive.plan_name(act, wn).text) if act != "" else "", false, "Umschalten", func() -> void: await _naechstes(g)]
		"pip":
			# Bild in Bild gleich verschieben: linker Stick schiebt, LT/RT Größe, A lässt es dort.
			return ["Bild verschieben", "move", "", false, "Verschieben", func() -> void:
				GuidePip.sofort_bewegen = true
				g.close()
				main.toggle_guide("pip")]
		"freunde":
			# Der Guide auf dem Reiter Freunde (wie „Guide“, nur gleich dort).
			return ["Freunde", "friends", "", false, "Freunde", func() -> void:
				g.close()
				main.toggle_guide("freunde")]
		"pads":
			var pads: Array = Pads.pads
			var low := pads.any(func(p) -> bool: return g.pad_low(p))
			return ["Controller", "controller", "Akku schwach" if low else (PadsS.battery_text(pads[0]) if pads.size() == 1 else ""), false,
				"Controller", func() -> void:
					if Pads.pads.size() == 1:
						GuidePads.open_pad(main, Pads.pads[0])
					else:
						GuidePads.open_all(main)]
		"mitteilungen":
			var n := Toasts.unread
			return ["Mitteilungen", "bell", (TranslationServer.translate("%d neu") % n) if n > 0 else "", false, "Öffnen",
				func() -> void: main.open_notifications()]
		"aufnahmen":
			return ["Aufnahmen", "image", "", false, "Öffnen", func() -> void: main.open_captures()]
		"zimmer":
			# Im Spiel wie im Guide (der Fernseher zeigt das Spiel), sonst erst zu und dann hinein.
			return ["Zimmer", "home", "", false, "Betreten", func() -> void:
				if not Launcher.in_game:
					g.close()
				main.open_room()]
		"einstellungen":
			return ["Einstellungen", "settings", "", false, "Öffnen", func() -> void:
				g.close()
				main.goto("settings")]
		"rest":
			return ["Ruhemodus", "moon", "", false, "Ruhemodus", func() -> void:
				var rest: Node = main.rest
				if rest:
					rest.enter("schnellmenü")
				else:
					g.close()]
		"schlaf":
			# A schaltet weiter: 15, 30, 60, 90 Min., nach diesem Video, aus (src/core/schlaf_timer.gd).
			var st: Node = main.rest.schlaf if main and main.rest != null else null
			var on: bool = st != null and st.an()
			return ["Schlaf-Timer", "clock", st.text() if st else "", on, "Ändern" if on else "Stellen", func() -> void:
				if st:
					st.weiter()
					refill(g, "schlaf")]
		"ruhe":
			# Pop-ups von Freunden, Discord und Shop nur still in die Mitteilungen (src/core/nicht_stoeren.gd).
			return ["Nicht stören", "bell", NichtStoeren.zustand(), NichtStoeren.an, "Ausschalten" if NichtStoeren.an else "Einschalten", func() -> void:
				NichtStoeren.umschalten()
				refill(g, "ruhe")]
		"hoeren":
			# Bild dunkel, Musik läuft weiter; jede Taste weckt (rest.gd, enter mit hoeren).
			return ["Nur hören", "headset", "", false, "Bild dunkel", func() -> void:
				var rest: Node = main.rest
				if rest:
					rest.enter("nur hören", { "hoeren": true })
				else:
					g.close()]
		"beenden":
			return tile(g, Wahl.beenden_id(context(g)))
		"quit":
			if Launcher.is_app(Launcher.current):
				return ["Sofort beenden" if Launcher.quit_sofort() else "App schließen", "close", "", false, "Schließen", func() -> void:
					g.close()
					Launcher.quit_game(Launcher.quitting)]
			# Beenden läuft schon, hängt oder ging nicht: „Sofort beenden“ (guide_spiel.gd _ask_quit).
			return ["Sofort beenden" if Launcher.quit_sofort() else "Spiel beenden", "close", "", false, "Beenden", g._ask_quit]
		"video_stop":
			return ["Video beenden", "close", "", false, "Beenden", func() -> void:
				g.close()
				Video.stop()]
		"power":
			return ["Ausschalten", "power", "", false, "Ausschalten", func() -> void: main.open_power()]
		"guide":
			return ["Guide", "grid", "", false, "Guide öffnen", func() -> void:
				g.close()
				main.toggle_guide()]
	return []


## Nächstes Energieprofil (Kachel „Leistung“). Im Spiel stellt Uzai danach zurück (PerfLive).
static func _naechstes(g: Control) -> void:
	var nxt := Handheld.naechstes_profil(plaene.get("plans", []), str(plaene.get("active", "")))
	if nxt == "":
		return
	var ok := false
	if Launcher.in_game:
		ok = await PerfLive.switch_plan(str(plaene.get("active", "")), nxt)
	else:
		ok = await PerfLive.set_plan(nxt)
	if not ok:
		Toasts.show_toast("Energieprofil ließ sich nicht umstellen",
				"Windows erlaubt es gerade nicht. Unter Einstellungen → System → Windows → Energie noch einmal versuchen.", "warning", { "ms": 5000 })
		return
	plaene["active"] = nxt
	if is_instance_valid(g):
		refill(g, "leistung")


## Eine Zeile für die Einstellungen: „Standard“ oder wie viele Kacheln gewählt sind.
static func zusammenfassung() -> String:
	var raw: Variant = Config.get_value("system.quick_tiles", [])
	if not (raw is Array) or (raw as Array).is_empty():
		return "Standard"
	return U.plural(Wahl.auswahl().size(), "Kachel", "Kacheln")


## Aus den Einstellungen: das Schnellmenü gleich zum Anpassen öffnen; B führt dorthin zurück.
static func oeffnen_zum_anpassen(main: Main) -> Control:
	sofort_anpassen = true
	main.toggle_guide("schnell")      # guide_basis.QUICK
	var g: Variant = main._guide
	if not (g is Control) or not is_instance_valid(g):
		sofort_anpassen = false
		return null
	(g as Control).set_meta("uz_quick_nur_anpassen", true)
	return g


## Breite der Leiste für n Kacheln und s schmale (Anpassen, Hinzufügen).
static func breite(n: int, s := 1) -> float:
	var w := n * TILE_W + s * QuickTile.SCHMAL_W + maxi(n + s - 1, 0) * GAP + 2 * RAND
	return minf(w, MAX_BREITE)


## Aufbau statt der großen Karte: Leiste unten, darin Kopfzeile und die Kacheln.
static func build(g: Control) -> void:
	# Über dem Spiel bleibt es gut zu sehen; über Uzai tritt die Startseite deutlich zurück.
	g.dim = 0.34 if Launcher.in_game else 0.55
	g._scrim.color = Color(UzTheme.col("bg"), g.dim)
	g.set_meta("uz_hints_center", true)
	g.set_meta("uz_silent", true)
	var w := breite(ids(context(g)).size())
	var panel := PanelContainer.new()
	# Fast deckend: die Kacheln sind aus Glas, dahinter lägen sonst Cover und Titel.
	var sb := UzTheme.solid(0.97, 30)
	sb.content_margin_left = RAND
	sb.content_margin_right = RAND
	sb.content_margin_top = 22
	sb.content_margin_bottom = 26
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 48
	sb.shadow_offset = Vector2(0, 18)
	panel.add_theme_stylebox_override("panel", sb)
	UzTheme.kernlicht(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -BOTTOM
	panel.offset_top = -BOTTOM
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(panel)
	g.set_meta("uz_quick_panel", panel)
	var col := U.vbox(16)
	panel.add_child(col)
	var head := U.hbox(12)
	var t := U.label("Schnellmenü", "l", "text", "ui_bold")
	head.add_child(t)
	g.set_meta("uz_quick_titel", t)
	head.add_child(U.spacer())
	var right := U.label(_ort_text(), "s", "muted", "medium")
	right.clip_text = true
	right.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.custom_minimum_size.x = minf(w - 280.0, 520.0)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(right)
	g.set_meta("uz_quick_rechts", right)
	col.add_child(head)
	var row := U.hbox(int(GAP))
	row.set_meta("uz_group", "guide:schnell")
	g.set_meta("uz_quick_row", row)
	col.add_child(row)
	if sofort_anpassen:
		sofort_anpassen = false
		g.set_meta("uz_quick_edit", Wahl.stand(Wahl.auswahl()))
		_kopf(g)
		_breite_setzen(g, false)
	_hinweise(g)
	_fill_row(g, row, "")
	_intro(panel, row)
	if plaene.is_empty() and (not Handheld.aktiv.is_empty() or PcAkku.zeigen(PcAkku.stand)):
		_spaeter(g)


## Rechts im Kopf: was läuft und die Uhr.
static func _ort_text() -> String:
	var where := Library.display_title(Launcher.current) if Launcher.in_game else (str(Video.video.get("title", "")) if Video.watching() else "")
	return where + ("  ·  " if where != "" else "") + U.clock()


## Tastenhinweise je Modus. Y macht wie im Guide ein Bildschirmfoto; als Hinweis stünde es doppelt
## (die erste Kachel). Beim Anpassen: LB/RB verschieben, B speichert.
static func _hinweise(g: Control) -> void:
	var s: Variant = g.get_meta("uz_quick_edit") if g.has_meta("uz_quick_edit") else null
	if s is Dictionary:
		var griff := bool((s as Dictionary).get("griff", false))
		g.set_meta("uz_hint_b", "Ablegen" if griff else "Fertig")
		g.set_meta("uz_hints", [["lb", ""], ["rb", "Verschieben"]])
	else:
		g.set_meta("uz_hint_b", "Schließen")
		g.set_meta("uz_hints", [["menu", "Anpassen"]])
	var f := Nav.focused()
	if f and g.is_ancestor_of(f):
		Nav.focus_moved.emit(f)


## Energieprofile kamen erst nach dem Öffnen: „Leistung“ nachtragen, die Auswahl bleibt.
static func _spaeter(g: Control) -> void:
	await plaene_laden()
	if not is_instance_valid(g) or not g.is_inside_tree() or not leistung_da():
		return
	var f := Nav.focused()
	refill(g, _key_of(f) if f else "")


static func _key_of(c: Control) -> String:
	var k := str(c.get_meta("uz_key", ""))
	return k.substr(3) if k.begins_with("qm:") or k.begins_with("qe:") else ""


## Kacheln neu (Mikro umgeschaltet, Anpassen), die Auswahl bleibt auf key.
static func refill(g: Control, key: String) -> void:
	var row: Variant = g.get_meta("uz_quick_row", null)
	if not (row is Control) or not is_instance_valid(row):
		return
	U.clear(row)
	_fill_row(g, row, key)
	await g.get_tree().process_frame
	if not is_instance_valid(row):
		return
	for c in (row as Control).get_children():
		if _key_of(c as Control) == key:
			Nav.focus(c, true)
			return
	# Gesuchte Kachel gibt es nicht (mehr): die erste der Reihe, nie ohne Auswahl.
	Nav.focus(Nav.default_in(row as Control), true)


static func _fill_row(g: Control, row: Control, focus_key: String) -> void:
	if bearbeitet(g):
		_fill_edit(g, row, focus_key)
		return
	var first := true
	for id in ids(context(g)):
		var d := tile(g, str(id))
		if d.is_empty():
			continue
		# Breite gibt die Leiste vor (je TILE_W), die Kacheln teilen sie gleichmäßig.
		var q = QuickTile.new().setup(str(d[0]), str(d[1]), str(d[2]), bool(d[3]))
		q.set_meta("uz_key", "qm:" + str(id))
		q.set_meta("uz_hint_a", str(d[4]))
		q.activated.connect(d[5])
		if (focus_key == "" and first) or focus_key == str(id):
			q.set_meta("uz_default", true)
		first = false
		row.add_child(q)
	# Zuletzt, schmal und leise: Anpassen (wie die Menü-Taste).
	var a = QuickTile.new().setup("Anpassen", "edit")
	a.schmal = true
	a.set_meta("uz_key", "qm:anpassen")
	a.set_meta("uz_hint_a", "Anpassen")
	a.activated.connect(func() -> void: anpassen(g))
	# Gewählt sagt sie es selbst (A): „Menü Anpassen“ stünde daneben doppelt. Die Tastenleiste hat
	# beim Fokuswechsel schon gelesen – danach noch einmal anstoßen.
	a.focus_entered.connect(func() -> void:
		g.set_meta("uz_hints", [])
		Nav.focus_moved.emit.call_deferred(a))
	a.focus_exited.connect(func() -> void:
		if not bearbeitet(g):
			g.set_meta("uz_hints", [["menu", "Anpassen"]])
			var f := Nav.focused()
			if f:
				Nav.focus_moved.emit.call_deferred(f))
	if focus_key == "anpassen":
		a.set_meta("uz_default", true)
	row.add_child(a)


# --- Anpassen ------------------------------------------------------------------------------------

static func bearbeitet(g: Control) -> bool:
	return g.has_meta("uz_quick_edit") and g.get_meta("uz_quick_edit") is Dictionary


static func _stand(g: Control) -> Dictionary:
	return g.get_meta("uz_quick_edit", {})


## In den Bearbeiten-Modus: alle gewählten Kacheln (auch die gerade nicht da sind), dahinter „+“.
static func anpassen(g: Control) -> void:
	if bearbeitet(g):
		return
	var f := Nav.focused()
	var key := _key_of(f) if f and g.is_ancestor_of(f) else ""
	# Die Kachel heißt im Menü nach der Lage (Spiel beenden …), gespeichert ist sie als „beenden“.
	if key in ["quit", "video_stop", "power"]:
		key = "beenden"
	g.set_meta("uz_quick_edit", Wahl.stand(Wahl.auswahl()))
	Sfx.play("open")
	_umbauen(g, key if key != "anpassen" else "")


## Fertig (B, Menü-Taste): speichern und zurück ins Schnellmenü – aus den Einstellungen gleich zu.
static func fertig(g: Control) -> void:
	if not bearbeitet(g):
		return
	Wahl.speichern(Wahl.ergebnis(_stand(g)))
	g.remove_meta("uz_quick_edit")
	Sfx.play("select")
	if g.has_meta("uz_quick_nur_anpassen"):
		g.close()
		return
	_umbauen(g, "anpassen")


## Kopf, Breite, Hinweise und Kacheln für den Modus neu; die Kacheln blenden gestaffelt ein.
static func _umbauen(g: Control, key: String) -> void:
	_kopf(g)
	_hinweise(g)
	_breite_setzen(g, true)
	var row: Variant = g.get_meta("uz_quick_row", null)
	if not (row is Control) or not is_instance_valid(row):
		return
	refill(g, key)
	var i := 0
	for c: Control in (row as Control).get_children():
		c.modulate.a = 0.0
		U.ankommen(c, U.T_ORT, "uz_quick_ein").tween_property(c, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE + U.staffel(i))
		i += 1


static func _kopf(g: Control) -> void:
	var t: Variant = g.get_meta("uz_quick_titel", null)
	var r: Variant = g.get_meta("uz_quick_rechts", null)
	var edit := bearbeitet(g)
	if t is Label and is_instance_valid(t):
		(t as Label).text = "Schnellmenü anpassen" if edit else "Schnellmenü"
	if r is Label and is_instance_valid(r):
		(r as Label).text = (TranslationServer.translate("%d von %d") % [Wahl.ergebnis(_stand(g)).size(), Wahl.MAX]) if edit else _ort_text()


## Die Leiste wächst bzw. schrumpft auf die Breite für ihre Kacheln.
static func _breite_setzen(g: Control, weich: bool) -> void:
	var panel: Variant = g.get_meta("uz_quick_panel", null)
	if not (panel is Control) or not is_instance_valid(panel):
		return
	var p := panel as Control
	var w := breite(_stand(g).liste.size()) if bearbeitet(g) else breite(ids(context(g)).size())
	if not weich:
		p.offset_left = -w * 0.5
		p.offset_right = w * 0.5
		return
	var tw := U.ankommen(p, U.T_ORT, "uz_quick_breite").set_parallel(true)
	tw.tween_property(p, "offset_left", -w * 0.5, U.T_ORT)
	tw.tween_property(p, "offset_right", w * 0.5, U.T_ORT)


static func _fill_edit(g: Control, row: Control, focus_key: String) -> void:
	var s := _stand(g)
	var ctx := context(g)
	var first := true
	for id: String in s.liste:
		var da := Wahl.da(id, ctx)
		var d := tile(g, id) if da else []
		var q = QuickTile.new().setup(str(d[0]) if da else Wahl.name_of(id), str(d[1]) if da else Wahl.icon_of(id),
			str(d[2]) if da else Wahl.wann(id), bool(d[3]) if da else false)
		q.gedimmt = not da
		q.set_meta("uz_key", "qe:" + id)
		q.set_meta("uz_hint_a", "Greifen")
		q.set_meta("uz_on_x", func() -> void: _umschalten(g, q))
		_aus_zeigen(q, (s.aus as Array).has(id), false)
		q.activated.connect(func() -> void: _greifen(g, q, not q.gegriffen))
		q.focus_exited.connect(func() -> void:
			if q.gegriffen:
				_greifen(g, q, false))
		if (focus_key == "" and first) or focus_key == id:
			q.set_meta("uz_default", true)
		first = false
		row.add_child(q)
	var neu = QuickTile.new().setup("Hinzufügen", "plus")
	neu.schmal = true
	neu.leer = true
	neu.set_meta("uz_key", "qe:neu")
	neu.set_meta("uz_hint_a", "Hinzufügen")
	neu.activated.connect(func() -> void: _hinzufuegen_liste(g))
	if focus_key == "neu":
		neu.set_meta("uz_default", true)
	row.add_child(neu)


## Ausgeblendet zeigen: blass, „Ausgeblendet“ statt des Zustands, X blendet wieder ein.
static func _aus_zeigen(q: Control, aus: bool, weich := true) -> void:
	q.call("set_aus", aus, weich)
	if str(q.get_meta("uz_key", "")) != "qe:" + Wahl.FEST:
		q.set_meta("uz_hint_x", "Einblenden" if aus else "Ausblenden")


## X: aus- bzw. einblenden. Der Guide bleibt (sonst käme man nicht mehr hinein).
static func _umschalten(g: Control, q: Control) -> void:
	var id := _key_of(q)
	var s := _stand(g)
	var neu := Wahl.umschalten(s, id)
	if neu == s:
		Sfx.play("bump", 1.0, q)
		if id == Wahl.FEST:
			Toasts.show_toast("Der Guide bleibt immer", "So kommst du jederzeit an alles.", "grid", { "ms": 2200, "quiet": true })
		elif (s.aus as Array).has(id):
			Toasts.show_toast("Die Leiste ist voll", "Erst eine andere Kachel ausblenden.", "info", { "ms": 2200, "quiet": true })
		return
	neu["griff"] = false
	g.set_meta("uz_quick_edit", neu)
	var aus := (neu.aus as Array).has(id)
	Sfx.play("toggle_off" if aus else "toggle_on", 1.0, q)
	_aus_zeigen(q, aus)
	_kopf(g)
	Nav.focus_moved.emit(q)


## A: Kachel greifen (sie hebt sich ab, links/rechts trägt sie) bzw. wieder ablegen.
static func _greifen(g: Control, q: Control, an: bool) -> void:
	if not is_instance_valid(q) or bool(q.get("gegriffen")) == an:
		return
	q.call("set_griff", an)
	q.set_meta("uz_hint_a", "Ablegen" if an else "Greifen")
	var s := _stand(g)
	s["griff"] = an
	Sfx.play("toggle_on" if an else "toggle_off", 1.0, q)
	_hinweise(g)


## Gewählte Kachel um d Plätze tragen (LB/RB, gegriffen links/rechts). Die beiden Kacheln gleiten
## von ihrem alten Platz an den neuen, statt zu springen.
static func _tragen(g: Control, d: int) -> void:
	var row: Variant = g.get_meta("uz_quick_row", null)
	var q := Nav.focused()
	if not (row is Container) or q == null or q.get_parent() != row or not str(q.get_meta("uz_key", "")).begins_with("qe:"):
		return
	var id := _key_of(q)
	var s := _stand(g)
	var i := (s.liste as Array).find(id)
	if i < 0:
		Sfx.play("bump", 1.0, q)
		return
	var neu := Wahl.verschieben(s.liste, i, d)
	if neu == s.liste:
		Sfx.play("bump", 1.0, q)
		return
	var box := row as Container
	var vorher := {}
	for c in box.get_children():
		vorher[c] = (c as Control).position.x
	s["liste"] = neu
	box.move_child(q, neu.find(id))
	box.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in box.get_children():
		var dx: float = float(vorher.get(c, (c as Control).position.x)) - (c as Control).position.x
		if absf(dx) > 0.5:
			c.call("gleiten", dx)
	Sfx.play("tick", 1.0 + 0.06 * float(d), q)


## „+“: Liste der Kacheln, die noch fehlen, darunter „Standard“. A fügt hinzu.
static func _hinzufuegen_liste(g: Control) -> void:
	var s := _stand(g)
	if Wahl.frei(s) <= 0:
		Sfx.play("bump")
		Toasts.show_toast("Die Leiste ist voll", "Erst eine Kachel ausblenden (X).", "info", { "ms": 2200, "quiet": true })
		return
	var sh = Sheet.new()
	sh.setup("Kachel hinzufügen", TranslationServer.translate("Noch %d frei") % Wahl.frei(s), 640)
	sh.set_meta("uz_key", "guide:quick_neu")
	sh.set_meta("uz_hints_center", true)
	sh.fill_func = func(sheet) -> void:
		var first := true
		for id: String in Wahl.verfuegbar(_stand(g)):
			var r = ListItem.new()
			var w := Wahl.wann(id)
			r.setup(Wahl.name_of(id), w if w != "" else "Immer da", "")
			r.icon_name = Wahl.icon_of(id)
			r.sub_color = "faint"
			r.set_meta("uz_key", "neu:" + id)
			r.set_meta("uz_hint_a", "Hinzufügen")
			if first:
				r.set_meta("uz_default", true)
				first = false
			r.activated.connect(func() -> void:
				sheet.close()
				_hinzufuegen(g, id))
			sheet.add_row(r)
		if Wahl.ergebnis(_stand(g)) != Wahl.STANDARD:
			sheet.add_gap(10)
			var rs = ListItem.new()
			rs.setup("Standard", "Die Kacheln von Anfang an", "")
			rs.icon_name = "refresh"
			rs.set_meta("uz_key", "neu:standard")
			rs.set_meta("uz_hint_a", "Zurücksetzen")
			rs.activated.connect(func() -> void:
				sheet.close()
				_standard(g))
			sheet.add_row(rs)
		sheet.add_gap(8)
	g.main.open_layer(sh)


static func _hinzufuegen(g: Control, id: String) -> void:
	if not is_instance_valid(g) or not bearbeitet(g):
		return
	var neu := Wahl.hinzufuegen(_stand(g), id)
	if neu == _stand(g):
		return
	g.set_meta("uz_quick_edit", neu)
	Sfx.play("toggle_on")
	_kopf(g)
	_breite_setzen(g, true)
	_neu_mit(g, id)


static func _standard(g: Control) -> void:
	if not is_instance_valid(g) or not bearbeitet(g):
		return
	g.set_meta("uz_quick_edit", Wahl.stand(Wahl.STANDARD))
	Sfx.play("toggle_on")
	_umbauen(g, "")


## Reihe neu, die neue Kachel id wächst sanft herein (Fläche zuerst) und ist gewählt.
static func _neu_mit(g: Control, id: String) -> void:
	var row: Variant = g.get_meta("uz_quick_row", null)
	if not (row is Control) or not is_instance_valid(row):
		return
	await refill(g, id)
	if not is_instance_valid(row):
		return
	for c: Control in (row as Control).get_children():
		if _key_of(c) == id:
			c.modulate.a = 0.0
			U.ankommen(c, U.T_ORT, "uz_quick_ein").tween_property(c, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE)


## Aufgehen (Ebene, T_RAUM): die Leiste steigt W_ORT von unten auf und blendet in T_ORT ein, die
## Kacheln folgen nach der Fläche (NACH_FLAECHE) gestaffelt (U.staffel).
static func _intro(panel: Control, row: Control) -> void:
	panel.modulate.a = 0.0
	var top0 := panel.offset_top
	var bot0 := panel.offset_bottom
	var w := U.weg_px(U.W_ORT)
	var tw := U.ankommen(panel, U.T_RAUM, "uz_quick").set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, U.T_ORT)
	tw.tween_property(panel, "offset_top", top0, U.T_RAUM).from(top0 + w)
	tw.tween_property(panel, "offset_bottom", bot0, U.T_RAUM).from(bot0 + w)
	var i := 0
	for c: Control in row.get_children():
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE + U.staffel(i))
		i += 1
	U.aufglanz(panel, U.NACH_FLAECHE)


## Schließen: die Leiste sinkt W_ANSTOSS ab, während die Ebene in T_WEG ausblendet („Gehen“).
## Ging es beim Anpassen zu (Guide-Taste), bleibt das Angepasste gespeichert.
static func leave(g: Control) -> void:
	if bearbeitet(g):
		Wahl.speichern(Wahl.ergebnis(_stand(g)))
		g.remove_meta("uz_quick_edit")
	var panel: Variant = g.get_meta("uz_quick_panel", null)
	if not (panel is Control) or not is_instance_valid(panel):
		return
	var p := panel as Control
	var w := U.weg_px(U.W_ANSTOSS)
	var tw := U.weg(p, "uz_quick").set_parallel(true)
	tw.tween_property(p, "offset_top", p.offset_top + w, U.T_WEG)
	tw.tween_property(p, "offset_bottom", p.offset_bottom + w, U.T_WEG)


## B beim Anpassen: eine gegriffene Kachel ablegen, sonst fertig (speichert). true = erledigt.
static func command(g: Control, cmd: String) -> bool:
	if cmd != "b" or not bearbeitet(g):
		return false
	var f := Nav.focused()
	if bool(_stand(g).get("griff", false)) and f and f.has_method("set_griff"):
		_greifen(g, f, false)
		return true
	fertig(g)
	return true


## Richtungen beim Anpassen: Eine gegriffene Kachel wandert links/rechts mit, hoch/runter ruhen.
static func nav_dir(g: Control, dir: String) -> bool:
	if not bearbeitet(g) or not bool(_stand(g).get("griff", false)):
		return false
	if dir == "left" or dir == "right":
		_tragen(g, -1 if dir == "left" else 1)
	return true


## Tasten im Schnellmenü: Y macht wie im Guide ein Bildschirmfoto; Reiter und Lautstärke gibt es
## hier nicht. Die Menü-Taste passt an bzw. ist fertig, LB/RB verschieben beim Anpassen.
## Die Guide-Taste schließt über main (doppelte Meldungen, siehe main.toggle_guide).
static func handle(g: Control, cmd: String) -> bool:
	var edit := bearbeitet(g)
	match cmd:
		"menu":
			if edit:
				fertig(g)
			else:
				anpassen(g)
			return true
		"lb", "rb":
			if edit:
				_tragen(g, -1 if cmd == "lb" else 1)
			return true
		"y":
			if not edit and g._can_screenshot():
				Sfx.play("select")
				g.main.take_screenshot()
			return true
		"guide":
			return false
		"lt", "rt", "x":
			return true
	return false
