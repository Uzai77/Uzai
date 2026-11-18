extends "res://src/ui/layers/guide_musik.gd"
## Der Guide: eine Leiste links über allem, auch über dem laufenden Spiel oder Video – rechts
## bleibt das Spiel zu sehen (nur leicht abgedunkelt). Oben dein Profil (A: Status ändern) und die
## Uhr, darunter die Reiter Start, Freunde, Discord, Musik und System (LB/RB). Alles darunter ist
## eine Liste in einer Sprache: Zeilen mit Symbol, Text, rechts Wert, Taste oder Pfeil; Abschnitte
## mit kleinen Etiketten und Trennlinien statt Karten. Unten die Tastenhinweise.
## - Start: das laufende (sonst zuletzt gespielte) Spiel als Bühne mit seiner Hauptaktion und
##   Spielzeit, darunter wenige Zeilen passend zur Lage (guide_game.gd) und „Mehr …“, das an Ort
##   und Stelle aufklappt (Steam-Overlay, Bildmodus, Alle Aktionen); dann Kontext und Neues
##   (guide_start.gd: Erfolge mit dem nächsten, die neueste Aufnahme, neue Mitteilungen,
##   Downloads), Musik und Freunde nur, wenn es etwas zu sehen gibt, und ganz unten die
##   Schnellleiste (Mikro, Lautstärke, Controller, Ruhemodus, Ausschalten) – ein Druck.
## - Freunde: Im Spiel, Online, Abwesend (je gezählt), Steam und Discord zusammen mit Zeichen der
##   Quelle; A: Menü, X: Nachricht, Y: beitreten.
## - Discord: der Sprachkanal mit den Leuten als Zeilen, darunter was man im Kanal tut.
## - Musik: was läuft, Steuerung, die nächsten Titel, Suchen, Playlists, Gerät, Song schicken.
## - System, kurz: Mitteilungen (mit Zahl), Profil wechseln, Alle Einstellungen, „Mehr …“ (Bild &
##   Ton, Maus, Nicht stören, Aufnahmen, Kacheln, Doktor, Controller) und Ausschalten; Doktor und Controller vorn
##   nur bei einem Problem.
## Überall: B und die Guide-Taste schließen, Y macht im Spiel ein Bildschirmfoto; X im Start (im
## Spiel) ebenfalls, im Reiter Musik der nächste Titel, sonst pausiert X die Musik. LT/RT ändern die
## Lautstärke nur im Start (nur das Spiel bzw. Video) und in Musik (nur die Musik), nie die von
## Windows. Was hier aufgeht, bleibt in Uzai; kein Knopf holt ein anderes Programm nach vorn
## (Ausnahmen: Streams ansehen, Übertragen über die Discord-App).
##
## Hier stehen Aufbau, Kopf, Reiter, die Reiter Freunde und System, der untere Teil von Start und
## die Steuerung; darunter liegen Schichten (jede erbt von der darunter und kennt nur sie):
## guide_basis.gd (Bausteine, Lautstärke, Hinweise), guide_spiel.gd, guide_discord.gd und
## guide_musik.gd (je ein Reiter).

