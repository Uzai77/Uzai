extends "res://src/room/zimmer_regal.gd"
## „Dein Zimmer“ (Punkt 131, Stufe 1): dein Uzai als begehbares Zimmer – eine andere Art, die
## Startseite zu zeigen (docs/AUFBAU.md). Das Zimmer selbst braucht kein Netz; Besuch von Freunden (Zimmer
## online) kommt über freundestest.gd dazu (_online_bild, besuch_an) und ändert hier nie etwas.
##
## Bedienung mit dem Controller:
##   Modi        oben die Modus-Leiste (modus_ui.gd): Leben · Bauen · Foto, die View-Taste schaltet
##               reihum (Maus: Klick aufs Wort).
##   Leben       linker Stick (Steuerkreuz) laufen, rechter Stick umsehen, LB/RB drehen,
##               A benutzen, was vor dir steht (auch: Haustier streicheln), Y Aktionen am Möbel
##               (Kontextmenü direkt daneben, kontext_ui.gd), X Ich-Ansicht → über die Schulter →
##               von oben, RT Emotes, Menü Zimmer (Figur, Haustier, Teilen, Online, Mehr), B zur
##               klassischen Startseite. Blick aufs Regal: das Spiel im Blick ist gewählt, A spielt.
##               Ego-Bewegung wie in Source/HL2 (bewegung.gd): Gehen 2,4 m/s, Rennen 4 m/s (Shift,
##               linken Stick drücken), Springen (Leertaste; A, wo nichts zu tun ist), Ducken (Strg
##               halten, rechten Stick drücken), Stufen bis 0,34 m, an Möbeln entlang gleiten. Maus
##               nach Klick ins Zimmer roh 1:1, Stick linear; beim Blick nach unten sind Beine und
##               Füße da. Kamera und Bild im Zimmer-Menü.
##   Figur       deine Figur und dein Haustier (src/room/figur/): Jackenständer bzw. Körbchen mit A
##               oder Menü › Figur und Haustier öffnet den Editor (am Jackenständer tritt die Kamera
##               erst vor deine Figur).
##   Ansehen     Regal, Schrank, Plattenregal durchsehen (Aktionen › Regal durchsehen): Steuerkreuz
##               wählt, A spielt bzw. legt auf.
##   Einräumen   Spieleregale stehen zuerst leer. A am leeren Regal, Y › Spiele einräumen, Menü beim
##               Durchsehen oder Bauen › Y: das Raster deiner Bibliothek mit Covern, A räumt ein bzw.
##               aus, B fertig; Reihenfolge beim Durchsehen mit LB/RB (zimmer_einrichten.gd).
##   Bauen       direkt im Raum (zimmer_einrichten.gd): was du ansiehst, ist gewählt; A hebt hoch
##               bzw. setzt ab, LB/RB drehen, Y Aktionen am Möbel (beim Tragen: Farbe), X rückgängig
##               (beim Tragen: wegräumen), auf leerem Boden A Katalog und Y Boden, über den Rand
##               hinaus die Wand. Unten das Bau-Menü (katalog_ui.gd): Raum-Bereiche und Möbel nach
##               Zweck als Zeichen, darüber große Kacheln; die Wahl steht als Probe im Zimmer, A
##               übernimmt. Maus: Feld unter dem Zeiger, Klick wie A.
##   Hinweise    im Bild statt als Leiste (tasten_ui.gd): eine ruhige Tastenzeile wie überall, nur
##               was gerade geht; was A tut, steht am Schild beim Ziel. Beim Laufen blenden sie aus.
##   Anpassen    Menü (Zimmer) bzw. Y auf einem Möbel: Seitenleiste (anpassen_ui.gd) – Wände,
##               Boden, Decke, Fenster, Tür, Größe, Licht, Stimmungen, Vorlagen, Hüllen, eigene
##               Möbel; je Möbel Farbe, Material, Muster, Größe, Beine, Griffe, Licht; Regale
##               als Tafel mit Hüllen (regal_tafel.gd).
##               Alles wirkt sofort und weich, X macht rückgängig, B zurück.
##   Stimmung    LT im Zimmer: Rad mit den Licht-Stimmungen, beim Wählen schon zu sehen.
##   Baukasten   eigene Möbel aus Bauteilen (baukasten.gd), danach im Katalog unter „Eigene“.
##
## Spiel aus dem Regal → in die Konsole → der Fernseher schaltet sich ein, die Kamera setzt sich
## davor → Start über den bestehenden Launcher (main.launch) → ist das Spielfenster da, fährt die
## Kamera in den Bildschirm, und das Spiel liegt randlos vorn, fokussiert (fernsehspiel.gd). Das Zimmer
## wartet unsichtbar dahinter (ruhen). Die Guide-Taste fährt sofort wieder heraus an deinen Platz (ohne
## Guide), das Spiel läuft im Fernseher weiter; erst der nächste Druck öffnet den Guide. A am Fernseher
## (oder Guide › Zum Spiel) fährt wieder hinein. Liegt eine andere Ebene darüber (Auswahl, Guide,
## Spielseite), steht das Bild still (eingefroren).
##
## Stufe 2 – Fernseher zeigt das laufende Spiel: Läuft ein Spiel, öffnet Guide › „Dein Zimmer“ das
## Zimmer über dem Spiel. Die Kamera kommt aus dem Fernseher heraus (aus_dem_spiel), der Fernseher
## zeigt das Spiel (spielbild.gd: sparsam, nur im Speicher), es läuft weiter. A am Fernseher fährt
## hinein und holt das Spiel nach vorn (zum_spiel) – nur auf deinen Wunsch.
##
## Stufe 3 – Zimmer teilen (zimmer_teilen.gd): Menü › Teilen: als Datei oder QR-Code (teilen_ui.gd),
## Zimmer-Datei bzw. -Code einführen mit Vorschau und Rückfrage (einfuehren_ui.gd), Fotomodus für
## einen Schnappschuss mit eigener Kamera und Pose (Bilder\Uzai, dezentes Uzai-Zeichen).

const Platten := preload("res://src/room/plattenspieler.gd")

const Bew := preload("res://src/room/bewegung.gd")
const FT := preload("res://src/room/freundestest.gd")
const Besucher := preload("res://src/room/besucher.gd")

const TEMPO := Bew.GEHEN       ## Gehen: Meter je Sekunde (HL2 190 u/s im Zimmer-Maßstab)
const TEMPO_RENNEN := Bew.RENNEN   ## Rennen (Shift, linken Stick drücken; HL2-Sprint 320 u/s)
const SPRUNG := Bew.SPRUNG     ## Absprung (m/s): 0,4 m hoch wie in HL2
const SCHWERE := Bew.SCHWERE
const DREH := 3.6652           ## Umsehen mit dem Stick: 210°/s waagrecht (cl_yawspeed) × Empfindlichkeit
const DREH_HOCH := 3.927       ## 225°/s senkrecht (cl_pitchspeed)
const MAUS := 0.0022           ## Umsehen mit der Maus: Bogenmaß je Pixel (× Empfindlichkeit Maus)
const NEIGUNG := 1.5533        ## Blick nach oben und unten höchstens 89° (wie Source)
const AUGEN_DUCK := 1.0        ## Augenhöhe geduckt
## Ego-Kamera wie in Source: Die Maus dreht roh im Eingabe-Ereignis (Pixel × Empfindlichkeit – kein
## Glätten, keine Beschleunigung, kein Nachziehen), der rechte Stick linear mit kleiner runder Totzone
## und fester Drehgeschwindigkeit, ohne Trägheit. Die Kamera folgt dem Blick in jedem Bild; Laufen
## rechnet im Physik-Takt (bewegung.gd), gezeigt wird zwischen den letzten zwei Takten (bei 144 Hz
## ruckelt nichts). Laufen: runde Totzone gegen Stick-Drift, außen ein kleiner Rand (abgenutzte
## Sticks erreichen 1,0 kaum), linear. Einstellungen: Zimmer-Menü › Kamera und Bild.
const TOTZONE := 0.15
const TOTZONE_BLICK := 0.1
const RAND := 0.05
const KURVE_BLICK := 1.0

## Sitzung: wo du zuletzt standest (beim Wiederkommen nach einem Spiel).
static var _letzte := {}

