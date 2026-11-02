// hshader_options in the game: the option values of Horizon's own shader packs (.hshader, shader
// API 0.1), changed on this mod's page in Options > Mods and used when the pack is drawn.
//
// Horizon 26.3 up to its Shader Options page (on main from 2026-11-01) builds a picked pack with
// every option at its default (`tick_native_shader_pack`). This mod changes nothing of that: it
// hooks only the native hook points (native_frame, native_mods, native_settings,
// native_settings_click), so the launcher can build it on any Horizon that has them. After the
// game has built the pack, it hands the renderer the same pack again with the player's values,
// through the same `set_native_shader_pack` the game uses:
//
//  * once the game has had time to build a pack it looked at anew (picked, saved, reloaded):
//    SETTLE after the mod sees the change, as the game looks at a pack twice a second;
//  * at once after a click on the page, as nothing in the pack's own files changed then;
//  * and, turned off in Options > Mods, by having the game build the pack again with its
//    defaults.
//
// The values are kept where Horizon's own page keeps them (`hshader_options_logic`).
//
// A support module's source takes no file attributes, so these are plain comments.

use super::Game;
use super::hshader_options_logic as logic;
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// The mod's id: its row in Options > Mods.
pub const ID: &str = "hshader_options";
pub const VERSION: &str = "0.1.0";

/// How often the pack and its values file are looked at.
const LOOK_EVERY: Duration = Duration::from_millis(250);
/// How long after a change to the pack the mod builds it with the player's values: more than
/// the game's own look (twice a second) and its build.
const SETTLE: Duration = Duration::from_millis(1200);

#[derive(Default)]
struct State {
    looked: Option<Instant>,
    /// What the game runs and what it was built from: its pick, the pack's files, the values file.
    key: Option<(String, Option<u64>, Option<u64>)>,
    /// When to build the pack with the player's values.
    due: Option<Instant>,
    /// The renderer has the pack with values other than the defaults (from this mod).
    custom: bool,
    /// A key whose build failed: not tried again until something changes.
    failed: Option<(String, Option<u64>, Option<u64>)>,
    /// The page: clicks lower values; the open groups; what each button does.
    back: bool,
    open: HashSet<String>,
    actions: Vec<logic::Action>,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

fn with<R>(f: impl FnOnce(&mut State) -> R) -> R {
    let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    f(guard.get_or_insert_with(State::default))
}

/// The pack the player picked (Options > Horizon Settings > Shader Packs, or
/// `HORIZON_SHADER_PACK` as the game reads it), as a path when it is one of Horizon's own.
fn picked_pack(game: &Game<'_>) -> (String, Option<PathBuf>) {
    let name = std::env::var("HORIZON_SHADER_PACK")
        .unwrap_or_else(|_| game.settings.horizon.shader_pack.clone());
    (name.clone(), pack_path(&name))
}

fn pack_path(name: &str) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    let path = Game::shader_packs_dir().join(name);
    horizon_shader_api::package::is_pack(&path).then_some(path)
}

fn key_of(name: &str, path: &std::path::Path) -> (String, Option<u64>, Option<u64>) {
    (
        name.to_owned(),
        logic::fingerprint(path),
        logic::fingerprint(&logic::values_path(path)),
    )
}

/// Once a frame (native_frame).
pub(super) fn frame(game: &mut Game<'_>) {
    if !game.native_window() {
        return;
    }
    let now = Instant::now();
    let on = game.native_on(ID);
    // The pack the game runs now; empty until a world is drawn with one.
    let running = game.native_shaders.picked.clone();
    let path = pack_path(&running);
    enum Do {
        Nothing,
        Build(PathBuf),
        Defaults,
    }
    let todo = with(|s| {
        let due_now = s.due.is_some_and(|d| now >= d);
        if !due_now && s.looked.is_some_and(|t| now - t < LOOK_EVERY) {
            return Do::Nothing;
        }
        s.looked = Some(now);
        let Some(path) = path else {
            s.key = None;
            s.due = None;
            s.custom = false;
            return Do::Nothing;
        };
        let key = key_of(&running, &path);
        if s.key.as_ref() != Some(&key) {
            s.key = Some(key.clone());
            s.due = Some(now + SETTLE);
            s.failed = None;
            return Do::Nothing;
        }
        if !on {
            s.due = None;
            if s.custom {
                s.custom = false;
                return Do::Defaults;
            }
            return Do::Nothing;
        }
        if !s.due.is_some_and(|d| now >= d) || s.failed.as_ref() == Some(&key) {
            return Do::Nothing;
        }
        s.due = None;
        Do::Build(path)
    });
    match todo {
        Do::Nothing => {}
        Do::Defaults => game.native_shaders = super::native_shaders::NativeShaders::picking(&running),
        Do::Build(path) => build(game, &running, &path),
    }
}