const Arbeit := preload("res://src/core/arbeit.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const FriendRow := preload("res://src/ui/components/guide_friend.gd")
const GuidePip := preload("res://src/ui/components/guide_pip.gd")
const GuideTon := preload("res://src/ui/components/guide_ton.gd")
const GuidePads := preload("res://src/ui/components/guide_pads.gd")
const GuideTiles := preload("res://src/ui/layers/guide_tiles.gd")
const GuideStart := preload("res://src/ui/components/guide_start.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const PadBattery := preload("res://src/ui/components/pad_battery.gd")
const Doktor := preload("res://src/core/doktor.gd")
const DoktorLage := preload("res://src/core/doktor_lage.gd")
const Zeichen := preload("res://src/ui/components/uzai_logo.gd")
const MovieArt := preload("res://src/ui/components/movie_art.gd")
const NichtStoeren := preload("res://src/core/nicht_stoeren.gd")
const ChatViewS := preload("res://src/ui/layers/chat_view.gd")
const PIN_GAP := 24.0           ## angehefteter Chat: Abstand zur Leiste und zum Rand

const TABS := [["spiel", "Start"], ["freunde", "Freunde"], ["discord", "Discord"], ["musik", "Musik"], ["system", "System"]]
const HEAD_H := 168.0           ## Kopf und Reiter (logische Pixel)
const FOOT_H := 88.0            ## Tastenhinweise unten
const ONLINE_MAX := 5           ## so viele „Online“ zeigt Freunde, bevor „N weitere“ aufklappt
const LOW_PCT := 20             ## Akku eines Controllers gilt ab hier als schwach

var _head: Control
var _glocke: Button             ## oben im Kopf: Mitteilungen (Punkt bei neuen), hinauf und A
var _glocke_punkt: Control
var _tabs_bar: Control
var _tabs_row: HBoxContainer
var _tab_ind: ColorRect
var _holder: Control
var _foot: Control
var _edge: Control
var _people_sig := ""          ## Stand der Freunde-Liste beim letzten Aufbau (Reiter Freunde)
var _fr_open := {}             ## Freunde: aufgeklappte Abschnitte („N weitere“), Kennung -> true
var _strip: Control            ## Schnellleiste, fest unten in der Leiste (nur im Start)
var _mic_btn: Button           ## Schnellleiste: der Mikro-Knopf (Zustand lebt mit, guide_start.gd)
var _mic_cap: Label
var _dl_row: Control           ## Zeile „Downloads“ im Start (Fortschritt lebt mit)
var _pads_sig := ""
## Das Zeichen oben links: steht genau dort, wo es in der Kopfzeile steht (main.brand_mark),
## bleibt beim Öffnen stehen und liegt über der Leiste, die darunter hineingleitet. Im Spiel
## (ohne Kopfzeile) erscheint es an derselben Stelle.
var _mark: Control
var _grund: Control            ## die Fläche der Leiste (Material „Kernlicht“)
var _pin: Control              ## angehefteter Chat ganz rechts am Schirm (chat_view.gd, angeheftet)
var _pin_back: Control         ## links aus dem Chat: zurück hierher


func build() -> void:
	# The page behind stays where it is: the push-back effect (layer.gd „Tiefe“) shifted the icons and text of the
	# whole UI by a few pixels on opening, which looked odd.
	depth = false
	# Über dem Menü steht die Seite dahinter als Bild, statt in jedem Bild neu gezeichnet zu werden
	# (main_fenster.gd seite_anhalten; nicht neben einem Spiel oder Video). Sie steht so, wie sie beim
	# Druck war: Die Auswahl verlässt sie erst, wenn das Abbild gezeichnet ist (_vor_dem_stapel).
	if main:
		main.seite_anhalten()
	if start_tab == QUICK:
		GuideQuick.build(self)
		return
	# Rechts bleibt das Spiel zu sehen, nur leicht abgedunkelt; über der Startseite etwas mehr.
	dim = 0.14 if Launcher.in_game else (0.3 if Video.watching() else 0.42)
	_scrim.color = Color(UzTheme.col("bg"), dim)
	# Im Spiel tritt die Startseite zurück, falls sie noch zu sehen ist.
	if Launcher.in_game and not Video.watching() and main and is_instance_valid(main.shell) and main.shell.visible:
		U.weg(main.shell, "uz_guide_shell").tween_property(main.shell, "modulate:a", 0.0, U.T_WEG)
		var sh: Control = main.shell
		closed.connect(func() -> void:
			if is_instance_valid(sh):
				U.ankommen(sh, U.T_ORT, "uz_guide_shell").tween_property(sh, "modulate:a", 1.0, U.T_ORT)
		)
	# Der Verlauf unten auf der Startseite (für die Leiste dort) läge über den eigenen Hinweisen.
	var fade: Variant = main._hint_fade if main else null
	if fade is CanvasItem and is_instance_valid(fade):
		var f: CanvasItem = fade
		U.weg(f, "uz_guide_fade").tween_property(f, "modulate:a", 0.0, U.T_WEG)
		closed.connect(func() -> void:
			if is_instance_valid(f):
				U.ankommen(f, U.T_ORT, "uz_guide_fade").tween_property(f, "modulate:a", 1.0, U.T_ORT)
		)
	set_meta("uz_hint_b", "Schließen")
	set_meta("uz_hints_eigen", true)
	set_meta("uz_silent", true)
	_update_hints()
	_build_panel()
	Music.updated.connect(_refresh_music)
	Music.lists_changed.connect(_on_music_lists)
	Music.quelle_changed.connect(_on_quelle)
	Voice.changed.connect(_on_voice_changed)
	Voice.speaking_changed.connect(_on_speaking)
	Social.updated.connect(_on_social)
	SteamChat.changed.connect(_on_unread)
	DiscordChat.changed.connect(_on_unread)
	Achievements.updated.connect(_on_achievements)
	Mixer.mic_changed.connect(_on_mic)
	Voice.changed.connect(func() -> void: _on_mic(GuideStart.mic_muted()))
	Installs.changed.connect(_on_installs)
	Launcher.hung_changed.connect(func(_on: bool) -> void:
		if tab == "spiel" and Launcher.in_game:
			_rebuild_soon()
	)
	_on_pads()
	Pads.changed.connect(_on_pads)
	_refresh_data()
	Pads.refresh()
	# Immer vorn anfangen (erster Reiter, erstes Element) – außer Uzai öffnet gezielt einen
	# Reiter (Anruf, Nachricht). Läuft Bild in Bild, ist das der Reiter „Bild in Bild“ (GuidePip.tabs).
	tab = start_tab if start_tab != "" else str(_tabs()[0][0])
	# Gestaffelt: Jetzt steht nur die Leiste (Kopf, Reiter, Hinweise), der Inhalt des Reiters kommt im
	# nächsten Bild – noch bevor die Leiste hereingleitet (_auf) und die Auswahl gesetzt wird
	# (layer.gd open). Beide warten selbst auf dieses Bild, und die Schrift ist bis NACH_FLAECHE
	# unsichtbar: Zu sehen ist derselbe Ablauf, aber kein Bild trägt mehr Leiste und Inhalt zusammen
	# (beim Freund bis 137 ms).
	get_tree().process_frame.connect(_inhalt_bauen, CONNECT_ONE_SHOT)
	# Das Aufgehen choreografiert _auf() (layer.gd ruft es gleich nach build).


## Zweiter Teil des Aufbaus (siehe build): der Inhalt des Start-Reiters.
func _inhalt_bauen() -> void:
	if not is_inside_tree() or _closing or not is_instance_valid(_holder):
		return
	_show_tab(tab, false)
	_refresh_music()
	_update_tab_dots()
	_pin_bauen()


## Skripte, die Reiter des Guides erst beim Aufbau laden (load): Beim ersten Mal übersetzte Godot
## sie mitten im Bild – „Remote Play“ im Discord-Reiter allein kostete gut 40 ms. main lädt sie kurz
## nach dem Start im Hintergrund (main_ebenen.gd _preload_rare); load() findet sie dann fertig.
const VORLADEN := ["res://src/core/call_invite.gd", "res://src/ui/layers/call_invite.gd", "res://src/ui/layers/discord_connect.gd",
	"res://src/ui/layers/discord_profile.gd", "res://src/ui/layers/sheet.gd", "res://src/ui/layers/spieler_controller.gd"]


static func vorladen() -> void:
	Arbeit.vorladen(VORLADEN)


## Schreibst du gerade mit jemandem (zuletzt geöffneter Chat, ChatView.pin_jetzt), steht das
## Gespräch als schmale Spalte ganz rechts am Schirm. Erst nach dem ersten Bild gebaut (der
## Guide geht ohne Wartezeit auf), der Verlauf lädt darin von selbst. Passt sie nicht neben die
## Leiste (große Oberfläche), bleibt sie weg.
func _pin_bauen() -> void:
	var p := ChatViewS.pin_jetzt()
	if p.is_empty():
		return
	await get_tree().process_frame
	if _closing or not is_inside_tree() or is_instance_valid(_pin):
		return
	var r := pin_rect(get_viewport().get_visible_rect().size)
	if r.size.x <= 0.0:
		return
	var cv = ChatViewS.new()
	cv.friend = p.friend
	cv.kind = str(p.kind)
	cv.main = main
	cv.angeheftet = true
	cv.bubble_max = r.size.x - 120.0
	cv.anchor_right = 0.0
	cv.anchor_bottom = 0.0
	cv.position = r.position
	cv.size = r.size
	cv.modulate.a = 0.0
	add_child(cv)
	cv.build()
	_pin = cv
	cv.closed.connect(func() -> void:
		var f := Nav.focused()
		if f == null or not is_instance_valid(f) or cv.is_ancestor_of(f):
			Nav.focus(_pin_back if is_instance_valid(_pin_back) and _pin_back.is_visible_in_tree() else Nav.default_in(_holder))
		_pin = null
	)
	var tw := U.ankommen(cv, U.T_ORT, "uz_pin").set_parallel(true)
	tw.tween_property(cv, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE)
	tw.tween_property(cv, "position:x", r.position.x, U.T_ORT).from(r.position.x + 32.0)


## Rect of the chat column (logical pixels): at the far right of the screen, where the chat also opens from the
## friends list, not directly next to the panel; as tall as the screen minus the margin. Empty if there is not
## enough room between the panel and the edge.
static func pin_rect(view: Vector2) -> Rect2:
	var w := minf(ChatViewS.PIN_W, view.x - panel_w(view.x) - PIN_GAP * 2.0)
	if w < ChatViewS.PIN_MIN_W:
		return Rect2()
	return Rect2(view.x - w - PIN_GAP, PIN_GAP, w, view.y - PIN_GAP * 2.0)


## Links Guide, rechts Chat: Rechts von einer Zeile der Leiste (ohne Nachbarn daneben) geht es in
## den Chat, links aus dem Chat (ohne Nachbarn) zurück an dieselbe Stelle der Leiste.
func _pin_dir(dir: String) -> bool:
	if not is_instance_valid(_pin) or (dir != "left" and dir != "right") or _pin.get("_closing"):
		return false
	var f := Nav.focused()
	if f == null or not is_instance_valid(f):
		return false
	if dir == "left" and _pin.is_ancestor_of(f) and not _nachbar(_pin, f, -1):
		_pin.call("pin_verlassen", f)
		var back: Control = _pin_back if is_instance_valid(_pin_back) and _pin_back.is_visible_in_tree() else Nav.default_in(_holder)
		if back:
			Nav.focus(back)
			return true
	if dir == "right" and is_instance_valid(_panel) and _panel.is_ancestor_of(f) and not _nachbar(_panel, f, 1):
		if f.has_method("nav_lr") and f.call("nav_lr", 1):
			return true
		var to: Control = _pin.call("pin_fokus")
		if to:
			_pin_back = f
			Nav.focus(to)
			return true
	return false


## Liegt in root neben f (gleiche Höhe) noch etwas in Richtung d (−1 links, 1 rechts)?
static func _nachbar(root: Control, f: Control, d: int) -> bool:
	var a := f.get_global_rect()
	for e in Nav.focusables(root):
		if e == f:
			continue
		var b := e.get_global_rect()
		if minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y) <= 4.0:
			continue
		if (d > 0 and b.position.x >= a.end.x - 12.0) or (d < 0 and b.end.x <= a.position.x + 12.0):
			return true
	return false


## Breite der Leiste: 620 logische Pixel, auf schmalen Fenstern (große Oberfläche) höchstens die
## Hälfte – rechts bleibt immer das Spiel.
static func panel_w(view_w: float) -> float:
	return minf(PANEL_W, roundf(view_w * 0.5))


## Platz für die Liste zwischen Kopf und Hinweisen; was nicht passt, rollt mit der Auswahl.
static func body_room(view_h: float) -> float:
	return view_h - HEAD_H - FOOT_H


func _build_panel() -> void:
	var vs := get_viewport().get_visible_rect().size
	_panel = Control.new()
	# Up at the top edge wraps around to the bottom and vice versa (nav.gd).
	_panel.set_meta("uz_umlauf", true)
	_panel.anchor_bottom = 1.0
	_panel.offset_right = panel_w(vs.x)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	get_viewport().size_changed.connect(func() -> void:
		if is_instance_valid(_panel):
			_panel.offset_right = panel_w(get_viewport().get_visible_rect().size.x)
	)
	# Die Leiste schwebt über dem Spiel (Höhenstufe 3, Schatten nach rechts) im Material „Kernlicht“:
	# Licht von oben, zur Mitte des Schirms hin ein Hauch Akzent, feines Korn.
	var bg := Panel.new()
	var gsb := UzTheme.box(UzTheme.col("surface"), 0)
	UzTheme.lift(gsb, 3)
	gsb.shadow_offset = Vector2(12, 0)
	bg.add_theme_stylebox_override("panel", gsb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bg)
	_panel.add_child(bg)
	UzTheme.kernlicht(bg)
	_grund = bg
	# Signatur: die rechte Kante glimmt ganz leicht in der Farbe des Spiels.
	_edge = _Edge.new()
	_edge.anchor_left = 1.0
	_edge.anchor_right = 1.0
	_edge.anchor_bottom = 1.0
	_edge.offset_left = -1.0
	_edge.offset_right = 28.0
	_panel.add_child(_edge)
	var g: Dictionary = Launcher.current if Launcher.in_game else {}
	if g.is_empty() and not Video.watching():
		var rec: Array = Library.recent(1)
		g = rec[0] if not rec.is_empty() else {}
	if not g.is_empty():
		var we: WeakRef = weakref(_edge)
		var wg: WeakRef = weakref(bg)
		Media.game_tint(g, func(c: Variant) -> void:
			var e: Control = we.get_ref()
			if e and c is Color:
				e.set("tint", c)
			# Das Kernlicht der Leiste nimmt die Farbe des Spiels an (hell genug, nie grell).
			var b: Control = wg.get_ref()
			var m: ShaderMaterial = b.material as ShaderMaterial if b else null
			if m and c is Color:
				var tc := c as Color
				m.set_shader_parameter("akzent", Color.from_hsv(tc.h, minf(tc.s, 0.55), clampf(tc.v, 0.6, 0.85)))
		)
	_head = _build_top()
	_panel.add_child(_head)
	_tabs_bar = _build_tabs()
	_panel.add_child(_tabs_bar)
	# Die Fläche der Reiter: so breit wie die Leiste, damit der Cursor über die Zeilen ragen darf.
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.anchor_right = 1.0
	_holder.anchor_bottom = 1.0
	_holder.offset_top = HEAD_H
	_holder.offset_bottom = -FOOT_H
	_holder.clip_contents = true
	_panel.add_child(_holder)
	_foot = U.margin(PAD_X, 0, PAD_X, 0)
	_foot.anchor_top = 1.0
	_foot.anchor_right = 1.0
	_foot.anchor_bottom = 1.0
	_foot.offset_top = -FOOT_H
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HintBar.new()
	hb.inside = true
	hb.gap = 18
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foot.add_child(hb)
	_panel.add_child(_foot)
	hb.refresh.call_deferred(true)
	_panel.add_child(_build_volume_hud())
	_build_mark()


## Das Zeichen über der Leiste, an der Stelle aus mark_rect (ganze Pixel).
func _build_mark() -> void:
	var r := mark_rect(main.brand_mark if main else null)
	_mark = Zeichen.new()
	_mark.set("stil", "kopf")
	_mark.name = "Zeichen"
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark)
	var inv := get_global_transform().affine_inverse()
	_mark.position = (inv * r.position).round()
	_mark.size = r.size
	# Kopf: Platz rechts neben dem Zeichen, damit dein Profil nicht darunter liegt.
	var row: Node = _head.get_child(0) if is_instance_valid(_head) and _head.get_child_count() > 0 else null
	if row is HBoxContainer:
		var gap := U.spacer(maxi(0, int(ceilf(r.end.x - float(PAD_X) + 28.0))), 0, false)
		row.add_child(gap)
		row.move_child(gap, 0)


