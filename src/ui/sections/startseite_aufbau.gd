extends Node
## Die Startseite baut sich vor den Augen auf (games.gd aufbauen, nach „Los“ am Ende der
## Einrichtung) – ein Konsolen-Moment von knapp drei Sekunden, ruhig und klar gestaffelt. Die erste
## Stufe kreuzt mit dem Gehen der Einrichtung (Licht und Raum der Einrichtung gehen in T_LICHT), alles
## Weitere kommt erst, wenn deren Raum fast weg ist – vorher lief es darunter ab, und am Ende stand
## scheinbar alles zugleich da:
##   1. Licht und Raum (Hintergrund) blenden auf, das große Spielbild folgt,
##   2. die Leiste oben gleitet herein (Marke, Reiter, Symbole gestaffelt),
##   3. der Kopf (Schild, Titel, Zeile) steigt Glied um Glied hoch,
##   4. die Quellen erscheinen der Reihe nach, mit ihrer Linie,
##   5. die Cover kommen eins nach dem anderen an ihren Platz (COVER_ABSTAND, bis COVER_GLIEDER) –
##      die Cover der Einrichtung sind schon vorher da: Sie fliegen gleich nach „Los“ gestaffelt an
##      ihre Plätze (AB_FLUG) und übergeben beim Landen an die echten (gelandet()), nie zwei Bilder
##      übereinander, nie ein Cover, das wartend im Raum hängt –, die Spiegelung kommt zuletzt,
##   6. die Tastenzeile, mit ihr der Fokus (bereit).
## Alles läuft auf einer Zeitachse (_t, im Tempo von U.tempo()); jedes Glied kennt Beginn, Dauer
## und wie es seinen Stand setzt. Wege in ganzen Pixeln (U.px_schluss), Kurve „Ankommen“.
## Eine Eingabe (Taste, Knopf, Stick, Klick) beendet den Aufbau sofort: Alles steht, der Fokus
## kommt, und die Eingabe läuft weiter zur Steuerung – nichts wird verschluckt.
## „Animationen reduzieren“: nur ein kurzes Einblenden, ohne Wege und Flüge. Der leichte Modus
## behält die Folge (nur Deckkraft und Lage, kostet nichts), im Tempo des leichten Modus.
## Geladen wird hier nichts: Startseite und Bilder stehen längst (unter der Einrichtung gebaut);
## solange der Aufbau läuft, lädt Media nur dringende Bilder hoch (hold_uploads).

signal bereit     ## Fokus darf kommen (die Einrichtung schließt jetzt)
signal fertig     ## alles steht

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")

## Zeitplan in Sekunden ab „Los“ (vor U.tempo()).
const AB_BILD := 0.35
const AB_LEISTE := 0.6
const AB_KOPF := 0.95
const AB_LINIE := 1.3
const AB_QUELLEN := 1.35
const AB_COVER := 1.75
const AB_SPIEGEL := 2.5
const AB_TASTEN := 2.85
## Kopf: so weit liegen Schild, Titel und Zeile auseinander (s).
const KOPF_ABSTAND := 0.08
## Cover: eins nach dem anderen, so weit auseinander (s), bis zum COVER_GLIEDER-ten (danach zugleich).
const COVER_ABSTAND := 0.08
const COVER_GLIEDER := 10
## Covers from the setup start flying right after „Los“, one after another (FLUG_ABSTAND), and land on
## their real slots while the bar, header and sources build up around them. Waiting until shortly before
## AB_COVER would leave them floating in mid-air for over a second.
const AB_FLUG := 0.12
const FLUG_ABSTAND := 0.04
## Gestaffelt wird doppelt so weit wie in Listen: ein Moment, kein Wechsel. Quellen der Reihe nach
## (bis zu QUELLEN_GLIEDER), sonst höchstens U.STAFFEL_MAX Glieder.
const STAFFEL_K := 2.0
const QUELLEN_GLIEDER := 8

var kurz := false                ## reduziert oder leicht: nur kurz einblenden
var von_einrichtung := true
var _main: Node
var _section: Control
var _glieder: Array = []         ## { ab, dauer, setzen: Callable(k) }
var _t := 0.0
var _t_bereit := AB_TASTEN
var _t_ende := 0.0
var _laeuft := false
var _bereit_raus := false
var _start_bild := 0
var _eltern: Array = []          ## [Container, Callable]: nach dem Ordnen die Wege wieder anbringen
var _regal: Control
var _flug := {}                  ## Spiel-ID → [Karte, Abflug in s] (Cover aus der Einrichtung)


