// Shared by every stage. Only `frame` is available here: the post
// resources (scene_color, depth_at, ...) exist in post passes alone.

const PI: f32 = 3.14159265;

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 1 while the sun is up in the Overworld, fading around the horizon.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.12, 0.12, frame.sun_direction.y), frame.dimension == 0);
}

// 1 when the sun is on the horizon, 0 from about a quarter of the way up.
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.4, abs(frame.sun_direction.y));
}

// Rain and thunder together, 0..1.
fn wet_weather() -> f32 {
    return clamp(frame.rain * 0.8 + frame.thunder * 0.2, 0.0, 1.0);
}

// The colour of direct sunlight: white at noon, orange at the horizon.
fn sun_tint() -> vec3<f32> {
    return mix(vec3<f32>(1.0, 0.97, 0.92), vec3<f32>(1.0, 0.6, 0.3), sun_low());
}

// The light that casts rays and glints: the sun by day, the moon (dim, blue) at night.
fn key_direction() -> vec3<f32> {
    return select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > -0.05);
}

fn key_color() -> vec3<f32> {
    return select(vec3<f32>(0.35, 0.45, 0.7) * 0.4, sun_tint(), frame.sun_direction.y > -0.05);
}

fn hash21(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(123.34, 456.21));
    let r = q + dot(q, q + 45.32);
    return fract(r.x * r.y);
}

// Interleaved gradient noise (Jimenez 2014): a per-pixel offset whose
// pattern a small blur removes almost entirely. Steady from frame to frame.
fn ign(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(floor(pixel), vec2<f32>(0.06711056, 0.00583715))));
}

// The picture is gamma-encoded (sRGB); light adds up in linear.
fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn to_gamma(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

// Smooth value noise, 0..1.
fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal value noise: four octaves, 0..1.
fn fbm2(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var q = p;
    for (var i = 0; i < 4; i++) {
        sum += noise2(q) * amp;
        q = q * 2.03 + vec2<f32>(17.1, 9.2);
        amp *= 0.5;
    }
    return sum / 0.9375;
}

// How cold the biome at the camera is: 1 in snowy biomes, 0 from temperate up.
fn biome_cold() -> f32 {
    return 1.0 - smoothstep(-0.2, 0.4, frame.temperature);
}

// How hot and dry: 1 in deserts and badlands, 0 in temperate biomes.
fn biome_hot() -> f32 {
    return smoothstep(1.0, 1.8, frame.temperature) * (1.0 - frame.downfall);
}

// How damp: 1 in swamps and jungles.
fn biome_damp() -> f32 {
    return smoothstep(0.6, 0.9, frame.downfall) * (1.0 - biome_cold());
}
