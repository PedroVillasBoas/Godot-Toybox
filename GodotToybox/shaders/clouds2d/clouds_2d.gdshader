// Clouds 2D Shader

// Animated procedural cloud shadows
// Two layers of fbm noise warp each other and multiply-blend onto the world below to fake drifting cloud cover
// No external textures required
// Apply via ShaderMaterial to a ColorRect (or Sprite2D) covering the area you want shadowed

// Made by: Pedro Vilas Boas
// Repository: https://github.com/PedroVillasBoas/Godot-Toybox  (other shaders + full demo project)

shader_type canvas_item;
render_mode blend_mul;

// Cloud Shadow Color
uniform vec4 shadow_tint : source_color = vec4(0.4, 0.45, 0.6, 1.0);

// Cloud Shape
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.15;
uniform float cloud_opacity  : hint_range(0.0, 1.0) = 1.0;

// Layer 1 (main cloud shapes)
uniform vec2  scroll_direction_1 = vec2(0.7, -0.7);
uniform float time_scale_1  : hint_range(0.0, 0.25) = 0.012;
uniform float tile_factor_1 : hint_range(0.1, 10.0) = 2.0;

// Layer 2 (distortion / wispy detail)
uniform vec2  scroll_direction_2 = vec2(0.75, 0.25);
uniform float time_scale_2  : hint_range(0.0, 0.25) = 0.005;
uniform float tile_factor_2 : hint_range(0.1, 10.0) = 1.0;

// How strongly Layer 2 warps Layer 1
uniform float distortion_amount : hint_range(0.0, 0.5) = 0.05;

// Pseudo-random 2D hash
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
             dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// 2D gradient (Perlin-style) noise, output range ~[0,1]
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

// Fractional Brownian Motion for organic, fluffy shapes
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * gradient_noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    // Distortion noise layer
    vec2 uv2 = UV * tile_factor_2 + scroll_direction_2 * TIME * time_scale_2;
    float noise_2 = fbm(uv2);

    // Main cloud layer, warped by the distortion layer
    vec2 uv1 = UV * tile_factor_1 + scroll_direction_1 * TIME * time_scale_1;
    float noise_1 = fbm(uv1 + vec2(noise_2) * distortion_amount);

    // Threshold the noise into cloud shapes with soft edges
    float threshold = 1.0 - cloud_coverage;
    float clouds = smoothstep(threshold - cloud_softness,
                              threshold + cloud_softness,
                              noise_1);

    // Multiply blend: white = no shadow, tint = full shadow
    vec3 result = mix(vec3(1.0), shadow_tint.rgb,
                      clouds * shadow_tint.a * cloud_opacity);
    COLOR.rgb = result;
    COLOR.a = 1.0;
}
