// Bloom: the bright parts of the picture (lava, glowstone, the sun, rays)
// spread a soft glow, from three rings of taps scaled with the picture's
// height so it looks the same at any resolution. The daytime sky is bright
// too, so it counts for less.
override lens_bloom: f32 = 0.35;

fn bright(uv: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    // The daytime sky is bright everywhere; only light sources should glow.
    let sky = select(1.0, 0.1, depth_at(uv) == 0.0);
    // A soft knee from 0.8 up (values past 1 from the rays count fully).
    let l = luma(c);
    let knee = smoothstep(0.8, 1.1, l);
    return c * knee * sky;
}

fn post(input: PostInput) -> vec4<f32> {
    if lens_bloom <= 0.0 {
        return input.color;
    }
    let unit = frame.resolution.y / 720.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    var total = 0.0;
    for (var ring = 0; ring < 3; ring++) {
        let radius = 3.0 + f32(ring) * 5.0;
        let w = 1.0 / (1.0 + f32(ring));
        for (var i = 0; i < 10; i++) {
            // Each ring turned a little so the taps don't line up.
            let angle = (f32(i) + f32(ring) * 0.5) * (2.0 * PI / 10.0);
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius * unit;
            sum += bright(input.uv + offset) * w;
            total += w;
        }
    }
    let glow = sum / total;
    return vec4<f32>(input.color.rgb + glow * lens_bloom * 1.5, input.color.a);
}
