// Muster für Stoffe und Tapeten (gestalt.gd, MUSTER): p in Metern auf der Fläche, Ergebnis 0..1
// = Anteil der Musterfarbe. Kanten weich über fwidth (kein Flimmern aus der Ferne).
// 1 Streifen, 2 Nadelstreifen, 3 Karo, 4 Punkte, 5 Rauten, 6 Fischgrät, 7 Zickzack, 8 Ornament.

float uz_band(float x, float breite) {
	float d = abs(fract(x) - 0.5) - breite * 0.5;
	float w = max(fwidth(x) * 1.2, 0.0001);
	return 1.0 - smoothstep(-w, w, d);
}

float uz_kreis(vec2 q, float r) {
	float d = length(q) - r;
	float w = max(fwidth(d) * 1.2, 0.0001);
	return 1.0 - smoothstep(-w, w, d);
}

float uz_muster(vec2 p, int art, float mass) {
	p /= max(mass, 0.05);
	if (art == 1) {
		return uz_band(p.x / 0.14, 0.42);
	} else if (art == 2) {
		return uz_band(p.x / 0.05, 0.1);
	} else if (art == 3) {
		float bx = uz_band(p.x / 0.12, 0.38);
		float by = uz_band(p.y / 0.12, 0.38);
		return clamp(0.45 * bx + 0.45 * by + 0.1 * bx * by, 0.0, 1.0);
	} else if (art == 4) {
		vec2 g = p / 0.06;
		g.x += 0.5 * mod(floor(g.y), 2.0);
		return uz_kreis((fract(g) - 0.5) * 0.06, 0.011);
	} else if (art == 5) {
		return max(uz_band((p.x + p.y) / 0.11, 0.1), uz_band((p.x - p.y) / 0.11, 0.1));
	} else if (art == 6) {
		float spalte = floor(p.x / 0.07);
		float s = mod(spalte, 2.0) * 2.0 - 1.0;
		return uz_band((p.y + s * p.x) / 0.045, 0.5) * uz_band(p.x / 0.07, 0.9);
	} else if (art == 7) {
		float t = abs(fract(p.x / 0.09) - 0.5) * 0.09;
		return uz_band((p.y + t) / 0.07, 0.34);
	} else if (art == 8) {
		vec2 g = p / 0.18;
		vec2 id = floor(g);
		vec2 q = (fract(g) - 0.5) * 0.18;
		float a = atan(q.y, q.x);
		float blume = uz_kreis(q, 0.028 + 0.014 * cos(a * 5.0));
		float mitte = uz_kreis(q, 0.009);
		vec2 q2 = (fract(g + 0.5) - 0.5) * 0.18;
		float punkt = uz_kreis(q2, 0.006);
		float ranke = uz_band((p.x + 0.4 * sin(p.y * 35.0 + id.x)) / 0.18, 0.025) * 0.6;
		return clamp(max(blume - mitte * 0.7, max(punkt, ranke)), 0.0, 1.0);
	}
	return 0.0;
}
