extends HBoxContainer
## Akku des PCs oben rechts neben der Uhr (Punkt 64): auf Handhelds immer, auf Laptops nur ohne
## Netzteil. Dasselbe Symbol wie bei den Controllern (pad_battery.gd: Balken, Blitz beim Laden),
## daneben die Prozent. Gelesen wird über den Helfer („pc-akku“, GetSystemPowerStatus, nur lesen)
## einmal je Minute; ohne Akku bleibt alles unsichtbar.

const U := preload("res://src/ui/u.gd")
const Handheld := preload("res://src/core/handheld.gd")
const PerfLive := preload("res://src/core/perf_live.gd")
const PadBattery := preload("res://src/ui/components/pad_battery.gd")

const ABSTAND_S := 60.0
const DEMO := { "ok": true, "akku": true, "prozent": 76, "laedt": false, "netz": false, "sparen": false, "minuten": 170 }

## Zuletzt gelesen (auch für das Schnellmenü im Guide).
static var stand: Dictionary = {}

var _icon: Control
var _l: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_icon = PadBattery.new().setup({}, 15.0)
	add_child(_icon)
	_l = U.label("", "s", "text", "medium")
	_l.clip_text = false
	add_child(_l)
	var t := Timer.new()
	t.wait_time = ABSTAND_S
	t.autostart = true
	t.timeout.connect(_lesen)
	add_child(t)
	_zeigen()
	_lesen()


func _lesen() -> void:
	var a := await lesen()
	if not is_inside_tree():
		return
	stand = a
	_zeigen()


func _zeigen() -> void:
	visible = zeigen(stand)
	if not visible:
		return
	_icon.set("pad", { "level": Handheld.akku_stufe(int(stand.prozent)), "charging": bool(stand.laedt) })
	_icon.queue_redraw()
	_l.text = Handheld.akku_text(stand)
	_l.add_theme_color_override("font_color", UzTheme.col("warn") if int(stand.prozent) <= 15 and not bool(stand.laedt) else UzTheme.col("text"))


## Oben zeigen? Auf Handhelds immer (mit Akku), sonst nur ohne Netzteil.
static func zeigen(a: Dictionary) -> bool:
	if not bool(a.get("akku", false)) or int(a.get("prozent", -1)) < 0:
		return false
	return not Handheld.aktiv.is_empty() or not bool(a.get("netz", false))


## Den Akku lesen ({} ohne Helfer). In der Vorführung nur auf einem (nachgestellten) Handheld.
static func lesen() -> Dictionary:
	if Library.demo:
		return Handheld.parse_akku(DEMO) if not Handheld.aktiv.is_empty() else {}
	if not Config.is_windows() or not Helper.available:
		return {}
	return Handheld.parse_akku(PerfLive.parse_reply(await Helper.run("pc-akku", {}, 6.0)))
