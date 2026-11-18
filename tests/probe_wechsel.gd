extends "res://tests/probe_base.gd"
## Misst den ersten Wechsel in einen Bereich: Dauer des Aufrufs und jedes lange Bild danach.

var _t := 0
var _an := false
var _t0 := 0


func run() -> void:
	get_tree().process_frame.connect(_bild)
	var ziel := "shop"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-ziel="):
			ziel = a.substr(12)
	await wait(1.0)
	_an = true
	_t0 = Time.get_ticks_usec()
	print("MESS start pid=%d" % OS.get_process_id())
	if ziel == "zimmer":
		main.open_room(true)
	else:
		main.goto(ziel)
	print("MESS aufruf %.0f ms" % ((Time.get_ticks_usec() - _t0) / 1000.0))
	await wait(8.0)
	_an = false
	print("MESS ende")


func _bild() -> void:
	var t := Time.get_ticks_usec()
	if _an and _t > 0:
		var ms := (t - _t) / 1000.0
		if ms > 40.0:
			print("MESS bild +%.0f ms: %.0f ms, prozess %.0f ms" % [(t - _t0) / 1000.0, ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	_t = t
