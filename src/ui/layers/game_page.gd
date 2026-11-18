extends "res://src/ui/layers/layer.gd"
## Die Seite eines Spiels, bevor es startet – wie auf einer Konsole: oben groß das Bild des Spiels
## (voll sichtbar, nichts Großes davor), links der Schriftzug bzw. Titel groß, darunter eine kleine
## Zeile (Schild der Quelle, Spielzeit · zuletzt, leiser Genre · Studio bzw. Emulator · Bild), dann
## die Knöpfe: Spielen hell vorn, Optionen, runde Symbolknöpfe (Favorit, Soundtrack). Rechts die
## Hülle (dorthin fliegt das Cover von der Startseite). Unter den Knöpfen kleine Pillen
## (src/ui/spielseite/buehne_chip.gd): Erfolge mit Ring, die Woche mit Mini-Säulen, Freunde, die es
## gerade spielen, Spielstände – nur, was es gibt; A tut, was früher die großen Karten taten.
## Dann ruhig: Erfolge (Symbole, Balken, „Als Nächstes“, Fast geschafft), Bilder, Aufnahmen, Letzte
## Runden, bei Steam Neuigkeiten, Erweiterungen, Bewertungen (dieselben Bausteine wie im Shop),
## Über das Spiel, Backlog, Deine Angaben, mehr für das System. X Favorit, B zurück, Y Optionen.
##
## Wie lange ein Spiel dauert (HowLongToBeat), steht nicht hier: Dafür gibt es keine offizielle
## Schnittstelle, und die Seite auszulesen wäre gegen ihre Regeln. Die Spielzeit ist gemessen.
##
## Rhythmus: Kopf mit Pillen, dann Abschnitte mit gleichem Abstand (Überschrift, Inhalt). Unten
## läuft die Seite in den Raum aus, damit die Tastenhinweise nie auf Inhalt stehen.

const Shelf := preload("res://src/ui/components/shelf.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const BG := preload("res://src/ui/components/background.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")
const VDF := preload("res://src/library/vdf.gd")
const RemotePlay := preload("res://src/core/remote_play.gd")
const InstallFlow := preload("res://src/ui/install_flow.gd")
const StorageFlow := preload("res://src/ui/storage_flow.gd")
const InstallParse := preload("res://src/core/install_parse.gd")
const QuickResume := preload("res://src/core/quick_resume.gd")
const Spielstaende := preload("res://src/ui/layers/spielstaende.gd")
const Spielklang := preload("res://src/core/spielklang.gd")
const CapturesUI := preload("res://src/ui/layers/captures.gd")
const Lang := preload("res://src/core/lang.gd")
const StoreGame := preload("res://src/ui/layers/store_game.gd")
const MusicBits := preload("res://src/ui/components/music_bits.gd")
const SessionSummary := preload("res://src/core/session_summary.gd")
const SessionChart := preload("res://src/ui/components/session_chart.gd")
const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const GameFields := preload("res://src/library/game_fields.gd")
const ChatLink := preload("res://src/ui/layers/chat_link.gd")
const Backlog := preload("res://src/library/backlog.gd")
const BacklogFlow := preload("res://src/ui/backlog_flow.gd")
const StarRow := preload("res://src/ui/components/star_row.gd")
const RetroSysteme := preload("res://src/core/retro_systeme.gd")
const Buehne := preload("res://src/ui/spielseite/buehne.gd")
const BuehneChip := preload("res://src/ui/spielseite/buehne_chip.gd")
const RetroBuehne := preload("res://src/ui/components/retro_buehne.gd")
const MediaS := preload("res://src/core/media.gd")
const Leicht := preload("res://src/core/leicht.gd")

const GUT := 96
const SECTION_GAP := 56     ## Luft über jedem Abschnitt
const HEAD_GAP := 18        ## zwischen Überschrift und Inhalt
const KOPF_OBEN := 150      ## Luft über dem Kopf: das Bild trägt die obere Hälfte der Seite
const PILLEN_GAP := 12      ## zwischen den Pillen unter den Knöpfen
const KNOPF_H := 60         ## Höhe der Knöpfe im Kopf
const RETRO_ABSTAND := 48.0 ## Retro-Bühne: Luft zur Hülle und zum Text
const RETRO_OBEN := 24.0    ## … und höchstens so weit nach oben (240 Zeilen passen zweifach)

var game: Dictionary = {}
const Main := preload("res://src/main.gd")
var main: Main
var _hero_mask: TextureRect
var _hero: TextureRect
var _logo: TextureRect
var _title: Label
var _col: VBoxContainer
var _shots_box: Control
var _ach_box: Control
var _about_box: Control
var _news_box: Control
var _dlc_box: Control
var _rv_box: Control
var _mine_box: Control         ## „Deine Angaben“ (Tags, Kategorie, Links …), folgt den Optionen
var _mine_sig := ""
var _bild_stand := -1           ## Media.bilder_stand beim Bau (Bildwahl, Spiele scrapen: Bilder neu)
var _backlog_box: Control      ## „Dein Backlog“ (Status, Sterne, Rezension, Tagebuch, Listen)
var _backlog_sig := ""
var _play: Control
var _shots: Array = []
var _shots_count: Label
var _shots_section: Control
var _shade: Control
var _inst_box: Control
var _inst_label: Label
var _inst_bar: Control
var _zeile1: Label             ## leise hinten: „·  PCSX2 · Bild: CRT“ bzw. „·  Genre · Studio“ (kommt mit dem Store)
var _zeile2: Label             ## vorn: „120 Std. gespielt · zuletzt heute · nicht installiert · 182 GB frei auf C:“
var _schild_w := 0.0           ## Breite des Schilds vorn in der Zeile
var _erfolge_pille: Control    ## Pille „Erfolge“ (füllt sich, sobald die Liste da ist)
var _pillen_row: HBoxContainer
var _pillen_v: VBoxContainer    ## Spalte, in der die Pillenreihe steht (für die Pille des Klangs, die später kommt)
var _pillen_platz := 0
var _fav_btn: Button           ## runder Favorit-Knopf (Herz), folgt auch X
var _ach_title: Label          ## Zeile unter den Erfolg-Symbolen: der gewählte bzw. nächste Erfolg
var _ach_desc: Label

var _hero_in := 0.0
var _sc: ScrollContainer       ## Bildlauf mit Titel, Knöpfen und Abschnitten (Schrift der Seite)
var _im_bau := false           ## Bilder kommen noch im Aufbau (vorab geladen): stehen sofort
var _hero_par := 1.0
var _cover: Control            ## Hülle im Kopf: Ziel des Covers, das von der Karte herfliegt (flug.gd)
var _head_row: HBoxContainer    ## Knöpfe im Kopf (rücken bei wenig Platz zusammen, _fit_head)
var _cover_w := 270.0           ## Breite der Hülle im Kopf (bei schmaler Oberfläche kleiner)
var _retro: Control             ## Retro-Bühne: die Spielszene als Bildschirm neben der Hülle (retro_buehne.gd)
var _retro_platz := false       ## Emulator-Spiel ohne großes Bild: Titel und Knöpfe lassen der Bühne Platz


func build() -> void:
	_im_bau = true
	_bauen()
	_im_bau = false
	# Klang des Spiels von iiDB, solange die Seite offen ist (nur mit Schlüssel und eingeschaltet).
	# Gibt es einen, zeigt ihn eine Pille mit kleiner Pegelanzeige; A schaltet ihn stumm.
	var klang := Spielklang.an(self, game)
	if klang:
		klang.connect("bereit", _pille_klang.bind(klang), CONNECT_ONE_SHOT)


## Seite (layer.gd): Sie selbst ist die deckende Fläche, der Bildlauf mit Titel und Knöpfen ihre
## Schrift – der Grund (Bild, Licht) kommt beim Öffnen zuerst, die Schrift danach: Der Titel der
## Startseite liegt dann schon unter der Fläche, wenn der neue kommt (nie Titel über Titel).
func flaeche() -> Control:
	return self


func schrift() -> Array:
	return [_sc] if is_instance_valid(_sc) else []


func _bauen() -> void:
	dim = 1.0
	set_meta("uz_flug", "g:" + str(game.get("id", "")))
	_scrim.color = Color(UzTheme.col("bg"), 1.0)
	set_meta("uz_hint_b", "Zurück")
	set_meta("uz_hint_y", "Optionen")
	set_meta("uz_hints", [["y", "Optionen"]])
	# Emulator-Spiel ohne eigenes großes Bild: Die Spielszene steht gleich als Bildschirm zwischen Text
	# und Hülle (Retro-Bühne). Der Kopf rechnet von Anfang an mit ihr – nichts rückt nachträglich.
	_retro_platz = str(game.get("source", "")) in ["rom", "disc"] and Media.local_path(game, "hero") == ""
	# Bild des Spiels groß im oberen Teil. Eine Verlaufsmaske lässt es nach unten weich in den
	# Raum auslaufen – ohne sichtbare Kante, auch bei hellen Bildern und beim Blättern.
	_hero_mask = TextureRect.new()
	_hero_mask.texture = _mask_tex()
	_hero_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_mask.stretch_mode = TextureRect.STRETCH_SCALE
	_hero_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_hero_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_mask.anchor_right = 1.0
	_hero_mask.offset_bottom = BG.page_hero_area(get_viewport_rect().size).y
	add_child(_hero_mask)
	_hero = TextureRect.new()
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_hero)
	_hero.modulate.a = 0.0
	_hero_mask.add_child(_hero)
	var shade := _Shade.new()
	shade.anchor_right = 1.0
	shade.offset_bottom = 830
	add_child(shade)
	_shade = shade
	var retro = RetroBuehne.new()
	retro.wechseln = true
	retro.anchor_right = 1.0
	retro.offset_bottom = BG.page_hero_area(get_viewport_rect().size).y + 120.0
	add_child(retro)
	_retro = retro
	# Lichtschein in der Farbe des Covers, sonst des Systems (auch ohne Bild nie ganz schwarz).
	var wshade: WeakRef = weakref(shade)
	var sys_col := Color(str(Config.system(str(game.get("system", ""))).get("color", "#3a4050")))
	Media.game_tint(game, func(c: Variant) -> void:
		var sh: Control = wshade.get_ref()
		if sh == null:
			return
		var col: Color = c if c is Color else sys_col
		var tw := sh.create_tween()
		tw.tween_method(func(a: float) -> void:
			var s2: Control = wshade.get_ref()
			if s2:
				s2.tint = Color(col, a)
				s2.queue_redraw()
		, 0.0, 1.0, U.T_LICHT).set_trans(Tween.TRANS_SINE)
	)
	# Das große Bild nur im sichtbaren Ausschnitt und in Schirmgröße (Media.fit_texture): kleiner
	# hochzuladen als der ganze Hero samt Mipmaps und in 1080p schärfer. Die Startseite lädt es
	# für das gewählte Spiel vorab (games.gd), die Seite hat es dann sofort.
	var hero_area := BG.page_hero_area(get_viewport_rect().size)
	var hero_cb := func(t: Texture2D) -> void:
		if t:
			_set_hero(t)
		else:
			Media.game_texture(game, "wide", func(t2: Texture2D) -> void:
				if t2:
					_set_hero(t2)
				elif game.get("source") in ["rom", "disc"]:
					# Emulator-Spiel (auch von der Disc): eine Szene aus dem Spiel. Groß und breit genug
					# (Wikipedia, RetroAchievements: hero_tauglich) trägt sie den Kopf wie ein Hero; sonst
					# steht sie ungeschnitten als Bildschirm auf der Retro-Bühne – nie gestreckt, nie beschnitten.
					Media.game_texture(game, "shot", func(t3: Texture2D) -> void:
						if t3 == null:
							_cover_glow()
						elif MediaS.hero_tauglich(MediaS.orig_groesse(t3)):
							Media.fit_texture(str(t3.get_meta("uz_src", "")), hero_area, func(t4: Texture2D) -> void:
								_set_hero(t4 if t4 else t3)
							)
						else:
							_retro_zeigen(t3)
					)
				else:
					_cover_glow()
			)
	Media.game_file(game, "hero", func(path: String) -> void:
		if hero_cb.is_valid() and path != "":   # die Seite kann schon zu sein, wenn die Antwort kommt
			Media.fit_texture(path, hero_area, hero_cb)
		elif hero_cb.is_valid():
			hero_cb.call(null)
	)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.set_meta("uz_pad_v", 230.0)
	U.full_rect(sc)
	add_child(sc)
	_sc = sc
	# Das Bild wandert beim Blättern halb so schnell mit (Tiefe) und blendet aus.
	sc.get_v_scroll_bar().value_changed.connect(func(v: float) -> void:
		var y := -v * 0.5
		if is_instance_valid(_hero_mask):
			_hero_mask.position.y = y
		if is_instance_valid(_shade):
			_shade.position.y = y
		if is_instance_valid(_retro):
			# Wandert ganz mit der Seite (halb so schnell stand sie hinter den Erfolgen), in ganzen Punkten.
			_retro.position.y = roundf(-v)
		_hero_par = clampf(1.0 - v / 900.0, 0.0, 1.0)
		if is_instance_valid(_retro):
			_retro.modulate.a = _hero_par
		if is_instance_valid(_hero):
			_hero.modulate.a = _hero_in * _hero_par
	)
	_col = U.vbox(0)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_col)
	_col.add_child(U.spacer(0, KOPF_OBEN, false))
	_build_head()
	# Zurück im Kopf (Knöpfe, Pillen): die Seite geht ganz nach oben, das Bild ist wieder voll da.
	sc.set_meta("uz_top_node", _col.get_child(_col.get_child_count() - 1))
	_ach_box = U.vbox(0)
	_col.add_child(_ach_box)
	_shots_box = U.vbox(0)
	_col.add_child(_shots_box)
	_build_captures()
	_news_box = U.vbox(0)
	_col.add_child(_news_box)
	_dlc_box = U.vbox(0)
	_col.add_child(_dlc_box)
	_about_box = U.vbox(0)
	_col.add_child(_about_box)
	_rv_box = U.vbox(0)
	_col.add_child(_rv_box)
	_backlog_box = U.vbox(0)
	_col.add_child(_backlog_box)
	_build_backlog()
	_mine_box = U.vbox(0)
	_col.add_child(_mine_box)
	_build_mine()
	# Der Verlauf (Diagramm der Runden) steht weit unten: groß, aber selten gesucht. Die Spielzeit-Pille
	# oben springt dorthin.
	_build_stats()
	_bild_stand = Media.bilder_stand
	Library.changed.connect(_on_library_changed)
	Library.backlog_changed.connect(_on_lists_changed)
	_build_more()
	# Platz, damit auch der letzte Abschnitt ganz über den Hinweisen stehen kann.
	_col.add_child(U.spacer(0, 210, false))
	add_child(_bottom_fade())
	_load()


