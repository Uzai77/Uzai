extends RefCounted
## Quelltext für Prüfungen im Code: eine Datei samt aller Schichten darunter („extends "res://…"“),
## so dass ein Test dieselbe Stelle findet, egal in welcher Schicht sie steht.


static func lesen(pfad: String) -> String:
	var out := ""
	var p := pfad
	var seen := {}
	while p != "" and not seen.has(p):
		seen[p] = true
		var src := FileAccess.get_file_as_string(p)
		out = src + "\n" + out
		var first := src.get_slice("\n", 0).strip_edges()
		p = first.trim_prefix("extends \"").trim_suffix("\"") if first.begins_with("extends \"res://") else ""
	return out