## Teile der Startseite (games.gd): "kopf" [Controls], "linie" (Zeile der Quellen), "quellen"
## [Controls], "quellen_leiste" (zeichnet den Strich), "anzahl", "regal" (cover_row.gd), "inhalt"
## [Controls, ohne Regal: einfach blenden].
## fluege: Spiel-IDs, deren Cover die Einrichtung herüberfliegt (gelandet() zeigt die echten).
func start(main_: Node, section: Control, teile: Dictionary, fluege: Array = []) -> void:
	_main = main_
	_section = section
	kurz = U.reduziert()
	_start_bild = Engine.get_process_frames()
	var bg: Variant = _main.get("background")
	if bg is Control and is_instance_valid(bg) and (bg as Control).has_method("aufbau"):
		var stand := [0.0, 0.0]
		var b := bg as Control
		_glied(0.0, U.T_LICHT, func(k: float) -> void:
			stand[0] = k
			if is_instance_valid(b):
				b.call("aufbau", stand[0], stand[1]))
		_glied(AB_BILD, U.T_LICHT, func(k: float) -> void:
			stand[1] = k
			if is_instance_valid(b):
				b.call("aufbau", stand[0], stand[1]))
	# 2. Die Leiste: ganz in einem Zug sichtbar, ihre Teile gleiten gestaffelt von oben herein
	# (ihre eigene Deckkraft gehört der Ruhe der Kopfleiste, kopf_ruhe.gd).
	var bar: Variant = _main.get("top_bar")
	if bar is Control and (bar as Control).is_visible_in_tree():
		_blende(bar as Control, AB_LEISTE, U.T_RAUM + _staffel(2))
		var i := 0
		for n in ["brand_mark", "tabs_box", "kopf_status"]:
			var c: Variant = _main.get(n)
			if c is Control and (c as Control).is_visible_in_tree():
				_gleiten(c as Control, AB_LEISTE + _staffel(i), U.T_RAUM, Vector2(0, -U.W_ORT))
				i += 1
	# 3. Kopf: Schild, Titel, Zeile steigen gestaffelt hoch.
	var i3 := 0
	for c in teile.get("kopf", []):
		if c is Control and is_instance_valid(c):
			_blende(c, AB_KOPF + _staffel(i3, 4, KOPF_ABSTAND / U.STAFFEL), U.T_RAUM)
			_gleiten(c, AB_KOPF + _staffel(i3, 4, KOPF_ABSTAND / U.STAFFEL), U.T_RAUM, Vector2(0, U.W_ORT))
			i3 += 1
	# 4. Die Quellen: erst die Linie, dann ein Name nach dem anderen.
	var linie: Variant = teile.get("linie")
	if linie is CanvasItem and is_instance_valid(linie):
		_blende(linie, AB_LINIE, U.T_ORT, "self_modulate:a")
	# Der Strich unter der gewählten Quelle (zeichnet die Leiste selbst) kommt mit der Linie.
	var leiste: Variant = teile.get("quellen_leiste")
	if leiste is CanvasItem and is_instance_valid(leiste):
		_blende(leiste, AB_LINIE, U.T_ORT, "self_modulate:a")
	var qs: Array = (teile.get("quellen", []) as Array).filter(func(c: Variant) -> bool:
		return c is Control and is_instance_valid(c) and (c as Control).visible)
	for j in qs.size():
		var ab := AB_QUELLEN + _staffel(j, QUELLEN_GLIEDER, 1.0)
		_blende(qs[j], ab, U.T_RAUM)
		_gleiten(qs[j], ab, U.T_RAUM, Vector2(0, U.W_ORT * 0.5))
	var anzahl: Variant = teile.get("anzahl")
	if anzahl is Control and is_instance_valid(anzahl):
		_blende(anzahl, AB_QUELLEN + _staffel(maxi(qs.size() - 1, 0), QUELLEN_GLIEDER, 1.0), U.T_RAUM)
	# 5. Regal.
	var regal: Variant = teile.get("regal")
	if regal is Control and is_instance_valid(regal) and (regal as Control).has_method("einblenden"):
		_regal_aufbauen(regal as Control, fluege)
	for c in teile.get("inhalt", []):
		if c is Control and is_instance_valid(c):
			_blende(c, AB_KOPF, U.T_RAUM)
	# 6. Tastenzeile.
	var hud: Variant = _main.get("hint_hud")
	if hud is Control and is_instance_valid(hud):
		_blende(hud as Control, AB_TASTEN, U.T_ORT)
	if kurz:
		# Nur kurz einblenden: alles zugleich, ohne Wege (die Glieder setzen ihre Wege dann nicht).
		for g in _glieder:
			g.ab = 0.0
			g.dauer = U.T_RAUM
		_t_bereit = U.T_RAUM
	_t_ende = _t_bereit
	for g in _glieder:
		_t_ende = maxf(_t_ende, float(g.ab) + float(g.dauer))
	for id in _flug:
		_t_ende = maxf(_t_ende, float(_flug[id][1]))
	# Fokus erst am Ende: liegt er auf der Startseite (keine Ebene darüber), geht er solange weg.
	var f := Nav.focused()
	var shell: Variant = _main.get("shell")
	if f and shell is Control and (shell as Control).is_ancestor_of(f):
		f.release_focus()
	Media.hold_uploads(_t_ende / maxf(U.tempo(), 0.01) + 0.1)
	_laeuft = true
	_anwenden()