## Wo das Zeichen im Guide steht (Schirm-Koordinaten): genau über dem in der Kopfzeile von Uzai
## (bm = main.brand_mark), sonst – im Spiel, ohne Kopfzeile – an seinem gewohnten Platz oben links.
static func mark_rect(bm: Variant, view := Vector2(1920, 1080)) -> Rect2:
	if bm is Control and is_instance_valid(bm) and (bm as Control).is_inside_tree() and (bm as Control).size.x >= 4.0:
		var c := bm as Control
		var xf := c.get_global_transform()
		return Rect2(xf.origin, c.size * xf.get_scale())
	var k := view.y / 1080.0
	var h := Zeichen.KOPF_H * k
	return Rect2(Vector2(Zeichen.KOPF_MITTE.x * k, Zeichen.KOPF_MITTE.y * k - h * 0.5), Vector2(Zeichen.zeichen_breite(h, Zeichen.KOPF_STIL == "kachel"), h))


## Die deckende Fläche der Ebene (layer.gd, Fläche vor Schrift): die Leiste. Das Schnellmenü hat
## keine – dann blendet die Ebene wie jede andere.
func flaeche() -> Control:
	return _panel if is_instance_valid(_panel) else null


## Die Schrift auf der Leiste: Kopf, Reiter, Inhalt und Tastenhinweise. Sie kommt nach der Fläche
## und geht vor ihr (T_ANTWORT); das Zeichen gehört nicht dazu, es bleibt stehen.
func schrift() -> Array:
	var out: Array = []
	for c in [_head, _tabs_bar, _holder, _strip, _foot]:
		if c is Control and is_instance_valid(c):
			out.append(c)
	return out


## Aufgehen mit Tiefe (Signatur der Marke): die Abdunklung blendet in T_ORT ein, die Oberfläche
## dahinter rückt zurück (layer.gd, _push_back), die Leiste kommt deckend in T_ORT von links und
## gleitet unter dem Zeichen hinein, das stehen bleibt; ihre Schrift folgt NACH_FLAECHE später
## und gestaffelt (Kopf, Reiter, Inhalt, Hinweise). Die Fuge leuchtet im selben Bild wie die
## Guide-Taste (_signatur). Bedienbar ist der Guide ab dem nächsten Bild, die Leiste gleitet noch.
func _auf() -> void:
	if not is_instance_valid(_panel):
		super()
		return
	modulate.a = 1.0
	var w := _panel.offset_right
	var gleiten := not U.reduziert()
	if gleiten:
		_panel.offset_left = -w
		_panel.offset_right = 0.0
	var ziel := _scrim.color if is_instance_valid(_scrim) else Color.TRANSPARENT
	if is_instance_valid(_scrim):
		_scrim.color = Color(ziel, 0.0)
	var text := schrift()
	for c: Control in text:
		c.modulate.a = 0.0
	_signatur()
	# Erst im nächsten Bild: der Aufbau selbst kostet ein Bild, sonst spränge die Leiste herein.
	await get_tree().process_frame
	if not is_instance_valid(_panel) or _closing:
		return
	var tw := U.ankommen(_panel, U.T_ORT, "uz_intro").set_parallel(true)
	if is_instance_valid(_scrim):
		tw.tween_property(_scrim, "color", ziel, U.T_ORT)
	if gleiten:
		tw.tween_property(_panel, "offset_left", 0.0, U.T_ORT)
		tw.tween_property(_panel, "offset_right", w, U.T_ORT)
	var i := 0
	for c: Control in text:
		tw.tween_property(c, "modulate:a", 1.0, U.T_ORT - U.NACH_FLAECHE).set_delay(U.NACH_FLAECHE + U.staffel(i))
		i += 1
	if is_instance_valid(_grund):
		U.aufglanz(_grund, U.NACH_FLAECHE)


## Schließen (layer.gd ruft es mit dem Tween der Ebene): die Schrift ist schon auf dem Weg
## (T_ANTWORT), die Leiste gleitet in T_WEG ganz nach links hinaus – ease-in, sie verlässt den
## Schirm –, während die Ebene und die Abdunklung mit der Kurve „Gehen“ ausblenden.
func _exit_motion(tw: Tween) -> void:
	if not is_instance_valid(_panel):
		return
	U.stop(_panel, "uz_intro")
	tw.set_parallel(true)
	tw.tween_property(_panel, "position:x", -U.weg_px(_panel.size.x), U.T_WEG).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Guide-Signatur, alles im Bild der Guide-Taste: Ein Licht läuft einmal durch die Fuge des Zeichens
## (über der Leiste und in der Kopfzeile, main.brand_mark). Klang und tiefer Impuls kommen aus
## Sfx.play("guide") (sfx.gd → Pads.pulse("guide")), das main_guide.gd unmittelbar vor dem Öffnen
## ruft – im selben Bild.
func _signatur() -> void:
	if is_instance_valid(_mark):
		_mark.call("pulse")
	var bm: Variant = main.brand_mark if main else null
	if bm is Object and is_instance_valid(bm) and (bm as Object).has_method("pulse"):
		(bm as Object).call("pulse")


## Frische Daten nach dem Öffnen, alle im Hintergrund: Musik, Freunde, ungelesene Nachrichten,
## Sprachkanal, Mikro. Nichts davon hält den Aufbau auf – der Guide steht aus dem Zwischenspeicher.
func _refresh_data() -> void:
	Voice.refresh()
	SteamChat.refresh_unread()
	Mixer.refresh_mic()
	if Library.demo:
		return
	Music.poll()
	if Music.mode() == "spotify" and Music.has_spotify():
		Music.load_queue()
	# Freunde frisch, wenn die letzte Abfrage älter als 20 s ist (Status auch vom Chat-Server).
	Social.refresh_stale(20.0)


# --- Kopf ----------------------------------------------------------------------------------

## Kopf: links du (Bild, Name, „● Online · Level 34“; A: Status ändern), rechts Mikro-Hinweis,
## PC-Akku und die Uhr.
func _build_top() -> Control:
	var head := U.margin(PAD_X, 34, PAD_X, 0)
	head.anchor_right = 1.0
	head.offset_bottom = 104
	var row := U.hbox(14)
	head.add_child(row)
	# Die Karte nimmt den Platz bis zur Glocke und kürzt lange Namen mit „…“ – vorher schob ein
	# langer Name (oder der Hinweis „Mikro aus“) die Uhr rechts aus der Leiste.
	var me := _MeCard.new()
	me.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	me.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me.chosen.connect(func() -> void:
		if MyStatus.has_steam() or MyStatus.has_discord():
			_open_my_profile(me)
		else:
			main.open_profiles("switch")
	)
	row.add_child(me)
	# Mitteilungen als Glocke im Kopf (statt Zeilen im Start und in System): hinauf, A öffnet sie.
	_glocke = MovieArt.icon_button("bell")
	_glocke.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glocke.set_meta("uz_key", "kopf:glocke")
	_glocke.set_meta("uz_hint_a", "Mitteilungen")
	_glocke.pressed.connect(func() -> void:
		Toasts.unread = 0
		main.open_notifications()
		_update_tab_dots()
		_dirty = true
	)
	_glocke_punkt = Control.new()
	_glocke_punkt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glocke_punkt.position = Vector2(34, 8)
	# Wie die Punkte an den Reitern: ein kleines Quadrat im Akzent.
	_glocke_punkt.draw.connect(func() -> void: _glocke_punkt.draw_rect(Rect2(0, 0, 6, 6), UzTheme.col("accent")))
	_glocke_punkt.visible = Toasts.unread > 0
	_glocke.add_child(_glocke_punkt)
	row.add_child(_glocke)
	var mikro := preload("res://src/ui/components/mic_badge.gd").new()
	mikro.kurz = true
	row.add_child(mikro)
	var pc := preload("res://src/ui/components/pc_akku.gd").new()
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pc)
	_clock = U.label(U.clock(), "22", "text", "ui_bold")
	_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Uhrzeit
	_clock.clip_text = false
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clock)
	return head


# --- Reiter --------------------------------------------------------------------------------

## Reiterzeile: [LB] Start · Freunde (kleine Zahl) · Discord · Musik · System [RB]; der gewählte
## hell und fett, darunter ein Strich im Akzent, der zum neuen Reiter gleitet. LB/RB stehen als
## Tasten an den Enden – unten muss „Bereich“ darum nicht noch einmal stehen.
func _build_tabs() -> Control:
	var bar := U.margin(PAD_X, 0, PAD_X, 0)
	bar.anchor_right = 1.0
	bar.offset_top = 104
	bar.offset_bottom = 148
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := U.hbox(0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	var lb := U.glyph("lb", 24)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lb)
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	_tabs_row = U.hbox(0)
	_tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_tabs_row)
	holder.add_child(_tabs_row)
	_tab_ind = ColorRect.new()
	_tab_ind.color = UzTheme.col("accent")
	_tab_ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_ind.size = Vector2(0, 2)
	holder.add_child(_tab_ind)
	var rb := U.glyph("rb", 24)
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rb)
	_fill_tabs()
	holder.resized.connect(func() -> void:
		_fit_tabs()
		_move_indicator(false))
	return bar


## Reiter (neu) in die Zeile legen; so eng, dass auch „Bild in Bild“ oder „Video-Ton“ noch passen.
func _fill_tabs() -> void:
	U.clear(_tabs_row)
	var list := _tabs()
	for t in list:
		var item := _TabPill.new()
		item.id = str(t[0])
		# Mit Kontext „tab“: Wo die Übersetzung zu lang für die Leiste ist, gibt es eine kurze
		# („Bild in Bild“ → „PiP“).
		item.text = game_tab_label() if item.id == "spiel" else TranslationServer.translate(str(t[1]), "tab")
		item.on = item.id == tab
		if item.id == "freunde":
			var n: int = main.online_friends() if main else 0
			item.count = str(n) if n > 0 else ""
		item.picked.connect(func(id: String) -> void:
			if id != tab:
				var ids := _tabs().map(func(x): return str(x[0]))
				Sfx.play("tab")
				_show_tab(id, true, signi(ids.find(id) - ids.find(tab)))
		)
		# Reachable with the D-pad, so up and down do not skip the tabs: the selected tab accepts the focus;
		# left/right switches like LB/RB, down or A moves into the content.
		item.set_meta("uz_key", "reiter:" + item.id)
		item.set_meta("uz_hint_a", "Öffnen")
		item.schritt.connect(_step_tab)
		item.betreten.connect(_focus_default)
		_tabs_row.add_child(item)
	_fit_tabs()
	if tab != "":
		_move_indicator(false)


