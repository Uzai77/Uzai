extends RefCounted
## Emulatoren im Hintergrund (Spiel im Fernseher des Zimmers, src/room/fernsehspiel.gd): Stehst du im
## Zimmer auf, hat Uzai den Fokus und das Spiel läuft im Fernseher weiter. Viele Emulatoren halten
## aber an, sobald ihr Fenster den Fokus verliert, und manche lesen den Controller auch im Hintergrund –
## dann landete jeder Schritt der Figur zugleich im Spiel. Vor jedem Start eines Emulator-Spiels durch
## Uzai stellt es deshalb genau zwei Dinge um, wo der Emulator dafür eine Einstellung hat:
##   pause    bei Fokusverlust weiterlaufen
##   eingabe  den Controller nur lesen, solange das eigene Fenster vorn ist
## Kann ein Emulator das Mitlesen nicht abschalten (PCSX2, yuzu & Co.), stellt Uzai statt „pause“
## das Gegenteil ein:
##   anhalten bei Fokusverlust anhalten – im Zimmer hat Uzai den Fokus, das Spiel wartet; spielst du
##            wieder (Vollbild), hat es den Fokus und läuft weiter (der Emulator selbst, Uzai schickt keine
##            Tasten). Im Zimmer sagt ein kurzer Hinweis, dass es wartet.
## Warum bei jedem Start und nicht erst beim Aufstehen: Die Emulatoren lesen ihre Einstellungen nur
## beim Start, und aufstehen kann man in jedem laufenden Spiel (Guide › Dein Zimmer). Im Vollbild
## ändert sich dadurch nichts (der Emulator hat den Fokus); über dem Guide hält Uzai Emulatoren
## ohnehin selbst an.
##
## Derselbe vorsichtige Weg wie bei Remote Play (remote_play_pads.gd): Nur diese Schlüssel, alles
## andere bleibt Zeile für Zeile. Die alten Werte stehen in Config („emu.hintergrund_zurueck“, übersteht
## einen Absturz); nach dem Spiel (und beim nächsten Start von Uzai) kommen sie zurück – aber nur, was
## noch so aussieht, wie Uzai es geschrieben hat. Ausschalten: Config „system.emu_hintergrund“ = false.
##
## Woher die Schlüssel stammen (Quelltexte der Emulatoren):
##   RetroArch   retroarch.cfg  pause_nonactive, input_joypad_background (neuere Versionen)
##   Dolphin     Dolphin.ini    [Interface] PauseOnFocusLost, [Input] BackgroundInput
##   DuckStation settings.ini   [Main] PauseOnFocusLoss, [Main] DisableBackgroundInput
##   PCSX2       PCSX2.ini      [UI] PauseOnFocusLoss → anhalten. Controller im Hintergrund: keine
##                              Einstellung – SDL liest ohne eigenes SDL-Fenster immer (SDLInputSource:
##                              auch [SDLHints] hilft nicht), XInput und DirectInput (DISCL_BACKGROUND)
##                              ebenso; dazu nie exklusives Vollbild (pcsx2_vollbild, Zweck „vollbild“)
##   PPSSPP      ppsspp.ini     [General] PauseOnLostFocus, [Control] GamepadOnlyFocused
##   Eden & Co.  qt-config.ini  [UI] pauseWhenInBackground → anhalten (SDL mit Hintergrund-Ereignissen)

const Ini := preload("res://src/core/remote_play_pads.gd")
const Sicher := preload("res://src/core/sicher.gd")
const SpielerEmus := preload("res://src/core/spieler_emus.gd")

const RESTORE_KEY := "emu.hintergrund_zurueck"
const KEY_AN := "system.emu_hintergrund"
const NAMEN := ["retroarch.cfg", "dolphin.ini", "settings.ini", "pcsx2.ini", "ppsspp.ini", "qt-config.ini"]
const MAX_BYTES := 2 * 1024 * 1024
const ZWECKE := ["pause", "eingabe"]

