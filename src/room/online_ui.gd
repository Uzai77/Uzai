extends "res://src/ui/layers/sheet.gd"
## „Zimmer online“ (Punkt 131; docs/ZIMMER_SICHERHEIT.md): oben der Stand und der Schalter (Standard aus).
## Einschalten zeigt einmal den Hinweis zur IP-Adresse und prüft dann die Abschottung auf diesem PC; erst wenn
## sie besteht, gilt das Zimmer als eingeschaltet. Eingeschaltet: Freund einladen (Code), Einladung annehmen,
## wer anklopft und wer da ist (freundestest.gd). Darunter, was der Gastgeber einmal einstellt (wie viele Gäste,
## wie lange eine Einladung gilt; anklopfen kann nur, wen du eingeladen hast), die Sicherheits-Hinweise
## (IP-Adresse, Schutz, „Wenn es nicht klappt“: ohne Vermittlungsserver scheitert etwa jede fünfte Verbindung)
## und die Prüfung der Abschottung am Windows-PC (AppContainer, Leitung, beide Prüfmauern mit einer
## Test-Gegenstelle).
##
## Solange das Zimmer offline ist, steht darunter eine Vorschau mit Beispiel-Gästen zum Üben: Einladen,
## Anklopfen, Gästeliste, Sperrliste mit Hereinlassen, Ablehnen, Rauswerfen, Sperren. Die Vorschau verbindet
## sich mit niemandem und verschickt nichts.
##
## „Testbetrieb“ (Standard aus, Einstellung room.online_test): schaltet den Verbindungstest frei – zwei
## Abschottungen auf diesem PC verbinden sich über die echten Relays und WebRTC. Läuft nur ohne Adminrechte und
## nur, wenn die Abschottung samt beiden Netz-Bibliotheken gerade geprüft ist (Online.darf_testen).
##
## ansicht: "start" (diese Übersicht), "anklopfen", "gaeste", "gesperrt", "einladungen" (Listen der Vorschau).
## Erreichbar über das Zimmer-Menü (Menü-Taste → „Online“) und Einstellungen → System.

const Online := preload("res://src/room/online.gd")
const ZimmerNetz := preload("res://src/room/zimmer_netz.gd")
const Verbindungstest := preload("res://src/room/verbindungstest.gd")
const FT := preload("res://src/room/freundestest.gd")
const Einladung := preload("res://src/room/einladung.gd")
const EinladungUi := preload("res://src/room/einladung_ui.gd")

## Gründe, warum ein Einladungscode nicht passt (einladung.gd code_lesen).
const CODE_FEHLER := {
	"leer": "Kein Code.", "lang": "Das ist kein Einladungscode.", "zeichen": "Das ist kein Einladungscode.",
	"laenge": "Der Code hat 35 Zeichen (ohne UZAI und Striche).", "pruefsumme": "Tippfehler im Code – bitte vergleichen.",
	"abgelaufen": "Die Einladung ist abgelaufen. Bitte um eine neue.", "zeit": "Die Uhrzeit passt nicht – Uhr am PC prüfen.",
}

const GUELTIG := [[15, "15 Minuten"], [60, "1 Stunde"], [1440, "1 Tag"]]

## Die Vorschau bleibt, solange Uzai läuft (Hereinlassen und Sperren wirken über die Listen hinweg).
static var _vorschau: Online

const Main := preload("res://src/main.gd")
var main: Main
var ansicht := "start"
var _ft_uhr: Timer
var _ft_zeile: Control


func build() -> void:
	help_on = ansicht == "start"
	match ansicht:
		"anklopfen": setup("Anklopfen", "Beispiel – keine echte Verbindung", 820)
		"gaeste": setup("Gäste im Zimmer", "Beispiel – keine echte Verbindung", 820)
		"gesperrt": setup("Gesperrt", "Beispiel – keine echte Verbindung", 820)
		"einladungen": setup("Einladungen", "Beispiel – keine echte Verbindung", 820)
		_: setup("Zimmer online", "Freunde live in deinem Zimmer", 860)
	super()


static func vorschau() -> Online:
	if _vorschau == null:
		_vorschau = Online.new()
		_vorschau.beispiel(int(Time.get_unix_time_from_system()))
	_vorschau.einstellen(int(Config.get_value("room.online_max", 4)))
	return _vorschau


func fill() -> void:
	match ansicht:
		"anklopfen": _liste(vorschau().wartend, "Niemand klopft gerade an.")
		"gaeste": _liste(vorschau().gaeste, "Gerade ist niemand zu Besuch.")
		"gesperrt": _gesperrt()
		"einladungen": _einladungen()
		_: _start()


# --- Übersicht ------------------------------------------------------------------------------------

func _row(kind: String, t: String, desc: String, icon: String, v: Variant = null) -> Control:
	var r = SettingRow.new()
	r.setup(kind, t, desc, v)
	r.icon_name = icon
	r.set_meta("uz_key", "zonline:" + t)
	r.focused_row.connect(func() -> void: set_help(tr(desc)))
	return add_row(r)