## Reiter an den Platz zwischen LB und RB anpassen (tab_fit). Vor dem ersten Layout geschätzt
## (Leiste ohne Rand, LB und RB je 36 px), danach bei jeder Größenänderung genau.
func _fit_tabs() -> void:
	if not is_instance_valid(_tabs_row):
		return
	var holder := _tabs_row.get_parent() as Control
	var room := holder.size.x if holder.size.x > 0.0 else panel_w(get_viewport().get_visible_rect().size.x) - PAD_X * 2.0 - 72.0
	var widths: Array = []
	for c in _tabs_row.get_children():
		widths.append((c as _TabPill).word_w())
	var passt := tab_fit(widths, room)
	for c in _tabs_row.get_children():
		(c as _TabPill).fit(float(passt.pad), int(passt.fs))


## Wie die Reiter zwischen LB und RB passen: { pad (Abstand je Seite), fs (Schriftgröße) }. widths:
## Wort und Zahl je Reiter bei 20 px. Sonst 12 px Abstand, ab sechs Reitern 8 px; reicht das nicht
## (lange Wörter, „Bild in Bild“ als erster Reiter), erst enger bis 4 px, dann die Schrift kleiner
## bis 16 px – vorher lag RB über dem letzten Reiter.
static func tab_fit(widths: Array, room: float) -> Dictionary:
	var n := widths.size()
	var pad := 12.0 if n <= 5 else 8.0
	var sum := 0.0
	for w in widths:
		sum += float(w)
	if n == 0 or sum + pad * 2.0 * n <= room:
		return { "pad": pad, "fs": 20 }
	var p := floorf((room - sum) / (2.0 * n))
	if p >= 4.0:
		return { "pad": p, "fs": 20 }
	return { "pad": 4.0, "fs": clampi(floori(20.0 * (room - 8.0 * n) / sum - 0.5), 16, 20) }


## Strich unter den gewählten Reiter schieben (gleitet weich, die Breite folgt dem Wort).
func _move_indicator(animate: bool) -> void:
	if not is_instance_valid(_tab_ind) or not is_instance_valid(_tabs_row):
		return
	var it: Control = null
	for c in _tabs_row.get_children():
		if str(c.get("id")) == tab:
			it = c
	if it == null:
		return
	await get_tree().process_frame
	if not is_instance_valid(it) or not is_instance_valid(_tab_ind):
		return
	var r: Rect2 = it.call("word_rect")
	var x := _tabs_row.position.x + it.position.x + r.position.x
	var y := _tabs_row.position.y + it.position.y + it.size.y - 3.0
	if not animate or _tab_ind.size.x < 1.0:
		_tab_ind.position = Vector2(x, y)
		_tab_ind.size = Vector2(r.size.x, 2)
		return
	# Ortswechsel in der Ebene: der Strich gleitet in T_ORT mit der Kurve „Ankommen“.
	var tw := U.ankommen(_tab_ind, U.T_ORT, "uz_ind").set_parallel(true)
	tw.tween_property(_tab_ind, "position", Vector2(x, y), U.T_ORT)
	tw.tween_property(_tab_ind, "size:x", r.size.x, U.T_ORT)


## Punkte an den Reitern: Freunde (ungelesene Nachrichten), System (neue Mitteilungen, oder der
## Uzai-Doktor sieht etwas Wichtiges – abschaltbar wie der Hinweis).
func _doktor_dot() -> bool:
	if not bool(Config.get_value("system.doktor_hint", true)):
		return false
	return int(Doktor.summary(Doktor.cards(DoktorLage.cached())).wichtig) > 0


func _update_tab_dots() -> void:
	if not is_instance_valid(_tabs_row):
		return
	for it in _tabs_row.get_children():
		match str(it.get("id")):
			"freunde":
				it.set("dot", not SteamChat.unread.is_empty() or DiscordChat.total_unread() > 0)
				var n: int = main.online_friends() if main else 0
				it.call("set_count", str(n) if n > 0 else "")
			"system":
				it.set("dot", _doktor_dot())
	# Die Zahl der Freunde kann breiter werden: Abstand neu.
	_fit_tabs()
	if is_instance_valid(_glocke_punkt):
		_glocke_punkt.visible = Toasts.unread > 0


## Steht die Auswahl gerade auf der Reiterzeile?
func _auf_reitern() -> bool:
	var f := Nav.focused()
	return f != null and is_instance_valid(_tabs_row) and _tabs_row.is_ancestor_of(f)


## Die Auswahl auf den gewählten Reiter (nach einem Wechsel von dort aus bleibt sie in der Zeile).
func _reiter_fokus() -> void:
	for it in _tabs_row.get_children():
		if str(it.get("id")) == tab:
			Nav.focus(it as Control, true)
			return


func _show_tab(id: String, focus := true, dir := 0) -> void:
	var auf_reitern := _auf_reitern()
	tab = id
	_update_hints()
	for it in _tabs_row.get_children():
		it.call("set_on", str(it.get("id")) == id, focus and not _quiet)
	_move_indicator(focus and not _quiet and dir != 0)
	_tiles.clear()
	_voice_sig = ""
	_speaker_l = null
	_music_title = null
	_music_bar = null
	_music_next = null
	_lyrics_btn = null
	_play_btn = null
	_mini_box = null
	_mini_bar = null
	_mini_play = null
	_eq = null
	_mic_btn = null
	_mic_cap = null
	_dl_row = null
	_reveal.clear()
	_clear_strip(dir)
	var old: Control = _content.get_meta("uz_page") if is_instance_valid(_content) and _content.has_meta("uz_page") else null
	_content = _new_page()
	match id:
		"spiel": _tab_game()
		"discord": _tab_discord()
		"musik": _tab_music()
		"freunde": _tab_friends()
		"system": _tab_system()
		"pip": GuidePip.fill(self)
		"ton": GuideTon.fill(self)
	_retire(old, dir)
	var page: Control = _content.get_meta("uz_page")
	if _quiet:
		# Neuaufbau wegen neuer Daten: nur, was neu dazukam, blendet weich nach.
		_nachblenden()
		return
	# Reiterwechsel kreuzt (docs/DESIGN.md › Bewegung): der alte Inhalt geht sofort W_ORT zur
	# Gegenseite und kreuzt (_retire), der neue kommt NACH_WEG später aus der Richtung des Wechsels
	# mit „Ankommen“ – kein Leerbild, zusammen decken beide in jedem Bild. Die Teile gestaffelt.
	page.modulate.a = 0.0
	if dir != 0:
		U.slide_x(page, U.weg_px(U.W_ORT) * dir, U.T_ORT)
	var verz := U.NACH_WEG if dir != 0 else U.NACH_FLAECHE
	U.ankommen(page, U.T_ORT, "uz_fade").tween_property(page, "modulate:a", 1.0, U.T_ORT).set_delay(verz)
	if is_instance_valid(_strip):
		# Die Schnellleiste kommt mit der Seite, als Letztes der Staffel.
		_strip.modulate.a = 0.0
		U.ankommen(_strip, U.T_ORT, "uz_fade").tween_property(_strip, "modulate:a", 1.0, U.T_ORT).set_delay(verz + U.staffel(U.STAFFEL_MAX))
	_play_reveal(verz)
	if auf_reitern:
		_reiter_fokus()
	elif focus:
		_focus_default()


## Eine Seite für einen Reiter: rollt mit der Auswahl (oben und unten laufen die Zeilen weich
## aus, sobald es weitergeht). Der Inhalt hat links und rechts PAD_X Rand – dort darf der Cursor
## über die Zeilen ragen.
func _new_page() -> VBoxContainer:
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(frame)
	_holder.add_child(frame)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 64.0)
	U.full_rect(sc)
	frame.add_child(sc)
	_edge_fades(frame, sc)
	var pad := U.margin(PAD_X, 8, PAD_X, 16)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(pad)
	var col := U.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(col)
	col.set_meta("uz_page", frame)
	return col


## Alter Inhalt geht sofort W_ORT zur Gegenseite (ease-out) und kreuzt: er hält ein Bild
## (NACH_WEG) und blendet dann sine in-out in T_WEG aus (U.kreuz_aus), während der neue im selben
## Bild ankommt – nie ein dunkles Zwinkern zwischen zwei Reitern.
func _retire(old: Control, dir: int) -> void:
	if not is_instance_valid(old):
		return
	old.set_meta("uz_skip", true)
	if dir == 0 or _quiet:
		old.queue_free()
		return
	var slide: Variant = old.get_meta("uz_slide") if old.has_meta("uz_slide") else null
	if slide is Tween and (slide as Tween).is_valid():
		(slide as Tween).kill()
	var tw := U.weg(old, "uz_out").set_parallel(true)
	U.kreuz_aus(tw, old)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(old):
			old.offset_left = v
			old.offset_right = v
	, old.offset_left, -U.weg_px(U.W_ORT) * dir, U.T_WEG).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(old.queue_free)


## Teile eines Reiters erscheinen nacheinander (gestaffelt, höchstens STAFFEL_MAX Glieder): nur die
## Deckkraft – die Lage gehört dem Container, Schrift wird nie skaliert.
func _play_reveal(base: float) -> void:
	var list := _reveal.duplicate()
	_reveal.clear()
	for c in list:
		if is_instance_valid(c):
			(c as Control).modulate.a = 0.0
	await get_tree().process_frame
	var i := 0
	for c in list:
		if not is_instance_valid(c):
			continue
		var n := c as Control
		var d := base + U.staffel(i)
		i += 1
		var tw := U.ankommen(n, U.T_ORT, "uz_casc").set_parallel(true)
		tw.tween_property(n, "modulate:a", 1.0, U.T_ORT).set_delay(d)


