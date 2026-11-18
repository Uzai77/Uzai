extends RefCounted
## Bildschirm: auf welchem Uzai läuft und dass das Bild dort scharf ist (Meldung vom PC, 12.11.:
## „Text pixelig, wenn man Uzai auf den anderen Monitor zieht“). Reine Logik, testbar
## (tests/logic_bildschirmwahl.gd); die Aufrufer sind remote.gd (Neustart), main_fenster.gd (Wechsel)
## und die Einstellungen unter Aussehen.
##
## 1. Wahl: display.screen = "auto" (Hauptbildschirm, wie Windows ihn nennt) oder "1", "2", … (die
##    Nummer aus der Liste der Einstellungen). Gibt es die Nummer nicht mehr, gilt "auto".
## 2. Schärfe: Godot meldet sich bei Windows nur mit der Skalierung des Hauptbildschirms an
##    (PROCESS_SYSTEM_DPI_AWARE, kein WM_DPICHANGED). Auf einem Bildschirm mit anderer Skalierung
##    (4K-Fernseher mit 300 % neben einem Monitor mit 100 %) rechnet Uzai dann in zu wenigen
##    Bildpunkten, und Windows zieht das Bild groß. Die Skalierung der einzelnen Bildschirme sieht so
##    ein Prozess gar nicht (GetDpiForMonitor nennt ihm überall dieselbe). Abhilfe ohne Eingriff in
##    Windows: Sind mehrere Bildschirme angeschlossen, startet Uzai sich einmal selbst neu, mit der
##    Umgebungsvariable __COMPAT_LAYER=HighDpiAware – sie gilt nur für diesen einen Prozess und
##    entspricht „Hohe DPI-Skalierung überschreiben: Anwendung“ in den Eigenschaften der Datei. Dann
##    rechnet Uzai auf jedem Bildschirm in dessen echten Bildpunkten, auch nach dem Verschieben.
##    Das neue Uzai nimmt die Variable sofort wieder aus seiner Umgebung (start()), damit Helfer und
##    Spiele sie nicht erben. Stellt es fest, dass alle Bildschirme gleich skaliert sind, merkt es
##    sich deren Anordnung (display.dpi_gleich) – der Neustart entfällt dann beim nächsten Mal.
##    Nicht im Sicheren Modus, nicht in Proben; abschaltbar mit display.dpi_eigen = false.
## 3. Größe der Oberfläche: je Bildschirm gemerkt (display.skalen). Wechselt Uzai auf einen
##    Bildschirm, den es noch nicht kennt, stellt es sich dafür ein wie beim ersten Start
##    (display_fit.gd); auf einem bekannten gilt wieder die Größe von dort.

const AUTO := "auto"
## Compat-Schicht von Windows für „Skalierung durch: Anwendung“ und die Variable, die sie einem
## neuen Prozess mitgibt.
const SCHICHT := "HighDpiAware"
const VARIABLE := "__COMPAT_LAYER"
## Beweis für das neue Uzai, dass es mit der Schicht gestartet wurde (nur dann stimmt „eigen“).
const BEWEIS := "UZAI_DPI_EIGEN"
## So viele gemerkte Größen höchstens (ein Eintrag je Bildschirm, den Uzai gesehen hat).
const SKALEN_MAX := 12

## Dieser Lauf rechnet auf jedem Bildschirm in dessen eigenen Bildpunkten (start()).
static var eigen := false


## Ganz am Anfang (config.gd, vor dem ersten Kindprozess): Wurde dieses Uzai mit der Schicht
## gestartet? Dann merken und beide Variablen wieder aus der Umgebung nehmen.
static func start() -> void:
	if OS.get_environment(BEWEIS) != "1":
		return
	eigen = true
	OS.unset_environment(BEWEIS)
	var rest := schicht_weg(OS.get_environment(VARIABLE))
	if rest == "":
		OS.unset_environment(VARIABLE)
	else:
		OS.set_environment(VARIABLE, rest)


## Vor jedem Start eines neuen Uzai aus diesem heraus: Soll es scharf rechnen, bekommt es Schicht
## und Beweis mit. Danach nach_neustart(), falls dieses Uzai noch etwas anderes startet.
static func vor_neustart(an: bool) -> void:
	if not an:
		return
	OS.set_environment(VARIABLE, schicht_dazu(OS.get_environment(VARIABLE)))
	OS.set_environment(BEWEIS, "1")


static func nach_neustart() -> void:
	if OS.get_environment(BEWEIS) != "1":
		return
	OS.unset_environment(BEWEIS)
	var rest := schicht_weg(OS.get_environment(VARIABLE))
	if rest == "":
		OS.unset_environment(VARIABLE)
	else:
		OS.set_environment(VARIABLE, rest)


## Die Schicht an einen vorhandenen Wert der Variable hängen (andere Schichten bleiben).
static func schicht_dazu(wert: String) -> String:
	var teile := _teile(wert)
	if not teile.any(func(t: String) -> bool: return t.to_lower() == SCHICHT.to_lower()):
		teile.append(SCHICHT)
	return " ".join(PackedStringArray(teile))


