shader_type canvas_item;
// Anmutung Xbox: grünes, organisches Leuchten – Adern aus Licht fließen in tiefem Schwarzgrün,
// wachsen aus der Mitte, ein Kern pulst einmal kräftig. Eigener Entwurf, kein Zeichen.
#include "res://src/ui/components/intro/intro.gdshaderinc"

void fragment() {
	vec2 p = ort(UV);
	float r = length(p);
	vec2 q = p * 1.5;
	vec2 w = vec2(fbm(q + vec2(0.0, t * 0.22)), fbm(q + vec2(5.2, 1.3) - t * 0.18));
	q += (w - 0.5) * 1.8 - normalize(p + 0.0001) * t * 0.15;
	float n = fbm(q * 1.3 + vec2(t * 0.08, 0.0));
	float ader = pow(1.0 - abs(2.0 * n - 1.0), 9.0);
	float front = 2.6 * e_out(t / 1.3);
	float wachs = smoothstep(front, front - 0.6, r);
	vec3 c = vec3(0.0, 0.018, 0.004) + vec3(0.0, 0.07, 0.015) * n * wachs;
	float ru = ruhe();
	c += vec3(0.25, 0.95, 0.15) * ader * wachs * (0.9 - 0.45 * ru) * exp(-r * 0.6);
	// Kern: wächst, pulst bei 1,1 s, bleibt als warmes Glimmen.
	float puls = buckel(1.0, 1.55, t);
	float kern = e_out((t - 0.2) / 0.8);
	c += vec3(0.35, 1.0, 0.2) * glanz(r, 0.05 + 0.04 * puls) * kern * (0.7 + 1.2 * puls);
	c += vec3(0.1, 0.45, 0.06) * halo(r, 0.08 + 0.12 * puls) * kern * (0.4 + 0.9 * puls) * (1.0 - 0.4 * ru);
	// Druckwelle des Pulses durch die Adern.
	float rw = (t - 1.08) * 2.2;
	c += vec3(0.3, 1.0, 0.2) * glanz(r - rw, 0.08) * ader * 1.6 * step(0.0, rw) * (1.0 - sat(rw / 2.0));
	c *= e_out(t / 0.35);
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.6), 1.0);
}
