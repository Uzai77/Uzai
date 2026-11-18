// Gemeinsame Helfer der Start-Sequenzen je System (src/ui/components/system_intro.gd).
// Alles eigener Entwurf: nur Farbe, Material und Bewegungsart erinnern an die Konsole – keine
// nachgebauten Boot-Bilder, keine Logos, keine Schriftzüge (R4).
//
// Zeit t in Sekunden ab Start (0 … system_intro.DAUER); ab ruhe_ab wird das Bild ruhiger, damit
// Name oder Logo darüber Platz haben. Koordinaten aus ort(): Mitte 0, y nach oben, y in −1 … 1.
//
// Gemeinsame Regie für alle Sequenzen (hier, damit jede gleich gewinnt):
// - Kamera (in ort()): Sie fährt aus etwas Abstand heran und dreht sich dabei sacht ein (steht, wenn
//   der Name kommt); ab aus_ab fliegt sie durch das Bild hindurch in die Spielstart-Karte.
// - Höhepunkt (in fertig()): kurz vor dem Namen hebt sich das Licht, ein Glanz streift schräg über das
//   Bild – der Name erscheint im Licht (system_intro.gd lässt denselben Glanz über ihn laufen).
// - Teilchen (in fertig()): feiner Staub in drei Tiefen, der mit der Kamera zieht, in der Farbe des
//   Systems; nah weich und groß, fern klein und scharf.

uniform float t = 0.0;
uniform float aspect = 1.7778;
uniform vec4 sys_col = vec4(0.5, 0.55, 0.65, 1.0);
uniform vec4 acc_col = vec4(0.91, 0.76, 0.49, 1.0);
uniform float variante = 0.0;
uniform float ruhe_ab = 1.5;
uniform float aus_ab = 2.15;                 // ab hier fliegt die Kamera in die Karte (system_intro.AUS_AB)
uniform float dauer = 2.6;                   // Ende (system_intro.DAUER)
uniform float hoehepunkt = 1.36;             // der Höhepunkt (kurz vor dem Namen)
// Größe eines Bildpunkts in ort()-Einheiten: 2 / Höhe der Fläche in echten Bildpunkten (nicht in
// Einheiten der Oberfläche). system_intro.gd setzt sie in jedem Bild – so sind Kanten in 1080p, 1440p
// und 4K genau einen Bildpunkt weich, statt einen festen Anteil des Schirms (früher 0,004 Einheiten:
// 2 Bildpunkte in 1080p, 4 in 4K, dazu Linien als Gauß-Flecken – darum wirkte alles unscharf).
uniform float bildpunkt = 0.00185;

float sat(float x) { return clamp(x, 0.0, 1.0); }

