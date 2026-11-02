// Sun rays: a radial blur toward the sun's place on screen, gathering only
// the sky (depth 0), so shafts pour through gaps in the trees and hills.
// The moon casts faint ones. Overworld only, not underwater.
override air_rays: f32 = 0.5;

const RAY_SAMPLES: i32 = 32;

// Where a direction lands on screen (uv), and whether it is in front.
fn screen_of(direction: vec3<f32>) -> vec3<f32> {
    let v = (frame.view * vec4<f32>(direction, 0.0)).xyz;
    let clip = frame.projection * vec4<f32>(v, 1.0);
    let ndc = clip.xy / max(abs(clip.w), 1e-4);
    return vec3<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, select(0.0, 1.0, clip.w > 0.0));
}

fn post(input: PostInput) -> vec4<f32> {
    if air_rays <= 0.0 || frame.dimension != 0 || frame.eye_in != 0u {
        return input.color;
    }
    let light = key_direction();
    let s = screen_of(light);
    if s.z == 0.0 {
        return input.color;
    }
    // Fade as the light leaves the screen, and when it's high overhead.
    let off = max(abs(s.x - 0.5), abs(s.y - 0.5));
    let on_screen = 1.0 - smoothstep(0.5, 1.2, off);
    let low = mix(0.45, 1.0, sun_low());
    let fade = on_screen * low * (1.0 - weather());
    if fade <= 0.0 {
        return input.color;
    }

    let delta = (s.xy - input.uv) / f32(RAY_SAMPLES);
    // Jitter the start per pixel so the steps don't band.
    var uv = input.uv + delta * hash21(input.pixel + vec2<f32>(f32(frame.frame_index % 64u)));
    var sum = 0.0;
    var weight = 1.0;
    for (var i = 0; i < RAY_SAMPLES; i++) {
        uv += delta;
        let sky = select(0.0, 1.0, depth_at(uv) == 0.0);
        sum += sky * weight;
        weight *= 0.965;
    }
    let shafts = sum / f32(RAY_SAMPLES);
    let aspect = frame.resolution.x / frame.resolution.y;
    let near = 1.0 - smoothstep(0.0, 0.9, length((input.uv - s.xy) * vec2<f32>(aspect, 1.0)));
    let rays = key_color() * shafts * near * near * fade * air_rays * 0.6;
    return vec4<f32>(input.color.rgb + rays, input.color.a);
}