func _start() -> void:
	add_row(_status_karte())
	add_gap(10)
	var an := _normal()
	var st = _row("toggle", "Zimmer online", "Freunde besuchen dein Zimmer – nur wer eingeladen ist und wen du hereinlässt.", "friends", an)
	st.subtitle = "Du entscheidest bei jedem Anklopfen" if an else "Niemand kann dein Zimmer sehen oder betreten"
	st.changed.connect(_online_schalten)
	if an:
		_freundestest_zeilen()
	add_gap()
	add_label("Einstellungen")
	var mx = _row("choice", "Höchstens Gäste",
			"Gäste gleichzeitig.", "user",
			int(Config.get_value("room.online_max", 4)))
	var zahlen: Array = []
	for i in range(1, Online.MAX_GAESTE_GRENZE + 1):
		zahlen.append([i, str(i)])
	mx.options = zahlen
	mx.changed.connect(func(v: Variant) -> void: Config.set_value("room.online_max", int(v)))
	var gl = _row("choice", "Einladung gilt", "Eine Einladung je Freund, einmal gültig.", "clock",
			int(Config.get_value("room.online_gueltig", 60)))
	gl.options = GUELTIG
	gl.changed.connect(func(v: Variant) -> void: Config.set_value("room.online_gueltig", int(v)))
	add_gap()
	add_label("Sicherheit")
	var ip = _row("action", "Hinweis zur IP-Adresse", "Gäste sehen deine IP-Adresse.", "eye")
	ip.on_activate = _ip_hinweis
	var nk = _row("action", "Wenn es nicht klappt", "Etwa jede fünfte Verbindung scheitert.", "info")
	nk.on_activate = _ausweg
	var sch = _row("action", "Schutz",
			"Keine offenen Ports, nur Eingeladene.", "lock")
	sch.on_activate = _schutz
	var pr = _row("action", "Abschottung prüfen", "Prüft die Abschottung des Netzwerk-Teils.", "check")
	pr.value_text = "Prüfen" if (OS.get_name() == "Windows") else "Nur unter Windows"
	pr.on_activate = _abschottung
	var test_an := bool(Config.get_value("room.online_test", false))
	var tb = _row("toggle", "Testbetrieb", "Echte Relays und Direktverbindung, nur zum Testen.", "warning", test_an)
	tb.changed.connect(func(v: Variant) -> void:
		Config.set_value("room.online_test", bool(v))
		refill())
	if test_an:
		var vt = _row("action", "Verbindungstest", "Zwei Abschottungen auf diesem PC, echte Relays.", "friends")
		vt.value_text = "Starten" if (OS.get_name() == "Windows") else "Nur unter Windows"
		vt.on_activate = _verbindungstest
		if not an:
			_freundestest_zeilen()
	if an:
		return          # die Übung mit Beispiel-Gästen gibt es nur, solange das Zimmer offline ist
	add_gap()
	add_label("Vorschau mit Beispiel-Gästen")
	var o := vorschau()
	o.aufraeumen(int(Time.get_unix_time_from_system()))
	var ei = _row("action", "Freund einladen", "Eine Einladung je Freund, über Steam-Chat oder Discord.", "user")
	ei.value_text = "Vorschau"
	ei.on_activate = _einladen
	var eo = _row("action", "Einladungen", "Offene Einladungen zurückziehen.", "clock")
	eo.value_text = tr("%d offen") % o.einladungen.filter(func(e: Dictionary) -> bool: return not bool(e.benutzt)).size()
	eo.on_activate = func() -> void: _liste_oeffnen("einladungen")
	var kl = _row("action", "Anklopfen",
			"Vorschau: Hereinlassen, Ablehnen oder Sperren.",
			"bell")
	kl.value_text = tr("%d warten") % o.wartend.size() if not o.wartend.is_empty() else tr("Niemand")
	kl.on_activate = func() -> void: _liste_oeffnen("anklopfen")
	var gs = _row("action", "Gäste im Zimmer", "Rauswerfen oder Sperren.", "friends")
	gs.value_text = tr("%d von %d") % [o.gaeste.size(), o.max_gaeste]
	gs.on_activate = func() -> void: _liste_oeffnen("gaeste")
	var gp = _row("action", "Gesperrt", "", "close")
	gp.value_text = str(o.gesperrt.size())
	gp.on_activate = func() -> void: _liste_oeffnen("gesperrt")
	if o.wartend.is_empty() and o.gaeste.is_empty() and o.einladungen.is_empty():
		var neu = _row("action", "Beispiel-Gäste zurückholen", "Füllt die Vorschau wieder mit Beispiel-Gästen.", "refresh")
		neu.on_activate = func() -> void:
			vorschau().beispiel(int(Time.get_unix_time_from_system()))
			Sfx.play("toggle_on")
			refill()
	else:
		var off = _row("action", "Zimmer offline",
				"Alle Gäste raus, alle Einladungen ungültig.", "power")
		off.value_text = "Alle raus"
		off.on_activate = func() -> void:
			vorschau().offline()
			Sfx.play("toggle_off")
			Toasts.show_toast("Zimmer offline", "Beispiel – keine echte Verbindung", "power")
			refill()


