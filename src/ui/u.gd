extends RefCounted
## Kleine Bausteine, damit sich die Oberfläche kurz und lesbar im Code aufbauen lässt.

const Glyph := preload("res://src/ui/components/glyph.gd")
const Lang := preload("res://src/core/lang.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Raster := preload("res://src/core/raster.gd")


static func label(text: String, size := "m", color := "text", weight := "regular", wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	# Titel schmal und fett in Saira, Überschriften und Bedienelemente in Saira normal breit,
	# Sätze in der gut lesbaren Grundschrift (siehe docs/DESIGN.md).
	if weight == "title":
		l.add_theme_font_override("font", UzTheme.display("title"))
	elif size in ["xl", "xxl", "hero"] and weight in ["bold", "black"]:
		l.add_theme_font_override("font", UzTheme.display(weight))
	elif size == "l" and weight in ["bold", "black"]:
		l.add_theme_font_override("font", UzTheme.ui("ui_bold"))
	else:
		l.add_theme_font_override("font", UzTheme.font(weight))
	l.add_theme_font_size_override("font_size", UzTheme.size(size) if size in UzTheme.SIZE else int(size))
	l.add_theme_color_override("font_color", UzTheme.col(color))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Text kürzen statt Platz einzufordern (für Spalten mit fester Breite).
## Weicher Schlagschatten unter großer Schrift (Titel über Bildern).
## Schatten unter Schrift auf Bildern. Godot zeichnet Schriftschatten nicht weich; ein dicker
## Umriss wirkt wie ein dunkler Hof. Darum schmal, leicht versetzt und eher hell.
static func shadow(l: Label, strength := 0.55) -> Label:
	# Dunkle Schrift (helle Themes) bekommt einen zarten hellen Hof statt eines dunklen Schattens –
	# der lag dort wie Schmutz unter den Buchstaben. Helle Schrift behält ihren Schatten.
	var dark_ink := l.get_theme_color("font_color").get_luminance() < 0.5
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, strength * 0.45) if dark_ink else Color(0, 0, 0, strength * 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	return l


static func ellipsis(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func set_label_color(l: Label, color: String, alpha := 1.0) -> void:
	l.add_theme_color_override("font_color", UzTheme.col(color, alpha))


static func icon(name: String, px := 24, color := "text") -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.tex(name, px)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = UzTheme.col(color)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_meta("uz_icon", true)
	return t


## --- Takt (docs/DESIGN.md › Bewegung): fünf Zeiten mit Bedeutung ---------------------------
## Antwort auf einen Druck: Cursor, Eindrücken, Schalter, Rand-Anstoß, Hinweis-Tausch.
const T_ANTWORT := 0.09
## Was geht: Ausblenden, Schließen, alter Inhalt.
const T_WEG := 0.16
## Ortswechsel in einer Ebene: Unterbereich, App, Reiterstrich, Guide-Leiste.
const T_ORT := 0.2
## Wechsel der Ebene oder des Raums: Bereich LT/RT, Seitenleiste, Dialog, Seite, Spielstart.
const T_RAUM := 0.36
## Nur Hintergrund: Raumfarbe, Lichter, Parallaxe.
const T_LICHT := 0.8
## Staffeln: höchstens STAFFEL_MAX Glieder im Abstand STAFFEL, der Rest kommt mit dem letzten.
const STAFFEL := 0.03
const STAFFEL_MAX := 4
## Wege in Pixeln: Anstoß am Rand, Ortswechsel, Bereichswechsel, Seitenleiste.
const W_ANSTOSS := 6.0
const W_ORT := 24.0
const W_BEREICH := 56.0
const W_LEISTE := 72.0
## Schrift folgt ihrer Fläche um so viel später (Fläche vor Schrift).
const NACH_FLAECHE := 0.04
## Erst gehen, dann kommen: das Neue beginnt ein Bild nach dem Druck. Übereinander decken zwei
## Deckkräfte nicht ihre Summe, sondern a_neu + a_alt · (1 − a_neu): 0,63 (alt) und 0,23 (neu) sind
## nur 0,72 – gemessen ein dunkles Zwinkern über drei Bilder. Darum geht Altes, an dessen Stelle
## sofort Neues kommt, mit der Kurve „Kreuzen“ (U.kreuzen): es hält dieses eine Bild und blendet
## dann sanft (sine in-out) in T_WEG aus, das Neue kommt im selben Bild mit „Ankommen“. So decken
## beide zusammen in jedem Bild mindestens 85 % (tests/logic_kreuzen.gd).
const NACH_WEG := 1.0 / 60.0
## Ruhig (Animationen reduzieren): alles läuft so viel schneller (360 ms → 180, 200 → 100).
const RUHIG_TEMPO := 2.0

## Die alten Namen bleiben mit ihren heutigen Werten, bis jede Stelle bewusst umgestellt ist.
const FOCUS_IN := 0.16
const FOCUS_OUT := 0.2
const T_PRESS := 0.07
const T_FAST := 0.12
const T_EXIT := 0.16
const T_BASE := 0.2
const T_FOCUS := 0.26
const T_MOVE := 0.3
const T_ENTER := 0.36
const T_AMBIENT := 0.8
const STAGGER := 0.045
## Feder fürs Scrollen und Gleiten (kritisch gedämpft): größer = straffer. 22 setzt sich nach
## einem Schritt in etwa 0,3 s, ohne nachzuschwingen. Beim Halten (Schritte dicht hintereinander)
## wird sie weicher (SPRING_HOLD): die Liste gleitet dann fast gleichmäßig statt zu pumpen.
const SPRING := 22.0
const SPRING_HOLD := 16.0


## Neuer Tween für node unter key; ein laufender wird vorher beendet (nie zwei auf einer Eigenschaft).
## Standard ist die Kurve „Ankommen“ (ease-out cubic).
static func tw(n: Node, key := "uz_tw", trans := Tween.TRANS_CUBIC, ease := Tween.EASE_OUT) -> Tween:
	var old: Variant = n.get_meta(key) if n.has_meta(key) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := n.create_tween().set_trans(trans).set_ease(ease)
	t.set_speed_scale(tempo())
	n.set_meta(key, t)
	return t


## Für Stellen, die ihren Tween selbst bauen (create_tween mit eigener Kurve oder mehreren Spuren): gibt ihm das
## Tempo aller anderen (tempo(): leichter Modus, „Animationen reduzieren“) – sonst liefe genau diese Bewegung als
## einzige im gewöhnlichen Tempo weiter. Kurve, Ziel und Reihenfolge bleiben. Nicht für Abläufe mit eigener Zeit
## (Start eines Spiels, Bildschirmschoner, Begrüßung).
static func im_tempo(t: Tween) -> Tween:
	t.set_speed_scale(tempo())
	return t


## --- Die Kurven -------------------------------------------------------------------------
## 1. Ankommen: ease-out cubic bis T_ORT, quart ab T_RAUM – schnell da, weich gesetzt (U.ankommen).
## 2. Gehen: Deckkraft ease-out quad (U.weg), wenn nichts an die Stelle tritt (Ebene schließt,
##    Mitteilung geht). Nie ease-in auf Deckkraft, das endet mit einem Ruck; ease-in nur für Wege,
##    auf denen ein Element den Schirm ganz verlässt.
## 2b. Kreuzen: Deckkraft sine in-out in T_WEG, NACH_WEG verzögert (U.kreuzen, U.kreuz_aus), wenn
##    im selben Bild Neues an die Stelle kommt (Bereich, Unterbereich, App, Bibliothek). In-out endet
##    mit Tempo 0 – kein Ruck im letzten Bild; der Weg dazu bleibt ease-out und beginnt sofort.
## 3. Folgen: kritisch gedämpfte Feder (U.spring_step), sobald sich ein Ziel unterwegs ändern kann.

## Kurve „Ankommen“ passend zur Dauer.
static func trans_ankommen(dur: float) -> Tween.TransitionType:
	return Tween.TRANS_QUART if dur >= T_RAUM - 0.001 else Tween.TRANS_CUBIC


## Tween mit der Kurve „Ankommen“ für eine Bewegung der Länge dur.
static func ankommen(n: Node, dur := T_ORT, key := "uz_tw") -> Tween:
	return tw(n, key, trans_ankommen(dur), Tween.EASE_OUT)


## Tween mit der Kurve „Gehen“ (Deckkraft ease-out quad).
static func weg(n: Node, key := "uz_tw") -> Tween:
	return tw(n, key, Tween.TRANS_QUAD, Tween.EASE_OUT)


## Tween mit der Kurve „Kreuzen“ (sine in-out) – für Altes, an dessen Stelle sofort Neues kommt.
## Die Deckkraft geht damit in T_WEG und beginnt NACH_WEG später (U.kreuz_aus), Wege im selben
## Tween setzen ihre Kurve selbst (ease-out).
static func kreuzen(n: Node, key := "uz_tw") -> Tween:
	return tw(n, key, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


## Deckkraft von n in einem laufenden Tween t mit der Kurve „Kreuzen“ auf 0 (T_WEG, NACH_WEG
## verzögert). Für Tweens, die daneben einen Weg mit „Gehen“ oder „Ankommen“ tragen.
static func kreuz_aus(t: Tween, n: CanvasItem) -> PropertyTweener:
	return t.tween_property(n, "modulate:a", 0.0, T_WEG).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(NACH_WEG)


## Wert einer Kurve bei Anteil x (0…1) – für Tests und eigene _process-Bewegungen.
## art: "ankommen" (cubic), "raum" (quart), "gehen" (quad), "kreuzen" (sine in-out).
static func kurve(art: String, x: float) -> float:
	var tr := Tween.TRANS_CUBIC
	var ea := Tween.EASE_OUT
	match art:
		"raum":
			tr = Tween.TRANS_QUART
		"gehen":
			tr = Tween.TRANS_QUAD
		"kreuzen":
			tr = Tween.TRANS_SINE
			ea = Tween.EASE_IN_OUT
	return float(Tween.interpolate_value(0.0, 1.0, clampf(x, 0.0, 1.0), 1.0, tr, ea))


## --- Pixel-Schluss -------------------------------------------------------------------------
## Die Oberfläche steht in ganzen Pixeln (project.godot: snap_2d_transforms_to_pixel). Ein langer
## Ausläufer (quart) verteilt die letzten 1–2 px über 100 ms: 1 px, Stillstand, 1 px – ein spätes
## Nachrucken, wenn sonst alles steht. px_schluss rundet den Weg und rückt je Bild mindestens 1 px
## näher an 0, nie zurück: Die Bewegung endet mit kleinen Schritten statt einer Treppe.

## Wert v (Rest des Wegs bis 0, in px) für das nächste Bild; key: Meta an n mit dem letzten Wert.
## Vor der Bewegung den Anfang setzen: n.set_meta(key, roundf(von)).
## Ein Schritt ist ein Schritt des Rasters (src/core/raster.gd): ein Punkt, an 4K ein Bildpunkt.
static func px_schluss(n: Object, key: String, v: float) -> float:
	var g := Raster.schritt
	var r := Raster.rund(v)
	var alt := float(n.get_meta(key, r))
	if absf(alt) < g * 0.5 or r * alt < 0.0:
		r = 0.0
	elif absf(r) >= absf(alt):
		r = Raster.rund(alt - signf(alt) * g)
	n.set_meta(key, r)
	return r


## Tween-Methode für einen Weg von px bis 0 in ganzen Pixeln (px_schluss), die setzen(p) aufruft.
## Gibt den Tweener zurück (für set_delay).
static func px_weg(t: Tween, n: Object, key: String, von: float, dauer: float, setzen: Callable) -> MethodTweener:
	n.set_meta(key, Raster.rund(von))
	return t.tween_method(func(v: float) -> void:
		if is_instance_valid(n):
			setzen.call(px_schluss(n, key, v))
	, von, 0.0, dauer)


## --- Arbeit in Scheiben -----------------------------------------------------------------------
## Was man nicht gleich sieht (Cover weiter rechts, Abschnitte unter dem Bildschirm), baut nicht im Tastendruck,
## sondern in den nächsten Bildern: je Bild höchstens SCHEIBE_MS, mindestens ein Schritt. Bei 120 Hz hat ein Bild
## 8,3 ms – ein Wechsel, der alles auf einmal baut, ließ zwei bis sechs Bilder aus (gemessen am 17.11.).
const SCHEIBE_MS := 3.0


## schritte (Callables) nach diesem Bild ausführen, solange anker im Baum ist (wird er frei, endet es). Ohne Baum
## (Tests, unsichtbarer Aufbau) alles sofort.
static func nach_und_nach(anker: Node, schritte: Array, budget_ms := SCHEIBE_MS) -> void:
	if schritte.is_empty():
		return
	if anker == null or not anker.is_inside_tree():
		for s in schritte:
			(s as Callable).call()
		return
	var baum := anker.get_tree()
	var i := 0
	while i < schritte.size():
		await baum.process_frame
		if not is_instance_valid(anker) or not anker.is_inside_tree():
			return
		var t0 := Time.get_ticks_usec()
		(schritte[i] as Callable).call()
		i += 1
		while i < schritte.size() and float(Time.get_ticks_usec() - t0) < budget_ms * 1000.0:
			(schritte[i] as Callable).call()
			i += 1


## --- Ruhig und leicht --------------------------------------------------------------------

## „Animationen reduzieren“ (theme.reduce_motion). Die einzige Stelle, die das liest: 0 px Weg,
## kein Wachsen, Federn sofort am Ziel, kurze Dauern; Überblenden bleibt (sonst harte Schnitte).
## Heißt nicht ruhig(), weil U.ruhig(button) schon der ruhige Knopf der Listen-Sprache ist.
static func reduziert() -> bool:
	return bool(Config.get_value("theme.reduce_motion", false))


## Tempo aller Tweens aus U.tw: leichter Modus 1,4 (weniger Bilder), ruhig doppelt so schnell.
static func tempo() -> float:
	var s := 1.0
	if Leicht.active:
		s *= Leicht.ANIM_SPEED
	if reduziert():
		s *= RUHIG_TEMPO
	return s


## Weg in Pixeln, der im ruhigen Modus 0 wird.
static func weg_px(px: float) -> float:
	return 0.0 if reduziert() else px


## Wachsen (Skalierung von → 1): im ruhigen Modus kein Wachsen.
static func wachsen(von: float) -> float:
	return 1.0 if reduziert() else von


## Verzögerung im i-ten Glied einer Staffel (höchstens STAFFEL_MAX Glieder, ruhig ohne Staffel).
static func staffel(i: int) -> float:
	if reduziert():
		return 0.0
	return mini(maxi(i, 0), STAFFEL_MAX - 1) * STAFFEL


## --- Ortswechsel ohne Leerbild: erst gehen, dann kommen -------------------------------------

## Teil 1: die bisherigen Kinder von host gehen. Sie wandern in eine Hülle mit gleicher Lage auf
## dem Schirm, außerhalb des Layouts (beim nächsten Vorfahren, der kein Container ist, darum ändert
## der neue Inhalt nichts an ihr), die in T_WEG um W_ORT gegen dir gleitet, ausblendet und sich
## danach freigibt. host ist sofort leer für den neuen Inhalt; die Hülle ist für die Steuerung
## nicht da (uz_skip). dir: +1 = Neues kommt von rechts (Altes geht nach links), -1 umgekehrt,
## 0 = nur blenden. kreuzen: Neues kommt im selben Bild an die Stelle (U.ankunft) – die Hülle geht
## mit der Kurve „Kreuzen“, große Titel darin (Meta "uz_titel") weichen zuerst (titel_weichen);
## false: Kurve „Gehen“ (die Hülle ist selbst Schrift, etwa der Kopf der Apps).
## Gibt die Hülle zurück (null, wenn nichts zu sehen war: dann ist host nur leer).
static func abgang(host: Control, dir := 1, kreuzen := true) -> Control:
	abgang_ende(host)
	var kids: Array = host.get_children()
	var ziel := _ohne_layout(host)
	var sicht := sichtbar(host) if host.is_inside_tree() and host.is_visible_in_tree() else Rect2()
	if kids.is_empty() or ziel == null or sicht.size.x < 1.0 or sicht.size.y < 1.0:
		for ch in kids:
			host.remove_child(ch)
			ch.queue_free()
		return null
	var h := Control.new()
	h.name = "UzAbgang"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.focus_mode = Control.FOCUS_NONE
	h.set_meta("uz_skip", true)
	h.clip_contents = true
	# Lage in ziel: das sichtbare Stück von host, in ziel-Koordinaten.
	var inv := ziel.get_global_transform().affine_inverse()
	var hxf := host.get_global_transform()
	var sc := hxf.get_scale() / ziel.get_global_transform().get_scale()
	sc = Vector2(maxf(sc.x, 0.001), maxf(sc.y, 0.001))
	ziel.add_child(h)
	h.position = inv * sicht.position
	h.scale = sc
	h.size = (inv.basis_xform(sicht.size)) / sc
	# Die eigene Deckkraft von host (zwischen ziel und host) nimmt die Hülle mit.
	var m := Color.WHITE
	var n: Node = host
	while n != null and n != ziel:
		if n is CanvasItem:
			m *= (n as CanvasItem).modulate
		n = n.get_parent()
	h.modulate = m
	var innen := (hxf.origin - sicht.position) / (hxf.get_scale())
	for ch in kids:
		var c := ch as Control
		var pos := c.position if c else Vector2.ZERO
		var size := c.size if c else Vector2.ZERO
		host.remove_child(ch)
		h.add_child(ch)
		if c:
			c.set_meta("uz_skip", true)
			c.anchor_left = 0.0
			c.anchor_top = 0.0
			c.anchor_right = 0.0
			c.anchor_bottom = 0.0
			c.position = pos + innen
			c.size = size
	host.set_meta("uz_abgang_h", h)
	var x0 := h.position.x
	var t := weg(h, "uz_abgang_tw").set_parallel(true)
	if kreuzen:
		kreuz_aus(t, h)
		titel_weichen(h)
	else:
		t.tween_property(h, "modulate:a", 0.0, T_WEG)
	if dir != 0 and not reduziert():
		t.tween_property(h, "position:x", x0 - W_ORT * dir, T_WEG).set_trans(Tween.TRANS_CUBIC)
	t.chain().tween_callback(func() -> void:
		if is_instance_valid(h):
			h.queue_free()
	)
	takt_halten(t)
	return h


## Ein einzelnes Element verlässt seinen Platz im Layout und kreuzt dort aus, wo es gerade auf dem
## Schirm steht (Kurve „Kreuzen“) – an seine Stelle kommt im selben Bild Neues (U.ankunft). Es
## wandert zum nächsten Vorfahren, der kein Container ist, ohne Beschnitt (Spiegelungen und
## gewachsene Karten bleiben ganz), ist für die Steuerung sofort weg (uz_skip) und gibt sich danach
## frei. Unsichtbar: gleich weg.
static func abheben(c: Control) -> void:
	if not is_instance_valid(c):
		return
	var alt := c.get_parent()
	var ziel := _ohne_layout(c)
	if alt == null or ziel == null or not c.is_inside_tree() or not c.is_visible_in_tree():
		if alt:
			alt.remove_child(c)
		c.queue_free()
		return
	var xf := c.get_global_transform()
	var sz := c.size
	var m := c.modulate
	var n: Node = alt
	while n != null and n != ziel:
		if n is CanvasItem:
			m *= (n as CanvasItem).modulate
		n = n.get_parent()
	var inv := ziel.get_global_transform().affine_inverse()
	alt.remove_child(c)
	ziel.add_child(c)
	c.set_meta("uz_skip", true)
	c.focus_mode = Control.FOCUS_NONE
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.position = inv * xf.origin
	c.size = sz
	c.modulate = m
	var t := weg(c, "uz_abheben")
	kreuz_aus(t, c)
	titel_weichen(c)
	t.chain().tween_callback(c.queue_free)


## Der große Titel weicht zuerst: Elemente mit der Meta "uz_titel" unter root (Titel eines
## Bereichs, Schriftzug des gewählten Spiels) gehen in T_ANTWORT mit der Kurve „Gehen“, während
## der Rest kreuzt – zwei große Titel stehen nie übereinander. Schrift und Bild (Label,
## TextureRect) über ihre eigene Deckkraft (self_modulate), sonst über modulate. Wer den Titel
## behält (Bereich kommt zurück), ruft titel_zurueck.
static func titel_weichen(root: Node) -> void:
	for n in _titel_unter(root, []):
		var ci := n as CanvasItem
		var prop := "self_modulate:a" if (ci is Label or ci is TextureRect) else "modulate:a"
		weg(ci, "uz_titel_tw").tween_property(ci, prop, 0.0, T_ANTWORT)


## Titel unter root wieder ganz da (nach titel_weichen); verz ≥ 0: sanft in T_ORT nach verz.
static func titel_zurueck(root: Node, verz := -1.0) -> void:
	for n in _titel_unter(root, []):
		var ci := n as CanvasItem
		var prop := "self_modulate:a" if (ci is Label or ci is TextureRect) else "modulate:a"
		if verz >= 0.0:
			ankommen(ci, T_ORT, "uz_titel_tw").tween_property(ci, prop, 1.0, T_ORT).set_delay(verz)
			continue
		stop(ci, "uz_titel_tw")
		if ci is Label or ci is TextureRect:
			ci.self_modulate.a = 1.0
		else:
			ci.modulate.a = 1.0


static func _titel_unter(n: Node, out: Array) -> Array:
	for ch in n.get_children():
		var v: Variant = ch.get_meta("uz_titel", false)
		if ch is CanvasItem and v is bool and v:
			out.append(ch)
		elif ch.get_child_count() > 0:
			_titel_unter(ch, out)
	return out


static func _ohne_layout(c: Node) -> Control:
	var p := c.get_parent()
	while p != null:
		if p is Control and not (p is Container):
			return p as Control
		p = p.get_parent()
	return null


## Eine laufende Hülle von abgang() sofort entfernen (neuer Wechsel, Neuaufbau).
static func abgang_ende(host: Control) -> void:
	if not is_instance_valid(host) or not host.has_meta("uz_abgang_h"):
		return
	var h: Variant = host.get_meta("uz_abgang_h")
	host.remove_meta("uz_abgang_h")
	if is_instance_valid(h) and h is Control and not (h as Control).is_queued_for_deletion():
		stop(h as Control, "uz_abgang_tw")
		(h as Control).get_parent().remove_child(h)
		(h as Control).queue_free()


## Teil 2: der neue Inhalt von host kommt gleich danach (NACH_WEG) in T_ORT, um W_ORT (weg) aus der
## Richtung dir gleitend (über die Ränder bzw. position.x, wie es der Platz von host erlaubt), und
## blendet dabei auf. Es gibt keine leere Phase: bis er beginnt, liegt der alte Inhalt noch da.
static func ankunft(host: Control, dir := 1, dauer := T_ORT, verz := NACH_WEG, weg := W_ORT) -> void:
	if not is_instance_valid(host):
		return
	stop(host, "uz_ankunft")
	var px := weg_px(weg) * dir
	host.modulate.a = 0.0
	var t := ankommen(host, dauer, "uz_ankunft").set_parallel(true)
	takt_halten(t)
	t.tween_property(host, "modulate:a", 1.0, dauer).set_delay(verz)
	var anchored := not (host.get_parent() is Container)
	# Unterbrochen (schneller zweiter Wechsel): von der gemerkten Ruhelage aus, sonst wanderte sie.
	var base: float = host.get_meta("uz_ank_base") if host.has_meta("uz_ank_base") else (host.offset_left if anchored else host.position.x)
	if px != 0.0:
		host.set_meta("uz_ank_base", base)
		var setx := func(v: float) -> void:
			if not is_instance_valid(host):
				return
			if anchored:
				var w := host.offset_right - host.offset_left
				host.offset_left = base + v
				host.offset_right = base + v + w
			else:
				host.position.x = base + v
		setx.call(px)
		t.tween_method(setx, px, 0.0, dauer).set_delay(verz)
		t.chain().tween_callback(func() -> void:
			if is_instance_valid(host) and host.has_meta("uz_ank_base"):
				host.remove_meta("uz_ank_base")
		)
	elif host.has_meta("uz_ank_base"):
		# Ruhig nach einem unterbrochenen Wechsel: gleich an die Ruhelage.
		if anchored:
			var w2 := host.offset_right - host.offset_left
			host.offset_left = base
			host.offset_right = base + w2
		else:
			host.position.x = base
		host.remove_meta("uz_ank_base")


## Ein langes Bild überspringt keine Bewegung: Ein Ortswechsel baut im Bild des Drucks den neuen
## Inhalt; dieses Bild (Aufbau, Layout, erstes Zeichnen) kann lang werden, und der Tween holte die
## ganze Zeit im nächsten Bild auf einmal nach – das Hereingleiten sprang oder fiel ganz aus
## („Profil-Unterbereiche ruckeln nicht nur, sie springen“). Darum steht t in den ersten
## TAKT_BILDER Bildern still, wenn eines deutlich länger war als das Bild davor (mindestens
## TAKT_SPRUNG), und läuft danach dort weiter, wo es war. Ein Rechner, auf dem jedes Bild lang
## ist, wartet so nicht: es zählt der Sprung, nicht die Länge.
const TAKT_SPRUNG := 0.045
const TAKT_BILDER := 2


static func takt_halten(t: Tween) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or t == null:
		return
	var grenze := maxf(TAKT_SPRUNG, tree.root.get_process_delta_time() * 2.0)
	var angehalten := false
	for i in TAKT_BILDER:
		await tree.process_frame
		if not t.is_valid():
			return
		# Die Zeit, die die Tweens in diesem Bild nachholen würden (vor ihnen gemessen).
		var lang := tree.root.get_process_delta_time() > grenze
		if lang and t.is_running():
			t.pause()
			angehalten = true
		elif not lang and angehalten:
			t.play()
			angehalten = false
	if angehalten:
		await tree.process_frame
		if t.is_valid():
			t.play()


## Material „Kernlicht“ (UzTheme.kernlicht): Kommt die Fläche an, glänzt ihre Lichtkante einmal auf –
## ein Licht, das von der Seite der Lampe über die Kante streift (T_LICHT, sine in-out), während die
## Fläche sich setzt. Ruhig (Animationen reduzieren) und ohne Material: nichts.
static func aufglanz(c: Control, verz := NACH_FLAECHE) -> void:
	var m := c.material as ShaderMaterial if is_instance_valid(c) else null
	if m == null or reduziert() or m.shader != UzTheme.KERNLICHT:
		return
	var lx := 0.5
	var l: Variant = m.get_shader_parameter("licht")
	if l is Vector2:
		lx = (l as Vector2).x
	var von := -0.4 if lx <= 0.5 else 1.4
	m.set_shader_parameter("glanz", -1.0)
	var t := tw(c, "uz_glanz", Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	t.tween_method(func(v: float) -> void: m.set_shader_parameter("glanz", v), von, 1.0 - von, T_LICHT).set_delay(verz)
	t.tween_callback(func() -> void: m.set_shader_parameter("glanz", -1.0))


## Der Teil eines Elements, der auf dem Schirm wirklich zu sehen ist (geschnitten an allen
## Vorfahren mit clip_contents, z. B. einer Bildlaufliste), in Schirm-Koordinaten.
static func sichtbar(c: Control) -> Rect2:
	var xf := c.get_global_transform()
	var r := Rect2(xf.origin, c.size * xf.get_scale())
	var p := c.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents:
			var pc := p as Control
			var pxf := pc.get_global_transform()
			r = r.intersection(Rect2(pxf.origin, pc.size * pxf.get_scale()))
		p = p.get_parent()
	return r.intersection(Rect2(Vector2.ZERO, view_size()))


## Laufende Bewegung unter key beenden, ohne eine neue anzulegen.
static func stop(n: Node, key := "uz_tw") -> void:
	if not is_instance_valid(n) or not n.has_meta(key):
		return
	var old: Variant = n.get_meta(key)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	n.remove_meta(key)


## Etikett: Schrift und Symbole in einem Element dunkel (auf der hellen Auswahl) bzw. wieder
## normal – weich überblendet, zusammen mit der Auswahlfläche (siehe focus_anim/draw_focus).
static func etikett(root: Node, on: bool, animate := true) -> void:
	if root is Control:
		focus_anim(root as Control, on, animate)
	# Cursor der Marke: die Fläche darunter ist heller Graphit, die Schrift bleibt, wie sie ist –
	# wie im Guide (Nebentext bleibt leise, nichts springt auf Weiß).
	if on and UzTheme.cursor_frame():
		return
	var dark := UzTheme.col("on_focus")
	var dur := T_ANTWORT if animate else 0.0
	for n in root.find_children("*", "", true, false):
		if n is Label:
			var l := n as Label
			if on:
				if not l.has_meta("uz_col"):
					l.set_meta("uz_col", l.get_theme_color("font_color"))
				_tint(l, "theme_override_colors/font_color", dark, dur, false)
			elif l.has_meta("uz_col"):
				_tint(l, "theme_override_colors/font_color", l.get_meta("uz_col"), dur, true)
		elif n is TextureRect and n.has_meta("uz_icon"):
			var t := n as TextureRect
			if on:
				if not t.has_meta("uz_mod"):
					t.set_meta("uz_mod", t.modulate)
				_tint(t, "modulate", dark, dur, false)
			elif t.has_meta("uz_mod"):
				_tint(t, "modulate", t.get_meta("uz_mod"), dur, true)


static func _tint(n: CanvasItem, prop: String, to: Color, dur: float, forget: bool) -> void:
	var old: Variant = (n.get_meta("uz_ctw") if n.has_meta("uz_ctw") else null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var meta := "uz_col" if n is Label else "uz_mod"
	if dur <= 0.0 or not n.is_inside_tree():
		n.set(prop, to)
		if forget:
			n.remove_meta(meta)
		return
	var tw := n.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_speed_scale(tempo())
	tw.tween_property(n, prop, to, dur)
	if forget:
		tw.tween_callback(func() -> void:
			if is_instance_valid(n) and n.has_meta(meta):
				n.remove_meta(meta)
		)
	n.set_meta("uz_ctw", tw)


## Auswahlfläche weich ein- und ausblenden: Stand 0…1 liegt in der Meta "uz_f".
static func focus_anim(c: Control, on: bool, animate := true) -> void:
	var old: Variant = (c.get_meta("uz_ftw") if c.has_meta("uz_ftw") else null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var to := 1.0 if on else 0.0
	if not animate or not c.is_inside_tree():
		c.set_meta("uz_f", to)
		c.queue_redraw()
		return
	# Antwort im ersten Bild (Takt): der neue Cursor steht sofort zu 70 % da und setzt sich in
	# T_ANTWORT, der alte fällt sofort auf 30 % und geht ebenso schnell. Ohne Überschwingen.
	var from: float = c.get_meta("uz_f", 0.0)
	from = maxf(from, 0.7) if on else minf(from, 0.3)
	c.set_meta("uz_f", from)
	c.queue_redraw()
	var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_speed_scale(tempo())
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(c):
			c.set_meta("uz_f", v)
			c.queue_redraw()
	, from, to, T_ANTWORT)
	c.set_meta("uz_ftw", tw)
	# Ein Lichtstreif zieht einmal über das gewählte Element: nur wo draw_shine benutzt wird und das
	# Theme ihn will (Graphit nicht), nie im leichten oder ruhigen Modus.
	if on and c.has_meta("uz_shiny") and not Leicht.active and UzTheme.focus_shine() and not reduziert():
		c.set_meta("uz_shine", 0.0)
		var st := c.create_tween()
		st.tween_interval(0.06)
		st.tween_method(func(v: float) -> void:
			if is_instance_valid(c):
				c.set_meta("uz_shine", v)
				c.queue_redraw()
		, 0.0, 1.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Der Lichtstreif über einem gewählten Bild (schräg, weich, läuft einmal durch).
static func draw_shine(c: Control, r: Rect2) -> void:
	var t: float = c.get_meta("uz_shine", 1.0) if c.has_meta("uz_shine") else 1.0
	if t <= 0.0 or t >= 1.0:
		return
	var w := r.size.x * 0.32
	var x := lerpf(r.position.x - w - r.size.y * 0.5, r.end.x + w, t)
	var skew := r.size.y * 0.45
	var a := 0.2 * sin(PI * t)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var white := Color(1, 1, 1, 0)
	for p in [[x, 0.0], [x + w * 0.5, a], [x + w, 0.0]]:
		pts.append(Vector2(clampf(float(p[0]) + skew, r.position.x, r.end.x), r.position.y))
		cols.append(Color(white, float(p[1])))
	for p in [[x + w, 0.0], [x + w * 0.5, a], [x, 0.0]]:
		pts.append(Vector2(clampf(float(p[0]), r.position.x, r.end.x), r.end.y))
		cols.append(Color(white, float(p[1])))
	c.draw_polygon(PackedVector2Array([pts[0], pts[1], pts[4], pts[5]]), PackedColorArray([cols[0], cols[1], cols[4], cols[5]]))
	c.draw_polygon(PackedVector2Array([pts[1], pts[2], pts[3], pts[4]]), PackedColorArray([cols[1], cols[2], cols[3], cols[4]]))


## Kinder auf die runde Form ihres Rahmens zuschneiden (Cover, Kacheln). clip_children zeichnet
## jedes solche Element über einen eigenen Puffer – bei einer Reihe Cover auf schwachen PCs der
## größte Posten. Im leichten Modus schneidet der Rahmen eckig zu (clip_contents); seine Ecken
## sind dann klein (UzTheme.r_cover), das Bild deckt sie.
static func clip_round(c: Control, mode := CanvasItem.CLIP_CHILDREN_ONLY) -> void:
	if Leicht.active:
		c.clip_contents = true
	else:
		c.clip_children = mode


## Entstuft zeichnen: für Elemente, die nur weiche Lichter oder Verläufe zeichnen (Bühne, Schein).
## Ein schwacher Schein auf dunklem Grund hat im 8-Bit-Bild nur wenige Stufen – sie stünden als
## Ringe da (Color Banding). Das Material legt vor der Ausgabe dreieckiges, blau verteiltes Rauschen
## von ±1 Stufe darüber (Interleaved Gradient Noise, im Mittel ±0,5/255), und zwar nach dem Mischen
## gerechnet (vormultipliziert: Es wirkt auch dort, wo der Schein fast durchsichtig ist). Kein
## Körnen, kein Flimmern, eine Rechnung je Bildpunkt. Nur für Lichter, nicht für Schrift.
const ENTSTUFEN_GLSL := """
float uz_ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
vec3 uz_rauschen(vec2 fc) {
	vec3 a = vec3(uz_ign(fc), uz_ign(fc + vec2(17.0, 59.0)), uz_ign(fc + vec2(83.0, 23.0)));
	vec3 b = vec3(uz_ign(fc + vec2(41.0, 7.0)), uz_ign(fc + vec2(5.0, 97.0)), uz_ign(fc + vec2(67.0, 31.0)));
	return (a + b - 1.0) / 255.0;
}
"""
static var _entstuft: ShaderMaterial


static func entstuft() -> ShaderMaterial:
	if _entstuft:
		return _entstuft
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nrender_mode blend_premul_alpha;\n" + ENTSTUFEN_GLSL + """
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	// Rauschen nur, wo etwas gezeichnet wird (außerhalb bleibt der Grund unberührt).
	COLOR = vec4(c.rgb * c.a + uz_rauschen(FRAGCOORD.xy) * step(0.0005, c.a), c.a);
}
"""
	_entstuft = ShaderMaterial.new()
	_entstuft.shader = sh
	return _entstuft


## Weicher Verlauf von voll (Anfang) zu durchsichtig (Ende), weiß – beim Zeichnen einfärben.
## vertical: oben → unten, sonst links → rechts.
static var _fades := {}


static func fade_texture(vertical: bool, from_end := false) -> Texture2D:
	var key := str(vertical) + str(from_end)
	if _fades.has(key):
		return _fades[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	# from_end: voll am Ende (unten bzw. rechts), durchsichtig am Anfang.
	var a := Vector2(0, 1) if vertical else Vector2(1, 0)
	t.fill_from = a if from_end else Vector2.ZERO
	t.fill_to = Vector2.ZERO if from_end else a
	t.width = 8 if vertical else 256
	t.height = 256 if vertical else 8
	_fades[key] = t
	return t


## Bild mit runden Ecken (und auf Wunsch unten dunkler auslaufend) als Material für eine
## TextureRect, die das Bild genau in ihrer Größe zeigt.
static var _round_shader: Shader


static func rounded_mat(radius: float, fade_bottom := 0.0) -> ShaderMaterial:
	if _round_shader == null:
		_round_shader = Shader.new()
		_round_shader.code = """shader_type canvas_item;
uniform float radius = 14.0;
uniform float fade = 0.0;
uniform vec2 size = vec2(100.0);
varying vec4 tint;
void vertex() {
	tint = COLOR;   // modulate/self_modulate: sonst wirkte Einblenden nicht
}
void fragment() {
	vec2 px = UV * size;
	vec2 q = min(px, size - px);
	float d = length(max(vec2(radius) - q, vec2(0.0))) - radius;
	vec4 c = texture(TEXTURE, UV);
	c.rgb *= 1.0 - fade * smoothstep(0.4, 1.0, UV.y);
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c * tint;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _round_shader
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("fade", fade_bottom)
	return m


## Eine TextureRect mit runden Ecken; das Bild füllt sie ganz (Seitenverhältnis wie die Fläche).
static func rounded_image(radius: float, fade_bottom := 0.0) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := rounded_mat(radius, fade_bottom)
	t.material = m
	t.resized.connect(func() -> void: m.set_shader_parameter("size", t.size))
	return t


## Die helle Auswahlfläche im _draw eines Elements: wächst beim Einblenden leicht auf und
## glimmt warm (UzTheme.draw_selection).
static func draw_focus(c: Control, r := -1, rect := Rect2()) -> void:
	var f: float = c.get_meta("uz_f", 1.0 if c.has_focus() else 0.0)
	if f <= 0.01:
		return
	var rr := rect if rect.size != Vector2.ZERO else Rect2(Vector2.ZERO, c.size)
	var k := (1.0 - f) * 6.0
	UzTheme.draw_selection(c, rr.grow_individual(-k, -k * 0.5, -k, -k * 0.5), r, f, glow_for(rr.size))


## Wie stark eine Auswahl glimmt: kleine Pillen deutlich, breite Zeilen nur zart.
static func glow_for(sz: Vector2) -> float:
	return clampf(remap(sz.x, 220.0, 1100.0, 1.0, 0.55), 0.55, 1.0)


## Kritisch gedämpfte Feder, ein Schritt: [Lage, Tempo] → neue [Lage, Tempo] zum Ziel hin.
## Exakt gelöst, also auch bei wenigen Bildern pro Sekunde stabil und ohne Nachschwingen.
static func spring_step(pos: float, vel: float, target: float, dt: float, omega := SPRING) -> Vector2:
	var x := pos - target
	var e := exp(-omega * dt)
	var k := vel + omega * x
	return Vector2(target + (x + k * dt) * e, (vel - omega * k * dt) * e)


static func hbox(sep := 12) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func vbox(sep := 12) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func margin(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


static func panel(bg := "surface", r := -1, pad := 0, alpha := 1.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col(bg, alpha), r)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Logische Größe des Fensters. Die Oberfläche ist für 1920 × 1080 gebaut; 21:9 ist breiter,
## 4:3 und 16:10 sind höher, eine größere Oberfläche (Einstellungen → Aussehen) ist kleiner.
## Geht auch, bevor ein Knoten eingehängt ist (Bereiche bauen sich im Voraus).
static func view_size() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_visible_rect().size if tree != null and tree.root != null else Vector2(1920, 1080)


## Spalten eines Rasters, das bei 1920 Pixeln Breite base Spalten hat: auf breiteren Bildschirmen
## (21:9) entsprechend mehr, damit rechts keine leere Fläche bleibt, auf schmaleren (größere
## Oberfläche) weniger, damit nichts über den Rand ragt. gutter: Rand links und rechts.
static func cols_for(base: int, gutter := 96.0, view_w := -1.0) -> int:
	var w := (view_w if view_w > 0.0 else view_size().x) - gutter * 2.0
	return maxi(mini(2, base), int(floor(base * w / (1920.0 - gutter * 2.0) + 0.001)))


## Breite zwischen den Seitenrändern (1728 in 1080p; mit größerer Oberfläche entsprechend weniger).
static func room_w(gutter := 96.0) -> float:
	return view_size().x - gutter * 2.0


## Wie knapp die Höhe ist: 0 bei 1080 logischen Zeilen und mehr (wie gebaut, auch 4:3, 16:10),
## 1 bei 720 (Oberfläche 150 % auf 16:9). Seiten rücken damit Abstände zusammen und blenden
## Zweitrangiges aus, statt etwas abzuschneiden.
static func tight(view_h := -1.0) -> float:
	var h := view_h if view_h > 0.0 else view_size().y
	return clampf((1080.0 - h) / 360.0, 0.0, 1.0)


## Maß, das bei knapper Höhe von full (wie gebaut) bis least (bei 720 Zeilen) schrumpft.
static func by_room(full: float, least: float, view_h := -1.0) -> float:
	return roundf(lerpf(full, least, tight(view_h)))


static func spacer(min_w := 0, min_h := 0, expand := true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(min_w, min_h)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func button(text: String, icon_name := "", kind := "normal") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if icon_name != "":
		b.icon = Icons.tex(icon_name, 26)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 26)
	b.custom_minimum_size = Vector2(0, 56)
	# Marke: überall derselbe ruhige Knopf – eine echte, gerundete Fläche (Haupthandlung im Akzent),
	# gewählt hell mit dunkler Schrift. Symbolknöpfe sind runde getönte Flächen.
	if UzTheme.strict() and UzTheme.cursor_frame():
		if kind == "icon":
			b.custom_minimum_size = Vector2(56, 56)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ruhig(b, kind if kind in ["primary", "danger"] else ("symbol" if kind == "icon" else ""), 0 if kind == "icon" else (22 if kind == "flat" else 26))
		return b
	if kind == "primary":
		# Die eine wichtigste Handlung ruht als Glas wie die anderen Knöpfe, nur etwas kräftiger und
		# gehoben; den Akzent trägt das Symbol (ohne Symbol die Schrift). Nie eine gedämpfte helle
		# Fläche: die sah am Fernseher gedrückt oder abgeschaltet aus. Gewählt wird sie voll hell,
		# wächst und glimmt.
		var sb := UzTheme.lift(UzTheme.box(UzTheme.col("primary"), 999), 1)
		sb.content_margin_left = 30
		sb.content_margin_right = 32
		var hv := sb.duplicate() as StyleBoxFlat
		hv.bg_color = UzTheme.col("sel")
		var fr := UzTheme.with_glow(sb.duplicate() as StyleBoxFlat, 1.8)
		fr.bg_color = UzTheme.col("sel")
		UzTheme.cursor(fr, true)
		# Abgeschaltet: flaches, leises Glas ohne Schatten und ohne Akzent (wie jeder Knopf).
		var dis := UzTheme.box(UzTheme.col("glass"), 999)
		dis.content_margin_left = 30
		dis.content_margin_right = 32
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.add_theme_stylebox_override("focus", fr)
		b.add_theme_stylebox_override("disabled", dis)
		b.add_theme_font_override("font", UzTheme.ui("ui_bold"))
		b.add_theme_color_override("font_color", UzTheme.col("text" if icon_name != "" else "accent_ink"))
		for k in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, UzTheme.col("on_focus"))
		b.add_theme_color_override("font_disabled_color", UzTheme.col("faint"))
		b.add_theme_color_override("icon_normal_color", UzTheme.col("accent_ink"))
		for k in ["icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
			b.add_theme_color_override(k, UzTheme.col("on_focus"))
		b.add_theme_color_override("icon_disabled_color", UzTheme.col("faint"))
	elif kind == "icon":
		# Radius knapp unter der halben Höhe: bei genau der Hälfte zeichnet Godot eine Naht.
		b.custom_minimum_size = Vector2(56, 56)
		b.add_theme_stylebox_override("normal", UzTheme.box(UzTheme.col("glass_hi"), UzTheme.r_round(27), 1, UzTheme.col("stroke")))
		b.add_theme_stylebox_override("hover", UzTheme.box(UzTheme.col("text", 0.16), UzTheme.r_round(27), 1, UzTheme.col("stroke")))
		b.add_theme_stylebox_override("pressed", UzTheme.box(UzTheme.col("text", 0.16), UzTheme.r_round(27), 1, UzTheme.col("stroke")))
		var fi := UzTheme.with_glow(UzTheme.focus_fill(UzTheme.r_round(27)), 1.0)
		b.add_theme_stylebox_override("focus", fi)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif kind == "flat":
		var sb3 := UzTheme.box(UzTheme.col("glass_hi"), 999, 1, UzTheme.col("stroke"))
		sb3.content_margin_left = 22
		sb3.content_margin_right = 24
		b.add_theme_stylebox_override("normal", sb3)
		var f3 := UzTheme.with_glow(UzTheme.focus_fill(999), 0.85)
		f3.content_margin_left = 22
		f3.content_margin_right = 24
		b.add_theme_stylebox_override("focus", f3)
	return b



## Der ruhige Knopf der Listen-Sprache (Marke): immer eine echte Fläche, nie Wort mit bloßem
## Rahmen. art: "" Nebenhandlung (matter Graphit, Schrift hell), "primary" Haupthandlung (im Akzent
## getönt, Schrift hell, ruht mit weichem Schatten), "danger" (rot getönt, rote Schrift), "symbol" (runde
## getönte Fläche für ein Symbol allein), "flach" (ruht ohne Fläche – nur Symbol und Wort, wie im
## Guide). Jede Fläche ist deckend und trägt oben eine Lichtkante (UzTheme.lichtkante) – Tiefe
## durch Licht statt Kontur. Gewählt wird jeder hell (Cursorfarbe, Schrift dunkel, der Schatten
## wird tiefer; "danger" rot) – weich im Cursor-Takt (T_ANTWORT), ohne Linie und ohne Wachsen.
## pad: Innenrand links und rechts.
static func ruhig(b: Button, art := "", pad := 26) -> void:
	var f := knopf_farben(art)
	b.set_meta("uz_kf", f)
	var rest: Color = f.rest
	# Eine Box für Ruhe und Auswahl: knopf_stand() blendet ihre Farbe und ihren Schatten über.
	var nb := UzTheme.flaeche(rest, 999, 0, 0.0 if art == "flach" else 1.0)
	nb.content_margin_left = pad
	nb.content_margin_right = pad
	nb.shadow_offset = Vector2(0, 4)
	var pr := UzTheme.box(f.druck as Color, 999)
	pr.content_margin_left = pad
	pr.content_margin_right = pad
	var dis := UzTheme.box(Color(rest, rest.a * 0.45), 999)
	dis.content_margin_left = pad
	dis.content_margin_right = pad
	b.add_theme_stylebox_override("normal", nb)
	b.add_theme_stylebox_override("hover", nb)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_font_override("font", UzTheme.ui("ui_bold"))
	b.add_theme_color_override("font_disabled_color", UzTheme.col("faint"))
	b.add_theme_color_override("icon_disabled_color", UzTheme.col("faint"))
	b.set_meta("uz_kt", 1.0 if b.has_focus() else 0.0)
	knopf_stand(b, float(b.get_meta("uz_kt")))
	if not b.has_meta("uz_kn"):
		b.set_meta("uz_kn", true)
		b.focus_entered.connect(func() -> void: _knopf_takt(b, true))
		b.focus_exited.connect(func() -> void: _knopf_takt(b, false))
		# Kinder (Symbol, Wort in eigenen Knöpfen wie PillButton) nehmen die Schrift gleich mit.
		b.child_entered_tree.connect(func(_n: Node) -> void:
			(func() -> void:
				if is_instance_valid(b):
					knopf_stand(b, float(b.get_meta("uz_kt", 0.0)))).call_deferred())


## Farben des ruhigen Knopfs: ruhend (rest, ink, icon), gewählt (on, on_ink), gedrückt (druck),
## dazu schatten (0 … 1: wie tief der Knopf schon in Ruhe liegt – nur die Haupthandlung ruht gehoben).
## Alle Flächen deckend (matt): keine Durchsicht auf das Bild dahinter.
static func knopf_farben(art := "") -> Dictionary:
	var text := UzTheme.col("text")
	var on := UzTheme.col("focus")
	var on_ink := UzTheme.col("on_cursor")
	var hi := UzTheme.col("surface_hi") as Color
	var tint := hi.lerp(text, 0.1)
	var ink := text
	var schatten := 0.0
	match art:
		"primary":
			# At rest the main action is tinted with the accent, not fully filled: only the selection is
			# fully bright. A fully colored main button next to a white selected button made it unclear
			# where the selection was.
			var akz := UzTheme.col("accent") as Color
			tint = hi.lerp(akz, 0.36)
			ink = text.lerp(akz, 0.3)
			schatten = 1.0
		"danger":
			tint = hi.lerp(UzTheme.col("danger"), 0.26)
			ink = UzTheme.col("danger_text")
			on = UzTheme.col("danger")
			on_ink = UzTheme.text_on(on)
		"flach":
			tint = Color(on, 0.0)
	return { "rest": tint, "ink": ink, "icon": ink, "on": on, "on_ink": on_ink, "druck": on.darkened(0.12), "schatten": schatten }


## Ruhender Schatten der Haupthandlung und Schatten der Auswahl (Deckkraft, Weite).
const KNOPF_RUHT := Vector2(0.26, 10.0)
const KNOPF_AUF := Vector2(0.42, 14.0)


## Stand des ruhigen Knopfs setzen: 0 ruht, 1 gewählt (Fläche hell, Schrift dunkel, tieferer Schatten).
static func knopf_stand(b: Button, v: float) -> void:
	if not is_instance_valid(b) or not b.has_meta("uz_kf"):
		return
	var f: Dictionary = b.get_meta("uz_kf")
	v = clampf(v, 0.0, 1.0)
	var nb := b.get_theme_stylebox("normal") as StyleBoxFlat
	var on: Color = f.on
	var on_ink: Color = f.on_ink
	if nb:
		nb.bg_color = (f.rest as Color).lerp(on, v)
		var ruht := float(f.get("schatten", 0.0))
		nb.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(lerpf(KNOPF_RUHT.x * ruht, KNOPF_AUF.x, v)))
		nb.shadow_size = int(round(lerpf(KNOPF_RUHT.y * ruht, KNOPF_AUF.y, v)))
		if nb.border_width_top > 0:
			nb.border_color = UzTheme.kante_farbe(nb.bg_color)
	var ink: Color = (f.ink as Color).lerp(on_ink, v)
	var ic: Color = (f.icon as Color).lerp(on_ink, v)
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(k, ink)
	for k in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		b.add_theme_color_override(k, ic)
	for k in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(k, on_ink)
	for n in b.get_children():
		_knopf_kind(n, ink, ic)


## Mouse over an idle button (schweben.gd): the surface a touch brighter with an accent glow around it, so hovering
## is clearly visible (for example on the game page); nothing gets selected and the text stays. Selected buttons
## stay as they are.
static func knopf_schweben(b: Button, an: bool) -> void:
	if not is_instance_valid(b) or not b.has_meta("uz_kf"):
		return
	var kt := float(b.get_meta("uz_kt", 0.0))
	knopf_stand(b, kt)
	if not an or kt > 0.5:
		return
	var nb := b.get_theme_stylebox("normal") as StyleBoxFlat
	if nb == null:
		return
	var f: Dictionary = b.get_meta("uz_kf")
	nb.bg_color = (f.rest as Color).lerp(f.on as Color, 0.14)
	nb.shadow_color = Color(UzTheme.col("accent"), 0.5)
	nb.shadow_size = 14


static func _knopf_kind(n: Node, ink: Color, ic: Color) -> void:
	if n is Label:
		(n as Label).add_theme_color_override("font_color", ink)
	elif n is TextureRect and n.has_meta("uz_icon"):
		(n as TextureRect).modulate = ic
	elif n is Container:
		for k in n.get_children():
			_knopf_kind(k, ink, ic)


## Auswahl des ruhigen Knopfs im Cursor-Takt: im ersten Bild zu 70 % da, gesetzt in T_ANTWORT;
## abgewählt sofort auf 30 %, weg in T_ANTWORT (wie Liste.takt).
static func _knopf_takt(b: Button, on: bool) -> void:
	var von: float = b.get_meta("uz_kt", 0.0)
	var start := maxf(von, 0.7) if on else minf(von, 0.3)
	var bis := 1.0 if on else 0.0
	var setzen := func(v: float) -> void:
		if is_instance_valid(b):
			b.set_meta("uz_kt", v)
			knopf_stand(b, v)
	setzen.call(start)
	if not b.is_inside_tree():
		setzen.call(bis)
		return
	var t := ankommen(b, T_ANTWORT, "uz_ktw") if on else weg(b, "uz_ktw")
	t.tween_method(setzen, start, bis, T_ANTWORT)


static func glyph(cmd: String, px := 30) -> Control:
	var g := Glyph.new()
	g.cmd = cmd
	g.px = px
	return g


static func hint(cmd: String, text: String) -> HBoxContainer:
	var h := hbox(9)
	h.add_child(glyph(cmd, 27))
	var l := label(text, "s", "muted", "medium")
	h.add_child(l)
	return h


## Viele Karten in einen Behälter, ohne das Bild anzuhalten: die ersten sofort (mehr sieht man beim Öffnen nicht),
## der Rest in Scheiben über die nächsten Bilder. Gemessen: 500 Playlist-Kacheln in einem Zug kosten 116 ms Aufbau
## und einen langen ersten Durchgang des Layouts. baue(i) liefert die Karte Nummer i (oder null: auslassen).
## bis: So lange wird ohne Pause gebaut, bis bis(karte) wahr war – für die Auswahl, die nach einem Neuaufbau wieder
## auf derselben Karte stehen soll. Der Behälter muss im Baum hängen; verlässt er ihn, endet das Bauen.
static func in_scheiben(halter: Node, n: int, baue: Callable, sofort := 24, je_bild := 30, bis := Callable()) -> void:
	var gefunden := not bis.is_valid()
	var seit := je_bild
	for i in n:
		if i >= sofort and gefunden:
			if seit >= je_bild:
				seit = 0
				await (Engine.get_main_loop() as SceneTree).process_frame
				if not is_instance_valid(halter) or not halter.is_inside_tree() or not baue.is_valid():
					return
			seit += 1
		var c: Node = baue.call(i)
		if c == null:
			continue
		halter.add_child(c)
		if not gefunden and bis.call(c):
			gefunden = true
			seit = 0


static func clear(n: Node) -> void:
	for ch in n.get_children():
		n.remove_child(ch)
		ch.queue_free()


## Ein an den Rahmen gehefteter Knoten gleitet waagerecht herein (über die Ränder, nicht über
## position – sonst rechnet Godot die Breite falsch, solange der Rahmen noch keine Größe hat).
static func slide_x(c: Control, from: float, dur := 0.3) -> void:
	from = weg_px(from)
	if from == 0.0:
		stop(c, "uz_slide")
		c.offset_left = 0.0
		c.offset_right = 0.0
		return
	c.offset_left = from
	c.offset_right = from
	# In ganzen Pixeln mit sauberem Schluss (px_schluss): kein spätes Nachrucken um 1 px.
	px_weg(tw(c, "uz_slide", Tween.TRANS_QUART), c, "uz_px_slide", from, dur, func(p: float) -> void:
		c.offset_left = p
		c.offset_right = p
	)


## Reihen einer Seite erscheinen nacheinander: höchstens STAFFEL_MAX Glieder im Abstand STAFFEL,
## der Rest kommt mit dem letzten. Nur Deckkraft – Schrift wird nie skaliert, die Lage gehört dem
## Container. max_items: so viele Reihen staffeln höchstens (weniger als STAFFEL_MAX geht auch).
static func cascade(root: Control, max_items := STAFFEL_MAX) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	var list := _cascade_list(root, 0)
	if list == null:
		return
	# Sofort verstecken (läuft deferred, also vor dem Zeichnen) – kein Aufblitzen im Layout-Frame.
	for ch in list.get_children():
		if ch is Control:
			stop(ch, "uz_casc")
			(ch as Control).modulate.a = 0.0
	var tree := root.get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(list):
		return
	var glieder := mini(maxi(max_items, 1), STAFFEL_MAX)
	var unten := view_size().y
	var i := 0
	for ch in list.get_children():
		if not (ch is Control):
			continue
		var c := ch as Control
		if not c.visible or c.size.y < 24 or c.get_global_rect().position.y > unten:
			c.modulate.a = 1.0
			continue
		ankommen(c, T_ORT, "uz_casc").tween_property(c, "modulate:a", 1.0, T_ORT).set_delay(staffel(mini(i, glieder - 1)))
		i += 1


## Die erste senkrechte Liste mit mehreren Reihen (meist in einem ScrollContainer).
static func _cascade_list(n: Node, depth: int) -> Control:
	if depth > 6:
		return null
	for ch in n.get_children():
		if ch is VBoxContainer and (ch as Control).get_child_count() >= 3:
			return ch
	for ch in n.get_children():
		if ch is Control and not (ch is HBoxContainer) and not (ch is GridContainer):
			var r := _cascade_list(ch, depth + 1)
			if r:
				return r
	return null


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


# --- Texte -------------------------------------------------------------------

static func playtime(seconds: int) -> String:
	if seconds <= 0:
		return "Noch nicht gespielt"
	var m := seconds / 60
	if m < 60:
		return "%d Min. gespielt" % maxi(m, 1)
	var h := float(seconds) / 3600.0
	if h < 10.0:
		return Lang.dec("%.1f" % h) + " Std. gespielt"
	return "%d Std. gespielt" % int(h)


## Für den Satzinneren: nur den ersten Buchstaben klein („Vor 2 Tagen“ → „vor 2 Tagen“).
static func lower_first(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1) if s != "" else s


static func ago(unix: int) -> String:
	if unix <= 0:
		return ""
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var midnight := int((now + bias) / 86400) * 86400
	var local := unix + bias
	if local >= midnight:
		var mins := (now - unix) / 60
		if mins < 2:
			return "Gerade eben"
		if mins < 60:
			return "Vor %d Min." % mins
		return "Heute"
	var days := int(ceil(float(midnight - local) / 86400.0))
	if days <= 1:
		return "Gestern"
	if days < 7:
		return "Vor %d Tagen" % days
	if days < 14:
		return "Letzte Woche"
	if days < 60:
		return "Vor %d Wochen" % (days / 7)
	return date(unix)


static func date(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := Time.get_time_zone_from_system().get("bias", 0) as int
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return Lang.date_text(int(d.day), int(d.month), int(d.year), false, true)


static func clock() -> String:
	var t := Time.get_time_dict_from_system()
	if Config.get_value("theme.clock_24h", true):
		return "%02d:%02d" % [t.hour, t.minute]
	var h: int = t.hour % 12
	return "%d:%02d %s" % [12 if h == 0 else h, t.minute, "PM" if t.hour >= 12 else "AM"]


static func plural(n: int, one: String, many: String) -> String:
	return Lang.count(n, one, many)
