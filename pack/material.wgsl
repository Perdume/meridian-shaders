// Lit block surfaces. Vanilla's colour is albedo * tint * lightmap; this
// stage changes the light: sun shadows from the engine's shadow map, warm
// sunlit faces and cool shade, coloured block light, glowing blocks, light
// through leaves, wet surfaces in the rain, LabPBR normal and specular maps,
// and clear water with waves, caustics, foam and a mirror of the world.
// (lib/shadow.wgsl is put before this file.)

// Light
override light_warmth: f32 = 0.5;
override light_shade: f32 = 0.35;
override light_torch: f32 = 0.6;
override light_colored: f32 = 0.8;
override light_emissive: f32 = 1.0;
override light_foliage: f32 = 0.6;
override light_wet: f32 = 0.7;
override light_biome: f32 = 0.5;
override light_cave: f32 = 0.0;
override light_contrast: f32 = 1.1;
// Surfaces
override pbr_normals: bool = true;
override pbr_specular: bool = true;
override light_specular: f32 = 0.6;
// Water
override water_living: bool = true;
override water_waves: f32 = 1.0;
override water_reflection: f32 = 0.6;
override water_mirror: bool = true;
override water_clarity: f32 = 0.6;
override water_refraction: f32 = 0.5;
override water_caustics: f32 = 0.5;
override water_foam: f32 = 0.5;
override water_tint: u32 = 0u;       // 0 Biome, 1 Clear blue, 2 Turquoise, 3 Deep green
// Shadows (with lib/shadow.wgsl's softness and quality)
override shadow_strength: f32 = 0.75;
override shadow_colored: bool = true;

// [[materials]] ids (horizon-shaders.toml).
const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;
const MAT_METAL: u32 = 3u;
const MAT_GLASS: u32 = 4u;

// ---------------------------------------------------------------- water

// The camera-relative point at screen `uv` (0..1 from the top left) and
// reversed depth `depth`, as the post stage's `view_position`.
fn screen_point(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    let v = frame.projection_inverse * clip;
    return (frame.view_inverse * vec4<f32>(v.xyz / v.w, 0.0)).xyz;
}

// The colour water scatters back: its biome's (vanilla's) or a chosen one.
fn water_color(biome: vec3<f32>) -> vec3<f32> {
    switch water_tint {
        case 1u: { return vec3<f32>(0.16, 0.42, 0.78); }
        case 2u: { return vec3<f32>(0.10, 0.58, 0.62); }
        case 3u: { return vec3<f32>(0.12, 0.34, 0.26); }
        default: { return biome; }
    }
}

// The water's surface height at world `p` (in blocks): four wind-driven swells
// of different lengths and directions, plus fine ripples.
fn wave_height(p: vec2<f32>, t: f32) -> f32 {
    var h = 0.0;
    h += sin(dot(p, vec2<f32>(0.80, 0.60)) * 0.9 + t * 1.30) * 0.50;
    h += sin(dot(p, vec2<f32>(-0.40, 0.92)) * 1.7 + t * 1.90) * 0.25;
    h += sin(dot(p, vec2<f32>(0.97, -0.25)) * 3.1 + t * 2.60) * 0.12;
    h += sin(dot(p, vec2<f32>(-0.70, -0.71)) * 5.3 + t * 3.40) * 0.06;
    h += (noise2(p * 2.6 + vec2<f32>(t * 0.5, t * 0.3)) - 0.5) * 0.30;
    return h;
}

// The surface's normal from the slope of the waves, steeper with water_waves.
fn wave_normal(p: vec2<f32>, t: f32) -> vec3<f32> {
    let e = 0.06;
    let dx = wave_height(p + vec2<f32>(e, 0.0), t) - wave_height(p - vec2<f32>(e, 0.0), t);
    let dz = wave_height(p + vec2<f32>(0.0, e), t) - wave_height(p - vec2<f32>(0.0, e), t);
    let k = 0.08 * water_waves / (2.0 * e);
    return normalize(vec3<f32>(-dx * k, 1.0, -dz * k));
}

