#!/usr/bin/env bash
# Windows-Paket bauen: Export aus einem sauberen Arbeitsbaum des aktuellen Commits, dazu die
# Discord-Bibliothek (nur hier, nie im Repo) nach Prüfsumme, dann ZIP. Der ScreenScraper-Programmzugang
# (data/screenscraper_dev.json, .gitignore) kommt NUR mit UZAI_PRIVAT=1 dazu – er stünde lesbar im Paket
# (Uzai.pck). Öffentliche Pakete also immer ohne; dann ist ScreenScraper darin aus.
#   UZAI_GODOT=<godot 4.5.1> bash tools/build_windows.sh <ziel.zip>
#   UZAI_PRIVAT=1 UZAI_GODOT=… bash tools/build_windows.sh <ziel.zip>   # nur fürs eigene Paket
set -euo pipefail
ZIEL=$(realpath -m "${1:?Ziel-ZIP angeben}")
PROJ=$(cd "$(dirname "$0")/.." && pwd)
DLL="$PROJ/third_party/discord/discord_partner_sdk.dll"
DLL_SHA=$(grep -m1 -oE 'SHA-256: +[0-9a-f]{64}' "$PROJ/third_party/discord/QUELLE.txt" | awk '{print $2}')
TMP=$(mktemp -d)
trap 'git -C "$PROJ" worktree remove --force "$TMP/wt" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

git -C "$PROJ" worktree add -q --detach "$TMP/wt" HEAD
[ -d "$PROJ/.godot" ] && cp -r "$PROJ/.godot" "$TMP/wt/"
SS="$PROJ/data/screenscraper_dev.json"
if [ "${UZAI_PRIVAT:-}" = "1" ] && [ -f "$SS" ]; then
	cp "$SS" "$TMP/wt/data/"
	# export_presets.cfg schließt die Datei sonst aus (ein Export im eigenen Arbeitsordner packte sie früher still mit).
	sed -i 's#, data/screenscraper_dev.json"#"#' "$TMP/wt/export_presets.cfg"
	echo "Hinweis: PRIVATES Paket – der ScreenScraper-Zugang steht lesbar darin. Nicht veröffentlichen."
else
	echo "Hinweis: ohne ScreenScraper-Programmzugang – ScreenScraper ist im Paket aus."
fi
# Figuren (assets/figur/psx): dürfen ins Paket, aber nicht ins Repository – darum aus dem eigenen Arbeitsordner.
FIG="$PROJ/assets/figur/psx"
if [ -d "$FIG" ]; then
	mkdir -p "$TMP/wt/assets/figur"
	cp -r "$FIG" "$TMP/wt/assets/figur/"
else
	echo "Hinweis: ohne Figuren (assets/figur/psx fehlt) – das Zimmer bleibt ohne sichtbare Figur."
fi
mkdir -p "$TMP/wt/build"
timeout 600 "$UZAI_GODOT" --headless --path "$TMP/wt" --import >/dev/null 2>&1 || true
# Kein Paket mit einem Skript, das sich nicht übersetzen lässt (0.16.24 lief so ohne Startbild hinaus).
PRUEF=$(timeout 300 "$UZAI_GODOT" --headless --path "$TMP/wt" res://tests/check.tscn 2>&1 | grep -E "geprüft|^FEHLER" || true)
echo "$PRUEF" | grep -q "geprüft, Fehler: 0" || { echo "Skripte übersetzen nicht:" >&2; echo "$PRUEF" >&2; exit 1; }
timeout 900 "$UZAI_GODOT" --headless --path "$TMP/wt" --export-release "Windows" build/Uzai.exe
[ -f "$TMP/wt/build/Uzai.exe" ] || { echo "Export fehlgeschlagen" >&2; exit 1; }

if [ -f "$DLL" ]; then
	echo "$DLL_SHA  $DLL" | sha256sum -c --quiet - || { echo "Discord-Bibliothek: Prüfsumme passt nicht zu QUELLE.txt" >&2; exit 1; }
	cp "$DLL" "$TMP/wt/build/"
else
	echo "Hinweis: keine Discord-Bibliothek – Nachrichten brauchen sie dann extra neben Uzai.exe."
fi

rm -f "$ZIEL"
(cd "$TMP/wt/build" && zip -q -r "$ZIEL" .)
echo "Paket: $ZIEL"
(cd "$TMP/wt/build" && ls -l)
