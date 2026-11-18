extends Control
## Eine Titelliste mit großem Kopf: links Bild, Name, Angaben und „Abspielen“, rechts die Titel,
## die unten weich auslaufen. Für Playlists, Alben, Mixe, Lieblingssongs und „Zuletzt gehört“.
## Gibt Spotify die Titel nicht heraus (Mixe von Spotify, fremde Playlists), steht das ehrlich da –
## abspielen geht trotzdem.
## A spielt ab diesem Titel (die Liste läuft danach weiter), X stellt ihn in die Warteschlange,
## Y macht ihn zum Lieblingssong (oder nimmt ihn heraus).

const TrackRow := preload("res://src/ui/components/track_row.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")
const U := preload("res://src/ui/u.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")

## { kind (playlist|album|mix|spotify_mix|liked|recent), id, name, kicker, sub, desc, art, arts, hue,
##   icon, uri (zum Abspielen als Ganzes), count, tracks?, restricted? }
var info: Dictionary = {}
var loader: Callable            ## liefert die Titel (mit await); sonst info.tracks
var cover := 400.0
var margins := [96, 56, 96, 24]
var group := "tracks"
var _rows: VBoxContainer
var _right: VBoxContainer
var _meta: Label
var _tracks: Array = []
var _glow: Control
var _err := ""                  ## warum es keine Titel gibt (gleich nach dem Laden gemerkt)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var m := U.margin(int(margins[0]), int(margins[1]), int(margins[2]), int(margins[3]))
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(76)
	m.add_child(row)
	# Links: Bild mit Lichtschein und die Angaben
	var left := U.vbox(0)
	left.custom_minimum_size = Vector2(cover, 0)
	row.add_child(left)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(cover, cover)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(holder)
	_glow = _Glow.new()
	_glow.position = Vector2(-cover * 0.3, -cover * 0.3)
	_glow.size = Vector2(cover * 1.6, cover * 1.6)
	_glow.set("color", Color.from_hsv(hue(), 0.55, 0.7))
	holder.add_child(_glow)
	var art = MusicTile.new()
	art.art_only = true
	art.item = info
	art.side = cover
	art.title_text = str(info.get("name", ""))
	art.big_name = str(info.get("kind", "")) in ["mix", "spotify_mix"] and str(info.get("art", "")) == ""
	art.kicker = str(info.get("tile_kicker", ""))
	art.hue = hue()
	art.icon_name = str(info.get("icon", "music"))
	art.art_urls = _art_urls()
	holder.add_child(art)
	left.add_child(U.spacer(0, 28, false))
	var kick := str(info.get("kicker", ""))
	if kick != "":
		var k := U.label(kick, "xs", "accent" if str(info.get("kind", "")) in ["mix", "spotify_mix"] else "muted", "medium")
		k.clip_text = false
		left.add_child(k)
		left.add_child(U.spacer(0, 6, false))
	var name_s := str(info.get("name", ""))
	var nl := U.label(name_s, "xl" if name_s.length() > 22 else "xxl", "text", "black", true)
	nl.max_lines_visible = 3
	nl.add_theme_constant_override("line_spacing", -6)
	left.add_child(nl)
	left.add_child(U.spacer(0, 8, false))
	# Der Künstler auf eigener Zeile, darunter leise Zahl und Länge: In einer Zeile brach der Text
	# in der schmalen Spalte mitten in „1 Min.“ um.
	var wer := _wer_text()
	if wer != "":
		left.add_child(U.ellipsis(U.label(wer, "m", "text", "medium")))
		left.add_child(U.spacer(0, 2, false))
	_meta = U.label(_meta_text(), "m", "muted", "medium", true)
	left.add_child(_meta)
	var desc := str(info.get("desc", ""))
	if desc != "":
		left.add_child(U.spacer(0, 6, false))
		var dl := U.label(desc, "s", "faint", "regular", true)
		dl.max_lines_visible = 3
		left.add_child(dl)
	left.add_child(U.spacer(0, 26, false))
	var btns := U.hbox(12)
	btns.set_meta("uz_group", group + ":knoepfe")
	left.add_child(btns)
	var play := U.button("Abspielen", "play", "primary")
	play.set_meta("uz_hint_a", "Alles abspielen")
	play.set_meta("uz_default", true)
	play.set_meta("uz_entry", true)
	play.set_meta("uz_key", "tp:play")
	play.pressed.connect(func() -> void: _play_all(false))
	btns.add_child(play)
	# Rund und nur mit Symbol: neben dem hellen „Abspielen“ bleibt so klar, was gewählt ist.
	var shuf := U.button("", "shuffle", "icon")
	shuf.custom_minimum_size = Vector2(56, 56)
	shuf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shuf.set_meta("uz_hint_a", "Zufällig abspielen")
	shuf.set_meta("uz_key", "tp:shuffle")
	shuf.pressed.connect(func() -> void: _play_all(true))
	btns.add_child(shuf)
	# Rechts: Titel, unten weich ausgeblendet
	_right = U.vbox(0)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_right)
	var mask := fade_mask(_right)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 150.0)
	U.full_rect(sc)
	mask.add_child(sc)
	var inner := U.vbox(0)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	_rows = U.vbox(2)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.set_meta("uz_group", group)
	_rows.set_meta("uz_mem", true)
	inner.add_child(_rows)
	inner.add_child(U.spacer(0, 140, false))
	_load()


