// Stoff eines fremden Modells (assets/zimmer/modelle, CC0 / CC BY 4.0) in Wunschfarbe: die
// Grundfarbkarte des Modells gibt nur die Helligkeit (Falten, Nähte, Abrieb), die Farbe kommt aus
// dem Katalog bzw. dem Anpassen. Normal-, Rauheits- und AO-Karten des Modells bleiben; dazu ein
// weicher Samtglanz an den Kanten (Sheen), den der Importer sonst weglässt.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform sampler2D t_farbe : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D t_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D t_rau : hint_default_white, filter_linear_mipmap;
uniform sampler2D t_ao : hint_default_white, filter_linear_mipmap;
uniform vec3 farbe : source_color = vec3(0.6, 0.6, 0.6);
uniform float mittel = 0.5;        // mittlere Helligkeit der Grundfarbkarte
uniform float normal_an = 0.0;
uniform float rau_an = 0.0;
uniform int rau_kanal = 1;         // 0 R, 1 G, 2 B, 3 A
uniform float rauheit = 0.9;
uniform float ao_an = 0.0;
uniform int ao_kanal = 0;
uniform float sheen = 0.35;

float kanal(vec4 t, int k) {
	return k == 0 ? t.r : (k == 1 ? t.g : (k == 2 ? t.b : t.a));
}

void fragment() {
	vec3 t = texture(t_farbe, UV).rgb;
	float l = dot(t, vec3(0.3, 0.59, 0.11)) / max(mittel, 0.02);
	vec3 c = farbe * clamp(l, 0.0, 2.5);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c + c * fres * sheen;
	if (normal_an > 0.5) {
		NORMAL_MAP = texture(t_normal, UV).xyz;
		NORMAL_MAP_DEPTH = 1.0;
	}
	ROUGHNESS = rau_an > 0.5 ? clamp(kanal(texture(t_rau, UV), rau_kanal) * rauheit, 0.2, 1.0) : rauheit;
	if (ao_an > 0.5) {
		AO = kanal(texture(t_ao, UV), ao_kanal);
		AO_LIGHT_AFFECT = 0.5;
	}
	SPECULAR = 0.3;
}
