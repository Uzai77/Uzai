extends "res://src/ui/layers/layer.gd"
## Uzai-Browser (Wunschliste 120): ein Browser, der von Grund auf für Controller und Fernseher gebaut
## ist. Die Darstellung der Seite kommt von Uzais eigenem Chromium (CEF) im Browser-Kern (browser_wirt.gd,
## docs/BROWSER_PLAN.md); alles, was man sieht und tut, ist von Uzai: Startseite, Fokusrahmen, Leiste, Tabs,
## Menü, Kontextrad, Tastatur, Lesemodus, Fernbedienung, Gliederung, Wahl-Listen, Formular-Assistent,
## Link-Vorschau, Suche auf der Seite, Blocker-Pille. Die Seite füllt den Schirm, Uzai erscheint nur bei Bedarf.
## Beim ersten Öffnen richtet Uzai den Kern von selbst ein (browser_kern_lauf.gd, Fortschritt in browser_kern_ui.gd
## und auf der Startbühne). Von der Startbühne
## (browser_view.gd) aus wächst die Bühne nahtlos in den Browser (Aufgang).
##
## Bedienung auf einer Seite:
##   Steuerkreuz/linker Stick  von Ziel zu Ziel (browser_karte.gd), langer Text: erst rollen
##   A                         öffnen bzw. klicken; Textfeld: Uzai-Tastatur
##   A halten                  Kontextrad (Öffnen, Neuer Tab, Ans Handy; Video: Fernbedienung, Vollbild)
##   B                         zurück; ohne Verlauf zur Startseite, dort schließt B den Browser
##   rechter Stick             weich rollen mit Trägheit (Kurve wie der Zeiger, lange voll: schneller;
##                             am Seitenende hält es sauber an)
##   LT/RT                     Zoom um das gewählte Ziel (je Seite gemerkt)
##   LB/RB                     in den vorigen/nächsten Bereich der Seite (Kopf, Inhalt, Seitenleiste …);
##                             in einem Formular (nach einem Textfeld): voriges/nächstes Feld
##   X                         Tabs als Karussell mit Vorschau; Y Adresse oder Suche; Menü: Menü
##   L3                        Zeiger (browser_zeiger.gd): linker Stick mit Kurve und Schub, LB/RB halten fein,
##                             bremst über Zielen und rastet ein (Menü: Zeiger-Tempo, Zeiger einrasten),
##                             Steuerkreuz springt ihn zum nächsten Ziel, A klickt das Ziel darunter
##   Video groß                Controller wird Fernbedienung: A Pause, links/rechts 10 s, LB/RB 60 s,
##                             hoch/runter Lautstärke, X stumm, Y Vollbild, A halten: Tempo, Untertitel
##   Suche auf der Seite       (Menü) Y nächster Treffer, B Suche aus
##   Dialog der Seite offen    der Fokus bleibt darin (browser_karte.gd aktive)
##   Link ruht 0,9 s           seine Adresse steht leise unter dem Rahmen (Link-Vorschau)
## Unter Windows liegt Uzai dabei durchsichtig über dem Fenster des Wirts (main.see_through); im
## Vorführmodus zeichnet browser_seite_demo.gd an seiner Stelle die Platzhalter-Seite.
##
## Spotify-Modus (spotify = true, „Mit Spotify anmelden“, src/ui/layers/spotify_anmelden.gd): derselbe Browser mit
## dem Kern der Spotify-Sitzung (eigener Ordner, nur Spotify, spotify_web.gd) und nur der Anmeldeseite – ohne
## Startseite, Tabs, Adresse und Kontextrad, ohne Verlauf, Lesezeichen und Sitzung. Meldet der Kern einen Schlüssel,
## prüft Music ihn (web_angemeldet); gehört er zu einem Konto, schließt das Fenster von selbst. B ohne Verlauf schließt.

const Wirt := preload("res://src/core/browser_wirt.gd")
const P := preload("res://src/core/browser_protokoll.gd")
const K := preload("res://src/core/browser_karte.gd")
const D := preload("res://src/core/browser_daten.gd")
const Adresse := preload("res://src/core/browser_adresse.gd")
const Start := preload("res://src/ui/layers/browser_start.gd")
const SeiteDemo := preload("res://src/ui/components/browser_seite_demo.gd")
const Karussell := preload("res://src/ui/layers/browser_tabs.gd")
const Rad := preload("res://src/ui/layers/browser_rad.gd")
const Lesen := preload("res://src/ui/layers/browser_lesen.gd")
const KernUi := preload("res://src/ui/layers/browser_kern_ui.gd")
const Kern := preload("res://src/core/browser_kern.gd")
const KernLauf := preload("res://src/core/browser_kern_lauf.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Zeiger := preload("res://src/core/browser_zeiger.gd")
const SpotifyWeb := preload("res://src/core/spotify_web.gd")
const Zustand := preload("res://src/core/zustand.gd")

## Ansicht des Browsers: seine Startseite oder eine Seite.
const ZUSTAENDE_MODUS := { "": ["start"], "start": ["seite"], "seite": ["start"] }
## Frage nach der Adresse eines Links (Ans Handy, Link-Vorschau): offen bis zur Antwort oder bis sie verfällt.
const ZUSTAENDE_LINK := { "*": [""], "": ["handy", "vorschau"], "handy": [], "vorschau": ["handy"] }
## So lange gilt eine Frage nach der Adresse eines Links. Der Kern antwortet nur für Links mit http(s)-Adresse und
## nur im Tab vorn – ohne Antwort blieb die Frage früher offen und die Link-Vorschau kam bis zum Schließen nie wieder.
const LINK_WARTE_MS := 3000

const ZOOMS := [50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300]
const ROLL_VH := 3.0               ## Bildhöhen je Sekunde bei vollem rechten Stick …
const ROLL_SCHUB := 2.0           ## … lange voll gehalten bis zu so viel schneller
const ROLL_TOT := 0.16
const ANSTOSS := 2600             ## Anstoß, wenn ein Druck die Seite erst rollt
const ZEIGER_TAKT := 25           ## ms: so oft höchstens geht die Stelle des Zeigers an die Seite (Hover)
const UI_S := 3.2                 ## so lange stehen Leiste und Tasten nach einem Seitenwechsel
const VORSCHAU_MS := 900          ## ruht der Fokus so lange auf einem Link, steht seine Adresse unter dem Rahmen
const WEBVIEW2_LINK := "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
const T_AUFGANG := 0.46           ## die Startbühne wächst in dieser Zeit zum Browser

var main
var start_url := ""               ## gleich öffnen (Kachel einer Seite, App)
var start_zoom := 0
var allein := false               ## als eigenes Programm gestartet (--browser): Schließen beendet Uzai
var spotify := false              ## „Mit Spotify anmelden“: nur die Spotify-Anmeldung (siehe Kopf)
var _spotify_prueft := false
var _spotify_abschluss := false   ## Anmeldung durch: die Spotify-Oberfläche bleibt verdeckt, Uzai schließt ab
const SPOTIFY_ABSCHLUSS_S := 15.0  ## so lange höchstens auf den Schlüssel warten, dann trotzdem zu
var von := {}                     ## Startbühne, von der der Browser aufgeht: { rect, marke, hoehe } (Schirm-Koordinaten)
var wirt: Wirt
var tabs := {}                    ## Tab → { url, titel, laedt, zurueck, vor, zoom, privat, karte, ziele, fokus, video, bild }
var reihe: Array = []             ## Reihenfolge der Tabs
var aktiv := 0
var geschlossen: Array = []       ## zuletzt geschlossen [{ url, titel, privat }], höchstens 10
var modus := "":                  ## "start" oder "seite"
	set(neu):
		Zustand.wechsel("browser.modus", ZUSTAENDE_MODUS, modus, neu)
		modus = neu

var _neu_tab := false             ## die Startseite öffnet als neuer Tab (Menü › Neuer Tab)
var _privat_neu := false
var _start: Start
var _demo: Control
var _rahmen: Rahmen
var _kopf: PanelContainer
var _kopf_host: Label
var _kopf_titel: Label
var _kopf_zusatz: Label
var _kopf_ic: TextureRect
var _tasten: HBoxContainer
var _pille: PanelContainer
var _seite: Control
var _ui_bis := 0
var _sprung_ms := 0
var _roll_v := Vector2.ZERO
var _roll_ms := 0
var _roll_stopp_ms := 0           ## da hörte das Rollen auf (bis zur nächsten Karte sind die Ziele alt)
var _roll_voll := 0.0             ## so lange schon voll gerollt (Schub)
var _rand_ton := false            ## Seitenende schon gemeldet (einmal je Rollen)
var _rad_rest := 0.0              ## Rollen über einem Rahmen: Rad-Schritte, noch nicht geschickt
var _rad_ms := 0
var _karte_ms := 0
var _her := {}                    ## letzter Sprung { von, nach, dir }: die Gegenrichtung führt zurück
var _l3 := false
var zeiger_an := false
var _zg := Zeiger.new()
var _zeiger_ms := 0
var _zeiger_gesendet := Vector2i(-1, -1)
var video_an := false
var _video_aus_url := ""
var _link_wunsch := "":
	set(neu):
		Zustand.wechsel("browser.link", ZUSTAENDE_LINK, _link_wunsch, neu)
		_link_wunsch = neu
var _link_ms := 0                 ## wann die offene Frage nach einer Link-Adresse ging (LINK_WARTE_MS)
var _maus_ms := 0
var _zu := false
var _vorschau_id := -1            ## Link, dessen Adresse schon unter dem Rahmen steht (oder angefragt ist)
var _suche_an := false
var _suche := {}                  ## letztes Suche-Ereignis { treffer, aktuell }
var _formular := {}               ## letztes Formular-Ereignis { id, index, anzahl, ende } (LB/RB wechseln das Feld)
var _video_leiste: Control
var _aufgang: Control
var _kern_ui: Control
var _pad_vorher := false          ## Nav.pad_unfocused vor der Seite (zurück beim Verlassen)
var _pad_gesetzt := false
var _fokus_meldungen := 0
var zu_grund := ""                ## warum der Browser zugeht (Protokoll)


func build() -> void:
	dim = 0.0
	depth = false
	# Kein dunkler Auslauf unten über der Seite; B schließt auf der Startseite den Browser.
	set_meta("uz_ohne_auslauf", true)
	set_meta("uz_hint_b", "Schließen")
	if is_instance_valid(_scrim):
		_scrim.color = Color(0, 0, 0, 0)
	wirt = Wirt.new()
	wirt.spotify = spotify
	add_child(wirt)
	if wirt.demo:
		_demo = SeiteDemo.new()
		U.full_rect(_demo)
		_demo.visible = false
		add_child(_demo)
	_start = Start.new()
	_start.connect("suchen", _adresse)
	_start.connect("oeffnen", func(url: String, zoom: int) -> void: _oeffnen(url, true, zoom))
	add_child(_start)
	_rahmen = Rahmen.new()
	U.full_rect(_rahmen)
	add_child(_rahmen)
	_seite = SeitenFokus.new()
	_seite.set_meta("uz_key", "browser:seite")
	_seite.set_meta("uz_on_hold_a", _rad_auf)
	_seite.set_meta("uz_on_x", _karussell)
	_seite.set_meta("uz_on_y", _y)
	_seite.connect("gedrueckt", _a)
	add_child(_seite)
	_kopf_bauen()
	_video_leiste = VideoLeiste.new()
	U.full_rect(_video_leiste)
	_video_leiste.visible = false
	add_child(_video_leiste)
	# Tastenzeile unten rechts, nur bei Bedarf – auf einer matten Pille (wie im Regal), damit sie auf jeder
	# Seite lesbar ist.
	var halt := U.margin(0, 0, 96, 30)
	U.full_rect(halt)
	halt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var unten := VBoxContainer.new()
	unten.alignment = BoxContainer.ALIGNMENT_END
	unten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halt.add_child(unten)
	_pille = PanelContainer.new()
	var psb := UzTheme.flaeche(UzTheme.col("surface"), UzTheme.r_pill(), 3)
	psb.content_margin_left = 26
	psb.content_margin_right = 26
	psb.content_margin_top = 10
	psb.content_margin_bottom = 10
	_pille.add_theme_stylebox_override("panel", psb)
	UzTheme.kernlicht(_pille)
	_pille.size_flags_horizontal = Control.SIZE_SHRINK_END
	_pille.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pille.modulate.a = 0.0
	unten.add_child(_pille)
	_tasten = U.hbox(28)
	_pille.add_child(_tasten)
	add_child(halt)
	wirt.ereignis.connect(_ereignis)
	wirt.beendet.connect(_wirt_aus)
	if is_instance_valid(main):
		main.shell.visible = false
	if spotify:
		_spotify_starten()
		return
	_zeige_start(false)
	wirt.starten()


## Spotify-Modus: erst den unsichtbaren Kern der Sitzung beenden (derselbe Ordner), dann die Anmeldeseite.
func _spotify_starten() -> void:
	modus = "start"
	_start.visible = false
	_seite.visible = false
	_rahmen.visible = false
	_fenster(false)
	var web: Node = Music.web_sitzung()
	web.call("anmeldung_start", wirt)
	await web.call("stoppen")
	if not is_inside_tree() or _zu:
		return
	wirt.starten("Mit Spotify anmelden")


func _first_focus() -> Control:
	return _seite if spotify else _start.standard()


## Von der Startbühne aus kommt der Browser nicht als Überblendung: Die Bühne wächst zum Schirm (Aufgang).
func _auf() -> void:
	if von.is_empty() or not (von.get("rect", null) is Rect2) or U.reduziert():
		super._auf()
		return
	modulate.a = 1.0
	_aufgang = Aufgang.new()
	_aufgang.von = von.rect
	_aufgang.marke_von = von.get("marke", (von.rect as Rect2).get_center())
	_aufgang.hoehe_von = float(von.get("hoehe", 160.0))
	_aufgang.ziel = Callable(_start, "marke_rect")
	_aufgang.dauer = T_AUFGANG
	_aufgang.fertig.connect(func() -> void:
		if is_instance_valid(_start):
			_start.marke_zeigen(true)
		_aufgang = null)
	# Die Startseite kommt unter der wachsenden Fläche hoch, ihre eigene Marke erst, wenn die fliegende da ist.
	_start.marke_zeigen(false)
	_start.modulate.a = 0.0
	U.ankommen(_start, U.T_ORT, "uz_aufgang").tween_property(_start, "modulate:a", 1.0, U.T_ORT).set_delay(T_AUFGANG * 0.45)
	U.full_rect(_aufgang)
	add_child(_aufgang)


## Die Leiste oben, nur bei Bedarf: Schloss bzw. Hinweis, Name der Seite, Titel, „Lädt“, Zoom.
func _kopf_bauen() -> void:
	_kopf = PanelContainer.new()
	var sb := UzTheme.flaeche(UzTheme.col("surface"), UzTheme.r_pill(), 3)
	sb.content_margin_left = 26
	sb.content_margin_right = 30
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_kopf.add_theme_stylebox_override("panel", sb)
	UzTheme.kernlicht(_kopf)
	_kopf.anchor_left = 0.5
	_kopf.anchor_right = 0.5
	_kopf.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_kopf.offset_top = 34
	_kopf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kopf.modulate.a = 0.0
	var h := U.hbox(14)
	_kopf.add_child(h)
	_kopf_ic = U.icon("lock", 22, "muted")
	_kopf_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_kopf_ic)
	_kopf_host = U.label("", "m", "text", "medium")
	_kopf_host.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	h.add_child(_kopf_host)
	_kopf_titel = U.label("", "m", "muted")
	_kopf_titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	h.add_child(_kopf_titel)
	_kopf_zusatz = U.label("", "s", "accent", "medium")
	# Schon von Hand übersetzt (_kopf_auffrischen) und mit laufenden Zahlen: nicht noch einmal durch die Übersetzung.
	_kopf_zusatz.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_kopf_zusatz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_kopf_zusatz)
	add_child(_kopf)


