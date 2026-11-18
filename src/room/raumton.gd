extends Node
## Ton des Spiels aus dem Fernseher (Punkt 131): Läuft ein Spiel und du bist im Zimmer (laufen, Bauen,
## Foto, Menüs, Guide über dem Zimmer – fernsehspiel.gd ton_im_raum), klingt es, als käme es aus dem
## Fernseher im Zimmer: leiser mit der Entfernung,
## links/rechts nach der Richtung zum Fernseher, bezogen auf deinen Blick, dahinter etwas leiser, und
## immer ein wenig zurückgenommen (GEDAEMPFT). Ein echter Tiefpass ginge nur im Tonweg des Spiels
## selbst – dort greift Uzai nicht ein. Im Vollbild klingt das Spiel normal.
##
## Umsetzung: Der Helfer („raum-ton“, UzAudio.RaumTon) setzt nur die Kanal-Lautstärken
## (IChannelAudioVolume) der Audiositzungen des Spiels samt Kindprozessen – nie die Gesamtlautstärke
## von Windows, nie andere Programme; Uzai schickt nur zwei Zahlen 0..1000. Gibt eine Sitzung die
## Kanäle nicht her, nimmt er ihre Lautstärke (dann ohne links/rechts). Was vorher eingestellt war,
## merkt er sich und stellt es zurück: auf „aus“ (Fokus, Spielende, Zimmer zu), wenn Uzai LEASE_S lang
## nichts sagt (Absturz, Hänger) und wenn Uzai den Helfer schließt (Uzai beendet). Für den Fall, dass
## auch der Helfer abstürzt, steht in Config, was zurückmuss (ZURUECK_KEY); beim nächsten Start
## desselben Spiels stellt aufraeumen() es zurück.
##
## Sparsam: höchstens TAKT_HZ Aufträge je Sekunde und nur bei einer Änderung ab SCHWELLE, dazu ein
## Lebenszeichen alle PULS_S; dazwischen gleitet der Pegel weich (GLAETTEN_S). Abschaltbar im
## Zimmer-Menü › Kamera und Bild („Spielton aus dem Fernseher“, Config KEY_AN).
## Ohne Fenster prüfbar (tests/logic_fernsehspiel.gd): pegel, antwort, werte.

const Fernsehspiel := preload("res://src/room/fernsehspiel.gd")
const Spielbild := preload("res://src/room/spielbild.gd")
const MixerS := preload("res://src/core/mixer.gd")
const Fremd := preload("res://src/core/fremd.gd")

const KEY_AN := "room.raumton"
const ZURUECK_KEY := "room.raumton_zurueck"   ## { spiel, alt: [0..1000, …] } – nach einem Absturz zurück
const TAKT_HZ := 10.0
const SCHWELLE := 0.02             ## kleinere Änderungen schickt Uzai nicht (nur mit dem Lebenszeichen)
const PULS_S := 1.5
const LEASE_S := 5.0               ## so lange ohne Auftrag stellt der Helfer von selbst zurück (UzAudio)
const GLAETTEN_S := 0.25
const NAH_M := 1.6                 ## bis hierher volle Lautstärke (etwa der Platz vor dem Fernseher)
const MIN_PEGEL := 0.15            ## ganz hinten im Raum
const GEDAEMPFT := 0.85            ## außerhalb des Fokus immer ein wenig leiser
const HINTEN := 0.25               ## hinter dir: so viel leiser
const BALANCE := 0.65              ## ganz seitlich: das abgewandte Ohr so viel leiser
const OHNE_TV := 0.2               ## kein Fernseher in diesem Raum: leise, mittig
const MAX_KANAELE := 8
const VERSUCHE := [3.0, 10.0, 30.0]   ## aufraeumen: so lange nach dem Start (die Sitzung kommt oft später)

var hoerer: Callable               ## → Transform3D: wo du hörst (Kamera bzw. Kopf der Figur), Blick nach −z
var quelle: Callable               ## → Vector3 (Bildschirm des Fernsehers) oder null (kein Fernseher)
var zustand: Callable              ## → String: Zustand des Spiels im Fernseher (fernsehspiel.gd)

var _ist := Vector2.ONE
var _gesendet := Vector2(-1, -1)
var _seit := 0.0
var _takt := 0.0
var _aktiv := false                ## der Helfer hat Werte gesetzt, die zurückmüssen
var _unterwegs := false
var _gemeldet := false


