extends Node
## Spielklang: der Klang eines Spiels von iiDB (Soundbite) als leise Hintergrundmusik seiner
## Spielseite. Hängt als Kind an der Seite: kurz nach dem Öffnen holt er den Klang (aus dem Cache
## oder einmal von iiDB), blendet ihn weich ein und lässt ihn in Schleife laufen, solange die Seite
## offen ist. Die Menümusik schweigt solange (Klang.musik_soll). Er schweigt selbst, sobald etwas
## anderes Ton macht – Spielstart, Spiel, Video, eigene Musik – oder Uzai nicht vorn ist, und ist
## beim Verlassen der Seite sofort aus. Einstellung: library.spielklang (nur mit iiDB-Schlüssel).

const Iidb := preload("res://src/core/iidb.gd")
const Klang := preload("res://src/core/klang.gd")

const NAME := "Spielklang"
const WARTE_S := 0.7          ## erst, wenn die Seite steht (wer nur durchblättert, löst nichts aus)
const EIN_S := 1.4
const AUS_S := 0.25
const TAKT := 0.3
const ANTEIL := 0.45          ## Lautstärke gegenüber den Menüklängen

## Der Klang dieses Spiels ist geladen (die Seite zeigt dann ihre Pille).
signal bereit
## Der Klang läuft oder schweigt (an).
signal wechsel(an: bool)

## So viele Spielseiten lassen gerade ihren Klang laufen (für die Menümusik: dann schweigt sie).
static var aktiv := 0

var game: Dictionary = {}
var _player: AudioStreamPlayer
var _timer: Timer
var _tw: Tween
var _an := false              ## läuft bzw. blendet ein
var _zu := false              ## die Seite schließt: nie wieder anfangen


## An eine Spielseite hängen (einmal je Seite). seite: die Ebene; schließt sie, ist der Klang aus.
static func an(seite: Node, g: Dictionary) -> Node:
	if seite == null or seite.has_node(NAME) or g.is_empty():
		return null
	var k: Node = new()
	k.name = NAME
	k.game = g
	seite.add_child(k)
	if seite.has_signal("closed"):
		seite.connect("closed", k.aus)
	return k


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -60.0
	add_child(_player)
	_timer = Timer.new()
	_timer.wait_time = TAKT
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_holen()


func _exit_tree() -> void:
	_zaehlen(false)


## Was gerade gilt – für Klang.spielklang_soll.
func zustand() -> Dictionary:
	var musik := bool(Music.now.get("playing", false))
	if not musik and Music.local and Music.local.has_method("playing"):
		musik = bool(Music.local.playing())
	return {
		"an": bool(Config.get_value("library.spielklang", true)) and Media.iidb.verbunden(),
		"laut": float(Config.get_value("theme.sound_volume", 0.6)) > 0.001,
		"spiel": Launcher.in_game, "startet": Launcher.is_starting(), "video": Video.active, "musik": musik,
		"vorn": get_tree().root.has_focus() or not Config.is_windows(),
	}


func _holen() -> void:
	await get_tree().create_timer(WARTE_S).timeout
	if _zu or not is_inside_tree() or not Klang.spielklang_soll(zustand()):
		return
	var pfad: String = await Media.iidb.klang_datei(game)
	if _zu or not is_inside_tree() or pfad == "":
		return
	var strom := Iidb.klang_strom(pfad)
	if strom == null:
		return
	_player.stream = strom
	bereit.emit()
	_timer.start()
	_tick()


## Läuft er gerade?
func laeuft() -> bool:
	return _an


## Läuft, solange nichts anderes Ton macht; sonst weich aus und später (Seite noch offen) wieder ein.
func _tick() -> void:
	if _zu or _player.stream == null:
		return
	var soll := Klang.spielklang_soll(zustand())
	if soll and not _an:
		_an = true
		_zaehlen(true)
		Sfx.musik.ducken()
		_player.volume_db = -60.0
		_player.play()
		_blenden(_ziel_db(), EIN_S)
	elif not soll and _an:
		_an = false
		_zaehlen(false)
		_blenden(-60.0, AUS_S, true)
	elif _an and (_tw == null or not _tw.is_running()):
		_player.volume_db = _ziel_db()


func _ziel_db() -> float:
	return linear_to_db(clampf(float(Config.get_value("theme.sound_volume", 0.6)), 0.0, 1.0) * ANTEIL + 0.0001)


## Die Seite geht: sofort aus (ein kurzes Ausblenden statt eines Knackens) und nie wieder an.
func aus() -> void:
	_zu = true
	if is_instance_valid(_timer):
		_timer.stop()
	if _an:
		_an = false
		_zaehlen(false)
		_blenden(-60.0, AUS_S, true)


func _blenden(db: float, sek: float, danach_halt := false) -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_player, "volume_db", db, sek).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if danach_halt:
		_tw.tween_callback(func() -> void:
			if not _an:
				_player.stop()
		)


var _gezaehlt := false


func _zaehlen(an_: bool) -> void:
	if an_ == _gezaehlt:
		return
	_gezaehlt = an_
	aktiv = maxi(0, aktiv + (1 if an_ else -1))
	wechsel.emit(an_)
