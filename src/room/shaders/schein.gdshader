// Lichtschein um Lampen (statt Glühen über den ganzen Bildschirm): kleine, zur Kamera gedrehte
// Flächen mit weichem Verlauf, ein Stück zur Kamera hin versetzt, damit der Schirm sie nicht
// anschneidet. Ein Netz je Lampe kann mehrere Scheine tragen (Lichterkette): Mitte im Eckpunkt,
// Ecke in UV (−1 … 1), Größe in UV2.x.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec3 farbe : source_color = vec3(1.0, 0.75, 0.5);
uniform float staerke = 0.0;

varying vec2 ecke;

void vertex() {
	vec3 mitte = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = UV2.x;
	vec3 zur_kamera = normalize(-mitte);
	mitte += zur_kamera * min(r * 0.7, max(length(mitte) - 0.1, 0.0));
	VERTEX = mitte + vec3(UV * r, 0.0);
	ecke = UV;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// Ein weicher Verlauf ohne exp (günstig auch bei Software-Grafik), außen genau null.
	float d = clamp(1.0 - dot(ecke, ecke), 0.0, 1.0);
	float a = d * d * d * (0.55 + 0.45 * d * d);
	ALBEDO = farbe * a * staerke;
}
