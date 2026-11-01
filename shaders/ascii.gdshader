shader_type canvas_item;
// ASCII post-process for the world layer. Reads what the code-drawn rigs put on
// screen, splits it into character cells, and redraws each cell as one glyph:
// brightness picks how dense the glyph is, the brightest pixel picks its green.
// The HUD and touch controls sit on a higher CanvasLayer and are untouched.
//
// Glyphs are 3x4 bitmaps packed into ints, so no font asset is needed. Small
// on purpose: at one screen pixel per glyph pixel a 4x5 cell is fine enough
// for a 30 px key to keep its bow, shaft and bit.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// Size of one glyph pixel, in viewport pixels. 1 is the smallest the glyphs
// can go and stay crisp; 2 doubles them. It is snapped to whole screen pixels,
// which is what keeps a glyph sharp at this size.
uniform float pixel = 1.0;
// The Mirror's arena: the void past the floor goes black too, not just shadows.
uniform bool black_void = false;

// Post effects, set every frame by the Post autoload (scripts/post.gd). They
// all work in glyph space, on which glyph a cell shows and when, never on
// colour, so the three greens stay the only colours on screen.
// Shockwave: a ring of glyph density running out from `shock_at` (screen UV),
// pulling what it crosses outward as it passes.
uniform vec2 shock_at = vec2(0.5);
uniform float shock_t = 1.0;       // 0 at the blast .. 1 spent
uniform float shock_r = 0.7;       // final radius, in screen heights
// Impact: cells round `hit_at` flicker through random glyphs.
uniform vec2 hit_at = vec2(0.5);
uniform float hit_k = 0.0;         // 0..1, falls off fast
uniform float hit_r = 0.13;        // in screen heights
// Scene change: 0 shown .. 1 every cell thinned rung by rung down to nothing.
uniform float fade = 0.0;
// Low health: the screen edges breathe into SHADE.
uniform float pulse = 0.0;
// Phosphor: last frame's bright glyphs linger, keeping `glow_k` a frame.
uniform sampler2D prev_tex : filter_nearest;
uniform float glow_k = 0.0;
const vec2 CELL = vec2(4.0, 5.0);   // 3x4 glyph + 1 column and 1 row of gap

const vec3 MOSS = vec3(0.231, 0.286, 0.224);
const vec3 CORE = vec3(0.412, 0.627, 0.384);
const vec3 JADE = vec3(0.733, 0.886, 0.714);
const vec3 SHADE = vec3(0.141, 0.184, 0.137);   // #243023, under ground shadows

// one 3-bit row per argument, top row first, leftmost column = high bit
int pack(int a, int b, int c, int d) {
	return (a << 9) | (b << 6) | (c << 3) | d;
}

// density ramp, 1 = sparsest
int ramp(int i) {
	if (i == 1) return pack(0, 0, 0, 2);            // .
	if (i == 2) return pack(0, 2, 0, 2);            // :
	if (i == 3) return pack(0, 0, 7, 0);            // -
	if (i == 4) return pack(0, 7, 0, 7);            // =
	if (i == 5) return pack(0, 2, 7, 2);            // +
	if (i == 6) return pack(5, 2, 5, 2);            // *
	if (i == 7) return pack(5, 7, 5, 7);            // #
	if (i == 8) return pack(7, 5, 7, 5);            // %
	return pack(7, 5, 7, 7);                        // @
}

