extends Control
## Die Bühne hinter der Einrichtung (setup_wizard.gd): Licht, Staub und die eigenen Spiele. Sie bleibt
## über alle Schritte stehen – was auf ihr liegt, wandert von Schritt zu Schritt mit.
## Staub im Licht (boot.motes), außer im Willkommen.
## "willkommen": wie im Intro (boot.gd) – ein einziger, leiser Lichtverlauf in der Farbe der
##   Lichtlinie geht hinter dem Zeichen auf (T_LICHT; fokus() nennt das Zeichen, das Licht steht genau
##   hinter dem U), kein Staub. "fertig": ein Schein im Akzent wächst auf und atmet.
## "spiele": Der Höhepunkt. Jedes gefundene Spiel fliegt als echtes Cover in die Reihe (Platzhalter
##   der Seite, regal()) – klein und fern aus der Tiefe der Mitte (bzw. dem Ort, den die Seite nennt),
##   einzeln nacheinander –, die sich von der Mitte nach außen füllt (E.regal_platz). Die Reihe hat
##   Tiefe (buehne_platz): zum Rand hin stehen die Cover kleiner, etwas höher und leiser, wie in einem
##   Bogen um die Mitte. Landet ein
##   Cover, geht ein Glanz über sein Bild und unter ihm glimmt kurz Licht auf; dazu steigt der Klang
##   „gefunden“ Stufe um Stufe (Klang.stufe_ton, höchstens alle KLANG_TAKT s). Hinter dem Zähler
##   wächst ein Schein mit der Zahl. Wie viele schon da sind, gibt der Zähler vor (zeigen()). Die
##   Spiele der Startseite kommen zuerst (reihe()); bei "fertig" stehen sie flach in deren Folge von
##   links nach rechts.
## Andere Schritte: Das Regal sinkt und blendet aus; bei "fertig" steigt es wieder auf.
## Ende (aufloesen): Jedes Cover fliegt an sein Gegenstück auf der Startseite, die übrigen gehen –
##   die Bühne wird zur echten Oberfläche. Mit Abflugzeiten (Aufbau der Startseite,
##   startseite_aufbau.gd) fliegen die Cover gleich nach „Los“ gestaffelt los (bis dahin stehen sie
##   still an ihrem Platz im Regal) und geben beim Landen an das echte Cover ab (Signal gelandet:
##   das echte kommt, das eigene kreuzt aus). Cover ohne Gegenstück gehen mit der Seite (T_WEG).
##   feiern(): ein ruhiger Lichtschein, keine Schnipsel.
##   welle(): „Los“ – die Handschrift der Marke zum Schluss: An der Taste zündet ein Kern (hell, dann
##   Akzent), ein Lichtring läuft über den ganzen Schirm, und hinter ihm baut sich die Startseite auf.
## Alle weichen Lichter liegen auf dunklem Grund: Die Bühne zeichnet sie entstuft (U.entstuft – ein
## Hauch blaues Rauschen vor der Ausgabe), sonst stünden im 8-Bit-Bild Ringe.
## Bewegung: kritisch gedämpfte Federn (U.spring_step), ganze Pixel, nichts schwingt nach. Leistung:
## höchstens CAP Cover (TextureRect mit runden Ecken), einige Dutzend Lichtpunkte, kein eigener Puffer;
## im leichten Modus weniger Lichtpunkte und höchstens 30 Bilder je Sekunde. Bei „Animationen
## reduzieren“ fliegt nichts: Cover blenden an ihrem Platz ein, das Licht steht.

signal gelandet(id: String)      ## ein Cover liegt auf seinem Gegenstück (nur mit Abflugzeiten)

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Boot := preload("res://src/ui/boot.gd")
const Logo := preload("res://src/ui/components/uzai_logo.gd")
const Szene := preload("res://src/ui/components/einrichtung_szene.gd")
const E := preload("res://src/core/einrichtung.gd")
const Klang := preload("res://src/core/klang.gd")

