// Tone map and grade: exposure, a filmic curve (so bloom and rays roll off
// instead of clipping), a golden hour tint, saturation, a night shift toward
// blue and a vignette.
override tone_map: u32 = 0u;        // 0 ACES, 1 Soft, 2 Off
override tone_exposure: f32 = 1.0;
override tone_saturation: f32 = 1.1;
override tone_night: f32 = 0.4;
override lens_vignette: bool = true;

// Narkowicz's fit of the ACES curve.
fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn post(input: PostInput) -> vec4<f32> {
    // Tone curves work on light, so in linear; the picture is gamma-encoded.
    var c = to_linear(input.color.rgb) * tone_exposure;

    // Golden hour.
    let golden = sun_low() * daylight() * (1.0 - weather() * 0.7);
    c *= mix(vec3<f32>(1.0), vec3<f32>(1.1, 1.0, 0.8), golden * 0.6);

    if tone_map == 0u {
        // 0.8 keeps mid grey where vanilla has it; white lands at 0.88 and
        // bloom and rays above it roll off instead of clipping.
        c = aces(c * 0.8);
    } else if tone_map == 1u {
        c = c / (1.0 + 0.25 * c) * 1.25;
    }
    c = to_gamma(c);

    // Night: dim scenes lose colour and lean blue.
    let dark = 1.0 - smoothstep(0.02, 0.25, luma(c));
    let night = dark * tone_night * (1.0 - frame.night_vision);
    c = mix(c, vec3<f32>(luma(c)) * vec3<f32>(0.85, 0.95, 1.2), night * 0.6);

    c = mix(vec3<f32>(luma(c)), c, tone_saturation);

    if lens_vignette {
        let aspect = frame.resolution.x / frame.resolution.y;
        let d = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.5, 1.15, d) * 0.3;
    }
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
