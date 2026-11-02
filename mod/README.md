# Shader Pack Options (`hshader_options`)

A small Horizon **native mod** that lets you change the options of Horizon's own shader packs
(`.hshader`, shader API 0.1), such as Meridian, in game. Horizon 26.3 up to its own Shader Options page
(on `main` from 2026-11-01) always builds a pack with every option at its default. This mod fills the
gap until that page is in the version you play.

Horizon 셰이더 팩(.hshader)의 옵션을 게임 안에서 바꾸는 작은 네이티브 모드입니다. Horizon 본체에
셰이더 옵션 화면이 들어오기 전까지 그 빈자리를 메웁니다.

## Using it

1. Install `hshader_options-<version>.hnmod` from the Mods page of the launcher (or put it in
   `horizon-native-mods/`), turn on **Settings → Game → Native mods (experimental)**, and **Build**.
   Native mods are compiled into the game and are not sandboxed: build only mods you trust.
2. Pick a Horizon pack in **Options → Horizon Settings → Shader Packs**.
3. Open **Options → Mods → Shader Pack Options → Settings**:
   - the first line is the pack and how many options you changed;
   - **Clicks: + raise / - lower** sets which way a click on an option moves it (it wraps at the ends);
   - **Reset all to defaults**;
   - `[+] Group` opens a group: options are grouped by their id up to the first `_` (`shadow_strength`
     is in *Shadow*); a pack with 8 options or fewer is listed without groups.
4. A click takes effect at once in the world (the pack is rebuilt with your values, ~0.1-0.2 s).

The game's language picks English or Korean for the page.

## How it works

- Values are kept in `shaderpacks/<pack file>.txt`, one `id=value` a line (bool 1/0, the number, a
  choice's index; values at their defaults left out): the same file and format as Horizon's own
  Shader Options page, so your choices carry over when you move to a Horizon that has it.
- It hooks only Horizon's **native hook points** (`native_frame`, `native_mods`, `native_settings`,
  `native_settings_click`; `"hooks": 1`), so it is not pinned to one Nightly: the launcher builds it on
  any Horizon that has them. It was tested on Nightly 2026-10-30 (`ba6344a`).
- The game builds the picked pack with its defaults whenever the pack is picked, saved or reloaded.
  About 1.2 s after the mod sees that, it hands the renderer the same pack with your values, through
  the same `set_native_shader_pack` call. A click applies at once. Turning the mod off in Options →
  Mods has the game rebuild the pack with its defaults.
- If your values make a pipeline the GPU refuses, the chat says so and the pack goes back to its
  defaults.

## Files

```
mod/
  horizon-native.json             id, version, "hooks": 1, the commit it was tested on
  mixins/hshader_options/
    horizon-mixin.toml            two modules and four HEAD injections on hook points
    logic.rs                      values, steps, groups, the page (std + horizon_shader_api only)
    runtime.rs                    the game side: when to rebuild, the row, the page, clicks
    frame.rs list.rs settings.rs click.rs   one-line hook helpers
  test-harness/                   cargo test for logic.rs
```

## Building and testing

```sh
python tools/package_mod.py                                   # dist/hshader_options-<version>.hnmod
cargo test --manifest-path mod/test-harness/Cargo.toml        # logic.rs's tests
# Compile check against the game, with horizon-mixins (as the launcher does):
horizon-mixins apply --workspace <horizon source at the commit> --mods mod/mixins --out <stage>
cargo check --locked -p horizon-client                        # in <stage>
```

MIT licensed, as Meridian. Its values format follows Horizon's `shader_pack_list.rs` (MIT).
