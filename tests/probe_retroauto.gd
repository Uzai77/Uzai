extends "res://tests/probe_base.gd"
## Probe „Retro ohne Einrichtung“ (Roadmap 19, 104): Übersicht mit gefundenen Systemen und Karten,
## Zustimmung mit Lizenz, Lizenztext, Fortschritt, Abbrechen, Bereit mit BIOS-Hinweis, alle auf
## einmal, Einrichtung (Schritt „Suche“), Doktor („Einrichten“) und Einstellungen → Emulation.
## Vorführung: ohne Netz, nichts wird geladen (src/core/retro_laden.gd, _demo).
## Aufruf: A2_PROJ=<worktree> A2_TIMEOUT=600 bash a2_run.sh res://tests/probe_retroauto.gd retroauto

const Laden := preload("res://src/core/retro_laden.gd")
const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func focus_key(k: String) -> bool:
	for c in Nav.focusables(Nav.scope_root()):
		if str(c.get_meta("uz_key", "")) == k:
			Nav.focus(c, true)
			return true
	print("nicht gefunden: ", k)
	return false


func close_all() -> void:
	for l in Nav.layers.duplicate():
		if is_instance_valid(l) and l.has_method("close"):
			l.close()
	await wait(0.7)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	for sid in ["ps2", "ps1", "gc", "gba", "switch"]:
		Config.set_system(sid, "enabled", true)
	main.background.clear_image()
	await wait(0.8)
	var l: Control = load("res://src/ui/layers/retro_einrichten.gd").open_for(main)
	await wait(1.4)
	await shot("01_uebersicht", 0.2)
	focus_key("ra:pcsx2")
	await shot("02_karte_gewaehlt", 0.5)
	await press("a")
	await shot("03_zustimmung", 0.8)
	await press("y")
	await shot("04_lizenz", 0.9)
	await press("down", 6, 0.12)
	await shot("05_lizenz_geblaettert", 0.5)
	await press("b")
	await wait(0.5)
	await press("a")
	await wait(1.1)
	await shot("06_laedt", 0.0)
	await wait(2.6)
	await shot("07_bereit_bios", 0.3)
	await press("a")
	await shot("08_bios_hinweis", 0.7)
	await press("b")
	await wait(0.4)
	focus_key("ra:retroarch")
	await press("y")
	await shot("09_lizenz_wahl", 0.7)
	await press("b")
	await wait(0.4)
	await press("x")
	await shot("10_alle_zustimmung", 0.9)
	await press("a")
	await wait(0.9)
	await shot("11_alle_laden", 0.0)
	focus_key("ra:retroarch")
	await press("a")
	await shot("12_abbrechen_frage", 0.7)
	focus_key("")
	var top: Node = Nav.top_layer()
	for c in Nav.focusables(top):
		if c is Button and str((c as Button).text) == "Abbrechen":
			Nav.focus(c, true)
	await press("a")
	await shot("13_abgebrochen", 1.0)
	await wait(5.0)
	await shot("14_danach", 0.3)
	focus_key("ra:row:Nach Updates sehen")
	await press("a")
	await shot("15_updates", 1.2)
	await close_all()
	# Einrichtung, Schritt „Suche“: frischer Stand ohne eingerichtete Emulatoren.
	Laden.inst().demo_bereit.clear()
	Laden.inst().auftraege.clear()
	for id in ["pcsx2", "duckstation", "dolphin", "retroarch"]:
		Config.set_emulator(id, "exe", "")
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.restart", true)
	Config.set_value("einrichtung.step", "spiele")
	Wizard.open_for(main, false)
	await wait(4.0)
	focus_key("su:f:retro")
	await shot("16_einrichtung_suche", 0.6)
	await press("a")
	await shot("17_einrichtung_retro", 1.4)
	await close_all()
	await close_all()
	# Doktor: „Emulator fehlt → Einrichten“.
	main.open_doktor()
	await wait(1.6)
	focus_key("dk:emu:dolphin")
	await shot("18_doktor_einrichten", 0.5)
	await press("a")
	await wait(2.4)
	await shot("19_doktor_offizielle_quelle", 0.4)
	await close_all()
	await close_all()
	main.open_setting("emulation", "")
	await wait(1.6)
	await shot("20_einstellungen_emulation", 0.3)
