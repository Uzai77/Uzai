extends Control
## Grundlage für die Bereiche oben (Spiele, Erfolge, Freunde, Musik, Shop, Einstellungen).

const U := preload("res://src/ui/u.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const ProgressBarUz := preload("res://src/ui/components/progress_bar.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")
const LeerBuehne := preload("res://src/ui/components/leer_buehne.gd")

const GUTTER := 96

var id := ""
var title := ""
var icon_name := ""
var sub := ""
const Main := preload("res://src/main.gd")
var main: Main
var chips_slot: Control = null    ## eigener Platz für die Unterbereiche (sonst unter den Reitern)
var chip_counts := true           ## Anzahl klein neben jedem Unterbereich
var own_subnav := false           ## Unterbereiche zeigt der Bereich selbst (Einstellungen: Liste links)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Config.changed.connect(_on_config_for_build)


# --- Neuaufbau nur bei Bedarf ----------------------------------------------------------------
# Früher baute jeder Wechsel (LT/RT) den Bereich komplett neu, auch ohne jede Änderung – Videos,
# Erfolge und Filme kosteten so 2–3 verlorene Bilder pro Wechsel. Bereiche, die ihre Datenquellen
# kennen, schalten keep_built ein und melden Änderungen über mark_stale(); dann baut main.goto
# nur neu, wenn sich etwas geändert hat, der Unterbereich ein anderer ist oder der letzte Aufbau
# länger als 10 Minuten her ist (Zeitangaben wie „Heute“).

var keep_built := false
var stale_keys: PackedStringArray = []   ## Einstellungen (Anfänge der Schlüssel), die den Bereich betreffen
var _changed_since := true
var _built_sub := ""
var _built_at := -1000000

const KEEP_MS := 600000


func mark_stale(_a: Variant = null, _b: Variant = null) -> void:
	_changed_since = true


func _on_config_for_build(key: String) -> void:
	if stale_keys.is_empty() or Array(stale_keys).any(func(p: String) -> bool: return key.begins_with(p)):
		_changed_since = true


## Für main.goto: muss der Bereich beim Betreten neu gebaut werden?
func needs_build() -> bool:
	if prebuilt:
		# Unsichtbar vorgebaut (auch Bereiche ohne keep_built): nur neu, wenn sich seitdem etwas
		# geändert hat.
		return _changed_since or sub != _built_sub or get_child_count() == 0
	return not keep_built or _changed_since or sub != _built_sub or get_child_count() == 0 \
		or Time.get_ticks_msec() - _built_at > KEEP_MS


## Am Anfang von build() aufrufen: der Stand gilt jetzt als aufgebaut.
func mark_built() -> void:
	_changed_since = false
	_built_sub = sub
	_built_at = Time.get_ticks_msec()


# --- Vorbauen beim Start ---------------------------------------------------------------------
# Während der Startanimation (und kurz danach, solange man auf der Startseite bleibt) baut main
# jeden Bereich einmal unsichtbar auf (main._prebuild): Der erste Wechsel mit LT/RT zeigt dann
# gleich die fertige Seite statt „wird geladen“. prefetch() stößt vorher das Laden der Daten an
# (was sonst erst on_enter täte), data_ready() sagt, ob sie da sind (oder das Laden gescheitert
# ist). Ändern sich die Daten danach, meldet der Bereich das über mark_stale() – dann baut main
# unsichtbar noch einmal bzw. goto beim Betreten wie bisher.

var prebuilt := false             ## unsichtbar vorgebaut, noch nicht betreten


## Daten für den ersten Besuch anstoßen (parallel, ohne Aufbau). Darf nichts Sichtbares ändern.
func prefetch() -> void:
	pass


## Sind die Daten für den ersten Unterbereich da (oder ist das Laden gescheitert)?
func data_ready() -> bool:
	return true


## Unsichtbar aufbauen, so wie main.goto den Bereich beim Betreten aufbauen würde: erster
## Unterbereich, vorn. Läuft der Bereich, ohne sichtbar zu sein (visible = false).
func prebuild() -> void:
	var subs: Array = subtabs()
	sub = str(subs[0].id) if not subs.is_empty() else ""
	reset_position()
	mark_built()
	build()
	prebuilt = true


## Vorgebaut und noch aktuell (keine Änderung seitdem, erster Unterbereich noch derselbe)?
func prebuilt_fresh() -> bool:
	if not prebuilt or _changed_since or get_child_count() == 0:
		return false
	var subs: Array = subtabs()
	return _built_sub == (str(subs[0].id) if not subs.is_empty() else "")


## Betreten ohne Neuaufbau: was beim Verlassen zurückgesetzt wurde, wieder herstellen
## (etwa das Hintergrundbild zur gewählten Karte).
func reenter() -> void:
	pass


## [{ id, label, count? }]
func subtabs() -> Array:
	return []


## Alte oder andere Namen eines Unterbereichs auf den heutigen abbilden (z. B. nach einem Umbau).
func resolve_sub(sub_id: String) -> String:
	return sub_id


func build() -> void:
	pass


func on_enter() -> void:
	pass


func on_leave() -> void:
	pass


## Was B im Inhalt tut (Hinweisleiste): eine Ebene hoch zu Unterbereichen bzw. Reitern.
## Bereiche mit eigenen Unterseiten (handle_back) sagen „Zurück“.
func back_hint() -> String:
	return "Nach oben"


## Die Gruppe (Meta uz_group: Reihe, Raster), in der ein Element liegt.
func _group_of(c: Node) -> Control:
	var n := c.get_parent()
	while n and n != self:
		if n is Control and n.has_meta("uz_group"):
			return n
		n = n.get_parent()
	return null


static func _find_group(root: Node, group: String) -> Control:
	for ch in root.get_children():
		if ch is Control and str(ch.get_meta("uz_group", "")) == group:
			return ch
		var r := _find_group(ch, group)
		if r:
			return r
	return null


func focus_default() -> void:
	var d := Nav.default_in(self)
	if d:
		Nav.focus(d, true)


## Läuft gerade ein Wechsel des Bereichs (hinein oder hinaus) oder ein Ortswechsel in ihm? Dann
## baut ein Bereich nicht dazwischen neu (neue Daten warten das Ende ab).
func im_uebergang() -> bool:
	if has_meta("uz_skip"):
		return true
	var h: Variant = get_meta("uz_abgang_h") if has_meta("uz_abgang_h") else null
	if h != null and is_instance_valid(h) and h is Control and not (h as Control).is_queued_for_deletion():
		return true
	for k in ["uz_sec", "uz_ankunft", "uz_slide"]:
		var t: Variant = get_meta(k) if has_meta(k) else null
		if t != null and is_instance_valid(t) and t is Tween and (t as Tween).is_valid() and (t as Tween).is_running():
			return true
	return false


## Bereich neu betreten (LT/RT) oder anderer Unterbereich (LB/RB): vorn anfangen statt an der
## zuletzt gewählten Stelle. Vergisst die gemerkte Auswahl der Reihen (uz_mem) und das eigene
## Gedächtnis der Bereiche: _last_by_sub (Spiele: Karte je Unterbereich), _row_mem (Videos, Filme:
## Karte je Reihe). Bereiche mit weiterem Gedächtnis überschreiben das und rufen super() auf.
func reset_position() -> void:
	Nav.forget_in(self)
	for k in ["_last_by_sub", "_row_mem"]:
		var mem: Variant = get(k)
		if mem is Dictionary:
			(mem as Dictionary).clear()


## Hinweis, wenn ein Bereich (noch) nichts zeigt. Drei Arten, damit Laden, Fehler und Leere nicht
## alle wie ein riesiger Spieltitel aussehen:
##   "leer"   – große Überschrift, Satz, Knöpfe zum Einrichten (wie bisher),
##   "laden"  – leise Zeile über Platzhalter-Karten, die sanft schimmern (wie PS5 und Xbox; dieselbe
##              Komponente wie überall, components/skeleton.gd), darunter der Satz; Knöpfe klein,
##   "fehler" – Symbol in runder Glasfläche, ruhige Überschrift (statt 54 px), Satz, „Neu laden“.
func empty_state(head: String, text: String, buttons: Array, kind := "leer") -> Control:
	var m := U.margin(GUTTER, 60, GUTTER, 40)
	var col := U.vbox(22)
	col.custom_minimum_size = Vector2(900, 0)
	m.add_child(col)
	match kind:
		"laden":
			var hl := U.label(head, "l", "muted", "medium")
			hl.clip_text = false
			col.add_child(hl)
			col.add_child(Skeleton.cards(5, UzTheme.cover_size()))
			col.add_child(U.label(text, "m", "faint", "regular", true))
		"fehler":
			m.add_theme_constant_override("margin_top", 120)
			var ic := PanelContainer.new()
			ic.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("glass_hi"), 999))
			ic.custom_minimum_size = Vector2(96, 96)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cc := CenterContainer.new()
			cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cc.add_child(U.icon("warning", 44, "warn"))
			ic.add_child(cc)
			col.add_child(ic)
			col.add_child(U.label(head, "xl", "text", "bold", true))
			var pe := U.label(text, "m", "muted", "regular", true)
			pe.custom_minimum_size = Vector2(900, 0)
			col.add_child(pe)
		_:
			var h := U.label(head, "xxl", "text", "black", true)
			col.add_child(h)
			var p := U.label(text, "l", "muted", "regular", true)
			p.custom_minimum_size = Vector2(1000, 0)
			col.add_child(p)
	var row := U.hbox(16)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(U.spacer(0, 10, false))
	col.add_child(row)
	for b in buttons:
		var first: bool = b == buttons[0]
		var btn := U.button(str(b[0]), str(b[1]), "primary" if first and kind != "laden" else "normal")
		btn.pressed.connect(b[2])
		if first:
			btn.set_meta("uz_default", true)
		row.add_child(btn)
	return m


## Noch nicht eingerichtet (kein Konto, keine Spiele, Musik aus): die ruhige Bühne mit der Form des
## späteren Inhalts und einem Knopf, der gleich einrichtet (components/leer_buehne.gd). Ist danach
## eingerichtet (o.fertig), baut der Bereich neu und der Inhalt kommt im Takt herein.
## o: wie LeerBuehne.setup; host ist dieser Bereich.
func leer_buehne(o: Dictionary) -> Control:
	if not o.has("host"):
		o["host"] = self
	var b := LeerBuehne.new().setup(o)
	U.full_rect(b)
	return b


func section_title(text: String, extra := "") -> Control:
	var m := U.margin(GUTTER, 0, GUTTER, 0)
	var row := U.hbox(14)
	m.add_child(row)
	var l := U.label(text, "l", "text", "bold")
	l.clip_text = false
	row.add_child(l)
	if extra != "":
		var e := U.label(extra, "m", "faint", "medium")
		e.clip_text = false
		row.add_child(e)
	return m


func scroll_v(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc
