extends Node
## Emulator-Suche (Nutzertest: „findet kaum Emulatoren, die nicht in Program Files sind“): Namen
## erkennen, Suchorte mit Tiefe, Grenzen, Verknüpfungen (.lnk), Registry- und Prozess-Hinweise –
## alles mit einem nachgebauten Dateisystem, nichts wird ausgeführt.
## Aufruf: godot --headless --path . res://tests/logic_emu_suche.tscn

const EmuSuche := preload("res://src/core/emu_suche.gd")
const E := preload("res://src/core/einrichtung.gd")

var fails := 0
var fs := {}          ## Pfad → { dirs, files }, Bytes von .lnk unter lnk


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _put(path: String) -> void:
	# Legt die Datei und alle Ordner darüber an.
	var parts := path.split("/")
	var cur := parts[0] + "/"
	for i in range(1, parts.size()):
		if not fs.has(cur):
			fs[cur] = { "dirs": [], "files": [] }
		var last := i == parts.size() - 1
		var key := "files" if last else "dirs"
		if not (fs[cur][key] as Array).has(parts[i]):
			(fs[cur][key] as Array).append(parts[i])
		cur = (cur if cur.ends_with("/") else cur + "/") + parts[i]
		if not last and not fs.has(cur):
			fs[cur] = { "dirs": [], "files": [] }


func _io(lnks: Dictionary = {}) -> Dictionary:
	return {
		"list_dirs": func(p: String) -> Array: return (fs.get(p, {}) as Dictionary).get("dirs", []),
		"list_files": func(p: String) -> Array: return (fs.get(p, {}) as Dictionary).get("files", []),
		"read": func(p: String) -> PackedByteArray: return lnks.get(p, PackedByteArray()),
		"exists": func(p: String) -> bool:
			var d := p.get_base_dir()
			return ((fs.get(d, {}) as Dictionary).get("files", []) as Array).has(p.get_file()),
	}


## Kleinste echte Verknüpfung: Kopf + LinkInfo mit lokalem Pfad (ANSI oder Unicode).
static func lnk(target: String, unicode: bool) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(0x4C)
	b.encode_u32(0, 0x4C)
	var clsid := [0x01, 0x14, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]
	for i in 16:
		b[4 + i] = clsid[i]
	b.encode_u32(0x14, 0x2 | (0x80 if unicode else 0))
	var hdr := 0x24 if unicode else 0x1C
	var vol := PackedByteArray()
	vol.resize(16)
	var ansi := target.to_ascii_buffer()
	ansi.append(0)
	var uni := target.to_utf16_buffer()
	uni.append_array(PackedByteArray([0, 0]))
	var li := PackedByteArray()
	li.resize(hdr)
	var lbp := hdr + vol.size()
	var cps := lbp + ansi.size()
	var ulbp := cps + 1
	var size := ulbp + (uni.size() + 2 if unicode else 0)
	li.encode_u32(0, size)
	li.encode_u32(4, hdr)
	li.encode_u32(8, 1)
	li.encode_u32(12, hdr)
	li.encode_u32(16, lbp)
	li.encode_u32(20, 0)
	li.encode_u32(24, cps)
	if unicode:
		li.encode_u32(28, ulbp)
		li.encode_u32(32, size - 2)
	li.append_array(vol)
	li.append_array(ansi)
	li.append(0)
	if unicode:
		li.append_array(uni)
		li.append_array(PackedByteArray([0, 0]))
	b.append_array(li)
	return b


