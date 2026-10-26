#![deny(unsafe_code)]

mod app;
mod downloader;
mod innertube;
mod models;
mod player;
mod storage;
mod ui;

use app::ChitauriApp;
use eframe::egui::Vec2;

fn main() -> eframe::Result<()> {
    // 1. Initialize multi-threaded Tokio asynchronous runtime for background networking & extraction
    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(3)
        .enable_all()
        .build()
        .expect("Failed to initialize Tokio runtime");

    let tokio_handle = rt.handle().clone();

    // 2. Configure mobile-optimized eframe viewport (400px x 800px aspect ratio)
    let native_options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_inner_size(Vec2::new(400.0, 800.0))
            .with_min_inner_size(Vec2::new(360.0, 640.0))
            .with_title("Chitauri Mobile Audio")
            .with_active(true),
        ..Default::default()
    };

    // 3. Launch pure Rust immediate-mode mobile GUI
    eframe::run_native(
        "Chitauri Mobile Audio",
        native_options,
        Box::new(move |cc| {
            // Register image loaders for thumbnails
            egui_extras::install_image_loaders(&cc.egui_ctx);
            Ok(Box::new(ChitauriApp::new(cc, tokio_handle)))
        }),
    )
}
