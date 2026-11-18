extends "res://tests/probe_base.gd"
## Messprobe „Unterbereiche“: Wie ruhig wechseln die Unterbereiche (LB/RB) im Shop und im Profil?
## Je Wechsel: block = so lange hing der Aufruf selbst (ms), bild = längstes Bild bis 0,8 s danach,
## skript = Rechenzeit der Skripte in diesem Bild, lang = Bilder über 50 ms. Unter xvfb ist alles
## langsamer; es zählt der Vergleich Shop – Profil.
##   UZAI_DATA=<leer> xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##       -- --demo --no-boot --uzai-script=res://tests/probe_unterbereiche.gd

var _anfaenge: Array = []
var _rechnen: Array = []


func _ready() -> void:
	get_tree().process_frame.connect(func() -> void:
		_anfaenge.append(Time.get_ticks_usec())
		_rechnen.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	super._ready()


func _messen(name: String, tat: Callable) -> Array:
	await wait(0.7)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var ab := _anfaenge.size() - 1
	await tat.call()
	var block := (Time.get_ticks_usec() - t0) / 1000.0
	await wait(0.8)
	var bild := 0.0
	var skript := 0.0
	var lang := 0
	for i in range(ab + 1, _anfaenge.size()):
		var ms := (int(_anfaenge[i]) - int(_anfaenge[i - 1])) / 1000.0
		if ms > bild:
			bild = ms
			skript = float(_rechnen[i])
		lang += 1 if ms > 50.0 else 0
	_anfaenge = _anfaenge.slice(_anfaenge.size() - 1)
	_rechnen = _rechnen.slice(_rechnen.size() - 1)
	print("UB %-28s block %6.1f ms  bild %6.1f ms  skript %6.1f ms  >50: %d" % [name, block, bild, skript, lang])
	return [block, bild]


func _runde(sec: String, runde: int) -> Array:
	main.goto(sec)
	await wait(2.5)
	var s: Node = main.sections.get(sec)
	var subs: Array = s.subtabs()
	var summe := [0.0, 0.0]
	for i in subs.size():
		var von := str(s.sub)
		var r: Array = await _messen("%s%d %s>" % [sec.left(4), runde, von.left(10)], func() -> void: main._step_sub(1))
		summe[0] = maxf(summe[0], r[0])
		summe[1] = maxf(summe[1], r[1])
	return summe


func run() -> void:
	await wait(3.0)
	for runde in 2:
		for sec in ["shop", "achievements"]:
			var m: Array = await _runde(sec, runde)
			print("UB MAX %s Runde %d: block %.1f ms, bild %.1f ms" % [sec, runde, m[0], m[1]])
