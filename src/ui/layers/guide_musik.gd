extends "res://src/ui/layers/guide_discord.gd"
## Guide, Schicht über guide_discord.gd: der Reiter Musik – was läuft, Steuerung, als Nächstes,
## Songtext, Gerät, Song schicken und Zusammen hören; dazu der kleine Player im Reiter Start.

const Sheet := preload("res://src/ui/layers/sheet.gd")
const MusicS := preload("res://src/core/music.gd")
const MediaS := preload("res://src/core/media.gd")
const LyricsS := preload("res://src/core/lyrics.gd")
const MusicBits := preload("res://src/ui/components/music_bits.gd")
const MusicShare := preload("res://src/ui/layers/music_share.gd")
const LocalUi := preload("res://src/ui/local_music_ui.gd")
const Verlauf := preload("res://src/core/spotify_verlauf.gd")
const JetztLaeuft := preload("res://src/ui/layers/jetzt_laeuft.gd")

var _eq: Control
var _clock: Label
var _mini_title: Label
var _mini_artist: Label
var _mini_art: TextureRect
var _mini_box: Control
var _mini_bar = null
var _mini_time: Label
var _mini_total: Label
var _mini_play: Button
var _music_title: Label
var _music_artist: Label
var _music_bar = null
var _music_time: Label
var _music_art: TextureRect
var _music_album: Label
var _music_device: Label
var _music_total: Label
var _music_glow: TextureRect
var _music_next: Control       ## Abschnitt „Als Nächstes“ (bis zu drei Titel)
var _next_sig := ""
var _lyrics_btn: Control
var _shuffle_btn: Button
var _like_btn: Button
var _play_btn = null
var _art_url := ""
var _music_cover: Control    ## die Fläche des Covers im Reiter Musik (wächst, sobald es ein Bild gibt)
var _art_track := ""         ## Titel|Interpret, zu dem das gezeigte Cover gehört


# --- Musik ---------------------------------------------------------------------------------

## Reiter Musik: oben Cover (mit Schein in seiner Farbe) und was läuft, darunter Fortschritt und
## Steuerung, dann bis zu drei Titel „Als Nächstes“ (A spielt gleich diesen) und die Wege als
## Zeilen (Suchen, Playlists, Gerät, Song schicken, Songtext bzw. Alben); unten die laufende Zeile
## des Songtexts. X nächster Titel, Y suchen. Ohne Cover bleibt das Feld klein. A auf dem Cover
## öffnet „Jetzt läuft“ groß (Cover, Liedtext, Steuerung; jetzt_laeuft.gd).
func _tab_music() -> void:
	var row := U.hbox(22)
	_content.add_child(row)
	_musik_cover(row)
	_musik_angaben(row)
	_content.add_child(U.spacer(0, 18, false))
	if Music.mode() == "aus":
		# Ein Druck schaltet ein (Musik-Apps über Windows, ohne Konto); der Reiter zeigt dann, was läuft.
		# Spotify nicht im Spiel: die Anmeldung käme hinter dem Spiel heraus.
		var b := _act("Einschalten", "music", func() -> void:
			Config.set_value("system.music_mode", "tasten")
			_show_tab("musik", true))
		b.set_meta("uz_default", true)
		_content.add_child(_rv(b))
		if not Launcher.in_game and not Video.active:
			_content.add_child(_rv(_act("Mit Spotify anmelden", "link", func() -> void:
				close()
				LeerBuehneG.spotify(main))))
		_refresh_music()
		return
	if _ohne_ordner():
		# Eigene Musik ohne Ordner: statt einer Steuerung, die nichts spielen kann, der Weg zum Ordner.
		# Nicht im Spiel: die Ordnerwahl käme hinter dem Spiel heraus.
		if not Launcher.in_game and not Video.active:
			var w := _act("Musikordner wählen", "folder", func() -> void:
				close()
				LocalUi.pick_folder(main))
			w.set_meta("uz_default", true)
			_content.add_child(_rv(w))
		_refresh_music()
		return
	var spotify := Music.has_spotify() and Music.mode() != "aus" and not Music.local_on()
	var local := Music.local_on()
	_musik_fortschritt()
	_content.add_child(U.spacer(0, 10, false))
	_musik_steuerung(spotify, local)
	if spotify or local:
		_music_next = _next_rows()
		_content.add_child(_music_next)
	_content.add_child(_divider(16))
	_musik_wege(spotify, local)
	# Songtext (LRCLIB), wenn es einen gibt: unten die laufende Zeile und die nächste. Ohne
	# zeitgenaue Zeilen bleibt nur „Songtext“ (ganzer Text als Liste), ohne Songtext gar nichts.
	if not Music.now.is_empty():
		_content.add_child(U.spacer())
		var strip := _LyricStrip.new()
		strip.found.connect(func(any: bool, _synced: bool) -> void:
			if is_instance_valid(_lyrics_btn):
				_lyrics_btn.visible = any
		)
		_content.add_child(strip)
	_refresh_music()