## Maske für das große Bild (wie der Hintergrund der Startseite): rechts oben voll, nach links
## sanft zurückgenommen (der Titel steht ruhig), ab der Mitte nach unten weich bis ganz durchsichtig.
static var _mask: ImageTexture


static func _mask_tex() -> Texture2D:
	if _mask == null:
		var w := 128
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var v := float(y) / float(h - 1)
			var av := 1.0 - smoothstep(0.42, 1.0, v)
			av = av * (1.25 - 0.25 * av)
			for x in w:
				var u := float(x) / float(w - 1)
				var ah := lerpf(0.22, 1.0, smoothstep(0.0, 0.62, u))
				img.set_pixel(x, y, Color(1, 1, 1, clampf(ah * av, 0.0, 1.0)))
		_mask = ImageTexture.create_from_image(img)
	return _mask


## Unten läuft die Seite in den Raum aus: Was unter die Hinweise rutscht, verschwindet ganz.
func _bottom_fade() -> Control:
	var g := Gradient.new()
	var bg := UzTheme.col("bg")
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.7, 1.0])
	g.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 0.78), Color(bg, 1.0), Color(bg, 1.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	var f := TextureRect.new()
	f.texture = gt
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.anchor_top = 1.0
	f.anchor_bottom = 1.0
	f.anchor_right = 1.0
	f.offset_top = -200
	return f


## Kein großes Bild: das Cover leicht weichgezeichnet als Lichtschein (wie im Hintergrund); ohne
## Cover die Spielszene (ersatz), ebenso weich.
func _cover_glow(ersatz: Texture2D = null) -> void:
	Media.game_texture(game, "cover", func(t: Texture2D) -> void:
		if t:
			_set_hero(t, true)
		elif ersatz:
			_set_hero(ersatz, true)
		elif is_instance_valid(_shade):
			# Gar kein Bild: dann trägt die Farbe des Spiels den Kopf allein, etwas kräftiger.
			_shade.set("bare", true)
			_shade.queue_redraw()
	)


# --- Retro-Bühne ------------------------------------------------------------------------------

## Fläche der Retro-Bühne im Kopf: zwischen Text und Hülle, unten bündig mit der Hülle (unten: ihre
## Unterkante), höchstens 4 : 3 in der Breite eines Drittels der Oberfläche (640 × 480 in 1080p –
## Szenen mit 240 Zeilen passen zweifach hinein).
static func retro_breite(view_w: float) -> float:
	return clampf(roundf(view_w / 3.0), 420.0, 640.0)


static func retro_box(view_w: float, cover_w: float, unten: float) -> Rect2:
	var rechts := view_w - GUT - cover_w - RETRO_ABSTAND
	var w := retro_breite(view_w)
	var oben := maxf(RETRO_OBEN, unten - roundf(w * 0.75))
	return Rect2(rechts - w, oben, w, maxf(unten - oben, 0.0))


## So breit dürfen Titel, Zeile und Knöpfe werden, wenn die Retro-Bühne steht.
static func retro_text_raum(view_w: float, cover_w: float) -> float:
	return view_w - GUT * 2.0 - cover_w - RETRO_ABSTAND * 2.0 - retro_breite(view_w)


## Platz rechts im Kopf für Titel, Zeile und Knöpfe (mit Retro-Bühne schmaler).
func _kopf_raum() -> float:
	var r := head_room(U.view_size().x, _cover_w)
	return minf(r, retro_text_raum(U.view_size().x, _cover_w)) if _retro_platz else r


func _retro_rect() -> Rect2:
	var unten := KOPF_OBEN + roundf(_cover_w * 4.0 / 3.0)
	if is_instance_valid(_cover) and _cover.is_inside_tree() and is_instance_valid(_sc):
		var u := _cover.get_global_rect().end.y - get_global_rect().position.y + float(_sc.scroll_vertical)
		if u > KOPF_OBEN and u < BG.page_hero_area(get_viewport_rect().size).y + 100.0:
			unten = u
	return retro_box(U.view_size().x, _cover_w, roundf(unten))


## Szene ohne Hero: das Cover weich als Licht dahinter, die Szene als Bildschirm davor; weitere
## Szenen (Libretro, Wikipedia, RetroAchievements) wechseln langsam durch.
func _retro_zeigen(t: Texture2D) -> void:
	if not is_instance_valid(_retro):
		return
	_cover_glow(t)
	_retro.zeigen([t], _retro_rect(), true, _im_bau)
	if is_instance_valid(_cover) and not _cover.item_rect_changed.is_connected(_retro_neu_legen):
		_cover.item_rect_changed.connect(_retro_neu_legen)
	_retro_mehr(t)


func _retro_neu_legen() -> void:
	if is_instance_valid(_retro):
		_retro.platz(_retro_rect())


func _retro_mehr(erste: Texture2D) -> void:
	if U.reduziert() or Leicht.active:
		return
	var src := str(erste.get_meta("uz_src", ""))
	var urls: Array = await Media.rom_shots(game)
	var n := 1
	for u in urls:
		if not is_instance_valid(_retro) or n >= RetroBuehne.SZENEN_MAX:
			break
		var adr := str(u)
		if (Media.url_path(adr) if adr.begins_with("http") else adr) == src:
			continue
		n += 1
		Media.url_texture(adr, Media.max_width("shot"), func(t: Texture2D) -> void:
			if t and is_instance_valid(_retro) and _retro.zeigt() and not MediaS.hero_tauglich(MediaS.orig_groesse(t)):
				_retro.dazu(t)
		)


static var _blur_shader: Shader


func _set_hero(t: Texture2D, blurred := false, lod := 2.0) -> void:
	if not is_instance_valid(_hero):
		return
	if blurred:
		var m := ShaderMaterial.new()
		# Ein Shader für alle Spielseiten: jede Seite einen neuen zu übersetzen, kostete bei jedem
		# Öffnen Grafikspeicher und Zeit.
		if _blur_shader == null:
			_blur_shader = Shader.new()
			_blur_shader.code = BG.BLUR
		m.shader = _blur_shader
		_hero.material = m
		_hero.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# Sauber weichgezeichnet (siehe Background.soft_image): glatt statt blockig, auch bei
		# kleinen Bildern auf 4K. Stark (Lichtschein aus dem Cover) oder leicht (kleine
		# Spielszenen alter Systeme, damit keine Pixeltreppen bildschirmgroß werden).
		var steps := 40 if lod >= 2.0 else 80
		m.set_shader_parameter("lod", 0.0)
		m.set_shader_parameter("radius", BG.soft_radius(steps))
		m.set_shader_parameter("taps", BG.blur_taps())
		# Klein gerechnet im Hintergrund-Thread (Media.soft), nicht hier von der Grafikkarte zurück.
		Media.soft(t, steps, func(s: Texture2D) -> void:
			if s:
				_hero_show(s)
		)
		return
	_hero_show(t)


func _hero_show(t: Texture2D) -> void:
	if not is_instance_valid(_hero):
		return
	# Breites Bild oder Spielszene statt Hero: Ausschnitt dort, wo das Wichtige ist (der Hero selbst
	# kommt schon so zugeschnitten aus Media.fit_texture).
	Zuschnitt.put(_hero, t, false, false)
	# Vorab geladen (die Startseite holt es für das gewählte Spiel): Es steht sofort, die Seite
	# trägt es mit ihrer Fläche herein. Kommt es später, blendet es in T_ORT ein.
	if _im_bau:
		U.stop(_hero, "uz_hero")
		_hero_in = 1.0
		_hero.modulate.a = _hero_par
	else:
		U.ankommen(_hero, U.T_ORT, "uz_hero").tween_method(func(a: float) -> void:
			_hero_in = a
			if is_instance_valid(_hero):
				_hero.modulate.a = _hero_in * _hero_par
		, _hero_in, 1.0, U.T_ORT)
	# Das Bild steht still (kein Heraus- oder Heranzoomen: das wirkte beim Wechsel wie ein Stottern);
	# es kommt nur über die Deckkraft.
	_hero.scale = Vector2.ONE


func _first_focus() -> Control:
	return _play


## Geteilte Elemente: Das Cover der Karte landet auf der Hülle im Kopf.
func flug_ziel() -> Control:
	return _cover


# --- Kopf -------------------------------------------------------------------------------

func _build_head() -> void:
	var m := U.margin(GUT, 0, GUT, 0)
	var hb := U.hbox(40)
	m.add_child(hb)
	var v := U.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_END
	hb.add_child(v)
	# Rechts die Hülle wie im Regal – Ziel des Flugs von der Startseite; bei größerer Oberfläche
	# (schmaler) etwas kleiner, damit sie neben Titel und Knöpfen im Bild bleibt.
	_cover_w = cover_width(U.view_size().x)
	var cover = CoverCard.new()
	cover.setup(game, false, Vector2(_cover_w, roundf(_cover_w * 4.0 / 3.0)))
	cover.focus_mode = Control.FOCUS_NONE
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_meta("uz_skip", true)
	cover.size_flags_vertical = Control.SIZE_SHRINK_END
	hb.add_child(cover)
	_cover = cover
	_col.add_child(m)
	var room := _kopf_raum()
	_kopf_titel(v, room)
	_kopf_zeile(v)
	v.add_child(U.spacer(0, 10, false))
	var installed: bool = Library.is_installed(game)
	_kopf_knoepfe(v, installed)
	_kopf_installation(v, installed)
	_pillen_v = v
	_pillen_platz = v.get_child_count()
	_build_pillen(v)
	# Mit „Neu starten“ und mehreren Launchern wird die Reihe breit: Dann rücken die Knöpfe
	# zusammen, statt die Hülle rechts aus dem Bild zu schieben.
	_fit_head()


## Titel im Kopf: der Schriftzug des Spiels oder sein Name in großer Schrift.
func _kopf_titel(v: VBoxContainer, room: float) -> void:
	# Schriftzug, wenn es einen gibt; sonst der Titel groß (Meta uz_titel: weicht beim Kreuzen zuerst).
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.custom_minimum_size = Vector2(minf(620.0, room), 190)
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.visible = false
	v.add_child(_logo)
	_title = U.shadow(U.label(Library.display_title(game), "hero", "text", "title", true), 0.5)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels
	_title.set_meta("uz_titel", true)
	# Höchstens so breit, dass Titel und Hülle nebeneinander passen (auch mit größerer Oberfläche).
	_title.custom_minimum_size = Vector2(minf(1200.0, room), 0)
	_title.max_lines_visible = 2
	if _retro_platz:
		# Neben der Retro-Bühne bricht der Titel vor dem Bildschirm um (sonst füllte er die Spalte).
		_title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(_title)
	Media.game_texture(game, "logo", func(t: Texture2D) -> void:
		if t and is_instance_valid(_logo):
			_logo.texture = t
			_logo.visible = true
			_title.visible = false
	)


## Die kleine Zeile unter dem Titel: Schild der Quelle, dann was es dir ist und was es ist.
func _kopf_zeile(v: VBoxContainer) -> void:
	# Eine kleine Zeile: Schild der Quelle, was es dir ist (Spielzeit · zuletzt · nicht installiert ·
	# Platz), leise dahinter, was es ist (Genre · Studio bzw. Emulator · Bild). Hintere Angaben fallen
	# weg, statt abzubrechen.
	var zeile := U.hbox(12)
	var sys := Config.system(str(game.get("system", "")))
	var sys_short := str(sys.get("short", sys.get("name", ""))) if not sys.is_empty() else Library.store_name(game, true, "PC")
	var schild := _schild(sys_short)
	_schild_w = schild.get_combined_minimum_size().x
	zeile.add_child(schild)
	_zeile2 = U.shadow(U.label("", "m", "text", "medium"), 0.4)
	_zeile2.clip_text = false
	_zeile2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(_zeile2)
	_zeile1 = U.shadow(U.label("", "m", "muted", "medium"), 0.35)
	_zeile1.clip_text = false
	_zeile1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(_zeile1)
	v.add_child(zeile)
	_set_zeile2()


## Die Knopfreihe: „Spielen“ bzw. „Installieren“, Weiterspielen, Remote Play, Launcher, Optionen, Favorit, Soundtrack.
func _kopf_knoepfe(v: VBoxContainer, installed: bool) -> void:
	# Knöpfe: „Spielen“ hell und breit vorn, daneben ruhig die Nebenhandlungen und runde Symbole.
	var epic_inst := not installed and str(game.get("source", "")) == "epic"
	var row := U.hbox(14)
	row.set_meta("uz_group", "gp:buttons")
	v.add_child(row)
	_head_row = row
	var play := U.button("Spielen" if installed else "Installieren", "play" if installed else "download", "primary")
	play.custom_minimum_size = Vector2(280, KNOPF_H)
	play.set_meta("uz_default", true)
	play.set_meta("uz_key", "gp:play")
	play.set_meta("uz_hint_a", "Spielen" if installed else ("Über Epic installieren" if epic_inst else "Über Steam installieren"))
	play.pressed.connect(func() -> void: do_play(main, game, close))
	if not installed:
		play.set_meta("uz_haupt", true)
	_x_favorit(play)
	row.add_child(play)
	_play = play
	# Spielstände (quick_resume.gd): „Weiter, wo du warst“ vorn, „Neu starten“ daneben, darüber das
	# Bild vom Moment des Beendens – nur, wenn das Weiterspielen angeboten wird (QuickResume.record).
	var qrec: Dictionary = QuickResume.record(game) if installed else {}
	if not qrec.is_empty():
		_resume_head(v, row, play, qrec)
	# Mit Steam-Freunden spielen: über den Remote-Play-Spender (Steam zeigt dann den Spender als Spiel).
	if installed and RemotePlay.possible_for(game) and RemotePlay.configured():
		var rp := U.button("Mit Freund spielen", "friends")
		rp.custom_minimum_size.y = KNOPF_H
		rp.set_meta("uz_key", "gp:rp")
		rp.set_meta("uz_hint_a", "Starten")
		rp.pressed.connect(func() -> void: do_remote_play(main, game, close))
		_x_favorit(rp)
		row.add_child(rp)
	# Dasselbe Spiel in mehreren Launchern (stores.gd): „Über Steam“ – A wählt einen anderen.
	if installed and Library.alternatives(game).size() > 1:
		var via := U.button(_via_text(), Library.Stores.icon_of(_via_source()))
		via.custom_minimum_size.y = KNOPF_H
		via.set_meta("uz_key", "gp:via")
		via.set_meta("uz_hint_a", "Launcher wählen")
		via.pressed.connect(func() -> void:
			main.ask_launch_via(game, func(_v: String) -> void:
				game = Library.get_game(str(game.id))
				if is_instance_valid(via):
					if via.text != "":
						via.text = _via_text()
					via.icon = Icons.tex(Library.Stores.icon_of(_via_source()), 26)
					Nav.focus_moved.emit(via)))
		_x_favorit(via)
		row.add_child(via)
	var opts := U.button("Optionen", "more")
	opts.custom_minimum_size.y = KNOPF_H
	opts.set_meta("uz_key", "gp:opts")
	opts.set_meta("uz_hint_a", "Öffnen")
	# Auf dem Knopf selbst steht „Optionen“ nicht noch einmal bei Y (hint_bar.gd „—“).
	opts.set_meta("uz_hint_y", "—")
	opts.pressed.connect(func() -> void: main.open_game_options(game))
	_x_favorit(opts)
	row.add_child(opts)
	# Favorit als rundes Herz (X tut dasselbe überall auf der Seite).
	var fav := U.button("", "heart_f" if game.get("favorite", false) else "heart", "icon")
	fav.custom_minimum_size = Vector2(KNOPF_H, KNOPF_H)
	fav.set_meta("uz_key", "gp:fav")
	fav.set_meta("uz_hint_a", "Favorit")
	fav.pressed.connect(_favorit)
	row.add_child(fav)
	_fav_btn = fav
	# Soundtrack: Uzais Musiksuche (Spotify) mit dem Titel – abgespielt wird über Spotify, nichts
	# wird geladen. Nicht von selbst im Hintergrund: Das risse dir die laufende Musik weg.
	if Music.has_spotify():
		var ost := U.button("", "music", "icon")
		ost.custom_minimum_size = Vector2(KNOPF_H, KNOPF_H)
		ost.set_meta("uz_key", "gp:ost")
		ost.set_meta("uz_hint_a", "Soundtrack suchen")
		ost.pressed.connect(func() -> void: MusicBits.open_search(main, soundtrack_query(Library.display_title(game))))
		_x_favorit(ost)
		row.add_child(ost)


## Unter den Knöpfen: Stand der Installation (nicht installierte Steam- und Epic-Spiele).
func _kopf_installation(v: VBoxContainer, installed: bool) -> void:
	_inst_box = U.vbox(8)
	_inst_box.visible = false
	_inst_label = U.shadow(U.label("", "s", "text", "medium"), 0.4)
	_inst_label.clip_text = false
	_inst_box.add_child(_inst_label)
	_inst_bar = ProgressBarUz.new().setup(0.0, "accent", 6, 560)
	_inst_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_inst_bar.visible = false
	_inst_box.add_child(_inst_bar)
	v.add_child(_inst_box)
	if not installed:
		# Lädt Steam schon (zum Beispiel von früher oder in Steam angestoßen), steht der
		# Fortschritt gleich da.
		Installs.track(game)
		Installs.changed.connect(_on_install)
		_on_install(str(game.get("id", "")))


## Kleines Schild der Plattform (gerundet, Haarlinie) wie auf der Startseite.
static func _schild(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("glass_hi", 0.92), 8, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := U.label(text, "s", "text", "ui_bold")
	l.clip_text = false
	p.add_child(l)
	return p


## Leiser hinterer Teil der Zeile: Emulator-Spiel „PCSX2 · Bild: CRT“, Steam „Genre · Studio“
## (sobald der Store geantwortet hat); das System steht schon im Schild davor. Er bekommt den
## Platz, den der vordere Teil (Spielzeit · zuletzt) übrig lässt.
func _set_zeile1(_sys := {}) -> void:
	if not is_instance_valid(_zeile1) or not is_instance_valid(_zeile2):
		return
	var sys := Config.system(str(game.get("system", "")))
	var frei := _kopf_raum() - _schild_w - 24.0 - _breite_m(_zeile2.text) - _breite_m("·  ")
	var t := Buehne.passend(_zeile_oben(sys), frei, _breite_m) if frei > 80.0 else ""
	_zeile1.text = ("·  " + t) if t != "" and _breite_m(t) <= frei else ""
	_zeile1.visible = _zeile1.text != ""


func _zeile_oben(sys: Dictionary) -> Array:
	var emu_name := ""
	var flt_name := ""
	var genres := PackedStringArray()
	var dev := ""
	if game.get("source") in ["rom", "disc"] and not sys.is_empty():
		var emu := Config.emulator(str(game.get("emulator", sys.get("emulator", ""))))
		emu_name = str(emu.get("name", ""))
		var flt := Config.filter(Launcher.active_filter_id(game))
		if not flt.is_empty():
			flt_name = str(flt.get("name", ""))
	elif _shop_id() > 0:
		var d := Store.cached(_shop_id())
		genres = d.get("genres", PackedStringArray())
		dev = str(d.get("developer", ""))
	return Buehne.oben("", emu_name, flt_name, genres, dev)


## Vorderer Teil der Zeile (was es dir ist) neu setzen – auch, wenn die Installation fertig ist;
## der leise hintere Teil rückt mit.
func _set_zeile2() -> void:
	if not is_instance_valid(_zeile2):
		return
	var installed: bool = Library.is_installed(game)
	var last := Library.last_played(game)
	var note := StorageFlow.page_note(game) if not installed else ""
	var parts := Buehne.unten(_gesamt_secs(), _ago_low(last) if last > 0 else "", installed, note)
	_zeile2.text = Buehne.passend(parts, _kopf_raum() - _schild_w - 24.0, _breite_m)
	_set_zeile1()


static func _breite_m(text: String) -> float:
	return UzTheme.font("medium").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x


## Gesamte Spielzeit: die gemessene bzw. die des Launchers, mindestens aber die Summe der eigenen
## Runden (sonst stünde oben „Noch nicht gespielt“ und in der Karte „55 Min.“).
func _gesamt_secs() -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var st := SessionSummary.per_game(Library.load_sessions(), str(game.get("id", "")), bias)
	return maxi(Library.playtime(game), int(st.get("total", 0)))


## X auf einem Element des Kopfs: Favorit an/aus (wie auf der Startseite) – dasselbe wie das Herz.
func _x_favorit(c: Control) -> void:
	c.set_meta("uz_hint_x", "Favorit")
	c.set_meta("uz_on_x", _favorit)


## Favorit an/aus: Herz und Stern auf der Hülle folgen.
func _favorit() -> void:
	game = do_favorite(game)
	_cover_neu()
	if is_instance_valid(_fav_btn):
		_fav_btn.icon = Icons.tex("heart_f" if bool(game.get("favorite", false)) else "heart", 26)
	var f := Nav.focused()
	if f:
		Nav.focus_moved.emit(f)


## Die Hülle im Kopf neu (der Stern des Favoriten sitzt auf dem Cover): gleiche Stelle, gleiche
## Größe, das Bild steht aus dem Speicher sofort.
func _cover_neu() -> void:
	if not is_instance_valid(_cover):
		return
	var parent := _cover.get_parent()
	var at := _cover.get_index()
	var alt := _cover
	var cover = CoverCard.new()
	cover.setup(game, false, Vector2(_cover_w, roundf(_cover_w * 4.0 / 3.0)))
	cover.focus_mode = Control.FOCUS_NONE
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_meta("uz_skip", true)
	cover.size_flags_vertical = Control.SIZE_SHRINK_END
	parent.add_child(cover)
	parent.move_child(cover, at)
	parent.remove_child(alt)
	alt.queue_free()
	_cover = cover


## Breite der Hülle im Kopf: 270 bei 1920 logischen Punkten, bei größerer Oberfläche weniger.
static func cover_width(view_w: float) -> float:
	return clampf(roundf(view_w * 0.14), 180.0, 270.0)


## Platz rechts neben der Hülle (Ränder, Abstand 44).
static func head_room(view_w: float, cover_w: float) -> float:
	return view_w - GUT * 2.0 - 44.0 - cover_w


## Knöpfe der Reihe zusammenrücken, bis sie neben die Hülle passen: erst „Spielen“ ohne
## Mindestbreite, dann die Nebenknöpfe von rechts nach links nur noch mit Zeichen (was sie tun,
## steht weiter unten in der Tastenzeile).
func _fit_head() -> void:
	if not is_instance_valid(_head_row) or not _head_row.is_inside_tree():
		return
	var room := _kopf_raum()
	if _head_row.get_combined_minimum_size().x <= room:
		return
	if is_instance_valid(_play):
		_play.custom_minimum_size.x = 0.0
	var kids := _head_row.get_children()
	kids.reverse()
	for c in kids:
		if _head_row.get_combined_minimum_size().x <= room:
			return
		var b := c as Button
		if b == null or b == _play or b.text == "" or b.icon == null:
			continue
		if not b.has_meta("uz_hint_a") or str(b.get_meta("uz_hint_a")) == "Öffnen":
			b.set_meta("uz_hint_a", b.text)
		b.tooltip_text = b.text
		b.text = ""
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(64, 64)


## Quelle, über die „Spielen“ startet (gewählt oder die eigene).
func _via_source() -> String:
	return str(Library.launch_target(game).get("source", ""))


func _via_text() -> String:
	return tr("Über %s") % Library.Stores.name_of(_via_source(), true)


# --- Pillen unter den Knöpfen ----------------------------------------------------------------

## Unter den Knöpfen eine Reihe kleiner Pillen – nur, was es zu diesem Spiel gibt (Buehne.karten):
## Erfolge mit Ring, Freunde, die es gerade spielen, die Woche mit Mini-Säulen, Spielstände.
## A tut dasselbe wie früher die großen Karten; X ist Favorit wie überall im Kopf.
const PILLEN_ORDNUNG := ["erfolge", "freunde", "zeit", "stand"]


func _build_pillen(v: VBoxContainer) -> void:
	var gid := str(game.get("id", ""))
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var sessions := Library.load_sessions()
	var st := SessionSummary.per_game(sessions, gid, bias)
	var installed := Library.is_installed(game)
	var friends: Array = Social.playing(int(game.get("appid", 0))) if game.get("source") == "steam" else []
	var staende: Array = QuickResume.states(game) if installed else []
	var known := Achievements.known(game)
	var src := str(game.get("source", ""))
	var lage := { "secs": Library.playtime(game), "runden": int(st.get("count", 0)),
		"erfolge_bekannt": known.size() == 2 and int(known[1]) > 0,
		"erfolge_moeglich": known.is_empty() and ((src == "steam" and Achievements.has_steam()) or (src == "rom" and Achievements.has_ra())),
		"freunde": friends.size(), "staende": staende.size() }
	var arten := Buehne.karten(lage)
	if arten.is_empty():
		return
	arten.sort_custom(func(a: String, b: String) -> bool: return PILLEN_ORDNUNG.find(a) < PILLEN_ORDNUNG.find(b))
	var row := U.hbox(PILLEN_GAP)
	row.set_meta("uz_group", "gp:pillen")
	_pillen_row = row
	var i := 0
	for art in arten:
		var k: Control
		match art:
			"zeit":
				k = _pille_zeit(sessions, gid, st, now, bias)
			"erfolge":
				k = _pille_erfolge(known)
			"freunde":
				k = _pille_freunde(friends)
			_:
				k = _pille_stand(staende)
		k.set("delay_i", i)
		k.set_meta("uz_key", "gp:k:" + str(art))
		_x_favorit(k)
		if i == 0:
			k.set_meta("uz_entry", true)
		row.add_child(k)
		_staffel_ein(k, i)
		i += 1
	v.add_child(U.spacer(0, 2, false))
	v.add_child(row)


## Die Pillen blenden gestaffelt ein (höchstens vier Glieder, U.staffel); Ring und Säulen füllen
## sich danach einmal (buehne_chip.gd).
func _staffel_ein(k: Control, i: int) -> void:
	if U.reduziert():
		return
	k.modulate.a = 0.0
	U.ankommen(k, U.T_ORT, "uz_ein").tween_property(k, "modulate:a", 1.0, U.T_ORT).set_delay(U.staffel(i))


func _pille(art: String, t: Dictionary) -> Control:
	var k: Control = BuehneChip.new().setup_chip(art, str(t.get("wert", "")), str(t.get("wort", "")))
	k.wert_roh = bool(t.get("roh", false))
	return k


func _pille_zeit(sessions: Array, gid: String, st: Dictionary, now: int, bias: int) -> Control:
	var w := Buehne.woche(sessions, gid, now, bias)
	var k = _pille("zeit", Buehne.pille_zeit(int(w.gesamt)))
	# Ohne Spiel in dieser Woche: statt sieben Punkten das Uhr-Symbol.
	k.week = w.tage if int(w.gesamt) > 0 else []
	var hat_runden := not st.is_empty()
	k.set_meta("uz_hint_a", "Verlauf" if hat_runden else "Spielzeit")
	k.chosen.connect(func() -> void:
		var chart := _find_key(_col, "gp:sessions")
		if chart:
			Nav.focus(chart)
		else:
			close()
			main.goto("achievements", "statistik")
	)
	return k


func _pille_erfolge(known: Array) -> Control:
	var got := int(known[0]) if known.size() == 2 else 0
	var total := int(known[1]) if known.size() == 2 else 0
	var k = _pille("erfolge", Buehne.pille_erfolge(got, total))
	k.frac = clampf(float(got) / float(total), 0.0, 1.0) if total > 0 else 0.0
	k.voll = total > 0 and got >= total
	k.set_meta("uz_hint_a", "Alle Erfolge")
	k.chosen.connect(func() -> void: main.open_game_achievements(game))
	_erfolge_pille = k
	return k


func _pille_freunde(friends: Array) -> Control:
	var fr := Buehne.freunde(friends)
	var k = _pille("freunde", Buehne.pille_freunde(friends))
	k.faces = friends
	var one := friends.size() == 1
	k.set_meta("uz_hint_a", ("Mitspielen" if bool(fr.get("beitreten", false)) else "Mehr") if one else "Auswählen")
	k.chosen.connect(func() -> void: _pick_friend(friends))
	return k


## Der Klang des Spiels ist da: eine Pille „Spielklang“ ans Ende der Reihe (die Reihe entsteht, wenn
## es noch keine gibt). Die Säulen bewegen sich, solange er läuft; A schaltet ihn aus und wieder ein.
func _pille_klang(klang: Node) -> void:
	if _closing or not is_instance_valid(_pillen_v) or not is_instance_valid(klang):
		return
	if not is_instance_valid(_pillen_row):
		_pillen_row = U.hbox(PILLEN_GAP)
		_pillen_row.set_meta("uz_group", "gp:pillen")
		_pillen_v.add_child(_pillen_row)
		_pillen_v.move_child(_pillen_row, mini(_pillen_platz, _pillen_v.get_child_count() - 1))
	var an := bool(Config.get_value("library.spielklang", true))
	var k: Control = BuehneChip.new().setup_chip("klang", "Spielklang", "iiDB" if an else "aus")
	k.set("lebt", bool(klang.call("laeuft")))
	k.set_meta("uz_key", "gp:k:klang")
	k.set_meta("uz_hint_a", "Stumm" if an else "Einschalten")
	_x_favorit(k)
	k.connect("chosen", func() -> void:
		var neu := not bool(Config.get_value("library.spielklang", true))
		Config.set_value("library.spielklang", neu)
		k.call("set_values", "Spielklang", "iiDB" if neu else "aus")
		k.set_meta("uz_hint_a", "Stumm" if neu else "Einschalten")
		Nav.focus_moved.emit(Nav.focused())
	)
	klang.connect("wechsel", func(laeuft: bool) -> void:
		if is_instance_valid(k):
			k.set("lebt", laeuft)
	)
	_pillen_row.add_child(k)
	_staffel_ein(k, 0)


func _pille_stand(staende: Array) -> Control:
	var k = _pille("stand", Buehne.pille_staende(staende.size()))
	k.set_meta("uz_hint_a", "Alle Stände mit Bild")
	k.chosen.connect(func() -> void: open_states(main, game, close))
	return k


## Ein Freund: seine Möglichkeiten (Beitreten, Chat, Profil); mehrere: erst wählen.
func _pick_friend(friends: Array) -> void:
	if friends.is_empty():
		return
	if friends.size() == 1:
		main.open_friend(friends[0], "steam")
		return
	var opts: Array = []
	for f in friends:
		opts.append([str(f.get("id", "")), str(f.get("name", "")) + ("  ·  Beitreten möglich" if Social.join_url(f) != "" else "")])
	main.open_choice("Wer?", opts, "", func(fid: Variant) -> void:
		for f in friends:
			if str(f.get("id", "")) == str(fid):
				main.open_friend(f, "steam")
				return
	, "Freunde in diesem Spiel")


# --- Handlungen ------------------------------------------------------------------------------

## „Spielen“: starten – oder, nicht installiert, über Uzai installieren (Installs: kein fremdes
## Fenster; die Seite bleibt offen und zeigt den Fortschritt). Läuft die Installation schon: Optionen.
static func do_play(main: Main, g: Dictionary, close_cb: Callable) -> void:
	if bool(g.get("installed", true)):
		do_launch(main, g, close_cb)
		return
	if Installs.busy(str(g.get("id", ""))):
		InstallFlow.actions(main, str(g.get("id", "")), true)
	else:
		InstallFlow.begin(main, g)


static func do_launch(main: Main, g: Dictionary, close_cb: Callable) -> void:
	if close_cb.is_valid():
		close_cb.call()
	main.launch(g)


## Mit einem Stand starten. Lässt er sich gerade nicht laden (RetroArch: fremde Einstiegsdatei am
## Platz), startet das Spiel normal und sagt es.
static func do_resume(main: Main, g: Dictionary, rec: Dictionary, close_cb: Callable) -> void:
	var rg := QuickResume.resume_game(g, rec)
	if rg.is_empty():
		Toasts.show_toast("Stand lässt sich nicht laden", "Am Platz des Emulators liegt schon eine fremde Startdatei. Das Spiel startet ohne den Stand.", "warning", { "ms": 6000 })
		rg = g
	do_launch(main, rg, close_cb)


## Alle Spielstände: A startet das Spiel mit dem gewählten.
static func open_states(main: Main, g: Dictionary, close_cb: Callable) -> void:
	Spielstaende.open_for(main, g, "start", func(rec: Dictionary) -> void: do_resume(main, g, rec, close_cb))


## Mit Steam-Freunden über den Remote-Play-Spender spielen.
static func do_remote_play(main: Main, g: Dictionary, close_cb: Callable) -> void:
	var gg := g.duplicate()
	gg["_rp"] = true
	do_launch(main, gg, close_cb)


## Favorit an/aus mit kurzer Rückmeldung; Ergebnis: das Spiel mit neuem Stand.
static func do_favorite(g: Dictionary) -> Dictionary:
	var on := Library.toggle_favorite(str(g.id))
	var ng := Library.get_game(str(g.id))
	Toasts.show_toast("Favorit" if on else "Kein Favorit mehr", Library.display_title(ng), "heart_f" if on else "heart", { "sub_raw": true, "ms": 1200, "quiet": true })
	return ng


## Emulatorspiel mit gemerkter Stelle: A spielt dort weiter, daneben „Neu starten“, darüber das
## Vorschaubild (wenn Uzai eins machen konnte) mit der Zeit.
func _resume_head(v: VBoxContainer, row: HBoxContainer, play: Button, rec: Dictionary) -> void:
	var now := int(Time.get_unix_time_from_system())
	play.text = QuickResume.RESUME_TEXT
	play.custom_minimum_size.x = 360
	play.set_meta("uz_hint_a", "Weiterspielen")
	for c in play.pressed.get_connections():
		play.pressed.disconnect(c["callable"])
	play.pressed.connect(func() -> void: do_resume(main, game, rec, close))
	var fresh := U.button("Neu starten", "restart")
	fresh.custom_minimum_size.y = 64
	fresh.set_meta("uz_key", "gp:fresh")
	fresh.set_meta("uz_hint_a", "Ohne gemerkte Stelle starten")
	fresh.pressed.connect(func() -> void: do_launch(main, game, close))
	row.add_child(fresh)
	row.move_child(fresh, play.get_index() + 1)
	var tex := QuickResume.shot_texture(rec)
	var hb := U.hbox(14)
	if tex:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(224, 126)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(pic)
	var lab := U.shadow(U.label("Gemerkt %s" % QuickResume.ago_short(now - int(rec.get("at", now))), "s", "text", "medium"), 0.4)
	lab.size_flags_vertical = Control.SIZE_SHRINK_END
	hb.add_child(lab)
	v.add_child(hb)
	v.move_child(hb, row.get_index())


# --- Installation über Uzai ---------------------------------------------------------------

## Stand aus Installs unter den Knöpfen; fertig installiert wird aus „Installieren“ „Spielen“.
func _on_install(id: String) -> void:
	if id != str(game.get("id", "")) or not is_inside_tree() or not is_instance_valid(_inst_box):
		return
	var g := Library.get_game(id)
	if not g.is_empty() and Library.is_installed(g):
		game = g
		_inst_box.visible = false
		(_play as Button).text = "Spielen"
		(_play as Button).icon = Icons.tex("play", 26)
		_play.set_meta("uz_hint_a", "Spielen")
		_set_zeile2()
		Nav.focus_moved.emit(Nav.focused())
		return
	var e := Installs.entry(id)
	if e.is_empty():
		_inst_box.visible = false
		return
	_inst_box.visible = true
	var phase := str(e.phase)
	_inst_label.text = str(e.text)
	var frac := float(e.get("frac", -1.0))
	_inst_bar.visible = frac >= 0.0 and not (phase in ["failed", "cancelled"])
	if frac >= 0.0:
		_inst_bar.call("set_value", frac)
	var busy := Installs.busy(id)
	(_play as Button).text = ("Pausiert" if phase == "paused" else ("Lädt %d %%" % int(frac * 100.0) if frac >= 0.0 else "Lädt …")) if busy else "Installieren"
	_play.set_meta("uz_hint_a", "Pausieren, abbrechen …" if busy else "Installieren")
	if _play.has_focus():
		Nav.focus_moved.emit(_play)


## Stand aus Steams appmanifest: { text, frac (-1 = unbekannt), done } (siehe InstallParse).
static func install_state(st: Dictionary) -> Dictionary:
	return InstallParse.steam_state(st)


static func _gb(bytes: float) -> String:
	var gb := bytes / 1073741824.0
	if gb < 1.0:
		return "%d MB" % int(bytes / 1048576.0)
	return Lang.dec("%.1f GB" % gb)


## „Heute“, „Gestern“, „vor 3 Tagen“ – klein geschrieben, wie im Satz.
static func _ago_low(unix: int) -> String:
	return Buehne.zuletzt_text(U.ago(unix))


# --- Abschnitte --------------------------------------------------------------------------

## Ein Abschnitt: Abstand nach oben, Überschrift mit kleiner Zusatzangabe, dann der Inhalt.
## Die Zusatzangabe liegt in der Meta "uz_extra" (zum späteren Ändern).
func _section(title: String, extra := "") -> VBoxContainer:
	var box := U.vbox(HEAD_GAP)
	box.add_child(U.spacer(0, SECTION_GAP - HEAD_GAP, false))
	var m := U.margin(GUT, 0, GUT, 0)
	var hb := U.hbox(14)
	m.add_child(hb)
	var t := U.label(title, "l", "text", "bold")
	t.clip_text = false
	hb.add_child(t)
	var e := U.label(extra, "m", "faint", "medium")
	e.clip_text = false
	e.visible = extra != ""
	hb.add_child(e)
	box.set_meta("uz_extra", e)
	box.add_child(m)
	return box


## Bilder, Erfolge und Angaben laden unabhängig voneinander; jeder Teil erscheint, sobald er da ist.
func _load() -> void:
	_load_shots()
	_load_ach()
	_load_about()
	_load_steam()


## Neuigkeiten, Erweiterungen und Bewertungen (nur Steam-Spiele) erst, wenn die Seite einen Moment
## offen ist: Wer nur durchblättert, löst keine Anfragen aus. Store merkt sich die Antworten.
func _load_steam() -> void:
	var appid := int(game.get("appid", 0))
	if game.get("source") != "steam" or appid <= 0:
		return
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree() or _closing:
		return
	_load_news(appid)
	_load_dlc(appid)
	_load_reviews(appid)


## Ein nachgeladener Abschnitt blendet weich ein (er steht meist unter dem sichtbaren Teil).
func _put(slot: Control, box: Control) -> void:
	box.modulate.a = 0.0
	slot.add_child(box)
	U.ankommen(box, U.T_ORT, "uz_in").tween_property(box, "modulate:a", 1.0, U.T_ORT)


func _row(c: Control) -> Control:
	var m := U.margin(GUT, 0, GUT, 0)
	m.add_child(c)
	return m


func _load_shots() -> void:
	_shots = (await Media.screenshots(game)).duplicate()
	if not is_inside_tree() or _shots.is_empty():
		return
	var box := _section("Bilder", U.plural(_shots.size(), "Bild", "Bilder"))
	_shots_count = box.get_meta("uz_extra")
	_shots_section = box
	var shelf = Shelf.new().setup("gp:shots", 22, true, 18, GUT, 24)
	for i in _shots.size():
		var t := _Shot.new()
		t.url = str(_shots[i])
		t.set_meta("uz_hint_a", "Groß ansehen")
		var url := t.url
		t.chosen.connect(func() -> void: _open_viewer(url))
		t.failed.connect(_on_shot_failed.bind(t))
		if i == 0:
			t.set_meta("uz_entry", true)
		shelf.add(t)
	box.add_child(shelf)
	_shots_box.add_child(box)


## Ein Bild ließ sich nicht laden: Kachel weg statt eines leeren Kastens, Anzahl stimmt wieder.
func _on_shot_failed(t: Control) -> void:
	if not is_instance_valid(t):
		return
	_shots.erase(t.get("url"))
	var had_focus := t.has_focus()
	var parent := t.get_parent()
	if parent:
		parent.remove_child(t)
	t.queue_free()
	if _shots.is_empty():
		if is_instance_valid(_shots_section):
			_shots_section.queue_free()
		if had_focus and is_instance_valid(_play):
			Nav.focus(_play, true)
		return
	if is_instance_valid(_shots_count):
		_shots_count.text = U.plural(_shots.size(), "Bild", "Bilder")
	if had_focus and parent and parent.get_child_count() > 0:
		Nav.focus(parent.get_child(0) as Control, true)


## Die Erfolge des Spiels: die Pille füllt sich, darunter kommt der Abschnitt Erfolge.
func _load_ach() -> void:
	var ach := await Achievements.for_game(game)
	if not is_inside_tree():
		return
	if ach.is_empty() or int(ach.get("total", 0)) <= 0:
		# Doch keine Erfolge: die vorsorglich gesetzte Pille geht leise (selten – nur, wenn der
		# Dienst für dieses Spiel nichts kennt).
		if is_instance_valid(_erfolge_pille) and str(_erfolge_pille.get("wert")) == "…":
			var k := _erfolge_pille
			_erfolge_pille = null
			if k.has_focus() and is_instance_valid(_play):
				Nav.focus(_play, true)
			U.weg(k, "uz_ein").tween_property(k, "modulate:a", 0.0, U.T_WEG).finished.connect(func() -> void:
				if is_instance_valid(k):
					k.queue_free())
		return
	var e := Buehne.erfolge(ach, U.ago)
	if is_instance_valid(_erfolge_pille):
		var t := Buehne.pille_erfolge(int(ach.get("unlocked", 0)), int(ach.total))
		_erfolge_pille.call("set_values", str(t.wert), str(t.wort), float(e.get("frac", 0.0)), bool(e.get("voll", false)))
	_build_achievements(ach)


func _show_space() -> void:
	_set_zeile2()


## Das Spiel im Steam-Shop: bei Steam die eigene Nummer, bei anderen das schon gefundene gleichnamige (steam_match), sonst 0.
func _shop_id() -> int:
	if game.get("source") == "steam":
		return int(game.get("appid", 0))
	if game.get("source") in Media.STEAM_MATCH_SOURCES:
		var lib := Library.get_game(str(game.get("id", "")))
		return maxi(int((lib if not lib.is_empty() else game).get("steam_match", 0)), 0)
	return 0


## Angaben aus dem Store, bei Emulator-Spielen aus Wikipedia
func _load_about() -> void:
	# PC, Epic, EA and self-added games: the same game on Steam, searched by name (Media.steam_match_id, as for the
	# images) - otherwise the page of a newly added game would stay empty.
	if game.get("source") in Media.STEAM_MATCH_SOURCES and Config.get_value("library.steam_images", true):
		await Media.steam_match_id(game)
		if not is_inside_tree():
			return
	if _shop_id() > 0:
		var d := await Store.details(_shop_id())
		if is_inside_tree() and not d.is_empty():
			_build_about(d)
			_show_space()
			_set_zeile1(Config.system(str(game.get("system", ""))))
	elif game.get("source") == "rom" and Config.get_value("library.web_info", true):
		var w := await Media.wiki(game)
		if is_inside_tree() and str(w.get("about", "")) != "":
			var sys := Config.system(str(game.get("system", "")))
			_build_about({ "about": str(w.about), "system": str(sys.get("name", "")),
				"credit": "Text: Wikipedia, „%s“ (CC BY-SA)" % str(w.get("page_de", w.get("page", ""))) })


## Abschnitt Erfolge wie gewohnt: Stand und Anteil, ein Balken, die Symbole (freigeschaltete zuerst),
## darunter eine ruhige Zeile mit dem gewählten bzw. nächsten Erfolg, dann „Fast geschafft“.
func _build_achievements(ach: Dictionary) -> void:
	var total := int(ach.total)
	var got := int(ach.get("unlocked", 0))
	var pct := int(round(100.0 * got / maxf(1.0, float(total))))
	# Die Zahl steht schon in der Pille im Kopf („26 / 42 Erfolge“): hier nur der Anteil.
	var box := _section("Erfolge", "Alle freigeschaltet" if got >= total else "%d %%" % pct)
	var m := U.margin(GUT, 0, GUT, 0)
	var v := U.vbox(16)
	m.add_child(v)
	v.add_child(ProgressBarUz.new().setup(float(got) / maxf(1.0, float(total)), "gold" if got >= total else "accent", 6, 900))
	var row := U.hbox(14)
	row.set_meta("uz_group", "gp:ach")
	var list: Array = ach.get("list", [])
	# Freigeschaltete zuerst, dann die nächsten – so viele, wie nebeneinander Platz haben (mit
	# großer Oberfläche weniger).
	var fit := clampi(int((U.room_w(GUT) + 14.0) / (ACH_TILE + 14.0)), 4, 12)
	var i := 0
	for a in list.slice(0, fit):
		var tile := _Ach.new()
		tile.ach = a
		tile.set_meta("uz_key", "gp:ach:%d" % i)
		tile.set_meta("uz_hint_a", "Alle Erfolge")
		_x_favorit(tile)
		tile.chosen.connect(func() -> void: main.open_game_achievements(game))
		tile.shown.connect(_show_ach)
		row.add_child(tile)
		i += 1
	v.add_child(row)
	# Darunter eine ruhige Zeile mit dem gewählten Erfolg (statt einer Einblendung irgendwo oben).
	var cap := U.vbox(2)
	_ach_title = U.label("", "m", "text", "ui_bold")
	# Name und Beschreibung des Erfolgs sind fremder Text; was Uzai dazusetzt, ist in _show_ach schon übersetzt.
	_ach_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_ach_title.clip_text = true
	_ach_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.add_child(_ach_title)
	_ach_desc = U.label("", "s", "muted", "regular")
	_ach_desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_ach_desc.clip_text = true
	_ach_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.add_child(_ach_desc)
	v.add_child(cap)
	var al := almost(ach)
	if not al.is_empty():
		var extra := ("Noch %s bis 100 %%" % U.plural(int(al.left), "Erfolg", "Erfolge")) if al.near else "die meisten Spieler haben sie"
		var wrap := U.vbox(14)
		var head := U.hbox(12)
		var hl := U.label("Fast geschafft", "m", "text", "bold")
		hl.clip_text = false
		head.add_child(hl)
		var el := U.label(extra, "s", "faint", "medium")
		el.clip_text = false
		el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(el)
		wrap.add_child(head)
		wrap.add_child(_almost_row(al))
		v.add_child(U.spacer(0, 6, false))
		v.add_child(wrap)
	box.add_child(m)
	_put(_ach_box, box)
	# In Ruhe steht der nächste offene Erfolg da – ein kleiner Anstoß.
	var nxt: Dictionary = {}
	for a in list:
		if a is Dictionary and not (a as Dictionary).get("unlocked", false):
			nxt = a
			break
	if nxt.is_empty() and not list.is_empty() and list[0] is Dictionary:
		nxt = list[0]
	_show_ach(nxt, true)


func _show_ach(a: Dictionary, resting := false) -> void:
	if not is_instance_valid(_ach_title) or a.is_empty():
		return
	var on: bool = a.get("unlocked", false)
	var titel := (tr("Als Nächstes: ") if resting and not on else "") + str(a.get("title", ""))
	var neu := _ach_title.text != titel
	_ach_title.text = titel
	var bits := PackedStringArray()
	if on:
		var d := int(a.get("date", 0))
		bits.append(tr("Freigeschaltet am %s") % U.date(d) if d > 0 else tr("Freigeschaltet"))
	else:
		bits.append(tr("Noch offen"))
	if str(a.get("desc", "")) != "":
		bits.append(str(a.desc))
	if float(a.get("rarity", -1.0)) >= 0.0:
		bits.append(Lang.dec(tr("%.1f %% haben ihn") % float(a.rarity)))
	_ach_desc.text = "  ·  ".join(bits)
	if neu:
		_tausch(_ach_title)
		_tausch(_ach_desc)


## Hinweis-Tausch im Cursor-Takt (wie die Tastenzeile): das neue Wort steht im ersten Bild und
## setzt sich in T_ANTWORT. Beim Halten ohne Aufblenden – sonst flackerte es bei jedem Schritt.
static func _tausch(l: CanvasItem) -> void:
	if not is_instance_valid(l):
		return
	if Nav.halten_takt() > 0.0:
		U.stop(l, "uz_tausch")
		l.modulate.a = 1.0
		return
	l.modulate.a = 0.3
	U.ankommen(l, U.T_ANTWORT, "uz_tausch").tween_property(l, "modulate:a", 1.0, U.T_ANTWORT)


## Offene Erfolge, die die meisten schon haben – kurz vor 100 % auch seltenere – als kleine Karten
## mit Bild, Name, Beschreibung und Anteil; A zeigt alle Erfolge.
func _almost_row(al: Dictionary) -> Control:
	var row := U.hbox(16)
	row.set_meta("uz_group", "gp:almost")
	var shown: Array = al.list
	for i in shown.size():
		var a: Dictionary = shown[i]
		var c := StoreGame._Card.new()
		c.custom_minimum_size = Vector2(420, 164)
		c.set_meta("uz_key", "gp:almost:%d" % i)
		c.set_meta("uz_hint_a", "Alle Erfolge")
		c.chosen.connect(func() -> void: main.open_game_achievements(game))
		var hb := U.hbox(18)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(72, 72)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		pic.texture = Icons.tex("trophy", 36)
		pic.modulate = UzTheme.col("text", 0.4)      # in der Schriftfarbe: weiß verschwand im hellen Schema
		hb.add_child(pic)
		var url := str(a.get("icon_locked", a.get("icon", "")))
		if url != "":
			Media.url_texture(url, 128, func(t: Texture2D) -> void:
				if t and is_instance_valid(pic):
					pic.texture = t
					pic.modulate = Color.WHITE
			)
		var v := U.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var at := U.ellipsis(U.label(str(a.get("title", "")), "m", "text", "bold"))
		at.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Erfolgs
		v.add_child(at)
		var d := U.label(StoreGame._short(str(a.get("desc", "")), 80), "s", "muted", "regular", true)
		d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		d.max_lines_visible = 2
		v.add_child(d)
		var pct := float(a.get("rarity", -1.0))
		v.add_child(U.label(Lang.dec("%.1f %% haben ihn" % pct) if pct >= 0.0 else "Noch offen", "xs", "faint", "medium"))
		hb.add_child(v)
		c.body.add_child(hb)
		row.add_child(c)
	return row


const ALMOST_SHOWN := 4
const ACH_TILE := 96.0            ## Breite einer Erfolg-Kachel in der Reihe (_Ach)
const ALMOST_NEAR := 0.6          ## ab diesem Anteil ist ein Spiel kurz vor 100 % (wie unter „Für dich“)


## „Fast geschafft“ aus Achievements.for_game: { left, near, list }. list: offene, nicht geheime
## Erfolge, die häufig sind (Achievements.rarity_tier 0), häufigste zuerst; kurz vor 100 % (near)
## alle offenen. {} bei 100 %, ohne passende Erfolge oder bevor überhaupt einer frei ist.
static func almost(ach: Dictionary) -> Dictionary:
	var total := int(ach.get("total", 0))
	var left := total - int(ach.get("unlocked", 0))
	if total <= 0 or left <= 0 or left >= total:
		return {}
	var near := float(total - left) / total >= ALMOST_NEAR
	var open: Array = []
	for a in ach.get("list", []):
		if a is Dictionary and not a.get("unlocked", false) and not a.get("hidden", false) \
				and (near or Achievements.rarity_tier(float(a.get("rarity", -1.0))) == 0):
			open.append(a)
	if open.is_empty():
		return {}
	open.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.get("rarity", -1.0)) > float(y.get("rarity", -1.0)))
	return { "left": left, "near": near, "list": open.slice(0, ALMOST_SHOWN) }


