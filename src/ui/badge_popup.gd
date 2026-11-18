extends CanvasLayer
## Pop-up für neue Abzeichen und ein neues Level – dieselbe gläserne Pille wie die
## Erfolgs-Pop-ups (achievement_toast.gd, gleicher Platz unten bzw. oben in der Mitte): der Kreis
## springt auf, der Lichtring läuft aus, die Pille öffnet sich. Im Kreis steht statt des Pokals
## die Medaille des Abzeichens bzw. der Level-Ring mit der neuen Zahl; rechts die Punkte der Stufe.
## Silber/Gold mit goldenem Glas, Platin wie ultraseltene Erfolge. Läuft gerade ein
## Erfolgs-Pop-up, wartet das Abzeichen dahinter – nie zwei übereinander.
##
## Arten (push): { kind: "badge", id, tier } · { kind: "level", level } ·
## { kind: "summary", count, level, first, best: { id, tier } }
## Klang: Abzeichen wie Erfolge („unlock“, ab Gold „unlock_rare“), Level und Zusammenfassung
## eine kurze Fanfare (hier aus Sinus erzeugt, keine Datei).

const L := preload("res://src/core/badges_logic.gd")
const Toast := preload("res://src/ui/components/achievement_toast.gd")
const Medal := preload("res://src/ui/components/badge_medal.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

const MARGIN_BOTTOM := 92.0      ## wie achievement_popups.gd
const MARGIN_TOP := 36.0
const HOLD := 4.2
const RATE := 44100

var shown := 0                   ## gezeigte Pop-ups (Tests)
var current: Control
var _queue: Array = []
var _root: Control
var _player: AudioStreamPlayer
var _wartet := false             ## _next wartet schon auf die Erfolgs-Pop-ups
static var _fanfare: AudioStreamWAV
static var _fanfare_laeuft := false


func _ready() -> void:
	layer = 102
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)
	_player = AudioStreamPlayer.new()
	_player.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	add_child(_player)


func push(item: Dictionary) -> void:
	_queue.append(item)
	if not is_instance_valid(current):
		_next()


func busy() -> bool:
	return is_instance_valid(current) or not _queue.is_empty()


func _next() -> void:
	if _queue.is_empty() or _wartet:
		return
	# Erfolgs-Pop-ups zuerst: erst wenn deren Reihe leer ist. Nur einer wartet – kamen während eines
	# Erfolgs zwei Einträge (Abzeichen und neues Level), warteten sonst zwei und zeigten ihre Pop-ups
	# übereinander.
	_wartet = true
	var up := get_node_or_null("/root/Unlocks")
	var ach: Variant = up.get("popups") if up else null
	while ach is Object and is_instance_valid(ach) and ((ach as Object).call("busy") or int((ach as Object).call("waiting")) > 0):
		await get_tree().create_timer(0.3).timeout
	_wartet = false
	if is_instance_valid(current) or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	var toast := BadgeToast.new()
	toast.item = item
	toast.setup(entry_of(item), deco_of(item), HOLD if _queue.is_empty() else 2.6)
	_root.add_child(toast)
	_place(toast)
	current = toast
	shown += 1
	toast.finished.connect(func() -> void:
		toast.queue_free()
		if current == toast:
			current = null
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(current):
			_next()
	)
	_sound(item)
	var pads := get_node_or_null("/root/Pads")
	if pads != null and pads.has_method("pulse"):
		pads.call("pulse", "achievement")
	toast.play()


func _place(toast: Control) -> void:
	var vs := _root.get_viewport_rect().size
	var top := str(Config.get_value("notify.unlock_pos", "unten")) == "oben"
	var pill_off := Toast.AREA.y * 0.5 - Toast.R
	toast.position.x = roundf((vs.x - Toast.AREA.x) * 0.5)
	toast.position.y = MARGIN_TOP - pill_off if top else vs.y - MARGIN_BOTTOM - (pill_off + Toast.H)


# --- Inhalt (rein) -----------------------------------------------------------------------------

## Uzais eigene Texte gleich in der Sprache der Oberfläche: Die Pille zeichnet die zweite Zeile, wie sie kommt (bei
## Steam ist das der Name des Erfolgs, fremder Text) – Abzeichen und Level blieben auf Englisch sonst deutsch.
static func _t(s: String) -> String:
	return str(TranslationServer.translate(s))


