shader_type canvas_item;
// Anmutung Switch: zwei leuchtende Seitenteile (Blau links, Rot rechts) gleiten herein und
// rasten mit einem Klick in der Mitte ein – ein Lichtschlag, ein Ring, dann Ruhe. Eigener
// Entwurf, kein Zeichen.
#include "res://src/ui/components/intro/intro.gdshaderinc"

vec3 teil(vec2 q, vec2 b, vec3 farbe, float seite) {
	float d = sd_rbox(q, b, 0.13);
	float innen = kante(d);
	float rand = sat(-d / 0.13);
	float gl = glanz(q.x + seite * b.x * 0.45, b.x * 0.22) * 0.35 * rand;
	vec3 col = farbe * (0.75 + 0.35 * smoothstep(-b.y, b.y, q.y)) + vec3(gl);
	return col * innen;
}

void fragment() {
	vec2 p = ort(UV);
	vec3 c = mix(vec3(0.02, 0.02, 0.025), vec3(0.075, 0.075, 0.085), glanz(p.y, 1.2));
	c *= e_out(t / 0.35);
	float rein = e_in(t / 0.72);
	float klick = 0.72;
	float rueck = 0.025 * buckel(klick, klick + 0.18, t);
	float aus = 0.12 * e_io((t - 1.35) / 0.7);
	vec2 b = vec2(0.15, 0.42);
	float x = mix(aspect + 0.4, b.x + 0.012, rein) + rueck + aus;
	vec3 blau = vec3(0.0, 0.66, 0.85);
	vec3 rot = vec3(1.0, 0.27, 0.33);
	vec2 ql = p - vec2(-x, 0.0);
	vec2 qr = p - vec2(x, 0.0);
	// Schatten und Schein der Teile.
	c += blau * halo(max(sd_rbox(ql, b, 0.13), 0.0), 0.05) * 0.1;
	c += rot * halo(max(sd_rbox(qr, b, 0.13), 0.0), 0.05) * 0.1;
	float ml = kante(sd_rbox(ql, b, 0.13));
	float mr = kante(sd_rbox(qr, b, 0.13));
	c = mix(c, teil(ql, b, blau, -1.0), ml);
	c = mix(c, teil(qr, b, rot, 1.0), mr);
	// Klick: Lichtschlag in der Fuge, Ring, kurzes Aufhellen.
	float s = t - klick;
	if (s > 0.0) {
		float schlag = exp(-s * 7.0);
		c += vec3(1.0) * glanz(p.x, 0.008 + aus * 0.5 + 0.02 * schlag) * smoothstep(b.y + 0.05, b.y - 0.1, abs(p.y)) * (0.6 * schlag + 0.5 * aus * 6.0);
		float rr = s * 2.3;
		float rd = length(p * vec2(0.8, 1.0)) - rr;
		c += vec3(0.95) * (strich(rd, 0.0028) * 0.75 + glanz(rd, 0.012 + s * 0.03) * 0.35) * exp(-s * 2.5);
		c += vec3(0.15) * schlag * glanz(length(p), 1.2);
	}
	c *= 1.0 - 0.3 * ruhe() * (1.0 - smoothstep(0.3, 0.6, abs(p.y)));
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.45), 1.0);
}
