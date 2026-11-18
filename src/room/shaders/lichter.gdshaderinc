// Licht auf der Hülle (Wände, Decke, Boden, Teppiche) ohne Engine-Lampen: Die Lampen des Zimmers
// leuchten die großen Flächen hier im Shader an – mit derselben Abnahme wie die Engine (damit
// Möbel, die echte Lampen sehen, dazu passen), aber mit Form: ein Schirm lässt Licht nur oben und
// unten heraus (die typischen Lichtkegel an der Wand), die Deckenlampe strahlt nach unten, der
// Fernseher nach vorn. Kostet ein paar Rechenschritte je Lampe, keinen Zeichendurchgang.
// Dazu der Sonnenfleck aus dem Fenster für die Stufe ohne echte Schatten: Jeder Punkt schaut in
// Richtung Sonne zurück auf die Fensterwand (x = 0) und ist hell, wenn er dort im Glas landet.
// Gesetzt von zimmer_welt.gd (lampen_setzen) und raum.gd (setze_licht).

uniform int lampen_n = 0;
uniform vec4 lampe_pos[12];     // xyz Ort, w Reichweite
uniform vec4 lampe_farbe[12];   // rgb Farbe × Stärke, a Art: 0 Punkt, 1 Schirm, 2 Decke, 3 Bildschirm
uniform vec4 lampe_dir[12];     // Bildschirm: Blickrichtung; Schirm: w = Höhe der Schirmmitte über dem Licht
uniform vec3 fleck_farbe : source_color = vec3(0.0);   // Sonnenfleck (Farbe × Stärke), 0 = aus
uniform vec3 fleck_dir = vec3(1.0, -0.4, 0.0);          // Richtung, in die das Sonnenlicht fällt
uniform vec4 fenster = vec4(1.55, 3.45, 0.88, 2.28);    // Glas: z von, z bis, y von, y bis
uniform vec2 fenster_teile = vec2(1.0);                 // Mittelpfosten, Kämpfer (1 = da)

// Wie die Engine (Godot 4: Fenster bis zur Reichweite, dann Abfall mit der Entfernung hoch 1,5 –
// omni_attenuation der Lampen in moebel.gd) – aber nie näher als 0,35 m gerechnet: Eine Lampe
// direkt an der Wand gibt einen weichen Schein, keinen grellen Punkt. d^-1,5 als inversesqrt³
// (günstiger als pow, zählt bei Software-Grafik und kleiner Grafik im Prozessor).
float uz_abfall(float d, float r) {
	float nd = d / r;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	float k = inversesqrt(max(d, 0.35));
	return nd * nd * k * k * k;
}

vec3 uz_lampen(vec3 wp, vec3 n) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		if (i >= lampen_n) {
			break;
		}
		vec3 d = lampe_pos[i].xyz - wp;
		float dist = length(d);
		float r = lampe_pos[i].w;
		if (dist >= r) {
			continue;
		}
		vec3 l = d / max(dist, 0.0001);
		float art = lampe_farbe[i].a;
		float form = 1.0;
		float ndl = max(dot(n, l), 0.0);
		if (art > 0.5 && art < 1.5) {
			// Schirm: zur Seite gedämpft (durch den Stoff), nach oben und unten offen.
			float steil = abs(l.y);
			form = mix(0.16, 1.0, smoothstep(0.42, 0.78, steil));
			// Nach unten kräftiger (der Schirm ist unten weiter offen), nach oben sanfter.
			form *= l.y > 0.0 ? 1.0 : 0.62;
		} else if (art > 1.5 && art < 2.5) {
			// Deckenlampe: ein warmer Kegel nach unten, darüber nur ein Hauch an der Decke.
			form = mix(0.12, 1.5, smoothstep(0.05, 0.6, l.y));
		} else if (art > 2.5) {
			float vorn = max(dot(-l, lampe_dir[i].xyz), 0.0);
			form = vorn * vorn;
		}
		sum += lampe_farbe[i].rgb * ndl * form * uz_abfall(dist, r);
	}
	return sum;
}

// Sonnenfleck (Stufe Leicht): weich begrenztes Fenster mit Pfosten und Kämpfer.
vec3 uz_fleck(vec3 wp, vec3 n) {
	if (fleck_farbe.r + fleck_farbe.g + fleck_farbe.b <= 0.0 || fleck_dir.x <= 0.01 || wp.x < 0.0) {
		return vec3(0.0);
	}
	float t = wp.x / fleck_dir.x;
	vec3 q = wp - fleck_dir * t;
	float weich = 0.02 + t * 0.018;
	float innen = smoothstep(fenster.x - weich, fenster.x + weich, q.z) * smoothstep(fenster.y + weich, fenster.y - weich, q.z);
	innen *= smoothstep(fenster.z - weich, fenster.z + weich, q.y) * smoothstep(fenster.w + weich, fenster.w - weich, q.y);
	float mitte = (fenster.x + fenster.y) * 0.5;
	innen *= mix(1.0, smoothstep(0.022, 0.022 + weich, abs(q.z - mitte)), fenster_teile.x);
	innen *= mix(1.0, smoothstep(0.02, 0.02 + weich, abs(q.y - (fenster.w - 0.42))), fenster_teile.y);
	return fleck_farbe * innen * max(dot(n, -fleck_dir), 0.0);
}

