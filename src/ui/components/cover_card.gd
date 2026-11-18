extends Control
## Ein Spiel als Cover. Fokussiert: größer, heller Ring mit Gold-Glimmen und weichem Schatten.
## Auf der Startseite wächst das gewählte Cover nach oben und spiegelt sich leicht im Boden.

signal chosen(game: Dictionary)
signal focused_game(game: Dictionary)

const CoverArt := preload("res://src/ui/components/cover_art.gd")
const Shine := preload("res://src/ui/components/shine.gd")
const U := preload("res://src/ui/u.gd")
const InstallBadge := preload("res://src/ui/components/install_badge.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")
const KachelZustand := preload("res://src/ui/components/kachel_zustand.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Flug := preload("res://src/ui/flug.gd")

## Solange das Bild lädt, schimmert ein Platzhalter (Punkt 93); das Ersatz-Cover mit dem Titel
## kommt erst, wenn es nach so vielen Sekunden noch kein Bild gibt (oder gar keins).
const WAIT_ART_S := 1.2

var _shine: Control
var game: Dictionary = {}
var show_system := false
var card_size := Vector2(216, 288)
var _clip: Panel
var _img: TextureRect
var _art: Control
var _fav: Control
var _bar: Control
var _focus_t := 0.0
var _tw: Tween
var _check: Control
var checked := -1          ## -1: keine Auswahl, 0: nicht gewählt, 1: gewählt (Auswahlmodus)
var focus_scale := 1.06
var grow_up := false       ## beim Fokus nach oben wachsen (unten bündig bleiben)
var grow_left := false   ## dabei links bündig bleiben (Regal der Startseite: die Nachbarn rücken)
var calm := false          ## ruhig gewählt: ohne Nachfedern und Lichtstreif (Regal der Startseite)
var reflect := false       ## Spiegelung unter dem Cover
const REFLECT_ALPHA := 0.55   ## Deckkraft direkt unter dem Cover (läuft weich aus)
const REFLECT_DEPTH := 0.28   ## Länge der Spiegelung (Anteil der Coverhöhe)
## Deckkraft der Spiegelung 0…1: Beim Aufbau der Startseite kommt sie zuletzt (startseite_aufbau.gd).
var spiegel := 1.0:
	set(v):
		if v != spiegel:
			spiegel = v
			queue_redraw()
var _sync_tex := false
## Bild erst laden, wenn load_image() kommt (Bibliotheks-Raster: nur was zu sehen ist). Weit
## entfernte Karten geben ihr Bild mit unload_image() wieder frei – sonst lagen bei 1000 Spielen
## alle Cover gleichzeitig im Grafikspeicher. Auch das Innere (Ersatz-Cover mit gesetztem Titel,
## Plaketten) entsteht erst dann: bei 3000 Spielen kostete es sonst Sekunden beim Öffnen.
var lazy := false
var _built := false
var _requested := false
var _img_gen := 0
var _answered := false
var _wait: Control
## Lebendige Kachel (Startseite, Bibliothek): was gerade am Spiel los ist, als Abzeichen auf dem
## Cover – eigene Schicht kachel_zustand.gd, die Karte setzt sie nur ein und meldet den Fokus.
var live := false
var _live: Control
## Zeile unter dem Cover, nur zu sehen, solange es gewählt ist (Startseite: Spielzeit und wann
## zuletzt gespielt) – unter allen Covern wäre es eine Wand aus Zahlen.
var caption := ""


## A gedrückt: kurz einsinken und zurück, ohne Nachfedern (eigener Tween, kämpft nicht mit dem Fokus).
func press_feedback() -> void:
	if _tw:
		_tw.kill()
	_set_focus_t(1.0)
	var s := _gross(true)
	_tw = U.ankommen(self, U.T_ORT, "uz_cover")
	_tw.tween_property(self, "scale", Vector2.ONE * (s - (0.0 if U.reduziert() else 0.045)), U.T_ANTWORT)
	_tw.tween_property(self, "scale", Vector2.ONE * s, U.T_ORT)


func setup(g: Dictionary, with_system := false, override_size := Vector2.ZERO) -> Control:
	game = g
	show_system = with_system
	card_size = override_size if override_size != Vector2.ZERO else UzTheme.cover_size()
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = card_size
	if grow_left:
		pivot_offset = Vector2(0, card_size.y)
	else:
		pivot_offset = Vector2(card_size.x * 0.5, card_size.y) if grow_up else card_size * 0.5
	# Wer die Karte baut, darf den Hinweis vorgeben; sonst: Spielseite öffnen bzw. spielen.
	if not has_meta("uz_hint_a"):
		set_meta("uz_hint_a", "Öffnen" if Config.get_value("system.game_page", true) else ("Spielen" if Library.is_installed(game) else "Installieren"))
	set_meta("uz_key", "g:" + str(game.get("id", "")))
	set_meta("uz_flug", "g:" + str(game.get("id", "")))
	if checked >= 0:
		set_checked(checked == 1)
	if not lazy:
		_build()
		_request_image()
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(_on_gui_input)


## Das Innere der Karte: Ersatz-Cover, Platz für das Bild, Plaketten (einmal).
func _build() -> void:
	if _built:
		return
	_built = true
	_clip = Panel.new()
	_clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_cover()))
	U.clip_round(_clip)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_clip)
	add_child(_clip)
	_art = CoverArt.new()
	_art.compact = card_size.x < 190
	U.full_rect(_art)
	_clip.add_child(_art)
	_art.setup(game)
	_art.modulate = _dim_color()
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_img)
	_img.visible = false
	_clip.add_child(_img)
	if live:
		_live = KachelZustand.new().setup(self, _img)
		_clip.add_child(_live)
	_build_badges()
	# Der Haken (Auswahlmodus) liegt über dem Cover.
	if _check:
		move_child(_check, get_child_count() - 1)


