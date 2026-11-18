extends "res://src/ui/sections/section.gd"
## Browser (Bereich oben in der Leiste, Wunschliste 120): die Startbühne des Uzai-Browsers. In der Mitte eine
## ruhige Fläche im Material „Kernlicht“ (Graphit, Lichtkante oben), darauf groß die Marke – das Zeichen flach
## im Akzent mit Licht in der Fuge – und der Name „Uzai Browser“; darunter leise, was ihn ausmacht. A öffnet:
## Die Bühne wächst nahtlos zum Browser (browser.gd Aufgang: Fläche wird Schirm, Marke fliegt in den Kopf
## der Startseite; kein Schnitt, kein helles Bild). Darunter eine Reihe deiner Seiten (Apps, Lesezeichen) als
## Abkürzung – A öffnet die Seite direkt.
## Fehlt der Browser-Kern noch, richtet Uzai ihn beim ersten Öffnen des Bereichs von selbst ein
## (browser_kern_lauf.gd); die Bühne zeigt dann statt der Unterzeile den Schritt und einen Balken, X bricht ab.

const Kachel := preload("res://src/ui/components/browser_kachel.gd")
const D := preload("res://src/core/browser_daten.gd")
const Logo := preload("res://src/ui/components/uzai_logo.gd")
const KernLauf := preload("res://src/core/browser_kern_lauf.gd")

var _buehne: Control


func _init() -> void:
	super()
	id = "browser"
	title = "Browser"
	icon_name = "browser"


func build() -> void:
	mark_built()
	U.clear(self)
	var col := U.vbox(0)
	var sc := scroll_v(col)
	U.full_rect(sc)
	add_child(sc)
	var seiten: Array = D.liste("apps") + D.liste("favoriten")
	var halt := CenterContainer.new()
	halt.custom_minimum_size = Vector2(0, U.by_room(620.0 if seiten.is_empty() else 560.0, 440.0))
	halt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	halt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(halt)
	_buehne = Buehne.new()
	_buehne.set_meta("uz_key", "browser:oeffnen")
	_buehne.set_meta("uz_hint_a", "Öffnen")
	_buehne.set_meta("uz_default", true)
	_buehne.set_meta("uz_entry", true)
	_buehne.chosen.connect(_oeffnen)
	halt.add_child(_buehne)
	KernLauf.automatisch()
	if seiten.is_empty():
		return
	var hm := U.margin(GUTTER, 8, GUTTER, 0)
	hm.add_child(U.label("Deine Seiten", "l", "muted", "medium"))
	col.add_child(hm)
	var reihe = Shelf.new().setup("browser:seiten", 28, true, 10, GUTTER, 30)
	col.add_child(reihe)
	var gesehen := {}
	for e in seiten.slice(0, 12):
		if gesehen.has(e.url):
			continue
		gesehen[e.url] = true
		var k = Kachel.new().setup(str(e.url), str(e.titel))
		k.set_meta("uz_key", "browser:seite:" + str(e.url).sha256_text().substr(0, 10))
		k.set_meta("uz_hint_a", "Öffnen")
		var zoom := int(e.get("zoom", 0))
		k.chosen.connect(func() -> void: main.open_browser(str(e.url), zoom))
		reihe.add(k)


## A auf der Bühne: der Browser wächst aus ihr (Lage der Fläche und der Marke in Schirm-Koordinaten).
func _oeffnen() -> void:
	main.open_browser("", 0, false, _buehne.call("aufgang_von"))


