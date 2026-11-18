extends "res://src/ui/layers/layer.gd"
## Einrichtung beim ersten Start, unterste Schicht: Seitenbausteine (Gerüst, Kopf, Karte, Zeile,
## Seitenleiste, Hilfe), Fortschritt und Abschluss, die gezeichneten Teile (Punkte, Zeichen,
## Farbmuster, Suche) und welche Bereiche es gibt.
## Die Einrichtung besteht aus Schichten; jede erbt von der darunter und kennt nur sie:
## setup_wizard_bausteine.gd → setup_wizard_start.gd → setup_wizard_spiele.gd →
## setup_wizard_konten.gd → setup_wizard_show.gd → setup_wizard.gd. _go ist
## hier nur ein Haken, setup_wizard.gd überschreibt ihn.

const E := preload("res://src/core/einrichtung.gd")
const Profiles := preload("res://src/core/profiles.gd")
const Tour := preload("res://src/ui/layers/tour.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Zustand := preload("res://src/core/zustand.gd")
const PAGE_W := 1480.0
const LEFT_W := 860.0
const ASIDE_W := 560.0

const Main := preload("res://src/main.gd")
const Buehne := preload("res://src/ui/components/einrichtung_buehne.gd")
var main: Main
var restart := false             ## aus den Einstellungen neu gestartet
var _steps: Array = []
var _idx := 0
var _page: Control
var _buehne: Buehne             ## hinter allem: Licht, Staub, die eigenen Cover (einrichtung_buehne.gd)
var _live: Array[Callable] = []  ## Anzeigen, die sich laufend auffrischen (Zustand der Konten …)
var _finished := false
var _aside_t: Label
var _aside_d: Label


# --- Welche Bereiche es gibt ---------------------------------------------------------------------

## Was es auf diesem PC gibt: Zusatzfunktionen (nur die, die im Code stehen) und Konten.
static func features() -> Dictionary:
	var sysd: Dictionary = Config.DEFAULTS.get("system", {})
	var has := {
		"lossless": true,
		"background_wake": sysd.has("background_wake"),
		"autostart": sysd.has("autostart") and Config.is_windows(),
		"clips": sysd.has("clip_keys") or Config.DEFAULTS.has("capture"),
		"gamebar": Config.is_windows(),
		"steam_guide": Config.is_windows(),
		"ruhemodus": (Config.DEFAULTS.get("controller", {}) as Dictionary).has("guide_hold"),
		"browser_kern": Config.is_windows() and str(Config.get_value("browser.kern", "cef")) == "cef",
	}
	return { "extras": E.extras_for(has), "accounts": ["steam", "discord", "spotify", "youtube", "nuvio"] }


# --- Fortschritt und Abschluss -------------------------------------------------------------------

func _b_text() -> String:
	if _idx == 0:
		# No „Überspringen“ (skip) option in the setup: B does nothing in the first step; when the setup was
		# restarted from the settings, B closes it.
		return "Schließen" if restart else "—"
	return "Zurück"


## B im ersten Schritt: aus den Einstellungen neu gestartet schließt die Einrichtung (alles bleibt,
## wie es war); bei der ersten Einrichtung gibt es kein Überspringen – nur ein leiser Anschlag.
func _back_at_start() -> void:
	if restart:
		Sfx.play("back")
		call("protokoll", "Abgebrochen im ersten Schritt – kommt nicht wieder (Einstellungen → System: erneut starten)")
		Config.set_value("einrichtung.done", true)
		Config.set_value("einrichtung.step", "")
		Config.set_value("einrichtung.restart", false)
		Config.save_settings()
		_finished = true
		close()
		return
	Sfx.play("bump")


func _finish(show_off := true) -> void:
	if _finished:
		return
	_finished = true
	var tour := { "tour": bool(Config.get_value("einrichtung.tour", false)), "restart": restart }
	call("protokoll", "Fertig")
	Config.set_value("einrichtung.done", true)
	Config.set_value("einrichtung.step", "")
	Config.set_value("einrichtung.restart", false)
	Config.set_value("system.first_run", false)
	Config.save_settings()
	# „Fertig“ ist der eigentliche Start von Uzai: dessen Signatur („launch“ gehört dem Spielstart).
	if show_off:
		Sfx.play("boot")
		# Die Bühne löst sich in die Startseite auf (setup_wizard.gd): Licht und Raum gehen, die
		# Startseite baut sich auf, die Cover landen auf ihren Gegenstücken – erst dann geht die Ebene
		# (und der Fokus kommt auf die Startseite).
		await _ausklang()
	if is_instance_valid(main):
		Tour.offer(main, tour)
	# Die Karte geht wie eine Ebene, die die Oberfläche verdeckt (Meta uz_verdeckt: Alt geht,
	# während die Startseite schon darunter steht); die Oberfläche kommt ohne Skalieren zurück –
	# Schrift wird nie skaliert, höchstens die Tiefe der Ebenen (layer.gd) läuft aus.
	set_meta("uz_verdeckt", true)
	close()


## Übergang in die Startseite vor dem Schließen (setup_wizard.gd überschreibt es).
func _ausklang() -> void:
	pass


func _tick() -> void:
	for f in _live:
		if f.is_valid():
			f.call()


# --- Seitenbausteine ----------------------------------------------------------------------

## Weiter oder Zurück. Die Schritte kennt erst setup_wizard.gd, das diese Funktion überschreibt;
## hier ruft sie das Gerüst der Seite.
func _go(_how: String) -> void:
	pass


## Kopf, zwei Spalten (links Inhalt, rechts Erklärung oder Vorschau) und unten „Weiter“.
## left_w: Breite der linken Spalte (die rechte bekommt den Rest; PAGE_W: keine rechte Spalte).
## Gewählt ist „Weiter“, wo der Schritt nichts anderes vorgibt: A geht durch die ganze Einrichtung.
func _skeleton(icon: String, title: String, sub: String, left_w := LEFT_W) -> Dictionary:
	var col := U.vbox(0)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_bottom = 1.0
	col.offset_left = -PAGE_W * 0.5
	col.offset_right = PAGE_W * 0.5
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(col)
	var head := U.hbox(30)
	col.add_child(head)
	head.add_child(_Badge.make(icon, 92))
	var hc := U.vbox(6)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hc)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UzTheme.display("title"))
	t.add_theme_font_size_override("font_size", 54)
	t.add_theme_color_override("font_color", UzTheme.col("text"))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hc.add_child(t)
	var s := U.label(sub, "l", "muted", "regular", true)
	s.custom_minimum_size = Vector2(1200, 0)
	hc.add_child(s)
	col.add_child(U.spacer(0, 28, false))
	var body := U.hbox(60)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.custom_minimum_size = Vector2(left_w, 0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	body.add_child(sc)
	var left := U.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(left)
	var right := U.vbox(16)
	right.custom_minimum_size = Vector2(maxf(0.0, PAGE_W - left_w - 60.0), 0)
	right.visible = left_w < PAGE_W - 60.0
	body.add_child(right)
	col.add_child(U.spacer(0, 26, false))
	var foot := U.hbox(18)
	col.add_child(foot)
	var go := _weiter()
	foot.add_child(go)
	return { "left": left, "right": right, "go": go, "scroll": sc, "title": t, "sub": s }


## Der eine Knopf eines Schritts: „Weiter“ – auch wo ein Schritt freiwillig ist (Konten), geht er
## ohne Verbindung weiter; ein „Später“ oder „Überspringen“ gibt es nicht mehr. Im selben ruhigen
## Stil wie jeder Knopf der Einrichtung (_knopf).
func _weiter() -> Button:
	var go := _knopf("Weiter", "chevron_right")
	go.custom_minimum_size = Vector2(240, 60)
	go.set_meta("uz_hint_a", "Weiter")
	go.set_meta("uz_key", "su:weiter")
	go.pressed.connect(func() -> void: _go("weiter"))
	return go


## Every button in the setup looks the same: calm and dark, light when selected. Buttons in different
## colors were confusing next to the white selection color, and a primary button in the accent color
## looked like a second selection.
func _knopf(text: String, icon_name := "") -> Button:
	return U.button(text, icon_name, "normal")


## Gerüst der mittigen Seiten (Spiele): eine Spalte über die ganze Seite.
func _mitte() -> VBoxContainer:
	var col := U.vbox(0)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_bottom = 1.0
	col.offset_left = -PAGE_W * 0.5
	col.offset_right = PAGE_W * 0.5
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(col)
	return col


## „Weiter“ mittig unter einer solchen Spalte; gibt den Knopf zurück.
func _fuss_mitte(col: Control) -> Button:
	var foot := U.hbox(18)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	var go := _weiter()
	foot.add_child(go)
	return go


## Elemente einer Spalte steigen nacheinander W_ORT von unten an ihren Platz und blenden dabei ein
## (T_RAUM, Kurve „Ankommen“, gestaffelt) – jedes in einer Hülle, damit der Container seine Lage
## nicht festhält. „Animationen reduzieren“: nur Einblenden.
func _steigen(items: Array, verz := 0.0) -> void:
	var i := 0
	for c0 in items:
		var c: Control = c0
		if not is_instance_valid(c) or c.get_parent() == null:
			continue
		var parent := c.get_parent()
		var at := c.get_index()
		var h := Control.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.size_flags_horizontal = c.size_flags_horizontal
		h.size_flags_vertical = c.size_flags_vertical
		parent.remove_child(c)
		parent.add_child(h)
		parent.move_child(h, at)
		h.add_child(c)
		var fit := func() -> void:
			if is_instance_valid(c) and is_instance_valid(h):
				h.custom_minimum_size = c.get_combined_minimum_size()
				c.size = Vector2(h.size.x, c.get_combined_minimum_size().y)
		c.minimum_size_changed.connect(fit)
		h.resized.connect(fit)
		fit.call()
		c.modulate.a = 0.0
		var d := verz + U.staffel(i)
		c.position.y = U.weg_px(U.W_ORT)
		var tw := U.ankommen(c, U.T_RAUM, "uz_steigen").set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, U.T_RAUM).set_delay(d)
		tw.tween_property(c, "position:y", 0.0, U.T_RAUM).set_delay(d)
		i += 1


