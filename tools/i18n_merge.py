"""Übersetzungs-Teile in i18n/en.json zusammenführen.

Jeder Teil ist eine JSON-Datei {"deutscher Text": "English text"}, z. B. von einem Arbeitszweig,
der so keine Merge-Konflikte in der großen en.json erzeugt. Vorhandene Einträge werden nur
überschrieben, wenn der Teil einen nicht leeren Text bringt.

    python3 -I tools/i18n_merge.py i18n/en.json <teil.json> [<teil.json> …]
    python3 -I tools/i18n_merge.py i18n/en.json <ordner mit teilen>
"""
import json
import pathlib
import sys


def main() -> int:
	if len(sys.argv) < 3:
		print(__doc__)
		return 2
	target = pathlib.Path(sys.argv[1])
	data = json.loads(target.read_text(encoding="utf-8"))
	parts = []
	for a in sys.argv[2:]:
		p = pathlib.Path(a)
		parts += sorted(p.glob("*.json")) if p.is_dir() else [p]
	for p in parts:
		part = json.loads(p.read_text(encoding="utf-8"))
		if not isinstance(part, dict):
			print(f"übersprungen (kein Objekt): {p}")
			continue
		for k, v in part.items():
			if isinstance(k, str) and isinstance(v, str) and v.strip():
				data[k] = v
	out = json.dumps(dict(sorted(data.items())), ensure_ascii=False, indent="\t")
	target.write_text(out, encoding="utf-8")
	print(len(data))
	return 0


if __name__ == "__main__":
	sys.exit(main())
