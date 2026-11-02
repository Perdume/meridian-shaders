// Height haze: distant terrain fades into the air, thicker low down (around
// sea level) and in the rain, brighter toward the sun. Overworld only, and
// not underwater or in lava, where vanilla's own fog already rules.
override air_haze: f32 = 0.4;

fn post(input: PostInput) -> vec4<f32> {
    if air_haze <= 0.0 || frame.dimension != 0 || frame.eye_in != 0u || input.depth == 0.0 {
        return input.color;
    }
    let p = view_position(input.uv, input.depth);
    let dist = length(p);
    let height = frame.camera_position.y + p.y;
    // Denser below y=63, thinning above it.
    let thickness = exp(-max(height - 63.0, 0.0) * 0.025) * mix(1.0, 2.5, weather());
    let density = air_haze * 0.004 * thickness;
    // Leave the near world alone: vanilla's fog takes over near the end.
    var amount = 1.0 - exp(-max(dist - 16.0, 0.0) * density);
    amount *= 1.0 - smoothstep(frame.fog_start, frame.fog_end, dist) * 0.5;

    let view_dir = p / max(dist, 1e-3);
    let toward = pow(max(dot(view_dir, frame.sun_direction), 0.0), 8.0) * daylight();
    let air = mix(frame.fog_color, sun_tint() * max(luma(frame.fog_color), 0.05) * 1.6, toward * 0.5);
    return vec4<f32>(mix(input.color.rgb, air, clamp(amount, 0.0, 0.85)), input.color.a);
}
