extends Node
## Spielzeit eines Kinderprofils (Roadmap 109): zählt, was über Uzai gespielt wird (je Kalendertag,
## kind.json im Ordner des Profils; die laufende Runde alle zwei Minuten), meldet sich zehn Minuten vor Schluss und am Ende freundlich –
## und fragt vor dem nächsten Start. Uzai erzwingt nichts: kein Spiel wird beendet, nichts an
## Windows verstellt. Mehr Zeit gibt es mit einer Eltern-PIN.

const Profiles := preload("res://src/core/profiles.gd")
const ProfilePin := preload("res://src/ui/layers/profile_pin.gd")

## So oft wird die laufende Runde gutgeschrieben (Sekunden): Stürzt Uzai mitten im Spiel ab oder wird beendet,
## fehlt höchstens so viel – früher zählte die ganze Runde dann nicht.
const FESTHALTEN_S := 120

const Main := preload("res://src/main.gd")
var main: Main
var _start_ms := 0                 ## Beginn der laufenden Runde (0 = keine)
var _gut := 0                      ## so viele Sekunden der laufenden Runde sind schon gutgeschrieben
var _warned := false
var _ended := false


func _ready() -> void:
	Launcher.started.connect(func(_g: Dictionary) -> void:
		_start_ms = Time.get_ticks_msec()
		_gut = 0
		_warned = false
		_ended = false
	)
	Launcher.ended.connect(func(_g: Dictionary, secs: int) -> void:
		if _start_ms > 0:
			_festhalten(secs if secs > 0 else _runde_s(), true)
		_start_ms = 0
		_gut = 0
	)
	var t := Timer.new()
	t.wait_time = 15.0
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)


## Sekunden seit Beginn der laufenden Runde.
func _runde_s() -> int:
	return int((Time.get_ticks_msec() - _start_ms) / 1000)


## Sekunden der laufenden Runde, die noch nicht gutgeschrieben sind.
func running_secs() -> int:
	return maxi(0, _runde_s() - _gut) if _start_ms > 0 and Launcher.in_game else 0


## Wie viele Sekunden jetzt gutzuschreiben sind: am Ende der Runde der ganze Rest, unterwegs erst, wenn
## FESTHALTEN_S zusammengekommen sind (nicht bei jedem Takt eine Datei schreiben).
static func faellig(runde_s: int, gut_s: int, ende: bool) -> int:
	var offen := maxi(0, runde_s - gut_s)
	return offen if ende or offen >= FESTHALTEN_S else 0


func _festhalten(runde_s: int, ende: bool) -> void:
	var s := faellig(runde_s, _gut, ende)
	if s > 0:
		Config.kid_time_add(s)
		_gut += s


func _tick() -> void:
	if not Config.is_kid() or not Launcher.in_game:
		return
	if _start_ms > 0:
		_festhalten(_runde_s(), false)
	hint(Config.kid_time_left(running_secs()))


## Hinweis zur verbleibenden Zeit (Sekunden; -1 = ohne Grenze): je einmal kurz vor Schluss und am Ende.
func hint(left: int) -> void:
	if left < 0:
		return
	if left == 0 and not _ended:
		_ended = true
		_warned = true
		Toasts.show_toast("Zeit für eine Pause", "Deine Spielzeit für heute ist um. Speichere am besten gleich – das Spiel bleibt offen, bis du es beendest.",
				"clock", { "ms": 12000 })
	elif left <= Profiles.LIMIT_WARN_S and not _warned:
		_warned = true
		Toasts.show_toast("Noch %d Minuten" % maxi(1, int(ceil(left / 60.0))), "Dann ist deine Spielzeit für heute um. Ein guter Moment, bald zu speichern.", "clock",
				{ "ms": 9000 })


## Vor einem Spielstart (main.launch): true = los. Über der Altersstufe nie; ist die Zeit um,
## fragt Uzai freundlich – mit Eltern-PIN gibt es 30 Minuten dazu.
func may_launch(g: Dictionary) -> bool:
	if not Config.is_kid():
		return true
	if Config.kid_hides(g):
		Toasts.show_toast("Nicht freigegeben", "Dieses Spiel ist für dein Profil nicht freigegeben.", "lock")
		return false
	if Config.kid_time_left() != 0:
		return true
	var answer := [""]
	var parents := Config.parent_ids()
	var buttons: Array = [["OK", func() -> void: answer[0] = "nein"]]
	if not parents.is_empty():
		buttons.append(["Eltern-PIN: 30 Minuten mehr", func() -> void: answer[0] = "pin"])
	else:
		buttons.append(["Trotzdem spielen", func() -> void: answer[0] = "ja"])
	var d: Control = main.open_dialog("Für heute ist Schluss", "Deine Spielzeit für heute ist um. Morgen geht es weiter – oder frag deine Eltern nach mehr Zeit.",
			buttons, "clock")
	await d.closed
	# Der Knopf ruft seine Handlung erst nach dem Schließen auf.
	await get_tree().process_frame
	if answer[0] == "ja":
		return true
	if answer[0] != "pin":
		return false
	var pin = ProfilePin.new()
	pin.mode = "parent"
	pin.reason = "30 Minuten mehr für heute."
	var ok := [false]
	pin.passed.connect(func() -> void: ok[0] = true)
	main.open_layer(pin)
	await pin.closed
	if ok[0]:
		Config.kid_time_bonus(30)
		Toasts.show_toast("30 Minuten mehr", "", "clock")
	return ok[0]
