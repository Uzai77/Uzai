#!/usr/bin/env bash
# Baut den Start-Stummel des Browser-Kerns (helper/uzai-browser-start.c → assets/browser/cef/uzai-browser-start.dll)
# unter Linux, reproduzierbar: clang (Ziel x86_64-pc-windows-msvc, freistehend, ohne Laufzeitbibliothek) und
# lld-link (/Brepro: keine Zeitstempel). Die Importbibliotheken für kernel32 und mscoree entstehen aus .def-Dateien
# mit llvm-dlltool – es wird kein Windows-SDK gebraucht. Am Ende steht die SHA-256, die in
# src/core/browser_kern.gd (SHIM_SHA256) und helper/uzai-helper.ps1 eingetragen sein muss.
#
#   tools/kern_shim_bauen.sh            baut und zeigt die Prüfsumme
#   tools/kern_shim_bauen.sh --pruefen  baut in einen Zwischenordner und vergleicht mit der eingecheckten Datei
set -eu
PROJ=$(cd "$(dirname "$0")/.." && pwd)
QUELLE="$PROJ/helper/uzai-browser-start.c"
ZIEL="$PROJ/assets/browser/cef/uzai-browser-start.dll"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for t in clang lld-link llvm-dlltool; do command -v "$t" >/dev/null || { echo "$t fehlt"; exit 1; }; done

printf 'LIBRARY kernel32.dll\nEXPORTS\nGetCommandLineW\nLoadLibraryExW\nGetProcAddress\nGetModuleHandleExW\nGetModuleFileNameW\n' > "$TMP/kernel32.def"
printf 'LIBRARY mscoree.dll\nEXPORTS\nCLRCreateInstance\n' > "$TMP/mscoree.def"
llvm-dlltool -m i386:x86-64 -d "$TMP/kernel32.def" -l "$TMP/kernel32.lib"
llvm-dlltool -m i386:x86-64 -d "$TMP/mscoree.def" -l "$TMP/mscoree.lib"

clang -target x86_64-pc-windows-msvc -std=c11 -O2 -ffreestanding -fno-builtin -nostdlib -fno-stack-protector \
	-fno-exceptions -fno-asynchronous-unwind-tables -mno-stack-arg-probe -fshort-wchar -Wall -Wextra -Werror \
	-c "$QUELLE" -o "$TMP/start.obj"
lld-link /dll /noentry /nodefaultlib /machine:x64 /subsystem:windows,6.1 /Brepro /nxcompat /dynamicbase /highentropyva \
	/out:"$TMP/uzai-browser-start.dll" "$TMP/start.obj" "$TMP/kernel32.lib" "$TMP/mscoree.lib"

# Nachsehen: genau ein Export (RunWinMain), nur die beiden Importe, keine Laufzeitbibliothek.
if command -v llvm-readobj >/dev/null; then
	llvm-readobj --coff-exports --coff-imports "$TMP/uzai-browser-start.dll" > "$TMP/readobj.txt"
	grep -q "Name: RunWinMain" "$TMP/readobj.txt" || { echo "Export RunWinMain fehlt"; exit 1; }
	n=$(grep -c "^  Name: " "$TMP/readobj.txt" || true)
	grep -E "Name: (kernel32|mscoree)\.dll" "$TMP/readobj.txt" | sort -u
	echo "Exporte/Importe: $n Einträge"
fi
sha=$(sha256sum "$TMP/uzai-browser-start.dll" | cut -c1-64)
if [ "${1:-}" = "--pruefen" ]; then
	ist=$(sha256sum "$ZIEL" | cut -c1-64)
	[ "$sha" = "$ist" ] && echo "Stummel: eingecheckte Datei stimmt ($sha)" || { echo "Stummel: eingecheckt $ist, gebaut $sha"; exit 1; }
	exit 0
fi
mkdir -p "$(dirname "$ZIEL")"
cp "$TMP/uzai-browser-start.dll" "$ZIEL"
ls -l "$ZIEL"
echo "SHA-256 $sha"
