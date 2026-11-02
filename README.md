# Meridian — a shader pack for Horizon

**Meridian** is a shader pack for [Horizon](https://github.com/horizon-rust/horizon), the Rust reimplementation of
Minecraft: Java Edition. It is written in WGSL against Horizon's own shader API (0.1), so it runs on Vulkan, Metal
and DirectX 12 and passes the same check the game, the launcher and the registry run.

Horizon 전용 셰이더 팩입니다. Horizon 자체 셰이더 API(0.1)에 맞춰 WGSL로 작성했으며, 게임·런처·레지스트리가
사용하는 공식 검사(`horizon-shader check`)를 통과합니다.

## Two packs, one source

| Pack | For | Shadows |
|---|---|---|
| **`meridian-<version>.hshader`** | Horizon **Nightly 2026-11-01** and later | the engine's **shadow map** (`[shadow]`): drawn from the sun each frame, the same whichever way you look; terrain, trees, mobs and the player (in first person too) cast them; light through water and stained glass takes their colour |
| `meridian_compat-<version>.hshader` | Horizon **0.2.97** (the latest release) and older Nightlies, which refuse `[shadow]` | screen-space shadows plus sky-light shade under cover (a caster must be on screen) |

`pack/` is Meridian; `compat/` holds only the files that differ for the compat pack. `tools/build_packs.py` builds both
into `dist/packs/`, and CI checks each against the Horizon it is for.

이 저장소는 팩 두 개를 만듭니다. `meridian`은 최신 Nightly의 그림자 맵을 써서 시선과 상관없이 그림자가 일정하고,
`meridian_compat`은 최신 릴리스(0.2.97)용 화면 공간 그림자 버전입니다.

## Effects (meridian, Nightly 2026-11-01+)

| Stage | What it does |
|---|---|
| **sky** | Rayleigh scattering with a reddened low sun and a Mie halo; high thin clouds coloured at dusk; stars and the Milky Way turning with the night; an aurora over cold biomes |
| **material** | sun shadows from the engine's shadow map (soft edges, light tinted through water and stained glass); warm sunlit faces and cool shade; **coloured block light** (soul fire blue, redstone red, amethyst violet... 11 groups); glowing blocks; light through leaves and grass; **wet, glossy ground in the rain**; biome mood (bluer snow, warmer desert, greener swamp); **LabPBR normal and specular maps**; shine on metal, glass and ice; **clear water** with waves, refraction, depth absorption, caustics, shore foam, a mirror of the world and sun glints; an optional floor to cave darkness |
| **weather** | rain catching a cool light, bright snow, adjustable opacity |
| post 1 · Shadows and AO | **ambient occlusion** on everything; shadow-map shadows on mobs, the player, water and glass |
| post 2 · Air | height haze tinted by biome; **under water**: wavering, distance absorption, swaying light shafts; **Nether** heat shimmer and red haze; **End** violet air |
| post 3 · Sun rays | light shafts through gaps in the terrain; faint moon rays |
| post 4–5 · Bloom, Lens | half-size bloom with threshold and size; **depth of field** (auto-focus), **motion blur**, **chromatic aberration** (off by default) |
| post 6 · Tone map and grade | ACES / Soft / Off in linear light, exposure, **eye adaptation**, contrast, saturation, vibrance, colour temperature, golden hour, night blue shift, vignette, film grain |
| post 7 · Temporal AA | steadies shimmering edges and leaves, smooths shadow and AO grain |
| post 8 · Sharpen | contrast-adaptive sharpening and a dither against banding |

The compat pack (`meridian_compat`, Horizon 0.2.97) keeps the 0.4 feature set: screen-space shadows, simpler water,
the earlier sky and post passes (`compat/` holds its own copies).

### Options

**Quality preset** at the top of the options: **Low / Medium / High (default) / Ultra** sets in one click how many
samples the costly effects take: shadow-map taps 4/8/12/20, ambient occlusion off/4/8/12, sun rays 16/24/32/48,
bloom 8/12/16/24, depth of field 6/8/12/16, motion blur 4/6/8/12; Low also drops caustics and shore foam.

Then **58 more options** on 8 pages of Horizon's Shader Options screen (Options → Horizon Settings → Shader Packs →
Shader Options...): **Lighting** (13), **Shadows** (5), **Water** (9), **Sky** (5), **Air and weather** (7),
**Camera** (9), **Colour** (8), **Anti-aliasing** (2). Values move in coarse steps (mostly 0.1): a click steps up, a
right click down, shift-click resets one, Reset resets all. (Horizon draws a pack's options as buttons; sliders are
only for `shaders/`-format packs.) `tools/make_manifest.py` generates the manifest, options and pages from one table.

