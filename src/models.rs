use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub duration_secs: u32,
    pub duration_formatted: String,
    pub file_path: String,
    pub thumbnail_url: String,
    pub created_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub track_ids: Vec<String>,
    pub created_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub video_id: String,
    pub title: String,
    pub channel_name: String,
    pub duration_text: String,
    pub thumbnail_url: String,
    pub views_text: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DownloadStatus {
    Queued,
    Resolving,
    Downloading(f32),
    Tagging,
    SavedToAppFolder,
    Failed(String),
}

#[derive(Debug, Clone)]
pub struct DownloadItem {
    pub video_id: String,
    pub title: String,
    #[allow(dead_code)]
    pub channel: String,
    pub progress: f32,
    pub status: DownloadStatus,
    pub speed_kbps: f32,
    pub bitrate_kbps: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RepeatMode {
    Off,
    All,
    One,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tab {
    Explore,
    Library,
    StorageInspector,
}

#[derive(Debug, Clone)]
pub enum AppEvent {
    SearchCompleted(Result<Vec<SearchResult>, String>),
    DownloadProgress {
        video_id: String,
        progress: f32,
        speed_kbps: f32,
        status: DownloadStatus,
    },
    DownloadCompleted {
        track: Track,
    },
    DownloadFailed {
        video_id: String,
        error: String,
    },
    #[allow(dead_code)]
    ReloadTracks,
}
