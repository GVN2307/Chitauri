use eframe::egui::{self, Color32, RichText, Rounding, Stroke, Ui, Vec2};
use crate::storage::{ensure_nomedia_sentinel, get_app_storage_dir, inspect_storage};
use crate::ui::{COLOR_CYAN, COLOR_EMERALD, COLOR_SURFACE, COLOR_TEXT_MUTED, card_stroke};

pub fn render_storage_view(ui: &mut Ui) {
    let stats = inspect_storage();
    ui.spacing_mut().item_spacing = Vec2::new(8.0, 10.0);

    // Title & Isolation Banner
    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(12.0))
        .stroke(card_stroke())
        .inner_margin(12.0)
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label(RichText::new("🛡 PRIVATE OFFLINE STORAGE").strong().size(13.0).color(COLOR_CYAN));
            });

            ui.add_space(8.0);

            // Active .nomedia Status Badge
            let badge_bg = if stats.nomedia_present {
                Color32::from_rgb(10, 40, 25)
            } else {
                Color32::from_rgb(50, 20, 20)
            };
            let badge_border = if stats.nomedia_present { COLOR_EMERALD } else { Color32::RED };

            egui::Frame::none()
                .fill(badge_bg)
                .rounding(Rounding::same(8.0))
                .stroke(Stroke::new(1.0_f32, badge_border))
                .inner_margin(10.0)
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        let icon = if stats.nomedia_present { "✔" } else { "⚠" };
                        let label = if stats.nomedia_present {
                            "PRIVACY ACTIVE: Hidden from Other Music Players"
                        } else {
                            "WARNING: Privacy file missing! Tracks may be visible to other players."
                        };
                        ui.label(RichText::new(icon).strong().color(badge_border));
                        ui.label(RichText::new(label).strong().size(11.0).color(Color32::WHITE));
                    });
                });

            ui.add_space(8.0);

            ui.label(
                RichText::new(
                    "Your downloaded audio is stored in a private directory guarded by Android's '.nomedia' sentinel. This keeps your offline tracks hidden from external media scanners (Spotify, VLC, Apple Music), while remaining directly accessible in your device's File Manager."
                ).size(10.5).color(COLOR_TEXT_MUTED)
            );
        });

    ui.add_space(4.0);

    // Storage Details Card
    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(12.0))
        .stroke(card_stroke())
        .inner_margin(12.0)
        .show(ui, |ui| {
            ui.label(RichText::new("DIRECTORY DETAILS").size(10.0).color(COLOR_TEXT_MUTED).strong());
            ui.add_space(6.0);

            ui.horizontal(|ui| {
                ui.label(RichText::new("App Folder:").size(11.0).color(COLOR_TEXT_MUTED));
            });
            ui.label(RichText::new(&stats.folder_path).strong().size(11.0).color(COLOR_CYAN));

            ui.add_space(6.0);
            ui.separator();
            ui.add_space(6.0);

            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(RichText::new("TOTAL TRACKS").size(9.0).color(COLOR_TEXT_MUTED));
                    ui.label(RichText::new(format!("{}", stats.total_tracks)).strong().size(16.0).color(Color32::WHITE));
                });
                ui.add_space(24.0);
                ui.vertical(|ui| {
                    ui.label(RichText::new("PLAYLISTS").size(9.0).color(COLOR_TEXT_MUTED));
                    ui.label(RichText::new(format!("{}", stats.total_playlists)).strong().size(16.0).color(Color32::WHITE));
                });
                ui.add_space(24.0);
                ui.vertical(|ui| {
                    ui.label(RichText::new("DISK USED").size(9.0).color(COLOR_TEXT_MUTED));
                    ui.label(RichText::new(&stats.total_size_formatted).strong().size(16.0).color(COLOR_EMERALD));
                });
            });

            ui.add_space(10.0);

            ui.horizontal(|ui| {
                if ui.button(RichText::new("🔄 Re-verify .nomedia").size(11.0)).clicked() {
                    let dir = get_app_storage_dir();
                    let _ = ensure_nomedia_sentinel(&dir);
                }

                if ui.button(RichText::new("📂 Open in File Manager").strong().size(11.0).color(COLOR_CYAN)).clicked() {
                    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
                    {
                        let dir = get_app_storage_dir();
                        #[cfg(target_os = "windows")]
                        let _ = std::process::Command::new("explorer").arg(&dir).spawn();
                        #[cfg(target_os = "macos")]
                        let _ = std::process::Command::new("open").arg(&dir).spawn();
                        #[cfg(target_os = "linux")]
                        let _ = std::process::Command::new("xdg-open").arg(&dir).spawn();
                    }
                }
            });
        });

    ui.add_space(4.0);

    // Raw Files Inspection
    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(12.0))
        .stroke(card_stroke())
        .inner_margin(12.0)
        .show(ui, |ui| {
            ui.label(RichText::new("PHYSICAL FILES ON DISK").size(10.0).color(COLOR_TEXT_MUTED).strong());
            ui.add_space(6.0);

            egui::ScrollArea::vertical()
                .id_salt("raw_files_scroll")
                .max_height(ui.available_height() - 75.0)
                .show(ui, |ui| {
                    let dir = get_app_storage_dir();
                    if let Ok(entries) = std::fs::read_dir(&dir) {
                        for entry in entries.flatten() {
                            let name = entry.file_name().to_string_lossy().to_string();
                            let is_nomedia = name == ".nomedia";
                            let icon = if is_nomedia { "🛡" } else if name.ends_with(".mp3") { "🎵" } else { "📄" };
                            let color = if is_nomedia { COLOR_EMERALD } else { Color32::WHITE };
                            let display_name = if is_nomedia {
                                ".nomedia (Privacy shield — blocks other music apps)".to_string()
                            } else {
                                name
                            };

                            ui.horizontal(|ui| {
                                ui.label(RichText::new(icon).size(12.0));
                                ui.label(RichText::new(display_name).size(11.0).color(color));
                            });
                        }
                    }
                });
        });
}
