// Breakable Glass Shader

// Stylized 2D glass shatter effect: voronoi shards, refraction, chromatic split, animated cracks, and an optional center hole.
// Apply to a ColorRect with "Full Rect" anchors and drive `break_progress` from 0.0 (intact) to 1.0 (shards fully fallen) to play the animation.

// Made by: Peu Vilas Boas
// Repository: https://github.com/PedroVillasBoas/Godot-Toybox  (other shaders + full demo project)


shader_type canvas_item;


// ============================================================================
// Uniforms
// ============================================================================

group_uniforms Screen;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
group_uniforms;

group_uniforms Animation;
uniform float break_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 impact_point = vec2(0.5, 0.5);
group_uniforms;

group_uniforms Glass_Mask;
uniform bool use_glass_mask = false;
uniform bool glass_mask_circle = true;
uniform vec2 glass_mask_position = vec2(0.5, 0.5);
uniform vec2 glass_mask_scale = vec2(0.5, 0.5);
uniform float glass_mask_rotation : hint_range(-180.0, 180.0) = 0.0;
uniform float glass_mask_softness : hint_range(0.0, 0.5) = 0.02;
group_uniforms;

group_uniforms Shards;
uniform int pieces_x : hint_range(2, 64) = 12;
uniform int pieces_y : hint_range(2, 64) = 8;
uniform float point_jitter : hint_range(0.0, 0.48) = 0.34;
group_uniforms;

group_uniforms Motion;
uniform float gravity : hint_range(0.0, 6.0) = 2.4;
uniform float shard_scatter : hint_range(0.0, 2.0) = 0.35;
uniform float rotation_amount : hint_range(0.0, 8.0) = 1.0;
uniform float delay_variation : hint_range(0.0, 1.0) = 0.35;
group_uniforms;

group_uniforms Cracks;
uniform float crack_width : hint_range(0.0001, 0.05) = 0.005;
uniform float crack_brightness : hint_range(0.0, 5.0) = 1.5;
uniform float crack_density : hint_range(0.0, 3.0) = 1.0;
uniform vec4 crack_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Widens cracks within a radius of the impact, scaled by progress.
uniform float impact_crack_boost : hint_range(0.0, 5.0) = 1.5;
uniform float impact_crack_radius : hint_range(0.05, 1.0) = 0.5;
group_uniforms;

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.75, 0.9, 1.0, 0.15);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.15;
group_uniforms;

group_uniforms Hole;
uniform float center_hole_size : hint_range(0.0, 0.5) = 0.0;
uniform float hole_irregularity : hint_range(0.0, 1.0) = 0.4;
uniform float hole_appear_at : hint_range(0.0, 1.0) = 0.3;
group_uniforms;

group_uniforms FX;
uniform float refraction : hint_range(0.0, 0.1) = 0.015;
uniform float chromatic : hint_range(0.0, 0.05) = 0.003;
uniform float shake : hint_range(0.0, 0.1) = 0.008;
group_uniforms;

group_uniforms Performance;
// Half-width of the horizontal candidate search
// Increase if you crank `shard_scatter` very high and notice shards disappearing sideways
uniform int search_columns_half : hint_range(1, 8) = 4;
// Hard cap on the vertical search. The shader auto-shrinks the search while break_progress is low; this is the ceiling at full progress
uniform int max_search_rows : hint_range(2, 50) = 30;
group_uniforms;

const int SEARCH_RADIUS = 1;


// Helpers
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	return vec2(
		hash12(p + vec2(1.23, 4.56)),
		hash12(p + vec2(7.89, 0.12))
	);
}