## Links: das Cover mit Schein in seiner Farbe; A öffnet „Jetzt läuft“ groß.
func _musik_cover(row: Control) -> void:
	var cs := 168.0 if str(Music.now.get("art", "")) != "" else 112.0
	var left := _CoverLink.new()
	left.custom_minimum_size = Vector2(cs, cs)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left.set_meta("uz_key", "m:gross")
	left.set_meta("uz_hint_a", "Groß anzeigen")
	left.set_active(Music.mode() != "aus" and not Music.now.is_empty())
	left.picked.connect(func() -> void: JetztLaeuft.zeigen(main))
	row.add_child(_rv(left))
	_music_cover = left
	_music_glow = TextureRect.new()
	_music_glow.texture = _glow_tex()
	_music_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_music_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_music_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_music_glow.position = Vector2(-cs, -cs) * 0.8
	_music_glow.size = Vector2(cs, cs) * 2.6
	_music_glow.modulate = UzTheme.col("music", 0.0)
	left.add_child(_music_glow)
	var frame := Panel.new()
	U.full_rect(frame)
	frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), 2))
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(frame)
	var center := CenterContainer.new()
	U.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(U.icon("music", 36, "faint"))
	frame.add_child(center)
	_music_art = TextureRect.new()
	_music_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_music_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_music_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_music_art)
	frame.add_child(_music_art)
	left.ring_oben()


## Rechts neben dem Cover: Titel, Interpret (mit Spotify anwählbar), Album, Gerät und wer mithört.
func _musik_angaben(row: Control) -> void:
	# Rechts daneben: was läuft und wo.
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var top := U.hbox(10)
	_eq = _Eq.new()
	top.add_child(_eq)
	var kick := _section("Läuft gerade" if Music.mode() != "aus" and not Music.now.is_empty() else "Musik",
			music_source_name(Music.now) if not Music.now.is_empty() else "")
	kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_music_kicker = kick.get_child(0)
	top.add_child(kick)
	col.add_child(_rv(top))
	col.add_child(U.spacer(0, 6, false))
	# Titel, Interpret und Album erscheinen zusammen (sonst stünde der Interpret vor dem Titel da).
	var info := U.vbox(0)
	col.add_child(_rv(info))
	_music_title = U.label("", "30", "text", "title", true)
	_music_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_music_title.max_lines_visible = 2
	_music_title.add_theme_constant_override("line_spacing", -6)
	info.add_child(_music_title)
	info.add_child(U.spacer(0, 2, false))
	# Der Künstler ist anwählbar (A öffnet seine Seite: Bild, beliebte Titel, Alben) – nur mit
	# Spotify bzw. in der Vorführung, sonst (auch bei eigener Musik) bleibt er ein schlichter Name.
	if ((Music.has_spotify() and Music.mode() != "aus") or Music.demo()) and not Music.local_on() and not Music.grundmodus():
		var link := _ArtistLink.new()
		link.set_meta("uz_key", "m:artist")
		link.set_meta("uz_hint_a", "Zum Künstler")
		link.picked.connect(func() -> void: MusicBits.open_artist(main, Music.artist_of_now()))
		info.add_child(link)
		_music_artist = link.label
	else:
		_music_artist = U.ellipsis(U.label("", "20", "muted", "medium"))
		info.add_child(_music_artist)
	_music_artist.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_music_album = U.ellipsis(U.label("", "cap", "faint", "regular"))
	_music_album.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.add_child(_music_album)
	var dev := U.hbox(6)
	dev.add_child(U.icon("speaker", 16, "muted"))
	_music_device = U.ellipsis(U.label("", "cap", "muted", "medium"))
	_music_device.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_music_device.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev.add_child(_music_device)
	info.add_child(dev)
	# Wer mithört (Discord-Status zeigt denselben Titel) oder eingeladen ist.
	_music_together = U.hbox(8)
	_music_together.visible = false
	_music_together.add_child(U.icon("headset", 16, "music"))
	var tl := U.ellipsis(U.label("", "cap", "music", "medium"))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_together.add_child(tl)
	info.add_child(_music_together)
	if not Music.together_changed.is_connected(_refresh_together):
		Music.together_changed.connect(_refresh_together)


## Fortschritt mit den beiden Zeiten.
func _musik_fortschritt() -> void:
	var prog := U.vbox(4)
	_content.add_child(_rv(prog))
	_music_bar = ProgressBarUz.new().setup(0.0, "accent", 3, 0)
	_music_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog.add_child(_music_bar)
	var times := U.hbox(0)
	_music_time = U.label("", "cap", "muted", "medium")
	_music_time.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # läuft jede Sekunde weiter: nur Zahlen
	_music_time.clip_text = false
	_music_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	times.add_child(_music_time)
	_music_total = U.label("", "cap", "muted", "medium")
	_music_total.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_music_total.clip_text = false
	times.add_child(_music_total)
	prog.add_child(times)