## Leiser Neuaufbau (neue Daten kamen: Erfolge bekannt, Download, Freund, Mitteilung): was es vor
## dem Neuaufbau schon gab, steht sofort da, wie es stand; was neu dazukam – an seinen Schlüsseln
## (uz_key) erkannt, siehe _rebuild_keep –, blendet weich nach, gestaffelt, mit „Ankommen“ in T_ORT.
func _nachblenden() -> void:
	var list := _reveal.duplicate()
	_reveal.clear()
	if _old_keys.is_empty():
		return
	var i := 0
	for c in list:
		if not is_instance_valid(c):
			continue
		var keys := _keys_in(c)
		if keys.is_empty() or keys.any(func(k: String) -> bool: return _old_keys.has(k)):
			continue
		var n := c as Control
		n.modulate.a = 0.0
		U.ankommen(n, U.T_ORT, "uz_nach").tween_property(n, "modulate:a", 1.0, U.T_ORT).set_delay(U.staffel(i))
		i += 1


## Alle Schlüssel (uz_key) an c und darunter.
static func _keys_in(c: Node) -> Array:
	var out: Array = []
	if c.has_meta("uz_key"):
		out.append(str(c.get_meta("uz_key")))
	for ch in c.get_children():
		out.append_array(_keys_in(ch))
	return out


func _step_tab(d: int) -> void:
	var ids := _tabs().map(func(t): return str(t[0]))
	var i := ids.find(tab)
	Sfx.play("tab")
	_show_tab(ids[(i + d + ids.size()) % ids.size()], true, d)


## Hinweise je Reiter (höchstens vier, je ein Wort): im Spiel Y Bildschirmfoto (im Start zeigt die
## Zeile X), in Musik X nächster Titel und Y suchen.
func _update_hints() -> void:
	var h: Array = []
	if tab == "musik" and Music.mode() != "aus" and not _ohne_ordner():
		h.append(["x", "Nächster"])
		if Music.has_spotify() and not Music.local_on():
			h.append(["y", "Suchen"])
	elif _can_screenshot() and tab != "spiel":
		h.append(["y", "Foto"])
	var key := str(h)
	if key == _hints_key:
		return
	_hints_key = key
	set_meta("uz_hints", h)
	if is_inside_tree() and Nav.top_layer() == self:
		Nav.focus_moved.emit(Nav.focused())


# --- Start: Kontext, Neues, Musik, Freunde, Schnellleiste ---------------------------------------

## Unten im Start, in jeder Lage gleich (docs/PLAN_GUIDE3.md): ein schwacher Controller-Akku
## direkt (echtes Problem), dann „Mehr …“ unter den Zeilen der Lage (klappt an Ort und Stelle auf,
## nur ab zwei Zeilen) und im Spiel „Weitere Aktionen“ als eigene Zeile. Dann, nur wenn es
## Inhalt gibt: Kontext zum Spiel (Erfolge mit dem nächsten, die neueste Aufnahme) und Neues (neue
## Mitteilungen, Downloads), was läuft (Musik mit Steuerung), und
## ganz unten die Schnellleiste: Mikro, Lautstärke, Controller, Ruhemodus, Ausschalten mit einem
## Druck (guide_start.gd). Lautstärke und Mikro stehen darum nicht mehr unter „Mehr …“.
func _start_tail() -> void:
	if not is_instance_valid(_start_list):
		_start_list = _list()
		_content.add_child(_start_list)
	var pr := _pads_row(true)
	if pr:
		_start_list.add_child(_rv(pr))
	var rows: Array = []
	var last: Array = []
	for r in _start_more:
		(last if (r as Control).has_meta("uz_fold_last") else rows).append(r)
	# Eine Klappe „Mehr …“ nur ab zwei Zeilen; eine einzelne steht direkt da. „Weitere Aktionen“
	# (öffnet selbst die Seitenleiste) steht nie in der Klappe – „Mehr … · Alle Aktionen“ war doppelt.
	if rows.size() >= 2:
		_start_list.add_child(_rv(_fold("start", rows)))
	else:
		for r in rows:
			_start_list.add_child(_rv(r))
	for r in last:
		_start_list.add_child(_rv(r))
	_start_more = []
	# Nichts in der Liste (Video ohne Werkzeuge, kein Windows): auch keine Linie darüber.
	if _start_list.get_child_count() == 0:
		var i := _start_list.get_index()
		var prev: Node = _content.get_child(i - 1) if i > 0 else null
		if prev and prev.has_meta("uz_linie"):
			prev.queue_free()
		_start_list.queue_free()
	var ctx: Array = GuideStart.context_rows(self) + GuideStart.news_rows(self)
	if not ctx.is_empty():
		_content.add_child(_divider(14))
		var cl := _list()
		cl.set_meta("uz_group", "guide:kontext")
		_content.add_child(cl)
		for r in ctx:
			cl.add_child(_rv(r))
	if Music.mode() != "aus" and not Music.now.is_empty():
		_content.add_child(_divider(14))
		_content.add_child(_rv(_music_block()))
	# Friends are not listed in the start tab: the Friends tab is right next to it.
	_set_strip(GuideStart.quick_strip(self))


## Die Schnellleiste steht fest unten in der Leiste, über den Tastenhinweisen (wie die Symbolreihe
## im Kontrollzentrum der PS5): immer zu sehen, egal wie weit die Liste rollt; die Liste endet
## darüber. Beim Reiterwechsel kommt und geht sie mit der Seite (_show_tab, _clear_strip).
func _set_strip(s: Control) -> void:
	_strip = s
	s.anchor_top = 1.0
	s.anchor_bottom = 1.0
	s.anchor_right = 1.0
	s.offset_left = PAD_X
	s.offset_right = -PAD_X
	s.offset_top = -FOOT_H - GuideStart.STRIP_H
	s.offset_bottom = -FOOT_H
	_panel.add_child(s)
	_panel.move_child(s, _foot.get_index())
	_holder.offset_bottom = -FOOT_H - GuideStart.STRIP_H
	if is_instance_valid(_vol_hud):
		_vol_hud.offset_bottom = -FOOT_H - GuideStart.STRIP_H + 4.0


## Schnellleiste weg (anderer Reiter, Neuaufbau): beim Reiterwechsel kreuzt sie mit der Seite,
## sonst sofort; die Liste bekommt den Platz zurück.
func _clear_strip(dir: int) -> void:
	if is_instance_valid(_holder):
		_holder.offset_bottom = -FOOT_H
	if is_instance_valid(_vol_hud):
		_vol_hud.offset_bottom = -84
	if not is_instance_valid(_strip):
		_strip = null
		return
	var old := _strip
	_strip = null
	old.set_meta("uz_skip", true)
	if dir == 0 or _quiet:
		old.queue_free()
		return
	var tw := U.weg(old, "uz_out")
	U.kreuz_aus(tw, old)
	tw.chain().tween_callback(old.queue_free)


## Musik im Start: kleines Cover, Titel, „Künstler · Spotify“, rechts ⏮ ⏯ ⏭ (links/rechts
## wandert zwischen ihnen, X pausiert auch hier nicht – X ist im Start das Bildschirmfoto),
## darunter der Fortschritt mit beiden Zeiten. Cover und Titel sind anwählbar: A öffnet „Jetzt
## läuft“ groß (jetzt_laeuft.gd).
func _music_block() -> Control:
	_mini_box = U.vbox(8)
	var row := U.hbox(14)
	row.set_meta("uz_group", "guide:minimusic")
	row.set_meta("uz_row", true)
	row.set_meta("uz_mem", true)
	_mini_box.add_child(row)
	var link := _JetztZeile.new()
	link.set_meta("uz_key", "mm:gross")
	link.set_meta("uz_hint_a", "Groß anzeigen")
	link.picked.connect(func() -> void: JetztLaeuft.zeigen(main))
	row.add_child(link)
	var art := Panel.new()
	art.custom_minimum_size = Vector2(48, 48)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), 2))
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mic := U.icon("music", 20, "faint")
	mic.position = Vector2(14, 14)
	art.add_child(mic)
	_mini_art = TextureRect.new()
	_mini_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mini_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_mini_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_mini_art)
	art.add_child(_mini_art)
	link.add_child(art)
	var col := U.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	link.add_child(col)
	_mini_title = U.ellipsis(U.label("", "20", "text", "ui_bold"))
	_mini_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_mini_title)
	_mini_artist = U.ellipsis(U.label("", "16", "muted", "regular"))
	_mini_artist.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_mini_artist)
	var ctl := U.hbox(4)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ctl)
	var prev := _round("prev", 44)
	prev.set_meta("uz_key", "mm:prev")
	prev.set_meta("uz_hint_a", "Zurück")
	prev.pressed.connect(func() -> void: Music.previous())
	ctl.add_child(prev)
	_mini_play = _round("pause" if bool(Music.now.get("playing", false)) else "play", 44)
	_mini_play.set_meta("uz_key", "mm:play")
	_mini_play.set_meta("uz_hint_a", "Pause")
	_mini_play.set_meta("uz_entry", true)
	_mini_play.pressed.connect(func() -> void:
		Music.play_pause()
		_refresh_music()
	)
	ctl.add_child(_mini_play)
	var nxt := _round("next", 44)
	nxt.set_meta("uz_key", "mm:next")
	nxt.set_meta("uz_hint_a", "Weiter")
	nxt.pressed.connect(func() -> void: Music.next())
	ctl.add_child(nxt)
	var times := U.hbox(12)
	_mini_box.add_child(times)
	_mini_time = U.label("", "cap", "muted", "medium")
	_mini_time.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # läuft jede Sekunde weiter: nur Zahlen
	_mini_time.clip_text = false
	_mini_time.custom_minimum_size.x = 44
	times.add_child(_mini_time)
	_mini_bar = ProgressBarUz.new().setup(0.0, "accent", 2, 0)
	_mini_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mini_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	times.add_child(_mini_bar)
	_mini_total = U.label("", "cap", "muted", "medium")
	_mini_total.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_mini_total.clip_text = false
	_mini_total.custom_minimum_size.x = 44
	_mini_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	times.add_child(_mini_total)
	_art_url = ""
	return _mini_box


