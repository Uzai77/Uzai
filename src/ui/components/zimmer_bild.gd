extends Control
## Kleines Live-Bild von „Dein Zimmer“ (Vitrine im Profil): das eigene Zimmer in einer eigenen
## kleinen Ansicht, die Kamera kreist langsam darüber – wie die Vorschau beim Einführen eines
## Zimmers (src/room/einfuehren_ui.gd), immer in der leichten Stufe. Im leichten Modus ein stilles
## Bild. A betritt das Zimmer.
##
## Ruhig beim Wechseln: Die Welt (3D-Zimmer in einer SubViewport) baute früher jedes neue Bild
## selbst – im Aufbau der Profilseite und in den ersten Bildern danach (Pipelines, Netze): beim
## Wechsel der Unterbereiche mit LB/RB vier lange Bilder mitten im Hereingleiten, die Bewegung
## sprang. Jetzt hält ein Halter (am Wurzelknoten) die eine Welt für alle Zimmerbilder; ein
## Zimmerbild zeigt nur deren Bild (ViewportTexture). Gebaut wird erst, wenn das Bild still steht
## (kein Wechsel läuft); unsichtbar nur hinter der Startanimation (Vorbauen beim Start). Dann blendet
## das Bild weich auf. Nicht mehr unsichtbar im laufenden Betrieb: Ruhte man im Shop, baute der
## Vorbau der Nachbarseite „Profil“ das ganze Zimmer – ein Stillstand von Sekunden und der Speicher
## einer 3D-Welt für eine Seite, die man vielleicht nie öffnet.
## Die Welt bleibt, solange ein Zimmerbild besteht, und HALTEN_MS danach; ein geändertes Zimmer
## baut sie neu. Gerendert wird nur, solange ein Zimmerbild zu sehen ist.
##
## Der Bau selbst läuft über mehrere Bilder (zimmer_welt.gd bauen_gestreckt): In einem Zug stand beim
## ersten Mal alles rund 1 s still (gemessen), auch die Eingabe. Er ruht, solange etwas hereingleitet,
## eine Ebene offen ist oder kein Zimmerbild zu sehen ist (Halter.frei_bild). Vorher laden die Karten und
## Modelle des Zimmers im Hintergrund (Welt.vorlade_pfade); der Bau wartet darauf höchstens VORLADEN_MS.

signal activated

const U := preload("res://src/ui/u.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Welt := preload("res://src/room/zimmer_welt.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

const HALTEN_MS := 180000      ## so lange bleibt die Welt ohne Zimmerbild (Unterbereiche hin und zurück)
const VORLADEN_MS := 6000      ## länger wartet der Bau nicht auf das Vorladen (dann lädt er selbst)
const RUHE_BILDER := 6         ## so viele ruhige Bilder nacheinander, bevor gebaut wird

static var _halter: Halter = null

var _r := 18
var _bild: TextureRect
var _daten: Dictionary = {}
var _sig := 0
var _da := false               ## das Bild der Welt ist zu sehen (aufgeblendet)
var _vor: Array[String] = []   ## Karten und Modelle des Zimmers, die im Hintergrund vorladen
var _vor_ab := 0               ## seit wann (Time.get_ticks_msec)
var _ruhe := 0                 ## Bilder in Folge, in denen das Bild still und frei zu sehen war
var _vorbau := false           ## unsichtbar entstanden: bauen, sobald der Halter im Baum ist


func setup(sz: Vector2) -> Control:
	custom_minimum_size = sz
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta("uz_hint_a", "Betreten")
	set_meta("uz_key", "apps:zimmer")
	_r = maxi(8, UzTheme.r_panel() - 4)
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), _r))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(clip)
	add_child(clip)
	_bild = TextureRect.new()
	_bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bild.modulate.a = 0.0
	U.full_rect(_bild)
	clip.add_child(_bild)
	_daten = Daten.laden()
	_sig = _daten.hash()
	var h := _halter_holen()
	if h.fertig(_sig):
		_zeigen(false)
	else:
		_vor = dateien_vorladen(_daten, true)
		_vor_ab = Time.get_ticks_msec()
		# Unsichtbar vorgebaut hinter der Startanimation (main._prebuild): gleich bauen.
		_vorbau = not is_visible_in_tree() and _hinter_start()
	# Aufbau vorab: Das Zimmer selbst (Skripte) lädt schon im Hintergrund, solange sein Bild zu
	# sehen ist – A betritt es dann ohne langes Laden.
	var m: Node = get_tree().current_scene
	if m and m.has_method("zimmer_vorladen"):
		m.call_deferred("zimmer_vorladen")
	focus_entered.connect(func() -> void: U.focus_anim(self, true))
	focus_exited.connect(func() -> void: U.focus_anim(self, false))
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			activate()
			accept_event())


