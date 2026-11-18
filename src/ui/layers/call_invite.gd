extends "res://src/ui/layers/sheet.gd"
## Guide → Discord → „Alle im Call zu Remote Play einladen“: Leiste mit allen Leuten im Call.
## Je Person steht, welcher Steam-Freund sie ist (gemerkt, sicherer Vorschlag oder noch offen);
## A wählt (drei Vorschläge, „Andere wählen …“, „Nicht einladen“), X lässt jemanden diesmal aus.
## Unten schickt ein Druck alle Einladungen; danach steht bei jeder Person, wie es lief.
## Die Logik steckt in src/core/call_invite.gd.

const CI := preload("res://src/core/call_invite.gd")
const SheetC := preload("res://src/ui/layers/sheet.gd")

const Main := preload("res://src/main.gd")
var main: Main
var _choice := {}            ## Discord-ID → Steam-ID ("" = diesmal nicht einladen)
var _plan: Dictionary = {}
var _done: Array = []        ## rows nach dem Senden (leer: noch nicht gesendet)
var _sending := false
var _sig := ""

const STATE_TEXT := { "online": "Online", "away": "Abwesend", "busy": "Beschäftigt", "snooze": "Abwesend", "game": "Im Spiel", "offline": "Offline" }


func build() -> void:
	var av := CI.availability()
	var ch := str(Voice.channel.get("name", ""))
	var head := "Ganze Gruppe einladen" if str(av.label).begins_with("Ganze") else "Alle im Call einladen"
	setup(head, "Remote Play Together · %s%s" % [Library.display_title(Launcher.current), ("  ·  " + ch) if ch != "" else ""], 800)
	var ic := U.icon("controller", 44, "accent")
	ic.custom_minimum_size = Vector2(56, 56)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	set_header_image(ic)
	_replan()
	super()
	Voice.changed.connect(_on_voice)
	Social.updated.connect(_on_social)


func _replan() -> void:
	_plan = CI.build_plan(Voice.members, CI.load_map(), _choice, Social.steam_friends, Voice.me_id, CI.my_steam(), CI.joined_now())
	_sig = _people_sig()


func _people_sig() -> String:
	return ",".join(PackedStringArray(Voice.members.map(func(m): return str(m.get("id", "")))))


func _on_voice() -> void:
	if _sending or not is_inside_tree() or _people_sig() == _sig:
		return
	_replan()
	refill()


func _on_social(what: String) -> void:
	if what == "steam" and not _sending and _done.is_empty() and is_inside_tree():
		_replan()
		refill()


func _rows() -> Array:
	return _done if not _done.is_empty() else (_plan.get("rows", []) as Array)


func fill() -> void:
	var rows := _rows()
	if rows.is_empty():
		add_label("Außer dir ist gerade niemand im Call.", "m", "muted")
		return
	var focus_set := false
	for r in rows:
		var it := _person_row(r)
		if not focus_set and _done.is_empty() and str(r.status) == "unmapped":
			it.set_meta("uz_default", true)
			focus_set = true
		add_row(it)
	add_gap(10)
	var n := (_plan.get("invite", []) as Array).size()
	var btn = SettingRow.new()
	if _sending:
		btn.setup("action", "Lade ein …", "", null)
		btn.value_text = U.plural(n, "Einladung", "Einladungen")
		btn.icon_name = "controller"
	elif not _done.is_empty():
		var failed := _done.filter(func(r): return str(r.status) == "failed").size()
		btn.setup("action", "Nochmal versuchen" if failed > 0 else "Fertig", "", null)
		btn.icon_name = "refresh" if failed > 0 else "check"
		btn.value_text = U.plural(failed, "ging nicht", "gingen nicht") if failed > 0 else ""
		btn.on_activate = func() -> void:
			if failed > 0:
				_done = []
				_replan()
				_send()
			else:
				close()
	else:
		var names := PackedStringArray((_plan.get("invite", []) as Array).map(func(r): return str(r.name)))
		btn.setup("action", ("%d zu Remote Play einladen" % n) if n > 0 else "Niemand zum Einladen", "", null)
		btn.icon_name = "controller"
		btn.value_text = ", ".join(names)
		btn.on_activate = func() -> void:
			if n == 0:
				Toasts.show_toast("Niemand zum Einladen", "Wähle bei den Leuten oben ihren Steam-Freund (A).", "info", { "ms": 3500, "quiet": true })
				return
			_send()
	if not focus_set:
		btn.set_meta("uz_default", true)
	add_row(btn)
	# Nach add_row: SettingRow setzt den Hinweis in _ready selbst.
	btn.set_meta("uz_hint_a", "—" if _sending else ("Schließen" if btn.title == "Fertig" else ("Nochmal" if not _done.is_empty() else "Alle einladen")))
	var warn := CI.limit_warning(int(_plan.get("guests", 0)))
	if warn != "":
		add_gap(4)
		add_label(warn, "s", "warn")
	var ex := CI.explain(rows)
	if ex != "":
		add_gap(4)
		add_label(ex, "s", "faint")