## Die Schicht wieder herausnehmen; was sonst darin stand, bleibt.
static func schicht_weg(wert: String) -> String:
	var teile := _teile(wert).filter(func(t: String) -> bool: return t.to_lower() != SCHICHT.to_lower())
	return " ".join(PackedStringArray(teile))


static func _teile(wert: String) -> Array:
	var out: Array = []
	for t in wert.split(" ", false):
		out.append(str(t))
	return out


## Soll sich Uzai für ein scharfes Bild einmal selbst neu starten? windows: läuft unter Windows mit
## Fenster; anzahl: Bildschirme; an: display.dpi_eigen; args: Startparameter nach „--“;
## gleich: die gemerkte Anordnung, bei der alle gleich skaliert waren; jetzt: die Anordnung jetzt.
static func neustart_noetig(windows: bool, anzahl: int, an: bool, args: Array, gleich: String, jetzt: String) -> bool:
	if not windows or eigen or not an or anzahl < 2:
		return false
	for a in args:
		var s := str(a)
		if s in ["--sicherer-modus", "--demo"] or s.begins_with("--uzai-"):
			return false
	return gleich == "" or gleich != jetzt


## Die Anordnung der Bildschirme als Text: Lage und Größe, wie Uzai sie sieht. Rechnet Windows einen
## Bildschirm um (andere Skalierung), ändern sich seine Zahlen – dann passt die gemerkte nicht mehr.
static func anordnung(flaechen: Array) -> String:
	var teile := PackedStringArray()
	for f in flaechen:
		if f is Rect2i:
			var r := f as Rect2i
			teile.append("%d,%d,%dx%d" % [r.position.x, r.position.y, r.size.x, r.size.y])
	return ";".join(teile)


## Sind alle Bildschirme gleich skaliert? (dpis: je Bildschirm; nur im scharfen Lauf verlässlich.)
static func gleich_skaliert(dpis: Array) -> bool:
	for d in dpis:
		if int(d) != int(dpis[0]):
			return false
	return not dpis.is_empty()


## Die Wahl als Bildschirmnummer von Godot (0 …) oder -1: „automatisch“ bzw. eine Nummer, die es
## nicht (mehr) gibt.
static func index(wahl: Variant, anzahl: int) -> int:
	var s := str(wahl).strip_edges()
	if not s.is_valid_int():
		return -1
	var n := int(s)
	return n - 1 if n >= 1 and n <= anzahl else -1


## Zeilen für die Einstellungen: [["auto", "Automatisch"], ["1", "1 · 3840 × 2160 · Hauptbildschirm"], …].
## groessen: je Bildschirm die Größe in Bildpunkten; haupt: Nummer (0 …) des Hauptbildschirms.
static func wahl_liste(groessen: Array, haupt: int, wort_auto: String, wort_haupt: String) -> Array:
	var out: Array = [[AUTO, wort_auto]]
	for i in groessen.size():
		var g: Vector2i = groessen[i]
		var t := "%d  ·  %d × %d" % [i + 1, g.x, g.y]
		if i == haupt:
			t += "  ·  " + wort_haupt
		out.append([str(i + 1), t])
	return out


## Startparameter der Engine ohne „--screen <n>“ (kommt beim Neustart aus der Einstellung neu dazu).
static func ohne_schirm(args: Array) -> Array:
	var out: Array = []
	var weg := false
	for a in args:
		if weg:
			weg = false
			continue
		if str(a) == "--screen":
			weg = true
			continue
		out.append(a)
	return out


## Startparameter der Engine für ein neues Uzai: mit dem gewählten Bildschirm, wenn einer gewählt ist.
static func mit_schirm(args: Array, wahl: Variant, anzahl: int) -> Array:
	var out := ohne_schirm(args)
	var i := index(wahl, anzahl)
	if i >= 0:
		out.append_array(["--screen", str(i)])
	return out


## Unter diesem Namen merkt sich Uzai die Größe der Oberfläche für einen Bildschirm.
static func schluessel(groesse: Vector2i, dpi: int) -> String:
	return "%dx%d@%d" % [groesse.x, groesse.y, dpi]


## Die gemerkten Größen mit einem neuen Eintrag; über SKALEN_MAX fällt der älteste weg.
static func skala_merken(skalen: Dictionary, key: String, wert: float) -> Dictionary:
	var out := {}
	for k in skalen:
		if str(k) != key and (skalen[k] is float or skalen[k] is int):
			out[str(k)] = clampf(float(skalen[k]), 0.6, 2.0)
	while out.size() >= SKALEN_MAX:
		out.erase(out.keys()[0])
	out[key] = clampf(wert, 0.6, 2.0)
	return out


## Die gemerkte Größe für einen Bildschirm oder 0, wenn Uzai ihn noch nicht kennt.
static func skala_von(skalen: Variant, key: String) -> float:
	if not (skalen is Dictionary) or not (skalen as Dictionary).has(key):
		return 0.0
	var v: Variant = (skalen as Dictionary)[key]
	return clampf(float(v), 0.6, 2.0) if (v is float or v is int) else 0.0
