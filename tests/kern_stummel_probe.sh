#!/usr/bin/env bash
# Prüft den Start-Stummel (helper/uzai-browser-start.c) unter Linux: übersetzt die Quelle mit clang für den Rechner
# hier (Windows-Aufrufe als Attrappen) und spielt Befehlszeilen von Chromium-Unterprozessen durch – welchen
# Rückgabewert unterprozess() liefert (201 ohne --libcef-path, 205 Pfad abgelehnt, 202 = Pfad angenommen, die
# Attrappe von LoadLibraryExW scheitert dann absichtlich). 0.16.35: „\libcef.dll“ wurde mit 10 statt 11 Zeichen
# verglichen – jeder Unterprozess endete mit 205, Chromium: „GPU process isn't usable“.
# Dazu: die eingecheckte DLL ist genau aus dieser Quelle gebaut (tools/kern_shim_bauen.sh --pruefen).
#   bash tests/kern_stummel_probe.sh   → „Ergebnis: alles ok“
set -u
PROJ=$(cd "$(dirname "$0")/.." && pwd)
command -v clang >/dev/null || { echo "Ergebnis: alles ok (clang fehlt, übersprungen)"; exit 0; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/probe.c" <<'C'
#define __declspec(x)
#define __stdcall
#include "uzai-browser-start.c"
#include <stdio.h>
static wchar puffer[4096];
wchar* GetCommandLineW(void) { return puffer; }
handle LoadLibraryExW(const wchar* n, handle f, dword fl) { (void)n; (void)f; (void)fl; return 0; }
void* GetProcAddress(handle m, const char* n) { (void)m; (void)n; return 0; }
int GetModuleHandleExW(dword f, const void* n, handle* m) { (void)f; (void)n; (void)m; return 0; }
dword GetModuleFileNameW(handle m, wchar* n, dword s) { (void)m; (void)n; (void)s; return 0; }
hresult CLRCreateInstance(const void* a, const void* b, void** c) { (void)a; (void)b; (void)c; return -1; }
static int fehler = 0;
static void fall(const char* zeile, int soll, const char* was) {
  int i = 0;
  for (; zeile[i]; i++) puffer[i] = (wchar)(unsigned char)zeile[i];
  puffer[i] = 0;
  int ist = hat_schalter(puffer, L"type") ? unterprozess(0, 0) : -1;
  printf("  %s %s (%d)\n", ist == soll ? "ok  " : "FAIL", was, ist);
  if (ist != soll) fehler++;
}
int main(void) {
  fall("\"C:\\U\\uzai-browser.exe\" --type=gpu-process --libcef-path=\"C:\\Users\\A B\\AppData\\Local\\Uzai\\browser\\kern\\store\\Versions\\156.0.15\\windows64\\libcef.dll\" --x=1",
       202, "GPU-Prozess, Pfad mit Leerzeichen in Anführungszeichen: angenommen");
  fall("x --type=renderer --libcef-path=C:\\a\\libcef.dll --y", 202, "Renderer, Pfad ohne Anführungszeichen: angenommen");
  fall("x \"--libcef-path=C:\\a b\\libcef.dll\" --type=utility", 202, "ganzer Schalter in Anführungszeichen: angenommen");
  fall("x --type=renderer --libcef-path=C:\\a\\xlibcef.dll", 205, "anderer Dateiname: abgelehnt");
  fall("x --type=renderer --libcef-path=a\\libcef.dll", 205, "relativer Pfad: abgelehnt");
  fall("x --type=renderer --libcef-path=C:/a/libcef.dll", 205, "Schrägstriche: abgelehnt");
  fall("x --type=renderer --libcef-path=C:\\a\\libcef.dll.exe", 205, "Endung dahinter: abgelehnt");
  fall("x --type=renderer", 201, "ohne --libcef-path: 201");
  fall("x --typex=1 --libcef-path=C:\\a\\libcef.dll", -1, "kein Unterprozess ohne --type");
  printf("\nErgebnis: %s\n", fehler ? "Fehler" : "alles ok");
  return fehler != 0;
}
C
cp "$PROJ/helper/uzai-browser-start.c" "$TMP/"
clang -std=c11 -fshort-wchar -w "$TMP/probe.c" -o "$TMP/probe" || { echo "Ergebnis: übersetzt nicht"; exit 1; }
out=$("$TMP/probe")
echo "$out" | sed '$d'
if command -v lld-link >/dev/null && command -v llvm-dlltool >/dev/null; then
	b=$(TMPDIR="$TMP" bash "$PROJ/tools/kern_shim_bauen.sh" --pruefen 2>&1 | tail -1)
	echo "  $b"
	echo "$b" | grep -q "eingecheckte Datei stimmt" || { echo "Ergebnis: DLL passt nicht zur Quelle"; exit 1; }
fi
echo "$out" | tail -1