func _head(box: Control, text: String, extra := "") -> void:
	if UzTheme.strict():
		# Abschnitt wie überall: kleines Etikett in Versalien (liste.gd).
		var sm := U.margin(22, 0 if box.get_child_count() == 0 else 22, 22, 6)
		sm.add_child(Liste.abschnitt(text, extra))
		box.add_child(sm)
		return
	var m := U.margin(22, 0 if box.get_child_count() == 0 else 26, 22, 10)
	var row := U.hbox(12)
	m.add_child(row)
	row.add_child(U.label(text, "s", "muted", "bold"))
	if extra != "":
		row.add_child(U.spacer())
		row.add_child(U.label(extra, "s", "faint", "medium"))
	box.add_child(m)


func _card(box: Control) -> VBoxContainer:
	var c := _Card.new()
	box.add_child(c)
	return c.rows


## Zeile in eine Karte: Titel, eine Zeile Erklärung, rechts der Wert. desc steht rechts in der Spalte.
## prep läuft vor dem Einhängen (etwa der Bereich eines Reglers – danach zeigte er den alten).
func _row(rows: VBoxContainer, kind: String, title: String, sub: String, desc: String, value: Variant = null, prep := Callable()) -> Control:
	var r = SettingRow.new()
	r.setup(kind, title, desc, value)
	r.subtitle = sub
	if prep.is_valid():
		prep.call(r)
	r.focus_radius = maxi(UzTheme.radius, UzTheme.r_panel() - 6)
	r.set_meta("uz_lr_block", true)
	r.set_meta("uz_key", "su:%s:%s" % [_steps[_idx], title])
	var t := title
	r.focus_entered.connect(func() -> void: _help(t, desc))
	rows.add_child(r)
	r.draw.connect((rows.get_parent() as Control).queue_redraw)
	return r