const MOTES := 26
const MOTES_LEICHT := 10
const CAP := 15                  ## so viele Cover höchstens auf der Bühne
const FLUG := 11.0               ## Straffheit der Feder: nach gut 0,4 s am Platz
const LANDEN := 13.0             ## beim Auflösen etwas straffer
const FEIER_S := 1.6
const FAHRT_S := 1.8             ## Einstieg: so lange sinkt der Staub („Kamerafahrt“)
const TAKT_COVER := 0.07         ## höchstens ein neues Cover je so viel Sekunden (sie kommen einzeln)
const KLANG_TAKT := 0.2          ## Landen klingt höchstens so oft („gefunden“, Stufe um Stufe höher)
const TIEFE := 0.075             ## je Platz vom Rand der Mitte so viel kleiner (Tiefe der Reihe) …
const TIEFE_MIN := 0.6           ## … höchstens bis hierhin

var mode := ""
var _t := 0.0
var _mode_t := 0.0
var _calm := false
var _wait := 0.0
var _motes: Array = []
var _feier_t := -1.0
var _feier_at := Vector2.ZERO
var _feier_k := 1.0
var _fokus: WeakRef              ## Willkommen: das Zeichen (das Licht steht dahinter)
var _klang_t := -1.0             ## zuletzt „gefunden“ beim Landen
var _klang_n := 0                ## so viele Landungen klangen schon (Stufe)
var _zahl_glanz := 0.0           ## Schein hinter dem Zähler (folgt der Zahl)
var _zaehler: WeakRef            ## Spiele: der Zähler (dahinter der Schein)
var _fahrt := 0.0                ## 1 → 0 beim Einstieg
var _aus := 1.0                  ## Licht und Staub insgesamt (geht beim Auflösen auf 0)
var _hullen: Array = []          ## je Cover: { id, node, pos, vel, dim, dvel, a, shown, ziel }
var _regal: WeakRef
var _quelle: WeakRef
var _zeigen := 0
var _zeigen_ist := 0.0           ## so viele stehen schon (folgt _zeigen, ein Cover je TAKT_COVER)
var _reihe: Array = []           ## Spiel-IDs in der Folge der Startseite (zuerst auf die Bühne)
var _aufl := {}                  ## id → Rect2 (eigene Koordinaten) beim Auflösen
var _aufl_an := false
var _aufl_t := 0.0               ## Sekunden seit aufloesen
var _abflug := {}                ## id → Abflug in Sekunden (leer: alle sofort, ohne Abgabe)
var _gelandet := {}              ## id → Sekunden seit der Landung (das eigene Cover kreuzt aus)
var _geladen := false
var _welle_t := -1.0             ## Sekunden seit welle() (−1: keine)
var _welle_at := Vector2.ZERO
const WELLE_S := 1.15


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_calm = U.reduziert()
	_motes = Boot.motes(MOTES_LEICHT if Leicht.active else MOTES)
	material = U.entstuft()
	resized.connect(queue_redraw)


func set_mode(m: String) -> void:
	if m == mode:
		return
	var erst := mode == ""
	mode = m
	_mode_t = 0.0
	if m == "willkommen" and erst and not _calm:
		_fahrt = 1.0
	if m in ["spiele", "fertig"]:
		spiele_laden()
	queue_redraw()


## Platzhalter der Seite, in dem das Regal steht (seine Lage gilt in jedem Bild – gleitet die Seite,
## gleitet das Regal mit), und der Ort, aus dem neue Cover kommen (der Zähler).
func regal(platz: Control, quelle_: Control = null) -> void:
	_regal = weakref(platz) if platz else null
	_quelle = weakref(quelle_) if quelle_ else null


## Spiele: der Zähler (hinter ihm wächst ein Schein mit der Zahl).
func zaehler(node: Control) -> void:
	_zaehler = weakref(node) if node else null


## Das Element, hinter dem das Licht des Willkommens steht (null: oben in der Mitte).
func fokus(node: Control) -> void:
	_fokus = weakref(node) if node else null


## So viele Cover stehen im Regal (der Zähler gibt es vor).
func zeigen(n: int) -> void:
	_zeigen = clampi(n, 0, CAP)


## Folge der Startseite (Spiel-IDs): Diese Spiele kommen zuerst auf die Bühne – so landet am Ende
## jedes Cover des Regals auf einem Cover der Startseite.
func reihe(ids: Array) -> void:
	_reihe = ids.duplicate()


