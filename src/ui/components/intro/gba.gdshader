shader_type canvas_item;
// Anmutung Game Boy Advance: aus tiefem Indigo zieht ein Lichtschweif in einem Bogen über den
// Schirm, platzt am Ende weich auf, der Grund wird hell lavendel, kleine Pixel funkeln.
// Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

vec2 weg(float s) {
	return vec2(mix(-aspect - 0.3, 0.35, s), -0.45 + 0.75 * sin(s * PI * 0.62));
}

void fragment() {
	vec2 p = ort(UV);
	float hell = e_io((t - 0.95) / 0.5);
	vec3 tief = mix(vec3(0.05, 0.04, 0.16), vec3(0.16, 0.12, 0.42), glanz(p.y + 0.2, 1.0));
	vec3 licht = mix(vec3(0.82, 0.8, 0.94), vec3(0.97, 0.96, 1.0), glanz(length(p - vec2(0.3, 0.15)), 1.1));
	vec3 c = mix(tief, licht, hell);
	c *= e_out(t / 0.35);
	float s = e_out((t - 0.15) / 0.95);
	vec3 farbe = vec3(0.6, 0.55, 1.0);
	for (int k = 0; k < 28; k++) {
		float fk = float(k);
		float sk = s - fk * 0.012;
		if (sk < 0.0) {
			break;
		}
		vec2 at = weg(sk);
		float d = length(p - at);
		float w = 1.0 - fk / 28.0;
		c += mix(farbe, vec3(1.0), w) * (glanz(d, 0.006 + 0.012 * w) * 0.6 * w + halo(d, 0.01) * 0.02 * w) * (1.0 - hell * 0.45);
	}
	// Funken entlang des Schweifs, kleine Quadrate.
	vec2 g = p * 26.0;
	vec2 id = floor(g);
	float r = h21(id);
	vec2 nah = weg(clamp(s - 0.1 * r, 0.0, 1.0));
	float bei = glanz(length(p - nah), 0.15) * step(0.88, r);
	float qd = kante_bp(max(abs(fract(g.x) - 0.5), abs(fract(g.y) - 0.5)) - 0.22, bildpunkt * 13.0);
	float tw = 0.5 + 0.5 * sin(t * 9.0 + r * 50.0);
	c += vec3(0.85, 0.82, 1.0) * qd * bei * tw * (1.0 - hell * 0.6);
	// Aufplatzen am Ende des Bogens.
	vec2 ende = weg(1.0);
	float pl = buckel(1.0, 1.6, t);
	float d = length(p - ende);
	c += vec3(1.0, 0.98, 1.0) * glanz(d, 0.05 + 0.4 * pl) * pl * 0.8;
	float rw = (t - 1.05) * 1.8;
	c = mix(c, vec3(0.45, 0.4, 0.85), (strich(d - rw, 0.004) * 0.8 + glanz(d - rw, 0.02) * 0.3) * 0.5 * step(0.0, rw) * (1.0 - sat(rw / 1.8)));
	// Danach funkeln kleine Pixel auf hellem Grund.
	float sp = step(0.94, r) * qd * hell * (0.5 + 0.5 * sin(t * 6.0 + r * 80.0)) * (1.0 - ruhe() * 0.5);
	c = mix(c, vec3(0.6, 0.56, 0.95), sp * 0.5);
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.15), 1.0);
}
