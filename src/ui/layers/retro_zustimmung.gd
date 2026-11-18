extends "res://src/ui/layers/modal.gd"
## Zustimmung vor dem Laden eines Emulators (Retro ohne Einrichtung, src/core/retro_auto.gd): Name,
## Fassung, offizielle Quelle, Lizenz mit Text zum Lesen, Größe und wie Uzai prüft – dann erst
## „Zustimmen und laden“. Für mehrere Emulatoren auf einmal steht jeder in einer eigenen Zeile.
## Y oder „Lizenz lesen“ öffnet den vollen Lizenztext (bei mehreren erst die Wahl).

const RA := preload("res://src/core/retro_auto.gd")
const SELF := "res://src/ui/layers/retro_zustimmung.gd"

const Main := preload("res://src/main.gd")
var main: Main
## [{ angebot: RA-Angebot, kerne: [Kern-IDs], systeme: [Namen] }]
var teile: Array = []
var update := false
var zugestimmt: Callable
var ordner_text := ""


static func open_for(m: Main, liste: Array, ordner: String, cb: Callable, als_update := false) -> Control:
	var l = load(SELF).new()
	l.main = m
	l.teile = liste
	l.zugestimmt = cb
	l.update = als_update
	l.ordner_text = ordner
	m.open_layer(l)
	return l


func build() -> void:
	width = 1180.0
	set_meta("uz_hint_b", "Abbrechen")
	super()


func fill() -> void:
	var titel := ""
	if teile.size() == 1:
		titel = tr("%s aktualisieren?" if update else "%s laden und einrichten?") % str(teile[0].angebot.name)
	else:
		titel = tr("%d Emulatoren aktualisieren?" if update else "%d Emulatoren laden und einrichten?") % teile.size()
	var head := U.hbox(22)
	box.add_child(head)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(64, 64)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(func() -> void: badge.draw_circle(Vector2(32, 32), 32.0, UzTheme.col("accent", 0.16), true, -1.0, true))
	var ic := U.icon("download", 30, "accent")
	ic.position = Vector2(17, 17)
	badge.add_child(ic)
	head.add_child(badge)
	var hv := U.vbox(4)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var t := U.label(titel, "xl", "text", "black", true)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hv.add_child(t)
	hv.add_child(U.label("Von der offiziellen Quelle.", "m", "muted", "regular", true))
	box.add_child(U.spacer(0, 4, false))
	for teil in teile:
		box.add_child(_block(teil))
	var note := U.label(tr("Ordner: %s. Keine BIOS, Firmware, Schlüssel oder Spiele.") % ordner_text, "s", "muted", "regular", true)
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note.custom_minimum_size = Vector2(width - 96.0, 0)
	box.add_child(note)
	box.add_child(U.spacer(0, 6, false))
	var row := U.hbox(14)
	box.add_child(row)
	var ok := U.button("Zustimmen und aktualisieren" if update else "Zustimmen und laden", "check", "primary")
	ok.set_meta("uz_default", true)
	ok.set_meta("uz_hint_y", "Lizenz lesen")
	ok.pressed.connect(func() -> void:
		close()
		if zugestimmt.is_valid():
			zugestimmt.call())
	row.add_child(ok)
	var lic := U.button("Lizenz lesen", "file")
	lic.pressed.connect(_lizenzen)
	row.add_child(lic)
	var no := U.button("Abbrechen", "close")
	no.pressed.connect(close)
	row.add_child(no)


func handle(cmd: String) -> bool:
	if cmd == "y":
		Sfx.play("select")
		_lizenzen()
		return true
	return false


