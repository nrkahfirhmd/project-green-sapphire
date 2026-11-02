shader_type canvas_item;
// The scene-change iris: everything outside a circle is Deep Moss, with a
// thin Sapphire Core ring at its edge. Game.go() closes it onto the player
// (or the screen's middle), swaps the scene, and opens it again.

uniform float radius = 1.5;                 // in screen heights
uniform vec2 centre = vec2(0.5, 0.5);       // in screen UV
uniform vec4 moss : source_color = vec4(0.231, 0.286, 0.224, 1.0);
uniform vec4 core : source_color = vec4(0.412, 0.627, 0.384, 1.0);

void fragment() {
	vec2 d = SCREEN_UV - centre;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;    // circles, not ovals
	float r = length(d);
	float outside = smoothstep(radius, radius + 0.003, r);
	float ring = smoothstep(radius - 0.008, radius, r) * (1.0 - outside) * step(0.002, radius);
	COLOR = mix(vec4(core.rgb, ring), moss, outside);
}
