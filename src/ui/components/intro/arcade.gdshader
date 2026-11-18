shader_type canvas_item;
// Anmutung Spielhalle: Leuchtlinien wie auf einem Vektor-Monitor – Strahlen schießen aus der
// Mitte, Rahmen fliegen als Tunnel nach außen, ein Sechseck pulst. Röhre mit Zeilen. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

// Neonröhre: scharfer Kern (in Bildpunkten geglättet), weicher Schein.
float strahl(float d, float k) { return strich(d, 0.0032) * 1.1 + glanz(d, 0.006) * 0.3 + glanz(d, 0.024) * 0.4 * k; }

void fragment() {
	vec2 uv = UV - 0.5;
	uv *= 1.0 + 0.05 * dot(uv, uv) * 4.0;
	vec2 p = ort(uv + 0.5);
	vec3 c = vec3(0.01, 0.0, 0.02);
	vec3 neon = vec3(1.0, 0.25, 0.45);
	vec3 cyan = vec3(0.25, 0.9, 1.0);
	vec2 at = vec2(0.0, 0.05);
	vec2 q = p - at;
	float r = length(q);
	float a = atan(q.y, q.x);
	// Strahlen.
	float g = e_out(t / 0.4);
	float weg = 1.0 - sat((t - 0.45) / 0.45);
	float sek = TAU / 16.0;
	float aa = mod(a + 0.1, sek) - sek * 0.5;
	float dr = abs(sin(aa)) * r;
	float lauf = step(0.12 * g, r) * step(r, 0.12 + 2.2 * g);
	c += cyan * strahl(dr, 1.0) * lauf * weg;
	// Tunnel aus Rahmen.
	float tun = sat((t - 0.25) / 0.25);
	for (int i = 0; i < 5; i++) {
		float f = fract(t * 0.9 + float(i) / 5.0);
		float s = 0.06 * pow(18.0, f);
		float d = abs(sd_rbox(q, vec2(s * 1.6, s), 0.0));
		c += mix(neon, cyan, f) * strahl(d, 1.0) * tun * (1.0 - f) * (1.0 - 0.6 * ruhe());
	}
	// Sechseck in der Mitte, pulst einmal.
	float pz = e_out((t - 0.1) / 0.3) * (1.0 + 0.12 * buckel(0.6, 0.95, t));
	float sk = TAU / 6.0;
	float ah = mod(a + PI / 6.0, sk) - sk * 0.5;
	float hx = r * cos(ah) - 0.12 * pz;
	c += vec3(1.0, 0.8, 0.4) * strahl(abs(hx), 1.0) * step(0.001, pz);
	c += vec3(1.0) * glanz(r, 0.012 * pz);
	// Zeilen und Röhrenrand.
	c *= 0.78 + 0.22 * cos(FRAGCOORD.y * PI * 0.5);
	if (abs(uv.x) > 0.5 || abs(uv.y) > 0.5) {
		c = vec3(0.0);
	}
	c *= e_out(t / 0.25);
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.6), 1.0);
}
