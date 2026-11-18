extends "res://src/ui/layers/dialog.gd"
## Einmal beim ersten Öffnen eines Mosaiks (mosaik_seite.gd): was man daraus machen kann – Raster,
## Kacheln verschieben und vergrößern, eigene Bilder und Ordner, Hintergrund – und wie man anfängt
## (A halten oder Menü). „Gestalten“ schaltet das Gestalten gleich ein. Danach nie wieder
## (Config KEY); in Rundgängen und Proben (--uzai-…) kommt er nicht von selbst.

const KEY := "mosaik.einfuehrung"

## Zeichen und Zeile je Möglichkeit.
const ZEILEN := [
	["grid", "Raster von 2 × 2 bis 10 × 10"],
	["move", "Kacheln verschieben und größer ziehen"],
	["image", "Eigene Bilder, Ordner und Hintergrund"],
	["palette", "A halten oder Menü: gestalten"],
]

var los: Callable              ## „Gestalten“: schaltet das Gestalten im Mosaik ein


## Kommt die Einführung? Nur einmal und nie in automatischen Rundgängen.
static func faellig() -> bool:
	if bool(Config.get_value(KEY, false)):
		return false
	return not Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--uzai-"))


func fill() -> void:
	heading = "Dein Raster"
	icon_name = ""
	buttons = [["Gestalten", func() -> void:
		if los.is_valid():
			los.call()
	], ["Später", Callable()]]
	Config.set_value(KEY, true)
	Config.save_soon()
	super()
	if not is_instance_valid(panel) or not panel.visible:
		return
	var liste := U.vbox(14)
	for z in ZEILEN:
		var reihe := U.hbox(16)
		var ic := U.icon(str(z[0]), 26, "accent")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reihe.add_child(ic)
		reihe.add_child(U.label(str(z[1]), "m", "text", "regular"))
		liste.add_child(reihe)
	box.add_child(liste)
	# Vor die Knopfzeile (das letzte Kind), mit Luft davor.
	box.move_child(liste, box.get_child_count() - 3)