## Die eigenen Spiele (sichtbar, ohne Doppelte), höchstens CAP – zuerst in der Folge der Startseite;
## neue kommen hinten dazu.
func spiele_laden() -> void:
	if not _geladen:
		_geladen = true
		if not Library.changed.is_connected(spiele_laden):
			Library.changed.connect(spiele_laden)
	var have := {}
	for h in _hullen:
		have[str(h.id)] = true
	var liste: Array = []
	for id0 in _reihe:
		var g1 := Library.get_game(str(id0))
		if not g1.is_empty():
			liste.append(g1)
	liste.append_array(Library.visible_games())
	for g0 in liste:
		if _hullen.size() >= CAP:
			break
		var g: Dictionary = g0
		var id := str(g.get("id", ""))
		if id == "" or have.has(id) or str(g.get("dupe_of", "")) != "":
			continue
		have[id] = true
		_hullen.append(_neu(g))


func _neu(g: Dictionary) -> Dictionary:
	var n := _Huelle.new()
	n.setup(g)
	add_child(n)
	n.modulate.a = 0.0
	return { "id": str(g.get("id", "")), "node": n, "pos": Vector2.ZERO, "vel": Vector2.ZERO, "dim": Vector2.ZERO, "dvel": Vector2.ZERO, "a": 0.0,
		"shown": false, "landed": false, "land_t": -1.0 }


## Die Ziele (id → Rect2), deren Cover wirklich auf der Bühne steht – nur sie können fliegen. Die
## übrigen Cover der Startseite kommen dort von selbst (z. B. neu eingerichtet aus den Einstellungen:
## Die Bühne kannte die Folge der Startseite nicht, dann fliegt nichts, und kein Cover wartet
## vergeblich auf seine Landung).
func fliegbar(ziele: Dictionary) -> Dictionary:
	var out := {}
	for h in _hullen:
		var id := str(h.id)
		if ziele.has(id) and bool(h.shown):
			out[id] = ziele[id]
	return out


## Ende der Einrichtung: Cover mit Gegenstück (id → Rect2 in Schirm-Koordinaten) fliegen dorthin,
## die anderen gehen; Licht und Staub verglimmen. Gibt zurück, wie viele landen.
func aufloesen(ziele: Dictionary, abflug := {}) -> int:
	var inv := get_global_transform().affine_inverse()
	var n := 0
	_aufl.clear()
	_abflug = abflug.duplicate()
	_aufl_t = 0.0
	_gelandet.clear()
	for h in _hullen:
		var id := str(h.id)
		if ziele.has(id) and bool(h.shown):
			var r: Rect2 = ziele[id]
			_aufl[id] = Rect2(inv * r.position, r.size)
			n += 1
	_aufl_an = true
	set_process(true)
	return n


## „Los“: Der Kern zündet bei at (eigene Koordinaten), ein Lichtring läuft über den ganzen Schirm
## (WELLE_S, Kurve „Ankommen“). Bei „Animationen reduzieren“ nicht.
func welle(at: Vector2) -> void:
	if _calm:
		return
	_welle_at = at
	_welle_t = 0.0
	set_process(true)


## Die kleine Feier: ein ruhiger Lichtschein, der von at ausgeht (eigene Koordinaten); staerke 0 … 1.
func feiern(at: Vector2, staerke := 1.0) -> void:
	_feier_at = at
	_feier_k = staerke
	_feier_t = 0.0
	set_process(true)


func _process(dt: float) -> void:
	_t += dt
	_mode_t += dt
	if _fahrt > 0.0:
		_fahrt = maxf(0.0, _fahrt - dt / FAHRT_S)
	if _feier_t >= 0.0:
		_feier_t += dt
		if _feier_t > FEIER_S:
			_feier_t = -1.0
	if _welle_t >= 0.0:
		_welle_t += dt
		if _welle_t > WELLE_S:
			_welle_t = -1.0
	if _aufl_an:
		_aus = maxf(0.0, _aus - dt / U.T_RAUM)
		_aufl_t += dt
	# Neue Cover einzeln: höchstens eins je TAKT_COVER, auch wenn der Zähler schneller ist.
	_zeigen_ist = minf(float(_zeigen), _zeigen_ist + dt / TAKT_COVER) if not _calm else float(_zeigen)
	_hullen_schritt(dt)
	if Leicht.active:
		_wait += dt
		if _wait < 1.0 / 30.0:
			return
		_wait = 0.0
	queue_redraw()


# --- Cover -----------------------------------------------------------------------------------

## Wo das Regal steht (eigene Koordinaten) – leer, solange es keinen Platz gibt.
func _band() -> Rect2:
	var p: Control = _regal.get_ref() as Control if _regal else null
	if p == null or not p.is_inside_tree():
		return Rect2()
	var inv := get_global_transform().affine_inverse()
	var g := p.get_global_rect()
	return Rect2(inv * g.position, g.size)


