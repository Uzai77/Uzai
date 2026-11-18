extends "res://src/ui/layers/layer.gd"
## Guide, unterste Schicht: Bausteine der Reiter (Überschrift, Abschnitt, Zeile, Trennlinie, Liste,
## weiches Erscheinen), Neuaufbau bei neuen Daten, Lautstärke (LT/RT, Anzeige) und die Tastenhinweise.
## Der Guide besteht aus Schichten; jede erbt von der darunter und kennt nur sie:
## guide_basis.gd → guide_spiel.gd → guide_discord.gd → guide_musik.gd → guide.gd.
## _show_tab ist hier nur ein Haken; die Reiter kennt erst guide.gd.

const GuideRow := preload("res://src/ui/components/guide_row.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const GuideQuick := preload("res://src/ui/components/guide_quick.gd")
const GuideMehr := preload("res://src/ui/components/guide_mehr.gd")
const Zustand := preload("res://src/core/zustand.gd")

## start_tab für das Schnellmenü (Guide-Taste halten): der Guide in klein, siehe guide_quick.gd.
const QUICK := "schnell"
## Reiter des Guides: LB/RB und Sprünge gehen von jedem zu jedem.
const ZUSTAENDE_REITER := { "*": ["spiel", "freunde", "discord", "musik", "system", "pip", "ton"],
	"": [], "spiel": [], "freunde": [], "discord": [], "musik": [], "system": [], "pip": [], "ton": [] }
## Breite der Leiste links (logische Pixel bei 1080 Zeilen); rechts bleibt das Spiel zu sehen.
const PANEL_W := 620.0
## Innenrand der Leiste links und rechts.
const PAD_X := 40

var start_tab := ""
var tab := "":
	set(neu):
		Zustand.wechsel("guide.reiter", ZUSTAENDE_REITER, tab, neu)
		tab = neu
var _panel: Control
var _content: VBoxContainer
var _vol_hud: PanelContainer
var _vol_ic: TextureRect
var _vol_l: Label
var _reveal: Array = []        ## Elemente, die nach dem Aufbau nacheinander einblenden
var _quiet := false            ## Neuaufbau wegen neuer Daten: ohne Bewegung
var _dirty := false            ## neue Daten kamen, während ein Menü offen war
var _hints_key := ""
var _folds := {}               ## „Mehr …“ aufgeklappt (Kennung -> true), hält über Neuaufbauten
var _old_keys := {}            ## Schlüssel (uz_key) vor dem letzten leisen Neuaufbau: Neues blendet nach


# --- Reiter --------------------------------------------------------------------------------

func _rv(c: Control) -> Control:
	_reveal.append(c)
	return c


func _focus_default() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_content):
		return
	var d := Nav.default_in(_content)
	if d:
		Nav.focus(d, true)


## Überschrift eines Reiters in der Titelschrift, daneben auf derselben Linie leise ein Zusatz.
## own: Überschrift und Zusatz sind Namen (Kanal, Server) bzw. schon übersetzt – bleiben, wie sie sind.
func _heading(text: String, sub := "", own := false) -> HBoxContainer:
	var row := U.hbox(14)
	var h := U.label(text, "36", "text", "title")
	h.clip_text = false
	if own:
		h.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(h)
	if sub != "":
		var s := U.ellipsis(U.label(sub, "17", "muted", "regular"))
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		s.custom_minimum_size.y = 34
		s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if own:
			s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(s)
	return row


## Abschnitt in der Leiste: kleines Etikett in Versalien, leicht gesperrt, leise („IM SPIEL · 6“).
## Gemeinsamer Baustein (liste.gd), überall gleich.
func _section(text: String, extra := "") -> HBoxContainer:
	return Liste.abschnitt(text, extra)


## Eine Zeile der Leiste (guide_row.gd): Symbol, Titel · Zusatz, rechts ein Wert.
func _row(t: String, ic: String, cb: Callable, extra := "", v := "", key := "") -> Control:
	var r = GuideRow.new().setup(t, ic, extra, v)
	r.set_meta("uz_key", key if key != "" else "r:" + t)
	if cb.is_valid():
		r.activated.connect(cb)
	return r


## Handlung als Zeile mit Pfeil (öffnet etwas); sub steht leise hinter dem Titel.
func _act(t: String, ic: String, cb: Callable, sub := "", v := "") -> Control:
	var r = GuideRow.new().setup(t, ic, sub, v)
	r.chevron = v == ""
	r.set_meta("uz_key", "a:" + t)
	r.activated.connect(cb)
	return r


