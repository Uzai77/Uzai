extends "res://src/room/zimmer_umbau.gd"
## Dein Zimmer, Schicht über zimmer_umbau.gd: das Spieleregal einfach und selbsterklärend.
##
## - Beim Laufen: der Blick wählt eine Hülle (sie rückt ein Stück heraus, das Schild nennt sie),
##   A nimmt sie heraus – das Regal von nahem, die Hülle dreht sich und zeigt ihr Cover. A halten
##   verschiebt das ganze Regal (wie jedes Möbel), nie aus Versehen eine Hülle.
## - Vor dem Regal: das Steuerkreuz wandert über die Rücken (die gewählte zieht sich heraus, Titel
##   und System groß im Bild). A nimmt sie heraus und zeigt das Cover, A noch einmal spielt (bzw.
##   installiert), Y öffnet die Spielseite, B legt sie zurück. Ohne Hülle in der Hand öffnet Y das
##   Menü des Regals: Umstellen (ausdrücklich, dann wie bisher von Hand), Spiele einräumen, Regal
##   einrichten. B geht zurück ins Zimmer.
## - Von nahem sind die Hüllen dieselben wie im Regal des Hauptmenüs (regal_welt.gd Huelle: Logos,
##   Felder, Titel, Seriennummer); aus der Ferne zeichnet das MultiMesh dieselbe Form und Aufmachung
##   (inhalt.gd). Die echten Hüllen entstehen nur, solange du vor dem Regal stehst, ein paar je Bild
##   (kein Ruck), und gehen mit dir wieder.

const DETAIL_JE_BILD := 6           ## so viele echte Hüllen entstehen je Bild
const RAUS_VOR := 0.15              ## so weit vor das Fach kommt die herausgenommene Hülle (m)

var _raus := {}                     ## herausgenommen: { id, huelle, platz, start, ziel }
var _detail := {}                   ## Spiel-ID → { huelle, platz, basis } (Regal von nahem)
var _detail_m := -1
var _detail_warte: Array = []
var _dtakt: Node


class _DTakt extends Node:
	var z: Node

	func _process(_dt: float) -> void:
		z.call("_detail_bild")


# --- Beim Laufen ---------------------------------------------------------------------------------------

## Das Spieleregal vor dir (mit Spielen), sonst -1.
func _regal_ziel() -> int:
	if modus != "laufen" or _ziel < 0 or _ziel_tier or _ziel_fenster or _ziel >= (raum.moebel as Array).size():
		return -1
	if str(raum.moebel[_ziel].t) != "spieleregal" or (welt.plaetze.get(_ziel, []) as Array).is_empty():
		return -1
	return _ziel


func _ziel_handlung() -> String:
	if _regal_ziel() >= 0:
		return "Herausnehmen" if str(_bp.get("art", "")) == "spiel" else "Regal ansehen"
	return super._ziel_handlung()


func _tippen_a() -> void:
	if _regal_ziel() >= 0:
		_regal_oeffnen(_regal_ziel(), str((_bp.get("daten", {}) as Dictionary).get("id", "")) if str(_bp.get("art", "")) == "spiel" else "")
		return
	super._tippen_a()


func _umbau_taste(cmd: String) -> bool:
	if _a_druck.is_empty() and not _lauf_tragen:
		if modus == "laufen" and cmd == "a" and _regal_ziel() >= 0 and not _halten_moeglich():
			_tippen_a()
			return true
		if _regal_offen():
			var r: Variant = _regal_taste(cmd)
			if r is bool:
				return r
	return super._umbau_taste(cmd)


func _aktionen_laufen() -> void:
	var i := _regal_ziel()
	if i < 0:
		super._aktionen_laufen()
		return
	_kontext_auf(_moebel_name("spieleregal"), [
		{ "text": "Regal ansehen", "tun": func() -> void: _regal_oeffnen(i, "") },
		{ "text": "Spiele einräumen", "tun": func() -> void: regal_einraeumen(i) },
		{ "text": "Regal einrichten", "tun": func() -> void: _anpassen_auf(_seiten.seite_regal(i), i) },
		{ "text": "Verschieben", "tun": func() -> void: _tragen_start(i) },
	], _moebel_punkt(i))


