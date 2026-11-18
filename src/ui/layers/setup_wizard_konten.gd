extends "res://src/ui/layers/setup_wizard_spiele.gd"
## Einrichtung, Schicht über setup_wizard_spiele.gd: Konten (alle Dienste zur Wahl, nach Bereichen,
## Steam und Discord groß zuerst) und – freiwillig – Extras (Bildrate ×2,
## Guide-Taste weckt Uzai, Autostart …).

const Konten := preload("res://src/core/konten.gd")
const Sgdb := preload("res://src/core/sgdb_konto.gd")
const CLIP_KEYS := [["WIN+ALT+G", "Xbox Game Bar"], ["ALT+F10", "NVIDIA"], ["CTRL+SHIFT+S", "AMD"]]
const Leicht := preload("res://src/core/leicht.gd")
const SteamGuide := preload("res://src/core/steam_guide.gd")
## Linke Spalte der Seiten mit Szene (Einrichten); die rechte (Szene) bekommt den Rest der Seite.
const SHOW_LEFT_W := 640.0
const SZENE_H := 470.0

## Accounts, laid out like the accounts page of a console so the overview is easier to scan than a
## dropdown with every entry at the same level: Steam and Discord large at the top (KONTO_GROSS),
## below them the rest compact by area (KONTO_GRUPPEN), in two columns exactly under Steam and
## Discord (same width, same center); E.spalten_verteilen works out by height which areas go where.
## The services carry their area in "group".
const KONTO_GROSS := ["Steam", "Discord"]
## [id, Überschrift]
const KONTO_GRUPPEN := [
	["spiele", "Spiele"],
	["musik", "Musik"],
	["videos", "Video"],
	["filme", "Filme & Serien"],
]
## Höhe einer Bereichs-Überschrift (für die Verteilung).
const KONTO_KOPF_H := 46.0
## Bereich der großen Kacheln (kleines Etikett über dem Namen).
const KONTO_BEREICH := { "Steam": "Spiele", "Discord": "Freunde & Chat" }
## Logo zur Laufzeit (badge_logos.gd, R4) – sonst das eigene Zeichen.
const KONTO_LOGO := { "Steam": "steam", "Discord": "discord", "Epic Games": "epic" }
const KONTO_LUECKE := 24.0

## Nur für Proben: wie ein PC ohne verbundene Konten (in der Vorführung sind alle verbunden).
static var probe_no_accounts := false


# --- 5 Konten -------------------------------------------------------------------------------