float h11(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec2 h22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

float rauschen(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * rauschen(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Kurven: weich hinaus, weich hin und zurück, exponentiell, Sinus.
float e_out(float x) { x = sat(x); return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x); }
float e_in(float x) { x = sat(x); return x * x * x; }
float e_io(float x) { x = sat(x); return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5; }
float e_expo(float x) { x = sat(x); return x >= 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * x); }
float e_sin(float x) { return 0.5 - 0.5 * cos(PI * sat(x)); }
// Ein weicher Buckel: 0 → 1 → 0 zwischen a und b.
float buckel(float a, float b, float x) { return sin(PI * sat((x - a) / (b - a))); }

mat2 dreh(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Kamera: Maßstab (kleiner als 1 = näher dran). Heranfahren bis zum Namen, ab aus_ab durch das Bild.
float kamera_nah() {
	float ran = mix(1.13, 1.0, 1.0 - pow(1.0 - sat(t / 1.5), 3.0));
	float durch = mix(1.0, 0.7, pow(sat((t - aus_ab) / max(dauer - aus_ab, 0.01)), 2.0));
	return ran * durch;
}

vec2 ort(vec2 uv) {
	vec2 p = (uv - 0.5) * 2.0;
	p.x *= aspect;
	p.y = -p.y;
	// Kamera: fährt heran, dreht sich sacht ein (1,4° → 0), driftet zur Mitte.
	float ein = 1.0 - pow(1.0 - sat(t / 1.6), 3.0);
	p = dreh(0.024 * (1.0 - ein)) * p;
	p = p * kamera_nah() + vec2(0.035, 0.018) * (1.0 - ein);
	return p;
}

// Fläche mit Abstandsfeld d (innen negativ): Kante über genau einen Bildpunkt geglättet. bp ist die
// Größe eines Bildpunkts im Raum von d (verzerrte oder skalierte Räume: bildpunkt * Maßstab).
float kante_bp(float d, float bp) { return sat(0.5 - d / max(bp, 1e-6)); }
float kante(float d) { return kante_bp(d, bildpunkt); }
// Linie mit halber Breite hw (in Einheiten, wächst mit dem Bild), Kante einen Bildpunkt weich.
// Dünner als ein Bildpunkt wird sie blasser statt breiter – so flimmert sie nicht.
float strich_bp(float d, float hw, float bp) {
	float w = max(hw, bp * 0.5);
	return sat(0.5 + (w - abs(d)) / max(bp, 1e-6)) * (hw / w);
}
float strich(float d, float hw) { return strich_bp(d, hw, bildpunkt); }

// Licht: Gauß (weicher Kern) und Halo (weiter, weicher Schein). Für Kanten und feine Linien
// kante() und strich(); glanz() nur für Licht, das weich sein soll.
float glanz(float d, float w) { return exp(-(d * d) / (w * w)); }
float halo(float d, float w) { return w / (abs(d) + w); }

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sd_box3(vec3 p, vec3 b, float r) {
	vec3 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// Wie viel Ruhe am Ende (0 … 1): Platz für Name oder Logo.
float ruhe() { return smoothstep(ruhe_ab - 0.25, ruhe_ab + 0.45, t); }

// Weiches Knie über 0,8 statt hartem Abschneiden: Glühen brennt nicht flächig aus.
vec3 knie(vec3 c) {
	vec3 k = vec3(0.8);
	vec3 o = max(c - k, vec3(0.0));
	return mix(c, k + (1.0 - k) * (1.0 - exp(-o / (1.0 - k))), step(k, c));
}

// Dreieckiges Rauschen (±1 Stufe, im Mittel ±0,4/255), je Kanal eigen und blau verteilt
// (interleaved gradient noise), fest am Bildpunkt: bricht Stufen in dunklen Verläufen und im
// Schein, ohne zu körnen oder zu flimmern. (Früher: weißes Rauschen, für alle Kanäle gleich und in
// jedem Bild neu – Stufen blieben in Farbverläufen sichtbar, dazu ein leises Flimmern.)
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
vec3 zittern(vec2 fc) {
	vec3 a = vec3(ign(fc), ign(fc + vec2(17.0, 59.0)), ign(fc + vec2(83.0, 23.0)));
	vec3 b = vec3(ign(fc + vec2(41.0, 7.0)), ign(fc + vec2(5.0, 97.0)), ign(fc + vec2(67.0, 31.0)));
	return (a + b - 1.0) / 255.0;
}

// Staub in einer Tiefe z (1 nah … 0 fern): Zellen mit je höchstens einem Teilchen, das langsam
// steigt; mit der Kamera wandert es nach außen (nahe stärker). Rückgabe: Helligkeit.
float staub(vec2 uv, float z, float seed) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	p /= mix(1.0, kamera_nah(), 0.4 + 0.6 * z);
	float dichte = mix(5.0, 13.0, 1.0 - z);
	vec2 g = p * dichte + vec2(seed * 3.7, t * mix(0.12, 0.05, 1.0 - z) * dichte * 0.2);
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float r = h21(id + seed * 11.0);
	if (r < 0.55) {
		return 0.0;
	}
	vec2 o = (h22(id + seed * 5.3) - 0.5) * 0.7 + 0.1 * vec2(sin(t * 0.7 + r * 30.0), cos(t * 0.6 + r * 20.0));
	float bp_z = bildpunkt * dichte * 0.5;
	float gr = mix(0.6, 3.2, z * z) * bp_z * (0.6 + 0.8 * h21(id + 3.1));
	float weich = mix(1.0, 3.5, z) * bp_z;
	float d = length(f - o);
	float funkeln = 0.6 + 0.4 * sin(t * (1.5 + r * 3.0) + r * 50.0);
	return smoothstep(gr + weich, gr - weich * 0.3, d) * funkeln * mix(0.9, 0.35, z);
}

// Höhepunkt: 0 → 1 → 0 um hoehepunkt (Licht hebt sich, dann setzt es sich).
float hoch() {
	float x = (t - hoehepunkt + 0.22) / 0.62;
	return x > 0.0 && x < 1.0 ? pow(sin(PI * x), 2.0) * (1.0 - 0.35 * x) : 0.0;
}

// Abschluss: Randabdunklung, Höhepunkt (Licht und Glanz), Staub, Durchflug, Knie, Zittern gegen
// Farbstufen in Verläufen.
vec3 fertig(vec3 c, vec2 uv, vec2 fc, float vig) {
	vec2 d = (uv - 0.5) * vec2(1.0, 1.15);
	c *= 1.0 - vig * smoothstep(0.2, 0.85, length(d));
	// Höhepunkt: Das Licht hebt sich, ein breiter Glanz streift schräg von links nach rechts.
	float h = hoch();
	float lauf = (t - hoehepunkt + 0.3) / 0.75;
	float spur = uv.x * 1.25 - (1.0 - uv.y) * 0.35;
	float glanz_b = lauf > 0.0 && lauf < 1.0 ? exp(-pow((spur - mix(-0.45, 1.3, lauf)) / 0.14, 2.0)) * sin(PI * lauf) : 0.0;
	vec3 licht_f = mix(sys_col.rgb, vec3(1.0), 0.6);
	c *= 1.0 + 0.32 * h + 0.55 * glanz_b;
	c += licht_f * (0.045 * h * (1.0 - smoothstep(0.1, 0.9, length(d))) + 0.05 * glanz_b);
	// Staub in drei Tiefen, in der Farbe des Systems (auf hellem Grund kaum sichtbar, wie Licht).
	float st = staub(uv, 0.15, 1.0) * 0.55 + staub(uv, 0.5, 2.0) * 0.45 + staub(uv, 0.95, 3.0) * 0.3;
	c += mix(sys_col.rgb, vec3(1.0), 0.45) * st * 0.22 * smoothstep(0.15, 0.7, t) * (1.0 - 0.45 * ruhe());
	// Durchflug in die Karte: das Licht hebt sich zur Mitte hin, während alles ausblendet.
	float durch = sat((t - aus_ab) / max(dauer - aus_ab, 0.01));
	c += licht_f * durch * durch * 0.12 * exp(-dot(d, d) * 5.0);
	c = knie(max(c, vec3(0.0)));
	c += zittern(fc);
	return c;
}