## Zufall und Herz nur, wo es sie gibt (Spotify, eigene Musik).
func _musik_steuerung(spotify: bool, local: bool) -> void:
	# Steuerung mittig, die Wiedergabe größer.
	var ctl := U.hbox(12)
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	ctl.set_meta("uz_group", "guide:music")
	ctl.set_meta("uz_row", true)
	_content.add_child(_rv(ctl))
	if spotify or local:
		_shuffle_btn = _round("shuffle", 48)
		_shuffle_btn.set_meta("uz_hint_a", "Zufall")
		_shuffle_btn.set_meta("uz_key", "m:shuffle")
		_shuffle_btn.pressed.connect(func() -> void:
			Music.set_shuffle(not bool(Music.now.get("shuffle", false)))
			_refresh_music()
		)
		ctl.add_child(_shuffle_btn)
	var prev := _round("prev", 56)
	prev.set_meta("uz_hint_a", "Vorheriger Titel")
	prev.set_meta("uz_key", "m:prev")
	prev.pressed.connect(func() -> void: Music.previous())
	ctl.add_child(prev)
	_play_btn = _round("pause" if bool(Music.now.get("playing", true)) else "play", 68, true)
	_play_btn.set_meta("uz_default", true)
	_play_btn.set_meta("uz_hint_a", "Pause" if bool(Music.now.get("playing", false)) else "Weiter")
	_play_btn.set_meta("uz_key", "m:play")
	_play_btn.pressed.connect(func() -> void:
		Music.play_pause()
		_refresh_music()
	)
	ctl.add_child(_play_btn)
	var nxt := _round("next", 56)
	nxt.set_meta("uz_hint_a", "Nächster Titel")
	nxt.set_meta("uz_key", "m:next_t")
	nxt.pressed.connect(func() -> void: Music.next())
	ctl.add_child(nxt)
	if spotify:
		_like_btn = _round("heart_f" if bool(Music.now.get("liked", false)) else "heart", 48)
		_like_btn.set_meta("uz_hint_a", "Gefällt mir")
		_like_btn.set_meta("uz_key", "m:like")
		_like_btn.pressed.connect(func() -> void:
			Music.toggle_like()
			_refresh_music()
		)
		ctl.add_child(_like_btn)


## Die Wege als Zeilen: Suchen, Playlists, Gerät, Song schicken, Songtext bzw. Alben.
func _musik_wege(spotify: bool, local: bool) -> void:
	var list := _list()
	_content.add_child(list)
	if spotify and Music.grundmodus():
		# Grundmodus: statt Suche und Playlists der eigene Verlauf (über dem Guide, auch im Spiel).
		var vh := _act("Zuletzt gehört", "history", _open_recent)
		vh.set_meta("uz_key", "m:recent")
		list.add_child(_rv(vh))
		_eigene_zeile(list)
	elif spotify:
		# Suchen, Playlists und Warteschlange öffnen sich über dem Guide – auch im Spiel, wo die
		# Musikseite von Uzai hinter dem Spiel läge.
		var find := _act("Musik suchen", "search", func() -> void: MusicBits.open_search(main))
		find.set("chevron", false)
		find.set("key_cmd", "y")
		find.set_meta("uz_key", "m:search")
		find.set_meta("uz_hint_a", "Suchen")
		list.add_child(_rv(find))
		var pl := _act("Playlists", "music", func() -> void: main.open_spotify_playlists())
		pl.set_meta("uz_key", "m:playlists")
		list.add_child(_rv(pl))
		_eigene_zeile(list)
	if spotify:
		var dv := _act("Gerät", "speaker", _pick_device)
		dv.set_meta("uz_hint_a", "Abspielen auf …")
		dv.set_meta("uz_key", "m:device")
		list.add_child(_rv(dv))
		# Song schicken: an Steam- und Discord-Freunde, über den Chat in Uzai (alle Freunde,
		# wer online ist zuerst).
		if Music.share_link() != "":
			var send := _act("Song an Freunde schicken", "chat", _send_song)
			send.set_meta("uz_hint_a", "Schicken")
			send.set_meta("uz_key", "m:send")
			list.add_child(_rv(send))
		_lyrics_btn = _lyrics_pill()
		list.add_child(_lyrics_btn)
	elif local:
		# Eigene Musik: Alben öffnen sich über dem Guide – auch im Spiel.
		var al := _act("Alben", "music", func() -> void: LocalUi.open_albums_sheet(main))
		al.set_meta("uz_key", "m:albums")
		list.add_child(_rv(al))
		# Neben Spotify: dessen Listen bleiben einen Druck entfernt (startet etwas, hält die eigene Musik an).
		if Music.beide() and Music.has_spotify():
			var sp := _act("Zuletzt gehört", "history", _open_recent) if Music.grundmodus() \
				else _act("Spotify-Playlists", "music", func() -> void: main.open_spotify_playlists())
			sp.set_meta("uz_key", "m:spotify")
			list.add_child(_rv(sp))
		if not Music.now.is_empty():
			_lyrics_btn = _lyrics_pill()
			list.add_child(_lyrics_btn)
	elif not Music.now.is_empty():
		_lyrics_btn = _lyrics_pill()
		list.add_child(_lyrics_btn)


## Eigene Musik gewählt, aber noch kein Musikordner: nichts zu spielen, nichts zu steuern.
func _ohne_ordner() -> bool:
	return Music.local_on() and LocalUi.state() == "ordner"


## Spotify spielt, daneben gibt es die eigene Musik: ihre Alben über dem Guide (auch im Spiel).
func _eigene_zeile(list: Control) -> void:
	if not Music.beide():
		return
	var e := _act("Eigene Musik", "folder", func() -> void: LocalUi.open_albums_sheet(main))
	e.set_meta("uz_key", "m:eigene")
	list.add_child(_rv(e))