func _build_badges() -> void:
	if show_system:
		# Matt (Marke): eckiges Schild mit Haarlinie statt dunkler Glas-Pille.
		var tag := U.panel("bg", 999, 0, 0.72)
		if UzTheme.matt():
			tag.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("bg", 0.86), 999, 1, UzTheme.col("line")))
		var sys := Config.system(str(game.get("system", "")))
		var txt := str(sys.get("short", Library.store_name({ "source": str(game.get("system", "")) }, true, "PC")))
		var l := U.label(txt, "cap", "text", "ui_bold")
		l.clip_text = false
		var m := U.margin(10, 3, 10, 4)
		m.add_child(l)
		tag.add_child(m)
		tag.position = Vector2(10, 10)
		tag.visible = false
		tag.name = "SysTag"
		_clip.add_child(tag)
	if game.get("favorite", false):
		_fav = U.panel("bg", 14, 0, 0.72)
		_fav.custom_minimum_size = Vector2(30, 30)
		var st := U.icon("star_f", 18, "accent_ink")
		st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_fav.add_child(st)
		_fav.position = Vector2(card_size.x - 40, 10)
		_clip.add_child(_fav)
	# Nicht installiert: kein Zeichen und kein Grau – im Raster und in der Vitrine sind das die
	# eigenen Spiele; ob eins installiert ist, sagt die Spielseite. Lädt Uzai es gerade (oder
	# gleich): unten Balken und Prozent, live.
	if not Library.is_installed(game):
		_on_install(str(game.get("id", "")))
		if not Installs.changed.is_connected(_on_install):
			Installs.changed.connect(_on_install)
	var ach := Achievements.cached(game)
	if not ach.is_empty() and int(ach.get("total", 0)) > 0:
		var frac := float(ach.unlocked) / float(ach.total)
		_bar = ColorRect.new()
		_bar.color = UzTheme.col("gold") if frac >= 1.0 else UzTheme.col("accent")
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.position = Vector2(0, card_size.y - 4)
		_bar.size = Vector2(card_size.x * frac, 4)
		_clip.add_child(_bar)


## Download-Anzeige auf dem Cover, sobald Installs dieses Spiel lädt (InstallBadge entfernt sich
## selbst, wenn der Download endet).
func _on_install(id: String) -> void:
	if id != str(game.get("id", "")) or not Installs.busy(id) or not is_instance_valid(_clip) or _clip.has_node("InstallBadge"):
		return
	var b := InstallBadge.new()
	b.name = "InstallBadge"
	b.game_id = id
	_clip.add_child(b)


