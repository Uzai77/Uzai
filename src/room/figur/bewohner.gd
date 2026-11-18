extends Node3D
## Wer im Zimmer wohnt (Punkt 131 c, d): deine Figur und dein Haustier, eingebunden in zimmer.gd
## mit wenigen Aufrufen (einrichten, bild, kamera_soll, Emote-Leiste, Streicheln). Hier liegt:
##   – Figur: von oben und über die Schulter sichtbar, läuft, sitzt mit Controller in der Hand.
##     In der Ich-Ansicht ist der Körper für die Kamera ausgeblendet (sein Schatten bleibt), bei Emotes
##     und am Jackenständer (Figur wechseln, vor_figur) tritt die Kamera kurz vor die Figur.
##   – Haustier: Verhalten aus der Lage im Zimmer (folgen, schlafen, vor dem Fernseher liegen).
##   – Meilensteine: neue Freischaltungen gibt es als leise Mitteilung, das Tier freut sich.
##   – Emote-Leiste (RT): unten eine Reihe, Steuerkreuz wählt, A spielt, B schließt.
##   – Kleiderständer (garderobe.gd): die Figur gleich im Zimmer wechseln, ←/→ probiert an, A behält.

const D := preload("res://src/room/figur/figur_daten.gd")
const M := preload("res://src/room/figur/meilensteine.gd")
const Avatar := preload("res://src/room/figur/avatar.gd")
const Tier := preload("res://src/room/figur/tier.gd")
const Leistung := preload("res://src/room/leistung.gd")
const Licht := preload("res://src/room/licht.gd")
const Katalog := preload("res://src/room/katalog.gd")
const U := preload("res://src/ui/u.gd")
const Garderobe := preload("res://src/room/figur/garderobe.gd")
const FT := preload("res://src/room/freundestest.gd")
const Besucher := preload("res://src/room/besucher.gd")
const P := preload("res://src/room/netz_protokoll.gd")
const Zimmer := preload("res://src/room/zimmer.gd")

const NACH_EBENE := 1 << 19        ## Nachbearbeitung der Hauptkamera (nicht in der Reflexionssonde)
## Sitzhöhe (Oberkante Polster) je Sitzmöbel.
const SITZ_HOEHE := { "sofa": 0.47, "sessel": 0.47, "sitzsack": 0.4, "hocker": 0.43, "ohrensessel": 0.46, "schlafsofa": 0.44, "bett": 0.5,
	"buerostuhl": 0.48, "pouf": 0.42 }

## Sitzung: wo das Tier zuletzt war und wie viele Erfolge es gab (Freude beim Wiederkommen).
static var _tier_letzt := {}
static var _erfolge_stand := -1

var zimmer: Zimmer
var daten := {}                  ## das Zimmer (zimmer_daten.gd) mit figur, tier, gemeldet
var erreichte: Array = []
var avatar: Avatar
var tier: Tier
var ruhe := 0.0
var _selfie := 0.0
var _vor_figur := false            ## Jackenständer: Kamera vor die Figur, bis die Figurenwahl zu ist
var _leiste: _Leiste
var _garderobe: Garderobe
var _alt_pos := Vector3.ZERO
var _fleck_figur: MeshInstance3D
var _fleck_tier: MeshInstance3D
var _blase: Label3D                ## Freundestest: dein Schnellsatz über deiner Figur
var _blase_t := 0.0


func einrichten(z: Control) -> void:
	zimmer = z
	name = "bewohner"
	daten = z.daten
	erreichte = M.erreicht(_facts())
	avatar = Avatar.new()
	avatar.name = "figur"
	add_child(avatar)
	tier = Tier.new()
	tier.name = "haustier"
	add_child(tier)
	_fleck_figur = _fleck(0.78)
	_fleck_tier = _fleck(0.5)
	_bauen()
	umziehen(z.welt)
	_tier_ankommen()
	_leiste = _Leiste.new()
	_leiste.bewohner = self
	(z.get("_hud") as Control).add_child(_leiste)
	_garderobe = Garderobe.new()
	_garderobe.bewohner = self
	(z.get("_hud") as Control).add_child(_garderobe)
	var b := get_node_or_null("/root/Badges")
	if b and b.has_signal("changed"):
		b.connect("changed", _freischaltungen_pruefen)
	var u := get_node_or_null("/root/Unlocks")
	if u and u.has_signal("unlocked"):
		u.connect("unlocked", _neuer_erfolg)
		var n := (u.call("history") as Array).size() if u.has_method("history") else 0
		if _erfolge_stand >= 0 and n > _erfolge_stand:
			tier.freuen()
		_erfolge_stand = n
	_freischaltungen_pruefen.call_deferred()