## Die nächsten Titel der Warteschlange (Titel und Künstler): als Zeichen, ob neu gebaut werden muss.
func _queue_sig() -> String:
	return JSON.stringify(Music.queue_list.slice(0, 3).map(func(t): return [str(t.get("title", "")), str(t.get("artist", ""))] if t is Dictionary else []))


## „Als Nächstes“: bis zu drei Titel mit kleinem Cover; A spielt gleich diesen (ein Druck statt
## erst die Warteschlange zu öffnen). Sind es mehr, führt die letzte Zeile zur ganzen Liste.
func _next_rows() -> Control:
	_next_sig = _queue_sig()
	var box := U.vbox(0)
	var list: Array = Music.queue_list
	# Grundmodus ohne Warteschlange: die letzten Titel aus dem eigenen Verlauf (A spielt sie).
	var hist := list.is_empty() and Music.grundmodus() and not Music.local_on()
	if hist:
		list = Verlauf.recent(Music.verlauf_list(), 4).filter(func(t: Dictionary) -> bool: return str(t.uri) != str(Music.now.get("uri", "")))
	if list.is_empty():
		return box
	box.add_child(_divider(16))
	box.add_child(_section("Zuletzt gehört" if hist else "Als Nächstes"))
	box.add_child(U.spacer(0, 4, false))
	var rows := _list()
	rows.set_meta("uz_group", "guide:queue")
	box.add_child(rows)
	for i in mini(list.size(), 3):
		var t: Dictionary = list[i] if list[i] is Dictionary else {}
		var r = GuideRow.new().setup(str(t.get("title", "")), "", str(t.get("artist", "")))
		r.own_text = true
		r.lead = _queue_art(str(t.get("art", "")))
		r.value = _mmss(int(t.get("duration", 0))) if int(t.get("duration", 0)) > 0 else ""
		r.set_meta("uz_key", "m:q%d" % i)
		r.set_meta("uz_hint_a", "Abspielen")
		var idx := i
		r.activated.connect(func() -> void:
			if hist:
				_play_hist(t)
			elif Music.local_on():
				Music.local.skip_to(idx)
			else:
				Music.play_list(list, idx)
		)
		rows.add_child(_rv(r))
	if list.size() > 3 and not hist:
		var all := _act("Ganze Warteschlange", "list", _open_queue, "", str(list.size()))
		all.set("chevron", true)
		all.set_meta("uz_key", "m:next")
		rows.add_child(_rv(all))
	return box


## Kleines Cover vor einem Titel der Warteschlange.
func _queue_art(url: String) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(36, 36)
	p.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), 2))
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if url == "":
		return p
	var tr_ := TextureRect.new()
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(tr_)
	p.add_child(tr_)
	var wt: WeakRef = weakref(tr_)
	MusicS.load_art(url, 96, func(tex: Texture2D) -> void:
		var r: TextureRect = wt.get_ref()
		if r and tex:
			r.texture = tex
	)
	return p


## „Songtext“: erst sichtbar, wenn LRCLIB einen hat (der Streifen unten meldet es).
func _lyrics_pill() -> Control:
	var b := _act("Songtext", "subtitles", _open_lyrics)
	b.set_meta("uz_key", "m:lyrics")
	b.set_meta("uz_hint_a", "Ganzen Songtext zeigen")
	b.visible = false
	return b


## Der ganze Songtext über dem Guide, Strophe für Strophe (der Controller blättert). Läuft der
## Titel mit Zeitangaben, steht die Auswahl gleich auf der laufenden Strophe.
func _open_lyrics() -> void:
	var now: Dictionary = Music.now
	var data: Dictionary = await LyricsS.fetch(str(now.get("title", "")), str(now.get("artist", "")), str(now.get("album", "")), int(now.get("duration", 0)))
	if _closing or not is_inside_tree():
		return
	if str(data.get("state", "")) != "ok":
		Toasts.show_toast("Kein Songtext", str(now.get("title", "")), "subtitles", { "ms": 1600, "quiet": true })
		return
	var parts := stanzas(data, Music.progress_ms())
	var s = Sheet.new()
	s.setup("Songtext", "%s · %s" % [now.get("title", ""), now.get("artist", "")], 760)
	s.subheading_raw = true      # Titel und Künstler
	s.fill_func = func(sheet) -> void:
		for i in (parts.verses as Array).size():
			var v := _Verse.new()
			v.text = str(parts.verses[i])
			if i == int(parts.current):
				v.set_meta("uz_default", true)
			sheet.add_row(v)
		sheet.add_gap(10)
		sheet.add_label("Songtext: LRCLIB", "cap", "faint")
	main.open_layer(s)


## Songtext in Strophen (Leerzeilen trennen) und welche gerade läuft (-1 ohne Zeitangaben).
## { verses: [Text], current: int } – öffentlich für die Tests.
static func stanzas(data: Dictionary, ms: int) -> Dictionary:
	var synced: Array = data.get("synced", [])
	var lines: Array = []
	if synced.is_empty():
		for l in data.get("plain", PackedStringArray()):
			lines.append([-1, str(l)])
	else:
		lines = synced
	var cur_line := LyricsS.line_at(synced, ms) if not synced.is_empty() else -1
	var verses: Array = []
	var current := -1
	var want := false           # laufende Zeile ist leer (Pause): die nächste Strophe zählt
	var buf := PackedStringArray()
	for i in lines.size():
		if i == cur_line:
			want = true
		var t := str(lines[i][1]).strip_edges()
		if t == "":
			if not buf.is_empty():
				verses.append("\n".join(buf))
				buf = PackedStringArray()
			continue
		buf.append(t)
		if want:
			current = verses.size()
			want = false
	if not buf.is_empty():
		verses.append("\n".join(buf))
	if want and not verses.is_empty():
		current = verses.size() - 1
	return { "verses": verses, "current": current }