// Caustics: the net of light the waves focus on the bottom. 0..1.
fn caustic(p: vec2<f32>, t: f32) -> f32 {
    let a = noise2(p * 1.4 + vec2<f32>(t * 0.35, -t * 0.25));
    let b = noise2(p * 1.4 * 1.31 + vec2<f32>(-t * 0.30, t * 0.40) + 17.0);
    return pow(1.0 - abs(a - b), 14.0);
}

// Clear water: what lies behind the surface (the world before translucent
// terrain), bent by the waves, dimmed by the water it passes through, lit
// by caustics, with foam where it is shallow against the shore.
fn water_body(input: MaterialInput, wn: vec3<f32>, lit: vec3<f32>) -> vec4<f32> {
    let size = frame.resolution;
    let here = length(input.position);
    let bend = wn.xz * water_refraction * 0.04 / max(here * 0.15, 1.0);
    var uv = clamp(input.screen + bend, vec2<f32>(0.0), vec2<f32>(1.0));
    var depth = textureLoad(opaque_depth, vec2<i32>(uv * size), 0);
    var bottom = screen_point(uv, depth);
    // Something in front of the water at the bent spot: read straight behind.
    if depth > 0.0 && length(bottom) < here {
        uv = input.screen;
        depth = textureLoad(opaque_depth, vec2<i32>(uv * size), 0);
        bottom = screen_point(uv, depth);
    }
    let thickness = select(64.0, max(length(bottom) - here, 0.0), depth > 0.0);
    let behind = textureLoad(opaque_color, vec2<i32>(uv * size), 0).rgb;
    let reach = mix(1.5, 14.0, water_clarity * water_clarity);
    let absorb = vec3<f32>(0.45, 0.16, 0.10) * (4.0 / reach);
    let through = exp(-absorb * thickness);
    let scatter = water_color(input.tint.rgb * input.albedo.rgb) * lit;
    let fog = 1.0 - exp(-thickness / reach);
    let t = frame.time;
    let floor_at = frame.camera_position.xz + bottom.xz;
    let focus = select(0.0, caustic(floor_at, t), quality >= 1u) * water_caustics * daylight() * (1.0 - wet_weather())
        * exp(-thickness * 0.25) * select(0.0, 1.0, depth > 0.0);
    var rgb = mix(behind * through * (1.0 + focus * 2.0), scatter, fog);
    let surface_at = frame.camera_position.xz + input.position.xz;
    let edge = 1.0 - smoothstep(0.0, 1.1, thickness);
    let froth = smoothstep(0.35, 0.65, noise2(surface_at * 3.0 + vec2<f32>(t * 0.4, t * 0.25)) + edge * 0.5);
    let foam = select(0.0, edge * froth, quality >= 1u) * water_foam * select(0.0, 1.0, depth > 0.0);
    rgb = mix(rgb, lit * 0.95, foam);
    return vec4<f32>(rgb, 1.0);
}

// What the water mirrors at a glancing angle: the world (the engine's water
// mirror, bent by the waves) where there is one, else the sky's colour.
fn water_sky(input: MaterialInput, wn: vec3<f32>, sky: f32) -> vec3<f32> {
    let fallback = mix(frame.fog_color, frame.sky_color, 0.6) * mix(0.3, 1.0, sky);
    if !water_mirror || frame.has_reflection == 0u {
        return fallback;
    }
    let uv = clamp(input.screen + wn.xz * 0.03 * water_waves, vec2<f32>(0.0), vec2<f32>(1.0));
    return textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
}

// ------------------------------------------------------------- surfaces

// The surface's normal: its LabPBR normal map's where a resource pack has one.
fn detail_normal(input: MaterialInput) -> vec3<f32> {
    let n = input.normal;
    if !pbr_normals || !block_pbr_maps() {
        return n;
    }
    let m = block_normal_map(input.uv);
    let xy = m.xy * 2.0 - 1.0;
    let z = sqrt(max(1.0 - dot(xy, xy), 0.0));
    let t = input.tangent.xyz;
    let b = cross(n, t) * input.tangent.w;
    return normalize(t * xy.x + b * xy.y + n * z);
}

