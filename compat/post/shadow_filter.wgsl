// Screen-space sun shadows, part 2: a 5x5 blur of the trace's alpha that
// stops at depth edges (so a tree's shadow doesn't bleed onto the sky or a
// far hill), then the shade itself. Shaded light keeps the sky's blue, since
// what's left in a shadow is skylight.
override shadow_strength: f32 = 0.7;

fn post(input: PostInput) -> vec4<f32> {
    if shadow_strength <= 0.0 || input.depth == 0.0 {
        return vec4<f32>(input.color.rgb, 1.0);
    }
    let texel = 1.0 / vec2<f32>(textureDimensions(previous));
    // Reversed depth goes as 1 / distance, so the relative change of depth is
    // the relative change of distance: 4% apart is another surface.
    let tolerance = 0.04;
    var sum = 0.0;
    var total = 0.0;
    for (var y = -2; y <= 2; y++) {
        for (var x = -2; x <= 2; x++) {
            let uv = input.uv + vec2<f32>(f32(x), f32(y)) * texel;
            let d = depth_at(uv);
            let gap = abs(d - input.depth) / input.depth;
            let w = select(0.0, 1.0 - gap / tolerance, gap < tolerance && d > 0.0);
            sum += textureSampleLevel(previous, nearest_sampler, uv, 0.0).a * w;
            total += w;
        }
    }
    let lit = select(1.0, sum / total, total > 0.0);
    let shadow = clamp(1.0 - lit, 0.0, 1.0) * shadow_strength;
    let shade = mix(vec3<f32>(1.0), vec3<f32>(0.55, 0.62, 0.78), shadow);
    return vec4<f32>(input.color.rgb * shade, 1.0);
}
