extends "res://src/ui/layers/sheet.gd"
## Ordner oder Datei auswählen – komplett mit dem Controller, ohne Windows-Dialog.
## Oben steht der Weg als ruhige Zeile („Laufwerke › D: › Spiele“), ganz oben in der Liste die
## Schnellziele (zuletzt benutzt, Downloads, Desktop, Dokumente). Leere Ordner sagen, was gesucht wird.

signal picked(path: String)

var want_dir := false
var exts: Array = []
var start_dir := ""
var _dir := ""
var _crumb: Label


func build() -> void:
	setup(heading, "", 900)
	_dir = start_dir if start_dir != "" and DirAccess.dir_exists_absolute(start_dir) else str(Config.get_value("system.last_dir", ""))
	if _dir == "" or not DirAccess.dir_exists_absolute(_dir):
		_dir = ""
	_update_b()
	super()


## Wie auf einer Konsole: B geht eine Ordnerebene hoch (bei den Laufwerken: schließen), Y bricht
## gleich ganz ab.
func _update_b() -> void:
	set_meta("uz_hint_b", "Ordner hoch" if _dir != "" else "Abbrechen")
	var hints: Array = []
	if _dir != "":
		hints.append(["y", "Abbrechen"])
		if want_dir:
			hints.append(["x", "Diesen Ordner nehmen"])
	set_meta("uz_hints", hints)