# --- Ansichten: Startseite und Seite ---------------------------------------------------------------

func _zeige_start(fokus := true) -> void:
	modus = "start"
	_pad_ohne_fokus(false)
	video_an = false
	zeiger_an = false
	_rahmen.zeiger(false, Vector2.ZERO)
	_start.visible = true
	_start.aufbauen()
	_seite.visible = false
	_rahmen.visible = false
	if _demo:
		_demo.visible = false
	_ui_ausblenden()
	_fenster(false)
	if fokus and is_inside_tree():
		await get_tree().process_frame
		if is_instance_valid(_start) and _start.visible:
			Nav.focus(_start.standard(), true)


func _zeige_seite() -> void:
	if modus == "seite":
		return
	modus = "seite"
	_start.visible = false
	_seite.visible = true
	_rahmen.visible = true
	if _demo:
		_demo.visible = true
	_fenster(true)
	if is_inside_tree() and Nav.top_layer() == self:
		Nav.focus(_seite, true)
	_pad_ohne_fokus(true)
	_ui_zeigen(UI_S)
	_rahmen_auffrischen()


## Liegt die Seite (Fenster des Kerns) unter Uzais durchsichtigem Fenster, kann Windows den Fokus dem Kern geben
## (Klick, Seite, Start des Prozesses) – Uzai nahm dann keine Controller-Eingaben mehr an (Nav nimmt sie nur mit
## Fensterfokus) und ruhte. Solange die Seite gezeigt wird, gehen sie trotzdem an den Browser (wie beim Video vorn).
func _pad_ohne_fokus(an: bool) -> void:
	if wirt == null or wirt.demo or not Config.is_windows():
		return
	if an and not _pad_gesetzt:
		_pad_vorher = Nav.pad_unfocused
		_pad_gesetzt = true
		Nav.pad_unfocused = true
	elif not an and _pad_gesetzt:
		_pad_gesetzt = false
		Nav.pad_unfocused = _pad_vorher


## Browser weg: Ansicht und offene Frage aus Zustand.lage() (kein alter Stand im Fehlerbericht).
func _exit_tree() -> void:
	Zustand.vergessen("browser.modus")
	Zustand.vergessen("browser.link")


func _notification(what: int) -> void:
	super._notification(what)
	if modus != "seite" or wirt == null or wirt.demo or _fokus_meldungen >= 8:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_fokus_meldungen += 1
		Kern.protokoll("Uzai-Fenster %s (Seite offen, Controller %s)" % ["verlor den Fokus" if what == NOTIFICATION_APPLICATION_FOCUS_OUT else "hat den Fokus",
			"geht weiter an den Browser" if Nav.pad_unfocused else "gesperrt"])


## Uzais Fenster passend zur Ansicht: auf der Startseite der ruhige Hintergrund von Uzai, auf einer
## Seite durchsichtig über dem Fenster des Wirts (nur Windows), im Vorführmodus die Platzhalter-Seite.
func _fenster(seite: bool) -> void:
	if not is_instance_valid(main):
		return
	main.background.visible = not seite
	if wirt.demo:
		return
	main.call("see_through", seite)
	if seite:
		var scr := DisplayServer.window_get_current_screen()
		var pos := DisplayServer.screen_get_position(scr)
		var sz := DisplayServer.screen_get_size(scr)
		wirt.senden("fenster", { "x": pos.x, "y": pos.y, "w": sz.x, "h": sz.y })
	wirt.senden("zeigen", { "an": seite })


func close() -> void:
	if _zu or is_queued_for_deletion():
		return
	_zu = true
	_pad_ohne_fokus(false)
	if spotify:
		# Die Sitzung darf erst wieder einen eigenen Kern starten, wenn dieser weg ist (derselbe Ordner).
		Music.web_sitzung().call("anmeldung_beendet", wirt)
	else:
		D.sitzung_merken(reihe.map(func(id: int) -> Dictionary: return tabs[id]))
	if is_instance_valid(wirt) and not wirt.demo:
		Kern.protokoll("Browser zu: %s" % (zu_grund if zu_grund != "" else "Ebene geschlossen"))
	if is_instance_valid(wirt):
		# Sauber: der Wirt hängt sich an die Wurzel, wartet auf das Ende des Kerns (sonst hart) und räumt sich weg.
		wirt.beenden(zu_grund if zu_grund != "" else "Browser zu")
	if is_instance_valid(main):
		if not wirt.demo:
			main.call("see_through", false)
		main.background.visible = true
		main.shell.visible = true
		main.hint_hud.visible = true
	super.close()
	if allein and is_instance_valid(main):
		main.call("_quit_uzai", false)


# --- Ereignisse des Wirts ------------------------------------------------------------------------

func _ereignis(e: Dictionary) -> void:
	match str(e.t):
		"bereit":
			if start_url != "":
				_oeffnen(start_url, true, start_zoom)
		"fehler":
			_fehler(str(e.code))
		"tab":
			_tab_stand(e)
		"tab-zu":
			_tab_weg(int(e.tab))
		"karte":
			_karte(e)
		"ziel":
			_ziel(e)
		"feld":
			_feld(e)
		"link":
			_link(e)
		"video":
			_video(e)
		"frage":
			_frage(e)
		"meldung":
			Toasts.show_toast(str(e.herkunft), str(e.text), "info")
		"download":
			_download(e)
		"gesperrt":
			_gesperrt(str(e.grund))
		"vorschau":
			_vorschau_laden(int(e.tab), str(e.datei))
		"lesen":
			_lesen_auf(e)
		"vollbild":
			if bool(e.an) and int(e.tab) == aktiv:
				video_an = true
				_tasten_setzen()
		"absturz":
			Toasts.show_toast("Seite reagiert nicht", "Im Menü neu laden.", "warning")
		"gliederung":
			_gliederung_auf(e)
		"wahl":
			_wahl_auf(e)
		"formular":
			_formular_stand(e)
		"suche":
			_suche_stand(e)
		"blocker":
			_blocker_stand(e)
		"kern":
			_kern_stand(e)
		"spotify":
			_spotify_ereignis(e)
		"spotify-antwort":
			# Kontoprüfung gleich nach der Anmeldung läuft in dieser Seite (spotify_web.gd abfrage).
			Music.web_sitzung().call("antwort", e)
	if wirt.demo and modus == "seite":
		_demo.call("zeigen", wirt.demo_seite(aktiv))