## Ruhige Karte oben: großes Schloss, „Noch aus“ und ein Satz, warum.
func _status_karte() -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_panel())
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(22)
	p.add_child(h)
	var ic := U.icon("lock", 40, "accent")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var col := U.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _normal():
		col.add_child(U.label("Zimmer online ist an", "l", "text", "bold", true))
		col.add_child(U.label("Nur von Uzai zu Uzai. Hinein kommt nur, wen du einlädst und hereinlässt.", "s", "muted", "regular", true))
	else:
		col.add_child(U.label("Dein Zimmer ist offline", "l", "text", "bold", true))
		col.add_child(U.label("Standard ist aus. Einschalten prüft zuerst die Abschottung auf diesem PC.", "s", "muted", "regular", true))
	h.add_child(col)
	return p


func _liste_oeffnen(art: String) -> void:
	var l = get_script().new()
	l.ansicht = art
	l.closed.connect(func() -> void:
		if is_inside_tree() and not _closing:
			refill())
	main.open_layer(l)


# --- Ein- und Ausschalten --------------------------------------------------------------------------

## Zimmer online als normale Funktion eingeschaltet (Einstellung und Hinweis; die Abschottung prüft
## _freund_pruefen vor jedem Start)?
func _normal() -> bool:
	return Online.BEREIT and bool(Config.get_value("room.online", false)) and bool(Config.get_value("room.online_hinweis", false))


## Für Titel und Meldungen: läuft gerade der Testbetrieb statt der normalen Funktion?
func _nur_test() -> bool:
	return not _normal()


## Einschalten: erst der ehrliche Hinweis zur IP-Adresse (einmal), dann prüft Uzai die Abschottung selbst.
## Besteht sie nicht (oder läuft Uzai mit Adminrechten), bleibt das Zimmer offline und sagt, warum.
## Ausschalten: sofort – alle raus, alle Einladungen ungültig.
func _online_schalten(v: Variant) -> void:
	if not bool(v):
		Config.set_value("room.online", false)
		if FT.laeuft():
			FT.aktiv.beenden("offline" if str(FT.aktiv.rolle) == "gastgeber" else "verlassen")
		Sfx.play("toggle_off")
		Toasts.show_toast("Zimmer offline", "Niemand kann es sehen oder betreten", "power")
		refill()
		return
	var weiter := func() -> void:
		Config.set_value("room.online_hinweis", true)
		# Erst die Prüfung, dann gilt es als an: Wird diese Seite geschlossen, während sie läuft, bleibt das
		# Zimmer offline (vorher stand der Schalter dann auf „an“, ohne dass die Abschottung bestanden hatte).
		var ok := await _freund_pruefen(true)
		if not is_inside_tree():
			return
		if ok:
			Config.set_value("room.online", true)
			Sfx.play("toggle_on")
			Toasts.show_toast("Zimmer online ist an", "Lade einen Freund ein", "friends")
		refill()
	if bool(Config.get_value("room.online_hinweis", false)):
		weiter.call()
		return
	main.open_dialog("Zimmer online", "Wen du hereinlässt, sieht deine IP-Adresse. Daraus lassen sich Stadt und Anbieter ablesen.\n\nLade nur Leute ein, denen du vertraust. Du entscheidest bei jedem Anklopfen.",
			[["Verstanden", weiter], ["Abbrechen", func() -> void: refill()]], "eye")


# --- Hinweise --------------------------------------------------------------------------------------

func _ip_hinweis() -> void:
	main.open_dialog("Hinweis zur IP-Adresse", "Gäste, die du hereinlässt, sehen deine IP-Adresse. Daraus lassen sich Stadt und Anbieter ablesen.\n\nNur Bekannte hereinlassen.", [["Verstanden", func() -> void: pass]], "eye")


func _schutz() -> void:
	main.open_dialog("Schutz", "Keine offenen Ports. Nur Eingeladene. Ende-zu-Ende verschlüsselt.\nTreffpunkt über öffentliche Relays – die sehen nur versiegelte Daten.\nGäste senden nur Position, Emotes und feste Sätze.\nNetzwerk-Teil abgeschottet, ohne Adminrechte.", [["Gut", func() -> void: pass]], "lock")


func _ausweg() -> void:
	main.open_dialog("Wenn es nicht klappt", "Ohne Vermittlungsserver kommt etwa jede fünfte Verbindung nicht zustande, z. B. bei DS-Lite oder im Mobilfunk.\n\nDann mitspielen über Remote Play Together: im Spiel über den Guide einladen. Gäste ohne Steam bekommen im Steam-Overlay einen Link (kostenlose Steam-Link-App).\nZuschauen geht über die Discord-Übertragung.", [["OK", func() -> void: pass]], "info")


