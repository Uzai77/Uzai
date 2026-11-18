extends "res://src/ui/layers/modal.gd"
## Ein fehlender Launcher (Punkt 115): wo es ihn offiziell gibt. Uzai lädt selbst nichts herunter
## und startet keinen Installer – es zeigt die Seite des Anbieters als QR-Code fürs Handy und
## öffnet sie auf Wunsch im Browser am PC. Nach der Installation liest „Noch einmal suchen“ neu ein.

const QrView := preload("res://src/ui/components/qr_view.gd")
const LauncherSites := preload("res://src/library/launcher_sites.gd")

const Main := preload("res://src/main.gd")
var main: Main
var launcher := ""              ## steam | epic | ea


func build() -> void:
	width = 1240.0
	set_meta("uz_hint_b", "Schließen")
	super()


func fill() -> void:
	var s := LauncherSites.site(launcher)
	var url := LauncherSites.url(launcher)
	if s.is_empty() or url == "":
		return
	var row := U.hbox(52)
	box.add_child(row)
	var left := U.vbox(12)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	frame.add_child(QrView.new().setup(url, 300))
	left.add_child(frame)
	var cap := U.label(url.replace("https://", "").trim_suffix("/"), "s", "muted", "medium")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(cap)
	row.add_child(left)
	var col := U.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(U.label("%s fehlt noch" % str(s.name), "xl", "text", "black"))
	col.add_child(_text("%s fehlt, damit fehlen %s. Download auf der offiziellen Seite." % [str(s.name), str(s.what)]))
	col.add_child(
			_step("1",
			"Code scannen oder „Im Browser am PC“."))
	col.add_child(_step("2", "Herunterladen, installieren, anmelden."))
	col.add_child(_step("3", "„Noch einmal suchen“ wählen."))
	var brow := U.hbox(14)
	col.add_child(brow)
	var pc := U.button("Im Browser am PC", "link", "primary")
	pc.set_meta("uz_default", true)
	pc.pressed.connect(func() -> void:
		if Config.kid_stop("browser"):
			return
		OS.shell_open(url)
		Toasts.show_toast("Offizielle Seite im Browser", "%s dort herunterladen und installieren, dann hier „Noch einmal suchen“." % str(s.name), "link",
				{ "ms": 6000 })
	)
	brow.add_child(pc)
	var again := U.button("Noch einmal suchen", "refresh")
	again.pressed.connect(func() -> void:
		Library.scan(true)
		Toasts.show_toast("Bibliothek wird eingelesen …", "", "refresh", { "quiet": true })
		close()
	)
	brow.add_child(again)
	var later := U.button("Später", "close")
	later.pressed.connect(close)
	brow.add_child(later)


func _text(text: String) -> Label:
	var t := U.label(text, "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(720, 0)
	return t


func _step(n: String, text: String) -> Control:
	var r := U.hbox(14)
	var badge := U.panel("accent", 17, 0)
	badge.custom_minimum_size = Vector2(34, 34)
	var l := U.label(n, "s", "bg", "black")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(l)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(badge)
	var t := U.label(text, "m", "text", "medium", true)
	t.custom_minimum_size = Vector2(680, 0)
	r.add_child(t)
	return r
