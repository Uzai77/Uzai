extends "res://tests/probe_base.gd"
## „In 2 Minuten fertig“ und Uzai-Doktor (Punkte 51, 133): Einrichtung Schritt für Schritt –
## Sprache (der Controller wird still erkannt), Theme mit großer Vorschau, Suche mit
## Fortschritt, Fertig mit den freiwilligen Schritten –, danach der Doktor mit mehreren Karten,
## „Beheben“ (Emulator suchen), „Mehr dazu“, Einstellungen → System, Guide → System und der
## Hinweis auf der Startseite.
## Aufruf (mit Suchorten, die es wirklich gibt, und etwas langsamer, damit der Fortschritt zu sehen ist):
##   UZAI_SETUP_DRIVES=<ordner> UZAI_SETUP_SLOW=250 A2_PROJ=<worktree> bash a2_run.sh res://tests/probe_einrichtung2.gd einrichtung2

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func focus_key(k: String) -> bool:
	for c in Nav.focusables(Nav.scope_root()):
		if str(c.get_meta("uz_key", "")) == k:
			Nav.focus(c, true)
			return true
	print("nicht gefunden: ", k)
	return false


func focus_title(root: Control, t: String) -> bool:
	for c in Nav.focusables(root):
		if str(c.get("title")) == t:
			Nav.focus(c, true)
			return true
	print("Zeile nicht gefunden: ", t)
	return false


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.restart", false)
	Config.set_value("einrichtung.tour", true)
	Config.set_value("einrichtung.mehr", false)
	Config.set_value("einrichtung.step", "willkommen")
	Config.set_value("einrichtung.started", int(Time.get_unix_time_from_system()) - 102)
	Wizard.open_for(main, false)
	await wait(2.4)
	await shot("01_sprache", 0.2)
	await press("up")
	await shot("02_sprache_auswahl", 0.4)
	# Sprache wechseln: wirkt sofort, die Einrichtung baut sich in der neuen Sprache neu auf.
	await press("right")
	await press("a")
	await wait(1.8)
	print("Sprache: ", TranslationServer.get_locale(), " · Einrichtung offen: ", Nav.top_layer() != null)
	await shot("02b_english", 0.2)
	focus_key("su:lang:de")
	await press("a")
	await wait(1.8)
	print("Sprache zurück: ", TranslationServer.get_locale())
	focus_key("su:start")
	# Der Controller wird still erkannt (wie mit einem echten Xbox-Controller).
	Wizard.probe_pad = true
	Wizard._detected = "Xbox Wireless Controller"
	await press("a")
	await wait(1.0)
	# Weiter zum Theme.
	focus_key("su:weiter")
	await press("a")
	await wait(1.4)
	await shot("09_theme", 0.3)
	focus_key("su:t:retro")
	await wait(0.9)
	await shot("10_theme_vorschau_retro", 0.2)
	focus_key("su:t:kacheln")
	await wait(0.9)
	await shot("11_theme_vorschau_kacheln", 0.2)
	focus_key("su:p:papier")
	await wait(0.9)
	await shot("12_theme_farbschema_papier", 0.2)
	focus_key("su:weiter")
	await press("a")
	await shot("13_suche_laeuft", 1.1)
	await wait(6.0)
	await shot("14_suche_fertig", 0.4)
	focus_key("su:weiter")
	await press("a")
	await wait(1.2)
	await shot("15_fertig", 0.3)
	# In der Vorführung sind alle Konten verbunden; wie bei einem frischen PC ohne Konten:
	Wizard.probe_no_accounts = true
	var w: Node = Nav.top_layer()
	w.call("_show_step", int(w.get("_idx")), 0, true)
	await wait(0.6)
	focus_key("su:mehr:konten")
	await shot("16_fertig_konten_freiwillig", 0.4)
	await press("a")
	await wait(1.0)
	await shot("17_konten_eingereiht", 0.3)
	Wizard.probe_no_accounts = false
	# Zu Ende: über „Später“ bis Fertig, dann los.
	await press("y")
	await wait(0.8)
	if str(Config.get_value("einrichtung.step", "")) != "fertig":
		await press("y")
		await wait(0.8)
	if focus_key("su:los"):
		await press("a")
	await wait(1.4)
	print("Einrichtung zu: ", Nav.top_layer() == null, " · fertig: ", Config.get_value("einrichtung.done", false))
	# Uzai-Doktor
	main.open_doktor()
	await wait(1.6)
	await shot("18_doktor", 0.2)
	focus_key("dk:emu:dolphin")
	await shot("19_doktor_emulator_gewaehlt", 0.4)
	await press("a")
	await shot("20_doktor_beheben_sucht", 0.5)
	await wait(1.2)
	await shot("21_doktor_behoben", 0.2)
	await wait(2.2)
	await shot("22_doktor_danach", 0.2)
	focus_key("dk:speicher")
	await press("y")
	await shot("23_doktor_mehr_dazu", 0.7)
	await press("b")
	await wait(0.4)
	focus_key("dk:pad_akku:DualSense")
	await press("a")
	await shot("24_doktor_so_gehts", 0.7)
	await press("b")
	await wait(0.4)
	await press("b")
	await wait(0.8)
	# Einstellungen → System und Controller
	main.open_setting("system", "")
	await wait(1.4)
	focus_title(main.view_host, "Uzai-Doktor")
	await shot("25_einstellungen_system", 0.6)
	main.open_setting("controller", "")
	await wait(1.4)
	focus_title(main.view_host, "Controller koppeln")
	await shot("26_einstellungen_controller", 0.6)
	# Guide → System
	main.goto("games")
	await wait(1.0)
	main.toggle_guide("system")
	await wait(1.4)
	await shot("27_guide_system", 0.3)
	main.toggle_guide()
	await wait(1.0)
	# Hinweis auf der Startseite
	Config.set_value("system.doktor_seen", "")
	var shown: bool = await main._doktor_hint(0.0)
	print("Hinweis gezeigt: ", shown)
	await shot("28_hinweis_startseite", 0.9)
