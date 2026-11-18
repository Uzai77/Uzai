extends Node
## Menüs an einem Spiel ohne Bildschirm: Die Spiel-Optionen zeigen vorn nur das Häufige (höchstens
## acht Zeilen), alles Seltene steht geordnet unter „Spiel-Einstellungen“ – und nichts geht
## verloren: Jede frühere Zeile ist genau einmal erreichbar. Dazu: Konsolen-Museum, „Heute legal
## spielen“ und der Retro-Katalog sind weg, die Retro-Klassiker im Shop bleiben.
## Aufruf: godot --headless --path . res://tests/logic_spielmenus.tscn

const GameOptions := preload("res://src/ui/layers/game_options.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const RK := preload("res://src/core/retro_klassiker.gd")

## Was es vorher an Zeilen gab (Steam-, Emulator-, eigenes PC-Spiel; Demo unter Windows-Bedingungen).
const VORHER := {
	"steam": ["Spielen", "Favorit", "Bilder", "Titel ändern", "Ordner", "Status", "Bewertung", "Listen", "Eigene Angaben", "Profil",
		"Lossless Scaling beim Start", "Verknüpfung anlegen", "Im Discord-Status zeigen", "Ausblenden"],
	"rom": ["Spielen", "Mit Remote Play Together starten", "Favorit", "Bildfilter", "Bilder", "Titel ändern", "Ordner",
		"Status", "Bewertung", "Listen", "Eigene Angaben", "Profil", "Zusätzliche Startparameter", "RetroAchievements-Spiel",
		"Lossless Scaling beim Start", "Verknüpfung anlegen", "Im Discord-Status zeigen", "Ausblenden"],
	"pc": ["Spielen", "Favorit", "Bilder", "Titel ändern", "Ordner", "Status", "Bewertung", "Listen", "Eigene Angaben", "Profil",
		"Zusätzliche Startparameter", "Programmdatei", "Arbeitsordner", "Lossless Scaling beim Start", "Verknüpfung anlegen",
		"Im Discord-Status zeigen", "Ausblenden", "Aus Uzai entfernen"],
}
## Status, Bewertung und Listen stehen jetzt im Blatt „Backlog“ (BacklogFlow.open_sheet).
const IM_BACKLOG := ["Status", "Bewertung", "Listen"]

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	Library.demo = true
	var games := {
		"steam": { "id": "steam:1", "source": "steam", "system": "steam", "appid": 1, "title": "Ein Steam-Spiel" },
		"rom": { "id": "ps2:x", "source": "rom", "system": "ps2", "title": "Ein PS2-Spiel", "path": "D:/PS2/x.iso" },
		"pc": { "id": "pc:x", "source": "pc", "system": "pc", "title": "Ein PC-Spiel", "path": "D:/Spiele/x/x.exe" },
	}
	for k in games:
		print("Spiel-Optionen: %s" % k)
		var opt = GameOptions.new()
		opt.game = games[k]
		opt.content = VBoxContainer.new()
		opt.fill()
		var main_rows := _titles(opt.content)
		var sub = Sheet.new()
		sub.content = VBoxContainer.new()
		opt.call("_advanced_rows", sub)
		var adv_rows := _titles(sub.content)
		check(main_rows.size() <= 8, "vorn höchstens acht Zeilen (%d: %s)" % [main_rows.size(), ", ".join(main_rows)])
		check(main_rows.has("Spielen") and main_rows.has("Favorit") and main_rows.has("Ausblenden") and main_rows.has("Spiel-Einstellungen"),
				"vorn: Spielen, Favorit, Ausblenden, Spiel-Einstellungen")
		check(main_rows.find("Ausblenden") > main_rows.find("Spiel-Einstellungen"), "Ausblenden in der letzten Gruppe")
		var all := main_rows + adv_rows + IM_BACKLOG
		var lost: Array = (VORHER[k] as Array).filter(func(t: String) -> bool: return not all.has(t))
		check(lost.is_empty(), "nichts verloren %s" % str(lost))
		var twice: Array = main_rows.filter(func(t: String) -> bool: return adv_rows.has(t))
		check(twice.is_empty(), "keine Zeile doppelt %s" % str(twice))
		check(not main_rows.has("Retro-Katalog") and not main_rows.has("Profil") and not main_rows.has("Titel ändern"),
				"Seltenes nicht vorn")
		check(adv_rows.size() >= 5, "Spiel-Einstellungen gefüllt (%d)" % adv_rows.size())
		check(_labels(sub.content).has("Start") and _labels(sub.content).has("Angaben"), "Spiel-Einstellungen in Gruppen")
		if k == "rom":
			check(_labels(sub.content).has("Emulator") and not adv_rows.has("Retro-Katalog"), "Emulator-Gruppe ohne Retro-Katalog")
		check(str(opt.call("_advanced_text")) != "", "Wert der Zeile Spiel-Einstellungen")
		sub.content.free()
		sub.free()
		opt.content.free()
		opt.free()

	print("Konsolen-Museum und „Heute legal spielen“ entfernt")
	check(not ResourceLoader.exists("res://src/ui/layers/retro_museum.gd"), "Museum-Ebene weg")
	check(not ResourceLoader.exists("res://src/ui/components/museum_tile.gd"), "Museum-Kachel weg")
	var main_script: Script = load("res://src/main_ebenen.gd")
	check(not main_script.get_script_method_list().any(func(m: Dictionary) -> bool: return str(m.name) == "open_retro_museum"), "kein open_retro_museum")
	check(not Store.has_method("retro_offers") and not Store.has_method("retro_for_system"), "Store fragt nicht mehr je Spiel/System")
	check(Store.has_method("load_retro_classics") and RK.shop_collections().size() >= 10, "Retro-Klassiker im Shop bleiben")
	check(not main_script.get_script_method_list().any(func(m: Dictionary) -> bool: return str(m.name) == "open_retro_system"), "kein open_retro_system")
	Library.demo = false
	# Kürzel aus den Einstellungen von Lossless Scaling (fremde Datei): nur was Uzai sicher versteht.
	var LS = load("res://src/core/lossless.gd")
	check(LS.parse_settings_hotkey("<Hotkey>S</Hotkey><HotkeyModifierKeys>Alt Control</HotkeyModifierKeys>") == "CTRL+ALT+S"
			and LS.parse_settings_hotkey("<ScaleHotkey> F12 </ScaleHotkey><ScaleHotkeyModifierKeys>None</ScaleHotkeyModifierKeys>") == "F12"
			and LS.parse_settings_hotkey("<Hotkey>Ctrl+Alt+D5</Hotkey>") == "CTRL+ALT+5"
			and LS.parse_settings_hotkey("<Hotkey>NumPad3</Hotkey><HotkeyModifierKeys>Shift</HotkeyModifierKeys>") == "SHIFT+NUM3",
			"Lossless Scaling: Kürzel aus Settings.xml gelesen")
	check(LS.parse_settings_hotkey("<Hotkey>S</Hotkey>") == "" and LS.parse_settings_hotkey("<Hotkey>LWin</Hotkey><HotkeyModifierKeys>None</HotkeyModifierKeys>") == ""
			and LS.parse_settings_hotkey("<Hotkey>S</Hotkey><HotkeyModifierKeys>Hyper</HotkeyModifierKeys>") == "" and LS.parse_settings_hotkey("kein xml") == "",
			"Lossless Scaling: Unbekanntes ergibt kein Kürzel (dann gilt die Uzai-Einstellung)")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _titles(box: Node) -> Array:
	return box.get_children().filter(func(c: Node) -> bool: return c is SettingRow).map(func(c: Node) -> String: return str(c.title))


## Abschnitte einer Liste: Etiketten direkt darin oder (Listen-Sprache, liste.gd) in einem Rahmen darum.
func _labels(box: Node) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is Label:
			out.append(str((c as Label).text))
		elif not (c is SettingRow):
			for l in c.find_children("*", "Label", true, false):
				out.append(str((l as Label).text))
	return out
