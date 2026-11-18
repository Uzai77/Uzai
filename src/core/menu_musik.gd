extends Node
## Menümusik (Roadmap 99): ein ruhiger Loop (assets/musik, erzeugt mit tools/synth_musik.py),
## wählbar unter Einstellungen → Bild & Ton → Musikstück. Standardmäßig aus
## (Aussehen → „Menümusik“, 0 % = aus). Blendet aus, sobald etwas anderes Ton macht – Spielstart,
## Spiel, Video, Musik –, wenn Uzai nicht vorn ist und im leichten Modus; wieder ein erst, wenn
## alles eine Weile ruhig war, und dann dort, wo sie aufgehört hat. Entscheidung: Klang.musik_soll.

const Klang := preload("res://src/core/klang.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Spielklang := preload("res://src/core/spielklang.gd")

const BUS := "Menuemusik"
const TAKT := 0.3

var _player: AudioStreamPlayer
var _timer: Timer
var _stueck := ""          ## was gerade geladen ist ("" = nichts)
var _an := false           ## spielt bzw. blendet gerade ein
var _ruhig_seit := -1.0    ## seit wann (s) alles ruhig ist; -1 = nicht ruhig
var _halt_bis := 0.0       ## bis wann (s) sie still bleibt (Startbild, Ausschalten)
var _tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, "Master")
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.volume_db = -80.0
	add_child(_player)
	_timer = Timer.new()
	_timer.wait_time = TAKT
	_timer.timeout.connect(_tick)
	add_child(_timer)
	# Die anderen Dienste (Launcher, Video, Music) kommen erst nach Sfx in den Baum.
	_start.call_deferred()


func _start() -> void:
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("theme.music") or k == "display.light":
			_wach()
	)
	Video.started.connect(func(_v: Dictionary) -> void: ducken())
	_wach()


## Läuft der Takt nur, solange Musik an ist: ausgeschaltet kostet sie nichts.
func _wach() -> void:
	if not is_inside_tree():
		return
	var an := float(Config.get_value("theme.music", 0.0)) > 0.001
	if an and _timer.is_stopped():
		_timer.start()
	_tick()
	if not an:
		_timer.stop()


## Sofort leiser werden (Spielstart, Video): nicht erst auf den nächsten Takt warten.
## halten: so viele Sekunden still bleiben (Startbild mit eigenem Klang, Ausschalten).
func ducken(halten := 0.0) -> void:
	_ruhig_seit = -1.0
	_halt_bis = maxf(_halt_bis, Time.get_ticks_msec() / 1000.0 + halten)
	if _an:
		_aus()


## Was gerade Ton macht – für Klang.musik_soll.
func zustand() -> Dictionary:
	var musik := false
	if Music.now.get("playing", false):
		musik = true
	elif Music.local and Music.local.has_method("playing") and Music.local.playing():
		musik = true
	return {
		"an": float(Config.get_value("theme.music", 0.0)) > 0.001,
		"leicht": Leicht.active,
		"spiel": Launcher.in_game,
		"startet": Launcher.is_starting(),
		"video": Video.active,
		"musik": musik,
		"spielklang": Spielklang.aktiv > 0,
		"vorn": get_tree().root.has_focus() or not Config.is_windows(),
		"stueck": _quelle() != "",
	}


## Gerade gewähltes Stück (Kennung aus Klang.MUSIK).
func _quelle() -> String:
	return Klang.stueck(str(Config.get_value("theme.music_track", "theme")))


func _tick() -> void:
	var jetzt := Time.get_ticks_msec() / 1000.0
	var soll := Klang.musik_soll(zustand()) and jetzt >= _halt_bis
	if not soll:
		_ruhig_seit = -1.0
		if _an:
			_aus()
		return
	if _ruhig_seit < 0.0:
		_ruhig_seit = jetzt
	var q := _quelle()
	if q != _stueck:
		_laden(q)
	if _an:
		# Lautstärke folgt dem Regler gleich (ohne neues Einblenden).
		if _tw == null or not _tw.is_running():
			_player.volume_db = _ziel_db()
		return
	if jetzt - _ruhig_seit >= Klang.MUSIK_WARTE_S:
		_ein()


func _ziel_db() -> float:
	return Klang.musik_db(float(Config.get_value("theme.music", 0.0)))


func _laden(q: String) -> void:
	_stueck = q
	var s: AudioStream = null
	if Klang.MUSIK.has(q):
		var res := "%s/%s.ogg" % [Klang.MUSIK_DIR, q]
		if ResourceLoader.exists(res):
			s = load(res)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	var war_an := _an
	_player.stop()
	_player.stream = s
	_player.stream_paused = false
	_an = false
	if war_an and s:
		_ein()


func _ein() -> void:
	if _player.stream == null:
		return
	_an = true
	if _player.stream_paused:
		_player.stream_paused = false
	elif not _player.playing:
		_player.volume_db = -60.0
		_player.play()
	_blend(_ziel_db(), Klang.MUSIK_EIN_S)


func _aus() -> void:
	_an = false
	_blend(-60.0, Klang.MUSIK_AUS_S, true)


func _blend(db: float, sec: float, pause_after := false) -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_player, "volume_db", db, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if pause_after:
		_tw.tween_callback(func() -> void:
			if not _an and _player.playing:
				_player.stream_paused = true
		)


## Für Tests und Proben: spielt sie gerade (oder blendet ein)?
func spielt() -> bool:
	return _an
