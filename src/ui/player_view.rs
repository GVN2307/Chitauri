use std::sync::{Arc, Mutex};
use eframe::egui::{self, Align2, Color32, FontId, Rect, RichText, Rounding, Sense, Stroke, Ui, Vec2};
use crate::models::RepeatMode;
use crate::player::AudioPlayer;
use crate::ui::{
    COLOR_ACCENT, COLOR_CYAN, COLOR_EMERALD, COLOR_SURFACE, COLOR_SURFACE_LIGHT, COLOR_TEXT_MUTED,
};

pub fn render_mini_player(
    ui: &mut Ui,
    player: &Arc<Mutex<AudioPlayer>>,
    is_expanded: &mut bool,
) {
    let mut p = player.lock().unwrap();
    if p.playback_queue.is_empty() {
        return;
    }

    let current = p.current_track().cloned();
    let is_playing = p.is_playing;
    let elapsed = p.elapsed_seconds;
    let duration = current.as_ref().map(|c| c.duration_secs as f32).unwrap_or(210.0);
    let progress = (elapsed / duration).clamp(0.0, 1.0);

    egui::Frame::none()
        .fill(Color32::from_rgb(18, 24, 38))
        .rounding(Rounding::same(12.0))
        .stroke(Stroke::new(1.0_f32, Color32::from_rgb(40, 50, 75)))
        .inner_margin(8.0)
        .show(ui, |ui| {
            // Micro progress line at the top
            let (p_rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 3.0), Sense::hover());
            ui.painter().rect_filled(p_rect, Rounding::same(1.0), COLOR_SURFACE_LIGHT);
            let fill_width = (p_rect.width() * progress).max(2.0);
            ui.painter().rect_filled(
                Rect::from_min_size(p_rect.min, Vec2::new(fill_width, 3.0)),
                Rounding::same(1.0),
                COLOR_CYAN,
            );

            ui.add_space(4.0);

            ui.horizontal(|ui| {
                // Miniature Rolling Vinyl Disc & Tonearm
                let (rect, res) = ui.allocate_exact_size(Vec2::new(38.0, 38.0), Sense::click());
                let center = rect.center();
                let painter = ui.painter();

                // Platter
                painter.circle_filled(center, 18.0, Color32::from_rgb(14, 16, 22));
                painter.circle_stroke(center, 18.0, Stroke::new(1.2_f32, Color32::from_rgb(50, 65, 95)));
                // Grooves
                painter.circle_stroke(center, 14.0, Stroke::new(0.6_f32, Color32::from_rgb(30, 40, 60)));
                painter.circle_stroke(center, 10.0, Stroke::new(0.6_f32, Color32::from_rgb(30, 40, 60)));

                // Rotating specular highlights if playing
                if is_playing {
                    let rot = elapsed * 3.6;
                    for i in 0..2 {
                        let a = rot + (i as f32) * std::f32::consts::PI;
                        let dir = Vec2::new(a.cos(), a.sin());
                        painter.line_segment(
                            [center + dir * 6.0, center + dir * 16.0],
                            Stroke::new(1.2_f32, Color32::from_rgba_unmultiplied(0, 242, 254, 140)),
                        );
                    }
                }

                // Center crimson label
                painter.circle_filled(center, 5.5, COLOR_ACCENT);
                painter.circle_filled(center, 2.0, Color32::WHITE);

                // Miniature Tonearm
                let pivot = center + Vec2::new(13.0, -13.0);
                painter.circle_filled(pivot, 2.2, Color32::from_rgb(180, 195, 220));
                if is_playing {
                    let needle = center + Vec2::new(6.0, 4.0);
                    painter.line_segment([pivot, pivot + Vec2::new(3.0, 8.0)], Stroke::new(1.5_f32, Color32::from_rgb(160, 175, 200)));
                    painter.line_segment([pivot + Vec2::new(3.0, 8.0), needle], Stroke::new(1.2_f32, Color32::WHITE));
                    painter.circle_filled(needle, 1.2, COLOR_CYAN);
                } else {
                    let rest = center + Vec2::new(16.0, 6.0);
                    painter.line_segment([pivot, rest], Stroke::new(1.4_f32, Color32::from_rgb(140, 155, 180)));
                }

                if res.clicked() {
                    *is_expanded = true;
                }

                ui.add_space(6.0);

                // Title and artist (tap to expand)
                let (info_rect, info_res) = ui.allocate_exact_size(Vec2::new(ui.available_width() - 110.0, 36.0), Sense::click());
                let title = current.as_ref().map(|c| c.title.as_str()).unwrap_or("No Track");
                let artist = current.as_ref().map(|c| c.artist.as_str()).unwrap_or("Unknown");

                ui.allocate_new_ui(egui::UiBuilder::new().max_rect(info_rect), |ui| {
                    ui.vertical(|ui| {
                        let short_title: String = title.chars().take(22).collect();
                        ui.label(RichText::new(short_title).strong().size(11.5).color(Color32::WHITE));
                        ui.label(RichText::new(artist).size(9.5).color(COLOR_TEXT_MUTED));
                    });
                });

                if info_res.clicked() {
                    *is_expanded = true;
                }

                // Controls
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let expand_btn = egui::Button::new(RichText::new("⛶").size(12.0).color(COLOR_CYAN))
                        .fill(COLOR_SURFACE_LIGHT)
                        .rounding(Rounding::same(6.0))
                        .min_size(Vec2::new(26.0, 30.0));
                    if ui.add(expand_btn).clicked() {
                        *is_expanded = true;
                    }

                    if ui.button(RichText::new("⏭").size(13.0).color(Color32::WHITE)).clicked() {
                        p.next();
                    }

                    let play_icon = if is_playing { "⏸" } else { "▶" };
                    let play_btn = egui::Button::new(RichText::new(play_icon).strong().size(13.0).color(Color32::WHITE))
                        .fill(COLOR_ACCENT)
                        .rounding(Rounding::same(16.0))
                        .min_size(Vec2::new(32.0, 32.0));
                    if ui.add(play_btn).clicked() {
                        p.toggle_play_pause();
                    }
                });
            });
        });
}