## Suchwort für den Soundtrack auf Spotify: der Titel ohne ™/®/©, dazu „Soundtrack“.
static func soundtrack_query(title: String) -> String:
	var t := title.replace("™", "").replace("®", "").replace("©", "").strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t + " Soundtrack" if t != "" else ""


## Eigene Aufnahmen aus diesem Spiel (Clips tragen die Spiel-ID, ältere Clips und Bildschirm-
## fotos zählen über den Titel): dieselben Karten wie in der Galerie, A spielt ab bzw. zeigt groß,
## X teilt. Mehr als 12: am Ende „Alle Aufnahmen“.
const CAPS_SHOWN := 12


func _build_captures() -> void:
	var items := Capture.for_game(game)
	if items.is_empty():
		return
	var clips := items.filter(func(x) -> bool: return str(x.kind) == "clip").size()
	var bits := PackedStringArray()
	if clips > 0:
		bits.append(U.plural(clips, "Clip", "Clips"))
	if items.size() > clips:
		bits.append(U.plural(items.size() - clips, "Bildschirmfoto", "Bildschirmfotos"))
	# Eigener Abschnitt, getrennt von „Bilder“ (Szenen aus dem Netz).
	var box := _section("Deine Screenshots und Clips" if clips > 0 else "Deine Screenshots", "  ·  ".join(bits))
	var shelf = Shelf.new().setup("gp:captures", 28, true, 18, GUT, 24)
	for it in items.slice(0, CAPS_SHOWN):
		var c := CapturesUI.make_card(main, it, 384.0, items, "gp")
		if (shelf.items() as Array).is_empty():
			c.set_meta("uz_entry", true)
		shelf.add(c)
	if items.size() > CAPS_SHOWN:
		var b := U.button("Alle Aufnahmen", "video")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.set_meta("uz_key", "gp:caps_all")
		var next := str(items[CAPS_SHOWN].path)
		b.pressed.connect(func() -> void:
			close()
			main.open_captures(next)
		)
		shelf.add(b)
	box.add_child(shelf)
	_col.add_child(box)