## Ein Bildschirm, kein Formular: oben Steam und Discord als große Kacheln (Logo, Bereich, Name,
## wofür, Stand), darunter alle übrigen Dienste kompakt nach Bereichen in zwei Spalten – mit kleinen
## Überschriften, damit nicht alles gleich wichtig aussieht. Jede Kachel sagt ruhig „Verbunden“ oder
## „Nicht verbunden“; A meldet an (per QR-Code oder Code am Handy, Discord mit einer Bestätigung in
## der Discord-App). Unten steht leise, wie die gewählte Kachel verbindet (auch, wo ein Weg
## inoffiziell ist). Nichts, was eine eigene Entwickler-App oder ein Secret verlangt (die liegen
## unter Einstellungen → Konten → Mehr). Alles freiwillig: „Weiter“ geht auch ohne Verbindung.
## Alles auf einer Mittelachse: Kacheln, die zwei Spalten darunter, die leise Zeile und „Weiter“.
## Wird ein Dienst verbunden, während der Schritt offen ist, leuchtet seine Kachel mit dem Klang
## „gefunden“ auf.
func _konten() -> void:
	var sk := _skeleton("user", "Konten", "Verbinde, was du nutzt. Alles freiwillig.", PAGE_W)
	var left: VBoxContainer = sk.left
	var accs: Array = E.setup_accounts(_accounts()).filter(func(a: Dictionary) -> bool: return not bool(a.get("needs_id", false)))
	var gross := U.hbox(int(KONTO_LUECKE))
	gross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(gross)
	for acc in accs:
		if str(acc.title) in KONTO_GROSS:
			var k := _konto_kachel(acc, true)
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			gross.add_child(k)
	left.add_child(U.spacer(0, 14, false))
	# Bereiche mit Diensten (Spiele immer: SteamGridDB steht darin) und ihre Höhe.
	var titel := {}
	var glieder := {}
	var hoehen: Array = []
	for g in KONTO_GRUPPEN:
		var gid := str(g[0])
		titel[gid] = str(g[1])
		var members: Array = accs.filter(func(a: Dictionary) -> bool:
			return str(a.get("group", "")) == gid and not (str(a.title) in KONTO_GROSS))
		var zeilen := members.size() + (1 if gid == "spiele" else 0)
		if zeilen == 0:
			continue
		glieder[gid] = members
		hoehen.append([gid, KONTO_KOPF_H + zeilen * _Konto.H_KLEIN])
	var spalten := U.hbox(int(KONTO_LUECKE))
	spalten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(spalten)
	for ids in E.spalten_verteilen(hoehen):
		var sp := U.vbox(0)
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.size_flags_stretch_ratio = 1.0
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spalten.add_child(sp)
		for gid in ids:
			_head(sp, str(titel.get(str(gid), gid)))
			var rows := _card(sp)
			for acc in glieder[str(gid)]:
				rows.add_child(_konto_kachel(acc, false))
			if str(gid) == "spiele":
				rows.add_child(_sgdb_kachel())
				rows.add_child(_iidb_kachel())
	left.add_child(U.spacer(0, 18, false))
	# Leise unten und mittig: wie die gewählte Kachel verbindet; darunter mittig „Weiter“.
	_aside_d = U.label("", "s", "muted", "regular", true)
	_aside_d.custom_minimum_size = Vector2(PAGE_W, 0)
	_aside_d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_aside_d)
	(sk.go.get_parent() as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_default = sk.go


## Kachel eines Dienstes (gross: Steam und Discord obenauf). A meldet an; schon verbunden: sagt es nur.
func _konto_kachel(acc: Dictionary, gross: bool) -> Control:
	var k := _Konto.new()
	k.gross = gross
	k.titel = str(acc.title)
	k.zeile = str(acc.sub)
	k.bereich = str(KONTO_BEREICH.get(str(acc.title), ""))
	k.icon_name = str(acc.icon)
	k.logo = str(KONTO_LOGO.get(str(acc.title), ""))
	var desc := str(acc.desc)
	var status: Callable = acc["status"]
	var connect_cb: Callable = acc["connect"]
	k.on_activate = func() -> void:
		if bool(status.call()[2]):
			Toasts.show_toast("%s ist schon verbunden" % str(acc.title), "", "check", { "quiet": true })
			return
		connect_cb.call()
	_konto_einhaengen(k, desc, func() -> Array: return status.call())
	return k


## SteamGridDB (ein kostenloser Schlüssel für den ganzen PC, übers Handy eingefügt und sofort
## geprüft) – Cover und Hintergründe. Ohne ihn nimmt Uzai Steam- und Libretro-Bilder.
func _sgdb_kachel() -> Control:
	var k := _Konto.new()
	k.titel = "SteamGridDB"
	k.icon_name = "image"
	k.on_activate = func() -> void:
		if Sgdb.connected():
			Toasts.show_toast("SteamGridDB verbunden", "", "check", { "quiet": true })
			return
		open_sgdb(main)
	_konto_einhaengen(k, "Cover und Hintergründe. Kostenloser Schlüssel, gilt für alle Profile.",
			func() -> Array: return _st(Sgdb.connected(), ""))
	return k


## iiDB von iiSU (eigener Schlüssel, übers Handy eingefügt und sofort geprüft): Bilder und der Klang
## der Spielseite.
func _iidb_kachel() -> Control:
	var k := _Konto.new()
	k.titel = "iiDB"
	k.icon_name = "image"
	k.on_activate = func() -> void:
		if Media.iidb.verbunden():
			Toasts.show_toast("iiDB verbunden", "", "check", { "quiet": true })
			return
		open_iidb(main)
	_konto_einhaengen(k, "Bilder und Spielklang von iiSU. Eigener Schlüssel, gilt für alle Profile.",
			func() -> Array: return _st(Media.iidb.verbunden(), ""))
	return k


## Gemeinsam für jede Kachel: Schlüssel für die Wiederkehr nach einem Neuaufbau, unten die leise
## Zeile beim Wählen und der laufende Stand (zweimal je Sekunde) mit Klang, sobald verbunden.
func _konto_einhaengen(k: Control, desc: String, stand: Callable) -> void:
	k.set_meta("uz_key", "su:konten:%s" % str(k.get("titel")))
	var t := str(k.get("titel"))
	k.focus_entered.connect(func() -> void: _help(t, desc))
	var war := [bool(stand.call()[2])]
	var upd := func() -> void:
		if not is_instance_valid(k):
			return
		var s: Array = stand.call()
		k.call("stand", str(s[0]), str(s[1]), bool(s[2]))
		if bool(s[2]) and not war[0]:
			war[0] = true
			_verbunden(k)
	upd.call()
	_live.append(upd)


## Eine Kachel der Konten: gross (Logo in einer Scheibe, darüber klein der Bereich, Name, wofür,
## rechts der Stand) oder kompakt als Zeile (Zeichen, Name, rechts der Stand). Die Auswahl ist die
## der Listen (Liste.fokus / zeilen_auswahl): hell, die Schrift darauf dunkel – im Rahmen-Cursor
## bleibt sie, wie sie ist. Verbunden steht leise in Grün, „Nicht verbunden“ zurückhaltend.
class _Konto extends Control:
	const ListeK := preload("res://src/ui/components/liste.gd")
	const LogosK := preload("res://src/core/badge_logos.gd")
	const H_GROSS := 148.0
	const H_KLEIN := 66.0
	var gross := false
	var titel := ""
	var zeile := ""
	var bereich := ""
	var icon_name := ""
	var logo := ""
	var on_activate: Callable
	var _text := ""
	var _ton := ""
	var _an := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, H_GROSS if gross else H_KLEIN)
		focus_entered.connect(func() -> void:
			ListeK.fokus(self, true)
			queue_redraw())
		focus_exited.connect(func() -> void:
			ListeK.fokus(self, false)
			queue_redraw())
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())
		if logo != "" and LogosK.enabled():
			var l := LogosK.loader()
			if l:
				l.logo_ready.connect(func(_k: String) -> void: queue_redraw())

	## Stand: Text, Ton ("ok", "warn", "faint", sonst leise), verbunden.
	func stand(text: String, ton: String, an: bool) -> void:
		if text == _text and ton == _ton and an == _an:
			return
		_text = text
		_ton = ton
		_an = an
		set_meta("uz_hint_a", "Konto" if an else "Anmelden")
		queue_redraw()

	func activate() -> void:
		ListeK.druck(self)
		if on_activate.is_valid():
			on_activate.call()

	func _farbe(k: String, f: float) -> Color:
		var c := UzTheme.col(k)
		return c if UzTheme.cursor_frame() else c.lerp(UzTheme.col("on_focus"), f)

	func _draw() -> void:
		var f: float = get_meta("uz_f", 1.0 if has_focus() else 0.0)
		var rad := maxi(UzTheme.radius, UzTheme.r_panel() - 6)
		if gross and not UzTheme.strict():
			draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))
		elif gross:
			draw_style_box(UzTheme.box(UzTheme.col("text", 0.04), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))
		ListeK.zeilen_auswahl(self, UzTheme.r_panel() if gross else rad)
		var fs := UzTheme.ui("ui")
		var fb := UzTheme.ui("ui_bold")
		var ink := _farbe("text", f)
		var leise := _farbe("muted", f)
		var stand_c := _farbe("muted", f)
		match _ton:
			"ok": stand_c = UzTheme.col("ok") if f < 0.5 or UzTheme.cursor_frame() else UzTheme.col("on_focus")
			"warn": stand_c = UzTheme.col("warn") if f < 0.5 or UzTheme.cursor_frame() else UzTheme.col("on_focus")
			"faint": stand_c = _farbe("faint", f)
		var cy := size.y * 0.5
		var x := 22.0
		if gross:
			# Logo in einer matten Scheibe.
			var d := 84.0
			var mc := Vector2(30.0 + d * 0.5, cy)
			draw_circle(mc, d * 0.5, Color(ink, 0.08), true, -1.0, true)
			var lr := Rect2(mc - Vector2(d, d) * 0.29, Vector2(d, d) * 0.58)
			var got := LogosK.line_logo(logo, lr.size.y, lr.size.x) if logo != "" else {}
			if not got.is_empty():
				var sz: Vector2 = got.size
				draw_texture_rect(got.tex, Rect2(mc - sz * 0.5, sz), false, ink)
			else:
				draw_texture_rect(Icons.tex(icon_name, int(lr.size.y)), lr, false, ink)
			x = 30.0 + d + 26.0
			var cf := ListeK.caps_font()
			var top := cy - 40.0
			if bereich != "":
				draw_string(cf, Vector2(x, top + 6.0), tr(bereich).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(leise, 0.85))
			draw_string(fb, Vector2(x, top + 44.0), tr(titel), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("xl"), ink)
			draw_string(fs, Vector2(x, top + 76.0), tr(zeile), HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 260.0, UzTheme.size("s"), leise)
			_stand_zeichnen(_text, Vector2(size.x - 30.0, cy + 6.0), UzTheme.size("m"), stand_c, fs)
			return
		var ic := 26.0
		draw_texture_rect(Icons.tex(icon_name, int(ic)), Rect2(Vector2(x, cy - ic * 0.5), Vector2(ic, ic)), false, leise)
		x += ic + 18.0
		var fsz := UzTheme.size("m")
		var y := cy + (fs.get_ascent(fsz) - fs.get_descent(fsz)) * 0.5
		# Kompakt: nur der Stand, der Name des Kontos steht in den großen Kacheln und unter Einstellungen.
		var kurz := _text.get_slice(" · ", 0)
		var stand_w := _stand_breite(kurz, UzTheme.size("s"), fs)
		var max_w := size.x - x - stand_w - 44.0
		draw_string(fs, Vector2(x, y), tr(titel), HORIZONTAL_ALIGNMENT_LEFT, max_w, fsz, ink)
		_stand_zeichnen(kurz, Vector2(size.x - 22.0, y - 1.0), UzTheme.size("s"), stand_c, fs)

	func _stand_breite(text: String, px: int, fnt: Font) -> float:
		return fnt.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + (18.0 if _an else 0.0)

	## Stand rechtsbündig an rechts (Grundlinie y): verbunden mit einem kleinen Punkt davor.
	func _stand_zeichnen(text: String, rechts: Vector2, px: int, c: Color, fnt: Font) -> void:
		if text == "":
			return
		var w := fnt.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(fnt, Vector2(rechts.x - w, rechts.y), tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)
		if _an:
			draw_circle(Vector2(rechts.x - w - 13.0, rechts.y - px * 0.34), 4.5, c, true, -1.0, true)


