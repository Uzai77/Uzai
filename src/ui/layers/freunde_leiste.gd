extends "res://src/ui/layers/sheet.gd"
## Freunde als Seitenleiste: Select (View) im Hauptmenü lässt sie von links hereingleiten – ruhig
## wie der Guide (sheet.gd mit links, T_RAUM); rechts liegt „Für dich“ auf Start. Öffnet der Guide
## (auch von links), geht diese Leiste vorher zu (main_guide.gd toggle_guide, Meta uz_links_leiste),
## damit nie zwei Leisten übereinander liegen. Darin der Bereich Freunde (friends_view.gd) in
## schmal: die Liste von Steam und Discord, oben die Dienste (LB/RB wechseln, wie früher die
## Unterbereiche unter dem Reiter). A auf einer Person: Chat, Profil, Beitreten wie bisher
## (friend_actions.gd), X Chat, Y Profil. B oder noch einmal Select schließt.
## Öffnen: main.open_friends(sub) – auch jeder alte Sprung auf „friends“ (main.goto) landet hier.

const FriendsView := preload("res://src/ui/sections/friends_view.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const TabStrip := preload("res://src/ui/components/tab_strip.gd")

const Main := preload("res://src/main.gd")
var main: Main
var start_sub := ""
var view: Control
var _tabs: HBoxContainer
var _tabs_sig := ""


func _init() -> void:
	super()
	setup("Freunde", "", 820.0)
	links = true
	set_meta("uz_links_leiste", true)
	set_meta("uz_hint_b", "Schließen")


func build() -> void:
	super()
	# Statt der Zeilen der Seitenleiste: der Bereich Freunde mit eigenem Bildlauf.
	var frame := scroll.get_parent() as Control
	scroll.visible = false
	_edge.visible = false
	var col := panel.get_child(0) as Control
	_tabs = TabStrip.new()
	_tabs.set("style", "chip")
	_tabs.add_theme_constant_override("separation", 6)
	col.add_child(_tabs)
	col.move_child(_tabs, 1)
	view = FriendsView.new()
	view.main = main
	view.host_layer = self
	var ids: Array = (view.subtabs() as Array).map(func(t: Dictionary) -> String: return str(t.id))
	view.sub = start_sub if ids.has(start_sub) else (str(ids[0]) if not ids.is_empty() else "")
	U.full_rect(view)
	view.visible = true
	frame.add_child(view)
	frame.move_child(_edge_unten, -1)      # der Auslauf liegt über der Liste
	view.build()
	view.on_enter()
	_fill_tabs()
	Social.updated.connect(_on_data)
	DiscordChat.changed.connect(_on_data)


func _on_data(_w: Variant = null) -> void:
	if is_instance_valid(view):
		_fill_tabs()


## Die Dienste oben (Steam, Discord, Server) mit ihrer Zahl; nur, wenn es mehr als einen gibt.
## Nicht wählbar (der Cursor bleibt in der Liste): LB/RB wechseln, Maus klickt.
func _fill_tabs() -> void:
	var subs: Array = view.subtabs()
	var sig := JSON.stringify(subs) + str(view.sub)
	if sig == _tabs_sig:
		return
	_tabs_sig = sig
	U.clear(_tabs)
	_tabs.call("snap")
	_tabs.visible = subs.size() > 1
	if not _tabs.visible:
		return
	_tabs.add_child(_bumper("lb"))
	for t in subs:
		var item = NavItem.new()
		item.setup(str(t.label), "", "chip", str(t.id) == str(view.sub), int(t.get("count", -1)))
		var sid := str(t.id)
		item.ready.connect(func() -> void:
			item.focus_mode = Control.FOCUS_NONE
			item.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_open_sub(sid)
					item.accept_event()))
		_tabs.add_child(item)
	_tabs.add_child(_bumper("rb"))


func _bumper(cmd: String) -> Control:
	var g := U.glyph(cmd, 26)
	g.set("subtle", true)
	return g


func _open_sub(sid: String) -> void:
	if not is_instance_valid(view) or str(view.sub) == sid:
		return
	view.sub = sid
	view.build()
	_fill_tabs()
	Sfx.play("tab")
	await get_tree().process_frame
	var d := Nav.default_in(view)
	if d:
		Nav.focus(d, true)


func nav_command(cmd: String) -> bool:
	# B schließt wie jede Seitenleiste (layer.gd); Select schließt über main._on_command.
	if cmd == "b":
		return super(cmd)
	if cmd in ["lb", "rb"] and is_instance_valid(view):
		var ids: Array = (view.subtabs() as Array).map(func(t: Dictionary) -> String: return str(t.id))
		if ids.size() > 1:
			var i := maxi(0, ids.find(str(view.sub)))
			_open_sub(str(ids[(i + (1 if cmd == "rb" else -1) + ids.size()) % ids.size()]))
		return true
	return super(cmd)


func close() -> void:
	if is_instance_valid(view):
		view.on_leave()
	super()
