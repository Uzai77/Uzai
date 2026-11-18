extends Control
## Seitenleiste „Anpassen“ im Zimmer (Punkt 131): ruhig, rechts am Rand, ganz mit dem Controller.
## Zeigt Seiten aus Zeilen (anpassen.gd baut sie); jede Änderung wirkt sofort und weich im Zimmer.
##
## Zeilen: { art, text, … }
##   wahl      optionen [[id, Name]], wert() → id, setzen(id)          ←/→ blättert
##   stufe     wie wahl, als Regler gezeigt                              ←/→
##   zahl      min, max, schritt, einheit („%d cm“), wert(), setzen(n)   ←/→, LB/RB in großen Schritten
##   farbe     wert() → „#rrggbb“ oder „“, setzen(hex), leer („Natur“)  ←/→ Palette, A Farbwahl
##   schalter  wert() → bool, setzen(bool)                               A oder ←/→
##   seite     oeffnen() → Seite, wert() → Text rechts (freiwillig)      A
##   aktion    tun(), gefahr (rot)                                        A
##   option    wert() → bool (Haken), tun()                              A
##   abschnitt, info: nur Text
## Dazu freiwillig: hinweis (Zeile darunter), std (Y setzt zurück), roh (Text ist vom Nutzer: nie
## übersetzen), roh_wert (ebenso für den Wert rechts); Optionen [id, Name, true] = Name vom Nutzer.
## Seite: { titel, kicker, zeilen, zurueck: Callable, roh } – zurueck läuft beim Verlassen mit B.
## Seite mit „tafel“ (Regal einrichten, anpassen.gd seite_regal): statt der Zeilen eine Tafel mit
## großen Kacheln (regal_tafel.gd) unten wie im Bau-Menü; Tasten und Hinweise gehen an sie.
##
## Farbwahl: Palette, eigene Farben, „Natur“ und das Farbrad (Farbton im Ring, Sättigung und
## Helligkeit im Feld). Beim Blättern sieht man die Farbe sofort; B stellt die alte wieder her.

signal geschlossen
signal schritt_neu              ## andere Zeile gewählt: nächste Änderung ist ein neuer Rückgängig-Schritt

const G := preload("res://src/room/gestalt.gd")
const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Stil := preload("res://src/room/zimmer_stil.gd")
const RegalTafel := preload("res://src/room/regal_tafel.gd")

const BREITE := 600.0
const RAND := 48.0
const ZEILE_H := 60.0
const ABSTAND := 6.0

var rueckgaengig: Callable       ## X: einen Schritt zurück (vom Zimmer)
var eigene_farben: Callable      ## () → Array der eigenen Farben
var farbe_merken: Callable       ## (hex) eigene Farbe merken

var _stapel: Array = []          ## Seiten
var _sel: Array = []             ## gewählte Zeile je Seite
var _panel: PanelContainer
var _kicker: Label
var _titel: Label
var _liste: Control
var _inhalt: VBoxContainer
var _zeilen: Array = []          ## _Zeile je Eintrag der aktuellen Seite
var _scroll := 0.0
var _farbwahl: _Farbwahl
var _offen := false
var _tafel: RegalTafel              ## regal_tafel.gd, solange eine Tafel-Seite oben liegt


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	_panel = PanelContainer.new()
	# Ein Blatt in der warmen Optik des Zimmers (zimmer_stil.gd, wie das Bau-Menü): matt und deckend,
	# Lichtkante oben, weicher Schatten – kein Glas, kein kaltes Grau.
	_panel.add_theme_stylebox_override("panel", UzTheme.flaeche(Color(Stil.FLAECHE, 1.0), UzTheme.r_panel(), 3))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var m := U.margin(30, 28, 30, 24)
	_panel.add_child(m)
	var col := U.vbox(18)
	m.add_child(col)
	var kopf := U.vbox(2)
	_kicker = U.label("", "s", "accent_ink", "ui_bold")
	_titel = U.label("", "l", "text", "bold")
	if UzTheme.strict():
		# Kopf wie in den Blättern: darüber ein Etikett in kleinen Versalien, der Titel in der Titelschrift.
		_kicker = U.label("", "cap", "faint", "medium")
		_kicker.uppercase = true
		_kicker.add_theme_font_override("font", Liste.caps_font())
		_titel = U.label("", "l", "text", "title")
	_titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_titel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_titel.clip_text = true
	kopf.add_child(_kicker)
	kopf.add_child(_titel)
	col.add_child(kopf)
	_liste = Control.new()
	_liste.clip_contents = true
	_liste.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_liste.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_liste)
	_inhalt = U.vbox(int(ABSTAND))
	_inhalt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_liste.add_child(_inhalt)
	_farbwahl = _Farbwahl.new()
	_farbwahl.ui = self
	_farbwahl.visible = false
	_liste.add_child(_farbwahl)
	resized.connect(_lage)
	_lage.call_deferred()
	visible = false


func _lage() -> void:
	var s := size if size.x > 0 else U.view_size()
	_panel.position = Vector2(s.x - BREITE - RAND + (0.0 if _offen else 40.0), RAND)
	_panel.size = Vector2(BREITE, _hoehe_soll())
	_inhalt.size.x = BREITE - 60.0
	_farbwahl.size = Vector2(BREITE - 60.0, _hoehe_max() - 140.0)


