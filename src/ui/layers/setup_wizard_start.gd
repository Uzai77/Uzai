extends "res://src/ui/layers/setup_wizard_bausteine.gd"
## Einrichtung, Schicht über setup_wizard_bausteine.gd: Willkommen (der Einschalt-Moment mit
## Sprache), das stille Erkennen des Controllers und – freiwillig – Aussehen (Akzentfarbe,
## Klänge, Größe).

const Lang := preload("res://src/core/lang.gd")

const ACCENTS := ["#a47bff", "#e7c27d", "#ff8a57", "#ff5d78", "#f29ad8", "#a8a3ff", "#7aa2ff", "#4fc3e8", "#69e39a", "#e4e4e7"]
const DisplayFit := preload("res://src/core/display_fit.gd")
## Gezeichnete Szenen der Einrichtung (Vorschau im Willkommen, Szenen der Vorstellung).
const Szene := preload("res://src/ui/components/einrichtung_szene.gd")
## Willkommen: das Zeichen genau wie im Intro (boot.gd) – so hoch steht das U.
const MARK_PX := 230.0

var resume := {}                 ## nach einem Neuaufbau: { index, key }
var _default: Control            ## erste Wahl der Seite
var _last_key := ""             ## zuletzt gewählt (für das Wiederöffnen nach einem Neuaufbau)

## Bleibt über einen Neuaufbau (Farbschema) erhalten.
static var _detected := ""       ## erkannter Controller („Tastatur“ ohne Controller)
## Nur für Proben: so tun, als wäre ein Controller verbunden (unter xvfb gibt es keinen).
static var probe_pad := false


# --- 1 Willkommen -------------------------------------------------------------------------

