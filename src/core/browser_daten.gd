extends RefCounted
## Uzai-Browser: was sich der Browser merkt – je Uzai-Profil in den Einstellungen (browser.*):
##   favoriten  Lesezeichen (höchstens 48)          apps     als App angeheftete Seiten mit eigener Zoomstufe (24)
##   zuletzt    zuletzt besucht (30, neueste vorn; aus mit browser.verlauf, nie im privaten Tab)
##   zoom       Zoomstufe je Seite (Name → Prozent, 200)   stellen  Stelle je Seite (Schlüssel → Punkt, 150)
##   suche      gewählte Suchmaschine                 sitzung  offene Tabs beim Schließen (12)
## Jeder Eintrag wird beim Lesen neu geprüft (Adresse nach browser_adresse.gd, Titel ohne
## Steuerzeichen, Länge) – auch einer aus einer Sicherung oder einer von Hand geänderten Datei.
## Passwörter speichert Uzai nie. Tests: tests/logic_browser.gd.

const Adresse := preload("res://src/core/browser_adresse.gd")

const MAX := { "favoriten": 48, "apps": 24, "zuletzt": 30, "sitzung": 12 }
const MAX_ZOOM := 200
const MAX_STELLEN := 150
const TITEL_MAX := 120


## Gibt es den Browser hier? Nur unter Windows (WebView2) bzw. im Vorführmodus, nicht im sicheren Modus und
## nicht im Kinderprofil (kein Filter für Webseiten).
static func verfuegbar() -> bool:
	return (OS.get_name() == "Windows" or "--demo" in OS.get_cmdline_user_args()) and not Config.safe_mode and not Config.is_kid()


## Einträge einer Liste (favoriten, apps, zuletzt, sitzung), geprüft: [{ url, titel, zoom? }].
static func liste(art: String) -> Array:
	var roh: Variant = Config.get_value("browser." + art, [])
	return saeubern(roh, int(MAX.get(art, 0)), art == "apps")


static func saeubern(roh: Variant, max_n: int, mit_zoom := false) -> Array:
	var out: Array = []
	if not (roh is Array):
		return out
	var gesehen := {}
	for e in roh:
		if out.size() >= max_n:
			break
		if not (e is Dictionary):
			continue
		var url: Variant = e.get("url", "")
		# Gemerkte Ziele dürfen ins Heimnetz zeigen (selbst gewählt), nie auf diesen PC.
		if not (url is String) or Adresse.grund(url, true) != "" or gesehen.has(url):
			continue
		gesehen[url] = true
		var titel := Adresse.sauber(e.get("titel", ""), TITEL_MAX)
		var eintrag := { "url": url, "titel": titel if titel != "" else Adresse.host_von(url) }
		if mit_zoom:
			eintrag["zoom"] = zoom_wert(e.get("zoom", 100))
		out.append(eintrag)
	return out


static func zoom_wert(v: Variant) -> int:
	if not (v is int or v is float):
		return 100
	return clampi(int(v), 25, 300)


static func _setzen(art: String, liste_neu: Array) -> void:
	Config.set_value("browser." + art, liste_neu.slice(0, int(MAX.get(art, 0))))


static func hat(art: String, url: String) -> bool:
	for e in liste(art):
		if e.url == url:
			return true
	return false


## Lesezeichen setzen bzw. entfernen; true = jetzt gesetzt.
static func favorit_umschalten(url: String, titel: String) -> bool:
	if Adresse.grund(url, true) != "":
		return false
	var l := liste("favoriten")
	for i in l.size():
		if l[i].url == url:
			l.remove_at(i)
			_setzen("favoriten", l)
			return false
	l.push_front({ "url": url, "titel": Adresse.sauber(titel, TITEL_MAX) })
	_setzen("favoriten", l)
	return true


