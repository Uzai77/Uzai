extends RefCounted
## Gemeinsam für probe_englisch.gd und logic_englisch.gd: sichtbare Texte eines Baums so lesen,
## wie sie auf dem Bildschirm stehen (nach der Übersetzung), und erkennen, ob einer noch deutsch
## aussieht. Namen (Spiele, Freunde aus den Demo-Daten) zählen nicht.

## Häufige deutsche Wörter, die es im Englischen nicht gibt (klein geschrieben verglichen).
const WOERTER := ["und", "oder", "nicht", "mit", "für", "der", "das", "den", "dem", "des", "ein", "eine",
	"einen", "einem", "ist", "sind", "noch", "alle", "alles", "auch", "auf", "aus", "bei", "zum", "zur",
	"vom", "nach", "wird", "kein", "keine", "jetzt", "hier", "dein", "deine", "deinen", "deiner", "ich",
	"wir", "gestern", "heute", "zuletzt", "spielen", "gespielt", "zurück", "weiter", "wählen",
	"auswählen", "starten", "suchen", "einstellungen", "spiele", "spiel", "freunde", "bereit", "fertig",
	"mehr", "std", "tage", "tagen", "woche", "stunden", "minuten", "uhr", "ohne", "über", "schon",
	"bitte", "ja", "nein", "neu", "neue", "läuft", "gerade", "seit", "vor", "beenden", "abbrechen",
	"schließen", "öffnen", "anzeigen", "ändern", "hinzufügen", "entfernen", "laden", "lädt", "wird",
	"bibliothek", "erfolge", "aufnahmen", "musik", "filme", "zimmer", "konto", "konten", "anmelden",
	"verbunden", "nie", "immer", "aktiv", "zeigen", "wie", "sich", "dich", "uns", "euch",
	"wenn", "dann", "sonst", "eingerichtet", "gefunden", "verbinden", "bild", "lauter",
	"leiser", "jahr", "monat", "woche", "morgen", "abends", "mitteilungen", "spielzeit",
	"stelle", "weiterspielen", "einrichten", "überspringen", "fortsetzen"]
const UMLAUT := "äöüÄÖÜß"

var namen: Array = []          ## längste zuerst: werden vor der Prüfung aus dem Text genommen
var _katalog := {}
var _woerter := {}
var _tags := RegEx.create_from_string("\\[[^\\]]*\\]")
var _wort := RegEx.create_from_string("[A-Za-zÄÖÜäöüß]+")


func _init() -> void:
	for w in WOERTER:
		_woerter[w] = true
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://i18n/en.json"))
	if d is Dictionary:
		_katalog = d


## Namen aus den geladenen (Demo-)Daten: Spieltitel, Freunde, Musik, Filme.
func namen_aus_demo() -> void:
	var n := {}
	var lib: Node = Engine.get_main_loop().root.get_node_or_null("Library")
	if lib:
		for g in lib.games:
			for k in ["title", "name", "developer", "publisher"]:
				if str(g.get(k, "")).length() > 1:
					n[str(g.get(k, ""))] = true
			n[str(lib.display_title(g))] = true
	var soc: Node = Engine.get_main_loop().root.get_node_or_null("Social")
	if soc:
		for f in soc.steam_friends:
			if f is Dictionary:
				for k in ["name", "game", "server"]:
					if str(f.get(k, "")).length() > 1:
						n[str(f.get(k, ""))] = true
		for sid in soc.discord:
			n[str((soc.discord[sid] as Dictionary).get("name", ""))] = true
	for k in ["Uzai", "Steam", "Discord", "Spotify", "YouTube", "Twitch", "Xbox", "PlayStation", "RetroArch"]:
		n[k] = true
	namen_setzen(n.keys())


func namen_setzen(liste: Array) -> void:
	namen = liste.duplicate()
	namen.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())


func im_katalog(t: String) -> bool:
	return _katalog.has(t)


## Alle sichtbaren Texte unter n, so wie sie gezeigt werden (Label, Button, RichTextLabel,
## Platzhalter von Eingabefeldern), nur was im Bild liegt.
func sichtbare_texte(n: Node, bild := Rect2()) -> Array:
	var out: Array = []
	if bild.size == Vector2.ZERO:
		bild = Rect2(Vector2.ZERO, Engine.get_main_loop().root.get_visible_rect().size)
	_sammeln(n, out, bild)
	return out


func _sammeln(n: Node, out: Array, bild: Rect2) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var t := ""
		if c is Label:
			t = (c as Label).text
		elif c is Button:
			t = (c as Button).text
		elif c is RichTextLabel:
			t = (c as RichTextLabel).text
		elif c is LineEdit:
			t = (c as LineEdit).placeholder_text
		if t.strip_edges() != "" and c.get_global_rect().intersects(bild) and c.modulate.a > 0.01:
			if c.can_auto_translate():
				t = c.atr(t)
			if c is RichTextLabel:
				t = _tags.sub(t, "", true)
			out.append(t.strip_edges())
	for k in n.get_children():
		_sammeln(k, out, bild)


## „“ = sieht englisch aus, sonst der Grund („Umlaut“, „Wort: zuletzt“).
func deutsch(t: String) -> String:
	var s := t
	for nm in namen:
		if s.contains(str(nm)):
			s = s.replace(str(nm), " ")
	for ch in UMLAUT:
		if s.contains(ch):
			return "Umlaut"
	for m in _wort.search_all(s):
		var w := m.get_string().to_lower()
		if _woerter.has(w):
			return "Wort: " + w
	return ""