## Laufende und nächste Zeile eines Songtexts mit Zeitangaben: [jetzt, danach] (leer vor der
## ersten Zeile bzw. am Ende). Öffentlich für die Tests.
static func lyric_pair(synced: Array, ms: int) -> Array:
	return _LyricStrip.pair(synced, ms)


func _pick_device() -> void:
	var list := await Music.devices()
	if list.is_empty():
		# Kein Spotify offen: auf diesem PC unsichtbar starten und die Wiedergabe hierher holen.
		var dev := await Music.start_here()
		if dev != "":
			Music.switch_to(dev)
			return
		Toasts.show_toast("Kein Gerät gefunden", Music.error if Music.error != "" else "Spotify ließ sich auf diesem PC nicht starten.", "speaker")
		return
	# Guide inzwischen zu: keine Auswahl mehr öffnen.
	if _closing or not is_inside_tree():
		return
	var opts: Array = []
	var cur := ""
	for d in list:
		opts.append([str(d.id), str(d.name), "läuft gerade" if d.active else ("nicht steuerbar" if bool(d.get("restricted", false)) else "")])
		if d.active:
			cur = str(d.id)
	if Config.is_windows() and not Music.pc_dabei(list, OS.get_environment("COMPUTERNAME")):
		opts.append(["__start", "Dieser PC", ""])
	main.open_choice("Abspielen auf", opts, cur, func(id: Variant) -> void:
		if str(id) == "__start":
			var dev := await Music.start_here()
			if dev != "":
				Music.switch_to(dev)
			return
		Music.switch_to(str(id))
	)


## Was als Nächstes kommt, als Liste über dem Guide: A spielt ab diesem Titel.
func _open_queue() -> void:
	var s = Sheet.new()
	s.setup("Als Nächstes", "nach „%s“" % str(Music.now.get("title", "")) if not Music.now.is_empty() else "", 720)
	s.fill_func = func(sheet) -> void:
		var list: Array = Music.queue_list
		if list.is_empty():
			sheet.add_label("Die Warteschlange ist leer. Unter %s etwas auswählen." % ("Alben" if Music.local_on() else "Playlists"), "m", "muted")
			return
		for i in mini(list.size(), 30):
			var t: Dictionary = list[i]
			var it = ListItem.new()
			it.setup(str(t.get("title", "")), str(t.get("artist", "")), _mmss(int(t.get("duration", 0))))
			it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Titel und Künstler
			if str(t.get("art", "")) != "":
				it.image_url = str(t.art)
			else:
				it.icon_name = "music"
			it.set_meta("uz_hint_a", "Jetzt abspielen")
			var idx := i
			it.activated.connect(func() -> void:
				if Music.local_on():
					Music.local.skip_to(idx)
				else:
					Music.play_list(list, idx)
				sheet.close()
			)
			sheet.add_row(it)
	main.open_layer(s)


## Ein Titel aus dem eigenen Verlauf: in seiner Playlist bzw. seinem Album, sonst allein. Statisch: Der Guide geht
## nach der Wahl meist gleich zu – an ihm hängend käme die Meldung „spielt nicht“ dann nie.
static func _play_hist(t: Dictionary) -> void:
	if str(t.get("context", "")) != "":
		await Music.play_in(str(t.context), str(t.uri))
	else:
		await Music.play_list([t], 0)
	if Music.error != "":
		Toasts.show_toast(str(t.get("title", "")) + " spielt nicht", Music.error, "warning", { "ms": 4500 })


## Zuletzt gehört (eigener Verlauf, nur auf diesem PC) als Liste über dem Guide.
func _open_recent() -> void:
	var s = Sheet.new()
	s.setup("Zuletzt gehört", "nur auf diesem PC", 720)
	s.fill_func = func(sheet) -> void:
		var list := Verlauf.recent(Music.verlauf_list(), 30)
		if list.is_empty():
			sheet.add_label("Noch nichts gehört.", "m", "muted")
			return
		for t in list:
			var it = ListItem.new()
			it.setup(str(t.get("title", "")), str(t.get("artist", "")), "")
			it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Titel und Künstler
			if str(t.get("art", "")) != "":
				it.image_url = str(t.art)
			else:
				it.icon_name = "music"
			it.set_meta("uz_hint_a", "Abspielen")
			var tt: Dictionary = t
			it.activated.connect(func() -> void:
				_play_hist(tt)
				sheet.close()
			)
			sheet.add_row(it)
	main.open_layer(s)


## Den laufenden Song an einen Freund schicken – über den Steam- bzw. Discord-Chat in Uzai.
func _send_song() -> void:
	MusicShare.show_for(main, "song")


var _music_kicker: Label
var _music_together: HBoxContainer


func _refresh_together() -> void:
	if not is_instance_valid(_music_together):
		return
	var line := Music.together_line(Music.listeners, Music.waiting()) if not Music.now.is_empty() else ""
	_music_together.visible = line != ""
	(_music_together.get_child(1) as Label).text = line


