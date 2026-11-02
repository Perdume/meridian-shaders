// hshader_options, the part that knows no game: where a Horizon shader pack's option values
// are kept, how a click steps one, how a value is shown, and the buttons of the settings page.
// It is the module `game::hshader_options_logic` in the game, and the library the tests build
// (mod/test-harness), so it uses only std and horizon_shader_api.
//
// The values file is Horizon's own format, from its upcoming Shader Options page
// (crates/horizon-client-render/src/shader_pack_list.rs on main, MIT): `<pack>.txt` beside the
// pack, one `id=value` a line, each value the pipeline constant (bool 1/0, the number, a choice's
// index), values at their defaults left out. A player who moves to a Horizon with that page keeps
// their choices.
//
// A support module's source takes no file attributes, so these are plain comments.

use horizon_shader_api::{OptionKind, PackOption};
use std::collections::HashSet;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

/// Where the option values of the pack at `pack` are kept: `<pack>.txt` beside it.
pub fn values_path(pack: &Path) -> PathBuf {
    let mut path = pack.as_os_str().to_owned();
    path.push(".txt");
    PathBuf::from(path)
}

/// The value of each of `options` in `text` (a values file), else its default; a value out of
/// the option's range is brought into it.
pub fn parse_values(text: &str, options: &[PackOption]) -> Vec<f64> {
    let saved: std::collections::HashMap<&str, f64> = text
        .lines()
        .filter_map(|l| l.split_once('='))
        .filter_map(|(k, v)| Some((k.trim(), v.trim().parse::<f64>().ok()?)))
        .filter(|(_, v)| v.is_finite())
        .collect();
    options
        .iter()
        .map(|o| {
            saved
                .get(o.id.as_str())
                .map_or_else(|| o.kind.default_constant(), |&v| clamp(&o.kind, v))
        })
        .collect()
}

/// The values saved for the pack at `pack`, else the defaults.
pub fn load_values(pack: &Path, options: &[PackOption]) -> Vec<f64> {
    let text = std::fs::read_to_string(values_path(pack)).unwrap_or_default();
    parse_values(&text, options)
}

/// The values file's text: the values not at their defaults.
pub fn values_text(options: &[PackOption], values: &[f64]) -> String {
    options
        .iter()
        .zip(values)
        .filter(|(o, v)| o.kind.default_constant() != **v)
        .map(|(o, v)| format!("{}={v}\n", o.id))
        .collect()
}

/// Saves `values`; with every value at its default the file goes.
pub fn save_values(pack: &Path, options: &[PackOption], values: &[f64]) -> std::io::Result<()> {
    let text = values_text(options, values);
    let path = values_path(pack);
    if text.is_empty() {
        match std::fs::remove_file(&path) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
            _ => Ok(()),
        }
    } else {
        std::fs::write(path, text)
    }
}

/// Whether any value differs from its option's default.
pub fn customised(options: &[PackOption], values: &[f64]) -> usize {
    options
        .iter()
        .zip(values)
        .filter(|(o, v)| o.kind.default_constant() != **v)
        .count()
}

pub fn clamp(kind: &OptionKind, v: f64) -> f64 {
    match kind {
        OptionKind::Bool { .. } => f64::from(u8::from(v != 0.0)),
        OptionKind::Float { min, max, .. } => v.clamp(f64::from(*min), f64::from(*max)),
        OptionKind::Int { min, max, .. } => v.round().clamp(f64::from(*min), f64::from(*max)),
        OptionKind::Choice { values, .. } => v.round().clamp(0.0, values.len() as f64 - 1.0),
    }
}

/// The option's next value (`back`: the one before), wrapping around at the ends, as Horizon's
/// own page steps it.
pub fn step_value(kind: &OptionKind, v: f64, back: bool) -> f64 {
    let dir = if back { -1.0 } else { 1.0 };
    match kind {
        OptionKind::Bool { .. } => f64::from(u8::from(v == 0.0)),
        OptionKind::Float { min, max, step, .. } => {
            let (min, max, step) = (f64::from(*min), f64::from(*max), f64::from(*step));
            if !back && v >= max - step * 0.01 {
                min
            } else if back && v <= min + step * 0.01 {
                max
            } else {
                // On the grid of steps from the minimum, so float error never piles up.
                let n = ((v - min) / step).round() + dir;
                (min + n * step).clamp(min, max)
            }
        }
        OptionKind::Int { min, max, .. } => {
            let (min, max) = (f64::from(*min), f64::from(*max));
            let n = v.round() + dir;
            if n > max {
                min
            } else if n < min {
                max
            } else {
                n
            }
        }
        OptionKind::Choice { values, .. } => {
            let n = values.len() as f64;
            (v.round() + dir).rem_euclid(n)
        }
    }
}