func _enter_tree() -> void:
	if is_instance_valid(_halter):
		_halter.nutzer += 1


func _exit_tree() -> void:
	if is_instance_valid(_halter):
		_halter.nutzer = maxi(0, _halter.nutzer - 1)
		_halter.zuletzt_ms = Time.get_ticks_msec()


func activate() -> void:
	activated.emit()


func _process(_dt: float) -> void:
	var h := _halter_holen()
	var da := is_visible_in_tree()
	if _vorbau and h.is_inside_tree():
		# Hinter der Startanimation unsichtbar bauen; ist sie vorbei, wartet der Rest, bis das Bild zu sehen ist.
		if da or h.fertig(_sig):
			_vorbau = false
		elif _hinter_start() and _vorgeladen():
			h.frei_bild = Engine.get_process_frames()
			h.bauen(_daten, _sig, _groesse())
	if not da:
		_ruhe = 0
		# Unsichtbar fertig geworden: Das Bild steht schon, wenn die Seite kommt.
		if not _da and h.fertig(_sig) and Engine.get_process_frames() - h.gebaut_bild >= 2:
			_zeigen(false)
		return
	if not h.fertig(_sig):
		# Erst bauen, wenn nichts mehr hereingleitet und keine Ebene darüber liegt: Der Aufbau der Welt
		# kostet beim ersten Mal ein paar längere Bilder. Ein paar ruhige Bilder abwarten – das Hereingleiten
		# eines Bereichs beginnt erst zwei Bilder nach dem Wechsel (main.goto), der Bau finge sonst davor an.
		if _da:
			_da = false
			_bild.modulate.a = 0.0
		_ruhe = _ruhe + 1 if Nav.top_layer() == null and not _in_bewegung() else 0
		if h.is_inside_tree() and _ruhe >= RUHE_BILDER and _vorgeladen():
			h.frei_bild = Engine.get_process_frames()
			h.bauen(_daten, _sig, _groesse())
		return
	h.gesehen = Engine.get_process_frames()
	# Aufblenden erst, wenn die Welt einmal gezeichnet ist (das erste Bild ist das teure).
	if not _da and Engine.get_process_frames() - h.gebaut_bild >= 2:
		_zeigen(true)


## Karten und Modelle des eigenen Zimmers im Hintergrund laden – auch für die Tür zum Zimmer (zimmer_tuer.gd):
## Der erste Bau lädt sie sonst selbst, mitten im Bau. Zurück: die Dateien.
static func dateien_vorladen(daten: Dictionary, zuerst := false) -> Array[String]:
	var pfade := Welt.vorlade_pfade(Halter.raum_von(daten))
	Arbeit.vorladen(pfade, zuerst)
	return pfade


## Sind Karten und Modelle des Zimmers im Hintergrund geladen (oder ist die Geduld um)?
func _vorgeladen() -> bool:
	return Arbeit.alle_geladen(_vor) or Time.get_ticks_msec() - _vor_ab > VORLADEN_MS


func _zeigen(weich: bool) -> void:
	_da = true
	_bild.texture = _halter.vp.get_texture()
	if weich and not U.reduziert():
		_bild.modulate.a = 0.0
		U.ankommen(_bild, U.T_ORT).tween_property(_bild, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE)
	else:
		_bild.modulate.a = 1.0


## Läuft die Startanimation noch? Nur dahinter darf die Welt unsichtbar entstehen.
func _hinter_start() -> bool:
	var m: Node = get_tree().current_scene
	return m != null and m.has_method("startet") and bool(m.call("startet"))


## Läuft über dem Bild gerade ein Wechsel (Bereich, Unterbereich, Neuaufbau) oder steht es in der
## Hülle eines Abgangs? Dann wartet der Aufbau der Welt.
func _in_bewegung() -> bool:
	var n: Node = get_parent()
	while n != null:
		if n.has_meta("uz_skip"):
			return true
		if n.has_method("im_uebergang") and bool(n.call("im_uebergang")):
			return true
		n = n.get_parent()
	return false


func _groesse() -> Vector2i:
	var s := size if size.x >= 1.0 and size.y >= 1.0 else custom_minimum_size
	return Vector2i(maxi(int(s.x), 8), maxi(int(s.y), 8))


