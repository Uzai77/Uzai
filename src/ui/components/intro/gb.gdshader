shader_type canvas_item;
// Anmutung Game Boy, Game Boy Color und Game Gear: der Schirm ist ein Punktraster mit vier
// Tönen; drei kleine Pixel-Juwelen fallen in Stufen herab, setzen in der Mitte auf, und in dem
// Moment glänzt der Schirm kurz auf (der „Ping“ ohne Ton). Flüssigkristall mit Nachzieh-Schatten.
// variante 0: Grüntöne (Game Boy), 1: bunt auf hellem Grund (Color), 2: bunt, hinterleuchtet
// (Game Gear). Eigener Entwurf, kein Schriftzug.
#include "res://src/ui/components/intro/intro.gdshaderinc"

// Juwel-Muster: 1 an, sonst 0; ix in Zellen relativ zur Mitte des Musters.
float muster(vec2 id, float y0) {
	vec2 q = id - vec2(0.0, y0);
	float best = 0.0;
	for (int k = -1; k <= 1; k++) {
		vec2 r = q - vec2(float(k) * 8.0, 0.0);
		float m = abs(r.x) + abs(r.y);
		best = max(best, step(m, 2.5 + (k == 0 ? 1.0 : 0.0)) * (k == 0 ? 2.0 : 1.0));
	}
	return best;
}

void fragment() {
	vec2 p = ort(UV);
	float v = variante;
	float n = 18.0;
	vec2 g = p * n;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	vec3 aus = v < 0.5 ? vec3(0.36, 0.42, 0.2) : (v < 1.5 ? vec3(0.62, 0.63, 0.58) : vec3(0.0, 0.0, 0.0));
	vec3 hell = v < 0.5 ? vec3(0.66, 0.74, 0.38) : (v < 1.5 ? vec3(0.92, 0.93, 0.88) : vec3(0.05, 0.06, 0.08));
	vec3 mittel = v < 0.5 ? vec3(0.4, 0.5, 0.24) : vec3(0.55, 0.3, 0.75);
	vec3 dunkel = v < 0.5 ? vec3(0.1, 0.17, 0.1) : vec3(0.85, 0.2, 0.3);
	float an = floor(e_out(t / 0.35) * 4.0) / 4.0;
	vec3 grund = mix(aus, hell, an);
	// Fallen: leicht beschleunigt, in ganzen Zellen, Landung bei 1,0 s.
	float fz = sat(t / 1.0);
	float fall = fz * fz * 0.65 + fz * 0.35;
	float y0 = floor(mix(n + 4.0, 0.0, fall) + 0.5);
	float ping = buckel(1.0, 1.35, t);
	float m = muster(id, y0);
	// Nachziehen der Flüssigkristalle: die letzten Lagen blass.
	float spur = max(muster(id, y0 + 1.0), muster(id, y0 + 2.0) * 0.5) * (1.0 - step(1.0, t));
	float schatten = muster(floor(g - vec2(0.18, -0.18)), y0);
	vec3 pcol = m > 1.5 ? dunkel : mittel;
	if (v > 0.5) {
		float farbe = mod(id.x + 30.0 + floor(t * 8.0) * step(1.0, t), 6.0);
		pcol = mix(pcol, 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + farbe), 0.6 * step(0.5, m));
	}
	float zelle = kante_bp(max(abs(f.x), abs(f.y)) - 0.445, bildpunkt * n);
	vec3 c = grund;
	c = mix(c, c * 0.82, sat(schatten) * 0.35 * an);
	c = mix(c, mix(grund, mittel, 0.5), spur * zelle * 0.5);
	c = mix(c, pcol, step(0.5, m) * zelle);
	// Raster der Bildpunkte, zart.
	c *= mix(1.0, 0.93, 1.0 - zelle);
	// Ping: Glanz zieht diagonal über den Schirm, zwei Funken an den Rändern.
	float gl = glanz(p.x * 0.5 - p.y - mix(-1.6, 1.6, sat((t - 1.0) / 0.5)), 0.12) * ping;
	c += vec3(0.25, 0.28, 0.18) * gl * (v > 1.5 ? 1.6 : 0.6);
	for (int k = 0; k < 2; k++) {
		vec2 at = vec2((k == 0 ? -1.0 : 1.0) * 12.5 / n, 0.5 / n + 2.0 / n);
		vec2 d = abs(p - at);
		float stern = glanz(d.x, 0.006) * glanz(d.y, 0.07) + glanz(d.y, 0.006) * glanz(d.x, 0.07);
		c += (v > 1.5 ? vec3(1.0, 0.95, 0.8) : vec3(0.95, 1.0, 0.8)) * stern * ping;
	}
	if (v > 1.5) {
		c += pcol * step(0.5, m) * 0.25 + vec3(0.02, 0.03, 0.05) * glanz(length(p), 1.0);
	}
	c *= 1.0 - 0.25 * ruhe();
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.45), 1.0);
}
