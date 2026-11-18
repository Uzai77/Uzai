extends HBoxContainer
## Status oben rechts in der Kopfleiste (main.gd _build): nur, was gerade zählt.
## Immer: Uhr, Suche, Profilbild. Dazu nur echte Zustände – „läuft gerade“ (drei Pegel und der
## Titel), solange Musik oder Video-Ton läuft; Freunde nur, wenn jemand online ist; der Akku eines
## Controllers nur, wenn er schwach ist (alle stehen im Guide); der Akku des PCs auf Handhelds und
## Laptops ohne Netzteil (pc_akku.gd); „Mikro aus“ und „Sicherer Modus“, solange sie gelten.
## Neue Mitteilungen sind ein Punkt im Akzent am Profilbild – keine Glocke, keine Zahl.
## Alles in Tinte; Farbe nur für Zustände (Musik läuft, jemand online, Akku schwach).
## Was ohne Oberfläche entscheidbar ist (pads_schwach, freunde_zeigen), prüft tests/logic_kopf.gd;
## die Leiste im echten Uzai tests/probe_reiter.gd, Bilder tests/probe_leiste.gd.

const U := preload("res://src/ui/u.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const ProfileAvatar := preload("res://src/ui/components/profile_avatar.gd")
const PcAkku := preload("res://src/ui/components/pc_akku.gd")
const PadBattery := preload("res://src/ui/components/pad_battery.gd")
const MicBadge := preload("res://src/ui/components/mic_badge.gd")

## Ab dieser Stufe gilt ein Controller als voll genug, um oben nicht zu stehen (pads.gd level: 0 leer, 1 schwach, 2 mittel, 3 voll).
const PAD_OK := 2
## Durchmesser des Profilbilds und der Lupe.
const KNOPF := 44

var music_box: HBoxContainer
var music_label: Label
var friends_box: HBoxContainer
var friends_label: Label
var pad_box: HBoxContainer
var clock_label: Label
var search: Control            ## Lupe (SuchKnopf), signal activated
var avatar: AvatarKnopf            ## Profilbild (AvatarKnopf), signal activated, set_selected, set_punkt
var gap: Control               ## der freie Platz links vom Status (für die Breite des Songtitels)
var narrow := false
var _schwach: Array = []
var _punkt_an := false


func setup(narrow_top: bool, top_gap: Control) -> Control:
	narrow = narrow_top
	gap = top_gap
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 16 if narrow else 22)
	music_box = U.hbox(10)
	music_box.add_child(Pegel.new())
	music_label = U.ellipsis(U.label("", "s", "muted", "medium"))
	music_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Titel und Interpret: nie übersetzen
	music_label.custom_minimum_size = Vector2(0, 0)
	music_box.add_child(music_label)
	music_box.visible = false
	add_child(music_box)
	friends_box = U.hbox(8)
	friends_box.add_child(Praesenz.new())
	friends_label = U.label("", "s", "muted", "medium")
	friends_label.clip_text = false
	friends_box.add_child(friends_label)
	friends_box.visible = false
	add_child(friends_box)
	if Config.safe_mode:
		# Immer sichtbar, solange er gilt; zurück unter Einstellungen → System oder per Neustart.
		var safe := U.hbox(6)
		safe.add_child(U.icon("warning", 20, "warn"))
		safe.add_child(U.label("Sicherer Modus", "s", "warn", "bold"))
		add_child(safe)
	# Mikro aus (Mixer.toggle_mic oder in Windows): bleibt sichtbar, solange es aus ist.
	add_child(MicBadge.new())
	pad_box = U.hbox(6)
	pad_box.visible = false
	add_child(pad_box)
	# Akku des PCs (Handhelds immer, Laptops ohne Netzteil) – auch bei großer Oberfläche.
	add_child(PcAkku.new())
	clock_label = U.label("", "m", "text", "medium")
	clock_label.clip_text = false
	add_child(clock_label)
	# Lupe: die Suche über alles (wie R3), wählbar wie das Profilbild daneben.
	search = SuchKnopf.new()
	add_child(search)
	avatar = AvatarKnopf.new()
	add_child(avatar)
	tick()


## Jede Sekunde (main._tick): Uhr und der Punkt für neue Mitteilungen.
func tick() -> void:
	clock_label.text = U.clock()
	var an := Toasts.unread > 0
	if an != _punkt_an:
		_punkt_an = an
		avatar.set_punkt(an)


## Nur Controller, deren Akku schwach oder leer ist und die nicht gerade laden – die stehen oben;
## volle, unbekannte und Kabel stehen nur im Guide.
static func pads_schwach(pads: Array) -> Array:
	return pads.filter(func(p: Dictionary) -> bool:
		var lvl := int(p.get("level", -1))
		return lvl >= 0 and lvl < PAD_OK and not bool(p.get("charging", false)) and str(p.get("power", "")) != "wired")


