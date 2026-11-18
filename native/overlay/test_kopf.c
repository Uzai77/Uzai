/* Prüft die Kopfprüfung des Overlays ohne Windows (tools/bau_overlay.sh --test). */
#include <stdio.h>
#include <string.h>
#include "uzai_overlay.h"

static int fehler = 0;
static void check(int ok, const char *was) {
	printf("  %s %s\n", ok ? "ok  " : "FAIL", was);
	if (!ok) fehler++;
}

int main(void) {
	uzov_kopf k;
	memset(&k, 0, sizeof k);
	check(sizeof(uzov_kopf) == UZOV_KOPF, "Kopf ist 64 Byte");
	k.magic = UZOV_MAGIC; k.version = UZOV_VERSION; k.breite = 620; k.hoehe = 1080; k.zaehler = 2; k.sichtbar = 1;
	size_t n = UZOV_KOPF + 620u * 1080u * 4u;
	check(uzov_laenge(&k) == n, "Länge aus Breite und Höhe");
	check(uzov_kopf_pruefen(&k, n) == 1, "gültiges Bild wird genommen");
	check(uzov_kopf_pruefen(&k, n - 1) == 0, "Datei kürzer als das Bild: nichts tun");
	check(uzov_kopf_pruefen(&k, 10) == 0, "kürzer als der Kopf: nichts tun");
	k.zaehler = 3; check(uzov_kopf_pruefen(&k, n) == 0, "ungerader Zähler (Uzai schreibt): nichts tun"); k.zaehler = 2;
	k.magic = 1; check(uzov_kopf_pruefen(&k, n) == 0, "falsches Kennzeichen: nichts tun"); k.magic = UZOV_MAGIC;
	k.version = 9; check(uzov_kopf_pruefen(&k, n) == 0, "fremde Fassung: nichts tun"); k.version = UZOV_VERSION;
	k.breite = 0; check(uzov_kopf_pruefen(&k, n) == 0, "Breite 0: nichts tun");
	k.breite = UZOV_MAX_BREITE + 1; check(uzov_kopf_pruefen(&k, (size_t)-1) == 0, "zu breit: nichts tun");
	k.breite = 0xFFFFFFFFu; k.hoehe = 0xFFFFFFFFu; check(uzov_kopf_pruefen(&k, (size_t)-1) == 0, "Riesenmaße laufen nicht über");
	k.breite = 620; k.hoehe = 1080; k.sichtbar = 7; check(uzov_kopf_pruefen(&k, n) == 0, "unbekannter Befehl: nichts tun");
	k.sichtbar = 0; check(uzov_kopf_pruefen(&k, n) == 1, "versteckt ist ein gültiger Zustand");
	printf("Ergebnis: %s\n", fehler ? "Fehler" : "alles ok");
	return fehler ? 1 : 0;
}
