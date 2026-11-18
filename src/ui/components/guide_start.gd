extends RefCounted
## Guide › Start, der Teil nach dem Spielblock – in jeder Lage (docs/PLAN_GUIDE3.md):
## - Kontext zum Spiel: Spielzeit heute bzw. insgesamt in der Zeile unter dem Titel, „Erfolge“ mit
##   dem nächsten bzw. dem eben freigeschalteten Erfolg, „Aufnahmen“ mit dem neuesten Clip dieses
##   Spiels (Vorschaubild) – jede Zeile nur, wenn sie Inhalt hat.
## - Neues: die neuen Mitteilungen einzeln (höchstens NOTES_MAX) und Downloads, solange etwas lädt.
## - Die Schnellleiste ganz unten: Mikro, Lautstärke, Controller, Ruhemodus, Ausschalten als runde
##   Symbolknöpfe mit einem Wort darunter – ein Druck, wie im Kontrollzentrum der PS5 und beim
##   Halten der Home-Taste der Switch. Was sie zeigt, steht nicht noch einmal unter „Mehr …“.
## Die Regeln sind reine Funktionen (tests/logic_guidestart.gd); den Aufbau ruft guide.gd.

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const People := preload("res://src/ui/components/guide_people.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")
const GuidePads := preload("res://src/ui/components/guide_pads.gd")
const MixerSheet := preload("res://src/ui/layers/mixer_sheet.gd")
const InstallFlow := preload("res://src/ui/install_flow.gd")
const InstallsS := preload("res://src/core/installs.gd")
const Main := preload("res://src/main.gd")

const NOTES_MAX := 2            ## so viele neue Mitteilungen stehen im Start einzeln (wenn an)
const MITTEILUNGEN_IM_KOPF := true   ## Mitteilungen als Glocke im Kopf des Guides statt einzeln im Start
const FRESH_S := 86400          ## so jung muss eine Aufnahme sein, um ohne Spiel im Start zu stehen
const THUMB := Vector2(56, 32)  ## Vorschaubild vor „Aufnahmen“
const QUICK_PX := 48            ## Durchmesser der Knöpfe in der Schnellleiste
const STRIP_H := 96.0           ## Höhe der Schnellleiste samt Haarlinie (unten in der Leiste, fest)


# --- Regeln (rein) ------------------------------------------------------------------------------

## Zeile unter dem Titel ohne Spiel: wann zuletzt und wie viel („Zuletzt gestern  ·  14 Std.“,
## „Gerade gespielt  ·  1 Std.“). Ohne Zeitpunkt (Spielzeit aus dem Launcher) „Zuletzt
## gespielt  ·  14 Std.“, ohne alles „Noch nicht gespielt“. Schon übersetzt.
static func stage_sub(last: int, total: int) -> String:
	var when := U.ago(last) if last > 0 else ""
	var dur := ("  ·  " + People.dur(total)) if total > 0 else ""
	if when == "":
		if total <= 0:
			return TranslationServer.translate("Noch nicht gespielt")
		return TranslationServer.translate("Zuletzt gespielt") + dur
	if when == "Gerade eben":
		return TranslationServer.translate("Gerade gespielt") + dur
	return TranslationServer.translate("Zuletzt %s") % U.lower_first(TranslationServer.translate(when)) + dur


## Spielzeit unter dem Balken im Spiel: „Heute 1,2 Std.“, sobald heute schon vor dieser Sitzung
## gespielt wurde (sonst sagte es dasselbe wie die Sitzungsuhr), dazu „Insgesamt 14 Std.“ ab einer
## Stunde; ohne beides "".
static func time_bit(today_before: int, session: int, total: int) -> String:
	var bits := PackedStringArray()
	if today_before >= 60:
		bits.append(TranslationServer.translate("Heute %s") % People.dur(today_before + session))
	if total >= 3600:
		bits.append(TranslationServer.translate("Insgesamt %s") % People.dur(total))
	return "  ·  ".join(bits)


## Heute schon gespielt (abgeschlossene Runden, Sekunden) – gid "" zählt alle Spiele.
static func today_secs(sessions: Array, gid: String, now: int, bias_min: int) -> int:
	return int(People.week(sessions, gid, now, bias_min)[6])


