// Once a frame: build the picked pack with the player's values when it is time.
fn hshader_options_frame(game: &mut crate::game::Game<'_>) {
    crate::game::hshader_options::frame(game);
}