var _vel := Vector3.ZERO        ## Geschwindigkeit (m/s) für Figur und Kopfwippen
var _hoehe := 0.0               ## Füße über dem Boden (Sprung, auf einem Möbel), wie gezeigt
var _k := Bew.neu(Vector3.ZERO) ## der Körper im Physik-Takt (bewegung.gd)
var _k_alt := Vector3.ZERO      ## seine Lage im Takt davor (gezeigt wird dazwischen)
var _duck_alt := 0.0
var _duck_senken := 0.0         ## so viel tiefer sind die Augen geduckt (gezeigt)
var _pos_gezeigt := Vector3(INF, 0, INF)
var _sprung_puls := false       ## Springen gedrückt (der nächste Takt springt)
var _duck_um := false           ## Ducken umgeschaltet (rechten Stick drücken)
var _rennen := false
var _wipp := 0.0                ## Phase des Kopfwippens
var _direkt := 0.0              ## Ich-Ansicht: 1 = Kamera sitzt ohne Nachlauf in den Augen


var _hud: Control
var _punkt: Control
var _uhr_min := -1
var _ps := {}                  ## Plattenspieler: Drehzahl, Teller, Tonarm (plattenspieler.gd)
var _ps_art := "~"             ## Cover, das auf der Hülle liegt (art aus Music.now)
var _ps_knoten := 0            ## Knoten, auf den es gelegt wurde (nach Umbauen neu)
var _ps_tex: Texture2D
var _ps_farbe := Color("#d9cdb6")
var _ruhe := 0.0               ## so lange keine Bewegung (Hinweise blenden beim Laufen aus)
var _figur_k := 1.0            ## Figur sichtbar (im Einrichten weich ausgeblendet)
var _klick_von := Vector2(-1, -1)    ## Maus im Einrichten: wo die Taste gedrückt wurde
var _quader: Array = []              ## Quader der Möbel für die Figur (_welt_quader)
var _quader_stand: Array = []
var _besucher: Node3D                ## Freundestest: die Figuren der Gegenseite (besucher.gd)
var _eigener_raum := {}              ## beim Besuch: dein eigenes Zimmer (zurück nach dem Besuch)
var _eigener_rueck: Array = []       ## … und dein Rückgängig-Stapel (nie mit dem Zimmer des Freundes gemischt)
var _besuch_stand := -1


func _init() -> void:
	super()
	dim = 0.0
	depth = false
	set_meta("uz_silent", true)


func build() -> void:
	main = get_tree().current_scene
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.color = Color(0, 0, 0, 0)
	daten = Daten.laden()
	Katalog.eigene_setzen(daten.get("eigene", []))
	raum = _aktueller_raum()
	_speicher_timer = Timer.new()
	_speicher_timer.one_shot = true
	_speicher_timer.wait_time = 0.8
	_speicher_timer.timeout.connect(speichern)
	add_child(_speicher_timer)
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(svc)
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	_stufe_waehlen()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.audio_listener_enable_3d = false
	# Nicht in den Behälter: Er rechnete die Ansicht in Oberflächen-Einheiten (4K: nur 1080p); er zeigt
	# sie als Bild in echten Bildpunkten (zimmer_basis.gd _aufloesung).
	add_child(vp)
	welt = Welt.new()
	welt.huellen = daten.get("huellen", {})
	vp.add_child(welt)
	welt.bauen(raum, stufe)
	spielbild = Spielbild.new()
	spielbild.stufe = stufe
	spielbild.sichtbar = _tv_im_bild
	spielbild.bild.connect(func(img: Image) -> void: welt.tv_live(img))
	spielbild.kein_bild.connect(func() -> void: welt.tv_live_aus())
	add_child(spielbild)
	raumton = Raumton.new()
	raumton.hoerer = _hoerer
	raumton.quelle = _ton_quelle
	raumton.zustand = func() -> String: return str(main.tv_zustand()) if main else ""
	add_child(raumton)
	bildzeit = Bildzeit.new()
	bildzeit.zimmer(vp)
	bildzeit.leistung = leistung
	leistung.netze_info = _netze_text
	bildzeit.skripte = func() -> String: return "Skripte Ø %.2f ms (teuerste im Zimmer: %s)" % [leistung.skript_ms, Leistung.skript_text(3)] if leistung else ""
	add_child(bildzeit)
	_spiel_lief = Spielbild.spiel_laeuft()
	if _spiel_lief:
		welt.laeuft_titel = Spielbild.titel()
		welt.tv_auffrischen()
	_hud_bauen()
	_ankommen()
	bewohner = Bewohner.new()
	bewohner.einrichten(self)
	_besucher = Besucher.new()
	_besucher.name = "besucher"
	bewohner.add_child(_besucher)
	modulate.a = 1.0
	# Läuft schon ein Spiel (Guide › Dein Zimmer): gleich schlank und gemessen, und die Kamera kommt aus
	# dem Fernseher.
	if _spiel_lief:
		_spar_lage(str(main.tv_zustand()) if main else "")
	if _spiel_lief and welt.medienwand() >= 0:
		_verstecke_shell(true)
		aus_dem_spiel()
	elif has_meta("uz_tuer"):
		_eintreten_tuer()
	else:
		_eintreten()


## Eintreten ohne Schnitt ins Dunkle (Plan „Gefühl“: das Zimmer liegt hinter dem Live-Bild): Das
## Zimmer wächst in T_RAUM aus dem Rechteck der Kachel, von der es aufging (Meta „uz_von“, von
## main.open_room: Live-Bild unter „Weiter“ der Apps, Zimmer-Kachel), auf den Schirm und blendet dabei
## in T_WEG auf; ohne Kachel blendet es in T_RAUM über die Oberfläche. Die Oberfläche bleibt
## darunter stehen, bis das Zimmer sie ganz deckt – erst dann wird sie versteckt.
func _eintreten() -> void:
	_schwarz.color.a = 0.0
	var von: Variant = get_meta("uz_von") if has_meta("uz_von") else null
	var voll := size if size.x > 1.0 else U.view_size()
	Toasts.unruhe(U.T_RAUM)
	svc.modulate.a = 0.0
	_hud.modulate.a = 0.0
	var tw := U.ankommen(svc, U.T_RAUM, "uz_zimmer_ein").set_parallel(true)
	if von is Rect2 and not U.reduziert():
		var r: Rect2 = von
		var k := clampf(maxf(r.size.x / voll.x, r.size.y / voll.y), 0.05, 1.0)
		svc.pivot_offset = Vector2.ZERO
		svc.scale = Vector2(k, k)
		svc.position = (r.get_center() - voll * k * 0.5).round()
		tw.tween_property(svc, "scale", Vector2.ONE, U.T_RAUM)
		tw.tween_property(svc, "position", Vector2.ZERO, U.T_RAUM)
		tw.tween_property(svc, "modulate:a", 1.0, U.T_WEG).set_trans(Tween.TRANS_QUAD)
	else:
		tw.tween_property(svc, "modulate:a", 1.0, U.T_RAUM)
	# Angaben und Hinweise im Bild kommen, wenn das Zimmer steht (Fläche vor Schrift).
	tw.tween_property(_hud, "modulate:a", 1.0, U.T_ORT).set_delay(U.T_RAUM - U.T_ORT + U.NACH_FLAECHE)
	tw.chain().tween_callback(func() -> void:
		if not _closing and is_inside_tree():
			_verstecke_shell(true)
	)


## Durch die Tür (zimmer_tuer.gd, Bereich Zimmer): Die Kamera steht gleich hinter der Zimmertür und schaut
## in den Raum; die Tür darüber zeigt das Zimmer durch ihre Öffnung, bis sie den Schirm füllt. tuer_hinein
## führt die Kamera dann an deinen Platz. Die Oberfläche darunter ist schon ganz verdeckt.
## Du stehst danach immer so, als kämst du gerade herein (tuer_ankommen) – nicht dort, wo du zuletzt warst.
func _eintreten_tuer() -> void:
	_schwarz.color.a = 0.0
	_hud.modulate.a = 0.0
	_verstecke_shell(true)
	tuer_ankommen()
	welt.kamera.fov = float(_kamera_soll()[1])
	welt.kamera.global_transform = _tuer_blick()
	modus = "fahrt"
	_hinweise_auffrischen()


