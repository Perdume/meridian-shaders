// Pass 7, temporal anti-aliasing (second to last, so `history` is its own
// output last frame): each pixel finds where it was last frame, takes that
// colour, keeps it within the colours around it now (so moving things don't
// smear), and blends. It steadies the shimmer of distant leaves and edges and
// the grain of soft shadows and ambient occlusion.
override aa_taa: bool = true;
override aa_taa_blend: f32 = 0.85;

fn post(input: PostInput) -> vec4<f32> {
    let c = input.color.rgb;
    if !aa_taa {
        return input.color;
    }
    // Where this pixel was last frame.
    let p = select(view_position(input.uv, 0.0001), view_position(input.uv, input.depth), input.depth > 0.0);
    let was = frame.previous_view_projection * vec4<f32>(p + frame.camera_motion, 1.0);
    if was.w <= 0.0 {
        return input.color;
    }
    let prev_uv = vec2<f32>(was.x / was.w * 0.5 + 0.5, 0.5 - was.y / was.w * 0.5);
    if any(prev_uv < vec2<f32>(0.0)) || any(prev_uv > vec2<f32>(1.0)) {
        return input.color;
    }
    let old = textureSampleLevel(history, linear_sampler, prev_uv, 0.0).rgb;
    // The colours around this pixel now: last frame's is kept inside them.
    let texel = 1.0 / frame.resolution;
    var lo = c;
    var hi = c;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let n = textureSampleLevel(previous, nearest_sampler, input.uv + vec2<f32>(f32(x), f32(y)) * texel, 0.0).rgb;
            lo = min(lo, n);
            hi = max(hi, n);
        }
    }
    let kept = clamp(old, lo, hi);
    // Fast motion trusts this frame more.
    let moved = length((input.uv - prev_uv) * frame.resolution);
    let blend = aa_taa_blend * (1.0 - smoothstep(2.0, 24.0, moved));
    // History is black on the first frame and after a gap.
    let fresh = select(blend, 0.0, dot(old, old) == 0.0);
    return vec4<f32>(mix(c, kept, fresh), input.color.a);
}
