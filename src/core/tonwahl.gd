extends Node
## Audio output: a fixed device that Uzai always switches back to, plus FxSound – both controlled without leaving
## Uzai. Attached to the mixer (Mixer.tonwahl).
##
## Reason: when the TV turns off, its audio output disappears; Windows or FxSound fall back to another device and
## stay there once the TV is back. Switching back had to be done by hand, i.e. outside Uzai. Now:
##
## 1. Fixed device (ton.fest_id / ton.fest_name, for the whole PC). While one is set, Uzai checks every
##    TAKT_S seconds which audio outputs exist (audio-list – no network, in the helper).
##    - Windows in charge: if another device is the default although the fixed one is present, Uzai switches back.
##    - FxSound in charge (its own device is the default): Windows does not reveal where FxSound outputs to.
##      So once the devices have changed and then stayed unchanged for RUHE_MS (the TV is back), Uzai points
##      FxSound at the fixed device (--output), reads the state back and tries at most FX_VERSUCHE times.
##    Choosing another device in Uzai makes that one the fixed device. Paused while a game profile has changed
##    the audio output (profile_run.gd) – afterwards the fixed device applies again.
## 2. FxSound (src/core/fxsound.gd): read state, on/off, sound profile, launch. Only through FxSound's own
##    command line, and only when it is running and recent enough.
##
## Decisions are static and testable without Windows (tests/logic_fxsound.gd). Not yet run on Windows.

signal changed

const BildTon := preload("res://src/core/bild_ton.gd")
const FxSound := preload("res://src/core/fxsound.gd")
const Fremd := preload("res://src/core/fremd.gd")
const ProfileRun := preload("res://src/core/profile_run.gd")

const TAKT_S := 2.0
const RUHE_MS := 1500           ## so lange müssen die Geräte still stehen, bevor Uzai FxSound umstellt
const FX_VERSUCHE := 3
const FX_ALT_MS := 20000        ## so lange gilt ein gelesener Stand von FxSound
## Stellt etwas anderes immer wieder um (ein zweites Programm mit derselben Idee): nach ZURUECK_MAX Mal in einer
## Minute ruht Uzai ZURUECK_PAUSE_MS, statt alle zwei Sekunden dagegenzuhalten.
const ZURUECK_MAX := 4
const ZURUECK_PAUSE_MS := 300000
const DEMO_PROFILE := ["General", "Gaming", "Movies", "Music", "Bass Boost", "Voice", "Volume Boost"]

static var _id_form := RegEx.create_from_string("^\\{[0-9.]{1,40}\\}\\.\\{[0-9a-fA-F-]{36}\\}\\z")

## Stand von FxSound (FxSound.stand): { da, laeuft, version, bedienbar, alt, an, profil, profile, geraet, geraete }.
var fx: Dictionary = FxSound.stand({})
var _fx_ms := -FX_ALT_MS
var _sig := ""                  ## Geräte beim letzten Takt
var _seit_ms := 0               ## seit wann sie so stehen
var _neu := true                ## sie haben sich geändert, Uzai hat darauf noch nicht geantwortet
var _offen := false             ## FxSound steht (noch) nicht auf dem festen Gerät
var _versuche := 0
var _busy := false
var _gestartet := false
var _demo_fx := { "an": true, "profil": "Gaming", "geraet": "" }
var _zurueck: Array = []        ## wann Uzai zuletzt zurückgestellt hat (ms)
var _pause_bis := 0


func _ready() -> void:
	if not (Config.is_windows() or Library.demo):
		return
	if Library.demo:
		_fx_demo()
	var t := Timer.new()
	t.wait_time = TAKT_S
	t.timeout.connect(_takt)
	add_child(t)
	t.start()
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("ton.fest"):
			_neu = true
			_offen = false
			_versuche = 0
	)
	Helper.helper_ready.connect(_beim_start)
	if Helper.available:
		_beim_start()


# --- Rein (getestet) -----------------------------------------------------------------------------

## Antwort auf „audio-list“ → [{ id, name, ff, default }]. Kennungen geprüft; Namen bleiben, wie Windows sie nennt
## (FxSound verlangt sie genau so) – einer mit Steuer- oder Anführungszeichen wird leer (dann nur über Windows).
static func geraete_aus(r: Dictionary) -> Array:
	var out: Array = []
	var res: Variant = r.get("result")
	if r.get("ok") != true or not (res is Dictionary):
		return out
	for d in Fremd.zeilen(res, "devices"):
		var id := Fremd.text((d as Dictionary).get("id"))
		if _id_form.search(id) == null or out.size() >= FxSound.GERAETE_MAX or out.any(func(x: Dictionary) -> bool: return str(x.id) == id):
			continue
		var name := Fremd.text((d as Dictionary).get("name"))
		out.append({ "id": id, "name": name if FxSound.wert_ok(name) else "", "ff": Fremd.zahl((d as Dictionary).get("ff"), -1),
				"default": Fremd.ja((d as Dictionary).get("default")) })
	return out


