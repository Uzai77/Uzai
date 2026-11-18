"""Grobe Suche nach Lücken der englischen Oberfläche (ergänzt tests/probe_englisch.gd).

Findet im Code deutsch aussehende Texte, die sichtbar werden können (Labels, Knöpfe, Toasts,
Hinweise uz_hint_*, open_dialog, open_choice, tr(), …) und
  fehlt       … weder genau noch als Muster in i18n/en.json stehen,
  verkettet   … mit + an einen Wert gehängt werden, ohne dass das Bruchstück im Katalog steht,
  gesperrt    … in einem Label mit AUTO_TRANSLATE_MODE_DISABLED landen und nicht über tr() gehen,
  gezeichnet  … mit draw_string ohne tr() gezeichnet werden,
  daten       … aus data/*.json (Namen, Titel) und nicht im Katalog stehen.
Grob, aber hilfreich: Logs, Config-Schlüssel und Kommentare werden übersprungen.

    python3 -I tools/i18n_luecken.py [projekt] [--nur fehlt,verkettet,…] [--teil teil.json …]
"""
import json
import pathlib
import re
import sys

UMLAUT = re.compile(r"[äöüÄÖÜß]")
WOERTER = set("""und oder nicht mit für der das den dem des ein eine einen einem ist sind noch alle
alles auch auf aus bei zum zur vom nach wird kein keine jetzt hier dein deine deinen deiner ich wir
gestern heute zuletzt spielen gespielt zurück weiter wählen auswählen starten suchen einstellungen
spiele spiel freunde bereit fertig mehr std tage tagen woche stunden minuten uhr ohne über schon
bitte nein neu neue läuft gerade seit vor beenden abbrechen schließen öffnen anzeigen ändern
hinzufügen entfernen laden lädt bibliothek erfolge aufnahmen musik filme zimmer konto konten
anmelden verbunden nie immer zeigen wie sich dich uns wenn dann sonst eingerichtet gefunden
verbinden bild lauter leiser jahr monat morgen mitteilungen spielzeit stelle weiterspielen
einrichten überspringen fortsetzen""".split())
WORT = re.compile(r"[A-Za-zÄÖÜäöüß]+")
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
SLOT = re.compile(r"%[-\d.]*[sdfxX]")
# Zeilen, deren Texte nie auf dem Bildschirm landen.
STUMM = re.compile(r"(\w*(?:log|Log|protokoll|diag|debug)\w*\(|\"diagnose\"|line \+=|\b(?:print|prints|printerr|push_error|push_warning|_log|Log\.\w+|assert|get_value|set_value|"
	r"has_meta|get_meta|set_meta\(\"uz_(?!hint)|remove_meta|emit_signal|connect|has_method|call_deferred|"
	r"load|preload|FileAccess|DirAccess|OS\.\w+|JSON|RegEx|match_|begins_with|ends_with|contains|find|split|"
	r"replace|helper\.\w+|Helper\.\w+|run_cmd|\.call\(|group|is_in_group)\b)")
SICHTBAR = re.compile(r"(\.text\s*=|label\(|button\(|Button|toast|notify|Notify|uz_hint_|open_dialog|open_choice|"
	r"setup\(|\btr\(|translate\(|title|sub|head|hint|add_label|add_row|row\(|item\(|_zeile|caption|placeholder|"
	r"tooltip|text\b)", re.I)


def deutsch(s: str) -> bool:
	if UMLAUT.search(s):
		return True
	return any(w.lower() in WOERTER for w in WORT.findall(SLOT.sub(" ", s)))


def wie_text(s: str) -> bool:
	"""Sieht der Text wie ein sichtbarer Satz aus (nicht wie ein Schlüssel, Pfad oder Name)?"""
	if len(s) < 3 or "://" in s or s.startswith(("res:", "user:", "@", "#", "uz_")):
		return False
	if " " not in s and (re.fullmatch(r"[a-z0-9_.\-:/]+", s) or "_" in s or "." in s.strip(".")):
		return False
	return bool(re.search(r"[A-Za-zÄÖÜäöüß]{2}", s))


class Katalog:
	def __init__(self, d: dict):
		self.d = d
		self.muster = []
		for k in d:
			if SLOT.search(k):
				rx = "^" + "".join(".+?" if SLOT.fullmatch(p) else re.escape(p) for p in re.split(r"(%[-\d.]*[sdfxX])", k)) + "$"
				try:
					self.muster.append(re.compile(rx, re.S))
				except re.error:
					pass

	def kennt(self, s: str) -> bool:
		if s in self.d or s.strip() in self.d:
			return True
		if SLOT.search(s):
			return False
		return any(m.match(s) for m in self.muster)


def ohne_kommentar(zeile: str) -> str:
	"""Den Teil vor einem # außerhalb von Texten."""
	in_str = False
	esc = False
	for i, ch in enumerate(zeile):
		if esc:
			esc = False
			continue
		if ch == "\\":
			esc = True
		elif ch == '"':
			in_str = not in_str
		elif ch == "#" and not in_str:
			return zeile[:i]
	return zeile


def entschluesseln(s: str) -> str:
	return s.replace("\\n", "\n").replace('\\"', '"').replace("\\t", "\t").replace("\\\\", "\\")


