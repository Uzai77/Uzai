extends "res://src/room/zimmer_basis.gd"
## Dein Zimmer, Schicht über zimmer_basis.gd: Fotomodus und Schnappschuss, Zimmer teilen und
## einführen (Stufe 3).

const Teilen := preload("res://src/room/zimmer_teilen.gd")
const TeilenUi := preload("res://src/room/teilen_ui.gd")
const EinfuehrenUi := preload("res://src/room/einfuehren_ui.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const Logo := preload("res://src/ui/components/uzai_logo.gd")
const Boot := preload("res://src/ui/boot.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

var _blitz: ColorRect           ## Fotomodus: kurzer Blitz beim Auslösen
var _marke: Image               ## dezentes Uzai-Zeichen für Schnappschüsse (einmal gezeichnet)
var _foto_namen: Array = []     ## Dateinamen der Schnappschüsse, die der Hilfsfaden gerade schreibt
var _still := false             ## eigene Ansicht kurz anhalten (Vorschaubild wird gerechnet)


# --- Fotomodus und Schnappschuss (Stufe 3) ---------------------------------------------------------

## Fotomodus: eine eigene Kamera frei im Raum, die Figur mit Pose, A macht den Schnappschuss.
## Solange er offen ist, rechnet die Ansicht in voller Auflösung (auch in „Leicht“ – das Bild
## steht dabei meist still).
func fotomodus() -> void:
	if modus == "anpassen":
		_ui.schliessen(true)
	if not _halten.is_empty():
		_ablegen_abbrechen()
	if modus == "sitzen":
		_aufstehen()
	welt.raster.visible = false
	# Kamera vor die Figur, dorthin, wo am meisten Platz ist und nichts davor steht (die ganze Figur
	# soll ins Bild).
	var figur := Vector3(pos.x, 0.95, pos.z)
	var o := figur
	var best := -INF
	for w: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, PI]:
		var vorn := Vector3(-sin(yaw + w), 0, -cos(yaw + w))
		var p := _foto_im_raum(figur + vorn * 2.9 + Vector3(0, 0.25, 0))
		var frei := Vector2(p.x - figur.x, p.z - figur.z).length() - absf(w) * 0.3
		if _foto_verdeckt(p, figur + Vector3(0, 0.45, 0)) or _foto_verdeckt(p, figur):
			frei -= 5.0
		if frei > best:
			best = frei
			o = p
	var dir := (figur - o).normalized()
	# Die Figur dreht sich zur Kamera (Steuerkreuz ←/→ dreht sie danach weiter).
	yaw = atan2(dir.x, dir.z)
	_yaw_soll = yaw
	_foto = { "pos": o, "yaw": atan2(-dir.x, -dir.z), "pitch": asin(clampf(dir.y, -1.0, 1.0)), "fov": 46.0, "ziel_fov": 46.0,
		"pose": 0, "figur": true, "busy": false }
	modus = "foto"
	_rate = 4.0
	_glimmen_setzen(null)
	_ziel_zeigen()
	_info_weg()
	# Fotomodus: volle Auflösung mit MSAA 4×, ohne Anpassen nach der gemessenen Zeit.
	if leistung:
		leistung.halten = true
	vp.scaling_3d_scale = 1.0
	if not leicht:
		vp.msaa_3d = Viewport.MSAA_4X
	Sfx.play("open")
	_kopf_auffrischen()
	_hinweise_auffrischen()
	_marke_zeichnen()


## Steht ein Möbel zwischen Kamera und Figur? (Teppiche und Flaches am Boden zählen nicht.)
func _foto_verdeckt(von: Vector3, nach: Vector3) -> bool:
	for i in mini(welt.boxen.size(), (raum.moebel as Array).size()):
		var b: AABB = welt.boxen[i]
		if b.size.y < 0.25 or Katalog.ebene(str(raum.moebel[i].t)) in ["teppich", "decke"]:
			continue
		if b.intersects_segment(von, nach):
			return true
	return false


func _foto_im_raum(p: Vector3) -> Vector3:
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	return Vector3(clampf(p.x, 0.2, w - 0.2), clampf(p.y, 0.25, 2.6), clampf(p.z, 0.2, d - 0.2))


## Abzug eines Schultertasters (0 … 1), stärkster Controller.
func _abzug(achse: int) -> float:
	var v := 0.0
	for id in Input.get_connected_joypads():
		v = maxf(v, Input.get_joy_axis(id, achse))
	return clampf((v - 0.08) / 0.92, 0.0, 1.0)


## Tastatur im Fotomodus: nur W/A/S/D und Q/E (das Steuerkreuz dreht die Figur und wählt die Pose).
func _foto_tasten() -> Vector3:
	var v := Vector3.ZERO
	if not get_window().has_focus():
		return v
	if Input.is_physical_key_pressed(KEY_W): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_E): v.z += 1.0
	if Input.is_physical_key_pressed(KEY_Q): v.z -= 1.0
	return v