## Ist der Raumton eingeschaltet (Zimmer-Menü)?
static func an() -> bool:
	var v: Variant = Config.get_value(KEY_AN, true)
	return not (v is bool) or bool(v)


## Pegel [links, rechts] 0..1 für einen Hörer (Transform, Blick nach −z) und den Bildschirm des
## Fernsehers (Vector3, sonst kein Fernseher im Raum).
static func pegel(h: Transform3D, ziel: Variant) -> Vector2:
	if not (ziel is Vector3):
		return Vector2(OHNE_TV, OHNE_TV)
	var v: Vector3 = h.orthonormalized().affine_inverse() * (ziel as Vector3)
	var g := clampf(NAH_M / maxf(NAH_M, v.length()), MIN_PEGEL, 1.0) * GEDAEMPFT
	var flach := Vector2(v.x, v.z)
	if flach.length() < 0.05:
		return Vector2(g, g)
	var seite := clampf(v.x / flach.length(), -1.0, 1.0)
	g *= 1.0 - HINTEN * clampf(v.z / flach.length(), 0.0, 1.0)
	return Vector2(g * (1.0 - BALANCE * maxf(0.0, seite)), g * (1.0 - BALANCE * maxf(0.0, -seite)))


## Auf Tausendstel (so geht es zum Helfer).
static func gerundet(p: Vector2) -> Vector2:
	return Vector2(clampf(roundf(p.x * 1000.0), 0.0, 1000.0) / 1000.0, clampf(roundf(p.y * 1000.0), 0.0, 1000.0) / 1000.0)


## Antwort des Helfers → { found, kanal, sessions, alt: [0..1000 …], weg, error }.
static func antwort(r: Dictionary) -> Dictionary:
	var out := { "found": false, "kanal": false, "sessions": 0, "alt": [], "weg": 0, "error": true }
	var res: Variant = r.get("result")
	if not bool(r.get("ok", false)) or not (res is Dictionary):
		return out
	var d: Variant = Fremd.json_roh(str((res as Dictionary).get("json", "")))
	if not (d is Dictionary):
		return out
	out.error = bool((d as Dictionary).get("timeout", false)) or (d as Dictionary).has("error")
	out.found = bool((d as Dictionary).get("found", false))
	out.kanal = bool((d as Dictionary).get("kanal", false))
	out.sessions = clampi(int((d as Dictionary).get("sessions", 0)) if (d as Dictionary).get("sessions") is float else 0, 0, 512)
	out.weg = clampi(int((d as Dictionary).get("weg", 0)) if (d as Dictionary).get("weg") is float else 0, 0, 512)
	out.alt = werte((d as Dictionary).get("alt"))
	return out


## Kanal-Werte aus fremder Hand: höchstens MAX_KANAELE ganze Zahlen 0..1000, sonst [].
static func werte(v: Variant) -> Array:
	if not (v is Array) or (v as Array).is_empty() or (v as Array).size() > MAX_KANAELE:
		return []
	var out: Array = []
	for x in v:
		if not (x is float or x is int) or float(x) < 0.0 or float(x) > 1000.0:
			return []
		out.append(roundi(float(x)))
	return out


func _helfer() -> bool:
	return Config.is_windows() and Helper.available and not Library.demo


func _process(dt: float) -> void:
	var z := str(zustand.call()) if zustand.is_valid() else ""
	var im_raum := an() and Launcher.in_game and Spielbild.spiel_laeuft() and Fernsehspiel.ton_im_raum(z)
	var soll := Vector2.ONE
	if im_raum and hoerer.is_valid():
		soll = pegel(hoerer.call(), quelle.call() if quelle.is_valid() else null)
	_ist = _ist.lerp(soll, 1.0 - exp(-dt / GLAETTEN_S))
	if _ist.distance_to(soll) < 0.004:
		_ist = soll
	_takt -= dt
	_seit += dt
	if _unterwegs or _takt > 0.0 or not _helfer():
		return
	if not Launcher.in_game:
		if _aktiv:
			_aus()
		return
	if not im_raum:
		# Weich zurück auf normal, dann gibt der Helfer die alten Werte genau zurück.
		if _aktiv and _ist == Vector2.ONE:
			_aus()
			return
		if not _aktiv:
			return
	var q := gerundet(_ist)
	if _aktiv and absf(q.x - _gesendet.x) < SCHWELLE and absf(q.y - _gesendet.y) < SCHWELLE and _seit < PULS_S \
			and not (q == Vector2.ONE and _gesendet != Vector2.ONE):
		return
	_senden(q)