## Gleich hinter der Zimmertür (rechte Wand), Blick in den Raum: Ich-Ansicht einen Schritt herein, über
## die Schulter ein paar Schritte (die Kamera hinter dir bleibt im Raum); von oben wird zur Ich-Ansicht.
func tuer_ankommen() -> void:
	var t: Vector3 = welt.huelle.call("tuer_mitte")
	if blick == "oben":
		blick = "ich"
	pos = _frei(Vector3(t.x - (0.85 if blick == "ich" else 2.3), 0, t.z))
	yaw = PI * 0.5
	_yaw_soll = yaw
	pitch = -0.07
	cursor = Vector2i(clampi(int(pos.x / Katalog.ZELLE), 0, int(raum.w) - 1), clampi(int(pos.z / Katalog.ZELLE), 0, int(raum.d) - 1))


## Blick gleich hinter der Zimmertür (rechte Wand) in den Raum.
func _tuer_blick() -> Transform3D:
	var t: Vector3 = welt.huelle.call("tuer_mitte")
	return Transform3D(Basis(), Vector3(t.x - 0.32, AUGEN, t.z)).looking_at(Vector3(t.x - 3.0, AUGEN - 0.2, t.z), Vector3.UP)


## Die Tür ist auf (zimmer_tuer.gd): erst geradeaus durch sie hindurch, dann an deinen Platz; Angaben und
## Hinweise kommen, wenn die Kamera steht.
func tuer_hinein(dauer: float) -> void:
	if not is_inside_tree() or _closing or modus != "fahrt":
		return
	modus = "laufen"
	var soll := _kamera_soll()
	modus = "fahrt"
	var von := welt.kamera.global_transform
	# Geradeaus durch die Tür an deinen Platz gleich dahinter (ohne Schwung darüber hinaus und zurück).
	var nach: Transform3D = soll[0]
	await _bogen(von, welt.kamera.fov, nach, float(soll[1]), von.origin.lerp(nach.origin, 0.5), dauer, false).finished
	if not is_inside_tree() or _closing:
		return
	U.ankommen(_hud, U.T_ORT, "uz_zimmer_ein").tween_property(_hud, "modulate:a", 1.0, U.T_ORT)
	modus = "laufen"
	_rate = 30.0
	_ziel = -2
	_ziel_suchen()
	_kopf_auffrischen()
	_hinweise_auffrischen()


## Grafik-Stufe wechseln (Seitenleiste „Licht“): die Welt wird mit der neuen Stufe neu gebaut, du
## bleibst, wo du bist.
## Bildrate im Zimmer (Anpassen › Mehr): wie der Bildschirm, 60 oder 30 (leistung.gd).
func fps_setzen(wahl: String) -> void:
	Config.set_value("room.fps", wahl)
	if leistung:
		leistung.fps_waehlen(wahl)


func grafik_setzen(wahl: String) -> void:
	Config.set_value("room.grafik", wahl)
	if not _halten.is_empty():
		_ablegen_abbrechen()     # das Getragene gehört zur alten Welt
	_glimmen_setzen(null)
	_stufe_waehlen()
	spielbild.stufe = stufe
	_welt_neu()
	if modus == "bauen":
		_raster_auffrischen()
	_kopf_auffrischen()


func _aktueller_raum() -> Dictionary:
	for r in daten.raeume:
		if str(r.id) == str(daten.aktuell):
			return r
	return daten.raeume[0]


## Where you stand when you enter: at the start position, facing the TV and sofa, or just inside the door
## (tuer_ankommen). The last position is restored only when returning to the room (after a game launched from
## the TV, or next to a running game), so the room reliably resets on every other entry.
func _ankommen() -> void:
	if not has_meta("uz_anfang") and not _letzte.is_empty() and str(_letzte.get("raum", "")) == str(raum.id):
		pos = _letzte.pos
		yaw = float(_letzte.yaw)
		pitch = float(_letzte.pitch)
		blick = str(_letzte.blick)
		_oben_az = float(_letzte.get("az", _oben_az))
	else:
		var w := float(raum.w) * Katalog.ZELLE
		var d := float(raum.d) * Katalog.ZELLE
		pos = _frei(Vector3(w * 0.84, 0, d * 0.88))
		var tv := welt.medienwand()
		var ziel := Vector3(w * 0.5, 0, 0) if tv < 0 else (welt.boxen[tv] as AABB).get_center()
		var dir := ziel - pos
		yaw = atan2(-dir.x, -dir.z)
		pitch = -0.1
	_yaw_soll = yaw
	_oben_az_soll = _oben_az
	cursor = Vector2i(clampi(int(pos.x / Katalog.ZELLE), 0, int(raum.w) - 1), clampi(int(pos.z / Katalog.ZELLE), 0, int(raum.d) - 1))
	# Erstes Bild: Kamera ein Stück zurück, dann gleitet sie an ihren Platz.
	var soll := _kamera_soll()
	welt.kamera.transform = Transform3D(soll[0].basis, (soll[0] as Transform3D).origin + (soll[0] as Transform3D).basis.z * 0.6 + Vector3(0, 0.15, 0))
	welt.kamera.fov = float(soll[1])
	_rate = 3.0
	_hinweise_auffrischen()


func _notification(what: int) -> void:
	super(what)
	if what == NOTIFICATION_EXIT_TREE:
		_maus_frei()
		_verstecke_shell(false)
		_hinweis_grund(true)
		if _speicher_timer and not _speicher_timer.is_stopped():
			speichern()
		_letzte = { "raum": str(raum.get("id", "")), "pos": pos, "yaw": yaw, "pitch": pitch, "blick": blick, "az": _oben_az }
		# Über dem laufenden Spiel zu (aufgestanden oder dahinter wartend): main räumt auf.
		if main and str(main.tv_zustand()) in ["zimmer", "vollbild"]:
			main.tv_zimmer_zu.call_deferred()
		# Globale Einstellungen der Engine wieder wie im Projekt (zimmer_basis.gd _forward_global).
		_global_wie_projekt()


# --- Oberfläche über dem Zimmer ------------------------------------------------------------------