/// The value as the page shows it; `on`/`off` are the game's own words.
pub fn show_value(kind: &OptionKind, v: f64, on: &str, off: &str) -> String {
    match kind {
        OptionKind::Bool { .. } => (if v != 0.0 { on } else { off }).to_owned(),
        OptionKind::Float { step, .. } => {
            let digits = if *step >= 1.0 {
                0
            } else if *step >= 0.1 {
                1
            } else {
                2
            };
            format!("{v:.digits$}")
        }
        OptionKind::Int { .. } => format!("{v:.0}"),
        OptionKind::Choice { values, .. } => {
            values.get(v.round() as usize).cloned().unwrap_or_default()
        }
    }
}

/// An option's group: its id up to the first `_` (`shadow_strength` is in `shadow`), or "" for
/// an id without one.
pub fn group_of(id: &str) -> &str {
    match id.split_once('_') {
        Some((g, rest)) if !g.is_empty() && !rest.is_empty() => g,
        _ => "",
    }
}

/// A group's title: its prefix with a capital, or `general` for "".
pub fn group_title(group: &str, general: &str) -> String {
    let mut chars = group.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().chain(chars).collect(),
        None => general.to_owned(),
    }
}

/// The groups of `options` in the order they first appear.
pub fn groups(options: &[PackOption]) -> Vec<&str> {
    let mut out: Vec<&str> = Vec::new();
    for o in options {
        let g = group_of(&o.id);
        if !out.contains(&g) {
            out.push(g);
        }
    }
    out
}

/// A hash of a pack's file names, sizes and modification times, as the game looks at a pack
/// (`None` when unreadable).
pub fn fingerprint(path: &Path) -> Option<u64> {
    fn walk(path: &Path, hasher: &mut std::hash::DefaultHasher) -> Option<()> {
        let meta = std::fs::metadata(path).ok()?;
        path.hash(hasher);
        if meta.is_dir() {
            let mut entries: Vec<_> = std::fs::read_dir(path)
                .ok()?
                .flatten()
                .map(|e| e.path())
                .collect();
            entries.sort();
            for entry in entries {
                walk(&entry, hasher)?;
            }
        } else {
            meta.len().hash(hasher);
            meta.modified().ok()?.hash(hasher);
        }
        Some(())
    }
    let mut hasher = std::hash::DefaultHasher::new();
    walk(path, &mut hasher)?;
    Some(hasher.finish())
}

/// The page's words, in the game's language.
pub struct Words {
    pub no_pack: &'static str,
    pub pick_one: &'static str,
    pub options: &'static str,
    pub raise: &'static str,
    pub lower: &'static str,
    pub reset: &'static str,
    pub changed: &'static str,
    pub default: &'static str,
    pub general: &'static str,
    pub no_options: &'static str,
}

pub const ENGLISH: Words = Words {
    no_pack: "No Horizon shader pack (.hshader) is picked",
    pick_one: "Pick one: Options > Horizon Settings > Shader Packs",
    options: "options",
    raise: "Clicks: + raise values",
    lower: "Clicks: - lower values",
    reset: "Reset all to defaults",
    changed: "changed",
    default: "default",
    general: "General",
    no_options: "This pack has no options",
};

pub const KOREAN: Words = Words {
    no_pack: "선택된 Horizon 셰이더 팩(.hshader)이 없습니다",
    pick_one: "설정 > Horizon Settings > Shader Packs에서 고르세요",
    options: "옵션",
    raise: "클릭: + 값 올리기",
    lower: "클릭: - 값 내리기",
    reset: "모두 기본값으로",
    changed: "변경",
    default: "기본",
    general: "일반",
    no_options: "이 팩에는 옵션이 없습니다",
};

