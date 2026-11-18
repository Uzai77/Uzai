// Auswahl im Zimmer: warmes Glimmen im Akzent an den Kanten (wie das Glimmen um die Auswahl im
// Menü), als zweiter Durchgang über dem Material. Die Hülle liegt ein paar Millimeter außen auf dem
// Möbel: auf genau derselben Fläche kämpfte sie mit ihr um die Tiefe und flackerte (vor allem im
// Bauen, von weit oben).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 farbe : source_color = vec3(0.906, 0.761, 0.49);
uniform float staerke = 0.0;

void vertex() {
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = farbe * (fres * 0.85 + 0.06) * staerke;
}
