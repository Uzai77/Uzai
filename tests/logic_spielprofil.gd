extends Node
## Spiel-Profile (Roadmap 18, 43): Prüfen fremder Werte, Vorlage und Spiel zusammen, Texte,
## Antworten des Helfers, Zurückstellen (auch nach einem Absturz), vorübergehende Einstellungen,
## Lossless aus der Vorlage und dass Profile beim Einlesen bleiben.
## Aufruf: godot --headless --path . res://tests/logic_spielprofil.tscn

const GameProfile := preload("res://src/core/game_profile.gd")
const ProfileRun := preload("res://src/core/profile_run.gd")

const DEV_A := "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a001}"
const DEV_B := "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a002}"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Prüfen")
	var p := GameProfile.clean({
		"display": { "w": 1920, "h": 1080, "hz": 60, "extra": "x" }, "hdr": "an", "volume": 73.0,
		"audio": { "id": DEV_A, "name": "  Fernseher  " }, "deadzone": 0.93, "repeat_rate": 0.1,
		"actions": ["quiet", "rm -rf", "mic_mute", "quiet"], "cmd": "calc.exe", "lossless": "an",
	})
	check(p.display == { "w": 1920, "h": 1080, "hz": 60 }, "Auflösung nur mit Breite, Höhe, Hz")
	check(p.hdr == "an" and p.volume == 70 and p.audio.name == "Fernseher", "HDR, Lautstärke in 10er-Schritten, Gerätename getrimmt")
	check(is_equal_approx(float(p.deadzone), 0.8) and is_equal_approx(float(p.repeat_rate), 0.1), "Controller-Werte im Bereich der Feineinstellung")
	check(p.actions == ["mic_mute", "quiet"], "nur eingebaute Aktionen, ohne doppelte")
	check(not p.has("cmd") and not p.has("lossless"), "Unbekanntes fällt weg; Lossless nur in der Vorlage")
	check(GameProfile.clean({ "lossless": "an" }, true).lossless == "an", "Vorlage kennt Lossless")
	var bad := GameProfile.clean({ "display": { "w": 99999, "h": 1080, "hz": 60 }, "hdr": "vielleicht",
		"audio": { "id": DEV_A + "\" & calc", "name": "x" }, "volume": "laut", "actions": "mic_mute" })
	check(bad.is_empty(), "Unsinn, angehängte Befehle und falsche Typen: nichts")
	check(GameProfile.clean({ "hdr": "keep", "audio": "keep" }) == { "hdr": "keep", "audio": "keep" }, "„Nicht ändern“ am Spiel")
	check(GameProfile.clean({ "hdr": "keep" }, true).is_empty(), "in der Vorlage gibt es kein „Nicht ändern“")
	check(GameProfile.clean("kaputt").is_empty() and GameProfile.clean(null).is_empty(), "kein Wörterbuch: leer")

	print("Spiel und Vorlage")
	var tpl := GameProfile.clean({ "display": { "w": 3840, "h": 2160, "hz": 60 }, "hdr": "an", "volume": 50, "actions": ["quiet"], "lossless": "an" }, true)
	var own := GameProfile.clean({ "hdr": "keep", "volume": 80, "actions": [] })
	var eff := GameProfile.effective(own, tpl)
	check(eff.display.w == 3840 and not eff.has("hdr"), "aus der Vorlage; „Nicht ändern“ schlägt die Vorlage")
	check(eff.volume == 80 and not eff.has("actions"), "eigene Werte vor der Vorlage, leere Aktionen = keine")
	check(eff.lossless == "an", "Lossless aus der Vorlage")
	check(GameProfile.effective({}, {}).is_empty(), "ohne alles: nichts")
	var w := GameProfile.with_value(own, "volume", "")
	check(not w.has("volume") and own.has("volume"), "Wert weg (erbt wieder), Original unverändert")
	check(GameProfile.with_value({}, "display", { "w": 1, "h": 1, "hz": 1 }).is_empty(), "ungültiger neuer Wert wird nicht gesetzt")
	check(GameProfile.template_id({ "system": "ps2", "source": "rom" }) == "ps2" and GameProfile.template_id({ "source": "pc" }) == "pc",
			"Vorlage je System bzw. Laden")
	check(GameProfile.template_name("steam", {}) == "Steam" and GameProfile.template_name("ps2", { "short": "PS2" }) == "PS2", "Name der Vorlage")

	print("Texte")
	check(GameProfile.mode_text({ "w": 1920, "h": 1080, "hz": 120 }) == "1920 × 1080 · 120 Hz", "Auflösung als Text")
	var sum := GameProfile.summary(
			GameProfile.clean({ "display": { "w": 1920, "h": 1080, "hz": 60 }, "hdr": "an", "audio": { "id": DEV_A, "name": "TV" }, "volume": 40, "deadzone": 0.3,
			"repeat_delay": 0.3 }), 3)
	check(sum == "1920 × 1080 · 60 Hz, HDR an, TV, 2 weitere", "Kurzfassung: drei und der Rest gezählt (%s)" % sum)
	check(GameProfile.summary({}) == "" and GameProfile.summary({ "hdr": "keep" }) == "", "leer bzw. nur „Nicht ändern“: kein Text")
	check(GameProfile.pad_text("deadzone", 0.35) == "0,35" and GameProfile.pad_text("repeat_delay", 0.25) == "250 ms", "Controller-Werte als Text")

	print("Antworten des Helfers")
	var modes := { "ok": true, "result": { "json": JSON.stringify({ "device": "\\\\.\\DISPLAY1", "w": 1920, "h": 1080, "hz": 60, "hdr": "moeglich",
		"modes": [{ "w": 1280, "h": 720, "hz": 60 }, { "w": 1920, "h": 1080, "hz": 60 }, { "w": 1920, "h": 1080, "hz": 120 }, { "w": 1920, "h": 1080, "hz": 60 },
			{ "w": 10, "h": 10, "hz": 60 }, "x"] }) } }
	var info := GameProfile.parse_modes(modes)
	check(info.device == "\\\\.\\DISPLAY1" and info.hdr == "moeglich" and info.w == 1920, "Gerät, jetziger Modus, HDR")
	check(info.modes.size() == 3 and info.modes[0] == { "w": 1920, "h": 1080, "hz": 120 } and info.modes[2].w == 1280,
			"Modi: ohne doppelte und Unsinn, groß und schnell zuerst")
	var evil := { "ok": true, "result": { "json": JSON.stringify({ "device": "\\\\.\\DISPLAY1\n; calc", "modes": [] }) } }
	check(GameProfile.parse_modes(evil).is_empty() and GameProfile.parse_modes({ "ok": false }).is_empty(), "falsches Gerät oder keine Antwort: nichts")
	check(GameProfile.valid_device("\\\\.\\DISPLAY12") and not GameProfile.valid_device("C:\\x") and not GameProfile.valid_device(7), "Gerätenamen streng")

	print("Zurückstellen")
	check(GameProfile.audio_back(DEV_B, DEV_B, DEV_A, [DEV_A, DEV_B]) == DEV_A, "Ton: zurück aufs vorige Gerät")
	check(GameProfile.audio_back(DEV_A, DEV_B, DEV_A, [DEV_A, DEV_B]) == "", "selbst zurückgestellt: nichts tun")
	check(GameProfile.audio_back("{x}", DEV_B, DEV_A, [DEV_A, DEV_B]) == "", "währenddessen anderes Gerät gewählt: bleibt")
	check(GameProfile.audio_back(DEV_B, DEV_B, DEV_A, [DEV_B]) == "", "voriges Gerät abgesteckt: bleibt")
	var pend := GameProfile.clean_pending({ "display": "\\\\.\\DISPLAY2", "hdr": { "device": "\\\\.\\DISPLAY2", "before": "moeglich", "set": "x" },
		"audio": { "before": DEV_A, "set": DEV_B }, "mic": true, "discord": "online", "run": "calc.exe" })
	check(pend.display == "\\\\.\\DISPLAY2" and pend.hdr.before == "moeglich" and pend.hdr.set == "an", "gemerkter Stand: Bildschirm, HDR")
	check(pend.audio.before == DEV_A and pend.mic == true and pend.discord == "online" and not pend.has("run"), "Ton, Mikrofon, Discord; Fremdes fällt weg")
	check(GameProfile.clean_pending({ "display": "C:\\Windows", "audio": { "before": "x", "set": DEV_B }, "mic": "ja", "discord": "dnd" }).is_empty(),
			"gemerkter Stand mit Unsinn: nichts")
	check(GameProfile.restored_text(pend) == "Bildschirm, HDR, Tonausgabe, Mikrofon, Discord-Status", "Text nach dem Zurückstellen")
	var path := Config.path("profile/test.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x".repeat(9000))
	f.close()
	check(ProfileRun.read_pending(path).is_empty(), "zu große Datei: nicht gelesen")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "mic": true }))
	f.close()
	check(ProfileRun.read_pending(path) == { "mic": true }, "Datei gelesen")
	DirAccess.remove_absolute(path)

	print("Vorlagen und vorübergehende Werte")
	GameProfile.set_template("ps2", { "volume": 60, "hdr": "keep", "lossless": "an" })
	check(GameProfile.template("ps2") == { "volume": 60, "lossless": "an" }, "Vorlage gespeichert (geprüft)")
	check(GameProfile.template_for({ "system": "ps2" }).volume == 60, "Vorlage für ein PS2-Spiel")
	Config.set_value("lossless.auto", "aus")
	check(Lossless._wants_auto({ "system": "ps2", "source": "rom" }), "Lossless aus der Vorlage")
	check(not Lossless._wants_auto({ "system": "ps2", "source": "rom", "lossless": "aus" }), "eigene Wahl des Spiels zählt zuerst")
	GameProfile.set_template("ps2", {})
	check(not (Config.get_value(GameProfile.TEMPLATES_KEY, {}) as Dictionary).has("ps2"), "leere Vorlage verschwindet")

	Config.set_value("controller.deadzone", 0.5)
	var run: Node = Launcher.profile
	Library.games.append({ "id": "test:prof", "title": "Profil-Test", "source": "pc", "system": "pc",
		"profile": { "deadzone": 0.3, "actions": ["quiet"] } })
	Library._reindex()
	await run.apply(Library.get_game("test:prof"))
	check(is_equal_approx(float(Config.get_value("controller.deadzone")), 0.3) and Config.get_value("notify.in_game") == false,
			"beim Start: Totzone und Pop-ups ruhig")
	check(is_equal_approx(float(Config.settings.controller.deadzone), 0.5), "gespeichert bleibt die eigene Einstellung")
	await run.restore()
	check(is_equal_approx(float(Config.get_value("controller.deadzone")), 0.5) and Config.get_value("notify.in_game", true) == true,
			"nach dem Spiel: wieder wie eingestellt")
	Config.set_temp("controller.deadzone", 0.3)
	Config.set_value("controller.deadzone", 0.45)
	check(not Config.has_temp("controller.deadzone") and is_equal_approx(float(Config.get_value("controller.deadzone")), 0.45),
			"selbst umgestellt: die eigene Wahl gilt")
	Config.set_value("controller.deadzone", 0.5)
	check(not FileAccess.file_exists(ProfileRun.pending_path()), "ohne Windows-Änderung kein gemerkter Stand")

	print("Zurückstellen, wenn der Helfer nicht antwortet")
	# Endete ein Spiel, während der Helfer neu startete, blieben Auflösung, HDR und Tonausgabe früher verstellt – und
	# der Merkzettel war gelöscht. Jetzt bleibt offen, was ohne Antwort blieb, und wird nachgeholt.
	check(Helper.ohne_antwort({ "ok": false, "error": Helper.KEINE_ANTWORT }) and Helper.ohne_antwort({ "ok": false, "error": "Zeitüberschreitung", "timeout": true }),
			"keine Antwort: Helfer nicht bereit oder Zeit abgelaufen")
	check(not Helper.ohne_antwort({ "ok": false, "error": "Windows lehnt ab" }) and not Helper.ohne_antwort({ "ok": true, "result": {} })
			and not Helper.ohne_antwort({}), "eine Absage oder ein Erfolg ist eine Antwort")
	var stand := { "display": "\\\\.\\DISPLAY1", "hdr": { "device": "\\\\.\\DISPLAY1", "before": "an", "set": "aus" },
		"audio": { "before": DEV_A, "set": DEV_B }, "mic": true, "discord": "online", "music": true }
	check(ProfileRun.offen_ohne_helfer(stand).keys() == ["display", "hdr", "audio", "mic"], "ohne Helfer bleibt offen, was Windows betrifft (nicht Discord, nicht Musik)")
	check(ProfileRun.gemerkt({}, { "display": "\\\\.\\DISPLAY1" }) == { "display": "\\\\.\\DISPLAY1" }, "Ausstehendes vom letzten Spiel steht in der Datei")
	check(ProfileRun.gemerkt({ "display": "\\\\.\\DISPLAY2", "music": true }, { "display": "\\\\.\\DISPLAY1", "mic": true })
			== { "display": "\\\\.\\DISPLAY2", "mic": true }, "das laufende Spiel geht vor, der Rest bleibt; Musik steht nie in der Datei")
	run._offen = { "display": "\\\\.\\DISPLAY1" }
	run._write_pending()
	check(ProfileRun.read_pending(ProfileRun.pending_path()) == { "display": "\\\\.\\DISPLAY1" }, "offen Gebliebenes übersteht einen Neustart von Uzai")
	run._offen = {}
	run._write_pending()
	check(not FileAccess.file_exists(ProfileRun.pending_path()), "erledigt: der Merkzettel ist weg")

	print("Bleibt erhalten")
	check("profile" in Library.USER_FIELDS, "„profile“ gehört zu den eigenen Feldern (Einlesen, Sicherung)")
	Library._merge([{ "id": "test:prof", "title": "Neu eingelesen", "source": "pc", "system": "pc", "profile": {} }], ["pc"])
	check((Library.get_game("test:prof").get("profile", {}) as Dictionary).has("deadzone"), "Einlesen überschreibt das Profil nicht")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
