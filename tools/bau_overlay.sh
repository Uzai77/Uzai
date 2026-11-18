#!/usr/bin/env bash
# Baut das Overlay im Spiel (Versuch, docs/OVERLAY.md) aus native/overlay/ für Windows, 32 und 64 Bit:
#
#   assets/overlay/uzai-overlay32.dll  uzai-overlay64.dll          die Bibliothek im Spiel (Direct3D 9 und 11)
#   assets/overlay/uzai-overlay-start32.exe  …-start64.exe         der Starter (lädt sie in das eine Spiel)
#
# Eigener Code, keine fremden Quellen, keine Abhängigkeit außer Windows-Systembibliotheken.
# Kreuzbau mit mingw-w64; Härtung /DYNAMICBASE, /NXCOMPAT (64 Bit: /HIGHENTROPYVA), ohne Zeitstempel und Pfade.
#
#   tools/bau_overlay.sh              bauen nach assets/overlay/, Prüfsummen ausgeben
#   tools/bau_overlay.sh --pruefen    in einen Zwischenordner bauen und mit assets/overlay/ vergleichen (bit-gleich?)
#   tools/bau_overlay.sh --test       Kopfprüfung als C-Test unter Linux (ohne Windows, ohne mingw)
#   tools/bau_overlay.sh --wine       Durchlauf unter Wine: Testspiele (Direct3D 9 und 11, 64 Bit), Starter, zeigen, verstecken
#
# Werkzeuge: i686-w64-mingw32-gcc, x86_64-w64-mingw32-gcc (apt: gcc-mingw-w64-i686 gcc-mingw-w64-x86-64), gcc;
# für --wine: wine64 (apt, liegt unter /usr/lib/wine), xvfb-run, python3.
# Bit-gleich nachgebaut mit Ubuntu 24.04: gcc-mingw-w64 13.2.0-6ubuntu1+26.1, binutils-mingw-w64 2.41.90.20240122,
# mingw-w64-dev 11.0.1. Andere Fassungen bauen dieselben Quellen, aber nicht bit-gleich.
set -eu
PROJ=$(cd "$(dirname "$0")/.." && pwd)
Q="$PROJ/native/overlay"
ZIEL="$PROJ/assets/overlay"
MODUS=${1:-bauen}
W="-std=c11 -O2 -Wall -Wextra -Werror -fno-ident -ffile-prefix-map=$Q=."
L="-static-libgcc -s -Wl,--no-insert-timestamp -Wl,--dynamicbase -Wl,--nxcompat"

bauen() {   # bauen <Zielordner>
	local z=$1
	mkdir -p "$z"
	( cd "$Q"
	  # Feste Bildbasis (ASLR verschiebt sie beim Laden): Sonst wählt der Binder sie aus dem Pfad der Ausgabedatei.
	  i686-w64-mingw32-gcc $W -frandom-seed=uzai_overlay.c -shared -Wl,--kill-at $L \
	      -Wl,--disable-auto-image-base -Wl,--image-base=0x62a00000 -o "$z/uzai-overlay32.dll" uzai_overlay.c
	  x86_64-w64-mingw32-gcc $W -frandom-seed=uzai_overlay.c -shared $L -Wl,--high-entropy-va \
	      -Wl,--disable-auto-image-base -Wl,--image-base=0x182a00000 -o "$z/uzai-overlay64.dll" uzai_overlay.c
	  i686-w64-mingw32-gcc $W -frandom-seed=uzai_inject.c -municode $L -o "$z/uzai-overlay-start32.exe" uzai_inject.c
	  x86_64-w64-mingw32-gcc $W -frandom-seed=uzai_inject.c -municode $L -Wl,--high-entropy-va -o "$z/uzai-overlay-start64.exe" uzai_inject.c )
}

case "$MODUS" in
	--test)
		T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
		gcc -std=c11 -Wall -Wextra -Werror -O2 -o "$T/test_kopf" "$Q/test_kopf.c"
		"$T/test_kopf"
		;;
	--pruefen)
		T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
		bauen "$T"
		ok=0
		for f in uzai-overlay32.dll uzai-overlay64.dll uzai-overlay-start32.exe uzai-overlay-start64.exe; do
			if cmp -s "$T/$f" "$ZIEL/$f"; then echo "gleich: $f"; else echo "ANDERS: $f"; ok=1; fi
		done
		exit $ok
		;;
	--wine)
		T=$(mktemp -d); trap 'WINEPREFIX="$T/prefix" /usr/lib/wine/wineserver -k 2>/dev/null || true; rm -rf "$T"' EXIT
		export PATH=/usr/lib/wine:$PATH WINEPREFIX="$T/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
		cp "$ZIEL/uzai-overlay64.dll" "$ZIEL/uzai-overlay-start64.exe" "$T/"
		x86_64-w64-mingw32-gcc -std=c11 -O2 -Wall -Wextra -Werror -static-libgcc -o "$T/testspiel9.exe" "$Q/test_d3d9.c" -ld3d9
		x86_64-w64-mingw32-gcc -std=c11 -O2 -Wall -Wextra -Werror -static-libgcc -o "$T/testspiel11.exe" "$Q/test_d3d11.c" -ld3d11
		cat > "$T/lauf.sh" <<'LAUF'