## Ein Dienst ist gerade verbunden worden: Klang „gefunden“ und ein weicher Lichtschein von seiner
## Zeile in den Raum (Bühne).
func _verbunden(r: Control) -> void:
	Sfx.play("setup_found", 1.0, r)
	if is_instance_valid(_buehne) and r.is_inside_tree():
		var at: Vector2 = _buehne.get_global_transform().affine_inverse() * r.get_global_rect().get_center()
		_buehne.feiern(at, 0.5)


## Die Szene rechts in einem Rahmen (Ecken wie die Flächen des Themes; im leichten Modus ohne
## eigenen Zuschnitt; breite: eigene Breite, etwa die ganze Seite in der Vorstellung).
## zuschnitt aus: Der Inhalt schneidet sich selbst zu (zimmer_bild.gd – zwei
## Zuschnitte ineinander zeigten das 3D-Bild nicht).
func _szene_rahmen(right: Control, inner: Control, zuschnitt := true, h := SZENE_H, breite := -1.0) -> Control:
	var w := PAGE_W - SHOW_LEFT_W - 60.0 if breite < 0.0 else breite
	var clip := Panel.new()
	clip.custom_minimum_size = Vector2(w, h)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := 0 if Leicht.active else UzTheme.r_panel()
	clip.add_theme_stylebox_override("panel", UzTheme.flaeche(UzTheme.col("surface"), r, 1))
	if r > 0 and zuschnitt:
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	right.add_child(clip)
	U.full_rect(inner)
	clip.add_child(inner)
	if resume.is_empty() and not U.reduziert():
		# Die Szene kommt nach der Seite: ruhig (T_RAUM).
		clip.modulate.a = 0.0
		var tw := U.ankommen(clip, U.T_RAUM, "uz_szene")
		tw.tween_property(clip, "modulate:a", 1.0, U.T_RAUM).set_delay(U.T_ORT)
	return clip