## Ist der Akku dieses Controllers schwach (≤ 20 % bzw. fast leer, nicht am Kabel, lädt nicht)?
static func pad_low(p: Dictionary) -> bool:
	if str(p.get("power", "")) == "wired" or bool(p.get("charging", false)):
		return false
	var pct := int(p.get("pct", -1))
	if pct >= 0:
		return pct <= LOW_PCT
	return int(p.get("level", -1)) == 0


## Controller-Zeile: low_only – nur, wenn ein Akku schwach ist (steht dann direkt da); sonst,
## sobald einer verbunden ist (unter „Mehr …“). A: der eine Controller bzw. alle.
func _pads_row(low_only: bool) -> Control:
	var pads: Array = Pads.pads
	var any_low := pads.any(func(p): return pad_low(p))
	if pads.is_empty() or (low_only and not any_low):
		return null
	var box := U.hbox(8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PadBattery.fill(box, pads, 15.0)
	if box.get_child_count() > 0:
		box.get_child(0).queue_free()          # das Controller-Symbol steht schon vorn
	var low := pads.filter(func(p): return pad_low(p))
	var r = GuideRow.new().setup("Controller", "controller", tr("Akku schwach") if not low.is_empty() else (tr("%d verbunden") % pads.size() if pads.size() > 1 else ""))
	r.value_color = "warn" if not low.is_empty() else "muted"
	r.trail = box
	r.chevron = true
	r.set_meta("uz_key", "s:pads")
	r.activated.connect(func() -> void:
		if pads.size() == 1:
			GuidePads.open_pad(main, pads[0])
		else:
			GuidePads.open_all(main)
	)
	return r


## Mikro umgeschaltet (Windows oder Discord): der Knopf in der Schnellleiste lebt mit.
func _on_mic(_muted: bool) -> void:
	GuideStart.set_mic_state(self, GuideStart.mic_muted())
	_mikro_neu()


## Download kam dazu, läuft weiter oder wurde fertig: die Zeile im Start nachführen; gibt es noch
## keine (neuer Download), baut der Start leise neu.
func _on_installs(_id: String) -> void:
	if tab != "spiel":
		return
	if is_instance_valid(_dl_row):
		GuideStart.update_downloads(self)
	else:
		_rebuild_soon()


## Controller kamen, gingen oder der Akku änderte sich: nur dann neu bauen (Pads meldet öfter).
func _on_pads() -> void:
	var sig := JSON.stringify(Pads.pads.map(func(p): return [str(p.get("key", "")), int(p.get("pct", -1)), int(p.get("level", -1)),
		bool(p.get("charging", false)), str(p.get("power", ""))]))
	if sig == _pads_sig:
		return
	var first := _pads_sig == ""
	_pads_sig = sig
	if not first and (tab == "spiel" or tab == "system"):
		_rebuild_soon()


# --- Neuaufbau bei neuen Daten -------------------------------------------------------------

func _on_social(_what: String) -> void:
	_update_tab_dots()
	if (tab == "freunde" and _people_changed()) or (tab == "spiel" and Launcher.in_game):
		_rebuild_soon()


## Ungelesenes oder Discord-Freunde (online, spielt …) haben sich geändert.
func _on_unread() -> void:
	_update_tab_dots()
	if tab == "freunde" and _people_changed():
		_rebuild_soon()


## Hat sich an der Liste etwas geändert, das man sieht (wer da ist, Status, Spiel, Ungelesenes)?
## Sonst kein Neuaufbau – jede Meldung (auch Nachrichten-Zähler anderer Leute) baute neu.
func _people_changed() -> bool:
	return _people_sig == "" or _people_key(_people_now()) != _people_sig


static func _people_key(list: Array) -> String:
	return JSON.stringify(list.map(func(e): return [str(e.get("key", "")), str(e.get("name", "")), str(e.get("avatar", "")),
		str(e.get("state", "")), str(e.get("game", "")), str(e.get("join_url", "")), str(e.get("voice", "")), int(e.get("unread", 0)),
		bool(e.get("with_me", false)), int(e.get("rank", 0))]))


func _on_music_lists(what: String) -> void:
	if what == "queue":
		_refresh_music()


## Spotify und eigene Musik: die andere Quelle spielt jetzt – Steuerung, Wege und Tasten passen sich an.
func _on_quelle() -> void:
	_update_hints()
	if tab == "musik":
		var f := Nav.focused()
		_rebuild_keep(str(f.get_meta("uz_key", "")) if f != null and is_ancestor_of(f) else "")


func _on_achievements(what: String) -> void:
	if tab == "spiel" and Launcher.in_game and what == "game:" + str(Launcher.current.get("id", "")):
		_rebuild_soon()


# --- Laufend auffrischen (Uhr, Musikbalken, Sitzung) ---------------------------------------------

func _process(_dt: float) -> void:
	if _dirty and Nav.top_layer() == self and not _closing:
		_dirty = false
		_rebuild_soon()
	if Engine.get_process_frames() % 15 != 0:
		return
	if not Music.now.is_empty():
		var d := maxf(float(Music.now.get("duration", 1)), 1.0)
		var p := float(Music.progress_ms())
		for b in [_music_bar, _mini_bar]:
			if b and is_instance_valid(b):
				b.set_value(p / d)
		for l in [_music_time, _mini_time]:
			if is_instance_valid(l):
				(l as Label).text = _mmss(Music.progress_ms())
	if is_instance_valid(_clock):
		_clock.text = U.clock()
	_tick_session()


# --- Freunde -------------------------------------------------------------------------------

## Alle, die gerade da sind (Steam, Discord-Server, dein Sprachkanal), jede Person einmal.
func _people_now() -> Array:
	var appid := ""
	var title := ""
	if Launcher.in_game:
		var g: Dictionary = Launcher.current
		if str(g.get("source", "")) == "steam" and int(g.get("appid", 0)) > 0:
			appid = str(int(g.get("appid", 0)))
		title = Library.display_title(g)
	var voice: Array = []
	if Voice.in_channel():
		for m in Voice.members:
			var d: Dictionary = (m as Dictionary).duplicate()
			if str(d.get("game", "")) == "":
				d["game"] = Voice.activity(m)
			voice.append(d)
	return People.build(Social.steam_friends, Social.discord, voice, str(Voice.channel.get("id", "")) if Voice.in_channel() else "", SteamChat.unread, appid,
			title, DiscordChat.friends, DiscordChat.unread, SteamChat.last_at, DiscordChat.last_at)


## Spieltitel, wie er in deiner Bibliothek heißt (Steam meldet „ELDEN RING“).
func _lib_title(e: Dictionary) -> String:
	var gid := str(e.get("game_id", ""))
	if gid == "":
		return ""
	var g := Library.get_game("steam:" + gid)
	return Library.display_title(g) if not g.is_empty() else ""


## Eine Person als Zeile: A Menü, X Nachricht (Steam), Y beitreten (offene Lobby, kein anderes
## Spiel läuft) – ein Druck statt durchs Menü.
func _friend_row(e: Dictionary, compact: bool, mixed := false) -> Control:
	var fr = FriendRow.new()
	fr.entry = e
	fr.compact = compact
	fr.show_source = mixed
	fr.game_title = _lib_title(e)
	fr.set_meta("uz_hint_a", "Optionen")
	var sf: Dictionary = e.get("steam", {})
	if not sf.is_empty():
		fr.set_meta("uz_hint_x", "Nachricht")
		fr.set_meta("uz_on_x", func() -> void: main.open_chat(sf))
	var url := str(e.get("join_url", ""))
	if url != "" and not Launcher.in_game:
		fr.set_meta("uz_hint_y", "Beitreten")
		fr.set_meta("uz_on_y", func() -> void:
			close()
			var jf := sf.duplicate()
			if jf.is_empty():
				jf = { "name": str(e.get("name", "")), "game_id": str(e.get("game_id", "")), "game": str(e.get("game", "")) }
			main.join_game(jf, url)
		)
	fr.chosen.connect(_open_friend.bind(fr))
	return fr


## Reiter Freunde: Kopf „Freunde“ mit der Zahl aller, darunter die Abschnitte Im Spiel, Online,
## Abwesend (je gezählt, guide_people.gd). Steam und Discord stehen zusammen; in gemischten Listen
## trägt jede Zeile rechts das Zeichen ihrer Quelle. Online und Abwesend zeigen erst ONLINE_MAX,
## der Rest klappt mit „N weitere“ auf. Ganz unten „Alle Freunde“ (außer im Spiel).
func _tab_friends() -> void:
	var list := _people_now()
	_people_sig = _people_key(list)
	var has_social := Social.has_steam() or not Social.servers().is_empty() or Voice.in_channel() or DiscordChat.logged_in()
	var total := Social.steam_friends.size() + (DiscordChat.friends.size() if DiscordChat.logged_in() else 0)
	_content.add_child(_heading("Freunde", str(total) if total > 0 else ""))
	_content.add_child(U.spacer(0, 14, false))
	if list.is_empty():
		if has_social:
			_content.add_child(_rv(U.label("Gerade ist niemand online.", "s", "muted", "regular", true)))
			return
		# Noch kein Konto: die schmale Bühne mit angedeuteten Personen, darunter ein Druck zur
		# Anmeldung (QR-Code mit der Steam-App bzw. Freigabe in der Discord-App). Im Spiel käme die
		# Anmeldung hinter dem Spiel heraus: dann nur die Bühne.
		_content.add_child(_rv(LeerBuehneG.new().setup({ "art": "personen", "symbol": "friends", "schmal": true,
			"titel": "Noch kein Konto verbunden." })))
		if not Launcher.in_game and not Video.active:
			_content.add_child(U.spacer(0, 12, false))
			var b := _act("Steam verbinden", "steam", func() -> void:
				close()
				LeerBuehneG.weg(main, "steam").call())
			b.set_meta("uz_default", true)
			_content.add_child(_rv(b))
			_content.add_child(_rv(_act("Discord verbinden", "discord", func() -> void:
				close()
				LeerBuehneG.weg(main, "discord").call())))
		return
	var mixed := People.mixed(list)
	var i := 0
	for s in People.sections(list):
		var items: Array = s.items
		if i > 0:
			_content.add_child(U.spacer(0, 16, false))
		_content.add_child(_section(str(s.title), str(items.size())))
		_content.add_child(U.spacer(0, 4, false))
		var col := _list()
		col.set_meta("uz_group", "guide:fr:" + str(s.id))
		_content.add_child(col)
		var sid := str(s.id)
		var foldable := sid == "online" or sid == "abwesend"
		var shown := items if (not foldable or _fr_open.has(sid) or items.size() <= ONLINE_MAX + 1) else items.slice(0, ONLINE_MAX)
		for e in shown:
			var fr := _friend_row(e, false, mixed)
			if i == 0:
				fr.set_meta("uz_default", true)
			col.add_child(fr)
			if i < 14:
				_rv(fr)
			i += 1
		if shown.size() < items.size():
			var rest := items.size() - shown.size()
			var more = GuideRow.new().setup(tr("%d weitere online" if sid == "online" else "%d weitere") % rest, "plus")
			more.set_meta("uz_key", "fr:more:" + sid)
			more.set_meta("uz_hint_a", "Anzeigen")
			var next_key := "fr:" + str((items[shown.size()] as Dictionary).get("key", ""))
			more.activated.connect(func() -> void:
				_fr_open[sid] = true
				_rebuild_keep(next_key)     # die Auswahl steht gleich auf dem ersten neuen
			)
			col.add_child(_rv(more))
	# Im Spiel läge die Freunde-Seite hinter dem Spiel: dort reicht die Liste.
	if not Launcher.in_game and not Video.active:
		_content.add_child(_divider(16))
		var all := _act("Alle Freunde", "friends", func() -> void:
			close()
			main.goto("friends"), "", str(total) if total > 0 else "")
		all.set("chevron", true)
		all.set_meta("uz_key", "f:all")
		_content.add_child(_rv(all))


# --- System --------------------------------------------------------------------------------

## Reiter System, kurz – nur, was man im Spiel braucht: „Mitteilungen“ (mit der Zahl; die neuen
## stehen einzeln im Start), der Uzai-Doktor und der Controller nur bei einem echten Problem
## (Wichtiges kaputt, Akku schwach), Profil wechseln, Alle Einstellungen (nicht im Spiel – die
## Seite läge hinter dem Spiel), „Mehr …“ und Ausschalten. Unter „Mehr …“ (klappt an Ort und Stelle
## auf, auch im Spiel): Bild & Ton, Maus mit dem Controller, Aufnahmen, Kacheln im Guide,
## Uzai-Doktor, Controller – alles davon steht auch in den Einstellungen. Lautstärke, Mikro und
## Downloads stehen im Start (Schnellleiste bzw. Neues), nicht hier.
func _tab_system() -> void:
	var list := _list()
	list.set_meta("uz_group", "guide:system")
	_content.add_child(list)
	# Mitteilungen stehen als Glocke oben im Kopf (_build_top).
	# Uzai-Doktor (Punkt 133): vorn nur, wenn etwas Wichtiges kaputt ist (Warnfarbe), sonst unter „Mehr …“.
	var dk := Doktor.summary(Doktor.cards(DoktorLage.cached()))
	var doc := _act("Uzai-Doktor", "pulse", func() -> void: main.open_doktor(), "", str(dk.text))
	doc.set("chevron", true)
	var more: Array = []
	if int(dk.wichtig) > 0:
		doc.set("value_color", "warn")
		list.add_child(_rv(doc))
	# Controller wie im Xbox-Guide (A: Spieler, Akku, vibrieren, testen, ausschalten): vorn nur mit
	# schwachem Akku.
	var pad_warn := _pads_row(true)
	if pad_warn:
		list.add_child(_rv(pad_warn))
	# Profile (Roadmap 109): „Wer spielt?“ – ein anderes Profil startet Uzai mit dessen Daten neu.
	list.add_child(_rv(_act("Profil wechseln", "user", func() -> void: main.open_profiles("switch"))))
	if not Launcher.in_game and not Video.active:
		list.add_child(_rv(_act("Alle Einstellungen", "settings", func() -> void:
			close()
			main.goto("settings")
		)))
	if Config.is_windows() or Library.demo:
		# Bild & Ton (Roadmap 4/16): Tonausgabe, Auflösung, Hz und HDR – auch über dem Spiel.
		more.append(_act("Bild & Ton", "monitor", func() -> void: main.open_bild_ton()))
		var mouse = GuideRow.new().setup("Maus mit dem Controller", "controller")
		var on: bool = main.mouse_on
		mouse.switch_state = 1 if on else 0
		mouse.value = TranslationServer.translate("An" if on else "Aus")
		mouse.set_meta("uz_key", "a:Maus mit dem Controller")
		var flip := func(_d: int = 0) -> void: main.set_mouse_mode(not main.mouse_on)
		mouse.activated.connect(flip)
		mouse.stepped.connect(flip)
		more.append(mouse)
	# Nicht stören (src/core/nicht_stoeren.gd): Pop-ups von Freunden, Discord und Shop nur still in
	# die Mitteilungen – wie die Kachel im Schnellmenü.
	var ruhe = GuideRow.new().setup("Nicht stören", "bell")
	ruhe.switch_state = 1 if NichtStoeren.an else 0
	ruhe.value = TranslationServer.translate(NichtStoeren.zustand() if NichtStoeren.zustand() != "" else "Aus")
	ruhe.set_meta("uz_key", "a:Nicht stören")
	var ruhe_flip := func(_d: int = 0) -> void:
		NichtStoeren.umschalten()
		_rebuild_soon()
	ruhe.activated.connect(ruhe_flip)
	ruhe.stepped.connect(ruhe_flip)
	more.append(ruhe)
	var caps: Array = Capture.latest(0)
	var cap := _act("Aufnahmen", "video", func() -> void: main.open_captures(), "", str(caps.size()) if not caps.is_empty() else "")
	cap.set("chevron", true)
	more.append(cap)
	# Eigene Zeilen im Start und „Passend zur Lage“ (dieselbe Seite wie in den Einstellungen).
	var ti := _act("Kacheln im Guide", "grid", func() -> void: GuideTiles.open(main, func() -> void: _rebuild_soon()), "", GuideTiles.summary())
	ti.set("chevron", true)
	more.append(ti)
	if int(dk.wichtig) <= 0:
		more.append(doc)
	if pad_warn == null:
		var pa := _pads_row(false)
		if pa:
			more.append(pa)
	var fold := _fold("system", more)
	if fold:
		list.add_child(_rv(fold))
	_content.add_child(_divider(16))
	var power := _act("Ausschalten", "power", func() -> void: main.open_power())
	_content.add_child(_rv(power))
	(list.get_child(0) as Control).set_meta("uz_default", true)


## Erst wenn das Abbild der Seite gezeichnet ist, nimmt der Guide die Auswahl: Sonst zeigte das Abbild
## schon, wie die Auswahl die Seite verlässt. Im üblichen Ablauf ist es das beim Aufruf schon (der Druck
## kommt in der Verarbeitung eines Bildes an, gezeichnet wird an dessen Ende) – gewartet wird nur, wenn der
## Guide zwischen zwei Bildern geöffnet wurde. Höchstens drei Bilder.
func _vor_dem_stapel() -> void:
	var n := 0
	while main and main.seite_im_bau() and n < 3 and is_inside_tree():
		n += 1
		await get_tree().process_frame


# --- Steuerung -----------------------------------------------------------------------------

func nav_command(cmd: String) -> bool:
	# Bild in Bild wird gerade verschoben: B setzt zurück, LT/RT ändern die Größe.
	if GuidePip.command(self, cmd):
		return true
	# Schnellmenü anpassen: B legt eine gegriffene Kachel ab bzw. speichert (guide_quick.gd).
	if start_tab == QUICK and GuideQuick.command(self, cmd):
		return true
	if cmd == "b":
		close()
		return true
	return super(cmd)


## Richtungen gehören beim Verschieben (Bild in Bild, gegriffene Kachel im Schnellmenü) dem
## Verschieben, nicht der Auswahl.
func nav_dir(dir: String) -> bool:
	if start_tab == QUICK and GuideQuick.nav_dir(self, dir):
		return true
	if GuidePip.nav_dir(self, dir):
		return true
	return _pin_dir(dir)


## Reiter samt „Bild in Bild“ und „Video-Ton“, solange sie laufen.
func _tabs() -> Array:
	return GuideTon.tabs(GuidePip.tabs(TABS, main))


func handle(cmd: String) -> bool:
	if start_tab == QUICK:
		return GuideQuick.handle(self, cmd)
	match cmd:
		"lb":
			_step_tab(-1)
			return true
		"rb":
			_step_tab(1)
			return true
		"x":
			# Im Start (im Spiel bzw. Video) steht X an „Bildschirmfoto“.
			if tab == "spiel" and _can_screenshot():
				Sfx.play("select")
				main.take_screenshot()
				return true
			if tab == "musik" and Music.mode() != "aus":
				Music.next()
				return true
			if Music.mode() == "aus":
				return true
			var was := bool(Music.now.get("playing", false))
			Music.play_pause()
			Toasts.show_toast("Musik pausiert" if was else "Musik läuft weiter", str(Music.now.get("title", "")), "pause" if was else "play",
					{ "ms": 1200, "quiet": true })
			return true
		"lt":
			volume_step(-1)
			return true
		"rt":
			volume_step(1)
			return true
		"y":
			if tab == "musik" and Music.has_spotify() and not Music.local_on() and Music.mode() != "aus":
				MusicBits.open_search(main)
				return true
			# Wie bei Xbox und PS5: im Spiel oder Video macht Y aus dem Guide ein Bildschirmfoto.
			if _can_screenshot():
				Sfx.play("select")
				main.take_screenshot()
			return true
		"guide":
			# Nicht selbst schließen: main.toggle_guide erkennt die zweite Meldung derselben Taste
			# (Godot und Helfer). Schloss der Guide hier direkt, öffnete die Meldung des Helfers
			# ihn gleich wieder – „geht nicht immer weg“.
			return false
	return false


# --- Zeichnen: Kopf, Reiter, Freunde im Start, Kante -------------------------------------------

## Musik im Start: Cover und Titel als eine Zeile, anwählbar wie jede Zeile im Guide (die helle
## Fläche darunter im Cursor-Takt). A öffnet „Jetzt läuft“ groß.
class _JetztZeile extends HBoxContainer:
	signal picked
	const UU := preload("res://src/ui/u.gd")
	const PAD := Vector2(10, 6)

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 14)

	func _ready() -> void:
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

	func activate() -> void:
		picked.emit()

	func _draw() -> void:
		UU.draw_focus(self, 12, Rect2(-PAD, size + PAD * 2.0))