## Welcher Erfolg in der Zeile steht: der jüngste, der in dieser Sitzung kam (ab since) –
## { kind: "neu", a } –, sonst der häufigste offene, der nicht geheim ist – { kind: "naechster", a }
## (in den meisten Spielen der nächste Schritt der Geschichte). {} ohne passenden.
static func pick_achievement(list: Array, since: int) -> Dictionary:
	var newest := {}
	var easiest := {}
	for a in list:
		if not (a is Dictionary):
			continue
		var d: Dictionary = a
		if bool(d.get("unlocked", false)):
			if since > 0 and int(d.get("date", 0)) >= since and int(d.get("date", 0)) > int(newest.get("date", -1)):
				newest = d
		elif not bool(d.get("hidden", false)) and str(d.get("title", "")) != "":
			if easiest.is_empty() or float(d.get("rarity", -1.0)) > float(easiest.get("rarity", -1.0)):
				easiest = d
	if not newest.is_empty():
		return { "kind": "neu", "a": newest }
	if not easiest.is_empty():
		return { "kind": "naechster", "a": easiest }
	return {}


## Text hinter „Erfolge“: „Neu: Godrick der Verpflanzte“ bzw. „Als Nächstes: Malenia“ (schon übersetzt).
static func achievement_line(pick: Dictionary) -> String:
	if pick.is_empty():
		return ""
	var a: Dictionary = pick.a
	var key := "Neu: %s" if str(pick.kind) == "neu" else "Als Nächstes: %s"
	return TranslationServer.translate(key) % str(a.get("title", ""))


## Neue Mitteilungen für den Start: die jüngsten unread, ohne Abzeichen, höchstens max_n.
static func notes(history: Array, unread: int, max_n := NOTES_MAX) -> Array:
	if unread <= 0:
		return []
	return history.filter(func(h) -> bool: return h is Dictionary and str((h as Dictionary).get("kind", "")) != "abzeichen").slice(0, mini(unread, max_n))


## Zeile „Downloads“ aus Installs.list() (laufende zuerst): { extra, value, active } oder {} ohne
## Einträge. extra: der vorderste mit Prozent, value: „2 aktiv“ ab zwei bzw. „Fertig“, wenn nichts
## mehr läuft.
static func downloads_line(items: Array) -> Dictionary:
	if items.is_empty():
		return {}
	var first: Dictionary = items[0] if items[0] is Dictionary else {}
	var active := items.filter(func(e) -> bool: return e is Dictionary and not (str((e as Dictionary).get("phase", "")) in InstallsS.ENDED)).size()
	var extra := str(first.get("title", ""))
	var frac := float(first.get("frac", -1.0))
	if active > 0 and frac >= 0.0:
		extra += "  ·  %d %%" % int(round(clampf(frac, 0.0, 1.0) * 100.0))
	var value := ""
	if active > 1:
		value = TranslationServer.translate("%d aktiv") % active
	elif active == 0:
		value = TranslationServer.translate("Fertig") if str(first.get("phase", "")) == "done" else ""
	return { "extra": extra, "value": value, "active": active }


## Ist die Aufnahme jung genug für den Start ohne Spiel (heute)?
static func fresh(it: Dictionary, now: int) -> bool:
	return not it.is_empty() and now - int(it.get("mtime", 0)) < FRESH_S


## Knöpfe der Schnellleiste, in dieser Reihenfolge. ctx: { mic (Windows-Mikrofon oder Discord
## schaltbar), volume (Mixer da), pads (Controller verbunden), rest (Ruhemodus da) }.
static func quick_ids(ctx: Dictionary) -> Array:
	var out: Array = []
	if bool(ctx.get("mic", false)):
		out.append("mic")
	if bool(ctx.get("volume", false)):
		out.append("volume")
	if bool(ctx.get("pads", false)):
		out.append("pads")
	if bool(ctx.get("rest", false)):
		out.append("rest")
	out.append("power")
	return out


static func quick_context(g: Control) -> Dictionary:
	var main: Main = g.main
	return { "mic": (Config.is_windows() and Helper.available) or Library.demo or Voice.ready_(),
		"volume": Config.is_windows() or Library.demo, "pads": not Pads.pads.is_empty(),
		"rest": main != null and main.rest != null }


## Mikro aus? Windows-Mikrofon oder das eigene in Discord (wie im Schnellmenü).
static func mic_muted() -> bool:
	return Mixer.mic_aus()


# --- Aufbau: Kontext und Neues ---------------------------------------------------------------------