// The surface's smoothness (0 rough .. 1 mirror) and whether it is a metal:
// its LabPBR specular map's, else by kind (metal blocks, glass and ice).
fn surface_smoothness(input: MaterialInput) -> vec2<f32> {
    if pbr_specular && block_pbr_maps() {
        let s = block_specular_map(input.uv);
        return vec2<f32>(s.r, select(0.0, 1.0, s.g >= 0.9));
    }
    switch input.material {
        case 3u: { return vec2<f32>(0.6, 1.0); }
        case 4u: { return vec2<f32>(0.85, 0.0); }
        default: { return vec2<f32>(0.0, 0.0); }
    }
}

fn material(input: MaterialInput) -> Surface {
    let geo = input.normal;
    let n = detail_normal(input);
    let sky = input.light.y;
    let block = input.light.x;
    let day = daylight();
    let l = select(frame.sun_direction, frame.light_direction, frame.has_shadow == 1u);
    let foliage = input.material == MAT_LEAVES || input.material == MAT_PLANT;
    let to_eye = normalize(-input.position);

    // How much of the light here comes straight from the sky: none in caves
    // (no sky light) or where torches outshine it; faint moonlight at night.
    let skylit = smoothstep(0.2, 0.6, sky) * (1.0 - smoothstep(0.5, 1.0, block) * 0.7);
    let overworld = select(0.0, 1.0, frame.dimension == 0);
    let direct = skylit * (1.0 - wet_weather()) * mix(0.3, 1.0, day) * overworld;

    // The shadow: the shadow map where it reaches, else cover overhead from
    // sky light. Leaves and plants are thin: light comes through them from
    // behind, so they don't darken facing away from the sun.
    let cover = 1.0 - smoothstep(0.87, 0.96, sky);
    var shadow = cover;
    var through = vec3<f32>(1.0);
    let ndl = dot(n, l);
    let facing = select(max(ndl, 0.0), mix(max(ndl, 0.0), 0.7, light_foliage), foliage);
    if frame.has_shadow == 1u && direct > 0.0 {
        let s = shadow_position(input.position + geo * shadow_texel(input.position) * 1.5
            + l * shadow_texel(input.position) * 0.5);
        let turning = select(smoothstep(0.0, 0.2, dot(geo, l)), 1.0, foliage);
        let vis = shadow_visibility(s, input.screen * frame.resolution) * turning;
        let edge = shadow_edge(input.position);
        shadow = mix(1.0 - vis, cover, edge);
        if shadow_colored && !input.translucent {
            through = mix(shadow_tint(s), vec3<f32>(1.0), edge);
        }
    }
    let sunlit = 1.0 - shadow;

    var light = input.lightmap;
    let warm = sun_tint() * mix(0.85, 1.12, facing);
    light *= mix(vec3<f32>(1.0), warm, direct * sunlit * day * light_warmth);
    light *= mix(vec3<f32>(1.0), vec3<f32>(0.86, 0.93, 1.08), direct * sunlit * (1.0 - facing) * light_shade);
    light *= mix(vec3<f32>(1.0), vec3<f32>(0.55, 0.62, 0.78), direct * shadow * shadow_strength);
    light *= mix(vec3<f32>(1.0), through, direct * sunlit);

    // The biome's mood: cold biomes bluer, hot dry ones warmer, damp ones greener.
    let mood = vec3<f32>(1.0)
        + vec3<f32>(-0.08, -0.03, 0.08) * biome_cold()
        + vec3<f32>(0.06, 0.0, -0.10) * biome_hot()
        + vec3<f32>(-0.05, 0.02, -0.08) * biome_damp();
    light *= mix(vec3<f32>(1.0), mood, light_biome * skylit);

    // Block light: orange torchlight, or the colour of the light sources
    // nearby ([[lights]]: soul fire blue, redstone red, amethyst violet...).
    let bl = block_light_color(input.position);
    let source = bl.rgb / max(luma(bl.rgb), 0.05);
    let lamp = mix(vec3<f32>(1.15, 0.95, 0.72), source, clamp(bl.a * light_colored, 0.0, 1.0));
    let lamp_weight = smoothstep(0.25, 1.0, block) * (1.0 - sky * day)
        * max(light_torch, light_colored * bl.a);
    light *= mix(vec3<f32>(1.0), lamp, lamp_weight);

    light = pow(max(light, vec3<f32>(0.0)), vec3<f32>(light_contrast));
    // Never quite black in caves, if asked.
    light = max(light, vec3<f32>(light_cave * 0.1));
    // Blocks that shine (glowstone, lava, sea lanterns...) glow brighter.
    light = max(light, vec3<f32>(input.emission * light_emissive));

    // Wet in the rain: open surfaces darken a little and turn glossy.
    let wet = frame.wetness * light_wet * smoothstep(0.85, 1.0, sky) * max(geo.y, 0.3)
        * select(1.0, 0.0, input.translucent || input.fluid != 0u);
    var albedo = input.albedo;
    albedo = vec4<f32>(albedo.rgb * mix(1.0, 0.7, wet), albedo.a);
    var color = albedo * input.tint * vec4<f32>(light, 1.0);

    // Light through leaves and grass when the sun is behind them.
    if foliage {
        let behind = pow(max(dot(-to_eye, l), 0.0), 4.0);
        let glow = albedo.rgb * input.tint.rgb * sun_tint() * behind * sunlit * direct * day;
        color = vec4<f32>(color.rgb + glow * light_foliage * 0.8, color.a);
    }

    // Shine: the sun's highlight and the sky's reflection on smooth surfaces
    // (metal, glass, ice, a resource pack's specular maps, wet ground).
    let sm = surface_smoothness(input);
    let gloss = max(sm.x, wet * 0.8);
    if gloss > 0.05 && input.fluid == 0u {
        let h = normalize(l + to_eye);
        let power = exp2(gloss * 10.0) + 2.0;
        let f0 = mix(vec3<f32>(0.04), albedo.rgb, sm.y);
        let fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(n, to_eye), 0.0), 5.0);
        let highlight = pow(max(dot(n, h), 0.0), power) * (power + 8.0) / 64.0;
        let sun_spec = key_color() * fres * highlight * sunlit * direct * gloss;
        let sky_spec = mix(frame.fog_color, frame.sky_color, 0.6) * fres * gloss * smoothstep(0.5, 1.0, sky) * 0.35;
        color = vec4<f32>(color.rgb + (sun_spec + sky_spec) * light_specular, color.a);
    }

    // Solid terrain tells the post passes its normal and smoothness.
    if !input.translucent {
        set_surface(n, gloss, 0.0);
    }

    // Water: Horizon says which surfaces are water. Its top faces ripple;
    // seen from above, its body is clear (water_body), and the top faces
    // mirror the world and glint.
    if input.fluid == 1u {
        let top = geo.y > 0.9;
        var wn = vec3<f32>(0.0, 1.0, 0.0);
        if water_living && top {
            wn = wave_normal(frame.camera_position.xz + input.position.xz, frame.time);
        }
        if frame.eye_in == 0u {
            color = water_body(input, wn, light);
        }
        if water_living && top {
            let cos_v = max(dot(wn, to_eye), 0.0);
            let fresnel = 0.03 + 0.97 * pow(1.0 - cos_v, 5.0);
            let mirrored = water_sky(input, wn, sky);
            color = vec4<f32>(mix(color.rgb, mirrored, fresnel * water_reflection),
                mix(color.a, 1.0, fresnel * water_reflection * 0.8));
            let r = reflect(-to_eye, wn);
            let glint = pow(max(dot(r, key_direction()), 0.0), 600.0) * smoothstep(0.55, 1.0, sky)
                * (1.0 - wet_weather()) * sunlit;
            color = vec4<f32>(color.rgb + key_color() * glint * 0.6, min(color.a + glint * 0.5, 1.0));
        }
    }
    return Surface(color);
}
