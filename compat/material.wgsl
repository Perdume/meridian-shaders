// Lit block surfaces. Vanilla's colour is albedo * tint * lightmap; this
// stage changes the light: sunlit faces warm, faces turned from the sun
// cool, torchlight orange, and water ripples, reflects the sky and glints.
override light_warmth: f32 = 0.5;
override light_shade: f32 = 0.35;
override light_torch: f32 = 0.6;
override water_living: bool = true;
override water_waves: f32 = 1.0;
override water_reflection: f32 = 0.6;
override water_clarity: f32 = 0.6;
override water_tint: u32 = 0u;       // 0 Biome, 1 Clear blue, 2 Turquoise, 3 Deep green
override light_contrast: f32 = 1.1;
// Shared with the post shadow passes: one slider for both kinds of shadow.
override shadow_strength: f32 = 0.7;

// The face's normal from the screen-space change of position. Called first,
// in uniform control flow, as derivatives must be.
fn face_normal(position: vec3<f32>) -> vec3<f32> {
    let c = cross(dpdx(position), dpdy(position));
    let len2 = dot(c, c);
    var n = select(vec3<f32>(0.0, 1.0, 0.0), c * inverseSqrt(max(len2, 1e-20)), len2 > 1e-20);
    // Face the camera (position is camera-relative).
    n = select(n, -n, dot(n, position) > 0.0);
    return n;
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

fn material(input: MaterialInput) -> Surface {
    let n = face_normal(input.position);
    let sky = input.light.y;
    let block = input.light.x;
    let day = daylight();
    let sun = frame.sun_direction;

    // How much of the light here is daylight: none in caves (no sky light)
    // or where torches outshine it.
    let skylit = smoothstep(0.2, 0.6, sky) * (1.0 - smoothstep(0.5, 1.0, block) * 0.7);
    let direct = skylit * day * (1.0 - weather());
    // Cover overhead, from the world's own sky light: 15 is open sky, and
    // every leaf or roof block above takes a level off (12-14 under a tree).
    // Unlike the screen-space trace this needs no caster on screen, so the
    // shade under a tree stays when the canopy is above the view.
    // Full at 13, a fifth at 14 (the edge of a canopy), none at 15.
    let cover = 1.0 - smoothstep(0.87, 0.96, sky);
    let sunlit = 1.0 - cover;

    // Sunlight and shade, only where the sun reaches.
    let facing = max(dot(n, sun), 0.0);
    var light = input.lightmap;
    let warm = sun_tint() * mix(0.85, 1.12, facing);
    light *= mix(vec3<f32>(1.0), warm, direct * sunlit * light_warmth);
    light *= mix(vec3<f32>(1.0), vec3<f32>(0.86, 0.93, 1.08), direct * sunlit * (1.0 - facing) * light_shade);
    // Under cover: the skylight blue of a shadow (as shadow_filter.wgsl).
    light *= mix(vec3<f32>(1.0), vec3<f32>(0.55, 0.62, 0.78), direct * cover * shadow_strength);

    // Torchlight where block light outshines the sky.
    let torch = smoothstep(0.25, 1.0, block) * (1.0 - sky * day) * light_torch;
    light *= mix(vec3<f32>(1.0), vec3<f32>(1.15, 0.95, 0.72), torch);

    light = pow(max(light, vec3<f32>(0.0)), vec3<f32>(light_contrast));
    var color = input.albedo * input.tint * vec4<f32>(light, 1.0);

    // Water: translucent, biome-tinted blue and facing up. Stained glass and
    // ice aren't tinted this way, so they keep vanilla's look.
    // Without the world behind the water (Horizon 0.2.97 has none), clarity is
    // its opacity, and its colour a tint.
    let watery = input.translucent && input.tint.b > input.tint.r * 1.15;
    if watery {
        let tinted = water_color(input.tint.rgb * input.albedo.rgb) * light;
        let rgb = select(color.rgb, tinted, water_tint != 0u);
        color = vec4<f32>(rgb, clamp(color.a * mix(1.25, 0.35, water_clarity), 0.05, 1.0));
    }
    let is_water = watery && n.y > 0.9;
    if water_living && is_water {
        let world = frame.camera_position.xz + input.position.xz;
        let t = frame.time;
        let h0 = noise2(world * 0.9 + vec2<f32>(t * 0.6, t * 0.35));
        let h1 = noise2(world * 2.3 - vec2<f32>(t * 0.4, t * 0.9));
        let ripple = vec2<f32>(h0 - 0.5, h1 - 0.5);
        let wn = normalize(vec3<f32>(ripple.x * 0.12 * water_waves, 1.0, ripple.y * 0.12 * water_waves));

        let to_eye = normalize(-input.position);
        let cos_v = max(dot(wn, to_eye), 0.0);
        let fresnel = 0.03 + 0.97 * pow(1.0 - cos_v, 5.0);

        // The sky seen in the water, only as bright as the sky light here.
        let reflected = mix(frame.fog_color, frame.sky_color, 0.6) * mix(0.3, 1.0, sky);
        color = vec4<f32>(mix(color.rgb, reflected, fresnel * water_reflection), mix(color.a, 1.0, fresnel * water_reflection * 0.8));

        // A glint of the sun (or moon).
        let r = reflect(-to_eye, wn);
        let glint = pow(max(dot(r, key_direction()), 0.0), 600.0) * smoothstep(0.55, 1.0, sky) * (1.0 - weather());
        color = vec4<f32>(color.rgb + key_color() * glint * 0.6, min(color.a + glint * 0.5, 1.0));
    }
    return Surface(color);
}