#!/usr/bin/env bash
D=$1; SPIEL=$2; NAME=$3
rm -f "$D/aus.txt"
echo "$NAME"
win() { echo "Z:${1//\//\\}"; }
bild() {   # bild <sichtbar>: rotes Testbild 100×200 schreiben
	python3 - "$D/bild.bin" "$1" <<'PY'
import struct, sys
w, h = 100, 200
kopf = struct.pack('<6I', 0x564F5A55, 1, 2, int(sys.argv[2]), w, h) + b'\0' * 40
open(sys.argv[1], 'wb').write(kopf + bytes([255, 0, 0, 255]) * (w * h))
PY
}
punkt() { tail -1 "$D/aus.txt" | tr -d '\r'; }
bild 1
wine64 "$D/$SPIEL" "$(win "$D/aus.txt")" &
for i in $(seq 1 200); do grep -q "punkt" "$D/aus.txt" 2>/dev/null && break; sleep 0.3; done
pid=$(grep -o "pid=[0-9]*" "$D/aus.txt" | cut -d= -f2)
vorher=$(punkt)
erg=$(wine64 "$D/uzai-overlay-start64.exe" "$pid" "$(win "$D/uzai-overlay64.dll")" "$(win "$D/bild.bin")" | tr -d '\r')
sleep 1.5; sichtbar=$(punkt)
python3 - "$D/bild.bin" <<'PY'
import struct, sys
f = open(sys.argv[1], 'r+b')
for ort, wert in ((8, 3), (12, 0), (8, 4)):      # Zähler ungerade, verstecken, Zähler gerade
    f.seek(ort); f.write(struct.pack('<I', wert))
f.close()
PY
sleep 1.5; versteckt=$(punkt)
zweit=$(wine64 "$D/uzai-overlay-start64.exe" "$pid" "$(win "$D/uzai-overlay64.dll")" "$(win "$D/bild.bin")" | tr -d '\r')
fremd=$(wine64 "$D/uzai-overlay-start64.exe" 999999 "$(win "$D/uzai-overlay64.dll")" "$(win "$D/bild.bin")" | tr -d '\r')
wait
ende=$(punkt)
f=0
p() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (ist „$2“, soll „$3“)"; f=1; fi; }
p "vor dem Laden zeigt das Testspiel sein Blau" "$vorher" "punkt 0 0 200"
p "Starter meldet: Haken sitzt" "$erg" "ergebnis=1"
p "sichtbar: das Overlay liegt über dem fertigen Bild" "$sichtbar" "punkt 255 0 0"
p "versteckt: wieder das Bild des Spiels" "$versteckt" "punkt 0 0 200"
p "zweiter Aufruf: lief schon, nichts doppelt" "$zweit" "ergebnis=5"
p "fremde Prozessnummer: nicht zu öffnen" "$fremd" "ergebnis=11"
case "$ende" in ende*) echo "  ok   das Testspiel lief bis zum Ende ($ende)";; *) echo "  FAIL das Testspiel endete nicht sauber ($ende)"; f=1;; esac
[ $f = 0 ] && echo "Ergebnis: alles ok" || echo "Ergebnis: Fehler"
exit $f
LAUF
		chmod +x "$T/lauf.sh"
		f=0
		xvfb-run -a -s "-screen 0 1280x720x24" "$T/lauf.sh" "$T" testspiel9.exe "Direct3D 9" 2>/dev/null || f=1
		xvfb-run -a -s "-screen 0 1280x720x24" "$T/lauf.sh" "$T" testspiel11.exe "Direct3D 11 (DXGI)" 2>/dev/null || f=1
		exit $f
		;;
	bauen)
		bauen "$ZIEL"
		( cd "$ZIEL" && sha256sum uzai-overlay32.dll uzai-overlay64.dll uzai-overlay-start32.exe uzai-overlay-start64.exe )
		;;
	*) echo "Unbekannt: $MODUS" >&2; exit 2 ;;
esac
