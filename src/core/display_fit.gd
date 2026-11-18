extends RefCounted
## Uzai stellt sich selbst ein (Punkt 96): Fernseher, Monitor oder Laptop, Bildwiederholrate und
## HDR des Bildschirms, auf dem Uzai liegt. Daraus Startwerte für die Größe der Oberfläche und die
## Bildrate im Menü – beides jederzeit unter Einstellungen → Aussehen änderbar. Beim ersten
## Start einmal von selbst (main), danach nur auf Wunsch („Automatisch einstellen“). An Windows
## selbst ändert Uzai nichts.
##
## Woher: Name, Anschluss und HDR liest der Windows-Helfer aus der Bildschirmkonfiguration von
## Windows, die Bildgröße aus den Gerätedaten (EDID) des Bildschirms (display-info). Meldet das
## Gerät nichts Brauchbares (oder fehlt der Helfer), bleibt alles, wie es ist – lieber nichts
## als geraten. Tastensymbole wählt Nav.glyph_set() schon am Namen des Controllers.
## Handhelds (Steam Deck, ROG Ally, Legion Go, MSI Claw …) erkennt handheld.gd am Gerätenamen aus
## dem BIOS und an der Größe des eingebauten Bildschirms; sie bekommen 140–150 %.

## Uzai ist für einen Fernseher um 55 Zoll in etwa 2,5 m Abstand gebaut (100 %). Am Schreibtisch
## (60–80 cm vor dem Bildschirm) wirkt dieselbe Oberfläche gut anderthalbmal so groß; ein kleiner
## Fernseher auf Sofa-Abstand zeigt sie kleiner. Die Werte liegen im Bereich des Reglers.
const SCALE := { "tv": 1.0, "tv_klein": 1.1, "monitor": 0.85, "monitor_gross": 0.9, "laptop": 0.9 }
const TV_SMALL_IN := 43.0
const MONITOR_BIG_IN := 32.0
const TV_MIN_IN := 40.0
## Sinnvolle Bildgrößen; Fernseher melden oft nur das Seitenverhältnis (16 × 9 cm) oder 0.
const PLAUSIBLE_IN := Vector2(10.0, 120.0)
## Über dieser Bildwiederholrate läuft das Menü mit der halben Rate: jedes Bild bleibt genau zwei
## Bildwechsel stehen (ohne Ruckeln), und ein 240-Hz-Monitor rechnet nicht 240 Menübilder je Sekunde.
const FULL_RATE_MAX_HZ := 144.0
const HALF_RATE_MIN_FPS := 100

const Handheld := preload("res://src/core/handheld.gd")
const KIND_NAMES := { "tv": "Fernseher", "monitor": "Monitor", "laptop": "Laptop-Bildschirm", "handheld": "Handheld" }
const KIND_DONE := { "tv": "Für deinen Fernseher eingestellt", "monitor": "Für deinen Monitor eingestellt", "laptop": "Für deinen Laptop eingestellt",
		"handheld": "Für deinen Handheld eingestellt" }
const TECHS := ["hdmi", "dp", "intern", "drahtlos", "anders"]

## Fernseher nennen sich in ihren Gerätedaten meist so: „LG TV SSCR2“, „SONY TV“, „Panasonic-TV“,
## „Philips FTV“ – oder nur mit dem Markennamen („SAMSUNG“), Monitore dagegen mit Modellnamen.
static var _tv_word := RegEx.create_from_string("(?i)(^|[^a-z])(tv|ftv|bravia)([^a-z]|$)")
static var _brand_only := RegEx.create_from_string("(?i)^\\s*(samsung|hisense|vizio|tcl|sharp|toshiba|grundig|metz|loewe)\\s*$")


## Bildschirmdiagonale in Zoll aus der Bildgröße in cm; 0, wenn die Angabe nicht passt.
static func inches(w_cm: float, h_cm: float) -> float:
	var d := sqrt(w_cm * w_cm + h_cm * h_cm) / 2.54
	return d if d >= PLAUSIBLE_IN.x and d <= PLAUSIBLE_IN.y else 0.0


## „tv“, „monitor“, „laptop“ oder "" (unklar – dann stellt Uzai nichts um).
static func kind_of(seen: Dictionary) -> String:
	if str(seen.get("handheld", "")) != "":
		return "handheld"
	if str(seen.get("tech", "")) == "intern":
		return "laptop"
	var name := str(seen.get("name", ""))
	var d := inches(float(seen.get("w_cm", 0)), float(seen.get("h_cm", 0)))
	if _tv_word.search(name) != null:
		return "tv"
	if _brand_only.search(name) != null and (d == 0.0 or d >= MONITOR_BIG_IN):
		return "tv"
	if d >= TV_MIN_IN:
		return "tv"
	if d > 0.0:
		return "monitor"
	return ""