## Rechte Spalte: Titel und Erklärung der gewählten Zeile.
func _aside(right: Control, title: String, text: String) -> void:
	var p := PanelContainer.new()
	# Matte Fläche ohne Kontur (Marke: Tiefe statt Linie).
	var sb := UzTheme.box(UzTheme.col("text", 0.035), UzTheme.r_panel())
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 32
	sb.content_margin_bottom = 34
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(p)
	var v := U.vbox(14)
	p.add_child(v)
	_aside_t = U.label(title, "l", "text", "bold", true)
	v.add_child(_aside_t)
	_aside_d = U.label(text, "m", "muted", "regular", true)
	_aside_d.custom_minimum_size = Vector2(ASIDE_W - 72, 0)
	_aside_d.visible = text != ""
	v.add_child(_aside_d)


func _help(t: String, d: String) -> void:
	if is_instance_valid(_aside_t):
		_aside_t.text = t
	if is_instance_valid(_aside_d):
		_aside_d.text = d
		_aside_d.visible = d != ""


# --- Gezeichnete Teile ---------------------------------------------------------------------------

## Punkte oben: erledigt leise, der aktuelle als längliche Pille im Akzent.
class _Dots extends Control:
	const UD := preload("res://src/ui/u.gd")
	var count := 7
	var cur := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(count * 26 + 26, 14)

	func set_cur(i: int, animate := true) -> void:
		custom_minimum_size = Vector2(count * 26 + 26, 14)
		if not animate or not is_inside_tree():
			cur = float(i)
			queue_redraw()
			return
		# Ortswechsel: der Punkt gleitet mit dem Schritt (T_ORT, Kurve „Ankommen“).
		var tw := UD.ankommen(self, UD.T_ORT, "uz_punkte")
		tw.tween_method(func(v: float) -> void:
			cur = v
			queue_redraw()
		, cur, float(i), UD.T_ORT)

	func _draw() -> void:
		var x := 0.0
		var cy := size.y * 0.5
		for i in count:
			var d := absf(cur - i)
			var t := clampf(1.0 - d, 0.0, 1.0)
			var w := lerpf(10.0, 36.0, t)
			var col: Color
			if t > 0.01:
				col = UzTheme.col("text", 0.3).lerp(UzTheme.col("accent"), t)
			elif i < cur:
				col = UzTheme.col("text", 0.45)
			else:
				col = UzTheme.col("text", 0.16)
			draw_style_box(UzTheme.box(col, 999), Rect2(x, cy - 5, w, 10))
			x += w + 16.0