func _hud_bauen() -> void:
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_hud)
	add_child(_hud)
	# Leiser Verlauf unten, damit Angaben und Hinweise (Hinweisleiste von main) lesbar bleiben.
	var unten := TextureRect.new()
	unten.texture = U.fade_texture(true, true)
	unten.modulate = Color(0, 0, 0, 0.5)
	unten.anchor_left = 0.0
	unten.anchor_right = 1.0
	unten.anchor_top = 1.0
	unten.anchor_bottom = 1.0
	unten.offset_top = -300
	unten.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	unten.stretch_mode = TextureRect.STRETCH_SCALE
	unten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(unten)
	_punkt = _Punkt.new()
	_punkt.anchor_left = 0.5
	_punkt.anchor_right = 0.5
	_punkt.anchor_top = 0.5
	_punkt.anchor_bottom = 0.5
	_hud.add_child(_punkt)
	_kopf = U.vbox(2)
	_kopf.position = Vector2(UzTheme.GUTTER, 56)
	_kopf_titel = U.shadow(U.label("Dein Zimmer", "l", "text", "title" if UzTheme.strict() else "bold"), 0.5)
	_kopf_sub = U.shadow(U.label("", "s", "muted", "medium"), 0.5)
	_kopf.add_child(_kopf_titel)
	_kopf.add_child(_kopf_sub)
	_hud.add_child(_kopf)
	_ziel_pill = PanelContainer.new()
	# Das Schild am Ziel: im eckigen Theme (Marke) ein kleines Blatt wie überall – matt, eckig,
	# Haarlinie; kein Glas.
	if UzTheme.strict():
		_ziel_pill.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), 0, 1, UzTheme.col("line")))
	else:
		_ziel_pill.add_theme_stylebox_override("panel", UzTheme.box(Color(UzTheme.col("surface"), 0.78), 26))
	var zm := U.margin(22, 10, 22, 10)
	var zh := U.hbox(14)
	_ziel_text = U.label("", "m", "text", "ui_bold")
	_ziel_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	zh.add_child(_ziel_text)
	_ziel_glyph = U.glyph("a", 27)
	zh.add_child(_ziel_glyph)
	_ziel_aktion = U.label("", "s", "muted", "medium")
	zh.add_child(_ziel_aktion)
	zm.add_child(zh)
	_ziel_pill.add_child(zm)
	_ziel_pill.modulate.a = 0.0
	_hud.add_child(_ziel_pill)
	_info = U.vbox(4)
	_info.position = Vector2(UzTheme.GUTTER, 0)
	_info_kicker = U.shadow(U.label("", "s", "accent_ink", "ui_bold"), 0.5)
	_info_titel = U.shadow(U.label("", "xl", "text", "bold"), 0.55)
	_info_titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info_titel.custom_minimum_size = Vector2(1000, 0)
	_info_titel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info_titel.clip_text = true
	_info_meta = U.shadow(U.label("", "m", "muted", "regular"), 0.5)
	_info.add_child(_info_kicker)
	_info.add_child(_info_titel)
	_info.add_child(_info_meta)
	_info.modulate.a = 0.0
	_hud.add_child(_info)
	_meldung = PanelContainer.new()
	_meldung.add_theme_stylebox_override("panel", UzTheme.box(Color(UzTheme.col("surface"), 0.86), 22))
	var mm := U.margin(22, 9, 22, 9)
	_meldung_l = U.label("", "m", "text", "medium")
	mm.add_child(_meldung_l)
	_meldung.add_child(mm)
	_meldung.modulate.a = 0.0
	_hud.add_child(_meldung)
	_katalog = KatalogUi.new()
	_katalog.zimmer = self
	_katalog.visible = false
	_hud.add_child(_katalog)
	_seiten = Anpassen.new(self)
	_ui = AnpassenUi.new()
	_ui.rueckgaengig = rueckgaengig
	_ui.eigene_farben = eigene_farben
	_ui.farbe_merken = farbe_merken
	_ui.schritt_neu.connect(func() -> void: _schritt_offen = true)
	_ui.geschlossen.connect(_anpassen_zu)
	_hud.add_child(_ui)
	_rad = RadUi.new()
	_rad.vorschau = _stimmung_vorschau
	_rad.gewaehlt.connect(_stimmung_gewaehlt)
	_rad.abgebrochen.connect(_stimmung_abgebrochen)
	_hud.add_child(_rad)
	_baukasten = Baukasten.new()
	_baukasten.zimmer = self
	_baukasten.fertig.connect(_baukasten_fertig)
	_baukasten.verworfen.connect(_baukasten_zu)
	_hud.add_child(_baukasten)
	_tasten_ui = TastenUi.new()
	_hud.add_child(_tasten_ui)
	_modus_ui = ModusUi.new()
	_modus_ui.gewaehlt.connect(modus_wechseln)
	_hud.add_child(_modus_ui)
	_kontext = KontextUi.new()
	_kontext.zu.connect(func() -> void:
		_ziel_zeigen()
		_hinweise_auffrischen())
	_hud.add_child(_kontext)
	# Spielbild bildschirmfüllend: liegt am Ende der Fahrt in den Fernseher über allem (und am
	# Anfang der Fahrt heraus), schwarz hinterlegt wie der Bildschirm selbst.
	_spiel_voll = TextureRect.new()
	_spiel_voll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spiel_voll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spiel_voll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_spiel_voll)
	var grund := ColorRect.new()
	grund.color = Color.BLACK
	grund.show_behind_parent = true
	grund.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(grund)
	_spiel_voll.add_child(grund)
	_spiel_voll.visible = false
	add_child(_spiel_voll)
	_blitz = ColorRect.new()
	_blitz.color = Color(1, 1, 1, 0)
	_blitz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_blitz)
	add_child(_blitz)
	_schwarz = ColorRect.new()
	_schwarz.color = Color(0, 0, 0, 0)
	_schwarz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_schwarz)
	add_child(_schwarz)
	resized.connect(_hud_lage)
	_hud_lage.call_deferred()
	_kopf_auffrischen()


# --- Jedes Bild ---------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not is_inside_tree() or _closing:
		return
	if _still:
		return
	_zeit += dt
	_spiel_pruefen()
	# Das Spiel liegt vorn (Vollbild): Das Zimmer wartet dahinter – kein Bild, keine Eingabe (ruhen).
	if modus == "spiel":
		return
	# Liegt etwas darüber (Auswahl, Guide, Spielseite): Bild anhalten, nichts rechnen.
	var vorn := Nav.top_layer() == self
	_tasten_ui.visible = vorn
	_hinweis_grund(not vorn)
	if not vorn and modus != "fahrt":
		if vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		leistung.hinten()
		return
	# Bildrate (leistung.gd): wie im Menü, jedes Bild neu gerechnet – auch neben dem laufenden Spiel.
	leistung.spiel = _spiel_lief
	leistung.vor_bild()
	# Zeit je Abschnitt (leistung.gd: die teuersten stehen in launch.log).
	var t := Time.get_ticks_usec()
	var ls := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	var rs := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	match modus:
		"laufen":
			# Kontextmenü offen: stehen bleiben (das Steuerkreuz wählt in der Liste).
			if not _kontext.offen():
				_laufen(dt, _stick_lauf(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 1.0), _stick_lauf(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, KURVE_BLICK, TOTZONE_BLICK))
			else:
				_darstellen()
		"ansehen":
			_ansehen_bild(dt)
		"sitzen":
			_sitz_blick = (_sitz_blick + Vector2(-rs.x, -rs.y) * dt * 1.4).clamp(Vector2(-1.1, -0.5), Vector2(1.1, 0.45))
			if ls.length() > 0.6:
				_aufstehen()
		"bauen", "katalog", "anpassen":
			_oben_az_soll -= rs.x * dt * 1.6
			_oben_zoom = clampf(_oben_zoom + rs.y * dt * 0.8, 0.62, 1.25)
		"rad":
			_rad.stick(ls)
		"baukasten":
			_baukasten.bild(dt, rs)
		"foto":
			_foto_bild(dt, ls, rs)
	_oben_az = lerp_angle(_oben_az, _oben_az_soll, 1.0 - exp(-dt * 7.0))
	if modus != "laufen" and (_hoehe > 0.0 or _duck_senken > 0.0 or not bool(_k.boden)):
		_koerper_setzen(pos)
	t = Leistung.abschnitt("Steuerung", t)
	_blick_platz(dt)
	t = Leistung.abschnitt("Blick aufs Regal", t)
	_kamera(dt)
	t = Leistung.abschnitt("Kamera", t)
	bewohner.bild(dt)     # misst selbst (Figur, Haustier)
	t = Time.get_ticks_usec()
	_online_bild(dt)
	_figur_bild(dt)
	_ruhe_bild(dt, ls, rs)
	_schild_bild(dt)
	if modus != "baukasten":
		_glimmen_bild(dt)
	t = Leistung.abschnitt("Figur, Ruhe, Schild", t)
	_kleinigkeiten(dt)
	t = Leistung.abschnitt("Kleinigkeiten", t)
	leistung.nach_bild(dt)
	Leistung.abschnitt("Messen", t)


## Stick mit runder Totzone und weichem Anstieg (feine Bewegungen bleiben fein).
func _stick(ax: int, ay: int) -> Vector2:
	var v := Vector2.ZERO
	for id in Input.get_connected_joypads():
		var p := Vector2(Input.get_joy_axis(id, ax), Input.get_joy_axis(id, ay))
		if p.length() > v.length():
			v = p
	var l := v.length()
	if l < 0.16:
		return Vector2.ZERO
	var k := (minf(l, 1.0) - 0.16) / 0.84
	return v / l * k * k * (3.0 - 2.0 * k) if k < 0.999 else v / l


## Stick fürs Laufen und Umsehen: runde Totzone, Rand außen, danach ohne Sprung von 0 bis 1 und
## hoch kurve (1 = linear). Ohne weiche S-Kurve: die machte kleine und große Ausschläge zäh.
func _stick_lauf(ax: int, ay: int, kurve: float, totzone := TOTZONE) -> Vector2:
	var v := Vector2.ZERO
	for id in Input.get_connected_joypads():
		var p := Vector2(Input.get_joy_axis(id, ax), Input.get_joy_axis(id, ay))
		if p.length() > v.length():
			v = p
	return stick_kurve(v, kurve, totzone)


static func stick_kurve(v: Vector2, kurve: float, totzone := TOTZONE) -> Vector2:
	var l := v.length()
	if l < totzone:
		return Vector2.ZERO
	var k := clampf((l - totzone) / (1.0 - totzone - RAND), 0.0, 1.0)
	return v / l * pow(k, kurve)


func _tasten() -> Vector2:
	var v := Vector2.ZERO
	if not get_window().has_focus():
		return v
	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("uz_up"):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("uz_down"):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("uz_left"):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("uz_right"):
		v.x += 1.0
	return v.limit_length(1.0)


## Springen (Leertaste; A, wenn vor dir nichts zu tun ist): der nächste Takt springt, nur vom
## Boden aus (bewegung.gd).
func _springen() -> void:
	if not bool(_k.boden) or blick == "oben":
		Sfx.play("bump")
		return
	_sprung_puls = true


