extends RefCounted
## Kacheln im Guide selbst wählen (Punkt 20): die vier Plätze vorn im Reiter Spiel. Je Platz eine
## Handlung aus GuideGame.CHOICES oder „Automatisch“ (wie bisher: was gerade am wichtigsten ist).
## Dazu „Passend zur Lage“ (Punkt 102). Offen über Einstellungen → Im Spiel → Kacheln im Guide und
## im Guide unter „Mehr“ – beides dieselbe Seitenleiste, ganz mit dem Controller.

const GuideGame := preload("res://src/ui/components/guide_game.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const ListItem := preload("res://src/ui/components/list_item.gd")
const Main := preload("res://src/main.gd")


static func name_of(id: String) -> String:
	for c in GuideGame.CHOICES:
		if str(c[0]) == id:
			return str(c[1])
	return "Automatisch"


static func icon_of(id: String) -> String:
	for c in GuideGame.CHOICES:
		if str(c[0]) == id:
			return str(c[2])
	return "spark"


## Eine Zeile für Einstellungen und „Mehr“: „Automatisch“ oder die gewählten Namen.
static func summary(pins: Array = []) -> String:
	var p := pins if not pins.is_empty() else GuideGame.pins()
	var names: Array = p.filter(func(x): return str(x) != "").map(func(x): return TranslationServer.translate(name_of(str(x))))
	if names.is_empty():
		return "Automatisch"
	return ", ".join(PackedStringArray(names))


## Platz i auf id setzen. Stand dieselbe Handlung schon auf einem anderen Platz, wird der frei
## (automatisch) – jede Kachel nur einmal.
static func set_slot(pins: Array, i: int, id: String) -> Array:
	var out := pins.duplicate()
	while out.size() < GuideGame.PRIMARY_MAX:
		out.append("")
	if id != "":
		for j in out.size():
			if j != i and str(out[j]) == id:
				out[j] = ""
	out[i] = id
	return out


## Seitenleiste öffnen. done: nach jeder Änderung (der Guide baut seine Reihe neu).
static func open(main: Main, done := Callable()) -> Control:
	var s = Sheet.new()
	s.setup("Kacheln im Guide", "", 680)
	s.set_meta("uz_key", "guide:tiles")
	if Launcher.guide_open:
		s.set_meta("uz_hints_center", true)
	s.fill_func = func(sheet) -> void:
		var pins := GuideGame.pins()
		for i in pins.size():
			var id := str(pins[i])
			var r = ListItem.new()
			r.setup(name_of(id) if id != "" else "Automatisch", "", "Platz %d" % (i + 1))
			r.icon_name = icon_of(id) if id != "" else "grid"
			r.sub_color = "faint"
			r.set_meta("uz_key", "tile:%d" % i)
			r.set_meta("uz_hint_a", "Ändern")
			if i == 0:
				r.set_meta("uz_default", true)
			var slot := i
			r.activated.connect(func() -> void: _pick(main, sheet, slot, done))
			sheet.add_row(r)
		sheet.add_gap(10)
		var smart := bool(Config.get_value("system.guide_smart", true))
		var sm = ListItem.new()
		sm.setup("Passend zur Lage", "", "An" if smart else "Aus")
		sm.icon_name = "spark"
		sm.set_meta("uz_key", "tile:smart")
		sm.set_meta("uz_hint_a", "Ausschalten" if smart else "Einschalten")
		sm.activated.connect(func() -> void:
			Config.set_value("system.guide_smart", not smart)
			sheet.refill()
			if done.is_valid():
				done.call()
		)
		sheet.add_row(sm)
		if pins.any(func(x): return str(x) != ""):
			var rs = ListItem.new()
			rs.setup("Alle automatisch", "", "")
			rs.icon_name = "refresh"
			rs.set_meta("uz_key", "tile:reset")
			rs.activated.connect(func() -> void:
				Config.set_value("system.guide_tiles", [])
				sheet.refill()
				if done.is_valid():
					done.call()
			)
			sheet.add_row(rs)
		sheet.add_gap(8)
	main.open_layer(s)
	return s


static func _pick(main: Main, sheet: Control, slot: int, done: Callable) -> void:
	var pins := GuideGame.pins()
	var opts: Array = [["", "Automatisch"]]
	for c in GuideGame.CHOICES:
		var where := pins.find(str(c[0]))
		opts.append([str(c[0]), str(c[1]), ("auf Platz %d" % (where + 1)) if where >= 0 and where != slot else ""])
	main.open_choice("Platz %d" % (slot + 1), opts, str(pins[slot]), func(v: Variant) -> void:
		Config.set_value("system.guide_tiles", set_slot(GuideGame.pins(), slot, str(v)))
		if is_instance_valid(sheet):
			sheet.refill()
		if done.is_valid():
			done.call()
	)