## Vorschau: eine Einladung für einen Freund anlegen (verschickt wird nichts).
func _einladen() -> void:
	var namen: Array = []
	for f in Social.steam_friends.slice(0, 40):
		namen.append([str(f.get("name", "")), str(f.get("name", ""))])
	if namen.is_empty():
		for n in ["Mila", "Jonas", "Sophie"]:
			namen.append([n, n])
	var gewaehlt := func(w: Variant) -> void:
		var e := vorschau().einladen(int(Time.get_unix_time_from_system()), int(Config.get_value("room.online_gueltig", 60)), str(w), "steam")
		Sfx.play("toggle_on")
		Toasts.show_toast(tr("Einladung für %s") % str(e.get("fuer", "")), "Beispiel – verschickt wird nichts", "user")
		refill()
	main.open_choice("Freund einladen", namen, "", gewaehlt, "Beispiel – keine echte Verbindung")


func _abschottung() -> void:
	if not (OS.get_name() == "Windows") or not Helper.available:
		main.open_dialog("Nur unter Windows", "Nur unter Windows 10 oder 11.",
				[["OK", func() -> void: pass]], "info")
		return
	Toasts.show_toast("Abschottung wird geprüft", "Dauert ein paar Sekunden", "lock")
	ZimmerNetz.netzlibs_auslegen()
	var r := probe_antwort(await Helper.run("zimmer-netz-probe", {}, 30.0))
	if not is_inside_tree():
		return
	# Danach die Leitung mit beiden Prüfmauern: dieselbe Sandbox, eine Test-Gegenstelle schickt gute
	# und böse Nachrichten (kein Netz).
	var g := {}
	if bool(r.get("ok", false)):
		g = await ZimmerNetz.pruefen(ZimmerNetz.windows_starten("gastgeber"), get_tree(), 60.0)
		if not is_inside_tree():
			return
	var ok := bool(r.get("ok", false)) and bool(g.get("ok", false))
	FT.abschottung_merken(r, g)
	main.open_dialog("Abschottung in Ordnung" if ok else "Abschottung nicht in Ordnung", abschottung_text(r, g), [["OK", func() -> void: pass]],
			"check" if ok else "warning", "" if ok else "warn")


## Helper.run liefert { ok, result, error }: das Ergebnis der Probe steckt in result. Früher wurde die
## Hülle selbst gelesen – dann stand überall „nein“ ohne Grund. Scheitert der Aufruf, steht der Grund da.
static func probe_antwort(antwort: Dictionary) -> Dictionary:
	if bool(antwort.get("ok", false)) and antwort.get("result") is Dictionary:
		return antwort.result
	var grund := str(antwort.get("error", "")).strip_edges()
	return { "ok": false, "fehler": grund if grund != "" else "helfer" }


## Antwort des Helfers und der Test-Gegenstelle als kurze Liste (eine Zeile je Mauer). Unbekanntes
## zählt als „nein“.
func abschottung_text(r: Dictionary, g: Dictionary = {}) -> String:
	var zeilen: Array = []
	for p in [["container", "Eigener Container ohne Rechte"], ["echo", "Leitung zu Uzai (Echo)"], ["eigener_ordner", "Nur der eigene leere Ordner beschreibbar"],
			["uzai_daten_gesperrt", "Uzais Dateien gesperrt"], ["profil_gesperrt", "Deine Dateien gesperrt"], ["temp_gesperrt", "Temp-Ordner gesperrt"],
			["programme_gesperrt", "Keine Programme starten"], ["krypto", "Verschlüsselung in der Abschottung"]]:
		zeilen.append("%s: %s" % [tr(p[1]), tr("ja") if r.get(p[0]) == true else tr("nein")])
	for p in [["rahmen", "Leitung ohne Verlust"], ["mauer1", "Prüfmauer in der Abschottung"], ["mauer2", "Prüfmauer in Uzai"], ["drossel", "Flut gebremst, Unsinn fliegt raus"],
			["ausgang", "Hinaus nur feste Nachrichten"]]:
		var ja: bool = g.get(p[0]) == true and (p[0] != "drossel" or g.get("rauswurf") == true)
		zeilen.append("%s: %s" % [tr(p[1]), tr("ja") if ja else tr("nein")])
	# Netz-Bibliotheken in der Abschottung: „ja“ = geladen, Prüfsumme und Selbsttest in Ordnung.
	for p in [["secp", "Signatur (libsecp256k1)"], ["rtc", "Datenkanal (libdatachannel)"]]:
		var z := int(r.get(p[0], 0)) if (r.get(p[0]) is int or r.get(p[0]) is float) else 0
		zeilen.append("%s: %s" % [tr(p[1]), tr(ZimmerNetz.NETZLIB_ZUSTAENDE[z]) if z >= 1 and z < ZimmerNetz.NETZLIB_ZUSTAENDE.size() else tr("nein")])
	var f := str(r.get("fehler", ""))
	if f == "admin":
		zeilen.append(tr("Nicht mit Adminrechten."))
	elif f != "":
		zeilen.append(tr("Grund: %s") % f.substr(0, 40))
	# Leitung (Rahmen verloren, zu) oder Prüfmauer (falsches Urteil) – getrennt, damit klar ist, wo es hakt.
	var fg := str(g.get("fehler", ""))
	if f == "" and fg.begins_with("leitung "):
		zeilen.append(tr("Leitung: %s") % fg.trim_prefix("leitung ").substr(0, 40))
	elif f == "" and fg != "":
		zeilen.append(tr("Prüfmauer: %s") % fg.trim_prefix("pruefung ").substr(0, 40))
	return "\n".join(zeilen)


