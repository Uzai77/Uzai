// Stoff, der im Luftzug weht (Vorhänge, raum.gd): wie stoff.gdshader, der Saum bewegt sich (wehen,
// wehen_hoehe). Eigener Shader, weil nur er TIME im Vertex-Teil nutzt (siehe stoff.gdshader). Ohne
// empfangene Schatten: Die weichen Schatten der Engine streuen ihre Proben je Bildpunkt (ohne TAA ein
// festes Rauschen) – auf dem bewegten Stoff tanzte es und das Fenster flackerte ständig.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, shadows_disabled;

#define WEHEN
#include "res://src/room/shaders/stoff_kern.gdshaderinc"