## Rundes Zeichen in einer weichen Scheibe (Kopf jeder Seite). „marke“: das U-Zeichen frei in den
## Markenfarben, ohne Scheibe (Die Guide-Taste – die Taste ist das U).
class _Badge extends Control:
	const UU := preload("res://src/ui/u.gd")
	const LogoB := preload("res://src/ui/components/uzai_logo.gd")
	var tone := ""
	var marke := false

	static func make(icon: String, px: int, tone_ := "") -> Control:
		var b := _Badge.new()
		b.tone = tone_
		b.custom_minimum_size = Vector2(px, px)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if icon == "marke":
			b.marke = true
			return b
		var ic := UU.icon(icon, int(px * 0.46), "ok" if tone_ == "ok" else "accent_ink")
		ic.set_anchors_preset(Control.PRESET_CENTER)
		ic.offset_left = -px * 0.23
		ic.offset_top = -px * 0.23
		ic.offset_right = px * 0.23
		ic.offset_bottom = px * 0.23
		b.add_child(ic)
		return b

	func _draw() -> void:
		if marke:
			LogoB.zeichne(self, size * 0.5, minf(size.y, size.x * 1.9 / 1.7) * 0.84, LogoB.farben("marke", UzTheme.col("accent")), { "kachel": 0.0 })
			return
		var c := UzTheme.col("ok" if tone == "ok" else "accent")
		var r := minf(size.x, size.y) * 0.5
		# Eine matte Scheibe im Akzent, ohne Ring und ohne Rahmen (keine dünnen Konturen).
		draw_circle(size * 0.5, r, Color(c, 0.14), true, -1.0, true)


