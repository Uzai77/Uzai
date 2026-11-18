extends RefCounted
## „Spielstände“ eines Emulatorspiels (src/core/quick_resume.gd): oben die Stände vom Beenden,
## darunter die selbst gesicherten – je mit dem Bild vom Moment und der Zeit. Auf der Spielseite
## startet A das Spiel mit diesem Stand, im Guide holt A ihn ins laufende Spiel. Y entfernt einen
## Stand aus Uzais Ablage (nach Rückfrage); Spielstände des Emulators fasst Uzai nie an.

const Sheet := preload("res://src/ui/layers/sheet.gd")
const ListItemC := preload("res://src/ui/components/list_item.gd")
const QuickResume := preload("res://src/core/quick_resume.gd")
const Main := preload("res://src/main.gd")

const THUMB := Vector2(192, 108)


## Liste öffnen. mode: "start" (Spielseite) oder "laden" (Guide, das Spiel läuft).
## on_pick(rec) bekommt den gewählten Stand; die Liste ist dann schon zu.
static func open_for(main: Main, g: Dictionary, mode: String, on_pick: Callable) -> Control:
	var s = Sheet.new()
	s.setup("Spielstände", Library.display_title(g), 820)
	s.subheading_raw = true      # Name des Spiels
	s.fill_func = func(sheet) -> void: fill(sheet, main, g, mode, on_pick)
	main.open_layer(s)
	return s


static func fill(sheet, main: Main, g: Dictionary, mode: String, on_pick: Callable) -> void:
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var autos := QuickResume.states(g, "auto")
	var owns := QuickResume.states(g, "own")
	if autos.is_empty() and owns.is_empty():
		sheet.add_label("Noch keine Spielstände. Beim Beenden über den Guide merkt sich Uzai die Stelle, im Spiel sichert Guide → Sichern weitere.", "m", "muted")
		return
	if mode == "laden":
		sheet.add_label("Das Spiel springt zu diesem Stand. Was seit dem letzten Sichern passiert ist, geht dabei verloren.", "s", "faint")
		sheet.add_gap(4)
	if not autos.is_empty():
		sheet.add_label("Beim Beenden gemerkt")
		for r in autos:
			sheet.add_row(_row(sheet, main, g, r, mode, on_pick, now, bias))
	if not owns.is_empty():
		if not autos.is_empty():
			sheet.add_gap()
		sheet.add_label("Selbst gesichert  ·  %d von %d" % [owns.size(), QuickResume.OWN_MAX])
		for r in owns:
			sheet.add_row(_row(sheet, main, g, r, mode, on_pick, now, bias))


static func _row(sheet, main: Main, g: Dictionary, rec: Dictionary, mode: String, on_pick: Callable, now: int, bias: int) -> Control:
	var it = ListItemC.new()
	# Die Art steht schon in der Abschnittszeile darüber: unten nur, wie lange es her ist (nicht
	# „gestern“ unter „Gestern, 18:25“).
	var ago := QuickResume.ago_short(now - int(rec.get("at", now)))
	it.setup(QuickResume.when_text(int(rec.get("at", now)), now, bias), "" if ago == "gestern" else ago)
	it.image_size = THUMB
	it.min_h = 124
	var shot := str(rec.get("shot", ""))
	if shot != "" and FileAccess.file_exists(shot):
		it.image_url = shot
	else:
		it.icon_name = "save"
	it.set_meta("uz_key", "st:" + str(rec.get("id", "")))
	it.set_meta("uz_hint_a", "Von hier starten" if mode == "start" else "Laden")
	it.set_meta("uz_hint_y", "Entfernen")
	it.set_meta("uz_on_y", func() -> void: _ask_remove(sheet, main, g, rec))
	it.activated.connect(func() -> void:
		sheet.close()
		on_pick.call(rec)
	)
	return it


## Nur Uzais Kopie fliegt; der Platz im Emulator bleibt, wie er ist.
static func _ask_remove(sheet, main: Main, g: Dictionary, rec: Dictionary) -> void:
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	main.open_dialog("Spielstand entfernen?", "%s\nNur Uzais Kopie geht, die Spielstände im Emulator bleiben." % QuickResume.when_text(int(rec.get("at", now)), now, bias), [
		["Entfernen", func() -> void:
			QuickResume.remove(str(g.get("id", "")), str(rec.get("id", "")))
			if is_instance_valid(sheet):
				sheet.refill(), "danger"],
		["Behalten", func() -> void: pass],
	], "trash")
