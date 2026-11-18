extends "res://src/ui/sections/section.gd"
## Zimmer (App oben in der Leiste, Symbol Sofa): der Einstieg in „Dein Zimmer“ (3D,
## src/room/zimmer.gd). A auf dem Symbol öffnet es gleich; hier (main.goto("room")) ist die ganze Fläche
## eine Tür dorthin (zimmer_tuer.gd: eine Hand drückt sie auf, die Kamera geht hindurch ins Zimmer). Im
## Zimmer behalten LT/RT, LB/RB und B ihre eigene Belegung; A betritt es, B dort führt hierher zurück.

const ZimmerTuer := preload("res://src/ui/components/zimmer_tuer.gd")

## Die Tür deckt die ganze Fläche: beim Wechsel mit LT/RT geht sie sofort statt zu kreuzen (main.gd).
var ganze_flaeche := true


func _init() -> void:
	super()
	id = "room"
	title = "Zimmer"
	icon_name = "room"


func build() -> void:
	mark_built()
	U.clear(self)
	var t = ZimmerTuer.new().setup("Dein Zimmer")
	t.set_meta("uz_key", "room:betreten")
	t.set_meta("uz_hint_a", "Betreten")
	t.set_meta("uz_default", true)
	t.set_meta("uz_entry", true)
	U.full_rect(t)
	t.chosen.connect(func(_k: String) -> void: main.open_room())
	add_child(t)
