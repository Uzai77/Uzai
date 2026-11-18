// Gesicht der Figur und des Haustiers: Augen, Brauen, Mund, Wangen und Sommersprossen als
// Abstandsfelder (keine Bilder) – scharf aus jeder Nähe, Blinzeln und Mienen nur über Parameter.
// p: Lage auf dem Kopf in Winkeln (u waagrecht, v senkrecht, Bogenmaß; das Gesicht um 0).
// Benutzt von haut.gdshader und koerper.gdshader (braucht rauschen.gdshaderinc davor).

uniform int augen = 0;            // 0 rund, 1 oval, 2 mandel, 3 wimpern, 4 knopf, 5 Katze, 6 Tier rund, -1 keine
uniform vec3 iris : source_color = vec3(0.36, 0.23, 0.13);
uniform vec2 augen_lage = vec2(0.30, 0.03);
uniform float augen_groesse = 1.0;
uniform int brauen = 0;           // 0 fein, 1 kräftig, 2 keine
uniform vec3 braue : source_color = vec3(0.25, 0.17, 0.12);
uniform int mund = 0;             // 0 lächeln, 1 grinsen, 2 sanft, 3 gerade, 4 Katzenmund, -1 keiner
uniform float mund_y = -0.27;
uniform float mund_groesse = 1.0;
uniform int wangen = 1;           // 0 nichts, 1 Wangen, 2 Sommersprossen, 3 beides
uniform bool nase = true;

uniform float blinzeln = 0.0;     // 0 offen … 1 zu
uniform float zwinkern = 0.0;     // rechtes Auge zu
uniform float freude = 0.0;       // lachende Augen (Bögen nach oben)
uniform float schlaf = 0.0;       // entspannt geschlossen (Bögen nach unten)
uniform float offen = 0.0;        // Mund offen

float ellipse(vec2 p, vec2 r) {
	return (length(p / r) - 1.0) * min(r.x, r.y);
}

// Abstand zu einem Kreisbogen (Mitte c, Radius r), nur unterhalb (unten > 0) bzw. oberhalb.
float bogen(vec2 p, vec2 c, float r, float breite, float unten) {
	vec2 q = p - c;
	float d = abs(length(q) - r);
	float seite = unten > 0.0 ? -q.y : q.y;
	float wink = atan(abs(q.x), seite);
	return wink < breite ? d : 1e3;
}

float deck(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}

// Ein Auge (s = +1 links, −1 rechts). Gibt Farbe und Deckung zurück.
vec4 auge(vec2 p, float s, float aa) {
	float zu = max(blinzeln, s < 0.0 ? zwinkern : 0.0);
	float lacht = freude;
	float ruht = schlaf;
	vec3 dunkel = vec3(0.12, 0.08, 0.07);
	vec2 r = vec2(0.078, 0.098);
	if (augen == 1) r = vec2(0.064, 0.108);
	if (augen == 2) r = vec2(0.088, 0.07);
	if (augen == 4) r = vec2(0.036, 0.05);
	if (augen == 5) r = vec2(0.1, 0.1);
	if (augen == 6) r = vec2(0.088, 0.096);
	r *= augen_groesse;
	// Geschlossen: ein Bogen statt des Auges (lachend nach oben gewölbt, schlafend nach unten).
	float geschl = max(zu, max(lacht, ruht));
	vec4 out_c = vec4(0.0);
	if (geschl < 0.98) {
		vec2 rr = vec2(r.x, r.y * max(0.04, 1.0 - geschl));
		vec2 q = p - vec2(0.0, -r.y * geschl * 0.35);
		float d = ellipse(q, rr);
		float a = deck(d, aa);
		vec3 c = dunkel;
		if (augen != 4) {
			// Iris mit Verlauf, Pupille, zwei Glanzpunkte; oben ein kräftiger Lidstrich.
			vec2 ir = rr * 0.78;
			float di = ellipse(q - vec2(0.0, -rr.y * 0.08), ir);
			vec3 ic = mix(iris * 1.25, iris * 0.55, smoothstep(-ir.y, ir.y, q.y));
			c = mix(c, ic, deck(di, aa));
			vec2 pr = augen == 5 ? vec2(rr.x * 0.16, rr.y * 0.62) : rr * 0.42;
			float dp = ellipse(q - vec2(0.0, -rr.y * 0.05), pr);
			c = mix(c, dunkel * 0.6, deck(dp, aa));
			float rand = smoothstep(0.0, -0.016 * augen_groesse, d) ;
			c = mix(dunkel, c, rand);
		}
		float g1 = ellipse(q - vec2(rr.x * 0.32 * s, rr.y * 0.38), vec2(r.x * 0.26, r.x * 0.26 * min(1.0, rr.y / r.y * 1.6)));
		float g2 = ellipse(q - vec2(-rr.x * 0.3 * s, -rr.y * 0.42), vec2(r.x * 0.12, r.x * 0.12));
		c = mix(c, vec3(1.0), deck(g1, aa) * 0.95);
		c = mix(c, vec3(1.0), deck(g2, aa) * 0.7 * (augen == 4 ? 0.0 : 1.0));
		out_c = vec4(c, a);
		if (augen == 3) {
			// Wimpern: zwei kleine Striche am äußeren Lidrand.
			for (int i = 0; i < 2; i++) {
				vec2 w = q - vec2(s * (r.x * (0.72 + 0.22 * float(i))), r.y * (0.78 - 0.32 * float(i)) * (1.0 - geschl));
				float dw = ellipse(vec2(w.x * 0.8 - w.y * 0.6 * s, w.x * 0.6 * s + w.y * 0.8), vec2(0.026, 0.007));
				float aw = deck(dw, aa);
				out_c = vec4(mix(out_c.rgb, dunkel, aw), max(out_c.a, aw));
			}
		}
	}
	if (geschl > 0.5) {
		float t = smoothstep(0.5, 0.95, geschl);
		float dl;
		if (lacht >= ruht && lacht > zu) {
			dl = bogen(p, vec2(0.0, -r.y * 0.45), r.x * 0.9, 1.15, 0.0);
		} else {
			dl = bogen(p, vec2(0.0, r.y * 0.25), r.x * 0.9, 1.05, 1.0);
		}
		float a = deck(dl - 0.011 * augen_groesse, aa) * t;
		out_c = vec4(mix(out_c.rgb, dunkel, a), max(out_c.a * (1.0 - t), a));
	}
	return out_c;
}