## Größe der Oberfläche für diesen Bildschirm (1.0 = Uzais Standard).
static func scale_for(kind: String, inch: float) -> float:
	match kind:
		"tv":
			return SCALE.tv_klein if inch > 0.0 and inch < TV_SMALL_IN else SCALE.tv
		"monitor":
			return SCALE.monitor_gross if inch >= MONITOR_BIG_IN else SCALE.monitor
		"laptop":
			return SCALE.laptop
		"handheld":
			return Handheld.skala_fuer(inch if inch > 0.0 else 7.0)
	return 1.0


## Obergrenze für Bilder je Sekunde im Menü (0 = so viele, wie der Bildschirm zeigt).
## mode: „auto“ oder „voll“ (Einstellungen → Aussehen → Bildrate im Menü).
static func menu_fps(hz: float, mode: String) -> int:
	if mode == "voll" or hz <= FULL_RATE_MAX_HZ:
		return 0
	var half := roundi(hz / 2.0)
	return half if half >= HALF_RATE_MIN_FPS else 0


## Kurz, was Uzai erkannt hat: „Fernseher · 55″ · 120 Hz · HDR an“. "" ohne Erkennung.
## brief: nur Art und Größe („Fernseher · 55″“), für enge Stellen.
static func summary(seen: Dictionary, brief := false) -> String:
	var parts := PackedStringArray()
	var kind := kind_of(seen)
	if kind == "handheld" and str(seen.get("geraet", "")) not in ["", "Handheld"]:
		parts.append(str(seen.geraet))
	elif kind != "":
		parts.append(TranslationServer.translate(KIND_NAMES[kind]))
	var d := inches(float(seen.get("w_cm", 0)), float(seen.get("h_cm", 0)))
	if d > 0.0:
		parts.append("%d″" % roundi(d))
	if brief:
		return "  ·  ".join(parts)
	var hz := float(seen.get("hz", 0.0))
	if hz > 0.0:
		parts.append("%d Hz" % roundi(hz))
	match str(seen.get("hdr", "")):
		"an":
			parts.append(TranslationServer.translate("HDR an"))
		"moeglich":
			parts.append(TranslationServer.translate("HDR möglich (in Windows aus)"))
	return "  ·  ".join(parts)


## Antwort des Helfers auf das Nötige beschränken (Name gekürzt, Anschluss nur bekannte Werte).
static func clean(raw: Dictionary) -> Dictionary:
	var tech := str(raw.get("tech", ""))
	var hdr := str(raw.get("hdr", ""))
	return {
		"name": str(raw.get("name", "")).strip_edges().left(64),
		"tech": tech if tech in TECHS else "",
		"w_cm": clampi(int(raw.get("w_cm", 0)), 0, 1000),
		"h_cm": clampi(int(raw.get("h_cm", 0)), 0, 1000),
		"hdr": hdr if hdr in ["an", "moeglich", "nein"] else "",
	}


# --- Erkennen und einstellen (braucht das Fenster und den Helfer) ------------------------------

## Den Bildschirm unter Uzais Fenster ansehen. Ohne Helfer nur die Bildwiederholrate (und was
## Godots Gerätename über einen Handheld verrät).
static func detect(window: Window) -> Dictionary:
	var seen := { "hz": DisplayServer.screen_get_refresh_rate(window.current_screen) }
	if Helper.available:
		var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())
		var r: Dictionary = await Helper.run("display-info", { "hwnd": hwnd }, 8.0)
		var res: Variant = r.get("result")
		if bool(r.get("ok", false)) and res is Dictionary and bool((res as Dictionary).get("ok", false)):
			seen.merge(clean(res))
		var g: Dictionary = await Helper.run("geraet-info", {}, 6.0)
		var gres: Variant = g.get("result")
		if bool(g.get("ok", false)) and gres is Dictionary and bool((gres as Dictionary).get("ok", false)):
			seen.merge(Handheld.clean_info(gres))
	mark_handheld(seen, OS.get_model_name())
	return seen


## Handheld eintragen ({ handheld: Kennung, geraet: Name }) und für diese Sitzung merken.
static func mark_handheld(seen: Dictionary, model: String) -> void:
	var hh := Handheld.vom_start(seen, model)
	seen.erase("handheld")
	seen.erase("geraet")
	if not hh.is_empty():
		seen["handheld"] = str(hh.id)
		seen["geraet"] = str(hh.name)


## Startwerte aus dem Erkannten setzen. Gibt die Art zurück ("" = nichts umgestellt).
## only_default: beim ersten Start nur, was noch auf Uzais Standard steht.
static func apply(seen: Dictionary, only_default: bool) -> String:
	Config.set_value("display.seen", seen)
	var kind := kind_of(seen)
	if kind == "":
		return ""
	var sc := scale_for(kind, inches(float(seen.get("w_cm", 0)), float(seen.get("h_cm", 0))))
	# Handheld ohne gemeldete Größe: die bekannte des Geräts (Legion Go 8,8″ → 140 %).
	if kind == "handheld" and not Handheld.aktiv.is_empty():
		sc = float(Handheld.aktiv.skala)
	if not only_default or is_equal_approx(float(Config.get_value("theme.ui_scale", 1.0)), 1.0):
		Config.set_value("theme.ui_scale", sc)
	return kind