## Kamera im Fotomodus: linker Stick fährt (in Blickrichtung), rechter Stick schaut, LT/RT senken
## und heben, LB/RB zoomen (weich).
func _foto_bild(dt: float, ls: Vector2, rs: Vector2) -> void:
	var b := Basis(Vector3.UP, float(_foto.yaw))
	var vor := b * Vector3.FORWARD
	var re := b * Vector3.RIGHT
	var t := _foto_tasten()
	var w := ls if ls.length() > Vector2(t.x, t.y).length() else Vector2(t.x, t.y).limit_length(1.0)
	var hoch := _abzug(JOY_AXIS_TRIGGER_RIGHT) - _abzug(JOY_AXIS_TRIGGER_LEFT) + t.z
	_foto.pos = _foto_im_raum(_foto.pos + (re * w.x + vor * -w.y) * 1.2 * dt + Vector3(0, clampf(hoch, -1.0, 1.0) * 0.8 * dt, 0))
	_foto.yaw = float(_foto.yaw) - rs.x * dt * 1.7
	_foto.pitch = clampf(float(_foto.pitch) - rs.y * dt * 1.2, -1.3, 1.2)
	_foto.fov = lerpf(float(_foto.fov), float(_foto.ziel_fov), 1.0 - exp(-dt * 9.0))


func _foto_taste(cmd: String) -> bool:
	match cmd:
		"a":
			_foto_ausloesen()
		"b":
			Sfx.play("back")
			_foto_aus()
		"y":
			_foto_pose(1)
		"x":
			_foto.figur = not bool(_foto.figur)
			bewohner.figur_zeigen(bool(_foto.figur))
			Sfx.play("toggle_on" if _foto.figur else "toggle_off")
			_hinweise_auffrischen()
		"lb", "rb":
			var z := clampf(float(_foto.ziel_fov) + (6.0 if cmd == "lb" else -6.0), 22.0, 80.0)
			Sfx.play("move" if z != float(_foto.ziel_fov) else "bump")
			_foto.ziel_fov = z
		"guide":
			return false
	return true


## Steuerkreuz: ←/→ dreht die Figur, ↑/↓ wechselt die Pose.
func _foto_schritt(cmd: String) -> void:
	match cmd:
		"left", "right":
			yaw += PI / 8.0 * (1.0 if cmd == "left" else -1.0)
			_yaw_soll = yaw
			Sfx.play("move")
		"up", "down":
			_foto_pose(-1 if cmd == "up" else 1)


func _foto_pose(d: int) -> void:
	var i := posmod(int(_foto.get("pose", 0)) + d, FOTO_POSEN.size())
	_foto.pose = i
	var p: Array = FOTO_POSEN[i]
	bewohner.avatar.foto_halten(str(p[0]), float(p[2]))
	Sfx.play("move")
	_kopf_auffrischen()
	_hinweise_auffrischen()


func _foto_aus() -> void:
	if modus != "foto":
		return
	bewohner.avatar.foto_ende()
	bewohner.figur_zeigen(true)
	_foto = {}
	modus = "laufen"
	_rate = 3.0
	if leistung:
		leistung.halten = false
	_stufe_waehlen()
	_ziel = -2
	_ziel_suchen()
	_kopf_auffrischen()
	_hinweise_auffrischen()


