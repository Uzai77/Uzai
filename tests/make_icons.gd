extends Node
## Erzeugt PNG-Größen des App-Symbols (für die .ico-Datei).
func _ready() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for px in [256, 64, 48, 32, 16]:
		var img := Image.new()
		img.load_svg_from_string(svg, float(px) / 256.0)
		img.save_png(ProjectSettings.globalize_path("res://build/icon_%d.png" % px))
	get_tree().quit()
