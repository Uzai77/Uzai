extends "res://tests/probe_base.gd"
## Probe „Freundschaftsanfragen“ und „Was ist neu“: Anfragen oben im Freunde-Bereich (Steam und
## Discord), A fragt nach, Ablehnen mit Rückfrage, Profil vorher, Annehmen; die
## ruhige Mitteilung; die Karte „Was ist neu“ aus den Einstellungen und für die nächste Fassung.

const WN := preload("res://src/core/whats_new.gd")
const WhatsNew := preload("res://src/ui/layers/whats_new.gd")


func _focus_key(root: Node, key: String) -> bool:
	for c in Nav.focusables(root):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return true
	print("nicht gefunden: ", key)
	return false


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.15)
	await wait(0.4)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	await main.goto("friends", "steam")
	await wait(0.6)
	var fv = main.friends_view()
	await wait(1.0)
	_focus_key(fv, "rq:steam:76561190000000021")
	await shot("a01_steam_anfragen", 0.8)
	_focus_key(fv, "rq:steam:76561190000000022")
	await shot("a02_gesendet", 0.7)
	_focus_key(fv, "rq:steam:76561190000000021")
	await wait(0.4)
	await press("a")
	await shot("a03_frage", 0.7)
	await press("right", 2)
	await press("a")
	await shot("a04_profil", 1.6)
	await press("b")
	await wait(0.6)
	_focus_key(fv, "rq:steam:76561190000000021")
	await wait(0.3)
	await press("a")
	await wait(0.5)
	await press("right")
	await press("a")
	await shot("a05_ablehnen_frage", 0.7)
	await press("b")
	await wait(0.5)
	# Annehmen: A auf der Anfrage, „Annehmen“ ist vorgewählt.
	_focus_key(fv, "rq:steam:76561190000000021")
	await wait(0.3)
	await press("a")
	await wait(0.5)
	await press("a")
	await shot("a07_angenommen", 1.2)
	print("Anfragen danach: ", Social.requests.map(func(r): return str(r.key)))
	await main.goto("friends", "discord")
	await wait(1.0)
	_focus_key(fv, "rq:discord:1005")
	await shot("a08_discord", 0.8)
	await press("y")
	await shot("a09_discord_profil", 1.0)
	await _close_all()
	# Ruhige Mitteilung für eine neue Anfrage (wie außerhalb der Vorführung).
	Social.toast_request(
			{ "key": "steam:76561198000000999", "source": "steam", "id": "76561198000000999", "dir": "in", "name": "Robin", "avatar": "", "username": "" })
	await shot("a10_mitteilung", 0.9)
	# „Was ist neu“: aus den Einstellungen (aktuelle Fassung) und die Karte der nächsten Fassung.
	await main.goto("settings", "system")
	await wait(0.8)
	var sv = main.sections["settings"]
	sv._enter_content()
	await wait(0.3)
	for c in Nav.focusables(sv._list):
		if str(c.get_meta("uz_key", "")).ends_with("Was ist neu"):
			Nav.focus(c, true)
	await shot("a11_einstellungen_zeile", 0.6)
	await press("a")
	await shot("a12_neu", 1.2)
	await press("a")
	await wait(0.6)
	var entries := WN.load_entries()
	await main.goto("games")
	await wait(0.8)
	WhatsNew.open_for(main, WN.items(entries, "0.8.3", "0.9.0", "de"))
	await shot("a13_neu_090", 1.4)
	await _close_all()
	WhatsNew.open_for(main, WN.items(entries, "0.8.3", "0.9.0", "en"))
	await shot("a14_neu_090_en", 1.4)
	await _close_all()