// How far c sits along the line from Deep Moss to `to` (0..1), and how far off
// that line it is. Everything on screen is one of the greens, or a translucent
// one over Deep Moss, so each pixel lies on one of these two lines.
vec2 fit(vec3 c, vec3 to) {
	vec3 v = to - MOSS;
	float k = clamp(dot(c - MOSS, v) / dot(v, v), 0.0, 1.0);
	return vec2(k, length(c - (MOSS + v * k)));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// the viewport is 900 tall (stretch "expand" keeps it), so this converts
	// viewport pixels to screen pixels on any device
	float px = max(1.0, round(pixel * (1.0 / SCREEN_PIXEL_SIZE.y) / 900.0));
	vec2 cell = CELL * px;
	vec2 gpix = floor(FRAGCOORD.xy / px);
	vec2 id = floor(gpix / CELL);
	ivec2 gp = ivec2(gpix - id * CELL);
	vec2 asp = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);   // UV -> screen heights
	vec2 cuv = (id + 0.5) * cell * SCREEN_PIXEL_SIZE;

	float ring = 0.0;
	vec2 push = vec2(0.0);
	if (shock_t < 1.0) {
		vec2 v = (cuv - shock_at) * asp;
		float w = 0.04 + 0.05 * shock_t;
		ring = exp(-pow((length(v) - shock_t * shock_r) / w, 2.0)) * (1.0 - shock_t);
		push = -normalize(v + 1e-5) / asp * ring * 0.025;
	}

	// Brightness alone can't tell a translucent Pale Jade telegraph from the
	// solid Sapphire Core player, so each sample is split by which green it is
	// made of. 3x3 samples so thin lines (swing arc, ring pulse) still land in
	// the cells they cross.
	vec2 sum = vec2(0.0);    // x = core amount, y = jade amount
	vec2 peak = vec2(0.0);
	float dark = 0.0;        // how far below Deep Moss the cell sits (ground shadows are black)
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 uv = (id + (vec2(float(x), float(y)) + 0.5) / 3.0) * cell * SCREEN_PIXEL_SIZE + push;
			vec3 c = texture(screen_tex, uv).rgb;
			dark += 1.0 - clamp(dot(c, vec3(1.0)) / dot(MOSS, vec3(1.0)), 0.0, 1.0);
			vec2 fc = fit(c, CORE);
			vec2 fj = fit(c, JADE);
			vec2 amt = fc.y < fj.y ? vec2(fc.x, 0.0) : vec2(0.0, fj.x);
			sum += amt;
			peak = max(peak, amt);
		}
	}
	vec2 avg = sum / 9.0;
	avg.x += ring * 0.5;
	peak.x += ring * 0.7;

	int g = 0;
	int lvl = 0;             // rung on the density ramp, for the dissolve
	vec3 col = CORE;
	if (max(peak.x, peak.y) < 0.2) {
		// faint tones (floor, far scenery): the brighter the tone, the more cells
		// get a speck, so stone tiles and seams come through as texture density
		// while staying well below anything that matters in the fight
		float f = smoothstep(0.04, 0.19, avg.x);
		if (hash(id) < f * 0.6) {
			float h = hash(id * 1.7);
			if (h < 0.4) g = pack(0, 0, 0, 2);             // .
			else if (h < 0.7) g = pack(0, 0, 2, 4);        // ,
			else if (h < 0.9) g = pack(0, 2, 0, 2);        // :
			else g = pack(2, 2, 0, 0);                     // '
			lvl = 1;
			col = mix(MOSS, CORE, 0.3 + 0.4 * f);
		}
	} else {
		// the stronger green owns the cell, so the player stays visible while
		// standing inside a telegraph. Lean on the peak too: the rigs' Deep Moss
		// outlines would otherwise drag a solid limb down to a faint ':'.
		bool jade = peak.y > peak.x;
		float d = jade ? mix(avg.y, peak.y, 0.45) : mix(avg.x, peak.x, 0.45);
		lvl = clamp(int(d * 9.0) + 1, 1, 9);
		g = ramp(lvl);
		// small glyphs are dense for their size, so the light end of the ramp
		// is also dimmed: floor texture recedes, the rigs keep full green
		col = jade ? JADE : mix(MOSS, CORE, smoothstep(0.1, 0.7, d) * 0.6 + 0.4);
	}

	if (hit_k > 0.0) {
		float tick = floor(TIME * 24.0);
		float s = hit_k * (1.0 - length((cuv - hit_at) * asp) / hit_r);
		if (hash(id + tick) < s) {
			lvl = 1 + int(hash(id * 2.3 + tick) * 9.0);
			g = ramp(lvl);
			col = hash(id * 0.7 + tick) < 0.35 ? JADE : CORE;
		}
	}
	if (fade > 0.0 && lvl > 0) {
		// each cell steps down the ramp towards '.' and out, in its own order
		int drop = int(clamp(fade * 1.5 - hash(id * 3.7) * 0.5, 0.0, 1.0) * 10.0);
		if (drop > 0) g = lvl - drop < 1 ? 0 : ramp(lvl - drop);
	}

	bool on = gp.x < 3 && gp.y < 4
		&& ((g >> ((3 - gp.y) * 3 + (2 - gp.x))) & 1) == 1;
	// Behind the glyphs: Deep Moss, deepening towards SHADE under ground
	// shadows (drawn darker than Deep Moss). Graded by how much of the cell the
	// shadow covers and how dark it is, so its rim softens over a cell or two
	// and a high floater's faint shadow stays light. The Mirror's void is black.
	vec3 bg = mix(MOSS, SHADE, smoothstep(0.05, 0.6, dark / 9.0));
	if (black_void && max(peak.x, peak.y) < 0.04 && dark < 0.5) bg = vec3(0.0);
	bg = mix(bg, MOSS, fade);
	if (pulse > 0.0) {
		float edge = smoothstep(0.55, 1.3, length((cuv - 0.5) * 2.0));
		bg = mix(bg, SHADE, pulse * edge);
	}
	vec3 outc = on ? col : bg;
	if (glow_k > 0.0) {
		vec3 prev = texture(prev_tex, SCREEN_UV).rgb;
		if (dot(prev, vec3(1.0)) > dot(MOSS, vec3(1.0)) + 0.08)
			outc = max(outc, MOSS + (prev - MOSS) * glow_k);
	}
	COLOR = vec4(outc, 1.0);
}
