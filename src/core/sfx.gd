extends Node
## Menüklänge. Standard ist der Klangsatz „Handpan“ (Klang.SATZ_STD, tools/synth_klang5.py,
## assets/sounds/handpan: eine tiefe, weiche Handpan mit Nachklang). Wählbar (Einstellung theme.sound_set,
## Klang.SAETZE): „Samt“, „Kiesel“, „Pad“ und „Haptik“ (weich und leise, tools/synth_klang4.py), „Perle“ (gläsern, präzise,
## tools/synth_klang3.py), „Filz & Glas“, „Glas kurz“, „Filz“ und „Luft“ (warm, kurz, tools/synth_klang2.py,
## assets/sounds/<Kennung>), „Glas“ (die gläsernen Klänge bis 0.11, assets/sounds/glas) und „Tick“
## (assets/sounds, tools/synth_tick.py).
## Fassungen: Liegen neben <name>.wav auch <name>_v2.wav, <name>_v3.wav …, wählt jeder Druck zufällig
## eine davon, nie dieselbe zweimal hintereinander (Klang.variante) – Bewegen ermüdet so nicht.
## Fehlt eine Datei, greift die aus „Tick“, und fehlt auch die, wird der Tick hier erzeugt.
## Eigene Klänge im Datenordner gelten immer zuletzt.
## Eigene Klänge: Datei "<name>.wav" oder ".ogg" in den Datenordner unter "sounds" legen
## (move, tick, bump, select, back, open, toggle_on, toggle_off, tab, guide, guide_close,
## notify, error, boot, launch, achievement, shutter, power_off, unlock, unlock_rare, unlock_retro,
## setup_step, setup_found, setup_done, swell – die vier für die Einrichtung: Klang.EINRICHTUNG).
##
## Regeln (Plan „Gefühl“ 3.3, Rechnung in klang.gd): ein Druck, ein Klang (der spätere, mindestens
## so wichtige ersetzt den früheren: „open“ statt „select“); Bewegen höchstens alle 70 ms, beim
## Halten bis −8 dB leiser, nie zweimal gleich (Tonhöhe ±1,5 %, Lautstärke ±0,5 dB); nach über
## 10 min ohne Eingabe 6 dB leiser und in 3 s wieder voll; abends (22–7 Uhr) 4 dB leiser.
## Jeder Spieler hat eine eigene kleine Leitung mit Panorama vor „UI“ – so kommt ein Klang ganz
## leicht von dort, wo die Auswahl steht, der Bereichswechsel aus seiner Richtung. Die Menümusik
## (menu_musik.gd) hängt hier mit dran.
##
## Haptik (Plan 3.5): Guide, Spielen, Rand und Fehler geben über Pads.pulse einen kurzen Impuls
## (25–60 ms, nur mit dem Controller, Schalter controller.vibration) – auch bei ausgeschalteten Klängen.

const Klang := preload("res://src/core/klang.gd")
const MenuMusik := preload("res://src/core/menu_musik.gd")
const START := preload("res://assets/sounds/start.wav")

const RATE := 44100
const DIR := "res://assets/sounds"
var _streams := {}
## Weitere Fassungen je Klang (name → [AudioStream, …], die erste ist _streams[name]) und die zuletzt gespielte.
var _fassungen := {}
var _letzte_fassung := {}
## Klänge, deren Dateien keine eigene Staffelung tragen (Glas, eigene): mit den alten Stärken (GAIN).
var _alt := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_move := 0
var _streak := 0
var _panners: Array[AudioEffectPanner] = []
var _klang_von := {}             # Spieler → Name des Klangs, den er spielt
var _letzte_eingabe := 0         # ms
var _rampe_ab := -1              # ms der ersten Eingabe nach langer Ruhe (−1: keine)
var _richtung := ""              # zuletzt LB/LT ("left") oder RB/RT ("right")
var _richtung_ms := -100000
## Die Menümusik (eigener Knoten, eigene Leitung).
var musik: MenuMusik


func _ready() -> void:
	# Eigene Leitung für die Menüklänge mit Begrenzer: gestapelte Klänge werden nie zu laut.
	if AudioServer.get_bus_index("UI") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "UI")
		AudioServer.set_bus_send(idx, "Master")
		# Höhen sanft abrunden: das Klicken wird weicher und weniger spitz, ohne dumpf zu wirken.
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 5200.0
		lp.resonance = 0.5
		AudioServer.add_bus_effect(idx, lp)
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -3.0
		AudioServer.add_bus_effect(idx, lim)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = _pan_bus(i)
		add_child(p)
		_players.append(p)
	musik = MenuMusik.new()
	musik.name = "Musik"
	add_child(musik)
	_build()
	# Anderer Klangsatz: neu laden.
	Config.changed.connect(func(key: String) -> void:
		if key == "theme.sound_set":
			_build()
	)
	# Jede Eingabe, bevor Nav sie verbraucht (Ruhe, Richtung des Bereichswechsels).
	get_tree().root.window_input.connect(_on_eingabe)


