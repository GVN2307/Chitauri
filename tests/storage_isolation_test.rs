use chitauri::storage::{ensure_nomedia_sentinel, sanitize_filename, NOMEDIA_FILENAME};
use std::fs;
use std::path::PathBuf;

#[test]
fn test_nomedia_sentinel_atomic_creation() {
    let test_dir = PathBuf::from("./target/test_sandbox");
    let _ = fs::create_dir_all(&test_dir);

    let nomedia_path = test_dir.join(NOMEDIA_FILENAME);
    if nomedia_path.exists() {
        let _ = fs::remove_file(&nomedia_path);
    }

    assert!(!nomedia_path.exists());
    let created = ensure_nomedia_sentinel(&test_dir).expect("Failed to ensure nomedia");
    assert!(created);
    assert!(nomedia_path.exists());

    // Calling it again should detect that it already exists
    let second_run = ensure_nomedia_sentinel(&test_dir).expect("Failed to check nomedia");
    assert!(!second_run);

    let _ = fs::remove_dir_all(&test_dir);
}

#[test]
fn test_filename_sanitization_defense() {
    let dangerous = "../../etc/passwd:Lofi Chill?*<Beat>.mp3";
    let sanitized = sanitize_filename(dangerous);

    assert!(!sanitized.contains(".."));
    assert!(!sanitized.contains('/'));
    assert!(!sanitized.contains('\\'));
    assert!(!sanitized.contains(':'));
    assert!(!sanitized.contains('*'));
    assert!(!sanitized.contains('?'));
    assert!(!sanitized.contains('<'));
    assert!(!sanitized.contains('>'));
    assert_eq!(sanitized, "____etc_passwd_Lofi Chill___Beat_.mp3");
}
