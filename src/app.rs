use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use eframe::egui::{self, Color32, RichText, Rounding, Stroke};
use crate::downloader::Downloader;
use crate::innertube::InnerTubeClient;
use crate::models::{AppEvent, DownloadItem, DownloadStatus, Playlist, SearchResult, Tab, Track};
use crate::player::AudioPlayer;
use crate::storage::{delete_track, ensure_nomedia_sentinel, get_app_storage_dir, load_all_playlists, load_all_tracks, save_playlists};
use crate::ui::library_view::{render_library_view, LibraryAction};
use crate::ui::player_view::{render_full_player, render_mini_player};
use crate::ui::search_view::{render_search_view, SearchAction};
use crate::ui::storage_view::render_storage_view;
use crate::ui::{COLOR_ACCENT, COLOR_BG, COLOR_CYAN, COLOR_EMERALD, COLOR_SURFACE, COLOR_TEXT_MUTED};

pub struct ChitauriApp {
    active_tab: Tab,
    search_query: String,
    search_results: Vec<SearchResult>,
    downloads: Vec<DownloadItem>,
    tracks: Vec<Track>,
    playlists: Vec<Playlist>,
    active_playlist_id: Option<String>,
    new_playlist_name: String,
    player: Arc<Mutex<AudioPlayer>>,
    is_player_expanded: bool,
    event_tx: Sender<AppEvent>,
    event_rx: Receiver<AppEvent>,
    tokio_handle: tokio::runtime::Handle,
}

impl ChitauriApp {
    pub fn new(cc: &eframe::CreationContext<'_>, tokio_handle: tokio::runtime::Handle) -> Self {
        // Initialize high DPI and custom dark visuals
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = COLOR_BG;
        visuals.window_fill = COLOR_BG;
        cc.egui_ctx.set_visuals(visuals);

        // Ensure storage directory and .nomedia file
        let storage_dir = get_app_storage_dir();
        let _ = ensure_nomedia_sentinel(&storage_dir);

        let (event_tx, event_rx) = channel();
        let tracks = load_all_tracks();
        let playlists = load_all_playlists();
        let player = AudioPlayer::new();

        let initial_results = InnerTubeClient::new().get_fallback_results("Trending Music");

        // Spawn async background task to fetch live YouTube results on startup
        let bg_tx = event_tx.clone();
        tokio_handle.spawn(async move {
            let client = InnerTubeClient::new();
            if let Ok(res) = client.search("Trending Music").await {
                let _ = bg_tx.send(AppEvent::SearchCompleted(Ok(res)));
            }
        });

        Self {
            active_tab: Tab::Explore,
            search_query: "Trending Music".to_string(),
            search_results: initial_results,
            downloads: Vec::new(),
            tracks,
            playlists,
            active_playlist_id: None,
            new_playlist_name: String::new(),
            player,
            is_player_expanded: false,
            event_tx,
            event_rx,
            tokio_handle,
        }
    }

    fn handle_events(&mut self) {
        while let Ok(event) = self.event_rx.try_recv() {
            match event {
                AppEvent::SearchCompleted(res) => {
                    if let Ok(results) = res {
                        self.search_results = results;
                    }
                }
                AppEvent::DownloadProgress { video_id, progress, speed_kbps, status } => {
                    if let Some(item) = self.downloads.iter_mut().find(|d| d.video_id == video_id) {
                        item.progress = progress;
                        item.speed_kbps = speed_kbps;
                        item.status = status;
                    }
                }
                AppEvent::DownloadCompleted { track } => {
                    if let Some(item) = self.downloads.iter_mut().find(|d| d.video_id == track.id) {
                        item.status = DownloadStatus::SavedToAppFolder;
                        item.progress = 1.0;
                    }
                    self.tracks = load_all_tracks();
                }
                AppEvent::DownloadFailed { video_id, error } => {
                    if let Some(item) = self.downloads.iter_mut().find(|d| d.video_id == video_id) {
                        item.status = DownloadStatus::Failed(error);
                    }
                }
                AppEvent::ReloadTracks => {
                    self.tracks = load_all_tracks();
                }
            }
        }
    }
}