## Stand der Geräte als Text: ändert er sich, ist ein Gerät gekommen oder gegangen (oder der Standard gewechselt).
static func signatur(geraete: Array) -> String:
	var ids := PackedStringArray()
	var std := ""
	for g in geraete:
		ids.append(str(g.id))
		if bool(g.get("default", false)):
			std = str(g.id)
	ids.sort()
	return ",".join(ids) + "|" + std


## Das feste Gerät unter den vorhandenen: nach Kennung, sonst nach Namen (Windows vergibt nach einem neuen
## Treiber neue Kennungen). {} wenn es gerade nicht da ist.
static func finde(geraete: Array, fest_id: String, fest_name: String) -> Dictionary:
	for g in geraete:
		if fest_id != "" and str(g.id) == fest_id:
			return g
	for g in geraete:
		if fest_name != "" and str(g.name) == fest_name:
			return g
	return {}


## Das Standardgerät von Windows ({} wenn keins gemeldet ist).
static func standard(geraete: Array) -> Dictionary:
	for g in geraete:
		if bool(g.get("default", false)):
			return g
	return {}


## Führt FxSound den Ton? (Sein eigenes Gerät ist das Standardgerät von Windows.)
static func fx_fuehrt(geraete: Array) -> bool:
	return FxSound.ist_eigenes(str(standard(geraete).get("name", "")))


## Was der Wächter jetzt tut: "" (nichts), "windows" (als Standardgerät setzen) oder "fxsound" (FxSound darauf
## stellen). da: das feste Gerät, wie finde() es liefert. geaendert: Die Geräte haben sich geändert und stehen
## still. offen: Ein früherer Versuch mit FxSound steht noch aus. fx_bedienbar: FxSound nimmt Befehle.
static func schritt(geraete: Array, da: Dictionary, geaendert: bool, offen: bool, fx_bedienbar: bool) -> String:
	if da.is_empty():
		return ""
	if fx_fuehrt(geraete):
		# FxSound nimmt den Namen: ohne sendbaren Namen oder ohne bedienbares FxSound lässt Uzai es in Ruhe
		# (am Standardgerät von Windows vorbei umzustellen, nähme FxSound den Ton weg).
		if not fx_bedienbar or str(da.get("name", "")) == "" or not (geaendert or offen):
			return ""
		return "fxsound"
	return "" if bool(da.get("default", false)) else "windows"


## Geräte für eine Auswahl in Uzai: ohne FxSounds eigenes Gerät. { devices: [{ id, name, kind }], current }.
## Führt FxSound, ist „current“ das Gerät, auf das FxSound ausgibt (fx_geraet), sonst das Standardgerät.
static func auswahl(geraete: Array, fx_geraet: String) -> Dictionary:
	var out := { "devices": [], "current": "" }
	var fuehrt := fx_fuehrt(geraete)
	for g in geraete:
		if FxSound.ist_eigenes(str(g.name)):
			continue
		var gezeigt: String = str(g.name) if str(g.name) != "" else str(TranslationServer.translate("Tonausgabe"))
		(out.devices as Array).append({ "id": str(g.id), "name": gezeigt, "kind": BildTon.audio_kind(int(g.get("ff", -1)), gezeigt) })
		if (fuehrt and fx_geraet != "" and str(g.name) == fx_geraet) or (not fuehrt and bool(g.get("default", false))):
			out.current = str(g.id)
	return out


# --- Festes Gerät --------------------------------------------------------------------------------

static func fest_id() -> String:
	var v := str(Config.get_value("ton.fest_id", ""))
	return v if _id_form.search(v) != null else ""


static func fest_name() -> String:
	var v := str(Config.get_value("ton.fest_name", ""))
	return v if FxSound.wert_ok(v) else ""


static func fest_an() -> bool:
	return fest_id() != "" or fest_name() != ""


## Das feste Gerät wählen ("" und "" = keins).
func fest_setzen(id: String, name: String) -> void:
	Config.set_value("ton.fest_id", id if _id_form.search(id) != null else "")
	Config.set_value("ton.fest_name", name if FxSound.wert_ok(name) else "")
	changed.emit()


## Ruht der Wächter? Solange ein Spiel-Profil die Tonausgabe umgestellt hat – oder nach zu vielen Rückstellungen.
func _ruht() -> bool:
	if Time.get_ticks_msec() < _pause_bis:
		return true
	var p := Launcher.profile as ProfileRun
	return p != null and p.ton_umgestellt()


