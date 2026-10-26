use eframe::egui::{self, Color32, RichText, Rounding, Sense, Stroke, Ui, Vec2};
use crate::models::{DownloadItem, DownloadStatus, SearchResult};
use crate::ui::{COLOR_ACCENT, COLOR_CYAN, COLOR_EMERALD, COLOR_SURFACE, COLOR_SURFACE_LIGHT, COLOR_TEXT_MUTED, card_stroke};

#[derive(Debug, Clone)]
pub enum SearchAction {
    Search(String),
    Download(SearchResult),
    PlaySaved(String),
}

pub fn render_search_view(
    ui: &mut Ui,
    query: &mut String,
    results: &[SearchResult],
    downloads: &[DownloadItem],
) -> Option<SearchAction> {
    let mut action: Option<SearchAction> = None;
    ui.spacing_mut().item_spacing = Vec2::new(8.0, 8.0);

    // 1. YOUTUBE BRANDED HEADER
    ui.horizontal(|ui| {
        egui::Frame::none()
            .fill(Color32::from_rgb(255, 0, 0))
            .rounding(Rounding::same(6.0))
            .inner_margin(egui::Margin::symmetric(8.0, 3.0))
            .show(ui, |ui| {
                ui.label(RichText::new("▶ YouTube").strong().size(12.0).color(Color32::WHITE));
            });
        ui.label(RichText::new("Mini Audio • Tap video to grab MP3").size(10.5).color(COLOR_TEXT_MUTED));
    });

    ui.add_space(2.0);

    // 2. STICKY TOP SEARCH HEADER (Miniature YouTube Search)
    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(12.0))
        .stroke(card_stroke())
        .inner_margin(10.0)
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label(RichText::new("🔍").size(16.0));
                
                let text_edit = egui::TextEdit::singleline(query)
                    .hint_text(RichText::new("Search YouTube for songs, podcasts...").color(COLOR_TEXT_MUTED))
                    .desired_width(ui.available_width() - 85.0);
                
                let res = ui.add(text_edit);
                let enter_pressed = res.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));

                if !query.is_empty() && ui.button(RichText::new("✖").size(12.0)).clicked() {
                    query.clear();
                }

                if ui.button(RichText::new("Search").strong().color(Color32::WHITE)).clicked() || enter_pressed {
                    if !query.trim().is_empty() {
                        action = Some(SearchAction::Search(query.trim().to_string()));
                    }
                }
            });
        });

    // 3. YOUTUBE QUICK-FILTER CATEGORY CHIPS
    egui::ScrollArea::horizontal()
        .id_salt("yt_category_chips")
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                let chips = [
                    ("⚡ Trending", "Trending Music"),
                    ("🎧 Lofi Chill", "Lofi Hip Hop Chill"),
                    ("🎹 Synthwave", "Synthwave Retro"),
                    ("🎸 Rock & Pop", "Popular Rock Hits"),
                    ("🎙 Podcasts", "Joe Rogan Podcast Audio"),
                    ("🌌 Ambient", "Deep Ambient Relaxing"),
                ];

                for (label, search_term) in chips {
                    let is_selected = query.eq_ignore_ascii_case(search_term);
                    let btn = egui::Button::new(RichText::new(label).size(11.0))
                        .fill(if is_selected { COLOR_ACCENT } else { COLOR_SURFACE })
                        .rounding(Rounding::same(16.0));
                    if ui.add(btn).clicked() {
                        *query = search_term.to_string();
                        action = Some(SearchAction::Search(search_term.to_string()));
                    }
                }
            });
        });

    ui.add_space(2.0);
    ui.horizontal(|ui| {
        ui.label(RichText::new("YOUTUBE FEED (Tap any video to download MP3)").size(10.5).color(COLOR_CYAN).strong());
    });

    // 4. MINI VIDEO FEED CARDS (Scrollable Feed)
    egui::ScrollArea::vertical()
        .id_salt("search_scroll")
        .max_height(ui.available_height() - if downloads.is_empty() { 60.0 } else { 160.0 })
        .show(ui, |ui| {
            if results.is_empty() {
                ui.add_space(30.0);
                ui.vertical_centered(|ui| {
                    ui.label(RichText::new("▶").size(36.0).color(Color32::from_rgb(255, 0, 0)));
                    ui.label(RichText::new("Loading YouTube Audio Feed...").color(COLOR_TEXT_MUTED));
                    if ui.button(RichText::new("🔄 Load Trending YouTube Music").strong().color(Color32::WHITE)).clicked() {
                        action = Some(SearchAction::Search("Trending Music".to_string()));
                    }
                });
            } else {
                for item in results {
                    if let Some(act) = render_video_card(ui, item, downloads) {
                        action = Some(act);
                    }
                    ui.add_space(6.0);
                }
            }
        });

    // 5. BOTTOM STICKY DOWNLOAD DRAWER
    if !downloads.is_empty() {
        render_download_drawer(ui, downloads);
    }

    action
}

