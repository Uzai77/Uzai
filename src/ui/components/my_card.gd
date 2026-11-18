extends Control
## Dein Profil oben rechts im Guide-Reiter Freunde – wie bei Steam und Discord, wo man selbst
## über der Freundesliste steht: Profilbild mit Status, Name, darunter Steam und Discord mit je
## einem Statuspunkt (oder was gerade läuft). A öffnet das Panel „Dein Status“ (my_profile.gd).

signal chosen

const U := preload("res://src/ui/u.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const MyStatus := preload("res://src/core/my_status.gd")

const H := 64
var hold := false:
	set(v):
		hold = v
		if not v and is_inside_tree() and not has_focus():
			U.etikett(self, false)
			queue_redraw()
var _av
var _m: MarginContainer
var _name: Label
var _line: HBoxContainer


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta("uz_key", "me:card")
	set_meta("uz_hint_a", "Status ändern")
	custom_minimum_size = Vector2(0, H)
	_m = U.margin(10, 6, 20, 6)
	U.full_rect(_m)
	add_child(_m)
	var row := U.hbox(14)
	_m.add_child(row)
	var p := MyStatus.profile()
	_av = Avatar.new()
	_av.setup(str(p.name), str(p.avatar), "", 48)
	_av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_av)
	var col := U.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_name = U.label(str(p.name), "20", "text", "ui_bold")
	_name.clip_text = false
	# Neben dem Namen das Uzai-Level (Abzeichen, profile_badges.gd).
	var name_row := U.hbox(10)
	name_row.add_child(_name)
	name_row.add_child(load("res://src/ui/sections/profile_badges.gd").pill("xs"))
	col.add_child(name_row)
	_line = U.hbox(8)
	col.add_child(_line)
	refresh()
	Social.updated.connect(_on_data)
	DiscordChat.changed.connect(refresh)
	SteamCM.own_changed.connect(refresh)
	focus_entered.connect(func() -> void:
		U.etikett(self, true)
		queue_redraw()
	)
	focus_exited.connect(func() -> void:
		if not hold:
			U.etikett(self, false)
		queue_redraw()
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Status neu zeigen (nach einer Änderung im Panel oder neuen Daten).
func refresh() -> void:
	if not is_instance_valid(_line):
		return
	var st := MyStatus.steam_now()
	var dc := MyStatus.discord_now()
	var hs := MyStatus.has_steam()
	var hd := MyStatus.has_discord()
	_av.status = MyStatus.overall(st if hs else "", dc if hd else "", Launcher.in_game)
	_av.queue_redraw()
	U.clear(_line)
	var playing := MyStatus.playing()
	if playing != "":
		var gi := U.icon("games", 16, "ok")
		gi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_line.add_child(gi)
		_line.add_child(_lab(playing))
		_fit()
		return
	if hs:
		_service("steam", st)
	if hd:
		if hs:
			_line.add_child(U.spacer(4, 0, false))
		_service("discord", dc)
	if not hs and not hd:
		_line.add_child(_lab("Status ändern"))
	# Fokus liegt gerade hier: neue Beschriftungen gleich in der Fokusfarbe.
	if has_focus() or hold:
		U.etikett(self, true, false)
	_fit()


## Breite aus dem Inhalt (ein Control rechnet sie nicht selbst aus seinen Kindern).
func _fit() -> void:
	custom_minimum_size = Vector2(ceilf(_m.get_combined_minimum_size().x), H)


func _on_data(_what: String) -> void:
	refresh()


func _service(icon: String, id: String) -> void:
	var ic := U.icon(icon, 16, "muted")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line.add_child(ic)
	var d := StatusDot.new()
	d.id = id
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line.add_child(d)
	_line.add_child(_lab(MyStatus.name_of(id) if id != "" else "–"))


func _lab(t: String) -> Label:
	var l := U.label(t, "xs", "muted", "medium")
	l.clip_text = false
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func activate() -> void:
	chosen.emit()


func _draw() -> void:
	U.draw_focus(self, UzTheme.radius + 2)


## Kleiner Statuspunkt: gefüllt in der Farbe des Status, „Unsichtbar“ als Ring (wie bei Discord).
class StatusDot extends Control:
	var id := ""
	var px := 10.0

	func _ready() -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(px, px) * 0.5
		var r := px * 0.5
		var key := str(Avatar.STATUS_COLORS.get(MyStatus.dot(id), "faint"))
		if id == "invisible":
			draw_arc(c, r - 1.25, 0.0, TAU, 32, UzTheme.col("muted"), 2.5, true)
		elif id == "":
			draw_arc(c, r - 1.0, 0.0, TAU, 32, UzTheme.col("faint"), 1.5, true)
		else:
			draw_circle(c, r, UzTheme.col(key))