## Spotify-Modus: Ist die Anmeldung durch (Webplayer statt Anmeldeseite), zeigt Uzai die Spotify-Oberfläche nie –
## das Fenster wird verdeckt, ein ruhiger Uzai-Zustand steht davor, die Seite arbeitet unsichtbar weiter. Kommt der
## Schlüssel, schließt _spotify_ereignis; sonst geht das Fenster nach SPOTIFY_ABSCHLUSS_S trotzdem zu (Musik nimmt
## dann den Grundmodus und versucht es später erneut, spotify_web.gd).
func _spotify_seite(url: String) -> void:
	if _spotify_abschluss or _zu or not SpotifyWeb.nach_anmeldung(url):
		return
	_spotify_abschluss = true
	_fenster(false)
	var c := CenterContainer.new()
	U.full_rect(c)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := U.vbox(14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(U.label("Spotify wird verbunden …", "xl", "text", "bold"))
	col.add_child(U.label("Bibliothek und Mixe kommen gleich.", "m", "muted", "regular"))
	c.add_child(col)
	add_child(c)
	if not wirt.demo:
		Kern.protokoll("Spotify: Anmeldung durch, Seite verdeckt")
	await get_tree().create_timer(SPOTIFY_ABSCHLUSS_S).timeout
	if _zu or not is_inside_tree():
		return
	if not wirt.demo:
		Kern.protokoll("Spotify: kein Schlüssel nach %d s, Fenster zu" % int(SPOTIFY_ABSCHLUSS_S))
	Toasts.show_toast("Mit Spotify angemeldet", "Bibliothek gerade nicht erreichbar. Uzai versucht es später erneut.", "music", { "ms": 5000 })
	zu_grund = "Spotify ohne Schlüssel"
	close()


## Spotify-Modus: Schlüssel von der Seite – gehört er zu einem Konto, ist die Anmeldung fertig und das Fenster geht zu.
func _spotify_ereignis(e: Dictionary) -> void:
	if not spotify or _spotify_prueft or _zu:
		return
	_spotify_prueft = true
	var t: Dictionary = tabs.get(aktiv, {})
	var ok: bool = await Music.web_angemeldet(e, not SpotifyWeb.auf_anmeldung(str(t.get("url", ""))))
	_spotify_prueft = false
	if not ok or _zu or not is_inside_tree():
		return
	Sfx.play("notify")
	var who := str(Music.me.get("name", ""))
	Toasts.show_toast("Mit Spotify angemeldet", who, "music", { "ms": 3000 })
	zu_grund = "Spotify angemeldet"
	close()


const KERN_FEHLER_TEXT := {
	"kern_sandbox": "Der Browser startet nur mit vollem Schutz, und der ist auf diesem PC gerade nicht verfügbar.",
	"kern_api": "Der geladene Kern passt nicht zu dieser Fassung von Uzai.",
	"kern_signatur": "Die Signatur des Browser-Kerns stimmt nicht.",
	"kern_pfad": "Die Dateien des Browser-Kerns fehlen.",
	"kern_installer": "Der Installer des Browser-Kerns meldet einen Fehler.",
}


func _fehler(code: String) -> void:
	zu_grund = "Fehler: %s" % code
	match code:
		"kern":
			_kern_anbieten()
		"kern_sandbox", "kern_api", "kern_signatur", "kern_pfad", "kern_installer":
			Kern.vergessen(code)
			main.open_dialog("Browser-Kern", TranslationServer.translate(str(KERN_FEHLER_TEXT[code])) + " " + TranslationServer.translate("Uzai kann ihn neu laden."), [
				["Neu laden", func() -> void: _kern_anbieten()],
				["Schließen", func() -> void: close()],
			], "browser", "warn")
		"webview2":
			main.open_dialog("WebView2 fehlt", "Der Browser braucht Microsofts WebView2. Unter Windows 10 kommt es mit Microsoft Edge oder dem Installer von Microsoft.", [
				["Link aufs Handy", func() -> void: _handy(WEBVIEW2_LINK, "WebView2")],
				["Schließen", func() -> void: close()],
			], "browser", "warn")
		"tabs":
			Toasts.show_toast("Höchstens %d Tabs" % P.MAX_TABS, "", "info")
		"pruefung":
			Toasts.show_toast("Browser-Dateien beschädigt", _mit_code("Uzai neu installieren."), "warning")
			close()
		_:
			Toasts.show_toast("Browser startet nicht", _mit_code("Uzai neu starten und nochmal versuchen."), "warning")
			close()


## Text mit dem Code des Wirts (wirt.diagnose, etwa „start K14“); der lange Grund steht in logs/browser_kern.log.
func _mit_code(text: String) -> String:
	var t := TranslationServer.translate(text)
	return t if str(wirt.diagnose) == "" else t + " " + TranslationServer.translate("Code: %s") % str(wirt.diagnose)


func _wirt_aus(grund: String) -> void:
	if grund == "kern_ende" and is_inside_tree() and not is_queued_for_deletion():
		zu_grund = "Kern hat sich beendet"
		close()
		return
	if grund != "ende" and is_inside_tree() and not is_queued_for_deletion():
		_fehler(grund)


func _tab(id := -1) -> Dictionary:
	return tabs.get(aktiv if id < 0 else id, {})


func _tab_stand(e: Dictionary) -> void:
	var id := int(e.tab)
	var t: Dictionary = tabs.get(id, {})
	if t.is_empty():
		t = { "id": id, "url": "", "karte": {}, "ziele": [], "fokus": -1, "video": {}, "bild": null, "stelle": false, "besucht": "" }
		tabs[id] = t
		reihe.append(id)
	var alt := str(t.url)
	for k in ["url", "titel", "laedt", "zurueck", "vor", "zoom", "privat"]:
		t[k] = e[k]
	if str(t.url) != alt:
		t.fokus = -1
		t.stelle = false
		t.video = {}
		t.ziele = []
		t.karte = {}
		t.blocker = {}
		if id == aktiv:
			_formular = {}
			_suche_an = false
			_suche = {}
			_vorschau_id = -1
			_rahmen.hinweis("")
		var z := D.zoom_fuer(str(t.url))
		if z != int(t.zoom) and str(t.url) != "about:blank":
			wirt.senden("zoom", { "tab": id, "prozent": z })
		if id == aktiv:
			_ui_zeigen(UI_S)
	if spotify and id == aktiv:
		_spotify_seite(str(t.url))
	if not bool(t.laedt) and str(t.besucht) != str(t.url) and str(t.url) != "about:blank" and not spotify:
		t.besucht = t.url
		D.besucht(str(t.url), str(t.titel), bool(t.privat))
	if bool(e.aktiv) and aktiv != id:
		aktiv = id
		video_an = false
	elif not bool(e.aktiv) and alt == "" and id != aktiv:
		Toasts.show_toast("Neuer Tab", Adresse.host_von(str(t.url)), "plus")
	if id == aktiv:
		_zeige_seite()
		_kopf_auffrischen()


func _tab_weg(id: int) -> void:
	if not tabs.has(id):
		return
	var t: Dictionary = tabs[id]
	if str(t.url) != "" and str(t.url) != "about:blank":
		geschlossen.push_front({ "url": t.url, "titel": t.titel, "privat": t.privat })
		geschlossen = geschlossen.slice(0, 10)
	tabs.erase(id)
	var i := reihe.find(id)
	reihe.erase(id)
	if aktiv != id:
		return
	aktiv = 0
	if reihe.is_empty():
		_zeige_start()
		return
	tab_waehlen(int(reihe[clampi(i, 0, reihe.size() - 1)]))


func tab_waehlen(id: int) -> void:
	if not tabs.has(id):
		return
	aktiv = id
	video_an = false
	wirt.senden("tab-wahl", { "tab": id })
	_zeige_seite()
	_kopf_auffrischen()
	_rahmen_auffrischen()


func tab_schliessen(id: int) -> void:
	wirt.senden("tab-zu", { "tab": id })


func _vw(t: Dictionary) -> Vector2:
	var k: Dictionary = t.get("karte", {})
	return Vector2(float(k.get("vw", 1280)), float(k.get("vh", 720)))


func _karte(e: Dictionary) -> void:
	var t := _tab(int(e.tab))
	if t.is_empty():
		return
	var alt := _vw(t)
	t.karte = e
	t.ziele = K.als_ziele(e.ziele)
	if int(e.tab) != aktiv:
		return
	var v := _vw(t)
	_karte_ms = Time.get_ticks_msec()
	if zeiger_an and not alt.is_equal_approx(v):
		_zg.umrechnen(alt.x, alt.y, v.x, v.y)
	if _roll_v.y != 0.0 and _am_ende(_roll_v.y) and not _rand_ton:
		_rand_ton = true
		Sfx.play("bump")
	var f := K.finde(t.ziele, int(t.fokus))
	var frisch := Time.get_ticks_msec() - _sprung_ms < 1400
	if f.is_empty() or (not frisch and not K.im_bild(f.r, v.x, v.y)):
		var gem := Vector2(-1, -1)
		if not bool(t.stelle):
			t.stelle = true
			gem = D.stelle(str(t.url))
		elif not f.is_empty():
			# Mit dem Stick weggerollt: das Ziel im Bild, das der alten Stelle am nächsten liegt.
			var c: Vector2 = (f.r as Rect2).get_center()
			gem = Vector2(clampf(c.x, 0, v.x), clampf(c.y, v.y * 0.15, v.y * 0.85)) + Vector2(0, float(e.sy))
		var id := K.erstes(t.ziele, v.x, v.y, gem, float(e.sy))
		if id >= 0:
			t.fokus = id
			wirt.senden("fokus", { "tab": aktiv, "id": id })
	_video_pruefen()
	_rahmen_auffrischen()


func _ziel(e: Dictionary) -> void:
	var t := _tab(int(e.tab))
	if t.is_empty():
		return
	for z in t.ziele:
		if int(z.id) == int(e.id):
			z.r = Rect2(float(e.x), float(e.y), float(e.w), float(e.h))
	if int(e.tab) == aktiv and int(e.id) == int(t.fokus):
		_rahmen_auffrischen()


func _rahmen_auffrischen() -> void:
	var t := _tab()
	if modus != "seite" or t.is_empty():
		_rahmen.setzen(Rect2(), -1)
		return
	var z := K.finde(t.ziele, int(t.fokus))
	if z.is_empty() or zeiger_an:
		_rahmen.setzen(Rect2(), -1)
		return
	var v := _vw(t)
	_rahmen.setzen(K.auf_schirm(z.r, v.x, v.y, size), int(z.id))


func _kopf_auffrischen() -> void:
	var t := _tab()
	if t.is_empty():
		return
	var url := str(t.url)
	_kopf_host.text = Adresse.host_von(url) if url != "about:blank" else ""
	var titel := Adresse.sauber(t.get("titel", ""), 300)
	_kopf_titel.text = titel if titel.length() <= 64 else titel.left(62).strip_edges() + "…"
	_kopf_titel.visible = _kopf_titel.text != "" and _kopf_titel.text != _kopf_host.text
	_kopf_ic.texture = Icons.tex("lock" if Adresse.sicher(url) else "info", 22)
	var zusatz: Array = []
	if bool(t.get("privat", false)):
		zusatz.append(TranslationServer.translate("Privat"))
	if bool(t.get("laedt", false)):
		zusatz.append(TranslationServer.translate("Lädt"))
	if int(t.get("zoom", 100)) != 100:
		zusatz.append("%d %%" % int(t.zoom))
	var bl: Dictionary = t.get("blocker", {})
	if not bl.is_empty():
		if str(bl.get("cookies", "")) == "aus":
			zusatz.append(TranslationServer.translate("Blocker aus"))
		else:
			var n := int(bl.get("anzahl", 0)) + int(bl.get("versteckt", 0))
			if n > 0:
				zusatz.append(TranslationServer.translate("%d geblockt") % n)
			if str(bl.get("cookies", "")) == "abgelehnt":
				zusatz.append(TranslationServer.translate("Cookies abgelehnt"))
	if _suche_an and not _suche.is_empty():
		zusatz.append(TranslationServer.translate("Suche %d/%d") % [int(_suche.aktuell), int(_suche.treffer)])
	_kopf_zusatz.text = "  ·  ".join(zusatz)
	_kopf_zusatz.visible = not zusatz.is_empty()
	if bool(t.get("laedt", false)):
		_ui_zeigen(UI_S)


## Leiste und Tasten kurz zeigen (Seitenwechsel, Zoom, nach dem Öffnen).
func _ui_zeigen(sek: float) -> void:
	if modus != "seite":
		return
	_ui_bis = maxi(_ui_bis, Time.get_ticks_msec() + int(sek * 1000.0))
	_tasten_setzen()
	for c in [_kopf, _pille]:
		if c.modulate.a < 0.99:
			U.ankommen(c, U.T_ORT, "uz_ui").tween_property(c, "modulate:a", 1.0, U.T_ORT)


func _ui_ausblenden() -> void:
	_ui_bis = 0
	for c in [_kopf, _pille]:
		if c.modulate.a > 0.01:
			U.weg(c, "uz_ui").tween_property(c, "modulate:a", 0.0, U.T_WEG)


func _tasten_setzen() -> void:
	U.clear(_tasten)
	var h: Array
	if zeiger_an:
		h = [[["a"], "Klicken"], [["lb"], "Fein"], [["b"], "Zeiger aus"]]
	elif video_an:
		var t := _tab()
		var laeuft := bool((t.get("video", {}) as Dictionary).get("laeuft", false))
		h = [[["a"], "Pause" if laeuft else "Abspielen"], [["lr"], "10 s"], [["y"], "Vollbild"], [["b"], "Zurück"]]
	elif _suche_an:
		h = [[["y"], "Nächster Treffer"], [["b"], "Suche aus"]]
	elif not _formular.is_empty() and int(_formular.get("anzahl", 0)) > 1:
		h = [[["a"], "Öffnen"], [["rb"], "Nächstes Feld"], [["b"], "Zurück"]] if spotify else [[["a"], "Öffnen"], [["rb"], "Nächstes Feld"], [["x"], "Tabs"], [["b"], "Zurück"]]
	elif spotify:
		h = [[["a"], "Öffnen"], [["b"], "Zurück"]]
	else:
		h = [[["a"], "Öffnen"], [["x"], "Tabs"], [["y"], "Adresse"], [["b"], "Zurück"]]
	if is_instance_valid(_video_leiste):
		_video_leiste.visible = video_an and modus == "seite"
	for e in Liste.tasten_ordnen(h):
		_tasten.add_child(U.hint(str(e[0][0]), str(e[1])))


# --- Bedienung ----------------------------------------------------------------------------------

func nav_dir(dir: String) -> bool:
	if modus != "seite" or Nav.top_layer() != self:
		return false
	if zeiger_an:
		# Den linken Stick nimmt der Zeiger selbst (analog, _process); das Steuerkreuz springt zum nächsten Ziel.
		if not Nav.vom_stick:
			_zeiger_springen(dir)
		return true
	if video_an and dir in ["left", "right"]:
		wirt.senden("video", { "tab": aktiv, "aktion": "zurueck" if dir == "left" else "vor" })
		return true
	if video_an and dir in ["up", "down"]:
		wirt.senden("video", { "tab": aktiv, "aktion": "lauter" if dir == "up" else "leiser" })
		return true
	_springen(dir)
	return true


func nav_command(cmd: String) -> bool:
	match cmd:
		"b":
			if modus == "seite":
				_zurueck()
			else:
				zu_grund = "B auf der Startseite"
				close()
			return true
		"menu":
			_menu()
			return true
		"x":
			if modus == "seite" and video_an:
				wirt.senden("video", { "tab": aktiv, "aktion": "stumm" })
				return true
			if not spotify:
				_karussell()
			return true
		"y":
			_y()
			return true
		"lb", "rb":
			if modus == "seite":
				if zeiger_an:
					pass   # gehalten: fein (_process)
				elif video_an:
					wirt.senden("video", { "tab": aktiv, "aktion": "zurueck_lang" if cmd == "lb" else "vor_lang" })
				elif not _formular.is_empty() and int(_formular.get("anzahl", 0)) > 1:
					wirt.senden("feld-weiter", { "tab": aktiv, "id": int(_formular.id), "richtung": -1 if cmd == "lb" else 1 })
				else:
					_bereich(-1 if cmd == "lb" else 1)
				return true
		"lt", "rt":
			if modus == "seite":
				_zoom(-1 if cmd == "lt" else 1)
				return true
	return false


func _a() -> void:
	var t := _tab()
	if modus != "seite" or t.is_empty():
		return
	if zeiger_an:
		_zeiger_klick()
		return
	if video_an:
		wirt.senden("video", { "tab": aktiv, "aktion": "umschalten" })
		return
	if int(t.fokus) < 0:
		return
	# Ein Rahmen (iframe, etwa ein Cookie-Banner fremder Herkunft): das Sprung-Skript sieht nicht hinein – A schaltet
	# den Zeiger auf seiner Mitte ein, A klickt dann dort (der Klick geht als echte Maus an die Seite).
	var z := K.finde(t.ziele, int(t.fokus))
	if not z.is_empty() and str(z.art) == "rahmen":
		_zeiger_umschalten()
		return
	_rahmen.druck()
	wirt.senden("aktivieren", { "tab": aktiv, "id": int(t.fokus), "neu": false })


func _y() -> void:
	if modus == "seite" and video_an:
		wirt.senden("video", { "tab": aktiv, "aktion": "vollbild" })
		return
	if modus == "seite" and _suche_an:
		wirt.senden("suche-weiter", { "tab": aktiv, "richtung": 1 })
		return
	if not spotify:
		_adresse()


func _springen(dir: String) -> void:
	var t := _tab()
	if t.is_empty() or (t.karte as Dictionary).is_empty():
		return
	var v := _vw(t)
	var von := int(t.fokus)
	var r := K.naechstes(t.ziele, von, dir, v.x, v.y, _her)
	if int(r.id) >= 0:
		_her = { "von": von, "nach": int(r.id), "dir": dir }
		_fokus_setzen(int(r.id))
	elif str(r.rollen) != "":
		_anstossen(str(r.rollen))


func _fokus_setzen(id: int) -> void:
	var t := _tab()
	t.fokus = id
	_sprung_ms = Time.get_ticks_msec()
	_vorschau_id = -1
	_rahmen.hinweis("")
	if not _formular.is_empty() and int(_formular.get("id", 0)) != id:
		_formular = {}
		_tasten_setzen()
	wirt.senden("fokus", { "tab": aktiv, "id": id })
	Sfx.play("move")
	var z := K.finde(t.ziele, id)
	if not z.is_empty() and not spotify:
		D.stelle_merken(str(t.url), K.stelle(z, float(t.karte.get("sy", 0))), bool(t.privat))
	_rahmen_auffrischen()


## Ein Druck ohne Ziel in der Richtung: die Seite rollt ein Stück (läuft mit Trägheit aus).
func _anstossen(dir: String) -> void:
	var t := _tab()
	var k: Dictionary = t.karte
	var sy := int(k.get("sy", 0))
	if (dir == "up" and sy <= 0) or (dir == "down" and sy + int(k.get("vh", 0)) >= int(k.get("sh", 0)) - 1):
		Sfx.play("bump")
		return
	var v := Vector2i.ZERO
	match dir:
		"up": v.y = -ANSTOSS
		"down": v.y = ANSTOSS
		"left": v.x = -ANSTOSS
		"right": v.x = ANSTOSS
	wirt.senden("rollen", { "tab": aktiv, "vx": v.x, "vy": v.y })
	_roll_stopp_ms = Time.get_ticks_msec() + 120
	var tab := aktiv
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(wirt) and _roll_v == Vector2.ZERO:
			wirt.senden("rollen", { "tab": tab, "vx": 0, "vy": 0 }))