/// Hands the renderer the pack at `path` with the player's values.
fn build(game: &mut Game<'_>, running: &str, path: &std::path::Path) {
    let started = Instant::now();
    let pack = match horizon_shader_api::Pack::read(path) {
        Ok(p) => p,
        Err(e) => return fail(game, path, e, false),
    };
    let options = &pack.manifest.options;
    let values = logic::load_values(path, options);
    let changed = logic::customised(options, &values);
    // The game's own build has every default: nothing to do unless this mod changed it before.
    if changed == 0 && !with(|s| s.custom) {
        return;
    }
    let report = match horizon_shader_api::check(&pack) {
        Ok(r) => r,
        // The game says what is wrong with the pack itself.
        Err(_) => return fail(game, path, String::new(), false),
    };
    let constants: Vec<(String, f64)> = options.iter().map(|o| o.id.clone()).zip(values).collect();
    let Some(renderer) = game.renderer.as_mut() else {
        return;
    };
    match renderer.set_native_shader_pack(Some((report, constants))) {
        Ok(_) => {
            with(|s| s.custom = changed > 0);
            log::info!(
                "[{ID}] shader pack {} {} with {changed} option(s) changed in {} ms",
                pack.manifest.id,
                pack.manifest.version,
                started.elapsed().as_millis()
            );
        }
        Err(e) => {
            // These values make a pipeline the GPU refuses: back to the defaults, and say so.
            fail(game, path, e, true);
            game.native_shaders = super::native_shaders::NativeShaders::picking(running);
        }
    }
}

fn fail(game: &mut Game<'_>, path: &std::path::Path, error: String, tell: bool) {
    with(|s| {
        s.failed = s.key.clone();
        s.custom = false;
    });
    if !error.is_empty() {
        log::warn!("[{ID}] {}: {error}", path.display());
    }
    if tell {
        let name = path.file_name().unwrap_or_default().to_string_lossy();
        game.native_chat(&format!("[Shader pack options] {name}: {error}"));
    }
}

/// The mod's row in Options > Mods (native_mods).
pub fn listed(mods: &mut Vec<super::native_hooks::NativeMod>) {
    let korean = horizon_client::lang::code().starts_with("ko");
    mods.push(super::native_hooks::NativeMod {
        id: ID.into(),
        title: if korean {
            format!("셰이더 팩 옵션 {VERSION}")
        } else {
            format!("Shader Pack Options {VERSION}")
        },
        description: if korean {
            "Horizon 셰이더 팩(.hshader)의 옵션을 바꿉니다.".into()
        } else {
            "Change the options of Horizon shader packs (.hshader).".into()
        },
        keys: Vec::new(),
    });
}

/// The page's buttons (native_settings), asked when it opens and after each click.
pub(super) fn settings(game: &mut Game<'_>, buttons: &mut Vec<String>) {
    let w = logic::words(&horizon_client::lang::code());
    let (on, off) = (
        horizon_client::lang::get("options.on"),
        horizon_client::lang::get("options.off"),
    );
    let (name, path) = picked_pack(game);
    let page = match path {
        None => logic::Page {
            labels: vec![w.no_pack.to_owned(), w.pick_one.to_owned()],
            actions: vec![logic::Action::Refresh, logic::Action::Refresh],
        },
        Some(path) => match horizon_shader_api::Pack::read(&path) {
            Err(e) => logic::Page {
                labels: vec![format!("{name}: {e}")],
                actions: vec![logic::Action::Refresh],
            },
            Ok(pack) => {
                let m = &pack.manifest;
                let values = logic::load_values(&path, &m.options);
                let title = format!("{} {}", m.name, m.version);
                with(|s| logic::page(&title, &m.options, &values, s.back, &s.open, w, &on, &off))
            }
        },
    };
    with(|s| s.actions = page.actions);
    buttons.extend(page.labels);
}

/// A click on button `button` of the page (native_settings_click).
pub(super) fn click(game: &mut Game<'_>, button: usize) {
    let Some(action) = with(|s| s.actions.get(button).cloned()) else {
        return;
    };
    let (name, path) = picked_pack(game);
    match action {
        logic::Action::Refresh => {}
        logic::Action::Direction => with(|s| s.back = !s.back),
        logic::Action::Group(g) => with(|s| {
            if !s.open.remove(&g) {
                s.open.insert(g);
            }
        }),
        logic::Action::ResetAll | logic::Action::Step(_) => {
            let Some(path) = path else { return };
            let Ok(pack) = horizon_shader_api::Pack::read(&path) else {
                return;
            };
            let options = &pack.manifest.options;
            let mut values = logic::load_values(&path, options);
            match action {
                logic::Action::Step(i) if i < options.len() => {
                    let back = with(|s| s.back);
                    values[i] = logic::step_value(&options[i].kind, values[i], back);
                }
                logic::Action::ResetAll => {
                    values = options.iter().map(|o| o.kind.default_constant()).collect();
                }
                _ => return,
            }
            if let Err(e) = logic::save_values(&path, options, &values) {
                log::warn!("[{ID}] saving {}: {e}", logic::values_path(&path).display());
                return;
            }
            // The game runs this pack: build it with the new values now (its own files did not
            // change, so the game itself builds nothing). Otherwise the values wait for the pack.
            if game.native_shaders.picked == name {
                let key = key_of(&name, &path);
                with(|s| {
                    s.key = Some(key);
                    s.failed = None;
                    s.due = Some(Instant::now());
                });
            }
        }
    }
}
