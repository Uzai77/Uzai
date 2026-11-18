extends "res://src/ui/layers/modal.gd"
## Eingehender Discord-Anruf, mittig wie auf einer Konsole: großes Bild, „Mia ruft an“, Annehmen
## (A), Ignorieren (B) oder Ablehnen (klingelt für diesen Anruf nicht mehr). Annehmen lässt die Discord-App dem Anruf beitreten – Uzai bleibt vorn,
## der Ton läuft über Discord. Legt der Freund auf, geht die Karte von selbst zu.

const Avatar := preload("res://src/ui/components/avatar.gd")
const RING_SECS := 45.0

var info: Dictionary = {}      ## { user_id, channel_id, name, avatar }
const Main := preload("res://src/main.gd")
var main: Main
var _ring_t := 0.0
var _left := RING_SECS


func build() -> void:
	width = 700.0
	set_meta("uz_hint_b", "Ignorieren")
	super()
	Voice.call_ended.connect(_on_ended)
	Sfx.play("notify")


func _friend() -> Dictionary:
	var f := DiscordChat.friend(str(info.get("user_id", "")))
	return f


func fill() -> void:
	var f := _friend()
	var name_ := str(f.get("name", info.get("name", "")))
	if name_ == "":
		name_ = "Ein Freund"
	var av_url := str(f.get("avatar", info.get("avatar", "")))
	var top := U.vbox(18)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(top)
	var av := Avatar.new()
	av.setup(name_, av_url, "online", 132)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(av)
	var t := U.label("%s ruft an" % name_, "xl", "text", "black")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(t)
	# No text line below the name any more, only the three options.
	top.add_child(U.spacer(0, 8, false))
	var row := U.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(row)
	var yes := U.button("Annehmen", "phone", "primary")
	yes.set_meta("uz_default", true)
	yes.pressed.connect(_accept)
	row.add_child(yes)
	var no := U.button("Ignorieren", "close")
	no.pressed.connect(_ignore)
	row.add_child(no)
	var weg := U.button("Ablehnen", "phone_off", "danger")
	weg.pressed.connect(_decline)
	row.add_child(weg)


func _accept() -> void:
	Voice.accept_call(str(info.get("channel_id", "")))
	var f := _friend()
	Toasts.show_toast("Anruf angenommen", "Mit %s · Auflegen im Guide unter Discord „Verlassen“." % str(f.get("name", info.get("name", "deinem Freund"))), "phone",
			{ "sound": "select", "ms": 3500 })
	close()


func _ignore() -> void:
	Voice.dismiss_call(str(info.get("channel_id", "")))
	close()


## Ablehnen: zu, und Uzai klingelt für diesen Anruf nicht noch einmal (Voice.decline_call).
func _decline() -> void:
	Voice.decline_call(str(info.get("channel_id", "")))
	close()


func _on_ended(cid: String) -> void:
	# Schon angenommen oder ignoriert (die Karte geht gerade zu): kein „Verpasster Anruf“ hinterher.
	if cid == str(info.get("channel_id", "")) and is_inside_tree() and not _closing:
		Toasts.show_toast("Verpasster Anruf", str(_friend().get("name", info.get("name", ""))), "phone", { "ms": 4000 })
		close()


func _process(dt: float) -> void:
	_left -= dt
	_ring_t += dt
	if _ring_t >= 3.0:
		_ring_t = 0.0
		Sfx.play("notify")
	if _left <= 0.0:
		_left = 1e9
		_ignore()