## Testbetrieb: erst die Abschottung (mit beiden Bibliotheken), dann zwei Abschottungen über echte Relays.
func _verbindungstest() -> void:
	if not (OS.get_name() == "Windows") or not Helper.available:
		main.open_dialog("Nur unter Windows", "Nur unter Windows 10 oder 11.", [["OK", func() -> void: pass]], "info")
		return
	Toasts.show_toast("Verbindungstest läuft", "Dauert bis zu zwei Minuten", "friends")
	ZimmerNetz.netzlibs_auslegen()
	var r := probe_antwort(await Helper.run("zimmer-netz-probe", {}, 30.0))
	if not is_inside_tree():
		return
	var g := {}
	if bool(r.get("ok", false)):
		g = await ZimmerNetz.pruefen(ZimmerNetz.windows_starten("gastgeber"), get_tree(), 60.0)
		if not is_inside_tree():
			return
	var ab_ok := FT.abschottung_merken(r, g)
	if not Online.darf_testen(bool(Config.get_value("room.online_test", false)), str(r.get("fehler", "")) == "admin", ab_ok):
		main.open_dialog("Verbindungstest nicht möglich", abschottung_text(r, g), [["OK", func() -> void: pass]], "warning", "warn")
		return
	var v: Dictionary = await Verbindungstest.laufen(get_tree(), 120.0)
	if not is_inside_tree():
		return
	main.open_dialog("Verbindung in Ordnung" if bool(v.ok) else "Verbindung nicht in Ordnung", verbindung_text(v), [["OK", func() -> void: pass]],
			"check" if bool(v.ok) else "warning", "" if bool(v.ok) else "warn")


func verbindung_text(v: Dictionary) -> String:
	var zeilen: Array = [tr("Relays: %d von %d") % [int(v.get("relays", 0)), int(v.get("gesamt", 0))]]
	for p in [["klopft", "Anklopfen über die Relays"], ["verbunden", "Direktverbindung"], ["hin", "Nachricht zum Gast"], ["zurueck", "Nachricht zurück"]]:
		zeilen.append("%s: %s" % [tr(p[1]), tr("ja") if v.get(p[0]) == true else tr("nein")])
	var f := str(v.get("fehler", ""))
	if f == "direkt":
		zeilen.append(tr("Ohne Vermittlungsserver klappt das nicht überall."))
	elif f != "":
		zeilen.append(tr("Grund: %s") % f.substr(0, 40))
	return "\n".join(zeilen)


# --- Listen der Vorschau -------------------------------------------------------------------------

func _liste(eintraege: Array, leer: String) -> void:
	if eintraege.is_empty():
		add_label(leer, "m", "muted")
		return
	var jetzt := int(Time.get_unix_time_from_system())
	for e in eintraege:
		var id := str(e.id)
		var quelle := tr("über Discord") if str(e.quelle) == "discord" else tr("über Steam")
		var seit := maxi(1, (jetzt - int(e.seit)) / 60)
		var sub := (tr("Klopft an · %s · seit %d Min.") if ansicht == "anklopfen" else tr("Im Zimmer · %s · seit %d Min.")) % [quelle, seit]
		var li = ListItem.new()
		li.setup(str(e.name), sub)
		li.avatar = true
		# Namen wählt jeder selbst: nie übersetzen; der Untertitel ist schon übersetzt.
		li.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		li.set_meta("uz_hint_a", "Entscheiden" if ansicht == "anklopfen" else "Optionen")
		li.activated.connect(func() -> void: _waehlen(id, str(e.name)))
		add_row(li)


func _gesperrt() -> void:
	var o := vorschau()
	if o.gesperrt.is_empty():
		add_label("Niemand ist gesperrt.", "m", "muted")
		return
	for id in o.gesperrt.keys():
		var name_ := str(o.gesperrt[id])
		var li = ListItem.new()
		li.setup(name_, tr("Gesperrt · Kennung %s") % str(id).substr(0, 8))
		li.avatar = true
		li.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		li.set_meta("uz_hint_a", "Entsperren")
		li.activated.connect(func() -> void:
			o.entsperren(str(id))
			Sfx.play("toggle_off")
			Toasts.show_toast(tr("%s entsperrt") % name_, "Beispiel – keine echte Verbindung", "check")
			refill())
		add_row(li)


