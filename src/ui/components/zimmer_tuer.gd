extends Control
## Die Tür zu „Dein Zimmer“ (Bereich Zimmer, room_view.gd): Die ganze Fläche ist eine Tür in der Wand –
## Nussbaum mit Kassetten, Messingdrücker, ein Schild mit dem Namen, warmes Licht im Spalt und davor auf
## dem Boden (zimmer_tuer.gdshader, Farben aus dem Theme). Gewählt atmet der Lichtspalt leise.
## A: Eine Hand drückt die Tür auf, die Kamera geht hindurch – und dahinter liegt schon das echte Zimmer.
## Es wird beim Druck gebaut, während ein stilles Bild des Bildschirms (genau das, was eben zu sehen war)
## als Ebene über allem liegt; bewegt wird erst, wenn das Zimmer einige ruhige Bilder gezeichnet hat
## (seine Pipelines sind dann warm, zimmer_basis.gd _pipelines_planen). Durch die Öffnung sieht man das
## Zimmer selbst, seine Kamera tritt durch die eigene Tür herein (zimmer.gd tuer_hinein) – kein Schnitt,
## kein Ladebild. Je Bild kostet die Fahrt nur diesen einen Shader. Animationen reduzieren oder leichter
## Modus: Die Tür geht kurz auf, das Zimmer blendet über.

signal chosen(kind: String)

## Gruppe der Tür (main.open_room findet sie darüber) und: Die Tür geht gerade auf und öffnet gleich selbst
## das Zimmer – main schickt dann nicht noch einmal zur Tür.
const GRUPPE := "uz_zimmer_tuer"
static var unterwegs := false

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")
const SHADER := preload("res://src/ui/components/zimmer_tuer.gdshader")
const ZimmerBild := preload("res://src/ui/components/zimmer_bild.gd")

const HOEHE := 0.8                       ## Lichte der Tür: Anteil der Höhe der Fläche
const SEITE := 0.44                      ## Breite : Höhe der Lichte (0,92 × 2,08 m)
const BODEN := 0.88                      ## Unterkante der Tür (Anteil der Höhe)
const ZARGE := 0.11                      ## Zarge in Türbreiten (wie im Shader)
const HAND_S := 0.3                      ## die Hand kommt
const DRUCK_S := 0.14                    ## sie drückt
const AUF_S := 0.8                       ## die Tür schwingt auf
const ZOOM_S := 0.7                      ## hindurch
const WARTEN_S := 1.5                    ## höchstens so lange auf ruhige Bilder des Zimmers warten
const RUHIG_N := 4                       ## so viele ruhige Bilder nacheinander (je höchstens RUHIG_MS)
const RUHIG_MS := 34
const ZIMMER := "res://src/room/zimmer.gd"

var title := "Dein Zimmer"

var _szene: ColorRect
var _mat: ShaderMaterial
var _schild_vp: SubViewport
var _atmen_t := 0.0
var _laeuft := false
var _dateien_vor := false                ## Karten und Modelle des Zimmers laden schon vor (einmal je Tür)
var _ohne_ring := false
var _ebene: CanvasLayer


func setup(t: String) -> Control:
	title = t
	return self


func _ready() -> void:
	add_to_group(GRUPPE)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not has_meta("uz_key"):
		set_meta("uz_key", "room:betreten")
	if not has_meta("uz_hint_a"):
		set_meta("uz_hint_a", "Betreten")
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_farben()
	_schild_bauen()
	_szene = ColorRect.new()
	_szene.material = _mat
	_szene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_szene)
	add_child(_szene)
	resized.connect(_lage)
	_lage()
	set_process(false)
	focus_entered.connect(func() -> void:
		_zimmer_vorladen()
		set_process(not Leicht.active and not U.reduziert())
		_wahl(1.0)
		queue_redraw())
	focus_exited.connect(func() -> void:
		_wahl(0.0)
		queue_redraw())
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			activate()
			accept_event())
	visibility_changed.connect(_zurueck)


## Farben aus dem Theme: die Zarge aus der Oberfläche, das Blatt Nussbaum, das Licht warm mit einem Hauch
## des Akzents, Messing für Drücker und Schild.
func _farben() -> void:
	var hoch := UzTheme.col("surface_hi")
	var akzent := UzTheme.col("accent")
	_mat.set_shader_parameter("rahmen", hoch.lerp(Color(0.32, 0.27, 0.23), 0.55))
	_mat.set_shader_parameter("blatt", Color(0.36, 0.23, 0.15))
	_mat.set_shader_parameter("licht", Color(1.0, 0.76, 0.48).lerp(akzent, 0.12))
	_mat.set_shader_parameter("metall", Color(0.83, 0.65, 0.38))


