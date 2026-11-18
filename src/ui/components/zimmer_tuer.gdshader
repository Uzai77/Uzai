// Die Tür zu „Dein Zimmer“ (zimmer_tuer.gd): Die ganze Fläche ist eine Tür in der Wand – Zarge,
// Nussbaum-Blatt mit vier Kassetten, Messingdrücker mit Schlüsselschild, ein Messingschild mit dem
// Namen (Textur „schild“), warmes Licht im Spalt und davor auf dem Boden. Um die Tür bleibt der Grund
// der Oberfläche (nur Licht und ein weicher Schatten liegen darauf).
// auf 0 … 1: das Blatt schwingt um die Bänder links in den Raum (perspektivisch richtig: die freie Kante
// rückt nach hinten). In der Fahrt (zimmer_tuer.gd, Ebene über allem): rund um die Tür ein stilles Bild
// des Bildschirms („kulisse“), die Öffnung ist durchsichtig („durch“: dahinter das echte Zimmer), eine
// Hand drückt das Blatt auf („hand“), und alles wächst um die Öffnung („zoom“), bis sie den Schirm füllt.
// Alles aus UV, ohne Bilder; Kanten nach Bildpunktgröße weich.
shader_type canvas_item;

uniform vec4 wand : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform vec4 rahmen : source_color = vec4(0.2, 0.19, 0.19, 1.0);
uniform vec4 blatt : source_color = vec4(0.33, 0.22, 0.15, 1.0);
uniform vec4 licht : source_color = vec4(1.0, 0.78, 0.5, 1.0);
uniform vec4 metall : source_color = vec4(0.8, 0.62, 0.36, 1.0);
uniform vec4 haut : source_color = vec4(0.8, 0.6, 0.48, 1.0);
uniform vec4 aermel : source_color = vec4(0.13, 0.13, 0.15, 1.0);
uniform vec2 groesse = vec2(1920.0, 1080.0);   // Fläche in Bildpunkten
uniform vec4 tuer = vec4(0.4, 0.1, 0.6, 0.9);  // Lichte der Tür in UV der Fläche: x0, y0, x1, y1
uniform float auf = 0.0;
uniform float gewaehlt = 0.0;
uniform float atmen = 0.0;
uniform float durch = 0.0;
uniform float zoom = 1.0;
uniform vec2 zoom_von = vec2(0.5);              // dieser Punkt (UV) …
uniform vec2 zoom_nach = vec2(0.5);             // … liegt beim Zoom hier
uniform float mit_kulisse = 0.0;
uniform sampler2D kulisse : filter_linear, repeat_disable;
uniform sampler2D schild : filter_linear, repeat_disable;
uniform float hand = 0.0;                       // 0 weg … 1 ganz da (nur in der Fahrt)
uniform float druck = 0.0;                      // die Hand drückt (das Blatt gibt ein wenig nach)

const float WINKEL = 1.38;      // ganz auf (Bogenmaß)
const float TIEFE = 0.42;       // Türbreite / Abstand zum Auge (Perspektive des Blatts)
const float AUGE = 0.52;        // Augenhöhe in der Tür (0 oben, 1 unten)

float kante(float d, float w) {
	return 1.0 - smoothstep(-w, w, d);
}