func _hullen_schritt(dt: float) -> void:
	if _hullen.is_empty():
		return
	var band := _band()
	var regal_an := mode in ["spiele", "fertig"] and band.size.y > 10.0 and not _aufl_an
	var u := size.y / 1080.0
	var cs := UzTheme.cover_size()
	var hh := band.size.y if band.size.y > 10.0 else 200.0 * u
	var ww := roundf(hh * cs.x / maxf(cs.y, 1.0))
	var gap := roundf(22.0 * u)
	var cx := band.get_center().x if band.size.x > 0.0 else size.x * 0.5
	var inner := band.size.x * 0.5 if band.size.x > 0.0 else size.x * 0.4
	var aussen := maxf(size.x * 0.5, inner + 1.0)
	var src := Vector2(cx, band.position.y + hh * 0.5)
	var q: Control = _quelle.get_ref() as Control if _quelle else null
	if q and q.is_inside_tree():
		src = get_global_transform().affine_inverse() * q.get_global_rect().get_center()
	# Bereit: in der Folge der Startseite von links nach rechts (die Flüge am Ende laufen parallel);
	# bei der Suche von der Mitte aus.
	var reihe_n := mini(_hullen.size(), _zeigen)
	var tief := mode != "fertig" and not _calm
	for i in _hullen.size():
		var h: Dictionary = _hullen[i]
		var node: Control = h.node
		if not is_instance_valid(node):
			continue
		var slot: Rect2
		if mode != "fertig":
			var bp := buehne_platz(E.regal_platz(i), ww, hh, gap, TIEFE if tief else 0.0)
			slot = Rect2(Vector2(roundf(cx + bp.x - bp.z * 0.5), roundf(band.position.y + bp.y)), Vector2(roundf(bp.z), roundf(bp.w)))
		else:
			var k := float(i) - float(reihe_n - 1) * 0.5
			slot = Rect2(roundf(cx + k * (ww + gap) - ww * 0.5), roundf(band.position.y), ww, roundf(hh))
		var dist := absf(slot.get_center().x - cx)
		var leise := clampf(1.0 - maxf(0.0, dist + ww * 0.5 - inner) / (aussen - inner) * 0.8, 0.2, 1.0)
		var ziel := slot
		var ziel_a := 0.0
		var omega := FLUG
		var landet := false
		if _aufl_an:
			omega = LANDEN
			if _aufl.has(str(h.id)) and _aufl_t < float(_abflug.get(str(h.id), 0.0)):
				# Wartet die wenigen Bilder bis zu seinem Abflug (gestaffelt, Bruchteile einer Sekunde)
				# genau an seinem Platz im Regal – kein halber Weg, kein Schweben im Raum.
				ziel = Rect2(h.pos, h.dim)
				ziel_a = 1.0
			elif _aufl.has(str(h.id)):
				ziel = _aufl[str(h.id)]
				ziel_a = 1.0
				landet = not _abflug.is_empty()
			else:
				# Ohne Gegenstück auf der Startseite: sinkt ein Stück und geht mit der Seite (T_WEG).
				ziel = Rect2(h.pos + Vector2(0, 30.0 * u), h.dim)
		elif regal_an and i < int(_zeigen_ist):
			ziel_a = leise
			if not bool(h.shown):
				# Neu im Regal: aus der Mitte (oder der Quelle), klein, fern und unsichtbar.
				h.shown = true
				h.landed = false
				var start := Vector2(ww, hh) * (1.0 if _calm else 0.32)
				h.dim = start
				h.pos = slot.position if _calm else src - start * 0.5
				h.vel = Vector2.ZERO
				h.dvel = Vector2.ZERO
		elif bool(h.shown):
			# Anderer Schritt: das Regal sinkt ein Stück und geht.
			ziel = Rect2(slot.position + Vector2(0, 60.0 * u), slot.size)
		if not bool(h.shown):
			continue
		if _calm:
			h.pos = ziel.position
			h.dim = ziel.size
		else:
			var sx := U.spring_step(h.pos.x, h.vel.x, ziel.position.x, dt, omega * 1.08)
			var sy := U.spring_step(h.pos.y, h.vel.y, ziel.position.y, dt, omega)
			var sw := U.spring_step(h.dim.x, h.dvel.x, ziel.size.x, dt, omega)
			var sh := U.spring_step(h.dim.y, h.dvel.y, ziel.size.y, dt, omega)
			h.pos = Vector2(sx.x, sy.x)
			h.vel = Vector2(sx.y, sy.y)
			h.dim = Vector2(sw.x, sh.x)
			h.dvel = Vector2(sw.y, sh.y)
			# Fast da: genau auf den Platz (ganze Pixel, kein spätes Nachrücken).
			if h.pos.distance_to(ziel.position) < 0.5 and h.dim.distance_to(ziel.size) < 0.5:
				h.pos = ziel.position
				h.dim = ziel.size
				h.vel = Vector2.ZERO
				h.dvel = Vector2.ZERO
		var rate := dt / (U.T_ORT if ziel_a > float(h.a) else (U.T_WEG if _aufl_an else U.T_RAUM))
		if _calm:
			rate *= 2.0
		h.a = move_toward(float(h.a), ziel_a, rate)
		node.position = h.pos.round()
		node.size = h.dim.round()
		node.modulate.a = U.kurve("ankommen", float(h.a)) if ziel_a > 0.0 else float(h.a)
		if regal_an and mode == "spiele" and ziel_a > 0.0 and not bool(h.landed) and h.pos.distance_to(ziel.position) < 2.0 and h.dim.distance_to(ziel.size) < 2.0:
			_landen(h, ziel)
		if float(h.land_t) >= 0.0:
			h.land_t = float(h.land_t) + dt
			if float(h.land_t) > U.T_LICHT:
				h.land_t = -1.0
		if landet and _gelandet.has(str(h.id)):
			# Gelandet: Das echte Cover kommt („Ankommen“), das eigene kreuzt aus (U.kreuz_aus).
			var seit := float(_gelandet[str(h.id)]) + dt * U.tempo()
			_gelandet[str(h.id)] = seit
			node.modulate.a *= 1.0 - U.kurve("kreuzen", (seit - U.NACH_WEG) / U.T_WEG)
			node.visible = seit < U.NACH_WEG + U.T_WEG
		elif landet and h.pos == ziel.position and h.dim == ziel.size:
			_gelandet[str(h.id)] = 0.0
			gelandet.emit(str(h.id))