## Konten als Liste: { title, sub, desc, icon, status → [Text, Ton, verbunden], connect, way }.
## way: "qr" (QR-Code oder Code am Handy) oder "app" (Bestätigen in der App am PC). needs_id: geht
## nur mit einer eigenen Entwickler-App (dann sagt die Zeile das ehrlich, statt still leer zu bleiben).
func _accounts() -> Array:
	var out: Array = []
	out.append({ "title": "Steam", "icon": "steam", "group": "spiele", "sub": "Freunde, Erfolge, Chat",
		"desc": "Code mit der Steam-App scannen.",
		"status": func() -> Array: return _st(SteamChat.logged_in(), SteamChat.account_name()),
		"connect": func() -> void: main.open_chat({ "id": "", "name": "Steam" }, true), "way": "qr" })
	out.append({ "title": "Discord", "icon": "discord", "group": "freunde", "sub": "Status, Sprachkanal, Nachrichten",
		"desc": "In der Discord-App am PC freigeben." if Voice.uzai_app_direkt() else "Eigene Discord-App, etwa 3 Minuten mit dem Handy.",
		"status": func() -> Array:
			if Voice.ready_():
				return ["Verbunden", "ok", true]
			if not Voice.configured():
				return ["Geht gerade nicht", "faint", false]
			return ["Nicht verbunden", "", false],
		"connect": _connect_discord, "way": "app", "needs_id": Voice.client_id() == "" })
	out.append({ "title": "Epic Games", "icon": "games", "group": "spiele", "sub": "Alle gekauften Spiele",
		"desc": "Code mit dem Handy scannen.",
		"status": func() -> Array:
			var acc = Library.epic_account
			return _st(bool(acc.logged_in()), ""),
		"connect": func() -> void: main.open_layer(load("res://src/ui/layers/epic_login.gd").new()), "way": "qr" })
	out.append({ "title": "Spotify", "icon": "music", "group": "musik", "sub": "Mixe, Playlists, Suche",
		"desc": "Mit deinem Spotify-Konto anmelden.",
		"status": func() -> Array:
			if Music.has_spotify() and Music.problem == "app":
				return ["Eingeschränkt", "warn", true]
			return _st(Music.has_spotify(), ""),
		"connect": _connect_spotify, "way": "app" })
	out.append({ "title": "YouTube", "icon": "video", "group": "videos", "sub": "Abos, Playlists, Startseite",
		"desc": _yt_desc(),
		"status": func() -> Array: return _st(_yt_logged_in(), _yt_name()),
		"connect": _connect_youtube, "way": "qr" })
	out.append({ "title": "Twitch", "icon": "live", "group": "videos", "sub": "Live-Kanäle",
		"desc": "Code mit dem Handy scannen.",
		"status": func() -> Array: return _st(Twitch.logged_in(), Twitch.account_name()),
		"connect": func() -> void: main.open_twitch_login(), "way": "qr" })
	out.append({ "title": "Nuvio", "icon": "film", "group": "filme", "sub": "Filme und Serien",
		"desc": "Addons, Bibliothek und Weiterschauen.",
		"status": func() -> Array: return _st(NuvioSync.connected(), NuvioSync.email()),
		"connect": func() -> void: main.open_nuvio_login(), "way": "qr" })
	# Plex and Stremio are always part of the setup, both with a code on the phone like Nuvio. Jellyfin and
	# Emby (address and sign-in) are used by few: only when one is already connected; otherwise they are
	# under Einstellungen › Filme › Filme-Quellen.
	out.append({ "title": "Plex", "icon": "drive", "group": "filme", "sub": "Filme und Serien von deinem Server",
		"desc": "Code auf plex.tv/link eingeben.",
		"status": func() -> Array: return _st(Konten.stored("plex", Config.get_value), ""),
		"connect": func() -> void: main.open_plex_login(), "way": "qr" })
	out.append({ "title": "Stremio", "icon": "film", "group": "filme", "sub": "Bibliothek, Weiterschauen, eigene Addons",
		"desc": "Code auf link.stremio.com eingeben. Keine Addons enthalten.",
		"status": func() -> Array: return _st(Konten.stored("stremio", Config.get_value), ""),
		"connect": func() -> void: main.open_stremio_login(), "way": "qr" })
	if _server_stored():
		out.append({ "title": "Jellyfin oder Emby", "icon": "drive", "group": "filme", "sub": "Eigener Medienserver",
			"desc": "Keine Addons enthalten. Für deine Quellen bist du verantwortlich.",
			"status": func() -> Array:
				var names: Array = []
				for id in ["jellyfin", "emby"]:
					if Konten.stored(id, Config.get_value):
						names.append(str(Konten.find(id).name))
				return _st(not names.is_empty(), " · ".join(PackedStringArray(names))),
			"connect": func() -> void: main.open_movie_sources(), "way": "qr" })
	# Unter „Spiele“ (eine Überschrift weniger): mit Plex und Stremio passen die Konten sonst nicht mehr ohne Blättern.
	out.append({ "title": "RetroAchievements", "icon": "retro", "group": "spiele", "sub": "Erfolge für Emulator-Spiele",
		"desc": "Benutzername und Web-API-Schlüssel.",
		"status": func() -> Array:
			var ra := str(Config.get_value("accounts.ra_user", ""))
			return _st(ra != "", ra),
		"connect": func() -> void: main.open_ra_login(), "way": "qr" })
	return out



