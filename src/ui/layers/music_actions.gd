extends "res://src/ui/layers/sheet.gd"
## Musik im Guide: Gefällt mir, Zufall, Wiederholen, Playlists, Gerät, Song aufs Handy (QR-Code)
## und an einen Freund. Alles bleibt in Uzai – nichts öffnet Spotify oder den Browser.

const MusicQr := preload("res://src/ui/layers/music_qr.gd")

const Main := preload("res://src/main.gd")
var main: Main


func build() -> void:
	var now: Dictionary = Music.now
	setup(str(now.get("title", "Musik")) if not now.is_empty() else "Musik", str(now.get("artist", "")) if not now.is_empty()
			else ("Spotify" if Music.has_spotify() else "Medientasten"), 760)
	heading_raw = not now.is_empty()      # Titel des Lieds: nie übersetzen
	subheading_raw = not now.is_empty()   # Name des Künstlers
	super()


func _row(k: String, t: String, icon: String, v: Variant = null) -> Control:
	var r = SettingRow.new()
	r.setup(k, t, "", v)
	r.icon_name = icon
	return r


func fill() -> void:
	var now: Dictionary = Music.now
	var pp = _row("action", "Pause" if now.get("playing", false) else "Abspielen", "pause" if now.get("playing", false) else "play")
	pp.on_activate = func() -> void:
		Music.play_pause()
		await get_tree().create_timer(0.3).timeout
		refill()
	add_row(pp)
	if not Music.has_spotify():
		add_label("Mit Spotify-Konto: Gefällt mir, Playlists, Geräte und Songs fürs Handy.", "s", "muted")
		return
	if not now.is_empty():
		var like = _row("toggle", "Gefällt mir", "heart", bool(now.get("liked", false)))
		like.changed.connect(func(_v: Variant) -> void: Music.toggle_like())
		add_row(like)
		var sh = _row("toggle", "Zufällige Wiedergabe", "shuffle", bool(now.get("shuffle", false)))
		sh.changed.connect(func(v: Variant) -> void: Music.set_shuffle(bool(v)))
		add_row(sh)
		var rep := str(now.get("repeat", "off"))
		var rp = _row("action", "Wiederholen", "repeat")
		rp.value_text = { "off": "Aus", "context": "Liste", "track": "Titel" }.get(rep, "Aus")
		rp.on_activate = func() -> void:
			await Music.cycle_repeat()
			refill()
		add_row(rp)
	var pl = _row("action", "Playlists", "list")
	pl.on_activate = func() -> void: main.open_spotify_playlists()
	add_row(pl)
	var dev = _row("action", "Abspielen auf …", "speaker")
	dev.value_text = str(now.get("device", ""))
	dev.on_activate = _pick_device
	add_row(dev)
	if Music.share_link() != "":
		add_gap()
		var qr = _row("action", "Song aufs Handy", "qr")
		qr.value_text = "QR-Code"
		qr.on_activate = func() -> void:
			var l = MusicQr.new()
			l.link = Music.share_link()
			l.song = "%s – %s" % [now.get("title", ""), now.get("artist", "")]
			main.open_layer(l)
		add_row(qr)
		var send = _row("action", "Song an einen Freund schicken", "chat")
		send.on_activate = func() -> void:
			# Alle Freunde (Steam und Discord), wer online ist zuerst.
			load("res://src/ui/layers/music_share.gd").show_for(main, "song")
		add_row(send)
	if Music.error != "":
		add_label(Music.error, "s", "warn")


func _switch_to(dev_id: String) -> void:
	await Music.switch_to(dev_id)
	if is_inside_tree():
		refill()


## Gerät wählen. Läuft Spotify auf keinem PC, startet Uzai es hier im Hintergrund.
func _pick_device() -> void:
	var list := await Music.devices()
	var opts: Array = []
	for d in list:
		opts.append([str(d.id), str(d.name) + ("  ·  läuft" if d.active else ("  ·  nicht steuerbar" if bool(d.get("restricted", false)) else ""))])
	# Wie in Musik › Läuft gerade: Nur dieser PC zählt – läuft Spotify bloß auf einem anderen Rechner, fehlte der
	# Weg, es hier zu starten.
	if Config.is_windows() and not Music.pc_dabei(list, OS.get_environment("COMPUTERNAME")):
		opts.append(["__start", "Spotify auf diesem PC starten"])
	if opts.is_empty():
		Toasts.show_toast("Kein Gerät gefunden", "Spotify auf dem Handy oder einem Lautsprecher öffnen, dann erscheint es hier.", "speaker")
		return
	main.open_choice("Abspielen auf", opts, "", func(dev_id: Variant) -> void:
		if str(dev_id) == "__start":
			var got := await Music.start_here()
			if got != "":
				_switch_to(got)
			return
		_switch_to(str(dev_id))
	)