## Karte mit Zeilen (wie in den Einstellungen): leise Fläche, feine Trennlinien.
class _Card extends MarginContainer:
	var rows: VBoxContainer

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(k, 6)
		rows = VBoxContainer.new()
		rows.add_theme_constant_override("separation", 0)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rows)
		# Trennlinien erst zeichnen, wenn die Zeilen liegen (sonst ein Strich links oben).
		rows.sort_children.connect(queue_redraw)
		resized.connect(queue_redraw)

	func _draw() -> void:
		# Eckig (Marke): keine Karte, keine Linien zwischen den Zeilen – wie im Guide.
		if UzTheme.strict():
			return
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))
		if rows.size.x < 60.0:
			return
		var kids: Array[Control] = []
		for ch in rows.get_children():
			if ch is Control and (ch as Control).visible:
				kids.append(ch as Control)
		for i in range(1, kids.size()):
			var fa: float = kids[i - 1].get_meta("uz_f", 0.0)
			var fb: float = kids[i].get_meta("uz_f", 0.0)
			var alpha := 0.07 * (1.0 - maxf(fa, fb))
			if alpha > 0.002:
				var y := rows.position.y + kids[i].position.y
				draw_line(Vector2(rows.position.x + 20.0, y), Vector2(rows.position.x + rows.size.x - 20.0, y), UzTheme.col("text", alpha), 1.0)