## Haarlinie zwischen den Abschnitten (statt Karten), gemeinsamer Baustein (liste.gd).
func _divider(gap := 14) -> Control:
	return Liste.linie(gap)


## „Mehr …“, das an Ort und Stelle aufklappt (guide_mehr.gd); ohne Zeilen nichts. Der Zustand hält
## über Neuaufbauten wegen neuer Daten, ein neuer Guide fängt zugeklappt an.
func _fold(key: String, rows: Array) -> Control:
	if rows.is_empty():
		return null
	var f = GuideMehr.new().setup(key, rows, _folds.has(key))
	f.toggled.connect(func(on: bool) -> void:
		if on:
			_folds[key] = true
		else:
			_folds.erase(key)
	)
	return f


## Liste von Zeilen (eng, wie eine Konsole).
func _list() -> VBoxContainer:
	var l := U.vbox(2)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# --- Neuaufbau bei neuen Daten -------------------------------------------------------------

## Wo der Fokus gerade steht: sein Schlüssel, sonst seine Stelle im Reiter.
func _focus_token() -> String:
	var f := Nav.focused()
	if f == null or not is_instance_valid(_content) or not _content.is_ancestor_of(f):
		return ""
	if f.has_meta("uz_key"):
		return str(f.get_meta("uz_key"))
	return "#%d" % Nav.focusables(_content).find(f)


func _rebuild_soon() -> void:
	if not is_instance_valid(_content) or _closing:
		return
	_rebuild_keep(_focus_token())


## Reiter zeigen. Die Reiter kennt erst guide.gd, das diese Funktion überschreibt; hier ruft sie
## der Neuaufbau.
func _show_tab(_id: String, _focus := true, _dir := 0) -> void:
	pass


## Reiter neu bauen und den Fokus auf dem Element mit diesem Schlüssel halten.
func _rebuild_keep(key: String) -> void:
	# Nicht unter einem offenen Menü umbauen: das passiert, sobald der Guide wieder vorn ist.
	if Nav.top_layer() != self:
		_dirty = true
		return
	_dirty = false
	# Was es schon gab, steht nach dem Neuaufbau sofort wieder; nur Neues blendet nach (guide.gd).
	_old_keys = {}
	for c in Nav.focusables(_content):
		if c.has_meta("uz_key"):
			_old_keys[str(c.get_meta("uz_key"))] = true
	_quiet = true
	_show_tab(tab, false)
	_quiet = false
	await get_tree().process_frame
	if not is_instance_valid(_content):
		return
	# Stand die Auswahl außerhalb des Inhalts und hat den Umbau überstanden (Reiterzeile, Karte oben), bleibt sie
	# dort – sonst zog jeder Neuaufbau (neue Daten im Reiter Discord) sie vom Reiter in den Inhalt.
	var steht := Nav.focused()
	if steht != null and is_ancestor_of(steht) and not _content.is_ancestor_of(steht):
		return
	var all := Nav.focusables(_content)
	if key.begins_with("#"):
		var i := int(key.substr(1))
		if i >= 0 and i < all.size():
			Nav.focus(all[i], true)
			return
	elif key != "":
		for c in all:
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				return
	_focus_default()


# --- Kleine Helfer -------------------------------------------------------------------------------

