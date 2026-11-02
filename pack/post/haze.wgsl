// Pass 2, the air.
//  * Overworld: height haze, thicker low down and in the rain, brighter toward
//    the sun, tinted by the biome (bluer in snow, dusty in deserts, green in swamps).
//  * Under water: the picture wavers, reds fade with distance, light shafts.
//  * The Nether: a heat shimmer and a red-orange haze. The End: violet air.
override air_haze: f32 = 0.4;
override air_underwater: f32 = 0.7;
override air_nether: f32 = 0.6;
override air_end: f32 = 0.6;
override light_biome: f32 = 0.5;

fn overworld_haze(input: PostInput, color: vec3<f32>) -> vec3<f32> {
    if air_haze <= 0.0 || input.depth == 0.0 {
        return color;
    }
    let p = view_position(input.uv, input.depth);
    let dist = length(p);
    let height = frame.camera_position.y + p.y;
    let thickness = exp(-max(height - 63.0, 0.0) * 0.025) * mix(1.0, 2.5, wet_weather())
        * (1.0 + (biome_hot() * 0.6 + biome_damp() * 0.8) * light_biome);
    let density = air_haze * 0.004 * thickness;
    var amount = 1.0 - exp(-max(dist - 16.0, 0.0) * density);
    amount *= 1.0 - smoothstep(frame.fog_start, frame.fog_end, dist) * 0.5;
    let view_dir = p / max(dist, 1e-3);
    let toward = pow(max(dot(view_dir, frame.sun_direction), 0.0), 8.0) * daylight();
    var air = mix(frame.fog_color, sun_tint() * max(luma(frame.fog_color), 0.05) * 1.6, toward * 0.5);
    let tint = vec3<f32>(1.0)
        + vec3<f32>(-0.10, 0.0, 0.12) * biome_cold()
        + vec3<f32>(0.12, 0.04, -0.12) * biome_hot()
        + vec3<f32>(-0.10, 0.06, -0.10) * biome_damp();
    air *= mix(vec3<f32>(1.0), tint, light_biome);
    return mix(color, air, clamp(amount, 0.0, 0.85));
}

fn underwater(input: PostInput) -> vec3<f32> {
    let t = frame.time;
    // The picture wavers.
    let wobble = vec2<f32>(sin(input.uv.y * 24.0 + t * 2.1), cos(input.uv.x * 19.0 + t * 1.7)) * 0.0025 * air_underwater;
    let uv = clamp(input.uv + wobble, vec2<f32>(0.0), vec2<f32>(1.0));
    var c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let depth = depth_at(uv);
    let dist = select(48.0, length(view_position(uv, depth)), depth > 0.0);
    // Reds go first, then greens.
    let through = exp(-vec3<f32>(0.20, 0.06, 0.03) * dist * air_underwater);
    let water = vec3<f32>(0.05, 0.22, 0.32) * mix(0.25, 1.0, frame.eye_light_smooth.y);
    c = mix(water, c, through);
    // Light shafts from above, swaying.
    let rays = pow(noise2(vec2<f32>(input.uv.x * 9.0 + input.uv.y * 3.0 + t * 0.3, t * 0.2)), 6.0)
        * (1.0 - input.uv.y) * daylight() * frame.eye_light_smooth.y;
    return c + vec3<f32>(0.3, 0.5, 0.5) * rays * air_underwater * 0.6;
}

fn nether(input: PostInput, color: vec3<f32>) -> vec3<f32> {
    let t = frame.time;
    // Heat shimmer, stronger low on the screen and far away.
    let far = select(1.0, smoothstep(4.0, 40.0, length(view_position(input.uv, input.depth))), input.depth > 0.0);
    let shimmer = vec2<f32>(sin(input.uv.y * 60.0 + t * 4.0), 0.0) * 0.0015 * air_nether * far;
    var c = select(color, textureSampleLevel(previous, linear_sampler, input.uv + shimmer, 0.0).rgb, air_nether > 0.0);
    let dist = select(64.0, length(view_position(input.uv, input.depth)), input.depth > 0.0);
    let amount = (1.0 - exp(-dist * 0.012)) * air_nether;
    return mix(c, frame.fog_color * vec3<f32>(1.25, 0.85, 0.65), clamp(amount, 0.0, 0.75));
}

fn end_air(input: PostInput, color: vec3<f32>) -> vec3<f32> {
    let dist = select(96.0, length(view_position(input.uv, input.depth)), input.depth > 0.0);
    let amount = (1.0 - exp(-dist * 0.008)) * air_end;
    let violet = vec3<f32>(0.22, 0.14, 0.30);
    let c = mix(color, color * vec3<f32>(0.95, 0.85, 1.1), air_end * 0.5);
    return mix(c, violet, clamp(amount, 0.0, 0.7));
}

fn post(input: PostInput) -> vec4<f32> {
    var c = input.color.rgb;
    if frame.eye_in == 1u && air_underwater > 0.0 {
        c = underwater(input);
    } else if frame.eye_in != 0u {
        return input.color;
    } else if frame.dimension == 0 {
        c = overworld_haze(input, c);
    } else if frame.dimension == -1 && air_nether > 0.0 {
        c = nether(input, c);
    } else if frame.dimension == 1 && air_end > 0.0 {
        c = end_air(input, c);
    }
    return vec4<f32>(c, input.color.a);
}
