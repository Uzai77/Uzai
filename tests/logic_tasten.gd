extends Node
## Eingaben an Fenster (docs/SECURITY.md „Eingaben an Fenster“) ohne Bildschirm: die Erlaubnisliste
## für Tastenbelegungen von Discord und Lossless Scaling in Uzai (Helper.global_keys_ok, dieselbe
## Tabelle wie der Helfer: tests/fixtures/tasten_kombis.json), die Sätze zu nicht gedrückten Tasten,
## und dass jeder Aufrufer ein Ziel nennt, das Ergebnis prüft und Medientasten nur nach eigenem
## Knopfdruck an Windows gehen. Mit UZAI_HELPER_SHELL=<pwsh> zusätzlich tests/tasten_cs.ps1: dieselbe
## Tabelle im Helfer, Pfadprüfung, geschützte Fenster, require_focus immer, böse Befehle.
## Aufruf: godot --headless --path . res://tests/logic_tasten.tscn

const HelperS := preload("res://src/core/helper.gd")
const LosslessS := preload("res://src/core/lossless.gd")
const Main := preload("res://src/main.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p).replace("\r\n", "\n")


func _fn(src: String, kopf: String) -> String:
	var a := src.find(kopf)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + kopf.length())
	var c := src.find("\nstatic func ", a + kopf.length())
	if b < 0 or (c >= 0 and c < b):
		b = c
	return src.substr(a, (b - a) if b > 0 else -1)


