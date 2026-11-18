extends RefCounted
## Laufen im Zimmer wie in Source/Half-Life 2 (gamemovement): Bodenreibung mit stopspeed,
## Beschleunigung zur Wunschgeschwindigkeit, kaum Steuern in der Luft, Schwerkraft, Sprung,
## Ducken, Stufen hinauf und an Wänden entlang gleiten. Kein Glätten: was der Stick bzw. die
## Tasten wollen, setzt die Beschleunigung in wenigen Hundertstelsekunden um, beim Loslassen bremst
## die Reibung in Zehntelsekunden.
##
## Der Körper ist wie in Source ein Quader (Hülle), die Welt sind Quader (Wände, Boden, Möbel) –
## gestoßen wird mit einem echten Sweep (trace), der Rest der Bewegung gleitet an der getroffenen
## Fläche entlang (TryPlayerMove), Stufen bis STUFE geht man einfach hinauf (StepMove).
## Rein rechnend, ohne Szene und ohne Physik-Server – tests/logic_bewegung.gd prüft die Formeln.
##
## Werte: aus HL2 umgerechnet. Höhen, Schwerkraft und Sprung mit 1 u ≈ 1,9 cm (wie die Karten);
## die Tempi im Zimmer-Maßstab mit 1 u ≈ 1,25 cm (das Zimmer ist klein, HL2-Tempo in echten
## Metern wäre hier ein Sprint durch die Wand).

const U := 0.019                     ## 1 u in m (Höhen, Schwerkraft, Sprung)
const ZU := 0.0125                   ## 1 u in m für Tempi im Zimmer
const GEHEN := 190.0 * ZU            ## 2,38 m/s – HL2 normal (cl_forwardspeed 190)
const RENNEN := 320.0 * ZU           ## 4,0 m/s – HL2 Sprint (hl2_sprintspeed 320)
const LANGSAM := 150.0 * ZU          ## 1,88 m/s – HL2 gehen (hl2_walkspeed 150), halber Stick
const DUCK_TEMPO := 1.0 / 3.0        ## geduckt ein Drittel (HL2 0,33333)
const REIBUNG := 4.0                 ## sv_friction
const STOPP := 100.0 * ZU            ## sv_stopspeed: darunter bremst die Reibung mit fester Rate
const BESCHL := 10.0                 ## sv_accelerate
const LUFT_BESCHL := 10.0            ## sv_airaccelerate
const LUFT_MAX := 30.0 * ZU          ## Wunschtempo in der Luft höchstens 30 u/s (kaum Steuern)
const SCHWERE := 600.0 * U           ## sv_gravity: 11,4 m/s²
const SPRUNG_HOEHE := 21.0 * U       ## GAMEMOVEMENT_JUMP_HEIGHT: 0,4 m
const SPRUNG := 3.0182               ## sqrt(2 · SCHWERE · SPRUNG_HOEHE) m/s
const STUFE := 18.0 * U              ## sv_stepsize: 0,34 m
const NICHT_SPRUNG := 140.0 * U      ## schneller nach oben: nicht mehr am Boden
const BODEN_N := 0.7                 ## Fläche mit Normale.y ab hier ist Boden
const BREITE := 0.24                 ## halbe Breite der Hülle (Wände und Möbel)
const HOCH := 1.78                   ## Höhe der Hülle stehend
const HOCH_DUCK := 1.12              ## geduckt
const DUCK_ZEIT := 0.2               ## so lange senkt sich der Blick beim Ducken
const EPS := 0.001                   ## Abstand, den die Hülle von Flächen hält

## Zustand eines Körpers: pos (Füße, Mitte), vel, boden, duck, duck_t (0…1, Blickhöhe), sprung_alt.
static func neu(pos: Vector3) -> Dictionary:
	return { "pos": pos, "vel": Vector3.ZERO, "boden": true, "duck": false, "duck_t": 0.0, "sprung_alt": false }


