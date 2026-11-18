extends "res://tests/probe_base.gd"
## Beispiel: Startseite und Shop fotografieren.


func run() -> void:
	main.goto("games")
	await shot("01_start", 1.0)
	main.goto("shop")
	await shot("02_shop", 3.0)