vec4 mund_farbe(vec2 p, float aa) {
	vec3 linie = vec3(0.32, 0.12, 0.1);
	vec3 innen = vec3(0.42, 0.13, 0.12);
	vec3 zunge = vec3(0.86, 0.45, 0.42);
	p /= mund_groesse;
	float a = 0.0;
	vec3 c = linie;
	float w = 0.0105;
	if (offen > 0.02 || mund == 1) {
		// Offen: ein weiches „D“ mit Zunge (grinsen, jubeln, staunen).
		float o = mund == 1 ? max(offen, 0.6) : offen;
		float d = mund == 1 && offen < 0.6
			? max(ellipse(p - vec2(0.0, 0.012), vec2(0.07, 0.06 * o + 0.012)), p.y - 0.012)
			: ellipse(p, vec2(0.04 + 0.025 * o, 0.012 + 0.05 * o));
		a = deck(d, aa);
		float dz = ellipse(p - vec2(0.0, -0.035 * o - 0.006), vec2(0.035, 0.022));
		c = mix(innen, zunge, deck(dz, aa) * smoothstep(0.2, 0.6, o));
		c = mix(linie, c, smoothstep(0.0, -0.008, d));
		return vec4(c, a);
	}
	float d = 1e3;
	if (mund == 0) d = bogen(p, vec2(0.0, 0.07 + 0.02 * freude), 0.085 + 0.01 * freude, 0.62 + 0.15 * freude, 1.0);
	if (mund == 2) d = bogen(p, vec2(0.0, 0.045), 0.055, 0.6, 1.0);
	if (mund == 3) {
		vec2 q = p - vec2(clamp(p.x, -0.035, 0.035), 0.0);
		d = length(q);
	}
	if (mund == 4) {
		d = min(bogen(p, vec2(0.021, 0.012), 0.021, 1.45, 1.0), bogen(p, vec2(-0.021, 0.012), 0.021, 1.45, 1.0));
	}
	a = deck(d - w, aa);
	return vec4(c, a);
}

vec3 gesicht_malen(vec3 c, vec3 grund, vec2 p, float aa, inout float rough, inout float spec) {
	float u = p.x;
	float v = p.y;
	// Wangen und Sommersprossen unter allem anderen.
	if (wangen == 1 || wangen == 3) {
		for (int i = -1; i <= 1; i += 2) {
			vec2 q = (p - vec2(float(i) * augen_lage.x * 1.38, augen_lage.y - 0.17)) / vec2(0.085, 0.055);
			c = mix(c, vec3(0.93, 0.48, 0.45), exp(-dot(q, q) * 1.6) * 0.32);
		}
	}
	if (wangen == 2 || wangen == 3) {
		vec2 g = p * 26.0;
		vec2 zelle = floor(g);
		float h = uz_hash2(zelle + 7.0);
		vec2 m = zelle + 0.5 + (vec2(uz_hash2(zelle + 1.0), uz_hash2(zelle + 3.0)) - 0.5) * 0.6;
		float zone = smoothstep(0.62, 0.3, abs(u)) * smoothstep(-0.27, -0.12, v) * smoothstep(0.05, -0.08, v);
		float a = (1.0 - smoothstep(0.1, 0.2, length(g - m))) * step(0.45, h) * zone;
		c = mix(c, grund * 0.62, a * 0.75);
	}
	if (nase) {
		vec2 q = (p - vec2(0.0, -0.115)) / vec2(0.045, 0.03);
		c *= 1.0 - exp(-dot(q, q) * 1.4) * 0.07;
	}
	// Augen und Brauen.
	if (augen >= 0) {
		for (int i = -1; i <= 1; i += 2) {
			float s = float(i);
			vec2 q = p - vec2(s * augen_lage.x, augen_lage.y);
			vec4 e = auge(q, s, aa);
			c = mix(c, e.rgb, e.a);
			rough = mix(rough, 0.18, e.a);
			spec = mix(spec, 0.6, e.a);
			if (brauen < 2) {
				float hoch = 0.165 * augen_groesse + freude * 0.012 + offen * 0.02;
				float db = bogen(q, vec2(0.0, hoch - 0.12), 0.12, 0.5, 0.0);
				float dicke = brauen == 1 ? 0.0145 : 0.0085;
				float ab = deck(db - dicke * (1.0 - 0.45 * smoothstep(0.0, 0.07, s * q.x)), aa);
				c = mix(c, braue, ab * 0.95);
			}
		}
	}
	if (mund >= 0) {
		vec4 m = mund_farbe(p - vec2(0.0, mund_y), aa);
		c = mix(c, m.rgb, m.a);
	}
	return c;
}
