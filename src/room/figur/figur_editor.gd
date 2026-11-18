extends "res://src/ui/layers/layer.gd"
## Editor für deine Figur und dein Haustier (Punkt 131 c): links eine warme kleine Bühne mit
## Figur und Tier auf einem Podest, rechts die Liste der Eigenschaften. Alles mit dem Controller:
##   Steuerkreuz hoch/runter wählt die Zeile, links/rechts ändert sie (sofort zu sehen; beim Tier
##   fährt die Kamera zum Tier), LB/RB Figur ↔ Haustier,
##   X führt ein Emote vor (beim Tier: freuen), Y würfelt, A beim Namen öffnet die Tastatur,
##   rechter Stick bzw. LT/RT drehen die Figur, B speichert und schließt.
## Was erst durchs Spielen frei wird, lässt sich ansehen (mit Schloss und Bedingung), getragen
## wird es erst, wenn der Meilenstein erreicht ist.

signal fertig

const D := preload("res://src/room/figur/figur_daten.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const M := preload("res://src/room/figur/meilensteine.gd")
const Avatar := preload("res://src/room/figur/avatar.gd")
const Tier := preload("res://src/room/figur/tier.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")
const Zimmer := preload("res://src/room/zimmer.gd")

const BREITE := 640.0
const ZEILE := 74.0
## Wohin die Kamera bei welcher Zeile schaut: [Ziel, Abstand].
const FOKUS := {
	"ganz": [Vector3(0, 0.82, 0), 3.5], "tier": [Vector3(0.62, 0.24, 0.3), 1.6],
}

var tab := "figur"
var erreichte: Array = []
var zimmer: Zimmer             ## das offene Zimmer (speichert); ohne Zimmer: direkt in die Datei
var daten := {}                  ## Arbeitskopie { figur, tier }
var _alle := {}                  ## die Zimmerdaten, in die gespeichert wird
var avatar: Avatar
var tier: Tier
var _sel := { "figur": 0, "tier": 0 }
var _vp: SubViewport
var _cam: Camera3D
var _cam_ziel := Vector3(0, 0.82, 0)
var _cam_abstand := 3.5
var _dreh := 0.0
var _dreh_soll := 0.0
var _emote := -1
var _liste: Control
var _inhalt: VBoxContainer
var _zeilen: Array = []
var _reiter: Array = []
var _sub: Label
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	super()
	dim = 0.0
	depth = false


func build() -> void:
	_scrim.color = Color(0, 0, 0, 0)
	_alle = zimmer.daten if zimmer else Daten.laden()
	daten = { "figur": D.pruefe_figur(_alle.get("figur")), "tier": D.pruefe_tier(_alle.get("tier")) }
	if erreichte.is_empty():
		var b := get_node_or_null("/root/Badges")
		erreichte = M.erreicht(b.get("facts") if b and "facts" in b else {})
	_rng.randomize()
	_buehne()
	_tafel()
	_zeigen(false)
	set_meta("uz_hint_b", "")


# --- Bühne ---------------------------------------------------------------------------------------

func _buehne() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(svc)
	add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.positional_shadow_atlas_size = 1024
	svc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2a2420")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f3e3cf")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.03
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Hintergrund: eine große, innen sichtbare Kugel mit warmem Verlauf und weichem Lichtfleck.
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, cull_front;\nvarying vec3 p;\nvoid vertex() { p = VERTEX; }\nvoid fragment() {\n\tvec3 n = normalize(p);\n\tfloat h = smoothstep(-0.2, 0.7, n.y);\n\tvec3 c = mix(vec3(0.36, 0.27, 0.21), vec3(0.13, 0.11, 0.1), h);\n\tvec2 q = vec2(atan(n.x, n.z) - 0.25, n.y - 0.1);\n\tc += vec3(0.32, 0.22, 0.14) * exp(-dot(q, q) * 3.0);\n\tALBEDO = c;\n}\n"
	var hm := ShaderMaterial.new()
	hm.shader = sh
	var kugel := SphereMesh.new()
	kugel.radius = 14.0
	kugel.height = 28.0
	var hk := MeshInstance3D.new()
	hk.mesh = kugel
	hk.material_override = hm
	hk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(hk)
	var boden := MeshInstance3D.new()
	boden.mesh = F.walze(6.0, 0.02, 0.01, 64)
	boden.material_override = S.stoff_farbig(Color("#6e5747"), 30.0, 0.6)
	boden.position.y = -0.02
	_vp.add_child(boden)
	var podest := MeshInstance3D.new()
	podest.mesh = F.walze(0.5, 0.06, 0.02, 48, true)
	podest.material_override = S.lack(Color("#6b4c39"), 0.55, 0.4)
	_vp.add_child(podest)
	var teppich := MeshInstance3D.new()
	teppich.mesh = F.walze(0.42, 0.012, 0.004, 40)
	teppich.material_override = S.stoff("creme", 90.0, 0.6)
	teppich.position = Vector3(0.66, 0.0, 0.32)
	_vp.add_child(teppich)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 32, 0)
	key.light_energy = 1.25
	key.light_color = Color("#ffe9d2")
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.directional_shadow_max_distance = 8.0
	_vp.add_child(key)
	var rand := DirectionalLight3D.new()
	rand.rotation_degrees = Vector3(-18, 200, 0)
	rand.light_energy = 0.9
	rand.light_color = Color("#bcd2ff")
	_vp.add_child(rand)
	var fuell := OmniLight3D.new()
	fuell.position = Vector3(-1.4, 1.2, 1.6)
	fuell.light_energy = 0.45
	fuell.omni_range = 5.0
	fuell.light_color = Color("#ffd6b0")
	_vp.add_child(fuell)
	avatar = Avatar.new()
	avatar.position = Vector3(0, 0.06, 0)
	_vp.add_child(avatar)
	tier = Tier.new()
	_vp.add_child(tier)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.current = true
	_vp.add_child(_cam)
	_figur_bauen()
	_tier_bauen()
	tier.setze(Vector3(0.66, 0, 0.32), -0.6, "sitzen")
	_kamera(1.0)