// Gebackenes Licht der Hülle (Forward+, lichtbacken.gd): Lichtkarten je Fläche, zwei Sätze (a, b) zum
// Überblenden (lm_mix), lm_an 0 … 1 vom laufenden Licht auf die Karten. Die Karte hält, wie viel Licht
// ankommt (auf eine weiße, matte Fläche); die Farbe der Fläche kommt im Shader dazu. Abbildung Welt →
// Karte: u = dot((P, 1), lm_*_u), v = dot((P, 1), lm_*_v). Nur Flächen mit der Normalen der Karte
// (lm_n) nutzen sie – Laibungen von Fenster und Tür bleiben im laufenden Licht.
uniform float lm_an = 0.0;
uniform float lm_mix = 0.0;
uniform sampler2D lm_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D lm_b : hint_default_black, filter_linear, repeat_disable;
uniform vec4 lm_a_u = vec4(0.0);
uniform vec4 lm_a_v = vec4(0.0);
uniform vec4 lm_b_u = vec4(0.0);
uniform vec4 lm_b_v = vec4(0.0);
uniform vec3 lm_n = vec3(0.0, 1.0, 0.0);

// Nur der Backkamera fehlt diese Ebene (lichtbacken.gd BACK_LUECKE).
bool uz_backen(uint ebenen) {
	return (ebenen & (1u << 17u)) == 0u;
}

// Wo die Karte nichts sah (Fensteröffnung), ist sie durchsichtig: durch die Deckkraft geteilt, nimmt
// ein Punkt am Rand das Licht seiner Nachbarn statt Schwarz.
vec3 uz_lm_holen(sampler2D t, vec4 u, vec4 v, vec3 wp) {
	vec4 p = vec4(wp, 1.0);
	vec4 s = texture(t, vec2(dot(p, u), dot(p, v)));
	return max(s.rgb, vec3(0.0)) / max(s.a, 0.05);
}

vec3 uz_lm(vec3 wp) {
	vec3 a = lm_mix < 0.999 ? uz_lm_holen(lm_a, lm_a_u, lm_a_v, wp) : vec3(0.0);
	vec3 b = lm_mix > 0.001 ? uz_lm_holen(lm_b, lm_b_u, lm_b_v, wp) : vec3(0.0);
	return mix(a, b, lm_mix);
}

// Relief auf gebackenem Licht: Die Karte ist glatt (ein Wert je 2–6 cm); die Normalkarte der Fläche
// soll im Licht der Lampen und der Sonne trotzdem Struktur zeigen. Je Lampe (die kräftigsten,
// relief_pos: Ort, w = Stärke) und für die Sonne (fleck_dir, relief_sonne) wird verglichen, wie viel
// Licht die feine Normale gegenüber der glatten bekäme – das Verhältnis tönt die Karte (bis ±25 %). Die
// Sonne zählt nur zu einem Drittel (sie trifft nur den Fleck, die Karte weiß nicht, wo).
uniform int relief_n = 0;
uniform vec4 relief_pos[4];
uniform float relief_sonne = 0.0;

float uz_relief(vec3 wp, vec3 wn, vec3 n) {
	float b = 0.0001;
	float r = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= relief_n) {
			break;
		}
		vec3 d = relief_pos[i].xyz - wp;
		float dist2 = dot(d, d);
		vec3 l = d * inversesqrt(max(dist2, 0.0001));
		float nl = dot(wn, l);
		if (nl <= 0.0) {
			continue;
		}
		float w = relief_pos[i].w / (dist2 + 0.5);
		b += w * nl;
		r += w * (max(dot(n, l), 0.0) - nl);
	}
	float sl = dot(wn, -fleck_dir);
	if (relief_sonne > 0.0 && sl > 0.0) {
		float ws = relief_sonne * 0.33;
		b += ws * sl;
		r += ws * (max(dot(n, -fleck_dir), 0.0) - sl);
	}
	// Halb so stark wie das Verhältnis: Die Karte trägt auch Umgebung und Abprall, die die feine Normale
	// kaum sehen – voll wirkte der Putz grob und körnig.
	return 1.0 + clamp(r / b * 0.5, -0.25, 0.25);
}

float uz_lm_anteil(vec3 wn) {
	return lm_an * smoothstep(0.85, 0.95, dot(wn, lm_n));
}
