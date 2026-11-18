extends "res://src/ui/layers/sheet.gd"
## „Für dich“ als Seitenleiste: Start (Menü) auf der Startseite lässt sie von rechts hereingleiten –
## gebaut wie jede Seitenleiste (sheet.gd, Takt T_RAUM, dieselbe Fläche); links liegen Guide und
## Freunde. Oben ein großer „Weiter“-Moment (die Runde eben, sonst Weiterspielen mit Bild, sonst die
## große Karte der Mischung), darunter ruhige Abschnitte in der Listen-Sprache des Guides – Freunde
## spielen, Fast geschafft, Weiterschauen, Läuft gerade (mit ⏮ ⏯ ⏭), Neu in deiner Bibliothek,
## Wiederentdecken (auch „Vor einem Jahr“), Neuigkeiten, Wunschliste im Angebot, Deine Woche. Jeder
## Abschnitt nur mit Inhalt (ForYou.ordnen). A führt aus und schließt die Leiste, Y bei Spielen zur
## Spielseite; Start oder B schließt.
## Daten: die Kandidaten rechnet die Startseite vorab (games.gd, for_you.gd gather/pick), die
## übrigen Zeilen kommen beim Öffnen aus dem, was schon da ist (ForYou.leiste_extra).
## Öffnen: games.menu_taste() (main.gd, Zweig „menu“).

const ForYou := preload("res://src/ui/components/for_you.gd")
const ForYouCard := preload("res://src/ui/components/for_you_card.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")

const BREITE := 640.0
## Karte so breit wie die Liste: Leiste ohne ihre Ränder (2 × 44) und die der Liste (2 × 8).
const KARTE_W := BREITE - 88.0 - 16.0
const GROSS_H := 224.0
const ZEILE_H := 58                  ## Zeilen mit Bild vorn (Cover, Profilbild)
const COVER := Vector2(32, 42)
const KNOPF := 44                    ## ⏮ ⏯ ⏭ in „Läuft gerade“

## { big: Kandidat oder {}, small: [Kandidaten] } – wie ForYou.pick (die große Karte, falls es
## nichts zum Weiterspielen gibt).
var plan: Dictionary = {}
## Alle Kandidaten (ForYou.gather), von der Startseite vorab gerechnet. Leer: die Karten des Plans.
var cands: Array = []
## Zeilen weiterer Quellen (ForYou.leiste_extra); null: beim Aufbau holen (braucht main).
var extra: Variant = null
const Main := preload("res://src/main.gd")
var main: Main


func _init() -> void:
	super()
	setup("Für dich", "", BREITE)
	set_meta("uz_hint_b", "Schließen")


func fill() -> void:
	content.add_theme_constant_override("separation", 2)
	var alle: Array = cands
	if alle.is_empty():
		alle = ([plan.get("big", {})] + Array(plan.get("small", []))).filter(func(c: Variant) -> bool:
			return c is Dictionary and not (c as Dictionary).is_empty())
	var ex: Dictionary = extra if extra is Dictionary else (ForYou.leiste_extra(main) if main else {})
	var o := ForYou.ordnen(alle, ex, plan.get("big", {}))
	var hero: Dictionary = o.hero
	if not hero.is_empty():
		# Luft oben: Die gewählte Karte hebt sich (for_you_card.gd LIFT) und trägt ihren Schein.
		content.add_child(U.spacer(0, 4, false))
		content.add_child(_karte(hero))
	for a in o.abschnitte:
		_abschnitt(str(a.label))
		for z in a.rows:
			content.add_child(_musik(z) if bool((z as Dictionary).get("music", false)) else _zeile(z))
	_bibliothek()
	if hero.is_empty() and (o.abschnitte as Array).is_empty() and content.get_child_count() == 0:
		add_label("Gerade nichts Neues", "m", "muted")


## Unten, sobald es Emulator-Spiele gibt: „Spiele scrapen“ (spiele_scrapen.gd) mit dem Stand.
func _bibliothek() -> void:
	if Media.sgdb_games().is_empty() or main == null:
		return
	var fehlt := Media.sgdb_missing()
	_abschnitt("Bibliothek")
	var m := main
	var stand := tr("Läuft …") if Media.sgdb_running else (tr("%d ohne Cover") % fehlt if fehlt > 0 else tr("Alle da"))
	content.add_child(_zeile({ "key": "scrapen", "title": "Spiele scrapen", "icon": "image", "hint": "Öffnen",
		"extra": stand, "chevron": true,
		"act": func() -> void:
			var l = load("res://src/ui/layers/spiele_scrapen.gd").new()
			l.main = m
			m.open_layer(l) }))


## Abschnitt wie im Guide: kleines Etikett in Versalien, davor Luft (die erste Gruppe nach der Karte
## etwas mehr).
func _abschnitt(text: String) -> void:
	content.add_child(U.spacer(0, 22 if content.get_child_count() > 0 else 0, false))
	var hm := U.margin(4, 0, 0, 6)
	hm.add_child(Liste.abschnitt(text))
	content.add_child(hm)