## SteamGridDB einrichten (src/ui/layers/sgdb_login.gd), auch für Einstellungen → Konten.
static func open_sgdb(m: Main) -> void:
	var l = load("res://src/ui/layers/sgdb_login.gd").new()
	l.main = m
	m.open_layer(l)


## iiDB verbinden (src/ui/layers/iidb_login.gd), auch für Einstellungen → Konten und „Spiele scrapen“.
static func open_iidb(m: Main) -> Control:
	var l: Control = load("res://src/ui/layers/iidb_login.gd").new()
	l.main = m
	m.open_layer(l)
	return l


## Stand einer Kachel: [Text, Ton, verbunden] – ruhig: „Verbunden“ (mit Namen) oder „Nicht verbunden“.
static func _st(on: bool, who: String) -> Array:
	if on:
		return [(TranslationServer.translate("Verbunden") + " · " + who) if who != "" else "Verbunden", "ok", true]
	return ["Nicht verbunden", "", false]


func _yt_desc() -> String:
	if _has_tv_login():
		return "Code mit dem Handy scannen."
	return "Mit Google-Konto."


func _has_tv_login() -> bool:
	return ResourceLoader.exists("res://src/ui/layers/yt_tv_login.gd") and YouTube.get("tv") != null


func _yt_logged_in() -> bool:
	if _has_tv_login():
		var tv: Object = YouTube.get("tv")
		if tv.has_method("logged_in") and bool(tv.call("logged_in")):
			return true
	return YouTube.logged_in()


