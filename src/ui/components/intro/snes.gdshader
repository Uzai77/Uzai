shader_type canvas_item;
// Anmutung 16 Bit (Super Nintendo, PC Engine): grobe Bildpunkte, ein gestufter Abendhimmel und
// ein gekachelter Boden, der sich in Perspektive dreht und heranzoomt („Mode 7“-Gefühl), dann
// ein heller Lichtstreif am Horizont. variante 0: Lavendel und Grau (SNES), 1: Weiß und Orange
// (PC Engine). Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

float bayer(vec2 px) {
	vec2 m = mod(floor(px), 2.0);
	return (m.x * 2.0 + m.y * 3.0 - 4.0 * m.x * m.y) / 4.0;
}

void fragment() {
	vec2 pix = vec2(floor(200.0 * aspect), 200.0);
	vec2 cell = floor(UV * pix);
	vec2 p = ort((cell + 0.5) / pix);
	bool pce = variante > 0.5;
	vec3 sky_o = pce ? vec3(0.1, 0.05, 0.03) : vec3(0.1, 0.07, 0.24);
	vec3 sky_u = pce ? vec3(0.98, 0.62, 0.3) : vec3(0.8, 0.62, 0.86);
	vec3 kach_a = pce ? vec3(0.92, 0.9, 0.84) : vec3(0.58, 0.56, 0.78);
	vec3 kach_b = pce ? vec3(0.82, 0.38, 0.12) : vec3(0.42, 0.4, 0.6);
	vec3 linie = pce ? vec3(1.0, 0.85, 0.6) : vec3(0.85, 0.82, 0.95);
	float hor = 0.06 + 0.16 * (1.0 - e_out(t / 1.3));
	vec3 c;
	if (p.y > hor) {
		// Himmel in gestuften Bändern mit Raster dazwischen, wie mit wenigen Farben.
		float v = sat((p.y - hor) / (1.0 - hor));
		float stufen = 9.0;
		float s = floor(v * stufen + bayer(cell) * 0.999) / stufen;
		c = mix(sky_u, sky_o, pow(s, 0.8));
		float sonne = length((p - vec2(0.55, hor + 0.12)) * vec2(1.0, 1.0));
		c = mix(c, mix(linie, vec3(1.0), 0.4), step(sonne, 0.13 + 0.02 * floor(sin(t * 6.0) + 1.0)) * 0.85);
	} else {
		float zf = (0.35 + 0.45 * (1.0 - e_io(t / 1.6))) / max(hor - p.y, 0.002);
		float ang = 0.9 * (1.0 - e_out(t / 1.7)) + 0.12 * t;
		vec2 w = dreh(ang) * vec2(p.x * zf, zf) + vec2(0.0, t * 3.0);
		vec2 f = fract(w * 0.5);
		float schach = step(0.5, f.x) == step(0.5, f.y) ? 1.0 : 0.0;
		c = mix(kach_b, kach_a, schach);
		vec2 l = abs(fract(w) - 0.5);
		c = mix(c, linie, step(0.44, max(l.x, l.y)) * 0.6);
		float fern = sat(zf / 18.0);
		c = mix(c, sky_u, floor(fern * 5.0) / 5.0 * 0.85);
	}
	// Lichtstreif am Horizont, dann ein kurzes Aufhellen.
	float blitz = buckel(1.0, 1.5, t);
	float streif = step(abs(p.y - hor), 0.012 + 0.05 * blitz) * step(abs(p.x), aspect * e_out((t - 0.95) / 0.3));
	c = mix(c, vec3(1.0), streif * 0.9);
	c = mix(c, vec3(1.0), blitz * 0.25);
	c *= 1.0 - 0.35 * ruhe();
	c = floor(c * 31.0 + 0.5) / 31.0;
	c *= floor(e_out(t / 0.5) * 8.0) / 8.0;
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.4), 1.0);
}
