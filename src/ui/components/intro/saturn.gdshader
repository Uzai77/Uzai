shader_type canvas_item;
// Anmutung Saturn: tiefblauer Nebelraum mit Sternen, ein beringter Planet zieht heran, ein Licht
// wandert über den Ring, hinter dem Rand blitzt die Sonne auf. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

void fragment() {
	vec2 p = ort(UV);
	float nb = fbm(p * 1.4 + vec2(t * 0.05, 0.0));
	vec3 c = mix(vec3(0.005, 0.01, 0.04), vec3(0.06, 0.1, 0.3), nb * nb * 1.4);
	c += vec3(0.12, 0.05, 0.25) * pow(fbm(p * 2.2 - vec2(0.0, t * 0.04) + 4.0), 3.0);
	vec2 g = p * 40.0;
	vec2 id = floor(g);
	float r0 = h21(id);
	c += vec3(0.85, 0.9, 1.0) * step(0.965, r0) * glanz(length(fract(g) - 0.5), 0.08) * (0.5 + 0.5 * sin(t * 4.0 + r0 * 60.0));
	float nah = e_out(t / 1.4);
	float s = mix(0.55, 1.0, nah);
	vec2 at = vec2(0.0, mix(-0.25, 0.14, nah));
	vec2 q = (p - at) / s;
	float pr = 0.3;
	float d = length(q);
	float neig = 0.24;
	vec2 rq = dreh(-0.32) * q;
	float re = length(rq * vec2(1.0, 1.0 / neig));
	// Kanten des Rings in Bildpunkten (re ist gestaucht: Breite aus der Ableitung).
	float rw = max(fwidth(re), 1e-5);
	float ring = sat((re - 0.43) / rw + 0.5) * sat((0.735 - re) / rw + 0.5);
	float rillen = 0.65 + 0.35 * sin(re * 90.0) * sin(re * 23.0);
	float vorn = step(rq.y, 0.0);
	// Hinterer Ring zuerst, dann Planet, dann vorderer Ring.
	vec3 rcol = vec3(0.72, 0.76, 0.85) * rillen;
	float rlicht = glanz(atan(rq.y, rq.x) - mix(-3.2, 3.2, e_io((t - 0.4) / 1.6)), 0.4);
	rcol += vec3(0.5, 0.6, 0.9) * rlicht * 0.6;
	c = mix(c, rcol, ring * (1.0 - vorn) * 0.85 * nah);
	if (d < pr) {
		vec3 n = vec3(q / pr, sqrt(max(1.0 - dot(q, q) / (pr * pr), 0.0)));
		vec3 l = normalize(vec3(-0.6, 0.5, 0.6));
		float dif = max(dot(n, l), 0.0);
		float baender = 0.85 + 0.15 * sin(n.y * 18.0 + n.x * 2.0);
		vec3 pl = vec3(0.45, 0.52, 0.66) * baender * (0.08 + 0.95 * dif);
		pl += vec3(0.3, 0.45, 0.9) * pow(1.0 - n.z, 3.0) * 0.6;
		c = mix(c, pl, kante_bp(d - pr, bildpunkt / s) * nah);
	}
	c += vec3(0.25, 0.4, 0.9) * glanz(d - pr, 0.03) * 0.35 * nah;
	c = mix(c, rcol, ring * vorn * 0.9 * nah);
	// Sonne blitzt am Rand auf.
	vec2 sonne = vec2(0.24, 0.17) * s;
	float fl = buckel(1.05, 1.8, t);
	float sd = length(q - sonne / s * 1.0);
	c += vec3(0.9, 0.95, 1.0) * (glanz(sd, 0.03) + halo(sd, 0.05) * 0.25) * fl;
	c += vec3(0.6, 0.75, 1.0) * strich_bp(q.y - sonne.y / s, 0.0025, bildpunkt / s) * glanz(q.x - sonne.x / s, 0.6) * fl * 0.6;
	c *= 1.0 - 0.3 * ruhe();
	c *= e_out(t / 0.5);
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.5), 1.0);
}