func _figur_bauen() -> void:
	avatar.bauen(daten.figur)


func _tier_bauen() -> void:
	var p := tier.position
	var y := tier.rotation.y
	tier.bauen(daten.tier)
	tier.position = p
	tier.rotation.y = y


func _process(dt: float) -> void:
	if not is_inside_tree() or _closing or avatar == null:
		return
	var vorn := Nav.top_layer() == self
	var rs := 0.0
	if vorn:
		for id in Input.get_connected_joypads():
			var a := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
			if absf(a) > absf(rs):
				rs = a
	if absf(rs) > 0.18:
		_dreh_soll += rs * dt * 2.4
	_dreh = lerp_angle(_dreh, _dreh_soll, 1.0 - exp(-dt * 8.0))
	avatar.rotation.y = _dreh
	avatar.bild(dt)
	tier.bild(dt)
	_kamera(dt)


func _kamera(dt: float) -> void:
	var soll: Array = FOKUS["tier" if tab == "tier" else "ganz"]
	var k := 1.0 - exp(-dt * 4.5)
	var ziel: Vector3 = soll[0]
	_cam_ziel = _cam_ziel.lerp(ziel, k)
	_cam_abstand = lerpf(_cam_abstand, float(soll[1]), k)
	var dir := Vector3(0.16, 0.16, 1.0).normalized()
	_cam.look_at_from_position(_cam_ziel + dir * _cam_abstand, _cam_ziel, Vector3.UP)
	# Die Tafel liegt rechts: die Figur rückt im Bild nach links.
	_cam.h_offset = _cam_abstand * 0.2


# --- Tafel rechts ------------------------------------------------------------------------------------