## Was in der Pille steht, im Format der Erfolgs-Pop-ups: { name, points, icon }.
static func entry_of(item: Dictionary) -> Dictionary:
	match str(item.get("kind", "")):
		"badge":
			var d := L.def_of(str(item.get("id", "")))
			var t := int(item.get("tier", 1))
			return { "name": _t(L.tier_title(d, t)), "points": 0 if bool(d.get("no_points", false)) else int(L.TIER_POINTS[clampi(t, 0, 4)]), "icon": "" }
		"level":
			return { "name": _t("Level %d erreicht" % int(item.get("level", 1))), "points": 0, "icon": "" }
		"summary":
			return { "name": _t(summary_text(item)), "points": 0, "icon": "" }
	return { "name": "", "points": 0, "icon": "" }


## Zeile 1, Farbe (wie Unlocks.decorate) und Chip.
static func deco_of(item: Dictionary) -> Dictionary:
	match str(item.get("kind", "")):
		"badge":
			var d := L.def_of(str(item.get("id", "")))
			var t := int(item.get("tier", 1))
			var v := "ultra" if t >= 4 else ("rare" if t >= 2 else "normal")
			# Die Teile einzeln: Am Stück träfe „Abzeichen freigeschaltet“ den Eintrag für die Mehrzahl.
			return { "variant": v, "rare": t >= 3, "line1": _t("Abzeichen freigeschaltet · ") + _t(str(d.get("name", ""))),
				"chip": str(L.TIER_NAMES[clampi(t, 0, 4)]) }
		"level":
			return { "variant": "rare", "rare": true, "line1": _t("Neues Uzai-Level · ") + _t(L.level_left_text(Badges.total_points())), "chip": "" }
		"summary":
			return { "variant": "rare", "rare": true, "line1": _t("Abzeichen · Level %d" % int(item.get("level", 1))), "chip": "" }
	return { "variant": "normal", "line1": "", "chip": "" }


static func summary_text(item: Dictionary) -> String:
	var n := int(item.get("count", 0))
	if bool(item.get("first", false)):
		return "Du hast %d Abzeichen freigeschaltet" % n
	return "1 neues Abzeichen" if n == 1 else "%d neue Abzeichen" % n


func _sound(item: Dictionary) -> void:
	if not Config.get_value("notify.unlock_sound", true) or not Config.get_value("theme.sounds", true):
		return
	var kind := str(item.get("kind", ""))
	if kind == "level" or kind == "summary":
		_fanfare_spielen()
	else:
		Sfx.play("unlock_rare" if int(item.get("tier", 1)) >= 3 else "unlock")


## Die Fanfare entsteht beim ersten Mal im Hintergrund und setzt dann ein (gemessen 170 ms – im Hauptfaden
## stand das Bild genau in dem Moment, in dem das Pop-up aufspringt). Danach liegt sie bereit.
func _fanfare_spielen() -> void:
	if _fanfare == null:
		if _fanfare_laeuft:
			return
		_fanfare_laeuft = true
		var f: Variant = await Arbeit.ergebnis(make_fanfare)
		_fanfare_laeuft = false
		_fanfare = f as AudioStreamWAV
		if _fanfare == null:
			return
	_player.stream = _fanfare
	_player.volume_db = linear_to_db(clampf(float(Config.get_value("theme.sound_volume", 0.6)), 0.0, 1.0) * 0.75 + 0.0001)
	_player.play()


# --- Fanfare -----------------------------------------------------------------------------------

