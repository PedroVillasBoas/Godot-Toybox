// Waterfall Shader

// Procedural 2D waterfall with refraction, animated vertical streaks, wobbly side edges, and an optional splash-erosion bottom
// Self-contained, no external textures required
// Apply to a ColorRect or Sprite2D; samples the screen texture for refraction, so make sure something is rendered behind

// Made by: Peu Vilas Boas
// Repository: https://github.com/PedroVillasBoas/Godot-Toybox  (other shaders + full demo project)


shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

group_uniforms colors;
uniform vec4 water_tint : source_color = vec4(0.2, 0.6, 1.0, 0.35);
uniform vec4 water_highlight : source_color = vec4(1.0, 1.0, 1.0, 0.6);

group_uniforms flow;
uniform float flow_speed : hint_range(0.0, 5.0) = 2.0;

group_uniforms refraction;
uniform vec2  refraction_tiling = vec2(2.0, 0.8);
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.02;

group_uniforms streaks;
uniform vec2  gap_size = vec2(0.9, 0.06);
uniform float flow_gaps : hint_range(0.0, 1.0) = 0.33;
uniform float highlight_width : hint_range(0.0, 0.3) = 0.04;
uniform float gap_softness : hint_range(0.0, 0.2) = 0.02;

group_uniforms edges;
uniform float edge_wobble : hint_range(0.0, 0.5) = 0.15;
uniform float edge_softness : hint_range(0.001, 0.2) = 0.04;
uniform float left_edge   : hint_range(0.0, 0.5) = 0.05;
uniform float right_edge  : hint_range(0.5, 1.0) = 0.95;
uniform float top_edge    : hint_range(0.0, 0.5) = 0.04;
uniform float bottom_edge : hint_range(0.5, 1.0) = 0.96;

group_uniforms splash;
uniform bool  simulate_splash = false;
uniform float splash_size : hint_range(0.0, 0.5) = 0.15;
uniform float splash_softness : hint_range(0.0, 0.5) = 0.15;
uniform vec2  splash_tiling = vec2(4.0, 8.0);

group_uniforms;

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
             dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gradient_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                   dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
               u.y) * 0.5 + 0.5;
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        value += amplitude * gradient_noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    // === Refraction ===
    vec2 refr_uv = vec2(UV.x, UV.y - TIME * flow_speed * 0.5) * refraction_tiling;
    vec2 refraction_offset = vec2(fbm(refr_uv),
                                  fbm(refr_uv + vec2(5.2, 1.3))) - 0.5;
    vec4 refraction = texture(screen_tex,
                              SCREEN_UV + refraction_offset * refraction_strength);

    // Vertical streak pattern
    vec2 gap_uv = vec2(UV.x, UV.y - TIME * flow_speed) * gap_size;
    float gap_mask = fbm(gap_uv);

    // Compose water color
    float in_water     = smoothstep(flow_gaps, flow_gaps + gap_softness, gap_mask);
    float in_highlight = 1.0 - smoothstep(flow_gaps + highlight_width,
                                          flow_gaps + highlight_width + gap_softness,
                                          gap_mask);

    vec4 color;
    color.rgb = mix(refraction.rgb, water_tint.rgb, water_tint.a);
    color.rgb = mix(color.rgb, water_highlight.rgb, water_highlight.a * in_highlight);
    color.a = in_water;

    // Wobbly side and top edges
    vec2 edge_noise_uv = vec2(UV.x, UV.y - TIME * 0.1) * vec2(0.15, 0.6);
    float horiz_wobble = fbm(edge_noise_uv) - 0.5;
    float vert_wobble  = gap_mask - 0.5;

    float left_mask   = smoothstep(left_edge - edge_softness,
                                   left_edge + edge_softness,
                                   UV.x - vert_wobble * edge_wobble);
    float right_mask  = 1.0 - smoothstep(right_edge - edge_softness,
                                         right_edge + edge_softness,
                                         UV.x + vert_wobble * edge_wobble);
    float top_mask    = smoothstep(top_edge - edge_softness,
                                   top_edge + edge_softness,
                                   UV.y - horiz_wobble * edge_wobble * 0.3);

    color.a *= left_mask * right_mask * top_mask;

    // Bottom edge: splash erosion when enabled, otherwise smooth wobble
    if (simulate_splash) {
        // Erosion intensity climbs from 0 (above the splash zone) to 1 (at the bottom edge)
        float splash_strength = smoothstep(bottom_edge - splash_size,
                                           bottom_edge,
                                           UV.y);

        // High-frequency animated noise gives the irregular "broken up" pattern
        vec2 splash_uv = vec2(UV.x, UV.y - TIME * flow_speed * 1.2) * splash_tiling;
        float splash_noise = fbm(splash_uv);

        // Erase pixels where the noise loses to the erosion threshold
        // Near the bottom (strength~1) almost everything erodes; higher up
        // (strength<<1) only the noise valleys cut into the waterfall
        float splash_mask = smoothstep(splash_strength - splash_softness,
                                       splash_strength + splash_softness,
                                       splash_noise);
        color.a *= splash_mask;
    } else {
        float bottom_mask = 1.0 - smoothstep(bottom_edge - edge_softness,
                                             bottom_edge + edge_softness,
                                             UV.y + horiz_wobble * edge_wobble * 0.5);
        color.a *= bottom_mask;
    }

    COLOR = color;
}