func _build_about(d: Dictionary) -> void:
	var box := _section("Über das Spiel")
	var m := U.margin(GUT, 0, GUT, 0)
	var hb := U.hbox(80)
	m.add_child(hb)
	var left := U.vbox(12)
	# Mit großer Oberfläche wird der Text schmaler, die Angaben rechts behalten ihren Platz.
	var lw := clampf(U.room_w(GUT) - 80.0 - 340.0, 520.0, 980.0)
	left.custom_minimum_size = Vector2(lw, 0)
	hb.add_child(left)
	var text := U.label(str(d.get("about", "")), "m", "muted", "regular", true)
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Text des Shops bzw. der Wikipedia, kommt schon in der Sprache
	text.custom_minimum_size = Vector2(lw, 0)
	text.add_theme_constant_override("line_spacing", 4)
	left.add_child(text)
	if str(d.get("credit", "")) != "":
		left.add_child(U.label(str(d.credit), "xs", "faint", "regular"))
	var facts := U.vbox(12)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kv in [["System", str(d.get("system", ""))], ["Entwickler", str(d.get("developer", ""))], ["Erschienen", str(d.get("release", ""))],
			["Genre", ", ".join(d.get("genres", PackedStringArray()))], ["Sprache", Lang.own_name() if d.get("my_lang", false) else ""],
			["Metacritic", str(int(d.get("metacritic", 0))) if int(d.get("metacritic", 0)) > 0 else ""]]:
		if str(kv[1]) == "":
			continue
		var r := U.hbox(12)
		var k := U.label(str(kv[0]), "s", "faint", "medium")
		k.custom_minimum_size = Vector2(150, 0)
		r.add_child(k)
		r.add_child(U.ellipsis(U.label(str(kv[1]), "s", "text", "medium")))
		facts.add_child(r)
	hb.add_child(facts)
	box.add_child(m)
	var seiten: Control = null
	if game.get("source") == "steam":
		seiten = StoreGame.steam_seiten_zeile(main, int(game.get("appid", 0)), "gp", bool(d.get("workshop", false)))
	if seiten != null:
		var sm := U.margin(GUT, 22, GUT, 0)
		var sv := U.vbox(10)
		sv.add_child(U.label("Mehr auf Steam", "s", "faint", "medium"))
		sv.add_child(seiten)
		sm.add_child(sv)
		box.add_child(sm)
	_about_box.add_child(box)