func _bereich(d: int) -> void:
	var t := _tab()
	var v := _vw(t)
	var id := K.bereich_sprung(t.ziele, int(t.fokus), d, v.x, v.y)
	if id >= 0:
		_fokus_setzen(id)
	else:
		Sfx.play("bump")


func _zoom(d: int) -> void:
	var t := _tab()
	if t.is_empty():
		return
	var z := int(t.get("zoom", 100))
	var i := ZOOMS.find(z)
	if i < 0:
		i = ZOOMS.find(100)
		for k in ZOOMS.size():
			if ZOOMS[k] <= z:
				i = k
	var j := clampi(i + d, 0, ZOOMS.size() - 1)
	if j == i:
		Sfx.play("bump")
		return
	t.zoom = ZOOMS[j]
	wirt.senden("zoom", { "tab": aktiv, "prozent": int(t.zoom) })
	if not spotify:
		D.zoom_merken(str(t.url), int(t.zoom))
	Sfx.play("tick")
	_kopf_auffrischen()
	_ui_zeigen(1.6)


func _zurueck() -> void:
	if zeiger_an:
		_zeiger_umschalten()
		return
	if _suche_an:
		_suche_aus()
		return
	if video_an:
		video_an = false
		_video_aus_url = str(_tab().get("url", ""))
		_tasten_setzen()
		_ui_zeigen(1.6)
		return
	var t := _tab()
	if not t.is_empty() and bool(t.zurueck):
		Sfx.play("back")
		wirt.senden("zurueck", { "tab": aktiv })
		return
	Sfx.play("back")
	if spotify:
		zu_grund = "B ohne Verlauf (Spotify-Anmeldung)"
		close()
		return
	_neu_tab = false
	_zeige_start()


func _adresse() -> void:
	var t := _tab()
	var jetzt := str(t.get("url", "")) if modus == "seite" and str(t.get("url", "")) != "about:blank" else ""
	main.open_keyboard("Adresse oder Suche", jetzt, func(text: String) -> void:
		var d := Adresse.deuten(text, D.suchmaschine())
		if d.is_empty():
			return
		if str(d.grund) != "":
			_gesperrt(str(d.grund))
			return
		_oeffnen(str(d.url), true, 0), false, "", Tastatur.kuerzel_fuer("adresse"))


## Eine Adresse öffnen: im Tab vorn, als neuer Tab (Menü › Neuer Tab, noch kein Tab) bzw. privat.
func _oeffnen(url: String, nutzer: bool, zoom: int) -> void:
	if Adresse.grund(url, nutzer) != "":
		_gesperrt(Adresse.grund(url, nutzer))
		return
	if zoom > 0:
		D.zoom_merken(url, zoom)
	var neu := _neu_tab or aktiv == 0 or not tabs.has(aktiv)
	if neu and reihe.size() >= P.MAX_TABS:
		Toasts.show_toast("Höchstens %d Tabs" % P.MAX_TABS, "", "info")
		neu = false
	if neu:
		wirt.senden("tab-neu", { "url": url, "privat": _privat_neu, "vorn": true, "nutzer": nutzer })
	else:
		wirt.senden("laden", { "tab": aktiv, "url": url, "nutzer": nutzer })
		_zeige_seite()
	_neu_tab = false
	_privat_neu = false


func neuer_tab(privat := false) -> void:
	_neu_tab = true
	_privat_neu = privat
	_zeige_start()


func wiederherstellen() -> void:
	if geschlossen.is_empty():
		return
	var g: Dictionary = geschlossen.pop_front()
	_neu_tab = true
	_privat_neu = bool(g.privat)
	_oeffnen(str(g.url), false, 0)


# --- Textfelder, Links, Video -------------------------------------------------------------------

const Tastatur := preload("res://src/ui/layers/keyboard.gd")
const FELD_TITEL := { "text": "Text", "suche": "Suchen", "email": "E-Mail", "zahl": "Zahl", "passwort": "Passwort", "url": "Adresse",
	"tel": "Telefonnummer", "bereich": "Text" }


func _feld(e: Dictionary) -> void:
	if int(e.tab) != aktiv:
		return
	var typ := str(e.typ)
	var id := int(e.id)
	var l = Tastatur.new()
	l.heading = str(FELD_TITEL.get(typ, "Text"))
	l.text = str(e.wert)
	l.kuerzel = Tastatur.kuerzel_fuer("adresse" if typ == "url" else typ)
	l.secret = typ == "passwort"
	# Die Handy-Seite ist unverschlüsselt: kein Passwort darüber.
	l.phone_ok = typ != "passwort"
	l.done.connect(func(text: String) -> void:
		if not is_instance_valid(wirt):
			return
		wirt.senden("text", { "tab": aktiv, "id": id, "text": text.left(2000) })
		if typ == "suche":
			wirt.senden("taste", { "tab": aktiv, "taste": "enter" }))
	main.open_layer(l)


func _link(e: Dictionary) -> void:
	if int(e.tab) != aktiv:
		return
	if _link_wunsch == "handy":
		_handy(str(e.url), Adresse.host_von(str(e.url)))
	elif _link_wunsch == "vorschau" and int(e.id) == int(_tab().get("fokus", -1)):
		# Link-Vorschau: nur der Name der Seite, leise unter dem Rahmen – nie die ganze Adresse (Platz, Ruhe).
		var host := Adresse.host_von(str(e.url))
		var eigener := Adresse.host_von(str(_tab().get("url", "")))
		_rahmen.hinweis("" if host == "" or host == eigener else host.trim_prefix("www."))
	_link_wunsch = ""


func _video(e: Dictionary) -> void:
	var t := _tab(int(e.tab))
	if t.is_empty():
		return
	t.video = e
	if int(e.tab) == aktiv:
		_video_pruefen()
		if is_instance_valid(_video_leiste):
			_video_leiste.call("stand", e)
			if video_an:
				_ui_zeigen(2.0)


func _video_pruefen() -> void:
	var t := _tab()
	if t.is_empty() or zeiger_an:
		return
	var v := _vw(t)
	var soll := K.video_modus(t.video, t.ziele, v.x, v.y) and _video_aus_url != str(t.url)
	if not bool((t.video as Dictionary).get("laeuft", false)):
		_video_aus_url = ""
	if soll != video_an and (soll or not bool((t.video as Dictionary).get("da", false))):
		video_an = soll
		_ui_zeigen(2.0)
	elif video_an:
		_tasten_setzen()


# --- Fragen der Seite, Downloads, Sperren --------------------------------------------------------

const FRAGE_TEXT := { "kamera": "%s möchte deine Kamera nutzen.", "mikrofon": "%s möchte dein Mikrofon nutzen.",
	"standort": "%s möchte deinen Standort wissen." }


func _frage(e: Dictionary) -> void:
	var id := int(e.frage)
	var art := str(e.art)
	var herkunft: String = str(e.herkunft) if str(e.herkunft) != "" else str(TranslationServer.translate("Eine Seite"))
	var antwort := func(ja: bool) -> void:
		if is_instance_valid(wirt):
			wirt.senden("antwort", { "frage": id, "ja": ja })
	if art == "bestaetigen":
		main.open_dialog(herkunft, str(e.text), [["OK", antwort.bind(true)], ["Abbrechen", antwort.bind(false)]], "browser")
		return
	main.open_dialog("Erlauben?", TranslationServer.translate(str(FRAGE_TEXT.get(art, "%s"))) % herkunft,
			[["Ablehnen", antwort.bind(false)], ["Erlauben", antwort.bind(true)]], "lock")


func _download(e: Dictionary) -> void:
	match str(e.stand):
		"laeuft":
			Toasts.show_toast("Download läuft", str(e.name), "download")
		"fertig":
			Toasts.show_toast("Download fertig", "Downloads › Uzai Browser", "download")
		"gesperrt":
			Toasts.show_toast("Download gesperrt", "Programme und Skripte lädt der Browser nicht.", "lock")
		_:
			Toasts.show_toast("Download abgebrochen", str(e.name), "warning")


const SPERR_TEXT := {
	"lokal": ["Gesperrt", "Adressen auf diesem PC öffnet der Browser nie."],
	"heimnetz": ["Gesperrt", "Ins Heimnetz nur, wenn du die Adresse selbst eingibst."],
	"protokoll": ["Gesperrt", "Nur Webseiten (http und https)."],
	"app": ["Link zu einer App gesperrt", "Der Browser startet keine Programme."],
	"popup": ["Pop-up blockiert", ""],
	"zertifikat": ["Unsichere Verbindung", "Das Zertifikat der Seite stimmt nicht."],
	"anmeldedialog": ["Anmeldefenster gesperrt", ""],
	"anmeldung": ["Gesperrt", "Adressen mit Anmeldedaten öffnet der Browser nicht."],
	"download": ["Download gesperrt", ""],
	"nur_spotify": ["Nur Spotify", "In diesem Fenster öffnet sich nur Spotify."],
}


func _gesperrt(grund: String) -> void:
	var t: Array = SPERR_TEXT.get(grund, ["Adresse ungültig", ""])
	Toasts.show_toast(str(t[0]), str(t[1]), "lock")


# --- Kontextrad, Tabs, Menü, Lesemodus, Handy -------------------------------------------------------