## Der Einschalt-Moment, genau wie im Intro (boot.gd): Das Licht geht an (Bühne, mit dem
## Anschwellen „swell“), die Lichtlinie zieht sich durch den Bogen, die Bänder setzen sich um sie,
## das U setzt sich groß und frei (ohne Kachel) auf seine Größe, darunter erscheint klein und flach
## die gesperrte Wortmarke (_Marke). Steht das Licht, kommt der tiefe Tick der Guide-Taste und vom
## Grund des Bogens ein weicher Lichtschein in den Raum. Dann kommen Gruß, Sprache und „Starten“
## von unten herein. A startet sofort; die Sprache wirkt beim Wählen.
func _willkommen() -> void:
	var cc := CenterContainer.new()
	U.full_rect(cc)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(cc)
	var col := U.vbox(0)
	col.custom_minimum_size = Vector2(1100, 0)
	cc.add_child(col)
	var mark := _Marke.new()
	mark.u_h = MARK_PX
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(mark)
	_buehne.fokus(mark)
	col.add_child(U.spacer(0, 40, false))
	var title := Label.new()
	title.text = "Willkommen"
	title.add_theme_font_override("font", UzTheme.display("title"))
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", UzTheme.col("text"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	col.add_child(U.spacer(0, 10, false))
	var tag := U.label("Dein PC als Konsole.", "l", "muted", "regular", true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	# Sprache: wirkt sofort, die Einrichtung baut sich in der neuen Sprache neu auf.
	col.add_child(U.spacer(0, 56, false))
	var lrow := U.hbox(14)
	lrow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(lrow)
	var cur_lang := str(Config.get_value("system.language", "de"))
	for l in Lang.LANGS:
		var code := str(l[0])
		var on := code == cur_lang
		var lb := _knopf(str(l[1]), "check" if on else "")
		# Sprachnamen stehen immer in ihrer eigenen Sprache.
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lb.custom_minimum_size = Vector2(200, 56)
		lb.set_meta("uz_key", "su:lang:" + code)
		lb.set_meta("uz_hint_a", "Gewählt" if on else "Auswählen")
		lb.pressed.connect(func() -> void: _set_language(code))
		lrow.add_child(lb)
	col.add_child(U.spacer(0, 22, false))
	var row := U.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var go := _knopf("Starten")
	go.custom_minimum_size = Vector2(300, 64)
	go.set_meta("uz_hint_a", "Starten")
	go.set_meta("uz_key", "su:start")
	go.pressed.connect(func() -> void: _go("weiter"))
	row.add_child(go)
	# Kein „Überspringen“: Die Einrichtung ist kurz (A geht durch). Nur aus den Einstellungen neu
	# gestartet lässt sie sich hier abbrechen.
	if restart:
		var stop := _knopf("Abbrechen")
		stop.custom_minimum_size = Vector2(0, 64)
		stop.set_meta("uz_key", "su:abbrechen")
		stop.pressed.connect(_back_at_start)
		row.add_child(stop)
	_default = go
	if not resume.is_empty():
		return
	# Erst Licht und Zeichen, dann der Rest: steigt W_ORT von unten und blendet ein (T_RAUM, gestaffelt).
	Sfx.play("swell", 1.0, null)
	mark.play(0.25)
	var steht := 0.25 + _Marke.STEHT
	get_tree().create_timer(steht).timeout.connect(func() -> void:
		if not is_instance_valid(mark) or not is_instance_valid(_buehne):
			return
		Sfx.play("guide", 1.0, null)
		# Vom Grund des Bogens geht ein weicher Schein in den Raum (das Licht steht).
		var at: Vector2 = _buehne.get_global_transform().affine_inverse() * (mark.get_global_transform() * mark.licht_pos())
		_buehne.feiern(at, 0.7)
	)
	_steigen([title, tag, lrow, row], steht)


# --- Wer spielt? -------------------------------------------------------------------------------

## Name und Farbe des Profils – wie jede Konsole zuerst fragt, wem sie gehört. Das Bild in der Mitte
## trägt gleich Anfangsbuchstabe und Farbe; der Name steht danach auf der Startseite, bei Freunden
## und über „Alles bereit“. Bild, PIN und Kinderprofil bleiben in den Einstellungen.
func _du() -> void:
	var cc := CenterContainer.new()
	U.full_rect(cc)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(cc)
	var col := U.vbox(0)
	col.custom_minimum_size = Vector2(1100, 0)
	cc.add_child(col)
	var p: Dictionary = Config.profile()
	var pid := str(p.get("id", ""))
	var gesicht := _Gesicht.new()
	gesicht.name_ = str(p.get("name", ""))
	gesicht.farbe = Profiles.color_of(p)
	gesicht.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(gesicht)
	_buehne.fokus(gesicht)
	col.add_child(U.spacer(0, 36, false))
	var title := Label.new()
	title.text = "Wer spielt?"
	title.add_theme_font_override("font", UzTheme.display("title"))
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", UzTheme.col("text"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	col.add_child(U.spacer(0, 10, false))
	var wer := U.label(str(p.get("name", "")), "xl", "text", "bold")
	wer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(wer)
	col.add_child(U.spacer(0, 6, false))
	var tag := U.label("So heißt du auf der Startseite und bei Freunden.", "m", "muted", "regular", true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	col.add_child(U.spacer(0, 40, false))
	# Farben: eine Reihe runder Felder, die gewählte trägt den Ring. Wirkt sofort auf das Bild oben.
	var farben := U.hbox(14)
	farben.alignment = BoxContainer.ALIGNMENT_CENTER
	farben.set_meta("uz_row", true)
	col.add_child(farben)
	var felder: Array = []
	for c in Profiles.COLORS:
		var f := _Farbfeld.new()
		f.kennung = str(c[0])
		f.farbe = c[2]
		f.gewaehlt = str(c[0]) == str(p.get("color", Profiles.COLORS[0][0]))
		f.set_meta("uz_key", "su:farbe:" + str(c[0]))
		f.set_meta("uz_hint_a", "Auswählen")
		f.gewollt.connect(func() -> void:
			Config.update_profile(pid, { "color": f.kennung })
			gesicht.farbe = f.farbe
			gesicht.queue_redraw()
			for x in felder:
				x.gewaehlt = x == f
				x.queue_redraw()
			Sfx.play("toggle_on"))
		felder.append(f)
		farben.add_child(f)
	col.add_child(U.spacer(0, 34, false))
	var row := U.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var go := _knopf("Weiter")
	go.custom_minimum_size = Vector2(300, 64)
	go.set_meta("uz_hint_a", "Weiter")
	go.set_meta("uz_key", "su:du_weiter")
	go.pressed.connect(func() -> void: _go("weiter"))
	row.add_child(go)
	var um := _knopf("Name ändern", "edit")
	um.custom_minimum_size = Vector2(0, 64)
	um.set_meta("uz_key", "su:name")
	um.set_meta("uz_hint_a", "Ändern")
	um.pressed.connect(func() -> void:
		main.open_keyboard("Dein Name", str(Config.profile().get("name", "")), func(t: String) -> void:
			var neu := Profiles.clean_name(t)
			if neu == "" or not Config.update_profile(pid, { "name": neu }):
				return
			if is_instance_valid(wer):
				wer.text = neu
			if is_instance_valid(gesicht):
				gesicht.name_ = neu
				gesicht.queue_redraw()))
	row.add_child(um)
	# Heißt das Profil noch „Spieler 1“, liegt die Auswahl auf dem Namen – sonst geht A einfach weiter.
	_default = um if E.name_ist_standard(str(p.get("name", ""))) else go
	if resume.is_empty():
		_steigen([title, wer, tag, farben, row], 0.1)


## Das Profilbild im Großen: eine Scheibe in der Profilfarbe mit dem Anfangsbuchstaben, darum ein
## weicher Schein in derselben Farbe.
class _Gesicht extends Control:
	const PX := 190.0
	var name_ := ""
	var farbe := Color.WHITE

	func _ready() -> void:
		custom_minimum_size = Vector2(PX, PX)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var m := size * 0.5
		var r := PX * 0.5
		for i in 6:
			draw_circle(m, r + 10.0 + i * 9.0, Color(farbe, 0.06 - i * 0.009), true, -1.0, true)
		draw_circle(m, r, farbe, true, -1.0, true)
		draw_arc(m, r - 1.5, 0.0, TAU, 96, Color(1, 1, 1, 0.22), 3.0, true)
		var buchstabe := name_.strip_edges().left(1).to_upper()
		if buchstabe == "":
			return
		var font := UzTheme.display("title")
		var gr := int(PX * 0.5)
		var w := font.get_string_size(buchstabe, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x
		draw_string(font, Vector2(m.x - w * 0.5, m.y + gr * 0.36), buchstabe, HORIZONTAL_ALIGNMENT_LEFT, -1, gr, UzTheme.text_on(farbe))


## Ein rundes Farbfeld der Auswahl: gewählt mit Ring, mit dem Cursor etwas größer.
class _Farbfeld extends Control:
	signal gewollt
	const PX := 52.0
	var kennung := ""
	var farbe := Color.WHITE
	var gewaehlt := false

	func _ready() -> void:
		custom_minimum_size = Vector2(PX + 12.0, PX + 12.0)
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		gui_input.connect(func(e: InputEvent) -> void: Nav.klick(self, e))

	func activate() -> void:
		gewollt.emit()

	func _draw() -> void:
		var m := size * 0.5
		var r := PX * 0.5 * (1.0 if has_focus() else 0.84)
		if has_focus():
			draw_arc(m, r + 5.0, 0.0, TAU, 64, UzTheme.col("focus"), 3.0, true)
		draw_circle(m, r, farbe, true, -1.0, true)
		if gewaehlt:
			var ink := UzTheme.text_on(farbe)
			draw_polyline(PackedVector2Array([m + Vector2(-8, 0), m + Vector2(-2.5, 6), m + Vector2(8.5, -6.5)]), ink, 3.2, true)


## Sprache wechseln: speichern, die Übersetzung sofort tauschen und die Oberfläche neu bauen – die
## Einrichtung öffnet sich danach an derselben Stelle wieder (wie beim Farbschema).
func _set_language(code: String) -> void:
	if code == str(Config.get_value("system.language", "de")):
		Sfx.play("select")
		return
	Config.set_value("system.language", code)
	Config.save_settings()
	Lang.release()
	Lang.apply(code)
	_last_key = "su:lang:" + code
	Sfx.play("toggle_on")
	UzTheme.crossfade()
	UzTheme.rebuilt.emit()


# --- Controller (still) -------------------------------------------------------------------

## Der Controller wird still erkannt (kein eigener Schritt; Koppeln und der Test aller Tasten liegen
## unter Einstellungen → Controller): sobald einer verbunden ist oder benutzt wird. Der Name steht
## am Ende in der Bilanz unter „Alles bereit“.
func _erkennen() -> void:
	var pads := not Input.get_connected_joypads().is_empty() or probe_pad
	var nm := ""
	if Nav.device == "pad" or pads:
		nm = Nav.pad_name if Nav.pad_name != "" else ("Controller" if _detected in ["", "Tastatur"] else _detected)
	else:
		nm = "Tastatur"
	if nm == _detected:
		return
	_detected = nm
	Config.set_value("einrichtung.pad", _detected)


## Aussehen: Akzentfarbe, Menüklänge und Größe der Oberfläche. Alles wirkt sofort.
const AUSSEHEN_LINKS := 740.0


# --- 3 Darstellung --------------------------------------------------------------------------

func _darstellung() -> void:
	var sk := _skeleton("palette", "Aussehen", "Akzentfarbe, Klänge und Größe.", AUSSEHEN_LINKS)
	var left: VBoxContainer = sk.left
	var acc := str(Config.get_value("theme.accent", ""))
	_head(left, "Akzentfarbe", "Eigene" if acc != "" else "Vom Farbschema")
	var arow := HFlowContainer.new()
	arow.add_theme_constant_override("h_separation", 6)
	arow.add_theme_constant_override("v_separation", 6)
	left.add_child(arow)
	var list: Array = [""]
	list.append_array(ACCENTS)
	list.append("eigen")
	for a in list:
		var s2 := _Swatch.new()
		s2.kind = "auto" if a == "" else ("custom" if a == "eigen" else "accent")
		s2.id = str(a)
		s2.on = (a == "" and acc == "") or (a != "" and a != "eigen" and acc.to_lower() == str(a).to_lower()) \
				or (a == "eigen" and acc != "" and not ACCENTS.has(acc.to_lower()))
		s2.set_meta("uz_key", "su:a:" + str(a))
		s2.set_meta("uz_hint_a", "Eigene wählen" if a == "eigen" else "Übernehmen")
		var aid := str(a)
		s2.activated.connect(func() -> void:
			if aid == "eigen":
				main.open_color_picker("Akzentfarbe", UzTheme.col("accent"), func(c: Color) -> void: Config.set_value("theme.accent", "#" + c.to_html(false)))
			elif str(Config.get_value("theme.accent", "")).to_lower() != aid.to_lower():
				Config.set_value("theme.accent", aid)
		)
		arow.add_child(s2)
	left.add_child(U.spacer(0, 26, false))
	var rows := _card(left)
	var on_snd := bool(Config.get_value("theme.sounds", true))
	var snd = _row(rows, "slider", "Menüklänge", "Klänge beim Bewegen", "", float(Config.get_value("theme.sound_volume", 0.6))
			if on_snd else 0.0)
	snd.min_v = 0.0
	snd.max_v = 1.0
	snd.step = 0.1
	snd.icon_name = "volume"
	snd.changed.connect(func(v: Variant) -> void:
		var f := float(v)
		Config.set_value("theme.sounds", f > 0.001)
		if f > 0.001:
			Config.set_value("theme.sound_volume", f)
			Sfx.play("select")
	)
	# Größe der Oberfläche: beim ersten Start schon passend zum erkannten Bildschirm (main →
	# display_fit.gd); der Regler wirkt sofort auf alles.
	var seen := DisplayFit.summary(Config.get_value("display.seen", {}), true)
	var sz = _row(rows, "slider", "Größe", seen if seen != "" else "Je nach Abstand",
		"", float(Config.get_value("theme.ui_scale", 1.0)), func(r: Control) -> void:
			r.min_v = 0.8
			r.max_v = UzTheme.SCALE_MAX
			r.step = 0.05
			r.icon_name = "tv")
	sz.changed.connect(func(v: Variant) -> void: Config.set_value("theme.ui_scale", float(v)))
	if _default == null:
		_default = Nav.default_in(arow)


## Das Zeichen im Willkommen, genau wie im Intro: dieselben Zeichenfunktionen und Maße wie
## boot.gd (Boot.zeichen, Boot.wort_unter, Boot.marke_mass) – das U-Band frei ohne Kachel in den
## Markenfarben, die Linie zieht sich, die Bänder setzen sich, das Ganze setzt sich von 106 % auf
## seine Größe; darunter klein, flach und weit gesperrt die Wortmarke im hellen Grau (im hellen
## Farbschema im Ton der Schrift, sonst wäre sie unsichtbar). Das Licht dahinter macht die Bühne
## (fokus). „Animationen reduzieren“: beides blendet nur ein.
class _Marke extends Control:
	const BootM := preload("res://src/ui/boot.gd")
	const Form := preload("res://src/ui/marke_form.gd")
	const UU := preload("res://src/ui/u.gd")
	## Bis hierhin steht alles (s nach dem Start von play): die Wortmarke ist da.
	const STEHT := BootM.NAME_AT + BootM.NAME_S
	var u_h := 230.0
	var t := 99.0
	var _ruhig := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ruhig = UU.reduziert()
		custom_minimum_size = BootM.marke_mass(u_h)
		set_process(false)

	func play(delay := 0.0) -> void:
		t = -delay
		set_process(true)
		queue_redraw()

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()
		if t > BootM.LAENGE:
			set_process(false)

	## Mitte des U in eigenen Koordinaten (dort steht das Licht der Bühne).
	func licht_mitte() -> Vector2:
		return Vector2(size.x * 0.5, u_h * 0.5)

	## Der tiefste Punkt der Linie (Grund des Bogens) in eigenen Koordinaten.
	func licht_pos() -> Vector2:
		var cy := -Form.H * 0.5 + Form.B * 0.5
		var rx := Form.B * 0.5 - Form.STRICH * 0.5
		return licht_mitte() + Vector2(0, -(cy - rx)) * u_h / Form.H

	func _draw() -> void:
		if t < 0.0:
			return
		var ph := BootM.phasen(t)
		var a := 1.0
		var name_a := float(ph.name)
		if _ruhig:
			var r := BootM.phasen_ruhig(t + BootM.R_ZEICHEN_AT)
			ph = BootM.phasen(99.0)
			a = float(r[0])
			name_a = float(r[1])
		var mass := lerpf(1.0, BootM.MASS_VON, float(ph.mass))
		BootM.zeichen(self, licht_mitte(), u_h * mass, ph, a, UzTheme.boot_color("accent"))
		BootM.wort_unter(self, licht_mitte(), u_h, clampf(name_a, 0.0, 1.0) * a, UzTheme.col("text") if UzTheme.light else BootM.WORT_FARBE)
