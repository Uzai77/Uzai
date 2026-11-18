shader_type canvas_item;
// Anmutung Mega Drive: schwarz, scharf, schnell. Chrom- und Blaustreifen schießen quer über den
// Schirm, laufen zu einem Chromband in der Mitte zusammen, ein Glanz zieht darüber. Grobe
// Bildpunkte wie auf 16-Bit-Hardware. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

vec3 chrom(float v) {
	// oben Himmel, Mitte hart, unten dunkel: klassischer Chrom-Verlauf
	vec3 a = mix(vec3(0.25, 0.45, 0.95), vec3(0.95, 0.97, 1.0), smoothstep(0.0, 0.5, v));
	vec3 b = mix(vec3(0.25, 0.18, 0.12), vec3(0.75, 0.7, 0.62), smoothstep(-0.5, 0.0, v));
	return v > 0.0 ? a : b;
}

void fragment() {
	vec2 pix = vec2(floor(224.0 * aspect), 224.0);
	vec2 cell = floor(UV * pix);
	vec2 p = ort((cell + 0.5) / pix);
	vec3 c = vec3(0.0);
	float zeilen = 112.0;
	float row = floor((p.y + 1.0) * 0.5 * zeilen);
	float hr = h11(row * 1.37 + 3.0);
	float sammeln = e_io((t - 0.75) / 0.55);
	if (hr > 0.5) {
		float tempo = mix(2.5, 7.0, h11(row + 11.0));
		float lang = mix(0.3, 1.6, h11(row + 23.0));
		float span = 2.0 * aspect + lang + 0.6;
		float kopf = -aspect - 0.3 + mod(h11(row + 41.0) * span + t * tempo, span);
		float x = p.x;
		float in_s = step(kopf - lang, x) * step(x, kopf);
		float s = sat((x - (kopf - lang)) / lang);
		float blau = step(0.78, h11(row + 57.0));
		vec3 farbe = blau > 0.5 ? vec3(0.12, 0.4, 1.0) : chrom(sin(row * 0.9) * 0.5);
		float naehe = 1.0 - sammeln * smoothstep(0.05, 0.5, abs(p.y));
		c += farbe * in_s * pow(s, 2.0) * naehe * (1.0 - smoothstep(1.5, 1.9, t));
	}
	// Chromband in der Mitte: öffnet sich, ein Glanz läuft darüber.
	float bh = 0.13 * e_out((t - 0.95) / 0.35);
	float bw = aspect * e_out((t - 0.85) / 0.4);
	if (abs(p.y - 0.12) < bh && abs(p.x) < bw) {
		float v = (p.y - 0.12) / max(bh, 0.001);
		vec3 band = chrom(v);
		float gl = step(abs(p.x - mix(-aspect, aspect, e_io((t - 1.2) / 0.6)) + v * 0.2), 0.05);
		band = mix(band, vec3(1.0), gl * 0.8);
		c = band * (1.0 - 0.3 * ruhe());
	}
	float saum = step(abs(abs(p.y - 0.12) - bh), 0.008) * step(abs(p.x), bw);
	c = mix(c, vec3(1.0), saum * 0.9);
	c += vec3(0.3, 0.5, 1.0) * buckel(0.9, 1.15, t) * 0.25 * glanz(p.y - 0.12, 0.3);
	c = floor(c * 7.0 + 0.5) / 7.0;
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.35), 1.0);
}