## Haken für den Auswahlmodus (Spiele in einen Ordner legen).
func set_checked(on: bool) -> void:
	checked = 1 if on else 0
	if _check == null:
		_check = Panel.new()
		_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_check.size = Vector2(36, 36)
		_check.position = Vector2(10, 10)
		var ic := U.icon("check", 22, "bg")
		ic.position = Vector2(7, 7)
		ic.name = "Icon"
		_check.add_child(ic)
		add_child(_check)
	_check.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("accent") if on else Color(0, 0, 0, 0.55), 18, 2, UzTheme.col("text", 0.9)))
	_check.get_node("Icon").visible = on
	# Nicht gewählt: abgedunkelt, aber deckend – sonst scheint das Ersatz-Cover mit seinem
	# Titel durch das echte Bild.
	var tint := _dim_color()
	if _img:
		_img.modulate = Color(tint, _img.modulate.a)
	if _art:
		_art.modulate = tint
	# Im Auswahlmodus ruht das Abzeichen der lebendigen Kachel.
	if _live:
		_live.refresh()


func _dim_color() -> Color:
	return Color(0.42, 0.42, 0.44, 1.0) if checked == 0 else Color.WHITE


func _request_image() -> void:
	if _requested:
		return
	_requested = true
	var kind := _art_kind()
	_answered = false
	_sync_tex = true
	Media.game_texture(game, kind, _on_texture.bind(_img_gen))
	_sync_tex = false
	if not _answered:
		_begin_wait()


func _art_kind() -> String:
	return "wide" if UzTheme.cover_size().x > UzTheme.cover_size().y * 1.4 else "cover"


## Bild noch unterwegs: Platzhalter in Form des Covers statt gleich des Ersatz-Covers – so blitzt
## beim Öffnen einer Reihe nicht erst der Titel auf, bevor das Bild darüber einblendet.
func _begin_wait() -> void:
	if not is_instance_valid(_clip) or is_instance_valid(_wait) or not is_inside_tree():
		return
	_art.visible = false
	# In der gemerkten Grundfarbe des Covers: Das Bild „entwickelt“ sich dann nur noch darüber.
	_wait = Skeleton.fill(0, Media.grundfarbe(Media.local_path(game, _art_kind())))
	_clip.add_child(_wait)
	_clip.move_child(_wait, _art.get_index() + 1)
	var gen := _img_gen
	get_tree().create_timer(WAIT_ART_S).timeout.connect(func() -> void:
		if gen == _img_gen and is_instance_valid(_img) and not _img.visible:
			_end_wait()
	)


## Bild da (oder es kommt keins bzw. noch lange nicht): Platzhalter weich weg. Ohne Bild blendet
## das Ersatz-Cover ein; deckt das Bild, bleibt es aus (siehe _bild_deckt).
func _end_wait() -> void:
	if not is_instance_valid(_wait):
		return
	Skeleton.fade_out(_wait)
	_wait = null
	if _img.visible:
		return
	_art.visible = true
	var a := _art.modulate.a
	_art.modulate.a = 0.0
	U.ankommen(_art, U.T_ORT, "uz_art").tween_property(_art, "modulate:a", a, U.T_ORT)


## Das Bild deckt die ganze Karte: das Ersatz-Cover mit dem Titel darunter geht aus. Sonst schiene
## es durch, sobald die Karte (oder ihre Reihe) halb durchsichtig ist – Geister-Titel beim
## Bereichswechsel, im Regal, in der Bibliothek und bei der Rückkehr aus dem Spiel.
func _bild_deckt() -> void:
	if is_instance_valid(_img) and _img.visible and _img.texture != null and _img.modulate.a >= 0.99 and is_instance_valid(_art):
		U.stop(_art, "uz_art")
		_art.visible = false


func load_image() -> void:
	if not is_node_ready():
		lazy = false
		return
	_build()
	_request_image()


func unload_image() -> void:
	if not _requested:
		return
	_requested = false
	_img_gen += 1
	_end_wait()
	if is_instance_valid(_img):
		_img.texture = null
		_img.visible = false
		if is_instance_valid(_art):
			_art.visible = true
		if reflect:
			queue_redraw()
	if is_instance_valid(_art):
		_art.visible = true


func image_requested() -> bool:
	return _requested


