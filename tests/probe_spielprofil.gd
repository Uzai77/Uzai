extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Spiel-Profile – Spieloptionen → Profil, Auflösung wählen, Aktionen, Vorlage
## für alle PS2-Spiele und Übertragen auf andere Spiele. Aufruf siehe probe_base.gd.

const GameProfile := preload("res://src/core/game_profile.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var all := Library.visible_games()
	var g: Dictionary = all.filter(func(x): return x.get("system", "") == "ps2")[0]
	var gid := str(g.id)
	GameProfile.set_template("ps2", { "hdr": "an", "actions": ["quiet"] })
	main.open_game_options(g)
	await wait(0.8)
	await _focus("opt:Spiel-Einstellungen")
	await press("a")
	await wait(0.8)
	await _focus("opt:Profil")
	await shot("p01_optionen_profil", 0.6)
	await press("a")
	await wait(0.9)
	await shot("p02_profil_leer", 0.5)
	await _focus("prof:Auflösung")
	await press("a")
	await wait(0.9)
	await shot("p03_aufloesung_wahl", 0.5)
	await press("down", 2)
	await press("a")
	await wait(0.8)
	await _focus("prof:Lautstärke des Spiels")
	await press("right", 3)
	await _focus("prof:Stick-Totzone")
	await press("right", 4)
	await shot("p04_profil_gesetzt", 0.6)
	print("Probe: Profil = ", JSON.stringify(Library.get_game(gid).get("profile", {})))
	await _focus("prof:Aktionen")
	await press("a")
	await wait(0.8)
	await press("a")
	await shot("p05_aktionen", 0.6)
	Nav.top_layer().close()
	await wait(0.6)
	await _focus_suffix("PS2-Spiele")
	await shot("p06_teilen", 0.5)
	await press("a")
	await wait(0.9)
	await shot("p07_vorlage_ps2", 0.6)
	Nav.top_layer().close()
	await wait(0.6)
	await _focus("prof:Auf andere Spiele übertragen")
	await press("a")
	await wait(0.9)
	await press("down")
	await press("a")
	await shot("p08_uebertragen", 0.6)
	print("Probe: wirksam = ", JSON.stringify(GameProfile.effective(GameProfile.own_of(Library.get_game(gid)), GameProfile.template_for(g))))
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.15)
	await wait(0.3)
	main.open_game_options(Library.get_game(gid))
	await wait(0.8)
	await _focus("opt:Spiel-Einstellungen")
	await press("a")
	await wait(0.8)
	await _focus("opt:Profil")
	await shot("p09_optionen_mit_profil", 0.6)


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