## Zeilen zum laufenden Spiel: Erfolge (sobald bekannt) und die neueste Aufnahme dieses Spiels.
## Leer, wenn nichts da ist – und ohne Spiel.
static func context_rows(g: Control) -> Array:
	var out: Array = []
	if not Launcher.in_game or Launcher.is_app(Launcher.current):
		return out
	var main: Main = g.main
	var game: Dictionary = Launcher.current
	var res: Dictionary = Achievements.cached(game)
	var total := int(res.get("total", 0))
	if total > 0:
		var since := int(Time.get_unix_time_from_system()) - Launcher.elapsed() if Launcher.elapsed() > 0 else 0
		var pick := pick_achievement(res.get("list", []) if res.get("list") is Array else [], since)
		var r = GuideRow.new().setup(TranslationServer.translate("Erfolge"), "trophy", achievement_line(pick), "%d / %d" % [int(res.get("unlocked", 0)), total])
		r.own_text = true
		r.chevron = true
		if str(pick.get("kind", "")) == "neu":
			r.icon_color = "accent"
		r.set_meta("uz_key", "c:ach")
		r.set_meta("uz_hint_a", "Alle Erfolge")
		r.activated.connect(func() -> void: main.open_game_achievements(game))
		out.append(r)
	var mine: Array = Capture.for_game(game, 1)
	if not mine.is_empty():
		out.append(capture_row(g, mine[0]))
	return out


## „Aufnahmen · Neuester Clip · vor 3 Min.“ mit Vorschaubild; A öffnet die Galerie bei dieser Aufnahme.
static func capture_row(g: Control, it: Dictionary) -> Control:
	var main: Main = g.main
	var r = GuideRow.new().setup(TranslationServer.translate("Aufnahmen"), "video", TranslationServer.translate(GuideGame.capture_line(it)))
	r.own_text = true
	r.chevron = true
	r.lead = _thumb(it)
	r.set_meta("uz_key", "c:cap")
	r.set_meta("uz_hint_a", "Ansehen")
	var path := str(it.get("path", ""))
	r.activated.connect(func() -> void: main.open_captures(path))
	return r


## Kleines Vorschaubild einer Aufnahme (Foto: die Datei selbst, Clip: Capture.thumb im Hintergrund).
static func _thumb(it: Dictionary) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = THUMB
	p.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), 2))
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := U.icon("video" if str(it.get("kind", "")) == "clip" else "camera", 18, "faint")
	ic.position = (THUMB - Vector2(18, 18)) * 0.5
	p.add_child(ic)
	var tr_ := TextureRect.new()
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(tr_)
	tr_.modulate.a = 0.0
	p.add_child(tr_)
	var wt: WeakRef = weakref(tr_)
	var put := func(t: Texture2D) -> void:
		var r: TextureRect = wt.get_ref()
		if r and t:
			r.texture = t
			U.ankommen(r, U.T_ORT, "uz_thumb").tween_property(r, "modulate:a", 1.0, U.T_ORT)
	var path := str(it.get("path", ""))
	if str(it.get("kind", "")) == "clip":
		Capture.thumb(path, func(tp: String) -> void:
			if tp != "" and wt.get_ref():
				Media.file_texture(tp, 160, put)
		)
	elif path != "":
		Media.file_texture(path, 160, put)
	return p


## Neues: Downloads (solange es welche gibt). Mitteilungen stehen als Glocke oben im Kopf.
static func news_rows(g: Control) -> Array:
	var out: Array = []
	var main: Main = g.main
	var k := 0
	for h in ([] if MITTEILUNGEN_IM_KOPF else notes(Toasts.history, Toasts.unread)):
		var hh: Dictionary = h
		var tx: Array = Toasts.texte(hh)
		var nr = GuideRow.new().setup(str(tx[0]), str(hh.get("icon", "info")), str(tx[1]),
				TranslationServer.translate(U.ago(int(hh.get("at", 0)))))
		nr.own_text = true
		nr.icon_color = "accent"
		nr.set_meta("uz_key", "n:%d" % k)
		# Mit Ziel (Chat, Spiel, Erfolge) führt A dorthin, sonst in die ganze Liste.
		var has_go := (hh.get("go", Callable()) as Callable).is_valid()
		nr.set_meta("uz_hint_a", str(hh.get("go_text", "Öffnen")) if has_go else "Alle")
		nr.activated.connect(func() -> void:
			Toasts.unread = 0
			if not main.open_note(hh):
				main.open_notifications()
			g._update_tab_dots()
			# Gelesen: beim Zurückkommen nicht mehr einzeln.
			g._dirty = true
		)
		out.append(nr)
		k += 1
	if not Installs.items.is_empty():
		var dl := downloads_row(g)
		if dl:
			out.append(dl)
	return out


## Zeile „Downloads“; guide.gd führt sie nach (Installs.changed), statt den Reiter neu zu bauen.
static func downloads_row(g: Control) -> Control:
	var d := downloads_line(Installs.list())
	if d.is_empty():
		return null
	var main: Main = g.main
	var r = GuideRow.new().setup(TranslationServer.translate("Downloads"), "download", str(d.extra), str(d.value))
	r.own_text = true
	r.chevron = true
	r.icon_color = "accent" if int(d.active) > 0 else "muted"
	r.set_meta("uz_key", "n:dl")
	r.activated.connect(func() -> void: InstallFlow.open_downloads(main))
	g._dl_row = r
	return r