## Der Name auf dem Schild: einmal in eine kleine Textur gezeichnet (der Shader legt sie aufs Blatt, sie
## dreht sich mit ihm).
func _schild_bauen() -> void:
	_schild_vp = SubViewport.new()
	_schild_vp.size = Vector2i(640, 132)
	_schild_vp.transparent_bg = true
	_schild_vp.disable_3d = true
	_schild_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var l := U.label(title, "xl", "text", "title")
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.uppercase = true
	l.add_theme_font_size_override("font_size", 72)
	l.add_theme_constant_override("outline_size", 0)
	l.position = Vector2.ZERO
	l.size = Vector2(_schild_vp.size)
	_schild_vp.add_child(l)
	add_child(_schild_vp)
	_mat.set_shader_parameter("schild", _schild_vp.get_texture())


## Lichte der Tür in der Fläche: mittig, so hoch wie HOEHE, unten auf BODEN.
func _tuer_rect() -> Rect2:
	var h := size.y * HOEHE
	var w := h * SEITE
	return Rect2(Vector2((size.x - w) * 0.5, size.y * BODEN - h), Vector2(w, h))


func _lage() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	var r := _tuer_rect()
	_mat.set_shader_parameter("groesse", size)
	_mat.set_shader_parameter("tuer", Vector4(r.position.x / size.x, r.position.y / size.y, r.end.x / size.x, r.end.y / size.y))
	queue_redraw()


func _wahl(ziel: float) -> void:
	if not is_inside_tree():
		return
	var jetzt: Variant = _mat.get_shader_parameter("gewaehlt")
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void: _mat.set_shader_parameter("gewaehlt", k), float(jetzt) if jetzt != null else 0.0, ziel,
			U.T_ORT / maxf(U.tempo(), 0.01))


func _process(dt: float) -> void:
	if not has_focus() or not is_visible_in_tree():
		set_process(false)
		_mat.set_shader_parameter("atmen", 0.0)
		return
	_atmen_t += dt
	_mat.set_shader_parameter("atmen", 0.5 + 0.5 * sin(_atmen_t * 2.1))


## Der Cursor liegt um die Zarge (die Tür ist das, was man wählt).
func _draw() -> void:
	if _ohne_ring:
		return
	var r := _tuer_rect()
	var z := r.size.x * ZARGE
	U.draw_focus(self, maxi(8, UzTheme.r_panel()), Rect2(r.position - Vector2(z, z), r.size + Vector2(z * 2.0, z)).grow(10))


## Das Zimmer (Skripte) schon im Hintergrund laden, solange die Tür zu sehen ist – und einmal je Tür die
## Karten und Modelle, die sein Bau braucht.
func _zimmer_vorladen() -> void:
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	if m and m.has_method("zimmer_vorladen"):
		m.call_deferred("zimmer_vorladen")
	if not _dateien_vor:
		_dateien_vor = true
		ZimmerBild.dateien_vorladen(ZimmerBild.Daten.laden())


func activate() -> void:
	if _laeuft or not is_inside_tree():
		return
	unterwegs = true
	await _hinein()
	unterwegs = false


func _exit_tree() -> void:
	unterwegs = false


