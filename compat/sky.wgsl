// A cheap analytic atmosphere: Rayleigh scattering along the view ray, lit
// by sunlight reddened by its own path through the air, plus a Mie halo.
// Blended over vanilla's sky by day; at night vanilla's sky is kept, a
// little bluer. Rain pulls it back to vanilla's grey.
override sky_scatter: f32 = 0.7;
override sky_halo: f32 = 0.6;

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
    let wet = weather();

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

    // Rain: greyer.
    c = mix(c, vec3<f32>(luma(c)), wet * 0.4);
    return vec4<f32>(max(c, vec3<f32>(0.0)), input.color.a);
}
