extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Clip bearbeiten (Roadmap 137) – Editor öffnen, Ende verschieben, Zeitlupe,
## Text oben über die Bildschirmtastatur, Vorschau in Uzai, Speichern mit Fortschritt, neue Datei
## in der Galerie. Braucht FFmpeg: UZAI_TEST_FFMPEG (ein Linux-FFmpeg genügt; es wird als
## tools/ffmpeg/ffmpeg.exe in den Datenordner der Probe verlinkt). Aufruf siehe probe_base.gd.

const E := preload("res://src/core/clip_edit.gd")


func run() -> void:
	var ff := OS.get_environment("UZAI_TEST_FFMPEG")
	if ff == "" or not FileAccess.file_exists(ff):
		_check(false, "UZAI_TEST_FFMPEG fehlt")
		return
	var dir := Config.path("probe_clips")
	DirAccess.make_dir_recursive_absolute(dir)
	Config.set_value("capture.folder", dir)
	DirAccess.make_dir_recursive_absolute(Config.path("tools/ffmpeg"))
	OS.execute("ln", ["-sf", ff, Config.path("tools/ffmpeg/ffmpeg.exe")])
	var src := dir.path_join("Elden Ring 2026-10-22 18-30-00.mp4")
	OS.execute(ff, ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=size=1280x720:rate=60,trim=duration=12",
		"-f", "lavfi", "-i", "sine=frequency=330:duration=12", "-c:v", "libx264", "-preset", "veryfast", "-g", "120", "-pix_fmt", "yuv420p",
		"-c:a", "aac", "-shortest", src], [], true)
	Capture.changed.emit("files")
	main.open_captures()
	await wait(1.5)
	var cap: Node = Nav.top_layer()
	await shot("01_galerie", 0.5)
	var ed = load("res://src/ui/layers/capture_edit.gd").new()
	ed.file = src
	ed.main = main
	main.open_layer(ed)
	await wait(3.0)
	await shot("02_editor", 0.4)
	_check(Nav.focused() != null and str(Nav.focused().get_meta("uz_key", "")) == "edit:bar", "Zeitleiste gewählt")

	# Anfang nach rechts, dann Ende (A) nach links; LT fein.
	await press("right", 4)
	await press("a")
	await press("left", 3)
	await press("lt", 2)
	await shot("03_anfang_ende", 0.8)
	_check(float(ed._p.a) > 0.0 and float(ed._p.b) < 12.0, "Anfang und Ende verschoben (%s–%s)" % [E.time_text(float(ed._p.a)), E.time_text(float(ed._p.b))])

	# Zeitlupe 0,5×, dann ihren Bereich wählen.
	await _focus("edit:speed")
	await press("right")
	await _focus("edit:bar")
	await press("a")
	await press("right", 2)
	await shot("04_zeitlupe", 0.8)
	_check(E.has_slow(ed._p) and ed._sel == "sa", "Zeitlupe an, ihr Anfang gewählt")

	# Text oben über die Bildschirmtastatur.
	await _focus("edit:top")
	await press("a")
	await wait(0.6)
	await shot("05_tastatur", 0.2)
	var kb: Node = Nav.top_layer()
	if kb and kb.has_signal("done"):
		kb.set("text", "Erster Versuch!")
		kb.call("_finish")
	await wait(0.6)
	await shot("06_text_oben", 0.6)
	_check(str(ed._p.top) == "Erster Versuch!", "Text oben gesetzt")

	# Vorschau in Uzai (X auf der Zeitleiste).
	await _focus("edit:bar")
	await press("x")
	await shot("07_vorschau_wird_gebaut", 0.4)
	for i in 60:
		if ed._playing:
			break
		await wait(0.25)
	await shot("08_vorschau_laeuft", 1.2)
	_check(ed._playing, "Vorschau läuft")
	await press("x")
	await wait(0.4)

	# Speichern: Fortschritt, danach Mitteilung und neue Datei.
	await _focus("edit:save")
	await press("a")
	await shot("09_speichern", 0.3)
	for i in 120:
		if Capture.edit_job.is_empty():
			break
		await wait(0.25)
	await shot("10_gespeichert", 0.8)
	var made := Array(DirAccess.get_files_at(dir)).filter(func(f): return str(f).ends_with("(bearbeitet).mp4"))
	_check(made.size() == 1 and FileAccess.file_exists(src), "neue Datei, Original bleibt")
	await wait(1.0)
	await shot("11_galerie_neu", 1.2)
	if is_instance_valid(cap):
		await press("y")
		await shot("12_optionen", 0.6)


func _check(cond: bool, what: String) -> void:
	print("Probe ", "ok   " if cond else "FAIL ", what)


func _focus(key: String) -> void:
	var c := _find(Nav.top_layer(), func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == key)
	if c:
		Nav.focus(c)
	else:
		print("Probe: nicht gefunden: ", key)
	await wait(0.35)


func _find(n: Node, f: Callable) -> Control:
	if n == null:
		return null
	if n is Control and f.call(n):
		return n
	for ch in n.get_children():
		var r := _find(ch, f)
		if r:
			return r
	return null