func _rad_auf() -> void:
	var t := _tab()
	if modus != "seite" or t.is_empty() or spotify:
		return
	# Mit dem Zeiger: das Ziel darunter (ein Rahmen hat kein Rad – dort weiß nur die Seite, was liegt).
	var z := K.finde(t.ziele, int(t.fokus)) if not zeiger_an else (_zg.ueber if _ziele_frisch() else {})
	if z.is_empty() or (zeiger_an and str(z.art) == "rahmen"):
		return
	var id := int(z.id)
	var opts: Array = []
	match str(z.art):
		"feld":
			wirt.senden("feld", { "tab": aktiv, "id": id })
			return
		"video":
			opts = [["play", "Abspielen", func() -> void: wirt.senden("video", { "tab": aktiv, "aktion": "umschalten" })],
				["tv", "Vollbild", func() -> void: wirt.senden("video", { "tab": aktiv, "aktion": "vollbild" })],
				["controller", "Fernbedienung", func() -> void:
					video_an = true
					_video_aus_url = ""
					_ui_zeigen(2.0)],
				["speed", "Schneller", func() -> void: wirt.senden("video", { "tab": aktiv, "aktion": "tempo_auf" })],
				["skip", "Langsamer", func() -> void: wirt.senden("video", { "tab": aktiv, "aktion": "tempo_ab" })],
				["subtitles", "Untertitel", func() -> void: wirt.senden("video", { "tab": aktiv, "aktion": "untertitel" })]]
		_:
			opts = [["chevron_right", "Öffnen", func() -> void: wirt.senden("aktivieren", { "tab": aktiv, "id": id, "neu": false })],
				["plus", "Neuer Tab", func() -> void: wirt.senden("aktivieren", { "tab": aktiv, "id": id, "neu": true })],
				["phone", "Ans Handy", func() -> void:
					_link_wunsch = "handy"
					_link_ms = Time.get_ticks_msec()
					wirt.senden("link", { "tab": aktiv, "id": id })]]
	var v := _vw(t)
	var r = Rad.new()
	r.mitte = K.auf_schirm(z.r, v.x, v.y, size).get_center()
	r.optionen = opts
	main.open_layer(r)


func _karussell() -> void:
	if reihe.is_empty():
		neuer_tab()
		return
	_vorschau_holen()
	var k = Karussell.new()
	k.ebene = self
	main.open_layer(k)


## Vorschau des Tabs vorn: unter Windows macht der Wirt sie (die Seite liegt nicht in Uzais Bild),
## im Vorführmodus ein Bild der Platzhalter-Seite.
func _vorschau_holen() -> void:
	var t := _tab()
	if t.is_empty() or modus != "seite":
		return
	if not wirt.demo:
		wirt.senden("vorschau", { "tab": aktiv })
		return
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.resize(640, int(640.0 * img.get_height() / maxf(1.0, img.get_width())), Image.INTERPOLATE_BILINEAR)
	t.bild = ImageTexture.create_from_image(img)


## Vorschau-Datei des Wirts (nur sein eigener Ordner, Name nach festem Muster): als fremdes Bild
## gelesen, Größe vor dem Dekodieren begrenzt.
func _vorschau_laden(tab: int, datei: String) -> void:
	var t := _tab(tab)
	var basis := OS.get_environment("LOCALAPPDATA")
	if t.is_empty() or basis == "":
		return
	var pfad := basis.path_join("Uzai/browser/vorschau").path_join(datei)
	var f := FileAccess.open(pfad, FileAccess.READ)
	if f == null or f.get_length() > 4 * 1024 * 1024:
		return
	var b := f.get_buffer(f.get_length())
	var img := Image.new()
	if img.load_jpg_from_buffer(b) != OK or img.get_width() > 8192 or img.get_height() > 8192:
		return
	img.resize(640, int(640.0 * img.get_height() / maxf(1.0, img.get_width())), Image.INTERPOLATE_BILINEAR)
	t.bild = ImageTexture.create_from_image(img)


func _menu() -> void:
	if spotify:
		_spotify_menu()
		return
	var t := _tab()
	var seite := modus == "seite" and not t.is_empty()
	var url := str(t.get("url", "")) if seite else ""
	var s = Sheet.new().setup("Browser", Adresse.host_von(url) if seite else "")
	s.fill_func = func(sh: Sheet) -> void:
		var zeile := func(icon: String, text: String, cb: Callable, extra: String) -> void:
			var it = ListItem.new().setup(text, "", extra)
			it.icon_name = icon
			it.activated.connect(func() -> void:
				sh.close()
				cb.call())
			sh.add_row(it)
		zeile.call("plus", "Neuer Tab", func() -> void: neuer_tab(false), "")
		zeile.call("lock", "Privater Tab", func() -> void: neuer_tab(true), "")
		if seite and Adresse.grund(url, true) == "":
			var fav := D.hat("favoriten", url)
			var fav_cb := func() -> void:
				var an := D.favorit_umschalten(url, str(t.titel))
				Toasts.show_toast("Lesezeichen gesetzt" if an else "Lesezeichen entfernt", Adresse.host_von(url), "star")
			zeile.call("star", "Lesezeichen entfernen" if fav else "Lesezeichen setzen", fav_cb, "")
			var app := D.hat("apps", url)
			var app_cb := func() -> void:
				var an := D.app_umschalten(url, str(t.titel), int(t.zoom))
				Toasts.show_toast("Als App angeheftet" if an else "App gelöst", Adresse.host_von(url), "apps")
			zeile.call("apps", "App lösen" if app else "Als App anheften", app_cb, "")
			zeile.call("file", "Lesemodus", func() -> void: wirt.senden("lesen", { "tab": aktiv }), "")
			zeile.call("list", "Gliederung", func() -> void: wirt.senden("gliederung", { "tab": aktiv }), "")
			zeile.call("search", "Auf der Seite suchen", func() -> void: _suche_auf(), "")
			var host := Adresse.host_von(url)
			var aus := _blocker_aus_fuer(host)
			var bl: Dictionary = t.get("blocker", {})
			var bl_text := ""
			if not aus and not bl.is_empty():
				bl_text = TranslationServer.translate("%d geblockt") % (int(bl.get("anzahl", 0)) + int(bl.get("versteckt", 0)))
			zeile.call("eye" if aus else "eye_off", "Blocker hier einschalten" if aus else "Blocker hier ausschalten",
				func() -> void: _blocker_umschalten(host), bl_text)
			zeile.call("phone", "Ans Handy senden", func() -> void: _handy(url, Adresse.host_von(url)), "")
			zeile.call("refresh", "Neu laden", func() -> void: wirt.senden("neu", { "tab": aktiv }), "")
			if int(t.zoom) != 100:
				var zoom_cb := func() -> void:
					t.zoom = 100
					wirt.senden("zoom", { "tab": aktiv, "prozent": 100 })
					D.zoom_merken(url, 100)
					_kopf_auffrischen()
				zeile.call("search", "Zoom zurücksetzen", zoom_cb, "%d %%" % int(t.zoom))
			zeile.call("move", "Zeiger aus" if zeiger_an else "Zeiger", func() -> void: _zeiger_umschalten(), "")
		sh.add_gap()
		zeile.call("search", "Suchmaschine", func() -> void: _suchmaschine(), str(Adresse.maschine(D.suchmaschine()).name))
		zeile.call("speed", "Zeiger-Tempo", func() -> void: _zeiger_tempo_waehlen(), str(TEMPO_NAMEN.get(_zeiger_tempo(), "")))
		var rasten := func() -> void:
			var an := not _einrasten()
			Config.set_value("browser.zeiger_einrasten", an)
			Toasts.show_toast("Zeiger rastet ein" if an else "Zeiger rastet nicht ein", "", "move")
		zeile.call("move", "Zeiger einrasten", rasten, "An" if _einrasten() else "Aus")
		var leeren := func() -> void:
			D.verlauf_leeren()
			Toasts.show_toast("Verlauf gelöscht", "", "trash")
		zeile.call("trash", "Verlauf löschen", leeren, "")
		zeile.call("browser", "Browser-Kern", func() -> void: _kern_menu(), _kern_kurz())
		if Config.is_windows() and not allein:
			zeile.call("desktop", "Als eigenes Programm anlegen", func() -> void: _verknuepfung(), "")
		zeile.call("close", "Browser schließen", func() -> void:
			zu_grund = "Menü › Browser schließen"
			close(), "")
	main.open_layer(s)


func _suchmaschine() -> void:
	var opts: Array = []
	for m in Adresse.SUCHMASCHINEN:
		opts.append([m.id, m.name])
	main.open_choice("Suchmaschine", opts, D.suchmaschine(), func(v: Variant) -> void:
		Config.set_value("browser.suche", str(v))
		if modus == "start":
			_start.aufbauen())


## Verknüpfung „Uzai Browser“ auf dem Desktop: startet Uzai gleich im Browser (--browser).
func _verknuepfung() -> void:
	var exe := OS.get_executable_path().replace("/", "\\")
	var r: Dictionary = await Helper.run("shortcut", { "name": "Uzai Browser", "target": exe, "args": "-- --browser", "icon": exe, "where": "desktop" })
	if r.ok:
		Toasts.show_toast("Verknüpfung angelegt", "Uzai Browser", "link")
	else:
		# Mit dem Grund und einem Rat – vorher stand unter „ging nicht“ gar nichts.
		Toasts.show_toast("Verknüpfung ging nicht", Helper.klartext(str(r.get("error", ""))), "warning")


func _lesen_auf(e: Dictionary) -> void:
	if int(e.tab) != aktiv:
		return
	if (e.absaetze as Array).is_empty():
		Toasts.show_toast("Kein Text zum Lesen", "", "info")
		return
	var l = Lesen.new()
	l.titel = str(e.titel)
	l.absaetze = e.absaetze
	l.herkunft = Adresse.host_von(str(_tab().get("url", "")))
	main.open_layer(l)


## Link aufs Handy: QR-Code, keine Verbindung zum Handy nötig.
func _handy(url: String, titel: String) -> void:
	if Adresse.grund(url, true) != "":
		return
	var m = HandyLink.new()
	m.url = url
	m.titel = titel
	main.open_layer(m)


# --- Gliederung, Wahl-Listen, Formular, Suche, Blocker ------------------------------------------------

## Gliederung: die Überschriften der Seite als Liste (eingerückt nach Stufe); A springt dorthin.
func _gliederung_auf(e: Dictionary) -> void:
	if int(e.tab) != aktiv:
		return
	var punkte: Array = e.punkte
	if punkte.is_empty():
		Toasts.show_toast("Keine Überschriften", "", "info")
		return
	var s = Sheet.new().setup("Gliederung", Adresse.host_von(str(_tab().get("url", ""))))
	s.fill_func = func(sh: Sheet) -> void:
		for p in punkte:
			var stufe := clampi(int(p[2]), 1, 6)
			var it = ListItem.new().setup("      ".repeat(stufe - 1) + Adresse.sauber(str(p[3]), 80), "", "")
			it.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Überschrift der Seite: fremder Text
			it.icon_name = "list" if stufe <= 2 else ""
			var id := int(p[0])
			it.activated.connect(func() -> void:
				sh.close()
				if is_instance_valid(wirt):
					wirt.senden("springe", { "tab": aktiv, "id": id })
					_sprung_ms = Time.get_ticks_msec())
			sh.add_row(it)
	main.open_layer(s)


## Auswahlfeld der Seite: Uzais Auswahlliste statt des kleinen Aufklappmenüs der Seite.
func _wahl_auf(e: Dictionary) -> void:
	if int(e.tab) != aktiv:
		return
	var opts: Array = []
	var optionen: Array = e.optionen
	for i in optionen.size():
		opts.append([i, Adresse.sauber(str(optionen[i]), 120)])
	if opts.is_empty():
		return
	var id := int(e.id)
	main.open_choice("Auswahl", opts, int(e.aktuell), func(v: Variant) -> void:
		if is_instance_valid(wirt):
			wirt.senden("wahl-setzen", { "tab": aktiv, "id": id, "index": int(v) }))


## Formular-Assistent: nach einem Textfeld führt RB ins nächste Feld, LB zurück (Tastenzeile sagt es).
func _formular_stand(e: Dictionary) -> void:
	if int(e.tab) != aktiv:
		return
	_formular = e
	_tasten_setzen()
	if int(e.anzahl) > 1 and int(e.index) == 0:
		_ui_zeigen(UI_S)


## Suche auf der Seite: Text aus der Tastatur, Treffer werden auf der Seite markiert, Y springt weiter.
func _suche_auf() -> void:
	if modus != "seite":
		return
	main.open_keyboard("Auf der Seite suchen", "", func(text: String) -> void:
		var t := text.strip_edges().left(200)
		if t == "" or not is_instance_valid(wirt):
			return
		_suche_an = true
		_suche = {}
		wirt.senden("suche", { "tab": aktiv, "text": t })
		_tasten_setzen()
		_ui_zeigen(UI_S))


