#!/usr/bin/env bash
# Alle Prüfungen von Uzai unter Linux (ohne Windows): Kompilierprüfung, Lint, Logik-Tests und –
# ohne „quick“ – die Netz-Proben gegen nachgebaute Dienste auf 127.0.0.1 und der Rundgang.
#
#   tools/run_tests.sh [quick]
#
# Umgebung (alles optional):
#   UZAI_GODOT    Godot 4.5.1 (Standard: godot im PATH)
#   UZAI_PWSH     PowerShell 7 für die Helfer-Proben (sonst übersprungen)
#   UZAI_PROJ     Projektordner (Standard: Ordner über diesem Skript)
#   UZAI_TMP      Ordner für Datenordner der Tests (Standard: mktemp)
#   UZAI_JS_RUNTIME  Node 22 für die Filme-/Nuvio-Proben (Standard: node im PATH)
#   UZAI_TEST_FFMPEG FFmpeg 8.x für den echten Probelauf der Aufnahme (sonst ffmpeg im PATH;
#                    ältere Fassungen zählen Bilder anders, siehe tests/logic_aufnahmen.gd)
#
# Netz-Proben nutzen feste Ports (18765–18821) und laufen deshalb nie zweimal gleichzeitig.
# Am Ende steht FAIL=0, wenn alles in Ordnung ist; der Rückgabewert ist 1 bei einem Fehler.
set -u
PROJ=${UZAI_PROJ:-$(cd "$(dirname "$0")/.." && pwd)}
G=${UZAI_GODOT:-$(command -v godot || true)}
PWSH=${UZAI_PWSH:-$(command -v pwsh || true)}
JS=${UZAI_JS_RUNTIME:-$(command -v node || true)}
TMPROOT=${UZAI_TMP:-$(mktemp -d)}
mkdir -p "$TMPROOT"
cd "$PROJ" || exit 1
[ -x "$G" ] || { echo "Godot fehlt (UZAI_GODOT)"; exit 1; }
fail=0
data() { mktemp -d -p "$TMPROOT"; }
# Letzte Ergebniszeile; ein Zustandswechsel außerhalb seiner Tabelle (src/core/zustand.gd meldet
# „ZUSTAND-VERSTOSS …“) zählt als Fehler und steht dann statt des Ergebnisses da.
ergebnis() { awk '/ZUSTAND-VERSTOSS/ && v == "" { v = $0 } /Ergebnis|SCRIPT ERROR/ { r = $0 } END { print (v != "" ? v : r) }'; }
pruefe() {  # name, ergebniszeile
	echo "$1: $2"
	echo "$2" | grep -q "alles ok" || fail=1
}
stopp() {  # Python-Server mit diesem Muster beenden (nur eigene, über die Befehlszeile erkannt)
	for p in $(pgrep -x python3); do
		if tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -qE "$1"; then kill "$p" 2>/dev/null; fi
	done
}

