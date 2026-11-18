extends Node
## Lädt alle Skripte einmal, damit Syntaxfehler sofort auffallen (mit Autoloads) – auch die der Tests: Eine
## Testszene, deren Skript nicht lädt, läuft ohne Skript weiter und endet nie von selbst.
func _ready() -> void:
	var bad := 0
	var stack := ["res://src", "res://tests"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var da := DirAccess.open(dir)
		for d in da.get_directories():
			stack.append(dir.path_join(d))
		for f in da.get_files():
			if f.ends_with(".gd"):
				var s = ResourceLoader.load(dir.path_join(f), "", ResourceLoader.CACHE_MODE_REUSE)
				if s == null or not (s as GDScript).can_instantiate():
					bad += 1
					print("FEHLER: ", dir.path_join(f))
	print("geprüft, Fehler: ", bad)
	get_tree().quit(1 if bad > 0 else 0)