## Du oben in der Leiste: Bild mit Zustand, Name, „● Online · Level 34“. A öffnet „Dein Status“.
class _MeCard extends Control:
	signal chosen
	const UU := preload("res://src/ui/u.gd")
	const Av := preload("res://src/ui/components/avatar.gd")
	const MS := preload("res://src/core/my_status.gd")
	const Row := preload("res://src/ui/components/guide_row.gd")
	var hold := false:
		set(v):
			hold = v
			_focus_to(v or has_focus())
	var _f := 0.0
	var _m: MarginContainer
	var _breit := 0.0             ## so breit wäre die Karte ungekürzt (die Auswahl liegt nur darum)

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_meta("uz_key", "me:card")
		set_meta("uz_hint_a", "Status")
		_build()
		focus_entered.connect(_focus_to.bind(true))
		focus_exited.connect(func() -> void: _focus_to(hold))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func _build() -> void:
		_m = UU.margin(0, 2, 8, 2)
		_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_m)
		var row := UU.hbox(14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_m.add_child(row)
		var p := MS.profile()
		var hs := MS.has_steam()
		var hd := MS.has_discord()
		var st := MS.overall(MS.steam_now() if hs else "", MS.discord_now() if hd else "", Launcher.in_game) if hs or hd else ""
		var av := Av.new()
		av.setup(str(p.name), str(p.avatar), "", 44)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(av)
		var col := UU.vbox(0)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var nl := UU.label(str(p.name), "20", "text", "ui_bold")
		nl.clip_text = false
		nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		col.add_child(nl)
		var line := UU.hbox(6)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(line)
		if st != "":
			var dot := _Dot.new()
			dot.on = st in ["online", "game"]
			line.add_child(dot)
			var sl := UU.label(MS.name_of(st) if st != "game" else "Online", "16", "muted", "regular")
			sl.clip_text = false
			line.add_child(sl)
		var lv := UU.label(("· " if st != "" else "") + TranslationServer.translate("Level %d") % Badges.level_number(), "16", "muted", "regular")
		lv.clip_text = false
		lv.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		line.add_child(lv)
		# Erst messen, wie breit alles ungekürzt wäre; dann dürfen Name und Level kürzen, und die
		# Karte füllt, was die Kopfzeile ihr lässt.
		var ganz := _m.get_combined_minimum_size()
		_breit = ganz.x
		UU.ellipsis(nl)
		UU.ellipsis(lv)
		UU.full_rect(_m)
		custom_minimum_size = Vector2(minf(ganz.x, 150.0), ganz.y)

	## Nach einer Änderung im Panel „Dein Status“ (my_profile.gd ruft refresh).
	func refresh() -> void:
		if is_instance_valid(_m):
			_m.queue_free()
		_build()

	func _focus_to(on: bool) -> void:
		UU.tw(self, "uz_cur").tween_method(func(v: float) -> void:
			_f = v
			queue_redraw()
		, _f, 1.0 if on else 0.0, UU.T_ANTWORT)

	func activate() -> void:
		chosen.emit()

	func _draw() -> void:
		Row.draw_cursor(self, Rect2(-10, -6, minf(size.x, _breit) + 20, size.y + 12), _f)


## Kleiner Punkt vor „Online“: grün nur für Präsenz, sonst leise.
class _Dot extends Control:
	var on := true

	func _ready() -> void:
		custom_minimum_size = Vector2(8, 8)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 4.0, UzTheme.col("ok") if on else UzTheme.col("faint"))