func _on_texture(t: Texture2D, gen := -1) -> void:
	if not is_instance_valid(_img) or (gen >= 0 and gen != _img_gen):
		return
	_answered = true
	if t == null:
		_end_wait()
		return
	# Kluger Ausschnitt, Ton und gemeinsamer Verlauf (Punkt 97).
	Zuschnitt.put(_img, t)
	_img.visible = true
	if reflect:
		queue_redraw()
	_img.modulate = _dim_color()
	var tag := _clip.get_node_or_null("SysTag")
	if tag:
		tag.visible = true
		_clip.move_child(tag, _clip.get_child_count() - 1)
	if _sync_tex:
		_bild_deckt()
		return
	_img.modulate.a = 0.0
	var tw := U.ankommen(_img, U.T_ORT, "uz_bild")
	tw.tween_property(_img, "modulate:a", 1.0, U.T_ORT)
	tw.tween_callback(_end_wait)
	tw.tween_callback(_bild_deckt)


## Gewählt: das Cover wächst (Kurve „Ankommen“, ohne Nachfedern) und der Ring steht im Cursor-Takt
## da – im ersten Bild zu 70 %, gesetzt in T_ANTWORT; abgewählt fällt er sofort auf 30 % und geht.
func _on_focus(on: bool) -> void:
	_build()
	if _tw:
		_tw.kill()
	_tw = U.ankommen(self, U.T_ORT, "uz_cover").set_parallel(true)
	_tw.tween_property(self, "scale", Vector2.ONE * _gross(on), U.T_ORT if on else U.T_WEG)
	if on and not calm and not Leicht.active and UzTheme.focus_shine() and not U.reduziert():
		if _shine == null or not is_instance_valid(_shine):
			_shine = Shine.new()
			_clip.add_child(_shine)
		_clip.move_child(_shine, _clip.get_child_count() - 1)
		_shine.play()
	var von := maxf(_focus_t, Liste.ANTWORT_VON) if on else minf(_focus_t, Liste.ANTWORT_REST)
	_set_focus_t(von)
	_tw.tween_method(_set_focus_t, von, 1.0 if on else 0.0, U.T_ANTWORT).set_trans(Tween.TRANS_CUBIC if on else Tween.TRANS_QUAD)
	if _live:
		_live.focus(on)
	if on:
		focused_game.emit(game)


func _set_focus_t(v: float) -> void:
	_focus_t = v
	queue_redraw()


## Maus darüber (schweben.gd): derselbe Schein wie die Auswahl, nur leiser – zeigt, was ein Klick öffnet.
var _hover_t := 0.0
var _hover_tw: Tween


func zeiger_schweben(an: bool) -> void:
	if _hover_tw:
		_hover_tw.kill()
	_hover_tw = create_tween()
	_hover_tw.tween_method(func(v: float) -> void:
		_hover_t = v
		queue_redraw(), _hover_t, 1.0 if an else 0.0, U.T_ANTWORT)


## Wachsen bei Auswahl: das Maß des Bauteils, vom Grundwert verstärkt oder gedämpft.
func _scale() -> float:
	return UzTheme.focus_scale(focus_scale)


## Größe gewählt bzw. nicht gewählt; „Animationen reduzieren“: kein Wachsen.
func _gross(on: bool) -> float:
	return U.wachsen(_scale()) if on else 1.0


## Schatten, Goldband und Ring: drei Boxen für alle Cover, nur ihre Werte ändern sich je
## Zeichnung (draw_style_box legt die Form sofort an). Früher entstanden pro Cover und Bild drei
## neue StyleBoxen – beim Einblenden der Auswahl jedes Bild.
static var _sb_sh: StyleBoxFlat


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Leichter Modus: keine Spiegelung, halb so weite Schatten.
	if reflect and not Leicht.active and UzTheme.reflection():
		_draw_reflection(r)
	var rc := UzTheme.r_cover()
	var k := Leicht.SHADOW_K if Leicht.active else 1.0
	# Jede Hülle liegt mit einem weichen Schatten im Raum; die gewählte etwas mehr.
	if _sb_sh == null:
		# Mitte durchsichtig statt ausgelassen: Ohne Mitte zeichnet Godot auch den Schatten als
		# Ring – unter dem Cover blieb ein heller Spalt (auf hellen Themes deutlich zu sehen).
		_sb_sh = StyleBoxFlat.new()
		_sb_sh.bg_color = Color(0, 0, 0, 0)
	_sb_sh.set_corner_radius_all(rc)
	_sb_sh.shadow_color = Color(0, 0, 0, (0.32 + 0.22 * _focus_t) * minf(UzTheme.shadow_weite(), 1.0))
	_sb_sh.shadow_size = int((18 + 18 * _focus_t) * k)
	_sb_sh.shadow_offset = Vector2(0, (10 + 8 * _focus_t) * k)
	draw_style_box(_sb_sh, r)
	# Zartes Band im Akzent und darauf der helle Ring (im Theme: Stärke, Rahmen).
	UzTheme.draw_tile_hover(self, r, rc, _hover_t * (1.0 - minf(_focus_t, 1.0)))
	UzTheme.draw_tile_focus(self, r, rc, _focus_t)
	if caption != "" and _focus_t > 0.01:
		_draw_caption(r)