## Weicher Kontaktschatten auf dem Boden (eine Fläche mit Verlauf): erdet Figur und Tier in jeder
## Grafikstufe, auch in „Leicht“ ohne echte Schatten – kostet so gut wie nichts.
func _fleck(groesse: float) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\nuniform float staerke = 0.32;\nvoid fragment() {\n\tfloat d = length(UV * 2.0 - 1.0);\n\tALBEDO = vec3(0.05, 0.035, 0.03);\n\tALPHA = staerke * (1.0 - smoothstep(0.15, 1.0, d)) * (1.0 - smoothstep(0.15, 1.0, d));\n}\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	var pm := PlaneMesh.new()
	pm.size = Vector2(groesse, groesse)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## In eine (neu gebaute) Welt: Raumgröße, Vorlage oder Grafikstufe haben sich geändert.
func umziehen(welt: Node3D) -> void:
	if get_parent():
		get_parent().remove_child(self)
	welt.add_child(self)
	# Die Nachbearbeitung gehört nur zur Hauptkamera: nicht in die Reflexionssonde.
	for c in (welt.get("kamera") as Node).get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).layers = NACH_EBENE
	if tier:
		tier.position = zimmer._frei(tier.position)


func _facts() -> Dictionary:
	var b := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Badges")
	if b and "facts" in b:
		return b.get("facts")
	return {}


