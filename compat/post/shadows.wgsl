// Screen-space sun shadows, part 1: the trace. Shader API 0.1 has no shadow
// stage (no shadow map), so this pass marches from each visible point toward
// the sun through the depth buffer: where something on screen (a block, a
// tree, the player in third person, a mob) lies between the point and the
// sun, the point is in shadow. A caster out of view casts nothing.
//
// The picture passes through unchanged; the shadow goes out in alpha
// (1 lit, 0 fully shadowed) for shadow_filter.wgsl to smooth and apply.
// Post targets between passes are Rgba16Float, so alpha survives.
override shadow_strength: f32 = 0.7;
override shadow_quality: u32 = 1u;   // 0 Low (12 steps), 1 Medium (20), 2 High (32)
override shadow_distance: f32 = 48.0;

// A camera-relative point on screen: uv, its (reversed) depth, and clip w
// (> 0 in front).
fn to_screen(q: vec3<f32>) -> vec4<f32> {
    let clip = frame.projection * (frame.view * vec4<f32>(q, 1.0));
    let w = max(clip.w, 1e-4);
    let ndc = clip.xyz / w;
    return vec4<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, ndc.z, clip.w);
}

// Marches from the visible point `p` along `dir` for `reach` blocks: the
// fraction of the way (0..1) to the first thing on screen in the way, or -1.
fn march(p: vec3<f32>, dist: f32, dir: vec3<f32>, reach: f32, steps: u32, jitter: f32) -> f32 {
    // Lift the start off the surface, toward the camera and along the ray,
    // so a face doesn't shadow itself.
    let bias = 0.05 + dist * 0.004;
    let start = p - (p / dist) * bias + dir * bias;
    for (var i = 0u; i < steps; i++) {
        let t = (f32(i) + jitter) / f32(steps);
        // Steps packed near the surface, where contact shadows are.
        let q = start + dir * (t * t * reach + 0.04);
        let s = to_screen(q);
        if s.w <= 0.0 || any(s.xy < vec2<f32>(0.0)) || any(s.xy > vec2<f32>(1.0)) {
            break;
        }
        let d = depth_at(s.xy);
        if d <= 0.0 {
            continue;
        }
        // Reversed depth goes as 1 / distance, so the scene's distance there
        // is here * s.z / d: no matrix needed per step.
        let here = length(q);
        let gap = here * (1.0 - s.z / d);
        // Something in front of the ray's point, but not so far in front that
        // it is a separate surface the ray passes behind. Two blocks and more
        // with distance: a tree's canopy is that deep.
        let thickness = 2.0 + here * 0.03;
        if gap > bias && gap < thickness {
            return t;
        }
    }
    return -1.0;
}

// 0 lit .. 1 fully shadowed from the sun.
fn occlusion(p: vec3<f32>, dist: f32, light: vec3<f32>, jitter: f32) -> f32 {
    let steps = select(select(32u, 20u, shadow_quality == 1u), 12u, shadow_quality == 0u);
    let t = march(p, dist, light, 12.0, steps, jitter);
    // Softer the farther along the ray the caster is.
    return select(0.0, 1.0 - smoothstep(0.5, 1.0, t) * 0.6, t >= 0.0);
}

// 1 when something is overhead (a canopy, a roof). Those points are shaded
// by the material stage from the world's sky light, which works whether or
// not the cover is on screen; tracing them here too would shade them twice,
// and only while the cover is in view. So this pass leaves them alone, and
// shades what is open above but out of the sun: the ground beside a tree,
// under the player, behind a wall.
fn overhead(p: vec3<f32>, dist: f32, jitter: f32) -> f32 {
    let t = march(p, dist, vec3<f32>(0.0, 1.0, 0.0), 8.0, 8u, jitter);
    return select(0.0, 1.0, t >= 0.0);
}

fn post(input: PostInput) -> vec4<f32> {
    let lit = vec4<f32>(input.color.rgb, 1.0);
    if shadow_strength <= 0.0 || frame.dimension != 0 || frame.eye_in != 0u || input.depth == 0.0 {
        return lit;
    }
    let light = key_direction();
    if light.y <= 0.03 {
        return lit;
    }
    let p = view_position(input.uv, input.depth);
    let dist = length(p);
    if dist > shadow_distance || dist < 1e-3 {
        return lit;
    }
    let jitter = ign(input.pixel);
    var shadow = occlusion(p, dist, light, jitter);
    if shadow > 0.0 {
        shadow *= 1.0 - overhead(p, dist, jitter);
    }

    // Fainter far away, in the rain, at dusk, and from the moon.
    let sun_up = frame.sun_direction.y > -0.05;
    let fade = (1.0 - smoothstep(shadow_distance * 0.7, shadow_distance, dist))
        * (1.0 - weather())
        * select(0.3, mix(0.4, 1.0, smoothstep(0.03, 0.25, light.y)), sun_up);
    return vec4<f32>(input.color.rgb, 1.0 - shadow * fade);
}
