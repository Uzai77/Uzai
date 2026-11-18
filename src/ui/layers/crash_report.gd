extends "res://src/ui/layers/modal.gd"
## Fehlerbericht (Punkt 55, src/core/crash_guard.gd): ein QR-Code mit einer vorausgefüllten
## GitHub-Meldung. Das Handy öffnet sie, man sieht alles und schickt nur ab, wenn man will – Uzai
## selbst sendet nichts. Was drinsteht, zeigt der Dialog auch hier: Version, Windows, Grafik, wie
## es endete und die letzten Fehlerzeilen ohne Namen, Pfade und Schlüssel. Derselbe Text liegt
## als logs/fehlerbericht.txt im Datenordner (für die Meldung am PC).

const QrView := preload("res://src/ui/components/qr_view.gd")
const CrashGuard := preload("res://src/core/crash_guard.gd")
const Zustand := preload("res://src/core/zustand.gd")
const SHOWN_LINES := 5

const Main := preload("res://src/main.gd")
var main: Main
var report: Dictionary = {}


func build() -> void:
	width = 1320.0
	set_meta("uz_hint_b", "Schließen")
	report = make_report()
	var f := FileAccess.open(Config.path("logs/fehlerbericht.txt"), FileAccess.WRITE)
	if f:
		f.store_string(str(report.title) + "\n\n" + str(report.text))
		f.close()
	super()


## Bericht zum letzten unerwarteten Ende, sonst zum laufenden Uzai (für Fehler ohne Absturz).
func make_report() -> Dictionary:
	var crash: Dictionary = Config.last_crash
	var log_path := CrashGuard.last_log(crash.is_empty())
	var homes := [OS.get_environment("USERPROFILE"), OS.get_environment("HOME"), OS.get_environment("APPDATA"), OS.get_environment("LOCALAPPDATA")]
	var lines := CrashGuard.log_tail(CrashGuard.tail_text(log_path), homes) if log_path != "" else PackedStringArray()
	var where := str(main.where_name(str(crash.get("where", "")))) if not crash.is_empty() and main else ""
	return CrashGuard.build({
		"version": Config.VERSION,
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"godot": str(Engine.get_version_info().get("string", "")),
		"gpu": RenderingServer.get_video_adapter_name(),
		"safe": Config.safe_mode,
		"crash": crash,
		"where": where,
		# Zustände: beim letzten unerwarteten Ende die gemerkten aus der Markierung, sonst die jetzigen.
		"zustaende": PackedStringArray(crash.get("zustaende", [])) if not crash.is_empty() else Zustand.lage_text(),
	}, lines)


func fill() -> void:
	var row := U.hbox(48)
	box.add_child(row)
	var frame := PanelContainer.new()
	var sb := UzTheme.box(Color.WHITE, UzTheme.radius + 4)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, 10)
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	frame.add_child(QrView.new().setup_async(str(report.url), 560))
	var col := U.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(U.label("Fehlerbericht", "xl", "text", "black"))
	var t := U.label("Mit dem Handy scannen. GitHub öffnet eine ausgefüllte Meldung, die du prüfst und selbst absendest. GitHub-Konto nötig.", "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(600, 0)
	col.add_child(t)
	col.add_child(U.spacer(0, 4, false))
	var crash: Dictionary = Config.last_crash
	_fact(col, "Uzai", "%s · %s %s" % [Config.VERSION, OS.get_name(), OS.get_version()])
	if not crash.is_empty():
		_fact(col, "Ende", "kurz nach dem Start" if bool(crash.get("quick", false)) else "unerwartet")
	var n := int(report.lines)
	_fact(col, "Protokoll", (U.plural(n, "Zeile", "Zeilen") + ", ohne Namen, Pfade und Schlüssel") if n > 0 else "keine Fehler gefunden")
	var text := str(report.text)
	var log_start := text.find("```\n")
	if log_start >= 0:
		var lines := text.substr(log_start + 4).trim_suffix("\n").trim_suffix("```").strip_edges().split("\n")
		var shown := lines.slice(maxi(0, lines.size() - SHOWN_LINES))
		var mono := U.label("\n".join(shown), "cap", "faint", "regular", true)
		mono.add_theme_font_override("font", UzTheme.font("mono"))
		mono.custom_minimum_size = Vector2(600, 0)
		mono.max_lines_visible = SHOWN_LINES * 2
		col.add_child(mono)
	var h := U.label("Auch gespeichert unter logs\\fehlerbericht.txt im Datenordner.", "s", "faint", "regular", true)
	h.custom_minimum_size = Vector2(600, 0)
	col.add_child(h)
	col.add_child(U.spacer(0, 6, false))
	var done := U.button("Fertig", "check", "primary")
	done.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	done.set_meta("uz_default", true)
	done.set_meta("uz_hint_a", "Schließen")
	done.pressed.connect(close)
	col.add_child(done)


func _fact(col: Control, key: String, value: String) -> void:
	var r := U.hbox(14)
	var k := U.label(key, "s", "faint", "bold")
	k.custom_minimum_size = Vector2(120, 0)
	r.add_child(k)
	var v := U.ellipsis(U.label(value, "s", "text", "medium"))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(v)
	col.add_child(r)