func _tafel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UzTheme.lift(UzTheme.box(Color(UzTheme.col("surface"), 0.9), UzTheme.r_panel()), 3))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -BREITE - UzTheme.GUTTER + 24
	panel.offset_right = -UzTheme.GUTTER + 24
	panel.offset_top = 96
	panel.offset_bottom = -112
	add_child(panel)
	var m := U.margin(30, 26, 30, 22)
	panel.add_child(m)
	var col := U.vbox(16)
	m.add_child(col)
	var kopf := U.hbox(14)
	kopf.add_child(U.glyph("lb", 26))
	for t in [["figur", "Deine Figur"], ["tier", "Dein Haustier"]]:
		var r := _Reiter.new()
		r.text = str(t[1])
		r.id = str(t[0])
		kopf.add_child(r)
		_reiter.append(r)
	kopf.add_child(U.glyph("rb", 26))
	col.add_child(kopf)
	_sub = U.label("", "s", "muted", "regular", true)
	col.add_child(_sub)
	_liste = Control.new()
	_liste.clip_contents = true
	_liste.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_liste.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_liste)
	_inhalt = U.vbox(4)
	_inhalt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_liste.add_child(_inhalt)
	_liste.resized.connect(func() -> void: _inhalt.size.x = _liste.size.x)


func _felder() -> Array:
	if tab == "tier":
		return D.TIER_FELDER + [["name", "Name", "n", [], D.TIER_NAME]]
	return D.FIGUR_FELDER


func _werte() -> Dictionary:
	return daten.tier if tab == "tier" else daten.figur


func _feld() -> String:
	var fl := _felder()
	return str(fl[clampi(int(_sel[tab]), 0, fl.size() - 1)][0])


func _zeigen(animiert := true) -> void:
	for r in _reiter:
		(r as _Reiter).setze(r.id == tab)
	_sub.text = tr("Wie du im Zimmer aussiehst – auch Gäste sehen dich so.") if tab == "figur" else tr(
			"Dein Begleiter im Zimmer: folgt dir, schläft und freut sich mit dir.")
	U.clear(_inhalt)
	_zeilen.clear()
	for e in _felder():
		var z := _Zeile.new()
		z.feld = e
		z.editor = self
		z.custom_minimum_size = Vector2(0, ZEILE + (10.0 if str(e[2]) == "p" else 0.0))
		_inhalt.add_child(z)
		_zeilen.append(z)
	_auswahl(animiert)
	_hinweise()


func _auswahl(animiert := true) -> void:
	var s := int(_sel[tab])
	for i in _zeilen.size():
		(_zeilen[i] as _Zeile).setze(i == s, animiert)
	# Liste so schieben, dass die gewählte Zeile gut im Blick ist.
	await get_tree().process_frame
	if not is_inside_tree() or s >= _zeilen.size():
		return
	var z: Control = _zeilen[s]
	var soll := clampf(-(z.position.y - _liste.size.y * 0.38), minf(0.0, _liste.size.y - _inhalt.size.y), 0.0)
	if animiert:
		U.tw(_inhalt, "uz_fliste", Tween.TRANS_QUART).tween_property(_inhalt, "position:y", soll, U.T_MOVE)
	else:
		_inhalt.position.y = soll


func _hinweise() -> void:
	var h: Array = [["lb", "Figur / Haustier"]]
	if _feld() == "name":
		h.append(["a", "Umbenennen"])
	h.append(["x", "Emote" if tab == "figur" else "Freuen"])
	h.append(["y", "Zufall"])
	h.append(["b", "Fertig"])
	set_meta("uz_hints", h)
	var mn := get_tree().current_scene
	if mn and "hint_bar" in mn and is_instance_valid(mn.hint_bar):
		mn.hint_bar.refresh()


# --- Tasten --------------------------------------------------------------------------------------

func nav_dir(cmd: String) -> bool:
	var fl := _felder()
	var s := int(_sel[tab])
	if cmd in ["up", "down"]:
		var n := s + (1 if cmd == "down" else -1)
		if n < 0 or n >= fl.size():
			Sfx.play("bump")
			return true
		_sel[tab] = n
		Sfx.play("move")
		_auswahl()
		_hinweise()
		return true
	aendern(1 if cmd == "right" else -1)
	return true


