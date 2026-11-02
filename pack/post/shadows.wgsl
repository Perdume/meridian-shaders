// Pass 1, shadows and ambient occlusion.
//  * Sun shadows for what the material stage doesn't draw: entities (mobs, the
//    player), water and glass. Solid terrain shades itself in material.wgsl and
//    says so with `set_surface`, so its pixels skip this part.
//  * Ambient occlusion on everything: corners, crevices and the ground under
//    things darken, from the depth around each pixel (and terrain's normal).
// (lib/shadow.wgsl is put before this file.)
override shadow_strength: f32 = 0.75;
override ao_strength: f32 = 0.6;
override ao_radius: f32 = 1.0;

// Ambient occlusion samples by Quality (none on Low).
fn ao_samples() -> u32 {
    switch quality {
        case 0u: { return 0u; }
        case 1u: { return 4u; }
        case 3u: { return 12u; }
        default: { return 8u; }
    }
}

// Screen-space ambient occlusion: a ring of points around `p` in the plane
// facing `n`; each that is behind what the depth buffer shows there is occluded.
fn ambient_occlusion(uv: vec2<f32>, p: vec3<f32>, n: vec3<f32>, pixel: vec2<f32>) -> f32 {
    let dist = length(p);
    let radius = ao_radius * 0.6;
    let turn = ign(pixel) * 6.2831853;
    // A frame around the normal.
    let up = select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(n.y) > 0.9);
    let t = normalize(cross(up, n));
    let b = cross(n, t);
    var hidden = 0.0;
    let count = ao_samples();
    for (var i = 0u; i < count; i++) {
        let fi = f32(i);
        let a = fi * 2.3999632 + turn;
        let r = radius * sqrt((fi + 0.5) / f32(count));
        let q = p + (t * cos(a) + b * sin(a)) * r + n * r * 0.6;
        let clip = frame.projection * (frame.view * vec4<f32>(q, 1.0));
        if clip.w <= 0.0 {
            continue;
        }
        let ndc = clip.xyz / clip.w;
        let quv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        let d = depth_at(quv);
        // Reversed depth: the scene there is nearer than the point.
        let gap = length(q) * (1.0 - ndc.z / max(d, 1e-6));
        let near_enough = 1.0 - smoothstep(radius, radius * 2.5, gap);
        hidden += select(0.0, near_enough, gap > 0.02 && d > 0.0);
    }
    return hidden / f32(max(count, 1u)) * (1.0 - smoothstep(32.0, 64.0, dist));
}

fn post(input: PostInput) -> vec4<f32> {
    if input.depth == 0.0 {
        return input.color;
    }
    var rgb = input.color.rgb;
    let p = view_position(input.uv, input.depth);
    let dist = length(p);
    let surface = surface_at(vec2<i32>(input.pixel));

    // Ambient occlusion: terrain's own normal, else one facing the camera.
    if ao_strength > 0.0 && ao_samples() > 0u {
        let n = select(-p / max(dist, 1e-3), surface.normal, surface.present);
        let ao = ambient_occlusion(input.uv, p, n, input.pixel);
        rgb *= 1.0 - ao * ao_strength * 0.6;
    }

    // Sun shadows on what isn't terrain.
    if shadow_strength > 0.0 && frame.has_shadow == 1u && frame.dimension == 0 && frame.eye_in == 0u
        && !surface.present {
        let edge = shadow_edge(p);
        if edge < 1.0 {
            // No normal here: push the point toward the camera and the light instead.
            let texel = shadow_texel(p);
            let l = frame.light_direction;
            let s = shadow_position(p - (p / max(dist, 1e-3)) * texel * 2.0 + l * texel * 1.5);
            let vis = shadow_visibility(s, input.pixel);
            let amount = (1.0 - vis) * (1.0 - edge) * (1.0 - wet_weather()) * mix(0.3, 1.0, daylight())
                * shadow_strength;
            rgb *= mix(vec3<f32>(1.0), vec3<f32>(0.55, 0.62, 0.78), amount);
        }
    }
    return vec4<f32>(rgb, input.color.a);
}
