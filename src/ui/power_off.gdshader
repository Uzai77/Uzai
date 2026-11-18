shader_type canvas_item;
// Ausschalten (src/ui/power_off.gd): Das Bild der Oberfläche tritt zurück, fällt wie bei einem
// Röhrenfernseher zu einer hellen Linie zusammen, die Linie zieht sich zum Punkt zusammen – und der
// Punkt ist der Uzai-Punkt im Akzent, der noch kurz leuchtet und dann verglimmt. Die Form ist ein
// abgerundetes Rechteck um die Mitte (Bild → Linie → Kapsel → Kreis), ihre Kante ist genau einen
// echten Bildpunkt weich. Die Zeitpunkte rechnet power_off.gd (zustand); hier wird nur gezeichnet.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 groesse = vec2(1920.0, 1080.0);  // Fläche in Einheiten der Oberfläche
uniform float px_e = 1.0;                     // Einheiten je echtem Bildpunkt
uniform float u = 1.0;                        // Maßstab (Höhe / 1080)
uniform float zoom = 1.0;                     // Bild tritt zurück
uniform float sx = 1.0;                       // Breite des Bilds (Anteil)
uniform float sy = 1.0;                       // Höhe des Bilds (Anteil)
uniform float dicke = 0.0;                    // Mindest-Halbhöhe der Form (Linie, dann Punkt)
uniform float ecke = 0.0;                     // Rundung der Ecken
uniform float dunkel = 0.0;                   // Bild dunkler (0 … 1)
uniform float phosphor = 0.0;                 // Bild wird hell wie Leuchtstoff (0 … 1)
uniform float punkt = 0.0;                    // Farbe geht in den Akzent über (0 … 1)
uniform float schein = 0.0;                   // Licht um die Form
uniform float form_a = 1.0;                   // Deckkraft der Form
uniform float ruhe_punkt = 0.0;               // ruhige Fassung: der Punkt allein in der Mitte
uniform float punkt_r = 15.0;                 // Halbmesser des Punkts
uniform float schwarz = 0.0;                  // Schwarz über allem (Ende, Abkürzen)
uniform float vorschau = 0.0;                 // 1: ein ruhiges Ersatzbild statt des Bildschirms
uniform vec4 raum : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 akzent : source_color = vec4(0.72, 0.65, 0.94, 1.0);
uniform float fade = 1.0;                     // Deckkraft des Ganzen (reveal)

float sat(float x) { return clamp(x, 0.0, 1.0); }

// Licht in linearem Licht addiert, Ausgabe mit dreieckigem, blau verteiltem Rauschen (±1 Stufe):
// der Schein um Linie und Punkt läuft ohne Stufen ins Schwarz aus (wie in boot.gdshader).
vec3 lin(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 srgb(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
vec3 dither(vec2 fc) {
	vec3 a = vec3(ign(fc), ign(fc + vec2(17.0, 59.0)), ign(fc + vec2(83.0, 23.0)));
	vec3 b = vec3(ign(fc + vec2(41.0, 7.0)), ign(fc + vec2(5.0, 97.0)), ign(fc + vec2(67.0, 31.0)));
	return (a + b - 1.0) / 255.0;
}

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Vorschau in den Einstellungen: ein ruhiges Bild in Graphit mit einem Schimmer im Akzent.
vec3 ersatz(vec2 uv) {
	vec3 c = mix(vec3(0.11, 0.11, 0.13), vec3(0.06, 0.06, 0.07), uv.y);
	c += akzent.rgb * 0.18 * exp(-dot(uv - vec2(0.3, 0.35), uv - vec2(0.3, 0.35)) * 9.0);
	float zeile = step(0.62, uv.y) * step(uv.y, 0.66) * step(0.1, uv.x) * step(uv.x, 0.55);
	return mix(c, vec3(0.85), zeile * 0.5);
}

void fragment() {
	vec2 pos = (UV - 0.5) * groesse;
	vec3 hell = vec3(0.93, 0.95, 1.0);
	vec2 halb = max(groesse * 0.5 * zoom * vec2(sx, sy), vec2(dicke));
	float r = min(max(ecke, dicke), min(halb.x, halb.y));
	float d = sd_rbox(pos, halb, r);
	float innen = sat(0.5 - d / px_e);
	// Inhalt: der Bildschirm, gestaucht. Ist er sehr flach, aus gröberen Stufen (kein Flimmern).
	vec2 q = pos / max(groesse * zoom * vec2(sx, sy), vec2(1e-3));
	vec2 suv = clamp(q + 0.5, vec2(0.001), vec2(0.999));
	float lod = clamp(log2(1.0 / max(sy, 1e-3)) - 1.0, 0.0, 7.0);
	vec3 bild = vorschau > 0.5 ? ersatz(suv) : textureLod(screen_tex, suv, lod).rgb;
	bild *= 1.0 - dunkel * (0.75 + 0.25 * sat(dot(q, q) * 4.0));
	bild = mix(bild, hell, phosphor);
	bild = mix(bild, akzent.rgb, punkt);
	vec3 c = lin(raum.rgb);
	// Licht um die Form: eng und hell, dazu ein weiter, leiser Hof.
	float aussen = max(d, 0.0);
	vec3 licht = lin(mix(hell, akzent.rgb, punkt));
	c += licht * schein * (0.3 * exp(-(aussen * aussen) / (64.0 * u * u)) + 0.02 * exp(-aussen / (60.0 * u)));
	c = mix(c, lin(bild), innen * form_a);
	// Ruhige Fassung: der Punkt allein, ohne Bewegung.
	if (ruhe_punkt > 0.0) {
		float dp = length(pos) - punkt_r;
		c += lin(akzent.rgb) * ruhe_punkt * 0.03 * exp(-max(dp, 0.0) / (24.0 * u));
		c = mix(c, lin(akzent.rgb), sat(0.5 - dp / px_e) * ruhe_punkt);
	}
	c = mix(c, vec3(0.0), schwarz);
	// Wo das Bild unverändert steht (erstes Bild), kein Rauschen: die Oberfläche bleibt genau gleich.
	float still = innen * form_a * (1.0 - step(0.001, dunkel + phosphor + punkt + schwarz + abs(1.0 - zoom)));
	COLOR = vec4(srgb(c) + dither(FRAGCOORD.xy) * (1.0 - still), fade);
}
