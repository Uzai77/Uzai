extends Control
## Nahtlose Übergänge mit geteilten Elementen (Punkt 90). Öffnet eine Karte ihre Seite, fliegt ihr
## Bild weich an seinen Platz in der neuen Seite: Cover → Hülle im Kopf der Spielseite, Shop-Karte →
## Hülle der Shop-Seite, Film-Plakat → großes Bild der Detailseite, Video → Player, Profilbild →
## Profil. Der Rest der Seite kommt mit ihr: Nennt sie sich selbst als Fläche (Layer.flaeche, Seiten),
## kommt erst ihr deckender Grund (T_WEG), dann ihre Schrift (T_ANTWORT später) – nie steht der
## Titel der Startseite unter dem der Seite. Der Inhalt gleitet ein Stück nach. Beim Schließen fliegt das Bild
## zurück an seine Karte – dorthin, wo sie jetzt steht, auch wenn die Liste inzwischen geblättert
## hat. Ist die Karte nicht mehr da (neu aufgebaut, anderer Bereich), blendet die Seite nur aus.
##
## Wer mitmacht:
##  - Karten tragen die Meta "uz_flug" (Schlüssel wie "g:<id>") und können ihr Bild über
##    flug_bild() -> Dictionary nennen (siehe bild_von); sonst zählt die Karte selbst (TextureRect).
##  - Seiten (Ebenen) tragen dieselbe Meta und nennen ihr Ziel über flug_ziel() -> Control.
##  - Layer.open/close rufen auf() und zu(); sonst ist nichts zu tun. Wer Ebenen erst nach einem
##    Augenblick öffnet (Videos schließen vorher alles), merkt sich die Karte vorher mit merke().
##
## Zwei Arten zu landen (Meta "uz_flug_art" der Seite):
##  - "landen" (Standard): Das Bild liegt über der Seite und wird am Ende zum Ziel, das solange
##    unsichtbar bleibt. Für Hüllen und Profilbilder.
##  - "aufloesen": Das Ziel ist ein großes Bild hinter der Seite (Film, Player). Das Bild fliegt
##    unter der aufgehenden Seite und geht in ihr auf. Zurück löst es sich aus der Seite und
##    liegt dabei über ihr (sonst stünde es kurz doppelt).
##
## Bewegung: eine kritisch gedämpfte Feder – schnell da und ruhig gesetzt, ohne nachzufedern; so
## gestreckt, dass sie nach T_AUF genau ankommt (kein Ausläufer unter einem Pixel bis 0,6 s), und in
## ganzen Pixeln beendet: Fehlt überall weniger als ein halbes Pixel, landet das Bild.
## Waagerecht etwas schneller als senkrecht, so fliegt das Bild auf einem flachen Bogen.
## Jedes Bild rechnet mit der echten Zeit seit dem letzten (60, 120, 144 Hz gleich schnell); die
## ersten beiden Bilder (Aufbau der Seite) zählen höchstens 1/60 s – so springt nichts.
## Leichter Modus: kürzer, ohne wachsenden Schatten. „Animationen reduzieren“: kein Flug, nur das
## Überblenden. Eingaben hält der Flug nie auf: Die Seite ist sofort bedienbar; im einen Bild, bis
## sie oben liegt, warten Befehle in Nav (hold_for) und gehen dann an sie – B mitten im Flug
## schickt das Bild von dort zurück, wo es gerade ist.
##
## Gezeichnet wird das schon geladene Bild der Karte, auch wenn es ein Zuschnitt (AtlasTexture,
## Zuschnitt.put) ist: Der Ausschnitt wandert stufenlos vom Format der Karte ins Format des Ziels,
## nichts lädt nach, nichts wird neu gerechnet. Kommt das Bild der Seite dazu (ein anderes Bild
## oder eine größere Fassung), blendet es während des Flugs darüber. Runde Ecken mit weicher Kante
## macht ein kleiner Shader. Ohne Fenster testbar (tests/logic_flug.gd).

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")

const T_AUF := 0.45           ## Flug beim Öffnen: nach 0,3 s gut 95 % da, landet spätestens hier
const T_ZU := 0.4             ## Flug zurück
const T_AUS := 0.12           ## nach dem Landen: das Bild über dem Ziel weg
const DAEMPFUNG := 1.0        ## Feder: kritisch gedämpft, kommt an ohne nachzufedern (Takt: kein Überschwingen)
const STEIF := 7.0            ## Feder: Straffheit über die ganze Dauer (auf genau 1 gestreckt, Ende fast in Ruhe)
const T_SEITE := 0.26         ## Aufloesen: so lange blendet die Seite über dem Bild auf
const BOGEN := 1.12           ## waagerecht so viel schneller: flacher Bogen statt gerader Linie
const DT_START := 1.0 / 60.0  ## die ersten Bilder (Aufbau der Seite) zählen höchstens so viel …
const DT_MAX := 0.1           ## … danach echte Zeit (schwache PCs mit 20 Bildern/s: gleich lang)
const GLEITEN := 26.0         ## so weit gleitet der Inhalt der neuen Seite nach oben
const QUELLE_MS := 1500       ## so lange gilt eine gemerkte Karte (merke)