func _ready() -> void:
	var emus: Array = (Config.read_json("res://data/emulators.json", {}) as Dictionary).get("emulators", [])
	check(emus.size() >= 20, "Emulator-Liste geladen (%d)" % emus.size())
	var pats := EmuSuche.patterns(emus, E.ALT_EXE)

	print("Programmnamen")
	check(EmuSuche.exe_id("pcsx2-qtx64-avx2.exe", pats) == "pcsx2", "pcsx2-qtx64-avx2.exe → PCSX2")
	check(EmuSuche.exe_id("Dolphin.exe", pats) == "dolphin", "Dolphin.exe → Dolphin (Groß/klein egal)")
	check(EmuSuche.exe_id("duckstation-qt-x64-ReleaseLTCG.exe", pats) == "duckstation", "DuckStation")
	check(EmuSuche.exe_id("xenia_canary.exe", pats) == "xenia" and EmuSuche.exe_id("xenia.exe", pats) == "xenia_master", "Xenia Canary und Xenia getrennt")
	check(EmuSuche.exe_id("RetroArch.exe", pats) == "retroarch" and EmuSuche.exe_id("Ryujinx.exe", pats) == "ryubing", "RetroArch, Ryujinx")
	for bad in ["unins000.exe", "pcsx2-updater.exe", "notepad.exe", "Dolphin.exe.lnk", "retroarch_crash.exe", "duckstation-setup.exe"]:
		check(EmuSuche.exe_id(bad, pats) == "", "kein Emulator: %s" % bad)
	check(EmuSuche.product_id("PCSX2 Nightly", emus) == "pcsx2" and EmuSuche.product_id("Dolphin", emus) == "" and EmuSuche.product_id("Dolphin Emulator", emus) == "dolphin",
			"Versionsangaben: PCSX2 ja, „Dolphin“ allein (Dateimanager) nein")

	print("Suchorte")
	var env := { "USERPROFILE": "C:\\Users\\Ana", "LOCALAPPDATA": "C:\\Users\\Ana\\AppData\\Local", "APPDATA": "C:\\Users\\Ana\\AppData\\Roaming",
		"ProgramFiles": "C:\\Program Files", "ProgramData": "C:\\ProgramData", "PUBLIC": "C:\\Users\\Public" }
	var roots := EmuSuche.roots(["C:", "D:"], env, ["E:\\SteamLibrary"])
	var paths := roots.map(func(r): return str(r[0]))
	for want in ["D:/Emulators", "D:/Emulatoren", "D:/Games", "D:/Spiele", "D:/Tools", "C:/Users/Ana/Desktop", "C:/Users/Ana/Downloads",
			"C:/Users/Ana/Documents", "C:/Users/Ana/AppData/Local/Programs", "C:/Users/Ana/scoop/apps", "C:/ProgramData/chocolatey/lib",
			"C:/Users/Ana/AppData/Local/Microsoft/WinGet/Packages", "E:/SteamLibrary/steamapps/common", "C:/Users/Ana/AppData/Roaming/EmuDeck/Emulators",
			"D:/RetroBat/emulators", "D:/LaunchBox/Emulators", "C:/Program Files", "D:/"]:
		check(paths.has(want), "Suchort: %s" % want)
	check(not paths.has("D:") and roots.all(func(r): return int(r[1]) >= 1 and int(r[1]) <= 4), "Laufwerk als „D:/“, Tiefe 1–4")
	check(paths.find("D:/Emulators") < paths.find("D:/"), "eigene Emulator-Ordner vor dem ganzen Laufwerk")

	print("Ordner durchgehen")
	_put("D:/Zeug/pcsx2-v2.1.0-windows-x64-Qt/pcsx2-qt.exe")
	_put("D:/Zeug/pcsx2-v2.1.0-windows-x64-Qt/unins000.exe")
	_put("D:/Windows/System32/Dolphin.exe")
	_put("D:/a/b/c/d/Cemu.exe")
	_put("C:/Users/Ana/Downloads/rpcs3-v0.0.33/rpcs3.exe")
	_put("C:/Users/Ana/scoop/apps/duckstation/current/duckstation-qt-x64-ReleaseLTCG.exe")
	_put("E:/SteamLibrary/steamapps/common/RetroArch/retroarch.exe")
	var io := _io()
	var found := EmuSuche.walk(roots, pats, io.list_dirs, io.list_files, EmuSuche.budget(), {})
	check(str(found.get("pcsx2", {}).get("exe", "")) == "D:/Zeug/pcsx2-v2.1.0-windows-x64-Qt/pcsx2-qt.exe", "PCSX2 in einem Ordner mit Fassung im Namen (D:\\Zeug)")
	check(found.has("rpcs3") and found.has("duckstation") and found.has("retroarch"), "Downloads, Scoop, Steam")
	check(not found.has("dolphin"), "Windows-Ordner bleibt außen vor")
	check(not found.has("cemu"), "zu tief unter dem Laufwerk: nicht gesucht (Tiefe begrenzt)")
	var small := EmuSuche.budget(3, 10000)
	EmuSuche.walk(roots, pats, io.list_dirs, io.list_files, small, {})
	check(int(small.dirs) == 3, "Grenze: höchstens so viele Ordner wie erlaubt")
	var late := EmuSuche.budget(100000, -1)
	check(EmuSuche.walk(roots, pats, io.list_dirs, io.list_files, late, {}).is_empty(), "Grenze: Zeit abgelaufen, nichts mehr gesucht")

	print("Verknüpfungen (.lnk)")
	check(EmuSuche.lnk_target(lnk("F:\\Emus\\Cemu 2.0\\Cemu.exe", false)) == "F:/Emus/Cemu 2.0/Cemu.exe", "Ziel aus LinkInfo (ANSI)")
	check(EmuSuche.lnk_target(lnk("F:\\Spiele\\Émulateurs\\xemu.exe", true)) == "F:/Spiele/Émulateurs/xemu.exe", "Ziel aus LinkInfo (Unicode)")
	var cut := lnk("F:\\Emus\\Cemu\\Cemu.exe", false)
	check(EmuSuche.lnk_target(cut.slice(0, cut.size() - 12)) == "", "abgeschnittene Datei: nichts")
	var broken := lnk("F:\\Emus\\Cemu\\Cemu.exe", false)
	broken.encode_u32(0x4C, 0x7fffffff)
	check(EmuSuche.lnk_target(broken) == "", "falsche Länge: nichts")
	check(EmuSuche.lnk_target(PackedByteArray([1, 2, 3])) == "" and EmuSuche.lnk_target(PackedByteArray()) == "", "keine Verknüpfung: nichts")
	check(EmuSuche.lnk_target(lnk("\\\\server\\share\\cemu.exe", false)) == "", "Netzpfad: nichts")
	check(EmuSuche.lnk_target(lnk("F:\\a\\..\\Windows\\cemu.exe", false)) == "", "Pfad mit „..“: nichts")

	print("Registry und laufende Programme")
	_put("G:/RA/retroarch.exe")
	_put("F:/Konsole/ryujinx.exe")
	_put("F:/Y/emu.exe")
	_put("H:/DS/x64/duckstation-qt.exe")
	var hints := {
		"procs": [{ "path": "F:\\Konsole\\ryujinx.exe" }, { "path": "F:\\Y\\emu.exe", "product": "PCSX2 Nightly" },
			{ "path": "C:\\Windows\\explorer.exe", "product": "Dolphin" }, "kaputt"],
		"uninstall": [{ "name": "RetroArch", "icon": "\"G:\\RA\\retroarch.exe\",0" }, { "name": "DuckStation", "dir": "H:\\DS" }, 7],
	}
	var hf := {}
	var more := EmuSuche.from_hints(hints, emus, pats, io.exists, hf)
	check(str(hf.get("ryubing", {}).get("exe", "")) == "F:/Konsole/ryujinx.exe", "laufendes Programm nach Namen")
	check(str(hf.get("pcsx2", {}).get("exe", "")) == "F:/Y/emu.exe", "laufendes Programm nach Versionsangabe")
	check(str(hf.get("retroarch", {}).get("exe", "")) == "G:/RA/retroarch.exe", "Registry: Symbol-Datei des Eintrags")
	check(more.map(func(r): return str(r[0])).has("H:/DS"), "Registry: Ordner eines Eintrags ohne passende Datei wird durchsucht")
	check(not hf.has("dolphin"), "fremdes Programm mit ähnlichem Namen bleibt draußen")

	print("Ganze Suche")
	_put("C:/Users/Ana/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Cemu.lnk")
	_put("K:/Irgendwo/Tief/Drin/Cemu/Cemu.exe")
	var lnks := { "C:/Users/Ana/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Cemu.lnk": lnk("K:\\Irgendwo\\Tief\\Drin\\Cemu\\Cemu.exe", false) }
	var all := EmuSuche.find(emus, E.ALT_EXE, ["C:", "D:"], env, ["E:\\SteamLibrary"], hints, _io(lnks))
	check(str(all.get("cemu", {}).get("exe", "")) == "K:/Irgendwo/Tief/Drin/Cemu/Cemu.exe" and str(all.cemu.how) == "verknuepfung", "Cemu über die Verknüpfung im Startmenü")
	check(str(all.get("duckstation", {}).get("how", "")) == "registry" or all.has("duckstation"), "DuckStation gefunden")
	check(all.has("pcsx2") and all.has("rpcs3") and all.has("retroarch") and all.has("ryubing"), "alle übrigen Funde dabei (%s)" % ", ".join(PackedStringArray(all.keys())))
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit()