fn render_video_card(
    ui: &mut Ui,
    item: &SearchResult,
    downloads: &[DownloadItem],
) -> Option<SearchAction> {
    let mut card_action: Option<SearchAction> = None;
    let active_dl = downloads.iter().find(|d| d.video_id == item.video_id);

    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(10.0))
        .stroke(card_stroke())
        .inner_margin(10.0)
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                // Miniature video thumbnail mock / duration badge
                let (rect, _response) = ui.allocate_exact_size(Vec2::new(76.0, 54.0), Sense::click());
                ui.painter().rect_filled(rect, Rounding::same(6.0), Color32::from_rgb(18, 24, 38));
                // Red YouTube play icon badge in thumbnail
                ui.painter().rect_filled(
                    egui::Rect::from_center_size(rect.center() - Vec2::new(0.0, 4.0), Vec2::new(26.0, 18.0)),
                    Rounding::same(4.0),
                    Color32::from_rgb(255, 0, 0),
                );
                ui.painter().text(
                    rect.center() - Vec2::new(0.0, 4.0),
                    egui::Align2::CENTER_CENTER,
                    "▶",
                    egui::FontId::proportional(11.0),
                    Color32::WHITE,
                );
                // Duration tag in corner
                let tag_rect = egui::Rect::from_min_size(
                    rect.max - Vec2::new(36.0, 14.0),
                    Vec2::new(36.0, 14.0)
                );
                ui.painter().rect_filled(tag_rect, Rounding::same(3.0), Color32::from_black_alpha(210));
                ui.painter().text(
                    tag_rect.center(),
                    egui::Align2::CENTER_CENTER,
                    &item.duration_text,
                    egui::FontId::proportional(9.0),
                    Color32::WHITE,
                );

                ui.add_space(8.0);

                // Title and channel info
                ui.vertical(|ui| {
                    ui.set_width(ui.available_width() - 95.0);
                    ui.label(RichText::new(&item.title).strong().size(12.5).color(Color32::WHITE));
                    ui.horizontal(|ui| {
                        ui.label(RichText::new(&item.channel_name).size(10.5).color(COLOR_CYAN));
                        ui.label(RichText::new("✓").size(10.0).color(COLOR_ACCENT));
                        ui.label(RichText::new("•").size(9.0).color(COLOR_TEXT_MUTED));
                        ui.label(RichText::new(&item.views_text).size(10.0).color(COLOR_TEXT_MUTED));
                    });
                });

                // ONE-TAP DOWNLOAD INTERCEPTION BUTTON
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if let Some(dl) = active_dl {
                        match &dl.status {
                            DownloadStatus::Queued | DownloadStatus::Resolving => {
                                ui.label(RichText::new("⏳ Resolving").size(10.5).color(COLOR_CYAN));
                            }
                            DownloadStatus::Downloading(p) => {
                                ui.label(RichText::new(format!("⏳ {:.0}%", p * 100.0)).strong().size(11.0).color(COLOR_CYAN));
                            }
                            DownloadStatus::Tagging => {
                                ui.label(RichText::new("🏷 Tagging").size(10.5).color(COLOR_EMERALD));
                            }
                            DownloadStatus::SavedToAppFolder => {
                                ui.horizontal(|ui| {
                                    ui.label(RichText::new("✔ Saved").strong().size(10.5).color(COLOR_EMERALD));
                                    let play_btn = egui::Button::new(RichText::new("▶ Play").strong().size(10.5).color(Color32::WHITE))
                                        .fill(COLOR_EMERALD)
                                        .rounding(Rounding::same(6.0));
                                    if ui.add(play_btn).clicked() {
                                        card_action = Some(SearchAction::PlaySaved(item.title.clone()));
                                    }
                                });
                            }
                            DownloadStatus::Failed(_) => {
                                if ui.button(RichText::new("Retry").size(10.0).color(COLOR_ACCENT)).clicked() {
                                    card_action = Some(SearchAction::Download(item.clone()));
                                }
                            }
                        }
                    } else {
                        let btn = egui::Button::new(RichText::new("⬇ Grab MP3").strong().size(10.5).color(Color32::WHITE))
                            .fill(Color32::from_rgb(220, 38, 38))
                            .rounding(Rounding::same(6.0));
                        if ui.add(btn).clicked() {
                            card_action = Some(SearchAction::Download(item.clone()));
                        }
                    }
                });
            });
        });

    card_action
}

fn render_download_drawer(ui: &mut Ui, downloads: &[DownloadItem]) {
    egui::Frame::none()
        .fill(Color32::from_rgb(14, 20, 32))
        .rounding(Rounding::same(12.0))
        .stroke(Stroke::new(1.0_f32, COLOR_CYAN))
        .inner_margin(12.0)
        .show(ui, |ui| {
            let active_count = downloads.iter().filter(|d| !matches!(d.status, DownloadStatus::SavedToAppFolder | DownloadStatus::Failed(_))).count();
            let saved_count = downloads.iter().filter(|d| matches!(d.status, DownloadStatus::SavedToAppFolder)).count();

            ui.horizontal(|ui| {
                ui.label(RichText::new(format!("⚡ ACTIVE QUEUE ({} Running, {} Saved)", active_count, saved_count)).strong().size(11.0).color(COLOR_CYAN));
            });

            ui.add_space(4.0);

            for dl in downloads.iter().rev().take(2) {
                ui.horizontal(|ui| {
                    ui.label(RichText::new("🎵").size(12.0));
                    let short_title: String = dl.title.chars().take(26).collect();
                    ui.label(RichText::new(short_title).size(12.0).color(Color32::WHITE));
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.label(RichText::new(format!("{} kbps", dl.bitrate_kbps)).size(10.0).color(COLOR_TEXT_MUTED));
                        ui.label(RichText::new(format!("{:.0}%", dl.progress * 100.0)).strong().size(11.0).color(COLOR_CYAN));
                    });
                });

                // Custom sleek progress bar
                let (rect, _response) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 6.0), Sense::hover());
                ui.painter().rect_filled(rect, Rounding::same(3.0), COLOR_SURFACE_LIGHT);
                let fill_width = (rect.width() * dl.progress.clamp(0.0, 1.0)).max(2.0);
                let filled_rect = egui::Rect::from_min_size(rect.min, Vec2::new(fill_width, rect.height()));
                ui.painter().rect_filled(filled_rect, Rounding::same(3.0), COLOR_CYAN);
                ui.add_space(2.0);
            }
        });
}
