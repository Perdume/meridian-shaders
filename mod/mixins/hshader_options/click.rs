// A click on the settings page: step an option, open a group, reset.
fn hshader_options_click(game: &mut crate::game::Game<'_>, mod_id: &str, button: usize) {
    if mod_id == crate::game::hshader_options::ID {
        crate::game::hshader_options::click(game, button);
    }
}