## Die Leiste ist so hoch wie ihre Seite (eine Wand mit vier Zeilen ist keine leere Tafel), höchstens
## bis über die Tastenhinweise; die Farbwahl braucht die ganze Höhe.
func _hoehe_max() -> float:
	var s := size if size.x > 0 else U.view_size()
	return s.y - RAND - 172.0


func _hoehe_soll() -> float:
	if _farbwahl.visible:
		return _hoehe_max()
	var h := 0.0
	for r in _zeilen:
		h += (r as Control).custom_minimum_size.y + ABSTAND
	return clampf(h + 150.0, 320.0, _hoehe_max())


## Höhe weich an die Seite anpassen.
func _hoehe_anpassen() -> void:
	var soll := _hoehe_soll()
	if absf(_panel.size.y - soll) < 1.0:
		return
	U.tw(_panel, "uz_hoehe", Tween.TRANS_QUART).tween_property(_panel, "size:y", soll, U.T_MOVE)


func ist_offen() -> bool:
	return _offen


## Seite öffnen (neue Leiste) – gleitet von rechts herein.
func oeffnen(seite: Dictionary) -> void:
	_stapel = [seite]
	_sel = [0]
	_offen = true
	visible = true
	modulate.a = 0.0
	_lage()
	var ziel := _panel.position.x - 40.0
	var tw := U.tw(self, "uz_anpassen", Tween.TRANS_QUART)
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_panel, "position:x", ziel, U.T_MOVE)
	_zeigen(0)
	# Neu geöffnet: gleich in der Höhe der Seite (nicht von der vorigen her wachsen).
	U.stop(_panel, "uz_hoehe")
	_panel.size.y = _hoehe_soll()
	_auswahl(false)


## still: ohne „geschlossen“ zu melden (das Zimmer wechselt selbst weiter, z. B. in den Baukasten).
func schliessen(still := false) -> void:
	if not _offen:
		return
	_offen = false
	_farbwahl.visible = false
	if _tafel and bool(_tafel.ist_offen()):
		_tafel.schliessen()
	var tw := U.tw(self, "uz_anpassen", Tween.TRANS_CUBIC, Tween.EASE_IN)
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, U.T_FAST)
	tw.tween_property(_panel, "position:x", _panel.position.x + 30.0, U.T_FAST)
	tw.chain().tween_callback(func() -> void: visible = false)
	if not still:
		geschlossen.emit()


## Eine Unterseite öffnen (A auf einer „seite“-Zeile).
func hinein(seite: Dictionary) -> void:
	_sel[_sel.size() - 1] = _wahl()
	_stapel.append(seite)
	_sel.append(0)
	Sfx.play("open")
	_zeigen(1)


func zurueck() -> void:
	if _farbwahl.visible:
		_farbwahl.abbrechen()
		return
	var s: Dictionary = _stapel.back()
	if s.get("zurueck") is Callable and (s.zurueck as Callable).is_valid():
		(s.zurueck as Callable).call()
	if _stapel.size() <= 1:
		Sfx.play("back")
		schliessen()
		return
	_stapel.pop_back()
	_sel.pop_back()
	Sfx.play("back")
	_zeigen(-1)


## Werte neu lesen (nach Rückgängig oder wenn sich der Raum geändert hat), Seite neu aufbauen.
func auffrischen() -> void:
	if not _offen:
		return
	if _ist_tafel():
		_tafel.auffrischen()
		return
	var s: Dictionary = _stapel.back()
	if s.get("neu") is Callable and (s.neu as Callable).is_valid():
		var frisch: Dictionary = (s.neu as Callable).call()
		frisch["neu"] = s.neu
		_stapel[_stapel.size() - 1] = frisch
	_sel[_sel.size() - 1] = _wahl()
	_zeigen(0)


func seite() -> Dictionary:
	return _stapel.back() if not _stapel.is_empty() else {}


func _wahl() -> int:
	return int(_sel.back()) if not _sel.is_empty() else 0


## Liegt oben eine Tafel-Seite (Regal einrichten)?
func _ist_tafel() -> bool:
	return not _stapel.is_empty() and str((_stapel.back() as Dictionary).get("tafel", "")) != "" and _tafel != null


func _zeigen(richtung: int) -> void:
	var s: Dictionary = _stapel.back()
	# Tafel statt Zeilen: die Leiste rechts tritt zurück, unten steigt die Tafel auf.
	if str(s.get("tafel", "")) != "":
		if _tafel == null:
			_tafel = RegalTafel.new()
			add_child(_tafel)
		_panel.visible = false
		U.clear(_inhalt)
		_zeilen.clear()
		_tafel.zeigen(s)
		return
	_panel.visible = true
	if _tafel and bool(_tafel.ist_offen()):
		_tafel.schliessen()
	_kicker.text = str(s.get("kicker", ""))
	_titel.text = str(s.get("titel", "")) if bool(s.get("roh", false)) else tr(str(s.get("titel", "")))
	U.clear(_inhalt)
	_zeilen.clear()
	var zl: Array = s.get("zeilen", [])
	for z in zl:
		var row := _Zeile.new()
		row.daten = z
		row.custom_minimum_size = Vector2(BREITE - 60.0, _hoehe(z))
		_inhalt.add_child(row)
		_zeilen.append(row)
	var sel := clampi(_wahl(), 0, maxi(0, zl.size() - 1))
	if not _waehlbar(sel):
		sel = _naechste(sel, 1)
	_sel[_sel.size() - 1] = sel
	_hoehe_anpassen()
	_auswahl(false)
	if richtung != 0:
		_inhalt.modulate.a = 0.0
		_inhalt.position.x = 36.0 * richtung
		var tw := U.tw(_inhalt, "uz_seite", Tween.TRANS_QUART)
		tw.set_parallel(true)
		tw.tween_property(_inhalt, "modulate:a", 1.0, U.T_BASE)
		tw.tween_property(_inhalt, "position:x", 0.0, U.T_MOVE)


