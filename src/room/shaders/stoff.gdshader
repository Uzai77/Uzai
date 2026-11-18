// Stoff: feines Gewebe, weicher Samtschimmer an den Kanten (Licht streift die Fasern), keine
// harten Glanzlichter. leuchten > 0: von innen beleuchtet (Lampenschirm). Still – Vorhänge, die im
// Luftzug wehen, nutzen stoff_wehen.gdshader (TIME im Vertex-Teil: die Engine hält jeden
// Schattenwerfer mit so einem Shader für bewegt und zeichnet die Schatten der Lichter um ihn in jedem
// Bild neu).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/room/shaders/stoff_kern.gdshaderinc"