func _einladungen() -> void:
	var o := vorschau()
	var jetzt := int(Time.get_unix_time_from_system())
	o.aufraeumen(jetzt)
	if o.einladungen.is_empty():
		add_label("Keine offenen Einladungen.", "m", "muted")
		return
	for e in o.einladungen:
		var quelle := tr("über Discord") if str(e.quelle) == "discord" else tr("über Steam")
		var li = ListItem.new()
		li.setup(str(e.fuer), tr("%s · noch %d Min. · nur einmal") % [quelle, maxi(1, (int(e.bis) - jetzt) / 60)])
		li.avatar = true
		li.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		li.set_meta("uz_hint_a", "Zurückziehen")
		var k: PackedByteArray = e.kennung
		var name_ := str(e.fuer)
		li.activated.connect(func() -> void:
			o.zurueckziehen(k)
			Sfx.play("toggle_off")
			Toasts.show_toast(tr("Einladung für %s zurückgezogen") % name_, "Beispiel – keine echte Verbindung", "close")
			refill())
		add_row(li)


func _waehlen(id: String, name_: String) -> void:
	var opts: Array = [["rein", tr("Hereinlassen")], ["nein", tr("Ablehnen")], ["sperren", tr("Sperren")]] if ansicht == "anklopfen" else [
			["raus", tr("Rauswerfen")], ["sperren", tr("Sperren")]]
	main.open_choice(name_, opts, "", func(w: Variant) -> void: anwenden(id, name_, str(w)), "Beispiel – keine echte Verbindung")


## Eine Entscheidung auf die Vorschau anwenden (auch für Tests und die Probe).
func anwenden(id: String, name_: String, was: String) -> void:
	var o := vorschau()
	var text := ""
	match was:
		"rein":
			var r: String = o.annehmen(id, int(Time.get_unix_time_from_system()))
			text = tr("%s ist im Zimmer") % name_ if r == "ok" else (tr("Das Zimmer ist voll") if r == "voll" else tr("Die Einladung ist abgelaufen"))
		"nein":
			o.ablehnen(id)
			text = tr("%s abgelehnt") % name_
		"raus":
			o.rauswerfen(id)
			text = tr("%s muss gehen") % name_
		"sperren":
			o.sperren(id)
			text = tr("%s gesperrt") % name_
	Sfx.play("toggle_on" if was == "rein" else "toggle_off")
	Toasts.show_toast(text, "Beispiel – keine echte Verbindung", "friends")
	refill()


# --- Freundestest (Testbetrieb: echter Besuch mit einem Freund, freundestest.gd) -------------------------------

func _freundestest_zeilen() -> void:
	var ft: Node = FT.aktiv if FT.aktiv != null and is_instance_valid(FT.aktiv) else null
	if ft != null and not ft.geaendert.is_connected(_ft_geaendert):
		ft.geaendert.connect(_ft_geaendert)
	if FT.laeuft() and str(ft.rolle) == "gastgeber":
		var st = _row("info", "Freundestest" if _nur_test() else "Besuch", "Dein Zimmer ist für deinen Freund offen.", "friends")
		st.value_text = str(ft.stand_text())
		st.value_raw = true           # schon in der Sprache der Oberfläche
		_ft_zeile = st
		var ei = _row("action", "Einladung", "Code anzeigen, kopieren oder zurückziehen.", "link")
		ei.on_activate = func() -> void: _einladung_zeigen() if int(ft.einladung_rest()) > 0 else _freund_einladen()
		ei.value_text = _rest_text(int(ft.einladung_rest())) if int(ft.einladung_rest()) > 0 else tr("Neue Einladung")
		ei.value_raw = true
		ei.set_meta("uz_rest", true)
		for a in ft.anklopfer:
			var id := str(a.id)
			var name_ := str(a.name)
			# Name im Titel: Die Zeile ist ausgenommen, ihr fester Text darum von Hand übersetzt.
			var kl = _row("action", tr("%s möchte rein") % name_, tr("Hereinlassen, Ablehnen oder Sperren."), "bell")
			kl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			kl.on_activate = func() -> void: ft._klopf_dialog(id, name_)
		for platz in ft.gaeste:
			var g: Dictionary = ft.gaeste[platz]
			var pl := int(platz)
			var gr = _row("action", str(g.name), tr("Rauswerfen oder Sperren."), "user")
			gr.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			gr.value_raw = true
			gr.value_text = tr("Im Zimmer") if bool(g.hallo) else tr("Verbinde …")
			gr.on_activate = func() -> void:
				main.open_choice(str(g.name), [["raus", tr("Rauswerfen")], ["sperren", tr("Sperren")]], "", func(w: Variant) -> void:
					ft.rauswerfen(pl, str(w) == "sperren")
					Sfx.play("toggle_off")
					Toasts.show_toast(tr("%s muss gehen") % str(g.name), "", "friends")
					refill(), "Rauswerfen oder sperren")
		var off = _row("action", "Alle raus", "Alle Gäste raus, Einladung ungültig.", "power")
		off.value_text = "Test beenden" if _nur_test() else "Jetzt"
		off.on_activate = func() -> void:
			ft.beenden("offline")
			Sfx.play("toggle_off")
			Toasts.show_toast("Zimmer offline", "Alle raus, Einladung ungültig", "power")
			refill()
	elif FT.laeuft():
		var st = _row("info", "Besuch", "Du bist im Zimmer deines Freundes.", "friends")
		st.value_text = str(ft.stand_text())
		st.value_raw = true
		_ft_zeile = st
		if str(ft.zustand) == "verbunden":
			var zi = _row("action", "Ins Zimmer", "Zum Zimmer deines Freundes.", "home")
			zi.on_activate = _ins_zimmer
		var weg = _row("action", "Besuch verlassen", "Verbindung beenden.", "power")
		weg.on_activate = func() -> void:
			ft.beenden("verlassen")
			Sfx.play("toggle_off")
			refill()
	else:
		var ei = _row("action", "Freund einladen (Test)" if _nur_test() else "Freund einladen", "Einladung als Code – an einen Freund schicken oder zeigen.", "user")
		ei.value_text = "Einladen" if (OS.get_name() == "Windows") else "Nur unter Windows"
		ei.on_activate = _freund_einladen
		var an = _row("action", "Einladung annehmen", "Code eingeben oder einfügen.", "link")
		an.value_text = "Code" if (OS.get_name() == "Windows") else "Nur unter Windows"
		an.on_activate = _einladung_annehmen
		if ft != null and str(ft.zustand) == "ende" and not (str(ft.grund) in ["verlassen", "offline"]):
			var lz = _row("info", "Letzter Versuch", "Protokoll: logs/zimmer_online.log", "warning")
			lz.value_text = str(ft.stand_text()).substr(0, 60)
			lz.value_raw = true
	if _ft_uhr == null:
		_ft_uhr = Timer.new()
		_ft_uhr.wait_time = 1.0
		_ft_uhr.timeout.connect(_ft_takt)
		add_child(_ft_uhr)
		_ft_uhr.start()