## Vor das Regal treten; mit gid gleich diese Hülle herausnehmen.
func _regal_oeffnen(m: int, gid: String) -> void:
	_bp_loslassen()
	Sfx.play("select")
	_ansehen(m)
	if gid == "":
		return
	for k in _ans_plaetze.size():
		if str((_ans_plaetze[k] as Dictionary).daten.get("id", "")) == gid:
			_ans_sel = k
	_platz_zeigen()
	_raus_an()


# --- Vor dem Regal --------------------------------------------------------------------------------------

func _regal_offen() -> bool:
	return modus == "ansehen" and _hand.is_empty() and _ans >= 0 and _ans < (raum.moebel as Array).size() \
			and str(raum.moebel[_ans].t) == "spieleregal"


## Tasten vor dem Spieleregal (null: wie bisher, zimmer_ansehen.gd).
func _regal_taste(cmd: String) -> Variant:
	var p := _platz()
	match cmd:
		"a":
			if p.is_empty() or str(p.get("art", "")) != "spiel":
				Sfx.play("bump")
			elif _raus.is_empty():
				_raus_an()
			else:
				_raus_weg()
				Sfx.play("select")
				_einlegen(p)
			return true
		"b":
			if not _raus.is_empty():
				Sfx.play("back")
				_raus_aus()
				return true
			return null
		"y":
			if not _raus.is_empty():
				Sfx.play("open")
				main.open_game(p.daten)
			else:
				_regal_menue()
			return true
		"lb", "rb":
			Sfx.play("bump")
			return true
	return null


## Y vor dem Regal: was man mit ihm machen kann – ausdrücklich, nichts davon aus Versehen.
func _regal_menue() -> void:
	var m := _ans
	var p := _platz()
	var e: Array = []
	if str(p.get("art", "")) == "spiel":
		e.append({ "text": "Umstellen", "tun": func() -> void: _hand_start(m, p) })
	e.append({ "text": "Spiele einräumen", "tun": func() -> void: _regal_weiter(m, "einraeumen") })
	e.append({ "text": "Regal einrichten", "tun": func() -> void: _regal_weiter(m, "einrichten") })
	_kontext_auf(_moebel_name("spieleregal"), e, _platz_lage(p)[0] if not p.is_empty() else _moebel_punkt(m))


## Vom Regal weiter: einräumen (Raster der Bibliothek) bzw. einrichten (Tafel).
func _regal_weiter(m: int, was: String) -> void:
	_ansehen_ende()
	if was == "einraeumen":
		regal_einraeumen(m)
	else:
		_anpassen_auf(_seiten.seite_regal(m), m)


func _umbau_dir(cmd: String) -> bool:
	if _regal_offen() and not _raus.is_empty():
		_raus_aus()
	return super._umbau_dir(cmd)


func _umbau_hinweise() -> Array:
	if _regal_offen() and not (_kontext and _kontext.offen()):
		var p := _platz()
		if not _raus.is_empty():
			return [["a", "Spielen" if Library.is_installed(p.daten) else "Installieren"], ["y", "Spielseite"], ["b", "Zurücklegen"]]
		if p.is_empty():
			return [["y", "Regal"], ["b", "Zurück"]]
		return [["a", "Herausnehmen"], ["y", "Umstellen · Einräumen"], ["b", "Zurück"]]
	return super._umbau_hinweise()


func _ansehen(i: int) -> void:
	_raus_weg()
	_detail_weg()
	super._ansehen(i)
	if str(raum.moebel[i].t) == "spieleregal":
		_detail_start(i)


func _ansehen_ende() -> void:
	_raus_weg()
	_detail_weg()
	super._ansehen_ende()


func _einlegen(p: Dictionary) -> void:
	_raus_weg()
	_detail_weg()
	super._einlegen(p)


