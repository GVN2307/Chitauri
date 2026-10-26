pub mod app;
pub mod downloader;
pub mod innertube;
pub mod models;
pub mod player;
pub mod storage;
pub mod ui;

#[cfg(target_os = "android")]
#[no_mangle]
pub fn android_main(app: android_activity::AndroidApp) {
    std::panic::set_hook(Box::new(|info| {
        let msg = format!("[CHITAURI PANIC] {info}\n");
        eprintln!("{msg}");
        let candidate_paths = [
            "/data/data/com.chitauri.audio/files/chitauri_crash.log",
            "/storage/emulated/0/Android/data/com.chitauri.audio/files/chitauri_crash.log",
        ];
        for p in candidate_paths {
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
                use std::io::Write;
                let _ = writeln!(f, "{msg}");
            }
        }
    }));

    if let Some(path) = app.external_data_path().or_else(|| app.internal_data_path()) {
        storage::set_custom_storage_base(path);
    }

    let native_options = eframe::NativeOptions {
        android_app: Some(app),
        ..Default::default()
    };

    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .or_else(|_| {
            tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
        })
        .expect("Failed to initialize Tokio runtime");

    let tokio_handle = rt.handle().clone();

    let res = eframe::run_native(
        "Chitauri Mobile Audio",
        native_options,
        Box::new(move |cc| {
            Ok(Box::new(app::ChitauriApp::new(cc, tokio_handle)))
        }),
    );

    if let Err(err) = res {
        let msg = format!("[CHITAURI EFRAME ERROR] {err:?}\n");
        eprintln!("{msg}");
        let candidate_paths = [
            "/data/data/com.chitauri.audio/files/chitauri_crash.log",
            "/storage/emulated/0/Android/data/com.chitauri.audio/files/chitauri_crash.log",
        ];
        for p in candidate_paths {
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
                use std::io::Write;
                let _ = writeln!(f, "{msg}");
            }
        }
    }
}
