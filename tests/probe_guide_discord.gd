extends "res://tests/probe_base.gd"
## Guide › Discord im Sprachkanal (ruhiger Aufbau): ohne Spiel, im Spiel, mit Video, „Kanal
## wechseln“; dazu Musik mit Songtext. Bilder: dc_*.png, musik_*.png.

const Lyrics := preload("res://src/core/lyrics.gd")


func _desc(f: Control) -> String:
	if f == null:
		return "<null>"
	return "%s«%s»" % [f.get_script().resource_path.get_file() if f.get_script() else f.get_class(),
			str(f.get_meta("uz_key", f.get("text") if "text" in f else ""))]


func _walk(tag: String) -> void:
	for i in 3:
		await press("down", 1, 0.2)
	print("DC %s unten: %s" % [tag, _desc(Nav.focused())])
	for i in 6:
		await press("right", 1, 0.15)
		print("DC %s rechts %d: %s" % [tag, i, _desc(Nav.focused())])


func run() -> void:
	main.toggle_guide("discord")
	await wait(1.2)
	await shot("dc_ohne_spiel", 0.3)
	await _walk("ohne Spiel")
	await shot("dc_ohne_spiel_leiste", 0.3)
	# Kanal wechseln: Auswahl mit den anderen Kanälen und „Anderer Server …“.
	for i in 6:
		if str(Nav.focused().get_meta("uz_key", "")) == "vb:switch":
			break
		await press("left", 1, 0.15)
	await press("a", 1, 0.8)
	await shot("dc_kanal_wechseln", 0.3)
	await press("b", 1, 0.5)
	await press("guide", 1, 0.8)
	# Im Spiel.
	Launcher.in_game = true
	Launcher.current = Library.get_game(Library.recent(1)[0].id)
	main.toggle_guide("discord")
	await wait(1.2)
	await shot("dc_im_spiel", 0.3)
	await _walk("im Spiel")
	main.discord_live = true
	main._guide._rebuild_soon()
	await wait(0.6)
	await shot("dc_live", 0.3)
	main.discord_live = false
	await press("guide", 1, 0.8)
	Launcher.in_game = false
	# Video läuft (Simulation): Übertragen im Discord- und im Video-Reiter.
	main.open_video([{ "id": "dQw4w9WgXcQ", "title": "Ein Video", "channel": "Kanal" }], 0, {})
	await wait(1.5)
	main.toggle_guide("discord")
	await wait(1.2)
	await shot("dc_video", 0.3)
	await _walk("Video")
	await press("lb", 1, 0.8)
	await shot("video_reiter", 0.3)
	await press("guide", 1, 0.8)
	Video.stop()
	await wait(1.0)
	# Musik mit Songtext (zeitgenaue Zeilen vorab in den Zwischenspeicher, ohne Netz).
	var now: Dictionary = Music.now
	var key := ("%s|%s" % [str(now.get("title", "")), str(now.get("artist", ""))]).to_lower()
	var lrc := ""
	for i in 40:
		lrc += "[%02d:%02d.00] %s\n" % [int(i * 5 / 60.0), (i * 5) % 60,
				["Durch die Stille zieht ein Ton", "Über Wasser, über Stein", "Wo die alten Lichter wohnen", "", "Gehen wir den Weg zurück"][i % 5]]
	Lyrics._cache[key] = Lyrics.parse(lrc, "")
	main.toggle_guide("musik")
	await wait(1.4)
	await shot("musik_songtext", 0.3)
	for i in 6:
		if str(Nav.focused().get_meta("uz_key", "")) == "m:lyrics":
			break
		await press("down" if i < 2 else "right", 1, 0.15)
	print("MU Fokus: ", _desc(Nav.focused()))
	await press("a", 1, 1.0)
	await shot("musik_songtext_blatt", 0.3)
	await press("b", 1, 0.5)
	await press("guide", 1, 0.6)
	# Ohne Songtext: kein Streifen, kein Knopf.
	Lyrics._cache[key] = { "state": "keine", "synced": [], "plain": PackedStringArray() }
	main.toggle_guide("musik")
	await wait(1.4)
	await shot("musik_ohne_songtext", 0.3)
