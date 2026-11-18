// Lichtstrahl durchs Fenster: ein weicher Fake statt Volumen-Nebel. Die Form ist das Fenster,
// entlang der Sonnenrichtung bis zum Boden gezogen (raum.gd baut sie). Vorder- und Rückseite
// addieren sich, Flächen, auf die man von der Kante schaut, verschwinden – so wirkt es wie Licht
// im Raum, ohne harte Ränder. Am Fenster am dichtesten, zum Boden hin aus; dazu feiner Staub, der
// langsam treibt. v (UV.y) läuft vom Fenster (0) zum Boden (1), u (UV.x) einmal um den Strahl.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/room/shaders/rauschen.gdshaderinc"

uniform vec3 farbe : source_color = vec3(1.0, 0.8, 0.55);
uniform float staerke = 0.0;
uniform float staub = 0.35;
uniform float oben = 0.0;     // Blick von oben: der Strahl läge über dem halben Raum – nur ein Hauch

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Mit MSAA liegen Proben am Rand außerhalb des Dreiecks: v knapp über 1 gab pow() einer negativen
	// Zahl (NaN) – eine schwarz gestrichelte Linie, wo der Strahl auf den Boden trifft.
	float v = clamp(UV.y, 0.0, 1.0);
	float kante = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float laengs = smoothstep(0.0, 0.08, v) * pow(1.0 - v, 1.7);
	// Weiche Ränder rund um den Strahl (je Seite der Rand in u).
	float rand = smoothstep(0.0, 0.08, fract(UV.x)) * smoothstep(1.0, 0.92, fract(UV.x));
	float s = uz_noise3(wp * 2.2 + vec3(0.0, TIME * 0.05, TIME * 0.03)) * 0.5 + 0.75;
	float k = uz_noise3(wp * 34.0 + vec3(TIME * 0.11, TIME * 0.07, 0.0));
	// Staubkörner nur, wo sie größer als ein Bildpunkt sind – kleiner funkelten sie als Flimmern.
	vec3 kfw = fwidth(wp * 34.0);
	float korn = smoothstep(0.93, 0.995, k) * staub * (1.0 - smoothstep(0.25, 0.6, max(kfw.x, max(kfw.y, kfw.z))));
	// Nah an der Kamera ausblenden (man steht im Strahl).
	float nah = smoothstep(0.25, 1.1, length(wp - CAMERA_POSITION_WORLD));
	ALBEDO = farbe * staerke * (kante * laengs * rand * s * 0.06 + korn * laengs * rand * 0.04) * nah * mix(1.0, 0.3, oben);
}
