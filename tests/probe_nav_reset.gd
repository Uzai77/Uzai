extends "res://tests/probe_base.gd"
## Bereiche und Reiter fangen beim Betreten vorn an (erster Unterbereich, erstes Element);
## nur B aus einer Ebene (Spielseite) kehrt an die alte Stelle zurück. Gibt „NR ok/FAIL …“ aus.

var fails := 0


func _key(f: Control) -> String:
	if f == null:
		return "<null>"
	if f.get("game") is Dictionary:
		return "game:" + str((f.get("game") as Dictionary).get("id", ""))
	return str(f.get_meta("uz_key", f.get_class()))


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("NR %s %s (Fokus %s, Bereich %s/%s)" % ["ok  " if cond else "FAIL", what, _key(Nav.focused()), main.current, main.sections[main.current].sub])


func run() -> void:
	main.goto("games")
	await wait(1.0)
	var first := _key(Nav.focused())
	await press("right", 3, 0.25)
	var moved := _key(Nav.focused())
	_ck(moved != first, "Spiele: drei nach rechts")
	# Ebene: Spielseite auf und mit B zu – die Stelle bleibt.
	var f := Nav.focused()
	if f and f.get("game") is Dictionary:
		main.open_game(f.get("game"))
		await wait(1.2)
		await press("b", 1, 1.0)
		_ck(_key(Nav.focused()) == moved, "B aus der Spielseite: dieselbe Stelle")
	# Bereich wechseln und zurück: vorn.
	await press("rt", 1, 0.9)
	await press("lt", 1, 1.2)
	_ck(_key(Nav.focused()) == first, "Spiele wieder betreten: erstes Spiel")
	await shot("01_spiele_vorn", 0.2)
	# Unterbereich (LB/RB) wechseln und zurück: vorn, nicht das gemerkte Spiel.
	await press("right", 2, 0.25)
	await press("rb", 1, 0.9)
	await press("lb", 1, 0.9)
	_ck(_key(Nav.focused()) == first, "Spiele: anderer Unterbereich und zurück: erstes Spiel")
	# Freunde: Unterbereich wechseln, dann Bereich verlassen und wiederkommen: erster Unterbereich.
	main.goto("friends")
	await wait(1.0)
	var ffirst := _key(Nav.focused())
	var first_sub: String = main.sections.friends.sub
	await press("rb", 1, 0.9)
	await press("down", 2, 0.25)
	main.goto("games")
	await wait(0.9)
	main.goto("friends")
	await wait(1.0)
	_ck(main.sections.friends.sub == first_sub and _key(Nav.focused()) == ffirst, "Freunde wieder betreten: erster Reiter, erste Person")
	await shot("02_freunde_vorn", 0.2)
	# Videos (bleibt aufgebaut): tiefer hinein, raus und wieder rein: vorn.
	if main.sections.has("videos"):
		main.goto("videos")
		await wait(1.2)
		var vfirst := _key(Nav.focused())
		await press("down", 2, 0.3)
		await press("right", 2, 0.25)
		main.goto("games")
		await wait(0.9)
		main.goto("videos")
		await wait(1.2)
		_ck(_key(Nav.focused()) == vfirst, "Videos wieder betreten: erstes Element")
		var row_first: Control = main.sections.videos._rows[0].shelf.items()[0]
		await press("down", 1, 0.5)
		_ck(Nav.focused() == row_first, "Videos: erste Reihe beginnt vorn")
		await shot("03_videos_vorn", 0.2)
	# Guide: Reiter wechseln, zu, wieder auf: erster Reiter.
	main.goto("games")
	await wait(0.8)
	await press("guide", 1, 0.9)
	await press("rb", 2, 0.5)
	await press("guide", 1, 0.8)
	await press("guide", 1, 1.0)
	_ck(main._guide != null and str(main._guide.tab) == "spiel", "Guide wieder auf: erster Reiter (%s)" % (str(main._guide.tab) if main._guide else "-"))
	await shot("04_guide_vorn", 0.2)
	await press("guide", 1, 0.6)
	print("NR Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