func _ft_geaendert() -> void:
	if is_inside_tree() and not _closing and Nav.top_layer() == self:
		refill()


## Jede Sekunde: Stand und Restzeit nachführen (ohne die Liste neu zu bauen).
func _ft_takt() -> void:
	if not FT.laeuft() or not is_instance_valid(_ft_zeile):
		return
	_ft_zeile.set("value_text", str(FT.aktiv.stand_text()))


static func _rest_text(s: int) -> String:
	return TranslationServer.translate("noch %d:%02d") % [s / 60, s % 60]


## Erst die Abschottung (einmal je Sitzung, mit beiden Bibliotheken, ohne Adminrechte), sonst kein Besuch –
## weder im Testbetrieb noch als normale Funktion. Uzai prüft selbst; niemand muss vorher etwas anstoßen.
## einschalten: die Prüfung vor dem Einschalten von „Zimmer online“ (der Schalter steht dann noch auf aus).
func _freund_pruefen(einschalten := false) -> bool:
	if not (OS.get_name() == "Windows") or not Helper.available:
		main.open_dialog("Nur unter Windows", "Nur unter Windows 10 oder 11.", [["OK", func() -> void: pass]], "info")
		return false
	if not einschalten and not bool(Config.get_value("room.online_test", false)) and not _normal():
		return false
	if FT.abschottung_ok:
		return true
	Toasts.show_toast("Abschottung wird geprüft", "Dauert ein paar Sekunden", "lock")
	ZimmerNetz.netzlibs_auslegen()
	var r := probe_antwort(await Helper.run("zimmer-netz-probe", {}, 30.0))
	if not is_inside_tree():
		return false
	var g := {}
	if bool(r.get("ok", false)):
		g = await ZimmerNetz.pruefen(ZimmerNetz.windows_starten("gastgeber"), get_tree(), 60.0)
		if not is_inside_tree():
			return false
	if not FT.abschottung_merken(r, g):
		main.open_dialog("Freundestest nicht möglich" if _nur_test() and not einschalten else "Zimmer online geht auf diesem PC nicht", abschottung_text(r, g),
				[["OK", func() -> void: pass]], "warning", "warn")
		return false
	return true