func _halter_holen() -> Halter:
	if not is_instance_valid(_halter):
		_halter = Halter.new()
		_halter.name = "UzZimmerBild"
		get_tree().root.add_child.call_deferred(_halter)
		_halter.nutzer = 1 if is_inside_tree() else 0
	return _halter


func _draw() -> void:
	U.draw_focus(self, _r, Rect2(Vector2.ZERO, size).grow(6))


## Hält die eine Welt aller Zimmerbilder: SubViewport mit dem Zimmer, Kamera kreist, solange ein
## Zimmerbild zu sehen ist (gesehen = dieses oder letztes Bild); sonst zeichnet sie nicht.
class Halter extends Node:
	var vp: SubViewport
	var welt: Node3D
	var sig := 0
	var nutzer := 0                ## Zimmerbilder im Baum
	var zuletzt_ms := 0            ## wann das letzte Zimmerbild den Baum verließ
	var gesehen := -10             ## Bild (Engine.get_process_frames), in dem ein Zimmerbild zu sehen war
	var gebaut_bild := -10         ## Bild, in dem die Welt gebaut wurde
	var frei_bild := -10           ## Bild, in dem ein Zimmerbild den Bau zuletzt freigab (sonst ruht er)
	var _baut := false             ## die Welt entsteht gerade, über mehrere Bilder verteilt
	var _az := 0.5

	func _init() -> void:
		vp = SubViewport.new()
		vp.own_world_3d = true
		vp.audio_listener_enable_3d = false
		vp.positional_shadow_atlas_size = 0
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		zuletzt_ms = Time.get_ticks_msec()

	func fertig(s: int) -> bool:
		return is_instance_valid(welt) and sig == s and not _baut

	## Die Welt (neu) bauen: ein geändertes Zimmer ersetzt die alte, das Bild (Textur) bleibt dasselbe.
	## Läuft schon ein Bau, endet er erst (die Welt wird unterwegs nie freigegeben); das Zimmerbild fragt
	## danach wieder.
	func bauen(daten: Dictionary, s: int, groesse: Vector2i) -> void:
		if _baut:
			return
		if is_instance_valid(welt):
			vp.remove_child(welt)
			welt.queue_free()
		sig = s
		vp.size = groesse
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		Katalog.eigene_setzen(daten.get("eigene", []))
		welt = Welt.new()
		welt.huellen = daten.get("huellen", {})
		vp.add_child(welt)
		_baut = true
		var ganz: bool = await welt.bauen_gestreckt(raum_von(daten), "leicht", _frei)
		_baut = false
		if not ganz:
			if is_instance_valid(welt):
				welt.queue_free()
			welt = null
			sig = 0
			return
		gebaut_bild = Engine.get_process_frames()
		_kamera(0.0)
		# Einmal zeichnen, auch ungesehen: Pipelines und Netze sind dann bereit, bevor das Bild kommt.
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	## Der Raum, den das Bild zeigt: der zuletzt betretene, sonst der erste.
	static func raum_von(daten: Dictionary) -> Dictionary:
		var raum: Dictionary = (daten.raeume as Array)[0]
		for r in daten.raeume:
			if str(r.id) == str(daten.get("aktuell", "")):
				raum = r
		return raum

	## Darf der Bau in diesem Bild weiter? Nur, wenn ein Zimmerbild ihn eben freigegeben hat.
	func _frei() -> bool:
		return Engine.get_process_frames() - frei_bild <= 1

	func _process(dt: float) -> void:
		if _baut or not is_instance_valid(welt):
			return
		if nutzer <= 0 and Time.get_ticks_msec() - zuletzt_ms > HALTEN_MS:
			vp.remove_child(welt)
			welt.queue_free()
			welt = null
			sig = 0
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
		if Engine.get_process_frames() - gesehen > 1 or Leicht.active:
			if vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_kamera(dt)

	func _kamera(dt: float) -> void:
		_az += dt * 0.12
		var r: Dictionary = welt.raum
		var w := float(r.w) * Katalog.ZELLE
		var d := float(r.d) * Katalog.ZELLE
		var mitte := Vector3(w * 0.5, 0.45, d * 0.5)
		var hoehe := 0.78
		var dist := 9.6 * maxf(w, d) / 6.0
		var o := mitte + Vector3(sin(_az) * cos(hoehe), sin(hoehe), cos(_az) * cos(hoehe)) * dist
		welt.kamera.fov = 34.0
		welt.kamera.global_transform = Transform3D(Basis(), o).looking_at(mitte, Vector3.UP)
		welt.schnitt(o, true)
