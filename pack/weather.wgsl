// Rain and snow streaks: rain a little bluer and catching the light, snow
// bright and soft, both as opaque as weather_opacity says.
override weather_opacity: f32 = 0.8;
override weather_tint: f32 = 0.5;

fn weather(input: WeatherInput) -> vec4<f32> {
    let lit = mix(0.35, 1.0, max(input.light.y * mix(0.25, 1.0, daylight()), input.light.x));
    var rgb = input.color.rgb;
    if input.snow {
        rgb = mix(rgb, vec3<f32>(0.95, 0.97, 1.0), weather_tint * 0.5) * lit;
    } else {
        rgb = mix(rgb, vec3<f32>(0.62, 0.72, 0.9), weather_tint) * lit;
    }
    return vec4<f32>(rgb, input.color.a * weather_opacity);
}
