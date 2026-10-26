pub mod search_view;
pub mod library_view;
pub mod player_view;
pub mod storage_view;

use eframe::egui::{Color32, Stroke};

pub const COLOR_BG: Color32 = Color32::from_rgb(11, 15, 23);         // Dark OLED slate
pub const COLOR_SURFACE: Color32 = Color32::from_rgb(22, 30, 46);    // Card surface
pub const COLOR_SURFACE_LIGHT: Color32 = Color32::from_rgb(35, 47, 70);
pub const COLOR_ACCENT: Color32 = Color32::from_rgb(230, 57, 70);    // Crimson red
pub const COLOR_CYAN: Color32 = Color32::from_rgb(0, 242, 254);      // Electric cyan
pub const COLOR_EMERALD: Color32 = Color32::from_rgb(16, 185, 129);  // Verification green
pub const COLOR_TEXT_MUTED: Color32 = Color32::from_rgb(156, 163, 175);

pub fn card_stroke() -> Stroke {
    Stroke::new(1.0_f32, Color32::from_rgb(45, 55, 75))
}
