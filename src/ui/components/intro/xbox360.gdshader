shader_type canvas_item;
// Anmutung Xbox 360: heller, silbrig-weißer Raum, Lichtbänder kreisen um einen weiß-grünen
// Kern, ziehen sich zusammen und lösen sich in einem weichen Aufleuchten. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

void fragment() {
	vec2 p = ort(UV);
	vec2 q0 = p - vec2(0.0, 0.08);
	float r = length(q0);
	vec3 grund = mix(vec3(0.74, 0.77, 0.75), vec3(0.97, 0.975, 0.97), glanz(r, 1.2));
	vec3 c = mix(vec3(0.0), grund, e_expo(t / 0.5));
	vec3 gruen = vec3(0.42, 0.72, 0.1);
	float zug = e_io((t - 1.0) / 0.45);
	float auf = e_out((t - 0.1) / 0.6);
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float ang = fi * 0.63 + t * (0.9 + 0.25 * fi) * (1.0 - 0.6 * zug);
		float neig = 0.18 + 0.12 * fi;
		float rad = mix(0.4 + 0.1 * fi, 0.08, zug) * auf;
		vec2 q = dreh(ang) * q0;
		vec2 ab = vec2(rad, rad * neig) + 0.0001;
		float f = length(q / ab) - 1.0;
		float gr = length(q / (ab * ab)) / max(length(q / ab), 0.0001);
		float d = abs(f) / max(gr, 0.0001);
		float vorn = mix(0.35, 1.0, smoothstep(0.02, -0.02, q.y));
		float band = strich(d, 0.0055) * 0.95 + glanz(d, 0.04) * 0.2;
		c = mix(c, mix(gruen, vec3(0.92, 1.0, 0.85), 0.35 * vorn), sat(band * vorn) * (1.0 - zug * 0.8));
	}
	// Kern und Aufleuchten.
	float flash = buckel(1.3, 1.85, t);
	float kern = e_out((t - 0.2) / 0.9);
	c = mix(c, vec3(0.96, 1.0, 0.92), glanz(r, 0.06 + 0.25 * flash) * kern);
	c = mix(c, gruen, sat(halo(r, 0.05) * 0.25) * kern * (1.0 - flash) * (1.0 - ruhe()));
	c += vec3(0.25, 0.35, 0.1) * flash * glanz(r, 0.9) * 0.4;
	// Danach bleibt eine ruhige, leuchtende Kugel mit feinem Rand.
	float bleib = smoothstep(1.45, 1.95, t);
	c = mix(c, vec3(0.93, 0.98, 0.88), glanz(r, 0.13) * bleib * 0.85);
	c = mix(c, gruen, strich(r - 0.15, 0.0065) * bleib * 0.75);
	c = mix(c, gruen * 1.2, halo(r - 0.15, 0.03) * bleib * 0.12);
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.25), 1.0);
}