## Gastgeber: ehrlicher Hinweis, Name wählen, Abschottung starten, Einladung zeigen.
func _freund_einladen() -> void:
	if not await _freund_pruefen() or not is_inside_tree():
		return
	var minuten := int(Config.get_value("room.online_gueltig", 60))
	var dauer := "1 Stunde"
	for o in GUELTIG:
		if int(o[0]) == minuten:
			dauer = str(o[1])
	var weiter := func() -> void:
		var namen: Array = []
		for f in Social.steam_friends.slice(0, 30):
			var n := Online.anzeige_name(f.get("name", ""))
			namen.append([n, n])
		namen.append(["Freund", tr("Ohne Namen (Freund)")])
		namen.append(["@tippen", tr("Name eingeben")])
		main.open_choice("Für wen?", namen, "", func(w: Variant) -> void:
			if str(w) == "@tippen":
				main.open_keyboard("Name deines Freundes", "", func(t: String) -> void: _einladung_anlegen(t))
			else:
				_einladung_anlegen(str(w)), "Nur du siehst den Namen.")
	main.open_dialog("Freund einladen (Test)" if _nur_test() else "Freund einladen", tr("Dein Freund sieht deine IP-Adresse – daraus lassen sich Stadt und Anbieter ablesen.\nSchick den Code nur an Leute, denen du vertraust.\nEr gilt einmal und %s; du kannst ihn zurückziehen.") % tr(dauer),
			[["Weiter", weiter], ["Abbrechen", func() -> void: pass]], "eye")


func _einladung_anlegen(fuer: String) -> void:
	var ft: Node = FT.aktiv
	if not FT.laeuft() or str(ft.rolle) != "gastgeber":
		ft = FT.gastgeber_starten(get_tree())
	if str(ft.zustand) == "ende":
		main.open_dialog("Freundestest nicht möglich" if _nur_test() else "Einladen geht gerade nicht", str(ft.stand_text()), [["OK", func() -> void: pass]], "warning", "warn")
		return
	if not ft.bereit():
		Toasts.show_toast("Verbinde mit den Relays …", "Dauert ein paar Sekunden", "friends")
		var t0 := Time.get_ticks_msec()
		while is_instance_valid(ft) and not ft.bereit() and str(ft.zustand) != "ende" and Time.get_ticks_msec() - t0 < int(FT.RELAYS_FRIST * 1000.0):
			await get_tree().process_frame
		if not is_inside_tree():
			return
		if not is_instance_valid(ft) or not ft.bereit():
			main.open_dialog("Freundestest nicht möglich" if _nur_test() else "Einladen geht gerade nicht", str(ft.stand_text()) if is_instance_valid(ft) else "",
					[["OK", func() -> void: pass]], "warning", "warn")
			return
	if ft.einladen(fuer).is_empty():
		return
	Sfx.play("toggle_on")
	refill()
	_einladung_zeigen()


func _einladung_zeigen() -> void:
	if not FT.laeuft() or FT.aktiv.einladung.is_empty():
		return
	var l = EinladungUi.new()
	l.ft = FT.aktiv
	l.closed.connect(func() -> void:
		if is_inside_tree() and not _closing:
			refill())
	main.open_layer(l)


## Gast: Code aus der Zwischenablage oder eintippen (Bildschirmtastatur), streng prüfen, dann anklopfen.
func _einladung_annehmen() -> void:
	if not await _freund_pruefen() or not is_inside_tree():
		return
	main.open_choice("Einladung annehmen", [["clip", tr("Aus der Zwischenablage")], ["tippen", tr("Code eintippen")]], "", func(w: Variant) -> void:
		if str(w) == "clip":
			code_pruefen(DisplayServer.clipboard_get().left(Einladung.CODE_MAX_EINGABE + 1))
		else:
			main.open_keyboard("Einladungscode", "UZAI-", func(t: String) -> void: code_pruefen(t)), "Den Code hat dir dein Freund geschickt.")


## Einladung aus dem Chat eines Freundes (Notify): wie eingetippt – erst die Abschottung, dann lesen und
## der Hinweis. Mit dem Anklopfen gilt der Code als benutzt (kein zweites Angebot).
func einladung_aus_chat(code: String) -> void:
	if not await _freund_pruefen() or not is_inside_tree():
		return
	code_pruefen(Einladung.code_anzeige(code))


## Den Code lesen (nur lesen – nie ausführen, nie als Link öffnen); passt er, Hinweis und anklopfen.
func code_pruefen(t: String) -> void:
	var l := Einladung.code_lesen(t, int(Time.get_unix_time_from_system()))
	if not bool(l.ok):
		Sfx.play("error")
		main.open_dialog("Code passt nicht", str(CODE_FEHLER.get(str(l.fehler), "Das ist kein Einladungscode.")), [["OK", func() -> void: pass]], "warning", "warn")
		return
	main.open_dialog("Anklopfen", tr("Dein Freund sieht deine IP-Adresse, wenn er dich hereinlässt.\nDie Einladung gilt noch %d Min.") % int(l.rest_min), [
		["Anklopfen", func() -> void:
			var aus_chat := str(Einladung.code_im_text(t, int(Time.get_unix_time_from_system())).code)
			if aus_chat != "":
				Notify.einladungen.benutzt(aus_chat, int(Time.get_unix_time_from_system()))
			FT.gast_starten(get_tree(), t)
			Toasts.show_toast("Klopfe an …", "Dein Freund muss dich hereinlassen", "friends")
			refill()],
		["Abbrechen", func() -> void: pass]], "friends")


func _ins_zimmer() -> void:
	if main and main.room_layer() == null:
		main.open_room()
