extends "res://src/ui/layers/setup_wizard_konten.gd"
## Einrichtung, Schicht über setup_wizard_konten.gd: die Vorstellung der starken Funktionen. Jede
## Station ist ein Bild über die ganze Breite mit einer Animation in der Handschrift der Marke
## (einrichtung_szene.gd: Licht aus dem Kern, Flächen im Kernlicht, ruhige Federn) und einem Satz;
## oben in der Szene zeigen drei kleine Kapitel, wo die Geschichte gerade ist. A geht weiter
## („Weiter“ ist gewählt), B geht zurück – für Eilige drei Drücke.
## Emulatoren – Systeme werden erkannt, ein Licht tastet die Sammlung ab; das Fenster zeigt den
##   echten Stand (bereit, kann geladen werden, von Hand) – geladen wird nur nach Zustimmung; die
##   Controller landen auf Spieler 1–4 (mit Multitap).
## Die Guide-Taste – rechts die Szene „guide“: Ein Spiel läuft, der Guide fährt herein und zeigt der
##   Reihe nach Freunde, Musik, Bildschirmfoto, Clip und Ausschalten. Links die Aufforderung, die
##   echte Guide-Taste zu drücken: Der echte Guide öffnet sich über der Einrichtung (B oder die
##   Taste schließen ihn), danach steht dort „Ausprobiert“. Darunter Guide-Taste halten und
##   Guide-Taste weckt Uzai.
## Dein Zimmer – ein echtes kleines 3D-Zimmer (einrichtung_zimmer.gd): ein gemütliches Retro-Zimmer
##   am Abend, drei Figuren sitzen zusammen auf dem Sofa und spielen am Röhrenfernseher. Bei einem
##   neuen Zimmer darunter die Vorlage – wer eine wählt, sieht gleich ihren Raum (mit den dreien).
## Schauen & Hören – Musik mit Lyrics, Videos, Filme und Livestreams in einer Szene („schauen“).

const Zimmerszene := preload("res://src/ui/components/einrichtung_zimmer.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const ZDaten := preload("res://src/room/zimmer_daten.gd")

## Zimmer: in dieser Einrichtung gewählte Vorlage ("" = noch keine). Solange es noch kein eigenes
## Zimmer gab, bleibt die Wahl offen (auch nach Zurück).
static var _vorlage := ""
var _zimmer_box: Control


## Nur für Proben: wie ein PC ohne Retro-Spiele (die Vorführung hat welche).
static var probe_ohne_retro := false

## Wurde die echte Guide-Taste in dieser Einrichtung schon ausprobiert? (bleibt über einen Neuaufbau)
static var _guide_probiert := false
var _probier: Control             ## Guide: die Aufforderung zum Ausprobieren
var _probier_an := false          ## … zeigt schon „Ausprobiert“


func _szene_guide() -> void:
	var sk := _skeleton("marke", "Die Guide-Taste", "Ein Druck öffnet den Guide. Auch über jedem Spiel.", SHOW_LEFT_W)
	_szene_rahmen(sk.right, Szene.new().setup("guide", Vector2.ZERO))
	var left: VBoxContainer = sk.left
	_probier = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("text", 0.035), UzTheme.r_panel())
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	_probier.add_theme_stylebox_override("panel", sb)
	_probier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_probier)
	_probier_an = false
	_probier_stand(false)
	_live.append(func() -> void:
		if _guide_probiert and not _probier_an and Nav.top_layer() == self:
			_probier_stand(true))
	var ex: Array = features().extras
	if ex.has("ruhemodus") or ex.has("background_wake"):
		left.add_child(U.spacer(0, 18, false))
		var rows := _card(left)
		if ex.has("ruhemodus"):
			_szene_guide_halten(rows)
		if ex.has("background_wake"):
			_szene_guide_weckt(rows)
	_default = sk.go


## Die echte Guide-Taste wurde gedrückt (setup_wizard.gd, handle): Der Guide öffnet sich wie
## überall; ist er wieder zu, steht „Ausprobiert“ da.
func _guide_gedrueckt() -> void:
	_guide_probiert = true


