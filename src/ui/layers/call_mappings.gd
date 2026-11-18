extends "res://src/ui/layers/sheet.gd"
## Einstellungen → Konten → Discord → „Zuordnungen Discord ↔ Steam“: wer aus Discord welcher
## Steam-Freund ist (für „Alle im Call zu Remote Play einladen“). A ändert oder entfernt, X
## entfernt sofort. Die Liste kommt aus call_invite.gd (Config „accounts.discord_steam“).

const CI := preload("res://src/core/call_invite.gd")
const SheetC := preload("res://src/ui/layers/sheet.gd")

const Main := preload("res://src/main.gd")
var main: Main
var on_change: Callable


func build() -> void:
	setup("Zuordnungen Discord ↔ Steam", "Wer aus deinen Discord-Calls welcher Steam-Freund ist", 780)
	super()


func fill() -> void:
	var rows := CI.map_rows(CI.load_map(), Social.steam_friends)
	if rows.is_empty():
		add_label("Noch keine. Sie entstehen beim Einladen zu Remote Play (Guide → Discord).", "m", "muted")
		return
	for r in rows:
		var it = ListItem.new()
		it.setup(str(r.discord_name), "Steam: " + str(r.steam_name), "")
		it.avatar = true
		var f := _friend(str(r.steam))
		it.image_url = str(f.get("avatar", ""))
		if f.is_empty() and not Social.steam_friends.is_empty():
			it.subtitle = "Steam: %s · kein Steam-Freund mehr" % str(r.steam_name)
			it.sub_color = "warn"
		it.set_meta("uz_hint_a", "Ändern")
		it.set_meta("uz_hint_x", "Entfernen")
		var rd: Dictionary = r
		it.set_meta("uz_on_x", func() -> void: _remove(rd))
		it.activated.connect(_edit.bind(rd))
		add_row(it)
	add_gap(10)
	add_label("Einmal je Person zuordnen.", "s", "faint")


func _friend(sid: String) -> Dictionary:
	for f in Social.steam_friends:
		if str(f.get("id", "")) == sid:
			return f
	return {}


func _remove(r: Dictionary) -> void:
	CI.forget(str(r.discord_id))
	Toasts.show_toast("Zuordnung entfernt", "%s ↔ %s" % [str(r.discord_name), str(r.steam_name)], "trash", { "ms": 2000, "quiet": true })
	_changed()


func _changed() -> void:
	refill()
	if on_change.is_valid():
		on_change.call()


func _edit(r: Dictionary) -> void:
	var list: Array = Social.steam_friends.duplicate()
	list.sort_custom(func(a, b):
		var ao := str(a.get("state", "offline")) != "offline"
		var bo := str(b.get("state", "offline")) != "offline"
		if ao != bo:
			return ao
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	var s = SheetC.new()
	s.setup(str(r.discord_name), "Steam: " + str(r.steam_name), 720)
	s.fill_func = func(sheet) -> void:
		var rm = ListItem.new()
		rm.setup("Zuordnung entfernen", "Uzai fragt beim nächsten Call wieder")
		rm.icon_name = "trash"
		rm.activated.connect(func() -> void:
			sheet.close()
			_remove(r)
		)
		sheet.add_row(rm)
		sheet.add_gap(8)
		sheet.add_label("Anderer Steam-Freund", "s", "faint")
		for f in list:
			var it = ListItem.new()
			var real := str(f.get("real", ""))
			it.setup(str(f.get("name", "")), real)
			it.avatar = true
			it.image_url = str(f.get("avatar", ""))
			it.status = str(f.get("state", ""))
			if str(f.get("id", "")) == str(r.steam):
				it.set_meta("uz_default", true)
			var fd: Dictionary = f
			it.activated.connect(func() -> void:
				sheet.close()
				CI.remember(str(r.discord_id), str(fd.id), str(r.discord_name), str(fd.get("name", "")))
				_changed()
			)
			sheet.add_row(it)
	main.open_layer(s)