static func _hoehe(z: Dictionary) -> float:
	match str(z.get("art", "")):
		"abschnitt": return 40.0
		"info": return 26.0 + 24.0 * ceilf(str(z.get("text", "")).length() / 46.0)
	return ZEILE_H + (22.0 if str(z.get("hinweis", "")) != "" else 0.0)


func _waehlbar(i: int) -> bool:
	if i < 0 or i >= _zeilen.size():
		return false
	return not (str((_zeilen[i] as _Zeile).daten.get("art", "")) in ["abschnitt", "info"])


func _naechste(i: int, d: int) -> int:
	var j := i
	for _k in _zeilen.size():
		j += d
		if j < 0 or j >= _zeilen.size():
			return i if _waehlbar(i) else -1
		if _waehlbar(j):
			return j
	return i


func _auswahl(weich := true) -> void:
	var sel := _wahl()
	for i in _zeilen.size():
		(_zeilen[i] as _Zeile).setze(i == sel)
	# Die gewählte Zeile bleibt sichtbar: die Liste gleitet mit.
	if sel < 0 or sel >= _zeilen.size():
		return
	var y := 0.0
	for i in sel:
		y += (_zeilen[i] as _Zeile).custom_minimum_size.y + ABSTAND
	var h := (_zeilen[sel] as _Zeile).custom_minimum_size.y
	var sicht := _liste.size.y if _liste.size.y > 10 else 700.0
	var ziel := _scroll
	if y - ziel < 40.0:
		ziel = maxf(0.0, y - 40.0)
	elif y + h - ziel > sicht - 40.0:
		ziel = y + h - sicht + 40.0
	var gesamt := 0.0
	for r in _zeilen:
		gesamt += (r as _Zeile).custom_minimum_size.y + ABSTAND
	ziel = clampf(ziel, 0.0, maxf(0.0, gesamt - sicht))
	_scroll = ziel
	if weich:
		U.tw(_inhalt, "uz_scroll", Tween.TRANS_CUBIC).tween_property(_inhalt, "position:y", -ziel, U.T_FOCUS)
	else:
		_inhalt.position.y = -ziel


## Gleich das Farbrad zur Farbzeile mit diesem Text (Bau-Menü: „Eigene Farbe mischen“). Übernehmen
## oder Abbrechen dort schließt auch die Seite – zurück, wo es herkam.
func farbrad_auf(text: String) -> void:
	for i in _zeilen.size():
		var z: Dictionary = (_zeilen[i] as _Zeile).daten
		if str(z.get("art", "")) == "farbe" and str(z.get("text", "")) == text:
			_sel[_sel.size() - 1] = i
			_auswahl(false)
			_farbwahl.oeffnen(z)
			_farbwahl.direkt = true
			_farbwahl.rad_auf()
			return


## Was die Tasten gerade tun (für die Hinweisleiste des Zimmers).
func hinweise() -> Array:
	if _ist_tafel():
		return _tafel.hinweise("Zurück" if _stapel.size() > 1 else "Fertig")
	if _farbwahl.visible:
		return _farbwahl.hinweise()
	var h: Array = []
	var z := _zeile()
	match str(z.get("art", "")):
		"wahl", "stufe", "farbe":
			h.append(["a", "Farben" if z.art == "farbe" else "Weiter"])
		"zahl":
			h.append(["lb", "Großer Schritt"])
		"schalter":
			h.append(["a", "Umschalten"])
		"seite":
			h.append(["a", "Öffnen"])
		"aktion":
			h.append(["a", "Ausführen"])
		"option":
			h.append(["a", "Wählen"])
	if z.has("std"):
		h.append(["y", "Standard"])
	if rueckgaengig.is_valid():
		h.append(["x", "Rückgängig"])
	h.append(["b", "Zurück" if _stapel.size() > 1 else "Fertig"])
	return h


func _zeile() -> Dictionary:
	var i := _wahl()
	return (_zeilen[i] as _Zeile).daten if i >= 0 and i < _zeilen.size() else {}


## Steuerkreuz bzw. linker Stick.
func schritt(cmd: String) -> void:
	if _ist_tafel():
		_tafel.schritt(cmd)
		return
	if _farbwahl.visible:
		_farbwahl.schritt(cmd)
		return
	match cmd:
		"up", "down":
			var n := _naechste(_wahl(), -1 if cmd == "up" else 1)
			if n == _wahl() or n < 0:
				Sfx.play("bump")
				return
			_sel[_sel.size() - 1] = n
			Sfx.play("move")
			schritt_neu.emit()
			_auswahl()
		"left", "right":
			_aendern(-1 if cmd == "left" else 1)


