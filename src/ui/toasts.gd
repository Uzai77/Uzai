extends CanvasLayer
## Mitteilungen oben rechts (Freund online, Erfolg, Bildschirmfoto, Fehler). Liegen über allem,
## auch über dem Guide. Eine neue Mitteilung fliegt von rechts ein und wird dabei klar; die
## anderen rücken weich nach unten. Beim Gehen gleitet sie hinaus, und die Lücke schließt sich
## weich. Eine feine Linie unten zeigt, wie lange sie noch bleibt.
##
## Nachrichten von Freunden (opts overlay) erscheinen auch über einem laufenden Spiel: dann in
## einem eigenen kleinen Fenster (toast_window.gd), das dem Spiel nie den Fokus nimmt. Ein
## Pop-up mit opts open lässt sich öffnen: in Uzai mit View, im Spiel mit der Guide-Taste.
##
## Ruhe und Platz (Plan „Gefühl“, Regel 12): In Uzai erscheint ein Pop-up frühestens U.T_RAUM nach
## dem letzten Wechsel (Ebene, Bereich, Zimmer, Spielstart; unruhe() meldet eigene Wechsel) und nie
## über dem Cursor oder über „Für dich“ – liegt dort etwas, kommt es unten rechts. Klang und
## Zeitlinie beginnen erst, wenn es wirklich erscheint.

const U := preload("res://src/ui/u.gd")
const ToastWindow := preload("res://src/ui/toast_window.gd")
const NichtStoeren := preload("res://src/core/nicht_stoeren.gd")
const W := 500.0
const GAP := 12.0
const MAX := 3
const MERK_MAX := 60           ## so viele Einträge behält die Mitteilungsliste
## Ränder: oben unter der Kopfzeile, unten über der Tastenzeile, rechts wie der Inhalt.
const TOP := 112.0
const BOTTOM := 132.0
const RIGHT := 96.0
## Spätestens so lange wartet ein Pop-up auf Ruhe (s), dann kommt es trotzdem.
const WAIT_MAX := 2.5
## In dieser Gruppe steht, was zu „Für dich“ gehört (for_you_card.gd, fuer_dich_leiste.gd) – siehe _meiden.
const GRUPPE_FUER_DICH := "uz_fuer_dich"

var _box: VBoxContainer
var history: Array = []        ## letzte Hinweise für die Mitteilungen im Guide
var unread := 0
var still := 0                 ## bei „Nicht stören“ nur in die Liste gegangen (für Tests)
## Pop-ups im eigenen Fenster zeigen, auch ohne Spiel (nur für Proben und Tests).
var force_overlay := false
var _win: Window
var _open_slot: Control         ## das jüngste Pop-up, das sich öffnen lässt
var _open_cb: Callable
## Ruhe: Zeitpunkt (in Bildzeit, _uhr), ab dem wieder Ruhe herrscht, und der zuletzt gesehene
## Zustand der Ebenen und Bereiche (ändert er sich, war das ein Wechsel). Bildzeit statt Uhr: Die
## Bewegungen laufen in Bildzeit – hängt ein Bild (Aufbau), zählt die Wartezeit nicht weiter.
var _ruhe_ab := 0.0
var _uhr := 0.0
var _zustand := ""
var _nach_ruhe_pruefen := false
## Wo die Spalte gerade steht: "oben" (rechts oben), "unten" (rechts unten) oder der Platz einer Ebene.
var spot := "oben"
var _zuletzt_sub := ""          ## Zusatz des letzten Pop-ups und wann (eben_gezeigt)
var _zuletzt_ms := -100000


func _ready() -> void:
	layer = 100
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(root)
	add_child(root)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anchor_left = 1.0
	_box.anchor_right = 1.0
	_box.offset_left = -W - 96.0
	_box.offset_right = -96
	_box.offset_top = TOP
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_box)


## Ein Wechsel beginnt (oder dauert noch sec Sekunden): Pop-ups warten danach noch U.T_RAUM.
func unruhe(sec := 0.0) -> void:
	_ruhe_ab = maxf(_ruhe_ab, _uhr + sec + U.T_RAUM)


## Ist gerade Ruhe (kein Wechsel in den letzten U.T_RAUM)?
func ruhig() -> bool:
	_beobachte()
	return _uhr >= _ruhe_ab


