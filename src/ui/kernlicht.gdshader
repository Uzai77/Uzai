shader_type canvas_item;
// Material „Kernlicht“ (docs/DESIGN.md, Premium-Durchgang): Schwebende Flächen – Guide,
// Schnellmenü, Seitenleisten, Dialoge – sind mattes Graphit im Licht des Kerns, nicht flaches Grau.
// Das Material liegt nur auf der Fläche selbst (der StyleBox der Ebene); Schrift und Bauteile darauf
// haben ihr eigenes Material und bleiben unberührt. UzTheme.kernlicht() setzt es, U.aufglanz()
// lässt die Lichtkante beim Ankommen einmal aufglänzen.
//
// Vier Dinge, deutlich, aber matt (kein Glas, kein Neon):
// 1. Licht von oben: oben heller, nach unten in die Tiefe, unten ein weicher Schatten nach innen.
// 2. Akzent von der Lichtquelle (oben, zur Mitte des Schirms hin): ein heller Kern, weit auslaufend.
// 3. Eine klare Lichtkante oben, zu den Seiten auslaufend, unter dem Licht am hellsten; dazu eine
//    feine Kante an der Seite, die zur Lampe zeigt.
// 4. Feines Korn, fest am Bildpunkt: bricht Stufen im Verlauf und gibt der Fläche Material.
// Schatten und Kantenglättung außerhalb der Fläche bleiben, wie sie sind.

uniform vec2 groesse = vec2(600.0, 400.0);    // Größe der Fläche (Einheiten der Oberfläche)
uniform vec2 licht = vec2(0.5, -0.12);        // Lichtquelle in Anteilen der Fläche (y < 0: über ihr)
uniform vec4 akzent : source_color = vec4(0.72, 0.65, 0.94, 1.0);
uniform vec4 tinte : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform float hell = 0.0;                     // 1: helles Schema
uniform float staerke = 1.0;                  // 0 … 1 (Theme flach: weniger)
uniform float kante_oben = 1.0;               // 1: weiche Lichtkante oben
uniform float glanz = -1.0;                   // Lage des Glanzes auf der Kante (−0,4 … 1,4; < −0,5 aus)
uniform float einheit = 1.0;                  // echte Bildpunkte je Einheit (4K mit Streckung: 2)
uniform float rund = 0.0;                     // Eckenradius der Fläche (Einheiten): außerhalb der Rundung kein Licht
// Otherwise the light in the corners hits the shadow that still lies inside the rectangle there, leaving a small
// angular edge around the rounded corners (visible on the call window).

varying vec2 lokal;

void vertex() {
	lokal = VERTEX;
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec4 c = COLOR;
	vec2 g = max(groesse, vec2(1.0));
	vec2 uv = lokal / g;
	// Abstand zur gerundeten Fläche (< 0 innen); auf der Kante weich, damit die Rundung glatt bleibt.
	float r = clamp(rund, 0.0, 0.5 * min(g.x, g.y));
	vec2 q = abs(lokal - 0.5 * g) - (0.5 * g - vec2(r));
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	float innen = clamp(0.5 - sd * einheit, 0.0, 1.0);
	if (c.a > 0.0 && innen > 0.0 && uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		vec3 roh = c.rgb;
		float k = staerke;
		float dunkel = 1.0 - hell;
		vec3 col = c.rgb;
		// 1. Licht von oben, Tiefe nach unten (unten zusätzlich ein weicher Schatten nach innen).
		float oben = pow(1.0 - uv.y, 2.0);
		col = mix(col, mix(tinte.rgb, vec3(1.0), hell), (0.1 * dunkel + 0.32 * hell) * oben * k);
		col *= 1.0 - (0.24 * dunkel + 0.06 * hell) * smoothstep(0.25, 1.0, uv.y) * k;
		col *= 1.0 - 0.12 * dunkel * exp(-(g.y - lokal.y) / 36.0) * k;
		// 2. Kernlicht: Akzent von der Lichtquelle – ein heller Kern dicht an ihr, weit auslaufend.
		float weite = 0.75 * min(max(g.x, g.y), 1100.0);
		float d = length((uv - licht) * g) / weite;
		float schein = exp(-d * d) * 0.8 + 0.2 * exp(-d * 0.9);
		float kern = exp(-d * d * 6.0);
		col += akzent.rgb * (schein * 0.15 + kern * 0.07) * dunkel * k;
		col = mix(col, akzent.rgb, (schein * 0.06 + kern * 0.04) * hell * k);
		// 3. Lichtkante oben (in echten Bildpunkten: in 4K genauso fein), unter dem Licht am hellsten,
		// zu den Seiten auslaufend; dazu eine feine Kante an der Seite, die zur Lampe zeigt.
		float y_px = lokal.y * einheit;
		float band = exp(-y_px / 1.1) + 0.3 * exp(-y_px / 9.0);
		float seiten = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
		float unter_licht = 0.5 + 0.5 * exp(-pow((uv.x - licht.x) * 2.0, 2.0));
		float gl = glanz > -0.5 ? exp(-pow((uv.x - glanz) * g.x / 150.0, 2.0)) : 0.0;
		float kante = band * (seiten * unter_licht + 2.6 * gl) * kante_oben;
		col = mix(col, mix(tinte.rgb, vec3(1.0), 0.45), clamp(kante * 0.4 * dunkel * k, 0.0, 0.75));
		float zur_lampe = licht.x > 0.6 ? (g.x - lokal.x) : (licht.x < 0.4 ? lokal.x : 1e5);
		float rand = exp(-zur_lampe * einheit / 1.1) * pow(1.0 - uv.y, 1.5) * kante_oben;
		col = mix(col, tinte.rgb, clamp(rand * 0.22 * dunkel * k, 0.0, 0.5));
		// Der Glanz streift beim Ankommen auch die obere Fläche.
		col += tinte.rgb * gl * exp(-lokal.y / 110.0) * 0.045 * dunkel * k;
		// 4. Korn (dreieckig, gut ±2 Stufen), fest am Bildpunkt.
		float n = ign(FRAGCOORD.xy) + ign(FRAGCOORD.xy + vec2(37.0, 17.0)) - 1.0;
		col += vec3(n * (2.2 * dunkel + 0.8 * hell) / 255.0);
		c.rgb = mix(roh, col, innen);
	}
	COLOR = c;
}