## Aufforderung bzw. „Ausprobiert“: links das Tastensymbol (passend zum Gerät) bzw. ein Haken,
## rechts zwei Zeilen. jetzt: gerade eben geschafft – der Haken kommt mit dem Klang „gefunden“, und
## vom Haken geht ein weicher Lichtschein in den Raum (Bühne).
func _probier_stand(jetzt: bool) -> void:
	if not is_instance_valid(_probier):
		return
	var fertig := _guide_probiert
	_probier_an = fertig
	U.clear(_probier)
	var h := U.hbox(24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_probier.add_child(h)
	var zeichen: Control = _Badge.make("check", 72, "ok") if fertig else U.glyph("guide", 64)
	zeichen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(zeichen)
	var v := U.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(U.label("Ausprobiert" if fertig else "Jetzt ausprobieren", "l", "ok" if fertig else "text", "bold"))
	var satz := U.label("Genauso kommt er über jedem Spiel." if fertig else "Drück die Guide-Taste. B schließt den Guide wieder.", "m", "muted", "regular", true)
	satz.custom_minimum_size = Vector2(SHOW_LEFT_W - 160.0, 0)
	v.add_child(satz)
	if jetzt:
		Sfx.play("setup_found", 1.0, zeichen)
		_steigen([h])
		if is_instance_valid(_buehne):
			var at: Vector2 = _buehne.get_global_transform().affine_inverse() * _probier.get_global_rect().get_center()
			_buehne.feiern(at, 0.6)


## Guide-Taste halten: Schnellmenü, Ruhemodus oder nichts (derselbe Schlüssel wie unter Extras).
func _szene_guide_halten(rows: VBoxContainer) -> void:
	var rm = _row(rows, "choice", "Guide-Taste halten", "Schnellmenü oder Ruhemodus", "Kurz drücken öffnet den Guide.", str(Config.get_value("controller.guide_hold", "menu")))
	rm.options = [["menu", "Schnellmenü"], ["rest", "Ruhemodus"], ["aus", "Nichts"]]
	rm.icon_name = "moon"
	rm.changed.connect(func(v: Variant) -> void: Config.set_value("controller.guide_hold", str(v)))


## Guide-Taste weckt Uzai (derselbe Schlüssel wie unter Extras).
func _szene_guide_weckt(rows: VBoxContainer) -> void:
	var bw = _row(rows, "toggle", "Guide-Taste weckt Uzai", "Startet Uzai nach dem Schließen",
			"Auch mit View + Start.", bool(Config.get_value("system.background_wake", true)))
	bw.icon_name = "power"
	bw.changed.connect(func(v: Variant) -> void: Config.set_value("system.background_wake", bool(v)))


## Höhe der großen Szene der Vorstellung (über die ganze Seite).
const VOR_H := 500.0
## Zimmer: so hoch, wenn darunter noch die Vorlage steht.
const VOR_H_ZIMMER := 430.0


## Gerüst einer Station der Vorstellung: oben Titel und ein Satz (ohne Zeichen davor – die Szene
## darunter zeigt, worum es geht), darunter die Szene über die ganze Breite der Seite. Gibt { col,
## frame } zurück; danach kommt, was die Station einrichtet, und zuletzt „Weiter“ (_fuss_mitte).
func _vorstellung(title: String, sub: String, inner: Control, h := VOR_H, zuschnitt := true) -> Dictionary:
	var col := _mitte()
	var head := U.hbox(30)
	col.add_child(head)
	var hc := U.vbox(6)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hc)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UzTheme.display("title"))
	t.add_theme_font_size_override("font_size", 54)
	t.add_theme_color_override("font_color", UzTheme.col("text"))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hc.add_child(t)
	var st := U.label(sub, "l", "muted", "regular", true)
	st.custom_minimum_size = Vector2(1200, 0)
	hc.add_child(st)
	col.add_child(U.spacer(0, 26, false))
	var frame := _szene_rahmen(col, inner, zuschnitt, h, PAGE_W)
	col.add_child(U.spacer(0, 24, false))
	return { "col": col, "frame": frame }


## Emulators: show honestly what is on this PC, so it does not look as if all emulators were already being set
## up. The scene gets the real state (_emu_stand) and shows only systems with games; if one lacks an emulator
## that Uzai can download from the official source, a line „… einrichten?“ appears below it. That line opens
## Retro einrichten with license and consent; only then is anything downloaded (and only then does the scene
## show progress).
##
## Without retro games, an empty emulator field would look odd. The step still stays - the dots at the top do
## not change in the middle of setup, and anyone with retro games that Uzai did not find ends up here. The scene
## calmly shows „Keine Retro-Spiele gefunden“ (einrichtung_szene.gd _emu_leer), below it „Ordner hinzufügen …“
## (the same path as for games; finds are applied and scanned right away), and „Weiter“ is selected.
func _szene_emulatoren() -> void:
	var sz: Control = Szene.new().setup("emulatoren", Vector2.ZERO)
	var retro := _retro_fehlt() if str(_find.get("state", "")) == "fertig" else _retro_fehlt_lage()
	var leer := _emu_stand().is_empty()
	var v := _vorstellung("Emulatoren", "Erkannt, auf Wunsch geladen, mit dem Controller belegt.", sz,
			VOR_H_ZIMMER if leer or not retro.is_empty() else VOR_H)
	sz.call("stand", _emu_stand())
	_live.append(func() -> void:
		if is_instance_valid(sz):
			sz.call("stand", _emu_stand()))
	var col: VBoxContainer = v.col
	if leer or not retro.is_empty():
		var box := HBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(box)
		var holder := U.vbox(0)
		holder.custom_minimum_size = Vector2(760, 0)
		box.add_child(holder)
		var rows := _card(holder)
		if leer:
			_folder_row(rows)
		else:
			_retro_offer(rows, retro)
		col.add_child(U.spacer(0, 18, false))
	_default = _fuss_mitte(col)