## Umsehen und, von oben, die Figur drehen – in jedem Bild. Laufen selbst rechnet _physics_process.
func _laufen(dt: float, ls: Vector2, rs: Vector2) -> void:
	var tast := _tasten()
	var wunsch := ls if ls.length() > tast.length() else tast
	if blick == "oben":
		_oben_az_soll -= rs.x * dt * 1.6
		_oben_zoom = clampf(_oben_zoom + rs.y * dt * 0.8, 0.62, 1.25)
		var vorwaerts := Vector3(-sin(_oben_az), 0, -cos(_oben_az))
		var rechts := Vector3(cos(_oben_az), 0, -sin(_oben_az))
		var w := rechts * wunsch.x + vorwaerts * -wunsch.y
		if wunsch.length() > 0.2:
			_yaw_soll = atan2(-w.x, -w.z)
		# Von oben dreht sich nur die Figur weich in die Laufrichtung (die Kamera bleibt).
		yaw = lerp_angle(yaw, _yaw_soll, 1.0 - exp(-dt * 8.0))
	else:
		# Umsehen mit dem Stick: linear, feste Drehgeschwindigkeit, ohne Trägheit oder Nachlauf.
		var e := stick_empf()
		yaw -= rs.x * DREH * e * dt
		_yaw_soll = yaw
		pitch = clampf(pitch - rs.y * DREH_HOCH * e * y_achse() * dt, -NEIGUNG, NEIGUNG)
	_darstellen()
	var v_jetzt := Vector2(_vel.x, _vel.z).length()
	if bool(_k.boden) and v_jetzt > 0.1:
		_wipp += dt * v_jetzt * TAU / Bewohner.Avatar.schritt_laenge(v_jetzt)
	_ziel_suchen()


## Laufen im Physik-Takt (wie Source: feste Schritte, gezeigt wird dazwischen).
func _physics_process(dt: float) -> void:
	var t := Time.get_ticks_usec()
	_physik(dt)
	Leistung.abschnitt("Laufen (Physik)", t)


func _physik(dt: float) -> void:
	if not is_inside_tree() or _closing or _still or modus != "laufen" or Nav.top_layer() != self:
		return
	if pos.x != _pos_gezeigt.x or pos.z != _pos_gezeigt.z:
		_koerper_setzen(pos)
	var wunsch := Vector2.ZERO
	var frei: bool = not _kontext.offen() and not (bewohner and bewohner.leiste_offen())
	if frei:
		var ls := _stick_lauf(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 1.0)
		var tast := _tasten()
		wunsch = ls if ls.length() > tast.length() else tast
	# Rennen: Shift halten oder den linken Stick drücken (gilt, bis du stehen bleibst).
	var fokus := get_window().has_focus()
	var shift := fokus and Input.is_physical_key_pressed(KEY_SHIFT)
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_STICK):
			_rennen = true
	if wunsch.length() < 0.2:
		_rennen = false
	var ducken := blick != "oben" and (_duck_um or (fokus and Input.is_physical_key_pressed(KEY_CTRL)))
	var az := _oben_az if blick == "oben" else yaw
	var vorwaerts := Vector3(-sin(az), 0, -cos(az))
	var rechts := Vector3(cos(az), 0, -sin(az))
	_k_alt = _k.pos
	_duck_alt = float(_k.duck_t)
	Bew.schritt(_k, rechts * wunsch.x + vorwaerts * -wunsch.y, TEMPO_RENNEN if _rennen or shift else TEMPO, _sprung_puls, ducken,
			_welt_quader(), dt)
	_sprung_puls = false
	_vel = _k.vel


## Was gezeigt wird: zwischen dem letzten und dem jetzigen Takt (Bruchteil des Physik-Takts).
func _darstellen() -> void:
	if pos.x != _pos_gezeigt.x or pos.z != _pos_gezeigt.z:
		_koerper_setzen(pos)      # von außen gesetzt (Ankommen, Aufstehen, Einrichten)
	var f := Engine.get_physics_interpolation_fraction()
	var p: Vector3 = _k_alt.lerp(_k.pos, f)
	pos = Vector3(p.x, 0.0, p.z)
	_pos_gezeigt = pos
	_hoehe = maxf(p.y, 0.0)
	var d := lerpf(_duck_alt, float(_k.duck_t), f)
	_duck_senken = (AUGEN - AUGEN_DUCK) * d * d * (3.0 - 2.0 * d)


## Den Körper an eine Stelle setzen (Ankommen, Aufstehen, Einrichten): auf dem Boden, in Ruhe.
func _koerper_setzen(p: Vector3) -> void:
	_k = Bew.neu(Vector3(p.x, 0.0, p.z))
	_k_alt = _k.pos
	_duck_alt = 0.0
	_duck_um = false
	_vel = Vector3.ZERO
	_hoehe = 0.0
	_duck_senken = 0.0
	_pos_gezeigt = Vector3(p.x, 0.0, p.z)


## Die Welt fürs Laufen: Wände, Boden, Decke und die Möbel, die im Weg stehen (als Quader mit
## ihrer Höhe – auf niedrige steigt man, auf andere springt man).
## Die Quader, an denen die Figur anstößt – gemerkt, bis sich Möbel oder Raum ändern (sonst je
## Physikschritt neu aus allen Möbeln gerechnet).
func _welt_quader() -> Array:
	var stand := [welt.get("_knoten_nr"), (raum.moebel as Array).size(), raum.w, raum.d, _quader_ohne()]
	if stand != _quader_stand:
		_quader_stand = stand
		_quader = _welt_quader_rechnen()
	return _quader


func _welt_quader_rechnen() -> Array:
	var m: Array = []
	var ohne := _quader_ohne()     # was du gerade trägst (zimmer_umbau.gd), steht nicht im Weg
	for i in (raum.moebel as Array).size():
		var it: Dictionary = raum.moebel[i]
		if Katalog.ebene(str(it.t)) != "boden" or i == ohne:
			continue
		var g := Katalog.groesse_it(it)
		m.append([float(it.x) * Katalog.ZELLE + 0.06, float(it.z) * Katalog.ZELLE + 0.06, float(int(it.x) + g.x) * Katalog.ZELLE - 0.06,
				float(int(it.z) + g.y) * Katalog.ZELLE - 0.06, Katalog.hoehe_it(it)])
	return Bew.welt_aus(float(raum.w) * Katalog.ZELLE, float(raum.d) * Katalog.ZELLE, Raum.HOEHE, m)


## Für die Figur: in der Luft? geduckt (0…1)?
func in_der_luft() -> bool:
	return not bool(_k.boden)


func duck_anteil() -> float:
	return float(_k.duck_t)


## Der dunkle Verlauf, auf dem unten die Hinweisleiste von main steht: im Zimmer nicht nötig (die
## Hinweise liegen im Bild und tragen selbst), er läge sonst als Streifen über dem Raum.
func _hinweis_grund(an: bool) -> void:
	var f: Variant = main._hint_fade if main else null
	if f is CanvasItem and is_instance_valid(f) and (f as CanvasItem).visible != an:
		(f as CanvasItem).visible = an


## Im Einrichten tritt die Figur zur Seite: sie wird kleiner und ist weg (sie stand sonst genau auf
## dem gewählten Feld und vor dem Getragenen); beim Fertig kommt sie wieder.
func _figur_bild(dt: float) -> void:
	if modus == "foto":
		# Fotomodus (auch aus dem Einrichten heraus): die Figur ist gleich ganz da.
		if _figur_k < 1.0:
			_figur_k = 1.0
			bewohner.avatar.scale = Vector3.ONE
			bewohner.figur_zeigen(bool(_foto.get("figur", true)))
		return
	var weg := modus in ["bauen", "katalog"] or (modus in ["anpassen", "baukasten"] and _vor_modus == "bauen")
	var soll := 0.0 if weg else 1.0
	if is_equal_approx(_figur_k, soll):
		return
	_figur_k = move_toward(_figur_k, soll, dt / U.T_MOVE)
	var k := _figur_k * _figur_k * (3.0 - 2.0 * _figur_k)
	bewohner.avatar.scale = Vector3.ONE * maxf(k, 0.001)
	bewohner.figur_zeigen(_figur_k > 0.01)


