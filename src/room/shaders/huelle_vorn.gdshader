// Vorderseite einer Spielhülle (src/room/regal_welt.gd Huelle, auch im Zimmer): eine Fläche über der
// ganzen Front. Darauf der Einleger (Regal.einleger) – ein echter Scan unverändert (bild_lage, nie
// gestreckt; daneben bleibt ein schmaler Rand der Hülle), sonst Uzais Ersatz-Vorderseite (Verlauf in
// grund/grund2) bzw. ein Motiv – mit dem Band des Systems in seiner echten Form (Regal.RAHMEN:
// gerade, Bogen, Schwung; Verlauf, feine Kante). Um den Einleger der Kunststoff der Hülle.
// Kunststoffhülle (art 0): Klarsichtfolie über allem (Glanz, Fresnel, ein weicher Lichtschein, der
// beim Drehen wandert) und das Scharnier als Wulst nahe dem Rücken. CD-Hülle (art 1): klarer Deckel,
// links der gerippte Scharnierstreifen über der Schale, rechts die beiden Haltenasen. Karton (art 2):
// matt bedruckt mit Fasern und hellen, abgegriffenen Kanten.
// Koordinaten in Metern, Ursprung unten links (links ist der Rücken).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/room/shaders/rauschen.gdshaderinc"

uniform vec2 seite = vec2(0.135, 0.19);
uniform float rad = 0.0025;
uniform vec4 einleger = vec4(0.0006, 0.0025, 0.1319, 0.185);
uniform sampler2D bild : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool hat_bild = false;
uniform vec4 bild_lage = vec4(0.0, 0.0, 1.0, 1.0);   // auf dem Einleger (m, unten links)
uniform vec4 bild_uv = vec4(0.0, 0.0, 1.0, 1.0);     // Ausschnitt im Bild (oben links)
uniform vec3 plastik : source_color = vec3(0.07);
uniform vec3 schale : source_color = vec3(0.04);
uniform int art = 0;
uniform bool klar = false;
uniform float folie = 0.5;
uniform vec3 grund : source_color = vec3(0.2, 0.22, 0.3);
uniform vec3 grund2 : source_color = vec3(0.08, 0.08, 0.1);
uniform int band_seite = -1;                          // -1 ohne, 0 oben, 1 links, 2 rechts, 3 unten
uniform float band_anteil = 0.1;
uniform int band_form = 0;                            // 0 gerade, 1 Bogen, 2 Schwung
uniform vec3 band_farbe : source_color = vec3(0.0);
uniform vec3 band_farbe2 : source_color = vec3(0.0);
uniform vec3 linie : source_color = vec3(0.0);
uniform bool mit_linie = false;
uniform float scharnier = 0.0095;                    // Abstand des Scharniers vom Rücken (m)
uniform float glimmen = 0.0;

// Band: d = Abstand vom Rand (Anteil), s = Lage entlang des Bands (0 … 1) → 0 außen, 1 im Band,
// 2 auf der feinen Kante darunter.
float band_masz(float s) {
	if (band_form == 1) {
		return band_anteil * (0.62 + 0.55 * sin(3.14159 * clamp(s * 0.9 + 0.08, 0.0, 1.0)));
	} else if (band_form == 2) {
		return band_anteil * mix(0.18, 1.2, smoothstep(0.0, 1.0, s));
	}
	return band_anteil;
}

