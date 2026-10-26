use eframe::egui::{self, Color32, RichText, Rounding, Sense, Ui, Vec2};
use crate::models::{Playlist, Track};
use crate::ui::{COLOR_ACCENT, COLOR_CYAN, COLOR_EMERALD, COLOR_SURFACE, COLOR_SURFACE_LIGHT, COLOR_TEXT_MUTED, card_stroke};

#[derive(Debug, Clone)]
pub enum LibraryAction {
    PlayTrack(usize),
    PlayPlaylist(Playlist),
    CreatePlaylist(String),
    DeleteTrack(String),
    DeletePlaylist(String),
}

pub fn render_library_view(
    ui: &mut Ui,
    tracks: &[Track],
    playlists: &[Playlist],
    active_playlist_id: &mut Option<String>,
    new_playlist_name: &mut String,
) -> Option<LibraryAction> {
    let mut action: Option<LibraryAction> = None;
    ui.spacing_mut().item_spacing = Vec2::new(8.0, 10.0);

    // Header & Playlist Creation Bar
    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(12.0))
        .stroke(card_stroke())
        .inner_margin(12.0)
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label(RichText::new("📁 OFFLINE LIBRARY").strong().size(13.0).color(COLOR_CYAN));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(RichText::new(format!("{} Tracks", tracks.len())).size(11.0).color(COLOR_TEXT_MUTED));
                });
            });

            ui.add_space(8.0);

            // New Playlist Creator
            ui.horizontal(|ui| {
                ui.add(
                    egui::TextEdit::singleline(new_playlist_name)
                        .hint_text(RichText::new("New Playlist Name...").color(COLOR_TEXT_MUTED))
                        .desired_width(ui.available_width() - 85.0)
                );
                if ui.button(RichText::new("+ Create").strong().color(Color32::WHITE)).clicked() {
                    let name = new_playlist_name.trim();
                    if !name.is_empty() {
                        action = Some(LibraryAction::CreatePlaylist(name.to_string()));
                        new_playlist_name.clear();
                    }
                }
            });
        });

    ui.add_space(4.0);

    // Playlists Horizontal Pill Scroller
    ui.horizontal(|ui| {
        ui.label(RichText::new("PLAYLISTS:").size(10.0).color(COLOR_TEXT_MUTED).strong());
    });

    egui::ScrollArea::horizontal()
        .id_salt("playlists_hscroll")
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                let all_selected = active_playlist_id.is_none();
                let all_btn = egui::Button::new(RichText::new("All Songs").size(11.0))
                    .fill(if all_selected { COLOR_ACCENT } else { COLOR_SURFACE })
                    .rounding(Rounding::same(20.0));
                if ui.add(all_btn).clicked() {
                    *active_playlist_id = None;
                }

                for pl in playlists {
                    let is_active = active_playlist_id.as_deref() == Some(&pl.id);
                    let label = format!("{} ({})", pl.name, pl.track_ids.len());
                    let btn = egui::Button::new(RichText::new(label).size(11.0))
                        .fill(if is_active { COLOR_CYAN } else { COLOR_SURFACE })
                        .rounding(Rounding::same(20.0));
                    if ui.add(btn).clicked() {
                        *active_playlist_id = Some(pl.id.clone());
                    }
                }
            });
        });

    ui.add_space(4.0);

    // Action row for active playlist
    if let Some(ref pl_id) = active_playlist_id {
        if let Some(pl) = playlists.iter().find(|p| &p.id == pl_id) {
            ui.horizontal(|ui| {
                ui.label(RichText::new(&pl.name).strong().size(13.0).color(Color32::WHITE));
                if ui.button(RichText::new("▶ Play All").size(11.0).color(COLOR_EMERALD)).clicked() {
                    action = Some(LibraryAction::PlayPlaylist(pl.clone()));
                }
                if pl.id != "favorites" {
                    if ui.button(RichText::new("🗑 Delete").size(10.0).color(COLOR_ACCENT)).clicked() {
                        action = Some(LibraryAction::DeletePlaylist(pl.id.clone()));
                        *active_playlist_id = None;
                    }
                }
            });
        }
    }

    // Tracks List
    let visible_tracks: Vec<(usize, &Track)> = if let Some(ref pl_id) = active_playlist_id {
        if let Some(pl) = playlists.iter().find(|p| &p.id == pl_id) {
            tracks.iter().enumerate().filter(|(_, t)| pl.track_ids.contains(&t.id)).collect()
        } else {
            tracks.iter().enumerate().collect()
        }
    } else {
        tracks.iter().enumerate().collect()
    };

    egui::ScrollArea::vertical()
        .id_salt("library_tracks_scroll")
        .max_height(ui.available_height() - 75.0)
        .show(ui, |ui| {
            if visible_tracks.is_empty() {
                ui.add_space(40.0);
                ui.vertical_centered(|ui| {
                    ui.label(RichText::new("📁").size(36.0));
                    ui.label(RichText::new("No downloaded MP3 files yet.").color(COLOR_TEXT_MUTED));
                    ui.label(RichText::new("Use the Mini Search tab to grab songs into your local folder.").size(11.0).color(COLOR_CYAN));
                });
            } else {
                for (orig_idx, track) in visible_tracks {
                    if let Some(act) = render_library_track_row(ui, track, orig_idx) {
                        action = Some(act);
                    }
                    ui.add_space(6.0);
                }
            }
        });

    action
}