## Kurze Fanfare: aufsteigender Dreiklang (C–E–G–C) mit Glockenobertönen, darüber ein warmer
## Schlussakkord, der ausklingt, und ein leises Funkeln. Etwa 1,65 s, aus Sinus erzeugt.
static func make_fanfare() -> AudioStreamWAV:
	var length := 1.65
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var notes := [[0.0, 523.25], [0.085, 659.25], [0.17, 783.99], [0.27, 1046.5]]
	var chord := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for nt in notes:
			var st: float = nt[0]
			if t < st:
				continue
			var u := t - st
			var f: float = nt[1]
			var env := minf(u / 0.006, 1.0) * exp(-u * 6.5)
			v += (sin(TAU * f * u) * 0.16 + sin(TAU * f * 2.0 * u) * 0.05 * exp(-u * 9.0) + sin(TAU * f * 3.01 * u) * 0.02 * exp(-u * 14.0)) * env
		if t > 0.36:
			var w := t - 0.36
			var env2 := minf(w / 0.05, 1.0) * exp(-w * 2.4)
			for f2 in chord:
				v += (sin(TAU * float(f2) * w) * 0.035 + sin(TAU * float(f2) * 1.004 * w) * 0.02) * env2
			v += sin(TAU * 2093.0 * w) * 0.018 * exp(-w * 5.0) * (0.5 + 0.5 * sin(TAU * 7.0 * w))
		var tail := float(n - i) / RATE
		if tail < 0.03:
			v *= tail / 0.03
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Die Pille der Erfolge mit Medaille bzw. Level-Ring im Kreis. Ohne Punkte (Level,
## Zusammenfassung) bleibt rechts nichts stehen.
class BadgeToast extends "res://src/ui/components/achievement_toast.gd":
	var item: Dictionary = {}
	var _medals: Array = []      ## [[Textur, Versatz, Größe 0…1, Deckkraft, Abzeichen, Stufe]]

	func setup(e: Dictionary, d: Dictionary, hold_sec := 3.4) -> Control:
		super(e, d, hold_sec)
		# Kein Pokal: die Medaille steht von Anfang an im Kreis.
		_pal = _pal.duplicate()
		_pal["glyph"] = Color(0, 0, 0, 0)
		var px := int(ceil(R * 2.4 * 2.0))
		match str(item.get("kind", "")):
			"badge":
				_medals = [[Medal.texture_for(L.def_of(str(item.id)), int(item.tier), px), Vector2.ZERO, 1.0, 1.0, L.def_of(str(item.id)), int(item.tier)]]
			"summary":
				var ids: Array = []
				var best: Dictionary = item.get("best", {})
				if not best.is_empty():
					ids.append([str(best.id), int(best.tier)])
				for x in Badges.showcase(4):
					if ids.size() >= 3:
						break
					if int(x.tier) > 0 and (best.is_empty() or str(x.id) != str(best.get("id", ""))):
						ids.append([str(x.id), int(x.tier)])
				for i in range(ids.size() - 1, -1, -1):
					var off := Vector2(0, 0) if i == 0 else Vector2(-14.0 if i == 1 else 14.0, -6.0)
					_medals.append(
							[Medal.texture_for(L.def_of(str(ids[i][0])), int(ids[i][1]), px), off, 1.0 if i == 0 else 0.7, 1.0 if i == 0 else 0.55, L.def_of(str(ids[i][0])),
							int(ids[i][1])])
		return self

	func _apply() -> void:
		if int(entry.get("points", 0)) <= 0 and _f.has("pa"):
			_f["pa"] = 0.0
		super()

	func _draw_ink() -> void:
		super()
		var g := geometry()
		var a: float = _f.get("a", 0.0)
		var s: float = g.s
		if a <= 0.001 or s <= 0.001:
			return
		var bc: Vector2 = g.bc
		var dr: float = g.dr
		if str(item.get("kind", "")) == "level":
			_draw_level(bc, dr, s, a)
			return
		for m in _medals:
			var sz: float = dr * 2.3 * float(m[2])
			var c: Vector2 = bc + (m[1] as Vector2) * s
			var rect := Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
			_ink.draw_texture_rect(m[0], rect, false, Color(1, 1, 1, a * float(m[3])))
			Medal.draw_mark(_ink, rect, m[4], int(m[5]), a * float(m[3]), m[0])

	func _draw_level(bc: Vector2, dr: float, s: float, a: float) -> void:
		var info: Dictionary = Badges.level
		var gold := Color("#3b2a10")
		var r := dr - 6.0 * s
		_ink.draw_arc(bc, r, 0.0, TAU, 64, Color(gold, 0.25 * a), 4.0 * s, true)
		var fk: float = clampf(float(info.get("frac", 0.0)), 0.0, 1.0) * float(_f.get("pk", 1.0))
		if fk > 0.01:
			_ink.draw_arc(bc, r, -PI * 0.5, -PI * 0.5 + TAU * fk, 64, Color(gold, 0.9 * a), 4.0 * s, true)
		var txt := str(int(item.get("level", 1)))
		var f := UzTheme.display("black")
		var fs := int(round((30.0 if txt.length() <= 2 else 24.0) * s))
		if fs < 4:
			return
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_ink.draw_string(f, Vector2(bc.x - w * 0.5, bc.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(gold, a))