def code_pruefen(proj: pathlib.Path, kat: Katalog, funde: list) -> None:
	for p in sorted((proj / "src").rglob("*.gd")):
		rel = str(p.relative_to(proj))
		zeilen = p.read_text(encoding="utf-8").splitlines()
		gesperrt = set()
		for z in zeilen:
			m = re.match(r"\s*([A-Za-z_][\w.]*)\.auto_translate_mode\s*=\s*Node\.AUTO_TRANSLATE_MODE_DISABLED", z)
			if m:
				gesperrt.add(m.group(1).split(".")[-1])
		for nr, roh in enumerate(zeilen, 1):
			z = ohne_kommentar(roh)
			if not z.strip() or z.lstrip().startswith(("##", "const ", "@")) and "[" not in z and "{" not in z:
				continue
			if STUMM.search(z) and not SICHTBAR.search(z):
				continue
			for m in STR.finditer(z):
				s = entschluesseln(m.group(1))
				if not wie_text(s) or not deutsch(s):
					continue
				vor = z[:m.start()]
				nach = z[m.end():]
				# Schlüssel eines Wörterbuchs („"name": …“) und Vergleiche („== "…"“) sind kein Text.
				if re.match(r"\s*:", nach) and not re.search(r"(text|title|titel|label|sub|name|hint|head)\"?\s*$", vor, re.I):
					continue
				if re.search(r"(==|!=|\bin)\s*$", vor) or re.match(r"\s*(==|!=)", nach):
					continue
				if not kat.kennt(s):
					funde.append(("fehlt", rel, nr, s))
					continue
				# Verkettung: „"Live seit " + x“ – nur Bruchstücke am Rand, die der Katalog nicht kennt.
				if (re.match(r"\s*\+", nach) or re.search(r"\+\s*$", vor)) and (s != s.strip()) and s not in kat.d:
					funde.append(("verkettet", rel, nr, s))
			# Gesperrtes Label mit festem deutschem Text (ohne tr()).
			m2 = re.search(r"\b(?:var\s+)?(\w+)\s*:?=\s*U\.(?:label|ellipsis\(U\.label)\(\s*\"((?:[^\"\\]|\\.)*)\"", z)
			if m2 and m2.group(1) in gesperrt and deutsch(m2.group(2)) and wie_text(m2.group(2)):
				funde.append(("gesperrt", rel, nr, m2.group(2)))
			if "draw_string(" in z and "tr(" not in z and "translate(" not in z:
				m3 = re.search(r"draw_string\([^,]+,[^,]+,\s*([^,]+),", z)
				if m3:
					arg = m3.group(1).strip()
					lit = STR.fullmatch(arg)
					if lit and deutsch(lit.group(1)):
						funde.append(("gezeichnet", rel, nr, lit.group(1)))
					elif re.fullmatch(r"\w+", arg) and not _uebersetzt(zeilen, nr, arg):
						funde.append(("gezeichnet?", rel, nr, arg))


def _uebersetzt(zeilen: list, nr: int, var: str) -> bool:
	"""Wurde var in den 40 Zeilen davor (oder als Parameter) über tr() gesetzt?"""
	for z in reversed(zeilen[max(0, nr - 40):nr]):
		if re.search(r"\b%s\b\s*(:?=|\+=)" % re.escape(var), z) or re.search(r"func .*\b%s\b" % re.escape(var), z):
			if re.search(r"\btr\(|translate\(|Lang\.|U\.plural|_tr\(", z):
				return True
			if re.search(r"func ", z):
				return False
	return False


def daten_pruefen(proj: pathlib.Path, kat: Katalog, funde: list) -> None:
	for p in sorted((proj / "data").glob("*.json")):
		try:
			d = json.loads(p.read_text(encoding="utf-8"))
		except ValueError:
			continue
		rel = str(p.relative_to(proj))

		def gehen(x, schluessel=""):
			if isinstance(x, dict):
				for k, v in x.items():
					gehen(v, k)
			elif isinstance(x, list):
				for v in x:
					gehen(v, schluessel)
			elif isinstance(x, str) and schluessel in ("name", "title", "titel", "label", "desc", "beschreibung", "text", "sub", "hinweis", "note"):
				if wie_text(x) and deutsch(x) and not kat.kennt(x):
					funde.append(("daten", rel, schluessel, x))
		gehen(d)


def main() -> int:
	args = sys.argv[1:]
	nur = None
	teile = []
	proj = pathlib.Path(__file__).resolve().parent.parent
	i = 0
	while i < len(args):
		if args[i] == "--nur":
			nur = set(args[i + 1].split(","))
			i += 2
		elif args[i] == "--teil":
			teile.append(pathlib.Path(args[i + 1]))
			i += 2
		else:
			proj = pathlib.Path(args[i])
			i += 1
	d = json.loads((proj / "i18n" / "en.json").read_text(encoding="utf-8"))
	for t in teile:
		d.update(json.loads(t.read_text(encoding="utf-8")))
	kat = Katalog(d)
	funde: list = []
	code_pruefen(proj, kat, funde)
	daten_pruefen(proj, kat, funde)
	zahl: dict = {}
	for art, datei, nr, s in funde:
		if nur and art not in nur:
			continue
		zahl[art] = zahl.get(art, 0) + 1
		print(f"{art:12} {datei}:{nr}  {s!r}")
	print("Summe: " + ", ".join(f"{k} {v}" for k, v in sorted(zahl.items())))
	return 0


if __name__ == "__main__":
	sys.exit(main())