func _on_eingabe(e: InputEvent) -> void:
	if not Klang.ist_eingabe(e):
		return
	var now := Time.get_ticks_msec()
	if now - _letzte_eingabe > Klang.RUHE_MS:
		_rampe_ab = now
	_letzte_eingabe = now
	for a in [["uz_lb", "left"], ["uz_lt", "left"], ["uz_rb", "right"], ["uz_rt", "right"]]:
		if InputMap.has_action(a[0]) and e.is_action_pressed(a[0]):
			_richtung = a[1]
			_richtung_ms = now


## Leitung „UI_P<i>“ mit Panorama, die in „UI“ mündet (Begrenzer und Tiefpass bleiben gemeinsam).
func _pan_bus(i: int) -> String:
	var name := "UI_P%d" % i
	var idx := AudioServer.get_bus_index(name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "UI")
		AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
	_panners.append(AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner)
	return name


## Wie laut jeder Klang im Verhältnis steht – nur für Klänge, deren Dateien alle ähnlich laut sind
## (Glas, eigene). Die erzeugten Sätze (Klang.SAETZE_GESTAFFELT) tragen ihre Staffelung
## selbst (tools/synth_tick.py und tools/synth_klang2.py, jeweils --pruefen).
const GAIN := { "move": 0.32, "tick": 0.28, "bump": 0.4, "tab": 0.5, "select": 0.7, "back": 0.6,
	"open": 0.65, "toggle_on": 0.6, "toggle_off": 0.55, "guide": 0.8, "guide_close": 0.65 }
## Rang: Der spätere Klang desselben Drucks ersetzt die früheren, wenn er mindestens so wichtig ist
## (Klang.ein_druck) – „tab“ statt „move“ beim Reiterwechsel, „open“ statt „select“ beim Öffnen,
## ein Fehler statt „Menü auf“. Unwichtigere bleiben still.
const PRIO := { "move": 0, "tick": 0, "bump": 1, "tab": 2, "select": 3, "back": 3, "open": 4,
	"toggle_on": 3, "toggle_off": 3, "guide_close": 4, "guide": 5, "notify": 5, "error": 6,
	"shutter": 6, "launch": 7, "achievement": 7, "unlock": 7, "unlock_rare": 7, "unlock_retro": 7, "boot": 9, "power_off": 9,
	"setup_step": 3, "setup_found": 4, "setup_done": 7, "swell": 6 }
## Impulse am Controller (Pads.PULSES_UI): nur wo etwas körperlich passiert.
const HAPTIK := { "guide": "guide", "launch": "auswahl", "bump": "rand", "error": "fehler" }
var _recent: Array = []          # [ms, Rang, Name, Spieler, Bild]
var _last_bump := 0


