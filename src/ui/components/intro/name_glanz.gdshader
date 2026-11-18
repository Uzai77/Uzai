shader_type canvas_item;
// Glanz über Name bzw. Logo am Ende der Start-Sequenz (system_intro.gd): ein schmales, schräges
// Licht streift einmal von links nach rechts darüber – das Echo des Höhepunkts im Bild. Es hellt nur
// auf, was gezeichnet ist (Schrift, Logo, Linie); dunkle Schrift wird dabei eine Spur heller.

uniform float lage = -1.0;     // Mitte des Glanzes in Anteilen der Breite (−0,3 … 1,3; < −0,5 aus)
uniform float breite = 0.06;   // halbe Breite (Anteil der Breite)
uniform float staerke = 0.7;

void fragment() {
	vec4 c = COLOR;
	if (lage > -0.5) {
		float x = SCREEN_UV.x + (SCREEN_UV.y - 0.5) * 0.18;
		float g = exp(-pow((x - lage) / breite, 2.0)) * staerke;
		c.rgb = mix(c.rgb, vec3(1.0), clamp(g, 0.0, 1.0) * (0.55 + 0.45 * (1.0 - dot(c.rgb, vec3(0.333)))) * 0.85);
	}
	COLOR = c;
}
