/* Uzai – Overlay im Spiel (Versuch, docs/OVERLAY.md).
 * Gemeinsamer Kopf des Bildes, das Uzai in eine Datei schreibt und die Bibliothek im Spiel liest.
 * Reines C ohne Windows-Köpfe: Die Prüfung läuft auch als Test unter Linux (test_kopf.c).
 *
 * Aufbau der Datei: 64 Byte Kopf, danach breite*hoehe*4 Byte Bildpunkte (R, G, B, A je Punkt,
 * Zeilen von oben nach unten). Alle Zahlen 32 Bit, kleines Ende zuerst.
 *
 * Schreiben ohne Riss (Seqlock): Uzai setzt den Zähler ungerade, schreibt Maße und Punkte, setzt ihn
 * gerade. Die Bibliothek nimmt ein Bild nur, wenn der Zähler vor und nach dem Kopieren gleich und
 * gerade ist. Alles, was sie liest, prüft sie selbst – die Datei ist für sie fremde Eingabe.
 */
#ifndef UZAI_OVERLAY_H
#define UZAI_OVERLAY_H

#include <stdint.h>
#include <stddef.h>

#define UZOV_MAGIC      0x564F5A55u   /* "UZOV" */
#define UZOV_VERSION    1u
#define UZOV_KOPF       64u
#define UZOV_MAX_BREITE 2048u
#define UZOV_MAX_HOEHE  2400u

typedef struct {
	uint32_t magic;      /* UZOV_MAGIC */
	uint32_t version;    /* UZOV_VERSION */
	uint32_t zaehler;    /* gerade: Bild vollständig; ungerade: Uzai schreibt gerade */
	uint32_t sichtbar;   /* 0 versteckt, 1 zeigen – der einzige Befehl */
	uint32_t breite;     /* Bildpunkte, 1 … UZOV_MAX_BREITE */
	uint32_t hoehe;      /* Bildpunkte, 1 … UZOV_MAX_HOEHE */
	uint32_t frei[10];   /* 0 */
} uzov_kopf;

/* Länge der ganzen Datei zu einem gültigen Kopf (0: Kopf ungültig). */
static inline size_t uzov_laenge(const uzov_kopf *k) {
	if (k == NULL || k->magic != UZOV_MAGIC || k->version != UZOV_VERSION) return 0;
	if (k->breite == 0 || k->hoehe == 0 || k->breite > UZOV_MAX_BREITE || k->hoehe > UZOV_MAX_HOEHE) return 0;
	return (size_t)UZOV_KOPF + (size_t)k->breite * (size_t)k->hoehe * 4u;
}

/* Darf die Bibliothek dieses Bild nehmen? vorhanden: Byte, die wirklich abgebildet sind.
 * 1: gültig, vollständig, passt in die Abbildung. 0: nichts tun. */
static inline int uzov_kopf_pruefen(const uzov_kopf *k, size_t vorhanden) {
	size_t n;
	if (vorhanden < UZOV_KOPF) return 0;
	n = uzov_laenge(k);
	if (n == 0 || n > vorhanden) return 0;
	if (k->zaehler & 1u) return 0;
	if (k->sichtbar > 1u) return 0;
	return 1;
}

#endif