## Wert der gewählten Zeile weiterschalten (d = ±1).
func aendern(d: int) -> void:
	var e: Array = _felder()[int(_sel[tab])]
	var k := str(e[0])
	if k == "name":
		Sfx.play("bump")
		return
	var liste: Array = e[3]
	var w := _werte()
	var i := 0
	for j in liste.size():
		if str(liste[j][0]) == str(w[k]):
			i = j
	i = (i + d + liste.size()) % liste.size()
	w[k] = str(liste[i][0])
	Sfx.play("move")
	_neu(k)
	(_zeilen[int(_sel[tab])] as _Zeile).puls(d)


## Feld direkt setzen (für Proben und die Zufallsauswahl).
func setze(k: String, wert: String) -> void:
	var w := _werte()
	if w.has(k):
		w[k] = wert
		_neu(k)


func _neu(_k: String) -> void:
	if tab == "figur":
		_figur_bauen()
	else:
		_tier_bauen()
	for z in _zeilen:
		(z as _Zeile).queue_redraw()


func handle(cmd: String) -> bool:
	match cmd:
		"lb", "rb":
			tab = "tier" if tab == "figur" else "figur"
			_emote = -1
			Sfx.play("tab")
			_zeigen()
			return true
		"x":
			if tab == "figur":
				_emote = (_emote + 1) % Avatar.EMOTES.size()
				avatar.emote(str(Avatar.EMOTES[_emote][0]))
				_sub.text = tr(str(Avatar.EMOTES[_emote][1]))
			else:
				tier.freuen()
			Sfx.play("select")
			return true
		"y":
			zufall()
			return true
		"a":
			if _feld() == "name":
				var mn := get_tree().current_scene
				mn.open_keyboard("Name deines Haustiers", str(daten.tier.name), func(t: String) -> void:
					daten.tier.name = D.name_sauber(t)
					_tier_bauen()
					_zeigen(false))
			else:
				aendern(1)
			return true
		"lt", "rt":
			_dreh_soll += PI * 0.25 * (1.0 if cmd == "lt" else -1.0)
			Sfx.play("move")
			return true
	return false


func nav_command(cmd: String) -> bool:
	if cmd == "b":
		Sfx.play("back")
		speichern()
		close()
		return true
	return handle(cmd)


## Zufällige, stimmige Auswahl (nur Freies).
func zufall() -> void:
	var w := _werte()
	for e in (D.TIER_FELDER if tab == "tier" else D.FIGUR_FELDER):
		var k := str(e[0])
		var frei: Array = (e[3] as Array).filter(func(p: Array) -> bool: return M.ist_frei(("tier_" if tab == "tier" else "") + k + ":" + str(p[0]), erreichte))
		w[k] = str(frei[_rng.randi() % frei.size()][0])
	Sfx.play("select")
	_neu("")
	if tab == "figur":
		avatar.emote("jubeln")
	else:
		tier.freuen()


## Speichern: Gesperrtes fällt dabei auf den Standard zurück (erst tragen, wenn es frei ist).
func speichern() -> void:
	_alle["figur"] = M.nur_freies(daten.figur, D.FIGUR_FELDER, erreichte)
	_alle["tier"] = M.nur_freies(daten.tier, D.TIER_FELDER, erreichte, "tier_")
	if zimmer:
		zimmer.speichern()
	else:
		Daten.speichern(_alle)
	fertig.emit()


# --- Zeilen --------------------------------------------------------------------------------------