## Reibung am Boden (Source Friction): unter STOPP bremst sie wie bei STOPP – so steht man
## schnell, statt langsam auszurollen.
static func reibung(vel: Vector3, dt: float) -> Vector3:
	var tempo := vel.length()
	if tempo < 0.001:
		return Vector3(0, vel.y, 0) if vel.y != 0.0 else Vector3.ZERO
	var drop := maxf(tempo, STOPP) * REIBUNG * dt
	return vel * (maxf(tempo - drop, 0.0) / tempo)


## Beschleunigen zur Wunschrichtung (Source Accelerate): nur der Anteil, der in dieser Richtung
## noch fehlt, und höchstens beschl · dt · wunsch_tempo.
static func beschleunigen(vel: Vector3, richtung: Vector3, wunsch_tempo: float, beschl: float, dt: float) -> Vector3:
	var jetzt := vel.dot(richtung)
	var fehlt := wunsch_tempo - jetzt
	if fehlt <= 0.0:
		return vel
	return vel + richtung * minf(beschl * dt * wunsch_tempo, fehlt)


## In der Luft (Source AirAccelerate): Wunschtempo auf LUFT_MAX begrenzt, die Rate wie am Boden.
static func luft_beschleunigen(vel: Vector3, richtung: Vector3, wunsch_tempo: float, dt: float) -> Vector3:
	var jetzt := vel.dot(richtung)
	var fehlt := minf(wunsch_tempo, LUFT_MAX) - jetzt
	if fehlt <= 0.0:
		return vel
	return vel + richtung * minf(LUFT_BESCHL * wunsch_tempo * dt, fehlt)


## Ein Takt. wunsch: gewünschte Bewegung in der Welt (Richtung · Ausschlag 0…1, waagrecht),
## tempo: Höchsttempo (GEHEN oder RENNEN), springen/ducken: Tasten jetzt, welt: Array[AABB].
static func schritt(k: Dictionary, wunsch: Vector3, tempo: float, springen: bool, ducken: bool, alle: Array, dt: float) -> void:
	# Nur die Quader in Reichweite dieses Takts (weniger Rechnen je Stoß).
	var r := (k.vel as Vector3).length() * dt + STUFE + BREITE + 0.5
	var nah := AABB((k.pos as Vector3) - Vector3(r, r, r), Vector3(r * 2.0, HOCH + r * 2.0, r * 2.0))
	var welt: Array = alle.filter(func(b: AABB) -> bool: return b.intersects(nah))
	_ducken(k, ducken, welt, dt)
	var ausschlag := minf(Vector2(wunsch.x, wunsch.z).length(), 1.0)
	var richtung := Vector3(wunsch.x, 0, wunsch.z).normalized() if ausschlag > 0.0001 else Vector3.ZERO
	var wunsch_tempo := tempo * ausschlag * (DUCK_TEMPO if bool(k.duck) else 1.0)
	var vel: Vector3 = k.vel
	# Schwerkraft zur Hälfte vor, zur Hälfte nach der Bewegung (Source StartGravity/FinishGravity).
	if not bool(k.boden):
		vel.y -= SCHWERE * dt * 0.5
	# Springen nur vom Boden und nur bei neuem Drücken (kein Dauerhüpfen).
	if springen and not bool(k.sprung_alt) and bool(k.boden):
		vel.y = SPRUNG
		k.boden = false
	k.sprung_alt = springen
	if bool(k.boden):
		vel.y = 0.0
		vel = reibung(vel, dt)
		vel = beschleunigen(vel, richtung, wunsch_tempo, BESCHL, dt)
		k.vel = vel
		_boden_bewegen(k, welt, dt)
	else:
		vel = luft_beschleunigen(vel, richtung, wunsch_tempo, dt)
		k.vel = vel
		_gleiten(k, welt, dt)
	_lage_pruefen(k, welt)
	if not bool(k.boden):
		var v2: Vector3 = k.vel
		v2.y -= SCHWERE * dt * 0.5
		k.vel = v2
	else:
		var v3: Vector3 = k.vel
		v3.y = 0.0
		k.vel = v3