## Als App anheften (mit der Zoomstufe der Seite) bzw. lösen; true = jetzt angeheftet.
static func app_umschalten(url: String, titel: String, zoom: int) -> bool:
	if Adresse.grund(url, true) != "":
		return false
	var l := liste("apps")
	for i in l.size():
		if l[i].url == url:
			l.remove_at(i)
			_setzen("apps", l)
			return false
	l.append({ "url": url, "titel": Adresse.sauber(titel, TITEL_MAX), "zoom": zoom_wert(zoom) })
	_setzen("apps", l)
	return true


## Besuchte Seite vorn in „Zuletzt besucht“ (nie im privaten Tab, nicht wenn der Verlauf aus ist).
static func besucht(url: String, titel: String, privat: bool) -> void:
	if privat or not bool(Config.get_value("browser.verlauf", true)) or Adresse.grund(url, true) != "":
		return
	var l := liste("zuletzt").filter(func(e: Dictionary) -> bool: return e.url != url)
	l.push_front({ "url": url, "titel": Adresse.sauber(titel, TITEL_MAX) })
	_setzen("zuletzt", l)


static func verlauf_leeren() -> void:
	Config.set_value("browser.zuletzt", [])
	Config.set_value("browser.stellen", {})


## Zoomstufe einer Seite (nach Name), 100 wenn nichts gemerkt ist.
static func zoom_fuer(url: String) -> int:
	var z: Variant = Config.get_value("browser.zoom", {})
	var h := Adresse.host_von(url)
	if not (z is Dictionary) or h == "":
		return 100
	return zoom_wert((z as Dictionary).get(h, 100))


static func zoom_merken(url: String, prozent: int) -> void:
	var h := Adresse.host_von(url)
	if h == "":
		return
	var z: Variant = Config.get_value("browser.zoom", {})
	var d: Dictionary = (z as Dictionary).duplicate() if z is Dictionary else {}
	d.erase(h)
	if prozent != 100:
		d[h] = zoom_wert(prozent)
	while d.size() > MAX_ZOOM:
		d.erase(d.keys()[0])
	Config.set_value("browser.zoom", d)


## Gemerkte Stelle einer Seite (Mitte des letzten Ziels in Seiten-Koordinaten) oder (-1, -1).
static func stelle(url: String) -> Vector2:
	var s: Variant = Config.get_value("browser.stellen", {})
	if not (s is Dictionary):
		return Vector2(-1, -1)
	var p: Variant = (s as Dictionary).get(Adresse.seiten_schluessel(url), null)
	if not (p is Array) or (p as Array).size() != 2 or not (p[0] is float or p[0] is int) or not (p[1] is float or p[1] is int):
		return Vector2(-1, -1)
	return Vector2(clampf(float(p[0]), 0.0, 100000.0), clampf(float(p[1]), 0.0, 10000000.0))


static func stelle_merken(url: String, p: Vector2, privat: bool) -> void:
	if privat or Adresse.grund(url, true) != "":
		return
	var s: Variant = Config.get_value("browser.stellen", {})
	var d: Dictionary = (s as Dictionary).duplicate() if s is Dictionary else {}
	var k := Adresse.seiten_schluessel(url)
	d.erase(k)
	d[k] = [roundi(p.x), roundi(p.y)]
	while d.size() > MAX_STELLEN:
		d.erase(d.keys()[0])
	Config.set_value("browser.stellen", d)


static func suchmaschine() -> String:
	return str(Adresse.maschine(str(Config.get_value("browser.suche", Adresse.STANDARD_SUCHE))).id)


## Offene Tabs merken (für den nächsten Start), ohne private.
static func sitzung_merken(tabs: Array) -> void:
	var l: Array = []
	for t in tabs:
		if not bool(t.get("privat", false)) and Adresse.grund(str(t.get("url", "")), true) == "":
			l.append({ "url": str(t.url), "titel": Adresse.sauber(t.get("titel", ""), TITEL_MAX) })
	_setzen("sitzung", l)


## Kurzes Zeichen für eine Kachel ohne Bild: erster Buchstabe des Namens der Seite.
static func monogramm(url: String) -> String:
	var h := Adresse.host_von(url)
	for ch in h:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			return ch.to_upper()
	return "•"