## Stand der Zeile „Downloads“ nachführen (Fortschritt, fertig); ohne Zeile nichts.
static func update_downloads(g: Control) -> void:
	var r: Control = g._dl_row
	if r == null or not is_instance_valid(r):
		return
	var d := downloads_line(Installs.list())
	if d.is_empty():
		return
	r.call("set_extra", str(d.extra))
	r.call("set_value", str(d.value))


# --- Schnellleiste ---------------------------------------------------------------------------------

## Die Leiste: eine Haarlinie, darunter runde Symbolknöpfe gleichmäßig verteilt, je ein Wort
## darunter. Sie steht fest unten in der Leiste über den Tastenhinweisen (guide.gd _set_strip) –
## immer zu sehen, auch wenn die Liste rollt. Links/rechts wandert in der Leiste (uz_row),
## hoch/runter verlässt sie; die zuletzt gewählte bleibt gemerkt (uz_mem).
static func quick_strip(g: Control) -> Control:
	var box := U.vbox(0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(Liste.linie(10))
	var row := U.hbox(6)
	row.set_meta("uz_group", "guide:schnell")
	row.set_meta("uz_row", true)
	row.set_meta("uz_mem", true)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var first := true
	for id in quick_ids(quick_context(g)):
		var item := _quick_item(g, str(id))
		if first:
			(item.get_child(0) as Control).set_meta("uz_entry", true)
			first = false
		row.add_child(item)
	box.add_child(row)
	return box


## Ein Knopf der Leiste: [Symbol, Wort, Hinweis A, Handlung] je Kennung.
static func quick_tile(g: Control, id: String) -> Array:
	var main: Main = g.main
	match id:
		"mic":
			var muted := mic_muted()
			return ["mic_off" if muted else "mic", "Mikro aus" if muted else "Mikro", "Mikro an" if muted else "Mikro aus", func() -> void:
				await Mixer.toggle_mic()]
		"volume":
			return ["volume", "Lautstärke", "Mixer", func() -> void: MixerSheet.open_for(main)]
		"pads":
			var pads: Array = Pads.pads
			var low := pads.any(func(p) -> bool: return g.pad_low(p))
			return ["controller", "Akku schwach" if low else "Controller", "Controller", func() -> void:
				if Pads.pads.size() == 1:
					GuidePads.open_pad(main, Pads.pads[0])
				else:
					GuidePads.open_all(main)]
		"rest":
			return ["moon", "Ruhemodus", "Ruhemodus", func() -> void:
				var rest: Node = main.rest
				if rest:
					rest.enter("guide")
				else:
					g.close()]
		"power":
			return ["power", "Ausschalten", "Ausschalten", func() -> void: main.open_power()]
	return []


static func _quick_item(g: Control, id: String) -> Control:
	var d := quick_tile(g, id)
	var col := U.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b: Button = g._round(str(d[0]), QUICK_PX)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.set_meta("uz_key", "qs:" + id)
	b.set_meta("uz_hint_a", str(d[2]))
	b.pressed.connect(d[3])
	col.add_child(b)
	var l := U.label(str(d[1]), "cap", "muted", "medium")
	l.clip_text = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	if id == "mic":
		g._mic_btn = b
		g._mic_cap = l
		_mic_look(b, mic_muted())
	elif id == "pads" and str(d[1]) == "Akku schwach":
		U.set_label_color(l, "warn")
	return col


## Mikro aus: das Symbol in der Warnfarbe (ein echter Zustand), sonst wie jeder Knopf.
static func _mic_look(b: Button, muted: bool) -> void:
	if not is_instance_valid(b) or not b.has_meta("uz_kf"):
		return
	var f: Dictionary = b.get_meta("uz_kf")
	f.icon = UzTheme.col("warn") if muted else UzTheme.col("text")
	U.knopf_stand(b, float(b.get_meta("uz_kt", 0.0)))


## Mikro umgeschaltet (Mixer.mic_changed): Symbol, Wort und Hinweis nachführen, ohne Neuaufbau.
static func set_mic_state(g: Control, muted: bool) -> void:
	var b: Button = g._mic_btn
	if b == null or not is_instance_valid(b):
		return
	b.icon = Icons.tex("mic_off" if muted else "mic", int(QUICK_PX * 0.4))
	b.set_meta("uz_hint_a", "Mikro an" if muted else "Mikro aus")
	_mic_look(b, muted)
	var l: Label = g._mic_cap
	if l and is_instance_valid(l):
		l.text = "Mikro aus" if muted else "Mikro"
	if b.has_focus():
		Nav.focus_moved.emit(b)