## Ducken: die Hülle wird gleich niedriger (Füße bleiben), der Blick senkt sich in DUCK_ZEIT.
## Aufstehen nur, wenn über dem Kopf Platz ist.
static func _ducken(k: Dictionary, ducken: bool, welt: Array, dt: float) -> void:
	if ducken and not bool(k.duck):
		k.duck = true
	elif not ducken and bool(k.duck):
		var p: Vector3 = k.pos
		var t := trace(p, p + Vector3(0, HOCH - HOCH_DUCK, 0), BREITE, HOCH_DUCK, welt)
		if float(t.anteil) >= 1.0:
			k.duck = false
	k.duck_t = move_toward(float(k.duck_t), 1.0 if bool(k.duck) else 0.0, dt / DUCK_ZEIT)


static func hoehe(k: Dictionary) -> float:
	return HOCH_DUCK if bool(k.duck) else HOCH


## Am Boden: wie Source StepMove – einmal direkt gleiten, einmal über die Stufe (hoch, gleiten,
## runter); genommen wird, was weiter kommt.
static func _boden_bewegen(k: Dictionary, welt: Array, dt: float) -> void:
	var start: Vector3 = k.pos
	var v0: Vector3 = k.vel
	if Vector2(v0.x, v0.z).length() < 0.0001:
		return
	_gleiten(k, welt, dt)
	var unten_pos: Vector3 = k.pos
	var unten_vel: Vector3 = k.vel
	var h := hoehe(k)
	# Über die Stufe.
	k.pos = start
	k.vel = v0
	var hoch := trace(start, start + Vector3(0, STUFE, 0), BREITE, h, welt)
	k.pos = hoch.ende
	_gleiten(k, welt, dt)
	var p: Vector3 = k.pos
	var runter := trace(p, p - Vector3(0, STUFE + EPS * 2.0, 0), BREITE, h, welt)
	var stufe_ok := float(runter.anteil) < 1.0 and (runter.normale as Vector3).y >= BODEN_N
	var weit_unten := Vector2(unten_pos.x - start.x, unten_pos.z - start.z).length_squared()
	var weit_stufe := Vector2((runter.ende as Vector3).x - start.x, (runter.ende as Vector3).z - start.z).length_squared()
	if stufe_ok and weit_stufe > weit_unten + 0.000001:
		k.pos = runter.ende
		var v: Vector3 = k.vel
		v.y = unten_vel.y
		k.vel = v
	else:
		k.pos = unten_pos
		k.vel = unten_vel
	# Am Boden bleiben (Source StayOnGround): eine Stufe hinab geht man, statt zu fallen.
	var q: Vector3 = k.pos
	var halt := trace(q, q - Vector3(0, STUFE, 0), BREITE, h, welt)
	if float(halt.anteil) > 0.0 and float(halt.anteil) < 1.0 and (halt.normale as Vector3).y >= BODEN_N:
		k.pos = halt.ende


## Bewegung mit Gleiten (Source TryPlayerMove): bis zu vier Stöße; an jeder getroffenen Fläche
## wird der Teil der Geschwindigkeit in die Fläche entfernt, der Rest geht weiter.
static func _gleiten(k: Dictionary, welt: Array, dt: float) -> void:
	var zeit := dt
	var ebenen: Array = []
	var h := hoehe(k)
	for stoss in 4:
		var vel: Vector3 = k.vel
		if vel.length_squared() < 1e-10:
			break
		var p: Vector3 = k.pos
		var t := trace(p, p + vel * zeit, BREITE, h, welt)
		k.pos = t.ende
		if float(t.anteil) >= 1.0:
			break
		zeit -= zeit * float(t.anteil)
		var n: Vector3 = t.normale
		ebenen.append(n)
		# An allen bisher getroffenen Flächen entlang (bei zwei Flächen: entlang der Kante).
		var neu := clip(vel, n)
		for e: Vector3 in ebenen:
			if neu.dot(e) < -0.0001:
				neu = clip(neu, e)
		if ebenen.size() >= 2 and neu.dot(ebenen[0]) < -0.0001:
			var kante := (ebenen[0] as Vector3).cross(n)
			neu = kante * kante.dot(vel) if kante.length_squared() > 0.0001 else Vector3.ZERO
		k.vel = neu


## Geschwindigkeit an einer Fläche: der Anteil in die Fläche fällt weg (Source ClipVelocity, 1,0).
static func clip(v: Vector3, n: Vector3) -> Vector3:
	var hinein := v.dot(n)
	return v - n * hinein if hinein < 0.0 else v