## at: das Element, zu dem der Klang gehört (sonst die Auswahl); dir: Richtung eines Anschlags
## oder eines Bereichswechsels ("left"/"right"; fehlt sie, gilt die zuletzt gedrückte Schultertaste).
func play(name: String, pitch := 1.0, at: Control = null, dir := "") -> void:
	_haptik(name)
	# Die Menümusik macht Platz: beim Spielstart sofort, beim Startbild und beim Ausschalten so
	# lange, wie deren eigener Klang läuft.
	if musik and name in ["launch", "boot", "power_off"]:
		musik.ducken(0.0 if name == "launch" else length(name) + 0.3)
	if not Config.get_value("theme.sounds", true):
		return
	var t0 := Time.get_ticks_msec()
	var bild := Engine.get_process_frames()
	var pr: int = PRIO.get(name, 3)
	_recent = _recent.filter(func(e): return Klang.gleicher_druck(t0 - int(e[0]), bild - int(e[4])))
	var druck := Klang.ein_druck(_recent.map(func(e): return [e[1], e[2]]), name, pr)
	if not bool(druck.spielen):
		return
	var extra_db := 0.0
	if name == "move" or name == "tick":
		var b := Klang.bewegen(t0 - _last_move, _streak)
		if not bool(b.ok):
			return
		_last_move = t0
		# Beim schnellen Blättern (Halten) werden die Tupfer leiser statt lauter.
		_streak = int(b.reihe)
		extra_db += float(b.db)
	elif name == "bump":
		# Am Rand festgehalten: nicht bei jeder Wiederholung anschlagen.
		if t0 - _last_bump < 280:
			return
		_last_bump = t0
	var s: AudioStream = _fassung(name)
	if s == null:
		return
	for i in druck.ersetzen:
		_leise(_recent[i][3])
	if name == "move" or name == "tick":
		# Bewegen schneidet seinen eigenen Nachklang ab (Glas und der Raum der Handpan sind länger als der Takt).
		for q in _players:
			if q.playing and str(_klang_von.get(q, "")) in ["move", "tick"]:
				_leise(q)
	var p := _spieler()
	p.stream = s
	# Bewegen und Regler klingen nie ganz gleich, das ermüdet beim Blättern nicht.
	if pitch == 1.0 and (name == "move" or name == "tick"):
		var z := Klang.zufall(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		pitch = z.x
		extra_db += z.y
	var gain: float = GAIN.get(name, 1.0) if _alt.has(name) else 1.0
	var lage := _lage(at)
	var pan := 0.0
	if bool(Config.get_value("theme.sound_space", true)):
		if lage.size() == 3:
			pan = Klang.pan_for(lage[0], 1.0, Klang.RAUM_STD)
			var k := Klang.kontext(name, lage[1], dir, bool(lage[2]))
			pitch *= k.x
			gain *= k.y
		if name == "tab":
			var tp: Variant = Klang.tab_pan(dir if dir != "" else (_richtung if t0 - _richtung_ms <= Klang.RICHTUNG_MS else ""))
			if tp != null:
				pan = float(tp)
	extra_db += Klang.zusatz_db(name, int(Time.get_datetime_dict_from_system().hour), t0 - _letzte_eingabe,
			t0 - _rampe_ab if _rampe_ab >= 0 else -1, Launcher.in_game and not Launcher.guide_open)
	_panners[_players.find(p)].pan = pan
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(clampf(float(Config.get_value("theme.sound_volume", 0.6)), 0.0, 1.0) * 0.75 * gain + 0.0001) + extra_db
	p.play()
	_recent.append([t0, pr, name, p, bild])
	_klang_von[p] = name
	last_player = p


## Startklang der Startanimation „U-Band“ (boot.gd, assets/sounds/start.wav aus tools/synth_start.py):
## ein eigener, langer Klang im Takt des Bilds, gleich in jedem Klangsatz. Wie play(): nur mit
## eingeschalteten Klängen, in der gewählten Lautstärke (abends leiser), die Menümusik macht Platz.
func play_start() -> void:
	if musik:
		musik.ducken(START.get_length() + 0.3)
	if not Config.get_value("theme.sounds", true):
		return
	var t0 := Time.get_ticks_msec()
	var p := _spieler()
	p.stream = START
	_panners[_players.find(p)].pan = 0.0
	p.pitch_scale = 1.0
	p.volume_db = linear_to_db(clampf(float(Config.get_value("theme.sound_volume", 0.6)), 0.0, 1.0) * 0.75 + 0.0001) \
		+ Klang.zusatz_db("boot", int(Time.get_datetime_dict_from_system().hour), t0 - _letzte_eingabe, -1, false)
	p.play()
	_klang_von[p] = "start"
	last_player = p


## Der Spieler für den nächsten Klang, ab _next reihum: am liebsten ein freier, damit kein Nachklang (Guide,
## Start, die Handpan) abgeschnitten wird; sonst einer, der schon verstummt ist (_leise: Bewegen schneidet den
## eigenen Nachklang ab, der Spieler läuft still bis zum Ende der Datei); sonst der, dessen Klang am weitesten
## verklungen ist (größter Anteil seiner Länge gespielt) – nie ohne Not ein Klang, der gerade erst beginnt.
func _spieler() -> AudioStreamPlayer:
	var wahl := _next
	var bester := -1.0
	for i in _players.size():
		var k := (_next + i) % _players.size()
		var q := _players[k]
		var wert := 3.0
		if q.playing:
			wert = 2.0
			if q.volume_db > -79.0:
				var lang := q.stream.get_length() if q.stream != null else 0.0
				wert = clampf(q.get_playback_position() / lang, 0.0, 1.0) if lang > 0.0 else 1.0
		if wert > bester:
			bester = wert
			wahl = k
	_next = (wahl + 1) % _players.size()
	return _players[wahl]


## Einen Klang ohne Knacken verstummen lassen (die Lautstärke gleitet über einen Mischpuffer).
func _leise(p: Variant) -> void:
	if p is AudioStreamPlayer and is_instance_valid(p) and (p as AudioStreamPlayer).playing:
		(p as AudioStreamPlayer).volume_db = -80.0


## Impuls am Controller zu diesem Klang (nur mit dem Controller in der Hand).
func _haptik(name: String) -> void:
	if HAPTIK.has(name) and str(Nav.device) == "pad":
		Pads.pulse(str(HAPTIK[name]))


const NAMES := ["move", "tick", "bump", "select", "back", "open", "toggle_on", "toggle_off", "tab", "guide", "guide_close", "notify", "error", "launch", "boot",
		"achievement", "shutter", "power_off", "unlock", "unlock_rare", "unlock_retro", "setup_step", "setup_found", "setup_done", "swell"]
## Sätze ohne eigene Klänge für die Einrichtung (Klang.EINRICHTUNG) nehmen dafür einen ihrer Grundklänge.
const ERSATZ_IM_SATZ := { "setup_step": "select", "setup_found": "toggle_on", "setup_done": "achievement", "swell": "open" }
const FASSUNGEN_MAX := 6


## Eine Fassung des Klangs (zufällig, nie dieselbe zweimal hintereinander) oder der Klang selbst.
func _fassung(name: String) -> AudioStream:
	var alle: Array = _fassungen.get(name, [])
	if alle.size() < 2:
		return _streams.get(name)
	var k := Klang.variante(alle.size(), int(_letzte_fassung.get(name, -1)), randf())
	_letzte_fassung[name] = k
	return alle[k]

## Lage eines Elements auf dem Bildschirm: [x, y] als Anteile (0 … 1) und ob es in einer Ebene
## liegt (Seitenleiste, Guide, Dialog). Leer, wenn es keins gibt (Klänge ohne Ort: mittig).
func _lage(at: Control) -> Array:
	var c := at
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		c = get_viewport().gui_get_focus_owner()
	if c == null or not c.is_inside_tree():
		return []
	var vs := c.get_viewport_rect().size
	if not (vs.x > 1.0 and vs.y > 1.0):
		return []
	var mid := c.get_global_rect().get_center()
	var in_layer := false
	for l in Nav.layers:
		if is_instance_valid(l) and l.is_ancestor_of(c):
			in_layer = true
			break
	return [clampf(mid.x / vs.x, 0.0, 1.0), clampf(mid.y / vs.y, 0.0, 1.0), in_layer]


## Der Spieler des zuletzt gestarteten Klangs (die Ausschalt-Animation wartet, bis er verklungen ist).
var last_player: AudioStreamPlayer


## Länge eines Klangs in Sekunden (0, wenn es ihn nicht gibt).
func length(name: String) -> float:
	var s: AudioStream = _streams.get(name)
	return s.get_length() if s != null else 0.0


## Der gewählte Klangsatz: "handpan" (Standard) oder eine andere Kennung aus Klang.SAETZE.
func sound_set() -> String:
	var v := str(Config.get_value("theme.sound_set", Klang.SATZ_STD))
	return v if Klang.SAETZE.any(func(o): return o[0] == v) else Klang.SATZ_STD


func _build() -> void:
	_streams.clear()
	_alt.clear()
	_fassungen.clear()
	_letzte_fassung.clear()
	var satz := sound_set()
	var ordner := Klang.satz_ordner(satz)
	var gestaffelt: bool = satz in Klang.SAETZE_GESTAFFELT
	for name in NAMES:
		var res := ordner.path_join(name + ".wav")
		if not ResourceLoader.exists(res):
			if name in Klang.EINRICHTUNG:
				continue        # unten: ein Grundklang desselben Satzes (ERSATZ_IM_SATZ)
			res = DIR.path_join(name + ".wav")
		elif not gestaffelt:
			_alt[name] = true
		if ResourceLoader.exists(res):
			_streams[name] = load(res)
			# Weitere Fassungen <name>_v2.wav, <name>_v3.wav … im Ordner des Satzes.
			var alle: Array = [_streams[name]]
			for k in range(2, FASSUNGEN_MAX + 1):
				var rv := ordner.path_join("%s_v%d.wav" % [name, k])
				if not ResourceLoader.exists(rv):
					break
				alle.append(load(rv))
			if alle.size() > 1:
				_fassungen[name] = alle
		elif Klang.PALETTE.has(name):
			_streams[name] = _ersatz(name)
	if not _streams.has("achievement"):
		_streams["achievement"] = _streams.get("notify")
	# Fehlen neuere Klänge (alte eigene Klangordner), greifen die Grundklänge.
	for alt in [["tick", "move"], ["bump", "back"], ["open", "select"], ["toggle_on", "select"], ["toggle_off", "back"], ["guide_close", "back"],
			["unlock", "achievement"], ["unlock_rare", "unlock"], ["unlock_retro", "unlock"]]:
		if not _streams.has(alt[0]):
			_streams[alt[0]] = _streams.get(alt[1])
	for name in ERSATZ_IM_SATZ:
		if not _streams.has(name):
			_streams[name] = _streams.get(ERSATZ_IM_SATZ[name])
			if _alt.has(ERSATZ_IM_SATZ[name]):
				_alt[name] = true
	_load_overrides()


## Ersatz, wenn eine Datei fehlt: derselbe Grundklang wie tools/synth_tick.py, etwas einfacher
## (ohne Raum und Filter). [Grundton Hz, Abklingen s, Zahl der Ticks, Abstand s, Pegel des
## zweiten Ticks dB, Beginn s].
const ERSATZ := {
	"move": [200.0, 0.0075, 1, 0.0, 0.0, 0.0], "tick": [260.0, 0.0052, 1, 0.0, 0.0, 0.0],
	"bump": [120.0, 0.013, 1, 0.0, 0.0, 0.0], "select": [170.0, 0.0085, 2, 0.018, -3.0, 0.0],
	"back": [150.0, 0.0145, 1, 0.0, 0.0, 0.0], "open": [170.0, 0.02, 2, 0.018, -3.0, 0.0],
	"toggle_on": [240.0, 0.0065, 1, 0.0, 0.0, 0.0], "toggle_off": [170.0, 0.0065, 1, 0.0, 0.0, 0.0],
	"tab": [190.0, 0.011, 1, 0.0, 0.0, 0.0], "guide": [110.0, 0.022, 1, 0.0, 0.0, 0.0],
	"guide_close": [140.0, 0.0135, 1, 0.0, 0.0, 0.0], "error": [110.0, 0.016, 2, 0.09, -4.0, 0.0],
	"notify": [230.0, 0.012, 2, 0.13, -0.5, 0.0], "launch": [170.0, 0.03, 2, 0.018, -3.0, 0.0],
	"boot": [90.0, 0.03, 1, 0.0, 0.0, 0.3], "power_off": [70.0, 0.034, 1, 0.0, 0.0, 0.62],
	"shutter": [300.0, 0.004, 2, 0.06, -1.5, 0.0], "achievement": [170.0, 0.0085, 2, 0.018, -3.0, 0.0],
}


func _ersatz(name: String) -> AudioStreamWAV:
	var p: Array = Klang.PALETTE.get(name, [80, -6.0, 90])
	var e: Array = ERSATZ.get(name, ERSATZ["select"])
	var spitze := db_to_linear(-17.0 + float(p[1]))
	return _make(float(p[0]) / 1000.0, func(t: float) -> float:
		var v := 0.0
		for k in int(e[2]):
			v += _tick_wert(t - float(e[5]) - k * float(e[3]), float(e[0]), float(e[1])) * (db_to_linear(float(e[4])) if k > 0 else 1.0)
		return v * spitze)


## Der Grundklang: Sinus mit kurzem Tonhöhenfall (f × 1,3 → f), Anstieg 1,5 ms, Abklingen tau,
## dazu ein Hauch Rauschen als Holz.
static func _tick_wert(t: float, f: float, tau: float) -> float:
	if t < 0.0:
		return 0.0
	var ph := TAU * f * (t + 0.3 * 0.0027 * (1.0 - exp(-t / 0.0027)))
	var a := (0.5 - 0.5 * cos(PI * t / 0.0015)) if t < 0.0015 else 1.0
	return sin(ph) * a * exp(-t / tau) * 0.88 + (randf() * 2.0 - 1.0) * exp(-t / 0.0012) * 0.12


func _make(length: float, fn: Callable) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := clampf(float(fn.call(t)), -1.0, 1.0)
		# kurzes Ausblenden am Ende gegen Knacken
		var tail := float(n - i) / RATE
		if tail < 0.01:
			v *= tail / 0.01
		data.encode_s16(i * 2, int(v * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _load_overrides() -> void:
	var dir := Config.path("sounds")
	if not DirAccess.dir_exists_absolute(dir):
		return
	for name in _streams.keys():
		var ogg := dir.path_join(name + ".ogg")
		var wav := dir.path_join(name + ".wav")
		if FileAccess.file_exists(ogg):
			var s := AudioStreamOggVorbis.load_from_file(ogg)
			if s:
				_streams[name] = s
				_alt[name] = true
				_fassungen.erase(name)
		elif FileAccess.file_exists(wav):
			var w := AudioStreamWAV.load_from_file(wav)
			if w:
				_streams[name] = w
				_alt[name] = true
				_fassungen.erase(name)
