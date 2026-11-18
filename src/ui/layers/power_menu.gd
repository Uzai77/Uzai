extends "res://src/ui/layers/modal.gd"
## Ausschalten-Menü in zwei Gruppen: Uzai (Ruhemodus, beenden) und PC (Energiesparen, Neustart,
## Herunterfahren). Jede Zeile sagt in einem Satz, was passiert; läuft ein Spiel, sagt der Satz oben,
## was offen bleibt.

const ActRow := preload("res://src/ui/components/act_row.gd")
const PowerConfirm := preload("res://src/ui/layers/power_confirm.gd")

const Main := preload("res://src/main.gd")
var main: Main


func fill() -> void:
	width = 680.0
	set_meta("uz_hint_b", "Zurück")
	# Aus dem Guide geöffnet: Hinweise mittig wie im Guide.
	if Launcher.guide_open:
		set_meta("uz_hints_center", true)
	var head := U.vbox(6)
	var t := U.label("Ausschalten", "36", "text", "title")
	t.clip_text = false
	head.add_child(t)
	if Launcher.in_game:
		head.add_child(U.label("%s läuft. Ruhemodus und Energiesparen lassen es offen." % Library.display_title(Launcher.current),
				"m", "warn", "regular", true))
	box.add_child(head)
	# Zwei Gruppen, jede Zeile mit einem Satz, was passiert: „Ruhemodus“ (nur Uzai, der PC läuft) und
	# „Energiesparen“ (Windows schläft) lasen sich sonst wie dasselbe.
	var uzai := [
		["Ruhemodus", "image", "rest", "Diashow auf dem Bildschirm, der PC läuft weiter"],
		["Uzai beenden", "desktop", "quit", "Zurück zu Windows"],
	]
	# Nach dem Schließen im Hintergrund bereit: „Schließen“ (die Guide-Taste startet Uzai wieder) und
	# „Ganz beenden“ (ohne Wächter).
	if Helper.wake_active():
		uzai[1] = ["Uzai schließen", "desktop", "quit", "Die Guide-Taste startet Uzai wieder"]
		uzai.append(["Uzai ganz beenden", "close", "quit_full", "Auch ohne Guide-Taste"])
	# Schlaf-Timer (src/core/schlaf_timer.gd) und „Nur hören“ (Bild dunkel, Musik läuft) gleich nach
	# dem Ruhemodus: beides führt dorthin.
	var st: Node = _schlaf()
	if st:
		var stand: String = st.text()
		uzai.insert(1, ["Schlaf-Timer", "clock", "schlaf", stand if stand != "" else "Später von selbst in den Ruhemodus"])
	if not Launcher.in_game and bool(Music.now.get("playing", false)):
		uzai.insert(2 if st else 1, ["Nur hören", "headset", "hoeren", "Bild dunkel, die Musik läuft weiter"])
	var pc := [
		["Energiesparen", "moon", "sleep", "Der PC schläft, Netzschalter oder Taste weckt ihn"],
		["Neu starten", "restart", "restart", ""],
		["Herunterfahren", "power", "shutdown", ""],
	]
	var i := 0
	for gruppe in [["Uzai", uzai], ["PC", pc]]:
		var list := U.vbox(6)
		var kopf := U.label(str(gruppe[0]), "s", "faint", "medium")
		kopf.uppercase = true
		list.add_child(kopf)
		box.add_child(list)
		for it in gruppe[1]:
			var row = ActRow.new()
			row.setup(str(it[0]), str(it[1]), str(it[3]))
			row.set_meta("uz_key", "p:" + str(it[2]))
			var action: String = it[2]
			row.activated.connect(func() -> void: _do(action))
			if action == "rest":
				row.set_meta("uz_default", true)
			list.add_child(row)
			# Zeilen erscheinen kurz nacheinander (Staffel: höchstens vier Glieder, nach der Fläche).
			row.modulate.a = 0.0
			U.ankommen(row, U.T_ORT, "uz_zeile").tween_property(row, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE + U.staffel(i))
			i += 1


func _schlaf() -> Node:
	var rest: Node = main.rest if main else null
	return rest.get("schlaf") if rest else null


func _do(action: String) -> void:
	close()
	if action == "schlaf":
		var st: Node = _schlaf()
		if st:
			main.open_choice("Schlaf-Timer", st.optionen(Video.active, st.art()), st.stufe, func(v: Variant) -> void: st.setzen(str(v)),
					"Danach Ruhemodus. Video und Musik halten an.")
		return
	if action == "hoeren":
		var rest: Node = main.rest if main else null
		if rest:
			rest.enter("nur hören", { "hoeren": true })
		return
	if action == "quit" or action == "quit_full":
		if main:
			main.ask_quit_uzai(action == "quit_full")
		return
	# Ruhemodus und Schlafen (src/core/rest.gd): das Spiel bleibt offen.
	if action == "rest" or action == "sleep":
		var rest: Node = main.rest if main else null
		if rest:
			if action == "rest":
				rest.enter("menu")
			else:
				rest.ask_pc_sleep()
		return
	# PC aus bzw. neu: erst die Rückfrage (Standard „Abbrechen“, bestätigt nur mit gehaltenem A).
	if action in ["restart", "shutdown"] and main:
		var pc = PowerConfirm.new()
		pc.action = action
		pc.spiel = Library.display_title(Launcher.current) if Launcher.in_game else ""
		pc.on_confirm = func() -> void: ausschalten_pc(main, action)
		main.open_layer(pc)
		return
	await ausschalten_pc(main, action)


## Nach der Rückfrage: laufendes Spiel beenden, speichern, dann Animation und Befehl an Windows.
static func ausschalten_pc(m: Main, action: String) -> void:
	if Launcher.in_game:
		await Launcher.quit_game()
	Library.save()
	Config.save_settings()
	match action:
		"quit":
			m.get_tree().quit()
		_:
			if Config.is_windows():
				# Erst die Ausschalt-Animation (das Bild bleibt danach schwarz), dann der Befehl an Windows.
				if m and is_instance_valid(m):
					m.power_off_pc(action)
				else:
					Helper.run("power", { "action": action })
			else:
				Toasts.show_toast("Nur unter Windows", "Ausschalten steuert Uzai nur auf dem Konsolen-PC.", "power")