func _senden(q: Vector2) -> void:
	_takt = 1.0 / TAKT_HZ
	_seit = 0.0
	var a := MixerS.game_args(Launcher.pid, str(Launcher.current.get("install_dir", "")), Launcher.game_hwnd())
	if a.is_empty():
		_takt = 2.0
		return
	a["l"] = roundi(q.x * 1000.0)
	a["r"] = roundi(q.y * 1000.0)
	a["skip"] = [OS.get_process_id()]
	if not _aktiv:
		_aktiv = true
		_merken([])
	_gesendet = q
	_unterwegs = true
	var d := antwort(await Helper.run("raum-ton", a, 2.0))
	_unterwegs = false
	if not is_inside_tree():
		return
	if not (d.alt as Array).is_empty():
		var m: Variant = Config.get_value(ZURUECK_KEY, {})
		if m is Dictionary and ((m as Dictionary).get("alt", []) as Array).is_empty():
			_merken(d.alt)
	if bool(d.found) and not _gemeldet:
		_gemeldet = true
		Launcher.log_launch("Zimmer: Spielton kommt aus dem Fernseher (%d Audiositzung%s, %s)" % [int(d.sessions), "" if int(d.sessions) == 1 else "en",
				"links/rechts über die Kanäle" if bool(d.kanal) else "nur leiser – das Spiel gibt die Kanäle nicht her"])


## Was zurückmuss, in Config (übersteht einen Absturz von Uzai und Helfer).
func _merken(alt: Array) -> void:
	Config.set_value(ZURUECK_KEY, { "spiel": str(Launcher.current.get("id", "")), "alt": alt })
	Config.save_settings()


func _aus() -> void:
	_aktiv = false
	_gesendet = Vector2(-1, -1)
	_unterwegs = true
	await zurueck()
	_unterwegs = false


## Alte Werte zurück (der Helfer kennt sie). Konnte er alle zurückstellen, ist der Vermerk erledigt;
## war eine Sitzung schon weg (Spiel beendet), bleibt er für den nächsten Start dieses Spiels.
static func zurueck() -> void:
	var d := antwort(await Helper.run("raum-ton", { "aus": true }, 2.0))
	if not bool(d.error) and int(d.weg) == 0:
		Config.set_value(ZURUECK_KEY, {})
		Config.save_settings()


func _exit_tree() -> void:
	# Zimmer zu (auch beim Beenden von Uzai): zurück, ohne auf die Antwort zu warten.
	if _aktiv and _helfer():
		_aktiv = false
		zurueck()


## Beim Start eines Spiels (Spielfenster da): Steht noch ein Vermerk für genau dieses Spiel (Uzai und
## Helfer waren abgestürzt, während der Ton aus dem Fernseher kam), die alten Kanal-Werte setzen –
## einige Male, denn das Spiel öffnet seinen Ton oft erst nach dem Fenster.
static func aufraeumen() -> void:
	var m: Variant = Config.get_value(ZURUECK_KEY, {})
	if not (m is Dictionary) or (m as Dictionary).is_empty() or not Config.is_windows() or not Helper.available:
		return
	var id := str((m as Dictionary).get("spiel", ""))
	if not Launcher.in_game or id == "" or id != str(Launcher.current.get("id", "")):
		return
	var alt := werte((m as Dictionary).get("alt"))
	Config.set_value(ZURUECK_KEY, {})
	Config.save_settings()
	if alt.is_empty():
		return
	var baum := Engine.get_main_loop() as SceneTree
	var bisher := 0.0
	for s in VERSUCHE:
		if baum == null:
			return
		await baum.create_timer(float(s) - bisher).timeout
		bisher = float(s)
		if not Launcher.in_game or id != str(Launcher.current.get("id", "")):
			return
		var a := MixerS.game_args(Launcher.pid, str(Launcher.current.get("install_dir", "")), Launcher.game_hwnd())
		if a.is_empty():
			continue
		a["werte"] = alt
		a["skip"] = [OS.get_process_id()]
		var d := antwort(await Helper.run("raum-ton", a, 2.0))
		if bool(d.found):
			Launcher.log_launch("Zimmer: Kanal-Lautstärken des Spiels nach einem Absturz zurückgestellt (%d Audiositzung%s)" % [int(d.sessions),
					"" if int(d.sessions) == 1 else "en"])
			return
