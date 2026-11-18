extends "res://tests/probe_base.gd"
## Probe „Bild & Ton“ und „Windows“ (Roadmap 4/16, Demo): Guide → System → Bild & Ton über dem
## Spiel, Auflösung mit „Behalten?“ (Frist läuft ab, dann einmal behalten), HDR; Einstellungen →
## System → Windows mit WLAN (Passwort über die Bildschirmtastatur, Firmen-WLAN), Bluetooth,
## Energie; Doktor mit „Kein Netz“ und „Bluetooth ist aus“.

const BildTon := preload("res://src/core/bild_ton.gd")
const Lage := preload("res://src/core/doktor_lage.gd")


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.15)
	await wait(0.4)


func _focus_key(key: String) -> bool:
	var top = Nav.top_layer()
	if top == null:
		return false
	for c in Nav.focusables(top):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return true
	return false


func _focus_prefix(prefix: String) -> bool:
	var top = Nav.top_layer()
	for c in Nav.focusables(top):
		if str(c.get_meta("uz_key", "")).begins_with(prefix):
			Nav.focus(c, true)
			return true
	return false


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	Launcher.in_game = true
	Launcher.current = g
	main.toggle_guide("system")
	await wait(1.0)
	_focus_key("a:Bild & Ton")
	await shot("b01_guide_system", 0.7)
	await press("a")
	await shot("b02_bild_ton", 1.4)
	print("Fokus nach dem Öffnen: %s" % str(Nav.focused().get_meta("uz_key", "")))
	# Andere Tonausgabe wählen.
	_focus_prefix("bt:audio:{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a002}")
	await press("a")
	await shot("b03_kopfhoerer_aktiv", 0.8)
	# Auflösung: Liste, neue wählen, Rückfrage – ohne Antwort zurück.
	_focus_key("bt:res")
	await press("a")
	await shot("b04_aufloesungen", 1.0)
	await press("down", 2)
	await press("a")
	await shot("b05_behalten_frage", 1.2)
	await wait(6.0)
	await shot("b06_behalten_frist_laeuft", 0.2)
	print("Frage offen: %s, noch %d s" % [str(BildTon.asking()), BildTon.ask_left()])
	await wait(9.5)
	await shot("b07_zurueckgestellt", 0.6)
	print("Nach der Frist: Modus %s, Frage offen: %s" % [str(BildTon.demo_mode), str(BildTon.asking())])
	# Bildwiederholrate 120 Hz und behalten.
	_focus_key("bt:hz")
	await press("a")
	await shot("b08_hz_liste", 1.0)
	await press("up", 3)
	await press("a")
	await wait(1.0)
	await press("left")
	await shot("b09_behalten_gewaehlt", 0.5)
	await press("a")
	await shot("b10_120hz_behalten", 1.4)
	print("Behalten: Modus %s" % str(BildTon.demo_mode))
	_focus_key("bt:hdr")
	await press("a")
	await shot("b11_hdr_an", 1.2)
	await _close_all()
	Launcher.in_game = false
	Launcher.current = {}
	main.goto("games")
	await wait(0.8)

	# Einstellungen → System → Windows
	await main.open_setting("system", "more:system:Windows")
	await wait(0.8)
	await shot("w01_einstellungen_system", 0.6)
	await press("a")
	await shot("w02_windows_seite", 1.2)
	# WLAN
	load("res://src/ui/layers/win_wlan.gd").open_for(main)
	await shot("w03_wlan_sucht", 0.25)
	await shot("w04_wlan", 1.4)
	_focus_key("wl:FRITZ!Box 7590 KL")
	await shot("w05_wlan_neues_netz", 0.5)
	await press("a")
	await wait(0.8)
	var kb = Nav.top_layer()
	kb.text = "Sommer2026!"
	kb.caret = kb.text.length()
	kb.call("_update_field")
	await shot("w06_passwort_verdeckt", 0.5)
	await press("menu")
	await shot("w07_verbindet", 0.5)
	await wait(2.2)
	await shot("w08_verbunden", 0.6)
	_focus_key("wl:Büro")
	await press("a")
	await shot("w09_firmen_wlan", 1.0)
	await press("b")
	await wait(0.4)
	_focus_key("wl:Café am Markt")
	await press("a")
	await shot("w10_offenes_netz_frage", 1.0)
	await _close_all()
	# Bluetooth
	load("res://src/ui/layers/win_bt.gd").open_for(main)
	await shot("w11_bluetooth", 1.2)
	_focus_prefix("bl:Bluetooth#")
	await press("a")
	await shot("w12_bt_geraet", 1.0)
	await press("b")
	await wait(0.4)
	_focus_key("bl:radio")
	await press("a")
	await shot("w13_bt_aus_frage", 1.0)
	await _close_all()
	# Energie
	load("res://src/ui/layers/win_energie.gd").open_for(main)
	await shot("w14_energie", 1.4)
	_focus_key("en:monitor:ac")
	await press("right")
	await shot("w15_energie_bildschirm", 1.4)
	await _close_all()

	# Doktor: kein WLAN, Bluetooth aus
	Lage.demo_extra = { "wlan": { "radio": "an", "internet": "keins", "connected": "" }, "bt": { "radio": "aus", "paired": 2 } }
	main.open_doktor()
	await shot("d01_doktor_wlan_bt", 2.0)
	# Mit dem Steuerkreuz hin (die Liste rollt mit): unten rechts liegt „Bluetooth ist aus“.
	_focus_key("dk:emu:dolphin")
	await press("right")
	await press("down", 3)
	await shot("d01b_bt_karte", 0.8)
	await press("a")
	await shot("d02_bt_einschalten", 0.5)
	await wait(2.4)
	await shot("d03_bt_an", 0.4)
	_focus_key("dk:netz")
	await press("a")
	await shot("d04_wlan_aus_doktor", 1.6)
	await _close_all()
	Lage.demo_extra = {}