## Deine Angaben (Roadmap 41): Kategorie, Altersfreigabe und Region oben neben der Überschrift,
## darunter die Tags als eine leise Zeile und die Links – A zeigt den QR-Code fürs Handy, Uzai
## öffnet keinen Browser. Nichts gesetzt: kein Abschnitt.
func _build_mine() -> void:
	U.clear(_mine_box)
	var g := Library.get_game(str(game.get("id", "")))
	if g.is_empty():
		g = game
	_mine_sig = _mine_key(g)
	var tags := GameFields.tags_of(g)
	var links := GameFields.links_of(g)
	var bits := PackedStringArray()
	for b in [GameFields.category_of(g), GameFields.age_label(str(g.get("age", ""))), GameFields.region_label(str(g.get("region", "")))]:
		if str(b) != "":
			bits.append(str(b))
	if tags.is_empty() and links.is_empty() and bits.is_empty():
		return
	var box := _section("Deine Angaben", "  ·  ".join(bits))
	if not tags.is_empty():
		var hb := U.hbox(12)
		var ti := U.icon("tag", 20, "faint")
		ti.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ti)
		var tl := U.label("  ·  ".join(PackedStringArray(tags)), "m", "text", "medium", true)
		tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # eigene Wörter bleiben, wie sie sind
		tl.custom_minimum_size.x = minf(1300.0, U.room_w(GUT) - 40.0)
		tl.max_lines_visible = 2
		hb.add_child(tl)
		box.add_child(_row(hb))
	if not links.is_empty():
		var row := U.hbox(14)
		row.set_meta("uz_group", "gp:links")
		for l in links:
			var url := str(l.url)
			var b := _flach(GameFields.link_title(l), "qr")
			b.set_meta("uz_key", "gp:link:" + url)
			b.set_meta("uz_hint_a", "Aufs Handy")
			b.pressed.connect(func() -> void: ChatLink.show_qr(main, ChatLink.link_info(url), false))
			row.add_child(b)
		box.add_child(_row(row))
	_put(_mine_box, box)


