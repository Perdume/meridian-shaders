// The mod's row in Options > Mods.
fn hshader_options_listed(mods: &mut Vec<crate::game::native_hooks::NativeMod>) {
    crate::game::hshader_options::listed(mods);
}