func _suche_stand(e: Dictionary) -> void:
	if int(e.tab) != aktiv or not _suche_an:
		return
	_suche = { "treffer": int(e.treffer), "aktuell": int(e.aktuell) }
	if int(e.treffer) == 0:
		Toasts.show_toast("Kein Treffer", "", "search")
	_kopf_auffrischen()
	_ui_zeigen(UI_S)


func _suche_aus() -> void:
	_suche_an = false
	_suche = {}
	if is_instance_valid(wirt):
		wirt.senden("suche", { "tab": aktiv, "text": "" })
	Sfx.play("back")
	_kopf_auffrischen()
	_tasten_setzen()
	_ui_zeigen(1.6)


## Blocker-Pille: was der Blocker auf dieser Seite tat, steht in der Leiste oben (Anzahl, Cookies).
func _blocker_stand(e: Dictionary) -> void:
	var t := _tab(int(e.tab))
	if t.is_empty() or spotify:   # die Spotify-Sitzung läuft ohne Blocker
		return
	t.blocker = e
	if int(e.tab) == aktiv:
		_kopf_auffrischen()


static func _blocker_aus_fuer(host: String) -> bool:
	var aus: Variant = Config.get_value("browser.blocker_aus", [])
	return aus is Array and host != "" and (aus as Array).has(host)


## Blocker je Seite aus- und wieder einschalten (gemerkt in browser.blocker_aus, gilt für Kern und Seite sofort).
func _blocker_umschalten(host: String) -> void:
	if host == "":
		return
	var aus: Variant = Config.get_value("browser.blocker_aus", [])
	var liste: Array = (aus as Array).duplicate() if aus is Array else []
	var jetzt_aus := not liste.has(host)
	if jetzt_aus:
		liste.append(host)
		liste = liste.slice(maxi(0, liste.size() - 400), liste.size())
	else:
		liste.erase(host)
	Config.set_value("browser.blocker_aus", liste)
	wirt.senden("blocker-liste", { "hosts": liste })
	wirt.senden("blocker", { "tab": aktiv, "an": not jetzt_aus })
	Toasts.show_toast("Blocker aus" if jetzt_aus else "Blocker an", host, "eye" if jetzt_aus else "eye_off")


# --- Der Browser-Kern: laden, Stand, Sandbox prüfen, Updates ---------------------------------------------

## Erstes Öffnen (oder nach einem Fehler): Uzai richtet den Kern von selbst ein und zeigt den Fortschritt.
## „fehler kern“ kommt schon während build() – der Browser liegt dann noch nicht auf dem Stapel. Darum erst warten,
## bis er oben liegt: sonst legte sich der Browser über den Dialog, und der Fokus kam nie hinein (0.16.15).
func _kern_anbieten() -> void:
	if is_instance_valid(_kern_ui):
		return
	var k = KernUi.new()
	k.wirt = wirt
	k.gespielt = wirt.demo
	_kern_ui = k
	var bis := Time.get_ticks_msec() + 3000
	while is_inside_tree() and not Nav.layers.has(self) and Time.get_ticks_msec() < bis:
		await get_tree().process_frame
	if not is_inside_tree() or is_queued_for_deletion() or _zu:
		_kern_ui = null
		return
	k.fertig.connect(func(ok: bool) -> void:
		_kern_ui = null
		if not is_inside_tree() or is_queued_for_deletion():
			return
		if ok:
			if not wirt.laeuft():
				wirt.starten()
		else:
			close())
	main.open_layer(k)


func _kern_kurz() -> String:
	if wirt.demo:
		return TranslationServer.translate("Vorführung")
	if Wirt.kern() == "webview2":
		return "WebView2"
	var st := Kern.stand()
	return "Chromium %s" % str(st.fassung) if str(st.fassung) != "" else TranslationServer.translate("nicht geladen")


## Browser-Kern: Stand, Sandbox prüfen (Diagnose des laufenden Kerns), Update jetzt, Kern wählen.
## Spotify-Modus: nur Neu laden und Schließen.
func _spotify_menu() -> void:
	var s = Sheet.new().setup("Mit Spotify anmelden", "")
	s.fill_func = func(sh: Sheet) -> void:
		var zeile := func(icon: String, text: String, cb: Callable) -> void:
			var it = ListItem.new().setup(text, "", "")
			it.icon_name = icon
			it.activated.connect(func() -> void:
				sh.close()
				cb.call())
			sh.add_row(it)
		zeile.call("refresh", "Neu laden", func() -> void:
			if aktiv > 0:
				wirt.senden("neu", { "tab": aktiv }))
		zeile.call("close", "Schließen", func() -> void:
			zu_grund = "Menü › Schließen (Spotify-Anmeldung)"
			close())
	main.open_layer(s)


func _kern_menu() -> void:
	var st := Kern.stand()
	var s = Sheet.new().setup("Browser-Kern", _kern_kurz())
	s.fill_func = func(sh: Sheet) -> void:
		var zeile := func(icon: String, text: String, cb: Callable, extra: String) -> void:
			var it = ListItem.new().setup(text, "", extra)
			it.icon_name = icon
			it.activated.connect(func() -> void:
				sh.close()
				cb.call())
			sh.add_row(it)
		var stand_text: String = str(TranslationServer.translate("Sandbox an, bewährt" if bool(st.gesund) else "noch unbewährt"))
		if wirt.demo:
			stand_text = str(TranslationServer.translate("Vorführung"))
		zeile.call("lock", "Sandbox prüfen", func() -> void: wirt.senden("kern", { "aktion": "diagnose" }), stand_text)
		var naechste := str(Config.get_value("browser.kern_naechste", ""))
		var update := func() -> void:
			Config.set_value("browser.kern_pruefung", int(Time.get_unix_time_from_system()))
			wirt.senden("kern", { "aktion": "update" })
		var bald := ""
		if naechste != "" and naechste != str(st.fassung):
			bald = str(TranslationServer.translate("%s ab dem nächsten Start")) % naechste
		zeile.call("refresh", "Nach Updates suchen", update, bald)
		if Config.is_windows():
			zeile.call("download", "Kern neu laden", func() -> void:
				Kern.vergessen("")
				wirt.senden("ende")
				Kern.protokoll("Neu laden (Menü)")
				KernLauf.starten(wirt.demo)
				_kern_anbieten(), "")
			var wahl := func() -> void:
				main.open_choice("Browser-Kern", [["cef", "Uzai-Chromium (CEF, Sandbox, Blocker)"], ["webview2", "WebView2 (Notnagel: Edge von Windows)"]],
					Wirt.kern(), func(v: Variant) -> void:
						if str(v) in Wirt.KERNE and str(v) != Wirt.kern():
							Config.set_value("browser.kern", str(v))
							Toasts.show_toast("Browser-Kern gewechselt", "Gilt ab dem nächsten Öffnen.", "browser"))
			zeile.call("browser", "Kern wählen", wahl, "CEF" if Wirt.kern() == "cef" else "WebView2")
			var grafik := func() -> void:
				main.open_choice("Grafik", [["hardware", "Hardware (Grafikkarte)"], ["software", "Software (wenn der Grafikprozess nicht läuft)"]],
					Wirt.grafik(), func(v: Variant) -> void:
						if str(v) in ["hardware", "software"] and str(v) != Wirt.grafik():
							Config.set_value("browser.kern_grafik", str(v))
							Kern.protokoll("Grafik im Menü: %s" % str(v))
							Toasts.show_toast("Grafik umgestellt", "Gilt ab dem nächsten Öffnen.", "browser"))
			zeile.call("monitor", "Grafik", grafik, "Software" if Wirt.grafik() == "software" else "Hardware")
	main.open_layer(s)


func _kern_stand(e: Dictionary) -> void:
	match str(e.stand):
		"diagnose":
			main.open_dialog("Sandbox prüfen", Adresse.sauber(str(e.text), 1200), [["OK", func() -> void: pass]], "lock")
		"update":
			if str(e.fassung) != "":
				Toasts.show_toast("Browser-Kern aktualisiert", TranslationServer.translate("%s ab dem nächsten Start") % str(e.fassung), "download")
		"stand":
			if str(e.schritt) == "update" and str(Config.get_value("browser.kern_naechste", "")) == "":
				Toasts.show_toast("Browser-Kern ist aktuell", str(e.fassung) if not wirt.demo else "", "check")
		"fehler":
			# Gründe beim Start (schritt „grund“) zeigt der Hinweis „Browser startet nicht“ als Code; der Text steht im Protokoll.
			if str(e.schritt) != "grund":
				Toasts.show_toast("Browser-Kern", Adresse.sauber(str(e.text), 200), "warning")


# --- Zeiger, rechter Stick, Maus -----------------------------------------------------------------

const TEMPO_NAMEN := { "langsam": "Langsam", "mittel": "Mittel", "schnell": "Schnell" }


static func _zeiger_tempo() -> String:
	var n := str(Config.get_value("browser.zeiger_tempo", Zeiger.STANDARD_TEMPO))
	return n if Zeiger.TEMPI.has(n) else Zeiger.STANDARD_TEMPO


static func _einrasten() -> bool:
	return bool(Config.get_value("browser.zeiger_einrasten", true))


func _zeiger_tempo_waehlen() -> void:
	var opts: Array = []
	for n in ["langsam", "mittel", "schnell"]:
		opts.append([n, TEMPO_NAMEN[n]])
	main.open_choice("Zeiger-Tempo", opts, _zeiger_tempo(), func(v: Variant) -> void:
		Config.set_value("browser.zeiger_tempo", str(v)))


func _zeiger_umschalten() -> void:
	var t := _tab()
	if modus != "seite" or t.is_empty():
		return
	zeiger_an = not zeiger_an
	if zeiger_an:
		var v := _vw(t)
		var z := K.finde(t.ziele, int(t.fokus))
		_zg.setzen((z.r as Rect2).intersection(Rect2(Vector2.ZERO, v)).get_center() if not z.is_empty() else v * 0.5)
		_zeiger_gesendet = Vector2i(-1, -1)
		_zeiger_senden(true)
	_rahmen.zeiger(zeiger_an, _zeiger_schirm(), _hover_schirm())
	Sfx.play("select")
	_rahmen_auffrischen()
	_ui_zeigen(1.8)


func _zeiger_schirm() -> Vector2:
	var v := _vw(_tab())
	return _zg.p * Vector2(size.x / maxf(v.x, 1.0), size.y / maxf(v.y, 1.0))


## Rechteck des Ziels unter dem Zeiger auf dem Schirm (leer: keins oder ein Rahmen – dessen Knöpfe kennt nur die Seite).
func _hover_schirm() -> Rect2:
	if _zg.ueber.is_empty() or str(_zg.ueber.art) == "rahmen":
		return Rect2()
	var v := _vw(_tab())
	return K.auf_schirm(_zg.ueber.r, v.x, v.y, size)


## Die Stelle des Zeigers an die Seite (echte Mausbewegung über den Kern: Hover, Aufklappmenüs), höchstens
## alle ZEIGER_TAKT ms und nur, wenn sie sich um einen CSS-Pixel geändert hat – die letzte Stelle kommt immer an.
func _zeiger_senden(immer := false) -> void:
	var v := _vw(_tab())
	var q := Vector2i(clampi(roundi(_zg.p.x), 0, int(v.x)), clampi(roundi(_zg.p.y), 0, int(v.y)))
	if q == _zeiger_gesendet:
		return
	var jetzt := Time.get_ticks_msec()
	if not immer and jetzt - _zeiger_ms < ZEIGER_TAKT:
		return
	_zeiger_ms = jetzt
	_zeiger_gesendet = q
	wirt.senden("zeiger", { "tab": aktiv, "x": q.x, "y": q.y })


## Die Ziele der letzten Karte stimmen: nicht beim Rollen und bis die Karte danach da ist (höchstens 1,2 s).
func _ziele_frisch() -> bool:
	if _roll_v != Vector2.ZERO:
		return false
	var jetzt := Time.get_ticks_msec()
	return jetzt >= _roll_stopp_ms and (_karte_ms >= _roll_stopp_ms or jetzt - _roll_stopp_ms > 1200)


## Ein Bild Zeiger: ls linker Stick (roh), fein: LB/RB gehalten.
func _zeiger_lauf(ls: Vector2, fein: bool, dt: float) -> void:
	var t := _tab()
	var v := _vw(t)
	var bewegt: bool = _zg.schritt(ls, dt, t.ziele, v.x, v.y, { "tempo": Zeiger.tempo(_zeiger_tempo()), "fein": fein,
		"einrasten": _einrasten(), "ziele_frisch": _ziele_frisch() })
	_rahmen.zeiger(true, _zeiger_schirm(), _hover_schirm())
	if bewegt or _zeiger_gesendet != Vector2i(roundi(_zg.p.x), roundi(_zg.p.y)):
		_zeiger_senden()