float zufall(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rauschen(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(zufall(i), zufall(i + vec2(1.0, 0.0)), f.x), mix(zufall(i + vec2(0.0, 1.0)), zufall(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Abstand zu einem Rechteck mit runden Ecken (negativ innen).
float kasten(vec2 p, vec2 a, vec2 b, float r) {
	vec2 m = (a + b) * 0.5;
	vec2 h = (b - a) * 0.5 - vec2(r);
	vec2 q = abs(p - m) - h;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float kapsel(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// Holz: feine Maserung längs (v), leicht gewellt, mit Poren.
vec3 holz(vec2 uv, float breite_px) {
	float welle = rauschen(vec2(uv.y * 2.2, uv.x * 3.0)) * 1.6;
	float maser = rauschen(vec2(uv.x * 34.0 + welle, uv.y * 2.0)) * 0.55 + rauschen(vec2(uv.x * 95.0 + welle * 2.0, uv.y * 7.0)) * 0.3
			+ rauschen(vec2(uv.x * 260.0, uv.y * 30.0)) * 0.15 * clamp(breite_px / 400.0, 0.0, 1.0);
	vec3 b = blatt.rgb * (0.86 + 0.24 * maser);
	return b * (0.96 + 0.07 * (1.0 - uv.y));
}

// Ein Punkt des Blatts (u quer, v längs; 0..1) in der Lichte (0..1), bei Winkel a.
vec2 blatt_ort(float u, float v, float a) {
	float z = u * sin(a) * TIEFE;
	return vec2(u * cos(a) / (1.0 + z), AUGE + (v - AUGE) / (1.0 + z));
}

// Hand von hinten (rechte Hand, Handfläche am Blatt): Abstand in Einheiten der Handbreite.
float hand_form(vec2 h) {
	float d = kasten(h, vec2(-0.5, -0.46), vec2(0.5, 0.5), 0.26);
	d = min(d, kapsel(h, vec2(-0.33, -0.36), vec2(-0.36, -1.18), 0.118));
	d = min(d, kapsel(h, vec2(-0.11, -0.4), vec2(-0.1, -1.32), 0.122));
	d = min(d, kapsel(h, vec2(0.12, -0.38), vec2(0.15, -1.25), 0.118));
	d = min(d, kapsel(h, vec2(0.34, -0.3), vec2(0.4, -0.98), 0.104));
	d = min(d, kapsel(h, vec2(-0.4, 0.22), vec2(-0.66, -0.2), 0.14));
	d = min(d, kapsel(h, vec2(0.0, 0.3), vec2(0.1, 1.0), 0.37));
	return d;
}

// Licht bzw. Schatten auf den Grund: in der Kachel als Farbe mit Deckkraft (darunter liegt die Oberfläche),
// in der Fahrt auf das Bild davor.
void leuchten(inout vec4 c, float g, float kul) {
	g = clamp(g, 0.0, 1.0);
	if (kul > 0.5) {
		c.rgb += licht.rgb * g;
	} else {
		c.rgb = mix(c.rgb, licht.rgb, g / max(max(c.a, g), 0.0001));
		c.a = max(c.a, g);
	}
}

void abdunkeln(inout vec4 c, float s, float kul) {
	s = clamp(s, 0.0, 1.0);
	if (kul > 0.5) {
		c.rgb *= 1.0 - s;
	} else {
		c.rgb *= 1.0 - s / max(max(c.a, s), 0.0001);
		c.a = max(c.a, s);
	}
}

void fragment() {
	// Zoom: die Fläche wächst um zoom_von, das dabei nach zoom_nach wandert.
	vec2 p = zoom_von + (UV - zoom_nach) / zoom;
	float px = max(fwidth(p.x), fwidth(p.y)) * 1.2;
	vec2 seite = vec2(groesse.x / groesse.y, 1.0);
	vec2 t0 = tuer.xy;
	vec2 t1 = tuer.zw;
	vec2 tg = t1 - t0;
	float tuer_px = tg.x * groesse.x;
	vec2 q = (p - t0) / tg;                        // in der Lichte 0..1
	vec2 qpx = vec2(px / tg.x, px / tg.y);
	float schein = 0.7 + 0.18 * gewaehlt + 0.12 * atmen * gewaehlt;
	float a = auf * WINKEL;

	// Grund: in der Kachel durchsichtig (Hintergrund der Oberfläche), in der Fahrt das Bild davor.
	vec4 c = vec4(0.0);
	if (mit_kulisse > 0.5) {
		vec2 kq = clamp(p, vec2(0.0), vec2(1.0));
		c = vec4(texture(kulisse, kq).rgb, 1.0);
	}
	// Schatten der Tür auf der Wand (weich, nach unten rechts) und warmes Licht davor auf dem Boden.
	float zr = 0.11;                               // Zarge in Türbreiten
	vec2 qa = (p - t0) * groesse / tuer_px;        // in Türbreiten ab der Ecke oben links
	float hoch = tg.y * groesse.y / tuer_px;
	float aussen = kasten(qa, vec2(-zr - 0.02, -zr - 0.02), vec2(1.0 + zr + 0.02, hoch + 0.01), 0.02);
	abdunkeln(c, (1.0 - smoothstep(0.0, 0.22, aussen + 0.01)) * 0.45, mit_kulisse);
	if (q.y > 1.0) {
		// Boden vor der Tür: Lichtfächer aus dem Spalt bzw. der offenen Tür.
		float t = (qa.y - hoch) / 1.4;
		float breit = 0.5 * (1.0 + t * (0.7 + 2.2 * auf));
		float x = abs(qa.x - 0.5) / max(breit, 0.001);
		float f = (1.0 - smoothstep(0.4, 1.0, x)) * exp(-t * (2.6 - 1.6 * auf)) * step(0.0, t);
		leuchten(c, f * (0.22 * schein + 0.5 * auf), mit_kulisse);
	}
	// Ein Hauch Licht auf der Wand um die Zarge.
	leuchten(c, exp(-max(aussen, 0.0) * 4.0) * 0.16 * auf * (1.0 - smoothstep(0.98, 1.06, q.y)), mit_kulisse);

	// Zarge: oben und an den Seiten, profiliert (Licht von oben links).
	float z_aussen = kasten(qa, vec2(-zr, -zr), vec2(1.0 + zr, hoch + 0.004), 0.008);
	float z_innen = kasten(qa, vec2(0.0), vec2(1.0, hoch + 0.05), 0.0);
	float zpx = px * groesse.x / tuer_px;
	float zm = kante(z_aussen, zpx) * (1.0 - kante(z_innen, zpx));
	if (zm > 0.0) {
		float tief = clamp(-z_aussen / zr, 0.0, 1.0);
		float stufe = smoothstep(0.28, 0.34, tief) - smoothstep(0.62, 0.68, tief);
		vec3 z = rahmen.rgb * (0.86 + 0.2 * (1.0 - clamp(qa.y / hoch, 0.0, 1.0)));
		z *= 1.0 - 0.12 * stufe;
		// Lichtkante zur Wand und zur Öffnung.
		z += rahmen.rgb * 0.35 * kante(abs(z_aussen + zpx * 1.5) - zpx * 0.8, zpx);
		z = mix(z, z * 0.7, kante(abs(z_innen + zpx * 2.0) - zpx * 1.5, zpx));
		// Warmer Saum aus dem Spalt.
		z += licht.rgb * 0.18 * schein * (1.0 - auf) * exp(-max(-z_innen, 0.0) / (0.025));
		z += licht.rgb * 0.22 * auf * exp(-max(-z_innen, 0.0) / 0.05);
		c = mix(c, vec4(z, 1.0), zm);
	}

	// Öffnung: dahinter das Zimmer – in der Kachel warmes Licht, in der Fahrt durchsichtig.
	float innen = kante(z_innen, zpx) * step(qa.y, hoch);
	if (innen > 0.0) {
		float glut = 0.55 + 0.45 * exp(-dot((q - vec2(0.5, 0.6)) * vec2(1.6, 1.0), (q - vec2(0.5, 0.6)) * vec2(1.6, 1.0)) * 2.4);
		vec4 hinten = vec4(licht.rgb * glut * (0.72 + 0.45 * auf), 1.0);
		hinten = mix(hinten, vec4(0.0), durch);
		c = mix(c, hinten, innen);
		// Das Blatt: Bänder links, schwingt in den Raum; die Hand drückt es eine Spur nach hinten.
		float an = a + druck * 0.025;
		float u = q.x / max(cos(an) - q.x * sin(an) * TIEFE, 0.0001);
		float zt = u * sin(an) * TIEFE;
		float v = AUGE + (q.y - AUGE) * (1.0 + zt);
		if (u >= -0.003 && u <= 1.003 && v >= -0.003 && v <= 1.003 && cos(an) - q.x * sin(an) * TIEFE > 0.0) {
			float sx = qpx.x * (1.0 + zt) / max(cos(an), 0.05);
			float sy = qpx.y * (1.0 + zt);
			float bm = kante(abs(u - 0.5) - 0.5, sx) * kante(abs(v - 0.5) - 0.5, sy);
			vec2 fu = vec2(u, v);
			vec3 b = holz(fu, tuer_px);
			// Vier Kassetten mit Profil: oben lang, unten kürzer; Licht von oben links.
			vec2 asp = vec2(1.0, hoch);
			float d1 = kasten(fu * asp, vec2(0.15, 0.08) * asp, vec2(0.46, 0.52) * asp, 0.01);
			float d2 = kasten(fu * asp, vec2(0.54, 0.08) * asp, vec2(0.85, 0.52) * asp, 0.01);
			float d3 = kasten(fu * asp, vec2(0.15, 0.6) * asp, vec2(0.46, 0.92) * asp, 0.01);
			float d4 = kasten(fu * asp, vec2(0.54, 0.6) * asp, vec2(0.85, 0.92) * asp, 0.01);
			float fd = min(min(d1, d2), min(d3, d4));
			float fw = sx * 1.5;
			float profil = kante(fd, fw) * (1.0 - kante(fd + 0.035, fw));
			float spiegel = kante(fd + 0.035, fw);
			// Richtung des Profils: welche Kassette, welche Seite (oben/links hell, unten/rechts dunkel).
			vec2 mitte = fu.x < 0.5 ? (fu.y < 0.56 ? vec2(0.305, 0.3) : vec2(0.305, 0.76)) : (fu.y < 0.56 ? vec2(0.695, 0.3) : vec2(0.695, 0.76));
			vec2 rich = normalize((fu - mitte) * asp + vec2(0.0001));
			float hell = dot(rich, normalize(vec2(-0.6, -0.8)));
			b = mix(b, b * (1.0 + 0.32 * hell), profil);
			b *= 1.0 - 0.05 * spiegel;
			b = mix(b, b * 0.72, kante(abs(fd) - 0.002, fw * 0.7));
			// Kanten des Blatts: oben eine Lichtkante, rechts (Schlossseite) etwas dunkler.
			b *= 1.0 - 0.18 * smoothstep(0.96, 1.0, u) - 0.1 * smoothstep(0.985, 1.0, v);
			b += blatt.rgb * 0.18 * (1.0 - smoothstep(0.0, 0.012, v));
			// Schild „Dein Zimmer“: Messing, der Name eingraviert (dunkler, mit heller Unterkante).
			vec2 sm = vec2(0.5, 0.29);
			vec2 sg = vec2(0.46, 0.095);
			float sd = kasten(fu * asp, (sm - sg * vec2(0.5, 0.5 / hoch)) * asp, (sm + sg * vec2(0.5, 0.5 / hoch)) * asp, 0.012);
			float smk = kante(sd, sx);
			if (smk > 0.0) {
				vec2 suv = (fu - (sm - sg * vec2(0.5, 0.5 / hoch))) / (sg * vec2(1.0, 1.0 / hoch));
				vec3 ms = metall.rgb * (0.62 + 0.24 * (1.0 - suv.y)) * (0.95 + 0.08 * rauschen(vec2(suv.x * 140.0, suv.y * 6.0)));
				ms += metall.rgb * 0.25 * kante(abs(sd + sx * 1.5) - sx, sx);
				float schrift = texture(schild, suv).a;
				float schrift2 = texture(schild, suv - vec2(0.0, 0.035)).a;
				ms = mix(ms, ms * 1.12, schrift2 * (1.0 - schrift) * 0.6);
				ms = mix(ms, metall.rgb * 0.28, schrift);
				b = mix(b, ms, smk);
			}
			// Drücker: Rosette, Hebel zur Bandseite, darunter das Schlüsselschild.
			vec2 kl = (fu - vec2(0.9, 0.53)) * asp;
			float rose = length(kl) - 0.036;
			float hebel = kapsel(kl, vec2(0.0, 0.0), vec2(-0.17, 0.004), 0.016);
			float schl = kasten(kl, vec2(-0.016, 0.06), vec2(0.016, 0.13), 0.014);
			float km = kante(min(min(rose, hebel), schl), sx);
			if (km > 0.0) {
				float hl = kante(min(rose, hebel) + 0.006, sx) * 0.4 + 0.75;
				vec3 mf = metall.rgb * hl * (1.0 + 0.35 * clamp(-kl.y / 0.03, -1.0, 1.0));
				float loch = kante(min(length(kl - vec2(0.0, 0.085)) - 0.008, kasten(kl, vec2(-0.003, 0.085), vec2(0.003, 0.11), 0.002)), sx);
				mf = mix(mf, vec3(0.03), loch);
				b = mix(b, mf, km);
			}
			// Schatten des Hebels auf dem Holz.
			b *= 1.0 - 0.25 * kante(kapsel(kl - vec2(0.004, 0.012), vec2(0.0), vec2(-0.17, 0.004), 0.02), sx * 4.0) * (1.0 - km);
			// Gedreht: weniger Licht von vorn, an der freien Kante ein warmer Saum aus dem Zimmer.
			b *= 1.0 - 0.5 * sin(an);
			b += licht.rgb * 0.3 * auf * smoothstep(0.75, 1.0, u);
			c = mix(c, vec4(b, 1.0), bm);
		}
		// Lichtspalt unter dem Blatt, ein Hauch an der Schlossseite und oben – solange es zu ist.
		float spalt = exp(-max(1.0 - q.y, 0.0) * hoch / 0.006) * step(0.0, q.x) * step(q.x, 1.0);
		float saum = exp(-max(1.0 - q.x, 0.0) / 0.006) * 0.4 + exp(-max(q.y, 0.0) * hoch / 0.005) * 0.25;
		c.rgb += licht.rgb * (spalt * 0.95 + saum) * schein * (1.0 - smoothstep(0.0, 0.08, auf));
	}

	// Die Hand (nur in der Fahrt): drückt an der Schlossseite, folgt dem Blatt, zieht sich dann zurück.
	if (hand > 0.001) {
		vec2 haft = blatt_ort(0.78, 0.6, a + druck * 0.025);
		vec2 hp = (t0 + haft * tg) * groesse;     // Mitte der Handfläche in Bildpunkten
		hp.y += (1.0 - hand) * groesse.y * 0.55;
		float s = tuer_px * 0.2 * (1.0 - 0.04 * druck) / (1.0 + 0.78 * sin(a) * TIEFE);
		vec2 h = (p * groesse - hp) / s;
		h = vec2(h.x * 0.98 + h.y * 0.12, h.y * 0.98 - h.x * 0.12);   // ein wenig nach rechts gedreht
		float d = hand_form(h);
		// Unterarm im Ärmel: vom Handgelenk zum unteren Rand, nach vorn breiter.
		vec2 unten = vec2(1.4 + 0.45 * (groesse.y - hp.y) / s, (groesse.y - hp.y) / s + 1.5);
		float arm = kapsel(h, vec2(0.08, 0.62), unten, 0.43 + 0.16 * clamp(h.y - 0.6, 0.0, 12.0));
		float hpx = px * groesse.x / s;
		// Kontaktschatten auf der Tür.
		float hs = (1.0 - smoothstep(-0.05, 0.35, hand_form(h - vec2(0.1, 0.14)))) * 0.45 * hand;
		c.rgb *= 1.0 - hs * step(0.5, c.a);
		vec3 hf = haut.rgb * (0.76 + 0.2 * clamp(-h.y * 0.35 + 0.3 - h.x * 0.15, -0.6, 0.6));
		// Fingerzwischenräume: ein Hauch Schatten zwischen den Fingern.
		hf *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.06, abs(fract((h.x + 0.22) / 0.23 + 0.5) - 0.5) * 0.23)) * step(h.y, -0.45);
		hf *= mix(0.72, 1.0, smoothstep(0.0, 0.16, -d));            // weiche Rundung zur Kante
		hf *= 1.0 - 0.1 * kante(abs(h.y + 0.42) - 0.03, hpx * 2.0) * step(abs(h.x), 0.5);   // Knöchel
		hf += licht.rgb * 0.1 * auf * smoothstep(-0.5, 0.5, h.x);
		vec3 af = aermel.rgb * (0.85 + 0.25 * smoothstep(-1.0, 1.0, -h.x)) * (0.92 + 0.08 * sin(h.x * 40.0));
		af = mix(af, aermel.rgb * 1.25, kante(abs(h.y - 1.05) - 0.12, hpx) * step(h.y, 1.4));
		float am = kante(max(arm, -(h.y - 0.92)), hpx);
		float hm = kante(d, hpx);
		vec4 hand_c = mix(vec4(hf, 1.0), vec4(af, 1.0), am);
		c = mix(c, hand_c, max(hm, am) * hand);
	}
	COLOR = c;
}