/// The words for language `code` (`ko_kr`, `en_us`...).
pub fn words(code: &str) -> &'static Words {
    if code.starts_with("ko") { &KOREAN } else { &ENGLISH }
}

/// What a button of the page does.
#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    /// Nothing but asking the labels again (the pack's own line, a note).
    Refresh,
    /// Clicks raise or lower values.
    Direction,
    /// Every option back to its default.
    ResetAll,
    /// Open or close a group.
    Group(String),
    /// Step option `i` (its index in the manifest).
    Step(usize),
}

/// The settings page: a label and an action for each button.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Page {
    pub labels: Vec<String>,
    pub actions: Vec<Action>,
}

impl Page {
    fn push(&mut self, label: String, action: Action) {
        self.labels.push(label);
        self.actions.push(action);
    }
}

/// Packs with at most this many options, or a single group, list them without groups.
pub const FLAT_UP_TO: usize = 8;

/// The page for the pack `title` with `options` at `values`: its line, the direction of clicks,
/// reset, then each group (open ones with their options), or every option when the pack has few.
#[allow(clippy::too_many_arguments)]
pub fn page(
    title: &str,
    options: &[PackOption],
    values: &[f64],
    back: bool,
    open: &HashSet<String>,
    w: &Words,
    on: &str,
    off: &str,
) -> Page {
    let mut p = Page::default();
    let changed = customised(options, values);
    let head = if changed > 0 {
        format!("{title}: {} {} ({changed} {})", options.len(), w.options, w.changed)
    } else {
        format!("{title}: {} {}", options.len(), w.options)
    };
    p.push(head, Action::Refresh);
    if options.is_empty() {
        p.push(w.no_options.to_owned(), Action::Refresh);
        return p;
    }
    p.push((if back { w.lower } else { w.raise }).to_owned(), Action::Direction);
    p.push(w.reset.to_owned(), Action::ResetAll);
    let option_label = |i: usize| {
        let (o, v) = (&options[i], values[i]);
        let shown = show_value(&o.kind, v, on, off);
        let default = o.kind.default_constant();
        if v == default {
            format!("{}: {shown}", o.name)
        } else {
            let d = show_value(&o.kind, default, on, off);
            format!("{}: {shown}  ({} {d})", o.name, w.default)
        }
    };
    let groups = groups(options);
    if options.len() <= FLAT_UP_TO || groups.len() < 2 {
        for i in 0..options.len() {
            p.push(option_label(i), Action::Step(i));
        }
        return p;
    }
    for g in groups {
        let members: Vec<usize> = (0..options.len())
            .filter(|&i| group_of(&options[i].id) == g)
            .collect();
        let edited = members
            .iter()
            .filter(|&&i| options[i].kind.default_constant() != values[i])
            .count();
        let is_open = open.contains(g);
        let mark = if is_open { "[-]" } else { "[+]" };
        let title = group_title(g, w.general);
        let label = if edited > 0 {
            format!("{mark} {title} ({}, {edited} {})", members.len(), w.changed)
        } else {
            format!("{mark} {title} ({})", members.len())
        };
        p.push(label, Action::Group(g.to_owned()));
        if is_open {
            for i in members {
                p.push(option_label(i), Action::Step(i));
            }
        }
    }
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opt(id: &str, kind: OptionKind) -> PackOption {
        PackOption {
            id: id.into(),
            name: id.into(),
            description: String::new(),
            kind,
        }
    }

    fn float(default: f32, min: f32, max: f32, step: f32) -> OptionKind {
        OptionKind::Float {
            default,
            min,
            max,
            step,
        }
    }

    #[test]
    fn values_round_trip_and_defaults_are_left_out() {
        let options = [
            opt("a", float(0.5, 0.0, 1.0, 0.05)),
            opt("b", OptionKind::Bool { default: true }),
            opt(
                "c",
                OptionKind::Choice {
                    values: vec!["x".into(), "y".into(), "z".into()],
                    default: 0,
                },
            ),
            opt("d", OptionKind::Int { default: 3, min: 1, max: 5 }),
        ];
        let values = [0.75, 0.0, 2.0, 3.0];
        let text = values_text(&options, &values);
        assert_eq!(text, "a=0.75\nb=0\nc=2\n");
        assert_eq!(parse_values(&text, &options), values);
        // Missing, junk and out-of-range values.
        let parsed = parse_values("a=7\nb=yes\nc=-3\nd=4.6\nnope\n", &options);
        assert_eq!(parsed, [1.0, 1.0, 0.0, 5.0]);
        assert_eq!(parse_values("a=NaN\n", &options)[0], 0.5);
    }

    #[test]
    fn stepping_wraps_and_stays_on_the_grid() {
        let k = float(0.5, 0.0, 1.0, 0.1);
        let mut v = 0.5;
        for _ in 0..5 {
            v = step_value(&k, v, false);
        }
        assert!((v - 1.0).abs() < 1e-9);
        assert_eq!(step_value(&k, v, false), 0.0);
        assert_eq!(step_value(&k, 0.0, true), 1.0);
        let b = OptionKind::Bool { default: false };
        assert_eq!(step_value(&b, 0.0, false), 1.0);
        assert_eq!(step_value(&b, 1.0, true), 0.0);
        let c = OptionKind::Choice {
            values: vec!["x".into(), "y".into()],
            default: 0,
        };
        assert_eq!(step_value(&c, 1.0, false), 0.0);
        assert_eq!(step_value(&c, 0.0, true), 1.0);
    }

    #[test]
    fn shows_values_by_their_step() {
        assert_eq!(show_value(&float(0.0, 0.0, 128.0, 8.0), 48.0, "On", "Off"), "48");
        assert_eq!(show_value(&float(0.0, 0.0, 2.0, 0.1), 1.25, "On", "Off"), "1.2");
        assert_eq!(show_value(&float(0.0, 0.0, 1.0, 0.05), 0.7, "On", "Off"), "0.70");
        assert_eq!(show_value(&OptionKind::Bool { default: true }, 0.0, "On", "Off"), "Off");
    }

    #[test]
    fn groups_by_prefix() {
        assert_eq!(group_of("shadow_strength"), "shadow");
        assert_eq!(group_of("exposure"), "");
        assert_eq!(group_of("_x"), "");
        assert_eq!(group_of("x_"), "");
        assert_eq!(group_title("shadow", "General"), "Shadow");
        assert_eq!(group_title("", "General"), "General");
    }

    #[test]
    fn page_lists_few_options_flat_and_many_in_groups() {
        let few: Vec<PackOption> = (0..3)
            .map(|i| opt(&format!("sky_{i}"), float(0.5, 0.0, 1.0, 0.1)))
            .collect();
        let p = page("P", &few, &[0.5, 0.6, 0.5], false, &HashSet::new(), &ENGLISH, "On", "Off");
        assert_eq!(p.labels.len(), 3 + 3);
        assert_eq!(p.labels[0], "P: 3 options (1 changed)");
        assert_eq!(p.labels[4], "sky_1: 0.6  (default 0.5)");
        assert_eq!(p.actions[4], Action::Step(1));

        let many: Vec<PackOption> = (0..10)
            .map(|i| {
                let g = if i < 6 { "sky" } else { "fx" };
                opt(&format!("{g}_{i}"), float(0.5, 0.0, 1.0, 0.1))
            })
            .collect();
        let values = vec![0.5; 10];
        let closed = page("P", &many, &values, true, &HashSet::new(), &KOREAN, "켬", "끔");
        assert_eq!(closed.labels[1], KOREAN.lower);
        assert_eq!(closed.labels[3..], ["[+] Sky (6)", "[+] Fx (4)"]);
        let open: HashSet<String> = ["fx".to_owned()].into();
        let p = page("P", &many, &values, false, &open, &ENGLISH, "On", "Off");
        assert_eq!(p.labels[4], "[-] Fx (4)");
        assert_eq!(p.actions[5], Action::Step(6));
        assert_eq!(p.labels.len(), 3 + 2 + 4);
        assert_eq!(p.labels.len(), p.actions.len());
    }

    #[test]
    fn values_file_sits_beside_the_pack() {
        let p = values_path(Path::new("shaderpacks/meridian-0.2.0.hshader"));
        assert_eq!(p, PathBuf::from("shaderpacks/meridian-0.2.0.hshader.txt"));
    }
}
