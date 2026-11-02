// Pass 5, the camera's lens.
//  * Bloom: the half-size "glow" target spread wide and added back.
//  * Depth of field (off by default): focus on what is at the centre of the
//    screen, the rest blurs with its distance from it.
//  * Motion blur (off by default): streaks along how each point moved on the
//    screen since last frame.
//  * Chromatic aberration (off by default): red and blue part at the edges.
override lens_bloom: f32 = 0.35;
override lens_bloom_radius: f32 = 1.0;
override lens_dof: f32 = 0.0;
override lens_motion_blur: f32 = 0.0;
override lens_aberration: f32 = 0.0;
override quality: u32 = 2u;          // 0 Low, 1 Medium, 2 High, 3 Ultra (the Quality preset)

// Taps by Quality: the bloom's spread, the depth of field's blur, motion blur's streak.
fn glow_taps() -> u32 {
    switch quality {
        case 0u: { return 8u; }
        case 1u: { return 12u; }
        case 3u: { return 24u; }
        default: { return 16u; }
    }
}
fn dof_taps() -> u32 {
    switch quality {
        case 0u: { return 6u; }
        case 1u: { return 8u; }
        case 3u: { return 16u; }
        default: { return 12u; }
    }
}
fn blur_taps() -> u32 {
    switch quality {
        case 0u: { return 4u; }
        case 1u: { return 6u; }
        case 3u: { return 12u; }
        default: { return 8u; }
    }
}

fn glow_at(uv: vec2<f32>) -> vec3<f32> {
    let size = vec2<f32>(textureDimensions(glow));
    let unit = lens_bloom_radius * frame.resolution.y / 720.0 / size;
    var sum = vec3<f32>(0.0);
    var total = 0.0;
    let taps = glow_taps();
    for (var i = 0u; i < taps; i++) {
        let fi = f32(i);
        let r = sqrt((fi + 0.5) / f32(taps)) * 6.0;
        let a = fi * 2.3999632;
        let w = exp(-r * r / 18.0);
        sum += textureSampleLevel(glow, linear_sampler, uv + vec2<f32>(cos(a), sin(a)) * r * unit, 0.0).rgb * w;
        total += w;
    }
    return sum / total;
}

fn picture(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(previous, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn depth_blur(input: PostInput) -> vec3<f32> {
    let focus_depth = depth_at(vec2<f32>(0.5, 0.5));
    let focus = select(256.0, length(view_position(vec2<f32>(0.5, 0.5), focus_depth)), focus_depth > 0.0);
    let here = select(256.0, length(view_position(input.uv, input.depth)), input.depth > 0.0);
    let coc = clamp(abs(here - focus) / max(focus, 1.0), 0.0, 1.0) * lens_dof * 12.0;
    if coc < 0.5 {
        return input.color.rgb;
    }
    let texel = 1.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    let taps = dof_taps();
    for (var i = 0u; i < taps; i++) {
        let fi = f32(i);
        let r = sqrt((fi + 0.5) / f32(taps)) * coc;
        let a = fi * 2.3999632;
        sum += picture(input.uv + vec2<f32>(cos(a), sin(a)) * r * texel);
    }
    return sum / f32(taps);
}

fn motion_blur(input: PostInput, color: vec3<f32>) -> vec3<f32> {
    let p = select(view_position(input.uv, 0.0001), view_position(input.uv, input.depth), input.depth > 0.0);
    let was = frame.previous_view_projection * vec4<f32>(p + frame.camera_motion, 1.0);
    if was.w <= 0.0 {
        return color;
    }
    let prev_uv = vec2<f32>(was.x / was.w * 0.5 + 0.5, 0.5 - was.y / was.w * 0.5);
    let velocity = (input.uv - prev_uv) * lens_motion_blur;
    if length(velocity * frame.resolution) < 1.0 {
        return color;
    }
    var sum = color;
    let taps = blur_taps();
    for (var i = 1u; i < taps; i++) {
        sum += picture(input.uv - velocity * (f32(i) / f32(taps)));
    }
    return sum / f32(taps);
}

fn post(input: PostInput) -> vec4<f32> {
    var c = input.color.rgb;
    if lens_dof > 0.0 {
        c = depth_blur(input);
    }
    if lens_motion_blur > 0.0 {
        c = motion_blur(input, c);
    }
    if lens_aberration > 0.0 {
        let off = (input.uv - 0.5) * lens_aberration * 0.006;
        c = vec3<f32>(picture(input.uv + off).r, c.g, picture(input.uv - off).b);
    }
    if lens_bloom > 0.0 {
        c += glow_at(input.uv) * lens_bloom * 1.5;
    }
    return vec4<f32>(c, input.color.a);
}