## Ein ruhiger Knopf ohne Fläche (Listen-Sprache „flach“): Symbol und Wort, gewählt hell.
static func _flach(text: String, icon_name: String) -> Button:
	var b := U.button(text, icon_name)
	b.custom_minimum_size.y = 56
	U.ruhig(b, "flach", 18)
	return b


static func _mine_key(g: Dictionary) -> String:
	return JSON.stringify(GameFields.FIELDS.map(func(k): return g.get(k)))


## Neue Bilder (Bildwahl über den Optionen, Spiele scrapen): Hintergrund, Schriftzug und Hülle neu
## laden – die Pfade sind neu, also kommt nichts Altes aus einem Zwischenspeicher.
func _bilder_neu() -> void:
	var hero_area := BG.page_hero_area(get_viewport_rect().size)
	Media.game_file(game, "hero", func(path: String) -> void:
		if path != "":
			Media.fit_texture(path, hero_area, func(t: Texture2D) -> void:
				if t and is_instance_valid(_hero):
					_hero.material = null
					_set_hero(t)
			)
	)
	Media.game_texture(game, "logo", func(t: Texture2D) -> void:
		if t and is_instance_valid(_logo):
			_logo.texture = t
			_logo.visible = true
			if is_instance_valid(_title):
				_title.visible = false
	)
	if is_instance_valid(_cover) and _cover.has_method("load_image"):
		_cover.set("game", game)
		_cover.call("unload_image")
		_cover.call("load_image")


