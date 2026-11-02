// The mod's settings page: the picked pack's options.
fn hshader_options_page(game: &mut crate::game::Game<'_>, mod_id: &str, buttons: &mut Vec<String>) {
    if mod_id == crate::game::hshader_options::ID {
        crate::game::hshader_options::settings(game, buttons);
    }
}