## Freunde stehen oben, wenn ein Dienst angemeldet ist und jemand online ist – sonst nicht.
static func freunde_zeigen(online: int, angemeldet: bool) -> bool:
	return angemeldet and online > 0


## Akkustand der Controller (Pads.pads): oben nur die schwachen.
func set_pads(pads: Array) -> void:
	_schwach = pads_schwach(pads)
	PadBattery.fill(pad_box, _schwach)
	pad_box.visible = not _schwach.is_empty() and not narrow


func hat_schwache() -> bool:
	return not _schwach.is_empty()


## Profilbild, Freunde und „läuft gerade“ neu lesen (main._update_status). av_sig: Kennung des
## Uzai-Profils (mehrere Profile zeigen das Profilbild, sonst das Bild aus Steam); now: was läuft
## ({ title, artist, playing } wie Music.now); music_on: ob oben Platz für den Titel ist.
func refresh(av_sig: String, now: Dictionary, music_on: bool) -> void:
	var many := Config.profile_list().size() > 1
	var av_key := ("profil:" + av_sig) if many else str(Social.me.get("avatar", ""))
	if avatar.get_meta("url", "") != av_key or avatar.bild() == null:
		if many:
			avatar.set_bild(ProfileAvatar.new().setup(Config.profile(), KNOPF))
		else:
			var av = Avatar.new()
			var pname := str(Config.get_value("system.player_name", "Spieler 1"))
			if pname == "Spieler 1" and str(Social.me.get("name", "")) != "":
				pname = str(Social.me.name)
			av.setup(pname, str(Social.me.get("avatar", "")), "online" if Social.has_steam() else "", KNOPF)
			avatar.set_bild(av)
		avatar.set_meta("url", av_key)
	var n: int = online_friends()
	friends_box.visible = freunde_zeigen(n, Social.has_steam() or DiscordChat.logged_in())
	friends_label.text = str(n)
	music_box.visible = music_on
	if music_box.get_child_count() > 0:
		(music_box.get_child(0) as CanvasItem).queue_redraw()
	if now.is_empty():
		return
	# So breit, wie oben Platz ist. Reicht es nicht für Titel und Interpret, steht nur der Titel da.
	var f := UzTheme.font("medium")
	var room := 240.0
	if music_box.visible and is_instance_valid(gap) and gap.size.x > 0.0 and music_label.custom_minimum_size.x > 0.0:
		room = clampf(music_label.custom_minimum_size.x + gap.size.x - 40.0, 160.0, 420.0)
	var title := str(now.get("title", ""))
	var txt := "%s · %s" % [title, now.get("artist", "")]
	if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 4.0 > room and title != "":
		txt = title
	music_label.text = txt
	music_label.custom_minimum_size.x = minf(room, f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 4.0)


## Freunde online (Steam und Discord, getrennt wie in den Listen) – die Zahl oben und im Guide.
## Leute in Discord-Servern ohne Freundschaft und der eigene Sprachkanal zählen nicht mit.
static func online_friends() -> int:
	var n := Social.steam_friends.filter(func(f): return str(f.get("state", "offline")) != "offline").size()
	if DiscordChat.logged_in():
		n += DiscordChat.friends.filter(func(f): return str(f.get("state", "offline")) != "offline").size()
	return n