## Senkrechte Maske: Inhalt läuft unten weich aus (statt hart abgeschnitten zu werden).
static func fade_mask(into: Control) -> Control:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.84, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 256
	var mask := TextureRect.new()
	mask.texture = t
	mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mask.stretch_mode = TextureRect.STRETCH_SCALE
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask.mouse_filter = Control.MOUSE_FILTER_PASS
	mask.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	into.add_child(mask)
	return mask


func hue() -> float:
	if info.has("hue"):
		return float(info.hue)
	return float(absi(str(info.get("name", "")).hash()) % 1000) / 1000.0


func _art_urls() -> Array:
	var arts: Variant = info.get("arts")
	if arts is Array and not (arts as Array).is_empty() and str(info.get("art", "")) == "":
		return arts
	var a := str(info.get("art_big", info.get("art", "")))
	return [a] if a != "" else []


## Bei Alben der Künstler; Mixe sagen ihr Motto schon oben und im Bild.
func _wer_text() -> String:
	return "" if str(info.get("kind", "")) in ["mix", "spotify_mix"] else str(info.get("sub", ""))


func _meta_text() -> String:
	var parts := PackedStringArray()
	var n := _tracks.size() if not _tracks.is_empty() else int(info.get("count", 0))
	if n > 0:
		parts.append(U.plural(n, "Titel", "Titel"))
	if not _tracks.is_empty():
		var ms := 0
		for t in _tracks:
			ms += int(t.get("duration", 0))
		var mins := int(ms / 60000.0)
		parts.append(("%d Std. %d Min." % [int(mins / 60.0), mins % 60]) if mins >= 60 else "%d Min." % maxi(1, mins))
	return "  ·  ".join(parts)


func _load() -> void:
	var pre: Variant = info.get("tracks")
	if pre is Array and not (pre as Array).is_empty():
		_show(pre)
		return
	if bool(info.get("restricted", false)) or not loader.is_valid():
		_show([])
		return
	_rows.add_child(Skeleton.track_rows())
	var got: Variant = await loader.call()
	# Sofort merken: list_error teilen sich alle Listen, eine andere könnte ihn gleich überschreiben.
	_err = Music.list_error if str(info.get("kind", "")) in ["playlist", "recent", "spotify_mix"] else ""
	if not is_inside_tree():
		return
	_show(got if got is Array else [])


func _show(list: Array) -> void:
	_tracks = list
	U.clear(_rows)
	if is_instance_valid(_meta):
		_meta.text = _meta_text()
	if list.is_empty():
		_rows.add_child(_notice())
		return
	var ctx := str(info.get("uri", ""))
	var use_ctx := ctx != "" and str(info.get("kind", "")) in ["playlist", "album", "spotify_mix"]
	var album := str(info.get("kind", "")) == "album"
	for i in list.size():
		var t: Dictionary = list[i]
		var r = TrackRow.new().setup(t, i + 1)
		if album:
			# Im Album: kein Bild und kein Albumname je Zeile (wäre überall dasselbe).
			r.show_art = false
			r.show_album = false
		r.set_meta("uz_hint_a", "Abspielen")
		r.set_meta("uz_hint_x", "Als Nächstes")
		r.set_meta("uz_on_x", func() -> void:
			Music.enqueue(str(t.uri))
			Toasts.show_toast("Kommt als Nächstes", str(t.title), "music", { "ms": 1400, "quiet": true })
		)
		# Lieblingssongs gibt es nur bei Spotify (eigene Musikdateien haben kein Herz).
		if not str(t.get("uri", "")).begins_with("lokal:"):
			var liked := Music.is_liked(str(t.id))
			r.set_meta("uz_hint_y", "Kein Lieblingssong mehr" if liked else "Lieblingssong")
			r.set_meta("uz_on_y", func() -> void:
				var was := Music.is_liked(str(t.id))
				Music.toggle_like(str(t.id))
				r.set_meta("uz_hint_y", "Lieblingssong" if was else "Kein Lieblingssong mehr")
				Toasts.show_toast("Aus Lieblingssongs entfernt" if was else "Zu Lieblingssongs", str(t.title), "heart" if was else "heart_f", { "ms": 1400, "quiet": true })
			)
		if i == 0:
			r.set_meta("uz_entry", true)
		var idx := i
		r.chosen.connect(func(_t: Dictionary) -> void:
			if use_ctx and not ctx.contains(":demo"):
				Music.play_in(ctx, str(t.uri))
				return
			var lieblinge: String = await Music.liked_uri() if str(info.get("kind", "")) == "liked" else ""
			if lieblinge != "":
				Music.play_in(lieblinge, str(t.uri))
			else:
				Music.play_list(_tracks, idx)
		)
		_rows.add_child(r)


