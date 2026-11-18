shader_type canvas_item;
// Anmutung 8 Bit (NES, Master System, Atari 2600): ein gewölbter Röhrenschirm, große
// Bildpunkte mit Nachglühen, eine Raute aus wenigen Farben breitet sich in 15 Bildern je Sekunde
// aus, die Farben laufen durch (Paletten-Wechsel) und setzen sich zu einem Juwel.
// variante 0: Rot/Weiß/Grau (NES), 1: Blau/Rot (Master System), 2: Orange/Braun (Atari).
// Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

vec3 palette(float i) {
	float v = variante;
	vec3 a = v < 0.5 ? vec3(0.86, 0.16, 0.12) : (v < 1.5 ? vec3(0.15, 0.4, 0.95) : vec3(0.92, 0.52, 0.16));
	vec3 b = v < 0.5 ? vec3(0.98, 0.96, 0.92) : (v < 1.5 ? vec3(0.95, 0.95, 0.95) : vec3(0.92, 0.82, 0.55));
	vec3 cc = v < 0.5 ? vec3(0.55, 0.55, 0.6) : (v < 1.5 ? vec3(0.85, 0.15, 0.2) : vec3(0.52, 0.3, 0.14));
	vec3 d = v < 0.5 ? vec3(0.16, 0.16, 0.2) : (v < 1.5 ? vec3(0.1, 0.12, 0.3) : vec3(0.24, 0.14, 0.08));
	float k = mod(i, 4.0);
	return k < 0.5 ? a : (k < 1.5 ? b : (k < 2.5 ? cc : d));
}

// Farbe einer Zelle (Rasterkoordinate) zur gestuften Zeit ts; a = Deckkraft.
vec4 zelle(vec2 id, float ts) {
	float m = abs(id.x) + abs(id.y);
	float front = ts * 34.0;
	if (m > front) {
		return vec4(0.0);
	}
	float setzen = sat((ts - 1.0) / 0.35);
	float juwel = 7.0;
	float aussen = step(juwel + 0.5, m);
	float welle = floor((m - ts * 14.0) / 2.0);
	vec3 col = palette(welle);
	float a = 1.0 - aussen * floor(setzen * 4.0) / 4.0;
	if (setzen > 0.0 && m <= juwel + 0.5) {
		// Juwel: Rand in Farbe a, innen hell, Mitte in Farbe c; blinkt kurz beim Setzen.
		float ring = step(juwel - 0.5, m);
		float blink = mod(floor(ts * 15.0), 4.0) < 2.0 && ts < 1.45 ? 1.0 : 0.0;
		col = ring > 0.5 ? palette(0.0) : (m < 2.5 ? palette(2.0 + blink) : palette(1.0));
		if (m > 3.5 && m < 4.5) {
			col = palette(3.0);
		}
	}
	return vec4(col, a * (m <= juwel + 0.5 || setzen < 1.0 ? 1.0 : 0.0));
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv *= 1.0 + 0.06 * dot(uv, uv) * 4.0;
	vec2 p = ort(uv + 0.5);
	bool aussen = abs(uv.x) > 0.5 || abs(uv.y) > 0.5;
	float ts = floor(t * 15.0) / 15.0;
	float n = 13.5;
	vec2 g = p * n;
	vec2 id = floor(g + 0.5);
	vec2 f = g - id;
	vec3 c = vec3(0.012, 0.012, 0.018);
	// Eigene Zelle scharf, Nachbarn als Glühen (Röhre).
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec4 z = zelle(id + o, ts);
			if (z.a <= 0.0) {
				continue;
			}
			vec2 d = f - o;
			float kasten = sd_rbox(d, vec2(0.38), 0.08);
			float voll = kante_bp(kasten, bildpunkt * n);
			c += z.rgb * z.a * (voll * 0.85 + glanz(max(kasten, 0.0), 0.22) * 0.22);
		}
	}
	// Zeilen und Röhrenrand.
	c *= 0.84 + 0.16 * cos(FRAGCOORD.y * PI * 0.5);
	c *= 1.0 - 0.3 * ruhe();
	c *= floor(e_out(t / 0.3) * 6.0) / 6.0;
	if (aussen) {
		c = vec3(0.0);
	}
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.7), 1.0);
}