## In den Optionen geändert (die liegen über der Seite): den Abschnitt neu bauen. Andere
## Änderungen an der Bibliothek lassen ihn stehen.
func _on_library_changed() -> void:
	if _closing or not is_instance_valid(_mine_box):
		return
	var g := Library.get_game(str(game.get("id", "")))
	if not g.is_empty() and _bild_stand != Media.bilder_stand:
		_bild_stand = Media.bilder_stand
		game = g
		_bilder_neu()
	if not g.is_empty() and _mine_key(g) != _mine_sig:
		_build_mine()
	if not g.is_empty() and _backlog_key(g) != _backlog_sig:
		_build_backlog()


## Listen geändert (In Liste …): die Zahl auf dem Knopf stimmt wieder.
func _on_lists_changed() -> void:
	if not _closing and is_instance_valid(_backlog_box):
		_build_backlog()


# --- Dein Backlog (Roadmap 2, src/library/backlog.gd) -----------------------------------------

## Status, Sterne und Rezension, die letzten Einträge im Tagebuch, bei Emulator-Spielen die Notiz
## und – nur als Angebot – ein Vorschlag für den Status (Uzai setzt ihn nie selbst). Die drei
## häufigen Handlungen stehen als ruhige Zeile ohne Flächen (Status, Bewerten, Tagebuch), „…“
## öffnet alles zum Backlog (BacklogFlow.open_sheet: Rezension, Listen, Notizen). Der Abschnitt
## baut sich nach jeder Änderung neu auf und behält die Auswahl.
func _build_backlog() -> void:
	var f := Nav.focused()
	var keep := str(f.get_meta("uz_key", "")) if f and _backlog_box.is_ancestor_of(f) else ""
	U.clear(_backlog_box)
	var g := Library.get_game(str(game.get("id", "")))
	if g.is_empty():
		g = game
	_backlog_sig = _backlog_key(g)
	var sum := Backlog.summary(g)
	var box := _section("Dein Backlog", sum if sum != "" else "Noch nichts eingetragen")
	var v := U.vbox(16)
	var stars := Backlog.stars_of(g)
	var review := Backlog.review_of(g)
	if stars > 0 or review != "":
		var top := U.hbox(22)
		if stars > 0:
			var sr = StarRow.new().setup(stars, 30)
			sr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			top.add_child(sr)
		if review != "":
			var rl := U.label("„%s“" % review, "m", "text", "regular", true)
			rl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # eigene Worte
			rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rl.custom_minimum_size.x = 600
			top.add_child(rl)
		v.add_child(top)
	var own_note := str(g.get("notes", "")) if RetroSysteme.is_retro_game(g) and g.get("notes") is String else ""
	if own_note != "":
		var nl := U.label(own_note, "m", "muted", "regular", true)
		nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # eigene Worte
		nl.custom_minimum_size = Vector2(minf(1100.0, U.room_w(GUT)), 0)
		nl.max_lines_visible = 4
		var nb := U.hbox(14)
		var ni := U.icon("edit", 22, "faint")
		ni.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		nb.add_child(ni)
		nb.add_child(nl)
		v.add_child(nb)
	var row := U.hbox(6)
	row.set_meta("uz_group", "gp:backlog")
	var s := Backlog.status_of(g)
	var n_diary := Backlog.diary_of(g).size()
	var btns: Array = [
		["status", Backlog.status_name(s) if s != "" else "Status", Backlog.status_icon(s) if s != "" else "bookmark",
			func() -> void: BacklogFlow.pick_status(main, g)],
		["stars", "Bewerten" if stars == 0 else Backlog.stars_text(stars), "star", func() -> void: BacklogFlow.pick_stars(main, g)],
		["diary", "Tagebuch" if n_diary == 0 else "Tagebuch (%d)" % n_diary, "history", func() -> void: BacklogFlow.open_diary(main, g)],
		["more", "Mehr", "more", func() -> void: BacklogFlow.open_sheet(main, g)],
	]
	for e in btns:
		var b := _flach(str(e[1]), str(e[2]))
		b.set_meta("uz_key", "gp:bl:" + str(e[0]))
		if str(e[0]) == "more":
			b.set_meta("uz_hint_a", "Rezension, Listen, Notizen" if RetroSysteme.is_retro_game(g) else "Rezension, Listen")
		b.pressed.connect(e[3] as Callable)
		row.add_child(b)
	v.add_child(row)
	var now := int(Time.get_unix_time_from_system())
	var sug := Backlog.suggest(g, Library.playtime(g), Library.last_played(g), Achievements.known(g), now)
	if not sug.is_empty():
		var sl := U.hbox(14)
		sl.add_child(U.icon("bulb", 24, "accent"))
		var t := U.label("Vorschlag: %s" % Backlog.status_name(str(sug.status)), "m", "text", "bold")
		t.clip_text = false
		sl.add_child(t)
		var why := U.label(str(sug.why), "m", "muted", "regular")
		why.clip_text = false
		sl.add_child(why)
		var take := _flach("Übernehmen", "check")
		take.set_meta("uz_key", "gp:bl:suggest")
		var gid := str(g.get("id", ""))
		var st := str(sug.status)
		take.pressed.connect(func() -> void: Library.set_status(gid, st))
		sl.add_child(take)
		v.add_child(sl)
	var entries := Backlog.diary_of(g).slice(0, 2)
	if not entries.is_empty():
		var dv := U.vbox(8)
		for e in entries:
			var line := U.hbox(14)
			var head := U.label(BacklogFlow.entry_head(int(e.at), int(e.get("secs", 0))), "s", "muted", "medium")
			head.clip_text = false
			line.add_child(head)
			if str(e.get("note", "")) != "":
				var note := U.ellipsis(U.label(str(e.note), "s", "text", "regular"))
				note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				line.add_child(note)
			dv.add_child(line)
		v.add_child(dv)
	box.add_child(_row(v))
	_backlog_box.add_child(box)
	if keep != "":
		var hit := _find_key(_backlog_box, keep)
		if hit:
			Nav.focus.call_deferred(hit, true)


static func _backlog_key(g: Dictionary) -> String:
	return JSON.stringify(Backlog.FIELDS.map(func(k): return g.get(k)) + [g.get("notes")])


static func _find_key(n: Node, key: String) -> Control:
	for c in n.get_children():
		if c is Control and str(c.get_meta("uz_key", "")) == key:
			return c
		var r := _find_key(c, key)
		if r:
			return r
	return null


## Verlauf (Punkte 38, 100): die letzten Runden (links/rechts wählt eine Runde) und darunter eine
## einzige Zeile, was auffällt – Runden und Schnitt, längste Runde, Tageszeit, nächster
## Meilenstein. Zahlen aus SessionSummary.per_game, nur aus Uzais eigenen Runden.
func _build_stats() -> void:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var now := int(Time.get_unix_time_from_system())
	var st := SessionSummary.per_game(Library.load_sessions(), str(game.get("id", "")), bias)
	if st.is_empty():
		return
	var box := _section("Verlauf", "seit %s" % SessionSummary.date_text(int(st.first), bias, now))
	var m := U.margin(GUT, 0, GUT, 0)
	var v := U.vbox(18)
	m.add_child(v)
	var chart = SessionChart.new().setup(st.recent, bias, Vector2(0, 320))
	chart.set_meta("uz_key", "gp:sessions")
	_x_favorit(chart)
	v.add_child(chart)
	var total := Library.playtime(game)
	var parts := Buehne.runden_zeile(st, total, PlaytimePage.dur, func(unix: int) -> String: return SessionSummary.date_text(unix, bias, now),
		SessionSummary.daypart, SessionSummary.marks(total))
	if not parts.is_empty():
		var l := U.label(Buehne.passend(parts, U.room_w(GUT) - 8.0, _breite_m), "m", "muted", "medium")
		l.clip_text = false
		v.add_child(l)
	box.add_child(m)
	_col.add_child(box)


# --- Aus Steam (dieselben Bausteine wie im Shop) ---------------------------------------------

func _load_news(appid: int) -> void:
	var list: Array = await Store.news(appid)
	if not is_inside_tree() or list.is_empty():
		return
	var box := _section("Neuigkeiten", "von den Entwicklern")
	box.add_child(_row(StoreGame.news_row(main, list, "gp")))
	_put(_news_box, box)


