extends "res://src/ui/layers/layer.gd"
## Ein Bildschirmfoto groß, auf schwarzem Grund. Links/rechts (oder LB/RB) blättert, B schließt.
## Auch Bilder aus dem Chat (Adressen statt Dateien, ChatLink.open_in_uzai): dann ohne Dateinamen darunter.

var files: Array = []
var titel := ""              ## statt des Dateinamens (Chat: Name des Freundes oder „Bild“)
var index := 0
var _img: TextureRect
var _cap: Label


func build() -> void:
	dim = 1.0
	_scrim.color = Color(0, 0, 0, 1)
	set_meta("uz_hints", [["lb", ""], ["rb", "Blättern"]] if files.size() > 1 else [])
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_img)
	_img.offset_bottom = -90
	add_child(_img)
	_cap = U.label("", "m", "muted", "medium")
	_cap.anchor_top = 1.0
	_cap.anchor_bottom = 1.0
	_cap.offset_top = -78
	_cap.offset_left = 96
	add_child(_cap)
	# Ein unsichtbarer Halt für den Fokus: A und X sollen nicht die Galerie dahinter treffen.
	var hold := Control.new()
	hold.focus_mode = Control.FOCUS_ALL
	hold.custom_minimum_size = Vector2(1, 1)
	hold.set_meta("uz_default", true)
	hold.set_meta("uz_hint_a", "—")
	add_child(hold)
	_show()


func _show() -> void:
	if files.is_empty():
		return
	index = posmod(index, files.size())
	var p := str(files[index])
	var name_ := titel if titel != "" else p.get_file().get_basename()
	_cap.text = name_ if files.size() <= 1 else "%s   ·   %d / %d" % [name_, index + 1, files.size()]
	# Beim schnellen Blättern kann ein älteres, großes Bild nach dem neueren ankommen: Es gehört dann nicht mehr
	# unter die Zeile des jetzigen (gemerkt am Bild selbst, die Ebene kann inzwischen zu sein).
	_img.set_meta("uz_pfad", p)
	var wr: WeakRef = weakref(_img)
	var da := func(t: Texture2D) -> void:
		var r: TextureRect = wr.get_ref()
		if r and t and str(r.get_meta("uz_pfad", "")) == p:
			r.texture = t
	if p.begins_with("https://"):
		Media.url_texture(p, 1920, da)
	else:
		Media.file_texture(p, 1920, da)


func nav_dir(cmd: String) -> bool:
	if cmd == "left" or cmd == "right":
		index += -1 if cmd == "left" else 1
		Sfx.play("move")
		_show()
	return true


func handle(cmd: String) -> bool:
	if cmd == "lb" or cmd == "rb":
		return nav_dir("left" if cmd == "lb" else "right")
	return false
