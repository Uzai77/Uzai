shader_type canvas_item;
// Anmutung PlayStation 2: blauschwarzer Raum, schwebende Lichtteilchen, gläserne Säulen wachsen
// aus einem spiegelnden Boden, die Kamera gleitet langsam in die Tiefe. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

float teilchen(vec2 p, float dichte, float tempo, float seed) {
	vec2 g = p * dichte + vec2(seed * 7.0, -t * tempo);
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	vec2 o = h22(id + seed) - 0.5;
	float r = h21(id + seed * 1.37);
	float d = length(f - o * 0.6);
	float funkeln = 0.55 + 0.45 * sin(t * (2.0 + r * 5.0) + r * 40.0);
	return step(0.62, r) * glanz(d, 0.035 + 0.05 * r) * funkeln;
}

void fragment() {
	vec2 p = ort(UV);
	float an = e_out(t / 0.7);
	float ru = ruhe();
	vec2 q = vec2(p.x, p.y - 0.16);
	// Raum: oben fast schwarz, zum Horizont tiefes Blau.
	vec3 c = mix(vec3(0.004, 0.008, 0.03), vec3(0.02, 0.05, 0.17), exp(-abs(q.y) * 2.6));
	// Ferne Lichtquelle am Horizont, wird heller.
	float quelle = halo(length(q * vec2(0.55, 1.4)), 0.08) * (0.25 + 0.6 * e_io((t - 0.3) / 1.4));
	c += vec3(0.12, 0.28, 0.85) * quelle * 0.55;
	float camh = 0.55 + 0.25 * (1.0 - e_out(t / 2.4));
	float fahrt = t * 0.5;
	float basis = floor(fahrt);
	float fr = fract(fahrt);
	// Boden: feines Raster, das auf uns zuläuft, im Nebel.
	if (q.y < 0.0) {
		float zf = camh / -q.y;
		vec2 w = vec2(q.x * zf, zf + fahrt * 0.75);
		vec2 l = abs(fract(w * 1.6) - 0.5);
		float linie = strich_bp(min(l.x, l.y), 0.0055 * zf, bildpunkt * zf * 1.6) + 0.25 * glanz(min(l.x, l.y), 0.012 * zf);
		c += vec3(0.08, 0.2, 0.6) * linie * exp(-zf * 0.28) * 0.3;
	}
	vec3 acc = vec3(0.0);
	float tr = 1.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float z = 0.75 + (fi + 1.0 - fr) * 0.95;
		float lid = fi + basis;
		float sp = 1.25;
		float wx = q.x * z + h11(lid) * sp;
		float k = floor(wx / sp + 0.5);
		float lx = wx - k * sp;
		float r = h21(vec2(k, lid));
		if (r < 0.4) {
			continue;
		}
		float wy = q.y * z + camh;
		float yy = abs(wy);
		float spiegel = wy < 0.0 ? 0.22 : 1.0;
		float hw = 0.17 + 0.1 * h21(vec2(lid, k + 7.0));
		float delay = 0.05 + h21(vec2(k + 3.1, lid)) * 0.75;
		float hoehe = (0.35 + 1.7 * pow(h21(vec2(k, lid + 9.0)), 1.3)) * e_out((t - delay) / 1.0);
		// Ein Bildpunkt in Weltmaßen dieser Tiefe: Kanten genau einen Bildpunkt weich.
		float ex = bildpunkt * z * 0.5;
		float dx = abs(lx);
		float m = smoothstep(hw + ex, hw - ex, dx) * smoothstep(hoehe + ex, hoehe - ex, yy) * step(0.002, hoehe);
		if (m <= 0.001) {
			continue;
		}
		float nebel = exp(-z * 0.3);
		float nah = smoothstep(0.75, 1.4, z);
		float saum = strich_bp(dx - hw, 0.0022 * z, ex * 2.0) + 0.35 * glanz(dx - hw, 0.006 * z);
		float deckel = strich_bp(yy - hoehe, 0.0026 * z, ex * 2.0) + 0.35 * glanz(yy - hoehe, 0.007 * z);
		float streif = glanz(lx + hw * 0.4, hw * 0.13) + 0.5 * glanz(lx - hw * 0.55, hw * 0.06);
		float innen = 0.12 + 0.32 * exp(-yy * 1.1) + 0.25 * pow(dx / hw, 4.0) + 0.08 * deckel;
		vec3 glas = vec3(0.07, 0.18, 0.7) * innen + vec3(0.3, 0.55, 1.0) * (saum * 0.85 + streif * 0.22)
				+ vec3(0.75, 0.88, 1.0) * deckel;
		float licht = nebel * nah * spiegel * (1.0 - 0.35 * ru);
		acc += tr * glas * licht * m;
		tr *= 1.0 - 0.3 * m * nah * spiegel;
	}
	c = c * tr + acc;
	// Lichtteilchen in drei Tiefen, die nahen größer und schneller.
	float pt = teilchen(p, 6.0, 0.25, 1.0) * 0.45 + teilchen(p, 11.0, 0.4, 2.0) * 0.3 + teilchen(p, 3.2, 0.15, 3.0) * 0.8;
	c += vec3(0.45, 0.65, 1.0) * pt * smoothstep(0.1, 0.9, t) * (1.0 - 0.4 * ru);
	c *= an;
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.55), 1.0);
}
