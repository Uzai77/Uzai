shader_type canvas_item;
// Anmutung PlayStation 3 und PSP: ein seidenes Band aus feinen Lichtlinien zieht durch einen
// dunklen Raum, ein Lichtfunke läuft daran entlang. variante 0: Silber auf Schwarz (PS3),
// 1: Blau (PSP). Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

float bahn(float x, float fi) {
	float ph = t * 0.85 + fi * 0.8;
	float grund = 0.2 * sin(x * 1.05 + ph) * (0.65 + 0.35 * sin(x * 0.47 - t * 0.35 + fi * 1.7));
	float faecher = (fi - 0.5) * 0.16 * (0.4 + 0.6 * sin(x * 0.8 + t * 0.55 + 1.3));
	return grund + faecher - 0.08;
}

void fragment() {
	vec2 p = ort(UV);
	bool psp = variante > 0.5;
	vec3 tief = psp ? vec3(0.0, 0.02, 0.09) : vec3(0.012, 0.012, 0.016);
	vec3 hoch = psp ? vec3(0.02, 0.1, 0.32) : vec3(0.075, 0.075, 0.085);
	vec3 farbe = psp ? vec3(0.45, 0.7, 1.0) : vec3(0.86, 0.88, 0.93);
	vec3 c = mix(tief, hoch, smoothstep(-1.0, 1.2, p.y) * 0.4 + 0.6 * glanz(p.y + 0.1, 0.8) * 0.6);
	// Das Band baut sich von links nach rechts auf.
	float front = mix(-aspect - 0.6, aspect + 0.6, e_io(t / 1.15));
	float zeigen = smoothstep(front, front - 0.6, p.x);
	float linien = 0.0;
	float lo = 10.0;
	float hi = -10.0;
	for (int i = 0; i < 22; i++) {
		float fi = float(i) / 21.0;
		float y = bahn(p.x, fi);
		lo = min(lo, y);
		hi = max(hi, y);
		float d = abs(p.y - y);
		float hell = 0.35 + 0.65 * pow(sin(PI * fi), 2.0);
		linien += (strich(d, 0.0019) * 0.55 + glanz(d, 0.018) * 0.06) * hell;
	}
	float flaeche = smoothstep(lo - bildpunkt, lo + 0.03, p.y) * smoothstep(hi + bildpunkt, hi - 0.03, p.y);
	float licht = 1.0 - 0.45 * ruhe();
	c += farbe * (linien * 0.75 + flaeche * 0.07) * zeigen * licht;
	// Der Funke: läuft auf der mittleren Linie, zieht eine kurze Spur.
	float sx = mix(-aspect - 0.3, aspect + 0.3, e_io((t - 0.35) / 1.25));
	for (int k = 0; k < 6; k++) {
		float fk = float(k);
		float x = sx - fk * 0.06;
		vec2 at = vec2(x, bahn(x, 0.5));
		float d = length((p - at) * vec2(0.5, 1.0));
		c += mix(farbe, vec3(1.0), 0.6) * (glanz(d, 0.012) * 0.9 + halo(d, 0.02) * 0.12) * (1.0 - fk / 6.0) * buckel(0.3, 1.7, t);
	}
	c *= e_out(t / 0.4);
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.5), 1.0);
}