func _yt_name() -> String:
	if _has_tv_login():
		var tv: Object = YouTube.get("tv")
		if tv.has_method("logged_in") and bool(tv.call("logged_in")) and tv.has_method("account_name"):
			return str(tv.call("account_name"))
	return str(YouTube.account) if YouTube.logged_in() else ""


func _connect_youtube() -> void:
	if _has_tv_login():
		main.open_layer(load("res://src/ui/layers/yt_tv_login.gd").new())
	else:
		main.open_yt_login()


## Mit Uzais Discord-App (oder einer eigenen) gleich zur Freigabe in der Discord-App. Fehlt jede
## App-ID, sagt Uzai ehrlich, was fehlt; die eigene App bleibt ein Weg unter „Mehr“.
func _connect_discord() -> void:
	if Voice.configured():
		main.open_layer(load("res://src/ui/layers/discord_connect.gd").new())
		return
	main.open_dialog("Discord geht gerade nicht", Voice.missing_text(), [
		["Eigene App-ID", func() -> void:
			main.open_keyboard("Discord-App-ID", Voice.own_id(), func(id: String) -> void:
				Config.set_value("accounts.discord_client_id", id.strip_edges())
				if Voice.configured():
					Voice.start()
					main.open_layer(load("res://src/ui/layers/discord_connect.gd").new())
			, false, "https://discord.com/developers/applications")],
		["Schließen", func() -> void: pass],
	], "discord")