func _ready() -> void:
	print("Erlaubnisliste (Uzai)")
	var jp := JSON.new()
	check(jp.parse(_src("res://tests/fixtures/tasten_kombis.json")) == OK and jp.data is Dictionary, "Tabelle lesbar")
	var cases: Array = (jp.data as Dictionary).get("faelle", []) if jp.data is Dictionary else []
	var bad := PackedStringArray()
	for c in cases:
		var want := str(c[1]) == "ok"
		if HelperS.global_keys_ok(str(c[0])) != want:
			bad.append("„%s“ → %s" % [str(c[0]).c_escape(), "ok" if not want else "nein"])
	check(cases.size() >= 50 and bad.is_empty(), "%d Kürzel wie im Helfer%s" % [cases.size(), (": " + "; ".join(bad)) if not bad.is_empty() else ""])
	for k in LosslessS.HOTKEYS:
		check(HelperS.global_keys_ok(str(k[0])), "Lossless-Auswahl „%s“ erlaubt" % str(k[0]))
	check(HelperS.global_keys_ok("CTRL+SHIFT+F9"), "Standard für Discord erlaubt")
	# Aus der Datei von Lossless Scaling (fremde Daten) kommt ein Kürzel mit Windows-Taste nicht durch.
	var xml_win := "<Settings><Hotkey>R</Hotkey><HotkeyModifierKeys>Windows</HotkeyModifierKeys></Settings>"
	var xml_ok := "<Settings><Hotkey>S</Hotkey><HotkeyModifierKeys>Alt Control</HotkeyModifierKeys></Settings>"
	check(LosslessS.parse_settings_hotkey(xml_win) == "WIN+R" and not HelperS.global_keys_ok(LosslessS.parse_settings_hotkey(xml_win)),
			"Lossless-Datei mit Win+R: nicht übernommen")
	check(HelperS.global_keys_ok(LosslessS.parse_settings_hotkey(xml_ok)), "Lossless-Datei mit Strg+Alt+S: übernommen")
	var ls := _src("res://src/core/lossless.gd")
	check(_fn(ls, "func effective_hotkey(").contains("HelperScript.global_keys_ok(k)"), "Kürzel aus der Datei nur im erlaubten Format")
	check(_fn(ls, "func _toggle(").contains("if not HelperScript.global_keys_ok(key):"), "Lossless: falsches Kürzel wird gar nicht gesendet")

	print("Sätze")
	check(HelperS.keys_text({ "ok": true, "result": { "sent": true } }, "R") == "", "gedrückt: kein Satz")
	check(HelperS.keys_text({ "ok": true, "result": { "sent": false, "reason": "nicht vorn", "window": "" } }, "R").contains("Spielfenster nicht"),
			"ohne Ziel: Spielfenster nicht gefunden")
	check(HelperS.keys_text({ "ok": true, "result": { "sent": false, "reason": "nicht vorn", "window": "PCSX2" } }, "R").contains("nicht nach vorn"),
			"Ziel nicht vorn: nicht gedrückt")
	check(HelperS.keys_text({ "ok": true, "result": { "sent": false, "reason": "nicht erlaubt" } }, "R").contains("nicht zu"), "nicht erlaubt")
	check(HelperS.keys_text({ "ok": true, "result": { "sent": false, "reason": "geschützt" } }, "R").contains("Sicherheitsfenster"), "geschütztes Fenster")
	check(HelperS.keys_text({ "ok": false, "error": "" }, "R") != "", "Helfer antwortet nicht: ein Satz")
	check(LosslessS.key_problem({ "ok": true, "result": { "sent": false, "reason": "nicht erlaubt" } }, "WIN+R").contains("WIN+R"), "Lossless: nicht erlaubt mit Kürzel")
	check(LosslessS.key_problem({ "ok": true, "result": { "sent": false, "reason": "zu oft" } }, "F12") != "", "Lossless: zu oft")
	for pair in [["nicht erlaubt", "not_allowed"], ["nicht vorn", "not_front"], ["geschützt", "protected"], ["zu oft", "too_often"]]:
		var r := { "ok": true, "result": { "sent": false, "reason": pair[0], "accepted": 0, "expected": 6, "discord": [{ "name": "Discord" }] } }
		check(Main.live_problem_kind(r, true) == pair[1] and Main.live_problem(r, "WIN+R", true) != "", "Discord: „%s“ → %s mit Satz" % pair)
	check(Main.live_fallback_ok("not_allowed") and Main.live_fallback_ok("not_front"), "nicht erlaubt / nicht vorn: weiter über die Discord-App")
	check(not Main.live_fallback_ok("protected") and not Main.live_fallback_ok("too_often"), "vor Sicherheitsfenster oder gleich danach: nicht")

	print("Aufrufer")
	var bare := PackedStringArray()
	var re := RegEx.create_from_string("Helper\\.run\\(\"keys\", \\{([^}]*)\\}")
	for path in _gd_files("res://src"):
		for m in re.search_all(_src(path)):
			var body := m.get_string(1)
			if not (body.contains("\"hwnd\"") or body.contains("\"pid\"") or body.contains("\"pids\"")):
				bare.append(path.get_file())
	# lossless.gd baut die Argumente vorher (args mit pids und hwnd).
	check(bare.is_empty(), "jeder Tastendruck nennt sein Ziel (hwnd/pid/pids)%s" % ((": " + ", ".join(bare)) if not bare.is_empty() else ""))
	var cap := _src("res://src/ui/layers/captures.gd")
	check(cap.contains("Helper.run(\"keys\", { \"hwnd\": fg_hw, \"keys\": \"CTRL+V\" }") and cap.contains("nm.begins_with(\"steam\") and fg_hw != 0"),
			"Steam-Chat: Strg+V nur an das Steam-Fenster vorn")
	var lau := _src("res://src/core/launcher.gd")
	check(_fn(lau, "func hotkey(").contains("get(\"sent\", false)"), "Emulator-Kürzel: Erfolg nur, wenn wirklich gedrückt")
	var mg := _src("res://src/main_guide.gd")
	check(_fn(mg, "func save_clip(").contains("HelperScript.keys_text(r,") and _fn(mg, "func steam_overlay(").contains("HelperScript.keys_text(r,"),
			"Clip und Steam-Overlay: „gesendet“ nur, wenn gedrückt")
	var md := _src("res://src/main_discord.gd")
	check(_fn(md, "func discord_go_live(").contains("if HelperScript.global_keys_ok(keys):") and _fn(md, "func test_stream_keys(").contains("if HelperScript.global_keys_ok(keys):"),
			"Discord: Taste nur im erlaubten Format")
	check(md.contains("\"discord-buttons\", { \"hwnd\": hwnd, \"budget_ms\": 5000, \"app\": \"discord\" }"), "Bildschirm teilen: UIA nur in der Discord-App")
	check(_src("res://src/core/installs.gd").contains("\"discord-buttons\", { \"hwnd\": hwnd, \"budget_ms\": 4000, \"app\": \"steam\" }"), "Installieren: UIA nur in Steam")

	print("Medientasten")
	var mu := _src("res://src/core/music.gd")
	check(_fn(mu, "func media_key(").contains("a[\"user\"] = by_user") and mu.contains("func play_pause(by_user := true) -> void:"),
			"Medientaste sagt dem Helfer, ob du gedrückt hast")
	check(_fn(mu, "func play_pause(").count("media_key(\"playpause\", by_user)") == 2, "… auch beim Ersatzweg nach Spotify")
	for p in ["res://src/core/profile_run.gd", "res://src/core/rest.gd"]:
		var s := _src(p)
		check(s.count("Music.play_pause(false)") == 2 and not s.contains("Music.play_pause()"), "%s hält nur gezielt an (nie die Taste an Windows)" % p.get_file())

	await _pwsh()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


func _pwsh() -> void:
	if HelperS._test_shell() == "":
		print("  (PowerShell-Prüfung übersprungen: UZAI_HELPER_SHELL nicht gesetzt)")
		return
	print("Helfer unter PowerShell 7 (tests/tasten_cs.ps1)")
	var o: Array = []
	OS.execute(HelperS._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", ProjectSettings.globalize_path("res://tests/tasten_cs.ps1"),
			ProjectSettings.globalize_path("res://helper/uzai-helper.ps1"), ProjectSettings.globalize_path("res://tests/fixtures/tasten_kombis.json")]), o, true)
	var txt := str(o[0] if not o.is_empty() else "")
	for line in txt.split("\n"):
		if line.contains("FAIL"):
			print("    " + line.strip_edges())
	check(txt.contains("Ergebnis: alles ok"), "tasten_cs.ps1: " + txt.get_slice("Ergebnis: ", 1).strip_edges().left(80))
