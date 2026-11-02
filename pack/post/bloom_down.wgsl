// Pass 4, at half size (output "glow"): the bright parts of the picture, a
// soft knee above the threshold, gathered from 13 taps so the glow lens.wgsl
// spreads from it is smooth. The daytime sky counts for little.
override lens_bloom_threshold: f32 = 0.75;

fn bright(uv: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let sky = select(1.0, 0.1, depth_at(uv) == 0.0);
    let knee = smoothstep(lens_bloom_threshold, lens_bloom_threshold + 0.3, luma(c));
    return c * knee * sky;
}

fn post(input: PostInput) -> vec4<f32> {
    let texel = 1.0 / frame.resolution;
    var sum = bright(input.uv) * 0.125;
    for (var i = 0; i < 4; i++) {
        let a = f32(i) * 1.5707963 + 0.7853982;
        let near = vec2<f32>(cos(a), sin(a)) * texel * 1.0;
        let far = vec2<f32>(cos(a), sin(a)) * texel * 2.8;
        let side = vec2<f32>(cos(a - 0.7853982), sin(a - 0.7853982)) * texel * 2.0;
        sum += bright(input.uv + near) * 0.125;
        sum += bright(input.uv + far) * 0.03125;
        sum += bright(input.uv + side) * 0.0625;
    }
    return vec4<f32>(sum, 1.0);
}