## Darf Uzai jetzt (noch einmal) zurückstellen? Zählt mit; nach zu vielen in einer Minute ist Pause.
static func darf_zurueck(zeiten: Array, jetzt: int) -> bool:
	return zeiten.filter(func(t: int) -> bool: return jetzt - t < 60000).size() < ZURUECK_MAX


func _takt() -> void:
	if _busy or Library.demo or not fest_an() or not Helper.available or _ruht():
		return
	_busy = true
	await _pruefen()
	_busy = false


func _pruefen() -> void:
	var geraete := geraete_aus(await Helper.run("audio-list", {}, 8.0))
	if geraete.is_empty():
		return
	var jetzt := Time.get_ticks_msec()
	var sig := signatur(geraete)
	if sig != _sig:
		_sig = sig
		_seit_ms = jetzt
		_neu = true
	var da := finde(geraete, fest_id(), fest_name())
	# Dasselbe Gerät unter neuer Kennung (oder erst jetzt mit Namen): merken, was jetzt gilt.
	if not da.is_empty() and (str(da.id) != fest_id() or (str(da.name) != "" and str(da.name) != fest_name())):
		Config.set_value("ton.fest_id", str(da.id))
		if str(da.name) != "":
			Config.set_value("ton.fest_name", str(da.name))
	var geaendert := _neu and jetzt - _seit_ms >= RUHE_MS
	var fuehrt := fx_fuehrt(geraete)
	if fuehrt and (geaendert or _offen) and not da.is_empty():
		await fx_lesen(true)
	var was := schritt(geraete, da, geaendert, _offen, bool(fx.bedienbar))
	if was != "" and not darf_zurueck(_zurueck, jetzt):
		_pause_bis = jetzt + ZURUECK_PAUSE_MS
		_zurueck.clear()
		Helper.hlog("Tonausgabe: etwas stellt immer wieder um – Uzai hält %d Minuten still" % int(ZURUECK_PAUSE_MS / 60000.0))
		return
	if was != "":
		_zurueck = _zurueck.filter(func(t: int) -> bool: return jetzt - t < 60000)
		_zurueck.append(jetzt)
	match was:
		"windows":
			_neu = false
			var r := await Helper.run("audio-set", { "id": str(da.id) }, 8.0)
			Helper.hlog("Tonausgabe: zurück auf das feste Gerät (Windows) – %s" % ("ok" if r.get("ok") == true else "nicht übernommen"))
			if r.get("ok") == true:
				_melden(str(da.name))
		"fxsound":
			_neu = false
			if str(fx.geraet) == str(da.name):
				_offen = false
				_versuche = 0
				return
			_versuche += 1
			var ok := await fx_setzen({ "output": str(da.name) })
			var steht: bool = ok and str(fx.geraet) == str(da.name)
			_offen = not steht and _versuche < FX_VERSUCHE
			Helper.hlog("Tonausgabe: FxSound auf das feste Gerät – %s (Versuch %d)" % ["ok" if steht else "noch nicht", _versuche])
			if steht:
				_versuche = 0
				_melden(str(da.name))
		_:
			if geaendert:
				_neu = false


func _melden(name: String) -> void:
	if name != "":
		Toasts.show_toast("Ton wieder über", name, "speaker", { "ms": 2600, "quiet": true, "sub_raw": true })


# --- Auswahl in Uzai -----------------------------------------------------------------------------

## Geräte für die Auswahl lesen (auswahl()). Leer, wenn der Helfer nicht antwortet.
func geraete_lesen() -> Dictionary:
	if Library.demo:
		return _demo_auswahl()
	if not Helper.available:
		return { "devices": [], "current": "" }
	var geraete := geraete_aus(await Helper.run("audio-list", {}, 8.0))
	if fx_fuehrt(geraete):
		await fx_lesen()
	var out := auswahl(geraete, str(fx.geraet))
	out["roh"] = geraete
	return out


## Jetzt über dieses Gerät ausgeben (Kennung aus geraete_lesen). Führt FxSound, stellt Uzai FxSound um, sonst das
## Standardgerät von Windows. Ist ein festes Gerät gewählt, wird dieses zum festen. true: übernommen.
func ausgeben_ueber(id: String, liste: Dictionary = {}) -> bool:
	if Library.demo:
		BildTon.demo_audio = id
		for d in BildTon.DEMO_AUDIO:
			if str(d.id) == id:
				_demo_fx.geraet = str(d.name)
				if fest_an():
					fest_setzen(id, str(d.name))
		changed.emit()
		return true
	var roh: Array = liste.get("roh", []) if liste.get("roh") is Array else geraete_aus(await Helper.run("audio-list", {}, 8.0))
	var ziel := finde(roh, id, "")
	if ziel.is_empty():
		return false
	var ok := false
	if fx_fuehrt(roh):
		if str(ziel.name) == "" or not bool(fx.bedienbar):
			return false
		ok = await fx_setzen({ "output": str(ziel.name) }) and str(fx.geraet) == str(ziel.name)
	else:
		ok = (await Helper.run("audio-set", { "id": id }, 8.0)).get("ok") == true
	if ok and fest_an():
		fest_setzen(id, str(ziel.name))
	if ok:
		_sig = ""
		changed.emit()
	return ok