const SHADER := """shader_type canvas_item;
uniform vec4 box;
uniform float radius;
varying vec2 p;
void vertex() {
	p = VERTEX;
}
void fragment() {
	vec2 h = box.zw * 0.5;
	vec2 q = abs(p - box.xy - h) - h + vec2(radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	// COLOR ist hier schon Bild mal Farbe; nur die Ecken weich ausschneiden.
	COLOR.a *= clamp(0.5 - d, 0.0, 1.0);
}
"""

static var _shader: Shader
static var _gemerkt := {}
## Laufende Flüge je Schlüssel: Ein neuer Flug übernimmt Lage und Bild des alten (B mitten im
## Öffnen fliegt von dort zurück, wo das Bild gerade ist).
static var _laufend := {}
## Für Proben: alle Flüge der Reihe nach (Schlüssel, Art, Richtung).
static var protokoll: Array = []
static var _unsichtbar := {}     ## Instanz-ID -> true, solange ein Flug das Element verbirgt

var key := ""
var art := "landen"
var zurueck := false
var dauer := T_AUF
var _x := 0.0
var _a: Dictionary = {}          ## Anfang: { tex, src, voll, rect, radius, rund, tint, scrim }
var _b: Dictionary = {}          ## Ende (wird jedes Bild neu gelesen, solange das Ziel lebt)
var _ziel: WeakRef               ## wo das Bild landet
var _such_key := ""              ## Rückflug: Karte erst im nächsten Bild suchen (Liste kommt zurück)
var _such_weak: WeakRef
var _versteckt: Array = []       ## WeakRefs auf Elemente, die gerade nicht zeichnen
var _wieder: Array = []          ## … und die nach der Landung sanft wieder einblenden
var _bild: Control
var _mat: ShaderMaterial
var _faellt := false             ## blendet aus (nach der Landung oder bei einem Abbruch) …
var _aus := 0.0                  ## … so weit (unter 0: wartet noch, bis das Ziel darunter da ist)
var _gelandet := false
var _jetzt: Dictionary = {}      ## was gerade zu sehen ist (für eine Übernahme)
var _sb: StyleBoxFlat
var _warten := 0.0
var _bilder := 0


# --- Für Ebenen ------------------------------------------------------------------------------

## Animationen reduzieren (Einstellung): kein Flug, nur Überblenden.
static func ruhig() -> bool:
	return U.reduziert()


## Karte merken, bevor erst andere Ebenen zugehen (Videos). Layer.open nimmt sie dann statt der
## Auswahl in dem Moment.
static func merke(c: Control) -> void:
	_gemerkt = _quelle_von(c)
	if not _gemerkt.is_empty():
		_gemerkt["ms"] = Time.get_ticks_msec()


## Die Karte, von der eine neue Ebene aufgeht: gemerkt (frisch) oder die gewählte.
static func quelle() -> Dictionary:
	if not _gemerkt.is_empty():
		var g := _gemerkt
		_gemerkt = {}
		if Time.get_ticks_msec() - int(g.get("ms", 0)) <= QUELLE_MS:
			return g
	var vp := Engine.get_main_loop() as SceneTree
	if vp == null or vp.root == null:
		return {}
	return _quelle_von(vp.root.gui_get_focus_owner())


## Karte mit Schlüssel: die Auswahl selbst oder bis zu drei Ebenen darüber.
static func _quelle_von(c: Control) -> Dictionary:
	var n: Node = c
	for i in 4:
		if n == null or not (n is Control):
			return {}
		if (n as Control).has_meta("uz_flug"):
			var k := str(n.get_meta("uz_flug"))
			if k == "":
				return {}
			return { "key": k, "weak": weakref(n), "bild": bild_von(n as Control) }
		n = n.get_parent()
	return {}