## Zeile unter dem gewählten Cover, links bündig, unter dem Rahmen des Cursors. Blendet mit der
## Auswahl ein; ist sie zu lang, endet sie mit „…“.
func _draw_caption(r: Rect2) -> void:
	var fnt := UzTheme.font("medium")
	var fs := UzTheme.size("s")
	var y := r.end.y + UzTheme.cursor_gap() + UzTheme.cursor_width() + 8.0 + fnt.get_ascent(fs)
	var w := r.size.x * 1.6
	var t := tr(caption)
	if fnt.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		while t.length() > 1 and fnt.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
			t = t.substr(0, t.length() - 1)
		t = t.strip_edges() + "…"
	draw_string(fnt, Vector2(r.position.x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted", _focus_t))


## Spiegelung: das untere Stück des Covers kopfüber, in Streifen ausgeblendet (ohne Shader).
func _draw_reflection(r: Rect2) -> void:
	var t: Texture2D = _img.texture if _img and _img.visible else null
	# Fliegt das Bild gerade (flug.gd verbirgt nur es), spiegelt sich auch nichts.
	if t == null or Flug.verborgen(_img):
		return
	var ts := t.get_size()
	if ts.x <= 0 or ts.y <= 0:
		return
	var sc := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var region := Rect2((ts - r.size / sc) * 0.5, r.size / sc)
	# Stronger than before (0.16 · 20 %): on bright images the reflection was often lost completely.
	var depth := r.size.y * REFLECT_DEPTH
	var strips := 16
	var sh := depth / strips
	var src_h := region.size.y * REFLECT_DEPTH / strips
	# Unter dem gewählten Cover steht die Zeile (caption): dort tritt die Spiegelung zurück.
	var k := (1.0 - _focus_t if caption != "" else 1.0) * spiegel
	if k <= 0.01:
		return
	for i in strips:
		var fade := 1.0 - float(i) / strips
		var a := REFLECT_ALPHA * pow(fade, 1.4) * k
		var dest := Rect2(r.position.x, r.end.y + 8 + i * sh + sh, r.size.x, -sh)
		var src := Rect2(region.position.x, region.end.y - (i + 1) * src_h, region.size.x, src_h)
		draw_texture_rect_region(t, dest, src, Color(1, 1, 1, a))


## Lebendige Kachel: Zustand neu bestimmen (die Startseite stößt das nach neuen Daten an).
func refresh_live() -> void:
	if _live:
		_live.refresh()


func activate() -> void:
	chosen.emit(game)


## Geteilte Elemente (src/ui/flug.gd): das Bild des Covers, sobald es geladen ist. Solange es
## fliegt, ist nur das Bild verborgen (hide): Ring, Schild und Spielzeit stehen nach B im ersten
## Bild wieder da, nur das Bild kommt per Flug.
func flug_bild() -> Dictionary:
	if not is_instance_valid(_img) or not _img.visible or _img.texture == null:
		return {}
	return { "node": _img, "radius": UzTheme.r_cover(), "hide": _img }


## Steuerkreuz hoch/runter: Wer die Karte baut, kann das Ziel vorgeben (Meta "uz_up" bzw.
## "uz_down" mit einem Callable, das true liefert, wenn es den Fokus selbst gesetzt hat).
func nav_ud(d: int) -> bool:
	var key := "uz_up" if d < 0 else "uz_down"
	if has_meta(key):
		var cb: Variant = get_meta(key)
		if cb is Callable and (cb as Callable).is_valid():
			return bool((cb as Callable).call())
	return false


func _on_gui_input(e: InputEvent) -> void:
	Nav.klick(self, e)