## Hinweise blenden aus, solange du läufst oder die Kamera führst (Laufen, Fotomodus) – stehst du
## eine knappe Sekunde still, kommen sie wieder. Im Menü und beim Einrichten bleiben sie stehen.
func _ruhe_bild(dt: float, ls: Vector2, rs: Vector2) -> void:
	var bewegt := ls.length() > 0.2 or rs.length() > 0.2 or (modus == "laufen" and _tasten().length() > 0.0)
	_ruhe = 0.0 if bewegt else _ruhe + dt
	var leise := modus in ["laufen", "foto"] and _ruhe < 0.9 and not (bewohner and bewohner.leiste_offen())
	_tasten_ui.leise(leise)
	_modus_ui.zeigen(not leise and modus in ["laufen", "bauen", "katalog", "foto", "sitzen", "ansehen"] and not _kontext.offen())


func _glimmen_bild(dt: float) -> void:
	var soll := 0.0
	if is_instance_valid(_glimmen_an) and modus == "laufen":
		soll = 0.42 + 0.08 * sin(_zeit * 2.4)
	elif is_instance_valid(_glimmen_an) and modus == "bauen":
		# Einrichten: das Möbel unter dem Feld glimmt leiser und ruhig (kein Pulsieren im Editor).
		soll = 0.3
	_glimmen = lerpf(_glimmen, soll, 1.0 - exp(-dt * 8.0))
	S.glimmen().set_shader_parameter("staerke", _glimmen)


# --- Kamera ------------------------------------------------------------------------------------

func _kamera(dt: float) -> void:
	var soll := _kamera_soll()
	# Ich- und Schulterblick: ohne Nachlauf (die Kamera hängt fest an Blick und Figur).
	var ich := modus in ["laufen", "rad"] and blick in ["ich", "schulter"] and not bewohner.selfie()
	var ziel_rate := 30.0 if ich else 6.5
	if modus == "foto":
		ziel_rate = 12.0
	if modus in ["fahrt", "fernsehen"]:
		_direkt = 0.0
		_punkt.visible = false
		return
	_rate = lerpf(_rate, ziel_rate, 1.0 - exp(-dt * 2.2))
	var k := 1.0 - exp(-dt * _rate)
	var cam: Camera3D = welt.kamera
	# Ich-Ansicht: Ist die Kamera nach einem Übergang (Regal, Sofa, Blickwechsel) angekommen, sitzt sie
	# ohne Nachlauf in den Augen – sonst lagen drei weiche Folgen übereinander (Stick, Drehung, Kamera).
	var soll_t: Transform3D = soll[0]
	var nah := cam.transform.origin.distance_to(soll_t.origin) < 0.06 and cam.transform.basis.z.angle_to(soll_t.basis.z) < 0.05
	# Jeder andere Blick (Ansehen, Sitzen, Bauen) gleitet gleich wieder weich – nie ein Sprung.
	_direkt = move_toward(_direkt, 1.0, dt * 4.0) if ich and (nah or _direkt > 0.0) else 0.0
	k = lerpf(k, 1.0, _direkt)
	cam.transform = cam.transform.interpolate_with(soll[0], k)
	cam.fov = lerpf(cam.fov, float(soll[1]), k)
	var oben := modus in ["bauen", "katalog", "anpassen", "baukasten"] or (modus in ["laufen", "rad", "sitzen"] and blick == "oben")
	welt.schnitt(cam.global_position, oben)
	# Von oben (10 m und mehr) eine weiter entfernte Nahebene: genauere Tiefe, kein Flackern flacher
	# Lagen (Teppich, Raster); die Umgebungsverdeckung dort leiser (ihr Rauschen kroch beim Drehen).
	cam.near = 0.2 if oben else 0.03
	welt.nach_mat.set_shader_parameter("ao_staerke", 0.3 if oben else 0.55)
	_punkt.visible = modus == "laufen" and blick == "ich" and not bewohner.selfie()
	# Tiefenschärfe: Standard aus (sie machte alles weich). Eingeschaltet (Kamera und Bild) nur dezent
	# beim Ansehen und im Fotomodus – nie beim Laufen oder Bauen.
	if tiefe_an() and modus == "ansehen":
		welt.fokus(float(soll[2]), 0.35, 2.5)
	elif tiefe_an() and modus == "foto":
		welt.fokus(float(soll[2]), 1.4, 1.6 if bool(_foto.get("figur", true)) else 0.0)
	else:
		welt.fokus(float(soll[2]), 99.0, 0.0)


## Ein bisschen Leben, ohne Kitsch: Blätter wiegen sich (Meta „wiegen“ aus moebel.gd), und das
## Licht des Fernsehers flimmert leicht mit dem Bild, solange dort etwas läuft. Nicht in „Leicht“.
var _flimmer_t := 0.0


func _lebendig(dt: float) -> void:
	if stufe == "leicht" or modus == "baukasten":
		return
	for i in welt.knoten.size():
		var n: Node3D = welt.knoten[i]
		if not is_instance_valid(n) or not n.has_meta("wiegen"):
			continue
		var ph := float(i) * 1.7
		for e: Array in n.get_meta("wiegen"):
			var k: Node3D = e[0]
			if not is_instance_valid(k):
				continue
			var r0: Vector3 = e[1]
			var a := sin(_zeit * 0.9 + ph + r0.y) * 0.028 + sin(_zeit * 2.3 + ph * 0.5) * 0.008
			k.rotation = r0 + Vector3(a, 0.0, a * 0.6)
	if welt.tv_spiel and welt.tv_spiel.visible:
		_flimmer_t -= dt
		if _flimmer_t <= 0.0:
			_flimmer_t = randf_range(0.12, 0.3)
			welt.tv_flimmern(randf_range(0.8, 1.08))


func _kleinigkeiten(dt: float) -> void:
	_lebendig(dt)
	# Uhr an der Wand (jede Minute) und der Plattenteller, solange Musik läuft.
	var m := int(Time.get_time_dict_from_system().minute)
	if m != _uhr_min:
		_uhr_min = m
		for i in welt.knoten.size():
			if is_instance_valid(welt.knoten[i]) and (welt.knoten[i] as Node3D).has_meta("uhr"):
				Moebel.stelle_uhr(welt.knoten[i])
		if str(raum.licht.get("z", "")) == "auto":
			_licht_neu()
	_plattenspieler_takt(dt)


## Plattenspieler: dreht nur bei Wiedergabe (33⅓ U/min), Tonarm auf und zurück, Hülle mit Cover.
func _plattenspieler_takt(dt: float) -> void:
	var ps := welt.plattenspieler()
	if ps < 0 or not is_instance_valid(welt.knoten[ps]):
		return
	var n: Node3D = welt.knoten[ps]
	var now: Dictionary = Music.now
	var dauer := int(now.get("duration", 0))
	var anteil := clampf(float(Music.progress_ms()) / float(dauer), 0.0, 1.0) if dauer > 0 else 0.0
	_ps = Platten.schritt(_ps, bool(now.get("playing", false)), anteil, dt, U.reduziert())
	Platten.anwenden(n, _ps)
	var art := str(now.get("art", "")) if not now.is_empty() else "~"
	if art != _ps_art or n.get_instance_id() != _ps_knoten:
		_ps_art = art
		_ps_knoten = n.get_instance_id()
		_cover_holen(art)
		_huelle_setzen(n)


## Cover zum laufenden Titel aus Uzais eigenem Zwischenspeicher (plattenspieler.gd). Fehlt ein
## Spotify-Bild dort noch, holt es der gewohnte Weg der Musik (Media.url_texture) in den Speicher.
func _cover_holen(art: String) -> void:
	_ps_tex = null
	_ps_farbe = Color("#d9cdb6")
	if art == "~" or art == "":
		return
	var pfad := Platten.cover_pfad(art, Config.path("cache"), OS.get_environment("TEMP"))
	if pfad == "":
		return
	if FileAccess.file_exists(pfad):
		var img := Platten.cover_laden(pfad)
		if img != null:
			_ps_tex = ImageTexture.create_from_image(img)
			_ps_farbe = Platten.mittelfarbe(img)
	elif art.begins_with("http"):
		Media.url_texture(art, 64, func(_t: Variant) -> void:
			if is_inside_tree() and _ps_art == art and FileAccess.file_exists(pfad):
				_ps_knoten = 0)