## Knopf mit Symbol (Musik): runde Fläche mit dem Symbol (primary, Wiedergabe: getönt, sonst ruhend
## ohne Fläche). Gewählt hell wie jeder Knopf (U.ruhig). alert: aus (Symbol leise).
func _round(icon: String, px: int, primary := false, alert := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(px, px)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon = Icons.tex(icon, int(px * 0.4))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	U.ruhig(b, "symbol" if primary else "flach", 0)
	if alert:
		var f: Dictionary = b.get_meta("uz_kf")
		f.icon = UzTheme.col("muted")
		U.knopf_stand(b, 0.0)
	return b


static func _mmss(ms: int) -> String:
	var s := maxi(0, floori(ms / 1000.0))
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## Weiche Kanten über einer Liste, die rollt: oben, sobald gescrollt ist, unten, solange noch etwas
## kommt. Zwei Verläufe in der Farbe der Leiste darüber (die Leiste ist matt und deckend). Früher
## eine Maske über clip_children: über der Startseite schimmerte deren Bild dabei durch.
func _edge_fades(frame: Control, sc: ScrollContainer) -> void:
	var col := UzTheme.col("surface")
	var fades: Array = []
	for top in [true, false]:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(col, 1.0), Color(col, 0.0)]) if top else PackedColorArray([Color(col, 0.0), Color(col, 1.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 64
		var tr_ := TextureRect.new()
		tr_.texture = gt
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_.stretch_mode = TextureRect.STRETCH_SCALE
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr_.anchor_right = 1.0
		if top:
			tr_.offset_bottom = 40
		else:
			tr_.anchor_top = 1.0
			tr_.anchor_bottom = 1.0
			tr_.offset_top = -56
		tr_.modulate.a = 0.0
		frame.add_child(tr_)
		fades.append(tr_)
	var bar := sc.get_v_scroll_bar()
	var upd := func(_v: float = 0.0) -> void:
		if not is_instance_valid(bar) or not is_instance_valid(frame):
			return
		var rest := bar.max_value - bar.page - bar.value
		(fades[0] as CanvasItem).modulate.a = clampf(bar.value / 40.0, 0.0, 1.0)
		(fades[1] as CanvasItem).modulate.a = clampf(rest / 40.0, 0.0, 1.0)
	bar.value_changed.connect(upd)
	bar.changed.connect(upd)
	frame.resized.connect(upd)


# --- Lautstärke ----------------------------------------------------------------------------

## Unten in der Leiste: kurz, was LT/RT gerade ändern (Spiel, Video, Musik), mit dem echten Pegel.
func _build_volume_hud() -> Control:
	_vol_hud = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface_hi"), 2)
	sb.content_margin_left = 18
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_vol_hud.add_theme_stylebox_override("panel", sb)
	_vol_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := U.hbox(12)
	_vol_ic = U.icon("volume", 26, "text")
	_vol_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_vol_ic)
	_vol_l = U.label("Lauter", "m", "text", "ui_bold")
	_vol_l.clip_text = false
	row.add_child(_vol_l)
	_vol_hud.add_child(row)
	_vol_hud.anchor_top = 1.0
	_vol_hud.anchor_bottom = 1.0
	_vol_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_vol_hud.offset_left = PAD_X
	_vol_hud.offset_bottom = -84
	_vol_hud.modulate.a = 0.0
	return _vol_hud


## LT/RT im Guide: nur im Reiter Spiel (nur das Spiel bzw. Video, wie im Lautstärkemixer von
## Windows) und im Reiter Musik (nur die Musik). Sonst nirgends, und nie die Gesamtlautstärke.
func volume_step(d: int) -> void:
	if d == 0:
		return
	var target := _vol_target()
	match target:
		"":
			return
		"spotify", "spotify_fest", "lokal":
			# Music.change_volume: Spotify über die Web-API; lehnt Spotify ab (kein Premium, Gerät
			# ohne Lautstärke) und spielt es auf diesem PC, die Audiositzung der Spotify-App. Eigene
			# Musik: Uzais eigener Player.
			Sfx.play("tick", 1.0 + 0.08 * signf(d))
			if target != "spotify_fest":
				_show_volume_hud("music", volume_level_text(target, clampi(int(Music.now.get("volume", 50)) + 5 * signi(d), 0, 100), false))
			_music_volume(target, d)
		"video":
			# Video (YouTube, Trailer, Filme): mpvs eigene Lautstärke – dieselbe Stufe wie hoch/runter
			# im Player, sofort bekannt und gespeichert. Früher der Windows-Mixer für mpv: eine zweite,
			# unsichtbare Stufe daneben, und ohne gefundene Tonquelle passierte gar nichts.
			var before := Video.volume_level()
			var lv := Video.volume(Video.VOLUME_STEP * signi(d))
			Sfx.play("tick" if lv != before else "bump", 1.0 + 0.08 * signf(d))
			_show_volume_hud("volume_down" if lv == 0 or d < 0 else "volume", volume_level_text(target, lv, false))
		"spiel", "app":
			Sfx.play("tick", 1.0 + 0.08 * signf(d))
			if not _app_vol_busy:
				_show_volume_hud("volume_down" if d < 0 else "volume", volume_level_text(target, -1, false, _music_app(), d))
			_app_vol_pending += d
			_app_volume(target)
		_:
			Sfx.play("bump")
			_show_volume_hud("volume", volume_none_text(target, _music_app()))


func _music_volume(target: String, d: int) -> void:
	var r: Dictionary = await Music.change_volume(5 * signi(d))
	if not is_inside_tree():
		return
	if bool(r.get("ok", false)):
		_show_volume_hud("music", volume_level_text("lokal" if target == "lokal" else "spotify", int(r.level), bool(r.mute)))
	else:
		_show_volume_hud("volume", "Lautstärke gerade nicht erreichbar" if str(r.get("why", "")) == "fehler" else volume_none_text(target))


## Wohin LT/RT gehen. tab_id: Reiter; now: Music.now; spotify: Spotify-Konto verbunden.
## - Spiel: "video" (Video läuft, mpv), "spiel" (das Spiel samt Kindprozessen) oder "kein_spiel".
## - Musik: "spotify" (Spotify-Player über die Web-API), "spotify_fest" (Gerät ohne eigene
##   Lautstärke), "app" (andere Musik-App über Windows), "lokal" (eigene Musik) oder "keine_musik".
## Alle anderen Reiter: "" (keine Lautstärke, kein Hinweis).
static func volume_target(tab_id: String, in_game: bool, video: bool, now: Dictionary, spotify: bool) -> String:
	match tab_id:
		"spiel":
			if video:
				return "video"
			return "spiel" if in_game else "kein_spiel"
		"pip", "ton":
			# Bild in Bild: die eigene Lautstärke des kleinen Videos (Video.volume_key); Video-Ton:
			# dieselbe Stufe wie im Player.
			return "video"
		"musik":
			if str(now.get("title", "")) == "":
				return "keine_musik"
			if str(now.get("source", "")) == "windows":
				return "app"
			if str(now.get("source", "")) == "lokal":
				return "lokal"
			if not spotify:
				return "keine_musik"
			return "spotify" if int(now.get("volume", -1)) >= 0 else "spotify_fest"
	return ""


## Text in der Hinweisleiste für LT/RT ("": LT/RT fehlen dort).
static func volume_hint(target: String) -> String:
	return { "spiel": "Spiel-Lautstärke", "video": "Video-Lautstärke", "spotify": "Spotify-Lautstärke", "spotify_fest": "Spotify-Lautstärke",
			"app": "Musik-Lautstärke", "lokal": "Musik-Lautstärke" }.get(target, "")


## Anzeige unter der Karte: „Spiel 45 %“, „Spotify stumm“; level < 0: noch unbekannt (lauter/leiser).
static func volume_level_text(target: String, level: int, mute: bool, app := "", d := 0) -> String:
	var who: String = { "spiel": "Spiel", "video": "Video", "spotify": "Spotify" }.get(target, app if app != "" else "Musik")
	if level < 0:
		return who + (" lauter" if d > 0 else " leiser")
	return (who + " stumm") if mute else "%s %d %%" % [who, level]


## Hinweis, wenn LT/RT hier nichts zum Steuern finden (es passiert dann nichts).
static func volume_none_text(target: String, app := "") -> String:
	match target:
		"kein_spiel":
			return "Kein Spiel läuft"
		"spiel":
			return "Kein Ton vom Spiel gefunden"
		"video":
			return "Kein Ton vom Video gefunden"
		"app":
			return "Kein Ton von %s gefunden" % (app if app != "" else "der Musik-App")
		"spotify_fest":
			return "Dieses Spotify-Gerät regelt die Lautstärke selbst"
	return "Gerade läuft keine Musik"


func _vol_target() -> String:
	return volume_target(tab, Launcher.in_game, Video.watching(), Music.now, Music.has_spotify())


func _music_app() -> String:
	return str(Music.now.get("device", "")) if str(Music.now.get("source", "")) == "windows" else ""


func _volume_args(target: String) -> Dictionary:
	match target:
		"video":
			return { "pids": [Video.mpv_pid()] } if Video.mpv_pid() > 0 else {}
		"spiel":
			return Mixer.game_args(Launcher.pid, str(Launcher.current.get("install_dir", "")), Launcher.game_hwnd())
	return {}


var _app_vol_pending := 0      ## Schritte, die noch zum Helfer müssen (LT/RT schnell hintereinander)
var _app_vol_busy := false
var _demo_vol := {}            ## Demo ohne Windows: Pegel je Ziel


## Läufe von _app_volume, die gerade unterwegs sind (siehe dort).
var _app_volume_offen := 0


## Schickt die gesammelten Schritte an den Helfer (app-volume), einen Befehl auf einmal, und zeigt
## den echten Pegel des Programms. Findet er keinen Ton: nur der Hinweis, sonst passiert nichts.
func _app_volume(target: String) -> void:
	_app_volume_offen += 1
	await _app_volume_lauf(target)
	_app_volume_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _app_volume täte bis zum Neustart nichts mehr.
	if _app_volume_offen == 0 and _app_vol_busy:
		_app_vol_busy = false


func _app_volume_lauf(target: String) -> void:
	if _app_vol_busy:
		return
	_app_vol_busy = true
	while _app_vol_pending != 0:
		var step := clampi(_app_vol_pending, -6, 6)
		_app_vol_pending = 0
		var r := {}
		if Library.demo and not Config.is_windows():
			var lv := clampi(int(_demo_vol.get(target, 80)) + 5 * step, 0, 100)
			_demo_vol[target] = lv
			r = { "found": true, "level": lv, "mute": false }
		elif target == "app":
			r = await Music.app_volume(5 * step)
		else:
			var args := _volume_args(target)
			r = await Helper.app_volume(args, 5 * step) if not args.is_empty() else { "found": false }
		if not is_inside_tree():
			break
		if bool(r.get("found", false)):
			_show_volume_hud("volume_down" if step < 0 else "volume", volume_level_text(target, int(r.level), bool(r.mute), _music_app()))
		else:
			_app_vol_pending = 0
			_show_volume_hud("volume", "Lautstärke gerade nicht erreichbar" if bool(r.get("error", false)) else volume_none_text(target, _music_app()))
	_app_vol_busy = false


func _show_volume_hud(icon: String, text: String) -> void:
	if not is_instance_valid(_vol_hud):
		return
	_vol_ic.texture = Icons.tex(icon, 26)
	_vol_l.text = text
	_vol_hud.reset_size()
	_vol_hud.offset_top = _vol_hud.offset_bottom - _vol_hud.get_combined_minimum_size().y
	_vol_hud.pivot_offset = Vector2(0, _vol_hud.get_combined_minimum_size().y * 0.5)
	# Antwort auf den Druck (T_ANTWORT), setzt sich in T_ORT; nach einer Weile geht sie mit „Gehen“.
	var tw := U.ankommen(_vol_hud, U.T_ORT, "uz_vol").set_parallel(true)
	tw.tween_property(_vol_hud, "modulate:a", 1.0, U.T_ANTWORT)
	tw.tween_property(_vol_hud, "scale", Vector2.ONE, U.T_ORT).from(Vector2.ONE * U.wachsen(1.04))
	tw.chain().tween_interval(1.1)
	tw.chain().tween_property(_vol_hud, "modulate:a", 0.0, U.T_WEG).set_trans(Tween.TRANS_QUAD)


# --- Tastenhinweise ------------------------------------------------------------------------------

## Höchstens vier Hinweise unten in der Leiste: A, B und LB/RB (dazu X, wenn die gewählte Zeile es
## nennt). Y (Bildschirmfoto), LT/RT (Lautstärke) und X (Musik pausieren bzw. im Spiel
## Bildschirmfoto) wirken weiter, stehen aber nicht unten – die Zeile „Bildschirmfoto“ zeigt X.
func _update_hints() -> void:
	var h: Array = [["lb", ""], ["rb", "Bereich"]]
	var key := str(h)
	if key == _hints_key:
		return
	_hints_key = key
	set_meta("uz_hints", h)
	if is_inside_tree() and Nav.top_layer() == self:
		Nav.focus_moved.emit(Nav.focused())


# --- Schließen -----------------------------------------------------------------------------------

## Schließen (layer.gd): die Schrift geht zuerst (T_ANTWORT), dann gleitet die Leiste ganz nach
## links hinaus (guide.gd _exit_motion, ease-in: sie verlässt den Schirm), während die Ebene und
## die Abdunklung mit „Gehen“ ausblenden; die Wortmarke oben links bleibt stehen. Eigener Klang.
func close() -> void:
	if _closing:
		return
	Sfx.play("guide_close")
	# Aus dem Guide geöffnete Ebenen (Erfolge, Mitteilungen, Menüs) schließen mit.
	var i := Nav.layers.find(self)
	if i >= 0:
		for l in Nav.layers.slice(i + 1):
			if is_instance_valid(l):
				l.close()
	if start_tab == QUICK:
		GuideQuick.leave(self)
	super()


## Guide weg (auch ohne close(), etwa beim Neuaufbau): sein Reiter aus Zustand.lage() – sonst nennte
## der Fehlerbericht noch Stunden später den zuletzt offenen Reiter.
func _exit_tree() -> void:
	Zustand.vergessen("guide.reiter")


static func _can_screenshot() -> bool:
	return (Launcher.in_game or Video.active) and (Config.is_windows() or Library.demo)