func _kamera_soll() -> Array:
	if modus == "ansehen" and not _raus.is_empty() and _ans >= 0 and _ans < welt.knoten.size():
		var regal: Node3D = welt.knoten[_ans]
		var h: Node3D = _raus.huelle
		var z: Transform3D = _raus.ziel
		var c := regal.global_transform * (z.origin + Vector3(0, float(h.get("masse").y) * 0.5, 0))
		var vor := regal.global_transform.basis.z.normalized()
		var o := c + vor * 0.6 + Vector3(0, 0.05, 0)
		return [Transform3D(Basis(), o).looking_at(c, Vector3.UP), 46.0, o.distance_to(c)]
	return super._kamera_soll()


# --- Herausnehmen: die Hülle dreht sich und zeigt ihr Cover -----------------------------------------

func _raus_an() -> void:
	var p := _platz()
	if p.is_empty() or str(p.get("art", "")) != "spiel" or _ans < 0:
		Sfx.play("bump")
		return
	_raus_weg()
	var m := _ans
	var g: Dictionary = p.daten
	var regal: Node3D = welt.knoten[m]
	var h := Inhalt.huelle_neu(g, welt.huellen)
	regal.add_child(h)
	var hm: Vector3 = h.get("masse")
	var start := _platz_basis(p, hm)
	if p.has("knoten"):
		start = (p.knoten as Node3D).transform * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	h.transform = start
	# Vor das Fach, das Cover zum Raum, ein wenig zur Kamera gedreht.
	var f := _fach_von(m, int(p.get("fach", 0)))
	var vorn := float(f.pos.z) + float(f.tiefe) * 0.5 if not f.is_empty() else start.origin.z
	var ziel := Transform3D(Basis(Vector3.UP, -PI * 0.5 + 0.12) * Basis(Vector3.RIGHT, 0.05), Vector3(start.origin.x, float(p.y) + 0.035, vorn + RAUS_VOR))
	var tw := U.im_tempo(h.create_tween())
	tw.tween_property(h, "transform", ziel, U.T_MOVE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_raus = { "id": str(g.get("id", "")), "huelle": h, "platz": p, "start": start, "ziel": ziel }
	_platz_verstecken(p, true)
	Inhalt.huellen_cover(self, g, h)
	Sfx.play("select")
	_rate = 3.6
	_raus_info()
	_hinweise_auffrischen()


func _raus_info() -> void:
	var g: Dictionary = (_raus.platz as Dictionary).daten
	var teile: Array = [tr("Installiert") if Library.is_installed(g) else tr("Nicht installiert")]
	var zeit := Library.playtime(g)
	teile.append(U.playtime(zeit) if zeit > 0 else tr("Noch nicht gespielt"))
	_info_zeigen(Inhalt.system_name(g), Library.display_title(g), " · ".join(teile))


## Zurück ins Fach (gleitet), dann ist der Platz wieder da.
func _raus_aus() -> void:
	if _raus.is_empty():
		return
	var r := _raus
	_raus = {}
	var h: Node3D = r.huelle
	var p: Dictionary = r.platz
	if is_instance_valid(h):
		var tw := U.im_tempo(h.create_tween())
		tw.tween_property(h, "transform", r.start, U.T_FAST).set_trans(Tween.TRANS_CUBIC)
		tw.tween_callback(func() -> void:
			if is_instance_valid(h):
				h.queue_free()
			if _platz_gilt(int(_ans), p):
				_platz_verstecken(p, false))
	_rate = 3.2
	_platz_zeigen()
	_hinweise_auffrischen()


## Sofort weg (Regal zu, neu gefüllt, Spiel startet).
func _raus_weg() -> void:
	if _raus.is_empty():
		return
	var h: Node3D = _raus.huelle
	var p: Dictionary = _raus.platz
	_raus = {}
	if is_instance_valid(h):
		h.queue_free()
	_platz_verstecken(p, false)


func _fach_von(m: int, fi: int) -> Dictionary:
	var faecher: Array = (welt.knoten[m] as Node3D).get_meta("faecher", [])
	if fi == -1:
		return Inhalt.oben_fach(faecher)
	return faecher[fi] if fi >= 0 and fi < faecher.size() else {}


## Lage einer Hülle aus dem MultiMesh als Hülle des Hauptmenüs (Ursprung unten in der Mitte).
static func _platz_basis(p: Dictionary, hm: Vector3) -> Transform3D:
	var t: Transform3D = p.get("basis", Transform3D())
	return Transform3D(t.basis, t.origin - t.basis * Vector3(0, hm.y * 0.5, 0))


# --- Von nahem: die echten Hüllen des Hauptmenüs ------------------------------------------------------

func _detail_start(m: int) -> void:
	_detail_m = m
	var sel := _platz()
	var sx := float(sel.get("x", 0.0))
	var sy := float(sel.get("y", 0.0))
	_detail_warte = (welt.plaetze.get(m, []) as Array).filter(func(q: Dictionary) -> bool:
		return q.has("mm") and Inhalt.wie_system(q.daten, welt.huellen))
	# Von der gewählten aus nach außen: was du ansiehst, ist zuerst echt.
	_detail_warte.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.x) - sx) + absf(float(a.y) - sy) * 2.0 < absf(float(b.x) - sx) + absf(float(b.y) - sy) * 2.0)
	if _dtakt == null:
		_dtakt = _DTakt.new()
		_dtakt.z = self
		add_child(_dtakt)
	_dtakt.set_process(not _detail_warte.is_empty())