## Art → [[Abschnitt, Schlüssel, gewünschter Wert, Zweck, Wert, der gilt, wenn der Schlüssel fehlt]].
const REGELN := {
	"retroarch": [["", "pause_nonactive", "\"false\"", "pause", "true"],
		["", "input_joypad_background", "\"false\"", "eingabe", "true"]],
	"dolphin": [["Interface", "PauseOnFocusLost", "False", "pause", "false"],
		["Input", "BackgroundInput", "False", "eingabe", "false"]],
	"duckstation": [["Main", "PauseOnFocusLoss", "false", "pause", "false"],
		["Main", "DisableBackgroundInput", "true", "eingabe", "false"]],
	"pcsx2": [["UI", "PauseOnFocusLoss", "true", "anhalten", "false"]],
	"ppsspp": [["General", "PauseOnLostFocus", "False", "pause", "false"],
		["Control", "GamepadOnlyFocused", "True", "eingabe", "false"]],
	"yuzu": [["UI", "pauseWhenInBackground", "true", "anhalten", "false"]],
}


## PCSX2: kein exklusives Vollbild. Steht man im Zimmer auf, zeigt der Fernseher das Spiel über Windows
## Graphics Capture – ein exklusives Vollbild sieht Windows dabei nicht (schwarz), und es minimiert sich,
## sobald Uzai darüberliegt. Aus den Quelltexten von PCSX2 (GSDevice.cpp, VKSwapChain.cpp, Config.h):
##   [EmuCore/GS] FullscreenMode  „1920 x 1080 @ 60 hz“ = exklusiv (D3D11/D3D12), leer = randlos → leer
##   [EmuCore/GS] ExclusiveFullscreenControl  -1 automatisch (Treiber entscheidet), 0 nie, 1 erlaubt
##                (nur Vulkan) → 0, wenn erlaubt oder mit Vulkan (Renderer 14) auf „automatisch“
## Rückgabe wie REGELN: [[Abschnitt, Schlüssel, gewünschter Wert, Zweck]] – nur, was zu ändern ist.
static func pcsx2_vollbild(text: String) -> Array:
	var aus: Array = []
	var modus := _roh(Ini.ini_get(text, "EmuCore/GS", "FullscreenMode"))
	if modus.contains("x") and modus.contains("@"):
		aus.append(["EmuCore/GS", "FullscreenMode", "", "vollbild"])
	var ex := _roh(Ini.ini_get(text, "EmuCore/GS", "ExclusiveFullscreenControl"))
	if ex == "1" or (ex != "0" and _roh(Ini.ini_get(text, "EmuCore/GS", "Renderer")) == "14"):
		aus.append(["EmuCore/GS", "ExclusiveFullscreenControl", "0", "vollbild"])
	return aus


## Grafik von PCSX2 fürs Protokoll ([EmuCore/GS] Renderer, GSRendererType in Config.h).
static func pcsx2_renderer(text: String) -> String:
	var r := _roh(Ini.ini_get(text, "EmuCore/GS", "Renderer"))
	var namen := { "3": "Direct3D 11", "12": "OpenGL", "13": "Software", "14": "Vulkan", "15": "Direct3D 12" }
	return str(namen.get(r, "automatisch (bei NVIDIA, AMD und Intel Direct3D 12)"))


## Art des Emulators für die Regeln (Eden, Citron, Sudachi zählen wie yuzu).
static func art(emu_id: String, exe: String) -> String:
	var k := SpielerEmus.kind_of(emu_id, exe)
	return "yuzu" if Ini.YUZU_LIKE.has(k) else k


static func _roh(v: Variant) -> String:
	return "" if v == null else str(v).strip_edges().trim_prefix("\"").trim_suffix("\"").to_lower()