## Erweiterungen mit „In deiner Bibliothek“, wo Steam sie auf diesem PC installiert hat; A öffnet
## die Shop-Seite.
func _load_dlc(appid: int) -> void:
	var list: Array = await Store.dlc_items(appid)
	if not is_inside_tree() or list.is_empty():
		return
	var have := Store.dlc_installed(appid)
	var bits := PackedStringArray([U.plural(list.size(), "Inhalt", "Inhalte")])
	var n := list.filter(func(it: Dictionary) -> bool: return have.has(int(it.get("appid", 0)))).size()
	if n > 0:
		bits.append("%d installiert" % n)
	var box := _section("Erweiterungen", "  ·  ".join(bits))
	box.add_child(StoreGame.dlc_shelf(list, "gp:dlc", have, func(it: Dictionary) -> void:
		var l = StoreGame.new()
		l.item = it
		l.main = main
		main.open_layer(l)
	))
	_put(_dlc_box, box)


func _load_reviews(appid: int) -> void:
	var rv: Dictionary = await Store.reviews(appid)
	if not is_inside_tree() or int(rv.get("total", 0)) <= 0:
		return
	var texts: Array = await Store.review_texts(appid)
	if not is_inside_tree():
		return
	var box := _section("Bewertungen", "von Spielern auf Steam")
	box.add_child(_row(StoreGame.reviews_row(main, rv, texts, "gp")))
	_put(_rv_box, box)


## Weitere Spiele desselben Systems (öffnet deren Seite).
func _build_more() -> void:
	var sys := str(game.get("system", ""))
	var others := Library.by_system(sys).filter(func(g): return str(g.id) != str(game.id))
	if others.is_empty():
		return
	others = Library.sorted(others, "recent")
	var sname := str(Config.system(sys).get("name", "")) if not Config.system(sys).is_empty() else Library.store_name({ "source": sys }, false, "PC")
	var box := _section("Mehr für " + sname)
	var shelf = Shelf.new().setup("gp:more", 24, true, 26, GUT, 40)
	for g in others.slice(0, 16):
		var card = CoverCard.new()
		card.setup(g, false, Vector2(200, 266))
		card.focus_scale = 1.08
		card.chosen.connect(func(gg: Dictionary) -> void:
			close()
			main.open_game(gg)
		)
		shelf.add(card)
		card.set_meta("uz_hint_a", "Öffnen")
	box.add_child(shelf)
	_col.add_child(box)


func handle(cmd: String) -> bool:
	if cmd == "y":
		main.open_game_options(game)
		return true
	return false


# --- Bildbetrachter ----------------------------------------------------------------------

func _open_viewer(url: String) -> void:
	var i := _shots.find(url)
	if i < 0:
		return
	var v := _Viewer.new()
	v.urls = _shots
	v.idx = i
	main.open_layer(v)


class _Viewer extends "res://src/ui/layers/layer.gd":
	var urls: Array = []
	var idx := 0
	var _img: TextureRect
	var _count: Label
	var _pad: Control

	func build() -> void:
		dim = 0.96
		_scrim.color = Color(0, 0, 0, dim)
		set_meta("uz_hint_b", "Zurück")
		set_meta("uz_hints", [["lb", ""], ["rb", "Blättern"]])
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		U.full_rect(_img)
		_img.offset_left = 80
		_img.offset_right = -80
		_img.offset_top = 60
		_img.offset_bottom = -110
		add_child(_img)
		_count = U.label("", "m", "muted", "medium")
		_count.position = Vector2(96, 1012)
		add_child(_count)
		_pad = Control.new()
		_pad.focus_mode = Control.FOCUS_ALL
		_pad.custom_minimum_size = Vector2(1, 1)
		_pad.set_meta("uz_hint_a", "—")
		add_child(_pad)
		_show(idx)

	func _first_focus() -> Control:
		return _pad

	func _show(i: int) -> void:
		if urls.is_empty():
			return
		idx = posmod(i, urls.size())
		_count.text = "%d von %d" % [idx + 1, urls.size()]
		var url := str(urls[idx])
		Media.url_texture(url, 1920, func(t: Texture2D) -> void:
			if is_instance_valid(_img) and t and str(urls[idx]) == url:
				_img.texture = t
				_img.modulate.a = 0.3
				U.ankommen(_img, U.T_ORT, "uz_bild").tween_property(_img, "modulate:a", 1.0, U.T_ORT)
		)

	func handle(cmd: String) -> bool:
		match cmd:
			"lb", "left":
				_show(idx - 1)
				Sfx.play("tick")
				return true
			"rb", "right":
				_show(idx + 1)
				Sfx.play("tick")
				return true
		return false


# --- Bausteine ---------------------------------------------------------------------------

## Ein Bild aus dem Spiel (16:9) mit runden Ecken, Schatten, Ring und Lichtstreif (nur, wo die
## Grundwerte ihn wollen). Solange es lädt, steht die Fläche ruhig (kein Pulsieren); lädt es nicht, meldet
## die Kachel das (failed) und verschwindet. Aus dem Speicher steht das Bild sofort.
class _Shot extends Control:
	signal chosen
	signal failed
	const UU := preload("res://src/ui/u.gd")
	const ShineC := preload("res://src/ui/components/shine.gd")
	var url := ""
	var _frame: Panel
	var _img: TextureRect
	var _shine
	var _im_bau := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(400, 225)
		_frame = Panel.new()
		_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
		_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.size = Vector2(400, 225)
		add_child(_frame)
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UU.full_rect(_img)
		_img.modulate.a = 0.0
		_frame.add_child(_img)
		_shine = ShineC.new()
		_frame.add_child(_shine)
		var me: WeakRef = weakref(self)
		_im_bau = true
		Media.url_texture(url, 640, func(t: Texture2D) -> void:
			var s: Object = me.get_ref()
			if s:
				s.call("_loaded", t)
		)
		_im_bau = false
		focus_entered.connect(func() -> void:
			UU.focus_anim(self, true)
			if UzTheme.focus_shine():
				_shine.play()
		)
		focus_exited.connect(func() -> void: UU.focus_anim(self, false))

	func _loaded(t: Texture2D) -> void:
		if t == null:
			failed.emit()
			return
		_img.texture = t
		if _im_bau:
			_img.modulate.a = 1.0
			return
		UU.ankommen(_img, UU.T_ORT, "uz_bild").tween_property(_img, "modulate:a", 1.0, UU.T_ORT)

	func activate() -> void:
		chosen.emit()

	func _draw() -> void:
		var f := float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
		_frame.position.y = -8.0 * f
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0)
		sh.set_corner_radius_all(UzTheme.r_cover())
		sh.shadow_color = Color(0, 0, 0, 0.35 + 0.2 * f)
		sh.shadow_size = int(14 + 14 * f)
		sh.shadow_offset = Vector2(0, 10)
		draw_style_box(sh, Rect2(Vector2(4, 6 - 8.0 * f), size - Vector2(8, 8)))
		if f > 0.01:
			draw_set_transform(Vector2(0, -8.0 * f))
			draw_style_box(UzTheme.focus_ring(minf(f, 1.0), UzTheme.r_cover()), Rect2(Vector2.ZERO, size))
			draw_set_transform(Vector2.ZERO)


## Ein Erfolg als Symbol; nicht freigeschaltete sind blass. Gewählt hebt es sich ein Stück, darum
## der leise Schein der Kacheln (UzTheme.draw_tile_focus) – kein weißer Rahmen; die Seite nennt
## darunter Titel und Beschreibung (Signal shown).
class _Ach extends Control:
	signal chosen
	signal shown(a: Dictionary)
	const UU := preload("res://src/ui/u.gd")
	var ach: Dictionary = {}
	var _tex: Texture2D

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(96, 96)
		var url := str(ach.get("icon", "")) if ach.get("unlocked", false) else str(ach.get("icon_locked", ach.get("icon", "")))
		if url != "":
			var wr: WeakRef = weakref(self)
			Media.url_texture(url, 128, func(t: Texture2D) -> void:
				var me: Control = wr.get_ref()
				if me:
					me.set("_tex", t)
					me.queue_redraw()
			)
		focus_entered.connect(func() -> void:
			UU.focus_anim(self, true)
			shown.emit(ach)
		)
		focus_exited.connect(func() -> void: UU.focus_anim(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func activate() -> void:
		chosen.emit()

	func _draw() -> void:
		var f := clampf(float(get_meta("uz_f", 0.0)), 0.0, 1.0) if has_meta("uz_f") else 0.0
		var rad := UzTheme.r_panel()
		var r := Rect2(Vector2(0, -6.0 * f), size)
		var sh := StyleBoxFlat.new()
		sh.draw_center = false
		sh.set_corner_radius_all(rad)
		sh.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(0.2 + 0.24 * f))
		sh.shadow_size = int(8 + 12 * f)
		sh.shadow_offset = Vector2(0, 4 + 6 * f)
		draw_style_box(sh, r)
		var hi: Color = UzTheme.col("surface_hi")
		draw_style_box(UzTheme.flaeche(hi.lerp(UzTheme.col("sel"), 0.6 * f), rad), r)
		var on: bool = ach.get("unlocked", false)
		if _tex:
			draw_texture_rect(_tex, r.grow(-10), false, Color(1, 1, 1, 1.0 if on else 0.35))
		else:
			var ic := Icons.tex("trophy", 36)
			# In der Schriftfarbe: Weiß auf der hellen Kachel (Farbschema „Papier“) war nicht zu sehen.
			draw_texture_rect(ic, Rect2(r.get_center() - Vector2(18, 18), Vector2(36, 36)), false, UzTheme.col("text", 0.8 if on else 0.25))
		if on:
			draw_circle(r.position + Vector2(r.size.x - 14, 14), 8, UzTheme.col("gold"))
		UzTheme.draw_tile_focus(self, r, rad, f)


## Das Bild des Spiels läuft nach unten und links in den Raum aus.
class _Shade extends Control:
	const UU := preload("res://src/ui/u.gd")

	## Farbe des Spiels (aus dem Cover): ein weicher Lichtschein hinter Titel und Hülle.
	var tint := Color(0, 0, 0, 0)
	## Kein Bild gefunden: der Lichtschein trägt den Kopf allein und darf kräftiger sein.
	var bare := false
	static var _glow_tex: GradientTexture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	static func glow() -> GradientTexture2D:
		if _glow_tex == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
			_glow_tex = GradientTexture2D.new()
			_glow_tex.gradient = g
			_glow_tex.fill = GradientTexture2D.FILL_RADIAL
			_glow_tex.fill_from = Vector2(0.5, 0.5)
			_glow_tex.fill_to = Vector2(1.0, 0.5)
			_glow_tex.width = 256
			_glow_tex.height = 256
		return _glow_tex

	func _draw() -> void:
		var bg := UzTheme.col("bg")
		draw_rect(Rect2(Vector2.ZERO, size), Color(bg, 0.25))
		draw_texture_rect(UU.fade_texture(true, true), Rect2(0, size.y * 0.25, size.x, size.y * 0.75), false, bg)
		draw_texture_rect(UU.fade_texture(false), Rect2(0, 0, size.x * 0.6, size.y), false, Color(bg, 0.75))
		if tint.a > 0.0:
			# Unten links hinter Hülle und Titel und rechts oben, wie Licht aus dem Bild.
			var k := 2.2 if bare else 1.0
			draw_texture_rect(glow(), Rect2(-420, size.y * 0.35, 1500, 900), false, Color(tint, tint.a * 0.22 * k))
			draw_texture_rect(glow(), Rect2(size.x - 760, 60, 900, 760), false, Color(tint, tint.a * 0.16 * k))
			if bare:
				draw_texture_rect(glow(), Rect2(size.x * 0.2, -380, 1300, 900), false, Color(tint, tint.a * 0.2))