func _person_row(r: Dictionary) -> Control:
	var it = ListItem.new()
	var st := str(r.status)
	var sn := str(r.get("steam_name", ""))
	if sn == "":
		sn = "Steam-Freund"
	var sub := ""
	var trail := ""
	var color := "muted"
	match st:
		"invite":
			trail = "Einladen"
			match str(r.how):
				"map": sub = "Steam: %s" % sn
				"suggest": sub = "Steam: %s · Vorschlag, wird gemerkt" % sn
				_: sub = "Steam: %s · gewählt" % sn
		"joined":
			trail = "Dabei"
			sub = "Steam: %s · schon in der Sitzung" % sn
			color = "ok"
		"unmapped":
			trail = "Wählen"
			var sg: Array = r.get("suggestions", [])
			sub = (
					"Vielleicht %s? A zum Wählen" % " oder ".join(PackedStringArray(sg.slice(0,
					2).map(func(s): return str(s.name))))) if not sg.is_empty() else "Welcher Steam-Freund? A zum Wählen"
			color = "accent"
		"excluded":
			trail = "—"
			sub = "Wird diesmal nicht eingeladen"
			color = "faint"
		"not_friend":
			trail = "—"
			sub = "Steam: %s · ist kein Steam-Freund" % sn
			color = "warn"
		"duplicate":
			trail = "—"
			sub = "Steam: %s · kommt schon über jemand anderen" % sn
			color = "faint"
		"invited":
			trail = "Eingeladen"
			sub = "Steam: %s · Einladung unterwegs" % sn
			color = "ok"
		"failed":
			trail = "Fehler"
			sub = "Ging nicht: %s" % str(r.get("reason", "Steam hat nicht geantwortet")).get_slice("Lade im Steam-Overlay", 0).strip_edges()
			color = "warn"
	if _sending and st == "invite":
		trail = "Sende …"
	it.setup(str(r.name), sub, trail)
	it.avatar = true
	it.image_url = str(r.get("avatar", ""))
	it.sub_color = color
	var did := str(r.id)
	if _done.is_empty() and not _sending:
		it.set_meta("uz_hint_a", "Steam-Freund wählen")
		it.activated.connect(_pick.bind(r))
		if st != "joined":
			it.set_meta("uz_hint_x", "Doch einladen" if st == "excluded" else "Nicht einladen")
			it.set_meta("uz_on_x", func() -> void:
				if _choice.has(did) and str(_choice[did]) == "":
					_choice.erase(did)
				else:
					_choice[did] = ""
				_replan()
				refill()
			)
	else:
		it.set_meta("uz_hint_a", "—")
	return it


## Wer ist diese Person bei Steam? Drei Vorschläge, alle Freunde, nicht einladen.
func _pick(r: Dictionary) -> void:
	var did := str(r.id)
	var dname := str(r.name)
	var m := Voice.member(did)
	var sugg: Array = r.get("suggestions", [])
	if sugg.is_empty():
		sugg = CI.suggest(m if not m.is_empty() else { "id": did, "name": dname }, Social.steam_friends)
	var cur := str(r.get("steam", ""))
	var s = SheetC.new()
	s.setup("Wer ist %s bei Steam?" % dname, "Änderbar unter Einstellungen → Konten → Discord.", 720)
	s.fill_func = func(sheet) -> void:
		var first := true
		for g in sugg:
			var it = ListItem.new()
			var pct := int(round(float(g.score) * 100.0))
			it.setup(str(g.name), "Passt zu %d %% · %s" % [pct, STATE_TEXT.get(str(g.state), "Online")], "Vorschlag" if first else "")
			it.avatar = true
			it.image_url = str(g.avatar)
			it.status = str(g.state)
			if (cur == "" and first) or str(g.id) == cur:
				it.set_meta("uz_default", true)
			first = false
			var gd: Dictionary = g
			it.activated.connect(func() -> void:
				sheet.close()
				_choose(did, dname, str(gd.id), str(gd.name))
			)
			sheet.add_row(it)
		var other = ListItem.new()
		other.setup("Andere wählen …", U.plural(Social.steam_friends.size(), "Steam-Freund", "Steam-Freunde"))
		other.icon_name = "search"
		if sugg.is_empty():
			other.set_meta("uz_default", true)
		other.activated.connect(func() -> void:
			sheet.close()
			_pick_any(did, dname, cur)
		)
		sheet.add_row(other)
		var none = ListItem.new()
		none.setup("Nicht einladen", "Nur diesmal")
		none.icon_name = "close"
		none.activated.connect(func() -> void:
			sheet.close()
			_choice[did] = ""
			_replan()
			refill()
		)
		sheet.add_row(none)
		if CI.map_steam(CI.load_map(), did) != "":
			var rm = ListItem.new()
			rm.setup("Zuordnung entfernen", "Uzai fragt beim nächsten Mal wieder")
			rm.icon_name = "trash"
			rm.activated.connect(func() -> void:
				sheet.close()
				CI.forget(did)
				_choice.erase(did)
				_replan()
				refill()
			)
			sheet.add_row(rm)
		if Social.steam_friends.is_empty():
			sheet.add_gap(6)
			sheet.add_label("Bei Steam anmelden (Einstellungen → Konten).", "s", "faint")
	main.open_layer(s)