## Rein: was in diesem Text zu ändern ist. Rückgabe { text, keys: [{ section, key, old, new }],
## gesetzt: [Zwecke, die jetzt stimmen], fehlt: [Zwecke ohne Einstellung bei diesem Emulator] }.
static func plan(kind: String, text: String) -> Dictionary:
	var regeln: Array = REGELN.get(kind, [])
	var out := text
	var keys: Array = []
	var gesetzt: Array = []
	for r in regeln:
		var sec := str(r[0])
		var key := str(r[1])
		var cur: Variant = Ini.ini_get(out, sec, key)
		# Qt-Einstellungen (yuzu & Co.): mit „…\default=true“ gilt der Standard, nicht der Wert.
		var std: Variant = Ini.ini_get(out, sec, key + "\\default")
		var gilt := str(r[4]) if cur == null or _roh(std) == "true" else _roh(cur)
		if gilt != _roh(r[2]):
			keys.append({ "section": sec, "key": key, "old": cur, "new": str(r[2]) })
			out = Ini.ini_set(out, sec, key, str(r[2]))
		gesetzt.append(str(r[3]))
	var extra := { "text": out, "keys": keys, "gesetzt": gesetzt }
	if kind == "pcsx2":
		for r in pcsx2_vollbild(out):
			var cur: Variant = Ini.ini_get(out, str(r[0]), str(r[1]))
			keys.append({ "section": str(r[0]), "key": str(r[1]), "old": cur, "new": str(r[2]) })
			out = Ini.ini_set(out, str(r[0]), str(r[1]), str(r[2]))
		gesetzt.append("vollbild")
		extra["renderer"] = pcsx2_renderer(out)
	extra["text"] = out
	# Hält der Emulator ohne Fokus an, fehlt weder „pause“ noch „eingabe“ – er liest dann nichts mit.
	extra["fehlt"] = ZWECKE.filter(func(z: String) -> bool: return not gesetzt.has(z) and not gesetzt.has("anhalten"))
	extra["anhalten"] = gesetzt.has("anhalten")
	return extra


## Wo die Einstellungsdatei liegt (die zuletzt geschriebene der üblichen Orte, "" wenn keine).
static func datei(kind: String, exe: String, env: Dictionary, emu_id := "") -> String:
	var dir := exe.get_base_dir()
	match kind:
		"retroarch":
			var f: Array = SpielerEmus.files_for("retroarch", exe, "", env)
			return str(f[0][0]) if not f.is_empty() else ""
		"ppsspp":
			return Ini.newest([dir.path_join("memstick/PSP/SYSTEM/ppsspp.ini"), str(env.docs).path_join("PPSSPP/PSP/SYSTEM/ppsspp.ini")])
		"yuzu":
			var id := SpielerEmus.kind_of(emu_id, exe)
			if not Ini.YUZU_LIKE.has(id):
				id = "yuzu"
			var c := Ini.candidates(id, dir, str(env.docs), str(env.appdata), str(env.localappdata), Ini.is_portable(id, dir))
			return Ini.newest(c.get("ini", []))
		"pcsx2", "duckstation", "dolphin":
			var c := Ini.candidates(kind, dir, str(env.docs), str(env.appdata), str(env.localappdata), Ini.is_portable(kind, dir))
			return Ini.newest(c.get("core" if kind == "dolphin" else "ini", []))
	return ""


## Darf Uzai diese Datei anfassen? Bekannter Name, kein „..“, unter einem Ordner des Emulators,
## vorhanden und nicht riesig.
static func datei_ok(path: String, roots: Array) -> bool:
	return Sicher.datei_unter(path, roots, NAMEN, MAX_BYTES)


## Klartext fürs Protokoll (launch.log).
static func bericht(name: String, kind: String, gefunden: bool, p: Dictionary) -> String:
	if not REGELN.has(kind):
		return "%s: keine Einstellung für Weiterlaufen im Hintergrund bekannt – aufgestanden im Zimmer kann es anhalten oder den Controller mitlesen" % name
	if not gefunden:
		return "%s: Einstellungsdatei nicht gefunden – Weiterlaufen im Hintergrund nicht eingestellt" % name
	var teile := PackedStringArray()
	var keys: Array = p.get("keys", [])
	teile.append("läuft ohne Fokus weiter" if (p.gesetzt as Array).has("pause") else "")
	teile.append("hält ohne Fokus an (Controller im Hintergrund nicht abschaltbar) – weiter, sobald du wieder spielst"
			if (p.gesetzt as Array).has("anhalten") else "")
	teile.append("Controller nur mit Fokus" if (p.gesetzt as Array).has("eingabe") else "")
	teile.append("Vollbild randlos statt exklusiv" if (p.gesetzt as Array).has("vollbild") else "")
	teile.append(("Grafik " + str(p.renderer)) if p.has("renderer") else "")
	var was := ", ".join(PackedStringArray(Array(teile).filter(func(t: String) -> bool: return t != "")))
	var geaendert := ", ".join(PackedStringArray(keys.map(func(e: Dictionary) -> String: return "%s=%s" % [e.key, e.new])))
	var s := "%s: %s (%s)" % [name, was, ("geändert: " + geaendert + ", nach dem Spiel zurück") if geaendert != "" else "war schon so"]
	if (p.fehlt as Array).has("eingabe"):
		s += "; keine Einstellung gegen Controller im Hintergrund – aufgestanden kann das Spiel Eingaben mitlesen"
	return s