## Die große Karte wie auf der Startseite; ihre Handlungen (A, Y) schließen zuerst die Leiste.
func _karte(c: Dictionary) -> Control:
	var d := c.duplicate()
	var leiste := self
	var act: Variant = c.get("act")
	d["act"] = func() -> void: leiste.tun(act)
	var ya: Variant = c.get("y_act")
	if ya is Callable and (ya as Callable).is_valid():
		d["y_act"] = func() -> void: leiste.tun(ya)
	var k = ForYouCard.new().setup(d, true, Vector2(KARTE_W, GROSS_H))
	k.leise = true
	return k


## Eine Zeile der Listen-Sprache (guide_row.gd): vorn Cover, Profilbild oder Symbol, Titel, leise
## der Zusatz, rechts ein Wert oder Pfeil. A führt aus und schließt, Y (wo es geht) zur Spielseite.
func _zeile(z: Dictionary) -> Control:
	var r = GuideRow.new()
	r.setup(str(z.get("title", "")), str(z.get("icon", "")), str(z.get("extra", "")), str(z.get("value", "")))
	r.chevron = bool(z.get("chevron", false))
	var p: Variant = z.get("person")
	var g: Variant = z.get("game")
	if p is Dictionary and not (p as Dictionary).is_empty():
		r.lead = Avatar.new().setup(str(p.get("name", "")), str(p.get("avatar", "")), str(p.get("state", "online")), 36)
		r.own_text = true
		r.min_h = ZEILE_H
	elif g is Dictionary and not (g as Dictionary).is_empty():
		r.lead = PlaytimePage.cover_clip(g, COVER, 6)
		r.min_h = ZEILE_H
	elif str(z.get("icon", "")) == "":
		r.icon_name = "spark"
	r.set_meta("uz_key", "fy:" + str(z.get("key", "")))
	r.add_to_group("uz_fuer_dich")     # Mitteilungen weichen aus (toasts.gd, _meiden)
	r.set_meta("uz_hint_a", str(z.get("hint", "Öffnen")))
	var leiste := self
	var act: Variant = z.get("act")
	r.activated.connect(func() -> void: leiste.tun(act))
	var ya: Variant = z.get("y_act")
	if ya is Callable and (ya as Callable).is_valid():
		r.set_meta("uz_hint_y", str(z.get("y_hint", "Zum Spiel")))
		r.set_meta("uz_on_y", func() -> void: leiste.tun(ya))
	return r


## „Läuft gerade“: die Zeile (A öffnet die Musik) und daneben ⏮ ⏯ ⏭ – die bleiben in der Leiste.
func _musik(z: Dictionary) -> Control:
	var r := _zeile(z)
	if str(Music.now.get("title", "")) == "" or Music.mode() == "aus":
		return r
	var row := U.hbox(22)
	row.set_meta("uz_row", true)
	row.set_meta("uz_group", "fy:musik")
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(r)
	var ctl := U.hbox(4)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ctl)
	ctl.add_child(_rund("prev", "Zurück", func() -> void: Music.previous()))
	var spielt := bool(Music.now.get("playing", false))
	var b := _rund("pause" if spielt else "play", "Pause" if spielt else "Abspielen", Callable())
	b.pressed.connect(func() -> void:
		var war := bool(Music.now.get("playing", false))
		Music.play_pause()
		b.icon = Icons.tex("play" if war else "pause", int(KNOPF * 0.4))
		b.set_meta("uz_hint_a", "Abspielen" if war else "Pause"))
	ctl.add_child(b)
	ctl.add_child(_rund("next", "Weiter", func() -> void: Music.next()))
	return row


## Runder Symbolknopf der Listen-Sprache (ruhig, flach), wie die Musik im Guide.
func _rund(icon: String, hint: String, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(KNOPF, KNOPF)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon = Icons.tex(icon, int(KNOPF * 0.4))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	U.ruhig(b, "flach", 0)
	b.set_meta("uz_key", "fy:musik:" + icon)
	b.add_to_group("uz_fuer_dich")
	b.set_meta("uz_hint_a", hint)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Handlung einer Karte oder Zeile: die Leiste geht zu, dann geschieht es. Die gewählte Karte wird
## gemerkt, damit ein Spielbild von ihr in die Spielseite fliegt (flug.gd) statt vom Cover darunter.
func tun(cb: Variant) -> void:
	var f := Nav.focused()
	if f and is_ancestor_of(f):
		Flug.merke(f)
	close()
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()


func nav_command(cmd: String) -> bool:
	# Start schließt wie B (main.gd bekommt die Taste nicht mehr, solange die Leiste offen ist).
	if cmd in ["menu", "b"] and closable:
		Sfx.play("back")
		close()
		return true
	return super(cmd)
