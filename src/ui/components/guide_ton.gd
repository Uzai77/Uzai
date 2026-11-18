extends RefCounted
## Reiter „Video-Ton“ im Guide (nur solange ein Video als Ton im Hintergrund läuft, gleich nach
## „Spiel“; Video.background). Gesteuert wie Musik:
## - Block: Vorschaubild, Titel, Stand mit Balken; Pause/Weiter · Mit Bild (Player wieder auf, ohne
##   Spiel) · Beenden.
## - Zeilen: −10 s · +10 s · Voriges · Nächstes.
## - Unten die Lautstärke des Videos (LT/RT, dieselbe Stufe wie hoch/runter im Player).
## Endet der Ton (Liste zu Ende, Spielstart), verschwindet der Reiter von selbst.

const U := preload("res://src/ui/u.gd")
const ProgressBarUz := preload("res://src/ui/components/progress_bar.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")

const ID := "ton"


## Reiter des Guides: „Video-Ton“ gleich nach „Spiel“, solange er läuft.
static func tabs(base: Array) -> Array:
	var t := base.duplicate()
	if Video.active and Video.background:
		t.insert(1, [ID, "Video-Ton"])
	return t


## „Nur Ton  ·  Läuft  ·  3:12 von 10:00“
static func status_text() -> String:
	var t := func(s: String) -> String: return TranslationServer.translate(s)
	var bits := PackedStringArray([t.call("Nur Ton")])
	if Video.loading:
		bits.append(t.call("Lädt …"))
	elif Video.is_live():
		bits.append(t.call("Pausiert" if Video.paused else "Live"))
	elif Video.duration > 0.0:
		bits.append(t.call("Angehalten bei %s von %s" if Video.paused else "Läuft  ·  %s von %s") % [YouTube.time_text(Video.pos), YouTube.time_text(Video.duration)])
	return "  ·  ".join(bits)


## Der Ton ist aus (oder läuft wieder mit Bild): Reiter aus der Leiste nehmen, zurück zu „Spiel“.
static func drop_tab(g: Control) -> void:
	if is_instance_valid(g._tabs_row):
		g._fill_tabs()
	if str(g.tab) == ID:
		g._show_tab("spiel", true, -1)


## Inhalt des Reiters in guide._content.
static func fill(g: Control) -> void:
	var c: VBoxContainer = g._content
	var v: Dictionary = Video.video
	var frac := Video.pos / Video.duration if Video.duration > 0.0 and not Video.is_live() else -1.0
	var pills: Array = [[
		"Weiter" if Video.paused else "Pause", "primary", "play" if Video.paused else "pause", "t:play", func() -> void:
			Video.toggle_pause()
			g._rebuild_keep("t:play"), "Weiter" if Video.paused else "Pause"]]
	# Im Spiel kein Bild: das Video läge sonst über dem Spiel, ohne dass Uzai vorn ist.
	if not Launcher.in_game:
		pills.append(["Mit Bild", "flat", "video", "t:show", func() -> void:
			g.close()
			g.main.resume_player(true), "Mit Bild ansehen"])
	pills.append(["Beenden", "danger", "close", "t:stop", func() -> void:
		Video.stop()
		drop_tab(g), "Ton beenden"])
	var head: Control = g._head_row({}, str(v.get("title", "Video")), status_text(), frac, pills, VideoCard.thumb_url(v))
	c.add_child(g._rv(head))
	c.add_child(g._divider(22))
	var list: VBoxContainer = g._list()
	list.set_meta("uz_group", "guide:ton")
	c.add_child(list)
	if not Video.is_live():
		list.add_child(g._quick("−10 s", "rewind", func() -> void: Video.seek(-10.0), "", false, "t:back"))
		list.add_child(g._quick("+10 s", "forward", func() -> void: Video.seek(10.0), "", false, "t:fwd"))
	if Video.has_prev():
		list.add_child(g._quick("Voriges", "prev", func() -> void:
			Video.prev()
			g._rebuild_keep("q:t:prev")
		, "%d von %d" % [Video.index, Video.queue.size()], false, "t:prev"))
	if Video.has_next():
		list.add_child(g._quick("Nächstes", "next", func() -> void:
			Video.next()
			g._rebuild_keep("q:t:next")
		, "%d von %d" % [Video.index + 2, Video.queue.size()], false, "t:next"))
	c.add_child(g._divider(22))
	c.add_child(g._section("Lautstärke", "LT/RT"))
	var vrow := U.hbox(14)
	c.add_child(g._rv(vrow))
	var ic := U.icon("volume", 22, "muted")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vrow.add_child(ic)
	var bar = ProgressBarUz.new().setup(float(Video.volume_level()) / float(Video.VOLUME_MAX), "accent", 2, 0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vrow.add_child(bar)
	var vl := U.label("%d %%" % Video.volume_level(), "17", "text", "ui_bold")
	vl.clip_text = false
	vl.custom_minimum_size.x = 60
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vrow.add_child(vl)
	var t := _Ticker.new()
	t.guide = g
	t.head = head
	t.bar = bar
	t.vol_l = vl
	t.vid = str(v.get("id", ""))
	c.add_child(t)


## Läuft im Reiter: Stand und Balken, Pegel; nächstes Video (Liste läuft weiter) baut neu auf.
class _Ticker extends Node:
	var guide: Control
	var head: Control
	var bar: Control
	var vol_l: Label
	var vid := ""
	var _t := 0.0

	func _ready() -> void:
		Video.volume_changed.connect(_on_volume)

	func _exit_tree() -> void:
		if Video.volume_changed.is_connected(_on_volume):
			Video.volume_changed.disconnect(_on_volume)

	func _on_volume(level: int) -> void:
		if is_instance_valid(bar):
			bar.call("set_value", float(level) / float(Video.VOLUME_MAX))
		if is_instance_valid(vol_l):
			vol_l.text = "%d %%" % level

	func _process(dt: float) -> void:
		_t += dt
		if _t < 0.25 or not is_instance_valid(guide):
			return
		_t = 0.0
		if not (Video.active and Video.background):
			set_process(false)
			preload("res://src/ui/components/guide_ton.gd").drop_tab(guide)
			return
		if str(Video.video.get("id", "")) != vid:
			set_process(false)
			guide._rebuild_keep("t:play")
			return
		# Block oben: die Zeile (Stand) und der Balken unter dem Titel.
		if is_instance_valid(head):
			var sl: Variant = head.get_meta("uz_sub", null)
			if sl is Label and is_instance_valid(sl):
				(sl as Label).text = preload("res://src/ui/components/guide_ton.gd").status_text()
			var hb: Variant = head.get_meta("uz_bar", null)
			if hb is Control and is_instance_valid(hb) and Video.duration > 0.0:
				(hb as Control).call("set_value", Video.pos / Video.duration)