## Ebene geht auf (Layer.open, nach build): fliegt, wenn Karte und Seite zusammengehören, und
## blendet dann auch die Ebene selbst ein. false: kein Flug, die Ebene blendet wie immer auf.
static func auf(layer: Control, q: Dictionary) -> bool:
	if q.is_empty() or not layer.has_meta("uz_flug") or ruhig():
		return false
	var k := str(layer.get_meta("uz_flug"))
	if k == "" or k != str(q.get("key", "")):
		return false
	var ziel: Control = layer.call("flug_ziel") if layer.has_method("flug_ziel") else null
	if ziel == null or not is_instance_valid(ziel):
		return false
	var karte: Control = (q.weak as WeakRef).get_ref() if q.get("weak") is WeakRef else null
	var start := _uebernehmen(k)
	if start.is_empty():
		start = q.get("bild", {})
		# Die Auswahl hatte noch kein Bild (lädt gerade): jetzt noch einmal fragen.
		if start.is_empty() and karte:
			start = bild_von(karte)
	if start.is_empty():
		return false
	layer.set_meta("uz_flug_quelle", q.get("weak"))
	var f := new()
	f.key = k
	f.art = str(layer.get_meta("uz_flug_art", "landen"))
	f.dauer = T_AUF
	f._a = start
	f._ziel = weakref(ziel)
	f._einsetzen(layer)
	if karte:
		f._verbergen(_versteck_von(karte))
	if f.art == "landen":
		f._verbergen(ziel)
	# Das Bild ist schon geladen: Ein Ziel, das seins erst holt, nimmt gleich dieses.
	if ziel.has_method("flug_bild_da"):
		ziel.call("flug_bild_da", start.tex)
	_nachgleiten(layer)
	# Eine Seite nennt sich selbst als Fläche: Grund zuerst, Schrift danach (Layer._auf_flaeche).
	var seite: bool = layer.has_method("flaeche") and layer.call("flaeche") == layer
	if f.art == "landen":
		if seite:
			layer.call("_auf_flaeche", layer, U.T_ANTWORT)
		else:
			U.tw(layer, "uz_layer").tween_property(layer, "modulate:a", 1.0, U.T_ORT)
	else:
		# Aufloesen: Die Seite kommt erst, wenn das Bild fast da ist – sonst stünde es kurz
		# doppelt (Bild im Flug und dasselbe Bild in der Seite).
		var tw := U.tw(layer, "uz_layer").set_parallel(true)
		var spaet := T_AUF * 0.36
		tw.tween_property(layer, "modulate:a", 1.0, T_SEITE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(spaet)
		if seite:
			for ch in layer.call("schrift"):
				if ch is CanvasItem and (ch as CanvasItem).visible:
					(ch as CanvasItem).modulate.a = 0.0
					tw.tween_property(ch, "modulate:a", 1.0, U.T_ORT).set_delay(spaet + U.T_ANTWORT)
	return true


## Ebene geht zu (Layer.close, nachdem Nav die Auswahl zurückgegeben hat): zurück zur Karte.
static func zu(layer: Control) -> void:
	if not layer.has_meta("uz_flug") or ruhig() or not layer.has_meta("uz_flug_quelle"):
		return
	var k := str(layer.get_meta("uz_flug"))
	var ziel: Control = layer.call("flug_ziel") if layer.has_method("flug_ziel") else null
	var start := _uebernehmen(k)
	if start.is_empty() and ziel and is_instance_valid(ziel):
		start = bild_von(ziel)
	if start.is_empty():
		return
	var f := new()
	f.key = k
	f.art = str(layer.get_meta("uz_flug_art", "landen"))
	f.zurueck = true
	f.dauer = T_ZU
	f._a = start
	f._such_key = k
	var w: Variant = layer.get_meta("uz_flug_quelle")
	f._such_weak = w if w is WeakRef else null
	f._einsetzen(layer)
	if ziel and is_instance_valid(ziel):
		f._verbergen(ziel)
	# Die Karte gleich verbergen, wenn sie noch steht (sonst blitzt sie ein Bild lang auf).
	var karte: Variant = f._such_weak.get_ref() if f._such_weak else null
	if karte is Control and is_instance_valid(karte) and karte.is_inside_tree():
		f._verbergen(_versteck_von(karte))


## Inhalt der neuen Seite gleitet ein Stück nach oben (nur die Bildlauf-Flächen direkt in der
## Ebene; ihre Lage setzt sonst niemand, Hintergrundbilder bleiben stehen). In ganzen Pixeln mit
## sauberem Schluss (U.px_schluss): kein einzelnes spätes Pixel.
static func _nachgleiten(layer: Control) -> void:
	for c in layer.get_children():
		if c is ScrollContainer:
			var sc := c as ScrollContainer
			var y := sc.position.y
			sc.position.y = y + U.weg_px(GLEITEN)
			U.px_weg(U.ankommen(sc, U.T_RAUM, "uz_flug_gleiten"), sc, "uz_px_gleiten", U.weg_px(GLEITEN), U.T_RAUM, func(p: float) -> void:
				sc.position.y = y + p
			)


## Läuft schon ein Flug mit diesem Schlüssel: dessen Bild, wie es gerade aussieht, und ihn beenden.
static func _uebernehmen(k: String) -> Dictionary:
	var alt: Variant = _laufend.get(k)
	if alt == null or not is_instance_valid(alt):
		_laufend.erase(k)
		return {}
	var f: Control = alt
	var jetzt: Dictionary = f.get("_jetzt")
	f.call("_beenden")
	return jetzt


## Was eine Karte verbirgt, solange ihr Bild fliegt (Meta "uz_flug_hide", sonst sie selbst).
static func _versteck_von(c: Control) -> Control:
	var h: Variant = c.get_meta("uz_flug_hide") if c.has_meta("uz_flug_hide") else null
	if h is Control and is_instance_valid(h):
		return h
	if c.has_method("flug_bild"):
		var d: Dictionary = c.call("flug_bild")
		if d.get("hide") is Control and is_instance_valid(d.hide):
			return d.hide
	return c


# --- Bilder ------------------------------------------------------------------------------------

## Was ein Element zeigt, in Bildschirm-Koordinaten:
##   { tex (Grundbild, nie AtlasTexture), src (Ausschnitt darin), voll (größtmöglicher Ausschnitt),
##     rect, radius, rund, tint, scrim }
## Leer, wenn es (noch) kein Bild hat. flug_bild() darf liefern: node (die Bildfläche), tex, rect
## (in Koordinaten von node), radius, rund, fit (ganz eingepasst statt gefüllt), tint, scrim.
static func bild_von(c: Control) -> Dictionary:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		return {}
	var d: Dictionary = {}
	if c.has_method("flug_bild"):
		d = c.call("flug_bild")
	elif c is TextureRect:
		d = { "node": c }
	if d.is_empty():
		return {}
	var n: Control = d.get("node", c)
	if n == null or not is_instance_valid(n) or not n.is_visible_in_tree():
		return {}
	var tex: Texture2D = d.get("tex", (n as TextureRect).texture if n is TextureRect else null)
	if tex == null or tex.get_width() < 1 or tex.get_height() < 1:
		return {}
	var xf := n.get_global_transform()
	var local: Rect2 = d.get("rect", Rect2(Vector2.ZERO, n.size))
	var rect := Rect2(xf * local.position, local.size * xf.get_scale())
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return {}
	var g := grund(tex)
	var base: Texture2D = g[0]
	var region: Rect2 = g[1]
	# Zuschnitt: Der Ausschnitt darf bis an den Rand des ganzen Bilds wandern.
	var voll := Rect2(Vector2.ZERO, base.get_size()) if tex is AtlasTexture and tex.has_meta("uz_crop") else region
	var src: Rect2
	var fit := bool(d.get("fit", false))
	var gestreckt := false
	if n is TextureRect and not d.has("fit"):
		var sm := (n as TextureRect).stretch_mode
		fit = sm in [TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED]
		gestreckt = sm == TextureRect.STRETCH_SCALE
	if d.has("src"):
		var s: Rect2 = d.src
		src = Rect2(region.position + s.position, s.size)
	elif fit:
		src = region
		rect = einpassen(region.size, rect)
	elif gestreckt:
		src = region
	else:
		src = fuellen(region, rect.size.x / rect.size.y)
	var tint: Color = d.get("tint", n.modulate * n.self_modulate)
	tint.a = 1.0
	var rund := bool(d.get("rund", false))
	var radius := float(d.get("radius", UzTheme.r_cover()))
	if rund:
		radius = minf(rect.size.x, rect.size.y) * 0.5
	return { "tex": base, "src": src, "voll": voll, "rect": rect, "radius": radius, "rund": rund, "tint": tint,
		"scrim": 1.0 if bool(d.get("scrim", n.has_node("UzScrim"))) else 0.0 }


## Grundbild und Ausschnitt einer Textur (AtlasTexture auch verschachtelt aufgelöst).
static func grund(tex: Texture2D) -> Array:
	var r := Rect2(Vector2.ZERO, tex.get_size())
	var t: Texture2D = tex
	var tiefe := 0
	while t is AtlasTexture and (t as AtlasTexture).atlas != null and tiefe < 4:
		var a := t as AtlasTexture
		var reg := a.region if a.region.size.x > 0.0 and a.region.size.y > 0.0 else Rect2(Vector2.ZERO, a.atlas.get_size())
		r = Rect2(reg.position + r.position, r.size)
		t = a.atlas
		tiefe += 1
	return [t, r]


## Mittiger Ausschnitt von region im Seitenverhältnis aspect (Breite / Höhe), so groß wie möglich.
static func fuellen(region: Rect2, aspect: float) -> Rect2:
	if aspect <= 0.0 or region.size.y <= 0.0:
		return region
	var s := region.size
	if s.x / s.y > aspect:
		var w := s.y * aspect
		return Rect2(region.position + Vector2((s.x - w) * 0.5, 0.0), Vector2(w, s.y))
	var h := s.x / aspect
	return Rect2(region.position + Vector2(0.0, (s.y - h) * 0.5), Vector2(s.x, h))


## Ganzes Bild der Größe ts in box eingepasst, mittig.
static func einpassen(ts: Vector2, box: Rect2) -> Rect2:
	if ts.x <= 0.0 or ts.y <= 0.0:
		return box
	var k := minf(box.size.x / ts.x, box.size.y / ts.y)
	var sz := ts * k
	return Rect2(box.position + (box.size - sz) * 0.5, sz)


## Ausschnitt mit Höhe h im Seitenverhältnis aspect um mitte, ganz innerhalb von voll (wird nötig
## kleiner, nie verzerrt).
static func ausschnitt(voll: Rect2, mitte: Vector2, h: float, aspect: float) -> Rect2:
	var sz := Vector2(h * aspect, h)
	if sz.x > voll.size.x:
		sz *= voll.size.x / sz.x
	if sz.y > voll.size.y:
		sz *= voll.size.y / sz.y
	var pos := (mitte - sz * 0.5).clamp(voll.position, voll.end - sz)
	return Rect2(pos, sz)


## Weg der Feder für die Zeit x (0…1): von 0 nach 1 (kritisch gedämpft: ohne Überschwingen),
## auf genau 1 bei x = 1 gestreckt – der Rest der Feder (0,7 %) wird über den Weg verteilt statt
## als Ausläufer unter einem Pixel nachzulaufen.
static func feder(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return _feder_roh(x) / _feder_roh(1.0)


static func _feder_roh(x: float) -> float:
	if DAEMPFUNG >= 1.0:
		return 1.0 - exp(-STEIF * x) * (1.0 + STEIF * x)
	var wd := STEIF * sqrt(1.0 - DAEMPFUNG * DAEMPFUNG)
	var e := exp(-DAEMPFUNG * STEIF * x)
	return 1.0 - e * (cos(wd * x) + DAEMPFUNG * STEIF / wd * sin(wd * x))


## Rechteck zwischen a und b: Mitte waagerecht mit px, senkrecht mit py, Größe mit ps.
static func zwischen(a: Rect2, b: Rect2, px: float, py: float, ps: float) -> Rect2:
	var ca := a.get_center()
	var cb := b.get_center()
	var c := Vector2(lerpf(ca.x, cb.x, px), lerpf(ca.y, cb.y, py))
	var s := a.size.lerp(b.size, ps).max(Vector2.ONE)
	return Rect2(c - s * 0.5, s)


# --- Der Flug ---------------------------------------------------------------------------------

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## In die Ebenenablage neben die Ebene: über ihr (landen, und jeder Rückflug: Das Bild löst sich
## aus der Seite, die darunter ausblendet) oder darunter (aufloesen beim Öffnen).
func _einsetzen(layer: Control) -> void:
	var host := layer.get_parent()
	host.add_child(self)
	host.move_child(self, layer.get_index() + (1 if art == "landen" or zurueck else 0))
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	# Ein Bild desselben Schlüssels, das gerade nach seiner Landung ausblendet, geht sofort.
	for c in host.get_children():
		if c != self and c.get_script() == get_script() and c.get("key") == key and bool(c.get("_faellt")):
			c.call("_beenden")
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_bild = Control.new()
	_bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bild.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bild.material = _mat
	_bild.draw.connect(_zeichne_bild)
	add_child(_bild)
	_sb = StyleBoxFlat.new()
	_sb.draw_center = false
	_sb.anti_aliasing = true
	_laufend[key] = self
	protokoll.append({ "key": key, "art": art, "zurueck": zurueck })
	if protokoll.size() > 64:
		protokoll.pop_front()
	_jetzt = _a.duplicate()
	_b = {}
	if not zurueck:
		_b = bild_von(_ziel.get_ref())


## Solange das Bild fliegt, zeichnet das Element nicht – unsichtbar nur für die Grafik
## (RenderingServer), ohne visible oder modulate anzufassen: Auswahl, Layout und eigene
## Animationen (Reihen blenden ihre Karten am Rand selbst aus) laufen ungestört weiter.
func _verbergen(n: Control) -> void:
	if n == null or not is_instance_valid(n):
		return
	for w in _versteckt:
		if (w as WeakRef).get_ref() == n:
			return
	_versteckt.append(weakref(n))
	_unsichtbar[n.get_instance_id()] = true
	RenderingServer.canvas_item_set_visible(n.get_canvas_item(), false)
	_um_neu(n)


## Wer um ein verborgenes Bild herum zeichnet (Spiegelung unter dem Cover), zeichnet neu – bis zur
## Karte (flug_bild), höchstens drei Ebenen hinauf.
static func _um_neu(n: Node) -> void:
	var p := n.get_parent()
	for k in 3:
		if not (p is CanvasItem):
			return
		(p as CanvasItem).queue_redraw()
		if p.has_method("flug_bild"):
			return
		p = p.get_parent()


## Verborgenes wieder zeigen; sanft: kurz einblenden (unter dem Bild, das danach geht – so
## erscheint auch die Schrift einer Karte weich statt auf einen Schlag).
func _zeigen(sanft := false) -> void:
	for w in _versteckt:
		var n: Control = (w as WeakRef).get_ref()
		if n == null or not is_instance_valid(n):
			continue
		_unsichtbar.erase(n.get_instance_id())
		RenderingServer.canvas_item_set_visible(n.get_canvas_item(), n.visible)
		_um_neu(n)
		if sanft and n.is_inside_tree():
			_wieder.append(w)
			RenderingServer.canvas_item_set_modulate(n.get_canvas_item(), Color(n.modulate, 0.0))
	_versteckt.clear()


## Sanftes Wiederzeigen: t von 0 (unsichtbar) bis 1 (wie das Element es selbst will).
func _einblenden(t: float) -> void:
	for w in _wieder:
		var n: Control = (w as WeakRef).get_ref()
		if n and is_instance_valid(n):
			RenderingServer.canvas_item_set_modulate(n.get_canvas_item(), Color(n.modulate, n.modulate.a * clampf(t, 0.0, 1.0)))
	if t >= 1.0:
		_wieder.clear()


## Ist n gerade wegen eines Flugs unsichtbar? (Für Tests.)
static func verborgen(n: Control) -> bool:
	return n != null and _unsichtbar.has(n.get_instance_id())


func _process(dt: float) -> void:
	_bilder += 1
	var step := minf(dt, DT_START if _bilder <= 2 else DT_MAX)
	if Leicht.active:
		step *= Leicht.ANIM_SPEED
	if _faellt:
		_aus += step / T_AUS
		_einblenden((_aus + 0.6) / 0.6)
		modulate.a = clampf(1.0 - _aus, 0.0, 1.0)
		if _aus >= 1.0:
			_beenden()
		return
	if _such_key != "":
		_ziel_suchen()
		if _faellt or is_queued_for_deletion():
			return
	for w in _versteckt:
		var n: Control = (w as WeakRef).get_ref()
		if n and is_instance_valid(n):
			RenderingServer.canvas_item_set_visible(n.get_canvas_item(), false)
	var z: Control = _ziel.get_ref() if _ziel else null
	if z == null or not is_instance_valid(z) or not z.is_inside_tree() or (zurueck and not z.is_visible_in_tree()):
		# Ziel weg (Seite ohne Schließen entfernt, Liste neu gebaut, gleich ein Video darüber):
		# hier ausblenden.
		_ausblenden()
		return
	var b := bild_von(z)
	if b.is_empty():
		# Ziel ohne Bild (Player über mpv, Karte ohne geladenes Bild): nur die Lage zählt.
		b = _nur_lage(z)
	if b.is_empty():
		# Das Ziel hat noch keinen Platz (Seite eben erst gebaut): kurz an der Karte warten.
		_warten += step
		if _warten > 0.4:
			_ausblenden()
		return
	_b = b
	_x += step / dauer
	_bild.queue_redraw()
	queue_redraw()
	if _x >= 1.0 or (art == "landen" or zurueck) and _fast_da():
		_landen()


## Pixel-Schluss: Fehlt an Lage und Größe überall weniger als ein halbes Pixel, ist das Bild da –
## ein Ausläufer darunter wäre nur noch ein einzelnes spätes Pixel.
func _fast_da() -> bool:
	if _b.is_empty() or not _b.has("rect"):
		return false
	var r: Rect2 = _stand().rect
	var z: Rect2 = _b.rect
	return absf(r.position.x - z.position.x) < 0.5 and absf(r.position.y - z.position.y) < 0.5 \
			and absf(r.end.x - z.end.x) < 0.5 and absf(r.end.y - z.end.y) < 0.5


## Rückflug: Die Karte steht erst nach dem Schließen wieder da (Liste sichtbar, Auswahl zurück).
func _ziel_suchen() -> void:
	var k := _such_key
	_such_key = ""
	var karte := finde_karte(k, _such_weak.get_ref() if _such_weak else null)
	if karte == null:
		# Keine Karte: Das Bild gehört wieder der Seite und blendet mit ihr aus.
		_beenden()
		return
	_ziel = weakref(karte)
	_verbergen(_versteck_von(karte))


## Die Karte zum Schlüssel: die gemerkte, wenn sie noch steht, sonst eine neue mit demselben
## Schlüssel in der Ansicht unter der Ebene. Nur sichtbare Karten auf (oder nahe) dem Bildschirm.
static func finde_karte(k: String, gemerkt: Variant) -> Control:
	if gemerkt is Control and is_instance_valid(gemerkt) and _passt(gemerkt, k):
		return gemerkt
	var root: Control = Nav.scope_root()
	if root == null:
		return null
	for n in root.find_children("*", "Control", true, false):
		if (n as Control).has_meta("uz_flug") and _passt(n, k):
			return n
	return null


static func _passt(c: Control, k: String) -> bool:
	if str(c.get_meta("uz_flug", "")) != k or not c.is_visible_in_tree():
		return false
	var vp := c.get_viewport_rect()
	var r := c.get_global_rect()
	# Eine Bildschirmhöhe Luft: Die Liste rückt die Karte gleich wieder ins Bild.
	return vp.grow(vp.size.y).intersects(r) and r.size.x > 1.0


## Ziel ohne Bild: die Fläche, in der es läge (rund wie das Bild, mit dem es losflog).
func _nur_lage(z: Control) -> Dictionary:
	var xf := z.get_global_transform()
	var rect := Rect2(xf.origin, z.size * xf.get_scale())
	if z.has_method("flug_bild"):
		var d: Dictionary = z.call("flug_bild")
		var n: Control = d.get("node", z)
		if n and is_instance_valid(n):
			xf = n.get_global_transform()
			var lr: Rect2 = d.get("rect", Rect2(Vector2.ZERO, n.size))
			rect = Rect2(xf * lr.position, lr.size * xf.get_scale())
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return {}
	var rund := bool(_a.get("rund", false))
	return { "rect": rect, "radius": minf(rect.size.x, rect.size.y) * 0.5 if rund else float(_a.get("radius", 0.0)),
		"rund": rund, "tint": _a.get("tint", Color.WHITE), "scrim": 0.0, "leer": true }


func _landen() -> void:
	if _gelandet:
		return
	_gelandet = true
	_x = 1.0
	_bild.queue_redraw()
	queue_redraw()
	# Erst das Ziel darunter einblenden, dann das Bild darüber weg: nie ein Bild lang halb durchsichtig.
	_zeigen(true)
	if _laufend.get(key) == self:
		_laufend.erase(key)
	_faellt = true
	_aus = -0.6


func _ausblenden() -> void:
	_zeigen()
	if _laufend.get(key) == self:
		_laufend.erase(key)
	_faellt = true


## Sofort weg (ein neuer Flug übernimmt, oder fertig ausgeblendet).
func _beenden() -> void:
	_zeigen()
	_einblenden(1.0)
	if _laufend.get(key) == self:
		_laufend.erase(key)
	set_process(false)
	queue_free()


func _exit_tree() -> void:
	_zeigen()
	_einblenden(1.0)
	if _laufend.get(key) == self:
		_laufend.erase(key)


## Stand des Flugs: Lage, Größe, Ecken, Überblendung zum Bild des Ziels.
func _stand() -> Dictionary:
	var b := _b if not _b.is_empty() else _a
	var x := clampf(_x, 0.0, 1.0)
	var py := feder(x)
	var px := feder(minf(1.0, x * BOGEN))
	var ra: Rect2 = _a.rect
	var rb: Rect2 = b.rect
	var r := zwischen(ra, rb, px, py, py)
	var rund := bool(_a.get("rund", false)) and bool(b.get("rund", false))
	var radius := minf(r.size.x, r.size.y) * 0.5 if rund else lerpf(float(_a.radius), float(b.radius), clampf(py, 0.0, 1.0))
	# Zum Bild des Ziels überblenden (wenn es ein anderes ist, etwa das Hintergrundbild eines Films).
	var mix := 0.0
	if b.has("tex") and not bool(b.get("leer", false)) and b.tex != _a.tex:
		mix = smoothstep(0.2, 0.5, x)
	# Gehoben ist es, solange es sich bewegt (am meisten auf halbem Weg).
	return { "rect": r, "radius": radius, "p": py, "mix": mix, "b": b, "lift": sin(PI * clampf(py, 0.0, 1.0)) }


func _draw() -> void:
	var st := _stand()
	var inv := get_global_transform().affine_inverse()
	var r: Rect2 = st.rect
	r = Rect2(inv * r.position, r.size * inv.get_scale())
	var lift: float = st.lift
	var k := Leicht.SHADOW_K if Leicht.active else 1.0
	if Leicht.active:
		lift = 0.0
	# Das Bild hebt sich aus der Karte: Schatten wächst im Flug und setzt sich beim Landen.
	_sb.set_corner_radius_all(int(st.radius))
	_sb.shadow_color = Color(0, 0, 0, (0.32 + 0.2 * lift) * _deckung())
	_sb.shadow_size = int((18.0 + 26.0 * lift) * k)
	_sb.shadow_offset = Vector2(0, (10.0 + 14.0 * lift) * k)
	if r.size.x < get_viewport_rect().size.x * 0.9:
		draw_style_box(_sb, r)


## Wie deckend das Bild gerade ist (aufloesen: geht zum Ende hin in der Seite auf).
func _deckung() -> float:
	if art == "landen" or zurueck:
		return 1.0
	return 1.0 - smoothstep(0.55, 1.0, clampf(_x, 0.0, 1.0))


func _zeichne_bild() -> void:
	var st := _stand()
	var inv := _bild.get_global_transform().affine_inverse()
	var gr: Rect2 = st.rect
	var r := Rect2(inv * gr.position, gr.size * inv.get_scale())
	_mat.set_shader_parameter("box", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_mat.set_shader_parameter("radius", minf(float(st.radius), minf(r.size.x, r.size.y) * 0.5))
	var b: Dictionary = st.b
	var p: float = st.p
	var aspect := r.size.x / maxf(r.size.y, 1.0)
	var tint: Color = (_a.tint as Color).lerp(b.get("tint", _a.tint), clampf(p, 0.0, 1.0))
	tint.a = _deckung()
	var src_a := _src_fuer(_a, b, p, aspect)
	draw_texture_rect_region_on(_bild, _a.tex, r, src_a, tint)
	var src_now := src_a
	var tex_now: Texture2D = _a.tex
	var mix: float = st.mix
	if mix > 0.0:
		var src_b := _src_fuer(b, _a, 1.0 - p, aspect)
		draw_texture_rect_region_on(_bild, b.tex, r, src_b, Color(tint, tint.a * mix))
		if mix >= 0.5:
			src_now = src_b
			tex_now = b.tex
	var scrim := lerpf(float(_a.get("scrim", 0.0)), float(b.get("scrim", 0.0)), clampf(p, 0.0, 1.0))
	if scrim > 0.01 and not Leicht.active:
		_bild.draw_texture_rect(Zuschnitt.scrim(), r, false, Color(1, 1, 1, scrim * tint.a))
	# Für eine Übernahme (B mitten im Flug): so sieht es gerade aus.
	_jetzt = { "tex": tex_now, "src": src_now, "voll": _a.voll if tex_now == _a.tex else b.get("voll", src_now),
		"rect": gr, "radius": float(st.radius), "rund": bool(_a.get("rund", false)) and bool(b.get("rund", false)),
		"tint": Color(tint, 1.0), "scrim": scrim }


static func draw_texture_rect_region_on(ci: CanvasItem, t: Texture2D, r: Rect2, src: Rect2, c: Color) -> void:
	if t == null or c.a <= 0.003:
		return
	ci.draw_texture_rect_region(t, r, src, c)


## Ausschnitt eines Endes e für die Zeit: Mitte und Höhe wandern von e zum Format des anderen
## Endes o (p = 0: genau wie bei e, p = 1: so, wie e im Format von o aussähe).
func _src_fuer(e: Dictionary, o: Dictionary, p: float, aspect: float) -> Rect2:
	var s: Rect2 = e.src
	var voll: Rect2 = e.get("voll", s)
	var ro: Rect2 = o.get("rect", e.rect)
	var re: Rect2 = e.rect
	var asp_o := ro.size.x / maxf(ro.size.y, 1.0)
	var asp_e := re.size.x / maxf(re.size.y, 1.0)
	# Wie sähe e im Format von o aus? Der größte Ausschnitt um dieselbe Mitte, nicht verzerrt.
	var o_src := ausschnitt(voll, s.get_center(), s.size.y if asp_o <= asp_e else s.size.x / asp_o, asp_o)
	var q := clampf(p, -0.05, 1.05)
	var h := lerpf(s.size.y, o_src.size.y, q)
	var mitte := s.get_center().lerp(o_src.get_center(), clampf(q, 0.0, 1.0))
	return ausschnitt(voll, mitte, maxf(h, 1.0), aspect)