func _process(dt: float) -> void:
	_uhr += dt
	_beobachte()


## Wechsel erkennen, ohne dass jemand sie meldet: Ebenen auf oder zu, Bereich oder Unterbereich.
func _beobachte() -> void:
	var nav: Node = get_node_or_null("/root/Nav")
	var main: Node = get_tree().current_scene if is_inside_tree() else null
	var top: Variant = nav.call("top_layer") if nav else null
	var z := "%d|%d|%s|%s" % [(nav.get("layers") as Array).size() if nav else 0, (top as Object).get_instance_id() if top is Object else 0,
		str(main.get("current")) if main else "", _sub_of(main)]
	if z != _zustand:
		_zustand = z
		unruhe()
		_nach_ruhe_pruefen = true
	elif _nach_ruhe_pruefen and _uhr >= _ruhe_ab:
		_nach_ruhe_pruefen = false
		_ausweichen()


## Nach einem Wechsel steht die Spalte womöglich über dem neuen Cursor oder „Für dich“ (eine
## Mitteilung kam im Zimmer, dann zurück zur Startseite): Sie weicht aus – geht in T_WEG und kommt
## an der freien Stelle in T_ORT wieder.
func _ausweichen() -> void:
	if spot not in ["oben", "unten"] or _lebende() == 0 or Nav.top_layer() != null:
		return
	var vs := _box.get_viewport_rect().size
	var h := _box.size.y
	var frei := spot_frei(vs, h, _meiden())
	if frei == spot:
		return
	var tw := U.weg(_box, "uz_ausweichen")
	tw.tween_property(_box, "modulate:a", 0.0, U.T_WEG)
	tw.tween_callback(func() -> void:
		spot = frei
		if frei == "unten":
			_set_box(1.0, 1.0, -W - RIGHT, -RIGHT, -BOTTOM)
			_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		else:
			_box.grow_vertical = Control.GROW_DIRECTION_END
			_set_box(1.0, 0.0, -W - RIGHT, -RIGHT, TOP)
	)
	tw.tween_property(_box, "modulate:a", 1.0, U.T_ORT).set_trans(Tween.TRANS_CUBIC)


static func _sub_of(main: Node) -> String:
	if main == null:
		return ""
	var secs: Variant = main.get("sections")
	var cur: Variant = main.get("current")
	if secs is Dictionary and (secs as Dictionary).has(cur) and is_instance_valid((secs as Dictionary)[cur]):
		return str(((secs as Dictionary)[cur] as Object).get("sub"))
	return ""