void fragment() {
	vec2 p = vec2(rad, rad) + vec2(UV.x, 1.0 - UV.y) * (seite - 2.0 * vec2(rad));
	vec2 e = (p - einleger.xy) / einleger.zw;
	float px = fwidth(p.x) * 1.2;
	float im = smoothstep(-px, px, p.x - einleger.x) * smoothstep(-px, px, einleger.x + einleger.z - p.x)
		* smoothstep(-px, px, p.y - einleger.y) * smoothstep(-px, px, einleger.y + einleger.w - p.y);
	// Einleger: Scan, Motiv oder Ersatz.
	vec3 c;
	vec2 q = (p - einleger.xy - bild_lage.xy) / bild_lage.zw;
	float im_bild = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	if (hat_bild) {
		vec2 uv = bild_uv.xy + vec2(q.x, 1.0 - q.y) * bild_uv.zw;
		c = texture(bild, uv).rgb;
		c = mix(art == 2 ? textureLod(bild, clamp(uv, 0.0, 1.0), 6.0).rgb : plastik * 0.9, c, im_bild);
	} else {
		// Ersatz: ruhiger Verlauf mit einem Lichtschein oben, dunkler zum Rand.
		float v = e.y;
		c = mix(grund2, grund, smoothstep(0.0, 1.0, v));
		c += grund * 0.35 * exp(-8.0 * dot(e - vec2(0.62, 0.68), e - vec2(0.62, 0.68)));
		c *= 1.0 - 0.28 * smoothstep(0.35, 0.75, length(e - 0.5));
	}
	if (band_seite >= 0) {
		float d = band_seite == 0 ? 1.0 - e.y : (band_seite == 1 ? e.x : (band_seite == 2 ? 1.0 - e.x : e.y));
		float s = band_seite == 0 || band_seite == 3 ? e.x : 1.0 - e.y;
		float b = band_masz(s);
		float aa = fwidth(d) * 1.2;
		vec3 bc = mix(band_farbe, band_farbe2, smoothstep(0.15, 1.0, s));
		float l = mit_linie ? (smoothstep(b - aa, b, d) * (1.0 - smoothstep(b + 0.007, b + 0.007 + aa, d))) : 0.0;
		c = mix(c, linie, l);
		c = mix(c, bc, 1.0 - smoothstep(b - aa, b, d));
	}
	// Um den Einleger: Kunststoff der Hülle bzw. bei der CD-Hülle die Schale unter dem Deckel.
	vec3 rand = plastik;
	float rippe = 0.0;
	if (art == 1) {
		rand = mix(schale, plastik, 0.12);
		if (p.x < einleger.x) {
			// Gerippter Scharnierstreifen: feine Rippen längs, je eine helle und eine dunkle Kante.
			float r = fract(p.x / 0.0011);
			rippe = smoothstep(0.0, 0.25, r) * (1.0 - smoothstep(0.55, 0.85, r));
			rand += vec3(0.12) * rippe;
		}
	} else if (art == 2) {
		rand = mix(c, vec3(0.75, 0.72, 0.66), 0.4);
	}
	c = mix(rand, c, im);
	// Material: Kunststoff mit Folie, klarer Deckel oder matter Karton.
	float rau = 0.42;
	float cc = 0.0;
	float ccr = 0.3;
	vec3 n_off = vec3(0.0);
	vec3 emi = vec3(0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	if (art == 2) {
		float f = uz_noise2(p * vec2(9000.0, 1400.0)) * 0.6 + uz_noise2(p * 2600.0) * 0.4;
		c *= 0.94 + 0.08 * f;
		// Abgegriffene Kanten: der Karton hellt zum Rand hin etwas auf.
		vec2 r2 = min(p, seite - p);
		float kante = 1.0 - smoothstep(0.0, 0.0022, min(r2.x, r2.y));
		c = mix(c, vec3(0.86, 0.83, 0.77), kante * 0.35 * (0.6 + 0.4 * f));
		rau = 0.74;
	} else {
		// Folie bzw. klarer Deckel: glatt, mit einem weichen Lichtschein, der beim Drehen wandert.
		float wellig = uz_noise2(p * 55.0);
		rau = mix(0.22, 0.08, folie) + wellig * 0.05;
		cc = art == 1 ? 0.6 : mix(0.25, 0.55, folie);
		ccr = art == 1 ? 0.03 : mix(0.12, 0.05, folie);
		float schein = dot(p / seite, vec2(0.75, 0.5)) + VIEW.x * 0.8 - 0.55;
		float streif = exp(-pow(schein * 6.0, 2.0)) * 0.014 + exp(-pow((schein - 0.32) * 14.0, 2.0)) * 0.008;
		emi = vec3(streif + fres * (klar ? 0.035 : 0.02)) * (1.0 + glimmen * 0.4);
		if (art == 0) {
			// Scharnier: ein Wulst längs, nahe dem Rücken (Licht oben, Schatten unten an der Kante).
			float sd = (p.x - scharnier) / 0.0016;
			float wulst = exp(-sd * sd);
			n_off.x = -sd * wulst * 0.9;
			c *= 1.0 - 0.18 * exp(-pow((p.x - scharnier - 0.0019) / 0.0006, 2.0));
			c += vec3(0.05) * wulst;
		} else {
			// Haltenasen rechts oben und unten über dem Heft.
			vec2 na = vec2(seite.x - 0.006, 0.0);
			float nase = 0.0;
			for (int i = 0; i < 2; i++) {
				vec2 m = vec2(na.x, i == 0 ? einleger.y + 0.007 : einleger.y + einleger.w - 0.007);
				vec2 dd = (p - m) / vec2(0.004, 0.0045);
				nase = max(nase, 1.0 - smoothstep(0.8, 1.0, length(dd)));
			}
			c = mix(c, c * 0.82 + vec3(0.08), nase * 0.6);
			n_off.x += rippe * 0.5 - 0.25;
		}
	}
	ALBEDO = c;
	ROUGHNESS = rau;
	SPECULAR = art == 2 ? 0.25 : 0.55;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = ccr;
	EMISSION = emi;
	NORMAL = normalize(NORMAL + TANGENT * n_off.x);
}
