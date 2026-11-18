extends Node
## Wrap-around in the selection (Nav, meta uz_umlauf – the Guide's bar: up at the top edge continues at
## the very bottom and vice versa), a state for the microphone (Mixer.mic_aus) and the log line for
## Steam's notification windows (src/core/steam_still.gd).
## Run: godot --headless --path . res://tests/logic_umlauf.tscn

const SteamStill := preload("res://src/core/steam_still.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _knopf(eltern: Control, text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.position = pos
	b.size = Vector2(140, 40)
	b.custom_minimum_size = Vector2(140, 40)
	eltern.add_child(b)
	return b


func _gewaehlt() -> String:
	var f := Nav.focused()
	return (f as Button).text if f is Button else "nichts"


func _ready() -> void:
	print("Umlauf")
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	add_child(root)
	var alt_scope := Nav.root_scope
	Nav.root_scope = root
	var kasten := Control.new()
	kasten.size = Vector2(620, 1080)
	kasten.set_meta("uz_umlauf", true)
	root.add_child(kasten)
	var oben := _knopf(kasten, "oben", Vector2(40, 60))
	var glocke := _knopf(kasten, "glocke", Vector2(400, 60))
	var mitte := _knopf(kasten, "mitte", Vector2(40, 300))
	var u1 := _knopf(kasten, "unten1", Vector2(40, 920))
	var u2 := _knopf(kasten, "unten2", Vector2(400, 920))
	var draussen := _knopf(root, "draussen", Vector2(900, 10))
	await get_tree().process_frame
	Nav.focus(oben, true)
	Nav.move("up")
	check(_gewaehlt() == "unten1", "hoch am oberen Rand: ganz unten weiter (%s)" % _gewaehlt())
	Nav.move("down")
	check(_gewaehlt() == "oben", "runter am unteren Rand: ganz oben weiter (%s)" % _gewaehlt())
	Nav.focus(glocke, true)
	Nav.move("up")
	check(_gewaehlt() == "unten2", "es geht zu dem, was waagerecht am nächsten liegt (%s)" % _gewaehlt())
	Nav.focus(u1, true)
	Nav.move("up")
	check(_gewaehlt() == "mitte", "von unten hoch geht es normal weiter (%s)" % _gewaehlt())
	Nav.focus(oben, true)
	Nav._wiederholt = true
	Nav.move("up")
	Nav._wiederholt = false
	check(_gewaehlt() == "oben", "wer die Richtung hält, bleibt am Rand stehen (%s)" % _gewaehlt())
	Nav.move("left")
	check(_gewaehlt() == "oben", "links und rechts laufen nicht um (%s)" % _gewaehlt())
	# Ohne das Merkmal gilt die alte Regel: was außerhalb höher liegt, zählt – und am Rand ist Schluss.
	kasten.remove_meta("uz_umlauf")
	Nav.focus(oben, true)
	Nav.move("up")
	check(_gewaehlt() == "draussen", "ohne Umlauf: wie bisher (%s)" % _gewaehlt())
	Nav.focus(u1, true)
	Nav.move("down")
	check(_gewaehlt() == "unten1", "ohne Umlauf: unten ist Schluss (%s)" % _gewaehlt())
	kasten.set_meta("uz_umlauf", true)
	# Eine lange, rollende Liste über einer festen Leiste: unten ist die Leiste, nicht die letzte Zeile der Liste.
	mitte.queue_free()
	var sc := ScrollContainer.new()
	sc.position = Vector2(40, 140)
	sc.size = Vector2(540, 700)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	kasten.add_child(sc)
	var vb := VBoxContainer.new()
	sc.add_child(vb)
	for i in 30:
		_knopf(vb, "zeile%d" % i, Vector2.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	Nav.focus(oben, true)
	Nav.move("up")
	check(_gewaehlt() == "unten1", "lange Liste: unten ist die feste Leiste (%s)" % _gewaehlt())
	Nav.move("up")
	check(_gewaehlt() == "zeile15", "darüber die letzte Zeile, die in der Liste zu sehen ist (%s)" % _gewaehlt())
	Nav.focus(u1, true)
	Nav.move("down")
	check(_gewaehlt() == "oben", "von der Leiste runter: nicht in hinausgerollte Zeilen, sondern ganz nach oben (%s)" % _gewaehlt())
	Nav.move("down")
	check(_gewaehlt() == "zeile0", "von oben runter in die erste Zeile (%s)" % _gewaehlt())
	# Ohne feste Leiste (andere Reiter): unten ist die letzte Zeile der Liste, auch wenn sie hinausgerollt ist.
	u1.queue_free()
	u2.queue_free()
	await get_tree().process_frame
	Nav.focus(oben, true)
	Nav.move("up")
	check(_gewaehlt() == "zeile29", "ohne Leiste: von oben hoch zur letzten Zeile der Liste (%s)" % _gewaehlt())
	Nav.move("down")
	check(_gewaehlt() == "oben", "und von dort runter wieder nach oben (%s)" % _gewaehlt())
	Nav.root_scope = alt_scope
	root.queue_free()
	var guide := FileAccess.get_file_as_string("res://src/ui/layers/guide.gd")
	check(guide.contains("_panel.set_meta(\"uz_umlauf\", true)"), "die Leiste des Guide läuft um")

	print("Guide ohne Übertragen und Optionen")
	var dc := FileAccess.get_file_as_string("res://src/ui/layers/guide_discord.gd")
	check(not dc.contains("\"Übertragen\"") and not dc.contains("In Discord übertragen") and dc.contains("\"Stream beenden\""),
			"Discord-Reiter: kein Übertragen mehr, ein laufender Stream lässt sich beenden")
	var spiel := FileAccess.get_file_as_string("res://src/ui/layers/guide_spiel.gd") + FileAccess.get_file_as_string("res://src/ui/components/guide_game.gd")
	check(not spiel.contains("\"g:opts\"") and not spiel.contains("open_game_options"), "Start: kein Knopf „Optionen“ am Spiel")

	print("Ein Mikro")
	var war_stumm: bool = Mixer.mic_muted
	Mixer.mic_muted = false
	check(not Mixer.mic_aus(), "Windows-Mikro an, Discord nicht verbunden: an")
	Mixer.mic_muted = true
	check(Mixer.mic_aus(), "Windows-Mikro aus: aus")
	Mixer.mic_muted = war_stumm
	var zeile := FileAccess.get_file_as_string("res://src/ui/components/guide_voice_row.gd")
	check(zeile.contains("Mixer.mic_aus() if me") and zeile.count("\"Stumm aus\"") == 2 and not zeile.contains("\"Hören\""),
			"Zeile im Sprachkanal: X heißt bei dir und bei anderen gleich, dein Stand ist der des einen Mikros")
	check(dc.contains("Mixer.toggle_mic()") and not dc.contains("Voice.set_self_mute("), "Discord-Reiter schaltet das Mikro wie die Schnellleiste")
	var rest := FileAccess.get_file_as_string("res://src/ui/layers/person_menu.gd") + FileAccess.get_file_as_string("res://src/ui/components/guide_game.gd")
	check(not rest.contains("Voice.set_self_mute("), "Menü an dir selbst und die Zeile im Spiel ebenso")

	print("Steams Mitteilungs-Fenster")
	check(SteamStill.zeile({}) == "keine Antwort (?)" and SteamStill.zeile({ "ok": false, "error": "nur unter Windows" }) == "keine Antwort (nur unter Windows)",
			"keine Antwort des Helfers steht im Protokoll")
	check(SteamStill.zeile({ "aktiv": true, "gesehen": 1, "gesetzt": 3, "zuletzt": "notificationtoasts_18_desktop", "aehnlich": "", "zurueck": 0 })
			== "aktiv, Fenster 1, gesetzt 3, zuletzt notificationtoasts_18_desktop", "Stand als eine Zeile")
	check(SteamStill.zeile({ "aktiv": false, "gesehen": 2.0, "gesetzt": "5", "zurueck": 2, "aehnlich": "notificationtoasts_3_bpm" })
			== "aus, Fenster 2, gesetzt 5, zurückgegeben 2, ähnlich: notificationtoasts_3_bpm", "abgeschaltet: wie viele Fenster zurückgegeben wurden")
	check(SteamStill.zeile({ "aktiv": "ja", "gesehen": [], "gesetzt": null, "zuletzt": {}, "aehnlich": 7 }) == "aus, Fenster 0, gesetzt 0, ähnlich: 7",
			"falsche Arten in der Antwort: kein Fehler")
	check(bool(Config.get_value(SteamStill.KEY, false)), "voreingestellt an")
	var helfer := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var ende := helfer.substr(helfer.rfind("$line = [Console]::In.ReadLine()"))
	check(ende.contains("[UzSteamStill]::Aus()"), "endet der Helfer (Uzai zu oder abgestürzt), zeigt Steam seine Fenster wieder")
	check(helfer.contains("'steam-still' {") and not helfer.contains("localconfig"), "der Helfer fasst Steams Dateien dafür nicht an")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)