## Ein Cover ist an seinem Platz: Glanz über das Bild, Licht darunter, und – höchstens alle
## KLANG_TAKT s – der Klang „gefunden“, jedes Mal eine Stufe höher. Ruhig (reduziert) ohne Glanz.
func _landen(h: Dictionary, ziel: Rect2) -> void:
	h.landed = true
	if _calm:
		return
	h.land_t = 0.0
	h.land_at = Vector2(ziel.get_center().x, ziel.end.y)
	h.land_w = ziel.size.x
	(h.node as Control).call("glanz")
	if _t - _klang_t >= KLANG_TAKT and is_visible_in_tree():
		_klang_t = _t
		Sfx.play("setup_found", Klang.stufe_ton(mini(_klang_n, 7)))
		_klang_n += 1


## Platz k (0 Mitte, ±1, ±2 … wie E.regal_platz) in einer Reihe mit Tiefe: Mitte des Covers
## (x, von der Mitte der Reihe aus), Versatz nach oben (y), Breite und Höhe (z, w). tiefe: je Platz
## so viel kleiner (0: flach, alle gleich groß) bis TIEFE_MIN; die Abstände wachsen mit den Covern,
## so berühren sie sich nie. Weiter weg steht ein Cover etwas höher (wie auf einem Bogen).
static func buehne_platz(k: int, ww: float, hh: float, gap: float, tiefe: float) -> Vector4:
	var n := absi(k)
	var sc := func(j: int) -> float: return maxf(TIEFE_MIN, 1.0 - tiefe * float(j))
	var x := 0.0
	for j in range(1, n + 1):
		x += (ww * (float(sc.call(j - 1)) + float(sc.call(j)))) * 0.5 + gap * float(sc.call(j))
	var s: float = sc.call(n)
	return Vector4(x * signf(float(k)), (1.0 - s) * hh * 0.32, ww * s, hh * s)


# --- Zeichnen --------------------------------------------------------------------------------