## Keine Titel: ehrlich sagen warum (gesperrt oder leer).
func _notice() -> Control:
	var kind := str(info.get("kind", ""))
	var restricted := bool(info.get("restricted", false)) or (kind in ["playlist", "spotify_mix"] and _err != "")
	var card := PanelContainer.new()
	var sb := UzTheme.glass(UzTheme.r_panel())
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 30
	sb.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var col := U.vbox(12)
	card.add_child(col)
	var ic := U.icon("lock" if restricted else "music", 34, "muted")
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(ic)
	col.add_child(U.label("Titelliste nicht freigegeben" if restricted else "Hier ist noch nichts", "l", "text", "bold"))
	var text := str(info.get("restricted_text", ""))
	if restricted and text == "":
		text = _err
	if not restricted:
		text = _err if _err != "" else str(info.get("empty_text", ""))
		if text == "":
			text = "Diese Liste ist leer."
	var l := U.label(text, "m", "muted", "regular", true)
	l.custom_minimum_size = Vector2(640, 0)
	col.add_child(l)
	if restricted:
		col.add_child(U.label("„Abspielen“ startet sie trotzdem auf deinem Spotify-Gerät.", "s", "faint", "medium", true))
	var m := U.margin(0, 6, 0, 0)
	m.add_child(card)
	return m


## Ganze Liste abspielen (als Playlist/Album bei Spotify, sonst als lose Titel), auf Wunsch gemischt.
func _play_all(shuffle: bool) -> void:
	var uri := str(info.get("uri", ""))
	var name_s := str(info.get("name", ""))
	var kind := str(info.get("kind", ""))
	var lieblinge: String = await Music.liked_uri() if kind == "liked" else ""
	if uri != "" and kind in ["playlist", "album", "spotify_mix"]:
		if shuffle:
			await Music.set_shuffle(true)
		var ok: bool = await Music.play_context(uri)
		if ok:
			Toasts.show_toast("Läuft: " + name_s, "Zufällig" if shuffle else "", "music", { "ms": 1600, "quiet": true })
		else:
			Toasts.show_toast("Spielt nicht", Music.error, "warning", { "ms": 4200 })
		return
	var list: Array = _tracks.duplicate()
	if list.is_empty() and loader.is_valid():
		var got: Variant = await loader.call()
		list = got if got is Array else []
	if list.is_empty():
		return
	if lieblinge != "":
		# Lieblingssongs als Spotifys eigener Kontext, ab einem bestimmten Titel (gemischt: ein zufälliger) – Spotify
		# mischt dann selbst. Als lose Liste spielte Weg d nur das Album des ersten Titels, bei einer Single mit
		# „Liste wiederholen“ immer denselben (PC, 13.11.). Ab einem Titel, weil die App am PC als Kontext eine eigene
		# Adresse meldet: Uzai sieht so am Titel nach, ob es läuft.
		if shuffle:
			await Music.set_shuffle(true)
		var start: Dictionary = list.pick_random() if shuffle else list[0]
		Music.play_in(lieblinge, str(start.get("uri", "")))
		Toasts.show_toast("Läuft: " + name_s, "Zufällig" if shuffle else "", "music", { "ms": 1600, "quiet": true })
		return
	if shuffle:
		list.shuffle()
	Music.play_list(list, 0)
	Toasts.show_toast("Läuft: " + name_s, "Zufällig" if shuffle else "", "music", { "ms": 1600, "quiet": true })


## Weicher, farbiger Schein hinter dem Bild.
class _Glow extends Control:
	var color := Color(0.4, 0.5, 0.9)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_texture_rect(preload("res://src/ui/components/music_tile.gd").glow_tex(), Rect2(Vector2.ZERO, size), false, Color(color, 0.34))