## Vor dem Start eines Emulators (Launcher). Rückgabe { done: [Dateien], log: Text }.
static func vor_start(emu_id: String, exe: String, name: String, env: Dictionary = {}) -> Dictionary:
	if Library.demo:
		return { "done": [], "log": "" }
	zurueck()
	var an: Variant = Config.get_value(KEY_AN, true)
	if (an is bool and not an) or exe == "":
		return { "done": [], "log": "" }
	if env.is_empty():
		env = SpielerEmus.env_now()
	var kind := art(emu_id, exe)
	var leer := { "text": "", "keys": [], "gesetzt": [], "fehlt": ZWECKE.duplicate() }
	if not REGELN.has(kind):
		return { "done": [], "log": bericht(name, kind, false, leer) }
	var path := datei(kind, exe, env, emu_id)
	var roots: Array = [exe.get_base_dir(), env.get("docs", ""), env.get("appdata", ""), env.get("localappdata", "")].filter(func(r): return str(r) != "")
	if not datei_ok(path, roots):
		return { "done": [], "log": bericht(name, kind, false, leer) }
	# Byte für Byte wie beim Zurückstellen (lesen_treu): fremde Kodierung oder Nullbyte → nicht anfassen, BOM bleibt.
	var roh := Ini.lesen_treu(path)
	if not bool(roh.ok):
		return { "done": [], "log": "%s: %s" % [name, Ini.FREMD_KODIERT % path.get_file()] }
	var text := str(roh.text)
	var p := plan(kind, text)
	var done: Array = []
	if str(p.text) != text:
		if Ini.write_text(path, str(p.text), bool(roh.bom)):
			done.append(path)
			Config.set_value(RESTORE_KEY, [{ "file": path, "keys": p.keys }])
			Config.save_settings()
		else:
			return { "done": [], "log": "%s: %s ist schreibgeschützt – Weiterlaufen im Hintergrund nicht eingestellt" % [name, path.get_file()] }
	return { "done": done, "log": bericht(name, kind, true, p), "anhalten": bool(p.get("anhalten", false)) }


## Nach dem Spiel und beim Start von Uzai (falls es vorher abgestürzt ist): alte Werte zurück – nur
## Schlüssel, die noch so aussehen, wie Uzai sie geschrieben hat. Zahl der zurückgestellten Dateien.
static func zurueck() -> int:
	var list: Variant = Config.get_value(RESTORE_KEY, [])
	if not (list is Array) or (list as Array).is_empty():
		return 0
	var n := 0
	# Die Liste liegt in den Einstellungen (und damit in Sicherungen): nur erlaubte Dateien unter den Ordnern eines
	# eingerichteten Emulators oder Dokumente/AppData, lokal, nicht riesig (Sicher.datei_unter, wie vor_start).
	var env := SpielerEmus.env_now()
	var roots: Array = [env.get("docs", ""), env.get("appdata", ""), env.get("localappdata", "")]
	for emu in Config.emulators():
		if emu is Dictionary and str(emu.get("exe", "")) != "":
			roots.append(str(emu.exe).get_base_dir())
	for e in list:
		if not (e is Dictionary) or not (e.get("keys") is Array):
			continue
		var path := str(e.get("file", ""))
		if not datei_ok(path, roots):
			continue
		# Byte für Byte lesen und schreiben (lesen_treu): Eine Datei mit fremder Kodierung oder Nullbyte fasst Uzai nicht an.
		var roh := Ini.lesen_treu(path)
		if not bool(roh.ok):
			continue
		var text := str(roh.text)
		var back := Ini.undo_text(text, { "keys": e.keys })
		if back != text and Ini.write_text(path, back, bool(roh.bom)):
			n += 1
	Config.set_value(RESTORE_KEY, [])
	Config.save_settings()
	return n