mat2 rot(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

vec2 cell_point(vec2 cell_id) {
	vec2 h = hash22(cell_id);
	return cell_id + 0.5 + (h - 0.5) * (point_jitter * 2.0);
}

// Standard 3x3 voronoi
// Returns the owner cell, its jittered point, and the distance to the closest neighbor edge (second - first)
void voronoi_info(
	vec2 p,
	out vec2 owner_cell,
	out vec2 owner_point,
	out float edge_dist
) {
	vec2 base = floor(p);
	float best_d = 1e20;
	float second_d = 1e20;
	vec2 best_cell = vec2(0.0);
	vec2 best_point = vec2(0.0);

	for (int j = -SEARCH_RADIUS; j <= SEARCH_RADIUS; j++) {
		for (int i = -SEARCH_RADIUS; i <= SEARCH_RADIUS; i++) {
			vec2 c = base + vec2(float(i), float(j));
			vec2 pt = cell_point(c);
			float d = distance(p, pt);
			if (d < best_d) {
				second_d = best_d;
				best_d = d;
				best_cell = c;
				best_point = pt;
			} else if (d < second_d) {
				second_d = d;
			}
		}
	}

	owner_cell = best_cell;
	owner_point = best_point;
	edge_dist = second_d - best_d;
}

// Per-piece motion parameters
// Pure function of the cell id, so we can call it for any candidate cell during the search
void piece_transform(
	vec2 piece_cell,
	out float t,
	out vec2 piece_offset_uv,
	out float piece_angle
) {
	float rnd = hash12(piece_cell);
	float rnd2 = hash12(piece_cell + 17.37);

	vec2 grid = vec2(float(pieces_x), float(pieces_y));
	vec2 piece_uv = (piece_cell + 0.5) / grid;

	float impact_dist = distance(piece_uv, impact_point);
	float radial_delay = impact_dist * delay_variation;
	float delay = rnd * 0.2 + radial_delay;

	t = clamp((break_progress - delay) / max(0.0001, 1.0 - delay), 0.0, 1.0);

	vec2 explode_dir = normalize(piece_uv - impact_point + vec2(0.0001));
	float explode_force = max(1.0 - impact_dist, 0.0);

	float drift_x = explode_dir.x * shard_scatter * t * explode_force;
	float drift_y = explode_dir.y * shard_scatter * 0.35 * t * explode_force;

	float fall_y = gravity * t * t * (0.3 + rnd2);

	piece_offset_uv = vec2(drift_x, drift_y + fall_y);
	piece_angle = (rnd - 0.5) * rotation_amount * t * explode_force;
}

float glass_mask_value(vec2 uv) {
	vec2 local_uv = uv - glass_mask_position;
	local_uv = rot(radians(glass_mask_rotation)) * local_uv;
	local_uv /= glass_mask_scale;

	float dist;
	if (glass_mask_circle) {
		dist = length(local_uv);
	} else {
		vec2 d = abs(local_uv);
		dist = max(d.x, d.y);
	}

	return 1.0 - smoothstep(1.0 - glass_mask_softness, 1.0, dist);
}


// Fragment

void fragment() {
	vec2 uv = UV;
	vec2 grid = vec2(float(pieces_x), float(pieces_y));

	// Shake: only applied after the break starts
	uv += vec2(
		sin(TIME * 120.0 + uv.y * 40.0),
		cos(TIME * 90.0 + uv.x * 50.0)
	) * shake * break_progress;

	// Auto-shrink the vertical search to what's actually needed right now
	// At break_progress = 0 no shard has fallen, so the search is tiny
	float max_possible_fall = gravity * break_progress * break_progress * 1.3;
	int dyn_rows = min(int(ceil(max_possible_fall * float(pieces_y))) + 2, max_search_rows);

	vec2 base_grid = floor(uv * grid);

	// ----- Candidate search: which piece currently covers this pixel? -----
	bool found = false;
	float found_t = 0.0;
	vec2 found_offset = vec2(0.0);
	float found_angle = 0.0;
	float found_edge_dist = 0.0;

	for (int j = -1; j < 60; j++) {
		if (j >= dyn_rows) break;

		for (int i = -8; i <= 8; i++) {
			if (i + search_columns_half < 0) continue;
			if (i > search_columns_half) break;

			// Candidate cell: j > 0 means we look at cells statically
			// above this pixel (which may have fallen down onto it).
			vec2 candidate = base_grid + vec2(float(i), -float(j));

			float t_c;
			vec2 offset_c;
			float angle_c;
			piece_transform(candidate, t_c, offset_c, angle_c);

			vec2 candidate_center_uv = cell_point(candidate) / grid;

			// Reverse the piece's rigid transform: where would this pixel sit in the piece's rest frame?
			vec2 rel_uv = uv - candidate_center_uv;
			vec2 orig_uv = candidate_center_uv + rot(-angle_c) * (rel_uv - offset_c);

			if (orig_uv.x < -0.02 || orig_uv.x > 1.02) continue;
			if (orig_uv.y < -0.02 || orig_uv.y > 1.02) continue;

			// If the static voronoi at the rest position is still this candidate, the pixel really does belong to this moved piece
			vec2 cell_at_orig;
			vec2 point_at_orig;
			float edge_at_orig;
			voronoi_info(orig_uv * grid, cell_at_orig, point_at_orig, edge_at_orig);

			if (distance(cell_at_orig, candidate) < 0.001) {
				found = true;
				found_t = t_c;
				found_offset = offset_c;
				found_angle = angle_c;
				found_edge_dist = edge_at_orig;
				break;
			}
		}
		if (found) break;
	}

	// Plain background: what's actually behind the ColorRect right now.
	vec3 plain_bg = texture(screen_tex, SCREEN_UV).rgb;

	// Composing the glass piece
	vec3 final_color = plain_bg;

	if (found) {
		// The piece "carries" its rest-position content as it slides
		// We sample the screen at SCREEN_UV - offset so the content stays glued to the shard during the fall
		vec2 carried_uv = SCREEN_UV - found_offset;

		// Radial refraction from impact, ramping with this shard's progress
		vec2 refract_dir = normalize(uv - impact_point + vec2(0.0001)) * refraction;
		carried_uv += refract_dir * found_t;
		carried_uv = clamp(carried_uv, vec2(0.0), vec2(1.0));

		// Chromatic split (also ramps with shard progress)
		float r = texture(screen_tex, carried_uv + vec2(chromatic, 0.0) * found_t).r;
		float g = texture(screen_tex, carried_uv).g;
		float b = texture(screen_tex, carried_uv - vec2(chromatic, 0.0) * found_t).b;
		vec3 piece_color = vec3(r, g, b);

		// Glass tint
		piece_color = mix(piece_color, glass_tint.rgb, tint_strength);

		// Cracks: widen near impact as the break propagates (no fake rays)
		float dist_to_impact = distance(uv, impact_point);
		float impact_factor = 1.0 + impact_crack_boost
			* smoothstep(impact_crack_radius, 0.0, dist_to_impact)
			* break_progress;
		float effective_crack_width = crack_width * impact_factor * crack_density;

		float edge = 1.0 - smoothstep(0.0, effective_crack_width, found_edge_dist);
		piece_color += crack_color.rgb * edge * crack_brightness;

		final_color = piece_color;
	}

	// Center hole
	float hole_n = noise(uv * 40.0);
	float impact_dist_uv = distance(uv, impact_point);
	float hole = smoothstep(
		center_hole_size + hole_n * hole_irregularity * 0.05,
		0.0,
		impact_dist_uv
	);
	hole *= smoothstep(hole_appear_at, hole_appear_at + 0.2, break_progress);
	final_color = mix(final_color, plain_bg, hole);

	// Glass mask (clip the effect to an arbitrary shape)
	if (use_glass_mask) {
		float mask = glass_mask_value(uv);
		final_color = mix(plain_bg, final_color, mask);
	}

	COLOR = vec4(final_color, 1.0);
}