## Alle Steam-Freunde (online zuerst), auch wer offline ist.
func _pick_any(did: String, dname: String, cur: String) -> void:
	var list: Array = Social.steam_friends.duplicate()
	list.sort_custom(func(a, b):
		var ao := str(a.get("state", "offline")) != "offline"
		var bo := str(b.get("state", "offline")) != "offline"
		if ao != bo:
			return ao
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	var s = SheetC.new()
	s.setup("Steam-Freund für %s" % dname, U.plural(list.size(), "Freund", "Freunde"), 720)
	s.fill_func = func(sheet) -> void:
		for f in list:
			var it = ListItem.new()
			var real := str(f.get("real", ""))
			it.setup(str(f.get("name", "")), (real + " · " if real != "" else "") + str(STATE_TEXT.get(str(f.get("state", "")), "Online")))
			it.avatar = true
			it.image_url = str(f.get("avatar", ""))
			it.status = str(f.get("state", ""))
			if str(f.get("id", "")) == cur:
				it.set_meta("uz_default", true)
			var fd: Dictionary = f
			it.activated.connect(func() -> void:
				sheet.close()
				_choose(did, dname, str(fd.id), str(fd.get("name", "")))
			)
			sheet.add_row(it)
		if list.is_empty():
			sheet.add_label("Keine Steam-Freunde geladen. Unter Einstellungen → Konten → Steam anmelden.", "m", "muted")
	main.open_layer(s)


func _choose(did: String, dname: String, sid: String, sname: String) -> void:
	CI.remember(did, sid, dname, sname)
	_choice.erase(did)
	_replan()
	refill()
	Toasts.show_toast("%s ist %s bei Steam" % [dname, sname], "Gemerkt. Ändern: Einstellungen → Konten → Discord.", "check", { "ms": 2400, "quiet": true })


func _send() -> void:
	var invite: Array = _plan.get("invite", [])
	if invite.is_empty() or _sending:
		return
	# Sichere Vorschläge, mit denen jetzt eingeladen wird, gelten als bestätigt.
	for r in invite:
		if str(r.how) == "suggest":
			CI.remember(str(r.id), str(r.steam), str(r.name), str(r.steam_name))
	_sending = true
	refill()
	Toasts.show_toast("Remote-Play-Einladungen …", ", ".join(PackedStringArray(invite.map(func(r): return str(r.name)))), "steam", { "ms": 2000, "quiet": true })
	var res: Dictionary = await CI.send(invite)
	_sending = false
	if not is_inside_tree():
		return
	CI.note_joined(res.get("joined", []) if res.get("joined") is Array else [])
	_done = CI.apply_result(_plan.get("rows", []), res)
	refill()
	var line := CI.summary(_done)
	var invited := _done.filter(func(r): return str(r.status) == "invited")
	if not invited.is_empty():
		Launcher.rp_invited(", ".join(PackedStringArray(invited.map(func(r): return str(r.name)))))
		var parts := line.split(" · ", true, 1)
		Toasts.show_toast(parts[0],
				(parts[1] + ". " if parts.size() > 1 else "") + "Jeder nimmt die Einladung in Steam an und spielt mit dem eigenen Controller mit.", "check",
				{ "sound": "select", "ms": 8000 })
	else:
		Toasts.show_toast("Einladen ging nicht", str(res.get("text", "")) if str(res.get("text", "")) != "" else line, "warning", { "ms": 9000 })