func _detail_bild() -> void:
	if modus != "ansehen" or _ans != _detail_m or _detail_warte.is_empty():
		_dtakt.set_process(false)
		return
	var regal: Node3D = welt.knoten[_detail_m]
	for _k in DETAIL_JE_BILD:
		if _detail_warte.is_empty():
			break
		var p: Dictionary = _detail_warte.pop_front()
		var id := str(p.daten.get("id", ""))
		if not _platz_gilt(_detail_m, p) or (not _hand.is_empty() and id == str(_hand.id)) or id == str(_raus.get("id", "")):
			continue
		var h := Inhalt.huelle_neu(p.daten, welt.huellen)
		regal.add_child(h)
		var basis := _platz_basis(p, h.get("masse"))
		h.transform = basis
		_detail[id] = { "huelle": h, "platz": p, "basis": basis }
		_mm_zeigen(p, false)
	_dtakt.set_process(not _detail_warte.is_empty())


func _detail_weg() -> void:
	for id in _detail.keys():
		var e: Dictionary = _detail[id]
		if is_instance_valid(e.huelle):
			(e.huelle as Node).queue_free()
		_mm_zeigen(e.platz, true)
	_detail.clear()
	_detail_warte.clear()
	_detail_m = -1


## Hülle im MultiMesh (samt Titel) zeigen bzw. verstecken (dort steht dann die echte).
func _mm_zeigen(p: Dictionary, an: bool) -> void:
	if not p.has("mm"):
		return
	var t: Transform3D = p.basis
	(p.mm as MultiMesh).set_instance_transform(int(p.index), t if an else t.scaled_local(Vector3(0.001, 0.001, 0.001)))
	if p.has("schild") and is_instance_valid(p.schild):
		(p.schild as Node3D).visible = an


## Verstecken (Hand, herausgenommen): auch die echte Hülle von nahem.
func _platz_verstecken(p: Dictionary, weg: bool) -> void:
	var id := str((p.get("daten", {}) as Dictionary).get("id", ""))
	if _detail.has(id):
		var h: Node3D = _detail[id].huelle
		if is_instance_valid(h):
			h.visible = not weg
		return
	super._platz_verstecken(p, weg)


## Herausziehen beim Wählen: die echte Hülle von nahem gleitet wie die im MultiMesh.
func _platz_auszug(p: Dictionary, v: float) -> void:
	var id := str((p.get("daten", {}) as Dictionary).get("id", "")) if str(p.get("art", "")) == "spiel" else ""
	if id != "" and id == str(_raus.get("id", "")):
		return
	if id != "" and _detail.has(id):
		var e: Dictionary = _detail[id]
		if is_instance_valid(e.huelle) and (_hand.is_empty() or id != str(_hand.id)):
			var b: Transform3D = e.basis
			(e.huelle as Node3D).transform = Transform3D(b.basis, b.origin + Vector3(0, 0.006 * v, 0.06 * v))
		return
	super._platz_auszug(p, v)