## Spotify: „Mit Spotify anmelden“ (die echte Anmeldeseite im Uzai-Browser). Die eigene Spotify-App steht als
## zweiter Weg unter Einstellungen › Konten › Spotify.
func _connect_spotify() -> void:
	load("res://src/ui/layers/spotify_anmelden.gd").start(main)


# --- 6 Extras -------------------------------------------------------------------------------

func _extras() -> void:
	var sk := _skeleton("spark", "Extras", "Alles später änderbar.")
	var left: VBoxContainer = sk.left
	_aside(sk.right, "Extras", "")
	var rows := _card(left)
	var ex: Array = features().extras
	if ex.has("lossless"):
		var exe := str(Lossless.exe_path())
		var ls = _row(rows, "choice", "Bildrate ×2 (Lossless Scaling)", ("Gefunden: " + exe.get_file()) if exe != "" else "Nicht installiert",
				"Verdoppelt die Bildrate im Fenstermodus." + ("" if exe != "" else " Erhältlich auf Steam."), Config.get_value("lossless.auto", "aus"))
		ls.options = [["aus", "Von Hand"], ["pc", "Bei PC-Spielen"], ["emu", "Bei Emulator-Spielen"], ["alle", "Bei allen Spielen"]]
		ls.icon_name = "bolt"
		ls.changed.connect(func(v: Variant) -> void: Config.set_value("lossless.auto", v))
	if ex.has("background_wake"):
		var bw = _row(rows, "toggle", "Guide-Taste weckt Uzai", "Startet Uzai nach dem Schließen",
				"Auch mit View + Start.", bool(Config.get_value("system.background_wake", true)))
		bw.icon_name = "power"
		bw.changed.connect(func(v: Variant) -> void: Config.set_value("system.background_wake", bool(v)))
	if ex.has("autostart"):
		var au = _row(rows, "toggle", "Mit Windows starten", "Der PC startet direkt in Uzai",
				"",
				bool(Config.get_value("system.autostart", false)))
		au.icon_name = "desktop"
		au.changed.connect(func(v: Variant) -> void:
			Config.set_value("system.autostart", bool(v))
			Helper.run("autostart", { "enable": bool(v), "exe": OS.get_executable_path().replace("/", "\\") })
		)
	if ex.has("ruhemodus"):
		var rm = _row(rows, "choice", "Guide-Taste halten", "Schnellmenü oder Ruhemodus", "Kurz drücken öffnet den Guide.", str(Config.get_value("controller.guide_hold", "menu")))
		rm.options = [["menu", "Schnellmenü"], ["rest", "Ruhemodus"], ["aus", "Nichts"]]
		rm.icon_name = "moon"
		rm.changed.connect(func(v: Variant) -> void: Config.set_value("controller.guide_hold", str(v)))
	if ex.has("clips") and Config.DEFAULTS.has("capture"):
		var cv = _row(rows, "choice", "Aufnahmen und Clips", "Die letzten Sekunden speichern", "Uzai (eigen) lädt einmalig FFmpeg (190 MB).", Config.get_value("capture.via", "uzai"))
		cv.options = [["uzai", "Uzai (eigen)"], ["gamebar", "Windows Game Bar"], ["nvidia", "NVIDIA ShadowPlay"]]
		cv.icon_name = "camera"
		cv.changed.connect(func(v: Variant) -> void: Config.set_value("capture.via", v))
	elif ex.has("clips"):
		var opts: Array = CLIP_KEYS.duplicate(true)
		var cur := str(Config.get_value("system.clip_keys", "WIN+ALT+G"))
		if not opts.any(func(o): return o[0] == cur):
			opts.append([cur, cur])
		var cl = _row(rows, "choice", "Aufnahmen und Clips", "„Clip speichern“ im Guide", "Kürzel der Aufnahme-Software.", cur)
		cl.options = opts
		cl.icon_name = "camera"
		cl.changed.connect(func(v: Variant) -> void: Config.set_value("system.clip_keys", v))
	if ex.has("browser_kern"):
		var bk = _row(rows, "toggle", "Browser-Kern vorab laden", "Uzai Browser gleich startklar",
				"Lädt Chromium (rund 150 MB) im Hintergrund.", bool(Config.get_value("browser.kern_vorab", false)))
		bk.icon_name = "browser"
		bk.changed.connect(func(v: Variant) -> void:
			Config.set_value("browser.kern_vorab", bool(v))
			if bool(v):
				load("res://src/core/browser_kern_lauf.gd").vorab(get_tree()))
	if ex.has("gamebar"):
		_gamebar_row(rows)
	if ex.has("steam_guide"):
		_steam_guide_row(rows)
	_default = Nav.default_in(rows)