## Die Bühne: eine Fläche, die später der ganze Browser ist. Gewählt: der Kachel-Cursor der Marke im
## Cursor-Takt, die Fläche hebt sich eine Spur (T_ORT). A drückt kurz ein und öffnet.
class Buehne extends Control:
	signal chosen

	const U2 := preload("res://src/ui/u.gd")
	const Liste := preload("res://src/ui/components/liste.gd")
	const Logo2 := preload("res://src/ui/components/uzai_logo.gd")

	const GROESSE := Vector2(880, 470)
	const MARKE_H := 168.0
	const LIFT := 8.0
	const KernLauf2 := preload("res://src/core/browser_kern_lauf.gd")
	const SCHRITTE := { "liste": "Fassungen lesen", "download": "Kern laden", "pruefen": "Prüfsummen prüfen", "auslegen": "Dateien auslegen",
		"install": "Installer prüft Signatur und entpackt" }

	var _focus_t := 0.0
	var _hub := 0.0
	var _kern := {}                   ## Stand des Kern-Laufs (browser_kern_lauf.gd), solange er läuft oder scheiterte
	var _kern_ms := 0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = GROESSE
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())

	## Kern-Lauf ansehen (viermal je Sekunde): Text und Balken auf der Bühne, X bricht ab, solange er läuft.
	func _process(_dt: float) -> void:
		var jetzt := Time.get_ticks_msec()
		if jetzt - _kern_ms < 250:
			return
		_kern_ms = jetzt
		var st: Dictionary = KernLauf2.stand()
		var neu := {} if not bool(st.laeuft) and str(st.fehler) == "" else st
		if neu.hash() == _kern.hash():
			return
		var lief := bool(_kern.get("laeuft", false))
		_kern = neu
		if bool(neu.get("laeuft", false)):
			set_meta("uz_hint_x", "Abbrechen")
			set_meta("uz_on_x", func() -> void:
				if is_instance_valid(KernLauf2.jetzt):
					KernLauf2.jetzt.call("abbrechen")
					Sfx.play("back"))
		elif has_meta("uz_on_x"):
			remove_meta("uz_on_x")
			remove_meta("uz_hint_x")
		if lief != bool(neu.get("laeuft", false)) and has_focus():
			Nav.focus_moved.emit(self)
		queue_redraw()

	## Zeile und Balken des Kern-Laufs (statt der Unterzeile).
	func _kern_zeile(m: Vector2) -> void:
		var f2 := UzTheme.display("medium")
		var y := m.y + MARKE_H * 0.5 + 118.0
		var t: String
		if bool(_kern.get("laeuft", false)):
			var sch := str(_kern.schritt)
			var name := str(_kern.text) if sch == "install" and str(_kern.text) != "" else str(SCHRITTE.get(sch, "Kern laden"))
			t = TranslationServer.translate("Browser-Kern wird eingerichtet") + " · " + TranslationServer.translate(name)
			if sch in ["download", "install"]:
				t += " %d %%" % int(_kern.prozent)
		else:
			t = TranslationServer.translate("Browser-Kern nicht eingerichtet – A versucht es noch einmal")
		var w2 := f2.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
		draw_string(f2, Vector2(size.x * 0.5 - w2.x * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UzTheme.col("text" if bool(_kern.get("laeuft", false)) else "muted"))
		if not bool(_kern.get("laeuft", false)):
			return
		var bw := 460.0
		var bar := Rect2(size.x * 0.5 - bw * 0.5, y + 22.0, bw, 6.0)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.09), 3), bar)
		var a := clampf(float(_kern.anteil), 0.0, 1.0)
		if a > 0.005:
			draw_style_box(UzTheme.box(UzTheme.col("accent"), 3), Rect2(bar.position, Vector2(maxf(6.0, bw * a), 6.0)))

	func activate() -> void:
		var t := U2.ankommen(self, U2.T_ORT, "uz_hub")
		t.tween_method(_set_hub, _hub, 0.4, U2.T_ANTWORT)
		t.tween_method(_set_hub, 0.4, 1.0, U2.T_ORT)
		chosen.emit()

	func activate_sound() -> String:
		return "select"

	func _on_focus(on: bool) -> void:
		Liste.takt(self, _focus_t, on, func(v: float) -> void:
			_focus_t = v
			queue_redraw())
		var t := U2.ankommen(self, U2.T_ORT if on else U2.T_WEG, "uz_hub") if on else U2.weg(self, "uz_hub")
		t.tween_method(_set_hub, _hub, 1.0 if on else 0.0, U2.T_ORT if on else U2.T_WEG)

	func _set_hub(v: float) -> void:
		_hub = v
		queue_redraw()

	## Die Fläche (ohne Hebung) in eigenen Koordinaten.
	func flaeche_rect() -> Rect2:
		return Rect2(Vector2.ZERO, size)

	## Mitte des Zeichens (eigene Koordinaten): etwas über der Mitte, der Name darunter.
	func marke_mitte() -> Vector2:
		return Vector2(size.x * 0.5, size.y * 0.5 - 44.0)

	## Für den Aufgang (browser.gd): Fläche, Mitte und Höhe der Marke in Schirm-Koordinaten.
	func aufgang_von() -> Dictionary:
		var xf := get_global_transform()
		var r := flaeche_rect()
		return { "rect": Rect2(xf * r.position, r.size * xf.get_scale()), "marke": xf * marke_mitte(), "hoehe": MARKE_H * xf.get_scale().y }

	## Der Hof: acht Ringe, nach außen leiser (ein weicher Verlauf ohne Textur); auch der Aufgang zeichnet ihn so.
	static func hof(ci: CanvasItem, m: Vector2, h: float, akz: Color, staerke: float) -> void:
		for i in 8:
			var k := float(i) / 7.0
			ci.draw_circle(m + Vector2(0, h * 0.05), h * (0.56 + 0.8 * k), Color(akz, 0.028 * (1.0 - k * 0.85) * staerke))

	func _draw() -> void:
		var dy := -U2.weg_px(LIFT) * _hub
		var r := flaeche_rect()
		r.position.y += dy
		var rc := int(float(UzTheme.r_panel()) * 1.4)
		var sb := UzTheme.flaeche(UzTheme.col("surface_hi"), rc, 2)
		sb.shadow_color = Color(0, 0, 0, 0.34 + 0.16 * _focus_t)
		sb.shadow_size = int(26 + 14 * _focus_t)
		sb.shadow_offset = Vector2(0, 12 + 6 * _focus_t)
		draw_style_box(sb, r)
		# Ein leiser Hof aus Licht hinter der Marke – das Kernlicht der Marke, weich auslaufend, kein Glanz.
		var m := marke_mitte() + Vector2(0, dy)
		var akz := UzTheme.col("accent")
		hof(self, m, MARKE_H, akz, 1.0 + 0.35 * _focus_t)
		Logo2.draw_mark(self, m, MARKE_H, akz, Logo2.licht_von(akz))
		var f := UzTheme.display()
		var name := "Uzai Browser"
		var fs := 46
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(size.x * 0.5 - w.x * 0.5, m.y + MARKE_H * 0.5 + 76.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
		if not _kern.is_empty():
			_kern_zeile(m)
		else:
			var zeile := TranslationServer.translate("Werbung und Tracker geblockt")
			var f2 := UzTheme.display("medium")
			var w2 := f2.get_string_size(zeile, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
			draw_string(f2, Vector2(size.x * 0.5 - w2.x * 0.5, m.y + MARKE_H * 0.5 + 118.0), zeile, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UzTheme.col("muted"))
		if _focus_t > 0.01:
			UzTheme.draw_tile_focus(self, r, rc, clampf(_focus_t, 0.0, 1.0))
