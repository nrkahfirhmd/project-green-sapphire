shader_type canvas_item;
// Dither post-process for the world layer. Reads what the code-drawn rigs put
// on screen and redraws it in chunky pixels through a 4x4 Bayer matrix, in the
// four palette colours and nothing else. Smooth alpha ramps in the scenery
// come out as thickening stipple. The HUD and touch controls sit on a higher
// CanvasLayer; palette_snap.gdshader holds them to the same four colours.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// Size of one dither pixel, in viewport pixels. Snapped to whole screen pixels,
// which is what keeps the pattern crisp.
uniform float pixel = 3.0;

// Post effects, set every frame by the Post autoload (scripts/post.gd). They
// all move a pixel's tone or threshold, never its colour, so the palette holds.
// Shockwave: a ring of tone running out from `shock_at` (screen UV), pulling
// what it crosses outward as it passes.
uniform vec2 shock_at = vec2(0.5);
uniform float shock_t = 1.0;       // 0 at the blast .. 1 spent
uniform float shock_r = 0.7;       // final radius, in screen heights
// Impact: blocks round `hit_at` flicker through random tones.
uniform vec2 hit_at = vec2(0.5);
uniform float hit_k = 0.0;         // 0..1, falls off fast
uniform float hit_r = 0.13;        // in screen heights
// Scene change: 0 shown .. 1 every block dithered away to nothing.
uniform float fade = 0.0;
// Low health: the screen edges breathe into solid INK.
uniform float pulse = 0.0;
// Phosphor: last frame's bright pixels linger, each surviving at odds `glow_k`.
uniform sampler2D prev_tex : filter_nearest;
uniform float glow_k = 0.0;
// That last frame is already in screen colours, so reading it needs them.
uniform vec3 screen_palette[4];

// The art is always drawn in these four fixed roles, chosen far enough apart to
// be told apart when mixed by alpha. What they look like on screen is set in one
// place, Game.SCREEN_PALETTE; palette_snap.gdshader does the swap.
const vec3 INK = vec3(0.10588, 0.12941, 0.10196);   // Deep Moss
const vec3 MID = vec3(0.38431, 0.50588, 0.25490);   // Floor
const vec3 PALE = vec3(0.54510, 0.68235, 0.40000);   // Sapphire Core
const vec3 CREAM = vec3(0.92157, 0.83529, 0.67059);   // Pale Jade

// Where the floor colour sits on the line from INK to PALE, so a floor painted
// that colour comes out solid, not stippled.
const float MID_AT = 0.64;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

// Everything drawn is INK, PALE and CREAM mixed by alpha, so a pixel is
// INK + a * (PALE - INK) + b * (CREAM - INK); this solves for (a, b). Then b is
// how much cream lies over it and a / (1 - b) is the tone underneath, which keeps
// a translucent telegraph apart from the floor it lies on.
vec2 unmix(vec3 c) {
	vec3 d = c - INK;
	vec3 u = PALE - INK;
	vec3 w = CREAM - INK;
	float uu = dot(u, u);
	float uw = dot(u, w);
	float ww = dot(w, w);
	float du = dot(d, u);
	float dw = dot(d, w);
	float det = uu * ww - uw * uw;
	float b = clamp((uu * dw - uw * du) / det, 0.0, 1.0);
	// the two lines are close in direction, so with no cream left, read tone off
	// its own line or a flat green leaks into a false tone
	float a = b > 0.0 ? (ww * du - uw * dw) / det : du / uu;
	return vec2(clamp(a / max(1.0 - b, 0.05), 0.0, 1.0), b);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// the viewport is 900 tall (stretch "expand" keeps it), so this converts
	// viewport pixels to screen pixels on any device
	float px = max(1.0, round(pixel * (1.0 / SCREEN_PIXEL_SIZE.y) / 900.0));
	vec2 dot_id = floor(FRAGCOORD.xy / px);
	vec2 block = floor(dot_id / 4.0);
	ivec2 b = ivec2(dot_id - block * 4.0);
	float th = (BAYER[b.y * 4 + b.x] + 0.5) / 16.0;
	vec2 asp = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);   // UV -> screen heights
	vec2 duv = (dot_id + 0.5) * px * SCREEN_PIXEL_SIZE;

	float ring = 0.0;
	vec2 push = vec2(0.0);
	if (shock_t < 1.0) {
		vec2 v = (duv - shock_at) * asp;
		float w = 0.04 + 0.05 * shock_t;
		ring = exp(-pow((length(v) - shock_t * shock_r) / w, 2.0)) * (1.0 - shock_t);
		push = -normalize(v + 1e-5) / asp * ring * 0.025;
	}

	// 2x2 samples so thin lines (swing arc, ring pulse) still land in the pixels
	// they cross. Lean on the peak so outlines don't drag a solid limb to stipple.
	vec2 sum = vec2(0.0);    // x = tone, y = cream
	vec2 peak = vec2(0.0);
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			vec2 uv = (dot_id + (vec2(float(x), float(y)) + 0.5) / 2.0) * px * SCREEN_PIXEL_SIZE + push;
			vec2 m = unmix(texture(screen_tex, uv).rgb);
			sum += m;
			peak = max(peak, m);
		}
	}
	vec2 mixed = mix(sum / 4.0, peak, 0.5);
	float tone = mixed.x + ring * 0.8;
	float cream = mixed.y;

	if (hit_k > 0.0) {
		float tick = floor(TIME * 24.0);
		float k = hit_k * (1.0 - length((duv - hit_at) * asp) / hit_r);
		if (hash(block + tick) < k) {
			th = hash(dot_id + tick);
			tone = hash(block * 2.3 + tick);
			cream = hash(block * 0.7 + tick) < 0.35 ? tone : 0.0;
		}
	}
	if (pulse > 0.0) {
		float edge = smoothstep(0.55, 1.3, length((duv - 0.5) * 2.0));
		tone *= 1.0 - pulse * edge;
	}
	if (glow_k > 0.0 && hash(dot_id + fract(TIME) * 97.0) < glow_k) {
		// four colours can't hold a fading tone from frame to frame, so a trail
		// decays by chance: each pixel of it survives a frame at odds of glow_k
		vec3 prev = texture(prev_tex, duv).rgb;
		int near = 0;
		for (int i = 1; i < 4; i++) {
			if (distance(prev, screen_palette[i]) < distance(prev, screen_palette[near])) near = i;
		}
		tone = max(tone, (near == 0 ? 0.0 : near == 1 ? MID_AT : 1.0) * 0.85);
	}
	if (fade > 0.0) {
		// each block thins out in its own order
		float keep = 1.0 - clamp(fade * 1.5 - hash(block * 3.7) * 0.5, 0.0, 1.0);
		tone *= keep;
		cream *= keep;
	}

	vec3 outc;
	if (cream > th) {
		// cream is laid over whatever is below it, straight, skipping the greens:
		// a telegraph can't be mistaken for scenery at any alpha
		outc = CREAM;
	} else if (tone < MID_AT) {
		// Faint scenery drops out to clean INK, so the dark is a rest for the eye
		// and not a field of noise; only stronger shapes break into stipple.
		float x = clamp((tone / MID_AT - 0.2) / 0.8, 0.0, 1.0);
		outc = pow(x, 1.5) > th ? MID : INK;
	} else {
		outc = (tone - MID_AT) / (1.0 - MID_AT) > th ? PALE : MID;
	}
	COLOR = vec4(outc, 1.0);
}
