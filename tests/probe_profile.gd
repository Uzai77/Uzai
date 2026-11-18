extends "res://tests/probe_base.gd"
## Mehrere Nutzerprofile (Roadmap 109) am Bildschirm: „Wer spielt?“ beim Start, PIN-Eingabe
## (richtig gezeigt, falsch mit Bremse), Profil anlegen und bearbeiten, Kinderprofil mit Regeln,
## Guide → Profil wechseln, der Wechsel (Bild gleitet zur Mitte) und die Begrüßung danach,
## die Startseite im Kinderprofil und der Hinweis zur Spielzeit. Ausgabe „PP ok/FAIL …“.

const Profiles := preload("res://src/core/profiles.gd")
const ProfilePicker := preload("res://src/ui/layers/profile_picker.gd")
const ProfileEdit := preload("res://src/ui/layers/profile_edit.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("PP %s %s" % ["ok  " if cond else "FAIL", what])


func _top() -> Control:
	return Nav.layers.back() if not Nav.layers.is_empty() else null


func _top_name() -> String:
	var t := _top()
	if t == null:
		return ""
	var s: Script = t.get_script()
	return s.resource_path.get_file() if s else ""


func _close_all() -> void:
	while _top():
		_top().close()
		await wait(0.25)


func _key(root: Node, key: String) -> Control:
	for c in root.find_children("*", "", true, false):
		if c is Control and str(c.get_meta("uz_key", "")) == key:
			return c
	return null


func run() -> void:
	# Familie anlegen: Robin (aktiv), Lena mit PIN, Mia als Kinderprofil.
	var me := Config.profile_id
	Config.update_profile(me, { "name": "Robin", "color": "gold", "avatar": "games" })
	var lena := Config.add_profile("Lena", "blau", "buchstabe")
	Config.update_profile(str(lena.id), { "pin": Profiles.make_pin("2580") })
	var mia := Config.add_profile("Mia", "rose", "star_f")
	Config.update_profile(str(mia.id), { "kid": true, "rules": { "age": 6, "limit": 60 } })
	Config.update_profile(me, { "pin": Profiles.make_pin("1357") })
	_ck(Config.profile_list().size() == 3 and Config.needs_picker(), "drei Profile, beim Start wird gefragt")
	await wait(0.5)

	# 1. „Wer spielt?“ wie beim Start.
	var pk = ProfilePicker.new()
	pk.main = main
	pk.mode = "start"
	main.open_layer(pk)
	await shot("01_wer_spielt", 1.2)
	await press("right")
	await shot("02_wer_spielt_auswahl", 0.9)
	_ck(str(Nav.focused().get_meta("uz_key", "")) == "profil:" + str(lena.id), "rechts: Lena gewählt")

	# 2. PIN: Lena hat eine. Erst zwei Ziffern, dann falsch.
	await press("a")
	await wait(0.8)
	_ck(_top_name() == "profile_pin.gd", "Lena: Ziffernfeld (%s)" % _top_name())
	var pin = _top()
	pin._on_key("2")
	pin._on_key("5")
	await shot("03_pin_eingabe", 0.5)
	pin._on_key("8")
	pin._on_key("1")
	pin._on_key("ok")
	await wait(1.4)
	await shot("04_pin_falsch", 0.2)
	_ck(_top_name() == "profile_pin.gd" and Config.pin_tries_left([str(lena.id)]) == 2, "falsche PIN: bleibt offen, Bremse zählt")
	await press("b")
	await wait(0.6)

	# 3. Anlegen: letzte Karte → Name → Bearbeiten.
	await press("right", 2)
	_ck(str(Nav.focused().get_meta("uz_key", "")) == "profil:neu", "Karte „Profil hinzufügen“")
	await shot("05_hinzufuegen_karte", 0.6)
	await press("a")
	await wait(0.9)
	await shot("06_anlegen_name", 0.3)
	var kb = _top()
	if kb and kb.has_signal("done"):
		kb.done.emit("Noah")
		kb.close()
	await wait(1.2)
	_ck(_top_name() == "profile_edit.gd" and Config.profile_list().size() == 4, "neues Profil „Noah“, Bearbeiten offen (%s)" % _top_name())
	await shot("07_anlegen_bearbeiten", 0.4)
	await press("down", 2)
	await press("right")
	await wait(0.3)
	await press("down")
	await press("right", 3)
	await shot("08_bearbeiten_bild_farbe", 0.6)
	await _close_all()

	# 4. Kinderprofil Mia: Regeln.
	main.open_profiles("manage")
	await wait(1.0)
	await shot("09_profile_verwalten", 0.3)
	ProfileEdit.open_for(main, str(mia.id))
	await wait(0.9)
	await press("down", 6)
	await shot("10_kinderprofil_regeln", 0.6)
	await press("down", 4)
	await shot("11_kinderprofil_zeit", 0.6)
	await _close_all()

	# 5. Guide → System → Profil wechseln.
	main.toggle_guide("system")
	await wait(1.4)
	var row := _find_text(main._guide, "Profil wechseln")
	_ck(row != null, "Guide: Zeile „Profil wechseln“")
	if row:
		Nav.focus(row)
	await shot("12_guide_profil_wechseln", 0.6)
	if row:
		Nav.activate(row)
	await wait(1.2)
	_ck(_top_name() == "profile_picker.gd", "Guide öffnet „Wer spielt?“")
	await shot("13_guide_wer_spielt", 0.3)
	# Mia wählen: alles löst sich, ihr Bild gleitet zur Mitte (Probe startet nicht neu).
	var mc := _key(_top(), "profil:" + str(mia.id))
	if mc:
		Nav.focus(mc)
		await wait(0.5)
		Nav.activate(mc)
	await shot("14_wechsel", 0.42)
	await wait(0.8)
	_ck(str(Config.profiles.last) == str(mia.id), "Wechsel merkt sich Mia als zuletzt gewählt")
	await _close_all()
	if main._guide and is_instance_valid(main._guide):
		main._guide.close()
	await wait(0.6)

	# 6. Wie im neuen Uzai: Begrüßung, dann die Startseite im Kinderprofil.
	for g in Library.games:
		var n := absi(str(g.id).hash()) % 5
		g["age"] = ["usk0", "usk6", "usk12", "usk16", "usk18"][n]
	Config.profile_id = str(mia.id)
	Config.profile_dir = Profiles.dir_of(Config.data_dir, str(mia.id))
	Library.forget_visible()
	main._rebuild()
	await wait(0.4)
	ProfilePicker.welcome(main)
	await shot("15_hallo", 0.35)
	await wait(1.6)
	await shot("16_kind_startseite", 0.5)
	var vis: Array = Library.visible_games()
	_ck(not vis.is_empty() and vis.all(func(g: Dictionary) -> bool: return Profiles.game_age(g) in [0, 6]), "Kinderprofil: nur Spiele bis 6 (%d)" % vis.size())
	_ck(not main.order.has("shop"), "Kinderprofil: kein Shop in der Leiste")

	# 7. Spielzeit: Hinweis kurz vor Schluss, dann „Für heute ist Schluss“ vor dem Start.
	main.kid_time.hint(9 * 60)
	await shot("17_zeit_hinweis", 1.0)
	Config.kid_time_add(60 * 60)
	var g0: Dictionary = vis[0] if not vis.is_empty() else {}
	main.kid_time.may_launch(g0)
	await shot("18_zeit_um", 1.0)
	await _close_all()

	# 8. Einstellungen → Konten: Profil, wechseln, verwalten.
	Config.profile_id = me
	Config.profile_dir = Profiles.dir_of(Config.data_dir, me)
	main._rebuild()
	await wait(0.5)
	main.goto("settings", "konten")
	await wait(1.2)
	await shot("19_einstellungen_konten", 0.3)
	print("PP Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))


func _find_text(root: Node, t: String) -> Control:
	if root == null:
		return null
	for c in root.find_children("*", "", true, false):
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL:
			for l in c.find_children("*", "Label", true, false):
				if (l as Label).text == t:
					return c
			if str(c.get("title")) == t:
				return c
	return null