func _demo_auswahl() -> Dictionary:
	var roh: Array = []
	if BildTon.demo_audio == "":
		BildTon.demo_audio = str(BildTon.DEMO_AUDIO[0].id)
	for d in BildTon.DEMO_AUDIO:
		roh.append({ "id": str(d.id), "name": str(d.name), "ff": int(d.ff), "default": str(d.id) == BildTon.demo_audio })
	var out := auswahl(roh, "")
	out["roh"] = roh
	return out


# --- FxSound -------------------------------------------------------------------------------------

## Einmal, sobald der Helfer läuft: nachsehen, ob es FxSound gibt (für die Einstellungen), und es auf Wunsch still
## starten (ton.fxsound_start).
func _beim_start() -> void:
	if _gestartet or Library.demo or not Config.is_windows():
		return
	_gestartet = true
	# „status“ schließt „info“ ein: Läuft FxSound, steht gleich sein ganzer Stand da (Zeile in den Einstellungen).
	var s := FxSound.stand(await Helper.run("fxsound", { "op": "status" }, 12.0))
	fx = s
	_fx_ms = Time.get_ticks_msec()
	if bool(s.da) != bool(Config.get_value("ton.fxsound_da", false)):
		Config.set_value("ton.fxsound_da", bool(s.da))
	if bool(s.da) and not bool(s.laeuft) and bool(Config.get_value("ton.fxsound_start", false)):
		await fx_starten()
	changed.emit()


## Stand von FxSound lesen (höchstens alle FX_ALT_MS, außer erzwingen).
func fx_lesen(erzwingen := false) -> void:
	if Library.demo:
		_fx_demo()
		return
	if not Helper.available or (not erzwingen and Time.get_ticks_msec() - _fx_ms < FX_ALT_MS):
		return
	_fx_ms = Time.get_ticks_msec()
	fx = FxSound.stand(await Helper.run("fxsound", { "op": "status" }, 12.0))
	if bool(fx.da) != bool(Config.get_value("ton.fxsound_da", false)):
		Config.set_value("ton.fxsound_da", bool(fx.da))
	changed.emit()


## FxSound umstellen: { "power": bool }, { "preset": Name } oder { "output": Gerätename }. Liest danach den Stand.
## true: FxSound hat den Befehl bekommen (ob er gewirkt hat, steht in fx).
func fx_setzen(was: Dictionary) -> bool:
	if Library.demo:
		if was.has("power"):
			_demo_fx.an = bool(was.power)
		if was.has("preset"):
			_demo_fx.profil = str(was.preset)
		if was.has("output"):
			_demo_fx.geraet = str(was.output)
		_fx_demo()
		return true
	var args := { "op": "set" }
	if was.has("power"):
		args["power"] = 1 if bool(was.power) else 0
	if was.has("preset"):
		if not FxSound.wert_ok(str(was.preset), FxSound.NAME_MAX):
			return false
		args["preset"] = str(was.preset)
	if was.has("output"):
		if not FxSound.wert_ok(str(was.output)):
			return false
		args["output"] = str(was.output)
	if args.size() < 2 or not Helper.available:
		return false
	var r := await Helper.run("fxsound", args, 14.0)
	_fx_ms = Time.get_ticks_msec()
	fx = FxSound.stand(r)
	changed.emit()
	return r.get("ok") == true and bool(fx.laeuft)


## FxSound still starten (im Infobereich, ohne Fenster) und warten, bis es antwortet. true: es läuft.
func fx_starten() -> bool:
	if Library.demo:
		_fx_demo()
		return true
	if not Helper.available:
		return false
	await Helper.run("fxsound", { "op": "start" }, 10.0)
	for i in 10:
		await get_tree().create_timer(1.0).timeout
		await fx_lesen(true)
		if bool(fx.bedienbar) or bool(fx.alt):
			break
	return bool(fx.laeuft)


func _fx_demo() -> void:
	var geraet := str(_demo_fx.geraet)
	if geraet == "":
		geraet = str(BildTon.DEMO_AUDIO[0].name)
	fx = { "da": true, "laeuft": true, "version": "1.2.15.0", "bedienbar": true, "alt": false, "an": bool(_demo_fx.an), "profil": str(_demo_fx.profil),
			"profile": DEMO_PROFILE.duplicate(), "geraet": geraet, "geraete": BildTon.DEMO_AUDIO.map(func(d: Dictionary) -> String: return str(d.name)) }
	changed.emit()