func _glow(c: Vector2, r: float, col: Color) -> void:
	if col.a > 0.003 and r > 1.0:
		draw_texture_rect(Szene.glow_tex(), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


func _draw() -> void:
	var s := size
	if s.x < 10.0:
		return
	var acc := UzTheme.col("accent")
	var fade := Szene.eo(_mode_t / 0.6) if not _calm else 1.0
	var strength := (1.0 if mode in ["willkommen", "fertig"] else 0.5) * _aus
	var u := s.y / 1080.0
	# Einstieg: das Licht geht an (wächst in T_LICHT aus dem Zeichen auf), dann atmet es.
	if mode in ["willkommen", "fertig"]:
		var an := Szene.eo(_mode_t / U.T_LICHT) if not _calm else 1.0
		var br := 0.5 - 0.5 * cos(_t * TAU / 4.0) if not _calm else 0.5
		var c := Vector2(s.x * 0.5, s.y * (0.3 if mode == "willkommen" else 0.42))
		var f: Control = _fokus.get_ref() as Control if _fokus else null
		if f and f.is_inside_tree():
			var fc := f.get_global_rect().get_center()
			if f.has_method("licht_mitte"):
				fc = f.get_global_transform() * (f.call("licht_mitte") as Vector2)
			c = get_global_transform().affine_inverse() * fc
		if mode == "willkommen":
			# Wie im Intro (boot.gd _paint_licht): ein einziger, leiser Lichtverlauf hinter dem Zeichen
			# in der Farbe seiner Lichtlinie – kein Kern, kein Staub.
			_glow(c, s.y * 0.67 * lerpf(0.7, 1.0, an), Color(Logo.licht_von(acc), 0.042 * an * _aus))
		else:
			_glow(c, s.y * lerpf(0.35, 0.8, an) * (1.0 + 0.12 * _fahrt), Color(acc, (0.06 + 0.035 * br) * an * _aus))
			# Ein engerer, hellerer Kern dicht am Zeichen: Das Licht kommt von dort.
			_glow(c, s.y * lerpf(0.08, 0.26, an), Color(acc.lerp(Color.WHITE, 0.25), (0.035 + 0.06 * (1.0 - an)) * an * _aus))
	# Staub im Licht (wie beim Start): steigt langsam, nahe Punkte größer und schneller; beim
	# Einstieg sinkt das Feld ein Stück mit (Kamerafahrt).
	var tint := acc.lerp(Color.WHITE, 0.35)
	var fahrt := Szene.eo(_fahrt) * 70.0 * u
	# Im Willkommen wie im Intro ohne Staub; er kommt erst mit dem nächsten Schritt (fade).
	for m in (_motes if mode != "willkommen" else []):
		var z: float = m[2]
		var ph: float = m[3]
		var p := Vector2(float(m[0]) * s.x, float(m[1]) * s.y)
		if not _calm:
			p.y = fposmod(p.y - _t * 14.0 * u * z, s.y + 40.0) - 20.0
			p.x += sin(_t * 0.5 + ph) * 10.0 * u * z
			p.y -= fahrt * z
		var tw := 0.75 + 0.25 * sin(_t * 1.3 + ph * 2.0)
		_glow(p, lerpf(5.0, 14.0, z) * float(m[4]) * u, Color(tint, tw * lerpf(0.06, 0.22, z) * strength * fade))
	# Unter dem Regal ein leiser Schein (die Cover stehen im Licht), hinter dem Zähler einer, der mit
	# der Zahl wächst.
	if mode in ["spiele", "fertig"] and _zeigen > 0 and not _aufl_an:
		var band := _band()
		if band.size.y > 10.0:
			var k := clampf(float(_zeigen) / 5.0, 0.0, 1.0) * fade
			_glow(Vector2(band.get_center().x, band.end.y), band.size.y * 1.8, Color(acc, 0.07 * k))
		var q: Control = _zaehler.get_ref() as Control if _zaehler else null
		if mode == "spiele" and q and q.is_inside_tree():
			_zahl_glanz = move_toward(_zahl_glanz, clampf(float(_zeigen) / float(CAP), 0.0, 1.0), 0.02)
			var qc := get_global_transform().affine_inverse() * q.get_global_rect().get_center()
			_glow(qc, s.y * lerpf(0.16, 0.3, _zahl_glanz), Color(acc, (0.03 + 0.05 * _zahl_glanz) * fade))
	# Gerade gelandet: unter dem Cover glimmt kurz Licht auf (T_LICHT).
	if mode == "spiele" and not _aufl_an:
		for h in _hullen:
			if float(h.land_t) >= 0.0:
				var lt := float(h.land_t) / U.T_LICHT
				var la := 0.16 * (1.0 - Szene.eo(lt)) * (h.node as Control).modulate.a
				_glow(h.land_at, float(h.land_w) * lerpf(0.7, 1.3, Szene.eo(lt)), Color(acc.lerp(Color.WHITE, 0.3), la))
	if _feier_t >= 0.0:
		var f := _feier_t / FEIER_S
		_glow(_feier_at, 460.0 * u * (0.6 + 0.4 * Szene.eo(f * 2.0)) * lerpf(0.7, 1.0, _feier_k), Color(acc, 0.14 * _feier_k * (1.0 - Szene.eo(f))))
	# „Los“: Der Kern zündet an der Taste, ein Lichtring läuft über den ganzen Schirm.
	if _welle_t >= 0.0:
		var x := _welle_t / WELLE_S
		var hell := acc.lerp(Color.WHITE, 0.45)
		var kern := Szene.win(x, 0.0, 0.07) * (1.0 - Szene.win(x, 0.12, 0.5))
		if kern > 0.0:
			_glow(_welle_at, (70.0 + 160.0 * kern) * u, Color(hell, 0.45 * kern))
			draw_circle(_welle_at, 13.0 * u * (1.0 + 0.3 * kern), Color(hell, kern), true, -1.0, true)
		var weit := s.length() * 0.8
		var rr := lerpf(16.0 * u, weit, Szene.eo(x))
		var aa := 1.0 - Szene.eio(x)
		_glow(_welle_at, rr * 0.95, Color(acc, 0.05 * aa))
		for q in 3:
			draw_arc(_welle_at, maxf(rr - q * 12.0 * u, 1.0), 0.0, TAU, 160, Color(hell, aa * (0.32 - q * 0.09)), maxf((7.0 - q * 2.0) * u, 1.0), true)


## Ein Cover auf der Bühne: das echte Bild mit runden Ecken (wie auf der Startseite) über einem
## weichen Schatten; ohne Bild eine ruhige Fläche in der Farbe des Systems mit dem Titel.
class _Huelle extends Control:
	const UU := preload("res://src/ui/u.gd")
	var game: Dictionary = {}
	var _img: TextureRect
	var _farbe := Color("#2b2d33")
	var _licht: Control              ## über dem Bild: der Glanz beim Landen (U.draw_shine)

	func setup(g: Dictionary) -> void:
		game = g
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sys := Config.system(str(g.get("system", "")))
		if not sys.is_empty():
			_farbe = Color(str(sys.get("color", "#2b2d33"))).darkened(0.35)
		_img = UU.rounded_image(UzTheme.r_cover())
		UU.full_rect(_img)
		_img.visible = false
		add_child(_img)
		_licht = Control.new()
		_licht.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UU.full_rect(_licht)
		_licht.draw.connect(func() -> void: UU.draw_shine(_licht, Rect2(Vector2.ZERO, _licht.size)))
		add_child(_licht)
		resized.connect(queue_redraw)

	## Einmal ein Glanz schräg über das Bild (T_LICHT), wenn das Cover landet.
	func glanz() -> void:
		var tw := UU.ankommen(_licht, UU.T_LICHT, "uz_glanz")
		tw.tween_method(func(v: float) -> void:
			_licht.set_meta("uz_shine", v)
			_licht.queue_redraw()
		, 0.0, 1.0, UU.T_LICHT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func _ready() -> void:
		Media.game_texture(game, "cover", func(t: Texture2D) -> void:
			if t != null and is_instance_valid(_img):
				_img.texture = t
				_img.visible = true
				queue_redraw()
		)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if r.size.x < 4.0:
			return
		var sb := UzTheme.box(_farbe, UzTheme.r_cover())
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = int(maxf(6.0, size.y * 0.08))
		sb.shadow_offset = Vector2(0, maxf(3.0, size.y * 0.035))
		draw_style_box(sb, r)
		if _img.visible:
			return
		var f := UzTheme.font("bold")
		var fs := int(clampf(size.y * 0.075, 11.0, 20.0))
		draw_multiline_string(f, Vector2(size.x * 0.1, size.y * 0.72), str(game.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.8, fs, 3,
				UzTheme.col("text", 0.8))