## Steuerkreuz im Zeiger: zum nächsten Ziel im Bild gleiten, sonst rollt die Seite ein Stück.
func _zeiger_springen(dir: String) -> void:
	var t := _tab()
	var v := _vw(t)
	if not _ziele_frisch() or _zg.springen(dir, t.ziele, v.x, v.y) < 0:
		_anstossen(dir)
		return
	Sfx.play("move")


## A im Zeiger: das Ziel darunter (knapp daneben zählt). Ein Textfeld öffnet Uzais Tastatur, eine Auswahl
## Uzais Liste (wie mit dem Steuerkreuz); sonst ein echter Mausklick genau dort, auch in Rahmen.
func _zeiger_klick() -> void:
	var t := _tab()
	var v := _vw(t)
	var treffer := Zeiger.treffer(_zg.p, t.ziele if _ziele_frisch() else [])
	_rahmen.druck()
	if int(treffer.id) >= 0 and str(treffer.art) in ["feld", "wahl"]:
		wirt.senden("aktivieren", { "tab": aktiv, "id": int(treffer.id), "neu": false })
		return
	var q: Vector2 = treffer.punkt
	if not q.is_equal_approx(_zg.p):
		_zg.setzen(q)
		_rahmen.zeiger(true, _zeiger_schirm(), _hover_schirm())
	_zeiger_gesendet = Vector2i(clampi(roundi(q.x), 0, int(v.x)), clampi(roundi(q.y), 0, int(v.y)))
	wirt.senden("klick", { "tab": aktiv, "x": _zeiger_gesendet.x, "y": _zeiger_gesendet.y })


## Steht die Seite am Ende in Richtung dy (Karte)?
func _am_ende(dy: float) -> bool:
	var k: Dictionary = _tab().get("karte", {})
	if k.is_empty():
		return false
	var sy := int(k.get("sy", 0))
	return (dy < 0.0 and sy <= 0) or (dy > 0.0 and sy + int(k.get("vh", 0)) >= int(k.get("sh", 0)) - 1)


func _process(dt: float) -> void:
	# Auf der Seite zeigt der Browser seine Tasten selbst (nur bei Bedarf); über ihm (Menü, Tastatur,
	# Guide) gilt wieder Uzais Tastenzeile.
	if is_instance_valid(main) and main.hint_hud:
		var hud := not (modus == "seite" and Nav.top_layer() == self)
		if main.hint_hud.visible != hud:
			main.hint_hud.visible = hud
	if modus != "seite" or Nav.top_layer() != self:
		if _roll_v != Vector2.ZERO and is_instance_valid(wirt):
			_roll_v = Vector2.ZERO
			_roll_stopp_ms = Time.get_ticks_msec()
			wirt.senden("rollen", { "tab": aktiv, "vx": 0, "vy": 0 })
		return
	if _ui_bis > 0 and Time.get_ticks_msec() > _ui_bis:
		_ui_ausblenden()
	_vorschau_pruefen()
	var rs := Vector2.ZERO
	var ls := Vector2.ZERO
	var l3 := false
	var fein := false
	for id in Input.get_connected_joypads():
		var p := Vector2(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
		if p.length() > rs.length():
			rs = p
		var q := Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		if q.length() > ls.length():
			ls = q
		l3 = l3 or Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_STICK)
		fein = fein or Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
	if l3 and not _l3:
		_zeiger_umschalten()
	_l3 = l3
	if zeiger_an:
		_zeiger_lauf(ls, fein, dt)
	_rollen_lauf(rs, dt)


## Rechter Stick: dieselbe Kurve wie der Zeiger, in Bildhöhen je Sekunde; lange voll gehalten weich bis ROLL_SCHUB.
## Drückt der Zeiger gegen den oberen/unteren Rand, rollt die Seite mit. Über einem Rahmen (iframe) rollt
## ein echtes Mausrad an der Stelle des Zeigers (sein Inhalt gehört nicht dem Sprung-Skript).
func _rollen_lauf(rs: Vector2, dt: float) -> void:
	var k := Zeiger.kurve(rs, ROLL_TOT)
	_roll_voll = _roll_voll + dt if k.length() > 0.9 else 0.0
	var schub := 1.0 + (ROLL_SCHUB - 1.0) * smoothstep(0.5, 1.3, _roll_voll)
	var vh := _vw(_tab()).y
	var soll := k * ROLL_VH * vh * schub
	if zeiger_an:
		soll += _zg.rand
	soll = soll.round()
	var jetzt := Time.get_ticks_msec()
	if soll == Vector2.ZERO:
		_rand_ton = false
		_rad_rest = 0.0
	elif zeiger_an and not _zg.ueber.is_empty() and str(_zg.ueber.art) == "rahmen":
		if _roll_v != Vector2.ZERO:
			_roll_v = Vector2.ZERO
			wirt.senden("rollen", { "tab": aktiv, "vx": 0, "vy": 0 })
		_rad_rest += soll.y * dt
		if jetzt - _rad_ms >= 33 and absf(_rad_rest) >= 1.0:
			_rad_ms = jetzt
			var dy := clampi(int(_rad_rest), -5000, 5000)
			_rad_rest -= dy
			wirt.senden("rad", { "tab": aktiv, "x": _zeiger_gesendet.x, "y": _zeiger_gesendet.y, "dy": dy })
		return
	var wechsel := (soll == Vector2.ZERO) != (_roll_v == Vector2.ZERO)
	if wechsel and soll != Vector2.ZERO and soll.y != 0.0 and _am_ende(soll.y):
		_rand_ton = true
		Sfx.play("bump")
	var schwelle := maxf(40.0, soll.length() * 0.06)
	if wechsel or ((soll - _roll_v).length() > schwelle and jetzt - _roll_ms > 40):
		if soll == Vector2.ZERO:
			_roll_stopp_ms = jetzt
		_roll_v = soll
		_roll_ms = jetzt
		wirt.senden("rollen", { "tab": aktiv, "vx": int(soll.x), "vy": int(soll.y) })


## Link-Vorschau: ruht der Fokus VORSCHAU_MS auf einem Link zu einer anderen Seite, fragt Uzai die Adresse
## einmal ab (link) und zeigt nur den Namen der Seite unter dem Rahmen.
func _vorschau_pruefen() -> void:
	var t := _tab()
	if t.is_empty() or zeiger_an or video_an:
		return
	var id := int(t.get("fokus", -1))
	if _link_wunsch != "" and link_verfallen(_link_ms, Time.get_ticks_msec()):
		_link_wunsch = ""
	if id < 0 or id == _vorschau_id or Time.get_ticks_msec() - _sprung_ms < VORSCHAU_MS or _link_wunsch != "":
		return
	var z := K.finde(t.ziele, id)
	if z.is_empty() or str(z.art) != "link":
		return
	_vorschau_id = id
	_link_wunsch = "vorschau"
	_link_ms = Time.get_ticks_msec()
	wirt.senden("link", { "tab": aktiv, "id": id })


## Ist die offene Frage nach einer Link-Adresse verfallen (LINK_WARTE_MS ohne Antwort)?
static func link_verfallen(seit_ms: int, jetzt_ms: int) -> bool:
	return jetzt_ms - seit_ms >= LINK_WARTE_MS


func _gui_input(e: InputEvent) -> void:
	if modus != "seite" or aktiv == 0:
		return
	var t := _tab()
	var v := _vw(t)
	var k := Vector2(v.x / maxf(size.x, 1.0), v.y / maxf(size.y, 1.0))
	if e is InputEventMouseButton and e.pressed:
		var p: Vector2 = (e as InputEventMouseButton).position * k
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				wirt.senden("klick", { "tab": aktiv, "x": clampi(int(p.x), 0, int(v.x)), "y": clampi(int(p.y), 0, int(v.y)) })
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var dy := -120 if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else 120
				wirt.senden("rad", { "tab": aktiv, "x": clampi(int(p.x), 0, int(v.x)), "y": clampi(int(p.y), 0, int(v.y)), "dy": dy })
			MOUSE_BUTTON_XBUTTON1:
				_zurueck()
		accept_event()
	elif e is InputEventMouseMotion and Time.get_ticks_msec() - _maus_ms > 50:
		_maus_ms = Time.get_ticks_msec()
		var p2: Vector2 = (e as InputEventMouseMotion).position * k
		wirt.senden("zeiger", { "tab": aktiv, "x": clampi(int(p2.x), 0, int(v.x)), "y": clampi(int(p2.y), 0, int(v.y)) })


# --- Bauteile -----------------------------------------------------------------------------------

## Der unsichtbare Halt auf einer Seite: A, langes A, X, Y gehen hierher (Nav-Metas).
class SeitenFokus extends Control:
	signal gedrueckt

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2.ONE
		modulate.a = 0.0

	func activate() -> void:
		gedrueckt.emit()

	func activate_sound() -> String:
		return "select"


## Der große Fokusrahmen über der Seite: der Kachel-Cursor der Marke (heller Ring, weicher Schein),
## gleitet von Ziel zu Ziel (beim Rollen klebt er am Ziel), drückt beim Öffnen kurz ein. Dazu der
## Zeiger als Kern im Akzent (dunkler Saum für helle Seiten) und, solange er über einem Ziel steht, ein
## leiser Ring um dieses Ziel (gleitet mit, blendet weich); beim Klick drückt der Kern kurz ein.
class Rahmen extends Control:
	const UU := preload("res://src/ui/u.gd")

	var _ziel := Rect2()
	var _jetzt := Rect2()
	var _id := -1
	var _t := 0.0
	var _druck := 0.0
	var _zeiger_an := false
	var _zeiger := Vector2.ZERO
	var _hov_an := false
	var _hov_ziel := Rect2()
	var _hov_jetzt := Rect2()
	var _hov_t := 0.0
	var _hinweis := ""
	var _hinweis_t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Link-Vorschau: ein Wort (Name der Seite) leise unter dem Rahmen; "" nimmt es weg.
	func hinweis(text: String) -> void:
		if text != "":
			_hinweis = text
		elif _hinweis_t <= 0.01:
			_hinweis = ""
		var ziel := 1.0 if text != "" else 0.0
		if not is_equal_approx(_hinweis_t, ziel):
			UU.ankommen(self, UU.T_ORT, "uz_hinweis").tween_method(func(v: float) -> void:
				_hinweis_t = v
				queue_redraw(), _hinweis_t, ziel, UU.T_ORT if text != "" else UU.T_WEG)

	func setzen(r: Rect2, id: int) -> void:
		if id < 0:
			_id = -1
			queue_redraw()
			return
		var gleich := id == _id
		_ziel = r
		if gleich or _jetzt.size == Vector2.ZERO or UU.reduziert():
			_jetzt = r
		_id = id
		queue_redraw()

	func druck() -> void:
		_druck = 1.0

	## hover: Rechteck des Ziels unter dem Zeiger auf dem Schirm (leer: keins).
	func zeiger(an: bool, p: Vector2, hover := Rect2()) -> void:
		_zeiger_an = an
		_zeiger = p
		_hov_an = an and hover.size.x > 0.0
		if _hov_an:
			if _hov_t <= 0.01 or _hov_jetzt.size == Vector2.ZERO or UU.reduziert():
				_hov_jetzt = hover
			_hov_ziel = hover
		queue_redraw()

	func _process(dt: float) -> void:
		var soll := 1.0 if _id >= 0 else 0.0
		var alt_t := _t
		_t = move_toward(_t, soll, dt / 0.09)
		var k := 1.0 - exp(-dt * 24.0)
		var weiter := not _jetzt.is_equal_approx(_ziel)
		if weiter:
			_jetzt = Rect2(_jetzt.position.lerp(_ziel.position, k), _jetzt.size.lerp(_ziel.size, k))
		if _druck > 0.0:
			_druck = maxf(0.0, _druck - dt / 0.2)
		var alt_h := _hov_t
		_hov_t = move_toward(_hov_t, 1.0 if _hov_an else 0.0, dt / 0.08)
		var hov_weiter := _hov_t > 0.0 and not _hov_jetzt.is_equal_approx(_hov_ziel)
		if hov_weiter:
			_hov_jetzt = Rect2(_hov_jetzt.position.lerp(_hov_ziel.position, k), _hov_jetzt.size.lerp(_hov_ziel.size, k))
		if weiter or hov_weiter or _druck > 0.0 or alt_t != _t or alt_h != _hov_t:
			queue_redraw()

	func _draw() -> void:
		if _t > 0.01 and _jetzt.size.x > 0.0:
			var r := _jetzt.grow(-6.0 * sin(_druck * PI))
			var rad := int(minf(float(UzTheme.r_panel()), r.size.y * 0.5))
			# Webseiten sind oft hell: ein dunkler Hof außen um den hellen Ring der Marke, damit der Rahmen auf
			# jedem Grund aus 3 m zu sehen ist.
			var hof := StyleBoxFlat.new()
			hof.draw_center = false
			hof.anti_aliasing = true
			hof.set_border_width_all(5)
			hof.border_color = Color(0, 0, 0, 0.5 * _t)
			hof.set_corner_radius_all(rad + 11)
			hof.set_expand_margin_all(11)
			draw_style_box(hof, r)
			UzTheme.draw_tile_focus(self, r, rad, _t)
			if _hinweis != "" and _hinweis_t > 0.01:
				var f := UzTheme.display("medium")
				var fs := 20
				var w := f.get_string_size(_hinweis, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var p := Rect2(Vector2(r.position.x, r.end.y + 18.0), Vector2(w.x + 36.0, 40.0))
				if p.end.y > size.y - 8.0:
					p.position.y = r.position.y - 58.0
				p.position.x = clampf(p.position.x, 8.0, maxf(8.0, size.x - p.size.x - 8.0))
				var sb := UzTheme.flaeche(Color(UzTheme.col("surface"), 0.96 * _hinweis_t), UzTheme.r_pill(), 2)
				draw_style_box(sb, p)
				draw_string(f, p.position + Vector2(18.0, 27.0), _hinweis, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UzTheme.col("text"), _hinweis_t))
		if _zeiger_an:
			var akz := UzTheme.col("accent")
			if _hov_t > 0.01 and _hov_jetzt.size.x > 0.0:
				var hr := _hov_jetzt.grow(5.0)
				var hrad := int(minf(float(UzTheme.r_panel()), hr.size.y * 0.5))
				var hof := StyleBoxFlat.new()
				hof.draw_center = false
				hof.anti_aliasing = true
				hof.set_border_width_all(3)
				hof.border_color = Color(0, 0, 0, 0.4 * _hov_t)
				hof.set_corner_radius_all(hrad + 3)
				hof.set_expand_margin_all(3)
				draw_style_box(hof, hr)
				var ring := StyleBoxFlat.new()
				ring.bg_color = Color(akz, 0.1 * _hov_t)
				ring.anti_aliasing = true
				ring.set_border_width_all(3)
				ring.border_color = Color(1, 1, 1, 0.9 * _hov_t)
				ring.set_corner_radius_all(hrad)
				draw_style_box(ring, hr)
			var d := sin(_druck * PI)
			draw_circle(_zeiger, lerpf(22.0, 27.0, _hov_t), Color(akz, lerpf(0.16, 0.26, _hov_t)), true, -1.0, true)
			var r0 := 12.0 * (1.0 - 0.3 * d)
			draw_circle(_zeiger, r0 + 1.5, Color(0, 0, 0, 0.45), true, -1.0, true)
			draw_circle(_zeiger, r0, Color.WHITE, true, -1.0, true)
			draw_circle(_zeiger, r0 - 3.0, akz, true, -1.0, true)


