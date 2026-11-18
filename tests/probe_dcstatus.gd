extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Discord-Status beim Spielen – je Spiel abschaltbar in den Spieloptionen, die
## Einstellung unter Konten → Discord, dazu die Aktivität, die Uzai für ein paar Demo-Spiele an
## Discord gäbe (im Protokoll). Aufruf siehe probe_base.gd.

const GamePresence := preload("res://src/core/game_presence.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var all := Library.visible_games()
	var sotc: Dictionary = all.filter(func(g): return g.get("system", "") == "ps2")[0]
	var gid := str(sotc.id)
	main.open_game_options(sotc)
	await wait(0.8)
	await _focus("opt:Spiel-Einstellungen")
	await press("a")
	await wait(0.8)
	await _focus("opt:Im Discord-Status zeigen")
	await shot("d01_optionen_status_an", 0.6)
	await press("a")
	await shot("d02_optionen_status_aus", 0.6)
	print("Probe: ausgeblendet = ", GamePresence.hidden(Library.get_game(gid)))
	await press("a")
	await wait(0.3)
	print("Probe: wieder an = ", not GamePresence.hidden(Library.get_game(gid)))
	await _close_all()

	await main.goto("settings", "konten")
	await wait(0.8)
	var sv = main.sections["settings"]
	sv.open_more("Discord")
	await wait(0.9)
	await _focus_suffix("auf Uzai“")
	await shot("d03_einstellung_discord", 0.7)
	await _close_all()

	# Was Discord je Quelle bekäme (Bild nur, wenn ohne Warten bekannt).
	for src in ["steam", "epic", "ea", "rom", "disc", "pc"]:
		var gs: Array = all.filter(func(g): return str(g.get("source", "")) == src)
		if gs.is_empty():
			continue
		var g: Dictionary = gs[0]
		var sys := str(Config.system(str(g.get("system", ""))).get("name", ""))
		print("Probe: %s → %s" % [src, JSON.stringify(GamePresence.activity(g, Media.presence_image_known(g), 1700000000, sys))])


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.15)
	await wait(0.4)


func _focus(key: String) -> void:
	var c := _find(Nav.top_layer(), func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == key)
	if c:
		Nav.focus(c)
	else:
		print("Probe: nicht gefunden: ", key)
	await wait(0.35)


func _focus_suffix(suffix: String) -> void:
	var c := _find(Nav.top_layer(), func(n: Node) -> bool: return str(n.get_meta("uz_key", "")).ends_with(suffix))
	if c:
		Nav.focus(c)
	else:
		print("Probe: nicht gefunden: …", suffix)
	await wait(0.35)


func _find(n: Node, f: Callable) -> Control:
	if n == null:
		return null
	if n is Control and f.call(n):
		return n
	for ch in n.get_children():
		var r := _find(ch, f)
		if r:
			return r
	return null
