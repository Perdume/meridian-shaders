// A cheap analytic atmosphere: Rayleigh scattering along the view ray, lit
// by sunlight reddened by its own path through the air, plus a Mie halo.
// Blended over vanilla's sky by day; at night vanilla's sky is kept, a
// little bluer. Rain pulls it back to vanilla's grey.
override sky_scatter: f32 = 0.7;
override sky_halo: f32 = 0.6;
override sky_stars: f32 = 0.6;
override sky_cirrus: f32 = 0.4;
override sky_aurora: f32 = 0.5;

fn rayleigh_phase(mu: f32) -> f32 {
    return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
}

fn mie_phase(mu: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5));
}

fn atmosphere(d: vec3<f32>, sun: vec3<f32>) -> vec3<f32> {
    let beta = vec3<f32>(0.18, 0.42, 1.0);
    let mu = dot(d, sun);
    // Air along the ray: 1 straight up, about 6.7 at the horizon.
    let view_air = 1.0 / (max(d.y, 0.0) * 0.85 + 0.15);
    let sun_air = 1.0 / (max(sun.y, 0.0) * 0.85 + 0.15);
    let sunlight = exp(-beta * sun_air * 0.45);
    let inscatter = (1.0 - exp(-beta * view_air * 0.9)) * (0.55 + rayleigh_phase(mu) * 4.0);
    let halo = mie_phase(mu, 0.78) * 0.08 * sky_halo * (1.0 - exp(-view_air * 0.3));
    return sunlight * (inscatter * 1.1 + vec3<f32>(halo));
}

fn sky(input: SkyInput) -> vec4<f32> {
    let d = input.direction;
    let vanilla = input.color.rgb;
    let day = daylight();
    let wet = wet_weather();

    // Below the horizon the ground's haze: the horizon's colour, darkened.
    let dd = vec3<f32>(d.x, max(d.y, 0.0), d.z);
    var custom = atmosphere(normalize(dd + vec3<f32>(0.0, 1e-3, 0.0)), frame.sun_direction);
    custom *= mix(1.0, 0.55, smoothstep(0.0, -0.3, d.y));
    // Keep vanilla's overall brightness so the Brightness option and
    // the day cycle still read the same.
    custom *= clamp(luma(vanilla) / max(luma(custom), 1e-3), 0.6, 1.6);

    let weight = sky_scatter * day * (1.0 - wet);
    var c = mix(vanilla, custom, weight);

    // Night: a deeper blue overhead, slightly brighter at the horizon.
    let night = (1.0 - day) * select(0.0, 1.0, frame.dimension == 0);
    let zenith = smoothstep(0.0, 1.0, d.y);
    c *= mix(vec3<f32>(1.0), mix(vec3<f32>(1.0, 1.02, 1.1), vec3<f32>(0.8, 0.9, 1.15), zenith), night);

    // High thin clouds (cirrus), drifting, lit by the sun and coloured at dusk.
    if sky_cirrus > 0.0 && d.y > 0.02 && frame.dimension == 0 {
        let plane = d.xz / (d.y + 0.15) * 3.0 + vec2<f32>(frame.time * 0.004, frame.time * 0.002);
        let streak = fbm2(plane * vec2<f32>(1.0, 3.0));
        let cloud = smoothstep(0.5, 0.85, streak) * smoothstep(0.02, 0.25, d.y) * sky_cirrus;
        let lit = mix(vec3<f32>(0.25, 0.27, 0.35), sun_tint() * 1.1, day) * mix(1.0, 0.6, wet);
        c = mix(c, lit, cloud * 0.6);
    }

    // At night: stars, the band of the Milky Way, and in cold biomes an aurora.
    if night > 0.0 && d.y > 0.0 {
        // The sky turns with the time of day.
        let a = frame.day_time * 6.2831853;
        let rd = vec3<f32>(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a), d.z);
        let cell = floor(rd * 180.0);
        let star = step(0.9975, hash21(cell.xy + cell.z * 37.1)) * hash21(cell.yz + 3.7);
        let band = exp(-pow(dot(rd, normalize(vec3<f32>(0.3, 0.5, 0.8))) * 3.0, 2.0));
        let milky = band * fbm2(rd.xz * 6.0 + rd.y * 3.0) * vec3<f32>(0.35, 0.33, 0.45);
        let clear = night * (1.0 - wet) * smoothstep(0.0, 0.2, d.y);
        c += (vec3<f32>(star) * 1.2 + milky * 0.25) * sky_stars * clear;
        if sky_aurora > 0.0 {
            let h = d.xz / (d.y + 0.25);
            let curtain = fbm2(vec2<f32>(h.x * 1.5 + frame.time * 0.03, frame.time * 0.02));
            let ribbon = smoothstep(0.35, 0.0, abs(h.y * 0.6 - curtain + 0.3)) * smoothstep(0.05, 0.4, d.y);
            let color = mix(vec3<f32>(0.1, 0.9, 0.5), vec3<f32>(0.5, 0.2, 0.9), smoothstep(0.2, 0.7, d.y));
            c += color * ribbon * sky_aurora * biome_cold() * clear * 0.6;
        }
    }

    // Rain: greyer.
    c = mix(c, vec3<f32>(luma(c)), wet * 0.4);
    return vec4<f32>(max(c, vec3<f32>(0.0)), input.color.a);
}
