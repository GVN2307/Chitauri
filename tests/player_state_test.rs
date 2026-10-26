use chitauri::models::{RepeatMode, Track};
use chitauri::player::AudioPlayer;

fn create_sample_tracks(count: usize) -> Vec<Track> {
    (0..count)
        .map(|i| Track {
            id: format!("track_{}", i),
            title: format!("Track Title {}", i),
            artist: format!("Artist {}", i),
            duration_secs: 180 + (i as u32 * 10),
            duration_formatted: "03:00".to_string(),
            file_path: format!("/storage/emulated/0/Music/ChitauriMusic/track_{}.mp3", i),
            thumbnail_url: "https://example.com/thumb.jpg".to_string(),
            created_at: i as u64,
        })
        .collect()
}

#[test]
fn test_player_queue_and_shuffle_invariance() {
    let player_arc = AudioPlayer::new();
    let mut player = player_arc.lock().unwrap();

    let tracks = create_sample_tracks(10);
    // Load playlist starting at track index 3
    player.load_playlist(tracks.clone(), 3);

    assert_eq!(player.current_index, 3);
    assert_eq!(player.current_track().unwrap().id, "track_3");
    assert_eq!(player.playback_queue.len(), 10);
    assert!(!player.is_shuffled);

    // TOGGLE SHUFFLE ON
    player.toggle_shuffle();
    assert!(player.is_shuffled);

    // Critical Invariant: Current playing track MUST remain active and be pinned at index 0
    assert_eq!(player.current_index, 0);
    assert_eq!(player.current_track().unwrap().id, "track_3");
    assert_eq!(player.playback_queue.len(), 10);

    // TOGGLE SHUFFLE OFF (Unshuffle)
    player.toggle_shuffle();
    assert!(!player.is_shuffled);

    // Critical Invariant: Original order must be restored without jumping away from track_3
    assert_eq!(player.playback_queue.len(), 10);
    for (i, t) in player.playback_queue.iter().enumerate() {
        assert_eq!(t.id, format!("track_{}", i));
    }
    assert_eq!(player.current_track().unwrap().id, "track_3");
    assert_eq!(player.current_index, 3);
}

#[test]
fn test_repeat_mode_state_machine() {
    let player_arc = AudioPlayer::new();
    let mut player = player_arc.lock().unwrap();

    assert_eq!(player.repeat_mode, RepeatMode::Off);

    player.cycle_repeat_mode();
    assert_eq!(player.repeat_mode, RepeatMode::All);

    player.cycle_repeat_mode();
    assert_eq!(player.repeat_mode, RepeatMode::One);

    player.cycle_repeat_mode();
    assert_eq!(player.repeat_mode, RepeatMode::Off);
}