class _Zeile extends Control:
	var feld: Array = []
	var editor: Node
	var _an := 0.0
	var _puls := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setze(an: bool, animiert: bool) -> void:
		var soll := 1.0 if an else 0.0
		if not animiert:
			_an = soll
			queue_redraw()
			return
		var tw := U.tw(self, "uz_fz")
		tw.tween_method(func(v: float) -> void:
			_an = v
			queue_redraw(), _an, soll, U.T_FOCUS if an else U.T_BASE)

	func puls(d: int) -> void:
		var tw := U.ankommen(self, U.T_ORT, "uz_fp")
		tw.tween_method(func(v: float) -> void:
			_puls = v
			queue_redraw(), float(d) * 14.0, 0.0, U.T_ORT)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UzTheme.draw_selection(self, r.grow(-2), 20, _an, 0.6)
		var k := str(feld[0])
		var titel := tr(str(feld[1]))
		var fs := UzTheme.size("s")
		var fm := UzTheme.size("m")
		var ink := UzTheme.col("text").lerp(UzTheme.col("on_focus"), _an)
		var muted := UzTheme.col("muted").lerp(UzTheme.col("on_focus"), _an * 0.7)
		draw_string(UzTheme.font("medium"), Vector2(22, 30), titel, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
		var w: Dictionary = editor.call("_werte")
		var wert := str(w.get(k, ""))
		var tier: bool = str(editor.get("tab")) == "tier"
		var schluessel := ("tier_" if tier else "") + k + ":" + wert
		var bed := M.bedingung(schluessel, editor.get("erreichte"))
		if str(feld[2]) == "p":
			_farben(w, k, wert, ink)
		else:
			var t := wert if k == "name" else tr(D.name_von(feld[3], wert))
			var f := UzTheme.font("ui_bold")
			var x := 22.0 + _puls
			draw_string(f, Vector2(x, 60), t, HORIZONTAL_ALIGNMENT_LEFT, size.x - 120, fm, ink)
			if k != "name":
				var n := (feld[3] as Array).size()
				var idx := 0
				for j in n:
					if str(feld[3][j][0]) == wert:
						idx = j
				var px := size.x - 22.0 - n * 12.0
				for j in n:
					var c := ink if j == idx else Color(ink, 0.28)
					draw_circle(Vector2(px + j * 12.0 + 4.0, 52), 3.5 if j == idx else 2.6, c)
		if bed != "":
			var lock := Icons.tex("lock", 18)
			var y := 16.0
			var tx := tr("Freischalten: %s") % tr(bed)
			var bf := UzTheme.font("medium")
			var bw := bf.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2).x
			var bx := size.x - 22.0 - bw
			draw_texture_rect(lock, Rect2(bx - 24, y - 2, 18, 18), false, Color(UzTheme.col("accent_ink"), 0.95))
			draw_string(bf, Vector2(bx, y + 13), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, UzTheme.col("accent_ink"))

	func _farben(_w: Dictionary, _k: String, wert: String, ink: Color) -> void:
		var liste: Array = feld[3]
		var n := liste.size()
		var schritt := minf(34.0, (size.x - 44.0) / n)
		var rad := minf(13.0, schritt * 0.4)
		for j in n:
			var c := D.farbe(liste, str(liste[j][0]))
			var mitte := Vector2(22.0 + rad + j * schritt, 60)
			if str(liste[j][0]) == wert:
				draw_circle(mitte, rad + 5.0, Color(ink, 0.9))
				draw_circle(mitte, rad + 3.0, UzTheme.col("surface"))
			draw_circle(mitte, rad, c)
			draw_arc(mitte, rad, 0, TAU, 24, Color(0, 0, 0, 0.25), 1.0, true)
		var name_ := tr(D.name_von(liste, wert))
		var f := UzTheme.font("medium")
		var fs := UzTheme.size("s")
		var tw := f.get_string_size(name_, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(size.x - 22.0 - tw, 30), name_, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, 0.8))


class _Reiter extends Control:
	var text := ""
	var id := ""
	var _an := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setze(an: bool) -> void:
		_an = an
		var f := UzTheme.font("ui_bold")
		custom_minimum_size = Vector2(f.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x + 36, 44)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _an:
			UzTheme.draw_selection(self, r, 22, 1.0, 0.6)
		var f := UzTheme.font("ui_bold")
		var fs := UzTheme.size("m")
		var c := UzTheme.col("on_focus") if _an else UzTheme.col("muted")
		draw_string(f, Vector2(18, (size.y + fs * 0.72) * 0.5), tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