## Hülle und Etikett: mit Cover, ohne Bild eine schlichte Hülle; läuft nichts, keine Hülle.
func _huelle_setzen(n: Node3D) -> void:
	if not n.has_meta("huelle"):
		return
	var leer := _ps_art == "~"
	(n.get_meta("huelle") as Node3D).visible = not leer
	var vorn: StandardMaterial3D = n.get_meta("huelle_bild")
	var rand: StandardMaterial3D = n.get_meta("huelle_rand")
	vorn.albedo_texture = _ps_tex
	vorn.albedo_color = Color.WHITE if _ps_tex != null else _ps_farbe
	rand.albedo_color = _ps_farbe.darkened(0.25) if _ps_tex != null else _ps_farbe.darkened(0.08)
	var bild: MeshInstance3D = n.get_meta("etikett_bild")
	bild.visible = _ps_tex != null
	if _ps_tex != null:
		var m := bild.material_override as StandardMaterial3D
		m.albedo_texture = _ps_tex
		m.roughness = 0.6


# --- Tasten ------------------------------------------------------------------------------------

func nav_dir(cmd: String) -> bool:
	if modus != "laufen":
		_ruhe = maxf(_ruhe, 0.9)     # im Fotomodus: Pose wählen zeigt die Hinweise gleich wieder
	if bewohner and bewohner.leiste_offen():
		return bewohner.leiste_taste(cmd)
	if _kontext.offen():
		_kontext.schritt(cmd)
		_hinweise_auffrischen()
		return true
	if _umbau_dir(cmd):
		return true
	match modus:
		"ansehen":
			_ansehen_schritt(cmd)
		"bauen":
			_cursor_schritt(cmd)
		"katalog":
			_katalog.schritt(cmd)
		"anpassen":
			_ui.schritt(cmd)
			_hinweise_auffrischen()
		"rad":
			# Mit dem Stick zeigt man direkt auf einen Eintrag; nur das Steuerkreuz blättert.
			if _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y).length() < 0.3:
				_rad.schritt(cmd)
		"baukasten":
			_baukasten.schritt(cmd)
			_hinweise_auffrischen()
		"foto":
			_foto_schritt(cmd)
	return true


func nav_command(cmd: String) -> bool:
	_ruhe = maxf(_ruhe, 0.9)
	if bewohner and bewohner.leiste_offen() and cmd != "guide":
		return bewohner.leiste_taste(cmd)
	if _kontext.offen() and cmd != "guide":
		_kontext.taste(cmd)
		_hinweise_auffrischen()
		return true
	if _umbau_taste(cmd):
		_hinweise_auffrischen()
		return true
	# View: Leben → Bauen → Foto (die Modus-Leiste oben).
	if cmd == "view" and modus in ["laufen", "bauen", "katalog", "foto", "sitzen", "ansehen"]:
		Sfx.play("tab")
		modus_wechseln(ModusUi.naechster(modus_gruppe(modus)))
		return true
	match modus:
		"laufen": return _laufen_taste(cmd)
		"ansehen": return _ansehen_taste(cmd)
		"sitzen":
			# Vom Sofa aus: A geht ins Spiel, wenn es gerade im Fernseher läuft.
			if cmd == "a" and _spiel_lief and welt.medienwand() >= 0:
				zum_spiel()
				return true
			if cmd in ["b", "a"]:
				Sfx.play("back")
				_aufstehen()
				return true
			if cmd == "x":
				_blick_wechseln()
				return true
			return cmd != "guide" and cmd != "search"
		"bauen": return _bauen_taste(cmd)
		"katalog": return _katalog_taste(cmd)
		"fernsehen":
			# Vor dem Fernseher: Startet das Spiel noch, geht es gleich hinein; lief es nicht an, steht B auf.
			if cmd == "b":
				if str(main.tv_zustand()) == "startet":
					return true
				Sfx.play("back")
				_fernsehen_ende()
				return true
			return cmd != "guide"
		"fahrt": return cmd != "guide"
		"foto": return _foto_taste(cmd)
		"anpassen":
			if cmd in ["lt", "rt"]:
				_oben_az_soll += PI * 0.5 * (1.0 if cmd == "lt" else -1.0)
				Sfx.play("move")
				return true
			if cmd == "guide":
				return false
			_ui.taste(cmd)
			_hinweise_auffrischen()
			return true
		"rad":
			if cmd == "guide":
				return false
			return bool(_rad.taste(cmd))
		"baukasten":
			if cmd == "guide":
				return false
			_baukasten.taste(cmd)
			_hinweise_auffrischen()
			return true
	return false


func _laufen_taste(cmd: String) -> bool:
	match cmd:
		"a":
			_benutzen()
			return true
		"b":
			if _maus_gefangen:
				_maus_frei()
				return true
			Sfx.play("back")
			# Das Spiel läuft weiter, du bist im Zimmer (fernsehspiel „zimmer“): B führt zum Guide –
			# von dort zurück ins Spiel.
			if str(main.tv_zustand()) == "zimmer":
				main.toggle_guide()
				return true
			close()
			return true
		"x":
			_blick_wechseln()
			return true
		"rt":
			bewohner.leiste_auf()
			return true
		"y":
			if besuch_sperre():
				return true
			_aktionen_laufen()
			return true
		"lb", "rb":
			if blick == "oben":
				_oben_az_soll += PI * 0.5 * (1.0 if cmd == "lb" else -1.0)
			else:
				# Um 45° drehen – sofort, ohne Nachlauf (wie jeder Blick in der Ich-Ansicht).
				yaw += PI * 0.25 * (1.0 if cmd == "lb" else -1.0)
				_yaw_soll = yaw
			Sfx.play("move")
			return true
		"search":
			# Rechten Stick drücken: ducken bzw. wieder aufstehen (die Suche ist im Zimmer nicht da).
			if blick != "oben":
				_duck_um = not _duck_um
			return true
		"menu":
			_zimmer_menue()
			return true
		"lt":
			_rad_auf()
			return true
	return false


func _blick_wechseln() -> void:
	blick = _naechster_blick()
	if blick == "oben":
		_oben_az_soll = yaw
		_oben_az = yaw
	_rate = 4.0
	Sfx.play("select")
	_glimmen_setzen(null)
	_ziel = -2
	_ziel_suchen()
	_hinweise_auffrischen()


## Maus roh: Pixel × Empfindlichkeit, sofort (ohne Glätten, ohne Beschleunigung, ohne Nachziehen).
func _maus_blick(r: Vector2) -> void:
	var k := MAUS * maus_empf()
	yaw -= r.x * k
	_yaw_soll = yaw
	pitch = clampf(pitch - r.y * k * y_achse(), -NEIGUNG, NEIGUNG)


## Klassische Ego-Kamera mit der Maus: ein Klick ins Zimmer fängt den Zeiger (Umsehen ohne Taste),
## danach ist ein Klick A; B (Esc), ein Menü oder ein anderer Modus geben ihn wieder frei.
var _maus_gefangen := false


