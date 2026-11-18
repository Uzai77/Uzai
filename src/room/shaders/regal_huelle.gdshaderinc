// Gemeinsamer Kern der Spielhülle (Regal im Hauptmenü: regal_huelle.gdshader; Spieleregal im Zimmer:
// regal_huelle_mm.gdshader als MultiMesh): Felder der echten Aufmachung auf dem Rücken (Regal.ruecken_aufbau),
// feine Kante unter dem Kopf, Kunststoff mit Schimmer oben und unten. Kunststoffhülle (art 0): Einleger
// unter der Folie bis über die runden Kanten, durchscheinender Kunststoff (klar: DS, 3DS, PS3) mit
// weichem Schein. CD-Hülle (art 1): klarer Kunststoff über der Schale (schale: PS1 schwarz), am Rücken
// vorn die Kante des Deckels mit den Scharnierzapfen oben und unten, hinten die Schale. Karton (art 2):
// rundum bedruckt, matt, mit Fasern. Die Vorderseite liegt als eigene Fläche darüber (huelle_vorn.gdshader).
// Ein Ort für das Aussehen – beide Regale zeigen dieselbe Hülle. Braucht rauschen.gdshaderinc davor.

uniform vec3 plastik : source_color = vec3(0.07, 0.07, 0.08);
uniform vec3 schale : source_color = vec3(0.04, 0.04, 0.045);
uniform bool klar = false;
uniform float band_hoehe = 0.12;      // Unterkante des Kopfs von oben (für die Kante)
uniform int felder = 0;
uniform vec4 feld_y[6];                // x: unten, y: oben (0 unten … 1 oben)
uniform vec3 feld_c[6];                // linear
uniform vec3 schimmer : source_color = vec3(0.07, 0.07, 0.08);
uniform vec3 halb = vec3(0.007, 0.095, 0.0675);
uniform int art = 0;
uniform float kante_staerke = 0.18;
uniform float folie = 0.4;

// Farbe und Oberfläche an einer Stelle der Hülle (op: Punkt, on: Normale im Raum der Hülle).
vec3 uz_huelle(vec3 grund, vec3 op, vec3 on, float gl, out float rau, out float spec, out float cc, out float ccr) {
	float ty = (op.y + halb.y) / (2.0 * halb.y);
	float tx = (op.x + halb.x) / (2.0 * halb.x);
	float tz = (op.z + halb.z) / (2.0 * halb.z);
	vec3 c = plastik;
	rau = art == 1 ? 0.06 : (art == 2 ? 0.66 : (klar ? 0.18 : 0.3));
	spec = art == 2 ? 0.25 : 0.5;
	if (on.z > 0.55) {
		// Rücken: Titelfeld, darüber die Felder der Aufmachung, unter dem Kopf eine feine Kante.
		vec3 r = grund;
		for (int i = 0; i < 6; i++) {
			if (i >= felder) {
				break;
			}
			float m = smoothstep(feld_y[i].x - 0.0015, feld_y[i].x, ty) * (1.0 - smoothstep(feld_y[i].y, feld_y[i].y + 0.0015, ty));
			r = mix(r, feld_c[i], m);
		}
		r *= mix(0.92, 1.03, smoothstep(0.0, 1.0, ty));
		float b = 1.0 - band_hoehe;
		float kante = smoothstep(b - 0.008, b - 0.004, ty) * (1.0 - smoothstep(b - 0.002, b, ty));
		c = mix(r, mix(r, vec3(1.0), kante_staerke), kante);
		if (art == 1) {
			// CD-Hülle: hinten die Schale, vorn die klare Kante des Deckels mit den Zapfen des Scharniers.
			float deckel = smoothstep(0.80, 0.83, tx);
			float hinten = 1.0 - smoothstep(0.1, 0.13, tx);
			vec3 klarc = mix(c, plastik, 0.3) * 0.85 + vec3(0.05);
			c = mix(c, mix(schale, plastik, 0.1), hinten);
			float zapfen = deckel * (1.0 - smoothstep(0.025, 0.035, min(ty, 1.0 - ty)));
			c = mix(c, klarc, deckel);
			c = mix(c, plastik * 0.95 + vec3(0.04), zapfen);
			rau = mix(0.12, 0.04, deckel);
		} else {
			// Runde Kanten links und rechts: der Kunststoff biegt weg (Karton kaum).
			float seite = 1.0 - smoothstep(0.0, 0.16, min(tx, 1.0 - tx));
			c *= 1.0 - seite * (art == 2 ? 0.06 : 0.26);
			rau = art == 2 ? 0.6 : mix(0.3, 0.14, folie);
		}
		c += c * gl * 0.12;
	} else if (abs(on.y) > 0.55) {
		if (art == 1) {
			// Oben und unten: klarer Kunststoff über der Schale, vorn der Deckel heller.
			c = mix(schale, plastik, mix(0.22, 0.55, smoothstep(0.75, 0.85, tx)));
		} else if (art == 2) {
			c = mix(grund, plastik, 0.25) * 0.9;
		} else {
			// Der Kunststoff schimmert in seiner Farbe (PS2 dunkelblau), zur Mitte hin; durchscheinender
			// Kunststoff lässt den Einleger an der Kante ahnen.
			float mitte = 1.0 - smoothstep(0.1, 0.5, abs(tx - 0.5));
			c = mix(plastik, schimmer, 0.35 + 0.4 * mitte);
			if (klar) {
				c = mix(c, grund, 0.18 * smoothstep(0.85, 1.0, tz));
			}
		}
	} else if (art == 2) {
		c = mix(grund, plastik, 0.25) * 0.9;
	} else if (on.x < -0.55) {
		// Rückseite: CD-Hülle mit der Schale, Kunststoffhülle mit dem Einleger unter der Folie.
		c = art == 1 ? mix(schale, plastik, 0.12) : mix(plastik, grund * 0.7, 0.55);
	}
	if (art == 2) {
		float f = uz_noise3(op * vec3(900.0, 2600.0, 900.0));
		c *= 0.94 + 0.08 * f;
	}
	cc = art == 2 ? 0.0 : (on.z > 0.55 ? mix(0.3, 0.75, folie) : (art == 1 ? 0.8 : 0.3));
	ccr = art == 1 ? 0.03 : mix(0.2, 0.06, folie);
	return c;
}