## Ohne fertige Suche (etwa nach einem Neustart in diesem Schritt): der Stand nur aus der Bibliothek.
func _retro_fehlt_lage() -> Dictionary:
	var text := RetroAuto.fehlt_text(load("res://src/core/retro_laden.gd").inst().lage({}, []))
	return { "text": text, "extra": {}, "schon_da": [] } if text != "" else {}


## Der echte Stand je System mit Spielen (Bibliothek und gewählte Funde), für die Szene:
## { sys, kurz, name, spiele, zustand, pct, emu, emu_name, farbe }. zustand: "bereit" (Emulator da),
## "laedt"/"wartet" (ein Laden läuft wirklich – nach Zustimmung in Retro einrichten), "angebot" (Uzai
## kann ihn laden, erst nach Zustimmung) oder "selbst" (von Hand einrichten). Höchstens sechs.
func _emu_stand() -> Array:
	if probe_ohne_retro:
		return []
	var wahl := _funde_wahl() if str(_find.get("state", "")) == "fertig" else [{}, []]
	var laden: Node = load("res://src/core/retro_laden.gd").inst()
	var jobs: Dictionary = laden.get("auftraege")
	var out: Array = []
	for r0 in (laden.call("lage", wahl[0], wahl[1]) as Array).slice(0, 6):
		var r: Dictionary = r0
		var sid := str(r.system)
		var zustand := "bereit" if bool(r.bereit) else ("angebot" if str(r.angebot) != "" else "selbst")
		var pct := 0.0
		if zustand != "bereit":
			for k in jobs:
				var j: Dictionary = jobs[k]
				if str(j.get("phase", "")) in ["wartet", "laeuft"] and (j.get("systeme", []) as Array).has(sid):
					zustand = "laedt" if str(j.phase) == "laeuft" else "wartet"
					pct = float(j.get("got", 0)) / float(j.get("total", 0)) if int(j.get("total", 0)) > 0 else 0.0
		var eid := str(r.emulator) if bool(r.bereit) else str(r.angebot)
		var nm := str(Config.emulator(eid).get("name", eid)).get_slice(" (", 0) if eid != "" else ""
		out.append({ "sys": sid, "kurz": str(r.short), "name": str(r.name), "spiele": int(r.spiele), "zustand": zustand, "pct": pct,
			"emu": eid, "emu_name": nm, "farbe": Color(str(Config.system(sid).get("color", "#7a5fd0"))) })
	return out


func _szene_medien() -> void:
	var v := _vorstellung("Schauen & Hören", "Musik mit Lyrics, Videos, Filme und Livestreams.",
			Szene.new().setup("schauen", Vector2.ZERO))
	_default = _fuss_mitte(v.col)


func _szene_zimmer() -> void:
	var neu := _vorlage != "" or not FileAccess.file_exists(ZDaten.pfad())
	_zimmer_box = Control.new()
	_zimmer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := _vorstellung("Dein Zimmer", "Bauen, einrichten, Freunde einladen, zusammen spielen.",
			_zimmer_box, VOR_H_ZIMMER if neu else VOR_H, false)
	_zimmer_bild()
	var col: VBoxContainer = v.col
	if neu:
		var opts: Array = []
		for o in Vorlagen.LISTE:
			opts.append([str(o[0]), str(o[1])])
		var box := HBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(box)
		var holder := U.vbox(0)
		holder.custom_minimum_size = Vector2(760, 0)
		box.add_child(holder)
		var rows := _card(holder)
		var ch = _row(rows, "choice", "Einrichtung", "Für dein erstes Zimmer", "Fertige Einrichtung. Umräumen im Zimmer.",
				_vorlage if _vorlage != "" else "gemuetlich")
		ch.options = opts
		ch.icon_name = "palette"
		ch.changed.connect(func(val: Variant) -> void: _vorlage_setzen(str(val)))
		col.add_child(U.spacer(0, 18, false))
	_default = _fuss_mitte(col)


## Die Zimmer-Szene (einrichtung_zimmer.gd): das Retro-Zimmer, nach einer gewählten Vorlage deren
## Raum. Nicht fokussierbar; geht mit der Seite.
func _zimmer_bild() -> void:
	if not is_instance_valid(_zimmer_box):
		return
	U.clear(_zimmer_box)
	var zb: Control = Zimmerszene.new().setup(_vorlage)
	U.full_rect(zb)
	_zimmer_box.add_child(zb)


## Eine Vorlage übernehmen: nur solange es kein eigenes Zimmer gab (sonst steht die Wahl nicht da).
func _vorlage_setzen(id: String) -> void:
	var raum := Vorlagen.raum(id)
	if raum.is_empty():
		return
	var d := ZDaten.standard()
	d.raeume = [raum]
	d.aktuell = str(raum.id)
	if ZDaten.speichern(d):
		_vorlage = id
		_zimmer_bild()