## Ein Reiter (LB/RB, Maus oder Steuerkreuz): gewählt hell und fett, sonst leise; „Freunde“ mit kleiner Zahl,
## dot für Neues (ungelesene Nachrichten, Mitteilungen) als kleines Quadrat. Nur der gewählte Reiter nimmt die
## Auswahl an: Von oben oder unten landet das Steuerkreuz so immer auf ihm; links/rechts wechselt den Reiter
## (schritt), runter oder A geht in den Inhalt (betreten).
class _TabPill extends Control:
	signal picked(id: String)
	signal schritt(d: int)
	signal betreten
	const UU := preload("res://src/ui/u.gd")
	var id := ""
	var text := ""
	var count := ""
	var pad := 12.0
	var fs := 20                ## Schriftgröße (kleiner nur, wenn die Reiter sonst nicht passen)
	var on := false
	var dot := false:
		set(v):
			if v != dot:
				dot = v
				queue_redraw()
	var _l: Label
	var _c: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_l = Label.new()
		_l.text = text
		_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # schon übersetzt (mit Kontext „tab“, _fill_tabs)
		_l.add_theme_font_override("font", UzTheme.ui("ui_bold"))
		_l.add_theme_font_size_override("font_size", fs)
		_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_l)
		_c = Label.new()
		_c.add_theme_font_override("font", UzTheme.font("medium"))
		_c.add_theme_font_size_override("font_size", 15)
		_c.add_theme_color_override("font_color", UzTheme.col("faint"))
		_c.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_c)
		set_count(count)
		set_on(on, false)
		focus_entered.connect(func() -> void: UU.etikett(self, true))
		focus_exited.connect(func() -> void: UU.etikett(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				picked.emit(id)
				accept_event()
		)

	func nav_lr(d: int) -> bool:
		schritt.emit(d)
		return true

	func nav_ud(d: int) -> bool:
		if d > 0:
			betreten.emit()
			return true
		return false

	func activate() -> void:
		betreten.emit()

	func set_count(c: String) -> void:
		count = c
		if _c == null:
			return
		_c.text = c
		var w := UzTheme.ui("ui_bold").get_string_size(TranslationServer.translate(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cw := UzTheme.font("medium").get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if c != "" else 0.0
		_l.position = Vector2(pad, 6.0 + (20 - fs) * 0.5)
		_c.position = Vector2(pad + w + 4, 12)
		custom_minimum_size = Vector2(w + pad * 2.0 + (cw + 4.0 if c != "" else 0.0), 44)

	## Abstand und Schrift setzen (Guide._fit_tabs).
	func fit(p: float, size_px: int) -> void:
		if p == pad and size_px == fs:
			return
		pad = p
		fs = size_px
		if _l:
			_l.add_theme_font_size_override("font_size", fs)
		set_count(count)

	## Breite von Wort und Zahl bei 20 px, ohne Rand (Guide._fit_tabs).
	func word_w() -> float:
		var w := UzTheme.ui("ui_bold").get_string_size(TranslationServer.translate(text), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		return w + (UzTheme.font("medium").get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 4.0 if count != "" else 0.0)

	## Wo das Wort steht (für den Strich darunter).
	func word_rect() -> Rect2:
		var w := UzTheme.ui("ui_bold").get_string_size(TranslationServer.translate(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		return Rect2(pad, 0, w, size.y)

	func set_on(v: bool, animate := true) -> void:
		on = v
		focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		queue_redraw()
		if _l == null:
			return
		# Eine noch laufende Überblendung der Auswahl (U.etikett) darf die neue Farbe nicht überschreiben.
		if _l.has_meta("uz_ctw"):
			var alt: Variant = _l.get_meta("uz_ctw")
			if alt is Tween and (alt as Tween).is_valid():
				(alt as Tween).kill()
			_l.remove_meta("uz_ctw")
		if _l.has_meta("uz_col"):
			_l.remove_meta("uz_col")
		var c := UzTheme.col("text") if on else UzTheme.col("muted")
		if animate:
			UU.tw(_l, "uz_farbe").tween_property(_l, "theme_override_colors/font_color", c, UU.T_ANTWORT)
		else:
			_l.add_theme_color_override("font_color", c)

	func _draw() -> void:
		UU.draw_focus(self, 12, Rect2(2, 5, size.x - 4, size.y - 12))
		if dot:
			draw_rect(Rect2(size.x - pad * 0.5 - 3.0, 8.0, 6.0, 6.0), UzTheme.col("accent"))


## Rechte Kante der Leiste: eine Haarlinie, die leicht in der Farbe des Spiels glimmt (in der Mitte
## am stärksten), dazu ein schmaler, weicher Schein nach außen. Sonst kein Schmuck.
class _Edge extends Control:
	var tint := Color.TRANSPARENT:
		set(v):
			tint = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if tint.a <= 0.0:
			tint = UzTheme.col("accent")

	func _draw() -> void:
		var h := size.y
		var c := Color(tint.lightened(0.15), 1.0)
		var steps := 24
		for i in steps:
			var y0 := h * i / steps
			var t := float(i) / (steps - 1)
			var a := 0.18 + 0.5 * sin(t * PI)
			draw_rect(Rect2(0, y0, 1, h / steps + 1.0), Color(c, a))
			for k in 3:
				draw_rect(Rect2(1 + k * 4, y0, 4, h / steps + 1.0), Color(c, a * 0.12 / (k + 1)))
		draw_rect(Rect2(0, 0, 1, h), Color(UzTheme.col("line"), 0.6))