## Ein Emulator: Name und Fassung, darunter Quelle, Lizenz, Größe und Prüfung in zwei Spalten.
func _block(teil: Dictionary) -> Control:
	var a: Dictionary = teil.angebot
	var card := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel())
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := U.vbox(10)
	card.add_child(v)
	var top := U.hbox(12)
	v.add_child(top)
	var n := U.label("%s %s" % [str(a.name), str(a.fassung)], "l", "text", "bold")
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	top.add_child(n)
	var sys: Array = teil.get("systeme", [])
	if not sys.is_empty():
		var s := U.label(tr("für %s") % ", ".join(PackedStringArray(sys)), "m", "muted")
		s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		top.add_child(s)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grid)
	_pair(grid, "Quelle", tr("%s (offiziell)") % str(a.web))
	if not bool(a.get("nur_kerne", false)):
		_pair(grid, "Lizenz", str(RA.lizenz(str(a.lizenz)).get("name", a.lizenz)))
		_pair(grid, "Größe", RA.groesse_text(int(a.groesse)) if int(a.groesse) > 0 else tr("zeigt der Server beim Laden"))
		_pair(grid, "Prüfung", tr(str(a.pruefung)))
	var kerne: Array = teil.get("kerne", [])
	if not kerne.is_empty():
		var names := PackedStringArray()
		for k in kerne:
			var info: Array = RA.KERN_INFO.get(k, [k, ""])
			names.append(
					"%s (%s)" % [info[0],
					str(RA.lizenz(str(info[1])).get("name", info[1])).replace("GNU General Public License", "GPL").replace("Mozilla Public License",
					"MPL").replace("GNU Affero General Public License", "AGPL")])
		var kl := U.label(tr("Kerne vom Buildbot (buildbot.libretro.com, geprüft mit dessen CRC32): %s") % ", ".join(names), "s", "muted", "regular", true)
		kl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		kl.custom_minimum_size = Vector2(width - 160.0, 0)
		v.add_child(kl)
	return card


func _pair(grid: GridContainer, k: String, val: String) -> void:
	var kl := U.label(k, "s", "faint", "medium")
	grid.add_child(kl)
	var vl := U.label(val, "s", "text", "medium")
	vl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vl.custom_minimum_size = Vector2(340, 0)
	grid.add_child(vl)


## Alle Lizenzen dieser Zustimmung (Emulatoren und Kerne), jede einmal: [[Schlüssel, Wofür]].
func _alle_lizenzen() -> Array:
	var out: Array = []
	var seen := {}
	for teil in teile:
		var nur := bool(teil.angebot.get("nur_kerne", false))
		var wer := [] if nur else [str(teil.angebot.name)]
		var keys := [] if nur else [str(teil.angebot.lizenz)]
		for k in teil.get("kerne", []):
			wer.append(str(RA.KERN_INFO[k][0]))
			keys.append(str(RA.KERN_INFO[k][1]))
		for i in keys.size():
			if seen.has(keys[i]):
				(out[seen[keys[i]]][1] as Array).append(wer[i])
			else:
				seen[keys[i]] = out.size()
				out.append([keys[i], [wer[i]]])
	return out


func _lizenzen() -> void:
	var all := _alle_lizenzen()
	if all.size() == 1:
		Lizenz.open_for(main, str(all[0][0]), PackedStringArray(all[0][1]))
		return
	var opts: Array = all.map(
			func(x: Array) -> Array: return [x[0], "%s · %s" % [str(RA.lizenz(str(x[0])).get("name", x[0])), ", ".join(PackedStringArray(x[1]))]])
	main.open_choice("Welche Lizenz?", opts, null, func(v: Variant) -> void:
		for x in all:
			if str(x[0]) == str(v):
				Lizenz.open_for(main, str(v), PackedStringArray(x[1])))


## Der volle Lizenztext als Seitenleiste; hoch/runter blättert (LB/RB seitenweise).
class Lizenz extends "res://src/ui/layers/sheet.gd":
	const RA2 := preload("res://src/core/retro_auto.gd")
	var key := ""
	var wer := PackedStringArray()

	static func open_for(m: Main, k: String, fuer: PackedStringArray) -> Control:
		var l := Lizenz.new()
		l.key = k
		l.wer = fuer
		l.setup(str(RA2.lizenz(k).get("name", k)), TranslationServer.translate("Gilt für %s") % ", ".join(fuer), 1000)
		l.heading_raw = true
		m.open_layer(l)
		return l

	func build() -> void:
		set_meta("uz_hint_b", "Schließen")
		super()

	func fill() -> void:
		var t := U.label(str(RA2.lizenz(key).get("text", "")), "s", "muted", "regular", true)
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		content.add_child(t)

	func nav_dir(cmd: String) -> bool:
		if cmd == "up" or cmd == "down":
			_scroll(260.0 if cmd == "down" else -260.0)
			return true
		return cmd == "left" or cmd == "right"

	func handle(cmd: String) -> bool:
		if cmd == "lb" or cmd == "rb":
			_scroll((scroll.size.y - 80.0) * (1.0 if cmd == "rb" else -1.0))
			return true
		return false

	func _scroll(dy: float) -> void:
		if not is_instance_valid(scroll):
			return
		var to := clampf(scroll.scroll_vertical + dy, 0.0, maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.size.y))
		U.im_tempo(create_tween()).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(scroll, "scroll_vertical", int(to), 0.18)