func _refresh_music() -> void:
	_refresh_together()
	var now: Dictionary = Music.now
	if is_instance_valid(_music_kicker):
		_music_kicker.text = "Läuft gerade" if Music.mode() != "aus" and not now.is_empty() else "Musik"
	var t := ""
	var a := ""
	if Music.mode() == "aus":
		t = tr("Musik ist aus")
		a = tr("Unter Einstellungen → Klang → Musikquelle wählen")
	elif now.is_empty():
		if _ohne_ordner():
			t = tr("Noch keine Musik")
			a = tr("Ordner wählen – Alben kommen von selbst.")
		elif Music.local_on():
			t = tr("Gerade läuft nichts")
			a = tr("Unter Alben etwas auswählen")
		elif Music.mode() == "tasten" or not Music.has_spotify():
			t = tr("Gerade läuft nichts")
			a = tr("Musik in einer App starten")
		elif Music.grundmodus():
			var last := Verlauf.last(Music.verlauf_list())
			t = tr("Gerade läuft nichts")
			a = (tr("Zuletzt: %s · %s") % [str(last.t), str(last.a)]) if not last.is_empty() else tr("Musik in Spotify starten")
		else:
			t = tr("Gerade läuft nichts")
			a = tr("Unter Playlists etwas auswählen")
	else:
		t = str(now.get("title", ""))
		a = str(now.get("artist", ""))
	var playing := bool(now.get("playing", false)) and not now.is_empty()
	_update_hints()
	if is_instance_valid(_mini_box):
		_mini_title.text = t
		_mini_artist.text = ("%s  ·  %s" % [a, music_source_name(now)]) if a != "" else music_source_name(now)
		if is_instance_valid(_mini_play):
			_mini_play.icon = Icons.tex("pause" if playing else "play", 18)
		if is_instance_valid(_mini_total):
			_mini_total.text = _mmss(int(now.get("duration", 0))) if not now.is_empty() else ""
		if is_instance_valid(_mini_time):
			_mini_time.text = _mmss(Music.progress_ms()) if not now.is_empty() else ""
		if _mini_bar and is_instance_valid(_mini_bar) and not now.is_empty():
			_mini_bar.set_value(float(Music.progress_ms()) / maxf(float(now.get("duration", 1)), 1.0))
	if is_instance_valid(_music_title):
		_music_title.text = t
		_music_artist.text = a
		var lk := _music_artist.get_parent().get_parent()
		if lk is _ArtistLink:
			(lk as _ArtistLink).set_active(not Music.artist_of_now().is_empty())
		_music_album.text = str(now.get("album", ""))
		# Wo es spielt: Spotify-Gerät, Windows-App oder Uzai selbst (eigene Musik).
		var dev := tr("Eigene Musik") if str(now.get("source", "")) == "lokal" else str(now.get("device", ""))
		_music_device.text = dev
		_music_device.get_parent().visible = dev != ""
	if is_instance_valid(_music_next) and tab == "musik" and _queue_sig() != _next_sig:
		_rebuild_soon()
	if is_instance_valid(_eq):
		_eq.set("playing", playing)
	if _play_btn and is_instance_valid(_play_btn):
		_play_btn.icon = Icons.tex("pause" if playing else "play", 27)
		if _play_btn.get_meta("uz_hint_a", "") != ("Pause" if playing else "Weiter"):
			_play_btn.set_meta("uz_hint_a", "Pause" if playing else "Weiter")
			if _play_btn.has_focus():
				Nav.focus_moved.emit(_play_btn)
	if is_instance_valid(_like_btn):
		_like_btn.icon = Icons.tex("heart_f" if bool(now.get("liked", false)) else "heart", 19)
	if is_instance_valid(_shuffle_btn):
		var on := bool(now.get("shuffle", false))
		_shuffle_btn.add_theme_color_override("icon_normal_color", UzTheme.col("music") if on else UzTheme.col("text"))
	if is_instance_valid(_music_total):
		_music_total.text = _mmss(int(now.get("duration", 0))) if not now.is_empty() else ""
	if is_instance_valid(_music_time):
		_music_time.text = _mmss(Music.progress_ms()) if not now.is_empty() else ""
	if is_instance_valid(_music_bar) and not now.is_empty():
		_music_bar.set_value(float(Music.progress_ms()) / maxf(float(now.get("duration", 1)), 1.0))
	_refresh_art(now)


## Woher die Musik kommt, kurz: „Spotify“, die Windows-App („Apple Music“) oder „Eigene Musik“.
static func music_source_name(now: Dictionary) -> String:
	match str(now.get("source", "")):
		"lokal":
			return TranslationServer.translate("Eigene Musik")
		"windows":
			return str(now.get("device", "")) if str(now.get("device", "")) != "" else "Musik"
	return "Spotify"