impl eframe::App for ChitauriApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.handle_events();
        
        let dt = ctx.input(|i| i.stable_dt);
        {
            let mut p = self.player.lock().unwrap();
            p.tick(dt);
        }

        // Request continuous repaint if playing or active downloads
        let is_busy = {
            let p = self.player.lock().unwrap();
            p.is_playing || self.downloads.iter().any(|d| !matches!(d.status, DownloadStatus::SavedToAppFolder | DownloadStatus::Failed(_)))
        };
        if is_busy {
            ctx.request_repaint();
        }

        if !self.is_player_expanded {
            egui::TopBottomPanel::bottom("bottom_dock")
                .frame(egui::Frame::none().fill(COLOR_BG).inner_margin(egui::Margin::symmetric(10.0, 8.0)))
                .show(ctx, |ui| {
                    render_mini_player(ui, &self.player, &mut self.is_player_expanded);
                    ui.add_space(4.0);
                    render_bottom_nav_bar(ui, &mut self.active_tab);
                });
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            // MOBILE SHELL CONTAINER
            ui.vertical(|ui| {
                // Safe area spacing below system status bar
                ui.add_space(24.0);

                if self.is_player_expanded {
                    // FULL SCREEN PLAYER DRAWER
                    render_full_player(ui, &self.player, &mut self.is_player_expanded);
                } else {
                    // MAIN CONTENT AREA
                    match self.active_tab {
                        Tab::Explore => {
                            let maybe_action = render_search_view(
                                ui,
                                &mut self.search_query,
                                &self.search_results,
                                &self.downloads,
                            );

                            if let Some(action) = maybe_action {
                                match action {
                                    SearchAction::Search(q) => {
                                        let tx = self.event_tx.clone();
                                        self.tokio_handle.spawn(async move {
                                            let client = InnerTubeClient::new();
                                            let res = client.search(&q).await.map_err(|e| e.to_string());
                                            let _ = tx.send(AppEvent::SearchCompleted(res));
                                        });
                                    }
                                    SearchAction::Download(item) => {
                                        self.downloads.push(DownloadItem {
                                            video_id: item.video_id.clone(),
                                            title: item.title.clone(),
                                            channel: item.channel_name.clone(),
                                            progress: 0.0,
                                            status: DownloadStatus::Queued,
                                            speed_kbps: 0.0,
                                            bitrate_kbps: 192,
                                        });

                                        let tx = self.event_tx.clone();
                                        self.tokio_handle.spawn(async move {
                                            let downloader = Downloader::new();
                                            downloader.start_download(item, tx).await;
                                        });
                                    }
                                    SearchAction::PlaySaved(title) => {
                                        if let Some(pos) = self.tracks.iter().position(|t| t.title.contains(&title) || title.contains(&t.title)) {
                                            let mut p = self.player.lock().unwrap();
                                            p.load_playlist(self.tracks.clone(), pos);
                                        }
                                    }
                                }
                            }
                        }
                        Tab::Library => {
                            let maybe_action = render_library_view(
                                ui,
                                &self.tracks,
                                &self.playlists,
                                &mut self.active_playlist_id,
                                &mut self.new_playlist_name,
                            );

                            if let Some(action) = maybe_action {
                                match action {
                                    LibraryAction::PlayTrack(idx) => {
                                        let mut p = self.player.lock().unwrap();
                                        p.load_playlist(self.tracks.clone(), idx);
                                    }
                                    LibraryAction::PlayPlaylist(pl) => {
                                        let pl_tracks: Vec<Track> = self.tracks
                                            .iter()
                                            .filter(|t| pl.track_ids.contains(&t.id))
                                            .cloned()
                                            .collect();
                                        let mut p = self.player.lock().unwrap();
                                        p.load_playlist(pl_tracks, 0);
                                    }
                                    LibraryAction::CreatePlaylist(name) => {
                                        let new_pl = Playlist {
                                            id: format!("pl_{}", chrono::Utc::now().timestamp_millis()),
                                            name,
                                            track_ids: Vec::new(),
                                            created_at: chrono::Utc::now().timestamp() as u64,
                                        };
                                        self.playlists.push(new_pl);
                                        let _ = save_playlists(&self.playlists);
                                    }
                                    LibraryAction::DeleteTrack(id) => {
                                        let _ = delete_track(&id);
                                        self.tracks = load_all_tracks();
                                    }
                                    LibraryAction::DeletePlaylist(id) => {
                                        self.playlists.retain(|p| p.id != id);
                                        let _ = save_playlists(&self.playlists);
                                    }
                                }
                            }
                        }
                        Tab::StorageInspector => {
                            render_storage_view(ui);
                        }
                    }
                }
            });
        });
    }
}

fn render_bottom_nav_bar(ui: &mut egui::Ui, active_tab: &mut Tab) {
    egui::Frame::none()
        .fill(COLOR_SURFACE)
        .rounding(Rounding::same(14.0))
        .stroke(Stroke::new(1.0_f32, Color32::from_rgb(35, 45, 65)))
        .inner_margin(6.0)
        .show(ui, |ui| {
            let item_width = (ui.available_width() - 16.0) / 3.0;
            ui.horizontal(|ui| {
                // Tab 1: YouTube Mini View
                let is_search = *active_tab == Tab::Explore;
                let color_search = if is_search { COLOR_ACCENT } else { COLOR_TEXT_MUTED };
                let bg_search = if is_search { Color32::from_rgb(45, 15, 20) } else { Color32::TRANSPARENT };
                if ui.add_sized(
                    [item_width, 42.0],
                    egui::Button::new(RichText::new("▶ YouTube").size(11.5).strong().color(color_search))
                        .fill(bg_search)
                        .rounding(Rounding::same(8.0)),
                ).clicked() {
                    *active_tab = Tab::Explore;
                }

                // Tab 2: My Music / Playlists
                let is_lib = *active_tab == Tab::Library;
                let color_lib = if is_lib { COLOR_CYAN } else { COLOR_TEXT_MUTED };
                let bg_lib = if is_lib { Color32::from_rgb(18, 38, 48) } else { Color32::TRANSPARENT };
                if ui.add_sized(
                    [item_width, 42.0],
                    egui::Button::new(RichText::new("📁 My Music").size(11.5).strong().color(color_lib))
                        .fill(bg_lib)
                        .rounding(Rounding::same(8.0)),
                ).clicked() {
                    *active_tab = Tab::Library;
                }

                // Tab 3: Storage & Privacy
                let is_storage = *active_tab == Tab::StorageInspector;
                let color_storage = if is_storage { COLOR_EMERALD } else { COLOR_TEXT_MUTED };
                let bg_storage = if is_storage { Color32::from_rgb(16, 40, 28) } else { Color32::TRANSPARENT };
                if ui.add_sized(
                    [item_width, 42.0],
                    egui::Button::new(RichText::new("🛡 Storage").size(11.5).strong().color(color_storage))
                        .fill(bg_storage)
                        .rounding(Rounding::same(8.0)),
                ).clicked() {
                    *active_tab = Tab::StorageInspector;
                }
            });
        });
}
