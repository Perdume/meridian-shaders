// The engine's shadow map, as the material stage and post/shadows.wgsl both
// read it (`files = ["lib/shadow.wgsl"]` on each). The map is drawn from the
// sun (the moon by night) each frame, distorted toward the camera.
override shadow_softness: f32 = 1.0;
override quality: u32 = 2u;          // 0 Low, 1 Medium, 2 High, 3 Ultra (the Quality preset)

// Shadow-map taps per lookup by Quality.
fn shadow_taps() -> u32 {
    switch quality {
        case 0u: { return 4u; }
        case 1u: { return 8u; }
        case 3u: { return 20u; }
        default: { return 12u; }
    }
}

// The world one shadow-map texel covers around `p`: texels grow with distance.
fn shadow_texel(p: vec3<f32>) -> f32 {
    let r = clamp(length(p.xz) / max(frame.shadow_distance, 1.0), 0.0, 1.0);
    let k = frame.shadow_distortion;
    let f = (r * k + 1.0 - k) / max(1.0 - k, 0.05);
    return frame.shadow_center_texel * f * f;
}

// 0 well inside the shadow map, 1 at and past its edge.
fn shadow_edge(p: vec3<f32>) -> f32 {
    let clip = frame.shadow_view_proj * vec4<f32>(p, 1.0);
    return smoothstep(0.8, 0.98, max(abs(clip.x), abs(clip.y)));
}

// How much of the light reaches the map position `s`, 0..1: a spiral of
// taps around it, each a 2x2 filtered comparison, turned per pixel.
fn shadow_visibility(s: vec3<f32>, pixel: vec2<f32>) -> f32 {
    let taps = shadow_taps();
    let radius = (0.5 + shadow_softness * 1.5) / frame.shadow_resolution;
    let turn = ign(pixel) * 6.2831853;
    var lit = 0.0;
    for (var i = 0u; i < taps; i++) {
        let fi = f32(i);
        let r = sqrt((fi + 0.5) / f32(taps)) * radius;
        let a = fi * 2.3999632 + turn;
        lit += textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + vec2<f32>(cos(a), sin(a)) * r, s.z);
    }
    return lit / f32(taps);
}

// The colour of the light at `s` after water or stained glass above it
// (white where the light comes straight down).
fn shadow_tint(s: vec3<f32>) -> vec3<f32> {
    let solid = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z);
    let through = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, s.xy, s.z);
    let size = vec2<f32>(textureDimensions(shadow_color));
    let texel = vec2<i32>(clamp(s.xy * size, vec2<f32>(0.0), size - 1.0));
    let c = textureLoad(shadow_color, texel, 0);
    let under = solid * (1.0 - through);
    return mix(vec3<f32>(1.0), c.rgb, under * 0.85);
}
