shader_type canvas_item;
// Anmutung Wii und Wii U: helles, weiches Weiß, eine glänzende runde Form schwebt auf, ein
// Glanzstreif zieht darüber, feine Ringe und Bläschen. variante 0: Wii (hellblau),
// 1: Wii U (tieferes Blau, etwas grauer Grund). Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

// Glänzende Kuppel aus einer abgerundeten Fläche: Deckkraft, Helligkeit, Glanz.
vec3 kuppel(vec2 q, vec2 b, float r, float sweep, float bp) {
	float d = sd_rbox(q, b, r);
	float innen = kante_bp(d, bp);
	float rand = sat(-d / r);
	float hoehe = sqrt(max(1.0 - (1.0 - rand) * (1.0 - rand), 0.0));
	float oben = glanz(q.y - b.y * 0.55, b.y * 0.32) * smoothstep(b.x, b.x * 0.6, abs(q.x)) * 0.5;
	float streif = glanz(q.x + q.y * 0.6 - sweep, 0.05) * hoehe;
	return vec3(innen, 0.86 + 0.14 * hoehe, oben + streif * 0.8);
}

void fragment() {
	vec2 p = ort(UV);
	bool u = variante > 0.5;
	vec3 blau = u ? vec3(0.08, 0.55, 0.78) : vec3(0.22, 0.72, 0.93);
	vec3 grund_o = u ? vec3(0.95, 0.955, 0.965) : vec3(0.995, 0.997, 1.0);
	vec3 grund_u = u ? vec3(0.8, 0.82, 0.85) : vec3(0.88, 0.9, 0.93);
	float auf = e_expo(t / 0.6);
	vec3 c = mix(grund_u, grund_o, smoothstep(-1.1, 0.9, p.y));
	c = mix(vec3(0.0), c, auf);
	// Feine blaue Ringe laufen von der Mitte aus.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float rr = (t - 0.35 - fi * 0.22) * 0.9;
		float d = abs(length(p * vec2(0.75, 1.0)) - rr);
		c = mix(c, blau, strich(d, 0.003) * 0.45 * (1.0 - sat(rr / 1.8)) * step(0.0, rr));
	}
	// Bläschen in verschiedenen Tiefen.
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		vec2 at = vec2((h11(fi) - 0.5) * 2.0 * aspect, -1.3 + fract(h11(fi + 4.0) + t * (0.06 + 0.05 * h11(fi + 9.0))) * 2.6);
		float rad = 0.03 + 0.07 * h11(fi + 2.0);
		float d = length(p - at) - rad;
		// Nahe Bläschen scharf, ferne weich (Tiefe): die Kante nie weicher als nötig.
		float weich = 0.02 * h11(fi + 6.0);
		float k = sat(0.5 - d / (bildpunkt + 2.0 * weich)) * smoothstep(0.2, 0.8, t);
		c = mix(c, mix(c, vec3(1.0), 0.6), k * 0.6);
		c = mix(c, blau, glanz(d, weich + 0.003) * 0.35 * smoothstep(0.2, 0.8, t));
	}
	// Die Form: schwebt auf, wächst weich, setzt sich.
	float s = e_out((t - 0.25) / 0.85);
	vec2 q = (p - vec2(0.0, 0.1 - 0.12 * (1.0 - s))) / mix(0.75, 1.0, s);
	vec2 b = vec2(0.5, 0.2);
	float sweep = mix(-1.0, 1.0, e_io((t - 0.8) / 0.8));
	float schatten = glanz(max(sd_rbox(q - vec2(0.0, -0.05), b, 0.2), 0.0), 0.13) * 0.1 * s;
	c *= 1.0 - schatten;
	float bp = bildpunkt / mix(0.75, 1.0, s);
	vec3 k = kuppel(q, b, 0.2, sweep, bp);
	vec3 koerper = vec3(k.y) * vec3(0.985, 0.99, 1.0) + vec3(k.z);
	float randlinie = strich_bp(sd_rbox(q, b, 0.2), 0.0035, bp);
	c = mix(c, koerper, k.x * s);
	c = mix(c, blau, randlinie * s * 0.85);
	c *= mix(1.0, 0.94, ruhe() * glanz(length(p), 0.6));
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.12), 1.0);
}