## opts: image (URL oder Pfad), sound ("notify"), ms (Anzeigedauer), color (Farbname),
## quiet (nicht in die Liste, nur mit ausdrücklichem Klang), force (Klang auch, wenn Hinweise still sind),
## overlay (läuft ein Spiel: im eigenen Fenster über dem Spiel), open (Callable: View öffnet es),
## open_text (Wort neben dem Tastensymbol), tag (zum gezielten Wegnehmen, siehe dismiss),
## go (Callable: führt aus der Mitteilungsliste dorthin, worum es ging), go_text (Wort dazu),
## stoert (kommt von außen – Freunde, Discord, Shop: bei „Nicht stören“ nur still in die Liste),
## title_raw, sub_raw (Titel bzw. Zusatz ist fremder Text – ein Name, die Nachricht eines Freundes – und
## wird nie übersetzt; sonst übersetzt texte() ihn in die Sprache der Oberfläche)
func show_toast(title: String, sub := "", icon := "info", opts := {}) -> void:
	_zuletzt_sub = sub
	_zuletzt_ms = Time.get_ticks_msec()
	if not opts.get("quiet", false):
		merken({ "title": title, "sub": sub, "icon": icon, "image": str(opts.get("image", "")),
			"go": opts.get("go", Callable()), "go_text": str(opts.get("go_text", "Öffnen")),
			"title_raw": bool(opts.get("title_raw", false)), "sub_raw": bool(opts.get("sub_raw", false)) })
		unread += 1
	if bool(opts.get("stoert", false)) and NichtStoeren.aktiv():
		still += 1
		return
	if not is_instance_valid(_box):
		return
	var over := bool(opts.get("overlay", false)) and use_overlay()
	var box := _box
	if over:
		box = _overlay_box()
	var ms := float(opts.get("ms", 4200))
	var tint := str(opts.get("color", "warn" if icon == "warning" else "accent"))
	# Ein Platzhalter in der Spalte: Seine Höhe wächst und schrumpft weich, die Karte darin fliegt frei.
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(W, 0)
	if str(opts.get("tag", "")) != "":
		slot.set_meta("uz_tag", str(opts.tag))
	var open_cb: Callable = opts.get("open", Callable())
	var hint := ""
	if open_cb.is_valid():
		hint = "guide" if over else "view"
	var tx := texte({ "title": title, "sub": sub, "title_raw": opts.get("title_raw", false), "sub_raw": opts.get("sub_raw", false) })
	var card: Control = _card(tx[0], tx[1], icon, tint, str(opts.get("image", "")), hint, str(opts.get("open_text", "Öffnen")),
			str(opts.get("vorschau", "")))
	card.modulate.a = 0.0
	slot.add_child(card)
	box.add_child(slot)
	box.move_child(slot, 0)
	if open_cb.is_valid():
		_open_slot = slot
		_open_cb = open_cb
	# Mehr als drei: Die ältesten gehen (weich, nicht schlagartig).
	var slots := box.get_children()
	for i in range(MAX, slots.size()):
		_leave(slots[i] as Control)
	# Erst messen (umbrechender Text braucht ein Bild), dann einfliegen.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(slot) or slot.has_meta("uz_leaving"):
		return
	card.size = Vector2(W, card.get_combined_minimum_size().y)
	card.pivot_offset = Vector2(W, card.size.y * 0.5)
	var h := card.size.y + GAP
	if not over:
		# Mitten in einem Wechsel warten, bis er steht (höchstens WAIT_MAX); dann einen Platz suchen.
		var t0 := _uhr
		while not ruhig() and _uhr - t0 < WAIT_MAX:
			await get_tree().process_frame
			if not is_instance_valid(slot) or slot.has_meta("uz_leaving"):
				return
		_place_box(h)
	# Leise Hinweise (Lautstärke, Pause, „Wird gesendet …“) klingen nur, wenn ein Klang gewünscht ist.
	# Der Klang kommt mit dem Bild, nicht schon während des Wartens.
	if (Config.get_value("system.notifications", true) or opts.get("force", false)) and (not opts.get("quiet", false) or opts.has("sound")):
		Sfx.play(str(opts.get("sound", "error" if icon == "warning" else "notify")))
	var tw := U.ankommen(slot, U.T_ORT, "uz_toast").set_parallel(true)
	if not over and spot == "unten":
		# Unten wächst die Spalte nach oben: Die neue Karte bleibt dabei auf ihrer Höhe stehen (sie
		# hängt am unteren Rand ihres Platzes) und kommt nur vom Rand rechts – keine zweite Bewegung.
		tw.tween_method(func(v: float) -> void:
			if is_instance_valid(slot) and is_instance_valid(card):
				slot.custom_minimum_size.y = v
				card.position.y = v - h
		, 0.0, h, U.T_ORT)
	else:
		tw.tween_property(slot, "custom_minimum_size:y", h, U.T_ORT)
	# Die Karte kommt vom Rand rechts (Ankommen, ohne Wachsen), ihre Fläche deckend, die Deckkraft
	# folgt in T_ORT.
	tw.tween_property(card, "position:x", 0.0, U.T_ORT).from(U.weg_px(U.W_LEISTE))
	tw.tween_property(card, "modulate:a", 1.0, U.T_ORT)
	# Die Zeitlinie läuft ab, dann geht die Mitteilung.
	var lt := card.create_tween()
	lt.tween_method(func(v: float) -> void:
		if is_instance_valid(card):
			if card.has_method("set_var"):
				card.call("set_var", "rest", v)
			else:
				card.set_meta("t", v)
				card.queue_redraw()
	, 1.0, 0.0, ms / 1000.0)
	await get_tree().create_timer(ms / 1000.0).timeout
	# Schon weg (geöffnet oder von neueren verdrängt): nichts mehr zu tun.
	if is_instance_valid(slot):
		_leave(slot)


