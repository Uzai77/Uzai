extends Node
## Lautstärkemixer und Mikro stumm (Punkte 22 und 12): Antworten des Helfers lesen, Zeilen bauen
## und zuordnen, Schritte, Mixer-Zeile, Demo-Ablauf. Aufruf: godot --headless --path . res://tests/logic_mixer.tscn

const MixerS := preload("res://src/core/mixer.gd")
const MixRow := preload("res://src/ui/components/mix_row.gd")
const IconsS := preload("res://src/core/icons.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_parse()
	_rows()
	_steps()
	_mic()
	await _row()
	_demo()
	_helper()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


static func _reply(json: String, ok := true) -> Dictionary:
	return { "ok": ok, "result": { "json": json } }


func _parse() -> void:
	print("Antworten des Helfers")
	var d := MixerS.parse_list(_reply('{"found":true,"master":{"level":62,"mute":false,"device":"TV"},"apps":[{"pid":900,"name":"Spotify","desc":"Spotify","level":140,"mute":false,"game":false,"active":true},{"pid":3,"name":"x"},"kaputt"]}'))
	check(bool(d.found) and int(d.master.level) == 62 and str(d.master.device) == "TV", "Gesamtlautstärke gelesen")
	check((d.apps as Array).size() == 1, "nur gültige Programme (Nummer über 4, keine Fremdwerte)")
	check(int(d.apps[0].level) == 100 and str(d.apps[0].name) == "spotify", "Pegel begrenzt, Name klein")
	var mn := MixerS.parse_list(_reply('{"found":true,"master":{"level":null,"mute":null,"device":null},"apps":[{"pid":900,"name":null,"desc":null,"level":null,"mute":null,"game":null,"active":null}]}'))
	check(bool(mn.found) and int(mn.master.level) == 0 and (mn.apps as Array).size() == 1 and int(mn.apps[0].level) == 100 and not bool(mn.apps[0].mute),
			"Helfer-Antwort mit null: Ersatzwerte statt Abbruch")
	check(not bool(MixerS.parse_list(_reply('{"found":false,"timeout":true}')).found) and bool(MixerS.parse_list(_reply('{"found":false,"timeout":true}')).error),
			"Zeitüberschreitung: Fehler")
	check(not bool(MixerS.parse_list(_reply('{"found":false}')).error), "nichts gefunden: kein Fehler")
	check(bool(MixerS.parse_list({ "ok": false, "error": "nur unter Windows" }).error), "ohne Helfer: Fehler")
	check(bool(MixerS.parse_list(_reply('nicht json')).error), "kaputte Antwort: Fehler")
	check((MixerS.parse_list(_reply('{"found":true,"master":null,"apps":[]}')).master as Dictionary).is_empty(), "ohne Wiedergabegerät: keine Gesamt-Zeile")
	var s := MixerS.parse_set(_reply('{"found":true,"level":45,"mute":true,"sessions":2}'))
	check(bool(s.found) and int(s.level) == 45 and bool(s.mute), "Pegel gesetzt: echter Stand")
	check(not bool(MixerS.parse_set(_reply('{"found":false}')).found), "Programm weg: nicht gefunden")
	var m := MixerS.parse_mic(_reply('{"found":true,"mute":true,"name":" Headset-Mikrofon "}'))
	check(bool(m.found) and bool(m.mute) and str(m.name) == "Headset-Mikrofon", "Mikrofon gelesen")
	check(not bool(MixerS.parse_mic(_reply('{"found":false}')).found), "kein Mikrofon")
	var ga := MixerS.game_args(1234, "D:/Spiele/Elden Ring/", 77)
	check(ga.pids == [1234] and str(ga.dir) == "D:\\Spiele\\Elden Ring\\" and int(ga.hwnd) == 77, "Spiel: Prozess, Ordner, Fenster")
	check(MixerS.game_args(0, " ", 0).is_empty(), "ohne Spiel: nichts")


func _rows() -> void:
	print("Zeilen")
	var c := { "uzai_pid": 100, "video_pid": 200, "music_keys": ["spotify"], "music_app": "", "game": "Elden Ring" }
	var apps := [
		{ "pid": 500, "name": "zoom", "desc": "Zoom Meetings", "level": 80, "mute": false },
		{ "pid": 300, "name": "discord", "desc": "Discord", "level": 60, "mute": true },
		{ "pid": 301, "name": "discord", "desc": "Discord", "level": 90, "mute": false },
		{ "pid": 400, "name": "msedge", "desc": "Microsoft Edge", "level": 50, "mute": true },
		{ "pid": 401, "name": "msedge", "desc": "Microsoft Edge", "level": 40, "mute": true },
		{ "pid": 100, "name": "uzai", "desc": "", "level": 100, "mute": false },
		{ "pid": 600, "name": "eldenring", "desc": "ELDEN RING", "level": 100, "mute": false, "game": true },
		{ "pid": 601, "name": "start_protected_game", "desc": "", "level": 70, "mute": false, "game": true },
		{ "pid": 900, "name": "spotify", "desc": "Spotify", "level": 70, "mute": false },
		{ "pid": 200, "name": "mpv", "desc": "mpv", "level": 100, "mute": false },
		{ "pid": 700, "name": "audacity", "desc": "", "level": 30, "mute": false },
	]
	var rows := MixerS.rows({ "master": { "level": 62, "mute": false, "device": "Wohnzimmer-TV" }, "apps": apps }, c)
	var ids := rows.map(func(r: Dictionary) -> String: return str(r.id))
	check(ids == ["master", "spiel", "uzai", "musik", "discord", "video", "browser", "app:audacity", "app:zoom"],
			"Reihenfolge: Gesamt, Spiel, Uzai, Musik, Discord, Video, Browser, Rest nach Name (%s)" % str(ids))
	var by := {}
	for r in rows:
		by[str(r.id)] = r
	check(str(by.master.sub) == "Wohnzimmer-TV" and str(by.master.kind) == "master", "Gesamt mit Gerätename")
	check(str(by.spiel.title) == "Elden Ring" and by.spiel.pids == [600, 601] and int(by.spiel.level) == 100, "Spiel samt Kindprozess unter seinem Namen")
	check(by.discord.pids == [300, 301] and int(by.discord.level) == 90 and not bool(by.discord.mute),
			"mehrere Discord-Prozesse: eine Zeile, lautester Pegel, stumm nur wenn alle")
	check(bool(by.browser.mute) and str(by.browser.title) == "Edge", "Browser: alle stumm → stumm, kurzer Name")
	check(str(by["app:zoom"].title) == "Zoom Meetings" and str(by["app:audacity"].title) == "Audacity", "Rest: Beschreibung der Programmdatei, sonst Dateiname")
	check(str(by["app:zoom"].sub) == "zoom.exe", "Rest: Programmdatei darunter (gleich hohe Zeilen)")
	check(str(by.musik.title) == "Spotify" and str(by.video.title) == "Video", "Spotify und Uzais Video erkannt")
	for r in rows:
		check(IconsS.P.has(str(r.icon)), "%s: Symbol „%s“ gibt es" % [r.title, r.icon])
		check(not (r as Dictionary).has("active"), "%s: nur, was die Zeile braucht" % r.title)
	var c2 := c.duplicate()
	c2.music_keys = ["foobar2000", "spotify"]
	c2.music_app = "foobar2000"
	var r2 := MixerS.rows({ "apps": [{ "pid": 800, "name": "foobar2000", "desc": "foobar2000", "level": 50, "mute": false }] }, c2)
	check(r2.size() == 1 and str(r2[0].id) == "musik" and str(r2[0].title) == "foobar2000", "andere Musik-App über die Mediensitzung als Musik")
	var many: Array = []
	for i in 12:
		many.append({ "pid": 1000 + i, "name": "app%02d" % i, "desc": "", "level": 50, "mute": false })
	check(MixerS.rows({ "apps": many }, c).size() == MixerS.MAX_OTHERS, "höchstens %d weitere Programme" % MixerS.MAX_OTHERS)
	check(MixerS.rows({ "apps": [] }, c).is_empty(), "ohne Gerät und Programme: leer")
	c2.game = ""
	check(str(MixerS.classify({ "pid": 5, "name": "x", "game": true }, c2).title) == "Spiel", "Spiel ohne Namen")


func _steps() -> void:
	print("Schritte")
	check(MixerS.step_level(62, 1) == 65 and MixerS.step_level(62, -1) == 55, "auf Fünfer: 62 → 65 bzw. 55")
	check(MixerS.step_level(100, 1) == 100 and MixerS.step_level(0, -1) == 0, "an den Rändern fest")
	check(MixerS.step_level(3, -1) == 0, "knapp über null → null")
	check(MixerS.level_text(45, false) == "45 %" and MixerS.level_text(45, true) == "Stumm", "Wert rechts")


func _mic() -> void:
	print("Mikrofon")
	check(MixerS.mic_text(true, true, "Headset") == "Headset · auch in Discord", "Windows und Discord")
	check(MixerS.mic_text(true, false, "") == "Mikrofon von Windows", "nur Windows, ohne Namen")
	check(MixerS.mic_text(false, true, "") == "Nur in Discord", "ohne Helfer: nur Discord")


func _row() -> void:
	print("Mixer-Zeile")
	var row = MixRow.new()
	row.setup("slider", "Spiel", "", 0.6)
	add_child(row)
	await get_tree().process_frame
	var got: Array = []
	row.mute_toggled.connect(func(on: bool) -> void: got.append(on))
	var vals: Array = []
	row.changed.connect(func(v: Variant) -> void: vals.append(roundi(float(v) * 100.0)))
	row.nav_lr(1)
	check(vals == [65], "rechts: 5 lauter")
	row.activate()
	check(row.muted and got == [true] and row._full_text() == "Stumm" and row.track_dim, "A: stumm, „Stumm“, Schiene leise")
	check(str(row.get_meta("uz_hint_a")) == "Ton an", "Hinweis wechselt zu „Ton an“")
	row.nav_lr(1)
	check(not row.muted and got == [true, false] and vals == [65], "rechts hebt Stumm erst auf, Pegel bleibt")
	row.nav_lr(-1)
	check(vals == [65, 60], "links: 5 leiser")
	row.show_level(30, true)
	check(row.muted and roundi(float(row.value) * 100.0) == 30 and got.size() == 2, "Stand vom Helfer ohne Signal")
	row.queue_free()


func _demo() -> void:
	print("Demo-Ablauf (ohne Windows)")
	var was := Library.demo
	Library.demo = true
	var seen: Array = []
	var cb := func(id: String, level: int, mute: bool) -> void: seen.append([id, level, mute])
	Mixer.row_changed.connect(cb)
	var row := { "id": "discord", "kind": "app", "pids": [4300, 4301] }
	Mixer.set_level(row, 40)
	Mixer.set_mute(row, true)
	Mixer.set_level(row, 55, true)
	check(seen == [["discord", 40, false], ["discord", 40, true], ["discord", 55, false]], "jeder Schritt mit echtem Stand zurück (%s)" % str(seen))
	check(not Mixer.pending("discord"), "nichts mehr offen")
	seen.clear()
	Mixer.set_mute({ "id": "musik", "kind": "app", "pids": [4200], "level": 70, "mute": false }, true)
	check(seen == [["musik", 70, true]], "stumm behält den Pegel der Zeile")
	var mics: Array = []
	var mcb := func(on: bool) -> void: mics.append(on)
	Mixer.mic_changed.connect(mcb)
	var before: bool = Mixer.mic_muted
	Mixer.toggle_mic()
	check(Mixer.mic_muted != before and mics == [not before], "Mikro mit einem Druck umgeschaltet")
	Mixer.toggle_mic()
	check(Mixer.mic_muted == before and mics.size() == 2, "und wieder zurück")
	Mixer.mic_changed.disconnect(mcb)
	Mixer.row_changed.disconnect(cb)
	Library.demo = was


func _helper() -> void:
	print("Helfer")
	var src := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	for cmd in ["mixer", "mixer-set", "master-set", "mic"]:
		check(src.contains("        '%s' {" % cmd), "fester Befehl „%s“" % cmd)
		check(cmd in Helper.FAST, "„%s“ über den schnellen Weg" % cmd)
	check(src.contains("(Get-Num $a.level 100)") and src.contains("(Get-Num $a.mute 1)"), "Pegel und Stumm nur als begrenzte Zahlen")
	var i := src.find("        'mixer-set' {")
	var line := src.substr(i, src.find("\n", i) - i)
	check(not line.contains("Invoke-") and not line.contains("Start-") and not line.contains("iex"), "mixer-set führt nichts aus")
