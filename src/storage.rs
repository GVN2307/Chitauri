use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use crate::models::{Playlist, Track};

pub const APP_FOLDER_NAME: &str = "ChitauriMusic";
pub const NOMEDIA_FILENAME: &str = ".nomedia";
pub const TRACKS_DB_FILE: &str = "tracks_catalog.json";
pub const PLAYLISTS_DB_FILE: &str = "playlists_catalog.json";

static CUSTOM_STORAGE_BASE: OnceLock<PathBuf> = OnceLock::new();

#[allow(dead_code)]
pub fn set_custom_storage_base(path: PathBuf) {
    let _ = CUSTOM_STORAGE_BASE.set(path);
}

/// Resolves the dedicated application audio directory and guarantees the `.nomedia` sentinel.
pub fn get_app_storage_dir() -> PathBuf {
    let base_dir = CUSTOM_STORAGE_BASE
        .get()
        .cloned()
        .or_else(|| {
            #[cfg(target_os = "android")]
            {
                let candidates = [
                    PathBuf::from("/sdcard/Android/data/com.chitauri.audio/files"),
                    PathBuf::from("/data/data/com.chitauri.audio/files"),
                    PathBuf::from("/storage/emulated/0/Music"),
                    PathBuf::from("/sdcard/Music"),
                    PathBuf::from("/storage/emulated/0/Download"),
                ];
                for candidate in candidates {
                    let test_dir = candidate.join(APP_FOLDER_NAME);
                    if fs::create_dir_all(&test_dir).is_ok() {
                        return Some(candidate);
                    }
                }
                None
            }
            #[cfg(not(target_os = "android"))]
            {
                None
            }
        })
        .or_else(|| dirs::audio_dir())
        .or_else(|| dirs::data_local_dir())
        .unwrap_or_else(|| PathBuf::from("."));
    
    let app_dir = base_dir.join(APP_FOLDER_NAME);
    if !app_dir.exists() {
        let _ = fs::create_dir_all(&app_dir);
    }

    // Immediately guarantee .nomedia sentinel exists
    let _ = ensure_nomedia_sentinel(&app_dir);
    app_dir
}

/// Atomically ensures the `.nomedia` marker exists in the designated directory.
/// This prevents mobile OS media scanners (like Android MediaStore) from indexing
/// tracks into third-party media players while allowing File Managers to browse and open them.
pub fn ensure_nomedia_sentinel(dir: &Path) -> io::Result<bool> {
    let nomedia_path = dir.join(NOMEDIA_FILENAME);
    if !nomedia_path.exists() {
        let mut file = File::create(&nomedia_path)?;
        file.write_all(b"")?;
        Ok(true)
    } else {
        Ok(false)
    }
}

/// Sanitizes track titles to create safe filesystem names, preventing directory traversal.
pub fn sanitize_filename(name: &str) -> String {
    let sanitized: String = name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0' => '_',
            _ => c,
        })
        .collect();

    let safe = sanitized.replace("..", "_");
    safe.trim().chars().take(100).collect()
}

/// Storage inspection stats for the Storage Inspector module.
#[derive(Debug, Clone)]
pub struct StorageStats {
    pub folder_path: String,
    pub nomedia_present: bool,
    pub total_tracks: usize,
    pub total_playlists: usize,
    #[allow(dead_code)]
    pub total_size_bytes: u64,
    pub total_size_formatted: String,
}

pub fn inspect_storage() -> StorageStats {
    let dir = get_app_storage_dir();
    let nomedia_present = dir.join(NOMEDIA_FILENAME).exists();
    let tracks = load_all_tracks();
    let playlists = load_all_playlists();

    let mut total_bytes: u64 = 0;
    if let Ok(entries) = fs::read_dir(&dir) {
        for entry in entries.flatten() {
            if let Ok(meta) = entry.metadata() {
                if meta.is_file() {
                    total_bytes += meta.len();
                }
            }
        }
    }

    let size_mb = total_bytes as f64 / (1024.0 * 1024.0);
    let total_size_formatted = if size_mb < 1.0 {
        format!("{:.1} KB", total_bytes as f64 / 1024.0)
    } else {
        format!("{:.2} MB", size_mb)
    };

    StorageStats {
        folder_path: dir.to_string_lossy().to_string(),
        nomedia_present,
        total_tracks: tracks.len(),
        total_playlists: playlists.len(),
        total_size_bytes: total_bytes,
        total_size_formatted,
    }
}

/// Loads all saved track metadata from the app's persistent catalog.
pub fn load_all_tracks() -> Vec<Track> {
    let catalog_path = get_app_storage_dir().join(TRACKS_DB_FILE);
    if let Ok(data) = fs::read_to_string(&catalog_path) {
        if let Ok(tracks) = serde_json::from_str::<Vec<Track>>(&data) {
            // Verify that audio files still exist on disk
            return tracks
                .into_iter()
                .filter(|t| Path::new(&t.file_path).exists())
                .collect();
        }
    }
    Vec::new()
}

/// Saves a track into the persistent catalog.
pub fn save_track(track: &Track) -> io::Result<()> {
    let mut tracks = load_all_tracks();
    // Replace if exists, else append
    if let Some(pos) = tracks.iter().position(|t| t.id == track.id) {
        tracks[pos] = track.clone();
    } else {
        tracks.push(track.clone());
    }

    let catalog_path = get_app_storage_dir().join(TRACKS_DB_FILE);
    let serialized = serde_json::to_string_pretty(&tracks)?;
    fs::write(catalog_path, serialized)?;
    Ok(())
}

/// Deletes a track from the catalog and the physical audio file from disk.
pub fn delete_track(track_id: &str) -> io::Result<()> {
    let mut tracks = load_all_tracks();
    if let Some(pos) = tracks.iter().position(|t| t.id == track_id) {
        let removed = tracks.remove(pos);
        let _ = fs::remove_file(&removed.file_path);
    }
    let catalog_path = get_app_storage_dir().join(TRACKS_DB_FILE);
    let serialized = serde_json::to_string_pretty(&tracks)?;
    fs::write(catalog_path, serialized)?;
    Ok(())
}

/// Loads all custom playlists.
pub fn load_all_playlists() -> Vec<Playlist> {
    let file_path = get_app_storage_dir().join(PLAYLISTS_DB_FILE);
    if let Ok(data) = fs::read_to_string(&file_path) {
        if let Ok(playlists) = serde_json::from_str::<Vec<Playlist>>(&data) {
            return playlists;
        }
    }
    // Return a default playlist if none exists
    vec![Playlist {
        id: "favorites".to_string(),
        name: "Favorites".to_string(),
        track_ids: Vec::new(),
        created_at: 0,
    }]
}

/// Saves all custom playlists.
pub fn save_playlists(playlists: &[Playlist]) -> io::Result<()> {
    let file_path = get_app_storage_dir().join(PLAYLISTS_DB_FILE);
    let serialized = serde_json::to_string_pretty(playlists)?;
    fs::write(file_path, serialized)?;
    Ok(())
}
