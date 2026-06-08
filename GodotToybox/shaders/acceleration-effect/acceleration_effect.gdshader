// Acceleration Effect Shader

// Single-pass afterimage / ghost trai
// Drives a color fade on short-lived Sprite2D snapshots spawned along a moving entity
// Tween `progress` from 0.0 (fresh) to 1.0 (fully faded) from a script, or scrub it in the inspector to preview the fade

// Made by: Peu Vilas Boas
// Repository: https://github.com/PedroVillasBoas/Godot-Toybox  (other shaders + full demo project)


shader_type canvas_item;

group_uniforms fade;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

group_uniforms colors;
uniform vec4 start_color : source_color = vec4(1.0, 0.7, 0.0, 0.8);
uniform vec4 end_color   : source_color = vec4(1.0, 0.0, 0.3, 0.0);

group_uniforms;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    vec4 fade_color = mix(start_color, end_color, progress);
    COLOR.rgb = fade_color.rgb;
    COLOR.a = fade_color.a * tex.a;
}