## Feld einer Akzentfarbe. kind: accent (eine feste Farbe, id = "#rrggbb") | auto (vom Farbschema) |
## custom (eigene wählen).
class _Swatch extends Control:
	signal activated
	var kind := "accent"
	var id := ""
	var on := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(64, 70)
		focus_entered.connect(func() -> void: _anim(true))
		focus_exited.connect(func() -> void: _anim(false))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func _anim(v: bool) -> void:
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(x: float) -> void:
			set_meta("uz_f", x)
			queue_redraw()
		, float(get_meta("uz_f", 0.0)), 1.0 if v else 0.0, 0.24 if v else 0.18)

	func activate() -> void:
		activated.emit()

	func _draw() -> void:
		var f: float = get_meta("uz_f", 0.0)
		var cen := size * 0.5 - Vector2(0, 3.0 * f)
		var r := 24.0
		# Eckig (Marke): Farbfelder eckig, gewählt der Rahmen-Cursor – kein Glimmen, kein Ring.
		if UzTheme.strict() and kind != "custom":
			var q := Rect2(cen - Vector2(r, r), Vector2(r, r) * 2.0)
			var fc := Color(id) if kind == "accent" else Color.BLACK
			# Der Cursor zuerst, das Farbfeld darauf: Er ist eine Fläche und deckte, zuletzt gezeichnet,
			# gerade die Farbe zu, die man wählt.
			Liste.cursor(self, q.grow(7), f)
			if kind == "auto":
				var pa: Dictionary = UzTheme.PRESETS.get(str(Config.get_value("theme.preset", "theme")), UzTheme.grund.colors)
				fc = pa.accent if pa.accent is Color else Color(str(pa.accent))
				if not on:
					draw_rect(q, fc)
					draw_string(UzTheme.font("bold"), cen + Vector2(-r, 5), tr("Auto"), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, UzTheme.text_on(fc))
			if kind == "accent" or on:
				draw_rect(q, fc)
			draw_rect(q.grow(-0.5), UzTheme.col("line"), false, 1.0)
			if on:
				_check(cen, 9.0, UzTheme.text_on(fc))
			return
		if f > 0.01:
			draw_circle(cen, r + 8.0, Color(UzTheme.col("accent"), 0.22 * f), true, -1.0, true)
			draw_arc(cen, r + 6.0, 0, TAU, 64, Color(UzTheme.col("focus"), f), 3.0, true)
		match kind:
			"accent":
				draw_circle(cen, r, Color(id), true, -1.0, true)
			"auto":
				var pr2: Dictionary = UzTheme.PRESETS.get(str(Config.get_value("theme.preset", "theme")), UzTheme.grund.colors)
				var a2: Color = pr2.accent if pr2.accent is Color else Color(str(pr2.accent))
				draw_circle(cen, r, a2, true, -1.0, true)
				if not on:
					draw_string(UzTheme.font("bold"), cen + Vector2(-r, 5), tr("Auto"), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, UzTheme.text_on(a2))
			"custom":
				for i in 12:
					draw_arc(cen, r - 6.0, TAU * i / 12.0, TAU * (i + 1) / 12.0, 6, Color.from_hsv(i / 12.0, 0.55, 0.95), 12.0, true)
				draw_line(cen - Vector2(7, 0), cen + Vector2(7, 0), UzTheme.col("text"), 2.5, true)
				draw_line(cen - Vector2(0, 7), cen + Vector2(0, 7), UzTheme.col("text"), 2.5, true)
		draw_arc(cen, r, 0, TAU, 64, UzTheme.col("text", 0.18), 1.5, true)
		if on and kind != "custom":
			var pr3: Dictionary = UzTheme.PRESETS.get(str(Config.get_value("theme.preset", "theme")), UzTheme.grund.colors)
			_check(cen, 9.0, UzTheme.text_on(Color(id) if kind == "accent" else (pr3.accent if pr3.accent is Color else Color(str(pr3.accent)))))
		elif on:
			draw_circle(cen + Vector2(r * 0.7, -r * 0.7), 9.0, UzTheme.col("accent"), true, -1.0, true)

	func _check(c: Vector2, s: float, col: Color) -> void:
		draw_polyline(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(-s * 0.3, s * 0.7), c + Vector2(s, -s * 0.6)]), col, 2.6, true)


## Der Fortschritt der Suche als schmale Linie unter dem Zähler (E.search_progress): gleitet zum
## neuen Stand (Feder, keine Sprünge) und geht, wenn die Suche fertig ist.
class _Fortschritt extends Control:
	const UF := preload("res://src/ui/u.gd")
	var _ziel := 0.0
	var _v := Vector2.ZERO           ## [Lage, Tempo]
	var _fertig := false
	var _a := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(360, 4)

	func set_pct(p: float, fertig: bool) -> void:
		_ziel = clampf(p, 0.0, 1.0)
		_fertig = fertig

	func _process(dt: float) -> void:
		if UF.reduziert():
			_v = Vector2(_ziel, 0.0)
		else:
			_v = UF.spring_step(_v.x, _v.y, _ziel, dt, 6.0)
		_a = move_toward(_a, 0.0 if _fertig and _v.x > 0.99 else 1.0, dt / UF.T_RAUM)
		queue_redraw()

	func _draw() -> void:
		if _a <= 0.0:
			return
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.1 * _a), 2), r)
		if _v.x > 0.005:
			draw_style_box(UzTheme.box(Color(UzTheme.col("accent"), _a), 2), Rect2(r.position, Vector2(maxf(4.0, r.size.x * clampf(_v.x, 0.0, 1.0)), r.size.y)))