## Läuft der Aufbau noch (sonst kommen bereit und fertig nicht mehr)?
func laeuft() -> bool:
	return _laeuft


## Wann (Sekunden ab jetzt, echte Zeit) das Cover zu Spiel id die Einrichtung verlassen soll.
func flug_ab(id: String) -> float:
	if not _flug.has(id):
		return 0.0
	return maxf(0.0, float(_flug[id][1]) - _t) / maxf(U.tempo(), 0.01)


## Das Cover aus der Einrichtung liegt auf seinem Platz: Das echte kommt dort in T_ORT, während das
## der Bühne auskreuzt (gleiches Bild an gleicher Stelle). sofort: gleich ganz da.
func gelandet(id: String, sofort := false) -> void:
	if not _flug.has(id):
		return
	var card: Variant = _flug[id][0]
	_flug.erase(id)
	if not (is_instance_valid(_regal) and card is Control and is_instance_valid(card)):
		return
	var c := card as Control
	var regal := _regal
	if sofort or not _laeuft:
		regal.call("einblenden", c, 1.0)
		return
	_glied(_t, U.T_ORT, func(k: float) -> void:
		if is_instance_valid(c) and is_instance_valid(regal):
			regal.call("einblenden", c, k))
	_t_ende = maxf(_t_ende, _t + U.T_ORT)


## Sofort ans Ende: alles steht, der Fokus kommt.
func ende() -> void:
	if not _laeuft:
		return
	_t = maxf(_t, _t_ende)
	_abschluss()


## Für Proben und Tests: an eine Stelle der Zeitachse springen (ohne zu enden).
func seek(t: float) -> void:
	_t = t
	_anwenden()


func _process(dt: float) -> void:
	if not _laeuft:
		return
	_t += dt * U.tempo()
	_anwenden()
	if not _bereit_raus and _t >= _t_bereit:
		_bereit_senden()
	if _t >= _t_ende:
		_abschluss()


func _input(e: InputEvent) -> void:
	if not _laeuft or Engine.get_process_frames() <= _start_bild:
		return
	var druck := false
	if e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton or e is InputEventScreenTouch:
		druck = e.is_pressed() and not e.is_echo()
	elif e is InputEventJoypadMotion:
		druck = absf((e as InputEventJoypadMotion).axis_value) > 0.5
	# Nicht als erledigt markieren: Die Eingabe geht danach wie immer an die Steuerung.
	if druck:
		ende()


func _exit_tree() -> void:
	if _laeuft:
		_laeuft = false
		if not _bereit_raus:
			_bereit_raus = true
			bereit.emit()
		fertig.emit()


# --- Glieder -------------------------------------------------------------------------------

func _glied(ab: float, dauer: float, setzen: Callable) -> void:
	_glieder.append({ "ab": ab, "dauer": dauer, "setzen": setzen })


## Verzögerung des i-ten Glieds einer Staffel (glieder: wie viele höchstens, k: Abstand in STAFFEL).
func _staffel(i: int, glieder := U.STAFFEL_MAX, k := STAFFEL_K) -> float:
	if U.reduziert():
		return 0.0
	return mini(maxi(i, 0), glieder - 1) * U.STAFFEL * k


## Deckkraft von 0 bis zu ihrem jetzigen Wert (prop: "modulate:a" oder "self_modulate:a").
func _blende(n: CanvasItem, ab: float, dauer: float, prop := "modulate:a") -> void:
	var ruhe := float(n.get_indexed(prop))
	_glied(ab, dauer, func(k: float) -> void:
		if is_instance_valid(n):
			n.set_indexed(prop, ruhe * k))