fn render_library_track_row(
    ui: &mut Ui,
    track: &Track,
    idx: usize,
) -> Option<LibraryAction> {
    let mut row_action: Option<LibraryAction> = None;

    let frame = egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(10.0))
        .stroke(card_stroke())
        .inner_margin(10.0);

    let frame_res = frame.show(ui, |ui| {
        ui.horizontal(|ui| {
            // Vinyl / disc icon
            let (rect, _) = ui.allocate_exact_size(Vec2::new(40.0, 40.0), Sense::hover());
            ui.painter().circle_filled(rect.center(), 18.0, COLOR_SURFACE_LIGHT);
            ui.painter().circle_filled(rect.center(), 6.0, COLOR_CYAN);

            ui.add_space(8.0);

            // Track title & artist
            ui.vertical(|ui| {
                ui.set_width((ui.available_width() - 120.0).max(60.0));
                ui.label(RichText::new(&track.title).strong().size(12.5).color(Color32::WHITE));
                ui.horizontal(|ui| {
                    ui.label(RichText::new(&track.artist).size(10.5).color(COLOR_TEXT_MUTED));
                    ui.label(RichText::new("•").size(9.0).color(COLOR_TEXT_MUTED));
                    ui.label(RichText::new(&track.duration_formatted).size(10.5).color(COLOR_TEXT_MUTED));
                });
            });

            // Play & Delete actions
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let del_btn = egui::Button::new(RichText::new("🗑").size(12.0).color(COLOR_ACCENT))
                    .min_size(Vec2::new(32.0, 36.0));
                if ui.add(del_btn).clicked() {
                    row_action = Some(LibraryAction::DeleteTrack(track.id.clone()));
                }

                ui.add_space(4.0);

                let play_btn = egui::Button::new(RichText::new("▶ PLAY").strong().size(11.5).color(Color32::WHITE))
                    .fill(COLOR_EMERALD)
                    .rounding(Rounding::same(6.0))
                    .min_size(Vec2::new(65.0, 36.0));
                if ui.add(play_btn).clicked() {
                    row_action = Some(LibraryAction::PlayTrack(idx));
                }
            });
        });
    });

    // Make tapping anywhere on the entire row card play the track
    let card_interact = ui.interact(frame_res.response.rect, ui.id().with(("lib_card", idx)), Sense::click());
    if row_action.is_none() && card_interact.clicked() {
        row_action = Some(LibraryAction::PlayTrack(idx));
    }

    row_action
}