func _hinein() -> void:
	_laeuft = true
	_zimmer_vorladen()
	if U.reduziert() or Leicht.active:
		var tw := create_tween()
		tw.tween_method(_auf, 0.0, 1.0, U.T_FAST)
		await tw.finished
		chosen.emit("room")
		return
	# 1. Ein stilles Bild des Bildschirms ohne Cursor: Es liegt gleich als Ebene über allem, während
	# darunter das Zimmer entsteht (der Aufbau hält das Bild an – man sieht nur, was eben schon da war).
	_ohne_ring = true
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var bild := get_viewport().get_texture().get_image()
	var voll := U.view_size()
	var r := _tuer_rect()
	var g := get_global_rect()
	var lichte := Rect2(g.position + r.position * (g.size / size), r.size * (g.size / size))
	var fahrt := _mat.duplicate() as ShaderMaterial
	fahrt.set_shader_parameter("groesse", voll)
	fahrt.set_shader_parameter("tuer", Vector4(lichte.position.x / voll.x, lichte.position.y / voll.y, lichte.end.x / voll.x, lichte.end.y / voll.y))
	fahrt.set_shader_parameter("kulisse", ImageTexture.create_from_image(bild))
	fahrt.set_shader_parameter("mit_kulisse", 1.0)
	fahrt.set_shader_parameter("durch", 1.0)
	_ebene = CanvasLayer.new()
	_ebene.layer = 90
	var flug := ColorRect.new()
	flug.material = fahrt
	flug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flug.position = Vector2.ZERO
	flug.size = voll
	_ebene.add_child(flug)
	get_tree().root.add_child(_ebene)
	# 2. Das Zimmer öffnen (main.open_room): Es weiß, dass es durch seine Tür betreten wird.
	set_meta("uz_tuer_fahrt", true)
	chosen.emit("room")
	remove_meta("uz_tuer_fahrt")
	await get_tree().process_frame
	var m: Node = get_tree().current_scene
	var zim: Node = m.call("room_layer") if m and m.has_method("room_layer") else null
	if zim == null or not zim.has_method("tuer_hinein"):
		_fahrt_weg()
		_zu()
		return
	# 3. Erst bewegen, wenn das Zimmer ruhig zeichnet (Pipelines warm, kein Ruckeln in der Fahrt).
	var t0 := Time.get_ticks_msec()
	var ruhig := 0
	var vorher := Time.get_ticks_msec()
	while ruhig < RUHIG_N and Time.get_ticks_msec() - t0 < WARTEN_S * 1000.0 and is_instance_valid(zim):
		await RenderingServer.frame_post_draw
		var jetzt := Time.get_ticks_msec()
		ruhig = ruhig + 1 if jetzt - vorher <= RUHIG_MS else 0
		vorher = jetzt
	if not is_instance_valid(zim) or not is_instance_valid(flug):
		_fahrt_weg()
		_zu()
		return
	# 4. Die Hand kommt und drückt, die Tür schwingt auf, die Kamera geht hindurch.
	# Ziel des Zooms: der freie Teil der Öffnung neben dem offenen Blatt (wie im Shader: WINKEL, TIEFE) –
	# am Ende deckt er den Schirm, und die Ebene geht, ohne dass etwas springt.
	var blatt := cos(1.38) / (1.0 + sin(1.38) * 0.42)
	var frei := Rect2(lichte.position + Vector2(lichte.size.x * blatt, 0.0), Vector2(lichte.size.x * (1.0 - blatt), lichte.size.y))
	var lc := Vector2(frei.get_center().x / voll.x, frei.get_center().y / voll.y)
	var k := maxf(voll.x / frei.size.x, voll.y / frei.size.y) * 1.1
	fahrt.set_shader_parameter("zoom_von", lc)
	fahrt.set_shader_parameter("zoom_nach", lc)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: fahrt.set_shader_parameter("hand", v), 0.0, 1.0, HAND_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: fahrt.set_shader_parameter("druck", v), 0.0, 1.0, DRUCK_S).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: Sfx.play("open"))
	tw.tween_method(func(v: float) -> void: fahrt.set_shader_parameter("auf", v), 0.0, 1.0, AUF_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_method(func(v: float) -> void: fahrt.set_shader_parameter("hand", v), 1.0, 0.0, AUF_S * 0.32) \
			.set_delay(AUF_S * 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_callback(func() -> void:
		if is_instance_valid(zim):
			zim.call("tuer_hinein", ZOOM_S + 1.1)).set_delay(AUF_S * 0.55)
	tw.parallel().tween_method(func(v: float) -> void: fahrt.set_shader_parameter("zoom", v), 1.0, k, ZOOM_S) \
			.set_delay(AUF_S * 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: Vector2) -> void: fahrt.set_shader_parameter("zoom_nach", v), lc, Vector2(0.5, 0.5), ZOOM_S) \
			.set_delay(AUF_S * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_fahrt_weg()


func _auf(k: float) -> void:
	_mat.set_shader_parameter("auf", k)


func _fahrt_weg() -> void:
	if is_instance_valid(_ebene):
		_ebene.queue_free()
	_ebene = null


## Wieder zu sehen (zurück aus dem Zimmer): Tür zu, bereit für das nächste Mal.
func _zurueck() -> void:
	if not is_visible_in_tree() or not _laeuft:
		return
	_zu()


func _zu() -> void:
	_laeuft = false
	_ohne_ring = false
	_auf(0.0)
	queue_redraw()