On Horizon 0.2.97 and older Nightlies, `meridian_compat`'s 23 options are its defaults, or every option in game with the
native mod in [`mod/`](mod/README.md) (*Shader Pack Options*).

## Install

1. Download `meridian-<version>.hshader` (Nightly 2026-11-01+) or `meridian_compat-<version>.hshader` (0.2.97) from
   [Releases](../../releases), or build them (below).
2. Put it in `shaderpacks/` beside `options.txt` in your Horizon game folder (Shader Packs > Open Pack Folder).
3. Options > Horizon Settings > Shader Packs > **Meridian (Horizon)**.

## Build and check

```sh
cargo install --locked --git https://github.com/horizon-rust/horizon --tag <latest release> \
  horizon-shader-api --bin horizon-shader
python tools/build_packs.py                    # dist/packs/meridian and dist/packs/meridian_compat
horizon-shader check dist/packs/meridian          # with the Nightly's checker (`--rev <nightly commit>`)
horizon-shader check dist/packs/meridian_compat   # with the release's checker
horizon-shader pack dist/packs/meridian           # writes meridian-<version>.hshader
```

On Windows without Visual Studio's C++ tools, the GNU toolchain works:
`cargo +stable-x86_64-pc-windows-gnu install ...` (needs MinGW `gcc` on `PATH`).

To edit live: put the `pack` folder (renamed `meridian`) in `shaderpacks/`, pick it, and save a file: the game rechecks
and reloads it twice a second, keeping the last good version if the new one fails.

## Staying current with Horizon

[`.github/workflows/check.yml`](.github/workflows/check.yml) builds both packs and checks `meridian` with the checker of
**Horizon's newest Nightly** and `meridian_compat` with that of **Horizon's latest release**, on every push, pull request
and weekly, so a Horizon version that changes the API breaks CI here before it breaks a player's game. Pushing a `v*`
tag publishes both `.hshader` files and the native mod as a GitHub release.

Last checked against: `meridian` on Nightly 2026-11-01 (`c9d474d`), `meridian_compat` on v0.2.97 (shader API 0.1), and
both in game.

## Layout

```
pack/                     Meridian: manifest ([shadow]), shared helpers, stages
  horizon-shaders.toml    stages, the shadow map, options
  common.wgsl             shared helpers (only `frame` is available here)
  sky.wgsl  material.wgsl (shadow map, clear water)
  post/shadows.wgsl (entity shadows) haze.wgsl rays.wgsl bloom.wgsl tonemap.wgsl sharpen.wgsl
compat/                   the files that differ for meridian_compat (Horizon 0.2.97)
  horizon-shaders.toml  material.wgsl  post/shadows.wgsl  post/shadow_filter.wgsl
mod/                      the Shader Pack Options native mod, for Horizon without its own options page
tools/build_packs.py      builds dist/packs/meridian and dist/packs/meridian_compat
tools/package_mod.py      packs mod/ into dist/hshader_options-<version>.hnmod
.github/workflows/        CI: each pack against the Horizon it is for
```

## License

MIT — see [LICENSE](LICENSE). Horizon itself is MIT licensed; Meridian uses only its public shader API and contains no
Horizon or Mojang code or assets.