func _bauen() -> void:
	avatar.bauen(M.nur_freies(daten.figur, D.FIGUR_FELDER, erreichte))
	tier.bauen(M.nur_freies(daten.tier, D.TIER_FELDER, erreichte, "tier_"))
	# Forward+: Figur und Tier werfen keine echten Schatten – sie bewegen sich immer (Atmen), und jede
	# Bewegung in der Reichweite einer Lampe ließ deren Würfelschatten (sechs Durchgänge) jedes Bild neu
	# rechnen. Geerdet sind beide durch den weichen Kontaktschatten (_fleck), wie in Spielen mit
	# vorberechnetem Licht.
	if Licht.renderer_jetzt() == "forward":
		for n: Node in [avatar, tier]:
			var stapel: Array[Node] = [n]
			while not stapel.is_empty():
				var k: Node = stapel.pop_back()
				stapel.append_array(k.get_children())
				if k is GeometryInstance3D:
					(k as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Nach dem Editor: neu bauen (Lage bleibt).
func neu_laden() -> void:
	daten = zimmer.daten
	var p := tier.position
	var y := tier.rotation.y
	_bauen()
	tier.setze(p, y, "sitzen")
	tier.freuen()


func _tier_ankommen() -> void:
	var z := zimmer
	if not _tier_letzt.is_empty() and str(_tier_letzt.get("raum", "")) == str(z.raum.id):
		tier.setze(_tier_letzt.pos, float(_tier_letzt.yaw), str(_tier_letzt.zustand))
		if tier.zustand in ["folgen", "hin", "freuen", "gestreichelt"]:
			tier.zustand = "sitzen"
		return
	var vorn := Vector3(-sin(z.yaw), 0, -cos(z.yaw))
	var p: Vector3 = z._frei(z.pos + vorn * 1.1 + Vector3(cos(z.yaw), 0, -sin(z.yaw)) * 0.4)
	tier.setze(p, atan2(z.pos.x - p.x, z.pos.z - p.z), "sitzen")


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and tier and zimmer:
		_tier_letzt = { "raum": str(zimmer.raum.get("id", "")), "pos": tier.position, "yaw": tier.rotation.y,
			"zustand": tier.zustand if tier.zustand in ["schlafen", "fernsehen", "sitzen"] else "sitzen" }


# --- Jedes Bild ----------------------------------------------------------------------------------

## Jedes Bild: Figur und Haustier bewegen. Misst die Zeit selbst (leistung.gd: „Figur“, „Haustier“).
func bild(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var z := zimmer
	var modus := str(z.modus)
	var sitz_i := int(z._sitz)
	# Ruhe: so lange bewegst du dich nicht (das Tier schläft irgendwann ein).
	var bewegt: bool = z.pos.distance_to(_alt_pos) > 0.002 or modus in ["bauen", "katalog", "ansehen", "fahrt"]
	_alt_pos = z.pos
	ruhe = 0.0 if bewegt else ruhe + dt
	# Figur: steht dort, wo du stehst – oder sitzt auf dem Möbel.
	if modus == "sitzen" and sitz_i >= 0 and sitz_i < (z.welt.knoten as Array).size():
		var n: Node3D = z.welt.knoten[sitz_i]
		var s: Dictionary = n.get_meta("sitz", {})
		var sp: Vector3 = s.get("pos", Vector3.ZERO)
		avatar.global_transform = Transform3D(n.global_transform.basis.orthonormalized(), n.global_transform * Vector3(sp.x, 0, sp.z - 0.07))
		avatar.sitz = true
		avatar.spielt = true
		avatar.sitz_hoehe = float(SITZ_HOEHE.get(str(z.raum.moebel[sitz_i].t), 0.45))
		avatar.tempo = 0.0
	else:
		avatar.sitz = false
		avatar.spielt = false
		# In der Ich-Ansicht steht der Körper ein Stück hinter den Augen – beim Blick nach unten so weit,
		# wie der untere Bildrand es erlaubt: die Füße bleiben im Bild, die Beine sieht man von vorn
		# oben (wie die „Beine“ in Source-Spielen), nicht senkrecht von oben in den Schnitt.
		var zurueck := Vector3.ZERO
		if str(z.blick) == "ich":
			var rand := absf(float(z.pitch)) + deg_to_rad(float(z.call("sicht_fov")) * 0.5) - PI * 0.5
			var augen := float((z.call("_augen") as Vector3).y) - float(z.get("_hoehe"))
			var weit := clampf(augen * tan(clampf(rand, 0.0, 1.2)) - 0.2, 0.12, 0.35)
			zurueck = Vector3(sin(float(z.yaw)), 0, cos(float(z.yaw))) * weit
		avatar.position = Vector3(z.pos.x, float(z.get("_hoehe")), z.pos.z) + zurueck
		avatar.rotation = Vector3(0, float(z.yaw) + PI, 0)
		avatar.tempo = Vector2(z._vel.x, z._vel.z).length() if modus == "laufen" else 0.0
		avatar.luft = modus == "laufen" and bool(z.call("in_der_luft"))
		avatar.ducken = float(z.call("duck_anteil")) if modus == "laufen" else 0.0
	avatar.blick_an = tier.position.distance_to(avatar.position) < 2.2 and modus == "laufen" and avatar.tempo < 0.1
	avatar.blick_auf = tier.mitte()
	var tf := Time.get_ticks_usec()
	avatar.bild(dt)
	var figur_us := Leistung.abschnitt("Figur", tf) - tf
	# Haustier.
	var lage := { "spieler": avatar.position, "spieler_yaw": float(z.yaw), "ruhe": ruhe,
		"fernsehen": modus in ["sitzen", "fahrt"], "tv": null, "tv_ziel": null, "korb": null, "frei": z._frei }
	var tv: int = z.welt.medienwand()
	if tv >= 0:
		var tn: Node3D = z.welt.knoten[tv]
		lage.tv = z._frei(tn.global_transform * Vector3(0.35, 0, 1.15))
		lage.tv_ziel = tn.global_transform * Vector3(0, 0.6, 0)
	for i in (z.welt.knoten as Array).size():
		var kn: Node3D = z.welt.knoten[i]
		if is_instance_valid(kn) and kn.has_meta("liegeplatz"):
			lage.korb = kn.global_transform * Vector3.ZERO
			break
	tier.verhalten(dt, lage)
	_fleck_figur.visible = not avatar.sitz and avatar.visible
	_fleck_figur.position = Vector3(avatar.position.x, 0.032, avatar.position.z)
	_fleck_tier.position = Vector3(tier.position.x, tier.position.y + 0.03, tier.position.z)
	if lage.korb != null and tier.zustand == "schlafen" and tier.position.distance_to(lage.korb) < 0.15:
		tier.position.y = 0.06
	else:
		tier.position.y = 0.0
	_selfie = move_toward(_selfie, 1.0 if _selfie_soll() else 0.0, dt * 2.5)
	if _blase:
		_blase_t = maxf(0.0, _blase_t - dt)
		_blase.visible = _blase_t > 0.0 and str(z.blick) != "ich"
		_blase.modulate.a = clampf(_blase_t / 0.4, 0.0, 1.0)
		_blase.global_position = avatar.kopf_mitte() + Vector3(0, 0.5, 0)
	_sichtbarkeit()
	Leistung.abschnitt("Haustier", t0 + figur_us)


## In der Ich-Ansicht ist der Körper für die Hauptkamera ausgeblendet (sein Schatten bleibt);
## Beine und Füße bleiben sichtbar (Blick nach unten). Bei einer Kamerafahrt (z. B. durch die Tür an
## deinen Platz) ebenso, sobald die Kamera der Figur nahe kommt – sonst sah man kurz den Kopf von innen.
func _sichtbarkeit() -> void:
	var cam: Camera3D = zimmer.welt.kamera
	var aus: bool = str(zimmer.blick) == "ich" and zimmer.modus in ["laufen", "rad", "sitzen", "ansehen"] and _selfie < 0.35
	if zimmer.modus == "fahrt" and avatar.visible:
		var d := cam.global_position - avatar.kopf_mitte()
		aus = aus or Vector2(d.x, d.z).length() < FAHRT_NAH
	var maske := 0xFFFFF
	if aus:
		maske &= ~(Avatar.EBENE_KOERPER | Avatar.EBENE_HAENDE)
	cam.cull_mask = maske


## So nah (waagerecht, m) darf die Kamera bei einer Fahrt dem Kopf kommen, bevor der Körper ausgeblendet wird.
const FAHRT_NAH := 0.6


func _selfie_soll() -> bool:
	return str(zimmer.blick) == "ich" and zimmer.modus == "laufen" and (avatar.emote_laeuft() != "" or _vor_figur)


## Jackenständer (Figur wechseln): die Kamera tritt vor deine Figur wie bei einem Emote, bis an = false.
func vor_figur(an: bool) -> void:
	_vor_figur = an


## Kamera, wenn die Figur sie bestimmt: [Transform3D, Blickwinkel, Fokus] – sonst [].
func kamera_soll() -> Array:
	var z := zimmer
	var modus := str(z.modus)
	var blick := str(z.blick)
	if modus == "laufen" and _selfie > 0.0 and blick == "ich":
		# Emote (oder Jackenständer) in der Ich-Ansicht: die Kamera tritt kurz vor die Figur. In einer Ecke drückt die
		# Wand die Kamera sonst bis vors Gesicht: dann schräg oder seitlich daneben, wo mehr Platz ist.
		var mitte: Vector3 = Vector3(z.pos.x, 0.95, z.pos.z)
		var o: Vector3 = mitte
		for w in [0.0, 0.6, -0.6, 1.2, -1.2, PI * 0.5, -PI * 0.5]:
			var yaw: float = float(z.yaw) + w
			var vorn := Vector3(-sin(yaw), 0, -cos(yaw))
			var p: Vector3 = _im_raum(mitte + vorn * 2.1 + Vector3(0, 0.35, 0) + Vector3(cos(yaw), 0, -sin(yaw)) * 0.3)
			if p.distance_to(mitte) > o.distance_to(mitte) + 0.05:
				o = p
			if o.distance_to(mitte) >= 1.8:
				break
		return [Transform3D(Basis(), o).looking_at(mitte, Vector3.UP), 50.0, o.distance_to(mitte)]
	if modus in ["laufen", "rad"] and blick == "schulter":
		var b := Basis(Vector3.UP, float(z.yaw)) * Basis(Vector3.RIGHT, float(z.pitch) * 0.8)
		var kopf: Vector3 = Vector3(z.pos.x, 1.5, z.pos.z)
		var o2: Vector3 = _im_raum(kopf + b * Vector3(0.5, 0.32, 2.05))
		return [Transform3D(b, o2), clampf(float(Config.get_value("room.fov", 70)), 55.0, 100.0) - 8.0, 3.0]
	if modus == "sitzen" and blick == "oben":
		return z._oben_kamera(avatar.global_position, 0.3)
	if modus == "sitzen" and blick == "schulter":
		var kopf2: Vector3 = avatar.kopf_mitte()
		var vorn2: Vector3 = avatar.global_transform.basis.z.normalized()
		var re := vorn2.cross(Vector3.UP).normalized()
		var o3: Vector3 = _im_raum(kopf2 - vorn2 * 1.15 - re * 0.38 + Vector3(0, 0.28, 0))
		var ziel: Vector3 = kopf2 + vorn2 * 3.0 - Vector3(0, 0.35, 0)
		return [Transform3D(Basis(), o3).looking_at(ziel, Vector3.UP), 58.0, 3.0]
	return []


## Fotomodus: Figur zeigen oder ausblenden (samt Kontaktschatten).
func figur_zeigen(an: bool) -> void:
	avatar.visible = an
	_fleck_figur.visible = an and not avatar.sitz


func selfie() -> bool:
	return _selfie > 0.0


func _im_raum(p: Vector3) -> Vector3:
	var w := float(zimmer.raum.w) * Katalog.ZELLE
	var d := float(zimmer.raum.d) * Katalog.ZELLE
	return Vector3(clampf(p.x, 0.15, w - 0.15), clampf(p.y, 0.3, 2.5), clampf(p.z, 0.15, d - 0.15))


# --- Haustier -------------------------------------------------------------------------------------

## Schaut der Blick (Ursprung o, Richtung r) auf das Haustier (bis max_d Meter)?
func tier_im_blick(o: Vector3, r: Vector3, max_d: float) -> bool:
	var c := tier.mitte()
	var v := c - o
	var l := v.length()
	if l > max_d:
		return false
	return r.angle_to(v) < atan2(0.3, l) + deg_to_rad(4.0)


func tier_name() -> String:
	return str(tier.name_text)


func streicheln() -> void:
	tier.streicheln()
	ruhe = 0.0
	if str(zimmer.blick) != "ich":
		avatar.emote("streicheln")
	Sfx.play("select")


func _neuer_erfolg(_e = null) -> void:
	_erfolge_stand += 1
	tier.freuen()


# --- Freischaltungen ----------------------------------------------------------------------------------

## Neue Meilensteine: leise melden (einmal je Meilenstein), das Tier freut sich.
func _freischaltungen_pruefen() -> void:
	if not is_inside_tree():
		return
	var neu_erreicht := M.erreicht(_facts())
	var war := erreichte
	erreichte = neu_erreicht
	var neue := M.neu(erreichte, daten.gemeldet)
	if neue.is_empty():
		return
	var text := M.meldung(neue)
	(daten.gemeldet as Array).append_array(neue)
	zimmer.speichern()
	Toasts.show_toast(text[0], text[1], "spark", { "ms": 5200, "title_raw": true, "sub_raw": true })
	tier.freuen()
	if war != erreichte:
		_bauen()


## Für den Katalog: Bedingung, wenn das Möbel noch gesperrt ist, sonst „“.
func gesperrt(moebel_id: String) -> String:
	return M.bedingung("moebel:" + moebel_id, erreichte)


# --- Emote-Leiste -------------------------------------------------------------------------------------

func leiste_offen() -> bool:
	return (_leiste != null and _leiste.offen) or garderobe_offen()


func garderobe_offen() -> bool:
	return _garderobe != null and _garderobe.offen


func leiste_auf() -> void:
	_leiste.oeffnen()


## Jackenständer (A): die Figur gleich hier wechseln (garderobe.gd).
func garderobe_auf() -> void:
	if _leiste.offen:
		_leiste.schliessen()
	_garderobe.oeffnen()


func leiste_taste(cmd: String) -> bool:
	if garderobe_offen():
		return _garderobe.taste(cmd)
	match cmd:
		"a":
			if _leiste.zeile == 0:
				var id: String = str(Avatar.EMOTES[_leiste.sel][0])
				avatar.emote(id)
				if FT.verbunden():
					FT.aktiv.emote_senden(id)
			else:
				_satz(str(P.SAETZE[_leiste.satz_index()][0]))
			Sfx.play("select")
			_leiste.schliessen()
		"b", "rt":
			Sfx.play("back")
			_leiste.schliessen()
		"left", "right":
			_leiste.schritt(-1 if cmd == "left" else 1)
		"up", "down":
			_leiste.zeile_wechseln(-1 if cmd == "up" else 1)
	return true


## Freundestest: ein fester Schnellsatz – über deiner Figur und an die Gegenseite (nur die Nummer).
func _satz(id: String) -> void:
	if _blase == null:
		_blase = Besucher.schild("", 40, true)
		add_child(_blase)
	Besucher.blase_setzen(_blase, id)
	_blase_t = Besucher.BLASE_S
	if FT.verbunden():
		FT.aktiv.satz_senden(id)


func hinweise() -> Array:
	if garderobe_offen():
		return _garderobe.hinweise()
	return [["a", "Sagen" if _leiste.zeile > 0 else "Abspielen"], ["b", "Schließen"]]


class _Leiste extends Control:
	var bewohner: Node
	var offen := false
	var sel := 0
	var zeile := 0                  ## 0 Emotes; beim Freundestest 1 und 2 die Schnellsätze (↑/↓)
	var _reihe: HBoxContainer
	var _panel: PanelContainer
	var _chips: Array = []
	var _zeilen: Array = []         ## je Zeile [HBoxContainer, [Chips]]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 1.0
		anchor_bottom = 1.0
		_panel = PanelContainer.new()
		_panel.add_theme_stylebox_override("panel", UzTheme.lift(UzTheme.box(Color(UzTheme.col("surface"), 0.9), 34), 2))
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
		var m := U.margin(14, 12, 14, 12)
		_panel.add_child(m)
		var spalte := U.vbox(6)
		m.add_child(spalte)
		var halb := P.SAETZE.size() / 2
		for liste in [Avatar.EMOTES, P.SAETZE.slice(0, halb), P.SAETZE.slice(halb)]:
			var r := U.hbox(6)
			r.alignment = BoxContainer.ALIGNMENT_CENTER
			spalte.add_child(r)
			var chips: Array = []
			for e in liste:
				var c := _Chip.new()
				c.text = str(e[1])
				r.add_child(c)
				chips.append(c)
			_zeilen.append([r, chips])
		_reihe = _zeilen[0][0]
		_chips = _zeilen[0][1]
		visible = false
		modulate.a = 0.0

	func oeffnen() -> void:
		offen = true
		visible = true
		var saetze := FT.verbunden()
		for i in range(1, _zeilen.size()):
			(_zeilen[i][0] as Control).visible = saetze
		if not saetze and zeile > 0:
			zeile = 0
			_chips = _zeilen[0][1]
			sel = clampi(sel, 0, _chips.size() - 1)
		_auswahl()
		await get_tree().process_frame
		# Im selben Bild wieder geschlossen (der Jackenständer ging auf): nicht doch noch einblenden.
		if not offen:
			return
		_panel.reset_size()
		_panel.position = Vector2(-_panel.size.x * 0.5, -_panel.size.y - 120)
		var tw := U.tw(self, "uz_emote", Tween.TRANS_QUART)
		tw.set_parallel(true)
		tw.tween_property(self, "modulate:a", 1.0, U.T_BASE)
		tw.tween_property(_panel, "position:y", -_panel.size.y - 132, U.T_MOVE).from(-_panel.size.y - 108)
		Sfx.play("open")
		bewohner.zimmer.call("_hinweise_auffrischen")

	func schliessen() -> void:
		offen = false
		var tw := U.tw(self, "uz_emote", Tween.TRANS_CUBIC, Tween.EASE_IN)
		tw.tween_property(self, "modulate:a", 0.0, U.T_FAST)
		tw.tween_callback(func() -> void: visible = false)
		bewohner.zimmer.call("_hinweise_auffrischen")

	func schritt(d: int) -> void:
		var n := sel + d
		if n < 0 or n >= _chips.size():
			Sfx.play("bump")
			return
		sel = n
		Sfx.play("move")
		_auswahl()

	## ↑/↓: zwischen Emotes und Schnellsätzen (nur beim Freundestest).
	func zeile_wechseln(d: int) -> void:
		var n := zeile + d
		if n < 0 or n >= _zeilen.size() or not (_zeilen[n][0] as Control).visible:
			Sfx.play("bump")
			return
		zeile = n
		_chips = _zeilen[n][1]
		sel = clampi(sel, 0, _chips.size() - 1)
		Sfx.play("move")
		_auswahl()
		bewohner.zimmer.call("_hinweise_auffrischen")

	func satz_index() -> int:
		return sel + (0 if zeile <= 1 else (_zeilen[1][1] as Array).size())

	func _auswahl() -> void:
		for z in _zeilen.size():
			var chips: Array = _zeilen[z][1]
			for i in chips.size():
				(chips[i] as _Chip).setze(z == zeile and i == sel)


class _Chip extends Control:
	var text := ""
	var _an := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setze(an: bool) -> void:
		var f := UzTheme.font("ui_bold")
		custom_minimum_size = Vector2(f.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x + 44, 52)
		var tw := U.tw(self, "uz_chip")
		tw.tween_method(func(v: float) -> void:
			_an = v
			queue_redraw(), _an, 1.0 if an else 0.0, U.T_FOCUS if an else U.T_BASE)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UzTheme.draw_selection(self, r, 26, _an, 0.7)
		var f := UzTheme.font("ui_bold")
		var fs := UzTheme.size("m")
		var c := UzTheme.col("text").lerp(UzTheme.col("on_focus"), _an)
		draw_string(f, Vector2(22, (size.y + fs * 0.72) * 0.5), tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