## Weg von weg (Pixel neben der Ruhelage) bis an den Platz, in ganzen Pixeln ohne Nachrücken.
func _gleiten(c: Control, ab: float, dauer: float, weg: Vector2) -> void:
	var p := c.get_parent()
	if p is Container and not _eltern.any(func(e: Array) -> bool: return e[0] == p):
		var cb := _nach_ordnen.bind(p)
		(p as Container).sort_children.connect(cb)
		_eltern.append([p, cb])
	var key := "uz_aufbau_px"
	var laenge := weg.length()
	var richtung := weg / maxf(laenge, 0.001)
	_glied(ab, dauer, func(k: float) -> void:
		if not is_instance_valid(c) or kurz:
			return
		var v := 0.0
		if k <= 0.0:
			v = roundf(laenge)
			c.set_meta(key, v)
		elif k < 1.0:
			v = U.px_schluss(c, key, laenge * (1.0 - k))
		_versetzen(c, richtung * v))


## c um off neben seine Ruhelage. Ordnet ein Container neu, gilt seine neue Lage als Ruhelage.
func _versetzen(c: Control, off: Vector2) -> void:
	var st: Dictionary = c.get_meta("uz_aufbau_lage", {})
	if st.is_empty():
		st = { "ruhe": c.position, "zuletzt": c.position }
	elif c.position != st.zuletzt:
		st.ruhe = c.position
	var neu: Vector2 = st.ruhe + off
	c.position = neu
	st.zuletzt = neu
	st.off = off
	if off == Vector2.ZERO:
		c.remove_meta("uz_aufbau_lage")
		c.remove_meta("uz_aufbau_px")
	else:
		c.set_meta("uz_aufbau_lage", st)


func _nach_ordnen(p: Container) -> void:
	if not is_instance_valid(p):
		return
	for ch in p.get_children():
		if ch is Control and ch.has_meta("uz_aufbau_lage"):
			var st: Dictionary = ch.get_meta("uz_aufbau_lage")
			_versetzen(ch as Control, st.get("off", Vector2.ZERO))


## Die sichtbaren Elemente des Regals gestaffelt; Cover aus der Einrichtung warten auf gelandet().
## Die Spiegelung jedes Covers kommt zuletzt.
func _regal_aufbauen(regal: Control, fluege: Array) -> void:
	_regal = regal
	var breite := regal.size.x
	var i := 0
	for it in regal.call("items"):
		var c := it as Control
		if c == null or c.position.x >= breite or c.position.x + c.size.x <= 0.0:
			continue
		var ab := AB_COVER + _staffel(i, COVER_GLIEDER, COVER_ABSTAND / U.STAFFEL)
		var gm: Variant = c.get("game")
		var gid := str((gm as Dictionary).get("id", "")) if gm is Dictionary else ""
		if not kurz and gid != "" and fluege.has(gid):
			_flug[gid] = [c, AB_FLUG + _flug.size() * FLUG_ABSTAND]
			regal.call("einblenden", c, 0.0)
		else:
			_glied(ab, U.T_RAUM, func(k: float) -> void:
				if is_instance_valid(c) and is_instance_valid(regal):
					regal.call("einblenden", c, k, 0.0 if kurz else roundf(U.W_ORT * (1.0 - k))))
		if "spiegel" in c:
			_glied(AB_SPIEGEL + _staffel(i, COVER_GLIEDER, COVER_ABSTAND / U.STAFFEL) * 0.5, U.T_RAUM, func(k: float) -> void:
				if is_instance_valid(c):
					c.set("spiegel", k))
		i += 1


func _anwenden() -> void:
	for g in _glieder:
		var x := clampf((_t - float(g.ab)) / maxf(float(g.dauer), 0.001), 0.0, 1.0)
		var k := U.kurve("raum" if float(g.dauer) >= U.T_RAUM - 0.001 else "ankommen", x)
		(g.setzen as Callable).call(k)


func _bereit_senden() -> void:
	_bereit_raus = true
	# Was noch fliegt, steht jetzt (die Einrichtung blendet ihre Bühne aus).
	for id in _flug.keys():
		gelandet(str(id), true)
	bereit.emit()
	if Nav.top_layer() == null and is_instance_valid(_section) and _section.is_visible_in_tree() and _section.has_method("focus_default"):
		var f := Nav.focused()
		if f == null or not f.is_visible_in_tree():
			_section.call("focus_default")


func _abschluss() -> void:
	if not _laeuft:
		return
	_t = maxf(_t, _t_ende)
	for g in _glieder:
		(g.setzen as Callable).call(1.0)
	if not _bereit_raus:
		_bereit_senden()
	_laeuft = false
	for e in _eltern:
		var p: Variant = e[0]
		if is_instance_valid(p):
			if (p as Container).sort_children.is_connected(e[1]):
				(p as Container).sort_children.disconnect(e[1])
			(p as Container).queue_sort()
	_eltern.clear()
	fertig.emit()
	queue_free()
