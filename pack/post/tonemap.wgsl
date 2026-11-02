// Pass 6, tone map and grade: exposure (with eye adaptation), a filmic curve
// in linear light, golden hour, contrast, saturation and vibrance, colour
// temperature, a blue shift in the dark, vignette and film grain.
override tone_map: u32 = 0u;        // 0 ACES, 1 Soft, 2 Off
override tone_exposure: f32 = 1.0;
override tone_auto_exposure: f32 = 0.5;
override tone_contrast: f32 = 1.0;
override tone_saturation: f32 = 1.1;
override tone_vibrance: f32 = 0.2;
override tone_temperature: f32 = 0.0;
override tone_night: f32 = 0.4;
override lens_vignette: f32 = 0.3;
override lens_grain: f32 = 0.0;

// Narkowicz's fit of the ACES curve.
fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn post(input: PostInput) -> vec4<f32> {
    var c = to_linear(input.color.rgb) * tone_exposure;

    // Eye adaptation: in the dark (low light at the eye, eased over seconds)
    // the picture opens up, up to two stops; in bright sun a little down.
    let eye = max(frame.eye_light_smooth.x, frame.eye_light_smooth.y * mix(0.3, 1.0, daylight()));
    let adapt = mix(1.0, mix(2.2, 0.9, smoothstep(0.1, 0.9, eye)), tone_auto_exposure);
    c *= adapt;

    // Golden hour.
    let golden = sun_low() * daylight() * (1.0 - wet_weather() * 0.7);
    c *= mix(vec3<f32>(1.0), vec3<f32>(1.1, 1.0, 0.8), golden * 0.6);

    // Colour temperature: warmer above 0, cooler below.
    c *= vec3<f32>(1.0 + tone_temperature * 0.12, 1.0, 1.0 - tone_temperature * 0.12);

    if tone_map == 0u {
        c = aces(c * 0.8);
    } else if tone_map == 1u {
        c = c / (1.0 + 0.25 * c) * 1.25;
    }
    c = to_gamma(c);

    // Contrast around mid grey.
    c = clamp((c - 0.5) * tone_contrast + 0.5, vec3<f32>(0.0), vec3<f32>(1.0));

    // Night: dim scenes lose colour and lean blue.
    let dark = 1.0 - smoothstep(0.02, 0.25, luma(c));
    let night = dark * tone_night * (1.0 - frame.night_vision);
    c = mix(c, vec3<f32>(luma(c)) * vec3<f32>(0.85, 0.95, 1.2), night * 0.6);

    // Saturation, then vibrance (more for colours that have little).
    c = mix(vec3<f32>(luma(c)), c, tone_saturation);
    let sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    c = mix(vec3<f32>(luma(c)), c, 1.0 + tone_vibrance * (1.0 - sat));

    if lens_vignette > 0.0 {
        let aspect = frame.resolution.x / frame.resolution.y;
        let d = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.5, 1.15, d) * lens_vignette;
    }
    if lens_grain > 0.0 {
        let g = hash21(input.pixel + vec2<f32>(f32(frame.frame_index % 1024u) * 13.7, 0.0)) - 0.5;
        c += vec3<f32>(g * lens_grain * 0.08);
    }
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
