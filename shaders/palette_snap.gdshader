shader_type canvas_item;
// Last thing drawn, over the world, HUD and iris alike. Every pixel takes the
// nearest of the four art roles, so soft text edges and translucent panels can't
// leak a fifth colour, and then shows as that role's screen colour.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 screen_palette[4];           // set from Game.SCREEN_PALETTE by Post

const vec3 ROLES[4] = vec3[](
	vec3(0.10588, 0.12941, 0.10196),   // Deep Moss
	vec3(0.38431, 0.50588, 0.25490),   // Floor
	vec3(0.54510, 0.68235, 0.40000),   // Sapphire Core
	vec3(0.92157, 0.83529, 0.67059));  // Pale Jade

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	int best = 0;
	for (int i = 1; i < 4; i++) {
		if (distance(c, ROLES[i]) < distance(c, ROLES[best])) best = i;
	}
	COLOR = vec4(screen_palette[best], 1.0);
}