## Tasten: true, wenn verbraucht.
func taste(cmd: String) -> bool:
	if _ist_tafel():
		if bool(_tafel.taste(cmd)):
			return true
		match cmd:
			"b":
				zurueck()
			"x":
				if rueckgaengig.is_valid():
					rueckgaengig.call()
			_:
				return false
		return true
	if _farbwahl.visible:
		return _farbwahl.taste(cmd)
	var z := _zeile()
	match cmd:
		"a":
			match str(z.get("art", "")):
				"seite":
					var c: Variant = z.get("oeffnen")
					if c is Callable:
						var neu: Dictionary = (c as Callable).call()
						if not neu.is_empty():
							hinein(neu)
				"aktion", "option":
					var t: Variant = z.get("tun")
					if t is Callable:
						Sfx.play("select")
						(t as Callable).call()
						_neu_zeichnen()
				"schalter":
					_aendern(1)
				"farbe":
					Sfx.play("open")
					_farbwahl.oeffnen(z)
				"wahl", "stufe":
					_aendern(1, true)
				_:
					Sfx.play("bump")
		"b":
			zurueck()
		"x":
			if rueckgaengig.is_valid():
				rueckgaengig.call()
		"y":
			if z.has("std") and z.get("setzen") is Callable:
				schritt_neu.emit()
				(z.setzen as Callable).call(z.std)
				Sfx.play("toggle_off")
				_neu_zeichnen()
				schritt_neu.emit()
			else:
				Sfx.play("bump")
		"lb", "rb":
			if str(z.get("art", "")) == "zahl":
				_aendern((-1 if cmd == "lb" else 1) * 5)
			else:
				Sfx.play("bump")
		_:
			return false
	return true


## Wert einer Zeile ändern (live im Zimmer).
func _aendern(d: int, rundum := false) -> void:
	var z := _zeile()
	var setzen: Variant = z.get("setzen")
	if not (setzen is Callable):
		Sfx.play("bump")
		return
	var wert: Variant = (z.wert as Callable).call() if z.get("wert") is Callable else null
	match str(z.get("art", "")):
		"wahl", "stufe":
			var opt: Array = z.get("optionen", [])
			if opt.is_empty():
				return
			var i := -1
			for k in opt.size():
				if str(opt[k][0]) == str(wert):
					i = k
			if i < 0 and (wert is int or wert is float):
				# Zwischen zwei Stufen: der Schritt führt zur nächsten in dieser Richtung.
				i = 0
				for k in opt.size():
					if (opt[k][0] is int or opt[k][0] is float) and float(opt[k][0]) < float(wert):
						i = k
				if d < 0:
					i += 1
			var n := maxi(i, 0) + d
			if rundum or str(z.art) == "wahl":
				n = posmod(n, opt.size())
			if n < 0 or n >= opt.size():
				Sfx.play("bump")
				return
			(setzen as Callable).call(opt[n][0])
		"zahl":
			var v := int(wert) + d * int(z.get("schritt", 1))
			v = clampi(v, int(z.get("min", 0)), int(z.get("max", 100)))
			if v == int(wert):
				Sfx.play("bump")
				return
			(setzen as Callable).call(v)
		"schalter":
			(setzen as Callable).call(not bool(wert))
			Sfx.play("toggle_on" if not bool(wert) else "toggle_off")
			_neu_zeichnen()
			return
		"farbe":
			var liste := farb_liste(z)
			var j := liste.find(str(wert))
			# Eine gemischte Farbe steht nicht in der Liste: nach rechts die erste, nach links die letzte
			# (früher nach links die vorletzte).
			if j < 0 and d < 0:
				j = 0
			(setzen as Callable).call(liste[posmod(j + d, liste.size())])
		_:
			Sfx.play("bump")
			return
	Sfx.play("move")
	_neu_zeichnen()


func _neu_zeichnen() -> void:
	if _ist_tafel():
		_tafel.queue_redraw()
	for r in _zeilen:
		(r as _Zeile).queue_redraw()


## Farben zum Blättern: „Natur“ (wenn erlaubt), Palette, eigene Farben.
func farb_liste(z: Dictionary) -> Array:
	var out: Array = []
	if z.has("leer"):
		out.append("")
	for p in G.PALETTE:
		out.append(str(p[0]))
	if eigene_farben.is_valid():
		for c in eigene_farben.call():
			if not (str(c) in out):
				out.append(str(c))
	return out


# --- Eine Zeile --------------------------------------------------------------------------------------