## Cover des laufenden Titels im Reiter Musik und im kleinen Player oben. Kommt ein neuer Titel
## ohne Bild (Spotify meldet Windows das Cover oft erst nach Titel und Interpret), verschwindet das
## alte Cover – früher blieb es stehen, und nach dem Wiederöffnen des Guides fehlte es dann ganz.
## Ein spät fertiges Bild eines älteren Titels überschreibt nie das aktuelle.
func _refresh_art(now: Dictionary) -> void:
	var art := str(now.get("art", ""))
	var track := "%s|%s" % [now.get("title", ""), now.get("artist", "")]
	if art == "":
		if track != _art_track:
			_art_track = track
			_art_url = ""
			for r in [_music_art, _mini_art]:
				if is_instance_valid(r):
					r.texture = null
		return
	_art_track = track
	if art != _art_url:
		_art_url = art
		MusicS.load_art(art, 600, func(tex: Texture2D) -> void:
			if _art_url != art:
				return
			if tex == null:
				_art_url = ""       # beim nächsten Stand noch einmal versuchen
				return
			_cover_mass(true)
			if is_instance_valid(_music_art):
				_music_art.texture = tex
				_music_art.modulate.a = 0.0
				U.ankommen(_music_art, U.T_ORT, "uz_art").tween_property(_music_art, "modulate:a", 1.0, U.T_ORT)
			if is_instance_valid(_mini_art):
				_mini_art.texture = tex
			if is_instance_valid(_music_glow):
				var c: Variant = MediaS.color_of(tex)
				if c is Color:
					# Licht hinter dem Cover: nur Hintergrund, langsam (T_LICHT).
					U.ankommen(_music_glow, U.T_RAUM, "uz_glow").tween_property(_music_glow, "modulate", Color(c, 0.45), U.T_LICHT)
		)
	elif (is_instance_valid(_music_art) and _music_art.texture == null) or (is_instance_valid(_mini_art) and _mini_art.texture == null):
		# Reiter neu aufgebaut: dasselbe Bild aus dem Zwischenspeicher, samt Schein in seiner Farbe.
		MusicS.load_art(art, 600, func(tex: Texture2D) -> void:
			if _art_url != art or tex == null:
				return
			_cover_mass(true)
			if is_instance_valid(_music_art) and _music_art.texture == null:
				_music_art.texture = tex
				if is_instance_valid(_music_glow):
					var c: Variant = MediaS.color_of(tex)
					if c is Color:
						_music_glow.modulate = Color(c, 0.45)
			if is_instance_valid(_mini_art) and _mini_art.texture == null:
				_mini_art.texture = tex
		)


## Size of the cover area: large with an image, small without. It is applied when the image arrives: with the
## size fixed while building the tab, an image that arrived later (the track had just changed and Spotify
## answered late) stayed in the small box and the album art was not shown properly.
func _cover_mass(gross: bool) -> void:
	if not is_instance_valid(_music_cover):
		return
	var cs := 168.0 if gross else 112.0
	if is_equal_approx(_music_cover.custom_minimum_size.x, cs):
		return
	_music_cover.custom_minimum_size = Vector2(cs, cs)
	if is_instance_valid(_music_glow):
		_music_glow.position = Vector2(-cs, -cs) * 0.8
		_music_glow.size = Vector2(cs, cs) * 2.6


# --- Zeichnen: Songtext, Künstler, Equalizer ---------------------------------------

## Songtext unten im Musik-Reiter: die laufende Zeile hell, die nächste leise darunter; wechselt
## die Zeile, gleitet die neue weich hoch. Nur mit zeitgenauen Zeilen sichtbar, sonst nimmt der
## Streifen keinen Platz. found meldet, ob es überhaupt einen Songtext gibt (für „Songtext“).
class _LyricStrip extends Control:
	signal found(any: bool, synced: bool)
	const LS := preload("res://src/core/lyrics.gd")
	var _key := ""
	var _synced: Array = []
	var _pair: Array = ["", ""]
	var _t := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 0)
		visible = false
		Music.updated.connect(_check)
		_check()

	func _check() -> void:
		var now: Dictionary = Music.now
		var key := "%s|%s" % [str(now.get("title", "")), str(now.get("artist", ""))]
		if key == _key:
			return
		_key = key
		_synced = []
		_show(false)
		if str(now.get("title", "")) == "":
			found.emit(false, false)
			return
		var me: WeakRef = weakref(self)
		var res: Dictionary = await LS.fetch(str(now.get("title", "")), str(now.get("artist", "")), str(now.get("album", "")), int(now.get("duration", 0)))
		var s: Object = me.get_ref()
		if s == null or key != _key:
			return
		var ok := str(res.get("state", "")) == "ok"
		_synced = res.get("synced", []) if ok else []
		_pair = ["", ""]
		_show(not _synced.is_empty())
		found.emit(ok, not _synced.is_empty())

	static func pair(synced: Array, ms: int) -> Array:
		var i := LS.line_at(synced, ms)
		var cur := str(synced[i][1]).strip_edges() if i >= 0 else ""
		var nxt := ""
		for k in range(i + 1, synced.size()):
			nxt = str(synced[k][1]).strip_edges()
			if nxt != "":
				break
		return [cur, nxt]

	func _show(on: bool) -> void:
		visible = on
		custom_minimum_size = Vector2(0, 84 if on else 0)
		set_process(on)

	func _process(dt: float) -> void:
		_t = minf(1.0, _t + dt / 0.32)
		var p: Array = pair(_synced, Music.progress_ms() + 250)
		if p != _pair:
			_pair = p
			_t = 0.0
		queue_redraw()

	func _draw() -> void:
		var e := 1.0 - pow(1.0 - _t, 3.0)
		var bold := UzTheme.ui("ui_bold")
		var reg := UzTheme.font("medium")
		var w := size.x
		var cur := str(_pair[0]) if str(_pair[0]) != "" else "♪"
		var y := 34.0 + (1.0 - e) * 14.0
		# Songtext ist fremder Text: so zeichnen, wie er ist (übersetzt stand aus „Weiter“ plötzlich „Continue“ da).
		draw_string(bold, Vector2(0, y), cur, HORIZONTAL_ALIGNMENT_CENTER, w, 27, UzTheme.col("text", 0.35 + 0.65 * e))
		if str(_pair[1]) != "":
			draw_string(reg, Vector2(0, y + 36.0), str(_pair[1]), HORIZONTAL_ALIGNMENT_CENTER, w, 20, UzTheme.col("muted", 0.8 * e))