func fill() -> void:
	if _dir != "":
		_crumb = U.label(_crumb_text(), "m", "muted", "medium", true)
		add_row(_crumb)
		add_gap(4)
	if want_dir and _dir != "":
		var take = SettingRow.new()
		take.setup("action", "Diesen Ordner nehmen")
		take.icon_name = "check"
		take.value_text = _dir.get_file() if _dir.get_file() != "" else _dir
		take.set_meta("uz_default", true)
		take.set_meta("uz_hint_a", "Nehmen")
		take.set_meta("uz_hint_x", "—")
		take.on_activate = func() -> void: _pick(_dir)
		add_row(take)
	if _dir != "":
		var parent := _parent_of(_dir)
		var up = _item("Eine Ebene höher", parent.get_file() if parent != "" and parent.get_file() != "" else ("Laufwerke" if parent == "" else parent),
				"chevron_left")
		up.activated.connect(_go_up)
		add_row(up)
	if _dir == "":
		_fill_roots()
		return
	var da := DirAccess.open(_dir)
	if da == null:
		add_label("Dieser Ordner lässt sich nicht öffnen.", "m", "muted")
		return
	da.include_hidden = false
	var dirs := Array(da.get_directories())
	dirs.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	var shown_dirs := 0
	for d in dirs:
		if str(d).begins_with("$") or str(d).begins_with("."):
			continue
		var it = _item(d, "", "folder", true)
		var target := _dir.path_join(d)
		it.activated.connect(func() -> void: _open(target))
		add_row(it)
		shown_dirs += 1
	var shown := 0
	if not want_dir:
		var files := Array(da.get_files())
		files.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
		for f in files:
			if not exts.is_empty() and not (str(f).get_extension().to_lower() in exts):
				continue
			var it = _item(f, "", "image" if str(f).get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"] else "file", true)
			var target2 := _dir.path_join(f)
			it.set_meta("uz_hint_a", "Auswählen")
			it.activated.connect(func() -> void: _pick(target2))
			add_row(it)
			shown += 1
			if shown > 600:
				add_label("… und weitere Dateien", "s", "faint")
				break
	if shown_dirs == 0 and shown == 0:
		add_gap(10)
		var what := "Hier liegen keine Unterordner." if want_dir else ("Hier liegt nichts Passendes. Gesucht: %s." % ", ".join(PackedStringArray(exts))
				if not exts.is_empty() else "Dieser Ordner ist leer.")
		add_label(what, "m", "muted")


## Laufwerke und Schnellziele.
func _fill_roots() -> void:
	var quick: Array = []
	var last := str(Config.get_value("system.last_dir", ""))
	if last != "" and DirAccess.dir_exists_absolute(last):
		quick.append(["Zuletzt benutzt", last, "history"])
	for spec in [[OS.SYSTEM_DIR_DOWNLOADS, "Downloads", "download"], [OS.SYSTEM_DIR_DESKTOP, "Desktop", "desktop"],
			[OS.SYSTEM_DIR_DOCUMENTS, "Dokumente", "file"]]:
		var p := OS.get_system_dir(spec[0])
		if p != "" and DirAccess.dir_exists_absolute(p) and not quick.any(func(q): return q[1] == p):
			quick.append([spec[1], p, spec[2]])
	if not quick.is_empty():
		add_label("Schnell zu", "s", "muted")
		for q in quick:
			var it = _item(str(q[0]), str(q[1]), str(q[2]))
			var target: String = q[1]
			it.activated.connect(func() -> void: _open(target))
			add_row(it)
		add_gap(10)
	add_label("Laufwerke", "s", "muted")
	for d in _roots():
		var it2 = _item(_drive_name(d), d if _drive_name(d) != d else "", "drive")
		var target2: String = d
		it2.activated.connect(func() -> void: _open(target2))
		add_row(it2)


func _drive_name(d: String) -> String:
	if d == "/":
		return "System"
	if d.length() <= 3 and d.contains(":"):
		return "Laufwerk " + d.trim_suffix("/")
	return d.get_file() if d.get_file() != "" else d


## „Laufwerke › D: › Spiele › PS2“ – bei tiefen Pfaden nur die letzten Stufen.
func _crumb_text() -> String:
	if _dir == "":
		return "Laufwerke"
	var parts := _dir.replace("\\", "/").split("/", false)
	var head := "Laufwerke"
	if _dir.begins_with("/"):
		head = "System"
	var shown: Array = Array(parts)
	if shown.is_empty():
		return head
	var cut := shown.size() > 4
	if cut:
		shown = shown.slice(shown.size() - 4)
	return head + "  ›  " + ("…  ›  " if cut else "") + "  ›  ".join(PackedStringArray(shown))


## roh: der Name eines Ordners oder einer Datei – er steht da, wie er heißt (ein Ordner „Spiele“ hieße auf Englisch
## sonst „Games“).
func _item(t: String, sub: String, ic: String, roh := false) -> Control:
	var it = ListItem.new()
	if roh:
		it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	it.setup(t, sub)
	it.icon_name = ic
	it.min_h = 64
	it.set_meta("uz_hint_a", "Öffnen")
	return it


func _roots() -> Array:
	var out: Array = []
	if OS.get_name() == "Windows":
		for i in DirAccess.get_drive_count():
			out.append(DirAccess.get_drive_name(i) + "/")
	else:
		out.append("/")
		var home := OS.get_environment("HOME")
		if home != "":
			out.append(home)
	return out


func _parent_of(d: String) -> String:
	var parent := d.get_base_dir()
	if parent == d or d.ends_with(":/") or d == "/":
		return ""
	return parent


func _open(d: String) -> void:
	_dir = d
	refill_top()


func _go_up() -> void:
	_dir = _parent_of(_dir)
	refill_top()


func refill_top() -> void:
	_update_b()
	U.clear(content)
	fill()
	# Die neuen Zeilen bauen sich nacheinander auf (versteckt, bevor sie gezeichnet werden).
	U.cascade.call_deferred(content.get_parent() as Control, 8)
	await get_tree().process_frame
	scroll.scroll_vertical = 0
	var d := Nav.default_in(content)
	if d:
		Nav.focus(d, true)


func _pick(p: String) -> void:
	Config.set_value("system.last_dir", p if want_dir else p.get_base_dir())
	picked.emit(p)
	close()


func nav_command(cmd: String) -> bool:
	if cmd == "b" and _dir != "":
		Sfx.play("back")
		_go_up()
		return true
	return super(cmd)


func handle(cmd: String) -> bool:
	if cmd == "y":
		Sfx.play("back")
		close()
		return true
	if cmd == "x" and want_dir and _dir != "":
		Sfx.play("select")
		_pick(_dir)
		return true
	return false