## Öffnet die Guide-Taste unter Windows zusätzlich die Game Bar? Erst wenn der Helfer „an“ meldet.
func _gamebar_row(rows: VBoxContainer) -> void:
	var res := await Helper.run("gamebar", {}, 6.0)
	if not is_instance_valid(rows) or not res.get("ok", false) or not (res.get("result") is Dictionary):
		return
	if not bool((res.result as Dictionary).get("enabled", true)):
		return
	var r = _row(rows, "action", "Guide-Taste nur für Uzai", "Xbox Game Bar nicht öffnen",
			"Game Bar weiter mit Win + G.")
	r.icon_name = "controller"
	r.value_text = "Abschalten"
	r.on_activate = func() -> void:
		var done := await Helper.run("gamebar", { "set": false }, 6.0)
		if is_instance_valid(r):
			var ok := bool(done.get("ok", false))
			r.value_text = "Erledigt" if ok else "Ging nicht"
			r.tone = "ok" if ok else "warn"


## Öffnet Steam mit der Guide-Taste Big Picture? Dann gleich hier abschalten (steam_guide.gd), auch
## wenn Steam dafür kurz neu startet. Steht es schon aus oder gibt es kein Steam: keine Zeile.
func _steam_guide_row(rows: VBoxContainer) -> void:
	var aus: Variant = await SteamGuide.stand()
	if not is_instance_valid(rows) or aus == null or bool(aus):
		return
	var r = _row(rows, "action", "Guide-Taste nur für Uzai", "Uzai schaltet Steams Guide-Taste ab: kein Big Picture",
			"Steam startet dafür kurz neu. Gilt auch ohne Uzai – zurück unter Einstellungen › Controller.")
	r.icon_name = "controller"
	var los := func() -> void:
		if not is_instance_valid(r):
			return
		r.value_text = "Wird abgeschaltet …"
		r.tone = ""
		var res := await SteamGuide.stellen(r.get_tree(), true, true)
		if bool(res.ok):
			Config.set_value("controller.steam_guide_aus", true)
		if is_instance_valid(r) and str(res.grund) != "laeuft_schon":
			r.value_text = "Erledigt" if bool(res.ok) else "Ging nicht"
			r.tone = "ok" if bool(res.ok) else "warn"
		if not bool(res.ok) and str(res.grund) != "laeuft_schon":
			Toasts.show_toast("Guide-Taste nicht umgestellt", SteamGuide.grund_text(str(res.grund)), "warning")
	r.on_activate = los
	los.call()


func _server_stored() -> bool:
	for id in ["jellyfin", "emby"]:
		if Konten.stored(id, Config.get_value):
			return true
	return false