## Eine Strophe im Songtext-Blatt: wählbar, damit der Controller durch den Text blättert.
class _Verse extends MarginContainer:
	const UU := preload("res://src/ui/u.gd")
	var text := ""

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		for side in ["left", "right", "top", "bottom"]:
			add_theme_constant_override("margin_" + side, 18 if side in ["left", "right"] else 12)
		var l := UU.label(text, "m", "text", "medium", true)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Songtext
		l.add_theme_constant_override("line_spacing", 6)
		add_child(l)
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			queue_redraw()
		)

	func _draw() -> void:
		UU.draw_focus(self, 18)


## Das Cover im Reiter Musik (und das kleine im Start, guide.gd): anwählbar, A öffnet „Jetzt
## läuft“ groß. Gewählt: der eine Cursor der Kacheln (UzTheme.draw_tile_focus) im Cursor-Takt.
## Ohne laufende Musik nur Bild, nicht anwählbar.
class _CoverLink extends Control:
	signal picked
	const UU := preload("res://src/ui/u.gd")
	var radius := 2
	var _ring: Control

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		_ring = Control.new()
		_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UU.full_rect(_ring)
		_ring.draw.connect(func() -> void:
			UzTheme.draw_tile_focus(_ring, Rect2(Vector2.ZERO, _ring.size), radius, minf(float(_ring.get_meta("uz_f", 0.0)), 1.0)))
		add_child(_ring)

	func set_active(on: bool) -> void:
		focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE

	## Der Ring liegt über dem Bild: nach dem Einsetzen von Rahmen und Bild ganz nach oben.
	func ring_oben() -> void:
		move_child(_ring, get_child_count() - 1)

	func _ready() -> void:
		focus_entered.connect(func() -> void: UU.focus_anim(_ring, true))
		focus_exited.connect(func() -> void: UU.focus_anim(_ring, false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and focus_mode != Control.FOCUS_NONE:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event()
		)

	func activate() -> void:
		picked.emit()


## Der Künstler unter dem Songtitel, anwählbar: ruht als schlichter Name mit kleinem Pfeil, gewählt
## hell wie jede Zeile. A öffnet die Künstlerseite.
class _ArtistLink extends Control:
	signal picked
	const UU := preload("res://src/ui/u.gd")
	const PAD := Vector2(12, 4)
	var label: Label
	var _row: HBoxContainer
	var _chev: TextureRect

	## Ohne Künstler (nichts läuft) ist die Zeile nur Text: nicht anwählbar, ohne Pfeil.
	func set_active(on: bool) -> void:
		focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		if is_instance_valid(_chev):
			_chev.visible = on
		# Neuer Name (nach jedem Titelwechsel): neu messen – ein kürzerer Name löst kein „resized“
		# aus, die Zeile bliebe sonst so breit wie der lange Name davor.
		_fit()

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_row = UU.hbox(8)
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_row)
		label = UU.label("", "20", "muted", "medium")
		label.clip_text = false
		_row.add_child(label)
		_chev = UU.icon("chevron_right", 22, "faint")
		_chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(_chev)
		_row.resized.connect(_fit)
		label.resized.connect(_fit)

	func _ready() -> void:
		_fit()
		focus_entered.connect(func() -> void:
			UU.etikett(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			UU.etikett(self, false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	## Lange Namen kürzen (die Zeile ist so breit wie der Name, nie breiter als die Spalte).
	func _fit() -> void:
		if label == null:
			return
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		label.custom_minimum_size.x = 0
		var full := label.get_minimum_size().x
		if full > 600.0:
			label.custom_minimum_size.x = 600.0
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_row.reset_size()
		custom_minimum_size = _row.get_combined_minimum_size()
		queue_redraw()

	func activate() -> void:
		picked.emit()

	func _draw() -> void:
		UU.draw_focus(self, 14, Rect2(-PAD, size + PAD * 2.0))


## Vier Balken wie ein Pegel, die sich bewegen, solange Musik läuft.
class _Eq extends Control:
	var playing := false:
		set(v):
			playing = v
			set_process(v)
			queue_redraw()
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(22, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(playing)

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var c := UzTheme.col("music")
		for i in 4:
			var h := 4.0 if not playing else 4.0 + 13.0 * absf(sin(_t * (4.2 + i * 1.3) + i * 1.1))
			draw_style_box(UzTheme.box(c, 1), Rect2(i * 6, size.y - h, 3, h))