## Am Boden? (Source CategorizePosition): ein kurzer Stoß nach unten.
static func _lage_pruefen(k: Dictionary, welt: Array) -> void:
	var vel: Vector3 = k.vel
	if vel.y > NICHT_SPRUNG:
		k.boden = false
		return
	var p: Vector3 = k.pos
	var t := trace(p, p - Vector3(0, 0.04, 0), BREITE, hoehe(k), welt)
	var war: bool = k.boden
	k.boden = float(t.anteil) < 1.0 and (t.normale as Vector3).y >= BODEN_N
	if bool(k.boden):
		# Am Boden ankleben (kleine Stufen hinab, kein Hüpfen über Kanten).
		if war or vel.y <= 0.0:
			k.pos = t.ende


## Sweep der Hülle (Füße in der Mitte unten, halbe Breite b, Höhe h) von a nach e gegen die
## Quader der Welt. { anteil 0…1, ende, normale }.
static func trace(a: Vector3, e: Vector3, b: float, h: float, welt: Array) -> Dictionary:
	var d := e - a
	var anteil := 1.0
	var normale := Vector3.ZERO
	for box: AABB in welt:
		# Minkowski: der Quader um die Hülle vergrößert, die Hülle wird zum Punkt (Fußmitte).
		var lo := box.position - Vector3(b, h, b)
		var hi := box.end + Vector3(b, 0, b)
		var t_ein := -INF
		var t_aus := INF
		var n_ein := Vector3.ZERO
		var drin := true
		var verfehlt := false
		for ach in 3:
			var s := a[ach]
			var r := d[ach]
			if s <= lo[ach] or s >= hi[ach]:
				drin = false
			if absf(r) < 1e-9:
				if s <= lo[ach] or s >= hi[ach]:
					verfehlt = true
					break
				continue
			var t1 := (lo[ach] - s) / r
			var t2 := (hi[ach] - s) / r
			var nn := Vector3.ZERO
			nn[ach] = -1.0 if r > 0.0 else 1.0
			if t1 > t2:
				var tt := t1
				t1 = t2
				t2 = tt
			if t1 > t_ein:
				t_ein = t1
				n_ein = nn
			t_aus = minf(t_aus, t2)
		if verfehlt:
			continue
		if drin:
			# Steckt die Hülle schon drin (ein Möbel wurde auf dich gestellt): dieser Quader hält
			# nicht fest – du gehst einfach hinaus.
			continue
		if t_ein > t_aus or t_aus <= 0.0 or t_ein >= anteil or t_ein < 0.0:
			continue
		anteil = t_ein
		normale = n_ein
	# Etwas Abstand zur Fläche halten (gegen Steckenbleiben durch Rundung).
	var len := d.length()
	var t_eps := clampf(anteil - (EPS / len if len > 0.0 else 0.0), 0.0, 1.0) if anteil < 1.0 else 1.0
	return { "anteil": anteil, "ende": a + d * t_eps, "normale": normale }


## Die Welt eines Zimmers: Boden, vier Wände, Decke und alle Möbel, die im Weg stehen.
## moebel: [[x0, z0, x1, z1, hoehe], …] (Meter).
static func welt_aus(w: float, d: float, decke: float, moebel: Array) -> Array:
	var out: Array = [
		AABB(Vector3(-1, -1, -1), Vector3(w + 2, 1, d + 2)),
		AABB(Vector3(-1, -1, -1), Vector3(1, decke + 2, d + 2)),
		AABB(Vector3(w, -1, -1), Vector3(1, decke + 2, d + 2)),
		AABB(Vector3(-1, -1, -1), Vector3(w + 2, decke + 2, 1)),
		AABB(Vector3(-1, -1, d), Vector3(w + 2, decke + 2, 1)),
		AABB(Vector3(-1, decke, -1), Vector3(w + 2, 1, d + 2)),
	]
	for m: Array in moebel:
		out.append(AABB(Vector3(float(m[0]), 0.0, float(m[1])), Vector3(float(m[2]) - float(m[0]), float(m[4]), float(m[3]) - float(m[1]))))
	return out