pub fn render_full_player(
    ui: &mut Ui,
    player: &Arc<Mutex<AudioPlayer>>,
    is_expanded: &mut bool,
) {
    let mut p = player.lock().unwrap();
    let current = p.current_track().cloned();
    let is_playing = p.is_playing;
    let is_shuffled = p.is_shuffled;
    let repeat_mode = p.repeat_mode;
    let elapsed = p.elapsed_seconds;
    let duration = current.as_ref().map(|c| c.duration_secs as f32).unwrap_or(228.0);
    let mut progress = (elapsed / duration).clamp(0.0, 1.0);

    ui.spacing_mut().item_spacing = Vec2::new(8.0, 10.0);

    // 1. Top Header Bar
    ui.horizontal(|ui| {
        let min_btn = egui::Button::new(RichText::new("▼ Minimize").size(11.5).color(COLOR_TEXT_MUTED))
            .fill(COLOR_SURFACE)
            .rounding(Rounding::same(6.0));
        if ui.add(min_btn).clicked() {
            *is_expanded = false;
        }
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.label(RichText::new("NOW PLAYING").strong().size(10.0).color(COLOR_CYAN));
        });
    });

    ui.add_space(4.0);

    // 2. Rolling Gramophone / Turntable Platter Deck
    let deck_height = 230.0;
    let (deck_rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), deck_height), Sense::hover());
    let painter = ui.painter();

    // Turntable Deck Surface
    let deck_panel = deck_rect.shrink2(Vec2::new(8.0, 0.0));
    painter.rect_filled(deck_panel, Rounding::same(16.0), Color32::from_rgb(14, 18, 28));
    painter.rect_stroke(deck_panel, Rounding::same(16.0), Stroke::new(1.0_f32, Color32::from_rgb(35, 45, 68)));

    // Turntable Platter (Center)
    let disc_center = deck_panel.center() - Vec2::new(18.0, 0.0);

    // Outer Platter Rim
    painter.circle_filled(disc_center, 94.0, Color32::from_rgb(20, 26, 38));
    painter.circle_stroke(disc_center, 94.0, Stroke::new(2.0_f32, Color32::from_rgb(45, 60, 90)));

    // Deep Obsidian Vinyl Record
    painter.circle_filled(disc_center, 90.0, Color32::from_rgb(10, 10, 12));

    // Concentric Sound Grooves
    for r in [85.0_f32, 78.0_f32, 71.0_f32, 64.0_f32, 57.0_f32, 50.0_f32, 43.0_f32] {
        painter.circle_stroke(disc_center, r, Stroke::new(0.7_f32, Color32::from_rgb(28, 32, 44)));
    }

    // Dynamic Rolling Physics & Specular Groove Highlights
    if is_playing {
        let rot_angle = elapsed * 3.8;
        for i in 0..4 {
            let a = rot_angle + (i as f32) * std::f32::consts::FRAC_PI_2;
            let dir = Vec2::new(a.cos(), a.sin());
            let p1 = disc_center + dir * 32.0;
            let p2 = disc_center + dir * 86.0;
            painter.line_segment(
                [p1, p2],
                Stroke::new(1.6_f32, Color32::from_rgba_unmultiplied(100, 200, 255, 95)),
            );
        }
        for j in 0..6 {
            let a2 = rot_angle * 1.5 + (j as f32) * (std::f32::consts::PI / 3.0);
            let p_dot = disc_center + Vec2::new(a2.cos(), a2.sin()) * 84.0;
            painter.circle_filled(p_dot, 1.2, Color32::from_rgb(0, 242, 254));
        }
    }

    // Center Vinyl Label (Crimson & Cyan)
    painter.circle_filled(disc_center, 28.0, COLOR_ACCENT);
    painter.circle_stroke(disc_center, 26.0, Stroke::new(1.0_f32, Color32::WHITE));
    painter.text(
        disc_center - Vec2::new(0.0, 5.0),
        Align2::CENTER_CENTER,
        "CHITAURI",
        FontId::proportional(8.0),
        Color32::WHITE,
    );
    painter.text(
        disc_center + Vec2::new(0.0, 6.0),
        Align2::CENTER_CENTER,
        "STEREO",
        FontId::proportional(7.0),
        Color32::from_rgb(255, 220, 220),
    );

    // Spindle Hole
    painter.circle_filled(disc_center, 4.5, Color32::from_rgb(210, 220, 235));
    painter.circle_filled(disc_center, 2.0, Color32::BLACK);

    // Articulated Metallic Tonearm & Stylus Needle
    let pivot = disc_center + Vec2::new(94.0, -74.0);
    painter.circle_filled(pivot, 8.5, Color32::from_rgb(30, 40, 60));
    painter.circle_stroke(pivot, 8.5, Stroke::new(2.0_f32, Color32::from_rgb(180, 195, 225)));
    painter.circle_filled(pivot, 3.5, Color32::WHITE);

    if is_playing {
        // Needle actively tracking across the record grooves from outer (r=80) to inner (r=36)
        let track_r = 80.0 - progress * (80.0 - 36.0);
        let needle_pos = disc_center + Vec2::new(track_r * 0.74, track_r * 0.67);
        let elbow = pivot + Vec2::new(15.0, 42.0);

        painter.line_segment([pivot, elbow], Stroke::new(3.5_f32, Color32::from_rgb(170, 185, 210)));
        painter.line_segment([elbow, needle_pos], Stroke::new(2.8_f32, Color32::from_rgb(220, 230, 250)));

        // Pickup Headshell
        painter.rect_filled(Rect::from_center_size(needle_pos, Vec2::new(13.0, 8.5)), Rounding::same(2.0), Color32::from_rgb(45, 55, 75));
        painter.rect_stroke(Rect::from_center_size(needle_pos, Vec2::new(13.0, 8.5)), Rounding::same(2.0), Stroke::new(1.2_f32, COLOR_CYAN));

        // Stylus Needle contact glow
        painter.circle_filled(needle_pos, 1.8, Color32::WHITE);
        painter.circle_stroke(needle_pos, 4.0, Stroke::new(1.0_f32, COLOR_CYAN));
    } else {
        // Tonearm resting safely in cradle off the record
        let rest_cradle = disc_center + Vec2::new(104.0, 16.0);
        let elbow = pivot + Vec2::new(10.0, 46.0);
        painter.line_segment([pivot, elbow], Stroke::new(3.5_f32, Color32::from_rgb(140, 155, 180)));
        painter.line_segment([elbow, rest_cradle], Stroke::new(2.8_f32, Color32::from_rgb(180, 195, 220)));
        painter.rect_filled(Rect::from_center_size(rest_cradle, Vec2::new(8.0, 14.0)), Rounding::same(2.0), Color32::from_rgb(60, 75, 100));
    }

    ui.add_space(8.0);

    // 3. Track Title & Artist (Clean Modern Typography)
    let title = current.as_ref().map(|c| c.title.as_str()).unwrap_or("No Track Selected");
    let artist = current.as_ref().map(|c| c.artist.as_str()).unwrap_or("Chitauri Audio");
    ui.vertical_centered(|ui| {
        ui.label(RichText::new(title).strong().size(15.0).color(Color32::WHITE));
        ui.add_space(2.0);
        ui.horizontal(|ui| {
            ui.add_space((ui.available_width() - 180.0).max(0.0) / 2.0);
            ui.label(RichText::new(artist).size(11.5).color(COLOR_TEXT_MUTED));
            ui.label(RichText::new("•").size(9.0).color(COLOR_TEXT_MUTED));
            ui.label(RichText::new("192 kbps MP3").size(10.0).color(COLOR_CYAN));
        });
    });

    ui.add_space(6.0);

    // 4. Interactive Time Scrubber
    let elapsed_mins = (elapsed as u32) / 60;
    let elapsed_secs = (elapsed as u32) % 60;
    let total_mins = (duration as u32) / 60;
    let total_secs = (duration as u32) % 60;

    ui.horizontal(|ui| {
        ui.label(RichText::new(format!("{:02}:{:02}", elapsed_mins, elapsed_secs)).size(10.5).color(COLOR_TEXT_MUTED));
        let slider = egui::Slider::new(&mut progress, 0.0..=1.0)
            .show_value(false)
            .trailing_fill(true);
        if ui.add_sized(Vec2::new(ui.available_width() - 44.0, 16.0), slider).changed() {
            p.elapsed_seconds = progress * duration;
        }
        ui.label(RichText::new(format!("{:02}:{:02}", total_mins, total_secs)).size(10.5).color(COLOR_TEXT_MUTED));
    });

    ui.add_space(6.0);

    // 5. Primary Control Console (Shuffle, Prev, Play/Pause, Next, Repeat)
    ui.horizontal(|ui| {
        ui.set_width(ui.available_width());
        let center_offset = (ui.available_width() - 250.0).max(0.0) / 2.0;
        ui.add_space(center_offset);

        // SHUFFLE TOGGLE
        let shuffle_color = if is_shuffled { COLOR_CYAN } else { COLOR_TEXT_MUTED };
        let shuffle_btn = egui::Button::new(RichText::new("🔀").size(15.0).color(shuffle_color))
            .fill(COLOR_SURFACE)
            .rounding(Rounding::same(18.0));
        if ui.add_sized(Vec2::new(36.0, 36.0), shuffle_btn).clicked() {
            p.toggle_shuffle();
        }

        ui.add_space(8.0);

        // PREVIOUS
        let prev_btn = egui::Button::new(RichText::new("⏮").size(16.0).color(Color32::WHITE))
            .fill(COLOR_SURFACE)
            .rounding(Rounding::same(18.0));
        if ui.add_sized(Vec2::new(36.0, 36.0), prev_btn).clicked() {
            p.previous();
        }

        ui.add_space(8.0);

        // PLAY / PAUSE (Large central button)
        let play_icon = if is_playing { "⏸" } else { "▶" };
        let play_btn = egui::Button::new(RichText::new(play_icon).strong().size(22.0).color(Color32::WHITE))
            .fill(COLOR_ACCENT)
            .rounding(Rounding::same(26.0));
        if ui.add_sized(Vec2::new(52.0, 52.0), play_btn).clicked() {
            p.toggle_play_pause();
        }

        ui.add_space(8.0);

        // NEXT
        let next_btn = egui::Button::new(RichText::new("⏭").size(16.0).color(Color32::WHITE))
            .fill(COLOR_SURFACE)
            .rounding(Rounding::same(18.0));
        if ui.add_sized(Vec2::new(36.0, 36.0), next_btn).clicked() {
            p.next();
        }

        ui.add_space(8.0);

        // REPEAT TOGGLE (Off -> All -> One)
        let (repeat_icon, repeat_color) = match repeat_mode {
            RepeatMode::Off => ("🔁", COLOR_TEXT_MUTED),
            RepeatMode::All => ("🔁", COLOR_CYAN),
            RepeatMode::One => ("🔂", COLOR_EMERALD),
        };
        let repeat_btn = egui::Button::new(RichText::new(repeat_icon).size(15.0).color(repeat_color))
            .fill(COLOR_SURFACE)
            .rounding(Rounding::same(18.0));
        if ui.add_sized(Vec2::new(36.0, 36.0), repeat_btn).clicked() {
            p.cycle_repeat_mode();
        }
    });

    ui.add_space(6.0);

    // 6. Volume Slider
    ui.horizontal(|ui| {
        ui.label(RichText::new("🔊").size(12.0));
        let mut vol = p.volume;
        if ui.add(egui::Slider::new(&mut vol, 0.0..=1.0).show_value(false)).changed() {
            p.set_volume(vol);
        }
    });

    ui.add_space(4.0);

    // 7. Up Next Queue
    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(12.0))
        .inner_margin(10.0)
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label(RichText::new("UP NEXT").strong().size(10.0).color(COLOR_CYAN));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let mode_str = match repeat_mode {
                        RepeatMode::Off => "Repeat: Off",
                        RepeatMode::All => "Repeat: All",
                        RepeatMode::One => "Repeat: One",
                    };
                    ui.label(RichText::new(mode_str).size(9.0).color(COLOR_TEXT_MUTED));
                });
            });

            ui.add_space(4.0);

            let queue_len = p.playback_queue.len();
            let cur_idx = p.current_index;

            egui::ScrollArea::vertical()
                .id_salt("full_player_queue_scroll")
                .max_height(110.0)
                .show(ui, |ui| {
                    for i in 0..queue_len {
                        let track = &p.playback_queue[i];
                        let is_active = i == cur_idx;
                        let text_color = if is_active { COLOR_CYAN } else { Color32::WHITE };
                        let prefix = if is_active { "▶ " } else { "   " };

                        ui.horizontal(|ui| {
                            let title_short: String = track.title.chars().take(28).collect();
                            ui.label(RichText::new(format!("{}{}", prefix, title_short)).size(11.0).color(text_color));
                            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                                ui.label(RichText::new(&track.duration_formatted).size(10.0).color(COLOR_TEXT_MUTED));
                            });
                        });
                    }
                });
        });
}