class _Zeile extends Control:
	var daten: Dictionary = {}
	var _an := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setze(an: bool) -> void:
		var ziel := 1.0 if an else 0.0
		if is_equal_approx(ziel, _an):
			queue_redraw()
			return
		var tw := U.tw(self, "uz_zeile")
		tw.tween_method(func(v: float) -> void:
			_an = v
			queue_redraw(), _an, ziel, U.T_FOCUS if an else U.T_BASE)

	func _wert() -> Variant:
		return (daten.wert as Callable).call() if daten.get("wert") is Callable else null

	func _draw() -> void:
		var art := str(daten.get("art", ""))
		var f := UzTheme.font("ui_bold")
		var fr := UzTheme.font("regular")
		var fs := UzTheme.size("s")
		var eckig := UzTheme.strict()
		if art == "abschnitt":
			# Wie die Abschnitte überall: im eckigen Theme kleine Versalien, gesperrt, leise.
			if eckig:
				var cf := Liste.caps_font()
				draw_string(cf, Vector2(4, size.y - 12), tr(str(daten.get("text", ""))).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("cap"), UzTheme.col("faint"))
				return
			draw_string(f, Vector2(4, size.y - 12), tr(str(daten.get("text", ""))), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted"))
			return
		if art == "info":
			var zeilen := tr(str(daten.get("text", "")))
			var y := 20.0
			for teil in _umbrechen(zeilen, fr, fs, size.x - 8.0):
				draw_string(fr, Vector2(4, y), teil, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted"))
				y += 24.0
			return
		var r := Rect2(Vector2.ZERO, size)
		var ink := UzTheme.col("text").lerp(UzTheme.col("on_focus"), _an)
		var leise := UzTheme.col("muted").lerp(UzTheme.col("on_focus").lerp(UzTheme.col("focus"), 0.35), _an)
		if eckig:
			# Zeile der Listen-Sprache: keine Karte je Zeile, gewählt der Zeilen-Cursor; die Schrift
			# bleibt, wie sie ist.
			Liste.cursor(self, r, _an)
			ink = UzTheme.col("text")
			leise = UzTheme.col("muted")
		else:
			draw_style_box(UzTheme.box(UzTheme.col("surface_hi", 0.55), 16), r)
			UzTheme.draw_selection(self, r, 16, _an, 0.6)
		if bool(daten.get("gefahr", false)):
			ink = UzTheme.col("danger_text") if eckig else UzTheme.col("danger_text").lerp(UzTheme.col("danger"), _an)
		var mitte := ZEILE_H * 0.5 + fs * 0.36
		var text := str(daten.get("text", "")) if bool(daten.get("roh", false)) else tr(str(daten.get("text", "")))
		draw_string(UzTheme.font("ui") if eckig else f, Vector2(20, mitte), text, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.52, fs, ink)
		if str(daten.get("hinweis", "")) != "":
			draw_string(fr, Vector2(20, mitte + 26), tr(str(daten.hinweis)), HORIZONTAL_ALIGNMENT_LEFT, size.x - 40.0, UzTheme.size("xs"), leise)
		var rechts := size.x - 20.0
		var w: Variant = _wert()
		match art:
			"wahl", "stufe", "zahl":
				var t := _wert_text(w)
				var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var x0 := rechts
				if _an > 0.05:
					_pfeil(Vector2(rechts - 4, mitte - fs * 0.36), 1, ink, _an)
					x0 = rechts - 18.0
				if art == "stufe" or art == "zahl":
					var anteil := _anteil(w)
					var bahn := Rect2(x0 - 120.0, mitte - fs * 0.36 - 2.0, 120.0, 4.0)
					draw_rect(bahn, UzTheme.col("line").lerp(Color(0, 0, 0, 0.18), _an))
					draw_rect(Rect2(bahn.position, Vector2(bahn.size.x * anteil, 4.0)), UzTheme.col("accent").lerp(ink, _an * 0.6))
					if eckig:
						draw_rect(Rect2(bahn.position.x + bahn.size.x * anteil - 5.0, bahn.position.y - 3.0, 10.0, 10.0), UzTheme.col("text"))
					else:
						draw_circle(Vector2(bahn.position.x + bahn.size.x * anteil, bahn.position.y + 2.0), 6.0, UzTheme.col("accent").lerp(ink, _an * 0.6))
					x0 -= 136.0
				draw_string(f if art != "zahl" else fr, Vector2(x0 - tw, mitte), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, leise if _an < 0.5 else ink)
				if _an > 0.05:
					_pfeil(Vector2(x0 - tw - 14.0, mitte - fs * 0.36), -1, ink, _an)
			"farbe":
				var hex := str(w)
				var c := Color(hex) if hex != "" else Color(0, 0, 0, 0)
				var mp := Vector2(rechts - 16.0, mitte - fs * 0.36)
				if eckig:
					# Ein Farbfeld mit Haarlinie (eckig wie alles).
					var q := Rect2(mp - Vector2(13, 13), Vector2(26, 26))
					if hex != "":
						draw_rect(q, c)
					else:
						draw_line(q.position + Vector2(5, 21), q.position + Vector2(21, 5), leise, 2.0, true)
					draw_rect(q.grow(-0.5), UzTheme.col("line"), false, 1.0)
				else:
					draw_circle(mp, 16.0, Color(0, 0, 0, 0.25))
					if hex != "":
						draw_circle(mp, 14.0, c)
					else:
						draw_arc(mp, 13.0, 0, TAU, 32, leise, 2.0, true)
						draw_line(mp + Vector2(-9, 9), mp + Vector2(9, -9), leise, 2.0, true)
					draw_arc(mp, 15.5, 0, TAU, 40, Color(1, 1, 1, 0.22 + 0.4 * _an), 1.5, true)
				var name_ := G.farbname(hex) if hex != "" else str(daten.get("leer", "Natur"))
				if name_ == "":
					name_ = hex.to_upper()
				var nw := fr.get_string_size(tr(name_), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(fr, Vector2(rechts - 44.0 - nw, mitte), tr(name_), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, leise if _an < 0.5 else ink)
			"schalter":
				var an := bool(w)
				if eckig:
					# Schalter wie im Guide: eckig, „An“/„Aus“ leise davor, der Griff an im Akzent.
					var sw := Rect2(rechts - 38.0, mitte - fs * 0.36 - 11.0, 38.0, 22.0)
					draw_rect(sw, UzTheme.col("surface_hi"))
					draw_rect(sw.grow(-0.5), UzTheme.col("line"), false, 1.0)
					var gx := sw.end.x - 18.0 if an else sw.position.x + 4.0
					draw_rect(Rect2(gx, sw.position.y + 4.0, 14, 14), UzTheme.col("accent") if an else UzTheme.col("muted"))
					var at := tr("An" if an else "Aus")
					var aw := fr.get_string_size(at, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					draw_string(fr, Vector2(sw.position.x - 12.0 - aw, mitte), at, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, leise)
				else:
					var pr := Rect2(rechts - 48.0, mitte - fs * 0.36 - 13.0, 48.0, 26.0)
					draw_style_box(UzTheme.box(UzTheme.col("accent") if an else UzTheme.col("line"), 13), pr)
					draw_circle(Vector2(pr.position.x + (35.0 if an else 13.0), pr.position.y + 13.0), 9.0, Color.WHITE if an else UzTheme.col("muted"))
			"option":
				var mp2 := Vector2(rechts - 12.0, mitte - fs * 0.36)
				if eckig:
					# Wie die Auswahllisten: der gewählte Wert trägt ein Häkchen im Akzent, sonst nichts.
					if bool(w):
						draw_texture_rect(Icons.tex("check", 24), Rect2(mp2 - Vector2(12, 12), Vector2(24, 24)), false, UzTheme.col("accent"))
				elif bool(w):
					draw_circle(mp2, 12.0, UzTheme.col("accent").lerp(ink, _an * 0.7))
					var hc := UzTheme.col("on_focus") if _an < 0.5 else UzTheme.col("focus")
					draw_polyline(PackedVector2Array([mp2 + Vector2(-5, 0), mp2 + Vector2(-1, 4), mp2 + Vector2(6, -4)]), hc, 2.4, true)
				else:
					draw_arc(mp2, 11.0, 0, TAU, 32, leise, 1.6, true)
			"seite":
				_pfeil(Vector2(rechts - 4, mitte - fs * 0.36), 1, leise.lerp(ink, _an), 1.0)
				if w != null and str(w) != "":
					var t2 := str(w) if bool(daten.get("roh_wert", false)) else tr(str(w))
					var tw2 := fr.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					draw_string(fr, Vector2(rechts - 22.0 - minf(tw2, size.x * 0.42), mitte), t2, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.42, fs, leise)

	func _wert_text(w: Variant) -> String:
		if str(daten.get("art", "")) == "zahl":
			return tr(str(daten.get("einheit", "%d"))) % int(w)
		for o in daten.get("optionen", []):
			if str(o[0]) == str(w):
				return str(o[1]) if (o as Array).size() > 2 and bool(o[2]) else tr(str(o[1]))
		# Ein Wert zwischen den Stufen (z. B. aus einer Stimmung): mit Einheit zeigen.
		if daten.has("einheit") and (w is int or w is float):
			return tr(str(daten.einheit)) % int(w)
		return str(w) if w != null else ""

	func _anteil(w: Variant) -> float:
		if str(daten.get("art", "")) == "zahl":
			var lo := float(daten.get("min", 0))
			var hi := float(daten.get("max", 100))
			return clampf((float(w) - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
		var opt: Array = daten.get("optionen", [])
		for k in opt.size():
			if str(opt[k][0]) == str(w):
				return float(k) / maxf(1.0, opt.size() - 1.0)
		# Zwischenwert: zwischen den Nachbarstufen einordnen.
		if (w is int or w is float) and opt.size() > 1:
			for k in opt.size() - 1:
				var a: Variant = opt[k][0]
				var b: Variant = opt[k + 1][0]
				if (a is int or a is float) and (b is int or b is float) and float(w) >= float(a) and float(w) <= float(b):
					return (float(k) + (float(w) - float(a)) / maxf(1.0, float(b) - float(a))) / (opt.size() - 1.0)
		return 0.0

	func _pfeil(p: Vector2, dir: int, c: Color, a: float) -> void:
		var col := Color(c, c.a * clampf(a, 0.0, 1.0))
		draw_polyline(PackedVector2Array([p + Vector2(-4 * dir, -6), p + Vector2(2 * dir, 0), p + Vector2(-4 * dir, 6)]), col, 2.2, true)

	static func _umbrechen(t: String, f: Font, fs: int, breite: float) -> Array:
		var out: Array = []
		var zeile := ""
		for wort in t.split(" "):
			var probe := wort if zeile == "" else zeile + " " + wort
			if f.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > breite and zeile != "":
				out.append(zeile)
				zeile = wort
			else:
				zeile = probe
		if zeile != "":
			out.append(zeile)
		return out


# --- Farbwahl: Palette und Farbrad ----------------------------------------------------------------

class _Farbwahl extends Control:
	const SPALTEN := 6
	const FELD := 64.0
	var ui: Control
	var direkt := false           ## aus dem Bau-Menü gleich ins Farbrad: danach auch die Seite zu
	var zeile: Dictionary = {}
	var _liste: Array = []
	var _sel := 0
	var _vorher := ""
	var _rad := false
	var _h := 0.0
	var _s := 0.5
	var _v := 0.8
	var _rad_mat: ShaderMaterial
	var _rad_rect: ColorRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rad_rect = ColorRect.new()
		_rad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rad_rect.size = Vector2(360, 360)
		_rad_rect.position = Vector2(90, 70)
		var sh := Shader.new()
		sh.code = RAD_SHADER
		_rad_mat = ShaderMaterial.new()
		_rad_mat.shader = sh
		_rad_rect.material = _rad_mat
		_rad_rect.visible = false
		# Unter den Markierungen, die _draw zeichnet.
		_rad_rect.show_behind_parent = true
		add_child(_rad_rect)

	func oeffnen(z: Dictionary) -> void:
		zeile = z
		_liste = ui.call("farb_liste", z)
		_vorher = str((z.wert as Callable).call()) if z.get("wert") is Callable else ""
		_sel = maxi(0, _liste.find(_vorher))
		_rad = false
		_rad_rect.visible = false
		visible = true
		modulate.a = 0.0
		U.tw(self, "uz_farbwahl").tween_property(self, "modulate:a", 1.0, U.T_BASE)
		(ui.get("_inhalt") as Control).visible = false
		ui.call("_hoehe_anpassen")
		queue_redraw()

	func _zu() -> void:
		visible = false
		ui.call("_hoehe_anpassen")
		(ui.get("_inhalt") as Control).visible = true
		ui.call("_neu_zeichnen")
		ui.emit_signal("schritt_neu")
		if direkt:
			direkt = false
			_rad = false
			_rad_rect.visible = false
			ui.call("zurueck")

	func abbrechen() -> void:
		(zeile.setzen as Callable).call(_vorher)
		Sfx.play("back")
		if _rad and not direkt:
			_rad = false
			_rad_rect.visible = false
			queue_redraw()
			return
		_zu()

	func _feld_anzahl() -> int:
		return _liste.size() + 1

	func hinweise() -> Array:
		if _rad:
			return [["a", "Übernehmen"], ["lb", "Farbton"], ["b", "Zurück"]]
		return [["a", "Übernehmen"], ["b", "Abbrechen"]]

	func schritt(cmd: String) -> void:
		if _rad:
			match cmd:
				"left": _s = clampf(_s - 0.05, 0.0, 1.0)
				"right": _s = clampf(_s + 0.05, 0.0, 1.0)
				"up": _v = clampf(_v + 0.05, 0.0, 1.0)
				"down": _v = clampf(_v - 0.05, 0.0, 1.0)
			Sfx.play("move")
			_rad_vorschau()
			return
		var n := _sel
		match cmd:
			"left": n -= 1
			"right": n += 1
			"up": n -= SPALTEN
			"down": n += SPALTEN
		if n < 0 or n >= _feld_anzahl():
			Sfx.play("bump")
			return
		_sel = n
		Sfx.play("move")
		if _sel < _liste.size():
			(zeile.setzen as Callable).call(_liste[_sel])
		queue_redraw()

	func taste(cmd: String) -> bool:
		match cmd:
			"a":
				if _rad:
					var hex := "#" + Color.from_hsv(_h, _s, _v).to_html(false)
					if ui.get("farbe_merken") is Callable and (ui.get("farbe_merken") as Callable).is_valid():
						(ui.get("farbe_merken") as Callable).call(hex)
					Sfx.play("select")
					_rad = false
					_rad_rect.visible = false
					_zu()
				elif _sel >= _liste.size():
					Sfx.play("open")
					rad_auf()
				else:
					Sfx.play("select")
					_zu()
			"b":
				abbrechen()
			"lb", "rb":
				if _rad:
					_h = fposmod(_h + (-1.0 if cmd == "lb" else 1.0) / 36.0, 1.0)
					Sfx.play("move")
					_rad_vorschau()
				else:
					Sfx.play("bump")
			_:
				return false
		return true

	## Farbrad: beginnt bei der Farbe, die gerade gilt.
	func rad_auf() -> void:
		var c := Color(_vorher) if _vorher != "" else Color("#c4913c")
		_h = c.h
		_s = c.s
		_v = c.v
		_sel = _liste.size()
		_rad = true
		_rad_rect.visible = true
		_rad_vorschau()

	func _rad_vorschau() -> void:
		_rad_mat.set_shader_parameter("ton", _h)
		(zeile.setzen as Callable).call("#" + Color.from_hsv(_h, _s, _v).to_html(false))
		queue_redraw()

	func _draw() -> void:
		var f := UzTheme.font("ui_bold")
		var fs := UzTheme.size("s")
		if _rad:
			var mitte := _rad_rect.position + _rad_rect.size * 0.5
			# Markierung im Ring (Farbton) und im Feld (Sättigung, Helligkeit).
			var a := _h * TAU - PI * 0.5
			var rp := mitte + Vector2(cos(a), sin(a)) * 162.0
			draw_circle(rp, 11.0, Color(0, 0, 0, 0.35))
			draw_circle(rp, 9.0, Color.from_hsv(_h, 1.0, 1.0))
			draw_arc(rp, 10.0, 0, TAU, 24, Color.WHITE, 2.0, true)
			var q := mitte + Vector2(-100, 100) + Vector2(_s * 200.0, -_v * 200.0)
			draw_circle(q, 10.0, Color(0, 0, 0, 0.35))
			draw_circle(q, 8.0, Color.from_hsv(_h, _s, _v))
			draw_arc(q, 9.0, 0, TAU, 24, Color.WHITE, 2.0, true)
			var hex := "#" + Color.from_hsv(_h, _s, _v).to_html(false)
			draw_string(f, Vector2(0, 30), tr("Farbrad"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
			draw_string(UzTheme.font("regular"), Vector2(0, 470), tr("Steuerkreuz: Sättigung und Helligkeit · Schultertasten: Farbton"), HORIZONTAL_ALIGNMENT_LEFT, size.x,
					UzTheme.size("xs"), UzTheme.col("muted"))
			draw_string(f, Vector2(size.x - f.get_string_size(hex.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 30), hex.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1,
					fs, UzTheme.col("muted"))
			# Vorher und neu nebeneinander.
			var fr := UzTheme.font("regular")
			var y0 := 520.0
			for k in 2:
				var x0 := k * (size.x * 0.5 + 6.0)
				var r := Rect2(x0, y0, size.x * 0.5 - 6.0, 64.0)
				var c := Color(_vorher) if k == 0 and _vorher != "" else (Color(0.3, 0.3, 0.32) if k == 0 else Color.from_hsv(_h, _s, _v))
				draw_style_box(UzTheme.box(c, 14), r)
				var t := tr("Vorher") if k == 0 else tr("Neu")
				draw_string(fr, r.position + Vector2(14, 38), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("xs"), UzTheme.text_on(c))
			return
		var titel := tr(str(zeile.get("text", "Farbe")))
		draw_string(f, Vector2(0, 30), titel, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
		var name_ := ""
		if _sel < _liste.size():
			var hex2 := str(_liste[_sel])
			name_ = G.farbname(hex2) if hex2 != "" else str(zeile.get("leer", "Natur"))
			if name_ == "":
				name_ = hex2.to_upper()
		else:
			name_ = "Eigene Farbe mischen"
		var nw := UzTheme.font("regular").get_string_size(tr(name_), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(UzTheme.font("regular"), Vector2(size.x - nw, 30), tr(name_), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted"))
		var abst := (size.x - FELD * SPALTEN) / float(SPALTEN - 1) + FELD
		for i in _feld_anzahl():
			var p := Vector2((i % SPALTEN) * abst + FELD * 0.5, 70.0 + floorf(float(i) / SPALTEN) * (FELD + 8.0) + FELD * 0.5)
			var gewaehlt := i == _sel
			if gewaehlt:
				draw_circle(p, FELD * 0.5, UzTheme.col("focus"))
			if i < _liste.size():
				var hex3 := str(_liste[i])
				if hex3 == "":
					draw_arc(p, FELD * 0.34, 0, TAU, 40, UzTheme.col("muted"), 2.0, true)
					draw_line(p + Vector2(-14, 14), p + Vector2(14, -14), UzTheme.col("muted"), 2.0, true)
				else:
					draw_circle(p, FELD * 0.38, Color(hex3))
					draw_arc(p, FELD * 0.38, 0, TAU, 40, Color(1, 1, 1, 0.14), 1.5, true)
			else:
				# Farbrad: ein kleiner bunter Ring mit Plus.
				for k in 24:
					var a0 := float(k) / 24.0 * TAU
					draw_arc(p, FELD * 0.3, a0, a0 + TAU / 24.0 + 0.02, 4, Color.from_hsv(float(k) / 24.0, 0.8, 0.95), 7.0, true)
				draw_line(p + Vector2(-7, 0), p + Vector2(7, 0), UzTheme.col("text") if not gewaehlt else UzTheme.col("on_focus"), 2.5, true)
				draw_line(p + Vector2(0, -7), p + Vector2(0, 7), UzTheme.col("text") if not gewaehlt else UzTheme.col("on_focus"), 2.5, true)

	const RAD_SHADER := """shader_type canvas_item;
uniform float ton = 0.0;
vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}
void fragment() {
	vec2 p = (UV - 0.5) * 360.0;
	float r = length(p);
	vec4 c = vec4(0.0);
	float aa = 1.2;
	if (r > 142.0 - aa && r < 182.0 + aa) {
		float a = atan(p.y, p.x) / 6.2831853 + 0.25;
		c = vec4(hsv(fract(a), 0.85, 0.95), smoothstep(142.0 - aa, 142.0 + aa, r) * (1.0 - smoothstep(182.0 - aa, 182.0 + aa, r)));
	}
	vec2 q = (p + vec2(100.0)) / 200.0;
	if (q.x >= 0.0 && q.x <= 1.0 && q.y >= 0.0 && q.y <= 1.0) {
		c = vec4(hsv(ton, q.x, 1.0 - q.y), 1.0);
	}
	COLOR = c;
}
"""