## Schnappschuss: genau das Bild der Ansicht (ohne Leisten), unten rechts dezent „uzai“, als PNG
## unter Bilder\Uzai – nur hier wird ein Bild gespeichert, und nur, weil du es auslöst.
func _foto_ausloesen() -> void:
	if bool(_foto.get("busy", false)):
		return
	_foto.busy = true
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or modus != "foto":
		return
	var img := vp.get_texture().get_image()
	Sfx.play("shutter")
	_blitz.color.a = 0.7
	U.tw(_blitz, "uz_blitz").tween_property(_blitz, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _marke == null:
		await _marke_zeichnen()
	# Wasserzeichen und PNG rechnet der Hilfsfaden – im Hauptfaden stand das Zimmer dafür (1080p: 0,8 s,
	# 4K: über 3 s, mitten im Blitz). Der nächste Schnappschuss geht sofort; sein Name weicht dem laufenden aus.
	var ziel := Teilen.foto_ziel([], _foto_namen)
	var marke := _marke
	if ziel != "":
		_foto_namen.append(ziel.get_file())
	if modus == "foto":
		_foto.busy = false
	var schreiben := func() -> String:
		Teilen.wasserzeichen(img, marke)
		return Teilen.foto_schreiben(img, ziel)
	var r: Variant = await Arbeit.ergebnis(schreiben, Arbeit.LANG)
	_foto_namen.erase(ziel.get_file())
	var pfad := str(r) if r is String else ""
	if pfad == "":
		Toasts.show_toast("Schnappschuss ging nicht", "Bild nicht gespeichert. Speicherplatz prüfen.", "warning")
		return
	var cap := get_node_or_null("/root/Capture")
	if cap and cap.has_signal("changed"):
		cap.emit_signal("changed", "files")
	Toasts.show_toast("Schnappschuss gespeichert", pfad.get_file(), "camera", { "image": pfad, "quiet": true, "force": true, "sub_raw": true })


## Das Uzai-Zeichen für Schnappschüsse einmal zeichnen (Schrift von Uzai, durchsichtiger Grund).
func _marke_zeichnen() -> void:
	if _marke != null:
		return
	var sv := SubViewport.new()
	sv.size = Vector2i(220, 76)
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Das U-Band und daneben flach die Wortmarke wie im Intro (boot.gd), mit leisem Schatten.
	var m := Control.new()
	m.position = Vector2(10, 12)
	m.size = Vector2(200, 52)
	m.draw.connect(func() -> void:
		Logo.zeichne_zeile(m, Vector2.ZERO, 44.0, UzTheme.col("accent"), Boot.WORT_FARBE, Boot.WORT_SPUR, Color(0, 0, 0, 0.35)))
	sv.add_child(m)
	add_child(sv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(sv):
		var img := sv.get_texture().get_image()
		if _marke == null:
			_marke = img
		sv.queue_free()


# --- Zimmer teilen (Stufe 3) -----------------------------------------------------------------------

## Teilen: der Auszug (ohne Spiele, Namen und Spielstand) und ein Vorschaubild aus schöner Sicht,
## dann die Seite mit Datei und QR-Code (teilen_ui.gd).
func teilen() -> void:
	var aus := Teilen.auszug(daten, raum)
	if aus.is_empty():
		Sfx.play("error")
		_melden(tr("Dieses Zimmer lässt sich nicht teilen"))
		return
	Sfx.play("select")
	var img := await vorschau_bild()
	if not is_inside_tree() or _closing:
		return
	var l := TeilenUi.new()
	l.zimmer = self
	l.auszug = aus
	l.vorschau = img
	main.open_layer(l)


## Sicht für Vorschaubilder: aus der vorderen rechten Ecke über den Raum (Fernseher und Fenster
## im Bild). [Transform3D, Blickwinkel].
func _schau_kamera() -> Array:
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	var o := Vector3(w - 0.35, 2.15, d - 0.3)
	var ziel := Vector3(w * 0.4, 0.7, d * 0.36)
	return [Transform3D(Basis(), o).looking_at(ziel, Vector3.UP), 64.0]


## Vorschaubild über eine zweite Kamera in derselben Welt – die eigene Ansicht bleibt, wie sie ist
## (sie steht die drei Bilder lang still, in denen die Regale für die Vorschau leer sind).
func vorschau_bild(groesse := Teilen.VORSCHAU_GROESSE) -> Image:
	var v2 := SubViewport.new()
	v2.size = groesse
	v2.world_3d = welt.get_world_3d()
	v2.msaa_3d = Viewport.MSAA_DISABLED if leicht else Viewport.MSAA_4X
	v2.positional_shadow_atlas_size = 0
	v2.audio_listener_enable_3d = false
	v2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	var sk := _schau_kamera()
	cam.fov = float(sk[1])
	cam.near = 0.03
	cam.far = 60.0
	v2.add_child(cam)
	add_child(v2)
	cam.global_transform = sk[0]
	cam.current = true
	welt.fokus(4.0, 10.0, 0.0)
	welt.schnitt(cam.global_position, false)
	# Das Bild reist mit der Datei: ohne Spiele, Pokale, Platten und ohne Spielbild im Fernseher.
	welt.privat(true)
	_still = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var w := welt
	for _i in 3:
		await RenderingServer.frame_post_draw
	var img: Image = v2.get_texture().get_image() if is_instance_valid(v2) else null
	if is_instance_valid(w):
		w.privat(false)
	_still = false
	if is_instance_valid(v2):
		v2.queue_free()
	return img


## Zimmer-Datei wählen (Dokumente › Uzai › Zimmer oder woanders), prüfen und mit Vorschau zeigen.
func einfuehren_datei() -> void:
	var ex := Teilen.export_ordner()
	var start := str(ex[1]) if DirAccess.dir_exists_absolute(str(ex[1])) else ""
	main.open_file_browser("Zimmer-Datei wählen", false, func(pfad: String) -> void:
		einfuehren_zeigen(Teilen.lesen_datei(pfad))
	, [Teilen.ENDUNG], start)


## Zimmer-Code aus der Zwischenablage (Text aus dem QR-Code eines anderen Uzai).
func einfuehren_code() -> void:
	var t := DisplayServer.clipboard_get().left(Teilen.QR_MAX * 3)
	if not t.strip_edges().begins_with(Teilen.CODE_PREFIX):
		Toasts.show_toast("Kein Zimmer-Code in der Zwischenablage", "Text aus dem QR-Code kopieren (beginnt mit „UZZ1:“).", "info")
		return
	einfuehren_zeigen(Teilen.code_lesen(t))


func einfuehren_zeigen(gelesen: Dictionary) -> void:
	var l := EinfuehrenUi.new()
	l.zimmer = self
	l.gelesen = gelesen
	main.open_layer(l)


## „Dein Zimmer ersetzen“: Einrichtung des geteilten Zimmers (vorbereitet in zimmer_teilen.gd),
## eigene Möbel kommen dazu, auf Wunsch Figur und Haustier (der Name deines Haustiers bleibt).
## Rückgängig (X) holt alles zurück.
func zimmer_ersetzen(vorb: Dictionary, figur := {}, tier := {}) -> void:
	var neu: Dictionary = vorb.get("raum", {})
	if neu.is_empty():
		return
	_merken(true)
	daten.eigene = (vorb.eigene as Array).duplicate(true)
	Katalog.eigene_setzen(daten.eigene)
	for k in raum.keys():
		if not neu.has(k) and not (k in ["id", "name"]):
			raum.erase(k)
	for k in neu.keys():
		if not (k in ["id", "name"]):
			raum[k] = neu[k].duplicate(true) if (neu[k] is Dictionary or neu[k] is Array) else neu[k]
	if not figur.is_empty():
		daten.figur = FD.pruefe_figur(figur)
		var t := FD.pruefe_tier(tier)
		t.name = str((daten.get("tier", {}) as Dictionary).get("name", FD.TIER_NAME))
		daten.tier = t
		bewohner.neu_laden()
	_welt_neu()
	_melden(tr("Zimmer übernommen – Rückgängig mit X"))
	_geaendert()
	if modus == "anpassen":
		_ui.auffrischen()


## „Als Vorlage speichern“: das geteilte Zimmer unter „Vorlagen“ aufheben (eigene Möbel kommen dazu).
func vorlage_speichern(vorb: Dictionary, name_: String) -> void:
	var liste: Array = daten.get("vorlagen", [])
	if liste.size() >= Daten.MAX_VORLAGEN:
		Sfx.play("error")
		_melden(tr("Höchstens %d eigene Vorlagen") % Daten.MAX_VORLAGEN)
		return
	_merken(true)
	daten.eigene = (vorb.eigene as Array).duplicate(true)
	Katalog.eigene_setzen(daten.eigene)
	var v := Teilen.vorlage(vorb.get("raum", {}), name_, liste)
	if v.is_empty():
		Sfx.play("error")
		return
	daten["vorlagen"] = liste + [v]
	Sfx.play("toggle_on")
	_melden(tr("Vorlage „%s“ gespeichert") % str(v.name))
	_geaendert()
	if modus == "anpassen":
		_ui.auffrischen()


func vorlage_loeschen(id: String) -> void:
	_merken(true)
	daten["vorlagen"] = (daten.get("vorlagen", []) as Array).filter(func(v: Dictionary) -> bool: return str(v.id) != id)
	_ui.zurueck()
	_ui.auffrischen()
	_melden(tr("Vorlage gelöscht"))
	_geaendert()
