extends Node3D
## Wer beim Freundestest außer dir im Zimmer steht (freundestest.gd figuren()): je Gegenseite eine Figur aus
## festen Kennungen (figur/avatar.gd), weich nachgeführt (Lage und Blick gleiten zum zuletzt gemeldeten Stand,
## Schritttempo aus der gezeigten Bewegung), Emotes, Schnellsatz als Sprechblase (Text aus Uzai selbst,
## netz_protokoll.gd SAETZE) und darüber der Name – beim Gastgeber der aus seiner Einladung, beim Gast
## „Gastgeber“. Nichts davon kommt als Text, Bild oder Modell aus dem Netz.
## Die Figuren liegen auf Ebene 1: Die Ich-Ansicht blendet nur den eigenen Körper aus (Avatar.EBENE_KOERPER).

const Avatar := preload("res://src/room/figur/avatar.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const P := preload("res://src/room/netz_protokoll.gd")

const NACHLAUF := 10.0          ## je Sekunde: so schnell gleitet die Lage zum gemeldeten Stand
const SPRUNG_WEIT := 3.0        ## weiter weg: gleich hinsetzen statt gleiten
const BLASE_S := 4.0

var _f := {}                    ## Schlüssel → { a, p, yaw, figur_n, emote_n, satz_n, name, blase, blase_t }


## Jedes Bild: daten = Freundestest.figuren() (oder {}).
func bild(dt: float, daten: Dictionary) -> void:
	for k in _f.keys():
		if not daten.has(k):
			_weg(k)
	for k in daten:
		var d: Dictionary = daten[k]
		var ziel: Vector3 = d.p
		if ziel.x < 0.0:
			continue            # noch keine Lage gemeldet
		if not _f.has(k):
			_f[k] = _neu(d)
		var f: Dictionary = _f[k]
		var a: Avatar = f.a
		if int(d.figur_n) != int(f.figur_n):
			f.figur_n = int(d.figur_n)
			_bauen(a, d.figur)
		var alt: Vector3 = f.p
		var p: Vector3 = alt
		if alt.x < 0.0 or alt.distance_to(ziel) > SPRUNG_WEIT:
			p = ziel
		else:
			p = alt.lerp(ziel, 1.0 - exp(-dt * NACHLAUF))
		f.p = p
		f.yaw = lerp_angle(float(f.yaw), float(d.yaw), 1.0 - exp(-dt * NACHLAUF * 1.2))
		a.position = p
		a.rotation = Vector3(0, float(f.yaw) + PI, 0)
		var v := Vector2(p.x - alt.x, p.z - alt.z).length() / maxf(dt, 0.001) if alt.x >= 0.0 else 0.0
		a.tempo = lerpf(a.tempo, v, 1.0 - exp(-dt * 8.0))
		a.luft = ziel.y > 0.08
		var vorn := Vector3(-sin(float(f.yaw)), 0, -cos(float(f.yaw)))
		a.blick_an = true
		a.blick_auf = p + Vector3(0, 1.55, 0) + (vorn * cos(float(d.pitch)) + Vector3(0, sin(float(d.pitch)), 0)) * 3.0
		if int(d.emote_n) != int(f.emote_n):
			f.emote_n = int(d.emote_n)
			a.emote(str(d.emote))
		if int(d.satz_n) != int(f.satz_n):
			f.satz_n = int(d.satz_n)
			blase_setzen(f.blase, str(d.satz))
			f.blase_t = BLASE_S
		f.blase_t = maxf(0.0, float(f.blase_t) - dt)
		(f.blase as Label3D).visible = float(f.blase_t) > 0.0
		(f.blase as Label3D).modulate.a = clampf(float(f.blase_t) / 0.4, 0.0, 1.0)
		a.bild(dt)
		var kopf := a.kopf_mitte()
		(f.name as Label3D).global_position = kopf + Vector3(0, 0.32, 0)
		(f.blase as Label3D).global_position = kopf + Vector3(0, 0.56, 0)


func anzahl() -> int:
	return _f.size()


func leeren() -> void:
	for k in _f.keys():
		_weg(k)


func _neu(d: Dictionary) -> Dictionary:
	var a := Avatar.new()
	a.name = "besuch"
	add_child(a)
	_bauen(a, d.figur)
	var n := schild(str(d.name), 34, false)
	add_child(n)
	var b := schild("", 40, true)
	b.visible = false
	add_child(b)
	return { "a": a, "p": Vector3(-1, 0, -1), "yaw": float(d.yaw), "figur_n": int(d.figur_n), "emote_n": int(d.emote_n), "satz_n": int(d.satz_n),
			"name": n, "blase": b, "blase_t": 0.0 }


func _bauen(a: Avatar, figur: Variant) -> void:
	a.bauen(FD.pruefe_figur(figur))
	for mi in a.ebenen_alle():
		(mi as MeshInstance3D).layers = 1


func _weg(k: String) -> void:
	var f: Dictionary = _f[k]
	for n in [f.a, f.name, f.blase]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_f.erase(k)


## Ein Schild im Raum (Name oder Sprechblase): zeigt immer zur Kamera, liegt über allem.
static func schild(text: String, groesse: int, blase: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.0022
	l.font_size = groesse
	l.outline_size = 10
	l.font = UzTheme.font("ui_bold")
	l.modulate = Color(UzTheme.col("text")) if not blase else Color.WHITE
	l.outline_modulate = Color(0, 0, 0, 0.55) if not blase else Color(UzTheme.col("accent"), 0.95)
	l.double_sided = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


## Sprechblase mit dem Schnellsatz (Kennung aus der festen Liste, Text übersetzt aus Uzai).
static func blase_setzen(l: Label3D, satz_id: String) -> void:
	l.text = TranslationServer.translate(P.satz_text(satz_id))
