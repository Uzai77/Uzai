extends "res://tests/probe_base.gd"
## Probe „Figur“: eine Figur rundherum (vorn, drei Viertel, Seite, hinten), Gesicht nah, alle Figuren
## in zwei Reihen (Frauen, Männer) und ein paar Bewegungen – auf einer eigenen kleinen Bühne.
## Aufruf: UZAI_DATA=… xvfb-run … --uzai-script=res://tests/probe_mensch.gd --uzai-out=<ordner>

const Avatar := preload("res://src/room/figur/avatar.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")
const D := preload("res://src/room/figur/figur_daten.gd")

const MENSCHEN := [{}]


## Eigene kleine Bühne über allem.
func buehne() -> Array:
	var cl := CanvasLayer.new()
	cl.layer = 120
	main.get_tree().root.add_child(cl)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3a332e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f3e3cf")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 28, 0)
	key.light_energy = 1.25
	key.light_color = Color("#ffe9d2")
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	vp.add_child(key)
	var rand := DirectionalLight3D.new()
	rand.rotation_degrees = Vector3(-18, 200, 0)
	rand.light_energy = 0.9
	rand.light_color = Color("#bcd2ff")
	vp.add_child(rand)
	var boden := MeshInstance3D.new()
	boden.mesh = F.walze(9.0, 0.02, 0.01, 64)
	boden.material_override = S.stoff_farbig(Color("#6e5747"), 30.0, 0.6)
	boden.position.y = -0.02
	vp.add_child(boden)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.current = true
	vp.add_child(cam)
	return [cl, vp, cam]


func figuren(vp: SubViewport, liste: Array, abstand := 0.78) -> Array:
	var out: Array = []
	for i in liste.size():
		var av := Avatar.new()
		vp.add_child(av)
		av.bauen(liste[i])
		av.position = Vector3((float(i) - float(liste.size() - 1) * 0.5) * abstand, 0, 0)
		out.append(av)
	return out


func laufen_lassen(avs: Array, sek: float) -> void:
	var t := 0.0
	while t < sek:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		for a: Node3D in avs:
			a.call("bild", minf(dt, 0.05))


func run() -> void:
	main.goto("games")
	await wait(1.0)
	var b := buehne()
	var vp: SubViewport = b[1]
	var cam: Camera3D = b[2]
	var eins := figuren(vp, [MENSCHEN[0]])
	var av: Node3D = eins[0]
	for a in [["m_vorn", 0.0], ["m_dreiviertel", 0.75], ["m_seite", 1.5708], ["m_hinten", 3.4]]:
		av.rotation.y = float(a[1])
		cam.look_at_from_position(Vector3(0, 0.95, 4.6), Vector3(0, 0.9, 0))
		await laufen_lassen(eins, 0.5)
		await shot(str(a[0]), 0.1)
	av.rotation.y = 0.35
	cam.look_at_from_position(Vector3(0.32, 1.6, 0.9), Vector3(0, 1.58, 0.04))
	await laufen_lassen(eins, 0.6)
	await shot("m_gesicht", 0.1)
	av.rotation.y = 0.0
	cam.look_at_from_position(Vector3(0.0, 0.25, 1.3), Vector3(0, 0.08, 0.05))
	await laufen_lassen(eins, 0.3)
	await shot("m_schuhe", 0.1)
	av.emote("jubeln")
	cam.look_at_from_position(Vector3(0.6, 1.1, 3.9), Vector3(0, 0.95, 0))
	await laufen_lassen(eins, 0.75)
	await shot("m_jubeln", 0.05)
	av.emote("")
	av.tempo = 1.4
	await laufen_lassen(eins, 0.62)
	await shot("m_gehen", 0.05)
	av.emote("")
	av.tempo = 0.0
	av.sitz = true
	av.spielt = true
	await laufen_lassen(eins, 1.2)
	await shot("m_sitzen", 0.05)
	av.queue_free()
	# Alle Figuren: Frauen, dann Männer.
	for art in ["w", "m"]:
		var liste: Array = []
		for e in D.PERSONEN:
			if str(e[2]) == art:
				liste.append({ "person": str(e[0]) })
		var reihe := figuren(vp, liste, 0.62)
		cam.fov = 30.0
		cam.look_at_from_position(Vector3(0, 1.0, 2.4 + liste.size() * 0.62), Vector3(0, 0.88, 0))
		await laufen_lassen(reihe, 0.6)
		await shot("m_alle_" + art, 0.1)
		for a: Node3D in reihe:
			a.queue_free()
	(b[0] as Node).queue_free()
	await wait(0.3)
