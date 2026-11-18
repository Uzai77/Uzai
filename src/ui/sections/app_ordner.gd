extends "res://src/ui/sections/section.gd"
## „Meine Apps“: der Ordner in der Leiste oben, nur wenn nicht alle Apps als Symbol Platz haben
## (src/core/leiste_oben.gd plan) – große Kacheln der Apps, die dann hier stehen (zuerst die
## eigenen, bei sehr wenig Platz auch eingebaute). A startet eine eigene App bzw. öffnet die App,
## Y (langes A, X): Verschieben, Ausblenden, Ausgeblendetes zurückholen, bei eigenen Entfernen.

const LeisteOben := preload("res://src/core/leiste_oben.gd")
const AppsExtern := preload("res://src/core/apps_extern.gd")
const ExtAppView := preload("res://src/ui/sections/ext_app_view.gd")
const MediaTile := preload("res://src/ui/components/media_tile.gd")
const AppGruppe := preload("res://src/ui/app_gruppe.gd")
## Ruhiger Farbton je eingebauter App (wenn sie bei wenig Platz hier steht).
const HUES := { "music": 0.93, "videos": 0.0, "movies": 0.6, "streams": 0.76, "room": 0.07 }

var _shelf: Control
var _gruppe: AppGruppe


func _init() -> void:
	super()
	id = LeisteOben.FOLDER
	title = "Meine Apps"
	icon_name = "apps"


## Die Apps im Ordner (main.folder_kids, in der Reihenfolge von apps.order).
func kids() -> Array:
	return (main.folder_kids as Array) if main and main.folder_kids is Array else []


func build() -> void:
	mark_built()
	U.clear(self)
	var col := U.vbox(18)
	var sc := scroll_v(col)
	U.full_rect(sc)
	add_child(sc)
	col.add_child(U.spacer(0, 18, false))
	_shelf = Shelf.new().setup("apps:ordner", 28, true, 26, GUTTER, 30)
	col.add_child(_shelf)
	_gruppe = AppGruppe.new(main, kids, func() -> Control: return _shelf.get("row") if is_instance_valid(_shelf) else null, "app:")
	var first := true
	for t in _gruppe.subtabs():
		var tile := _tile(str(t.id), str(t.label))
		if first:
			tile.set_meta("uz_default", true)
			first = false
		_shelf.add(tile)


func _tile(app_id: String, label: String) -> Control:
	var tile: Control
	if AppsExtern.is_ext_id(app_id):
		var prog := str(AppsExtern.get_entry(app_id).get("kind", "")) == "prog"
		tile = MediaTile.new().setup(app_id, label, "desktop" if prog else "tv", ExtAppView.hue_of(label), "Programm" if prog else "Store-App")
		tile.set("logo_path", AppsExtern.logo_path(app_id))
		tile.set_meta("uz_hint_a", "Starten")
	else:
		tile = MediaTile.new().setup(app_id, label, str(LeisteOben.ICONS.get(app_id, "apps")), float(HUES.get(app_id, 0.5)))
		tile.set_meta("uz_hint_a", "Betreten" if app_id == "room" else "Öffnen")
	tile.set_meta("uz_key", "app:" + app_id)
	var menu := func() -> void: _gruppe.menu(app_id, label)
	tile.set_meta("uz_on_hold_a", menu)
	# Dasselbe Menü auf Y (Optionen wie überall, auch Menü-Taste und Rechtsklick) und X: für
	# Controller, auf denen langes Drücken unzuverlässig ist.
	tile.set_meta("uz_on_y", menu)
	tile.set_meta("uz_on_x", menu)
	tile.set_meta("uz_on_menu", menu)
	tile.set_meta("uz_hint_y", "Optionen")
	tile.connect("chosen", func(_k: String) -> void: main.open_app(app_id))
	return tile