func _input(e: InputEvent) -> void:
	# Leertaste springt beim Laufen (wie in jedem Ego-Spiel); A bleibt Enter.
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and (e as InputEventKey).physical_keycode == KEY_SPACE \
			and modus == "laufen" and Nav.top_layer() == self and not _kontext.offen() and not (bewohner and bewohner.leiste_offen()):
		get_viewport().set_input_as_handled()
		_springen()
		return
	if not _maus_gefangen:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or modus != "laufen" or blick == "oben" or Nav.top_layer() != self:
		_maus_frei()
		return
	if e is InputEventMouseMotion:
		_maus_blick((e as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		Nav._fire("a")


func _maus_frei() -> void:
	if not _maus_gefangen:
		return
	_maus_gefangen = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _gui_input(e: InputEvent) -> void:
	# Leben, Ich- oder Schulterblick: Klick fängt die Maus (Ego-Kamera).
	if modus == "laufen" and blick != "oben" and not _maus_gefangen and e is InputEventMouseButton \
			and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not _kontext.offen():
		accept_event()
		_maus_gefangen = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	# Einrichten mit der Maus: das Feld folgt dem Zeiger, ein Klick ist A (ziehen dreht die Kamera).
	if modus == "bauen":
		if e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask == 0:
			var f: Variant = _feld_unter((e as InputEventMouseMotion).position)
			if f is Vector2i and f != cursor:
				cursor_setzen(f, false)
		elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.pressed:
				_klick_von = mb.position
			elif _klick_von.x >= 0.0 and mb.position.distance_to(_klick_von) < 8.0:
				_klick_von = Vector2(-1, -1)
				Nav._fire("a")
				return
	# Maus: mit gedrückter Taste umsehen (im Bau-Modus: Kamera drehen).
	if e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask != 0:
		var r := (e as InputEventMouseMotion).relative
		if modus == "foto":
			_foto.yaw = float(_foto.yaw) - r.x * 0.004
			_foto.pitch = clampf(float(_foto.pitch) - r.y * 0.004, -1.3, 1.2)
		elif modus == "laufen" and blick != "oben":
			_maus_blick(r)
		elif modus in ["bauen", "katalog", "anpassen"] or blick == "oben":
			_oben_az_soll -= r.x * 0.006


## Feld unter dem Mauszeiger (auch eine Reihe außerhalb: die Wand), sonst null.
func _feld_unter(p: Vector2) -> Variant:
	var cam: Camera3D = welt.kamera
	var o := cam.project_ray_origin(p)
	var r := cam.project_ray_normal(p)
	if absf(r.y) < 0.001:
		return null
	var t := -o.y / r.y
	if t <= 0.0:
		return null
	var hit := o + r * t
	var c := Vector2i(floori(hit.x / Katalog.ZELLE), floori(hit.z / Katalog.ZELLE))
	var w := int(raum.w)
	var d := int(raum.d)
	if c.x < -1 or c.y < -1 or c.x > w or c.y > d or ((c.x < 0 or c.x >= w) and (c.y < 0 or c.y >= d)):
		return null
	return c


# --- Benutzen ----------------------------------------------------------------------------------

func _benutzen() -> void:
	if _ziel_fenster:
		if besuch_sperre():
			return
		var ids: Array = Daten.ZEITEN.map(func(p: Array) -> String: return str(p[0]))
		var naechste: String = ids[(ids.find(str(raum.licht.get("z", "auto"))) + 1) % ids.size()]
		Daten.merke(_rueck, raum)
		raum.licht.z = naechste
		raum.licht.st = ""
		_licht_neu()
		Sfx.play("toggle_on")
		_melden(tr("Tageszeit: %s") % tr(Daten.wahl_name(Daten.ZEITEN, naechste)))
		_speichern_bald()
		return
	if _ziel_tier:
		bewohner.streicheln()
		return
	if _ziel < 0 or (_bp.is_empty() and Katalog.nutzen(str(raum.moebel[_ziel].t)) == ""):
		_springen()
		return
	# Beim Laufen aufs Regal geschaut: gleich das Spiel (den Pokal, die Platte) im Blick.
	if not _bp.is_empty():
		_platz_nutzen(_bp_m, _bp)
		return
	var it: Dictionary = raum.moebel[_ziel]
	match Katalog.nutzen(str(it.t)):
		"figur":
			Sfx.play("open")
			_figur_wechseln()
		"tier":
			Sfx.play("open")
			figur_editor("tier")
		"spiele", "pokale", "platten":
			# Leeres Spieleregal: gleich einräumen (durchsehen gäbe es nichts).
			if str(it.t) == "spieleregal" and (welt.plaetze.get(_ziel, []) as Array).is_empty():
				regal_einraeumen(_ziel)
				return
			Sfx.play("select")
			_ansehen(_ziel)
		"musik":
			if Music.now.is_empty():
				musik_oeffnen()
				return
			Sfx.play("select")
			Music.play_pause()
			_hinweise_auffrischen.call_deferred()
		"fernseher":
			if _spiel_lief:
				zum_spiel()
				return
			_kontext_auf(_moebel_name(str(it.t)), _tv_eintraege(_ziel), _moebel_punkt(_ziel))
		"sitzen":
			Sfx.play("select")
			_hinsetzen(_ziel)
		"lampe":
			it.an = not bool(it.an)
			Sfx.play("toggle_on" if it.an else "toggle_off")
			welt.lampen_auffrischen()
			_ziel_zeigen()
			_hinweise_auffrischen()
			_speichern_bald()


## Zum Bereich Musik (Plattenspieler › Musik öffnen): dort startet man Musik, das Zimmer geht.
func musik_oeffnen() -> void:
	Sfx.play("open")
	main.goto("music", "jetzt" if not Music.now.is_empty() else "")
	close()


func _hinsetzen(i: int) -> void:
	if not (welt.knoten[i] as Node3D).has_meta("sitz"):
		return
	_sitz = i
	_sitz_blick = Vector2.ZERO
	modus = "sitzen"
	_rate = 3.0
	_glimmen_setzen(null)
	_ziel_zeigen()
	_hinweise_auffrischen()


## Andere Variante für ein Möbel (Farbe, Holz, Fernseher-Art) – mit Rückgängig.
func _variante_setzen(i: int, v: String, merken: bool) -> void:
	if besuch_sperre():
		return
	var it: Dictionary = raum.moebel[i]
	if str(it.v) == v or not Katalog.variante_gueltig(str(it.t), v):
		return
	if merken:
		Daten.merke(_rueck, raum)
	it.v = v
	welt.moebel_neu(i)
	_speichern_bald()


# --- Speichern ---------------------------------------------------------------------------------

func speichern() -> void:
	_speicher_timer.stop()
	if besuch:
		return
	Daten.speichern(daten)


# --- Freundestest (freundestest.gd) -----------------------------------------------------------------------

## Jedes Bild: eigene Lage an den Freundestest, Figuren der Gegenseite zeigen; als Gast das Zimmer des
## Gastgebers (sobald es da ist), nach dem Besuch wieder dein eigenes.
func _online_bild(dt: float) -> void:
	var ft: Node = FT.aktiv if FT.laeuft() else null
	if ft == null:
		if _besucher.anzahl() > 0:
			_besucher.leeren()
		if besuch:
			besuch_aus()
		return
	ft.ich_setzen(Vector3(pos.x, _hoehe, pos.z), yaw, pitch)
	ft.figur_setzen(daten.get("figur"), daten.get("tier"))
	if str(ft.rolle) == "gast":
		if not (ft.gast_raum as Dictionary).is_empty() and int(ft.raum_stand) != _besuch_stand and modus in ["laufen", "sitzen"]:
			besuch_an(ft.gast_raum, int(ft.raum_stand))
	else:
		if besuch:
			besuch_aus()
		ft.raum_setzen(raum)
	_besucher.bild(dt, ft.figuren())


## Gast: ins Zimmer des Gastgebers (schon geprüft: netz_protokoll.gd → pruefe_raum). Dein Zimmer wird vorher
## gespeichert und bleibt unberührt.
func besuch_an(r: Dictionary, stand: int) -> void:
	var erst := not besuch
	if erst:
		if not _speicher_timer.is_stopped():
			speichern()
		_eigener_raum = raum
		# Rückgängig bleibt bei deinem Zimmer: Ein Stand aus dem Zimmer des Freundes auf deinem Stapel hätte
		# nach dem Besuch mit X dein eigenes Zimmer überschrieben (rueckgaengig übernimmt den ganzen Raum).
		_eigener_rueck = _rueck
		_rueck = []
	if modus == "sitzen":
		_aufstehen()
	besuch = true
	_besuch_stand = stand
	raum = r.duplicate(true)
	_welt_neu()
	if erst:
		pos = _frei(Vector3(float(raum.w) * Katalog.ZELLE * 0.84, 0, float(raum.d) * Katalog.ZELLE * 0.88))
		_koerper_setzen(pos)
		Toasts.show_toast("Im Zimmer deines Freundes", "Beim Besuch änderst du nichts.", "friends")
	_kopf_auffrischen()
	_hinweise_auffrischen()


func besuch_aus() -> void:
	if not besuch:
		return
	if modus == "sitzen":
		_aufstehen()
	besuch = false
	_besuch_stand = -1
	raum = _eigener_raum if not _eigener_raum.is_empty() else _aktueller_raum()
	_eigener_raum = {}
	_rueck = _eigener_rueck
	_eigener_rueck = []
	_welt_neu()
	pos = _frei(pos)
	_koerper_setzen(pos)
	_kopf_auffrischen()
	_hinweise_auffrischen()


# --- Fadenkreuz -------------------------------------------------------------------------------------

## Ein kleiner, weicher Punkt in der Mitte (Ich-Ansicht): zeigt, worauf A wirkt.
class _Punkt extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(12, 12)
		position = Vector2(-6, -6)
		size = Vector2(12, 12)

	func _draw() -> void:
		draw_circle(Vector2(6, 6), 4.5, Color(0, 0, 0, 0.25))
		draw_circle(Vector2(6, 6), 3.0, Color(UzTheme.col("text"), 0.8))