## Drei schmale Pegel, die sich ruhig bewegen, solange Musik läuft (grün); pausiert stehen sie
## still und leise. Video-Ton im Hintergrund zählt wie Musik (main.now_playing).
class Pegel extends Control:
	var _t := 0.0
	var _acc := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(20, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		if not is_visible_in_tree() or not playing():
			return
		_t += dt
		_acc += dt
		if _acc >= 1.0 / 24.0:
			_acc = 0.0
			queue_redraw()

	static func playing() -> bool:
		if Video.active and Video.background:
			return not Video.paused
		return bool(Music.now.get("playing", false))

	func _draw() -> void:
		var on := playing()
		var col := UzTheme.col("music") if on else UzTheme.col("muted")
		var w := 3.0
		var gap_ := 3.5
		var base := size.y * 0.86
		var x0 := (size.x - (3.0 * w + 2.0 * gap_)) * 0.5
		for i in 3:
			var amp := 0.32 + 0.12 * float(i % 2)
			if on:
				amp = 0.3 + 0.7 * absf(sin(_t * (1.9 + 0.55 * i) + i * 1.7)) * (0.75 + 0.25 * sin(_t * 0.8 + i * 2.1))
			var bh := maxf(3.0, size.y * 0.72 * amp)
			draw_style_box(UzTheme.box(col, 1), Rect2(x0 + i * (w + gap_), base - bh, w, bh))


## Freunde-Symbol in Tinte mit grünem Punkt: es ist jemand online.
class Praesenz extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(26, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var tex := Icons.tex("friends", 22)
		if tex:
			draw_texture_rect(tex, Rect2(0, 0, 22, 22), false, UzTheme.col("muted"))
		var c := Vector2(22.0, 18.0)
		draw_circle(c, 5.0, UzTheme.col("bg"))
		draw_circle(c, 3.4, UzTheme.col("ok"))


## Runder Knopf oben rechts (Lupe, Profilbild): A oder Klick löst activated aus; der Cursor ist die
## Pille der Marke rundherum.
class RundKnopf extends Control:
	signal activated

	func _ready() -> void:
		custom_minimum_size = Vector2(KNOPF, KNOPF)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_entered.connect(func() -> void: U.focus_anim(self, true))
		focus_exited.connect(func() -> void: U.focus_anim(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				activated.emit()
				accept_event()
		)

	func activate() -> void:
		activated.emit()


## Die Lupe: A (oder Klick) öffnet die Suche über alles.
class SuchKnopf extends RundKnopf:
	func _ready() -> void:
		super()
		focus_mode = Control.FOCUS_ALL
		set_meta("uz_key", "me:search")
		set_meta("uz_hint_a", "Suchen")

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		U.draw_focus(self, 999, r.grow(2))
		var f: float = get_meta("uz_f", 0.0)
		var px := 26
		draw_texture_rect(Icons.tex("search", px), Rect2((size - Vector2(px, px)) * 0.5, Vector2(px, px)), false,
			UzTheme.col("muted").lerp(UzTheme.col("on_focus"), f))


## Das Profilbild: führt immer zum Profil; wählbar nur, wenn kein Reiter „Profil“ da ist (main.gd).
## Steht man im Profil, trägt es den Ring im Akzent. Neue Mitteilungen: ein Punkt im Akzent oben
## rechts am Bild, der im Antwort-Takt aufgeht (set_punkt).
class AvatarKnopf extends RundKnopf:
	var selected := false
	var _bild: Control
	var _punkt: Punkt

	func _ready() -> void:
		super()
		focus_mode = Control.FOCUS_NONE
		set_meta("uz_key", "me:avatar")
		set_meta("uz_hint_a", "Profil")
		_punkt = Punkt.new()
		_punkt.position = Vector2(KNOPF - Punkt.D - 1.0, 1.0)
		add_child(_punkt)

	func bild() -> Control:
		return _bild if is_instance_valid(_bild) else null

	## Das runde Bild (avatar.gd bzw. profile_avatar.gd) einsetzen; der Punkt bleibt obenauf.
	func set_bild(c: Control) -> void:
		if is_instance_valid(_bild):
			_bild.queue_free()
		_bild = c
		add_child(c)
		move_child(_punkt, get_child_count() - 1)

	func set_punkt(on: bool) -> void:
		_punkt.zeigen(on)

	func set_selected(on: bool) -> void:
		selected = on
		set_meta("uz_selected", on)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if selected:
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.set_border_width_all(3)
			ring.border_color = UzTheme.col("accent")
			ring.set_corner_radius_all(999)
			for s in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				ring.set_expand_margin(s, 5)
			ring.anti_aliasing = true
			draw_style_box(ring, r)
		U.draw_focus(self, 999, r.grow(6))


## Der Punkt am Profilbild: Akzent auf einem Ring in Raumfarbe, damit er sich vom Bild löst.
## Geht in T_ANTWORT auf (wächst aus der Mitte) und ebenso wieder zu; ruhig ohne Wachsen.
class Punkt extends Control:
	const D := 12.0
	var k := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(D, D)
		size = custom_minimum_size
		visible = false

	func zeigen(on: bool) -> void:
		var to := 1.0 if on else 0.0
		if not is_inside_tree():
			k = to
			visible = on
			queue_redraw()
			return
		visible = true
		var tw := U.ankommen(self, U.T_ANTWORT, "uz_punkt")
		tw.tween_method(func(v: float) -> void:
			k = v
			queue_redraw()
		, k, to, U.T_ANTWORT)
		if not on:
			tw.tween_callback(func() -> void: visible = k > 0.01)

	func _draw() -> void:
		if k <= 0.01:
			return
		var c := size * 0.5
		var s := lerpf(U.wachsen(0.6), 1.0, k)
		draw_circle(c, D * 0.5 * s, Color(UzTheme.col("bg"), k))
		draw_circle(c, (D * 0.5 - 2.0) * s, Color(UzTheme.col("accent"), k))