## Wo die Mitteilungen in Uzai stehen: sonst rechts oben; ist der Guide offen, rechts unter seiner
## Karte, und liegt eine Seitenleiste offen, links unten – nie über der gewählten Zeile. In diesen
## beiden Fällen ist nur Platz für eine; ältere gehen sofort. Ohne Ebene: rechts oben, außer dort
## liegen der Cursor oder „Für dich“ (spot_frei) – dann rechts unten. Stehen schon Pop-ups, bleibt
## die Spalte, wo sie ist (sie spränge sonst).
func _place_box(h := 120.0) -> void:
	var top := Nav.top_layer()
	var lspot := str(top.get_meta("uz_toast_spot", "")) if top else ""
	var vs := _box.get_viewport_rect().size
	var vh := vs.y
	var single := lspot != ""
	_box.grow_vertical = Control.GROW_DIRECTION_END
	match lspot:
		"below":
			_set_box(1.0, 0.0, -W - RIGHT, -RIGHT, minf(float(top.get_meta("uz_toast_y", 892.0)), vh - 150.0))
			spot = "below"
		"left":
			_set_box(0.0, 0.0, RIGHT, RIGHT + W, vh - 250.0)
			spot = "left"
		_:
			var wahl := spot
			if _lebende() == 0 or spot not in ["oben", "unten"]:
				wahl = spot_frei(vs, h, _meiden())
			spot = wahl
			if wahl == "unten":
				_set_box(1.0, 1.0, -W - RIGHT, -RIGHT, -BOTTOM)
				_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
			else:
				_set_box(1.0, 0.0, -W - RIGHT, -RIGHT, TOP)
	if single:
		for s in _box.get_children():
			if not (s as Control).has_meta("uz_leaving") and (s as Control).custom_minimum_size.y > 0.0:
				_leave(s as Control)


func _set_box(ax: float, ay: float, left: float, right: float, y: float) -> void:
	_box.anchor_left = ax
	_box.anchor_right = ax
	_box.anchor_top = ay
	_box.anchor_bottom = ay
	_box.offset_left = left
	_box.offset_right = right
	if ay > 0.5:
		_box.offset_bottom = y
		_box.offset_top = y - _box.get_combined_minimum_size().y
	else:
		_box.offset_top = y
		_box.offset_bottom = y + _box.get_combined_minimum_size().y


## Wie viele Pop-ups gerade zu sehen sind (nicht gehend, schon eingeflogen).
func _lebende() -> int:
	var n := 0
	for c in _box.get_children():
		if not (c as Control).has_meta("uz_leaving") and (c as Control).custom_minimum_size.y > 0.0:
			n += 1
	return n


## Was ein Pop-up nicht verdecken darf: der Cursor (Rechteck des Fokus) und „Für dich“ samt
## Überschrift (Elemente mit uz_key „fy:…“), in Schirm-Koordinaten.
func _meiden() -> Array:
	var out: Array = []
	var f := Nav.focused()
	if f and f.is_visible_in_tree():
		out.append(U.sichtbar(f))
	# Die Karten und Zeilen von „Für dich“ melden sich in einer Gruppe – vorher ging die Suche bei jeder
	# Mitteilung durch alle Elemente der Oberfläche.
	var fy := Rect2()
	for n in get_tree().get_nodes_in_group(GRUPPE_FUER_DICH):
		var c := n as Control
		if c != null and c.is_visible_in_tree():
			var r := U.sichtbar(c)
			if r.size.x > 1.0 and r.size.y > 1.0:
				fy = r if fy.size == Vector2.ZERO else fy.merge(r)
	if fy.size != Vector2.ZERO:
		# Die Überschrift „Für dich“ steht über den Karten.
		out.append(fy.grow_individual(0, 56, 0, 0))
	return out


## Platz für ein Pop-up der Höhe h: "oben" (rechts oben), wenn dort nichts aus meiden liegt, sonst
## "unten" (rechts unten) – es sei denn, auch dort läge etwas und oben nicht der Cursor.
static func spot_frei(view: Vector2, h: float, meiden: Array) -> String:
	var oben := Rect2(view.x - RIGHT - W, TOP, W, h)
	var unten := Rect2(view.x - RIGHT - W, view.y - BOTTOM - h, W, h)
	if not _trifft(oben, meiden):
		return "oben"
	if not _trifft(unten, meiden):
		return "unten"
	# Beides belegt: nie über dem Cursor (er steht als erstes in meiden).
	if not meiden.is_empty() and oben.intersects((meiden[0] as Rect2).grow(8.0)):
		return "unten"
	return "oben"