r=$(timeout 300 "$G" --headless --path . res://tests/check.tscn 2>&1 | grep -E "geprüft" | tail -1)
echo "check: $r"; echo "$r" | grep -q "Fehler: 0" || fail=1
r=$(python3 -I tools/lint_gd.py | tail -1)
echo "lint: $r"; echo "$r" | grep -q "Fehler: 0" || fail=1
pruefe klang_pegel "$(python3 -I tools/synth_tick.py --pruefen | tail -1)"
pruefe klang2_pegel "$(python3 -I tools/synth_klang2.py --pruefen | tail -1)"
pruefe klang3_pegel "$(python3 -I tools/synth_klang3.py --pruefen | tail -1)"
pruefe klang4_pegel "$(python3 -I tools/synth_klang4.py --pruefen | tail -1)"
pruefe kern_stummel "$(bash tests/kern_stummel_probe.sh 2>&1 | tail -1)"

for t in tests/test_logic.tscn tests/logic_*.tscn; do
	n=$(basename "$t" .tscn)
	r=$(UZAI_DATA=$(data) timeout 300 "$G" --headless --path . "res://$t" 2>&1 | ergebnis)
	pruefe "$n" "$r"
done

if [ -n "$PWSH" ]; then
	for t in tests/*_cs.ps1; do
		# Aufruf-Argumente stehen im Kopf der Probe („-File tests/x.ps1 <argumente> →“).
		read -r -a args <<< "$(grep -m1 -oE "File $t [^→]*" "$t" | sed "s|File $t ||")"
		[ ${#args[@]} -eq 0 ] && args=(helper/uzai-helper.ps1)
		r=$("$PWSH" -NoProfile -NonInteractive -File "$t" "${args[@]}" 2>&1 | grep -E "Ergebnis" | tail -1)
		pruefe "$(basename "$t" .ps1)" "$r"
	done
else
	echo "pwsh fehlt: Helfer-Proben übersprungen"
fi

[ "${1:-}" = "quick" ] && { echo "FAIL=$fail"; exit $fail; }

# --- Netz-Proben (nur 127.0.0.1) ---------------------------------------------------------------
LIB=$(mktemp -d -p "$TMPROOT")
if [ -n "$PWSH" ] && gcc -shared -fPIC -o "$LIB/libdiscord_partner_sdk.so" tests/fake_discord_sdk.c; then
	r=$(UZAI_DATA=$(data) UZAI_HELPER_SHELL="$PWSH" LD_LIBRARY_PATH="$LIB" timeout 300 "$G" --headless --path . res://tests/net_discord_dm.tscn 2>&1 | ergebnis)
	pruefe net_discord_dm "$r"
fi
# Zimmer online: zwei Instanzen mit Sandbox (PowerShell 7) und Test-Relay auf 127.0.0.1 (zufälliger Port).
if [ -n "$PWSH" ]; then
	r=$(UZAI_DATA=$(data) UZAI_PWSH="$PWSH" timeout 400 "$G" --headless --path . res://tests/net_zimmer_treff.tscn 2>&1 | ergebnis)
	pruefe net_zimmer_treff "$r"
fi
for t in net_abruf net_downloads net_handy net_retroauto net_shop net_steam_cm; do
	r=$(UZAI_DATA=$(data) timeout 300 "$G" --headless --path . "res://tests/$t.tscn" 2>&1 | ergebnis)
	pruefe "$t" "$r"
done

(python3 tests/fake_spotify.py 18765 >/dev/null 2>&1 &)
(python3 tests/fake_addons.py 18766 >/dev/null 2>&1 &)
(python3 tests/fake_nuvio.py 18767 >/dev/null 2>&1 &)
(python3 tests/fake_medienquellen.py 18791 >/dev/null 2>&1 &)
(python3 tests/fake_twitch.py 18792 >/dev/null 2>&1 &)
(python3 tests/fake_youtube_tv.py 18793 >/dev/null 2>&1 &)
(python3 tests/fake_epic.py 18794 >/dev/null 2>&1 &)
(python3 tests/fake_epic_cdn.py 18789 >/dev/null 2>&1 &)
(python3 tests/fake_epic.py 18821 >/dev/null 2>&1 &)
sleep 2

r=$(UZAI_DATA=$(data) UZAI_SPOTIFY_API=http://127.0.0.1:18765/v1 UZAI_SPOTIFY_ACCOUNTS=http://127.0.0.1:18765 \
	timeout 300 "$G" --headless --path . res://tests/net_musik.tscn 2>&1 | ergebnis); pruefe net_musik "$r"
F=http://127.0.0.1:18766
r=$(UZAI_DATA=$(data) UZAI_FAKE=$F UZAI_CINEMETA=$F/cinemeta/manifest.json UZAI_TMDB_API=$F/tmdb/3 UZAI_JS_RUNTIME="$JS" \
	timeout 300 "$G" --headless --path . res://tests/net_filme.tscn 2>&1 | ergebnis); pruefe net_filme "$r"
F=http://127.0.0.1:18767
r=$(UZAI_DATA=$(data) UZAI_NUVIO_API=$F UZAI_FAKE=$F UZAI_CINEMETA=$F/addon/keins/manifest.json UZAI_JS_RUNTIME="$JS" \
	timeout 300 "$G" --headless --path . res://tests/net_nuvio.tscn 2>&1 | ergebnis); pruefe net_nuvio "$r"
F=http://127.0.0.1:18791
r=$(UZAI_DATA=$(data) UZAI_FAKE=$F UZAI_PLEX_TV=$F/plextv UZAI_STREMIO_LINK=$F/link UZAI_STREMIO_API=$F/stremio \
	UZAI_JF_DISCOVERY=127.0.0.1:18791 timeout 300 "$G" --headless --path . res://tests/net_medienquellen.tscn 2>&1 | ergebnis)
pruefe net_medienquellen "$r"
r=$(UZAI_DATA=$(data) UZAI_TWITCH_API=http://127.0.0.1:18792 timeout 300 "$G" --headless --path . res://tests/net_twitch.tscn 2>&1 | ergebnis)
pruefe net_twitch "$r"
r=$(UZAI_DATA=$(data) UZAI_YT_TV_API=http://127.0.0.1:18793 timeout 300 "$G" --headless --path . res://tests/net_youtube_tv.tscn 2>&1 | ergebnis)
pruefe net_youtube_tv "$r"
r=$(UZAI_DATA=$(data) UZAI_EPIC_API=http://127.0.0.1:18794 timeout 300 "$G" --headless --path . res://tests/net_epic.tscn 2>&1 | ergebnis)
pruefe net_epic "$r"
r=$(UZAI_DATA=$(data) UZAI_TEST_LOOPBACK=1 UZAI_EPIC_API=http://127.0.0.1:18789 timeout 300 "$G" --headless --path . res://tests/net_epic_install.tscn 2>&1 | ergebnis)
pruefe net_epic_install "$r"
r=$(UZAI_DATA=$(data) UZAI_TEST_LOOPBACK=1 UZAI_EPIC_API=http://127.0.0.1:18821 timeout 300 "$G" --headless --path . res://tests/net_epic_spielcode.tscn 2>&1 | ergebnis)
pruefe net_epic_spielcode "$r"
stopp "tests/fake_(spotify|addons|nuvio|medienquellen|twitch|youtube_tv|epic|epic_cdn).py 18"

# --- Rundgang durch alle Bereiche (Bildschirmfotos, braucht xvfb) -------------------------------
if command -v xvfb-run >/dev/null; then
	OUT=$(data)
	r=$(UZAI_DATA=$(data) timeout 600 xvfb-run -a -s "-screen 0 1920x1080x24" "$G" --path . --resolution 1920x1080 \
		-- --demo --uzai-test="$OUT" 2>&1 | grep -E "Rundgang fertig" | tail -1)
	echo "tour: $r ($(ls "$OUT" | wc -l) Bilder)"
	echo "$r" | grep -q "Clip-Schatten: 0" || fail=1
fi
[ -z "${UZAI_TMP:-}" ] && rm -rf "$TMPROOT"
echo "FAIL=$fail"
exit $fail