## Link aufs Handy: QR-Code mit dem Namen der Seite.
class HandyLink extends "res://src/ui/layers/modal.gd":
	const Qr := preload("res://src/ui/components/qr_view.gd")

	var url := ""
	var titel := ""

	func fill() -> void:
		width = 900.0
		set_meta("uz_hint_b", "Schließen")
		var row := U.hbox(40)
		box.add_child(row)
		var frame := PanelContainer.new()
		var fsb := UzTheme.box(Color.WHITE, UzTheme.r_panel())
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			fsb.set_content_margin(side, 10)
		frame.add_theme_stylebox_override("panel", fsb)
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var qr = Qr.new()
		qr.setup(url, 280)
		frame.add_child(qr)
		row.add_child(frame)
		var col := U.vbox(12)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(U.label("Aufs Handy", "s", "accent", "medium"))
		var t := U.label(titel, "xl", "text", "bold", true)
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		col.add_child(t)
		var u := U.label(url.left(160), "s", "muted", "regular", true)
		u.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		col.add_child(u)
		var ok := U.button("Fertig", "", "primary")
		ok.pressed.connect(close)
		col.add_child(ok)


## Fernbedienung Plus: unten eine schmale Leiste im Material der Marke – Zeit und Dauer mit Balken,
## Lautstärke (stumm: durchgestrichen), Tempo und Untertitel nur, wenn sie nicht Standard sind.
class VideoLeiste extends Control:
	var _e := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func stand(e: Dictionary) -> void:
		_e = e
		queue_redraw()

	static func zeit(s: int) -> String:
		var h := int(s / 3600.0)
		var m := int(s / 60.0) % 60
		return "%d:%02d:%02d" % [h, m, s % 60] if s >= 3600 else "%d:%02d" % [m, s % 60]

	func _draw() -> void:
		if _e.is_empty() or not bool(_e.get("da", false)):
			return
		# Über der Tastenzeile (Pille unten rechts, 30 Rand), damit beide ganz zu sehen sind.
		var w := minf(size.x - 2.0 * 96.0, 1400.0)
		var r := Rect2(Vector2((size.x - w) * 0.5, size.y - 30.0 - 64.0 - 18.0 - 78.0), Vector2(w, 78.0))
		var sb := UzTheme.flaeche(UzTheme.col("surface"), UzTheme.r_panel(), 3)
		draw_style_box(sb, r)
		var f := UzTheme.display("medium")
		var fs := 20
		var dauer := int(_e.get("dauer", 0))
		var z := int(_e.get("zeit", 0))
		var links := zeit(z)
		var rechts: String = zeit(dauer) if dauer > 0 else str(TranslationServer.translate("Live"))
		var lw := f.get_string_size(links, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rw := f.get_string_size(rechts, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := r.position.y + 46.0
		draw_string(f, Vector2(r.position.x + 26.0, y), links, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
		# Rechts: Tempo, Untertitel, Lautstärke, Dauer.
		var x := r.end.x - 26.0 - rw
		draw_string(f, Vector2(x, y), rechts, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted"))
		x -= 30.0
		var laut := int(_e.get("laut", 100))
		var stumm := bool(_e.get("stumm", false))
		var ic: Texture2D = Icons.tex("volume", 24)
		if ic:
			x -= 24.0
			draw_texture_rect(ic, Rect2(Vector2(x, y - 19.0), Vector2(24, 24)), false, UzTheme.col("muted") if stumm else UzTheme.col("accent"))
			if stumm:
				draw_line(Vector2(x + 3, y - 16), Vector2(x + 21, y + 2), UzTheme.col("muted"), 2.0, true)
			else:
				var lt := "%d" % laut
				var ltw := f.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				x -= ltw + 6.0
				draw_string(f, Vector2(x, y), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UzTheme.col("muted"))
			x -= 26.0
		if int(_e.get("untertitel", -1)) == 1:
			var cc: Texture2D = Icons.tex("subtitles", 24)
			if cc:
				x -= 24.0
				draw_texture_rect(cc, Rect2(Vector2(x, y - 19.0), Vector2(24, 24)), false, UzTheme.col("accent"))
				x -= 22.0
		var tempo := int(_e.get("tempo", 100))
		if tempo != 100:
			var tt := "%s×" % String.num(tempo / 100.0, 2).trim_suffix("0").trim_suffix("0").trim_suffix(".")
			var ttw := f.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			x -= ttw
			draw_string(f, Vector2(x, y), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("accent"))
			x -= 22.0
		# Balken: Spur leise, Stand im Akzent, ein kleiner Kern am Ende.
		var bx0 := r.position.x + 26.0 + lw + 22.0
		var bx1 := x - 22.0
		if bx1 - bx0 < 80.0:
			return
		var by := y - 7.0
		draw_line(Vector2(bx0, by), Vector2(bx1, by), Color(UzTheme.col("text"), 0.16), 4.0, true)
		if dauer > 0:
			var k := clampf(float(z) / float(dauer), 0.0, 1.0)
			var bx := lerpf(bx0, bx1, k)
			draw_line(Vector2(bx0, by), Vector2(bx, by), UzTheme.col("accent"), 4.0, true)
			draw_circle(Vector2(bx, by), 7.0, UzTheme.col("accent"))
			draw_circle(Vector2(bx, by), 3.0, Color.WHITE)


## Aufgang: Die Startbühne (browser_view.gd) wächst in den Browser – ihre Fläche wird zum Schirm, ihre
## Marke fliegt zu der kleinen Marke im Kopf der Startseite. Kein harter Schnitt, kein helles Bild: Unter der
## Fläche liegt die ganze Zeit Uzais Hintergrund, die Startseite kommt unter der wachsenden Fläche hoch.
class Aufgang extends Control:
	signal fertig

	const Logo := preload("res://src/ui/components/uzai_logo.gd")
	const Buehne := preload("res://src/ui/sections/browser_view.gd").Buehne

	var von := Rect2()
	var marke_von := Vector2.ZERO
	var hoehe_von := 160.0
	var ziel: Callable               ## liefert das Rechteck (Schirm) der Marke im Kopf der Startseite (leer = noch nicht)
	var dauer := 0.46
	var _x := 0.0
	var _bilder := 0
	var _fertig := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(dt: float) -> void:
		_bilder += 1
		_x += minf(dt, 1.0 / 60.0 if _bilder <= 2 else 0.1) / dauer
		queue_redraw()
		if _x >= 1.0 and not _fertig:
			_fertig = true
			fertig.emit()
			queue_free()

	## Kurve: schnell los, ruhig am Ende (die Feder des Flugs, kritisch gedämpft, auf 1 gestreckt).
	static func kurve(x: float) -> float:
		x = clampf(x, 0.0, 1.0)
		var roh := 1.0 - exp(-7.0 * x) * (1.0 + 7.0 * x)
		return roh / (1.0 - exp(-7.0) * 8.0)

	func _draw() -> void:
		var p := kurve(_x)
		var inv := get_global_transform().affine_inverse()
		var schirm := Rect2(Vector2.ZERO, size)
		var a := Rect2(inv * von.position, von.size * inv.get_scale())
		var r := Rect2(a.position.lerp(schirm.position, p), a.size.lerp(schirm.size, p))
		var rad := lerpf(float(UzTheme.r_panel()) * 1.4, 0.0, p)
		# Die Fläche: erst die Bühne (surface_hi), dann der Grund der Startseite (bg); zum Ende hin gibt sie die
		# Startseite frei, die darunter schon eingeblendet ist.
		var deck := 1.0 - smoothstep(0.6, 1.0, p)
		var farbe: Color = UzTheme.col("surface_hi").lerp(UzTheme.col("bg"), smoothstep(0.2, 0.9, p))
		if deck > 0.003:
			var sb := UzTheme.flaeche(Color(farbe, deck), int(rad), 2)
			sb.shadow_size = int(30.0 * (1.0 - p))
			sb.shadow_color = Color(0, 0, 0, 0.35 * (1.0 - p))
			draw_style_box(sb, r)
		# Name und Zeile der Bühne stehen noch kurz, wo sie waren, und verblassen (kein Schnitt); der Hof aus
		# Akzentlicht hinter der Marke geht mit ihnen.
		var m0 := inv * marke_von
		var h0 := hoehe_von * inv.get_scale().y
		var akz := UzTheme.col("accent")
		var rest := 1.0 - smoothstep(0.0, 0.3, _x)
		if rest > 0.003:
			var k := h0 / 168.0
			var f := UzTheme.display()
			var name := "Uzai Browser"
			var fs := int(46.0 * k)
			var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, Vector2(m0.x - w.x * 0.5, m0.y + h0 * 0.5 + 76.0 * k), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UzTheme.col("text"), rest))
			var zeile := TranslationServer.translate("Werbung und Tracker geblockt")
			var f2 := UzTheme.display("medium")
			var fs2 := int(19.0 * k)
			var w2 := f2.get_string_size(zeile, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
			draw_string(f2, Vector2(m0.x - w2.x * 0.5, m0.y + h0 * 0.5 + 118.0 * k), zeile, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(UzTheme.col("muted"), rest))
		# Die Marke fliegt zum Kopf der Startseite (oder bleibt in der Mitte, bis der Platz da ist).
		var zr: Variant = ziel.call() if ziel.is_valid() else Rect2()
		var m1 := m0
		var h1 := h0
		if zr is Rect2 and (zr as Rect2).size.y > 1.0:
			var z := Rect2(inv * (zr as Rect2).position, (zr as Rect2).size * inv.get_scale())
			m1 = z.get_center()
			h1 = z.size.y
		var pm := kurve(minf(1.0, _x * 1.08))
		var mc := m0.lerp(m1, pm)
		var mh := lerpf(h0, h1, pm)
		# Der Hof fliegt mit der Marke und verblasst dabei (im Kopf der Startseite gibt es keinen).
		if rest > 0.003:
			Buehne.hof(self, mc, mh, akz, rest)
		Logo.draw_mark(self, mc, mh, Color(akz, 1.0 - smoothstep(0.92, 1.0, _x)), Logo.licht_von(akz))