static func _trifft(r: Rect2, meiden: Array) -> bool:
	for m in meiden:
		if r.intersects((m as Rect2).grow(8.0)):
			return true
	return false


func _leave(slot: Control) -> void:
	if not is_instance_valid(slot) or slot.has_meta("uz_leaving"):
		return
	slot.set_meta("uz_leaving", true)
	var card: Control = slot.get_child(0) if slot.get_child_count() > 0 else null
	var tw := slot.create_tween()
	if card:
		# Gehen: Deckkraft ease-out (nie ease-in, das endet mit einem Ruck), ein Stück zum Rand.
		tw.set_parallel(true)
		tw.tween_property(card, "position:x", U.weg_px(U.W_LEISTE), U.T_WEG).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "modulate:a", 0.0, U.T_WEG).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.set_parallel(false)
	tw.set_speed_scale(U.tempo())
	tw.tween_property(slot, "custom_minimum_size:y", 0.0, U.T_ORT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(slot.queue_free)
	if is_instance_valid(_win) and _win.box.is_ancestor_of(slot):
		tw.tween_callback(_overlay_check.call_deferred)


# --- Über dem Spiel ---------------------------------------------------------------------------

## Pop-ups gehen ins eigene Fenster, wenn Uzai selbst nicht zu sehen ist: ein Spiel läuft (und
## der Guide ist zu) oder Uzai liegt minimiert. Nur unter Windows und mit „Pop-ups im Spiel“.
func use_overlay() -> bool:
	if force_overlay:
		return true
	if not Config.is_windows() or not bool(Config.get_value("notify.in_game", true)):
		return false
	if Launcher.in_game and not Launcher.guide_open:
		return true
	# Ein anderes Fenster liegt vorn: das eigene kleine Fenster ist dann das einzige, was man sieht.
	return get_tree().root.mode == Window.MODE_MINIMIZED or not get_tree().root.has_focus()


func _overlay_box() -> VBoxContainer:
	if not is_instance_valid(_win):
		_win = ToastWindow.new()
		add_child(_win)
	_win.appear()
	return _win.box


## Alle Pop-ups im Fenster sind gegangen: Fenster weg (bis zum nächsten).
func _overlay_check() -> void:
	if not is_instance_valid(_win):
		return
	for c in _win.box.get_children():
		if not c.is_queued_for_deletion():
			return
	_win.disappear()


## Einen Eintrag vorn in die Mitteilungsliste legen, ohne Pop-up und ohne Zähler (Erfolge und Abzeichen zeigen ihr
## eigenes Pop-up). Fehlende Felder bekommen ihren üblichen Wert, die Liste behält die letzten MERK_MAX Einträge.
func merken(e: Dictionary) -> void:
	var eintrag := { "title": "", "sub": "", "icon": "info", "at": int(Time.get_unix_time_from_system()), "image": "",
		"go": Callable(), "go_text": "Öffnen", "title_raw": false, "sub_raw": false }
	eintrag.merge(e, true)
	history.push_front(eintrag)
	history = history.slice(0, MERK_MAX)


## Titel und Zusatz einer Mitteilung, wie sie zu zeigen sind: [titel, zusatz]. Feste Texte in der Sprache
## der Oberfläche, fremde (title_raw, sub_raw) unverändert. Wer das Ergebnis zeigt, nimmt seine Beschriftung
## von der Übersetzung aus – sonst würde aus „Später?“ eines Freundes „Later?“.
func texte(h: Dictionary) -> Array:
	var t := str(h.get("title", ""))
	var s := str(h.get("sub", ""))
	return [t if t == "" or bool(h.get("title_raw", false)) else tr(t), s if s == "" or bool(h.get("sub_raw", false)) else tr(s)]


## Mitteilungsliste leeren (Glocke, Y). Gibt die alte Liste zurück – für „Rückgängig“.
func clear_history() -> Array:
	var old := history.duplicate()
	history = []
	unread = 0
	return old


## Rückgängig: die entfernten Mitteilungen wieder vorn einreihen (neuere bleiben davor).
func restore_history(old: Array) -> void:
	history = (history + old).slice(0, MERK_MAX)


## Kam eben schon ein Pop-up mit diesem Zusatz? (Damit eine zentrale Meldung nicht doppelt neben der der Stelle steht.)
func eben_gezeigt(sub: String, ms := 1500) -> bool:
	return sub != "" and sub == _zuletzt_sub and Time.get_ticks_msec() - _zuletzt_ms < ms


## Pop-ups mit diesem tag weichen lassen (etwa wenn der Chat dazu aufgeht).
func dismiss(tag: String) -> void:
	var boxes: Array = [_box]
	if is_instance_valid(_win):
		boxes.append(_win.box)
	for b in boxes:
		if not is_instance_valid(b):
			continue
		for c in (b as Node).get_children():
			if str(c.get_meta("uz_tag", "")) == tag:
				_leave(c as Control)


## Das jüngste Pop-up mit „Öffnen“ öffnen (View in Uzai). true, wenn eins zu sehen war.
func open_latest() -> bool:
	if not is_instance_valid(_open_slot) or _open_slot.has_meta("uz_leaving") or not _open_cb.is_valid():
		return false
	var cb := _open_cb
	_leave(_open_slot)
	_open_slot = null
	_open_cb = Callable()
	Sfx.play("select")
	cb.call()
	return true


## vorschau: an image from the message (URL), shown small below the text – instead of just „Bild“.
func _card(title: String, sub: String, icon: String, tint: String, image: String, hint := "", hint_text := "", vorschau := "") -> PanelContainer:
	var card := PanelContainer.new()
	# Eine schwebende Fläche mit feinem Rand und weichem, dunklem Schatten.
	var sb := UzTheme.box(UzTheme.col("surface_hi"), UzTheme.radius + 6, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 20
	sb.content_margin_right = 26
	sb.content_margin_top = 18
	sb.content_margin_bottom = 20
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 34
	sb.shadow_offset = Vector2(0, 12)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(W, 0)
	var row := U.hbox(18)
	card.add_child(row)
	var ib := Control.new()
	ib.custom_minimum_size = Vector2(52, 52) if image != "" else Vector2(40, 40)
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var ic := U.icon(icon, 30, tint)
	U.full_rect(ic)
	ib.add_child(ic)
	row.add_child(ib)
	if image != "":
		var bild := U.rounded_image(12.0)
		U.full_rect(bild)
		ib.add_child(bild)
		var cb := func(t: Texture2D) -> void:
			if is_instance_valid(bild) and t:
				bild.texture = t
				ic.visible = false
		if image.begins_with("http"):
			Media.url_texture(image, 128, cb)
		else:
			Media.file_texture(image, 128, cb)
	var col := U.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# Titel und Zusatz kommen fertig übersetzt (texte).
	var t := U.label(title, "m", "text", "ui_bold", true)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.custom_minimum_size = Vector2(W - 140.0, 0)
	col.add_child(t)
	if sub != "":
		var s := U.label(sub, "s", "muted", "regular", true)
		s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		s.custom_minimum_size = Vector2(W - 140.0, 0)
		if hint != "":
			s.max_lines_visible = 3
		col.add_child(s)
	if vorschau.begins_with("https://"):
		# Feste Fläche von Anfang an: Die Karte wird einmal gemessen (show_toast) – ein später wachsendes Bild ragte heraus.
		var vb := U.rounded_image(10.0)
		vb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		vb.custom_minimum_size = Vector2(240, 135)
		vb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(U.spacer(0, 6, false))
		col.add_child(vb)
		Media.url_texture(vorschau, 480, func(t: Texture2D) -> void:
			if is_instance_valid(vb) and t:
				vb.texture = t)
	# Lässt sich öffnen: kleines Tastensymbol darunter (View in Uzai, Guide-Taste im Spiel).
	if hint != "":
		var hb := U.hint(hint, hint_text)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(U.spacer(0, 4, false))
		col.add_child(hb)
	row.add_child(col)
	# Feine Zeitlinie am unteren Rand (auf der Fläche, unter dem Inhalt).
	card.set_meta("t", 1.0)
	card.draw.connect(func() -> void:
		var k: float = card.get_meta("t", 1.0)
		var w := (card.size.x - 48.0) * k
		if w > 1.0:
			card.draw_rect(Rect2(24.0, card.size.y - 4.0, w, 2.0), UzTheme.col(tint, 0.32))
	)
	return card
