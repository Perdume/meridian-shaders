// The last pass: a contrast-adaptive sharpen (after AMD's CAS idea: sharpen
// less where the neighbourhood already has contrast, so edges don't ring),
// then a tiny dither so dark gradients don't band in 8 bits.
override lens_sharpen: f32 = 0.3;

fn tap(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(previous, nearest_sampler, uv, 0.0).rgb;
}

fn post(input: PostInput) -> vec4<f32> {
    var c = input.color.rgb;
    if lens_sharpen > 0.0 {
        let texel = 1.0 / vec2<f32>(textureDimensions(previous));
        let n = tap(input.uv + vec2<f32>(0.0, -texel.y));
        let s = tap(input.uv + vec2<f32>(0.0, texel.y));
        let e = tap(input.uv + vec2<f32>(texel.x, 0.0));
        let w = tap(input.uv + vec2<f32>(-texel.x, 0.0));
        let lo = min(c, min(min(n, s), min(e, w)));
        let hi = max(c, max(max(n, s), max(e, w)));
        // Room to sharpen before clipping, per channel.
        let amp = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, vec3<f32>(1e-4)), vec3<f32>(0.0), vec3<f32>(1.0)));
        let k = -amp * mix(0.125, 0.2, lens_sharpen);
        c = clamp((c + (n + s + e + w) * k) / (1.0 + 4.0 * k), vec3<f32>(0.0), vec3<f32>(1.0));
    }
    let dither = (hash21(input.pixel) - 0.5) / 255.0;
    return vec4<f32>(c + vec3<f32>(dither), input.color.a);
}
